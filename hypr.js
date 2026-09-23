const net = require('net');

const SIGNATURE = process.env.HYPRLAND_INSTANCE_SIGNATURE;
const SOCKET = SIGNATURE
  ? `${process.env.XDG_RUNTIME_DIR}/hypr/${SIGNATURE}/.socket.sock`
  : null;

const WINDOW_CLASS = 'kevin-pc-version';
const MATCH = `class:^(${WINDOW_CLASS})$`;

const WINDOW_RULES = [
  'float',
  'noblur',
  'noborder',
  'noshadow',
  'noanim',
  'nodim',
  'noinitialfocus',
  'norounding',
  'pin',
  'keepaspectratio',
];

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

async function applyWindowRules() {
  for (const rule of WINDOW_RULES) {
    await send(`/keyword windowrule ${rule} ${MATCH}`);
  }
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

async function activeMonitor() {
  const monitors = await json('monitors');
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

async function world() {
  const monitor = await activeMonitor();
  const reserved = monitor.reserved || [0, 0, 0, 0];
  const [top, bottom, left, right] = reserved;
  const width = Math.round(monitor.width / monitor.scale);
  const height = Math.round(monitor.height / monitor.scale);

  return {
    monitor: monitor.name,
    originX: monitor.x,
    originY: monitor.y,
    width,
    height,
    reserved: { top, bottom, left, right },
    shell: shellEdge(reserved),
    ground: height - bottom,
  };
}

module.exports = { available, send, json, applyWindowRules, moveTo, resizeTo, ownWindow, world, WINDOW_CLASS };
