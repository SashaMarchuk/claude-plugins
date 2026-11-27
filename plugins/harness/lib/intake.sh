# shellcheck shell=bash
# Intake: harness intake <run-dir> interval|tick|poll (tasks.md 12.1, pickup part).
# H-002 only the ready label puts a ticket into work; H-003 a ticket labelled during a live run
# is taken on the next poll; H-004 and D4 the interval: one key, default 60 s, minimum 30, a
# back-off up to 15 minutes on tracker errors, and a script polls, not a model. H-008, H-009,
# H-011 the write-access check; H-012, H-013 the readiness check at every pickup (D6, D8).
#
# Order at pickup (D2): the write-access check, then the claim and its comment, then the
# readiness check.
#   1. The trigger author is the actor of the newest "labeled" event for the ready label.
#      Write, maintain or admin access passes; anything else, an unknown person, a login of an
#      unexpected shape or a failed query is read-only (H-009), and the ticket moves to
#      needs-review with one status comment (H-011, H-026, D5). A configured target repository
#      that the ticket text (title or body) names needs the same access (D37-INTAKE-9); a text
#      that cannot be read means no claim. A bot is judged by its
#      own access, with no allow-list (H-008 interim rule until OPEN-INTAKE-1 is answered).
#   2. Claim: ready -> in-progress, then one "picked up" comment.
#   3. Readiness: the main runtime, run without a terminal and read-only from its runtime
#      profile, judges the fenced ticket text against the required content (tickets.required_content,
#      default D6). Its verdict goes to the run ledger at every pickup. ready -> "start <id>" for
#      the orchestrator; not ready -> numbered questions on the ticket and blocked (H-032; the
#      configurable reaction of H-016 belongs to #51); no readable verdict -> needs-review.
#
# Unblock (H-031, OPEN-10 decided under D37): a ready label on a blocked ticket is the unblock
# command. A writer's ready label that is newer than the newest blocked label returns the ticket
# to ready, and pickup goes on. Anything else removes the ready label; the ticket stays blocked.
#
# The tick also closes every session that asked a question (H-032): "tickets ask" records it in
# the ledger from inside the session, and the tick closes the session gracefully from outside.
#
#   <run>/intake/poll.json   {"errors": n}; its modification time is the time of the last poll
#
# Settings: tickets.poll_seconds, tickets.required_content, tickets.target_repos,
# tickets.readiness_timeout_seconds. No command is read from any config: the judge's command
# line comes from the runtime profile, which a project cannot add (D37-FLOW-8).
# Exit codes: 64 usage, 69 the tracker could not be read, 75 the run is stopped, 78 bad settings.
# Requires lib/tickets.sh, lib/run.sh, lib/config.sh, lib/common.sh, lib/sessions.sh, lib/slots.sh.

HO_IN_DEFAULT_POLL=60
HO_IN_MIN_POLL=30
HO_IN_MAX_WAIT=900

ho_in_err() { printf 'harness intake: %s\n' "$*" >&2; }

# ho_in_cfg_json <jq-path>: the compact JSON value (project, then user), or null.
ho_in_cfg_json() {
  local files f v
  files=$(ho_config_files) || exit $?
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    v=$(jq -c "$1" "$f" 2>/dev/null) || { ho_in_err "cannot read $1 from config $f"; exit 78; }
    [ "$v" = null ] && continue
    printf '%s\n' "$v"
    return 0
  done <<EOF_FILES
$files
EOF_FILES
  echo null
}

# ho_in_seconds <key> <default> <min> <max>: a whole JSON number within bounds, or exit 78.
ho_in_seconds() {
  local v
  v=$(ho_in_cfg_json ".tickets.$1")
  [ "$v" = null ] && { printf '%s\n' "$2"; return 0; }
  case $v in
    '' | *[!0-9]* | 0[0-9]*) ;;
    *) if [ "$v" -ge "$3" ] && [ "$v" -le "$4" ]; then printf '%s\n' "$v"; return 0; fi ;;
  esac
  ho_in_err "tickets.$1 must be a whole number of seconds, at least $3 and at most $4, not $v"
  exit 78
}
ho_in_interval() { ho_in_seconds poll_seconds "$HO_IN_DEFAULT_POLL" "$HO_IN_MIN_POLL" 86400; }

