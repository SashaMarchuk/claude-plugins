# shellcheck shell=bash
# End of run, standby and closing finished sessions (tasks.md 17.3, standby and end-of-run part).
# H-079: by default a run ends when all tickets are done. H-080: opt-in standby, where finished
# terminals close and the orchestrator alone watches the tracker. H-081: a worker session closes
# when its task ends, and only sessions of this run are closed, each by its exact process (S8-27,
# through session close). H-082: when only review tickets remain the workers stop and the
# orchestrator and the watcher wait. S8-20a: only human-blocked tickets left with standby off:
# on_only_human_blocked, default wait, with no nudges. D37-LIFECYCLE-3: the orchestrator and the
# watcher are exempt from close-when-done and close when the run ends, also when a stop ends it.
#
#   <run>/lifecycle.json   {standby, standby_source, on_only_human_blocked}: written once by run new
#
# Settings (OPEN-9, settled under D37): run.standby (true or false, default false), overridden for
# one run by "run new --standby on|off"; run.on_only_human_blocked (wait or end, default wait).
#
# The run keeps no list of its own tickets. Its tickets are the tickets of the queue it runs
# (tickets ids <state>); a done ticket of an earlier run counts as done. A queue that cannot be
# read, or that lists a ticket in none of the five states (D2), is "unknown", never "all done".
#
# Requires lib/run.sh, lib/config.sh, lib/tickets.sh, lib/sessions.sh and lib/liveness.sh.

# ho_life_settings: set HO_LIFE_STANDBY and HO_LIFE_ONB from lifecycle.json. A run without the
# file (started by older code) uses the defaults; an unreadable file is a config error.
ho_life_settings() {
  local f="$HO_RUN_DIR/lifecycle.json"
  HO_LIFE_STANDBY=false
  HO_LIFE_ONB=wait
  [ -e "$f" ] || return 0
  HO_LIFE_STANDBY=$(jq -er '.standby | if . == true or . == false then tostring else error end' "$f" 2>/dev/null) \
    && HO_LIFE_ONB=$(jq -er '.on_only_human_blocked | select(. == "wait" or . == "end")' "$f" 2>/dev/null) \
    || { printf 'harness: %s is unreadable\n' "$f" >&2; return 78; }
}

# ho_life_ids <state>: the ticket numbers in that state, read-only. The ticket folder defaults
# to the project's .harness/tickets, wherever the caller stands.
ho_life_ids() {
  (
    [ -n "${HO_TICKETS_DIR:-}" ] || export HO_TICKETS_DIR="$HO_PROJECT_DIR/.harness/tickets"
    # A missing local ticket folder lists nothing, which must never read as "all done".
    if [ "${HO_TICKETS_SOURCE:-local}" = local ] && [ ! -d "$HO_TICKETS_DIR" ]; then
      printf 'harness: the ticket folder %s does not exist\n' "$HO_TICKETS_DIR" >&2
      exit 74
    fi
    ho_tickets ids "$1"
  )
}

# ho_life_unstated: the queue's tickets that are in none of the five states (D2), read-only, from
# one listing. Local: a ticket file whose status is not a known state (or cannot be read). GitHub:
# an open issue with a harness label (<prefix>:...) but no state label; an issue with no harness
# label is not a harness ticket. Such a ticket may or may not be done, so it is never "all done".
ho_life_unstated() {
  (
    [ -n "${HO_TICKETS_DIR:-}" ] || export HO_TICKETS_DIR="$HO_PROJECT_DIR/.harness/tickets"
    ho_tk_settings || exit $?
    if ho_tk_gh; then
      local json
      json=$(gh issue list --repo "$HO_TK_REPO" --state open --limit 200 --json number,labels) || exit 1
      printf '%s' "$json" |
        jq -r --arg p "$HO_TK_PREFIX:" --arg s "$HO_STATES" '($s | split(" ") | map($p + .)) as $known
          | .[] | [.labels[].name] as $l
          | select(any($l[]; startswith($p)) and all($l[]; . as $x | $known | index($x) | not)) | .number'
    else
      local n f
      ho_tk_l_each | while IFS=$'\t' read -r n f; do
        [ "$(ho_tk_l_state "$f")" != unknown ] || printf '%s\n' "$n"
      done
    fi
  )
}

