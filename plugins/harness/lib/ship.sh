# shellcheck shell=bash
# Push, draft PR, merge confirmation by git, close on merge, stage release (tasks.md 14.2;
# H-043 to H-046, H-050, H-051; design D10, D11, S8-07). `harness ship <run-dir> <verb>`.
#
#   push <lane> --ticket N --title T   push the lane's finalize commit to the ticket branch
#                                      <prefix><N>-<short title> (git.branch_prefix, default
#                                      "harness/") on git.remote (default origin), only when the
#                                      autonomy profile allows a push; git must then show the
#                                      remote branch at that commit
#   pr <lane>                          open the PR, always as a draft (D10), at the profile's
#                                      opening point (pr_open: after-validator, the default, needs
#                                      the validator's plain "passed" verdict for the pushed
#                                      commit; a step id needs that step begun for the ticket).
#                                      The PR always links its ticket; on GitHub it adds
#                                      "Closes #N" (S8-07). Only a profile that may merge marks it
#                                      ready. The base is stage.branch when stage.allow is true
#                                      (H-050), else git.target (default main).
#   merge <lane> --facts F             the remote merge (H-050): only under a profile that may merge,
#                                      with every mechanical condition (autonomy check merge), the
#                                      validator's pass and the tests for the pushed commit; gh
#                                      merges the PR, then `merged` confirms it by git
#   merged <lane>                      confirm the merge through git (H-046): the remote base
#                                      holds the pushed commit, or the PR's merge commit is on
#                                      the base and carries the same change (a squash merge).
#                                      A hard stop refuses it; a soft stop lets it finish.
#                                      Unconfirmed: the ticket is not touched, exit 70. Confirmed:
#                                      the post-merge smoke test runs at once when one is set
#                                      (smoke.use, command in smoke.list.<label>.command of the
#                                      user config); the ticket is set to done only after it
#                                      passes (H-045), and closed unless close_on_merge is false
#                                      (D11). A failed smoke test runs smoke.on_fail (H-051):
#                                      "fix" (default) or "revert".
#   status                             one JSON line per shipped lane
#
#   <run>/ship/<lane>.json   {lane, ticket, title, branch, remote, sha, worktree, pr, url, base}
#
# Exit codes: 64 usage, 65 refused (missing record, bad name, no pass or tests), 70 not confirmed by
# git, 72 the smoke test failed, 75 a stop refuses it, 76 waits for a human (the profile runs no post-merge steps), 77 the
# autonomy profile does not allow it, 78 config error.
# Requires lib/run.sh, lib/config.sh, lib/autonomy.sh, lib/loop.sh, lib/tickets.sh, lib/sessions.sh
# and ho_vf_block from lib/verify.sh.

ho_ship_err() { printf 'harness: ship: %s\n' "$*" >&2; }

ho_ship_usage() {
  cat >&2 <<'USAGE'
usage: harness ship <run-dir> push <lane> --ticket N --title T
       harness ship <run-dir> pr <lane>
       harness ship <run-dir> merge <lane> --facts FILE
       harness ship <run-dir> merged <lane>
       harness ship <run-dir> status
exit: 0 done, 64 usage, 65 refused, 70 not confirmed by git, 72 smoke test failed,
      76 waits for a human, 77 not allowed by the autonomy profile, 78 config error
USAGE
}

# ho_ship_slug <title>: a short branch-safe title (a-z 0-9 -, at most 40 characters).
ho_ship_slug() {
  printf '%s' "$1" | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -c 'a-z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//' | cut -c1-40 | sed 's/-$//'
}

# ho_ship_stop <ticket> [soft]: 0 when no stop refuses this remote step (D25, H-085): like loop
# merge, a stop lets nothing new reach the remote except under a soft:ticket stop that covers the
# ticket; with "soft", a soft stop lets the step finish and only a hard stop refuses it.
ho_ship_stop() {
  local rc=0
  if [ "${2-}" = soft ]; then ho_stop_gate_soft || rc=$?; else ho_stop_gate "$1" || rc=$?; fi
  [ "$rc" -eq 0 ] && return 0
  ho_ledger_append ship-stopped ticket "$1" reason "$([ "$rc" -eq 2 ] && echo "the stop state is unknown" || echo "a stop is in force")"
  ho_ship_err "the run is stopped (or its stop state is unknown); nothing goes to the remote for ticket $1"
  return 75
}

