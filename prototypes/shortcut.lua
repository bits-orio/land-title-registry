-- Two entry points for the survey tool, both using the engine's spawn-item
-- action so the tool appears directly in the cursor and never needs a recipe.

data:extend({
  {
    type = "shortcut",
    name = "ltr-get-survey-tool",
    action = "spawn-item",
    item_to_spawn = "ltr-survey-tool",
    associated_control_input = "ltr-get-survey-tool",
    icon = "__land-title-registry__/graphics/survey-tool.png",
    icon_size = 64,
    small_icon = "__land-title-registry__/graphics/survey-tool.png",
    small_icon_size = 64,
    order = "f[land-title-registry]-a[survey]",
  },
  {
    type = "custom-input",
    name = "ltr-get-survey-tool",
    key_sequence = "ALT + S",
    action = "spawn-item",
    item_to_spawn = "ltr-survey-tool",
    consuming = "none",
  },
  {
    -- Map-view chronicle toggle. The vanilla map-layer list
    -- (MapViewSettings) is a fixed set of engine layers with no extension
    -- point for mods, so the equivalent ships as our own toggle: a
    -- shortcut-bar button plus the rebindable input below.
    type = "shortcut",
    name = "ltr-toggle-chronicle",
    action = "lua",
    toggleable = true,
    associated_control_input = "ltr-toggle-chronicle",
    icon = "__land-title-registry__/graphics/survey-stake.png",
    icon_size = 64,
    small_icon = "__land-title-registry__/graphics/survey-stake.png",
    small_icon_size = 64,
    order = "f[land-title-registry]-b[chronicle]",
  },
  {
    type = "custom-input",
    name = "ltr-toggle-chronicle",
    key_sequence = "ALT + C",
    consuming = "none",
  },
  {
    -- The Rampart survey tool's only entry point. W is free in the ALT
    -- row vanilla occupies (A/B/C/D/E/F/G/L/R/T/U/Y); rebindable like
    -- every custom input.
    type = "custom-input",
    name = "ltr-get-rampart-tool",
    key_sequence = "ALT + W",
    action = "spawn-item",
    item_to_spawn = "ltr-survey-tool-rampart",
    consuming = "none",
  },
})
