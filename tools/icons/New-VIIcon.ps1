<#
.SYNOPSIS
Draws a 32x32 VI icon PNG in the style of the toolkit's icons.

.DESCRIPTION
The toolkit's icons were made in LabVIEW's icon editor with the Windows raster
font "Small Fonts" at 7 px. GDI+ (System.Drawing.Font) cannot use raster fonts
and silently substitutes another font, so the text is drawn through GDI
(CreateFont/TextOut). The result matches the existing icons pixel for pixel.

Layout, measured on the existing icons:
  - 1 px black frame, banner in rows 1-10, black line in row 11, white body.
  - Toolkit style: green banner (00FF00) with "MCP" in black.
  - Test style: red banner (FF6666) without text.
  - Class style: yellow banner (FFFF00) with -BannerText in black.
  - Body text in black capitals, every line centred horizontally;
    one line at row 19, two at rows 15 and 23, three at rows 13, 19 and 25
    (top of the capitals).

Apply the PNG with lvai_set_vi_icon (iconImagePath), then save the VI in
LabVIEW 20.0 format.

.EXAMPLE
.\New-VIIcon.ps1 -Lines 'REPORT','PROGR' -OutFile "$env:TEMP\icon.png" -Show
#>
param(
    [Parameter(Mandatory = $true)][string[]]$Lines,
    [ValidateSet('Toolkit', 'Test', 'Class')][string]$Style = 'Toolkit',
    [string]$BannerText = '',
    [Parameter(Mandatory = $true)][string]$OutFile,
    [switch]$Show
)

$ErrorActionPreference = 'Stop'
if ($Lines.Count -lt 1 -or $Lines.Count -gt 3) { throw 'Give one to three lines.' }
if ($Style -eq 'Class' -and -not $BannerText) { throw 'Class style needs -BannerText.' }

Add-Type -AssemblyName System.Drawing
if (-not ('SmallFontsText' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Runtime.InteropServices;
public static class SmallFontsText {
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateFont(int h, int w, int e, int o, int wt, uint i, uint u, uint s, uint cs, uint op, uint cp, uint q, uint pf, string face);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr o);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr o);
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)] static extern bool TextOut(IntPtr dc, int x, int y, string s, int n);
    [DllImport("gdi32.dll")] static extern int SetBkMode(IntPtr dc, int m);
    [DllImport("gdi32.dll", CharSet = CharSet.Unicode)] static extern int GetTextFaceW(IntPtr dc, int n, System.Text.StringBuilder sb);
    // Returns the ink of the text as rows of '#' and '.', cropped to its bounding box.
    public static string[] Ink(string text) {
        using (var b = new Bitmap(200, 20)) {
            string face;
            using (var g = Graphics.FromImage(b)) {
                g.Clear(Color.White);
                IntPtr dc = g.GetHdc();
                IntPtr f = CreateFont(-7, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 3, 0, "Small Fonts");
                IntPtr old = SelectObject(dc, f);
                SetBkMode(dc, 1);
                TextOut(dc, 2, 2, text, text.Length);
                var sb = new System.Text.StringBuilder(64);
                GetTextFaceW(dc, 64, sb);
                face = sb.ToString();
                SelectObject(dc, old); DeleteObject(f); g.ReleaseHdc(dc);
            }
            if (face != "Small Fonts") throw new Exception("The font Small Fonts is not available (got " + face + ").");
            int x0 = 999, x1 = -1, y0 = 999, y1 = -1;
            for (int y = 0; y < b.Height; y++) for (int x = 0; x < b.Width; x++)
                if (b.GetPixel(x, y).R < 128) { x0 = Math.Min(x0, x); x1 = Math.Max(x1, x); y0 = Math.Min(y0, y); y1 = Math.Max(y1, y); }
            if (x1 < 0) return new string[0];
            var rows = new string[y1 - y0 + 1];
            for (int y = y0; y <= y1; y++) {
                var l = new System.Text.StringBuilder();
                for (int x = x0; x <= x1; x++) l.Append(b.GetPixel(x, y).R < 128 ? '#' : '.');
                rows[y - y0] = l.ToString();
            }
            return rows;
        }
    }
}
'@
}

$black = [System.Drawing.Color]::FromArgb(255, 0, 0, 0)
$white = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
$banner = switch ($Style) {
    'Toolkit' { [System.Drawing.Color]::FromArgb(255, 0, 255, 0) }
    'Test'    { [System.Drawing.Color]::FromArgb(255, 255, 102, 102) }
    'Class'   { [System.Drawing.Color]::FromArgb(255, 255, 255, 0) }
}

$bmp = New-Object System.Drawing.Bitmap 32, 32, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($y = 0; $y -lt 32; $y++) {
    for ($x = 0; $x -lt 32; $x++) {
        $c = if ($x -eq 0 -or $x -eq 31 -or $y -eq 0 -or $y -eq 11 -or $y -eq 31) { $black }
             elseif ($y -le 10) { $banner } else { $white }
        $bmp.SetPixel($x, $y, $c)
    }
}

function Write-Ink([string]$Text, [int]$Top, [int]$Left = -1) {
    # Capitals only: the icons use upper case, and descenders would not fit.
    $ink = [SmallFontsText]::Ink($Text.ToUpperInvariant())
    if ($ink.Count -eq 0) { return }
    $w = $ink[0].Length
    if ($w -gt 28) { throw "'$Text' is $w px wide; at most 28 px fit inside the frame with a 1 px margin." }
    # Centred like the existing icons: x = floor((32 - width) / 2).
    $x0 = if ($Left -ge 0) { $Left } else { [math]::Floor((32 - $w) / 2) }
    for ($r = 0; $r -lt $ink.Count; $r++) {
        for ($i = 0; $i -lt $w; $i++) {
            if ($ink[$r][$i] -eq '#') { $script:bmp.SetPixel($x0 + $i, $Top + $r, $black) }
        }
    }
}

switch ($Style) {
    'Toolkit' { Write-Ink 'MCP' 3 8 }      # exactly where the existing icons have it
    'Class'   { Write-Ink $BannerText 3 }
}

$tops = switch ($Lines.Count) { 1 { , 19 } 2 { 15, 23 } 3 { 13, 19, 25 } }
for ($i = 0; $i -lt $Lines.Count; $i++) { Write-Ink $Lines[$i] $tops[$i] }

# .NET resolves a relative path against the process directory, not the
# PowerShell location, so resolve it here.
$OutFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
$dir = Split-Path -Parent $OutFile
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$bmp.Save($OutFile, [System.Drawing.Imaging.ImageFormat]::Png)

if ($Show) {
    for ($y = 0; $y -lt 32; $y++) {
        $s = ''
        for ($x = 0; $x -lt 32; $x++) {
            $p = $bmp.GetPixel($x, $y)
            $s += if ($p.R -eq 0 -and $p.G -eq 0 -and $p.B -eq 0) { '#' } elseif ($p.R -eq 255 -and $p.G -eq 255 -and $p.B -eq 255) { '.' } else { 'g' }
        }
        $s
    }
}
$bmp.Dispose()


