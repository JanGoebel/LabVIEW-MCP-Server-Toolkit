<#
.SYNOPSIS
Finds the LabVIEW installations, VI Server ports and command-line tools a CI
job needs on this runner, repairs what is easy to repair, and hands the result
to the following steps.

.DESCRIPTION
Runs as the first step of every job. It picks

  * the test LabVIEW (tests and package build): the repository variable
    LABVIEW_PATH if it exists, otherwise the OLDEST installed LabVIEW of at
    least MinVersion, 64-bit preferred. The package is built with it, so its
    version becomes the package's minimum LabVIEW version;
  * the comparison LabVIEW (VI diff): LABVIEW_COMPARE_PATH if it exists,
    otherwise the NEWEST installed LabVIEW; of two with the same version the
    32-bit one, which is the one nobody develops in on a developer machine.
    LabVIEW CLI's comparison only loads into a LabVIEW at least as new as
    the CLI, which is checked.

LabVIEW is searched in the default folders and in the registry. For each one
the VI Server port is taken from what actually works (see
Resolve-ViServerPort in LabVIEWCi.psm1); LABVIEW_PORT / LABVIEW_COMPARE_PORT
are only used when LabVIEW.ini has none. LabVIEWCLI, vipm and gh are found on
PATH or in their default folders.

With -Fix it also: enables VI Server in LabVIEW.ini, moves a port that another
program holds, gives the two LabVIEWs different ports, closes a LabVIEW that
runs without listening on its port, and ends LabVIEW CLI processes left over
from a cancelled run.

