-- Blocker lifecycle: the derived-state manager. Blockers are consequences of
-- the registry, never authoritative (ADR-0003). If the world and the registry
-- disagree, this module rebuilds the world to match.

local const = require("scripts.const")
local registry = require("scripts.registry")
local render = require("scripts.render")
local chronicle = require("scripts.chronicle")

local blockers = {}

-- Bounded slice per drain so large rebuilds never spike a tick.
local REBUILD_TICK_INTERVAL = 2
local REBUILD_SLICE = 48

-- Is any chunk touching this cell generated? The gameplay gate for claims
-- and heals; blocker creation itself works on ungenerated chunks.
function blockers.cell_touches_generated(surface, cx, cy)
  local kx0, kx1 = const.chunk_range_of_cell(cx)
  local ky0, ky1 = const.chunk_range_of_cell(cy)
  for ky = ky0, ky1 do
    for kx = kx0, kx1 do
      if surface.is_chunk_generated({ x = kx, y = ky }) then return true end
    end
  end
  return false
end

function blockers.cell_center(cx, cy)
  return { x = cx * const.CELL + const.CELL / 2, y = cy * const.CELL + const.CELL / 2 }
end

function blockers.cell_area(cx, cy)
  return {
    left_top = { x = cx * const.CELL, y = cy * const.CELL },
    right_bottom = { x = (cx + 1) * const.CELL, y = (cy + 1) * const.CELL },
  }
end

local function register(entity, surface_index, cell_key)
  local regid = script.register_on_object_destroyed(entity)
  storage.blocker_registrations[regid] = { surface_index = surface_index, cell_key = cell_key }
  storage.blocker_regids[surface_index][cell_key] = regid
end

-- Retire a cell's registration BEFORE an intentional destroy, so the
-- on_object_destroyed that follows finds no entry and does not self-heal.
local function unregister(surface_index, cell_key)
  local regids = storage.blocker_regids[surface_index]
  local regid = regids and regids[cell_key]
  if regid then
    storage.blocker_registrations[regid] = nil
    regids[cell_key] = nil
  end
end

-- Ensure the blocker in cell (cx, cy) matches `state`. The cheap path used
-- by claims and chunk generation: looks only at the cell center.
function blockers.set(surface, cx, cy, state)
  local surface_index = surface.index
  local cell_key = registry.cell_key(cx, cy)
  local expected = const.BLOCKER[state] -- nil for deed
  local center = blockers.cell_center(cx, cy)

  registry.init_surface(surface_index)

  local kept
  for _, name in ipairs(const.BLOCKER_NAMES) do
    local entity = surface.find_entity(name, center)
    if entity then
      if name == expected and not kept then
        kept = entity
      else
        unregister(surface_index, cell_key)
        entity.destroy()
      end
    end
  end

  if kept then
    -- A matching blocker can pre-exist WITHOUT bookkeeping: surface
    -- cloning copies entities but not storage (MTS team-surface seeding
    -- clones per chunk, and its handler runs before ours). Adopt it, or
    -- the regid-gated map sprite never appears for the cell.
    if not storage.blocker_regids[surface_index][cell_key] then
      kept.destructible = false
      register(kept, surface_index, cell_key)
    end
  elseif expected then
    local entity = surface.create_entity({
      name = expected,
      position = center,
      force = "neutral",
      create_build_effect_smoke = false,
    })
    if entity then
      entity.destructible = false
      register(entity, surface_index, cell_key)
    end
  end
end

-- Deep reconcile for one cell: sweeps the whole cell area for stray or
-- duplicate blockers (not just the center), then ensures the expected one.
-- Used by the rebuild queue.
function blockers.reconcile(surface, cx, cy)
  local surface_index = surface.index
  local cell_key = registry.cell_key(cx, cy)
  -- A disabled surface expects NO blocker anywhere: the same reconcile that
  -- builds an enabled surface sweeps a disabled one clean.
  local expected
  if not storage.disabled_surfaces[surface_index] then
    expected = const.BLOCKER[registry.state_of(surface_index, cell_key)]
  end
  local center = blockers.cell_center(cx, cy)

  registry.init_surface(surface_index)

  local kept
  local strays = surface.find_entities_filtered({
    area = blockers.cell_area(cx, cy),
    name = const.BLOCKER_NAMES,
  })
  for _, entity in pairs(strays) do
    local pos = entity.position
    if not kept and entity.name == expected and pos.x == center.x and pos.y == center.y then
      kept = entity
    else
      entity.destroy()
    end
  end

  unregister(surface_index, cell_key)
  if kept then
    register(kept, surface_index, cell_key)
  elseif expected then
    local entity = surface.create_entity({
      name = expected,
      position = center,
      force = "neutral",
      create_build_effect_smoke = false,
    })
    if entity then
      entity.destructible = false
      register(entity, surface_index, cell_key)
    end
  end

  -- Renders are derived state exactly like blockers: /ltr-rebuild, surface
  -- sweeps, and re-enables refresh them through the same reconcile.
  render.refresh_cell(surface, cx, cy)
  chronicle.refresh_cell(surface, cx, cy)
