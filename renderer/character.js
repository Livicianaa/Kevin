const character = document.getElementById('character');
const bubble = document.getElementById('bubble');
const panel = document.getElementById('panel');
const configView = document.getElementById('config-view');
const chatView = document.getElementById('chat-view');
const providerSelect = document.getElementById('provider');
const apikeyInput = document.getElementById('apikey');
const modelSelect = document.getElementById('model');
const nameInput = document.getElementById('name');
const nicknamesInput = document.getElementById('nicknames');
const saveConfigBtn = document.getElementById('save-config');
const chatLog = document.getElementById('chat-log');
const chatInput = document.getElementById('chat-input');
const chatSendBtn = document.getElementById('chat-send');
const closePanelBtn = document.getElementById('close-panel');
const micBtn = document.getElementById('mic-btn');
const settingsBtn = document.getElementById('settings-btn');
const agentStatus = document.getElementById('agent-status');
const refreshModelsBtn = document.getElementById('refresh-models');
const handsFreeInput = document.getElementById('handsfree');
const wakeRepliesInput = document.getElementById('wake-replies');
const sessionSecsInput = document.getElementById('session-secs');
const personaInput = document.getElementById('persona');

const AGENT_TOOL_LABELS = {
  open_url_or_app: 'açıyor...',
  list_directory: 'klasöre bakıyor...',
  screenshot: 'ekrana bakıyor...',
  list_windows: 'pencereleri listeliyor...',
  list_apps: 'uygulamaları listeliyor...',
  focused_window: 'aktif pencereyi kontrol ediyor...',
  get_app_state: 'uygulamayı inceliyor...',
  click: 'tıklıyor...',
  drag: 'sürüklüyor...',
  scroll: 'kaydırıyor...',
  type_text: 'yazıyor...',
  press_key: 'tuşa basıyor...',
  activate_window: 'pencereyi öne getiriyor...',
  move_window: 'pencereyi taşıyor...',
  resize_window: 'pencereyi yeniden boyutlandırıyor...',
  perform_action: 'bir işlem yapıyor...',
  set_value: 'değer giriyor...',
};

window.kevinAPI.onAgentActivity((data) => {
  if (!data) {
    agentStatus.classList.add('hidden');
    return;
  }
  agentStatus.textContent = `🖥️ ${AGENT_TOOL_LABELS[data.tool] || data.tool}`;
  agentStatus.classList.remove('hidden');
});

const IDLE_SIZE = { width: 200, height: 330 };
const PANEL_SIZE = { width: 360, height: 500 };

const CHAR_WIDTH = 190;
const CHAR_HEIGHT = 320;

function positionCharacter(size) {
  character.style.left = `${(size.width - CHAR_WIDTH) / 2}px`;
  character.style.top = `${size.height - CHAR_HEIGHT}px`;
}

window.KevinSkin.initSkinViewer(character, 'assets/skins/totem.png', CHAR_WIDTH, CHAR_HEIGHT);

positionCharacter(IDLE_SIZE);

// --- Animasyon durum makinesi ---

const SLEEP_AFTER_MS = 10 * 60 * 1000;
const MUSIC_POLL_MS = 6000;
const NIGHT_START = 0;
const NIGHT_END = 6;
const LONG_PRESS_MS = 600;

const YES_PREFIXES = ['evet', 'tabii', 'olur', 'tamam', 'aynen', 'kesinlikle', 'elbette'];
const NO_PREFIXES = ['hayir', 'hayır', 'olmaz', 'maalesef', 'uzgunum', 'üzgünüm', 'yok,'];

let busyState = null;
let listening = false;
let musicPlaying = false;
let lastInteraction = Date.now();
let world = null;
let sleeping = false;

const forcedAnim = new URLSearchParams(window.location.search).get('anim');

// --brain: bu pencere gorunmez; karakteri Godot govdesi oynatiyor. Durum ve
// hareketleri ona iletiyoruz, eski 2B karakteri cizmiyoruz.
const BRAIN = new URLSearchParams(window.location.search).get('brain') === '1';
const BODY_STATES = new Set(['idle', 'listen', 'think', 'talk', 'sleep', 'night-sleepy', 'dance']);
const BODY_PLAYS = new Set(['wake', 'nod-yes', 'nod-no', 'wave', 'tickle', 'jump']);
if (BRAIN) {
  let lastState = '';
  const setState = window.KevinSkin.setState;
  const play = window.KevinSkin.play;
  window.KevinSkin.setState = (state) => {
    const mapped = BODY_STATES.has(state) ? state : 'idle';
    if (mapped !== lastState) {
      lastState = mapped;
      window.kevinAPI.bodyEvent({ type: 'state', state: mapped });
    }
    return setState(state);
  };
  window.KevinSkin.play = (name) => {
    if (BODY_PLAYS.has(name)) window.kevinAPI.bodyEvent({ type: 'play', name });
    return play(name);
  };
}

