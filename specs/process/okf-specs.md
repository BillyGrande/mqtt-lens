---
type: process
title: OKF specs
description: OKF format and layout of the specs/ source of truth.
status: draft
tags: [process, okf, specs]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:25:00Z
x-mqttlens-source: docs/DEVELOPMENT.md §5
---

# specs/ (OKF source of truth)

## Format

A minimal OKF bundle (OKF 0.3, current on 2026-11-24). Only `type` is required. We also use the trust fields:

```markdown
---
type: feature
title: OIDC login
description: Authorization Code + PKCE login against the configured OIDC provider.
status: approved            # draft | approved | stable | deprecated
tags: [auth, security]
generated:
  by: claude-opus-5-5
  at: 2026-11-24T12:00:00Z
verified:
  - by: human:BillyGrande
    at: 2026-11-24T15:00:00Z
x-mqttlens-beads: [ml-a3f8]
---

# Behaviour
...
# Acceptance
...
# Citations
1. [Threat model](/architecture/threat-model.md)
```

- `status` = the place in the loop. `verified` by `human:BillyGrande` = owner approval;
  by `process:ci` = CI confirms the as-built state. Only a `verified` entry at or after `generated.at` counts.
- Links are absolute from the bundle root.
- `specs/index.md` lists all documents. The orchestrator reads only this file at session start.
- `specs/log.md` records dated changes, newest first.

## Layout

```
specs/
  index.md
  log.md
  architecture/  index, overview, threat-model, supervision-tree, resource-safety, deployment,
                 supply-chain, observability, testing, code-layout, mvp-plan
  features/      index, oidc-login, sessions, authorization, web-security, broker-ingest, routes
  decisions/     index, 0001-elixir-phoenix-liveview, 0002-websocket-not-sse, 0003-no-trusted-types,
                 0004-emqtt-without-quic, 0005-no-ip-allow-list, 0006-public-repo,
                 0007-beads-okf-orchestrator-process, 0008-beads-server-mode-private-remote,
                 0009-toolchain-versions, 0010-oidc-provider-deployment-value,
                 0011-reference-broker-emqx, 0012-merge-on-owner-word
  process/       index, overview, roles, orchestrator, beads, okf-specs, guardrails, evals,
                 repo-layout, environments-release-maintain
  reviews/       index, spike-s0; security-review-<n>.md (created later)
  lessons/       post-mortems (type: lesson; created later)
```
