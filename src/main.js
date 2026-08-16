'use strict'
const { app, BrowserWindow, Tray, Menu, shell, ipcMain, nativeImage } = require('electron')
const path = require('node:path')
const fs = require('node:fs')
const { HostManager } = require('./host-manager')
const { loadConfig, configPath, logDir } = require('./config')

const gotLock = app.requestSingleInstanceLock()
if (!gotLock) {
  app.quit()
} else {
  main()
}

function main () {
  const config = loadConfig()
  app.setAppUserModelId('local.dsh-shell')

  const host = new HostManager()
  let shellWin = null // 状态/错误小窗（只加载本地页面，带 preload）
  let appWin = null // 主窗口（只加载官方 harness 页面，无 preload，保持页面原样）
  let tray = null
  let quitting = false
  let readyUrl = null

  const boundsFile = () => path.join(app.getPath('userData'), 'bounds.json')
  const lastBounds = () => {
    try { return JSON.parse(fs.readFileSync(boundsFile(), 'utf8')) } catch { return null }
  }
  const rememberBounds = win => {
    try { fs.writeFileSync(boundsFile(), JSON.stringify(win.getBounds())) } catch {}
  }

  function createShellWin () {
    if (shellWin && !shellWin.isDestroyed()) return shellWin
    shellWin = new BrowserWindow({
      width: 480,
      height: 400,
      resizable: false,
      minimizable: false,
      maximizable: false,
      title: 'DeepSeek Harness',
      icon: path.join(__dirname, '..', 'assets', 'icon.png'),
      webPreferences: {
        preload: path.join(__dirname, 'preload.js'),
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true
      }
    })
    shellWin.setMenu(null)
    shellWin.loadFile(path.join(__dirname, '..', 'ui', 'status.html'))
    shellWin.on('closed', () => { shellWin = null })
    return shellWin
  }

  function createAppWin () {
    if (appWin && !appWin.isDestroyed()) return appWin
    const bounds = lastBounds() || { width: 1320, height: 860 }
    appWin = new BrowserWindow({
      width: bounds.width,
      height: bounds.height,
      minWidth: 960,
      minHeight: 600,
      title: 'DeepSeek Harness',
      icon: path.join(__dirname, '..', 'assets', 'icon.png'),
      webPreferences: { contextIsolation: true, nodeIntegration: false, sandbox: true }
    })
    appWin.on('close', () => rememberBounds(appWin))
    appWin.on('closed', () => { appWin = null })
    return appWin
  }

  function openApp (url) {
    readyUrl = url
    const win = createAppWin()
    if (win.webContents.getURL() !== url) void win.loadURL(url)
    win.show()
    win.focus()
    if (shellWin && !shellWin.isDestroyed()) shellWin.close()
    refreshTrayMenu()
  }

  host.on('state', state => {
    if (state.phase === 'ready' && state.url) openApp(state.url)
    else if (state.phase === 'error') createShellWin().show()
  })

  // ---- IPC（仅状态小窗使用）----
  ipcMain.handle('shell:status', () => host.status())
  ipcMain.on('shell:retry', () => { void host.restart() })
  ipcMain.on('shell:cancel', () => { app.quit() })
  ipcMain.on('shell:openExternal', (_e, url) => {
    if (typeof url === 'string' && /^https?:/.test(url)) void shell.openExternal(url)
  })
  ipcMain.on('shell:openLogs', () => { void shell.openPath(logDir()) })
  ipcMain.on('shell:openConfig', () => { void shell.openPath(configPath()) })
  ipcMain.on('shell:quit', () => { app.quit() })

  // ---- 单实例 ----
  app.on('second-instance', () => {
    if (appWin && !appWin.isDestroyed()) {
      if (appWin.isMinimized()) appWin.restore()
      appWin.show()
      appWin.focus()
    } else if (shellWin && !shellWin.isDestroyed()) {
      shellWin.show()
    }
  })

  // ---- 托盘 ----
  function createTray () {
    const img = nativeImage.createFromPath(path.join(__dirname, '..', 'assets', 'tray.png'))
    tray = new Tray(img)
    tray.setToolTip('DeepSeek Harness')
    refreshTrayMenu()
    tray.on('click', () => {
      if (appWin && !appWin.isDestroyed()) {
        if (appWin.isVisible()) appWin.hide()
        else { appWin.show(); appWin.focus() }
      }
    })
  }

  function refreshTrayMenu () {
    if (!tray) return
    tray.setContextMenu(Menu.buildFromTemplate([
      { label: '显示窗口', click: () => { if (appWin && !appWin.isDestroyed()) { appWin.show(); appWin.focus() } else createShellWin().show() } },
      { label: '在浏览器中打开', enabled: !!readyUrl, click: () => { if (readyUrl) void shell.openExternal(readyUrl) } },
      { label: '重启 Harness', click: () => { void host.restart() } },
      { type: 'separator' },
      { label: '打开日志目录', click: () => { void shell.openPath(logDir()) } },
      { label: '退出', click: () => { app.quit() } }
    ]))
  }

  // ---- 应用菜单 ----
  Menu.setApplicationMenu(Menu.buildFromTemplate([
    {
      label: '文件',
      submenu: [
        { label: '重启 Harness', click: () => { void host.restart() } },
        { type: 'separator' },
        { role: 'quit', label: '退出' }
      ]
    },
    {
      label: '视图',
      submenu: [
        { role: 'reload', label: '刷新页面' },
        { role: 'toggleDevTools', label: '开发者工具', visible: config.openDevTools }
      ]
    },
    {
      label: '帮助',
      submenu: [
        { label: '打开日志目录', click: () => { void shell.openPath(logDir()) } },
        { label: '打开配置文件', click: () => { void shell.openPath(configPath()) } }
      ]
    }
  ]))

  app.whenReady().then(() => {
    createTray()
    createShellWin()
    void host.start()
  })

  app.on('window-all-closed', () => { app.quit() })

  app.on('before-quit', event => {
    if (quitting || !host.child) return
    event.preventDefault()
    quitting = true
    void host.stop().finally(() => app.quit())
  })
}
