# Instruction delivery (issue #64, T31): messages first, terminal typing as a checked fallback.
# H-101 (messages first; a send counts only with a correlated transcript entry), H-099 (no
# wake keystrokes; typing only onto an empty input line; suggested text is not typed text),
# H-137 (a byte limit for typed text; longer text through a file). Design S8-24, D42f, D42g,
# D37-LIFECYCLE-4 (the send-now chord is runtime data). The screens are fixture files.
. "$HO_TESTS_DIR/sessions-setup.sh"

# A copy of the plugin, so a test runtime can name a message command (runtime data lives in
# the plugin's runtimes/ folder). Engine code is the same files.
plug="$base/plugin"
mkdir -p "$plug"
cp -R "$HO_PLUGIN_ROOT/bin" "$HO_PLUGIN_ROOT/lib" "$HO_PLUGIN_ROOT/runtimes" "$HO_PLUGIN_ROOT/.claude-plugin" "$plug/"
jq --arg m "$HO_TESTS_DIR/fake-bin/fake-msg" '.message.argv = [$m, "{session_id}", "{instruction_id}", "{text_file}"]' \
  "$plug/runtimes/claude-code.json" > "$plug/runtimes/claude-msg.json"
h="$plug/bin/harness"
screens="$HO_TESTS_DIR/fixtures/screens"
export HO_FAKE_CLAUDE_TRANSCRIPT=1 HO_FAKE_MSG_LOG="$base/msg.log"
jq '.delivery = {"wait_seconds": 2, "message_timeout_seconds": 5}' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
set_runtime() { printf '{"schemaVersion": 2, "runtime": {"main": "%s"} }\n' "$1" > "$user/config.json"; }

