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
#      that the ticket text (title or body) names needs the same access (D37-INTAKE-9); a ticket
#      that names none needs it on every configured target; a text that cannot be read means no
#      claim. A bot is judged by its
#      own access, with no allow-list (H-008 interim rule until OPEN-INTAKE-1 is answered).
#   2. Claim: ready -> in-progress, then one "picked up" comment.
#   3. Readiness: the main runtime, run without a terminal and with no tools (sandbox.no-tools
#      of its runtime profile), from an empty folder, judges the fenced ticket text against the
#      required content (tickets.required_content, default D6). Its verdict goes to the run ledger at every pickup. ready -> "start <id>" for
#      the orchestrator; not ready -> numbered questions on the ticket and blocked (H-032);
#      no readable verdict -> needs-review. The mode (H-016, D37-INTAKE-5) is
#      tickets.readiness.on_not_ready, else assume under the full profile and ask otherwise:
#      ask turns every gap into a question; assume fills what it can and lists each assumption
#      in one comment before the work starts. A ticket that starts gets the working brief
#      (H-014, D8, D37-INTAKE-4): a "Working brief" comment, or with tickets.normalize "body" a
#      new description, or with "off" nothing.
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
# tickets.readiness_timeout_seconds, tickets.readiness.on_not_ready, tickets.normalize, tickets.changes.mode, tickets.urgent.pause. No command is read from any config: the judge's command
# line comes from the runtime profile, which a project cannot add (D37-FLOW-8).
# Exit codes: 64 usage, 69 the tracker could not be read, 75 the run is stopped or has ended,
# 78 bad settings.
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

# ho_in_mode: the reaction to a ticket that is not ready (H-016, D7, D37-INTAKE-5): ask or assume.
# tickets.readiness.on_not_ready wins when set; otherwise the run's autonomy profile gives the
# default: full assumes, every other profile (or one that cannot be read) asks.
ho_in_mode() {
  local v name
  v=$(ho_in_cfg_json '.tickets.readiness.on_not_ready')
  case $v in
    '"ask"' | '"assume"') v=${v#\"}; printf '%s\n' "${v%\"}"; return 0 ;;
    null) ;;
    *) ho_in_err "tickets.readiness.on_not_ready must be ask or assume, not $v"; exit 78 ;;
  esac
  name=$(ho_au_profile 2>/dev/null | jq -r '.name // empty' 2>/dev/null) || name=""
  if [ "$name" = full ]; then echo assume; else echo ask; fi
}
# ho_in_normalize: where the working brief goes (H-014, D8, D37-INTAKE-4): comment (not set),
# body or off.
ho_in_normalize() {
  local v
  v=$(ho_in_cfg_json '.tickets.normalize')
  case $v in
    null | '"comment"') echo comment ;;
    '"body"') echo body ;;
    '"off"') echo off ;;
    *) ho_in_err "tickets.normalize must be body or off (or unset), not $v"; exit 78 ;;
  esac
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
# The ticket text is untrusted, and the judge's questions are posted to the ticket. So the judge
# gets nothing to read secrets with: it runs with the runtime profile's sandbox.no-tools flags
# (no tools at all), from a new empty folder outside the project, and its questions are cut to
# HO_IN_MAX_Q of at most HO_IN_MAX_QLEN characters; a question holding the home folder path is dropped. A profile without no-tools flags gives no
# verdict, and the ticket goes to needs-review.
HO_IN_MAX_Q=10
HO_IN_MAX_QLEN=300
HO_IN_MAX_BRIEF=6000
# The runtime adds the signed-in account's e-mail address to the judge's context, and an
# injected ticket could ask for it in a question (#110). Every address-shaped word in what the
# judge returns is replaced by a fixed mark before anything is posted; the text itself stays.
HO_IN_JQ_NOADDR='def noaddr: gsub("[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+"; "[address removed]"); '
ho_in_judge() {
  local id=$1 qf=$2 prof timeout sid tmpl prompt out err ticket rc=0 i=0 verdict cwd
  local -a argv
  HO_IN_VERDICT=unknown
  : > "$qf"
  : > "$qf.assumptions"
  : > "$qf.brief"
  prof=$(ho_runtime_profile) || return 0
  if ! jq -e '(.modes | index("noninteractive")) != null
      and (.sandbox["no-tools"] | type == "array" and length > 0 and all(type == "string"))' "$prof" >/dev/null 2>&1; then
    ho_in_err "runtime profile $prof gives no sandbox.no-tools flags, so it cannot judge untrusted ticket text without tools; the readiness check has no verdict"
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
        (@MODE@)
          if [ "$HO_IN_MODE" = assume ]; then
            printf '%s\n' 'Fill every gap you can infer from the text yourself, and list each such assumption in "assumptions", one short line each. Put in "questions" only what a person alone can answer; with no such question the ticket is ready.'
          else
            printf '%s\n' 'Put every gap in "questions": do not fill gaps with assumptions, and leave "assumptions" empty.'
          fi ;;
        (@BRIEF@)
          if [ "$HO_IN_NORM" = off ]; then
            printf '%s\n' 'Leave "brief" empty.'
          else
            printf '%s\n' 'When the ticket is ready, write in "brief" a structured working version of it in Markdown, with the headings Outcome, Scope, Acceptance criteria and Checks. Name the checks you infer from the text when the ticket names none. Keep the meaning of the ticket; add nothing it does not imply.'
          fi ;;
        (@TICKET@) printf '%s\n' "$ticket" ;;
        (*) printf '%s\n' "$line" ;;
      esac
    done < "$tmpl"
  )
  argv=()
  while IFS= read -r -d '' a; do argv+=("$a"); done < <(jq -j --arg sid "$sid" --arg p "$prompt" '
    [.command] + (.noninteractive.argv | map(gsub("\\{session_id\\}"; $sid)))
    + .sandbox["no-tools"] + (.noninteractive.prompt | map(if . == "{prompt}" then $p else . end))
    | .[] | ., "\u0000"' "$prof")
  [ "${#argv[@]}" -gt 1 ] || { ho_in_err "runtime profile $prof gives no command line"; return 0; }
  out=$(mktemp "${TMPDIR:-/tmp}/ho-judge.XXXXXX") || return 0
  err=$(mktemp "${TMPDIR:-/tmp}/ho-judge-err.XXXXXX") || { rm -f "$out"; return 0; }
  cwd=$(mktemp -d "${TMPDIR:-/tmp}/ho-judge-cwd.XXXXXX") || { rm -f "$out" "$err"; return 0; }
  # The judge runs in its own empty folder, without a terminal, and is stopped by its exact
  # process group when it runs past the limit.
  (cd "$cwd" && ho_group_start "${argv[@]}" < /dev/null > "$out" 2> "$err"
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
      # A question that holds the person's home folder path is dropped: it may carry a local path
      # or file content, and it would be posted to the ticket.
      printf '%s' "$verdict" | jq -r --argjson n "$HO_IN_MAX_Q" --argjson l "$HO_IN_MAX_QLEN" --arg home "${HOME:-}" \
        "$HO_IN_JQ_NOADDR"'[.questions[] | gsub("[[:cntrl:]]"; " ") | noaddr | select(test("\\S"))
          | select(($home | length) < 2 or (contains($home) | not))][:$n][] | .[:$l]' > "$qf"
      # Assumptions (assume mode) and the working brief get the same bounds; a brief that holds
      # the home folder path is dropped whole.
      printf '%s' "$verdict" | jq -r --argjson n "$HO_IN_MAX_Q" --argjson l "$HO_IN_MAX_QLEN" --arg home "${HOME:-}" \
        "$HO_IN_JQ_NOADDR"'[(.assumptions // [])[] | select(type == "string") | gsub("[[:cntrl:]]"; " ") | noaddr | select(test("\\S"))
          | select(($home | length) < 2 or (contains($home) | not))][:$n][] | .[:$l]' > "$qf.assumptions"
      printf '%s' "$verdict" | jq -r --argjson l "$HO_IN_MAX_BRIEF" --arg home "${HOME:-}" \
        "$HO_IN_JQ_NOADDR"'.brief | select(type == "string") | explode | map(select(. == 9 or . == 10 or (. >= 32 and . != 127))) | implode
          | noaddr | select(test("\\S")) | select(($home | length) < 2 or (contains($home) | not)) | .[:$l]' > "$qf.brief"
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
  rm -rf "$cwd"
}

