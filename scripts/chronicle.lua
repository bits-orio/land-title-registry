-- The cell chronicle (ADR-0012): a per-cell speedrun leaderboard. For every
-- (planet, cell), the teams that have deeded that cell, ranked by how FAST
-- they did it on their own team clock — not by who arrived first. A later
-- team posting a better time rightfully displaces earlier entries, and the
-- drawn rankings update to match. This exploits MTS's isolated-copies
-- structure (cell (x, y) is directly comparable across team surfaces of a
-- planet) for asynchronous competition with zero physical interference.
--
-- Records are keyed by PLANET, so they survive surface clears and outlive
-- downgrades: a chronicle entry is an achievement, not a state.
--
-- Rendered as tiny text lines under each cell's top edge (centered) on
-- EVERY surface of the planet — each team sees the standings on its own
-- copy. Recognition (flying text + chat) fires only when at least two
-- teams hold entries, so vanilla single-force play gets the quiet personal
-- log without "Fastest!" spam.

local const = require("scripts.const")
local registry = require("scripts.registry")

local chronicle = {}

-- compat/mts.lua installs a provider returning
-- { display_name = ?, clock_start_tick = ? } for a force name, via
-- mts-v1's get_team_info. Without it (or for non-team forces), names are
-- force names and clocks fall back to absolute game time.
chronicle.team_info_provider = nil

-- Standings text is drawn in a neutral tint; the TEAM's own color arrives
-- inside the rich-text label (below), so rank never invents a palette of
-- its own — a team reads the same color everywhere it is named.
local TEXT_COLOR = { r = 0.92, g = 0.92, b = 0.92 }
local COORD_COLOR = { r = 0.78, g = 0.78, b = 0.72 }
local LINE_STEP = 0.62          -- vertical spacing of world standings
-- World standings are centred on the cell; the coordinate is right-aligned
-- so it ends just left of them, and the pair reads as one centred block.
local STANDINGS_HALF_WIDTH = 3.9
local COORD_GAP = 0.3
-- Map type is large again: the compact map format (team tag and clock, no
-- rank number and no leader name) is short enough to carry it without
-- overrunning the cell, which the full label at this size could not.
local CHART_SCALE = 4.4
local CHART_LINE_STEP = 3.6
-- The map draws one record line and the cell coordinate, both at every
-- zoom (playtest: hiding the coordinate at a distance made it feel
-- unreliable). There is nothing left to thin out, so the zoom ladder that
-- used to stage detail is gone; visibility is now simply on or off per
-- player. World view is separate and always shows the full standings.
--
-- Bump when the stored entry structure changes: chronicle.needs_repair
-- compares against it, so a shape change self-heals on the next load
-- without depending on any other version counter staying in step.
local ENTRY_SHAPE = 4

-- Every Land Title Registry announcement carries the survey-tool mark: one symbol
-- across the portal thumbnail, shortcut bar, tool, technology, and chat.
local BRAND = "[img=item/ltr-survey-tool]"

-- compat/mts.lua installs this to return mts-v1's team label: the team's
-- colored tag plus its current leader in brackets, e.g.
-- "[color=…]Team Pioneers[/color] [Alice]". Always prefer it over a bare
-- name — every mention of a team carries its leader.
chronicle.team_label_provider = nil

-- Team name WITHOUT the leader suffix, for compact chat lines.
chronicle.team_tag_provider = nil

-- MTS's animated pop-up presets, when MTS is present: a companion mod's
-- celebrations then look native instead of reinventing the animation.
-- Signature: (preset, text, force_name) -> boolean handled.
chronicle.popup_provider = nil

-- Labels reflect live state (renames, leader changes, recolors), so they
-- are re-fetched rather than stored — but a full rebuild redraws many
-- cells in one tick, so memoize within a tick to keep the remote calls to
-- one per force. game.tick is deterministic, so this is desync-safe.
local label_cache, label_cache_tick = {}, -1
local pending = {}

