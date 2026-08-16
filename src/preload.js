'use strict'
// 仅注入到壳自己的状态/错误小窗；主窗口加载官方页面时不带任何 preload。
const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('dshShell', {
  status: () => ipcRenderer.invoke('shell:status'),
  retry: () => ipcRenderer.send('shell:retry'),
  cancel: () => ipcRenderer.send('shell:cancel'),
  openExternal: url => ipcRenderer.send('shell:openExternal', url),
  openLogs: () => ipcRenderer.send('shell:openLogs'),
  openConfig: () => ipcRenderer.send('shell:openConfig'),
  quit: () => ipcRenderer.send('shell:quit')
})
