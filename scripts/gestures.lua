-- The survey tool's gesture grammar: which action a gesture performs for a
-- given player and tool, and which cells a dragged area covers. Shared by
-- the final selection handlers (scripts/tool.lua) and the live drag preview
-- (scripts/drag_preview.lua), so both always agree on what a drag will do.
--
-- Right is the exact mirror of left (ADR-0013). Drag raises one rung,
-- right-drag lowers one; Shift jumps to the top (Deed), Shift-right jumps
-- to the bottom (sell everything back to Wilderness); Ctrl+Shift is the
-- middle jump (Rampart). Each gesture's ACTION is per-player remappable
-- through the ltr-gesture-* settings; the claims-side vocabulary is the
-- setting value translated here.

local const = require("scripts.const")

local gestures = {}

gestures.TOOL_NAME = "ltr-survey-tool"
gestures.RAMPART_TOOL_NAME = "ltr-survey-tool-rampart"

-- Actions that take rights away (they refund, and confirm before applying).
gestures.LOWERING = { downgrade = true, release = true }

local ACTION_OF = {
  ["raise-one"] = "advance",
  ["jump-deed"] = "deed",
  ["jump-rampart"] = "rampart",
  ["lower-one"] = "downgrade",
  ["release-all"] = "release",
}

-- The Rampart variant tool is fixed-function (its whole point is a
-- dependable Rampart jump on plain drag); the other gestures mirror the
-- main tool's defaults so muscle memory transfers.
local RAMPART_TOOL_ACTION = {
  ["ltr-gesture-drag"] = "rampart",
  ["ltr-gesture-shift-drag"] = "deed",
  ["ltr-gesture-ctrl-shift-drag"] = "rampart",
  ["ltr-gesture-right-drag"] = "downgrade",
  ["ltr-gesture-shift-right-drag"] = "release",
}

-- The preselection events carry the gesture as event.selection_mode; the
-- final events are one event per gesture instead. Keyed by the define's
-- value, built from its names so a missing name (an older engine) is
-- simply absent.
local SETTING_OF_MODE = {}
for name, setting in pairs({
  select = "ltr-gesture-drag",
  alt_select = "ltr-gesture-shift-drag",
  super_forced_select = "ltr-gesture-ctrl-shift-drag",
  reverse_select = "ltr-gesture-right-drag",
  alt_reverse_select = "ltr-gesture-shift-right-drag",
}) do
  local mode = defines.selection_mode and defines.selection_mode[name]
  if mode then SETTING_OF_MODE[mode] = setting end
end

function gestures.is_tool(item_name)
  return item_name == gestures.TOOL_NAME or item_name == gestures.RAMPART_TOOL_NAME
end

function gestures.setting_of_mode(selection_mode)
  return SETTING_OF_MODE[selection_mode]
end

-- The claims action a gesture performs, or nil when the item is not a
-- survey tool (or the gesture is unknown).
function gestures.action_for(player, item_name, gesture_setting)
  if not gesture_setting then return nil end
  if item_name == gestures.TOOL_NAME then
    return ACTION_OF[player.mod_settings[gesture_setting].value] or "advance"
  end
  if item_name == gestures.RAMPART_TOOL_NAME then
    return RAMPART_TOOL_ACTION[gesture_setting]
  end
  return nil
end

-- Inclusive cell rectangle covered by a dragged area.
function gestures.rect_from_area(area)
  return {
    x1 = math.floor(area.left_top.x / const.CELL),
    y1 = math.floor(area.left_top.y / const.CELL),
    x2 = math.floor(area.right_bottom.x / const.CELL),
    y2 = math.floor(area.right_bottom.y / const.CELL),
  }
end

return gestures
