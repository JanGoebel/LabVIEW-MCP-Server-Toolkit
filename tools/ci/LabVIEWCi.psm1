<#
Shared helpers for the CI scripts: finding the LabVIEW installations on a
runner, the VI Server port each of them listens on, and the command-line tools
the workflows call. Used by Resolve-CiEnvironment.ps1, Invoke-CliTest.ps1 and
New-ViDiffReport.ps1.
#>

$script:IniSection = 'LabVIEW'

function Get-ExeBitness([string]$Path) {
    # Machine type in the PE header: 0x8664 is x64, 0x14C is x86.
    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $reader = New-Object System.IO.BinaryReader $stream
        [void]$stream.Seek(0x3C, 'Begin')
        $peOffset = $reader.ReadInt32()
        [void]$stream.Seek($peOffset + 4, 'Begin')
        $machine = $reader.ReadUInt16()
    }
    finally { $stream.Dispose() }
    switch ($machine) { 0x8664 { return '64' } 0x14C { return '32' } default { return $null } }
}

function Get-LabVIEWInstall {
    <# Every LabVIEW.exe in the default folders and in the registry, with its
       year (from the file version: 20.x is 2020) and bitness. #>
    $dirs = New-Object System.Collections.Generic.List[string]
    $roots = @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ } | Select-Object -Unique
    foreach ($root in $roots) {
        Get-ChildItem (Join-Path $root 'National Instruments') -Directory -Filter 'LabVIEW *' -ErrorAction SilentlyContinue |
            ForEach-Object { $dirs.Add($_.FullName) }
    }
    foreach ($key in 'HKLM:\SOFTWARE\National Instruments\LabVIEW', 'HKLM:\SOFTWARE\WOW6432Node\National Instruments\LabVIEW') {
        Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
            $p = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).PATH
            if ($p) { $dirs.Add($p.TrimEnd('\')) }
        }
    }
    $seen = @{}
    foreach ($dir in $dirs) {
        $exe = Join-Path $dir 'LabVIEW.exe'
        if (-not (Test-Path -LiteralPath $exe)) { continue }
        $full = (Resolve-Path -LiteralPath $exe).Path
        if ($seen.ContainsKey($full.ToLowerInvariant())) { continue }
        $seen[$full.ToLowerInvariant()] = $true
        $fileVersion = (Get-Item -LiteralPath $full).VersionInfo.FileVersion
        if ($fileVersion -notmatch '^(\d+)\.') { continue }
        $major = [int]$Matches[1]
        # From LabVIEW 2017 on, the major version is the year minus 2000.
        $year = if ($major -ge 2000) { $major } elseif ($major -ge 17) { 2000 + $major } else { $null }
        if (-not $year) { continue }
        [pscustomobject]@{
            Path    = $full
            Year    = $year
            Bitness = Get-ExeBitness $full
            Version = $fileVersion
        }
    }
}

function Get-IniValue([string]$Ini, [string]$Key) {
    if (-not (Test-Path -LiteralPath $Ini)) { return $null }
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*=(.*)$'
    foreach ($line in [System.IO.File]::ReadAllLines($Ini)) {
        if ($line -match $pattern) { return $Matches[1].Trim().Trim('"') }
    }
    return $null
}

function Set-IniValue([string]$Ini, [string]$Key, [string]$Value) {
    <# Sets key=value in the [LabVIEW] section of a LabVIEW.ini. Only call it
       while that LabVIEW is not running: LabVIEW rewrites the file on exit. #>
    $encoding = [System.Text.Encoding]::Default
    # Not "$lines = if (...) { list }": PowerShell would unroll the list into a
    # fixed-size array, and Insert would fail.
    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Ini) { $lines.AddRange([string[]][System.IO.File]::ReadAllLines($Ini, $encoding)) }
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    $index = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match $pattern) { $index = $i; break } }
    if ($index -ge 0) {
        $lines[$index] = "$Key=$Value"
    } else {
        $section = -1
        for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i].Trim() -eq "[$script:IniSection]") { $section = $i; break } }
        if ($section -lt 0) { $lines.Insert(0, "[$script:IniSection]"); $section = 0 }
        $lines.Insert($section + 1, "$Key=$Value")
    }
    [System.IO.File]::WriteAllLines($Ini, $lines, $encoding)
}

function Get-ListeningPort([int]$ProcessId) {
    @(Get-NetTCPConnection -State Listen -OwningProcess $ProcessId -ErrorAction SilentlyContinue |
        ForEach-Object { [int]$_.LocalPort } | Sort-Object -Unique)
}

