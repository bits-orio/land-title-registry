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

-- Per-state edge art (Trail dashed, Rampart long-dashed, Deed solid).
-- Each claimed side of a frontier draws its own art — see INSET below.
local EDGE_ART = {
  trail = { width = 1, dash = 0.5, gap = 0.5 },
  rampart = { width = 1, dash = 2.2, gap = 0.7 },
  deed = { width = 1, dash = 0, gap = 0 },
}

-- Edge colors are per STATE and per PLAYER: each player styles their own
-- force's lines through the ltr-border-* per-user settings (width, color,
-- alpha — playtest call), whose defaults are the scripts/state_colors.lua
-- palette. Line objects therefore carry BOTH a forces filter and a players
-- filter; ownership identity stays on the survey stakes, which keep the
-- per-planet / MTS team color and stay shared per force.
--
-- Alpha as a coarse zoom ramp. ScriptRenderMode is exactly "game"|"chart"
-- (verified against the 2.0.77 API — the chart_zoomed_in defines value is
-- the PLAYER's view state, not a draw-call option), so a continuous
-- zoom-dependent alpha does not exist and neither does a middle step. What
-- exists is a two-step ramp — subtle lines up close in the world, full
-- strength on the map — scaled by the alpha the player chose.
local EDGE_ALPHA = { game = 0.55, chart = 1.0 }

-- A player's line style, read once per refresh/rebuild pass.
local function style_of(player)
  local s = player.mod_settings
  return {
    width = s["ltr-border-width"].value,
    colors = {
      trail = s["ltr-border-color-trail"].value,
      rampart = s["ltr-border-color-rampart"].value,
      deed = s["ltr-border-color-deed"].value,
    },
  }
end

-- Premultiplied line color: the player's chosen color and alpha, scaled by
-- the mode's ramp step.
local function line_color(style, state, mode_alpha)
  local c = style.colors[state]
  local a = (c.a or 1) * mode_alpha
  return { r = c.r * a, g = c.g * a, b = c.b * a, a = a }
end

-- Optional provider hook: compat/mts.lua (M4) sets this to return a team
-- color for a force; nil falls through to the per-planet settings.
render.team_color_provider = nil

local function planet_color(surface)
  local planet = surface.planet
  if planet then
    local setting = "ltr-color-" .. planet.name
    if prototypes.mod_setting[setting] then
      return settings.global[setting].value
    end
  end
  return settings.global["ltr-color-default"].value
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

-- Border lines are INSET into their own claimed side rather than drawn on
-- the shared boundary. Where two claimed states abut, BOTH sides draw their
-- own line in their own art, 2×INSET apart — adjoining territories read as
-- separate outlines instead of merging into one shape (survey stakes stay
-- on the true shared vertices). A wilderness side draws nothing, so outer
-- frontiers remain single lines.
local INSET = 0.2

-- Both render modes of one edge line, for one player, in that player's
-- style. The forces filter scopes to the owner; the players filter scopes
-- to the one viewer whose settings shaped these objects.
local function draw_edge(objects, surface, from, to, state, force, player, style)
  local art = EDGE_ART[state]
  objects[#objects + 1] = rendering.draw_line({
    surface = surface,
    from = from,
    to = to,
    color = line_color(style, state, EDGE_ALPHA.game),
    width = style.width,
    dash_length = art.dash,
    gap_length = art.gap,
    draw_on_ground = true,
    only_in_alt_mode = true,
    forces = { force },
    players = { player },
  })
  objects[#objects + 1] = rendering.draw_line({
    surface = surface,
    from = from,
    to = to,
    color = line_color(style, state, EDGE_ALPHA.chart),
    width = style.width + 1,
    dash_length = art.dash,
    gap_length = art.gap,
    render_mode = "chart",
    forces = { force },
    players = { player },
  })
end

