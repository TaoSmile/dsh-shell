# Contributing to dsh-shell

欢迎任何形式的贡献：issue、PR、文档修正、翻译。

## 边界（一条硬规则）

**不改 DeepSeek Harness 核心。** 本项目是纯外壳：窗口里 100% 是官方 Web GUI，壳的全部工作都在窗口之外。对 harness 本体的任何改动请直接提给上游 [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)。

## 原则

- **零新环境**：新功能默认复用用户现有环境（Node / checkout / Edge），不引入需下载的运行时或依赖；确需新增依赖时在 PR 里说明理由。
- **零注入**：主窗口加载官方页面原样；壳脚本只允许注入自己的状态小窗（`ui/status.html`）。
- **就绪判定**：以官方就绪行 `dsh web: http://…` 为准，不得用"HTTP 200"冒充就绪。
- 文档中英文同步（`README.md` / `README.en.md`）。

## 约定

- PR 标题用 conventional 风格：`feat:` / `fix:` / `docs:` / `chore:`。
- 提交前过一遍 `node --check`（JS）与 PowerShell 解析检查（PS1）。
- 启动脚本（`.cmd` / `.ps1`）改动后请在 Windows 上双击实测一遍。

## 本地开发

```powershell
cd dsh-shell
npm install
npm start          # Electron 壳（主入口 src/main.js）
```

Edge 零安装版核心逻辑：`launcher/start-shell-edge.ps1`（可用 `-NoLaunch` 调试，不开窗只走探测/拉起）。

## 验证链路

1. `npm start` → 状态小窗出现
2. 若 3080 有实例 → 直接附着开窗；没有 → 自动拉起后开窗
3. 托盘：显示/隐藏、重启、打开日志
4. 退出 → 由壳拉起的实例一并停止，附着实例不受影响
