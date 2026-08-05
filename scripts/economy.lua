-- Land points: held per force, plain Lua numbers (refunds are fractional at
-- the default rate, and fractions are applied exactly).

local custom_events = require("scripts.custom_events")

local economy = {}

-- Balances are quantized to hundredths of a point after every mutation.
-- step * percent / 100 always has at most two decimal digits for the
-- sanctioned integer settings, but values like 0.3 are not exactly
-- representable as doubles; re-snapping to the nearest hundredth on every
-- change keeps accumulation exact (ten 0.3 refunds sum to exactly 3.0, so
-- a 3-point claim is never falsely denied by 2.9999999999999996).
local function snap(n)
  if n >= 0 then
    return math.floor(n * 100 + 0.5) / 100
  end
  return -math.floor(-n * 100 + 0.5) / 100
end

function economy.get(force_index)
  return storage.points[force_index] or 0
end

function economy.refund_percent()
  return settings.global["fh-refund-percent"].value
end

-- Every balance mutation goes through here, so on_points_changed fires from
-- one place with a stable reason vocabulary.
function economy.change(force, delta, reason)
  local balance = snap((storage.points[force.index] or 0) + delta)
  storage.points[force.index] = balance
  script.raise_event(custom_events.on_points_changed, {
    force_name = force.name,
    points = balance,
    delta = delta,
    reason = reason,
  })
end

function economy.set(force, points, reason)
  points = snap(points)
  local delta = points - (storage.points[force.index] or 0)
  storage.points[force.index] = points
  script.raise_event(custom_events.on_points_changed, {
    force_name = force.name,
    points = points,
    delta = delta,
    reason = reason,
  })
end

-- Starting grant on force creation (and for all existing forces on init).
function economy.init_force(force)
  if storage.points[force.index] == nil then
    economy.set(force, settings.global["fh-starting-points"].value, "starting-grant")
  end
end

-- Forces merged: union everything into the destination. The two forces' cell
-- sets are disjoint by construction (a record holds exactly one force_index),
-- so there is no conflict to resolve — sum balances, reassign cells, raise.
function economy.on_forces_merged(event)
  local destination = event.destination
  local source_index = event.source_index

  local source_points = storage.points[source_index]
  storage.points[source_index] = nil

  for _, cells in pairs(storage.cells) do
    for _, rec in pairs(cells) do
      if rec.force_index == source_index then
        rec.force_index = destination.index
      end
    end
  end

  if source_points and source_points ~= 0 then
    economy.change(destination, source_points, "merge")
  end
end

-- Display formatting: integers plain, fractions to two decimals.
function economy.format(n)
  if n % 1 == 0 then
    return tostring(n)
  end
  return string.format("%.2f", n)
end

return economy
