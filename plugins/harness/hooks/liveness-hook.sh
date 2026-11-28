#!/bin/bash
# Liveness hook (H-089; design S8-SESSIONS, D37-SESSIONS-2, D42l). One script for seven
# events; hooks.json passes the event name as the only argument. It appends one short line
# per event to the run's hook log and does nothing else:
#   - It prints nothing and always exits 0, so it adds no text to the session's conversation
#     and never blocks a tool call. It makes no model call and no terminal call.
#   - It acts only in a session the harness launched: the launcher sets HO_HOOK_LOG (the
#     absolute path of <run>/hooks.jsonl) and HO_HOOK_EVENTS (liveness.hook_events). Without
#     the mark it exits at once, so the user's other sessions are untouched.
#   - A line holds the time (t, epoch seconds; ts), the event, the session ID, the tool name
#     and tool call ID when the event has them, and for StopFailure the error type (a short
#     word, else "unknown"). It never stores tool input, tool output or failure text. It
#     never creates a folder.
exec >/dev/null 2>&1
# ho_hook_drain: read the rest of stdin, so a hook that returns early never makes the
# sender's write fail on a closed pipe.
ho_hook_drain() { [ -t 0 ] || cat >/dev/null 2>&1 || true; }
ho_hook_main() {
  local log=${HO_HOOK_LOG-} ev=${1-} line
  case $log in /*.jsonl) ;; *) return 0 ;; esac
  case " SessionStart PreToolUse PostToolUse PostToolUseFailure Stop StopFailure SessionEnd " in
    *" $ev "*) ;;
    *) return 0 ;;
  esac
  if [ -n "${HO_HOOK_EVENTS+x}" ]; then
    case " $HO_HOOK_EVENTS " in *" $ev "*) ;; *) return 0 ;; esac
  fi
  [ -d "${log%/*}" ] || return 0
  # D42l: at most 1 MiB is parsed, so a huge tool input or output cannot hold the hook past its
  # 1 s bound. A larger payload is read from its first MiB with the streaming parser, top-level
  # fields only: the event and session ID are kept, a tool call ID only when it lies inside
  # that MiB. The rest of stdin is read and dropped by ho_hook_drain.
  local max=1048576 body mode=whole
  body=$(LC_ALL=C head -c $((max + 1)); echo x) || return 0
  body=${body%x}
  [ "$(printf '%s' "$body" | LC_ALL=C wc -c | tr -d ' ')" -le "$max" ] || { body=$(printf '%s' "$body" | LC_ALL=C head -c "$max"); mode=stream; }
  # One jq call reads named fields only; anything that is not a JSON object writes nothing.
  local pick='(now | floor) as $t
    | def s: if type == "string" then .[0:200] else null end;
    {t: $t, ts: ($t | todate), event: $ev, session_id: (.session_id | s)}
    + (if .tool_use_id != null then {tool: (.tool_name | s), tool_use_id: (.tool_use_id | s)} else {} end)
    + (if $ev == "StopFailure" then {error: (if (.error | type) == "string" and (.error | test("^[a-z_]{1,40}$")) then .error else "unknown" end)} else {} end)'
  if [ "$mode" = whole ]; then
    line=$(printf '%s' "$body" | jq -c --arg ev "$ev" "select(type == \"object\") | $pick" 2>/dev/null) || return 0
  else
    line=$(printf '%s' "$body" | jq -c -n --stream --arg ev "$ev" 'reduce (try inputs catch empty) as $e ({ok: null, v: {}};
        if .ok == null then .ok = (($e[0][0] | type) == "string") else . end
        | if ($e | length) == 2 and ($e[0] | length) == 1 then .v[$e[0][0] | tostring] = $e[1] else . end)
      | select(.ok == true) | .v | '"$pick" 2>/dev/null) || return 0
  fi
  [ -n "$line" ] || return 0
  case $line in *$'\n'*) return 0 ;; esac
  printf '%s\n' "$line" >> "$log"
}
ho_hook_main "$@"
ho_hook_drain
exit 0
