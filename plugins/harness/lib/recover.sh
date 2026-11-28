# shellcheck shell=bash
# Recovery (H-088, H-091, H-092, H-093, H-094, H-114; design D14, D20, D21, D28c, D32,
# D37-LIFECYCLE-1, D37-LIFECYCLE-2, D37-SESSIONS-1, D42h).
#
# The engine reports facts and runs the fixed order; the orchestrator calls "recover <run> tick"
# from its loop and may judge doubts itself (D20). For each ticket whose newest worker session
# reads dead, in this order:
#   1. leave it: a human-stop signal (a STOP file or a stop in force, the ticket's state label
#      changed away from in-progress, or the runtime's exit command typed by a human in the
#      transcript) leaves the ticket stopped (H-093, D20)
#   2. resume the same session by its ID, once, when the D14 conditions hold: the ID is
#      recorded, the transcript is on this machine, the working folder still exists, and the
#      runtime can resume by ID (H-092)
#   3. a new session with the context pack (D14): ticket text and thread (fenced), branch and
#      worktree, the current step, the step reports, the old session ID. Every launch of this
#      engine opens its own terminal tab or pane, so step 3 is also the "fresh terminal" step.
#   4. escalate: when the attempts run out, the ticket goes to blocked with one comment (H-094)
# Attempts and waits (D21): recovery.attempts (3) and recovery.waits_seconds ([60, 300, 900]).
# A failed resume counts as an attempt and the new session follows at once (D14). The late
# attempt (D37-SESSIONS-1) runs once, recovery.late_hours (12; 0 turns it off) after the block,
# while the run is alive, the ticket is still blocked and no human-stop signal exists; if it
# fails, one ledger line and no second comment.
# The attempt clock (D21) stops during outages, limit waits and sleep: each tick adds the time
# since the last tick, at most recovery.tick_cap_seconds (300), so a sleep counts as one cap at
# most; while a wait is open in the ledger (wait-begin with no wait-end), it adds nothing.
#
#   <run>/recovery/<ticket>.json        attempts, clock, phase, late due time (survives an
#                                       orchestrator restart)
#   <run>/recovery/<ticket>.pack.md     the context pack of the newest new session
#
# Reboot (D32, D37-LIFECYCLE-2): nothing starts by itself. "recover last" names the newest
# unfinished run of the project; "recover <run> reopen" resumes each session of the registry
# whose process is gone by its recorded ID (D42h) and leaves every live one. A recorded process
# ID is never signalled. With recovery.ask_first true, reopen asks first: it exits 77 and
# launches nothing unless --yes is given (H-088).
#
# Exit codes: 64 usage, 66 no run, 77 asks first, 78 config.

HO_REC_EXIT_ASK=77

ho_rec_dir() { printf '%s/recovery\n' "$HO_RUN_DIR"; }

ho_rec_settings() {
  HO_REC_ATTEMPTS=$(ho_cfg_int '.recovery.attempts' 3) || return 78
  HO_REC_WAITS=$(ho_cfg '.recovery.waits_seconds | tojson' '[60,300,900]') || return 78
  [ "$HO_REC_WAITS" = null ] && HO_REC_WAITS='[60,300,900]'
  printf '%s' "$HO_REC_WAITS" | jq -e 'type == "array" and length > 0 and all(type == "number" and . >= 0)' >/dev/null 2>&1 || {
    echo "harness: config recovery.waits_seconds must be a list of whole seconds" >&2; return 78; }
  HO_REC_LATE=$(ho_cfg_int '.recovery.late_hours' 12) || return 78
  HO_REC_CAP=$(ho_cfg_int '.recovery.tick_cap_seconds' 300) || return 78
}

# ho_rec_wait_open: 0 while a limit wait or an outage is open in the ledger (D21 clock stops).
ho_rec_wait_open() {
  [ "$(ho_ledger_events | jq -r 'select(.kind == "wait-begin" or .kind == "wait-end") | .kind' | tail -n 1)" = wait-begin ]
}

# ho_rec_state <ticket>: the ticket's recovery state (JSON).
ho_rec_state() {
  local f s
  f="$(ho_rec_dir)/$1.json"
  s=$(jq -c 'select(type == "object")' "$f" 2>/dev/null) || s=""
  [ -n "$s" ] || s=$(jq -cn --arg t "$1" --argjson now "$(date +%s)" '{ticket: $t, attempts: 0, clock: 0, last_tick: $now, phase: "watching", due: 0, late_due: null, late_done: false}')
  printf '%s\n' "$s"
}
ho_rec_save() { mkdir -p "$(ho_rec_dir)" && printf '%s\n' "$2" | ho_atomic_write "$(ho_rec_dir)/$1.json"; }

