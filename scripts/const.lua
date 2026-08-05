-- Shared constants for the state ladder. Prices are the *cumulative* totals;
-- every step cost is a difference of totals, which is what makes full credit
-- (path-independence) hold by construction.

local const = {}

const.CELL = 32

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
