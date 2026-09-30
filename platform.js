// Platforma bagli isler tek yerde. Kevin Windows + Linux hedefliyor;
// her yeni isletim sistemi icin sadece bu dosya genisletiliyor.

const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const isWindows = process.platform === 'win32';
const isMac = process.platform === 'darwin';
const isLinux = process.platform === 'linux';

const HOME = os.homedir();

function run(command, args, options = {}) {
  return new Promise((resolve) => {
    const proc = spawn(command, args, { ...options });
    let stdout = '';
    let stderr = '';
    proc.stdout?.on('data', (d) => (stdout += d));
    proc.stderr?.on('data', (d) => (stderr += d));
    proc.on('error', (err) => resolve({ ok: false, stdout, stderr: err.message }));
    proc.on('close', (code) => resolve({ ok: code === 0, code, stdout, stderr }));
  });
}

function runDetached(command, args, env) {
  return new Promise((resolve) => {
    try {
      const proc = spawn(command, args, {
        detached: true,
        stdio: 'ignore',
        env: env || { ...process.env },
      });
      proc.on('error', (err) => resolve({ ok: false, error: err.message }));
      proc.unref();
      setTimeout(() => resolve({ ok: true }), 400);
    } catch (err) {
      resolve({ ok: false, error: err.message });
    }
  });
}

function processRunning(name) {
  if (isWindows) {
    return run('tasklist', ['/FI', `IMAGENAME eq ${name}.exe`, '/NH']).then(
      (r) => r.stdout.toLowerCase().includes(name.toLowerCase()),
    );
  }
  return run('pgrep', ['-x', name]).then((r) => r.ok);
}

// --- Uygulama / adres acma ---

const DESKTOP_DIRS = [
  path.join(HOME, '.local/share/applications'),
  '/usr/share/applications',
  '/var/lib/flatpak/exports/share/applications',
  path.join(HOME, '.local/share/flatpak/exports/share/applications'),
];

function findDesktopEntry(name) {
  if (!isLinux) return null;
  const wanted = name.toLowerCase().trim();
  const candidates = [];

  for (const dir of DESKTOP_DIRS) {
    let entries;
    try {
      entries = fs.readdirSync(dir);
    } catch {
      continue;
    }
    for (const file of entries) {
      if (!file.endsWith('.desktop')) continue;
      const id = file.slice(0, -8);
      let displayName = '';
      try {
        const body = fs.readFileSync(path.join(dir, file), 'utf8');
        if (/^NoDisplay=true/m.test(body)) continue;
        const m = body.match(/^Name=(.+)$/m);
        displayName = m ? m[1].trim() : '';
      } catch {
        continue;
      }
      const idLower = id.toLowerCase();
      const nameLower = displayName.toLowerCase();
      let score = 0;
      if (idLower === wanted || nameLower === wanted) score = 100;
      else if (idLower.endsWith('.' + wanted) || nameLower.startsWith(wanted)) score = 80;
      else if (idLower.includes(wanted) || nameLower.includes(wanted)) score = 50;
      if (score) candidates.push({ id, displayName: displayName || id, score });
    }
  }
  candidates.sort((a, b) => b.score - a.score);
  return candidates[0] || null;
}

function openUrl(url) {
  if (isWindows) return runDetached('cmd', ['/c', 'start', '', url]);
  if (isMac) return runDetached('open', [url]);
  return runDetached('xdg-open', [url]);
}

// Windows'ta uygulama adini PowerShell cozuyor (Start-Process),
// Linux'ta .desktop girdisi + compositor.
async function launchApp(name, compositorExec) {
  const binary = name.split(/\s+/)[0];

  if (isWindows) {
    const result = await runDetached('powershell', [
      '-NoProfile', '-Command', `Start-Process -FilePath "${binary}"`,
    ]);
    if (result.ok && (await processRunning(binary))) return { ok: true, label: binary };
    return { ok: false, label: binary };
  }

  if (isMac) {
    const result = await runDetached('open', ['-a', name]);
    return { ok: result.ok, label: name };
  }

  const entry = findDesktopEntry(name);
  const label = entry ? entry.displayName : name;

  // Electron'dan dogrudan baslatilan GUI uygulamalari acilmiyor (kutuphane
  // yollari miras kaliyor); compositor baslatinca sorun kalmiyor.
  if (compositorExec) {
    if (await compositorExec(name)) {
      if (await processRunning(binary)) return { ok: true, label };
    }
    if (entry && (await compositorExec(`gtk-launch ${entry.id}`))) {
      if (await processRunning(entry.id.split('.').pop())) return { ok: true, label };
    }
  }

  const direct = await runDetached(binary, name.split(/\s+/).slice(1));
  if (direct.ok && (await processRunning(binary))) return { ok: true, label };
  return { ok: false, label, installed: Boolean(entry) };
}

// --- Ekran goruntusu ---

async function captureScreen(outPath, scale = 0.5) {
  if (isWindows) {
    const script = `
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
$w = [int]($b.Width * ${scale}); $h = [int]($b.Height * ${scale})
$small = New-Object System.Drawing.Bitmap $bmp, $w, $h
$small.Save('${outPath.replace(/\\/g, '\\\\')}', [System.Drawing.Imaging.ImageFormat]::Png)`;
    const r = await run('powershell', ['-NoProfile', '-Command', script]);
    return r.ok;
  }

  if (isMac) {
    const r = await run('screencapture', ['-x', outPath]);
    return r.ok;
  }

  let r = await run('grim', ['-s', String(scale), '-l', '0', outPath]);
  if (!r.ok) r = await run('import', ['-window', 'root', outPath]); // X11 yedegi
  return r.ok;
}

module.exports = {
  isWindows,
  isMac,
  isLinux,
  run,
  runDetached,
  processRunning,
  findDesktopEntry,
  openUrl,
  launchApp,
  captureScreen,
  HOME,
};
