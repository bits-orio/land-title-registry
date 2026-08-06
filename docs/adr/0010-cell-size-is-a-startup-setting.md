---
status: accepted — supersedes the "configurable cell size — rejected" entries in ADR-0001 and the design doc's rejected-decisions log
---

# Cell size is a startup setting: 16, 24, or 32 tiles, default 24

`ltr-cell-size` (startup, string, allowed `"16"` / `"24"` / `"32"`, default `"24"`) sets the cell edge length. ADR-0001 rejected configurability to keep conditions identical on every server; the designer overturned that deliberately, accepting the cross-server variance.

**24 is the size ADR-0001 was written against** — it straddles a chunk boundary every third cell — and it works because of an engine fact the original decision assumed away: a headless probe (2026-08-05) established that entities can be created on ungenerated chunks, survive later generation, and enforce collision afterwards. A straddling cell therefore receives its **full-size blocker the moment the first chunk touching it generates** (`on_chunk_generated` ensures every overlapping cell, idempotently), with no enforcement gap and no sliver management — the frontier dilemma ADR-0001 described simply does not arise. The mapping helpers are general overlap ranges (`const.cell_range_of_chunk` / `const.chunk_range_of_cell`); the claim/heal gate is "the cell touches a generated chunk". This shipped after the divisor-only first version, when the designer asked for 24 back as the default.

Consequences:

- All runtime math flows through `const.CELL` and the overlap-range helpers. Nothing may assume cell coordinates equal chunk coordinates (true only at 32) or that a cell sits inside one chunk (false at 24). The remote interface exposes `get_cell_size()` and `docs/API.md` states the convention.
- Data stage sizes the blocker collision/selection boxes and scales the 1024-px overlays (`size × 32 / 1024`).
- **A size change on an existing save cannot be migrated** — the registry is keyed by cell coordinates. `on_configuration_changed` detects the change via `storage.meta.cell_size`, refunds every cell's `invested_points` in full, returns the world to Wilderness, and rebuilds. Loud message; no silent corruption.
- The economy ships calibrated for one mental model of cell area; at 24 the same prices buy ~1.8× and at 16 4× finer granularity than at 32. Numeric tuning is M5's problem and now has one more axis.
- 16-tile cells mean 4× blockers and registry entries per explored area, multiplied again by MTS team surfaces. Watch UPS in M5 playtesting.
