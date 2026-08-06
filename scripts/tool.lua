-- Survey-tool UX: selection-event handling, batch feedback (sounds, flying
-- text), the cursor balance label, and hover feedback via a tick handler
-- scoped to tool holders (ADR-0005 — registered only while at least one
-- player holds the tool; an idle game pays nothing).

local const = require("scripts.const")
local registry = require("scripts.registry")
local economy = require("scripts.economy")
local claims = require("scripts.claims")
local chronicle = require("scripts.chronicle")

local tool = {}

local TOOL_NAME = "fh-survey-tool"
local HOVER_TICK_INTERVAL = 10

local SOUND_CLAIM = "fh-sound-claim"
local SOUND_DENY = "fh-sound-deny"
local SOUND_REFUND = "fh-sound-refund"

local LABEL_OK = { r = 1, g = 1, b = 1 }
local LABEL_SHORT = { r = 1, g = 0.35, b = 0.35 }

local function holding_tool(player)
  local stack = player.cursor_stack
  return stack ~= nil and stack.valid_for_read and stack.name == TOOL_NAME
end

-- Cursor-stack writes are guarded by value comparison: a write to the stack
-- while the player is mid-drag can cancel the selection, so never touch the
-- stack unless the value actually changed.
local function update_label(player)
  if not holding_tool(player) then return end
  local stack = player.cursor_stack
  local text = economy.format(economy.get(player.force.index)) .. " Land points"
  if stack.label ~= text then stack.label = text end
end

local function set_label_color(stack, color)
  local current = stack.label_color
  if current
    and math.abs(current.r - color.r) < 0.01
    and math.abs(current.g - color.g) < 0.01
    and math.abs(current.b - color.b) < 0.01 then
    return
  end
  stack.label_color = color
end

-- ---------------------------------------------------------------------------
-- Selection handling

local function rect_from_area(area)
  return {
    x1 = math.floor(area.left_top.x / const.CELL),
    y1 = math.floor(area.left_top.y / const.CELL),
    x2 = math.floor(area.right_bottom.x / const.CELL),
    y2 = math.floor(area.right_bottom.y / const.CELL),
  }
end

local function feedback(player, action, result)
  if result.denied then
    player.play_sound({ path = SOUND_DENY })
    local text
    if result.denied == "points" then
      text = {
        "freehold.insufficient-points",
        economy.format(result.need),
        economy.format(result.have),
        economy.format(result.need - result.have),
      }
    elseif result.denied == "anchor" then
      text = { "freehold.no-adjacency" }
    else
      text = { "freehold.surface-disabled" }
    end
    player.create_local_flying_text({ text = text, create_at_cursor = true })
    return
  end

  if result.applied == 0 then
    -- Multi-cell batches no-op silently per spec; a single-cell click gets
    -- a quiet explanation when claims.lua supplied one.
    if result.hint then
      player.create_local_flying_text({
        text = { "freehold.hint-" .. result.hint },
        create_at_cursor = true,
      })
    end
    return
  end

  if action == "downgrade" then
    player.play_sound({ path = SOUND_REFUND })
    player.create_local_flying_text({
      text = { "freehold.batch-refunded", economy.format(result.refund) },
      create_at_cursor = true,
    })
  else
    player.play_sound({ path = SOUND_CLAIM })
    player.create_local_flying_text({
      text = { "freehold.batch-claimed", economy.format(result.cost) },
      create_at_cursor = true,
    })
  end
  update_label(player)
end

-- Force-chat claim announcements (fh-print-claims, default on): the acting
-- player, the action, cell count, cost or refund, and a clickable GPS tag at
-- the batch center. force.print lands in the MTS team channel automatically
-- when MTS is present, and ODB does not relay it — both by construction.
local function colored_name(player)
  local c = player.chat_color
  return string.format("[color=%.3f,%.3f,%.3f]%s[/color]", c.r, c.g, c.b, player.name)
end

-- ONE chat line per drag (playtest call: two lines per unlock was noise).
-- Carries team (in team color, with leader), who acted, what changed,
-- where, and the cost — plus a record clause only when the batch actually
-- set a record. Placing 2nd or 3rd says nothing.
local function announce(player, surface, rect, action, result)
  if not settings.global["fh-print-claims"].value then return end
  -- Denied results carry no `applied` at all — {denied = "anchor"} — so the
  -- nil must be handled explicitly, not just the zero.
  if result.denied or not result.applied or result.applied == 0 then return end

  local gps = string.format("[gps=%d,%d,%s]",
    (rect.x1 + rect.x2 + 1) / 2 * const.CELL,
    (rect.y1 + rect.y2 + 1) / 2 * const.CELL, surface.name)
  local amount = economy.format(action == "downgrade" and result.refund or result.cost)

  local notable = chronicle.take_notable()
  local record = ""
  if notable then
    local coords = string.format("(%d,%d)", notable.cell_pos.x, notable.cell_pos.y)
    record = notable.kind == "first"
      and { "freehold.record-first", coords }
      or { "freehold.record-fastest", coords,
           chronicle.team_label(notable.beat_force) }
  end

  player.force.print({
    action == "downgrade" and "freehold.announce-lower" or "freehold.announce-raise",
    chronicle.team_tag(player.force.name),
    colored_name(player),
    result.applied,
    amount,
    record,
    gps,
  })
