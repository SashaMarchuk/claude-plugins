# shellcheck shell=bash
# Minimal run loop (tasks.md 8.1): the local integration branch of a run and the engine-checked
# merge into it. H-055: no merge without a plain "passed" verdict of the independent validator
# for the exact commit. H-046: a merge counts only when git confirms it. Design Rebuild reuse
# list: one local integration branch per run, the gate re-run on the merged tree, and the
# finalize commit as the only completion signal.
#
#   <run>/integration.json            {branch, worktree, base, tip}; tip is the last confirmed tip
#   <run>/lanes/<lane>.json           {lane, worktree, branch, sha}: the finalize commit
#   <run>/verdicts/<lane>/<sha>.md    validator verdict for that exact commit
#   <run>/gates/<lane>-<sha>.log      output of the gate on the merged tree
#
# Exit codes: 65 refused before any merge, 69 the merge would change nothing, 70 the merge was
# not confirmed (conflict or a failed git check), 72 the gate failed on the merged tree,
# 75 the run is stopped. On 69, 72 and a failed merge or check (70) the integration branch is put
# back at its old tip; when the branch moved while the gate ran (70) it is left for a person.
# Requires lib/run.sh, lib/config.sh, lib/files.sh and ho_cfg_user from lib/sessions.sh.

HO_EXIT_NOOP=69
HO_EXIT_UNCONFIRMED=70
HO_EXIT_GATE=72

ho_loop_err() { printf 'harness: %s\n' "$*" >&2; }

# A lane name becomes a path and part of the finalize subject: a-z 0-9 . - only.
ho_loop_lane_ok() {
  case ${1-} in
    '' | [.-]* | *..* | *[!a-z0-9.-]*) ho_loop_err "lane name must use a-z 0-9 . - and not start with . or -: ${1-}"; return 65 ;;
  esac
}

# ho_loop_clean <worktree>: 0 clean, 1 dirty, 2 cannot read (never taken as clean).
ho_loop_clean() {
  local out
  out=$(git -C "$1" status --porcelain --untracked-files=all 2>/dev/null) || return 2
  [ -z "$out" ] || return 1
  ! git -C "$1" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 || return 1
}

ho_loop_ref() { git -C "$1" rev-parse -q --verify "$2^{commit}" 2>/dev/null; }

ho_loop_field() { jq -er --arg k "$2" '.[$k] | strings' "$1" 2>/dev/null; }

# ---- integration --repo R --base B --worktree W -------------------------------------------
ho_loop_integration() {
  local repo="" base="" wt="" f="$HO_RUN_DIR/integration.json" sha branch
  while [ $# -gt 0 ]; do
    case $1 in
      --repo) repo=${2-}; shift 2 ;;
      --base) base=${2-}; shift 2 ;;
      --worktree) wt=${2-}; shift 2 ;;
      *) ho_loop_usage; return 64 ;;
    esac
  done
  [ -n "$repo" ] && [ -n "$base" ] && [ -n "$wt" ] || { ho_loop_usage; return 64; }
  ho_assert_abs "$wt" "integration worktree" || return 65
  [ ! -e "$f" ] || { ho_loop_err "run $HO_RUN_ID already has an integration branch ($(ho_loop_field "$f" branch))"; return 65; }
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || { ho_loop_err "not a git repository: $repo"; return 65; }
  sha=$(ho_loop_ref "$repo" "$base") || { ho_loop_err "base $base is not a commit in $repo"; return 65; }
  [ ! -e "$wt" ] || { ho_loop_err "integration worktree already exists: $wt"; return 65; }
  branch="ho/$HO_RUN_ID"
  ! git -C "$repo" show-ref -q --verify "refs/heads/$branch" || { ho_loop_err "branch $branch already exists"; return 65; }
  git -C "$repo" worktree add -q -b "$branch" "$wt" "$sha" || { ho_loop_err "cannot create the integration worktree $wt"; return 1; }
  wt=$(cd -P "$wt" && pwd -P)
  jq -n --arg branch "$branch" --arg worktree "$wt" --arg base "$sha" --arg tip "$sha" '$ARGS.named' \
    | ho_atomic_write "$f" || return 1
  ho_ledger_append integration-start branch "$branch" base "$sha"
  printf '%s\n' "$branch"
}

