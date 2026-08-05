const { app, BrowserWindow, screen, ipcMain, protocol, net } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const { spawn } = require('child_process');
const { pathToFileURL } = require('url');

protocol.registerSchemesAsPrivileged([
  {
    scheme: 'kevin',
    privileges: { standard: true, secure: true, supportFetchAPI: true, corsEnabled: true },
  },
]);

const WIN_WIDTH = 140;
const WIN_HEIGHT = 210;
const MARGIN = 20;

const CONFIG_PATH = path.join(app.getPath('userData'), 'config.json');

const PIPER_DIR = path.join(__dirname, 'bin', 'piper');
const PIPER_BIN = path.join(PIPER_DIR, 'piper');
const PIPER_VOICE = path.join(__dirname, 'bin', 'piper-voices', 'tr_TR-fahrettin-medium', 'tr_TR-fahrettin-medium.onnx');
const PIPER_ESPEAK_DATA = path.join(PIPER_DIR, 'espeak-ng-data');

const WHISPER_DIR = path.join(__dirname, 'bin', 'whisper');
const WHISPER_BIN = path.join(WHISPER_DIR, 'whisper-cli');
const WHISPER_MODEL = path.join(__dirname, 'bin', 'whisper-models', 'ggml-base.bin');

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

const PROVIDERS = {
  nvidia: {
    baseURL: 'https://integrate.api.nvidia.com/v1',
    defaultModel: 'meta/llama-3.3-70b-instruct',
  },
  groq: {
    baseURL: 'https://api.groq.com/openai/v1',
    defaultModel: 'openai/gpt-oss-120b',
  },
};

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

function resizeAnchored(width, height) {
  const { width: screenW, height: screenH } = screen.getPrimaryDisplay().workAreaSize;
  win.setBounds({
    x: screenW - width - MARGIN,
    y: screenH - height - MARGIN,
    width,
    height,
  });
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
    },
  });

  win.setAlwaysOnTop(true, 'screen-saver');
  win.loadURL('kevin://app/renderer/index.html');

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
  resizeAnchored(width, height);
});

ipcMain.handle('chat', async (_event, message) => {
  const cfg = loadConfig();
  if (!cfg.apiKey || !cfg.provider) {
    throw new Error('API key ayarlanmamis');
  }

  const provider = PROVIDERS[cfg.provider];
  const model = cfg.model || provider.defaultModel;
  const language = cfg.language || 'Turkce';
  const name = cfg.name || 'Kevin';

  const response = await fetch(`${provider.baseURL}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${cfg.apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: 'system',
          content: `Senin adin ${name}. Kullanicinin masaustunde yasayan, kisa ve samimi cevaplar veren bir AI karaktersin. Sadece ${language} dilinde cevap ver. Cevaplarin 2-3 cumleyi gecmesin.`,
        },
        { role: 'user', content: message },
      ],
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`API hatasi (${response.status}): ${text.slice(0, 200)}`);
  }

  const data = await response.json();
  return data.choices?.[0]?.message?.content?.trim() || '(bos cevap)';
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
      ['-m', WHISPER_MODEL, '-f', wavPath, '-l', lang, '-nt', '-np'],
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
      ['-m', WHISPER_MODEL, '-f', wavPath, '-l', lang, '-nt', '-np'],
      { env: { LD_LIBRARY_PATH: WHISPER_DIR } },
    );

    return stdout.trim();
  } finally {
    fs.rmSync(wavPath, { force: true });
  }
});

ipcMain.handle('speak', async (_event, text) => {
  const id = crypto.randomUUID();
  const outPath = path.join(os.tmpdir(), `kevin-tts-${id}.wav`);

  try {
    await runCommand(
      PIPER_BIN,
      ['-m', PIPER_VOICE, '--espeak_data', PIPER_ESPEAK_DATA, '-f', outPath],
      { env: { LD_LIBRARY_PATH: PIPER_DIR }, input: text },
    );

    const audio = fs.readFileSync(outPath);
    return audio.toString('base64');
  } finally {
    fs.rmSync(outPath, { force: true });
  }
});

app.whenReady().then(() => {
  protocol.handle('kevin', (request) => {
    const url = new URL(request.url);
    const filePath = path.join(__dirname, url.pathname);
    return net.fetch(pathToFileURL(filePath).toString());
  });

  createWindow();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
