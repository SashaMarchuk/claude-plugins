#!/usr/bin/env bash
# launch-terminal.sh — single-terminal worker loop.
# Open N copies of this in N terminals for parallelism.
#
# Usage:
#   launch-terminal.sh <run-path>
#
# Claims topics one at a time, invokes analyze-unit via `claude --print`,
# exits when no pending topics remain.

set -uo pipefail

run_path="${1:?run-path required}"
bindir=$(cd "$(dirname "$0")" && pwd)
plugin_dir=$(dirname "$bindir")

# Portable timeout detection. Workers hang if adapter queries never return.
# On macOS, `timeout` isn't built-in — require coreutils (`brew install coreutils`
# gives `gtimeout`). Fall back to `timeout` on Linux.
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
else
  echo "[launch] WARNING: no timeout command found; hung workers will not be killed." >&2
  echo "[launch]          install coreutils on macOS: brew install coreutils" >&2
fi

# Per-worker ceiling (seconds). Safety net above topic-level budget (max_runtime_s).
# Set to 2x the largest expected topic budget.
WORKER_TIMEOUT_S="${ULTRA_ANALYZER_WORKER_TIMEOUT_S:-1800}"

# Read worker models from the run's active profile (set via /ultra-analyzer:set-profile).
# Fallbacks to sane defaults if profile fields are missing (defensive — state.sh init
# writes the full profile object, so absence means manual state tampering).
state_file="$run_path/state.json"
if [[ -f "$state_file" ]] && command -v jq >/dev/null 2>&1; then
  PROFILE_WORKER_MODEL=$(jq -r '.profile.worker_model // "sonnet"' "$state_file")
  PROFILE_WORKER_MODEL_S=$(jq -r '.profile.worker_model_complexity_S // "haiku"' "$state_file")
  # Retry escalation: retries up the tier for the current profile.
  # For most profiles, worker_model is already strong — retries stick to the same.
  # For profiles where S-complexity uses a lighter model, retries upgrade to the standard model.
  PROFILE_RETRY_MODEL="$PROFILE_WORKER_MODEL"
else
  echo "[launch] WARNING: state.json or jq missing — falling back to hardcoded models" >&2
  PROFILE_WORKER_MODEL="sonnet"
  PROFILE_WORKER_MODEL_S="haiku"
  PROFILE_RETRY_MODEL="sonnet"
fi

# Model selection based on retry tag and complexity.
# Retries upgrade to the profile's standard worker_model (stronger than S-complexity variant).
pick_model() {
  local topic="$1"
  local complexity
  complexity=$(grep -m1 '^## Complexity:' "$topic" 2>/dev/null | awk '{print $3}')
  if [[ "$topic" == *__retry-* ]]; then
    echo "$PROFILE_RETRY_MODEL"
  else
    case "$complexity" in
      S) echo "$PROFILE_WORKER_MODEL_S" ;;
      *) echo "$PROFILE_WORKER_MODEL" ;;
    esac
  fi
}

while true; do
  topic=$(bash "$bindir/claim.sh" "$run_path") || { echo "[launch] no pending work, exiting"; break; }
  model=$(pick_model "$topic")
  echo "[launch] topic=$(basename "$topic") model=$model"

  # Three retry attempts on transient failures. Each attempt wrapped in timeout
  # to kill hung workers (network stall, adapter deadlock).
  ok=0
  for i in 1 2 3; do
    if [[ -n "$TIMEOUT_CMD" ]]; then
      $TIMEOUT_CMD --kill-after=30s "${WORKER_TIMEOUT_S}s" \
        claude --plugin-dir "$plugin_dir" --model "$model" --print "/ultra-analyzer:analyze-unit $topic"
      rc=$?
    else
      claude --plugin-dir "$plugin_dir" --model "$model" --print "/ultra-analyzer:analyze-unit $topic"
      rc=$?
    fi
    if [[ $rc -eq 0 ]]; then
      ok=1
      break
    fi
    # Exit 124 = timeout killed the worker. Don't retry — underlying issue won't resolve.
    if [[ $rc -eq 124 ]]; then
      echo "[launch] worker timed out after ${WORKER_TIMEOUT_S}s on $(basename "$topic")" >&2
      break
    fi
    sleep $((i * 10))
  done

  if [[ $ok -eq 0 ]]; then
    # All retries failed (or timed out) — route to failed/ with diagnostic reason.
    if [[ "${rc:-0}" -eq 124 ]]; then
      bash "$bindir/release.sh" "$topic" failed "worker-timeout" || true
    else
      bash "$bindir/release.sh" "$topic" failed "transient-error" || true
    fi
  fi
done
