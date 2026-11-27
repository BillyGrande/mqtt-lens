---
type: process
title: Development process overview
description: Sources of the process, principles and the development loop.
status: draft
tags: [process, overview]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:25:00Z
x-mqttlens-source: docs/DEVELOPMENT.md header, §1, §3
---

# Overview

Status: DRAFT v3 for review (2026-11-24). Updated with the Spike S0 results. Nothing is set up in the repo yet.

This file defines how humans and Claude agents build mqtt-lens. It combines two sources:

1. **The AI-native SDLC playbook** (claude.com, 2026-08-21): a loop of six stages —
   Plan, Design, Build, Test, Deploy, Maintain. Each stage commits an artifact that the next
   stage reads, and "the chain of commits is also the audit trail". Humans own the approval
   gates: "the agent may act up to the production gate and cannot pass it."
2. **The orchestrator + issue-database pattern:**
   - The main session only orchestrates. It never writes code, never reviews and never tests.
   - An issue database (**beads**, `bd`) is the communication channel between agents.
     It replaces handoff files.
   - A `specs/` folder in **OKF** (Open Knowledge Format) is the source of truth for what the system is.

# Principles

1. **One source of truth for each artifact.** No handoff files, no scratch notes.

   | Artifact (playbook name) | Source of truth here |
   |---|---|
   | `intent.md` (Plan) | beads **epic** (problem, outcome, users, constraints, open questions) |
   | `spec.md` (Design) | `specs/features/*.md`, `specs/architecture/*.md` (OKF) |
   | Decisions | `specs/decisions/NNNN-*.md` (OKF, type `decision`) |
   | `plan.md` (Build) | beads **tasks** under the epic (files, acceptance, verify command, dependencies) |
   | Verification evidence | beads RESULT comment + CI check run |
   | Review findings | beads **finding** issues + PR comments |
   | Post-mortems ("lessons file") | `specs/lessons/*.md` (OKF, type `lesson`) |
   | Code, tests, history | git |

2. **An agent gets an issue ID, not a long prompt.** It reads the issue and the specs that the issue links to.
3. **Humans approve. Agents prepare.** Role agents cannot merge, cannot release and cannot deploy.
   The owner decides each merge (H3). The main session or the orchestrator runs the merge only on
   the owner's word for that PR or batch, and always as a rebase merge
   ([merge on the owner's word](/decisions/0012-merge-on-owner-word.md)). H4 and H5 stay owner-only.
4. **Deterministic controls over advisory controls.** "A skill is an advisory control"; a hook is
   "the deterministic layer behind it". Rules that matter are hooks and CI checks.
5. **Fresh context for checks.** The verifier and the reviewers never share a context with the implementer.
6. **Tests first.** A test author writes the failing tests. The implementer does not change them.
   "Fix the code, not the test."
7. **Small and separate.** One task = one branch = one worktree = one PR. Parallel work only on
   tasks with no shared files. This keeps the code base clean, not spaghetti.
8. **Public from day one, so no employer data anywhere.** The code, specs, issues and commits
   contain no employer names, hosts, IPs, realms or tickets. Beads data goes only to the private repo
   `BillyGrande/mqtt-lens-work` (P7), never to the public code repo. The rule applies to the work repo
   too, because it could leak.

---

# The loop

```
 Owner + Orchestrator      architect               test-author → implementer       verifier    reviewers        Owner
 ────────────────────      ─────────               ─────────────────────────       ────────    ─────────        ─────
 1 INTENT ─ epic in bd ─►  2 SPEC (status:draft)
                │                 │
          H1 owner approves  H2 owner approves ──► 3 PLAN: tasks in bd
                                                   4 TESTS FIRST (failing, committed)
                                                   5 BUILD in worktree → PR ──────► 6 VERIFY ─► 7 REVIEW ─► H3 MERGE
                                                                                                                │
 9 MAINTAIN: breach / incident ─► new epic or bug ◄── 8 AS-BUILT: spec-keeper → status:stable ◄───────────────┘
```

| Stage | Playbook stage | Input | Output | Gate |
|---|---|---|---|---|
| 1 Intent | Plan | Owner conversation | Epic in beads | **H1** owner approves (label `approved`) |
| 2 Spec | Design | Epic | `specs/...` with `status: draft`; ADRs | **H2** owner approves → `status: approved`, `verified: human:BillyGrande` |
| 3 Plan | Build (plan mode) | Approved spec | Tasks under the epic ([task content](/process/beads.md)) | Each task links to a spec section |
| 4 Tests first | Test | Task | Failing tests in one commit; SHA in the task | The verifier confirms that they fail for the right reason |
| 5 Build | Build | Task + tests | Code in a worktree branch; PR | CI green |
| 6 Verify | Test | PR | RESULT comment: each criterion pass/fail, literal command output | All criteria pass |
| 7 Review | Deploy (PR review) | PR | Findings: `important` or `nit` (max 5 nits, rest as a count) | No open `important` finding |
| H3 Merge | Deploy | PR | Rebase merge to `main` | **Owner decides.** The main session or the orchestrator runs `gh pr merge <n> --rebase` only on the owner's word for that PR or batch ([0012](/decisions/0012-merge-on-owner-word.md)). Role agents never merge. |
| 8 As-built | — | Merged PR | Spec `status: stable` + `verified: process:ci`; tasks closed | — |
| 9 Maintain | Maintain | Bands, incidents, scans | New epic or bug; a regression test first | — |
| H4 Security sign-off | — | Security epic | `specs/reviews/security-review-<n>.md` + owner sign-off | **Before the first public route** |
| H5 Release | Deploy | Tag by owner | Signed image in GHCR | **Owner only** |

Bug rule: every bug starts with a committed failing test that shows it. Then the fix, without a change to that test.

# Citations

1. [Roles](/process/roles.md)
2. [beads](/process/beads.md)
3. [Merge on the owner's word](/decisions/0012-merge-on-owner-word.md)