end

-- Every cell of the newly generated chunk gets the blocker matching its
-- REGISTERED state (every cell overlapping the chunk). Never skip registered cells:
-- the only way a chunk generates for one is a surface regeneration, and
-- skipping would leave it blockerless — which is how Deed is represented.
function blockers.on_chunk_generated(event)
  local surface = event.surface
  if storage.disabled_surfaces[surface.index] then return end
  local x0, x1 = const.cell_range_of_chunk(event.position.x)
  local y0, y1 = const.cell_range_of_chunk(event.position.y)
  for cy = y0, y1 do
    for cx = x0, x1 do
      blockers.set(surface, cx, cy, registry.state_of(surface.index, registry.cell_key(cx, cy)))
      -- Fresh blockers need their map-view chart sprite. Claims and
      -- downgrades refresh through their events; chunk generation is the
      -- third way a blocker appears, and it refreshes here.
      render.refresh_cell(surface, cx, cy)
    end
  end
end

-- A blocker died that we did not destroy ourselves (another mod, the editor,
-- a surface event we did not see). The registry wins: re-derive the cell.
function blockers.on_object_destroyed(event)
  local entry = storage.blocker_registrations[event.registration_number]
  if not entry then return end
  storage.blocker_registrations[event.registration_number] = nil
  local regids = storage.blocker_regids[entry.surface_index]
  if regids then regids[entry.cell_key] = nil end

  local surface = game.surfaces[entry.surface_index]
  if not (surface and surface.valid) then return end
  if storage.disabled_surfaces[surface.index] then return end
  local pos = registry.cell_key_to_pos(entry.cell_key)
  if not blockers.cell_touches_generated(surface, pos.x, pos.y) then return end
  blockers.set(surface, pos.x, pos.y, registry.state_of(surface.index, entry.cell_key))
end

-- ---------------------------------------------------------------------------
-- Rebuild queue: the temporary on_nth_tick pattern. Work items live in
-- storage (a save mid-batch is deterministic); the handler drains a bounded
-- slice and unregisters itself when the queue empties.

local function drain_rebuild_queue()
  local queue = storage.rebuild_queue
  local n = #queue
  local slice = math.min(REBUILD_SLICE, n)
  for _ = 1, slice do
    local item = queue[n]
    queue[n] = nil
    n = n - 1
    -- Queue items are CHUNK coordinates; reconcile every cell of the chunk.
    local surface = game.surfaces[item.surface_index]
    if surface and surface.valid and surface.is_chunk_generated({ x = item.x, y = item.y }) then
      local x0, x1 = const.cell_range_of_chunk(item.x)
      local y0, y1 = const.cell_range_of_chunk(item.y)
      for cy = y0, y1 do
        for cx = x0, x1 do
          blockers.reconcile(surface, cx, cy)
        end
      end
    end
  end
  if n == 0 then
    script.on_nth_tick(REBUILD_TICK_INTERVAL, nil)
    for _, player in pairs(game.players) do
      player.print({ "land-title-registry.rebuild-done" })
    end
    -- An epoch rechart waits here, at the END of the drain, so its
    -- on_chunk_charted volley sweeps over the freshly created sprites and
    -- reveals every charted chunk's wilderness stripes (render.lua).
    if storage.rechart_pending then
      storage.rechart_pending = nil
      for _, force in pairs(game.forces) do
        force.rechart()
      end
    end
    -- Census to the log: one line per completed rebuild, so a "stripes
    -- missing" report comes with evidence of created-vs-visible.
    local total, visible = 0, 0
    for _, sprites in pairs(storage.chart_sprites) do
      for _, sprite in pairs(sprites) do
        if sprite.valid then
          total = total + 1
          if sprite.visible then visible = visible + 1 end
        end
      end
    end
    log("LTR-MAP census after rebuild: " .. total .. " wilderness chart sprites, " .. visible .. " visible")
  end
end

-- Called from on_load as well as after enqueueing: registration must happen
-- in both places, and on_load may not touch storage beyond reading it.
function blockers.ensure_rebuild_handler()
  if next(storage.rebuild_queue) then
    script.on_nth_tick(REBUILD_TICK_INTERVAL, drain_rebuild_queue)
  end
end

function blockers.enqueue_surface_rebuild(surface)
  local queue = storage.rebuild_queue
  local count = 0
  for chunk in surface.get_chunks() do
    queue[#queue + 1] = { surface_index = surface.index, x = chunk.x, y = chunk.y }
    count = count + 1
  end
  blockers.ensure_rebuild_handler()
  return count
end

function blockers.enqueue_full_rebuild()
  local total = 0
  for _, surface in pairs(game.surfaces) do
    total = total + blockers.enqueue_surface_rebuild(surface)
  end
  return total
end

return blockers
