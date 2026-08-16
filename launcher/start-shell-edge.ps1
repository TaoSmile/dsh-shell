# =============================================================================
# DeepSeek Harness zero-install desktop shell (Edge app-mode) — fixed build
#
# Reuses the machine's existing node + harness checkout + Edge. Nothing to install.
#   A0: probe existing instance (default http://127.0.0.1:3080) and wrap it in a window
#   A1: otherwise start `dsh web --port <free-port>` with the existing environment
#
# UX:
#   - native splash: a small borderless PowerShell window with animated progress
#     shows IMMEDIATELY while probing/starting the host (no file:// tricks)
#   - window opens DIRECTLY at the GUI URL once the official readiness line prints
#   - single-instance reuse / centered first window / position memory
#   - close-window stops the instance THIS launcher started (attach never touched)
#   - autostart OPTIONAL, default OFF (-ToggleAutostart / -InstallAutostart / -UninstallAutostart)
#   - -CreateDesktopShortcut: desktop shortcut with the whale icon
#
# Usage:
#   .\start-shell-edge.ps1                          # A0 first, A1 fallback, open window
#   .\start-shell-edge.ps1 -AttachUrl http://127.0.0.1:3999
#   .\start-shell-edge.ps1 -NoLaunch                # probe/spawn only, no window (debug)
#   .\start-shell-edge.ps1 -NoWatch                 # return right after opening the window
#   .\start-shell-edge.ps1 -Stop
#   .\start-shell-edge.ps1 -ToggleAutostart
#   .\start-shell-edge.ps1 -InstallAutostart / -UninstallAutostart
#   .\start-shell-edge.ps1 -CreateDesktopShortcut
# =============================================================================
[CmdletBinding()]
param(
  [string]$AttachUrl = 'http://127.0.0.1:3080',
  [string]$Checkout = 'D:\workspace\deepseek-harness',
  [string]$NodePath = 'node',
  [ValidateSet('built', 'tsx')]
  [string]$SpawnMode = 'built',
  [int]$WaitTimeoutSec = 90,
  [switch]$Stop,
  [switch]$NoLaunch,
  [switch]$NoWatch,
  [switch]$ToggleAutostart,
  [switch]$InstallAutostart,
  [switch]$UninstallAutostart,
  [switch]$CreateDesktopShortcut
)

$script:SplashForm = $null
$script:SplashLabel = $null

function Test-HarnessReady([string]$url) {
  try {
    $r = Invoke-WebRequest -Uri "$url/" -UseBasicParsing -TimeoutSec 3
    return ($r.StatusCode -eq 200 -and $r.Content -match '__DSH_BOOT__')
  } catch { return $false }
}

function Find-FreePort {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
  $listener.Start()
  $port = $listener.LocalEndpoint.Port
  $listener.Stop()
  return $port
}

# ---- native splash (best-effort; failures never block the flow) ----
function New-Splash {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $form.Size = New-Object System.Drawing.Size(460, 240)
    $form.BackColor = [System.Drawing.Color]::FromArgb(255, 20, 22, 28)
    $form.TopMost = $true
    $form.ShowInTaskbar = $false

    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Size = New-Object System.Drawing.Size(64, 64)
    $pic.Location = New-Object System.Drawing.Point(24, 40)
    $iconPath = Join-Path $PSScriptRoot '..\assets\icon.png'
    if (Test-Path $iconPath) {
      $pic.Image = [System.Drawing.Image]::FromFile($iconPath)
      $pic.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    }

    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'DeepSeek Harness'
    $title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::White
    $title.AutoSize = $true
    $title.Location = New-Object System.Drawing.Point(112, 34)

    $label = New-Object System.Windows.Forms.Label
    $label.Text = '正在启动…'
    $label.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $label.ForeColor = [System.Drawing.Color]::FromArgb(255, 139, 144, 160)
    $label.Size = New-Object System.Drawing.Size(320, 44)
    $label.Location = New-Object System.Drawing.Point(112, 66)

    $bar = New-Object System.Windows.Forms.ProgressBar
    $bar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    $bar.MarqueeAnimationSpeed = 30
    $bar.Size = New-Object System.Drawing.Size(412, 6)
    $bar.Location = New-Object System.Drawing.Point(24, 176)

    $form.Controls.AddRange(@($pic, $title, $label, $bar))
    $script:SplashLabel = $label
    $script:SplashForm = $form
    $form.Show()
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
    return $true
  } catch { return $false }
}

