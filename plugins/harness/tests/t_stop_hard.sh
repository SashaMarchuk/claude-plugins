# H-087 (hard stop variants that may force-close sessions), H-085 (the own stop message on any
# variant), design D25 (hard:message default, hard:now), D25c (escalate after the wait),
# S8-20b (one engine record per session before closing), S8-27 and H-103 (force-close only the
# exact recorded process ID), D37-LIFECYCLE-4 (force-send), D37-LIFECYCLE-5 (own message),
# D37-LIFECYCLE-6 (a session that does not park). tasks.md 17.1, hard and custom part.
. "$HO_TESTS_DIR/sessions-setup.sh"

# A copy of the plugin, so a test runtime can name the fake message command (runtime data lives
# in the plugin's runtimes/ folder). Engine code is the same files.
plug="$base/plugin"
mkdir -p "$plug"
cp -R "$HO_PLUGIN_ROOT/bin" "$HO_PLUGIN_ROOT/lib" "$HO_PLUGIN_ROOT/runtimes" "$HO_PLUGIN_ROOT/.claude-plugin" "$plug/"
jq --arg m "$HO_TESTS_DIR/fake-bin/fake-msg" '.message.argv = [$m, "{session_id}", "{instruction_id}", "{text_file}"]' \
  "$plug/runtimes/claude-code.json" > "$plug/runtimes/claude-msg.json"
