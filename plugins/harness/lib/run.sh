# shellcheck shell=bash
# Run state: the stamp, the append-only run ledger and markers that carry the run ID.
# Design "Rebuild": the STOP file, decision log and owner-action log are merged into one
# append-only run ledger, and every marker carries the run ID (S8-27). A run folder without
# a valid stamp (a 0.6.0 run, or anything else) is refused before any write (exit 66).
#
#   <project>/.harness/runs/<run-id>/run.json        stamp, written once
#   <project>/.harness/runs/<run-id>/ledger.jsonl    one JSON object per line, append only
#   <project>/.harness/runs/<run-id>/markers/<name>  one JSON object: {run, name, ts}
#   <project>/.harness/STOP                          kept for users; recorded in the ledger
#
# Requires lib/files.sh and lib/config.sh.

HO_ENGINE=harness-orchestrator
HO_RUN_SCHEMA=2
HO_EXIT_REFUSED=66
HO_EXIT_STOPPED=75
HO_LEDGER_MAX=4000

ho_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

ho_run_id_new() {
  printf '%s-%s\n' "$(date -u '+%Y%m%d-%H%M%S')" "$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n')"
}

# ho_run_open <run-dir>: check the stamp; on success set HO_RUN_DIR and HO_RUN_ID.
# Writes nothing. On any problem: print why and exit 66.
ho_run_open() {
  local dir=${1-} id why=""
  # The STOP file is found from the run folder, so a bare run ID or ./<id> must become
  # an absolute path first, or a run started inside .harness/runs would miss STOP.
  # Both the logical path (as given, made absolute) and the physical path (links
  # resolved) are kept: a STOP file beside either one stops the run, so neither a
  # linked runs folder nor a linked path to it can hide STOP.
  HO_RUN_DIR_PHYS=""
  if [ -n "$dir" ] && [ -d "$dir" ]; then
    HO_RUN_DIR_PHYS=$(cd -P "$dir" && pwd -P) || HO_RUN_DIR_PHYS=""
    dir=$(cd "$dir" && pwd) || dir=${1-}
  fi
  id=$(basename "$dir")
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    why="no such run folder"
  elif [ ! -f "$dir/run.json" ]; then
    why="it has no run.json stamp (a 0.6.0 run, or not a run of this engine)"
  elif [ -L "$dir/run.json" ] || [ -L "$dir/ledger.jsonl" ] || [ -L "$dir/markers" ]; then
    why="its run.json, ledger.jsonl or markers is a link (a run folder must hold plain files)"
  elif ! jq -e --arg id "$id" --arg engine "$HO_ENGINE" --argjson schema "$HO_RUN_SCHEMA" \
      'type == "object" and .schemaVersion == $schema and .engine == $engine and .runId == $id' \
      "$dir/run.json" >/dev/null 2>&1; then
    why="its run.json stamp is not a schemaVersion 2 stamp for run $id"
  fi
  if [ -n "$why" ]; then
    printf 'harness: refusing run folder %s: %s. Nothing was changed.\n' "$dir" "$why" >&2
    exit "$HO_EXIT_REFUSED"
  fi
  HO_RUN_DIR=$dir
  HO_RUN_ID=$id
}

# ho_stop_file: the first STOP file that exists beside the logical or the physical run path, or in the current project;
# with none, the place beside the logical run path (where a STOP would be written).
ho_stop_file() {
  local d f
  for d in "$HO_RUN_DIR" ${HO_RUN_DIR_PHYS:+"$HO_RUN_DIR_PHYS"}; do
    f="$(dirname "$(dirname "$d")")/STOP"
    [ -e "$f" ] && { printf '%s\n' "$f"; return 0; }
  done
  # The project the engine runs in counts too: its runs folder may be a link elsewhere.
  if d=$(ho_project_root 2>/dev/null); then
    f="$d/.harness/STOP"
    [ -e "$f" ] && { printf '%s\n' "$f"; return 0; }
  fi
  printf '%s/STOP\n' "$(dirname "$(dirname "$HO_RUN_DIR")")"
}

