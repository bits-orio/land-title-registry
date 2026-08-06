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
local LINE_STEP = 0.52          -- vertical spacing of standings lines
local COORD_WIDTH = 3.1         -- space reserved for the coordinate label

-- Every Freehold announcement carries the survey-tool mark: one symbol
-- across the portal thumbnail, shortcut bar, tool, technology, and chat.
local BRAND = "[item=fh-survey-tool]"

-- compat/mts.lua installs this to return mts-v1's team label: the team's
-- colored tag plus its current leader in brackets, e.g.
-- "[color=…]Team Pioneers[/color] [Alice]". Always prefer it over a bare
-- name — every mention of a team carries its leader.
chronicle.team_label_provider = nil

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
  if removed > 0 then log("FH-CHRON purge: removed " .. removed .. " non-competitor entries") end
  return removed
end

local function team_info(force_name)
  if chronicle.team_info_provider then
    local info = chronicle.team_info_provider(force_name)
    if info then return info end
  end
  return { display_name = force_name, clock_start_tick = 0 }
end

local function format_clock(ticks)
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
  if moved > 0 then log("FH-CHRON regroup: " .. moved .. " entries moved to planet groups") end
  return moved
end

-- Public read accessor (also the remote interface's get_cell_chronicle):
-- the ranked entries for a cell, or an empty table.
function chronicle.entries_for(surface, cx, cy)
  local group = storage.chronicle[group_of(surface)]
  return group and group[registry.cell_key(cx, cy)] or {}
end

-- Destroy and redraw the chronicle text of one cell on one surface.
function chronicle.refresh_cell(surface, cx, cy)
  local surface_index = surface.index
  storage.chronicle_renders[surface_index] = storage.chronicle_renders[surface_index] or {}
  local refs = storage.chronicle_renders[surface_index]
  local cell_key = registry.cell_key(cx, cy)

  local old = refs[cell_key]
  if old then
    for _, object in pairs(old) do
      if object.valid then object.destroy() end
    end
    refs[cell_key] = nil
  end

  if storage.disabled_surfaces[surface_index] then return end
  local entries = (storage.chronicle[group_of(surface)] or {})[cell_key]
  if not entries or #entries == 0 then return end

  local objects = {}
  local shown = math.min(3, #entries)
  local x0 = cx * const.CELL
  local y0 = cy * const.CELL
  local rank_x = x0 + COORD_WIDTH
  local first_y = y0 + 0.5

  -- Cell coordinates, left of the standings block and a little larger:
  -- the standings are fine print, the coordinate is the label.
  objects[#objects + 1] = rendering.draw_text({
    text = string.format("(%d,%d)", cx, cy),
    surface = surface,
    target = { x = x0 + 0.5, y = first_y + (shown - 1) * LINE_STEP / 2 },
    color = COORD_COLOR,
    scale = 0.8,
    font = "default-small",
    alignment = "left",
  })

  for rank = 1, shown do
    local entry = entries[rank]
    objects[#objects + 1] = rendering.draw_text({
      text = { "freehold.chronicle-line", rank,
        chronicle.team_label(entry.force_name), format_clock(entry.clock) },
      surface = surface,
      target = { x = rank_x, y = first_y + (rank - 1) * LINE_STEP },
      color = TEXT_COLOR,
      scale = 0.55,
      font = "default-small",
      alignment = "left",
      use_rich_text = true,
    })
  end
  refs[cell_key] = objects
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
    log("FH-CHRON skip: invalid surface " .. tostring(event.surface_index))
    return
  end
  if not chronicle.is_competitor(event.force_name) then
    log("FH-CHRON skip: " .. tostring(event.force_name) .. " is not a competing team")
    return
  end
  local group = group_of(surface)
  local cell_key = registry.cell_key(event.cell_pos.x, event.cell_pos.y)
  local entries = entries_of(group, cell_key)

  for _, entry in pairs(entries) do
    if entry.force_name == event.force_name then
      log(string.format("FH-CHRON skip: %s already recorded on %s (%d,%d)",
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

  log(string.format("FH-CHRON record: %s rank %d/%d on %s cell (%d,%d) clock %d",
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

  -- MTS-style on-screen milestone: drawn above each member of the force,
  -- zoom-stable, expiring on its own (no tick loop, so the no-idle-tick
  -- discipline holds).
  local force = game.forces[event.force_name]
  if not (force and force.valid) then return end
  local coords = string.format("(%d,%d)", event.cell_pos.x, event.cell_pos.y)
  local banner = notable.kind == "first"
    and { "freehold.pop-first", BRAND, coords }
    or { "freehold.pop-fastest", BRAND, coords, format_clock(clock),
         chronicle.team_label(notable.beat_force), format_clock(notable.beat_clock) }
  for _, member in pairs(force.players) do
    if member.valid and member.connected and member.mod_settings["fh-show-celebrations"].value then
      rendering.draw_text({
        text = banner,
        surface = member.surface,
        target = { x = member.position.x, y = member.position.y - 6 },
        color = { r = 1, g = 0.92, b = 0.55 },
        scale = 0.1,
        font = "default-large-semibold",
        alignment = "center",
        use_rich_text = true,
        scale_with_zoom = true,
        players = { member.index },
        time_to_live = 300,
      })
      member.play_sound({ path = "utility/achievement_unlocked" })
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
  log("FH-CHRON backfill: " .. added .. " entries added")
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