end

local function handle_selection(action, event)
  if event.item ~= TOOL_NAME then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local surface = event.surface
  if not (surface and surface.valid) then return end

  local rect = rect_from_area(event.area)
  chronicle.begin_batch()
  local result = claims.apply_batch(surface, player.force, player, rect, action)
  feedback(player, action, result)
  announce(player, surface, rect, action, result)
end

-- The advertised interaction is two gestures (ADR-0011): drag raises every
-- covered cell one rung, right-drag lowers one rung. The Shift variants are
-- unadvertised accelerators that jump with full credit — the economy's
-- path-independence makes stepping and jumping cost the same.
function tool.on_selected(event) handle_selection("advance", event) end
function tool.on_alt_selected(event) handle_selection("deed", event) end
function tool.on_reverse_selected(event) handle_selection("downgrade", event) end
function tool.on_alt_reverse_selected(event) handle_selection("rampart", event) end

-- ---------------------------------------------------------------------------
-- Hover feedback: a short-interval on_nth_tick registered only while at
-- least one player holds the tool. Resolves the hovered cell from the
-- selected entity when there is one (low-priority blockers are still
-- selected over empty ground) and the player position otherwise.

local function show_hover(player, surface, cx, cy)
  if storage.disabled_surfaces[surface.index] then return end
  local rec = registry.get(surface.index, registry.cell_key(cx, cy))
  local text
  if rec and rec.force_index ~= player.force.index then
    local owner = game.forces[rec.force_index]
    text = { "freehold.hover-other-force",
      owner and chronicle.team_label(owner.name) or "?" }
  else
    local state = rec and rec.state or "wilderness"
    text = { "freehold.hover-" .. state }
  end
  player.create_local_flying_text({
    text = text,
    position = { x = cx * const.CELL + const.CELL / 2, y = cy * const.CELL + const.CELL / 2 },
    time_to_live = 120,
  })
end

local function hover_tick()
  for player_index in pairs(storage.tool_holders) do
    local player = game.get_player(player_index)
    if player and player.valid and player.connected and holding_tool(player) then
      local surface = player.surface
      local selected = player.selected
      local pos = (selected and selected.valid) and selected.position or player.position
      local cx = math.floor(pos.x / const.CELL)
      local cy = math.floor(pos.y / const.CELL)
      local hover_id = surface.index .. ":" .. registry.cell_key(cx, cy)

      if storage.hover[player_index] ~= hover_id then
        storage.hover[player_index] = hover_id
        show_hover(player, surface, cx, cy)
      end

      -- Red label when the balance cannot cover the hovered cell's next-tier
      -- step; Deed cells have no next step.
      local state = registry.state_of(surface.index, registry.cell_key(cx, cy))
      local next_cost = const.NEXT_STEP_COST[state]
      local short = next_cost ~= nil and economy.get(player.force.index) < next_cost
      set_label_color(player.cursor_stack, short and LABEL_SHORT or LABEL_OK)
    end
  end
end

-- Registration must be reproducible from storage alone: called after holder
-- changes and from on_load.
function tool.ensure_hover_handler()
  if next(storage.tool_holders) then
    script.on_nth_tick(HOVER_TICK_INTERVAL, hover_tick)
  else
    script.on_nth_tick(HOVER_TICK_INTERVAL, nil)
  end
end

function tool.on_cursor_changed(event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  if holding_tool(player) then
    storage.tool_holders[player.index] = true
    update_label(player)
  else
    storage.tool_holders[player.index] = nil
    storage.hover[player.index] = nil
  end
  tool.ensure_hover_handler()
end

function tool.on_player_gone(event)
  storage.tool_holders[event.player_index] = nil
  storage.hover[event.player_index] = nil
  tool.ensure_hover_handler()
end

-- HUD refresh triggers (the mod-gui HUD itself is M3; the cursor label is
-- M1's balance surface). on_player_changed_force is non-negotiable — MTS
-- moves players between forces as a normal part of team flows.
function tool.on_player_changed_force(event)
  local player = game.get_player(event.player_index)
  if player and player.valid then update_label(player) end
end

function tool.on_points_changed(event)
  for player_index in pairs(storage.tool_holders) do
    local player = game.get_player(player_index)
    if player and player.valid and player.force.name == event.force_name then
      update_label(player)
    end
  end
end

return tool
