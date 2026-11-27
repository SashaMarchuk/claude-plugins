# Instruction delivery (issue #64, T31): messages first, terminal typing as a checked fallback.
# H-101 (messages first; a send counts only with a correlated transcript entry), H-099 (no
# wake keystrokes; typing only onto an empty input line; suggested text is not typed text),
# H-137 (a byte limit for typed text; longer text through a file). Design S8-24, D42f, D42g,
# D37-LIFECYCLE-4 (the send-now chord is runtime data). The screens are fixture files.
. "$HO_TESTS_DIR/sessions-setup.sh"
# This file launches many sessions in one run: a run of its own with a worker cap that fits.
run=$("$h" run new --workers 300)

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
# The delivery safety settings are read from the user config only (review rounds 5 and 7).
DW=2 DT=5 DG=2 CUR=claude-code
write_user() { printf '{"schemaVersion": 2, "runtime": {"main": "%s"}, "delivery": {"wait_seconds": %s, "message_timeout_seconds": %s, "message_kill_grace_seconds": %s} }\n' "$CUR" "$DW" "$DT" "$DG" > "$user/config.json"; }
set_timeout() { DT=$1; write_user; }
set_grace() { DG=$1; write_user; }
set_runtime() { CUR=$1; write_user; }
set_wait() { DW=$1; write_user; }
export HO_FAKE_TOOLS_PATH="$PATH"

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

