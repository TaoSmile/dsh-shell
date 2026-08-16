# dsh-shell · DeepSeek Harness 桌面壳 / Desktop Shell

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-4f46e5)]()
[![Node: >=22.19](https://img.shields.io/badge/Node-%3E%3D22.19%20or%20%3E%3D24-green)]()
[![Upstream: deepseek-harness](https://img.shields.io/badge/Upstream-deepseek--harness-red)](https://github.com/deepseek-ai/deepseek-harness)

**一个动作，把已经装好的 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web GUI 变成独立桌面窗口。**

> A lightweight desktop shell for an already-installed DeepSeek Harness: one double-click, no new environment, zero changes to the harness core.

- ✅ 不打包 Node、不打包依赖、不改 harness 一行代码
- ✅ harness 在跑 → 直接附着包住它；没跑 → 自动用现有环境拉起
- ✅ 沿用你的 `~/.dsh`：会话、设置、工作区原样可见
- ✅ 端口自动分配（`--port 0`），以官方就绪行为准，绝不"假就绪"

## 30 秒上手

1. 双击 `启动Harness桌面.cmd`（零安装，Edge app-mode）
2. 完。

想要托盘 / 日志面板 / 重试按钮的完整版：

```powershell
cd dsh-shell
npm install   # 国内网络已内置 npmmirror 镜像，解决 Electron 二进制下载失败
npm start
```

或双击 `start-electron.cmd`。

## 工作原理

```
壳 ──探测──▶ http://127.0.0.1:3080（响应含 __DSH_BOOT__ 才算就绪）
 ├─ 命中 ──▶ 开窗附着（不拥有生命周期，退出不影响已有实例）
 └─ 未命中 ─▶ node <checkout>/apps/cli/lib/bin.js web --port 0
              └─ 解析官方就绪行 "dsh web: http://127.0.0.1:<port>" ──▶ 开窗（壳拥有该实例，退出即停）
```

就绪判定严格以 harness 官方 URL 行为准，不用"HTTP 200"冒充就绪。

## 特性对比

| | Edge 零安装版 | Electron 完整版 |
|---|---|---|
| 安装 | **无** | npm install（一次性） |
| 窗口 | Edge app-mode 独立窗口（专用 profile） | 原生窗口 + 尺寸记忆 |
| 托盘 | - | 显示/隐藏、重启、打开日志 |
| 状态小窗 | - | 启动进度 / 错误 / 日志 / 重试 |
| 适合 | 快速体验、零门槛 | 日常主力 |

## 常见问题

- **和 anywhere-labs/deepseek-harness-desktop 有什么区别？** 那是给"没装过 harness 的新用户"的一体化打包（内置 Node/依赖/插件，开箱即用）；本项目面向**已经装好 harness** 的用户，零新环境、更轻，也更容易改。
- **会和我终端里跑的 `dsh web` 冲突吗？** 不会。壳先探测，命中就附着同一个实例，不会起第二份、不会抢写同一份配置。
- **端口冲突？** 不存在——拉起时永远 `--port 0`，由 OS 分配空闲端口。
- **数据在哪？** 沿用 `~/.dsh`（或你设置的 `DSH_HOME`），与命令行共享同一份会话。
- **怎么停止壳拉起的实例？** Electron 版退出即停；Edge 版运行 `.\launcher\start-shell-edge.ps1 -Stop`。
- **代理/网络？** 壳不联网下载任何东西（唯一的例外是首次 `npm install electron`，已内置 npmmirror 镜像）。

## 配置

首次运行自动生成 `%APPDATA%\dsh-shell\dsh-shell.json`（Electron 版；默认值见 `src/config.js`）：

| 键 | 默认 | 说明 |
|---|---|---|
| `harnessCheckout` | `D:\workspace\deepseek-harness` | A1 拉起使用的 checkout 路径 |
| `attachUrl` | `http://127.0.0.1:3080` | A0 附着探测地址 |
| `spawnMode` | `auto` | `tsx`（源码）/ `built`（构建产物）/ `auto`（失败自动回退） |
| `dshHome` | `''` | 空 = 继承环境（默认 `~/.dsh`）；可显式指定 |
| `spawnArgs` | `[]` | 追加给 `dsh web` 的参数（默认已有 `--port 0`） |

## 目录结构

```
dsh-shell/
├─ 启动Harness桌面.cmd       零安装双击启动（Edge app-mode）
├─ start-electron.cmd        Electron 版双击启动
├─ src/                      Electron 主进程
│  ├─ main.js                窗口 / 托盘 / 菜单 / 生命周期
│  ├─ host-manager.js        壳↔harness 唯一桥：attach / spawn / 就绪解析 / 日志
│  ├─ config.js              配置读写
│  └─ preload.js             仅注入壳自己的状态小窗；主窗口零注入，官方页面原样
├─ ui/status.html            启动状态 / 错误 / 日志
├─ launcher/start-shell-edge.ps1   Edge 版核心逻辑（探测→拉起→开窗）
└─ assets/                   图标
```

## 许可

MIT，与上游 [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)（MIT）保持一致。
