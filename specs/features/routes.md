---
type: feature
title: Routes and LiveViews
description: Route table, authentication per route, and the live_session rule.
status: draft
tags: [routes, liveview]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §4.4
---

# Routes and LiveViews

| Route | Auth | Notes |
|---|---|---|
| `/auth/login`, `/auth/callback` | none | Rate-limited per IP. |
| `/auth/logout` | session | DELETE with CSRF token. |
| `/` (LiveView `TopicsLive`) | session | Tree, topic detail, live updates. |
| `/live` (LiveView socket) | session | `check_origin` on. Session from `connect_info`. |
| `/assets/*` | none | Static, digested files only. |
| `/healthz`, `/readyz`, `/metrics` | none | `OpsEndpoint` on port 9090 only. Not in the HTTPRoute. |

All other paths: 404. No JSON API. No LiveDashboard. No `/dev/*` routes in the release.

All LiveViews are in one `live_session :authenticated` with
`on_mount: [{MqttLensWeb.Auth, :require_session}]`. A LiveView outside this `live_session`
is a CI failure (a test lists the router's live routes).

# Citations

1. [Threat model](/architecture/threat-model.md)
