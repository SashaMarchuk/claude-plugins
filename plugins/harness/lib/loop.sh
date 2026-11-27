# shellcheck shell=bash
# Minimal run loop (tasks.md 8.1): the local integration branch of a run and the engine-checked
# merge into it. H-055: no merge without a plain "passed" verdict of the independent validator
# for the exact commit. H-046: a merge counts only when git confirms it. Design Rebuild reuse
# list: one local integration branch per run, the gate re-run on the merged tree, and the
# finalize commit as the only completion signal.
#
#   <run>/integration.json            {branch, worktree, base, tip}; tip is the last confirmed tip
#   <run>/lanes/<lane>.json           {lane, worktree, branch, sha, worker_session}: the finalize
#                                     commit, and the session that called ready (null outside one)
#   <run>/verdicts/<lane>/<sha>.json  {lane, sha, session_id, session_name, text}: the validator
#                                     verdict for that exact commit, written only by `verdict`
#   <run>/gates/<lane>-<sha>.log      output of the gate on the merged tree
#
# Verdict author (H-055, D37-FLOW-8a): `verdict` runs inside a launched session. It takes the
# session name and ID that the launcher exports and records the session ID with the verdict.
# A merge accepts the verdict only when that session ID belongs to this run's registry with the
# role validator and with no other role (a resumed worker keeps its session ID), and when it is
# not the session that called ready for the lane. This guards against a worker that uses its own
# session identity, and against a file in the repository, passing as the validator. It does not
# guard against a same-user process, a worker included, that sets the two variables to the
# validator's values or edits the run folder by hand: D37-FLOW-8a puts that outside the beta's
# boundary (the owner confirms this reading).
#
# Exit codes: 64 usage, 65 refused before any merge, 69 the merge would change nothing, 70 the
# merge was not confirmed (conflict or a failed git check) or the branch is left for a person,
# 72 the gate failed on the merged tree, 75 the run is stopped, the merge was stopped by a signal
# or another merge holds the lock, 78 config error. On 69, 72, 75 and a failed merge or check
# (70) the integration branch is put back at its old tip, but only while it is still at the old
# tip or at this merge's commit. When it moved to anything else, or the roll back fails, it is
# left for a person (70) and the message never says "rolled back".
# Requires lib/run.sh, lib/config.sh, lib/files.sh, lib/common.sh, ho_cfg_user from
# lib/sessions.sh, and ho_au_profile and ho_au_decide from lib/autonomy.sh.

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
      --repo | --base | --worktree)
        # A flag with no value is a usage error (shift 2 would fail and the loop would never end).
        [ $# -ge 2 ] && [ -n "$2" ] || { ho_loop_usage; return 64; }
        case $1 in --repo) repo=$2 ;; --base) base=$2 ;; *) wt=$2 ;; esac
        shift 2 ;;
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
  local lane=${1-} wt="" branch sha subj rc=0 ticket=""
  shift || true
  while [ $# -gt 0 ]; do
    case $1 in
      --worktree) [ -n "${2-}" ] || { ho_loop_usage; return 64; }; wt=$2; shift 2 ;;
      --ticket) [ $# -ge 2 ] || { ho_loop_usage; return 64; }; ticket=$(ho_stop_ticket_arg "$2") || return 64; shift 2 ;;
      *) ho_loop_usage; return 64 ;;
    esac
  done
  [ -n "$wt" ] || { ho_loop_usage; return 64; }
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
  mkdir -p "$HO_RUN_DIR/lanes"
  jq -n --arg lane "$lane" --arg worktree "$wt" --arg branch "$branch" --arg sha "$sha" --arg ws "${HO_SESSION_ID-}" --arg t "$ticket" \
    '{lane: $lane, worktree: $worktree, branch: $branch, sha: $sha, worker_session: (if $ws == "" then null else $ws end),
      ticket: (if $t == "" then null else $t end)}' \
    | ho_atomic_write "$HO_RUN_DIR/lanes/$lane.json" || return 1
  ho_ledger_append lane-ready lane "$lane" sha "$sha"
  printf '%s\n' "$HO_RUN_DIR/verdicts/$lane/$sha.json"
}

