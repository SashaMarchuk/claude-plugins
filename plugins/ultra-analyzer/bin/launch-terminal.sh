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
#
# H-4: if NEITHER is available, fail LOUDLY at launch (exit 7) rather than
# silently running without a timeout. A hung worker without a timeout wrapper
# never returns and the retry loop never activates — historically the #1
# operational pain on stock macOS without coreutils.
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout"
else
  echo "[launch] FATAL: no timeout command available (neither 'timeout' nor 'gtimeout')." >&2
  echo "[launch]        Install coreutils via 'brew install coreutils' on macOS." >&2
  echo "[launch]        Refusing to launch — hung workers would never be killed (H-4)." >&2
  exit 7
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

# Topic-filename prompt-injection sanitizer (closes M-1).
# Topic basenames are interpolated into the prompt string passed to
# `claude --print`. A malicious basename (planted via filesystem race or
# a poisoned seed) could carry pseudo-directives. Refuse anything outside
# the strict allowlist before invoking the worker.
basename_safe() {
  local b="$1"
  # Allowlist: alnum, _, ., - only. Length cap 200.
  if [[ ! "$b" =~ ^[A-Za-z0-9_.-]+$ ]]; then return 1; fi
  if [[ ${#b} -gt 200 ]]; then return 1; fi
  # Reject literal injection markers even if they slip through allowlist
  # via unicode lookalikes (the allowlist already blocks `[`, but be loud).
  case "$b" in
    *FILE:*|*AGENT:*|*DOC:*|*DATA:*|*URL:*|*Phase*|*phase*|*Ignore*|*ignore*) return 1 ;;
  esac
  return 0
}

while true; do
  topic=$(bash "$bindir/claim.sh" "$run_path") || { echo "[launch] no pending work, exiting"; break; }
  topic_base=$(basename "$topic")
  if ! basename_safe "$topic_base"; then
    echo "[launch] REFUSING topic with unsafe basename: $topic_base (M-1)" >&2
    bash "$bindir/release.sh" "$topic" failed "unsafe-basename" || true
    continue
  fi
  model=$(pick_model "$topic")
  echo "[launch] topic=$topic_base model=$model"

  # Three retry attempts on transient failures. Each attempt wrapped in timeout
  # to kill hung workers (network stall, adapter deadlock).
  ok=0
  for i in 1 2 3; do
    # TIMEOUT_CMD is guaranteed non-empty — H-4 exits at startup if missing.
    # Delimit the topic argument with explicit BEGIN/END markers so the
    # worker (and any LLM eyes) treat it as quoted data, not directives.
    # Even with the allowlist above, defense in depth is cheap.
    $TIMEOUT_CMD --kill-after=30s "${WORKER_TIMEOUT_S}s" \
      claude --plugin-dir "$plugin_dir" --model "$model" --print "/ultra-analyzer:analyze-unit <<TOPIC_PATH_BEGIN>>${topic}<<TOPIC_PATH_END>>"
    rc=$?
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
