# The `fh-land-grants` tier ladder is derived from the technology DAG, never hardcoded

Freehold's income chain never names a science pack as a constant. The tier ladder is computed in `data-final-fixes.lua` from the technology graph actually present in the running mod set, with a startup string setting (`fh-tech-tiers`) as a host override.

The obvious implementation — writing `automation-science-pack`, `logistic-science-pack`, … into each tier's `unit.ingredients` — is not merely suboptimal under overhaul mods. It ranges from wrong to fatal:

- **Krastorio2** keeps the vanilla packs and adds four of its own, so a vanilla chain loads but places tiers at the wrong depths.
- **Periodic Madness** keeps `automation`, `logistic`, and `chemical` but interleaves eight of its own between them — `pm-advanced-advanced-transition-metal-science-pack` comes *before* chemical — so a vanilla ordering misrepresents the progression outright.
- **Ultracube** replaces science entirely: `cube-basic-contemplation-unit`, `cube-fundamental-comprehension-card`, and so on. No vanilla pack prototype exists. A chain naming one in `unit.ingredients` references a nonexistent prototype — a data-stage crash, or at best an unresearchable chain and a dead income faucet for the whole game.

Since land points are Freehold's only recurring faucet, a dead chain is not a degraded experience; it is an unplayable mod.

The derivation (implemented and engine-verified 2026-08-05): collect every `tool` prototype used in some technology's `unit.ingredients`; compute availability depth from producing recipes' unlock techs (excluding recycling-category and self-producing recipes — Space Age's self-recycling would flatten every depth to 0); sort by depth then name; band by **DAG comparability** — a pack joins the current tier iff its unlock tech and every member's are mutually non-ancestral and it sits within a small depth span (`BAND_SPAN = 4`) of the tier start; the terminal band takes every pack with `max_level = "infinite"` and a linear `count_formula`. Comparability is the primary signal because depth gaps alone are contradictory (the same gap of 3 must merge production+utility and split utility|space in 2.0.77). Verified output: 6 tiers under vanilla, 9 under Space Age, preserving every intended grouping; automation and logistic split because base 2.0 genuinely orders them in the DAG.

The name tiebreak in the sort is load-bearing, not cosmetic — it makes the ladder deterministic rather than dependent on `pairs()` iteration order.

## Consequences

- The vanilla and Space Age tier tables in the design document are the **expected output** of the derivation, and are asserted by tests rather than written into the source.
- Under Space Age, the three inner-planet packs (metallurgic, agricultural, electromagnetic) land in one tier. This is also the right answer independently: Vulcanus, Fulgora, and Gleba are completed in any order, but `unit.ingredients` is a conjunction with no "any one of" form, so a per-planet chain would pick an arbitrary order and stall a force's entire income for visiting Fulgora first.
- `fh-tech-tiers` (startup, string, default empty) pins the ladder explicitly when the derivation gets a novel tech tree wrong: semicolon-separated tiers, each a comma-separated cumulative pack list. Same philosophy as the layer-membership overrides — the host always has the final word, and no Freehold release is needed to fix a third-party tech tree.
- Changing the ladder's shape after release reshapes technology prototypes and invalidates in-progress research, so it ships in M2 rather than being retrofitted.
