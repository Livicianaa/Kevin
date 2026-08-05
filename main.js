const { app, BrowserWindow, screen, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');

const WIN_WIDTH = 140;
const WIN_HEIGHT = 210;
const MARGIN = 20;

const CONFIG_PATH = path.join(app.getPath('userData'), 'config.json');

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
  win.loadFile('renderer/index.html');
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

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});
