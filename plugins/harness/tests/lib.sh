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

# select_config <project-dir> [name]: the person's confirmation on this machine (H-072,
# D37-FLOW-8 (b)): select a committed config (default .harness/config.json) and record its
# approved profile, so a run may start there. Select again after a test raises a recorded field.
select_config() {
  HO_PROJECT_DIR="$1" "$HO_PLUGIN_ROOT/bin/harness" config select "${2:-config}" >/dev/null
}