function Get-PortOwner([int]$Port) {
    Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty OwningProcess
}

function Get-FreePort([int]$Start, [int[]]$Avoid) {
    for ($p = $Start; $p -lt $Start + 200; $p++) {
        if ($Avoid -contains $p) { continue }
        if (-not (Get-PortOwner $p)) { return $p }
    }
    throw "No free TCP port between $Start and $($Start + 199)."
}

function Get-LabVIEWProcess([string]$Path) {
    Get-Process -Name LabVIEW -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and ($_.Path -ieq $Path) } | Select-Object -First 1
}

function Test-CiDedicatedMachine {
    <# True when the environment variable CI_DEDICATED_MACHINE is 1: nobody
       works on this machine, so a LabVIEW with unsaved changes may be closed
       as well (see Select-LabVIEWToStop). #>
    return ("$env:CI_DEDICATED_MACHINE" -eq '1')
}

function Get-ProcessWindowTitle {
    <# Titles of the visible top-level windows of a process: every front
       panel, block diagram and project window of a LabVIEW, not only the one
       Process.MainWindowTitle reports. Falls back to MainWindowTitle when the
       window list cannot be read. Read-only. #>
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    try {
        if (-not ('LabVIEWCi.Windows' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
namespace LabVIEWCi {
    public static class Windows {
        delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextLength(IntPtr hWnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
        public static string[] Titles(int processId) {
            List<string> titles = new List<string>();
            EnumWindows(delegate (IntPtr hWnd, IntPtr lParam) {
                uint owner;
                GetWindowThreadProcessId(hWnd, out owner);
                if (owner == (uint)processId && IsWindowVisible(hWnd)) {
                    int length = GetWindowTextLength(hWnd);
                    if (length > 0) {
                        StringBuilder text = new StringBuilder(length + 1);
                        GetWindowText(hWnd, text, text.Capacity);
                        titles.Add(text.ToString());
                    }
                }
                return true;
            }, IntPtr.Zero);
            return titles.ToArray();
        }
    }
}
'@
        }
        return @([LabVIEWCi.Windows]::Titles($ProcessId))
    } catch {
        $title = (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue).MainWindowTitle
        if ($title) { return @($title) } else { return @() }
    }
}

function Select-LabVIEWToStop {
    <# Decides which running LabVIEWs a CI step may end. Changes nothing.
       Process: objects with Id, Path and WindowTitles (Get-RunningLabVIEW).
       LabVIEWPath: the LabVIEWs this job uses (tests/build and comparison).
       Returns one object per process with Id, Path, Stop and Reason:
         * a LabVIEW at any other path is never stopped: on a developer
           machine that is where someone works;
         * a LabVIEW one of whose windows has a title with "*", which LabVIEW
           shows for unsaved changes, is not stopped either, unless Dedicated
           is set (CI_DEDICATED_MACHINE=1, nobody works on this machine);
         * every other LabVIEW at one of the LabVIEWPath paths is stopped. #>
    param([object[]]$Process = @(), [string[]]$LabVIEWPath = @(), [switch]$Dedicated)
    $wanted = @($LabVIEWPath | Where-Object { $_ })
    foreach ($p in @($Process | Where-Object { $_ })) {
        $path = "$($p.Path)"
        $used = [bool](@($wanted | Where-Object { $_ -ieq $path }).Count)
        $unsaved = @($p.WindowTitles | Where-Object { "$_" -match '\*' })
        if (-not $used) {
            $stop = $false; $reason = 'not a LabVIEW this job uses'
        } elseif ($unsaved.Count -gt 0 -and -not $Dedicated) {
            $stop = $false
            $reason = "it has unsaved changes (window ""$($unsaved[0])""); save or close them, or set CI_DEDICATED_MACHINE=1 on a machine nobody works on"
        } else {
            $stop = $true; $reason = if ($unsaved.Count -gt 0) { 'CI_DEDICATED_MACHINE=1, unsaved changes are discarded' } else { 'used by this job' }
        }
        [pscustomobject]@{ Id = $p.Id; Path = $path; Stop = $stop; Reason = $reason }
    }
}

function Get-RunningLabVIEW {
    <# The running LabVIEW processes at the given paths, with the titles of
       their windows, as Select-LabVIEWToStop takes them. Read-only. #>
    param([string[]]$LabVIEWPath = @())
    foreach ($path in @($LabVIEWPath | Where-Object { $_ } | Select-Object -Unique)) {
        $process = Get-LabVIEWProcess $path
        if (-not $process) { continue }
        [pscustomobject]@{ Id = $process.Id; Path = $process.Path; WindowTitles = @(Get-ProcessWindowTitle $process.Id) }
    }
}

function Stop-CiLabVIEW {
    <# Ends the running LabVIEWs at LabVIEWPath that Select-LabVIEWToStop
       allows to end, and waits up to 60 s for each. Returns the decisions
       (Id, Path, Stop, Reason), so the caller can say what it ended and what
       it left running. #>
    param([string[]]$LabVIEWPath = @())
    $decisions = @(Select-LabVIEWToStop -Process @(Get-RunningLabVIEW $LabVIEWPath) -LabVIEWPath $LabVIEWPath -Dedicated:(Test-CiDedicatedMachine))
    foreach ($d in $decisions | Where-Object { $_.Stop }) {
        Stop-Process -Id $d.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $d.Id -Timeout 60 -ErrorAction SilentlyContinue
    }
    return $decisions
}

function Get-VipmPort {
    <# The VI Server port VIPM has recorded for the LabVIEW at Path, or 0.
       Read-only. VIPM keeps its LabVIEW list in the [Targets] section of its
       Settings.ini (Locations i, and a Ports array in the same order) and puts
       a LabVIEW back on that port whenever it starts it, for example to
       install packages. #>
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Settings = (Join-Path $env:ProgramData 'JKI\VIPM\Settings.ini'))
    if (-not (Test-Path -LiteralPath $Settings)) { return 0 }
    $inTargets = $false
    $locations = @{}
    $ports = @()
    foreach ($line in [System.IO.File]::ReadAllLines($Settings, [System.Text.Encoding]::Default)) {
        if ($line -match '^\s*\[(.+)\]\s*$') { $inTargets = ($Matches[1] -eq 'Targets'); continue }
        if (-not $inTargets) { continue }
        if ($line -match '^Locations (\d+)="(.*)"$') { $locations[[int]$Matches[1]] = $Matches[2] }
        elseif ($line -match '^Ports="<size\(s\)=\d+>\s*(.*)"$') { $ports = @($Matches[1].Trim() -split '\s+' | Where-Object { $_ }) }
    }
    $location = '/' + ($Path -replace ':', '' -replace '\\', '/')
    foreach ($index in $locations.Keys) {
        if ($locations[$index] -ieq $location -and $index -lt $ports.Count) {
            $port = 0
            if ([int]::TryParse($ports[$index], [ref]$port)) { return $port }
        }
    }
    return 0
}

function Resolve-ViServerPort {
    <#
    Returns the VI Server port LabVIEW CLI must use for the LabVIEW at Path,
    plus notes on what was found or changed.
    The port this LabVIEW should have is, in this order: Preferred (VIPM's
    port for it, because VIPM moves it back there whenever it starts it),
    its LabVIEW.ini port, the requested port, 3363. A running instance that
    listens on it is used as it is.
    With -Fix it repairs what is easy to repair: VI Server disabled or on a
    different port in LabVIEW.ini, a port taken by another program or
    configured for another LabVIEW (Avoid), and an instance that runs on a
    different port or none: that LabVIEW is force-closed (Stop-Process,
    unsaved changes are lost) so that LabVIEW CLI starts it again with the
    settings written here. A running instance with unsaved changes (a window
    title with "*") is not closed unless CI_DEDICATED_MACHINE=1; it is then
    handled as without -Fix, and LabVIEW.ini is not written while it runs.
    Without -Fix it only reports, and uses a running instance's port as it
    is when that is its LabVIEW.ini port or the requested port.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$Requested,
        [int]$Preferred,
        [int[]]$Avoid = @(),
        [switch]$Fix
    )
    $notes = New-Object System.Collections.Generic.List[string]
    $ini = Join-Path (Split-Path $Path) 'LabVIEW.ini'
    $enabled = Get-IniValue $ini 'server.tcp.enabled'
    $iniPort = 0
    [void][int]::TryParse([string](Get-IniValue $ini 'server.tcp.port'), [ref]$iniPort)

    $want = if ($Preferred -and -not ($Avoid -contains $Preferred)) { $Preferred } elseif ($iniPort) { $iniPort } elseif ($Requested) { $Requested } else { 3363 }
    if ($Preferred -and ($Avoid -contains $Preferred)) {
        $notes.Add("VIPM's port $Preferred for this LabVIEW is also used by another LabVIEW; set different ports in VIPM (Tools > Options > LabVIEW).")
    }

    # LabVIEW.ini is only written when -Fix is given and this LabVIEW is not
    # running: LabVIEW rewrites the file when it exits.
    $write = [bool]$Fix
    $process = Get-LabVIEWProcess $Path
    if ($process) {
        $listening = Get-ListeningPort $process.Id
        if ($listening -contains $want) {
            if ($Requested -and $Requested -ne $want) { $notes.Add("Requested port $Requested ignored: the running LabVIEW listens on $want.") }
            return [pscustomobject]@{ Port = $want; Notes = $notes; Changed = $false }
        }
        $actual = @($iniPort, $Requested) | Where-Object { $_ -and ($listening -contains $_) } | Select-Object -First 1
        $was = if ($actual) { "on port $actual" } else { 'without listening on its VI Server port' }
        $stop = $null
        if ($Fix) {
            $titles = @(Get-ProcessWindowTitle $process.Id)
            $stop = Select-LabVIEWToStop -Process @([pscustomobject]@{ Id = $process.Id; Path = $Path; WindowTitles = $titles }) -LabVIEWPath @($Path) -Dedicated:(Test-CiDedicatedMachine)
            if (-not $stop.Stop) {
                $notes.Add("LabVIEW (process $($process.Id)) runs $was instead of on $want, but was not closed: $($stop.Reason).")
                $write = $false
            }
        }
        if ($stop -and $stop.Stop) {
            $notes.Add("LabVIEW (process $($process.Id)) was running $was instead of on $want; force-closed it so LabVIEW CLI starts it with the settings below.")
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            Wait-Process -Id $process.Id -Timeout 60 -ErrorAction SilentlyContinue
        } elseif ($actual) {
            $hint = if ($Fix) { 'It is repaired once it can be closed.' } else { 'Run with -Fix to repair it.' }
            $notes.Add("LabVIEW (process $($process.Id)) runs on port $actual, not on $want (VIPM may move it back); using $actual. $hint")
            return [pscustomobject]@{ Port = $actual; Notes = $notes; Changed = $false }
        } else {
            $hint = if ($Fix) { 'Close it.' } else { 'Close it, or run with -Fix.' }
            $notes.Add("LabVIEW (process $($process.Id)) is running but not listening on its VI Server port ($iniPort); LabVIEW CLI will probably not reach it. $hint")
        }
    }

    $port = $want
    $changes = @{}
    if ("$enabled" -ine 'TRUE') { $changes['server.tcp.enabled'] = 'True' }
    $owner = Get-PortOwner $port
    if (($Avoid -contains $port) -or $owner) {
        $why = if ($owner) { "is taken by process $owner" } else { 'is configured for another LabVIEW on this machine' }
        $newPort = Get-FreePort ([Math]::Max($port + 1, 3363)) $Avoid
        $notes.Add("Port $port $why; using $newPort.")
        $port = $newPort
    }
    if ($port -ne $iniPort) { $changes['server.tcp.port'] = "$port" }
    $access = Get-IniValue $ini 'server.tcp.access'
    if ($access -and ($access -notmatch '\+(127\.0\.0\.1|localhost|\*)')) {
        $changes['server.tcp.access'] = '"+127.0.0.1;+localhost;' + $access + '"'
    }

    $changed = $false
    if ($changes.Count -gt 0) {
        $list = ($changes.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
        if ($write) {
            try {
                foreach ($entry in $changes.GetEnumerator()) { Set-IniValue $ini $entry.Key $entry.Value }
                $notes.Add("Set $list in $ini.")
                $changed = $true
            } catch {
                $notes.Add("Could not write $ini ($($_.Exception.Message)); it needs $list.")
            }
        } elseif ($Fix) {
            $notes.Add("$ini needs $list; not written while this LabVIEW runs.")
        } else {
            $notes.Add("$ini needs $list (run with -Fix to write it).")
        }
    }
    if ($Requested -and $Requested -ne $port) { $notes.Add("Requested port $Requested ignored: this LabVIEW uses $port.") }
    return [pscustomobject]@{ Port = $port; Notes = $notes; Changed = $changed }
}

function Stop-LeftoverVipm {
    <# Ends a running VIPM Desktop and, only if one was running, the LabVIEWs
       at LabVIEWPath it may have been driving. For the start of a CI job,
       where a running VIPM Desktop belongs to an earlier job (see
       Resolve-CiEnvironment.ps1, -CleanStart). LabVIEWPath must be the
       LabVIEWs the job uses, not every installed one: LabVIEWs at other
       paths are never touched, and of these only those without unsaved
       changes are ended (see Select-LabVIEWToStop, CI_DEDICATED_MACHINE).
       Both are force-closed (Stop-Process). Returns notes, or nothing when
       VIPM Desktop was not running. #>
    param([string[]]$LabVIEWPath = @(), [string]$ProcessName = 'VI Package Manager')
    $desktop = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    if ($desktop.Count -eq 0) { return }
    $desktop | Stop-Process -Force -ErrorAction SilentlyContinue
    $desktop | ForEach-Object { Wait-Process -Id $_.Id -Timeout 60 -ErrorAction SilentlyContinue }
    $decisions = @(Stop-CiLabVIEW -LabVIEWPath $LabVIEWPath)
    $ended = @($decisions | Where-Object { $_.Stop })
    $what = 'VIPM Desktop'
    if ($ended.Count -gt 0) { $what += " and $($ended.Count) LabVIEW(s) ($(($ended | ForEach-Object { $_.Path }) -join ', '))" }
    "Ended $what left over from an earlier job, so this job starts with a VIPM that answers."
    foreach ($kept in $decisions | Where-Object { -not $_.Stop }) {
        "Left LabVIEW $($kept.Path) (process $($kept.Id)) running: $($kept.Reason). VIPM may not answer if it was driving it."
    }
}

function Find-Tool {
    <# Path of a command-line tool: from PATH, else from its default install
       folders, in which case its folder is added to PATH for this process and,
       inside GitHub Actions, for the following steps. #>
    param([Parameter(Mandatory = $true)][string]$Name, [string[]]$Candidates = @())
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    foreach ($candidate in $Candidates) {
        $hit = Resolve-Path $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $hit) { continue }
        $dir = Split-Path $hit.Path
        $env:PATH = "$dir;$env:PATH"
        if ($env:GITHUB_PATH) { Add-Content -LiteralPath $env:GITHUB_PATH -Value $dir }
        return $hit.Path
    }
    return $null
}

