'use strict'
/**
 * HostManager：桌面壳与 harness 之间的唯一桥。
 *
 * A0（attach）：GET 探测 attachUrl，200 且响应含 `__DSH_BOOT__` 才算就绪，
 *              之后挂一个周期探测循环，断连即报错。
 * A1（spawn） ：用本机现有 node + checkout 拉起 `web --port 0`（零新环境），
 *              解析 stdout 的官方就绪行 `dsh web: http://127.0.0.1:<port>`。
 *
 * 就绪判定以 URL 行为准，绝不用“HTTP 200”冒充就绪（见 harness postmortem 0003）。
 */
const { EventEmitter } = require('node:events')
const { spawn } = require('node:child_process')
const fs = require('node:fs')
const http = require('node:http')
const path = require('node:path')
const { loadConfig, logDir } = require('./config')

const READY_RE = /^dsh web: (http:\/\/127\.0\.0\.1:\d+)/
const READY_MARKER = '__DSH_BOOT__'
const LOG_CAP = 400

class HostManager extends EventEmitter {
  constructor () {
    super()
    this.config = loadConfig()
    this.phase = 'idle'
    this.url = null
    this.owned = false
    this.child = null
    this.logTail = []
    this.readyTimer = null
    this.probeTimer = null
    this.triedBuilt = false
    try { fs.mkdirSync(logDir(), { recursive: true }) } catch {}
  }

  pushLog (line) {
    this.logTail.push(line)
    if (this.logTail.length > LOG_CAP) this.logTail.splice(0, this.logTail.length - LOG_CAP)
    try {
      const stamp = new Date().toISOString().slice(0, 19).replace('T', ' ')
      fs.appendFileSync(path.join(logDir(), 'host.log'), `[${stamp}] ${line}\n`)
    } catch {}
  }

  setPhase (phase, message) {
    this.phase = phase
    this.pushLog(`[${phase}] ${message || ''}`)
    this.emit('state', { phase, message, url: this.url, owned: this.owned, logTail: this.logTail.slice(-40) })
  }

  status () {
    return { phase: this.phase, url: this.url, owned: this.owned, logTail: this.logTail.slice(-40) }
  }

  clearReadyTimer () {
    if (this.readyTimer) { clearTimeout(this.readyTimer); this.readyTimer = null }
  }

  // ---- A0：探测已有实例（内容级就绪判定）----
  probe (url, timeoutMs) {
    return new Promise(resolve => {
      const req = http.get(url + '/', { timeout: timeoutMs }, res => {
        let body = ''
        res.on('data', chunk => {
          body += chunk
          if (body.length > 512 * 1024) { req.destroy(); resolve(false) }
        })
        res.on('end', () => resolve(res.statusCode === 200 && body.includes(READY_MARKER)))
      })
      req.on('timeout', () => { req.destroy(); resolve(false) })
      req.on('error', () => resolve(false))
    })
  }

  async attach () {
    this.setPhase('attaching', `正在探测已有 Harness 实例（${this.config.attachUrl}）…`)
    const ok = await this.probe(this.config.attachUrl, this.config.attachTimeoutMs)
    if (!ok) return false
    this.url = this.config.attachUrl
    this.owned = false
    this.startProbeLoop()
    this.setPhase('ready', `已附着已有实例 ${this.url}`)
    return true
  }

  // ---- A1：复用现有环境拉起 ----
  binArgs (mode) {
    const checkout = this.config.harnessCheckout
    const tail = ['web', '--port', '0', ...(this.config.spawnArgs || [])]
    if (mode === 'tsx') {
      return {
        bin: this.config.nodePath,
        args: ['--import', 'tsx/esm', path.join(checkout, 'apps', 'cli', 'src', 'bin.ts'), ...tail],
        cwd: checkout
      }
    }
    return {
      bin: this.config.nodePath,
      args: [path.join(checkout, 'apps', 'cli', 'lib', 'bin.js'), ...tail],
      cwd: checkout
    }
  }

  childEnv () {
    const env = { ...process.env }
    if (this.config.dshHome) env.DSH_HOME = this.config.dshHome
    return env
  }