# ---- H-101, at most once: a started message command is never followed by typing -----------
# (review round 3 of PR #95). The command ran and only unrelated growth followed, or it failed:
# the result is "unknown, not sent again", one owner-action line, and 0 bytes typed.
start m4
screen m4 idle-empty
export HO_FAKE_MSG_MODE=noise
out=$(deliver m4 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "H-101 at most once: an unproven message is not followed by typing (exit 1, 0 bytes)" "1 0" "$rc $(inbytes m4)"
assert_contains "H-101 at most once: it is reported as unknown, not sent again" "$out" "unknown, not sent again"
id4=$(printf '%s' "$out" | sed -n 's/.*id=\(ho-[0-9a-f]*\).*/\1/p')
assert_eq "H-101 at most once: one owner-action line names the instruction" "1" "$(ledger | jq -r 'select(.kind == "owner-action") | .title' | grep -c -F "$id4" || true)"
start m5
screen m5 idle-empty
export HO_FAKE_MSG_MODE=fail
out=$(deliver m5 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
# Review round 4: a proven failure (non-zero exit, group gone, no record of the id in a
# readable transcript) falls back to typing (H-101 "Message fails").
assert_eq "H-101: a proven failure (non-zero exit, nothing in the transcript) is typed once (exit 0)" "0 1" "$rc $(grep -c . "$(fin m5)")"
assert_contains "H-101: the proven failure names the typed route" "$out" "route=typed"
assert_contains "H-101: the failed message and the proven failure are in the ledger" "$(ledger)" '"result":"proven failure'
# A "#!" line that names a missing interpreter: the command never starts, typing follows.
printf '#!/nonexistent/ho-interp\nexit 0\n' > "$base/bad-shebang"
chmod 700 "$base/bad-shebang"
jq --arg m "$base/bad-shebang" '.message.argv = [$m, "{session_id}"]' "$plug/runtimes/claude-code.json" > "$plug/runtimes/claude-shebang.json"
set_runtime claude-shebang
start m8
screen m8 idle-empty
out=$(deliver m8 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "H-101: a message command with a bad #! line never starts; the instruction is typed once (exit 0)" "0 1" "$rc $(grep -c . "$(fin m8)")"
assert_contains "H-101: the bad #! line is a refusal before start" "$(ledger | grep -F "$(printf '%s' "$out" | sed -n 's/.*id=\(ho-[0-9a-f]*\).*/\1/p')")" "refused before start"
set_runtime claude-msg
# The route refused before it starts (its command is missing): typing is the fallback.
jq '.message.argv = ["/nonexistent/ho-msg", "{session_id}"]' "$plug/runtimes/claude-code.json" > "$plug/runtimes/claude-gone.json"
set_runtime claude-gone
start m7
screen m7 idle-empty
out=$(deliver m7 --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "H-101: a message route refused before start falls back to typing, which is proven (exit 0)" "0" "$rc"
assert_contains "H-101: the fallback names the typed route" "$out" "route=typed proof=user-turn"
id7=$(printf '%s' "$out" | sed -n 's/.*id=\(ho-[0-9a-f]*\).*/\1/p')
assert_eq "S8-24: the typed line carries the instruction id" "$id7: run the unit tests" "$(head -n 1 "$(fin m7)")"
assert_eq "S8-24: request, message, typed and confirmed ledger lines carry the same id" "deliver-confirmed deliver-message deliver-request deliver-typed" \
  "$(ledger | grep -F "\"id\":\"$id7\"" | jq -r .kind | sort -u | tr '\n' ' ' | sed 's/ $//')"
assert_contains "H-101: the refusal before start is in the ledger" "$(ledger | grep -F "$id7")" "refused before start"
set_runtime claude-msg

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
set_wait 10
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

# ==== Fix round 1 of PR #95 (validator B1-B3, M1 and minors; Codex findings) ===============
set_wait 2
set_runtime claude-code

# ---- B1: the id is checked as one whole value; a newline cannot carry a path ---------------
start v1
screen v1 idle-empty
rc=0; deliver v1 --id "../../esc
ho-good1" --text hello >/dev/null 2>&1 || rc=$?
assert_eq "B1, H-137: an id with a newline and a path is refused (65)" "65" "$rc"
assert_eq "B1, H-137: no file is written outside the run's messages folder" "" "$(find "$proj/.harness" -name '*esc*' | head -n 1)"
assert_eq "B1: nothing is typed for a refused id" "0" "$(inbytes v1)"

# ---- B2: the id is matched as a literal, never as a pattern made from input ----------------
tv=$(trof v1)
jq -cn '{type: "user", message: {role: "user", content: "something else entirely"} }' >> "$tv"
rc=0; "$h" session "$run" proof v1 "ho-never1
|" >/dev/null 2>&1 || rc=$?
assert_eq "B2, S8-24: an id with a newline and a pattern cannot forge a proof (65)" "65" "$rc"

# ---- B3: a draft always means 0 bytes, --force-send included -------------------------------
start v2
screen v2 busy-draft
: > "$(fbusy v2)"
out=$(HO_FAKE_CLAUDE_VERSION=2.1.332 deliver v2 --force-send --text "stop now" 2>&1) && rc=0 || rc=$?
assert_eq "B3, H-099: a busy session with a draft gets 0 bytes even with --force-send" "1 0" "$rc $(inbytes v2)"
assert_contains "B3, H-099: the report names the draft" "$out" "input line holds text typed by the user"

# ---- M1: a transcript that exists but cannot be read gets nothing --------------------------
start v3
screen v3 idle-empty
chmod 000 "$(trof v3)"
out=$(deliver v3 --text "run tests" 2>&1) && rc=0 || rc=$?
chmod 600 "$(trof v3)"
assert_eq "M1, H-101: an unreadable transcript: nothing is typed (exit 1, 0 bytes)" "1 0" "$rc $(inbytes v3)"

# ---- H-099, D42g: the input line is read again before Enter --------------------------------
start v4
screen v4 idle-empty
out=$(HO_FAKE_TERM_ECHO_EXTRA=x deliver v4 --text "run tests" 2>&1) && rc=0 || rc=$?
assert_eq "D42g: when the line holds more than the typed text, no Enter is sent" "" "$(calls | grep -F "key $(rec v4 .handle) Enter" || true)"
assert_eq "D42g: that instruction is not delivered (exit 1)" "1" "$rc"
assert_contains "D42g: the report says the line changed before Enter" "$out" "NOT-DELIVERED"

# ---- S8-24: which records count ------------------------------------------------------------
start v5
t5=$(trof v5)
jq -cn '{type: "user", message: {role: "user", content: "ho-meta0001: x"}, isMeta: true}' >> "$t5"
jq -cn '{type: "user", message: {role: "user", content: "ho-summ0001: x"}, isCompactSummary: true}' >> "$t5"
jq -cn '{type: "user", message: {role: "user", content: "ho-side0001: x"}, isSidechain: true}' >> "$t5"
jq -cn '{type: "user", message: {role: "user", content: "ho-good0001: x"} }' >> "$t5"
jq -cn '{type: "user", message: "a plain string"}' >> "$t5"
jq -cn '{type: "user", message: {role: "user", content: "ho-word0001_x Xho-word0002 ho-word0003.txt ho-word0004X"} }' >> "$t5"
p5() { "$h" session "$run" proof v5 "$1" 2>&1 | cut -d' ' -f1-2; }
assert_eq "S8-24: an isMeta user record does not count" "none id=ho-meta0001" "$(p5 ho-meta0001)"
assert_eq "S8-24: a compaction summary does not count" "none id=ho-summ0001" "$(p5 ho-summ0001)"
assert_eq "S8-24: a sidechain record does not count" "none id=ho-side0001" "$(p5 ho-side0001)"
assert_eq "S8-24: a record whose message is a string does not hide an earlier proof" "delivered user-turn" "$(p5 ho-good0001)"
assert_eq "S8-24: an underscore after the id blocks the match" "none id=ho-word0001" "$(p5 ho-word0001)"
assert_eq "S8-24: an upper-case letter before the id blocks the match" "none id=ho-word0002" "$(p5 ho-word0002)"
assert_eq "S8-24: a dot after the id blocks the match" "none id=ho-word0003" "$(p5 ho-word0003)"
assert_eq "S8-24: an upper-case letter after the id blocks the match" "none id=ho-word0004" "$(p5 ho-word0004)"

# ---- H-137: the message file ---------------------------------------------------------------
start v6
screen v6 idle-empty
deliver v6 --id ho-mode0001 --text "run tests" >/dev/null 2>&1 || true
assert_eq "H-137: the message file is readable by the owner only (600)" "600" "$(stat -f %Lp "$run/messages/ho-mode0001.txt" 2>/dev/null || stat -c %a "$run/messages/ho-mode0001.txt")"
assert_exit "H-137: a --file value that starts with - is refused (65)" 65 "$h" session "$run" deliver v6 --file -n
screen v6 draft-two-lines
deliver v6 --text "run tests" >/dev/null 2>&1 || true
assert_eq "H-099: a two-line draft does not reach the ledger" "" "$(ledger | grep -F "of the draft" || true)"

# ---- Codex P2: a message already queued is not typed again ---------------------------------
set_runtime claude-msg
start v7
screen v7 idle-empty
out=$(HO_FAKE_MSG_MODE=queue deliver v7 --text "run tests" 2>&1) && rc=0 || rc=$?
assert_eq "H-101: a queued message is not typed a second time (exit 1, 0 bytes)" "1 0" "$rc $(inbytes v7)"
assert_contains "H-101: the queued message is reported as queued" "$out" "queued"

# ---- D37-LIFECYCLE-4: no chord once the entry has left the queue ---------------------------
start v8
screen v8 busy
: > "$(fbusy v8)"
out=$(HO_FAKE_MSG_MODE=dequeue HO_FAKE_CLAUDE_VERSION=2.1.332 deliver v8 --force-send --text "stop now" 2>&1) && rc=0 || rc=$?
assert_eq "D37-LIFECYCLE-4: no chord after the entry left the queue" "" "$(calls | grep "byte $(rec v8 .handle) " || true)"

# ---- Codex security P2: the version check runs the launch-checked runtime, not a PATH lookup
set_runtime claude-code
start v9
screen v9 busy
: > "$(fbusy v9)"
mkdir -p "$base/evil"
printf '#!/bin/sh\n: > "%s/evil-ran"\necho 9.9.9\n' "$base" > "$base/evil/claude"
chmod 700 "$base/evil/claude"
# A positive force-send passes through the queue: a longer wait, as for the other force-sends.
# With 2 s the wait could end before the fake took the queued line (a timing flake, PR #105);
# with 10 s it still failed under heavy load. The wait ends as soon as the proof shows.
set_wait 30
out=$(PATH="$base/evil:$PATH" HO_FAKE_CLAUDE_VERSION=2.1.332 deliver v9 --force-send --text "stop now" 2>&1) && rc=0 || rc=$?
set_wait 2
assert_eq "Codex P2: a claude found first on PATH after launch is never run" "no" "$([ -e "$base/evil-ran" ] && echo yes || echo no)"
assert_eq "Codex P2: the force-send still works with the launch-checked runtime" "0" "$rc"

# ==== Fix round 2 of PR #95 (Codex P2 at line 470, validator F2, minor 12) ==================
# ---- F1, H-101: a message command that fails after it delivered gets no typed copy ----------
set_timeout 2
set_runtime claude-msg
for mode in deliver-fail deliver-hang; do
  start "w-$mode"
  screen "w-$mode" idle-empty
  out=$(HO_FAKE_MSG_MODE=$mode deliver "w-$mode" --text "run tests" 2>&1) && rc=0 || rc=$?
  assert_eq "F1, H-101: a message command that delivered and then failed ($mode): nothing is typed (0 bytes)" "0" "$(inbytes "w-$mode")"
  assert_eq "F1, H-101: the transcript proof of that message counts ($mode, exit 0)" "0" "$rc"
  assert_contains "F1, H-101: it is reported as the message route ($mode)" "$out" "route=message"
done
set_runtime claude-code

# ---- F2, S8-24: an id that starts a line after a line of text is found -----------------------
start x1
jq -cn --arg c "$(printf 'Please do this.\nho-line0001: stop')" '{type: "user", message: {role: "user", content: $c} }' >> "$(trof x1)"
jq -cn --arg c "$(printf 'ho-line0002\nx')" '{type: "user", message: {role: "user", content: $c} }' >> "$(trof x1)"
assert_eq "F2, S8-24: an id at the start of a line after a line ending in a dot is found" "delivered user-turn" \
  "$("$h" session "$run" proof x1 ho-line0001 2>&1 | cut -d' ' -f1-2)"
assert_eq "F2, S8-24: an id at the end of a line before a line of text is found" "delivered user-turn" \
  "$("$h" session "$run" proof x1 ho-line0002 2>&1 | cut -d' ' -f1-2)"

# ---- minor 12: no line feed or carriage return as a control byte ----------------------------
for bad in '[10]' '[13]' '["10"]' '["13"]' '["\n"]' '["\r"]' '["0x0a"]' '[24, 13]'; do
  jq --argjson b "$bad" '.force_send.bytes = $b' "$plug/runtimes/claude-code.json" > "$plug/runtimes/claude-bad.json"
  set_runtime claude-bad
  nm="y$(printf '%s' "$bad" | cksum | cut -c1-6)"
  start "$nm"
  screen "$nm" busy
  : > "$(fbusy "$nm")"
  out=$(HO_FAKE_CLAUDE_VERSION=2.1.332 deliver "$nm" --force-send --text "stop now" 2>&1) && rc=0 || rc=$?
  assert_eq "minor 12: chord data $bad is refused; no byte is sent" "" "$(calls | grep "byte $(rec "$nm" .handle) " || true)"
done
set_runtime claude-code

# ==== Fix round 3 of PR #95 (at most once; validator N1-N4; minors 1 and 2) =================
set_runtime claude-msg
export HO_FAKE_MSG_PIDS="$base/extra.pids"
# ---- N1: a slow writer after a failed command: the same bounded wait finds the proof --------
start z1
screen z1 idle-empty
out=$(HO_FAKE_MSG_MODE=slow-fail deliver z1 --text "run tests" 2>&1) && rc=0 || rc=$?
# Round 4: the writer is in the command's group, which is stopped after the non-zero exit. Either
# its turn landed first (delivered, nothing typed) or it never lands (proven failure, typed):
# exactly one copy either way.
sleep 1.5
z1id=$(printf '%s' "$out" | sed -n 's/.*id=\(ho-[0-9a-f]*\).*/\1/p')
assert_eq "N1, H-101: a slow writer inside the stopped group: delivered once, never twice (exit 0, 1 copy)" "0 1" \
  "$rc $(jq -r 'select(.type == "user") | .message | objects | .content | strings' "$(trof z1)" | grep -c -F "$z1id: " || true)"
# ---- N2: a transcript unreadable after the command: unknown, not sent again, clean output ---
start z2
screen z2 idle-empty
out=$(HO_FAKE_MSG_MODE=unreadable-fail deliver z2 --text "run tests" 2>&1) && rc=0 || rc=$?
chmod 600 "$(trof z2)"
assert_eq "N2, H-101: an unreadable transcript after the command: nothing is typed (exit 1, 0 bytes)" "1 0" "$rc $(inbytes z2)"
assert_contains "N2, H-101: the result is unknown, not sent again" "$out" "unknown, not sent again"
assert_eq "N2: no raw shell error reaches the output" "" "$(printf '%s\n' "$out" | grep -E 'Permission denied|integer expression' || true)"
# ---- N3: the chord follows the transcript state, whatever the command's exit status --------
start z3
screen z3 busy
: > "$(fbusy z3)"
# A positive force-send passes through the queue and the screen gate: a longer wait.
set_wait 10
out=$(HO_FAKE_MSG_MODE=queue-fail HO_FAKE_CLAUDE_VERSION=2.1.332 deliver z3 --force-send --text "stop now" 2>&1) && rc=0 || rc=$?
set_wait 2
assert_eq "N3, D37-LIFECYCLE-4: a queued stop from a failed command still gets the chord once" "0x18 0x13" \
  "$(calls | grep "^tmux byte $(rec z3 .handle) " | awk '{ print $4 }' | tr '\n' ' ' | sed 's/ $//')"
assert_eq "N3: nothing is typed for it (0 bytes besides the chord)" "<0x18><0x13>" "$(cat "$(fin z3)")"
# ---- N4: a command that ignores SIGTERM: its group gets SIGKILL after the grace -------------
set_timeout 2
set_grace 1
start z4
screen z4 idle-empty
t0=$(date +%s)
out=$(HO_FAKE_MSG_MODE=term-ignore deliver z4 --text "run tests" 2>&1) && rc=0 || rc=$?
el=$(( $(date +%s) - t0 ))
# The bound proves the SIGKILL: the command would sleep 15 s. 12 s leaves room for a loaded
# machine (it was 7 s, and took 9 s under load; PR #105 review round 2).
assert_eq "N4: deliver returns within the timeout plus the grace and the proof wait (at most 12 s)" "yes" "$([ "$el" -le 12 ] && echo yes || echo "no (${el}s)")"
tp=$(cat "$base/extra.pids.term" 2>/dev/null || true)
assert_eq "N4: the command that ignored SIGTERM is gone" "no" "$([ -n "$tp" ] && alive "$tp" && echo yes || echo no)"
assert_eq "N4: a stopped command is not followed by typing (0 bytes)" "0" "$(inbytes z4)"
assert_eq "minor 2 (round 4): no raw job notice such as Terminated or Killed reaches the output" "" "$(printf '%s\n' "$out" | grep -E 'Terminated|Killed' || true)"
set_runtime claude-code
# ---- minors 1 and 2: the whole-word check ----------------------------------------------------
start z5
jq -cn '{type: "user", message: {role: "user", content: "яho-wide0001: stop"} }' >> "$(trof z5)"
jq -cn '{type: "user", message: {role: "user", content: "ho-wide0002é stop"} }' >> "$(trof z5)"
jq -cn '{type: "user", message: {role: "user", content: "ho-glue0001ho-glue0001"} }' >> "$(trof z5)"
p6() { "$h" session "$run" proof z5 "$1" 2>&1 | cut -d' ' -f1-2; }
assert_eq "minor 1: a letter outside ASCII before the id blocks the match" "none id=ho-wide0001" "$(p6 ho-wide0001)"
assert_eq "minor 1: a letter outside ASCII after the id blocks the match" "none id=ho-wide0002" "$(p6 ho-wide0002)"
assert_eq "minor 2: an id glued to itself is no whole word" "none id=ho-glue0001" "$(p6 ho-glue0001)"

# ==== Fix round 4 of PR #95 (Codex security findings; minors) ==============================
# ---- Codex P2 (line 537): the Enter delay has a cap ----------------------------------------
set_runtime claude-code
start q1
screen q1 idle-empty
for bad in 11 '"abc"'; do
  jq --argjson d "$bad" '.terminal.enter_delay_seconds = $d' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
  t0=$(date +%s)
  rc=0; deliver q1 --text "run tests" >/dev/null 2>&1 || rc=$?
  assert_eq "Codex P2: terminal.enter_delay_seconds=$bad is refused (78) at once, 0 bytes typed" "78 0 yes" "$rc $(inbytes q1) $([ $(( $(date +%s) - t0 )) -le 5 ] && echo yes || echo no)"
done
jq '.terminal.enter_delay_seconds = 0' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"

# ---- Codex P2 (line 116): delivery never runs the account command ---------------------------
mkdir -p "$base/acct-cfg"
printf '{"schemaVersion": 2, "runtime": {"main": "claude-code"}, "delivery": {"wait_seconds": 2}, "accounts": {"roles": {"worker": "acct-one"}, "list": {"acct-one": {"env_command": "echo run >> %s/acct-runs; echo CLAUDE_CONFIG_DIR=%s/acct-cfg"} } } }\n' "$base" "$base" > "$user/config.json"
start q2
screen q2 idle-empty
assert_eq "Codex P2: the launch records the account's config folder for delivery" "$base/acct-cfg" "$(rec q2 .transcript_root)"
runs=$(wc -l < "$base/acct-runs" | tr -d ' ')
out=$(deliver q2 --text "run tests" 2>&1) && rc=0 || rc=$?
assert_eq "Codex P2: delivery finds the transcript in the recorded folder (exit 0)" "0" "$rc"
assert_eq "Codex P2: delivery never runs the account command" "$runs" "$(wc -l < "$base/acct-runs" | tr -d ' ')"
jq '.transcript_root = "relative/path" | del(.transcript)' "$run/sessions/q2.json" > "$base/r.json" && mv "$base/r.json" "$run/sessions/q2.json"
out=$(deliver q2 --text "run tests" 2>&1) && rc=0 || rc=$?
assert_eq "Codex P2: a recorded folder that is not absolute is refused; nothing is typed (exit 1)" "1 1" "$rc $(grep -c . "$(fin q2)")"
set_runtime claude-code

# ==== Fix round 5 of PR #95 (Codex security P2 line 317; validator items 1 and 2D) ==========
set_runtime claude-code
mkdir -p "$proj/bin"
# The planted programs log their arguments and then run the real one, because the engine's own
# "#!/usr/bin/env bash" scripts (and the fakes) also resolve through this PATH; that is the
# launch-side PATH matter of issue #91. Delivery's own calls must never reach them.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/planted-bash.log"\nexec /bin/bash "$@"\n' "$base" > "$proj/bin/bash"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/planted-env.log"\nexec /usr/bin/env "$@"\n' "$base" > "$proj/bin/env"
chmod 700 "$proj/bin/bash" "$proj/bin/env"
planted() { cat "$base/planted-bash.log" "$base/planted-env.log" 2>/dev/null | grep -e "$1" || true; }
# ---- Codex P2 (line 317): the version check runs with a fixed PATH ---------------------------
start r1
screen r1 busy
: > "$(fbusy r1)"
# A positive force-send passes through the queue and the screen gate: a longer wait.
set_wait 10
out=$(PATH="$proj/bin:$PATH" HO_FAKE_CLAUDE_VERSION=2.1.332 deliver r1 --force-send --text "stop now" 2>&1) && rc=0 || rc=$?
set_wait 2
assert_eq "Codex P2: a bash or env planted in a project folder first on PATH never runs the version check" "" "$(planted '--version')"
assert_contains "Codex P2: the planted programs were on PATH (the engine's own scripts went through them)" "$(cat "$base/planted-bash.log" 2>/dev/null || true)" "session"
assert_eq "Codex P2: the force-send still works with the fixed PATH (exit 0)" "0" "$rc"
# ---- and the message command runs with the same fixed PATH ----------------------------------
set_runtime claude-msg
start r2
screen r2 idle-empty
out=$(PATH="$proj/bin:$PATH" HO_FAKE_MSG_MODE=deliver deliver r2 --text "run tests" 2>&1) && rc=0 || rc=$?
assert_eq "Codex P2: neither planted program runs the message command" "" "$(planted 'fake-msg')"
assert_eq "Codex P2: the message command still delivers (exit 0)" "0" "$rc"
# ---- validator item 1: an exit by a signal is unknown, not a proven failure -----------------
start r3
screen r3 idle-empty
out=$(HO_FAKE_MSG_MODE=signal-exit deliver r3 --text "run tests" 2>&1) && rc=0 || rc=$?
assert_eq "item 1, H-101: a message command ended by a signal is unknown; nothing is typed (exit 1, 0 bytes)" "1 0" "$rc $(inbytes r3)"
assert_contains "item 1: it is reported as unknown, not sent again" "$out" "unknown, not sent again"
# ---- validator item 1: delivery.wait_seconds is at least 2, and from the user config only ---
set_runtime claude-code
start r4
screen r4 idle-empty
set_wait 1
rc=0; deliver r4 --text "run tests" >/dev/null 2>&1 || rc=$?
assert_eq "item 1: delivery.wait_seconds below 2 is refused (78), 0 bytes typed" "78 0" "$rc $(inbytes r4)"
set_wait 2
jq '.delivery.wait_seconds = 5' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
rc=0; deliver r4 --text "run tests" >/dev/null 2>&1 || rc=$?
assert_eq "item 1: delivery.wait_seconds in the project config is refused (65), 0 bytes typed" "65 0" "$rc $(inbytes r4)"
jq 'del(.delivery.wait_seconds)' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
# ---- validator item 2D: a transcript folder inside the project is refused --------------------
start r5
s5=$(rec r5 .session_id)
mkdir -p "$proj/.harness/fake-root/projects/x"
jq -cn '{type: "user", message: {role: "user", content: "ho-plant0001: stop"} }' > "$proj/.harness/fake-root/projects/x/$s5.jsonl"
jq --arg r "$proj/.harness/fake-root" '.transcript_root = $r | del(.transcript)' "$run/sessions/r5.json" > "$base/r.json" && mv "$base/r.json" "$run/sessions/r5.json"
rc=0; o=$("$h" session "$run" proof r5 ho-plant0001 2>&1) || rc=$?
assert_eq "item 2D: a transcript folder inside the project cannot forge a proof (exit 1)" "1" "$rc"
assert_eq "item 2D: no delivered line for the planted record" "" "$(printf '%s' "$o" | grep '^delivered' || true)"
# ---- validator item 2D: the cached transcript must name the record's session ID -------------
start r6
start r7
jq -cn '{type: "user", message: {role: "user", content: "ho-other0001: stop"} }' >> "$(trof r7)"
jq --arg t "$(trof r7)" '.transcript = $t' "$run/sessions/r6.json" > "$base/r.json" && mv "$base/r.json" "$run/sessions/r6.json"
assert_eq "item 2D: a cached transcript of another session is not used" "none id=ho-other0001" \
  "$("$h" session "$run" proof r6 ho-other0001 2>&1 | cut -d' ' -f1-2)"

# ==== Fix round 6 of PR #95 (validator B4 = Codex P2 line 327; Codex P2 line 275; minors) ===
# The screen fixtures of T14 are used as shapes only; no test prints them.
set_runtime claude-code
R6='────────────────────────────────────────'
# IC: the idle prompt colour. An idle screen must show it, or idle is not proven (PR #105).
IC=$(printf '\033[39m')
sf="$HO_TESTS_DIR/fixtures/screen"
# frame <fixture>: the fixture without its last line (a bare prompt or a frame end), then a
# framed empty prompt, as the idle screen shows it.
frame() { sed '$d' "$sf/$1.txt"; printf '%s\n%s> \n%s\n' "$R6" "$IC" "$R6"; }
hold_case() { # <name> <label> <screen-builder...>
  local nm=$1 label=$2
  shift 2
  start "$nm"
  "$@" > "$(fout "$nm")"
  out=$(deliver "$nm" --text "run tests" 2>&1) && rc=0 || rc=$?
  assert_eq "B4, D42g: $label: 0 bytes typed, no Enter (exit 1)" "1 0" "$rc $(inbytes "$nm")"
  assert_eq "B4, D42g: $label: no Enter key reached the session" "" "$(calls | grep -F "key $(rec "$nm" .handle) Enter" || true)"
  # HC_HOLD=1: the screen shows the idle colour, so the refusal must name the hold itself,
  # not "idle is not proven" (PR #105 review round 2, m4).
  [ "${HC_HOLD:-}" != 1 ] || assert_contains "B4: $label: refused because of the hold" "$out" "hold (D42g)"
}
for fx in limit-notice-plain limit-notice-short limit-notice-contraction; do
  HC_HOLD=1 hold_case "h-$fx" "a limit notice above a framed empty prompt ($fx)" frame "$fx"
done
HC_HOLD=1 hold_case h-trust "a trust dialog above a framed empty prompt" frame trust-dialog
pw() { cat "$screens/idle-empty.txt"; tail -n 1 "$sf/password-prompt.txt"; }
HC_HOLD=1 hold_case h-pass "the idle screen with a password prompt line below it" pw
assert_contains "B4: the report names the hold" "$out" "hold"
# No chord on a hold, with --force-send on a busy session.
start h-chord
frame limit-notice-plain > "$(fout h-chord)"
: > "$(fbusy h-chord)"
out=$(HO_FAKE_CLAUDE_VERSION=2.1.332 deliver h-chord --force-send --text "stop now" 2>&1) && rc=0 || rc=$?
assert_eq "B4: a hold gets no chord and no typed text, also with --force-send" "1 0" "$rc $(inbytes h-chord)"
# A stale notice with later text below it reads as no hold: the continue message goes through.
stale() { sed '$d' "$sf/limit-notice-plain.txt"; printf 'Later the session went on with other work.\nIt wrote a summary of the tests.\n%s\n%s> \n%s\n' "$R6" "$IC" "$R6"; }
start h-stale
stale > "$(fout h-stale)"
out=$(deliver h-stale --text "continue" 2>&1) && rc=0 || rc=$?
assert_eq "B4: a stale notice followed by later text is no hold; the continue message is delivered (exit 0)" "0" "$rc"
# ---- Codex P2 (line 275): a separator inside a multi-line draft ------------------------------
start h-sep
printf ' Fake runtime 0.0.0\n\n%s\n> \n  ────────────\n  unfinished owner text\n%s\n  ? for shortcuts\n' "$R6" "$R6" > "$(fout h-sep)"
out=$(deliver h-sep --text "run tests" 2>&1) && rc=0 || rc=$?
assert_eq "Codex P2: a separator inside a multi-line draft does not hide the draft (0 bytes, exit 1)" "1 0" "$rc $(inbytes h-sep)"
assert_contains "Codex P2: it is reported as a draft" "$out" "input line holds text typed by the user"
# ---- minor 2: the cached path must name the session ID as a whole part ----------------------
start h-sub
ssub=$(rec h-sub .session_id)
tsub=$(trof h-sub)
cp "$tsub" "$(dirname "$tsub")/x${ssub}y.jsonl"
jq -cn '{type: "user", message: {role: "user", content: "ho-subs0001: stop"} }' >> "$(dirname "$tsub")/x${ssub}y.jsonl"
jq --arg t "$(dirname "$tsub")/x${ssub}y.jsonl" '.transcript = $t' "$run/sessions/h-sub.json" > "$base/r.json" && mv "$base/r.json" "$run/sessions/h-sub.json"
assert_eq "minor 2: a cached path that holds the ID only inside a longer name is not used" "none id=ho-subs0001" \
  "$("$h" session "$run" proof h-sub ho-subs0001 2>&1 | cut -d' ' -f1-2)"
# ---- minor 3: delivery.wait_seconds must be a JSON number ------------------------------------
start h-wait
screen h-wait idle-empty
printf '{"schemaVersion": 2, "runtime": {"main": "claude-code"}, "delivery": {"wait_seconds": "5"} }\n' > "$user/config.json"
rc=0; deliver h-wait --text "run tests" >/dev/null 2>&1 || rc=$?
assert_eq "minor 3: delivery.wait_seconds given as a string is refused (78), 0 bytes typed" "78 0" "$rc $(inbytes h-wait)"
set_runtime claude-code

# ==== Fix round 7 of PR #95 (validator B5; Codex security P2 lines 394 and 510; minors) =====
set_runtime claude-code
R7='────────────────────────────────────────'
# tall <n> <first-line> <inner...>: a framed box whose closing rule line is <n> lines below
# the input line; the inner lines come first, then blank lines.
tall() {
  local n=$1 first=$2 i=1
  shift 2
  printf ' Fake runtime 0.0.0\n\n%s\n%s>%s\n' "$R7" "$IC" "$first"
  for l in "$@"; do printf '%s\n' "$l"; i=$((i + 1)); done
  while [ "$i" -lt "$n" ]; do printf '\n'; i=$((i + 1)); done
  printf '%s\n  ? for shortcuts\n' "$R7"
}
b5() { # <name> <label> <expect: draft|empty> <tall args...>
  local nm=$1 label=$2 want=$3
  shift 3
  start "$nm"
  tall "$@" > "$(fout "$nm")"
  out=$(deliver "$nm" --text "run tests" 2>&1) && rc=0 || rc=$?
  if [ "$want" = draft ]; then
    assert_eq "B5, H-099: $label: 0 bytes, no Enter (exit 1)" "1 0" "$rc $(inbytes "$nm")"
  else
    assert_eq "B5: $label: typed and delivered (exit 0)" "0" "$rc"
  fi
}
for N in 21 40; do
  b5 "b5-$N" "a separator and text, closing frame $N lines down" draft "$N" " " "  ────────────" "  some text of the owner" "  more text"
done
b5 b5-25 "a separator and text, closing frame 25 lines down" draft 25 " " "  ────────────" "  some text of the owner"
b5 b5-sep "a draft that is only a separator line" draft 3 " " "  ────────────"
b5 b5-empty25 "an empty box whose closing frame is 25 lines down" empty 25 " "
# A second input line on the screen reads as a draft.
start b5-two
printf ' Fake runtime 0.0.0\n%s\n> \n%s\nolder text\n%s\n> \n%s\n  ? for shortcuts\n' "$R7" "$R7" "$R7" "$R7" > "$(fout b5-two)"
out=$(deliver b5-two --text "run tests" 2>&1) && rc=0 || rc=$?
assert_eq "B5: two input lines on the screen read as a draft (0 bytes, exit 1)" "1 0" "$rc $(inbytes b5-two)"

# ---- minor 1: the chord passes the same screen gate as typing ----------------------------------
set_runtime claude-msg
start c7-draft
screen c7-draft busy-draft
out=$(HO_FAKE_MSG_MODE=queue HO_FAKE_CLAUDE_VERSION=2.1.332 deliver c7-draft --force-send --text "stop now" 2>&1) && rc=0 || rc=$?
assert_eq "minor 1: a queued stop gets no chord while the input line holds a draft" "" "$(calls | grep "byte $(rec c7-draft .handle) " || true)"
jq 'del(.screen_file)' "$plug/runtimes/claude-msg.json" > "$plug/runtimes/claude-noscreen.json"
set_runtime claude-noscreen
start c7-noreader
screen c7-noreader busy
out=$(HO_FAKE_MSG_MODE=queue HO_FAKE_CLAUDE_VERSION=2.1.332 deliver c7-noreader --force-send --text "stop now" 2>&1) && rc=0 || rc=$?
assert_eq "minor 1: a queued stop gets no chord when the screen reader cannot run" "" "$(calls | grep "byte $(rec c7-noreader .handle) " || true)"

# ---- minor 3: the screen reader uses the session's own runtime --------------------------------
jq '.shapes |= map(select(.id == "password"))' "$plug/runtimes/claude-code.screen.json" > "$plug/runtimes/other.screen.json"
jq '.screen_file = "other.screen.json"' "$plug/runtimes/claude-code.json" > "$plug/runtimes/claude-other.json"
set_runtime claude-code
start c7-own
{ sed '$d' "$sf/limit-notice-plain.txt"; printf '%s\n%s> \n%s\n' "$R7" "$IC" "$R7"; } > "$(fout c7-own)"
set_runtime claude-other
out=$(deliver c7-own --text "run tests" 2>&1) && rc=0 || rc=$?
assert_eq "minor 3: a hold is read with the pattern file of the session's runtime, not runtime.main (0 bytes)" "1 0" "$rc $(inbytes c7-own)"
set_runtime claude-code

# ---- minor 6: every CSI code is stripped before the screen is read ----------------------------
E7=$(printf '\033')
start c7-csi
{ sed '$d' "$sf/limit-notice-plain.txt" | sed "s/^/${E7}[2K${E7}[38:2::255:0:0m/; s/\$/${E7}[0m/"; printf '%s\n%s> \n%s\n' "$R7" "$IC" "$R7"; } > "$(fout c7-csi)"
out=$(deliver c7-csi --text "run tests" 2>&1) && rc=0 || rc=$?
assert_eq "minor 6: a hold wrapped in colon-form and non-colour CSI codes is still a hold (0 bytes)" "1 0" "$rc $(inbytes c7-csi)"
start c7-esc
{ printf '%sX\n' "$E7"; cat "$screens/idle-empty.txt"; } > "$(fout c7-esc)"
out=$(deliver c7-esc --text "run tests" 2>&1) && rc=0 || rc=$?
assert_eq "minor 6: an escape byte left after stripping reads as unknown (0 bytes)" "1 0" "$rc $(inbytes c7-esc)"

# ---- minor 5: no capture file is left behind -----------------------------------------------------
assert_eq "minor 5: no capture file of delivery is left in the run's screen folder" "" "$(ls -A "$run/screen" 2>/dev/null | grep '^\.deliver\.' || true)"

# ---- Codex P2 (line 394): the version parser and compare do not use the caller's awk -----------
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/planted-awk.log"\nexec /usr/bin/awk "$@"\n' "$base" > "$proj/bin/awk"
chmod 700 "$proj/bin/awk"
start c7-awk
screen c7-awk busy
: > "$(fbusy c7-awk)"
# A positive force-send passes through the queue and the screen gate: a longer wait.
set_wait 10
out=$(PATH="$proj/bin:$PATH" HO_FAKE_CLAUDE_VERSION=2.1.332 deliver c7-awk --force-send --text "stop now" 2>&1) && rc=0 || rc=$?
set_wait 2
assert_eq "Codex P2: an awk planted first on PATH never reads the runtime's version" "" "$(grep -e 'print \$1' -e '2.1.275' "$base/planted-awk.log" 2>/dev/null || true)"
assert_eq "Codex P2: the force-send still works (exit 0)" "0" "$rc"

# ---- Codex P2 (line 510): delivery safety settings, user config only and bounded --------------
start c7-set
screen c7-set idle-empty
for k in terminal.typed_max_bytes delivery.message_timeout_seconds delivery.message_kill_grace_seconds; do
  jq --arg k "$k" 'setpath($k | split("."); 0)' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
  rc=0; deliver c7-set --text "run tests" >/dev/null 2>&1 || rc=$?
  assert_eq "Codex P2: $k in the project config is refused (65), 0 bytes typed" "65 0" "$rc $(inbytes c7-set)"
  jq --arg k "$k" 'delpaths([$k | split(".")])' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
done
for v in 0 100 1001 '"800"'; do
  printf '{"schemaVersion": 2, "runtime": {"main": "claude-code"}, "delivery": {"wait_seconds": 2}, "terminal": {"typed_max_bytes": %s} }\n' "$v" > "$user/config.json"
  rc=0; deliver c7-set --text "run tests" >/dev/null 2>&1 || rc=$?
  assert_eq "Codex P2: terminal.typed_max_bytes=$v in the user config is refused (78), 0 bytes typed" "78 0" "$rc $(inbytes c7-set)"
done
set_runtime claude-code

# ==== Fix round 8 of PR #95 (validator B6; a hold before Enter; Codex P2 line 170; minors) ===
set_runtime claude-code
R8='────────────────────────────────────────'
H8='━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
hdr8() { printf ' Fake runtime 0.0.0\n\n'; }
cut_a() { hdr8; printf '%s\n> \n  ────────────\n' "$R8"; }
cut_b() { hdr8; printf '%s\n> \n  ────────────\n  owner text\n  owner more\n' "$R8"; }
topcut() { printf '  owner text line\n  owner more\n────────────\n> \n%s\n  ? for shortcuts\n' "$R8"; }
topcut_engine() { local i=0; hdr8; printf '%s\n> \n' "$R8"; while [ "$i" -lt 62 ]; do printf '  owner line %s\n' "$i"; i=$((i + 1)); done; printf '────────────\n> \n%s\n  ? for shortcuts\n' "$R8"; }
mixed() { hdr8; printf '%s\n> \n  ────────────\n  owner text\n%s\n  ? for shortcuts\n' "$R8" "$H8"; }
for shape in cut_a cut_b topcut topcut_engine mixed; do
  nm="b6-$(printf '%s' "$shape" | tr '_' '-')"
  start "$nm"
  "$shape" > "$(fout "$nm")"
  out=$(deliver "$nm" --text "run tests" 2>&1) && rc=0 || rc=$?
  assert_eq "B6, H-099: a person's rule line cannot stand in for a frame ($shape): 0 bytes, exit 1" "1 0" "$rc $(inbytes "$nm")"
done
for fx in idle-empty suggestion; do
  start "b6-ok-$fx"
  screen "b6-ok-$fx" "$fx"
  out=$(deliver "b6-ok-$fx" --text "run tests" 2>&1) && rc=0 || rc=$?
  assert_eq "B6: the shipped idle fixture $fx is still delivered (exit 0)" "0" "$rc"
done

# ---- a hold or a busy mark that appears between typing and Enter ----------------------------
hf8() { sed '$d' "$sf/limit-notice-plain.txt"; printf '%s\n%s> \n%s\n' "$R8" "$IC" "$R8"; }
tf8() { sed '$d' "$sf/trust-dialog.txt"; printf '%s\n%s> \n%s\n' "$R8" "$IC" "$R8"; }
busy8() { cat "$screens/busy.txt"; }
cp "$proj/.harness/config.json" "$base/proj8.bak"
dcase8() { # <name> <label> <delay> <builder>
  local nm=$1 label=$2 delay=$3 b=$4 dp i=0
  start "$nm"
  screen "$nm" idle-empty
  jq --argjson d "$delay" '.terminal.enter_delay_seconds = $d' "$base/proj8.bak" > "$proj/.harness/config.json"
  deliver "$nm" --text "run tests" > "$base/$nm.out" 2>&1 &
  dp=$!
  while [ "$(inbytes "$nm")" = 0 ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  sleep 0.5
  "$b" > "$(fout "$nm")"
  rc=0; wait "$dp" || rc=$?
  cp "$base/proj8.bak" "$proj/.harness/config.json"
  assert_eq "round 8: $label: no Enter is sent (exit 1)" "1 " "$rc $(calls | grep -F "key $(rec "$nm" .handle) Enter" || true)"
  assert_contains "round 8: $label: the owner is told the text sits typed on the input line" "$(ledger | jq -r 'select(.kind == "owner-action") | .title')" "typed text waits on the input line of session $nm"
}
dcase8 d8-limit2 "a limit notice appears during a 2 s Enter delay" 2 hf8
dcase8 d8-limit10 "a limit notice appears during a 10 s Enter delay" 10 hf8
dcase8 d8-trust4 "a trust dialog appears during a 4 s Enter delay" 4 tf8
dcase8 d8-busy4 "a busy mark appears during a 4 s Enter delay" 4 busy8

# ---- Codex P2 (line 170): the cached path is resolved before it is checked ------------------
start c8
s8=$(rec c8 .session_id)
mkdir -p "$HOME/.claude/$s8" "$base/elsewhere"
jq -cn '{type: "user", message: {role: "user", content: "ho-dots0001: stop"} }' > "$base/elsewhere/t.jsonl"
jq --arg t "$HOME/.claude/$s8/../../${base#"$HOME"/}/elsewhere/t.jsonl" '.transcript = $t' "$run/sessions/c8.json" > "$base/r.json" && mv "$base/r.json" "$run/sessions/c8.json"
assert_eq "Codex P2: a cached path with .. segments that leaves the root is not used" "none id=ho-dots0001" \
  "$("$h" session "$run" proof c8 ho-dots0001 2>&1 | cut -d' ' -f1-2)"

# ---- minors: presence in the project config; enter delay as a JSON number --------------------
start m8b
screen m8b idle-empty
jq '.delivery.message_timeout_seconds = false' "$base/proj8.bak" > "$proj/.harness/config.json"
rc=0; deliver m8b --text "run tests" >/dev/null 2>&1 || rc=$?
assert_eq "minor: a user-only key set to false in the project config is refused (65), 0 bytes" "65 0" "$rc $(inbytes m8b)"
jq '.terminal.enter_delay_seconds = "1"' "$base/proj8.bak" > "$proj/.harness/config.json"
rc=0; deliver m8b --text "run tests" >/dev/null 2>&1 || rc=$?
assert_eq "minor: terminal.enter_delay_seconds given as a string is refused (78), 0 bytes" "78 0" "$rc $(inbytes m8b)"
cp "$base/proj8.bak" "$proj/.harness/config.json"

# ==== Fix round 9 of PR #95 (validator B7; Codex P2 lines 191 and 454) =========================
set_runtime claude-code
# ---- B7: the owner-action line of the busy branch holds no screen text -----------------------
start d9-busy
screen d9-busy idle-empty
jq '.terminal.enter_delay_seconds = 4' "$base/proj8.bak" > "$proj/.harness/config.json"
HO_FAKE_TERM_ECHO_EXTRA=ZKEYZ deliver d9-busy --text "run tests PAYLOADZ" > "$base/d9.out" 2>&1 &
d9=$!
i=0; while [ "$(inbytes d9-busy)" = 0 ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
sleep 0.5
busy8 > "$(fout d9-busy)"
rc=0; wait "$d9" || rc=$?
cp "$base/proj8.bak" "$proj/.harness/config.json"
oa=$(ledger | jq -c 'select(.kind == "owner-action" and (.title | contains("d9-busy")))')
assert_eq "B7: a busy mark before Enter gives no Enter and one owner-action line" "1 1" "$rc $(printf '%s\n' "$oa" | grep -c . || true)"
assert_eq "B7: the whole owner-action line holds neither the instruction text nor a typed key" "" "$(printf '%s\n' "$oa" | grep -e PAYLOADZ -e ZKEYZ || true)"
assert_eq "B7: no ledger line of that delivery holds the instruction text or a typed key" "" "$(ledger | grep -F d9-busy | grep -e PAYLOADZ -e ZKEYZ || true)"

# ---- Codex P2 (line 191): no linked folder below the transcript root -------------------------
start d9-link
s9=$(rec d9-link .session_id)
mkdir -p "$base/elsewhere9/x"
jq -cn '{type: "user", message: {role: "user", content: "ho-link0001: stop"} }' > "$base/elsewhere9/x/$s9.jsonl"
rm -f "$(trof d9-link)"
ln -s "$base/elsewhere9/x" "$HOME/.claude/projects/aaa-linked"
jq 'del(.transcript)' "$run/sessions/d9-link.json" > "$base/r.json" && mv "$base/r.json" "$run/sessions/d9-link.json"
rc=0; o=$("$h" session "$run" proof d9-link ho-link0001 2>&1) || rc=$?
assert_eq "Codex P2: a linked folder below the transcript root cannot forge a proof (exit 1)" "1" "$rc"
assert_eq "Codex P2: no delivered line through the linked folder" "" "$(printf '%s' "$o" | grep '^delivered' || true)"
rm -f "$HOME/.claude/projects/aaa-linked"

# ---- Codex P2 (line 454): the version check has a time bound --------------------------------
start d9-ver
screen d9-ver busy
: > "$(fbusy d9-ver)"
set_wait 10
t0=$(date +%s)
out=$(HO_FAKE_CLAUDE_VERSION=2.1.332 HO_FAKE_CLAUDE_VERSION_SLEEP=60 deliver d9-ver --force-send --text "stop now" 2>&1) && rc=0 || rc=$?
el=$(( $(date +%s) - t0 ))
set_wait 2
# The version check would hang 60 s; returning within 40 s proves it was stopped, with room
# for a loaded machine (the bound was 16 s against a 20 s hang, and took 20 s under load).
assert_eq "Codex P2: a version check that hangs is stopped; deliver returns within the bound (at most 40 s)" "yes" "$([ "$el" -le 40 ] && echo yes || echo "no (${el}s)")"
assert_eq "Codex P2: with the version unknown no chord is sent" "" "$(calls | grep "byte $(rec d9-ver .handle) " || true)"
assert_contains "Codex P2: the skipped chord names the unknown version" "$(ledger | grep -F deliver-force-send | tail -n 1)" "unknown"

# ==== Issue #104: the real Claude Code screen layout ============================================
# tests/fixtures/screens-real holds styled screens in the real layout: the prompt is the
# runtime's mark with a no-break space, and the runtime's status lines and agent list sit under
# the box. At 64 columns the busy hint shows only there, cut short. No test prints a screen.
set_runtime claude-code
set_wait 2
real="$HO_TESTS_DIR/fixtures/screens-real"
rscreen() { cat "$real/$2.txt" > "$(fout "$1")"; }
for fx in idle-full idle-status idle-box-only wide-idle-full idle-notification; do
  start "r104-$fx"
  rscreen "r104-$fx" "$fx"
  out=$(deliver "r104-$fx" --text "run the unit tests" 2>&1) && rc=0 || rc=$?
  assert_eq "#104, H-099: the real idle screen ($fx) gets the instruction typed and proven (exit 0)" "0" "$rc"
done
for fx in draft-one-line draft-multi-line draft-separator-only busy-draft; do
  start "r104-$fx"
  rscreen "r104-$fx" "$fx"
  out=$(deliver "r104-$fx" --text "run the unit tests" 2>&1) && rc=0 || rc=$?
  assert_eq "#104, H-099: a draft in the real box ($fx) gets 0 bytes (exit 1)" "1 0" "$rc $(inbytes "r104-$fx")"
  assert_contains "#104, H-099: the real draft ($fx) is reported as the user's text" "$out" "input line holds text typed by the user"
  assert_eq "#104, H-099: no Enter key reached the session ($fx)" "" "$(calls | grep -F "key $(rec "r104-$fx" .handle) Enter" || true)"
done
# busy-cut-before-hint: the status line is cut before the busy hint; the dim prompt still shows it.
for fx in busy-full busy-status wide-busy-full busy-cut-before-hint; do
  start "r104-$fx"
  rscreen "r104-$fx" "$fx"
  out=$(deliver "r104-$fx" --text "run the unit tests" 2>&1) && rc=0 || rc=$?
  assert_eq "#104, D42g: the real busy screen ($fx) gets 0 bytes (exit 1)" "1 0" "$rc $(inbytes "r104-$fx")"
  assert_contains "#104, D42g: the real busy screen ($fx) is reported as busy" "$out" "the session is busy; nothing was typed"
done
# A hold above the real box: the T14 fixtures spliced in by script.
rhead() { LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*m//g" "$real/idle-full.txt" | awk '/^────/ { exit } { print }'; }
rtail() { awk -v e="$(printf '\033')" 'index($0, e "[38;5;244m─") == 1 { t = 1 } t { print }' "$real/$1.txt"; }
# rhold <fixture> <real screen> <lines to drop>: a T14 fixture between the real text and the box.
rhold() { local n; n=$(awk 'END { print NR }' "$sf/$1.txt"); rhead; head -n "$((n - $3))" "$sf/$1.txt"; rtail "$2"; }
for tl in idle-full draft-one-line busy-full; do
  for fx in limit-notice-plain limit-notice-short; do
    hold_case "r104-h-$fx-$tl" "a hold ($fx) above the real box ($tl)" rhold "$fx" "$tl" 1
  done
  hold_case "r104-h-trust-$tl" "a hold (trust-dialog) above the real box ($tl)" rhold trust-dialog "$tl" 0
  hold_case "r104-h-pass-$tl" "a hold (password-prompt) above the real box ($tl)" rhold password-prompt "$tl" 0
done
# A hold above the runtime's notification line, which is glued to the top rule of the box.
rntail() { awk -v e="$(printf '\033')" 'index($0, e "[38;5;244m─") == 1 && !t { print prev; t = 1 } t { print } { prev = $0 }' "$real/idle-notification.txt"; }
rnhold() { local n; n=$(awk 'END { print NR }' "$sf/$1.txt"); rhead; head -n "$((n - $2))" "$sf/$1.txt"; rntail; }
hold_case r104-hn-limit "a hold (limit-notice-plain) above the notification line and the real box" rnhold limit-notice-plain 1
hold_case r104-hn-limit-glued "a hold (limit-notice-plain, glued) above the notification line and the real box" rnhold limit-notice-plain 2
hold_case r104-hn-trust "a hold (trust-dialog) above the notification line and the real box" rnhold trust-dialog 0

# ==== PR #105 review round 1 (Codex P1): idle is proven, never read from a missing busy mark ====
# A capture without colour (iTerm2 keeps none) cannot show the busy prompt colour. When the
# status line is cut before the busy hint, such a screen looks idle. Each cut point of the real
# busy status line, without colour, must get 0 bytes.
plainc() { LC_ALL=C sed "s/$(printf '\033')\[[0-9;]*m//g" "$1"; }
s2=$(plainc "$real/busy-full.txt" | grep -n '⏵⏵' | cut -d: -f1)
s2line=$(plainc "$real/busy-full.txt" | sed -n "${s2}p")
s2len=$(printf '%s' "$s2line" | LC_ALL=C wc -c | tr -d ' ')
cuts=0
c=4
while [ "$c" -lt "$s2len" ]; do
  cut=$(printf '%s' "$s2line" | LC_ALL=C head -c "$c")
  # a cut inside a multi-byte character is no screen line: skip it
  if printf '%s' "$cut" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
    nm="rr1-cut-$c"
    start "$nm"
    plainc "$real/busy-full.txt" | awk -v n="$s2" -v l="$cut…" 'NR == n { print l; next } { print }' > "$(fout "$nm")"
    out=$(deliver "$nm" --text "run the unit tests" 2>&1) && rc=0 || rc=$?
    assert_eq "PR #105 round 1: a colourless busy screen, status line cut at byte $c, gets 0 bytes (exit 1)" "1 0" "$rc $(inbytes "$nm")"
    cuts=$((cuts + 1))
  fi
  c=$((c + 2))
done
assert_eq "PR #105 round 1: the sweep covered at least 20 cut points" "yes" "$([ "$cuts" -ge 20 ] && echo yes || echo "no ($cuts)")"
# The real idle screen without colour: idle is not proven, so nothing is typed.
for fx in idle-full idle-status idle-box-only; do
  start "rr1-plain-$fx"
  plainc "$real/$fx.txt" > "$(fout "rr1-plain-$fx")"
  out=$(deliver "rr1-plain-$fx" --text "run the unit tests" 2>&1) && rc=0 || rc=$?
  assert_eq "PR #105 round 1: the real idle screen without colour ($fx) gets 0 bytes (exit 1)" "1 0" "$rc $(inbytes "rr1-plain-$fx")"
  assert_contains "PR #105 round 1: it is reported as not proven idle ($fx)" "$out" "idle is not proven"
done
# A styled screen whose status line is cut with no hint and whose prompt has no idle colour.
start rr1-nohint
{ awk -v e="$(printf '\033')" -v n="$s2" 'NR == n { print "  " e "[38;5;211m⏵⏵ bypass permissions on" e "[38;5;246m · " e "[38;5;44m12 backgrou…" e "[39m"; next }
  index($0, "❯") { sub(/^\033\[[0-9;]*m/, "\033[1m"); print; next } { print }' "$real/idle-full.txt"; } > "$(fout rr1-nohint)"
out=$(deliver rr1-nohint --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "PR #105 round 1: a cut status line with no hint and no idle prompt colour gets 0 bytes (exit 1)" "1 0" "$rc $(inbytes rr1-nohint)"
# The real idle screen on iTerm2 (no colours): nothing is typed.
jq '.terminal.app = "iterm2"' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
start rr1-iterm
rscreen rr1-iterm idle-full
out=$(deliver rr1-iterm --text "run the unit tests" 2>&1) && rc=0 || rc=$?
assert_eq "PR #105 round 1: on iTerm2 the real idle screen gets 0 bytes, idle cannot be proven (exit 1)" "1 0" "$rc $(inbytes rr1-iterm)"
jq '.terminal.app = "tmux"' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
# M1: a hold between the empty box and the status lines gets nothing typed. Only status-area
# lines may sit under the box.
rbox() { awk -v e="$(printf '\033')" 'index($0, e "[38;5;244m─") == 1 { c++ } { print } c == 2 { exit }' "$real/idle-full.txt"; }
rstatus() { awk -v e="$(printf '\033')" 'index($0, e "[38;5;244m─") == 1 { c++; next } c == 2 { print }' "$real/idle-full.txt"; }
rmid() { local n; n=$(awk 'END { print NR }' "$sf/$1.txt"); rbox; head -n "$((n - $2))" "$sf/$1.txt"; rstatus; }
hold_case rr1-m1-trust "M1: a trust dialog between the real box and its status lines" rmid trust-dialog 0
hold_case rr1-m1-pass "M1: a password prompt between the real box and its status lines" rmid password-prompt 0
hold_case rr1-m1-limit "M1: a limit notice (last line dropped) between the real box and its status lines" rmid limit-notice-plain 1
hold_case rr1-m1-limit-whole "M1: a whole limit notice between the real box and its status lines" rmid limit-notice-plain 0
# M2: a line with two leading spaces is not the status area unless it has a status shape.
prose2() { rbox; printf '  Neutral text that only starts with two spaces.\n'; rstatus; }
hold_case rr1-m2-prose "M2: a two-space text line between the real box and its status lines" prose2
# PR #105 review round 2: a stale hold, then a later indented line glued to the top rule, then
# the real box: no hold, so the continue message is delivered.
rlater() { local n; n=$(awk 'END { print NR }' "$sf/$1.txt"); rhead; head -n "$((n - $2))" "$sf/$1.txt"; printf '%*sThis is example output, not an active hold.\n' "$3" ''; rtail idle-full; }
start rr2-stale
rlater limit-notice-plain 1 10 > "$(fout rr2-stale)"
out=$(deliver rr2-stale --text "continue" 2>&1) && rc=0 || rc=$?
assert_eq "PR #105 round 2: a stale notice, then a later line indented 10 above the real box: no hold, delivered (exit 0)" "0" "$rc"
# A plain two-space line right under the box is not the status line: nothing is typed.
under1() { rbox; printf '  Neutral text that only starts with two spaces.\n'; }
hold_case rr2-under "PR #105 round 2: a plain two-space line right under the real box" under1
