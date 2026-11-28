# Notification channels (T38; H-115, H-116, H-117, H-118, H-119, H-120, H-121, H-122, H-123;
# D36, S8-28a, D37-FLOW-8, D37-NOTIFICATIONS-2, D37-NOTIFICATIONS-3, D37-NOTIFICATIONS-5).
# Fake channels only (tests/fake-bin/fake-channel); never a real channel or token.
. "$HO_TESTS_DIR/intake-setup.sh"
export HO_FAKE_CHANNEL_DIR="$base/channels"
mkdir -p "$HO_FAKE_CHANNEL_DIR"
sent() { cat "$HO_FAKE_CHANNEL_DIR/$1/sent.jsonl" 2>/dev/null || true; }
nsent() { sent "$1" | grep -c . || true; }
reply() { # <channel> <id> <reply-to-ref> <sender> <text> [authenticated]
  jq -cn --arg id "$2" --arg r "$3" --arg s "$4" --arg t "$5" --argjson a "${6:-false}" \
    '{id: $id, reply_to: $r, sender: $s, text: $t, authenticated: $a}' >> "$HO_FAKE_CHANNEL_DIR/$1/replies.jsonl"
}
userconf() { # <notify-json>: the user config with channels and the identity map
  jq -n --argjson n "$1" '{schemaVersion: 2, notify: $n,
    identities: [{account: "alice", emails: ["alice@example.test"], senders: {telegram: "111", slack: "U-ALICE"}},
                 {account: "rita", emails: ["rita@example.test"], senders: {telegram: "222"}},
                 {account: "maya", emails: ["shared@example.test"], senders: {slack: "U-SHARED"}},
                 {account: "olga", emails: ["shared@example.test"], senders: {slack: "U-SHARED"}}]}' > "$user/config.json"
}
three='{"channels": {"tg": {"preset": "telegram", "via": "command", "argv": ["fake-channel", "tg"]},
  "sl": {"preset": "slack", "via": "command", "argv": ["fake-channel", "sl"]},
  "gm": {"preset": "gmail", "via": "command", "argv": ["fake-channel", "gm"]}}}'
printf 'Which page should change?\nHow do we tell it is done?\n' > "$base/q.md"
asked() { local t; t=$(ticket "$1"); label alice "$t" ready; tick >/dev/null; HO_RUN_DIR=$run HO_SESSION_ROLE=worker "$h" tickets ask "$t" "$base/q.md" >/dev/null; printf '%s\n' "$t"; }
qlines() { printf '%s' "$1" | grep -E '^[0-9]+\. ' || true; }

# H-115: no channel configured: the tracker only, nothing is sent, nothing is printed.
out=$(cd "$proj" && "$h" notify check)
assert_eq "H-115 no channel: questions and answers stay in the tracker" "no channel: questions and answers stay in the tracker" "$out"
t0=$(asked "No channel")
assert_eq "H-115 no channel: no notify state is written" "no" "$([ -e "$run/notify" ] && echo yes || echo no)"

# H-115 D37-FLOW-8: a project config that wires a channel by command is refused at start.
cp "$proj/.harness/config.json" "$base/proj-config.json"
jq '.notify.channels.tg = {"preset": "telegram", "via": "command", "argv": ["fake-channel", "tg"]}' "$base/proj-config.json" > "$proj/.harness/config.json"
select_config "$proj"
rc=0; err=$(cd "$proj" && "$h" run new 2>&1 >/dev/null) || rc=$?
assert_eq "D37-FLOW-8 a channel command in the project config refuses the run start" "78" "$rc"
assert_contains "D37-FLOW-8 the message says to move the command to the user config" "$err" "Move the command to the user config"
assert_eq "D37-FLOW-8 no command from the project config ran" "" "$(sent tg)"
# H-115 D36: a channel wired by mcp names a connector and may stay in the project config.
jq '.notify.channels.tg = {"preset": "telegram", "via": "mcp", "mcp": "telegram-bot"}' "$base/proj-config.json" > "$proj/.harness/config.json"
select_config "$proj"
assert_contains "D36 an mcp channel in the project config is accepted" "$(cd "$proj" && "$h" notify channels)" '"via":"mcp"'
cp "$base/proj-config.json" "$proj/.harness/config.json"
select_config "$proj"

# H-115: two channels enabled, Gmail left off.
userconf "$(jq -c '. + {use: ["tg", "sl"]}' <<<"$three")"
assert_eq "H-115 only the enabled channels are active" '["tg","sl"]' "$(cd "$proj" && "$h" notify channels | jq -c 'map(.label)')"

