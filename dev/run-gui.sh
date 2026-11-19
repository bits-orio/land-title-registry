#!/usr/bin/env bash
# Launch a graphical client for GUI checks and screenshots, isolated from the
# player's own config and saves (private write-data under .run/gui) and from
# the desktop (a private X display, dev/vdisplay.sh). Returns once the game
# is running. Drive it with dev/gui-drive.sh, watch it with
# "dev/gui-drive.sh watch", stop it with "dev/gui-drive.sh stop"; starting
# again replaces it. The world is a fresh map (seed 1) with this mod, its
# DEPS, GUI_WORLD (dev/harness.conf) if set, and a generated mod that keeps
# every surface at noon with no clouds. Graphics settings are low.
#   usage: dev/run-gui.sh [base|space-age] [game|menu]   (default: the first of SETS, game)
#     menu: stop at the main menu instead of loading a game
#   GUI_SIZE=<WxH>      window size (default 1600x900)
#   GUI_UI_SCALE=<n>    interface scale, e.g. 1 or 1.5 (default: automatic)
#   FACTORIO_DISPLAY=desktop   open the window on your own screen instead
set -uo pipefail
DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=harness-lib.sh
. "$DEV/harness-lib.sh"
# shellcheck source=vdisplay.sh
. "$DEV/vdisplay.sh"
RUN="$REPO/.run/gui"
SET="${SETS[0]}"; MENU=false
for arg in "$@"; do
  case "$arg" in
    base|space-age) SET=$arg ;;
    menu) MENU=true ;;
    game) MENU=false ;;
    *) echo "unknown argument: $arg (expected base, space-age, game or menu)"; exit 1 ;;
  esac
done
SIZE="${GUI_SIZE:-1600x900}"
[ -f "$RUN/pid" ] && "$DEV/gui-drive.sh" stop
mkdir -p "$RUN"; rm -f "$RUN/world.zip" "$RUN/client.log"
harness_world "$RUN/harness-world"
harness_config "$RUN" graphics
if [ -n "${GUI_UI_SCALE:-}" ]; then
  printf '[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale=%s\n' "$GUI_UI_SCALE" >> "$RUN/config.ini"
fi
harness_stage "$RUN" "$SET" "$RUN/harness-world" ${GUI_WORLD:+"$DEV/mods/$GUI_WORLD"} || exit 1
ARGS=(--config "$RUN/config.ini" --mod-directory "$RUN/mods" --window-size "$SIZE" --disable-audio)
if ! $MENU; then
  "$FACTORIO" --config "$RUN/config.ini" --create "$RUN/world.zip" --mod-directory "$RUN/mods" \
    --map-gen-seed 1 > "$RUN/create.log" 2>&1 || { tail -20 "$RUN/create.log"; exit 1; }
  ARGS+=(--load-game "$RUN/world.zip")
fi
vdisplay_start "$RUN" "$SIZE" || exit 1
nohup "$FACTORIO" "${ARGS[@]}" > "$RUN/client.log" 2>&1 &
PID=$!; echo "$PID" > "$RUN/pid"
# Ready when the loaded game ticks (harness-world logs it), or, at the main
# menu, when the menu has finished loading.
READY="HARNESS_READY"; $MENU && READY="Factorio initialised"
for _ in $(seq 1 240); do
  grep -q "$READY" "$RUN/client.log" 2>/dev/null && { echo "pid=$PID display=$DISPLAY ready"; exit 0; }
  kill -0 "$PID" 2>/dev/null || { echo "client exited:"; tail -20 "$RUN/client.log"; exit 1; }
  sleep 0.5
done
echo "client not ready after 120 s (pid=$PID, log: $RUN/client.log)"; exit 1
