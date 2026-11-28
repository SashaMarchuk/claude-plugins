# shellcheck shell=bash
# Hard stops and the own stop message (H-085, H-087; design D25, D25c, S8-20b, S8-27,
# D37-LIFECYCLE-4, D37-LIFECYCLE-5, D37-LIFECYCLE-6). The soft stops live in lib/run.sh; a hard
# stop is recorded there by the same `state stop` verb and then acted on here.
#
#   hard:now      no message. The engine writes one record per session of this run (S8-20b),
#                 then force-closes each one by its exact recorded process ID (H-103).
#   hard:message  the default hard stop. The standard hard stop line (plus the own message)
#                 goes to every open session of this run by `session deliver`, with the
#                 send-now chord when stop.hard_message.force_send is true (default). The wait
#                 of stop.hard_message.wait_seconds (default 120) starts when the stop is
#                 issued. A session counts as parked when the hook log shows a Stop event for
#                 it after its transcript shows the stop message (S8-24); a session whose
#                 process is gone counts as stopped. A parked session is closed the normal way
#                 at once. A session that is not parked when the wait ends is escalated: one
#                 record, then a force-close by its exact process ID, one ledger line, and the
#                 stop output names it. With --service-down (the caller knows the service
#                 cannot be reached, D22) no message is sent and the stop acts as hard:now.
#
#   <run>/stops/<stop-id>/<name>.json   the engine's record of one session at a hard stop
#
# Requires lib/run.sh, lib/sessions.sh, lib/deliver.sh, lib/liveness.sh and lib/slots.sh.

# The standard hard stop line. A running shell command keeps running in the background when the
# message lands, so the line asks the session to stop it (D37-LIFECYCLE-4).
ho_stop_hard_text() {
  echo "Hard stop: stop now. Stop your background work, start nothing new, do not finish the step, and end your turn."
}

# ho_stop_own_text <text>: the own message as one line (line breaks become spaces), word for word.
ho_stop_own_text() { printf '%s' "$1" | tr '\r\n' '  '; }

