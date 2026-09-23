const net = require('net');
const fs = require('fs');

const SIGNATURE = process.env.HYPRLAND_INSTANCE_SIGNATURE;
const SOCKET = SIGNATURE
  ? `${process.env.XDG_RUNTIME_DIR}/hypr/${SIGNATURE}/.socket.sock`
  : null;

const WINDOW_CLASS = 'kevin-pc-version';
const MATCH = `class:^(${WINDOW_CLASS})$`;

// Hyprland 0.56'da kural sozdizimi: `windowrule = <alan> <deger>, match:<sec>`
// (snake_case alan adlari). `hyprctl keyword windowrule ...` matcher'i kabul
// etmiyor; calisan yol kurallari bir dosyaya yazip `source` etmek.
// Dosya gecici: Hyprland yeniden baslatilinca gider, kullanicinin config'ine dokunmuyoruz.
const WINDOW_RULES = [
  'float 1',
  'pin 1',
  'no_blur 1',
  'no_shadow 1',
  'no_anim 1',
  'no_dim 1',
  'no_initial_focus 1',
];

// Acik pencereye dogrudan uygulanabilenler (kural dosyasi pencere acilmadan once
// yuklenemezse bunlar yine de isi kurtariyor).
const WINDOW_PROPS = ['decorate 0', 'rounding 0', 'opaque 0'];

function available() {
  return Boolean(SOCKET);
}

function send(payload) {
  return new Promise((resolve, reject) => {
    if (!SOCKET) return reject(new Error('Hyprland yok'));
    const sock = net.connect(SOCKET, () => sock.write(payload));
    let out = '';
    sock.on('data', (d) => (out += d));
    sock.on('end', () => resolve(out.trim()));
    sock.on('error', reject);
  });
}

async function json(what) {
  return JSON.parse(await send(`j/${what}`));
}

async function writeRulesFile(filePath) {
  const body = WINDOW_RULES.map((rule) => `windowrule = ${rule}, match:class ^(${WINDOW_CLASS})$`).join('\n');
  fs.writeFileSync(filePath, `${body}\n`, 'utf8');
  return send(`/keyword source ${filePath}`);
}

async function loadRules(filePath) {
  const out = await writeRulesFile(filePath);
  if (out.includes('error')) throw new Error(out.split('\n')[0]);
  return out;
}

async function applyWindowRules() {
  const results = [];

  for (const prop of WINDOW_PROPS) {
    results.push(`${prop}: ${await send(`/dispatch setprop ${MATCH} ${prop}`)}`);
  }
  results.push(`pin: ${await send(`/dispatch pin ${MATCH}`)}`);
  return results;
}

async function moveTo(x, y) {
  return send(`/dispatch movewindowpixel exact ${Math.round(x)} ${Math.round(y)},${MATCH}`);
}

async function resizeTo(width, height) {
  return send(`/dispatch resizewindowpixel exact ${Math.round(width)} ${Math.round(height)},${MATCH}`);
}

async function ownWindow() {
  const clients = await json('clients');
  return clients.find((c) => c.class === WINDOW_CLASS) || null;
}

// Dunya, Kevin'in penceresinin BULUNDUGU monitore gore kurulmali.
// Odaklanmis monitore bakmak karakteri baska ekranin koordinatlarina gonderiyordu.
async function activeMonitor() {
  const monitors = await json('monitors');
  try {
    const own = await ownWindow();
    if (own) {
      const mine = monitors.find((m) => m.id === own.monitor);
      if (mine) return mine;
    }
  } catch {
    // pencere henuz yoksa asagiya dus
  }
  return monitors.find((m) => m.focused) || monitors[0];
}

function shellEdge(reserved) {
  const [top, bottom, left, right] = reserved;
  const edges = [
    { edge: 'top', size: top },
    { edge: 'bottom', size: bottom },
    { edge: 'left', size: left },
    { edge: 'right', size: right },
  ];
  const biggest = edges.sort((a, b) => b.size - a.size)[0];
  return biggest.size >= 24 ? biggest : { edge: 'none', size: 0 };
}

// hyprctl'in bildirdigi reserved her zaman dogru olmuyor: caelestia bar solda
// dururken reserved [60,10,10,10] (ustte) diyordu. Ayni monitordeki tiling
// pencerelerin kapladigi alan gercek calisma alanini daha iyi gosteriyor.
async function workAreaFromWindows(monitor) {
  const clients = await json('clients');
  const tiled = clients.filter(
    (c) => !c.floating && c.mapped && c.monitor === monitor.id && c.size[0] > 200 && c.size[1] > 200,
  );
  if (!tiled.length) return null;

  const left = Math.min(...tiled.map((c) => c.at[0])) - monitor.x;
  const top = Math.min(...tiled.map((c) => c.at[1])) - monitor.y;
  const right = Math.max(...tiled.map((c) => c.at[0] + c.size[0])) - monitor.x;
  const bottom = Math.max(...tiled.map((c) => c.at[1] + c.size[1])) - monitor.y;
  return { left, top, right, bottom };
}

async function world() {
  const monitor = await activeMonitor();
  const width = Math.round(monitor.width / monitor.scale);
  const height = Math.round(monitor.height / monitor.scale);
  const [rTop, rBottom, rLeft, rRight] = monitor.reserved || [0, 0, 0, 0];

  let reserved = { top: rTop, bottom: rBottom, left: rLeft, right: rRight };

  const area = await workAreaFromWindows(monitor);
  if (area) {
    // Iki kaynaktan hangisi daha icerideyse onu aliyoruz.
    reserved = {
      top: Math.max(rTop, area.top),
      bottom: Math.max(rBottom, height - area.bottom),
      left: Math.max(rLeft, area.left),
      right: Math.max(rRight, width - area.right),
    };
  }

  return {
    monitor: monitor.name,
    originX: monitor.x,
    originY: monitor.y,
    width,
    height,
    reserved,
    shell: shellEdge([reserved.top, reserved.bottom, reserved.left, reserved.right]),
    ground: height - reserved.bottom,
  };
}

module.exports = { available, send, json, applyWindowRules, loadRules, moveTo, resizeTo, ownWindow, world, WINDOW_CLASS };
