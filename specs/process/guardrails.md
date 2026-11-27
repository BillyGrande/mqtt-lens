---
type: process
title: Guardrails
description: Hooks, git hooks and CI, REVIEW.md, CLAUDE.md verification block and GitHub settings.
status: draft
tags: [process, guardrails, security]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DEVELOPMENT.md §7
---

# Guardrails

## Hooks (`.claude/settings.json` in the repo; each block explains itself)

| Hook | Rule |
|---|---|
| PreToolUse (Bash) | Block `gh pr merge` and merges through `gh api` for every role agent. Allow only `gh pr merge <n> --rebase` for the main session (no `agent_type`) and the orchestrator; block all other merge methods and flags. The owner's word for the merge is a written rule, not a hook ([0012](/decisions/0012-merge-on-owner-word.md)). Block `git push` to `main`, `git push --force`, `git reset --hard` on `main`. |
| PreToolUse (Bash) | Before `gh` or `git push`: the active gh account must be `BillyGrande`. Else block: "run `gh auth switch --user BillyGrande`". |
| PreToolUse (Bash) | Block `gh release`, `git tag` and image pushes (H5 is owner-only). |
| PreToolUse (Read/Bash) | Block reads of `.env*`, `*.pem`, `*.key`, `secrets/**`, `~/.ssh`, `~/.config/gh`. |
| PreToolUse (Edit/Write) | `guard.sh`: block writes outside the role's paths (by `agent_type`, [roles](/process/roles.md)). For `implementer`: block edits to the files that the `tests-committed` SHA added. |
| PreToolUse (Bash, orchestrator) | `guard.sh`: allow only the commands in [orchestrator enforcement](/process/orchestrator.md). |
| SubagentStop | Block the stop until the task has a `RESULT:` comment ([roles](/process/roles.md)). |
| SessionStart | `bd prime` (from beads). |
| PostToolUse (Edit/Write `lib/**`) | Fast check for `raw(`, `{:safe,`, `String.to_atom`, `keys: :atoms`. |

## Git hooks and CI

| Check | Where |
|---|---|
| Employer-identifier scan on the diff, the commit message and the beads export. The deny-list is **outside** the repo (`~/.config/mqtt-lens/denylist` + a CI secret), so the list itself is not public. | pre-commit, pre-push, CI |
| Repo-local git identity = `BillyGrande` + GitHub noreply address | pre-commit |
| Test tampering: files that the `tests-committed` SHA added are unchanged after it | CI |
| All gates from [supply chain](/architecture/supply-chain.md) (`make check`) | CI |
| Integration: EMQX 6.2.2 + Keycloak in Docker Compose (`make integration`) | CI |
| Weekly scheduled scan: `mix deps.audit`, `mix hex.audit`, `sobelow` on `main` | CI (cron) |

## REVIEW.md (repo root, read by the reviewer agents)

- Three passes, each finding tagged: **Bugs**, **Security** (threat model T1–T20), **Compliance**
  (matches the spec, the task and DESIGN principles).
- Severity: "Reserve Important for findings that would break behavior, leak data or breach a
  policy." Style and naming are nits.
- "Report at most five nits per review; summarize the rest as a count."
- Exclude what CI already enforces (format, Credo, Sobelow rules) and generated files.
- Findings do not approve or block alone. The owner decides at H3.

## CLAUDE.md verification block

```
make check        must end with "0 failures" and no warnings. Never skip or delete a failing test.
make integration  needs Docker. Must end with "0 failures".
make lint         zero warnings (format, credo --strict, sobelow).
Fix the code, not the test.
```

## GitHub (personal account `BillyGrande`, public repo)

- Branch protection on `main`: PR required, all checks required, no force push, linear history.
- No required approvals (an owner cannot approve their own PR). The owner decides each merge. The owner
  merges by hand, or the main session or the orchestrator runs the rebase merge on the owner's word
  ([0012](/decisions/0012-merge-on-owner-word.md)).
- Secret scanning + push protection, Dependabot alerts and updates, private vulnerability
  reporting, `SECURITY.md`.
- Actions: minimum `permissions:`, actions pinned by commit SHA, no secrets for PRs from forks,
  `pull_request` (never `pull_request_target`) for untrusted code.

# Citations

1. [Roles](/process/roles.md)
2. [Threat model](/architecture/threat-model.md)
3. [Merge on the owner's word](/decisions/0012-merge-on-owner-word.md)
