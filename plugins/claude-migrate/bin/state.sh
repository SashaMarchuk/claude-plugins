#!/usr/bin/env bash
# state.sh - CRUD operations on .planning/claude-migrate/<run>/state.json
#
# Usage:
#   state.sh init <run-name> [input-mode-hint]    - bootstrap new run
#   state.sh get  <run-path> <json-path>          - read field (e.g. .current_step)
#   state.sh set  <run-path> <json-path> <value>  - write field
#   state.sh inc  <run-path> <counters.field>     - atomic increment
#   state.sh dec  <run-path> <counters.field>     - atomic decrement
#   state.sh checkpoint <run-path>                - snapshot state.json to checkpoints/
#
# RUN_PATH is the absolute or cwd-relative path to .planning/claude-migrate/<run>/
# JSON_PATH is a jq-style path starting with "."
#
# Ported from plugins/ultra-analyzer/bin/state.sh. Adapted to the claude-migrate
# state machine (§3.1 enum), full state.json schema (§3.2), run-dir tree (§3.4),
# run-dir .gitignore (§3.8), and the 3 /ultra machine-gates (pre-split, verify,
# pre-apply) for the in-lock gate-verdict consult (§3.1, §6.6).

set -euo pipefail

# Require jq
command -v jq >/dev/null || { echo "ERROR: jq not installed" >&2; exit 1; }

# Convert a caller-provided jq-style dot-path into a JSON path array suitable
# for `getpath($p) / setpath($p; ...)`. Only accepts the limited grammar the
# pipeline actually uses:
#   .a.b.c                -> ["a","b","c"]
#   .a."quoted-seg".b     -> ["a","quoted-seg","b"]
# Anything else (pipes, commas, parens, whitespace, `[`, `]`, `=`, `;`) is a
# jq-injection attempt and is rejected. All writes go through jq --argjson with
# a validated path array, so caller values can never become jq program
# fragments. Emits the JSON array on stdout, exits 9 on rejection.
_path_to_json_array() {
  local raw="$1"
  # Must begin with "." and contain no injection-friendly metacharacters.
  case "$raw" in
    .*) ;;
    *)  echo "ERROR: json-path must start with '.' (got: $raw)" >&2; return 9 ;;
  esac
  if printf '%s' "$raw" | LC_ALL=C grep -q '[][|,()[:space:];=]'; then
    echo "ERROR: json-path rejected - contains disallowed character (got: $raw)" >&2
    return 9
  fi
  local rest="${raw#.}"
  local -a segs=()
  while [[ -n "$rest" ]]; do
    if [[ "$rest" == \"* ]]; then
      # Quoted segment: ."seg" - closing quote must precede the next . or EOS.
      rest="${rest#\"}"
      local seg="${rest%%\"*}"
      if [[ "$seg" == "$rest" ]]; then
        echo "ERROR: json-path has unterminated quoted segment (got: $raw)" >&2
        return 9
      fi
      segs+=("$seg")
      rest="${rest#$seg\"}"
    else
      # Bare segment: up to next "." or EOS. Allowed chars: [A-Za-z0-9_-].
      local seg="${rest%%.*}"
      if ! printf '%s' "$seg" | LC_ALL=C grep -qE '^[A-Za-z0-9_-]+$'; then
        echo "ERROR: json-path bare segment must match [A-Za-z0-9_-]+ (got: $seg in $raw)" >&2
        return 9
      fi
      segs+=("$seg")
      rest="${rest#$seg}"
    fi
    # Consume the separating "." (if present).
    case "$rest" in
      .*) rest="${rest#.}" ;;
      "") ;;
      *)  echo "ERROR: json-path parse error near '$rest' (got: $raw)" >&2; return 9 ;;
    esac
  done
  # Emit as JSON array.
  printf '%s\n' "${segs[@]}" | jq -R . | jq -s .
}

cmd="${1:-}"
shift || { echo "Usage: state.sh {init|get|set|inc|dec|checkpoint} ..." >&2; exit 1; }

