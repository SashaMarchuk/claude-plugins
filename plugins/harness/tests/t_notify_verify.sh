# Every notification flow is checked and confirmed (issue #128; H-124). "notify <run> verify"
# reads the run's own evidence and reports each flow per channel: mirroring a question, reading
# a reply, writing the answer back to the tracker, announcing an event, and the fallback to the
# next channel. A flow with no evidence reads "not working". An mcp send counts only once the
# session reported it sent; the queue alone confirms nothing. Fake channels and the fake gh only.
. "$HO_TESTS_DIR/intake-setup.sh"
export HO_FAKE_CHANNEL_DIR="$base/channels"
mkdir -p "$HO_FAKE_CHANNEL_DIR"
jq -n '{schemaVersion: 2, identities: [{account: "alice", senders: {telegram: "111", slack: "U-ALICE"}}],
  notify: {channels: {tg: {preset: "telegram", via: "command", argv: ["fake-channel", "tg"]},
                      sl: {preset: "slack", via: "command", argv: ["fake-channel", "sl"]},
                      bot: {preset: "telegram", via: "mcp", mcp: "tg-bot"}}}}' > "$user/config.json"
printf 'Which page should change?\n' > "$base/q.md"
verify() { "$h" notify "$run" verify; }
line() { printf '%s\n' "$1" | grep -E "^$2: " || echo "$2: (no line)"; }
asked() { local t; t=$(ticket "$1"); label alice "$t" ready; tick >/dev/null; HO_RUN_DIR=$run HO_SESSION_ROLE=worker "$h" tickets ask "$t" "$base/q.md" >/dev/null; printf '%s\n' "$t"; }
ref_of() { jq -r --arg t "$2" 'select(.kind == "question" and .ticket == $t) | .ref' "$HO_FAKE_CHANNEL_DIR/$1/sent.jsonl"; }
reply() { jq -cn --arg id "$2" --arg r "$3" --arg s "$4" '{id: $id, reply_to: $r, sender: $s, text: "The report page."}' >> "$HO_FAKE_CHANNEL_DIR/$1/replies.jsonl"; }

# Nothing has run yet: every flow reads not working, and the verb fails.
rc=0; out=$(verify) || rc=$?
assert_eq "H-124: a flow that was not confirmed fails the verify (exit 69)" 69 "$rc"
for f in "question-mirror tg" "reply-read tg" "answer-written tg" "event-announced tg" "question-mirror bot" "fallback"; do
  assert_contains "H-124: before any run, $f reads not working" "$(line "$out" "$f")" "not working"
done
assert_eq "H-124: the verify writes nothing" "" "$(find "$run/notify" -type f 2>/dev/null || true)"

# A question: mirrored by both command channels and queued for the mcp channel.
t=$(asked "Verify question")
out=$(verify || true)
assert_contains "H-124: a sent question confirms the mirror on tg" "$(line "$out" "question-mirror tg")" "confirmed"
assert_contains "H-124: and on sl" "$(line "$out" "question-mirror sl")" "confirmed"
assert_contains "H-124: a question only queued for the mcp session is not confirmed" "$(line "$out" "question-mirror bot")" "not working"
"$h" notify "$run" sent "$(jq -r --arg t "$t" 'select(.kind == "question" and .ticket == $t) | .id' "$run/notify/outbox.jsonl")" botmsg-1 >/dev/null
out=$(verify || true)
assert_contains "H-124: the session's sent report confirms the mcp mirror" "$(line "$out" "question-mirror bot")" "confirmed"

# A reply: read on tg and written back to the tracker.
reply tg r1 "$(ref_of tg "$t")" 111
"$h" notify "$run" poll >/dev/null
out=$(verify || true)
assert_contains "H-124: a read reply confirms reading on tg" "$(line "$out" "reply-read tg")" "confirmed"
assert_contains "H-124: the recorded answer confirms the write-back on tg" "$(line "$out" "answer-written tg")" "confirmed"
assert_contains "H-124: sl read no reply yet" "$(line "$out" "reply-read sl")" "not working"

# An event on every channel; the mcp one counts after the session's report.
"$h" notify "$run" event done "$t" "ticket $t is done" >/dev/null
out=$(verify || true)
assert_contains "H-124: an announced event confirms tg" "$(line "$out" "event-announced tg")" "confirmed"
assert_contains "H-124: a queued mcp event is not confirmed" "$(line "$out" "event-announced bot")" "not working"

# The fallback: tg fails a question selected for tg only; sl takes it.
jq '.notify.questions = ["tg"]' "$user/config.json" > "$base/u.json" && mv "$base/u.json" "$user/config.json"
touch "$HO_FAKE_CHANNEL_DIR/tg/fail"
asked "Verify fallback" >/dev/null
rm -f "$HO_FAKE_CHANNEL_DIR/tg/fail"
out=$(verify || true)
assert_contains "H-124: a failed send taken by the next channel confirms the fallback" "$(line "$out" "fallback")" "confirmed"

# Two command channels only, every flow run: the verify passes.
jq 'del(.notify.channels.bot) | del(.notify.questions)' "$user/config.json" > "$base/u.json" && mv "$base/u.json" "$user/config.json"
t2=$(asked "Verify sl reply")
reply sl r2 "$(ref_of sl "$t2")" U-ALICE
"$h" notify "$run" poll >/dev/null
rc=0; out=$(verify) || rc=$?
assert_eq "H-124: with every flow confirmed on every channel the verify passes" "0" "$rc"
assert_eq "H-124: no flow reads not working" "" "$(printf '%s\n' "$out" | grep 'not working' || true)"

# No channel at all: nothing is confirmed.
printf '{"schemaVersion": 2}\n' > "$user/config.json"
rc=0; out=$(verify) || rc=$?
assert_eq "H-124: with no channel the verify fails" 69 "$rc"
assert_contains "H-124: with no channel the verify says so" "$out" "no channel"
