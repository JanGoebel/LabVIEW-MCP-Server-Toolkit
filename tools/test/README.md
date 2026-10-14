# Protocol tests against a running server

These checks talk to a running MCP server over HTTP. They complement the
Caraya tests in `tests/`, which test this toolkit's own fake tools; the checks
here test whether a server speaks the protocol correctly, whatever it serves.

Start a server first, for example `examples/Full Featured MCP Server/main.vi`.

## Test-McpServer.ps1

A curl-based checker for the rules every MCP server has to follow. It calls no
tools, so it is safe to run against any server.

```powershell
.\tools\test\Test-McpServer.ps1
.\tools\test\Test-McpServer.ps1 -Url http://127.0.0.1:36999/mcp/server
```

| Group | What is checked |
|---|---|
| Lifecycle | `initialize` answer and its fields, version negotiation, `notifications/initialized` |
| Transport | GET handling, `Origin` validation, `MCP-Protocol-Version` header |
| JSON-RPC | `ping`, unknown method, unknown notification, string ids, malformed JSON |
| Tools, Prompts, Resources | list methods and their entries, errors for unknown names (only for capabilities the server declares) |

"required" checks are demanded by the specification, "advisory" ones are
recommendations. The exit code is the number of failed required checks.

### In CI

`tests\Run_Protocol_Tests_CLI.vi` starts the test server of the Caraya suite
(port 36987, one fixture tool, prompt and two resources), runs this script
against it, writes its output to `tests\results\protocol-report.txt` and stops
the server again. Exit Code is 0 when every required check passed. Both
workflows run it after the Caraya suite:

```powershell
LabVIEWCLI -OperationName RunVI -VIPath "$PWD\tests\Run_Protocol_Tests_CLI.vi" `
    -LabVIEWPath "C:\Program Files\National Instruments\LabVIEW 2020\LabVIEW.exe" -PortNumber <port>
```

## Official conformance suite

The MCP project publishes its own suite. Needs Node.js.

```powershell
npx -y @modelcontextprotocol/conformance server --url http://127.0.0.1:36987/mcp/server
npx -y @modelcontextprotocol/conformance server --url http://127.0.0.1:36987/mcp/server --scenario ping
```

Most of its scenarios call tools, prompts and resources with fixed names
(`test_simple_text` and so on) that its reference server provides, so they fail
against any other server. The scenarios that apply to every server are
`server-initialize`, `ping`, `tools-list`, `resources-list`, `prompts-list` and
`dns-rebinding-protection`.
