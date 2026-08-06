# Land Title Registry — Design & Handoff Document

**Mod:** Land Title Registry (`land-title-registry`) · **Target:** Factorio 2.0+ (Space Age optional) · **Status:** design complete, pre-implementation · **Last updated:** 2026-08-04

This is the handoff document for Land Title Registry, a land-rights overlay mod inspired by Gridlocked by _CodeGreen and reimplemented from scratch. It is written so an implementer can build v1 without access to the design discussions behind it. Decisions are stated in spec voice; everything genuinely unresolved is marked **Open:** and consolidated in the final section.

Cross-references use shortened section names: *Overview & Identity*, *Core Model* (Core Model: Cells, Rights, and Enforcement), *Economy*, *Player Experience*, *Architecture* (Technical Architecture), *Interfaces* (Interfaces & Integration), and *Roadmap* (Scope, Roadmap, and Decision Log).

## Contents

1. [Overview & Identity](#overview--identity)
2. [Core Model: Cells, Rights, and Enforcement](#core-model-cells-rights-and-enforcement)
3. [Economy](#economy)
4. [Player Experience](#player-experience)
5. [Technical Architecture](#technical-architecture)
6. [Interfaces & Integration](#interfaces--integration)
7. [Scope, Roadmap, and Decision Log](#scope-roadmap-and-decision-log)

---

## Overview & Identity

### What Land Title Registry is

Land Title Registry is a land-rights overlay for Factorio 2.0. Building rights are earned cell by cell through a tiered ladder: Trail (transport corridors) → Rampart (self-sufficient defense) → Deed (full development). Land stops being binary.

The world is divided into cells of 32×32 tiles, exactly aligned to native Factorio chunks (one cell = one chunk footprint; the word "chunk" is reserved throughout this document for the engine concept — the mod's unit is always the "cell"). Every cell is in exactly one of four states on a linear ladder:

| State | Blocker entity | Construction permitted | Cumulative price |
|---|---|---|---|
| Wilderness | `ltr-cell-wilderness` | Nothing buildable — no layered entities (layer-exempt player-creations such as deployed vehicles remain placeable anywhere) | 0 |
| Trail | `ltr-cell-trail` | Transit-layer entities (belts, rails, pipes) | 1 |
| Rampart | `ltr-cell-rampart` | Everything Trail permits (transit entities) plus rampart-layer entities (walls, gates, non-artillery turrets, radar, electric poles, solar panels, accumulators) | 3 |
| Deed | none | Everything, explicitly including artillery turrets | 5 |

Rights are enforced by the engine, not by scripts. Three custom collision layers (`ltr-land`, `ltr-transit`, `ltr-rampart`) assign every player-buildable prototype to exactly one layer at the data stage — apart from a small exempt class (vehicles and similar non-building player-creations) that carries no layer and can exist anywhere — and one neutral, indestructible blocker entity per non-Deed cell carries the collision mask that denies the not-yet-earned layers. A Deed cell has no blocker at all — absence of a blocker means full rights. The full mechanism is specified in *Core Model*; prices, credits, and refunds in *Economy*.

Worked example of the ladder's core invariant (full credit — an incremental path never costs more than a direct one): claiming a wilderness cell as Trail costs 1 point and immediately permits belts, rails, pipes, and landfill. Upgrading that same cell to Rampart costs +2 (3 total) and adds defensive and power infrastructure. Upgrading onward to Deed costs +2 more (5 total) — exactly the price of a direct Wilderness→Deed claim — and deletes the blocker so everything places. Players interact with all of this through a single selection tool, `ltr-survey-tool`, with four drag modes for claim/upgrade/downgrade (see *Player Experience*).

Rampart strictly requires Trail; Deed is reachable from either Trail or Rampart; downgrades reverse one step at a time with a partial refund. Movement is never restricted — the ladder gates construction only.

### What Land Title Registry is not

- **Not a fork.** Land Title Registry is a full from-scratch reimplementation of an idea, not a derivative codebase. No code, assets, or prototype/setting names are reused from any other mod.
- **Not a terrain mod.** Land Title Registry never modifies terrain generation or edits the map's existing tiles; it does not gate tile placement either (see *Core Model*, Tiles Are Not Gated). Ownership exists as inert blocker entities plus rendered border overlays; remove the mod and the map itself is untouched.
- **Not a movement restriction.** Characters, vehicles, and trains traverse Wilderness freely; vehicles also remain deployable-as-items anywhere. Only construction is gated. The custom collision layers are added only to stationary buildable prototypes; everything descending from `VehiclePrototype` — cars, spidertrons, and all rolling stock — is explicitly exempt (assigned to no layer), so nothing that moves ever collides with a blocker.
- **Not a script-side build cop.** Enforcement is collision-mask physics. The single deliberate exception is one `find_entities_filtered` area query validating a downgrade (see *Economy*); there is no per-build event policing anywhere in the mod.

### Credit

Land Title Registry is inspired by Gridlocked by _CodeGreen, which demonstrated that this genre works at all. Two of its ideas are consciously retained, with thanks to its author: engine-enforced, chunk-scale land claiming with one blocker entity per unit of land, and a linear-cost terminal infinite technology as the shape of land income.

Everything else is a ground-up build. No code, no assets, and no prototype or setting names are reused from any mod, though Gridlocked's MIT license would have permitted it.

The mod portal description carries this exact credit line:

> Inspired by Gridlocked by _CodeGreen - reimagined from scratch with tiered land rights, a land economy, and first-class Multi-Team Support integration.

### Design pillars

The decisions that define the mod, each specified in full in its own section below:

| Pillar | Commitment |
|---|---|
| Claim model | A four-state ladder per cell — Wilderness → Trail → Rampart → Deed. Partial rights are the subject of the mod, not an add-on to a binary claim |
| Ownership record | The registry is the single source of truth: `storage.cells[surface_index][cell_key]` stores state, force, claim tick, invested points, and claimant. Blockers and renders are derived state, rebuildable at any time via `/ltr-rebuild` (ADR-0003) |
| Pricing | Flat step prices with full credit for rights already held, so totals are path-independent. Connectivity is a separate, visible, claim-time adjacency rule — never arithmetic folded into a price (ADR-0004) |
| Tech design | A sequential `ltr-land-grants-N` chain ending in one linear-cost infinite tech, with tiers derived from the actual tech DAG rather than a hardcoded pack list (ADR-0008). `on_research_reversed` decrements grants correctly, including infinite-tech levels, so finish-then-reverse is exactly net zero |
| Multi-force behavior | State keyed by force index *and* surface index; `on_player_changed_force` handled as a hard requirement; `reset_force` implemented and exercised from day one; every global effect iterates all forces |
| Remote API | A documented, stable-from-v1 `land-title-registry` interface: points get/set/add, claim/downgrade, cell queries, chronicle queries, territory stats, surface enable/disable, plus custom events (see *Interfaces*) |
| Rendering | Frontier-only borders — drawn only where adjacent cells' states differ, so cost scales with perimeter rather than area. Created lazily as chunks are charted, with per-force visibility via each render object's `forces` filter |
| Layer membership | Capability-based rules by default, plus two override channels: host startup settings and a `mod-data` declaration convention other mods author themselves. No hand-maintained blacklist of third-party entity names (see *Interfaces*) |
| Competition | A per-cell chronicle ranked by team clock, not wall time, so staged starts stay fair; only first-Deed and record-takeover are celebrated (ADR-0012) |

### Positioning: standalone-first, integration-ready

Land Title Registry is a standalone mod that works in vanilla single-player with zero other mods installed. Multi-Team Support (MTS) and Open Discord Bridge (ODB) are optional dependencies: when present, Land Title Registry consumes their published interfaces (`mts-v1`, `open-discord-bridge-v1`) behind `script.active_mods` guards; when absent, every integration path is inert and nothing degrades.

The "MTS " title-prefix convention in that ecosystem means *hard* dependency. Land Title Registry does not carry the prefix precisely because its MTS dependency is optional — the name signals correctly that no team framework is required. The design goal is stronger than mere coexistence: MTS ships no compat shim for Land Title Registry; Land Title Registry is instead the reference consumer of MTS's COMPAT.md patterns, and likewise the reference integrator for ODB. Multi-force and multi-surface correctness is a design pillar, not a compatibility patch (see *Architecture*).

### Name rationale

"Land Title Registry" is real land-tenure vocabulary: a land title registry is the authoritative public record of who holds which right over which parcel. That is literally what this mod is — `scripts/registry.lua` is the single source of truth for every cell's state and owner (ADR-0003), and the blockers and borders are only its rendering. The name describes the mechanism rather than the fantasy, and it is fully independent of any other mod's identity.

Rejected names, with reasons:

| Rejected | Why |
|---|---|
| Freehold | The project's original working name. Real land-tenure vocabulary, but it names only the *top* rung — a freehold is land held outright, which is the Deed tier alone — and so undersells a mod whose whole subject is the ladder of partial rights beneath it |
| MTS Gridlocked | Implies the original author's endorsement, confuses on the portal, undersells the divergence, and violates the ecosystem convention that the "MTS " prefix means hard dependency |
| Land Rush, Boomtown, Stakeout | Imply urgency and a competitive scramble the deliberate, stewardship-paced gameplay does not deliver — especially under MTS, where teams are isolated on separate surfaces |
| Deedlocked, Landlocked (the "-locked" family) | Deliberately ride Gridlocked's identity; rejected in favor of a fully independent one |

Runners-up considered: Parcell, Groundwork, Homestead, Cellbound, Enclosure.

### Target version and dependency posture

| Field | Value |
|---|---|
| Mod portal title | Land Title Registry |
| Internal name (`info.json` `name`) | `land-title-registry` |
| Prototype / setting name prefix | `ltr-` |
| Remote interface name | `land-title-registry` |
| `factorio_version` | `"2.0"` (Factorio 2.0+) |
| Dependencies | `["base >= 2.0", "? multi-team-support", "? space-age", "? open-discord-bridge"]` |
| Incompatibilities | None — the stated goal is an empty incompatibility list; composability is the brand |

Space Age is optional but fully supported: planet-science technology tiers, once-per-force-per-planet settlement charters (see *Economy*), and space platforms exempt from the grid entirely — platform surfaces are auto-disabled since platform tiles already constrain building (see *Interfaces*).

---

## Core Model: Cells, Rights, and Enforcement

Land Title Registry divides every enabled surface into **cells** and attaches building rights to each cell through a four-state ladder. Rights are enforced by the engine's collision system — not by scripts watching build events — which means blueprints, construction robots, and manual placement are all governed identically and for free. (One honest caveat: another mod calling `LuaSurface.create_entity` bypasses collision checks unless it opts into `build_check_type` — script spawns from other mods are outside any enforcement model that isn't event policing, and Land Title Registry accepts that.) The only script-side policing in the entire mod is the downgrade validity check described in *Economy*.

### The Cell

A cell is a square of **`ltr-cell-size` tiles** — a startup setting allowing **16, 24, or 32, default 24** (ADR-0010, overturning the original fixed-32 decision at the designer's request). 24-tile cells straddle chunk boundaries; that is safe because blockers are created full-size the moment the first chunk touching their cell generates — the engine handles entities on ungenerated chunks (probed; ADR-0010). All code goes through the overlap-range helpers (`const.cell_range_of_chunk` / `const.chunk_range_of_cell`) rather than assuming cells and chunks align. Changing the setting on an existing save cannot be migrated: all claims are released with a full refund of their invested points.

Two engineering reasons drive this:

- **Chunk alignment avoids world-generation-frontier problems.** Blockers are spawned from `on_chunk_generated` (see *Architecture*). Because a cell never straddles a chunk boundary, a newly generated chunk always yields exactly one complete cell that can be covered by exactly one blocker, immediately. A 24-tile cell was rejected precisely because it straddles chunk boundaries every third cell: at the generated-world frontier this forces a choice between temporary build gaps (part of a cell exists but is not yet blocked) or sliver-blocker management (partial blockers that must be merged when the neighboring chunk generates) — in the most fragile code path in the mod.
- **A fixed size gives standard conditions across all games and servers.** Prices, adjacency, and territory stats mean the same thing everywhere. A configurable size was rejected because it breaks this cross-game standardization. 16-tile and 64-tile cells were considered and rejected in favor of the native 32.

Terminology note for the codebase and all player-facing text: the mod's unit is always a **cell**. The word "chunk" is reserved exclusively for Factorio's native engine concept (`on_chunk_generated`, chart chunks, and so on).

### The State Ladder

Every cell is in exactly one of four states, forming a linear ladder:

```
  Wilderness ──claim──▶ Trail ──upgrade──▶ Rampart ──upgrade──▶ Deed
                          │                                       ▲
                          └───────── upgrade (skip Rampart) ──────┘

  Upgrades:   Rampart strictly requires Trail.
              Deed is reachable from Trail (skipping Rampart) or from Rampart.
  Downgrades: always exactly one step, right to left:
              Deed → Rampart → Trail → Wilderness
```

Rules:

- **Rampart requires Trail.** There is no Wilderness→Rampart edge in the ladder itself; the survey tool's direct claim-to-Rampart action composes Wilderness→Trail→Rampart internally, just as direct claim-to-Deed composes Wilderness→Trail→Deed. Step prices and the full-credit rule live in *Economy*.
- **Downgrades reverse one step at a time**, regardless of how the state was reached: a Deed always downgrades to Rampart, never directly to Trail.
- Wilderness is the implicit default. Wilderness cells are **not** stored in the registry — absence from `storage.cells` means wilderness (see *Architecture*).

### What Each State Means

**Wilderness** is unowned land. No layered construction can be placed — no land-, transit-, or rampart-layer entities. Tiles are not gated in any state (see *Tiles Are Not Gated* below). Layer-exempt items — vehicles deployed from inventory, and the other exemptions below — remain placeable. It is not hostile or hidden — it is simply land without building rights. Wilderness cells carry the mod's only fully-restrictive blocker and are the only cells absent from the registry.

**Trail** grants transport-corridor rights: belts, undergrounds, splitters, all rails and rail signals, pipes, and pipe-to-ground. Trails are how a force reaches outward — rail lines, belt buses, and pipelines cross Trail cells at 1 point per cell. Pure Trails are unpowered by design: electric poles are rampart-layer, so a corridor that needs power is priced as a Rampart corridor.

**Rampart** adds self-sufficient defense on top of Trail rights: gun/laser/flamethrower turrets (any `ammo-turret`, `electric-turret`, `fluid-turret` — but **not** `artillery-turret`), radar, walls, gates, electric poles, solar panels, and accumulators. The membership is chosen so a Rampart can power itself (solar + accumulator + pole) without a Deed anywhere nearby: fortified, powered frontier at 3 points total.

**Deed** is full development rights: everything placeable, explicitly including artillery turrets (superweapons require a Deed), assembling machines, miners, roboports, and labs. A Deed cell has **no blocker entity at all** — full rights are represented by absence.

**Movement is never restricted in any state.** Characters, vehicles, trains, and enemies traverse wilderness freely; only construction is gated. Vehicles also remain deployable-as-items anywhere (cars and spidertrons are layer-exempt, below). This falls directly out of the blocker masks: they contain only Land Title Registry's custom layers and no engine movement layers.

### Collision Layers and Membership

Data stage defines **three custom collision-layer prototypes**, all entity-facing:

```lua
-- prototypes/layers.lua
data:extend({
  { type = "collision-layer", name = "ltr-land"      },
  { type = "collision-layer", name = "ltr-transit"   },
  { type = "collision-layer", name = "ltr-rampart"   },
})
```

**The assignment rule:** every player-buildable prototype — anything carrying the `"player-creation"` flag — is assigned to **exactly one** of land/transit/rampart by adding that layer to its collision mask in `data-final-fixes.lua`, using `collision-mask-util`:

```lua
-- data-final-fixes.lua (sketch)
local mask_util = require("collision-mask-util")
-- for each entity prototype with the "player-creation" flag:
local layer = resolve_layer(prototype)  -- defaults < mod-data declarations < host settings (*Interfaces*)
local mask = table.deepcopy(mask_util.get_mask(prototype))
-- deepcopy matters: get_mask can return a shared type-default mask table by
-- reference; mutating it in place would edit every prototype of that type
mask.layers[layer] = true               -- exactly one of ltr-land / ltr-transit / ltr-rampart
prototype.collision_mask = mask
```

Default membership, by prototype type (prefer these capability/type-based rules over hand-maintained name lists — long name blacklists are an explicit anti-goal):

| Layer | Default members (prototype types) |
|---|---|
| `ltr-transit` | `transport-belt`, `underground-belt`, `splitter`, `lane-splitter`, `loader`, `loader-1x1`, `linked-belt`; all rail prototypes: `straight-rail`, `curved-rail-a`, `curved-rail-b`, `half-diagonal-rail`, the elevated variants, `rail-ramp`, `rail-support`, legacy rails; `rail-signal`, `rail-chain-signal`, `train-stop`; `pipe`, `pipe-to-ground` |
| `ltr-rampart` | `ammo-turret`, `electric-turret`, `fluid-turret` (**not** `artillery-turret`), `radar`, `wall`, `gate`, `electric-pole`, `solar-panel`, `accumulator`, `pump` |
| `ltr-land` | Everything else with the `player-creation` flag — explicitly including `artillery-turret`, assembling machines, mining drills, roboports, and labs |

These three were open and are now resolved, with different reasons:

- **`train-stop` → transit.** It has no energy source at all, so it functions on an unpowered Trail. Land membership would have required a Deed under every station on a rail line, contradicting "Trails are how a force reaches outward."
- **`pump` → rampart.** A pump needs electricity, and electricity is a Rampart right (poles are rampart-layer). Putting it in transit would have made it placeable on a pure Trail and permanently inert there; rampart membership makes the layer match where the entity can actually function.
- **`loader` / `loader-1x1` → transit.** Belt family. A loader on a Trail has nothing to feed, since containers are land-layer, but it is harmless and belongs with its relatives.

**Exemptions** — assigned to no layer; placeable and existing anywhere, in any state including Wilderness.

The primary rule is capability-based, exactly as the design demands instead of name lists: **everything descending from `VehiclePrototype` is exempt.** In the 2.0 prototype hierarchy that parent covers `car`, `spider-vehicle`, and the whole `RollingStockPrototype` subtree — `locomotive`, `cargo-wagon`, `infinity-cargo-wagon`, `fluid-wagon`, `artillery-wagon` — and it picks up modded vehicles and modded rolling stock with no maintenance.

Rolling stock is not optional here. Without the exemption, wagons and locomotives fall through to `ltr-land` as player-creations, so a locomotive could not be placed on the force's own Trail rails — and a *moving* train carrying `ltr-land` would collide with every Trail and Rampart blocker it drove through, stopping dead at cell boundaries.

**Accepted leak:** an artillery wagon is mobile artillery and therefore slips the "superweapons require a Deed" rule. This is unavoidable — any mask that blocks its placement also blocks its movement. Spidertrons carrying rocket launchers are the same class of leak. Document it; do not try to close it with a build-event check.

Additionally exempt, by name or by capability where one exists: `space-platform-hub`, `cargo-pod-container`, and crash-site entities.

Membership is overridable per host and per third-party mod via startup settings and a mod-data convention, with precedence Land Title Registry defaults < mod-data declarations < host settings — full specification in *Interfaces*.

### Blocker Entities

Enforcement is implemented by **exactly one blocker entity per non-Deed cell**, centered on the cell. For cell coordinates `(cx, cy)` the center is `{cx * 32 + 16, cy * 32 + 16}`.

| State | Blocker entity | Collision mask layers |
|---|---|---|
| Wilderness | `ltr-cell-wilderness` | `ltr-land`, `ltr-transit`, `ltr-rampart` |
| Trail | `ltr-cell-trail` | `ltr-land`, `ltr-rampart` |
| Rampart | `ltr-cell-rampart` | `ltr-land` |
| Deed | *(no entity)* | — |

Shared prototype spec for all three blockers:

| Field | Value |
|---|---|
| `type` | `simple-entity-with-owner` |
| force (at creation) | `neutral` |
| destructibility | indestructible (`entity.destructible = false` after `create_entity`) |
| `collision_box` | approximately `{{-15.99, -15.99}, {15.99, 15.99}}` |
| `selection_priority` | **low — `5`**. Deliberately near the bottom of the 0–255 range (default 50) so a blocker's full-cell selection box never steals the cursor from entities the player has built inside Trail and Rampart cells. `selection_priority` governs *cursor* selection only; area selection is unaffected by it, and the survey-tool handlers read `event.area` and ignore `event.entities` anyway. See ADR-0005. |
| Recommended flags | `placeable-off-grid`, `not-repairable`, `not-on-map`, `not-deconstructable`, `not-blueprintable` |

The `15.99` half-extent (rather than `16`) keeps the box fractionally inside the cell so it never collides across the boundary with entities legally placed flush against the edge of an adjacent cell. Because the mask contains only Land Title Registry's custom layers — no player, object, or train layers — blockers never impede movement or pathfinding.

How enforcement works, concretely: an assembling machine carries `ltr-land` in its mask, so it collides with all three blockers — placeable only in a Deed cell. A transport belt carries `ltr-transit`, so only `ltr-cell-wilderness` blocks it — placeable from Trail up. A gun turret carries `ltr-rampart` — placeable from Rampart up. The absence of a blocker in a Deed cell blocks nothing.

**State transitions are blocker swaps**: destroy the old blocker, create the blocker for the new state (or none, when upgrading to Deed; when downgrading from Deed, create `ltr-cell-rampart`). Each created blocker is registered with `script.register_on_object_destroyed` and its registration id recorded for cleanup in `on_object_destroyed`; blockers are derived state, rebuildable from the registry at any time (see *Architecture*).

### Tiles Are Not Gated

**Land Title Registry places no collision layer on any tile prototype and sets no flag on one.** Landfill, concrete, stone path, and foundation place and mine identically in every cell state, including Wilderness. Enforcement is entity-layer only. An earlier design gated tiles with a fourth layer, `ltr-cell-tile`, plus `check_collision_with_entities = true`; that mechanism was cut before implementation for the reasons in ADR-0007, summarized here:

- `check_collision_with_entities` is a per-prototype boolean and cannot be scoped to one layer — it tests the tile's **whole** mask against entities. Concrete, refined concrete, stone path, and landfill all carry exactly `{ground_tile = true}`, the same mask as grass, dirt, and sand.
- `fish` also carries `{ground_tile = true}` — that layer is what keeps fish out of landfill. Enabling the flag therefore makes **landfill fail to place wherever a fish happens to be swimming**, intermittently, because fish move. That is the lake causeway breaking at random. Several Gleba plants and wrigglers carry the layer too.
- The engine also checks the flag when **mining** a tile, not only when building one, so a cell downgraded to Wilderness would trap its concrete permanently.
- `data-final-fixes.lua` would have to set the flag on every player-placeable tile in the game, **including modded tiles whose masks Land Title Registry does not control**. For a mod whose brand is an empty incompatibility list, that is the likeliest single source of one.

The lake causeway is unaffected, because the gate was never what made it work:

1. Trail-claim a line of cells across a lake (claiming a cell does not require buildable ground; the blocker sits over water just fine).
2. Landfill a causeway. Landfill was always going to place here — and now places in Wilderness too, which buys a force nothing it can build on.
3. Run rails or belts across the new land — both are transit-layer, and **this** is the step Trail rights actually gate.

Space platforms need no special handling: platform surfaces are auto-disabled (no blockers, no grid — see *Interfaces*), and platform foundation tiles were always governed by the platform's own rules.

Revisit post-v1 only if playtesting shows that unrestricted paving of Wilderness is a real gameplay problem, and then with a mechanism whose blast radius stops at Land Title Registry's own prototypes.

### Engine Restriction: Masks Are Fixed at Startup

Collision masks are read once at prototype-load time and **cannot be changed at runtime**. Consequences to design around, not against:

- Layer membership (which entities are transit/rampart/land) is decided entirely at data stage. This is why both membership-override channels — the host's startup string settings and the cross-mod mod-data convention (*Interfaces*) — are **startup scope** and are applied in `data-final-fixes.lua`. There is no runtime API to move an entity between layers, and none should be promised.
- Per-cell state changes are unaffected: they swap blocker *entities* (a runtime operation), never masks.

### Rejected Geometries and Cell Sizes

Recorded here as engineering rationale so the questions stay closed:

- **Hexagons, triangles, pentagons — rejected.** Regular pentagons cannot tile the plane at all. Hex and triangle cells have diagonal edges that axis-aligned rectangular collision boxes cannot trace, so engine-level enforcement via blocker entities is impossible — enforcement would degrade into terrain ownership or script-side build policing, both of which abandon the engine-enforced rights model. Square cells are retained; the mod's visual identity comes from rendering (border styles, corner survey stakes — see *Player Experience*), not from geometry.
- **24-tile cells — rejected.** Straddle chunk boundaries every third cell, forcing either temporary build gaps or sliver-blocker management at the generated-world frontier, the most fragile code path.
- **16- and 64-tile cells — rejected** in favor of the native 32-tile chunk footprint.
- **Configurable cell size — originally rejected here, overturned by ADR-0010** (startup setting, 16/24/32, default 24). The cross-game standardization argument was consciously set aside by the designer, and the chunk-straddling objection to 24 dissolved against the real engine: blockers create fine on ungenerated chunks, so straddling cells get full blockers from their first touching chunk.

---

## Economy

The economy is a single-currency system: forces earn **points** (displayed in UI as **"Land points"**) from research and one-time grants, and spend them to claim and upgrade cells with the survey tool. All prices are flat and visible; all faucets are team-internal. Every numeric value in this section is a launch ballpark pending playtesting (see the consolidated open questions in *Roadmap*).

### Currency and balances

- Points are held **per force**, in `storage.points[force_index]` as a plain Lua number. There is no per-player currency.
- Initialize a force's balance on `defines.events.on_force_created` (and for all existing forces in `on_init` / `on_configuration_changed` — iterate **all** forces, never just `game.forces.player`; see *Architecture*).
- Every balance mutation — claim spend, downgrade refund, research grant, starting grant, settlement charter, remote `set_points`/`add_points`/`reset_force` — raises the custom event `on_points_changed` with payload `{force_name, points, delta, reason}` (see *Interfaces*). A short stable vocabulary for `reason` is recommended, e.g. `"claim"`, `"refund"`, `"research"`, `"research-reversed"`, `"starting-grant"`, `"settlement-charter"`, `"remote"`, `"reset"`.
- The per-player HUD and the survey-tool cursor label both display the acting force's balance (see *Player Experience*); refresh them from the `on_points_changed` path.
- **`on_forces_merged` — resolved: union everything into the destination.** Sum the two balances, reassign every cell record's `force_index` to the destination force, union the settlement-charter records (so the survivor cannot re-farm a planet the source had already charted), refresh renders whose `forces` filter names the now-destroyed force, and raise `on_points_changed` with reason `"merge"`. There is **no conflict resolution to design**: a cell record holds exactly one `force_index`, so the two forces' cell sets are disjoint by construction and the union is total and unambiguous. MTS never calls `merge_forces`, so this is a defensive-correctness handler reached by console commands, scenarios, and other mods — the bar is leaving `storage` consistent, not pricing the merge.

### Prices and the full-credit principle

Prices are flat per step, with **full credit for already-held rights**: an incremental path never costs more than a direct one. The total invested to reach a state is path-independent — every route to Rampart totals 3, every route to Deed totals 5.

| Transition | Step cost | Total invested at destination | Notes |
|---|---|---|---|
| Wilderness → Trail | 1 | 1 | New claim; adjacency rule applies |
| Trail → Rampart | 2 | 3 | Rampart strictly requires Trail (see *Core Model*) |
| Rampart → Deed | 2 | 5 | |
| Trail → Deed | 4 | 5 | Rampart may be skipped |
| Wilderness → Rampart (direct, one tool action) | 3 | 3 | New claim; adjacency rule applies |
| Wilderness → Deed (direct, one tool action) | 5 | 5 | New claim; internally passes through Trail |

The direct Wilderness → Deed action internally passes through Trail, so claim bookkeeping (adjacency check, registry insert, `invested_points`) runs through a single code path; its price is exactly the sum of the credited steps (1 + 4). Record each cell's cumulative spend in the registry field `invested_points` (see *Architecture*).

Worked examples:

1. **Incremental equals direct.** A force Trail-claims a corridor cell for 1 point, later upgrades it to Rampart for 2 (3 invested), and finally to Deed for 2 more (5 invested). The neighboring cell taken straight to Deed in one alt-select also costs 5. No path penalty in either direction.
2. **Mixed-state batch.** An alt-select (upgrade-to-Deed) drag covers four cells: one Wilderness, two Trail, one already Deed. Batch cost = 5 + 4 + 4 + 0 = 13 (the Deed cell is fully credited and charges nothing). If the balance is 12, **nothing** is applied — batches are all-or-nothing; the error sound plays and flying text shows the shortfall of 1 (see *Player Experience* for batch and feedback semantics).
3. **Skipping Rampart loses nothing.** Trail → Deed (4) equals Trail → Rampart → Deed (2 + 2). Players never need to route through Rampart "for the discount"; Rampart is bought for its defensive rights, not its price position.

The claim event `on_cell_claimed` carries the charged `cost`; `on_cell_downgraded` carries the paid `refund` (see *Interfaces*).

### Adjacency

A **new claim on a Wilderness cell requires adjacency to a cell already owned by the acting force, in any state** (Trail, Rampart, or Deed all qualify). Upgrades of already-owned cells never re-check adjacency.

- **Adjacency is 4-way orthogonal — resolved.** Only cells sharing an edge qualify; corner-touching cells do not. The reason is that Trail exists to carry belts, rails, and pipes, and transport is rook-connected: two cells touching only at a corner can pass nothing between them. 4-way makes the claim rule isomorphic to the physical rule, so a claimable direction is always a buildable direction. 8-way was rejected because it permits diagonal Trail "corridors" that read as corridors on the map but carry nothing, and lets a large rectangle anchor off a single corner touch.
- **First-claim seeding — resolved: the standing-cell anchor.** If the acting force owns **no** cells on the surface, the batch anchors if the drag rectangle contains the cell the acting player is standing in. This is one extra clause in the anchor test rather than a separate code path, and it serves three purposes at once: it seeds Nauvis at game start, it seeds each new planet exactly where the force actually lands (rather than at `force.get_spawn_position`, which a Space Age cargo pod need not drop anywhere near), and it un-sticks a force that has downgraded away its last cell on a surface. The acting player must be physically present, so the mechanism rewards travelling rather than scouting from map view.

  For the remote `claim` function, which may have no acting player: on a surface where the force owns nothing, the call is refused with reason `"no-anchor"` unless the caller passes `opts.ignore_adjacency = true`. Scenario and quest mods that need to seed territory deliberately use that flag; it is the only sanctioned way to bypass the rule. *(Implementer's call, recorded here so it stays consistent with the tool's semantics.)*
- **Batch adjacency — resolved: the whole-rectangle anchor test.** A batch is *anchored* if the drag rectangle contains, or shares an edge with, any cell the acting force already owns in any state. An anchored batch claims every eligible Wilderness cell in it; an unanchored batch claims nothing, plays the denial sound, and shows flying text. There is no partial case.

  This is progressive evaluation in two stages (corrected during M1 review — see ADR-0006). The anchor test gates the *batch*: unanchored means loud denial. A breadth-first reachability pass then gates the *cells*: the rectangle is not guaranteed hole-free — foreign-owned cells and ungenerated chunks are ineligible and break its connectivity — so only the eligible Wilderness cells actually reachable from the force's territory (or the standing cell), walking through same-batch candidates, are claimed. Unreachable candidates are ineligible no-ops like any other. Reachability is order-independent, so progressive adjacency does not reintroduce the unpredictability that partial application was rejected for (*Player Experience*, Batch Semantics); for a hole-free rectangle the pass reaches everything and the batch behaves as one unit.

  Consequences, both intended: a long drag anchored on one edge cell claims the whole line in one gesture (a 1×40 corridor costs 40 points), and a 20×20 rectangle sharing one edge with the border claims 400 cells for 400 points. Affordability is the limiter, not geometry — and all-or-nothing means the whole rectangle is bought or nothing is.
- Adjacency is checked **only at claim time**. There is **no global-connectivity maintenance**: downgrades may later disconnect territory, disconnected islands remain owned, and those islands remain valid adjacency sources for future claims. No flood-fill, no revocation, no reconnection requirement — ever.

Rejected alternative: adjacency-discount pricing, where cost arithmetic encodes connectivity. Land Title Registry splits the concerns: prices are flat and legible; connectivity is a visible, binary claim-time rule.

### Downgrades and refunds

Downgrades reverse the ladder **one step at a time**: Deed → Rampart → Trail → Wilderness (see *Core Model*). Each step refunds:

```
refund = step price of the reversed step × (ltr-refund-percent / 100)
```

`ltr-refund-percent` is a runtime-global setting, range 0–100, **default 25**. The default must never be high: claiming a cell, exhausting its resources, and downgrading must not be a free roundtrip. Refund arithmetic produces fractional amounts at the default rate (0.5 per Rampart/Deed step, 0.25 per Trail step); balances are therefore plain Lua numbers, quantized to hundredths of a point after every mutation. Quantization is what keeps fractional accumulation exact in floating point: every sanctioned refund (integer step × integer percent / 100) has at most two decimal digits, but values like 0.3 are not exactly representable as doubles, and without re-snapping, ten 0.3 refunds sum to 2.9999999999999996 and a 3-point claim is falsely denied — and the remote interface's `get_points` accordingly returns a number, not an integer (see *Interfaces*).

Refunds are symmetric with the credit principle. Fully unwinding a Deed at 25% refunds: Deed → Rampart 0.5 (25% of 2), Rampart → Trail 0.5 (25% of 2), Trail → Wilderness 0.25 (25% of 1) — total 1.25, exactly 25% of the 5 invested, regardless of the path taken up the ladder. Note that Deed always downgrades to Rampart even when the Deed was reached directly from Trail; the two-step refund basis (2 + 2) still matches the 4 originally charged.

**Downgrade validity** — a cell may only shed a right that nothing in it is using. This is checked with **one `find_entities_filtered` area query over the cell at downgrade time**, and it is the *only* script-side policing in the entire mod; all other enforcement is engine-level via blocker collision (see *Core Model*):

| Downgrade | Cell must contain |
|---|---|
| Deed → Rampart | No entities on the land layer |
| Rampart → Trail | No entities on the rampart layer |
| Trail → Wilderness | No player constructions at all |

**Tiles are irrelevant to downgrades.** Land Title Registry does not gate tile placement in any state (see *Core Model*, Tiles Are Not Gated), so a cell returning to Wilderness keeps whatever landfill, concrete, or foundation is on it, and the owner can still mine it away freely. Nothing about tiles enters the downgrade validity check.

**Deferred (post-v1, not in scope): depletion-aware refunds.** Snapshot the cell's total resource amount at claim time and scale the refund by the remaining fraction, so strip-mined cells refund less. v1 ships the flat rate only; the registry's `invested_points` and `claimed_tick` fields already provide the hooks.

### Income: the ltr-land-grants technology chain

Research is the recurring faucet. Income comes from a **sequential** chain of leveled technologies; each finished level grants the acting force `ltr-points-per-level` points (startup setting, default **5**) via `defines.events.on_research_finished`.

| Prototype (start level) | Science packs (cumulative) | Levels |
|---|---|---|
| `ltr-land-grants-1` | automation | 10 |
| `ltr-land-grants-11` | + logistic | 10 |
| `ltr-land-grants-21` | + military | 10 |
| `ltr-land-grants-31` | + chemical | 10 |
| `ltr-land-grants-41` | + production, utility | 10 |
| `ltr-land-grants-51` | + space | Base game: infinite (terminal). Space Age: 10, then the planet tiers below |

**That table is the expected output of the mechanism, not the mechanism.** Pack membership is **derived from the actual technology DAG at data stage**, never hardcoded — see *Deriving the tier ladder* below. The tables here are asserted against the real derivation by the in-engine test suite (verified 2026-08-05 against Factorio 2.0.77, both mod sets). Prototype names carry the family's *start level* — the engine parses the trailing number as a level, so tiers are `ltr-land-grants-1`, `-11`, `-21`, … with `max_level` closing each range; one locale key (`technology-name.ltr-land-grants`) covers the family.

**Space Age tiers**, as the derivation produces them:

| Prototype (start level) | Science packs (cumulative) | Levels |
|---|---|---|
| `ltr-land-grants-61` | + metallurgic, electromagnetic, agricultural | 10 |
| `ltr-land-grants-71` | + cryogenic | 10 |
| `ltr-land-grants-81` | + promethium | infinite (terminal) |

The three inner-planet packs share one tier deliberately. Vulcanus, Fulgora, and Gleba are completed in any order, but a technology's `unit.ingredients` is a conjunction — there is no "any one of these packs". A per-planet chain would therefore pick an arbitrary planet order and stall a force's entire land income if they happened to visit Fulgora first. Grouping the three is symmetric, and it mirrors how Space Age itself gates: three inner planets in any order, then Aquilo, then the Shattered Planet.

An earlier draft of this section merged automation and logistic into one first tier. The derivation splits them, and the split is *correct by the derivation's own rule*: base 2.0 gates the automation pack's recipe behind a starter technology that the logistic pack's tech descends from, so the two are genuinely ordered in the DAG — a real ordering must become a tier boundary. All groupings the design cares about (production+utility; the three inner-planet packs) are preserved. Every tier is 10 levels at launch (`LEVELS_PER_TIER`); per-tier level counts are M5 tuning.

- Each tier's prerequisite is the previous tier; players see a single ladder, not a lattice.
- Within a tier, science cost ramps **roughly linearly** via `unit.count_formula`; the terminal infinite tier uses the **linear** formula `L*1000*multiplier` with `max_level = "infinite"`. Linear is deliberate: exponential infinite techs effectively shut the faucet off late-game, whereas linear cost keeps land income flowing at a tapering but never-zero rate for megabase-scale play. (The linear-cost terminal technology is one of the two ideas retained from Gridlocked — see *Credit*. The parallel per-pack tech structure is not; see the rejected alternatives below.)
- `ltr-tech-cost-multiplier` (startup, default 1) globally scales science costs; being startup-scope it is readable at data stage and should be baked into each tier's `unit.count` / `unit.count_formula` (e.g. `"L*" .. (1000 * multiplier)`).
- **Engine note:** Factorio parses a trailing `-<number>` in a technology name as a level within a name family, and leveled prototypes express their range via the name suffix (starting level) plus `max_level` (ending level). The implementer must reconcile the tier naming with per-tier level counts when writing the prototypes (vanilla's `mining-productivity-*` chain is the reference pattern for a chained leveled family ending in an infinite tech).
- **Research-reversal correctness is a hard requirement.** `defines.events.on_research_reversed` must decrement the force's points by `ltr-points-per-level` per reversed level, **including infinite-tech levels**, so that finish-then-reverse is exactly net zero. The infinite-level case is the easy one to get wrong, so the testing matrix in *Architecture* includes research reversal explicitly.

#### Deriving the tier ladder

Land Title Registry must never name a science pack as a constant. Overhaul mods make hardcoded pack lists wrong at best and fatal at worst:

- **Krastorio2** keeps the vanilla packs and adds four of its own (`kr-basic-tech-card` … `kr-singularity-tech-card`) — a vanilla chain loads, but sits at the wrong depths.
- **Periodic Madness** keeps `automation`, `logistic`, and `chemical` but interleaves eight of its own between them; `pm-advanced-advanced-transition-metal-science-pack` comes *before* chemical, so a vanilla ordering is simply wrong.
- **Ultracube** replaces science outright — `cube-basic-contemplation-unit`, `cube-fundamental-comprehension-card`, and so on. **No vanilla pack prototype exists at all.** A chain naming `automation-science-pack` in `unit.ingredients` references a nonexistent prototype: a data-stage crash, or at best a permanently unresearchable chain and a dead income faucet for the entire game.

The ladder is therefore computed in `data-final-fixes.lua`:

1. **Candidate packs** — every `tool` prototype that appears in some technology's `unit.ingredients`. This picks up overhaul packs automatically and excludes tools that are not science.
2. **Availability depth** — for each pack, the minimum over producing recipes of (1 + the unlocking technology's prerequisite depth); recipes enabled at game start give depth 0. **Recycling-category and self-producing recipes are excluded** — Space Age's self-recycling recipes "produce" every pack from itself at 25%, enabled from the start, and would flatten every depth to 0 (found empirically against the 2.0.77 data dump).
3. **Order** — sort by depth ascending, then by prototype name. The name tiebreak is not cosmetic: it makes the ladder deterministic rather than dependent on `pairs()` iteration order.
4. **Band** — walk the ordered packs; a pack joins the current tier iff its unlock technology is **DAG-incomparable** with every current member's (neither is a prerequisite ancestor of the other — a real ordering in the tree must become a tier boundary) **and** its depth is within `BAND_SPAN` (4) of the tier's first pack (parallel branches far apart in progression read as separate tiers: military vs chemical). Depth-gap thresholding alone cannot reproduce the intended groupings — the same gap of 3 must merge production+utility and split utility|space — which is why comparability is the primary signal.
5. **Terminal tier** — the last band; takes every pack, `max_level = "infinite"`, linear `count_formula`.

**Host override channel.** A startup string setting `ltr-tech-tiers` pins the ladder explicitly, in the same spirit as the layer-membership override settings (*Interfaces*): semicolon-separated tiers, each a comma-separated list of the packs *added* at that tier (ingredients accumulate down the ladder automatically). Empty (the default) means derive. This gives overhaul authors and server hosts the final word when the derivation gets a novel tech tree wrong, without waiting for a Land Title Registry release:

```
ltr-tech-tiers = cube-basic-contemplation-unit; cube-fundamental-comprehension-card; cube-abstract-interrogation-card; cube-deep-introspection-card; cube-synthetic-premonition-card
```

**Validation.** The derivation reproducing the vanilla and Space Age tables above is a test assertion in the testing matrix, not an assumption.

### Starting grant and settlement charters

- **Starting grant:** on force creation, set the balance to `ltr-starting-points` (runtime-global, default **75** — roughly 12 Deeds plus connective Trails). The remote function `reset_force` resets a force to this same value and refreshes every member's HUD (see *Interfaces*); the MTS consumer uses it when team slots are recycled.
- **Settlement charters:** the **first** time a force establishes presence on each planet, grant a lump sum of `ltr-settlement-charter` points (runtime-global, default **30**). Strictly **once per force per planet** — record granted (force index, planet name) pairs in storage (key planets by `surface.planet.name`, never by surface name literals or surface indices; see *Architecture*), so the charter can never be farmed or re-triggered, even if the force abandons the planet and returns. Rationale: it solves the new-planet cold start (a fresh planet offers no adjacent territory income and demands immediate claims), and because the trigger is team-internal progression, it is clock-fair under MTS — each team earns its charters on its own independent team clock, never in a race against other teams.

### Rejected and deferred economy mechanisms

| Mechanism | Status | Rationale |
|---|---|---|
| Adjacency-discount cost formula | Rejected | Opaque arithmetic; replaced by flat prices plus the visible adjacency rule |
| Parallel per-science-pack infinite techs | Rejected | Tech-tree clutter, research-queue spam, and an opaque alternating-exponential cost formula; the sequential chain with one linear-cost terminal tech replaces it |
| Point rewards keyed to MTS records/recognitions | Rejected | Newer records overshadow older ones, making the reward basis unstable |
| High default refund rate | Rejected | Claim → extract → refund must not be a free roundtrip; hence the 25% default |
| Appraised/survey pricing (Deed price scales with in-cell resources) | Deferred post-v1 | Ships later as a startup toggle, Deeds only, default off |
| Pacification (points for clearing enemy nests inside a cell) | Deferred post-v1 | Ships later as an optional toggle, default off |
| Depletion-aware refunds | Deferred (future, not v1) | Snapshot-at-claim, scale-by-remaining-fraction; see *Downgrades and refunds* above |

### Economy settings reference

| Setting | Scope | Type | Default | Range | Purpose |
|---|---|---|---|---|---|
| `ltr-cell-size` | startup | string | 24 | {16, 24, 32} | Cell edge length in tiles; changing on an existing save releases all claims with a full refund (ADR-0010) |
| `ltr-starting-points` | runtime-global | int | 75 | — | Initial balance granted to each force |
| `ltr-settlement-charter` | runtime-global | int | 30 | — | One-time lump sum per force per planet |
| `ltr-refund-percent` | runtime-global | int | 25 | 0–100 | Fraction of the step price refunded on downgrade |
| `ltr-points-per-level` | startup | int | 5 | — | Points granted per finished `ltr-land-grants` level |
| `ltr-tech-cost-multiplier` | startup | double | 1 | — | Global scale on the tech chain's science costs |

The deferred appraised-pricing and pacification toggles are **not** part of v1's settings surface. All defaults above are launch ballparks; exact tuning of every number in this section is an open question carried into playtesting (see *Roadmap*).

---

## Player Experience

### The Survey Tool

All claiming, upgrading, and downgrading is done with a single item: the **survey tool**.

- **Prototype:** `type = "selection-tool"`, `name = "ltr-survey-tool"`, display name "Survey Tool".
- **Flags:** `"only-in-cursor"` (the item exists only in the cursor and vanishes when the cursor is cleared — it never occupies inventory), `"not-stackable"`, plus `"spawnable"` — an engine requirement of the spawn-item flow below, implied by the design even though the original decision listed only the first two flags.
- **Never craftable:** no recipe produces it, it appears in no crafting menu, and it cannot be placed in the world or in containers. The only way to hold it is the spawn-item flow.
- **Acquisition:** two entry points, both using the engine's spawn-item action so the tool appears directly in the cursor:
  - A shortcut-bar button: `type = "shortcut"`, suggested name `ltr-get-survey-tool`, `action = "spawn-item"`, `item_to_spawn = "ltr-survey-tool"`, `associated_control_input` pointing at the custom input below.
  - A hotkey: `type = "custom-input"`, name `ltr-get-survey-tool`, `action = "spawn-item"`, `item_to_spawn = "ltr-survey-tool"`, default `key_sequence = "ALT + S"` (S for Survey — unused by vanilla, which occupies ALT+A/B/C/D/E/F/G/L/R/T/U/Y). Like every custom-input, players rebind it per-player in Settings → Controls → Mods; the default is only a default.
- **Selection modes:** the prototype defines all four `SelectionModeData` blocks (`select`, `alt_select`, `reverse_select`, `alt_reverse_select`). Give each a distinct `border_color` hinting at the target state (exact colors are art-direction work, tracked with the open border-art question under *Rendering*). `mode = {"any-entity"}` is sufficient; the script handlers derive the affected cells from `event.area` and ignore `event.entities`, so no entity filters are load-bearing. Because `selection-tool` inherits from `item-with-label`, the cursor stack has `label` and `label_color` — the balance readout described under *Hover and Cursor Feedback* depends on this.

### Selection Modes

**Redesigned during playtesting (ADR-0011): the advertised interaction is two gestures.** Four modifier-combos proved to be a memory test; and since full credit makes stepping and jumping cost the same, tier-jump modes were solving a problem the pricing had already solved.

| Mode | Event | Action on the dragged rectangle |
|---|---|---|
| select (drag) | `on_player_selected_area` | **Raise one rung**: every covered cell advances one state (Wilderness→Trail→Rampart→Deed; Deeds no-op) |
| reverse-select (right-drag) | `on_player_reverse_selected_area` | **Lower one rung**, with refund, subject to the validity check |
| alt-select (Shift-drag) | `on_player_alt_selected_area` | Unadvertised accelerator: jump to Deed with full credit |
| alt-reverse-select (Shift-right-drag) | `on_player_alt_reverse_selected_area` | Unadvertised accelerator: jump to Rampart with full credit |

"Left raises land, right lowers it." Onboarding (welcome panel, tips-and-tricks, the free starter cell with surface-drawn gesture hints) ships alongside — see ADR-0011. The remote `claim` function keeps explicit target states.

Prices, credits, the adjacency rule for new claims on Wilderness, and downgrade validity (the entity check) are specified in *Economy*; the tool applies them, it does not define them.

Handler mechanics:

- **Cell rectangle from area:** for `event.area`, the covered cells run from `floor(left_top.x / 32)` to `floor(right_bottom.x / 32)` on each axis. Cell coordinates equal Factorio's native chunk coordinates (see *Core Model*).
- **Degenerate drag:** a single click without dragging produces a zero-size rectangle inside one cell and is handled as a 1×1 batch. There is no separate click path; every rule below applies identically.
- **Eligibility filtering:** each mode acts only on cells eligible for its action, as defined by the mode itself ("claim Trail on all wilderness cells", "downgrade every owned cell"). Ineligible cells in the rectangle — e.g. a Deed cell during a Trail claim, an unowned cell during a downgrade, an owned cell that fails the downgrade entity check, are no-ops: not charged, not refunded, not modified.
- **Adjacency is a batch-level gate, not a per-cell filter.** Before eligibility is computed, the batch is tested for anchoring. A batch is anchored if **either**: the drag rectangle contains or shares an edge (4-way, never diagonal) with a cell the acting force already owns in any state; **or** the force owns no cells at all on this surface and the rectangle contains the cell the acting player is standing in. An unanchored batch applies nothing — it plays the denial sound and shows local flying text (`No adjacent territory`), rather than silently no-opping. An anchored batch proceeds, and every eligible Wilderness cell in the rectangle claims. See *Economy* for why this single test is equivalent to progressive breadth-first evaluation, and for the standing-cell clause's rationale.
- **Events:** each applied cell change raises the corresponding custom event (`on_cell_claimed` / `on_cell_downgraded`) per cell; see *Interfaces*.

### Batch Semantics: All-or-Nothing

Compute the batch's total cost over all eligible cells, including full credit for already-held tiers. If the total exceeds the force's balance:

1. Apply **nothing** — no cell in the batch changes state.
2. Play the denial sound.
3. Show local flying text at the cursor with the shortfall.

There is **no partial application, ever**. Applying "as many cells as you can afford" would make the outcome depend on internal iteration order — predictability wins over cleverness. Reverse-select batches only refund, so they can never fail the affordability check.

**Worked example.** An alt-select (Deed) drag covers a 3×2 rectangle containing 2 Wilderness cells (5 each), 2 Trail cells (+4 each), 1 Rampart cell (+2), and 1 cell already at Deed (no-op). Total: 10 + 8 + 2 = 20 points. With a balance of 17, nothing is applied, the denial sound plays, and flying text reads: `Insufficient Land points: need 20, have 17 (short 3)` — via `player.create_local_flying_text{text = ..., create_at_cursor = true}` so only the acting player sees it.

**Engine constraint to respect:** the engine fires no event mid-drag, so a live "running total" preview while dragging is impossible. Do not attempt on_tick polling workarounds. Cost feedback happens at exactly two moments: at hover (per-cell, below) and at release (the batch verdict above).

### Hover and Cursor Feedback

- **Cell state and next cost on hover.** The mechanism is a short-interval `on_nth_tick` handler registered **only while at least one player holds the survey tool**, and unregistered when the last holder puts it down — a scoped exception to the no-idle-tick rule in *Architecture*, not a violation of it. The handler resolves the hovered cell by arithmetic on the cursor position and reads the cell's state from the registry. Because prices are flat and fixed, the feedback content is static per state (Wilderness — Trail: 1 · Rampart: 3 · Deed: 5; Trail — Rampart: +2 · Deed: +4; Rampart — Deed: +2), rendered as floating text. Deed cells have no next upgrade, but this mechanism still resolves them correctly — unlike the rejected alternative below, since a Deed cell has no blocker to hover.

  **Rejected: `on_selected_entity_changed` driven by high-`selection_priority` blockers.** Under a binary claim model this would be harmless, because a blocker only ever sits on empty unclaimed land. Here blockers persist on Trail and Rampart cells full of the owner's belts, rails, and turrets, and a high-priority full-cell selection box would hijack hover, tooltips, and pipette from all of them. Blockers therefore take `selection_priority = 5`. See ADR-0005.
- **Balance on the cursor label.** While the survey tool is held, `cursor_stack.label` continuously shows the force's balance (e.g. `42 Land points`), and `label_color` turns red when the balance cannot cover the hovered cell's next-tier cost. Update the label on every points change for the holder's force and on `on_selected_entity_changed`.

### Sounds and Claim Announcements

Three distinct `sound` prototypes, played via `player.play_sound`:

| Sound | Suggested name | Trigger |
|---|---|---|
| Claim success | `ltr-sound-claim` | A claim/upgrade batch applies |
| Denial | `ltr-sound-deny` | Batch rejected for insufficient points |
| Refund | `ltr-sound-refund` | A downgrade batch applies |

**Claim announcements** (runtime-global `ltr-print-claims`, default `true`): on each applied batch, print **one** line to force chat via `force.print` — the survey-tool mark, the team label (team color, leader in brackets), the acting player in their chat color, the cell count, the cost or refund, a record clause when the batch set a cell's first or fastest Deed, and a `[gps=x,y,surface-name]` tag so teammates can click through. One line per action is a hard rule: an earlier two-line form (claim summary plus a separate chronicle line) was rejected in playtesting as noise. Using `force.print` means the message lands in the MTS team channel automatically when MTS is present, with zero MTS-specific code; it also means ODB does not relay it to Discord (by construction — see *Interfaces*).

### Remote and Map View

Factorio 2.0 selection tools function natively in remote/map view: all four modes work when dragged over the map, with identical batch semantics. No click-position workarounds are needed or permitted. Combined with the GPS-tagged announcements, territory can be managed entirely from the map.

### HUD

A per-player points readout, built with the **mod-gui** library (`mod_gui.get_frame_flow(player)`) — never a raw `screen` frame positioned by resolution arithmetic. It shows the player's force balance as "Land points: N".

- **Visibility:** runtime-per-user setting `ltr-show-points`, default `true`. Toggling it (via `on_runtime_mod_setting_changed`) creates or destroys the element.
- **Refresh triggers (all mandatory):**
  1. Every points change for the force — claims, downgrades, tech grants, settlement charters, and remote-interface `set_points`/`add_points`/`reset_force` (the latter explicitly refreshes every member's HUD; see *Interfaces*).
  2. `on_player_changed_force` — re-read the **new** force's balance.
  3. `on_player_created` and player join.
- **Why `on_player_changed_force` is non-negotiable:** MTS moves players between forces as a normal part of team join/switch/disband flows. Miss the event and every points readout silently shows the wrong force's balance, so Land Title Registry treats it as a first-class refresh trigger.

### Rendering

**Shipped early (M1.5): the wilderness overlay.** Wilderness cells draw a translucent red-ribbon pattern — diagonal ribbons, a faint wash, and a cell-edge border — implemented as the `ltr-cell-wilderness` blocker's own `picture` on the `floor` render layer (ADR-0009). Zero render objects and zero rendering code: the blocker already lives on exactly the wilderness cells and the engine draws and culls it. Claimed states carry no picture, so the reading is wilderness-is-marked, claimed-is-clear; playtesting showed that with no visual cell boundaries at all, claiming is unusable (players cannot tell where cells end or which claims landed). The sprite is generated by `tools/gen_wilderness_overlay.py`.

**Playtest refinements (post-M3).** Edge lines are colored per STATE — Trail orange, Rampart yellow, Deed green — from the same palette the ground overlays are generated from (`scripts/state_colors.lua` is the single source of truth: render.lua requires it, `tools/gen_overlays.py` parses it), while ownership identity (per-planet or MTS team color) lives on the survey stakes. Edge alpha is a two-step zoom ramp — subtle in-world (0.55), full strength on the map — because `ScriptRenderMode` is exactly `"game"|"chart"` (verified 2.0.77): no continuous zoom alpha exists, and no middle chart-zoomed-in step either. Overlays form a busy-to-calm gradient in one shared ribbon pattern — wilderness red (full strength), Trail orange (fainter), Rampart yellow (fainter still), Deed clear — so raising land one rung at a time visibly calms the ground until it goes transparent. Border lines are **inset 0.4 tiles into their own claimed side**: where two claimed states abut, both sides draw their own line in their own art, 0.8 tiles apart, so adjoining territories read as separate outlines on the map instead of merging into one shape; outer frontiers against Wilderness stay single lines, and survey stakes keep marking the true shared vertices. The starter cell is a free **Deed** granted whenever a force owns nothing on a planet and a member stands there — retrofit-safe for saves whose presence predates the feature, and doubling as recovery.

Cell borders are drawn **frontier-only**. Precisely: for every pair of orthogonally adjacent cells `a`, `b`, a border segment is drawn on their shared edge **iff** `state(a) ≠ state(b)`, where a cell absent from the registry counts as Wilderness. A solid block of Deeds therefore renders only its outline; a Trail corridor through Deed territory renders as an internal seam; the interior of any uniform region draws nothing. This makes render-object count scale with the perimeter of a claimed region rather than its area, instead of costing a fixed number of objects per chunk regardless of state (see *Architecture* for the performance rationale — MTS multiplies surfaces by team count).

- **Eager creation at claim time (M3 implementation correction — supersedes the earlier lazy-on-chart design).** Render objects derive from the registry alone, created when a cell's state changes (via the `on_cell_claimed` / `on_cell_downgraded` events) and during rebuild reconciliation. The charted-status gate was removed: frontier-only rendering already bounds object count by claim perimeter, fog of war already hides in-world renders, the per-force `forces` filter already scopes visibility, and the adjacency rule keeps a force's claims inside its explored territory in practice — while gating on chartedness made derived state depend on a second input plus an event ordering, impurifying the registry-is-the-sole-source rule (ADR-0003). On a state change, only the changed cell's four render-owning neighbors are recomputed (each cell owns its west edge, north edge, and northwest stake — so exactly four cells' owned objects cover all affected geometry). Render bookkeeping lives per surface in `storage`; surfaces flagged in `storage.disabled_surfaces` get no grid at all.
- **Two render families:** chart-view (map) renders, plus in-world renders created with `only_in_alt_mode = true` so the in-world grid appears only in alt-mode.
- **Per-force visibility:** every `LuaRenderObject` is created with its `forces` filter set to the owning force, so each force sees only its own claims.
- **Colors:** with MTS active, use the team color obtained via the `mts-v1` interface (see *Interfaces*). Otherwise, use per-planet color settings looked up by `surface.planet.name` — **never** `surface.name` string literals and **never** surface-index sentinels like `[1]` or `[-1]`. Suggested setting pattern: one color per planet (e.g. `ltr-color-nauvis`), runtime-global; color changes re-tint existing objects via the temporary `on_nth_tick` batching described in *Architecture*. Space-platform surfaces are auto-disabled and render nothing (see *Interfaces*).
- **Per-state border art:** each state gets visually distinct border art. **Open:** art direction — e.g. Trail dashed, Rampart crenellated, Deed solid.
- **Survey stakes:** small stake-marker sprites at frontier corners (vertices touched by at least one frontier edge), sharing the border's color and `forces` filter. These corner survey stakes are the mod's visual signature — the identity work that square cells delegate to rendering (see *Core Model*).

### UX Settings

| Setting | Scope | Type | Default | Purpose |
|---|---|---|---|---|
| `ltr-show-points` | runtime-per-user | bool | `true` | Show/hide the points HUD |
| `ltr-print-claims` | runtime-global | bool | `true` | Force-chat claim announcements with GPS tags |
| per-planet border colors (e.g. `ltr-color-nauvis`, one per planet) | runtime-global | color | per-planet defaults | Border and stake tint when MTS is absent |

Pricing, refund, and income settings (`ltr-refund-percent`, `ltr-starting-points`, `ltr-settlement-charter`, `ltr-points-per-level`, `ltr-tech-cost-multiplier`) are specified in *Economy*. The survey-tool hotkey is a Factorio control binding (custom-input), not a mod setting; its default key is an open question (see *The Survey Tool*).

---

## Technical Architecture

### Registry as the single source of truth

All persistent mod state lives in `storage` (Factorio 2.0; never `global`). The cell registry is the authoritative record of every claimed cell. Blocker entities and render objects are **derived state**: they must always be reconstructible from the registry alone, and no code path may treat the presence or absence of a blocker or render as authoritative. If the registry and the world ever disagree, the registry wins and the world is rebuilt to match it.

Wilderness cells are deliberately **not** stored: absence of a registry entry means Wilderness. This keeps the registry proportional to claimed land, not to explored land.

#### Storage schema

```lua
storage = {
  meta = {
    version = 1,          -- save-data schema version; bumped by migrations
  },

  points = {
    -- [force_index] = number (Land points balance, see *Economy*)
    [2] = 41,
  },

  cells = {
    -- [surface_index][cell_key] = cell record
    -- ABSENCE of a key means Wilderness.
    [1] = {
      [cell_key(4, -2)] = {
        state           = "trail",     -- "trail" | "rampart" | "deed"
        force_index     = 2,
        claimed_tick    = 1234567,
        invested_points = 1,           -- total points sunk into this cell (basis for refunds)
        claimant        = "engineer_7" -- optional: name of the claiming player
      },
    },
  },

  -- Blocker bookkeeping: registration ids from script.register_on_object_destroyed,
  -- mapped back to their cell for cleanup in on_object_destroyed.
  blocker_registrations = {
    -- [registration_id] = { surface_index = 1, cell_key = ... }
  },

  -- Render bookkeeping, per surface: LuaRenderObject references (2.0 rendering
  -- returns objects, not numeric ids; storing the objects in storage is the
  -- idiomatic pattern) for frontier edges and corner survey stakes, organized
  -- so a cell's edges can be found and invalidated when a neighbor changes state.
  renders = {
    -- [surface_index] = { ... implementation-defined index ... }
  },

  disabled_surfaces = {
    -- [surface_index] = true  => surface gets no blockers and no grid at all
    -- (set via the remote interface, see *Interfaces*; used for MTS landing
    -- pens, scenario lobbies, and auto-disabled space platforms)
  },
}
```

Notes:

- Cell coordinates are identical to chunk coordinates (1 cell = 1 chunk footprint, see *Core Model*). The cell center in tile coordinates is `{cx * 32 + 16, cy * 32 + 16}`; blockers are looked up with `surface.find_entity(blocker_name, cell_center)` when operating on a cell — the registry never stores entity references.
- `invested_points` records cumulative spend so downgrades can refund the correct step price (see *Economy*).
- **`cell_key` encoding — resolved: the packed integer.** `cell_key(x, y) = (x + 0x8000) * 0x10000 + (y + 0x8000)`, valid for cell coordinates in ±32k — comfortably covering the ±1M-tile map limit (±31.25k cells). Compact in saves and fast to compare. Wrapped in `cell_key(x, y)` / `cell_key_to_pos(key)` helpers in `scripts/registry.lua` and used nowhere else directly; the encoding is persisted in `storage.cells`, so changing it later means a migration.

#### Derived state and recovery: `/ltr-rebuild`

A console command `/ltr-rebuild` reconciles the world with the registry, as the recovery path for any drift (mod bugs, other mods deleting entities, partial surface clears):

1. For every enabled, generated surface, iterate generated chunks; for each cell, compute the expected blocker (`ltr-cell-wilderness` / `ltr-cell-trail` / `ltr-cell-rampart`, or none for Deed — see *Core Model*) from the registry.
2. Destroy wrong or duplicate blockers, create missing ones, and re-register `on_object_destroyed` registrations.
3. Destroy and lazily recreate render objects for charted cells.

Large rebuilds run through the batched `on_nth_tick` queue described below, never in a single tick.

### Event handler inventory

| Event | Responsibility (one line) |
|---|---|
| `on_chunk_generated` | Spawn the blocker **matching the cell's registered state** — wilderness if the cell is absent from the registry, `ltr-cell-trail` / `ltr-cell-rampart` if registered, none if Deed — unless the surface is disabled. Do **not** skip registered cells: the only way a chunk generates for a registered cell is a surface regeneration, and skipping would leave that cell with no blocker, which is exactly how Deed is represented. Spawning by registered state is uniformly correct and handles regeneration for free. |
| `on_chunk_charted` | **Not handled.** Renders are created eagerly at claim time from the registry alone (see *Player Experience*, Rendering) — the lazy-on-chart design was superseded during M3. |
| `on_surface_created` | Initialize per-surface tables (`cells`, `renders`). |
| `on_surface_cleared` | Drop **everything** for that surface: the claim registry entries, blocker registrations, and render bookkeeping. A surface clear is an out-of-band administrative reset, not a gameplay action; leaving a force owning Deeds over regenerated wilderness with none of its buildings is incoherent. No refund is paid — Land Title Registry returns the surface to a consistent wilderness state rather than trying to price an operation it did not initiate. MTS deletes surfaces rather than clearing them, so this path is rare. |
| `on_surface_deleted` | Delete all per-surface keys from `storage`. |
| `on_force_created` | Initialize `storage.points[force.index]` with the starting grant (see *Economy*). |
| `on_forces_merged` | Sum balances into the destination, reassign every source cell's `force_index`, union charter records, refresh affected renders, raise `on_points_changed` with reason `"merge"`. Disjoint by construction — no conflict resolution needed. See *Economy*. |
| `on_player_created` | Build the per-player HUD (see *Player Experience*). |
| `on_player_changed_force` | Rebind the player's HUD to the new force's balance — mandatory, MTS moves players between forces and a HUD bound to the old force is silently wrong. |
| `on_research_finished` | Credit points for completed `ltr-land-grants-N` levels. |
| `on_research_reversed` | Debit points correctly, **including infinite-tech levels** — the case that is easiest to miss and the one the test suite pins. |
| `on_player_selected_area` | Survey tool: claim Trail on all Wilderness cells in the rectangle (all-or-nothing batch). |
| `on_player_alt_selected_area` | Survey tool: claim/upgrade to Deed with full credit for held rights. |
| `on_player_reverse_selected_area` | Survey tool: downgrade every owned cell one step, with refund. |
| `on_player_alt_reverse_selected_area` | Survey tool: claim/upgrade to Rampart. |
| `on_object_destroyed` | Clean up `blocker_registrations` for destroyed blockers (registered via `script.register_on_object_destroyed`). |
| `on_runtime_mod_setting_changed` | Re-read runtime settings (`ltr-refund-percent`, `ltr-print-claims`, `ltr-show-points`) and refresh HUDs where relevant. |
| `on_configuration_changed` | Run migrations against `storage.meta.version`; iterate **all** forces and all surfaces, never just one. |

`control.lua` is a thin dispatcher: it wires these events to the modules under `scripts/` and contains no logic itself.

### No unconditional `on_tick`

Land Title Registry registers **no** unconditional `on_tick` handler. All steady-state work is event-driven. Work that is too large for one tick — mass re-tints after a team color change, `/ltr-rebuild` reconciliation — uses a temporary `on_nth_tick` pattern:

1. Enqueue work items into a queue held in `storage` (so a save mid-batch is deterministic).
2. Register `script.on_nth_tick(n, handler)`; the handler drains a bounded slice per invocation.
3. When the queue is empty, unregister with `script.on_nth_tick(n, nil)`.
4. In `on_load`, re-register the handler if and only if the persisted queue is non-empty.

### Multi-force / multi-surface correctness

Multi-force and multi-surface correctness is a design pillar, not a compatibility afterthought. Land Title Registry implements all six patterns from MTS's published COMPAT.md as hard requirements:

| # | COMPAT.md pattern | Land Title Registry application |
|---|---|---|
| 1 | Never `game.forces.player`; always the acting force | Claims, grants, refunds, and HUDs operate on the force taken from the triggering event (`player.force`, `research.force`), never a hardcoded force. |
| 2 | Never hardcode surface names or indices; derive from `surface.planet.name` | Per-planet border colors key off `surface.planet.name` — never `surface.name` literals, never surface-index sentinels like `[1]` or `[-1]`. |
| 3 | Key persistent state by force index AND surface index | `storage.points` is keyed by force index; `storage.cells`, `renders`, and `disabled_surfaces` are keyed by surface index; cell records carry `force_index`. |
| 4 | Iterate all forces for global effects | Migrations, setting changes, and grant recalculations loop `game.forces` — never touch a single named force. |
| 5 | Expose runtime rules via the remote interface | The `land-title-registry` remote interface (see *Interfaces*) ships stable from v1 so other mods can query and drive claims, points, and surface enablement. |
| 6 | Emit custom events for lifecycle hooks | `on_cell_claimed`, `on_cell_downgraded`, and `on_points_changed` are raised via `script.raise_event` with ids from `script.generate_event_name` (see *Interfaces*). |

The stated goal is that MTS ships **no** compat shim for Land Title Registry; Land Title Registry is the reference consumer of these patterns.

### Shared-surface limitation (stated honestly)

Blocker collision is global per surface. On a surface where **multiple forces build**, engine-level enforcement cannot distinguish forces: a Deed cell has no blocker, and an absent blocker blocks nobody — any force could build there. v1 therefore targets the one-building-force-per-surface model, which covers vanilla play and MTS's per-team surface isolation exactly; in that model enforcement is precise and entirely engine-level. Script-side cross-force exclusion on shared surfaces is possible future work and is explicitly **out of v1 scope**. Document this limitation plainly in the mod description; do not paper over it.

### Performance analysis

- **Blockers:** at most one entity per non-Deed cell. Deed cells contribute zero entities.
- **Renders:** borders are drawn **frontier-only** — a render object exists only on edges where the two adjacent cells' states differ. A large contiguous claimed region costs render objects proportional to its perimeter, not its area, rather than a fixed count per chunk regardless of state. Renders are created lazily as chunks are charted, and the per-force `forces` filter on each `LuaRenderObject` keeps other forces' claims invisible without duplicate draw work.
- **Design driver:** MTS multiplies surfaces by team count. Every per-cell cost is paid once per team-surface, so constant factors that are tolerable in a single-force game become the dominant cost under MTS. Frontier-only rendering and the no-`on_tick` rule exist because of this multiplication.

### Migrations posture

The `migrations/` folder exists from day one, even if initially empty. `storage.meta.version` records the save-data schema version; `on_configuration_changed` compares it to the current version and applies ordered migration steps, iterating all forces and all surfaces. Any change to the storage schema, blocker prototypes, or render scheme ships with a migration in the same release.

### File layout

```
land-title-registry/
├── info.json
├── settings.lua
├── data.lua
├── data-updates.lua
├── data-final-fixes.lua        -- collision-layer assignment + host/mod-data overrides
├── control.lua                 -- thin event dispatcher only
├── scripts/
│   ├── registry.lua            -- cell registry, cell_key helpers
│   ├── claims.lua              -- claim/upgrade/downgrade, adjacency, batch semantics
│   ├── economy.lua             -- points, prices, refunds, settlement charters
│   ├── tech.lua                -- ltr-land-grants handling, research reversal
│   ├── tool.lua                -- survey tool selection events, shortcut, hotkey
│   ├── render.lua              -- frontier borders, survey stakes, lazy creation
│   ├── hud.lua                 -- mod-gui points readout
│   └── commands.lua            -- /ltr-rebuild (and later /ltr-stats)
├── compat/
│   ├── mts.lua                 -- guarded by script.active_mods["multi-team-support"]
│   └── odb.lua                 -- guarded by script.active_mods["open-discord-bridge"]
├── prototypes/
│   ├── layers.lua              -- ltr-land, ltr-transit, ltr-rampart
│   ├── blockers.lua            -- ltr-cell-wilderness / -trail / -rampart
│   ├── tool.lua                -- ltr-survey-tool
│   ├── tech.lua                -- ltr-land-grants-N chain
│   ├── shortcut.lua
│   ├── sprites.lua
│   └── styles.lua
├── locale/en/
├── graphics/
├── migrations/
└── docs/
```

### info.json draft

```json
{
  "name": "land-title-registry",
  "title": "Land Title Registry",
  "factorio_version": "2.0",
  "dependencies": [
    "base >= 2.0",
    "? multi-team-support",
    "? space-age",
    "? open-discord-bridge"
  ]
}
```

MTS, Space Age, and Open Discord Bridge are **optional** dependencies (the `"MTS "` title-prefix convention signals a hard dependency and is therefore not used — see *Overview & Identity*). Goal: **no incompatibility list, ever** — composability is the brand. Compatibility problems are solved via the layer-override channels (see *Interfaces*), not by declaring incompatibilities.

### Milestones

| Milestone | Scope |
|---|---|
| **M1 — Core** | Collision layers, blockers, registry, Trail/Deed claim + downgrade, survey tool, flat pricing, adjacency rule. |
| **M2 — Economy** | Rampart tier, `ltr-land-grants` tech chain, starting grant, settlement charters, refund rate, claim announcements. |
| **M3 — Polish** | Border art, HUD, sounds, locale. |
| **M4 — Integration** | Remote API, custom events, mod-data layer overrides, MTS consumer, ODB integrator, territory stats. |
| **M5 — Beta** | Playtesting, numeric tuning, migrations, portal release. |

### Testing matrix

Configuration axes — every cell of the cross product gets a pass:

| Axis | Values |
|---|---|
| Base game | vanilla, Space Age |
| Player count | solo, multiplayer |
| MTS | absent; present — including team create/disband, slot recycling, landing pen, force switching |
| ODB | absent, present |

Scenario checks run within that matrix:

- **Multiplayer determinism:** all state in `storage`; no non-deterministic sources (`math.random` without shared state, real time, per-client data) in any state-mutating path.
- **Save/load roundtrip:** including a save taken mid-`on_nth_tick` batch (queue persists, handler re-registers in `on_load`).
- **`on_configuration_changed` upgrades:** migrations apply across all forces and surfaces.
- **Building against every cell state:** manual placement, blueprints, and construction bots versus Wilderness/Trail/Rampart/Deed for entities of each layer.
- **Tile placement is unrestricted:** landfill, concrete, and foundation place and mine identically in every cell state, and no Land Title Registry layer appears on any tile prototype (see *Core Model*, Tiles Are Not Gated).
- **Research reversal:** `on_research_reversed` decrements grants correctly, including infinite-tech levels.
- **Editor mode:** no crashes or registry corruption under editor surface/entity manipulation.

---

## Interfaces & Integration

Land Title Registry is built to be built on. Every runtime rule is reachable through the remote interface `"land-title-registry"`, everything that happens is announced through custom events, and collision-layer membership is overridable by hosts and by other mods without a Land Title Registry release. The dependency stance is deliberately soft — `info.json` declares `"? multi-team-support"`, `"? space-age"`, and `"? open-discord-bridge"` as optional dependencies, all runtime integration sits behind `script.active_mods` guards, and the explicit goal is that Land Title Registry ships **no incompatibility list**. Composability is the brand.

### Remote interface `land-title-registry`

Registered via `remote.add_interface("land-title-registry", ...)` at `control.lua` root scope. The interface is documented and stable from v1: signatures below are a compatibility contract, not an implementation detail.

Conventions used by the functions:

- `cell_pos` is a `{x, y}` table in **cell coordinates**, which are identical to Factorio's native chunk coordinates (cell `(x, y)` covers tiles `[32x, 32x+31] × [32y, 32y+31]`; see *Core Model*).
- `surface` and `force` parameters take the runtime objects (`LuaSurface`, `LuaForce`); the points functions take a plain `force_index` for symmetry with the `storage.points[force_index]` schema (see *Architecture*).
- State strings match the registry exactly: `"trail"`, `"rampart"`, `"deed"` (absence from the registry means Wilderness).
- Functions returning `ok, reason` return `true, nil` on success, or `false` plus a short string explaining the refusal.

| Function | Returns | Behavior |
| --- | --- | --- |
| `get_points(force_index)` | `number` | Current Land-points balance of the force. Plain number, not an integer — refund arithmetic can leave fractional balances (see *Economy*). |
| `set_points(force_index, points)` | — | Sets the balance outright. Raises `on_points_changed`. |
| `add_points(force_index, delta)` | — | Adjusts the balance by `delta` (may be negative). Raises `on_points_changed`. |
| `reset_force(force_index)` | — | Resets the balance to the starting grant (`ltr-starting-points`) and refreshes the HUD of every member of the force. See rationale below. |
| `claim(surface, cell_pos, force, target_state, opts)` | `ok, reason` | Programmatic claim/upgrade of one cell to `target_state`. Applies exactly the survey tool's rules: flat step prices with full credit for already-held rights, adjacency check for new claims on Wilderness, Trail as strict prerequisite for Rampart, disabled-surface check (pricing in *Economy*). `opts` is an optional table; omit it or pass `nil` in normal use. |
| `downgrade(surface, cell_pos, force, opts)` | `ok, reason` | Downgrades one cell one step with refund (step price × `ltr-refund-percent` / 100, default 25%), subject to the downgrade validity check — the cell must contain no entities requiring the revoked right (see *Economy*). |
| `get_cell(surface, cell_pos)` | `nil` or table | Registry record `{state, force_index, claimed_tick, invested_points}`. `nil` means Wilderness. |
| `get_territory_stats(force_index, opts)` | table | `{trails, ramparts, deeds}` counts across all surfaces. With `opts = {by_surface = true}`, additionally includes `by_surface = {[surface_index] = {trails, ramparts, deeds}}`. A call-time option rather than a mod setting, deliberately: different consumers want different shapes simultaneously (an MTS scoreboard wants the breakdown, a HUD wants cheap totals), and both shapes are frozen contract members from v1. |
| `set_surface_enabled(surface, enabled)` | — | A disabled surface gets no blockers and no grid at all (`storage.disabled_surfaces`, see *Architecture*). Intended for MTS landing pens, scenario lobbies, and similar special surfaces. Behavior on re-enabling a previously disabled surface (e.g. reconciling blockers/renders from the registry, as `/ltr-rebuild` does) is an implementation question. |
| `get_surface_enabled(surface)` | `boolean` | Whether Land Title Registry's grid is active on the surface. |
| `get_event_id(name)` | `uint` | Resolves a custom-event name (below) to this session's event id. |

**Why `reset_force` exists.** MTS recycles team slots: a slot vacated by one team is handed to the next. Without an explicit reset the new occupant inherits the previous one's point balance, which is both an unfair head start and a confusing one — nothing in the UI explains where the points came from. Declaring the function is not enough; an integrator calling a `reset_force` that silently no-ops is worse off than one that gets an error, because the bug is invisible. Land Title Registry therefore ships `reset_force` implemented and exercised from day one, with the exact semantics an integrator needs: balance back to the starting grant, HUDs refreshed immediately for every member.

### Custom events

Land Title Registry generates its event ids with `script.generate_event_name()` at `control.lua` root scope and raises them with `script.raise_event`. Payloads (in addition to the engine-supplied `name` and `tick` fields):

| Event name | Payload | Raised when |
| --- | --- | --- |
| `on_cell_claimed` | `surface_index` (uint), `cell_pos` (`{x, y}` cell coords), `force_name` (string), `old_state` (string), `new_state` (string), `player_index` (uint, optional — absent for scripted claims with no acting player), `cost` (uint, points charged) | A cell is claimed or upgraded, whether by the survey tool or by the remote `claim` function. |
| `on_cell_downgraded` | `surface_index`, `cell_pos`, `force_name`, `old_state`, `new_state`, `refund` (number, points refunded — may be fractional), `player_index` (optional) | A cell is downgraded one step. |
| `on_points_changed` | `force_name` (string), `points` (number, new balance), `delta` (int), `reason` (short string identifying the source, e.g. a claim, refund, research grant, settlement charter, or remote call) | Any change to a force's balance, from any source. |

**The lookup pattern.** Event ids are regenerated every session and must **never** be stored — not in Land Title Registry's `storage`, not in a consumer's. **Corrected during M4 against the real engine:** Factorio 2.0 rejects `remote.call` at `control.lua` root scope ("Attempt to remote call outside of an event") but **allows it in `on_load`** (the 1.1-era prohibition is gone — verified empirically 2026-08-05). The correct consumer pattern is therefore a `resolve()` function called from **both `on_init` and `on_load`** — the two entry points that run before any events each session — that resolves ids via `get_event_id` and subscribes with `script.on_event`. The `"? land-title-registry"` optional dependency guarantees Land Title Registry's interface is registered by then. Storing an id in `storage` remains a save-corruption bug: the number can differ on the next load. Land Title Registry's own `compat/mts.lua` is the reference implementation of this pattern.

**Why events beat polling.** This follows MTS's published COMPAT.md patterns 5 and 6 — expose runtime rules through a remote interface so other mods can reuse them, and emit custom events for lifecycle hooks. An integrator receives a push at the exact tick of the change with full context in the payload (transition, actor, cost/refund) instead of running `on_tick`/`on_nth_tick` loops that diff territory snapshots. Land Title Registry itself has no unconditional `on_tick` handler (see *Architecture*), and its event surface is what keeps that discipline from being undone downstream: nothing about Land Title Registry's state requires any consumer to poll.

### Layer-membership overrides

Collision masks are fixed at prototype-load time — layer membership cannot change at runtime (see *Core Model*). Both override channels are therefore data-stage/startup-scope, applied in Land Title Registry's `data-final-fixes.lua` on top of the default layer assignment.

**Host channel — startup string settings.**

| Setting | Scope | Effect |
| --- | --- | --- |
| `ltr-transit-additions` | startup, string | Entries are moved into the transit layer. |
| `ltr-transit-removals` | startup, string | Entries are removed from transit and revert to land. |
| `ltr-rampart-additions` | startup, string | Entries are moved into the rampart layer. |
| `ltr-rampart-removals` | startup, string | Entries are removed from rampart and revert to land. |

Syntax: comma-separated entries; each entry is either an entity prototype name (`heat-pipe`) or a prototype type with the `type:` prefix (`type:storage-tank`). Removals always send an entity back to **land** — land is the universal default, and the invariant holds throughout: every player-buildable prototype ends up in exactly one layer. Example server configuration:

```
ltr-transit-additions = heat-pipe, type:storage-tank
ltr-rampart-removals  = solar-panel
```

**Mod channel — the mod-data convention (resolved).** Factorio 2.0's `mod-data` prototype exists for exactly this, and its `data_type` field is documented as the cross-mod discovery mechanism: *"Arbitrary string that mods can use to declare type of data. Can be used for mod compatibility when one mod declares block of data that is expected to be discovered by another mod."*

So the convention is **not** one shared prototype name. Each declaring mod creates **its own** `mod-data` prototype, named however it likes, and tags it:

```lua
data:extend({{
  type      = "mod-data",
  name      = "my-rail-mod-land-title-registry-layers",   -- any unique name
  data_type = "land-title-registry-layers",               -- the discovery key
  data = {
    transit = { "mrm-maglev-rail", "mrm-monorail-track" },
    rampart = { "mrm-guard-tower" },
    land    = { "mrm-depot" },                 -- pin against type defaults
  },
}})
```

Land Title Registry's `data-final-fixes.lua` then scans `data.raw["mod-data"]` for every prototype whose `data_type` is `"land-title-registry-layers"` and applies them all. This dissolves the name-collision problem the earlier lean worried about: no two mods contend for a prototype name, there is no get-or-create merge dance, and declaration order between mods is irrelevant.

Each list holds entity prototype names or `type:` entries; an explicit `land` list pins entities to land against Land Title Registry's type-based defaults.

**One requirement for declaring mods:** declare in `data.lua` or `data-updates.lua`, never in `data-final-fixes.lua`. A mod that declares `"? land-title-registry"` for load order loads *after* Land Title Registry, so a declaration made in its own `data-final-fixes.lua` would arrive too late to be read. The mod-data channel needs no dependency declaration at all — only the event-consumption channel does.

**Precedence:** Land Title Registry defaults < mod-data declarations < host settings. The host always has the final word.

**What this replaces.** The obvious implementation is a hand-written blacklist of other mods' entity names, kept inside this mod's own code. That is a maintenance treadmill: every new mod release outside the list produces wrong behavior until this author ships an update, and the list is always stale by exactly the lead time of a release. Land Title Registry inverts the ownership instead — defaults are capability-based wherever possible (see *Core Model*), mod authors declare their own entities through mod-data, and hosts override anything. No release of Land Title Registry is needed for a third-party mod to classify itself correctly.

### Multi-Team Support (MTS) integration

MTS is an optional dependency. All MTS-specific code lives in `compat/mts.lua` behind `script.active_mods["multi-team-support"]` guards (with a defensive `remote.interfaces["mts-v1"]` check before calling).

- **Team lifecycle.** Land Title Registry consumes the `mts-v1` interface: it resolves MTS's `on_team_created` and `on_team_released` custom events via MTS's `get_event_id` (the same resolve-every-session, never-store rule as Land Title Registry's own events) and resets points for recycled team slots — internally the same routine as `reset_force`. Without this, a force slot recycled to a new team would inherit the previous team's balance.
- **Team colors.** Border renders use the team color obtained via `mts-v1` instead of the per-planet color settings used without MTS (see *Player Experience*).
- **Landing pen / lobby surfaces — resolved: Land Title Registry queries, MTS ships nothing.** With MTS active, `compat/mts.lua` enables the grid **only on team surfaces**, determined by calling `mts-v1`'s existing `is_team_surface` / `get_surface_owner` functions as surfaces are created (and on init for existing surfaces). The landing pen is not a team surface, so it gets no grid — and neither does any special surface MTS invents later, with no enumeration of surface roles anywhere. This needs no new `mts-v1` functions and keeps the no-shim rule absolute: MTS contains not a single line about Land Title Registry, not even a `set_surface_enabled` call.
- **Territory stats.** MTS records and scoreboards consume `get_territory_stats` and subscribe to the `on_cell_claimed` event stream. Land Title Registry pushes nothing MTS-specific; the generic surface is enough.
- **Free composition elsewhere.** Claim announcements use `force.print`, which lands in the MTS team chat channel automatically; the HUD handles `on_player_changed_force` because MTS moves players between forces (both in *Player Experience*). Under MTS's per-team surface isolation, blocker enforcement is exact (see the shared-surface limitation in *Architecture*).

**The no-shim goal.** MTS ships **nothing** for Land Title Registry — no compat file, no special-casing. Integration flows one way, with Land Title Registry consuming `mts-v1`. Land Title Registry is the reference consumer of MTS's COMPAT.md patterns: always the acting force, never `game.forces.player`; surfaces derived from `surface.planet.name`, never hardcoded names or indices; state keyed by force index and surface index; all forces iterated for global effects; rules exposed via remote; lifecycle hooks emitted as custom events. If Land Title Registry ever needs a shim inside MTS, that is a Land Title Registry bug.

### Open Discord Bridge (ODB) integration

ODB (mod name `"open-discord-bridge"`, same author as MTS) mirrors chat and events between a Factorio server and Discord using a companion mod plus an external bridge process. The companion mod owns the **frozen** remote interface `"open-discord-bridge-v1"`:

| Function | Purpose |
| --- | --- |
| `emit{event, data, surface}` | Push an outbound namespaced event (e.g. `"land-title-registry.settlement_charter"`) to the bridge. |
| `register_source{namespace, events}` | Declare an event catalog so the bridge can offer per-event routing toggles without hardcoding any mod. |
| `set_baseline{event, enabled}` | Let an integrator take over one of ODB's built-in baseline announcements. |
| `get_event_id("on_incoming")` | Custom event for inbound Discord messages. |
| `linked_discord_id(player_name)` | Resolve a player's linked Discord account. |

Channel routing on the bridge side supports exact event keys, namespace globs (`"land-title-registry.*"`), and a catch-all.

**Compatible by construction.** Land Title Registry works with ODB out of the box with zero integration code, because the two mods share no systems: Land Title Registry intercepts no chat, writes no files, and emits no baseline events; claim announcements go through `force.print`, which ODB does not relay. The integrator module below is additive polish, not a compatibility requirement.

**The integrator module `compat/odb.lua` (v1, optional).** All behind `script.active_mods["open-discord-bridge"]` guards.

- At initialization, calls `register_source` with `namespace = "land-title-registry"` and the event catalog, so hosts get per-event routing toggles in the bridge.
- Emits **only low-frequency milestone events by default** — the anti-spam principle. Suggested catalog keys:

| Event key | Fired when |
| --- | --- |
| `land-title-registry.settlement_charter` | A force's first presence on a planet grants the settlement charter (see *Economy*). |
| `land-title-registry.first_deed` | A force's first Deed on each planet. |
| `land-title-registry.territory_milestone` | A force's Deed count on a planet crosses a multiple of 25 (25, 50, 75, …), tracked per force per planet. |

- Per-claim emission does not exist in v1 — not even behind a setting. Adding an opt-in later is additive; removing spam is not. (Resolved from the former open question.)
- No `set_baseline` takeovers in v1.

**Known interaction to document for hosts.** ODB's baseline `research_finished` announcement fires for every completed `ltr-land-grants-N` level, which can read as Discord spam late-game (the terminal tier is infinite). Mitigations: hosts can mute or reroute `research_finished` through ODB's channel routing; a Land Title Registry-enriched research takeover via `set_baseline` is a future consideration only, not v1.

**v1.x nicety.** An RCON-safe `/ltr-stats` console command printing territory stats as JSON via `rcon.print`, so hosts can wire ODB's configurable Discord-to-RCON commands to query Land Title Registry from Discord.

Land Title Registry thereby dogfoods both of the author's platform mods — MTS for multi-team and ODB for Discord — as their reference consumer.

### Space Age

- **Planet-science tech tiers** (grouping of the planet packs is open) and **per-planet settlement charters**: see *Economy*.
- **Space platforms are exempt from the grid entirely.** Platform surfaces are auto-disabled through the same mechanism as `set_surface_enabled` — no blockers, no renders — because platform tiles already constrain building. Platform-specific entities (`space-platform-hub`, `cargo-pod-container`) are additionally layer-exempt (see *Core Model*).
- **Elevated rails are transit like all rails in v1.** "Crossing rights" — elevated rails permitted over Wilderness — is a future consideration only.

### Cookbook for third-party mod authors

**1. Declare your entities' layers (data stage).** Create your *own* `mod-data` prototype and tag it with `data_type = "land-title-registry-layers"`. Land Title Registry discovers every prototype carrying that tag — you never contend with another mod for a prototype name, and declaration order between mods does not matter.

```lua
-- data-updates.lua of "my-rail-mod"
data:extend({{
  type      = "mod-data",
  name      = "my-rail-mod-land-title-registry-layers",  -- any name you like; keep it unique
  data_type = "land-title-registry-layers",              -- the discovery key Land Title Registry scans for
  data = {
    transit = { "mrm-maglev-rail", "mrm-monorail-track" },  -- names, or "type:<engine-type>"
    rampart = { "mrm-guard-tower" },
    land    = { "mrm-depot" },                -- pin to land against type-based defaults
  },
}})
```

Declare from `data.lua` or `data-updates.lua`, **never** from `data-final-fixes.lua` — a mod that declares `"? land-title-registry"` loads after Land Title Registry, so a declaration made in its own final-fixes stage would arrive too late to be read. No dependency declaration is needed for this channel at all.

Host settings still win over your declaration (precedence: defaults < mod-data < host settings). Every entity ends in exactly one layer.

**2. Consume Land Title Registry's events (control stage).** Resolve ids in `on_init` **and** `on_load`, never at root scope (2.0 rejects root-scope `remote.call`; it allows it in `on_load`) and never stored in `storage`.

```lua
-- control.lua of an integrating mod (declare "? land-title-registry" for load order)
local function resolve_ltr_events()
  if not remote.interfaces["land-title-registry"] then return end
  local on_cell_claimed =
    remote.call("land-title-registry", "get_event_id", "on_cell_claimed")
  script.on_event(on_cell_claimed, function(e)
    -- e: surface_index, cell_pos, force_name, old_state, new_state,
    --    player_index (optional), cost
    if e.new_state == "deed" then
      game.forces[e.force_name].print(
        {"my-mod.deed-message", e.cell_pos.x, e.cell_pos.y})
    end
  end)
end
script.on_init(resolve_ltr_events)
script.on_load(resolve_ltr_events)
-- Never write the event id to storage: ids are regenerated every session.
```

**3. Drive the economy and claims programmatically (scenarios, quest mods).**

```lua
-- Reward a player's force with points and a Deed on the cell they stand in.
local force = player.force
remote.call("land-title-registry", "add_points", force.index, 10)

local cell_pos = {                         -- tile position -> cell coordinates
  x = math.floor(player.position.x / 32),
  y = math.floor(player.position.y / 32),
}
local ok, reason = remote.call("land-title-registry", "claim",
  player.surface, cell_pos, force, "deed")
if not ok then
  player.print("Claim refused: " .. reason)
end
```

The remote `claim` charges the same flat prices with full credit and enforces the same adjacency and prerequisite rules as the survey tool — a scenario cannot accidentally create cells the tool could not. To keep a special surface grid-free (a custom lobby, a minigame arena), call `remote.call("land-title-registry", "set_surface_enabled", my_surface, false)` before chunks generate on it.

---

## Scope, Roadmap, and Decision Log

### v1 Scope

v1 ships the complete land-rights core: the fixed 32x32 cell grid with the Wilderness -> Trail -> Rampart -> Deed ladder (*Core Model*), engine-enforced building rights via the three collision layers and per-cell blockers (*Core Model*), the flat-price points economy with adjacency, refunds, the `ltr-land-grants-N` tech chain, starting grants, and settlement charters (*Economy*), the survey tool with its four all-or-nothing selection modes plus HUD, frontier-only border rendering, and feedback sounds (*Player Experience*), the registry-as-source-of-truth storage schema with `/ltr-rebuild` recovery and a migrations folder from day one (*Architecture*), and the full `land-title-registry` remote interface, custom events, startup layer-override channels, and the optional MTS and ODB integration modules (*Interfaces*). Implementation proceeds through milestones M1 (core) through M5 (beta/release) as laid out in *Architecture*. Explicitly out of v1: script-side cross-force exclusion on shared surfaces (v1 targets the one-building-force-per-surface model, where blocker enforcement is exact), appraised pricing, pacification rewards, depletion-aware refunds, and every v1.x/v2 item below.

**v1 checklist:**

- [x] Collision-layer prototypes `ltr-land`, `ltr-transit`, `ltr-rampart`; every player-creation assigned to exactly one layer in `data-final-fixes.lua` via collision-mask-util
- [x] Blocker prototypes `ltr-cell-wilderness`, `ltr-cell-trail`, `ltr-cell-rampart` (simple-entity-with-owner, ~31.98-tile collision box; `force = "neutral"` passed at `create_entity`, `destructible = false` set at runtime); no blocker for Deed
- [x] Registry: `storage.cells[surface_index][cell_key]`, `storage.points[force_index]`, blocker registration ids, `storage.disabled_surfaces`, `storage.meta.version`
- [x] Survey tool `ltr-survey-tool` (shortcut + custom-input, only-in-cursor, not-stackable), four selection-mode actions, all-or-nothing batch semantics with shortfall flying text
- [x] Flat pricing with full credit (Trail 1, Rampart 3, Deed 5), adjacency rule at claim time, downgrade validity via one `find_entities_filtered` query, refunds at `ltr-refund-percent` (default 25)
- [x] Tech chain `ltr-land-grants-*` derived from the tech DAG (+ Space Age planet tiers), linear `count_formula` terminal tier, correct `on_research_reversed` decrement (finish-then-reverse asserted net zero in-engine)
- [x] Starting grant `ltr-starting-points` (75), settlement charter `ltr-settlement-charter` (30, once per force per planet; the force's first — home — planet is recorded silently, its cold start being covered by the starting grant)
- [x] HUD via mod-gui, `ltr-show-points` per-user setting, refresh on points change / force change (`on_player_changed_force`) / player join and create (`on_player_created`)
- [x] Frontier-only border rendering (eager from the registry — the lazy-on-chart variant was superseded, see *Rendering*), per-force `forces` filter, per-planet colors via `surface.planet.name` with a provider hook for MTS team colors (compat wiring lands in M4), corner survey-stake markers, per-state edge art (Trail dashed / Rampart long-dash / Deed solid), world + chart render families, `ltr-` sound prototypes
- [x] Remote interface `land-title-registry` (all functions in *Interfaces*, including `reset_force`), custom events `on_cell_claimed` / `on_cell_downgraded` / `on_points_changed` resolvable via `get_event_id` *(pulled forward from M4 during M1 — it is also the headless test surface; contract in `docs/API.md`)*
- [x] Layer overrides: startup settings `ltr-transit-additions/-removals`, `ltr-rampart-additions/-removals`; mod-data declaration channel (`data_type = "land-title-registry-layers"`); precedence defaults < mod-data < host settings, name entries beating `type:` entries within a channel
- [x] `compat/mts.lua` (mts-v1 consumer: `on_team_surface_created` enables team surfaces and settles the creation-order race, `on_team_released` resets recycled slots, team colors via the force's own color, grid-only-on-team-surfaces via `is_team_surface`) and `compat/odb.lua` (register_source + settlement-charter / first-deed / 25-deed milestone emits), both behind `script.active_mods` guards, composed through control.lua (script.on_event replaces handlers — compat modules never subscribe to shared events themselves)
- [x] `/ltr-rebuild` console command; space-platform surfaces auto-disabled; full event inventory wired; no unconditional `on_tick`
- [ ] Migrations folder, `locale/en/`, testing matrix from *Architecture* green

### v1.x Candidates

| Candidate | One-liner |
| --- | --- |
| Deed-history hover tooltip | Surface `claimant` and `claimed_tick` from the registry on cell hover; the data is already stored in v1. |
| Pacification faucet | Optional toggle (default off): points for clearing enemy nests inside a cell. |
| Appraised Deed pricing | Startup toggle (default off), Deeds only: Deed price scales with in-cell resources. |
| Depletion-aware refunds | Snapshot a cell's resource total at claim time; scale the refund by the remaining fraction. |
| Host-level global charter presets | Symmetric rule presets that apply to ALL teams identically - never per-team. |
| `/ltr-stats` RCON command | RCON-safe territory stats as JSON via `rcon.print`, so hosts can wire ODB's Discord-to-RCON commands to query Land Title Registry from Discord. |

### v2 Candidates

| Candidate | One-liner |
| --- | --- |
| Zoning designations | The headline: designate Deed cells for purposes with bonuses. |
| Ghost borders | **Shipped early as the cell chronicle** (ADR-0012): per-cell speedrun leaderboard — fastest first-Deed times on team clocks, top three drawn under each cell's top edge on every copy of the planet, displacement on better times, celebration without points. |
| Estate reports / spectator views | Territory summaries and spectator-facing map views. |
| Planet personalities | Gleba: unused claims rot and partially refund; Vulcanus: demolisher-territory deeds; Aquilo: claims require heated adjacency; Fulgora: island-shaped parcels. |
| Wilderness regrowth | Trees slowly recolonize unclaimed cells. |
| Buddy land grants | MTS buddy join grants a small point bonus. |
| Mortgages | Negative balance permitted with a surcharge while in debt. |
| Tech prerequisites on held terrain | Inversion of the income chain: some techs require holding specific land. |
| Inter-team claim transfer / trading | Move or trade claimed cells between teams. |

Ghost borders deserve elaboration because they exploit an MTS structural fact: MTS teams play isolated copies of the same map, so cell (x, y) is directly comparable across teams. The overlay renders other teams' claim outlines annotated with their team-clock timestamps, letting a team see "they had a Deed here by hour 4 on their clock." This yields asynchronous competition with zero physical interference, consistent with MTS's separate-surfaces design.

### Rejected Decisions Log

| Decision | Verdict | Rationale |
| --- | --- | --- |
| Per-team founding charters | Rejected | Asymmetric starting conditions violate MTS's equal-conditions philosophy; only global, all-team presets are acceptable (v1.x). |
| Non-square cell geometries (hexagons, pentagons, triangles) | Rejected | Regular pentagons cannot tile the plane at all; hex and triangle cells have diagonal edges that axis-aligned rectangular collision boxes cannot trace, so engine-level enforcement via blocker entities is impossible - enforcement would degrade into terrain ownership or script-side build policing, both of which abandon the engine-enforced rights model. Visual identity comes from rendering, not geometry. |
| 24-tile cell size | Rejected | Straddles native chunk boundaries every third cell, forcing either temporary build gaps or sliver-blocker management at the generated-world frontier - the most fragile code path. |
| Configurable cell size | Rejected, later overturned (ADR-0010) | Now a startup setting {16, 32}, default 16; chunk-divisibility retained, non-divisors still excluded. |
| Separate power collision layer | Rejected | Merged into rampart: poles, solar panels, and accumulators make ramparts self-sufficient and price powered corridors correctly. |
| Standalone Rampart without Trail | Reverted | The Trail prerequisite prices self-sufficient forts at 3 points, eliminates a fourth blocker state, and pure Trails are unpowered by design since poles are rampart-layer. |
| Shared-surface team race modes | Rejected | MTS's core design keeps every team on separate surfaces with independent team clocks for fairness; Land Title Registry must never assume shared-surface competition. |
| MTS-record-keyed point rewards | Rejected | Newer records overshadow older ones, making the reward basis unstable. |
| High default refund rate | Rejected | Claim -> extract -> refund must never be a free roundtrip; hence the 25% default for `ltr-refund-percent`. |
| "MTS Gridlocked" name / hard MTS dependency | Rejected | Undersells the divergence, implies the original author's endorsement, and the "MTS " title prefix convention means hard dependency - which this standalone mod must not have. |
| Adjacency-discount pricing | Rejected | Opaque arithmetic; replaced by flat prices plus the visible adjacency rule. |
| Parallel per-science-pack infinite techs | Rejected | Tree clutter, research-queue spam, and an opaque alternating-exponential cost formula; only the linear-cost terminal-technology idea was retained. |

Naming history: earlier working names picket, stockade, watchpost, and waystation were retired in favor of the final Rampart (and the Trail-prerequisite change made a separate combined-state name unnecessary).

### Open Questions

The 2026-08-04 grilling session (see `docs/adr/0005` through `0008` and the resolutions inline throughout this document) closed ten of the twelve questions this section once held. The two below are deliberately unresolved — both are settled by looking at the running game, not by more design:

- **Open (M3, art):** Border art direction per state — the lean remains Trail dashed, Rampart crenellated, Deed solid. The corner survey-stake markers are fixed as the visual signature; the per-state edge styles await actual sprites on an actual map.
- **Open (M5, playtesting):** Exact numeric tuning of every value in *Economy* — prices, `ltr-refund-percent` (25), `ltr-points-per-level` (5), `ltr-starting-points` (75), `ltr-settlement-charter` (30), tech level counts and cost ramps, `ltr-tech-cost-multiplier` (1). All shipped numbers are launch ballparks pending playtesting.

### Handoff Note

Read *Core Model* and *Core Model* first, together: the state ladder and the blocker/layer mechanism are one design, and everything else hangs off the invariant that rights are enforced by the engine, not by scripts. Then read *Architecture* for the storage schema and event inventory before writing any code - the registry is the single source of truth and blockers/renders must be rebuildable from it. Follow with *Economy* and *Player Experience* for the gameplay surface, then *Interfaces* before starting milestone M4. This section closes the loop: check the open questions above before locking any default, and consult the rejected-decisions table before "improving" anything - most obvious alternatives were already tried on paper and turned down for cause. Implementation order follows milestones M1-M5 in *Architecture*; alongside this document, an implementer should have MTS's published COMPAT.md open, since Land Title Registry is intended as its reference consumer.
