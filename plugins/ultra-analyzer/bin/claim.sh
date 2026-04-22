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
topic=$(find "$pending" -maxdepth 1 -name "T*.md" -type f 2>/dev/null | sort | head -1)

if [[ -z "$topic" ]]; then
  exit 1  # no work
fi

base=$(basename "$topic")
dest="$in_progress/$base"
mv "$topic" "$dest"

# Absolute path for downstream tooling.
echo "$(cd "$(dirname "$dest")" && pwd)/$(basename "$dest")"
