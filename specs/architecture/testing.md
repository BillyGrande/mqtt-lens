---
type: architecture
title: Tests
description: Test levels and what each level checks.
status: draft
tags: [testing]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §11
---

# Tests

| Level | What |
|---|---|
| Unit | Topic matcher, scope compilation, store limits, `Display.sanitize/1`, config validation. |
| Property | Matcher vs a simple reference implementation (`StreamData`). Random topics and filters, including `$`-topics. |
| LiveView | `Phoenix.LiveViewTest`: every event with a forbidden topic → no data in the render. Forged events. Unknown events. Long parameters. |
| Auth | Every live route redirects to login without a session. Socket connect without a session fails. Logout closes the socket. Idle and absolute expiry. Flow state used twice → rejected. Wrong `state` → 400. |
| Headers | CSP and all [web security](/features/web-security.md) headers on every response type. Cookie flags. |
| XSS corpus | Topic names and payloads with `<script>`, `<img onerror>`, `javascript:`, `"><svg onload>`, bidi overrides. Check that the rendered HTML contains only escaped text. Browser test (Playwright) that no script runs and the console has no CSP violation (stage 1b). |
| Resource | Flood the store with unique topics and big payloads; check the limits and the memory. Slow client → resync, not memory growth. Atom count is constant after a flood. |
| Integration | EMQX + Keycloak in Docker Compose (realm import). Full login, tree, live updates. |