ho_ship_rec() { printf '%s/ship/%s.json\n' "$HO_RUN_DIR" "$1"; }

ho_ship_set() { # <lane> <jq filter> [jq args]
  local f new
  f=$(ho_ship_rec "$1")
  new=$(jq "${@:3}" "$2" "$f") || return 1
  printf '%s\n' "$new" | ho_atomic_write "$f"
}

# ho_ship_au <action> <for>: the autonomy check (one ledger line); its exit code.
ho_ship_au() { local rc=0; ho_au_check "$1" --for "$2" >/dev/null || rc=$?; return "$rc"; }

ho_ship_remote() {
  local r
  r=$(ho_cfg '.git.remote' origin) || return 78
  case $r in '' | -* | *[!A-Za-z0-9._-]*) ho_ship_err "git.remote must be a remote name: $r"; return 78 ;; esac
  printf '%s\n' "$r"
}

# ho_ship_base: the PR's base branch (H-050: the stage branch when a stage release is allowed).
ho_ship_base() {
  local stage b
  stage=$(ho_cfg '.stage.allow' false) || return 78
  if [ "$stage" = true ]; then
    b=$(ho_cfg '.stage.branch' '') || return 78
    [ -n "$b" ] || { ho_ship_err "stage.allow is true but stage.branch is not set"; return 78; }
  else
    b=$(ho_cfg '.git.target' main) || return 78
  fi
  git check-ref-format --branch "$b" >/dev/null 2>&1 || { ho_ship_err "not a branch name: $b"; return 78; }
  printf '%s\n' "$b"
}

# ---- push -------------------------------------------------------------------------------------
ho_ship_push() {
  local lane=${1-} ticket="" title="" lj wt sha prefix branch remote rc got
  shift || true
  while [ $# -gt 0 ]; do
    case $1 in
      --ticket) [ $# -ge 2 ] || { ho_ship_usage; return 64; }; ticket=$(ho_stop_ticket_arg "$2") || return 64; shift 2 ;;
      --title) [ $# -ge 2 ] || { ho_ship_usage; return 64; }; title=$2; shift 2 ;;
      *) ho_ship_usage; return 64 ;;
    esac
  done
  [ -n "$ticket" ] && [ -n "$(ho_ship_slug "$title")" ] || { ho_ship_usage; return 64; }
  ho_loop_lane_ok "$lane" || return 65
  lj="$HO_RUN_DIR/lanes/$lane.json"
  [ -f "$lj" ] || { ho_ship_err "lane $lane is not ready (no finalize commit recorded)"; return 65; }
  wt=$(ho_loop_field "$lj" worktree) && sha=$(ho_loop_field "$lj" sha) || { ho_ship_err "lane record of $lane is unreadable"; return 65; }
  ho_ship_stop "$ticket" || return $?
  rc=0; ho_ship_au push "$ticket" || rc=$?
  if [ "$rc" -ne 0 ]; then
    ho_ship_err "the autonomy profile allows no push; nothing leaves this machine until a human pushes"
    return "$rc"
  fi
  prefix=$(ho_cfg '.git.branch_prefix' 'harness/') || return 78
  branch="$prefix$ticket-$(ho_ship_slug "$title")"
  git check-ref-format --branch "$branch" >/dev/null 2>&1 || { ho_ship_err "not a branch name: $branch (git.branch_prefix)"; return 78; }
  remote=$(ho_ship_remote) || return $?
  if ! git -C "$wt" push -q "$remote" "$sha:refs/heads/$branch" 2>"$HO_RUN_DIR/logs/ship-push.log"; then
    ho_ledger_append ship-push-failed lane "$lane" branch "$branch"
    ho_ship_err "git push of $branch to $remote failed (see $HO_RUN_DIR/logs/ship-push.log)"
    return 70
  fi
  got=$(git -C "$wt" ls-remote "$remote" "refs/heads/$branch" 2>/dev/null | cut -f1)
  if [ "$got" != "$sha" ]; then
    ho_ledger_append ship-push-unconfirmed lane "$lane" branch "$branch" sha "$sha" remote_sha "${got:-none}"
    ho_ship_err "git does not show $branch at $sha on $remote; the push is not confirmed"
    return 70
  fi
  mkdir -p "$HO_RUN_DIR/ship"
  local f old='{}'
  f=$(ho_ship_rec "$lane")
  # A push after a fix keeps the open PR: the same branch moves to the new commit.
  [ ! -f "$f" ] || old=$(jq -c '{pr, url, base}' "$f" 2>/dev/null) || old='{}'
  jq -n --arg lane "$lane" --arg t "$ticket" --arg title "$title" --arg b "$branch" --arg r "$remote" --arg sha "$sha" --arg wt "$wt" --argjson old "$old" \
    '{schemaVersion: 2, lane: $lane, ticket: $t, title: $title, branch: $b, remote: $r, sha: $sha, worktree: $wt, pr: null, url: null, base: null, merged: null} + $old' \
    | ho_atomic_write "$f" || return 1
  ho_ledger_append ship-pushed lane "$lane" ticket "$ticket" branch "$branch" sha "$sha"
  printf 'pushed %s at %s to %s\n' "$branch" "$sha" "$remote"
  local pr
  pr=$(jq -r '.pr // ""' "$f")
  if [ -n "$pr" ]; then
    # The PR body follows the new head: its Verification block is built again (H-053).
    ho_ship_load "$lane" || return $?
    ho_ship_body "$lane" || return $?
    if gh pr edit "$pr" --body-file "$HO_RUN_DIR/ship/$lane.body.md" $(ho_ship_gh_repo) >/dev/null 2>&1; then
      ho_ledger_append ship-pr-body lane "$lane" pr "$pr" sha "$sha"
      printf 'PR #%s now shows the Verification block for %s\n' "$pr" "$sha"
    else
      ho_ship_err "the body of PR #$pr could not be updated; its Verification block is for the old commit"
      return 70
    fi
  fi
}

