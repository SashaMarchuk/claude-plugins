#!/usr/bin/env bash
# model.sh — resolve a model OR-chain ("fable|mythos|opus") into concrete candidates.
# Usage:
#   model.sh resolve <chain>      → one candidate per line, in order (validated aliases)
#   model.sh primary <chain>      → first candidate only
#   model.sh rest    <chain>      → comma-separated remainder (for --fallback-model, print mode)
# '|' means OR: try left first; the launcher falls through on boot failure (DESIGN.md §4).
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hlib.sh"

# Known aliases pass through as-is (the CLI accepts aliases and full IDs).
# haiku is rejected by policy. Unknown values are allowed if they look like full model IDs.
validate_candidate() {
  local m="$1"
  case "$m" in
    haiku|claude-haiku*|*haiku*) echo "ERROR: haiku is disallowed by harness policy" >&2; return 64 ;;
    fable|mythos|opus|sonnet) return 0 ;;
    claude-*) return 0 ;;
    *) echo "ERROR: unknown model '$m' (use an alias: fable|mythos|opus|sonnet, or a full claude-* id)" >&2; return 64 ;;
  esac
}

split_chain() { # one candidate per line, whitespace-trimmed, empties dropped
  printf '%s\n' "${1:?chain required}" | tr '|' '\n' | sed 's/^ *//; s/ *$//' | grep -v '^$'
}

cmd="${1:?usage: model.sh resolve|primary|rest <chain>}"; chain="${2:?chain required}"
candidates=()
while IFS= read -r _m; do candidates+=("$_m"); done < <(split_chain "$chain")
[ "${#candidates[@]}" -gt 0 ] || { echo "ERROR: empty model chain" >&2; exit 64; }
for m in "${candidates[@]}"; do validate_candidate "$m" || exit 64; done

case "$cmd" in
  resolve) printf '%s\n' "${candidates[@]}" ;;
  primary) printf '%s\n' "${candidates[0]}" ;;
  rest)
    if [ "${#candidates[@]}" -gt 1 ]; then
      printf '%s\n' "${candidates[@]:1}" | paste -sd, -
    fi ;;
  *) echo "usage: model.sh resolve|primary|rest <chain>" >&2; exit 64 ;;
esac
