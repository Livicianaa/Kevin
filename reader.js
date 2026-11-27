const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const fflate = require('fflate');

const IMAGE_EXTS = new Set(['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp']);
const CHUNK_TARGET = 150;
const CHUNKS_PER_PAGE = 20;

let pageRenderer = null;

function setPageRenderer(fn) {
  pageRenderer = fn;
}

function isImageFile(filename) {
  return IMAGE_EXTS.has(path.extname(filename).toLowerCase());
}

function naturalSort(list, keyFn = (x) => x) {
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' });
  return list.sort((a, b) => collator.compare(keyFn(a), keyFn(b)));
}

function cleanMarkdown(text) {
  return text
    .replace(/\r\n/g, '\n')
    .replace(/```[\s\S]*?```/g, '')
    .replace(/!\[.*?\]\(.*?\)/g, '')
    .replace(/^\s*\|.*?\|\s*$/gm, '')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/^#{1,6}\s+/gm, '')
    .replace(/(\*\*|__)(.*?)\1/g, '$2')
    .replace(/(\*|_)(.*?)\1/g, '$2')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/^>\s+/gm, '')
    .replace(/^[-*_]{3,}\s*$/gm, '')
    .replace(/<[^>]+>/g, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function stripHtml(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|h[1-6]|li|tr)>/gi, '\n\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\r\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function chunkText(text, targetLen = CHUNK_TARGET) {
  if (!text || !text.trim()) return [];
  const paragraphs = text.split(/\n\n+/);
  const units = [];
  for (const para of paragraphs) {
    const trimmed = para.trim();
    if (!trimmed) continue;
    const sentences = trimmed.split(/(?<=[.?!])\s+/);
    for (const s of sentences) {
      if (s.trim()) units.push(s.trim());
    }
  }

  const chunks = [];
  let cur = '';
  for (let unit of units) {
    if (unit.length > targetLen) {
      if (cur) {
        chunks.push(cur.trim());
        cur = '';
      }
      while (unit.length > targetLen) {
        let cut = unit.lastIndexOf(' ', targetLen);
        if (cut <= 0) cut = targetLen;
        chunks.push(unit.slice(0, cut).trim());
        unit = unit.slice(cut).trim();
      }
      cur = unit;
      continue;
    }

    if ((cur + ' ' + unit).length > targetLen && cur.length >= targetLen * 0.5) {
      chunks.push(cur.trim());
      cur = unit;
    } else {
      cur = cur ? cur + ' ' + unit : unit;
    }
  }
  if (cur.trim()) chunks.push(cur.trim());
  return chunks;
}

function groupChunksIntoPages(chunks) {
  if (!chunks || chunks.length === 0) {
    return [{ page: 0, chunks: [''], text: '' }];
  }
  const pages = [];
  for (let i = 0; i < chunks.length; i += CHUNKS_PER_PAGE) {
    const pageChunks = chunks.slice(i, i + CHUNKS_PER_PAGE);
    pages.push({
      page: pages.length,
      chunks: pageChunks,
      text: pageChunks.join('\n\n'),
    });
  }
  return pages;
}

function parseEpub(filePath) {
  const fileBuf = fs.readFileSync(filePath);
  const unzipped = fflate.unzipSync(new Uint8Array(fileBuf));

  const containerEntry = unzipped['META-INF/container.xml'];
  if (!containerEntry) throw new Error('Gecersiz EPUB: container.xml yok');
  const containerXml = fflate.strFromU8(containerEntry);
  const rootMatch = containerXml.match(/full-path=["']([^"']+)["']/i);
  const opfPath = rootMatch ? rootMatch[1] : 'OEBPS/content.opf';
  const opfEntry = unzipped[opfPath];
  if (!opfEntry) throw new Error(`Gecersiz EPUB: ${opfPath} bulunamadi`);

  const opfContent = fflate.strFromU8(opfEntry);
  const opfDir = path.posix.dirname(opfPath);

  const titleMatch = opfContent.match(/<dc:title[^>]*>([\s\S]*?)<\/dc:title>/i);
  const title = titleMatch ? titleMatch[1].trim() : path.basename(filePath, path.extname(filePath));

  const manifest = new Map();
  const itemRegex = /<item\s+[^>]*?>/gi;
  let m;
  while ((m = itemRegex.exec(opfContent)) !== null) {
    const tag = m[0];
    const idM = tag.match(/id=["']([^"']+)["']/i);
    const hrefM = tag.match(/href=["']([^"']+)["']/i);
    if (idM && hrefM) {
      manifest.set(idM[1], decodeURIComponent(hrefM[1].split('#')[0]));
    }
  }

  const spine = [];
  const itemrefRegex = /<itemref\s+[^>]*?idref=["']([^"']+)["']/gi;
  while ((m = itemrefRegex.exec(opfContent)) !== null) {
    spine.push(m[1]);
  }

  const textSections = [];
  for (const idref of spine) {
    const href = manifest.get(idref);
    if (!href) continue;
    const itemPath = opfDir === '.' ? href : path.posix.join(opfDir, href);
    const docEntry = unzipped[itemPath] || unzipped[decodeURIComponent(itemPath)];
    if (docEntry) {
      const html = fflate.strFromU8(docEntry);
      const text = stripHtml(html);
      if (text) textSections.push(text);
    }
  }

  const fullText = textSections.join('\n\n');
  const chunks = chunkText(cleanMarkdown(fullText));
  const pages = groupChunksIntoPages(chunks);
  return { title, pages };
}

