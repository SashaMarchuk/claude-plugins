# shellcheck shell=bash
# Slots: the worker cap, the heavy-work slot and stage limits, enforced by the engine.
# H-104: the worker cap is set before launch (run new --workers N) or in the config
# (limits.workers); default 1, minimum 1, no shipped maximum. H-105 and D26a: a start takes a
# slot under one lock and the count is checked inside it; when two starts race for the last
# slot, one gets it and the other waits. H-107 and D26: one heavy job at a time from a
# shipped list of six types, and one browser stage at a time. The orchestrator may add a heavy
# type for a run but never raise a limit: limits come only from the stamp written at run start.
# S8-21: no free-memory check.
#
#   <run>/limits.json                    {workers, heavy, stages}: written once by run new
#   <run>/slots/<kind>/<holder>.json     one slot held by one session (kind: worker, heavy,
#                                        stage-<id>)
#   <run>/slots/heavy-ops.extra          heavy types added for this run, one JSON line each
#   <run>/slots/.lock                    the lock (a folder; mkdir is atomic)
#
# A holder is a session of this run. Its slot is freed by release, by session close, or when
# the session reads dead (every recorded process of it is gone) or closed (lib/liveness.sh), or
# its record is gone. The age of a record or a slot never frees a slot. A session that
# needs a stage slot and the heavy slot takes the stage slot first.
# Exit codes: 64 usage, 65 refused, 66 no such session, 73 no free slot (try again later),
# 78 bad limit in the config.

HO_SLOT_NOSLOT=73

# ho_slot_limit <kind>: the limit for a kind. A run without a readable limits.json gets 1, the
# lowest limit, so a damaged stamp can never widen anything.
ho_slot_limit() {
  local kind=$1 v
  v=$(jq -r --arg k "$kind" '
      if $k == "worker" then .workers elif $k == "heavy" then .heavy
      elif ($k | startswith("stage-")) then (.stages[$k[6:]] // 1) else null end' "$HO_RUN_DIR/limits.json" 2>/dev/null) || v=""
  case $v in '' | *[!0-9]* | 0) v=1 ;; esac
  printf '%s\n' "$v"
}

# ho_slot_kind <token>: worker, heavy or stage:<id> -> the folder name.
ho_slot_kind() {
  case ${1-} in
    worker | heavy) printf '%s\n' "$1" ;;
    stage:*)
      printf '%s' "${1#stage:}" | grep -Eq '^[a-z][a-z0-9-]{0,39}$' || { printf 'harness: stage id %s must use a-z 0-9 -\n' "${1#stage:}" >&2; return 65; }
      printf 'stage-%s\n' "${1#stage:}"
      ;;
    *) printf 'harness: slot kind must be worker, heavy or stage:<id>, not %s\n' "${1-}" >&2; return 64 ;;
  esac
}

# ho_heavy_ops: every heavy type id for this run, the shipped six first.
ho_heavy_ops() {
  jq -r '.ops[].id' "$HO_ROOT/limits/heavy-ops.json" || { echo "harness: cannot read the shipped heavy list" >&2; return 78; }
  [ -f "$HO_RUN_DIR/slots/heavy-ops.extra" ] || return 0
  jq -r 'select(type == "object") | .id // empty' "$HO_RUN_DIR/slots/heavy-ops.extra" 2>/dev/null || true
}

# ---- the lock: a folder made by mkdir, held only for a count and one file write. Safety does
# not rest on it alone: after its write, a taker counts again and backs out when over the limit,
# so two takers can never both keep the last slot.
ho_slot_lock_take() {
  local lock="$HO_RUN_DIR/slots/.lock" n=0 t
  until mkdir "$lock" 2>/dev/null; do
    t=$(ho_live_mtime "$lock")
    if [ -n "$t" ] && [ $(( $(date +%s) - t )) -ge 30 ]; then
      rm -rf "$lock" 2>/dev/null || true
      continue
    fi
    n=$((n + 1))
    [ "$n" -lt 1200 ] || { printf 'harness: the slot lock %s is held; nothing taken\n' "$lock" >&2; return 1; }
    sleep 0.05
  done
  printf '%s\n' "$$" > "$lock/pid" 2>/dev/null || true
}