# ho_ship_load <lane>: set S_TICKET S_TITLE S_BRANCH S_REMOTE S_SHA S_WT S_PR S_BASE.
ho_ship_load() {
  local f
  f=$(ho_ship_rec "$1")
  [ -f "$f" ] && [ ! -L "$f" ] || { ho_ship_err "lane $1 was not pushed by the harness (no ship record)"; return 65; }
  IFS=$'\t' read -r S_TICKET S_TITLE S_BRANCH S_REMOTE S_SHA S_WT S_PR S_BASE < <(jq -r \
    '[.ticket, .title, .branch, .remote, .sha, .worktree, (.pr // "" | tostring), (.base // "")] | @tsv' "$f") \
    || { ho_ship_err "the ship record of $1 is unreadable"; return 65; }
}

ho_ship_gh_repo() { [ -z "${HO_TICKETS_REPO:-}" ] || printf -- '--repo\n%s\n' "$HO_TICKETS_REPO"; }

# ho_ship_body <lane>: write the PR body: the ticket link (S8-07) and the Verification block,
# built from recorded results (H-053). Needs ho_ship_load.
ho_ship_body() {
  local body="$HO_RUN_DIR/ship/$1.body.md"
  {
    if [ "${HO_TICKETS_SOURCE:-local}" = github ]; then
      printf 'Ticket: #%s\n\nCloses #%s\n' "$S_TICKET" "$S_TICKET"
    else
      printf 'Ticket: local ticket %s\n' "$S_TICKET"
    fi
    echo
  } > "$body"
  ho_vf_block "$1" >> "$body" || { ho_ship_err "the Verification block cannot be built"; return 65; }
}

