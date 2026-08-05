-- The cell chronicle (ADR-0012): a per-cell speedrun leaderboard. For every
-- (planet, cell), the teams that have deeded that cell, ranked by how FAST
-- they did it on their own team clock — not by who arrived first. A later
-- team posting a better time rightfully displaces earlier entries, and the
-- drawn rankings update to match. This exploits MTS's isolated-copies
-- structure (cell (x, y) is directly comparable across team surfaces of a
-- planet) for asynchronous competition with zero physical interference.
--
-- Records are keyed by PLANET, so they survive surface clears and outlive
-- downgrades: a chronicle entry is an achievement, not a state.
--
-- Rendered as tiny text lines under each cell's top edge (centered) on
-- EVERY surface of the planet — each team sees the standings on its own
-- copy. Recognition (flying text + chat) fires only when at least two
-- teams hold entries, so vanilla single-force play gets the quiet personal
-- log without "Fastest!" spam.

local const = require("scripts.const")
local registry = require("scripts.registry")

local chronicle = {}

-- compat/mts.lua installs a provider returning
-- { display_name = ?, clock_start_tick = ? } for a force name, via
-- mts-v1's get_team_info. Without it (or for non-team forces), names are
-- force names and clocks fall back to absolute game time.
chronicle.team_info_provider = nil

local RANK_COLORS = {
  { r = 1.0, g = 0.85, b = 0.40 }, -- gold
  { r = 0.80, g = 0.82, b = 0.88 }, -- silver
  { r = 0.80, g = 0.60, b = 0.42 }, -- bronze
}

local function team_info(force_name)
  if chronicle.team_info_provider then
    local info = chronicle.team_info_provider(force_name)
    if info then return info end
  end
  return { display_name = force_name, clock_start_tick = 0 }
end

local function format_clock(ticks)
  local total = math.floor(ticks / 60)
  local h = math.floor(total / 3600)
  local m = math.floor(total / 60) % 60
  local s = total % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%d:%02d", m, s)
end

local function entries_of(planet_name, cell_key)
  storage.chronicle[planet_name] = storage.chronicle[planet_name] or {}
  storage.chronicle[planet_name][cell_key] = storage.chronicle[planet_name][cell_key] or {}
  return storage.chronicle[planet_name][cell_key]
end

-- Destroy and redraw the chronicle text of one cell on one surface.
function chronicle.refresh_cell(surface, cx, cy)
  local surface_index = surface.index
  storage.chronicle_renders[surface_index] = storage.chronicle_renders[surface_index] or {}
  local refs = storage.chronicle_renders[surface_index]
  local cell_key = registry.cell_key(cx, cy)

  local old = refs[cell_key]
  if old then
    for _, object in pairs(old) do
      if object.valid then object.destroy() end
    end
    refs[cell_key] = nil
  end

  if storage.disabled_surfaces[surface_index] then return end
  local planet = surface.planet
  if not planet then return end
  local entries = (storage.chronicle[planet.name] or {})[cell_key]
  if not entries or #entries == 0 then return end

  local objects = {}
  local x = cx * const.CELL + const.CELL / 2
  local y = cy * const.CELL + 0.45
  for rank = 1, math.min(3, #entries) do
    local entry = entries[rank]
    objects[#objects + 1] = rendering.draw_text({
      text = { "freehold.chronicle-line", rank,
        team_info(entry.force_name).display_name, format_clock(entry.clock) },
      surface = surface,
      target = { x = x, y = y + (rank - 1) * 0.62 },
      color = RANK_COLORS[rank],
      scale = 0.7,
      alignment = "center",
      use_rich_text = true,
    })
  end
  refs[cell_key] = objects
end

local function redraw_on_planet(planet_name, cx, cy)
  for _, surface in pairs(game.surfaces) do
    if surface.planet and surface.planet.name == planet_name then
      chronicle.refresh_cell(surface, cx, cy)
    end
  end
end

