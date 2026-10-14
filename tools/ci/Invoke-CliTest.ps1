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

# LabVIEW CLI writes its errors to stderr; Windows PowerShell turns redirected
# stderr lines into errors, so they must not stop the script.
$ErrorActionPreference = 'Continue'
$output = & LabVIEWCLI -OperationName RunVI -VIPath $VIPath -PortNumber $PortNumber `
    -LabVIEWPath $LabVIEWPath 2>&1 | ForEach-Object {
        # An empty stderr line arrives as an error record whose text is its type name.
        if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
    } | Out-String
$code = $LASTEXITCODE
Write-Host $output
Write-Log $output

if ($output -match '-350000') {
    Write-Host "::error::LabVIEW not reachable: LabVIEW CLI could not connect to $LabVIEWPath on port $PortNumber. The VI did not run. Check the repository variable LABVIEW_PORT against server.tcp.port in that LabVIEW's LabVIEW.ini."
    exit 2
}
if ($code -ne 0) {
    Write-Host "::error::$(Split-Path $VIPath -Leaf) reported failures (exit code $code)."
    exit 1
}
Write-Host "$(Split-Path $VIPath -Leaf) passed."
exit 0
