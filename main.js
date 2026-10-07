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
const langs = require('./langs.js');
const { BeatTracker } = require('./beat.js');
const { createAkil } = require('./akil.js');

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

// --brain: pencere gorunmez, sadece beyin (ses, sohbet, araclar). Govde Godot
// (body/), olaylari yerel bir TCP baglantisiyla ona gonderiyoruz.
const BRAIN_MODE = process.argv.includes('--brain');
const BODY_PORT = Number(process.env.KEVIN_BODY_PORT || 47630);
const bodyClients = new Set();
let lastBodyState = null;

function bodySend(event) {
  if (event.type === 'state') lastBodyState = event;
  const line = JSON.stringify(event) + '\n';
  for (const sock of bodyClients) sock.write(line);
}

function startBodyBridge() {
  const tcp = require('node:net');
  let everConnected = false;
  let quitTimer = null;
  const server = tcp.createServer((sock) => {
    everConnected = true;
    clearTimeout(quitTimer);
    bodyClients.add(sock);
    sock.setEncoding('utf8');
    if (lastBodyState) sock.write(JSON.stringify(lastBodyState) + '\n');
    let buffer = '';
    sock.on('data', (chunk) => {
      buffer += chunk;
      let nl;
      while ((nl = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, nl).trim();
        buffer = buffer.slice(nl + 1);
        if (!line) continue;
        try {
          const msg = JSON.parse(line);
          if (win) win.webContents.send('body-command', msg);
        } catch {}
      }
    });
    const drop = () => {
      bodyClients.delete(sock);
      // Govde kapandiysa beyin de kapansin (sahipsiz kalmasin)
      if (everConnected && bodyClients.size === 0) {
        clearTimeout(quitTimer);
        quitTimer = setTimeout(() => app.quit(), 5000);
      }
    };
    sock.on('close', drop);
    sock.on('error', drop);
  });
  server.on('error', (err) => console.error('[kevin] govde koprusu:', err.message));
  server.listen(BODY_PORT, '127.0.0.1');
}

ipcMain.on('body-event', (_event, ev) => bodySend(ev));

// Sohbet gecmisi: yeniden baslayinca son konusmayi hatirlasin, govdenin
// menusu de gostersin. Modele sadece son birkac mesaj gidiyor.
const HISTORY_PATH = path.join(app.getPath('userData'), 'history.json');
const HISTORY_KEEP = 300;

function loadHistory() {
  try {
    const data = JSON.parse(fs.readFileSync(HISTORY_PATH, 'utf-8'));
    return Array.isArray(data) ? data : [];
  } catch {
    return [];
  }
}

ipcMain.handle('history-load', () => loadHistory());
ipcMain.on('history-add', (_event, entry) => {
  const all = loadHistory();
  all.push({ ...entry, at: new Date().toISOString() });
  try {
    fs.writeFileSync(HISTORY_PATH, JSON.stringify(all.slice(-HISTORY_KEEP), null, 1));
  } catch (err) {
    console.error('[kevin] gecmis yazilamadi:', err.message);
  }
});

// Windows'ta programlar .exe
const EXE = process.platform === 'win32' ? '.exe' : '';
const PIPER_DIR = path.join(__dirname, 'bin', 'piper');
const PIPER_BIN = path.join(PIPER_DIR, `piper${EXE}`);
const PIPER_VOICES_DIR = path.join(__dirname, 'bin', 'piper-voices');
// Paketlenmis surumde uygulama klasoru salt okunur (AppImage): yeni dilin sesi
// kullanicinin klasorune iner, pakete gomulu sesler de kullanilir
const VOICES_USER_DIR = app.isPackaged ? path.join(app.getPath('userData'), 'piper-voices') : PIPER_VOICES_DIR;

// Paketlenmis Windows surumu: Kevin.exe once govdeyi (Godot) baslatip kapanir,
// govde beyni yine bu programla --brain diye acar. Govde kullanicinin
// klasorune kopyalanir (Program Files gibi yazilamayan yerde de calissin).
// Linux AppImage'da bu isi AppRun yapiyor.
const LAUNCHER = app.isPackaged && !BRAIN_MODE && process.platform === 'win32';

function launchBody() {
  const appDir = app.getAppPath();
  const src = path.join(appDir, 'body');
  const dst = path.join(app.getPath('userData'), 'body');
  const stamp = path.join(dst, '.kevin-surum');
  const version = `${app.getVersion()}-${fs.statSync(path.join(src, 'project.godot')).mtimeMs}`;
  if (!fs.existsSync(stamp) || fs.readFileSync(stamp, 'utf8') !== version) {
    fs.rmSync(dst, { recursive: true, force: true });
    fs.cpSync(src, dst, { recursive: true });
    fs.writeFileSync(stamp, version);
  }
  const godot = path.join(path.dirname(process.execPath), 'godot', `godot${EXE}`);
  spawn(godot, ['--path', dst], {
    detached: true,
    stdio: 'ignore',
    env: { ...process.env, KEVIN_ROOT: appDir, KEVIN_ELECTRON: process.execPath },
  }).unref();
}

if (LAUNCHER) {
  try {
    launchBody();
  } catch (err) {
    console.error('[kevin] govde baslatilamadi:', err.message);
  }
  setTimeout(() => app.exit(0), 300);
}

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

// Ortam degiskeniyle zorlanan ses; yoksa dile gore (langs.js)
const PIPER_VOICE = process.env.KEVIN_VOICE ? findPiperVoice() : null;
const PIPER_ESPEAK_DATA = path.join(PIPER_DIR, 'espeak-ng-data');

