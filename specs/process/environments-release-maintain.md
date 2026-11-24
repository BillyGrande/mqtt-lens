---
type: process
title: Environments, release and maintain
description: Agent autonomy per environment, rollback and maintain loop.
status: draft
tags: [process, release, maintain]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DEVELOPMENT.md §9
---

# Environments, release and maintain

| Environment | Agent autonomy |
|---|---|
| Local (Docker Compose: EMQX 6.2.2 + Keycloak) | Free: agents start, stop and reset it. |
| CI | Agents read results. Changes only through PRs. |
| Release (GHCR image) | **Owner only (H5).** Agents prepare the changelog and a release PR. |
| Deployment (a cluster, from its own deployment repo) | Out of scope for this repo. The owner deploys. |

- **Rollback is the most rehearsed path:** immutable versioned images, the deployment pins a
  digest, rollback = point the deployment to the previous digest. Test it before the first public route.
- **Maintain (after the first deployment):** the app exports metrics ([observability](/architecture/observability.md)). Later, a
  `bands.yaml` with one metric first (for example login failures or 5xx rate), rolling baseline:
  1σ → log; 2σ → read-only diagnosis by an agent; 3σ → the agent may only open a PR or a pre-approved
  runbook. A breach becomes a new epic.
- Metrics of the process: first-pass CI success, time to first review, findings fixed without the
  owner, change failure rate, escaped defects.

# Citations

1. [Observability](/architecture/observability.md)
