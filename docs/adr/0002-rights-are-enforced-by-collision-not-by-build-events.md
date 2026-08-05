# Building rights are enforced by collision masks, not by build-event policing

Three custom collision layers (`fh-land`, `fh-transit`, `fh-rampart`) partition every player-creation prototype into exactly one layer at data stage, plus a fourth (`fh-cell-tile`) gating tile placement. One neutral, indestructible blocker entity per non-Deed cell carries the mask denying the not-yet-earned layers. A Deed cell has no blocker at all — full rights are represented by absence.

Why this and not an `on_built_entity` handler that validates and destroys:

- Manual placement, blueprints, and construction robots are all governed identically, for free, with no handler to keep in sync.
- There is no per-build script cost, which matters because MTS multiplies surfaces by team count.
- Movement is untouched: the blocker masks contain only Freehold's custom layers, no engine movement layers, so characters, vehicles, trains, and enemies traverse every state freely. Only construction is gated.

Accepted consequences:

- **Masks are fixed at prototype-load time.** Layer membership is decided entirely at data stage; both override channels (host startup settings, the cross-mod `mod-data` convention) are therefore startup-scope. There is no runtime API to move an entity between layers, and none should be promised.
- **Script `create_entity` bypasses collision** unless the caller opts into `build_check_type`. Spawns from other mods sit outside any enforcement model that isn't event policing, and Freehold accepts that.
- **Blocker collision is global per surface.** On a surface where multiple forces build, an absent blocker blocks nobody, so v1 targets the one-building-force-per-surface model — which covers vanilla play and MTS's per-team surface isolation exactly. Documented plainly rather than papered over.

Exactly one script-side check survives: the single `find_entities_filtered` area query validating a downgrade. Any other build inspection is a bug.
