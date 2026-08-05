-- Console commands. /fh-rebuild reconciles the world with the registry — the
-- recovery path for any drift (ADR-0003). Large rebuilds drain through the
-- batched on_nth_tick queue, never in a single tick.

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
