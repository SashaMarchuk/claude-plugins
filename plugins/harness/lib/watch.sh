# shellcheck shell=bash
# The watch script: outage monitor and dead-orchestrator restart (H-095, H-096, H-097, H-098;
# design D22, D23, D32, D37-SESSIONS-3, D37-SESSIONS-4). It runs no model session: it makes
# plain HTTP checks, reads files and calls the engine's own verbs.
#
# Outage monitor (D22): two plain HTTP checks, the service and the internet (URLs from the
# runtime profile's outage block, or watch.service_url and watch.internet_url). The service is
# up when it answers with a status below 500; the internet is up when it answers at all. Every
# watch.up_seconds (300) while up, every watch.down_seconds (60) while down. A change is one
# ledger line (outage-begin with what failed, outage-end) and opens or closes a wait
# (wait-begin/wait-end reason outage), which stops the D21 attempt clock (lib/recover.sh).
# While an outage is open, "session deliver" sends nothing and "session launch" starts nothing
# (exit 76). The last value is in <run>/watch/state.json.
#
# Back (D37-SESSIONS-3, H-097): after the outage ends, the monitor looks at the orchestrator.
# If its last turn ended with an API error (a StopFailure hook line), the "service is back"
# message goes out at once. Otherwise the monitor waits watch.back_wait_seconds (120) for a hook
# event from the orchestrator: that event is the "I am back" marker, and no message is sent.
# With no event the message is sent, at most 3 times, 120 s apart; after the third with no
# event the restart below applies to the live, idle orchestrator. The monitor never writes to a
# worker.
#
# Restart (D23, D37-SESSIONS-4): "watch <run> restart" takes one lock and reads the recorded
# orchestrator first. A live orchestrator is left alone (unless --idle, the case above, where it
# is first closed the normal way; if it does not close it is not resumed). A dead one is
# resumed by its ID; if that fails, a new session starts with <run>/handoff.md when it exists.
# At most watch.restarts_per_hour (3) restarts in any hour, counted in the run ledger, shared by
# every caller. With the cap used up: one owner-action line and one orchestrator-down event in
# that hour, and nothing restarts until the hour has passed or the next run or resume. Nothing
# restarts during an outage or after the run ended.
#
# Supervision (D32): "watch <run> loop" writes <run>/watch/watch.pid ("<pid> <start time>");
# the orchestrator and the context watcher call "watch <run> pid-check" (0 alive, 1 not) and
# start the loop again when it is not running. Nothing is installed into the operating system.
#
# Exit codes: 64 usage, 65 refused, 73 the restart cap is used up, 75 the run ended.

HO_EXIT_OUTAGE=76

ho_watch_dir() { printf '%s/watch\n' "$HO_RUN_DIR"; }

# ho_watch_outage_open: 0 while the newest outage line is an outage-begin.
ho_watch_outage_open() {
  [ -f "$HO_RUN_DIR/ledger.jsonl" ] || return 1
  [ "$(grep -F '"kind":"outage-' "$HO_RUN_DIR/ledger.jsonl" 2>/dev/null | tail -n 1 | jq -r '.kind' 2>/dev/null)" = outage-begin ]
}

ho_watch_state() {
  local f s
  f="$(ho_watch_dir)/state.json"
  s=$(jq -c 'select(type == "object")' "$f" 2>/dev/null) || s=""
  [ -n "$s" ] || s='{"state":"up","last_check":0,"back":{"phase":"none"}}'
  printf '%s\n' "$s"
}
ho_watch_save() { mkdir -p "$(ho_watch_dir)" && printf '%s\n' "$1" | ho_atomic_write "$(ho_watch_dir)/state.json"; }

# ho_watch_url <service|internet>: the URL for one check.
ho_watch_url() {
  local v profile
  v=$(ho_cfg ".watch.${1}_url" '') || return 78
  if [ -z "$v" ]; then
    profile=$(ho_runtime_profile 2>/dev/null) || profile=""
    [ -n "$profile" ] && v=$(jq -r --arg k "$1" '.outage[$k + "_url"] // ""' "$profile" 2>/dev/null)
  fi
  case $v in https://* | http://*) printf '%s\n' "$v" ;; *) return 1 ;; esac
}

# ho_watch_http <url>: the HTTP status code, or 000 when nothing answered.
ho_watch_http() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -- "$1" 2>/dev/null) || code=000
  case $code in [0-9][0-9][0-9]) ;; *) code=000 ;; esac
  printf '%s\n' "$code"
}