# ---- pr ---------------------------------------------------------------------------------------
ho_ship_pr() {
  local lane=${1-} prof open worker base body url n rc
  [ $# -eq 1 ] || { ho_ship_usage; return 64; }
  ho_loop_lane_ok "$lane" || return 65
  ho_ship_load "$lane" || return $?
  [ -z "$S_PR" ] || { printf 'PR #%s of lane %s is already open\n' "$S_PR" "$lane"; return 0; }
  prof=$(ho_au_profile) || return 78
  open=$(printf '%s' "$prof" | jq -r .pr_open)
  # H-044, D10: the opening point.
  case $open in
    none) ho_ship_err "the profile opens no PR (pr_open none)"; return "$HO_EXIT_DENIED" ;;
    after-validator)
      worker=$(jq -r '.worker_session // ""' "$HO_RUN_DIR/lanes/$lane.json" 2>/dev/null) || worker=""
      if ! ho_loop_verdict_check "$lane" "$S_SHA" "$worker"; then
        ho_ledger_append ship-pr-waits lane "$lane" reason "$HO_LOOP_VWHY"
        ho_ship_err "no draft PR before the validator passes: $HO_LOOP_VWHY"
        return 65
      fi ;;
    *)
      if ! jq -e --arg t "$S_TICKET" --arg s "$open" 'select(.kind == "step-begin" and .ticket == $t and .step == $s)' \
          "$HO_RUN_DIR/ledger.jsonl" >/dev/null 2>&1; then
        ho_ledger_append ship-pr-waits lane "$lane" reason "step $open has not begun"
        ho_ship_err "the PR opens at step $open (pr_open), which has not begun for ticket $S_TICKET"
        return 65
      fi ;;
  esac
  # H-056: the test rule gates the PR; the result must be recorded for this exact commit.
  if ! ho_vf_tests_ok "$lane"; then
    ho_ledger_append ship-pr-waits lane "$lane" reason "$HO_VF_WHY"
    ho_ship_err "no PR: $HO_VF_WHY"
    return 65
  fi
  ho_ship_stop "$S_TICKET" || return $?
  rc=0; ho_ship_au pr "$S_TICKET" || rc=$?
  [ "$rc" -eq 0 ] || { ho_ship_err "the autonomy profile opens no PR"; return "$rc"; }
  base=$(ho_ship_base) || return $?
  ho_ship_body "$lane" || return $?
  body="$HO_RUN_DIR/ship/$lane.body.md"
  url=$(gh pr create --draft --head "$S_BRANCH" --base "$base" --title "$S_TITLE" --body-file "$body" $(ho_ship_gh_repo) 2>"$HO_RUN_DIR/logs/ship-pr.log") \
    || { ho_ledger_append ship-pr-failed lane "$lane"; ho_ship_err "gh pr create failed (see $HO_RUN_DIR/logs/ship-pr.log)"; return 70; }
  url=$(printf '%s\n' "$url" | tail -n 1)
  n=${url##*/}
  case $n in '' | *[!0-9]*) ho_ship_err "gh pr create gave no PR number: $url"; return 70 ;; esac
  ho_ship_set "$lane" '.pr = ($n | tonumber) | .url = $u | .base = $b' --arg n "$n" --arg u "$url" --arg b "$base" || return 1
  ho_ledger_append ship-pr-opened lane "$lane" ticket "$S_TICKET" pr "$n" base "$base" draft true
  printf 'draft PR #%s opened: %s (base %s)\n' "$n" "$url" "$base"
  # D10: only a profile that may merge marks it ready.
  if ho_ship_au pr-ready "$S_TICKET" 2>/dev/null && [ "$(printf '%s' "$prof" | jq -r .merge)" != never ]; then
    gh pr ready "$n" $(ho_ship_gh_repo) >/dev/null 2>&1 && { ho_ledger_append ship-pr-ready lane "$lane" pr "$n"; printf 'PR #%s marked ready\n' "$n"; } \
      || ho_ship_err "PR #$n could not be marked ready; it stays a draft"
  fi
}

# ho_ship_patch <repo> <range-or-commit>: the stable patch id of a change.
ho_ship_patch() { git -C "$1" diff "${@:2}" 2>/dev/null | git -C "$1" patch-id --stable 2>/dev/null | cut -d' ' -f1; }

