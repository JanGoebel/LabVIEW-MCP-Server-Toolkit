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
| Tools, Prompts, Resources | list methods and their entries, errors for unknown names (only for capabilities the server declares); an unknown tool is also called with a `progressToken`, which may be answered as a stream, and the server must still answer afterwards |

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

## Official conformance suite (Invoke-Conformance.ps1)

The MCP project publishes its own suite,
[`@modelcontextprotocol/conformance`](https://github.com/modelcontextprotocol/conformance).
`Invoke-Conformance.ps1` runs exactly the server scenarios that one revision of
the specification requires (default 2026-07-28), with a pinned version of the
suite. Needs Node.js.

Many scenarios call tools, prompts and resources with fixed names
(`test_simple_text`, `test://static-text`, ...). Start
`examples/Conformance MCP Server/Conformance Main.vi`, which registers the ones
this toolkit can express, then:

```powershell
.\tools\test\Invoke-Conformance.ps1
.\tools\test\Invoke-Conformance.ps1 -Scenario server-stateless
.\tools\test\Invoke-Conformance.ps1 -NoBaseline
```

`conformance-baseline.yml` lists the scenarios and single checks that need
features the toolkit deliberately does not have, each with its reason (for
example audio content, resource templates, and sampling and roots, which MCP
2026-07-28 deprecates). The exit code is 0 when every failure is in the
baseline and every baselined entry still fails, and 1 for a regression or for a
baselined entry that now passes (then remove it). The per-scenario results
(`checks.json`) are written to `-OutDir`.

## Test-WithCodex.ps1

Lets the OpenAI Codex CLI connect to a running server, list its tools and call
some of them. It shows what an OpenAI client actually receives: Codex rewrites
every tool schema into a TypeScript-like declaration for the model, so a
missing `items`, `properties` or `enum` shows up there as `unknown` or a bare
`number`.

Needs Node.js, `npm install -g @openai/codex` and a `codex login` in your own
terminal. The server is passed as a temporary override; `~/.codex/config.toml`
is not changed.

```powershell
.\tools\test\Test-WithCodex.ps1 -Url http://127.0.0.1:36987/mcp/server -Calls fake_tool_schema_shapes
```

The full event log goes to `$env:TEMP\codex-mcp-report.jsonl`. The exit code
is 0 when Codex reports the server's tools. Whether a call worked is in the
printed answer and the log; the script does not judge it. It is not part of
CI, because it needs an OpenAI sign-in.
