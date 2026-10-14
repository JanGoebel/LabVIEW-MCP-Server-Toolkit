<#
.SYNOPSIS
Turns the Caraya plain-text test report into a Markdown summary.

.DESCRIPTION
Reads the report that tests\Run_Tests_CLI.vi writes (one line per suite, test
and assert: "<time> - <RESULT> - <indented label> - <VI>") and writes a
Markdown table with one row per test and its asserts.

TestStatus is the exit code of tools\ci\Invoke-CliTest.ps1 for the suite;
with 2 (LabVIEW not reachable) the report says that the tests did not run
instead of showing a failure. ProtocolReportPath and ProtocolStatus add a
section for tests\Run_Protocol_Tests_CLI.vi (tools\test\Test-McpServer.ps1
against a running server).

Exit code is always 0; whether the run passed is decided by the test step.
#>
param(
    [Parameter(Mandatory = $true)][string]$ReportPath,
    [Parameter(Mandatory = $true)][string]$OutFile,
    [string]$TestStatus = '',
    [string]$ProtocolReportPath = '',
    [string]$ProtocolStatus = ''
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$md = New-Object System.Text.StringBuilder

# Section for the protocol tester, appended to every variant of the report.
function Add-ProtocolSection {
    if (-not $ProtocolStatus) { return }
    [void]$md.AppendLine('### Protocol tests')
    [void]$md.AppendLine()
    switch ($ProtocolStatus) {
        '0' { [void]$md.AppendLine(':white_check_mark: `Test-McpServer.ps1` passed against the test server.') }
        '2' { [void]$md.AppendLine(':warning: Not run: LabVIEW could not be reached (LabVIEW CLI error -350000).') }
        '3' { [void]$md.AppendLine('Not run: `tests\Run_Protocol_Tests_CLI.vi` does not exist on this branch.') }
        default { [void]$md.AppendLine(':x: `Test-McpServer.ps1` reported failed required checks against the test server.') }
    }
    [void]$md.AppendLine()
    if ($ProtocolReportPath -and (Test-Path $ProtocolReportPath)) {
        $lines = @(Get-Content $ProtocolReportPath)
        $fails = @($lines | Where-Object { $_ -match '^\[FAIL\] \(required\)' })
        $open = if ($ProtocolStatus -ne '0') { ' open' } else { '' }
        [void]$md.AppendLine("<details$open><summary>Protocol tester output ($($fails.Count) failed required checks)</summary>")
        [void]$md.AppendLine()
        [void]$md.AppendLine('```')
        foreach ($line in $lines) { [void]$md.AppendLine($line) }
        [void]$md.AppendLine('```')
        [void]$md.AppendLine()
        [void]$md.AppendLine('</details>')
        [void]$md.AppendLine()
    }
}

function Save-Report {
    Add-ProtocolSection
    [System.IO.File]::WriteAllText($OutFile, $md.ToString(), $utf8)
}

[void]$md.AppendLine('### Tests')
[void]$md.AppendLine()

if ($TestStatus -eq '2') {
    [void]$md.AppendLine(':warning: The tests did not run: LabVIEW could not be reached (LabVIEW CLI error -350000). Check the repository variable `LABVIEW_PORT` against `server.tcp.port` in the LabVIEW.ini of the test LabVIEW.')
    [void]$md.AppendLine()
    Save-Report
    return
}

if (-not (Test-Path $ReportPath)) {
    [void]$md.AppendLine('No per-test report was produced. `tests\Run_Tests_CLI.vi` on this branch does not write `tests\results\caraya-report.txt` yet (update the branch from main), or the run stopped before the suite finished.')
    Save-Report
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
    Save-Report
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

Save-Report
