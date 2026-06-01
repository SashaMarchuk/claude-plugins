#!/usr/bin/env bash
# claim.sh - atomically claim one item from a queue's pending/ and move it to
# in-progress/. Uses mkdir-based locking (portable, works on macOS without flock).
#
# Usage:
#   claim.sh <run-path> <queue>
#
# <queue> is one of:
#   units  - the preflight/distill work queue (units/{pending,in-progress,...});
#            items are UNNN__<slug>.md; counter pair = preflight_pending / preflight_in_progress.
#   seed   - the browser-sink apply queue (seed/{pending,in-progress,...});
#            items are UNNN.json; counter pair = seed_pending / seed_in_progress.
#
# Prints the absolute path to the claimed item on success.
# Exits 1 if no pending items.
#
# Two-queue signature pinned by Repo H-2. The counter pair the script adjusts is
# determined entirely by <queue>, so the per-queue sum invariant (§3.3) holds:
#   units: chats_total == preflight_{pending+in_progress+done+failed}
#   seed:  seeded_units == seed_{pending+in_progress+done+failed}

set -euo pipefail

run_path="${1:?run-path required}"
queue="${2:?queue required (units|seed)}"

case "$queue" in
  units)
    qroot="$run_path/units"
    glob='U*.md'
    counter_pending=".counters.preflight_pending"
    counter_in_progress=".counters.preflight_in_progress"
    ;;
  seed)
    qroot="$run_path/seed"
    glob='U*.json'
    counter_pending=".counters.seed_pending"
    counter_in_progress=".counters.seed_in_progress"
    ;;
  *)
    echo "ERROR: unknown queue '$queue' (expected units|seed)" >&2
    exit 2
    ;;
esac

pending="$qroot/pending"
in_progress="$qroot/in-progress"
lockdir="$qroot/.claim.lock.d"

[[ -d "$pending" ]] || { echo "ERROR: no pending/ dir at $pending" >&2; exit 2; }
# Symlink-attack defense. A symlinked pending/ would let a hostile local user
# point our atomic-mv at attacker-controlled content. Refuse loudly.
if [[ -L "$pending" ]]; then
  echo "ERROR: $pending is a symlink - refusing to claim" >&2
  exit 5
fi
mkdir -p "$in_progress"

# Acquire exclusive lock via mkdir (atomic: fails if dir exists).
waited=0
while ! mkdir "$lockdir" 2>/dev/null; do
  sleep 0.1
  waited=$((waited + 1))
  if [[ $waited -gt 300 ]]; then
    echo "ERROR: claim.sh lock timeout on $lockdir (>30s)" >&2
    exit 3
  fi
done
trap 'rmdir "$lockdir" 2>/dev/null || true' EXIT

# Pick the first pending item. Sort deterministically (UNNN prefix orders the
# units, retry-tagged requeues sort after their base). `-P` makes find treat
# each candidate as the symlink itself (not the target). We deliberately DO NOT
# add `-type f` exclusively - we want symlinks to surface so we can refuse them
# loudly at the explicit `[ -L ]` check below (per-file symlink defense).
item=$(find -P "$pending" -maxdepth 1 -name "$glob" \( -type f -o -type l \) 2>/dev/null | sort | head -1)

if [[ -z "$item" ]]; then
  exit 1  # no work
fi

# Defense-in-depth - the candidate file itself must not be a symlink.
if [[ -L "$item" ]]; then
  echo "ERROR: $item is a symlink - refusing to claim" >&2
  exit 5
fi

base=$(basename "$item")
dest="$in_progress/$base"
mv "$item" "$dest"

# Counter invariant: moving pending -> in-progress decrements this queue's
# pending and increments its in-progress so the per-queue sum invariant holds
# throughout the claim/release/requeue cycle.
bindir=$(cd "$(dirname "$0")" && pwd)
bash "$bindir/state.sh" dec "$run_path" "$counter_pending"
bash "$bindir/state.sh" inc "$run_path" "$counter_in_progress"

# Absolute path for downstream tooling.
echo "$(cd "$(dirname "$dest")" && pwd)/$(basename "$dest")"
