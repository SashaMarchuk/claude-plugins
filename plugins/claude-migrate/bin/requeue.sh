#!/usr/bin/env bash
# requeue.sh - move a distilled unit from units/done/ back to units/pending/ with
# a retry tag. Used by GATE 2 (verify-gate) when /ultra or the byte-exact verify
# flags a brief that should not have passed (hallucination / leaked PII /
# injection-class string). Archives the prior brief under state/requeue-archive/
# for an audit trail, then adjusts counters so BOTH the distill (units-queue)
# invariant AND the seed invariant stay intact (§3.3).
#
# Usage:
#   requeue.sh <run-path> <unit-basename> <reason-slug>
#
# Example:
#   requeue.sh .planning/claude-migrate/my-run U012__topic-1.md ungrounded-claims
#
# Counter law (§3.3):
#   - ALWAYS: dec distill_done, inc distill_pending      (units-queue done -> pending)
#   - CONDITIONAL: dec briefs_verified_ok                (only if prior verdict was PASS)
#   - CONDITIONAL: if a seed item already exists for this unit, move it back to
#     seed/pending/ and re-add to seed_pending so the seed invariant
#     `seeded_units == seed_{pending+in_progress+done+failed}` is NOT broken.

# Strict mode: a failed `mv` (done -> temp -> pending) MUST abort before any
# `state.sh inc/dec` runs, so a half-completed move can never desync the
# distill/seed SUM invariants (§3.3). Linear move-then-count, no retry loop, so
# `-e` is correct here (unlike launch-worker.sh's retry loop, which uses `-uo`).
set -euo pipefail

run_path="${1:?run-path required}"
unit_base="${2:?unit basename required (e.g. U012__topic-1.md)}"
reason="${3:-gate2-requeue}"

bindir=$(cd "$(dirname "$0")" && pwd)

done_path="$run_path/units/done/$unit_base"
[[ -f "$done_path" ]] || { echo "ERROR: unit not in units/done/: $done_path" >&2; exit 2; }

stem="${unit_base%.md}"
# UNNN is the leading numeric token of the basename (e.g. U012 from U012__topic-1.md).
unnn="${stem%%__*}"
# Strip any retry tag already present so re-requeues don't compound it.
unnn="${unnn%%__retry-*}"

# Two-stage move (units/done -> temp -> units/pending) so a sweep never catches
# a half-moved file.
tmp="$run_path/units/done/${stem}.requeue-tmp.$$.md"
mv "$done_path" "$tmp"
tagged="${stem}__retry-$(date +%s)-${reason}.md"
mkdir -p "$run_path/units/pending"
mv "$tmp" "$run_path/units/pending/$tagged"

# Archive the prior brief + name + verify verdict under state/requeue-archive/,
# then remove the live brief so the next distill run regenerates it.
archive="$run_path/state/requeue-archive"
mkdir -p "$archive"
ts=$(date +%s)

brief_file="$run_path/briefs/${unnn}.brief.md"
name_file="$run_path/briefs/${unnn}.name.txt"
verdict_file="$run_path/validation/verify-${unnn}.json"

if [[ -f "$brief_file" ]]; then
  cp "$brief_file" "$archive/${unnn}.${ts}.brief.md"
  rm -f "$brief_file"
fi
if [[ -f "$name_file" ]]; then
  cp "$name_file" "$archive/${unnn}.${ts}.name.txt"
  rm -f "$name_file"
fi

# ALWAYS adjust the units-queue (distill) counters to preserve the invariant.
# units/done -> units/pending regardless of prior verify verdict.
bash "$bindir/state.sh" dec "$run_path" .counters.distill_done
bash "$bindir/state.sh" inc "$run_path" .counters.distill_pending

# CONDITIONAL: only decrement briefs_verified_ok if the prior verdict was PASS.
prior_verdict="unknown"
if [[ -f "$verdict_file" ]]; then
  prior_verdict=$(jq -r '.verdict // "unknown"' "$verdict_file" 2>/dev/null || echo "unknown")
  cp "$verdict_file" "$archive/${unnn}.${ts}.verify.json"
  rm -f "$verdict_file"
fi
if [[ "$prior_verdict" == "PASS" ]]; then
  bash "$bindir/state.sh" dec "$run_path" .counters.briefs_verified_ok
fi

# CONDITIONAL: if a seed item already exists for this unit (the unit was already
# pushed to the browser-sink apply queue), move it back to seed/pending/ so the
# seed invariant is preserved. Probe in-progress/done/failed in that order; the
# pending location is already correct.
seed_base="${unnn}.json"
for state_dir in in-progress done failed; do
  src="$run_path/seed/$state_dir/$seed_base"
  if [[ -f "$src" ]]; then
    mkdir -p "$run_path/seed/pending"
    mv "$src" "$run_path/seed/pending/$seed_base"
    # Re-add to seed_pending; remove from whichever counter the source dir owns.
    bash "$bindir/state.sh" inc "$run_path" .counters.seed_pending
    case "$state_dir" in
      in-progress) bash "$bindir/state.sh" dec "$run_path" .counters.seed_in_progress ;;
      done)        bash "$bindir/state.sh" dec "$run_path" .counters.seed_done ;;
      failed)      bash "$bindir/state.sh" dec "$run_path" .counters.seed_failed ;;
    esac
    break
  fi
done

# Append to run log (JSONL). The reason is a caller-supplied slug; redaction for
# free-form reasons lives in release.sh - requeue reasons are gate slugs.
log="$run_path/run.log"
now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"ts":"%s","queue":"units","item":"%s","outcome":"requeue-from-done","reason":"%s"}\n' \
  "$now_iso" "$unit_base" "$reason" >> "$log"

echo "requeued: $tagged"