# ho_ledger_append <kind> [<key> <value>]...: append one line. Never rewrites the file.
ho_ledger_append() {
  local kind=$1 line f="$HO_RUN_DIR/ledger.jsonl"
  local -a args
  args=(--arg ts "$(ho_now)" --arg run "$HO_RUN_ID" --arg kind "$kind")
  shift
  while [ $# -ge 2 ]; do
    args+=(--arg "$1" "$2")
    shift 2
  done
  line=$(jq -cn "${args[@]}" '$ARGS.named') || { echo "harness: cannot build a ledger line" >&2; exit 1; }
  if [ "${#line}" -gt "$HO_LEDGER_MAX" ]; then
    printf 'harness: ledger line for %s is %s bytes; the limit is %s\n' "$kind" "${#line}" "$HO_LEDGER_MAX" >&2
    exit 65
  fi
  # bash may split one printf into several writes, so parallel writers take a lock.
  ho_ledger_lock "$f.lock"
  # Never append through a link: the ledger must be a plain file of this run.
  if [ -L "$f" ]; then
    ho_ledger_unlock
    echo "harness: the run ledger is a link; refusing to append" >&2
    exit "$HO_EXIT_REFUSED"
  fi
  # A signal frees the lock and ends the process: after the lock is gone this writer
  # must not append.
  trap 'rm -rf "$HO_LEDGER_LOCK"; exit 130' INT
  trap 'rm -rf "$HO_LEDGER_LOCK"; exit 143' TERM
  trap 'rm -rf "$HO_LEDGER_LOCK"; exit 129' HUP
  # A torn last line (a writer killed mid-append) must not swallow this one.
  if [ -s "$f" ] && [ -n "$(tail -c 1 "$f")" ]; then
    line=$'\n'"$line"
  fi
  if ! printf '%s\n' "$line" >> "$f"; then
    ho_ledger_unlock
    echo "harness: cannot append to the run ledger" >&2
    exit 1
  fi
  ho_ledger_unlock
}

ho_ledger_unlock() {
  rm -rf "$HO_LEDGER_LOCK"
  trap - INT TERM HUP
}

# ho_ledger_lock <dir>: mkdir lock with the holder's PID inside. A lock whose holder is dead
# is taken over at once. A lock with no PID file (holder killed between mkdir and writing
# the PID) counts as stale after one minute. No lock after 90 s is an error.
# Known gap: two waiters that see the same dead holder at the same instant can race.
ho_ledger_lock() {
  local lock=$1 n=0 pid
  HO_LEDGER_LOCK=$lock
  until mkdir "$lock" 2>/dev/null; do
    pid=$(cat "$lock/pid" 2>/dev/null || true)
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      [ "$(cat "$lock/pid" 2>/dev/null || true)" = "$pid" ] && rm -rf "$lock"
      continue
    fi
    if [ -z "$pid" ] && [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
      rm -rf "$lock"
      continue
    fi
    n=$((n + 1))
    if [ "$n" -ge 1800 ]; then
      printf 'harness: run ledger is locked (%s); not written\n' "$lock" >&2
      exit 1
    fi
    sleep 0.05
  done
  printf '%s\n' "$$" > "$lock/pid"
}

# ho_ledger_events: print each non-empty ledger line as compact JSON; an unparsable line becomes
# {"kind":"unreadable"} so callers can tell "unreadable" from "nothing there".
ho_ledger_events() {
  local f="$HO_RUN_DIR/ledger.jsonl"
  [ -f "$f" ] || return 0
  jq -cR 'select(length > 0) | (fromjson? | select(type == "object")) // {"kind":"unreadable"}' "$f"
}

# Soft stops (H-086, design D25, D25a, D25b). A stop line carries its variant (`type`), the
# tickets it lets finish (`tickets`: "all" or a space list, soft:ticket only) and a stop id. The
# newest stop since the last resume is the one in force. While the STOP file exists the run is at
# least as strict as soft:step: a looser stop in force (soft:ticket) or none at all makes the next
# check record one soft:step line from the file.
#   soft:step    the current step finishes; no new step and no new ticket (the default)
#   soft:task    the same for the engine; its stop text asks the session to stop after its
#                current task inside the step
#   soft:ticket  a ticket that began before the stop may begin its next steps and merge; the
#                other tickets get soft:step; no new ticket begins
HO_STOP_TYPES="soft:step soft:task soft:ticket"
HO_STOP_HARD_TYPES="hard:message hard:now"

# ho_stop_info: one jq pass over the whole ledger, so no early-closing reader can hide a bad line.
# Prints <state>|<type>|<tickets>|<stop id>|<tickets begun before the stop> (| never collapses
# empty fields, as a tab would).
# state: none, stop or unknown (an unreadable line after the last stop or resume).
ho_stop_info() {
  ho_ledger_events | jq -rn 'reduce inputs as $e ({state: "none", type: "", scope: "", id: "", begun: [], seen: []};
      if $e.kind == "unreadable" then .state = "unknown"
      elif $e.kind == "stop" then
        (if .state == "stop" then . else .begun = .seen end)
        | .state = "stop" | .type = ($e.type // "soft:step") | .scope = ($e.tickets // "all") | .id = ($e.stop_id // "")
      elif $e.kind == "resume" then .state = "none" | .type = "" | .scope = "" | .id = "" | .begun = []
      elif $e.kind == "step-begin" or $e.kind == "pickup" or ($e.kind == "session-launch" and ($e.ticket // "") != "") then .seen += [($e.ticket // "" | tostring)]
      else . end)
    | [.state, .type, .scope, .id, (.begun | unique | join(" "))] | map(gsub("[|\\n]"; " ")) | join("|")'
}

# ho_stop_read: set HO_STOP_STATE, HO_STOP_TYPE, HO_STOP_TICKETS, HO_STOP_ID and HO_STOP_BEGUN.
ho_stop_read() {
  local info
  info=$(ho_stop_info) || info=unknown
  IFS='|' read -r HO_STOP_STATE HO_STOP_TYPE HO_STOP_TICKETS HO_STOP_ID HO_STOP_BEGUN <<EOF_STOP
$info
EOF_STOP
  case ${HO_STOP_STATE-} in none | stop) ;; *) HO_STOP_STATE=unknown ;; esac
}

# ho_stopped: 0 stopped, 1 not stopped, 2 unknown. An unreadable ledger line makes the state
# unknown (never "not stopped") until a later stop or resume line makes it known again.
ho_stopped() {
  ho_stop_read
  if [ -e "$(ho_stop_file)" ]; then
    # D25b: the file applies soft:step. It is recorded when no stop is in force, when the state
    # is unknown, or when the stop in force is looser; a stricter stop (soft:task) stays.
    if [ "$HO_STOP_STATE" != stop ] || [ "$HO_STOP_TYPE" = soft:ticket ]; then
      ho_ledger_append stop source file type soft:step tickets all stop_id "$(ho_stop_id_new)" reason "STOP file"
    fi
    return 0
  fi
  case $HO_STOP_STATE in
    stop) return 0 ;;
    none) return 1 ;;
  esac
  printf 'harness: run ledger %s/ledger.jsonl has an unreadable line after the last stop or resume; stop state unknown. Record a stop or resume to continue.\n' "$HO_RUN_DIR" >&2
  return 2
}

