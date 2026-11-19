# Private X displays for graphical test clients, sourced by run-gui.sh,
# run-mp.sh and gui-drive.sh. A client on its own Xvfb display never moves
# the desktop's mouse, takes its keyboard focus or overwrites its clipboard.
#   vdisplay_start <dir> <WxH>    start a display, export DISPLAY, record it in <dir>
#   vdisplay_watch <dir> [play]   serve it to a browser tab (noVNC on localhost);
#                                 view-only unless "play"; prints the URL
#   vdisplay_stop <dir>           stop the viewer and the display
#
# FACTORIO_DISPLAY=desktop puts the client on the desktop instead, for when
# you want it on your own screen. XVFB, X11VNC, WEBSOCKIFY and NOVNC_DIR
# override where the tools are (packages: xvfb x11vnc novnc).

# True once display :<n> is up and served by the Xvfb with pid <pid>.
vdisplay_up() {
  [ -S "/tmp/.X11-unix/X$1" ] && [ "$(tr -d ' \n' < "/tmp/.X$1-lock" 2>/dev/null)" = "$2" ]
}

# Starts Xvfb on the first free display from :90, as xvfb-run -a does.
vdisplay_start() {
  local dir="$1" size="$2" n pid
  if [ "${FACTORIO_DISPLAY:-}" = desktop ]; then echo "$DISPLAY" > "$dir/display"; return 0; fi
  command -v "${XVFB:-Xvfb}" > /dev/null || {
    echo "Xvfb not found: sudo apt install xvfb x11vnc novnc (or FACTORIO_DISPLAY=desktop)" >&2; return 1; }
  for n in $(seq 90 119); do
    [ -e "/tmp/.X$n-lock" ] && continue
    nohup "${XVFB:-Xvfb}" ":$n" -screen 0 "${size}x24" -nolisten tcp > "$dir/xvfb.log" 2>&1 &
    pid=$!
    for _ in $(seq 1 50); do
      vdisplay_up "$n" "$pid" && { echo "$pid" > "$dir/xvfb.pid"; echo ":$n" > "$dir/display"
                                   export DISPLAY=":$n"; return 0; }
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    kill "$pid" 2>/dev/null
  done
  echo "no free X display in :90-:119 (see $dir/xvfb.log)" >&2; return 1
}

# Kills the processes whose pid files are named, then removes the files.
vdisplay_kill() {
  local dir="$1" f; shift
  for f in "$@"; do
    [ -f "$dir/$f.pid" ] && kill "$(cat "$dir/$f.pid")" 2>/dev/null
    rm -f "$dir/$f.pid"
  done
}

vdisplay_watch() {
  local dir="$1" ro=(-viewonly) q="&view_only=true" vnc web
  [ "${2:-}" = play ] && { ro=(); q=""; }
  [ -f "$dir/xvfb.pid" ] || { echo "no private display running in $dir" >&2; return 1; }
  vdisplay_kill "$dir" websockify x11vnc
  read -r vnc web < <(python3 -c 'import socket
s = [socket.socket() for _ in range(2)]
for x in s: x.bind(("127.0.0.1", 0))
print(*(x.getsockname()[1] for x in s))')
  nohup "${X11VNC:-x11vnc}" -display "$(cat "$dir/display")" -localhost -shared -forever -nopw -quiet \
    -rfbport "$vnc" "${ro[@]}" > "$dir/x11vnc.log" 2>&1 &
  echo $! > "$dir/x11vnc.pid"
  nohup "${WEBSOCKIFY:-websockify}" --web "${NOVNC_DIR:-/usr/share/novnc}" "127.0.0.1:$web" "127.0.0.1:$vnc" \
    > "$dir/websockify.log" 2>&1 &
  echo $! > "$dir/websockify.pid"
  echo "http://127.0.0.1:$web/vnc.html?autoconnect=true&resize=scale$q"
}

vdisplay_stop() {
  vdisplay_kill "$1" websockify x11vnc xvfb
  rm -f "$1/display"
}
