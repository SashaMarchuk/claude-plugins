# The clarification round limit (issue #128; H-117, D37-NOTIFICATIONS-4). One round is one
# follow-up question and the reply to it; the first question is no follow-up, and a question
# with no reply uses no round. When the reply to the last follow-up is still not enough, the
# harness asks no more: one tracker comment lists what is still missing, the blocked event goes
# to the channels, and the ticket stays blocked until a person returns it to work.
# Fake channels and the fake gh only.
. "$HO_TESTS_DIR/intake-setup.sh"
export HO_FAKE_CHANNEL_DIR="$base/channels"
mkdir -p "$HO_FAKE_CHANNEL_DIR"
jq -n '{schemaVersion: 2, notify: {channels: {tg: {preset: "telegram", via: "command", argv: ["fake-channel", "tg"]}}}}' > "$user/config.json"
cp "$proj/.harness/config.json" "$base/proj-config.json"
rounds() { # <n|unset>: clarify.max_rounds in the project config
  if [ "$1" = unset ]; then cp "$base/proj-config.json" "$proj/.harness/config.json"
  else jq --argjson n "$1" '.clarify.max_rounds = $n' "$base/proj-config.json" > "$proj/.harness/config.json"; fi
  select_config "$proj"
}
printf 'Which page should change?\nHow do we tell it is done?\n' > "$base/q.md"
printf 'How do we tell it is done?\n' > "$base/missing.md"
# ask <ticket> [file]: a worker session asks (the follow-up path every caller shares).
ask() { HO_RUN_DIR=$run HO_SESSION_ROLE=worker HO_SESSION_NAME=w1 "$h" tickets ask "$1" "${2:-$base/q.md}"; }
# answered <ticket>: a writer replies on the tracker and the tick resumes the ticket.
printf 'Only part of it: the report page.\n' > "$base/part.md"
answered() { as alice issue comment "$1" --repo fake/repo --body-file "$base/part.md" >/dev/null; tick >/dev/null; }
start() { local t; t=$(ticket "$1"); label alice "$t" ready; tick >/dev/null; printf '%s\n' "$t"; }
# Own question comments on the ticket, split into real questions and the used-up record.
nquestions() { comments "$1" | jq '[.[] | select(contains("\"event\":\"question\"") and (contains("rounds-used-up") | not))] | length'; }
nused() { comments "$1" | jq '[.[] | select(contains("rounds-used-up"))] | length'; }
tgq() { jq -r --arg t "$1" 'select(.kind == "question" and .ticket == $t) | .ref' "$HO_FAKE_CHANNEL_DIR/tg/sent.jsonl" 2>/dev/null | grep -c . || true; }
tgblocked() { jq -r --arg t "$1" 'select(.event == "blocked" and .ticket == $t) | .ref' "$HO_FAKE_CHANNEL_DIR/tg/sent.jsonl" 2>/dev/null | grep -c . || true; }
state_of() { jq -r '[.labels[] | select(startswith("harness:"))] | join(" ")' "$HO_FAKE_GH_DIR/issues/$1.json"; }

# ---- the spec scenario: limit 3 (the default when unset) ----
rounds unset
t=$(start "Three rounds")
ask "$t" >/dev/null
for i in 1 2 3; do
  answered "$t"
  out=$(ask "$t")
  assert_contains "H-117: follow-up $i of 3 is asked" "$out" "OK asked $t"
done
assert_eq "H-117: the first question and three follow-ups reach the tracker" 4 "$(nquestions "$t")"
assert_eq "H-117: each one is mirrored to the channel" 4 "$(tgq "$t")"
answered "$t"
b=$(ncomments "$t")
rc=0; out=$(ask "$t" "$base/missing.md") || rc=$?
assert_eq "D37-NOTIFICATIONS-4: the verb still succeeds, so the session ends (exit 0)" 0 "$rc"
assert_contains "D37-NOTIFICATIONS-4: the session is told the rounds are used up" "$out" "rounds are used up"
assert_eq "H-117: after the third follow-up no further question is asked" 4 "$(nquestions "$t")"
assert_eq "H-117: one tracker comment lists what is still missing" "$((b + 1)) 1" "$(ncomments "$t") $(nused "$t")"
last=$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t.json")
assert_contains "H-117: the comment lists the missing point" "$last" "1. How do we tell it is done?"
assert_contains "D37-NOTIFICATIONS-4: the comment names the setting" "$last" "clarify.max_rounds"
assert_eq "H-117: the ticket stays blocked" "harness:blocked" "$(state_of "$t")"
assert_eq "D37-NOTIFICATIONS-4: no question goes to the channel" 4 "$(tgq "$t")"
assert_eq "D37-NOTIFICATIONS-4: the blocked event goes to the channel" 1 "$(tgblocked "$t")"
assert_contains "D37-NOTIFICATIONS-4: the poll still closes the asking session (ledger question line)" "$(ledger | tail -n 3)" "\"kind\":\"question\",\"ticket\":\"$t\""

