---
type: decision
title: No Trusted Types
description: The CSP does not use trusted-types none.
status: draft
tags: [csp, xss]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §2, §6.2
---

# Context

LiveView's client applies server HTML with DOM patching.

# Decision

Do not use `trusted-types 'none'`. It would break the app. Server-side escaping is the main control. The CSP blocks inline and third-party scripts, so an injection that gets through cannot run a script that is not on our origin.

# Consequences

Trusted Types is not a second XSS barrier. This is an accepted residual risk. See [threat model](/architecture/threat-model.md) (T5).

# Citations

1. [Web security](/features/web-security.md)
2. [Threat model](/architecture/threat-model.md)
