data:extend({
  {
    type = "sprite",
    name = "ltr-survey-stake",
    filename = "__land-title-registry__/graphics/survey-stake.png",
    width = 64,
    height = 64,
  },
  -- The claimed-state overlays as script-drawable sprites: the same PNGs
  -- the blockers wear in the world, re-declared so scripts/render.lua can
  -- draw them in chart mode — the striped artwork in map view, per claimed
  -- cell (playtest call). Wilderness needs no sprite: its map presence is
  -- the blocker's engine map_color (see prototypes/blockers.lua).
  {
    type = "sprite",
    name = "ltr-trail-overlay",
    filename = "__land-title-registry__/graphics/trail-overlay.png",
    width = 1024,
    height = 1024,
  },
  {
    type = "sprite",
    name = "ltr-rampart-overlay",
    filename = "__land-title-registry__/graphics/rampart-overlay.png",
    width = 1024,
    height = 1024,
  },
})
