-- Per-player Land-points readout, built with the mod-gui library — never a
-- raw screen frame positioned by resolution arithmetic. Refresh triggers
-- (all mandatory, see *Player Experience*): every points change for the
-- force, on_player_changed_force (MTS moves players between forces, and the
-- readout must rebind to the new force rather than go stale), player
-- create/join, and the ltr-show-points per-user setting.

local mod_gui = require("mod-gui")
local economy = require("scripts.economy")

local hud = {}

local FRAME_NAME = "ltr_points"

local function visible_for(player)
  return player.mod_settings["ltr-show-points"].value
end

local function frame_of(player)
  return mod_gui.get_frame_flow(player)[FRAME_NAME]
end

function hud.update(player)
  if not (player and player.valid) then return end
  local frame = frame_of(player)
  if not visible_for(player) then
    if frame then frame.destroy() end
    return
  end
  if not frame then
    frame = mod_gui.get_frame_flow(player).add({
      type = "frame",
      name = FRAME_NAME,
      style = mod_gui.frame_style,
    })
    frame.add({ type = "label", name = "points" })
  end
  frame.points.caption = { "land-title-registry.hud-points", economy.format(economy.get(player.force.index)) }
end

function hud.on_player_created(event)
  hud.update(game.get_player(event.player_index))
end

function hud.on_player_joined(event)
  hud.update(game.get_player(event.player_index))
end

function hud.on_player_changed_force(event)
  hud.update(game.get_player(event.player_index))
end

-- Balance changed for a force: refresh exactly that force's members
-- (force.players is already the correct subset — COMPAT.md pattern 4).
function hud.on_points_changed(event)
  local force = game.forces[event.force_name]
  if not (force and force.valid) then return end
  for _, player in pairs(force.players) do
    hud.update(player)
  end
end

function hud.on_setting_changed(event)
  if event.setting ~= "ltr-show-points" or not event.player_index then return end
  hud.update(game.get_player(event.player_index))
end

return hud
