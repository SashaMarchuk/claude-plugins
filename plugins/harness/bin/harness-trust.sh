#!/usr/bin/env bash
# harness-trust.sh — handle Claude Code's "Do you trust the files in this folder?" startup dialog.
# Two layers (DESIGN.md §trust):
#   pretrust <abs-dir>   deterministic belt: mark the dir trusted in ~/.claude.json BEFORE spawn,
#                        but ONLY if the dir is inside a configured project/worktree.
#   inside <abs-dir>     exit 0 iff the dir is inside this project (the factual basis a Sonnet
#                        gate confirms before the watch loop answers a dialog).
# We never blindly trust: a dir outside the project is refused (pretrust) / reported (watch).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hlib.sh"

CLAUDE_JSON="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/../.claude.json"
[ -f "$HOME/.claude.json" ] && CLAUDE_JSON="$HOME/.claude.json"

inside_project() { # exit 0 iff <dir> is inside the project or one of its git worktrees
  local d="${1:?dir}" proj resolved common main
  assert_abs "$d" "dir" >/dev/null 2>&1 || return 1
  [ -d "$d" ] || return 1
  resolved=$(cd "$d" && pwd -P) || return 1
  proj=$(hproject_root 2>/dev/null) || return 1
  proj=$(cd "$proj" && pwd -P)
  case "$resolved/" in "$proj"/*) return 0 ;; esac
  if common=$(git -C "$resolved" rev-parse --git-common-dir 2>/dev/null); then
    case "$common" in /*) ;; *) common=$(cd "$resolved" && cd "$common" && pwd -P) ;; esac
    main=$(cd "$common/.." 2>/dev/null && pwd -P || true)
    case "$main/" in "$proj"/*) return 0 ;; esac
  fi
  return 1
}

pretrust() {
  local d="${1:?abs dir required}" resolved tmp
  if ! inside_project "$d"; then
    echo "REFUSED: $d is not inside the project — not pre-trusting" >&2; return 65
  fi
  resolved=$(cd "$d" && pwd -P)
  [ -f "$CLAUDE_JSON" ] || { echo "WARN: $CLAUDE_JSON not found — skipping pretrust (dialog will be handled by the watch monitor)" >&2; return 0; }
  # merge-only: set projects[dir].hasTrustDialogAccepted=true, preserve every other key (L-config-merge)
  tmp=$(mktemp "$(dirname "$CLAUDE_JSON")/.claude.json.XXXXXX") || return 1
  if jq --arg p "$resolved" '.projects[$p] = ((.projects[$p] // {}) + {hasTrustDialogAccepted:true, hasCompletedProjectOnboarding:true})' \
       "$CLAUDE_JSON" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$CLAUDE_JSON"
    hlog "pretrust: marked $resolved trusted"
  else
    rm -f "$tmp"; echo "WARN: pretrust merge failed — leaving ~/.claude.json untouched" >&2; return 1
  fi
}

case "${1:?usage: harness-trust.sh pretrust|inside <dir>}" in
  pretrust) shift; pretrust "$@" ;;
  inside)   shift; inside_project "$@" ;;
  *) echo "usage: harness-trust.sh pretrust|inside <dir>" >&2; exit 64 ;;
esac
