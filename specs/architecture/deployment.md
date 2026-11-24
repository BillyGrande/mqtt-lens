---
type: architecture
title: Kubernetes deployment
description: Pod and release security, network policy, configuration and secrets.
status: draft
tags: [deployment, kubernetes, security]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §8
---

# Kubernetes

## Pod and release security

- `mix release`, built in a pinned `hexpm/elixir` builder image.
- Runtime image: a pinned minimal Debian slim (or Wolfi) image with only libc, `libcrypto`,
  CA certificates and `/bin/sh` (the release start scripts need it). No package manager in the final image where possible.
- **Erlang distribution off:** `RELEASE_DISTRIBUTION=none`. No EPMD, no distribution port,
  no cookie, no `remote` console. (T15)
- `runAsNonRoot: true`, UID/GID 65532.
- `readOnlyRootFilesystem: true` (a small `emptyDir` for `/tmp` if the release needs it),
  `allowPrivilegeEscalation: false`, capabilities drop `ALL`, `seccompProfile: RuntimeDefault`.
- `automountServiceAccountToken: false`. The app does not use the Kubernetes API.
- Requests and limits set. One replica.
- Pod Security Admission label `restricted` on the namespace.

## Network

- Ingress NetworkPolicy: port 4000 from the Traefik namespace only; port 9090 from the monitoring namespace only.
- Egress NetworkPolicy: DNS, the EMQX listener port, Keycloak. Nothing else (T14, T16).
- HTTPRoute on the Traefik Gateway (HTTP and WebSocket). TLS certificate from cert-manager.
- No IP allow-list (decision [D2](/decisions/0005-no-ip-allow-list.md)): the app is public from the first deployment. A Traefik
  rate-limit middleware is still recommended in front of `/auth/*`.
- Because there is no allow-list, the security review ([MVP plan](/architecture/mvp-plan.md) step 7) is a hard gate before
  the first public route exists.

## Configuration and secrets

- Non-secret config: a ConfigMap with `mqtt-lens.toml` (roles, broker host, limits, public host).
- Secrets: a Kubernetes Secret (the deployment chooses the source, for example External Secrets), mounted as files:
  OIDC client secret, MQTT password, `secret_key_base`, signing and encryption salts.
- `config/runtime.exs` reads the files. Startup fails (fail closed) on: a missing secret,
  an invalid filter, an `http://` issuer, a `check_origin` that is not an exact `https://` origin,
  or unknown config keys.

# Citations

1. [Threat model](/architecture/threat-model.md)
2. [No IP allow-list](/decisions/0005-no-ip-allow-list.md)
