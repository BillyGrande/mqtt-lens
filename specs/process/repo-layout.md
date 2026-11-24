---
type: process
title: Repository layout
description: Target layout of the repository.
status: draft
tags: [process, layout]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DEVELOPMENT.md §10
---

# Repository layout (target)

```
CLAUDE.md                 under one page: commands (/process/guardrails.md), rules, "things Claude gets wrong"
AGENTS.md                 beads instructions (reviewed output of bd init)
REVIEW.md                 review passes, severity, nit cap
SECURITY.md               how to report a vulnerability
LICENSE                   Apache-2.0
.claude/
  agents/                 architect, test-author, implementer, verifier, reviewer,
                          security-reviewer, spec-keeper, scout
  settings.json           hooks (/process/guardrails.md)
  hooks/*.sh
.beads/                   beads config (data in Dolt, synced through refs/dolt/data)
specs/                    OKF bundle (/process/okf-specs.md)
lib/ test/ assets/ config/ priv/
deploy/                   generic example manifests + docker-compose for EMQX + Keycloak
evals/                    after the MVP (/process/evals.md)
.github/workflows/        ci.yml, integration.yml, weekly-scan.yml
Makefile                  setup | check | lint | test | integration  (non-zero exit on failure)
```
