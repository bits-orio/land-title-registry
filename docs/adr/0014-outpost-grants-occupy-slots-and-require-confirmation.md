# Outpost grants: adjacency exemption as occupied slots, spent through a confirmation dialog

The adjacency rule (ADR-0004, ADR-0006) makes territory contiguous by construction. Playtesting asked for an earned exception: founding a Deed deep in the wilderness — expansion by expedition rather than by creep. The design constraint is that the exception must not dissolve the rule it pierces.

**The grant is a cap of concurrent outposts, not a consumable and not an unlock.** Each researched level of the `ltr-outpost-grants` chain (one tech per land-grants tier, costing `i × 1000` units of the cumulative pack list of tiers 1..i — a strategic purchase, deliberately far above the income techs) raises the force's cap by one. A founded outpost *occupies* a slot; the slot returns when the outpost's territory grows to reach the force's mainland, because at that point it is no longer an exception to adjacency — it *is* adjacent. Permanent-consumable charges were rejected (the mechanic dries up; hoarding), as was unlock-and-done (kills the adjacency rule's strategic meaning outright).

**Mainland accounting.** The force's first claim on a surface (starter grant or paid seed) is recorded as its *origin*. An outpost's slot frees when a BFS over the force's own cells connects the outpost cell to the origin — run once per survey batch and at founding time, never per cell event. When an outpost's own cell (or the origin cell) is downgraded away, its record moves to an adjacent owned cell — the region the record anchors still exists — and is dropped only when no region remains. Outpost claims themselves never seed an origin: an outpost must not anchor itself free.

**Founding requires an explicit confirmation dialog** (playtest requirement). Slots are hard-earned and the founding gesture — a Deed jump on a single disconnected Wilderness cell — is one mis-drag away from a normal claim. The drag never spends the slot: it opens a dialog stating the cell, the price, and the slot arithmetic; Esc or Cancel walks away. Everything is re-validated at confirm time (slot count, cell state, points), because research can reverse and the world can change while a dialog sits open.

## Consequences

- One new claims option (`opts.outpost`) skips the anchor test and origin seeding; the remote interface exposes `get_outpost_info` and integrators can still use `ignore_adjacency` for scripted seeding, which is a different sanction (ADR-0006) and does not touch slots.
- The HUD shows `Outposts: used/cap` only once the force has a slot, so the mechanic is invisible until researched.
- A released team slot (MTS) clears its outpost records and origins along with points, chronicle, and charters — recycled teams start blank everywhere.
- Two accepted edges: releasing an outpost cell after growing a region keeps the slot occupied via the moved record (no free-slot exploit), and a force whose origin cell is lost with no neighbour re-seeds its origin on its next claim.
