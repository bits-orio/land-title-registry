-- Multi-Team Support consumer (optional dependency). Land Title Registry is the
-- reference consumer of MTS's COMPAT.md patterns; MTS ships zero
-- Land Title Registry-specific code — integration flows one way, through mts-v1.
--
-- Everything here no-ops when MTS is absent: the module returns
-- { active = false } and control.lua's composition points check the flag.
-- Event subscriptions below target MTS's own custom-event ids (resolved at
-- root scope, never stored — ids regenerate every session), which cannot
-- collide with control.lua's handlers.

local economy = require("scripts.economy")
local blockers = require("scripts.blockers")
local render = require("scripts.render")
local chronicle = require("scripts.chronicle")
local tech = require("scripts.tech")
local outposts = require("scripts.outposts")

local mts = { active = false }

if not script.active_mods["multi-team-support"] then
  return mts
end
mts.active = true

-- Team colors on the survey stakes (edges carry per-STATE colors shared
-- with the ground overlays; ownership identity lives on the stakes): MTS
-- assigns each team force its color, so the force's own color is the team
-- color — no extra mts-v1 surface needed. Without MTS this provider is
-- never installed and the per-planet color settings apply.
render.team_color_provider = function(force_index)
  local force = game.forces[force_index]
  if force and force.valid then
    return force.custom_color or force.color
  end
end

-- Cell chronicle: team display names and team-clock starts come straight
-- from mts-v1's get_team_info — zero new MTS surface. Non-team forces fall
-- back to force name + absolute time inside the chronicle module.
chronicle.surface_planet_provider = function(surface)
  if not remote.interfaces["mts-v1"] then return nil end
  if not remote.interfaces["mts-v1"]["get_surface_planet"] then return nil end
  return remote.call("mts-v1", "get_surface_planet", surface.name)
end

-- Every mention of a team uses MTS's own label convention: colored team
-- tag plus current leader in brackets. Live state, so never cached across
-- ticks by the caller.
chronicle.team_label_provider = function(force_name)
  if not remote.interfaces["mts-v1"] then return nil end
  if not remote.interfaces["mts-v1"]["get_team_label"] then return nil end
  return remote.call("mts-v1", "get_team_label", force_name)
end

chronicle.team_tag_provider = function(force_name)
  if not remote.interfaces["mts-v1"] then return nil end
  if not remote.interfaces["mts-v1"]["get_team_tag"] then return nil end
  return remote.call("mts-v1", "get_team_tag", force_name)
end

-- Land Title Registry's celebrations ride MTS's own animated pop_text presets, so
-- they look native next to MTS's milestones instead of reinventing them.
chronicle.popup_provider = function(preset, text, force_name)
  if not remote.interfaces["mts-v1"] then return false end
  if not remote.interfaces["mts-v1"]["popup_text"] then return false end
  return remote.call("mts-v1", "popup_text",
    { preset = preset, text = text, force_name = force_name }) and true or false
end

chronicle.team_info_provider = function(force_name)
  if not remote.interfaces["mts-v1"] then return nil end
  if not remote.interfaces["mts-v1"]["get_team_info"] then return nil end
  return remote.call("mts-v1", "get_team_info", force_name)
end

-- Grid only on team surfaces — but ONLY once MTS's team flow is actually
-- running (at least one team exists). MTS merely being installed must not
-- kill Land Title Registry on plain nauvis freeplay: is_team_surface("nauvis") is
-- false there too, and pre-gating on it swept legitimate grids (found in
-- playtest, reproduced headless). No surface names are enumerated: the
-- signal is MTS's own team list and team lifecycle events.
local function teams_active()
  if not remote.interfaces["mts-v1"] then return false end
  if not remote.interfaces["mts-v1"]["get_team_list"] then return false end
  local list = remote.call("mts-v1", "get_team_list")
  if type(list) ~= "table" then return false end
  -- MTS pre-creates its slot POOL at init, so a non-empty list does not
  -- mean the flow is running — an OCCUPIED slot does.
  for _, info in pairs(list) do
    if info.is_occupied then return true end
  end
  return false
