-- Shared constants for the state ladder. Prices are the *cumulative* totals;
-- every step cost is a difference of totals, which is what makes full credit
-- (path-independence) hold by construction.

local const = {}

-- Cell edge length in tiles, from the startup setting (ADR-0010). Allowed
-- values all divide the 32-tile chunk, so every cell sits strictly inside
-- exactly one chunk and FACTOR cells span a chunk edge.
const.CELL = tonumber(settings.startup["fh-cell-size"].value)
const.FACTOR = 32 / const.CELL

-- The chunk containing cell (cx, cy) — 1-D helper, apply per axis.
function const.chunk_of_cell(c)
  return math.floor(c / const.FACTOR)
end

-- Inclusive cell-coordinate range covered by chunk coordinate k (1-D).
function const.cell_range_of_chunk(k)
  return k * const.FACTOR, (k + 1) * const.FACTOR - 1
end

-- Cumulative invested points at each state. Wilderness is 0 and is never a
-- stored state string — absence from the registry means Wilderness.
const.TOTAL = {
  wilderness = 0,
  trail = 1,
  rampart = 3,
  deed = 5,
}

-- Downgrades reverse exactly one step, right to left.
const.PREV = {
  deed = "rampart",
  rampart = "trail",
  trail = "wilderness",
}

-- Blocker entity per state; Deed has none (absence of a blocker means full
-- rights).
const.BLOCKER = {
  wilderness = "fh-cell-wilderness",
  trail = "fh-cell-trail",
  rampart = "fh-cell-rampart",
}

const.BLOCKER_NAMES = { "fh-cell-wilderness", "fh-cell-trail", "fh-cell-rampart" }

-- Downgrade validity: a cell may only shed a right nothing in it is using.
-- Keyed by the state being downgraded FROM; the cell must contain no entity
-- of the acting force carrying any of these layers.
const.VALIDITY_LAYERS = {
  deed = { "fh-land" },
  rampart = { "fh-rampart" },
  trail = { "fh-land", "fh-transit", "fh-rampart" },
}

-- Next step up the ladder, for hover feedback and the cursor label's
-- can-afford tint.
const.NEXT_STEP_COST = {
  wilderness = 1, -- -> trail
  trail = 2, -- -> rampart
  rampart = 2, -- -> deed
  deed = nil,
}

return const
