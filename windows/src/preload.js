const { contextBridge, ipcRenderer } = require('electron');

// Minimal, safe bridge between the renderer and the main process.
contextBridge.exposeInMainWorld('celistdb', {
  platform: () => ipcRenderer.invoke('app:platform'),
  version: () => ipcRenderer.invoke('app:version'),

  openDatabaseDialog: () => ipcRenderer.invoke('dialog:openDatabase'),
  newDatabaseDialog: () => ipcRenderer.invoke('dialog:newDatabase'),
  createSampleDialog: () => ipcRenderer.invoke('dialog:createSample'),
  exportCSVDialog: () => ipcRenderer.invoke('dialog:exportCSV'),
  importCSVDialog: () => ipcRenderer.invoke('dialog:importCSV'),
  importJSONDialog: () => ipcRenderer.invoke('dialog:importJSON'),
  backupDatabaseDialog: (currentPath) => ipcRenderer.invoke('dialog:backupDatabase', currentPath),

  readFile: (path) => ipcRenderer.invoke('fs:readFile', path),
  writeFile: (path, bytes) => ipcRenderer.invoke('fs:writeFile', path, bytes),
  fileExists: (path) => ipcRenderer.invoke('fs:exists', path),
});