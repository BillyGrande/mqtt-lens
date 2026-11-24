---
type: architecture
title: Architecture overview
description: Goals, non-goals, request path and technology stack of mqtt-lens.
status: draft
tags: [architecture, overview]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:25:00Z
x-mqttlens-source: docs/DESIGN.md §1, §3
---

# Overview

Status: DRAFT v3 for review (2026-11-24). Elixir + Phoenix LiveView. No implementation yet.
(v1 was a Rust + TypeScript design. It was replaced on 2026-11-24.)
How we build it: [development process](/process/overview.md).

mqtt-lens is a web UI to look at MQTT topics and messages, like AKHQ for Kafka.
It runs in Kubernetes. Users log in with OIDC. The reference setup is Keycloak, which
brokers a corporate IdP (for example Entra ID).
**It is exposed to the public internet with no IP allow-list. Security is the first design goal.**

**This is a personal, generic open project.** The repository contains no employer names,
hostnames, IP addresses, realm names or other deployment details. A deployment keeps its
own values (OIDC issuer, realm, groups, broker host) in its own deployment repository.

# Goals and non-goals

## MVP goals

1. OIDC login (Authorization Code + PKCE) against Keycloak.
2. Role-based visibility: a user sees only the topics that their groups allow.
3. Topic tree with message counts, last message, and a short history per topic.
4. Live updates of new messages for the selected subtree.
5. Payload view as text, pretty JSON, or hex.
6. One broker for each deployment.
7. **Read-only.** The MVP has no publish feature. There is no publish code in the release.
8. Container image (amd64 + arm64), Kubernetes manifests, health and metrics endpoints.

## Not in the MVP (later stages)

- Publish (stage 2: role check, audit log, broker ACL).
- More than one broker (stage 3).
- Search in history, export, payload decoders.
- High availability (more than one replica, Erlang clustering).
- OIDC back-channel logout.

## Non-goals

- Broker administration (clients, listeners, rules). Use the EMQX dashboard for this.
- Long-term message storage. Use Kafka or a database for this.
- User-defined broker connections. **The operator configures brokers. Users cannot
  enter a host.** (MQTT Explorer lets users enter a host. On a public service, that
  gives an attacker an SSRF path into the cluster network.)

# Architecture

```
Internet
   │ HTTPS + WSS (TLS at Traefik, cert-manager certificate)
   ▼
Traefik Gateway ── HTTPRoute ── rate-limit middleware only (no IP allow-list)
   │ HTTP :4000 (cluster network only)
   ▼
mqtt-lens pod (one replica, one BEAM node, distribution OFF)
   │
   ├─ MqttLensWeb.Endpoint      :4000  router, LiveView socket, static assets
   ├─ MqttLensWeb.OpsEndpoint   :9090  /healthz, /readyz, /metrics (not routed)
   │
   └─ Application supervisor (see supervision tree)
```

The process tree below the pod is in [supervision tree](/architecture/supervision-tree.md).

# Stack

| Part | Choice | Reason |
|---|---|---|
| Language | Elixir 1.20.5 on Erlang/OTP 28.5.0.8 (pinned in `.tool-versions`; S0-tested) | Type inference for all constructs; memory-safe VM. |
| Web | Phoenix 1.8.17 + LiveView 1.2.15 on Bandit 1.15 (S0-tested; pinned in `mix.lock`) | Server-rendered live UI, no public JSON API, HEEx auto-escaping. `compile --warnings-as-errors` is clean on 1.20.5. |
| Generator | `mix phx.new mqtt_lens --no-ecto --no-mailer --no-gettext --no-dashboard`, then remove daisyUI | No database, no mailer, no LiveDashboard. daisyUI is a git dependency from GitHub that we do not need. |
| OIDC | `oidcc` 3.9 + `oidcc_plug` 0.5 (Erlang Ecosystem Foundation) | OpenID-certified. PKCE, nonce, claim and signature checks. (Not yet compiled on 1.20 — step 3 checks it.) |
| MQTT | `emqtt` 1.16.2 (EMQ) with `BUILD_WITHOUT_QUIC=1` **and** `{:quicer, ">= 0.0.0", only: :never_env, override: true}` | S0: the env var alone is not enough — Mix still compiles `quicer` (msquic, C). With the override, `_build` contains no `.so` file. CI fails if any `.so` appears in `_build`. Other deps: `gun`, `cowlib`, `getopt`. |
| JSON | Built-in `JSON` module for decoding (string keys); `Jason` (already a Phoenix dependency) for pretty print | No atoms from payloads. |
| Rate limit | `hammer` with the ETS backend | Per-IP and per-session limits. |
| Client IP | `remote_ip` with a trusted-proxy list | Correct client IP behind Traefik only. |
| Logs | `logger_json` | Structured JSON logs. |
| Metrics | Open (step 1): `telemetry_metrics_prometheus_core` had its last release in 2024-03. Compare with a maintained exporter, or write a small exporter (telemetry handlers + ETS + text format, ~150 lines). | Prometheus text format on the ops endpoint. |
| CSS / JS build | Tailwind 4.3.3 (GitHub release) and esbuild 0.25.4 (npm registry) standalone binaries, through the `tailwind` / `esbuild` Hex packages | No npm dependency tree. CI checks the SHA-256 of both binaries against values committed in the repo. `heroicons` is a git dependency: pin it by commit SHA, not by tag. |

# Citations

1. [Threat model](/architecture/threat-model.md)
2. [Supervision tree](/architecture/supervision-tree.md)
3. [Development process](/process/overview.md)