# H-116: a question goes to the tracker and the same lines to every selected channel.
userconf "$three"
t1=$(asked "Mirrored question")
tracker=$(jq -r '[.comments[] | select(.body | contains("harness:v1"))] | last | .body' "$HO_FAKE_GH_DIR/issues/$t1.json")
for c in tg sl gm; do
  msg=$(sent "$c" | jq -r --arg t "$t1" 'select(.kind == "question" and .ticket == $t) | .text')
  assert_eq "H-116 the question in channel $c has the tracker's wording and order" "$(qlines "$tracker")" "$(qlines "$msg")"
done
assert_contains "H-116 the tracker holds the question first" "$tracker" "1. Which page should change?"
assert_eq "S8-28a a question sets blocked but sends no second blocked event" "0" "$(sent tg | jq -r --arg t "$t1" 'select(.event == "blocked" and .ticket == $t)' | grep -c . || true)"
# H-116: one channel selected for questions.
userconf "$(jq -c '. + {questions: ["tg"]}' <<<"$three")"
nq() { sent "$1" | jq -r 'select(.kind == "question") | .ticket' | grep -c . || true; }
b_sl=$(nq sl)
t2=$(asked "One channel")
assert_eq "H-116 a question selected for Telegram only reaches Telegram" "1" "$(sent tg | jq -r --arg t "$t2" 'select(.kind == "question" and .ticket == $t) | .ticket' | grep -c .)"
assert_eq "H-116 the unselected channel gets no question" "$b_sl" "$(nq sl)"

