-- Console commands. /fh-rebuild reconciles the world with the registry — the
-- recovery path for any drift (ADR-0003). Large rebuilds drain through the
-- batched on_nth_tick queue, never in a single tick.

local const = require("scripts.const")
local registry = require("scripts.registry")
local blockers = require("scripts.blockers")
local welcome = require("scripts.welcome")
local chronicle = require("scripts.chronicle")

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

-- Diagnosis dump: answers "why no celebration here?" directly.
commands.add_command("fh-debug", { "freehold.cmd-debug-help" }, function(event)
  if not event.player_index then return end
  local player = game.get_player(event.player_index)
  if not (player and player.valid) then return end
  local surface = player.surface
  local cx = math.floor(player.position.x / const.CELL)
  local cy = math.floor(player.position.y / const.CELL)
  local rec = registry.get(surface.index, registry.cell_key(cx, cy))
  local entries = chronicle.entries_for(surface, cx, cy)

  player.print("── Freehold debug ──")
  player.print(string.format("surface %s (planet: %s)  enabled: %s",
    surface.name, tostring(surface.planet and surface.planet.name),
    tostring(not storage.disabled_surfaces[surface.index])))
  player.print(string.format("you are on force %q; cell (%d,%d) is %s%s",
    player.force.name, cx, cy, rec and rec.state or "wilderness",
    rec and (" owned by " .. game.forces[rec.force_index].name) or ""))

  -- Which forces actually hold claims anywhere? The celebration gate is
  -- about distinct FORCES, and players sharing a force count once.
  local claiming = {}
  for _, cells in pairs(storage.cells) do
    for _, r in pairs(cells) do
      local f = game.forces[r.force_index]
      if f and f.valid then claiming[f.name] = (claiming[f.name] or 0) + 1 end
    end
  end
  local names = {}
  for name, count in pairs(claiming) do names[#names + 1] = name .. "(" .. count .. ")" end
  table.sort(names)
  player.print("forces holding cells: " .. (#names > 0 and table.concat(names, ", ") or "none"))

  player.print("chronicle for THIS cell: " .. #entries .. " team(s)")
  for rank, entry in ipairs(entries) do
    player.print(string.format("   %d. %s  %d ticks", rank, entry.force_name, entry.clock))
  end

  -- The verdict, spelled out.
  if not rec or rec.state ~= "deed" then
    player.print("[color=1,0.7,0.3]No celebration: this cell is not a Deed. Only Deeds enter the chronicle.[/color]")
  elseif #entries < 2 then
    player.print("[color=1,0.7,0.3]No celebration: only " .. #entries ..
      " team has deeded these coordinates. Celebration needs a SECOND force to deed the same cell (x,y) - two players on the same force count as one.[/color]")
  else
    player.print("[color=0.4,1,0.4]Celebration gate is OPEN here: the next team to deed these coordinates is celebrated.[/color]")
  end
end)
