-- Outpost accounting and the found-an-outpost confirmation dialog.
--
-- An outpost is a Deed claimed with no adjacency: a single Wilderness cell,
-- founded through an explicit confirmation dialog (slots are hard-earned;
-- an accidental drag must never spend one — playtest call), costing the
-- normal Deed price plus one of the force's outpost slots.
--
-- Slots come from the ltr-outpost-grants technology chain — one per
-- researched level — and are OCCUPIED, not consumed. A slot frees when its
-- outpost's territory grows to reach the force's mainland origin on that
-- surface (BFS over owned cells), permanently. When an outpost's own cell
-- is downgraded away, the record moves to an adjacent owned cell (the
-- region the outpost seeded still hangs off the slot) and is dropped only
-- when no region remains.
--
-- The mainland origin per (force, surface) is the force's first claim
-- there, recorded by claims.note_origin; it inherits to a neighbour the
-- same way when its cell is released.

local const = require("scripts.const")
local registry = require("scripts.registry")
local economy = require("scripts.economy")
local claims = require("scripts.claims")
local chronicle = require("scripts.chronicle")

local outposts = {}

local FRAME_NAME = "ltr_outpost_confirm_frame"
local SOUND_CLAIM = "ltr-sound-claim"
local SOUND_DENY = "ltr-sound-deny"

local NEIGHBOURS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

local function records_of(force_index)
  storage.outposts[force_index] = storage.outposts[force_index] or {}
  return storage.outposts[force_index]
end

-- Researched outpost level = slot cap. The chain is sequential, so counting
-- researched techs and reading the highest level agree.
function outposts.cap(force)
  local cap = 0
  local i = 1
  while true do
    local tech = force.technologies["ltr-outpost-grants-" .. i]
    if not tech then break end
    if tech.researched then cap = cap + 1 end
    i = i + 1
  end
  return cap
end

-- Passive counts (no BFS) for the HUD and the dialog.
function outposts.counts(force)
  return #records_of(force.index), outposts.cap(force)
end

local function adjacent_owned_key(surface_index, force_index, key)
  local cells = storage.cells[surface_index]
  if not cells then return nil end
  local pos = registry.cell_key_to_pos(key)
  for _, d in ipairs(NEIGHBOURS) do
    local nkey = registry.cell_key(pos.x + d[1], pos.y + d[2])
    local rec = cells[nkey]
    if rec and rec.force_index == force_index then return nkey end
  end
  return nil
end

