#!/usr/bin/env bash
# release.sh - route a claimed work item to done/failed/requeue.
#
# Usage:
#   release.sh <item-path> done
#   release.sh <item-path> failed   [reason]
#   release.sh <item-path> requeue  [reason]
#
# <item-path> is an in-progress/ item under either the `units` queue
# (units/in-progress/UNNN__*.md) or the `seed` queue (seed/in-progress/UNNN.json).
# The queue and run-path are DERIVED from the path - there is no queue argument
# (Repo H-2: release.sh takes the item path + outcome; the path tells it which
# counter pair to touch).
#
# Per-queue counter pairs preserve the §3.3 sum invariant:
#   units: chats_total  == preflight_{pending+in_progress+done+failed}
#   seed:  seeded_units == seed_{pending+in_progress+done+failed}
# Every move adjusts exactly two counters of the SAME queue.
#
# The `reason` string is PRE-REDACTED through the canonical [REDACTED:*] regex
# set (Edge C-3 / AC-REDACT) before it is written to either the retry-tag
# filename or the JSONL run.log, so a token-bearing reason never lands on disk.

set -uo pipefail

item="${1:?item-path required}"
outcome="${2:?outcome required (done|failed|requeue)}"
reason_raw="${3:-unspecified}"

# --- canonical PII redaction (shared regex set; see references/pii-policy.md) ---
# Replaces secrets/PII with [REDACTED:*] markers. Uses portable `sed -E` (no
# grep -P), case-insensitive where the token form allows. Order matters:
# longer/structured tokens first so they are not partially eaten by later rules.
_redact() {
  printf '%s' "$1" | sed -E \
    -e 's/[Bb]earer[[:space:]]+[A-Za-z0-9._~+/=-]+/[REDACTED:bearer]/g' \
    -e 's/[Aa]uthorization:[[:space:]]*[A-Za-z0-9._~+/=-]+/[REDACTED:authorization]/g' \
    -e 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/[REDACTED:jwt]/g' \
    -e 's/(sk|pk|rk)-[A-Za-z0-9_-]{16,}/[REDACTED:apikey]/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[REDACTED:email]/g' \
    -e 's/(session|sid|csrf|token|cookie|_ga|__cf)[A-Za-z0-9_-]*=[A-Za-z0-9._~+/=-]+/[REDACTED:cookie]/g' \
    -e 's/(\+?[0-9][0-9()[:space:]-]{7,}[0-9])/[REDACTED:phone]/g'
}

reason=$(_redact "$reason_raw")
# Also strip newlines so the reason stays a single JSONL field / filename token.
reason=$(printf '%s' "$reason" | tr '\n\r' '  ')

base=$(basename "$item")
dir=$(dirname "$item")                 # .../units/in-progress  or  .../seed/in-progress
qroot=$(dirname "$dir")                # .../units              or  .../seed
run_path=$(dirname "$qroot")           # .../<run>
queue=$(basename "$qroot")             # units                 or  seed

case "$queue" in
  units)
    ext="md"
    counter_done=".counters.preflight_done"
    counter_failed=".counters.preflight_failed"
    counter_pending=".counters.preflight_pending"
    counter_in_progress=".counters.preflight_in_progress"
    ;;
  seed)
    ext="json"
    counter_done=".counters.seed_done"
    counter_failed=".counters.seed_failed"
    counter_pending=".counters.seed_pending"
    counter_in_progress=".counters.seed_in_progress"
    ;;
  *)
    echo "ERROR: cannot derive queue from item path '$item' (expected .../units/in-progress/... or .../seed/in-progress/...)" >&2
    exit 2
    ;;
esac

# Two-stage move: rename to a temp name (excluded from sweeps by the pattern),
# then to the destination, so a concurrent sweep never catches a half-moved file.
tmp="$dir/${base%.$ext}.release-tmp.$$.$ext"
mv "$item" "$tmp"

bindir=$(cd "$(dirname "$0")" && pwd)

case "$outcome" in
  done)
    mkdir -p "$qroot/done"
    mv "$tmp" "$qroot/done/$base"
    bash "$bindir/state.sh" inc "$run_path" "$counter_done"
    # in-progress -> done: keep the per-queue sum invariant intact.
    bash "$bindir/state.sh" dec "$run_path" "$counter_in_progress"
    ;;
  failed)
    mkdir -p "$qroot/failed"
    mv "$tmp" "$qroot/failed/$base"
    bash "$bindir/state.sh" inc "$run_path" "$counter_failed"
    # in-progress -> failed: keep the per-queue sum invariant intact.
    bash "$bindir/state.sh" dec "$run_path" "$counter_in_progress"
    ;;
  requeue)
    mkdir -p "$qroot/pending"
    # Retry tag encodes attempt epoch + redacted reason; workers count
    # `__retry-` substrings to cap retries.
    tagged="${base%.$ext}__retry-$(date +%s)-${reason}.$ext"
    mv "$tmp" "$qroot/pending/$tagged"
    # Do not increment done/failed - the item remains unresolved.
    # in-progress -> pending: keep the per-queue sum invariant intact.
    bash "$bindir/state.sh" dec "$run_path" "$counter_in_progress"
    bash "$bindir/state.sh" inc "$run_path" "$counter_pending"
    ;;
  *)
    # Restore the item before erroring so the queue is not left in a temp state.
    mv "$tmp" "$item" 2>/dev/null || true
    echo "ERROR: unknown outcome: $outcome (expected done|failed|requeue)" >&2
    exit 1
    ;;
esac

# Append to run log (JSONL for later aggregation). The reason is already
# redacted; the basename can carry a UNNN id only (no PII by construction).
log="$run_path/run.log"
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"ts":"%s","queue":"%s","item":"%s","outcome":"%s","reason":"%s"}\n' \
  "$ts" "$queue" "$base" "$outcome" "$reason" >> "$log"
