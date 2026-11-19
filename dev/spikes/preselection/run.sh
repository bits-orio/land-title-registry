#!/usr/bin/env bash
# Spike: the pre-selection events of a selection tool (start, change and
# cancel while the player drags) and draw_selection_counts. Question, results
# and the recorded lines are in FINDINGS.md beside this file.
#   usage: dev/spikes/preselection/run.sh [proto|sp|mp [latency-ticks]]   (default: proto)
#
#   proto  Headless: creates a save with the probe mod and prints what the
#          tool's prototype and the event ids read as at runtime ("SPV"
#          lines), compared with recorded-proto-2.1.25.txt.
#   sp     A graphical client on a private display at 1920x1080. Drags the
#          tool with the mouse: slow, held still, fast, inside one tile, the
#          four modes, about 100 x 100 tiles, and a drag broken off with the
#          right button, Q and Escape. Prints the drags as analyze.py groups
#          them and saves mid-drag screenshots.
#   mp     A headless server and one graphical client that joins it and
#          drags. Compares the event lines the two peers logged. A second
#          argument sets minimum-latency-in-multiplayer in the client's
#          config.
#
# sp and mp need xdotool and start one graphical client; only one may run on
# a machine at a time. Every process gets a private config, write-data and
# mod directory (only the probe mod), as dev/run-tests.sh does it.
#   FACTORIO=<path>    the binary (default: the one dev/run-tests.sh uses)
#   HARNESS_RUN=<dir>  where the run folder goes (default .run/spikes)
#
# Exit status: 0 the probe finished (proto: and the lines match the recorded
# ones; mp: and both peers logged the same events), 1 it did not finish,
# 2 it finished with a different result. For sp, read the drags against
# recorded-drags-2.1.25.txt.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../harness-lib.sh
. "$HERE/../../harness-lib.sh"
# shellcheck source=../../vdisplay.sh
. "$DEV_DIR/vdisplay.sh"
RUN="${HARNESS_RUN:-$REPO/.run/spikes}/preselection"
MODE="${1:-proto}"
SIZE=1920x1080
echo "Factorio $ENGINE_FULL: $FACTORIO"

stage_mods() { # <mods dir>: the probe mod alone
  rm -rf "$1"; mkdir -p "$1"
  ln -s "$HERE" "$1/sel-probe"
  cat > "$1/mod-list.json" <<'EOF'
{ "mods": [
  { "name": "base", "enabled": true },
  { "name": "elevated-rails", "enabled": false },
  { "name": "quality", "enabled": false },
  { "name": "space-age", "enabled": false },
  { "name": "sel-probe", "enabled": true }
] }
EOF
}

# The window of a client, found by its pid: the first window a fresh client
# reports can be a splash that is already gone.
client_window() { # <pid>
  local id
  for id in $(xdotool search --pid "$1" 2>/dev/null); do
    case "$(xdotool getwindowname "$id" 2>/dev/null)" in Factorio*) W=$id ;; esac
  done
  [ -n "${W:-}" ]
}

# Mouse gestures on window W of the current DISPLAY. Coordinates are window
# pixels at 1920x1080; one tile is 32 pixels at zoom 1.
mark() { echo "$(date +%s.%N) $*" >> "$MARKS"; echo "MARK $*"; }
pointer() { xdotool mousemove --window "$W" "$1" "$2"; }
drag() { # <button> <x1> <y1> <x2> <y2> <steps> <seconds a step> <hold seconds> [shift]
  local b=$1 x1=$2 y1=$3 x2=$4 y2=$5 n=$6 d=$7 hold=$8 sh=${9:-} i
  [ -n "$sh" ] && xdotool keydown shift
  pointer "$x1" "$y1"; sleep 0.3; xdotool mousedown "$b"; sleep 0.2
  for i in $(seq 1 "$n"); do pointer $((x1 + (x2 - x1) * i / n)) $((y1 + (y2 - y1) * i / n)); sleep "$d"; done
  sleep "$hold"; xdotool mouseup "$b"; [ -n "$sh" ] && xdotool keyup shift; sleep 0.8
}
half_drag() { # left button down at 700,300, ten steps down and right; the button stays down
  local i
  pointer 700 300; sleep .3; xdotool mousedown 1; sleep .2
  for i in $(seq 1 10); do pointer $((700 + i * 20)) $((300 + i * 10)); sleep 0.05; done
}
drag_on() { # five more steps, then the button comes up
  local i
  for i in $(seq 1 "${1:-5}"); do pointer $((900 + i * 20)) $((400 + i * 10)); sleep 0.05; done
  xdotool mouseup 1; sleep 1
}

