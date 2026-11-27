---
type: process
title: Roles
description: Roles, what each role does and never does, and how the limits are enforced.
status: draft
tags: [process, roles]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DEVELOPMENT.md §2
---

# Roles

| Role | Who | Does | Never does |
|---|---|---|---|
| **Owner** | The human (`BillyGrande`) | Approves intents and specs. Decides each merge (H3): gives the word for a PR or a batch, or merges by hand. Approves releases (H5) and gives the security sign-off (H4). Answers `needs-human` issues. | — |
| **Orchestrator** | The main Claude session (Opus) | Talks with the owner. Records intents as epics. Splits work into tasks. Picks ready tasks and dispatches agents. Reads agent results from beads. Runs the rebase merge (`gh pr merge <n> --rebase`) on the owner's word for that PR or batch ([0012](/decisions/0012-merge-on-owner-word.md)). Reports status. | Write code, tests or spec content. Review diffs. Run tests. Merge without the owner's word. Merge with a method other than rebase. Release or tag. |
| **architect** | Agent, Opus | Drafts and updates specs and decisions from an epic. Marks concerns and open questions. | Write code. Approve its own spec. |
| **test-author** | Agent, Sonnet (Opus for `security` tasks) | Writes failing tests from the acceptance criteria. Commits them first. | Write implementation code. |
| **implementer** | Agent, Sonnet | Makes the tests pass in its own worktree. For UI tasks: implement → screenshot → compare → adjust (max 3 rounds). Opens the PR. | Change the test-author's tests. Merge. |
| **verifier** | Agent, Sonnet, fresh context, tools `Bash`, `Read` | Runs `make check` and `make integration`. Checks each acceptance criterion. "Do not fix anything; report only." | Edit files. |
| **reviewer** | Agent, Opus, fresh context | Reviews the PR with `REVIEW.md` ([REVIEW.md](/process/guardrails.md)): Bugs, Security, Compliance. Records findings. | Edit files. Approve or merge. |
| **security-reviewer** | Agent, Opus, fresh context | Reviews against the threat model for every `security` task, and does the H4 review. | Edit files. |
| **spec-keeper** | Agent, Sonnet | After a merge, updates the as-built specs and their OKF trust fields. | Change behaviour. |
| **scout** | Agent, Haiku | Lookups: Hex versions, hexdocs, changelogs, CVEs. Writes the answer into the issue. | Edit files. |

The rows from architect to scout are the role agents. Role agents never merge, release or tag. The main session without an agent file has the same merge rule as the orchestrator ([0012](/decisions/0012-merge-on-owner-word.md)).

The agent definitions go in `.claude/agents/<role>.md`. S0 confirmed how to enforce the role limits:

| Control | Mechanism (Claude Code docs, S0) |
|---|---|
| Tools per role | Frontmatter `tools:` / `disallowedTools:`. The verifier, reviewers and scout get no `Edit` and no `Write`. |
| Paths per role | One script `.claude/hooks/guard.sh` on PreToolUse. The hook input has **`agent_type`** (the role name) and `agent_id`. The script has one table: role → allowed write paths. Only `architect` and `spec-keeper` write in `specs/`; only `test-author` and `implementer` write in `lib/`, `test/`, `assets/`, `config/`. |
| Read-only check | `.claude/hooks/readonly-check.sh` on `SubagentStart` and `SubagentStop`. The roles `verifier`, `reviewer`, `security-reviewer` and `scout` have `Bash`, and `guard.sh` checks only the Edit and Write tools. At start, the hook saves the HEAD and `git status` of the `cwd`. At stop, it compares them. If a file changed or a commit was made, it blocks the stop (exit 2) and names the changed paths. A missing snapshot or bad input also blocks. On a second stop with changes (`stop_hook_active=true`), the hook allows the stop (no loop), keeps the snapshot, prints a warning and writes `<git-common-dir>/mqtt-lens-ro/<agent_id>.violation` (role, time, problems). The orchestrator looks for these files ([session start](/process/orchestrator.md)). Other roles are not blocked. This control detects the change after the fact. It does not prevent it. |
| Merge | `bash-policy.sh` and `guard.sh` on PreToolUse. Every role agent (any `agent_type` other than `orchestrator`) is blocked from `gh pr merge`. The main session (no `agent_type`) and the orchestrator can run only `gh pr merge <n> --rebase`. The owner's word is a written rule, not a hook ([0012](/decisions/0012-merge-on-owner-word.md)). |
| Role-only hooks | Frontmatter `hooks:` (they run only while that agent runs). Used for the test-tamper check of the implementer. |
| Worktrees | Frontmatter `isolation: worktree` for `test-author`, `implementer`, `verifier`, `reviewer` and `security-reviewer`. The three read-only roles start with `git fetch origin task/<id>` and `git checkout --detach origin/task/<id>` in their own worktree. So they never change the branch or the files of the main checkout. Agent worktrees are in `.claude/worktrees/` (git-ignored). Project settings and hooks come from the main checkout. A worktree with changes stays until cleanup, so the orchestrator removes it after merge. The branch name is not documented, so the agent creates `task/<issue-id>` itself. |
| Result required | `SubagentStop` hook: it reads the task ID from the agent's last message (`TASK: <id>`) and blocks the stop (exit 2) until a `RESULT:` comment exists on that issue. |
| Model | Frontmatter `model:` (Opus / Sonnet / Haiku per [roles](/process/roles.md) table). |

For this project only, this replaces the global rule "the main session keeps review and
verification". The project `CLAUDE.md` states this.

# Citations

1. [Guardrails](/process/guardrails.md)
2. [Merge on the owner's word](/decisions/0012-merge-on-owner-word.md)