# ho_slot_free_dead <kind-dir>: remove slots whose holder has no record or reads dead or closed;
# print one "<holder>\t<reason>" line for each. Called under the lock.
# A slot is freed only by a proven end, never by age (H-105). Before a "dead" holder's slot is
# freed, its close flag is written and the verdict is read again: a launcher records itself
# before it reads that flag, so either the second read sees the launcher alive and the slot is
# kept, or the launcher sees the flag and starts no session.
ho_slot_free_dead() {
  local f holder rec v
  for f in "$1"/*.json; do
    [ -f "$f" ] || continue
    holder=$(basename "$f" .json)
    rec="$HO_RUN_DIR/sessions/$holder.json"
    if [ ! -f "$rec" ]; then
      rm -f "$f" && printf '%s\tno session record\n' "$holder"
      continue
    fi
    v=$(ho_live_verdict "$rec")
    if [ "$v" = dead ]; then
      : > "$HO_RUN_DIR/sessions/$holder.closing" 2>/dev/null || continue
      v=$(ho_live_verdict "$rec")
    fi
    case $v in dead | closed) rm -f "$f" && printf '%s\tsession %s\n' "$holder" "$v" ;; esac
  done
}

ho_slot_count() {
  local f n=0
  for f in "$1"/*.json; do [ -f "$f" ] && n=$((n + 1)); done
  printf '%s\n' "$n"
}

# ho_slot_try <kind> <holder> <op>: one attempt. 0 taken (or already held), 73 full.
# Prints the freed slots for the ledger.
ho_slot_try() {
  local kind=$1 holder=$2 op=$3 dir="$HO_RUN_DIR/slots/$1" limit rc=0
  limit=$(ho_slot_limit "$kind")
  mkdir -p "$dir" || return 1
  ho_slot_lock_take || return 1
  (
    trap 'rm -rf "$HO_RUN_DIR/slots/.lock"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    [ -f "$dir/$holder.json" ] && exit 0
    ho_slot_free_dead "$dir"
    [ "$(ho_slot_count "$dir")" -lt "$limit" ] || exit "$HO_SLOT_NOSLOT"
    jq -n --arg run "$HO_RUN_ID" --arg kind "$kind" --arg holder "$holder" --arg op "$op" --arg ts "$(ho_now)" \
      '{run: $run, kind: $kind, holder: $holder, op: (if $op == "" then null else $op end), since: $ts}' \
      | ho_atomic_write "$dir/$holder.json" || exit 1
    if [ "$(ho_slot_count "$dir")" -gt "$limit" ]; then
      rm -f "$dir/$holder.json"
      exit "$HO_SLOT_NOSLOT"
    fi
    exit 0
  ) || rc=$?
  return "$rc"
}

# ho_slot_take <kind> <holder> <op> <wait-seconds>: take a slot, waiting up to the given time.
# 0 taken, 73 no free slot in time. Writes the ledger lines outside the lock.
ho_slot_take() {
  local kind=$1 holder=$2 op=$3 wait=${4:-0} deadline rc freed h why
  deadline=$(( $(date +%s) + wait ))
  while :; do
    rc=0
    freed=$(ho_slot_try "$kind" "$holder" "$op") || rc=$?
    while IFS="$(printf '\t')" read -r h why; do
      [ -n "$h" ] && ho_ledger_append slot-freed kind "$kind" holder "$h" reason "$why"
    done <<EOF_FREED
$freed
EOF_FREED
    case $rc in
      0) ho_ledger_append slot-taken kind "$kind" holder "$holder" op "$op" limit "$(ho_slot_limit "$kind")"; return 0 ;;
      "$HO_SLOT_NOSLOT")
        [ "$(date +%s)" -lt "$deadline" ] || return "$HO_SLOT_NOSLOT"
        # A stop recorded during the wait ends it: nothing starts in a stopped run.
        local stopped=0
        ho_stopped || stopped=$?
        [ "$stopped" -eq 1 ] || { echo "harness: the run is stopped (or its stop state is unknown); the wait for a slot ends" >&2; return 75; }
        ;;
      *) return "$rc" ;;
    esac
    sleep 0.5
  done
}

# ho_slot_give <kind> <holder>: give a slot back; nothing held is not an error.
ho_slot_give() {
  local f="$HO_RUN_DIR/slots/$1/$2.json"
  [ -f "$f" ] || return 0
  rm -f "$f" && ho_ledger_append slot-given kind "$1" holder "$2"
}

# ho_slot_give_all <holder>: every slot of one session (session close).
ho_slot_give_all() {
  local d
  for d in "$HO_RUN_DIR"/slots/*/; do
    [ -d "$d" ] || continue
    ho_slot_give "$(basename "$d")" "$1"
  done
}

