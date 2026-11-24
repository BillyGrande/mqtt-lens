---
type: architecture
title: Logging, audit and metrics
description: Log events, filtered parameters and Prometheus metrics.
status: draft
tags: [logging, metrics, audit]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §9
---

# Logging, audit and metrics

- JSON logs to stdout (`logger_json`), with request IDs.
- Events: `login_success` (sub, email, roles), `login_denied` (sub, groups, reason),
  `login_failed` (reason), `logout`, `session_expired`, `authz_denied` (sub, event, reason),
  `rate_limited` (ip or sub), `broker_connected`, `broker_disconnected`, `store_limit`,
  `process_killed` (max heap).
- `filter_parameters`: `code`, `state`, `token`, `id_token`, `password`, `secret`, `_csrf_token`.
- Never logged: tokens, codes, cookies, session tokens, payloads, secrets.
- Prometheus metrics on :9090: messages received/dropped, topics, store bytes, LiveView sockets,
  logins by result, rate-limit hits, broker connection state, atom count, process count,
  VM memory.
