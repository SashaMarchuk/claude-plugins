#!/usr/bin/env bash
# WS-10 master runner — invokes every plugin's regression harness in sequence
# and tallies aggregate PASS / FAIL. Exit 0 iff all per-plugin runners exit 0.
#
# Usage:  bash tests/run-all.sh
#
# Each per-plugin runner runs once. Its output is shown as it comes and kept; this
# script reads the PASS / FAIL counts from that run's last summary line, sums totals,
# and emits an aggregate summary at the end.
#
# One full suite at a time on this machine: a lock folder (HO_RUN_ALL_LOCK, default
# /tmp/claude-plugins-run-all-<uid>.lock) holds the PID and start time of the run that
# owns it. A second run waits. A lock whose holder is gone is taken over in place, under
# <lock>/takeover, and is never removed by a waiter, so a waiter never deletes a lock that
# another waiter has just made.

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

LOCK=${HO_RUN_ALL_LOCK:-/tmp/claude-plugins-run-all-$(id -u).lock}
ME=$$
# pstart <pid>: the process start time, so a reused PID is not taken for the holder.
pstart() { LC_ALL=C ps -o lstart= -p "$1" 2>/dev/null | sed 's/^ *//; s/ *$//'; }
ME_START=$(pstart "$ME")
# holder_alive <"pid start">: the recorded holder still runs (same PID, same start time).
holder_alive() {
  local pid=${1%% *} st=${1#* }
  case $pid in '' | *[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  [ "$(pstart "$pid")" = "$st" ]
}
# lock_old <path>: last changed more than one minute ago.
lock_old() { [ -n "$(find "$1" -maxdepth 0 -mmin +1 2>/dev/null)" ]; }
write_owner() { printf '%s %s\n' "$ME" "$ME_START" > "$LOCK/owner.$ME" && mv -f "$LOCK/owner.$ME" "$LOCK/owner"; }
TAKEOVER=0
release_lock() {
  [ "$TAKEOVER" = 1 ] && rmdir "$LOCK/takeover" 2>/dev/null
  if [ "$(cat "$LOCK/owner" 2>/dev/null || true)" = "$ME $ME_START" ]; then rm -rf "$LOCK"; fi
}
trap release_lock EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
take_lock() {
  local said=0 owner
  until mkdir "$LOCK" 2>/dev/null; do
    owner=$(cat "$LOCK/owner" 2>/dev/null || true)
    # A lock with no owner line (its maker died between mkdir and the write) is stale after a minute.
    if { [ -n "$owner" ] && ! holder_alive "$owner"; } || { [ -z "$owner" ] && lock_old "$LOCK"; }; then
      if mkdir "$LOCK/takeover" 2>/dev/null; then
        TAKEOVER=1
        # Under the takeover folder no other waiter changes the owner line: check it again, then write ours.
        if [ "$(cat "$LOCK/owner" 2>/dev/null || true)" = "$owner" ] && ! holder_alive "$owner" && write_owner; then
          rmdir "$LOCK/takeover" 2>/dev/null; TAKEOVER=0
          echo "run-all: took over the lock of a run that is gone (${owner:-no owner})"
          return 0
        fi
        rm -f "$LOCK/owner.$ME"; rmdir "$LOCK/takeover" 2>/dev/null; TAKEOVER=0
        continue
      fi
      # A waiter that died while taking over leaves an empty takeover folder; after a minute it goes.
      if lock_old "$LOCK/takeover"; then rmdir "$LOCK/takeover" 2>/dev/null; continue; fi
    fi
    if [ "$said" = 0 ]; then echo "run-all: another full run holds $LOCK (${owner:-starting}); waiting"; said=1; fi
    sleep 1
  done
  write_owner
}
take_lock

PLUGINS=(clickup g-event ultra ultra-analyzer claude-migrate find-call log-time harness ig-dm-export-analyzer interview-handoff)

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
  # One run: shown as it comes and kept. Each runner prints a final line of the form
  #   "<header>: PASS=<N>  FAIL=<M> ..."
  # and the counts are read from that run's output.
  out_file=$(mktemp "${TMPDIR:-/tmp}/run-all-out.XXXXXX")
  bash "$RUNNER" 2>&1 | tee "$out_file"
  rc=${PIPESTATUS[0]}
  summary=$(grep -E "PASS=[0-9]+.*FAIL=[0-9]+" "$out_file" | tail -1)
  pass_n=$(printf '%s\n' "$summary" | grep -oE "PASS=[0-9]+" | head -1 | cut -d= -f2)
  fail_n=$(printf '%s\n' "$summary" | grep -oE "FAIL=[0-9]+" | head -1 | cut -d= -f2)
  rm -f "$out_file"
  pass_n=${pass_n:-0}
  fail_n=${fail_n:-0}

  TOTAL_PASS=$((TOTAL_PASS + pass_n))
  TOTAL_FAIL=$((TOTAL_FAIL + fail_n))
  SUMMARIES+=("/$plugin: PASS=$pass_n  FAIL=$fail_n  exit=$rc")
  if [[ "$rc" -ne 0 ]]; then
    FAILED_PLUGINS+=("$plugin")
  fi
done

# Requirements: every spec and change under openspec/ must pass strict validation.
# Always the pinned CLI, so a different global install cannot change the verdict.
echo "=================================================================="
echo ">>> openspec validate --all --strict"
echo "=================================================================="
OPENSPEC_VERSION=1.16.0
OPENSPEC=(npx -y "@fission-ai/openspec@$OPENSPEC_VERSION")
set +e
(cd "$REPO_ROOT" && OPENSPEC_TELEMETRY=0 "${OPENSPEC[@]}" validate --all --strict --no-interactive)
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  TOTAL_PASS=$((TOTAL_PASS + 1)); SUMMARIES+=("openspec validate --strict: PASS")
else
  TOTAL_FAIL=$((TOTAL_FAIL + 1)); SUMMARIES+=("openspec validate --strict: FAIL (exit=$rc)")
  FAILED_PLUGINS+=("openspec")
fi

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
