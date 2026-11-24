---
type: architecture
title: Threat model
description: Assets, attackers, threats T1-T20, controls and accepted residual risks.
status: draft
tags: [security, threat-model]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §2
---

# Threat model

## Assets

| Asset | Why it is important |
|---|---|
| MQTT message content | Plant telemetry, setpoints, customer data. |
| Topic structure | It shows customers, sites and environments. |
| The broker connection | Its credentials and its network position inside the cluster. |
| User sessions | A stolen session gives the data of that user. |
| Pod and cluster | The pod is a foothold inside the cluster. |

## Attackers

| ID | Attacker | Capability |
|---|---|---|
| A1 | Anonymous internet user | Sends any HTTP or WebSocket request to the public host. |
| A2 | Authenticated user | Valid login. Sends any LiveView event with any parameters. Tries to see topics outside their role. |
| A3 | MQTT publisher | **Publishes any topic name and any payload.** Many real brokers allow anonymous publish, so anybody who reaches the broker is an A3. |
| A4 | Malicious website | The victim's browser has a valid session and visits the attacker's site (CSRF, cross-site WebSocket hijack, clickjacking). |
| A5 | Supply chain | A compromised Hex package, npm package, downloaded tool binary or base image. |

## Threats and controls

| # | Threat | Control (section) |
|---|---|---|
| T1 | A1 reads data without login | Deny by default. Every route and every LiveView needs a valid session ([routes](/features/routes.md)). |
| T2 | A1 brute-forces or floods login | Rate limits per IP. Traefik limits in front ([web security](/features/web-security.md)). |
| T3 | A2 sees topics outside their role | Server-side filtering of the tree, the counts, the history and the live updates. Deny wins over allow ([authorization](/features/authorization.md)). |
| T4 | **A2 sends a forged LiveView event** (for example, a forbidden topic name) | Authorization in `mount`, `handle_params` **and every** `handle_event` ([authorization](/features/authorization.md)). |
| T5 | **A3 stores XSS in a topic name or payload** | HEEx escaping, ban on `raw/1`, strict CSP ([web security](/features/web-security.md)). |
| T6 | A3 floods unique topics or big payloads (memory DoS) | Hard limits on topics, bytes, history and payload size. Process heap limits ([resource safety](/architecture/resource-safety.md), [resource safety](/architecture/resource-safety.md)). |
| T7 | **Atom table exhaustion** (crashes the VM) | No conversion of external data to atoms. CI checks ([resource safety](/architecture/resource-safety.md)). |
| T8 | A slow client makes its process mailbox grow | Batched updates, queue checks, `max_heap_size` ([resource safety](/architecture/resource-safety.md)). |
| T9 | A4 does CSRF or cross-site WebSocket hijack | CSRF token, `check_origin`, SameSite cookie, read-only events ([web security](/features/web-security.md)). |
| T10 | A4 does clickjacking | `frame-ancestors 'none'` ([web security](/features/web-security.md)). |
| T11 | Session theft or fixation | `__Host-` cookie, HttpOnly, Secure, new token at login, idle and absolute timeouts, server-side store ([sessions](/features/sessions.md)). |
| T12 | An open socket outlives the session (logout, expiry) | Server closes the user's sockets; periodic re-check ([sessions](/features/sessions.md)). |
| T13 | OIDC attacks (code injection, token replay, mix-up) | PKCE S256, `state`, `nonce`, exact `iss`/`aud`/`azp` checks, algorithm allow-list ([OIDC login](/features/oidc-login.md)). |
| T14 | SSRF into the cluster | No user-supplied hosts. Egress NetworkPolicy ([deployment](/architecture/deployment.md)). |
| T15 | Remote code execution through Erlang distribution | Distribution is off. No EPMD, no cookie, no remote shell ([deployment](/architecture/deployment.md)). |
| T16 | Pod compromise is used to move in the cluster | Non-root, read-only rootfs, no capabilities, no service-account token, egress NetworkPolicy ([deployment](/architecture/deployment.md)). |
| T17 | Secrets leak in logs or errors | Parameter filtering, no token or payload logging, generic error pages ([observability](/architecture/observability.md)). |
| T18 | Supply chain (A5) | Few dependencies, `mix_audit`, `mix hex.audit`, `sobelow`, lockfile, pinned tool binaries ([supply chain](/architecture/supply-chain.md)). |
| T19 | A bug in the app's authorization | Defense in depth: the broker user has a subscribe-only ACL ([broker ingest](/features/broker-ingest.md)). |
| T20 | Display spoofing (bidi overrides, control characters in topic names) | The UI shows control and bidi characters as visible escapes ([web security](/features/web-security.md)). |

## Residual risks (we accept these)

- A user with a valid role can copy the data that the role allows.
- The OIDC provider (and the IdP behind it) is trusted. MFA is enforced there, not in this app.
- One replica: a pod restart ends all sessions and clears all history.
- The release start scripts need `/bin/sh`, so the image is not shell-free ([deployment](/architecture/deployment.md)).
- LiveView's client patches the DOM with HTML from the server. So we cannot use
  Trusted Types `'none'` as a second XSS barrier. Server-side escaping is the main control ([web security](/features/web-security.md)).

# Citations

1. [Architecture overview](/architecture/overview.md)
2. [Web security](/features/web-security.md)
