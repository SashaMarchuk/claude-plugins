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

# Newest stop or resume event: "stop", "resume" or "" (none).
ho_last_stop_event() {
  ho_ledger_events | jq -r 'select(.kind == "stop" or .kind == "resume") | .kind' | tail -n 1
}

# ho_stopped: 0 stopped, 1 not stopped, 2 unknown. An unreadable ledger line makes the state
# unknown (never "not stopped") until a later stop or resume line makes it known again.
ho_stopped() {
  local state
  if [ -e "$(ho_stop_file)" ]; then
    [ "$(ho_last_stop_event)" = stop ] || ho_ledger_append stop source file type soft:step reason "STOP file"
    return 0
  fi
  # One jq pass reads the whole ledger, so no early-closing reader can hide a bad line.
  state=$(ho_ledger_events | jq -rn 'reduce inputs as $e ("none";
      if $e.kind == "unreadable" then "unknown"
      elif $e.kind == "stop" then "stop"
      elif $e.kind == "resume" then "none"
      else . end)') || state=unknown
  case $state in
    stop) return 0 ;;
    none) return 1 ;;
  esac
  printf 'harness: run ledger %s/ledger.jsonl has an unreadable line after the last stop or resume; stop state unknown. Record a stop or resume to continue.\n' "$HO_RUN_DIR" >&2
  return 2
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

# ho_workers_arg <value>: check a --workers value.
ho_workers_arg() {
  case ${1-} in
    '' | *[!0-9]* | 0 | 0*) printf 'harness: --workers must be a whole number of at least 1, not %s\n' "${1-}" >&2; return 64 ;;
  esac
}

# ho_run_new [--workers N]: the worker cap given at launch beats the config (H-104).
ho_run_new() {
  local proj runs id dir tries=0 workers=""
  while [ $# -gt 0 ]; do
    case $1 in
      --workers) [ $# -ge 2 ] || { echo "harness: --workers needs a number" >&2; exit 64; }; workers=$2; shift 2 ;;
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
  jq -n --argjson schema "$HO_RUN_SCHEMA" --arg engine "$HO_ENGINE" --arg id "$id" --arg ts "$(ho_now)" \
    '{schemaVersion: $schema, engine: $engine, runId: $id, created: $ts}' | ho_atomic_write "$dir/run.json" || exit 1
  HO_RUN_DIR=$dir
  HO_RUN_DIR_PHYS=""
  HO_RUN_ID=$id
  ho_ledger_append run-start
  printf '%s\n' "$dir"
}

ho_state_usage() {
  cat >&2 <<'USAGE'
usage: harness state <run-dir> <verb> [args]
  check                                   check the run stamp
  marker set|check|clear <name>           markers carry the run ID
  decision <title> <reason>               append a decision to the run ledger
  owner-action <title> <why> <command> <verify>
  stop [reason]                           record a default soft stop
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
    stop) ho_ledger_append stop source verb type soft:step reason "${*:-stop requested}" ;;
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