# ho_rec_h <args>: the engine itself, as a child process (its own exits stay its own).
ho_rec_h() { HO_PROJECT_DIR=$HO_PROJECT_DIR "$HO_ROOT/bin/harness" "$@"; }

# ho_rec_ticket_state <ticket>: in-progress, blocked, ... or unknown.
ho_rec_ticket_state() {
  local s
  for s in in-progress blocked ready needs-review done; do
    ho_rec_h tickets ids "$s" 2>/dev/null | grep -qx -- "$1" && { echo "$s"; return 0; }
  done
  echo unknown
}

# ho_rec_human_exit <record>: 0 when the transcript holds the runtime's exit command typed as a
# user line and no close by the harness was under way.
ho_rec_human_exit() {
  local rec=$1 tr profile exitcmd name
  name=$(jq -r .name "$rec")
  [ -e "$HO_RUN_DIR/sessions/$name.closing" ] && return 1
  [ "$(jq -r '.status // ""' "$rec")" = closed ] && return 1
  tr=$(ho_live_transcript "$rec" 2>/dev/null) || tr=""
  [ -n "$tr" ] && [ -r "$tr" ] || return 1
  profile=$(ho_runtime_profile 2>/dev/null) || return 1
  exitcmd=$(jq -r '.exit_command // ""' "$profile")
  [ -n "$exitcmd" ] || return 1
  jq -e --arg x "$exitcmd" --argjson ut "$(jq -c '.transcript.user_types // ["user"]' "$profile")" '
    select(type == "object" and (.type as $t | $ut | index($t)))
    | (.message.content // .content // "") | if type == "array" then map(.text? // "") | join("") else tostring end
    | gsub("^\\s+|\\s+$"; "") == $x' "$tr" >/dev/null 2>&1
}

# ho_rec_human_stop <ticket> <record>: print the signal and return 0 when a human stopped it.
ho_rec_human_stop() {
  local st=0 ts
  ho_stopped 2>/dev/null || st=$?
  [ "$st" -ne 1 ] && { echo "stop"; return 0; }
  ts=$(ho_rec_ticket_state "$1")
  case $ts in in-progress) ;; *) echo "ticket state $ts"; return 0 ;; esac
  ho_rec_human_exit "$2" && { echo "exit typed by a human"; return 0; }
  return 1
}

# ho_rec_resumable <record>: the D14 conditions for a resume by ID.
ho_rec_resumable() {
  local rec=$1 sid cwd tr profile
  sid=$(jq -r '.session_id // ""' "$rec"); cwd=$(jq -r '.cwd // ""' "$rec")
  ho_session_uuid_ok "$sid" 2>/dev/null || return 1
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 1
  tr=$(ho_live_transcript "$rec" 2>/dev/null) || tr=""
  [ -n "$tr" ] && [ -r "$tr" ] || return 1
  profile=$(ho_runtime_profile 2>/dev/null) || return 1
  jq -e '(.argv.resume | type) == "array" and (.argv.resume | length) > 0' "$profile" >/dev/null 2>&1
}

# ho_rec_pack <ticket> <record> <file>: write the context pack (D14).
ho_rec_pack() {
  local t=$1 rec=$2 out=$3 cwd branch step reports
  cwd=$(jq -r '.cwd // ""' "$rec")
  branch=$( [ -d "$cwd" ] && git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null ) || branch=""
  step=$(ho_ledger_events | jq -r --arg t "$t" 'select(.kind == "step-begin" and (.ticket | tostring) == $t) | .step' | tail -n 1)
  reports=$(ho_ledger_events | jq -r --arg t "$t" 'select((.kind == "step-done" or .kind == "step") and (.ticket | tostring) == $t) | "- \(.step // "?"): \(.result // "")"')
  {
    printf '# Continue ticket %s (recovery context pack)\n\n' "$t"
    printf 'A session working on this ticket stopped. Continue the work from the current step; do not start over.\n\n'
    printf -- '- Old session ID (for reference): %s\n' "$(jq -r '.session_id // "-"' "$rec")"
    printf -- '- Worktree: %s\n' "${cwd:--}"
    printf -- '- Branch: %s\n' "${branch:--}"
    printf -- '- Current step: %s\n\n' "${step:--}"
    printf '## Step reports\n\n%s\n\n' "${reports:-none}"
    printf '## Ticket text and thread\n\n'
    ho_rec_h tickets show "$t" 2>/dev/null || printf '(the ticket could not be read)\n'
  } > "$out"
}

