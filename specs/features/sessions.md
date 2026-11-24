---
type: feature
title: Sessions and socket lifetime
description: Server-side sessions, cookie settings, timeouts and socket lifetime.
status: draft
tags: [auth, sessions, security]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §4.3, §4.5
---

# Sessions

- The Phoenix cookie session is **signed and encrypted** (`encryption_salt` set), and it holds
  **only a session token**. All session data is on the server.
- Session token: 256 bit from `:crypto.strong_rand_bytes/1`. The ETS key is SHA-256(token),
  so a heap dump does not give a usable token.
- Cookie `__Host-mlens`: `Secure; HttpOnly; SameSite=Lax; Path=/`, no `Domain`.
  - `Lax`, not `Strict`: the first request after the Keycloak redirect is cross-site.
    CSRF protection comes from [web security](/features/web-security.md).
- Idle timeout 30 min. Absolute timeout 8 h. Then the user must log in again.
- Max 5 sessions per `sub`. The oldest session is deleted.
- Max 10 000 sessions in total. When full, new logins get 503 (no eviction of active users).
- A sweeper process deletes expired sessions and flows every minute.
- `secret_key_base` and the salts come from secret files ([deployment](/architecture/deployment.md)), not from source code.

# Socket lifetime (T12)

- At login, the session gets a `live_socket_id` = `"sessions:<token hash>"`.
- At logout or session deletion, the app broadcasts `"disconnect"` on that ID. Phoenix closes
  every LiveView socket of that session.
- Each LiveView checks its session every 60 s (`:timer` message). If the session is gone or
  expired, it redirects to `/auth/login`.
- The idle timeout counts user events, not server pushes. An open tab without user activity
  expires after 30 min.

# Citations

1. [Threat model](/architecture/threat-model.md)
2. [Web security](/features/web-security.md)
