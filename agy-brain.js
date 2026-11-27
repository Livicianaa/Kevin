const { spawn, execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

function agyAvailable() {
  try {
    execFileSync('agy', ['--help'], { timeout: 5000, stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

function extractActions(text) {
  if (!text || typeof text !== 'string') {
    return { clean: '', actions: [] };
  }
  const actions = [];
  const actionRegex = /\[\[kevin:(oku|ac|ses)\s+([^\]]+)\]\]/gi;
  let match;
  while ((match = actionRegex.exec(text)) !== null) {
    actions.push({
      kind: match[1].toLowerCase(),
      arg: match[2].trim(),
    });
  }
  const clean = text
    .replace(/\[\[kevin:(oku|ac|ses)\s+([^\]]+)\]\]/gi, '')
    .replace(/[ \t]{2,}/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
  return { clean, actions };
}

function agyIntro(persona, home) {
  const p = persona ? `${persona}\n\n` : '';
  const h = home || '';
  return `${p}Cevap sesli okunacak, kisa olmali. Markdown, liste, madde imi veya kod blogu kullanma.
Dosya bulmak veya okumak icin kendi araclarini kullan (ev klasoru: ${h}).
Eylemler icin cevap SONUNA etiket ekle:
[[kevin:oku /tam/yol]] (Kevin kitabi cikarip sesli okur: pdf epub md txt cbz resim).
[[kevin:ac adres-ya-da-uygulama]] (URL veya masaustu uygulamasi acar).
[[kevin:ses /tam/yol]] (ses modelini kurar ve o sesle konusmaya baslar: RVC .pth ve varsa yanindaki .index icin ayri ayri etiket, Piper .onnx). Kullanici ses modeli yukle/kur/ekle derse dosyayi bul (yoksa indirilenler ve ev klasorunde en yeni uygun .pth), G_ ve D_ ile baslayan egitim dosyalarini secme.
Kullanici bir sey okumani isterse dosyayi kendin bul, oku etiketini koy, icerigi anlatma, sadece kisa "tamam okuyorum" de; dosya belirtmezse indirilenler klasorundeki en yeni BELGEYI (pdf, epub, md, txt, cbz) sec, sorma; resim dosyasini sadece kullanici manga, cizgi roman ya da resim derse sec.`;
}

function arraysEqual(a, b) {
  if (a === b) return true;
  if (!a || !b) return false;
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

function createAgyBrain({ workDir, log } = {}) {
  const ws = path.resolve(workDir || process.cwd());
  try {
    fs.mkdirSync(ws, { recursive: true });
  } catch {}

  let proc = null;
  let currentConfig = null;
  let firstMessageSent = false;
  let stdoutBuffer = '';
  let activeTurn = null;
  let idleTimer = null;
  const queue = [];

  function logMsg(msg) {
    if (typeof log === 'function') {
      try {
        log(msg);
      } catch {}
    }
  }

  function resetIdleTimer() {
    if (idleTimer) {
      clearTimeout(idleTimer);
      idleTimer = null;
    }
    if (proc && queue.length === 0 && !activeTurn) {
      idleTimer = setTimeout(() => {
        stop();
      }, 20 * 60 * 1000);
    }
  }

  function killProcess() {
    if (proc) {
      const p = proc;
      proc = null;
      currentConfig = null;
      firstMessageSent = false;
      stdoutBuffer = '';
      try {
        p.kill('SIGTERM');
        setTimeout(() => {
          try {
            p.kill('SIGKILL');
          } catch {}
        }, 2000).unref();
      } catch {}
    }
  }

  function handleProcessExit(err) {
    proc = null;
    currentConfig = null;
    firstMessageSent = false;
    stdoutBuffer = '';
    if (activeTurn) {
      clearTimeout(activeTurn.timer);
      const rej = activeTurn.reject;
      activeTurn = null;
      rej(err || new Error('agy process exited'));
    }
    drainQueue();
  }

  function spawnProcess(config) {
    killProcess();
    currentConfig = {
      model: config.model || 'gemini-3.8-flash-medium',
      dirs: Array.isArray(config.dirs) ? [...config.dirs] : [],
      intro: config.intro || '',
    };
    firstMessageSent = false;
    stdoutBuffer = '';

    const args = [
      '-p', '',
      '--input-format', 'stream-json',
      '--output-format', 'stream-json',
      '--model', currentConfig.model,
      '--sandbox',
      '--disable-slash-commands',
    ];
    for (const dir of currentConfig.dirs) {
      if (dir) {
        args.push('--add-dir', dir);
      }
    }

    try {
      proc = spawn('agy', args, {
        cwd: ws,
        stdio: ['pipe', 'pipe', 'pipe'],
        env: process.env,
      });
    } catch (err) {
      proc = null;
      throw err;
    }

    proc.stderr.on('data', (chunk) => {
      logMsg(chunk.toString());
    });

    proc.stdout.on('data', (chunk) => {
      stdoutBuffer += chunk.toString();
      let nl;
      while ((nl = stdoutBuffer.indexOf('\n')) >= 0) {
        const line = stdoutBuffer.slice(0, nl).trim();
        stdoutBuffer = stdoutBuffer.slice(nl + 1);
        if (!line) continue;
        onLine(line);
      }
    });

    proc.on('error', (err) => {
      logMsg(`process error: ${err.message}`);
      handleProcessExit(err);
    });

    proc.on('close', (code, signal) => {
      logMsg(`process closed with code ${code} signal ${signal}`);
      handleProcessExit(new Error(`agy process exited with code ${code}`));
    });
  }

  function onLine(line) {
    if (!activeTurn) return;
    try {
      const data = JSON.parse(line);
      if (data.event === 'result') {
        const res = data.result || {};
        clearTimeout(activeTurn.timer);
        const resFn = activeTurn.resolve;
        const rejFn = activeTurn.reject;
        activeTurn = null;
        if (res.status === 'SUCCESS') {
          resFn(res.response || '');
        } else {
          rejFn(new Error(res.error || res.response || 'agy error'));
        }
        drainQueue();
      }
    } catch {}
  }

  function drainQueue() {
    if (activeTurn) return;

    if (queue.length === 0) {
      resetIdleTimer();
      return;
    }

    if (idleTimer) {
      clearTimeout(idleTimer);
      idleTimer = null;
    }

    const item = queue.shift();
    const targetModel = item.model || 'gemini-3.8-flash-medium';
    const targetDirs = Array.isArray(item.dirs) ? item.dirs : [];
    const targetIntro = item.intro || '';

    const needsRestart = !proc
      || !currentConfig
      || currentConfig.model !== targetModel
      || currentConfig.intro !== targetIntro
      || !arraysEqual(currentConfig.dirs, targetDirs);

    if (needsRestart) {
      try {
        spawnProcess({ model: targetModel, dirs: targetDirs, intro: targetIntro });
      } catch (err) {
        item.reject(err);
        drainQueue();
        return;
      }
    }

    let promptText = item.text || '';
    if (!firstMessageSent) {
      promptText = targetIntro ? `${targetIntro}\n\n---\n\n${promptText}` : promptText;
      firstMessageSent = true;
    }

    const inputEvent = JSON.stringify({
      event: 'user',
      message: {
        content: [{ type: 'text', text: promptText }],
      },
    }) + '\n';

    const timer = setTimeout(() => {
      if (activeTurn && activeTurn.timer === timer) {
        const rejFn = activeTurn.reject;
        activeTurn = null;
        killProcess();
        rejFn(new Error('Tur zaman asimi (90 sn)'));
        drainQueue();
      }
    }, 90000);

    activeTurn = {
      resolve: item.resolve,
      reject: item.reject,
      timer,
    };

    try {
      proc.stdin.write(inputEvent);
    } catch (err) {
      clearTimeout(timer);
      activeTurn = null;
      killProcess();
      item.reject(err);
      drainQueue();
    }
  }

  function ask({ model, dirs, intro, text }) {
    return new Promise((resolve, reject) => {
      queue.push({
        model: model || 'gemini-3.8-flash-medium',
        dirs: Array.isArray(dirs) ? dirs : [],
        intro: intro || '',
        text: text || '',
        resolve,
        reject,
      });
      drainQueue();
    });
  }

  function warm(opts = {}) {
    if (idleTimer) {
      clearTimeout(idleTimer);
      idleTimer = null;
    }
    const targetModel = opts.model || 'gemini-3.8-flash-medium';
    const targetDirs = Array.isArray(opts.dirs) ? opts.dirs : [];
    const targetIntro = opts.intro || '';

    const needsRestart = !proc
      || !currentConfig
      || currentConfig.model !== targetModel
      || currentConfig.intro !== targetIntro
      || !arraysEqual(currentConfig.dirs, targetDirs);

    if (needsRestart) {
      spawnProcess({ model: targetModel, dirs: targetDirs, intro: targetIntro });
    }
    resetIdleTimer();
  }

  function stop() {
    if (idleTimer) {
      clearTimeout(idleTimer);
      idleTimer = null;
    }
    if (activeTurn) {
      clearTimeout(activeTurn.timer);
      activeTurn.reject(new Error('Durduruldu'));
      activeTurn = null;
    }
    while (queue.length > 0) {
      const item = queue.shift();
      item.reject(new Error('Durduruldu'));
    }
    killProcess();
  }

  return {
    ask,
    warm,
    stop,
  };
}

module.exports = {
  createAgyBrain,
  agyAvailable,
  extractActions,
  agyIntro,
};
