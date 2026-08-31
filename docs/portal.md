# Land Title Registry

> Land rights, earned cell by cell.

[![Discord](https://img.shields.io/badge/Discord-join%20the%20server-5865F2?logo=discord&logoColor=white)](https://discord.gg/tWz4FT74pH) [![GitHub](https://img.shields.io/badge/GitHub-source-181717?logo=github&logoColor=white)](https://github.com/bits-orio/land-title-registry)

Land Title Registry divides the map into square cells, each on a four-state ladder: Wilderness, Trail, Rampart, Deed. You don't own a cell or not — you hold a particular *right* over it, and you buy your way up. The engine itself enforces what you may build where, so manual placement, blueprints and bots are governed identically.

It runs standalone in vanilla single-player, with optional [Multi-Team Support](https://mods.factorio.com/mod/multi-team-support) integration for servers running many teams on isolated surfaces.

## Status

Playable and in active development: everything below is shipped and exercised in game, but it is young and has rough edges, and bug reports are genuinely wanted — discussion tab or [GitHub issues](https://github.com/bits-orio/land-title-registry/issues).

One limitation up front: blocker collision is global per surface, so where *multiple forces build on one surface* the engine cannot tell them apart — a Deed cell carries no blocker, and an absent blocker blocks nobody. v1 targets the one-building-force-per-surface model, which covers vanilla play and Multi-Team Support's per-team surface isolation; cross-force exclusion on shared surfaces is out of scope.

## Quick start

1. Install it and start a game; nothing else is needed.
2. Open the **survey tool** from the shortcut bar.
3. Drag across cells touching land you hold to raise each a rung; shift-drag jumps straight to Deed.
4. Right-drag lowers a cell for a partial refund; shift + right-drag sells back to Wilderness.
5. Research the land grants chain for more points — it ends in an infinite technology with a *linear* cost curve, so late-game income tapers but never stops.

Movement is never restricted: walk, drive and railroad through Wilderness freely, only construction is gated. The tool works in map view.

## Features

- **Rights, not ownership.** Wilderness permits elevated rails only, so viaducts fly over unowned land; Trail adds belts, rails and pipes; Rampart turrets, walls, radar and power; Deed everything.
- **Enforced by the engine, not a script.** Collision layers class every buildable prototype, and one indestructible blocker per unclaimed cell denies the layers it hasn't earned, so blueprints and bots obey for free.
- **Prices that don't punish the scenic route.** Flat costs with full credit for rights you hold, so Trail to Deed costs what Trail to Rampart to Deed costs, and lowering a cell refunds part of it.
- **Adjacency you can see.** New claims must touch land you already hold — checked at claim time only, never folded into the price as a hidden discount. Territory later cut off stays yours.
- **Outpost grants.** Research permits Deeds founded anywhere in the wilderness with no adjacency, one concurrent outpost per level; the slot returns once that territory connects with your mainland.
- **A race, recorded per cell.** Each cell keeps a chronicle of the teams that have deeded it, ranked on *their own team clock* so staged starts stay fair. Being first, and taking the record, are the only things celebrated.
- **The causeway.** Trail-claim a line of cells across a lake — a claim needs no buildable ground — landfill it, and run rail across. Water stops being a wall.
- **Built to be built on.** Thirteen remote functions and three custom events, stable from v1; other mods declare their entities' layers through a `mod-data` prototype.

## Compatibility

No incompatibility list ships with it — composability is the point. Cells are 24 tiles by default, 16 and 32 at startup, and each player remaps gestures and restyles borders.

**Space Age** is optional and fully supported: tech tiers derive from the real tech tree, not a hardcoded science-pack list, so overhaul mods work; each force gets a settlement charter on first reaching a planet; space platforms are exempt.

Inspired by [Gridlocked](https://mods.factorio.com/mod/gridlocked) by _CodeGreen and reimagined from scratch — no code, no assets and no names reused, though Gridlocked's MIT license would have permitted it. _CodeGreen was told before this shipped and welcomed it.

## Works with

- [Multi-Team Support](https://mods.factorio.com/mod/multi-team-support) — optional. Team colors and leader labels on borders and standings, per-team clocks for chronicle rankings, points reset when a slot recycles.
- [Open Discord Bridge](https://mods.factorio.com/mod/open-discord-bridge) — optional. Milestones such as settlement charters and a first Deed on a planet reach your Discord channel.
- [Diggy](https://mods.factorio.com/mod/diggy) — also standalone, also Multi-Team Support aware, also about earning the ground you build on.

## Links

- [Full README](https://github.com/bits-orio/land-title-registry/blob/master/README.md) — the tier table in full, every gesture, the reasoning behind each rule
- [Remote interface and events](https://github.com/bits-orio/land-title-registry/blob/master/docs/API.md) for mod authors
- [Community Discord](https://discord.gg/tWz4FT74pH)

## Development

Developed with AI coding assistants alongside human review and in-game testing. Issues and pull requests are welcome on [GitHub](https://github.com/bits-orio/land-title-registry).

License: MIT