# ho_run_ended: 0 when the run has ended (H-079, D37-LIFECYCLE-3): its newest run-end line is
# newer than its newest resume line. 1 otherwise. Only "state <run> resume" opens an ended run
# again. The session launch reads it; lib/lifecycle.sh decides the run end.
ho_run_ended() {
  [ "$(ho_ledger_events | jq -r 'select(.kind == "run-end" or .kind == "resume") | .kind' | tail -n 1)" = run-end ]
}

ho_stop_id_new() { printf 'stop-%s\n' "$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"; }

# ho_stop_gate [ticket]: may new work of this ticket start? 0 yes (no stop, or a soft:ticket stop
# that covers a ticket begun before it), 75 no, 2 the stop state is unknown. Work that names no
# ticket counts as new work. An ended run (ho_run_ended) starts nothing new either (75, H-079),
# until "state <run> resume" opens it again.
ho_stop_gate() {
  local t=${1-} st=0
  ! ho_run_ended || { echo "harness: the run has ended; nothing new starts (record a resume to open it again)" >&2; return 75; }
  ho_stopped || st=$?
  case $st in 1) return 0 ;; 2) return 2 ;; esac
  ho_stop_read
  [ "$HO_STOP_TYPE" = soft:ticket ] && [ -n "$t" ] || return 75
  case " $HO_STOP_TICKETS " in *" all "* | *" $t "*) ;; *) return 75 ;; esac
  case " $HO_STOP_BEGUN " in *" $t "*) return 0 ;; esac
  return 75
}

