const character = document.getElementById('character');
const hook = document.getElementById('hook');
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

const IDLE_SIZE = { width: 150, height: 250 };
const PANEL_SIZE = { width: 340, height: 460 };

const CHAR_WIDTH = 130;
const CHAR_HEIGHT = 224;

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

function worldFrozen() {
  return Boolean(busyState || conversationActive || sleeping);
}

function refreshKevinState() {
  if (forcedAnim) return;
  if (busyState) return window.KevinSkin.setState(busyState);
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
  world = new window.KevinWorld(info);
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

    if (worldFrozen()) {
      window.KevinSkin.setFacing(conversationActive ? 0 : world.facing);
    } else {
      window.KevinSkin.setFacing(world.facing);
      pushAnchor(now);
    }
    refreshKevinState();
  }

  window.KevinSkin.tick(dt);
}

initWorld();
requestAnimationFrame(frame);


let pressTimer = null;
let suppressClick = false;

character.addEventListener('mousedown', () => {
  pressTimer = setTimeout(() => {
    pressTimer = null;
    suppressClick = true;
    markInteraction();
    window.KevinSkin.play('tickle');
  }, LONG_PRESS_MS);
});

function cancelLongPress() {
  clearTimeout(pressTimer);
  pressTimer = null;
}

character.addEventListener('mouseup', cancelLongPress);
character.addEventListener('mouseleave', cancelLongPress);

character.addEventListener('dblclick', () => {
  markInteraction();
  window.KevinSkin.play('jump');
});

function showBubble(text) {
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

character.addEventListener('click', () => {
  if (suppressClick) {
    suppressClick = false;
    return;
  }
  openPanel();
});
hook.addEventListener('click', openPanel);
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

async function speak(text) {
  try {
    const base64 = await window.kevinAPI.speak(text);
    const audio = new Audio(`data:audio/wav;base64,${base64}`);
    audio.onended = () => setBusy(null);
    audio.onerror = () => setBusy(null);
    setBusy('talk');
    audio.play();
  } catch (err) {
    setBusy(null);
    console.error('TTS hatasi:', err);
  }
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

          const freshCfg = await window.kevinAPI.getConfig();
          const wakeName = (freshCfg.name || 'Kevin').toLowerCase();
          const wakeWords = [wakeName, ...(freshCfg.nicknames || [])];
          const lowerText = text.toLowerCase();
          if (wakeWords.some((w) => lowerText.includes(w))) {
            openPanelForChat();
            sendChat(text);
          }
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
