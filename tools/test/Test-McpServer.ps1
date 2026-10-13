<#
.SYNOPSIS
Checks a running MCP server against the protocol rules it has to follow.

.DESCRIPTION
Sends requests with curl to an MCP server reachable over HTTP and checks the
answers against the Model Context Protocol specification (Streamable HTTP
transport, JSON-RPC rules, lifecycle, and the list methods of tools, prompts
and resources). It works against any server: nothing depends on which tools,
prompts or resources are registered, and no tool is called.

Every check is printed as PASS or FAIL. "required" checks are things the
specification demands; "advisory" checks are recommendations or behaviour
that is useful to know. The exit code is the number of failed required
checks, so 0 means the server passed.

.EXAMPLE
.\tools\test\Test-McpServer.ps1
.\tools\test\Test-McpServer.ps1 -Url http://127.0.0.1:36999/mcp/server
#>
param(
    [string]$Url = 'http://127.0.0.1:36987/mcp/server',
    [string]$ProtocolVersion = '2025-06-18',
    [int]$TimeoutSeconds = 10
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("mcptest_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force $tmp | Out-Null
$script:results = @()

function Send-Request {
    # Returns status code, headers, raw body and the parsed JSON (or $null).
    param([string]$Method = 'POST', [string]$Body, [string[]]$Headers = @(), [switch]$NoContentType)
    $bodyFile = Join-Path $tmp 'request.json'
    $outFile = Join-Path $tmp 'response.txt'
    $headerFile = Join-Path $tmp 'headers.txt'
    foreach ($f in @($outFile, $headerFile)) { if (Test-Path $f) { Remove-Item $f } }

    $curlArgs = @('-s', '-m', $TimeoutSeconds, '-X', $Method, '-o', $outFile, '-D', $headerFile, '-w', '%{http_code}')
    if (-not $NoContentType) { $curlArgs += @('-H', 'Content-Type: application/json') }
    $curlArgs += @('-H', 'Accept: application/json, text/event-stream')
    foreach ($h in $Headers) { $curlArgs += @('-H', $h) }
    if ($PSBoundParameters.ContainsKey('Body')) {
        [System.IO.File]::WriteAllText($bodyFile, $Body, $utf8)
        $curlArgs += @('--data-binary', "@$bodyFile")
    }
    $curlArgs += $Url

    $status = (& curl.exe @curlArgs | Out-String).Trim()
    $raw = if (Test-Path $outFile) { [System.IO.File]::ReadAllText($outFile) } else { '' }
    $head = if (Test-Path $headerFile) { [System.IO.File]::ReadAllText($headerFile) } else { '' }
    $json = $null
    if ($raw.Trim()) { try { $json = $raw | ConvertFrom-Json } catch { $json = $null } }
    return [pscustomobject]@{ Status = [int]("0$status" -replace '\D', ''); Headers = $head; Raw = $raw; Json = $json }
}

function Add-Result([string]$Group, [string]$Name, [bool]$Passed, [string]$Detail, [switch]$Advisory) {
    $level = if ($Advisory) { 'advisory' } else { 'required' }
    $script:results += [pscustomobject]@{ Group = $Group; Name = $Name; Passed = $Passed; Level = $level; Detail = $Detail }
    $mark = if ($Passed) { 'PASS' } else { 'FAIL' }
    $colour = if ($Passed) { 'Green' } elseif ($Advisory) { 'Yellow' } else { 'Red' }
    $line = "[$mark] ($level) $Group - $Name"
    if (-not $Passed -and $Detail) { $line += "`n         $Detail" }
    Write-Host $line -ForegroundColor $colour
}

function Get-Short([string]$Text) {
    $t = ($Text -replace '\s+', ' ').Trim()
    if ($t.Length -gt 160) { return $t.Substring(0, 160) + '...' }
    return $t
}

function Test-HasProperty($Object, [string]$Name) {
    return ($null -ne $Object) -and ($Object.PSObject.Properties.Name -contains $Name)
}

Write-Host "Testing MCP server at $Url" -ForegroundColor Cyan
Write-Host ''

# ---------------------------------------------------------------- lifecycle
$init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"' + $ProtocolVersion + '","capabilities":{},"clientInfo":{"name":"mcp-server-tester","version":"1.0"}}}'
$r = Send-Request -Body $init
if ($r.Status -eq 0) {
    Write-Host "No answer from $Url. Is the server running?" -ForegroundColor Red
    Remove-Item -Recurse -Force $tmp
    exit 99
}
$result = if (Test-HasProperty $r.Json 'result') { $r.Json.result } else { $null }
Add-Result 'Lifecycle' 'initialize answers 200 with a JSON result' ($r.Status -eq 200 -and $null -ne $result) "status $($r.Status), body: $(Get-Short $r.Raw)"
Add-Result 'Lifecycle' 'initialize answer is JSON-RPC 2.0 with the request id' ((Test-HasProperty $r.Json 'jsonrpc') -and $r.Json.jsonrpc -eq '2.0' -and $r.Json.id -eq 1) "body: $(Get-Short $r.Raw)"
Add-Result 'Lifecycle' 'initialize result has protocolVersion, capabilities and serverInfo.name' ((Test-HasProperty $result 'protocolVersion') -and (Test-HasProperty $result 'capabilities') -and (Test-HasProperty $result 'serverInfo') -and [bool]$result.serverInfo.name) "result: $(Get-Short $r.Raw)"
Add-Result 'Lifecycle' 'Content-Type of the answer is application/json' ($r.Headers -match '(?im)^content-type:\s*application/json') "headers: $(Get-Short $r.Headers)"
$capabilities = if (Test-HasProperty $result 'capabilities') { $result.capabilities } else { $null }
$serverVersion = if (Test-HasProperty $result 'protocolVersion') { $result.protocolVersion } else { $ProtocolVersion }