# ho_stop_gate_soft: may a session that already runs keep finishing its work (a heavy or stage
# slot)? 0 with no stop or a soft stop, 75 otherwise, 2 unknown (D25a). An ended run has no work
# left to finish (75, H-079).
ho_stop_gate_soft() {
  local st=0
  ! ho_run_ended || { echo "harness: the run has ended; no work goes on (record a resume to open it again)" >&2; return 75; }
  ho_stopped || st=$?
  case $st in 1) return 0 ;; 2) return 2 ;; esac
  ho_stop_read
  case " $HO_STOP_TYPES " in *" $HO_STOP_TYPE "*) return 0 ;; esac
  return 75
}

# ho_stop_ticket_arg <value>: a ticket id read in base 10 (at most 9 digits), or exit 64.
ho_stop_ticket_arg() {
  case ${1-} in '' | *[!0-9]*) printf 'harness: a ticket id must be a number, not %s\n' "${1-}" >&2; return 64 ;; esac
  [ "${#1}" -le 9 ] || { printf 'harness: a ticket id has at most 9 digits: %s\n' "$1" >&2; return 64; }
  printf '%s\n' "$((10#$1))"
}

# The standard stop text of each variant. It names no step of any flow (D2): step names come
# from the flow.
ho_stop_text() {
  case $1 in
    soft:step) echo "Soft stop: finish the step you are on now, write its result, then end your turn. Start no new step and no new ticket." ;;
    soft:task) echo "Soft stop: finish the task you are working on now inside your current step, commit it, write your step result with what is done and what is left, then end your turn. Start no new task, step or ticket." ;;
    soft:ticket) echo "Soft stop: finish the ticket you are working on through its remaining steps. No new ticket starts." ;;
  esac
}

# state <run> stop [--type T] [--ticket ID]... [--message TEXT] [--service-down] [reason...]:
# record a stop. A soft stop's text is printed for the caller to deliver (session deliver --id
# <stop id>); the verb sends nothing then. A hard stop is acted on at once (lib/stop.sh). The own
# message (--message, D37-LIFECYCLE-5) is added word for word after the standard line, as one
# line, and written once to the run ledger. --service-down goes with hard:message only.
ho_state_stop() {
  local type=soft:step tickets="" t id scope reason own="" have_own=0 down=0
  while [ $# -gt 0 ]; do
    case $1 in
      --type) [ $# -ge 2 ] || { ho_state_usage; return 64; }; type=$2; shift 2 ;;
      --ticket)
        [ $# -ge 2 ] || { ho_state_usage; return 64; }
        t=$(ho_stop_ticket_arg "$2") || return 64
        tickets="$tickets $t"
        shift 2
        ;;
      --message) [ $# -ge 2 ] || { ho_state_usage; return 64; }; own=$(ho_stop_own_text "$2"); have_own=1; shift 2 ;;
      --service-down) down=1; shift ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
  case $type in
    soft:step | soft:task | soft:ticket | hard:message | hard:now) ;;
    *) printf 'harness: unknown stop type %s (one of: %s %s)\n' "$type" "$HO_STOP_TYPES" "$HO_STOP_HARD_TYPES" >&2; return 64 ;;
  esac
  [ -z "$tickets" ] || [ "$type" = soft:ticket ] || { echo "harness: --ticket goes only with --type soft:ticket" >&2; return 64; }
  [ "$down" -eq 0 ] || [ "$type" = hard:message ] || { echo "harness: --service-down goes only with --type hard:message" >&2; return 64; }
  [ "$have_own" -eq 0 ] || [ -n "${own// /}" ] || { echo "harness: --message needs some text" >&2; return 64; }
  scope=all
  [ -z "$tickets" ] || scope=$(printf '%s\n' $tickets | sort -n -u | tr '\n' ' ' | sed 's/ $//')
  reason=${*:-stop requested}
  id=$(ho_stop_id_new)
  if [ -n "$own" ]; then
    ho_ledger_append stop source verb type "$type" tickets "$scope" stop_id "$id" reason "$reason" own_message "$own"
  else
    ho_ledger_append stop source verb type "$type" tickets "$scope" stop_id "$id" reason "$reason"
  fi
  printf 'stop %s %s tickets %s\n' "$id" "$type" "$scope"
  case $type in hard:*) ho_stop_hard "$type" "$id" "$own" "$down"; return $? ;; esac
  local tail=""
  [ -z "$own" ] || tail=" $own"
  if [ "$type" = soft:ticket ] && [ "$scope" != all ]; then
    printf 'text (tickets %s): %s%s\n' "$scope" "$(ho_stop_text soft:ticket)" "$tail"
    printf 'text (other tickets): %s%s\n' "$(ho_stop_text soft:step)" "$tail"
  else
    printf 'text: %s%s\n' "$(ho_stop_text "$type")" "$tail"
  fi
  printf 'note: the stop text is not delivered by this verb; send it to each session the stop covers with "session deliver <name> --id %s".\n' "$id"
}

