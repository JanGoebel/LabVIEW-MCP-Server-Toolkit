<#
.SYNOPSIS
Installs the built VI package, runs every installed example against the
protocol tester, and uninstalls the package again.

.DESCRIPTION
Everything else in CI tests the repository: the Caraya suite and the protocol
tests load the toolkit from src\. This script tests what users install.

1. Contents. Lists the .vip (a zip file) and fails on every entry that has
   no place in a user's LabVIEW: anything below tools\, _ci\, tests\,
   .github\ or builds\ of the installed toolkit, any .git file or folder,
   any .ps1 script and the test library.
   It also fails on every override the build renamed. The build puts the
   jg_mcp_ prefix in front of every VI name, and a class method only
   overrides its ancestor's method of the same name: a renamed Next
   Segment.vi no longer overrides IG's Streamable Response, its class is
   broken, and so is every VI that uses it. Such VIs need a Namespace
   override with an empty namespace in the .vipb. The ancestors are read
   from the test LabVIEW's vi.lib.
2. Install. `vipm install` into the test LabVIEW. The script refuses to run
   when the toolkit is already installed there, so it never replaces or
   removes a developer's own installation (-Force overrides that).
3. Examples. Starts each installed example, the copy under
   <LabVIEW>\examples\MCP Server\..., not the repository's, with Start VI.vi
   (next to this script) through LabVIEW CLI, waits until it answers on its port
   (36987), and runs tools\test\Test-McpServer.ps1 against it. The examples
   link to the installed jg_mcp_MCP Server.lvlib in vi.lib, so this also
   shows that the installed toolkit loads and serves. An example has a
   latched Stop button, which VI Server cannot press, so the test LabVIEW is
   closed after each one (LabVIEWCLI CloseLabVIEW, then Stop-Process if it
   does not go) and started again for the next.
4. Cleanup. The test LabVIEW is closed and the package is uninstalled with
   `vipm uninstall`. Cleanup runs also when an earlier step failed.

The exit code is 0 when the contents are clean, the install, every example
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
    # Paths of the examples in the package, below <LabVIEW>\examples\MCP Server.
    [string[]]$Example = @(
        'Datalogger MCP Server\Datalogger Main.vi',
        'Full Featured MCP Server\main.vi',
        'Simple MCP Server\main.vi'
    ),
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
    # Runs a console tool (Invoke-NativeCommand), prints and records its
    # output and returns its exit code.
    param([string]$Exe, [string[]]$Arguments)
    $run = Invoke-NativeCommand $Exe $Arguments
    foreach ($line in $run.Output) { Write-Line "    $line" }
    return $run.ExitCode
}

# The initialize request Test-ServerAnswers posts; a file of this run only,
# deleted at the end.
$script:initializeFile = Join-Path ([System.IO.Path]::GetTempPath()) ('installed-package-initialize_' + [guid]::NewGuid().ToString('N') + '.json')

function Close-TestLabVIEW {
    if (-not (Get-LabVIEWProcess $lvInfo.Path)) { return }
    Write-Line 'Closing the test LabVIEW (the example cannot be stopped from outside).'
    Invoke-Native $cli @('-OperationName', 'CloseLabVIEW', '-LabVIEWPath', $lvInfo.Path, '-PortNumber', $PortNumber) | Out-Null
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-LabVIEWProcess $lvInfo.Path) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
    $left = Get-LabVIEWProcess $lvInfo.Path
    if ($left) { Write-Line "LabVIEW did not close; stopping process $($left.Id)."; Stop-Process -Id $left.Id -Force }
    # The port is released with the process; wait for it so the next example
    # does not find it taken.
    $port = [int]([uri]$ServerUrl).Port
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-PortOwner $port) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 1 }
}

