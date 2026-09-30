const { app, BrowserWindow, screen, ipcMain, protocol, net } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const { spawn } = require('child_process');
const { pathToFileURL } = require('url');
const hypr = require('./hypr.js');
const platform = require('./platform.js');
const browser = require('./browser.js');

// Odakta olmayan pencerede Chromium zamanlayicilari ve rAF'i kisiyor;
// karakterin yuruyus hizi buna kurban gidiyordu.
app.commandLine.appendSwitch('disable-background-timer-throttling');
app.commandLine.appendSwitch('disable-renderer-backgrounding');
app.commandLine.appendSwitch('disable-backgrounding-occluded-windows');
app.commandLine.appendSwitch('disable-features', 'CalculateNativeWinOcclusion');
const { Client: McpClient } = require('@modelcontextprotocol/sdk/client/index.js');
const { StdioClientTransport } = require('@modelcontextprotocol/sdk/client/stdio.js');

protocol.registerSchemesAsPrivileged([
  {
    scheme: 'kevin',
    privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true },
  },
]);

const WIN_WIDTH = 200;
const WIN_HEIGHT = 330;
const MARGIN = 20;

let characterAnchor = null;
let windowSize = { width: WIN_WIDTH, height: WIN_HEIGHT };

const CONFIG_PATH = path.join(app.getPath('userData'), 'config.json');

const PIPER_DIR = path.join(__dirname, 'bin', 'piper');
const PIPER_BIN = path.join(PIPER_DIR, 'piper');
const PIPER_VOICES_DIR = path.join(__dirname, 'bin', 'piper-voices');

// Ses modeli sabit degil: bin/piper-voices altinda hangi ses kuruluysa o kullanilir.
// (kurulum scripti tr_TR-dfki-medium indiriyor, elde baska bir ses varsa o calisir)
function findPiperVoice() {
  const preferred = process.env.KEVIN_VOICE;
  try {
    const dirs = fs.readdirSync(PIPER_VOICES_DIR, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name)
      .sort();
    const chosen = preferred && dirs.includes(preferred) ? preferred : dirs[0];
    if (!chosen) return null;
    const onnx = fs.readdirSync(path.join(PIPER_VOICES_DIR, chosen)).find((f) => f.endsWith('.onnx'));
    return onnx ? path.join(PIPER_VOICES_DIR, chosen, onnx) : null;
  } catch {
    return null;
  }
}

const PIPER_VOICE = findPiperVoice();
const PIPER_ESPEAK_DATA = path.join(PIPER_DIR, 'espeak-ng-data');

const WHISPER_DIR = path.join(__dirname, 'bin', 'whisper');
const WHISPER_BIN = path.join(WHISPER_DIR, 'whisper-cli');
const WHISPER_MODEL = path.join(__dirname, 'bin', 'whisper-models', 'ggml-small-q5_1.bin');
const WHISPER_THREADS = '10';

function runCommand(cmd, args, { env, input } = {}) {
  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, args, { env: { ...process.env, ...(env || {}) } });
    let stdout = '';
    let stderr = '';
    proc.stdout.on('data', (d) => (stdout += d));
    proc.stderr.on('data', (d) => (stderr += d));
    proc.on('close', (code) => {
      if (code === 0) resolve({ stdout, stderr });
      else reject(new Error(stderr || `exit code ${code}`));
    });
    proc.on('error', reject);
    if (input !== undefined) {
      proc.stdin.write(input);
      proc.stdin.end();
    }
  });
}

const DEFAULT_PERSONA = [
  'Sen {isim}sin. Kullanicinin masaustunde yasayan bir arkadassin, asistan degil.',
  'SADECE {dil} konus.',
  'En fazla 2 cumle cevap ver. Kisa konus.',
  'Sesin var; yazi degil SES olarak duyuluyorsun. Bu yuzden emoji, sembol,',
  'madde isareti, baslik, kod blogu ASLA kullanma. Sesli okunmayacak hicbir sey yazma.',
  'Asistan kaliplari YASAK: "yardimci olabilir miyim", "baska bir sey var mi",',
  '"tabii ki buyurun" gibi seyler deme. Arkadassin, calisan degil.',
  'Icerik-uretici kapanislari YASAK: "bir sonraki videoda gorusuruz" gibi seyler deme.',
  'Ayni cumleyi tekrar etme.',
  'Gerekirse argo kullan, dogal konus.',
  'Kullanicinin dedigi anlamsizsa ya da yarim geldiyse UYDURMA:',
  '"Ne dedin, anlamadim" de. Sesi bazen yanlis duyuyorsun, bunu bil.',
  'Guncel bilgi (hava, haber, fiyat) gerekiyorsa ya araclarla gercek veriyi al',
  'ya da bilmedigini soyle; ASLA tahmin uydurma.',
  'Bir sey yapmaya basladiysan sonucunu mutlaka soyle, "bakiyorum" deyip birakma.',
  'ARACLARIN VAR: dosya okuma/yazma, internette arama, sayfa okuma, ekrana bakma,',
  'uygulama/site acma, klasor listeleme, dosya arama (uzantiyla), ve KENDI TARAYICIN',
  '(browser_open ile acip browser_read ile okursun, browser_click/browser_type ile',
  'tiklayip yazarsin). Giris gerektiren ya da JavaScript ile yuklenen sayfalarda',
  'fetch_page degil tarayiciyi kullan. Kullanici bunlardan birini isterse ARACI CAGIR,',
  'tahmin etme ve "yapamam" deme. Arac sonucunu aldiktan sonra kisa bir cumleyle anlat.',
].join(' ');

function buildPersona(cfg) {
  const isim = cfg.name || 'Kevin';
  const dil = cfg.language || 'Turkce';
  const base = (cfg.persona && cfg.persona.trim()) || DEFAULT_PERSONA;
  return base.replace(/\{isim\}/g, isim).replace(/\{dil\}/g, dil);
}