# state <run> stop-state: the stop in force as one JSON line; exit as "stopped".
ho_state_stop_state() {
  local rc=0
  ho_stopped 2>/dev/null || rc=$?
  ho_stop_read
  [ "$rc" -ne 2 ] || HO_STOP_STATE=unknown
  jq -cn --arg state "$HO_STOP_STATE" --arg type "$HO_STOP_TYPE" --arg tickets "$HO_STOP_TICKETS" --arg id "$HO_STOP_ID" \
    '{state: $state, type: $type, tickets: $tickets, stop_id: $id}'
  return "$rc"
}

# state <run> begin --ticket T --step S: the step gate (D25a). The caller asks before it starts a
# step of a ticket; 0 and one step-begin line, or 75 when a stop lets nothing new start (also
# when the stop state is unknown). The step id is data from the flow. A ticket also counts as
# begun when a session of it launched (session launch --ticket) or intake claimed it (its pickup
# line) before the stop, so a ticket claimed just before a soft:ticket stop is not stranded.
ho_state_begin() {
  local t="" s="" rc=0
  while [ $# -gt 0 ]; do
    case $1 in
      --ticket | --step)
        [ $# -ge 2 ] || { ho_state_usage; return 64; }
        if [ "$1" = --ticket ]; then t=$(ho_stop_ticket_arg "$2") || return 64; else s=$2; fi
        shift 2
        ;;
      *) printf 'harness: unknown begin argument %s\n' "$1" >&2; return 64 ;;
    esac
  done
  [ -n "$t" ] && [ -n "$s" ] || { ho_state_usage; return 64; }
  printf '%s' "$s" | grep -Eqx '[a-z0-9][a-z0-9-]{0,39}' || { printf 'harness: a step id uses a-z 0-9 - (at most 40), not %s\n' "$s" >&2; return 64; }
  # A lane paused for an urgent ticket begins no next step until intake lets it go (H-084, D3).
  if [ -f "$HO_RUN_DIR/pauses/$t.json" ]; then
    printf 'harness: ticket %s is paused for urgent ticket %s; step %s does not begin\n' "$t" \
      "$(jq -r '.for // "?"' "$HO_RUN_DIR/pauses/$t.json" 2>/dev/null)" "$s" >&2
    return 75
  fi
  ho_stop_gate "$t" || rc=$?
  case $rc in
    0)
      ho_ledger_append step-begin ticket "$t" step "$s"
      printf 'OK ticket %s step %s may begin\n' "$t" "$s"
      ho_state_notes "$t"
      ;;
    2) printf 'harness: the stop state is unknown; ticket %s step %s does not begin\n' "$t" "$s" >&2; return 75 ;;
    *) printf 'harness: the run is stopped (%s); ticket %s step %s does not begin\n' "${HO_STOP_TYPE:-stop}" "$t" "$s" >&2; return 75 ;;
  esac
}

