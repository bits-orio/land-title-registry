---
status: accepted — supersedes the "configurable cell size — rejected" entries in ADR-0001 and the design doc's rejected-decisions log
---

# Cell size is a startup setting: 16 or 32 tiles, default 16

`fh-cell-size` (startup, string, allowed `"16"` / `"32"`, default `"16"`) sets the cell edge length. ADR-0001 rejected configurability to keep conditions identical on every server; the designer overturned that deliberately, accepting the cross-server variance. The fixed-32 rationale's *engineering* half — chunk-frontier fragility — is what this ADR re-examines.

Both allowed sizes divide the 32-tile chunk, so every cell sits strictly inside exactly one chunk: `on_chunk_generated` ensures `(32/size)²` blockers per chunk, `chunk_of_cell` is a floor division, and the frontier stays trivially correct. Non-divisor sizes (24, 48) remain excluded from the allowed list — **but not because the engine forbids them**: a headless probe (2026-08-05) established that entities can be created on ungenerated chunks, survive later generation, and enforce collision afterwards, so a straddling cell could receive its full blocker from its first covering chunk with no enforcement gap. Recorded here because ADR-0001 assumed the opposite; if a future size needs straddling, the mechanism exists. They stay excluded today simply because nobody wants them and the mapping code is simpler without them.

Consequences:

- All runtime math flows through `const.CELL` / `const.FACTOR` / `const.chunk_of_cell` / `const.cell_range_of_chunk`. Nothing may assume cell coordinates equal chunk coordinates — true only at size 32. The remote interface exposes `get_cell_size()` and `docs/API.md` states the convention.
- Data stage sizes the blocker collision/selection boxes and scales the 1024-px overlays (`size × 32 / 1024`).
- **A size change on an existing save cannot be migrated** — the registry is keyed by cell coordinates. `on_configuration_changed` detects the change via `storage.meta.cell_size`, refunds every cell's `invested_points` in full, returns the world to Wilderness, and rebuilds. Loud message; no silent corruption.
- The economy ships calibrated for one mental model of cell area; at 16 the same prices buy four times finer granularity. Numeric tuning is M5's problem and now has one more axis.
- 16-tile cells mean 4× blockers and registry entries per explored area, multiplied again by MTS team surfaces. Watch UPS in M5 playtesting.
