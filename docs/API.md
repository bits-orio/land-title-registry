# The `freehold` remote interface

Stable from v1: these signatures and payloads are a compatibility contract. Declare `"? freehold"` in your `info.json` so Freehold loads first, and resolve event ids from `on_init` **and** `on_load` — Factorio 2.0 rejects `remote.call` at `control.lua` root scope, and allows it in `on_load`.

## Conventions

- `cell_pos` is `{x, y}` in **cell coordinates**: cell `(x, y)` covers tiles `[s·x, s·x+s−1] × [s·y, s·y+s−1]` where `s = get_cell_size()` (startup `fh-cell-size`: 16, 24, or 32). Cell coordinates equal chunk coordinates only at size 32.
- `surface` and `force` take runtime objects (`LuaSurface`, `LuaForce`); the points functions take a plain `force_index`.
- State strings are exactly `"trail"`, `"rampart"`, `"deed"`. `nil` from `get_cell` means Wilderness.
- Functions documented as `ok, reason` return `true, nil` on success, or `false` plus a short refusal string: `"surface-disabled"`, `"no-anchor"`, `"insufficient-points"`, `"ineligible"`, `"invalid-surface"`, `"invalid-force"`, `"invalid-cell-pos"`, `"invalid-target-state"`.

## Functions

| Function | Returns | Behavior |
| --- | --- | --- |
| `get_points(force_index)` | `number` | Current Land-points balance. A plain number, not an integer — refunds are fractional (balances are quantized to hundredths). |
| `set_points(force_index, points)` | — | Sets the balance outright. Raises `on_points_changed` (reason `"remote"`). |
| `add_points(force_index, delta)` | — | Adjusts the balance by `delta` (may be negative). Raises `on_points_changed` (reason `"remote"`). |
| `reset_force(force_index)` | — | Resets the balance to the starting grant (`fh-starting-points`) and refreshes every member's balance display. For integrators recycling force slots (MTS team lifecycle). Raises `on_points_changed` (reason `"reset"`). |
| `claim(surface, cell_pos, force, target_state, opts)` | `ok, reason` | Claim/upgrade one cell to `target_state`. Exactly the survey tool's rules: flat prices with full credit, adjacency for new Wilderness claims, Trail prerequisite for Rampart, disabled-surface check. `opts.ignore_adjacency = true` is the single sanctioned adjacency bypass, for scenario/quest mods seeding territory. |
| `downgrade(surface, cell_pos, force, opts)` | `ok, reason` | Downgrade one cell one step, refunding step price × `fh-refund-percent` / 100, subject to the downgrade validity check (the cell must contain none of the force's entities using the revoked right). |
| `get_cell(surface, cell_pos)` | `nil` or table | `{state, force_index, claimed_tick, invested_points, claimant}`. `nil` means Wilderness. |
| `get_territory_stats(force_index, opts)` | table | `{trails, ramparts, deeds}` across all surfaces. With `opts = {by_surface = true}`, adds `by_surface = {[surface_index] = {trails, ramparts, deeds}}`. |
| `set_surface_enabled(surface, enabled)` | — | A disabled surface gets no blockers and no grid. Disabling sweeps existing blockers via the batched rebuild queue; re-enabling reconciles them back from the registry. Claims are refused with `"surface-disabled"` while disabled; the registry itself survives. |
| `get_surface_enabled(surface)` | `boolean` | Whether Freehold's grid is active on the surface. |
| `get_cell_size()` | `uint` | Cell edge length in tiles (startup `fh-cell-size`). |
| `get_event_id(name)` | `uint` or `nil` | Resolves a custom-event name to this session's event id. |

## Custom events

Resolve ids via `get_event_id` from `on_init` **and** `on_load` every session — ids are regenerated per session and must never be stored in `storage` (root-scope `remote.call` is rejected by 2.0).

| Event | Payload (plus engine `name`/`tick`) |
| --- | --- |
| `on_cell_claimed` | `surface_index`, `cell_pos` (`{x, y}` cell coords), `force_name`, `old_state`, `new_state`, `player_index` (absent for remote claims with no acting player), `cost` |
| `on_cell_downgraded` | `surface_index`, `cell_pos`, `force_name`, `old_state`, `new_state`, `refund` (may be fractional), `player_index` (optional) |
| `on_points_changed` | `force_name`, `points` (new balance), `delta`, `reason` (`"claim"`, `"refund"`, `"starting-grant"`, `"merge"`, `"remote"`, `"reset"`; M2 adds `"research"`, `"research-reversed"`, `"settlement-charter"`) |

## Consumer snippet

```lua
-- control.lua of an integrating mod (declare "? freehold" for load order)
local function resolve_freehold_events()
  if not remote.interfaces["freehold"] then return end
  local on_cell_claimed = remote.call("freehold", "get_event_id", "on_cell_claimed")
  script.on_event(on_cell_claimed, function(e)
    if e.new_state == "deed" then
      game.forces[e.force_name].print({ "my-mod.deed-message", e.cell_pos.x, e.cell_pos.y })
    end
  end)
end
script.on_init(resolve_freehold_events)
script.on_load(resolve_freehold_events)
-- Never write the event id to storage: ids are regenerated every session.
```