# ho_rec_base <name>: the session name without a recovery suffix.
ho_rec_base() { printf '%s\n' "$1" | sed -E 's/-r[0-9]+$//'; }

# ho_rec_launch <ticket> <record> <how: resume|new> <n>: launch the attempt; 0 started.
ho_rec_launch() {
  local t=$1 rec=$2 how=$3 n=$4 name new cwd pack rc=0
  name=$(jq -r .name "$rec"); cwd=$(jq -r '.cwd // ""' "$rec")
  new="$(ho_rec_base "$name")-r$n"
  if [ "$how" = resume ]; then
    # The old record is closed the normal way first (a gone process is only marked closed); a
    # resume never runs beside an open record of the same session ID.
    ho_rec_h session "$HO_RUN_DIR" close "$name" >/dev/null 2>&1 || true
    ho_rec_h session "$HO_RUN_DIR" launch --role worker --name "$new" --cwd "$cwd" --ticket "$t" \
      --resume "$(jq -r .session_id "$rec")" >/dev/null 2>&1 || rc=$?
  else
    pack="$(ho_rec_dir)/$t.pack.md"
    ho_rec_pack "$t" "$rec" "$pack"
    ho_rec_h session "$HO_RUN_DIR" launch --role worker --name "$new" --cwd "$cwd" --ticket "$t" \
      --prompt "$pack" >/dev/null 2>&1 || rc=$?
  fi
  ho_ledger_append recover-attempt ticket "$t" name "$new" how "$how" attempt "$n" from "$name" rc "$rc"
  return "$rc"
}

