-- Research income and settlement charters.
--
-- Grants: each finished fh-land-grants level credits the RESEARCHING force
-- fh-points-per-level; each reversed level debits the same amount — finish
-- then reverse is exactly net zero, including infinite-tech levels
-- (Gridlocked's known TODO bug; a hard requirement here).
--
-- Charters: the first time a force establishes presence on each planet it
-- receives fh-settlement-charter points, strictly once per (force, planet) —
-- keyed by surface.planet.name, never surface names or indices. The force's
-- FIRST-ever planet is recorded silently without a grant: that is the home
-- planet, and the starting grant already covers its cold start.

local const = require("scripts.const")
local economy = require("scripts.economy")
local claims = require("scripts.claims")
local welcome = require("scripts.welcome")

local tech = {}

local GRANT_PATTERN = "^fh%-land%-grants%-%d+$"

local function points_per_level()
  return settings.startup["fh-points-per-level"].value
end

function tech.on_research_finished(event)
  local research = event.research
  if not string.find(research.name, GRANT_PATTERN) then return end
  local amount = points_per_level()
  if amount > 0 then
    economy.change(research.force, amount, "research")
  end
end

function tech.on_research_reversed(event)
  local research = event.research
  if not string.find(research.name, GRANT_PATTERN) then return end
  local amount = points_per_level()
  if amount > 0 then
    economy.change(research.force, -amount, "research-reversed")
  end
end

-- ---------------------------------------------------------------------------
-- Settlement charters

local function charters_of(force_index)
  storage.charters = storage.charters or {}
  storage.charters[force_index] = storage.charters[force_index] or {}
  return storage.charters[force_index]
end

-- Record presence of `force` on `surface`'s planet; grant when it is a new
-- planet and not the force's first (home) one.
-- Starter cell (ADR-0011): a free DEED on the cell the player is actually
-- standing on — the visible anchor showing the cell grid, where growth
-- begins, and the transparent end state of the ladder. The condition is
-- "the force owns nothing on this planet", NOT first-presence bookkeeping:
-- that retrofits saves that recorded presence before the grant existed,
-- and doubles as recovery if a force downgrades away everything. Granting
-- at PRESENCE position is what makes Space Age cargo pods work too.
local function force_owns_on_planet(force, planet)
  for _, candidate in pairs(game.surfaces) do
    if candidate.planet and candidate.planet.name == planet.name then
      if storage.cells[candidate.index] then
        for _, rec in pairs(storage.cells[candidate.index]) do
          if rec.force_index == force.index then return true end
        end
      end
    end
  end
  return false
end

local function maybe_grant_starter(force, surface, player, draw_hints)
  if not (player and player.valid and player.physical_surface_index == surface.index) then return end
  local planet = surface.planet
  if not planet then return end
  if force_owns_on_planet(force, planet) then return end

  local cx = math.floor(player.physical_position.x / const.CELL)
  local cy = math.floor(player.physical_position.y / const.CELL)
  if claims.grant_free(surface, force, player, cx, cy, "deed") then
    force.print({ "freehold.starter-cell",
      string.format("[gps=%d,%d,%s]",
        cx * const.CELL + const.CELL / 2,
        cy * const.CELL + const.CELL / 2, surface.name) })
    if draw_hints then
      welcome.draw_origin_hints(force, surface, cx, cy)
    end
  end
end

local function establish_presence(force, surface, player)
  if not (force and force.valid and surface and surface.valid) then return end
  local planet = surface.planet
  if not planet then return end -- space platforms and planet-less surfaces

  local charters = charters_of(force.index)
  local is_first_planet = next(charters) == nil

  -- The starter grant runs before the charter early-return so it can
  -- retrofit saves whose presence was recorded before the grant existed.
  maybe_grant_starter(force, surface, player, is_first_planet)

  if charters[planet.name] then return end
  charters[planet.name] = true

  if is_first_planet then return end -- home planet: starting grant covers it

  local amount = settings.global["fh-settlement-charter"].value
  if amount > 0 then
    economy.change(force, amount, "settlement-charter")
    force.print({ "freehold.settlement-charter", planet.prototype.localised_name or planet.name, amount })
  end
end

function tech.on_player_created(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then establish_presence(player.force, player.surface, player) end
end

function tech.on_player_changed_surface(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then establish_presence(player.force, player.surface, player) end
end

function tech.on_player_joined(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then establish_presence(player.force, player.surface, player) end
end

function tech.on_player_changed_force(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then establish_presence(player.force, player.surface, player) end
end

-- Merged forces: union charter records so the survivor cannot re-farm a
-- planet the source had already chartered (called from economy's merge).
function tech.merge_charters(source_index, destination_index)
  storage.charters = storage.charters or {}
  local source = storage.charters[source_index]
  if source then
    local destination = charters_of(destination_index)
    for planet_name in pairs(source) do
      destination[planet_name] = true
    end
    storage.charters[source_index] = nil
  end
end

return tech
