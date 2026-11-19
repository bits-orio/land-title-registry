-- Probe for dev/run-drag.sh: a real mouse drag of the survey tool, on a
-- headless server plus one graphical client. Every peer runs this file and
-- logs the same LTR_MP lines at the same ticks, so the two logs can be
-- compared line by line, and the client's log times say when its screen
-- could first show each change.
--
--   LTR_MP EV    one line per preselection or final selection event
--   LTR_MP STATE the purse and the live preview labels, when they change
--   LTR_MP MARK  the driver pressed the mark key (the player is idle)
--   LTR_MP FAIL  a broken rule: a label left behind, a label other players
--                could see, a label the view the player is in does not
--                draw, a price that differs from what was charged
--
-- It only reads the mod under test, through its remote interface, the
-- render objects it draws and its "Lower land?" dialog. The two writes it
-- makes are setup: the purse and the tool in the cursor.

local LTR = "land-title-registry"
local TOOL = "ltr-survey-tool"
local LOWER_FRAME = "ltr_lower_confirm_frame"
local START_POINTS = 100
local START_ZOOM = 0.3

local E = defines.events
local MODE_NAME = {}
for name, value in pairs(defines.selection_mode) do MODE_NAME[value] = name end

local function say(text) log("LTR_MP " .. text) end

local function fail(name, why)
  storage.failures = storage.failures + 1
  say("FAIL " .. name .. ": " .. why)
end

local function points(player)
  return remote.call(LTR, "get_points", player.force.index)
end

local function cell_size() return remote.call(LTR, "get_cell_size") end

-- "chart" on the map, "game" in the world (the map zoomed in far enough to
-- show the world counts as the world): the two modes a render object can
-- be drawn in.
local function view_of(player)
  return player.render_mode == defines.render_mode.chart and "chart" or "game"
end

-- Screen pixel of a map position, for matching an event to the mouse step
-- that caused it. The view is centred on the player.
local function pixel(player, position)
  local scale = 32 * player.zoom
  local resolution = player.display_resolution
  return math.floor((position.x - player.position.x) * scale + resolution.width / 2 + 0.5),
    math.floor((position.y - player.position.y) * scale + resolution.height / 2 + 0.5)
end

local function rect_text(area)
  local cell = cell_size()
  return string.format("%d,%d,%d,%d", math.floor(area.left_top.x / cell), math.floor(area.left_top.y / cell),
    math.floor(area.right_bottom.x / cell), math.floor(area.right_bottom.y / cell))
end

-- Render object ids count up across all mods, so a throwaway object reads
-- the counter.
local function next_render_id()
  local dummy = rendering.draw_line({ color = { 0, 0, 0, 0 }, width = 1, from = { 0, 0 }, to = { 0, 0 },
    surface = game.surfaces[1], visible = false })
  local id = dummy.id
  dummy.destroy()
  return id
end

-- Runs at the end of every event this mod sees, and it subscribes to all
-- of them. This mod loads after the one under test, so whatever was drawn
-- between this reading and a preselection event's handler below was drawn
-- by the mod under test while it handled that same event.
local function sync() storage.render_id = next_render_id() end