case "$cmd" in
  init)
    run_name="${1:?run-name required}"
    # Sanitize run-name - strict allowlist to block path traversal
    # (e.g. `../../tmp/evil`) and shell-meta injection.
    [[ "$run_name" =~ ^[A-Za-z0-9_-]+$ ]] || {
      echo "ERROR: run-name must match ^[A-Za-z0-9_-]+$ (got: $run_name)" >&2
      exit 6
    }
    # Input-mode hint is free-form ("export" | "live"); informational at init -
    # actual routing goes through <run>/source-connector.md. Defaults to export.
    input_hint="${2:-export}"
    run_path=".planning/claude-migrate/${run_name}"
    # Full run-dir tree (§3.4): work queues, value/briefs/project, seed+apply
    # queues, out/, validation/, checkpoints/, state/requeue-archive/.
    mkdir -p \
      "$run_path"/units/{pending,in-progress,done,failed,dropped} \
      "$run_path"/value \
      "$run_path"/briefs \
      "$run_path"/project \
      "$run_path"/seed/{pending,in-progress,done,failed} \
      "$run_path"/apply \
      "$run_path"/out/payloads \
      "$run_path"/validation \
      "$run_path"/checkpoints \
      "$run_path"/state/requeue-archive \
      "$run_path"/source
    state_file="$run_path/state.json"
    if [[ -f "$state_file" ]]; then
      echo "ERROR: run already exists at $run_path" >&2
      exit 2
    fi
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Run-dir .gitignore (§3.8) - excludes source/, seed/, apply/, payloads,
    # screenshots, run.log, state.json, checkpoints/ from accidental commit
    # (PII safety net, Edge C-3). Written once at init; idempotent overwrite.
    cat > "$run_path/.gitignore" <<'GITIGNORE'
