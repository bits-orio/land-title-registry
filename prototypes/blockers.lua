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

local function blocker(name, layers)
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
    -- No picture: blockers are invisible. Ownership is shown by the border
    -- renders (M3), not by the enforcement entity.
  }
end

data:extend({
  blocker("fh-cell-wilderness", { ["fh-land"] = true, ["fh-transit"] = true, ["fh-rampart"] = true }),
  blocker("fh-cell-trail", { ["fh-land"] = true, ["fh-rampart"] = true }),
  blocker("fh-cell-rampart", { ["fh-land"] = true }),
})
