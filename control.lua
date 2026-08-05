-- Thin event dispatcher: wires events to the modules under scripts/ and
-- contains no logic itself. Freehold registers no unconditional on_tick;
-- the two temporary on_nth_tick handlers (rebuild queue, hover) are managed
-- by their modules and re-registered from on_load iff their storage says so.

local registry = require("scripts.registry")
local blockers = require("scripts.blockers")
local economy = require("scripts.economy")
local tool = require("scripts.tool")
local custom_events = require("scripts.custom_events")
require("scripts.commands")
require("scripts.remote")

local function init_surface(surface)
  registry.init_surface(surface.index)
  -- Space platforms are exempt from the grid entirely: platform tiles
  -- already constrain building.
  if surface.platform then
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
  -- Blanket any chunks that existed before Freehold did (mid-game install,
  -- scenario-pregenerated maps). Fresh maps enqueue little or nothing.
  blockers.enqueue_full_rebuild()
end)

script.on_load(function()
  blockers.ensure_rebuild_handler()
  tool.ensure_hover_handler()
end)

script.on_configuration_changed(function()
  registry.init_storage()
  for _, surface in pairs(game.surfaces) do
    init_surface(surface)
  end
  for _, force in pairs(game.forces) do
    economy.init_force(force)
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
end)

script.on_event(defines.events.on_surface_deleted, function(event)
  registry.drop_surface(event.surface_index)
end)

-- Force lifecycle
script.on_event(defines.events.on_force_created, function(event)
  economy.init_force(event.force)
end)

script.on_event(defines.events.on_forces_merged, economy.on_forces_merged)

-- Survey tool
script.on_event(defines.events.on_player_selected_area, tool.on_selected)
script.on_event(defines.events.on_player_alt_selected_area, tool.on_alt_selected)
script.on_event(defines.events.on_player_reverse_selected_area, tool.on_reverse_selected)
script.on_event(defines.events.on_player_alt_reverse_selected_area, tool.on_alt_reverse_selected)
script.on_event(defines.events.on_player_cursor_stack_changed, tool.on_cursor_changed)

-- Players
script.on_event(defines.events.on_player_changed_force, tool.on_player_changed_force)
script.on_event(defines.events.on_player_left_game, tool.on_player_gone)
script.on_event(defines.events.on_player_removed, tool.on_player_gone)

-- Freehold's own custom events double as internal refresh triggers.
script.on_event(custom_events.on_points_changed, tool.on_points_changed)
