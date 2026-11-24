---
type: decision
title: beads server mode and private remote
description: beads runs in server mode with telemetry off, and syncs to a separate private repository.
status: draft
tags: [beads, process]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:25:00Z
x-mqttlens-source: docs/DEVELOPMENT.md §4.1, §12 (P7, P8)
---

# Context

S0 measured beads. 3 parallel writers x 90 operations gave 0 errors and 0 lost writes in both modes. Embedded mode took 116 s, server mode 49 s. `bd list --json` took 0.42 s in embedded mode and 0.22 s in server mode. Telemetry is on by default: it sends command name, version, OS and a machine ID to `gastownhall-eventsapi.com`, and Dolt has its own event flush. `bd dolt push` writes `refs/dolt/data` and a branch `__dolt_remote_info__` to the remote. Dolt keeps full history, so text that is later removed stays in the pushed history.

# Decision

P8: beads in server mode (`bd init --server`): a managed `dolt sql-server` on 127.0.0.1 only, random port. Telemetry off: the owner runs `bd metrics off` once, and all agents get `DO_NOT_TRACK=1` and `DOLT_DISABLE_EVENT_FLUSH=1` (env in `.claude/settings.json`).

P7 (decided: the owner confirmed it on 2026-11-24): beads data syncs to a separate private repo `BillyGrande/mqtt-lens-work`, not to the public code repo. Reason: Dolt history is permanent and the push adds an extra branch.

# Consequences

The employer-identifier scan still runs on `bd export` before each `bd dolt push`. Size: about 15 MB `.beads` after about 95 issues and about 300 writes. This is acceptable. `.beads/dolt` stays git-ignored.

# Citations

1. [beads](/process/beads.md)
2. [Spike S0](/reviews/spike-s0.md)
