---
type: architecture
title: Supply chain
description: Dependency pinning, CI gates and supply chain controls.
status: draft
tags: [supply-chain, ci]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §10
---

# Supply chain

- `mix.lock` committed. Erlang and Elixir versions pinned in `.tool-versions`.
- Builder and runtime images pinned by digest.
- Tailwind and esbuild versions pinned in `config/config.exs`. CI checks their SHA-256 sums.
- Git dependencies (`heroicons`) pinned by commit SHA. No daisyUI.
- CI fails if `_build` contains any native library (`*.so`): the release is NIF-free.
- Dependencies with no release in 18 months need a decision in `specs/decisions/`
  (at S0: `telemetry_metrics_prometheus_core`; close to the limit: `logger_json`, `mix_audit`).
- CI gates (all must pass):
  - `mix compile --warnings-as-errors` (this includes the 1.20 type-checker warnings)
  - `mix format --check-formatted`
  - `mix credo --strict` (with the `UnsafeToAtom` and `raw/1` checks)
  - `mix sobelow --exit --threshold low` (Phoenix security scan)
  - `mix deps.audit` (`mix_audit`, known CVEs) and `mix hex.audit` (retired packages)
  - `mix deps.unlock --check-unused`
  - `mix test` (with coverage of `Authz`, `Auth` and `Display` at 100%)
- Minimal dependencies. Each new dependency needs a reason in the PR description.
- SBOM (`mix sbom.cyclonedx`). Image signing with cosign (stage 2).
- Renovate or Dependabot for Hex packages and base images.

# Citations

1. [Threat model](/architecture/threat-model.md)
