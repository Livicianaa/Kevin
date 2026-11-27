import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const fflate = require('fflate');
const reader = require('../reader.js');

const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'kevin-reader-test-'));

try {
  // 1. Markdown testi
  const mdPath = path.join(tempDir, 'notlar.md');
  const mdContent = `# Kitap Basligi

Bu bir **kalin yazi** ve *italik yazi* ve \`kod parcasi\`.
Burada [Baglanti Metni](https://example.com) korunmali.
![Resim Aciklamasi](resim.png)

| Tablo 1 | Tablo 2 |
|---|---|
| Hucre 1 | Hucre 2 |

\`\`\`javascript
function gizli() {
  return "bu kod blogu tamamen atlanmali";
}
\`\`\`

Ikinci paragraf metni burada yer aliyor.`;

  fs.writeFileSync(mdPath, mdContent, 'utf8');

  const mdBook = await reader.openBook([mdPath]);
  assert.equal(mdBook.kind, 'text', 'MD kind text olmali');
  assert.equal(mdBook.title, 'notlar', 'MD baslik dosya adi olmali');
  assert(mdBook.pages.length >= 1, 'En az 1 sayfa olmali');

  const fullText = mdBook.pages.map((p) => p.chunks.join(' ')).join(' ');
  assert(fullText.includes('Kitap Basligi'), 'Baslik korunmali');
  assert(fullText.includes('kalin yazi'), 'Kalin yazi temizlenerek korunmali');
  assert(fullText.includes('italik yazi'), 'Italik yazi temizlenerek korunmali');
  assert(fullText.includes('kod parcasi'), 'Satir ici kod korunmali');
  assert(fullText.includes('Baglanti Metni'), 'Baglanti metni korunmali');
  assert(!fullText.includes('https://example.com'), 'Link url temizlenmeli');
  assert(!fullText.includes('Resim Aciklamasi'), 'Resim etiketi atilmali');
  assert(!fullText.includes('Tablo 1'), 'Tablo satirlari atilmali');
  assert(!fullText.includes('bu kod blogu tamamen atlanmali'), 'Kod bloklari atlanmali');
  console.log('READER TEST: Markdown temizligi ve openBook basarili.');

  // 2. TXT testi (~1500 karakterlik parcalama ve ~6 parca bir sayfa)
  const txtPath = path.join(tempDir, 'metin.txt');
  const paragraph = 'Kevin masaustunde yasayan yapay zeka karakteridir. Her gun farkli maceralar yasar. ';
  const longText = paragraph.repeat(25); // ~2000 karakter
  fs.writeFileSync(txtPath, longText, 'utf8');

  const txtBook = await reader.openBook([txtPath]);
  assert.equal(txtBook.kind, 'text', 'TXT kind text olmali');
  assert.equal(txtBook.title, 'metin', 'TXT baslik dosya adi olmali');
  assert(txtBook.pages[0].chunks.length > 1, 'Parcalara ayrilmis olmali');
  for (const chunk of txtBook.pages[0].chunks) {
    assert(chunk.length <= 600, `Parca boyutu hedefe yakin olmali (${chunk.length})`);
  }
  console.log('READER TEST: TXT parcalama ve sayfa gruplamasi basarili.');

  // 3. CBZ dogal siralama testi (10.png, 2.png, 1.png)
  const cbzPath = path.join(tempDir, 'manga.cbz');
  const png1x1 = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=', 'base64');
  const cbzData = fflate.zipSync({
    '10.png': new Uint8Array(png1x1),
    '2.png': new Uint8Array(png1x1),
    '1.png': new Uint8Array(png1x1),
  });
  fs.writeFileSync(cbzPath, cbzData);

  const cbzBook = await reader.openBook([cbzPath]);
  assert.equal(cbzBook.kind, 'images', 'CBZ kind images olmali');
  assert.equal(cbzBook.title, 'manga', 'CBZ baslik dosya adi olmali');
  assert.equal(cbzBook.pages.length, 3, 'Sayfa sayisi 3 olmali');

  const names = cbzBook.pages.map((p) => p.name);
  assert.deepEqual(names, ['1.png', '2.png', '10.png'], 'Dogal sayisal siralama saglanmali (2.png 10.png den once)');

  const page0Data = await cbzBook.loadPage(0);
  assert(typeof page0Data === 'string' && page0Data.length > 0, 'loadPage tembel veri donmeli');
  console.log('READER TEST: CBZ dogal siralama ve sayfa yukleme basarili.');

} finally {
  try {
    fs.rmSync(tempDir, { recursive: true, force: true });
  } catch {}
}
