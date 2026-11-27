# The liveness hooks (H-089; design S8-SESSIONS, D37-SESSIONS-2, D42l): one short script for
# seven events, declared with a 2 s limit. It appends one short line per event to the run's
# hook log, prints nothing, always exits 0 and stores no tool input, output or failure text.
hooks_file="$HO_PLUGIN_ROOT/hooks/hooks.json"
script="$HO_PLUGIN_ROOT/hooks/liveness-hook.sh"
seven="SessionStart PreToolUse PostToolUse PostToolUseFailure Stop StopFailure SessionEnd"
base=$(cd -P "$PWD" && pwd)
sid=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee
secret=S3CRET-do-not-log

# ---- the hooks file: seven events, one script, a 2 s limit each ----
assert_eq "H-089 (D37-SESSIONS-2): the hooks file is valid JSON with a top-level hooks key" object \
  "$(jq -r '.hooks | type' "$hooks_file" 2>/dev/null)"
assert_eq "H-089 (D37-SESSIONS-2): the hooks file declares exactly the seven events" \
  "PostToolUse PostToolUseFailure PreToolUse SessionEnd SessionStart Stop StopFailure" \
  "$(jq -r '.hooks | keys | join(" ")' "$hooks_file" 2>/dev/null)"
assert_eq "H-089 (D37-SESSIONS-2): every event has one command hook" "7" \
  "$(jq '[.hooks[] | length == 1 and (.[0].hooks | length == 1) and .[0].hooks[0].type == "command"] | map(select(.)) | length' "$hooks_file" 2>/dev/null)"
assert_eq "H-089 (D42l): every hook is declared with a time limit of 2 seconds" "2" \
  "$(jq -r '[.hooks[][].hooks[].timeout] | unique | map(tostring) | join(",")' "$hooks_file" 2>/dev/null)"
assert_eq "H-089 (D37-SESSIONS-2): all seven call one script, passing their own event name" "7" \
  "$(jq -r '.hooks | to_entries | map(.key as $k | select(.value[0].hooks[0].command | test("/hooks/liveness-hook\\.sh\"? " + $k + "$"))) | length' "$hooks_file" 2>/dev/null)"
assert_eq "H-089: the hook script exists and is executable" yes "$([ -x "$script" ] && echo yes || echo no)"

# hook_cmd <event>: the declared command for that event, with the plugin root filled in.
hook_cmd() {
  jq -r --arg e "$1" '.hooks[$e][0].hooks[0].command' "$hooks_file" | sed "s#\${CLAUDE_PLUGIN_ROOT}#$HO_PLUGIN_ROOT#g"
}
# input <event>: a realistic stdin payload with the secret in every free-text field.
input() {
  jq -cn --arg e "$1" --arg sid "$sid" --arg s "$secret" --arg tr "$base/run/transcript.jsonl" '{
    session_id: $sid, transcript_path: $tr, cwd: "/x", hook_event_name: $e, permission_mode: "default"}
    + (if $e == "PreToolUse" then {tool_name: "Bash", tool_use_id: "toolu_1", tool_input: {command: ("echo " + $s)}}
       elif $e == "PostToolUse" then {tool_name: "Bash", tool_use_id: "toolu_1", tool_input: {command: $s}, tool_response: {stdout: $s}}
       elif $e == "PostToolUseFailure" then {tool_name: "Bash", tool_use_id: "toolu_2", tool_input: {command: $s}, error: ("Exit code 1\n" + $s)}
       elif $e == "Stop" then {stop_hook_active: false, last_assistant_message: $s}
       elif $e == "StopFailure" then {error: "rate_limit", error_details: $s, last_assistant_message: $s}
       elif $e == "SessionStart" then {source: "startup", model: "m"}
       else {reason: "other"} end)'
}
mkdir -p "$base/run"
log="$base/run/hooks.jsonl"
printf '{"type":"user"}\n' > "$base/run/transcript.jsonl"
snap() { (cd "$base/run" && find . -type f -exec cksum {} + | sort -k3); }
before=$(snap)
out_all=""
rc_all=""
for e in $seven; do
  o=$(input "$e" | HO_HOOK_LOG="$log" /bin/sh -c "$(hook_cmd "$e")" 2>&1) && rc=0 || rc=$?
  out_all="$out_all$o"
  rc_all="$rc_all$rc"