# watch <run> outage-check [--now]: one check when it is due; prints the state.
ho_watch_outage_check() {
  local now s due svc net sc nc up=1 what=""
  now=$(date +%s)
  s=$(ho_watch_state)
  if [ "${1-}" != --now ]; then
    due=$(jq -r '.next_check // 0' <<<"$s")
    [ "$now" -ge "$due" ] || { jq -r '.state' <<<"$s"; return 0; }
  fi
  svc=$(ho_watch_url service) || svc=""
  net=$(ho_watch_url internet) || net=""
  sc=-; nc=-
  if [ -n "$svc" ]; then sc=$(ho_watch_http "$svc"); [ "$sc" != 000 ] && [ "$sc" -lt 500 ] || { up=0; what="service $sc"; }; fi
  if [ -n "$net" ]; then nc=$(ho_watch_http "$net"); [ "$nc" != 000 ] || { up=0; what="${what:+$what, }internet"; }; fi
  if [ "$up" -eq 0 ] && ! ho_watch_outage_open; then
    ho_ledger_append outage-begin failed "$what"
    ho_ledger_append wait-begin reason outage
    s=$(jq -c '.back = {phase: "none"}' <<<"$s")
  elif [ "$up" -eq 1 ] && ho_watch_outage_open; then
    ho_ledger_append outage-end
    ho_ledger_append wait-end reason outage result back
    s=$(jq -c --argjson now "$now" '.back = {phase: "waiting", since: $now, sent: 0, last_sent: 0}' <<<"$s")
  fi
  local st=up interval
  [ "$up" -eq 1 ] || st=down
  if [ "$st" = up ]; then interval=$(ho_cfg_int '.watch.up_seconds' 300); else interval=$(ho_cfg_int '.watch.down_seconds' 60); fi
  s=$(jq -c --arg st "$st" --argjson now "$now" --argjson i "$interval" --arg sc "$sc" --arg nc "$nc" \
    '.state = $st | .last_check = $now | .next_check = ($now + $i) | .interval = $i | .service = $sc | .internet = $nc' <<<"$s")
  ho_watch_save "$s"
  echo "$st"
}

