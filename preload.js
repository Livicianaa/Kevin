const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('kevinAPI', {
  getConfig: () => ipcRenderer.invoke('get-config'),
  saveConfig: (cfg) => ipcRenderer.invoke('save-config', cfg),
  chat: (message) => ipcRenderer.invoke('chat', message),
  resizeWindow: (width, height) => ipcRenderer.send('resize-window', width, height),
});