done
assert_eq "H-089 (S8-SESSIONS): the hooks print nothing, so nothing reaches the conversation" "" "$out_all"
assert_eq "H-089 (D37-SESSIONS-2): every hook exits 0" "0000000" "$rc_all"
assert_eq "H-089: one line per event" "7" "$(wc -l < "$log" | tr -d ' ')"
assert_eq "H-089: the lines name the seven events in order" "$seven" "$(jq -r .event "$log" | tr '\n' ' ' | sed 's/ $//')"
assert_eq "H-089 (S8-SESSIONS): the transcript and every other file are untouched" "$before" "$(snap | grep -v ' ./hooks.jsonl$' || true)"
assert_eq "H-089: the hook log is the one new file" yes "$([ -f "$log" ] && echo yes || echo no)"
assert_eq "H-089 (D37-SESSIONS-2): a line holds time, event, session ID, tool name and tool call ID" \
  "PreToolUse $sid Bash toolu_1 number" \
  "$(sed -n 2p "$log" | jq -r '"\(.event) \(.session_id) \(.tool) \(.tool_use_id) \(.t | type)"')"
assert_eq "H-089 (D37-SESSIONS-2): a StopFailure line holds the error type" "rate_limit" \
  "$(jq -r 'select(.event == "StopFailure") | .error' "$log")"
assert_eq "H-089 (D37-SESSIONS-2): no line stores tool input, tool output or failure text" "0" \
  "$(grep -c "$secret" "$log" || true)"
assert_eq "H-089 (D37-SESSIONS-2): a line holds only the named fields" "error event session_id t tool tool_use_id ts" \
  "$(jq -r 'keys[]' "$log" | sort -u | tr '\n' ' ' | sed 's/ $//')"
assert_eq "H-089: a line is short (under 300 bytes)" "0" "$(awk 'length($0) >= 300' "$log" | wc -l | tr -d ' ')"

# ---- no mark: other sessions of the same user are untouched ----
rm -f "$log"
before=$(snap)
o=$(input PreToolUse | env -u HO_HOOK_LOG /bin/sh -c "$(hook_cmd PreToolUse)" 2>&1) && rc=0 || rc=$?
assert_eq "H-089 (D37-SESSIONS-2): without the launcher's mark the hook exits 0" "0" "$rc"
assert_eq "H-089 (D37-SESSIONS-2): without the mark nothing is printed" "" "$o"
assert_eq "H-089 (D37-SESSIONS-2): without the mark no file is written" "$before" "$(snap)"
assert_eq "H-089 (D37-SESSIONS-2): without the mark no hook log exists" no "$([ -e "$log" ] && echo yes || echo no)"

# ---- the hook never creates folders and never fails ----
o=$(input Stop | HO_HOOK_LOG="$base/gone/hooks.jsonl" bash "$script" Stop 2>&1) && rc=0 || rc=$?
assert_eq "H-089: a run folder that is gone gets nothing and exit 0" "0:" "$rc:$o"
assert_eq "H-089: the hook never creates the run folder" no "$([ -e "$base/gone" ] && echo yes || echo no)"
o=$(input Stop | HO_HOOK_LOG="relative/hooks.jsonl" bash "$script" Stop 2>&1) && rc=0 || rc=$?
assert_eq "H-089: a relative log path is ignored, exit 0, no output" "0:" "$rc:$o"
o=$(printf 'not json at all' | HO_HOOK_LOG="$log" bash "$script" Stop 2>&1) && rc=0 || rc=$?
assert_eq "H-089: bad stdin gives exit 0 and no output" "0:" "$rc:$o"
assert_eq "H-089: bad stdin writes no line" no "$([ -s "$log" ] && echo yes || echo no)"
mkdir -p "$base/ro" && chmod 500 "$base/ro"
o=$(input Stop | HO_HOOK_LOG="$base/ro/hooks.jsonl" bash "$script" Stop 2>&1) && rc=0 || rc=$?
chmod 700 "$base/ro"
assert_eq "H-089: an unwritable log gives exit 0 and no output" "0:" "$rc:$o"
mkdir -p "$base/nojq"
for t in cat sed tr date; do p=$(command -v "$t") && ln -sf "$p" "$base/nojq/$t"; done
o=$(input Stop | PATH="$base/nojq" HO_HOOK_LOG="$log" /bin/bash "$script" Stop 2>&1) && rc=0 || rc=$?
assert_eq "H-089: with no jq on PATH the hook exits 0 and prints nothing" "0:" "$rc:$o"

