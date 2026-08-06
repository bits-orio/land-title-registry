# The survey tool is two gestures: drag raises one rung, right-drag lowers

Playtesting verdict: four modifier-gesture combinations (drag / Shift-drag / right-drag / Shift-right-drag, each mapped to a different tier action) is a memory test, not an interface. Nobody guessed them, and the rampart binding (Shift+Right) was effectively undiscoverable.

The replacement leans on an invariant the economy already guarantees: **full credit makes stepping and jumping cost the same** (every route to a state totals the same points — ADR-0004). The four-mode tool existed to let players jump straight to a tier, but jumping saves nothing, so the modes were solving a problem the pricing had already solved. The advertised interaction is now:

- **Drag** — every covered cell rises **one rung** (Wilderness → Trail → Rampart → Deed; Deeds no-op). Mixed rectangles behave naturally: each cell steps from wherever it is.
- **Right-drag** — every eligible covered cell lowers one rung, with the partial refund.

"Left raises land, right lowers it." The Shift variants remain wired as **unadvertised accelerators** (Shift-drag jumps to Deed, Shift-right-drag to Rampart, both with full credit) — power-user shortcuts, not required knowledge. The remote `claim` API keeps explicit `target_state`; scripts have no gesture problem.

Onboarding ships with the same change (all engine-native surfaces):

- A **first-join welcome panel** (screen GUI, once per player) with the ladder in two lines, the live keybind via the `__CONTROL__ltr-get-survey-tool__` locale macro, and a give-me-the-tool button.
- **Tips-and-tricks entries** (category + three items, time-triggered) in the built-in Tips window.
- **A free starter cell**: at a force's first presence on each planet, the cell the player is standing on is granted as Trail (invested 0). This partially reverses ADR-0006's rejection of auto-granting the spawn cell — the objection there was that Space Age cargo pods land far from `get_spawn_position`, and granting at *presence position* dissolves it. The standing-cell anchor clause remains as the recovery path. The grant makes the cell grid visible immediately and shows exactly where growth begins; the known 0.25-point refund leak on downgrading a granted cell is accepted.
- **Surface-drawn gesture hints** at the home starter cell (per-force render texts), destroyed on the force's first paid claim.

The survey tool also gets its own planner-style icon (generated: parchment card, green band, 2×2 grid with a deeded cell and a stake) instead of the borrowed landfill icon — tier identity on the shortcut bar, planner identity in the hand.
