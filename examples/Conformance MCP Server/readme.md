# Conformance MCP Server

## Overview

This example is not a demo for a chat client. It is the server the official MCP
conformance suite
([`@modelcontextprotocol/conformance`](https://github.com/modelcontextprotocol/conformance))
is run against. Many scenarios of that suite call tools, prompts and resources
with fixed names (`test_simple_text`, `test://static-text`, ...). This example
registers the ones the toolkit can express; each returns fixed test data.

## Running the suite

1. Open `Conformance MCP Server.lvproj` and run `Conformance Main.vi`. The
   server listens on `http://127.0.0.1:36987/mcp/server`.
2. Run the suite (needs Node.js):

   ```powershell
   .\tools\test\Invoke-Conformance.ps1
   ```

   See `tools/test/README.md` for the options and the baseline of expected
   failures.
3. Press **Stop** on the front panel of `Conformance Main.vi`.

## Fixtures

`Add Conformance Fixtures.vi` registers everything. The file name of a tool or
prompt VI is its MCP name.

| Kind | Name | What it does |
|---|---|---|
| Tool | `test_simple_text` | Returns the text "This is a simple text response for testing." |
| Tool | `test_image_content` | Returns a small red picture as image content |
| Tool | `test_error_handling` | Always fails with error 5000, so the result has `isError` true |
| Tool | `test_tool_with_progress` | Reports the progress 0, 50 and 100 of 100 with `Report Progress.vi` |
| Tool | `test_input_required_result_elicitation` | Asks "What is your name?" (key `user_name`) and answers "Hello, name!" |
| Tool | `test_input_required_result_request_state` | Asks "Please confirm" (key `confirm`) and answers "state-ok: confirmed" |
| Tool | `test_input_required_result_multi_round` | Asks for a name (key `step1`), then for a color (key `step2`) |
| Tool | `test_input_required_result_tampered_state` | Asks "Please confirm" (key `confirm`); the suite retries with a changed `requestState`, which the server refuses |
| Prompt | `test_simple_prompt` | Returns "This is a simple prompt for testing." |
| Prompt | `test_prompt_with_arguments` | Required arguments `arg1` and `arg2`, both put into the text |
| Prompt | `test_input_required_result_prompt` | Asks "What context should the prompt use?" (key `user_context`) |
| Resource | `test://static-text` | The file `static-text.txt` |
| Resource | `test://static-binary` | The file `static-binary.png` |

The tool and prompt VIs lie in `tools` and `prompts`. The questions are asked
with `Ask User.vi`; the resources get their uri from the `uri` input of
`Add Resource (File).vi`.

## What is left out

The suite also has fixtures for features this toolkit does not have: audio
content, embedded resources and mixed content in tool results, prompts with an
image or an embedded resource, resource templates, sampling and roots requests,
logging, the tasks extension and a few more. They are not faked here. Their
scenarios fail and are listed, each with its reason, in
`tools/test/conformance-baseline.yml`.
