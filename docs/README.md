# Engineering documentation

Each document has one job:

- [`architecture.md`](architecture.md) — module boundaries, data flow, ownership,
  and dependency rules.
- [`design-system.md`](design-system.md) — current visual intent and where exact
  tokens live in code.
- [`privacy.md`](privacy.md) — network, clipboard, storage, scripts, and
  permissions.
- [`testing.md`](testing.md) — automated coverage, known seams, mutation limits,
  and mandatory manual QA.
- [`releasing.md`](releasing.md) — version policy and the release procedure,
  including recovery points.
- [`performance-baseline.md`](performance-baseline.md) — signposts, measurement
  procedure, and recorded observations.
- [`gotchas.md`](gotchas.md) — stable-numbered platform traps with load-bearing
  workarounds.
- [`adr/`](adr/README.md) — durable decisions whose alternatives and
  consequences matter.

The repository is the source of truth. Exact constants and current behavior
belong in code and tests; these documents explain intent, boundaries, procedures,
and decisions. Temporary handovers, generated planning folders, and private
design exports are not specifications and must not be cited by tracked code.
