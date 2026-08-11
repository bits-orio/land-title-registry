-- Thin event dispatcher: wires events to the modules under scripts/ and
-- contains no logic itself. Land Title Registry registers no unconditional on_tick;
-- the two temporary on_nth_tick handlers (rebuild queue, hover) are managed
-- by their modules and re-registered from on_load iff their storage says so.

local const = require("scripts.const")
local registry = require("scripts.registry")
local blockers = require("scripts.blockers")
local economy = require("scripts.economy")
local tool = require("scripts.tool")
local tech = require("scripts.tech")
local render = require("scripts.render")
local hud = require("scripts.hud")
local custom_events = require("scripts.custom_events")
local welcome = require("scripts.welcome")
local chronicle = require("scripts.chronicle")
local outposts = require("scripts.outposts")
local mts_compat = require("compat.mts")
local odb_compat = require("compat.odb")
require("scripts.commands")
require("scripts.remote")

-- The engine CACHES chart tiles: charted chunks keep their last-rendered
-- look until recharted, so a change to engine-drawn map visuals never
-- shows on an existing save's map (playtest finding: a map_color tint
-- simply wasn't there). Bump CHART_EPOCH whenever the map-view scheme
-- changes; the mismatch triggers one force.rechart() per force — flushing
-- stale engine-drawn looks — plus a full rebuild so per-cell chart
-- sprites match the current scheme. Runs from both config-changed and the
-- join anchor (a control-only update at the same mod version never fires
-- config-changed).
--
-- Epoch 2: the tint experiments removed; striped chart sprites on every
-- blocker cell, wilderness included.
local CHART_EPOCH = 2

local function ensure_recharted()
  if storage.chart_epoch == CHART_EPOCH then return end
  storage.chart_epoch = CHART_EPOCH
  for _, force in pairs(game.forces) do
    force.rechart()
  end
  blockers.enqueue_full_rebuild()
end

local function init_surface(surface)
  registry.init_surface(surface.index)
  -- Space platforms are exempt from the grid entirely: platform tiles
  -- already constrain building. Under MTS, only team surfaces get the grid
  -- (the landing pen and other special surfaces are not team surfaces);
  -- the on_team_surface_created subscription in compat/mts.lua settles the
  -- creation-order race by re-enabling and rebuilding.
  if surface.platform or (mts_compat.active and mts_compat.should_disable(surface)) then
    storage.disabled_surfaces[surface.index] = true
  end
end

script.on_init(function()
  registry.init_storage()
  for _, surface in pairs(game.surfaces) do
    init_surface(surface)
  end
  for _, force in pairs(game.forces) do
    economy.init_force(force)
  end
  storage.meta.cell_size = const.CELL
  if mts_compat.active then mts_compat.resolve_events() end
  if odb_compat.active then odb_compat.register() end
  -- Blanket any chunks that existed before Land Title Registry did (mid-game install,
  -- scenario-pregenerated maps). Fresh maps enqueue little or nothing.
  blockers.enqueue_full_rebuild()
end)

script.on_load(function()
  blockers.ensure_rebuild_handler()
  tool.ensure_hover_handler()
  if mts_compat.active then mts_compat.resolve_events() end
end)

