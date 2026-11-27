# Decisions

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
- [Merge on the owner's word](/decisions/0012-merge-on-owner-word.md): The main session or the orchestrator runs the rebase merge only on the owner's word for each PR or batch. Role agents never merge.