function extractOneFromZip(zipPath, targetName) {
  return new Promise((resolve, reject) => {
    const uz = new fflate.Unzip();
    uz.register(fflate.UnzipInflate);
    let matched = false;
    uz.onfile = (file) => {
      if (file.name === targetName) {
        matched = true;
        const chunks = [];
        file.ondata = (err, chunk, final) => {
          if (err) return reject(err);
          if (chunk) chunks.push(chunk);
          if (final) {
            resolve(Buffer.concat(chunks.map((c) => Buffer.from(c))));
          }
        };
        file.start();
      }
    };
    const s = fs.createReadStream(zipPath);
    s.on('data', (c) => uz.push(new Uint8Array(c)));
    s.on('end', () => {
      uz.push(new Uint8Array(0), true);
      if (!matched) reject(new Error(`Dosya bulunamadi: ${targetName}`));
    });
    s.on('error', reject);
  });
}

async function listZipImageEntries(zipPath) {
  return new Promise((resolve, reject) => {
    const uz = new fflate.Unzip();
    const entries = [];
    uz.onfile = (file) => {
      const name = file.name;
      if (!name.endsWith('/') && !name.startsWith('__MACOSX') && !path.basename(name).startsWith('.')) {
        if (isImageFile(name)) {
          entries.push(name);
        }
      }
    };
    const s = fs.createReadStream(zipPath);
    s.on('data', (c) => uz.push(new Uint8Array(c)));
    s.on('end', () => {
      uz.push(new Uint8Array(0), true);
      resolve(naturalSort(entries));
    });
    s.on('error', reject);
  });
}

