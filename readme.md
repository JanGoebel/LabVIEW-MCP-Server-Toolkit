# 🧰 LabVIEW MCP Server Toolkit

With this toolkit you can make large language models like ChatGPT or Claude control your LabVIEW applications.

It opens a http server on the current machine. An MCP client can connect to that server and retrieve information about the available tools, prompts and resources. Then during a chat-conversation the LLM can decide itself when to call a VI for a specific purpouse.

---

## ✨ Overview

The Model Context Protocol (MCP) is a protocol to enable LLM chatbot applications to call external code. There is a huge community developing MCP servers typically tied to controlling some applications.
On mcp.so you can find MCP servers for apps like Blender, TouchDesigner, Photoshop, Git, and many more.
You can add multiple of these MCP servers to an MCP Client like Claude Desktop. The AI can then initiate multiple different actions in multiple different software products.

Detailed info can be found here:

https://modelcontextprotocol.io/docs/getting-started/intro

MCP consists of 3 types of objects:

### Tools
A tool is a function that can be called by the AI. It has in- and ouputs, a name and a description. The AI can read this description to understand how to use the tool (e.g. which strings to pass to the input ...) 

### Prompts
A prompt is a function with string-inputs and a single string output. It's listed for the user to pick in the chat-client (little plus icon in claude desktop). When selected, a dialog appears with a description and all parameters (string inputs). When clicking okay the resulting string is inserted into the chat message field.
It's a much less used feature than tools and really just a "configurable prompt template".

### Resoruces
Resources are very similar to prompts and added in the same way. They return a single string or byte stream. Resources are usually files that are fully returned as text. These are selected just as prompts, but they don't have parameters.
They are also much less common than tools and are just longer "prompt templates".

The core communication uses **JSON-RPC 2.0 messages** transmitted via HTTP POST requests, where:

## MCP Clients

This toolkit is tested using Claude Desktop as an MCP client. There are many more clients out there. Usually they have a ..config.json file that contains the MCP config which looks like this:

'''
{
  "mcpServers": {
    "vi-scripting-server": {
      "command": "npx",
      "args": [
        "mcp-remote",
        "http://127.0.0.1:36987/mcp/server"
      ],
      "env": {
      }
    }
  }
}
'''

It may of course contain multiple servers.
The port can be changed when starting the server.
Claude Desktop usually retrieves the list of available tools and prompts on startup, so multiple restarts may be necessary (close taskbar-icon also).

Download Claude Desktop:
https://claude.com/download

## 🚀 Datatypes
Every control of a tool VI's connector pane becomes a tool input, described to the model as JSON Schema in `tools/list`. Arguments in `tools/call` are converted with JSONtext into the control's own type.

| LabVIEW type | JSON Schema | Value in `tools/call` |
|---|---|---|
| I8 … U64 | `integer` with `minimum`/`maximum` of the representation | number |
| SGL, DBL, EXT (also with unit) | `number` | number |
| Boolean | `boolean` | `true`/`false` |
| String | `string` | string |
| Path | `string` | path as text, e.g. `C:\\data\\log.csv` |
| Timestamp | `string` with `format: date-time` | ISO 8601, e.g. `2026-10-17T12:34:56Z` |
| Enum | `string` with `enum` of the item names | item name (a number is an error) |
| Cluster | `object` with `properties` named by the element labels | object; a member left out keeps the control's value |
| Array, any number of dimensions | nested `array` with `items` | nested arrays |
| Other types (variant, waveform, complex, fixed point, ring, map, set, refnum, class, picture) | `{}` (any value) | not supported as inputs yet |

What else goes into the schema, so the model knows what to send:
- `description`: the control's description, and the description of every cluster element at any depth (inside clusters and arrays).
- Numerics with a unit get `Unit: <unit>.` appended to their description.
- `minimum`/`maximum` from the control's Data Entry limits when they are set to coerce, combined with the range of the integer representation.
- `default`: the control's default value for inputs that are not required on the connector pane (left out when it would be longer than 1024 characters).
- `required`: the inputs marked *Required* on the connector pane.

Write the descriptions with the model in mind: what the value means, its unit and its allowed values.