const PROVIDERS = {
  nvidia: {
    baseURL: 'https://integrate.api.nvidia.com/v1',
    defaultModel: 'meta/llama-3.3-70b-instruct',
  },
  groq: {
    // gpt-oss kendi "harmony" arac kavramini uydurup (repo_browser.open_file gibi)
    // istegi 400'e dusuruyordu; qwen arac cagrisinda uyumlu davraniyor.
    baseURL: 'https://api.groq.com/openai/v1',
    defaultModel: 'qwen/qwen3.8-27b',
  },
  gemini: {
    baseURL: 'https://generativelanguage.googleapis.com/v1beta/openai',
    defaultModel: 'gemini-2.5-flash',
  },
  ollama: {
    baseURL: 'http://127.0.0.1:11434/v1',
    defaultModel: 'qwen3:8b',
    visionModel: 'qwen2.5vl:7b',
    local: true,
  },
};

function isLocal(provider) {
  return Boolean(PROVIDERS[provider] && PROVIDERS[provider].local);
}

function loadConfig() {
  try {
    return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));
  } catch {
    return {};
  }
}

function saveConfig(cfg) {
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2));
}

let win;

// Agent modu: platforma gore uygun MCP sunucusu secilir. Simdilik sadece Linux.
const COMPUTER_USE_BIN = path.join(
  __dirname,
  'node_modules',
  '@agent-sh',
  'computer-use-linux',
  'npm',
  'bin',
  'computer-use-linux.js',
);

// Tani/kurulum amacli araclar (gereksiz token) + salt-gorsel donduren arac disarida.
// get_app_state accessibility-tree/metin de donduruyor (sanitizeToolResult goruntu
// kismini zaten temizliyor), o yuzden acik birakildi - modelin sayfa/uygulama
// icerigini "okuyabilmesi" icin sart.
const EXCLUDED_TOOLS = new Set([
  'doctor',
  'setup_accessibility',
  'setup_window_targeting',
  'screenshot',
]);

let mcpClient = null;
let mcpTools = [];

async function initAgentMCP() {
  if (mcpClient || process.platform !== 'linux') return;
  try {
    const transport = new StdioClientTransport({ command: COMPUTER_USE_BIN, args: ['mcp'] });
    const client = new McpClient({ name: 'kevin', version: '1.0.0' });
    await client.connect(transport);
    const { tools } = await client.listTools();
    mcpClient = client;
    mcpTools = tools.filter((t) => !EXCLUDED_TOOLS.has(t.name));
  } catch (err) {
    console.error('Agent MCP baslatilamadi:', err.message);
  }
}

// computer-use-linux sadece ACIK pencereleri kontrol ediyor, yeni bir uygulama/URL
// baslatamiyor. O bosluk icin kendi basit aracimiz - Linux'un standart xdg-open'i.
const OPEN_URL_TOOL = {
  type: 'function',
  function: {
    name: 'open_url_or_app',
    description:
      'Bir web adresini varsayilan tarayicida veya bir dosyayi varsayilan uygulamada acar. ' +
      'Kullanici "X\'i ac", "tarayicidan X\'e git", "su dosyayi ac" dediginde bunu kullan. ' +
      'Ornekler: "https://discord.com", "/home/user/belge.pdf"',
    parameters: {
      type: 'object',
      properties: {
        target: { type: 'string', description: 'Acilacak URL ya da dosya yolu' },
      },
      required: ['target'],
    },
  },
};

// computer-use-linux'un aciklamalari uzun, agentic dongude her adimda tekrar
// gonderiliyor - kisa versiyonlarla token'dan tasarruf.
const SHORT_TOOL_DESCRIPTIONS = {
  activate_window: 'Bir pencereyi one getirir/odaklar.',
  click: 'Bir elemana ya da koordinata tiklar.',
  drag: 'Bir noktadan digerine surukler.',
  focused_window: 'Su an odaklanmis pencereyi dondurur.',
  list_apps: 'Acik uygulamalari listeler.',
  list_windows: 'Acik pencereleri listeler.',
  move_window: 'Bir pencereyi tasir.',
  perform_action: 'Bir elemanda erisilebilirlik eylemi calistirir.',
  press_key: 'Klavyeden tus/kombinasyon basar.',
  resize_window: 'Bir pencereyi yeniden boyutlandirir.',
  scroll: 'Bir elemani/pencereyi kaydirir.',
  set_value: 'Bir elemanin degerini ayarlar.',
  type_text: 'Klavyeden metin yazar.',
};

const LOOK_TOOL = {
  type: 'function',
  function: {
    name: 'look_at_screen',
    description:
      'Ekrana bakar ve ne gordugunu anlatir. Kullanici "ekranima bak", "bu ne", ' +
      '"ne yaziyor", "sayfada ne var" gibi ekrandaki bir seyi sordugunda kullan.',
    parameters: {
      type: 'object',
      properties: {
        question: { type: 'string', description: 'Ekranda ozellikle neye bakilacagi' },
      },
      required: [],
    },
  },
};

const VISION_ENDPOINT = 'http://127.0.0.1:11434/v1/chat/completions';
const VISION_MODEL = process.env.KEVIN_VISION_MODEL || PROVIDERS.ollama.visionModel;

// Ekran goruntusunu sohbet modeline ham olarak gondermek yerine yerel vision
// modeline sorup METIN aliyoruz: boylece vision'i olmayan modeller de ekrani
// "gorebiliyor" ve token israfi olmuyor.
async function describeImage(imagePath, question) {
  const image = fs.readFileSync(imagePath).toString('base64');
  return describeImageBase64(image, question);
}

async function lookAtScreen(question) {
  const shot = path.join(os.tmpdir(), `kevin-vision-${crypto.randomUUID()}.png`);
  try {
    const captured = await platform.captureScreen(shot, 0.5);
    if (!captured) return 'ekran goruntusu alinamadi';

    const image = fs.readFileSync(shot).toString('base64');
    return describeImageBase64(image, question);
  } finally {
    fs.rmSync(shot, { force: true });
  }
}