function Update-Splash([string]$text) {
  if ($script:SplashLabel) {
    try { $script:SplashLabel.Text = $text; [System.Windows.Forms.Application]::DoEvents() } catch {}
  }
}

function Pump-Splash {
  if ($script:SplashForm) {
    try { [System.Windows.Forms.Application]::DoEvents() } catch {}
  }
}

function Close-Splash {
  if ($script:SplashForm) {
    try { $script:SplashForm.Close(); $script:SplashForm.Dispose() } catch {}
    $script:SplashForm = $null
    $script:SplashLabel = $null
  }
}

function Fail-Splash([string]$reason) {
  if ($script:SplashForm) {
    Update-Splash "启动失败：$reason"
    Start-Sleep -Seconds 6
    Close-Splash
  }
}

function Wait-ReadyUrl($proc, $logFile, $errFile) {
  $deadline = (Get-Date).AddSeconds($WaitTimeoutSec)
  while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) { return @{ Failed = $true; Reason = 'harness exited during startup' } }
    if (Test-Path $logFile) {
      $match = Select-String -Path $logFile -Pattern '^dsh web: (http://127\.0\.0\.1:\d+)' | Select-Object -Last 1
      if ($match) { return @{ Failed = $false; Url = $match.Matches[0].Groups[1].Value } }
    }
    Pump-Splash
    Start-Sleep -Milliseconds 500
  }
  return @{ Failed = $true; Reason = "timeout after $WaitTimeoutSec s" }
}

