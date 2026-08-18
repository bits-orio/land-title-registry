-- Survey-tool UX: selection-event handling, batch feedback (sounds, flying
-- text), the cursor balance label, and hover feedback via a tick handler
-- scoped to tool holders (ADR-0005 — registered only while at least one
-- player holds the tool; an idle game pays nothing).

local const = require("scripts.const")
local registry = require("scripts.registry")
local economy = require("scripts.economy")
local claims = require("scripts.claims")
local chronicle = require("scripts.chronicle")
local outposts = require("scripts.outposts")

local tool = {}

local TOOL_NAME = "ltr-survey-tool"
local RAMPART_TOOL_NAME = "ltr-survey-tool-rampart"
local HOVER_TICK_INTERVAL = 10

local SOUND_CLAIM = "ltr-sound-claim"
local SOUND_DENY = "ltr-sound-deny"
local SOUND_REFUND = "ltr-sound-refund"

local LABEL_OK = { r = 1, g = 1, b = 1 }
local LABEL_SHORT = { r = 1, g = 0.35, b = 0.35 }

local function holding_tool(player)
  local stack = player.cursor_stack
  return stack ~= nil and stack.valid_for_read
    and (stack.name == TOOL_NAME or stack.name == RAMPART_TOOL_NAME)
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
        "land-title-registry.insufficient-points",
        economy.format(result.need),
        economy.format(result.have),
        economy.format(result.need - result.have),
      }
    elseif result.denied == "anchor" then
      text = { "land-title-registry.no-adjacency" }
    else
      text = { "land-title-registry.surface-disabled" }
    end
    player.create_local_flying_text({ text = text, create_at_cursor = true })
    return
  end

  if result.applied == 0 then
    -- Multi-cell batches no-op silently per spec; a single-cell click gets
    -- a quiet explanation when claims.lua supplied one.
    if result.hint then
      player.create_local_flying_text({
        text = { "land-title-registry.hint-" .. result.hint },
        create_at_cursor = true,
      })
    end
    return
  end

  if action == "downgrade" or action == "release" then
    player.play_sound({ path = SOUND_REFUND })
    player.create_local_flying_text({
      text = { "land-title-registry.batch-refunded", economy.format(result.refund) },
      create_at_cursor = true,
    })
  else
    player.play_sound({ path = SOUND_CLAIM })
    player.create_local_flying_text({
      text = { "land-title-registry.batch-claimed", economy.format(result.cost) },
      create_at_cursor = true,
    })
  end
  update_label(player)
end

-- Force-chat claim announcements (ltr-print-claims, default on): the acting
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
  if not settings.global["ltr-print-claims"].value then return end
  -- Denied results carry no `applied` at all — {denied = "anchor"} — so the
  -- nil must be handled explicitly, not just the zero.
  if result.denied or not result.applied or result.applied == 0 then return end

  local lowering = action == "downgrade" or action == "release"
  local gps = string.format("[gps=%d,%d,%s]",
    (rect.x1 + rect.x2 + 1) / 2 * const.CELL,
    (rect.y1 + rect.y2 + 1) / 2 * const.CELL, surface.name)
  local amount = economy.format(lowering and result.refund or result.cost)

  local notable = chronicle.take_notable()
  local record = ""
  if notable then
    local coords = string.format("(%d,%d)", notable.cell_pos.x, notable.cell_pos.y)
    record = notable.kind == "first"
      and { "land-title-registry.record-first", coords }
      or { "land-title-registry.record-fastest", coords,
           chronicle.team_label(notable.beat_force) }
  end

  player.force.print({
    lowering and "land-title-registry.announce-lower" or "land-title-registry.announce-raise",
    chronicle.team_tag(player.force.name),
    colored_name(player),
    result.applied,
    amount,
    record,
    gps,
  })
end

