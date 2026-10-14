<#
.SYNOPSIS
Turns the Caraya plain-text test report into a Markdown summary.

.DESCRIPTION
Reads the report that tests\Run_Tests_CLI.vi writes (one line per suite, test
and assert: "<time> - <RESULT> - <indented label> - <VI>") and writes a
Markdown table with one row per test and its asserts.

Exit code is always 0; whether the run passed is decided by the test step.
#>
param(
    [Parameter(Mandatory = $true)][string]$ReportPath,
    [Parameter(Mandatory = $true)][string]$OutFile
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$md = New-Object System.Text.StringBuilder
[void]$md.AppendLine('### Tests')
[void]$md.AppendLine()

if (-not (Test-Path $ReportPath)) {
    [void]$md.AppendLine('No per-test report was produced. `tests\Run_Tests_CLI.vi` on this branch does not write `tests\results\caraya-report.txt` yet (update the branch from main), or the run stopped before the suite finished.')
    [System.IO.File]::WriteAllText($OutFile, $md.ToString(), $utf8)
    return
}

function Format-Result([string]$Result) {
    if ($Result -eq 'PASS') { return ':white_check_mark: pass' }
    return ":x: $($Result.ToLower())"
}

# Caraya indents by call depth, and that depth depends on how the suite was
# started (LabVIEWCLI adds its own callers on top). The deepest lines are the
# asserts; the lines one step (two spaces) above them are the tests.
$entries = @()
foreach ($line in (Get-Content $ReportPath)) {
    $parts = $line -split ' - ', 3
    if ($parts.Count -lt 3) { continue }
    $rest = $parts[2]
    $label = $rest.Trim()
    $vi = ''
    $cut = $label.LastIndexOf(' - ')
    if ($cut -ge 0) { $vi = $label.Substring($cut + 3).Trim(); $label = $label.Substring(0, $cut).Trim() }
    $entries += [pscustomobject]@{
        Indent = $rest.Length - $rest.TrimStart().Length
        Label  = $label.TrimEnd(' ', '-')
        Vi     = ($vi -replace '^.*:', '')
        Result = $parts[1].Trim()
    }
}

$assertIndent = ($entries | Measure-Object -Property Indent -Maximum).Maximum
$tests = @()
$current = $null
foreach ($entry in $entries) {
    if ($entry.Indent -eq $assertIndent) {
        if ($current) { $current.Asserts += $entry }
    } elseif ($entry.Indent -eq $assertIndent - 2) {
        $current = [pscustomobject]@{ Label = $entry.Label; Vi = $entry.Vi; Result = $entry.Result; Asserts = @() }
        $tests += $current
    }
}

if ($tests.Count -eq 0) {
    [void]$md.AppendLine('The report file contains no test entries.')
    [System.IO.File]::WriteAllText($OutFile, $md.ToString(), $utf8)
    return
}

$failed = @($tests | Where-Object { $_.Result -ne 'PASS' })
if ($failed.Count -eq 0) {
    [void]$md.AppendLine(":white_check_mark: All $($tests.Count) tests passed.")
} else {
    [void]$md.AppendLine(":x: $($failed.Count) of $($tests.Count) tests did not pass. Tests run in a chain, so a failure can mark the tests after it as failed too.")
}
[void]$md.AppendLine()
# The per-test table is folded away; it opens by itself when a test failed.
$open = if ($failed.Count -gt 0) { ' open' } else { '' }
[void]$md.AppendLine("<details$open><summary>Per-test results</summary>")
[void]$md.AppendLine()
[void]$md.AppendLine('| Test | VI | Result | Checks |')
[void]$md.AppendLine('|---|---|---|---|')
foreach ($test in $tests) {
    $checks = ($test.Asserts | ForEach-Object { "$($_.Label): $($_.Result.ToLower())" }) -join '<br>'
    [void]$md.AppendLine("| $($test.Label) | ``$($test.Vi)`` | $(Format-Result $test.Result) | $checks |")
}
[void]$md.AppendLine()
[void]$md.AppendLine('</details>')
[void]$md.AppendLine()

[System.IO.File]::WriteAllText($OutFile, $md.ToString(), $utf8)
