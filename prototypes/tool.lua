-- The survey tool: the single item through which all claiming, upgrading,
-- and downgrading happens. Only-in-cursor, never craftable; acquired via the
-- shortcut button or the ALT+S custom input (both engine-side spawn-item).
--
-- The five selection modes map onto the five actions (each gesture's action
-- is per-player remappable — scripts/tool.lua); handlers derive the affected
-- cells from event.area, so the entity filters below are a perf nicety
-- (keep the entities array to blockers), not load-bearing.
--
-- Border color grammar (playtest call): every raising gesture is a GREEN —
-- toward ownership reads as good — and every lowering gesture is a RED.
-- Within a family, stronger jumps get stronger shades. The colors follow
-- the GESTURE, not the remapped action: they are startup prototype data.

local BLOCKER_NAMES = { "ltr-cell-wilderness", "ltr-cell-trail", "ltr-cell-rampart" }

local function mode(border_color, cursor_box_type)
  return {
    border_color = border_color,
    cursor_box_type = cursor_box_type,
    mode = { "any-entity" },
    entity_filters = BLOCKER_NAMES,
  }
end

data:extend({
  {
    type = "selection-tool",
    name = "ltr-survey-tool",
    icon = "__land-title-registry__/graphics/survey-tool.png",
    icon_size = 64,
    stack_size = 1,
    flags = { "not-stackable", "only-in-cursor", "spawnable" },
    draw_label_for_cursor_render = true,
    subgroup = "tool",
    order = "z[land-title-registry]-a[survey-tool]",
    -- drag: raise one rung (green)
    select = mode({ r = 0.35, g = 0.65, b = 0.32 }, "entity"),
    -- shift-drag: jump to Deed (bright green — the strongest raise)
    alt_select = mode({ r = 0.45, g = 0.85, b = 0.40 }, "entity"),
    -- ctrl+shift-drag: jump to Rampart (teal green — the middle raise).
    -- Super-forced selection is a 2.1 engine feature; 2.0 ignores the
    -- property (verified against 2.0.77) and the Rampart-jump gesture
    -- there is the variant tool below.
    super_forced_select = mode({ r = 0.24, g = 0.72, b = 0.56 }, "entity"),
    -- right-drag: lower one rung (red)
    reverse_select = mode({ r = 0.80, g = 0.26, b = 0.26 }, "not-allowed"),
    -- shift-right-drag: sell everything back to Wilderness (dark red)
    alt_reverse_select = mode({ r = 0.55, g = 0.13, b = 0.13 }, "not-allowed"),
  },
  {
    -- The Rampart survey tool: the 2.0-reachable "jump straight to
    -- Rampart" shortcut (playtest ask). Same item family, fixed gestures:
    -- drag jumps to Rampart; the other three mirror the main defaults, so
    -- muscle memory transfers. Reachable only via its rebindable custom
    -- input — no second shortcut-bar button.
    type = "selection-tool",
    name = "ltr-survey-tool-rampart",
    icon = "__land-title-registry__/graphics/survey-tool.png",
    icon_size = 64,
    stack_size = 1,
    flags = { "not-stackable", "only-in-cursor", "spawnable" },
    draw_label_for_cursor_render = true,
    subgroup = "tool",
    order = "z[land-title-registry]-b[survey-tool-rampart]",
    -- drag: jump to Rampart (teal green — same shade as the 2.1 gesture)
    select = mode({ r = 0.24, g = 0.72, b = 0.56 }, "entity"),
    -- shift-drag: jump to Deed (bright green)
    alt_select = mode({ r = 0.45, g = 0.85, b = 0.40 }, "entity"),
    -- right-drag: lower one rung (red)
    reverse_select = mode({ r = 0.80, g = 0.26, b = 0.26 }, "not-allowed"),
    -- shift-right-drag: sell everything back to Wilderness (dark red)
    alt_reverse_select = mode({ r = 0.55, g = 0.13, b = 0.13 }, "not-allowed"),
  },
})
