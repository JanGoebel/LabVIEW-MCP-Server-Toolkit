<#
.SYNOPSIS
    Lets the OpenAI Codex CLI connect to a running MCP server, list its tools
    and call them.

.DESCRIPTION
    OpenAI rejects a whole tool list if a single tool schema breaks its rules
    (for example an array without "items"). This script checks that with the
    real client: Codex connects to the server, the model lists every tool it
    received and calls the tools named in -Calls.

    Needs the Codex CLI (npm install -g @openai/codex) and a signed-in
    `codex login`. The server is passed as a temporary configuration override;
    ~/.codex/config.toml is not changed.

    The exit code is 0 when Codex reports the server's tools, 1 otherwise.

.EXAMPLE
    .\tools\test\Test-WithCodex.ps1
    .\tools\test\Test-WithCodex.ps1 -Url http://127.0.0.1:36987/mcp/server -Calls 'fake_tool_array_shapes'
#>
param(
    [string]$Url = 'http://127.0.0.1:36987/mcp/server',
    [string[]]$Calls = @(),
    [string]$Codex = 'codex',
    [string]$OutFile = (Join-Path $env:TEMP 'codex-mcp-report.jsonl')
)

$server = 'labview_under_test'
$callText = if ($Calls.Count) {
    "Then call each of these tools once, choosing valid example values for every argument (use more than one element for arrays): $($Calls -join ', '). Report each call's result or error verbatim."
} else { '' }

$prompt = @"
You are testing an MCP server named '$server'. Do not run shell commands and do not touch files.
First list every tool you received from '$server', with the JSON schema of its input exactly as you received it.
$callText
End with one line: TOOLS_SEEN=<number of tools from $server>.
"@

$codexArgs = @(
    'exec', '--skip-git-repo-check', '--json',
    '--sandbox', 'read-only',
    '-c', 'approval_policy="never"',
    '-c', "mcp_servers.$server.url=`"$Url`"",
    '-c', "mcp_servers.$server.default_tools_approval_mode=`"approve`"",
    '-'
)

# The prompt goes through stdin: a multi-line argument does not survive the
# codex.cmd wrapper. stderr is kept, because Codex reports MCP errors there.
$ErrorActionPreference = 'Continue'
$prompt | & $Codex @codexArgs 2>&1 | ForEach-Object { "$_" } | Out-File -FilePath $OutFile -Encoding utf8

$lines = Get-Content $OutFile -Encoding utf8
$events = $lines | ForEach-Object { try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { } }
$stderr = $lines | Where-Object { $_ -notmatch '^\s*\{' -and $_ -match '\S' }
if ($stderr) {
    Write-Host '--- Codex log ---'
    $stderr | Write-Host
}
$errors = $events | Where-Object { $_.type -eq 'error' -or $_.item.type -eq 'error' }
$final = ($events | Where-Object { $_.item.type -eq 'agent_message' } | Select-Object -Last 1).item.text

if ($errors) {
    Write-Host '--- Codex errors ---'
    $errors | ForEach-Object { $_ | ConvertTo-Json -Depth 20 -Compress | Write-Host }
}
Write-Host '--- Codex answer ---'
Write-Host $final

if ($final -match 'TOOLS_SEEN=(\d+)' -and [int]$Matches[1] -gt 0) { exit 0 }
exit 1