function worldFrozen() {
  return Boolean(busyState || conversationActive || sleeping || voiceActive());
}

function refreshKevinState() {
  if (forcedAnim) return;
  if (busyState) return window.KevinSkin.setState(busyState);
  // Cagrildi ve bekliyor: kullaniciya donup dinliyor
  if (voiceState === VOICE_AWAKE) return window.KevinSkin.setState('listen');
  if (conversationActive) return window.KevinSkin.setState('idle');

  // Uyku sadece karakter zeminde bostayken; tirmanirken uyuyup dusmesin.
  sleeping = Date.now() - lastInteraction > SLEEP_AFTER_MS && (!world || world.mode === 'idle');
  if (sleeping) return window.KevinSkin.setState('sleep');

  if (world && world.mode !== 'idle') return window.KevinSkin.setState(world.animation);

  if (listening) return window.KevinSkin.setState('listen');
  if (musicPlaying) return window.KevinSkin.setState('dance');

  const hour = new Date().getHours();
  if (hour >= NIGHT_START && hour < NIGHT_END) return window.KevinSkin.setState('night-sleepy');
  window.KevinSkin.setState('idle');
}

function setBusy(state) {
  busyState = state;
  refreshKevinState();
}

function markInteraction() {
  const wasAsleep = window.KevinSkin.currentState() === 'sleep';
  lastInteraction = Date.now();
  if (wasAsleep) window.KevinSkin.play('wake');
  refreshKevinState();
}

function playAnswerGesture(reply) {
  const head = reply.trim().toLowerCase();
  if (YES_PREFIXES.some((w) => head.startsWith(w))) window.KevinSkin.play('nod-yes');
  else if (NO_PREFIXES.some((w) => head.startsWith(w))) window.KevinSkin.play('nod-no');
}

async function pollMusic() {
  try {
    const status = await window.kevinAPI.musicStatus();
    musicPlaying = !!(status && status.playing);
  } catch {
    musicPlaying = false;
  }
  refreshKevinState();
}

setInterval(refreshKevinState, 1000);

if (forcedAnim) {
  const [state, sit] = forcedAnim.split(':');
  window.KevinSkin.setSitting(sit === 'sit');
  if (window.KevinSkin.ANIMATION_STATES.includes(state)) {
    window.KevinSkin.setState(state);
    window.KevinSkin.play(state);
    window.KevinSkin.setSpeed(0.35);
    setInterval(() => {
      if (window.KevinSkin.currentState() !== state) window.KevinSkin.play(state);
    }, 250);
  }
}

pollMusic();
setInterval(pollMusic, MUSIC_POLL_MS);

// --- Dunya: zemin, yercekimi, gezinme ---

const ANCHOR_EPSILON = 0.75;
const ANCHOR_INTERVAL_MS = 1000 / 30;
let lastAnchor = { x: -1, y: -1 };
let lastAnchorAt = 0;

function pushAnchor(now = performance.now()) {
  if (!world) return;
  if (now - lastAnchorAt < ANCHOR_INTERVAL_MS) return;
  if (Math.abs(world.x - lastAnchor.x) < ANCHOR_EPSILON && Math.abs(world.y - lastAnchor.y) < ANCHOR_EPSILON) return;
  lastAnchorAt = now;
  lastAnchor = { x: world.x, y: world.y };
  window.kevinAPI.setAnchor(world.x, world.y);
}

// Karakter hareketsizken tam hizda cizmenin anlami yok: bos masaustunde
// surekli calisan bir uygulama icin kare hizi harekete gore ayarlaniyor.
const ACTIVE_FPS = 30;
const CALM_FPS = 12;

function targetFrameMs() {
  const moving = world && world.mode !== 'idle' && world.mode !== 'sit';
  const busy = Boolean(busyState || listening || musicPlaying);
  return 1000 / (moving || busy ? ACTIVE_FPS : CALM_FPS);
}

async function initWorld() {
  if (forcedAnim) return;
  const info = await window.kevinAPI.worldInfo();
  if (!info) {
    console.warn('[kevin] Hyprland yok - karakter sabit kalacak');
    return;
  }
  world = new window.KevinWorld(info, IDLE_SIZE.width / 2);
  pushAnchor();
}

let previousFrame = performance.now();

