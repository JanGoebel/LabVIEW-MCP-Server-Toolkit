<#
.SYNOPSIS
Builds a graphical diff report for the LabVIEW files changed between two commits.

.DESCRIPTION
GitHub cannot diff VIs. This script lists the .vi/.vim/.ctl files that differ
between BaseRef and the files in HeadDir, runs LabVIEW's own comparison
(LabVIEWCLI CreateComparisonReport) for each of them and writes

    <OutDir>\report.md      Markdown with before/after images per difference
    <OutDir>\images\...     the images the Markdown refers to (relative links)
    <OutDir>\summary.md     the short version for the pull request comment

LabVIEW's comparison images show each case structure on its visible frame
only. For every added VI and the new version of every modified VI the report
therefore also gets a folded "All case frames" section: Print Diagram
Frames.vi (next to this script, run through LabVIEW CLI RunVI in the same
LabVIEW) prints the VI with Print.VI To HTML, which writes one picture per
hidden frame, and lists the frames in LabVIEW's print order, so each picture
is captioned with its structure and selector value. When the pictures and the
list do not agree, the pictures are numbered instead of named.

The old versions are taken from a temporary full checkout of BaseRef, so an old
VI finds its own library and subVIs and only real differences are reported.
Position and size changes are left out of the comparison.

A failed comparison is noted in the report, and the reports are always
written. When LabVIEW cannot be reached at all (LabVIEW CLI error -350000),
the remaining comparisons are skipped instead of each waiting for the same
connection timeout, and the report says so.

Exit code: 0 when every changed VI was compared and its frames printed, 1
when at least one comparison or frame print failed or was skipped. A pull
request needs the diff, so the workflow fails on 1.
#>
param(
    [Parameter(Mandatory = $true)][string]$BaseRef,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [string]$HeadDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$LabVIEWPath = 'C:\Program Files (x86)\National Instruments\LabVIEW 2026\LabVIEW.exe',
    [int]$PortNumber = 3363
)

$ErrorActionPreference = 'Stop'
$extensions = @('.vi', '.vim', '.ctl')
$utf8 = New-Object System.Text.UTF8Encoding $false

Import-Module (Join-Path $PSScriptRoot 'LabVIEWCi.psm1') -Force
if (-not (Get-LabVIEWCliPath)) { Write-Warning 'LabVIEW CLI (LabVIEWCLI.exe) is not installed; no VI can be compared.' }
$script:portRetried = $false
# Prints every case frame of the new version of each VI. Absent on a base
# branch that predates it; the report then shows visible frames only.
$framePrinter = Join-Path $PSScriptRoot 'Print Diagram Frames.vi'
if (-not (Test-Path -LiteralPath $framePrinter)) { $framePrinter = $null; Write-Warning "$(Join-Path $PSScriptRoot 'Print Diagram Frames.vi') not found; case frames are not printed." }

function Invoke-CliComparison([string]$Vi1, [string]$Vi2, [string]$ReportPath) {
    # LabVIEW CLI writes its error text to stderr; keep it for the report.
    $run = Invoke-NativeCommand 'LabVIEWCLI' @('-OperationName', 'CreateComparisonReport', '-VI1', $Vi1, '-VI2', $Vi2,
        '-ReportType', 'html', '-ReportPath', $ReportPath, '-o', '-c', '-nobdcosm', '-nofppos',
        '-LabVIEWPath', $LabVIEWPath, '-PortNumber', $script:PortNumber)
    $output = ($run.Output | Out-String).Trim()
    return @{
        Ok          = (Test-Path -LiteralPath $ReportPath)
        Output      = $output
        # -350000: the CLI could not connect to LabVIEW (or the CLI is
        # missing). Every further comparison would wait for the same timeout.
        Unreachable = ($output -match '-350000') -or ($output -match 'LabVIEWCLI.*not recognized')
    }
}

