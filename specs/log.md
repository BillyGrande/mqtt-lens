# Log

## 2026-11-27

- Documented the controls from the dry run (ml-2p3.15). Orchestrator file and spec: the `<git-common-dir>/mqtt-lens-ro/*.violation` check at session start and before each merge decision, the stage hand-off (`bd unclaim <id> --force`, then remove the stage worktree), the replacement branch and PR after a rebase conflict (force push is blocked), and the PR head check before a merge. `roles.md`: `isolation: worktree` and the detached checkout for verifier, reviewer and security-reviewer, and the `.violation` file on a second stop. `beads.md`: every task has a `Verify` line, criteria must be checkable on the PR, loop outcomes go to the epic. `.gitignore`: `.claude/worktrees/`. No `status` or `generated` field changed.

- Dry run of the loop (ml-2p3.6, PR #14). One trivial task went through test-author, implementer, verifier, reviewer, owner merge and spec-keeper. `priv/dry_run/hello.sh` prints `mqtt-lens ok` and exits 0. `test/dry_run/hello_test.sh` checks it. Both files are throw-away; M2 removes `test/dry_run` and `priv/dry_run`. The test-tamper guard blocked the implementer's edit of the test file. Process findings: ml-2p3.11 (missing Tests-Committed trailer), ml-2p3.6.1 (script not executable), ml-2p3.6.2 (test does not check stderr), ml-2p3.6.3 (no CI checks on the PR). No other spec changed. No `status` or `generated` field changed.
- Added decision 0012 [merge on the owner's word](/decisions/0012-merge-on-owner-word.md) (ml-2p3.14). The owner decides each merge (H3). The main session or the orchestrator runs the rebase merge only on the owner's word for that PR or batch. Role agents never merge. H4 and H5 stay owner-only. The owner's word is a written rule, not a hook. Updated principle 3 and the H3 row in the overview, the owner and orchestrator rows and the merge control in roles, the orchestrator allow-list and a new merge section, the merge hook row and the GitHub merge line in guardrails, both index files, and the layout list in OKF specs.
- Fixed the `bd` commands in the process specs (ml-2p3.7). The claim command is `bd update <id> --claim` only, because `bd` rejects `--if-status` with `--claim`. Added the close step: after the merge, the orchestrator runs `bd close <id> --force -r <reason>` when the task has no open children.
- Added the repo `CLAUDE.md` (commands, rules, the override of the global review rule) and `REVIEW.md` (reviewer rules from guardrails).
- Fixed Spike S0 item 6: it shows Done 2026-11-24.

## 2026-11-24

- Closed Spike S0 items 7, 8 and 9: public repo and private beads repo created, repo-local identity, deny-list hooks in `.githooks/`, branch protection and security settings, beads in server mode with the Dolt remote on the private repo, telemetry off.
- The owner confirmed P7: beads data syncs to the private repo `BillyGrande/mqtt-lens-work`, never to the public code repo. Fixed the process principle that implied a public remote. Fixed the architecture diagram to match D2 (rate-limit middleware only, no IP allow-list).
- Specs split from `docs/` (Spike S0 item 6). The layout list in `process/okf-specs.md` now matches the tree.
- Split `docs/DESIGN.md` and `docs/DEVELOPMENT.md` into this OKF 0.3 bundle (Spike S0 item 6). All content moved without change. Status of all documents: draft. No `verified` entries yet.
