-- Layer assignment: every player-creation prototype ends up in exactly one of
-- ltr-land / ltr-transit / ltr-rampart — except the exempt class, which carries
-- no layer and can exist anywhere.
--
-- Membership is capability/type-based, never a name blacklist, with two
-- override channels: mod-data declarations (data_type = "land-title-registry-layers")
-- and host startup settings. Precedence: defaults < mod-data < host.

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

-- ---------------------------------------------------------------------------
-- Override channels (precedence: defaults < mod-data declarations < host
-- settings; within each channel, an entity-name entry beats a type: entry).

-- Mod channel: any mod-data prototype tagged data_type = "land-title-registry-layers"
-- declares { transit = {...}, rampart = {...}, land = {...} } of entity
-- names / "type:<type>" entries. Sorted by prototype name for determinism.
local moddata_by_name, moddata_by_type = {}, {}
local LAYER_OF_KEY = { transit = "ltr-transit", rampart = "ltr-rampart", land = "ltr-land" }
if data.raw["mod-data"] then
  local declarations = {}
  for proto_name, proto in pairs(data.raw["mod-data"]) do
    if proto.data_type == "land-title-registry-layers" then
      declarations[#declarations + 1] = proto_name
    end
  end
  table.sort(declarations)
  for _, proto_name in ipairs(declarations) do
    local decl = data.raw["mod-data"][proto_name].data or {}
    for key, layer in pairs(LAYER_OF_KEY) do
      for _, entry in pairs(decl[key] or {}) do
        if type(entry) == "string" then
          local type_name = entry:match("^type:%s*(.+)$")
          if type_name then
            moddata_by_type[type_name] = layer
          else
            moddata_by_name[entry] = layer
          end
        end
      end
    end
  end
end

-- Host channel: startup string settings. Removals always send back to land.
local host_by_name, host_by_type = {}, {}
local HOST_SETTINGS = {
  ["ltr-transit-additions"] = "ltr-transit",
  ["ltr-transit-removals"] = "ltr-land",
  ["ltr-rampart-additions"] = "ltr-rampart",
  ["ltr-rampart-removals"] = "ltr-land",
}
for setting_name, layer in pairs(HOST_SETTINGS) do
  for entry in string.gmatch(settings.startup[setting_name].value, "[^,]+") do
    local trimmed = entry:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      local type_name = trimmed:match("^type:%s*(.+)$")
      if type_name then
        host_by_type[type_name] = layer
      else
        host_by_name[trimmed] = layer
      end
    end
  end
end

local function resolve_layer(proto)
  -- Host beats mod-data beats defaults; overrides beat the exemption rules
  -- too — the host always has the final word, even to layer a vehicle.
  local override = host_by_name[proto.name] or host_by_type[proto.type]
    or moddata_by_name[proto.name] or moddata_by_type[proto.type]
  if override then return override end

  if EXEMPT_TYPES[proto.type] then return nil end
  if EXEMPT_NAMES[proto.name] then return nil end
  if proto.name:sub(1, 11) == "crash-site-" then return nil end
  if TRANSIT_TYPES[proto.type] then return "ltr-transit" end
  if RAMPART_TYPES[proto.type] then return "ltr-rampart" end
  -- Everything else with the player-creation flag — explicitly including
  -- artillery-turret, assembling machines, miners, roboports, and labs.
  return "ltr-land"
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

-- The ltr-land-grants ladder is derived here so every mod's technologies and
-- recipes exist (ADR-0008).
require("prototypes.tech")
