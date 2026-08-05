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
local SIZE = tonumber(settings.startup["fh-cell-size"].value)
local HALF = SIZE / 2

local function blocker(name, layers, picture)
  return {
    type = "simple-entity-with-owner",
    name = name,
    icon = "__base__/graphics/icons/landfill.png",
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
-- 32 px/tile). Wilderness is the loud one; trail and rampart are subtle
-- tints so claimed land still reads as normal ground at a glance. Deed has
-- no blocker and no overlay.
local function overlay(name)
  return {
    filename = "__freehold__/graphics/" .. name .. ".png",
    width = 1024,
    height = 1024,
    scale = SIZE * 32 / 1024,
  }
end

data:extend({
  blocker("fh-cell-wilderness",
    { ["fh-land"] = true, ["fh-transit"] = true, ["fh-rampart"] = true },
    overlay("wilderness-overlay")),
  blocker("fh-cell-trail", { ["fh-land"] = true, ["fh-rampart"] = true },
    overlay("trail-overlay")),
  blocker("fh-cell-rampart", { ["fh-land"] = true },
    overlay("rampart-overlay")),
})
