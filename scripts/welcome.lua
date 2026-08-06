-- Onboarding: the first-join welcome panel and the surface-drawn gesture
-- hints at the starter cell. Every player-facing key reference uses the
-- __CONTROL__ltr-get-survey-tool__ locale macro, so rebinds show correctly.

local const = require("scripts.const")

local welcome = {}

local FRAME_NAME = "ltr_welcome"

function welcome.show(player)
  if not (player and player.valid) then return end
  if player.gui.screen[FRAME_NAME] then return end
  local frame = player.gui.screen.add({
    type = "frame",
    name = FRAME_NAME,
    direction = "vertical",
    caption = { "land-title-registry.welcome-title" },
  })
  frame.add({ type = "label", name = "l1", caption = { "land-title-registry.welcome-line-1" } })
  frame.add({ type = "label", name = "l2", caption = { "land-title-registry.welcome-line-2" } })
  frame.add({ type = "label", name = "l3", caption = { "land-title-registry.welcome-line-3" } })
  frame.add({ type = "label", name = "l4", caption = { "land-title-registry.welcome-line-4" } })
  local buttons = frame.add({ type = "flow", name = "buttons", direction = "horizontal" })
  buttons.add({ type = "button", name = "ltr_welcome_grab", style = "confirm_button", caption = { "land-title-registry.welcome-grab" } })
  buttons.add({ type = "button", name = "ltr_welcome_close", caption = { "land-title-registry.welcome-close" } })
  frame.force_auto_center()
end

-- Existing saves: players created before the panel existed get it once on
-- their next join.
function welcome.on_player_joined(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  if storage.welcomed[player.index] then return end
  storage.welcomed[player.index] = true
  welcome.show(player)
end

function welcome.on_player_created(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  if storage.welcomed[player.index] then return end
  storage.welcomed[player.index] = true
  welcome.show(player)
end

function welcome.on_gui_click(event)
  local element = event.element
  if not (element and element.valid) then return end
  if element.name ~= "ltr_welcome_grab" and element.name ~= "ltr_welcome_close" then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  if element.name == "ltr_welcome_grab" and player.cursor_stack then
    player.clear_cursor()
    player.cursor_stack.set_stack("ltr-survey-tool")
  end
  local frame = player.gui.screen[FRAME_NAME]
  if frame then frame.destroy() end
end

-- Gesture hints drawn in the world at the starter cell (fancy, per-force,
-- destroyed on the force's first PAID claim so veterans stop seeing them).
function welcome.draw_origin_hints(force, surface, cx, cy)
  if storage.tutorial_renders[force.index] then return end
  local x = cx * const.CELL + const.CELL / 2
  local y = cy * const.CELL + const.CELL / 2
  local lines = {
    { text = { "land-title-registry.origin-hint-1" }, dy = -3.2, scale = 2.2 },
    { text = { "land-title-registry.origin-hint-2" }, dy = -0.8, scale = 1.3 },
    { text = { "land-title-registry.origin-hint-3" }, dy = 0.6, scale = 1.3 },
    { text = { "land-title-registry.origin-hint-4" }, dy = 2.0, scale = 1.3 },
  }
  local objects = {}
  for _, line in ipairs(lines) do
    objects[#objects + 1] = rendering.draw_text({
      text = line.text,
      surface = surface,
      target = { x = x, y = y + line.dy },
      color = { r = 1, g = 1, b = 1, a = 0.9 },
      scale = line.scale,
      alignment = "center",
      forces = { force },
    })
  end
  storage.tutorial_renders[force.index] = objects
end

local function destroy_hints(force_index)
  local objects = storage.tutorial_renders[force_index]
  if not objects then return end
  for _, object in pairs(objects) do
    if object.valid then object.destroy() end
  end
  storage.tutorial_renders[force_index] = nil
end

-- First paid claim: the force has learned the gesture; retire the hints.
function welcome.on_cell_claimed(event)
  if not event.cost or event.cost == 0 then return end
  local force = game.forces[event.force_name]
  if force and force.valid then destroy_hints(force.index) end
end

function welcome.on_forces_merged(event)
  destroy_hints(event.source_index)
end

return welcome
