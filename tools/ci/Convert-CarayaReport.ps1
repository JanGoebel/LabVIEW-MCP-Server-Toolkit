<#
.SYNOPSIS
Turns the Caraya plain-text test report into a Markdown summary.

.DESCRIPTION
Reads the report that tests\Run_Tests_CLI.vi writes (one line per suite, test
and assert: "<time> - <RESULT> - <indented label> - <VI>") and writes a
Markdown table with one row per test and its asserts.

TestStatus is the exit code of tools\ci\Invoke-CliTest.ps1 for the suite;
with 2 (LabVIEW not reachable) the report says that the tests did not run
instead of showing a failure, and with "not-run" (the workflow skipped the
step because finding LabVIEW or installing the packages failed) it says
that. ProtocolReportPath and ProtocolStatus (the same values) add a section
for tests\Run_Protocol_Tests_CLI.vi (tools\test\Test-McpServer.ps1 against a
running server).

Labels and VI names are escaped for the Markdown table, and the protocol
tester's output is put in a code fence that no line of it can close.

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
Import-Module (Join-Path $PSScriptRoot 'LabVIEWCi.psm1') -Force
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
        'not-run' { [void]$md.AppendLine(':warning: Not run: an earlier step (finding LabVIEW, installing the packages) failed, or LabVIEW was not reachable; see the job log.') }
        default { [void]$md.AppendLine(':x: `Test-McpServer.ps1` reported failed required checks against the test server.') }
    }
    [void]$md.AppendLine()
    if ($ProtocolStatus -ne 'not-run' -and $ProtocolReportPath -and (Test-Path -LiteralPath $ProtocolReportPath)) {
        $lines = @(Get-Content -LiteralPath $ProtocolReportPath -Encoding UTF8)
        $fails = @($lines | Where-Object { $_ -match '^\[FAIL\] \(required\)' })
        $open = if ($ProtocolStatus -ne '0') { ' open' } else { '' }
        [void]$md.AppendLine("<details$open><summary>Protocol tester output ($($fails.Count) failed required checks)</summary>")
        [void]$md.AppendLine()
        [void]$md.AppendLine((Format-MarkdownCodeBlock ($lines -join "`n")))
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

if ($TestStatus -eq 'not-run') {
    [void]$md.AppendLine(':warning: The tests did not run: finding LabVIEW or installing the packages failed before them. See the job log.')
    [void]$md.AppendLine()
    Save-Report
    return
}

if (-not (Test-Path -LiteralPath $ReportPath)) {
    [void]$md.AppendLine('No per-test report was produced. `tests\Run_Tests_CLI.vi` on this branch does not write `tests\results\caraya-report.txt` yet (update the branch from main), or the run stopped before the suite finished.')
    Save-Report
    return
}

function Format-Result([string]$Result) {
    if ($Result -eq 'PASS') { return ':white_check_mark: pass' }
    return ":x: $($Result.ToLower())"
}

# The report, one line per entry: "<time> - <RESULT> - <indent><text>",
# indented by call depth, two spaces per level. Its structure:
#   * first the callers (LabVIEW CLI's call chain, then Run_Tests_CLI and
#     the suite VI), each line "<name> - <calling VI>", each at its own depth;
#   * then one line per test, "<test label> - <library>:<test VI>.vi", all at
#     the same depth;
#   * after each test its asserts, one level (two spaces) deeper, with no VI
#     part; an assert's label may itself contain " - ".
# How deep the tree starts depends on how the suite was started. The assert
# level is the depth most lines share (each test has at least one assert,
# each caller line has a depth of its own; on a tie the deeper one), and the
# tests are one level above it. A line deeper than that belongs to the
# current test as well, so one deeper line cannot shift the levels.
$entries = @()
foreach ($line in (Get-Content -LiteralPath $ReportPath -Encoding UTF8)) {
    $parts = $line -split ' - ', 3
    if ($parts.Count -lt 3) { continue }
    $rest = $parts[2]
    $entries += [pscustomobject]@{
        Indent = $rest.Length - $rest.TrimStart().Length
        Text   = $rest.Trim()
        Result = $parts[1].Trim()
    }
}

$tests = @()
if ($entries.Count -gt 0) {
    $assertIndent = [int]($entries | Group-Object Indent |
        Sort-Object @{ Expression = 'Count'; Descending = $true }, @{ Expression = { [int]$_.Name }; Descending = $true } |
        Select-Object -First 1).Name
    $testIndent = $assertIndent - 2
    $current = $null
    foreach ($entry in $entries) {
        if ($entry.Indent -eq $testIndent) {
            # "<label> - <library>:<VI>": the VI is after the last " - ".
            $label = $entry.Text
            $vi = ''
            $cut = $label.LastIndexOf(' - ')
            if ($cut -ge 0) { $vi = $label.Substring($cut + 3).Trim(); $label = $label.Substring(0, $cut).Trim() }
            $current = [pscustomobject]@{ Label = $label.TrimEnd(' ', '-'); Vi = ($vi -replace '^.*:', ''); Result = $entry.Result; Asserts = @() }
            $tests += $current
        } elseif ($entry.Indent -gt $testIndent) {
            if ($current) { $current.Asserts += [pscustomobject]@{ Label = $entry.Text.TrimEnd(' ', '-'); Result = $entry.Result } }
        } else {
            # Back above the tests (a caller or suite line): no current test.
            $current = $null
        }
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
    $checks = ($test.Asserts | ForEach-Object { "$(ConvertTo-MarkdownText $_.Label): $($_.Result.ToLower())" }) -join '<br>'
    # In a code span only | needs escaping in a table; a backtick would end it.
    $vi = $test.Vi.Replace('`', "'").Replace('|', '\|')
    [void]$md.AppendLine("| $(ConvertTo-MarkdownText $test.Label) | ``$vi`` | $(Format-Result $test.Result) | $checks |")
}
[void]$md.AppendLine()
[void]$md.AppendLine('</details>')
[void]$md.AppendLine()

Save-Report
