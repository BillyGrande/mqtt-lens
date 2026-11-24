---
type: decision
title: Elixir and Phoenix LiveView
description: The application uses Elixir and Phoenix LiveView. It replaced the v1 Rust and TypeScript design.
status: draft
tags: [stack, elixir]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md header, §3, §10
---

# Context

Version 1 of the design used Rust and TypeScript. On 2026-11-24 the design was replaced with Elixir and Phoenix LiveView (DRAFT v3).

# Decision

Use Elixir 1.20.5 on Erlang/OTP 28.5.0.8 with Phoenix and LiveView.

Reasons:

- LiveView fits: it gives a server-rendered live UI.
- HEEx escapes output by default.
- There is no public JSON API.
- OTP supervision (see the [supervision tree](/architecture/supervision-tree.md)).
- Elixir 1.20 has type inference for all constructs, and the VM is memory-safe.

# Consequences

The Rust design had one advantage: a smaller memory footprint. This design accepts a larger memory footprint. The pod memory limit is set above the byte budget plus the VM baseline (see [resource safety](/architecture/resource-safety.md)).

# Citations

1. [Architecture overview](/architecture/overview.md)
2. [Toolchain versions](/decisions/0009-toolchain-versions.md)
