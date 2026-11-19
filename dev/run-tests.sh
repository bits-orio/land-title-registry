#!/usr/bin/env bash
# Headless test suite; settings in dev/harness.conf. The PRE_TESTS commands
# run first. Then, for each mod set, this mod, its DEPS and the test mod (if
# the repo has one) are staged in a private mod folder and a fresh save is
# created (on_init runs, no player yet). The save is then run in the game's
# test mode (--test-save, Factorio 2.1.24 and newer): on_load runs, a
# connected player is created (index 1, admin, so charting works), and the
# game ticks until the test mod calls script.finish_test(passed) or TICKS
# ticks have passed. Older engines run --benchmark for TICKS ticks instead,
# without a player.
#
# A test mod logs "<ABBR>_TEST PASS <name>", "<ABBR>_TEST FAIL <name>: <why>"
# and, after its last check, "<ABBR>_TEST DONE"; it should then call
# script.finish_test(failures == 0) so the run ends at once. The call does
# nothing outside test mode, but before 2.1.24 reading script.finish_test or
# script.test_arg throws: a test mod that also runs there wraps them in pcall.
# script.test_arg holds HARNESS_ARG.
#
# Exit status is non-zero on a failed PRE_TESTS command, a failed Factorio
# run (finish_test(false) and an uncaught Lua error both exit 1), any engine
# or Lua error in the logs, any <ABBR>_TEST FAIL line, or a test mod that
# never printed <ABBR>_TEST DONE. Running out of ticks exits 0 in test mode,
# so the DONE line is what proves a suite finished.
#   usage: dev/run-tests.sh [base|space-age ...]   (default: SETS in harness.conf)
#   HARNESS_TICKS=<n>  tick limit (default: TICKS in harness.conf)
#   HARNESS_ARG=<str>  passed as --test-arg; a test mod reads script.test_arg
#   HARNESS_RUN=<dir>  where runs live (default .run/tests), so parallel runs do not collide
#   FACTORIO=<path>    the binary (default: the install matching info.json's factorio_version)
set -uo pipefail
# shellcheck source=harness-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/harness-lib.sh"
RUN_DIR="${HARNESS_RUN:-$REPO/.run/tests}"
TICKS="${HARNESS_TICKS:-$TICKS}"
WANT=("$@"); [ ${#WANT[@]} -eq 0 ] && WANT=("${SETS[@]}")
TAG="${ABBR}_TEST"

run_pre_tests() {
  local cmd status=0
  for cmd in "${PRE_TESTS[@]}"; do
    if (cd "$REPO" && bash -c "$cmd") > "$RUN_DIR/pre.log" 2>&1; then
      echo "[pre] ok: $cmd"
    else
      echo "[pre] FAILED: $cmd"; tail -n 20 "$RUN_DIR/pre.log" | sed "s/^/  [pre] /"; status=1
    fi
  done
  return $status
}

launch() { # <set name> <set dir>; runs --create, then the save in test mode
  local name="$1" dir="$2" save="$2/test.zip" cfg="$2/config.ini" run
  rm -f "$save" "$dir/create.log" "$dir/bench.log"
  touch "$dir/bench.log"
  "$FACTORIO" --config "$cfg" --create "$save" --mod-directory "$dir/mods" --map-gen-seed 1 \
    > "$dir/create.log" 2>&1 || { echo "[$name] --create failed"; return 1; }
  if harness_engine_at_least 2.1.24; then
    run=(--test-save "$save" --test-ticks "$TICKS")
    [ -n "${HARNESS_ARG:-}" ] && run+=(--test-arg "$HARNESS_ARG")
  else
    run=(--benchmark "$save" --benchmark-ticks "$TICKS")
  fi
  "$FACTORIO" --config "$cfg" "${run[@]}" --mod-directory "$dir/mods" \
    > "$dir/bench.log" 2>&1 || { echo "[$name] ${run[0]} failed"; return 1; }
}

evaluate() { # <set name> <set dir> <launch status>; prints a summary
  local name="$1" dir="$2" status="$3" logs=("$2/create.log" "$2/bench.log") pass=0 fail=0 errors
  if [ -n "$TEST_MOD" ]; then
    grep -h "$TAG " "${logs[@]}" | sed -E "s/^.*$TAG /$TAG /" > "$dir/results.txt"
    pass=$(grep -c "^$TAG PASS" "$dir/results.txt")
    fail=$(grep -c "^$TAG FAIL" "$dir/results.txt")
    grep "^$TAG FAIL" "$dir/results.txt" | sed "s/^/  [$name] /"
    [ "$fail" -gt 0 ] && status=1
    grep -q "^$TAG DONE" "$dir/results.txt" || { echo "  [$name] missing $TAG DONE"; status=1; }
  fi
  errors=$(harness_errors "${logs[@]}")
  [ -n "$errors" ] && { echo "$errors" | head -20 | sed "s/^/  [$name] ERROR: /"; status=1; }
  if [ -n "$TEST_MOD" ]; then echo "[$name] pass=$pass fail=$fail   (logs: $dir)"
  else echo "[$name] loaded, ran up to $TICKS ticks: $([ "$status" -eq 0 ] && echo ok || echo FAILED)   (logs: $dir)"; fi
  if [ "$status" -ne 0 ] && [ "$fail" -eq 0 ]; then tail -n 15 "${logs[@]}" | sed "s/^/  [$name] /"; fi
  return "$status"
}

run_set() { # <set name>
  local dir="$RUN_DIR/$1" status=0
  mkdir -p "$dir"
  harness_config "$dir"
  harness_stage "$dir" "$1" ${TEST_MOD:+"$DEV_DIR/mods/$TEST_MOD"} || return 1
  launch "$1" "$dir" || status=1
  evaluate "$1" "$dir" "$status"
}

mkdir -p "$RUN_DIR"
overall=0
run_pre_tests || overall=1
echo "Factorio $ENGINE_VERSION: $FACTORIO"
for set in "${WANT[@]}"; do
  case "$set" in
    base|space-age) run_set "$set" || overall=1 ;;
    *) echo "unknown set: $set (expected base or space-age)"; overall=1 ;;
  esac
done
if [ $overall -eq 0 ]; then echo "ALL PASS"; else echo "FAILED"; fi
exit $overall
