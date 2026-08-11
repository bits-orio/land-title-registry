-- Research income and settlement charters.
--
-- Grants: each finished ltr-land-grants level credits the RESEARCHING force
-- ltr-points-per-level; each reversed level debits the same amount — finish
-- then reverse is exactly net zero, including infinite-tech levels. The
-- infinite-level case is the easy one to miss and a hard requirement here.
--
-- Charters: the first time a force establishes presence on each planet it
-- receives ltr-settlement-charter points, strictly once per (force, planet) —
-- keyed by surface.planet.name, never surface names or indices. The force's
-- FIRST-ever planet is recorded silently without a grant: that is the home
-- planet, and the starting grant already covers its cold start.

local const = require("scripts.const")
local economy = require("scripts.economy")
local claims = require("scripts.claims")
local welcome = require("scripts.welcome")
local chronicle = require("scripts.chronicle")

local tech = {}

local GRANT_PATTERN = "^ltr%-land%-grants%-%d+$"

local function points_per_level()
  return settings.startup["ltr-points-per-level"].value
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

-- Optional provider: compat/mts.lua overrides the HOME starter cell for
-- team surfaces (cell (0,0) exactly — every team races the same origin
-- cell, so cross-team chronicle times compare fairly). Returns cx, cy or
-- nil to fall through.
tech.home_cell_provider = nil

-- The home starter cell (playtest call: deterministic, not wherever the
-- player happens to stand). MTS team surfaces spawn at the origin and the
-- provider pins (0,0); everywhere else the force's spawn point decides,
-- which is the map origin on default freeplay and respects custom spawns.
local function home_cell(force, surface)
  if tech.home_cell_provider then
    local cx, cy = tech.home_cell_provider(surface)
    if cx then return cx, cy end
  end
  local spawn = force.get_spawn_position(surface)
  return math.floor(spawn.x / const.CELL), math.floor(spawn.y / const.CELL)
end

-- Every refusal logs its gate (LTR-GRANT): a missing starter Deed was a
-- silent mystery once (playtest report), never again.
local function maybe_grant_starter(force, surface, player, is_home)
  if not (player and player.valid and player.physical_surface_index == surface.index) then
    log("LTR-GRANT skip: player not physically on " .. surface.name)
    return
  end
  local planet = surface.planet
  if not planet then
    log("LTR-GRANT skip: " .. surface.name .. " has no planet")
    return
  end
  -- Never gift land to a non-competing force: under MTS players sit on
  -- `player` before joining a team and on `spectator` while watching, and
  -- granting there produced the bogus "Team player"/"Team spectator"
  -- chronicle entries seen in play.
  if not chronicle.is_competitor(force.name) then
    log("LTR-GRANT skip: " .. force.name .. " is not a competing force")
    return
  end
  if force_owns_on_planet(force, planet) then return end

  -- Home planet: the deterministic spawn cell. Later planets: the cell
  -- the player actually stands on — a cargo pod lands wherever it lands,
  -- and a spawn-cell grant there could be disconnected land the player
  -- never reached.
  local cx, cy
  if is_home then
    cx, cy = home_cell(force, surface)
  else
    cx = math.floor(player.physical_position.x / const.CELL)
    cy = math.floor(player.physical_position.y / const.CELL)
  end
  if claims.grant_free(surface, force, player, cx, cy, "deed") then
    log(string.format("LTR-GRANT: starter Deed (%d,%d) on %s for %s", cx, cy, surface.name, force.name))
    force.print({ "land-title-registry.starter-cell",
      string.format("[gps=%d,%d,%s]",
        cx * const.CELL + const.CELL / 2,
        cy * const.CELL + const.CELL / 2, surface.name) })
    if is_home then
      welcome.draw_origin_hints(force, surface, cx, cy)
    end
  else
    log(string.format("LTR-GRANT skip: grant_free refused (%d,%d) on %s — disabled surface, occupied cell, or ungenerated chunk",
      cx, cy, surface.name))
  end
end

local function establish_presence(force, surface, player)
  if not (force and force.valid and surface and surface.valid) then return end
  local planet = surface.planet
  if not planet then
    -- Space platforms and planet-less surfaces (the MTS pen); logged so a
    -- starter-grant hunt can see presence events that never qualify.
    log("LTR-GRANT skip: presence on planet-less " .. surface.name)
    return
  end

  local charters = charters_of(force.index)
  local is_first_planet = next(charters) == nil
  log(string.format("LTR-GRANT presence: %s on %s (first_planet=%s)",
    force.name, surface.name, tostring(is_first_planet)))

  -- The starter grant runs before the charter early-return so it can
  -- retrofit saves whose presence was recorded before the grant existed.
  maybe_grant_starter(force, surface, player, is_first_planet)

  if charters[planet.name] then return end
  charters[planet.name] = true

  if is_first_planet then return end -- home planet: starting grant covers it

  local amount = settings.global["ltr-settlement-charter"].value
  if amount > 0 then
    economy.change(force, amount, "settlement-charter")
    force.print({ "land-title-registry.settlement-charter", planet.prototype.localised_name or planet.name, amount })
  end
end

-- Public retry for surface-enablement races: MTS can enable a team
-- surface AFTER its players already landed there (deferred teleport
-- queues), so the landing-time grant attempt found a disabled surface
-- and refused. compat/mts.lua calls this when a team surface enables.
function tech.establish_presence_for_surface(surface)
  for _, player in pairs(game.connected_players) do
    if player.valid and player.physical_surface_index == surface.index then
      establish_presence(player.force, surface, player)
    end
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

-- Recycled team slots start blank: without this a re-created team inherits
-- its predecessor's charter history and never receives settlement grants.
function tech.reset_charters(force_index)
  if storage.charters then storage.charters[force_index] = nil end
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
