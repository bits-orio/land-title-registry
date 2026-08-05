# The cell chronicle is a per-cell speedrun leaderboard, not a first-come log

Every (planet, cell) keeps a chronicle: the teams that have deeded that cell, ranked by **how fast** they did it on **their own team clock** — not by who got there first in wall time. The top three render as tiny gold/silver/bronze text lines under the cell's top edge (centered) on every surface of that planet, so each team sees the standings on its own copy. This ships the v2 "ghost borders" idea, sharpened, pulled into v1 by the designer during playtesting.

Two semantics matter and both came from the designer directly:

- **Fastest, not first.** A speedrunning team that starts later but deeds cell (x, y) in less team-clock time *rightfully displaces* earlier entries, and the drawn rankings re-sort to match. (This also reframes the old "newer records overshadow older ones" rejection: that was about *points* being keyed to unstable records — the chronicle is celebration and standings only, no points, so displacement is the feature, not the instability.)
- **Team clocks, absolute fallback.** Times are measured from each team's own clock (`mts-v1` `get_team_info().clock_start_tick` — the getter already existed; zero MTS changes), which keeps MTS staged starts fair. Without MTS, or for non-team forces, times are absolute game time.

Mechanics:

- A team's time is set by its **first** Deed of the cell; re-deeding later never improves it. Entries are achievements: they are keyed by planet (not surface), survive downgrades and surface clears, and merge best-time-wins on force merges.
- Recognition (flying text for the actor, one force-chat line with placement) fires only when the cell has **at least two** entries — vanilla single-force play keeps the quiet personal log without "Fastest!" spam on every deed.
- Rendering follows the derived-state discipline: chronicle text objects rebuild through the same reconcile path as blockers and borders (`/fh-rebuild`, surface sweeps, re-enables), with their own bookkeeping so frontier refreshes never clobber them.
- Display names resolve at draw time through the `mts-v1` provider, so team renames stay current.