fin() { printf '%s/%s.in' "$HO_FAKE_TERM_DIR" "$(printf '%s' "$(rec "$1" .handle)" | tr -c 'A-Za-z0-9-' '_')"; }
fout() { printf '%s/%s.out' "$HO_FAKE_TERM_DIR" "$(printf '%s' "$(rec "$1" .handle)" | tr -c 'A-Za-z0-9-' '_')"; }
fbusy() { printf '%s/%s.busy' "$HO_FAKE_TERM_DIR" "$(printf '%s' "$(rec "$1" .handle)" | tr -c 'A-Za-z0-9-' '_')"; }
screen() { cat "$screens/$2.txt" > "$(fout "$1")"; }
trof() { ls "$HOME"/.claude/projects/*/"$(rec "$1" .session_id).jsonl" 2>/dev/null | head -n 1; }
# start <name>: launch, then wait until the fake has opened its transcript.
start() {
  local i=0
  launch "$1" >/dev/null
  while [ -z "$(trof "$1")" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
}
deliver() { local n=$1; shift; "$h" session "$run" deliver "$n" "$@"; }
ledger() { cat "$run/ledger.jsonl"; }
inbytes() { wc -c < "$(fin "$1")" | tr -d ' '; }

# ---- H-101: the message route first; a proven message means nothing is typed -------------
set_runtime claude-msg
start m1
screen m1 idle-empty
export HO_FAKE_MSG_MODE=deliver
out=$(deliver m1 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "H-101: a message the transcript records as a user turn with its id is delivered (exit 0)" "0" "$rc"
assert_contains "H-101: the delivery names the message route and the user-turn proof" "$out" "route=message proof=user-turn"
assert_eq "H-101: after a proven message nothing is typed into the terminal (0 bytes)" "0" "$(inbytes m1)"
assert_contains "H-101: the message command got the session ID and the message file" "$(cat "$base/msg.log")" "$(rec m1 .session_id)"

# ---- S8-24, H-101: unrelated growth is liveness, not delivery ----------------------------
# The message command exits 0, the transcript grows, but no entry carries the id. The screen
# shows a draft, so the typed fallback may not run either: the instruction is not delivered.
start m2
screen m2 draft
export HO_FAKE_MSG_MODE=noise
out=$(deliver m2 --text "push the trunk" 2>&1) && rc=0 || rc=$?
assert_eq "S8-24: a message whose send only made the transcript grow is not delivered (exit 1)" "1" "$rc"
assert_contains "S8-24: it is reported as not delivered" "$out" "NOT-DELIVERED"
assert_contains "S8-24: the ledger records the growth as liveness, not delivery" "$(ledger | grep '"kind":"deliver-message"' | grep unconfirmed)" '"transcript_grew":"yes"'
assert_eq "S8-24: no deliver-confirmed line for an unproven message" "" "$(ledger | grep deliver-confirmed | grep -F "$(printf '%s' "$out" | sed -n 's/.*id=\(ho-[0-9a-f]*\).*/\1/p')" || true)"

# A message command that reports success while the transcript does not grow at all.
start m6
screen m6 draft
export HO_FAKE_MSG_MODE=silent
out=$(deliver m6 --text "push the trunk" 2>&1) && rc=0 || rc=$?
assert_eq "H-101: a message send without transcript growth is not delivered (exit 1)" "1" "$rc"
assert_contains "H-101: the ledger records that the transcript did not grow" "$(ledger | grep '"kind":"deliver-message"' | grep unconfirmed | tail -n 1)" '"transcript_grew":"no"'

# A user turn that carries another instruction's id does not prove this one.
start m3
screen m3 draft
export HO_FAKE_MSG_MODE=other
out=$(deliver m3 --text "carry on with the queue" 2>&1) && rc=0 || rc=$?
assert_eq "S8-24: a user turn with another instruction's id does not count (exit 1)" "1" "$rc"

# ---- H-101: a failed or unproven message falls back to typing on an idle, empty line ------
start m4
screen m4 idle-empty
export HO_FAKE_MSG_MODE=noise
out=$(deliver m4 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "H-101: an unproven message falls back to typing, which is proven (exit 0)" "0" "$rc"
assert_contains "H-101: the fallback names the typed route" "$out" "route=typed proof=user-turn"
id4=$(printf '%s' "$out" | sed -n 's/.*id=\(ho-[0-9a-f]*\).*/\1/p')
assert_eq "S8-24: the typed line carries the instruction id" "$id4: run the unit tests" "$(head -n 1 "$(fin m4)")"
assert_eq "S8-24: request, message, typed and confirmed ledger lines carry the same id" "deliver-confirmed deliver-message deliver-request deliver-typed" \
  "$(ledger | grep -F "\"id\":\"$id4\"" | jq -r .kind | sort -u | tr '\n' ' ' | sed 's/ $//')"
start m5
screen m5 idle-empty
export HO_FAKE_MSG_MODE=fail
out=$(deliver m5 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "H-101: a failed message falls back to typing (exit 0)" "0" "$rc"
assert_contains "H-101: the failed message was followed by the typed route" "$out" "route=typed"
assert_contains "H-101: the failed message is in the ledger" "$(ledger)" '"result":"failed"'

# ---- H-099, D42g: the typed fallback runs only on an idle session with an empty line ------
set_runtime claude-code
start t1
screen t1 draft
out=$(deliver t1 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "H-099: a draft on the input line: the session receives 0 bytes" "0" "$(inbytes t1)"
assert_eq "H-099: a draft on the input line: not delivered (exit 1)" "1" "$rc"
assert_contains "H-099: the report says the input line holds the user's text" "$out" "input line holds text typed by the user"
screen t1 busy
out=$(deliver t1 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "D42g: a busy session gets nothing typed and no Enter key (0 bytes)" "1 0" "$rc $(inbytes t1)"
assert_contains "D42g: the busy instruction is reported as waiting" "$out" "busy"
screen t1 dialog
out=$(deliver t1 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "D42g: a dialog on the screen gets nothing typed (0 bytes)" "1 0" "$rc $(inbytes t1)"
assert_contains "D42g: the report says what it saw" "$out" "no idle input line"
assert_contains "D42g: the report names the last lines of the screen" "$out" "Esc to cancel"
assert_eq "H-099: the user's draft text is not copied into the ledger" "" "$(ledger | grep -F "half typed note" || true)"
assert_eq "H-099: the input line is checked by reading: no key reached the session" "" "$(calls | grep -E "(send-text|key|byte) $(rec t1 .handle) " || true)"
screen t1 suggestion
out=$(deliver t1 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "H-099: dim suggested text is not typed text: the instruction is typed and proven" "0" "$rc"
assert_contains "H-099: the read used the styled capture" "$(calls)" "tmux capture $(rec t1 .handle) styled"

# A backend without colours (iTerm2) cannot tell suggested text from typed text, so there the
# same screen counts as a draft and nothing is typed (the safe side).
jq '.terminal.app = "iterm2"' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
start i1
screen i1 suggestion
out=$(deliver i1 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "H-099: on iTerm2, which keeps no colours, text after the prompt counts as a draft (exit 1, 0 bytes)" "1 0" "$rc $(inbytes i1)"
jq '.terminal.app = "tmux"' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"

# ---- H-101, S8-24: a typed instruction that never shows up is not delivered ---------------
HO_FAKE_CLAUDE_DEAF=1 start t2
screen t2 idle-empty
out=$(deliver t2 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "H-101: typed text with no transcript entry is not delivered (exit 1)" "1" "$rc"
assert_contains "H-101: the reason names the missing transcript entry" "$out" "no transcript entry carries the instruction id"
assert_eq "H-101: the typed line went in once and was not typed again" "1" "$(grep -c . "$(fin t2)")"
# The screen looked idle, but the session only queued the line: reported as queued, so the
# caller checks again instead of sending a second copy.
start t3
screen t3 idle-empty
: > "$(fbusy t3)"
out=$(deliver t3 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "S8-24: a typed line that is only queued is not delivered yet (exit 1)" "1" "$rc"
assert_contains "S8-24: a queued line is reported as queued, not lost" "$out" "queued the instruction"

# ---- H-137, D42f: a byte limit; longer text through a file -------------------------------
start l1
screen l1 idle-empty
long=$(awk 'BEGIN { for (i = 0; i < 1500; i++) printf "\320\266" }')
out=$(deliver l1 --text "$long" 2>&1) && rc=0 || rc=$?
id=$(printf '%s' "$out" | sed -n 's/.*id=\(ho-[0-9a-f]*\).*/\1/p')
typed=$(head -n 1 "$(fin l1)")
assert_eq "H-137: a 3,000-byte prompt in two-byte letters is delivered through a file (exit 0)" "0" "$rc"
assert_eq "H-137: the typed line names the file in the run's state folder" "$id: read the file $run/messages/$id.txt and follow the instruction in it" "$typed"
assert_eq "H-137: the typed line is under the limit, counted in bytes" "yes" "$([ "$(printf '%s' "$typed" | LC_ALL=C wc -c)" -le 800 ] && echo yes || echo no)"
assert_eq "H-137: the file holds the whole prompt" "$id: $long" "$(cat "$run/messages/$id.txt")"
assert_contains "H-137: the ledger records the file mode" "$(ledger | grep '"kind":"deliver-typed"' | grep -F "$id")" '"mode":"file"'
# The limit counts bytes: 800 bytes go as they are, 801 go through a file.
start l2
screen l2 idle-empty
t800=$(awk 'BEGIN { for (i = 0; i < 786; i++) printf "a" }')
out=$(deliver l2 --id ho-limit-800 --text "$t800" 2>&1) && rc=0 || rc=$?
assert_eq "H-137: a line of exactly 800 bytes is typed as it is" "0 ho-limit-800: $t800" "$rc $(head -n 1 "$(fin l2)")"
out=$(deliver l2 --id ho-limit-801 --text "${t800}b" 2>&1) && rc=0 || rc=$?
assert_eq "H-137: a line of 801 bytes goes through a file" "0 ho-limit-801: read the file $run/messages/ho-limit-801.txt and follow the instruction in it" "$rc $(sed -n 2p "$(fin l2)")"
assert_exit "S8-24: an instruction id used before in the run is refused" 65 "$h" session "$run" deliver l2 --id ho-limit-800 --text again

# ---- D37-LIFECYCLE-4: the send-now chord comes from runtime data -------------------------
# A longer wait here: these deliveries pass through the queue, which takes a few more steps.
jq '.delivery.wait_seconds = 10' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
start f1
screen f1 busy
: > "$(fbusy f1)"
out=$(HO_FAKE_CLAUDE_VERSION=2.1.332 deliver f1 --force-send --text "stop now and park" 2>&1) && rc=0 || rc=$?
hf=$(rec f1 .handle)
assert_eq "D37-LIFECYCLE-4: a hard-stop message to a busy session is force-sent and proven (exit 0)" "0" "$rc"
assert_contains "D37-LIFECYCLE-4: the proof is the released queued command" "$out" "proof=queued-command"
assert_eq "D37-LIFECYCLE-4: the chord is sent once, as the runtime data's bytes, after the typed line" "send-text key byte byte" \
  "$(calls | grep -E "^tmux (send-text|key|byte) $hf( |$)" | awk '{ print $2 }' | tr '\n' ' ' | sed 's/ $//')"
assert_eq "D37-LIFECYCLE-4: the chord bytes are 0x18 then 0x13" "0x18 0x13" "$(calls | grep "^tmux byte $hf " | awk '{ print $4 }' | tr '\n' ' ' | sed 's/ $//')"
# Another runtime with another chord: the engine sends what the data says.
jq '.force_send.bytes = [1, 2]' "$plug/runtimes/claude-code.json" > "$plug/runtimes/claude-alt.json"
set_runtime claude-alt
start f2
screen f2 busy
: > "$(fbusy f2)"
out=$(HO_FAKE_CLAUDE_VERSION=2.1.332 deliver f2 --force-send --text "stop now and park" 2>&1) && rc=0 || rc=$?
assert_eq "D37-LIFECYCLE-4: the chord bytes come from runtime data, not engine code" "tmux byte $(rec f2 .handle) 0x01
tmux byte $(rec f2 .handle) 0x02" "$(calls | grep "byte $(rec f2 .handle) ")"
set_runtime claude-code
start f3
screen f3 busy
: > "$(fbusy f3)"
out=$(HO_FAKE_CLAUDE_VERSION=2.1.200 deliver f3 --force-send --text "stop now and park" 2>&1) && rc=0 || rc=$?
assert_eq "D37-LIFECYCLE-4: below the data's lowest version no chord is sent; the message stays queued" "1 " "$rc $(calls | grep "byte $(rec f3 .handle) " || true)"
assert_contains "D37-LIFECYCLE-4: the skipped chord is in the ledger" "$(ledger)" 'below 2.1.275'
start f4
screen f4 idle-empty
out=$(HO_FAKE_CLAUDE_VERSION=2.1.332 deliver f4 --force-send --text "stop now and park" 2>&1) && rc=0 || rc=$?
assert_eq "D37-LIFECYCLE-4: a free session takes the message at once and gets no chord" "0 " "$rc $(calls | grep "byte $(rec f4 .handle) " || true)"

# ---- S8-24: the proof check alone (for a message the caller sent itself) -----------------
start p1
tp=$(trof p1)
jq -cn '{type: "user", message: {role: "user", content: [{type: "tool_result", content: "ho-proofaaa1: read from the file"}]} }' >> "$tp"
jq -cn '{type: "queue-operation", operation: "enqueue", content: "ho-proofaaa2: stop"}' >> "$tp"
jq -cn '{type: "assistant", message: {role: "assistant", content: [{type: "text", text: "ACK ho-proofaaa3"}]} }' >> "$tp"
jq -cn '{type: "attachment", attachment: {type: "queued_command", prompt: "ho-proofaaa4: stop", humanTurn: true} }' >> "$tp"
jq -cn '{type: "user", message: {role: "user", content: "ho-proofaaa5: run the tests"} }' >> "$tp"
jq -cn '{type: "user", message: {role: "user", content: "ho-proofaaa6-b: a longer id"} }' >> "$tp"
pr() { "$h" session "$run" proof p1 "$1" 2>&1 | cut -d' ' -f1-2; }
assert_eq "S8-24: an id inside a tool result is not a delivery" "none id=ho-proofaaa1" "$(pr ho-proofaaa1)"
assert_eq "S8-24: an id only queued is not yet delivered" "queued id=ho-proofaaa2" "$(pr ho-proofaaa2)"
assert_eq "S8-24: a reply that acknowledges the id proves delivery" "delivered reply" "$(pr ho-proofaaa3)"
assert_eq "S8-24: a queued-command record with the id proves delivery" "delivered queued-command" "$(pr ho-proofaaa4)"
assert_eq "S8-24: a user turn with the id proves delivery" "delivered user-turn" "$(pr ho-proofaaa5)"
assert_exit "S8-24: proof exits 1 when not delivered" 1 "$h" session "$run" proof p1 ho-proofaaa2
assert_eq "S8-24: an id matches only as a whole word, not inside a longer id" "none id=ho-proofaaa6" "$(pr ho-proofaaa6)"

# ---- H-101: with no transcript to check, nothing is sent ---------------------------------
HO_FAKE_CLAUDE_TRANSCRIPT=0 launch n1 >/dev/null
screen n1 idle-empty
out=$(deliver n1 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "H-101: without a transcript to prove delivery nothing is typed (exit 1, 0 bytes)" "1 0" "$rc $(inbytes n1)"
