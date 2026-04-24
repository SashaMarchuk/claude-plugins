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
          validator_model: "haiku",
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
    jq -r "$json_path" "$run_path/state.json"
    ;;

  set)
    run_path="${1:?run-path required}"
    json_path="${2:?json-path required}"
    value="${3?value required}"
    state_file="$run_path/state.json"
    tmp=$(mktemp)
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Enforce .current_step enum. The enum mirrors the pipeline state
    # machine documented in skills/run/SKILL.md. Partial mitigation for
    # C-1 (gate bypass); the full gate-consult lives below.
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
    # Treat value as JSON if parseable, else as string
    if echo "$value" | jq empty 2>/dev/null; then
      jq "$json_path = $value | .updated_at = \"$now\"" "$state_file" > "$tmp"
    else
      jq --arg v "$value" "$json_path = \$v | .updated_at = \"$now\"" "$state_file" > "$tmp"
    fi
    mv "$tmp" "$state_file"
    ;;

  inc)
    run_path="${1:?run-path required}"
    counter="${2:?counter field required (e.g. .counters.topics_done)}"
    state_file="$run_path/state.json"
    lockdir="$state_file.lock.d"
    tmp=$(mktemp)
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
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
    jq "$counter += 1 | .updated_at = \"$now\"" "$state_file" > "$tmp"
    mv "$tmp" "$state_file"
    rmdir "$lockdir"
    trap - EXIT
    ;;

  dec)
    run_path="${1:?run-path required}"
    counter="${2:?counter field required (e.g. .counters.topics_pending)}"
    state_file="$run_path/state.json"
    lockdir="$state_file.lock.d"
    tmp=$(mktemp)
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
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
    jq "$counter -= 1 | .updated_at = \"$now\"" "$state_file" > "$tmp"
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
    tmp=$(mktemp)
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
