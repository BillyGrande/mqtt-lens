---
type: decision
title: No IP allow-list
description: The app is public from the first deployment with no IP allow-list.
status: draft
tags: [security, exposure]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md header, §8.2, §14 (D2)
---

# Context

mqtt-lens is exposed to the public internet. Security is the first design goal.

# Decision

D2: No IP allow-list. The app is public from the first deployment. The security review is a hard gate: no public route exists before it passes.

# Consequences

- A Traefik rate-limit middleware is still recommended in front of `/auth/*`.
- The security review ([MVP plan](/architecture/mvp-plan.md), step 7) is a hard gate before the first public route exists.

# Citations

1. [Deployment](/architecture/deployment.md)
2. [MVP plan](/architecture/mvp-plan.md)
