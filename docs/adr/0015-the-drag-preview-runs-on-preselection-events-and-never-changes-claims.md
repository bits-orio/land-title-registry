# The drag preview runs on preselection events and never changes claims

While the survey tool is being dragged, a label next to the cursor shows what releasing the button would do: the cell count and the cost, the refund, or why the drag would be refused. It is driven by the three preselection events Factorio 2.1.22 added (`on_player_start_selected_area`, `on_player_change_selected_area`, `on_player_cancel_selected_area`), which the engine sends only for a selection tool whose prototype sets `send_pre_selection_events = true`. Both survey tools set it, and `info.json` requires `base >= 2.1.22`.

Each start or change event runs the real batch evaluation as a dry run (`claims.apply_batch(..., { dry_run = true })`) for the gesture's action, so the label and the final result come from one rule set. The code is `scripts/drag_preview.lua`; the gesture-to-action mapping it shares with the final handlers is `scripts/gestures.lua`.

## What the events do (measured on 2.1.25, single player and server plus client)

- **Frequency.** A change event fires when the cursor moves with the button held, at most once per tick, and never while the mouse is still. It fires for sub-tile movement too, not once per tile crossed: 60 mouse steps in 3.5 seconds gave 60 events. It also fires when the gesture changes with the mouse still (Shift released mid-drag), carrying the new `selection_mode`.
- **Fields.** Start, change, cancel and the final events all carry `area`, `position`, `cursor_position`, `selection_mode`, `surface`, `item`, `quality`, `entities`, `tiles`. `area` is the raw dragged rectangle, not snapped to tiles. `position` is the drag origin. `selection_mode` is `defines.selection_mode`: select 1, alt_select 2, reverse_select 4, alt_reverse_select 5.
- **The origin can move mid-drag.** A right-click during a left drag does not cancel: a change event arrives with the origin reset to the cursor and no new start event. Read `position` on every event and keep nothing from the start event.
- **Cancel.** Q (clear cursor) sends the cancel event. Escape sends it in multiplayer; in single player Escape opens the game menu and the drag carries on after the menu closes. No final event follows a cancel.
- **`tiles` and `entities` are filled on every event.** Iterating `tiles` for a 100x100 drag costs about 4.5 ms, so nothing here reads them: the cells come from `area`.
- **Multiplayer.** The handlers run on the server and on every client as ordinary synced input: identical event sequences in both logs, identical `storage` and render objects, no desync, while writing `storage` and drawing on every event. The prototype docs warn that the flag costs network traffic in multiplayer, since every change is an input action.
- **Best effort.** The API docs say preselection events may be dropped or arrive out of order (after loading a save, or in multiplayer), because the selection lives on the client. None were dropped in the measured runs, but the design assumes they can be.

## Rules that follow

- **The preview only reads.** The five final selection events stay the only place a claim, a purse or a blocker changes. A dry run changes nothing; `dev/mods/ltr-test` holds it to that (registry, purse, origins, blockers and raised events are compared before and after).
- **One label per player, updated in place.** A drag sends an event per cursor movement; an object per event would pile up. The label is a render text object visible to that player only, kept in `storage.drag_preview` because render objects are game state and every peer must track the same one.
- **Every handler is idempotent.** Start and change share one handler that works from the event's own fields. The label is cleared on cancel, on every final event, when the tool leaves the cursor, on a surface change and when the player leaves, because any one of those may be the only one that arrives.
- **The dry run re-runs only when the answer can change**: when the drag covers a different cell rectangle or the gesture changes. Other change events only move the label.
- **Rectangles above 256 cells show their size without a price.** Measured dry-run cost: about 3.5 microseconds per cell for a raising gesture over generated land (100 cells 0.35 ms; cells beyond the generated map are cheaper, 400 cells reaching past it took 0.82 ms) and about 5.5 microseconds per owned cell for a lowering gesture, which searches each cell for entities (100 cells 0.56 ms, 400 cells 2.3 ms). 256 cells keeps one evaluation near 1.5 ms at worst, and it runs on cell crossings only.
- **The label sits on the side of the cursor that faces the drag origin**, over the selected box, so it stays on screen when the cursor reaches a screen edge.

## The hover tick (ADR-0005)

The change event takes over the hover feedback for a player who is dragging: `hover_tick` skips anyone with a preview up, and the label's colour says whether the purse covers the whole batch, which the hovered cell's next step never could. The scoped `on_nth_tick` itself stays. Hovering without a drag has no event (the preselection events need a held button, and `on_selected_entity_changed` cannot see Deed cells), so ADR-0005's reasoning stands for that part.

## Consequences

- If a final or cancel event is ever dropped, the label stays until the player's next drag, or until the tool leaves the cursor. Nothing else depends on it.
- An anchor-denied Deed jump on one Wilderness cell shows no label when the force has outpost slots: the final event may offer an outpost founding there (ADR-0014), and "No adjacent territory" would be wrong.
- Other mods that want the same feedback for their own selection tools can use these facts as they stand; none of them is specific to this mod.
