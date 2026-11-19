# Shared parts of the test harness, sourced by run-tests.sh, run-gui.sh and
# run-mp.sh. Every dev/*.sh harness file is a verbatim copy of the
# factorio-client-testing skill's reference/ folder; the repo's own settings
# live in dev/harness.conf.
#
# Sets REPO, DEV_DIR, MOD (info.json's name), MOD_FV (its factorio_version),
# FACTORIO, ENGINE_VERSION ("2.1") and ENGINE_FULL ("2.1.25"), and loads
# harness.conf.

DEV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DEV_DIR/.." && pwd)"

# Defaults; harness.conf overrides them.
ABBR=""        # test mod log prefix: <ABBR>_TEST PASS|FAIL|DONE, <ABBR>_MP
SETS=(base)    # mod sets run-tests.sh runs: base, space-age
TICKS=600      # tick limit of a run-tests.sh run
TEST_MOD=""    # dev/mods/<name> that run-tests.sh loads, if any
GUI_WORLD=""   # dev/mods/<name> that run-gui.sh loads, if any
MP_WORLD=""    # dev/mods/<name> that run-mp.sh loads, if any
MP_PORT=""     # server port on engines before 2.1.25 (newer ones pick a free port)
DEPS=()        # "name source [git-branch]" for each mod this one needs
PRE_TESTS=()   # commands run-tests.sh runs first, from the repo root
harness_stage_hook() { :; }  # called with the mods dir after staging
# shellcheck source=harness.conf
. "$DEV_DIR/harness.conf"

harness_json() { # <json file> <key>
  python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$1" "$2"
}

MOD="$(harness_json "$REPO/info.json" name)"
MOD_FV="$(harness_json "$REPO/info.json" factorio_version)"
FACTORIO="${FACTORIO:-$HOME/factorio-$MOD_FV/bin/x64/factorio}"
[ -x "$FACTORIO" ] || { echo "no Factorio binary at $FACTORIO (set FACTORIO=)" >&2; exit 1; }
# "2.1.25" and "2.1" from "Version: 2.1.25 (build ...)".
ENGINE_FULL="$("$FACTORIO" --version 2>/dev/null | sed -nE 's/^Version: ([0-9]+\.[0-9]+\.[0-9]+) .*/\1/p' | head -n 1)"
ENGINE_VERSION="${ENGINE_FULL%.*}"

harness_engine_at_least() { # <x.y.z>; true when the binary is that version or newer
  [ -n "$ENGINE_FULL" ] && [ "$(printf '%s\n%s\n' "$1" "$ENGINE_FULL" | sort -V | head -n 1)" = "$1" ]
}

# The port a server is started with. From 2.1.25 on, port 0 makes the game
# pick a free one, so servers of parallel or leftover runs never collide;
# older engines get the repo's MP_PORT. HARNESS_PORT overrides both.
harness_port_request() {
  if [ -n "${HARNESS_PORT:-}" ]; then echo "$HARNESS_PORT"
  elif harness_engine_at_least 2.1.25; then echo 0
  else echo "${MP_PORT:?set MP_PORT in dev/harness.conf}"
  fi
}

# The port the server really bound, read from its "Hosting game at" log line
# (waits up to 60 s for it). Prints nothing and fails if the server never
# hosted. With a line count, only the log after that many lines is read, for
# a log that several server starts append to.
harness_bound_port() { # <server log> [lines to skip]
  local port
  for _ in $(seq 1 120); do
    port="$(tail -n +$(( ${2:-0} + 1 )) "$1" 2>/dev/null | sed -nE 's/.*Hosting game at IP ADDR:\(\{[^}]*:([0-9]+)\}\).*/\1/p' | tail -n 1)"
    [ -n "$port" ] && { echo "$port"; return 0; }
    sleep 0.5
  done
  return 1
}

harness_patch_version() { # <mod dir>
  sed -i -E "s/(\"factorio_version\": *\")[^\"]+\"/\1$ENGINE_VERSION\"/" "$1/info.json"
}

# A symlink when the mod targets this engine, else a copy with its
# factorio_version patched (without git data, run output or dev folders).
harness_stage_dir() { # <source dir> <destination>
  if [ -z "$ENGINE_VERSION" ] || [ "$(harness_json "$1/info.json" factorio_version)" = "$ENGINE_VERSION" ]; then
    ln -s "$1" "$2"; return
  fi
  mkdir -p "$2"
  rsync -a --exclude .git --exclude .run --exclude dev --exclude docs --exclude tools --exclude reference "$1/" "$2/"
  harness_patch_version "$2"
}

