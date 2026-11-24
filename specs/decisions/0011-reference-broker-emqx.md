---
type: decision
title: Reference broker EMQX 6.2.2
description: EMQX 6.2.2 is the first and reference broker.
status: draft
tags: [mqtt, emqx]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §14 (D4)
---

# Context

The application needs a broker for development and tests.

# Decision

D4: First and reference broker: EMQX 6.2.2. Integration tests run against it in Docker.

# Consequences

Local and CI integration use Docker Compose with EMQX 6.2.2 and Keycloak (`make integration`).

# Citations

1. [Testing](/architecture/testing.md)
2. [Broker ingest](/features/broker-ingest.md)
3. [Environments](/process/environments-release-maintain.md)