function Invoke-Comparison([string]$Vi1, [string]$Vi2, [string]$ReportPath) {
    $result = Invoke-CliComparison $Vi1 $Vi2 $ReportPath
    if ($result.Unreachable -and -not $script:portRetried) {
        # Once per run: find the port this LabVIEW really uses (repairing
        # LabVIEW.ini inside GitHub Actions) and try again.
        $script:portRetried = $true
        $resolved = Resolve-ViServerPort -Path $LabVIEWPath -Requested $script:PortNumber -Fix:([bool]$env:GITHUB_ACTIONS)
        $resolved.Notes | ForEach-Object { Write-Warning $_ }
        Write-Host "LabVIEW not reachable on port $($script:PortNumber); trying again on port $($resolved.Port)."
        $script:PortNumber = $resolved.Port
        $result = Invoke-CliComparison $Vi1 $Vi2 $ReportPath
    }
    return $result
}

function Copy-ReportImage([string]$ReportPath, [string]$Source, [string]$Slug) {
    # $Source is the path as written in the HTML, relative to the report file.
    $from = Join-Path (Split-Path $ReportPath) $Source
    if (-not (Test-Path -LiteralPath $from)) { return $null }
    $targetDir = Join-Path (Join-Path $OutDir 'images') $Slug
    New-Item -ItemType Directory -Force $targetDir | Out-Null
    Copy-Item -LiteralPath $from -Destination (Join-Path $targetDir (Split-Path $from -Leaf)) -Force
    return "images/$Slug/$(Split-Path $from -Leaf)"
}

function Invoke-FramePrint([string]$ViPath, [string]$Slug) {
    # Print Diagram Frames.vi prints the VI with LabVIEW's documentation
    # printer (Print.VI To HTML), which writes one picture per case frame, and
    # lists every frame of every multi-frame structure in LabVIEW's print order.
    $dir = Join-Path (Join-Path $htmlDir 'frames') $Slug
    # Print.VI To HTML fails with Error 118 when the folder does not exist.
    New-Item -ItemType Directory -Force $dir | Out-Null
    $html = Join-Path $dir 'diagram.html'
    $list = Join-Path $dir 'frames.txt'
    # The VI's arguments come last; RunVI hands them to Command Line Arguments.
    $run = Invoke-NativeCommand 'LabVIEWCLI' @('-OperationName', 'RunVI', '-LabVIEWPath', $LabVIEWPath, '-PortNumber', $script:PortNumber,
        '-VIPath', $framePrinter, $ViPath, $html, $list)
    $output = $run.Output | Out-String
    $code = $run.ExitCode
    if ($code -ne 0 -or -not (Test-Path -LiteralPath $html) -or -not (Test-Path -LiteralPath $list)) {
        return @{ Ok = $false; Output = $output.Trim() }
    }
    # The pictures in the order of the HTML's block diagram section: the whole
    # diagram first, then one per hidden frame.
    $text = [System.IO.File]::ReadAllText($html)
    $section = [regex]::Match($text, '(?s)<H3>Block Diagram</H3>(.*?)(<HR>|$)').Groups[1].Value
    $images = @([regex]::Matches($section, '(?i)<IMG SRC="([^"]+)"') | ForEach-Object { Join-Path $dir $_.Groups[1].Value })
    # One line per frame: structure, class, label, frame index, visible, name.
    $frames = @([System.IO.File]::ReadAllLines($list) | Where-Object { $_ } | ForEach-Object {
        $f = $_ -split "`t"
        [pscustomobject]@{ Structure = [int]$f[0]; Class = $f[1]; Label = $f[2]; Index = [int]$f[3]; Visible = ($f[4] -eq '1'); Name = if ($f.Count -gt 5) { $f[5] } else { '' } }
    })
    return @{ Ok = $true; Images = $images; Frames = $frames }
}

function Format-FrameName($Frame) {
    $kind = switch ($Frame.Class) {
        'CaseStructure' { 'Case structure' }
        'EventStructure' { 'Event structure' }
        'StackedSequenceStructure' { 'Stacked sequence' }
        default { $Frame.Class -creplace '([a-z])([A-Z])', '$1 $2' }
    }
    # Name a structure's label only when someone gave it one.
    $label = if ($Frame.Label -and $Frame.Label -notmatch '^(Case|Event|Stacked Sequence|Diagram Disable|Conditional Disable) Structure$') { " ""$($Frame.Label)""" } else { '' }
    $value = if ($Frame.Name) { $Frame.Name } else { "frame $($Frame.Index)" }
    return "$kind $($Frame.Structure)${label}: $value"
}