# ---- ready <lane> --worktree W: the finalize commit is the only completion signal -----------
ho_loop_ready() {
  local lane=${1-} wt="" branch sha subj rc=0
  shift || true
  [ "${1-}" = --worktree ] && [ -n "${2-}" ] || { ho_loop_usage; return 64; }
  wt=$2
  ho_loop_lane_ok "$lane" || return 65
  [ -f "$HO_RUN_DIR/integration.json" ] || { ho_loop_err "run $HO_RUN_ID has no integration branch yet"; return 65; }
  branch=$(git -C "$wt" symbolic-ref -q --short HEAD 2>/dev/null) || { ho_loop_err "lane $lane: $wt is not on a branch"; return 65; }
  ho_loop_clean "$wt" || rc=$?
  [ "$rc" -eq 0 ] || { ho_loop_err "lane $lane: the worktree $wt is not clean (or cannot be read); not ready"; return 65; }
  sha=$(ho_loop_ref "$wt" HEAD) || { ho_loop_err "lane $lane: cannot read HEAD of $wt"; return 65; }
  subj=$(git -C "$wt" log -1 --format=%s "$sha")
  case $subj in
    "finalize($lane):"*) ;;
    *) ho_loop_err "lane $lane: the tip is not a finalize($lane): commit; not ready"; return 65 ;;
  esac
  wt=$(cd -P "$wt" && pwd -P)
  mkdir -p "$HO_RUN_DIR/lanes" "$HO_RUN_DIR/verdicts/$lane"
  jq -n --arg lane "$lane" --arg worktree "$wt" --arg branch "$branch" --arg sha "$sha" '$ARGS.named' \
    | ho_atomic_write "$HO_RUN_DIR/lanes/$lane.json" || return 1
  ho_ledger_append lane-ready lane "$lane" sha "$sha"
  printf '%s\n' "$HO_RUN_DIR/verdicts/$lane/$sha.md"
}

# ho_loop_gate_cmd: the gate command (D37-FLOW-8 (a): from the user config only; the
# project or user config selects its label with gate.use).
ho_loop_gate_cmd() {
  local proj label cmd has
  proj=$(ho_project_root) || { ho_loop_err "no project here (no .harness/config.json)"; return 78; }
  proj="$proj/.harness/config.json"
  has=$(jq -r '[(.gate.command? // empty), ((.gate.list? // {}) | to_entries[]? | .value.command? // empty)]
      | map(select(. != "" and . != null)) | length' "$proj" 2>/dev/null) || has=1
  if [ "$has" != 0 ]; then
    ho_loop_err "the project config $proj holds a gate command. A command is never read from a project config; move it to gate.list.<label>.command in the user config $(ho_user_config) and keep only gate.use in the project config"
    return 65
  fi
  label=$(ho_cfg '.gate.use' '') || return 78
  case $label in
    '' ) ho_loop_err "no gate is configured (gate.use); a merge without the gate is refused"; return 65 ;;
    -* | *[!a-z0-9-]*) ho_loop_err "gate.use must be a label of a-z 0-9 -: $label"; return 65 ;;
  esac
  cmd=$(ho_cfg_user ".gate.list[\"$label\"].command" | jq -r 'strings // ""') || return 78
  [ -n "$cmd" ] || { ho_loop_err "gate $label has no command in gate.list of the user config $(ho_user_config)"; return 65; }
  printf '%s\n' "$cmd"
}

ho_loop_refuse() { # <code> <lane> <reason>
  ho_ledger_append merge-refused lane "$2" reason "$3"
  ho_loop_err "merge of lane $2 refused: $3"
  return "$1"
}