-- A cell reached Deed: record the team's time (first Deed of that cell per
-- team; later re-deeds don't improve it), re-rank, redraw, recognize.
function chronicle.on_cell_claimed(event)
  if event.new_state ~= "deed" then return end
  local surface = game.surfaces[event.surface_index]
  if not (surface and surface.valid and surface.planet) then return end
  local planet_name = surface.planet.name
  local cell_key = registry.cell_key(event.cell_pos.x, event.cell_pos.y)
  local entries = entries_of(planet_name, cell_key)

  for _, entry in pairs(entries) do
    if entry.force_name == event.force_name then return end -- time already set
  end

  local info = team_info(event.force_name)
  local clock = event.tick - (info.clock_start_tick or 0)
  entries[#entries + 1] = { force_name = event.force_name, clock = clock }
  table.sort(entries, function(a, b)
    if a.clock ~= b.clock then return a.clock < b.clock end
    return a.force_name < b.force_name -- deterministic tiebreak
  end)

  local rank
  for i, entry in ipairs(entries) do
    if entry.force_name == event.force_name then rank = i break end
  end

  redraw_on_planet(planet_name, event.cell_pos.x, event.cell_pos.y)

  -- Recognition only when there is actual competition on this cell.
  if #entries < 2 or rank > 3 then return end
  local force = game.forces[event.force_name]
  if not (force and force.valid) then return end
  local gps = string.format("[gps=%d,%d,%s]",
    event.cell_pos.x * const.CELL + const.CELL / 2,
    event.cell_pos.y * const.CELL + const.CELL / 2, surface.name)
  force.print({ "freehold.chron-chat", { "freehold.chron-rank-" .. rank },
    format_clock(clock), gps })
  if event.player_index then
    local player = game.get_player(event.player_index)
    if player and player.valid then
      player.create_local_flying_text({
        text = { "freehold.chron-fly-" .. rank },
        create_at_cursor = true,
      })
    end
  end
end

-- Merged forces: keep each cell's best time under the surviving name.
function chronicle.on_forces_merged(event)
  local destination_name = event.destination.name
  for _, cells in pairs(storage.chronicle) do
    for _, entries in pairs(cells) do
      local best_own
      for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry.force_name == event.source_name or entry.force_name == destination_name then
          if best_own == nil or entry.clock < best_own then best_own = entry.clock end
          table.remove(entries, i)
        end
      end
      if best_own then
        entries[#entries + 1] = { force_name = destination_name, clock = best_own }
        table.sort(entries, function(a, b)
          if a.clock ~= b.clock then return a.clock < b.clock end
          return a.force_name < b.force_name
        end)
      end
    end
  end
end

-- Retrofit: deeds that predate the chronicle feature enter it from the
-- registry. The stored claimed_tick is the cell's FIRST CLAIM (not its
-- deed moment) — the best record that exists, so backfilled times read
-- slightly faster than they were; honest and one-time. Idempotent: teams
-- already present in a cell's chronicle are never re-added.
function chronicle.backfill()
  local added = 0
  for surface_index, cells in pairs(storage.cells) do
    local surface = game.surfaces[surface_index]
    if surface and surface.valid and surface.planet then
      local planet_name = surface.planet.name
      for cell_key, rec in pairs(cells) do
        if rec.state == "deed" then
          local force = game.forces[rec.force_index]
          if force and force.valid then
            local entries = entries_of(planet_name, cell_key)
            local present = false
            for _, entry in pairs(entries) do
              if entry.force_name == force.name then present = true end
            end
            if not present then
              local info = team_info(force.name)
              local clock = math.max(0, (rec.claimed_tick or 0) - (info.clock_start_tick or 0))
              entries[#entries + 1] = { force_name = force.name, clock = clock }
              table.sort(entries, function(a, b)
                if a.clock ~= b.clock then return a.clock < b.clock end
                return a.force_name < b.force_name
              end)
              added = added + 1
            end
          end
        end
      end
    end
  end
  return added
end

function chronicle.drop_surface(surface_index)
  local refs = storage.chronicle_renders[surface_index]
  if refs then
    for _, objects in pairs(refs) do
      for _, object in pairs(objects) do
        if object.valid then object.destroy() end
      end
    end
  end
  storage.chronicle_renders[surface_index] = nil
end

return chronicle
