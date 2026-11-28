# shellcheck shell=bash
# Test helpers, sourced into every t_*.sh file by tests/run.sh.
# Each result is printed and appended to $HO_TEST_RESULTS, which the runner counts.
# Every helper returns 0, so a failed check never stops the test file.

ok() {
  set -- "$(printf '%s' "$1" | tr '\n' ' ')"
  printf 'PASS  %s\n' "$1"
  printf 'PASS\t%s\n' "$1" >> "$HO_TEST_RESULTS"
}

bad() {
  set -- "$(printf '%s' "$1" | tr '\n' ' ')" "${2:-}"
  printf 'FAIL  %s: %s\n' "$1" "${2:-}"
  printf 'FAIL\t%s\n' "$1" >> "$HO_TEST_RESULTS"
  return 0
}

# assert_eq <name> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$2], got [$3]"; fi
}

# assert_contains <name> <haystack> <needle>
assert_contains() {
  case $2 in
    *"$3"*) ok "$1" ;;
    *) bad "$1" "[$3] not found in [$2]" ;;
  esac
}

# assert_exit <name> <code> <cmd...>
assert_exit() {
  local name=$1 want=$2 rc=0
  shift 2
  "$@" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$name"; else bad "$name" "expected exit $want, got $rc"; fi
}

# sleep_marks <dir>: make <dir>/sleep, a stand-in for sleep that appends its argument as one line
# to the file named by T_SLEEP_MARK (when set), then sleeps. A command run with <dir> first on
# PATH and T_SLEEP_MARK set leaves one line per sleep, so a test waits until a poll loop really
# waits (its sleep after a failed try) instead of sleeping a fixed time (issue #109).
sleep_marks() {
  mkdir -p "$1"
  printf '#!/bin/sh\n[ -z "${T_SLEEP_MARK:-}" ] || printf "%%s\\n" "$*" >> "$T_SLEEP_MARK"\nexec %s "$@"\n' "$(command -v sleep)" > "$1/sleep"
  chmod +x "$1/sleep"
}

# wait_mark <file> <arg> [count] [tenths]: wait until the mark file holds at least <count>
# (default 1) lines equal to <arg>; a generous cap (default 60 s), not a timing check.
wait_mark() {
  local i=0 n
  while :; do
    n=$(grep -cxF -- "$2" "$1" 2>/dev/null) || true
    [ "${n:-0}" -lt "${3:-1}" ] || return 0
    [ "$i" -lt "${4:-600}" ] || return 1
    sleep 0.1
    i=$((i + 1))
  done
}

# select_config <project-dir> [name]: the person's confirmation on this machine (H-072,
# D37-FLOW-8 (b)): select a committed config (default .harness/config.json) and record its
# approved profile, so a run may start there. Select again after a test raises a recorded field.
select_config() {
  HO_PROJECT_DIR="$1" "$HO_PLUGIN_ROOT/bin/harness" config select "${2:-config}" >/dev/null
}
