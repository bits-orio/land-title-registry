-- Claim/upgrade/downgrade rules: eligibility, the whole-rectangle anchor test
-- (ADR-0006), all-or-nothing batch pricing with full credit, and the single
-- sanctioned script-side check in the mod — downgrade validity.
--
-- This module is pure rules; player feedback (sounds, flying text) lives in
-- scripts/tool.lua so the remote interface (M4) can drive the same rules.

local const = require("scripts.const")
local registry = require("scripts.registry")
local blockers = require("scripts.blockers")
local economy = require("scripts.economy")
local custom_events = require("scripts.custom_events")

local claims = {}

-- Which source states each claim action may act on. Wilderness is implicit
-- (every claim action may claim Wilderness; Rampart composes Trail
-- internally, Deed composes Trail — the price is the sum of credited steps).
local UPGRADE_EDGES = {
  trail = {},
  rampart = { trail = true },
  deed = { trail = true, rampart = true },
}

local function cell_of(position)
  return math.floor(position.x / const.CELL), math.floor(position.y / const.CELL)
end

-- The batch-level anchor test: is there anything to grow FROM? True iff the
-- rectangle contains or 4-way-edge-touches a cell the force owns — or the
-- force owns nothing on the surface and the rectangle contains the acting
-- player's standing cell (the seeding/recovery clause, ADR-0006). Checked
-- before eligibility, so a fully unanchored drag is a loud denial.
local function batch_is_anchored(surface, rect, force, player)
  local surface_index = surface.index
  local force_index = force.index

  local function owned(cx, cy)
    local rec = registry.get(surface_index, registry.cell_key(cx, cy))
    return rec ~= nil and rec.force_index == force_index
  end

  for cy = rect.y1, rect.y2 do
    for cx = rect.x1, rect.x2 do
      if owned(cx, cy)
        or owned(cx - 1, cy) or owned(cx + 1, cy)
        or owned(cx, cy - 1) or owned(cx, cy + 1) then
        return true
      end
    end
  end

  -- Standing-cell clause: seeding and recovery in one line. The acting
  -- player must be physically on this surface, inside the rectangle.
  if not registry.force_owns_any(surface_index, force_index)
    and player and player.valid
    and player.physical_surface_index == surface_index then
    local px, py = cell_of(player.physical_position)
    if px >= rect.x1 and px <= rect.x2 and py >= rect.y1 and py <= rect.y2 then
      return true
    end
  end

  return false
end

