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

-- The panel no longer auto-opens (playtest call: it was one dialog too
-- many on top of MTS's own join flow). It remains reachable on demand via
-- /ltr-welcome; the in-world origin hints and the tips-and-tricks entries
-- carry the onboarding.

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

-- World text drawn per force at a teaching moment. use_rich_text is
-- load-bearing: the __CONTROL__ locale macros expand into font/color tags
-- (playtest screenshot: raw tags on screen without it), and the title line
-- carries the survey-tool icon.
local function draw_lines(surface, force, x, y, lines)
  local objects = {}
  for _, line in ipairs(lines) do
    objects[#objects + 1] = rendering.draw_text({
      text = line.text,
      surface = surface,
      target = { x = x, y = y + line.dy },
      color = { r = 1, g = 1, b = 1, a = 0.9 },
      scale = line.scale,
      alignment = "center",
      use_rich_text = true,
      forces = { force },
    })
  end
  return objects
end

-- Gesture hints drawn in the world at the starter cell (fancy, per-force,
-- destroyed on the force's first PAID claim so veterans stop seeing them).
function welcome.draw_origin_hints(force, surface, cx, cy)
  if storage.tutorial_renders[force.index] then return end
  local x = cx * const.CELL + const.CELL / 2
  local y = cy * const.CELL + const.CELL / 2
  storage.tutorial_renders[force.index] = draw_lines(surface, force, x, y, {
    { text = { "land-title-registry.origin-hint-1" }, dy = -3.2, scale = 2.2 },
    { text = { "land-title-registry.origin-hint-2" }, dy = -0.8, scale = 1.3 },
    { text = { "land-title-registry.origin-hint-3" }, dy = 0.6, scale = 1.3 },
    { text = { "land-title-registry.origin-hint-4" }, dy = 2.0, scale = 1.3 },
  })
end

local function destroy_hints(force_index)
  local objects = storage.tutorial_renders[force_index]
  if not objects then return end
  for _, object in pairs(objects) do
    if object.valid then object.destroy() end
  end
  storage.tutorial_renders[force_index] = nil
end

-- ---------------------------------------------------------------------------
-- Per-state tutorials (playtest ask, modeled on the starter-cell hints):
-- the force's FIRST paid claim of each state draws a short explainer on
-- that cell — recurring reinforcement of what Trail, Rampart, and Deed
-- mean, on the ground where it applies. The text retires the moment the
-- force builds something inside the cell (the lesson has landed) or the
-- cell changes state. Shown once per force, ever.

local STATE_HINT_LINES = {
  trail = 3,
  rampart = 3,
  deed = 3,
}

local function tutorials_of(force_index)
  storage.state_tutorials[force_index] = storage.state_tutorials[force_index] or {}
  return storage.state_tutorials[force_index]
end

local function dismiss_state_tutorial(entries, state)
  local entry = entries[state]
  if type(entry) == "table" then
    for _, object in pairs(entry.objects) do
      if object.valid then object.destroy() end
    end
  end
  entries[state] = true -- shown; never redrawn for this force
end

-- Any state tutorial sitting on this cell retires when the cell changes
-- state under it (upgrade, downgrade, release).
local function dismiss_tutorials_at(surface_index, cx, cy)
  for _, entries in pairs(storage.state_tutorials) do
    for state, entry in pairs(entries) do
      if type(entry) == "table" and entry.surface_index == surface_index
        and entry.cx == cx and entry.cy == cy then
        dismiss_state_tutorial(entries, state)
      end
    end
  end
end

local function maybe_state_tutorial(force, event)
  local state = event.new_state
  local line_count = STATE_HINT_LINES[state]
  if not line_count then return end
  local entries = tutorials_of(force.index)
  if entries[state] then return end
  local surface = game.surfaces[event.surface_index]
  if not (surface and surface.valid) then return end

  local cx, cy = event.cell_pos.x, event.cell_pos.y
  local x = cx * const.CELL + const.CELL / 2
  local y = cy * const.CELL + const.CELL / 2
  local lines = {
    { text = { "land-title-registry.state-hint-" .. state .. "-1" }, dy = -1.8, scale = 1.6 },
    { text = { "land-title-registry.state-hint-" .. state .. "-2" }, dy = 0.0, scale = 1.0 },
    { text = { "land-title-registry.state-hint-" .. state .. "-3" }, dy = 1.2, scale = 1.0 },
  }
  entries[state] = {
    surface_index = event.surface_index,
    cx = cx,
    cy = cy,
    objects = draw_lines(surface, force, x, y, lines),
  }
end

-- A build inside a tutorial's cell proves the lesson landed; retire it.
-- Cheap on the hot build path: one lookup for forces with no tutorials,
-- and at most three cell comparisons otherwise.
function welcome.on_entity_built(entity)
  local entries = storage.state_tutorials[entity.force.index]
  if not entries then return end
  local surface_index = entity.surface.index
  local cx = math.floor(entity.position.x / const.CELL)
  local cy = math.floor(entity.position.y / const.CELL)
  for state, entry in pairs(entries) do
    if type(entry) == "table" and entry.surface_index == surface_index
      and entry.cx == cx and entry.cy == cy then
      dismiss_state_tutorial(entries, state)
    end
  end
end

function welcome.on_cell_claimed(event)
  -- A state change under a tutorial retires it (upgrades included — the
  -- rampart tutorial may be about to draw on this very cell).
  dismiss_tutorials_at(event.surface_index, event.cell_pos.x, event.cell_pos.y)
  if not event.cost or event.cost == 0 then return end
  local force = game.forces[event.force_name]
  if not (force and force.valid) then return end
  -- First paid claim: the force has learned the gesture; retire the
  -- origin hints.
  destroy_hints(force.index)
  maybe_state_tutorial(force, event)
end

function welcome.on_cell_downgraded(event)
  dismiss_tutorials_at(event.surface_index, event.cell_pos.x, event.cell_pos.y)
end

-- Recycled team slots are new players: they get the tutorials again.
function welcome.reset_force(force_index)
  destroy_hints(force_index)
  local entries = storage.state_tutorials[force_index]
  if entries then
    for state in pairs(entries) do
      dismiss_state_tutorial(entries, state)
    end
  end
  storage.state_tutorials[force_index] = nil
end

function welcome.on_forces_merged(event)
  welcome.reset_force(event.source_index)
end

return welcome
