# Right-gestures mirror left exactly, and every gesture's action is a per-player setting

Playtest feedback on the ADR-0011 accelerators: Shift-drag jumping to Deed while Shift-right-drag jumped to *Rampart* — a raise on a lowering gesture — read as arbitrary. The requested rule is symmetry: **right does the exact opposite of left.**

The gesture grammar is now a mirror, with a color grammar to match — every raising gesture selects in a green, every lowering one in a red, stronger jumps in stronger shades:

| Left (greens) | Right (reds) |
|---|---|
| Drag: raise one rung | Right-drag: lower one rung (partial refund) |
| Shift-drag: jump to the top (Deed) | Shift-right-drag: jump to the bottom (sell everything back to Wilderness) |
| Ctrl+Shift-drag: middle jump (Rampart) | — |

Selling to Wilderness is a new claims action (`release`), all-or-nothing per cell: a cell whose entities still use any right no-ops rather than stopping at some intermediate state, so a release drag never leaves surprises. Its refund equals the sum of the step refunds — path-independence, downward (ADR-0004's credit principle, mirrored).

The middle jump has no right-side mirror because the engine has no sixth gesture, and no 2.0 fifth one: super-forced selection is a Factorio 2.1 feature. On 2.0 the prototype property is silently ignored (verified against 2.0.77) and the Rampart jump ships as a **variant survey tool** on its own rebindable custom input (default ALT+W) whose plain drag jumps to Rampart; its other gestures mirror the main defaults.

**Remapping.** The engine's gesture key-combinations are fixed, so "customizable shortcuts" (the playtest ask) is implemented one level up: five per-player dropdown settings (`ltr-gesture-*`) map each gesture to any of the five actions. Two consequences are accepted and documented in the setting descriptions:

- Selection border colors are startup prototype data and follow the **gesture**, not the remapped action.
- The variant tool is fixed-function — its whole point is a dependable Rampart jump on plain drag.

## Consequences

- `hint-already-trail` and the tips text teach the mirrored grammar; nothing advertises Shift-right as an upgrade anymore.
- The outpost confirmation intercept (ADR-0014) keys on the resolved *action* being a Deed jump, so it follows a remap.
- When the mod targets Factorio 2.1, the Ctrl+Shift gesture activates with no further code changes (the registration is guarded on the define existing).
