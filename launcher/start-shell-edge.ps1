# =============================================================================
# DeepSeek Harness 零安装桌面壳（Edge app-mode 版）
#
# 不安装任何东西：复用本机已有的 node + harness checkout + Edge。
#   A0：探测已有实例（默认 http://127.0.0.1:3080），就绪则直接开一个独立桌面窗口
#   A1：没有实例时，用现有环境拉起 `dsh web --port 0`，解析官方就绪行后开窗
#
# 用法：
#   .\start-shell-edge.ps1                          # A0 优先，A1 兜底，开窗
#   .\start-shell-edge.ps1 -AttachUrl http://127.0.0.1:3999   # 换附着地址
#   .\start-shell-edge.ps1 -NoLaunch                # 只做探测/拉起，不开窗（调试）
#   .\start-shell-edge.ps1 -Stop                    # 停止由本脚本拉起的 harness
#
# 注意：关闭 Edge 窗口不会停止 harness（附着模式本来就不归本脚本管；
#       拉起模式用 -Stop 停止，或直接退出 Edge 后运行 -Stop）。
# =============================================================================
[CmdletBinding()]
param(
  [string]$AttachUrl = 'http://127.0.0.1:3080',
  [string]$Checkout = 'D:\workspace\deepseek-harness',
  [string]$NodePath = 'node',
  [ValidateSet('built', 'tsx')]
  [string]$SpawnMode = 'built',   # built = 已构建产物（推荐，无需 esbuild）；tsx = 源码
  [int]$WaitTimeoutSec = 90,
  [switch]$Stop,
  [switch]$NoLaunch
)

function Test-HarnessReady([string]$url) {
  try {
    $r = Invoke-WebRequest -Uri "$url/" -UseBasicParsing -TimeoutSec 3
    return ($r.StatusCode -eq 200 -and $r.Content -match '__DSH_BOOT__')
  } catch { return $false }
}

function Main {
  $ErrorActionPreference = 'Stop'
  $pidFile = Join-Path $env:TEMP 'dsh-edge-launcher.pid'
  $edgeProfile = Join-Path $env:LOCALAPPDATA 'DSH-Edge-Shell'
  $result = @{ Code = 0; Url = $null; Pid = $null }

  if ($Stop) {
    if (Test-Path $pidFile) {
      $pidToKill = [int](Get-Content $pidFile -Raw)
      try { Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue; Write-Host "stopped harness pid $pidToKill" } catch {}
      Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    } else { Write-Host 'no launcher pid file found' }
    return $result
  }

  if (Test-HarnessReady $AttachUrl) {
    $result.Url = $AttachUrl
    Write-Host "attach: $AttachUrl"
  } else {
    Write-Host "no instance at $AttachUrl, starting harness from $Checkout ..."
    if (-not (Test-Path $Checkout)) { Write-Host "ERROR: checkout not found: $Checkout"; $result.Code = 1; return $result }
    if ($SpawnMode -eq 'tsx') {
      $bin = Join-Path $Checkout 'apps\cli\src\bin.ts'
      $args = @('--import', 'tsx/esm', $bin, 'web', '--port', '0')
    } else {
      $bin = Join-Path $Checkout 'apps\cli\lib\bin.js'
      $args = @($bin, 'web', '--port', '0')
    }
    $logFile = Join-Path $env:TEMP 'dsh-edge-launcher.log'
    $errFile = Join-Path $env:TEMP 'dsh-edge-launcher.err.log'
    Remove-Item $logFile, $errFile -Force -ErrorAction SilentlyContinue
    # 输出重定向到文件（不用管道，受限环境也能跑）
    $proc = Start-Process -FilePath $NodePath -ArgumentList $args -WorkingDirectory $Checkout `
      -RedirectStandardOutput $logFile -RedirectStandardError $errFile -WindowStyle Hidden -PassThru
    Set-Content -Path $pidFile -Value $proc.Id
    $result.Pid = $proc.Id
    $deadline = (Get-Date).AddSeconds($WaitTimeoutSec)
    while ((Get-Date) -lt $deadline) {
      if ($proc.HasExited) {
        Write-Host 'harness exited early:'
        if (Test-Path $errFile) { Get-Content $errFile -Tail 20 }
        $result.Code = 1
        return $result
      }
      if (Test-Path $logFile) {
        $match = Select-String -Path $logFile -Pattern '^dsh web: (http://127\.0\.0\.1:\d+)' | Select-Object -Last 1
        if ($match) { $result.Url = $match.Matches[0].Groups[1].Value; break }
      }
      Start-Sleep -Milliseconds 500
    }
    if (-not $result.Url) {
      Write-Host 'timeout waiting for harness ready'
      if (Test-Path $logFile) { Get-Content $logFile -Tail 20 }
      $result.Code = 1
      return $result
    }
    Write-Host "spawned: $($result.Url) (pid $($proc.Id))"
  }

  if ($NoLaunch) { Write-Host 'no-launch mode, done.'; return $result }

  $edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
  if (-not (Test-Path $edge)) { $edge = 'C:\Program Files\Microsoft\Edge\Application\msedge.exe' }
  if (-not (Test-Path $edge)) { Write-Host 'ERROR: msedge.exe not found'; $result.Code = 1; return $result }
  Write-Host "opening Edge app window -> $($result.Url)"
  Start-Process -FilePath $edge -ArgumentList @("--app=$($result.Url)", "--user-data-dir=$edgeProfile", '--window-size=1320,860')
  Write-Host 'done. 停止由本脚本拉起的 harness: .\start-shell-edge.ps1 -Stop'
  return $result
}

$exit = Main
# 仅作为脚本文件运行时才退出进程（dot-source 调试时留在当前会话）
if ($exit.Code -ne 0 -and $MyInvocation.InvocationName -ne '.') { exit $exit.Code }
