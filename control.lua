-- Thin event dispatcher: wires events to the modules under scripts/ and
-- contains no logic itself. Freehold registers no unconditional on_tick;
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
local mts_compat = require("compat.mts")
local odb_compat = require("compat.odb")
require("scripts.commands")
require("scripts.remote")

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
  -- Blanket any chunks that existed before Freehold did (mid-game install,
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
  for _, surface in pairs(game.surfaces) do
    init_surface(surface)
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
    game.print({ "freehold.cell-size-reset" })
    blockers.enqueue_full_rebuild()
  end
  storage.meta.cell_size = cell_size
  if odb_compat.active then odb_compat.register() end
  -- Retrofit sweep: players already in the world when the starter-grant
  -- feature (or a newer form of it) arrives get their grant on upgrade.
  for _, player in pairs(game.connected_players) do
    tech.on_player_joined({ player_index = player.index })
  end

  -- storage.meta.version is 1; migration steps compare against it here as
  -- the schema evolves.
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

-- Research income
script.on_event(defines.events.on_research_finished, tech.on_research_finished)
script.on_event(defines.events.on_research_reversed, tech.on_research_reversed)

-- Survey tool
script.on_event(defines.events.on_player_selected_area, tool.on_selected)
script.on_event(defines.events.on_player_alt_selected_area, tool.on_alt_selected)
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
script.on_event(defines.events.on_gui_click, welcome.on_gui_click)
script.on_event(defines.events.on_player_joined_game, function(event)
  hud.on_player_joined(event)
  tech.on_player_joined(event)
end)
script.on_event(defines.events.on_player_changed_surface, tech.on_player_changed_surface)
script.on_event(defines.events.on_player_changed_force, function(event)
  tool.on_player_changed_force(event)
  tech.on_player_changed_force(event)
  hud.on_player_changed_force(event)
end)
script.on_event(defines.events.on_player_left_game, tool.on_player_gone)
script.on_event(defines.events.on_player_removed, tool.on_player_gone)

-- Settings: HUD visibility per player; border-color changes re-render
-- everything through the batched rebuild queue, never in one tick.
script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  hud.on_setting_changed(event)
  if string.find(event.setting, "^fh%-color%-") then
    blockers.enqueue_full_rebuild()
  end
end)

-- Freehold's own custom events double as internal refresh triggers.
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
end)
