# Tiles are not gated; enforcement is entity-layer only

Land Title Registry places no collision layer on any tile prototype and sets no flag on one. Landfill, concrete, stone path, and foundation place and mine identically in every cell state, Wilderness included. An earlier design gated them with a fourth collision layer, `ltr-cell-tile`, added to every player-placeable tile's mask together with `check_collision_with_entities = true`. That mechanism was cut before implementation.

`check_collision_with_entities` is a per-prototype boolean. It cannot be scoped to a single layer — it tests the tile's *entire* collision mask against nearby entities. In Factorio 2.0.77, concrete, refined concrete, stone path, and landfill all carry exactly `{ground_tile = true}`, the same mask as grass, dirt, and sand. So the flag's real blast radius is "every entity carrying `ground_tile`", not "the wilderness blocker".

That set is not empty, and the most damaging member is `fish`, whose collision mask is `{ground_tile = true}` — that layer is precisely what keeps fish out of landfill. Enabling the flag would make **landfill fail to place wherever a fish happens to be swimming**, intermittently, because fish move. The lake causeway is the design's showcase mechanic, and this would have broken it at random. Several Gleba plants and wrigglers carry the layer too, so paving on Gleba would newly require clearing plants first.

Two further problems compounded it. The engine applies the flag when *mining* a tile as well as when building one, so a cell downgraded to Wilderness would trap its concrete permanently with no way to remove it. And `data-final-fixes.lua` would have had to set the flag on every player-placeable tile in the game, **including modded tiles whose masks Land Title Registry does not control** — for a mod whose stated brand is an empty incompatibility list, the likeliest single source of one.

What the gate bought was thematic: Wilderness stays unpaved. It was never load-bearing. Landfill in a Wilderness cell yields ground the force still cannot build on, because the entity layers do all the real work — the causeway's rails are gated by `ltr-transit`, not by the tile.

## Consequences

- The `ltr-cell-tile` collision layer does not exist. Three layers ship, all entity-facing: `ltr-land`, `ltr-transit`, `ltr-rampart`.
- The wilderness blocker's mask is `ltr-land`, `ltr-transit`, `ltr-rampart`.
- Tiles never enter the downgrade validity check, and a cell returning to Wilderness keeps whatever tiles are on it, still freely mineable. This closes the open question about removing tiles on downgrade — it is moot.
- Revisit post-v1 only if playtesting shows unrestricted paving of Wilderness is a real problem, and then only with a mechanism whose blast radius stops at Land Title Registry's own prototypes.