run_proto() {
  local dir="$RUN/proto"
  rm -rf "$dir"; mkdir -p "$dir"
  harness_config "$dir"
  stage_mods "$dir/mods"
  "$FACTORIO" --config "$dir/config.ini" --mod-directory "$dir/mods" --create "$dir/world.zip" \
    > "$dir/create.log" 2>&1 || { echo "--create failed"; tail -n 20 "$dir/create.log"; return 1; }
  grep -h "SPV " "$dir/create.log" | sed -E 's/^.*: SPV /SPV /' | tee "$dir/result.txt"
  grep -q "SPV send_pre_selection_events" "$dir/result.txt" || { echo "FAILED: the SPV lines are missing (log: $dir/create.log)"; return 1; }
  [ -z "$(harness_errors "$dir/create.log")" ] || { harness_errors "$dir/create.log" | head -20; echo "FAILED"; return 1; }
  if diff "$HERE/recorded-proto-2.1.25.txt" "$dir/result.txt" > "$dir/diff.txt"; then
    echo "DONE: same lines as recorded-proto-2.1.25.txt"
  else
    echo "---- differs from recorded-proto-2.1.25.txt (< recorded, > this run)"; cat "$dir/diff.txt"
    echo "DONE: the result differs from recorded-proto-2.1.25.txt"; return 2
  fi
}

# dev/run-gui.sh and dev/gui-drive.sh treat the folder above dev/ as the mod
# under test. Here that mod is the probe, so the run folder gets a stand-in
# repo: the probe mod with a copy of this repo's harness in its dev/. The
# client, its display and everything they write stay inside it.
RIG="$RUN/rig"
drive() { "$RIG/dev/gui-drive.sh" "$@"; }

