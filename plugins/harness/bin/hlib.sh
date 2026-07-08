#!/usr/bin/env bash
# hlib.sh — shared helpers for the harness engine. Source this; do not execute.
# Everything here is deterministic: config lookups, path guards, run-state paths, logging.

set -uo pipefail

HARNESS_USER_DIR="${HARNESS_USER_DIR:-$HOME/.claude/harness}"
HARNESS_USER_CONFIG="$HARNESS_USER_DIR/config.json"

# ---------------------------------------------------------------- project root
# Walk up from $PWD (or $HARNESS_PROJECT if exported) to the nearest .harness/config.json.
hproject_root() {
  if [ -n "${HARNESS_PROJECT:-}" ]; then
    [ -f "$HARNESS_PROJECT/.harness/config.json" ] && { printf '%s\n' "$HARNESS_PROJECT"; return 0; }
    echo "ERROR: HARNESS_PROJECT=$HARNESS_PROJECT has no .harness/config.json" >&2; return 1
  fi
  local d="$PWD"
  while [ "$d" != "/" ]; do
    [ -f "$d/.harness/config.json" ] && { printf '%s\n' "$d"; return 0; }
    d=$(dirname "$d")
  done
  echo "ERROR: no .harness/config.json found from $PWD upward — run /harness:init first" >&2
  return 1
}

# ------------------------------------------------------------------ config: cfg
# cfg <jq-path> <default>  → project value, else user value, else default.
# jq-path example: '.limits.pause_next_spawn_at'
cfg() {
  local path="${1:?jq path required}" def="${2-}"
  local v proj
  if proj=$(hproject_root 2>/dev/null); then
    v=$(jq -er "$path // empty" "$proj/.harness/config.json" 2>/dev/null) && [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
  fi
  if [ -f "$HARNESS_USER_CONFIG" ]; then
    v=$(jq -er "$path // empty" "$HARNESS_USER_CONFIG" 2>/dev/null) && [ -n "$v" ] && { printf '%s\n' "$v"; return 0; }
  fi
  printf '%s\n' "$def"
}

# ------------------------------------------------------------------- run state
# Run layout: <project>/.harness/runs/<run-id>/{launchers,prompts,state,logs,heartbeats,markers}
# <project>/.harness/CURRENT holds the active run id. STOP file: <project>/.harness/STOP
hruns_dir()   { printf '%s/.harness/runs\n' "$(hproject_root)"; }
hstop_file()  { printf '%s/.harness/STOP\n' "$(hproject_root)"; }
hcurrent_run() {
  local proj; proj=$(hproject_root) || return 1
  local id
  id=$(cat "$proj/.harness/CURRENT" 2>/dev/null || true)
  [ -n "$id" ] && [ -d "$proj/.harness/runs/$id" ] && { printf '%s\n' "$proj/.harness/runs/$id"; return 0; }
  echo "ERROR: no active run (missing/stale .harness/CURRENT) — start one with /harness:run" >&2
  return 1
}
stop_requested() { [ -f "$(hstop_file)" ]; }

hlog() { # hlog <msg...> — timestamped, to stderr and the run log when a run is active
  local line run
  line="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"
  printf '%s\n' "$line" >&2
  if run=$(hcurrent_run 2>/dev/null); then printf '%s\n' "$line" >> "$run/logs/harness.log"; fi
}

# ------------------------------------------------------------------ path guards
# The "claude opened at PC root" class of bug dies here (DESIGN.md L2/L3).
assert_abs() { # assert_abs <path> <what>
  case "${1:?}" in /*) return 0 ;; *) echo "ERROR: ${2:-path} must be absolute: $1" >&2; return 65 ;; esac
}
assert_safe_cwd() { # assert_safe_cwd <dir> — absolute, exists, not $HOME, not /, inside project
  local d="${1:?cwd required}" proj
  assert_abs "$d" "cwd" || return 65
  [ -d "$d" ] || { echo "ERROR: cwd does not exist: $d" >&2; return 65; }
  # resolve symlinks/.. so "$HOME/x/.." can't sneak through
  d=$(cd "$d" && pwd -P) || return 65
  [ "$d" = "/" ] && { echo "ERROR: refusing cwd /" >&2; return 65; }
  [ "$d" = "$HOME" ] && { echo "ERROR: refusing cwd \$HOME" >&2; return 65; }
  proj=$(hproject_root) || return 65
  proj=$(cd "$proj" && pwd -P)
  case "$d/" in
    "$proj"/*) return 0 ;;
    *) # worktrees may live next to the project dir (sibling convention) — allow siblings of project
       case "$d/" in "$(dirname "$proj")"/*) return 0 ;; esac
       echo "ERROR: cwd $d is outside the project ($proj) and its parent" >&2; return 65 ;;
  esac
}

# -------------------------------------------------------------------- utilities
atomic_write() { # atomic_write <file>  (content on stdin)
  local f="${1:?file required}" tmp
  tmp=$(mktemp "$(dirname "$f")/.tmp.XXXXXX") || return 1
  cat > "$tmp" && mv "$tmp" "$f"
}

iso_to_epoch() { # iso_to_epoch <iso8601-with-offset> — handles microseconds; empty on failure
  python3 - "$1" <<'PY' 2>/dev/null || true
import sys, datetime
print(int(datetime.datetime.fromisoformat(sys.argv[1]).timestamp()))
PY
}

now_epoch() { date +%s; }
run_id_new() { date -u '+%Y%m%d-%H%M%S'; }