function frame(now) {
  requestAnimationFrame(frame);

  const elapsed = now - previousFrame;
  if (elapsed < targetFrameMs() - 1) return;
  previousFrame = now;
  const dt = Math.min(elapsed / 1000, 0.05);

  if (world) {
    world.setPaused(worldFrozen());
    if (world.update(dt) === 'land') window.KevinSkin.play('land');

    if (world.mode === 'held' && lastCursor) {
      // Pencere fareyi takip ediyor; ragdoll'un tutma noktasi ise tutuldugu an
      // SABITLENDI. Onceden her karede fareden yeniden hesaplaniyordu: fare 90 ms'de
      // bir okundugu ve pencere ekran sinirinda kirpildigi icin hesap sapiyor,
      // karakter pencere disindaki bir noktaya uzanip yatiyordu.
      world.dragTo(lastCursor.x, lastCursor.y + dragOffsetY);
      window.KevinSkin.ragdollMuscle(world.struggling ? 1 : 0.22);
    }

    if (world.mode === 'fall') window.KevinSkin.ragdollMuscle(0.12);

    if (world.mode === 'held' || world.mode === 'fall') {
      const vx = (world.x - lastWorldPos.x) / dt;
      const vy = (world.y - lastWorldPos.y) / dt;
      window.KevinSkin.ragdollInertia((vx - lastWorldVel.x) / dt, (vy - lastWorldVel.y) / dt);
      lastWorldVel = { x: vx, y: vy };

      // Surukleme yonune donuyor: hizli saga cekince saga, sola cekince sola.
      // Karakterin duz bir kagit degil 3B bir govde oldugunu en cok bu gosteriyor.
      const spinTarget = Math.max(-1.15, Math.min(1.15, vx / 520));
      heldSpin += (spinTarget - heldSpin) * Math.min(1, dt * 4);
      window.KevinSkin.ragdollSpin(heldSpin);
    } else {
      heldSpin = 0;
      window.KevinSkin.ragdollStop();
      lastWorldVel = { x: 0, y: 0 };
    }
    lastWorldPos = { x: world.x, y: world.y };

    window.KevinSkin.setRootRotation(world.rootRotation);

    if (worldFrozen()) {
      window.KevinSkin.setFacing(conversationActive ? 0 : world.facing);
    } else {
      window.KevinSkin.setFacing(world.facing);
      pushAnchor(now);
    }
    refreshKevinState();
  }

  updateLook();
  window.KevinSkin.setCemContext(buildCemContext(dt));
  window.KevinSkin.tick(dt);
}




// --- Sesli akis: sohbet paneli yok, her sey ses uzerinden ---
//
// Bosta Kevin sadece dinler. Adi gecince kullaniciya doner ve kisa bir karsilik
// verir ("Efendim?"), sonra oturum acilir: soylenen her sey ona gider. Konusma
// bittikten sonra bir sure sessizlik olursa tekrar bosta moduna doner.

const VOICE_IDLE = 'idle';
const VOICE_AWAKE = 'awake';
const VOICE_THINKING = 'thinking';
const VOICE_SPEAKING = 'speaking';

const DEFAULT_WAKE_REPLIES = ['Efendim?', 'Buyur', 'Ne oldu?', 'Dinliyorum'];
const DEFAULT_SESSION_MS = 20000;

const VOICE_REPLY_TIMEOUT_MS = 40000;
const VOICE_STUCK_MS = 50000;

let voiceState = VOICE_IDLE;
let voiceSessionTimer = null;
let voiceBusy = false;
let voiceBusySince = 0;

function voiceActive() {
  return voiceState !== VOICE_IDLE;
}

function setVoiceState(next) {
  voiceState = next;
  refreshKevinState();
}

function endVoiceSession() {
  clearTimeout(voiceSessionTimer);
  voiceSessionTimer = null;
  setBusy(null);
  setVoiceState(VOICE_IDLE);
}

function touchVoiceSession(ms) {
  clearTimeout(voiceSessionTimer);
  voiceSessionTimer = setTimeout(endVoiceSession, ms || DEFAULT_SESSION_MS);
}

// Ses tanima ismi bozuk yaziyor ("Kevim", "Kev'in", "Kemin", "Ken"): yaklasik
// eslesme. Ilk iki kelimede daha toleransli (seslenme genelde basta).
function editDistance(a, b) {
  const d = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
  for (let j = 1; j <= b.length; j++) d[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
  }
  return d[a.length][b.length];
}