Outputs of any type are flattened to JSON (timestamps as ISO 8601, enums as item names):
- The result's text block holds all outputs as one JSON object, for older clients.
- `structuredContent` holds the same object without picture outputs.
- Picture outputs are returned as separate image content (PNG).
- `tools/list` describes the outputs as `outputSchema`, built like the input schema: types, descriptions, ranges, units.

## Tool title, annotations and errors

`Add Tool.vi` takes two optional inputs that clients show to users or use to decide when to ask before running a tool:
- `title`: a display name. Without one, no `title` is sent and clients show the tool name.
- `annotations` (`Tool Annotations.ctl`): `readOnlyHint`, `destructiveHint`, `idempotentHint` and `openWorldHint`.
  - Each hint is *not set*, *true* or *false*. Only hints that are set are sent.
  - MCP's defaults for unset hints are: not read-only, destructive, not idempotent, open world.
  - Mark tools that only read values as read-only. Mark tools that move hardware or delete data as destructive, so clients ask the user first.

A call with missing required arguments, or with an argument that does not fit its control's type, returns a normal result with `isError: true` and a message the model can act on. Unknown tools and malformed requests are JSON-RPC errors.

## Protocol versions

The server speaks both eras of MCP on the same endpoint, and decides per request:

- **MCP 2026-07-28** (stateless): a request whose `params._meta` carries `io.modelcontextprotocol/protocolVersion`.
  - Such a request must also carry `io.modelcontextprotocol/clientCapabilities` and the headers `MCP-Protocol-Version`, `Mcp-Method` and, for `tools/call`, `prompts/get` and `resources/read`, `Mcp-Name`.
  - Results carry `resultType` and `_meta.io.modelcontextprotocol/serverInfo`. Lists and `resources/read` also carry the caching hints `ttlMs` and `cacheScope`.
  - `server/discover` returns the supported versions, capabilities and server info.
- **MCP 2025-11-25, 2025-06-18, 2025-03-26 and 2024-11-05**: clients that start with `initialize`. These are served exactly as before.

An unsupported version is answered with HTTP 400 and error `-32022`, listing every supported version.

## Asking the user (elicitation)

A tool can ask the user a question while it runs, for example to confirm before it moves hardware. This works with clients that speak MCP 2026-07-28 and declare the `elicitation` capability.

- `Confirm With User.vi` asks a yes/no question. `Ask User.vi` asks for a small form (a flat JSON Schema with string, number, Boolean or enum fields).
- Each question needs a key that is unique within the tool.
- The tool VI runs twice:
  1. On the first run, the VI returns `pending`. The tool must then end at once, **without side effects**. The server sends the question to the client.
  2. The client asks the user and calls the tool again with the answer. On this run the same VI returns the answer (*accept*, *decline* or *cancel*). Do the real work only here.
- If the client cannot ask (older protocol, or no `elicitation` capability), the VI returns `not supported`. The tool decides what to do then: refuse with an error, or use a safe default.
- Never use it to ask for passwords or keys.

## Progress and cancellation

Long-running tools can report progress and stop when the client cancels.

- `Report Progress.vi` (progress, optional total and message) sends a `notifications/progress` event to the client. It returns `cancelled?`. Stop the tool when it is TRUE.
- `Cancel Requested.vi` returns `cancelled?`, for loops that do not report progress.
- Progress is streamed only when the client asks for it: `tools/call` with `_meta.progressToken`, and an `Accept` header that includes `text/event-stream`. The answer is then a Server-Sent Events stream: the progress events, then the result. Without that, both VIs do nothing and return FALSE.
- Cancelling works in two ways:
  - MCP 2026-07-28 clients cancel by closing the stream.
  - Older clients send `notifications/cancelled`.
  - Either way, the next `Report Progress.vi` / `Cancel Requested.vi` call returns TRUE.
  - A closed stream is noticed when an event is not taken within about one second.
  - `notifications/cancelled` only reaches a streamed call. A non-streamed call blocks other requests until it ends.

## Dependencies
This toolkit uses IG HTTP Server Toolkit and JKI JSONtext.

https://www.vipm.io/package/illuminatedg_lib_ig_http_server/

https://www.vipm.io/package/jdp_science_jsontext/

## G-AI
Main purpouse to develop this toolkit is to use it for my G-AI project which can generate LabVIEW code using LLMs. Have a look at it here:
https://github.com/JanGoebel/G-AI

## License
This toolkit is published under the MIT license. Feel free to use and modify it.