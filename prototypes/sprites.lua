data:extend({
  {
    type = "sprite",
    name = "ltr-survey-stake",
    filename = "__land-title-registry__/graphics/survey-stake.png",
    width = 64,
    height = 64,
  },
  -- The claimed-state overlays as script-drawable sprites for map view
  -- (scripts/render.lua draws them in chart mode, per claimed cell). These
  -- are the -chart variants of the blockers' world artwork: same stripes
  -- and cell border, but no between-stripes wash — on the chart the wash
  -- reads as a solid background block over the terrain (playtest report).
  -- Wilderness needs no sprite: its map presence is the blocker's engine
  -- map_color (see prototypes/blockers.lua).
  {
    type = "sprite",
    name = "ltr-trail-overlay",
    filename = "__land-title-registry__/graphics/trail-overlay-chart.png",
    width = 1024,
    height = 1024,
  },
  {
    type = "sprite",
    name = "ltr-rampart-overlay",
    filename = "__land-title-registry__/graphics/rampart-overlay-chart.png",
    width = 1024,
    height = 1024,
  },
})
