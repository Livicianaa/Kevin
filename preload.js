const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('kevinAPI', {
  getConfig: () => ipcRenderer.invoke('get-config'),
  saveConfig: (cfg) => ipcRenderer.invoke('save-config', cfg),
  chat: (message) => ipcRenderer.invoke('chat', message),
  transcribe: (arrayBuffer) => ipcRenderer.invoke('transcribe', arrayBuffer),
  transcribeWav: (arrayBuffer) => ipcRenderer.invoke('transcribe-wav', arrayBuffer),
  speak: (text) => ipcRenderer.invoke('speak', text),
  listModels: (provider, apiKey) => ipcRenderer.invoke('list-models', { provider, apiKey }),
  musicStatus: () => ipcRenderer.invoke('music-status'),
  resizeWindow: (width, height) => ipcRenderer.send('resize-window', width, height),
  setAnchor: (x, y) => ipcRenderer.send('set-anchor', x, y),
  worldInfo: () => ipcRenderer.invoke('world-info'),
  cemPack: () => ipcRenderer.invoke('cem-pack'),
  cursorPos: () => ipcRenderer.invoke('cursor-pos'),
  bodyEvent: (event) => ipcRenderer.send('body-event', event),
  historyLoad: () => ipcRenderer.invoke('history-load'),
  historyAdd: (entry) => ipcRenderer.send('history-add', entry),
  onBodyCommand: (callback) => {
    ipcRenderer.on('body-command', (_e, data) => callback(data));
  },
  onAgentActivity: (callback) => {
    ipcRenderer.on('agent-activity', (_e, data) => callback(data));
  },
});
