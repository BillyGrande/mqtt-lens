# Log

## 2026-11-24

- Closed Spike S0 items 7, 8 and 9: public repo and private beads repo created, repo-local identity, deny-list hooks in `.githooks/`, branch protection and security settings, beads in server mode with the Dolt remote on the private repo, telemetry off.
- The owner confirmed P7: beads data syncs to the private repo `BillyGrande/mqtt-lens-work`, never to the public code repo. Fixed the process principle that implied a public remote. Fixed the architecture diagram to match D2 (rate-limit middleware only, no IP allow-list).
- Specs split from `docs/` (Spike S0 item 6). The layout list in `process/okf-specs.md` now matches the tree.
- Split `docs/DESIGN.md` and `docs/DEVELOPMENT.md` into this OKF 0.3 bundle (Spike S0 item 6). All content moved without change. Status of all documents: draft. No `verified` entries yet.
