<#
.SYNOPSIS
Installs every VIPM package the toolkit needs into one LabVIEW version.

.DESCRIPTION
Installs, through the VIPM command line:

  1. the runtime dependencies from src\LabVIEW MCP Server SDK.vipc
     (the same list the package build uses), and
  2. the development and test packages listed in test-packages.txt.

Run it once per LabVIEW version, on a developer machine or a CI runner.
VIPM must already list that LabVIEW version; start VIPM Desktop once after
installing a new LabVIEW so it is detected.

.EXAMPLE
.\tools\setup\Install-Dependencies.ps1 -LabVIEWVersion 2020
#>
param(
    [Parameter(Mandatory = $true)][string]$LabVIEWVersion,
    [ValidateSet('32', '64')][string]$Bitness = '64'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$vipc = Join-Path $repo 'src\LabVIEW MCP Server SDK.vipc'
$target = @('--labview-version', $LabVIEWVersion, '--labview-bitness', $Bitness)

# VIPM Desktop goes quiet for minutes while LabVIEW starts and compiles.
$env:VIPM_DESKTOP_LIVELINESS_TIMEOUT = '600'

Write-Host "Installing runtime dependencies from $vipc ..."
& vipm install $vipc @target --yes --timeout 1200
if ($LASTEXITCODE -ne 0) { throw 'Installing the runtime dependencies failed.' }

$packages = @(Get-Content (Join-Path $PSScriptRoot 'test-packages.txt') |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
if ($packages.Count -gt 0) {
    Write-Host "Installing development and test packages: $($packages -join ', ') ..."
    & vipm install @packages @target --yes --timeout 1200
    if ($LASTEXITCODE -ne 0) { throw 'Installing the development and test packages failed.' }
}

Write-Host 'Installed packages:'
& vipm list --installed @target
