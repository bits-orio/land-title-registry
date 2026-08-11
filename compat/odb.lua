-- Open Discord Bridge integrator (optional dependency). Additive polish,
-- not a compatibility requirement: the two mods already coexist by
-- construction (claim announcements go through force.print, which ODB does
-- not relay).
--
-- Emits only low-frequency milestone events — the anti-spam principle. No
-- per-claim emission path exists, not even behind a setting.
--
-- The module exposes hooks; control.lua composes them into its handlers for
-- Land Title Registry's own custom events (script.on_event replaces handlers, so this
-- module must never subscribe to shared events itself).

local registry = require("scripts.registry")
local tech = require("scripts.tech")

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
      namespace = "land-title-registry",
      events = {
        "land-title-registry.settlement_charter",
        "land-title-registry.first_deed",
        "land-title-registry.territory_milestone",
      },
    })
  end
end

function odb.on_points_changed(event)
  if event.reason ~= "settlement-charter" then return end
  emit("land-title-registry.settlement_charter", {
    force = event.force_name,
    points = event.delta,
  })
end

-- Deed milestones are per force per PLANET (all surfaces of the planet),
-- computed on the rare deed-claim event — no counters to keep consistent.
-- Planet resolution goes through tech.planet_name_of: an MTS cloned team
-- surface has no engine .planet but still represents one.
function odb.on_cell_claimed(event)
  if event.new_state ~= "deed" then return end
  local surface = game.surfaces[event.surface_index]
  if not (surface and surface.valid) then return end
  local force = game.forces[event.force_name]
  if not (force and force.valid) then return end

  local planet_name = tech.planet_name_of(surface)
  if not planet_name then return end
  local deeds = 0
  for _, candidate in pairs(game.surfaces) do
    if tech.planet_name_of(candidate) == planet_name then
      for _, rec in pairs(storage.cells[candidate.index] or {}) do
        if rec.state == "deed" and rec.force_index == force.index then
          deeds = deeds + 1
        end
      end
    end
  end

  if deeds == 1 then
    emit("land-title-registry.first_deed", { force = event.force_name, planet = planet_name }, surface.name)
  elseif deeds % MILESTONE_DEEDS == 0 then
    emit("land-title-registry.territory_milestone",
      { force = event.force_name, planet = planet_name, deeds = deeds }, surface.name)
  end
end

return odb