function Add-FrameSection([string]$ViPath, [string]$Slug) {
    # A folded section with one row per case frame of the VI as it is now.
    # LabVIEW's comparison images show each structure on its visible frame only.
    if (-not $framePrinter) { return $true }
    if ([System.IO.Path]::GetExtension($ViPath) -ieq '.ctl') { return $true }
    $result = Invoke-FramePrint $ViPath $Slug
    if (-not $result.Ok) {
        Write-Warning "The case frames of $ViPath could not be printed."
        [void]$md.AppendLine("The case frames could not be printed:`n`n$(Format-MarkdownCodeBlock $result.Output)`n")
        return $false
    }
    $hidden = @($result.Frames | Where-Object { -not $_.Visible })
    if ($result.Images.Count -le 1) { return $true }
    # Captions only when the frame list and the pictures agree; otherwise the
    # pictures are numbered, so a wrong caption is never shown.
    $named = ($hidden.Count -eq $result.Images.Count - 1)
    if (-not $named) { Write-Warning "$ViPath`: $($result.Images.Count - 1) frame pictures, $($hidden.Count) hidden frames listed; frames are numbered, not named." }
    $targetDir = Join-Path (Join-Path (Join-Path $OutDir 'images') $Slug) 'frames'
    New-Item -ItemType Directory -Force $targetDir | Out-Null
    [void]$md.AppendLine("<details><summary>All case frames ($($result.Images.Count - 1) hidden frames)</summary>")
    [void]$md.AppendLine()
    [void]$md.AppendLine('| Frame | Picture |')
    [void]$md.AppendLine('|---|---|')
    for ($i = 0; $i -lt $result.Images.Count; $i++) {
        if (-not (Test-Path -LiteralPath $result.Images[$i])) { continue }
        $file = '{0:d2}.png' -f $i
        Copy-Item -LiteralPath $result.Images[$i] -Destination (Join-Path $targetDir $file) -Force
        if ($i -eq 0) {
            $visible = @($result.Frames | Where-Object { $_.Visible } | ForEach-Object { Format-FrameName $_ })
            $caption = if ($visible.Count -gt 0) { "Whole diagram, visible frames: $($visible -join '; ')" } else { 'Whole diagram' }
        } elseif ($named) {
            $caption = Format-FrameName $hidden[$i - 1]
        } else {
            $caption = "Frame picture $i"
        }
        # Frame names are selector values such as "<Default>" or "a|b".
        $caption = ConvertTo-MarkdownText $caption
        [void]$md.AppendLine("| $caption | ![$file](images/$Slug/frames/$file) |")
    }
    [void]$md.AppendLine()
    [void]$md.AppendLine('</details>')
    [void]$md.AppendLine()
    return $true
}

