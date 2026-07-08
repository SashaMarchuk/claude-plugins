#!/usr/bin/env bash
# tickets.sh — the ticket queue. Two sources, one verb set (DESIGN.md §7):
#   github: labeled issues  harness:ready → harness:in-progress → harness:done|blocked|needs-review
#   local:  .harness/tickets/<n>-<slug>.md with a `status:` frontmatter line, same state machine
# Usage:
#   tickets.sh bootstrap                    # idempotent: labels (github) / dir (local)
#   tickets.sh list [status]                # deterministic FIFO (issue number / file number)
#   tickets.sh show <id>                    # full body
#   tickets.sh add <title> <body-file> [ready|blocked]
#   tickets.sh claim <id>                   # ready → in-progress (+assignee on github)
#   tickets.sh comment <id> <body-file>     # in-place status comment (github) / append log (local)
#   tickets.sh done <id> | block <id> <why-file> | review <id>
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hlib.sh"

SOURCE=$(cfg '.tickets.source' 'local')
REPO=$(cfg '.tickets.repo' '')
PREFIX=$(cfg '.tickets.label_prefix' 'harness')
TDIR="$(hproject_root)/.harness/tickets"

[ "$SOURCE" = "github" ] && [ -z "$REPO" ] && { echo "ERROR: tickets.source=github but tickets.repo is empty" >&2; exit 78; }

# --------------------------------------------------------------------- github
gh_labels_bootstrap() {
  local l c d
  while read -r l c d; do
    gh label create "$PREFIX:$l" --repo "$REPO" --color "$c" --description "$d" --force >/dev/null
  done <<'EOF'
ready 0E8A16 Claimable by the harness
in-progress FBCA04 Claimed by a harness run
blocked D93F0B Needs human input before the harness may proceed
needs-review 5319E7 Finished with low confidence - review before trusting
done C2E0C6 Completed by the harness
EOF
  echo "OK labels ensured on $REPO"
}
gh_list() {
  local status="${1:-ready}"
  gh issue list --repo "$REPO" --label "$PREFIX:$status" --state open --limit 200 \
    --json number,title,labels --jq 'sort_by(.number) | .[] | "\(.number)\t\(.title)"'
}
gh_show() { gh issue view "${1:?id}" --repo "$REPO" --json number,title,body,labels,comments \
              --jq '{number,title,labels:[.labels[].name],body,comments:[.comments[]|{author:.author.login,body}]}'; }
gh_add() {
  local title="${1:?}" bodyf="${2:?}" state="${3:-ready}"
  gh issue create --repo "$REPO" --title "$title" --body-file "$bodyf" --label "$PREFIX:$state"
}
gh_claim() {
  local id="${1:?}"
  # read-verify-then-write; no CAS exists in gh — acceptable for single-operator queues
  gh issue view "$id" --repo "$REPO" --json labels --jq '[.labels[].name]' | grep -q "\"$PREFIX:ready\"" \
    || { echo "ERROR: #$id is not $PREFIX:ready" >&2; return 65; }
  gh issue edit "$id" --repo "$REPO" --remove-label "$PREFIX:ready" --add-label "$PREFIX:in-progress" --add-assignee "@me" >/dev/null
  echo "OK claimed #$id"
}
gh_comment() { gh issue comment "${1:?id}" --repo "$REPO" --body-file "${2:?body}" --edit-last --create-if-none >/dev/null; echo "OK commented #$1"; }
gh_done()   { gh issue edit "${1:?id}" --repo "$REPO" --remove-label "$PREFIX:in-progress" --add-label "$PREFIX:done" >/dev/null
              gh issue close "$1" --repo "$REPO" --comment "Completed by harness run $(basename "$(hcurrent_run 2>/dev/null || echo '?')")" >/dev/null; echo "OK done #$1"; }