# H-121: the first channel fails; the next by priority takes the message.
userconf "$(jq -c '. + {questions: ["tg"], priority: ["tg", "sl", "gm"]}' <<<"$three")"
touch "$HO_FAKE_CHANNEL_DIR/tg/fail"
t3=$(asked "Fallback")
assert_eq "H-121 when Telegram fails, Slack takes the question" "1" "$(sent sl | jq -r --arg t "$t3" 'select(.kind == "question" and .ticket == $t) | .ticket' | grep -c .)"
assert_eq "H-121 Gmail is not used once Slack took it" "0" "$(sent gm | jq -r --arg t "$t3" 'select(.kind == "question" and .ticket == $t) | .ticket' | grep -c . || true)"
assert_contains "H-121 the failure is in the run ledger" "$(ledger)" '"kind":"notify-failed","channel":"tg"'
# H-121: all channels fail; the tracker still holds the text.
touch "$HO_FAKE_CHANNEL_DIR/sl/fail" "$HO_FAKE_CHANNEL_DIR/gm/fail"
t4=$(asked "All fail")
assert_contains "H-121 every channel failed: one undelivered line" "$(ledger)" '"kind":"notify-undelivered"'
assert_contains "H-121 the question still exists in the tracker" "$(comments "$t4")" "Which page should change?"
rm -f "$HO_FAKE_CHANNEL_DIR"/*/fail
# H-121 S8-28a: with no priority set, the order of setup applies.
userconf "$three"
assert_eq "S8-28a no priority: the order of setup" '["tg","sl","gm"]' "$(cd "$proj" && "$h" notify channels | jq -c 'map(.label)')"
userconf "$(jq -c '. + {priority: ["gm"]}' <<<"$three")"
assert_eq "H-121 a set priority comes first, then the order of setup" '["gm","tg","sl"]' "$(cd "$proj" && "$h" notify channels | jq -c 'map(.label)')"

# H-118 H-119: the first answer read is recorded with its author; a later one gets the link.
userconf "$three"
t5=$(asked "Two answers")
ref_sl=$(sent sl | jq -r --arg t "$t5" 'select(.kind == "question" and .ticket == $t) | .ref')
ref_tg=$(sent tg | jq -r --arg t "$t5" 'select(.kind == "question" and .ticket == $t) | .ref')
reply sl m1 "$ref_sl" U-ALICE "1. The report page. 2. The export test passes."
out=$("$h" notify "$run" poll)
assert_contains "H-119 the first answer read is recorded" "$out" "answer $t5 sl"
reply tg m2 "$ref_tg" 222 "1. All pages."
out=$("$h" notify "$run" poll)
assert_contains "H-119 the later answer is not recorded" "$out" "late $t5 tg"
last=$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t5.json")
assert_contains "H-118 the answer is a comment on the ticket" "$last" "The report page."
assert_contains "H-118 H-122 the comment names the mapped author" "$last" '"author":"alice"'
assert_eq "H-119 the later answer never reaches the tracker" "" "$(comments "$t5" | grep -o 'All pages' || true)"
note=$(sent tg | jq -r 'select(.kind == "note" and .reply_to == "m2") | .text')
assert_contains "H-119 the later sender gets the tracker link" "$note" "https://github.com/fake/repo/issues/$t5"
assert_contains "H-119 the later sender is told to change it in the tracker" "$note" "directly in the tracker"
out=$(tick)
assert_contains "H-118 the recorded answer from a writer resumes the ticket" "$out" "resume $t5"
out=$("$h" notify "$run" poll)
assert_eq "H-120 a reply read once is not handled again" "" "$out"

# H-122 D37-NOTIFICATIONS-3: an unmapped and a shared sender are unmapped; the answer waits.
t6=$(asked "Unmapped sender")
ref=$(sent sl | jq -r --arg t "$t6" 'select(.kind == "question" and .ticket == $t) | .ref')
reply sl m3 "$ref" U-SHARED "Use the report page."
"$h" notify "$run" poll >/dev/null
last=$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t6.json")
assert_contains "H-122 a sender shared by two entries is unmapped" "$last" "unmapped sender slack:U-SHARED"
out=$(tick)
assert_contains "H-117 H-035 an unmapped author's answer moves the ticket to needs-review" "$out" "needs-review $t6"
# D37-NOTIFICATIONS-5: a writer's later channel answer is not applied; the writer gets the link.
reply tg m4 "$(sent tg | jq -r --arg t "$t6" 'select(.kind == "question" and .ticket == $t) | .ref')" 111 "Confirmed."
out=$("$h" notify "$run" poll)
assert_contains "D37-NOTIFICATIONS-5 a writer's later channel answer is not applied" "$out" "late $t6 tg"
# H-122: Gmail maps by address only when sender authentication passed.
t7=$(asked "Gmail answer")
ref=$(sent gm | jq -r --arg t "$t7" 'select(.kind == "question" and .ticket == $t) | .ref')
reply gm m5 "$ref" Alice@Example.test "The report page." false
"$h" notify "$run" poll >/dev/null
assert_contains "H-122 a Gmail sender without passed authentication is unmapped" "$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t7.json")" "unmapped sender gmail:"
t8=$(asked "Gmail answer ok")
ref=$(sent gm | jq -r --arg t "$t8" 'select(.kind == "question" and .ticket == $t) | .ref')
reply gm m6 "$ref" Alice@Example.test "The report page." true
"$h" notify "$run" poll >/dev/null
assert_contains "H-122 an authenticated Gmail sender maps by address" "$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t8.json")" '"author":"alice"'

# H-120 D37-NOTIFICATIONS-2: a message that answers no open question creates nothing.
before=$(jq -s length <<<"$(cat "$HO_FAKE_GH_DIR"/issues/*.json)")
reply tg m7 "" 111 "Please add a new task: build the export page."
out=$("$h" notify "$run" poll)
assert_eq "D37-NOTIFICATIONS-2 a new task in a channel creates no ticket" "$before" "$(jq -s length <<<"$(cat "$HO_FAKE_GH_DIR"/issues/*.json)")"
assert_eq "D37-NOTIFICATIONS-2 nothing acts on it" "" "$out"
assert_eq "D37-NOTIFICATIONS-2 its text goes nowhere" "" "$(grep -rl 'build the export page' "$run" "$HO_FAKE_GH_DIR" 2>/dev/null || true)"

# H-120 S8-28a: run events, each switchable.
b=$(nsent tg)
HO_RUN_DIR=$run "$h" tickets done "$t1" >/dev/null
assert_eq "H-120 ticket done is announced" "$((b + 1))" "$(nsent tg)"
assert_eq "H-120 the event names the ticket" "done $t1" "$(sent tg | tail -n 1 | jq -r '"\(.event) \(.ticket)"')"
userconf "$(jq -c '. + {events: {taken: false}}' <<<"$three")"
b=$(nsent tg)
t9=$(ticket "Taken off"); label alice "$t9" ready; tick >/dev/null
assert_eq "H-120 a switched-off event is not announced" "$b" "$(nsent tg)"
userconf "$three"
t10=$(ticket "Taken on"); label alice "$t10" ready; tick >/dev/null
assert_eq "H-120 ticket taken into work is announced" "taken $t10" "$(sent tg | tail -n 1 | jq -r '"\(.event) \(.ticket)"')"
"$h" notify "$run" event orchestrator-down - "the orchestrator is down" >/dev/null
assert_eq "S8-28a the orchestrator-down event reaches every active channel" "orchestrator-down orchestrator-down orchestrator-down" \
  "$(for c in tg sl gm; do sent "$c" | tail -n 1 | jq -r .event; done | tr '\n' ' ' | sed 's/ $//')"
assert_exit "S8-28a an unknown event is refused" 64 "$h" notify "$run" event coffee - "x"
(cd "$proj" && "$h" state "$run" stop --type soft:step "owner asked" >/dev/null 2>&1) || true
assert_eq "S8-28a a stop is announced as run ended or stopped" "run-ended" "$(sent tg | tail -n 1 | jq -r .event)"

# H-120 D37-NOTIFICATIONS-6: the intake tick polls the channels and returns with the answers.
run2=$(cd "$proj" && "$h" run new)
run_save=$run; run=$run2
t11=$(asked "Tick polls")
reply sl m8 "$(sent sl | jq -r --arg t "$t11" 'select(.kind == "question" and .ticket == $t) | .ref')" U-ALICE "The report page."
out=$(tick)
assert_contains "H-120 the tick reads the channel reply" "$out" "answer $t11 sl"
assert_contains "H-120 the session returns to the run with the answered ticket" "$out" "resume $t11"

# D36: the mcp route: the engine queues, the session sends and reports; a failure falls back.
userconf '{"channels": {"bot": {"preset": "telegram", "via": "mcp", "mcp": "tg-bot"}, "sl": {"preset": "slack", "via": "command", "argv": ["fake-channel", "sl"]}}, "questions": ["bot"]}'
t12=$(asked "Mcp route")
q=$(jq -c --arg t "$t12" 'select(.kind == "question" and .ticket == $t)' "$run/notify/outbox.jsonl")
assert_eq "D36 the mcp question is queued for the session with its connector" "tg-bot" "$(jq -r .mcp <<<"$q")"
assert_eq "H-116 the queued text has the tracker's lines" "$(qlines "$(comments "$t12" | jq -r '.[] | select(contains("harness:v1"))' | tail -n 20)")" "$(qlines "$(jq -r .text <<<"$q")")"
b_sl=$(nq sl)
"$h" notify "$run" failed "$(jq -r .id <<<"$q")" >/dev/null
assert_eq "H-121 a reported mcp failure falls back to the next channel" "$((b_sl + 1))" "$(nq sl)"
t13=$(asked "Mcp reply")
q=$(jq -c --arg t "$t13" 'select(.kind == "question" and .ticket == $t)' "$run/notify/outbox.jsonl")
"$h" notify "$run" sent "$(jq -r .id <<<"$q")" tgmsg-77 >/dev/null
jq -cn '{id: "u1", reply_to: "tgmsg-77", sender: "111", text: "The report page."}' > "$base/in.jsonl"
"$h" notify "$run" inbox bot "$base/in.jsonl" >/dev/null
out=$("$h" notify "$run" poll)
assert_contains "D36 a reply the session read through the connector is recorded" "$out" "answer $t13 bot"
run=$run_save
userconf "$three"

# H-123 D36: the connections check is read-only and lists owner actions for a missing one.
touch "$HO_FAKE_CHANNEL_DIR/tg/down"
rc=0; out=$(cd "$proj" && "$h" notify check) || rc=$?
assert_eq "H-123 a missing connection fails the check" "69" "$rc"
assert_contains "H-123 the missing connection is named" "$out" "channel tg: the connection check failed"
assert_contains "H-123 the owner gets the step only the owner can do" "$out" "owner action: Create the Telegram bot"
assert_contains "H-123 a working connection reads ok" "$out" "channel sl: ok"
rm -f "$HO_FAKE_CHANNEL_DIR/tg/down"

# D36: no token in any shipped file.
hits=$(grep -rIlE 'xox[abpr]-[A-Za-z0-9-]{10,}|[0-9]{8,10}:[A-Za-z0-9_-]{35}|ya29\.[A-Za-z0-9_-]{20,}|"(token|bot_token|api_key|secret)"[[:space:]]*:[[:space:]]*"[^"]+"' \
  "$HO_PLUGIN_ROOT" --exclude-dir=tests 2>/dev/null || true)
assert_eq "D36 no token in any shipped file" "" "$hits"
