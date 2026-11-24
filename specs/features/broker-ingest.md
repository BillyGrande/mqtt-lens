---
type: feature
title: Broker ingest
description: Broker connection and subscriptions.
status: draft
tags: [mqtt, broker]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §7.1-7.2
---

# Broker connection (T19)

- One `emqtt` client under the supervisor. Client ID `mqtt-lens-<pod-name>`. Clean session.
- Dedicated EMQX listener for mqtt-lens, with authentication on (built-in database user).
- EMQX ACL for that user: **deny publish `#`**, allow subscribe only to the configured roots.
  If the app has a bug, the broker still blocks publish.
- TLS to the broker is optional inside the cluster. It is required for a broker outside the
  cluster, with `verify: :verify_peer` and hostname checks.
- The password is read from a file (a mounted Kubernetes Secret). It is not in an env var or a log.
- Reconnect with exponential backoff and jitter (1 s → 60 s). The supervisor restarts the client on a crash.

# Subscriptions

- `subscribe_roots` in the config (default `["#"]`), QoS 0.
- `$SYS/#` only if the config asks for it.
- At startup, retained messages arrive with the subscription and fill the tree.

# Citations

1. [Resource safety](/architecture/resource-safety.md)
2. [emqtt without QUIC](/decisions/0004-emqtt-without-quic.md)
