-- Multi-Team Support consumer (optional dependency). Freehold is the
-- reference consumer of MTS's COMPAT.md patterns; MTS ships zero
-- Freehold-specific code — integration flows one way, through mts-v1.
--
-- Everything here no-ops when MTS is absent: the module returns
-- { active = false } and control.lua's composition points check the flag.
-- Event subscriptions below target MTS's own custom-event ids (resolved at
-- root scope, never stored — ids regenerate every session), which cannot
-- collide with control.lua's handlers.

local economy = require("scripts.economy")
local blockers = require("scripts.blockers")
local render = require("scripts.render")

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

-- Grid only on team surfaces. The landing pen, lobbies, and any special
-- surface MTS invents later are not team surfaces and get no grid — with
-- no enumeration of surface roles anywhere (uses mts-v1's existing
-- is_team_surface). Called by control.lua's init_surface.
function mts.should_disable(surface)
  if not remote.interfaces["mts-v1"] then return false end
  return not remote.call("mts-v1", "is_team_surface", surface.name)
end

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
        blockers.enqueue_surface_rebuild(surface)
      end
    end)
  end

  -- Recycled team slots must not inherit the previous occupant's balance —
  -- the founding grievance behind reset_force (MTS's Gridlocked shim calls
  -- a reset_force that Gridlocked never implemented).
  local on_team_released =
    remote.call("mts-v1", "get_event_id", "on_team_released")
  if on_team_released then
    script.on_event(on_team_released, function(event)
      local force = game.forces[event.force_name]
      if force and force.valid then
        economy.set(force, settings.global["fh-starting-points"].value, "reset")
      end
    end)
  end
end

return mts