# ho_stop_sessions: the names of this run's sessions that are not closed, one per line.
ho_stop_sessions() {
  local f
  for f in "$HO_RUN_DIR"/sessions/*.json; do
    [ -f "$f" ] || continue
    jq -e --arg run "$HO_RUN_ID" 'type == "object" and .run == $run and (.status // "") != "closed"' "$f" >/dev/null 2>&1 || continue
    basename "$f" .json
  done
}

# ho_stop_record <stop-id> <name> <reason>: write the engine's one record of a session (S8-20b).
# The session itself saves nothing.
ho_stop_record() {
  local id=$1 name=$2 why=$3 rec="$HO_RUN_DIR/sessions/$2.json" dir="$HO_RUN_DIR/stops/$1" pid
  mkdir -p "$dir" || return 1
  pid=$(ho_session_current_pid "$rec" 2>/dev/null) || pid=""
  jq --arg id "$id" --arg why "$why" --arg ts "$(ho_now)" --arg pid "$pid" \
    '{stop_id: $id, reason: $why, recorded: $ts, name, role, ticket: (.ticket // null), session_id, status,
      pid: (if $pid == "" then null else ($pid | tonumber) end), runtime: (.runtime // null), cwd: (.cwd // null)}' \
    "$rec" | ho_atomic_write "$dir/$name.json" || return 1
  ho_ledger_append hard-stop-record stop_id "$id" name "$name" reason "$why"
}

# ho_stop_force_close <stop-id> <name>: end the session's exact recorded process (H-087, H-103):
# SIGTERM, then SIGKILL after a short grace, then an existence check of up to 10 seconds (D42d).
# The process must still carry the session ID; nothing is matched by name. 0 closed, 1 not.
ho_stop_force_close() {
  local id=$1 name=$2 rec="$HO_RUN_DIR/sessions/$2.json" sid pid handle tag n
  sid=$(jq -r '.session_id // ""' "$rec")
  : > "$HO_RUN_DIR/sessions/$name.closing" 2>/dev/null || true
  pid=$(ho_session_current_pid "$rec" 2>/dev/null) || pid=""
  if [ -n "$pid" ] && ho_session_identity "$pid" "$sid"; then
    ho_ledger_append hard-stop-kill stop_id "$id" name "$name" session_id "$sid" pid "$pid"
    kill -TERM "$pid" 2>/dev/null || true
    n=0
    while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 20 ]; do sleep 0.1; n=$((n + 1)); done
    ! kill -0 "$pid" 2>/dev/null || ! ho_session_identity "$pid" "$sid" || kill -KILL "$pid" 2>/dev/null || true
    n=0
    while [ "$(ho_live_sid_state "$pid" "$sid")" != gone ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
    if [ "$(ho_live_sid_state "$pid" "$sid")" != gone ]; then
      ho_ledger_append hard-stop-not-closed stop_id "$id" name "$name" pid "$pid"
      printf 'harness: session %s (pid %s) is still there after the force-close; reported as not closed\n' "$name" "$pid" >&2
      return 1
    fi
  fi
  handle=$(jq -r '.handle // ""' "$rec") tag=$(jq -r '.term_tag // ""' "$rec")
  if [ -n "$handle" ]; then
    HO_TERM_BACKEND=$(jq -r '.backend // ""' "$rec")
    ho_term_close "$handle" "$tag" "$sid" >/dev/null 2>&1 \
      || ho_ledger_append session-close-terminal-skipped name "$name" session_id "$sid" handle "$handle" reason "after a force-close"
  fi
  ho_session_set "$rec" '.status = "closed" | .closed = $ts | .closed_reason = "force-closed"' --arg ts "$(ho_now)" || return 1
  ho_ledger_append session-close name "$name" session_id "$sid" result force-closed stop_id "$id"
  ho_slot_give_all "$name"
  return 0
}

# ho_stop_parked <name> <proof-id> <since>: 0 when the hook log shows a Stop event of the session
# at or after <since> (the time the transcript first showed the stop message).
ho_stop_parked() {
  local sid log
  sid=$(jq -r '.session_id // ""' "$HO_RUN_DIR/sessions/$1.json")
  log=$(ho_live_hook_log)
  [ -n "$sid" ] && [ -f "$log" ] || return 1
  { grep -F -- "\"$sid\"" "$log" 2>/dev/null || true; } | jq -R -s -e --arg sid "$sid" --argjson since "$3" '
    [split("\n")[] | select(length > 0) | (try fromjson catch null)
      | select(type == "object" and .session_id == $sid and .event == "Stop" and (.t | type) == "number" and .t >= $since)]
    | length > 0' >/dev/null 2>&1
}

# ho_stop_now <stop-id> <names...>: records first for every session, then the force-closes.
ho_stop_now() {
  local id=$1 n bad=0
  shift
  for n in "$@"; do ho_stop_record "$id" "$n" hard:now || bad=1; done
  for n in "$@"; do
    if ho_stop_force_close "$id" "$n"; then printf 'closed %s (forced)\n' "$n"; else bad=1; fi
  done
  return "$bad"
}

# ho_stop_hard <type> <stop-id> <own text> <service-down 0|1>
ho_stop_hard() {
  local type=$1 id=$2 own=$3 down=$4 names n
  ho_session_bind_project || return $?
  names=$(ho_stop_sessions | tr '\n' ' ')
  printf 'sessions: %s\n' "${names:-none}"
  if [ "$type" = hard:message ] && [ "$down" = 1 ]; then
    ho_ledger_append hard-stop-as-now stop_id "$id" reason "the service is down; no message is sent"
    printf 'note: the service is down; no message is sent and the stop acts as hard:now\n'
    type=hard:now
  fi
  if [ "$type" = hard:now ]; then
    [ -z "$own" ] || printf 'note: hard:now sends no message; your own message was not sent (it is in the run ledger)\n'
    # shellcheck disable=SC2086
    ho_stop_now "$id" $names
    return $?
  fi
  local wait force text start deadline i=0 pending="" parked="" escalated="" gone=""
  wait=$(ho_cfg_int '.stop.hard_message.wait_seconds' 120) || return $?
  force=$(ho_cfg '.stop.hard_message.force_send' true) || return $?
  text=$(ho_stop_hard_text)
  [ -z "$own" ] || text="$text $own"
  start=$(date +%s)
  deadline=$((start + wait))
  mkdir -p "$HO_RUN_DIR/stops/$id" || return 1
  # Each session gets its own delivery id (the stop id plus its place), so the chord marker of
  # one delivery never blocks another. The deliveries run side by side; the wait does not wait
  # for them.
  local -a dpids=()
  for n in $names; do
    i=$((i + 1))
    printf '%s\n' "$id-$i" > "$HO_RUN_DIR/stops/$id/$n.delivery"
    (
      if [ "$force" = true ]; then ho_session_deliver "$n" --text "$text" --id "$id-$i" --force-send
      else ho_session_deliver "$n" --text "$text" --id "$id-$i"; fi
    ) > "$HO_RUN_DIR/stops/$id/$n.deliver.log" 2>&1 &
    dpids+=("$!")
    pending="$pending $n"
  done
  # Poll every session until it is gone, parked, or the wait ends.
  local seen rest st
  while [ -n "${pending// /}" ]; do
    rest=""
    for n in $pending; do
      st=$(ho_live_session_state "$HO_RUN_DIR/sessions/$n.json" 2>/dev/null || echo unknown)
      if [ "$st" = gone ]; then gone="$gone $n"; continue; fi
      seen="$HO_RUN_DIR/stops/$id/$n.seen"
      if [ ! -f "$seen" ] && ho_session_proof "$n" "$(cat "$HO_RUN_DIR/stops/$id/$n.delivery")" >/dev/null 2>&1; then
        date +%s > "$seen"
      fi
      if [ -f "$seen" ] && ho_stop_parked "$n" "$id" "$(cat "$seen")"; then parked="$parked $n"; continue; fi
      rest="$rest $n"
    done
    pending=$rest
    [ -n "${pending// /}" ] || break
    [ "$(date +%s)" -lt "$deadline" ] || break
    sleep 0.5
  done
  escalated=$pending
  local bad=0
  for n in $gone; do
    ho_session_close "$n" >/dev/null 2>&1 || true
    printf 'stopped %s (process gone)\n' "$n"
  done
  for n in $parked; do
    if ho_session_close "$n" >/dev/null 2>&1; then printf 'closed %s (parked)\n' "$n"
    else bad=1; printf 'harness: parked session %s did not close the normal way\n' "$n" >&2; fi
  done
  if [ -n "${escalated// /}" ]; then
    for n in $escalated; do
      ho_ledger_append hard-stop-escalated stop_id "$id" name "$n" wait_seconds "$wait" reason "not parked within the wait"
    done
    printf 'escalated to hard:now (not parked within %s s):%s\n' "$wait" "$escalated"
    # shellcheck disable=SC2086
    ho_stop_now "$id" $escalated || bad=1
  fi
  # The deliveries end by their own timeouts; each is waited for by its exact process ID.
  for i in "${dpids[@]}"; do wait "$i" 2>/dev/null || true; done
  return "$bad"
}
