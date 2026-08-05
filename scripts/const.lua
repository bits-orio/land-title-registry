-- Shared constants for the state ladder. Prices are the *cumulative* totals;
-- every step cost is a difference of totals, which is what makes full credit
-- (path-independence) hold by construction.

local const = {}

-- Cell edge length in tiles, from the startup setting (ADR-0010): 16, 24,
-- or 32. 24 does not divide the chunk — a 24-tile cell can straddle a chunk
-- boundary — so the mapping helpers below are general overlap ranges, and a
-- blocker is created (full-size) the moment the FIRST chunk touching its
-- cell generates: the engine handles entities on ungenerated chunks (probed
-- and recorded in ADR-0010).
const.CELL = tonumber(settings.startup["fh-cell-size"].value)

-- Inclusive cell-coordinate range overlapping chunk coordinate k (1-D).
function const.cell_range_of_chunk(k)
  return math.floor(k * 32 / const.CELL),
    math.floor((k * 32 + 31) / const.CELL)
end

-- Inclusive chunk-coordinate range overlapped by cell coordinate c (1-D).
function const.chunk_range_of_cell(c)
  return math.floor(c * const.CELL / 32),
    math.floor((c * const.CELL + const.CELL - 1) / 32)
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

-- The rung above each state, for the advance action (drag = raise one rung).
const.NEXT_STATE = {
  wilderness = "trail",
  trail = "rampart",
  rampart = "deed",
  -- deed: top of the ladder
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
