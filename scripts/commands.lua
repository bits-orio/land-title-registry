-- Console commands. /fh-rebuild reconciles the world with the registry — the
-- recovery path for any drift (ADR-0003). Large rebuilds drain through the
-- batched on_nth_tick queue, never in a single tick.

local const = require("scripts.const")
local registry = require("scripts.registry")
local blockers = require("scripts.blockers")
local welcome = require("scripts.welcome")

commands.add_command("fh-rebuild", { "freehold.cmd-rebuild-help" }, function(event)
  local count = blockers.enqueue_full_rebuild()
  local message = { "freehold.rebuild-started", count }
  if event.player_index then
    local player = game.get_player(event.player_index)
    if player and player.valid then player.print(message) end
  else
    game.print(message)
  end
end)

commands.add_command("fh-welcome", { "freehold.cmd-welcome-help" }, function(event)
  if not event.player_index then return end
  local player = game.get_player(event.player_index)
  if player and player.valid then welcome.show(player) end
end)

-- Diagnosis dump for the player's standing cell and surface.
commands.add_command("fh-debug", { "freehold.cmd-debug-help" }, function(event)
  if not event.player_index then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local surface = player.surface
  local cx = math.floor(player.position.x / const.CELL)
  local cy = math.floor(player.position.y / const.CELL)
  local cell_key = registry.cell_key(cx, cy)
  local rec = registry.get(surface.index, cell_key)
  local group = surface.planet and surface.planet.name or ("surface:" .. surface.name)
  local entries = (storage.chronicle[group] or {})[cell_key]
  local renders = (storage.chronicle_renders[surface.index] or {})[cell_key]
  local lines = {
    "Freehold debug — surface " .. surface.name .. " (planet: " .. tostring(surface.planet and surface.planet.name) .. ")",
    "  enabled: " .. tostring(not storage.disabled_surfaces[surface.index]) .. "  cell (" .. cx .. "," .. cy .. ") state: " .. (rec and rec.state or "wilderness"),
    "  chronicle group: " .. group .. "  entries here: " .. (entries and #entries or 0) .. "  drawn objects here: " .. (renders and #renders or 0),
    "  backfilled: " .. tostring(storage.chronicle_backfilled) .. "  heal flag: " .. tostring(storage.disable_healed),
  }
  local total = 0
  for _, cells in pairs(storage.chronicle[group] or {}) do total = total + #cells end
  lines[#lines + 1] = "  chronicle entries on " .. group .. ": " .. total
  for _, line in pairs(lines) do player.print(line) end
end)
