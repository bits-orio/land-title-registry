# Freehold

Land rights, earned cell by cell. Every 32x32 cell of the map sits on a four-state ladder — Wilderness → Trail → Rampart → Deed — and the engine's own collision system, not a script watching build events, decides what may be placed where. Forces buy their way up the ladder with Land points earned from research. Exposes the `freehold` remote interface so other mods can query and drive claims.

> This glossary is seeded from `FREEHOLD_DESIGN.md`. Grow it as areas are documented; keep it and the code in the same vocabulary.

## Language

**Cell**:
The mod's unit of land: 32x32 tiles, exactly aligned to one native Factorio chunk footprint. Cell coordinates are chunk coordinates. Fixed size, deliberately not configurable.
_Avoid_: chunk (reserved for the engine concept), tile, plot, parcel, square

**Chunk**:
Factorio's own engine concept only — `on_chunk_generated`, `on_chunk_charted`, charted chunks. Never used for the mod's unit of land, even though the two coincide geometrically.

**State**:
Which rung of the ladder a cell occupies: Wilderness, Trail, Rampart, or Deed. Stored as `"trail" | "rampart" | "deed"`; Wilderness is the absence of a registry entry, never a stored string.
_Avoid_: tier, level, rank (when referring to a cell)

**Wilderness**:
Unowned land. No land-, transit-, or rampart-layer entity may be built. Tiles are not gated in any state. Not hostile, not hidden — simply land without building rights. Carries the fully-restrictive blocker and is the only state absent from the registry.

**Trail**:
The transport-corridor right: belts, rails, and pipes. How a force reaches outward. Unpowered by design — electric poles are a Rampart right, so a corridor that needs power is priced as a Rampart corridor. 1 point.

**Rampart**:
Trail's rights plus self-sufficient defense: turrets (never artillery), walls, gates, radar, poles, solar panels, accumulators. Chosen so a rampart can power itself with no Deed nearby. Strictly requires Trail. 3 points total.
_Naming history_: picket, stockade, watchpost, waystation — all retired.

**Deed**:
Full development rights, explicitly including artillery turrets. Represented by the **absence** of a blocker entity. 5 points total.

**Ladder**:
The linear ordering of the four states. Upgrades may skip Rampart (Trail → Deed); downgrades always reverse exactly one step, right to left.

**Full credit**:
The pricing invariant: an incremental path never costs more than a direct one, so the total invested to reach a state is path-independent. Every route to Rampart totals 3; every route to Deed totals 5.

**Land points** (code: `points`):
The single currency, held per force in `storage.points[force_index]` — never per player. A plain Lua number, not an integer: refunds are fractional at the default rate. Player-facing text always says "Land points".
_Avoid_: currency, credits, money, cash

**Blocker**:
The neutral, indestructible entity centered on a non-Deed cell whose collision mask denies the layers that cell has not earned. One per cell, at most. Derived state — rebuildable from the registry, never authoritative.
_Avoid_: marker, claim entity, tile entity

**Layer**:
One of the three custom collision-layer prototypes — `fh-land`, `fh-transit`, `fh-rampart`. Every player-creation prototype belongs to exactly one, assigned at data stage and unchangeable at runtime. No layer is ever placed on a tile prototype.

**Exempt**:
A player-creation assigned to no layer, so it can exist in any state including Wilderness — vehicles, space platform hubs, cargo pods, crash-site entities. Identified by capability where possible, never by a hand-maintained name blacklist.

**Registry**:
`storage.cells[surface_index][cell_key]` — the authoritative record of every claimed cell. Blockers and renders derive from it. If they disagree, the registry wins and the world is rebuilt.

**Frontier**:
An edge between two orthogonally adjacent cells whose states differ. Borders are drawn on frontiers only, so a uniform region costs render objects proportional to its perimeter, not its area.

**Survey stake**:
The corner marker sprite at a vertex touched by at least one frontier edge. The mod's visual signature — square cells delegate identity to rendering rather than geometry.

**Survey tool**:
`fh-survey-tool`, the single selection-tool item through which all claiming, upgrading, and downgrading happens. Only-in-cursor, never craftable, acquired via shortcut button or hotkey.

**Batch**:
The set of cells covered by one survey-tool drag. All-or-nothing: if the total cost exceeds the balance, nothing is applied. Never partially applied — predictability over cleverness.

**Adjacency**:
The claim-time requirement that a new Wilderness claim share an edge (4-way, never diagonal) with a cell the acting force already owns in any state. Checked only at claim time; there is no global-connectivity maintenance, and disconnected islands stay owned and stay valid adjacency sources.

**Anchor**:
What makes a batch eligible to claim: the drag rectangle contains or edge-touches owned territory — or, when the force owns nothing on the surface, contains the cell the acting player is standing in. A batch is anchored or it isn't; there is no partial case.

**Settlement charter**:
The one-time lump sum granted the first time a force establishes presence on a planet. Strictly once per force per planet, keyed by `surface.planet.name`. Solves the new-planet cold start; clock-fair under MTS because the trigger is team-internal progression.

**Land grants**:
The `fh-land-grants-N` sequential technology chain — the recurring income faucet. Ends in a terminal infinite tech with a **linear** cost formula, so late-game income tapers but never reaches zero.
