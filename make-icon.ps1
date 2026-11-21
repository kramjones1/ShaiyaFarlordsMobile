<#
    make-icon.ps1 - generates the Shaiya Farlords launcher icon set.
    Output: D:\ShaiyaAPK\branding\
      mipmap-*/ic_launcher.png            legacy square icon
      mipmap-*/ic_launcher_foreground.png adaptive-icon foreground (66% safe zone)
      ic_launcher_playstore.png           512x512 master

    Design: dark slate rounded plate, gold ring, gold-rimmed shield with a
    single upright sword. Shapes are few and bold so the icon survives 48 px.
#>

[CmdletBinding()]
param([string]$OutDir = 'D:\ShaiyaAPK\branding')

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$densities = [ordered]@{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }

function New-Canvas([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    return @($bmp, $g)
}

function New-RoundRect([System.Drawing.RectangleF]$rect, [double]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
    $p.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
    $p.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
    $p.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function Draw-Icon([System.Drawing.Graphics]$g, [int]$size, [double]$contentScale) {
    $g.Clear([System.Drawing.Color]::Transparent)

    $cx = $size / 2.0
    $cy = $size / 2.0
    $unit = $size * 0.5 * $contentScale

    # ---- plate -------------------------------------------------------------
    $pad  = $size * 0.02
    $side = $size - 2 * $pad
    $plate = New-RoundRect (New-Object System.Drawing.RectangleF($pad, $pad, $side, $side)) ($size * 0.22)

    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF(0, 0)),
        (New-Object System.Drawing.PointF(0, $size)),
        [System.Drawing.Color]::FromArgb(255, 26, 31, 43),
        [System.Drawing.Color]::FromArgb(255, 7, 9, 13))
    $g.FillPath($bg, $plate)
    $bg.Dispose()

    # ---- glow behind the emblem -------------------------------------------
    $glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gd = $size * 0.80
    $glowPath.AddEllipse((($size - $gd) / 2), (($size - $gd) / 2), $gd, $gd)
    $pgb = New-Object System.Drawing.Drawing2D.PathGradientBrush($glowPath)
    $pgb.CenterColor = [System.Drawing.Color]::FromArgb(60, 236, 186, 94)
    $pgb.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 236, 186, 94))
    $g.FillPath($pgb, $glowPath)
    $pgb.Dispose(); $glowPath.Dispose()

    # ---- gold ring ---------------------------------------------------------
    $ringR = $unit * 0.95
    $penGold = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 216, 166, 76), [Math]::Max(1.2, $size * 0.026))
    $g.DrawEllipse($penGold, ($cx - $ringR), ($cy - $ringR), ($ringR * 2), ($ringR * 2))
    $penGold.Dispose()

    # ---- shield ------------------------------------------------------------
    $shield = New-Object System.Drawing.Drawing2D.GraphicsPath
    $top     = -0.52 * $unit
    $shoulder = 0.06 * $unit
    $bottom  = 0.56 * $unit
    $halfW   = 0.40 * $unit

    $shield.AddLine($cx, ($cy + $top), ($cx + $halfW), ($cy + $top + 0.10 * $unit))
    $shield.AddLine(($cx + $halfW), ($cy + $top + 0.10 * $unit), ($cx + $halfW), ($cy + $shoulder))
    $shield.AddBezier(($cx + $halfW), ($cy + $shoulder), ($cx + $halfW), ($cy + 0.34 * $unit), ($cx + 0.20 * $unit), ($cy + 0.46 * $unit), $cx, ($cy + $bottom))
    $shield.AddBezier($cx, ($cy + $bottom), ($cx - 0.20 * $unit), ($cy + 0.46 * $unit), ($cx - $halfW), ($cy + 0.34 * $unit), ($cx - $halfW), ($cy + $shoulder))
    $shield.AddLine(($cx - $halfW), ($cy + $shoulder), ($cx - $halfW), ($cy + $top + 0.10 * $unit))
    $shield.CloseFigure()

    $shieldFill = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF($cx, ($cy + $top))),
        (New-Object System.Drawing.PointF($cx, ($cy + $bottom))),
        [System.Drawing.Color]::FromArgb(255, 46, 56, 76),
        [System.Drawing.Color]::FromArgb(255, 16, 20, 29))
    $g.FillPath($shieldFill, $shield)
    $shieldFill.Dispose()

    $penShield = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 214, 164, 74), [Math]::Max(1.0, $size * 0.024))
    $g.DrawPath($penShield, $shield)
    $penShield.Dispose()

    # ---- sword (upright, centred) -----------------------------------------
    $bladeTop = -0.40 * $unit
    $bladeBottom = 0.10 * $unit
    $bladeHalf = 0.062 * $unit

    $blade = New-Object System.Drawing.Drawing2D.GraphicsPath
    $blade.AddPolygon(@(
        (New-Object System.Drawing.PointF($cx, ($cy + $bladeTop))),
        (New-Object System.Drawing.PointF(($cx + $bladeHalf), ($cy + $bladeBottom - 0.06 * $unit))),
        (New-Object System.Drawing.PointF(($cx + $bladeHalf), ($cy + $bladeBottom))),
        (New-Object System.Drawing.PointF(($cx - $bladeHalf), ($cy + $bladeBottom))),
        (New-Object System.Drawing.PointF(($cx - $bladeHalf), ($cy + $bladeBottom - 0.06 * $unit)))
    ))

    $steel = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF(($cx - $bladeHalf), 0)),
        (New-Object System.Drawing.PointF(($cx + $bladeHalf), 0)),
        [System.Drawing.Color]::FromArgb(255, 252, 253, 255),
        [System.Drawing.Color]::FromArgb(255, 146, 160, 178))
    $g.FillPath($steel, $blade)
    $penEdge = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 38, 45, 58), [Math]::Max(0.8, $size * 0.005))
    $g.DrawPath($penEdge, $blade)
    $steel.Dispose(); $blade.Dispose()

    $goldBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF(($cx - 0.24 * $unit), 0)),
        (New-Object System.Drawing.PointF(($cx + 0.24 * $unit), 0)),
        [System.Drawing.Color]::FromArgb(255, 248, 210, 130),
        [System.Drawing.Color]::FromArgb(255, 190, 132, 46))

    # crossguard
    $guard = New-Object System.Drawing.RectangleF(($cx - 0.22 * $unit), ($cy + 0.10 * $unit), (0.44 * $unit), (0.075 * $unit))
    $g.FillRectangle($goldBrush, $guard)
    $g.DrawRectangle($penEdge, $guard.X, $guard.Y, $guard.Width, $guard.Height)

    # grip + pommel
    $grip = New-Object System.Drawing.RectangleF(($cx - 0.034 * $unit), ($cy + 0.175 * $unit), (0.068 * $unit), (0.20 * $unit))
    $g.FillRectangle($goldBrush, $grip)
    $pr = 0.055 * $unit
    $g.FillEllipse($goldBrush, ($cx - $pr), ($cy + 0.375 * $unit), ($pr * 2), ($pr * 2))
    $g.DrawEllipse($penEdge, ($cx - $pr), ($cy + 0.375 * $unit), ($pr * 2), ($pr * 2))

    $goldBrush.Dispose(); $penEdge.Dispose(); $shield.Dispose(); $plate.Dispose()
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

foreach ($k in $densities.Keys) {
    $size = $densities[$k]
    $dir  = Join-Path $OutDir "mipmap-$k"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $pair = New-Canvas $size
    $bmp = $pair[0]; $g = $pair[1]
    Draw-Icon -g $g -size $size -contentScale 1.0
    $g.Dispose()
    $bmp.Save((Join-Path $dir 'ic_launcher.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    $pair = New-Canvas $size
    $bmp = $pair[0]; $g = $pair[1]
    Draw-Icon -g $g -size $size -contentScale 0.60
    $g.Dispose()
    $bmp.Save((Join-Path $dir 'ic_launcher_foreground.png'), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()

    Write-Host ("  mipmap-{0,-8} {1,3}px" -f $k, $size)
}

$pair = New-Canvas 512
$bmp = $pair[0]; $g = $pair[1]
Draw-Icon -g $g -size 512 -contentScale 1.0
$g.Dispose()
$bmp.Save((Join-Path $OutDir 'ic_launcher_playstore.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Host "icon set written to $OutDir"
