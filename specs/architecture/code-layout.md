---
type: architecture
title: Code layout
description: Planned source tree of the application.
status: draft
tags: [code-layout]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §12
---

# Code layout

```
lib/
  mqtt_lens/
    application.ex       supervision tree
    config.ex            load + validate config (fail closed)
    auth/
      oidc.ex            oidcc provider, login, callback, logout
      flows.ex           login flow state (ETS, TTL)
      sessions.ex        session store (ETS), sweeper, live_socket_id
    authz.ex             topic matcher, Scope, visible?/2, narrow/2
    broker.ex            emqtt client, subscribe, reconnect
    store.ex             topic tree, history, byte budget (ETS)
    dispatcher.ex        batching → PubSub
    display.ex           sanitize, hex, JSON pretty, cut
    rate_limit.ex        Hammer
  mqtt_lens_web/
    endpoint.ex          main endpoint (:4000)
    ops_endpoint.ex      health + metrics (:9090)
    router.ex            pipelines, CSP, live_session
    auth.ex              on_mount hooks, plugs
    controllers/auth_controller.ex
    live/topics_live.ex  the MVP UI
    components/          tree, message list, payload view
assets/                  CSS (Tailwind), app.js (LiveView client, no data hooks)
config/                  config.exs, dev.exs, test.exs, runtime.exs
deploy/                  Kubernetes manifests (kustomize), EMQX ACL example, Keycloak client example
docs/                    this design
```