function Test-ServerAnswers {
    if (-not (Test-Path -LiteralPath $script:initializeFile)) {
        $body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"installed-package-test","version":"1.0"}}}'
        [System.IO.File]::WriteAllText($script:initializeFile, $body, $utf8)
    }
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $status = & curl.exe -s -m 5 -o NUL -w '%{http_code}' -X POST -H 'Content-Type: application/json' `
        -H 'Accept: application/json, text/event-stream' --data-binary "@$($script:initializeFile)" $ServerUrl 2>$null
    $ErrorActionPreference = $previous
    return "$status" -eq '200'
}

# ---------------------------------------------------------------- inputs
if (-not $VipPath) {
    $newest = Get-ChildItem -LiteralPath (Join-Path $RepoDir 'builds') -Filter *.vip -File -ErrorAction SilentlyContinue |
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
if (-not (Test-Path -LiteralPath $LabVIEWPath -PathType Leaf)) { Write-Host "::error::$LabVIEWPath does not exist."; exit 1 }
$lvInfo = Get-LabVIEWInstall | Where-Object { $_.Path -ieq (Resolve-Path -LiteralPath $LabVIEWPath).Path } | Select-Object -First 1
if (-not $lvInfo) { Write-Host "::error::$LabVIEWPath is not a LabVIEW installation."; exit 1 }
$lvDir = Split-Path $lvInfo.Path -Parent
if (-not $PortNumber) { $PortNumber = (Resolve-ViServerPort -Path $lvInfo.Path -Preferred (Get-VipmPort -Path $lvInfo.Path)).Port }

Write-Line "Package:  $VipPath"
if (-not $ContentsOnly) {
    $cli = Get-LabVIEWCliPath
    if (-not $cli) { Write-Host '::error::LabVIEW CLI (LabVIEWCLI.exe) is not installed.'; exit 1 }
    $vipm = Get-VipmPath
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

# Overrides. A class's parent is named in its Parent Libraries item by URL:
# /<vilib>/... for a class of another package (read from the test LabVIEW),
# or relative to the class file that names it, which is a zip entry for the
# classes of this package and a file in vi.lib for the others.
function Join-RelativePath([string]$Base, [string]$Url) {
    # LabVIEW counts a relative URL from the file itself: the first ..
    # leaves the file, the second its folder.
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($p in ($Base + '/' + $Url).Split('/')) {
        if ($p -eq '..') { if ($parts.Count) { $parts.RemoveAt($parts.Count - 1) } } elseif ($p -ne '.' -and $p) { $parts.Add($p) }
    }
    return $parts -join '/'
}
function Read-ClassXml([string]$Url, [string]$From) {
    # $From is the location of the file that names $Url: 'zip:<entry>' or
    # 'file:<path with />'. Returns the class and its own location, or $null.
    if ($Url -match '^/<vilib>/(.+)$') {
        $loc = 'file:' + (Join-Path $lvDir 'vi.lib').Replace('\', '/') + '/' + $Matches[1]
    } elseif ($From -match '^(zip|file):(.*)$') {
        $loc = $Matches[1] + ':' + (Join-RelativePath $Matches[2] $Url)
    } else { return $null }
    if ($loc -match '^file:(.*)$') {
        $file = $Matches[1].Replace('/', '\')
        if (-not (Test-Path -LiteralPath $file)) { return $null }
        return @{ Xml = [xml][System.IO.File]::ReadAllText($file); Location = $loc }
    }
    $zip = [System.IO.Compression.ZipFile]::OpenRead($VipPath)
    try {
        $entry = $zip.GetEntry($loc.Substring(4))
        if (-not $entry) { return $null }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { return @{ Xml = [xml]$reader.ReadToEnd(); Location = $loc } } finally { $reader.Dispose() }
    } finally { $zip.Dispose() }
}
function Get-DynamicMethods([xml]$Class) {
    @($Class.SelectNodes("//Item[@Type='VI']") | Where-Object {
        ($_.Property | Where-Object { $_.Name -eq 'NI.ClassItem.IsStaticMethod' }).'#text' -eq 'false'
    } | ForEach-Object { $_.Name })
}
function Get-ParentUrl([xml]$Class) {
    $p = $Class.SelectSingleNode("//Item[@Type='Parent Libraries']/Item[@Type='Parent']")
    if ($p) { return $p.URL }
    return $null
}

$renamed = New-Object System.Collections.Generic.List[string]
$checked = 0
foreach ($e in ($entries | Where-Object { $_ -match '\.lvclass$' })) {
    $class = Read-ClassXml $e 'zip:'
    $own = Get-DynamicMethods $class.Xml
    if (-not $own.Count) { continue }
    # Every dynamic method of every ancestor, up to LabVIEW Object.
    $inherited = New-Object System.Collections.Generic.List[string]
    $current = $class
    for ($depth = 0; $depth -lt 20; $depth++) {
        $url = Get-ParentUrl $current.Xml
        if (-not $url) { break }
        $parent = Read-ClassXml $url $current.Location
        if (-not $parent) { Write-Failure "Cannot read the parent $url of $e, so its overrides were not checked."; break }
        foreach ($m in (Get-DynamicMethods $parent.Xml)) { $inherited.Add($m) }
        $current = $parent
    }
    $checked++
    foreach ($m in $own) {
        foreach ($a in $inherited) {
            if ($m -ne $a -and $m.Length -gt $a.Length -and $m.EndsWith($a, [System.StringComparison]::OrdinalIgnoreCase)) {
                $renamed.Add("$(Split-Path ($e -replace '/', '\') -Leaf): $m should be $a")
            }
        }
    }
}
if ($renamed.Count -gt 0) {
    Write-Failure "The build renamed $($renamed.Count) override(s), which then no longer override their ancestor's method and break their class:"
    foreach ($r in $renamed) { Write-Line "    $r" }
    Write-Line '    Give each a Namespace override with an empty namespace in the .vipb.'
} else {
    Write-Line "PASS: the overrides of all $checked classes with dynamic methods keep their ancestors' names."
}

$exampleEntries = @()
foreach ($x in $Example) {
    $found = $entries | Where-Object { $_ -match '^File Group 0/examples/' -and $_.Replace('/', '\').EndsWith('\' + $x) } | Select-Object -First 1
    if ($found) { $exampleEntries += $found } else { Write-Failure "The package has no example ending in $x." }
}
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

    # ------------------------------------------------------------ 3. examples
    if (-not $exampleEntries.Count) { throw 'No example to start.' }
    # LabVIEW CLI's RunVI only runs VIs with its own connector pane (error
    # 1031 for any other VI), so Start VI.vi opens the example and starts it
    # without waiting; the CLI call returns while the example keeps running.
    $launcher = Join-Path $PSScriptRoot 'Start VI.vi'
    if (-not (Test-Path -LiteralPath $launcher)) { throw "$launcher does not exist." }
    $tester = Join-Path $RepoDir 'tools\test\Test-McpServer.ps1'

    foreach ($exampleEntry in $exampleEntries) {
        $examplePath = Join-Path $lvDir (($exampleEntry -replace '^File Group 0/', '').Replace('/', '\'))
        $exampleName = Split-Path (Split-Path $examplePath -Parent) -Leaf
        Write-Step "Installed example: $exampleName"
        try {
            if (-not (Test-Path -LiteralPath $examplePath)) { throw "The installed example $examplePath does not exist." }
            if ($examplePath.StartsWith($RepoDir, [System.StringComparison]::OrdinalIgnoreCase)) { throw "$examplePath is inside the repository, not the LabVIEW tree." }
            Write-Line "Starting $examplePath"
            $code = Invoke-Native $cli @('-OperationName', 'RunVI', '-VIPath', $launcher, '-LabVIEWPath', $lvInfo.Path, '-PortNumber', $PortNumber, $examplePath)
            if ($code -ne 0) { throw "Start VI.vi could not start $exampleName (LabVIEW CLI exit code $code); a broken example cannot run." }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $up = $false
            while ($sw.Elapsed.TotalSeconds -lt $StartTimeoutSeconds) {
                if (Test-ServerAnswers) { $up = $true; break }
                Start-Sleep -Seconds 2
            }
            if (-not $up) { throw "$exampleName was started but did not answer at $ServerUrl within $StartTimeoutSeconds s." }
            Write-Line "$exampleName answers at $ServerUrl after $([int]$sw.Elapsed.TotalSeconds) s."

            $code = Invoke-Native 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tester, '-Url', $ServerUrl)
            # Test-McpServer.ps1 exits with the number of failed required checks, or 99
            # when the server does not answer at all.
            if ($code -eq 99) { Write-Failure "Test-McpServer.ps1: $exampleName did not answer at $ServerUrl." }
            elseif ($code -ne 0) { Write-Failure "Test-McpServer.ps1: $code required checks failed against $exampleName." }
            else { Write-Line "PASS: every required protocol check passed against $exampleName." }
        }
        catch {
            Write-Failure $_.Exception.Message
        }
        finally {
            # The next example needs the port, and a running example can only
            # be ended with its LabVIEW.
            Close-TestLabVIEW
        }
    }
}
catch {
    Write-Failure $_.Exception.Message
}
finally {
    # ------------------------------------------------------------ 4. cleanup
    Write-Step 'Cleanup'
    Close-TestLabVIEW

    if ($installed -and -not $KeepInstalled) {
        $code = Invoke-Native $vipm @('uninstall', $packageName, '--labview-version', $lvInfo.Year, '--labview-bitness', $lvInfo.Bitness)
        if ($code -ne 0) { Write-Failure "vipm uninstall failed with exit code $code." }
        $left = @($installedRoots | Where-Object { Test-Path -LiteralPath $_ })
        if ($left.Count -gt 0) { Write-Failure "After the uninstall, $($left -join ', ') still exists." }
        elseif ($code -eq 0) { Write-Line 'Uninstalled.' }
    } elseif ($KeepInstalled) {
        Write-Line 'The package stays installed (-KeepInstalled).'
    }

    Remove-Item -LiteralPath $script:initializeFile -Force -ErrorAction SilentlyContinue

    Write-Step 'Result'
    if ($script:failed) { Write-Line 'FAILED: see the FAIL lines above.' } else { Write-Line 'PASSED: the installed package is clean and each of its examples serves MCP.' }
    [System.IO.File]::WriteAllLines($ReportFile, $script:report, $utf8)
    Write-Host "Report: $ReportFile"
}
if ($script:failed) { exit 1 }
exit 0
