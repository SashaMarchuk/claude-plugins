# shellcheck shell=bash
# Safe-file and path helpers (design "Rebuild" reuse list), ported from 0.6.0.
# Return codes: 0 ok, 65 refused path, 1 write failure.

# ho_atomic_write <file>: content on stdin. The file gets all of it or none of it.
ho_atomic_write() {
  local f=${1:?file required} tmp
  tmp=$(mktemp "$(dirname "$f")/.tmp.XXXXXX" 2>/dev/null) || {
    printf 'harness: cannot write %s\n' "$f" >&2
    return 1
  }
  if cat > "$tmp" && mv "$tmp" "$f"; then
    return 0
  fi
  rm -f "$tmp"
  printf 'harness: cannot write %s\n' "$f" >&2
  return 1
}

# ho_assert_abs <path> <what>
ho_assert_abs() {
  case ${1-} in
    /*) return 0 ;;
    *) printf 'harness: %s must be an absolute path: %s\n' "${2:-path}" "${1-}" >&2; return 65 ;;
  esac
}

# ho_is_project_worktree <dir> <project>: 0 if <dir> is a genuine linked git worktree whose
# main repository lives inside <project>. A separate git dir that only points into the
# project does not count: a real linked worktree has its git dir under <common>/worktrees/.
ho_is_project_worktree() {
  local d=$1 proj=$2 common gitdir main
  common=$(git -C "$d" rev-parse --git-common-dir 2>/dev/null) || return 1
  gitdir=$(git -C "$d" rev-parse --git-dir 2>/dev/null) || return 1
  case $common in /*) ;; *) common=$(cd "$d" && cd "$common" && pwd -P) || return 1 ;; esac
  case $gitdir in /*) ;; *) gitdir=$(cd "$d" && cd "$gitdir" && pwd -P) || return 1 ;; esac
  common=$(cd "$common" && pwd -P) || return 1
  gitdir=$(cd "$gitdir" && pwd -P) || return 1
  [ "$gitdir" != "$common" ] || return 1
  case "$gitdir/" in "$common"/worktrees/*) ;; *) return 1 ;; esac
  main=$(cd "$common/.." 2>/dev/null && pwd -P) || return 1
  case "$main/" in "$proj"/*) return 0 ;; esac
  return 1
}

# ho_assert_safe_cwd <dir> <project>: absolute, exists, not / or HOME, and inside the
# project or a genuine worktree of a repository inside it. Symlinks and ".." are resolved first.
ho_assert_safe_cwd() {
  local d=${1-} proj=${2-} home
  ho_assert_abs "$d" "working folder" || return 65
  ho_assert_abs "$proj" "project folder" || return 65
  [ -d "$d" ] || { printf 'harness: working folder does not exist: %s\n' "$d" >&2; return 65; }
  d=$(cd "$d" && pwd -P) || return 65
  proj=$(cd "$proj" 2>/dev/null && pwd -P) || { printf 'harness: project folder does not exist: %s\n' "$2" >&2; return 65; }
  home=$(cd "$HOME" 2>/dev/null && pwd -P) || home=$HOME
  if [ "$d" = / ] || [ "$d" = "$home" ]; then
    printf 'harness: refusing working folder %s\n' "$d" >&2
    return 65
  fi
  case "$d/" in "$proj"/*) return 0 ;; esac
  ho_is_project_worktree "$d" "$proj" && return 0
  printf 'harness: working folder %s is neither inside the project %s nor a worktree of it\n' "$d" "$proj" >&2
  return 65
}

# ho_sanitize_path <PATH>: keep only absolute components, in order. Empty, "." and relative
# components are dropped: each one would run programs from the current folder. No globbing.
ho_sanitize_path() {
  local out="" c IFS=: reglob=0
  case $- in *f*) ;; *) set -f; reglob=1 ;; esac
  for c in ${1-}; do
    case $c in /*) out="${out:+$out:}$c" ;; esac
  done
  [ "$reglob" -eq 1 ] && set +f
  printf '%s\n' "$out"
}
