#!/usr/bin/env bash
# Harness Orchestrator test runner.
# Re-runs itself once in a scrubbed environment, then runs every tests/t_*.sh
# file in its own process and its own temp folder. Last line of output:
#   harness tests: PASS=<n>  FAIL=<m>
set -euo pipefail

HO_TESTS_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HO_PLUGIN_ROOT=$(cd -P "$HO_TESTS_DIR/.." && pwd)

ho_summary_fail() {
  echo "FAIL  runner: $*"
  echo "harness tests: PASS=0  FAIL=1"
  exit 1
}

# ---- Stage 1: scrub the environment and re-run under env -i ----------------
if [ "${HO_TEST_SCRUBBED:-}" != 1 ]; then
  tmp_base=${TMPDIR:-/tmp}
  tmp_base=${tmp_base%/}
  path="$HO_TESTS_DIR/fake-bin"
  for tool in jq git bash; do
    tool_path=$(command -v "$tool" 2>/dev/null) || ho_summary_fail "$tool not found"
    tool_dir=$(dirname "$tool_path")
    case ":$path:" in *":$tool_dir:"*) ;; *) path="$path:$tool_dir" ;; esac
  done
  path="$path:/usr/bin:/bin:/usr/sbin:/sbin"
  bash_bin=$(command -v bash)
  test_home=$(mktemp -d "$tmp_base/ho-test-home.XXXXXX") || ho_summary_fail "mktemp failed"
  rc=0
  env -i HOME="$test_home" TMPDIR="$tmp_base" LANG=C PATH="$path" \
    HO_TEST_SCRUBBED=1 "$bash_bin" "$HO_TESTS_DIR/run.sh" "$@" || rc=$?
  rm -rf "$test_home"
  if [ "$rc" -ge 126 ]; then
    ho_summary_fail "scrubbed runner did not start (exit $rc)"
  fi
  exit "$rc"
fi

# ---- Stage 2: run the tests (scrubbed environment) --------------------------
case $(basename "$HOME") in
  ho-test-home.*) ;;
  *) ho_summary_fail "HOME is not a scrubbed test home" ;;
esac

PASS=0
FAIL=0
HO_SUMMARY_DONE=0
ho_finish() {
  local rc=$?
  if [ "$HO_SUMMARY_DONE" -eq 0 ]; then
    echo "FAIL  runner: stopped early (exit $rc)"
    echo "harness tests: PASS=$PASS  FAIL=$((FAIL + 1))"
    exit 1
  fi
}
trap ho_finish EXIT

HO_TEST_RESULTS="$HOME/results.txt"
: > "$HO_TEST_RESULTS"
export HO_PLUGIN_ROOT HO_TESTS_DIR HO_TEST_RESULTS

found=0
for test_file in "$HO_TESTS_DIR"/t_*.sh; do
  [ -f "$test_file" ] || continue
  found=1
  name=$(basename "$test_file")
  echo "--- $name"
  work=$(mktemp -d "$HOME/work.XXXXXX")
  before=$(wc -l < "$HO_TEST_RESULTS")
  rc=0
  (cd "$work" && exec bash -euo pipefail -c '. "$1"; . "$2"' _ "$HO_TESTS_DIR/lib.sh" "$test_file") || rc=$?
  rm -rf "$work"
  after=$(wc -l < "$HO_TEST_RESULTS")
  new_pass=$(tail -n "$((after - before))" "$HO_TEST_RESULTS" | grep -c '^PASS' || true)
  new_fail=$(tail -n "$((after - before))" "$HO_TEST_RESULTS" | grep -c '^FAIL' || true)
  [ "$after" -gt "$before" ] || { new_pass=0; new_fail=0; }
  PASS=$((PASS + new_pass))
  FAIL=$((FAIL + new_fail))
  if [ "$rc" -ne 0 ]; then
    echo "FAIL  $name: crashed (exit $rc)"
    FAIL=$((FAIL + 1))
  elif [ "$after" -eq "$before" ]; then
    echo "FAIL  $name: checked zero assertions"
    FAIL=$((FAIL + 1))
  fi
done

if [ "$found" -eq 0 ]; then
  echo "FAIL  runner: no t_*.sh test files found"
  FAIL=$((FAIL + 1))
fi

HO_SUMMARY_DONE=1
echo "------------------------------------------------------------------"
echo "harness tests: PASS=$PASS  FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
