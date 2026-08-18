-- Layer-membership override channels (host has the final word; precedence
-- Land Title Registry defaults < mod-data declarations < these settings). Entries are
-- comma-separated: an entity prototype name, or a prototype type with the
-- "type:" prefix (e.g. "heat-pipe, type:storage-tank"). Removals send an
-- entity back to land — the universal default.
local layer_overrides = {
  { name = "ltr-transit-additions", order = "e[layers]-a" },
  { name = "ltr-transit-removals", order = "e[layers]-b" },
  { name = "ltr-rampart-additions", order = "e[layers]-c" },
  { name = "ltr-rampart-removals", order = "e[layers]-d" },
}
local override_settings = {}
for _, entry in ipairs(layer_overrides) do
  override_settings[#override_settings + 1] = {
    type = "string-setting",
    name = entry.name,
    setting_type = "startup",
    default_value = "",
    allow_blank = true,
    order = entry.order,
  }
end
data:extend(override_settings)

data:extend({
  {
    type = "string-setting",
    name = "ltr-cell-size",
    setting_type = "startup",
    default_value = "24",
    allowed_values = { "16", "24", "32" },
    order = "a[core]-a[cell-size]",
  },
})


-- Per-planet border colors (used when MTS team colors are absent). The
-- settings stage cannot enumerate planet prototypes (they are data-stage),
-- so the known base/Space Age planets get named settings and every other
-- planet falls back to ltr-color-default at runtime.
local color_settings = {
  { name = "ltr-color-default", color = { r = 0.85, g = 0.80, b = 0.62 } },
  { name = "ltr-color-nauvis", color = { r = 0.36, g = 0.68, b = 0.38 } },
}
if mods["space-age"] then
  local sa = {
    { name = "ltr-color-vulcanus", color = { r = 0.85, g = 0.48, b = 0.24 } },
    { name = "ltr-color-fulgora", color = { r = 0.68, g = 0.50, b = 0.82 } },
    { name = "ltr-color-gleba", color = { r = 0.55, g = 0.72, b = 0.25 } },
    { name = "ltr-color-aquilo", color = { r = 0.42, g = 0.67, b = 0.82 } },
  }
  for _, entry in ipairs(sa) do color_settings[#color_settings + 1] = entry end
end
local extended = {}
for i, entry in ipairs(color_settings) do
  extended[#extended + 1] = {
    type = "color-setting",
    name = entry.name,
    setting_type = "runtime-global",
    default_value = entry.color,
    order = "d[colors]-" .. string.char(96 + i),
  }
end
data:extend(extended)

data:extend({
  {
    type = "bool-setting",
    name = "ltr-show-points",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "c[ux]-b[show-points]",
  },
  {
    type = "bool-setting",
    name = "ltr-show-celebrations",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "c[ux]-c[show-celebrations]",
  },
  {
    type = "int-setting",
    name = "ltr-points-per-level",
    setting_type = "startup",
    default_value = 5,
    minimum_value = 0,
    order = "b[tech]-a[points-per-level]",
  },
  {
    type = "double-setting",
    name = "ltr-tech-cost-multiplier",
    setting_type = "startup",
    default_value = 1,
    minimum_value = 0.1,
    order = "b[tech]-b[cost-multiplier]",
  },
  {
    type = "string-setting",
    name = "ltr-tech-tiers",
    setting_type = "startup",
    default_value = "",
    allow_blank = true,
    order = "b[tech]-c[tiers-override]",
  },
  {
    type = "int-setting",
    name = "ltr-settlement-charter",
    setting_type = "runtime-global",
    default_value = 30,
    minimum_value = 0,
    order = "a[economy]-c[settlement-charter]",
  },
  {
    -- On by default (playtest call, reversing 0.1.6): the line goes only
    -- to the acting TEAM's chat and is the audit trail for who bought or
    -- sold which land — accountability beat quietness once teammates
    -- shared a purse. Hosts who want silence still have the switch.
    type = "bool-setting",
    name = "ltr-print-claims",
    setting_type = "runtime-global",
    default_value = true,
    order = "c[ux]-a[print-claims]",
  },
  {
    -- A busy server's map fills with per-cell standings; hiding the
    -- uncontested ones keeps only the cells anyone is actually racing.
    type = "bool-setting",
    name = "ltr-chronicle-contested-only",
    setting_type = "runtime-per-user",
    default_value = false,
    order = "c[ux]-e[chronicle-contested-only]",
  },
  {
    -- Accidental right-drags refund only a fraction of the invested
    -- points; the dialog makes the loss explicit before it happens.
    type = "bool-setting",
    name = "ltr-confirm-lowering",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "c[ux]-d[confirm-lowering]",
  },
  {
    type = "int-setting",
    name = "ltr-starting-points",
    setting_type = "runtime-global",
    default_value = 75,
    minimum_value = 0,
    order = "a[economy]-a[starting-points]",
  },
  {
    type = "int-setting",
    name = "ltr-refund-percent",
    setting_type = "runtime-global",
    default_value = 25,
    minimum_value = 0,
    maximum_value = 100,
    order = "a[economy]-b[refund-percent]",
  },
})

-- Per-player border style (playtest call): each player draws their own
-- force's frontier lines in their own width and per-state colors, alpha
-- included. Lines are rendered per player (scripts/render.lua); the survey
-- stakes keep the team/planet identity color and are NOT per-player.
local BORDER_COLOR_DEFAULTS = {
  -- scripts/state_colors.lua values at full alpha; render.lua applies its
  -- world/chart alpha ramp on top, scaled by each color's alpha channel.
  { state = "trail", color = { r = 222 / 255, g = 126 / 255, b = 38 / 255, a = 1 } },
  { state = "rampart", color = { r = 224 / 255, g = 186 / 255, b = 48 / 255, a = 1 } },
  { state = "deed", color = { r = 90 / 255, g = 170 / 255, b = 82 / 255, a = 1 } },
}
local border_settings = {
  {
    type = "int-setting",
    name = "ltr-border-width",
    setting_type = "runtime-per-user",
    default_value = 1,
    minimum_value = 1,
    maximum_value = 6,
    order = "f[borders]-a[width]",
  },
}
for i, entry in ipairs(BORDER_COLOR_DEFAULTS) do
  border_settings[#border_settings + 1] = {
    type = "color-setting",
    name = "ltr-border-color-" .. entry.state,
    setting_type = "runtime-per-user",
    default_value = entry.color,
    order = "f[borders]-" .. string.char(97 + i), -- b, c, d
  }
end
data:extend(border_settings)

-- Per-player gesture mapping (playtest call): the engine's five selection
-- gestures are fixed key combinations, but WHAT each one does is a
-- per-player dropdown. Border colors follow the gesture (startup prototype
-- data), so a remapped gesture keeps its original color.
local GESTURE_ACTIONS = { "raise-one", "jump-deed", "jump-rampart", "lower-one", "release-all" }
local gesture_settings = {
  { name = "ltr-gesture-drag", default = "raise-one", order = "a" },
  { name = "ltr-gesture-shift-drag", default = "jump-deed", order = "b" },
  { name = "ltr-gesture-ctrl-shift-drag", default = "jump-rampart", order = "c" },
  { name = "ltr-gesture-right-drag", default = "lower-one", order = "d" },
  { name = "ltr-gesture-shift-right-drag", default = "release-all", order = "e" },
}
local extended_gestures = {}
for _, entry in ipairs(gesture_settings) do
  extended_gestures[#extended_gestures + 1] = {
    type = "string-setting",
    name = entry.name,
    setting_type = "runtime-per-user",
    default_value = entry.default,
    allowed_values = GESTURE_ACTIONS,
    order = "g[gestures]-" .. entry.order,
  }
end
data:extend(extended_gestures)
