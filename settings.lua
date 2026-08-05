-- M1 settings only. M2 adds fh-points-per-level, fh-tech-cost-multiplier,
-- fh-settlement-charter, fh-print-claims; M3 adds fh-show-points; M4 adds the
-- layer-override and fh-tech-tiers startup strings.
data:extend({
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
