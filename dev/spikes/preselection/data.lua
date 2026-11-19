-- The tool under test: pre-selection events on, tiles on the left button,
-- entities on the right, draw_selection_counts on in the plain modes and off
-- in the alt (Shift) modes.
local function mode(entity_or_tile, counts)
  return { mode = entity_or_tile, border_color = { 1, 0.5, 0 }, cursor_box_type = "copy", draw_selection_counts = counts }
end

data:extend {
  {
    type = "selection-tool",
    name = "sel-probe",
    icon = "__base__/graphics/icons/blueprint.png",
    icon_size = 64,
    flags = { "only-in-cursor", "spawnable" },
    stack_size = 1,
    subgroup = "tool",
    order = "z",
    send_pre_selection_events = true,
    select = mode({ "any-tile" }, true),
    alt_select = mode({ "any-tile" }, false),
    reverse_select = mode({ "any-entity" }, true),
    alt_reverse_select = mode({ "any-entity" }, false),
  },
}
