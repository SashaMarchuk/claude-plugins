#!/usr/bin/env bash
# launch-worker.sh - single-terminal parallel worker loop for the
# preflight and distill steps. Open N copies of this in N terminals
# for parallelism; claim races are resolved by claim.sh's mkdir lock.
#
# Usage:
#   launch-worker.sh <run-path> <step>
#
# Where:
#   <run-path>  absolute or relative path to the run dir
#               (.planning/claude-migrate/<run>/).
#   <step>      preflight | distill - selects the worker skill and the
#               default model tier read from the run profile.
#
# Each loop iteration:
#   1. claim.sh <run-path> units      (the preflight+distill queue)
#   2. basename_safe()                 (prompt-injection defense on the filename)
#   3. pick_model()                    (from the run profile; upgrade on retry)
#   4. timeout-wrapped `claude --print` worker, unit path delimited by
#      BEGIN/END markers so it is treated as quoted DATA, not directives.
#   5. 3-attempt retry on transient failure; exit 124 (timeout) never retries.
#   6. all-retries-failed -> release.sh <unit> failed <reason>.
#
# Exits when no pending units remain.

# Deliberately `set -uo pipefail` (NOT `set -e`). The retry loop below reads
# `$rc` after every claude invocation; `set -e` would abort on the first
# non-zero exit and defeat the whole point of the 3-attempt retry. This is
# intentional, audited, and documented here so a future cleanup pass does not
# blindly add `-e` and break retries (mirrors ultra-analyzer/launch-terminal.sh).
set -uo pipefail

run_path="${1:?run-path required}"
step="${2:?step required (preflight|distill)}"
bindir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$bindir")

# Map the pipeline step to its worker skill. Only these two steps fan out.
case "$step" in
  preflight) worker_skill="preflight-value" ;;
  distill)   worker_skill="distill-brief" ;;
  *)
    echo "[launch] FATAL: unknown step '$step' (expected: preflight|distill)" >&2
    exit 2 ;;
esac

# Portable timeout detection. Workers hang if the model or an adapter query
# never returns. On macOS `timeout` is not built-in - require coreutils
# (`brew install coreutils` provides `gtimeout`). Fall back to `timeout` on Linux.
#
# If NEITHER is available, fail LOUDLY at launch (exit 7) rather than silently
# running without a timeout. A hung worker without a timeout wrapper never
# returns and the retry loop never activates.
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
else
  echo "[launch] FATAL: no timeout command available (neither 'timeout' nor 'gtimeout')." >&2
  echo "[launch]        Install coreutils via 'brew install coreutils' on macOS." >&2
  echo "[launch]        Refusing to launch - hung workers would never be killed." >&2
  exit 7
fi

# Per-worker ceiling (seconds). Safety net above any per-unit budget.
WORKER_TIMEOUT_S="${CLAUDE_MIGRATE_WORKER_TIMEOUT_S:-1800}"

# Read worker models from the run's active profile (set via state.sh init or
# /claude-migrate:config). Defaults match SPEC §3.2 (preflight=haiku,
# distill=sonnet). Absence means manual state tampering - fall back defensively.
state_file="$run_path/state.json"
if [[ -f "$state_file" ]] && command -v jq >/dev/null 2>&1; then
  PREFLIGHT_MODEL=$(jq -r '.profile.preflight_model // "haiku"' "$state_file")
  DISTILL_MODEL=$(jq -r '.profile.distill_model // "sonnet"' "$state_file")
else
  echo "[launch] WARNING: state.json or jq missing - falling back to hardcoded models" >&2
  PREFLIGHT_MODEL="haiku"
  DISTILL_MODEL="sonnet"
fi

# Model selection by step, with a retry escalation: a retried unit upgrades the
# preflight tier to sonnet (a stronger second look on a flaky scoring run).
# Distill is already sonnet, so retries stick to the same tier.
pick_model() {
  local unit="$1"
  case "$step" in
    preflight)
      if [[ "$unit" == *__retry-* ]]; then
        echo "sonnet"
      else
        echo "$PREFLIGHT_MODEL"
      fi
      ;;
    distill)
      echo "$DISTILL_MODEL"
      ;;
  esac
}

# Unit-filename prompt-injection sanitizer. Unit basenames are interpolated into
# the prompt string passed to `claude --print`. A malicious basename (planted via
# a filesystem race or a poisoned export) could carry pseudo-directives. Refuse
# anything outside the strict allowlist before invoking the worker.
basename_safe() {
  local b="$1"
  # Allowlist: alnum, _, ., - only. Length cap 200.
  if [[ ! "$b" =~ ^[A-Za-z0-9_.-]+$ ]]; then return 1; fi
  if [[ ${#b} -gt 200 ]]; then return 1; fi
  # Reject literal injection markers even if they slip through the allowlist
  # via unicode lookalikes (the allowlist already blocks most, but be loud).
  case "$b" in
    *FILE:*|*AGENT:*|*DOC:*|*DATA:*|*URL:*|*UNIT:*|*Phase*|*phase*|*Ignore*|*ignore*) return 1 ;;
  esac
  return 0
}

while true; do
  unit=$(bash "$bindir/claim.sh" "$run_path" units) || { echo "[launch] no pending work, exiting"; break; }
  unit_base=$(basename "$unit")
  if ! basename_safe "$unit_base"; then
    echo "[launch] REFUSING unit with unsafe basename: $unit_base" >&2
    bash "$bindir/release.sh" "$unit" failed "unsafe-basename" || true
    continue
  fi
  model=$(pick_model "$unit")
  echo "[launch] step=$step unit=$unit_base model=$model"

  # Three retry attempts on transient failures. Each attempt wrapped in timeout
  # to kill hung workers (network stall, adapter deadlock).
  ok=0
  for i in 1 2 3; do
    # TIMEOUT_CMD is guaranteed non-empty - the FATAL check above exits at
    # startup if missing. Delimit the unit-path argument with explicit
    # BEGIN/END markers so the worker (and any LLM eyes) treat it as quoted
    # data, not directives. Defense in depth on top of the allowlist.
    $TIMEOUT_CMD --kill-after=30s "${WORKER_TIMEOUT_S}s" \
      claude --plugin-dir "$plugin_dir" --model "$model" --print "/claude-migrate:${worker_skill} <<UNIT_PATH_BEGIN>>${unit}<<UNIT_PATH_END>>"
    rc=$?
    if [[ $rc -eq 0 ]]; then
      ok=1
      break
    fi
    # Exit 124 = timeout killed the worker. Don't retry - the underlying issue
    # (a hung model call) won't resolve on a re-run within this window.
    if [[ $rc -eq 124 ]]; then
      echo "[launch] worker timed out after ${WORKER_TIMEOUT_S}s on $unit_base" >&2
      break
    fi
    sleep $((i * 10))
  done

  if [[ $ok -eq 0 ]]; then
    # All retries failed (or timed out) - route to failed/ with a diagnostic reason.
    if [[ "${rc:-0}" -eq 124 ]]; then
      bash "$bindir/release.sh" "$unit" failed "worker-timeout" || true
    else
      bash "$bindir/release.sh" "$unit" failed "transient-error" || true
    fi
  fi
done