async function openBook(inputPaths) {
  const paths = Array.isArray(inputPaths) ? inputPaths : [inputPaths];
  if (!paths.length) throw new Error('Dosya belirtilmedi');

  const firstPath = path.resolve(paths[0]);
  const stat = fs.statSync(firstPath);
  const id = crypto.createHash('sha1').update(`${firstPath}:${stat.size}:${stat.mtimeMs}`).digest('hex');

  if (stat.isDirectory()) {
    const files = fs.readdirSync(firstPath);
    const imageFiles = naturalSort(files.filter(isImageFile));
    const fullPaths = imageFiles.map((f) => path.join(firstPath, f));
    const title = path.basename(firstPath);
    const pages = fullPaths.map((p, i) => ({ page: i, path: p }));

    const loadPage = async (i) => {
      const p = pages[i]?.path;
      if (!p) throw new Error(`Gecersiz sayfa: ${i}`);
      if (pageRenderer) return pageRenderer({ type: 'image', path: p });
      const buf = fs.readFileSync(p);
      return buf.toString('base64');
    };

    pages.forEach((pg, i) => { pg.loadPage = () => loadPage(i); });
    return { id, title, kind: 'images', pages, loadPage };
  }

  if (paths.length > 1 && paths.every((p) => isImageFile(p))) {
    const sorted = naturalSort(paths.map((p) => path.resolve(p)));
    const title = path.basename(sorted[0], path.extname(sorted[0]));
    const pages = sorted.map((p, i) => ({ page: i, path: p }));

    const loadPage = async (i) => {
      const p = pages[i]?.path;
      if (!p) throw new Error(`Gecersiz sayfa: ${i}`);
      if (pageRenderer) return pageRenderer({ type: 'image', path: p });
      const buf = fs.readFileSync(p);
      return buf.toString('base64');
    };

    pages.forEach((pg, i) => { pg.loadPage = () => loadPage(i); });
    return { id, title, kind: 'images', pages, loadPage };
  }

  const ext = path.extname(firstPath).toLowerCase();
  const defaultTitle = path.basename(firstPath, ext);

  if (ext === '.cbz' || ext === '.zip') {
    const entries = await listZipImageEntries(firstPath);
    const pages = entries.map((name, i) => ({ page: i, name }));

    const loadPage = async (i) => {
      const name = pages[i]?.name;
      if (!name) throw new Error(`Gecersiz sayfa: ${i}`);
      const buf = await extractOneFromZip(firstPath, name);
      if (pageRenderer) return pageRenderer({ type: 'image', buffer: buf, name });
      return buf.toString('base64');
    };

    pages.forEach((pg, i) => { pg.loadPage = () => loadPage(i); });
    return { id, title: defaultTitle, kind: 'images', pages, loadPage };
  }

  if (ext === '.txt' || ext === '.md' || ext === '.markdown') {
    const raw = fs.readFileSync(firstPath, 'utf8');
    const cleaned = cleanMarkdown(raw);
    const chunks = chunkText(cleaned);
    const pages = groupChunksIntoPages(chunks);
    const loadPage = async (i) => pages[i]?.text || '';
    pages.forEach((pg, i) => { pg.loadPage = () => loadPage(i); });
    return { id, title: defaultTitle, kind: 'text', pages, loadPage };
  }

  if (ext === '.epub') {
    const { title, pages } = parseEpub(firstPath);
    const loadPage = async (i) => pages[i]?.text || '';
    pages.forEach((pg, i) => { pg.loadPage = () => loadPage(i); });
    return { id, title, kind: 'text', pages, loadPage };
  }

  if (ext === '.pdf') {
    const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
    const fileBuf = fs.readFileSync(firstPath);
    const data = new Uint8Array(fileBuf);
    const doc = await pdfjs.getDocument({ data, isEvalSupported: false, useSystemFonts: true }).promise;
    const numPages = doc.numPages;

    let totalChars = 0;
    const pageTexts = [];
    for (let i = 1; i <= numPages; i++) {
      const page = await doc.getPage(i);
      const textContent = await page.getTextContent();
      const text = textContent.items.map((it) => it.str).join(' ').trim();
      totalChars += text.length;
      pageTexts.push(text);
    }

    const avgChars = numPages > 0 ? totalChars / numPages : 0;
    if (avgChars < 40) {
      const pages = Array.from({ length: numPages }, (_, i) => ({ page: i }));
      const loadPage = async (i) => {
        if (i < 0 || i >= numPages) throw new Error(`Gecersiz sayfa: ${i}`);
        if (pageRenderer) return pageRenderer({ type: 'pdf', path: firstPath, pageNum: i + 1, buffer: fileBuf });
        return '';
      };
      pages.forEach((pg, i) => { pg.loadPage = () => loadPage(i); });
      return { id, title: defaultTitle, kind: 'images', pages, loadPage };
    }

    const fullText = pageTexts.join('\n\n');
    const chunks = chunkText(cleanMarkdown(fullText));
    const pages = groupChunksIntoPages(chunks);
    const loadPage = async (i) => pages[i]?.text || '';
    pages.forEach((pg, i) => { pg.loadPage = () => loadPage(i); });
    return { id, title: defaultTitle, kind: 'text', pages, loadPage };
  }

  if (isImageFile(firstPath)) {
    const pages = [{ page: 0, path: firstPath }];
    const loadPage = async () => {
      if (pageRenderer) return pageRenderer({ type: 'image', path: firstPath });
      return fs.readFileSync(firstPath).toString('base64');
    };
    pages[0].loadPage = () => loadPage(0);
    return { id, title: defaultTitle, kind: 'images', pages, loadPage };
  }

  throw new Error(`Desteklenmeyen dosya formati: ${ext}`);
}

module.exports = {
  openBook,
  setPageRenderer,
  cleanMarkdown,
  chunkText,
  groupChunksIntoPages,
  naturalSort,
};
