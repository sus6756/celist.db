const { app, BrowserWindow, ipcMain, dialog } = require('electron');
const path = require('path');
const fs = require('fs');

let mainWindow = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 980,
    minHeight: 620,
    title: 'celist.db',
    backgroundColor: '#f2f2f2',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  mainWindow.removeMenu();
  mainWindow.loadFile(path.join(__dirname, 'index.html'));
  mainWindow.on('closed', () => { mainWindow = null; });
}

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// ----- IPC: file dialogs -------------------------------------------------

function dbTypes() {
  return [
    { name: 'SQLite databases', extensions: ['db', 'sqlite', 'sqlite3'] },
    { name: 'All files', extensions: ['*'] },
  ];
}

ipcMain.handle('dialog:openDatabase', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: 'Open Database',
    properties: ['openFile'],
    filters: dbTypes(),
  });
  if (result.canceled || result.filePaths.length === 0) return null;
  return result.filePaths[0];
});

ipcMain.handle('dialog:newDatabase', async () => {
  const result = await dialog.showSaveDialog(mainWindow, {
    title: 'Create Database',
    defaultPath: 'MyDatabase.db',
    filters: dbTypes(),
  });
  if (result.canceled || !result.filePath) return null;
  return result.filePath;
});

ipcMain.handle('dialog:createSample', async () => {
  const result = await dialog.showSaveDialog(mainWindow, {
    title: 'Create Sample Database',
    defaultPath: 'Sample Shop.db',
    filters: dbTypes(),
  });
  if (result.canceled || !result.filePath) return null;
  return result.filePath;
});

ipcMain.handle('dialog:exportCSV', async () => {
  const result = await dialog.showSaveDialog(mainWindow, {
    title: 'Export CSV',
    defaultPath: 'query_results.csv',
    filters: [{ name: 'CSV', extensions: ['csv'] }],
  });
  if (result.canceled || !result.filePath) return null;
  return result.filePath;
});

ipcMain.handle('dialog:importCSV', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: 'Import CSV',
    properties: ['openFile'],
    filters: [{ name: 'CSV', extensions: ['csv'] }, { name: 'All files', extensions: ['*'] }],
  });
  if (result.canceled || result.filePaths.length === 0) return null;
  return result.filePaths[0];
});

ipcMain.handle('dialog:importJSON', async () => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: 'Import JSON',
    properties: ['openFile'],
    filters: [{ name: 'JSON', extensions: ['json'] }, { name: 'All files', extensions: ['*'] }],
  });
  if (result.canceled || result.filePaths.length === 0) return null;
  return result.filePaths[0];
});

ipcMain.handle('dialog:backupDatabase', async (_e, currentPath) => {
  const base = currentPath ? path.basename(currentPath, path.extname(currentPath)) : 'database';
  const result = await dialog.showSaveDialog(mainWindow, {
    title: 'Backup Database',
    defaultPath: base + '-backup.db',
    filters: dbTypes(),
  });
  if (result.canceled || !result.filePath) return null;
  return result.filePath;
});

// ----- IPC: file read / write --------------------------------------------

ipcMain.handle('fs:readFile', (_e, filePath) => {
  const buf = fs.readFileSync(filePath);
  // Copy into a plain Array-like so it can cross IPC without Buffers being stripped.
  return { bytes: Array.from(buf), path: filePath };
});

ipcMain.handle('fs:writeFile', (_e, filePath, bytes) => {
  fs.writeFileSync(filePath, Buffer.from(bytes));
  return true;
});

ipcMain.handle('fs:exists', (_e, filePath) => fs.existsSync(filePath));

ipcMain.handle('app:platform', () => process.platform);

ipcMain.handle('app:version', () => app.getVersion());