// Ekran kartli derleme (scripts/setup-whisper-gpu.sh) varsa ses tanima GPU'da
// daha dogru turbo modelle; yoksa CPU'da small (turbo CPU'da ~5 kat yavas)
const WHISPER_GPU_DIR = path.join(__dirname, 'bin', 'whisper-gpu');
const WHISPER_TURBO = path.join(__dirname, 'bin', 'whisper-models', 'ggml-large-v3-turbo-q5_0.bin');
const WHISPER_ON_GPU = fs.existsSync(path.join(WHISPER_GPU_DIR, `whisper-cli${EXE}`)) && fs.existsSync(WHISPER_TURBO);
const WHISPER_DIR = WHISPER_ON_GPU ? WHISPER_GPU_DIR : path.join(__dirname, 'bin', 'whisper');
const WHISPER_BIN = path.join(WHISPER_DIR, `whisper-cli${EXE}`);
const WHISPER_MODEL = WHISPER_ON_GPU ? WHISPER_TURBO : path.join(__dirname, 'bin', 'whisper-models', 'ggml-small-q5_1.bin');
const WHISPER_CPU_DIR = path.join(__dirname, 'bin', 'whisper');
const WHISPER_CPU_MODEL = path.join(__dirname, 'bin', 'whisper-models', 'ggml-small-q5_1.bin');
// Ekran karti doluysa (oyun, yerel model) GPU whisper bellek ayiramiyor;
// o zaman CPU'ya duser ve bir sure GPU'yu denemez
let whisperGpuSkipUntil = 0;

// Whisper sessizlikte/gurultude egitim verisindeki video sonu yazilarini
// uyduruyor ("Altyazi M.K.", "Abone olmayi unutmayin"); bunlar konusma degil
const WHISPER_HALLUCINATIONS = [
  /^altyaz[ıi](\s+[\p{L}.]+){0,3}[.!]?$/u, /abone ol/u, /izlediğiniz için teşekkür/u, /bir sonraki videoda/u,
  /^thanks? for watching/u, /^subtitles? (by|from)/u, /^\[?(müzik|music|alkış|applause)\]?\.?$/u,
  /^[♪♫\s.*-]+$/u,
];

function cleanTranscript(text) {
  const t = text.trim();
  const low = t.toLocaleLowerCase('tr');
  return WHISPER_HALLUCINATIONS.some((re) => re.test(low)) ? '' : t;
}

async function runWhisper(wavPath, cfg) {
  const args = (model) => ['-m', model, '-f', wavPath, '-l', langs.langCode(cfg), '-nt', '-np', '-t', WHISPER_THREADS, '--prompt', whisperPrompt(cfg)];
  if (WHISPER_ON_GPU && Date.now() >= whisperGpuSkipUntil) {
    try {
      const { stdout } = await runCommand(WHISPER_BIN, args(WHISPER_MODEL), { env: { LD_LIBRARY_PATH: WHISPER_DIR } });
      return cleanTranscript(stdout);
    } catch (err) {
      whisperGpuSkipUntil = Date.now() + 2 * 60 * 1000;
      console.warn('[kevin] GPU ses tanima basarisiz, CPU\'ya geciliyor:', String(err.message).split('\n')[0]);
    }
  }
  const { stdout } = await runCommand(path.join(WHISPER_CPU_DIR, `whisper-cli${EXE}`), args(WHISPER_CPU_MODEL), { env: { LD_LIBRARY_PATH: WHISPER_CPU_DIR } });
  return cleanTranscript(stdout);
}
// Islemci sayisina gore (her acilista): sabit 10 is parcacigi az cekirdekli
// makinede butun sistemi yavaslatir
const WHISPER_THREADS = String(Math.max(2, Math.min(10, os.cpus().length - 2)));

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

const akil = createAkil({ userData: app.getPath('userData'), runCommand });

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
  'LEB DEMEDEN LEBLEBIYI ANLA: kullanici ne istedigini tam soylemese de niyetini tahmin et ve',
  'sormadan hemen yap, sonra ne yaptigini kisaca soyle. Ornekler: "buton tasarimi bul" ya da',
  '"menu icin renk ornekleri" -> open_url_or_app ile https://www.pinterest.com/search/pins/?q=...',
  'aramasini ac. "su videoyu ac" -> YouTube aramasi ac. Bir sey ogrenmek istiyorsa ara ve cevapla.',
  'Ses yaziya cevrilirken kelimeler bozulabilir (site adlari, "nokta com", "nokta mi" gibi):',
  'en mantikli adresi tahmin edip ac, emin degilsen arama sayfasi ac. Kullanicinin onceki',
  'cumlelerinden baglami kullan; ayni seyi tekrar sordurtma.',
].join(' ');