# ho_loop_rollback <worktree> <branch> <old>: put the checked-out integration branch back.
# reset --hard inside its own worktree, never update-ref (field note C5).
ho_loop_rollback() {
  local wt=$1 branch=$2 old=$3
  if git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    git -C "$wt" merge --abort >/dev/null 2>&1 || true
  fi
  git -C "$wt" reset -q --hard "$old" >/dev/null 2>&1 || true
  if [ "$(ho_loop_ref "$wt" "refs/heads/$branch")" = "$old" ] && ho_loop_clean "$wt"; then
    return 0
  fi
  ho_ledger_append merge-rollback-failed branch "$branch" tip "$old"
  ho_loop_err "could not put $branch back to $old in $wt; fix it by hand before the next merge"
  return 1
}

# ---- merge <lane> ------------------------------------------------------------------------
ho_loop_merge_locked() {
  local lane=$1 ij="$HO_RUN_DIR/integration.json" lj="$HO_RUN_DIR/lanes/$1.json"
  local iwt branch old lwt lbranch lsha vf first gate stopped=0 rc=0 new gw log grc=0
  ho_stopped || stopped=$?
  [ "$stopped" -eq 1 ] || { ho_loop_err "the run is stopped (or its stop state is unknown); no merge"; return 75; }
  [ -f "$ij" ] || { ho_loop_err "run $HO_RUN_ID has no integration branch"; return 65; }
  [ -f "$lj" ] || ho_loop_refuse 65 "$lane" "lane is not ready (no finalize commit recorded)" || return
  iwt=$(ho_loop_field "$ij" worktree) && branch=$(ho_loop_field "$ij" branch) && old=$(ho_loop_field "$ij" tip) \
    || ho_loop_refuse 65 "$lane" "integration.json is unreadable" || return
  lwt=$(ho_loop_field "$lj" worktree) && lbranch=$(ho_loop_field "$lj" branch) && lsha=$(ho_loop_field "$lj" sha) \
    || ho_loop_refuse 65 "$lane" "lane record is unreadable" || return
  gate=$(ho_loop_gate_cmd) || { rc=$?; ho_ledger_append merge-refused lane "$lane" reason "gate not configured"; return "$rc"; }

  # H-055: a plain "passed" verdict for the exact finalize commit.
  vf="$HO_RUN_DIR/verdicts/$lane/$lsha.md"
  if [ -L "$vf" ] || [ ! -f "$vf" ]; then
    ho_loop_refuse 65 "$lane" "no verdict file for $lsha (a link does not count)"; return
  fi
  first=$(head -n 1 "$vf")
  [ "$first" = passed ] || { ho_loop_refuse 65 "$lane" "the verdict for $lsha is not \"passed\" (first line: ${first:0:60})"; return; }

  # The lane: still at the validated finalize commit, clean (PR-9).
  [ "$(ho_loop_ref "$lwt" "refs/heads/$lbranch")" = "$lsha" ] && [ "$(ho_loop_ref "$lwt" HEAD)" = "$lsha" ] \
    || { ho_loop_refuse 65 "$lane" "the lane tip moved after $lsha was validated; no verdict for the new tip"; return; }
  case $(git -C "$lwt" log -1 --format=%s "$lsha") in
    "finalize($lane):"*) ;;
    *) ho_loop_refuse 65 "$lane" "$lsha is not a finalize($lane): commit"; return ;;
  esac
  rc=0; ho_loop_clean "$lwt" || rc=$?
  [ "$rc" -eq 0 ] || { ho_loop_refuse 65 "$lane" "the lane worktree is not clean (or cannot be read)"; return; }

  # Tip check before: the checked-out integration branch is at the last confirmed tip, clean.
  [ "$(git -C "$iwt" symbolic-ref -q HEAD 2>/dev/null)" = "refs/heads/$branch" ] \
    || { ho_loop_refuse 65 "$lane" "$iwt does not have $branch checked out"; return; }
  [ "$(ho_loop_ref "$iwt" "refs/heads/$branch")" = "$old" ] \
    || { ho_loop_refuse 65 "$lane" "the tip of $branch is not the last confirmed tip $old; it moved outside the engine or a merge was interrupted"; return; }
  rc=0; ho_loop_clean "$iwt" || rc=$?
  [ "$rc" -eq 0 ] || { ho_loop_refuse 65 "$lane" "the integration worktree is not clean (or cannot be read)"; return; }
  ho_loop_ref "$iwt" "$lsha" >/dev/null || { ho_loop_refuse 65 "$lane" "$lsha is not in the integration repository"; return; }

  # No-op before merging: the lane is already in the branch.
  if git -C "$iwt" merge-base --is-ancestor "$lsha" "$old" 2>/dev/null; then
    ho_loop_refuse "$HO_EXIT_NOOP" "$lane" "no-op: $lsha is already in $branch; nothing would change"; return
  fi

  mkdir -p "$HO_RUN_DIR/gates"
  if ! git -C "$iwt" merge -q --no-ff --no-edit -m "merge($lane): $lsha into $branch" "$lsha" \
      > "$HO_RUN_DIR/gates/$lane-$lsha.merge.log" 2>&1; then
    ho_loop_rollback "$iwt" "$branch" "$old" || true
    ho_loop_refuse "$HO_EXIT_UNCONFIRMED" "$lane" "git merge failed (conflict or error, log gates/$lane-$lsha.merge.log); aborted, $branch stays at $old"; return
  fi

  # H-046: confirm through git, from the branch ref, not from what the merge printed.
  new=$(ho_loop_ref "$iwt" "refs/heads/$branch") || new=""
  if [ -z "$new" ] || [ "$new" = "$old" ] \
      || [ "$(ho_loop_ref "$iwt" HEAD)" != "$new" ] \
      || [ "$(ho_loop_ref "$iwt" "$new^1")" != "$old" ] \
      || [ "$(ho_loop_ref "$iwt" "$new^2")" != "$lsha" ] \
      || ! git -C "$iwt" merge-base --is-ancestor "$lsha" "refs/heads/$branch" 2>/dev/null \
      || ! ho_loop_clean "$iwt"; then
    ho_loop_rollback "$iwt" "$branch" "$old" || true
    ho_loop_refuse "$HO_EXIT_UNCONFIRMED" "$lane" "git does not confirm the merge of $lsha into $branch; rolled back to $old"; return
  fi
  if git -C "$iwt" diff --quiet "$old" "$new" 2>/dev/null; then
    ho_loop_rollback "$iwt" "$branch" "$old" || true
    ho_loop_refuse "$HO_EXIT_NOOP" "$lane" "no-op: the merge of $lsha changed no file in $branch; rolled back to $old"; return
  fi

  # The gate re-runs on the merged tree, in a throwaway detached worktree, so whatever the
  # gate writes never dirties the integration worktree (field note C1).
  mkdir -p "$HO_RUN_DIR/gates"
  log="$HO_RUN_DIR/gates/$lane-$lsha.log"
  if ! { gw=$(mktemp -d "${TMPDIR:-/tmp}/ho-gate.XXXXXX") && rmdir "$gw" \
      && git -C "$iwt" worktree add -q --detach "$gw" "$new" >/dev/null 2>&1; }; then
    ho_loop_rollback "$iwt" "$branch" "$old" || true
    ho_loop_refuse "$HO_EXIT_UNCONFIRMED" "$lane" "cannot create a worktree to run the gate on the merged tree; rolled back to $old"; return
  fi
  (cd "$gw" && /bin/bash -c "$gate") > "$log" 2>&1 || grc=$?
  git -C "$iwt" worktree remove --force "$gw" >/dev/null 2>&1 || rm -rf "$gw"
  git -C "$iwt" worktree prune >/dev/null 2>&1 || true
  if [ "$grc" -ne 0 ]; then
    ho_loop_rollback "$iwt" "$branch" "$old" || true
    ho_loop_refuse "$HO_EXIT_GATE" "$lane" "the gate failed on the merged tree (exit $grc, log $log); rolled back to $old"; return
  fi
  # Tip check after: nothing moved the branch while the gate ran.
  if [ "$(ho_loop_ref "$iwt" "refs/heads/$branch")" != "$new" ] || ! ho_loop_clean "$iwt"; then
    ho_loop_refuse "$HO_EXIT_UNCONFIRMED" "$lane" "$branch moved or got dirty while the gate ran; the merge is not confirmed"; return
  fi

  # Ledger line first: if the tip write then fails, the next merge refuses on the tip check.
  ho_ledger_append merge-confirmed lane "$lane" sha "$lsha" branch "$branch" base "$old" tip "$new"
  jq --arg tip "$new" '.tip = $tip' "$ij" | ho_atomic_write "$ij" || return 1
  printf 'merged lane %s (%s) into %s at %s\n' "$lane" "$lsha" "$branch" "$new"
}

