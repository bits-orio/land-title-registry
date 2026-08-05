# Freehold

**Land rights, earned cell by cell.**

Freehold divides the map into square **cells** (16 tiles by default; 32 available via startup setting) and puts each one on a four-state ladder. Land stops being binary — you don't own a chunk or not, you hold a particular *right* over it, and you buy your way up.

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

Land points come from the `fh-land-grants` research chain, which ends in an infinite technology with a **linear** cost curve — so late-game income tapers but never stops. Forces also get a starting grant, and a one-time settlement charter the first time they reach each planet.

New claims must touch land you already hold. That's checked only when you claim; territory that later gets disconnected stays yours.

### The causeway

Trail-claim a line of cells across a lake — a claim doesn't need buildable ground — landfill a causeway, and run rail across. Water stops being a wall. Freehold never gates tiles, so the landfill was always free; it's the rails that need Trail rights.

## Compatibility

Freehold is standalone-first. It works in vanilla single-player with nothing else installed, and it ships **no incompatibility list** — composability is the point.

- **[Multi-Team Support](https://mods.factorio.com/mod/multi-team-support)** — optional. When present, Freehold consumes `mts-v1` directly: team colors on borders, points reset when a team slot is recycled, territory stats for scoreboards. MTS ships no compat shim for Freehold; integration flows one way.
- **[Open Discord Bridge](https://mods.factorio.com/mod/open-discord-bridge)** — optional. Milestone events (settlement charters, first Deed on a planet) are relayed to Discord. Low-frequency by default; per-claim spam is not.
- **Space Age** — optional, fully supported. Planet-science tech tiers, per-planet settlement charters, and space platforms exempt from the grid entirely.

**Known limitation, stated plainly:** blocker collision is global per surface. On a surface where *multiple forces build*, the engine cannot tell them apart — a Deed cell has no blocker, and an absent blocker blocks nobody. v1 targets the one-building-force-per-surface model, which covers vanilla play and MTS's per-team surface isolation exactly. Script-side cross-force exclusion on shared surfaces is out of v1 scope.

## For mod authors

Freehold is built to be built on. The `freehold` remote interface is stable from v1 — points get/set/add, `reset_force`, programmatic claim and downgrade, cell queries, territory stats, per-surface enablement — and three custom events (`on_cell_claimed`, `on_cell_downgraded`, `on_points_changed`) are resolvable via `get_event_id`. See [docs/API.md](docs/API.md).

Layer membership is yours to override, without waiting for a Freehold release: declare your entities' layers through a `mod-data` prototype at data stage, and server hosts override anything with startup settings. Precedence is defaults < mod-data declarations < host settings. No hand-maintained blacklist of other people's entity names lives in this repo, and none ever will.

## Credit

> Inspired by Gridlocked by _CodeGreen - reimagined from scratch with tiered land rights, a land economy, and first-class Multi-Team Support integration.

Gridlocked is MIT licensed and reuse would be permitted, but Freehold deliberately reuses nothing — no code, no assets, no names. Two ideas are consciously retained: engine-enforced, chunk-scale land claiming with one blocker entity per unit of land, and a linear-cost terminal infinite technology. Everything else diverges.

## Development

| | |
|---|---|
| Design document | [FREEHOLD_DESIGN.md](FREEHOLD_DESIGN.md) — the full spec |
| Domain glossary | [CONTEXT.md](CONTEXT.md) |
| Decisions | [docs/adr/](docs/adr/) |
| Coding invariants | [.claude/skills/freehold-invariants.md](.claude/skills/freehold-invariants.md) |

```bash
./link-mod.sh        # symlink this checkout into every local Factorio mods dir
./tools/release.sh   # tag a release (GitHub Actions builds, publishes, uploads)
```

## License

GPL-3.0. See [LICENSE](LICENSE).