# ---- one pickup ------------------------------------------------------------------------------
HO_IN_NEXT_STEP="A person with write access should check the ticket and set the ready label again."

# ho_in_review <id> <from> <reason>: -> needs-review with one status comment.
ho_in_review() {
  ho_tk_set_state "$1" needs-review || return 1
  ho_tk_status_comment "$1" orchestrator "$2" needs-review "$3" "$HO_IN_NEXT_STEP" || return 1
}

# ho_in_pickup <id>: print one result line. Returns 0 only when the ticket starts. A tracker
# step that fails is never silent: it prints "error <id>" and adds a pickup-error ledger line.
# A step that fails after the claim moves the ticket to blocked, so no ticket stays in progress
# without a worker; a writer's ready label unblocks it (H-031). The move changes the label only,
# because the comment may be what failed; a status comment is tried after it. When the move
# fails too, one owner-action line says what a person does.
ho_in_pickup() {
  local rc=0 left=""
  HO_IN_STEP=access HO_IN_CLAIMED=0 HO_IN_CLAIM_SURE=1
  ho_in_pickup_steps "$1" || rc=$?
  case $rc in
    0) return 0 ;;
    1) return 1 ;;
  esac
  if [ "$HO_IN_CLAIMED" = 1 ]; then
    # A claim whose result could not be read may have left the ticket ready or in progress: the
    # words then say "may be" and the comment names no known start state (#110).
    local from=in-progress was="is in progress" how="a tracker step failed after the claim"
    if [ "$HO_IN_CLAIM_SURE" != 1 ]; then
      from=unknown was="may be in progress (or still ready)" how="the claim failed and the ticket's state could not be read after it"
    fi
    if ho_in_set_state "$1" blocked; then
      left=blocked
      printf 'Reason: %s (%s).\nNext: A person with write access checks the ticket and sets the ready label to take it again.\n' "$how" "${HO_IN_STEP:-unknown}" |
        ho_tk_post "$1" orchestrator status "pickup failed, blocked" - from "$from" to blocked >/dev/null 2>&1 || true
    else
      left=$([ "$HO_IN_CLAIM_SURE" = 1 ] && echo in-progress || echo unknown)
      ho_ledger_append owner-action title "ticket $1 $was with no worker" \
        why "$how (${HO_IN_STEP:-unknown}), and the move to blocked failed too" \
        command "harness tickets block $1 <why-file>, or set its blocked label by hand" verify "the ticket carries only the blocked label"
    fi
    ho_ledger_append pickup-error ticket "$1" step "${HO_IN_STEP:-unknown}" state "$left"
  else
    ho_ledger_append pickup-error ticket "$1" step "${HO_IN_STEP:-unknown}"
  fi
  echo "error $1"
  return 1
}
ho_in_set_state() { ho_tk_set_state "$@"; } # <id> <state>: on every backend

