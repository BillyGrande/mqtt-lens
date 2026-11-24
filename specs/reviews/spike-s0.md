---
type: review
title: Spike S0
description: Status and results of Spike S0.
status: draft
tags: [spike, s0]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DEVELOPMENT.md §11
---

# Spike S0

| # | Item | Status (2026-11-24) |
|---|---|---|
| 1 | Toolchain: OTP 28.5.0.8 + Elixir 1.20.5 (asdf, ~15 min build, no missing packages), `bd` 1.3.4, `dolt` 2.7.6 | **Done** |
| 2 | beads concurrency with worktrees | **Done** — server mode ([beads setup](/process/beads.md)) |
| 3 | `bd` syntax | **Done** — [bd command reference](/process/beads.md) |
| 4 | Hook identification of subagents | **Done** — `agent_type` ([roles](/process/roles.md)) |
| 5 | `emqtt` without QUIC | **Done** — needs the `quicer` override ([architecture overview](/architecture/overview.md)) |
| 6 | Split DESIGN.md and this file into `specs/` ([OKF layout](/process/okf-specs.md)) | Open — after the owner approves this v3 |
| 7 | Git identity (`BillyGrande`, `23191012+BillyGrande@users.noreply.github.com`), employer deny-list outside the repo, public code repo + private beads repo (P7), branch protection, security settings ([GitHub settings](/process/guardrails.md)) | Open — needs owner confirmation (outward-facing) |
| 8 | `bd metrics off` | Open — owner action |
| 9 | Minimal `bd init --server` in the real repo ([beads setup](/process/beads.md) row "bd init") | Open — after 7 |

The spike sandboxes (Phoenix probe app, beads test repos) are in the session scratchpad. They are
throw-away and are not part of the project.

# Citations

1. [beads setup results](/process/beads.md)
2. [Roles and enforcement](/process/roles.md)
3. [emqtt without QUIC](/decisions/0004-emqtt-without-quic.md)
4. [Toolchain versions](/decisions/0009-toolchain-versions.md)
