-- Layer-membership override channels (host has the final word; precedence
-- Freehold defaults < mod-data declarations < these settings). Entries are
-- comma-separated: an entity prototype name, or a prototype type with the
-- "type:" prefix (e.g. "heat-pipe, type:storage-tank"). Removals send an
-- entity back to land — the universal default.
local layer_overrides = {
  { name = "fh-transit-additions", order = "e[layers]-a" },
  { name = "fh-transit-removals", order = "e[layers]-b" },
  { name = "fh-rampart-additions", order = "e[layers]-c" },
  { name = "fh-rampart-removals", order = "e[layers]-d" },
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
    name = "fh-cell-size",
    setting_type = "startup",
    default_value = "24",
    allowed_values = { "16", "24", "32" },
    order = "a[core]-a[cell-size]",
  },
})


-- Per-planet border colors (used when MTS team colors are absent). The
-- settings stage cannot enumerate planet prototypes (they are data-stage),
-- so the known base/Space Age planets get named settings and every other
-- planet falls back to fh-color-default at runtime.
local color_settings = {
  { name = "fh-color-default", color = { r = 0.85, g = 0.80, b = 0.62 } },
  { name = "fh-color-nauvis", color = { r = 0.36, g = 0.68, b = 0.38 } },
}
if mods["space-age"] then
  local sa = {
    { name = "fh-color-vulcanus", color = { r = 0.85, g = 0.48, b = 0.24 } },
    { name = "fh-color-fulgora", color = { r = 0.68, g = 0.50, b = 0.82 } },
    { name = "fh-color-gleba", color = { r = 0.55, g = 0.72, b = 0.25 } },
    { name = "fh-color-aquilo", color = { r = 0.42, g = 0.67, b = 0.82 } },
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
    name = "fh-show-points",
    setting_type = "runtime-per-user",
    default_value = true,
    order = "c[ux]-b[show-points]",
  },
  {
    type = "int-setting",
    name = "fh-points-per-level",
    setting_type = "startup",
    default_value = 5,
    minimum_value = 0,
    order = "b[tech]-a[points-per-level]",
  },
  {
    type = "double-setting",
    name = "fh-tech-cost-multiplier",
    setting_type = "startup",
    default_value = 1,
    minimum_value = 0.1,
    order = "b[tech]-b[cost-multiplier]",
  },
  {
    type = "string-setting",
    name = "fh-tech-tiers",
    setting_type = "startup",
    default_value = "",
    allow_blank = true,
    order = "b[tech]-c[tiers-override]",
  },
  {
    type = "int-setting",
    name = "fh-settlement-charter",
    setting_type = "runtime-global",
    default_value = 30,
    minimum_value = 0,
    order = "a[economy]-c[settlement-charter]",
  },
  {
    type = "bool-setting",
    name = "fh-print-claims",
    setting_type = "runtime-global",
    default_value = true,
    order = "c[ux]-a[print-claims]",
  },
  {
    type = "int-setting",
    name = "fh-starting-points",
    setting_type = "runtime-global",
    default_value = 75,
    minimum_value = 0,
    order = "a[economy]-a[starting-points]",
  },
  {
    type = "int-setting",
    name = "fh-refund-percent",
    setting_type = "runtime-global",
    default_value = 25,
    minimum_value = 0,
    maximum_value = 100,
    order = "a[economy]-b[refund-percent]",
  },
})