# ho_in_pickup_steps <id>: returns 0 start, 1 handled (not started), 2 a step failed.
ho_in_pickup_steps() {
  local id=$1 state events ready blocked login="" ridx=-1 bidx=-1 repo body="" raw targets named qf
  if ho_tk_gh; then
    state=$(ho_tk_gh_state "$id") || { ho_in_err "cannot read the labels of #$id"; return 2; }
    # The listing is a snapshot from the start of the tick. A ready label removed since then (for
    # example during an earlier ticket's readiness check) withdraws the ticket: an old labeled
    # event alone never authorises a claim (H-002).
    case " $state " in *" ready "*) ;; *)
      ho_ledger_append pickup-skipped ticket "$id" state "${state:-none}" reason "no ready label"
      return 1 ;;
    esac
    if events=$(ho_tk_gh_events "$id"); then
      ready=$(ho_tk_last_labeled "$events" "$HO_TK_PREFIX:ready")
      blocked=$(ho_tk_last_labeled "$events" "$HO_TK_PREFIX:blocked")
      [ -z "$ready" ] || { ridx=${ready%% *}; login=${ready#* }; }
      [ -z "$blocked" ] || bidx=${blocked%% *}
    fi
    # A login of an unexpected shape is no login: read-only, and it never reaches a path or the ledger.
    ho_tk_login_ok "$login" || login=""
  elif ho_tk_ad; then
    # A tracker without labels (H-007, D1): the state comes from the mapped status (or the
    # last-resort text line), and the trigger author is the tracker's e-mail for whoever set it,
    # matched to a code host account through the identity map (H-010, D37-INTAKE-8). An unknown
    # author is no login: read-only.
    state=$(ho_tk_ad_state "$id") || { ho_in_err "cannot read ticket $id on the tracker"; return 2; }
    case " $state " in *" ready "*) ;; *)
      ho_ledger_append pickup-skipped ticket "$id" state "${state:-none}" reason "no ready trigger"
      return 1 ;;
    esac
    login=$(ho_tk_ad_trigger_login "$id") || login=""
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
      ho_tk_set_state "$id" "$cur" || return 2
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

  # 1. Write access of the trigger author, on the ticket repository and every named target. On a
  # tracker without labels it is the access on every configured target repository (H-010).
  if ho_tk_ad; then
    if [ -z "$login" ] || [ "$(ho_tk_access_all "$login")" != writer ]; then
      ho_in_review "$id" ready "the person behind the ready trigger is unknown or has no confirmed write access to every target repository" || return 2
      ho_ledger_append intake ticket "$id" verdict needs-review by "${login:-unknown}"
      echo "needs-review $id"
      return 1
    fi
  fi
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
    # The targets the ticket names; a ticket that names none may work in any of them, so the
    # trigger author needs write access on every configured target (D37-INTAKE-9).
    named=$(printf '%s\n' "$targets" | while IFS= read -r repo; do
      [ -n "$repo" ] && printf '%s\n' "$body" | LC_ALL=C grep -Fqi -- "$repo" && printf '%s\n' "$repo"
    done || true)
    [ -n "$named" ] || named=$targets
    while IFS= read -r repo; do
      [ -n "$repo" ] || continue
      if [ "$(ho_tk_access "$login" "$repo")" != writer ]; then
        ho_in_review "$id" ready "the person who set the ready label has no confirmed write access to $repo, a target repository of this ticket" || return 2
        ho_ledger_append intake ticket "$id" verdict needs-review by "$login" repo "$repo"
        echo "needs-review $id"
        return 1
      fi
    done <<EOF_REPOS
$named
EOF_REPOS
  fi

  # 2. Claim and comment.
  HO_IN_STEP=claim
  if ho_tk_gh; then
    if ! ho_tk_gh_set_state "$id" in-progress --add-assignee "@me"; then
      # The edit may have failed half way, with the in-progress label set (D2, H-030). Read the
      # state again: a set label, or a state that cannot be read, counts as claimed, so the
      # ticket is moved to blocked and never sits in progress with no worker.
      local now
      if now=$(ho_tk_gh_state "$id" 2>/dev/null); then
        case " $now " in *" in-progress "*) HO_IN_CLAIMED=1 ;; esac
      else
        HO_IN_CLAIMED=1 HO_IN_CLAIM_SURE=0
      fi
      return 2
    fi
  else
    if ho_tk_ad; then ho_tk_ad_set_state "$id" in-progress || { HO_IN_CLAIMED=1 HO_IN_CLAIM_SURE=0; return 2; }
    else ho_tk_locked ho_tk_l_set_state_locked "$id" in-progress ready || return 2; fi
  fi
  HO_IN_CLAIMED=1 HO_IN_STEP=pickup-comment
  printf 'The harness took this ticket and checks its readiness now.\n' |
    ho_tk_post "$id" orchestrator pickup "picked up" - from ready to in-progress || return 2
  ho_ledger_append pickup ticket "$id" by "$login"

  # 3. Readiness check, at every pickup (H-012), in the mode of H-016 (ask or assume).
  HO_IN_STEP=readiness
  qf=$(mktemp "${TMPDIR:-/tmp}/ho-questions.XXXXXX") || return 2
  ho_in_judge "$id" "$qf"
  ho_ledger_append readiness ticket "$id" verdict "$HO_IN_VERDICT" mode "$HO_IN_MODE" \
    questions "$(grep -c . "$qf" || true)" assumptions "$(grep -c . "$qf.assumptions" || true)"
  case $HO_IN_VERDICT in
    ready)
      # assume: every assumption is listed on the ticket before the work starts (H-016).
      if [ "$HO_IN_MODE" = assume ] && [ -s "$qf.assumptions" ]; then
        HO_IN_STEP=assumptions
        { printf 'The ticket left gaps; the harness filled them with these assumptions:\n\n'
          sed 's/^/- /' "$qf.assumptions"
          printf '\nIf one is wrong, a person with write access says so in a comment.\n'
        } | ho_tk_post "$id" orchestrator assumptions "assumptions" - || { ho_in_rm_q "$qf"; return 2; }
      fi
      HO_IN_STEP=working-brief
      ho_in_brief "$id" "$qf.brief" || { ho_in_rm_q "$qf"; return 2; }
      HO_IN_STEP=watch
      ho_in_watch_init "$id" || { ho_in_rm_q "$qf"; return 2; }
      ho_in_rm_q "$qf"; echo "start $id"; return 0 ;;
    not-ready)
      ho_tk_ask "$id" "$qf" orchestrator || { ho_in_rm_q "$qf"; return 2; }
      ho_in_rm_q "$qf"
      echo "blocked $id" ;;
    *)
      ho_in_rm_q "$qf"
      if ho_tk_gh || ho_tk_ad; then
        ho_in_review "$id" in-progress "the readiness check gave no readable verdict" || return 2
      else
        ho_tk_locked ho_tk_l_set_state_locked "$id" needs-review || return 2
      fi
      echo "needs-review $id" ;;
  esac
  return 1
}

