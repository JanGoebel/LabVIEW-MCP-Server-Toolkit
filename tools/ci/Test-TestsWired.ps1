<#
.SYNOPSIS
Checks that every test VI of the Caraya suite is called by the suite.

.DESCRIPTION
The Caraya suite runs only the tests that tests\Test_MCP_Server.vi calls. A
"test *.vi" that was added to tests\MCP Server tests.lvlib but never wired
into Test_MCP_Server.vi is skipped without any message, and the suite still
passes.

This script reads the members of the test library whose name starts with
"test " (any case) and looks each one up in the link table of
Test_MCP_Server.vi. LabVIEW stores the name of every subVI a VI calls there as
a length-prefixed string, so the check needs no LabVIEW and takes well under
a second. A name that only appears in a comment or a string constant does
not count: those are stored compressed with the block diagram.

The exit code is the number of test VIs that are not called.

.EXAMPLE
.\tools\ci\Test-TestsWired.ps1
.\tools\ci\Test-TestsWired.ps1 -RepoDir C:\work\LabVIEW-MCP-Server-Toolkit
#>
param(
    [string]$RepoDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$Library = 'tests\MCP Server tests.lvlib',
    [string]$SuiteVI = 'tests\Test_MCP_Server.vi'
)

$ErrorActionPreference = 'Stop'
$libraryPath = Join-Path $RepoDir $Library
$suitePath = Join-Path $RepoDir $SuiteVI
foreach ($p in $libraryPath, $suitePath) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Host "::error::$p does not exist."; exit 1 }
}

[xml]$lib = Get-Content -LiteralPath $libraryPath -Raw -Encoding UTF8
$suiteName = Split-Path $suitePath -Leaf
$tests = @($lib.SelectNodes('//Item[@Type="VI"]') | ForEach-Object { $_.Name } |
    Where-Object { $_ -match '^test ' -and $_ -ne $suiteName } | Sort-Object -Unique)
if ($tests.Count -eq 0) { Write-Host "::error::$Library has no ""test *.vi"" members."; exit 1 }

# VI names in the link table are Latin-1, preceded by one length byte.
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$suite = $latin1.GetString([System.IO.File]::ReadAllBytes($suitePath))
$missing = @($tests | Where-Object { $_.Length -gt 255 -or -not $suite.Contains([string][char]$_.Length + $_) })

Write-Host "$($tests.Count - $missing.Count) of $($tests.Count) test VIs in $Library are called by $suiteName."
foreach ($name in $missing) {
    Write-Host "::error::$name is a member of $Library but is not called by $suiteName, so the suite never runs it."
}
exit $missing.Count