-- The line objects of cell (cx, cy)'s owned edges (west + north) that
-- belong to ONE player: only sides owned by that player's force, in that
-- player's style. Factored out of refresh_cell so a player-scoped rebuild
-- (join, force change, setting change) can re-derive lines without
-- touching the shared stakes.
local function build_player_lines(surface, cx, cy, player, style)
  local surface_index = surface.index
  local force = player.force
  local force_index = force.index
  local objects = {}
  local x0, y0 = cx * const.CELL, cy * const.CELL
  local C = const.CELL

  local sc = state_at(surface_index, cx, cy)
  local sw = state_at(surface_index, cx - 1, cy)
  if sw ~= sc then
    if sc ~= "wilderness" and owner_at(surface_index, cx, cy) == force_index then
      draw_edge(objects, surface, { x = x0 + INSET, y = y0 + INSET },
        { x = x0 + INSET, y = y0 + C - INSET }, sc, force, player, style)
    end
    if sw ~= "wilderness" and owner_at(surface_index, cx - 1, cy) == force_index then
      draw_edge(objects, surface, { x = x0 - INSET, y = y0 + INSET },
        { x = x0 - INSET, y = y0 + C - INSET }, sw, force, player, style)
    end
  end

  local sn = state_at(surface_index, cx, cy - 1)
  if sn ~= sc then
    if sc ~= "wilderness" and owner_at(surface_index, cx, cy) == force_index then
      draw_edge(objects, surface, { x = x0 + INSET, y = y0 + INSET },
        { x = x0 + C - INSET, y = y0 + INSET }, sc, force, player, style)
    end
    if sn ~= "wilderness" and owner_at(surface_index, cx, cy - 1) == force_index then
      draw_edge(objects, surface, { x = x0 + INSET, y = y0 - INSET },
        { x = x0 + C - INSET, y = y0 - INSET }, sn, force, player, style)
    end
  end

  return objects
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

local function destroy_all(objects)
  if not objects then return end
  for _, object in pairs(objects) do
    if object.valid then object.destroy() end
  end
end

-- Rebuild the render objects OWNED by cell (cx, cy): west edge, north edge,
-- NW stake. Destroys before creating; safe to call for any cell at any
-- time. Stakes are shared per force (storage.renders); lines are built per
-- connected player of each involved force, in that player's own style
-- (storage.player_renders).
function render.refresh_cell(surface, cx, cy)
  local surface_index = surface.index
  storage.renders[surface_index] = storage.renders[surface_index] or {}
  local refs = storage.renders[surface_index]
  local cell_key = registry.cell_key(cx, cy)

  destroy_all(refs[cell_key])
  refs[cell_key] = nil
  for _, per_surface in pairs(storage.player_renders) do
    local bucket = per_surface[surface_index]
    if bucket then
      destroy_all(bucket[cell_key])
      bucket[cell_key] = nil
    end
  end

  if storage.disabled_surfaces[surface_index] then return end

  local objects = {}
  local x0, y0 = cx * const.CELL, cy * const.CELL

  -- The forces involved in this cell's owned edges and stake vertex — the
  -- stake owners, and whose connected players get line objects.
  local involved = {}
  local sc = state_at(surface_index, cx, cy)
  for _, pair in pairs({ { cx - 1, cy }, { cx, cy - 1 } }) do
    if state_at(surface_index, pair[1], pair[2]) ~= sc then
      local own = owner_at(surface_index, cx, cy)
      local other = owner_at(surface_index, pair[1], pair[2])
      if own then involved[own] = true end
      if other then involved[other] = true end
    end
  end

  -- Lines, per connected player of each involved force.
  for force_index in pairs(involved) do
    local force = game.forces[force_index]
    if force and force.valid then
      for _, player in pairs(force.connected_players) do
        local lines = build_player_lines(surface, cx, cy, player, style_of(player))
        if #lines > 0 then
          local per_surface = storage.player_renders[player.index] or {}
          storage.player_renders[player.index] = per_surface
          per_surface[surface_index] = per_surface[surface_index] or {}
          per_surface[surface_index][cell_key] = lines
        end
      end
    end
  end

  -- Map-view overlay: the cell's own striped -chart artwork as one chart
  -- sprite per BLOCKER (playtest-final design — stripes, never tints;
  -- terrain keeps its natural chart colors everywhere). One sprite per
  -- already-paid blocker entity, so the cost class is the blocker's own.
  -- Wilderness sprites are gated on the blocker actually standing there
  -- (generated chunks), so ungenerated void stays clean, and are visible
  -- to everyone like the world overlay. Claimed-state sprites carry the
  -- owner's forces filter, matching the border lines. Deed draws nothing:
  -- absence = fully yours, on the map as on the ground.
  if sc == "trail" or sc == "rampart" then
    local own = owner_at(surface_index, cx, cy)
    local force = own and game.forces[own]
    if force and force.valid then
      objects[#objects + 1] = rendering.draw_sprite({
        surface = surface,
        sprite = "ltr-" .. sc .. "-overlay",
        target = { x = x0 + const.CELL / 2, y = y0 + const.CELL / 2 },
        x_scale = const.CELL / 32,
        y_scale = const.CELL / 32,
        render_mode = "chart",
        forces = { force },
      })
    end
  elseif sc == "wilderness"
    and storage.blocker_regids[surface_index]
    and storage.blocker_regids[surface_index][cell_key] then
    objects[#objects + 1] = rendering.draw_sprite({
      surface = surface,
      sprite = "ltr-wilderness-overlay",
      target = { x = x0 + const.CELL / 2, y = y0 + const.CELL / 2 },
      x_scale = const.CELL / 32,
      y_scale = const.CELL / 32,
      render_mode = "chart",
    })
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
        sprite = "ltr-survey-stake",
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

