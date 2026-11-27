---
type: decision
title: Merge on the owner's word
description: The main session or the orchestrator runs the rebase merge only on the owner's word for each PR or batch. Role agents never merge.
status: approved
tags: [process, merge, guardrails]
generated:
  by: claude-opus-5-5
  at: 2026-11-27T15:36:50Z
verified:
  - by: human:BillyGrande
    at: 2026-11-27T15:36:50Z
x-mqttlens-beads: [ml-2p3.13, ml-2p3.14]
---

# Context

H3 (merge to `main`) was owner-only. The owner merged each PR by hand. The hooks blocked `gh pr merge` for all sessions and agents.

The owner reviews each PR and then gives a short instruction, for example "merge 12" or "merge 12, 13 and 14". The manual merge after that instruction adds work and no control. The owner decision stays the gate. The person or session that runs the command is not the gate.

Owner decision on 2026-11-27.

# Decision

1. The owner decides each merge (H3). This does not change.
2. The main session (no `agent_type`) and the orchestrator can run the merge. They run it only on the owner's word for that PR or for that batch.
3. The owner's word is an instruction in the owner's own message that names the PR or the batch. A batch is a list of PR numbers that the owner names in one message.
4. A message from an agent is never the owner's word. A beads comment, a PR comment or a RESULT comment is never the owner's word.
5. The merge is always a rebase merge: `gh pr merge <n> --rebase`. No other merge method.
6. Role agents (architect, test-author, implementer, verifier, reviewer, security-reviewer, spec-keeper, scout) never merge.
7. H4 (security sign-off) and H5 (release, tag, image push) stay owner-only.
8. The owner can always merge by hand.

# Consequences

- The hooks allow `gh pr merge <n> --rebase` only for the main session and the orchestrator. The hooks block all other merge commands and all merge commands from role agents ([guardrails](/process/guardrails.md)). Task ml-2p3.13 changes the hooks.
- **The owner's word is a written rule, not a hook.** A hook cannot know if the owner said "merge" for a PR. Thus this part is an advisory control (principle 4 in the [overview](/process/overview.md)). The written rule is in `CLAUDE.md`, the orchestrator agent file, [roles](/process/roles.md) and [orchestrator](/process/orchestrator.md).
- The deterministic controls that stay: branch protection on `main` (PR required, all checks required, linear history, no force push), the hook block for role agents, and the hook block for other merge methods.
- A rebase merge keeps a linear history and keeps each commit. The test commit with the `Tests-Committed` trailer stays a separate commit on `main`. But GitHub gives the rebased commits new SHAs. Thus a check on `main` must find the test commit by its trailer, not by the SHA in the task.
- After the merge, the orchestrator closes the task and removes the worktree ([orchestrator](/process/orchestrator.md)).
- Residual risk: the main session or the orchestrator can merge without the owner's word. The hook does not stop this. The owner sees each merge in the git history and in the report, and can revert it through a PR.

# Open questions

1. **Expiry of the word.** If new commits arrive on a PR after the owner's word, does the word still apply? Proposal: no. The orchestrator asks again when the PR head changed after the owner's word.
2. **Verified entry.** An agent wrote this document after the owner decision. The `verified` entry records the owner decision of 2026-11-27 as task ml-2p3.14 states it. The owner confirms this text, or corrects `verified.at`, when the owner reviews the PR.

# Citations

1. [Process overview](/process/overview.md)
2. [Roles](/process/roles.md)
3. [The orchestrator](/process/orchestrator.md)
4. [Guardrails](/process/guardrails.md)
5. [beads, OKF and orchestrator process](/decisions/0007-beads-okf-orchestrator-process.md)