async function describeImageBase64(image, question) {
  try {
    const prompt = question && question.trim()
      ? question.trim()
      : 'Bu ekranda ne var? Kisa ve somut anlat.';

    const response = await fetch(VISION_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: VISION_MODEL,
        stream: false,
        messages: [
          {
            role: 'user',
            content: [
              { type: 'text', text: `${prompt}\nTurkce cevapla, en fazla 4 cumle.` },
              { type: 'image_url', image_url: { url: `data:image/png;base64,${image}` } },
            ],
          },
        ],
      }),
    });

    if (!response.ok) {
      const text = await response.text();
      return `vision modeli yanit vermedi (HTTP ${response.status}): ${text.slice(0, 200)}`;
    }

    const data = await response.json();
    return data.choices?.[0]?.message?.content?.trim() || 'goruntuden bir sey okunamadi';
  } catch (err) {
    return `goruntuye bakilamadi: ${err.message}`;
  }
}

// --- Dosya ve internet araclari ---
//
// Kevin'i bir LLM suruyor; yanlislikla gizli dosyalari okumasin ya da sistem
// dosyalarinin uzerine yazmasin diye sinirlar burada.

const HOME = os.homedir();
const READ_DENY = [
  '.ssh', '.gnupg', '.git-credentials', '.netrc', 'shadow', 'id_rsa', 'id_ed25519',
  'kevin-pc-version/config.json', '.aws', '.kube', 'wallet', 'keyring',
];
const MAX_READ_BYTES = 120 * 1024;

function resolveUserPath(input) {
  if (!input) throw new Error('yol verilmedi');
  let target = input.trim();
  if (target.startsWith('~')) target = path.join(HOME, target.slice(1));
  target = path.resolve(target);
  const lower = target.toLowerCase();
  if (READ_DENY.some((deny) => lower.includes(deny))) {
    throw new Error('bu dosya gizli, acmiyorum');
  }
  return target;
}

function assertWritable(target) {
  if (!target.startsWith(HOME + path.sep)) {
    throw new Error('sadece ev dizini altina yazabilirim');
  }
  const lower = target.toLowerCase();
  if (lower.includes('/.config/') && lower.includes('kevin')) {
    throw new Error('kendi ayar dosyama yazmam');
  }
}

const READ_FILE_TOOL = {
  type: 'function',
  function: {
    name: 'read_file',
    description: 'Bir dosyanin icerigini okur. Kullanici bir dosyada ne yazdigini sordugunda kullan.',
    parameters: {
      type: 'object',
      properties: { path: { type: 'string', description: 'Dosya yolu (~ kullanilabilir)' } },
      required: ['path'],
    },
  },
};

async function readFileTool(input) {
  const target = resolveUserPath(input);
  const stat = fs.statSync(target);
  if (stat.isDirectory()) return listDirectoryTool(target);
  const buffer = fs.readFileSync(target);
  const text = buffer.slice(0, MAX_READ_BYTES).toString('utf8');
  const kesildi = buffer.length > MAX_READ_BYTES ? '\n... (dosya uzun, kalani kesildi)' : '';
  return `${target} (${buffer.length} bayt):\n${text}${kesildi}`;
}

const WRITE_FILE_TOOL = {
  type: 'function',
  function: {
    name: 'write_file',
    description:
      'Bir dosyaya yazar ya da var olani degistirir. Sadece ev dizini altinda calisir. ' +
      'Var olan dosyanin once yedegi alinir.',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Dosya yolu (~ kullanilabilir)' },
        content: { type: 'string', description: 'Dosyaya yazilacak tam icerik' },
        append: { type: 'boolean', description: 'true ise sonuna ekler' },
      },
      required: ['path', 'content'],
    },
  },
};

async function writeFileTool(args) {
  const target = resolveUserPath(args.path);
  assertWritable(target);
  fs.mkdirSync(path.dirname(target), { recursive: true });

  if (fs.existsSync(target) && !args.append) {
    fs.copyFileSync(target, `${target}.yedek`);
  }
  if (args.append) fs.appendFileSync(target, args.content, 'utf8');
  else fs.writeFileSync(target, args.content, 'utf8');

  return `${target} yazildi (${Buffer.byteLength(args.content)} bayt)`;
}

const FIND_FILES_TOOL = {
  type: 'function',
  function: {
    name: 'find_files',
    description:
      'Dosya/klasor arar. Kullanici "su dosyayi bul", "pdf\'lerim nerede", ' +
      '"resimleri goster" gibi bir sey sordugunda kullan.',
    parameters: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Aranan isim parcasi (bos birakilabilir)' },
        extension: { type: 'string', description: 'Uzanti: pdf, png, mp4, py ...' },
        directory: { type: 'string', description: 'Nerede aransin (varsayilan: ev dizini)' },
      },
      required: [],
    },
  },
};

async function findFilesTool(args) {
  const root = args.directory ? resolveUserPath(args.directory) : HOME;
  const namePart = (args.name || '').trim();
  const ext = (args.extension || '').trim().replace(/^\./, '');

  const pattern = ext
    ? `*${namePart ? namePart + '*' : ''}.${ext}`
    : namePart
      ? `*${namePart}*`
      : '*';

  const findArgs = [
    root, '-maxdepth', '6',
    '-not', '-path', '*/node_modules/*',
    '-not', '-path', '*/.git/*',
    '-not', '-path', '*/.cache/*',
    '-iname', pattern,
    '-printf', '%TY-%Tm-%Td %10s %p\\n',
  ];

  const { stdout } = await runCommand('find', findArgs).catch((err) => ({ stdout: '', stderr: err.message }));
  const lines = stdout.split('\n').filter(Boolean).slice(0, 25);
  if (!lines.length) return `"${pattern}" ile eslesen bir sey bulamadim (${root})`;
  return `${root} altinda ${lines.length} sonuc:\n` + lines.join('\n');
}