function Format-ImageRow([string]$Before, [string]$After) {
    $b = if ($Before) { "![before]($Before)" } else { '' }
    $a = if ($After) { "![after]($After)" } else { '' }
    return "| Before | After |`n|---|---|`n| $b | $a |`n"
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("vidiff_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$baseDir = Join-Path $workDir 'base'
$htmlDir = Join-Path $workDir 'html'
New-Item -ItemType Directory -Force $htmlDir | Out-Null

# A worktree of an earlier run that was killed before its clean-up would
# make "worktree add" below fail; forget those whose folder is gone.
Invoke-Git @('-C', $HeadDir, 'worktree', 'prune') | Out-Null

# -z and core.quotePath=false: NUL-separated and unquoted, so paths with
# spaces, quotes or non-ASCII characters arrive as they are.
$diffOutput = (Invoke-Git @('-C', $HeadDir, '-c', 'core.quotePath=false', 'diff', '-z', '--name-status', '--find-renames', "$BaseRef...HEAD")) -join "`n"
$changes = @(ConvertFrom-GitNameStatus $diffOutput |
    Where-Object { $extensions -contains [System.IO.Path]::GetExtension($_.NewPath).ToLower() })

$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine('## VI diff report')
[void]$md.AppendLine()

# One entry per compared VI, for the short summary (summary.md).
$summary = @()
# Set when LabVIEW could not be reached; the remaining VIs are not compared.
$unreachable = $false
# VIs whose case frames could not be printed.
$framesFailed = @()

if ($changes.Count -eq 0) {
    [void]$md.AppendLine('No VI, VIM or CTL files changed in this pull request.')
    [System.IO.File]::WriteAllText((Join-Path $OutDir 'report.md'), $md.ToString(), $utf8)
    [System.IO.File]::WriteAllText((Join-Path $OutDir 'summary.md'), "No VI, VIM or CTL files changed.`n", $utf8)
    Write-Host 'No LabVIEW files changed.'
    exit 0
}

$modified = @($changes | Where-Object { $_.Status -eq 'M' -or $_.Status -eq 'R' })
$added = @($changes | Where-Object { $_.Status -eq 'A' })
$deleted = @($changes | Where-Object { $_.Status -eq 'D' })
[void]$md.AppendLine("$($modified.Count) modified, $($added.Count) added, $($deleted.Count) deleted. Generated by LabVIEW's VI comparison; position and size changes are not shown.")
[void]$md.AppendLine()

$mergeBase = (@(Invoke-Git @('-C', $HeadDir, 'merge-base', $BaseRef, 'HEAD')) -join '').Trim()
Invoke-Git @('-C', $HeadDir, 'worktree', 'add', '--detach', $baseDir, $mergeBase) | Out-Null

try {
    $index = 0
    foreach ($change in ($modified + $added)) {
        $index++
        if ($unreachable) {
            $summary += [pscustomobject]@{ Path = $change.NewPath; Status = $change.Status; Count = -2; Image = $null }
            continue
        }
        $name = [System.IO.Path]::GetFileNameWithoutExtension($change.NewPath)
        $slug = ('{0:d2}-{1}' -f $index, ($name -replace '[^A-Za-z0-9]+', '-')).Trim('-')
        $report = Join-Path $htmlDir "$slug.html"
        $headFile = Join-Path $HeadDir $change.NewPath
        Write-Host "Comparing $($change.NewPath) ..."

        if ($change.Status -eq 'A') {
            # No old version: compare the VI with itself to get its overview images.
            [void]$md.AppendLine("### ``$($change.NewPath)`` (added)")
            [void]$md.AppendLine()
            $result = Invoke-Comparison $headFile $headFile $report
        } else {
            $label = if ($change.Status -eq 'R') { "renamed from ``$($change.OldPath)``" } else { 'modified' }
            [void]$md.AppendLine("### ``$($change.NewPath)`` ($label)")
            [void]$md.AppendLine()
            $result = Invoke-Comparison (Join-Path $baseDir $change.OldPath) $headFile $report
        }

        if (-not $result.Ok) {
            [void]$md.AppendLine('The comparison could not be created:')
            [void]$md.AppendLine()
            [void]$md.AppendLine((Format-MarkdownCodeBlock $result.Output))
            [void]$md.AppendLine()
            $summary += [pscustomobject]@{ Path = $change.NewPath; Status = $change.Status; Count = -1; Image = $null }
            if ($result.Unreachable) {
                $unreachable = $true
                Write-Warning "LabVIEW at port $PortNumber ($LabVIEWPath) is not reachable; the remaining VIs are not compared."
                [void]$md.AppendLine("**LabVIEW could not be reached on port $PortNumber, so the remaining VIs were not compared.** Check the VI Server port of ``$LabVIEWPath`` (repository variables ``LABVIEW_COMPARE_PATH`` / ``LABVIEW_COMPARE_PORT``).")
                [void]$md.AppendLine()
            }
            continue
        }

        $html = [System.IO.File]::ReadAllText($report)
        $filesDir = [regex]::Escape("${slug}_files/")
        $bd1 = Copy-ReportImage $report "${slug}_files/bd_1.png" $slug
        $bd2 = Copy-ReportImage $report "${slug}_files/bd_2.png" $slug
        $fp1 = Copy-ReportImage $report "${slug}_files/fp_1.png" $slug
        $fp2 = Copy-ReportImage $report "${slug}_files/fp_2.png" $slug

        if ($change.Status -eq 'A') {
            if ($bd1) { [void]$md.AppendLine("Block diagram (case structures show their visible frame only):`n`n![block diagram]($bd1)`n") }
            if ($fp1) { [void]$md.AppendLine("<details><summary>Front panel</summary>`n`n![front panel]($fp1)`n`n</details>`n") }
            if (-not (Add-FrameSection $headFile $slug)) { $framesFailed += $change.NewPath }
            $summary += [pscustomobject]@{ Path = $change.NewPath; Status = 'A'; Count = 0; Image = $bd1 }
            continue
        }
        $firstChange = $null

        # One <details open> block per reported difference.
        $sections = [regex]::Matches($html, '(?s)<details open>(.*?)</details>')
        if ($sections.Count -eq 0) {
            [void]$md.AppendLine('No functional differences found (cosmetic changes only).')
            [void]$md.AppendLine()
        }
        foreach ($section in $sections) {
            $body = $section.Groups[1].Value
            $heading = [regex]::Match($body, '(?s)<summary class="difference-heading">(.*?)</summary>').Groups[1].Value
            # LabVIEW's text, possibly with tags and entities: shown as plain
            # text, so a "<", "|" or "@" in a VI or control name stays as it is.
            $heading = [System.Net.WebUtility]::HtmlDecode(($heading -replace '<[^>]*>', '')).Trim()
            [void]$md.AppendLine("**$(ConvertTo-MarkdownText $heading)**")
            [void]$md.AppendLine()
            # LabVIEW marks each change in the images as <section number><letter>.
            $number = [regex]::Match($heading, '^\d+').Value
            $letter = 0
            foreach ($detail in [regex]::Matches($body, '(?s)<li class="diff-detail">(.*?)</li>')) {
                $mark = if ($letter -lt 26) { [string][char](65 + $letter) } else { [string]($letter + 1) }
                $text = [System.Net.WebUtility]::HtmlDecode(($detail.Groups[1].Value -replace '<[^>]*>', '')).Trim()
                [void]$md.AppendLine("- **$number$mark** " + (ConvertTo-MarkdownText $text))
                $letter++
            }
            [void]$md.AppendLine()
            $before = @([regex]::Matches($body, "src=`"($filesDir[^`"]*_1\.png)`"") | ForEach-Object { $_.Groups[1].Value })
            $after = @([regex]::Matches($body, "src=`"($filesDir[^`"]*_2\.png)`"") | ForEach-Object { $_.Groups[1].Value })
            for ($i = 0; $i -lt [Math]::Max($before.Count, $after.Count); $i++) {
                $b = if ($i -lt $before.Count) { Copy-ReportImage $report $before[$i] $slug } else { $null }
                $a = if ($i -lt $after.Count) { Copy-ReportImage $report $after[$i] $slug } else { $null }
                if (-not $firstChange -and $a) { $firstChange = $a }
                [void]$md.AppendLine((Format-ImageRow $b $a))
            }
        }
        # The summary shows the first changed spot as it is now, or the whole
        # diagram when LabVIEW reported no spot.
        $thumb = if ($firstChange) { $firstChange } else { $bd2 }
        $summary += [pscustomobject]@{ Path = $change.NewPath; Status = $change.Status; Count = $sections.Count; Image = $thumb }

        [void]$md.AppendLine('<details><summary>Whole block diagram and front panel</summary>')
        [void]$md.AppendLine()
        [void]$md.AppendLine((Format-ImageRow $bd1 $bd2))
        [void]$md.AppendLine((Format-ImageRow $fp1 $fp2))
        [void]$md.AppendLine('</details>')
        [void]$md.AppendLine()
        if (-not (Add-FrameSection $headFile $slug)) { $framesFailed += $change.NewPath }
    }

    if ($deleted.Count -gt 0) {
        [void]$md.AppendLine('### Deleted')
        [void]$md.AppendLine()
        foreach ($change in $deleted) { [void]$md.AppendLine("- ``$($change.OldPath)``") }
        [void]$md.AppendLine()
    }
}
finally {
    try { Invoke-Git @('-C', $HeadDir, 'worktree', 'remove', '--force', $baseDir) | Out-Null }
    catch { Write-Warning "Could not remove the worktree $baseDir ($($_.Exception.Message)); 'git worktree prune' cleans it up." }
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}

[System.IO.File]::WriteAllText((Join-Path $OutDir 'report.md'), $md.ToString(), $utf8)

# Short summary for the pull request comment: one row per modified VI with a
# small picture of its first changed spot, added VIs folded away. Image links
# are relative (images/...), like in report.md.
function Format-Thumb([string]$Image, [int]$Width) {
    if ($Image) { return "<img src=""$Image"" width=""$Width"">" }
    return ''
}
$sm = New-Object System.Text.StringBuilder
[void]$sm.AppendLine("**VIs:** $($modified.Count) modified, $($added.Count) added, $($deleted.Count) deleted")
[void]$sm.AppendLine()
if ($unreachable) {
    [void]$sm.AppendLine("**No VI comparison:** LabVIEW could not be reached on port $PortNumber. Check the repository variables ``LABVIEW_COMPARE_PATH`` and ``LABVIEW_COMPARE_PORT``.")
    [void]$sm.AppendLine()
}
$changedRows = @($summary | Where-Object { $_.Status -ne 'A' })
$visibleRows = 6   # more modified VIs than this are folded away
function Add-ChangedTable($Rows) {
    [void]$sm.AppendLine('| VI | Changes | Changed spot, now |')
    [void]$sm.AppendLine('|---|---|---|')
    foreach ($row in $Rows) {
        $name = [System.IO.Path]::GetFileName($row.Path)
        $folder = [System.IO.Path]::GetDirectoryName($row.Path) -replace '\\', '/'
        $count = if ($row.Count -eq -2) { 'not compared' } elseif ($row.Count -lt 0) { 'comparison failed' } elseif ($row.Count -eq 0) { 'cosmetic only' } else { "$($row.Count)" }
        [void]$sm.AppendLine("| ``$name``<br><sub>$(ConvertTo-MarkdownText $folder)</sub> | $count | $(Format-Thumb $row.Image 220) |")
    }
    [void]$sm.AppendLine()
}
if ($changedRows.Count -gt 0) {
    Add-ChangedTable @($changedRows | Select-Object -First $visibleRows)
    if ($changedRows.Count -gt $visibleRows) {
        [void]$sm.AppendLine("<details><summary>$($changedRows.Count - $visibleRows) more modified VIs</summary>")
        [void]$sm.AppendLine()
        Add-ChangedTable @($changedRows | Select-Object -Skip $visibleRows)
        [void]$sm.AppendLine('</details>')
        [void]$sm.AppendLine()
    }
}
$addedRows = @($summary | Where-Object { $_.Status -eq 'A' })
if ($addedRows.Count -gt 0) {
    [void]$sm.AppendLine("<details><summary>Added VIs ($($addedRows.Count))</summary>")
    [void]$sm.AppendLine()
    [void]$sm.AppendLine('| VI | Block diagram |')
    [void]$sm.AppendLine('|---|---|')
    foreach ($row in $addedRows) {
        $name = [System.IO.Path]::GetFileName($row.Path)
        $folder = [System.IO.Path]::GetDirectoryName($row.Path) -replace '\\', '/'
        [void]$sm.AppendLine("| ``$name``<br><sub>$(ConvertTo-MarkdownText $folder)</sub> | $(Format-Thumb $row.Image 200) |")
    }
    [void]$sm.AppendLine()
    [void]$sm.AppendLine('</details>')
    [void]$sm.AppendLine()
}
if ($deleted.Count -gt 0) {
    [void]$sm.AppendLine("Deleted: $(($deleted | ForEach-Object { '`' + $_.OldPath + '`' }) -join ', ')")
    [void]$sm.AppendLine()
}
[System.IO.File]::WriteAllText((Join-Path $OutDir 'summary.md'), $sm.ToString(), $utf8)
Write-Host "Report written to $(Join-Path $OutDir 'report.md') and summary.md"

$notCompared = @($summary | Where-Object { $_.Count -lt 0 })
if ($notCompared.Count -gt 0) {
    Write-Host "::error::$($notCompared.Count) of $($summary.Count) changed VIs could not be compared: $(($notCompared | ForEach-Object { $_.Path }) -join ', ')"
    exit 1
}
if ($framesFailed.Count -gt 0) {
    Write-Host "::error::The case frames of $($framesFailed.Count) changed VIs could not be printed: $($framesFailed -join ', ')"
    exit 1
}
exit 0