function buildPersona(cfg) {
  const isim = cfg.name || 'Kevin';
  const dil = langs.lang(cfg).prompt;
  const base = (cfg.persona && cfg.persona.trim()) || DEFAULT_PERSONA;
  const typing = cfg.liveTyping !== false
    ? '\nKOD/YAZI: Kullanici kod, betik ya da uzun bir metin yazmani isterse onu SESLI OKUMA. write_file ile '
      + '~/Kevin/ altina uygun uzantili bir dosyaya yaz (ekranda harf harf yazilarak gosterilecek), sonra tek cumleyle ne yazdigini soyle.'
    : '';
  return `${base.replace(/\{isim\}/g, isim).replace(/\{dil\}/g, dil)}\n${akil.personaBlock()}${typing}\nCevaplarini SADECE ${dil} dilinde ver (etiketler haric).`;
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
    // gemini-2.5-flash kaldirildi (404). *-latest takma adlari hep guncel
    // modele gidiyor; yogunlukta (503) lite'a geciliyor.
    baseURL: 'https://generativelanguage.googleapis.com/v1beta/openai',
    defaultModel: 'gemini-flash-latest',
    fallbackModel: 'gemini-flash-lite-latest',
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

// Ses tanimaya ismi onceden soyluyoruz: yoksa "Kevin"i "Ken", "Kemim", "Kevim"
// diye yaziyor ve uyanma kelimesi tutmuyordu.
function whisperPrompt(cfg) {
  const name = cfg.name || 'Kevin';
  const nicks = (cfg.nicknames || []).join(', ');
  // Sik gecen komut kelimeleri: ses tanima bunlari dogru yazsin ("yan ekanda",
  // "Firafoks" gibi yanlislar)
  const tail = langs.langCode(cfg) === 'tr'
    ? ` ${name}, bana yardım eder misin? Yan ekranda Firefox'u aç, YouTube'da şarkı başlat, ekranıma bak, bilgisayarda şunu yap.`
    : '';
  return `${name}${nicks ? `, ${nicks}` : ''}.${tail}`;
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
      'Kullanicinin KENDI varsayilan tarayicisinda bir adres, ya da varsayilan uygulamada bir dosya acar. ' +
      'Kullaniciya bir site/arama/sayfa GOSTERMEK icin HER ZAMAN bunu kullan. ' +
      'Kullanici "X\'i ac", "X\'e git", "X bul", "su dosyayi ac" dediginde bunu kullan. ' +
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

const SCREEN_ARG = {
  type: 'string',
  description: 'Hangi ekran: ekran adi (sistem mesajindaki), "focused" (odaktaki), "other" (yan/diger ekran), "left", "right", "laptop" ya da "all"',
};

const LOOK_TOOL = {
  type: 'function',
  function: {
    name: 'look_at_screen',
    description:
      'Ekrana bakar ve ne gordugunu anlatir. Kullanici "ekranima bak", "bu ne", ' +
      '"ne yaziyor", "sayfada ne var", "yan ekranda ne var" gibi ekrandaki bir seyi sordugunda kullan.',
    parameters: {
      type: 'object',
      properties: {
        question: { type: 'string', description: 'Ekranda ozellikle neye bakilacagi' },
        screen: { ...SCREEN_ARG, description: `${SCREEN_ARG.description}. Bos = odaktaki ekran.` },
      },
      required: [],
    },
  },
};

// Birden fazla ekran: "yan ekrana at", "diger ekranda ac" (livi: "yan ekranda
// islem yap deyince anlamiyor")
const MOVE_TO_SCREEN_TOOL = {
  type: 'function',
  function: {
    name: 'move_window_to_screen',
    description: 'Bir pencereyi baska bir ekrana tasir. "Sunu yan ekrana at", "Firefox\'u diger ekrana gonder" gibi isteklerde kullan.',
    parameters: {
      type: 'object',
      properties: {
        window: { type: 'string', description: 'Pencere basligindan ya da uygulama adindan bir parca (bos = odaktaki pencere)' },
        screen: SCREEN_ARG,
      },
      required: ['screen'],
    },
  },
};

const FOCUS_SCREEN_TOOL = {
  type: 'function',
  function: {
    name: 'focus_screen',
    description: 'Bir ekrani odaklar. Yeni acilacak uygulama/site belirli bir ekranda ("yan ekranda YouTube ac") acilsin isteniyorsa ONCE bunu cagir, sonra ac.',
    parameters: { type: 'object', properties: { screen: SCREEN_ARG }, required: ['screen'] },
  },
};

// Ekran duzeni (soldan saga) - modele ve araclara
async function screenLayout() {
  if (!hypr.available()) return [];
  try {
    const mons = (await hypr.json('monitors')).filter((m) => !m.disabled);
    const sorted = [...mons].sort((a, b) => a.x - b.x || a.y - b.y);
    return sorted.map((m, i) => ({
      name: m.name,
      side: sorted.length === 1 ? 'tek' : i === 0 ? 'sol' : i === sorted.length - 1 ? 'sag' : 'orta',
      laptop: /^(eDP|LVDS|DSI)/i.test(m.name),
      focused: Boolean(m.focused),
      model: String(m.model || m.description || '').slice(0, 40),
      workspace: m.activeWorkspace && m.activeWorkspace.id,
    }));
  } catch {
    return [];
  }
}

function describeLayout(layout) {
  const parts = layout.map((m) => `${m.name} = ${m.side} ekran, ${m.laptop ? 'laptop ekrani' : `harici monitor (${m.model})`}${m.focused ? ', SU AN ODAKTA (kullanicinin baktigi)' : ''}`);
  return `Ekranlar (soldan saga): ${parts.join('; ')}. Kullanici "yan ekran", "diger/obur ekran" derse odakta OLMAYAN ekrani, "bu ekran" derse odaktakini kastediyor. `
    + 'Ekranla ilgili islerde look_at_screen, focus_screen ve move_window_to_screen araclarina ekran adini ver.';
}

// "other", "sol", "laptop", "eDP-1"... -> ekran; bulunamazsa null (= hepsi)
function resolveScreen(arg, layout) {
  const a = String(arg || 'focused').toLocaleLowerCase('tr').trim();
  if (!layout.length || a === 'all' || a === 'hepsi') return null;
  const focused = layout.find((m) => m.focused) || layout[0];
  if (['focused', 'bu', 'this', 'current', 'odaktaki'].includes(a)) return focused;
  if (['other', 'yan', 'diger', 'diğer', 'obur', 'öbür', 'side'].some((w) => a.includes(w))) {
    return layout.find((m) => !m.focused) || focused;
  }
  if (a.includes('left') || a.includes('sol')) return layout.find((m) => m.side === 'sol') || focused;
  if (a.includes('right') || a.includes('sag') || a.includes('sağ')) return layout.find((m) => m.side === 'sag') || focused;
  if (a.includes('laptop') || a.includes('dizustu')) return layout.find((m) => m.laptop) || focused;
  return layout.find((m) => m.name.toLowerCase() === a) || focused;
}

async function moveWindowToScreen(windowQuery, screenArg) {
  const layout = await screenLayout();
  const target = resolveScreen(screenArg, layout);
  if (!target) return 'hedef ekran anlasilmadi';
  const q = String(windowQuery || '').toLocaleLowerCase('tr').trim();
  let win;
  if (!q) {
    win = await hypr.json('activewindow');
  } else {
    const clients = await hypr.json('clients');
    win = clients.find((c) => `${c.title} ${c.class} ${c.initialClass}`.toLocaleLowerCase('tr').includes(q) && c.class !== hypr.WINDOW_CLASS && c.class !== 'Kevin');
  }
  if (!win || !win.address) return `pencere bulunamadi: ${windowQuery || '(odaktaki)'}`;
  const out = await hypr.send(`/dispatch movetoworkspacesilent ${target.workspace},address:${win.address}`);
  return out === 'ok' ? `"${win.title}" ${target.name} ekranina tasindi` : `tasinamadi: ${out}`;
}

async function focusScreen(screenArg) {
  const target = resolveScreen(screenArg, await screenLayout());
  if (!target) return 'hedef ekran anlasilmadi';
  const out = await hypr.send(`/dispatch focusmonitor ${target.name}`);
  return out === 'ok' ? `${target.name} odaklandi; simdi acilan sey orada acilir` : `odaklanamadi: ${out}`;
}

const VISION_ENDPOINT = 'http://127.0.0.1:11434/v1/chat/completions';
const VISION_MODEL = process.env.KEVIN_VISION_MODEL || PROVIDERS.ollama.visionModel;

// Ekran goruntusunu sohbet modeline ham olarak gondermek yerine yerel vision
// modeline sorup METIN aliyoruz: boylece vision'i olmayan modeller de ekrani
// "gorebiliyor" ve token israfi olmuyor.
async function describeImage(imagePath, question) {
  const image = fs.readFileSync(imagePath).toString('base64');
  return describeImageBase64(image, question);
}

async function lookAtScreen(question, screenArg) {
  const shot = path.join(os.tmpdir(), `kevin-vision-${crypto.randomUUID()}.png`);
  try {
    // Eskiden butun ekranlar tek kucuk resimde yan yanaydi; artik istenen ekran
    const target = resolveScreen(screenArg, await screenLayout());
    const captured = await platform.captureScreen(shot, target ? 0.6 : 0.5, target ? target.name : null);
    if (!captured) return 'ekran goruntusu alinamadi';

    const image = fs.readFileSync(shot).toString('base64');
    return describeImageBase64(image, question);
  } finally {
    fs.rmSync(shot, { force: true });
  }
}

async function describeImageBase64(image, question) {
  const prompt = question && question.trim()
    ? question.trim()
    : 'Bu ekranda ne var? Kisa ve somut anlat.';
  return describeImages([image], prompt);
}

// Bulut saglayicilarin goruntu anlayan modelleri (kullanicinin kendi anahtariyla)
const CLOUD_VISION = {
  groq: 'meta-llama/llama-4-scout-17b-16e-instruct',
  gemini: 'gemini-flash-latest',
  nvidia: 'meta/llama-3.2-90b-vision-instruct',
};

async function visionRequest(baseURL, model, apiKey, prompt, images) {
  const response = await fetch(`${baseURL}/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(apiKey ? { Authorization: `Bearer ${apiKey}` } : {}) },
    signal: AbortSignal.timeout(60000),
    body: JSON.stringify({
      model,
      stream: false,
      messages: [{
        role: 'user',
        content: [
          { type: 'text', text: prompt },
          ...images.map((img) => ({
            type: 'image_url',
            image_url: { url: `data:image/${img.startsWith('/9j/') ? 'jpeg' : 'png'};base64,${img}` },
          })),
        ],
      }],
    }),
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${(await response.text()).slice(0, 200)}`);
  const data = await response.json();
  return data.choices?.[0]?.message?.content?.trim() || 'goruntuden bir sey okunamadi';
}

// Once bu bilgisayardaki goruntu modeli (Ollama), yoksa bulut
// Ollama modeli varsayilan olarak 5 dk ekran kartinda kaliyor; goruntu isi
// bitince birakilsin (ses tanima ve oyunlar icin VRAM)
function unloadOllamaModel(model) {
  fetch('http://127.0.0.1:11434/api/generate', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model, keep_alive: 0 }),
  }).catch(() => {});
}

