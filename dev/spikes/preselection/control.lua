-- Spike: the pre-selection events of a selection tool
-- (on_player_start_selected_area, on_player_change_selected_area,
-- on_player_cancel_selected_area) and the final selection events. See
-- FINDINGS.md. Every connected player holds the tool; every event is logged
-- as one "SP t=<tick> ev=<name> ..." line that analyze.py groups into drags.
--
-- The live handlers also write synced state on purpose (a counter in
-- storage, a rectangle that follows the drag, a local flying text), so a
-- multiplayer run shows whether the events arrive the same on every peer.
local E = defines.events

local function fmt(a) return a and string.format("(%.2f,%.2f)", a.x or a[1], a.y or a[2]) or "nil" end
local function box(a) return a and (fmt(a.left_top or a[1]) .. "-" .. fmt(a.right_bottom or a[2])) or "nil" end

local mode_names = {}
for name, value in pairs(defines.selection_mode) do mode_names[value] = name end

local function keys(event)
  local list = {}
  for key in pairs(event) do list[#list + 1] = key end
  table.sort(list)
  return table.concat(list, ",")
end

local function dump(name, e)
  local entities, tiles = e.entities and #e.entities or "nil", e.tiles and #e.tiles or "nil"
  local first = ""
  if e.tiles and e.tiles[1] then
    first = " tile1=" .. e.tiles[1].name .. "@" .. e.tiles[1].position.x .. "," .. e.tiles[1].position.y
  end
  log(string.format("SP t=%d ev=%s pi=%s surf=%s area=%s pos=%s cur=%s item=%s q=%s ents=%s tiles=%s mode=%s(%s)%s keys=%s",
    game.tick, name, tostring(e.player_index), e.surface and e.surface.name or "nil", box(e.area), fmt(e.position),
    fmt(e.cursor_position), tostring(e.item), tostring(e.quality), tostring(entities), tostring(tiles),
    tostring(e.selection_mode), mode_names[e.selection_mode] or "?", first, keys(e)))
  -- What reading every element of the tables costs.
  if e.tiles and #e.tiles > 0 or e.entities and #e.entities > 0 then
    local profiler = helpers.create_profiler()
    local sum = 0
    for _, tile in pairs(e.tiles or {}) do sum = sum + tile.position.x end
    for _, entity in pairs(e.entities or {}) do sum = sum + entity.position.x end
    profiler.stop()
    log({ "", "SP t=" .. game.tick .. " ev=" .. name .. " iterate-cost ", profiler })
  end
end

local LIVE = { "on_player_start_selected_area", "on_player_change_selected_area", "on_player_cancel_selected_area" }
local FINAL = {
  "on_player_selected_area", "on_player_alt_selected_area", "on_player_reverse_selected_area",
  "on_player_alt_reverse_selected_area", "on_player_super_forced_selected_area",
}

for _, name in pairs(FINAL) do
  if E[name] then
    script.on_event(E[name], function(e) if e.item == "sel-probe" then dump(name, e) end end)
  else
    log("SP no event " .. name)
  end
end

for _, name in pairs(LIVE) do
  if E[name] then
    script.on_event(E[name], function(e)
      dump(name, e)
      storage.count = (storage.count or 0) + 1
      storage.per = storage.per or {}
      storage.per[name] = (storage.per[name] or 0) + 1
      local changing = name == "on_player_change_selected_area"
      if changing and storage.write_state then
        if storage.rect and storage.rect.valid then storage.rect.destroy() end
        storage.rect = rendering.draw_rectangle { color = { 1, 0, 0, 0.3 }, filled = true,
          left_top = e.area.left_top, right_bottom = e.area.right_bottom, surface = e.surface }
        game.get_player(e.player_index).create_local_flying_text { text = "n=" .. storage.count,
          position = e.cursor_position, time_to_live = 30 }
      end
      if not changing and storage.rect and storage.rect.valid then storage.rect.destroy() end
    end)
  else
    log("SP no event " .. name)
  end
end

local function give_tool(player_index)
  local player = game.get_player(player_index)
  if not player.cursor_stack then
    storage.pending = storage.pending or {}
    storage.pending[player_index] = true
    return
  end
  player.cursor_stack.set_stack { name = "sel-probe" }
  player.zoom = storage.zoom or 1
  log("SP t=" .. game.tick .. " given tool to " .. player_index .. " conn=" .. tostring(player.connected))
end

-- What the prototype and the event ids read as at runtime ("SPV" lines):
-- run.sh proto needs only these.
local function log_prototype()
  local prototype = prototypes.item["sel-probe"]
  for _, m in pairs { "select", "alt_select", "reverse_select", "alt_reverse_select" } do
    local ok, r = pcall(function() return prototype.get_draw_selection_counts(defines.selection_mode[m]) end)
    log("SPV " .. m .. " ok=" .. tostring(ok) .. " r=" .. tostring(r))
  end
  log("SPV events start=" .. tostring(E.on_player_start_selected_area) .. " change=" .. tostring(E.on_player_change_selected_area))
  local ok, r = pcall(function() return prototype.send_pre_selection_events end)
  log("SPV send_pre_selection_events ok=" .. tostring(ok) .. " r=" .. tostring(r))
end

script.on_event(E.on_player_created, function(e) give_tool(e.player_index) end)

script.on_init(function()
  log_prototype()
  if remote.interfaces.freeplay then
    remote.call("freeplay", "set_skip_intro", true)
    remote.call("freeplay", "set_disable_crashsite", true)
  end
  for _, surface in pairs(game.surfaces) do surface.always_day = true end
  storage.write_state = true
  -- A field of chests for the entity modes.
  local surface = game.surfaces.nauvis
  for x = -20, 20, 2 do
    for y = -10, 10, 2 do
      local position = { x + 0.5, y + 0.5 }
      if surface.can_place_entity { name = "wooden-chest", position = position } then
        surface.create_entity { name = "wooden-chest", position = position, force = "player" }
      end
    end
  end
end)

-- Every two seconds: hand the tool back to whoever lost it (Q clears the
-- cursor) and log the synced counters.
script.on_nth_tick(120, function(e)
  for _, player in pairs(game.connected_players) do
    if player.cursor_stack and not player.cursor_stack.valid_for_read then
      player.cursor_stack.set_stack { name = "sel-probe" }
    end
  end
  for player_index in pairs(storage.pending or {}) do
    if game.get_player(player_index).cursor_stack then
      storage.pending[player_index] = nil
      give_tool(player_index)
    end
  end
  log(string.format("SP t=%d STATE count=%s per=%s rect=%s", e.tick, tostring(storage.count),
    serpent.line(storage.per), tostring(storage.rect and storage.rect.valid)))
end)

commands.add_command("spw", "sel-probe: 1 turns the state writes on, anything else off", function(c)
  storage.write_state = (c.parameter == "1")
  log("SP write_state=" .. tostring(storage.write_state))
end)
commands.add_command("spz", "sel-probe: set your zoom", function(c)
  game.get_player(c.player_index).zoom = tonumber(c.parameter)
  log("SP zoom " .. c.parameter)
end)