function normalizeWord(w) {
  return w.toLocaleLowerCase('tr').replace(/['’`]/g, '').replace(/[^a-zçğıöşü0-9]/g, '')
    .replace(/ı/g, 'i');
}

// Uyanma kelimesinin bittigi karakter konumu; yoksa -1
function findWake(text, wakeWords) {
  const re = /\S+/g;
  let m;
  let index = 0;
  const wakes = wakeWords.map(normalizeWord).filter(Boolean);
  while ((m = re.exec(text)) !== null) {
    const w = normalizeWord(m[0]);
    for (const wake of wakes) {
      if (!w) continue;
      const tol = index < 2 && wake.length >= 4 && w[0] === wake[0] ? 2 : (wake.length >= 5 ? 1 : 0);
      // "kevine", "kevinim" gibi ekler: kelimenin basi yeterli
      const head = w.slice(0, Math.max(wake.length, 3));
      if (w === wake || editDistance(head, wake) <= tol || (w.length >= 3 && editDistance(w, wake) <= tol)) {
        return m.index + m[0].length;
      }
    }
    index += 1;
  }
  return -1;
}

// "kevin hava nasil" -> "hava nasil" (uyanma kelimesi ve oncesi atiliyor)
function stripWakeWord(text, wakeWords) {
  const cut = findWake(text, wakeWords);
  if (cut < 0) return text.trim();
  return text.slice(cut).replace(/^[\s,.:!?]+/, '').trim();
}

async function voiceReply(text, cfg) {
  setVoiceState(VOICE_THINKING);
  setBusy('think');

  conversationHistory.push({ role: 'user', content: text });
  trimHistory();

  let reply;
  try {
    // Arac zinciri uzayabiliyor; renderer'i sonsuza kadar bekletmiyoruz.
    reply = await Promise.race([
      window.kevinAPI.chat(conversationHistory),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('zaman asimi')), VOICE_REPLY_TIMEOUT_MS),
      ),
    ]);
    conversationHistory.push({ role: 'assistant', content: reply });
    trimHistory();
  } catch (err) {
    conversationHistory.pop();
    reply = err.message === 'zaman asimi'
      ? 'Bu biraz uzun surdu, tekrar sorar misin?'
      : 'Bir sorun cikti, tekrar soyler misin?';
    console.error('[kevin] sohbet hatasi:', err.message);
  }

  console.log('[kevin] cevap:', reply);
  playAnswerGesture(reply);
  showBubble(reply);
  setVoiceState(VOICE_SPEAKING);
  await speak(reply);

  setVoiceState(VOICE_AWAKE);
  touchVoiceSession(cfg.voiceSessionMs);
}

if (BRAIN) {
  window.kevinAPI.onBodyCommand(async (msg) => {
    if (msg.type === 'wake') {
      // Karaktere tiklandi: adi soylenmis gibi
      const cfg = await window.kevinAPI.getConfig();
      handleVoice(cfg.name || 'Kevin');
    }
  });
}

async function handleVoice(text) {
  if (BRAIN) window.kevinAPI.bodyEvent({ type: 'heard', text });
  // Bir sey takildiysa kilitli kalmayalim: uzun suredir mesgulse sifirla.
  if (voiceBusy && Date.now() - voiceBusySince > VOICE_STUCK_MS) {
    console.warn('[kevin] takilmis gorunuyor, durum sifirlaniyor');
    voiceBusy = false;
    endVoiceSession();
  }
  if (voiceBusy) return;

  const cfg = await window.kevinAPI.getConfig();
  const wakeWords = [(cfg.name || 'Kevin').toLowerCase(), ...(cfg.nicknames || [])];
  const lower = text.toLowerCase();

  voiceBusy = true;
  voiceBusySince = Date.now();
  try {
    if (voiceState === VOICE_IDLE) {
      if (findWake(text, wakeWords) < 0) return;

      markInteraction();
      const rest = stripWakeWord(text, wakeWords);

      if (rest.length >= 3) {
        // "Kevin, hava nasil" - beklemeden cevapla
        await voiceReply(rest, cfg);
        return;
      }

      // Sadece cagirdi: donup karsilik ver
      const replies = (cfg.wakeReplies && cfg.wakeReplies.length ? cfg.wakeReplies : DEFAULT_WAKE_REPLIES);
      const answer = replies[Math.floor(Math.random() * replies.length)];
      setVoiceState(VOICE_SPEAKING);
      showBubble(answer);
      await speak(answer);
      setVoiceState(VOICE_AWAKE);
      touchVoiceSession(cfg.voiceSessionMs);
      return;
    }

    // Oturum acik: soylenen her sey Kevin'e
    markInteraction();
    await voiceReply(text, cfg);
  } finally {
    voiceBusy = false;
  }
}

// --- Fareyi takip etme: karakter imlece bakiyor ---

const CURSOR_POLL_MS = 90;
let lastCursor = null;

async function pollCursor() {
  try {
    const cursor = await window.kevinAPI.cursorPos();
    if (cursor && world) {
      lastCursor = { x: cursor.x - world.info.originX, y: cursor.y - world.info.originY };
    }
  } catch {
    lastCursor = null;
  }
}

setInterval(pollCursor, CURSOR_POLL_MS);

function updateLook() {
  if (!world || !lastCursor) {
    window.KevinSkin.setLook(0, 0);
    return;
  }
  const headX = world.x;
  const headY = world.y - CHAR_HEIGHT * 0.62;
  const dx = lastCursor.x - headX;
  const dy = lastCursor.y - headY;

  const yaw = Math.max(-0.95, Math.min(0.95, Math.atan2(dx, Math.abs(dy) + 220)));
  const pitch = Math.max(-0.5, Math.min(0.55, dy / 520));
  window.KevinSkin.setLook(yaw, pitch);
}