script.on_configuration_changed(function()
  registry.init_storage()
  -- Ensure per-surface tables WITHOUT re-evaluating enablement: the MTS
  -- grid-only-on-team-surfaces rule applies at fresh-game init and surface
  -- creation only. Re-running it here disabled surfaces that already
  -- carried claims (an MTS-enabled save building on plain nauvis) and the
  -- next rebuild swept their blockers — overlays and grid gone.
  for _, surface in pairs(game.surfaces) do
    registry.init_surface(surface.index)
  end

  -- One-shot self-heal for saves bitten by the above: a disabled,
  -- non-platform surface that holds claims is legitimate Land Title Registry ground —
  -- re-enable and reconcile it back. Flagged so it never fights a
  -- DELIBERATE set_surface_enabled(false) by an integrator later.
  if not storage.disable_healed then
    storage.disable_healed = true
    for surface_index in pairs(storage.disabled_surfaces) do
      local surface = game.surfaces[surface_index]
      if surface and surface.valid and not surface.platform then
        local cells = storage.cells[surface_index]
        if cells and next(cells) then
          storage.disabled_surfaces[surface_index] = nil
          blockers.enqueue_surface_rebuild(surface)
          game.print({ "land-title-registry.surface-healed", surface.name })
        end
      end
    end
  end
  for _, force in pairs(game.forces) do
    economy.init_force(force)
  end

  -- The registry is keyed by cell coordinates, which are meaningless under a
  -- different cell size — a size change on an existing save cannot be
  -- migrated. Refund every cell's invested points in full and return the
  -- world to Wilderness (ADR-0010).
  local cell_size = const.CELL
  if storage.meta.cell_size ~= nil and storage.meta.cell_size ~= cell_size then
    for _, cells in pairs(storage.cells) do
      for _, rec in pairs(cells) do
        local force = game.forces[rec.force_index]
        if force and force.valid then
          economy.change(force, rec.invested_points, "cell-size-reset")
        end
      end
    end
    for surface_index in pairs(storage.cells) do
      storage.cells[surface_index] = {}
      render.drop_surface(surface_index)
      registry.init_surface(surface_index)
    end
    game.print({ "land-title-registry.cell-size-reset" })
    blockers.enqueue_full_rebuild()
  end
  storage.meta.cell_size = cell_size
  if odb_compat.active then odb_compat.register() end
  -- Retrofit sweep: players already in the world when the starter-grant
  -- feature (or a newer form of it) arrives get their grant on upgrade.
  for _, player in pairs(game.connected_players) do
    tech.on_player_joined({ player_index = player.index })
  end
  -- Deeds that predate the chronicle enter it from the registry; a batched
  -- rebuild redraws everything (reconcile draws chronicle text too).
  storage.chronicle_backfilled = true
  if chronicle.backfill() > 0 then
    blockers.enqueue_full_rebuild()
  end

  -- Schema v2: border lines moved from shared per-force render objects to
  -- per-player objects (per-user style settings), and outpost accounting
  -- arrived. Old render arrays mix lines and stakes — drop everything and
  -- re-derive through the batched rebuild. Origins retrofit: the oldest
  -- claim per (force, surface) becomes the mainland anchor.
  if (storage.meta.version or 1) < 2 then
    storage.meta.version = 2
    for surface_index in pairs(storage.renders) do
      render.drop_surface(surface_index)
    end
    for surface_index, cells in pairs(storage.cells) do
      local oldest = {}
      for cell_key, rec in pairs(cells) do
        local tick = rec.claimed_tick or 0
        local current = oldest[rec.force_index]
        if not current or tick < current.tick then
          oldest[rec.force_index] = { key = cell_key, tick = tick }
        end
      end
      for force_index, entry in pairs(oldest) do
        storage.origins[force_index] = storage.origins[force_index] or {}
        storage.origins[force_index][surface_index] = entry.key
      end
    end
    blockers.enqueue_full_rebuild()
  end
  ensure_recharted()
end)

-- World lifecycle
script.on_event(defines.events.on_chunk_generated, blockers.on_chunk_generated)
script.on_event(defines.events.on_object_destroyed, blockers.on_object_destroyed)

script.on_event(defines.events.on_surface_created, function(event)
  init_surface(game.surfaces[event.surface_index])
end)

script.on_event(defines.events.on_surface_cleared, function(event)
  registry.drop_surface_claims(event.surface_index)
  render.drop_surface(event.surface_index)
  chronicle.drop_surface(event.surface_index)
end)

script.on_event(defines.events.on_surface_deleted, function(event)
  render.drop_surface(event.surface_index)
  chronicle.drop_surface(event.surface_index)
  registry.drop_surface(event.surface_index)
end)

-- Force lifecycle
script.on_event(defines.events.on_force_created, function(event)
  economy.init_force(event.force)
end)

script.on_event(defines.events.on_forces_merged, function(event)
  -- Charters union FIRST so the survivor cannot re-farm chartered planets.
  tech.merge_charters(event.source_index, event.destination.index)
  welcome.on_forces_merged(event)
  chronicle.on_forces_merged(event)
  economy.on_forces_merged(event)
  -- Rebuilding reconciles both blockers (idempotent) and renders, whose
  -- forces filters and colors must move to the surviving force.
  blockers.enqueue_full_rebuild()
end)

-- Research income; outpost techs grant slots (not points), so their HUD
-- line refreshes here rather than through on_points_changed.
script.on_event(defines.events.on_research_finished, function(event)
  tech.on_research_finished(event)
  if string.find(event.research.name, "^ltr%-outpost%-grants%-") then
    hud.refresh_force(event.research.force)
  end
end)
script.on_event(defines.events.on_research_reversed, function(event)
  tech.on_research_reversed(event)
  if string.find(event.research.name, "^ltr%-outpost%-grants%-") then
    hud.refresh_force(event.research.force)
  end
end)

