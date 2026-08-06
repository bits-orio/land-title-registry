-- Native onboarding: a Land Title Registry category in the built-in Tips and tricks
-- window. Text-only in v1 (no simulations); the engine surfaces triggered
-- tips unprompted.
data:extend({
  {
    type = "tips-and-tricks-item-category",
    name = "land-title-registry",
    order = "z[land-title-registry]",
  },
  {
    type = "tips-and-tricks-item",
    name = "ltr-tip-intro",
    category = "land-title-registry",
    order = "a",
    is_title = true,
    starting_status = "unlocked",
  },
  {
    type = "tips-and-tricks-item",
    name = "ltr-tip-raising",
    category = "land-title-registry",
    order = "b",
    indent = 1,
    trigger = { type = "time-elapsed", ticks = 60 * 90 },
  },
  {
    type = "tips-and-tricks-item",
    name = "ltr-tip-lowering",
    category = "land-title-registry",
    order = "c",
    indent = 1,
    trigger = { type = "time-elapsed", ticks = 60 * 60 * 5 },
  },
})
