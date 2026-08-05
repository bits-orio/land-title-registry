# Cells are fixed at 32x32, exactly aligned to native chunks

> **Partially superseded by ADR-0010** (2026-08-05): cell size is now a startup setting, 16 or 32 tiles (default 16), overturning the "configurable size — rejected" verdict below at the designer's request. Chunk *divisibility* is retained — every allowed size sits strictly inside one chunk — and the non-divisor rejection stands. The frontier-fragility argument is weakened by the ungenerated-chunk probe recorded in ADR-0010.

A cell is 32x32 tiles covering precisely one Factorio chunk footprint, so cell coordinates *are* chunk coordinates. The size is fixed and deliberately not configurable.

Two reasons drive it:

- **Chunk alignment removes the world-generation-frontier problem.** Blockers spawn from `on_chunk_generated`. Because a cell never straddles a chunk boundary, a newly generated chunk always yields exactly one complete cell, coverable by exactly one blocker, immediately.
- **A fixed size gives standard conditions across every game and server.** Prices, adjacency, and territory stats mean the same thing everywhere.

Rejected alternatives:

- **24-tile cells** — straddle chunk boundaries every third cell, forcing a choice at the generated-world frontier between temporary build gaps and sliver-blocker merging, inside the most fragile code path in the mod.
- **16- and 64-tile cells** — no advantage over the native 32.
- **Configurable size** — breaks the cross-game standardization that is itself a feature.
- **Hexagons, triangles, pentagons** — regular pentagons cannot tile the plane at all; hex and triangle cells have diagonal edges that axis-aligned rectangular collision boxes cannot trace, so engine-level enforcement via blocker entities becomes impossible. Enforcement would degrade into terrain ownership or script-side build policing, both of which abandon the model in ADR-0002. Visual identity comes from rendering — border art and corner survey stakes — not from geometry.