run_sp() {
  local log="$RIG/.run/gui/userdata/factorio-current.log" i
  command -v xdotool > /dev/null || { echo "xdotool not found"; return 1; }
  [ -x "$RIG/dev/gui-drive.sh" ] && drive stop   # a client left over from an earlier run
  rm -rf "$RIG" "$RUN/shots"; mkdir -p "$RIG/dev" "$RUN/shots"
  cp "$HERE/info.json" "$HERE/data.lua" "$HERE/control.lua" "$RIG/"
  cp "$DEV_DIR/harness-lib.sh" "$DEV_DIR/vdisplay.sh" "$DEV_DIR/run-gui.sh" "$DEV_DIR/gui-drive.sh" "$RIG/dev/"
  printf 'ABBR=SP\nSETS=(base)\n' > "$RIG/dev/harness.conf"
  MARKS="$RUN/marks-sp.txt"; : > "$MARKS"
  trap 'drive stop' EXIT
  export FACTORIO
  GUI_SIZE=$SIZE "$RIG/dev/run-gui.sh" base game || return 1
  DISPLAY="$(cat "$RIG/.run/gui/display")"; export DISPLAY
  client_window "$(cat "$RIG/.run/gui/pid")" || { echo "client window not found"; return 1; }
  sleep 3
  shot_drag() { # <name> <button> [shift]: a screenshot in the middle of a drag
    local name=$1 b=$2 sh=${3:-} i
    [ -n "$sh" ] && xdotool keydown shift
    pointer 500 250; sleep .3; xdotool mousedown "$b"; sleep .2
    for i in $(seq 1 15); do pointer $((500 + i * 60)) $((250 + i * 35)); sleep 0.05; done; sleep 0.7
    drive shot "$RUN/shots/mid-$name.png"
    xdotool mouseup "$b"; [ -n "$sh" ] && xdotool keyup shift; sleep 1
  }
  regive() { drive lua "game.get_player(1).cursor_stack.set_stack{name='sel-probe'}; game.get_player(1).zoom=1"; sleep 1; }

  # The first console command of a session only asks for confirmation.
  drive lua "game.print('hello')"; sleep 1; drive lua "game.print('hello2')"; sleep 1
  pointer 960 540; sleep 1
  mark A-slow-left;      drag 1 700 300 1000 300 60 0.05 0
  mark B-still-3s;       drag 1 700 600 900 700 10 0.05 3
  mark C-fast-1jump;     drag 1 600 300 1400 800 1 0 0.3
  mark D-fast-5steps;    drag 1 600 300 1400 800 5 0.02 0.1
  mark K-subtile-jiggle; pointer 800 400; sleep .3; xdotool mousedown 1; sleep .2
  for i in $(seq 1 20); do pointer $((800 + i % 5)) $((400 + i % 3)); sleep 0.05; done; sleep 0.3; xdotool mouseup 1; sleep 0.8
  mark H-alt-shift-left; drag 1 700 300 1000 500 20 0.05 0.2 shift
  mark I-reverse-right;  drag 3 700 300 1000 500 20 0.05 0.2
  mark J-altreverse-shift-right; drag 3 700 300 1000 500 20 0.05 0.2 shift
  mark S1-tile-counts-true;    shot_drag tile-counts-true 1
  mark S2-tile-counts-false;   shot_drag tile-counts-false 1 shift
  mark S3-entity-counts-true;  shot_drag entity-counts-true 3
  mark S4-entity-counts-false; shot_drag entity-counts-false 3 shift
  mark L-100x100-zoom; drive lua "game.get_player(1).zoom=0.3"; sleep 1.5
  drag 1 400 100 1360 1060 12 0.1 0.5
  mark G-cancel-rightclick; half_drag   # still at zoom 0.3, as in the recorded run
  xdotool mousedown 3; sleep .15; xdotool mouseup 3; sleep .3
  drag_on
  regive
  mark F-cancel-Q; half_drag
  xdotool key --window "$W" q; sleep 0.3
  drag_on
  regive
  mark E-cancel-escape; half_drag
  xdotool key --window "$W" Escape; sleep 1
  xdotool key --window "$W" Escape; sleep 0.5
  drag_on 10
  mark done; sleep 1

  cp "$log" "$RUN/sp-client.log"
  echo "---- drags (analyze.py)"
  python3 "$HERE/analyze.py" "$RUN/sp-client.log" | tee "$RUN/sp-drags.txt"
  [ -z "$(harness_errors "$RUN/sp-client.log")" ] || { harness_errors "$RUN/sp-client.log" | head -20; echo "FAILED"; return 1; }
  # Sixteen drags were made. Fewer than twelve grouped ones means the mouse
  # did not reach the game.
  [ "$(wc -l < "$RUN/sp-drags.txt")" -ge 12 ] || { echo "FAILED: only $(wc -l < "$RUN/sp-drags.txt") drags were logged (log: $RUN/sp-client.log)"; return 1; }
  echo "DONE: hold the drags against recorded-drags-2.1.25.txt (screenshots: $RUN/shots)"
}

