-- Two entry points for the survey tool, both using the engine's spawn-item
-- action so the tool appears directly in the cursor and never needs a recipe.

data:extend({
  {
    type = "shortcut",
    name = "fh-get-survey-tool",
    action = "spawn-item",
    item_to_spawn = "fh-survey-tool",
    associated_control_input = "fh-get-survey-tool",
    icon = "__freehold__/graphics/survey-tool.png",
    icon_size = 64,
    small_icon = "__freehold__/graphics/survey-tool.png",
    small_icon_size = 64,
    order = "f[freehold]-a[survey]",
  },
  {
    type = "custom-input",
    name = "fh-get-survey-tool",
    key_sequence = "ALT + S",
    action = "spawn-item",
    item_to_spawn = "fh-survey-tool",
    consuming = "none",
  },
})