function chronicle.team_label(force_name)
  if game.tick ~= label_cache_tick then
    label_cache, label_cache_tick = {}, game.tick
  end
  local hit = label_cache[force_name]
  if hit then return hit end

  local label
  if chronicle.team_label_provider then
    label = chronicle.team_label_provider(force_name)
  end
  if not label then
    -- No MTS (or not a team force): the force's own color, no leader.
    local force = game.forces[force_name]
    local c = force and force.valid and force.color or nil
    label = c
      and string.format("[color=%.2f,%.2f,%.2f]%s[/color]", c.r, c.g, c.b, force_name)
      or force_name
  end
  label_cache[force_name] = label
  return label
end

-- Only real competitors are ranked. Under MTS that means actual team
-- forces: players sit on `player` before joining and on `spectator` while
-- watching, and neither is a contender — get_team_info returns nil for
-- them, which is exactly the signal. Without MTS every player force
-- competes. (Screenshots showed "Team player" and "Team spectator"
-- ranked at 0:00; this is the fix.)
local NEVER_COMPETES = { neutral = true, enemy = true }

function chronicle.is_competitor(force_name)
  if not force_name or NEVER_COMPETES[force_name] then return false end
  if chronicle.team_info_provider then
    return chronicle.team_info_provider(force_name) ~= nil
  end
  return true
end

-- One-shot purge of entries recorded before the predicate existed.
function chronicle.purge_non_competitors()
  local removed = 0
  for _, cells in pairs(storage.chronicle) do
    for _, entries in pairs(cells) do
      for i = #entries, 1, -1 do
        if not chronicle.is_competitor(entries[i].force_name) then
          table.remove(entries, i)
          removed = removed + 1
        end
      end
    end
  end
  if removed > 0 then log("LTR-CHRON purge: removed " .. removed .. " non-competitor entries") end
  return removed
end

function chronicle.team_tag(force_name)
  if chronicle.team_tag_provider then
    local tag = chronicle.team_tag_provider(force_name)
    if tag then return tag end
  end
  return chronicle.team_label(force_name)
end

-- Show a celebration. Prefers MTS's animated presets; falls back to a
-- self-expiring zoom-stable text above each recipient.
local function popup(force, text, preset)
  if chronicle.popup_provider
    and chronicle.popup_provider(preset, text, force and force.name) then
    return
  end
  local audience = (preset == "global_milestone") and game.players or force.players
  for _, member in pairs(audience) do
    if member.valid and member.connected
      and member.mod_settings["ltr-show-celebrations"].value then
      rendering.draw_text({
        text = text,
        surface = member.surface,
        target = { x = member.position.x, y = member.position.y - 7 },
        color = { r = 1, g = 0.92, b = 0.55 },
        scale = 0.1,
        font = "default-game",
        alignment = "center",
        use_rich_text = true,
        scale_with_zoom = true,
        players = { member.index },
        time_to_live = 240,
      })
      member.play_sound({ path = "utility/achievement_unlocked" })
    end
  end
end

local function team_info(force_name)
  if chronicle.team_info_provider then
    local info = chronicle.team_info_provider(force_name)
    if info then return info end
  end
  return { display_name = force_name, clock_start_tick = 0 }
end

function chronicle.format_clock(ticks)
  local total = math.floor(ticks / 60)
  local h = math.floor(total / 3600)
  local m = math.floor(total / 60) % 60
  local s = total % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%d:%02d", m, s)
end

local function entries_of(planet_name, cell_key)
  storage.chronicle[planet_name] = storage.chronicle[planet_name] or {}
  storage.chronicle[planet_name][cell_key] = storage.chronicle[planet_name][cell_key] or {}
  return storage.chronicle[planet_name][cell_key]
end

-- Resolves the PLANET a surface represents when the engine association is
-- absent — MTS team copies are map clones with surface.planet == nil, and
-- compat/mts.lua plugs mts-v1's get_surface_planet in here. Cross-team
-- comparability lives or dies on this mapping.
chronicle.surface_planet_provider = nil

-- The chronicle group of a surface: its represented planet (cross-team
-- comparable — the point of the feature), falling back to a per-surface
-- group so the leaderboard still draws locally rather than skipping.
local function group_of(surface)
  if surface.planet then return surface.planet.name end
  if chronicle.surface_planet_provider then
    local planet = chronicle.surface_planet_provider(surface)
    if planet then return planet end
  end
  return "surface:" .. surface.name
