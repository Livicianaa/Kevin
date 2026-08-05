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

const AGENT_TOOL_LABELS = {
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

const IDLE_SIZE = { width: 200, height: 300 };
const PANEL_SIZE = { width: 340, height: 460 };

const CHAR_WIDTH = 130;
const CHAR_HEIGHT = 224;

function positionCharacter(size) {
  character.style.left = `${(size.width - CHAR_WIDTH) / 2}px`;
  character.style.top = `${size.height - CHAR_HEIGHT}px`;
}

window.KevinSkin.initSkinViewer(character, 'assets/skins/totem.png', CHAR_WIDTH, CHAR_HEIGHT);

positionCharacter(IDLE_SIZE);

function showBubble(text) {
  bubble.textContent = text;
  bubble.classList.remove('hidden');
  clearTimeout(showBubble._t);
  showBubble._t = setTimeout(() => bubble.classList.add('hidden'), 3000);
}

let conversationActive = false;
let conversationHistory = [];

async function openPanel() {
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
}

character.addEventListener('click', openPanel);
hook.addEventListener('click', openPanel);
closePanelBtn.addEventListener('click', closePanel);

async function refreshModelList(selectedModel) {
  modelSelect.innerHTML = '<option value="">Varsayılan</option>';
  const apiKey = apikeyInput.value.trim();
  if (!apiKey) return;

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
  apikeyInput.value = cfg.apiKey || '';
  nameInput.value = cfg.name || '';
  nicknamesInput.value = (cfg.nicknames || []).join(', ');
  await refreshModelList(cfg.model);
  document.body.classList.add('config-open');
  chatView.classList.add('hidden');
  configView.classList.remove('hidden');
});

saveConfigBtn.addEventListener('click', async () => {
  if (!apikeyInput.value.trim()) return;
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
    audio.play();
  } catch (err) {
    console.error('TTS hatasi:', err);
  }
}

async function sendChat(text) {
  const message = (text ?? chatInput.value).trim();
  if (!message) return;
  chatInput.value = '';
  addMessage(message, 'user');
  if (conversationActive) resetConversationTimeout();

  conversationHistory.push({ role: 'user', content: message });

  try {
    const reply = await window.kevinAPI.chat(conversationHistory);
    conversationHistory.push({ role: 'assistant', content: reply });
    addMessage(reply, 'kevin');
    speak(reply);
  } catch (err) {
    conversationHistory.pop();
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
  resetConversationTimeout();
}

let vadInstance = null;

async function initHandsFree() {
  if (vadInstance) return;

  const cfg = await window.kevinAPI.getConfig();
  if (!cfg.apiKey) return;

  try {
    const assetsURL = new URL('vad-assets/', window.location.href).href;
    vadInstance = await vad.MicVAD.new({
      baseAssetPath: assetsURL,
      onnxWASMBasePath: assetsURL,
      redemptionMs: 1600,
      preSpeechPadMs: 800,
      positiveSpeechThreshold: 0.6,
      negativeSpeechThreshold: 0.45,
      onSpeechEnd: async (audio) => {
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
