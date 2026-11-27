const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn, execSync, execFileSync } = require('child_process');
const fflate = require('fflate');

function cleanVoiceName(filePath) {
  let name = path.basename(filePath, path.extname(filePath));
  name = name.replace(/_(?:e\d+_s\d+|\d+e_\d+s|epoch\d+|step\d+|e\d+|s\d+|\d+e|\d+s)(?=_|$)/ig, '');
  name = name.replace(/[_-]+/g, ' ').trim();
  return name || 'ses';
}

function toSlug(text) {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function getFileSignature(filePath) {
  const stat = fs.statSync(filePath);
  const size = stat.size;
  const readSize = Math.min(size, 1024 * 1024);
  const buffer = Buffer.alloc(readSize);
  const fd = fs.openSync(filePath, 'r');
  fs.readSync(fd, buffer, 0, readSize, 0);
  fs.closeSync(fd);
  const sha1 = crypto.createHash('sha1').update(buffer).digest('hex');
  return { size, sha1, key: `${size}:${sha1}` };
}

function extractZipBuffer(zipBuf, targetDir, stripRoot = false) {
  return new Promise((resolve, reject) => {
    fflate.unzip(zipBuf, (err, unzipped) => {
      if (err) return reject(err);
      try {
        for (const [name, data] of Object.entries(unzipped)) {
          if (!data || name.endsWith('/')) continue;
          let rel = name;
          if (stripRoot) {
            const parts = name.split('/');
            if (parts.length <= 1) continue;
            parts.shift();
            rel = parts.join('/');
          }
          if (!rel) continue;
          const outPath = path.join(targetDir, rel);
          fs.mkdirSync(path.dirname(outPath), { recursive: true });
          fs.writeFileSync(outPath, Buffer.from(data));
        }
        resolve();
      } catch (e) {
        reject(e);
      }
    });
  });
}

async function downloadFile(url, destPath, onProgress) {
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) {
    throw new Error(`İndirme başarısız (${res.status}): ${url}`);
  }
  const total = parseInt(res.headers.get('content-length') || '0', 10);
  const tempPath = destPath + '.part';
  fs.mkdirSync(path.dirname(destPath), { recursive: true });
  const fileStream = fs.createWriteStream(tempPath);
  let loaded = 0;

  if (res.body) {
    for await (const chunk of res.body) {
      loaded += chunk.length;
      fileStream.write(Buffer.from(chunk));
      if (total > 0 && typeof onProgress === 'function') {
        onProgress(loaded / total);
      }
    }
    await new Promise((resolve, reject) => {
      fileStream.end((err) => (err ? reject(err) : resolve()));
    });
  } else {
    const buf = Buffer.from(await res.arrayBuffer());
    fs.writeFileSync(tempPath, buf);
  }
  fs.renameSync(tempPath, destPath);
}

function runCmd(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const cp = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'], ...opts });
    let errOutput = '';
    cp.stderr.on('data', (d) => { errOutput += d.toString(); });
    cp.on('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`Komut başarısız (${cmd} ${args.join(' ')}, kod: ${code}): ${errOutput.slice(-300)}`));
    });
    cp.on('error', reject);
  });
}