# One DEPS entry. A folder is staged like this mod; with a git branch, that
# branch's committed tree is exported instead, so the dependency's checkout
# can be on any branch. A zip is linked as it is.
harness_stage_dep() { # <mods dir> <name> <source> [git-branch]
  local dest="$1/$2"
  if [ -n "${4:-}" ]; then
    mkdir -p "$dest"
    git -C "$3" archive "$4" | tar -x -C "$dest" || { echo "dependency $2: cannot export $3 at $4" >&2; return 1; }
    [ -z "$ENGINE_VERSION" ] || harness_patch_version "$dest"
  elif [ -d "$3" ]; then harness_stage_dir "$3" "$dest"
  elif [ -f "$3" ]; then ln -s "$3" "$1/$(basename "$3")"
  else echo "dependency $2: no such source $3" >&2; return 1
  fi
}

# Builds <run dir>/mods: this mod, its DEPS and the extra mod folders given,
# all enabled, with the DLC enabled only for the space-age set.
harness_stage() { # <run dir> <set> [mod folder ...]
  local mods="$1/mods" set="$2" names=("$MOD") entry dep m dlc=false
  shift 2
  rm -rf "$mods"; mkdir -p "$mods"
  harness_stage_dir "$REPO" "$mods/$MOD" || return 1
  for entry in "${DEPS[@]}"; do
    read -r -a dep <<< "$entry"
    harness_stage_dep "$mods" "${dep[@]}" || return 1
    names+=("${dep[0]}")
  done
  for m in "$@"; do
    harness_stage_dir "$m" "$mods/$(basename "$m")" || return 1
    names+=("$(basename "$m")")
  done
  harness_stage_hook "$mods"
  [ "$set" = space-age ] && dlc=true
  python3 - "$mods/mod-list.json" "$dlc" "${names[@]}" <<'PY'
import json, sys
path, dlc, names = sys.argv[1], sys.argv[2] == "true", sys.argv[3:]
mods = [{"name": "base", "enabled": True}]
mods += [{"name": n, "enabled": dlc} for n in ("elevated-rails", "quality", "space-age")]
mods += [{"name": n, "enabled": True} for n in names]
json.dump({"mods": mods}, open(path, "w"), indent=1)
PY
}

# A private write-data folder keeps every run off the player's own lock file,
# config, saves and logs. Clients render in software into system memory, so
# their graphics settings stay low.
harness_config() { # <run dir> [graphics]
  mkdir -p "$1/userdata"
  {
    printf '[path]\nread-data=__PATH__executable__/../../data\nwrite-data=%s/userdata\n' "$1"
    if [ "${2:-}" = graphics ]; then
      printf '[graphics]\nfull-screen=false\ngraphics-quality=medium\nvideo-memory-usage=low\n'
      printf 'texture-compression-level=low-quality\n'
    fi
  } > "$1/config.ini"
}

# Engine and script errors, but not the test mod's own lines (a FAIL detail
# may contain the word "error").
harness_errors() { # <log files...>
  grep -h -v "_TEST " "$@" | grep -E "Error|error while|stack traceback|Failed to load mods" || true
}

# A dev-only mod for GUI runs: every surface at noon with no clouds, no
# freeplay crash site or intro (the intro turns the start to dusk when the
# player is created), and a HARNESS_READY log line once the loaded game
# ticks. Never used in multiplayer: it unregisters its tick handler, which a
# joining client would not match.
harness_world() { # <dir>
  mkdir -p "$1"
  cat > "$1/info.json" <<EOF
{ "name": "harness-world", "version": "1.0.0", "title": "Test harness world", "author": "test harness",
  "factorio_version": "${ENGINE_VERSION:-$MOD_FV}", "dependencies": ["base"] }
EOF
  cat > "$1/control.lua" <<'EOF'
local function daylight(surface)
  surface.always_day = true
  surface.show_clouds = false
end

script.on_init(function()
  local freeplay = remote.interfaces.freeplay
  if freeplay and freeplay.set_disable_crashsite then remote.call("freeplay", "set_disable_crashsite", true) end
  if freeplay and freeplay.set_skip_intro then remote.call("freeplay", "set_skip_intro", true) end
  for _, surface in pairs(game.surfaces) do daylight(surface) end
end)

script.on_event(defines.events.on_surface_created, function(event)
  daylight(game.get_surface(event.surface_index))
end)

script.on_event(defines.events.on_tick, function(event)
  log("HARNESS_READY tick " .. event.tick)
  script.on_event(defines.events.on_tick, nil)
end)
EOF
}