// --- CEM paketi (Fresh Moves gibi): Kevin'in durumu Minecraft degiskenlerine cevriliyor ---

let limbSwing = 0;
const startedAt = performance.now();

function buildCemContext(dt) {
  const mode = world ? world.mode : 'idle';
  const walking = mode === 'walk';
  const climbing = mode === 'climb';
  const sitting = mode === 'sit';
  const falling = mode === 'fall';
  const amount = walking ? 1 : climbing ? 0.6 : 0;

  if (walking) limbSwing += dt * 7;
  else if (climbing) limbSwing += dt * 4;

  const seconds = (performance.now() - startedAt) / 1000;

  return {
    limb_swing: limbSwing,
    limb_speed: amount,
    limb_swing_amount: amount,
    limb_speed_attenuation: amount,
    move_forward: walking ? 1 : 0,
    move_strafing: 0,
    age: seconds * 20,
    time: seconds,
    frame_time: dt,
    pi: Math.PI,
    is_on_ground: falling || climbing ? 0 : 1,
    is_climbing: 0,
    is_riding: sitting ? 1 : 0,
    is_sitting: sitting ? 1 : 0,
    is_sneaking: 0,
    is_sprinting: 0,
    is_swimming: 0,
    is_crawling: 0,
    is_gliding: 0,
    is_in_water: 0,
    is_hurt: 0,
    hurt_time: 0,
    is_first_person_hand: 0,
    is_aiming_crossbow: 0,
    has_raised_hands: 0,
    is_parcooling: 0,
    is_parcool_diving: 0,
    is_parcool_skydiving: 0,
    is_parcool_sliding: 0,
    health: 20,
    max_health: 20,
  };
}

// Fresh Moves gibi CEM paketleri varsayilan ACIK (bin/cem/player.jem varsa).
// `--no-cem` ile kapatilabilir.
const cemEnabled = new URLSearchParams(window.location.search).get('cem') !== '0';

async function initCemPack() {
  if (!cemEnabled) return;
  try {
    const jem = await window.kevinAPI.cemPack();
    if (!jem) return;
    const result = window.KevinSkin.useCemPack(jem);
    if (result.ok) {
      console.log(`[kevin] CEM paketi yuklendi: ${result.assignments} ifade` +
        (result.warnings.length ? `, ${result.warnings.length} uyari: ${result.warnings.slice(0, 3).join(' | ')}` : ''));
    } else {
      console.warn('[kevin] CEM paketi yuklenemedi:', result.reason);
    }
  } catch (err) {
    console.warn('[kevin] CEM:', err.message);
  }
}

initCemPack();

// Gelistirme: --ragdoll=<uzuv> ile karakter o uzvundan asili baslatiliyor
const ragdollTest = new URLSearchParams(window.location.search).get('ragdoll');
if (ragdollTest) {
  setTimeout(() => {
    window.KevinSkin.ragdollGrab(ragdollTest);
    if (world) world.grab('arm');
  }, 1200);
}

// Gelistirme: --selftest sesli sohbet zincirini uctan uca deniyor
if (new URLSearchParams(window.location.search).get('selftest')) {
  setTimeout(async () => {
    try {
      const cfg = await window.kevinAPI.getConfig();
      console.log(`SELFTEST saglayici=${cfg.provider} model=${cfg.model || '(varsayilan)'} eller-serbest=${cfg.handsFree !== false}`);
      const list = await window.kevinAPI.listModels(cfg.provider, cfg.apiKey);
      if (list.error) {
        console.log('SELFTEST model listesi alinamadi:', list.error);
      } else {
        console.log('SELFTEST kullanilabilir modeller:', (list.models || []).join(', ').slice(0, 400));
      }
      const reply = await window.kevinAPI.chat([{ role: 'user', content: 'Tek kelimeyle selam ver.' }]);
      console.log('SELFTEST LLM cevabi:', JSON.stringify(reply).slice(0, 160));
      const audio = await window.kevinAPI.speak(reply);
      console.log('SELFTEST TTS uretildi:', audio.length, 'bayt base64');
      console.log('SELFTEST VAD hazir mi:', typeof vad !== 'undefined');
      const seen = await window.kevinAPI.chat([{ role: 'user', content: 'Ekranima baksana, ne goruyorsun?' }]);
      console.log('SELFTEST ekrana bakma:', JSON.stringify(seen).slice(0, 300));
    } catch (err) {
      console.error('SELFTEST HATA:', err.message);
    }
  }, 2500);
}

