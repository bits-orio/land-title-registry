-- Frontier-only border rendering with corner survey stakes.
--
-- A border segment exists on the shared edge of two orthogonally adjacent
-- cells iff their states differ (absence = Wilderness). A solid region
-- renders only its outline; interiors draw nothing — render-object count is
-- proportional to claim perimeter, not area (the MTS design driver: every
-- per-cell cost is paid once per team-surface).
--
-- Ownership convention (no duplicate segments): cell (x, y) owns its WEST
-- edge, its NORTH edge, and the stake at its NORTH-WEST vertex. A state
-- change in cell c therefore refreshes exactly four cells' owned objects:
-- c, east(c), south(c), southeast(c) — see refresh_around.
--
-- Two render families per edge (the engine renders an object in ONE mode):
-- an in-world line (render_mode game, only_in_alt_mode, drawn on ground)
-- and a chart line (render_mode chart) so territory reads on the map.
-- Every object carries a `forces` filter — each force sees only its own
-- claims.
--
-- Renders derive from the registry ALONE, eagerly at claim/downgrade/
-- rebuild time — there is no charted-status gate. An earlier design created
-- them lazily on on_chunk_charted; that gate bought nothing (frontier-only
-- already bounds count by claim perimeter, fog already hides world renders,
-- the forces filter already scopes visibility, and adjacency keeps a
-- force's claims inside its charted territory in practice) while making
-- derived state depend on a second input and an event ordering. ADR-0003
-- purity wins.

local const = require("scripts.const")
local registry = require("scripts.registry")

local render = {}

-- Per-state edge art (M3 lean: Trail dashed, Rampart long-dashed, Deed
-- solid). An edge uses the art of its HIGHER state side.
local STATE_RANK = { wilderness = 0, trail = 1, rampart = 2, deed = 3 }
local EDGE_ART = {
  trail = { width = 2, dash = 0.9, gap = 0.9 },
  rampart = { width = 3, dash = 2.2, gap = 0.7 },
  deed = { width = 3, dash = 0, gap = 0 },
}

-- Optional provider hook: compat/mts.lua (M4) sets this to return a team
-- color for a force; nil falls through to the per-planet settings.
render.team_color_provider = nil

local function planet_color(surface)
  local planet = surface.planet
  if planet then
    local setting = "fh-color-" .. planet.name
    if prototypes.mod_setting[setting] then
      return settings.global[setting].value
    end
  end
  return settings.global["fh-color-default"].value
end

local function resolve_color(surface, force_index)
  if render.team_color_provider then
    local color = render.team_color_provider(force_index)
    if color then return color end
  end
  return planet_color(surface)
end

local function state_at(surface_index, cx, cy)
  return registry.state_of(surface_index, registry.cell_key(cx, cy))
end

-- The force that owns claimed cell (cx, cy), or nil.
local function owner_at(surface_index, cx, cy)
  local rec = registry.get(surface_index, registry.cell_key(cx, cy))
  return rec and rec.force_index or nil
end

-- Involved forces of an edge: the owners of its claimed sides (one force in
-- the v1 one-building-force-per-surface model; kept general regardless).
local function edge_forces(surface_index, ax, ay, bx, by)
  local out = {}
  local a = owner_at(surface_index, ax, ay)
  local b = owner_at(surface_index, bx, by)
  if a then out[a] = true end
  if b and b ~= a then out[b] = true end
  return out
end

local function is_frontier(surface_index, ax, ay, bx, by)
  return state_at(surface_index, ax, ay) ~= state_at(surface_index, bx, by)
end

local function edge_art(surface_index, ax, ay, bx, by)
  local sa, sb = state_at(surface_index, ax, ay), state_at(surface_index, bx, by)
  local higher = STATE_RANK[sa] > STATE_RANK[sb] and sa or sb
  return EDGE_ART[higher]
end

local function draw_edge(objects, surface, from, to, art, color, force)
  objects[#objects + 1] = rendering.draw_line({
    surface = surface,
    from = from,
    to = to,
    color = color,
    width = art.width,
    dash_length = art.dash,
    gap_length = art.gap,
    draw_on_ground = true,
    only_in_alt_mode = true,
    forces = { force },
  })
  objects[#objects + 1] = rendering.draw_line({
    surface = surface,
    from = from,
    to = to,
    color = color,
    width = 2,
    dash_length = art.dash,
    gap_length = art.gap,
    render_mode = "chart", -- ScriptRenderMode is a string union, not defines
    forces = { force },
  })