async function describeImages(images, question) {
  const cfg = loadConfig();
  const prompt = `${question}\n${langs.lang(cfg).prompt} dilinde cevapla, en fazla 4 cumle.`;
  const errors = [];
  // Bulut saglayici seciliyse once o: yerel goruntu modeli (qwen2.5vl ~4.5 GB)
  // ekran kartini doldurup ses tanimayi (whisper GPU) bellek hatasina
  // dusuruyordu, Kevin kimseyi duymaz oluyordu
  const cloud = CLOUD_VISION[cfg.provider];
  const tryCloud = async () => {
    if (!cloud || !cfg.apiKey) return null;
    try {
      return await visionRequest(PROVIDERS[cfg.provider].baseURL, cloud, cfg.apiKey, prompt, images);
    } catch (err) {
      errors.push(`bulut: ${err.message}`);
      return null;
    }
  };
  if (!isLocal(cfg.provider)) {
    const seen = await tryCloud();
    if (seen) return seen;
  }
  try {
    return await visionRequest(PROVIDERS.ollama.baseURL, VISION_MODEL, null, prompt, images);
  } catch (err) {
    errors.push(`yerel: ${err.message}`);
  } finally {
    unloadOllamaModel(VISION_MODEL);
  }
  return `goruntuye bakilamadi (${errors.join(' | ') || 'goruntu modeli yok'})`;
}

