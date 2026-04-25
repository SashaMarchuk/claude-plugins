#!/usr/bin/env bash
# WS-10 master runner — invokes every plugin's regression harness in sequence
# and tallies aggregate PASS / FAIL. Exit 0 iff all per-plugin runners exit 0.
#
# Usage:  bash tests/run-all.sh
#
# Each per-plugin runner prints its own PASS/FAIL lines + summary; this script
# captures the final summary line per plugin, sums totals, and emits an
# aggregate summary at the end.

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

PLUGINS=(clickup gevent ultra ultra-analyzer)

# Per-plugin tally
declare -a SUMMARIES
TOTAL_PASS=0
TOTAL_FAIL=0
FAILED_PLUGINS=()

for plugin in "${PLUGINS[@]}"; do
  RUNNER="$REPO_ROOT/plugins/$plugin/tests/run.sh"
  if [[ ! -x "$RUNNER" && ! -f "$RUNNER" ]]; then
    echo "------------------------------------------------------------------"
    echo "/$plugin: SKIP — runner not found at $RUNNER"
    echo "------------------------------------------------------------------"
    SUMMARIES+=("/$plugin: SKIP (no runner)")
    FAILED_PLUGINS+=("$plugin")
    TOTAL_FAIL=$((TOTAL_FAIL + 1))
    continue
  fi

  echo "=================================================================="
  echo ">>> /$plugin"
  echo "=================================================================="
  set +e
  bash "$RUNNER"
  rc=$?
  set -e

  # Re-extract PASS / FAIL counts from the runner's output by re-running it
  # quietly. Each runner prints a final line of the form:
  #   "<header>: PASS=<N>  FAIL=<M> ..."
  # We capture last invocation's tallies to keep things simple — a second
  # invocation is < 1s for all four plugins.
  set +e
  out=$(bash "$RUNNER" 2>&1)
  set -e
  pass_n=$(echo "$out" | grep -oE "PASS=[0-9]+" | tail -1 | cut -d= -f2)
  fail_n=$(echo "$out" | grep -oE "FAIL=[0-9]+" | tail -1 | cut -d= -f2)
  pass_n=${pass_n:-0}
  fail_n=${fail_n:-0}

  TOTAL_PASS=$((TOTAL_PASS + pass_n))
  TOTAL_FAIL=$((TOTAL_FAIL + fail_n))
  SUMMARIES+=("/$plugin: PASS=$pass_n  FAIL=$fail_n  exit=$rc")
  if [[ "$rc" -ne 0 ]]; then
    FAILED_PLUGINS+=("$plugin")
  fi
done

echo
echo "=================================================================="
echo "WS-10 master runner — aggregate summary"
echo "=================================================================="
for s in "${SUMMARIES[@]}"; do
  printf '  %s\n' "$s"
done
echo "------------------------------------------------------------------"
printf '  Total: %d PASS / %d FAIL\n' "$TOTAL_PASS" "$TOTAL_FAIL"
echo "=================================================================="

if [[ "$TOTAL_FAIL" -gt 0 || "${#FAILED_PLUGINS[@]}" -gt 0 ]]; then
  printf '  Failed plugin(s): %s\n' "${FAILED_PLUGINS[*]}"
  exit 1
fi
exit 0
