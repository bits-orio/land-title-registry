-- Layer assignment: every player-creation prototype ends up in exactly one of
-- fh-land / fh-transit / fh-rampart — except the exempt class, which carries
-- no layer and can exist anywhere.
--
-- Membership is capability/type-based, never a name blacklist. The mod-data
-- declaration channel and the host startup-setting overrides land in M4; this
-- file is structured so they slot into resolve_layer's precedence chain
-- (defaults < mod-data < host settings) without reshaping anything.

local mask_util = require("collision-mask-util")

-- Transport corridors: the belt family, every rail type, signals, stations,
-- and pipes. train-stop is transit because it has no energy source at all, so
-- it functions on an unpowered Trail.
local TRANSIT_TYPES = {
  ["transport-belt"] = true,
  ["underground-belt"] = true,
  ["splitter"] = true,
  ["lane-splitter"] = true,
  ["loader"] = true,
  ["loader-1x1"] = true,
  ["linked-belt"] = true,
  ["straight-rail"] = true,
  ["curved-rail-a"] = true,
  ["curved-rail-b"] = true,
  ["half-diagonal-rail"] = true,
  ["elevated-straight-rail"] = true,
  ["elevated-curved-rail-a"] = true,
  ["elevated-curved-rail-b"] = true,
  ["elevated-half-diagonal-rail"] = true,
  ["rail-ramp"] = true,
  ["rail-support"] = true,
  ["legacy-straight-rail"] = true,
  ["legacy-curved-rail"] = true,
  ["rail-signal"] = true,
  ["rail-chain-signal"] = true,
  ["train-stop"] = true,
  ["pipe"] = true,
  ["pipe-to-ground"] = true,
}

-- Self-sufficient defense: turrets (never artillery), walls, radar, and the
-- power kit that lets a rampart run itself. pump is rampart because it needs
-- electricity, and electricity is a Rampart right.
local RAMPART_TYPES = {
  ["ammo-turret"] = true,
  ["electric-turret"] = true,
  ["fluid-turret"] = true,
  ["radar"] = true,
  ["wall"] = true,
  ["gate"] = true,
  ["electric-pole"] = true,
  ["solar-panel"] = true,
  ["accumulator"] = true,
  ["pump"] = true,
}

-- Exempt: no layer, placeable/existing anywhere. The primary rule is the
-- whole VehiclePrototype subtree — rolling stock included, or trains would
-- collide with every blocker they drive through. Accepted leak: artillery
-- wagons (and rocket spidertrons) slip the superweapons-need-a-Deed rule;
-- any mask that blocks their placement also blocks their movement.
local EXEMPT_TYPES = {
  ["car"] = true,
  ["spider-vehicle"] = true,
  ["locomotive"] = true,
  ["cargo-wagon"] = true,
  ["infinity-cargo-wagon"] = true,
  ["fluid-wagon"] = true,
  ["artillery-wagon"] = true,
  ["construction-robot"] = true,
  ["logistic-robot"] = true,
  ["combat-robot"] = true,
  ["capture-robot"] = true,
  ["unit"] = true,
  ["character"] = true,
  ["space-platform-hub"] = true,
  ["cargo-pod"] = true,
  ["rocket-silo-rocket"] = true,
  ["rocket-silo-rocket-shadow"] = true,
}

-- Name-based exemptions, sanctioned by the spec for classes that share a
-- generic type: crash-site debris and the cargo pod container are type
-- "container" (exempting the type would exempt every chest in the game).
-- Crash-site wreckage carries player-creation and belongs to the player
-- force, so a layer on it would block downgrading the spawn cells until
-- every piece of debris was mined away.
local EXEMPT_NAMES = {
  ["cargo-pod-container"] = true,
}

local function resolve_layer(proto)
  if EXEMPT_TYPES[proto.type] then return nil end
  if EXEMPT_NAMES[proto.name] then return nil end
  if proto.name:sub(1, 11) == "crash-site-" then return nil end
  if TRANSIT_TYPES[proto.type] then return "fh-transit" end
  if RAMPART_TYPES[proto.type] then return "fh-rampart" end
  -- Everything else with the player-creation flag — explicitly including
  -- artillery-turret, assembling machines, miners, roboports, and labs.
  return "fh-land"
end

local function has_flag(proto, wanted)
  if not proto.flags then return false end
  for _, flag in ipairs(proto.flags) do
    if flag == wanted then return true end
  end
  return false
end

for _, group in pairs(data.raw) do
  for _, proto in pairs(group) do
    if type(proto) == "table" and has_flag(proto, "player-creation") then
      local layer = resolve_layer(proto)
      if layer then
        -- deepcopy matters: get_mask returns the prototype's own mask table
        -- by reference (possibly shared between prototypes); mutating it in
        -- place could edit every prototype sharing that table.
        local mask = table.deepcopy(mask_util.get_mask(proto))
        mask.layers[layer] = true
        proto.collision_mask = mask
      end
    end
  end
end