const CAMERA_TOOL = {
  type: 'function',
  function: {
    name: 'look_at_camera',
    description:
      'Kameradan bakar: kullaniciyi gorur, tanidigin biriyse adini soyler, elinde/onunde ne oldugunu anlatir. ' +
      'Kullanici "bana bak", "beni goruyor musun", "bu ne" (elindeki bir seyi gosterirken), "beni taniyor musun" derse kullan.',
    parameters: {
      type: 'object',
      properties: { question: { type: 'string', description: 'Kamerada ozellikle neye bakilacagi' } },
      required: [],
    },
  },
};

const REMEMBER_FACE_TOOL = {
  type: 'function',
  function: {
    name: 'remember_face',
    description:
      'Kameradaki kisinin yuzunu verilen isimle kaydeder, sonra onu kameradan taniyabilirsin. ' +
      'Kullanici "bu benim, beni hatirla", "yuzumu kaydet", "bu X, onu tani" derse kullan.',
    parameters: {
      type: 'object',
      properties: { name: { type: 'string', description: 'Kisinin adi' } },
      required: ['name'],
    },
  },
};

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

// Kevin bir dosya yazinca (ayarda aciksa) kendi editor penceresinde harf harf
// yazarak gosterir. Dosya diske hemen yaziliyor; pencere sadece gosteriyor.
function liveType(filePath, content) {
  const cfg = loadConfig();
  if (cfg.liveTyping === false || !content) return;
  const typer = new BrowserWindow({
    width: 860,
    height: 620,
    title: `Kevin - ${path.basename(filePath)}`,
    backgroundColor: '#f4eee2',
    autoHideMenuBar: true,
    show: false,
    // Baska calisma alanina gecilince de yazmaya devam etsin
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, backgroundThrottling: false },
  });
  typer.loadURL('kevin://app/renderer/typer.html');
  if (process.env.KEVIN_TYPER_SHOT) {
    // Gelistirme: pencereyi gostermeden yazma aninin goruntusunu al
    setTimeout(async () => {
      fs.writeFileSync(process.env.KEVIN_TYPER_SHOT, (await typer.webContents.capturePage()).toPNG());
      app.quit();
    }, 4000);
  } else {
    typer.once('ready-to-show', () => typer.show());
  }
  typer.webContents.once('did-finish-load', () => {
    typer.webContents.send('typer-start', {
      file: filePath,
      content,
      lang: langs.langCode(cfg),
      speed: Number(cfg.typingSpeed) || 1,
    });
  });
}