$old = $init.Replace($ProtocolVersion, '2024-11-05')
$r = Send-Request -Body $old
$negotiated = if ((Test-HasProperty $r.Json 'result') -and (Test-HasProperty $r.Json.result 'protocolVersion')) { $r.Json.result.protocolVersion } else { '' }
Add-Result 'Lifecycle' 'a client asking for 2024-11-05 gets that version back' ($negotiated -eq '2024-11-05') "server answered with protocolVersion '$negotiated'; a server that supports the requested version has to answer with it" -Advisory

$r = Send-Request -Body '{"jsonrpc":"2.0","method":"notifications/initialized"}'
Add-Result 'Lifecycle' 'notifications/initialized is accepted with 202 and no body' ($r.Status -eq 202 -and -not $r.Raw.Trim()) "status $($r.Status), body: $(Get-Short $r.Raw)"

# ---------------------------------------------------------------- transport
$r = Send-Request -Method GET -NoContentType
$sse = $r.Headers -match '(?im)^content-type:\s*text/event-stream'
Add-Result 'Transport' 'GET answers 405 or opens an event stream' ($r.Status -eq 405 -or ($r.Status -eq 200 -and $sse)) "status $($r.Status), body: $(Get-Short $r.Raw)"
if ($r.Status -eq 405) {
    Add-Result 'Transport' '405 answer names the allowed method in an Allow header' ($r.Headers -match '(?im)^allow:.*POST') "headers: $(Get-Short $r.Headers)" -Advisory
}

$list = '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
$r = Send-Request -Body $list -Headers @('Origin: http://evil.example')
Add-Result 'Transport' 'a request from a foreign Origin is rejected (403)' ($r.Status -eq 403) "status $($r.Status); servers must validate Origin to prevent DNS rebinding"
$r = Send-Request -Body $list -Headers @('Origin: http://localhost:6274')
Add-Result 'Transport' 'a request from a localhost Origin is accepted' ($r.Status -eq 200) "status $($r.Status), body: $(Get-Short $r.Raw)"
$r = Send-Request -Body $list -Headers @('MCP-Protocol-Version: 1999-01-01')
Add-Result 'Transport' 'an unsupported MCP-Protocol-Version header is rejected (400)' ($r.Status -eq 400) "status $($r.Status)"
$r = Send-Request -Body $list -Headers @("MCP-Protocol-Version: $serverVersion")
Add-Result 'Transport' 'the negotiated MCP-Protocol-Version header is accepted' ($r.Status -eq 200) "status $($r.Status) for version $serverVersion"

