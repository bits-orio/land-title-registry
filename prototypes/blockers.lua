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
    collision_box = { { -15.99, -15.99 }, { 15.99, 15.99 } },
    selection_box = { { -16, -16 }, { 16, 16 } },
    selection_priority = 5,
    collision_mask = { layers = layers },
    -- The wilderness blocker carries the red-ribbon overlay as its own
    -- sprite (ADR-0009): the entity already sits exactly on every wilderness
    -- cell, so the engine renders the overlay with zero render objects and
    -- it appears/disappears with claims automatically. Drawn on the floor
    -- layer so everything else renders above it. Trail/Rampart blockers
    -- stay invisible — claimed land looks normal.
    picture = picture,
    render_layer = picture and "floor" or nil,
  }
end

local wilderness_overlay = {
  filename = "__freehold__/graphics/wilderness-overlay.png",
  width = 1024,
  height = 1024,
  scale = 1, -- 1024 px at 32 px/tile = exactly one 32-tile cell
}

data:extend({
  blocker("fh-cell-wilderness",
    { ["fh-land"] = true, ["fh-transit"] = true, ["fh-rampart"] = true },
    wilderness_overlay),
  blocker("fh-cell-trail", { ["fh-land"] = true, ["fh-rampart"] = true }),
  blocker("fh-cell-rampart", { ["fh-land"] = true }),
})
