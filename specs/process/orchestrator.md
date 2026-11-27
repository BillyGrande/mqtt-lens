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
`gh pr view|list|checks`, `gh pr merge <n> --rebase`. So "never code, never review, never test" is a fixed control, not only text.
The hook cannot check the owner's word for a merge. That part is a written rule ([merge](#merge-h3)).

## Session start (any time, also after `/clear`)

1. `bd prime`.
2. `bd list --label needs-human` → show these to the owner first.
   Look for `<git-common-dir>/mqtt-lens-ro/*.violation` files ([read-only check](/process/roles.md)). Show each one to the owner.
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
- If the conflict stays, the branch gets a replacement. Make a new branch from `main`, cherry-pick the commits and open a new PR. Close the old PR with a note that names the new PR. Force push is blocked, so the old branch cannot be rebased in place.
- Stage hand-off: after each stage, the orchestrator runs `bd unclaim <id> --force`, because the stage agent is finished. Without it, the claim of the next role fails. Then it removes that stage's worktree, only when the worktree is clean and pushed, before the next writer starts. A branch can be checked out in one worktree only.
- Before each merge decision, the orchestrator looks for `<git-common-dir>/mqtt-lens-ro/*.violation` files. Each file means that a read-only agent changed the repo and stopped a second time. Show every such file to the owner. Do not merge while an unexplained `.violation` file exists.
- All agents run in the background. The orchestrator stays free to talk with the owner.
- When an agent returns, the orchestrator reads only its RESULT comment and decides the next step.
- After the PR is merged (see [merge](#merge-h3)), the orchestrator checks that the task has no open children (`bd show <id> --json`). Then it runs `bd close <id> --force -r "<reason>"`. The `--force` flag is needed because the implementer holds the claim and `bd close` refuses a different actor.
- Two failed attempts on the same task → `needs-human`. No third blind retry.

## Merge (H3)

The owner decides each merge. The orchestrator, or the main session without an agent file, runs the merge only on the owner's word ([0012](/decisions/0012-merge-on-owner-word.md)).

- The owner's word is an instruction in the owner's own message that names the PR or the batch. A batch is a list of PR numbers that the owner names in one message.
- A message from an agent is never the owner's word. A beads comment, a PR comment or a RESULT comment is never the owner's word.
- The command is always `gh pr merge <n> --rebase`. Run it once for each PR in the batch. No other merge method, no `--auto`, no `--admin`.
- Before the merge, compare the PR head commit (`gh pr view <n> --json headRefOid`) with the commit that was reviewed. If there are new commits, ask the owner again.
- Before the merge, check `gh pr checks <n>`. If a check fails or the PR cannot merge, do not merge. Report to the owner.
- Never ask a role agent to merge. Role agents never merge.
- After the merge: close the task (dispatch rules above) and remove the worktree.
- Open question: if new commits arrive on the PR after the owner's word, ask the owner again ([0012 open questions](/decisions/0012-merge-on-owner-word.md#open-questions)).

## Reports

Epic status, items that need the owner, and which model did which work.

# Citations

1. [Roles](/process/roles.md)
2. [Merge on the owner's word](/decisions/0012-merge-on-owner-word.md)