# ho_life_self <record>: 0 when the caller is the session of that record (the launcher exports
# its name and session ID).
ho_life_self() {
  [ -n "${HO_SESSION_NAME:-}" ] && [ -n "${HO_SESSION_ID:-}" ] || return 1
  [ "$(jq -r '"\(.name // "")|\(.session_id // "")"' "$1" 2>/dev/null)" = "$HO_SESSION_NAME|$HO_SESSION_ID" ]
}

# ho_life_say <text>: add one output line. The lines are printed once, at the end of the call
# (ho_life_flush): a reader that leaves early (a broken pipe) would otherwise leave a line in
# bash's output buffer, which bash flushes into the next command substitution and so into a
# record check of the sweep.
ho_life_say() { HO_LIFE_OUT="${HO_LIFE_OUT-}$*"$'\n'; }
ho_life_flush() { printf '%s' "${HO_LIFE_OUT-}" 2>/dev/null || true; HO_LIFE_OUT=""; }

# ho_life_close <name>: one graceful close in a subshell (session close may exit). Prints one
# line: "closed <name>" or "left-open <name> exit <code>".
ho_life_close() {
  local rc=0
  (ho_session_close "$1") >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then ho_life_say "closed $1"; else ho_life_say "left-open $1 exit $rc"; fi
}

# ho_life_sweep <workers|keepers>: close the sessions of this run that are not closed. "workers"
# is every session but the orchestrator and the watcher; "keepers" is those two. The calling
# session is never closed by itself: it is named as "self <name>" and ends its own session. A
# record of another run is never touched.
ho_life_sweep() {
  local which=$1 f name role
  for f in "$HO_RUN_DIR"/sessions/*.json; do
    [ -f "$f" ] || continue
    [ "$(jq -r 'if type == "object" then (.run // "") else "" end' "$f" 2>/dev/null)" = "$HO_RUN_ID" ] || continue
    [ "$(jq -r '.status // ""' "$f" 2>/dev/null)" != closed ] || continue
    name=$(jq -r '.name // ""' "$f" 2>/dev/null)
    role=$(jq -r '.role // ""' "$f" 2>/dev/null)
    [ "$name" = "$(basename "$f" .json)" ] || continue
    case $which:$role in
      workers:orchestrator | workers:watcher) continue ;;
      keepers:orchestrator | keepers:watcher) ;;
      keepers:*) continue ;;
    esac
    if ho_life_self "$f"; then
      ho_ledger_events | jq -e --arg n "$name" 'select(.kind == "session-close-self-skipped" and .name == $n)' >/dev/null 2>&1 \
        || ho_ledger_append session-close-self-skipped name "$name"
      ho_life_say "self $name: this session ends itself"
      continue
    fi
    ho_life_close "$name"
  done
}

# ho_life_live_others: names of this run's sessions other than the orchestrator and the watcher
# that may still run (working, starting or unknown).
ho_life_live_others() {
  local f
  for f in "$HO_RUN_DIR"/sessions/*.json; do
    [ -f "$f" ] || continue
    [ "$(jq -r 'if type == "object" then (.run // "") else "" end' "$f" 2>/dev/null)" = "$HO_RUN_ID" ] || continue
    case $(jq -r '.role // ""' "$f" 2>/dev/null) in orchestrator | watcher) continue ;; esac
    case $(ho_live_verdict "$f") in dead | closed) ;; *) basename "$f" .json ;; esac
  done
}

# ho_life_has <id> <list>: 0 when the id is in the space or newline separated list.
ho_life_has() { printf '%s\n' $2 | grep -qx -- "$1"; }

# harness lifecycle <run> check: decide what the run does now, act on it and print the decision
# as the first line. The decision is worked out again at every call, so standby and a wait go
# back to work when a ticket appears or changes; only a run end stays.
#   work          a ticket is ready or in progress
#   stopping      a soft stop is in force and work it allows still runs; nothing is closed
#   wait-review   every remaining ticket waits on review: workers close (H-082)
#   wait-blocked  only human-blocked tickets remain: workers close, nothing is sent (S8-20a)
#   standby       all tickets done, standby on: finished terminals close (H-080)
#   end           the run ends: every session of this run closes (H-079, D37-LIFECYCLE-3)
#   ended         the run ended earlier; a session still open is closed again
#   unknown       the stop state or the ticket queue cannot be read, or a ticket of the queue is
#                 in none of the five states (D2): nothing changes (exit 2)
ho_life_check() {
  local st=0 s ids ready="" inprog="" blocked="" review="" decision reason="" t active="" live prev
  if ho_run_ended; then
    # A close that failed at the run end (a busy session, a terminal that could not be reached)
    # is tried again at every later call; closed records are skipped.
    ho_life_say ended
    ho_life_sweep workers
    ho_life_sweep keepers
    return 0
  fi
  ho_life_settings || return $?
  ho_stopped 2>/dev/null || st=$?
  [ "$st" -ne 2 ] || { ho_life_say unknown; echo "harness: the stop state is unknown; nothing changed" >&2; return 2; }
  for s in ready in-progress blocked needs-review; do
    ids=$(ho_life_ids "$s" 2>/dev/null) || { ho_life_say unknown; printf 'harness: the %s tickets cannot be read; nothing changed\n' "$s" >&2; return 2; }
    case $s in
      ready) ready=$ids ;; in-progress) inprog=$ids ;; blocked) blocked=$ids ;; needs-review) review=$ids ;;
    esac
  done
  # A ticket in none of the five states might still be open work: fail closed, as above.
  ids=$(ho_life_unstated 2>/dev/null) || { ho_life_say unknown; echo "harness: the ticket states cannot be read; nothing changed" >&2; return 2; }
  if [ -n "$ids" ]; then
    ho_life_say unknown
    printf 'harness: ticket(s) %s are in none of the states ready, in-progress, blocked, needs-review, done; nothing changed\n' "$(printf '%s ' $ids)" >&2
    return 2
  fi
  if [ "$st" -eq 0 ]; then
    # D25a: a soft stop lets running work finish. soft:ticket also lets each covered ticket
    # begun before the stop run on while it is ready or in progress.
    ho_stop_read
    if [ "$HO_STOP_TYPE" = soft:ticket ]; then
      for t in $HO_STOP_BEGUN; do
        case " $HO_STOP_TICKETS " in *" all "* | *" $t "*) ;; *) continue ;; esac
        if ho_life_has "$t" "$ready $inprog"; then active="$active $t"; fi
      done
    fi
    live=$(ho_life_live_others)
    if [ -z "$live" ] && [ -z "$active" ]; then decision=end reason=stop; else decision=stopping; fi
  elif [ -n "$ready$inprog" ]; then
    decision=work
  elif [ -n "$review" ]; then
    decision=wait-review
  elif [ -n "$blocked" ]; then
    if [ "$HO_LIFE_STANDBY" = false ] && [ "$HO_LIFE_ONB" = end ]; then decision=end reason=only-human-blocked; else decision=wait-blocked; fi
  elif [ "$HO_LIFE_STANDBY" = true ]; then
    decision=standby
  else
    decision=end reason=all-done
  fi
  # One ledger line per change of decision, so a polling orchestrator does not fill the ledger.
  prev=$(ho_ledger_events | jq -r 'select(.kind == "lifecycle") | .decision' | tail -n 1)
  [ "$prev" = "$decision" ] || ho_ledger_append lifecycle decision "$decision" standby "$HO_LIFE_STANDBY"
  ho_life_say "$decision"
  case $decision in
    wait-review | wait-blocked | standby) ho_life_sweep workers ;;
    end)
      ho_ledger_append run-end reason "$reason"
      ho_life_sweep workers
      ho_life_sweep keepers
      ;;
  esac
  return 0
}

# harness lifecycle <run> done <name>: the task of that session ended (H-081). One ledger line,
# then a graceful close by its exact process. The orchestrator and the watcher have no single
# task and close only at run end (D37-LIFECYCLE-3). A session cannot close itself.
ho_life_done() {
  local name=${1-} rec role
  [ -n "$name" ] || { ho_life_usage; return 64; }
  ho_session_name_ok "$name" || return 65
  rec="$HO_RUN_DIR/sessions/$name.json"
  [ -f "$rec" ] || { printf 'harness: no session %s in run %s\n' "$name" "$HO_RUN_ID" >&2; return 66; }
  [ "$(jq -r 'if type == "object" then (.run // "") else "" end' "$rec" 2>/dev/null)" = "$HO_RUN_ID" ] \
    || { printf 'harness: session %s is not recorded under run %s; left alone\n' "$name" "$HO_RUN_ID" >&2; return 66; }
  role=$(jq -r '.role // ""' "$rec")
  case $role in
    orchestrator | watcher)
      printf 'harness: session %s is the %s; it has no single task and closes when the run ends\n' "$name" "$role" >&2
      return 65
      ;;
  esac
  if ho_life_self "$rec"; then
    printf 'harness: session %s cannot close itself; the orchestrator closes it\n' "$name" >&2
    return 65
  fi
  ho_ledger_append session-task-ended name "$name" role "$role"
  ho_session_close "$name"
}

ho_life_usage() {
  cat >&2 <<'USAGE'
usage: harness lifecycle <run-dir> <verb>
  check        decide what the run does now and act on it; first line of output:
               work, stopping, wait-review, wait-blocked, standby, end, ended or unknown (exit 2)
  done <name>  the task of that session ended: record it and close the session (never the
               orchestrator or the watcher, never a session of another run)
settings: run.standby (true|false, default false; "run new --standby on|off" for one run),
          run.on_only_human_blocked (wait|end, default wait)
USAGE
}

ho_life_main() {
  [ $# -ge 2 ] || { ho_life_usage; exit 64; }
  ho_run_open "$1"
  local verb=$2 rc=0
  shift 2
  ho_session_bind_project || exit $?
  case $verb in
    # A reader that stops after the first line must not end the sweep half way.
    check) trap '' PIPE; HO_LIFE_OUT=""; ho_life_check || rc=$?; ho_life_flush ;;
    done) ho_life_done "$@" || rc=$? ;;
    *) ho_life_usage; rc=64 ;;
  esac
  exit "$rc"
}
