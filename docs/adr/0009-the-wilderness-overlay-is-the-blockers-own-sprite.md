# The wilderness overlay is the blocker's own sprite

Wilderness cells render a translucent red-ribbon overlay (diagonal ribbons, a faint wash, and a cell-edge border). It is implemented with **zero render objects and zero rendering code**: the pattern is simply the `fh-cell-wilderness` blocker's `picture`, a 1024×1024 sprite drawn at scale 1 on the `floor` render layer — exactly one 32-tile cell.

The blocker entity already exists on precisely the set of cells that need the overlay, is created and destroyed on exactly the right transitions (chunk generation, claims, downgrades, surface disabling, `/fh-rebuild`), and is engine-rendered with entity culling for free. Any render-object implementation would have re-tracked all of that lifecycle by hand — per wilderness cell, which is O(explored area), the exact cost model the frontier-only border design (M3) exists to avoid. Claimed states stay visually unmarked at the entity level: Trail and Rampart blockers carry no picture, so claimed land looks normal, and M3's frontier borders remain the claim-side visual system.

The stripe period divides the sprite size, so the pattern continues seamlessly across adjacent wilderness cells; the baked-in cell-edge border is what makes individual cells readable — needed because nothing else in M1 shows where a cell begins and ends.

Consequences:

- The overlay appears only where chunks are generated and visible (fog hides it), and only in world/zoomed remote view — the blocker carries `not-on-map`, so chart view stays uncolored. Map-view territory display arrives with M3's chart renders.
- The sprite is generated, not hand-drawn: `tools/gen_overlays.py` (Pillow) writes the overlay PNGs. Regenerate rather than editing the PNG.
- Do not "optimize" the overlay into scripted renders. *(Amended after M3, by user request: Trail and Rampart blockers now carry their own subtle overlays — steel-blue opposite-diagonal lanes and amber crosshatch, far fainter than wilderness — via the same mechanism. Deed cells remain overlay-free: full rights look like normal land. `tools/gen_overlays.py` generates all three.)*
