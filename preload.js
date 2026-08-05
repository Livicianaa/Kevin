const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('kevinAPI', {
  getConfig: () => ipcRenderer.invoke('get-config'),
  saveConfig: (cfg) => ipcRenderer.invoke('save-config', cfg),
  chat: (message) => ipcRenderer.invoke('chat', message),
  transcribe: (arrayBuffer) => ipcRenderer.invoke('transcribe', arrayBuffer),
  transcribeWav: (arrayBuffer) => ipcRenderer.invoke('transcribe-wav', arrayBuffer),
  speak: (text) => ipcRenderer.invoke('speak', text),
  listModels: (provider, apiKey) => ipcRenderer.invoke('list-models', { provider, apiKey }),
  resizeWindow: (width, height) => ipcRenderer.send('resize-window', width, height),
});
