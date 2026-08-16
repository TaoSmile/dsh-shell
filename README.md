# dsh-shell —— 轻量 DeepSeek Harness 桌面壳 / A lightweight desktop shell for DeepSeek Harness

> Zero-install desktop window for an already-installed DeepSeek Harness: attaches to a running `dsh web` instance, or launches one with your existing Node environment. No bundled Node, no bundled deps, no harness changes. (Docs below are in Chinese.)

把**本机已安装的** DeepSeek Harness Web GUI 装进一个桌面窗口。不打包 Node、不打包依赖、不改 harness 一行代码：

- **A0 attach**：探测已有实例（默认 `http://127.0.0.1:3080`），命中就直接开窗——你现有的会话、设置、工作区原样出现。
- **A1 spawn**：没有实例时，用本机现有 node + checkout 拉起 `dsh web --port 0`，解析官方就绪行 `dsh web: http://127.0.0.1:<port>` 后开窗。

就绪判定以 harness 官方的 URL 行为准（内容含 `__DSH_BOOT__`），不用"HTTP 200"冒充就绪。

## 最快上手（一步到位，零安装）

**双击 `启动Harness桌面.cmd`**：壳会自动探测 harness——在跑就直接开窗包住它，没跑就自动拉起再开窗。不需要先启动 harness，也不需要敲任何命令。可以把它发送快捷方式到桌面/任务栏。

## 目录

```
dsh-shell/
├─ 启动Harness桌面.cmd    零安装双击启动（Edge app-mode）
├─ start-electron.cmd     Electron 版双击启动（需先 npm install 一次）
├─ src/main.js           Electron 主进程：窗口/托盘/菜单/生命周期
├─ src/host-manager.js   壳与 harness 的唯一桥：attach / spawn / 就绪解析 / 日志
├─ src/config.js         配置读写（%APPDATA%\dsh-shell\dsh-shell.json）
├─ src/preload.js        仅注入到壳自己的状态小窗；主窗口无 preload，官方页面原样
├─ ui/status.html        启动状态 / 错误 / 日志小窗
├─ assets/               图标
└─ launcher/start-shell-edge.ps1   零安装版（Edge app-mode，无需 npm）
```

## 运行方式一：Electron 完整版

```powershell
cd D:\workspace\harness-demo\dsh-shell
npm install        # 只需装 electron 这一个 devDependency（本机需联网）
npm start
```

> **npm install 报 `read ECONNRESET`（下载 Electron 二进制失败）怎么办？**
> 这是 GitHub Releases 直连被重置，与壳代码无关。仓库已内置 `.npmrc` 指向 npmmirror 镜像；删除 node_modules 后重装即可：
> ```powershell
> Remove-Item node_modules -Recurse -Force
> npm install
> ```
> 若镜像仍失败，可换华为云镜像再装：`$env:ELECTRON_MIRROR='https://mirrors.huaweicloud.com/electron/'` 后重跑 `npm install`；或配置你的代理后重试。手动下载二进制放进 `%LOCALAPPDATA%\electron\Cache` 也可（目录名 = 下载 URL 的 SHA256）。

- 启动后先出现状态小窗：探测 3080 → 命中直接开主窗；未命中则拉起 harness（先 tsx 后自动回退 built）。
- 托盘：显示/隐藏窗口、重启 Harness、打开日志、退出。
- 关闭主窗口 = 退出应用；**由壳拉起的 harness 会一并停止，附着模式的已有实例不动**。
- 日志：`%APPDATA%\dsh-shell\logs\host.log`；配置：`%APPDATA%\dsh-shell\dsh-shell.json`（菜单"帮助 → 打开配置文件"）。

## 运行方式二：零安装 Edge 版（今天就能跑）

不装任何东西（复用本机 node + Edge）：

```powershell
powershell -ExecutionPolicy Bypass -File D:\workspace\harness-demo\dsh-shell\launcher\start-shell-edge.ps1
```

- 开一个独立 app-mode 窗口（专用 profile，不干扰你日常 Edge）。
- 停止由它拉起的 harness：`.\start-shell-edge.ps1 -Stop`。
- 关闭 Edge 窗口不会停止 harness（附着模式不受影响；拉起模式用 `-Stop`）。

## 配置项（dsh-shell.json）

| 键 | 默认 | 说明 |
|---|---|---|
| `harnessCheckout` | `D:\workspace\deepseek-harness` | A1 拉起的 checkout 路径 |
| `attachUrl` | `http://127.0.0.1:3080` | A0 附着探测地址 |
| `spawnMode` | `auto` | `tsx`（源码）/ `built`（构建产物）/ `auto`（tsx 失败回退 built） |
| `nodePath` | `node` | 直接用 PATH 里的 node（本机 v24.19.0） |
| `dshHome` | `''` | 空 = 继承环境（默认 `~/.dsh`，现有数据全在）；可显式指定 |
| `spawnArgs` | `[]` | 追加给 `dsh web` 的参数（默认已有 `--port 0`） |
| `openDevTools` | `false` | 菜单显示开发者工具 |
| `probeIntervalMs` | `15000` | attach 模式断连探测间隔 |

## 行为语义（重要）

1. **附着（A0）**：壳只是窗口，不拥有 harness 生命周期——不启动、不停止、退出不影响它。
2. **拉起（A1）**：壳拥有该实例——退出时 `kill` + `taskkill /T` 兜底强杀。harness 存储为增量+事务设计（崩溃安全），强杀安全。
3. **DSH_HOME**：默认继承环境。桌面启动时未设置 → harness 用默认 `~/.dsh`。若你终端里开着 `dsh web`（同 home），壳会先探测到并直接附着，不会起第二份实例、不会写抢同一份配置。
4. **端口**：A1 永远 `--port 0`（OS 分配，零冲突），真实端口从就绪行解析。

## 限制（v0.1）

- Electron 版未做代码签名 / 自动更新 / 安装包（electron-builder 配置是下一步）。
- 沙箱提示：若在受限终端（如本项目的 agent 沙箱）里运行，tsx 模式会因 esbuild 管道限制失败——真实桌面环境无此问题；Electron 版会自动回退 built 模式。
- 主窗口只加载官方页面，不注入任何脚本；安全面与浏览器直连 `dsh web` 完全一致（loopback-only + `/api` 信任围栏）。

## 已验证

- A0：3080 探测 200 + `__DSH_BOOT__` ✅
- A1 全链路（同进程内）：无实例 → 复用现有 node + checkout 拉起 → 解析就绪行 `spawned: http://127.0.0.1:56685 (pid 10684)` → 探活 `status=200 has-boot=True` ✅ → `-Stop` 后进程退出、端口释放 ✅
- Electron 窗口渲染需在本机 `npm install electron` 后人工验收（当前环境无法下载 electron 二进制）。