# One merge at a time per run, under its own lock (not the ledger lock), in a subshell so the
# EXIT trap stays local. A lock whose holder is dead is taken over.
ho_loop_merge() {
  local lane=${1-}
  [ $# -eq 1 ] || { ho_loop_usage; return 64; }
  ho_loop_lane_ok "$lane" || return 65
  (
    HO_LOOP_LOCK="$HO_RUN_DIR/merge.lock"
    ho_loop_rc=70
    n=0
    until mkdir "$HO_LOOP_LOCK" 2>/dev/null; do
      pid=$(cat "$HO_LOOP_LOCK/pid" 2>/dev/null || true)
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then rm -rf "$HO_LOOP_LOCK"; continue; fi
      # A holder killed between mkdir and writing its PID: stale after one minute.
      if [ -z "$pid" ] && [ -n "$(find "$HO_LOOP_LOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then rm -rf "$HO_LOOP_LOCK"; continue; fi
      n=$((n + 1))
      [ "$n" -lt 1800 ] || { ho_loop_err "another merge of run $HO_RUN_ID holds $HO_LOOP_LOCK"; exit 75; }
      sleep 0.1
    done
    # The code stays 70 until the merge step returns: a step that ends with exit (a failed
    # ledger write) must never leave through this trap as 0.
    trap 'rm -rf "$HO_LOOP_LOCK"; exit "$ho_loop_rc"' EXIT
    # bash 3.2 has no BASHPID: the parent of a child shell is this subshell.
    sh -c 'echo "$PPID"' > "$HO_LOOP_LOCK/pid" 2>/dev/null || true
    if ho_loop_merge_locked "$lane"; then ho_loop_rc=0; else ho_loop_rc=$?; fi
    exit "$ho_loop_rc"
  )
}

ho_loop_status() {
  [ -f "$HO_RUN_DIR/integration.json" ] || { echo "no integration branch"; return 0; }
  jq -r '"integration \(.branch) at \(.tip) (base \(.base)) in \(.worktree)"' "$HO_RUN_DIR/integration.json"
  ho_ledger_events | jq -r 'select(.kind == "merge-confirmed") | "merged \(.lane) \(.sha) -> \(.tip)"'
}

ho_loop_usage() {
  cat >&2 <<'USAGE'
usage: harness loop <run-dir> <verb> [args]
  integration --repo R --base B --worktree W   create the run's local integration branch
  ready <lane> --worktree W                    the lane's tip must be a finalize(<lane>): commit
                                               on a clean tree; prints the verdict file path
  merge <lane>                                 merge only on a "passed" verdict, clean trees and
                                               checked tips; confirmed through git; gate re-run
  status                                       the integration tip and the confirmed merges
exit: 65 refused, 69 no-op, 70 not confirmed, 72 gate failed, 75 stopped
USAGE
}

ho_loop_main() {
  [ $# -ge 2 ] || { ho_loop_usage; exit 64; }
  ho_run_open "$1"
  local verb=$2 rc=0
  shift 2
  case $verb in
    integration) ho_loop_integration "$@" || rc=$? ;;
    ready) ho_loop_ready "$@" || rc=$? ;;
    merge) ho_loop_merge "$@" || rc=$? ;;
    status) ho_loop_status || rc=$? ;;
    *) ho_loop_usage; rc=64 ;;
  esac
  exit "$rc"
}
