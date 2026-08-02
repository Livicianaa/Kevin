const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('kevinAPI', {
  setIgnoreMouseEvents: (ignore, options) =>
    ipcRenderer.send('set-ignore-mouse-events', ignore, options),
});
