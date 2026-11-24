---
type: architecture
title: Supervision tree and data flow
description: Application supervisor children, the LiveView process model, and the data flow for one message.
status: draft
tags: [architecture, otp]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §3
---

# Supervision tree

The request path above the supervisor is in [architecture overview](/architecture/overview.md).

```
   └─ Application supervisor (one_for_one)
        ├─ MqttLens.Auth.Sessions     ETS: SHA-256(token) → session; sweeper
        ├─ MqttLens.Auth.Flows        ETS: login flow state (TTL 5 min)
        ├─ MqttLens.Auth.Oidc         oidcc provider worker (discovery + JWKS cache)
        ├─ MqttLens.RateLimit         Hammer (ETS backend)
        ├─ MqttLens.Store             ETS ordered_set: topic tree, last value, history, byte budget
        ├─ MqttLens.Broker            emqtt client, subscribe-only, reconnect with backoff
        ├─ MqttLens.Dispatcher        batches new messages every 250 ms → PubSub
        └─ Phoenix.PubSub
                 │
                 ▼
        one LiveView process per browser tab
          filters each batch by role + current view, then pushes a diff
```

# Data flow for one message

1. `Broker` receives a PUBLISH. It checks the topic length and the payload size,
   then copies the binary (`:binary.copy/1`, [resource safety](/architecture/resource-safety.md)).
2. `Store` writes the last value and the history entry, and applies the limits.
3. `Dispatcher` adds the message to the current batch. Every 250 ms it broadcasts the batch
   (max 500 messages; if more, it sends `:resync` instead).
4. Each LiveView filters the batch with its compiled role matcher and its view filter.
   It updates the page with a LiveView stream (`phx-update="stream"`, with a `limit`).

# Citations

1. [Resource safety](/architecture/resource-safety.md)
2. [Broker ingest](/features/broker-ingest.md)
