---
type: feature
title: Web security
description: Response headers, rendering of untrusted content, cross-site protection, request limits and errors.
status: draft
tags: [web-security, csp, xss]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §6
---

# Web security

## Response headers (all responses)

```
Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self';
  img-src 'self' data:; connect-src 'self' wss://<host>; font-src 'self';
  base-uri 'none'; form-action 'self' https://<keycloak-host>; frame-ancestors 'none'
Strict-Transport-Security: max-age=63072000; includeSubDomains
X-Content-Type-Options: nosniff
Referrer-Policy: no-referrer
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Resource-Policy: same-origin
Permissions-Policy: camera=(), microphone=(), geolocation=()
Cache-Control: no-store            (HTML)
Cache-Control: public, max-age=31536000, immutable   (digested assets only)
```

- No inline scripts and no inline `<style>`. Templates do not use the `style` attribute.
  (A browser test checks that the console has no CSP violations.)
- `put_secure_browser_headers/2` with these values in the router pipeline.
  `OpsEndpoint` sends no HTML.

## Rendering untrusted content (T5, T20)

Topic names and payloads come from A3. They are hostile input.

- All output goes through HEEx, which escapes by default.
- **`raw/1`, `Phoenix.HTML.raw`, `{:safe, _}` and `phx-no-format` with external data are banned.**
  A custom Credo check and a CI grep fail the build if they appear.
- No `phx-hook` reads payload data into `innerHTML`. Hooks get data only through
  `textContent` (a review rule; the MVP plans no hooks that display data).
- JSON view: decode with the built-in `JSON` module (string keys), then pretty-print with
  `Jason.encode!(value, pretty: true)`, then render as escaped text in `<pre>`.
- No auto-links, no Markdown, no images from payloads.
- Binary payloads (not valid UTF-8) show as hex only.
- Control characters (C0, C1) and bidi or invisible characters (U+200B–U+200F,
  U+202A–U+202E, U+2066–U+2069, U+FEFF) are shown as visible escapes like `⟨U+202E⟩`
  by `MqttLens.Display.sanitize/1`, before HEEx escaping.
- Display limit 64 KiB per payload. Bigger payloads are cut, with the original size shown.

Trusted Types: LiveView's client applies server HTML with DOM patching, so
`trusted-types 'none'` would break the app. Server-side escaping is the main control. The CSP
blocks inline and third-party scripts, so an injection that gets through cannot run a script
that is not on our origin.

## Cross-site protection (T9)

- `protect_from_forgery` on all browser routes. `DELETE /auth/logout` needs the CSRF token.
- LiveView socket: `check_origin: ["https://<host>"]` (exact). The CSRF token is in the
  connect parameters (Phoenix default). The session comes only from `connect_info`.
- The session cookie is SameSite=Lax.
- No CORS headers.

## Request limits

| Limit | Value |
|---|---|
| `/auth/*` per client IP | 10 per minute, burst 5 |
| LiveView events per socket | 20 per second (excess events ignored, then disconnect after 10 s of excess) |
| LiveView sockets per session | 4 |
| LiveView sockets in total | 200 |
| WebSocket frame size | 64 KiB (`max_frame_size`) |
| Request body | 16 KiB (`Plug.Parsers` `length`) |
| Event parameter length | 1 024 bytes |

The client IP comes from `X-Forwarded-For` **only** when the TCP peer is in the configured
trusted proxy CIDRs (Traefik), using `remote_ip`. Otherwise the TCP peer address is used.

## Errors

- Users see generic error pages with a request ID. `debug_errors: false` in prod.
- Details go to the log with the same request ID.

# Citations

1. [Threat model](/architecture/threat-model.md)
2. [No Trusted Types](/decisions/0003-no-trusted-types.md)
