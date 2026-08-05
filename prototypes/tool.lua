-- The survey tool: the single item through which all claiming, upgrading,
-- and downgrading happens. Only-in-cursor, never craftable; acquired via the
-- shortcut button or the ALT+S custom input (both engine-side spawn-item).
--
-- The four selection modes map one-to-one onto the four actions; handlers
-- derive the affected cells from event.area, so the entity filters below are
-- a perf nicety (keep the entities array to blockers), not load-bearing.

local BLOCKER_NAMES = { "fh-cell-wilderness", "fh-cell-trail", "fh-cell-rampart" }

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
    name = "fh-survey-tool",
    icon = "__base__/graphics/icons/landfill.png",
    icon_size = 64,
    stack_size = 1,
    flags = { "not-stackable", "only-in-cursor", "spawnable" },
    draw_label_for_cursor_render = true,
    subgroup = "tool",
    order = "z[freehold]-a[survey-tool]",
    -- select: claim Trail (green)
    select = mode({ r = 0.35, g = 0.65, b = 0.32 }, "entity"),
    -- alt-select: claim/upgrade to Deed (gold)
    alt_select = mode({ r = 0.90, g = 0.75, b = 0.31 }, "entity"),
    -- reverse-select: downgrade one step (red)
    reverse_select = mode({ r = 0.80, g = 0.26, b = 0.26 }, "not-allowed"),
    -- alt-reverse-select: claim/upgrade to Rampart (steel blue)
    alt_reverse_select = mode({ r = 0.47, g = 0.47, b = 0.71 }, "entity"),
  },
})