# ho_ship_confirm: 0 when git shows the change in the fetched base tip; sets S_MERGE (the commit
# on the base that holds it, or empty for a fast-forward).
ho_ship_confirm() {
  local tip=$1 mc mb want
  S_MERGE="" S_MERGE_KIND=""
  if git -C "$S_WT" merge-base --is-ancestor "$S_SHA" "$tip" 2>/dev/null; then
    S_MERGE=$(git -C "$S_WT" rev-list --first-parent --ancestry-path --reverse "$S_SHA..$tip" 2>/dev/null | head -n 1)
    S_MERGE_KIND=fast-forward
    if [ -n "$S_MERGE" ]; then
      if git -C "$S_WT" rev-list --parents -n 1 "$S_MERGE" | tr ' ' '\n' | tail -n +2 | grep -qx "$S_SHA"; then S_MERGE_KIND=merge
      else S_MERGE_KIND=unknown; fi
    fi
    return 0
  fi
  # A squash or rebase merge: the PR's merge commit must be on the base and carry the same change.
  mc=$(gh pr view "$S_PR" --json mergeCommit $(ho_ship_gh_repo) 2>/dev/null | jq -r '.mergeCommit.oid // ""' 2>/dev/null) || mc=""
  [ -n "$mc" ] || return 1
  git -C "$S_WT" merge-base --is-ancestor "$mc" "$tip" 2>/dev/null || return 1
  mb=$(git -C "$S_WT" merge-base "$S_SHA" "$mc^" 2>/dev/null) || return 1
  want=$(ho_ship_patch "$S_WT" "$mb" "$S_SHA")
  [ -n "$want" ] && [ "$want" = "$(ho_ship_patch "$S_WT" "$mc^" "$mc")" ] || return 1
  S_MERGE=$mc S_MERGE_KIND=squash
}

# ho_ship_smoke_cmd: the smoke command, from the user config only (D37-FLOW-8), or nothing.
ho_ship_smoke_cmd() {
  local proj label cmd
  proj="$HO_PROJECT_DIR/.harness/config.json"
  if [ "$(jq -r '[(.smoke.list? // {}) | to_entries[]? | .value.command? // empty] | length' "$proj" 2>/dev/null || echo 1)" != 0 ]; then
    ho_ship_err "the project config holds a smoke command; a command is read only from smoke.list.<label>.command of the user config"
    return 65
  fi
  label=$(ho_cfg '.smoke.use' '') || return 78
  [ -n "$label" ] || return 0
  case $label in -* | *[!a-z0-9-]*) ho_ship_err "smoke.use must be a label of a-z 0-9 -: $label"; return 78 ;; esac
  cmd=$(ho_cfg_user ".smoke.list[\"$label\"].command" | jq -r 'strings // ""') || return 78
  [ -n "$cmd" ] || { ho_ship_err "smoke test $label has no command in the user config"; return 78; }
  printf '%s\n' "$cmd"
}

# ho_ship_revert <tip>: revert the merged change on the base and push it back (H-051).
ho_ship_revert() {
  local tip=$1 tmp rc=0
  ho_ship_au push "$S_TICKET" || { ho_ship_err "the profile allows no push, so the revert cannot reach $S_BASE"; return 77; }
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/ho-revert.XXXXXX")
  git -C "$S_WT" worktree add -q --detach "$tmp" "$tip" 2>/dev/null || { rm -rf "$tmp"; return 1; }
  # Only a commit that brought the change in is reverted: a merge commit with the pushed commit
  # as a parent, or the squash commit the PR names. Anything else is left for a person.
  if [ -n "$S_MERGE" ] && [ "$S_MERGE_KIND" = unknown ]; then
    git -C "$S_WT" worktree remove --force "$tmp" >/dev/null 2>&1 || rm -rf "$tmp"
    return 1
  fi
  if [ -n "$S_MERGE" ]; then
    if [ "$(git -C "$tmp" rev-list --parents -n 1 "$S_MERGE" | wc -w)" -gt 2 ]; then
      git -C "$tmp" revert --no-edit -m 1 "$S_MERGE" >/dev/null 2>&1 || rc=1
    else
      git -C "$tmp" revert --no-edit "$S_MERGE" >/dev/null 2>&1 || rc=1
    fi
  else
    git -C "$tmp" revert --no-edit "$(git -C "$tmp" merge-base "$S_SHA" "$tip~0" 2>/dev/null)..$S_SHA" >/dev/null 2>&1 || rc=1
  fi
  [ "$rc" -ne 0 ] || git -C "$tmp" push -q "$S_REMOTE" "HEAD:refs/heads/$S_BASE" 2>/dev/null || rc=1
  git -C "$S_WT" worktree remove --force "$tmp" >/dev/null 2>&1 || rm -rf "$tmp"
  return "$rc"
}