# ----------------------------------------------------------------- JSON-RPC
$r = Send-Request -Body '{"jsonrpc":"2.0","id":3,"method":"ping"}'
Add-Result 'JSON-RPC' 'ping is answered with an empty result' ($r.Status -eq 200 -and (Test-HasProperty $r.Json 'result') -and $r.Json.id -eq 3) "status $($r.Status), body: $(Get-Short $r.Raw)"

$r = Send-Request -Body '{"jsonrpc":"2.0","id":4,"method":"does/not/exist"}'
$code = if ((Test-HasProperty $r.Json 'error') -and (Test-HasProperty $r.Json.error 'code')) { $r.Json.error.code } else { $null }
Add-Result 'JSON-RPC' 'an unknown method gets error -32601 with the request id' ($code -eq -32601 -and $r.Json.id -eq 4) "status $($r.Status), body: $(Get-Short $r.Raw)"

$r = Send-Request -Body '{"jsonrpc":"2.0","method":"notifications/does-not-exist"}'
Add-Result 'JSON-RPC' 'an unknown notification is not answered' (-not $r.Raw.Trim()) "status $($r.Status), body: $(Get-Short $r.Raw)"

$r = Send-Request -Body '{"jsonrpc":"2.0","id":"abc-1","method":"tools/list","params":{}}'
$echoed = if (Test-HasProperty $r.Json 'id') { $r.Json.id } else { $null }
Add-Result 'JSON-RPC' 'a string request id is returned unchanged' ($echoed -is [string] -and $echoed -eq 'abc-1') "sent id ""abc-1"", got id '$echoed'"

$r = Send-Request -Body '{"jsonrpc":"2.0","id":5,"method":'
$code = if ((Test-HasProperty $r.Json 'error') -and (Test-HasProperty $r.Json.error 'code')) { $r.Json.error.code } else { $null }
Add-Result 'JSON-RPC' 'malformed JSON gets error -32700' ($code -eq -32700) "status $($r.Status), body: $(Get-Short $r.Raw)"

$r = Send-Request -Body '{"jsonrpc":"2.0","id":6}'
$code = if ((Test-HasProperty $r.Json 'error') -and (Test-HasProperty $r.Json.error 'code')) { $r.Json.error.code } else { $null }
Add-Result 'JSON-RPC' 'a request without a method gets error -32600' ($code -eq -32600) "got error code '$code'; body: $(Get-Short $r.Raw)" -Advisory

# ----------------------------------------------------------------- features
if (Test-HasProperty $capabilities 'tools') {
    $r = Send-Request -Body '{"jsonrpc":"2.0","id":10,"method":"tools/list","params":{}}'
    $hasTools = (Test-HasProperty $r.Json 'result') -and (Test-HasProperty $r.Json.result 'tools')
    $tools = @()
    if ($hasTools) { $tools = @($r.Json.result.tools) }
    Add-Result 'Tools' 'tools/list returns a tools array' $hasTools "status $($r.Status), body: $(Get-Short $r.Raw)"
    if ($tools.Count -gt 0) {
        $bad = @($tools | Where-Object { -not $_.name -or -not (Test-HasProperty $_ 'inputSchema') -or $_.inputSchema.type -ne 'object' } | ForEach-Object { $_.name })
        Add-Result 'Tools' "every tool has a name and an inputSchema of type object ($($tools.Count) tools)" ($bad.Count -eq 0) "not valid: $($bad -join ', ')"
        $noItems = @()
        foreach ($tool in $tools) {
            if (Test-HasProperty $tool.inputSchema 'properties') {
                foreach ($p in $tool.inputSchema.properties.PSObject.Properties) {
                    if ($p.Value.type -eq 'array' -and -not (Test-HasProperty $p.Value 'items')) { $noItems += "$($tool.name).$($p.Name)" }
                }
            }
        }
        Add-Result 'Tools' 'array parameters say what their items are' ($noItems.Count -eq 0) "no ""items"" for: $($noItems -join ', ')" -Advisory
    }
    $r = Send-Request -Body '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"this_tool_does_not_exist","arguments":{}}}'
    $failed = (Test-HasProperty $r.Json 'error') -or ((Test-HasProperty $r.Json 'result') -and (Test-HasProperty $r.Json.result 'isError') -and $r.Json.result.isError)
    Add-Result 'Tools' 'calling an unknown tool is answered with an error' ($failed -and $r.Json.id -eq 11) "status $($r.Status), body: $(Get-Short $r.Raw)"
}

