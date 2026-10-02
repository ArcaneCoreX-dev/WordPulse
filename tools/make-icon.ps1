# make-icon.ps1 — 生成 WordPulse 专属桌面图标（assets\WordPulse.ico）
# 设计：深蓝圆角卡片 + 白色 "W" + 三条下划线（单词卡片意象），呼应 GUI 主色 #1A2E5C
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$root  = Split-Path -Parent $PSScriptRoot
$asset = Join-Path $root 'assets'
if (-not (Test-Path $asset)) { New-Item -ItemType Directory -Force -Path $asset | Out-Null }
$icoPath = Join-Path $asset 'WordPulse.ico'
$pngPath = Join-Path $asset 'WordPulse_256.png'

Add-Type -AssemblyName System.Drawing

# 绘制 256x256 位图
$size = 256
$bmp = New-Object System.Drawing.Bitmap($size, $size)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.Clear([System.Drawing.Color]::Transparent)

# 背景：深蓝圆角卡片
$bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 26, 46, 92))  # #1A2E5C
$radius = 48
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$d = $radius * 2
$path.AddArc(0, 0, $d, $d, 180, 90)
$path.AddArc($size - $d, 0, $d, $d, 270, 90)
$path.AddArc($size - $d, $size - $d, $d, $d, 0, 90)
$path.AddArc(0, $size - $d, $d, $d, 90, 90)
$path.CloseFigure()
$g.FillPath($bgBrush, $path)

# 白色 "W"（三峰形状）
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$font = New-Object System.Drawing.Font('Segoe UI', 130, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = 'Center'
$sf.LineAlignment = 'Center'
$rectW = New-Object System.Drawing.RectangleF(0, 22, $size, 170)
$g.DrawString('W', $font, $white, $rectW, $sf)

# 三条下划线（单词卡片意象）
$lineBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 127, 181, 244))  # 浅蓝 #7FB5F4
$linePen = New-Object System.Drawing.Pen($lineBrush, 10)
$linePen.StartCap = 'Round'
$linePen.EndCap = 'Round'
$y0 = 196
$g.DrawLine($linePen, 66, $y0, 190, $y0)
$g.DrawLine($linePen, 66, $y0 + 26, 190, $y0 + 26)
$g.DrawLine($linePen, 66, $y0 + 52, 132, $y0 + 52)

# 保存 PNG（供 ico 内嵌，256x256 现代 ICO 支持 PNG 数据）
$bmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# 拼装 ICO（PNG 内嵌格式：ICONDIR + ICONDIRENTRY + PNG）
$pngBytes = [System.IO.File]::ReadAllBytes($pngPath)
$ico = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ico)
# ICONDIR: reserved(2)=0, type(2)=1, count(2)=1  （显式小端字节，避免 PS 重载歧义）
$bw.Write([byte]0); $bw.Write([byte]0)
$bw.Write([byte]1); $bw.Write([byte]0)
$bw.Write([byte]1); $bw.Write([byte]0)
# ICONDIRENTRY: w(1)=0(256), h(1)=0, colors(1)=0, reserved(1)=0
$bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0)
# planes(2)=1 小端: 01 00
$bw.Write([byte]1); $bw.Write([byte]0)
# bitcount(2)=32 小端: 20 00
$bw.Write([byte]32); $bw.Write([byte]0)
# bytesInRes(4)=png 长度 小端
$len = $pngBytes.Length
$bw.Write([byte]($len -band 0xFF))
$bw.Write([byte](($len -shr 8) -band 0xFF))
$bw.Write([byte](($len -shr 16) -band 0xFF))
$bw.Write([byte](($len -shr 24) -band 0xFF))
# imageOffset(4)=22 小端
$bw.Write([byte]22); $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([byte]0)
$bw.Write($pngBytes)
$bw.Flush()
[System.IO.File]::WriteAllBytes($icoPath, $ico.ToArray())
$bw.Dispose(); $ico.Dispose()

Write-Host ("已生成图标: {0} ({1} bytes)" -f $icoPath, [System.IO.File]::ReadAllBytes($icoPath).Length)
Write-Host ("源 PNG 保留: {0}" -f $pngPath)
