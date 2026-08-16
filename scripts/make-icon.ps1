# =============================================================================
# dsh-shell icon generator: DeepSeek-style whale mark
# Outputs: assets/icon.png(512) / icon.ico(16,32,48,256) / tray.png(32)
# Requires: Windows PowerShell or pwsh + System.Drawing (local, no network)
# Usage: powershell -ExecutionPolicy Bypass -File scripts\make-icon.ps1
# =============================================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$outDir = Join-Path $PSScriptRoot '..\assets'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$C_BG_TOP = [System.Drawing.Color]::FromArgb(255, 79, 70, 229)    # #4F46E5 indigo
$C_BG_BOT = [System.Drawing.Color]::FromArgb(255, 30, 27, 75)     # #1E1B4B deep indigo
$C_FG = [System.Drawing.Color]::White

function New-RoundedRectPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

function New-WhalePath([float]$s) {
  # whale on s*s canvas: ellipse body + bezier twin-fluke tail (unit = canvas fraction)
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  # body (slightly left)
  $p.AddEllipse($s * 0.18, $s * 0.30, $s * 0.52, $s * 0.40)
  # tail: body right edge (0.70,0.50) -> upper fluke (0.94,0.22), notch (0.88,0.50), lower fluke (0.94,0.78)
  $p.AddBezier(
    $s * 0.70, $s * 0.50,
    $s * 0.80, $s * 0.38,
    $s * 0.88, $s * 0.30,
    $s * 0.94, $s * 0.22)
  $p.AddLine($s * 0.94, $s * 0.22, $s * 0.88, $s * 0.50)
  $p.AddLine($s * 0.88, $s * 0.50, $s * 0.94, $s * 0.78)
  $p.AddBezier(
    $s * 0.94, $s * 0.78,
    $s * 0.88, $s * 0.70,
    $s * 0.80, $s * 0.62,
    $s * 0.70, $s * 0.50)
  $p.CloseFigure()
  return $p
}

function New-IconBitmap([int]$size) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)

  # gradient rounded background
  $clip = New-RoundedRectPath 0 0 $size $size ($size * 0.22)
  $rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $C_BG_TOP, $C_BG_BOT, 45)
  $g.FillPath($brush, $clip)

  # whale
  $whale = New-WhalePath ([float]$size)
  $g.FillPath((New-Object System.Drawing.SolidBrush($C_FG)), $whale)

  # eye (background-colored dot)
  $eyeR = $size * 0.032
  $eyeBrush = New-Object System.Drawing.SolidBrush($C_BG_TOP)
  $g.FillEllipse($eyeBrush, $size * 0.31 - $eyeR, $size * 0.46 - $eyeR, $eyeR * 2, $eyeR * 2)

  # subtle top highlight arc
  $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(90, 255, 255, 255), [float]($size * 0.025))
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $g.DrawArc($pen, $size * 0.26, $size * 0.30, $size * 0.30, $size * 0.20, 200, 120)

  $g.Dispose()
  return $bmp
}

function Save-Png($bmp, $path) {
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function New-IcoFromPngs([hashtable]$pngs, $path) {
  # ICO container: ICONDIR + ICONDIRENTRY*N + PNG blobs (Vista+ accepts PNG for all sizes)
  $fs = [System.IO.File]::Create($path)
  $w = [System.IO.BinaryWriter]::new($fs)
  $w.Write([UInt16]0)          # reserved
  $w.Write([UInt16]1)          # type: icon
  $w.Write([UInt16]$pngs.Count)
  $offset = 6 + 16 * $pngs.Count
  foreach ($size in ($pngs.Keys | Sort-Object)) {
    $bytes = [System.IO.File]::ReadAllBytes($pngs[$size])
    $w.Write([byte]($(if ($size -ge 256) { 0 } else { $size })))  # width (0 = 256)
    $w.Write([byte]($(if ($size -ge 256) { 0 } else { $size })))  # height
    $w.Write([byte]0)          # palette
    $w.Write([byte]0)          # reserved
    $w.Write([UInt16]1)        # planes
    $w.Write([UInt16]32)       # bpp
    $w.Write([UInt32]$bytes.Length)
    $w.Write([UInt32]$offset)
    $offset += $bytes.Length
  }
  foreach ($size in ($pngs.Keys | Sort-Object)) {
    $w.Write([System.IO.File]::ReadAllBytes($pngs[$size]))
  }
  $w.Dispose(); $fs.Dispose()
}

# ---- render ----
$tmp = Join-Path $env:TEMP 'dsh-shell-icons'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$b512 = New-IconBitmap 512
Save-Png $b512 (Join-Path $outDir 'icon.png')
$b512.Dispose()
Write-Host 'icon.png (512) written'

$pngs = @{}
foreach ($size in @(16, 32, 48, 256)) {
  $bmp = New-IconBitmap $size
  $tmpPath = Join-Path $tmp "icon-$size.png"
  Save-Png $bmp $tmpPath
  $bmp.Dispose()
  $pngs[$size] = $tmpPath
}
New-IcoFromPngs $pngs (Join-Path $outDir 'icon.ico')
Write-Host 'icon.ico (16/32/48/256) written'

$b32 = New-IconBitmap 32
Save-Png $b32 (Join-Path $outDir 'tray.png')
$b32.Dispose()
Write-Host 'tray.png (32) written'

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem $outDir | Format-Table Name, Length -AutoSize