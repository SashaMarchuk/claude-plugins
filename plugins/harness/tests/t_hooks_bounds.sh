# Bounds of the liveness hook and its reader (H-089, D42l, D37-SESSIONS-2; wave-4 follow-ups #110).
# - The hook parses at most 1 MiB of its stdin; a larger payload still records the event and
#   its session ID, and the rest is read and dropped (proved by bytes, never by a clock).
# - The reader ignores a hook line timed in the future, so a forged far-future time cannot
#   hold the quiet flag off for ever.
# - The reader judges a session by the hook events it was launched with, not by today's config.
# shellcheck source=sessions-setup.sh
. "$HO_TESTS_DIR/sessions-setup.sh"
script="$HO_PLUGIN_ROOT/hooks/liveness-hook.sh"
hsid=aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee

# ---- the hook: jq never gets more than 1 MiB ----
realjq=$(command -v jq)
mkdir -p "$base/jqspy"
cat > "$base/jqspy/jq" <<EOF
#!/bin/bash
cat > "$base/jqspy/in.\$\$"
wc -c < "$base/jqspy/in.\$\$" | tr -d ' ' >> "$base/jqspy/bytes"
exec "$realjq" "\$@" < "$base/jqspy/in.\$\$"
EOF
chmod 700 "$base/jqspy/jq"
mkdir -p "$base/hrun"
hl="$base/hrun/hooks.jsonl"
# big <tool-use-id-first 0|1>: a PreToolUse payload of about 3 MiB.
big() {
  "$realjq" -cn --arg sid "$hsid" --argjson first "$1" '
    ([range(0; 3 * 1024 * 16)] | map("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef") | join("")) as $c
    | if $first == 1 then {session_id: $sid, hook_event_name: "PreToolUse", tool_name: "Write", tool_use_id: "toolu_head", tool_input: {content: $c}}
      else {session_id: $sid, hook_event_name: "PreToolUse", tool_name: "Write", tool_input: {content: $c}, tool_use_id: "toolu_tail"} end'
}
big 0 > "$base/big0.json"
big 1 > "$base/big1.json"
sz=$(wc -c < "$base/big0.json" | tr -d ' ')
[ "$sz" -gt 3000000 ] || bad "test setup: the payload is not over 3 MB" "$sz"
rc=$(set +e; PATH="$base/jqspy:$PATH" HO_HOOK_LOG="$hl" bash "$script" PreToolUse < "$base/big0.json"; echo $?)
assert_eq "H-089 (D42l): a payload over 1 MiB gives exit 0" 0 "$rc"
assert_eq "H-089 (D42l): jq reads at most 1 MiB of a large payload" ok \
  "$(awk 'BEGIN { m = 0 } { if ($1 > m) m = $1 } END { print (NR > 0 && m <= 1048576) ? "ok" : "max " m " bytes in " NR " call(s)" }' "$base/jqspy/bytes")"
assert_eq "H-089 (D42l): a large payload still records its event and session ID" "PreToolUse $hsid" \
  "$("$realjq" -r '"\(.event) \(.session_id)"' "$hl" 2>/dev/null | tail -n 1)"
assert_eq "H-089: the large payload's line holds no tool input" 0 "$(grep -c 0123456789abcdef "$hl" || true)"
rm -f "$hl"
PATH="$base/jqspy:$PATH" HO_HOOK_LOG="$hl" bash "$script" PreToolUse < "$base/big1.json"
assert_eq "H-089 (D42l): a tool call ID inside the first MiB is kept" "Write toolu_head" \
  "$("$realjq" -r '"\(.tool) \(.tool_use_id)"' "$hl" 2>/dev/null)"
rc=$(set +e; cat "$base/big0.json" | HO_HOOK_LOG="$hl" bash "$script" PreToolUse; echo "${PIPESTATUS[0]}${PIPESTATUS[1]}")
assert_eq "H-089: the rest of a large payload is read, so the sender sees no broken pipe" 00 "$rc"
rm -f "$base"/jqspy/in.*

# ---- the reader ----
hlog="$run/hooks.jsonl"
st() { "$h" session "$run" status "$@"; }
hk() { st "$1" | jq -c "$2"; }
cfg() { jq "$1" "$proj/.harness/config.json" > "$base/cfg.json" && mv "$base/cfg.json" "$proj/.harness/config.json"; }
line() {
  local t=$(($(date +%s) - $1))
  jq -cn --argjson t "$t" --arg sid "$2" --arg e "$3" --arg id "${4-}" '{t: $t, ts: ($t | todate),
    event: $e, session_id: $sid} + (if $id != "" then {tool: "Bash", tool_use_id: $id} else {} end)' >> "$hlog"
}
launch b1 >/dev/null
sid=$(rec b1 .session_id)
: > "$hlog"
line 1000 "$sid" Stop
line -100000 "$sid" PreToolUse toolu_future
assert_eq "D20 (#110): a hook line timed in the future is ignored; 16 quiet minutes still raise the flag" true "$(hk b1 .quiet)"
assert_eq "D20 (#110): the future line is not counted as an event" 1 "$(hk b1 .hooks.events)"

# ---- the hook events a session was launched with decide what it tracks ----
: > "$hlog"
line 100 "$sid" PreToolUse toolu_a
assert_eq "D37-SESSIONS-2: the record keeps the hook events of the launch" \
  "SessionStart PreToolUse PostToolUse PostToolUseFailure Stop StopFailure SessionEnd" "$(rec b1 '.hook_events // ""')"
cfg '.liveness.hook_events = ["Stop"]'
assert_eq "D37-SESSIONS-2 (#110): a later config change does not change what a running session tracks" "true" \
  "$(hk b1 .hooks.tools_tracked)"
assert_eq "D37-SESSIONS-2 (#110): its open tool call is still listed" "toolu_a" "$(hk b1 '.hooks.open_tools[0].tool_use_id' | tr -d '"')"
cfg 'del(.liveness)'

# ---- many open calls with no Stop: every one is listed, oldest first ----
: > "$hlog"
i=0; while [ $i -lt 300 ]; do line $((600 - i)) "$sid" PreToolUse "toolu_$i"; i=$((i + 1)); done
assert_eq "D37-SESSIONS-2: 300 open calls with no Stop are all listed, oldest first" "300 toolu_0 toolu_299" \
  "$(hk b1 '"\(.hooks.open_tools | length) \(.hooks.open_tools[0].tool_use_id) \(.hooks.open_tools[-1].tool_use_id)"' | tr -d '"')"
