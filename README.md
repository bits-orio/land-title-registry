# Land Title Registry

**Land rights, earned cell by cell.**

Land Title Registry divides the map into square **cells** (24 tiles by default; 16 and 32 available via startup setting) and puts each one on a four-state ladder. Land stops being binary — you don't own a chunk or not, you hold a particular *right* over it, and you buy your way up.

Built from the ground up, and designed first for **[Multi-Team Support](https://mods.factorio.com/mod/multi-team-support)** servers — many teams, isolated surfaces, staged starts — while running perfectly well standalone in vanilla single-player with nothing else installed.

| State | What you may build | Cumulative price |
|---|---|---|
| **Wilderness** | Nothing buildable. (Vehicles remain deployable anywhere.) | 0 |
| **Trail** | Belts, rails, pipes | 1 |
| **Rampart** | Everything Trail permits, plus turrets, walls, gates, radar, poles, solar, accumulators | 3 |
| **Deed** | Everything, including artillery turrets | 5 |

Rights are enforced by the **engine**, not by a script watching build events. Custom collision layers put every buildable prototype into exactly one class, and one indestructible blocker entity per unclaimed cell denies the layers that cell hasn't earned. Manual placement, blueprints, and construction robots are all governed identically, for free. A Deed cell has no blocker at all — full rights are represented by absence.

Movement is never restricted. You can walk, drive, and railroad through Wilderness freely; only construction is gated.

## Playing

Everything happens through one item: the **survey tool**, available from the shortcut bar. It has four drag modes:

| Drag | Action |
|---|---|
| select | Claim Trail on every Wilderness cell in the rectangle |
| alt-select | Claim or upgrade to Deed |
| alt-reverse-select | Claim or upgrade to Rampart |
| reverse-select | Downgrade one step, with a partial refund |

Batches are **all-or-nothing** — if you can't afford the whole drag, nothing is applied and the shortfall is shown. Prices are flat, with full credit for rights you already hold: an incremental path never costs more than a direct one. The tool works in map view, so territory can be managed remotely.

Land points come from the `ltr-land-grants` research chain, which ends in an infinite technology with a **linear** cost curve — so late-game income tapers but never stops. Forces also get a starting grant, and a one-time settlement charter the first time they reach each planet.

New claims must touch land you already hold. That's checked only when you claim; territory that later gets disconnected stays yours.

### The causeway

Trail-claim a line of cells across a lake — a claim doesn't need buildable ground — landfill a causeway, and run rail across. Water stops being a wall. Land Title Registry never gates tiles, so the landfill was always free; it's the rails that need Trail rights.

## More than a claim grid

Engine-enforced land claiming is the starting premise, not the feature list. What sits on top of it:

**Rights, not ownership.** Four states instead of two, so a cell can be a transport corridor without being a fortress. Prices are flat with full credit for what you already hold, which makes the total to reach a state path-independent — Trail → Deed costs exactly what Trail → Rampart → Deed costs, so nobody routes through a tier "for the discount".

**Land is reversible.** Right-drag lowers a cell a rung and refunds part of the price. A cell can only shed a right nothing on it is using, so the check is about what you built, not what you paid.

**Adjacency you can see.** New claims must touch land you already hold — a visible, binary, claim-time rule, deliberately *not* folded into the price as a hidden discount. Territory that later gets disconnected stays yours; there is no flood-fill and no revocation.

**A race, recorded per cell.** Every cell keeps a **chronicle**: the teams that have deeded it, ranked by how fast they did it on *their own team clock*, so MTS staged starts stay fair. Standings draw on the map in each team's own color. Only two things are celebrated — being first to Deed a cell, and taking its fastest record from someone — because placing third is not an achievement.

**Multi-force and multi-surface correctness as a design pillar.** State is keyed by force *and* surface. `on_player_changed_force` is a first-class refresh trigger, `reset_force` is implemented and exercised from day one so a recycled team slot never inherits the last occupant's balance, and every global effect iterates all forces.

**Space Age, fully.** Technology tiers derive from the actual tech tree rather than a hardcoded science-pack list, so overhaul mods work. Each force gets a one-time settlement charter the first time it reaches a new planet, and space platforms are exempt from the grid entirely.

**Borders that scale.** Only *frontier* edges are drawn — where two adjacent cells differ in state. A contiguous region costs render objects proportional to its perimeter, not its area, which matters when MTS multiplies surfaces by team count.

**Nothing hardcoded about other people's mods.** Layer membership is capability-based, then overridable by mod authors through a `mod-data` prototype and by hosts through startup settings. No blacklist of third-party entity names lives in this repo, and none ever will.

**Built to be built on.** Thirteen remote functions and three custom events, stable from v1 — plus Discord milestone relay through [Open Discord Bridge](https://mods.factorio.com/mod/open-discord-bridge).

## Compatibility

Multi-Team Support is what this was designed around; everything still runs without it. It works in vanilla single-player with nothing else installed, and it ships **no incompatibility list** — composability is the point.

- **[Multi-Team Support](https://mods.factorio.com/mod/multi-team-support)** — the primary target, still optional. When present, Land Title Registry consumes `mts-v1` directly: team colors and leader labels on borders and standings, per-team clocks for chronicle rankings, points reset when a team slot is recycled, territory stats for scoreboards. Integration flows one way — MTS ships no compat shim for Land Title Registry, and if it ever needs one, that is a bug here.
- **[Open Discord Bridge](https://mods.factorio.com/mod/open-discord-bridge)** — optional. Milestone events (settlement charters, first Deed on a planet) are relayed to Discord. Low-frequency by default; per-claim spam is not.
- **Space Age** — optional, fully supported. Planet-science tech tiers, per-planet settlement charters, and space platforms exempt from the grid entirely.

**Known limitation, stated plainly:** blocker collision is global per surface. On a surface where *multiple forces build*, the engine cannot tell them apart — a Deed cell has no blocker, and an absent blocker blocks nobody. v1 targets the one-building-force-per-surface model, which covers vanilla play and MTS's per-team surface isolation exactly. Script-side cross-force exclusion on shared surfaces is out of v1 scope.

## For mod authors

Land Title Registry is built to be built on. The `land-title-registry` remote interface is stable from v1 — points get/set/add, `reset_force`, programmatic claim and downgrade, cell queries, territory stats, per-surface enablement — and three custom events (`on_cell_claimed`, `on_cell_downgraded`, `on_points_changed`) are resolvable via `get_event_id`. See [docs/API.md](docs/API.md).

Layer membership is yours to override, without waiting for a Land Title Registry release: declare your entities' layers through a `mod-data` prototype at data stage, and server hosts override anything with startup settings. Precedence is defaults < mod-data declarations < host settings. No hand-maintained blacklist of other people's entity names lives in this repo, and none ever will.

## Credit

> Inspired by [Gridlocked](https://mods.factorio.com/mod/gridlocked) by _CodeGreen — reimagined from scratch with tiered land rights, a land economy, and first-class Multi-Team Support integration.

Gridlocked demonstrated that this genre works at all: that engine-enforced, chunk-scale land claiming is a real mechanic, and that a linear-cost terminal infinite technology is the right shape for land income. Those two ideas are consciously retained, with thanks to its author.

Everything else here is original. Land Title Registry is a ground-up build — no code, no assets, no names are reused, though Gridlocked's MIT license would have permitted it.

## Development

| | |
|---|---|
| Design document | [DESIGN.md](DESIGN.md) — the full spec |
| Domain glossary | [CONTEXT.md](CONTEXT.md) |
| Decisions | [docs/adr/](docs/adr/) |
| Coding invariants | [.claude/skills/ltr-invariants.md](.claude/skills/ltr-invariants.md) |

```bash
./link-mod.sh        # symlink this checkout into every local Factorio mods dir
./tools/release.sh   # tag a release (GitHub Actions builds, publishes, uploads)
```

## License

GPL-3.0. See [LICENSE](LICENSE).
