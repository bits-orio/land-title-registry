-- Live cost or refund while the survey tool is still being dragged
-- (ADR-0015). The preselection events (Factorio 2.1.22) fire as the cursor
-- moves with the button held; each one runs the real batch evaluation as a
-- dry run and shows the outcome in one text label next to the cursor.
--
-- This module only ever READS claims. The preselection events are best
-- effort (the engine may drop or reorder them), so the final selection
-- events in scripts/tool.lua stay the only place a claim changes, and
-- every handler here is safe to run twice or not at all.

local economy = require("scripts.economy")
local claims = require("scripts.claims")
local gestures = require("scripts.gestures")
local outposts = require("scripts.outposts")

local drag_preview = {}

-- The dry run is re-run only when the drag crosses into another cell, and
-- only for rectangles up to this many cells; a bigger drag shows its size
-- alone. Measured costs are in ADR-0015.
local MAX_CELLS = 256

local COLOR_COST = { r = 1, g = 1, b = 1 }
local COLOR_REFUND = { r = 0.6, g = 1, b = 0.6 }
local COLOR_DENIED = { r = 1, g = 0.6, b = 0.6 }

-- Screen distance of the label from the cursor, in pixels at any zoom. The
-- tool icon and its balance label hang below the cursor, hence the bigger
-- gap on that side.
local GAP_PX = 14
local GAP_BELOW_PX = 54
local PIXELS_PER_TILE = 32

-- A render object is drawn either in the world or on the map, never in
-- both (its render_mode). The label is therefore one text object per mode
-- with the same content, so the drag reads the same in either view and
-- through a change of view mid-drag. The map is where the big drags are.
local RENDER_MODES = { "game", "chart" }

-- player_index -> {key = string, objects = {LuaRenderObject, ...}?}. `key`
-- names the last evaluated (surface, cell rectangle, action); `objects`
-- (one per RENDER_MODES entry) is absent when that evaluation had nothing
-- to show.
local function previews()
  storage.drag_preview = storage.drag_preview or {}
  return storage.drag_preview
end

local function destroy_label(preview)
  for _, object in pairs(preview.objects or {}) do
    if object.valid then object.destroy() end
  end
  preview.objects = nil
end

-- The label's objects when all of them can still be updated in place.
local function live_objects(preview, surface)
  local objects = preview.objects
  if not objects then return nil end
  for _, object in pairs(objects) do
    if not object.valid then return nil end
    if surface and object.surface.index ~= surface.index then return nil end
  end
  return objects
end

local function cell_count(rect)
  return (rect.x2 - rect.x1 + 1) * (rect.y2 - rect.y1 + 1)
end

-- An anchor-denied Deed jump on one Wilderness cell may be an outpost
-- founding (ADR-0014), which the final event offers through its own
-- dialog; the preview stays silent instead of calling it a denial.
local function may_be_outpost(player, rect, action)
  return action == "deed" and cell_count(rect) == 1 and outposts.cap(player.force) > 0
end

-- What the drag would do right now: a localised text and its colour, or
-- nil when there is nothing to say.
local function describe(player, surface, rect, action)
  local cells = cell_count(rect)
  if cells > MAX_CELLS then
    return { "land-title-registry.drag-too-large", cells }, COLOR_COST
  end
  local result = claims.apply_batch(surface, player.force, player, rect, action, { dry_run = true })
  if result.denied == "points" then
    return { "land-title-registry.drag-short", result.cells, economy.format(result.need),
      economy.format(result.need - result.have) }, COLOR_DENIED
  end
  if result.denied == "anchor" then
    if may_be_outpost(player, rect, action) then return nil end
    return { "land-title-registry.no-adjacency" }, COLOR_DENIED
  end
  if result.denied or result.applied == 0 then return nil end
  if gestures.LOWERING[action] then
    return { "land-title-registry.drag-refund", result.applied, economy.format(result.refund) },
      COLOR_REFUND
  end
  return { "land-title-registry.drag-cost", result.applied, economy.format(result.cost) }, COLOR_COST
end