# ho_loop_author_ok <session-id> <lane worker session>: prints why not and returns 1 unless the
# session is a validator of this run and nothing else, and not the lane's worker. The role comes
# from the registry, never from the caller.
ho_loop_author_ok() {
  local sid=$1 worker=$2 sdir="$HO_RUN_DIR/sessions" f roles
  [ -n "$sid" ] || { echo "the verdict names no author session"; return 1; }
  [ -d "$sdir" ] && [ ! -L "$sdir" ] || { echo "run $HO_RUN_ID has no session registry"; return 1; }
  roles=$(for f in "$sdir"/*.json; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      jq -r --arg sid "$sid" --arg run "$HO_RUN_ID" \
        'select(type == "object" and .session_id == $sid) | if .run == $run then (.role | tostring) else "of another run" end' "$f" 2>/dev/null || true
    done | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')
  [ -n "$roles" ] || { echo "session $sid is not in the session registry of run $HO_RUN_ID"; return 1; }
  [ "$roles" = validator ] || { echo "session $sid has the role(s) $roles in run $HO_RUN_ID; only a session that is a validator and nothing else counts"; return 1; }
  [ "$sid" != "$worker" ] || { echo "session $sid is the lane's own worker"; return 1; }
}

# ho_loop_vdir_ok <lane>: the verdicts folder and the lane's folder are no links.
ho_loop_vdir_ok() {
  local d
  for d in "$HO_RUN_DIR/verdicts" "$HO_RUN_DIR/verdicts/$1"; do
    [ ! -L "$d" ] || { echo "$d is a link; a verdict is never read or written through a link"; return 1; }
  done
}

# ho_loop_verdict_check <lane> <sha> <lane worker session>: 0 when the verdict allows a merge;
# then HO_LOOP_VSNAP holds the record exactly as read (one snapshot). Otherwise 1, and
# HO_LOOP_VWHY says why.
ho_loop_verdict_check() {
  local lane=$1 sha=$2 worker=$3 vf="$HO_RUN_DIR/verdicts/$1/$2.json" snap why first sid
  HO_LOOP_VSNAP=""
  HO_LOOP_VWHY=""
  why=$(ho_loop_vdir_ok "$lane") || { HO_LOOP_VWHY=$why; return 1; }
  if [ -L "$vf" ] || [ ! -f "$vf" ]; then HO_LOOP_VWHY="no verdict file for $sha (a link does not count)"; return 1; fi
  snap=$(cat "$vf" 2>/dev/null) || { HO_LOOP_VWHY="the verdict for $sha cannot be read"; return 1; }
  why=$(printf '%s' "$snap" | jq -rs --arg lane "$lane" --arg sha "$sha" '
    if length != 1 or (.[0] | type) != "object" then "the verdict record is not one JSON object"
    else .[0] | if .lane != $lane or .sha != $sha then "the verdict record is not for lane \($lane) at \($sha)"
      elif (.text | type) != "string" then "the verdict record holds no text"
      elif (.session_id | type) != "string" then "the verdict names no author session; only the validator verdict counts, recorded with harness loop verdict"
      else "" end end' 2>/dev/null) || why="the verdict record is not readable JSON"
  [ -z "$why" ] || { HO_LOOP_VWHY=$why; return 1; }
  sid=$(printf '%s' "$snap" | jq -r .session_id)
  why=$(ho_loop_author_ok "$sid" "$worker") || { HO_LOOP_VWHY="the verdict for $sha is not from the independent validator: $why"; return 1; }
  first=$(printf '%s' "$snap" | jq -r '.text | split("\n")[0]')
  [ "$first" = passed ] || { HO_LOOP_VWHY="the verdict for $sha is not \"passed\" (first line: ${first:0:60})"; return 1; }
  HO_LOOP_VSNAP=$snap
}

# ---- verdict <lane> --sha S: the validator records its verdict (text on stdin) ----------------
ho_loop_verdict() {
  local lane=${1-} sha lj lsha worker sid name rec why text f
  shift || true
  [ "${1-}" = --sha ] && [ -n "${2-}" ] && [ $# -eq 2 ] || { ho_loop_usage; return 64; }
  sha=$2
  ho_loop_lane_ok "$lane" || return 65
  lj="$HO_RUN_DIR/lanes/$lane.json"
  [ -f "$lj" ] || { ho_loop_err "lane $lane is not ready (no finalize commit recorded)"; return 65; }
  lsha=$(ho_loop_field "$lj" sha) || { ho_loop_err "lane record of $lane is unreadable"; return 65; }
  [ "$sha" = "$lsha" ] || { ho_loop_err "lane $lane is recorded at $lsha, not $sha; a verdict covers only the recorded commit"; return 65; }
  sid=${HO_SESSION_ID-}
  name=${HO_SESSION_NAME-}
  if [ -z "$sid" ] || [ -z "$name" ]; then
    ho_loop_err "a verdict is recorded only from inside the validator's session (HO_SESSION_NAME and HO_SESSION_ID are not set)"
    return 65
  fi
  rec="$HO_RUN_DIR/sessions/$name.json"
  if ! ho_session_name_ok "$name" 2>/dev/null || [ -L "$rec" ] || [ ! -f "$rec" ] \
      || [ "$(jq -r '.session_id // ""' "$rec" 2>/dev/null)" != "$sid" ]; then
    ho_loop_err "session $name ($sid) is not a session of run $HO_RUN_ID"
    return 65
  fi
  worker=$(jq -r '.worker_session // ""' "$lj" 2>/dev/null) || worker=""
  why=$(ho_loop_author_ok "$sid" "$worker") || { ho_loop_err "verdict refused: $why"; return 65; }
  text=$(cat; printf x) || { ho_loop_err "cannot read the verdict text"; return 65; }
  text=${text%x}
  [ -n "$text" ] || { ho_loop_err "the verdict text is empty"; return 65; }
  why=$(ho_loop_vdir_ok "$lane") || { ho_loop_err "$why"; return 65; }
  mkdir -p "$HO_RUN_DIR/verdicts/$lane" || return 1
  why=$(ho_loop_vdir_ok "$lane") || { ho_loop_err "$why"; return 65; }
  f="$HO_RUN_DIR/verdicts/$lane/$sha.json"
  [ ! -L "$f" ] || { ho_loop_err "$f is a link; nothing is written through it"; return 65; }
  jq -n --arg lane "$lane" --arg sha "$sha" --arg sid "$sid" --arg name "$name" --arg text "$text" --arg ts "$(ho_now)" \
    '{schemaVersion: 2, lane: $lane, sha: $sha, session_id: $sid, session_name: $name, text: $text, written: $ts}' \
    | ho_atomic_write "$f" || return 1
  ho_ledger_append verdict-recorded lane "$lane" sha "$sha" session_id "$sid" verdict "$(printf '%s' "$text" | head -n 1 | cut -c1-60)"
  printf 'verdict for lane %s at %s recorded from session %s\n' "$lane" "$sha" "$name"
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

# ho_loop_ledger <kind> [key value]...: a ledger line from inside the merge subshell. The ledger
# append resets the TERM, INT and HUP traps when it frees its lock, so the merge's own signal
# trap is set again after it (outside a merge, ho_loop_sig is unset and nothing is set).
ho_loop_ledger() {
  ho_ledger_append "$@"
  [ -z "${ho_loop_sig+x}" ] || trap 'ho_loop_sig=1' TERM INT HUP
}

ho_loop_refuse() { # <code> <lane> <reason>
  ho_loop_ledger merge-refused lane "$2" reason "$3"
  ho_loop_err "merge of lane $2 refused: $3"
  return "$1"
}

# ho_loop_pristine <worktree>: prints the first line of `git status` when the worktree holds
# anything at all: an uncommitted change, an untracked file or an ignored file. Returns 1 then,
# 2 when git cannot tell, 0 when it is pristine. The engine itself writes no file into the
# integration worktree (the gate runs in its own throwaway worktree), so nothing is excepted.
ho_loop_pristine() {
  local st
  st=$(git -C "$1" status --porcelain=v1 --untracked-files=all --ignored 2>/dev/null) || { echo "git status failed"; return 2; }
  [ -z "$st" ] || { printf '%s\n' "$st" | head -n 1; return 1; }
  ! git -C "$1" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 || { echo "a merge is in progress"; return 1; }
}

# ho_loop_rollback <worktree> <branch> <old> <merge>: put the checked-out integration branch
# back to <old>. It acts only while the branch is checked out at <old> or at this merge's
# commit <merge> (so no commit made meanwhile is thrown away) and while the worktree is
# pristine, ignored files included (so no edit, untracked or ignored file is thrown away).
# Then `git reset --keep`, inside its own worktree, never update-ref (field note C5); --keep
# itself refuses to overwrite a local change. Returns 0 put back, 1 the reset failed, 2 left
# alone before any reset (HO_LOOP_LEFT_WHY says why).
ho_loop_rollback() {
  local wt=$1 branch=$2 old=$3 mc=$4 cur head first
  cur=$(ho_loop_ref "$wt" "refs/heads/$branch") || cur=""
  head=$(git -C "$wt" symbolic-ref -q HEAD 2>/dev/null || true)
  HO_LOOP_LEFT_WHY=""
  if [ "$head" != "refs/heads/$branch" ]; then
    HO_LOOP_LEFT_WHY="$wt does not have $branch checked out (HEAD is ${head:-detached}), so nothing is reset"
  elif [ "$cur" != "$old" ] && [ "$cur" != "$mc" ]; then
    HO_LOOP_LEFT_WHY="$branch is at ${cur:-an unreadable tip}, not at $old or this merge, so nothing is reset"
  fi
  if [ -z "$HO_LOOP_LEFT_WHY" ] && git -C "$wt" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    # The worktree was pristine before the merge, so aborting the merge loses nothing.
    git -C "$wt" merge --abort >/dev/null 2>&1 || true
  fi
  if [ -z "$HO_LOOP_LEFT_WHY" ] && ! first=$(ho_loop_pristine "$wt"); then
    HO_LOOP_LEFT_WHY="$wt is not clean ($first): it holds an uncommitted change, an untracked or an ignored file, so nothing is reset and nothing is lost"
  fi
  if [ -n "$HO_LOOP_LEFT_WHY" ]; then
    ho_loop_ledger merge-rollback-skipped branch "$branch" tip "${cur:-unknown}" expected "$mc" reason "$HO_LOOP_LEFT_WHY" || true
    return 2
  fi
  git -C "$wt" reset -q --keep "$old" >/dev/null 2>&1 || true
  if [ "$(ho_loop_ref "$wt" "refs/heads/$branch")" = "$old" ] && ho_loop_pristine "$wt" >/dev/null; then
    return 0
  fi
  ho_loop_ledger merge-rollback-failed branch "$branch" tip "$old" || true
  return 1
}

# ho_loop_undo <code> <lane> <reason> <merge>: roll back, then refuse with a message that says
# what really happened. Uses iwt, branch and old of the caller.
ho_loop_undo() {
  local r=0
  ho_loop_rollback "$iwt" "$branch" "$old" "$4" || r=$?
  case $r in
    0) ho_loop_refuse "$1" "$2" "$3; rolled back to $old" ;;
    1) ho_loop_refuse "$HO_EXIT_UNCONFIRMED" "$2" "$3; putting $branch back to $old failed in $iwt, so it is left for a person to fix before the next merge" ;;
    *) ho_loop_refuse "$HO_EXIT_UNCONFIRMED" "$2" "$3; $HO_LOOP_LEFT_WHY; it is left for a person" ;;
  esac
}

# ---- merge <lane> ------------------------------------------------------------------------
ho_loop_merge_locked() {
  local lane=$1 ij="$HO_RUN_DIR/integration.json" lj="$HO_RUN_DIR/lanes/$1.json"
  local iwt branch old lwt lbranch lsha worker why vsnap gate mc stopped=0 rc=0 new gw log grc=0 gpid prof
  # A stop refuses the merge, except for the lane of a ticket that a soft:ticket stop lets run to
  # its end (H-086, D25a); a lane with no ticket counts as new work.
  ho_stop_gate "$(jq -r '.ticket // ""' "$lj" 2>/dev/null || true)" || stopped=$?
  [ "$stopped" -eq 0 ] || { ho_loop_err "the run is stopped (or its stop state is unknown); no merge"; return 75; }
  [ "$ho_loop_sig" -eq 0 ] || { ho_loop_err "the merge was stopped by a signal before it started"; return 75; }
  [ -f "$ij" ] || { ho_loop_err "run $HO_RUN_ID has no integration branch"; return 65; }
  [ -f "$lj" ] || ho_loop_refuse 65 "$lane" "lane is not ready (no finalize commit recorded)" || return
  iwt=$(ho_loop_field "$ij" worktree) && branch=$(ho_loop_field "$ij" branch) && old=$(ho_loop_field "$ij" tip) \
    || ho_loop_refuse 65 "$lane" "integration.json is unreadable" || return
  lwt=$(ho_loop_field "$lj" worktree) && lbranch=$(ho_loop_field "$lj" branch) && lsha=$(ho_loop_field "$lj" sha) \
    || ho_loop_refuse 65 "$lane" "lane record is unreadable" || return
  worker=$(jq -r '.worker_session // ""' "$lj" 2>/dev/null) || worker=""
  # D12, S8-08a: the run's autonomy profile decides whether it merges at all (lib/autonomy.sh).
  # A refusal is recorded by the merge's own ledger line.
  prof=$(ho_au_profile) || ho_loop_refuse 78 "$lane" "the autonomy profile cannot be read" || return
  ho_au_decide "$prof" merge "$lane" "" "" 1
  [ "$HO_AU_RC" -eq 0 ] || ho_loop_refuse 65 "$lane" "profile $(printf '%s' "$prof" | jq -r .name): $HO_AU_WHY" || return
  gate=$(ho_loop_gate_cmd) || { rc=$?; ho_loop_ledger merge-refused lane "$lane" reason "gate not configured"; return "$rc"; }

  # H-055: a plain "passed" verdict of the independent validator for the exact finalize commit.
  ho_loop_verdict_check "$lane" "$lsha" "$worker" || { ho_loop_refuse 65 "$lane" "$HO_LOOP_VWHY"; return; }
  vsnap=$HO_LOOP_VSNAP

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
  # Pristine, ignored files included: a roll back later needs it, and resets nothing otherwise.
  why=$(ho_loop_pristine "$iwt") || { ho_loop_refuse 65 "$lane" "the integration worktree is not clean, ignored files included ($why)"; return; }
  ho_loop_ref "$iwt" "$lsha" >/dev/null || { ho_loop_refuse 65 "$lane" "$lsha is not in the integration repository"; return; }

  # No-op before merging: the lane is already in the branch. Exit 1 is "no"; any other code is a
  # git error, never a "no".
  rc=0; git -C "$iwt" merge-base --is-ancestor "$lsha" "$old" 2>/dev/null || rc=$?
  case $rc in
    0) ho_loop_refuse "$HO_EXIT_NOOP" "$lane" "no-op: $lsha is already in $branch; nothing would change"; return ;;
    1) ;;
    *) ho_loop_refuse "$HO_EXIT_UNCONFIRMED" "$lane" "git cannot tell whether $lsha is already in $branch (git exit $rc)"; return ;;
  esac
  [ "$ho_loop_sig" -eq 0 ] || { ho_loop_refuse 75 "$lane" "the merge was stopped by a signal before it started"; return; }

  mkdir -p "$HO_RUN_DIR/gates"
  if ! git -C "$iwt" merge -q --no-ff --no-edit -m "merge($lane): $lsha into $branch" "$lsha" \
      > "$HO_RUN_DIR/gates/$lane-$lsha.merge.log" 2>&1; then
    ho_loop_undo "$HO_EXIT_UNCONFIRMED" "$lane" "git merge failed (conflict or error, log gates/$lane-$lsha.merge.log)" "$old"; return
  fi

  # H-046: confirm through git, from the branch ref, not from what the merge printed.
  new=$(ho_loop_ref "$iwt" "refs/heads/$branch") || new=""
  if [ -z "$new" ] || [ "$new" = "$old" ] \
      || [ "$(ho_loop_ref "$iwt" HEAD)" != "$new" ] \
      || [ "$(ho_loop_ref "$iwt" "$new^1")" != "$old" ] \
      || [ "$(ho_loop_ref "$iwt" "$new^2")" != "$lsha" ] \
      || ! git -C "$iwt" merge-base --is-ancestor "$lsha" "refs/heads/$branch" 2>/dev/null \
      || ! ho_loop_clean "$iwt"; then
    # Only a commit that is provably this merge (parents old and the lane commit) may be undone;
    # anything else on the branch is left for a person.
    mc=$old
    if [ -n "$new" ] && [ "$(ho_loop_ref "$iwt" "$new^1")" = "$old" ] && [ "$(ho_loop_ref "$iwt" "$new^2")" = "$lsha" ]; then mc=$new; fi
    ho_loop_undo "$HO_EXIT_UNCONFIRMED" "$lane" "git does not confirm the merge of $lsha into $branch" "$mc"; return
  fi
  rc=0; git -C "$iwt" diff --quiet "$old" "$new" 2>/dev/null || rc=$?
  case $rc in
    0) ho_loop_undo "$HO_EXIT_NOOP" "$lane" "no-op: the merge of $lsha changed no file in $branch" "$new"; return ;;
    1) ;;
    *) ho_loop_undo "$HO_EXIT_UNCONFIRMED" "$lane" "git cannot compare $old with $new (git exit $rc), so the merge is not confirmed" "$new"; return ;;
  esac
  [ "$ho_loop_sig" -eq 0 ] || { ho_loop_undo 75 "$lane" "the merge was stopped by a signal" "$new"; return; }

  # The gate re-runs on the merged tree, in a throwaway detached worktree, so whatever the
  # gate writes never dirties the integration worktree (field note C1). It runs in its own
  # process group, so a signal stops it and every child it started (by exact group ID).
  log="$HO_RUN_DIR/gates/$lane-$lsha.log"
  if ! { gw=$(mktemp -d "${TMPDIR:-/tmp}/ho-gate.XXXXXX") && rmdir "$gw" \
      && git -C "$iwt" worktree add -q --detach "$gw" "$new" >/dev/null 2>&1; }; then
    ho_loop_undo "$HO_EXIT_UNCONFIRMED" "$lane" "cannot create a worktree to run the gate on the merged tree" "$new"; return
  fi
  # A signal that came while the worktree was made is acted on now, before the gate starts.
  if [ "$ho_loop_sig" -ne 0 ]; then
    git -C "$iwt" worktree remove --force "$gw" >/dev/null 2>&1 || rm -rf "$gw"
    git -C "$iwt" worktree prune >/dev/null 2>&1 || true
    ho_loop_undo 75 "$lane" "the merge was stopped by a signal before the gate started" "$new"; return
  fi
  ho_group_start /bin/bash -c 'cd "$1" && exec /bin/bash -c "$2"' ho-gate "$gw" "$gate" < /dev/null > "$log" 2>&1
  gpid=$HO_GROUP_PID
  while :; do
    grc=0; wait "$gpid" || grc=$?
    kill -0 "$gpid" 2>/dev/null || break
    # wait was cut short by a signal while the gate still runs.
    [ "$ho_loop_sig" -eq 0 ] || { ho_group_stop "$gpid"; grc=143; break; }
  done
  git -C "$iwt" worktree remove --force "$gw" >/dev/null 2>&1 || rm -rf "$gw"
  git -C "$iwt" worktree prune >/dev/null 2>&1 || true
  [ "$ho_loop_sig" -eq 0 ] || { ho_loop_undo 75 "$lane" "the merge was stopped by a signal while the gate ran" "$new"; return; }
  if [ "$grc" -ne 0 ]; then
    ho_loop_undo "$HO_EXIT_GATE" "$lane" "the gate failed on the merged tree (exit $grc, log $log)" "$new"; return
  fi
  # Tip check after: nothing moved the branch while the gate ran.
  if [ "$(ho_loop_ref "$iwt" "refs/heads/$branch")" != "$new" ] || ! ho_loop_pristine "$iwt" >/dev/null; then
    ho_loop_refuse "$HO_EXIT_UNCONFIRMED" "$lane" "$branch moved or got dirty while the gate ran; the merge is not confirmed and the branch is left for a person"; return
  fi
  # H-055 again, under the merge lock after the gate: the verdict is the same one, still passed.
  if ! ho_loop_verdict_check "$lane" "$lsha" "$worker" || [ "$HO_LOOP_VSNAP" != "$vsnap" ]; then
    ho_loop_undo 65 "$lane" "the verdict for $lsha changed while the gate ran${HO_LOOP_VWHY:+ ($HO_LOOP_VWHY)}" "$new"; return
  fi
  [ "$ho_loop_sig" -eq 0 ] || { ho_loop_undo 75 "$lane" "the merge was stopped by a signal" "$new"; return; }

  # Confirm and record. Ledger line first: if the tip write then fails, the next merge refuses
  # on the tip check. From here on a signal no longer undoes the merge: TERM, INT and HUP are
  # ignored, also when they go to the whole process group (a closed terminal). The ledger line
  # is written by a fresh shell that starts with them ignored, so the ledger code cannot set
  # its own traps for them; the tip write runs here with them ignored. The merge is then
  # complete, so a signal that came meanwhile changes nothing and the result is reported.
  trap '' TERM INT HUP
  /bin/bash -c 'set -euo pipefail; HO_ROOT=$1; export HO_ROOT
    for l in common files config run; do . "$HO_ROOT/lib/$l.sh"; done
    ho_run_open "$2"; shift 2; ho_ledger_append "$@"' ho-ledger "$HO_ROOT" "$HO_RUN_DIR" \
    merge-confirmed lane "$lane" sha "$lsha" branch "$branch" base "$old" tip "$new" || return 1
  jq --arg tip "$new" '.tip = $tip' "$ij" | ho_atomic_write "$ij" || return 1
  printf 'merged lane %s (%s) into %s at %s\n' "$lane" "$lsha" "$branch" "$new"
}

# ho_loop_lock_old <path>: the path exists and was last changed more than one minute ago.
ho_loop_lock_old() { [ -n "$(find "$1" -maxdepth 0 -mmin +1 2>/dev/null)" ]; }

# ho_loop_lock_take <lock> <me>: one merge at a time per run (its own lock, not the ledger
# lock). A lock whose holder is dead is taken over in place, under <lock>/takeover, and is never
# removed by a waiter: so a waiter can never delete a lock that another waiter has just made.
# A lock with no PID (holder killed between mkdir and writing it) counts as dead after a minute.
ho_loop_lock_take() {
  local lock=$1 me=$2 n=0 pid stale
  until mkdir "$lock" 2>/dev/null; do
    [ "$ho_loop_sig" -eq 0 ] || { ho_loop_err "stopped by a signal while waiting for the merge lock"; return 75; }
    pid=$(cat "$lock/pid" 2>/dev/null || true)
    stale=0
    if [ -n "$pid" ]; then kill -0 "$pid" 2>/dev/null || stale=1; else ho_loop_lock_old "$lock" && stale=1; fi
    if [ "$stale" -eq 1 ]; then
      if mkdir "$lock/takeover" 2>/dev/null; then
        HO_LOOP_TAKEOVER=1
        # Under the takeover folder no other waiter changes the PID file: check it again, then
        # write ours. (The age of a lock with no PID was checked above; the takeover folder
        # itself changes the lock folder's time.)
        if [ "$(cat "$lock/pid" 2>/dev/null || true)" = "$pid" ] \
            && { [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; } \
            && printf '%s\n' "$me" > "$lock/pid.$me" && mv -f "$lock/pid.$me" "$lock/pid"; then
          rmdir "$lock/takeover" 2>/dev/null || true
          HO_LOOP_TAKEOVER=0
          return 0
        fi
        rm -f "$lock/pid.$me"
        rmdir "$lock/takeover" 2>/dev/null || true
        HO_LOOP_TAKEOVER=0
        continue
      fi
      # A waiter that died while taking over leaves an empty takeover folder; after a minute it goes.
      if ho_loop_lock_old "$lock/takeover"; then rmdir "$lock/takeover" 2>/dev/null || true; continue; fi
    fi
    n=$((n + 1))
    [ "$n" -lt 1800 ] || { ho_loop_err "another merge of run $HO_RUN_ID holds $lock (holder ${pid:-unknown})"; return 75; }
    sleep 0.1
  done
  printf '%s\n' "$me" > "$lock/pid"
}

# The merge runs in a background subshell under the lock, so its traps stay local and the
# caller can wait for it. A TERM, INT or HUP to the caller is passed on to that exact subshell,
# which stops the gate, rolls back as far as it safely can, releases its lock and exits 75; the
# caller then returns that code. So a killed caller never leaves a merge running behind it.
ho_loop_merge() {
  local lane=${1-} mpid rc
  [ $# -eq 1 ] || { ho_loop_usage; return 64; }
  ho_loop_lane_ok "$lane" || return 65
  # Armed before the fork, so a signal that comes before the PID is known is passed on too.
  mpid=""
  ho_loop_caller_sig=0
  trap 'ho_loop_caller_sig=1; if [ -n "$mpid" ]; then kill -TERM "$mpid" 2>/dev/null || true; fi' TERM INT HUP
  (
    HO_LOOP_LOCK="$HO_RUN_DIR/merge.lock"
    HO_LOOP_TAKEOVER=0
    ho_loop_sig=0
    ho_loop_rc=70
    trap 'ho_loop_sig=1' TERM INT HUP
    # This subshell's own PID (bash 3.2 has no BASHPID): exec keeps the PID of the substitution
    # child, whose parent is this subshell.
    me=$(exec sh -c 'echo "$PPID"')
    held=0
    # The code stays 70 until the merge step returns: a step that ends with exit (a failed
    # ledger write) must never leave through this trap as 0. Only our own lock is released.
    trap 'if [ "$HO_LOOP_TAKEOVER" = 1 ]; then rmdir "$HO_LOOP_LOCK/takeover" 2>/dev/null || true; fi
          if [ "$held" = 1 ] && [ "$(cat "$HO_LOOP_LOCK/pid" 2>/dev/null || true)" = "$me" ]; then rm -rf "$HO_LOOP_LOCK"; fi
          exit "$ho_loop_rc"' EXIT
    if ho_loop_lock_take "$HO_LOOP_LOCK" "$me"; then held=1; else ho_loop_rc=$?; exit "$ho_loop_rc"; fi
    if ho_loop_merge_locked "$lane"; then ho_loop_rc=0; else ho_loop_rc=$?; fi
    exit "$ho_loop_rc"
  ) &
  mpid=$!
  [ "$ho_loop_caller_sig" -eq 0 ] || kill -TERM "$mpid" 2>/dev/null || true
  while :; do
    rc=0; wait "$mpid" || rc=$?
    kill -0 "$mpid" 2>/dev/null || break
  done
  trap - TERM INT HUP
  return "$rc"
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
  ready <lane> --worktree W [--ticket ID]      the lane's tip must be a finalize(<lane>): commit
                                               on a clean tree; prints the verdict record path;
                                               the ticket lets a soft:ticket stop merge the lane
  verdict <lane> --sha S                       from inside the validator's session: record its
                                               verdict for commit S (text on stdin)
  merge <lane>                                 merge only on a "passed" verdict of the validator,
                                               clean trees and checked tips; confirmed through
                                               git; gate re-run
  status                                       the integration tip and the confirmed merges
exit: 64 usage, 65 refused, 69 no-op, 70 not confirmed or left for a person, 72 gate failed,
      75 run stopped, merge stopped by a signal or merge lock held by another merge,
      78 config error
USAGE
}

ho_loop_main() {
  [ $# -ge 2 ] || { ho_loop_usage; exit 64; }
  ho_run_open "$1"
  # The run's config (the autonomy profile, the gate choice) comes from the project the run
  # belongs to, never the caller's (H-036).
  ho_session_bind_project || exit $?
  local verb=$2 rc=0
  shift 2
  case $verb in
    integration) ho_loop_integration "$@" || rc=$? ;;
    ready) ho_loop_ready "$@" || rc=$? ;;
    verdict) ho_loop_verdict "$@" || rc=$? ;;
    merge) ho_loop_merge "$@" || rc=$? ;;
    status) ho_loop_status || rc=$? ;;
    *) ho_loop_usage; rc=64 ;;
  esac
  exit "$rc"
}