# ---- merged -----------------------------------------------------------------------------------
ho_ship_merged() {
  local lane=${1-} tip cmd rc log react close
  [ $# -eq 1 ] || { ho_ship_usage; return 64; }
  ho_loop_lane_ok "$lane" || return 65
  ho_ship_load "$lane" || return $?
  [ -n "$S_PR" ] && [ -n "$S_BASE" ] || { ho_ship_err "lane $lane has no PR yet"; return 65; }
  ho_ship_stop "$S_TICKET" soft || return $?
  if ! git -C "$S_WT" fetch -q "$S_REMOTE" "refs/heads/$S_BASE" 2>/dev/null || ! tip=$(git -C "$S_WT" rev-parse -q --verify FETCH_HEAD); then
    ho_ledger_append ship-merge-unconfirmed lane "$lane" ticket "$S_TICKET" reason "cannot fetch $S_BASE from $S_REMOTE"
    ho_ship_err "cannot fetch $S_BASE from $S_REMOTE; the merge is not confirmed and ticket $S_TICKET stays open"
    return 70
  fi
  if ! ho_ship_confirm "$tip"; then
    ho_ledger_append ship-merge-unconfirmed lane "$lane" ticket "$S_TICKET" pr "$S_PR" base "$S_BASE" tip "$tip" reason "git does not show the change in the base"
    ho_ship_err "merge FAILED: git does not show the change of PR #$S_PR in $S_BASE; it does not count as done and ticket $S_TICKET stays open"
    return 70
  fi
  ho_ship_set "$lane" '.merged = $tip' --arg tip "$tip" || return 1
  ho_ledger_append ship-merge-confirmed lane "$lane" ticket "$S_TICKET" pr "$S_PR" base "$S_BASE" tip "$tip"
  printf 'merge of PR #%s confirmed by git in %s at %s\n' "$S_PR" "$S_BASE" "$tip"
  # H-045, H-050: post-merge steps first; the ticket waits for them.
  cmd=$(ho_ship_smoke_cmd) || return $?
  if [ -n "$cmd" ]; then
    rc=0; ho_ship_au post-merge "$S_TICKET" || rc=$?
    if [ "$rc" -ne 0 ]; then
      ho_ledger_append owner-action title "post-merge smoke test of ticket $S_TICKET" why "the autonomy profile runs no post-merge steps; the ticket stays in progress" \
        command "run the smoke test, then: harness tickets done $S_TICKET" verify "the smoke test passes"
      printf 'ticket %s stays in progress: the profile runs no post-merge steps; a human runs the smoke test\n' "$S_TICKET"
      return "$HO_EXIT_HUMAN"
    fi
    log="$HO_RUN_DIR/logs/smoke-$lane.log"
    ho_ledger_append smoke-start lane "$lane" ticket "$S_TICKET" base "$S_BASE" tip "$tip"
    rc=0
    (cd "$HO_PROJECT_DIR" && HO_SMOKE_BRANCH=$S_BASE HO_SMOKE_SHA=$tip bash -c "$cmd") > "$log" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
      react=$(ho_cfg '.smoke.on_fail' fix) || return 78
      ho_ledger_append smoke-failed lane "$lane" ticket "$S_TICKET" exit "$rc" reaction "$react"
      case $react in
        revert)
          if ho_ship_revert "$tip"; then
            ho_ledger_append smoke-reverted lane "$lane" ticket "$S_TICKET" base "$S_BASE"
            printf 'smoke test FAILED (exit %s): the change was reverted on %s; ticket %s is not done\n' "$rc" "$S_BASE" "$S_TICKET"
          else
            ho_ledger_append owner-action title "revert of ticket $S_TICKET failed" why "the smoke test failed and the revert did not go through" \
              command "revert the change on $S_BASE by hand" verify "the smoke test passes"
            printf 'smoke test FAILED (exit %s): the revert did not go through; a human must revert; ticket %s is not done\n' "$rc" "$S_TICKET"
          fi ;;
        fix)
          ho_ledger_append smoke-fix-due lane "$lane" ticket "$S_TICKET" log "$log"
          printf 'smoke test FAILED (exit %s): a fix is due for ticket %s (log %s); the ticket is not done\n' "$rc" "$S_TICKET" "$log" ;;
        *) ho_ship_err "smoke.on_fail must be fix or revert: $react"; return 78 ;;
      esac
      return "$HO_EXIT_GATE"
    fi
    ho_ledger_append smoke-passed lane "$lane" ticket "$S_TICKET"
    printf 'smoke test passed\n'
  fi
  # D11: done, and closed unless close_on_merge is false.
  close=$(ho_cfg '.close_on_merge' true) || return 78
  if [ "$close" = false ]; then ho_tickets done "$S_TICKET" --keep-open >/dev/null || return $?
  else ho_tickets done "$S_TICKET" >/dev/null || return $?; fi
  ho_ledger_append ship-ticket-done lane "$lane" ticket "$S_TICKET" closed "$([ "$close" = false ] && echo false || echo true)"
  printf 'ticket %s done%s\n' "$S_TICKET" "$([ "$close" = false ] && echo ' (left open: close_on_merge false)')"
}