ho_slot_usage() {
  cat >&2 <<'USAGE'
usage: harness slot <run-dir> <verb> [args]
  acquire heavy --holder NAME --op TYPE [--wait SECONDS]
  acquire stage:<id> --holder NAME [--wait SECONDS]
                       take the slot; exit 73 when none is free in time (try again later)
  release heavy|stage:<id> --holder NAME
  release worker --holder NAME --force
                       for the owner, at a terminal: free the worker slot of a session that
                       cannot be judged (it reads unknown or dead); asks for the name, writes
                       the close flag and a ledger line. Never for a working or starting one.
  list                 kind, holder, operation and since, one line per held slot
  limits               the limits of this run (fixed at run start)
  heavy-ops            the heavy types of this run
  heavy-add TYPE REASON
                       count one more operation type as heavy for this run; never raises a limit
Worker slots are taken by "session launch --role worker" and given back by "session close".
USAGE
}

ho_slot_cli_take_or_give() {
  local verb=$1 token=${2-} kind holder="" op="" wait=0 rec v
  [ -n "$token" ] || { ho_slot_usage; return 64; }
  shift 2
  kind=$(ho_slot_kind "$token") || return $?
  local force=0
  while [ $# -gt 0 ]; do
    case $1 in
      --force) force=1; shift; continue ;;
      --holder | --op | --wait)
        [ $# -ge 2 ] || { ho_slot_usage; return 64; }
        case $1 in --holder) holder=$2 ;; --op) op=$2 ;; --wait) wait=$2 ;; esac
        shift 2
        ;;
      *) printf 'harness: unknown slot argument %s\n' "$1" >&2; return 64 ;;
    esac
  done
  [ -n "$holder" ] || { ho_slot_usage; return 64; }
  ho_session_name_ok "$holder" || return 65
  if [ "$kind" = worker ]; then
    [ "$verb" = release ] && [ "$force" -eq 1 ] || { echo 'harness: worker slots are taken by "session launch" and given back by "session close" (the owner may use "release worker --holder NAME --force")' >&2; return 65; }
    ho_slot_force_release "$holder"
    return $?
  fi
  [ "$force" -eq 0 ] || { echo "harness: --force is only for a worker slot" >&2; return 64; }
  if [ "$verb" = release ]; then
    ho_slot_give "$kind" "$holder"
    printf 'OK released %s %s\n' "$token" "$holder"
    return 0
  fi
  case $wait in '' | *[!0-9]*) echo "harness: --wait must be whole seconds" >&2; return 64 ;; esac
  rec="$HO_RUN_DIR/sessions/$holder.json"
  [ -f "$rec" ] || { printf 'harness: %s is not a session of run %s\n' "$holder" "$HO_RUN_ID" >&2; return 66; }
  v=$(ho_live_verdict "$rec")
  case $v in dead | closed) printf 'harness: session %s reads %s; no slot taken\n' "$holder" "$v" >&2; return 65 ;; esac
  if [ "$kind" = heavy ]; then
    [ -n "$op" ] || { echo "harness: a heavy slot needs --op TYPE (see heavy-ops)" >&2; return 64; }
    ho_heavy_ops | grep -qxF -- "$op" || {
      printf 'harness: %s is not a heavy type of this run; add it with heavy-add first, or run it without the heavy slot\n' "$op" >&2
      return 65
    }
  else
    [ -z "$op" ] || { echo "harness: --op is only for the heavy slot" >&2; return 64; }
  fi
  local rc=0
  ho_slot_take "$kind" "$holder" "$op" "$((10#$wait))" || rc=$?
  case $rc in
    0) printf 'OK %s held by %s\n' "$token" "$holder" ;;
    "$HO_SLOT_NOSLOT") printf 'harness: no free %s slot (limit %s); wait and try again\n' "$token" "$(ho_slot_limit "$kind")" >&2 ;;
  esac
  return "$rc"
}

