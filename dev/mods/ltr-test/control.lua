-- Headless tests for Land Title Registry, read by dev/run-tests.sh through
-- the LTR_TEST log lines.
--
-- The modules under test are required straight from the mod, so they run in
-- THIS mod's Lua state with this mod's own `storage`: a private registry and
-- purse on the real map, next to the real mod and out of its way. The cases
-- seed that registry directly and only read the world, apart from the one
-- real batch that proves a dry run and the real thing agree.

local registry = require("__land-title-registry__/scripts/registry")
local economy = require("__land-title-registry__/scripts/economy")
local claims = require("__land-title-registry__/scripts/claims")
local custom_events = require("__land-title-registry__/scripts/custom_events")
local drag_preview = require("__land-title-registry__/scripts/drag_preview")
local const = require("__land-title-registry__/scripts/const")

local RUN_TICK = 10
local TOOL = "ltr-survey-tool"
local failures = 0
local raised = 0

local function check(name, ok, why)
  if ok then
    log("LTR_TEST PASS " .. name)
  else
    failures = failures + 1
    log("LTR_TEST FAIL " .. name .. ": " .. tostring(why))
  end
end

local function rect(x1, y1, x2, y2) return { x1 = x1, y1 = y1, x2 = x2, y2 = y2 } end

local function own(surface, force, cx, cy, state)
  registry.set(surface.index, registry.cell_key(cx, cy), {
    state = state, force_index = force.index, claimed_tick = 0,
    invested_points = const.TOTAL[state],
  })
end

-- Everything a batch could change: the registry, the purse, the origins,
-- the blockers on the ground and the claim events raised.
local function snapshot(surface, force)
  local blockers = surface.count_entities_filtered({
    name = const.BLOCKER_NAMES,
    area = { { -6 * const.CELL, -6 * const.CELL }, { 6 * const.CELL, 6 * const.CELL } },
  })
  return serpent.line({ storage.cells, storage.points, storage.origins, blockers, raised, economy.get(force.index) })
end

local function dry(surface, force, r, action)
  return claims.apply_batch(surface, force, nil, r, action, { dry_run = true })
end

local function dry_run_cases(surface, force)
  economy.set(force, 100, "test")
  own(surface, force, 0, 0, "deed")
  own(surface, force, 1, 0, "trail")
  local area = rect(-1, -1, 1, 1)
  local before = snapshot(surface, force)

  -- Seven Wilderness cells to Trail (1 each) plus the Trail cell to Rampart (2).
  local advance = dry(surface, force, area, "advance")
  check("dry.advance.result", advance.applied == 8 and advance.cost == 9, serpent.line(advance))
  local deed = dry(surface, force, area, "deed")
  check("dry.deed.result", deed.applied == 8 and deed.cost == 7 * 5 + 4, serpent.line(deed))
  local lower = dry(surface, force, area, "downgrade")
  check("dry.downgrade.result", lower.applied == 2 and lower.refund > 0, serpent.line(lower))
  local release = dry(surface, force, area, "release")
  check("dry.release.result", release.applied == 2 and release.refund >= lower.refund, serpent.line(release))
  local far = dry(surface, force, rect(4, 4, 5, 5), "advance")
  check("dry.unanchored.result", far.denied == "anchor", serpent.line(far))
  check("dry.leaves-everything", snapshot(surface, force) == before, "state changed by a dry run")

  economy.set(force, 3, "test")
  local short_before = snapshot(surface, force)
  local short = dry(surface, force, area, "advance")
  check("dry.short.result", short.denied == "points" and short.need == 9 and short.have == 3 and short.cells == 8,
    serpent.line(short))
  check("dry.short.leaves-everything", snapshot(surface, force) == short_before, "state changed by a dry run")

  -- The real batch: same numbers as its dry run, and this one does change things.
  economy.set(force, 100, "test")
  local real_before = snapshot(surface, force)
  local real = claims.apply_batch(surface, force, nil, area, "advance")
  check("real.matches-dry", real.applied == advance.applied and real.cost == advance.cost, serpent.line(real))
  check("real.changes-state", snapshot(surface, force) ~= real_before and economy.get(force.index) == 91
    and raised == 8, "points=" .. economy.get(force.index) .. " raised=" .. raised)