if (Test-HasProperty $capabilities 'prompts') {
    $r = Send-Request -Body '{"jsonrpc":"2.0","id":20,"method":"prompts/list","params":{}}'
    $hasPrompts = (Test-HasProperty $r.Json 'result') -and (Test-HasProperty $r.Json.result 'prompts')
    $prompts = @()
    if ($hasPrompts) { $prompts = @($r.Json.result.prompts) }
    Add-Result 'Prompts' 'prompts/list returns a prompts array' $hasPrompts "status $($r.Status), body: $(Get-Short $r.Raw)"
    if ($prompts.Count -gt 0) {
        $bad = @($prompts | Where-Object { -not $_.name })
        Add-Result 'Prompts' "every prompt has a name ($($prompts.Count) prompts)" ($bad.Count -eq 0) ''
    }
    $r = Send-Request -Body '{"jsonrpc":"2.0","id":21,"method":"prompts/get","params":{"name":"this_prompt_does_not_exist"}}'
    Add-Result 'Prompts' 'getting an unknown prompt is answered with an error' ((Test-HasProperty $r.Json 'error') -and $r.Json.id -eq 21) "status $($r.Status), body: $(Get-Short $r.Raw)"
}

if (Test-HasProperty $capabilities 'resources') {
    $r = Send-Request -Body '{"jsonrpc":"2.0","id":30,"method":"resources/list","params":{}}'
    $hasResources = (Test-HasProperty $r.Json 'result') -and (Test-HasProperty $r.Json.result 'resources')
    $resources = @()
    if ($hasResources) { $resources = @($r.Json.result.resources) }
    Add-Result 'Resources' 'resources/list returns a resources array' $hasResources "status $($r.Status), body: $(Get-Short $r.Raw)"
    if ($resources.Count -gt 0) {
        $bad = @($resources | Where-Object { -not $_.uri -or -not $_.name })
        Add-Result 'Resources' "every resource has a uri and a name ($($resources.Count) resources)" ($bad.Count -eq 0) ''
    }
    $r = Send-Request -Body '{"jsonrpc":"2.0","id":31,"method":"resources/read","params":{"uri":"file:///this/resource/does/not/exist"}}'
    Add-Result 'Resources' 'reading an unknown resource is answered with an error' ((Test-HasProperty $r.Json 'error') -and $r.Json.id -eq 31) "status $($r.Status), body: $(Get-Short $r.Raw)"
    $r = Send-Request -Body '{"jsonrpc":"2.0","id":32,"method":"resources/templates/list","params":{}}'
    $ok = (Test-HasProperty $r.Json 'result') -and (Test-HasProperty $r.Json.result 'resourceTemplates')
    Add-Result 'Resources' 'resources/templates/list returns a resourceTemplates array' $ok "status $($r.Status), body: $(Get-Short $r.Raw); clients such as MCP Inspector call this for every server with resources" -Advisory
}

# ------------------------------------------------------------------ summary
Remove-Item -Recurse -Force $tmp
$required = @($script:results | Where-Object { $_.Level -eq 'required' })
$requiredFailed = @($required | Where-Object { -not $_.Passed })
$advisoryFailed = @($script:results | Where-Object { $_.Level -eq 'advisory' -and -not $_.Passed })
Write-Host ''
Write-Host "Required: $($required.Count - $requiredFailed.Count) of $($required.Count) passed. Advisory: $($advisoryFailed.Count) failed." -ForegroundColor Cyan
exit $requiredFailed.Count
