-- The ltr-land-grants technology ladder, DERIVED from the technology DAG
-- actually present in the running mod set (ADR-0008). Land Title Registry never names a
-- science pack as a constant: hardcoded pack lists sit at the wrong depths
-- under Krastorio2, misorder under Periodic Madness, and reference
-- nonexistent prototypes under Ultracube — a data-stage crash or a dead
-- income faucet.
--
-- Required from data-final-fixes.lua so every mod's technologies exist.
--
-- Derivation:
--   1. Candidate packs = every tool appearing in some technology's
--      unit.ingredients.
--   2. Availability depth = min over producing recipes of (1 + unlock
--      tech's prerequisite depth), or 0 for recipes enabled at start.
--      Recycling-category and self-producing recipes are ignored (Space
--      Age's self-recycling recipes "produce" every pack from itself).
--   3. Order by depth, then name (determinism — never pairs() order).
--   4. Band into tiers: a pack joins the current band iff its unlock tech
--      is DAG-incomparable with every band member's (neither is a
--      prerequisite ancestor of the other — a real ordering must become a
--      tier boundary) AND its depth is within BAND_SPAN of the band start
--      (parallel branches far apart in progression still read as separate
--      tiers: military vs chemical in vanilla).
--   5. Each tier is a leveled technology; the terminal tier takes every
--      pack, max_level = "infinite", with a LINEAR count_formula so land
--      income tapers but never stops.
--
-- Host override: ltr-tech-tiers (startup string) pins the ladder — semicolon-
-- separated tiers, each a comma-separated list of the packs ADDED at that
-- tier. Empty means derive.

local BAND_SPAN = 4
local LEVELS_PER_TIER = 10 -- launch ballpark; M5 tunes

local multiplier = settings.startup["ltr-tech-cost-multiplier"].value

-- ---------------------------------------------------------------------------
-- DAG helpers (memoized; cycle-guarded)

local depth_memo = {}
local function tech_depth(name)
  local hit = depth_memo[name]
  if hit ~= nil then return hit end
  depth_memo[name] = 0 -- cycle guard
  local tech = data.raw.technology[name]
  local best = 0
  if tech and tech.prerequisites then
    for _, prereq in pairs(tech.prerequisites) do
      local d = 1 + tech_depth(prereq)
      if d > best then best = d end
    end
  end
  depth_memo[name] = best
  return best
end

local ancestors_memo = {}
local function ancestors(name)
  local hit = ancestors_memo[name]
  if hit then return hit end
  local set = {}
  ancestors_memo[name] = set -- cycle guard
  local tech = data.raw.technology[name]
  if tech and tech.prerequisites then
    for _, prereq in pairs(tech.prerequisites) do
      set[prereq] = true
      for a in pairs(ancestors(prereq)) do set[a] = true end
    end
  end
  return set
end

-- Neither tech is an ancestor of the other. A pack with no unlock tech
-- (craftable from game start) is incomparable with everything.
local function incomparable(tech_a, tech_b)
  if not tech_a or not tech_b then return true end
  return not ancestors(tech_b)[tech_a] and not ancestors(tech_a)[tech_b]
end

-- ---------------------------------------------------------------------------
-- Pack discovery

local function ingredient_name(ing)
  if ing.name then return ing.name end
  return ing[1]
end

local function collect_packs()
  local used = {}
  for _, tech in pairs(data.raw.technology) do
    if tech.unit and tech.unit.ingredients then
      for _, ing in pairs(tech.unit.ingredients) do
        used[ingredient_name(ing)] = true
      end
    end
  end

  -- recipe name -> list of unlocking technology names
  local unlockers = {}
  for tech_name, tech in pairs(data.raw.technology) do
    if tech.effects then
      for _, effect in pairs(tech.effects) do
        if effect.type == "unlock-recipe" then
          unlockers[effect.recipe] = unlockers[effect.recipe] or {}
          table.insert(unlockers[effect.recipe], tech_name)
        end
      end
    end
  end

  -- pack -> {depth, unlock_tech}
  local info = {}
  for _, recipe in pairs(data.raw.recipe) do
    if recipe.category ~= "recycling" and recipe.results then
      local ingredients = {}
      for _, ing in pairs(recipe.ingredients or {}) do
        ingredients[ingredient_name(ing)] = true
      end
      for _, result in pairs(recipe.results) do
        local name = result.name
        if name and used[name] and not ingredients[name] then
          if recipe.enabled ~= false then
            if not info[name] or info[name].depth > 0 then
              info[name] = { depth = 0, unlock_tech = nil }
            end
          else
            for _, tech_name in pairs(unlockers[recipe.name] or {}) do
              local depth = 1 + tech_depth(tech_name)
              local current = info[name]
              if not current or depth < current.depth
                or (depth == current.depth and current.unlock_tech and tech_name < current.unlock_tech) then
                info[name] = { depth = depth, unlock_tech = tech_name }
              end
            end
          end
        end
      end
    end
  end

  -- Fallback for packs no recipe produces (scenario-given): order by the
  -- min depth of a technology consuming them.
  for pack in pairs(used) do
    if not info[pack] then
      local best
      for tech_name, tech in pairs(data.raw.technology) do
        if tech.unit and tech.unit.ingredients then
          for _, ing in pairs(tech.unit.ingredients) do
            if ingredient_name(ing) == pack then
              local d = tech_depth(tech_name)
              if not best or d < best then best = d end
            end
          end
        end
      end
      info[pack] = { depth = best or 0, unlock_tech = nil }
    end
  end

  local ordered = {}
  for pack, i in pairs(info) do
    ordered[#ordered + 1] = { name = pack, depth = i.depth, unlock_tech = i.unlock_tech }
  end
  table.sort(ordered, function(a, b)
    if a.depth ~= b.depth then return a.depth < b.depth end
    return a.name < b.name
  end)
  return ordered
end

-- ---------------------------------------------------------------------------
-- Banding

local function band_packs(ordered)
  local bands = {}
  for _, pack in ipairs(ordered) do
    local band = bands[#bands]
    local joins = false
    if band then
      joins = (pack.depth - band.start_depth) <= BAND_SPAN
      if joins then
        for _, member in ipairs(band.packs) do
          if not incomparable(member.unlock_tech, pack.unlock_tech) then
            joins = false
            break
          end
        end
      end
    end
    if joins then
      band.packs[#band.packs + 1] = pack
    else
      bands[#bands + 1] = { start_depth = pack.depth, packs = { pack } }
    end
  end
  return bands
end

-- ---------------------------------------------------------------------------
-- Host override: "a,b; c; d,e" — packs added per tier, cumulative ladder.

local function parse_override(value)
  local bands = {}
  for segment in string.gmatch(value, "[^;]+") do
    local packs = {}
    for entry in string.gmatch(segment, "[^,]+") do
      local trimmed = entry:match("^%s*(.-)%s*$")
      if trimmed ~= "" then
        if not data.raw.tool[trimmed] then
          error("Land Title Registry: ltr-tech-tiers names unknown science pack '" .. trimmed .. "'")
        end
        packs[#packs + 1] = { name = trimmed }
      end
    end
    if #packs > 0 then bands[#bands + 1] = { packs = packs } end
  end
  return bands
end

-- ---------------------------------------------------------------------------
-- Prototype generation. Tier i covers LEVELS_PER_TIER levels; the engine
-- reads the trailing -<number> as the family's starting level, so tier
-- prototypes are named by start level ("ltr-land-grants-1", "-11", "-21", …)
-- and one locale key (technology-name.ltr-land-grants) covers the family.

-- Science prerequisites of one band: the unlock tech of every pack the band
-- adds, appended to `prereqs` (deduped, existing-tech-guarded). Without
-- these links a tier floats free in the tech tree — researchable before its
-- own ingredients can be crafted (playtest finding). Packs craftable from
-- game start have no unlock tech and contribute no link.
local function append_band_prereqs(band, unlock_of, prereqs)
  local seen = {}
  for _, existing in ipairs(prereqs) do seen[existing] = true end
  for _, pack in ipairs(band.packs) do
    local unlock = pack.unlock_tech or unlock_of[pack.name]
    if unlock and not seen[unlock] and data.raw.technology[unlock] then
      seen[unlock] = true
      prereqs[#prereqs + 1] = unlock
    end
  end
  return prereqs
end

local function build_ladder(bands, unlock_of)
  if #bands == 0 then return end
  local cumulative = {}
  local previous_name
  local techs = {}

  for i, band in ipairs(bands) do
    for _, pack in ipairs(band.packs) do
      cumulative[#cumulative + 1] = { pack.name, 1 }
    end
    local ingredients = table.deepcopy(cumulative)
    local terminal = (i == #bands)
    local start_level = (i - 1) * LEVELS_PER_TIER + 1
    local name = "ltr-land-grants-" .. start_level
    local prereqs = append_band_prereqs(band, unlock_of,
      previous_name and { previous_name } or {})

    techs[#techs + 1] = {
      type = "technology",
      name = name,
      icon = "__land-title-registry__/graphics/survey-tool.png",
      icon_size = 64,
      upgrade = true,
      max_level = terminal and "infinite" or (i * LEVELS_PER_TIER),
      prerequisites = #prereqs > 0 and prereqs or nil,
      -- The engine's global technology-price multiplier (map setting) is
      -- ignored: land income is an economy of its own, priced by
      -- ltr-tech-cost-multiplier alone. A marathon map should slow the
      -- science game, not divorce land prices from the tuned curve.
      ignore_tech_cost_multiplier = true,
      unit = {
        -- Non-terminal levels cost 50 each. The terminal tier climbs at
        -- 1000 a level so land income tapers without ever stopping -- but
        -- it must climb FROM where tier N-1 left off, not restart the
        -- steeper slope against the absolute level number.
        --
        -- It used to read "L*1000", which meant the first endless level
        -- inherited the whole magnitude of its own level number: on a
        -- 6-tier ladder, level 50 cost 2,500 and level 51 cost 51,000, a
        -- 20x wall at a single boundary (playtest: "51 feels too
        -- expensive"). Anchoring at the boundary makes it 3,500 and the
        -- curve continuous, while keeping the same 1000-per-level slope
        -- that the taper depends on. Where the ladder is a single tier
        -- the anchor is 0 and this reduces to the old formula exactly.
        count_formula = terminal
          and string.format("%s + %s*(L-%d)",
                            50 * multiplier * (start_level - 1),
                            1000 * multiplier, start_level - 1)
          or ("L*" .. (50 * multiplier)),
        ingredients = ingredients,
        time = terminal and 60 or 30,
      },
      order = string.format("z-ltr-%03d", i),
    }
    previous_name = name
  end

  data:extend(techs)
end

-- ---------------------------------------------------------------------------
-- The ltr-outpost-grants chain: one tech per tier, mirroring the grants
-- bands. Level i raises the force's cap of concurrent disconnected Deed
-- outposts to i (runtime accounting in scripts/outposts.lua). Costs climb
-- 1000 science per level over the cumulative pack list of tiers 1..i —
-- deliberately steep; an outpost slot is a strategic purchase, not a level
-- of income.

local function build_outposts(bands, unlock_of)
  if #bands == 0 then return end
  local cumulative = {}
  local previous_name
  local techs = {}

  for i, band in ipairs(bands) do
    for _, pack in ipairs(band.packs) do
      cumulative[#cumulative + 1] = { pack.name, 1 }
    end
    local name = "ltr-outpost-grants-" .. i
    local prereqs = append_band_prereqs(band, unlock_of,
      previous_name and { previous_name } or {})

    techs[#techs + 1] = {
      type = "technology",
      name = name,
      icon = "__land-title-registry__/graphics/survey-stake.png",
      icon_size = 64,
      upgrade = true,
      max_level = i, -- the -i suffix is the start level: one level per tech
      prerequisites = #prereqs > 0 and prereqs or nil,
      ignore_tech_cost_multiplier = true,
      unit = {
        count = math.max(1, math.floor(i * 1000 * multiplier + 0.5)),
        ingredients = table.deepcopy(cumulative),
        time = 60,
      },
      order = string.format("z-ltr-outpost-%03d", i),
    }
    previous_name = name
  end

  data:extend(techs)
end

-- Pack discovery runs regardless of the override: the override pins the
-- BANDING, but science-unlock prerequisites always come from the real DAG.
local packs = collect_packs()
local unlock_of = {}
for _, pack in ipairs(packs) do unlock_of[pack.name] = pack.unlock_tech end

local override = settings.startup["ltr-tech-tiers"].value
local bands
if override ~= "" then
  bands = parse_override(override)
else
  bands = band_packs(packs)
end
build_ladder(bands, unlock_of)
build_outposts(bands, unlock_of)
