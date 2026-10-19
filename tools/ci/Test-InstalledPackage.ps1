<#
.SYNOPSIS
Installs the built VI package, runs the installed Datalogger example against
the protocol tester, and uninstalls the package again.

.DESCRIPTION
Everything else in CI tests the repository: the Caraya suite and the protocol
tests load the toolkit from src\. This script tests what users install.

1. Contents. Lists the .vip (a zip file) and fails on every entry that has
   no place in a user's LabVIEW: anything below tools\, _ci\, tests\,
   .github\ or builds\ of the installed toolkit, any .git file or folder,
   any .ps1 script and the test library.
2. Install. `vipm install` into the test LabVIEW. The script refuses to run
   when the toolkit is already installed there, so it never replaces or
   removes a developer's own installation (-Force overrides that).
3. Example. Starts the installed Datalogger example, the copy under
   <LabVIEW>\examples\MCP Server\..., not the repository's, with Start VI.vi
   (next to this script) through LabVIEW CLI, waits until it answers on its port
   (36987), and runs tools\test\Test-McpServer.ps1 against it. The example
   links to the installed jg_mcp_MCP Server.lvlib in vi.lib, so this also
   shows that the installed toolkit loads and serves.
4. Cleanup. The example has a latched Stop button, which VI Server cannot
   press, so the test LabVIEW is closed (LabVIEWCLI CloseLabVIEW, then
   Stop-Process if it does not go) and the package is uninstalled with
   `vipm uninstall`. Cleanup runs also when an earlier step failed.

The exit code is 0 when the contents are clean, the install, the example
start and every required protocol check passed and the uninstall worked,
and 1 otherwise. A report is written to ReportFile.

Closing the test LabVIEW ends everything running in it. Do not run this
against a LabVIEW that someone is working in.

.EXAMPLE
.\tools\ci\Test-InstalledPackage.ps1
.\tools\ci\Test-InstalledPackage.ps1 -VipPath builds\jgoebel_lib_labview_mcp_server_sdk-2.2.6.40.vip `
    -LabVIEWPath "C:\Program Files\National Instruments\LabVIEW 2020\LabVIEW.exe" -PortNumber 3368
#>
param(
    # The package to test. Default: the newest .vip under builds\.
    [string]$VipPath,
    # The test LabVIEW. Defaults come from Resolve-CiEnvironment.ps1 in CI
    # (LABVIEW_PATH, LABVIEW_PORT), else the LabVIEW 2020 64-bit installation
    # and the port in its LabVIEW.ini.
    [string]$LabVIEWPath = $env:LABVIEW_PATH,
    [int]$PortNumber = $(if ($env:LABVIEW_PORT) { [int]$env:LABVIEW_PORT } else { 0 }),
    # Path of the example in the package, below <LabVIEW>\examples\MCP Server.
    [string]$Example = 'Datalogger MCP Server\Datalogger Main.vi',
    [string]$ServerUrl = 'http://127.0.0.1:36987/mcp/server',
    [int]$StartTimeoutSeconds = 300,
    [string]$RepoDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [string]$ReportFile = (Join-Path ([System.IO.Path]::GetTempPath()) 'installed-package-report.txt'),
    # Run even when the toolkit is already installed; it is uninstalled afterwards.
    [switch]$Force,
    # Leave the package installed at the end (for looking at it by hand).
    [switch]$KeepInstalled,
    # Only check the package contents; needs no LabVIEW and no vipm.
    [switch]$ContentsOnly
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabVIEWCi.psm1') -Force
Add-Type -AssemblyName System.IO.Compression.FileSystem
$utf8 = New-Object System.Text.UTF8Encoding $false
$script:report = New-Object System.Collections.Generic.List[string]
$script:failed = $false

function Write-Step([string]$Text) { Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan; $script:report.Add(''); $script:report.Add("== $Text") }
function Write-Line([string]$Text) { Write-Host $Text; $script:report.Add($Text) }
function Write-Failure([string]$Text) {
    $script:failed = $true
    Write-Host "::error::$Text"
    $script:report.Add("FAIL: $Text")
}

function Invoke-Native {
    # Runs a console tool, returns its exit code and prints and records its
    # output. Windows PowerShell turns stderr lines into errors; they must
    # not stop the script.
    param([string]$Exe, [string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & $Exe @Arguments 2>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
    }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    foreach ($line in $out) { Write-Line "    $line" }
    return $code
}

function Test-ServerAnswers {
    $body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"installed-package-test","version":"1.0"}}}'
    $file = Join-Path ([System.IO.Path]::GetTempPath()) 'installed-package-initialize.json'
    [System.IO.File]::WriteAllText($file, $body, $utf8)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $status = & curl.exe -s -m 5 -o NUL -w '%{http_code}' -X POST -H 'Content-Type: application/json' `
        -H 'Accept: application/json, text/event-stream' --data-binary "@$file" $ServerUrl 2>$null
    $ErrorActionPreference = $previous
    return "$status" -eq '200'
}

