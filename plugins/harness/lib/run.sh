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

# ho_run_open <run-dir> — check the stamp; on success set HO_RUN_DIR and HO_RUN_ID.
# Writes nothing. On any problem: print why and exit 66.
ho_run_open() {
  local dir=${1-} id why=""
  id=$(basename "$dir")
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    why="no such run folder"
  elif [ ! -f "$dir/run.json" ]; then
    why="it has no run.json stamp (a 0.6.0 run, or not a run of this engine)"
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

ho_stop_file() { printf '%s/STOP\n' "$(dirname "$(dirname "$HO_RUN_DIR")")"; }

# ho_ledger_append <kind> [<key> <value>]... — append one line. Never rewrites the file.
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
  # A torn last line (a writer killed mid-append) must not swallow this one.
  if [ -s "$f" ] && [ -n "$(tail -c 1 "$f")" ]; then
    line=$'\n'"$line"
  fi
  if ! printf '%s\n' "$line" >> "$f"; then
    rmdir "$f.lock" 2>/dev/null
    echo "harness: cannot append to the run ledger" >&2
    exit 1
  fi
  rmdir "$f.lock" 2>/dev/null || true
}

# ho_ledger_lock <dir> — mkdir lock. A lock older than one minute is left by a killed
# writer (an append takes milliseconds) and is removed. No lock after 30 s is an error.
ho_ledger_lock() {
  local lock=$1 n=0
  until mkdir "$lock" 2>/dev/null; do
    if [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
      rmdir "$lock" 2>/dev/null || true
      continue
    fi
    n=$((n + 1))
    if [ "$n" -ge 600 ]; then
      printf 'harness: run ledger is locked (%s); not written\n' "$lock" >&2
      exit 1
    fi
    sleep 0.05
  done
}

# ho_ledger_events — print each non-empty ledger line as compact JSON; an unparsable line becomes
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

# ho_stopped — 0 stopped, 1 not stopped, 2 unknown (unreadable ledger; never read as "not stopped").
ho_stopped() {
  if [ -e "$(ho_stop_file)" ]; then
    [ "$(ho_last_stop_event)" = stop ] || ho_ledger_append stop source file type soft:step reason "STOP file"
    return 0
  fi
  if ho_ledger_events | grep -q '^{"kind":"unreadable"}$'; then
    printf 'harness: run ledger %s/ledger.jsonl has an unreadable line; stop state unknown\n' "$HO_RUN_DIR" >&2
    return 2
  fi
  [ "$(ho_last_stop_event)" = stop ]
}

ho_marker_name_ok() {
  case ${1-} in
    '' | .* | *[!a-z0-9.-]*) printf 'harness: marker name must use a-z 0-9 . - and not start with a dot: %s\n' "${1-}" >&2; exit 65 ;;
  esac
}

# ho_marker_owner <file> — the run ID inside a marker, or "unreadable".
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
      mkdir -p "$HO_RUN_DIR/markers"
      jq -cn --arg run "$HO_RUN_ID" --arg name "$name" --arg ts "$(ho_now)" '$ARGS.named' | ho_atomic_write "$f" || exit 1
      ho_ledger_append marker-set name "$name"
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

# ho_run_new — create and stamp a run under the current project; print its folder.
ho_run_new() {
  local proj runs id dir tries=0
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
  jq -n --argjson schema "$HO_RUN_SCHEMA" --arg engine "$HO_ENGINE" --arg id "$id" --arg ts "$(ho_now)" \
    '{schemaVersion: $schema, engine: $engine, runId: $id, created: $ts}' | ho_atomic_write "$dir/run.json" || exit 1
  HO_RUN_DIR=$dir
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

# harness state <run-dir> <verb> [args] — the stamp is checked before anything else.
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
