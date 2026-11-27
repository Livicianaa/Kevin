const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

function isNewer(remote, current) {
  const r = (remote || '').replace(/^v/, '').split('.').map((n) => parseInt(n, 10) || 0);
  const c = (current || '').replace(/^v/, '').split('.').map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < 3; i++) {
    const rv = r[i] || 0;
    const cv = c[i] || 0;
    if (rv > cv) return true;
    if (rv < cv) return false;
  }
  return false;
}

function psQuote(val) {
  return "'" + String(val).replace(/'/g, "''") + "'";
}

async function downloadFile(url, destPath, expectedSize, onProgress) {
  const res = await fetch(url, {
    headers: { 'User-Agent': 'Kevin-Updater' },
    redirect: 'follow',
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const total = Number(res.headers.get('content-length')) || expectedSize || 0;
  const reader = res.body.getReader();
  const fileStream = fs.createWriteStream(destPath);
  let loaded = 0;
  let lastProgress = 0;

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      loaded += value.length;
      if (!fileStream.write(Buffer.from(value))) {
        await new Promise((resolve) => fileStream.once('drain', resolve));
      }
      const now = Date.now();
      if (onProgress && total > 0 && (now - lastProgress >= 250 || loaded === total)) {
        lastProgress = now;
        onProgress(Math.min(1, loaded / total));
      }
    }
    await new Promise((resolve, reject) => {
      fileStream.end((err) => (err ? reject(err) : resolve()));
    });
    if (onProgress) onProgress(1);
  } catch (err) {
    fileStream.destroy();
    try { fs.unlinkSync(destPath); } catch {}
    throw err;
  }
}

function createUpdater({ app, log }) {
  async function check() {
    if (!app.isPackaged) return { available: false };
    try {
      const res = await fetch('https://api.github.com/repos/Livicianaa/Kevin/releases/latest', {
        headers: {
          'User-Agent': 'Kevin-Updater',
          'Accept': 'application/vnd.github+json',
        },
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      const rawTag = data.tag_name || '';
      const version = rawTag.replace(/^v/, '');
      if (!isNewer(version, app.getVersion())) {
        return { available: false };
      }

      let targetName = null;
      if (process.platform === 'win32') {
        targetName = 'Kevin-Windows.zip';
      } else if (process.platform === 'linux' && process.env.APPIMAGE) {
        targetName = 'Kevin-x86_64.AppImage';
      } else {
        return { available: false };
      }

      const asset = Array.isArray(data.assets) ? data.assets.find((a) => a.name === targetName) : null;
      if (!asset || !asset.browser_download_url) {
        return { available: false };
      }

      return {
        available: true,
        version,
        url: asset.browser_download_url,
        size: asset.size || 0,
      };
    } catch (err) {
      return { available: false, error: err.message || String(err) };
    }
  }

  async function install(onProgress) {
    const res = await check();
    if (!res || !res.available || !res.url) {
      throw new Error(res?.error || 'Guncelleme bulunamadi');
    }

    if (process.platform === 'win32') {
      const zipPath = path.join(os.tmpdir(), 'Kevin-Windows.zip');
      await downloadFile(res.url, zipPath, res.size, onProgress);

      const installDir = path.dirname(process.execPath);
      const extractDir = path.join(os.tmpdir(), 'kevin-yeni');
      const ps1Path = path.join(os.tmpdir(), 'kevin-guncelle.ps1');

      const psScript = [
        'Start-Sleep -Seconds 3',
        `Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith(${psQuote(installDir)}, 'OrdinalIgnoreCase') } | Stop-Process -Force`,
        `Expand-Archive -Path ${psQuote(zipPath)} -DestinationPath ${psQuote(extractDir)} -Force`,
        `robocopy ${psQuote(path.join(extractDir, 'Kevin'))} ${psQuote(installDir)} /E /R:3 /W:1 /NFL /NDL /NJH /NJS`,
        `Start-Process ${psQuote(path.join(installDir, 'Kevin.exe'))}`,
        `Remove-Item -Path ${psQuote(zipPath)} -Force -ErrorAction SilentlyContinue`,
        `Remove-Item -Path ${psQuote(extractDir)} -Recurse -Force -ErrorAction SilentlyContinue`,
      ].join('\r\n') + '\r\n';

      fs.writeFileSync(ps1Path, '\uFEFF' + psScript, 'utf8');

      const child = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ps1Path], {
        detached: true,
        stdio: 'ignore',
        windowsHide: true,
      });
      child.unref();
      return true;
    }

    if (process.platform === 'linux' && process.env.APPIMAGE) {
      const appImagePath = process.env.APPIMAGE;
      const newAppImage = appImagePath + '.yeni';
      await downloadFile(res.url, newAppImage, res.size, onProgress);
      fs.chmodSync(newAppImage, 0o755);
      fs.renameSync(newAppImage, appImagePath);
      const child = spawn('sh', ['-c', 'sleep 4; exec "$0"', appImagePath], { detached: true, stdio: 'ignore' });
      child.unref();
      return true;
    }

    return false;
  }

  return { check, install };
}

module.exports = { createUpdater };
