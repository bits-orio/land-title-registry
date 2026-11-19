# Spike: pre-selection events of a selection tool (Factorio 2.1.25)

Question: a selection tool with `send_pre_selection_events = true` raises
`on_player_start_selected_area`, `on_player_change_selected_area` and
`on_player_cancel_selected_area` while the player drags. How often do they
fire, what do they carry, how does a drag end, do they arrive the same on a
server and its client, and what does `draw_selection_counts` draw?

Measured 2026-11-18 on 2.1.25 (build 88022) with the probe mod in this
folder, in a graphical client at 1920x1080 on a private display: one
single-player session and two sessions of a headless server with one client.
The drags, grouped by `analyze.py`, and the raw lines quoted here are in
`recorded-drags-2.1.25.txt`. The prototype check also ran on 2.1.23
(build 87750).

## How often

| Drag | Change events |
|---|---|
| 60 mouse steps of 5 pixels (0.16 tile) in 3.5 s | 60, two to four ticks apart |
| 10 steps, then the button held still for 3 s | 10. None while the mouse is still. |
| One jump across the screen | 1, then the final event |
| The same distance in 5 steps | 5 |
| 20 small moves inside one tile | 20, each with `tiles=1` |
| About 100 x 100 tiles at zoom 0.3 | 12, the tiles table growing from 90 to 10201 |

A change event fires for every mouse movement that moves the dragged
rectangle, not once per tile crossed. No two ever shared a tick.

## What an event carries

Start, change, cancel and the final events all have the same keys: `area`,
`cursor_position`, `entities`, `item`, `name`, `player_index`, `position`,
`quality`, `selection_mode`, `surface`, `tick`, `tiles`.

- `area` is the rectangle as dragged, not snapped to tiles. `position` is
  where the drag started, `cursor_position` where the cursor is.
- The start event has a point for an area, `tiles=1` in a tile mode and no
  entities.
- A tile mode fills `tiles`, an entity mode fills `entities`; the other
  table is empty.
- `selection_mode` reads 1 for select (left button), 2 for alt_select
  (Shift and left), 4 for reverse_select (right), 5 for alt_reverse_select
  (Shift and right).
- Reading `position` of every tile in a handler: 0.03 ms for 90 tiles,
  0.58 ms for 1190, 1.4 ms for 5776, 4.5 ms for 10201.

## How a drag ends

| What the player does | Events |
|---|---|
| Releases the button | The final event of the mode (`on_player_selected_area` and its three siblings) |
| Presses Q during the drag (the cursor is cleared) | `on_player_cancel_selected_area` with the full fields. Releasing the button afterwards raises nothing. |
| Presses Escape, multiplayer | `on_player_cancel_selected_area`. The survey tool's later run (`dev/run-drag.sh`, ADR-0015) found that it comes when the button is released under the game menu, not at the key press. |
| Presses Escape, single player | The game menu opens and no event comes while it is open. After a second Escape the drag goes on and ends with a normal final event. |
| Presses the right button during a left drag | No cancel and no new start. A change event arrives with the origin moved to the cursor (`position` changes, the area is a point, `tiles=1`), and the final event uses the new origin. |

## Server and client

The handlers wrote synced state on every change event: a counter in
`storage`, a render rectangle destroyed and drawn again, and a local flying
text. Both peers logged the same event lines, tick for tick (89 lines in the
first session, 145 in the second), the counters matched at the end
(count=140 on both), and neither log has a desync line.

The second session set `minimum-latency-in-multiplayer=250` in the client's
config. The client log shows the same `latency(32)` line as without it, and
the first event reaches the log within a second of the first mouse press in
both sessions. So what real latency does to these events is not measured here.
`dev/run-drag.sh` measures it for the survey tool, with a latency the server
imposes (docs: ADR-0015).

## draw_selection_counts

`selection-counts.png` shows the area at the cursor in the middle of four
drags, from the left: right button (entities, counts on), Shift and right
(entities, counts off), left button (tiles, counts on), Shift and left
(tiles, counts off). With counts on, the entity mode draws the entity's icon
with the number selected (126 chests) at the cursor. With counts off it draws
nothing. The two tile modes look the same: no count either way. The blue
square with a 1 is in all four. The red rectangle is the probe's own.

At runtime (`recorded-proto-2.1.25.txt`):
`LuaItemPrototype.get_draw_selection_counts(mode)` returns what the
prototype set on 2.1.25. On 2.1.23 the method does not exist
(`LuaItemPrototype doesn't contain key get_draw_selection_counts.`), while
the prototype with `draw_selection_counts` still loads. The two event ids
exist on both (224 and 225). `send_pre_selection_events` cannot be read at
runtime on either.

Not measured: a second client, lost packets, a save loaded in the middle of
a drag, more than 60 mouse moves a second.

## Rerun

```
dev/spikes/preselection/run.sh               # headless: the prototype check
dev/spikes/preselection/run.sh sp            # a graphical client, single player
dev/spikes/preselection/run.sh mp [ticks]    # a headless server and one client
```

The headless check compares its lines with `recorded-proto-2.1.25.txt`:
exit 0 when they match, 2 when they differ, 1 when it did not finish. Rerun
after the move into this repo on 2.1.25: same lines.

`sp` and `mp` start one graphical client on a private display (about 2 GB of
memory, one at a time on a machine) and need xdotool. `sp` prints the drags
to hold against `recorded-drags-2.1.25.txt` and saves mid-drag screenshots;
`mp` says whether server and client logged the same event lines. Neither was
rerun after the move: only their syntax was checked.