async function writeFileTool(args) {
  const target = resolveUserPath(args.path);
  assertWritable(target);
  fs.mkdirSync(path.dirname(target), { recursive: true });

  if (fs.existsSync(target) && !args.append) {
    fs.copyFileSync(target, `${target}.yedek`);
  }
  if (args.append) fs.appendFileSync(target, args.content, 'utf8');
  else fs.writeFileSync(target, args.content, 'utf8');
  liveType(target, args.content);

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
      'Kendi (gorunmeyen) tarayicinda bir adresi acar ve sayfayi SENIN icin okur. ' +
      'Kullaniciya gostermek icin DEGIL (onun icin open_url_or_app). Sadece icerigi okuman ' +
      'ya da sayfada islem yapman gerekiyorsa; JavaScript ile yuklenen sayfalarda fetch_page yerine.',
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

function mcpToolsAsOpenAI(includeScreenControl, cfg) {
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
    ...(cfg && cfg.camera ? [CAMERA_TOOL, REMEMBER_FACE_TOOL] : []),
    ...(hypr.available() ? [MOVE_TO_SCREEN_TOOL, FOCUS_SCREEN_TOOL] : []),
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
  if (BRAIN_MODE || !characterAnchor || !hypr.available()) return;
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
    show: !BRAIN_MODE,
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

  if (!BRAIN_MODE) win.setAlwaysOnTop(true, 'screen-saver');
  const animArg = process.argv.find((a) => a.startsWith('--anim='));
  const params = new URLSearchParams();
  if (animArg) params.set('anim', animArg.slice(7));
  if (process.argv.includes('--no-vad')) params.set('novad', '1');
  if (BRAIN_MODE) params.set('brain', '1');
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

// Secili dilin kisa cumleleri (uyanma cevaplari, hata mesajlari)
ipcMain.handle('lang-pack', () => {
  const cfg = loadConfig();
  langs.voiceFor(cfg, VOICES_USER_DIR, [PIPER_VOICES_DIR]);
  return langs.lang(cfg);
});

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
const CAMERA_GREET_GAP_MS = 30 * 60 * 1000;
let lastCameraGreet = 0;
const FOLLOW_UP_MS = 120000;
let lastToolUseAt = 0;
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
  'tasarim', 'tasarım', 'ornek', 'örnek', 'resim', 'gorsel', 'görsel', 'pinterest',
  'haber', 'hava', 'fiyat', 'kac para', 'kaç para', 'nedir', 'ne demek', 'kim',
  'ne zaman', 'nerede', 'guncel', 'güncel', 'indir', 'goster', 'göster',
  'ekran', 'bak', 'baksana', 'goruyor musun', 'görüyor musun', 'ne yaziyor', 'ne yazıyor',
  'masaustu', 'masaüstü', 'indirilenler', 'belgeler',
  'file', 'read', 'write', 'search', 'open', 'show', 'screen',
  'youtube', 'video', 'izle', 'dinle', 'sarki', 'şarkı', 'muzik', 'müzik',
  'giris yap', 'giriş yap', 'login', 'form', 'doldur', 'gonder', 'gönder',
  'tarayici', 'tarayıcı', 'browser', 'sekmede', 'sitede',
  'kamera', 'tanı', 'tani', 'tanıyor', 'taniyor', 'görüyor', 'goruyor', 'yüzüm', 'yuzum',
  'elimde', 'elimdeki', 'hatırla', 'hatirla', 'camera',
  'kod', 'script', 'betik', 'program', 'fonksiyon', 'code',
];

const SCREEN_CONTROL_KEYWORDS = [
  'tikla', 'tıkla', 'pencere', 'sekme', 'tusa bas', 'tuşa bas', 'yazi yaz', 'yazı yaz',
  'kaydir', 'kaydır', 'scroll', 'buyut', 'büyüt', 'kucult', 'küçült', 'kapat',
  'one getir', 'öne getir', 'click', 'window', 'type', 'press',
  // "bilgisayarda sunu yap", "yan ekranda islem yap" (livi: "yapmiyor lavuk")
  'bilgisayar', 'ekranda', 'ekranımda', 'ekranimda', 'yan ekran', 'diğer ekran', 'diger ekran',
  'öbür ekran', 'obur ekran', 'sağdaki', 'sagdaki', 'soldaki', 'monitör', 'monitor', 'laptop',
  'işlem yap', 'islem yap', 'şunu yap', 'sunu yap', 'bunu yap', 'yapar mısın', 'yapar misin',
  'yapsana', 'taşı', 'tasi', 'yerleştir', 'yerlestir', 'on the other screen',
];

// Kisa anahtar kelimeler ("ac", "bul", "oku") sadece kelime basinda: "acaba"
// gibi kelimelerin icinde eslesip her cumlede arac semalarini (binlerce token)
// gonderiyordu, Groq'un dakikalik siniri doluyordu.
function keywordHit(lower, key) {
  if (key.length > 4) return lower.includes(key);
  return new RegExp(`(^|[^a-zçğıöşü])${key}`, 'i').test(lower);
}

function messageNeedsAgent(text) {
  const lower = text.toLocaleLowerCase('tr');
  return BASIC_TOOL_KEYWORDS.some((k) => keywordHit(lower, k))
    || SCREEN_CONTROL_KEYWORDS.some((k) => keywordHit(lower, k));
}

function messageNeedsScreenControl(text) {
  const lower = text.toLocaleLowerCase('tr');
  return SCREEN_CONTROL_KEYWORDS.some((k) => keywordHit(lower, k));
}

ipcMain.handle('chat', async (_event, history) => {
  const cfg = loadConfig();
  if (!cfg.provider) {
    throw new Error('NO_KEY');
  }
  if (!cfg.apiKey && !isLocal(cfg.provider)) {
    // Herkes kendi anahtarini girmeli; renderer bunu kullaniciya soyluyor
    throw new Error('NO_KEY');
  }

  const provider = PROVIDERS[cfg.provider];
  let model = cfg.model || provider.defaultModel;
  const L = langs.lang(cfg);

  const messages = [
    {
      role: 'system',
      content: buildPersona(cfg),
    },
    ...history,
  ];

  // "Bizi gorunce taniyordu": ayarda aciksa, uzun aradan sonra ilk
  // seslenmede kameradan bir bakip kim oldugunu anliyor
  if (cfg.camera && cfg.cameraGreet && Date.now() - lastCameraGreet > CAMERA_GREET_GAP_MS) {
    lastCameraGreet = Date.now();
    try {
      const seen = await akil.lookAtCamera('Kim var? Tek cumle.', cfg.cameraDevice, describeImages);
      messages.splice(1, 0, {
        role: 'system',
        content: `Az once kameradan baktin: ${seen} (Taniyorsan adiyla hitap et; gerekmedikce kameradan bahsetme.)`,
      });
    } catch (err) {
      console.warn('[kevin] kamera:', err.message);
    }
  }

  const lastUserMessage = [...history].reverse().find((m) => m.role === 'user')?.content || '';
  // Az once arac kullanildiysa devam cumlelerinde de ("daha yumusak olsun",
  // "digerini ac") araclar acik: anahtar kelime yok diye araçsiz gidip bos
  // cevap donuyordu.
  const followUp = Date.now() - lastToolUseAt < FOLLOW_UP_MS;
  // Anahtar kelimeler Turkce; baska dilde araclar hep acik (model kendi secer)
  const otherLang = langs.langCode(cfg) !== 'tr';
  let tools = messageNeedsAgent(lastUserMessage) || followUp || otherLang
    ? mcpToolsAsOpenAI(messageNeedsScreenControl(lastUserMessage) || otherLang, cfg)
    : undefined;
  // Araclar aciksa model ekran duzenini bilsin ("yan ekran" hangisi)
  if (tools) {
    const layout = await screenLayout();
    if (layout.length > 1) messages.splice(1, 0, { role: 'system', content: describeLayout(layout) });
  }
  // Ilk adimda arac cagirmaya zorla (model metinle "yapiyorum" diye uydurmasin) -
  // en az bir gercek arac cagrisindan sonra 'auto'ya gecilir, yoksa sonsuz zorlanir.
  let hasCalledTool = false;
  let rateRetried = false;
  let emptyRetried = false;
  let busyRetries = 0;
  let usedFallback = false;

  async function callCompletions(forceNoTools) {
    const activeTools = forceNoTools ? undefined : tools;
    const toolChoice = hasCalledTool || !messageNeedsAgent(lastUserMessage) ? 'auto' : 'required';
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
      if (response.status === 404 && /model_not_found|models\/|is not found|not supported/i.test(text) && model !== provider.defaultModel) {
        console.warn(`[kevin] "${model}" artik yok, varsayilana geciliyor: ${provider.defaultModel}`);
        model = provider.defaultModel;
        saveConfig({ ...loadConfig(), model: '' });
        return callCompletions(forceNoTools);
      }

      // Groq ucretsiz katman: dakikalik token siniri (TPM). "X sn sonra dene"
      // diyorsa o kadar bekleyip bir kez daha dene; onceden direkt "bir sorun
      // cikti" deniyordu.
      if (response.status === 429 && !rateRetried) {
        const m = text.match(/try again in ([0-9.]+)s/i);
        const wait = m ? parseFloat(m[1]) : 6;
        if (wait <= 18) {
          rateRetried = true;
          console.warn(`[kevin] hiz siniri, ${wait.toFixed(1)} sn bekleniyor`);
          await new Promise((r) => setTimeout(r, (wait + 0.4) * 1000));
          return callCompletions(forceNoTools);
        }
      }

      // Saglayici yogun / gecici hata (Gemini "high demand" 503 veriyordu ve
      // Kevin her seferinde "bir sorun cikti" diyordu): kisa araliklarla iki
      // kez daha dene, olmazsa yedek modele gec
      if ([500, 502, 503, 504].includes(response.status) || (response.status === 429 && rateRetried)) {
        if (busyRetries < 2) {
          busyRetries += 1;
          console.warn(`[kevin] saglayici yogun (${response.status}), tekrar ${busyRetries}`);
          await new Promise((r) => setTimeout(r, busyRetries * 1200));
          return callCompletions(forceNoTools);
        }
        if (provider.fallbackModel && model !== provider.fallbackModel && !usedFallback) {
          usedFallback = true;
          console.warn(`[kevin] "${model}" yogun, bu cevap icin yedek model: ${provider.fallbackModel}`);
          model = provider.fallbackModel;
          return callCompletions(forceNoTools);
        }
        throw new Error('BUSY');
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
      return L.unclear;
    }

    if (replyMsg.tool_calls?.length) {
      messages.push(replyMsg);
      hasCalledTool = true;
      lastToolUseAt = Date.now();

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
          } else if (call.function.name === 'look_at_camera') {
            resultText = await akil.lookAtCamera(args.question, cfg.cameraDevice, describeImages);
          } else if (call.function.name === 'remember_face') {
            resultText = await akil.rememberFace(args.name, cfg.cameraDevice);
          } else if (call.function.name === 'look_at_screen') {
            resultText = await lookAtScreen(args.question, args.screen);
          } else if (call.function.name === 'move_window_to_screen') {
            resultText = await moveWindowToScreen(args.window, args.screen);
          } else if (call.function.name === 'focus_screen') {
            resultText = await focusScreen(args.screen);
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
    // Etiketler: [duygu] basta, [hatirla: ...] / [unut: ...] sonda
    const parsed = akil.parseReply(stripEmoji(replyMsg.content || ''));
    const text = parsed.text;
    if (parsed.mood && parsed.mood !== 'notr') bodySend({ type: 'mood', mood: parsed.mood });
    if (text) return text;
    // Model bos dondu (gpt-oss ara sira sadece 'dusunup' bos birakiyor):
    // bir kez daha, araçsiz ve kisa cevap iste
    if (!emptyRetried) {
      emptyRetried = true;
      tools = undefined;
      messages.push({ role: 'system', content: 'Cevabin bos geldi. Kullaniciya simdi kisa, dogal bir cumleyle cevap ver.' });
      continue;
    }
    console.warn('[kevin] model bos cevap verdi');
    return L.unclear;
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

    return await runWhisper(wavPath, loadConfig());
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
    return await runWhisper(wavPath, loadConfig());
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
  const cfg = loadConfig();
  const voice = PIPER_VOICE || langs.voiceFor(cfg, VOICES_USER_DIR, [PIPER_VOICES_DIR]);
  // Dilin sesi henuz inmediyse sessiz (indirme arkada suruyor)
  if (!voice) throw new Error('ses indiriliyor');
  const rate = Math.min(1.6, Math.max(0.6, Number(cfg.speechRate) || 1));

  try {
    await runCommand(
      PIPER_BIN,
      ['-m', voice, '--espeak_data', PIPER_ESPEAK_DATA, '--length_scale', String(1 / rate), '-f', outPath],
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

// Muzik sitesi (tarayicida calarken adresinden anlasilir)
const MUSIC_SITE_HINTS = [
  'music.youtube.com', 'open.spotify.com', 'soundcloud.com', 'deezer.com', 'music.apple.com',
  'tidal.com', 'bandcamp.com', 'fizy.com', 'music.amazon', 'radio', 'last.fm',
];
// YouTube'da video degil sarki oldugunu gosteren basliklar
const SONG_TITLE_HINTS = /(official audio|official (music )?video|music video|video ?clip|audio\)|lyrics?|lyric video|sözleri|şarkı sözü|remix|slowed|sped up|nightcore|\bft\.|\bfeat\.|playlist|full album|topic)/i;

// Kevin sadece SARKI calarken dans etsin; video (YouTube izlerken) degil.
// Tarayicida "sanatci" alani YouTube'da kanal adi oldugu icin tek basina
// yetmiyordu (her videoda dans ediyordu).
function looksLikeMusic({ player, url, album, title, lengthUs }) {
  const name = player.toLowerCase();
  if (MUSIC_PLAYER_HINTS.some((hint) => name.includes(hint))) return true;
  const u = url.toLowerCase();
  if (MUSIC_SITE_HINTS.some((hint) => u.includes(hint))) return true;
  // Muzik siteleri albumu da bildiriyor; video sitelerinde bos
  if (album.trim()) return true;
  const minutes = Number(lengthUs) / 60e6;
  const songLength = minutes > 0.5 && minutes < 9;
  return songLength && SONG_TITLE_HINTS.test(title);
}

const beatTracker = new BeatTracker((r) => bodySend({ type: 'beat', ...r }));

ipcMain.handle('music-status', async () => {
  if (!platform.isLinux) return { playing: false };

  try {
    const { stdout } = await runCommand('playerctl', [
      '-a',
      'metadata',
      '--format',
      '{{playerName}}\t{{status}}\t{{xesam:url}}\t{{xesam:album}}\t{{mpris:length}}\t{{xesam:title}}',
    ]);

    // anyPlaying: sarki ya da video, hoparlorden ses geliyor (mikrofona da
    // giriyor; Kevin videodaki konusmayi kullanicininki sanmasin)
    let music = null;
    let anyPlaying = false;
    for (const line of stdout.split('\n')) {
      const [player = '', status = '', url = '', album = '', lengthUs = '', title = ''] = line.split('\t');
      if (status !== 'Playing') continue;
      anyPlaying = true;
      if (!music && looksLikeMusic({ player, url, album, title, lengthUs })) music = { player, title };
    }
    // Sarki calarken temposunu olc (govde dansi vurusa oturtuyor)
    if (BRAIN_MODE) {
      if (music) beatTracker.start();
      else beatTracker.stop();
    }
    return { playing: Boolean(music), anyPlaying, ...(music || {}) };
  } catch {
    return { playing: false };
  }
});

// Kevin'e seslenilince calan video/muzik duraklar, konusma bitince devam eder
let pausedPlayers = [];

ipcMain.handle('media-pause', async () => {
  if (!platform.isLinux) return false;
  try {
    const { stdout } = await runCommand('playerctl', ['-a', 'metadata', '--format', '{{playerName}}\t{{status}}\t{{playerInstance}}']);
    const playing = stdout.split('\n').map((l) => l.split('\t')).filter((p) => p[1] === 'Playing').map((p) => p[2]);
    for (const inst of playing) await runCommand('playerctl', ['-p', inst, 'pause']).catch(() => {});
    pausedPlayers = playing;
    return playing.length > 0;
  } catch {
    return false;
  }
});

ipcMain.handle('media-resume', async () => {
  const list = pausedPlayers;
  pausedPlayers = [];
  for (const inst of list) await runCommand('playerctl', ['-p', inst, 'play']).catch(() => {});
  return list.length > 0;
});

// Kevin dinlerken/konusurken calan seslerin seviyesi kisilir, sonra geri
// gelir (livi: "konusurken sarki duruyor"). Kevin'in kendi sesi kisilmaz.
const DUCK_LEVEL = 0.25;
let duckedInputs = new Map();

async function sinkInputs() {
  const { stdout } = await runCommand('pactl', ['-f', 'json', 'list', 'sink-inputs']);
  return JSON.parse(stdout || '[]');
}

function isOwnStream(si) {
  const p = si.properties || {};
  const ownPids = new Set(app.getAppMetrics().map((m) => String(m.pid)));
  if (p['application.process.id'] && ownPids.has(String(p['application.process.id']))) return true;
  const name = `${p['application.name'] || ''} ${p['application.process.binary'] || ''}`.toLowerCase();
  return name.includes('electron') || name.includes('kevin');
}

ipcMain.handle('media-duck', async () => {
  if (!platform.isLinux || duckedInputs.size) return duckedInputs.size > 0;
  try {
    for (const si of await sinkInputs()) {
      if (si.corked || isOwnStream(si)) continue;
      const values = Object.values(si.volume || {}).map((c) => c.value);
      if (!values.length) continue;
      duckedInputs.set(si.index, values);
      await runCommand('pactl', ['set-sink-input-volume', String(si.index), ...values.map((v) => String(Math.round(v * DUCK_LEVEL)))]).catch(() => {});
    }
  } catch (err) {
    console.warn('[kevin] ses kisilamadi:', err.message);
  }
  return duckedInputs.size > 0;
});

ipcMain.handle('media-unduck', async () => {
  const list = duckedInputs;
  duckedInputs = new Map();
  for (const [index, values] of list) {
    await runCommand('pactl', ['set-sink-input-volume', String(index), ...values.map(String)]).catch(() => {});
  }
  return list.size > 0;
});

app.whenReady().then(async () => {
  if (LAUNCHER) return;
  protocol.handle('kevin', (request) => {
    const url = new URL(request.url);
    const filePath = path.join(__dirname, url.pathname);
    return net.fetch(pathToFileURL(filePath).toString());
  });

  if (BRAIN_MODE) startBodyBridge();
  if (process.env.KEVIN_TYPER_SHOT) {
    liveType('/home/kevin/ornek.py', 'import random\n\n# Zar at\ndef zar(kac=2):\n    return [random.randint(1, 6) for _ in range(kac)]\n\nif __name__ == "__main__":\n    print("Zarlar:", zar())\n'.repeat(3));
    return;
  }

  // Kurallar pencereden ONCE yuklenmeli: windowrule pencere acilirken uygulaniyor.
  if (hypr.available() && !BRAIN_MODE) {
    try {
      await hypr.loadRules(path.join(app.getPath('userData'), 'hypr-rules.conf'));
    } catch (err) {
      console.error('[kevin] kural dosyasi:', err.message);
    }
  }

  createWindow();
  initAgentMCP();

  // setprop acik pencereye uygulaniyor, o yuzden pencere gorunur olduktan sonra.
  if (hypr.available() && !BRAIN_MODE) {
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

app.on('will-quit', () => {
  beatTracker.stop();
  // Kisik birakilan ses kalmasin
  for (const [index, values] of duckedInputs) {
    spawn('pactl', ['set-sink-input-volume', String(index), ...values.map(String)]);
  }
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
