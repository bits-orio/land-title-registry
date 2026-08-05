# Territory grows by a single whole-rectangle anchor test

A survey-tool batch either anchors or it doesn't, and there is no partial case. A batch is **anchored** if the drag rectangle contains or shares an edge with a cell the acting force already owns in any state, **or** — when the force owns nothing at all on that surface — if the rectangle contains the cell the acting player is standing in. An anchored batch claims every eligible Wilderness cell in the rectangle; an unanchored one claims nothing and says so, with the denial sound and flying text.

Three decisions are folded into that one sentence, and each looks like something else in the source.

**There is no breadth-first search, despite the rule being progressive evaluation.** A rectangle of cells is always orthogonally connected, and every cell in it is either owned by the acting force (a valid adjacency source) or Wilderness (a claim candidate). A breadth-first walk outward from existing territory therefore always reaches either the whole rectangle or none of it. Since reachability is order-independent by construction, progressive adjacency does not reintroduce the iteration-order dependence that partial application was rejected for — the check collapses honestly to one containment-or-edge-share test. Do not "restore" a BFS here; it would compute the same answer more slowly.

**Adjacency is 4-way, never diagonal.** Trail exists to carry belts, rails, and pipes, and transport is rook-connected: two cells touching only at a corner can pass nothing between them. 4-way makes the claim rule isomorphic to the physical rule, so a claimable direction is always a buildable direction. 8-way would permit diagonal Trail "corridors" that read as corridors on the map and carry nothing.

**The standing-cell clause is seeding and recovery at once.** The two obvious first-claim mechanisms both have holes: exempting "the first claim" silently exempts the first *drag*, letting a force plant its entire starting balance anywhere on the map from map view; and auto-granting the spawn cell breaks on Space Age, where a cargo pod need not land anywhere near `force.get_spawn_position(surface)`, stranding the arriving player in Wilderness beside a cell they cannot reach. Anchoring on the acting player's own cell when the force owns nothing on the surface seeds Nauvis at spawn, seeds each planet where the force actually lands, and un-sticks a force that downgraded away its last cell — without once-per-planet bookkeeping and without a second code path.

## Consequences

- A drag anchored on one edge cell claims the whole rectangle in one gesture: a 1×40 corridor costs 40 points, a 20×20 rectangle costs 400. Affordability is the limiter, not geometry, and all-or-nothing means the whole rectangle is bought or nothing is.
- Seeding requires the acting player to be physically present, so the mechanism rewards travelling rather than scouting from map view.
- The remote `claim` function may have no acting player. On a surface where the force owns nothing it refuses with reason `"no-anchor"` unless the caller passes `opts.ignore_adjacency = true` — the only sanctioned bypass, intended for scenario and quest mods that seed territory deliberately.