-- Survey tool (five gestures; each one's action is per-player remappable).
-- Super-forced selection (Ctrl+Shift-drag) is a 2.1 engine feature: on 2.0
-- the define is nil and the gesture is inert — the 2.0.x path to a Rampart
-- jump is remapping another gesture via the ltr-gesture-* settings. The
-- prototype-side super_forced_select is silently ignored there (verified
-- against 2.0.77), so one code base serves both.
script.on_event(defines.events.on_player_selected_area, tool.on_selected)
script.on_event(defines.events.on_player_alt_selected_area, tool.on_alt_selected)
if defines.events.on_player_super_forced_selected_area then
  script.on_event(defines.events.on_player_super_forced_selected_area, tool.on_super_forced_selected)
end
script.on_event(defines.events.on_player_reverse_selected_area, tool.on_reverse_selected)
script.on_event(defines.events.on_player_alt_reverse_selected_area, tool.on_alt_reverse_selected)
script.on_event(defines.events.on_player_cursor_stack_changed, tool.on_cursor_changed)

-- Players (charter presence, HUD, label refresh; on_player_changed_force is
-- non-negotiable — MTS moves players between forces routinely)
script.on_event(defines.events.on_player_created, function(event)
  tech.on_player_created(event)
  hud.on_player_created(event)
  welcome.on_player_created(event)
end)
script.on_event(defines.events.on_gui_click, function(event)
  welcome.on_gui_click(event)
  outposts.on_gui_click(event)
end)
script.on_event(defines.events.on_gui_closed, outposts.on_gui_closed)
script.on_event(defines.events.on_player_joined_game, function(event)
  hud.on_player_joined(event)
  tech.on_player_joined(event)
  welcome.on_player_joined(event)
  -- Border lines are per player (per-user style settings); a joining
  -- player's set is derived fresh from the registry.
  local joined = game.get_player(event.player_index)
  if joined and joined.valid then render.rebuild_player(joined) end
  -- One-shot chronicle backfill, anchored to a join rather than only to
  -- on_configuration_changed: a control-only code update at the same mod
  -- version never fires config-changed, so dev-loop saves would miss it.
  if not storage.chronicle_backfilled then
    storage.chronicle_backfilled = true
    if chronicle.backfill() > 0 then
      blockers.enqueue_full_rebuild()
    end
  end
  -- Per-surface chronicle groups whose surface now resolves to a planet
  -- (the mts-v1 provider arriving after entries recorded) merge into the
  -- planet group; a rebuild redraws standings. One-shot.
  if not storage.chronicle_purged then
    storage.chronicle_purged = true
    if chronicle.purge_non_competitors() > 0 then
      blockers.enqueue_full_rebuild()
    end
  end
  if not storage.chronicle_regrouped then
    storage.chronicle_regrouped = true
    if chronicle.regroup() > 0 then
      blockers.enqueue_full_rebuild()
    end
  end
  -- One-shot map-overlay backfill, join-anchored like the above: interior
  -- claimed cells owned no render objects before chart overlays existed,
  -- and a control-only update at the same mod version never fires
  -- config-changed.
  if not storage.chart_overlays_backfilled then
    storage.chart_overlays_backfilled = true
    blockers.enqueue_full_rebuild()
  end
  ensure_recharted()
  -- Same join anchor for the disabled-surface heal (see config-changed).
  if not storage.disable_healed then
    storage.disable_healed = true
    for surface_index in pairs(storage.disabled_surfaces) do
      local surface = game.surfaces[surface_index]
      if surface and surface.valid and not surface.platform then
        local cells = storage.cells[surface_index]
        if cells and next(cells) then
          storage.disabled_surfaces[surface_index] = nil
          blockers.enqueue_surface_rebuild(surface)
          game.print({ "land-title-registry.surface-healed", surface.name })
        end
      end
    end
  end
end)
script.on_event(defines.events.on_player_changed_surface, tech.on_player_changed_surface)
script.on_event(defines.events.on_player_changed_force, function(event)
  tool.on_player_changed_force(event)
  tech.on_player_changed_force(event)
  hud.on_player_changed_force(event)
  -- The player's border lines belong to their force; re-derive them.
  local player = game.get_player(event.player_index)
  if player and player.valid then render.rebuild_player(player) end
end)
script.on_event(defines.events.on_player_left_game, function(event)
  tool.on_player_gone(event)
  render.drop_player(event.player_index)
end)
script.on_event(defines.events.on_player_removed, function(event)
  tool.on_player_gone(event)
  render.drop_player(event.player_index)
  outposts.on_player_removed(event)
end)

-- Settings: HUD visibility per player; planet-color changes re-render
-- everything through the batched rebuild queue, never in one tick;
-- per-player border style rebuilds just that player's lines.
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  hud.on_setting_changed(event)
  if string.find(event.setting, "^ltr%-color%-") then
    blockers.enqueue_full_rebuild()
  end
  if string.find(event.setting, "^ltr%-border%-") and event.player_index then
    local player = game.get_player(event.player_index)
    if player and player.valid then render.rebuild_player(player) end
  end
end)

-- Land Title Registry's own custom events double as internal refresh triggers.
script.on_event(custom_events.on_points_changed, function(event)
  tool.on_points_changed(event)
  hud.on_points_changed(event)
  if odb_compat.active then odb_compat.on_points_changed(event) end
end)
script.on_event(custom_events.on_cell_claimed, function(event)
  local surface = game.surfaces[event.surface_index]
  if surface and surface.valid then
    render.refresh_around(surface, event.cell_pos.x, event.cell_pos.y)
  end
  welcome.on_cell_claimed(event)
  chronicle.on_cell_claimed(event)
  if odb_compat.active then odb_compat.on_cell_claimed(event) end
end)
script.on_event(custom_events.on_cell_downgraded, function(event)
  local surface = game.surfaces[event.surface_index]
  if surface and surface.valid then
    render.refresh_around(surface, event.cell_pos.x, event.cell_pos.y)
  end
  -- A released cell passes its outpost record / mainland origin to a
  -- neighbouring owned cell.
  outposts.on_cell_downgraded(event)
end)