ho_in_rm_q() { rm -f "$1" "$1.assumptions" "$1.brief"; }

# ho_in_brief <id> <brief-file>: the working brief (H-014, D8, D37-INTAKE-4). Not set: a new
# "Working brief" comment, and the description stays as picked up. body: the description is
# replaced by the brief. off: nothing. A judge that wrote no brief leaves one ledger line; it
# never blocks the pickup (D8: structure does not gate).
ho_in_brief() {
  local id=$1 bf=$2
  [ "$HO_IN_NORM" = off ] && return 0
  if [ ! -s "$bf" ]; then
    ho_ledger_append brief-missing ticket "$id"
    return 0
  fi
  case $HO_IN_NORM in
    body) ho_tk_set_body "$id" "$bf" || return 1 ;;
    *) ho_tk_post "$id" orchestrator working-brief "Working brief" "$bf" || return 1 ;;
  esac
  ho_ledger_append working-brief ticket "$id" where "$HO_IN_NORM"
}

# ---- ticket changes through comments (H-019 to H-023, D9) -----------------------------------
# The tick reads new comments on every in-progress ticket this run picked up (GitHub only: local
# tickets have no other authors). State per ticket, set when the work starts:
#   <run>/intake/watch/<id>.json   {seen: <comments read>, body: <digest>, edit_noted: bool}
#   <run>/intake/watch/<id>.body   the description as picked up; "intake text" serves it
#   <run>/notes/<id>/<n>.md        an accepted change, fenced, waiting for the next step boundary
# A harness report (own account, ending in a machine line) is never a change. For every other comment:
#   - an author without confirmed write access: a new linked ticket in needs-review
#     (H-021, D37-INTAKE-2); the running work does not change;
#   - a writer: the first line harness:apply or harness:new-ticket chooses, else
#     tickets.changes.mode (apply by default, new-ticket, ignore; H-022, D37-INTAKE-6). apply
#     after the ticket's lane merged becomes a new linked ticket. An applied change that names a
#     configured target repository needs its author's write access there (D37-FLOW-8 c), else
#     the ticket moves to needs-review. Otherwise it is queued as a note: "state begin" hands
#     it to the worker at the next step boundary (H-023, D37-INTAKE-3), and the orchestrator
#     returns the ticket to its execution step (D37-INTAKE-6).
# A description edit is no change (D37-INTAKE-7): the first one gets one comment asking for the
# change as a comment; later edits get none.
ho_in_changes_mode() {
  local v
  v=$(ho_in_cfg_json '.tickets.changes.mode')
  case $v in
    null | '"apply"') echo apply ;;
    '"new-ticket"') echo new-ticket ;;
    '"ignore"') echo ignore ;;
    *) ho_in_err "tickets.changes.mode must be apply, new-ticket or ignore, not $v"; exit 78 ;;
  esac
}
ho_in_watch_file() { printf '%s/intake/watch/%s.json\n' "$HO_RUN_DIR" "$1"; }
ho_in_digest() { cksum | awk '{ print $1 "-" $2 }'; }
# ho_in_watch_init <id>: every comment so far counts as read; the description as picked up.
ho_in_watch_init() {
  local id=$1 json
  ho_tk_gh || return 0
  json=$(gh issue view "$id" --repo "$HO_TK_REPO" --json body,comments 2>/dev/null) || return 1
  mkdir -p "$HO_RUN_DIR/intake/watch" || return 1
  printf '%s' "$json" | jq -j '.body // ""' | ho_atomic_write "$HO_RUN_DIR/intake/watch/$id.body" || return 1
  jq -cn --argjson n "$(printf '%s' "$json" | jq '.comments | length')" \
    --arg b "$(printf '%s' "$json" | jq -r '.body // ""' | ho_in_digest)" \
    '{seen: $n, body: $b, edit_noted: false}' | ho_atomic_write "$(ho_in_watch_file "$id")"
}
# ho_in_watch_skip <id>: every comment so far counts as read; the saved description and digest
# stay. With no watch file yet, a full init.
ho_in_watch_skip() {
  local wf n
  wf=$(ho_in_watch_file "$1")
  [ -f "$wf" ] || { ho_in_watch_init "$1"; return; }
  n=$(gh issue view "$1" --repo "$HO_TK_REPO" --json comments 2>/dev/null | jq '.comments | length') || return 1
  jq -c --argjson n "$n" '.seen = $n' "$wf" | ho_atomic_write "$wf"
}
# ho_in_merged <id>: the ticket's lane has a merge-confirmed line in this run.
ho_in_merged() {
  local lj lane
  for lj in "$HO_RUN_DIR"/lanes/*.json; do
    [ -f "$lj" ] || continue
    [ "$(jq -r '.ticket // ""' "$lj" 2>/dev/null)" = "$1" ] || continue
    lane=$(jq -r '.lane // ""' "$lj" 2>/dev/null)
    ho_ledger_events | jq -e --arg l "$lane" 'select(.kind == "merge-confirmed" and .lane == $l)' >/dev/null 2>&1 && return 0
  done
  return 1
}
# ho_in_change_ticket <id> <n> <login> <text-file> <state>: a new ticket linked to the comment.
ho_in_change_ticket() {
  local id=$1 n=$2 who=$3 tf=$4 st=$5 bf url new
  bf=$(mktemp "${TMPDIR:-/tmp}/ho-change.XXXXXX") || return 1
  { printf 'A change proposed by %s in a comment on #%s, comment %s.\n\n' "$who" "$id" "$n"
    cat "$tf"; } > "$bf"
  url=$(gh issue create --repo "$HO_TK_REPO" --title "Change to #$id from comment $n" --body-file "$bf" --label "$HO_TK_PREFIX:$st") || { rm -f "$bf"; return 1; }
  rm -f "$bf"
  new=${url##*/}
  case $new in '' | *[!0-9]*) return 1 ;; esac
  printf 'Reason: the change in comment %s became a new ticket, #%s (%s).\nNext: The running work does not change.\n' "$n" "$new" "$st" |
    ho_tk_post "$id" orchestrator change "change became #$new" - || return 1
  HO_IN_NEW=$new
}
ho_in_watch() {
  local id=$1 wf json own seen total k login body first who mode tf note repo named st extra=0
  wf=$(ho_in_watch_file "$id")
  [ -f "$wf" ] || { ho_in_watch_init "$id"; return 0; }
  json=$(gh issue view "$id" --repo "$HO_TK_REPO" --json body,comments 2>/dev/null) || return 1
  seen=$(jq -r '.seen // 0' "$wf" 2>/dev/null) || seen=0
  case $seen in '' | *[!0-9]*) seen=0 ;; esac
  total=$(printf '%s' "$json" | jq '.comments | length')
  own=$(ho_tk_own_login)
  # Without the harness's own account no report can be told apart from a person's: wait.
  [ -n "$own" ] || return 0
  # D37-INTAKE-7: description edits.
  if [ "$(printf '%s' "$json" | jq -r '.body // ""' | ho_in_digest)" != "$(jq -r '.body // ""' "$wf")" ] &&
    [ "$(jq -r '.edit_noted' "$wf")" != true ]; then
    printf 'The harness works from the description as it was picked up, so an edit to it is not taken into the work.\nPlease add the change as a comment on this ticket; a comment from a person with write access reaches the work at its next step.\n' |
      ho_tk_post "$id" orchestrator edit-noted "description edit not taken" - || return 1
    extra=1
    jq -c '.edit_noted = true' "$wf" | ho_atomic_write "$wf" || return 1
    ho_ledger_append change-edit ticket "$id"
  fi
  mode=$HO_IN_CHANGES
  k=$seen
  while [ "$k" -lt "$total" ]; do
    login=$(printf '%s' "$json" | jq -r --argjson k "$k" '.comments[$k].author.login // ""')
    k=$((k + 1))
    # The harness's own reports end in a machine line (D13); a plain comment from the same
    # account is a person's (a one-person setup signs in as the person).
    if [ "$login" = "$own" ] && printf '%s' "$json" | jq -e --argjson k "$((k - 1))" --arg re "$HO_TK_MACHINE_RE" "$HO_TK_JQ_MLINE"'
        (.comments[$k].body // "") | gsub("\r"; "") | split("\n") | map(select(test("\\S"))) | last // "" | mline($re) != null' >/dev/null 2>&1; then
      continue
    fi
    body=$(printf '%s' "$json" | jq -r --argjson k "$((k - 1))" '.comments[$k].body // ""' | LC_ALL=C tr -d '\r')
    first=$(printf '%s\n' "$body" | awk 'NF { print tolower($0); exit }' | tr -d ' \t')
    tf=$(mktemp "${TMPDIR:-/tmp}/ho-change-text.XXXXXX") || return 1
    printf '%s\n' "$body" > "$tf"
    ho_tk_login_ok "$login" || login=unknown
    if [ "$(ho_tk_access "$login")" != writer ]; then
      who=reader st=needs-review
    else
      who=writer st=ready
      case $first in harness:apply) mode=apply ;; harness:new-ticket) mode=new-ticket ;; *) mode=$HO_IN_CHANGES ;; esac
      [ "$mode" = apply ] && ho_in_merged "$id" && mode=new-ticket
      # A writer's new ticket starts ready, labelled by the harness account, so the author's own
      # access on every target the comment names is checked here (D37-FLOW-8 c); a gap makes it
      # start in needs-review instead.
      if [ "$mode" = new-ticket ]; then
        while IFS= read -r repo; do
          [ -n "$repo" ] || continue
          printf '%s\n' "$body" | LC_ALL=C grep -Fqi -- "$repo" || continue
          [ "$(ho_tk_access "$login" "$repo")" = writer ] || { st=needs-review; break; }
        done <<EOF_NT