# ---- liveness.hook_events can remove events; a removed event writes nothing ----
rm -f "$log"
for e in PreToolUse Stop; do
  input "$e" | HO_HOOK_LOG="$log" HO_HOOK_EVENTS="SessionStart Stop" /bin/sh -c "$(hook_cmd "$e")" >/dev/null 2>&1
done
assert_eq "H-089 (D37-SESSIONS-2): an event removed by liveness.hook_events writes no line" "Stop" "$(jq -r .event "$log" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
o=$(input Stop | HO_HOOK_LOG="$log" bash "$script" UserPromptSubmit 2>&1) && rc=0 || rc=$?
assert_eq "H-089 (D37-SESSIONS-2): an event outside the seven writes nothing" "0:1" "$rc:$o$(wc -l < "$log" | tr -d ' ')"

# ---- D42l: no terminal app call, and the run takes under 1 second ----
export HO_FAKE_TERM_DIR="$base/term"
mkdir -p "$HO_FAKE_TERM_DIR"
for e in $seven; do
  input "$e" | PATH="$HO_TESTS_DIR/fake-bin:$PATH" HO_HOOK_LOG="$log" /bin/sh -c "$(hook_cmd "$e")" >/dev/null 2>&1
done
assert_eq "H-089 (D42l): the hook makes no call to the terminal app" "" "$(cat "$HO_FAKE_TERM_DIR/calls.log" 2>/dev/null || true)"
assert_eq "H-089 (D42l): the hook script names no terminal command" "" \
  "$(grep -nE 'osascript|tmux|iterm|it2|term\.sh' "$script" || true)"
# A large tool input (the size of a big file write) still finishes within 1 s.
big=$(jq -cn --arg sid "$sid" '{session_id: $sid, hook_event_name: "PreToolUse", tool_name: "Write", tool_use_id: "toolu_big",
  tool_input: {content: ([range(0; 20000)] | map("line of text") | join("\n"))}}')
ms_now() { if [ -n "${EPOCHREALTIME:-}" ]; then local r=${EPOCHREALTIME/[.,]/}; echo $((r / 1000)); else perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; fi; }
worst=0
for e in $seven PreToolUse; do
  if [ "$e" = PreToolUse ]; then payload=$big; else payload=$(input "$e"); fi
  t0=$(ms_now)
  printf '%s' "$payload" | HO_HOOK_LOG="$log" /bin/sh -c "$(hook_cmd "$e")" >/dev/null 2>&1
  t1=$(ms_now)
  if [ $((t1 - t0)) -gt "$worst" ]; then worst=$((t1 - t0)); fi
done
if [ "$worst" -lt 1000 ]; then ok "H-089 (D42l): every hook run finishes within 1 second (worst ${worst} ms)"
else bad "H-089 (D42l): every hook run finishes within 1 second" "worst ${worst} ms"; fi
assert_eq "H-089: the large payload's line holds no tool input" "0" "$(grep -c 'line of text' "$log" || true)"

# ---- an early return still reads all of stdin, so the sender never hits a closed pipe ----
rm -f "$log"
rc=$(set +e; printf '%s' "$big" | env -u HO_HOOK_LOG bash "$script" PreToolUse; echo "${PIPESTATUS[0]}${PIPESTATUS[1]}")
assert_eq "H-089: without the mark a large payload is read whole (the sender sees no broken pipe)" "00" "$rc"
rc=$(set +e; printf '%s' "$big" | HO_HOOK_LOG="$log" HO_HOOK_EVENTS="Stop" bash "$script" PreToolUse; echo "${PIPESTATUS[0]}${PIPESTATUS[1]}")
assert_eq "H-089: a removed event still reads a large payload whole" "00" "$rc"
assert_eq "H-089: neither early return wrote a line" no "$([ -e "$log" ] && echo yes || echo no)"

# ---- the StopFailure field holds an error type only, never failure text ----
rm -f "$log"
jq -cn --arg sid "$sid" --arg s "$secret" '{session_id: $sid, hook_event_name: "StopFailure", error: ("429 Too Many Requests " + $s)}' \
  | HO_HOOK_LOG="$log" bash "$script" StopFailure
assert_eq "H-089 (D37-SESSIONS-2): an error that is not a short type word is stored as unknown" "unknown 0" \
  "$(jq -r .error "$log") $(grep -c "$secret" "$log" || true)"