run_mp() { # [latency ticks]
  local dir="$RUN/mp" latency="${1:-${HARNESS_MP_LATENCY:-}}" port status=0
  command -v xdotool > /dev/null || { echo "xdotool not found"; return 1; }
  [ -d "$dir" ] && vdisplay_stop "$dir"
  rm -rf "$dir"; mkdir -p "$dir/server" "$dir/client"
  MARKS="$RUN/marks-mp.txt"; : > "$MARKS"
  harness_config "$dir/server"
  harness_config "$dir/client" graphics
  if [ -n "$latency" ] && ! grep -q "minimum-latency-in-multiplayer" "$dir/client/config.ini"; then
    printf '[other]\nminimum-latency-in-multiplayer=%s\n' "$latency" >> "$dir/client/config.ini"
  fi
  stage_mods "$dir/mods"
  cat > "$dir/server-settings.json" <<'EOF'
{ "name": "sel-probe", "description": "", "visibility": { "public": false, "lan": false },
  "require_user_verification": false, "auto_pause": false, "autosave_interval": 0, "max_players": 0 }
EOF
  "$FACTORIO" --config "$dir/server/config.ini" --create "$dir/world.zip" --mod-directory "$dir/mods" \
    --map-gen-seed 1 > "$dir/create.log" 2>&1 || { tail -n 20 "$dir/create.log"; return 1; }
  SERVER=""; CLIENT=""
  # shellcheck disable=SC2317  # runs from the trap
  cleanup() {
    [ -n "$CLIENT" ] && kill "$CLIENT" 2>/dev/null
    [ -n "$SERVER" ] && kill "$SERVER" 2>/dev/null
    sleep 2
    [ -n "$CLIENT" ] && kill -9 "$CLIENT" 2>/dev/null
    [ -n "$SERVER" ] && kill -9 "$SERVER" 2>/dev/null
    vdisplay_stop "$RUN/mp"
  }
  trap cleanup EXIT
  "$FACTORIO" --config "$dir/server/config.ini" --mod-directory "$dir/mods" --start-server "$dir/world.zip" \
    --port "$(harness_port_request)" --server-settings "$dir/server-settings.json" > "$dir/server.log" 2>&1 &
  SERVER=$!
  port="$(harness_bound_port "$dir/server.log")" || { echo "server never hosted"; tail -n 20 "$dir/server.log"; return 1; }
  vdisplay_start "$dir" "$SIZE" || return 1
  "$FACTORIO" --config "$dir/client/config.ini" --mod-directory "$dir/mods" --mp-connect "127.0.0.1:$port" \
    --window-size "$SIZE" --disable-audio > "$dir/client.log" 2>&1 &
  CLIENT=$!
  for _ in $(seq 1 180); do
    grep -qi "joined the game" "$dir/server.log" && break
    kill -0 "$CLIENT" 2>/dev/null || break
    sleep 1
  done
  grep -qi "joined the game" "$dir/server.log" || { echo "client never joined (logs: $dir)"; return 1; }
  sleep 15
  client_window "$CLIENT" || { echo "client window not found"; return 1; }
  xdotool windowraise "$W"; xdotool windowfocus "$W"

  pointer 960 540; sleep 1
  mark A-slow-left;      drag 1 700 300 1000 300 60 0.05 0
  mark B-still-3s;       drag 1 700 600 900 700 10 0.05 3
  mark C-fast-1jump;     drag 1 600 300 1400 800 1 0 0.3
  mark Q-cancel-q; half_drag
  xdotool key --window "$W" q; sleep 0.3; xdotool mouseup 1; sleep 3
  mark H-alt-shift;      drag 1 700 300 1000 500 20 0.05 0.2 shift
  mark I-reverse-right;  drag 3 700 300 1000 500 20 0.05 0.2
  mark E-cancel-escape; half_drag
  xdotool key --window "$W" Escape; sleep 0.3; xdotool mouseup 1; sleep 1
  mark end; sleep 3

  events() { grep -h "SP t=" "$1" | grep -v "STATE\|given tool\|iterate-cost" | sed -E 's/^ *[0-9.]+ Script @[^ ]+ //'; }
  events "$dir/server.log" > "$dir/server-events.txt"
  events "$dir/client/userdata/factorio-current.log" > "$dir/client-events.txt"
  echo "---- drags on the server (analyze.py)"
  python3 "$HERE/analyze.py" "$dir/server.log" | tee "$dir/server-drags.txt"
  echo "---- latency the client reports"
  grep -h "Initialized Synchronizer" "$dir/client.log" | sed -E 's/^ *[0-9.]+ //'
  if grep -hiE "desync|mod event handlers are not identical|non-recoverable|stack traceback" "$dir/server.log" "$dir/client.log" | head -20 | grep .; then
    echo "FAILED (logs: $dir)"; return 1
  fi
  [ -s "$dir/server-events.txt" ] || { echo "FAILED: the server logged no selection event (logs: $dir)"; return 1; }
  if cmp -s "$dir/server-events.txt" "$dir/client-events.txt"; then
    echo "DONE: server and client logged the same $(wc -l < "$dir/server-events.txt") event lines"
  else
    diff "$dir/server-events.txt" "$dir/client-events.txt" | head -40
    echo "DONE: server and client logged different event lines ($(wc -l < "$dir/server-events.txt") and $(wc -l < "$dir/client-events.txt"))"
    status=2
  fi
  return $status
}

mkdir -p "$RUN"
case "$MODE" in
  proto) run_proto ;;
  sp) run_sp ;;
  mp) run_mp "${2:-}" ;;
  *) echo "unknown mode: $MODE (expected proto, sp or mp)"; exit 1 ;;
esac
