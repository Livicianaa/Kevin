const { spawn, execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const availabilityCache = new Map();

function cliAvailable(cmd) {
  if (availabilityCache.has(cmd)) {
    return availabilityCache.get(cmd);
  }
  const lookup = process.platform === 'win32' ? 'where' : 'which';
  try {
    execFileSync(lookup, [cmd], { timeout: 5000, stdio: 'ignore' });
    availabilityCache.set(cmd, true);
    return true;
  } catch {
    availabilityCache.set(cmd, false);
    return false;
  }
}

function spawnCli(cmd, args, opts) {
  if (process.platform !== 'win32') return spawn(cmd, args, opts);
  const quoted = args.map((a) => (a === '' || /[\s"&|<>^]/.test(a) ? `"${String(a).replace(/"/g, '""')}"` : a));
  return spawn(cmd, quoted, { ...opts, shell: true, windowsHide: true });
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

function createClaudeBrain({ log } = {}) {
  let proc = null;
  let currentConfig = null;
  let stdoutBuffer = '';
  let activeTurn = null;
  const queue = [];

  function logMsg(msg) {
    if (typeof log === 'function') {
      try {
        log(msg);
      } catch {}
    }
  }

  function killProcess() {
    if (proc) {
      const p = proc;
      proc = null;
      currentConfig = null;
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
    stdoutBuffer = '';
    if (activeTurn) {
      clearTimeout(activeTurn.timer);
      const rej = activeTurn.reject;
      activeTurn = null;
      rej(err || new Error('claude sureci kapandi'));
    }
    drainQueue();
  }

  function spawnProcess(config) {
    killProcess();
    const model = ['haiku', 'sonnet', 'opus'].includes(config.model) ? config.model : 'haiku';
    currentConfig = {
      model,
      dirs: Array.isArray(config.dirs) ? [...config.dirs] : [],
      intro: config.intro || '',
    };
    stdoutBuffer = '';

    const introFile = path.join(os.tmpdir(), 'kevin-claude-intro.txt');
    try {
      fs.writeFileSync(introFile, currentConfig.intro || '', 'utf8');
    } catch (err) {
      logMsg(`intro yazma hatasi: ${err.message}`);
    }

    const args = [
      '-p',
      '--setting-sources', '',
      '--input-format', 'stream-json',
      '--output-format', 'stream-json',
      '--verbose',
      '--model', currentConfig.model,
      '--tools', 'Read,Glob,Grep,WebSearch,WebFetch',
      '--allowedTools', 'Read', 'Glob', 'Grep', 'WebSearch', 'WebFetch',
      '--no-session-persistence',
      '--append-system-prompt-file', introFile,
    ];
    for (const dir of currentConfig.dirs) {
      if (dir) {
        args.push('--add-dir', dir);
      }
    }

    try {
      proc = spawnCli('claude', args, {
        cwd: os.tmpdir(),
        stdio: ['pipe', 'pipe', 'pipe'],
      });
    } catch (err) {
      proc = null;
      throw err;
    }

    const self = proc;
    proc.stderr.on('data', (chunk) => {
      logMsg(chunk.toString());
    });

    proc.stdout.on('data', (chunk) => {
      if (proc !== self) return;
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
      logMsg(`surec hatasi: ${err.message}`);
      if (proc === self) handleProcessExit(err);
    });

    proc.on('close', (code, signal) => {
      logMsg(`surec kapandi: kod ${code} sinyal ${signal}`);
      if (proc === self) handleProcessExit(new Error(`claude sureci kapandi: kod ${code}`));
    });
  }

  function onLine(line) {
    if (!activeTurn) return;
    try {
      const data = JSON.parse(line);
      if (data.type === 'result') {
        clearTimeout(activeTurn.timer);
        const resFn = activeTurn.resolve;
        const rejFn = activeTurn.reject;
        activeTurn = null;
        if (data.is_error) {
          rejFn(new Error(data.result || 'claude hata'));
        } else {
          resFn(String(data.result != null ? data.result : ''));
        }
        drainQueue();
      }
    } catch {}
  }

  function drainQueue() {
    if (activeTurn) return;
    if (queue.length === 0) return;

    const item = queue.shift();
    const targetModel = ['haiku', 'sonnet', 'opus'].includes(item.model) ? item.model : 'haiku';
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

    const inputEvent = JSON.stringify({
      type: 'user',
      message: {
        role: 'user',
        content: [{ type: 'text', text: item.text || '' }],
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
        model: model || 'haiku',
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
    const targetModel = ['haiku', 'sonnet', 'opus'].includes(opts.model) ? opts.model : 'haiku';
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
  }

  function stop() {
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

function createOpenCodeBrain({ log } = {}) {
  let sessionId = null;
  let currentModel = null;
  let currentIntro = null;
  let isFirst = true;
  let activeProc = null;
  let activeTurn = null;
  const queue = [];

  function logMsg(msg) {
    if (typeof log === 'function') {
      try {
        log(msg);
      } catch {}
    }
  }

  function drainQueue() {
    if (activeTurn) return;
    if (queue.length === 0) return;

    const item = queue.shift();
    const targetModel = item.model || '';
    const targetIntro = item.intro || '';

    if (currentModel !== targetModel || currentIntro !== targetIntro) {
      sessionId = null;
      isFirst = true;
      currentModel = targetModel;
      currentIntro = targetIntro;
    }

    const promptText = isFirst && targetIntro
      ? `${targetIntro}\n\nKullanici: ${item.text || ''}`
      : (item.text || '');
    isFirst = false;

    const args = [
      'run',
      '--format', 'json',
      ...(targetModel ? ['-m', targetModel] : []),
      ...(sessionId ? ['-s', sessionId] : ['--title', 'Kevin']),
    ];

    let proc;
    try {
      proc = spawnCli('opencode', args, {
        cwd: os.tmpdir(),
        stdio: ['pipe', 'pipe', 'pipe'],
      });
    } catch (err) {
      item.reject(err);
      drainQueue();
      return;
    }

    activeProc = proc;
    let stdoutBuffer = '';
    const textParts = [];

    const timer = setTimeout(() => {
      if (activeTurn && activeTurn.timer === timer) {
        const rejFn = activeTurn.reject;
        activeTurn = null;
        if (activeProc) {
          try {
            activeProc.kill('SIGTERM');
          } catch {}
          activeProc = null;
        }
        rejFn(new Error('Tur zaman asimi (90 sn)'));
        drainQueue();
      }
    }, 90000);

    activeTurn = {
      resolve: item.resolve,
      reject: item.reject,
      timer,
    };

    proc.stdout.on('data', (chunk) => {
      stdoutBuffer += chunk.toString();
      let nl;
      while ((nl = stdoutBuffer.indexOf('\n')) >= 0) {
        const line = stdoutBuffer.slice(0, nl).trim();
        stdoutBuffer = stdoutBuffer.slice(nl + 1);
        if (!line) continue;
        try {
          const data = JSON.parse(line);
          if (data.sessionID && !sessionId) {
            sessionId = data.sessionID;
          }
          if (data.type === 'text' && data.part && typeof data.part.text === 'string') {
            textParts.push(data.part.text);
          }
        } catch {}
      }
    });

    proc.stderr.on('data', (chunk) => {
      logMsg(chunk.toString());
    });

    proc.on('error', (err) => {
      logMsg(`surec hatasi: ${err.message}`);
      if (activeTurn && activeTurn.timer === timer) {
        clearTimeout(timer);
        const rejFn = activeTurn.reject;
        activeTurn = null;
        activeProc = null;
        rejFn(err);
        drainQueue();
      }
    });

    proc.on('close', (code) => {
      if (!activeTurn || activeTurn.timer !== timer) return;
      clearTimeout(timer);
      const resFn = activeTurn.resolve;
      const rejFn = activeTurn.reject;
      activeTurn = null;
      activeProc = null;

      if (stdoutBuffer.trim()) {
        try {
          const data = JSON.parse(stdoutBuffer.trim());
          if (data.sessionID && !sessionId) {
            sessionId = data.sessionID;
          }
          if (data.type === 'text' && data.part && typeof data.part.text === 'string') {
            textParts.push(data.part.text);
          }
        } catch {}
      }

      if (code === 0) {
        const fullText = textParts.join('');
        if (!fullText.trim()) {
          rejFn(new Error('Bos cevap'));
        } else {
          resFn(fullText);
        }
      } else {
        rejFn(new Error(`opencode hata: kod ${code}`));
      }
      drainQueue();
    });

    try {
      proc.stdin.write(promptText);
      proc.stdin.end();
    } catch (err) {
      clearTimeout(timer);
      activeTurn = null;
      if (activeProc) {
        try {
          activeProc.kill('SIGTERM');
        } catch {}
        activeProc = null;
      }
      item.reject(err);
      drainQueue();
    }
  }

  function ask({ model, dirs, intro, text }) {
    return new Promise((resolve, reject) => {
      queue.push({
        model: model || '',
        dirs: Array.isArray(dirs) ? dirs : [],
        intro: intro || '',
        text: text || '',
        resolve,
        reject,
      });
      drainQueue();
    });
  }

  function warm() {}

  function stop() {
    sessionId = null;
    isFirst = true;
    if (activeProc) {
      try {
        activeProc.kill('SIGTERM');
      } catch {}
      activeProc = null;
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
  }

  return {
    ask,
    warm,
    stop,
  };
}

module.exports = {
  createClaudeBrain,
  createOpenCodeBrain,
  cliAvailable,
};
