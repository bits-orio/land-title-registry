data:extend({
  {
    type = "sprite",
    name = "ltr-survey-stake",
    filename = "__land-title-registry__/graphics/survey-stake.png",
    width = 64,
    height = 64,
  },
  -- The blocker-state overlays as script-drawable sprites for map view
  -- (scripts/render.lua draws them in chart mode, one per blocker cell —
  -- wilderness included). These are the -chart variants of the blockers'
  -- world artwork: same stripes and cell border, but no between-stripes
  -- wash — on the chart the wash reads as a solid background block over
  -- the terrain (playtest report). Deed has no blocker and no sprite.
  {
    type = "sprite",
    name = "ltr-wilderness-overlay",
    filename = "__land-title-registry__/graphics/wilderness-overlay-chart.png",
    width = 1024,
    height = 1024,
    -- Mip chain to the right of the base (prototypes/blockers.lua explains
    -- why); map view is exactly where the minification gets extreme.
    mipmap_count = 5,
    flags = { "linear-minification", "linear-magnification", "no-crop" },
  },
  {
    type = "sprite",
    name = "ltr-trail-overlay",
    filename = "__land-title-registry__/graphics/trail-overlay-chart.png",
    width = 1024,
    height = 1024,
    -- Mip chain to the right of the base (prototypes/blockers.lua explains
    -- why); map view is exactly where the minification gets extreme.
    mipmap_count = 5,
    flags = { "linear-minification", "linear-magnification", "no-crop" },
  },
  {
    type = "sprite",
    name = "ltr-rampart-overlay",
    filename = "__land-title-registry__/graphics/rampart-overlay-chart.png",
    width = 1024,
    height = 1024,
    -- Mip chain to the right of the base (prototypes/blockers.lua explains
    -- why); map view is exactly where the minification gets extreme.
    mipmap_count = 5,
    flags = { "linear-minification", "linear-magnification", "no-crop" },
  },
})