# ho_in_required: the required content, one item per line (H-013; default D6).
ho_in_required() {
  local v
  v=$(ho_in_cfg_json '.tickets.required_content')
  [ "$v" = null ] && v='["outcome", "done-check", "scope"]'
  printf '%s' "$v" | jq -er 'select(type == "array" and length > 0 and length <= 20
      and all(.[]; type == "string" and length > 0 and length <= 200 and (test("[[:cntrl:]]") | not)))
    | .[]' 2>/dev/null || { ho_in_err "tickets.required_content must be a list of 1 to 20 one-line texts"; exit 78; }
}
# ho_in_targets: the configured target repositories, one per line (D37-INTAKE-9).
ho_in_targets() {
  local v
  v=$(ho_in_cfg_json '.tickets.target_repos')
  [ "$v" = null ] && return 0
  printf '%s' "$v" | jq -er 'select(type == "array" and all(.[]; type == "string"
      and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"))) | .[]' 2>/dev/null ||
    { [ "$v" = '[]' ] && return 0; ho_in_err "tickets.target_repos must be a list of owner/name texts"; exit 78; }
}

# ---- poll timing (D4) ----------------------------------------------------------------------
ho_in_state() { printf '%s/intake/poll.json\n' "$HO_RUN_DIR"; }
ho_in_errors() {
  local n
  n=$(jq -r '.errors // 0' "$(ho_in_state)" 2>/dev/null) || n=0
  case $n in '' | *[!0-9]*) n=0 ;; esac
  printf '%s\n' "$n"
}
# ho_in_wait <interval> <errors>: the interval, doubled per tracker error, at most 15 minutes
# (or the interval itself when it is longer).
ho_in_wait() {
  local w=$1 i=0 cap=$HO_IN_MAX_WAIT
  [ "$1" -gt "$cap" ] && cap=$1
  while [ "$i" -lt "$2" ] && [ "$w" -lt "$cap" ]; do w=$((w * 2)); i=$((i + 1)); done
  [ "$w" -gt "$cap" ] && w=$cap
  printf '%s\n' "$w"
}
ho_in_record() { # <errors>: write the poll record; its time is now
  mkdir -p "$HO_RUN_DIR/intake" || return 1
  jq -cn --argjson e "$1" '{errors: $e}' | ho_atomic_write "$(ho_in_state)"
}

# ---- readiness judge -------------------------------------------------------------------------
# ho_in_judge <id> <out-questions-file>: sets HO_IN_VERDICT to ready, not-ready or unknown.
ho_in_judge() {
  local id=$1 qf=$2 prof timeout sid tmpl prompt out err ticket rc=0 i=0 verdict
  local -a argv
  HO_IN_VERDICT=unknown
  : > "$qf"
  prof=$(ho_runtime_profile) || return 0
  if ! jq -e '(.modes | index("noninteractive")) != null and (.sandbox["read-only"] | type == "array")' "$prof" >/dev/null 2>&1; then
    ho_in_err "runtime profile $prof cannot run read-only without a terminal; the readiness check has no verdict"
    return 0
  fi
  timeout=$(ho_in_seconds readiness_timeout_seconds 300 10 1800) || return 0
  sid=$(ho_session_new_id)
  tmpl="$HO_ROOT/templates/readiness-prompt.md"
  ticket=$(ho_tickets show "$id") || { ho_in_err "cannot read ticket $id for the readiness check"; return 0; }
  prompt=$(
    while IFS= read -r line || [ -n "$line" ]; do
      case $line in
        (@REQUIRED@) ho_in_required | sed 's/^/- /' ;;
        (@TICKET@) printf '%s\n' "$ticket" ;;
        (*) printf '%s\n' "$line" ;;
      esac
    done < "$tmpl"
  )
  argv=()
  while IFS= read -r -d '' a; do argv+=("$a"); done < <(jq -j --arg sid "$sid" --arg p "$prompt" '
    [.command] + (.noninteractive.argv | map(gsub("\\{session_id\\}"; $sid)))
    + .sandbox["read-only"] + (.noninteractive.prompt | map(if . == "{prompt}" then $p else . end))
    | .[] | ., "\u0000"' "$prof")
  [ "${#argv[@]}" -gt 1 ] || { ho_in_err "runtime profile $prof gives no command line"; return 0; }
  out=$(mktemp "${TMPDIR:-/tmp}/ho-judge.XXXXXX") || return 0
  err=$(mktemp "${TMPDIR:-/tmp}/ho-judge-err.XXXXXX") || { rm -f "$out"; return 0; }
  # The judge runs in the project, without a terminal, and is stopped by its exact process
  # group when it runs past the limit.
  (cd "$HO_PROJECT_DIR" && ho_group_start "${argv[@]}" < /dev/null > "$out" 2> "$err"
    pid=$HO_GROUP_PID
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt $((timeout * 5)) ]; do sleep 0.2; i=$((i + 1)); done
    if kill -0 "$pid" 2>/dev/null; then ho_group_stop "$pid"; exit 124; fi
    wait "$pid") || rc=$?
  if [ "$rc" -eq 0 ]; then
    # The verdict is the last output line that is a whole JSON object of the right shape.
    verdict=$(LC_ALL=C tr -d '\r' < "$out" | jq -cR 'fromjson? | select(type == "object"
        and (.ready | type) == "boolean" and (.questions | type) == "array"
        and all(.questions[]; type == "string"))' 2>/dev/null | tail -n 1)
    if [ -n "$verdict" ]; then
      printf '%s' "$verdict" | jq -r '.questions[] | select(test("\\S"))' > "$qf"
      if [ "$(printf '%s' "$verdict" | jq -r .ready)" = true ]; then
        # Ready only with no open question for a human (H-012).
        if [ -s "$qf" ]; then HO_IN_VERDICT=not-ready; else HO_IN_VERDICT=ready; fi
      elif [ -s "$qf" ]; then
        HO_IN_VERDICT=not-ready
      fi
    fi
  else
    ho_in_err "the readiness check for ticket $id ended with exit $rc"
  fi
  rm -f "$out" "$err"
}