-- Where the label goes: beside the cursor, on the side that faces the drag
-- origin. That side is the selected box, which is on screen, so the text
-- never runs off the screen edge the cursor is heading for. event.position
-- is read every time: the origin can move mid-drag.
local function placement(player, event)
  local cursor, origin = event.cursor_position, event.position
  local tiles_per_pixel = 1 / (PIXELS_PER_TILE * player.zoom)
  local box_is_left = cursor.x >= origin.x
  local box_is_above = cursor.y >= origin.y
  return {
    target = {
      x = cursor.x + (box_is_left and -GAP_PX or GAP_PX) * tiles_per_pixel,
      y = cursor.y + (box_is_above and -GAP_PX or GAP_BELOW_PX) * tiles_per_pixel,
    },
    alignment = box_is_left and "right" or "left",
    vertical_alignment = box_is_above and "bottom" or "top",
  }
end

local function place_label(object, place)
  object.target = place.target
  object.alignment = place.alignment
  object.vertical_alignment = place.vertical_alignment
end

-- One label per player, updated in place: a drag sends an event on every
-- cursor movement, so creating objects per event would pile them up.
local function show_label(preview, player, surface, place, text, color)
  local objects = live_objects(preview, surface)
  if objects then
    for _, object in pairs(objects) do
      object.text = text
      object.color = color
      place_label(object, place)
    end
    return
  end
  destroy_label(preview)
  preview.objects = {}
  for index, render_mode in ipairs(RENDER_MODES) do
    preview.objects[index] = rendering.draw_text({
      text = text,
      surface = surface,
      target = place.target,
      color = color,
      players = { player },
      scale = 1.25,
      scale_with_zoom = true,
      alignment = place.alignment,
      vertical_alignment = place.vertical_alignment,
      render_mode = render_mode,
    })
  end
end

local function evaluate(preview, player, event, rect, action)
  local text, color = describe(player, event.surface, rect, action)
  if not text then
    destroy_label(preview)
    return
  end
  show_label(preview, player, event.surface, placement(player, event), text, color)
end

local function preview_key(surface, rect, action)
  return string.format("%d:%d:%d:%d:%d:%s", surface.index, rect.x1, rect.y1, rect.x2, rect.y2, action)
end

-- on_player_start_selected_area and on_player_change_selected_area. The
-- drag origin can move mid-drag without a new start event (a right-click
-- during a left drag), so nothing is remembered from the start: every
-- event is evaluated from its own area and selection_mode.
function drag_preview.on_changed(event)
  if not gestures.is_tool(event.item) then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local surface = event.surface
  if not (surface and surface.valid) then return end
  local action = gestures.action_for(player, event.item, gestures.setting_of_mode(event.selection_mode))
  if not action then return drag_preview.clear(event.player_index) end

  local all = previews()
  local preview = all[event.player_index] or {}
  all[event.player_index] = preview
  local rect = gestures.rect_from_area(event.area)
  local key = preview_key(surface, rect, action)
  if preview.key == key then
    -- Same cells, same action: the numbers stand, the label follows.
    local objects = live_objects(preview)
    if objects then
      local place = placement(player, event)
      for _, object in pairs(objects) do place_label(object, place) end
    end
    return
  end
  preview.key = key
  evaluate(preview, player, event, rect, action)
end

-- True while a drag preview is up for this player: the hover feedback
-- (scripts/tool.lua) stands down, the change events speak for the drag.
function drag_preview.active(player_index)
  return storage.drag_preview ~= nil and storage.drag_preview[player_index] ~= nil
end

-- Called on cancel, on every final selection event, when the tool leaves
-- the cursor, on a surface change and when the player goes. Any one of
-- them can be the only one that arrives.
function drag_preview.clear(player_index)
  local all = storage.drag_preview
  local preview = all and all[player_index]
  if not preview then return end
  destroy_label(preview)
  all[player_index] = nil
end

-- A mod update ends every preview: no drag outlives one, and 0.2.1 kept its
-- label in a single `object` field that this code would never find again.
function drag_preview.reset()
  for _, preview in pairs(storage.drag_preview or {}) do
    if preview.object and preview.object.valid then preview.object.destroy() end
    destroy_label(preview)
  end
  storage.drag_preview = nil
end

function drag_preview.on_cancelled(event)
  drag_preview.clear(event.player_index)
end

return drag_preview
