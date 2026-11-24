---
type: process
title: Agent evals
description: Plan for continuous agent evals after the MVP.
status: draft
tags: [process, evals]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DEVELOPMENT.md §8
---

# Agent evals (after the MVP)

The playbook's continuous evals check that changes to `CLAUDE.md`, `.claude/**` or `REVIEW.md`
do not make the agents worse.

- `evals/*.json`: 5–10 real tasks from this project at first (later 20–50), each with a prompt and checks.
- `evals/check.sh`: runs the checks on the result.
- `.github/workflows/agent-evals.yml`: on PRs that touch `CLAUDE.md`, `REVIEW.md` or `.claude/**`,
  and nightly. It runs `claude -p` with a minimal tool allow-list.
- Cost: this needs an API key as a repository secret and has a running cost. **Owner decision when
  the MVP is done.** Until then, the same tasks run by hand after process changes.
- Each production incident becomes a permanent eval and a regression test.