-- Gesture grammar (playtest rework): right is the exact mirror of left.
-- Drag raises one rung, right-drag lowers one; Shift jumps to the top
-- (Deed), Shift-right jumps to the bottom (sell everything back to
-- Wilderness); Ctrl+Shift is the middle jump (Rampart). Each gesture's
-- ACTION is per-player remappable through the ltr-gesture-* settings —
-- the claims-side vocabulary is the setting value translated here.
local ACTION_OF = {
  ["raise-one"] = "advance",
  ["jump-deed"] = "deed",
  ["jump-rampart"] = "rampart",
  ["lower-one"] = "downgrade",
  ["release-all"] = "release",
}

-- The Rampart variant tool is fixed-function (its whole point is a
-- dependable Rampart jump on plain drag); the other gestures mirror the
-- main tool's defaults so muscle memory transfers.
local RAMPART_TOOL_ACTION = {
  ["ltr-gesture-drag"] = "rampart",
  ["ltr-gesture-shift-drag"] = "deed",
  ["ltr-gesture-ctrl-shift-drag"] = "rampart",
  ["ltr-gesture-right-drag"] = "downgrade",
  ["ltr-gesture-shift-right-drag"] = "release",
}

local LOWERING = { downgrade = true, release = true }
local LOWER_FRAME = "ltr_lower_confirm_frame"

-- Apply a batch with full player feedback — the shared tail of the direct
-- path and the confirmed-lowering path.
local function apply_with_feedback(player, surface, rect, action)
  chronicle.begin_batch()
  local result = claims.apply_batch(surface, player.force, player, rect, action)
  feedback(player, action, result)
  announce(player, surface, rect, action, result)
  if result.applied and result.applied > 0 and not LOWERING[action] then
    outposts.reconcile(player.force)
  end
  return result
end

local function close_lower_confirm(player)
  storage.lower_pending[player.index] = nil
  local frame = player.gui.screen[LOWER_FRAME]
  if frame then frame.destroy() end
end

-- Lowering gestures confirm before they act (playtest call: an accidental
-- right-drag refunds only a fraction of the invested points, and nothing
-- said so until it had happened). The preview runs the real evaluation as
-- a dry run, so the dialog shows the actual cell count and refund.
-- ltr-confirm-lowering (per-player, default on) disables it for veterans.
local function open_lower_confirm(player, surface, rect, action, preview)
  close_lower_confirm(player)
  storage.lower_pending[player.index] = {
    surface_index = surface.index,
    rect = rect,
    action = action,
  }
  local frame = player.gui.screen.add({
    type = "frame",
    name = LOWER_FRAME,
    direction = "vertical",
    caption = { "land-title-registry.lower-title" },
  })
  frame.auto_center = true
  frame.add({ type = "label", name = "l1", caption = {
    action == "release" and "land-title-registry.lower-line-release"
      or "land-title-registry.lower-line-downgrade",
    preview.applied,
    economy.format(preview.refund),
  } })
  local l2 = frame.add({ type = "label", name = "l2",
    caption = { "land-title-registry.lower-line-2", economy.refund_percent() } })
  l2.style.single_line = false
  l2.style.maximal_width = 400
  local buttons = frame.add({ type = "flow", name = "buttons" })
  buttons.style.horizontal_spacing = 12
  buttons.add({ type = "button", name = "ltr_lower_confirm", style = "confirm_button",
    caption = { "land-title-registry.lower-confirm" } })
  buttons.add({ type = "button", name = "ltr_lower_cancel",
    caption = { "land-title-registry.lower-cancel" } })
  player.opened = frame
end

function tool.on_gui_click(event)
  local element = event.element
  if not (element and element.valid) then return end
  -- Read the name BEFORE closing: the button lives inside the frame the
  -- close destroys, and a destroyed element throws on every access
  -- (playtest crash).
  local name = element.name
  if name ~= "ltr_lower_confirm" and name ~= "ltr_lower_cancel" then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local pending = storage.lower_pending[player.index]
  close_lower_confirm(player)
  if name ~= "ltr_lower_confirm" or not pending then return end
  local surface = game.surfaces[pending.surface_index]
  if not (surface and surface.valid) then return end
  -- The world may have shifted while the dialog sat open; the apply
  -- re-evaluates from scratch, so the outcome is honest even if it now
  -- differs from the preview.
  apply_with_feedback(player, surface, pending.rect, pending.action)
