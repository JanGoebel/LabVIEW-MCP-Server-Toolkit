# 📊 MCP Datalogger Example

This example shows how to use an MCP server with a datalogger. The Frontpanel has a control "Connected?" that lets you specify which channels are "connected"—meaning they have a useful signal (sine, triangle, sawtooth) or just pure noise.

## ⚙️ How It Works

The MCP Client (e.g., Claude Desktop) can query snapshots of the individual channels as images and evaluate if the channel is connected or not. It can then autonomously start logging *only* for the connected channels (or only for not-connected channels), and perform other related tasks based on the evaluation.

## 💬 Example Prompt

You can use the following prompt to test the integration:

> "Check my datalogger through MCP. Which channels are connected? Identify the channels that have not just noise on them, then log the connected channels for a moment, then stop and read the log file and check if the logging was successful."

## ⚡ MCP Prompt Registration

This prompt is also registered as an **MCP Prompt** in the server. This means you can conveniently select it from the `+` menu in Claude Desktop and automatically insert it into your prompt field without having to type it out manually.

## 🚀 Implementation Note

This is just an example, and the implementation is kept as simple as possible for demo purposes. Much more scalable implementations are possible, but this serves to demonstrate the basic concept of automating test and measurement applications through MCP.