end

local function drag_event(player, surface, mode, x1, y1, x2, y2)
  return {
    player_index = player.index, surface = surface, item = TOOL,
    selection_mode = defines.selection_mode[mode],
    area = { left_top = { x = x1, y = y1 }, right_bottom = { x = x2, y = y2 } },
    position = { x = x1, y = y1 }, cursor_position = { x = x2, y = y2 },
  }
end

-- What a drag draws is for the dragging player alone: every render object
-- made since `known` (a set of ids) names that player and nobody else.
-- Returns nil, or what is wrong with the first object that breaks the rule.
local function drawn_for_others(known, player)
  for _, object in pairs(rendering.get_all_objects("ltr-test")) do
    if not known[object.id] then
      local players, forces = object.players, object.forces
      if not (players and #players == 1 and players[1].index == player.index) then
        return object.type .. " #" .. object.id .. " is drawn for " .. (players and #players or 0) .. " players"
      end
      if forces and #forces > 0 then return object.type .. " #" .. object.id .. " is drawn for a force" end
    end
  end
  return nil
end

-- The label of a player's preview: the object drawn in the world, and
-- whether its twin for the map says the same thing in the same place.
local function label_of(player)
  local preview = storage.drag_preview[player.index]
  local objects = preview and preview.objects
  if not objects then return nil, false end
  local world, map = objects[1], objects[2]
  local same = #objects == 2 and world.render_mode == "game" and map.render_mode == "chart"
    and serpent.line(world.text) == serpent.line(map.text)
    and serpent.line(world.target.position) == serpent.line(map.target.position)
    and world.alignment == map.alignment and world.vertical_alignment == map.vertical_alignment
  return world, same
end

-- The handlers are fed hand-made events: the engine only sends the real ones
-- for a mouse drag, which dev/run-drag.sh covers.
local function preview_cases(player, surface, force)
  local C = const.CELL
  local before = snapshot(surface, force)
  local objects = #rendering.get_all_objects("ltr-test")
  local known = {}
  for _, object in pairs(rendering.get_all_objects("ltr-test")) do known[object.id] = true end

  drag_preview.on_changed(drag_event(player, surface, "select", 2.5 * C, 0.5 * C, 2.5 * C, 0.5 * C))
  local label, twin = label_of(player)
  check("preview.start.label", label ~= nil and label.valid and label.text[1] == "land-title-registry.drag-cost"
    and tonumber(label.text[2]) == 1, label and serpent.line(label.text))
  -- A render object shows in the world or on the map, never both: the label
  -- is a pair, and the drag has to read the same in either view.
  check("preview.start.world-and-map", twin, "the label is not a matching world and map pair")

  drag_preview.on_changed(drag_event(player, surface, "select", 2.5 * C, 0.5 * C, 3.5 * C, 1.5 * C))
  local same = label_of(player)
  check("preview.change.same-object", same.valid and same.id == label.id and tonumber(same.text[2]) == 4
    and #rendering.get_all_objects("ltr-test") == objects + 2, serpent.line(same.text))

  local target = same.target.position
  drag_preview.on_changed(drag_event(player, surface, "select", 2.5 * C, 0.5 * C, 3.6 * C, 1.6 * C))
  local moved, moved_twin = label_of(player)
  check("preview.move.follows-cursor", moved.id == label.id and moved.target.position.x > target.x
    and tonumber(moved.text[2]) == 4 and moved_twin, serpent.line(moved.target.position))

  drag_preview.on_changed(drag_event(player, surface, "reverse_select", -0.5 * C, -0.5 * C, 1.5 * C, 1.5 * C))
  local refund, refund_twin = label_of(player)
  check("preview.reverse.refund", refund.id == label.id and refund.text[1] == "land-title-registry.drag-refund"
    and refund_twin, serpent.line(refund.text))

  drag_preview.on_changed(drag_event(player, surface, "select", 20.5 * C, 20.5 * C, 20.6 * C, 20.6 * C))
  local denied = label_of(player)
  check("preview.unanchored.denied", denied.text[1] == "land-title-registry.no-adjacency", serpent.line(denied.text))

  -- Past the size the preview prices: the label gives the cell count alone.
  drag_preview.on_changed(drag_event(player, surface, "select", -8.5 * C, -8.5 * C, 8.5 * C, 8.5 * C))
  local large, large_twin = label_of(player)
  check("preview.too-large.label", large.id == label.id and large.text[1] == "land-title-registry.drag-too-large"
    and tonumber(large.text[2]) == 18 * 18 and large_twin, serpent.line(large.text))

  local stray = drawn_for_others(known, player)
  check("preview.only-the-dragging-player", stray == nil, stray)

  check("preview.active", drag_preview.active(player.index), "not active mid-drag")
  drag_preview.on_cancelled({ player_index = player.index })
  check("preview.cancel.clears", not label.valid and not drag_preview.active(player.index)
    and #rendering.get_all_objects("ltr-test") == objects, "label left behind")
  drag_preview.on_cancelled({ player_index = player.index })

  -- A mod update drops every preview, also one saved by 0.2.1, which kept
  -- its single label under `object`.
  drag_preview.on_changed(drag_event(player, surface, "select", 2.5 * C, 0.5 * C, 2.5 * C, 0.5 * C))
  local old = rendering.draw_text({ text = "0.2.1", surface = surface, target = { 0, 0 }, color = { 1, 1, 1 },
    players = { player } })
  storage.drag_preview[player.index + 1] = { key = "saved by 0.2.1", object = old }
  drag_preview.reset()
  check("preview.reset.clears", not old.valid and not drag_preview.active(player.index)
    and #rendering.get_all_objects("ltr-test") == objects, "label left behind by a mod update")
  check("preview.leaves-everything", snapshot(surface, force) == before, "state changed by a preview")
end

local function time_dry_run(surface, force, label, r, action)
  local profiler = helpers.create_profiler()
  for _ = 1, 10 do dry(surface, force, r, action) end
  profiler.stop()
  profiler.divide(10)
  local cells = (r.x2 - r.x1 + 1) * (r.y2 - r.y1 + 1)
  log({ "", "LTR_TEST INFO dry-run ", label, " ", action, " ", cells, " cells: ", profiler })
end

-- How long a dry run takes as the rectangle grows (ADR-0015's numbers):
-- first over mostly unowned land, then over a block the force owns outright,
-- where a lowering gesture searches every cell for entities.
local function timing(surface, force)
  for _, size in ipairs({ 5, 10, 20, 40 }) do
    time_dry_run(surface, force, "wilderness", rect(-1, -1, size - 2, size - 2), "advance")
  end
  for cy = -10, 9 do
    for cx = -10, 9 do own(surface, force, cx, cy, "trail") end
  end
  for _, size in ipairs({ 5, 10, 20 }) do
    local r = rect(-size / 2, -size / 2, size / 2 - 1, size / 2 - 1)
    if size == 5 then r = rect(-2, -2, 2, 2) end
    for _, action in ipairs({ "advance", "deed", "downgrade", "release" }) do
      time_dry_run(surface, force, "owned", r, action)
    end
  end
end

script.on_init(function() registry.init_storage() end)
script.on_event(custom_events.on_cell_claimed, function() raised = raised + 1 end)
script.on_event(custom_events.on_cell_downgraded, function() raised = raised + 1 end)

script.on_event(defines.events.on_tick, function(event)
  if event.tick ~= RUN_TICK then return end
  local surface = game.surfaces.nauvis
  local force = game.forces.player
  registry.init_surface(surface.index)
  dry_run_cases(surface, force)
  -- A player exists in the game's test mode only (2.1.24 and newer).
  local player = game.get_player(1)
  if player then
    preview_cases(player, surface, force)
  else
    log("LTR_TEST INFO no player on this engine: preview cases skipped")
  end
  timing(surface, force)
  log("LTR_TEST DONE")
  -- Ends the run at once in test mode; engines before 2.1.24 have no such
  -- function and throw on the lookup, and the run simply ticks out there.
  pcall(function() script.finish_test(failures == 0) end)
end)
