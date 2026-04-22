#!/usr/bin/env bash
# requeue.sh — move a topic from done/ back to pending/ with retry tag.
# Used by Gate 2 (pre-synthesize) when /ultra flags a finding that should
# not have passed. Decrements counters.topics_done and counters.findings_passed
# (if the finding was counted as passed) and increments counters.topics_pending.
#
# Usage:
#   requeue.sh <run-path> <topic-basename> <reason-slug>
#
# Example:
#   requeue.sh .planning/ultra-analyzer/my-run T042__p1__foo.md ungrounded-claims

set -euo pipefail

run_path="${1:?run-path required}"
topic_base="${2:?topic basename required}"
reason="${3:-gate2-requeue}"

done_path="$run_path/topics/done/$topic_base"
[[ -f "$done_path" ]] || { echo "ERROR: topic not in done/: $done_path" >&2; exit 2; }

bindir=$(cd "$(dirname "$0")" && pwd)

# Two-stage move.
tmp="$run_path/topics/done/${topic_base%.md}.requeue-tmp.$$.md"
mv "$done_path" "$tmp"

# Tag and relocate to pending/.
tagged="${topic_base%.md}__retry-$(date +%s)-${reason}.md"
mv "$tmp" "$run_path/topics/pending/$tagged"

# Counter adjustment: done -> pending. Also invalidate the prior findings file
# so the next worker run regenerates it.
finding_file="$run_path/findings/${topic_base%.md}.md"
verdict_file="$run_path/validation/findings/${topic_base%.md}.json"

# Archive the prior finding + verdict under state/requeue-archive/ for audit trail.
archive="$run_path/state/requeue-archive"
mkdir -p "$archive"
ts=$(date +%s)
if [[ -f "$finding_file" ]]; then
  cp "$finding_file" "$archive/${topic_base%.md}.${ts}.findings.md"
  rm "$finding_file"
fi
if [[ -f "$verdict_file" ]]; then
  # Only decrement findings_passed if the prior verdict was PASS.
  prior_verdict=$(jq -r '.verdict' "$verdict_file" 2>/dev/null || echo "unknown")
  cp "$verdict_file" "$archive/${topic_base%.md}.${ts}.verdict.json"
  rm "$verdict_file"
  if [[ "$prior_verdict" == "PASS" ]]; then
    # Manual decrement via jq (state.sh has no dec op).
    state_file="$run_path/state.json"
    lockdir="$state_file.lock.d"
    waited=0
    while ! mkdir "$lockdir" 2>/dev/null; do
      sleep 0.1
      waited=$((waited + 1))
      [[ $waited -gt 300 ]] && { echo "ERROR: lock timeout on requeue" >&2; exit 3; }
    done
    trap 'rmdir "$lockdir" 2>/dev/null || true' EXIT
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    tmp_state=$(mktemp)
    jq ".counters.topics_done -= 1 | .counters.findings_passed -= 1 | .updated_at = \"$now\"" \
       "$state_file" > "$tmp_state"
    mv "$tmp_state" "$state_file"
    rmdir "$lockdir"
    trap - EXIT
  fi
fi

# Append to run log.
log="$run_path/run.log"
now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"ts":"%s","topic":"%s","outcome":"requeue-from-done","reason":"%s"}\n' \
  "$now_iso" "$topic_base" "$reason" >> "$log"

echo "requeued: $tagged"