# ho_watch_orch: the newest orchestrator record of the run.
ho_watch_orch() {
  local f best="" bt="" c
  for f in "$HO_RUN_DIR"/sessions/*.json; do
    [ -f "$f" ] || continue
    jq -e 'type == "object" and .role == "orchestrator"' "$f" >/dev/null 2>&1 || continue
    c=$(jq -r '.created // ""' "$f")
    if [ -z "$best" ] || [[ "$c" > "$bt" ]]; then best=$f; bt=$c; fi
  done
  [ -n "$best" ] && printf '%s\n' "$best"
}

ho_watch_h() { HO_PROJECT_DIR=$HO_PROJECT_DIR "$HO_ROOT/bin/harness" "$@"; }

# ho_watch_hook_after <session-id> <epoch>: 0 when the session wrote a hook event other than a
# StopFailure after that time (the "I am back" marker).
ho_watch_hook_after() {
  local log
  log=$(ho_live_hook_log)
  [ -f "$log" ] || return 1
  { grep -F -- "\"$1\"" "$log" 2>/dev/null || true; } | jq -R -s -e --arg sid "$1" --argjson t "$2" '
    [split("\n")[] | select(length > 0) | (try fromjson catch null)
      | select(type == "object" and .session_id == $sid and (.t | type) == "number" and .t > $t and .event != "StopFailure")] | length > 0' >/dev/null 2>&1
}

# ho_watch_stop_error <session-id>: 0 when the session's last hook event is a StopFailure.
ho_watch_stop_error() {
  local log
  log=$(ho_live_hook_log)
  [ -f "$log" ] || return 1
  [ "$({ grep -F -- "\"$1\"" "$log" 2>/dev/null || true; } | jq -R -r --arg sid "$1" '(try fromjson catch null) | select(type == "object" and .session_id == $sid) | .event' 2>/dev/null | tail -n 1)" = StopFailure ]
}

HO_WATCH_BACK_TEXT="The service is back after an outage. Continue the run from where you stopped."

# watch <run> back-check: the "service is back" steps after an outage (D37-SESSIONS-3).
ho_watch_back_check() {
  local s now rec sid name phase since sent last wait max ref
  s=$(ho_watch_state)
  phase=$(jq -r '.back.phase // "none"' <<<"$s")
  [ "$phase" = waiting ] || return 0
  ho_watch_outage_open && return 0
  rec=$(ho_watch_orch) || { ho_watch_save "$(jq -c '.back.phase = "none"' <<<"$s")"; return 0; }
  sid=$(jq -r '.session_id // ""' "$rec"); name=$(jq -r .name "$rec")
  now=$(date +%s)
  since=$(jq -r .back.since <<<"$s"); sent=$(jq -r .back.sent <<<"$s"); last=$(jq -r .back.last_sent <<<"$s")
  wait=$(ho_cfg_int '.watch.back_wait_seconds' 120); max=3
  ref=$since; [ "$last" -gt "$ref" ] && ref=$last
  if ho_watch_hook_after "$sid" "$ref"; then
    ho_ledger_append orchestrator-back name "$name" messages "$sent"
    ho_watch_save "$(jq -c '.back.phase = "none"' <<<"$s")"
    echo "orchestrator $name is back"
    return 0
  fi
  local due=0
  if [ "$sent" -eq 0 ]; then
    { ho_watch_stop_error "$sid" || [ $((now - since)) -ge "$wait" ]; } && due=1
  elif [ "$sent" -lt "$max" ] && [ $((now - last)) -ge "$wait" ]; then
    due=1
  elif [ "$sent" -ge "$max" ] && [ $((now - last)) -ge "$wait" ]; then
    ho_watch_save "$(jq -c '.back.phase = "none"' <<<"$s")"
    ho_ledger_append orchestrator-not-back name "$name" messages "$sent"
    echo "orchestrator $name did not come back after $sent messages; restarting"
    ho_watch_restart --idle
    return 0
  fi
  [ "$due" -eq 1 ] || return 0
  sent=$((sent + 1))
  ho_watch_save "$(jq -c --argjson n "$sent" --argjson now "$now" '.back.sent = $n | .back.last_sent = $now' <<<"$s")"
  local rc=0
  ho_watch_h session "$HO_RUN_DIR" deliver "$name" --text "$HO_WATCH_BACK_TEXT" --id "back-$now-$sent" >/dev/null 2>&1 || rc=$?
  ho_ledger_append back-message name "$name" n "$sent" rc "$rc"
  echo "service is back: message $sent to $name (rc $rc)"
}

# ho_watch_restarts_last_hour: restarts recorded in the last hour.
ho_watch_restarts_last_hour() {
  ho_ledger_events | jq -s --argjson now "$(date +%s)" \
    '[.[] | select(.kind == "orchestrator-restart") | (.ts | try fromdateiso8601 catch 0) | select(. > $now - 3600)] | length'
}

# watch <run> restart [--idle]: the one restart command (D23, D37-SESSIONS-4).
ho_watch_restart() {
  local idle=0 lock rec name live sid cwd cap n rc=0 how=resume new
  [ "${1-}" = --idle ] && idle=1
  ho_run_ended && { echo "harness: the run has ended; the orchestrator is not restarted" >&2; return 75; }
  ho_watch_outage_open && { echo "the service is down; no restart during an outage"; return 0; }
  mkdir -p "$(ho_watch_dir)"
  lock="$(ho_watch_dir)/restart.lock"
  mkdir "$lock" 2>/dev/null || {
    [ -n "$(find "$lock" -maxdepth 0 -mmin +5 2>/dev/null)" ] && rm -rf "$lock" && mkdir "$lock" 2>/dev/null \
      || { echo "another restart is under way"; return 0; }
  }
  # shellcheck disable=SC2064
  trap "rm -rf '$lock'" RETURN
  rec=$(ho_watch_orch) || { echo "harness: the run has no orchestrator record" >&2; return 65; }
  name=$(jq -r .name "$rec"); sid=$(jq -r '.session_id // ""' "$rec"); cwd=$(jq -r '.cwd // ""' "$rec")
  live=$(ho_watch_h session "$HO_RUN_DIR" status "$name" 2>/dev/null | jq -r '.liveness // "unknown"') || live=unknown
  case $live in
    working | starting) [ "$idle" -eq 1 ] || { echo "orchestrator $name is alive; nothing to do"; return 0; } ;;
    dead | closed) ;;
    *) echo "orchestrator $name reads $live; not restarted"; return 0 ;;
  esac
  cap=$(ho_cfg_int '.watch.restarts_per_hour' 3)
  n=$(ho_watch_restarts_last_hour)
  if [ "$n" -ge "$cap" ]; then
    if [ "$(ho_ledger_events | jq -s --argjson now "$(date +%s)" '[.[] | select(.kind == "orchestrator-down") | (.ts | try fromdateiso8601 catch 0) | select(. > $now - 3600)] | length')" -eq 0 ]; then
      ho_ledger_append orchestrator-down name "$name" restarts "$n"
      ho_ledger_append owner-action title "orchestrator is down" \
        why "it was restarted $n times in the last hour, the most the harness does" \
        command "harness:resume" verify "the orchestrator session runs again"
    fi
    echo "harness: the restart cap ($cap per hour) is used up; the orchestrator is not restarted" >&2
    return 73
  fi
  if [ "$idle" -eq 1 ] && [ "$live" != dead ] && [ "$live" != closed ]; then
    ho_watch_h session "$HO_RUN_DIR" close "$name" >/dev/null 2>&1 || true
    live=$(ho_watch_h session "$HO_RUN_DIR" status "$name" 2>/dev/null | jq -r '.liveness // "unknown"') || live=unknown
    case $live in dead | closed) ;; *)
      ho_ledger_append orchestrator-restart-failed name "$name" reason "the old process did not close"
      echo "harness: orchestrator $name did not close; it is not resumed" >&2
      return 65 ;;
    esac
  fi
  ho_watch_h session "$HO_RUN_DIR" close "$name" >/dev/null 2>&1 || true
  new="$(printf '%s' "$name" | sed -E 's/-r[0-9]+$//')-r$(date +%s)"
  if ho_session_uuid_ok "$sid" 2>/dev/null; then
    ho_watch_h session "$HO_RUN_DIR" launch --role orchestrator --name "$new" --cwd "$cwd" --resume "$sid" >/dev/null 2>&1 || rc=$?
  else rc=65; fi
  if [ "$rc" -ne 0 ] && [ -s "$HO_RUN_DIR/handoff.md" ]; then
    how=handoff; rc=0
    ho_watch_h session "$HO_RUN_DIR" launch --role orchestrator --name "$new" --cwd "$cwd" --prompt "$HO_RUN_DIR/handoff.md" >/dev/null 2>&1 || rc=$?
  fi
  case $rc in 73 | 74 | 75 | 76)
    # Refused for now: not a restart, so the hourly cap is not used; the next cycle tries again.
    ho_ledger_append orchestrator-restart-deferred from "$name" rc "$rc"
    echo "orchestrator restart deferred (rc $rc)"
    return 0 ;;
  esac
  ho_ledger_append orchestrator-restart name "$new" from "$name" how "$how" rc "$rc"
  echo "orchestrator restarted as $new ($how, rc $rc)"
}

# watch <run> pid-check: 0 when the watch loop of this run runs.
ho_watch_pid_check() {
  local f pid start
  f="$(ho_watch_dir)/watch.pid"
  read -r pid start < "$f" 2>/dev/null || { echo "the watch script is not running"; return 1; }
  case $pid in '' | *[!0-9]*) echo "the watch script is not running"; return 1 ;; esac
  [ -n "$start" ] && [ "$(ho_proc_start "$pid")" = "$start" ] && { echo "the watch script runs as $pid"; return 0; }
  echo "the watch script is not running; start it with: harness watch <run-dir> loop"
  return 1
}

# watch <run> cycle: one pass: the outage check when due, the back steps, a dead orchestrator.
ho_watch_cycle() {
  ho_watch_outage_check "${1-}" >/dev/null
  ho_watch_outage_open && return 0
  ho_watch_back_check
  local rec live
  rec=$(ho_watch_orch) || return 0
  live=$(ho_watch_h session "$HO_RUN_DIR" status "$(jq -r .name "$rec")" 2>/dev/null | jq -r '.liveness // "unknown"') || live=unknown
  # A record closed by a deferred restart still needs one.
  if [ "$live" = closed ] && ho_ledger_events | jq -e --arg n "$(jq -r .name "$rec")" 'select(.kind == "orchestrator-restart-deferred" and .from == $n)' >/dev/null 2>&1; then live=dead; fi
  [ "$live" != dead ] || ho_watch_restart || true
  # H-108: a usage reading every watch.sample_seconds (300) while the run is active.
  local s now every
  s=$(ho_watch_state); now=$(date +%s); every=$(ho_cfg_int '.watch.sample_seconds' 300)
  if [ $((now - $(jq -r '.last_sample // 0' <<<"$s"))) -ge "$every" ]; then
    ho_res_sample >/dev/null 2>&1 || true
    ho_watch_save "$(jq -c --argjson now "$now" '.last_sample = $now' <<<"$s")"
  fi
}

# watch <run> loop [--cycles N]: the watch script. Ends when the run ends.
ho_watch_loop() {
  local cycles=0 n=0 every
  [ "${1-}" = --cycles ] && { cycles=${2-0}; case $cycles in '' | *[!0-9]*) ho_watch_usage; return 64 ;; esac; }
  ho_watch_pid_check >/dev/null 2>&1 && { echo "harness: the watch script already runs for this run" >&2; return 65; }
  mkdir -p "$(ho_watch_dir)"
  printf '%s %s\n' "$$" "$(ho_proc_start "$$")" | ho_atomic_write "$(ho_watch_dir)/watch.pid"
  every=$(ho_cfg_int '.watch.cycle_seconds' 15)
  [ "$every" -ge 1 ] || every=1
  while ! ho_run_ended; do
    ho_watch_cycle || true
    n=$((n + 1))
    [ "$cycles" -eq 0 ] || [ "$n" -lt "$cycles" ] || break
    sleep "$every"
  done
  rm -f "$(ho_watch_dir)/watch.pid"
}

ho_watch_usage() {
  cat >&2 <<'USAGE'
usage: harness watch <run-dir> <verb>
  loop [--cycles N]     the watch script: outage monitor and orchestrator restart, until the run ends
  cycle [--now]         one pass of the loop
  outage-check [--now]  one outage check when due; prints up or down
  back-check            the "service is back" steps after an outage
  restart [--idle]      the one orchestrator restart command (3 per hour)
  pid-check             exit 0 when the watch script of this run runs
USAGE
}

ho_watch_main() {
  [ $# -ge 2 ] || { ho_watch_usage; exit 64; }
  ho_run_open "$1"
  HO_PROJECT_DIR=${HO_PROJECT_DIR:-$(dirname "$(dirname "$(dirname "$HO_RUN_DIR")")")}
  export HO_PROJECT_DIR
  local verb=$2 rc=0
  shift 2
  case $verb in
    loop) ho_watch_loop "$@" || rc=$? ;;
    cycle) ho_watch_cycle "$@" || rc=$? ;;
    outage-check) ho_watch_outage_check "$@" || rc=$? ;;
    back-check) ho_watch_back_check || rc=$? ;;
    restart) ho_watch_restart "$@" || rc=$? ;;
    pid-check) ho_watch_pid_check || rc=$? ;;
    *) ho_watch_usage; rc=64 ;;
  esac
  exit "$rc"
}