-- Destroy one player's line objects everywhere (leave, force change, style
-- change — the rebuild half is render.rebuild_player).
function render.drop_player(player_index)
  local per_surface = storage.player_renders[player_index]
  if per_surface then
    for _, cells in pairs(per_surface) do
      for _, objects in pairs(cells) do destroy_all(objects) end
    end
  end
  storage.player_renders[player_index] = nil
end

-- Rebuild one player's lines from the registry. The force's lines live
-- only on cells it owns and their east/south neighbours (a cell owns its
-- west and north edges), so candidates come straight from the force's own
-- territory — O(owned cells), NOT the shared render bookkeeping, which
-- since map overlays covers every generated cell.
function render.rebuild_player(player)
  render.drop_player(player.index)
  if not (player.valid and player.connected) then return end
  local style = style_of(player)
  local force_index = player.force.index
  local per_surface = {}
  storage.player_renders[player.index] = per_surface

  for surface_index, cells in pairs(storage.cells) do
    local surface = game.surfaces[surface_index]
    if surface and surface.valid and not storage.disabled_surfaces[surface_index] then
      local bucket = {}
      local function build(cx, cy)
        local key = registry.cell_key(cx, cy)
        if bucket[key] then return end
        local lines = build_player_lines(surface, cx, cy, player, style)
        if #lines > 0 then bucket[key] = lines end
      end
      for cell_key, rec in pairs(cells) do
        if rec.force_index == force_index then
          local pos = registry.cell_key_to_pos(cell_key)
          build(pos.x, pos.y)
          build(pos.x + 1, pos.y)
          build(pos.x, pos.y + 1)
        end
      end
      if next(bucket) then per_surface[surface_index] = bucket end
    end
  end
end

-- A state change (or fresh charting) of cell (cx, cy) affects the owned
-- objects of exactly these four cells.
function render.refresh_around(surface, cx, cy)
  render.refresh_cell(surface, cx, cy)
  render.refresh_cell(surface, cx + 1, cy)
  render.refresh_cell(surface, cx, cy + 1)
  render.refresh_cell(surface, cx + 1, cy + 1)
end

-- Surface teardown: destroy every render object and drop the bookkeeping,
-- shared and per-player alike.
function render.drop_surface(surface_index)
  local refs = storage.renders[surface_index]
  if refs then
    for _, objects in pairs(refs) do destroy_all(objects) end
  end
  storage.renders[surface_index] = nil
  for _, per_surface in pairs(storage.player_renders) do
    local bucket = per_surface[surface_index]
    if bucket then
      for _, objects in pairs(bucket) do destroy_all(objects) end
      per_surface[surface_index] = nil
    end
  end
end

return render