-- Progressive adjacency inside the rectangle. The rectangle is NOT
-- guaranteed hole-free: foreign-owned cells and ungenerated chunks are
-- ineligible and break its connectivity, so the anchor test alone could
-- claim islands across a hole. This breadth-first pass keeps only the new
-- claims actually reachable from the force's territory (or the standing
-- cell), walking through same-batch candidates and the force's own cells
-- inside the rectangle. Order-independent by construction, so all-or-nothing
-- stays predictable (ADR-0006).
--
-- `candidates`: map cell_key -> transition for eligible Wilderness cells.
-- Returns the reachable subset as an array.
local function reachable_claims(surface, rect, force, player, candidates)
  local surface_index = surface.index
  local force_index = force.index

  local function owned(cx, cy)
    local rec = registry.get(surface_index, registry.cell_key(cx, cy))
    return rec ~= nil and rec.force_index == force_index
  end

  local owns_any = registry.force_owns_any(surface_index, force_index)
  local standing_key
  if not owns_any and player and player.valid
    and player.physical_surface_index == surface_index then
    local px, py = cell_of(player.physical_position)
    standing_key = registry.cell_key(px, py)
  end

  -- Seeds: candidates adjacent to owned territory (inside or outside the
  -- rectangle), or the standing cell when the force owns nothing here.
  local queue, reached = {}, {}
  for key, t in pairs(candidates) do
    local seeded = (key == standing_key)
      or owned(t.cx - 1, t.cy) or owned(t.cx + 1, t.cy)
      or owned(t.cx, t.cy - 1) or owned(t.cx, t.cy + 1)
    if seeded then
      reached[key] = true
      queue[#queue + 1] = t
    end
  end

  -- Expand through fellow candidates. Owned cells inside the rectangle are
  -- connectors, but every candidate adjacent to an owned cell is already a
  -- seed, so walking candidate-to-candidate is sufficient.
  local head = 1
  while head <= #queue do
    local t = queue[head]
    head = head + 1
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
      local nx, ny = t.cx + d[1], t.cy + d[2]
      if nx >= rect.x1 and nx <= rect.x2 and ny >= rect.y1 and ny <= rect.y2 then
        local nkey = registry.cell_key(nx, ny)
        local nt = candidates[nkey]
        if nt and not reached[nkey] then
          reached[nkey] = true
          queue[#queue + 1] = nt
        end
      end
    end
  end

  return queue
end

-- Downgrade validity: one find_entities_filtered area query — the only
-- script-side policing in the entire mod (ADR-0002). The force filter
-- naturally excludes the neutral blocker itself.
local function may_downgrade(surface, cx, cy, from_state, force)
  local found = surface.find_entities_filtered({
    area = blockers.cell_area(cx, cy),
    force = force,
    collision_mask = const.VALIDITY_LAYERS[from_state],
    limit = 1,
  })
  return #found == 0
end

-- Evaluate one cell for a claim action. Returns nil (ineligible no-op) or
-- {cx, cy, cell_key, old_state, new_state, cost, is_new_claim}.
local function evaluate_claim(surface, force, cx, cy, target)
  local surface_index = surface.index
  local cell_key = registry.cell_key(cx, cy)
  local rec = registry.get(surface_index, cell_key)

  if rec == nil then
    -- New claim on Wilderness; needs a generated chunk so the blocker swap
    -- has somewhere to happen.
    if not surface.is_chunk_generated({ x = cx, y = cy }) then return nil end
    return {
      cx = cx, cy = cy, cell_key = cell_key,
      old_state = "wilderness", new_state = target,
      cost = const.TOTAL[target], is_new_claim = true,
    }
  end

  if rec.force_index ~= force.index then return nil end
  if not UPGRADE_EDGES[target][rec.state] then return nil end

  return {
    cx = cx, cy = cy, cell_key = cell_key,
    old_state = rec.state, new_state = target,
    cost = const.TOTAL[target] - const.TOTAL[rec.state], -- full credit
    is_new_claim = false,
  }
end

local function evaluate_downgrade(surface, force, cx, cy)
  local surface_index = surface.index
  local cell_key = registry.cell_key(cx, cy)
  local rec = registry.get(surface_index, cell_key)
  if rec == nil or rec.force_index ~= force.index then return nil end
  if not may_downgrade(surface, cx, cy, rec.state, force) then return nil end

  local new_state = const.PREV[rec.state]
  local step = const.TOTAL[rec.state] - const.TOTAL[new_state]
  return {
    cx = cx, cy = cy, cell_key = cell_key,
    old_state = rec.state, new_state = new_state,
    refund = step * economy.refund_percent() / 100,
  }
end

local function apply_claim(surface, force, player, t)
  local rec = registry.get(surface.index, t.cell_key)
  if rec then
    rec.state = t.new_state
    rec.invested_points = const.TOTAL[t.new_state]
  else
    registry.set(surface.index, t.cell_key, {
      state = t.new_state,
      force_index = force.index,
      claimed_tick = game.tick,
      invested_points = const.TOTAL[t.new_state],
      claimant = player and player.name or nil,
    })
  end
  blockers.set(surface, t.cx, t.cy, t.new_state)
  script.raise_event(custom_events.on_cell_claimed, {
    surface_index = surface.index,
    cell_pos = { x = t.cx, y = t.cy },
    force_name = force.name,
    old_state = t.old_state,
    new_state = t.new_state,
    player_index = player and player.index or nil,
    cost = t.cost,
  })
end

local function apply_downgrade(surface, force, player, t)
  if t.new_state == "wilderness" then
    registry.clear_cell(surface.index, t.cell_key)
  else
    local rec = registry.get(surface.index, t.cell_key)
    rec.state = t.new_state
    rec.invested_points = const.TOTAL[t.new_state]
  end
  blockers.set(surface, t.cx, t.cy, t.new_state)
  script.raise_event(custom_events.on_cell_downgraded, {
    surface_index = surface.index,
    cell_pos = { x = t.cx, y = t.cy },
    force_name = force.name,
    old_state = t.old_state,
    new_state = t.new_state,
    player_index = player and player.index or nil,
    refund = t.refund,
  })
end

-- Apply one survey-tool batch. `action` is "trail" | "rampart" | "deed" |
-- "downgrade"; `rect` is inclusive cell coordinates {x1, y1, x2, y2}.
--
-- Returns a result for the caller's feedback:
--   {denied = "disabled"}
--   {denied = "anchor"}
--   {denied = "points", need = n, have = n}
--   {applied = n, cost = n}      (claim actions; n may be 0 -> silent no-op)
--   {applied = n, refund = n}    (downgrade)
function claims.apply_batch(surface, force, player, rect, action)
  if storage.disabled_surfaces[surface.index] then
    return { denied = "disabled" }
  end

  if action == "downgrade" then
    local transitions = {}
    local total_refund = 0
    for cy = rect.y1, rect.y2 do
      for cx = rect.x1, rect.x2 do
        local t = evaluate_downgrade(surface, force, cx, cy)
        if t then
          transitions[#transitions + 1] = t
          total_refund = total_refund + t.refund
        end
      end
    end
    for _, t in ipairs(transitions) do
      apply_downgrade(surface, force, player, t)
    end
    if total_refund > 0 then
      economy.change(force, total_refund, "refund")
    end
    return { applied = #transitions, refund = total_refund }
  end

  -- Anchor first, before eligibility, per the design: an unanchored claim
  -- drag is a loud denial, never a silent no-op.
  if not batch_is_anchored(surface, rect, force, player) then
    return { denied = "anchor" }
  end

  -- Eligibility: upgrades of owned cells apply unconditionally (their cells
  -- anchor the batch by definition); new Wilderness claims must additionally
  -- survive the progressive-adjacency pass, because foreign cells and
  -- ungenerated chunks can punch holes in the rectangle.
  local transitions = {}
  local candidates = {}
  for cy = rect.y1, rect.y2 do
    for cx = rect.x1, rect.x2 do
      local t = evaluate_claim(surface, force, cx, cy, action)
      if t then
        if t.is_new_claim then
          candidates[t.cell_key] = t
        else
          transitions[#transitions + 1] = t
        end
      end
    end
  end
  for _, t in ipairs(reachable_claims(surface, rect, force, player, candidates)) do
    transitions[#transitions + 1] = t
  end

  local total_cost = 0
  for _, t in ipairs(transitions) do
    total_cost = total_cost + t.cost
  end

  local balance = economy.get(force.index)
  if total_cost > balance then
    return { denied = "points", need = total_cost, have = balance }
  end

  for _, t in ipairs(transitions) do
    apply_claim(surface, force, player, t)
  end
  if total_cost > 0 then
    economy.change(force, -total_cost, "claim")
  end
  return { applied = #transitions, cost = total_cost }
end

return claims