# ---------------------------------------------------------------- inputs
if (-not $VipPath) {
    $newest = Get-ChildItem (Join-Path $RepoDir 'builds') -Filter *.vip -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $newest) { Write-Host "::error::No -VipPath given and no .vip under $RepoDir\builds."; exit 1 }
    $VipPath = $newest.FullName
}
$VipPath = (Resolve-Path -LiteralPath $VipPath).Path

if (-not $LabVIEWPath) {
    $lv = Get-LabVIEWInstall | Where-Object { $_.Year -eq 2020 -and $_.Bitness -eq 64 } | Select-Object -First 1
    if (-not $lv) { Write-Host '::error::No -LabVIEWPath given and no LabVIEW 2020 64-bit found.'; exit 1 }
    $LabVIEWPath = $lv.Path
}
$lvInfo = Get-LabVIEWInstall | Where-Object { $_.Path -ieq (Resolve-Path -LiteralPath $LabVIEWPath).Path } | Select-Object -First 1
if (-not $lvInfo) { Write-Host "::error::$LabVIEWPath is not a LabVIEW installation."; exit 1 }
$lvDir = Split-Path $lvInfo.Path -Parent
if (-not $PortNumber) { $PortNumber = (Resolve-ViServerPort -Path $lvInfo.Path -Preferred (Get-VipmPort -Path $lvInfo.Path)).Port }

Write-Line "Package:  $VipPath"
if (-not $ContentsOnly) {
    $cli = Get-LabVIEWCliPath
    if (-not $cli) { Write-Host '::error::LabVIEW CLI (LabVIEWCLI.exe) is not installed.'; exit 1 }
    $vipm = Find-Tool 'vipm' @("$env:ProgramFiles\JKI\VI Package Manager\support\vipm.exe", "${env:ProgramFiles(x86)}\JKI\VI Package Manager\support\vipm.exe")
    if (-not $vipm) { Write-Host '::error::The vipm CLI is not installed.'; exit 1 }
    Write-Line "LabVIEW:  $($lvInfo.Path) ($($lvInfo.Year) $($lvInfo.Bitness)-bit), VI Server port $PortNumber"
}

# ---------------------------------------------------------------- 1. contents
Write-Step 'Package contents'
$zip = [System.IO.Compression.ZipFile]::OpenRead($VipPath)
try { $entries = @($zip.Entries | ForEach-Object { $_.FullName }) } finally { $zip.Dispose() }
$packageName = $null
try {
    $zip = [System.IO.Compression.ZipFile]::OpenRead($VipPath)
    $spec = $zip.GetEntry('spec')
    if ($spec) {
        $reader = New-Object System.IO.StreamReader($spec.Open())
        $specText = $reader.ReadToEnd(); $reader.Dispose()
        if ($specText -match '(?m)^Name="([^"]+)"') { $packageName = $Matches[1] }
        if ($specText -match '(?m)^Version="([^"]+)"') { Write-Line "Version:  $($Matches[1])" }
    }
} finally { $zip.Dispose() }
if (-not $packageName) { Write-Host "::error::$VipPath has no package name in its spec; is it a VI package?"; exit 1 }
Write-Line "Name:     $packageName, $($entries.Count) entries"

