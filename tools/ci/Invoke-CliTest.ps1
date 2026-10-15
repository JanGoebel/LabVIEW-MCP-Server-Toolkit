<#
.SYNOPSIS
Runs a test entry VI through LabVIEW CLI and tells a failed test apart from an
unreachable LabVIEW.

.DESCRIPTION
Calls `LabVIEWCLI -OperationName RunVI` for VIPath (tests\Run_Tests_CLI.vi or
tests\Run_Protocol_Tests_CLI.vi), prints the CLI output and writes it to
LogFile. The exit code is

    0  the VI ran and returned Exit Code 0
    1  the VI ran and returned a non-zero Exit Code (tests failed)
    2  LabVIEW could not be reached (LabVIEW CLI error -350000), nothing ran
    3  VIPath does not exist on this branch

so a workflow can report "LabVIEW not reachable" instead of "tests failed".
#>
param(
    [Parameter(Mandatory = $true)][string]$VIPath,
    [Parameter(Mandatory = $true)][string]$LabVIEWPath,
    [Parameter(Mandatory = $true)][int]$PortNumber,
    [string]$LogFile
)

$utf8 = New-Object System.Text.UTF8Encoding $false
function Write-Log([string]$Text) {
    if ($LogFile) { [System.IO.File]::WriteAllText($LogFile, $Text, $utf8) }
}

if (-not (Test-Path $VIPath)) {
    $message = "$VIPath does not exist on this branch."
    Write-Host $message
    Write-Log $message
    exit 3
}

Import-Module (Join-Path $PSScriptRoot 'LabVIEWCi.psm1') -Force
if (-not (Get-LabVIEWCliPath)) {
    Write-Host '::error::LabVIEW CLI (LabVIEWCLI.exe) is not installed; the VI did not run.'
    exit 2
}

function Invoke-RunVI([int]$Port) {
    # LabVIEW CLI writes its errors to stderr; Windows PowerShell turns
    # redirected stderr lines into errors, so they must not stop the script.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & LabVIEWCLI -OperationName RunVI -VIPath $VIPath -PortNumber $Port `
        -LabVIEWPath $LabVIEWPath 2>&1 | ForEach-Object {
            # An empty stderr line arrives as an error record whose text is its type name.
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
        } | Out-String
    $script:code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    return $out
}

$output = Invoke-RunVI $PortNumber
if ($output -match '-350000') {
    # Not reachable on that port: find the port this LabVIEW really uses
    # (repairing LabVIEW.ini inside GitHub Actions) and try once more. A second
    # try also covers a LabVIEW that was still starting.
    Write-Host $output
    $resolved = Resolve-ViServerPort -Path $LabVIEWPath -Requested $PortNumber -Fix:([bool]$env:GITHUB_ACTIONS)
    $resolved.Notes | ForEach-Object { Write-Host "::warning::$_" }
    Write-Host "LabVIEW not reachable on port $PortNumber; trying again on port $($resolved.Port)."
    $PortNumber = $resolved.Port
    $output = Invoke-RunVI $PortNumber
}
Write-Host $output
Write-Log $output

if ($output -match '-350000') {
    Write-Host "::error::LabVIEW not reachable: LabVIEW CLI could not connect to $LabVIEWPath on port $PortNumber, also after a second try. The VI did not run. Check VI Server (server.tcp.enabled and server.tcp.port) in that LabVIEW's LabVIEW.ini, and whether a dialog is open in LabVIEW."
    exit 2
}
if ($code -ne 0) {
    Write-Host "::error::$(Split-Path $VIPath -Leaf) reported failures (exit code $code)."
    exit 1
}
Write-Host "$(Split-Path $VIPath -Leaf) passed."
exit 0
