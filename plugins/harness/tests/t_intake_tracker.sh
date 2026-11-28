# Trackers without labels (T21, T22; H-007, H-010; D1, D2, D37-INTAKE-8, D37-NOTIFICATIONS-3).
# The fake tracker has statuses and no labels. People are matched to code host accounts by
# e-mail through the identity map in the user config; access comes from the code host.
. "$HO_TESTS_DIR/intake-setup.sh"
export HO_TICKETS_SOURCE=adapter HO_TICKETS_ADAPTER="$HO_TESTS_DIR/fake-bin/fake-tracker"
export HO_FAKE_TRACKER_DIR="$base/tracker"
unset HO_TICKETS_REPO
run=$(cd "$proj" && "$h" run new --workers 5)
setcfg() { jq "$1" "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"; }
setcfg '.tickets.target_repos = ["fake/repo"] | .tickets.status_map = {"ready": "Ready for AI", "in-progress": "Doing", "blocked": "Waiting", "needs-review": "Review", "done": "Closed"}'
# The identity map lives in the user config only (D37-INTAKE-8, D37-NOTIFICATIONS-3).
jq '.identities = [{"account": "alice", "emails": ["Alice@Example.invalid"]},
  {"account": "rita", "emails": ["rita@example.invalid"]},
  {"account": "maya", "emails": ["shared@example.invalid"]}, {"account": "olga", "emails": ["shared@example.invalid"]}]' \
  "$user/config.json" > "$base/u.json" && mv "$base/u.json" "$user/config.json"
tr() { "$HO_TICKETS_ADAPTER" "$@"; }
status() { jq -r .status "$HO_FAKE_TRACKER_DIR/$1.json"; }
printf 'Make the report export CSV. Done when the export test passes.\n' > "$base/b.md"

# H-007 D1: the tracker has no labels; the mapped ready status triggers pickup.
t1=$(tr new "Status ticket" "$base/b.md" Backlog alice@example.invalid)
out=$(tick)
assert_eq "H-007 a ticket outside the ready status is not taken" "" "$(printf '%s' "$out" | grep -w "$t1" || true)"
tr person-status "$t1" "Ready for AI" alice@example.invalid
out=$(tick)
assert_contains "H-007 D1 the mapped ready status set by a writer triggers pickup" "$out" "start $t1"
assert_eq "D2 the claim sets the mapped in-progress status" "Doing" "$(status "$t1")"
assert_contains "D2 the pickup comment is posted on the tracker" "$(jq -r '.comments[0].body' "$HO_FAKE_TRACKER_DIR/$t1.json")" "picked up"
assert_contains "H-012 the readiness judge reads the tracker ticket inside the fence" "$(cat "$HO_FAKE_CLAUDE_LOG")" "Make the report export CSV."

# H-010 D37-INTAKE-8: e-mails match without regard to letter case; the account's access decides.
assert_contains "H-010 the ledger names the mapped account" "$(jq -c --arg t "$t1" 'select(.kind == "pickup" and .ticket == $t)' "$run/ledger.jsonl")" '"by":"alice"'
t2=$(tr new "Reader ticket" "$base/b.md" Backlog)
tr person-status "$t2" "Ready for AI" rita@example.invalid
out=$(tick)
assert_contains "H-010 H-008 a mapped account without write access: needs-review" "$out" "needs-review $t2"
assert_eq "H-011 the ticket moves to the mapped needs-review status" "Review" "$(status "$t2")"

# H-007 H-010: an unknown author (no e-mail, no entry, or more than one entry) goes to needs-review.
for who in - stranger@example.invalid shared@example.invalid; do
  t=$(tr new "Unknown $who" "$base/b.md" Backlog)
  tr person-status "$t" "Ready for AI" "$who"
  : > "$HO_FAKE_CLAUDE_LOG"
  out=$(tick)
  assert_contains "H-007 H-010 a trigger by '$who' moves the ticket to needs-review" "$out" "needs-review $t"
  assert_eq "H-007 the '$who' ticket is not taken into work" "Review" "$(status "$t")"
  assert_eq "H-007 the '$who' ticket text never reaches the judge" "" "$(cat "$HO_FAKE_CLAUDE_LOG")"
done

# D37-INTAKE-8: the identity map is never read from the project config.
jq '.identities = [{"account": "alice", "emails": ["proj@example.invalid"]}]' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
t3=$(tr new "Project map" "$base/b.md" Backlog)
tr person-status "$t3" "Ready for AI" proj@example.invalid
out=$(tick)
assert_contains "D37-INTAKE-8 an identity in the project config is no match" "$out" "needs-review $t3"

# H-007 D1 last resort: a tracker with no ready status; a harness:ready line in the text triggers,
# and its author must be known.
setcfg 'del(.tickets.status_map.ready)'
printf 'Make the report export CSV.\nharness:ready\n' > "$base/r.md"
t4=$(tr new "Text trigger" "$base/r.md" Backlog alice@example.invalid)
t5=$(tr new "Text no author" "$base/r.md" Backlog)
t6=$(tr new "No trigger line" "$base/b.md" Backlog alice@example.invalid)
out=$(tick)
assert_contains "H-007 D1 with no ready status a harness:ready line by a writer triggers pickup" "$out" "start $t4"
assert_contains "H-007 a text trigger with an unknown author goes to needs-review" "$out" "needs-review $t5"
assert_eq "H-007 a ticket without the line is not taken" "" "$(printf '%s' "$out" | grep -w "$t6" || true)"
# With a ready status the text line is not a trigger (label or status first).
setcfg '.tickets.status_map.ready = "Ready for AI"'
t7=$(tr new "Line but status map" "$base/r.md" Backlog alice@example.invalid)
out=$(tick)
assert_eq "H-007 D1 the text line is only the last resort" "" "$(printf '%s' "$out" | grep -w "$t7" || true)"

# A status map that misses a state other than ready, or names one status twice, is refused.
setcfg 'del(.tickets.status_map.done)'
assert_exit "D1 a status map without the done status is refused (exit 78)" 78 tick
setcfg '.tickets.status_map.done = "Doing"'
assert_exit "D1 a status map that names one status twice is refused (exit 78)" 78 tick
