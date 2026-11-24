---
type: decision
title: beads, OKF and orchestrator process
description: Agents work through beads issues, OKF specs and an orchestrator that never writes code.
status: draft
tags: [process, beads, okf]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DEVELOPMENT.md header, §1, §12 (P1, P5)
---

# Context

Humans and Claude agents build mqtt-lens. The process combines the AI-native SDLC playbook (a loop of six stages: Plan, Design, Build, Test, Deploy, Maintain) and the orchestrator + issue-database pattern.

# Decision

P1: Issue database: beads.

P5: Parallel agents: up to 3, at the orchestrator's choice, only for tasks with no shared files.

The main session only orchestrates. It never writes code, never reviews and never tests. beads (`bd`) is the communication channel between agents and replaces handoff files. A `specs/` folder in OKF is the source of truth for what the system is.

# Consequences

S0 verdict: beads fits, with the constraints in [beads](/process/beads.md). No switch to handoff files. For this project only, the rule replaces the global rule "the main session keeps review and verification". The project `CLAUDE.md` states this.

# Citations

1. [Process overview](/process/overview.md)
2. [Orchestrator](/process/orchestrator.md)
3. [OKF specs](/process/okf-specs.md)