source/
seed/
apply/
out/payloads/
*.png
run.log
state.json
checkpoints/
GITIGNORE
    # Full state.json schema (§3.2). Default profile = large (beta).
    jq -n \
      --arg run "$run_name" \
      --arg now "$now" \
      --arg input_mode "$input_hint" \
      '{
        run: $run,
        created_at: $now,
        updated_at: $now,
        current_step: "init",
        status: "pending",
        blocked_reason: null,
        input: {
          mode: $input_mode,
          export_path: null,
          source_account_email_hash: null
        },
        output: {
          mode: "auto",
          user_chose_auto: false,
          browser: {
            transport: null,
            endpoint: null,
            authed: false,
            dest_account_email_hash: null
          }
        },
        profile: {
          tier: "large",
          preflight_model: "haiku",
          distill_model: "sonnet",
          synth_model: "opus",
          validator_model: "opus",
          ultra_gate_tier: "--large",
          parallelism: 4,
          seed_parallelism: 1,
          seed_delay_ms: 1500,
          ok_wait_ms: 45000,
          breaker_threshold: 3,
          capture_screenshots: false,
          max_brief_tokens: 7000,
          inline_card_limit: 60,
          inline_byte_limit: 1500000
        },
        gates: {
          "pre-split": {verdict: "pending", report: null},
          "filter":    {verdict: "pending", report: null, user_confirmed: false},
          "verify":    {verdict: "pending", report: null},
          "pre-apply": {verdict: "pending", report: null}
        },
        decisions: {
          preflight_value_scan: true,
          naming_convention: "keep",
          onboarding_ok_protocol: "ok-then-strip",
          memories: "skip",
          cost_acknowledged: false,
          auto_reoffer_ack: false,
          project_assignment: {}
        },
        counters: {
          chats_total: 0,
          preflight_pending: 0,
          preflight_in_progress: 0,
          preflight_done: 0,
          preflight_failed: 0,
          kept: 0,
          dropped: 0,
          seeded_units: 0,
          doc_only_units: 0,
          distill_pending: 0,
          distill_in_progress: 0,
          distill_done: 0,
          distill_failed: 0,
          briefs_verified_ok: 0,
          briefs_verified_fail: 0,
          seed_pending: 0,
          seed_in_progress: 0,
          seed_done: 0,
          seed_failed: 0,
          seeded: 0,
          renamed: 0,
          ok_protocol_miss: 0,
          projects_total: 0,
          projects_pending: 0,
          projects_created: 0,
          projects_finalized: 0
        },
        cost_estimate: {
          in_tokens: 0,
          out_tokens_est: 0,
          usd_low: 0,
          usd_high: 0,
          model_blend: null
        },
        last_checkpoint: null
      }' > "$state_file"
    echo "$run_path"
    ;;

  get)
    run_path="${1:?run-path required}"
    json_path="${2:?json-path required}"
    path_arr=$(_path_to_json_array "$json_path") || exit 9
    # Match legacy `jq -r '.path'` output: string -> unquoted, null -> "null",
    # scalar (number/bool) -> its textual form, object/array -> compact JSON.
    jq -r --argjson p "$path_arr" '
      getpath($p) as $v
      | if   $v == null   then "null"
        elif ($v|type) == "string" then $v
        elif ($v|type) == "number" or ($v|type) == "boolean" then ($v|tostring)
        else ($v|tojson) end
    ' "$run_path/state.json"
    ;;

  set)
    run_path="${1:?run-path required}"
    json_path="${2:?json-path required}"
    value="${3?value required}"
    state_file="$run_path/state.json"
    lockdir="$state_file.lock.d"
    # tmp MUST live on the same filesystem as state_file so the final mv is
    # rename(2)-atomic. Default mktemp puts files in $TMPDIR, which on macOS
    # is on a different filesystem and degrades the mv to copy-then-delete -
    # breaking the atomicity contract a concurrent reader relies on.
    tmp=$(mktemp "$run_path/.state.set.XXXXXX")
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Validate path up front so we fail fast without taking the lock.
    # Caller-supplied text is never interpolated into the jq program string;
    # only --argjson values reach jq.
    path_arr=$(_path_to_json_array "$json_path") || { rm -f "$tmp"; exit 9; }
    # Enforce .current_step HARD ENUM (§3.1). The enum mirrors the pipeline
    # state machine documented in skills/run/SKILL.md. Any other value -> exit 7.
    if [[ "$json_path" == ".current_step" ]]; then
      # Strip surrounding quotes if value is JSON-encoded (e.g. '"split"').
      step_val="${value#\"}"; step_val="${step_val%\"}"
      case "$step_val" in
        init|pre-split-gate|split|preflight|filter-gate|distill|synthesize|build-page|verify-gate|ready|pre-apply-gate|apply|finalize|done|failed) ;;
        *)
          echo "ERROR: .current_step must be one of {init, pre-split-gate, split, preflight, filter-gate, distill, synthesize, build-page, verify-gate, ready, pre-apply-gate, apply, finalize, done, failed} (got: $step_val)" >&2
          rm -f "$tmp"
          exit 7
          ;;
      esac
    fi
    # Take the same mkdir-based lock as `inc`/`dec` so a concurrent set and
    # inc cannot read-modify-write stale JSON and clobber each other.
    waited=0
    while ! mkdir "$lockdir" 2>/dev/null; do
      sleep 0.1
      waited=$((waited + 1))
      if [[ $waited -gt 300 ]]; then
        echo "ERROR: state.sh set lock timeout on $lockdir (held by another worker for >30s)" >&2
        rm -f "$tmp"
        exit 4
      fi
    done
    trap 'rmdir "$lockdir" 2>/dev/null || true; rm -f "$tmp"' EXIT
    # Gate-consult runs INSIDE the lock so the verdict we read is the verdict
    # we write against - another writer cannot flip the gate between our
    # read and our mv. The 3 /ultra machine-gates (§3.1, §6.6):
    #   GATE 1 pre-split  -> required PASS before `split` (and everything after)
    #   GATE 2 verify     -> required PASS before `ready` (and everything after)
    #   GATE 3 pre-apply  -> required PASS before `apply` (and `finalize`/`done`)
    if [[ "$json_path" == ".current_step" ]]; then
      step_val="${value#\"}"; step_val="${step_val%\"}"
      pre_split_verdict=$(jq -r '.gates."pre-split".verdict // "pending"' "$state_file")
      verify_verdict=$(jq -r '.gates."verify".verdict // "pending"' "$state_file")
      pre_apply_verdict=$(jq -r '.gates."pre-apply".verdict // "pending"' "$state_file")
      _gate_fail() {
        echo "ERROR: cannot advance .current_step to '$step_val' - $1" >&2
        rmdir "$lockdir" 2>/dev/null || true
        rm -f "$tmp"
        trap - EXIT
        exit 8
      }
      case "$step_val" in
        split|preflight|filter-gate|distill|synthesize|build-page|verify-gate)
          [[ "$pre_split_verdict" == "PASS" ]] || _gate_fail "gates.pre-split.verdict is '$pre_split_verdict' (require PASS)"
          ;;
        ready)
          [[ "$pre_split_verdict" == "PASS" ]] || _gate_fail "gates.pre-split.verdict is '$pre_split_verdict' (require PASS)"
          [[ "$verify_verdict" == "PASS" ]] || _gate_fail "gates.verify.verdict is '$verify_verdict' (require PASS)"
          ;;
        pre-apply-gate)
          [[ "$pre_split_verdict" == "PASS" ]] || _gate_fail "gates.pre-split.verdict is '$pre_split_verdict' (require PASS)"
          [[ "$verify_verdict" == "PASS" ]] || _gate_fail "gates.verify.verdict is '$verify_verdict' (require PASS)"
          ;;
        apply|finalize|done)
          [[ "$pre_split_verdict" == "PASS" ]] || _gate_fail "gates.pre-split.verdict is '$pre_split_verdict' (require PASS)"
          [[ "$verify_verdict" == "PASS" ]] || _gate_fail "gates.verify.verdict is '$verify_verdict' (require PASS)"
          [[ "$pre_apply_verdict" == "PASS" ]] || _gate_fail "gates.pre-apply.verdict is '$pre_apply_verdict' (require PASS)"
          ;;
      esac
    fi
    if echo "$value" | jq empty 2>/dev/null; then
      jq --argjson p "$path_arr" --argjson v "$value" --arg now "$now" \
         'setpath($p; $v) | .updated_at = $now' "$state_file" > "$tmp"
    else
      jq --argjson p "$path_arr" --arg v "$value" --arg now "$now" \
         'setpath($p; $v) | .updated_at = $now' "$state_file" > "$tmp"
    fi
    mv "$tmp" "$state_file"
    rmdir "$lockdir"
    trap - EXIT
    ;;

  inc)
    run_path="${1:?run-path required}"
    counter="${2:?counter field required (e.g. .counters.preflight_done)}"
    state_file="$run_path/state.json"
    lockdir="$state_file.lock.d"
    # Same-filesystem tmp so the final mv is rename(2)-atomic on macOS too.
    tmp=$(mktemp "$run_path/.state.inc.XXXXXX")
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Validate+serialize path before acquiring the lock so we fail fast.
    path_arr=$(_path_to_json_array "$counter") || { rm -f "$tmp"; exit 9; }
    # Portable mkdir-based lock (works on macOS without flock).
    # Atomic: mkdir fails if dir exists. Spin with cap to avoid deadlock.
    waited=0
    while ! mkdir "$lockdir" 2>/dev/null; do
      sleep 0.1
      waited=$((waited + 1))
      if [[ $waited -gt 300 ]]; then
        echo "ERROR: state.sh inc lock timeout on $lockdir (held by another worker for >30s)" >&2
        rm -f "$tmp"
        exit 4
      fi
    done
    # Ensure lock is released even on error.
    trap 'rmdir "$lockdir" 2>/dev/null || true; rm -f "$tmp"' EXIT
    # Parameterized: no caller text enters the jq program string.
    jq --argjson p "$path_arr" --arg now "$now" \
       'setpath($p; (getpath($p) // 0) + 1) | .updated_at = $now' \
       "$state_file" > "$tmp"
    mv "$tmp" "$state_file"
    rmdir "$lockdir"
    trap - EXIT
    ;;

  dec)
    run_path="${1:?run-path required}"
    counter="${2:?counter field required (e.g. .counters.preflight_pending)}"
    state_file="$run_path/state.json"
    lockdir="$state_file.lock.d"
    # Same-filesystem tmp so the final mv is rename(2)-atomic on macOS too.
    tmp=$(mktemp "$run_path/.state.dec.XXXXXX")
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    path_arr=$(_path_to_json_array "$counter") || { rm -f "$tmp"; exit 9; }
    # Same mkdir-based lock discipline as `inc`.
    waited=0
    while ! mkdir "$lockdir" 2>/dev/null; do
      sleep 0.1
      waited=$((waited + 1))
      if [[ $waited -gt 300 ]]; then
        echo "ERROR: state.sh dec lock timeout on $lockdir (held by another worker for >30s)" >&2
        rm -f "$tmp"
        exit 4
      fi
    done
    trap 'rmdir "$lockdir" 2>/dev/null || true; rm -f "$tmp"' EXIT
    jq --argjson p "$path_arr" --arg now "$now" \
       'setpath($p; (getpath($p) // 0) - 1) | .updated_at = $now' \
       "$state_file" > "$tmp"
    mv "$tmp" "$state_file"
    rmdir "$lockdir"
    trap - EXIT
    ;;

  checkpoint)
    run_path="${1:?run-path required}"
    state_file="$run_path/state.json"
    now=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
    snap="$run_path/checkpoints/$now.json"
    cp "$state_file" "$snap"
    # Same-filesystem tmp so the final mv is rename(2)-atomic on macOS too.
    tmp=$(mktemp "$run_path/.state.checkpoint.XXXXXX")
    jq --arg cp "$snap" '.last_checkpoint = $cp' "$state_file" > "$tmp"
    mv "$tmp" "$state_file"
    echo "$snap"
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    echo "Usage: state.sh {init|get|set|inc|dec|checkpoint} ..." >&2
    exit 1
    ;;
esac