gh_review() { gh issue edit "${1:?id}" --repo "$REPO" --remove-label "$PREFIX:in-progress" --add-label "$PREFIX:needs-review" >/dev/null; echo "OK needs-review #$1"; }
gh_block()  { gh issue edit "${1:?id}" --repo "$REPO" --remove-label "$PREFIX:in-progress" --remove-label "$PREFIX:ready" --add-label "$PREFIX:blocked" >/dev/null 2>&1 || true
              gh issue comment "${1:?}" --repo "$REPO" --body-file "${2:?why-file}" >/dev/null; echo "OK blocked #$1"; }

# ---------------------------------------------------------------------- local
l_bootstrap() { mkdir -p "$TDIR"; echo "OK $TDIR"; }
l_file() { # id → path
  local f; f=$(find "$TDIR" -maxdepth 1 -name "${1:?id}-*.md" | head -1)
  [ -n "$f" ] || { echo "ERROR: no local ticket $1" >&2; return 66; }
  printf '%s\n' "$f"
}
l_status_get() { sed -n 's/^status: *//p' "$(l_file "$1")" | head -1; }
l_status_set() {
  local f; f=$(l_file "$1")
  awk -v s="$2" 'BEGIN{done=0} /^status: /{ if(!done){print "status: " s; done=1; next} } {print}' "$f" | atomic_write "$f"
}
l_list() {
  local status="${1:-ready}" f
  for f in "$TDIR"/[0-9]*-*.md; do
    [ -f "$f" ] || continue
    if [ "$(sed -n 's/^status: *//p' "$f" | head -1)" = "$status" ]; then
      printf '%s\t%s\n' "$(basename "$f" | cut -d- -f1)" "$(sed -n 's/^title: *//p' "$f" | head -1)"
    fi
  done | sort -n
}
l_add() {
  local title="${1:?}" bodyf="${2:?}" state="${3:-ready}" n slug
  mkdir -p "$TDIR"
  n=$(( $(find "$TDIR" -maxdepth 1 -name '[0-9]*-*.md' | sed 's|.*/||; s|-.*||' | sort -n | tail -1 | sed 's/^$/0/') + 1 ))
  slug=$(printf '%s' "$title" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//' | cut -c1-40)
  { printf 'title: %s\nstatus: %s\ncreated: %s\n\n' "$title" "$state" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"; cat "$bodyf"; } > "$TDIR/$n-$slug.md"
  echo "OK created ticket $n ($TDIR/$n-$slug.md)"
}
l_comment() { { printf '\n---\n%s harness log:\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"; cat "${2:?body}"; } >> "$(l_file "${1:?id}")"; echo "OK logged on $1"; }
l_claim()  { [ "$(l_status_get "$1")" = "ready" ] || { echo "ERROR: ticket $1 is not ready" >&2; return 65; }; l_status_set "$1" in-progress; echo "OK claimed $1"; }

case "${1:?usage: tickets.sh bootstrap|list|show|add|claim|comment|done|block|review}" in
  bootstrap) [ "$SOURCE" = github ] && gh_labels_bootstrap || l_bootstrap ;;
  list)    shift; [ "$SOURCE" = github ] && gh_list "$@" || l_list "$@" ;;
  show)    shift; [ "$SOURCE" = github ] && gh_show "$@" || cat "$(l_file "${1:?id}")" ;;
  add)     shift; [ "$SOURCE" = github ] && gh_add "$@" || l_add "$@" ;;
  claim)   shift; [ "$SOURCE" = github ] && gh_claim "$@" || l_claim "$@" ;;
  comment) shift; [ "$SOURCE" = github ] && gh_comment "$@" || l_comment "$@" ;;
  done)    shift; [ "$SOURCE" = github ] && gh_done "$@" || { l_status_set "${1:?}" "done"; echo "OK done $1"; } ;;
  block)   shift; [ "$SOURCE" = github ] && gh_block "$@" || { l_status_set "${1:?}" blocked; l_comment "$1" "${2:?why-file}"; } ;;
  review)  shift; [ "$SOURCE" = github ] && gh_review "$@" || { l_status_set "${1:?}" needs-review; echo "OK needs-review $1"; } ;;
  *) echo "usage: tickets.sh bootstrap|list|show|add|claim|comment|done|block|review" >&2; exit 64 ;;
esac
