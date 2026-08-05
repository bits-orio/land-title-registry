-- The three custom collision layers. All entity-facing; no layer is ever
-- placed on a tile prototype (ADR-0007).
data:extend({
  { type = "collision-layer", name = "fh-land" },
  { type = "collision-layer", name = "fh-transit" },
  { type = "collision-layer", name = "fh-rampart" },
})
