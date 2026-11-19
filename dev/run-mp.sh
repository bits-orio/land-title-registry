#!/usr/bin/env bash
# Multiplayer join test; settings in dev/harness.conf. A headless server runs a
# fresh map with this mod, its DEPS and MP_WORLD if set; after JOIN_AFTER
# seconds a graphical client joins over localhost, on a private X display
# (dev/vdisplay.sh; FACTORIO_DISPLAY=desktop shows it on your screen), and
# stays STAY seconds once it has joined (a software-rendered client can take
# half a minute to load its sprites first). A client that has not joined
# within 3 minutes, a join refused as "mod event handlers are not identical",
# a desync or a script error fails the run.
#   usage: dev/run-mp.sh [join-after-seconds] [stay-seconds] [base|space-age]
#   HARNESS_MP_LATENCY=<ticks>  the server keeps every client's input at least
#                         that many ticks ahead (minimum_latency_in_ticks in the
#                         server settings; 30 is half a second)
#   HARNESS_MP_DELAY=<ms>  the client joins through dev/udp-delay.py, which holds
#                         every packet that long each way (100 is a 200 ms round
#                         trip). A fresh client starts at 32 ticks of latency on
#                         any network; the server lowers it within about 20 s.
#   HARNESS_PORT=<port>   server port (default: a free port the game picks;
#                         MP_PORT in harness.conf on engines before 2.1.25)
set -uo pipefail
DEV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=harness-lib.sh
. "$DEV/harness-lib.sh"
# shellcheck source=vdisplay.sh
. "$DEV/vdisplay.sh"
RUN="$REPO/.run/mp"
JOIN_AFTER="${1:-20}"
STAY="${2:-30}"
SET="${3:-${SETS[0]}}"
PORT_REQUEST="$(harness_port_request)" || exit 1
[ -d "$RUN" ] && vdisplay_stop "$RUN"
rm -rf "$RUN"; mkdir -p "$RUN/server" "$RUN/client"
harness_config "$RUN/server"
harness_config "$RUN/client" graphics
harness_stage "$RUN" "$SET" ${MP_WORLD:+"$DEV/mods/$MP_WORLD"} || exit 1
cat > "$RUN/server-settings.json" <<JSON
{ "name": "$MOD-mp-test", "description": "", "visibility": { "public": false, "lan": false },
  "require_user_verification": false, "auto_pause": false, "only_admins_can_pause_the_game": true,
  "autosave_interval": 0, "max_players": 0, "minimum_latency_in_ticks": ${HARNESS_MP_LATENCY:-0} }
JSON
"$FACTORIO" --config "$RUN/server/config.ini" --create "$RUN/world.zip" --mod-directory "$RUN/mods" \
  --map-gen-seed 1 > "$RUN/create.log" 2>&1 || { tail -20 "$RUN/create.log"; exit 1; }
"$FACTORIO" --config "$RUN/server/config.ini" --mod-directory "$RUN/mods" --start-server "$RUN/world.zip" \
  --port "$PORT_REQUEST" --server-settings "$RUN/server-settings.json" > "$RUN/server.log" 2>&1 &
SERVER=$!
PORT="$(harness_bound_port "$RUN/server.log")" || { echo "server never hosted"; tail -20 "$RUN/server.log"; kill $SERVER 2>/dev/null; exit 1; }
echo "server pid=$SERVER port=$PORT, client joins in ${JOIN_AFTER}s"
timeout "$JOIN_AFTER" tail -f /dev/null
vdisplay_start "$RUN" 1280x720 || { kill $SERVER; exit 1; }
RELAY=""; JOIN_PORT="$PORT"
if [ -n "${HARNESS_MP_DELAY:-}" ]; then
  python3 "$DEV/udp-delay.py" "$PORT" "$HARNESS_MP_DELAY" "$RUN/relay.port" & RELAY=$!
  for _ in $(seq 1 50); do [ -s "$RUN/relay.port" ] && break; sleep 0.1; done
  JOIN_PORT="$(cat "$RUN/relay.port" 2>/dev/null)"
  [ -n "$JOIN_PORT" ] || { echo "the delay relay never started"; kill $SERVER $RELAY 2>/dev/null; vdisplay_stop "$RUN"; exit 1; }
  echo "client joins through a relay on port $JOIN_PORT, ${HARNESS_MP_DELAY} ms each way"
fi
"$FACTORIO" --config "$RUN/client/config.ini" --mod-directory "$RUN/mods" --mp-connect "127.0.0.1:$JOIN_PORT" \
  --window-size 1280x720 --disable-audio > "$RUN/client.log" 2>&1 &
CLIENT=$!
echo "client pid=$CLIENT"
for _ in $(seq 1 180); do
  grep -qi "joined the game" "$RUN/server.log" && break
  kill -0 "$CLIENT" 2>/dev/null || break
  sleep 1
done
grep -qi "joined the game" "$RUN/server.log" && { echo "joined, staying ${STAY}s"; timeout "$STAY" tail -f /dev/null; }
kill $CLIENT 2>/dev/null; sleep 1; kill $SERVER 2>/dev/null; sleep 1
kill -9 $CLIENT $SERVER 2>/dev/null; [ -z "$RELAY" ] || kill $RELAY 2>/dev/null; vdisplay_stop "$RUN"
if [ -n "$ABBR" ]; then
  echo "---- server ${ABBR}_MP"; grep -h "${ABBR}_MP" "$RUN/server.log" | sed -E "s/^.*${ABBR}_MP /${ABBR}_MP /"
fi
echo "---- join"; grep -hiE "joined the game|mod event handlers|desync|mismatch|refused|stack traceback" "$RUN/server.log" "$RUN/client.log" | head -20
status=0
grep -qiE "mod event handlers are not identical|desync|non-recoverable|stack traceback" "$RUN/server.log" "$RUN/client.log" && status=1
grep -qiE "joined the game" "$RUN/server.log" || { echo "client never joined"; status=1; }
[ $status -eq 0 ] && echo "MP JOIN OK" || echo "MP JOIN FAILED (logs: $RUN)"
exit $status
