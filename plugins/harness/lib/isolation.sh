# shellcheck shell=bash
# Isolation self-test (design "Rebuild", separate state).
# The new engine must never see the 0.6.0 engine's variables or scripts.
# This is the only file allowed to name them, and only as data.

# Variables the 0.6.0 engine (bin/*.sh on main) exports or reads.
HO_OLD_VARS="HARNESS_PROJECT HARNESS_USER_DIR HARNESS_USER_CONFIG HARNESS_ROLE"

# Script names of the 0.6.0 engine.
HO_OLD_SCRIPTS="harness-run.sh harness-tickets.sh harness-spawn.sh harness-term.sh harness-limits.sh harness-state.sh harness-model.sh harness-trust.sh harness-guide.sh harness-gsd.sh harness-validate.sh hlib.sh"

# Print one "ISOLATION FAIL:" line per problem. Exit 65 on any problem,
# else print "ISOLATION OK" and return 0.
ho_isolation_check() {
  local problems=0 var dir script rest seen=""
  # Every HARNESS_* variable counts: the 0.6.0 engine owns that prefix (the named list is the known set).
  for var in $HO_OLD_VARS $(env | sed -n 's/^\(HARNESS_[A-Za-z0-9_]*\)=.*/\1/p' | sort -u); do
    case " $seen " in *" $var "*) continue ;; esac
    seen="$seen $var"
    if printenv "$var" >/dev/null 2>&1; then
      printf 'ISOLATION FAIL: old variable %s is set\n' "$var"
      problems=$((problems + 1))
    fi
  done
  # Split PATH by hand: a trailing ":" is an empty component too, and
  # command substitution would drop it. An empty component means the current folder.
  rest="${PATH:-}:"
  while [ -n "$rest" ]; do
    dir=${rest%%:*}
    rest=${rest#*:}
    [ -n "$dir" ] || dir=.
    for script in $HO_OLD_SCRIPTS; do
      if [ -f "$dir/$script" ]; then
        printf 'ISOLATION FAIL: old script %s on PATH in %s\n' "$script" "$dir"
        problems=$((problems + 1))
      fi
    done
  done
  if [ "$problems" -gt 0 ]; then
    exit 65
  fi
  echo "ISOLATION OK"
}

# ---- PATH trust boundary (D37-FLOW-8; PR #90, Codex security review) --------------------
# No helper (tmux, git, gh, jq, uuidgen, osascript, the runtime) may be run from a folder
# inside the project, its worktrees folder or a git worktree of it: anyone who can commit
# could place a binary there. Every PATH entry inside one of those folders is dropped.
# Pass 1 uses bash builtins only, so no helper runs before the project folder is off PATH.

# ho_path_inside <dir> <root>: 0 when <dir> is <root> or below it, compared by identity.
ho_path_inside() {
  local a=$1
  [ -d "$a" ] || return 1
  while :; do
    [ "$a" -ef "$2" ] && return 0
    case $a in */*) ;; *) return 1 ;; esac
    [ "$a" = / ] && return 1
    a=${a%/*}
    [ -n "$a" ] || a=/
  done
}

# ho_path_drop_inside <root>...: rewrite PATH without the entries inside any root.
ho_path_drop_inside() {
  local rest="${PATH:-}:" dir out="" r keep
  while [ -n "$rest" ]; do
    dir=${rest%%:*}
    rest=${rest#*:}
    [ -n "$dir" ] || dir=.
    keep=1
    for r in "$@"; do
      [ -n "$r" ] || continue
      if ho_path_inside "$dir" "$r"; then keep=""; break; fi
    done
    [ -n "$keep" ] && out="${out:+$out:}$dir"
  done
  PATH=$out
  export PATH
}

# ho_path_project_guess: the project folder from HO_PROJECT_DIR or by walking up from PWD
# to .harness/config.json or a .harness-project pointer. Builtins only.
ho_path_project_guess() {
  local d=$PWD p
  if [ -n "${HO_PROJECT_DIR:-}" ]; then printf '%s\n' "$HO_PROJECT_DIR"; return 0; fi
  while :; do
    [ -f "$d/.harness/config.json" ] && { printf '%s\n' "$d"; return 0; }
    if [ -f "$d/.harness-project" ]; then
      IFS= read -r p < "$d/.harness-project" || true
      [ -n "${p:-}" ] && [ -f "$p/.harness/config.json" ] && { printf '%s\n' "$d"; printf '%s\n' "$p"; return 0; }
    fi
    [ "$d" = / ] || [ -z "$d" ] && return 1
    d=${d%/*}
    [ -n "$d" ] || d=/
  done
}

# ho_path_scrub: pass 1 drops the project folders found with builtins; pass 2 drops the
# configured worktrees folder and the git worktrees, found with the helpers now trusted.
ho_path_scrub() {
  local roots r
  roots=$(ho_path_project_guess) || return 0
  local -a list=()
  while IFS= read -r r; do [ -n "$r" ] && list+=("$r"); done <<EOF_GUESS
$roots
EOF_GUESS
  [ "${#list[@]}" -gt 0 ] || return 0
  ho_path_drop_inside "${list[@]}"
  local pd="" more
  for r in "${list[@]}"; do [ -f "$r/.harness/config.json" ] && pd=$r; done
  [ -n "$pd" ] || return 0
  more=$(HO_PROJECT_DIR=$pd ho_session_project_roots 2>/dev/null) || return 0
  while IFS= read -r r; do [ -n "$r" ] && list+=("$r"); done <<EOF_MORE
$more
EOF_MORE
  ho_path_drop_inside "${list[@]}"
}