-- BFS from the outpost cell over the force's owned cells, looking for the
-- mainland origin. Cost is bounded by the connected region's size; it runs
-- once per survey batch (tool.lua) and per dialog, never per cell event.
local function reaches_origin(surface_index, force_index, start_key, origin_key)
  if start_key == origin_key then return true end
  local cells = storage.cells[surface_index]
  if not cells then return false end
  local visited = { [start_key] = true }
  local queue = { start_key }
  local head = 1
  while head <= #queue do
    local pos = registry.cell_key_to_pos(queue[head])
    head = head + 1
    for _, d in ipairs(NEIGHBOURS) do
      local nkey = registry.cell_key(pos.x + d[1], pos.y + d[2])
      if not visited[nkey] then
        visited[nkey] = true
        local rec = cells[nkey]
        if rec and rec.force_index == force_index then
          if nkey == origin_key then return true end
          queue[#queue + 1] = nkey
        end
      end
    end
  end
  return false
end

-- Free every record that no longer occupies a slot: cell lost with nothing
-- inherited (surface clears — downgrades move records in-place first), or
-- territory grown to reach the mainland.
function outposts.reconcile(force)
  local force_index = force.index
  local records = records_of(force_index)
  local origins = storage.origins[force_index]
  for i = #records, 1, -1 do
    local r = records[i]
    local cells = storage.cells[r.surface_index]
    local rec = cells and cells[r.cell_key]
    if not (rec and rec.force_index == force_index) then
      table.remove(records, i)
    else
      local origin = origins and origins[r.surface_index]
      if origin and origin ~= r.cell_key
        and reaches_origin(r.surface_index, force_index, r.cell_key, origin) then
        table.remove(records, i)
      end
    end
  end
end

-- A released cell passes its outpost record (and the mainland origin) to an
-- adjacent owned cell; claims.note_origin re-seeds a cleared origin on the
-- force's next claim.
function outposts.on_cell_downgraded(event)
  if event.new_state ~= "wilderness" then return end
  local force = game.forces[event.force_name]
  if not (force and force.valid) then return end
  local surface_index = event.surface_index
  local force_index = force.index
  local key = registry.cell_key(event.cell_pos.x, event.cell_pos.y)

  local records = records_of(force_index)
  for i = #records, 1, -1 do
    local r = records[i]
    if r.surface_index == surface_index and r.cell_key == key then
      local heir = adjacent_owned_key(surface_index, force_index, key)
      if heir then r.cell_key = heir else table.remove(records, i) end
    end
  end

  local origins = storage.origins[force_index]
  if origins and origins[surface_index] == key then
    origins[surface_index] = adjacent_owned_key(surface_index, force_index, key)
  end
end

-- Recycled team slots start blank (same rule as points and the chronicle).
function outposts.reset_force(force_index)
  storage.outposts[force_index] = nil
  storage.origins[force_index] = nil
end

-- ---------------------------------------------------------------------------
-- Confirmation dialog

function outposts.close(player)
  storage.outpost_pending[player.index] = nil
  local frame = player.gui.screen[FRAME_NAME]
  if frame then frame.destroy() end
end

local function open_confirm(player, surface, cx, cy, used, cap)
  outposts.close(player)
  storage.outpost_pending[player.index] = { surface_index = surface.index, cx = cx, cy = cy }

  local frame = player.gui.screen.add({
    type = "frame",
    name = FRAME_NAME,
    direction = "vertical",
    caption = { "land-title-registry.outpost-title" },
  })
  frame.auto_center = true
  frame.add({ type = "label", name = "l1", caption = {
    "land-title-registry.outpost-line-1",
    string.format("(%d, %d)", cx, cy),
    economy.format(const.TOTAL.deed),
  } })
  frame.add({ type = "label", name = "l2", caption = {
    "land-title-registry.outpost-line-2", used + 1, cap,
  } })
  local l3 = frame.add({ type = "label", name = "l3", caption = { "land-title-registry.outpost-line-3" } })
  l3.style.single_line = false
  l3.style.maximal_width = 400
  local buttons = frame.add({ type = "flow", name = "buttons" })
  buttons.style.horizontal_spacing = 12
  buttons.add({ type = "button", name = "ltr_outpost_confirm", style = "confirm_button",
    caption = { "land-title-registry.outpost-confirm" } })
  buttons.add({ type = "button", name = "ltr_outpost_cancel",
    caption = { "land-title-registry.outpost-cancel" } })
  player.opened = frame
end

-- Offer the dialog for an anchor-denied Deed jump. Returns true when the
-- denial was handled here (dialog opened, or an explanatory message shown);
-- false hands the caller back the plain anchor denial.
function outposts.try_offer(player, surface, rect, force)
  if rect.x1 ~= rect.x2 or rect.y1 ~= rect.y2 then return false end
  local cap = outposts.cap(force)
  if cap == 0 then return false end
  if registry.get(surface.index, registry.cell_key(rect.x1, rect.y1)) then return false end
  outposts.reconcile(force)
  local used = #records_of(force.index)
  if used >= cap then
    player.play_sound({ path = SOUND_DENY })
    player.create_local_flying_text({
      text = { "land-title-registry.outpost-no-slots", used, cap },
      create_at_cursor = true,
    })
    return true
  end
  open_confirm(player, surface, rect.x1, rect.y1, used, cap)
  return true
end

function outposts.on_gui_click(event)
  local element = event.element
  if not (element and element.valid) then return end
  -- Read the name BEFORE closing: the button lives inside the frame the
  -- close destroys, and a destroyed element throws on every access (the
  -- lowering dialog crashed exactly here first).
  local name = element.name
  if name ~= "ltr_outpost_confirm" and name ~= "ltr_outpost_cancel" then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local pending = storage.outpost_pending[player.index]
  outposts.close(player)
  if name ~= "ltr_outpost_confirm" or not pending then return end

  local surface = game.surfaces[pending.surface_index]
  if not (surface and surface.valid) then return end
  local force = player.force

  local function refuse(text)
    player.play_sound({ path = SOUND_DENY })
    player.create_local_flying_text({ text = text, create_at_cursor = true })
  end

  -- Re-validate everything at confirm time: research can reverse, the cell
  -- can be claimed, and territory can shift while the dialog sits open.
  outposts.reconcile(force)
  local used, cap = outposts.counts(force)
  if used >= cap then
    return refuse({ "land-title-registry.outpost-no-slots", used, cap })
  end
  if registry.get(surface.index, registry.cell_key(pending.cx, pending.cy)) then
    return refuse({ "land-title-registry.outpost-cell-taken" })
  end

  local rect = { x1 = pending.cx, y1 = pending.cy, x2 = pending.cx, y2 = pending.cy }
  local result = claims.apply_batch(surface, force, player, rect, "deed", { outpost = true })
  if result.applied and result.applied > 0 then
    local records = records_of(force.index)
    records[#records + 1] = {
      surface_index = surface.index,
      cell_key = registry.cell_key(pending.cx, pending.cy),
    }
    player.play_sound({ path = SOUND_CLAIM })
    player.create_local_flying_text({
      text = { "land-title-registry.outpost-founded", economy.format(result.cost) },
      create_at_cursor = true,
    })
    -- The team-chat audit line the survey gestures print (dialog applies
    -- bypass tool.lua's announce path).
    if settings.global["ltr-print-claims"].value then
      local c = player.chat_color
      force.print({
        "land-title-registry.announce-raise",
        chronicle.team_tag(force.name),
        string.format("[color=%.3f,%.3f,%.3f]%s[/color]", c.r, c.g, c.b, player.name),
        1,
        economy.format(result.cost),
        "",
        string.format("[gps=%d,%d,%s]",
          pending.cx * const.CELL + const.CELL / 2,
          pending.cy * const.CELL + const.CELL / 2, surface.name),
      })
    end
  elseif result.denied == "points" then
    refuse({
      "land-title-registry.insufficient-points",
      economy.format(result.need),
      economy.format(result.have),
      economy.format(result.need - result.have),
    })
  else
    refuse({ "land-title-registry.outpost-cell-taken" })
  end
end

-- Esc while the dialog is player.opened.
function outposts.on_gui_closed(event)
  local element = event.element
  if not (element and element.valid) or element.name ~= FRAME_NAME then return end
  local player = game.get_player(event.player_index)
  if player and player.valid then outposts.close(player) end
end

function outposts.on_player_removed(event)
  storage.outpost_pending[event.player_index] = nil
end

return outposts
