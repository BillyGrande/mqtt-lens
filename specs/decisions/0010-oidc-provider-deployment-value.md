---
type: decision
title: OIDC provider is a deployment value
description: The first OIDC provider is a Keycloak realm that brokers Entra ID. Realm, groups and host are deployment values.
status: draft
tags: [oidc, keycloak]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §14 (D1)
---

# Context

The repository is public and generic. See [public repository](/decisions/0006-public-repo.md).

# Decision

D1: First OIDC provider: a Keycloak realm that brokers Entra ID. The realm, groups and host are deployment values. They are not in this repository.

# Consequences

The reference setup in the repository is Keycloak, which brokers a corporate IdP (for example Entra ID).

# Citations

1. [OIDC login](/features/oidc-login.md)
2. [Public repository](/decisions/0006-public-repo.md)