// --- Tarayici araclari (Playwright) ---
// Kevin kendi tarayicisini suruyor: pencere GORUNUR aciliyor, ne yaptigi
// canli izlenebiliyor, oturumlari kalici. Windows/Linux/macOS'ta ayni calisiyor.

function browserProfileDir() {
  return path.join(app.getPath('userData'), 'browser-profile');
}

const BROWSER_OPEN_TOOL = {
  type: 'function',
  function: {
    name: 'browser_open',
    description:
      'Kendi tarayicisinda bir adresi acar ve sayfayi okur. Giris gerektiren ya da ' +
      'JavaScript ile yuklenen sayfalar icin fetch_page yerine BUNU kullan.',
    parameters: {
      type: 'object',
      properties: { url: { type: 'string', description: 'Adres' } },
      required: ['url'],
    },
  },
};

const BROWSER_READ_TOOL = {
  type: 'function',
  function: {
    name: 'browser_read',
    description: 'Tarayicida ACIK olan sayfanin metnini okur.',
    parameters: { type: 'object', properties: {}, required: [] },
  },
};

const BROWSER_CLICK_TOOL = {
  type: 'function',
  function: {
    name: 'browser_click',
    description: 'Tarayicidaki sayfada gorunen bir yaziya/butona tiklar.',
    parameters: {
      type: 'object',
      properties: { text: { type: 'string', description: 'Tiklanacak yazi' } },
      required: ['text'],
    },
  },
};

const BROWSER_TYPE_TOOL = {
  type: 'function',
  function: {
    name: 'browser_type',
    description: 'Tarayicidaki bir kutuya yazar ve Enter\'a basar (arama kutusu, giris formu).',
    parameters: {
      type: 'object',
      properties: {
        value: { type: 'string', description: 'Yazilacak metin' },
        field: { type: 'string', description: 'Kutunun etiketi/placeholder\'i (opsiyonel)' },
      },
      required: ['value'],
    },
  },
};

const BROWSER_LOOK_TOOL = {
  type: 'function',
  function: {
    name: 'browser_look',
    description: 'Tarayicidaki sayfanin GORUNTUSUNE bakar ve ne gordugunu anlatir.',
    parameters: {
      type: 'object',
      properties: { question: { type: 'string', description: 'Sayfada neye bakilacagi' } },
      required: [],
    },
  },
};

async function browserLook(question) {
  const shot = path.join(os.tmpdir(), `kevin-page-${crypto.randomUUID()}.png`);
  try {
    await browser.screenshot(browserProfileDir(), shot);
    return await describeImage(shot, question || 'Bu sayfada ne var?');
  } finally {
    fs.rmSync(shot, { force: true });
  }
}

const WEB_SEARCH_TOOL = {
  type: 'function',
  function: {
    name: 'web_search',
    description:
      'Internette arama yapar. Guncel bilgi (haber, hava, fiyat, "nedir") gerektiginde kullan.',
    parameters: {
      type: 'object',
      properties: { query: { type: 'string', description: 'Arama sorgusu' } },
      required: ['query'],
    },
  },
};

function htmlToText(html) {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#x27;|&#39;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

async function webSearchTool(query) {
  const url = `https://html.duckduckgo.com/html/?q=${encodeURIComponent(query)}`;
  const response = await fetch(url, {
    headers: { 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) Kevin/1.0' },
  });
  if (!response.ok) return `arama basarisiz (HTTP ${response.status})`;

  const html = await response.text();
  const results = [];
  const re = /<a[^>]+class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/g;
  let m;
  while ((m = re.exec(html)) !== null && results.length < 3) {
    const link = decodeURIComponent((m[1].match(/uddg=([^&]+)/) || [, m[1]])[1]);
    results.push(`${results.length + 1}. ${htmlToText(m[2])}\n   ${link}`);
  }
  if (!results.length) {
    const snippet = htmlToText(html).slice(0, 600);
    return snippet ? `Sonuc ayiklanamadi, ham ozet: ${snippet}` : 'sonuc bulunamadi';
  }
  return results.join('\n');
}

const FETCH_PAGE_TOOL = {
  type: 'function',
  function: {
    name: 'fetch_page',
    description: 'Bir web sayfasini acip icerigini METIN olarak okur. Aramadan sonra detay icin kullan.',
    parameters: {
      type: 'object',
      properties: {
        url: { type: 'string', description: 'Tam adres (https://...)' },
        question: { type: 'string', description: 'Sayfada aranan bilgi' },
      },
      required: ['url'],
    },
  },
};

// Ham sayfa metni sohbet modeline gonderilince Groq'un ucretsiz katmani
// (8000 TPM) tek istekte doluyordu. Sayfayi YEREL modele ozetletip kisa metin
// donduruyoruz - look_at_screen'in goruntuyu yerelde tutmasiyla ayni mantik.
async function summarizeLocally(text, question) {
  try {
    const response = await fetch('http://127.0.0.1:11434/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: process.env.KEVIN_SUMMARY_MODEL || 'qwen3:8b',
        stream: false,
        think: false,
        options: { temperature: 0, num_predict: 220 },
        messages: [
          {
            role: 'user',
            content:
              `Asagidaki sayfa metninden su soruya cevap olacak bilgiyi cikar: "${question || 'sayfanin ozeti'}".\n` +
              'En fazla 4 cumle, sade Turkce, yorum katma.\n\n' +
              text.slice(0, 12000),
          },
        ],
      }),
    });
    if (!response.ok) return null;
    const data = await response.json();
    return (data.message?.content || '').trim() || null;
  } catch {
    return null;
  }
}

