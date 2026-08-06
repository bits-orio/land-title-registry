---
name: ltr-invariants
description: The non-negotiable coding rules for the Land Title Registry Factorio mod — cell terminology, registry-as-source-of-truth, engine-enforced rights, no unconditional on_tick, and multi-force/multi-surface correctness. Read before writing or reviewing any Lua in this repo.
---

# Land Title Registry Invariants

Five rules. Each one is load-bearing: the design in `DESIGN.md` stops working if any of them is broken. Violations are review blockers, not style nits.

## 1. "Cell" is the mod's unit. "Chunk" is the engine's.

The mod's unit of land is always a **cell**. The word "chunk" is reserved exclusively for Factorio's own concept — `on_chunk_generated`, `on_chunk_charted`, charted chunks, `LuaSurface.get_chunks`.

```lua
-- WRONG
local function claim_chunk(surface, chunk_pos, force) ... end
player.print("Chunk claimed for 1 point.")

-- CORRECT
local function claim_cell(surface, cell_pos, force) ... end
player.print("Cell claimed for 1 Land point.")
```

Applies to: identifiers, comments, locale strings, chat messages, GUI labels, changelog entries, commit messages. Cell size is the `ltr-cell-size` startup setting (16 or 32); a cell coincides with a chunk footprint only at 32, so never assume the identity — go through `const.chunk_of_cell` / `const.cell_range_of_chunk`.

Currency is **"Land points"** in every player-facing string; `points` in code.

State strings are exactly `"trail"`, `"rampart"`, `"deed"`. Wilderness has **no** string — it is the absence of a registry entry. Never introduce a `"wilderness"` value into `storage.cells`.

## 2. The registry is the single source of truth.

`storage.cells[surface_index][cell_key]` is authoritative. Blocker entities and render objects are **derived state**.

```lua
-- WRONG — the world is being asked what it owns
if surface.find_entity("ltr-cell-trail", center) then
    -- treat the cell as Trail
end

-- CORRECT — the registry is asked; the entity is only ever a consequence
local cell = registry.get(surface.index, cell_key)
if cell and cell.state == "trail" then ... end
```

Consequences to hold to:
- No code path may treat the presence or absence of a blocker or render object as authoritative.
- If registry and world disagree, the registry wins and the world is rebuilt (`/ltr-rebuild`).
- Never store `LuaEntity` references for blockers in `storage`. Look them up with `surface.find_entity(name, cell_center)`.
- Wilderness cells are **not** stored. Absence means Wilderness; the registry stays proportional to claimed land, not explored land.

## 3. Rights are enforced by collision, not by scripts.

Building rights come from collision masks: every player-creation prototype sits in exactly one of `ltr-land` / `ltr-transit` / `ltr-rampart`, and one blocker entity per non-Deed cell denies the layers that cell has not earned. A Deed cell has no blocker at all.

There is exactly **one** sanctioned script-side check in the whole mod: the `find_entities_filtered` area query that validates a downgrade. Anything else that inspects a build is a bug.

```lua
-- WRONG — reintroduces the build-cop model the design exists to avoid
script.on_event(defines.events.on_built_entity, function(event)
    if not force_may_build_here(event.entity) then event.entity.destroy() end
end)
```

If a rights rule seems to need a build event, the layer assignment is wrong — fix it in `data-final-fixes.lua`.

Related: masks are fixed at prototype-load time. Layer membership is decided at data stage only. Never promise or write a runtime API that moves an entity between layers.

## 4. No unconditional `on_tick`.

Land Title Registry registers no unconditional `on_tick` handler, ever. Steady state is event-driven.

Work too large for one tick (mass re-tints, `/ltr-rebuild` reconciliation) uses the temporary `on_nth_tick` pattern:

```lua
-- 1. enqueue into storage so a save mid-batch is deterministic
storage.work_queue[#storage.work_queue + 1] = item
-- 2. register
script.on_nth_tick(N, drain)
-- 3. drain a bounded slice per call; when empty:
script.on_nth_tick(N, nil)
-- 4. in on_load, re-register iff the persisted queue is non-empty
```

Polling to work around a missing engine event is not an acceptable substitute — with one documented exception, the survey-tool hover fallback, which registers `on_nth_tick` only while a player actually holds the tool and unregisters when nobody does.

## 5. Multi-force and multi-surface correctness is a hard requirement.

Land Title Registry is the reference consumer of MTS's `docs/COMPAT.md` patterns. All six apply here as rules, not suggestions:

| Rule | In Land Title Registry |
|---|---|
| Never `game.forces.player` | Take the force from the triggering event: `player.force`, `research.force`. |
| Never hardcode surface names or indices | Key per-planet behavior off `surface.planet.name`. No `"nauvis"` literals, no `[1]` / `[-1]` sentinels. |
| Key state by force index AND surface index | `storage.points[force_index]`; `storage.cells[surface_index][cell_key]`. |
| Iterate all forces for global effects | Migrations, setting changes, grant recalcs loop `game.forces`. |
| Expose runtime rules via remote | Every rule reachable through the `land-title-registry` interface. |
| Emit custom events for lifecycle | `on_cell_claimed`, `on_cell_downgraded`, `on_points_changed`. |

Two events are non-negotiable because MTS moves players between forces and recycles force slots:
- `on_player_changed_force` — rebind the HUD to the **new** force's balance.
- `reset_force` (remote) — implemented from day one, resetting the balance to the starting grant and refreshing every member's HUD.

**Never store a custom event id in `storage`.** Ids are regenerated every session; resolve them in `on_init` AND `on_load` (2.0 rejects root-scope `remote.call` and allows it in `on_load` — verified against the engine). This applies both to Land Title Registry's own ids and to ids resolved from `mts-v1` or `open-discord-bridge-v1`.

All cross-mod calls sit behind `script.active_mods[...]` guards plus a defensive `remote.interfaces[...]` check.

## Quick audit checklist

Grep before tagging a release. Each is a near-certain violation:

| Pattern in code | Rule broken |
|---|---|
| `chunk` in a mod-domain identifier or player-facing string | 1 |
| `"wilderness"` as a stored state value | 1 |
| `find_entity("ltr-cell-` used as a state query | 2 |
| `LuaEntity` stored in `storage` | 2 |
| `on_built_entity` / `on_robot_built_entity` handler | 3 |
| `script.on_event(defines.events.on_tick, ...)` | 4 |
| `game.forces.player` / `game.forces["player"]` | 5 |
| `surface.name ==` a literal, or `surfaces[1]` / `[-1]` | 5 |
| an event id written to `storage` | 5 |