# ho_rec_newest <ticket>: the newest worker record of the ticket.
ho_rec_newest() {
  local f best="" bt="" c
  for f in "$HO_RUN_DIR"/sessions/*.json; do
    [ -f "$f" ] || continue
    jq -e --arg t "$1" 'type == "object" and .role == "worker" and ((.ticket // "") | tostring) == $t' "$f" >/dev/null 2>&1 || continue
    c=$(jq -r '.created // ""' "$f")
    if [ -z "$best" ] || [[ "$c" > "$bt" ]] || { [ "$c" = "$bt" ] && [[ "$f" > "$best" ]]; }; then best=$f; bt=$c; fi
  done
  [ -n "$best" ] && printf '%s\n' "$best"
}

# ho_rec_block <ticket> <reason>: escalate: blocked with one comment (H-094, D20).
ho_rec_block() {
  local t=$1 why f
  f=$(mktemp "${TMPDIR:-/tmp}/ho-rec.XXXXXX")
  why=$2
  printf '%s\n' "$why" > "$f"
  ho_rec_h tickets block "$t" "$f" >/dev/null 2>&1 || ho_ledger_append recover-block-failed ticket "$t"
  rm -f "$f"
  ho_ledger_append recover-blocked ticket "$t" reason "$why"
}

# ho_rec_tick_one <ticket>: one pass of the order for one ticket. Prints what it did.
ho_rec_tick_one() {
  local t=$1 s rec live now delta sig n wait how rc
  s=$(ho_rec_state "$t")
  now=$(date +%s)
  delta=$(jq -n --argjson s "$s" --argjson now "$now" --argjson cap "$HO_REC_CAP" '[([($now - $s.last_tick), 0] | max), $cap] | min')
  ho_rec_wait_open && delta=0
  s=$(jq -c --argjson d "$delta" --argjson now "$now" '.clock += $d | .last_tick = $now' <<<"$s")
  rec=$(ho_rec_newest "$t") || { ho_rec_save "$t" "$s"; return 0; }
  live=$(ho_rec_h session "$HO_RUN_DIR" status "$(jq -r .name "$rec")" 2>/dev/null | jq -r '.liveness // "unknown"' 2>/dev/null) || live=unknown
  case $(jq -r .phase <<<"$s") in
    blocked)
      # The late attempt (D37-SESSIONS-1).
      if [ "$(jq -r '.late_done' <<<"$s")" != true ] && [ "$(jq -r '.late_due // "null"' <<<"$s")" != null ] \
        && jq -e '.clock >= .late_due' <<<"$s" >/dev/null && [ "$live" != working ]; then
        s=$(jq -c '.late_done = true' <<<"$s"); ho_rec_save "$t" "$s"
        if [ "$(ho_rec_ticket_state "$t")" != blocked ] || [ "$(ho_ledger_events | jq -r --arg t "$t" 'select(.ticket == $t and (.kind == "recover-blocked" or .kind == "recover-unblocked")) | .kind' | tail -n 1)" != recover-blocked ]; then
          ho_ledger_append recover-late-skipped ticket "$t" reason "the ticket is no longer blocked for the same reason"
          echo "late attempt skipped for ticket $t"; return 0
        fi
        sig=$(ho_rec_human_stop_blocked "$t") && { ho_ledger_append recover-late-skipped ticket "$t" reason "$sig"; echo "late attempt skipped for ticket $t: $sig"; return 0; }
        rc=0; ho_rec_launch "$t" "$rec" new "$(( $(jq -r .attempts <<<"$s") + 1 ))" || rc=$?
        s=$(jq -c '.attempts += 1 | .phase = "late"' <<<"$s"); ho_rec_save "$t" "$s"
        [ "$rc" -eq 0 ] && echo "late attempt for ticket $t" || { ho_ledger_append recover-late-failed ticket "$t" rc "$rc"; echo "late attempt for ticket $t failed"; }
        return 0
      fi
      ho_rec_save "$t" "$s"; return 0 ;;
    late)
      if [ "$live" = dead ] && [ "$(jq -r '.late_failed // false' <<<"$s")" != true ]; then
        ho_ledger_append recover-late-failed ticket "$t" name "$(jq -r .name "$rec")"
        s=$(jq -c '.late_failed = true' <<<"$s")
      fi
      ho_rec_save "$t" "$s"; return 0 ;;
    stopped) ho_rec_save "$t" "$s"; return 0 ;;
  esac
  [ "$live" = dead ] || { ho_rec_save "$t" "$s"; return 0; }
  # A dead session: the fixed order (D20).
  if sig=$(ho_rec_human_stop "$t" "$rec"); then
    s=$(jq -c '.phase = "stopped"' <<<"$s"); ho_rec_save "$t" "$s"
    ho_ledger_append recover-left ticket "$t" name "$(jq -r .name "$rec")" reason "human stop: $sig"
    echo "ticket $t left stopped ($sig)"
    return 0
  fi
  n=$(jq -r .attempts <<<"$s")
  if [ "$n" -ge "$HO_REC_ATTEMPTS" ]; then
    s=$(jq -c --argjson late "$HO_REC_LATE" '.phase = "blocked" | .late_due = (if $late > 0 then .clock + $late * 3600 else null end)' <<<"$s")
    ho_rec_save "$t" "$s"
    ho_rec_block "$t" "Recovery attempts ran out: $n attempts failed for this ticket's session. The ticket is blocked; set the ready label to try again."
    echo "ticket $t blocked: attempts ran out"
    return 0
  fi
  # The wait before this attempt, on the clock that stops during waits and sleep (D21).
  if [ "$(jq -r '.waiting_since // "null"' <<<"$s")" = null ]; then s=$(jq -c '.waiting_since = .clock' <<<"$s"); fi
  wait=$(jq -n --argjson w "$HO_REC_WAITS" --argjson n "$n" '$w[[($n), ($w | length - 1)] | min]')
  if ! jq -e --argjson w "$wait" '.clock - .waiting_since >= $w' <<<"$s" >/dev/null; then
    ho_rec_save "$t" "$s"; echo "ticket $t waits before attempt $((n + 1))"; return 0
  fi
  how=new
  [ "$n" -eq 0 ] && ho_rec_resumable "$rec" && how=resume
  s=$(jq -c '.attempts += 1 | del(.waiting_since)' <<<"$s"); ho_rec_save "$t" "$s"
  rc=0; ho_rec_launch "$t" "$rec" "$how" "$((n + 1))" || rc=$?
  if [ "$rc" -ne 0 ] && [ "$how" = resume ] && [ "$((n + 1))" -lt "$HO_REC_ATTEMPTS" ]; then
    # A failed or refused resume counts as an attempt; the new session starts at once (D14).
    echo "ticket $t: resume failed (rc $rc); a new session follows"
    s=$(jq -c '.attempts += 1' <<<"$s"); ho_rec_save "$t" "$s"
    how=new; n=$((n + 1)); rc=0
    ho_rec_launch "$t" "$rec" new "$((n + 1))" || rc=$?
  fi
  echo "ticket $t: attempt $((n + 1)) $how rc $rc"
}

# ho_rec_human_stop_blocked <ticket>: human-stop signals for a blocked ticket (no state check).
ho_rec_human_stop_blocked() {
  local st=0
  ho_stopped 2>/dev/null || st=$?
  [ "$st" -ne 1 ] && { echo "stop"; return 0; }
  return 1
}

# recover <run> tick: one pass over every ticket with a worker session.
ho_rec_tick() {
  local t
  ho_rec_settings || return 78
  ho_tk_bind_project_dir
  for t in $(for f in "$HO_RUN_DIR"/sessions/*.json; do [ -f "$f" ] && jq -r 'select(type == "object" and .role == "worker") | .ticket // empty | tostring' "$f" 2>/dev/null; done | sort -u); do
    case $t in '' | *[!0-9]*) continue ;; esac
    ho_rec_tick_one "$t"
  done
}

# recover last: the newest run of this project that has not ended.
ho_rec_last() {
  local proj d best=""
  proj=$(ho_project_root) || { echo "harness: no project here" >&2; return 66; }
  for d in "$proj/.harness/runs"/*/; do
    d=${d%/}
    [ -f "$d/run.json" ] || continue
    ( ho_run_open "$d" >/dev/null 2>&1 && ! ho_run_ended ) 2>/dev/null || continue
    best=$d
  done
  [ -n "$best" ] || { echo "harness: no unfinished run in this project" >&2; return 66; }
  printf '%s\n' "$best"
}

