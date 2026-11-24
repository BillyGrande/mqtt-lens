---
type: decision
title: emqtt without QUIC
description: The MQTT client is emqtt built without QUIC, with a quicer override.
status: draft
tags: [mqtt, emqtt, supply-chain]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §3, §14 (D5); docs/DEVELOPMENT.md §11
---

# Context

The release must be NIF-free. `emqtt` 1.16.2 (EMQ) depends on `quicer` (msquic, C). S0 item 5 tested the build.

# Decision

D5: MQTT client is `emqtt` built without QUIC (`BUILD_WITHOUT_QUIC=1` **and** `{:quicer, ">= 0.0.0", only: :never_env, override: true}`).

S0 result: the env var alone is not enough, because Mix still compiles `quicer` (msquic, C). With the override, `_build` contains no `.so` file. NIF-free is possible only with the `quicer` override.

Fallback: `tortoise311` 0.12.3 (pure Elixir), if the override stops working.

# Consequences

CI fails if any `.so` appears in `_build`. Other `emqtt` dependencies: `gun`, `cowlib`, `getopt`.

# Citations

1. [Supply chain](/architecture/supply-chain.md)
2. [Spike S0](/reviews/spike-s0.md)
