---
type: process
title: The orchestrator
description: Enforcement, session start, dispatch rules and reports.
status: draft
tags: [process, orchestrator]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DEVELOPMENT.md §6
---

# The orchestrator

## Enforcement

The owner starts the project with **`claude --agent orchestrator`**. This applies the
`orchestrator` agent file to the main session: tools `Agent`, `Read`, `Bash`, `AskUserQuestion`
only — no `Edit`, no `Write`. `guard.sh` allows the orchestrator (`agent_type = orchestrator`)
only these Bash commands: `bd *`, `git status|log|worktree list|worktree remove`,
`gh pr view|list|checks`. So "never code, never review, never test" is a fixed control, not only text.

## Session start (any time, also after `/clear`)

1. `bd prime`.
2. `bd list --label needs-human` → show these to the owner first.
3. `bd list --status in_progress` → check that their agents still run.
4. `bd ready --json` → candidates for dispatch.
5. Read `specs/index.md`. Do not read code.

The orchestrator can be cleared at any time. No compaction and no handoff files are needed.

## Dispatch rules (performance without spaghetti)

- Dispatch only tasks from `bd ready` that have the required content ([task content](/process/beads.md)).
- Each agent gets the issue ID, its role and the worktree path. Nothing more.
- The agent claims the task (`bd update <id> --claim`, without `--if-status`) before it starts. A failed claim = the agent stops and reports.
- **Parallel: up to 3 agents, at the orchestrator's choice.** Run in parallel only when the
  `Files:` lists do not overlap and the tasks are not in a dependency chain. Otherwise run in series.
- Read-only agents (verifier, reviewers, scout) can run in parallel with builders.
- Before verify, the branch is rebased on `main`. A rebase conflict → the implementer fixes it in its worktree.
- All agents run in the background. The orchestrator stays free to talk with the owner.
- When an agent returns, the orchestrator reads only its RESULT comment and decides the next step.
- After the PR is merged, the orchestrator checks that the task has no open children (`bd show <id> --json`). Then it runs `bd close <id> --force -r "<reason>"`. The `--force` flag is needed because the implementer holds the claim and `bd close` refuses a different actor.
- Two failed attempts on the same task → `needs-human`. No third blind retry.

## Reports

Epic status, items that need the owner, and which model did which work.

# Citations

1. [Roles](/process/roles.md)