function Main {
  $ErrorActionPreference = 'Stop'
  $pidFile = Join-Path $env:TEMP 'dsh-edge-launcher.pid'
  $urlFile = Join-Path $env:TEMP 'dsh-edge-launcher.url'
  $edgeProfile = Join-Path $env:LOCALAPPDATA 'DSH-Edge-Shell'
  $regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  $regName = 'DeepSeekHarnessDesktop'
  $result = @{ Code = 0; Url = $null; Pid = $null; Owned = $false }

  # ---- -Stop ----
  if ($Stop) {
    if (Test-Path $pidFile) {
      $pidToKill = [int](Get-Content $pidFile -Raw)
      try { Stop-Process -Id $pidToKill -Force -ErrorAction SilentlyContinue; Write-Host "stopped harness pid $pidToKill" } catch {}
    } else { Write-Host 'no launcher pid file found' }
    Remove-Item $pidFile, $urlFile -Force -ErrorAction SilentlyContinue
    return $result
  }

  # ---- autostart (optional, default OFF) ----
  if ($InstallAutostart) {
    $vbs = Join-Path $PSScriptRoot '..\启动Harness桌面.vbs'
    if (-not (Test-Path $vbs)) { Write-Host "ERROR: vbs not found: $vbs"; $result.Code = 1; return $result }
    Set-ItemProperty -Path $regPath -Name $regName -Value ('wscript.exe "' + $vbs + '"')
    Write-Host "autostart installed -> $vbs"
    return $result
  }
  if ($UninstallAutostart) {
    Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
    Write-Host 'autostart removed'
    return $result
  }
  if ($ToggleAutostart) {
    $vbs = Join-Path $PSScriptRoot '..\启动Harness桌面.vbs'
    $isOn = $null -ne (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue)
    $pop = New-Object -ComObject WScript.Shell
    if ($isOn) {
      $answer = $pop.Popup('开机自启当前：已开启' + [char]10 + [char]10 + '是否关闭？', 0, 'DeepSeek Harness 开机自启', 36)
      if ($answer -eq 6) {
        Remove-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
        $pop.Popup('已关闭开机自启。', 0, 'DeepSeek Harness', 64) | Out-Null
      }
    } else {
      $answer = $pop.Popup('开机自启当前：已关闭' + [char]10 + [char]10 + '是否开启？', 0, 'DeepSeek Harness 开机自启', 36)
      if ($answer -eq 6) {
        if (Test-Path $vbs) {
          Set-ItemProperty -Path $regPath -Name $regName -Value ('wscript.exe "' + $vbs + '"')
          $pop.Popup('已开启开机自启。', 0, 'DeepSeek Harness', 64) | Out-Null
        } else {
          $pop.Popup('未找到启动文件，开启失败。', 0, 'DeepSeek Harness', 16) | Out-Null
        }
      }
    }
    return $result
  }

  # ---- desktop shortcut ----
  if ($CreateDesktopShortcut) {
    $vbs = Join-Path $PSScriptRoot '..\启动Harness桌面.vbs'
    $ico = Join-Path $PSScriptRoot '..\assets\icon.ico'
    $ws = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath('Desktop')
    $lnkPath = Join-Path $desktop 'DeepSeek Harness.lnk'
    $lnk = $ws.CreateShortcut($lnkPath)
    $lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
    $lnk.Arguments = '"' + $vbs + '"'
    $lnk.WorkingDirectory = Join-Path $PSScriptRoot '..'
    $lnk.IconLocation = $ico + ',0'
    $lnk.Description = 'DeepSeek Harness 桌面端'
    $lnk.Save()
    Write-Host "desktop shortcut created: $lnkPath"
    return $result
  }

  # ---- splash (best-effort) ----
  if (-not $NoLaunch) { New-Splash | Out-Null; Update-Splash '正在检查 Harness 实例…' }

  # ---- single-instance reuse ----
  if (Test-Path $pidFile) {
    $prevPid = [int](Get-Content $pidFile -Raw)
    $prevUrl = if (Test-Path $urlFile) { (Get-Content $urlFile -Raw).Trim() } else { $null }
    $prevProc = Get-Process -Id $prevPid -ErrorAction SilentlyContinue
    if ($prevProc -and $prevUrl -and (Test-HarnessReady $prevUrl)) {
      $result.Url = $prevUrl
      Write-Host "reuse: $prevUrl (pid $prevPid)"
    } else {
      Remove-Item $pidFile, $urlFile -Force -ErrorAction SilentlyContinue
    }
  }

  # ---- A0 attach ----
  if (-not $result.Url) {
    if (Test-HarnessReady $AttachUrl) {
      $result.Url = $AttachUrl
      Write-Host "attach: $AttachUrl"
    }
  }

  # ---- A1 spawn (fixed free port chosen by the launcher) ----
  if (-not $result.Url) {
    Write-Host "no instance at $AttachUrl, starting harness from $Checkout ..."
    if (-not (Test-Path $Checkout)) {
      Write-Host "ERROR: checkout not found: $Checkout"
      Fail-Splash "找不到 harness 目录：$Checkout"
      $result.Code = 1
      return $result
    }
    $port = Find-FreePort
    $result.Url = "http://127.0.0.1:$port"
    if ($SpawnMode -eq 'tsx') {
      $bin = Join-Path $Checkout 'apps\cli\src\bin.ts'
      $args = @('--import', 'tsx/esm', $bin, 'web', '--port', "$port")
    } else {
      $bin = Join-Path $Checkout 'apps\cli\lib\bin.js'
      $args = @($bin, 'web', '--port', "$port")
    }
    $logFile = Join-Path $env:TEMP 'dsh-edge-launcher.log'
    $errFile = Join-Path $env:TEMP 'dsh-edge-launcher.err.log'
    Remove-Item $logFile, $errFile -Force -ErrorAction SilentlyContinue
    $proc = Start-Process -FilePath $NodePath -ArgumentList $args -WorkingDirectory $Checkout `
      -RedirectStandardOutput $logFile -RedirectStandardError $errFile -WindowStyle Hidden -PassThru
    Set-Content -Path $pidFile -Value $proc.Id
    Set-Content -Path $urlFile -Value $result.Url
    $result.Owned = $true
    $result.Pid = $proc.Id
    Write-Host "spawning: $($result.Url) (pid $($proc.Id))"
    Update-Splash '正在启动 Harness（首次启动需要几秒）…'

    if ($NoLaunch) {
      $ready = Wait-ReadyUrl $proc $logFile $errFile
      if ($ready.Failed) {
        Write-Host "ERROR: $($ready.Reason)"
        if (Test-Path $errFile) { Get-Content $errFile -Tail 20 }
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        Remove-Item $pidFile, $urlFile -Force -ErrorAction SilentlyContinue
        $result.Code = 1
        return $result
      }
      $result.Url = $ready.Url
      Write-Host "ready: $($ready.Url) (no-launch mode)"
      return $result
    }
  }

  if ($NoLaunch) { Write-Host 'no-launch mode, done.'; return $result }

  # ---- owned instance: wait for the official readiness line ----
  if ($result.Owned) {
    $ready = Wait-ReadyUrl $proc $logFile $errFile
    if ($ready.Failed) {
      Write-Host "ERROR: $($ready.Reason)"
      if (Test-Path $logFile) { Get-Content $logFile -Tail 20 }
      if (Test-Path $errFile) { Get-Content $errFile -Tail 20 }
      try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
      Remove-Item $pidFile, $urlFile -Force -ErrorAction SilentlyContinue
      Fail-Splash $ready.Reason
      $result.Code = 1
      return $result
    }
    $result.Url = $ready.Url
    Write-Host "ready: $ready.Url"
  } else {
    Update-Splash '已连接，正在打开窗口…'
  }

  Close-Splash

  # ---- open the window DIRECTLY at the GUI URL ----
  $edge = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
  if (-not (Test-Path $edge)) { $edge = 'C:\Program Files\Microsoft\Edge\Application\msedge.exe' }
  if (-not (Test-Path $edge)) { Write-Host 'ERROR: msedge.exe not found'; $result.Code = 1; return $result }
  $edgeArgs = @("--app=$($result.Url)", "--user-data-dir=$edgeProfile", '--disable-background-mode', '--no-first-run', '--no-default-browser-check')
  # 每次启动都按屏幕工作区居中（小屏自动收缩尺寸）
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $winW = [Math]::Min(1320, $wa.Width - 80)
    $winH = [Math]::Min(860, $wa.Height - 80)
    $posX = [int]($wa.Left + ($wa.Width - $winW) / 2)
    $posY = [int]($wa.Top + ($wa.Height - $winH) / 2)
    $edgeArgs += "--window-size=$winW,$winH"
    $edgeArgs += "--window-position=$posX,$posY"
  } catch { }
  Write-Host "opening window -> $($result.Url)"
  $edgeProc = Start-Process -FilePath $edge -ArgumentList $edgeArgs -PassThru

  # ---- close-window stops the instance this launcher started ----
  if ($result.Owned -and -not $NoWatch) {
    $edgeProc.WaitForExit()
    Write-Host 'Edge window closed; stopping harness spawned by this launcher...'
    try { Stop-Process -Id ([int]$result.Pid) -Force -ErrorAction SilentlyContinue } catch {}
    Remove-Item $pidFile, $urlFile -Force -ErrorAction SilentlyContinue
  }
  return $result
}

$exit = Main
# exit the process only when run as a script file (dot-sourced runs stay in session)
if ($exit.Code -ne 0 -and $MyInvocation.InvocationName -ne '.') { exit $exit.Code }