# ---- one pickup ------------------------------------------------------------------------------
HO_IN_NEXT_STEP="A person with write access should check the ticket and set the ready label again."

# ho_in_review <id> <from> <reason>: -> needs-review with one status comment.
ho_in_review() {
  ho_tk_gh_set_state "$1" needs-review || return 1
  ho_tk_status_comment "$1" orchestrator "$2" needs-review "$3" "$HO_IN_NEXT_STEP" || return 1
}

# ho_in_pickup <id>: print one result line. Returns 0 only when the ticket starts. A tracker
# step that fails is never silent: it prints "error <id>" and adds a pickup-error ledger line.
ho_in_pickup() {
  local rc=0
  HO_IN_STEP=access
  ho_in_pickup_steps "$1" || rc=$?
  case $rc in
    0) return 0 ;;
    1) return 1 ;;
  esac
  ho_ledger_append pickup-error ticket "$1" step "${HO_IN_STEP:-unknown}"
  echo "error $1"
  return 1
}

# ho_in_pickup_steps <id>: returns 0 start, 1 handled (not started), 2 a step failed.
ho_in_pickup_steps() {
  local id=$1 state events ready blocked login="" ridx=-1 bidx=-1 repo body="" raw targets qf
  if ho_tk_gh; then
    state=$(ho_tk_gh_state "$id") || { ho_in_err "cannot read the labels of #$id"; return 2; }
    if events=$(ho_tk_gh_events "$id"); then
      ready=$(ho_tk_last_labeled "$events" "$HO_TK_PREFIX:ready")
      blocked=$(ho_tk_last_labeled "$events" "$HO_TK_PREFIX:blocked")
      [ -z "$ready" ] || { ridx=${ready%% *}; login=${ready#* }; }
      [ -z "$blocked" ] || bidx=${blocked%% *}
    fi
    # A login of an unexpected shape is no login: read-only, and it never reaches a path or the ledger.
    ho_tk_login_ok "$login" || login=""
  else
    # Local tickets: whoever can write the ticket folder can write the repository.
    state=ready login=local
  fi

  # A ready label on a ticket that is already in progress or done is no new pickup (D2: one state
  # label at a time). The ticket keeps its state, the stray ready label goes, and one ledger
  # line records it; the next tick no longer sees the ticket. needs-review is not here: a
  # writer's ready label on it is the approval (H-011).
  local cur
  for cur in in-progress done; do
    case " $state " in *" $cur "*)
      ho_tk_gh_set_state "$id" "$cur" || return 2
      ho_ledger_append pickup-skipped ticket "$id" state "$cur" by "${login:-unknown}"
      echo "kept-$cur $id"
      return 1 ;;
    esac
  done

  # Unblock (H-031): the ready label on a blocked ticket.
  case " $state " in *" blocked "*)
    if [ -n "$login" ] && [ "$ridx" -gt "$bidx" ] && [ "$(ho_tk_access "$login")" = writer ]; then
      ho_tk_gh_set_state "$id" ready || return 2
      ho_tk_status_comment "$id" orchestrator blocked ready "a person with write access set the ready label" \
        "The harness checks the ticket's readiness again now." || return 2
      ho_ledger_append unblock ticket "$id" by "$login"
      echo "unblocked $id"
    else
      ho_tk_gh_set_state "$id" blocked || return 2
      printf 'Reason: the person who set the ready label has no confirmed write access, or the label is older than the block.\nNext: Only a person with write access can unblock the ticket, by setting the ready label.\n' |
        ho_tk_post "$id" orchestrator status "ready label removed, still blocked" - from blocked to blocked || return 2
      ho_ledger_append unblock-refused ticket "$id" by "${login:-unknown}"
      echo "kept-blocked $id"
      return 1
    fi ;;
  esac

  # 1. Write access of the trigger author, on the ticket repository and every named target.
  if ho_tk_gh; then
    if [ -z "$login" ] || [ "$(ho_tk_access "$login")" != writer ]; then
      ho_in_review "$id" ready "the person who set the ready label has no confirmed write access to $HO_TK_REPO" || return 2
      ho_ledger_append intake ticket "$id" verdict needs-review by "${login:-unknown}" repo "$HO_TK_REPO"
      echo "needs-review $id"
      return 1
    fi
    # The ticket text (title and body) is read only when another target repository is configured.
    # A failed read fails closed: no claim, the ticket stays ready for the next poll.
    targets=$(ho_in_targets | grep -vxF -- "$HO_TK_REPO" || true)
    if [ -n "$targets" ]; then
      HO_IN_STEP=target-repos
      raw=$(gh issue view "$id" --repo "$HO_TK_REPO" --json title,body 2>/dev/null) || { ho_in_err "cannot read the text of #$id to check its target repositories"; return 2; }
      body=$(printf '%s' "$raw" | jq -er '"\(.title // "")\n\(.body // "")"' 2>/dev/null) || { ho_in_err "cannot read the text of #$id to check its target repositories"; return 2; }
    fi
    while IFS= read -r repo; do
      [ -n "$repo" ] || continue
      printf '%s\n' "$body" | LC_ALL=C grep -Fqi -- "$repo" || continue
      if [ "$(ho_tk_access "$login" "$repo")" != writer ]; then
        ho_in_review "$id" ready "the person who set the ready label has no confirmed write access to $repo, which the ticket names" || return 2
        ho_ledger_append intake ticket "$id" verdict needs-review by "$login" repo "$repo"
        echo "needs-review $id"
        return 1
      fi
    done <<EOF_REPOS
$targets
EOF_REPOS
  fi

  # 2. Claim and comment.
  HO_IN_STEP=claim
  if ho_tk_gh; then
    ho_tk_gh_set_state "$id" in-progress --add-assignee "@me" || return 2
  else
    ho_tk_locked ho_tk_l_set_state_locked "$id" in-progress ready || return 2
  fi
  HO_IN_STEP=pickup-comment
  printf 'The harness took this ticket and checks its readiness now.\n' |
    ho_tk_post "$id" orchestrator pickup "picked up" - from ready to in-progress || return 2
  ho_ledger_append pickup ticket "$id" by "$login"

  # 3. Readiness check, at every pickup (H-012).
  HO_IN_STEP=readiness
  qf=$(mktemp "${TMPDIR:-/tmp}/ho-questions.XXXXXX") || return 2
  ho_in_judge "$id" "$qf"
  ho_ledger_append readiness ticket "$id" verdict "$HO_IN_VERDICT" questions "$(grep -c . "$qf" || true)"
  case $HO_IN_VERDICT in
    ready) rm -f "$qf"; echo "start $id"; return 0 ;;
    not-ready)
      ho_tk_ask "$id" "$qf" orchestrator || { rm -f "$qf"; return 2; }
      rm -f "$qf"
      echo "blocked $id" ;;
    *)
      rm -f "$qf"
      if ho_tk_gh; then
        ho_in_review "$id" in-progress "the readiness check gave no readable verdict" || return 2
      else
        ho_tk_locked ho_tk_l_set_state_locked "$id" needs-review || return 2
      fi
      echo "needs-review $id" ;;
  esac
  return 1
}