end

-- Migrate any per-surface fallback groups whose surface now resolves to a
-- planet (e.g. the provider arrived after entries were recorded): merge
-- entries into the planet group, best time per team winning. One-shot,
-- called from the join/backfill anchor.
function chronicle.regroup()
  local moved = 0
  for _, surface in pairs(game.surfaces) do
    local fallback = "surface:" .. surface.name
    local bucket = storage.chronicle[fallback]
    local target = group_of(surface)
    if bucket and target ~= fallback then
      for cell_key, entries in pairs(bucket) do
        local dest = entries_of(target, cell_key)
        for _, entry in pairs(entries) do
          local present
          for _, existing in pairs(dest) do
            if existing.force_name == entry.force_name then present = existing end
          end
          if present then
            if entry.clock < present.clock then present.clock = entry.clock end
          else
            dest[#dest + 1] = { force_name = entry.force_name, clock = entry.clock }
          end
          moved = moved + 1
        end
        table.sort(dest, function(a, b)
          if a.clock ~= b.clock then return a.clock < b.clock end
          return a.force_name < b.force_name
        end)
      end
      storage.chronicle[fallback] = nil
    end
  end
  if moved > 0 then log("LTR-CHRON regroup: " .. moved .. " entries moved to planet groups") end
  return moved
end

-- Public read accessor (also the remote interface's get_cell_chronicle):
-- the ranked entries for a cell, or an empty table.
function chronicle.entries_for(surface, cx, cy)
  local group = storage.chronicle[group_of(surface)]
  return group and group[registry.cell_key(cx, cy)] or {}
end

-- Standings are competition UI. With a single competing force — vanilla
-- freeplay without MTS — the per-cell roster is noise (playtest call:
-- "no need for player information in these cells"), so cells keep only
-- their map-view coordinates. MTS present means competitive; without it,
-- competitive means at least two player-bearing competitor forces (PvP
-- scenarios keep their standings). A game BECOMING competitive redraws
-- cells lazily, on their next record or rebuild.
function chronicle.competitive()
  if chronicle.team_info_provider then return true end
  local count = 0
  for _, force in pairs(game.forces) do
    if #force.players > 0 and chronicle.is_competitor(force.name) then
      count = count + 1
      if count > 1 then return true end
    end
  end
  return false
end

-- The cell's fastest entry, for on-demand detail (survey-tool hover).
-- Map view now hides standings at distance, so the answer has to stay
-- reachable without zooming in.
function chronicle.leader_of(surface, cx, cy)
  local entries = (storage.chronicle[group_of(surface)] or {})[registry.cell_key(cx, cy)]
  if not entries or #entries == 0 then return nil end
  return entries[1], #entries
end

-- ---------------------------------------------------------------------------
-- Map-view visibility
--
-- Chart objects are shared (one set per cell, not per player), and each
-- viewer's level of detail is expressed through the object's `players`
-- filter. That keeps object count independent of player count — the
-- alternative, a set per player, multiplies a mature surface's thousands
-- of objects by the team roster.

-- Player lists per tier for one surface, split by whether the viewer asked
-- to see uncontested cells. contested[t] is a superset of all[t]: a cell
-- with rivals is shown to everyone at that tier, a lone entry only to
-- those not filtering. Memoized per tick — a rebuild redraws many cells in
-- one tick and they all want the same answer.
local vis_cache, vis_cache_tick = {}, -1

local function visibility_lists(surface_index)
  if game.tick ~= vis_cache_tick then
    vis_cache, vis_cache_tick = {}, game.tick
  end
  local hit = vis_cache[surface_index]
  if hit then return hit end

  local lists = { all = {}, contested = {} }
  for _, player in pairs(game.connected_players) do
    -- player.surface_index follows remote view, which is exactly the
    -- surface whose chart the player is looking at.
    if player.valid and player.surface_index == surface_index
      and storage.chronicle_on[player.index] then
      local contested_only = player.mod_settings["ltr-chronicle-contested-only"].value
      lists.contested[#lists.contested + 1] = player.index
      if not contested_only then
        lists.all[#lists.all + 1] = player.index
      end
    end
  end
  vis_cache[surface_index] = lists
  return lists
end

-- An empty `players` array is ambiguous (it can read as "everyone"), so
-- nobody-sees-this is expressed with `visible` instead.
local function show_to(objects, players)
  local none = #players == 0
  for _, object in pairs(objects) do
    if object.valid then
      if none then
        object.visible = false
      else
        object.players = players
        object.visible = true
      end
    end
  end
end

local function apply_cell(entry, lists)
  if not entry.buckets then return end
  show_to(entry.buckets[1], entry.contested and lists.contested or lists.all)
end

-- Re-apply every cell's map visibility on one surface. Called when a
-- viewer's tier, surface, toggle, or filter setting changes — never per
-- frame, and at most once per poll for a given surface.
function chronicle.apply_visibility(surface_index)
  local refs = storage.chronicle_renders[surface_index]
  if not refs then return end
  local lists = visibility_lists(surface_index)
  for _, entry in pairs(refs) do
    apply_cell(entry, lists)
  end
end

-- control.lua installs this to redraw a surface the moment somebody looks
-- at it, paying a migration's cost per surface visited instead of for all
-- thirty up front.
chronicle.on_surface_viewed = nil

-- Poll connected players for zoom and viewed surface. There is no event
-- for either, so this is a 20-tick sampler registered only while someone
-- is connected (scripts/chronicle.ensure_poll_handler) — the same scoped
-- on_nth_tick discipline the survey-tool hover uses, never an
-- unconditional on_tick.
function chronicle.poll()
  local dirty = {}
  for _, player in pairs(game.connected_players) do
    if player.valid then
      local index = player.index
      local view = storage.chart_view[index]
      local surface_index = player.surface_index
      if chronicle.on_surface_viewed then
        chronicle.on_surface_viewed(surface_index)
      end
      if not view or view.surface_index ~= surface_index then
        if view and view.surface_index ~= surface_index then
          dirty[view.surface_index] = true
        end
        storage.chart_view[index] = { surface_index = surface_index }
        dirty[surface_index] = true
      end
    end
  end
  for surface_index in pairs(dirty) do
    chronicle.apply_visibility(surface_index)
  end
end

local POLL_INTERVAL = 20

-- Registration must be reproducible from storage alone: called after
-- watcher changes and from on_load.
function chronicle.ensure_poll_handler()
  -- on_load runs BEFORE on_configuration_changed, so a storage field
  -- introduced in the current version is still nil here on an updating
  -- save. Guard rather than assume (this crashed a 0.1.9 save on load).
  if storage.chart_watchers and next(storage.chart_watchers) then
    script.on_nth_tick(POLL_INTERVAL, chronicle.poll)
  else
    script.on_nth_tick(POLL_INTERVAL, nil)
  end
end

-- Is any tracked cell still holding objects of a retired shape? A stale
-- entry is either legacy (a flat array from before bucketing) or carries
-- the `world` block that no longer draws. Cheap enough to check on every
-- load, and checking the OBJECTS rather than a version counter means the
-- repair cannot be skipped by bookkeeping that got out of step — which is
-- exactly how dead text survived two migrations (playtest).
function chronicle.needs_repair()
  for _, refs in pairs(storage.chronicle_renders) do
    for _, entry in pairs(refs) do
      if entry.shape ~= ENTRY_SHAPE then return true end
    end
  end
  return false
end

-- Redraw every cell this mod has chronicle objects for, on every surface.
--
-- The lazy per-surface migration is right for MAP SPRITES, which number in
-- the hundred-thousands and are only worth paying for where someone looks.
-- Chronicle objects are the opposite: a few thousand in total, and stale
-- ones are actively wrong — they outlive their locale keys and render as
-- "Unknown key" (playtest screenshot). Cheap enough to fix everywhere at
-- once, so a chronicle-shape change does exactly that and never leaves a
-- surface carrying dead text because nobody happened to visit it.
-- Every render object this mod owns, and how many our bookkeeping knows
-- about. A gap between them is orphans; no gap plus visible strays means
-- the objects are not ours at all.
function chronicle.object_census()
  local total = 0
  for _ in pairs(rendering.get_all_objects("land-title-registry")) do total = total + 1 end
  local tracked = 0
  for _, refs in pairs(storage.chronicle_renders) do
    for _, entry in pairs(refs) do
      if entry.buckets then
        for _, bucket in pairs(entry.buckets) do tracked = tracked + #bucket end
        tracked = tracked + #(entry.world or {})
      else
        tracked = tracked + #entry
      end
    end
  end
  return total, tracked
end

function chronicle.refresh_all_tracked()
  local refreshed = 0
  for surface_index, refs in pairs(storage.chronicle_renders) do
    local surface = game.surfaces[surface_index]
    if surface and surface.valid then
      local keys = {}
      for key in pairs(refs) do keys[#keys + 1] = key end
      for _, key in ipairs(keys) do
        local pos = registry.cell_key_to_pos(key)
        chronicle.refresh_cell(surface, pos.x, pos.y)
        refreshed = refreshed + 1
      end
    else
      -- Surface is gone; free whatever it still held.
      for _, entry in pairs(refs) do destroy_refs(entry) end
      storage.chronicle_renders[surface_index] = nil
    end
  end
  log("LTR-CHRON refreshed " .. refreshed .. " tracked cells across all surfaces")
  return refreshed
end

-- Everything /ltr-debug needs to explain why the map layer does or does
-- not show anything for this player, in one call.
function chronicle.diagnose(player)
  local surface_index = player.surface_index
  local refs = storage.chronicle_renders[surface_index] or {}
  local cells, bucketed, legacy, objects, visible = 0, 0, 0, 0, 0
  for _, entry in pairs(refs) do
    cells = cells + 1
    if entry.buckets then
      bucketed = bucketed + 1
      for _, bucket in pairs(entry.buckets) do
        for _, object in pairs(bucket) do
          objects = objects + 1
          if object.valid and object.visible then visible = visible + 1 end
        end
      end
    else
      legacy = legacy + 1
    end
  end
  local view = storage.chart_view[player.index]
  return {
    enabled = chronicle.enabled_for(player),
    competitive = chronicle.competitive(),
    render_mode = tostring(player.render_mode),
    zoom = player.zoom,

    applied_surface = view and view.surface_index or 0,
    surface_index = surface_index,
    cells = cells, bucketed = bucketed, legacy = legacy,
    objects = objects, visible = visible,
    epoch = storage.chart_epoch or 0,
    queued = #storage.rebuild_queue,
  }
end

-- Toggle the whole map layer for one player (shortcut button / hotkey).
-- OFF is the default: the standings are genuinely useful but they are a
-- lot of ink on a developed map, and a player who wants them asks
-- (playtest call). Absent state therefore means hidden, and the opt-in
-- persists per player.
function chronicle.set_enabled(player, enabled)
  storage.chronicle_on[player.index] = enabled or nil
  player.set_shortcut_toggled("ltr-toggle-chronicle", enabled)
  chronicle.apply_visibility(player.surface_index)
end

function chronicle.enabled_for(player)
  return storage.chronicle_on[player.index] == true
end

function chronicle.on_player_joined(player)
  storage.chart_watchers[player.index] = true
  chronicle.ensure_poll_handler()
  player.set_shortcut_toggled("ltr-toggle-chronicle", chronicle.enabled_for(player))
end

function chronicle.on_player_gone(player_index)
  local view = storage.chart_view[player_index]
  storage.chart_view[player_index] = nil
  storage.chart_watchers[player_index] = nil
  chronicle.ensure_poll_handler()
  if view then chronicle.apply_visibility(view.surface_index) end
end

-- ---------------------------------------------------------------------------

local function destroy_refs(entry)
  if not entry then return end
  -- Pre-0.1.9 saves stored a flat array of objects; current ones store
  -- buckets. Both are swept here so a migration never leaks objects.
  if entry.buckets then
    for _, objects in pairs(entry.buckets) do
      for _, object in pairs(objects) do
        if object.valid then object.destroy() end
      end
    end
    -- `world` held the ranked world-view block, retired in 0.1.10. Entries
    -- written by builds that still drew it carry the field, and dropping
    -- this loop when the drawing went away orphaned those objects
    -- permanently — they are unreachable from storage, so nothing else can
    -- ever free them (playtest: the top-three text survived every rebuild).
    for _, object in pairs(entry.world or {}) do
      if object.valid then object.destroy() end
    end
  else
    for _, object in pairs(entry) do
      if type(object) == "table" and object.valid then object.destroy() end
    end
  end
end

-- Destroy and redraw the chronicle text of one cell on one surface.
function chronicle.refresh_cell(surface, cx, cy)
  local surface_index = surface.index
  storage.chronicle_renders[surface_index] = storage.chronicle_renders[surface_index] or {}
  local refs = storage.chronicle_renders[surface_index]
  local cell_key = registry.cell_key(cx, cy)

  destroy_refs(refs[cell_key])
  refs[cell_key] = nil

  if storage.disabled_surfaces[surface_index] then return end
  local entries = (storage.chronicle[group_of(surface)] or {})[cell_key]
  if not entries or #entries == 0 then return end

  -- Non-competitive games draw no standings rows anywhere and no world
  -- text at all — the map keeps the coordinates, at close zoom only.
  local competitive = chronicle.competitive()
  local shown = competitive and math.min(3, #entries) or 0
  local center_x = cx * const.CELL + const.CELL / 2
  local center_y = cy * const.CELL + const.CELL / 2

  local world = {}
  local buckets = { {} }
  local first_y = cy * const.CELL + 0.5

  -- WORLD view keeps the full standings. Only a handful of cells are on
  -- screen at a time here, so the ranked block costs nothing in
  -- legibility — it was the MAP that drowned in it (playtest).
  if shown > 0 then
    world[#world + 1] = rendering.draw_text({
      text = string.format("(%d,%d)", cx, cy),
      surface = surface,
      target = {
        x = center_x - STANDINGS_HALF_WIDTH - COORD_GAP,
        y = first_y + (shown - 1) * LINE_STEP / 2,
      },
      color = COORD_COLOR,
      scale = 0.8,
      alignment = "right",
      -- Stated rather than inherited: these must never reach the chart,
      -- and a default is a poor thing to bet the map's legibility on.
      render_mode = "game",
    })
    for rank = 1, shown do
      local ranked = entries[rank]
      world[#world + 1] = rendering.draw_text({
        text = { "land-title-registry.chronicle-line", rank,
          chronicle.team_label(ranked.force_name), chronicle.format_clock(ranked.clock) },
        surface = surface,
        target = { x = center_x, y = first_y + (rank - 1) * LINE_STEP },
        color = TEXT_COLOR,
        scale = 0.7,
        alignment = "center",
        use_rich_text = true,
        render_mode = "game",
      })
    end
  end

  -- MAP view: the record holder and the cell coordinate, both at every
  -- zoom. Compact format on purpose — team tag and clock, no rank number
  -- and no leader name — so the larger type still fits its own cell.
  local map = buckets[1]
  map[#map + 1] = rendering.draw_text({
    text = string.format("(%d,%d)", cx, cy),
    surface = surface,
    target = { x = center_x, y = center_y - CHART_LINE_STEP / 2 },
    color = COORD_COLOR,
    scale = CHART_SCALE,
    alignment = "center",
    vertical_alignment = "middle",
    render_mode = "chart",
  })
  if shown > 0 then
    local leader = entries[1]
    map[#map + 1] = rendering.draw_text({
      text = { "land-title-registry.chronicle-chart-line",
        chronicle.team_tag(leader.force_name), chronicle.format_clock(leader.clock) },
      surface = surface,
      target = { x = center_x, y = center_y + CHART_LINE_STEP / 2 },
      color = TEXT_COLOR,
      scale = CHART_SCALE,
      alignment = "center",
      vertical_alignment = "middle",
      use_rich_text = true,
      render_mode = "chart",
    })
  end

  local entry = {
    shape = ENTRY_SHAPE,
    world = world,
    buckets = buckets,
    contested = #entries > 1,
  }
  apply_cell(entry, visibility_lists(surface_index))
  refs[cell_key] = entry
end

local function redraw_on_planet(group, cx, cy)
  for _, surface in pairs(game.surfaces) do
    if group_of(surface) == group then
      chronicle.refresh_cell(surface, cx, cy)
    end
  end
end

-- A cell reached Deed: record the team's time (first Deed of that cell per
-- team; later re-deeds don't improve it), re-rank, redraw, recognize.
function chronicle.on_cell_claimed(event)
  if event.new_state ~= "deed" then return end
  local surface = game.surfaces[event.surface_index]
  if not (surface and surface.valid) then
    log("LTR-CHRON skip: invalid surface " .. tostring(event.surface_index))
    return
  end
  if not chronicle.is_competitor(event.force_name) then
    log("LTR-CHRON skip: " .. tostring(event.force_name) .. " is not a competing team")
    return
  end
  local group = group_of(surface)
  local cell_key = registry.cell_key(event.cell_pos.x, event.cell_pos.y)
  local entries = entries_of(group, cell_key)

  for _, entry in pairs(entries) do
    if entry.force_name == event.force_name then
      log(string.format("LTR-CHRON skip: %s already recorded on %s (%d,%d)",
        event.force_name, group, event.cell_pos.x, event.cell_pos.y))
      return
    end
  end

  local info = team_info(event.force_name)
  local clock = event.tick - (info.clock_start_tick or 0)
  entries[#entries + 1] = { force_name = event.force_name, clock = clock }
  table.sort(entries, function(a, b)
    if a.clock ~= b.clock then return a.clock < b.clock end
    return a.force_name < b.force_name -- deterministic tiebreak
  end)

  local rank
  for i, entry in ipairs(entries) do
    if entry.force_name == event.force_name then rank = i break end
  end

  log(string.format("LTR-CHRON record: %s rank %d/%d on %s cell (%d,%d) clock %d",
    event.force_name, rank, #entries, group, event.cell_pos.x, event.cell_pos.y, clock))
  redraw_on_planet(group, event.cell_pos.x, event.cell_pos.y)

  -- Only two things are worth celebrating: being FIRST to deed a cell, and
  -- TAKING the fastest record from someone. Placing 2nd or 3rd is not an
  -- achievement (playtest call) — it lands in the standings and nowhere
  -- else.
  local notable
  if #entries == 1 then
    notable = { kind = "first", cell_pos = event.cell_pos, clock = clock }
  elseif rank == 1 then
    local beaten = entries[2]
    notable = {
      kind = "fastest", cell_pos = event.cell_pos, clock = clock,
      beat_force = beaten.force_name, beat_clock = beaten.clock,
    }
  end
  if not notable then return end
  pending[#pending + 1] = notable

  local force = game.forces[event.force_name]
  if not (force and force.valid) then return end
  local coords = string.format("(%d,%d)", event.cell_pos.x, event.cell_pos.y)

  -- Celebration text. Under MTS these go through MTS's own animated
  -- pop_text presets (elastic pop for a team achievement, rainbow pop
  -- server-wide for a record), so Land Title Registry's milestones look native.
  -- Without MTS a plain zoom-stable draw_text stands in — still no tick
  -- loop, so the no-idle-tick discipline holds either way.
  if notable.kind == "first" then
    local text = BRAND .. " First to Deed " .. coords
    popup(force, text, "milestone")
  else
    -- A record change is told to the two teams it happened to, not to the
    -- whole server: with a dozen teams, every contested cell changes hands
    -- ~H(n) times and a global broadcast turns the race into chat spam.
    -- Everyone else still sees the standings on the map.
    local text = BRAND .. " Fastest Deed " .. coords
    popup(force, text, "milestone")
    force.print({ "land-title-registry.record-taken", coords, chronicle.format_clock(clock),
      chronicle.team_label(notable.beat_force), chronicle.format_clock(notable.beat_clock) })

    local beaten = game.forces[notable.beat_force]
    if beaten and beaten.valid then
      beaten.print({ "land-title-registry.record-lost", coords,
        chronicle.team_label(event.force_name), chronicle.format_clock(clock),
        chronicle.format_clock(notable.beat_clock) })
    end
  end
end

-- Batch plumbing: the survey tool prints ONE chat line per drag, enriched
-- with the batch's most notable chronicle outcome. Transient per-batch
-- state (never persisted, written and read inside one tick).
function chronicle.begin_batch()
  pending = {}
end

-- The batch's headline: a record taken outranks a first claim.
function chronicle.take_notable()
  local best
  for _, item in ipairs(pending) do
    if item.kind == "fastest" then return item end
    best = best or item
  end
  return best
end


-- A released team slot's history leaves with the team (playtest finding:
-- without this, the recycled slot's stale entry trips the already-recorded
-- guard in on_cell_claimed — the new occupant re-deeds a cell their
-- predecessor held and no record, and no name, ever appears). Purge every
-- entry and redraw the affected standings.
function chronicle.on_team_released(force_name)
  local affected = {}
  local removed = 0
  for group, cells in pairs(storage.chronicle) do
    for cell_key, entries in pairs(cells) do
      for i = #entries, 1, -1 do
        if entries[i].force_name == force_name then
          table.remove(entries, i)
          removed = removed + 1
          affected[#affected + 1] = { group = group, cell_key = cell_key }
        end
      end
      if #entries == 0 then cells[cell_key] = nil end
    end
  end
  if removed == 0 then return end
  log("LTR-CHRON release: purged " .. removed .. " entries of " .. force_name)
  for _, hit in ipairs(affected) do
    local pos = registry.cell_key_to_pos(hit.cell_key)
    for _, surface in pairs(game.surfaces) do
      if group_of(surface) == hit.group then
        chronicle.refresh_cell(surface, pos.x, pos.y)
      end
    end
  end
end

-- Merged forces: keep each cell's best time under the surviving name.
function chronicle.on_forces_merged(event)
  local destination_name = event.destination.name
  for _, cells in pairs(storage.chronicle) do
    for _, entries in pairs(cells) do
      local best_own
      for i = #entries, 1, -1 do
        local entry = entries[i]
        if entry.force_name == event.source_name or entry.force_name == destination_name then
          if best_own == nil or entry.clock < best_own then best_own = entry.clock end
          table.remove(entries, i)
        end
      end
      if best_own then
        entries[#entries + 1] = { force_name = destination_name, clock = best_own }
        table.sort(entries, function(a, b)
          if a.clock ~= b.clock then return a.clock < b.clock end
          return a.force_name < b.force_name
        end)
      end
    end
  end
end

-- Retrofit: deeds that predate the chronicle feature enter it from the
-- registry. The stored claimed_tick is the cell's FIRST CLAIM (not its
-- deed moment) — the best record that exists, so backfilled times read
-- slightly faster than they were; honest and one-time. Idempotent: teams
-- already present in a cell's chronicle are never re-added.
function chronicle.backfill()
  local added = 0
  for surface_index, cells in pairs(storage.cells) do
    local surface = game.surfaces[surface_index]
    if surface and surface.valid then
      local planet_name = group_of(surface)
      for cell_key, rec in pairs(cells) do
        if rec.state == "deed" then
          local force = game.forces[rec.force_index]
          if force and force.valid and chronicle.is_competitor(force.name) then
            local entries = entries_of(planet_name, cell_key)
            local present = false
            for _, entry in pairs(entries) do
              if entry.force_name == force.name then present = true end
            end
            if not present then
              local info = team_info(force.name)
              local clock = math.max(0, (rec.claimed_tick or 0) - (info.clock_start_tick or 0))
              entries[#entries + 1] = { force_name = force.name, clock = clock }
              table.sort(entries, function(a, b)
                if a.clock ~= b.clock then return a.clock < b.clock end
                return a.force_name < b.force_name
              end)
              added = added + 1
            end
          end
        end
      end
    end
  end
  log("LTR-CHRON backfill: " .. added .. " entries added")
  return added
end

function chronicle.drop_surface(surface_index)
  local refs = storage.chronicle_renders[surface_index]
  if refs then
    for _, objects in pairs(refs) do
      for _, object in pairs(objects) do
        if object.valid then object.destroy() end
      end
    end
  end
  storage.chronicle_renders[surface_index] = nil
end

return chronicle
