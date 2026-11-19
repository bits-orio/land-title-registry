#!/usr/bin/env bash
# The survey tool's drag preview under a real mouse, in multiplayer: a
# headless server and one graphical client on a private X display
# (dev/vdisplay.sh). The client drags the tool with xdotool through a list of
# scenarios while dev/mods/ltr-drag-probe logs every preselection and final
# event on both peers. Screenshots are taken mid-drag and right after each
# release or cancel, inside the latency window.
#
# The run fails on: a client that never joins, a desync or script error, a
# probe FAIL line (a label left behind, a label other players could see, a
# price that differs from what was charged), a probe line the client logged
# and the server did not, a preview label still up at the end, or a scenario
# that produced no drag events.
#
#   usage: dev/run-drag.sh [scenario ...]     (default: all; see SCENARIOS)
#   HARNESS_MP_LATENCY=<ticks>  the server keeps every client's input at
#                               least that many ticks away from its effect
#                               (12 is 0.2 s, 30 is 0.5 s; unset is localhost).
#                               It is minimum_latency_in_ticks in the server
#                               settings: the timing table shows the delay.
#   HARNESS_MP_DELAY=<ms>       the client joins through dev/udp-delay.py,
#                               which holds every packet that long each way,
#                               as dev/run-mp.sh does
#   HARNESS_RUN=<dir>   run folder (default .run/drag); screenshots go to
#                       <dir>/shots, the timing table to <dir>/lag.txt
#   FACTORIO=<path>     the binary, as for the other runners
#
# One graphical client at a time: stop other clients first. Takes about two
# minutes and 2 GB of memory.
set -uo pipefail
DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=harness-lib.sh
. "$DEV/harness-lib.sh"
# shellcheck source=vdisplay.sh
. "$DEV/vdisplay.sh"
RUN="${HARNESS_RUN:-$REPO/.run/drag}"
SHOTS="$RUN/shots"
STEPS="$RUN/steps.txt"
SIZE=1920x1080
SCENARIOS=(slow flick quick cancel-q shift right shift-right ctrl-shift short reorigin map far cancel-escape)
WANT=("$@"); [ ${#WANT[@]} -eq 0 ] && WANT=("${SCENARIOS[@]}")
SERVER=""; CLIENT=""; RELAY=""; W=""; SHOT_PIDS=()

cleanup() {
  [ -n "$CLIENT" ] && kill "$CLIENT" 2>/dev/null
  sleep 1
  [ -n "$SERVER" ] && kill "$SERVER" 2>/dev/null
  sleep 1
  kill -9 $CLIENT $SERVER 2>/dev/null
  [ -n "$RELAY" ] && kill "$RELAY" 2>/dev/null
  vdisplay_stop "$RUN"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Mouse and keyboard, each step written to $STEPS with its wall-clock time so
# dev/drag-lag.py can match it to the event it caused.

note() { echo "$EPOCHREALTIME $SCENARIO $*" >> "$STEPS"; }
move() { xdotool mousemove --window "$W" "$1" "$2"; note move "$1" "$2"; }
press() { xdotool mousedown "$1"; note press "$1"; }
release() { xdotool mouseup "$1"; note release "$1"; }
key() { xdotool key "$1"; note key "$1"; }
hold() { xdotool keydown "$1"; note hold "$1"; }
unhold() { xdotool keyup "$1"; note unhold "$1"; }
pause() { sleep "$1"; }
wheel() { local i; for i in $(seq 1 "$2"); do xdotool click "$1"; sleep 0.3; done; note wheel "$1" "$2"; }

# The capture happens when import starts; writing the PNG runs on.
shot() {
  note shot "$1"
  import -window "$W" "$SHOTS/$LABEL-$1.png" &
  SHOT_PIDS+=($!)
}

# A straight drag path: <x1> <y1> <x2> <y2> <steps> <seconds per step>.
glide() {
  local i
  for i in $(seq 1 "$5"); do
    move $(( $1 + ($3 - $1) * i / $5 )) $(( $2 + ($4 - $2) * i / $5 ))
    sleep "$6"
  done
}

# The probe's mark key: the player is idle, no label may be up, and the tool
# goes back into the cursor if a cancel cleared it.
mark() { pause 1.5; key ctrl+alt+m; pause 0.4; }

# Screenshots around the end of a drag: inside the latency window, then
# after it.
after() { pause 0.08; shot "$1-ended-early"; pause 1.4; shot "$1-ended-late"; }

# A lowering drag opens the "Lower land?" dialog in the middle of the
# window; its green button sits here at 1920x1080.
confirm_lowering() {
  pause 0.08; shot "$1-ended-early"; pause 1.2; shot "$1-dialog"
  move 820 540; pause 0.2; press 1; pause 0.15; release 1; note confirm
  pause 1.4; shot "$1-ended-late"
}

# ---------------------------------------------------------------------------
# Scenarios. The view is 1920x1080 at zoom 0.3: a 24-tile cell is 230 px.

scenario_slow() { # plain drag at a steady 280 px/s, held still, released
  move 1250 600; pause 0.3; press 1; pause 0.2
  glide 1250 600 1550 750 30 0.033; shot slow-moving
  glide 1550 750 1850 900 30 0.033; pause 1.2; shot slow-held
  release 1; after slow
}

scenario_flick() { # press, one jump and release with nothing in between
  move 1000 600; pause 0.3
  xdotool mousedown 1 mousemove --window "$W" 1500 300 mouseup 1
  note press 1; note move 1500 300; note release 1
  after flick
}

scenario_quick() { # a human-speed flick: about four frames from press to release
  move 1000 800; pause 0.3; press 1; pause 0.03
  move 1250 900; pause 0.02; move 1500 1000; pause 0.02; release 1
  after quick
}

scenario_cancel-q() { # Q clears the cursor mid-drag
  move 700 300; pause 0.3; press 1; pause 0.2
  glide 700 300 1100 500 20 0.033; pause 0.8; shot cancel-q-held
  key q; after cancel-q
  release 1
}

scenario_shift() { # Shift-drag: jump to Deed
  move 1000 600; pause 0.3; hold shift; pause 0.1; press 1; pause 0.2
  glide 1000 600 1400 800 20 0.033; pause 1.2; shot shift-held
  release 1; pause 0.1; unhold shift; after shift
}

scenario_right() { # right-drag: lower one rung
  move 1000 600; pause 0.3; press 3; pause 0.2
  glide 1000 600 1400 800 20 0.033; pause 1.2; shot right-held
  release 3; confirm_lowering right
}

scenario_shift-right() { # Shift-right-drag: sell back to Wilderness
  move 1250 600; pause 0.3; hold shift; pause 0.1; press 3; pause 0.2
  glide 1250 600 1600 900 20 0.033; pause 1.2; shot shift-right-held
  release 3; pause 0.1; unhold shift; confirm_lowering shift-right
}

scenario_ctrl-shift() { # Ctrl+Shift-drag: jump to Rampart
  move 1250 600; pause 0.3; hold ctrl; hold shift; pause 0.1; press 1; pause 0.2
  glide 1250 600 1600 900 20 0.033; pause 1.2; shot ctrl-shift-held
  release 1; pause 0.1; unhold shift; unhold ctrl; after ctrl-shift
}

scenario_short() { # Shift-drag over more cells than the purse covers
  move 100 100; pause 0.3; hold shift; pause 0.1; press 1; pause 0.2
  glide 100 100 975 550 15 0.033; shot short-moving
  glide 975 550 1850 1000 15 0.033; pause 1.2; shot short-held
  release 1; pause 0.1; unhold shift; after short
}

scenario_reorigin() { # a right-click during a left drag moves the origin
  move 300 300; pause 0.3; press 1; pause 0.2
  glide 300 300 700 500 20 0.033; pause 0.8
  xdotool click 3; note click 700 500; pause 0.8
  glide 700 500 900 800 20 0.033; pause 1.2; shot reorigin-held
  release 1; after reorigin
}

scenario_map() { # the same drag on the map
  key m; pause 2
  move 300 300; pause 0.3; press 1; pause 0.2
  glide 300 300 700 500 20 0.033; pause 1.2; shot map-held
  release 1; after map
  key m; pause 1.5
}

scenario_far() { # the map zoomed out: more cells than the preview prices
  key m; pause 2
  move 960 540; wheel 5 4; pause 1.5
  move 100 100; pause 0.3; press 1; pause 0.2
  glide 100 100 1820 1020 40 0.033; pause 1.5; shot far-over-limit
  glide 1820 1020 1000 600 20 0.033; pause 1.5; shot far-back-under-limit
  key q; pause 1.2; release 1
  mark
  # toward the top left corner, where the label has the least room
  move 1840 1040; pause 0.3; press 1; pause 0.2
  glide 1840 1040 40 60 40 0.033; pause 1.5; shot far-over-limit-top-left
  key q; pause 1.2; release 1
  mark
  # and along the other edges
  move 40 1040; pause 0.3; press 1; pause 0.2
  glide 40 1040 1890 60 40 0.033; pause 1.5; shot far-over-limit-top-right
  glide 1890 60 1890 1060 20 0.033; pause 1.5; shot far-over-limit-bottom-right
  key q; pause 1.2; release 1
  move 960 540; wheel 4 4; pause 1
  key m; pause 1.5
}

# Escape opens the game menu and hides the selection box, but the drag is
# only cancelled when the button is released under the menu.
scenario_cancel-escape() {
  move 900 500; pause 0.3; press 1; pause 0.2
  glide 900 500 500 250 20 0.033; pause 0.8; shot cancel-escape-held
  key Escape; pause 1.2; shot cancel-escape-menu
  release 1; after cancel-escape
  xdotool key Escape; note close-menu; pause 0.5
}

# ---------------------------------------------------------------------------

for name in "${WANT[@]}"; do
  declare -F "scenario_$name" > /dev/null || { echo "unknown scenario: $name (have: ${SCENARIOS[*]})"; exit 1; }
done
LABEL="lat${HARNESS_MP_LATENCY:-0}${HARNESS_MP_DELAY:+-delay$HARNESS_MP_DELAY}"
[ -d "$RUN" ] && vdisplay_stop "$RUN"
rm -rf "$RUN"; mkdir -p "$RUN/server" "$RUN/client" "$SHOTS"
: > "$STEPS"
harness_config "$RUN/server"
harness_config "$RUN/client" graphics
harness_stage "$RUN" "${SETS[0]}" "$DEV/mods/ltr-drag-probe" || exit 1
cat > "$RUN/server-settings.json" <<JSON
{ "name": "$MOD-drag-test", "description": "", "visibility": { "public": false, "lan": false },
  "require_user_verification": false, "auto_pause": false, "only_admins_can_pause_the_game": true,
  "autosave_interval": 0, "max_players": 0, "minimum_latency_in_ticks": ${HARNESS_MP_LATENCY:-0} }
JSON
"$FACTORIO" --config "$RUN/server/config.ini" --create "$RUN/world.zip" --mod-directory "$RUN/mods" \
  --map-gen-seed 1 > "$RUN/create.log" 2>&1 || { tail -20 "$RUN/create.log"; exit 1; }
echo "$EPOCHREALTIME" > "$RUN/server.start"
"$FACTORIO" --config "$RUN/server/config.ini" --mod-directory "$RUN/mods" --start-server "$RUN/world.zip" \
  --port "$(harness_port_request)" --server-settings "$RUN/server-settings.json" > "$RUN/server.log" 2>&1 &
SERVER=$!
PORT="$(harness_bound_port "$RUN/server.log")" || { echo "server never hosted"; tail -20 "$RUN/server.log"; exit 1; }
echo "server pid=$SERVER port=$PORT, latency ${HARNESS_MP_LATENCY:-0} ticks"
JOIN_PORT="$PORT"
if [ -n "${HARNESS_MP_DELAY:-}" ]; then
  python3 "$DEV/udp-delay.py" "$PORT" "$HARNESS_MP_DELAY" "$RUN/relay.port" & RELAY=$!
  for _ in $(seq 1 50); do [ -s "$RUN/relay.port" ] && break; sleep 0.1; done
  JOIN_PORT="$(cat "$RUN/relay.port" 2>/dev/null)"
  [ -n "$JOIN_PORT" ] || { echo "the delay relay never started"; exit 1; }
  echo "client joins through a relay on port $JOIN_PORT, ${HARNESS_MP_DELAY} ms each way"
fi
vdisplay_start "$RUN" "$SIZE" || exit 1
echo "$EPOCHREALTIME" > "$RUN/client.start"
"$FACTORIO" --config "$RUN/client/config.ini" --mod-directory "$RUN/mods" --mp-connect "127.0.0.1:$JOIN_PORT" \
  --window-size "$SIZE" --disable-audio > "$RUN/client.log" 2>&1 &
CLIENT=$!
for _ in $(seq 1 180); do
  grep -qi "joined the game" "$RUN/server.log" && break
  kill -0 "$CLIENT" 2>/dev/null || break
  kill -0 "$SERVER" 2>/dev/null || break
  sleep 1
done
grep -qi "joined the game" "$RUN/server.log" || {
  echo "client never joined"; harness_errors "$RUN/server.log" "$RUN/client.log" | head -5; exit 1; }
# A fresh connection starts with half a second of latency and settles in
# about twenty seconds.
echo "joined"; sleep 20
for id in $(xdotool search --pid "$CLIENT" 2>/dev/null); do
  case "$(xdotool getwindowname "$id" 2>/dev/null)" in Factorio*) W=$id ;; esac
done
[ -n "$W" ] || { echo "client window not found"; exit 1; }
xdotool windowraise "$W"; xdotool windowfocus --sync "$W"; sleep 0.3

SCENARIO=start
move 960 400; shot joined; mark
for _ in $(seq 1 50); do grep -q "LTR_MP MARK 1 " "$RUN/client.log" && break; sleep 0.1; done
grep -q "LTR_MP MARK 1 " "$RUN/client.log" || { echo "the client does not react to keys"; exit 1; }
MARKS=1
for SCENARIO in "${WANT[@]}"; do
  echo "scenario $SCENARIO"
  "scenario_$SCENARIO"
  mark; MARKS=$((MARKS + 1))
  [ "$SCENARIO" = far ] && MARKS=$((MARKS + 2))
done
SCENARIO=end
pause 1; shot end
wait "${SHOT_PIDS[@]}" 2>/dev/null
kill "$CLIENT" 2>/dev/null; sleep 2; kill "$SERVER" 2>/dev/null; sleep 1

# ---------------------------------------------------------------------------
# Verdict.

strip() { grep -h "LTR_MP" "$1" | sed -E 's/^.*LTR_MP /LTR_MP /'; }
strip "$RUN/server.log" > "$RUN/server-mp.txt"
strip "$RUN/client.log" > "$RUN/client-mp.txt"
status=0
flunk() { echo "FAILED: $*"; status=1; }
python3 "$DEV/drag-lag.py" "$RUN" "${WANT[@]}" | tee "$RUN/lag.txt" || flunk "the timing report (dev/drag-lag.py)"
echo "---- probe"
grep -E "^LTR_MP (JOIN|ORDER|FAIL)" "$RUN/server-mp.txt"
grep -E "^LTR_MP EV .* verdict=" "$RUN/server-mp.txt" | sed -E 's/^LTR_MP EV //'
echo "---- join"
grep -hiE "joined the game|mod event handlers|desync|mismatch|refused|stack traceback" "$RUN/server.log" "$RUN/client.log" | head -20
grep -qiE "mod event handlers are not identical|desync|non-recoverable|stack traceback" "$RUN/server.log" "$RUN/client.log" &&
  flunk "desync or script error"
# A server started in the background reports its closed stdin as an error.
errors=$(harness_errors "$RUN/server.log" "$RUN/client.log" | grep -v "Got EOF on stdin")
[ -z "$errors" ] || { echo "$errors" | head -5; flunk "errors in the logs"; }
fails=$(grep -c "^LTR_MP FAIL" "$RUN/server-mp.txt")
[ "$fails" -eq 0 ] || flunk "$fails probe FAIL line(s)"
# The client's log starts at its join; every line it has must be in the server's too.
missing=$(grep -v -x -F -f "$RUN/server-mp.txt" "$RUN/client-mp.txt" | wc -l)
[ "$missing" -eq 0 ] || flunk "$missing probe line(s) the client logged and the server did not"
grep -q "^LTR_MP MARK $MARKS " "$RUN/client-mp.txt" || flunk "expected $MARKS marks, the last one is missing"
grep "^LTR_MP STATE" "$RUN/client-mp.txt" | tail -n 1 | grep -q "labels=$" || flunk "a preview label is still up at the end"
echo "client probe lines: $(wc -l < "$RUN/client-mp.txt"), all in the server's log: $([ "$missing" -eq 0 ] && echo yes || echo no)"
[ $status -eq 0 ] && echo "DRAG OK   (shots: $SHOTS, timing: $RUN/lag.txt)" || echo "DRAG FAILED   (logs: $RUN)"
exit $status
