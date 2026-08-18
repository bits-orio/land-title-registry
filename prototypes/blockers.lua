-- One blocker entity per non-Deed cell. The mask denies the layers the cell
-- has not earned; a Deed cell has no blocker at all.
--
-- The 15.99 half-extent keeps the collision box fractionally inside the cell
-- so it never collides across the boundary with entities placed flush against
-- the edge of an adjacent cell.
--
-- selection_priority is deliberately LOW (ADR-0005): a high-priority full-cell
-- selection box would steal hover/tooltips/pipette from every entity the
-- player builds inside Trail and Rampart cells. Area selection is unaffected
-- by priority, and the survey-tool handlers read event.area anyway.

-- Cell size is a startup setting (ADR-0010): 16, 24, or 32 tiles. 24-tile
-- cells straddle chunk boundaries; the engine handles entities whose boxes
-- reach into ungenerated chunks, so the blocker is always full-size.
local SIZE = tonumber(settings.startup["ltr-cell-size"].value)
local HALF = SIZE / 2

-- Every blocker keeps not-on-map: map presence is script chart sprites of
-- the striped artwork (scripts/render.lua), one per blocker — the same
-- cost class as the blocker entities themselves. Engine map_color tints
-- were tried twice and reverted: a tint on either side of the
-- claimed/unclaimed boundary makes the OTHER side read as tinted by
-- contrast (chart terrain has its own hues), and the chart caches mean a
-- tint change needs a forced rechart to even appear.
local function blocker(name, layers, picture)
  return {
    type = "simple-entity-with-owner",
    name = name,
    icon = "__land-title-registry__/graphics/survey-tool.png",
    icon_size = 64,
    flags = {
      "placeable-off-grid",
      "not-repairable",
      "not-on-map",
      "not-deconstructable",
      "not-blueprintable",
    },
    allow_copy_paste = false,
    -- The 0.01 inset keeps the box fractionally inside the cell so it never
    -- collides across the boundary with entities placed flush against the
    -- edge of an adjacent cell.
    collision_box = { { -(HALF - 0.01), -(HALF - 0.01) }, { HALF - 0.01, HALF - 0.01 } },
    selection_box = { { -HALF, -HALF }, { HALF, HALF } },
    selection_priority = 5,
    collision_mask = { layers = layers },
    -- Each blocker carries its state's overlay as its own sprite (ADR-0009):
    -- the entity already sits exactly on the right cells, so the engine
    -- renders the overlay with zero render objects and it swaps with state
    -- transitions automatically. Drawn on the floor layer so everything
    -- else renders above it.
    picture = picture,
    render_layer = picture and "floor" or nil,
  }
end

-- Each 1024-px overlay is scaled to cover exactly one cell (SIZE tiles at
-- 32 px/tile). Wilderness is the loud one — fully opaque red stripes, a
-- hard no at any zoom. Rampart wears the original softer red pattern
-- (playtest call: one rung from Deed should still read as "not fully
-- yours"), trail stays a subtle orange tint, and Deed has no blocker and
-- no overlay.
local function overlay(name)
  return {
    filename = "__land-title-registry__/graphics/" .. name .. ".png",
    width = 1024,
    height = 1024,
    scale = SIZE * 32 / 1024,
    -- The art is anti-aliased at source; linear filtering keeps it smooth
    -- through the engine's own zoom scaling.
    flags = { "linear-minification", "linear-magnification", "no-crop" },
    -- The file is 1984 px wide: the 1024 base plus its mip chain (see
    -- tools/gen_overlays.py). Linear minification alone samples a 2x2
    -- texel footprint at any distance, which scrambles a 128-texel stripe
    -- period the moment the view minifies past ~2x. "no-crop" keeps the
    -- engine from trimming the sheet and breaking the chain's geometry.
    mipmap_count = 5,
  }
end

data:extend({
  blocker("ltr-cell-wilderness",
    { ["ltr-land"] = true, ["ltr-transit"] = true, ["ltr-rampart"] = true },
    overlay("wilderness-overlay")),
  blocker("ltr-cell-trail", { ["ltr-land"] = true, ["ltr-rampart"] = true },
    overlay("trail-overlay")),
  blocker("ltr-cell-rampart", { ["ltr-land"] = true },
    overlay("rampart-overlay")),
})
