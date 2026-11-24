---
type: feature
title: Authorization
description: Role model, server-side checks and the LiveView event rule.
status: draft
tags: [authz, security]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §5
---

# Authorization

## Model

Configured in `runtime.exs` from a mounted TOML or JSON config file (no atoms from config values):

```toml
[[roles]]
name   = "dev-read"
groups = ["/mqtt-lens/dev"]             # Keycloak group paths, exact match
allow  = ["telemetry/dev/#", "events/dev/#"]
deny   = ["events/dev/secrets/#"]

[[roles]]
name   = "ops-read-all"
groups = ["/mqtt-lens/ops"]
allow  = ["#"]
deny   = []
```

- Deny by default. A topic is visible if at least one role allows it **and** no role of
  the user denies it.
- Filters use MQTT wildcard rules (`+` = one level, `#` = rest, at the end only).
- `$`-topics (for example `$SYS/...`) never match a first-level `+` or `#`. This follows the
  MQTT specification. They are visible only with an explicit `$SYS/#` allow.
- Filters are checked at startup: an invalid filter stops the application (fail closed).
- At login, the user's roles compile into one `%MqttLens.Authz.Scope{}` struct. The struct
  is kept in the session and assigned to the socket.

## Where the check runs

The check runs on the server, before any data goes into a render:

- Tree: a node is listed only if the user can see at least one topic under it.
  Counts include only the visible topics. (Otherwise the counts leak hidden topics.)
- Topic detail and history: "not found" if not allowed, the same as a topic that does not exist.
- Live updates: each message in a batch is checked against the scope and the view filter.
- The user's view filter can only narrow what the role allows. It never widens it.

`MqttLens.Authz.visible?(scope, topic)` is a pure function. It has property tests against a
simple reference implementation ([testing](/architecture/testing.md)).

## LiveView event rule (T4)

LiveView events are client input. The router does not protect them.

- Every `handle_event/3` and `handle_params/3` that takes a topic or a filter calls
  `Authz.visible?/2` (or `Authz.narrow/2` for a filter) **before** it reads the store.
- Event parameters are validated: only expected keys, strings only, max 1 024 bytes.
  An unknown event or a bad parameter is logged (`authz_denied`) and ignored.
- The MVP has only read events: `select_topic`, `expand_node`, `set_filter`, `pause`,
  `resume`, `set_view`. No event changes broker state.
- Tests send each event with a forbidden topic and check that no data is in the render.

# Citations

1. [Threat model](/architecture/threat-model.md)
2. [Testing](/architecture/testing.md)
