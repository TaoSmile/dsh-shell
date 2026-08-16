'use strict'
const { app } = require('electron')
const fs = require('node:fs')
const path = require('node:path')

const DEFAULTS = {
  // 本机 harness checkout 位置（A1 拉起用）
  harnessCheckout: 'D:\\workspace\\deepseek-harness',
  // A0 附着探测的 URL（本机默认端口）
  attachUrl: 'http://127.0.0.1:3080',
  attachTimeoutMs: 3000,
  spawnTimeoutMs: 90000,
  // 'auto' = 先 tsx（源码，与 pnpm run dsh 一致）失败后回退 built（已构建产物）
  spawnMode: 'auto',
  // 直接用 PATH 里的 node（本机 v24.19.0，满足 harness 的 >=24 要求）
  nodePath: 'node',
  // 空 = 继承当前环境（默认 ~/.dsh，现有会话/设置/工作区全部原样可见）
  dshHome: '',
  // 追加给 `dsh web` 的额外参数（默认已有 --port 0）
  spawnArgs: [],
  openDevTools: false,
  // attach 模式下探测断连的间隔
  probeIntervalMs: 15000
}

let cached = null

function configPath () {
  return path.join(app.getPath('userData'), 'dsh-shell.json')
}

function loadConfig () {
  if (cached) return cached
  let file = {}
  try {
    file = JSON.parse(fs.readFileSync(configPath(), 'utf8'))
  } catch {}
  cached = { ...DEFAULTS, ...(file && typeof file === 'object' ? file : {}) }
  try {
    fs.mkdirSync(path.dirname(configPath()), { recursive: true })
    fs.writeFileSync(configPath(), JSON.stringify(cached, null, 2))
  } catch {}
  return cached
}

function logDir () {
  return path.join(app.getPath('userData'), 'logs')
}

module.exports = { loadConfig, configPath, logDir }
