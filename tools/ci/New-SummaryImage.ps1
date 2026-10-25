<#
.SYNOPSIS
Crops a block diagram picture to the spot a code summary talks about and marks
the nodes it explains with numbered boxes.

.DESCRIPTION
Pull request code summaries show only the parts of a diagram that explain the
change (see docs/pull-request-reports.md). This script makes such a picture
from an image of the diff report or of a rendered case frame:

- crops it to one rectangle (optional),
- draws an orange box with a numbered badge around each highlighted spot, so
  the summary text can refer to "1", "2", ... in the same order,
- scales it down if it is wider than -MaxWidth,
- leaves a white margin so badges at the edge stay visible.

All coordinates are pixels of the SOURCE image, as x,y,width,height. Find them
by opening the source image; the crop is applied after the boxes are placed,
so the same coordinates work with or without -Crop.

.EXAMPLE
.\New-SummaryImage.ps1 -Source frames\3-bounds-integer.png -OutFile summary\integer.png `
    -Crop '0,0,2400,700' -Highlight '1000,330,260,160', '1700,90,120,60'
#>
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [string]$Crop,
    [string[]]$Highlight = @(),
    [int]$MaxWidth = 1600,
    [int]$Margin = 16
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function ConvertTo-Rect([string]$Text) {
    $v = @($Text -split ',' | ForEach-Object { [int]$_.Trim() })
    if ($v.Count -ne 4) { throw "Expected x,y,width,height, got '$Text'." }
    return New-Object System.Drawing.Rectangle $v[0], $v[1], $v[2], $v[3]
}

# Accept a URL as well as a file, so images on the pr-assets branch can be used directly.
$sourceFile = $Source
if ($Source -match '^https?://') {
    $sourceFile = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName() + '.png')
    Invoke-WebRequest -Uri $Source -OutFile $sourceFile -UseBasicParsing
}
$image = [System.Drawing.Image]::FromFile((Resolve-Path $sourceFile).Path)

try {
    $area = if ($Crop) { ConvertTo-Rect $Crop } else { New-Object System.Drawing.Rectangle 0, 0, $image.Width, $image.Height }
    $area.Intersect((New-Object System.Drawing.Rectangle 0, 0, $image.Width, $image.Height))
    if ($area.Width -le 0 -or $area.Height -le 0) { throw "The crop rectangle lies outside the image ($($image.Width)x$($image.Height))." }

    $scale = [Math]::Min(1.0, $MaxWidth / [double]($area.Width + 2 * $Margin))
    $width = [int][Math]::Ceiling(($area.Width + 2 * $Margin) * $scale)
    $height = [int][Math]::Ceiling(($area.Height + 2 * $Margin) * $scale)

    $out = New-Object System.Drawing.Bitmap $width, $height
    $g = [System.Drawing.Graphics]::FromImage($out)
    try {
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.Clear([System.Drawing.Color]::White)

        # Diagram first, in output coordinates.
        $target = New-Object System.Drawing.RectangleF ($Margin * $scale), ($Margin * $scale), ($area.Width * $scale), ($area.Height * $scale)
        $g.DrawImage($image, $target, $area, [System.Drawing.GraphicsUnit]::Pixel)

        # Boxes and badges keep a fixed on-screen size, whatever the scale.
        $orange = [System.Drawing.Color]::FromArgb(255, 245, 124, 0)
        $pen = New-Object System.Drawing.Pen $orange, 3
        $fill = New-Object System.Drawing.SolidBrush $orange
        $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        $font = New-Object System.Drawing.Font 'Segoe UI', 11, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
        $format = New-Object System.Drawing.StringFormat
        $format.Alignment = [System.Drawing.StringAlignment]::Center
        $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        $badge = 22

        $number = 0
        foreach ($h in $Highlight) {
            $number++
            $r = ConvertTo-Rect $h
            $x = ($r.X - $area.X + $Margin) * $scale
            $y = ($r.Y - $area.Y + $Margin) * $scale
            $g.DrawRectangle($pen, [float]$x, [float]$y, [float]($r.Width * $scale), [float]($r.Height * $scale))

            $bx = [Math]::Max(0, [Math]::Min($width - $badge, $x - $badge / 2))
            $by = [Math]::Max(0, [Math]::Min($height - $badge, $y - $badge / 2))
            $g.FillEllipse($fill, [float]$bx, [float]$by, $badge, $badge)
            $g.DrawString([string]$number, $font, $white, (New-Object System.Drawing.RectangleF ([float]$bx), ([float]$by), $badge, $badge), $format)
        }
    }
    finally { $g.Dispose() }

    # .NET resolves a relative path against the process directory, not the
    # PowerShell location, so resolve it here.
    $OutFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $out.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)
    $out.Dispose()
    Write-Output "$OutFile ($width x $height, $number highlight(s))"
}
finally {
    $image.Dispose()
    if ($sourceFile -ne $Source) { Remove-Item $sourceFile -ErrorAction SilentlyContinue }
}