async function fetchPageTool(url, question) {
  if (!/^https?:\/\//i.test(url)) throw new Error('gecerli bir adres ver');
  const response = await fetch(url, {
    headers: { 'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) Kevin/1.0' },
  });
  if (!response.ok) return `sayfa acilamadi (HTTP ${response.status})`;

  const text = htmlToText(await response.text());
  const summary = await summarizeLocally(text, question);
  if (summary) return `${url} ozeti:\n${summary}`;
  return text.slice(0, 1200) + (text.length > 1200 ? ' ... (kisaltildi)' : '');
}

const LIST_DIR_TOOL = {
  type: 'function',
  function: {
    name: 'list_directory',
    description:
      'Bir klasordeki dosyalari en yeniden en eskiye siralayarak listeler. ' +
      'Kullanici "en son indirdigim", "su klasordeki" gibi bir sey sorunca once bunu kullan. ' +
      'Turkce klasor adlari: Indirilenler=Downloads, Belgeler=Documents, Resimler=Pictures, Masaustu=Desktop, ev klasoru=/home/<kullanici>.',
    parameters: {
      type: 'object',
      properties: {
        path: { type: 'string', description: 'Klasor yolu, ornek: /home/kullanici/Indirilenler' },
      },
      required: ['path'],
    },
  },
};

async function listDirectoryTool(dirPath) {
  const expanded = dirPath.replace(/^~/, os.homedir());
  const entries = fs.readdirSync(expanded, { withFileTypes: true });
  const files = entries
    .filter((e) => e.isFile())
    .map((e) => {
      const full = path.join(expanded, e.name);
      const stat = fs.statSync(full);
      return { name: e.name, path: full, degistirilme: stat.mtime.toISOString() };
    })
    .sort((a, b) => new Date(b.degistirilme) - new Date(a.degistirilme))
    .slice(0, 20);
  return JSON.stringify(files);
}

async function launchViaCompositor(commandLine) {
  if (!hypr.available()) return false;
  try {
    const out = await hypr.send(`/dispatch exec ${commandLine}`);
    return out.trim().startsWith('ok');
  } catch {
    return false;
  }
}

async function openUrlOrApp(target) {
  if (!target || !target.trim()) return 'ne acacagimi soylemedin';
  const value = target.trim();

  const looksLikeUrl = /^[a-z][a-z0-9+.-]*:\/\//i.test(value) || /^[\w.-]+\.[a-z]{2,}(\/|$)/i.test(value);
  const looksLikePath = value.startsWith('/') || value.startsWith('~') || value.startsWith('./');

  if (looksLikeUrl || looksLikePath) {
    const url = looksLikeUrl && !/^[a-z][a-z0-9+.-]*:\/\//i.test(value) ? `https://${value}` : value;
    const expanded = looksLikePath ? resolveUserPath(url) : url;
    if (await launchViaCompositor(`xdg-open "${expanded}"`)) return `acildi: ${expanded}`;
    const result = await platform.openUrl(expanded);
    return result.ok ? `acildi: ${expanded}` : `acilamadi: ${result.error || ''}`;
  }

  const result = await platform.launchApp(value, launchViaCompositor);
  if (result.ok) return `acildi: ${result.label}`;
  return result.installed
    ? `${result.label} kurulu ama baslatilamadi`
    : `"${value}" diye bir uygulama bulamadim`;
}

function mcpToolsAsOpenAI(includeScreenControl) {
  const remoteTools = (includeScreenControl ? mcpTools : []).map((t) => ({
    type: 'function',
    function: {
      name: t.name,
      description: SHORT_TOOL_DESCRIPTIONS[t.name] || t.description || '',
      parameters: t.inputSchema || { type: 'object', properties: {} },
    },
  }));
  return [
    OPEN_URL_TOOL, LIST_DIR_TOOL, LOOK_TOOL, READ_FILE_TOOL, WRITE_FILE_TOOL,
    FIND_FILES_TOOL, WEB_SEARCH_TOOL, FETCH_PAGE_TOOL,
    ...(browser.available()
      ? [BROWSER_OPEN_TOOL, BROWSER_READ_TOOL, BROWSER_CLICK_TOOL, BROWSER_TYPE_TOOL, BROWSER_LOOK_TOOL]
      : []),
    ...remoteTools,
  ];
}

function resizeAnchored(width, height) {
  const { width: screenW, height: screenH } = screen.getPrimaryDisplay().workAreaSize;
  win.setBounds({
    x: screenW - width - MARGIN,
    y: screenH - height - MARGIN,
    width,
    height,
  });
}

// Wayland'de pencere kendi konumunu belirleyemez; Hyprland'e IPC ile soyluyoruz.
// characterAnchor karakterin AYAK noktasi (dunya koordinati), pencere onun etrafina oturur.
let placing = false;
let placeAgain = false;

async function placeWindow() {
  if (!characterAnchor || !hypr.available()) return;
  if (placing) {
    placeAgain = true;
    return;
  }
  placing = true;
  try {
    const x = characterAnchor.x - windowSize.width / 2;
    const y = characterAnchor.y - windowSize.height;
    await hypr.moveTo(x, y);
  } catch {
    // Hyprland yoksa sessizce gec
  } finally {
    placing = false;
    if (placeAgain) {
      placeAgain = false;
      placeWindow();
    }
  }
}

function createWindow() {
  const { width: screenW, height: screenH } = screen.getPrimaryDisplay().workAreaSize;

  win = new BrowserWindow({
    width: WIN_WIDTH,
    height: WIN_HEIGHT,
    x: screenW - WIN_WIDTH - MARGIN,
    y: screenH - WIN_HEIGHT - MARGIN,
    transparent: true,
    frame: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    resizable: false,
    hasShadow: false,
    fullscreenable: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      // Pencere odakta olmadiginda Chromium rAF'i 1 FPS'e kisiyor,
      // karakter de o hizda yuruyor. Kapatiyoruz.
      backgroundThrottling: false,
    },
  });

  win.setAlwaysOnTop(true, 'screen-saver');
  const animArg = process.argv.find((a) => a.startsWith('--anim='));
  const params = new URLSearchParams();
  if (animArg) params.set('anim', animArg.slice(7));
  if (process.argv.includes('--no-vad')) params.set('novad', '1');
  if (process.argv.includes('--no-cem')) params.set('cem', '0');
  if (process.argv.includes('--selftest')) params.set('selftest', '1');
  const voiceArg = process.argv.find((a) => a.startsWith('--voicetest='));
  if (voiceArg) params.set('voicetest', voiceArg.slice(12));
  const ragdollArg = process.argv.find((a) => a.startsWith('--ragdoll='));
  if (ragdollArg) params.set('ragdoll', ragdollArg.slice(10));
  const query = params.toString() ? `?${params}` : '';
  win.loadURL(`kevin://app/renderer/index.html${query}`);

  if (process.env.KEVIN_DEBUG) {
    win.webContents.on('console-message', (_e, _level, message) => console.log('[renderer]', message));
  }

  win.webContents.session.setPermissionRequestHandler((_wc, permission, callback) => {
    callback(permission === 'media');
  });
}

