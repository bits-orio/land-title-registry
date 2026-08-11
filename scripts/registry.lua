-- The cell registry: the single source of truth (ADR-0003). Blockers and
-- renders are derived state and must always be reconstructible from here.
-- Wilderness cells are NOT stored — absence means Wilderness, keeping the
-- registry proportional to claimed land.

local registry = {}

-- Packed-integer cell key, valid for cell coordinates in +/-32k (the map
-- limit is +/-1M tiles = +/-31.25k cells). Persisted in storage.cells, so
-- changing the encoding means a migration. Used nowhere else directly.
function registry.cell_key(x, y)
  return (x + 0x8000) * 0x10000 + (y + 0x8000)
end

function registry.cell_key_to_pos(key)
  local x = math.floor(key / 0x10000) - 0x8000
  return { x = x, y = key % 0x10000 - 0x8000 }
end

function registry.init_storage()
  storage.meta = storage.meta or { version = 1 }
  storage.points = storage.points or {}
  storage.cells = storage.cells or {}
  storage.disabled_surfaces = storage.disabled_surfaces or {}
  -- registration id -> {surface_index, cell_key}, for on_object_destroyed
  storage.blocker_registrations = storage.blocker_registrations or {}
  -- [surface_index][cell_key] -> registration id (reverse map, so an
  -- intentional destroy can retire its registration first)
  storage.blocker_regids = storage.blocker_regids or {}
  -- pending /ltr-rebuild work items, drained by a temporary on_nth_tick
  storage.rebuild_queue = storage.rebuild_queue or {}
  -- [surface_index][cell_key] -> array of LuaRenderObject owned by the cell
  storage.renders = storage.renders or {}
  -- player_index -> true while that player holds the survey tool
  storage.tool_holders = storage.tool_holders or {}
  -- player_index -> last hovered cell key, for hover feedback
  storage.hover = storage.hover or {}
  -- player_index -> true once the welcome panel has been shown
  storage.welcomed = storage.welcomed or {}
  -- force_index -> render objects of the origin gesture hints, destroyed on
  -- the force's first paid claim
  storage.tutorial_renders = storage.tutorial_renders or {}
  -- [planet_name][cell_key] -> sorted {force_name, clock} speedrun entries
  storage.chronicle = storage.chronicle or {}
  -- [surface_index][cell_key] -> the drawn chronicle text objects
  storage.chronicle_renders = storage.chronicle_renders or {}
  -- [force_index][surface_index] -> mainland-anchor cell_key (outposts)
  storage.origins = storage.origins or {}
  -- [force_index] -> array of {surface_index, cell_key} founded outposts
  -- still counting against the force's slot cap
  storage.outposts = storage.outposts or {}
  -- player_index -> {surface_index, cx, cy} awaiting outpost confirmation
  storage.outpost_pending = storage.outpost_pending or {}
  -- [player_index][surface_index][cell_key] -> that player's border line
  -- objects (per-player styling; stakes stay in storage.renders)
  storage.player_renders = storage.player_renders or {}
  -- [surface_index][cell_key] -> the wilderness map-view sprite, kept
  -- apart from storage.renders so on_chunk_charted can reveal it in one
  -- lookup (created hidden, flipped visible when the chunk charts)
  storage.chart_sprites = storage.chart_sprites or {}
end

function registry.init_surface(surface_index)
  storage.cells[surface_index] = storage.cells[surface_index] or {}
  storage.blocker_regids[surface_index] = storage.blocker_regids[surface_index] or {}
end

-- Drop a surface's claims and blocker bookkeeping (surface cleared: the
-- world objects are gone and the claims do not survive — an out-of-band
-- administrative reset returns the surface to Wilderness).
function registry.drop_surface_claims(surface_index)
  storage.cells[surface_index] = {}
  local regids = storage.blocker_regids[surface_index]
  if regids then
    for _, regid in pairs(regids) do
      storage.blocker_registrations[regid] = nil
    end
  end
  storage.blocker_regids[surface_index] = {}
end

-- Full per-surface teardown (surface deleted).
function registry.drop_surface(surface_index)
  registry.drop_surface_claims(surface_index)
  storage.cells[surface_index] = nil
  storage.blocker_regids[surface_index] = nil
  storage.disabled_surfaces[surface_index] = nil
end

function registry.get(surface_index, cell_key)
  local cells = storage.cells[surface_index]
  return cells and cells[cell_key]
end

-- State of a cell as a string; "wilderness" for absent records.
function registry.state_of(surface_index, cell_key)
  local rec = registry.get(surface_index, cell_key)
  return rec and rec.state or "wilderness"
end

function registry.set(surface_index, cell_key, record)
  storage.cells[surface_index] = storage.cells[surface_index] or {}
  storage.cells[surface_index][cell_key] = record
end

function registry.clear_cell(surface_index, cell_key)
  local cells = storage.cells[surface_index]
  if cells then cells[cell_key] = nil end
end

-- Does the force own any cell on this surface? (Early-exit scan; used only
-- when the whole-rectangle anchor test has already failed.)
function registry.force_owns_any(surface_index, force_index)
  local cells = storage.cells[surface_index]
  if not cells then return false end
  for _, rec in pairs(cells) do
    if rec.force_index == force_index then return true end
  end
  return false
end

return registry