function createVoices({ userDir, log, searchHome }) {
  const isWin = process.platform === 'win32';
  const voicesDir = path.join(userDir, 'voices');

  let rvcProc = null;
  let rvcReadyPromise = null;
  let rvcReadyResolve = null;
  let rvcReadyReject = null;
  let stderrBuffer = [];
  let idleTimer = null;
  let currentJob = null;
  const jobQueue = [];

  let isInstalling = false;
  let installProgress = 0;
  let installText = '';
  let activeInstallPromise = null;
  let forceCpu = false;

  function getStderrSnippet() {
    if (stderrBuffer.length === 0) return '';
    return '\n' + stderrBuffer.slice(-20).join('\n');
  }

  function stopProcess() {
    if (rvcProc) {
      try { rvcProc.kill(); } catch {}
      rvcProc = null;
    }
    rvcReadyPromise = null;
    rvcReadyResolve = null;
    rvcReadyReject = null;
  }

  function resetIdleTimer() {
    if (idleTimer) {
      clearTimeout(idleTimer);
      idleTimer = null;
    }
  }

  function startIdleTimer() {
    resetIdleTimer();
    idleTimer = setTimeout(() => {
      if (!currentJob && jobQueue.length === 0) {
        stopProcess();
        forceCpu = false;
      }
    }, 10 * 60 * 1000);
    if (idleTimer.unref) idleTimer.unref();
  }

  function gpuFreeMb() {
    try {
      const out = execFileSync('nvidia-smi', ['--query-gpu=memory.free', '--format=csv,noheader,nounits'], { timeout: 3000, encoding: 'utf8' });
      const mb = parseInt(String(out).trim().split('\n')[0], 10);
      return Number.isFinite(mb) ? mb : Infinity;
    } catch {
      return Infinity;
    }
  }

  function ensureProcess(runtime) {
    if (rvcProc && rvcReadyPromise) {
      return rvcReadyPromise;
    }
    stopProcess();
    stderrBuffer = [];
    const scriptPath = path.join(__dirname, 'rvc', 'kevin_rvc.py');
    const env = { ...process.env, PYTHONUNBUFFERED: '1' };
    if (!runtime.cpu && !forceCpu && gpuFreeMb() < 1800) {
      forceCpu = true;
      if (log) log('[rvc] GPU bellegi az, islemcide baslatiliyor');
    }
    if (runtime.cpu || forceCpu) env.CUDA_VISIBLE_DEVICES = '';
    const proc = spawn(runtime.python, [scriptPath, runtime.applio], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env,
    });
    rvcProc = proc;

    let stdoutRemainder = '';
    proc.stdout.on('data', (chunk) => {
      if (rvcProc !== proc) return;
      stdoutRemainder += chunk.toString('utf8');
      const lines = stdoutRemainder.split('\n');
      stdoutRemainder = lines.pop();
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        try {
          const msg = JSON.parse(trimmed);
          if (msg.ready && rvcReadyResolve) {
            rvcReadyResolve();
            rvcReadyResolve = null;
            rvcReadyReject = null;
          } else if (currentJob && currentJob.id === msg.id) {
            clearTimeout(currentJob.timer);
            const job = currentJob;
            currentJob = null;
            if (msg.ok) {
              job.resolve(msg);
            } else {
              job.reject(new Error((msg.error || 'Dönüştürme başarısız') + getStderrSnippet()));
            }
            processNextJob();
          }
        } catch (err) {
          if (typeof log === 'function') log(`[rvc stdout err] ${err.message}`);
        }
      }
    });

    let stderrRemainder = '';
    proc.stderr.on('data', (chunk) => {
      stderrRemainder += chunk.toString('utf8');
      const lines = stderrRemainder.split('\n');
      stderrRemainder = lines.pop();
      for (const line of lines) {
        if (!line) continue;
        stderrBuffer.push(line);
        if (stderrBuffer.length > 20) stderrBuffer.shift();
        if (typeof log === 'function') log(`[rvc stderr] ${line}`);
      }
    });

    function onExitOrError(err) {
      if (rvcProc !== proc) return;
      if (rvcReadyReject) {
        rvcReadyReject(err || new Error('RVC süreci başlatılamadı' + getStderrSnippet()));
        rvcReadyResolve = null;
        rvcReadyReject = null;
      }
      if (currentJob) {
        clearTimeout(currentJob.timer);
        const job = currentJob;
        currentJob = null;
        job.reject(new Error((err ? err.message : 'RVC süreci çöktü') + getStderrSnippet()));
      }
      while (jobQueue.length > 0) {
        const qJob = jobQueue.shift();
        if (qJob.timer) clearTimeout(qJob.timer);
        qJob.reject(new Error('RVC süreci sonlandı' + getStderrSnippet()));
      }
      stopProcess();
      startIdleTimer();
    }

    proc.on('error', onExitOrError);
    proc.on('exit', (code, signal) => {
      onExitOrError(new Error(`RVC süreci sonlandı (kod: ${code}, sinyal: ${signal})`));
    });

    rvcReadyPromise = new Promise((resolve, reject) => {
      rvcReadyResolve = resolve;
      rvcReadyReject = reject;
      const timeout = setTimeout(() => {
        if (rvcReadyReject) {
          rvcReadyReject(new Error('RVC hazır olma zaman aşımı (120 sn)' + getStderrSnippet()));
          stopProcess();
        }
      }, 120 * 1000);
      if (timeout.unref) timeout.unref();
    });

    return rvcReadyPromise;
  }

  function processNextJob() {
    if (currentJob) return;
    if (jobQueue.length > 0 && !rvcProc) {
      while (jobQueue.length > 0) jobQueue.shift().reject(new Error('RVC süreci kapandı'));
    }
    if (jobQueue.length === 0) {
      startIdleTimer();
      return;
    }
    resetIdleTimer();
    currentJob = jobQueue.shift();
    currentJob.timer = setTimeout(() => {
      const err = new Error('RVC dönüştürme zaman aşımı (90 sn)' + getStderrSnippet());
      stopProcess();
      const job = currentJob;
      currentJob = null;
      if (job) job.reject(err);
      processNextJob();
    }, 90 * 1000);
    if (currentJob.timer.unref) currentJob.timer.unref();

    try {
      rvcProc.stdin.write(JSON.stringify(currentJob.payload) + '\n');
    } catch (err) {
      clearTimeout(currentJob.timer);
      const job = currentJob;
      currentJob = null;
      job.reject(new Error((err ? err.message : 'Yazma hatası') + getStderrSnippet()));
      processNextJob();
    }
  }

  function findExistingVoiceByHash(sigKey) {
    if (!fs.existsSync(voicesDir)) return null;
    const entries = fs.readdirSync(voicesDir, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      const metaPath = path.join(voicesDir, entry.name, 'meta.json');
      if (!fs.existsSync(metaPath)) continue;
      try {
        const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
        if (meta.hash === sigKey) return meta;
        if (meta.model && fs.existsSync(meta.model)) {
          const mSig = getFileSignature(meta.model);
          if (mSig.key === sigKey) return meta;
        }
      } catch {}
    }
    return null;
  }

  function list() {
    if (!fs.existsSync(voicesDir)) return [];
    const entries = fs.readdirSync(voicesDir, { withFileTypes: true });
    const results = [];
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      const metaPath = path.join(voicesDir, entry.name, 'meta.json');
      if (!fs.existsSync(metaPath)) continue;
      try {
        const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
        results.push({
          id: meta.id || entry.name,
          name: meta.name || entry.name,
          type: meta.type || 'rvc',
          pitch: meta.pitch ?? null,
          target_hz: meta.target_hz ?? 155,
        });
      } catch {}
    }
    return results;
  }

  function get(id) {
    if (!id) return null;
    const metaPath = path.join(voicesDir, id, 'meta.json');
    if (!fs.existsSync(metaPath)) return null;
    try {
      const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
      const voiceFolder = path.join(voicesDir, id);
      if (meta.model && !path.isAbsolute(meta.model)) {
        meta.model = path.join(voiceFolder, meta.model);
      }
      if (meta.index && !path.isAbsolute(meta.index)) {
        meta.index = path.join(voiceFolder, meta.index);
      }
      if (meta.config && !path.isAbsolute(meta.config)) {
        meta.config = path.join(voiceFolder, meta.config);
      }
      return meta;
    } catch {
      return null;
    }
  }

  function setPitch(id, pitch, target_hz) {
    if (!id) return { ok: false, error: 'Geçersiz ses kimliği' };
    const metaPath = path.join(voicesDir, id, 'meta.json');
    if (!fs.existsSync(metaPath)) return { ok: false, error: 'Ses bulunamadı' };
    try {
      const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
      meta.pitch = pitch === undefined ? meta.pitch : pitch;
      if (target_hz !== undefined) {
        meta.target_hz = target_hz;
      }
      fs.writeFileSync(metaPath, JSON.stringify(meta, null, 2), 'utf8');
      return { ok: true, voice: meta };
    } catch (err) {
      return { ok: false, error: err.message };
    }
  }

  function remove(id) {
    if (!id) return { ok: false, error: 'Geçersiz ses kimliği' };
    const voiceFolder = path.join(voicesDir, id);
    if (!fs.existsSync(voiceFolder)) return { ok: false, error: 'Ses bulunamadı' };
    try {
      fs.rmSync(voiceFolder, { recursive: true, force: true });
      return { ok: true };
    } catch (err) {
      return { ok: false, error: err.message };
    }
  }

  function install(paths) {
    const files = (Array.isArray(paths) ? paths : [paths]).map(p => path.resolve(p));
    if (files.length === 0) return { ok: false, error: 'Dosya belirtilmedi' };

    const pthFile = files.find(f => f.toLowerCase().endsWith('.pth'));
    const onnxFile = files.find(f => f.toLowerCase().endsWith('.onnx') && !f.toLowerCase().endsWith('.onnx.json'));

    if (pthFile) {
      const base = path.basename(pthFile);
      if (/^[GD]_/i.test(base)) {
        return { ok: false, error: 'Bu eğitim dosyası, ses modeli değil (adı ..._e100_s....pth gibi olanı seç)' };
      }
      if (!fs.existsSync(pthFile)) return { ok: false, error: 'Model dosyası bulunamadı' };
      const stat = fs.statSync(pthFile);
      if (stat.size < 10 * 1024 * 1024 || stat.size > 1024 * 1024 * 1024) {
        return { ok: false, error: 'Model dosyası boyutu geçersiz (10 MB - 1 GB arası olmalı)' };
      }

      let indexFile = files.find(f => f.toLowerCase().endsWith('.index'));
      if (!indexFile) {
        const pthDir = path.dirname(pthFile);
        if (fs.existsSync(pthDir)) {
          const dirEntries = fs.readdirSync(pthDir);
          const indexCandidates = dirEntries.filter(f => f.toLowerCase().endsWith('.index'));
          if (indexCandidates.length === 1) {
            indexFile = path.join(pthDir, indexCandidates[0]);
          } else if (indexCandidates.length > 1) {
            const rawBase = path.basename(pthFile, path.extname(pthFile));
            const modelPrefix = rawBase.split(/[_-\s]+/)[0].toLowerCase();
            const matched = indexCandidates.find(f => f.toLowerCase().includes(modelPrefix));
            if (matched) {
              indexFile = path.join(pthDir, matched);
            }
          }
        }
      }

      const sig = getFileSignature(pthFile);
      const existing = findExistingVoiceByHash(sig.key);
      if (existing) {
        return { ok: true, voice: existing };
      }

      const name = cleanVoiceName(pthFile);
      const slug = toSlug(name) || 'rvc-voice';
      const id = `${slug}-${sig.sha1.slice(0, 6)}`;
      const voiceFolder = path.join(voicesDir, id);
      fs.mkdirSync(voiceFolder, { recursive: true });

      const targetModel = path.join(voiceFolder, path.basename(pthFile));
      fs.copyFileSync(pthFile, targetModel);

      let targetIndex = null;
      if (indexFile && fs.existsSync(indexFile)) {
        targetIndex = path.join(voiceFolder, path.basename(indexFile));
        fs.copyFileSync(indexFile, targetIndex);
      }

      const meta = {
        id,
        name,
        type: 'rvc',
        model: targetModel,
        index: targetIndex,
        config: null,
        pitch: null,
        target_hz: 155,
        added: Date.now(),
        hash: sig.key
      };
      fs.writeFileSync(path.join(voiceFolder, 'meta.json'), JSON.stringify(meta, null, 2), 'utf8');
      return { ok: true, voice: meta };
    }

    if (onnxFile) {
      if (!fs.existsSync(onnxFile)) return { ok: false, error: 'Model dosyası bulunamadı' };
      let configFile = files.find(f => f.toLowerCase().endsWith('.onnx.json') || (f.toLowerCase().endsWith('.json') && !f.toLowerCase().endsWith('meta.json')));
      if (!configFile) {
        const onnxDir = path.dirname(onnxFile);
        const onnxBase = path.basename(onnxFile);
        const candidate1 = path.join(onnxDir, onnxBase + '.json');
        const candidate2 = path.join(onnxDir, path.basename(onnxFile, '.onnx') + '.onnx.json');
        const candidate3 = path.join(onnxDir, path.basename(onnxFile, '.onnx') + '.json');
        if (fs.existsSync(candidate1)) configFile = candidate1;
        else if (fs.existsSync(candidate2)) configFile = candidate2;
        else if (fs.existsSync(candidate3)) configFile = candidate3;
      }

      if (!configFile || !fs.existsSync(configFile)) {
        return { ok: false, error: 'onnx.json eksik' };
      }

      const sig = getFileSignature(onnxFile);
      const existing = findExistingVoiceByHash(sig.key);
      if (existing) {
        return { ok: true, voice: existing };
      }

      const name = cleanVoiceName(onnxFile);
      const slug = toSlug(name) || 'piper-voice';
      const id = `${slug}-${sig.sha1.slice(0, 6)}`;
      const voiceFolder = path.join(voicesDir, id);
      fs.mkdirSync(voiceFolder, { recursive: true });

      const targetModel = path.join(voiceFolder, path.basename(onnxFile));
      fs.copyFileSync(onnxFile, targetModel);

      const targetConfig = path.join(voiceFolder, path.basename(configFile));
      fs.copyFileSync(configFile, targetConfig);

      const meta = {
        id,
        name,
        type: 'piper',
        model: targetModel,
        index: null,
        config: targetConfig,
        pitch: null,
        target_hz: 155,
        added: Date.now(),
        hash: sig.key
      };
      fs.writeFileSync(path.join(voiceFolder, 'meta.json'), JSON.stringify(meta, null, 2), 'utf8');
      return { ok: true, voice: meta };
    }

    return { ok: false, error: 'Desteklenen ses modeli dosyası (.pth veya .onnx) bulunamadı' };
  }

  let localApplio = null;
  function findLocalApplio() {
    if (localApplio) return localApplio;
    const home = searchHome || require('os').homedir();
    const found = [];
    const look = (dir, depth) => {
      let entries;
      try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
      for (const e of entries) {
        if (!e.isDirectory() || e.name.startsWith('.') || e.name === 'node_modules') continue;
        const full = path.join(dir, e.name);
        if (/^applio/i.test(e.name) && fs.existsSync(path.join(full, 'rvc', 'infer', 'infer.py'))) found.push(full);
        else if (depth > 0) look(full, depth - 1);
      }
    };
    look(home, 2);
    localApplio = found;
    return found;
  }

  function rvcRuntime(cfg) {
    const candidates = [
      cfg && cfg.rvcApplio,
      process.env.KEVIN_RVC_APPLIO,
      path.join(userDir, 'rvc', 'Applio'),
      ...findLocalApplio()
    ].filter(Boolean);

    for (const applio of candidates) {
      if (!fs.existsSync(applio)) continue;

      const inferPy = path.join(applio, 'rvc', 'infer', 'infer.py');
      const rmvpePt = path.join(applio, 'rvc', 'models', 'predictors', 'rmvpe.pt');
      const contentvecBin = path.join(applio, 'rvc', 'models', 'embedders', 'contentvec', 'pytorch_model.bin');

      if (!fs.existsSync(inferPy) || !fs.existsSync(rmvpePt) || !fs.existsSync(contentvecBin)) {
        continue;
      }

      const venvPy = isWin
        ? path.join(applio, '.venv', 'Scripts', 'python.exe')
        : path.join(applio, '.venv', 'bin', 'python');
      const userVenvPy = isWin
        ? path.join(userDir, 'rvc', 'venv', 'Scripts', 'python.exe')
        : path.join(userDir, 'rvc', 'venv', 'bin', 'python');

      let python = null;
      if (fs.existsSync(venvPy)) {
        python = venvPy;
      } else if (fs.existsSync(userVenvPy)) {
        python = userVenvPy;
      }

      if (python) {
        return { python, applio, cpu: cfg && cfg.rvcDevice === 'cpu' };
      }
    }

    return null;
  }

  async function convert(cfg, voice, inWav, outWav) {
    try {
      return await convertOnce(cfg, voice, inWav, outWav);
    } catch (err) {
      if (forceCpu || !/out of memory|CUDA error/i.test(String(err && err.message))) throw err;
      if (log) log('[rvc] GPU bellegi dolu, islemciye geciliyor');
      forceCpu = true;
      stopProcess();
      return convertOnce(cfg, voice, inWav, outWav);
    }
  }

  function convertOnce(cfg, voice, inWav, outWav) {
    return new Promise(async (resolve, reject) => {
      const runtime = rvcRuntime(cfg);
      if (!runtime) {
        return reject(new Error('RVC çalışma ortamı bulunamadı'));
      }
      if (!voice) {
        return reject(new Error('Ses nesnesi belirtilmedi'));
      }
      const voiceFolder = voice.id ? path.join(voicesDir, voice.id) : '';
      const modelPath = path.isAbsolute(voice.model)
        ? voice.model
        : (voiceFolder ? path.join(voiceFolder, voice.model) : voice.model);
      if (!fs.existsSync(modelPath)) {
        return reject(new Error('Ses modeli dosyası bulunamadı'));
      }
      let indexPath = '';
      if (voice.index) {
        indexPath = path.isAbsolute(voice.index)
          ? voice.index
          : (voiceFolder ? path.join(voiceFolder, voice.index) : voice.index);
      }

      try {
        await ensureProcess(runtime);
      } catch (err) {
        return reject(err);
      }

      const jobId = crypto.randomUUID ? crypto.randomUUID() : String(Date.now() + Math.random());
      jobQueue.push({
        id: jobId,
        resolve,
        reject,
        payload: {
          id: jobId,
          input: inWav,
          output: outWav,
          model: modelPath,
          index: indexPath,
          pitch: voice.pitch !== undefined ? voice.pitch : null,
          target_hz: voice.target_hz || 155,
          index_rate: 0.6
        }
      });
      processNextJob();
    });
  }

  function installRvc(onProgress) {
    if (activeInstallPromise) {
      return activeInstallPromise;
    }
    activeInstallPromise = (async () => {
      isInstalling = true;
      function report(progress, text) {
        installProgress = progress;
        installText = text;
        if (typeof onProgress === 'function') {
          onProgress({ progress, text });
        }
      }
      try {
        const rvcDir = path.join(userDir, 'rvc');
        const binDir = path.join(rvcDir, 'bin');
        const applioDir = path.join(rvcDir, 'Applio');
        const pythonInstallDir = path.join(rvcDir, 'python');
        fs.mkdirSync(rvcDir, { recursive: true });
        fs.mkdirSync(binDir, { recursive: true });

        const uvBin = isWin ? path.join(binDir, 'uv.exe') : path.join(binDir, 'uv');
        if (!fs.existsSync(uvBin)) {
          report(0.05, 'uv indiriliyor...');
          const uvUrl = isWin
            ? 'https://github.com/astral-sh/uv/releases/download/0.6.0/uv-x86_64-pc-windows-msvc.zip'
            : 'https://github.com/astral-sh/uv/releases/download/0.6.0/uv-x86_64-unknown-linux-gnu.tar.gz';
          const uvArchive = path.join(binDir, isWin ? 'uv.zip' : 'uv.tar.gz');
          await downloadFile(uvUrl, uvArchive, (p) => report(0.05 + p * 0.1, 'uv indiriliyor...'));
          if (isWin) {
            const zipBuf = fs.readFileSync(uvArchive);
            await extractZipBuffer(zipBuf, binDir, false);
          } else {
            execSync(`tar -xzf "${uvArchive}" -C "${binDir}"`);
            const extractedSub = path.join(binDir, 'uv-x86_64-unknown-linux-gnu', 'uv');
            if (fs.existsSync(extractedSub)) {
              fs.renameSync(extractedSub, uvBin);
            }
            if (fs.existsSync(uvBin)) {
              fs.chmodSync(uvBin, 0o755);
            }
          }
          try { fs.rmSync(uvArchive, { force: true }); } catch {}
        }

        const inferScript = path.join(applioDir, 'rvc', 'infer', 'infer.py');
        if (!fs.existsSync(inferScript)) {
          report(0.2, 'Applio kaynak kodu indiriliyor...');
          const applioZip = path.join(rvcDir, 'applio.zip');
          let applioUrl = 'https://github.com/IAHispano/Applio/archive/refs/tags/3.6.5.zip';
          try {
            await downloadFile(applioUrl, applioZip, (p) => report(0.2 + p * 0.15, 'Applio kaynak kodu indiriliyor...'));
          } catch {
            applioUrl = 'https://github.com/IAHispano/Applio/archive/refs/heads/main.zip';
            await downloadFile(applioUrl, applioZip, (p) => report(0.2 + p * 0.15, 'Applio kaynak kodu indiriliyor...'));
          }
          report(0.35, 'Applio arşivden çıkarılıyor...');
          const zipBuf = fs.readFileSync(applioZip);
          await extractZipBuffer(zipBuf, applioDir, true);
          try { fs.rmSync(applioZip, { force: true }); } catch {}
        }

        const venvDir = path.join(applioDir, '.venv');
        const py = isWin
          ? path.join(venvDir, 'Scripts', 'python.exe')
          : path.join(venvDir, 'bin', 'python');
        if (!fs.existsSync(py)) {
          report(0.4, 'Python 3.12 ortamı oluşturuluyor...');
          fs.mkdirSync(pythonInstallDir, { recursive: true });
          await runCmd(uvBin, ['venv', '--python', '3.12', venvDir], {
            env: Object.assign({}, process.env, { UV_PYTHON_INSTALL_DIR: pythonInstallDir })
          });
        }

        let torchOk = false;
        try {
          execFileSync(py, ['-c', 'import torch, torchaudio'], { stdio: 'ignore' });
          torchOk = true;
        } catch {}

        if (!torchOk) {
          report(0.55, 'PyTorch kuruluyor...');
          let hasNvidia = false;
          try {
            execSync('nvidia-smi', { stdio: 'ignore' });
            hasNvidia = true;
          } catch {}
          const indexUrl = hasNvidia
            ? 'https://download.pytorch.org/whl/cu128'
            : 'https://download.pytorch.org/whl/cpu';
          await runCmd(uvBin, [
            'pip', 'install', '--python', py,
            'torch==2.11.0', 'torchaudio==2.11.0',
            '--index-url', indexUrl
          ]);
        }

        report(0.7, 'RVC bağımlılıkları kuruluyor...');
        const defaultDeps = [
          'numpy',
          'librosa==0.11.0',
          'scipy',
          'soundfile',
          'soxr',
          'noisereduce',
          'pedalboard',
          'stftpitchshift',
          'faiss-cpu',
          'transformers==5.13.1',
          'torchcrepe',
          'torchfcpe',
          'einops',
          'requests',
          'tqdm'
        ];
        const reqPath = path.join(applioDir, 'requirements.txt');
        let finalDeps = defaultDeps;
        if (fs.existsSync(reqPath)) {
          const reqLines = fs.readFileSync(reqPath, 'utf8')
            .split('\n')
            .map(l => l.trim())
            .filter(l => l && !l.startsWith('#'));
          const reqMap = new Map();
          for (const line of reqLines) {
            const name = line.split(/[=<>~!]/)[0].trim().toLowerCase();
            reqMap.set(name, line);
          }
          finalDeps = defaultDeps.map(dep => {
            const name = dep.split(/[=<>~!]/)[0].trim().toLowerCase();
            return reqMap.get(name) || dep;
          });
        }
        await runCmd(uvBin, ['pip', 'install', '--python', py, ...finalDeps]);

        report(0.85, 'Temel modeller kontrol ediliyor...');
        const modelsToDownload = [
          {
            url: 'https://huggingface.co/IAHispano/Applio/resolve/main/Resources/predictors/rmvpe.pt',
            dest: path.join(applioDir, 'rvc', 'models', 'predictors', 'rmvpe.pt')
          },
          {
            url: 'https://huggingface.co/IAHispano/Applio/resolve/main/Resources/embedders/contentvec/pytorch_model.bin',
            dest: path.join(applioDir, 'rvc', 'models', 'embedders', 'contentvec', 'pytorch_model.bin')
          },
          {
            url: 'https://huggingface.co/IAHispano/Applio/resolve/main/Resources/embedders/contentvec/config.json',
            dest: path.join(applioDir, 'rvc', 'models', 'embedders', 'contentvec', 'config.json')
          }
        ];

        for (let i = 0; i < modelsToDownload.length; i++) {
          const item = modelsToDownload[i];
          if (!fs.existsSync(item.dest) || fs.statSync(item.dest).size === 0) {
            report(0.85 + (i / modelsToDownload.length) * 0.1, `${path.basename(item.dest)} indiriliyor...`);
            await downloadFile(item.url, item.dest, (p) => {
              report(0.85 + ((i + p) / modelsToDownload.length) * 0.1, `${path.basename(item.dest)} indiriliyor...`);
            });
          }
        }

        report(0.98, 'RVC doğrulanıyor...');
        execFileSync(py, [
          '-c',
          `import sys; sys.path.insert(0,'${applioDir}'); import os; os.chdir('${applioDir}'); from rvc.infer.infer import VoiceConverter`
        ], { stdio: 'pipe' });

        report(1.0, 'RVC hazır');
        return { ok: true };
      } catch (err) {
        report(installProgress, `Kurulum hatası: ${err.message}`);
        throw err;
      } finally {
        isInstalling = false;
        activeInstallPromise = null;
      }
    })();
    return activeInstallPromise;
  }

  function rvcStatus(cfg) {
    const runtime = rvcRuntime(cfg);
    return {
      ready: runtime !== null,
      installing: isInstalling,
      progress: installProgress,
      text: installText || (runtime !== null ? 'RVC hazır' : 'RVC kurulu değil')
    };
  }

  return {
    list,
    install,
    remove,
    setPitch,
    get,
    rvcRuntime,
    convert,
    installRvc,
    rvcStatus
  };
}

createVoices.createVoices = createVoices;
module.exports = { createVoices };