# ho_in_close_asked: close every session that asked a question and is not closed yet (H-032).
ho_in_close_asked() {
  local s st
  # Only a session whose newest question has no later question-closed line: a session relaunched
  # under the same name after the answer (D14) is not closed again.
  ho_ledger_events | jq -rn 'reduce (inputs | select(.kind == "question" or .kind == "question-closed")
      | select((.session | type) == "string")) as $e ({}; .[$e.session] = $e.kind)
    | to_entries[] | select(.value == "question") | .key' |
    while IFS= read -r s; do
      ho_session_name_ok "$s" 2>/dev/null || continue
      [ -f "$HO_RUN_DIR/sessions/$s.json" ] || continue
      st=$(jq -r '.status // ""' "$HO_RUN_DIR/sessions/$s.json" 2>/dev/null) || continue
      if [ "$st" = closed ] || ho_session_close "$s" >/dev/null 2>&1; then
        ho_ledger_append question-closed session "$s"
        echo "closed $s"
      fi
    done
}

# ho_in_free_workers: free worker slots of this run.
ho_in_free_workers() {
  local limit used
  limit=$(ho_slot_limit worker)
  used=$(ho_slot_count "$HO_RUN_DIR/slots/worker")
  [ "$used" -lt "$limit" ] && echo $((limit - used)) || echo 0
}

