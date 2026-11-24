---
type: decision
title: Public repository and personal accounts
description: The repository is public on the personal GitHub account, with GHCR, Apache-2.0 and a noreply git identity.
status: draft
tags: [repo, licence, process]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md header, §14 (D3); docs/DEVELOPMENT.md §1, §12 (P2, P3, P4, P6)
---

# Context

mqtt-lens is a personal, generic open project. The repository contains no employer names, hostnames, IP addresses, realm names or other deployment details. A deployment keeps its own values (OIDC issuer, realm, groups, broker host) in its own deployment repository.

# Decision

D3: Public repository on the personal GitHub account, GitHub Actions CI, image in GHCR under the personal account, licence Apache-2.0. No employer resources.

P2: GitHub repository: public from the start, under `BillyGrande`.

P3: Image registry: GHCR under the personal account.

P4: Git identity: `BillyGrande` with the GitHub noreply e-mail address.

P6: Licence: Apache-2.0.

# Consequences

Public from day one, so no employer data anywhere. The code, specs, issues and commits contain no employer names, hosts, IPs, realms or tickets. See [guardrails](/process/guardrails.md) for the employer-identifier scan.

# Citations

1. [Process principles](/process/overview.md)
2. [Guardrails](/process/guardrails.md)
3. [beads server mode and private remote](/decisions/0008-beads-server-mode-private-remote.md)
