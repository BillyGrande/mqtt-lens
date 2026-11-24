---
type: architecture
title: BEAM resource safety
description: Store limits, process limits and atom safety.
status: draft
tags: [resource-safety, beam, dos]
generated:
  by: claude-sonnet-5-5
  at: 2026-11-24T10:19:47Z
x-mqttlens-source: docs/DESIGN.md §7.3-7.5
---

# Store limits (T6)

| Limit | Default | When it is reached |
|---|---|---|
| Max topics | 50 000 | New topics are dropped. Metric + rate-limited log. |
| Max topic name length | 1 024 bytes | Message dropped. |
| Max stored payload | 256 KiB | Payload cut; original size kept. |
| History per topic | 50 messages | Oldest dropped (ring buffer). |
| Total byte budget | 256 MiB | History of the least recently updated topics is dropped first. The last message stays. |
| Dispatcher batch | 500 messages / 250 ms | Overflow → one `:resync` broadcast; LiveViews reload their view from the store. |

The pod memory limit is set above the byte budget plus the VM baseline.

# Process limits (T6, T8)

- `:binary.copy/1` on every payload and topic that the store keeps. A slice of a large binary
  must not keep the full binary in memory.
- LiveView processes set `Process.flag(:max_heap_size, %{size: <~64 MiB>, kill: true, error_logger: true})`.
  A runaway process dies; the browser reconnects.
- LiveView processes check `Process.info(self(), :message_queue_len)` when a batch arrives.
  Above 50 batches, they drop the queue and do a resync.
- `Broker`, `Store` and `Dispatcher` use `:message_queue_data, :off_heap`.
- The message list in the UI is a LiveView stream with `limit: 200`, so neither the server
  process nor the browser keeps all messages.

# Atom safety (T7)

- External data (topic names, payloads, JSON keys, config values, OIDC claims, event
  parameters) never becomes an atom.
- Banned: `String.to_atom/1`, `List.to_atom/1`, `:erlang.binary_to_atom/2`,
  `JSON`/`Jason` decoding with `keys: :atoms`.
- CI: Credo `Credo.Check.Warning.UnsafeToAtom` and Sobelow `DOS.StringToAtom` fail the build.
- A metric shows `:erlang.system_info(:atom_count)`. An alert fires if it grows after startup.

# Citations

1. [Threat model](/architecture/threat-model.md)