With -Fix -CleanStart (the first step of every job) it also ends a VIPM
Desktop left over from an earlier job, together with the running LabVIEWs it
may have been driving. A runner runs one job at a time, so a VIPM Desktop
that is running when a job starts belongs to an earlier one. When vipm gives
up on an operation, VIPM Desktop can carry on with it, or wait at a dialog,
long afterwards, and then never answers the next job ("wait for VIPM startup
timed out"). The vipm command line starts VIPM Desktop again when needed, and
LabVIEW CLI starts LabVIEW. The check after the package install does not pass
-CleanStart, so it keeps what the install just started.

The requested values come from the environment variables
REQUESTED_LABVIEW_PATH, REQUESTED_LABVIEW_PORT, REQUESTED_COMPARE_PATH and
REQUESTED_COMPARE_PORT (the workflows map the repository variables onto
them). The result is written as LABVIEW_PATH, LABVIEW_PORT, LABVIEW_VERSION,
LABVIEW_BITNESS and LABVIEW_COMPARE_PATH, _PORT, _VERSION, _BITNESS to
GITHUB_ENV, and as a table to the job summary.

Exit code 1 when a required LabVIEW or LabVIEW CLI is missing; 0 otherwise.

.EXAMPLE
.\tools\ci\Resolve-CiEnvironment.ps1 -For All
Shows what CI would use on this machine, without changing anything.
#>
param(
    [ValidateSet('Test', 'Compare', 'All')][string]$For = 'All',
    [int]$MinVersion = 2020,
    [switch]$Fix,
    [switch]$CleanStart
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabVIEWCi.psm1') -Force

$notes = New-Object System.Collections.Generic.List[string]
$problems = New-Object System.Collections.Generic.List[string]
$result = [ordered]@{}

function Get-RequestedPort([string]$Value) {
    $port = 0
    if ($Value -and -not [int]::TryParse($Value, [ref]$port)) { $notes.Add("Port '$Value' is not a number; ignored.") }
    return $port
}

function Select-Requested([string]$Path, [string]$Variable, $Installs) {
    if (-not $Path) { return $null }
    $match = $Installs | Where-Object { $_.Path -ieq $Path } | Select-Object -First 1
    if ($match) { return $match }
    if (Test-Path -LiteralPath $Path) {
        $notes.Add("$Variable ($Path) is not a LabVIEW of a known version; ignored.")
    } else {
        $notes.Add("$Variable ($Path) does not exist on this runner; choosing a LabVIEW automatically.")
    }
    return $null
}

# --- tools -----------------------------------------------------------------
$cli = Get-LabVIEWCliPath
if (-not $cli) { $problems.Add('LabVIEW CLI (LabVIEWCLI.exe) is not installed. Install it with NI Package Manager (LabVIEW Command Line Interface).') }
$cliYear = $null
if ($cli -and ((Get-Item -LiteralPath $cli).VersionInfo.FileVersion -match '^(\d+)\.')) {
    $m = [int]$Matches[1]; $cliYear = if ($m -ge 2000) { $m } elseif ($m -ge 17) { 2000 + $m } else { $null }
}
$vipm = Find-Tool 'vipm' @(
    "$env:ProgramW6432\JKI\VI Package Manager\support\vipm.exe",
    "$env:ProgramFiles\JKI\VI Package Manager\support\vipm.exe",
    "${env:ProgramFiles(x86)}\JKI\VI Package Manager\support\vipm.exe")
if (-not $vipm) { $notes.Add('vipm (VIPM command line) not found; installing packages and building will fail.') }
# Git must be on the PATH before the job starts: without it actions/checkout
# downloads a zip instead of cloning, and then the VI diff has no history and
# VIPM Community Edition refuses to install ("Not inside a Git repository").
$gitOnPath = [bool](Get-Command git -CommandType Application -ErrorAction SilentlyContinue)
$git = Find-Tool 'git' @(
    "$env:ProgramW6432\Git\cmd\git.exe",
    "$env:ProgramFiles\Git\cmd\git.exe",
    "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
    "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe")
if (-not $git) {
    $problems.Add('Git is not installed on this runner. Install Git for Windows (system PATH) and restart the runner: without it actions/checkout downloads a zip instead of a repository, so the VI diff cannot run and VIPM Community Edition refuses to install packages ("Not inside a Git repository").')
} elseif (-not $gitOnPath) {
    $problems.Add("Git is installed ($git) but not on the PATH the runner started with, so actions/checkout downloaded a zip instead of a repository. Add $(Split-Path $git) to the system PATH and restart the runner.")
}
if ($env:GITHUB_WORKSPACE -and -not (Test-Path (Join-Path $env:GITHUB_WORKSPACE '.git'))) {
    $problems.Add('The checkout is not a Git repository (actions/checkout fell back to downloading a zip). The VI diff and VIPM Community Edition need a real clone; see the Git message above.')
}

$gh = Find-Tool 'gh' @("$env:ProgramW6432\GitHub CLI\gh.exe", "$env:ProgramFiles\GitHub CLI\gh.exe")
if (-not $gh) { $notes.Add('gh (GitHub CLI) not found; the report is posted through the REST API instead.') }

if ($Fix) {
    $stale = @(Get-Process -Name LabVIEWCLI -ErrorAction SilentlyContinue)
    if ($stale.Count -gt 0) {
        $stale | Stop-Process -Force -ErrorAction SilentlyContinue
        $notes.Add("Ended $($stale.Count) LabVIEW CLI process(es) left over from an earlier run.")
    }
}

# --- LabVIEW installations ---------------------------------------------------
$installs = @(Get-LabVIEWInstall | Sort-Object Year, Bitness)
if ($installs.Count -eq 0) {
    $problems.Add('No LabVIEW installation found (default folders and registry).')
}
$usable = @($installs | Where-Object { $_.Year -ge $MinVersion })

if ($Fix -and $CleanStart) {
    Stop-LeftoverVipm -LabVIEWPath @($installs | ForEach-Object { $_.Path }) | ForEach-Object { $notes.Add($_) }
}

$test = $null
if ($For -in 'Test', 'All' -and $installs.Count -gt 0) {
    $test = Select-Requested $env:REQUESTED_LABVIEW_PATH 'LABVIEW_PATH' $installs
    if (-not $test) {
        # Oldest first; of the same version the 64-bit one.
        $test = $usable | Sort-Object Year, @{ Expression = { if ($_.Bitness -eq '64') { 0 } else { 1 } } } | Select-Object -First 1
    }
    if (-not $test) {
        $problems.Add("No LabVIEW $MinVersion or newer for the tests and the build.")
    } elseif ($test.Year -ne $MinVersion -or $test.Bitness -ne '64') {
        $notes.Add("Tests and the package build use LabVIEW $($test.Year) $($test.Bitness)-bit, not $MinVersion 64-bit: a package built with it requires LabVIEW $($test.Year) or newer.")
    }
}

$compare = $null
if ($For -in 'Compare', 'All' -and $installs.Count -gt 0) {
    $compare = Select-Requested $env:REQUESTED_COMPARE_PATH 'LABVIEW_COMPARE_PATH' $installs
    if (-not $compare) {
        # Newest first; of the same version the 32-bit one.
        $compare = $installs | Sort-Object @{ Expression = 'Year'; Descending = $true }, @{ Expression = { if ($_.Bitness -eq '32') { 0 } else { 1 } } } | Select-Object -First 1
    }
    if ($compare -and $cliYear -and $compare.Year -lt $cliYear) {
        $notes.Add("The comparison LabVIEW ($($compare.Year)) is older than LabVIEW CLI ($cliYear); its comparison operation will not load there.")
    }
}

# --- VI Server ports -----------------------------------------------------------
# The port each installed LabVIEW is meant to have: VIPM's record of it if
# VIPM knows it (VIPM puts a LabVIEW back on that port whenever it starts it,
# for example to install packages), otherwise its LabVIEW.ini port. A
# LabVIEW that needs a port gets one none of the others is meant to have, so
# a working configuration is never moved to make room, and the ports agree
# with VIPM, whose settings are only read.
$configuredPorts = @{}
$vipmPorts = @{}
foreach ($i in $installs) {
    $p = Get-VipmPort $i.Path
    if ($p) { $vipmPorts[$i.Path.ToLowerInvariant()] = $p }
    else { [void][int]::TryParse([string](Get-IniValue (Join-Path (Split-Path $i.Path) 'LabVIEW.ini') 'server.tcp.port'), [ref]$p) }
    if ($p) { $configuredPorts[$i.Path.ToLowerInvariant()] = $p }
}
function Get-VipmPortFor([string]$Path) {
    $key = $Path.ToLowerInvariant()
    if ($vipmPorts.ContainsKey($key)) { return $vipmPorts[$key] } else { return 0 }
}
function Get-OtherPort([string]$Path) {
    @($configuredPorts.GetEnumerator() | Where-Object { $_.Key -ne $Path.ToLowerInvariant() } | ForEach-Object { $_.Value })
}

$testPort = $null
if ($test) {
    $r = Resolve-ViServerPort -Path $test.Path -Requested (Get-RequestedPort $env:REQUESTED_LABVIEW_PORT) -Preferred (Get-VipmPortFor $test.Path) -Avoid (Get-OtherPort $test.Path) -Fix:$Fix
    $configuredPorts[$test.Path.ToLowerInvariant()] = $r.Port
    $testPort = $r.Port
    $r.Notes | ForEach-Object { $notes.Add("Test LabVIEW: $_") }
    $result['LABVIEW_PATH'] = $test.Path
    $result['LABVIEW_PORT'] = $testPort
    $result['LABVIEW_VERSION'] = $test.Year
    $result['LABVIEW_BITNESS'] = $test.Bitness
}
if ($compare) {
    if ($test -and $compare.Path -ieq $test.Path) {
        $comparePort = $testPort
    } else {
        $r = Resolve-ViServerPort -Path $compare.Path -Requested (Get-RequestedPort $env:REQUESTED_COMPARE_PORT) -Preferred (Get-VipmPortFor $compare.Path) -Avoid (Get-OtherPort $compare.Path) -Fix:$Fix
        $comparePort = $r.Port
        $r.Notes | ForEach-Object { $notes.Add("Comparison LabVIEW: $_") }
    }
    $result['LABVIEW_COMPARE_PATH'] = $compare.Path
    $result['LABVIEW_COMPARE_PORT'] = $comparePort
    $result['LABVIEW_COMPARE_VERSION'] = $compare.Year
    $result['LABVIEW_COMPARE_BITNESS'] = $compare.Bitness
}

# --- hand over -------------------------------------------------------------------
foreach ($entry in $result.GetEnumerator()) {
    Set-Item -Path "env:$($entry.Key)" -Value "$($entry.Value)"
    if ($env:GITHUB_ENV) { Add-Content -LiteralPath $env:GITHUB_ENV -Value "$($entry.Key)=$($entry.Value)" }
}

$summary = New-Object System.Text.StringBuilder
[void]$summary.AppendLine('### Runner')
[void]$summary.AppendLine()
[void]$summary.AppendLine('| | |')
[void]$summary.AppendLine('|---|---|')
foreach ($i in $installs) { [void]$summary.AppendLine("| LabVIEW $($i.Year) $($i.Bitness)-bit | ``$($i.Path)`` ($($i.Version)) |") }
if ($test) { [void]$summary.AppendLine("| **Tests / build** | LabVIEW $($test.Year) $($test.Bitness)-bit, port $testPort |") }
if ($compare) { [void]$summary.AppendLine("| **VI comparison** | LabVIEW $($compare.Year) $($compare.Bitness)-bit, port $comparePort |") }
function Format-Tool([string]$Path, [string]$Missing) {
    if ($Path) { return '`' + $Path + '`' } else { return $Missing }
}
[void]$summary.AppendLine('| git | ' + (Format-Tool $git 'missing') + ' |')
[void]$summary.AppendLine('| LabVIEW CLI | ' + (Format-Tool $cli 'missing') + ' |')
[void]$summary.AppendLine('| vipm | ' + (Format-Tool $vipm 'missing') + ' |')
[void]$summary.AppendLine('| gh | ' + (Format-Tool $gh 'missing (REST fallback)') + ' |')
if ($notes.Count -gt 0) {
    [void]$summary.AppendLine()
    $notes | ForEach-Object { [void]$summary.AppendLine("- $_") }
}
Write-Host $summary.ToString()
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $summary.ToString() }
if ($env:GITHUB_ACTIONS) { $notes | ForEach-Object { Write-Host "::warning::$_" } }

if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Host "::error::$_" }
    exit 1
}
exit 0