# ho_slot_force_release <holder>: the owner's way out for a worker slot whose holder cannot be
# judged (a record from older code, an unreadable record, a process view that cannot see the
# session). It needs a person at a terminal who types the session name; an agent's shell has no
# terminal. A holder that reads working or starting is refused: its process is seen alive.
ho_slot_force_release() {
  local holder=$1 f="$HO_RUN_DIR/slots/worker/$1.json" rec="$HO_RUN_DIR/sessions/$1.json" v=unknown ans=""
  [ -f "$f" ] || { printf 'OK %s holds no worker slot\n' "$holder"; return 0; }
  [ ! -f "$rec" ] || v=$(ho_live_verdict "$rec")
  case $v in working | starting)
    printf 'harness: session %s reads %s; its slot is not released. Close it with "session close".\n' "$holder" "$v" >&2
    return 65 ;;
  esac
  if ! { exec 3<>/dev/tty; } 2>/dev/null; then
    printf 'harness: a forced release needs the owner at a terminal; nothing was released\n' >&2
    return 65
  fi
  printf 'Session %s reads %s. Releasing its worker slot lets another worker start; do it only when you know its process has ended.\nType the session name to release it: ' "$holder" "$v" >&3
  IFS= read -r -t 120 ans <&3 || ans=""
  exec 3>&-
  [ "$ans" = "$holder" ] || { printf 'harness: the answer did not match %s; nothing was released\n' "$holder" >&2; return 65; }
  # The flag first: a launcher that has not started yet then starts nothing (see ho_slot_free_dead).
  : > "$HO_RUN_DIR/sessions/$holder.closing" 2>/dev/null || true
  rm -f "$f" || return 1
  ho_ledger_append slot-force-released kind worker holder "$holder" verdict "$v" by owner
  printf 'OK released the worker slot of %s\n' "$holder"
}

# heavy-add: the name is all the orchestrator gives. Limits are not read from this list, so no
# entry can raise one.
ho_slot_heavy_add() {
  local op=${1-} reason=${2-}
  [ -n "$op" ] && [ -n "$reason" ] || { ho_slot_usage; return 64; }
  printf '%s' "$op" | grep -Eq '^[a-z][a-z0-9-]{1,39}$' || {
    printf 'harness: heavy type %s must be 2 to 40 of a-z 0-9 - (a name only; limits cannot be set here)\n' "$op" >&2
    return 65
  }
  if ho_heavy_ops | grep -qxF -- "$op"; then printf 'OK %s is already heavy\n' "$op"; return 0; fi
  mkdir -p "$HO_RUN_DIR/slots"
  jq -cn --arg id "$op" --arg reason "$reason" --arg ts "$(ho_now)" '{id: $id, reason: $reason, added: $ts}' \
    >> "$HO_RUN_DIR/slots/heavy-ops.extra" || return 1
  ho_ledger_append heavy-op-added op "$op" reason "$reason"
  printf 'OK %s counts as heavy for run %s\n' "$op" "$HO_RUN_ID"
}

ho_slot_list() {
  local f
  printf 'KIND\tHOLDER\tOP\tSINCE\n'
  for f in "$HO_RUN_DIR"/slots/*/*.json; do
    [ -f "$f" ] || continue
    jq -r '[.kind, .holder, (.op // "-"), .since] | @tsv' "$f" 2>/dev/null || printf '%s\t%s\tunreadable\n' "$(basename "$(dirname "$f")")" "$(basename "$f" .json)"
  done
}

ho_slot_main() {
  [ $# -ge 2 ] || { ho_slot_usage; exit 64; }
  ho_run_open "$1"
  local verb=$2 rc=0
  shift 2
  case $verb in
    acquire | release) ho_slot_cli_take_or_give "$verb" "$@" || rc=$? ;;
    list) ho_slot_list ;;
    limits)
      if [ -f "$HO_RUN_DIR/limits.json" ]; then jq -c 'del(.schemaVersion)' "$HO_RUN_DIR/limits.json"
      else jq -cn '{workers: 1, heavy: 1, stages: {browser: 1}, note: "no limits.json; the lowest limits apply"}'; fi
      ;;
    heavy-ops) ho_heavy_ops || rc=$? ;;
    heavy-add) ho_slot_heavy_add "$@" || rc=$? ;;
    *) ho_slot_usage; rc=64 ;;
  esac
  exit "$rc"
}