end

-- The four edges touching vertex V(cx, cy) — the NW corner of cell (cx, cy):
-- {a-cell, b-cell} pairs for the two vertical and two horizontal edges.
local function vertex_edges(cx, cy)
  return {
    { cx - 1, cy, cx, cy },     -- horizontal-neighbor pair north of nothing: west edge of (cx, cy) row
    { cx - 1, cy - 1, cx, cy - 1 }, -- west edge pair one cell north
    { cx, cy - 1, cx, cy },     -- north edge of (cx, cy)
    { cx - 1, cy - 1, cx - 1, cy }, -- north edge of west neighbor
  }
end

-- Rebuild the render objects OWNED by cell (cx, cy): west edge, north edge,
-- NW stake. Destroys before creating; safe to call for any cell at any time.
function render.refresh_cell(surface, cx, cy)
  local surface_index = surface.index
  storage.renders[surface_index] = storage.renders[surface_index] or {}
  local refs = storage.renders[surface_index]
  local cell_key = registry.cell_key(cx, cy)

  local old = refs[cell_key]
  if old then
    for _, object in pairs(old) do
      if object.valid then object.destroy() end
    end
    refs[cell_key] = nil
  end

  if storage.disabled_surfaces[surface_index] then return end

  local objects = {}
  local x0, y0 = cx * const.CELL, cy * const.CELL

  -- West edge: between (cx-1, cy) and (cx, cy).
  if is_frontier(surface_index, cx - 1, cy, cx, cy) then
    local art = edge_art(surface_index, cx - 1, cy, cx, cy)
    for force_index in pairs(edge_forces(surface_index, cx - 1, cy, cx, cy)) do
      local force = game.forces[force_index]
      if force and force.valid then
        draw_edge(objects, surface,
          { x = x0, y = y0 }, { x = x0, y = y0 + const.CELL },
          art, resolve_color(surface, force_index), force)
      end
    end
  end

  -- North edge: between (cx, cy-1) and (cx, cy).
  if is_frontier(surface_index, cx, cy - 1, cx, cy) then
    local art = edge_art(surface_index, cx, cy - 1, cx, cy)
    for force_index in pairs(edge_forces(surface_index, cx, cy - 1, cx, cy)) do
      local force = game.forces[force_index]
      if force and force.valid then
        draw_edge(objects, surface,
          { x = x0, y = y0 }, { x = x0 + const.CELL, y = y0 },
          art, resolve_color(surface, force_index), force)
      end
    end
  end

  -- NW survey stake: drawn when at least one touching edge is a frontier.
  local stake_forces = {}
  for _, e in pairs(vertex_edges(cx, cy)) do
    if is_frontier(surface_index, e[1], e[2], e[3], e[4]) then
      for force_index in pairs(edge_forces(surface_index, e[1], e[2], e[3], e[4])) do
        stake_forces[force_index] = true
      end
    end
  end
  for force_index in pairs(stake_forces) do
    local force = game.forces[force_index]
    if force and force.valid then
      objects[#objects + 1] = rendering.draw_sprite({
        surface = surface,
        sprite = "fh-survey-stake",
        target = { x = x0, y = y0 },
        tint = resolve_color(surface, force_index),
        x_scale = 0.5,
        y_scale = 0.5,
        only_in_alt_mode = true,
        forces = { force },
      })
    end
  end

  if #objects > 0 then refs[cell_key] = objects end
end

-- A state change (or fresh charting) of cell (cx, cy) affects the owned
-- objects of exactly these four cells.
function render.refresh_around(surface, cx, cy)
  render.refresh_cell(surface, cx, cy)
  render.refresh_cell(surface, cx + 1, cy)
  render.refresh_cell(surface, cx, cy + 1)
  render.refresh_cell(surface, cx + 1, cy + 1)
end

-- Surface teardown: destroy every render object and drop the bookkeeping.
function render.drop_surface(surface_index)
  local refs = storage.renders[surface_index]
  if refs then
    for _, objects in pairs(refs) do
      for _, object in pairs(objects) do
        if object.valid then object.destroy() end
      end
    end
  end
  storage.renders[surface_index] = nil
end

return render
