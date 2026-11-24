---
type: decision
title: Toolchain versions
description: The toolchain versions come from Spike S0.
status: draft
tags: [toolchain, versions]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §3, §14 (D6)
---

# Context

Spike S0 item 1 tested the toolchain: OTP 28.5.0.8 and Elixir 1.20.5 built with asdf in about 15 minutes, with no missing packages.

# Decision

D6: Toolchain from S0: OTP 28.5.0.8, Elixir 1.20.5, Phoenix 1.8.17, LiveView 1.2.15, Bandit. Built locally with asdf. CI uses the same versions.

# Consequences

Versions are pinned in `.tool-versions` and `mix.lock`. `compile --warnings-as-errors` is clean on 1.20.5.

# Citations

1. [Architecture overview](/architecture/overview.md)
2. [Supply chain](/architecture/supply-chain.md)