# recover <run> reopen [--yes]: resume every session whose process is gone, by its recorded ID
# (D42h, D37-LIFECYCLE-2). A live session is left alone; no recorded PID is ever signalled.
ho_rec_reopen() {
  local yes=0 f name live role sid cwd ticket rc n=0
  [ "${1-}" = --yes ] && yes=1
  if [ "$(ho_cfg '.recovery.ask_first' 'false')" = true ] && [ "$yes" -eq 0 ]; then
    echo "harness: recovery.ask_first is on; run again with --yes to resume the run's sessions" >&2
    return "$HO_REC_EXIT_ASK"
  fi
  for f in "$HO_RUN_DIR"/sessions/*.json; do
    [ -f "$f" ] || continue
    name=$(jq -r '.name // ""' "$f" 2>/dev/null); [ -n "$name" ] || continue
    live=$(ho_rec_h session "$HO_RUN_DIR" status "$name" 2>/dev/null | jq -r '.liveness // "unknown"') || live=unknown
    [ "$live" = dead ] || continue
    # A session that a later reopen or recovery already replaced is not reopened twice.
    ho_ledger_events | jq -e --arg n "$name" 'select((.kind == "recover-attempt" or .kind == "reopen") and .from == $n)' >/dev/null 2>&1 && continue
    role=$(jq -r .role "$f"); sid=$(jq -r '.session_id // ""' "$f"); cwd=$(jq -r '.cwd // ""' "$f"); ticket=$(jq -r '.ticket // "" | tostring' "$f")
    n=$((n + 1))
    rc=0
    ho_rec_h session "$HO_RUN_DIR" close "$name" >/dev/null 2>&1 || true
    ho_rec_h session "$HO_RUN_DIR" launch --role "$role" --name "$(ho_rec_base "$name")-o$(date +%s)$n" --cwd "$cwd" --resume "$sid" \
      ${ticket:+--ticket "$ticket"} >/dev/null 2>&1 || rc=$?
    ho_ledger_append reopen from "$name" session_id "$sid" rc "$rc"
    printf 'reopen %s session %s rc %s\n' "$name" "$sid" "$rc"
  done
  [ "$n" -gt 0 ] || echo "nothing to reopen"
}

ho_rec_usage() {
  cat >&2 <<'USAGE'
usage: harness recover last                 the newest unfinished run of this project
       harness recover <run-dir> tick       one recovery pass over the run's tickets (D20 order)
       harness recover <run-dir> reopen [--yes]
                                            resume every session whose process is gone by its ID
       harness recover <run-dir> state <ticket>
                                            the ticket's recovery state, one JSON line
USAGE
}

ho_rec_main() {
  [ "${1-}" = last ] && { ho_rec_last; return $?; }
  [ $# -ge 2 ] || { ho_rec_usage; exit 64; }
  ho_run_open "$1"
  HO_PROJECT_DIR=${HO_PROJECT_DIR:-$(dirname "$(dirname "$(dirname "$HO_RUN_DIR")")")}
  export HO_PROJECT_DIR
  case $2 in
    tick) ho_rec_tick ;;
    reopen) shift 2; ho_rec_reopen "$@" ;;
    state) [ -n "${3-}" ] || { ho_rec_usage; exit 64; }; ho_rec_state "$3" ;;
    *) ho_rec_usage; exit 64 ;;
  esac
}