h="$plug/bin/harness"
export HO_FAKE_CLAUDE_TRANSCRIPT=1 HO_FAKE_MSG_LOG="$base/msg.log" HO_FAKE_MSG_MODE=deliver HO_FAKE_TOOLS_PATH="$PATH"
printf '{"schemaVersion": 2, "runtime": {"main": "claude-msg"}, "delivery": {"wait_seconds": 2, "message_timeout_seconds": 5, "message_kill_grace_seconds": 1}}\n' > "$user/config.json"
set_stop() { jq --argjson w "$1" --argjson f "$2" '.stop.hard_message = {wait_seconds: $w, force_send: $f}' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"; }
set_stop 3 true

trof() { ls "$HOME"/.claude/projects/*/"$(rec "$1" .session_id "$2").jsonl" 2>/dev/null | head -n 1; }
wl() { local r=$1 n=$2; shift 2; "$h" session "$r" launch --role worker --name "$n" --cwd "$proj/src" --prompt "$base/prompt.md" "$@" >/dev/null; }
start() { # <run> <name>: launch and wait for the fake's transcript
  local i=0
  wl "$1" "$2"
  while [ -z "$(trof "$2" "$1")" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
}
pid_of() { rec "$2" .pid "$1"; }
gone() { wait_gone "$1" && echo yes || echo no; }
kinds() { jq -r --arg k "$2" 'select(.kind == $k) | .name' "$1/ledger.jsonl" | sort | tr '\n' ' ' | sed 's/ $//'; }

# ---- refusals ---------------------------------------------------------------------------------
r0=$("$h" run new --workers 20)
assert_exit "D25: an unknown hard variant is refused (64)" 64 "$h" state "$r0" stop --type hard:later
assert_exit "D37-LIFECYCLE-6: --service-down goes with hard:message only (64)" 64 "$h" state "$r0" stop --type soft:step --service-down
assert_exit "D37-LIFECYCLE-5: an empty own message is refused (64)" 64 "$h" state "$r0" stop --message " "
assert_eq "H-085: a refused stop records nothing" "" "$(jq -r 'select(.kind == "stop") | .type' "$r0/ledger.jsonl")"

# ---- H-085, D37-LIFECYCLE-5: the own message on a soft stop -------------------------------------
o=$("$h" state "$r0" stop --message "$(printf 'Please park now.\nThanks')")
assert_contains "D37-LIFECYCLE-5: the own message follows the standard soft line, as one line" "$o" \
  "text: Soft stop: finish the step you are on now"
assert_contains "D37-LIFECYCLE-5: the own message is passed word for word, line breaks as spaces" "$o" "end your turn. Start no new step and no new ticket. Please park now. Thanks"
assert_eq "D37-LIFECYCLE-5: the own message is written once to the run ledger" "Please park now. Thanks" \
  "$(jq -r 'select(.own_message != null) | .own_message' "$r0/ledger.jsonl")"

# ---- hard:now: records first, then force-close by exact PID; no message ------------------------
r=$("$h" run new --workers 20)
other=$("$h" run new --workers 20)
HO_FAKE_CLAUDE_HOLD=ignore start "$r" n1
HO_FAKE_CLAUDE_HOLD=ignore start "$r" n2
start "$other" x1
# A process that looks like a session (same runtime name in its command) but is not recorded.
( exec -a "claude --session-id $(rec n1 .session_id "$r")-lookalike" sleep 300 ) &
look=$!
echo "$look" >> "$base/extra.pids"
pn1=$(pid_of "$r" n1) pn2=$(pid_of "$r" n2) px=$(pid_of "$other" x1)
: > "$base/msg.log"
out=$("$h" state "$r" stop --type hard:now --message "my own words" 2>&1) && rc=0 || rc=$?
id=$(jq -r 'select(.kind == "stop") | .stop_id' "$r/ledger.jsonl")
assert_eq "H-087: hard:now succeeds" 0 "$rc"
assert_eq "H-087: hard:now ends the first session's exact process" yes "$(gone "$pn1")"
assert_eq "H-087: hard:now ends the second session's exact process" yes "$(gone "$pn2")"
assert_eq "H-103: a session of another run keeps running" yes "$(alive "$px" && echo yes || echo no)"
assert_eq "H-103: an unrecorded look-alike process keeps running" yes "$(alive "$look" && echo yes || echo no)"
assert_eq "H-087: hard:now sends no message" "" "$(cat "$base/msg.log")"
assert_eq "H-087: hard:now types nothing into the sessions" "" "$(calls | grep send-text || true)"
assert_eq "S8-20b: the engine writes one record per session" "n1 n2" "$(kinds "$r" hard-stop-record)"
assert_eq "S8-20b: each record names the session and its process" "n1 $pn1 hard:now|n2 $pn2 hard:now" \
  "$(for n in n1 n2; do jq -r '"\(.name) \(.pid) \(.reason)"' "$r/stops/$id/$n.json"; done | paste -sd '|' -)"
assert_eq "S8-20b: every record is written before the first close" yes \
  "$(jq -r '.kind' "$r/ledger.jsonl" | awk '/hard-stop-kill/ && !k {k=NR} /hard-stop-record/ {last=NR} END {print (last < k ? "yes" : "no")}')"
assert_eq "S8-27: each force-close names the exact recorded process ID" "n1 $pn1|n2 $pn2" \
  "$(jq -r 'select(.kind == "hard-stop-kill") | "\(.name) \(.pid)"' "$r/ledger.jsonl" | sort | paste -sd '|' -)"
assert_eq "H-087: the records are closed as force-closed" "closed force-closed closed force-closed" \
  "$(for n in n1 n2; do rec "$n" '"\(.status) \(.closed_reason)"' "$r"; done | tr '\n' ' ' | sed 's/ $//')"
assert_contains "D37-LIFECYCLE-5: hard:now says in one line that the own message was not sent" "$out" "own message was not sent"
assert_eq "D37-LIFECYCLE-5: the own message is still written to the run ledger" "my own words" \
  "$(jq -r 'select(.kind == "stop") | .own_message' "$r/ledger.jsonl")"
assert_exit "D25: a hard stop lets no step begin (75)" 75 "$h" state "$r" begin --ticket 1 --step s1
assert_eq "D25: stop-state names hard:now" "stop hard:now" "$("$h" state "$r" stop-state | jq -r '"\(.state) \(.type)"')"

# ---- hard:message: a parked session closes normally, one that does not park is escalated -------
r2=$("$h" run new --workers 20)
start "$r2" p1
HO_FAKE_CLAUDE_HOLD=ignore start "$r2" p2
pp1=$(pid_of "$r2" p1) pp2=$(pid_of "$r2" p2) sp1=$(rec p1 .session_id "$r2")
: > "$base/msg.log"
"$h" state "$r2" stop --type hard:message --message "$(printf 'Owner: wrap up.\nNow')" > "$base/hm.out" 2>&1 &
hm=$!
echo "$hm" >> "$base/extra.pids"
# The session parks: once the engine has seen the stop message in p1's transcript, p1's hook
# writes a Stop event.
i=0
while [ -z "$(ls "$r2"/stops/*/p1.seen 2>/dev/null)" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
jq -cn --arg sid "$sp1" --argjson t "$(date +%s)" '{t: $t, ts: "x", event: "Stop", session_id: $sid}' >> "$r2/hooks.jsonl"
rc=0; wait "$hm" || rc=$?
out=$(cat "$base/hm.out")
assert_eq "H-087: hard:message succeeds" 0 "$rc"
assert_contains "D37-LIFECYCLE-4: the stop message is sent with the forced send on (default)" \
  "$(jq -r 'select(.kind == "deliver-request") | .force_send' "$r2/ledger.jsonl" | sort -u | tr '\n' ' ')" "1"
assert_contains "D37-LIFECYCLE-5: the session gets the standard hard line, then the own message word for word" \
  "$(cat "$(trof p1 "$r2")")" "end your turn. Owner: wrap up. Now"
assert_eq "D37-LIFECYCLE-5: every session the stop covers gets the same text" 2 "$(grep -l 'Owner: wrap up. Now' "$r2"/messages/*.txt | wc -l | tr -d ' ')"
assert_eq "D37-LIFECYCLE-6: the parked session is closed the normal way" "closed exited" "$(rec p1 '"\(.status) \(.closed_reason)"' "$r2")"
assert_contains "D37-LIFECYCLE-6: the parked session got the exit command" "$(calls)" "send-text $(rec p1 .handle "$r2") /exit"
assert_eq "D37-LIFECYCLE-6: a parked session is never force-closed" "" "$(jq -r 'select(.kind == "hard-stop-kill" and .name == "p1") | .name' "$r2/ledger.jsonl")"
assert_eq "D25c: the session that did not park within the wait is escalated, alone" "p2" "$(kinds "$r2" hard-stop-escalated)"
assert_contains "D37-LIFECYCLE-6: the stop output names the escalated session" "$out" "escalated to hard:now (not parked within 3 s): p2"
assert_eq "D37-LIFECYCLE-6: the escalated session gets one record, the parked one none" "p2" "$(kinds "$r2" hard-stop-record)"
assert_eq "S8-27: the escalated session is force-closed by its exact process ID" "p2 $pp2" \
  "$(jq -r 'select(.kind == "hard-stop-kill") | "\(.name) \(.pid)"' "$r2/ledger.jsonl")"
assert_eq "D37-LIFECYCLE-6: both processes have ended" "yes yes" "$(gone "$pp1") $(gone "$pp2")"

# ---- the forced send switched off: the message only waits, the same wait applies ---------------
set_stop 1 false
r3=$("$h" run new --workers 20)
HO_FAKE_CLAUDE_HOLD=ignore start "$r3" f1
pf1=$(pid_of "$r3" f1)
out=$("$h" state "$r3" stop --type hard:message 2>&1) || true
assert_eq "D37-LIFECYCLE-4: with force_send false the message goes without the forced send" 0 \
  "$(jq -r 'select(.kind == "deliver-request") | .force_send' "$r3/ledger.jsonl")"
assert_eq "D37-LIFECYCLE-6: the wait still ends the stop: the session is escalated and closed" "f1 yes" "$(kinds "$r3" hard-stop-escalated) $(gone "$pf1")"

# ---- hard:message while the service is down: no message, acts as hard:now ----------------------
set_stop 3 true
r4=$("$h" run new --workers 20)
HO_FAKE_CLAUDE_HOLD=ignore start "$r4" d1
pd1=$(pid_of "$r4" d1)
: > "$base/msg.log"
out=$("$h" state "$r4" stop --type hard:message --service-down 2>&1) && rc=0 || rc=$?
assert_eq "D37-LIFECYCLE-6: hard:message with the service down succeeds" 0 "$rc"
assert_eq "H-095: no message is sent while the service is down" "" "$(cat "$base/msg.log")$(jq -r 'select(.kind == "deliver-request") | .id' "$r4/ledger.jsonl")"
assert_eq "D37-LIFECYCLE-6: the stop acts as hard:now at once (record, then force-close)" "d1 d1 yes" \
  "$(kinds "$r4" hard-stop-record) $(jq -r 'select(.kind == "hard-stop-kill") | .name' "$r4/ledger.jsonl") $(gone "$pd1")"
assert_contains "D37-LIFECYCLE-6: the output says the stop acts as hard:now" "$out" "acts as hard:now"
