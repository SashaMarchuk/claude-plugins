#!/usr/bin/env bash
# hlib.sh — shared helpers for the harness engine. Source this; do not execute.
# Everything here is deterministic: config lookups, path guards, run-state paths, logging.

set -uo pipefail

HARNESS_USER_DIR="${HARNESS_USER_DIR:-$HOME/.claude/harness}"
HARNESS_USER_CONFIG="$HARNESS_USER_DIR/config.json"

# ---------------------------------------------------------------- project root
# Resolution order: $HARNESS_PROJECT (exported by every generated launcher) → walk up from
# $PWD to a .harness/config.json → walk up to a .harness-project pointer file (dropped into
# each worktree at spawn). Sibling worktrees have no .harness/, so the env var / pointer are
# how workers reach the engine (DESIGN.md L-worktree).
hproject_root() {
  if [ -n "${HARNESS_PROJECT:-}" ]; then
    [ -f "$HARNESS_PROJECT/.harness/config.json" ] && { printf '%s\n' "$HARNESS_PROJECT"; return 0; }
    echo "ERROR: HARNESS_PROJECT=$HARNESS_PROJECT has no .harness/config.json" >&2; return 1
  fi
  local d="$PWD"
  while [ "$d" != "/" ]; do
    [ -f "$d/.harness/config.json" ] && { printf '%s\n' "$d"; return 0; }
    if [ -f "$d/.harness-project" ]; then
      local p; p=$(cat "$d/.harness-project" 2>/dev/null)
      [ -n "$p" ] && [ -f "$p/.harness/config.json" ] && { printf '%s\n' "$p"; return 0; }
    fi
    d=$(dirname "$d")
  done
  echo "ERROR: cannot locate the harness project from $PWD." >&2
  echo "  If you are in a worktree, export HARNESS_PROJECT=<project-root> (the launcher sets this automatically)." >&2
  echo "  If this is a new project, run /harness:init first." >&2
  return 1
}

# ------------------------------------------------------------------ config: cfg
# cfg <jq-path> <default>  → project value, else user value, else default.
# jq-path example: '.limits.pause_next_spawn_at'
# A present-but-false / present-but-0 value is honored (NOT overridden by the default) — the
# only thing that falls through to the next layer is a MISSING key or an explicit JSON null.
_cfg_read() { # _cfg_read <file> <path> — echoes the scalar; returns 1 if absent/null
  # Deliberately NOT `jq -e`: -e sets exit status from truthiness, which would treat a valid
  # `false`/`0`/`null` value as failure. We read raw and only reject the literal null.
  local file="$1" path="$2" v
  v=$(jq -r "$path" "$file" 2>/dev/null) || return 1
  [ "$v" = "null" ] && return 1
  printf '%s\n' "$v"
}
cfg() {
  local path="${1:?jq path required}" def="${2-}"
  local proj v
  if proj=$(hproject_root 2>/dev/null); then
    v=$(_cfg_read "$proj/.harness/config.json" "$path") && { printf '%s\n' "$v"; return 0; }
  fi
  if [ -f "$HARNESS_USER_CONFIG" ]; then
    v=$(_cfg_read "$HARNESS_USER_CONFIG" "$path") && { printf '%s\n' "$v"; return 0; }
  fi
  printf '%s\n' "$def"
}
# cfg_int <jq-path> <int-default> — like cfg, but the value must be a plain non-negative integer
# (digits only); anything else (units like "20m", empty, floats, negatives, garbage) logs a LOUD
# warning and returns the default. Normalized base-10 so a leading-zero value ("08") can never trip
# a fatal octal error in a later $(( )). EVERY numeric knob feeding arithmetic or sleep reads through
# this, so a bad config value can never abort a watch tick or busy-spin the loop (0.6.0 numeric fix).
cfg_int() {
  local path="${1:?jq path required}" def="${2:?integer default required}" v
  v=$(cfg "$path" "$def")
  case "$v" in
    ''|*[!0-9]*) hlog "WARN: config $path='$v' is not a non-negative integer — using default $def"; printf '%s\n' "$def" ;;
    *) printf '%s\n' "$((10#$v))" ;;
  esac
}

