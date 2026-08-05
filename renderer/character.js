const character = document.getElementById('character');
const hook = document.getElementById('hook');
const bubble = document.getElementById('bubble');
const panel = document.getElementById('panel');
const configView = document.getElementById('config-view');
const chatView = document.getElementById('chat-view');
const providerSelect = document.getElementById('provider');
const apikeyInput = document.getElementById('apikey');
const nameInput = document.getElementById('name');
const saveConfigBtn = document.getElementById('save-config');
const chatLog = document.getElementById('chat-log');
const chatInput = document.getElementById('chat-input');
const chatSendBtn = document.getElementById('chat-send');
const closePanelBtn = document.getElementById('close-panel');

const IDLE_SIZE = { width: 140, height: 210 };
const PANEL_SIZE = { width: 260, height: 340 };

const CHAR_WIDTH = 93;
const CHAR_HEIGHT = 160;
character.style.left = `${(IDLE_SIZE.width - CHAR_WIDTH) / 2}px`;
character.style.top = `${IDLE_SIZE.height - CHAR_HEIGHT}px`;

function showBubble(text) {
  bubble.textContent = text;
  bubble.classList.remove('hidden');
  clearTimeout(showBubble._t);
  showBubble._t = setTimeout(() => bubble.classList.add('hidden'), 3000);
}

async function openPanel() {
  document.body.classList.add('panel-open');
  panel.classList.remove('hidden');
  window.kevinAPI.resizeWindow(PANEL_SIZE.width, PANEL_SIZE.height);

  const cfg = await window.kevinAPI.getConfig();
  if (cfg.apiKey) {
    configView.classList.add('hidden');
    chatView.classList.remove('hidden');
    chatInput.focus();
  } else {
    chatView.classList.add('hidden');
    configView.classList.remove('hidden');
  }
}

function closePanel() {
  document.body.classList.remove('panel-open');
  panel.classList.add('hidden');
  window.kevinAPI.resizeWindow(IDLE_SIZE.width, IDLE_SIZE.height);
}

character.addEventListener('click', openPanel);
hook.addEventListener('click', openPanel);
closePanelBtn.addEventListener('click', closePanel);

saveConfigBtn.addEventListener('click', async () => {
  if (!apikeyInput.value.trim()) return;
  await window.kevinAPI.saveConfig({
    provider: providerSelect.value,
    apiKey: apikeyInput.value.trim(),
    name: nameInput.value.trim() || 'Kevin',
  });
  configView.classList.add('hidden');
  chatView.classList.remove('hidden');
  chatInput.focus();
});

function addMessage(text, who) {
  const div = document.createElement('div');
  div.className = `msg ${who}`;
  div.textContent = text;
  chatLog.appendChild(div);
  chatLog.scrollTop = chatLog.scrollHeight;
}

async function sendChat() {
  const text = chatInput.value.trim();
  if (!text) return;
  chatInput.value = '';
  addMessage(text, 'user');

  try {
    const reply = await window.kevinAPI.chat(text);
    addMessage(reply, 'kevin');
  } catch (err) {
    addMessage(`Hata: ${err.message}`, 'kevin');
  }
}

chatSendBtn.addEventListener('click', sendChat);
chatInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') sendChat();
  if (e.key === 'Escape') closePanel();
});