// Gelistirme: --voicetest mikrofonsuz sesli akisi deniyor
const voiceTest = new URLSearchParams(window.location.search).get('voicetest');
if (voiceTest) {
  setTimeout(async () => {
    const steps = voiceTest.split('|');
    for (const line of steps) {
      console.log(`VOICETEST duyulan: "${line}" (durum: ${voiceState})`);
      await handleVoice(line);
      console.log(`VOICETEST sonrasi durum: ${voiceState}`);
    }
    console.log('VOICETEST bitti');
  }, 3000);
}

initWorld();
if (!BRAIN) requestAnimationFrame(frame);


// --- Fare ile tutma: hangi uzuvdan tutuldugu onemli ---

const GRAB_MOVE_THRESHOLD = 7;
const CLICK_MAX_MS = 260;

let pressInfo = null;
let dragOffsetY = 0;
const RAGDOLL_SCALE = 6;
let heldSpin = 0;
let lastWorldPos = { x: 0, y: 0 };
let lastWorldVel = { x: 0, y: 0 };

function limbAt(offsetX, offsetY, width, height) {
  const ratioY = offsetY / height;
  const leftHalf = offsetX < width / 2;
  if (ratioY < 0.34) return { kind: 'head', body: 'head' };
  if (ratioY < 0.62) return { kind: 'arm', body: leftHalf ? 'rightArm' : 'leftArm' };
  return { kind: 'leg', body: leftHalf ? 'rightLeg' : 'leftLeg' };
}

character.addEventListener('mousedown', async (event) => {
  if (event.button !== 0) return;
  markInteraction();

  const limb = limbAt(
    event.offsetX,
    event.offsetY,
    character.clientWidth || CHAR_WIDTH,
    character.clientHeight || CHAR_HEIGHT,
  );
  pressInfo = { at: performance.now(), x: event.screenX, y: event.screenY, limb, moved: false };

  if (!world) return;
  const cursor = await window.kevinAPI.cursorPos();
  if (!cursor || !pressInfo) return;
  dragOffsetY = world.y - cursor.y;
});

window.addEventListener('mousemove', (event) => {
  if (!pressInfo) return;
  const dx = event.screenX - pressInfo.x;
  const dy = event.screenY - pressInfo.y;
  if (!pressInfo.moved && Math.hypot(dx, dy) > GRAB_MOVE_THRESHOLD) {
    pressInfo.moved = true;
    if (world) world.grab(pressInfo.limb.kind);
    window.KevinSkin.ragdollGrab(pressInfo.limb.body);
  }
});

window.addEventListener('mouseup', () => {
  if (!pressInfo) return;
  const quick = performance.now() - pressInfo.at < CLICK_MAX_MS;

  if (pressInfo.moved && world) {
    world.drop();
    window.KevinSkin.ragdollRelease();
  } else if (quick) {
    openPanel();
  } else if (world) {
    // Basili tutup birakti ama surukleMEDI: gidiklandi
    window.KevinSkin.play('tickle');
  }

  pressInfo = null;
});

character.addEventListener('dblclick', () => {
  if (pressInfo && pressInfo.moved) return;
  markInteraction();
  window.KevinSkin.play('jump');
});

function showBubble(text) {
  if (BRAIN) window.kevinAPI.bodyEvent({ type: 'say', text });
  bubble.textContent = text;
  bubble.classList.remove('hidden');
  clearTimeout(showBubble._t);
  showBubble._t = setTimeout(() => bubble.classList.add('hidden'), 3000);
}

let conversationActive = false;
let conversationHistory = [];

async function openPanel() {
  markInteraction();
  window.KevinSkin.setSitting(true);
  document.body.classList.add('panel-open');
  panel.classList.remove('hidden');
  window.kevinAPI.resizeWindow(PANEL_SIZE.width, PANEL_SIZE.height);
  positionCharacter(PANEL_SIZE);

  const cfg = await window.kevinAPI.getConfig();
  if (cfg.apiKey) {
    document.body.classList.remove('config-open');
    configView.classList.add('hidden');
    chatView.classList.remove('hidden');
    chatInput.focus();
    conversationActive = true;
    resetConversationTimeout();
    window.KevinSkin.play('wave');
  } else {
    document.body.classList.add('config-open');
    chatView.classList.add('hidden');
    configView.classList.remove('hidden');
  }
}

function closePanel() {
  document.body.classList.remove('panel-open', 'config-open');
  panel.classList.add('hidden');
  window.kevinAPI.resizeWindow(IDLE_SIZE.width, IDLE_SIZE.height);
  positionCharacter(IDLE_SIZE);
  conversationActive = false;
  conversationHistory = [];
  chatLog.innerHTML = '';
  clearTimeout(conversationTimeoutId);
  window.KevinSkin.setSitting(false);
  setBusy(null);
}


closePanelBtn.addEventListener('click', closePanel);

