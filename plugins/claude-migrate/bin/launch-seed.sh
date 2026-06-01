#!/usr/bin/env bash
# launch-seed.sh - thin ADVISORY helper for the in-session serial apply step.
#
# Usage:
#   launch-seed.sh <run-path>
#
# IMPORTANT - this is NOT a `--print` subprocess spawner (UX H-6 / Repo M-3).
# In v0.1.0 the apply step runs IN the user's interactive session so it can hold
# the single MCP browser connection. The apply-unit skill is invoked via the
# Skill tool from run/resume, iterating the seed queue SERIALLY. This script
# only PRINTS the deterministic plan the in-session controller should follow:
# - the project-creation prelude order (per-project, locked, probe-then-adopt),
# - the per-unit claim -> seed -> await-first-turn -> rename sequence,
# - the seed_delay_ms pacing between submissions.
# It performs no browser work, spawns no model subprocess, and never contends
# for the MCP browser. seed_parallelism is documented as 1 in v0.1.0;
# seed_parallelism>1 is reserved for a future CDP-library path (each tab = a
# separate Node context).

set -uo pipefail

run_path="${1:?run-path required}"
state_file="$run_path/state.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "[seed-plan] FATAL: jq not installed - cannot read state.json" >&2
  exit 1
fi
if [[ ! -f "$state_file" ]]; then
  echo "[seed-plan] FATAL: no state.json at $state_file" >&2
  exit 2
fi

# Pacing + concurrency knobs from the run profile (SPEC §3.2). seed_parallelism
# is read but enforced to 1 in v0.1.0: any value >1 is clamped with a notice so
# the advisory plan never implies parallel seeding.
seed_delay_ms=$(jq -r '.profile.seed_delay_ms // 1500' "$state_file")
ok_wait_ms=$(jq -r '.profile.ok_wait_ms // 45000' "$state_file")
seed_parallelism=$(jq -r '.profile.seed_parallelism // 1' "$state_file")
breaker_threshold=$(jq -r '.profile.breaker_threshold // 3' "$state_file")
output_mode=$(jq -r '.output.mode // "auto"' "$state_file")

if [[ "$seed_parallelism" != "1" ]]; then
  echo "[seed-plan] NOTE: seed_parallelism=$seed_parallelism requested, but v0.1.0 apply is SERIAL (clamped to 1)."
  seed_parallelism=1
fi

if [[ "$output_mode" == "copy-page" ]]; then
  echo "[seed-plan] output.mode=copy-page - no browser apply. The copy page (out/index.html) is the deliverable."
  echo "[seed-plan] Nothing to seed. ready is terminal in copy-page mode."
  exit 0
fi

seed_dir="$run_path/seed/pending"
pending_count=0
if [[ -d "$seed_dir" ]]; then
  # Count only non-symlink JSON unit files; do not follow symlinks.
  pending_count=$(find -P "$seed_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
fi

# Discover the per-project create order: stable PNN__slug sort over project/.
# This is the prelude - every needed project is created (locked, probe-then-adopt)
# BEFORE any chat is seeded into it.
project_root="$run_path/project"
projects=()
if [[ -d "$project_root" ]]; then
  while IFS= read -r d; do
    [[ -n "$d" ]] && projects+=("$(basename "$d")")
  done < <(find -P "$project_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
fi

echo "=============================================================="
echo " claude-migrate - apply plan (in-session serial, v0.1.0)"
echo "=============================================================="
echo " run-path           : $run_path"
echo " output.mode        : $output_mode"
echo " seed_parallelism   : $seed_parallelism (SERIAL - v0.1.0)"
echo " seed_delay_ms      : $seed_delay_ms  (pause between submissions)"
echo " ok_wait_ms         : $ok_wait_ms  (bounded await-first-turn)"
echo " breaker_threshold  : $breaker_threshold consecutive transport/auth failures -> stop + re-probe"
echo " seed units pending : $pending_count"
echo
echo " STEP A - project-creation prelude (serial, per-project locked, probe-then-adopt):"
if [[ ${#projects[@]} -eq 0 ]]; then
  echo "   (no projects in project/ - all kept chats seed as STANDALONE)"
else
  i=0
  for p in "${projects[@]}"; do
    i=$((i + 1))
    echo "   $i. create_project '$p'"
    echo "        - acquire project/$p/.create.lock.d (per-project mkdir lock)"
    echo "        - dedupe_probe destination by target name; adopt handle if it already exists"
    echo "        - set instructions-migration.md (instructions_mode=migration)"
    echo "        - release project/$p/.create.lock.d"
  done
fi
echo
echo " STEP B - seed loop (claim ONE unit at a time, in sorted order):"
echo "   for each seed/UNNN.json in seed/pending/ (serial):"
echo "     1. claim:  bash \$(dirname \$0)/claim.sh $run_path seed"
echo "     2. invoke /claude-migrate:apply-unit via the Skill tool (IN-SESSION),"
echo "        which performs SINK seed_unit -> await first turn -> finalize_unit:"
echo "          a. write seed/UNNN.json status=opened (write-ahead, BEFORE submit)"
echo "          b. seed_unit: paste the brief (never type char-by-char) + submit"
echo "          c. on successful submit: atomic write status=seeded + dest_chat_url"
echo "          d. await_first_turn: block on first assistant turn, bounded ${ok_wait_ms}ms"
echo "             - non-bare-OK first reply -> ok_protocol_miss=true (STILL rename)"
echo "             - timeout -> stay seeded + last_error=ok_timeout (resume re-polls)"
echo "          e. finalize_unit: rename to briefs/UNNN.name.txt (idempotent)"
echo "          f. release:  bash \$(dirname \$0)/release.sh <seed/UNNN.json> done"
echo "     3. pace:   pause ${seed_delay_ms}ms before claiming the next unit"
echo
echo " CIRCUIT BREAKER: >=${breaker_threshold} consecutive transport/auth-class failures"
echo "   -> stop claiming, set status=blocked (browser-lost), re-probe, fire G-BROWSER."
echo "   rate_limited -> unit back to pending with backoff, never failed."
echo
echo " STEP C - finalize (after the seed queue drains):"
echo "   finalize_run: swap EVERY created project migration -> steady"
echo "   (instructions_mode=steady, projects_finalized++). On any per-project"
echo "   failure -> status=blocked (NOT done) with the un-stripped list + steady"
echo "   file path. Never reach done with a project in migration mode."
echo "=============================================================="
