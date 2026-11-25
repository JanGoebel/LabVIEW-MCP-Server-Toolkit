<#
.SYNOPSIS
Runs the official MCP conformance suite against a running MCP server.

.DESCRIPTION
Calls the server scenarios of @modelcontextprotocol/conformance (the suite the
Model Context Protocol project publishes) through npx, for exactly what one
specification revision requires (--requirements, default 2026-07-28).

Many scenarios call fixture tools, prompts and resources with fixed names
(test_simple_text, test://static-text, ...). The example
examples\Conformance MCP Server provides those the toolkit can express; run the
suite against it. Against another server those scenarios fail with "Unknown
tool" and say nothing about the toolkit.

conformance-baseline.yml next to this script lists the scenarios and checks
that need features the toolkit deliberately does not have, each with the
reason. With it the exit code means:

    0  every failure is in the baseline and every baselined entry still fails
    1  an unexpected failure (a regression), or a baselined entry now passes
       (remove it from the baseline)

Needs Node.js (npx). The suite version is pinned, so a new release of the
suite does not change the result unnoticed.

.EXAMPLE
.\tools\test\Invoke-Conformance.ps1
.\tools\test\Invoke-Conformance.ps1 -Url http://127.0.0.1:36987/mcp/server -OutDir "$env:TEMP\conformance"
.\tools\test\Invoke-Conformance.ps1 -Scenario server-stateless -NoBaseline
#>
param(
    [string]$Url = 'http://127.0.0.1:36987/mcp/server',
    [string]$Requirements = '2026-07-28',
    [string]$SuiteVersion = '0.2.0-alpha.12',
    # Run one scenario only (then --spec-version is used instead of --requirements).
    [string]$Scenario,
    [string]$Baseline = (Join-Path $PSScriptRoot 'conformance-baseline.yml'),
    # Report every failure as a failure, without the baseline.
    [switch]$NoBaseline,
    [string]$OutDir = (Join-Path ([System.IO.Path]::GetTempPath()) 'mcp-conformance'),
    [int]$TimeoutMs = 20000
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
    Write-Host '::error::npx (Node.js) is not installed; the conformance suite cannot run.'
    exit 2
}
if (Test-Path $OutDir) { Remove-Item -Recurse -Force $OutDir }
New-Item -ItemType Directory -Force $OutDir | Out-Null

$arguments = @('--yes', "@modelcontextprotocol/conformance@$SuiteVersion", 'server', '--url', $Url,
               '--timeout', $TimeoutMs, '-o', $OutDir)
if ($Scenario) {
    $arguments += @('--scenario', $Scenario, '--spec-version', $Requirements)
} else {
    $arguments += @('--requirements', $Requirements)
}
if (-not $NoBaseline -and (Test-Path $Baseline)) { $arguments += @('--expected-failures', $Baseline) }

Write-Host "MCP conformance suite $SuiteVersion, requirements $Requirements, against $Url" -ForegroundColor Cyan
& npx @arguments
$code = $LASTEXITCODE
Write-Host ''
Write-Host "Results (checks.json per scenario): $OutDir"
exit $code