# ---- tick and poll ---------------------------------------------------------------------------
ho_in_tick() {
  local max="" interval wait age mtime ids id free started=0 rc=0
  while [ $# -gt 0 ]; do
    case $1 in
      --max) [ $# -ge 2 ] && case $2 in '' | *[!0-9]*) false ;; esac || { ho_in_usage; return 64; }; max=$((10#$2)); shift 2 ;;
      *) ho_in_usage; return 64 ;;
    esac
  done
  # Every setting is checked before anything else, so a bad one stops the tick (exit 78).
  interval=$(ho_in_interval) || return
  ho_in_required >/dev/null || return
  ho_in_targets >/dev/null || return
  ho_in_seconds readiness_timeout_seconds 300 10 1800 >/dev/null || return
  ho_tk_settings || return
  ho_stopped || rc=$?
  if [ "$rc" -ne 1 ]; then echo stopped; return "$HO_EXIT_STOPPED"; fi
  if [ -f "$(ho_in_state)" ]; then
    wait=$(ho_in_wait "$interval" "$(ho_in_errors)")
    mtime=$(ho_tk_lock_mtime "$(ho_in_state)")
    age=$(( $(date +%s) - mtime ))
    if [ "$age" -lt "$wait" ]; then echo "not-due $((wait - age))"; return 0; fi
  fi
  ho_in_close_asked
  if ! ids=$(ho_tickets ids ready 2>/dev/null); then
    ho_in_record $(( $(ho_in_errors) + 1 )) || return 1
    ho_ledger_append poll-error errors "$(ho_in_errors)"
    echo tracker-error
    return 69
  fi
  ho_in_record 0 || return 1
  free=$(ho_in_free_workers)
  [ -n "$max" ] && [ "$max" -lt "$free" ] && free=$max
  for id in $ids; do
    [ "$started" -lt "$free" ] || break
    if ho_in_pickup "$id"; then started=$((started + 1)); fi
  done
  return 0
}

ho_in_poll() {
  local rc out
  while :; do
    rc=0
    out=$(ho_in_tick "$@") || rc=$?
    printf '%s\n' "$out" | grep -v -e '^not-due ' -e '^$' || true
    case $rc in 64 | 75 | 78) return "$rc" ;; esac
    # Wake every second, so a stop is seen at once; the tick itself decides when to poll.
    sleep 1
  done
}

ho_in_usage() {
  cat >&2 <<'USAGE'
usage: harness intake <run-dir> <verb>
  interval [--next]   the poll interval in seconds (tickets.poll_seconds); --next: the wait
                      before the next poll, after the back-off for tracker errors
  tick [--max N]      one poll when it is due: close sessions that asked a question, then take
                      ready tickets up to the free worker slots (and N). Prints one line each:
                      start|blocked|needs-review|unblocked|kept-blocked|kept-in-progress|
                      kept-done|error <id>, closed <session>,
                      not-due <seconds>, tracker-error, stopped
  poll [--max N]      tick until the run is stopped
USAGE
}

ho_intake_main() {
  [ $# -ge 2 ] || { ho_in_usage; exit 64; }
  ho_run_open "$1"
  local verb=$2 rc=0
  shift 2
  ho_session_bind_project || exit $?
  case $verb in
    interval)
      local iv
      iv=$(ho_in_interval) || exit $?
      case ${1-} in
        '') printf '%s\n' "$iv" ;;
        --next) ho_in_wait "$iv" "$(ho_in_errors)" ;;
        *) ho_in_usage; exit 64 ;;
      esac ;;
    tick) ho_in_tick "$@" || rc=$? ;;
    poll) ho_in_interval >/dev/null || exit $?; ho_in_poll "$@" || rc=$? ;;
    *) ho_in_usage; rc=64 ;;
  esac
  exit "$rc"
}
