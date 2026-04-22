#!/usr/bin/env bash
# release.sh — route a completed topic to done/failed/requeue.
#
# Usage:
#   release.sh <topic-path> done
#   release.sh <topic-path> failed
#   release.sh <topic-path> requeue <reason-slug>

set -euo pipefail

topic="${1:?topic-path required}"
outcome="${2:?outcome required (done|failed|requeue)}"
reason="${3:-unspecified}"

base=$(basename "$topic")
dir=$(dirname "$topic")
run_path=$(dirname "$(dirname "$dir")")  # topics/in-progress/X → run-path

# Two-stage move: rename to temp (excluded from sweeps by pattern), then to destination.
tmp="$dir/${base%.md}.release-tmp.$$.md"
mv "$topic" "$tmp"

bindir=$(cd "$(dirname "$0")" && pwd)

case "$outcome" in
  done)
    mkdir -p "$run_path/topics/done"
    mv "$tmp" "$run_path/topics/done/$base"
    bash "$bindir/state.sh" inc "$run_path" .counters.topics_done
    ;;
  failed)
    mkdir -p "$run_path/topics/failed"
    mv "$tmp" "$run_path/topics/failed/$base"
    bash "$bindir/state.sh" inc "$run_path" .counters.topics_failed
    ;;
  requeue)
    mkdir -p "$run_path/topics/pending"
    tagged="${base%.md}__retry-$(date +%s)-${reason}.md"
    mv "$tmp" "$run_path/topics/pending/$tagged"
    # Do not increment done/failed — topic remains unresolved.
    ;;
  *)
    echo "ERROR: unknown outcome: $outcome" >&2
    exit 1
    ;;
esac

# Append to run log (JSONL for later aggregation).
log="$run_path/run.log"
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"ts":"%s","topic":"%s","outcome":"%s","reason":"%s"}\n' "$ts" "$base" "$outcome" "$reason" >> "$log"
