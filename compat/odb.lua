-- Open Discord Bridge integrator (optional dependency). Additive polish,
-- not a compatibility requirement: the two mods already coexist by
-- construction (claim announcements go through force.print, which ODB does
-- not relay).
--
-- Emits only low-frequency milestone events — the anti-spam principle. No
-- per-claim emission path exists, not even behind a setting.
--
-- The module exposes hooks; control.lua composes them into its handlers for
-- Freehold's own custom events (script.on_event replaces handlers, so this
-- module must never subscribe to shared events itself).

local registry = require("scripts.registry")

local odb = { active = false }

if not script.active_mods["open-discord-bridge"] then
  return odb
end
odb.active = true

local INTERFACE = "open-discord-bridge-v1"
local MILESTONE_DEEDS = 25

local function emit(event, data, surface_name)
  if remote.interfaces[INTERFACE] then
    remote.call(INTERFACE, "emit", { event = event, data = data, surface = surface_name })
  end
end

-- Declare the event catalog so the bridge offers per-event routing toggles
-- without hardcoding any mod. register_source writes to ODB's storage, so
-- this is called from on_init / on_configuration_changed, never root scope.
function odb.register()
  if remote.interfaces[INTERFACE] then
    remote.call(INTERFACE, "register_source", {
      namespace = "freehold",
      events = {
        "freehold.settlement_charter",
        "freehold.first_deed",
        "freehold.territory_milestone",
      },
    })
  end
end

function odb.on_points_changed(event)
  if event.reason ~= "settlement-charter" then return end
  emit("freehold.settlement_charter", {
    force = event.force_name,
    points = event.delta,
  })
end

-- Deed milestones are per force per PLANET (all surfaces of the planet),
-- computed on the rare deed-claim event — no counters to keep consistent.
function odb.on_cell_claimed(event)
  if event.new_state ~= "deed" then return end
  local surface = game.surfaces[event.surface_index]
  if not (surface and surface.valid and surface.planet) then return end
  local force = game.forces[event.force_name]
  if not (force and force.valid) then return end

  local planet_name = surface.planet.name
  local deeds = 0
  for _, candidate in pairs(game.surfaces) do
    if candidate.planet and candidate.planet.name == planet_name then
      for _, rec in pairs(storage.cells[candidate.index] or {}) do
        if rec.state == "deed" and rec.force_index == force.index then
          deeds = deeds + 1
        end
      end
    end
  end

  if deeds == 1 then
    emit("freehold.first_deed", { force = event.force_name, planet = planet_name }, surface.name)
  elseif deeds % MILESTONE_DEEDS == 0 then
    emit("freehold.territory_milestone",
      { force = event.force_name, planet = planet_name, deeds = deeds }, surface.name)
  end
end

return odb
