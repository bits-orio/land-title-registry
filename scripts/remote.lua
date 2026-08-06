-- The `land-title-registry` remote interface: documented and stable from v1 (see
-- docs/API.md). Registered at control.lua root scope, so mods declaring
-- "? land-title-registry" can resolve it from their own root scope.
--
-- Conventions: `cell_pos` is {x, y} in cell coordinates (cell (x, y) covers
-- tiles [size*x, size*x+size-1] per axis, size from ltr-cell-size; equal to
-- chunk coordinates only at size 32); `surface`/`force` take runtime
-- objects; the points functions
-- take a plain force_index. Functions returning ok, reason return true, nil
-- on success or false plus a short refusal string.

local const = require("scripts.const")
local registry = require("scripts.registry")
local blockers = require("scripts.blockers")
local economy = require("scripts.economy")
local claims = require("scripts.claims")
local chronicle = require("scripts.chronicle")
local custom_events = require("scripts.custom_events")

local VALID_TARGET = { trail = true, rampart = true, deed = true }

local function one_cell_rect(cell_pos)
  return { x1 = cell_pos.x, y1 = cell_pos.y, x2 = cell_pos.x, y2 = cell_pos.y }
end

-- Map an apply_batch result onto the ok, reason contract.
local function to_ok(result)
  if result.denied == "disabled" then return false, "surface-disabled" end
  if result.denied == "anchor" then return false, "no-anchor" end
  if result.denied == "points" then return false, "insufficient-points" end
  if result.applied == 0 then return false, "ineligible" end
  return true, nil
end

remote.add_interface("land-title-registry", {
  get_points = function(force_index)
    return economy.get(force_index)
  end,

  set_points = function(force_index, points)
    economy.set(game.forces[force_index], points, "remote")
  end,

  add_points = function(force_index, delta)
    economy.change(game.forces[force_index], delta, "remote")
  end,

  -- Reset to the starting grant. Exists for integrators recycling force
  -- slots (MTS team lifecycle): balance back to ltr-starting-points, every
  -- member's balance display refreshed via the on_points_changed path.
  reset_force = function(force_index)
    economy.set(game.forces[force_index], settings.global["ltr-starting-points"].value, "reset")
  end,

  claim = function(surface, cell_pos, force, target_state, opts)
    if not (surface and surface.valid) then return false, "invalid-surface" end
    if not (force and force.valid) then return false, "invalid-force" end
    if type(cell_pos) ~= "table" or type(cell_pos.x) ~= "number" or type(cell_pos.y) ~= "number" then
      return false, "invalid-cell-pos"
    end
    if not VALID_TARGET[target_state] then return false, "invalid-target-state" end
    return to_ok(claims.apply_batch(surface, force, nil, one_cell_rect(cell_pos), target_state,
      { ignore_adjacency = opts ~= nil and opts.ignore_adjacency or false }))
  end,

  downgrade = function(surface, cell_pos, force, opts)
    if not (surface and surface.valid) then return false, "invalid-surface" end
    if not (force and force.valid) then return false, "invalid-force" end
    if type(cell_pos) ~= "table" or type(cell_pos.x) ~= "number" or type(cell_pos.y) ~= "number" then
      return false, "invalid-cell-pos"
    end
    return to_ok(claims.apply_batch(surface, force, nil, one_cell_rect(cell_pos), "downgrade"))
  end,

  get_cell = function(surface, cell_pos)
    local rec = registry.get(surface.index, registry.cell_key(cell_pos.x, cell_pos.y))
    if not rec then return nil end
    return {
      state = rec.state,
      force_index = rec.force_index,
      claimed_tick = rec.claimed_tick,
      invested_points = rec.invested_points,
      claimant = rec.claimant,
    }
  end,

  get_territory_stats = function(force_index, opts)
    local stats = { trails = 0, ramparts = 0, deeds = 0 }
    local by_surface = opts ~= nil and opts.by_surface and {} or nil
    for surface_index, cells in pairs(storage.cells) do
      local per
      for _, rec in pairs(cells) do
        if rec.force_index == force_index then
          local bucket = rec.state .. "s"
          stats[bucket] = stats[bucket] + 1
          if by_surface then
            per = per or { trails = 0, ramparts = 0, deeds = 0 }
            per[bucket] = per[bucket] + 1
          end
        end
      end
      if by_surface and per then by_surface[surface_index] = per end
    end
    if by_surface then stats.by_surface = by_surface end
    return stats
  end,

  -- A disabled surface gets no blockers and no grid at all. Disabling
  -- sweeps existing blockers away through the rebuild queue; re-enabling
  -- reconciles blockers back from the registry, /ltr-rebuild-style.
  set_surface_enabled = function(surface, enabled)
    if enabled then
      storage.disabled_surfaces[surface.index] = nil
    else
      storage.disabled_surfaces[surface.index] = true
    end
    blockers.enqueue_surface_rebuild(surface)
  end,

  get_surface_enabled = function(surface)
    return not storage.disabled_surfaces[surface.index]
  end,

  -- The cell's chronicle: teams that have deeded these coordinates on this
  -- planet, ranked fastest-first on their own team clocks. Array of
  -- { force_name, clock } (clock in ticks). Empty when nobody has deeded
  -- it. Cross-team comparable: every team's copy of a planet shares one
  -- chronicle, so scoreboards can rank a cell across all teams.
  get_cell_chronicle = function(surface, cell_pos)
    if not (surface and surface.valid) then return {} end
    local out = {}
    for _, entry in ipairs(chronicle.entries_for(surface, cell_pos.x, cell_pos.y)) do
      out[#out + 1] = { force_name = entry.force_name, clock = entry.clock }
    end
    return out
  end,

  -- Cell edge length in tiles (startup ltr-cell-size). Cell coordinates
  -- equal chunk coordinates only when this is 32.
  get_cell_size = function()
    return const.CELL
  end,

  -- Custom-event ids are regenerated every session: resolve at YOUR
  -- control.lua root scope, subscribe there, and never store the id.
  get_event_id = function(name)
    return custom_events[name]
  end,
})