async function refreshModelList(selectedModel) {
  modelSelect.innerHTML = '<option value="">Varsayılan</option>';
  const apiKey = apikeyInput.value.trim();
  if (!apiKey && providerNeedsKey()) return;

  modelSelect.disabled = true;
  const result = await window.kevinAPI.listModels(providerSelect.value, apiKey);
  modelSelect.disabled = false;

  if (result.error) {
    const opt = document.createElement('option');
    opt.textContent = `Yüklenemedi: ${result.error}`;
    opt.disabled = true;
    modelSelect.appendChild(opt);
    return;
  }

  for (const id of result.models || []) {
    const opt = document.createElement('option');
    opt.value = id;
    opt.textContent = id;
    modelSelect.appendChild(opt);
  }

  if (selectedModel) modelSelect.value = selectedModel;
}

apikeyInput.addEventListener('blur', () => refreshModelList());
refreshModelsBtn.addEventListener('click', () => refreshModelList());
providerSelect.addEventListener('change', () => refreshModelList());

settingsBtn.addEventListener('click', async () => {
  const cfg = await window.kevinAPI.getConfig();
  providerSelect.value = cfg.provider || 'nvidia';
  syncKeyField();
  apikeyInput.value = cfg.apiKey || '';
  nameInput.value = cfg.name || '';
  nicknamesInput.value = (cfg.nicknames || []).join(', ');
  handsFreeInput.checked = cfg.handsFree !== false;
  wakeRepliesInput.value = (cfg.wakeReplies && cfg.wakeReplies.length ? cfg.wakeReplies : DEFAULT_WAKE_REPLIES).join(', ');
  sessionSecsInput.value = Math.round((cfg.voiceSessionMs || DEFAULT_SESSION_MS) / 1000);
  personaInput.value = cfg.persona || '';
  await refreshModelList(cfg.model);
  document.body.classList.add('config-open');
  chatView.classList.add('hidden');
  configView.classList.remove('hidden');
});

const LOCAL_PROVIDERS = ['ollama'];

function providerNeedsKey() {
  return !LOCAL_PROVIDERS.includes(providerSelect.value);
}

function syncKeyField() {
  const needed = providerNeedsKey();
  apikeyInput.disabled = !needed;
  apikeyInput.placeholder = needed ? 'API key yapıştır' : 'Gerekmiyor - model bu bilgisayarda çalışıyor';
}

providerSelect.addEventListener('change', syncKeyField);
syncKeyField();

saveConfigBtn.addEventListener('click', async () => {
  if (providerNeedsKey() && !apikeyInput.value.trim()) return;
  const nicknames = nicknamesInput.value
    .split(',')
    .map((n) => n.trim().toLowerCase())
    .filter(Boolean);

  await window.kevinAPI.saveConfig({
    provider: providerSelect.value,
    apiKey: apikeyInput.value.trim(),
    model: modelSelect.value,
    name: nameInput.value.trim() || 'Kevin',
    nicknames,
    handsFree: handsFreeInput.checked,
    wakeReplies: wakeRepliesInput.value.split(',').map((w) => w.trim()).filter(Boolean),
    voiceSessionMs: Math.max(5, Number(sessionSecsInput.value) || 20) * 1000,
    persona: personaInput.value.trim(),
  });
  document.body.classList.remove('config-open');
  configView.classList.add('hidden');
  chatView.classList.remove('hidden');
  chatInput.focus();
  initHandsFree();
});

function addMessage(text, who) {
  const div = document.createElement('div');
  div.className = `msg ${who}`;
  div.textContent = text;
  chatLog.appendChild(div);
  chatLog.scrollTop = chatLog.scrollHeight;
}

function speak(text) {
  return new Promise(async (resolve) => {
    try {
      const base64 = await window.kevinAPI.speak(text);
      const audio = new Audio(`data:audio/wav;base64,${base64}`);
      const done = () => {
        setBusy(null);
        resolve();
      };
      audio.onended = done;
      audio.onerror = done;
      setBusy('talk');
      audio.play();
    } catch (err) {
      setBusy(null);
      console.error('TTS hatasi:', err);
      resolve();
    }
  });
}

const MAX_HISTORY_MESSAGES = 16;

function trimHistory() {
  if (conversationHistory.length > MAX_HISTORY_MESSAGES) {
    conversationHistory = conversationHistory.slice(-MAX_HISTORY_MESSAGES);
  }
}

async function sendChat(text) {
  const message = (text ?? chatInput.value).trim();
  if (!message) return;
  chatInput.value = '';
  addMessage(message, 'user');
  if (conversationActive) resetConversationTimeout();

  conversationHistory.push({ role: 'user', content: message });
  trimHistory();
  markInteraction();
  setBusy('think');

  try {
    const reply = await window.kevinAPI.chat(conversationHistory);
    conversationHistory.push({ role: 'assistant', content: reply });
    trimHistory();
    addMessage(reply, 'kevin');
    playAnswerGesture(reply);
    speak(reply);
  } catch (err) {
    conversationHistory.pop();
    setBusy(null);
    addMessage(`Hata: ${err.message}`, 'kevin');
  }
}

