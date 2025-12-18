# 🧰 LabVIEW MCP Server Toolkit

With this toolkit you can make large language models like ChatGPT control your LabVIEW applications.

It opens a http server on the current machine. An MCP client can connect to that server and retrieve information about the available tools, prompts and resources. Then during a chat-conversation the LLM can decide itself when to call a VI for a specific purpouse.

---

## ✨ Overview

The Model Context Protocol (MCP) is a protocol to enable LLM chatbot applications to call external code. There is a huge community developing MCP servers typically tied to controlling some applications.
On mcp.so you can find MCP servers for apps like Blender, TouchDesigner, Photoshop, Git, and many more.
You can add multiple of these MCP servers to an MCP Client like Claude Desktop. The AI can then initiate multiple different actions in multiple different software products.

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

It may of course contain multiple servers.
The port can be changed when starting the server.
Claude Desktop usually retrieves the list of available tools and prompts on startup, so multiple restarts may be necessary (close taskbar-icon also).
Download Claude Desktop:
https://claude.com/download

## 🚀 Datatypes
Currently not all datatypes are fully supported.

## Dependencies
This toolkit uses IG HTTP Server Toolkit and JKI JSONtext.
https://www.vipm.io/package/illuminatedg_lib_ig_http_server/
https://www.vipm.io/package/jdp_science_jsontext/

## VI-Scripting-Server
Main purpouse to develop this toolkit is to use it for my vi-scripting-server project which can generate LabVIEW code using LLMs. Have a look at it here:
https://github.com/JanGoebel/labview_assistant