# ho_state_notes <ticket>: hand each accepted ticket change (intake, H-023, D37-INTAKE-3) to the
# step that begins, once: one "change <note-file>" line each, oldest first, and one
# change-delivered ledger line. The orchestrator gives the note to the worker and returns the
# ticket to its execution step (D37-INTAKE-6).
ho_state_notes() {
  local d="$HO_RUN_DIR/notes/$1" f
  [ -d "$d" ] || return 0
  for f in $(cd "$d" && ls | grep -E '^[0-9]+\.md$' | sort -n); do
    ho_ledger_events | jq -e --arg n "$d/$f" 'select(.kind == "change-delivered" and .note == $n)' >/dev/null 2>&1 && continue
    ho_ledger_append change-delivered ticket "$1" note "$d/$f"
    printf 'change %s\n' "$d/$f"
  done
}

ho_marker_name_ok() {
  case ${1-} in
    '' | .* | *[!a-z0-9.-]*) printf 'harness: marker name must use a-z 0-9 . - and not start with a dot: %s\n' "${1-}" >&2; exit 65 ;;
  esac
}

# ho_marker_owner <file>: the run ID inside a marker, or "unreadable".
ho_marker_owner() {
  jq -er 'select(type == "object") | .run | strings' "$1" 2>/dev/null || echo unreadable
}

# Log a foreign marker once per name (PR-1); a later check does not add another line.
ho_marker_foreign() {
  local name=$1 owner=$2
  ho_ledger_events | jq -e --arg n "$name" 'select(.kind == "marker-foreign" and .name == $n)' >/dev/null 2>&1 && return 0
  ho_ledger_append marker-foreign name "$name" found "$owner"
  printf 'harness: marker %s belongs to run %s, not %s; ignored\n' "$name" "$owner" "$HO_RUN_ID" >&2
}

ho_marker() {
  local sub=${1-} name=${2-} f owner
  ho_marker_name_ok "$name"
  f="$HO_RUN_DIR/markers/$name"
  case $sub in
    set)
      # Ledger line first: a marker must never exist without its ledger line.
      ho_ledger_append marker-set name "$name"
      mkdir -p "$HO_RUN_DIR/markers"
      jq -cn --arg run "$HO_RUN_ID" --arg name "$name" --arg ts "$(ho_now)" '$ARGS.named' | ho_atomic_write "$f" || exit 1
      ;;
    check | clear)
      if [ ! -f "$f" ]; then
        [ "$sub" = clear ] && return 0
        return 1
      fi
      owner=$(ho_marker_owner "$f")
      if [ "$owner" != "$HO_RUN_ID" ]; then
        ho_marker_foreign "$name" "$owner"
        return 1
      fi
      if [ "$sub" = clear ]; then
        rm -f "$f"
        ho_ledger_append marker-clear name "$name"
      fi
      return 0
      ;;
    *) echo "usage: harness state <run-dir> marker set|check|clear <name>" >&2; exit 64 ;;
  esac
}

# ho_run_new: create and stamp a run under the current project; print its folder.
# Run limits (H-104, H-107, D26): read once at run start into <run>/limits.json; lib/slots.sh
# enforces them.
# ho_limit_value <jq-path> <default> <what>: a whole number of at least 1 from the config.
ho_limit_value() {
  local v
  v=$(ho_cfg "$1" "$2") || exit $?
  case $v in
    '' | *[!0-9]* | 0 | 0*) printf 'harness: config %s=%s: %s must be a whole number of at least 1\n' "$1" "$v" "$3" >&2; return 78 ;;
  esac
  printf '%s\n' "$((10#$v))"
}