ipcMain.handle('get-config', () => loadConfig());

ipcMain.handle('save-config', (_event, cfg) => {
  saveConfig(cfg);
  return true;
});

ipcMain.on('resize-window', (_event, width, height) => {
  windowSize = { width, height };
  if (characterAnchor && hypr.available()) {
    win.setBounds({ width, height });
    hypr.resizeTo(width, height).then(placeWindow).catch(() => {});
  } else {
    resizeAnchored(width, height);
  }
});

ipcMain.on('set-anchor', (_event, x, y) => {
  characterAnchor = { x, y };
  placeWindow();
});

// CEM animasyon paketi (Fresh Moves gibi). Paket repoda DEGIL: kullanici kendi
// .jem dosyasini bin/cem/ altina koyuyor (telif nedeniyle dagitilmiyor).
ipcMain.handle('cem-pack', () => {
  const packPath = process.env.KEVIN_CEM || path.join(__dirname, 'bin', 'cem', 'player.jem');
  try {
    return fs.readFileSync(packPath, 'utf8');
  } catch {
    return null;
  }
});

ipcMain.handle('cursor-pos', async () => {
  if (!hypr.available()) return null;
  try {
    return await hypr.cursorPos();
  } catch {
    return null;
  }
});

ipcMain.handle('world-info', async () => {
  if (!hypr.available()) return null;
  try {
    return await hypr.world();
  } catch {
    return null;
  }
});

ipcMain.handle('list-models', async (_event, { provider, apiKey }) => {
  const p = PROVIDERS[provider];
  if (!p) return { error: 'Sağlayıcı seçilmedi' };
  if (!apiKey && !p.local) return { error: 'API key gir' };

  try {
    const response = await fetch(`${p.baseURL}/models`, {
      headers: p.local ? {} : { Authorization: `Bearer ${apiKey}` },
    });
    if (!response.ok) {
      const text = await response.text();
      return { error: `HTTP ${response.status}: ${text.slice(0, 150)}` };
    }
    const data = await response.json();
    return { models: (data.data || []).map((m) => m.id).sort() };
  } catch (err) {
    return { error: err.message };
  }
});

const AGENT_TIME_BUDGET_MS = 28000;
const MAX_AGENT_STEPS = 6;
const MAX_TOOL_RESULT_CHARS = 4000;

// Gorsel icerikleri (base64) LLM'e gonderme - sohbet modelleri vision degil,
// bosuna token yakar. Metni de asiri uzunsa kes.
function sanitizeToolResult(content) {
  const sanitized = (content || []).map((item) => {
    if (item.type === 'image') {
      return { type: 'text', text: '[gorsel icerik - metin modeline gonderilmedi]' };
    }
    return item;
  });

  let text = JSON.stringify(sanitized);
  if (text.length > MAX_TOOL_RESULT_CHARS) {
    text = `${text.slice(0, MAX_TOOL_RESULT_CHARS)}... [kesildi]`;
  }
  return text;
}

// Araclarin sema tanimlari her istekte token yakiyor - sadece gercekten
// ekran/pencere/uygulama ile ilgili bir istek varsa gonder.
// Iki kademe: temel araclar (dosya, internet, ekrana bakma) genis tetikleniyor;
// MCP'nin ekran kontrol araclari (tikla, yaz, pencere yonet) ayri ve dar, cunku
// semalari buyuk ve Groq'un ucretsiz katmaninda dakikalik token limitini yiyor.
const BASIC_TOOL_KEYWORDS = [
  'dosya', 'klasor', 'klasör', 'dizin', 'oku', 'okusana', 'yaz', 'kaydet', 'not al',
  'duzenle', 'düzenle', 'olustur', 'oluştur', 'sil', 'listele', 'ac', 'aç', 'baslat', 'başlat',
  'ara', 'arat', 'bul', 'internet', 'site', 'sayfa', 'link', 'adres', 'google',
  'haber', 'hava', 'fiyat', 'kac para', 'kaç para', 'nedir', 'ne demek', 'kim',
  'ne zaman', 'nerede', 'guncel', 'güncel', 'indir', 'goster', 'göster',
  'ekran', 'bak', 'baksana', 'goruyor musun', 'görüyor musun', 'ne yaziyor', 'ne yazıyor',
  'masaustu', 'masaüstü', 'indirilenler', 'belgeler',
  'file', 'read', 'write', 'search', 'open', 'show', 'screen',
  'youtube', 'video', 'izle', 'dinle', 'sarki', 'şarkı', 'muzik', 'müzik',
  'giris yap', 'giriş yap', 'login', 'form', 'doldur', 'gonder', 'gönder',
  'tarayici', 'tarayıcı', 'browser', 'sekmede', 'sitede',
];

const SCREEN_CONTROL_KEYWORDS = [
  'tikla', 'tıkla', 'pencere', 'sekme', 'tusa bas', 'tuşa bas', 'yazi yaz', 'yazı yaz',
  'kaydir', 'kaydır', 'scroll', 'buyut', 'büyüt', 'kucult', 'küçült', 'kapat',
  'one getir', 'öne getir', 'click', 'window', 'type', 'press',
];

