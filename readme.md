## 🧰 LabVIEW Toolkit for MCP Servers

This repository contains the source code for a LabVIEW toolkit designed to facilitate the creation of **Model Context Protocol (MCP) servers** using LabVIEW Web Services.

---

## 🚧 Status: Under Construction

This toolkit is currently **under active development**. Features are being implemented and tested to ensure robust and reliable communication with MCP-compatible clients.

---

## ✨ Overview

The Model Context Protocol (MCP) is a language-agnostic protocol designed to allow models (servers) to be managed and utilized by intelligent clients. This toolkit provides the necessary LabVIEW VIs and structures to build an MCP server that communicates over HTTP using standard LabVIEW Web Services. 

### Key Communication Detail

The toolkit implements the server-side handling of Remote Procedure Calls (RPC) over HTTP, as specified by the MCP. This enables integration with intelligent clients like **Claude Desktop** and other development environments that adhere to the protocol.

The core communication uses **JSON-RPC 2.0 messages** transmitted via HTTP POST requests, where:

* **Client (e.g., Claude Desktop) $\rightarrow$ Server (LabVIEW):** Sends **Request** or **Notification** JSON-RPC messages (e.g., `initialize`, `shutdown`).
* **Server (LabVIEW) $\rightarrow$ Client:** Sends **Response** (either `result` or `error`) JSON-RPC messages.

---

## 📖 Documentation & Protocol Details

For a complete understanding of the JSON message structure, required fields, and the specific methods used for the client-server handshake, please refer to the official MCP documentation:

* **[Model Context Protocol (MCP) Documentation](https://modelcontextprotocol.io/docs/protocol)**
* **[MCP Handshake Messages (Initialization & Shutdown)](https://modelcontextprotocol.io/docs/protocol/messages/handshake)**

---

## 🚀 Getting Started (Planned)

Once complete, this section will detail how to include the VIs in your LabVIEW project, configure your Web Service, and implement the necessary logic to handle the incoming RPC method calls.