# ho_limits_stamp <run-dir> <workers-from-launch>: write limits.json once. A launch value beats
# the config, which beats the default of 1.
ho_limits_stamp() {
  local dir=$1 workers=$2 heavy stages
  if [ -z "$workers" ]; then workers=$(ho_limit_value '.limits.workers' 1 'the worker cap') || return 78; fi
  heavy=$(ho_limit_value '.limits.heavy' 1 'the heavy-work limit') || return 78
  stages=$(ho_cfg '.limits.stages | tojson' 'null') || return 78
  [ "$stages" = null ] && stages='{}'
  printf '%s' "$stages" | jq -e 'type == "object" and all(to_entries[]; (.key | test("^[a-z][a-z0-9-]{0,39}$")) and (.value | type == "number" and . >= 1 and . == floor))' >/dev/null 2>&1 || {
    printf 'harness: config limits.stages must map stage ids (a-z 0-9 -) to whole numbers of at least 1\n' >&2
    return 78
  }
  jq -n --argjson w "$workers" --argjson h "$heavy" --argjson s "$stages" \
    '{schemaVersion: 2, workers: $w, heavy: $h, stages: ({browser: 1} + $s)}' | ho_atomic_write "$dir/limits.json"
}

# Lifecycle settings (H-079, S8-20a, OPEN-9): read once at run start into <run>/lifecycle.json;
# lib/lifecycle.sh acts on them.
# ho_life_stamp <run-dir> <standby flag: on, off or empty>: write lifecycle.json once.
ho_life_stamp() {
  local dir=$1 flag=$2 standby source onb
  standby=$(ho_cfg '.run.standby' 'false') || return 78
  source=config
  [ "$(ho_cfg '.run.standby' '__unset__')" != __unset__ ] || source=default
  case $standby in
    true | false) ;;
    *) printf 'harness: config run.standby=%s: it must be true or false\n' "$standby" >&2; return 78 ;;
  esac
  case $flag in
    on) standby=true; source=flag ;;
    off) standby=false; source=flag ;;
  esac
  onb=$(ho_cfg '.run.on_only_human_blocked' 'wait') || return 78
  case $onb in
    wait | end) ;;
    *) printf 'harness: config run.on_only_human_blocked=%s: it must be wait or end\n' "$onb" >&2; return 78 ;;
  esac
  jq -n --argjson s "$standby" --arg src "$source" --arg onb "$onb" \
    '{schemaVersion: 2, standby: $s, standby_source: $src, on_only_human_blocked: $onb}' | ho_atomic_write "$dir/lifecycle.json"
}

# ho_life_standby_arg <value>: check a --standby value.
ho_life_standby_arg() {
  case ${1-} in
    on | off) ;;
    *) printf 'harness: --standby must be on or off, not %s\n' "${1-}" >&2; return 64 ;;
  esac
}

# ho_workers_arg <value>: check a --workers value.
ho_workers_arg() {
  case ${1-} in
    '' | *[!0-9]* | 0 | 0*) printf 'harness: --workers must be a whole number of at least 1, not %s\n' "${1-}" >&2; return 64 ;;
  esac
}