# ---- merge <lane> --facts F: the remote merge under a profile that may merge -------------------
# The engine checks the profile and every mechanical merge condition first (S8-08b), and the
# verdict for the exact pushed commit; then gh merges the PR, and `merged` confirms it by git.
ho_ship_merge() {
  local lane=${1-} facts="" rc worker
  shift || true
  [ "${1-}" = --facts ] && [ -n "${2-}" ] && [ $# -eq 2 ] || { ho_ship_usage; return 64; }
  facts=$2
  ho_loop_lane_ok "$lane" || return 65
  ho_ship_load "$lane" || return $?
  [ -n "$S_PR" ] || { ho_ship_err "lane $lane has no PR yet"; return 65; }
  ho_ship_stop "$S_TICKET" || return $?
  worker=$(jq -r '.worker_session // ""' "$HO_RUN_DIR/lanes/$lane.json" 2>/dev/null) || worker=""
  ho_loop_verdict_check "$lane" "$S_SHA" "$worker" || { ho_ship_err "no merge: $HO_LOOP_VWHY"; return 65; }
  ho_vf_tests_ok "$lane" || { ho_ship_err "no merge: $HO_VF_WHY"; return 65; }
  rc=0; ho_au_check merge --for "$S_TICKET" --facts "$facts" >/dev/null || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  if ! gh pr merge "$S_PR" --merge $(ho_ship_gh_repo) >"$HO_RUN_DIR/logs/ship-merge.log" 2>&1; then
    ho_ledger_append ship-merge-failed lane "$lane" pr "$S_PR"
    ho_ship_err "gh pr merge of PR #$S_PR failed (see $HO_RUN_DIR/logs/ship-merge.log); ticket $S_TICKET stays open"
    return 70
  fi
  ho_ledger_append ship-merge-requested lane "$lane" pr "$S_PR"
  ho_ship_merged "$lane"
}

ho_ship_status() {
  local f
  for f in "$HO_RUN_DIR"/ship/*.json; do [ -f "$f" ] && jq -c '{lane, ticket, branch, pr, base, merged}' "$f"; done
  return 0
}

ho_ship_main() {
  [ $# -ge 2 ] || { ho_ship_usage; exit 64; }
  ho_run_open "$1"
  ho_session_bind_project || exit $?
  ho_tk_bind_project_dir
  local verb=$2 rc=0
  shift 2
  mkdir -p "$HO_RUN_DIR/logs"
  case $verb in
    push) ho_ship_push "$@" || rc=$? ;;
    pr) ho_ship_pr "$@" || rc=$? ;;
    merge) ho_ship_merge "$@" || rc=$? ;;
    merged) ho_ship_merged "$@" || rc=$? ;;
    status) ho_ship_status ;;
    *) ho_ship_usage; rc=64 ;;
  esac
  exit "$rc"
}
