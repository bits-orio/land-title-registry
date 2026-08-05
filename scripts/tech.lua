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
local function establish_presence(force, surface, player)
  if not (force and force.valid and surface and surface.valid) then return end
  local planet = surface.planet
  if not planet then return end -- space platforms and planet-less surfaces

  local charters = charters_of(force.index)
  if charters[planet.name] then return end

  local is_first_planet = next(charters) == nil
  charters[planet.name] = true

  -- Starter cell (ADR-0011): a free Trail on the cell the player is
  -- actually standing on — the visible anchor that shows the cell grid and
  -- where growth begins. Granting at PRESENCE position rather than the
  -- spawn point is what makes this work for Space Age cargo pods too.
  if player and player.valid and player.physical_surface_index == surface.index then
    local cx = math.floor(player.physical_position.x / const.CELL)
    local cy = math.floor(player.physical_position.y / const.CELL)
    if claims.grant_free(surface, force, player, cx, cy) then
      force.print({ "freehold.starter-cell",
        string.format("[gps=%d,%d,%s]",
          cx * const.CELL + const.CELL / 2,
          cy * const.CELL + const.CELL / 2, surface.name) })
      if is_first_planet then
        welcome.draw_origin_hints(force, surface, cx, cy)
      end
    end
  end

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