# ho_run_new [--workers N] [--standby on|off]: the worker cap given at launch beats the config
# (H-104); so does the standby flag (OPEN-9).
ho_run_new() {
  local proj runs id dir tries=0 workers="" standby=""
  while [ $# -gt 0 ]; do
    case $1 in
      --workers) [ $# -ge 2 ] || { echo "harness: --workers needs a number" >&2; exit 64; }; workers=$2; shift 2 ;;
      --standby) [ $# -ge 2 ] || { echo "harness: --standby needs on or off" >&2; exit 64; }; ho_life_standby_arg "$2" || exit 64; standby=$2; shift 2 ;;
      *) printf 'harness: unknown run new argument %s\n' "$1" >&2; exit 64 ;;
    esac
  done
  [ -z "$workers" ] || ho_workers_arg "$workers" || exit 64
  [ -z "$workers" ] || workers=$((10#$workers))
  ho_config_files >/dev/null || exit $?
  proj=$(ho_project_root) || { echo "harness: no project here (no .harness/config.json); run setup first" >&2; exit "$HO_EXIT_CONFIG"; }
  if [ -e "$proj/.harness/STOP" ]; then
    printf 'harness: %s/.harness/STOP exists; remove it to start a run\n' "$proj" >&2
    exit "$HO_EXIT_STOPPED"
  fi
  # D37-FLOW-8: a project config that holds an out-of-memory check command is refused at start.
  ho_res_project_cmd_check || exit 78
  runs="$proj/.harness/runs"
  mkdir -p "$runs"
  while :; do
    id=$(ho_run_id_new)
    dir="$runs/$id"
    mkdir "$dir" 2>/dev/null && break
    tries=$((tries + 1))
    [ "$tries" -lt 5 ] || { echo "harness: cannot create a run folder in $runs" >&2; exit 1; }
  done
  mkdir "$dir/markers"
  # Limits are fixed for the run before the stamp is written: a run never starts without them.
  ho_limits_stamp "$dir" "$workers" || { local rc=$?; rm -rf "$dir"; exit "$rc"; }
  # Standby and on_only_human_blocked (H-079, S8-20a, OPEN-9) are fixed for the run as well.
  ho_life_stamp "$dir" "$standby" || { local rc=$?; rm -rf "$dir"; exit "$rc"; }
  jq -n --argjson schema "$HO_RUN_SCHEMA" --arg engine "$HO_ENGINE" --arg id "$id" --arg ts "$(ho_now)" \
    '{schemaVersion: $schema, engine: $engine, runId: $id, created: $ts}' | ho_atomic_write "$dir/run.json" || exit 1
  HO_RUN_DIR=$dir
  HO_RUN_DIR_PHYS=""
  HO_RUN_ID=$id
  ho_ledger_append run-start
  ho_ledger_append run-settings standby "$(jq -r .standby "$dir/lifecycle.json")" \
    standby_source "$(jq -r .standby_source "$dir/lifecycle.json")" on_only_human_blocked "$(jq -r .on_only_human_blocked "$dir/lifecycle.json")"
  printf '%s\n' "$dir"
}

ho_state_usage() {
  cat >&2 <<'USAGE'
usage: harness state <run-dir> <verb> [args]
  check                                   check the run stamp
  marker set|check|clear <name>           markers carry the run ID
  decision <title> <reason>               append a decision to the run ledger
  owner-action <title> <why> <command> <verify>
  stop [--type soft:step|soft:task|soft:ticket] [--ticket ID]... [--message TEXT] [reason]
                                          record a soft stop (default soft:step); prints its
                                          stop id and text, which it does not deliver
  stop --type hard:message|hard:now [--message TEXT] [--service-down] [reason]
                                          a hard stop, acted on at once: hard:message sends
                                          the stop line and escalates a session that does not
                                          park in time; hard:now force-closes by exact PID
  stop-state                              the stop in force, one JSON line
  begin --ticket T --step S               the step gate: 0 may begin, 75 a stop refuses it
  resume                                  record a resume (refused while the STOP file exists)
  stopped                                 exit 0 stopped, 1 not stopped, 2 unknown
USAGE
}

# harness state <run-dir> <verb> [args]: the stamp is checked before anything else.
ho_state_main() {
  [ $# -ge 2 ] || { ho_state_usage; exit 64; }
  ho_run_open "$1"
  local verb=$2
  shift 2
  case $verb in
    check) printf 'run %s OK\n' "$HO_RUN_ID" ;;
    marker) ho_marker "$@" ;;
    decision)
      [ $# -ge 2 ] || { ho_state_usage; exit 64; }
      ho_ledger_append decision title "$1" reason "${*:2}"
      ;;
    owner-action)
      [ $# -eq 4 ] || { ho_state_usage; exit 64; }
      ho_ledger_append owner-action title "$1" why "$2" command "$3" verify "$4"
      ;;
    stop) ho_state_stop "$@" || exit $? ;;
    stop-state) ho_state_stop_state || exit $? ;;
    begin) ho_state_begin "$@" || exit $? ;;
    resume)
      if [ -e "$(ho_stop_file)" ]; then
        printf 'harness: %s exists; remove it before resuming\n' "$(ho_stop_file)" >&2
        exit "$HO_EXIT_STOPPED"
      fi
      ho_ledger_append resume
      ;;
    stopped) ho_stopped ;;
    *) ho_state_usage; exit 64 ;;
  esac
}
