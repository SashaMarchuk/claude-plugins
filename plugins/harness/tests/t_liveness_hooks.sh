# The liveness reader uses the hook log when it exists (H-089, H-090; D20, D37-SESSIONS-2).
# Hook records add facts; they never change a verdict, so a dead process ID always wins.
# Every time in a hook line is crafted relative to now, so the time edges are exact.
# shellcheck source=sessions-setup.sh
. "$HO_TESTS_DIR/sessions-setup.sh"
st() { "$h" session "$run" status "$@"; }
hk() { st "$1" | jq -c "$2"; }
cfg() { jq "$1" "$proj/.harness/config.json" > "$base/cfg.json" && mv "$base/cfg.json" "$proj/.harness/config.json"; }
hlog="$run/hooks.jsonl"
# line <seconds-ago> <session-id> <event> [tool-use-id] [error]: one hook line as the script writes it.
line() {
  local t=$(($(date +%s) - $1))
  jq -cn --argjson t "$t" --arg sid "$2" --arg e "$3" --arg id "${4-}" --arg err "${5-}" '{t: $t, ts: ($t | todate),
    event: $e, session_id: $sid} + (if $id != "" then {tool: "Bash", tool_use_id: $id} else {} end)
    + (if $err != "" then {error: $err} else {} end)' >> "$hlog"
}

# ---- the launcher marks each session it starts (D37-SESSIONS-2) ----
HO_FAKE_CLAUDE_SHOW_ENV=HO_HOOK_LOG launch w1 >/dev/null
sid=$(rec w1 .session_id)
i=0; while ! grep -q '^env HO_HOOK_LOG=' "$HO_FAKE_CLAUDE_LOG" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
assert_eq "H-089 (D37-SESSIONS-2): the launcher marks the session with the run's hook log" "env HO_HOOK_LOG=$hlog" \
  "$(grep '^env HO_HOOK_LOG=' "$HO_FAKE_CLAUDE_LOG" | tail -n 1)"
cfg '.liveness.hook_events = ["Stop", "PreToolUse", "NotAnEvent"]'
HO_FAKE_CLAUDE_SHOW_ENV=HO_HOOK_EVENTS launch w0 >/dev/null
i=0; while ! grep -q '^env HO_HOOK_EVENTS=' "$HO_FAKE_CLAUDE_LOG" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
assert_eq "H-089 (D37-SESSIONS-2): liveness.hook_events reaches the hook, kept to the seven events" "env HO_HOOK_EVENTS=PreToolUse Stop" \
  "$(grep '^env HO_HOOK_EVENTS=' "$HO_FAKE_CLAUDE_LOG" | tail -n 1)"