# "File Group 0" is the LabVIEW folder. The toolkit's own root in vi.lib is
# the folder that holds src\; tools\ and friends are only wrong there (the
# examples have a tools\ folder of their own).
$roots = @($entries | ForEach-Object { if ($_ -match '^(File Group \d+/vi\.lib/.+?/)src/') { $Matches[1] } } | Sort-Object -Unique)
if ($roots.Count -eq 0) { Write-Failure 'The package has no src\ folder in vi.lib; the toolkit is not in it.' }
$bad = New-Object System.Collections.Generic.List[string]
foreach ($e in $entries) {
    $why = $null
    foreach ($r in $roots) {
        if ($e.StartsWith($r) -and $e.Substring($r.Length) -match '^(tools|_ci|tests|\.github|builds)(/|$)') { $why = "$($Matches[1])\ folder" }
    }
    if (-not $why -and $e -match '(^|/)\.git(/|$)') { $why = '.git' }
    if (-not $why -and $e -match '\.ps1$') { $why = 'PowerShell script' }
    if (-not $why -and $e -match '(^|/)MCP Server tests\.lvlib$') { $why = 'test library' }
    if ($why) { $bad.Add("$e  ($why)") }
}
if ($bad.Count -gt 0) {
    Write-Failure "The package contains $($bad.Count) entries that do not belong in a user's LabVIEW:"
    foreach ($b in $bad) { Write-Line "    $b" }
} else {
    Write-Line 'PASS: no tools\, _ci\, tests\, .github\, builds\, .git, .ps1 or test library entries.'
}

