---
okf_version: "0.3"
title: mqtt-lens specifications
description: Design, features, decisions, process and reviews of mqtt-lens, a read-only MQTT topic viewer with OIDC login.
license: Apache-2.0
---

# mqtt-lens specifications

## Architecture and cross-cutting design

- [Code layout](/architecture/code-layout.md): Planned source tree of the application.
- [Kubernetes deployment](/architecture/deployment.md): Pod and release security, network policy, configuration and secrets.
- [MVP plan](/architecture/mvp-plan.md): Ordered build steps for the MVP, with the security review as a hard gate.
- [Logging, audit and metrics](/architecture/observability.md): Log events, filtered parameters and Prometheus metrics.
- [Architecture overview](/architecture/overview.md): Goals, non-goals, request path and technology stack of mqtt-lens.
- [BEAM resource safety](/architecture/resource-safety.md): Store limits, process limits and atom safety.
- [Supervision tree and data flow](/architecture/supervision-tree.md): Application supervisor children, the LiveView process model, and the data flow for one message.
- [Supply chain](/architecture/supply-chain.md): Dependency pinning, CI gates and supply chain controls.
- [Tests](/architecture/testing.md): Test levels and what each level checks.
- [Threat model](/architecture/threat-model.md): Assets, attackers, threats T1-T20, controls and accepted residual risks.

## Features

- [Authorization](/features/authorization.md): Role model, server-side checks and the LiveView event rule.
- [Broker ingest](/features/broker-ingest.md): Broker connection and subscriptions.
- [OIDC login](/features/oidc-login.md): Keycloak client settings and the Authorization Code + PKCE login flow.
- [Routes and LiveViews](/features/routes.md): Route table, authentication per route, and the live_session rule.
- [Sessions and socket lifetime](/features/sessions.md): Server-side sessions, cookie settings, timeouts and socket lifetime.
- [Web security](/features/web-security.md): Response headers, rendering of untrusted content, cross-site protection, request limits and errors.

## Decisions

- [Elixir and Phoenix LiveView](/decisions/0001-elixir-phoenix-liveview.md): The application uses Elixir and Phoenix LiveView. It replaced the v1 Rust and TypeScript design.
- [WebSocket, not SSE](/decisions/0002-websocket-not-sse.md): Live updates use the LiveView WebSocket.
- [No Trusted Types](/decisions/0003-no-trusted-types.md): The CSP does not use trusted-types none.
- [emqtt without QUIC](/decisions/0004-emqtt-without-quic.md): The MQTT client is emqtt built without QUIC, with a quicer override.
- [No IP allow-list](/decisions/0005-no-ip-allow-list.md): The app is public from the first deployment with no IP allow-list.
- [Public repository and personal accounts](/decisions/0006-public-repo.md): The repository is public on the personal GitHub account, with GHCR, Apache-2.0 and a noreply git identity.
- [beads, OKF and orchestrator process](/decisions/0007-beads-okf-orchestrator-process.md): Agents work through beads issues, OKF specs and an orchestrator that never writes code.
- [beads server mode and private remote](/decisions/0008-beads-server-mode-private-remote.md): beads runs in server mode with telemetry off, and syncs to a separate private repository.
- [Toolchain versions](/decisions/0009-toolchain-versions.md): The toolchain versions come from Spike S0.
- [OIDC provider is a deployment value](/decisions/0010-oidc-provider-deployment-value.md): The first OIDC provider is a Keycloak realm that brokers Entra ID. Realm, groups and host are deployment values.
- [Reference broker EMQX 6.2.2](/decisions/0011-reference-broker-emqx.md): EMQX 6.2.2 is the first and reference broker.

## Development process

- [beads issue database](/process/beads.md): Setup results of Spike S0, issue structure, labels, task content and command reference.
- [Environments, release and maintain](/process/environments-release-maintain.md): Agent autonomy per environment, rollback and maintain loop.
- [Agent evals](/process/evals.md): Plan for continuous agent evals after the MVP.
- [Guardrails](/process/guardrails.md): Hooks, git hooks and CI, REVIEW.md, CLAUDE.md verification block and GitHub settings.
- [OKF specs](/process/okf-specs.md): OKF format and layout of the specs/ source of truth.
- [The orchestrator](/process/orchestrator.md): Enforcement, session start, dispatch rules and reports.
- [Development process overview](/process/overview.md): Sources of the process, principles and the development loop.
- [Repository layout](/process/repo-layout.md): Target layout of the repository.
- [Roles](/process/roles.md): Roles, what each role does and never does, and how the limits are enforced.

## Reviews

- [Spike S0](/reviews/spike-s0.md): Status and results of Spike S0.