end

function mts.should_disable(surface)
  if not remote.interfaces["mts-v1"] then return false end
  local non_team = not remote.call("mts-v1", "is_team_surface", surface.name)
  -- Script-made, planet-less, non-team surfaces (the landing pen, lobbies)
  -- are never play surfaces: gate them immediately, no waiting (playtest
  -- report: wilderness overlays in the pen). The occupied-team wait below
  -- exists only to protect PLANET surfaces — plain-nauvis freeplay with
  -- MTS installed but unused — and every planet surface has a planet.
  if non_team and not surface.planet then return true end
  if not teams_active() then return false end
  return non_team
end

-- When the first team appears, the flow is real: gate the non-team,
-- claim-less surfaces (the pen and lobbies; a surface holding claims is
-- legitimate ground and is left alone). Public: also invoked from the
-- chart-epoch migration so existing saves shed pen overlays.
function mts.sweep_non_team_surfaces()
  for _, surface in pairs(game.surfaces) do
    if not surface.platform
      and not storage.disabled_surfaces[surface.index]
      and mts.should_disable(surface) then
      local cells = storage.cells[surface.index]
      if not (cells and next(cells)) then
        storage.disabled_surfaces[surface.index] = true
        blockers.enqueue_surface_rebuild(surface)
      end
    end
  end
end
local sweep_non_team_surfaces = mts.sweep_non_team_surfaces

-- Resolve MTS's custom-event ids and subscribe. Ids regenerate every
-- session and remote.call is not allowed at control.lua root scope in 2.0,
-- so control.lua calls this from BOTH on_init and on_load — the two entry
-- points that run before any events each session.
function mts.resolve_events()
  if not remote.interfaces["mts-v1"] then return end

  -- A surface may be created before MTS registers its ownership, so
  -- init_surface's is_team_surface check can race to "disabled". MTS's
  -- on_team_surface_created event settles it: enable and reconcile.
  local on_team_surface_created =
    remote.call("mts-v1", "get_event_id", "on_team_surface_created")
  if on_team_surface_created then
    script.on_event(on_team_surface_created, function(event)
      local surface = game.surfaces[event.surface_name]
      if surface and surface.valid and not surface.platform then
        storage.disabled_surfaces[surface.index] = nil
        -- The team's spawn area was charted DURING surface creation —
        -- before this rebuild creates the hidden map sprites — and
        -- on_chunk_charted never re-fires for chunks under constant
        -- vision. The drain-end rechart volley is the reveal.
        storage.rechart_pending = true
        blockers.enqueue_surface_rebuild(surface)
      end
    end)
  end

  local on_team_created = remote.call("mts-v1", "get_event_id", "on_team_created")
  if on_team_created then
    script.on_event(on_team_created, sweep_non_team_surfaces)
  end

  -- Recycled team slots must not inherit the previous occupant's state —
  -- balance, chronicle records, charter history, or outpost slots. This is
  -- what reset_force exists for, and why it is implemented and exercised
  -- from day one rather than left as a stub in the interface. The
  -- chronicle purge doubles as the fix for the re-deed bug: a stale entry
  -- under the recycled name trips the already-recorded guard, so the new
  -- occupant's deed would never enter the standings.
  local on_team_released =
    remote.call("mts-v1", "get_event_id", "on_team_released")
  if on_team_released then
    script.on_event(on_team_released, function(event)
      local force = game.forces[event.force_name]
      if force and force.valid then
        economy.set(force, settings.global["ltr-starting-points"].value, "reset")
        chronicle.on_team_released(force.name)
        tech.reset_charters(force.index)
        outposts.reset_force(force.index)
      end
    end)
  end
end

return mts
