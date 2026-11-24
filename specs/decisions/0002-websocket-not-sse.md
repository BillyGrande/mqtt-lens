---
type: decision
title: WebSocket, not SSE
description: Live updates use the LiveView WebSocket.
status: draft
tags: [websocket, liveview]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §3, §4.4, §6
---

# Context

The UI shows live updates of new messages for the selected subtree. LiveView runs the live updates on a WebSocket at `/live`.

# Decision

Use the LiveView WebSocket (WSS through Traefik) for live updates. The sources do not give a comparison with SSE.

# Consequences

- A cross-site WebSocket hijack is a threat (T9). The controls are `check_origin`, the CSRF token in the connect parameters and a SameSite cookie.
- The CSP allows `connect-src 'self' wss://<host>`.
- Limits: WebSocket frame size 64 KiB, 4 sockets per session, 200 sockets in total, 20 events per second per socket.
- The server closes the user's sockets at logout or session deletion.

# Citations

1. [Web security](/features/web-security.md)
2. [Sessions](/features/sessions.md)
3. [Routes](/features/routes.md)
