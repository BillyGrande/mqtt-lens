# Architecture and cross-cutting design

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