local function only_player(object, player)
  local players = object.players
  local forces = object.forces
  return players ~= nil and #players == 1 and players[1].index == player.index
    and (forces == nil or #forces == 0)
end

local function label_text(object)
  local text = object.text
  if type(text) ~= "table" then return tostring(text) end
  local parts = {}
  for i = 1, #text do parts[i] = tostring(text[i]) end
  return table.concat(parts, "|")
end

-- What the mod under test drew while handling this event. Each object has
-- to be for the dragging player alone; the texts among them are the
-- preview label and stay tracked until they are destroyed.
local function note_drawn(player, event_name)
  for id = storage.render_id, next_render_id() - 1 do
    local object = rendering.get_object_by_id(id)
    if object and object.valid then
      if not only_player(object, player) then
        fail("visible-to-others", string.format("%s object #%d drawn during %s is not restricted to player %d",
          object.type, id, event_name, player.index))
      end
      if object.type == "text" then storage.labels[id] = true end
    end
  end
end

-- The live labels, in id order.
local function labels()
  local ids = {}
  for id in pairs(storage.labels) do
    local object = rendering.get_object_by_id(id)
    if object and object.valid then
      ids[#ids + 1] = id
    else
      storage.labels[id] = nil
    end
  end
  table.sort(ids)
  local objects = {}
  for i, id in ipairs(ids) do objects[i] = rendering.get_object_by_id(id) end
  return objects
end

local function labels_text()
  local parts = {}
  for i, object in ipairs(labels()) do
    parts[i] = "#" .. object.id .. "/" .. object.render_mode .. "[" .. label_text(object) .. "]"
  end
  return parts
end

-- The label the player's current view draws, if any, and whether a label
-- exists that this view does not draw.
local function label_in_view(player)
  local view, hidden = view_of(player), false
  for _, object in ipairs(labels()) do
    if not only_player(object, player) then
      fail("visible-to-others", "label #" .. object.id .. " is no longer restricted to player " .. player.index)
    end
    if object.render_mode == view then return object, false end
    hidden = true
  end
  return nil, hidden
end

local function on_preselection(name, event)
  local player = game.get_player(event.player_index)
  if event.item ~= TOOL then return sync() end
  local drag = storage.drags[player.index]
  if name == "start" or not drag then
    if name ~= "start" then say("ORDER t=" .. event.tick .. " change without a start") end
    drag = {}
    storage.drags[player.index] = drag
  end
  note_drawn(player, name)
  local label, hidden = label_in_view(player)
  local view = view_of(player)
  if hidden and not drag.hidden_reported then
    drag.hidden_reported = true
    fail("label-not-drawn-in-" .. view .. "-view", "the preview exists but this view does not draw it")
  end
  local x, y = pixel(player, event.cursor_position)
  local ox, oy = pixel(player, event.position)
  drag.rect = rect_text(event.area)
  drag.mode = event.selection_mode
  drag.points = points(player)
  drag.text = label and label.text or nil
  local shown = hidden and "hidden" or "none"
  if label then
    local lx, ly = pixel(player, label.target.position)
    shown = string.format("#%d[%s]@%d,%d/%s/%s", label.id, label_text(label), lx, ly, label.alignment,
      label.vertical_alignment)
  end
  say(string.format("EV t=%d ev=%s mode=%s view=%s px=%d,%d origin=%d,%d rect=%s label=%s", event.tick, name,
    MODE_NAME[event.selection_mode] or "?", view, x, y, ox, oy, drag.rect, shown))
  sync()
end

-- The amount a label promises: negative for a cost, positive for a refund,
-- zero for a refusal or no label, nil when it names no price.
local function promised(text)
  if not text then return 0 end
  local key = text[1]
  if key == "land-title-registry.drag-cost" then return -tonumber(text[3]) end
  if key == "land-title-registry.drag-refund" then return tonumber(text[3]) end
  if key == "land-title-registry.drag-short" or key == "land-title-registry.no-adjacency" then return 0 end
  return nil
end

local function on_drag_end(name, event)
  local player = game.get_player(event.player_index)
  if event.item ~= TOOL then return sync() end
  local drag = storage.drags[player.index]
  storage.drags[player.index] = nil
  local left = labels_text()
  if #left > 0 then fail("label-after-" .. name, table.concat(left, " ")) end
  if name == "cancel" then
    say(string.format("EV t=%d ev=cancel labels=%d", event.tick, #left))
    return sync()
  end
  if not drag then
    say(string.format("EV t=%d ev=%s rect=%s without a preview", event.tick, name, rect_text(event.area)))
    return sync()
  end
  local x, y = pixel(player, event.cursor_position)
  local rect = rect_text(event.area)
  local promise = promised(drag.text)
  local same_drag = rect == drag.rect and event.selection_mode == drag.mode
  -- A lowering drag asks first: the dialog quotes the refund now and the
  -- purse changes when its button is clicked (see on_tick).
  local dialog = player.gui.screen[LOWER_FRAME]
  local delta = points(player) - drag.points
  local what = "charged"
  if dialog then
    delta = tonumber(dialog.l1.caption[3])
    what = "dialog-quotes"
    storage.asked[player.index] = { points = drag.points, quoted = delta }
  end
  local verdict
  if not same_drag then
    verdict = "preview-was-for-another-rectangle"
  elseif promise == nil then
    verdict = "no-price-shown"
  elseif math.abs(promise - delta) < 0.006 then
    verdict = "match"
  else
    verdict = "MISMATCH"
    fail("price", string.format("the label promised %s, %s %s (rect %s)", promise, what, delta, rect))
  end
  say(string.format("EV t=%d ev=%s mode=%s px=%d,%d rect=%s previewed=%s promised=%s %s=%s verdict=%s",
    event.tick, name, MODE_NAME[event.selection_mode] or "?", x, y, rect, drag.rect, tostring(promise), what,
    tostring(delta), verdict))
  sync()
end

-- The "Lower land?" dialog has gone: what did the purse get?
local function dialog_closed(player, asked, tick)
  local delta = points(player) - asked.points
  local verdict = "match"
  if delta == 0 then
    verdict = "kept"
  elseif math.abs(delta - asked.quoted) >= 0.006 then
    verdict = "MISMATCH"
    fail("refund", string.format("the dialog quoted %s, the purse changed by %s", asked.quoted, delta))
  end
  say(string.format("EV t=%d ev=dialog-closed quoted=%s charged=%s verdict=%s", tick, tostring(asked.quoted),
    tostring(delta), verdict))
end

local function give_tool(player)
  local stack = player.cursor_stack
  if stack and not (stack.valid_for_read and stack.name == TOOL) then stack.set_stack(TOOL) end
end

local function on_tick(event)
  if event.tick % 30 == 0 then
    for _, player in pairs(game.connected_players) do
      local welcome = player.gui.screen.ltr_welcome
      if welcome then welcome.destroy() end
    end
  end
  for player_index, asked in pairs(storage.asked) do
    local asker = game.get_player(player_index)
    if not asker.gui.screen[LOWER_FRAME] then
      storage.asked[player_index] = nil
      dialog_closed(asker, asked, event.tick)
    end
  end
  local player = game.connected_players[1]
  if player then
    local state = string.format("points=%s labels=%s", tostring(points(player)), table.concat(labels_text(), " "))
    if state ~= storage.state then
      storage.state = state
      say("STATE t=" .. event.tick .. " " .. state)
    end
  end
  sync()
end

local function on_joined(event)
  local player = game.get_player(event.player_index)
  remote.call(LTR, "set_points", player.force.index, START_POINTS)
  player.zoom = START_ZOOM
  give_tool(player)
  say(string.format("JOIN t=%d player=%d zoom=%.3f cell=%d", event.tick, player.index, player.zoom, cell_size()))
  sync()
end

-- The mark key: the driver presses it between drags, when nothing is held.
-- A label still up here was left behind by the drag before.
local function on_mark(event)
  local player = game.get_player(event.player_index)
  storage.marks = storage.marks + 1
  local left = labels_text()
  if #left > 0 then fail("label-at-mark-" .. storage.marks, table.concat(left, " ")) end
  give_tool(player)
  say(string.format("MARK %d t=%d points=%s labels=%d view=%s zoom=%.3f failures=%d", storage.marks, event.tick,
    tostring(points(player)), #left, view_of(player), player.zoom, storage.failures))
  sync()
end

script.on_init(function()
  local freeplay = remote.interfaces.freeplay
  if freeplay and freeplay.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  if freeplay and freeplay.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
  game.surfaces[1].always_day = true
  storage.failures = 0
  storage.marks = 0
  storage.drags = {}
  storage.asked = {}
  storage.labels = {}
  storage.render_id = 0
  storage.state = ""
end)

-- Every event first (see sync), then the ones this probe reads.
for _, id in pairs(E) do script.on_event(id, sync) end
script.on_nth_tick(1, sync)
script.on_event(E.on_tick, on_tick)
script.on_event(E.on_player_joined_game, on_joined)
script.on_event("ltr-drag-probe-mark", on_mark)
script.on_event(E.on_player_start_selected_area, function(event) on_preselection("start", event) end)
script.on_event(E.on_player_change_selected_area, function(event) on_preselection("change", event) end)
script.on_event(E.on_player_cancel_selected_area, function(event) on_drag_end("cancel", event) end)
for _, name in pairs({ "selected", "alt_selected", "reverse_selected", "alt_reverse_selected",
  "super_forced_selected" }) do
  script.on_event(E["on_player_" .. name .. "_area"], function(event) on_drag_end(name, event) end)
end