function messageNeedsAgent(text) {
  const lower = text.toLowerCase();
  return BASIC_TOOL_KEYWORDS.some((k) => lower.includes(k))
    || SCREEN_CONTROL_KEYWORDS.some((k) => lower.includes(k));
}

function messageNeedsScreenControl(text) {
  const lower = text.toLowerCase();
  return SCREEN_CONTROL_KEYWORDS.some((k) => lower.includes(k));
}

ipcMain.handle('chat', async (_event, history) => {
  const cfg = loadConfig();
  if (!cfg.provider) {
    throw new Error('Saglayici secilmemis');
  }
  if (!cfg.apiKey && !isLocal(cfg.provider)) {
    throw new Error('API key ayarlanmamis');
  }

  const provider = PROVIDERS[cfg.provider];
  let model = cfg.model || provider.defaultModel;
  const language = cfg.language || 'Turkce';
  const name = cfg.name || 'Kevin';

  const messages = [
    {
      role: 'system',
      content: buildPersona(cfg),
    },
    ...history,
  ];

  const lastUserMessage = [...history].reverse().find((m) => m.role === 'user')?.content || '';
  let tools = messageNeedsAgent(lastUserMessage)
    ? mcpToolsAsOpenAI(messageNeedsScreenControl(lastUserMessage))
    : undefined;
  // Ilk adimda arac cagirmaya zorla (model metinle "yapiyorum" diye uydurmasin) -
  // en az bir gercek arac cagrisindan sonra 'auto'ya gecilir, yoksa sonsuz zorlanir.
  let hasCalledTool = false;

  async function callCompletions(forceNoTools) {
    const activeTools = forceNoTools ? undefined : tools;
    const toolChoice = hasCalledTool ? 'auto' : 'required';
    const response = await fetch(`${provider.baseURL}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(provider.local ? {} : { Authorization: `Bearer ${cfg.apiKey}` }),
      },
      body: JSON.stringify({ model, messages, ...(activeTools ? { tools: activeTools, tool_choice: toolChoice } : {}) }),
    });

    if (!response.ok) {
      const text = await response.text();

      // Saglayici modeli kaldirmis olabilir (Groq llama-3.3-70b'yi kaldirdi ve
      // kayitli model 404 veriyordu). Gecersiz modelde varsayilana dusup devam et.
      if (response.status === 404 && text.includes('model_not_found') && model !== provider.defaultModel) {
        console.warn(`[kevin] "${model}" artik yok, varsayilana geciliyor: ${provider.defaultModel}`);
        model = provider.defaultModel;
        saveConfig({ ...loadConfig(), model: '' });
        return callCompletions(forceNoTools);
      }

      const err = new Error(`API hatasi (${response.status}): ${text.slice(0, 200)}`);
      err.rawText = text;
      throw err;
    }

    return response.json();
  }

  const agentDeadline = Date.now() + AGENT_TIME_BUDGET_MS;

  for (let step = 0; step < MAX_AGENT_STEPS; step++) {
    // Sesli kullanimda kullanici bekliyor: zincir uzarsa elindekiyle bitir.
    if (Date.now() > agentDeadline) {
      tools = undefined;
      messages.push({
        role: 'system',
        content: 'Sure doldu. Arac cagirma, elindeki bilgiyle tek cumlede cevap ver.',
      });
    }

    const isLastStep = step === MAX_AGENT_STEPS - 1;
    let data;
    try {
      data = await callCompletions(isLastStep);
    } catch (err) {
      // Model uyumsuz/bilmedigi bir arac cagirmaya calisti - araclar olmadan tekrar dene.
      // `tools` zaten kapali olsa bile olabiliyor (son adimda gpt-oss arac uyduruyordu),
      // o yuzden kosul tools'a bagli degil.
      if (/tool/i.test(err.rawText || '')) {
        tools = undefined;
        messages.push({
          role: 'system',
          content: 'Arac cagirma. Elindeki bilgiyle dogrudan, kisa bir cevap yaz.',
        });
        data = await callCompletions(true);
      } else {
        throw err;
      }
    }
    const choice = data.choices?.[0];
    const replyMsg = choice?.message;

    if (!replyMsg) {
      console.error('Bos cevap - ham data:', JSON.stringify(data).slice(0, 500));
      return '(bos cevap)';
    }

    if (replyMsg.tool_calls?.length) {
      messages.push(replyMsg);
      hasCalledTool = true;

      for (const call of replyMsg.tool_calls) {
        let args = {};
        try {
          args = JSON.parse(call.function.arguments || '{}');
        } catch {
          // bos birak
        }

        win?.webContents.send('agent-activity', { tool: call.function.name, args });
        if (process.env.KEVIN_DEBUG) console.log('[kevin] ARAC:', call.function.name, JSON.stringify(args).slice(0, 120));

        let resultText;
        try {
          if (call.function.name === 'open_url_or_app') {
            resultText = await openUrlOrApp(args.target);
          } else if (call.function.name === 'list_directory') {
            resultText = await listDirectoryTool(args.path);
          } else if (call.function.name === 'look_at_screen') {
            resultText = await lookAtScreen(args.question);
          } else if (call.function.name === 'read_file') {
            resultText = await readFileTool(args.path);
          } else if (call.function.name === 'write_file') {
            resultText = await writeFileTool(args);
          } else if (call.function.name === 'browser_open') {
            resultText = await browser.goto(browserProfileDir(), args.url);
          } else if (call.function.name === 'browser_read') {
            resultText = await browser.readPage(browserProfileDir());
          } else if (call.function.name === 'browser_click') {
            resultText = await browser.clickText(browserProfileDir(), args.text);
          } else if (call.function.name === 'browser_type') {
            resultText = await browser.typeText(browserProfileDir(), args.value, args.field);
          } else if (call.function.name === 'browser_look') {
            resultText = await browserLook(args.question);
          } else if (call.function.name === 'find_files') {
            resultText = await findFilesTool(args);
          } else if (call.function.name === 'web_search') {
            resultText = await webSearchTool(args.query);
          } else if (call.function.name === 'fetch_page') {
            resultText = await fetchPageTool(args.url, args.question || lastUserMessage);
          } else {
            const result = await mcpClient.callTool({ name: call.function.name, arguments: args });
            resultText = JSON.stringify(result.content);
          }
        } catch (err) {
          resultText = `hata: ${err.message}`;
        }

        messages.push({ role: 'tool', tool_call_id: call.id, content: resultText });
      }

      continue;
    }

    win?.webContents.send('agent-activity', null);
    // Sistem promptu emojiyi yasakliyor ama modeller ara sira yine koyuyor;
    // metinden de temizliyoruz (TTS'te zaten temizleniyordu).
    return stripEmoji(replyMsg.content || '').trim() || '(bos cevap)';
  }

  win?.webContents.send('agent-activity', null);
  throw new Error('Agent dongu limitine ulasildi');
});

ipcMain.handle('transcribe', async (_event, arrayBuffer) => {
  const id = crypto.randomUUID();
  const rawPath = path.join(os.tmpdir(), `kevin-rec-${id}.webm`);
  const wavPath = path.join(os.tmpdir(), `kevin-rec-${id}.wav`);
  fs.writeFileSync(rawPath, Buffer.from(arrayBuffer));

  try {
    await runCommand('ffmpeg', ['-y', '-i', rawPath, '-ar', '16000', '-ac', '1', wavPath]);

    const cfg = loadConfig();
    const lang = (cfg.language || 'tr').slice(0, 2);

    const { stdout } = await runCommand(
      WHISPER_BIN,
      ['-m', WHISPER_MODEL, '-f', wavPath, '-l', lang, '-nt', '-np', '-t', WHISPER_THREADS],
      { env: { LD_LIBRARY_PATH: WHISPER_DIR } },
    );

    return stdout.trim();
  } finally {
    fs.rmSync(rawPath, { force: true });
    fs.rmSync(wavPath, { force: true });
  }
});

ipcMain.handle('transcribe-wav', async (_event, arrayBuffer) => {
  const id = crypto.randomUUID();
  const wavPath = path.join(os.tmpdir(), `kevin-vad-${id}.wav`);
  fs.writeFileSync(wavPath, Buffer.from(arrayBuffer));

  try {
    const cfg = loadConfig();
    const lang = (cfg.language || 'tr').slice(0, 2);

    const { stdout } = await runCommand(
      WHISPER_BIN,
      ['-m', WHISPER_MODEL, '-f', wavPath, '-l', lang, '-nt', '-np', '-t', WHISPER_THREADS],
      { env: { LD_LIBRARY_PATH: WHISPER_DIR } },
    );

    return stdout.trim();
  } finally {
    fs.rmSync(wavPath, { force: true });
  }
});

function stripEmoji(text) {
  return text
    .replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{1F1E6}-\u{1F1FF}\u{2B00}-\u{2BFF}️]/gu, '')
    .replace(/\s{2,}/g, ' ')
    .trim();
}

ipcMain.handle('speak', async (_event, text) => {
  const id = crypto.randomUUID();
  const outPath = path.join(os.tmpdir(), `kevin-tts-${id}.wav`);

  try {
    await runCommand(
      PIPER_BIN,
      ['-m', PIPER_VOICE, '--espeak_data', PIPER_ESPEAK_DATA, '-f', outPath],
      { env: { LD_LIBRARY_PATH: PIPER_DIR }, input: stripEmoji(text) },
    );

    const audio = fs.readFileSync(outPath);
    return audio.toString('base64');
  } finally {
    fs.rmSync(outPath, { force: true });
  }
});

const MUSIC_PLAYER_HINTS = [
  'spotify', 'vlc', 'audacious', 'rhythmbox', 'mpd', 'strawberry', 'elisa',
  'amberol', 'tauon', 'clementine', 'lollypop', 'cmus', 'deadbeef', 'quodlibet',
];

ipcMain.handle('music-status', async () => {
  if (!platform.isLinux) return { playing: false };

  try {
    const { stdout } = await runCommand('playerctl', [
      'metadata',
      '--format',
      '{{playerName}}|{{status}}|{{xesam:artist}}|{{xesam:title}}',
    ]);

    const [player = '', status = '', artist = '', title = ''] = stdout.trim().split('|');
    if (status !== 'Playing') return { playing: false };

    const name = player.toLowerCase();
    const isMusicPlayer = MUSIC_PLAYER_HINTS.some((hint) => name.includes(hint));
    const looksLikeSong = artist.trim().length > 0;

    return { playing: isMusicPlayer || looksLikeSong, player, title };
  } catch {
    return { playing: false };
  }
});

app.whenReady().then(async () => {
  protocol.handle('kevin', (request) => {
    const url = new URL(request.url);
    const filePath = path.join(__dirname, url.pathname);
    return net.fetch(pathToFileURL(filePath).toString());
  });

  // Kurallar pencereden ONCE yuklenmeli: windowrule pencere acilirken uygulaniyor.
  if (hypr.available()) {
    try {
      await hypr.loadRules(path.join(app.getPath('userData'), 'hypr-rules.conf'));
    } catch (err) {
      console.error('[kevin] kural dosyasi:', err.message);
    }
  }

  createWindow();
  initAgentMCP();

  // setprop acik pencereye uygulaniyor, o yuzden pencere gorunur olduktan sonra.
  if (hypr.available()) {
    win.once('ready-to-show', () => {
      setTimeout(async () => {
        try {
          const results = await hypr.applyWindowRules();
          // Olcegi 1 olmayan ekranda Electron'un istedigi boyut kuculuyor;
          // gercek boyutu compositor'a IPC ile soyluyoruz.
          await hypr.resizeTo(windowSize.width, windowSize.height);
          if (process.env.KEVIN_DEBUG) console.log('[kevin] pencere ozellikleri:', results.join(' | '));
        } catch (err) {
          console.error('[kevin] setprop:', err.message);
        }
      }, 300);
    });
  }
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