$(ho_in_targets | grep -vxF -- "$HO_TK_REPO" || true)
EOF_NT
      fi
    fi
    [ "$who" = reader ] && mode=new-ticket
    case $mode in
      ignore)
        ho_ledger_append change ticket "$id" comment "$k" by "$login" result ignored
        echo "change-ignored $id" ;;
      new-ticket)
        ho_in_change_ticket "$id" "$k" "$login" "$tf" "$st" || { rm -f "$tf"; return 1; }
        ho_ledger_append change ticket "$id" comment "$k" by "$login" result "new-ticket" new "$HO_IN_NEW"
        echo "change-ticket $id $HO_IN_NEW" ;;
      apply)
        named=""
        while IFS= read -r repo; do
          [ -n "$repo" ] || continue
          printf '%s\n' "$body" | LC_ALL=C grep -Fqi -- "$repo" || continue
          if [ "$(ho_tk_access "$login" "$repo")" != writer ]; then named=$repo; break; fi
        done <<EOF_REPOS
$(ho_in_targets | grep -vxF -- "$HO_TK_REPO" || true)
EOF_REPOS
        if [ -n "$named" ]; then
          ho_tk_gh_set_state "$id" needs-review || { rm -f "$tf"; return 1; }
          ho_tk_status_comment "$id" orchestrator in-progress needs-review \
            "the change in comment $k names $named, where its author has no confirmed write access; it is not applied" \
            "A person with write access to $named checks the change and sets the ready label again." || { rm -f "$tf"; return 1; }
          ho_ledger_append change ticket "$id" comment "$k" by "$login" result needs-review repo "$named"
          echo "needs-review $id"
          k=$total
        else
          mkdir -p "$HO_RUN_DIR/notes/$id" || { rm -f "$tf"; return 1; }
          note="$HO_RUN_DIR/notes/$id/$k.md"
          { printf 'A change from %s (comment %s) arrived while you worked. Take it into the work from the execution step on.\n\n' "$login" "$k"
            ho_tk_fence "$id" < "$tf"; } | ho_atomic_write "$note" || { rm -f "$tf"; return 1; }
          ho_ledger_append change ticket "$id" comment "$k" by "$login" result applied note "$note"
          echo "change-applied $id"
        fi ;;
    esac
    rm -f "$tf"
  done
  # The harness's own comments posted during this watch are read too.
  jq -c --argjson n "$((total + extra))" '.seen = $n' "$wf" | ho_atomic_write "$wf"
}
# ho_in_watch_all: every in-progress ticket this run picked up.
ho_in_watch_all() {
  local ids id
  ho_tk_gh || return 0
  ids=$(ho_tickets ids in-progress 2>/dev/null) || return 0
  for id in $ids; do
    ho_ledger_events | jq -e --arg t "$id" 'select(.kind == "pickup" and .ticket == $t)' >/dev/null 2>&1 || continue
    ho_in_watch "$id" || echo "error $id"
  done
}