  spawnOnce (mode) {
    const { bin, args, cwd } = this.binArgs(mode)
    this.setPhase('starting', `正在用现有环境启动 Harness（${mode} 模式）…`)
    this.pushLog(`spawn: ${bin} ${args.join(' ')}`)
    this.pushLog(`cwd: ${cwd}`)
    const child = spawn(bin, args, {
      cwd,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe'],
      env: this.childEnv()
    })
    this.child = child
    let buffer = ''
    const handleLine = (line) => {
      line = String(line).replace(/\r?\n$/, '')
      if (!line) return
      this.pushLog(line)
      buffer += line + '\n'
      const m = buffer.match(READY_RE)
      if (m) {
        this.clearReadyTimer()
        this.url = m[1]
        this.owned = true
        this.setPhase('ready', `Harness 已就绪 ${this.url}`)
      }
    }
    child.stdout.on('data', d => String(d).split('\n').forEach(handleLine))
    child.stderr.on('data', d => String(d).split('\n').forEach(handleLine))
    child.on('error', err => {
      this.pushLog(`spawn error: ${err.message}`)
      if (this.phase !== 'ready' && this.phase !== 'error') {
        this.onSpawnFailed(new Error(`无法启动 Node（${this.config.nodePath}）：${err.message}`))
      }
    })
    child.on('exit', (code, signal) => {
      if (child.ignoreExit) return
      this.child = null
      this.pushLog(`harness exited code=${code} signal=${signal}`)
      if (this.phase === 'ready' && this.owned) {
        this.url = null
        this.stopProbeLoop()
        this.setPhase('error', `Harness 进程已退出（code=${code}）`)
      } else if (this.phase !== 'ready' && this.phase !== 'error') {
        this.clearReadyTimer()
        this.onSpawnFailed(new Error(`harness 启动失败（code=${code} signal=${signal}）`))
      }
    })
    this.readyTimer = setTimeout(() => {
      if (this.phase !== 'ready') {
        this.onSpawnFailed(new Error(`等待就绪超时（${this.config.spawnTimeoutMs}ms），未看到 "dsh web: http://…" 输出`))
      }
    }, this.config.spawnTimeoutMs)
  }

  onSpawnFailed (err) {
    if (this.phase === 'error') return
    // auto 模式：tsx 失败回退一次 built（覆盖源码未构建/构建产物缺失等场景）
    if (this.config.spawnMode === 'auto' && !this.triedBuilt) {
      this.triedBuilt = true
      this.pushLog(`tsx 模式失败（${err.message}），回退到已构建产物重试…`)
      if (this.child) {
        const dead = this.child
        dead.ignoreExit = true // 旧子进程的退出事件不再参与状态机
        this.child = null
        try { dead.kill() } catch {}
      }
      this.spawnOnce('built')
      return
    }
    this.setPhase('error', err.message)
    this.pushLog(`FAILED: ${err.message}`)
  }

  async start () {
    this.clearReadyTimer()
    this.triedBuilt = false
    if (await this.attach()) return
    const mode = this.config.spawnMode === 'built' ? 'built' : 'tsx'
    this.spawnOnce(mode)
  }

  async restart () {
    await this.stop()
    this.url = null
    this.owned = false
    this.triedBuilt = false
    await this.start()
  }

  async stop () {
    this.clearReadyTimer()
    this.stopProbeLoop()
    if (this.child) {
      const child = this.child
      this.child = null
      child.ignoreExit = true // 主动停止：退出事件只用于解除等待，不进入报错状态机
      this.pushLog('停止 harness 子进程…')
      try { child.kill() } catch {}
      await new Promise(resolve => {
        const timer = setTimeout(() => {
          try {
            spawn('taskkill', ['/pid', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' })
          } catch {}
          resolve()
        }, 4000)
        child.once('exit', () => { clearTimeout(timer); resolve() })
      })
    }
    this.url = null
    this.owned = false
    this.setPhase('idle', '已停止')
  }

  startProbeLoop () {
    this.stopProbeLoop()
    this.probeTimer = setInterval(async () => {
      if (this.owned || this.phase !== 'ready') return
      const ok = await this.probe(this.config.attachUrl, 3000)
      if (!ok) {
        this.url = null
        this.setPhase('error', '与 Harness 实例的连接已断开')
      }
    }, this.config.probeIntervalMs)
  }

  stopProbeLoop () {
    if (this.probeTimer) { clearInterval(this.probeTimer); this.probeTimer = null }
  }
}

module.exports = { HostManager }