chatSendBtn.addEventListener('click', () => sendChat());
chatInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') sendChat();
  if (e.key === 'Escape') closePanel();
});

let mediaRecorder = null;
let recordedChunks = [];
let isRecording = false;

async function startRecording() {
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  recordedChunks = [];
  mediaRecorder = new MediaRecorder(stream);
  mediaRecorder.ondataavailable = (e) => {
    if (e.data.size > 0) recordedChunks.push(e.data);
  };
  mediaRecorder.start();
  isRecording = true;
  micBtn.classList.add('recording');
}

function stopRecording() {
  return new Promise((resolve) => {
    mediaRecorder.onstop = async () => {
      const blob = new Blob(recordedChunks, { type: 'audio/webm' });
      mediaRecorder.stream.getTracks().forEach((t) => t.stop());
      resolve(await blob.arrayBuffer());
    };
    mediaRecorder.stop();
  });
}

micBtn.addEventListener('click', async () => {
  if (!isRecording) {
    try {
      await startRecording();
    } catch (err) {
      addMessage(`Mikrofon hatasi: ${err.message}`, 'kevin');
    }
    return;
  }

  isRecording = false;
  micBtn.classList.remove('recording');
  micBtn.disabled = true;

  try {
    const arrayBuffer = await stopRecording();
    const text = await window.kevinAPI.transcribe(arrayBuffer);
    if (text) sendChat(text);
  } catch (err) {
    addMessage(`Transkripsiyon hatasi: ${err.message}`, 'kevin');
  } finally {
    micBtn.disabled = false;
  }
});

// --- Eller serbest dinleme: "Kevin" (config'teki isim) deyince tetiklenir ---

function encodeWAV(samples, sampleRate) {
  const buffer = new ArrayBuffer(44 + samples.length * 2);
  const view = new DataView(buffer);

  function writeString(offset, str) {
    for (let i = 0; i < str.length; i++) view.setUint8(offset + i, str.charCodeAt(i));
  }

  writeString(0, 'RIFF');
  view.setUint32(4, 36 + samples.length * 2, true);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  writeString(36, 'data');
  view.setUint32(40, samples.length * 2, true);

  let offset = 44;
  for (let i = 0; i < samples.length; i++, offset += 2) {
    const s = Math.max(-1, Math.min(1, samples[i]));
    view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7fff, true);
  }

  return buffer;
}

const CONVERSATION_TIMEOUT_MS = 45000;
let conversationTimeoutId = null;

function resetConversationTimeout() {
  clearTimeout(conversationTimeoutId);
  conversationTimeoutId = setTimeout(() => {
    if (conversationActive) closePanel();
  }, CONVERSATION_TIMEOUT_MS);
}

function openPanelForChat() {
  document.body.classList.add('panel-open');
  panel.classList.remove('hidden');
  window.kevinAPI.resizeWindow(PANEL_SIZE.width, PANEL_SIZE.height);
  positionCharacter(PANEL_SIZE);
  configView.classList.add('hidden');
  chatView.classList.remove('hidden');
  conversationActive = true;
  window.KevinSkin.setSitting(true);
  markInteraction();
  resetConversationTimeout();
}

let vadInstance = null;

async function initHandsFree() {
  if (vadInstance) return;
  if (new URLSearchParams(window.location.search).get('novad')) return;

  const cfg = await window.kevinAPI.getConfig();
  if (cfg.handsFree === false) return;
  if (!cfg.apiKey && cfg.provider !== 'ollama') return;

  try {
    const assetsURL = new URL('vad-assets/', window.location.href).href;
    vadInstance = await vad.MicVAD.new({
      baseAssetPath: assetsURL,
      onnxWASMBasePath: assetsURL,
      onSpeechStart: () => {
        listening = true;
        refreshKevinState();
      },
      onVADMisfire: () => {
        listening = false;
        refreshKevinState();
      },
      redemptionMs: 1600,
      preSpeechPadMs: 800,
      positiveSpeechThreshold: 0.6,
      negativeSpeechThreshold: 0.45,
      onSpeechEnd: async (audio) => {
        listening = false;
        refreshKevinState();
        try {
          const wavBuffer = encodeWAV(audio, 16000);
          const text = await window.kevinAPI.transcribeWav(wavBuffer);
          if (!text) return;

          await handleVoice(text);
        } catch (err) {
          console.error('Eller serbest transkripsiyon hatasi:', err);
        }
      },
    });
    vadInstance.start();
  } catch (err) {
    console.error('[kevin] VAD baslatilamadi:', err.message);
  }
}

initHandsFree();