# ---- answers to the harness's questions (H-033 to H-035, D14, D37-COMMENTS-1 to 3) -----------
# On GitHub, the tick reads the replies after the newest numbered-question comment of every
# blocked or needs-review ticket. Cursor: <run>/intake/answers/<id>.json {seen: n}.
# The author of a reply: the platform login; on the harness's own recorded answer (H-034) its
# author field, or no one when it records an unmapped sender. A harness report (own account,
# machine line, any other event) is no answer.
#   - a writer: the ticket returns to work: in-progress, one status comment, "resume <id>"; the
#     orchestrator resumes the session by ID once or starts a new one (D14), and "tickets resume"
#     checks each step's real result before moving on (D2).
#   - anyone else (no write access, unmapped, or access that cannot be read): the answer is not
#     applied; a blocked ticket moves to needs-review with one status comment ("needs-review
#     <id>"), and a writer's later reply revalidates and resumes it (D37-COMMENTS-3).
ho_in_answers() {
  local id=$1 state=$2 af json own q seen total k login who
  af="$HO_RUN_DIR/intake/answers/$id.json"
  json=$(gh issue view "$id" --repo "$HO_TK_REPO" --json comments 2>/dev/null) || return 1
  own=$(ho_tk_own_login)
  [ -n "$own" ] || return 0
  # The newest own question or status comment decides: a question is open; a status comment is
  # open only when it records a refused answer (cause answer-refused), so an old answer never
  # resumes a ticket that reached needs-review another way. q is its 0-based index.
  q=$(printf '%s' "$json" | jq -r --arg own "$own" --arg re "$HO_TK_MACHINE_RE" "$HO_TK_JQ_MLINE"'
    [.comments | to_entries[] | select(.value.author.login == $own)
      | {k: .key, m: ((.value.body // "") | gsub("\r"; "") | split("\n") | map(select(test("\\S"))) | last // "" | mline($re))}
      | select(.m != null and (.m.event == "question" or .m.event == "status"))] | last
    | select(. != null and (.m.event == "question" or .m.cause == "answer-refused")) | .k')
  [ -n "$q" ] || return 0
  seen=$(jq -r '.seen // 0' "$af" 2>/dev/null) || seen=0
  case $seen in '' | *[!0-9]*) seen=0 ;; esac
  [ "$seen" -gt "$q" ] || seen=$((q + 1))
  total=$(printf '%s' "$json" | jq '.comments | length')
  k=$seen
  while [ "$k" -lt "$total" ]; do
    who=$(printf '%s' "$json" | jq -r --argjson k "$k" --arg own "$own" --arg re "$HO_TK_MACHINE_RE" "$HO_TK_JQ_MLINE"'
      .comments[$k] | (.author.login // "") as $l
      | ((.body // "") | gsub("\r"; "") | split("\n") | map(select(test("\\S"))) | last // "" | mline($re)) as $m
      | if $l == $own and $m != null then
          (if $m.event != "answer" then "-skip" elif ($m.author | type) == "string" then $m.author else "-unmapped" end)
        else $l end')
    k=$((k + 1))
    [ "$who" = -skip ] && continue
    login=$who
    [ "$login" = -unmapped ] || ho_tk_login_ok "$login" || login=-unmapped
    if [ "$login" != -unmapped ] && [ "$(ho_tk_access "$login")" = writer ]; then
      ho_tk_set_state "$id" in-progress || return 1
      ho_tk_status_comment "$id" orchestrator "$state" in-progress "a person with write access ($login) answered the questions" \
        "The work resumes from the first step whose result does not exist yet." || return 1
      ho_ledger_append answer ticket "$id" comment "$k" by "$login" verdict resumed
      mkdir -p "$HO_RUN_DIR/intake/answers" && jq -cn --argjson n "$((total + 1))" '{seen: $n}' | ho_atomic_write "$af" || return 1
      # The answers and the status comment are no ticket change (H-019): the watch reads on from
      # here. The description picked up stays (D37-INTAKE-7): an edit made while the ticket
      # waited still gets its notice at the next watch.
      ho_in_watch_skip "$id" || return 1
      echo "resume $id"
      return 0
    fi
    ho_ledger_append answer ticket "$id" comment "$k" by "${login#-}" verdict not-applied
    if [ "$state" = blocked ]; then
      ho_tk_set_state "$id" needs-review || return 1
      printf 'Reason: %s\nNext: %s\n' \
        "the answer in comment $k comes from a person without confirmed write access (or who cannot be matched to an account), so it is not applied" \
        "A person with write access revalidates it with their own reply on this ticket; that reply resumes the work." |
        ho_tk_post "$id" orchestrator status "blocked -> needs-review" - from blocked to needs-review cause answer-refused || return 1
      state=needs-review total=$((total + 1))
      echo "needs-review $id"
    fi
  done
  mkdir -p "$HO_RUN_DIR/intake/answers" && jq -cn --argjson n "$total" '{seen: $n}' | ho_atomic_write "$af"
}
ho_in_answers_all() {
  local st ids id
  ho_tk_gh || return 0
  for st in blocked needs-review; do
    ids=$(ho_tickets ids "$st" 2>/dev/null) || continue
    for id in $ids; do ho_in_answers "$id" "$st" || echo "error $id"; done
  done
}

# ---- urgent ticket out of turn (H-083, H-084, D3) -------------------------------------------
# The label <prefix>:urgent on a ready ticket, set by a writer (the newest labeled event for it),
# puts the ticket first. A reader's urgent label gives no priority (one urgent-refused ledger
# line). One urgent ticket at a time: while one is in progress or blocked, another urgent ticket
# waits ("urgent-waiting <id>"). With a free worker slot the urgent ticket starts at once
# (urgent-start). With none, the newest lane of this run (its pickup line is the latest) pauses:
#   <run>/pauses/<ticket>.json   {for: <urgent id>, type: step|hard}
# "state begin" refuses its next step (exit 75), so it pauses after its current step (D3 default);
# tickets.urgent.pause "hard" also closes that ticket's sessions at once (H-084). The urgent
# ticket waits for the freed slot; the cap is never exceeded (H-105), because only free slots
# start work. When the urgent ticket is no longer ready, in progress or blocked, its pause is removed
# ("unpause <ticket>").
ho_in_urgent_pause_type() {
  local v
  v=$(ho_in_cfg_json '.tickets.urgent.pause')
  case $v in
    null | '"step"') echo step ;;
    '"hard"') echo hard ;;
    *) ho_in_err "tickets.urgent.pause must be step or hard, not $v"; exit 78 ;;
  esac
}
# ho_in_active_urgent: the urgent ticket of this run that is in progress or blocked, or nothing.
ho_in_active_urgent() {
  local t st
  for t in $(ho_ledger_events | jq -r 'select(.kind == "urgent-start") | .ticket' | awk '!seen[$0]++'); do
    st=$(ho_tk_gh_state "$t" 2>/dev/null) || { echo "$t"; return 0; }
    case " $st " in *" in-progress "* | *" blocked "*) echo "$t"; return 0 ;; esac
  done
}
# ho_in_unpause: let go every pause whose urgent ticket is no longer active.
ho_in_unpause() {
  local f t u st
  for f in "$HO_RUN_DIR"/pauses/*.json; do
    [ -f "$f" ] || continue
    t=${f##*/}; t=${t%.json}
    u=$(jq -r '.for // ""' "$f" 2>/dev/null) || u=""
    # The pause holds while its urgent ticket waits for the slot (ready) or runs (in progress); a
    # state that cannot be read keeps it too. A blocked urgent ticket waits for a person, so the
    # paused lane goes on meanwhile (H-032); the urgent ticket pauses a lane again if it needs one.
    case $u in '' | *[!0-9]*) ;; *)
      st=$(ho_tk_gh_state "$u" 2>/dev/null) || continue
      case " $st " in *" ready "* | *" in-progress "*) continue ;; esac ;;
    esac
    rm -f "$f" || continue
    ho_ledger_append urgent-unpause ticket "$t" for "$u"
    echo "unpause $t"
  done
}
# ho_in_is_urgent <id>: 0 when the ticket carries the urgent label set by a writer.
ho_in_is_urgent() {
  local labels ev last login
  labels=$(ho_tk_gh_labels "$1" 2>/dev/null) || return 1
  printf '%s\n' "$labels" | grep -qxF "$HO_TK_PREFIX:urgent" || return 1
  ev=$(ho_tk_gh_events "$1") || ev='[]'
  last=$(ho_tk_last_labeled "$ev" "$HO_TK_PREFIX:urgent")
  login=${last#* }
  if [ -n "$last" ] && ho_tk_login_ok "$login" && [ "$(ho_tk_access "$login")" = writer ]; then return 0; fi
  ho_ledger_events | jq -e --arg t "$1" 'select(.kind == "urgent-refused" and .ticket == $t)' >/dev/null 2>&1 ||
    ho_ledger_append urgent-refused ticket "$1" by "${login:-unknown}"
  return 1
}
# ho_in_pause_newest <urgent-id>: pause the newest lane of this run, once per urgent ticket.
ho_in_pause_newest() {
  local u=$1 t st type s
  for t in "$HO_RUN_DIR"/pauses/*.json; do
    [ -f "$t" ] && [ "$(jq -r '.for // ""' "$t" 2>/dev/null)" = "$u" ] && return 0
  done
  for t in $(ho_ledger_events | jq -r 'select(.kind == "pickup") | .ticket' | awk '{ a[NR] = $0 } END { for (i = NR; i > 0; i--) if (!seen[a[i]]++) print a[i] }'); do
    [ "$t" = "$u" ] && continue
    [ -f "$HO_RUN_DIR/pauses/$t.json" ] && continue
    st=$(ho_tk_gh_state "$t" 2>/dev/null) || continue
    case " $st " in *" in-progress "*) ;; *) continue ;; esac
    type=$(ho_in_urgent_pause_type) || return 78
    mkdir -p "$HO_RUN_DIR/pauses" || return 1
    jq -cn --arg u "$u" --arg ty "$type" '{for: $u, type: $ty}' | ho_atomic_write "$HO_RUN_DIR/pauses/$t.json" || return 1
    ho_ledger_append urgent-pause ticket "$t" for "$u" type "$type"
    if [ "$type" = hard ]; then
      for s in "$HO_RUN_DIR"/sessions/*.json; do
        [ -f "$s" ] && [ "$(jq -r '.ticket // ""' "$s" 2>/dev/null)" = "$t" ] || continue
        ho_session_close "$(basename "$s" .json)" >/dev/null 2>&1 || true
      done
    fi
    echo "pause $t for $u"
    return 0
  done
}

# ho_in_close_asked: close every session that asked a question and is not closed yet (H-032).
# A close that fails is tried again at every tick, but reported once per question: one
# "close-failed <session>" line and one owner-action line, until a newer question resets it.
ho_in_close_asked() {
  local s kind st
  # Only a session whose newest question has no later question-closed line: a session relaunched
  # under the same name after the answer (D14) is not closed again.
  ho_ledger_events | jq -rn 'reduce (inputs | select(.kind == "question" or .kind == "question-closed"
        or .kind == "question-close-failed")
      | select((.session | type) == "string")) as $e ({}; .[$e.session] = $e.kind)
    | to_entries[] | select(.value != "question-closed") | "\(.key) \(.value)"' |
    while read -r s kind; do
      ho_session_name_ok "$s" 2>/dev/null || continue
      [ -f "$HO_RUN_DIR/sessions/$s.json" ] || continue
      st=$(jq -r '.status // ""' "$HO_RUN_DIR/sessions/$s.json" 2>/dev/null) || continue
      if [ "$st" = closed ] || ho_session_close "$s" >/dev/null 2>&1; then
        ho_ledger_append question-closed session "$s"
        echo "closed $s"
      elif [ "$kind" = question ]; then
        ho_ledger_append question-close-failed session "$s"
        ho_ledger_append owner-action title "session $s asked a question and could not be closed" \
          why "the intake tick closes a session that asked a question (H-032); this close failed and is tried again at every tick" \
          command "harness session $HO_RUN_DIR close $s" verify "the session record of $s reads closed"
        echo "close-failed $s"
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
  HO_IN_NORM=$(ho_in_normalize) || return
  HO_IN_MODE=$(ho_in_mode) || return
  HO_IN_CHANGES=$(ho_in_changes_mode) || return
  ho_in_urgent_pause_type >/dev/null || return
  ho_tk_settings || return
  if ho_tk_ad; then ho_tk_status_map >/dev/null || return; fi
  ho_in_halted || return
  if [ -f "$(ho_in_state)" ]; then
    wait=$(ho_in_wait "$interval" "$(ho_in_errors)")
    mtime=$(ho_tk_lock_mtime "$(ho_in_state)")
    age=$(( $(date +%s) - mtime ))
    if [ "$age" -lt "$wait" ]; then echo "not-due $((wait - age))"; return 0; fi
  fi
  ho_in_close_asked
  ho_in_watch_all
  # H-117, H-120: the channels are read at each due tick; first answers land on the ticket
  # before the answers are read there (H-118).
  if ho_nt_defined; then ho_nt_poll || true; fi
  ho_in_answers_all
  if ! ids=$(ho_tickets ids ready 2>/dev/null); then
    ho_in_record $(( $(ho_in_errors) + 1 )) || return 1
    ho_ledger_append poll-error errors "$(ho_in_errors)"
    echo tracker-error
    return 69
  fi
  ho_in_record 0 || return 1
  free=$(ho_in_free_workers)
  [ -n "$max" ] && [ "$max" -lt "$free" ] && free=$max
  # Urgent tickets first (H-083, H-084, D3).
  if ho_tk_gh; then
    local urg="" rest="" act
    ho_in_unpause
    for id in $ids; do if ho_in_is_urgent "$id"; then urg="$urg $id"; else rest="$rest $id"; fi; done
    act=$(ho_in_active_urgent)
    for id in $urg; do
      if [ -n "$act" ] && [ "$act" != "$id" ]; then echo "urgent-waiting $id"; continue; fi
      if [ "$started" -ge "$free" ]; then
        ho_in_pause_newest "$id" || return
        echo "urgent-waiting $id"
        act=$id
        continue
      fi
      ho_in_halted || return
      if ho_in_pickup "$id"; then
        started=$((started + 1))
        ho_ledger_append urgent-start ticket "$id"
        act=$id
      fi
    done
    ids=$rest
  fi
  for id in $ids; do
    [ "$started" -lt "$free" ] || break
    # A stop or a run end recorded during an earlier pickup (a readiness check can take
    # minutes) is seen before the next claim (D25a).
    ho_in_halted || return
    if ho_in_pickup "$id"; then started=$((started + 1)); fi
  done
  return 0
}

# ho_in_halted: 0 when intake may claim; otherwise prints "stopped" or "ended" and returns 75.
# A stop state that cannot be read counts as stopped. An ended run (its newest run-end line has
# no later resume, as lifecycle check reads it) claims nothing: a ticket taken now would have
# no run to work in (H-079).
ho_in_halted() {
  local rc=0
  ho_stopped || rc=$?
  if [ "$rc" -ne 1 ]; then echo stopped; return "$HO_EXIT_STOPPED"; fi
  if ho_run_ended; then echo ended; return "$HO_EXIT_STOPPED"; fi
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
                      kept-done|error <id>, change-applied|change-ignored <id>,
                      change-ticket <id> <new-id>, resume <id>, urgent-waiting <id>,
                      pause <id> for <urgent-id>, unpause <id>, closed|close-failed <session>,
                      not-due <seconds>, tracker-error, stopped, ended
  poll [--max N]      tick until the run is stopped or has ended
  text <id>           the ticket text for a session: the description as picked up and the
                      comments of writers, inside the untrusted fence
USAGE
}

ho_intake_main() {
  [ $# -ge 2 ] || { ho_in_usage; exit 64; }
  ho_run_open "$1"
  local verb=$2 rc=0
  shift 2
  ho_session_bind_project || exit $?
  # Local tickets: the folder of the run's own project, never of the place intake is called from.
  ho_tk_bind_project_dir
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
    text)
      # The ticket text a session gets: the description as picked up (D37-INTAKE-7) and the
      # comments of writers (H-018, D9), inside the untrusted fence.
      local tid bf
      tid=$(ho_stop_ticket_arg "${1-}") || exit 64
      bf="$HO_RUN_DIR/intake/watch/$tid.body"
      if [ -f "$bf" ] && [ ! -L "$bf" ]; then HO_TK_SHOW_BODY_FILE=$bf ho_tickets show "$tid" || rc=$?
      else ho_tickets show "$tid" || rc=$?; fi ;;
    poll) ho_in_interval >/dev/null || exit $?; ho_in_poll "$@" || rc=$? ;;
    *) ho_in_usage; rc=64 ;;
  esac
  exit "$rc"
}
