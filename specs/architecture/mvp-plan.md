---
type: architecture
title: MVP plan
description: Ordered build steps for the MVP, with the security review as a hard gate.
status: draft
tags: [plan, mvp]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §13
---

# MVP plan

1. Skeleton: `phx.new` with the flags in [architecture overview](/architecture/overview.md), `.tool-versions`, config validation, security
   headers, ops endpoint, release with distribution off, CI gates ([supply chain](/architecture/supply-chain.md)).
2. `Authz` matcher + `Scope` + property tests.
3. OIDC login, flows, sessions, socket lifetime + auth tests, against Keycloak in Docker.
4. `Broker` + `Store` + `Dispatcher` + limits + resource tests, against EMQX in Docker.
5. `TopicsLive`: tree, topic detail, live updates, payload views + LiveView and XSS tests.
6. Image (amd64 + arm64), manifests, NetworkPolicies.
7. Security review (Opus reviewer agent + human sign-off). **Hard gate: no public route before it passes.**
8. First deployment (public, Keycloak login only).