$exampleEntry = $entries | Where-Object { $_ -match '^File Group 0/examples/' -and $_.Replace('/', '\').EndsWith('\' + $Example) } | Select-Object -First 1
if (-not $exampleEntry) { Write-Failure "The package has no example ending in $Example." }
if ($ContentsOnly) {
    [System.IO.File]::WriteAllLines($ReportFile, $script:report, $utf8)
    if ($script:failed) { exit 1 }
    exit 0
}

# ---------------------------------------------------------------- 2. install
$installedRoots = @($roots | ForEach-Object { Join-Path $lvDir ($_ -replace '^File Group 0/', '').TrimEnd('/') })
$already = @($installedRoots | Where-Object { Test-Path -LiteralPath $_ })
if ($already.Count -gt 0 -and -not $Force) {
    Write-Failure "The toolkit is already installed in this LabVIEW ($($already -join ', ')). Uninstall it first, or pass -Force to replace it; it is uninstalled at the end either way."
    [System.IO.File]::WriteAllLines($ReportFile, $script:report, $utf8)
    exit 1
}
$owner = Get-PortOwner ([int]([uri]$ServerUrl).Port)
if ($owner) {
    $name = (Get-Process -Id $owner -ErrorAction SilentlyContinue).Path
    Write-Failure "Port $(([uri]$ServerUrl).Port) is already in use by process $owner ($name); a server is running there. Stop it first."
    [System.IO.File]::WriteAllLines($ReportFile, $script:report, $utf8)
    exit 1
}

# vipm gives up after 60 s without progress from VIPM Desktop; an install
# into LabVIEW 2020 is silent for longer than that while LabVIEW loads.
if (-not $env:VIPM_DESKTOP_LIVELINESS_TIMEOUT) { $env:VIPM_DESKTOP_LIVELINESS_TIMEOUT = '900' }

$installed = $false
try {
    Write-Step 'Install'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $code = Invoke-Native $vipm @('install', $VipPath, '-y', '--labview-version', $lvInfo.Year, '--labview-bitness', $lvInfo.Bitness)
    $installed = $true   # also try to uninstall after a partial install
    if ($code -ne 0) { throw "vipm install failed with exit code $code." }
    Write-Line "Installed in $([int]$sw.Elapsed.TotalSeconds) s."
    foreach ($r in $installedRoots) {
        if (-not (Test-Path -LiteralPath $r)) { throw "vipm reported success, but $r does not exist." }
    }

    # ------------------------------------------------------------ 3. example
    if (-not $exampleEntry) { throw 'No example to start.' }
    $examplePath = Join-Path $lvDir (($exampleEntry -replace '^File Group 0/', '').Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $examplePath)) { throw "The installed example $examplePath does not exist." }
    if ($examplePath.StartsWith($RepoDir, [System.StringComparison]::OrdinalIgnoreCase)) { throw "$examplePath is inside the repository, not the LabVIEW tree." }

    Write-Step 'Installed example'
    # LabVIEW CLI's RunVI only runs VIs with its own connector pane (error
    # 1031 for any other VI), so Start VI.vi opens the example and starts it
    # without waiting; the CLI call returns while the example keeps running.
    $launcher = Join-Path $PSScriptRoot 'Start VI.vi'
    if (-not (Test-Path -LiteralPath $launcher)) { throw "$launcher does not exist." }
    Write-Line "Starting $examplePath"
    $code = Invoke-Native $cli @('-OperationName', 'RunVI', '-VIPath', $launcher, '-LabVIEWPath', $lvInfo.Path, '-PortNumber', $PortNumber, $examplePath)
    if ($code -ne 0) { throw "Start VI.vi could not start the example (LabVIEW CLI exit code $code)." }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $up = $false
    while ($sw.Elapsed.TotalSeconds -lt $StartTimeoutSeconds) {
        if (Test-ServerAnswers) { $up = $true; break }
        Start-Sleep -Seconds 2
    }
    if (-not $up) { throw "The example was started but did not answer at $ServerUrl within $StartTimeoutSeconds s." }
    Write-Line "The example answers at $ServerUrl after $([int]$sw.Elapsed.TotalSeconds) s."

    Write-Step 'Protocol tests against the installed example'
    $tester = Join-Path $RepoDir 'tools\test\Test-McpServer.ps1'
    $code = Invoke-Native 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tester, '-Url', $ServerUrl)
    if ($code -ne 0) { Write-Failure "Test-McpServer.ps1: $code required checks failed against the installed example." }
    else { Write-Line 'PASS: every required protocol check passed against the installed example.' }
}
catch {
    Write-Failure $_.Exception.Message
}
finally {
    # ------------------------------------------------------------ 4. cleanup
    Write-Step 'Cleanup'
    if (Get-LabVIEWProcess $lvInfo.Path) {
        Write-Line 'Closing the test LabVIEW (the example cannot be stopped from outside).'
        Invoke-Native $cli @('-OperationName', 'CloseLabVIEW', '-LabVIEWPath', $lvInfo.Path, '-PortNumber', $PortNumber) | Out-Null
        $deadline = (Get-Date).AddSeconds(60)
        while ((Get-LabVIEWProcess $lvInfo.Path) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
        $left = Get-LabVIEWProcess $lvInfo.Path
        if ($left) { Write-Line "LabVIEW did not close; stopping process $($left.Id)."; Stop-Process -Id $left.Id -Force }
    }

    if ($installed -and -not $KeepInstalled) {
        $code = Invoke-Native $vipm @('uninstall', $packageName, '--labview-version', $lvInfo.Year, '--labview-bitness', $lvInfo.Bitness)
        if ($code -ne 0) { Write-Failure "vipm uninstall failed with exit code $code." }
        $left = @($installedRoots | Where-Object { Test-Path -LiteralPath $_ })
        if ($left.Count -gt 0) { Write-Failure "After the uninstall, $($left -join ', ') still exists." }
        elseif ($code -eq 0) { Write-Line 'Uninstalled.' }
    } elseif ($KeepInstalled) {
        Write-Line 'The package stays installed (-KeepInstalled).'
    }

    Write-Step 'Result'
    if ($script:failed) { Write-Line 'FAILED: see the FAIL lines above.' } else { Write-Line 'PASSED: the installed package is clean and its Datalogger example serves MCP.' }
    [System.IO.File]::WriteAllLines($ReportFile, $script:report, $utf8)
    Write-Host "Report: $ReportFile"
}
if ($script:failed) { exit 1 }
exit 0
