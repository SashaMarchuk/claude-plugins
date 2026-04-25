#!/usr/bin/env bash
# claim.sh — atomically claim one topic from pending/ and move it to in-progress/.
# Uses mkdir-based locking (portable, works on macOS without flock).
#
# Usage:
#   claim.sh <run-path>
#
# Prints the absolute path to the claimed topic on success.
# Exits 1 if no pending topics.

set -euo pipefail

run_path="${1:?run-path required}"
pending="$run_path/topics/pending"
in_progress="$run_path/topics/in-progress"
lockdir="$run_path/topics/.claim.lock.d"

[[ -d "$pending" ]] || { echo "ERROR: no pending/ dir at $pending" >&2; exit 2; }
# Symlink-attack defense (H-1). A symlinked pending/ would let a hostile local
# user point our atomic-mv at attacker-controlled content. Refuse loudly.
if [[ -L "$pending" ]]; then
  echo "ERROR: $pending is a symlink — refusing to claim (H-1)" >&2
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

# Pick the first pending topic. Sort deterministically (priority prefix in filename).
# `-P` makes find treat each candidate as the symlink itself (not the target).
# We deliberately DO NOT add `-type f` here — we want symlinks to surface so
# we can refuse them loudly at the explicit `[ -L ]` check below (closes H-1
# at the per-file level). Silently skipping them would be a confusing UX.
topic=$(find -P "$pending" -maxdepth 1 -name "T*.md" \( -type f -o -type l \) 2>/dev/null | sort | head -1)

if [[ -z "$topic" ]]; then
  exit 1  # no work
fi

# Defense-in-depth — the candidate file itself must not be a symlink.
if [[ -L "$topic" ]]; then
  echo "ERROR: $topic is a symlink — refusing to claim (H-1)" >&2
  exit 5
fi

base=$(basename "$topic")
dest="$in_progress/$base"
mv "$topic" "$dest"

# Counter invariant: moving pending -> in-progress decrements pending and
# increments in-progress so that
#   topics_total == done + failed + pending + in_progress
# holds throughout the claim/release/requeue cycle. Closes C-2.
bindir=$(cd "$(dirname "$0")" && pwd)
bash "$bindir/state.sh" dec "$run_path" .counters.topics_pending
bash "$bindir/state.sh" inc "$run_path" .counters.topics_in_progress

# Absolute path for downstream tooling.
echo "$(cd "$(dirname "$dest")" && pwd)/$(basename "$dest")"
