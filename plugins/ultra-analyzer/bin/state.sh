#!/usr/bin/env bash
# state.sh — CRUD operations on .planning/ultra-analyzer/<run>/state.json
#
# Usage:
#   state.sh init <run-name> <connector-hint>    — bootstrap new run
#   state.sh get  <run-path> <json-path>          — read field (e.g. .current_step)
#   state.sh set  <run-path> <json-path> <value>  — write field
#   state.sh inc  <run-path> <counters.field>     — atomic increment
#   state.sh dec  <run-path> <counters.field>     — atomic decrement
#   state.sh checkpoint <run-path>                — snapshot state.json to checkpoints/
#
# RUN_PATH is the absolute or cwd-relative path to .planning/ultra-analyzer/<run>/
# JSON_PATH is a jq-style path starting with "."

set -euo pipefail

# Require jq
command -v jq >/dev/null || { echo "ERROR: jq not installed" >&2; exit 1; }

# Convert a caller-provided jq-style dot-path into a JSON path array suitable
# for `getpath($p) / setpath($p; ...)`. Only accepts the limited grammar the
# analyzer actually uses:
#   .a.b.c                -> ["a","b","c"]
#   .a."quoted-seg".b     -> ["a","quoted-seg","b"]
# Anything else (pipes, commas, parens, whitespace, `[`, `]`, `=`, `;`) is a
# jq-injection attempt and is rejected. Closes H-2 systemically — all writes
# now go through jq --argjson with a validated path array, so caller values
# can never become jq program fragments. Emits the JSON array on stdout,
# exits 9 on rejection.
_path_to_json_array() {
  local raw="$1"
  # Must begin with "." and contain no injection-friendly metacharacters.
  case "$raw" in
    .*) ;;
    *)  echo "ERROR: json-path must start with '.' (got: $raw)" >&2; return 9 ;;
  esac
  if printf '%s' "$raw" | LC_ALL=C grep -q '[][|,()[:space:];=]'; then
    echo "ERROR: json-path rejected — contains disallowed character (got: $raw)" >&2
    return 9
  fi
  local rest="${raw#.}"
  local -a segs=()
  while [[ -n "$rest" ]]; do
    if [[ "$rest" == \"* ]]; then
      # Quoted segment: ."seg" — closing quote must precede the next . or EOS.
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
    # Sanitize run-name — strict allowlist to block path traversal
    # (e.g. `../../tmp/evil`) and shell-meta injection. Closes H-3.
    [[ "$run_name" =~ ^[A-Za-z0-9_-]+$ ]] || {
      echo "ERROR: run-name must match ^[A-Za-z0-9_-]+$ (got: $run_name)" >&2
      exit 6
    }
    # Connector hint is free-form (e.g. "mongo", "fs", "custom", "github-api").
    # Informational only — actual routing goes through <run>/connector.md.
    connector_hint="${2:-custom}"
    run_path=".planning/ultra-analyzer/${run_name}"
    mkdir -p "$run_path"/{topics/{pending,in-progress,done,failed},findings,validation/findings,synthesis,checkpoints,state}
    state_file="$run_path/state.json"
    if [[ -f "$state_file" ]]; then
      echo "ERROR: run already exists at $run_path" >&2
      exit 2
    fi
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Default profile = large. Can be changed later via /ultra-analyzer:set-profile.
    jq -n \
      --arg run "$run_name" \
      --arg now "$now" \
      --arg hint "$connector_hint" \
      --arg cfg "$run_path/config.yaml" \
      --arg seeds "$run_path/seeds.md" \
      --arg connector "$run_path/connector.md" \
      '{
        run: $run,
        created_at: $now,
        updated_at: $now,
        connector_hint: $hint,
        config_path: $cfg,
        seeds_path: $seeds,
        connector_path: $connector,
        current_step: "init",
        status: "pending",
        profile: {
          tier: "large",
          ultra_gate_tier: "--large",
          worker_model: "sonnet",
          worker_model_complexity_S: "haiku",
          validator_model: "opus",
          validator_model_complexity_S: "sonnet",
          synthesizer_model: "opus",
          topic_target_min: 45,
          topic_target_max: 70,
          redundancy_pair_rate_p1: 0.60,
          suggested_parallel_terminals: "3-5"
        },
        ultra_gates: {
          "pre-discover": {verdict: "pending", report: null},
          "pre-synthesize": {verdict: "pending", report: null}
        },
        counters: {
          topics_total: 0,
          topics_done: 0,
          topics_failed: 0,
          topics_pending: 0,
          topics_in_progress: 0,
          findings_passed: 0,
          findings_failed: 0
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
    # is on a different filesystem and degrades the mv to copy-then-delete —
    # breaking the atomicity contract a concurrent reader relies on.
    tmp=$(mktemp "$run_path/.state.set.XXXXXX")
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Validate path up front so we fail fast without taking the lock.
    # Caller-supplied text is never interpolated into the jq program string;
    # only --argjson values reach jq. Closes H-2.
    path_arr=$(_path_to_json_array "$json_path") || { rm -f "$tmp"; exit 9; }
    # Enforce .current_step enum. The enum mirrors the pipeline state
    # machine documented in skills/run/SKILL.md. Partial mitigation for
    # C-1 (gate bypass); the full gate-consult layers on top below.
    if [[ "$json_path" == ".current_step" ]]; then
      # Strip surrounding quotes if value is JSON-encoded (e.g. '"discover"').
      step_val="${value#\"}"; step_val="${step_val%\"}"
      case "$step_val" in
        init|pre-discover-gate|discover|analyze|pre-synthesize-gate|synthesize|done|failed) ;;
        *)
          echo "ERROR: .current_step must be one of {init, pre-discover-gate, discover, analyze, pre-synthesize-gate, synthesize, done, failed} (got: $step_val)" >&2
          rm -f "$tmp"
          exit 7
          ;;
      esac
    fi
    # Take the same mkdir-based lock as `inc`/`dec` so a concurrent set and
    # inc cannot read-modify-write stale JSON and clobber each other.
    # Closes H-7.
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
    # we write against — another writer cannot flip the gate between our
    # read and our mv. Closes C-1.
    if [[ "$json_path" == ".current_step" ]]; then
      step_val="${value#\"}"; step_val="${step_val%\"}"
      pre_discover_verdict=$(jq -r '.ultra_gates."pre-discover".verdict // "pending"' "$state_file")
      pre_synthesize_verdict=$(jq -r '.ultra_gates."pre-synthesize".verdict // "pending"' "$state_file")
      case "$step_val" in
        discover|analyze|pre-synthesize-gate)
          if [[ "$pre_discover_verdict" != "PASS" ]]; then
            echo "ERROR: cannot advance .current_step to '$step_val' — ultra_gates.pre-discover.verdict is '$pre_discover_verdict' (require PASS)" >&2
            rmdir "$lockdir" 2>/dev/null || true
            rm -f "$tmp"
            trap - EXIT
            exit 8
          fi
          ;;
        synthesize|done)
          if [[ "$pre_discover_verdict" != "PASS" ]]; then
            echo "ERROR: cannot advance .current_step to '$step_val' — ultra_gates.pre-discover.verdict is '$pre_discover_verdict' (require PASS)" >&2
            rmdir "$lockdir" 2>/dev/null || true
            rm -f "$tmp"
            trap - EXIT
            exit 8
          fi
          if [[ "$pre_synthesize_verdict" != "PASS" ]]; then
            echo "ERROR: cannot advance .current_step to '$step_val' — ultra_gates.pre-synthesize.verdict is '$pre_synthesize_verdict' (require PASS)" >&2
            rmdir "$lockdir" 2>/dev/null || true
            rm -f "$tmp"
            trap - EXIT
            exit 8
          fi
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
    counter="${2:?counter field required (e.g. .counters.topics_done)}"
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
    # Parameterized: no caller text enters the jq program string. Closes H-2.
    jq --argjson p "$path_arr" --arg now "$now" \
       'setpath($p; (getpath($p) // 0) + 1) | .updated_at = $now' \
       "$state_file" > "$tmp"
    mv "$tmp" "$state_file"
    rmdir "$lockdir"
    trap - EXIT
    ;;

  dec)
    run_path="${1:?run-path required}"
    counter="${2:?counter field required (e.g. .counters.topics_pending)}"
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
