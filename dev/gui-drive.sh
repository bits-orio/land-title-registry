#!/usr/bin/env bash
# Drive the client started by run-gui.sh. Coordinates are window-relative.
#   gui-drive.sh shot <out.png>            screenshot the game window only
#   gui-drive.sh move <x> <y>              move the mouse
#   gui-drive.sh click <x> <y> [button]    click (1 left, 3 right)
#   gui-drive.sh drag <x1> <y1> <x2> <y2>  left-drag
#   gui-drive.sh key <keys...>             e.g. alt+p, Escape, e
#   gui-drive.sh type <text>               paste text into the focused field
#   gui-drive.sh lua <code>                run "/c <code>" in the console
#   gui-drive.sh snap <x> <y> <w> <h> <out.png> [zoom]
#                                          render a map region (centre x,y; w by h
#                                          tiles) with the game's own screenshot
#   gui-drive.sh watch [play]              print a localhost URL that shows the
#                                          client in a browser tab; view-only
#                                          unless "play"
#   gui-drive.sh stop                      quit the client and its display
#
# Everything goes to the client's private X display (dev/vdisplay.sh), so
# the desktop's mouse, focus and clipboard are never touched. Text goes in
# through that display's clipboard (xclip, then CTRL + V), much faster than
# typing; with FACTORIO_DISPLAY=desktop that is your clipboard. A client asks
# to confirm the first Lua command of each session (it disables
# achievements), so lua sends that first one twice. snap uses
# game.take_screenshot: it shows the map and render objects but never the
# cursor or the player's view, and costs only the pixels asked for; use shot
# when the cursor, the character or a GUI matters.
set -uo pipefail
DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$(cd "$DEV_DIR/.." && pwd)/.run/gui"
# shellcheck source=vdisplay.sh
. "$DEV_DIR/vdisplay.sh"
case "${1:-}" in
  # Only clients started from this run folder: others may be running unseen.
  # Waits for them to exit, since a client holds its write-data lock until then.
  stop)  pids=$(ps -C factorio -o pid=,args= | grep -F -- "--config $RUN/" | awk '{print $1}')
         for p in $pids; do kill "$p"; done
         for p in $pids; do timeout 10 tail --pid="$p" -f /dev/null || kill -9 "$p" 2>/dev/null; done
         rm -f "$RUN/pid" "$RUN"/confirmed-*; vdisplay_stop "$RUN"; exit 0 ;;
  watch) vdisplay_watch "$RUN" "${2:-}"; exit ;;
esac
PID=$(cat "$RUN/pid" 2>/dev/null)
DISPLAY=$(cat "$RUN/display" 2>/dev/null) || { echo "no client running (dev/run-gui.sh)"; exit 1; }
export DISPLAY
# The first window a fresh client reports can be a short-lived splash that
# is already gone; take the one that still answers with a Factorio title.
W=""
for id in $(xdotool search --pid "$PID" 2>/dev/null); do
  case "$(xdotool getwindowname "$id" 2>/dev/null)" in Factorio*) W=$id ;; esac
done
[ -n "$W" ] || { echo "client window not found"; exit 1; }
focus() { xdotool windowactivate --sync "$W" 2>/dev/null || { xdotool windowraise "$W"; xdotool windowfocus --sync "$W"; }; sleep 0.3; }
cmd="$1"; shift
case "$cmd" in
  shot)  focus; import -window "$W" "$1" ;;
  move)  focus; xdotool mousemove --window "$W" "$1" "$2" ;;
  # Held briefly, like a real click: 2.1 ignores an instant press and release
  # on slot-style buttons (the recipe slot, choose-elem buttons).
  click) focus; xdotool mousemove --window "$W" "$1" "$2"; sleep 0.2
         xdotool mousedown "${3:-1}"; sleep 0.15; xdotool mouseup "${3:-1}" ;;
  drag)  focus; xdotool mousemove --window "$W" "$1" "$2" mousedown 1; sleep 0.2
         xdotool mousemove --window "$W" "$3" "$4"; sleep 0.2; xdotool mouseup 1 ;;
  key)   focus; for k in "$@"; do xdotool key --window "$W" "$k"; sleep 0.2; done ;;
  type)  focus; printf '%s' "$1" | xclip -selection clipboard -i 2>/dev/null; xdotool key --window "$W" ctrl+v ;;
  lua)   focus
         printf '%s' "/c $1" | xclip -selection clipboard -i 2>/dev/null
         for _ in 1 2; do
           xdotool key --window "$W" grave; sleep 0.2
           xdotool key --window "$W" ctrl+v; sleep 0.1; xdotool key --window "$W" Return; sleep 1
           [ -f "$RUN/confirmed-$PID" ] && break
           touch "$RUN/confirmed-$PID"
         done ;;
  snap)  OUT_FILE="$RUN/userdata/script-output/harness-snap.png"; rm -f "$OUT_FILE"
         ZOOM="${6:-1}"; WPX=$(python3 -c "print(round($3*32*$ZOOM))"); HPX=$(python3 -c "print(round($4*32*$ZOOM))")
         "$0" lua "game.take_screenshot{player=game.player, position={$1,$2}, resolution={$WPX,$HPX}, zoom=$ZOOM, path='harness-snap.png', daytime=0, hide_clouds=true, hide_fog=true, force_render=true}"
         for _ in $(seq 1 30); do [ -s "$OUT_FILE" ] && break; sleep 0.2; done
         [ -s "$OUT_FILE" ] || { echo "no screenshot written"; exit 1; }
         sleep 0.3; cp "$OUT_FILE" "$5" ;;
esac