# ------------------------------------------------------------------- run state
# Run layout: <project>/.harness/runs/<run-id>/{launchers,prompts,state,logs,heartbeats,markers}
# <project>/.harness/CURRENT holds the active run id. STOP file: <project>/.harness/STOP
hruns_dir()   { printf '%s/.harness/runs\n' "$(hproject_root)"; }
hstop_file()  { printf '%s/.harness/STOP\n' "$(hproject_root)"; }
hcurrent_run() {
  # Self-heal (0.6.0): a torn write (crash between truncate and write) can leave CURRENT empty while
  # the run is alive. ONE rule, applied everywhere (incl. do_start): "empty/stale CURRENT + exactly
  # ONE non-STOPPED run dir ⇒ that run IS current" — repair the pointer and return it; >1 candidates
  # ⇒ fail LOUDLY (rc 2, never guess); 0 ⇒ genuinely no active run (rc 1). NEVER call hlog here
  # (hlog calls hcurrent_run — that would recurse); plain stderr only.
  local proj id d cand="" n=0
  proj=$(hproject_root) || return 1
  id=$(cat "$proj/.harness/CURRENT" 2>/dev/null | tr -d '[:space:]')
  [ -n "$id" ] && [ -d "$proj/.harness/runs/$id" ] && { printf '%s\n' "$proj/.harness/runs/$id"; return 0; }
  for d in "$proj"/.harness/runs/*/; do
    [ -d "$d" ] || continue
    [ -f "${d}STOPPED" ] && continue
    cand="${d%/}"; n=$((n+1))
  done
  if [ "$n" -eq 1 ]; then
    printf '%s\n' "$(basename "$cand")" | atomic_write "$proj/.harness/CURRENT"
    echo "WARN: .harness/CURRENT was empty/stale — self-healed to run $(basename "$cand")" >&2
    printf '%s\n' "$cand"; return 0
  fi
  if [ "$n" -gt 1 ]; then
    echo "ERROR: .harness/CURRENT is empty/stale and $n non-STOPPED runs exist under .harness/runs/ — set it to the correct id manually" >&2
    return 2
  fi
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
# _is_project_worktree <dir> <proj-abs> — 0 iff <dir> is a GENUINE linked git worktree whose main
# repo lives inside <proj>. Hardened against --separate-git-dir spoofing (review F8): a real linked
# worktree has git-dir UNDER <common>/worktrees/ and git-dir != git-common-dir.
_is_project_worktree() {
  local d="$1" proj="$2" common gitdir main
  common=$(git -C "$d" rev-parse --git-common-dir 2>/dev/null) || return 1
  gitdir=$(git -C "$d" rev-parse --git-dir 2>/dev/null) || return 1
  case "$common" in /*) ;; *) common=$(cd "$d" && cd "$common" && pwd -P) ;; esac
  case "$gitdir" in /*) ;; *) gitdir=$(cd "$d" && cd "$gitdir" && pwd -P) ;; esac
  [ "$gitdir" != "$common" ] || return 1                            # linked worktree, not the main checkout
  case "$gitdir/" in "$common"/worktrees/*) ;; *) return 1 ;; esac  # genuine worktree, not a spoofed git-dir
  main=$(cd "$common/.." 2>/dev/null && pwd -P) || return 1
  case "$main/" in "$proj"/*) return 0 ;; esac
  return 1
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
  esac
  # Outside the project tree: allow ONLY a real git worktree whose main repo lives inside the
  # project (the sibling-worktree convention) — not every unrelated project under the parent dir.
  _is_project_worktree "$d" "$proj" && return 0
  echo "ERROR: cwd $d is neither inside the project ($proj) nor a git worktree of a repo in it" >&2
  return 65
}

# -------------------------------------------------------------------- utilities
atomic_write() { # atomic_write <file>  (content on stdin)
  local f="${1:?file required}" tmp
  tmp=$(mktemp "$(dirname "$f")/.tmp.XXXXXX") || return 1
  cat > "$tmp" && mv "$tmp" "$f"
}

iso_to_epoch() { # iso_to_epoch <iso8601-with-offset> — handles microseconds; empty on failure.
  # Prefer python3, but fall back to date(1) so a Mac without python3 still parses reset times
  # (review LOW — undeclared python3 dep). The usage API returns UTC (+00:00), so treat as UTC.
  local iso="$1" e base
  if command -v python3 >/dev/null 2>&1; then
    e=$(python3 - "$iso" <<'PY' 2>/dev/null
import sys, datetime
print(int(datetime.datetime.fromisoformat(sys.argv[1]).timestamp()))
PY
)
    [ -n "$e" ] && { printf '%s\n' "$e"; return 0; }
  fi
  # strip fractional seconds and the timezone offset, then parse as UTC seconds
  base=$(printf '%s' "$iso" | sed -E 's/\.[0-9]+//; s/(Z|[+-][0-9]{2}:?[0-9]{2})$//')
  e=$(date -u -d "$base" +%s 2>/dev/null) && { printf '%s\n' "$e"; return 0; }         # GNU date
  e=$(date -u -j -f '%Y-%m-%dT%H:%M:%S' "$base" +%s 2>/dev/null) && { printf '%s\n' "$e"; return 0; }  # BSD date
  return 1
}

now_epoch() { date +%s; }
run_id_new() { date -u '+%Y%m%d-%H%M%S'; }

# hsanitize_path <PATH> — keep only ABSOLUTE components, in order; drop empty / "." / relative
# entries (each is a `.`-style injection vector once baked into a session launcher). Globbing is
# disabled around the split so a component like "/opt/*/bin" is never expanded against the fs.
hsanitize_path() {
  local out="" c IFS=: reglob=0
  case $- in *f*) ;; *) set -f; reglob=1 ;; esac
  for c in ${1-}; do case "$c" in /*) out="${out:+$out:}$c" ;; esac; done
  [ "$reglob" -eq 1 ] && set +f
  printf '%s\n' "$out"
}

# git_recent <dir> <max_age_s> [head|any] — rc 0 iff the tree shows git activity newer than max_age:
# a recent commit (scope head = this checkout's HEAD; any = newest commit on any local branch, for the
# orchestrator at the project root whose lanes commit on sibling branches) OR a recent index mtime.
# The ground-truth cross-check the stall nudge consults before alarming (DESIGN L18). BSD/GNU stat.
git_recent() {
  local d="${1:?dir}" max="${2:?max age}" scope="${3:-head}" now t gitdir idx
  now=$(date +%s)
  if [ "$scope" = "any" ]; then
    t=$(git -C "$d" for-each-ref --sort=-committerdate --format='%(committerdate:unix)' --count=1 refs/heads 2>/dev/null | head -1)
  else
    t=$(git -C "$d" log -1 --format=%ct 2>/dev/null)
  fi
  [ -n "$t" ] && [ "$((now - t))" -le "$max" ] && return 0
  gitdir=$(git -C "$d" rev-parse --git-dir 2>/dev/null) || return 1
  case "$gitdir" in /*) ;; *) gitdir="$d/$gitdir" ;; esac
  idx=$(stat -f %m "$gitdir/index" 2>/dev/null || stat -c %Y "$gitdir/index" 2>/dev/null) || return 1
  [ "$((now - idx))" -le "$max" ]
}