function Get-LabVIEWCliPath {
    Find-Tool 'LabVIEWCLI' @(
        "${env:ProgramFiles(x86)}\National Instruments\Shared\LabVIEW CLI\LabVIEWCLI.exe",
        "$env:ProgramW6432\National Instruments\Shared\LabVIEW CLI\LabVIEWCLI.exe",
        "$env:ProgramFiles\National Instruments\Shared\LabVIEW CLI\LabVIEWCLI.exe")
}

function Get-VipmPath {
    <# Path of the VIPM command line (vipm.exe), or $null. #>
    Find-Tool 'vipm' @(
        "$env:ProgramW6432\JKI\VI Package Manager\support\vipm.exe",
        "$env:ProgramFiles\JKI\VI Package Manager\support\vipm.exe",
        "${env:ProgramFiles(x86)}\JKI\VI Package Manager\support\vipm.exe")
}

function Get-GhPath {
    <# Path of the GitHub CLI (gh.exe), or $null. #>
    Find-Tool 'gh' @("$env:ProgramW6432\GitHub CLI\gh.exe", "$env:ProgramFiles\GitHub CLI\gh.exe")
}

function Invoke-NativeCommand {
    <# Runs a console program with its standard error merged into its output
       and returns ExitCode and Output (one string per line). Windows
       PowerShell turns redirected stderr lines into error records; here they
       become plain text and never stop the caller, and an empty stderr line
       arrives as its message, not as the record's type name. A program that
       does not exist gives exit code -1 and a "not recognized" line. #>
    param([Parameter(Mandatory = $true)][string]$FilePath, [string[]]$ArgumentList = @())
    $ErrorActionPreference = 'Continue'
    if (-not (Get-Command $FilePath -CommandType Application -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ ExitCode = -1; Output = @("$FilePath is not recognized as the name of a program (not installed or not on PATH).") }
    }
    $output = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
        })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

Export-ModuleMember -Function Get-LabVIEWInstall, Get-IniValue, Set-IniValue, Get-ListeningPort,
    Get-PortOwner, Get-FreePort, Get-LabVIEWProcess, Resolve-ViServerPort, Find-Tool, Get-LabVIEWCliPath, Get-ExeBitness,
    Get-VipmPort, Stop-LeftoverVipm, Test-CiDedicatedMachine, Get-ProcessWindowTitle, Select-LabVIEWToStop,
    Get-RunningLabVIEW, Stop-CiLabVIEW, Get-VipmPath, Get-GhPath, Invoke-NativeCommand