# Asked again with no person action: nothing more is posted or sent.
b=$(ncomments "$t"); bq=$(wc -l < "$HO_FAKE_CHANNEL_DIR/tg/sent.jsonl")
rc=0; out=$(ask "$t" "$base/missing.md") || rc=$?
assert_eq "D37-NOTIFICATIONS-4: a second ask after the used-up comment posts nothing" "0 $b" "$rc $(ncomments "$t")"
assert_eq "D37-NOTIFICATIONS-4: and sends nothing" "$bq" "$(wc -l < "$HO_FAKE_CHANNEL_DIR/tg/sent.jsonl")"
assert_contains "D37-NOTIFICATIONS-4: the session is told nothing was posted" "$out" "nothing was posted"

# A writer returns the ticket in the usual way (a tracker reply); a new clarification may begin.
answered "$t"
assert_eq "D37-NOTIFICATIONS-4: a writer's reply returns the ticket to work" "harness:in-progress" "$(state_of "$t")"
out=$(ask "$t")
assert_contains "D37-NOTIFICATIONS-4: after a person returned it, a question may be asked again" "$out" "OK asked $t"
assert_eq "D37-NOTIFICATIONS-4: that question is mirrored" 5 "$(tgq "$t")"

# ---- silence uses no round ----
rounds 1
t=$(start "Silence")
ask "$t" >/dev/null
answered "$t"
ask "$t" >/dev/null
# No reply: a person unblocks from the terminal; the unanswered follow-up used no round.
"$h" tickets unblock "$t" >/dev/null
tick >/dev/null
out=$(ask "$t")
assert_contains "D37-NOTIFICATIONS-4: a follow-up with no reply uses no round" "$out" "OK asked $t"
answered "$t"
out=$(ask "$t" "$base/missing.md")
assert_contains "D37-NOTIFICATIONS-4: limit 1: the reply to the one counted follow-up ends the rounds" "$out" "rounds are used up"

# ---- 0 means no limit ----
rounds 0
t=$(start "No limit")
ask "$t" >/dev/null
for i in 1 2 3 4 5; do answered "$t"; ask "$t" >/dev/null; done
assert_eq "D37-NOTIFICATIONS-4: with 0 every follow-up is asked" "6 0" "$(nquestions "$t") $(nused "$t")"

# ---- the local backend counts recorded answers ----
rounds 1
export HO_TICKETS_SOURCE=local
unset HO_TICKETS_REPO
lt=$(ticket "Local rounds" ready)
ask "$lt" >/dev/null
printf 'The report page.\n' > "$base/a.md"
"$h" tickets answer "$lt" alice "$base/a.md" >/dev/null
out=$(ask "$lt")
assert_contains "H-117: local: the first follow-up is asked" "$out" "OK asked $lt"
"$h" tickets answer "$lt" alice "$base/a.md" >/dev/null
out=$(ask "$lt" "$base/missing.md")
assert_contains "H-117: local: the reply to the last follow-up ends the rounds" "$out" "rounds are used up"
assert_contains "H-117: local: the comment lists what is still missing" "$("$h" tickets show "$lt")" "How do we tell it is done?"
b=$("$h" tickets show "$lt" | wc -l)
out=$(ask "$lt" "$base/missing.md")
assert_contains "D37-NOTIFICATIONS-4: local: a second ask after the used-up comment posts nothing" "$out" "nothing was posted"
assert_eq "D37-NOTIFICATIONS-4: local: the ticket text is unchanged" "$b" "$("$h" tickets show "$lt" | wc -l)"

# ---- the adapter backend (a tracker without labels) counts a person's comments ----
export HO_TICKETS_SOURCE=adapter HO_TICKETS_ADAPTER="$HO_TESTS_DIR/fake-bin/fake-tracker" HO_FAKE_TRACKER_DIR="$base/tracker"
jq '.clarify.max_rounds = 1 | .tickets.target_repos = ["fake/repo"]
  | .tickets.status_map = {"ready": "Ready for AI", "in-progress": "Doing", "blocked": "Waiting", "needs-review": "Review", "done": "Closed"}' \
  "$base/proj-config.json" > "$proj/.harness/config.json"
select_config "$proj"
at=$("$HO_TICKETS_ADAPTER" new "Adapter rounds" "$base/q.md" Doing alice@example.invalid)
reply_ad() { "$HO_TICKETS_ADAPTER" person-comment "$at" "$base/part.md" alice@example.invalid; }
rc=0; out=$(ask "$at") || rc=$?
assert_eq "H-117: adapter: a question is asked (exit 0)" 0 "$rc"
reply_ad
out=$(ask "$at")
assert_contains "H-117: adapter: the first follow-up is asked" "$out" "OK asked $at"
reply_ad
out=$(ask "$at" "$base/missing.md")
assert_contains "H-117: adapter: the reply to the last follow-up ends the rounds" "$out" "rounds are used up"
assert_eq "H-117: adapter: the ticket is in the blocked status" Waiting "$(jq -r .status "$HO_FAKE_TRACKER_DIR/$at.json")"