cfg 'del(.liveness)'
HO_FAKE_CLAUDE_SHOW_ENV=HO_HOOK_EVENTS launch w00 >/dev/null
i=0; while [ "$(grep -c '^env HO_HOOK_EVENTS=' "$HO_FAKE_CLAUDE_LOG" 2>/dev/null)" -lt 2 ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
assert_eq "H-089 (D37-SESSIONS-2): by default all seven events are on" \
  "env HO_HOOK_EVENTS=SessionStart PreToolUse PostToolUse PostToolUseFailure Stop StopFailure SessionEnd" \
  "$(grep '^env HO_HOOK_EVENTS=' "$HO_FAKE_CLAUDE_LOG" | tail -n 1)"

# ---- no hook log: the facts of T12 stay, and quiet is not judged ----
out=$(st w1)
assert_eq "H-090: with no hook log a live session still reads as working" working "$(printf '%s' "$out" | jq -r .liveness)"
assert_eq "H-089: with no hook log the hook state is missing" missing "$(printf '%s' "$out" | jq -r .hooks.state)"
assert_eq "H-089: with no hook log quiet is not judged (null)" null "$(printf '%s' "$out" | jq -r .quiet)"
assert_eq "H-090: the T12 fields stay" "alive missing" "$(printf '%s' "$out" | jq -r '"\(.process) \(.transcript_state)"')"

# ---- the reader uses the hook records ----
line 300 "$sid" SessionStart
line 100 "$sid" PreToolUse toolu_a
out=$(st w1)
assert_eq "H-089: the hook records are read for this session" "present 2 PreToolUse" \
  "$(printf '%s' "$out" | jq -r '"\(.hooks.state) \(.hooks.events) \(.hooks.last_event)"')"
age=$(printf '%s' "$out" | jq -r .hooks.last_event_age_seconds)
if [ "$age" -ge 99 ] && [ "$age" -le 110 ]; then ok "H-089: the age comes from the time in the line ($age s)"; else bad "H-089: the age comes from the time in the line" "$age"; fi
assert_eq "H-089 (D37-SESSIONS-2): a PreToolUse with no closing record is an open tool call" "toolu_a Bash true" \
  "$(printf '%s' "$out" | jq -r '"\(.hooks.open_tools | map(.tool_use_id) | join(",")) \(.hooks.open_tools[0].tool) \(.hooks.tool_running)"')"
assert_eq "H-089: a recent event is not quiet" false "$(printf '%s' "$out" | jq -r .quiet)"
touch -t "$(date -v-3H '+%Y%m%d%H%M' 2>/dev/null || date -d '-3 hours' '+%Y%m%d%H%M')" "$hlog"
assert_eq "H-105: the age never comes from the file's mtime" false "$(hk w1 .quiet)"

# ---- the quiet flag of D20: no hook event for 15 minutes ----
: > "$hlog"
line 840 "$sid" Stop
assert_eq "D20: 14 minutes with no hook event is not quiet" false "$(hk w1 .quiet)"
: > "$hlog"
line 960 "$sid" Stop
out=$(st w1)
assert_eq "D20 (D37-SESSIONS-2): 16 minutes with no hook event raises the quiet flag" true "$(printf '%s' "$out" | jq -r .quiet)"
assert_eq "D20: the quiet flag is a fact; the session still reads as working" working "$(printf '%s' "$out" | jq -r .liveness)"
assert_eq "H-099: a quiet session gets nothing typed" "" "$(cat "$HO_FAKE_TERM_DIR/$(rec w1 .handle | tr -c 'A-Za-z0-9-' '_').in" 2>/dev/null || true)"

# ---- a long silent job: an open tool call holds the flag off for 60 minutes ----
: > "$hlog"
line 3540 "$sid" PreToolUse toolu_long
assert_eq "D37-SESSIONS-2: a tool call open for 59 minutes reads as running, not quiet" "true false" \
  "$(hk w1 '"\(.hooks.tool_running) \(.quiet)"' | tr -d '"')"
: > "$hlog"
line 3660 "$sid" PreToolUse toolu_long
assert_eq "D37-SESSIONS-2: a tool call open for 61 minutes raises the quiet flag" "false true" \
  "$(hk w1 '"\(.hooks.tool_running) \(.quiet)"' | tr -d '"')"
assert_eq "D37-SESSIONS-2: the open call past the limit is still listed as a fact" "toolu_long" "$(hk w1 '.hooks.open_tools[0].tool_use_id' | tr -d '"')"
cfg '.liveness.tool_running_max_minutes = 120'
assert_eq "D37-SESSIONS-2: liveness.tool_running_max_minutes moves the limit (61 minutes under 120)" "true false" \
  "$(hk w1 '"\(.hooks.tool_running) \(.quiet)"' | tr -d '"')"
cfg '.liveness.tool_running_max_minutes = 1'
assert_eq "D37-SESSIONS-2: a lower limit raises the flag sooner" "false true" \
  "$(hk w1 '"\(.hooks.tool_running) \(.quiet)"' | tr -d '"')"
cfg 'del(.liveness)'

# ---- closing records ----
: > "$hlog"
line 1200 "$sid" PreToolUse toolu_a
line 1200 "$sid" PreToolUse toolu_b
line 1100 "$sid" PostToolUse toolu_a
assert_eq "D37-SESSIONS-2: a parallel call stays open when its sibling closes" '["toolu_b"]' "$(hk w1 '.hooks.open_tools | map(.tool_use_id)')"
line 1000 "$sid" PostToolUseFailure toolu_b
assert_eq "D37-SESSIONS-2: a PostToolUseFailure with the same ID closes the call" '[]' "$(hk w1 '.hooks.open_tools | map(.tool_use_id)')"
line 990 "$sid" PreToolUse toolu_c
line 990 "$sid" PreToolUse toolu_d
line 980 "$sid" Stop
assert_eq "D37-SESSIONS-2: a later Stop closes every open call of the session" '[] false' "$(hk w1 '"\(.hooks.open_tools | map(.tool_use_id)) \(.hooks.tool_running)"' | tr -d '"')"
line 970 "$sid" PreToolUse toolu_e
line 960 "$sid" SessionEnd
assert_eq "D37-SESSIONS-2: a later SessionEnd closes every open call" '[]' "$(hk w1 '.hooks.open_tools | map(.tool_use_id)')"
: > "$hlog"
line 60 "$sid" PreToolUse toolu_skew
line 90 "$sid" PostToolUse toolu_skew
assert_eq "D37-SESSIONS-2: 'later' goes by line order, not by the time in the line" '[]' "$(hk w1 '.hooks.open_tools | map(.tool_use_id)')"

# ---- another session's records have no effect ----
: > "$hlog"
line 1200 "$sid" Stop
line 10 "11111111-2222-4333-8444-999999999999" PreToolUse toolu_other
line 5 "ffffffff-ffff-4fff-8fff-ffffffffffff" Stop
out=$(st w1)
assert_eq "H-089: another session's open call and fresh events do not hold off this session's quiet flag" "true 1 []" \
  "$(printf '%s' "$out" | jq -r '"\(.quiet) \(.hooks.events) \(.hooks.open_tools | map(.tool_use_id))"')"

# ---- malformed and unreadable logs ----
: > "$hlog"
printf 'not json\n{"t":"x","event":"Stop","session_id":"%s"}\n[1,2]\n{"event":"PreToolUse","session_id":"%s"}\n' "$sid" "$sid" >> "$hlog"
line 30 "$sid" PreToolUse toolu_ok
assert_eq "H-089: malformed lines are skipped" "1 toolu_ok" "$(hk w1 '"\(.hooks.events) \(.hooks.open_tools[0].tool_use_id)"' | tr -d '"')"
: > "$hlog"
line 30 "11111111-2222-4333-8444-999999999999" Stop
assert_eq "H-089: a log with no record of this session reads none, quiet not judged" "none null" "$(hk w1 '"\(.hooks.state) \(.quiet)"' | tr -d '"')"
chmod 000 "$hlog"
if [ -r "$hlog" ]; then ok "H-089: an unreadable log reads unknown (skipped: running as a user who reads every file)"
else
  out=$(st w1)
  assert_eq "H-089: an unreadable hook log reads unreadable, quiet null, never quiet" "unreadable null working" \
    "$(printf '%s' "$out" | jq -r '"\(.hooks.state) \(.quiet) \(.liveness)"')"
fi
chmod 600 "$hlog"

# ---- the last turn's error type (StopFailure) ----
: > "$hlog"
line 50 "$sid" StopFailure "" rate_limit
assert_eq "D37-SESSIONS-2: a StopFailure's error type is reported" rate_limit "$(hk w1 .hooks.stop_error | tr -d '"')"
line 40 "$sid" Stop
assert_eq "D37-SESSIONS-2: a later clean Stop clears the error type" null "$(hk w1 .hooks.stop_error)"

# ---- a reduced event list must not make every call look open forever ----
: > "$hlog"
line 30 "$sid" PreToolUse toolu_x
cfg '.liveness.hook_events = ["SessionStart", "PreToolUse", "Stop"]'
assert_eq "D37-SESSIONS-2: without both closing events, open calls are not tracked" "false [] false" \
  "$(hk w1 '"\(.hooks.tools_tracked) \(.hooks.open_tools | map(.tool_use_id)) \(.hooks.tool_running)"' | tr -d '"')"
cfg 'del(.liveness)'
assert_eq "D37-SESSIONS-2: with all seven events, open calls are tracked" "true" "$(hk w1 .hooks.tools_tracked)"

# ---- a dead process ID always wins over the hook log ----
launch w2 >/dev/null
sid2=$(rec w2 .session_id)
p2=$(rec w2 .pid)
kill "$p2"
wait_gone "$p2" || bad "test setup: w2 did not end" "$p2"
line 1 "$sid2" PreToolUse toolu_fresh
i=0; while [ "$(st w2 | jq -r .liveness)" = starting ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
out=$(st w2)
assert_eq "D37-SESSIONS-2: a fresh hook record with a dead process reads dead" dead "$(printf '%s' "$out" | jq -r .liveness)"
assert_eq "D37-SESSIONS-2: a dead session is not judged quiet or running" "null false" \
  "$(printf '%s' "$out" | jq -r '"\(.quiet) \(.hooks.tool_running)"')"
