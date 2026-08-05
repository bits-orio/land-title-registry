-- Native onboarding: a Freehold category in the built-in Tips and tricks
-- window. Text-only in v1 (no simulations); the engine surfaces triggered
-- tips unprompted.
data:extend({
  {
    type = "tips-and-tricks-item-category",
    name = "freehold",
    order = "z[freehold]",
  },
  {
    type = "tips-and-tricks-item",
    name = "fh-tip-freehold",
    category = "freehold",
    order = "a",
    is_title = true,
    starting_status = "unlocked",
  },
  {
    type = "tips-and-tricks-item",
    name = "fh-tip-raising",
    category = "freehold",
    order = "b",
    indent = 1,
    trigger = { type = "time-elapsed", ticks = 60 * 90 },
  },
  {
    type = "tips-and-tricks-item",
    name = "fh-tip-lowering",
    category = "freehold",
    order = "c",
    indent = 1,
    trigger = { type = "time-elapsed", ticks = 60 * 60 * 5 },
  },
})
