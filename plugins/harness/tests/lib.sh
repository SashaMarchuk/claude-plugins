# shellcheck shell=bash
# Test helpers, sourced into every t_*.sh file by tests/run.sh.
# Each result is printed and appended to $HO_TEST_RESULTS, which the runner counts.
# Every helper returns 0, so a failed check never stops the test file.

ok() {
  printf 'PASS  %s\n' "$1"
  printf 'PASS\t%s\n' "$1" >> "$HO_TEST_RESULTS"
}

bad() {
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
