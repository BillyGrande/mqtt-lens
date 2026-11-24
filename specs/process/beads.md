---
type: process
title: beads issue database
description: Setup results of Spike S0, issue structure, labels, task content and command reference.
status: draft
tags: [process, beads]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:25:00Z
x-mqttlens-source: docs/DEVELOPMENT.md §4, §11.1
---

# beads (issue database)

## Setup (S0 results, 2026-11-24)

**Verdict: beads fits, with the constraints below.** No switch to handoff files.

| Topic | S0 result | Decision |
|---|---|---|
| Version | `bd` 1.3.4, SHA-256 matches the release `checksums.txt`. `dolt` 2.7.6 (no `checksums.txt`; checked against the GitHub asset digest only). | Pin both versions. Upgrades only through a chore task. |
| Mode | 3 parallel writers × 90 operations: 0 errors, 0 lost writes in both modes. Embedded 116 s, **server 49 s**. `bd list --json` 0.42 s vs **0.22 s**. | **Server mode** (`bd init --server`): a managed `dolt sql-server` on **127.0.0.1 only**, random port. |
| Worktrees | All worktrees resolve to the main checkout's `.beads` with no setup. | Agents in worktrees use `bd` directly. |
| Claim | 3 parallel `--claim` on one issue: exactly 1 winner (3 of 3 runs). Losers exit 1. | Agents claim with `bd update <id> --claim --if-status open`. A failed claim = stop, report to the orchestrator. |
| Identity | The claim assignee comes from `BEADS_ACTOR`, else git `user.name`. | Each agent runs with `BEADS_ACTOR=<role>` (for example `implementer`). |
| Reading | `bd list --json` has no description and no comment text. | Agents and the orchestrator use `bd show <id> --json` and `bd comments <id> --json`. |
| `bd init` | The default writes 19 files: `CLAUDE.md`, `AGENTS.md`, `.claude/settings.json`, `.codex/*`, `.cursor/*`, `.agents/skills/*`, 5 git hooks. It sets `core.hooksPath=.beads/hooks`, which replaces other git hooks. | Init in a sandbox first. Keep only `.beads/` config and the `bd prime` SessionStart hook. Delete Codex, Cursor and `.agents` files. We own `CLAUDE.md`. Our hooks live in `.githooks/` and call the beads hook scripts (one `core.hooksPath`). |
| Telemetry | **On by default.** Sends command name, version, OS and a machine ID to `gastownhall-eventsapi.com`. Dolt has its own event flush. | Owner runs `bd metrics off` once. All agents also get `DO_NOT_TRACK=1` and `DOLT_DISABLE_EVENT_FLUSH=1` (env in `.claude/settings.json`). |
| Sync | `bd dolt push` writes `refs/dolt/data` **and** a branch `__dolt_remote_info__` to the remote. Dolt keeps full history, so text that is later removed stays in the pushed history. | **Beads data goes to a separate private repo** (P7, confirmed by the owner on 2026-11-24), not to the public code repo. The employer-identifier scan still runs on `bd export` before each `bd dolt push`. |
| Size | ~15 MB `.beads` after ~95 issues and ~300 writes. | Acceptable. `.beads/dolt` stays git-ignored. |

## Structure

- **Epic** = one intent. The MVP is 9 epics ([MVP plan](/architecture/mvp-plan.md) steps 1–8, plus Spike S0), linked with `blocks` dependencies.
- **Task** = one unit that one agent finishes in one context: at most about 300 changed lines, one PR.
- **Bug**, **chore**, **spike** (time-boxed research; result = a decision).
- **Finding** = a review result, a child of the task, with label `important` or `nit`.

## Labels

| Label | Meaning |
|---|---|
| `needs-human` | Waits for an owner decision. The orchestrator shows these first. |
| `approved` | The owner approved this epic or spec (H1, H2). |
| `security` | Touches auth, authz, display, router, endpoint or deploy. A security-reviewer pass is required. |
| `ui` | Needs the screenshot loop and a browser check. |
| `tests-committed` | The test-first commit exists. The SHA is in the task. |
| `important` / `nit` | Review finding severity. |

## Required content of a task

```
Spec:         /features/oidc-login.md#callback      (link to the spec section)
Goal:         one sentence
Files:        lib/mqtt_lens/auth/oidc.ex, test/mqtt_lens/auth/oidc_test.exs
Acceptance:   numbered, measurable criteria ("all tests in test/mqtt_lens/auth pass")
Verify:       make check && mix test test/mqtt_lens/auth
Out of scope: what the agent must not touch
```

Agents write their result as one comment:

```
RESULT: pass | fail
Commits: <sha> ...
Ran: <command> → <last lines of literal output>
Criteria: 1 pass, 2 pass, 3 fail (<reason>)
Follow-ups: <new issue ids>
```

## `bd` command reference (S0-tested, bd 1.3.4)

| Need | Command |
|---|---|
| Epic | `bd create "Title" -t epic -d "..." --acceptance "..." -l security` |
| Task under epic | `bd create "Title" -t task --parent <epic> -d "..." --design "..." --acceptance "..." -l ui` |
| Dependency | `bd dep add <blocked> <blocker>` |
| Ready work | `bd ready --json` (`-l <label>` to filter) |
| Claim | `bd update <id> --claim --if-status open` |
| Full text | `bd show <id> --json`; `bd comments <id> --json` |
| Result | `bd comment <id> --file result.txt` (or `--stdin`) |
| Labels | `bd update <id> --add-label x --remove-label y` |
| Close | `bd close <id> -r "reason"` |
| Export for scan | `bd export -o /tmp/<file>.jsonl` |
| Sync | `bd dolt push` / `bd dolt pull`; new clone: `bd bootstrap` |

# Citations

1. [Spike S0 review](/reviews/spike-s0.md)
2. [beads server mode and private remote](/decisions/0008-beads-server-mode-private-remote.md)