end

function tool.on_gui_closed(event)
  local element = event.element
  if element and element.valid and element.name == LOWER_FRAME then
    local player = game.get_player(event.player_index)
    if player and player.valid then close_lower_confirm(player) end
  end
end

local function handle_selection(gesture_setting, event)
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local surface = event.surface
  if not (surface and surface.valid) then return end
  local action
  if event.item == TOOL_NAME then
    action = ACTION_OF[player.mod_settings[gesture_setting].value] or "advance"
  elseif event.item == RAMPART_TOOL_NAME then
    action = RAMPART_TOOL_ACTION[gesture_setting]
  else
    return
  end

  local rect = rect_from_area(event.area)

  if LOWERING[action] and player.mod_settings["ltr-confirm-lowering"].value then
    local preview = claims.apply_batch(surface, player.force, player, rect, action, { dry_run = true })
    if preview.applied and preview.applied > 0 then
      open_lower_confirm(player, surface, rect, action, preview)
      return
    end
    -- Nothing would change: fall through so the normal path delivers the
    -- denied/hint feedback instead of a pointless dialog.
  end

  chronicle.begin_batch()
  local result = claims.apply_batch(surface, player.force, player, rect, action)

  -- An anchor-denied Deed jump on a single Wilderness cell may instead be
  -- an outpost founding — offered through a confirmation dialog, never
  -- applied from the drag itself (slots are hard-earned; an accidental
  -- gesture must not spend one).
  if result.denied == "anchor" and action == "deed"
    and outposts.try_offer(player, surface, rect, player.force) then
    return
  end

  feedback(player, action, result)
  announce(player, surface, rect, action, result)

  -- Territory changed: an outpost region may now reach the mainland. Once
  -- per batch, never per cell (the reconcile BFS is region-bounded).
  if result.applied and result.applied > 0 then
    outposts.reconcile(player.force)
  end
end

function tool.on_selected(event) handle_selection("ltr-gesture-drag", event) end
function tool.on_alt_selected(event) handle_selection("ltr-gesture-shift-drag", event) end
function tool.on_super_forced_selected(event) handle_selection("ltr-gesture-ctrl-shift-drag", event) end
function tool.on_reverse_selected(event) handle_selection("ltr-gesture-right-drag", event) end
function tool.on_alt_reverse_selected(event) handle_selection("ltr-gesture-shift-right-drag", event) end

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
    text = { "land-title-registry.hover-other-force",
      owner and chronicle.team_label(owner.name) or "?" }
  else
    local state = rec and rec.state or "wilderness"
    text = { "land-title-registry.hover-" .. state }
  end
  player.create_local_flying_text({
    text = text,
    position = { x = cx * const.CELL + const.CELL / 2, y = cy * const.CELL + const.CELL / 2 },
    time_to_live = 120,
  })

  -- The cell's record, on demand: map view hides standings at distance,
  -- so hovering has to answer "who holds this?" without a zoom.
  local leader, count = chronicle.leader_of(surface, cx, cy)
  if leader then
    player.create_local_flying_text({
      text = { "land-title-registry.hover-record",
        chronicle.team_label(leader.force_name),
        chronicle.format_clock(leader.clock), count },
      position = { x = cx * const.CELL + const.CELL / 2,
        y = cy * const.CELL + const.CELL / 2 + 1.4 },
      time_to_live = 120,
    })
  end
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
  if storage.tool_holders and next(storage.tool_holders) then
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
  storage.lower_pending[event.player_index] = nil
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
