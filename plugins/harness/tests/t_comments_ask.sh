# Questions to a human go to the ticket as numbered items, and the session closes (H-032,
# D2, S8-11). A worker cannot close its own session: "tickets ask" records the question in the
# run ledger, and the next poll closes the asking session from outside (graceful close) while
# other tickets go on.
. "$HO_TESTS_DIR/sessions-setup.sh"
export HO_FAKE_GH_DIR="$base/gh" HO_TICKETS_SOURCE=github HO_TICKETS_REPO=fake/repo
mkdir -p "$HO_FAKE_GH_DIR"
printf '{"harness-bot": "write", "alice": "write"}\n' > "$HO_FAKE_GH_DIR/perms.json"
printf '## Outcome\nx\n\n## Scope\ny\n\n## Acceptance criteria\nz\n' > "$base/body.md"
new_ticket() { "$h" tickets add "$1" "$base/body.md" "$2" | sed -n 's/^OK created ticket \([0-9]*\).*/\1/p'; }
labels() { jq -c '[.labels[]] | sort' "$HO_FAKE_GH_DIR/issues/$1.json"; }
# The readiness judge must not be held open like a session.
tick() { [ ! -f "$run/intake/poll.json" ] || touch -t 200001010000 "$run/intake/poll.json"; HO_FAKE_CLAUDE_HOLD= HO_FAKE_CLAUDE_STDOUT='{"ready": true, "questions": []}' "$h" intake "$run" tick "$@"; }

t1=$(new_ticket "Needs answers" in-progress)
launch w1 >/dev/null
p1=$(rec w1 .pid)
printf 'Which database should the export read?\n2. Should old reports be included?\n\n' > "$base/q.md"
# The worker asks from inside its session (the launcher exports these).
out=$(HO_RUN_DIR="$run" HO_RUN_ID="$(basename "$run")" HO_SESSION_NAME=w1 HO_SESSION_ROLE=worker "$h" tickets ask "$t1" "$base/q.md")
assert_contains "H-032 the worker is told to end its session" "$out" "end this session"
assert_eq "H-032 one new comment holds the questions" "1" "$(jq '.comments | length' "$HO_FAKE_GH_DIR/issues/$t1.json")"
c=$(jq -r '.comments[0].body' "$HO_FAKE_GH_DIR/issues/$t1.json")
assert_eq "H-032 the comment's first line names the role and the question" "**worker: question**" "$(printf '%s\n' "$c" | head -n 1)"
assert_contains "H-032 question 1 is numbered" "$c" "1. Which database should the export read?"
assert_contains "H-032 question 2 is numbered once (its own number is not doubled)" "$c" "2. Should old reports be included?"
assert_eq "H-032 no third item from the blank line" "" "$(printf '%s\n' "$c" | grep -E '^3\. ' || true)"
assert_contains "H-032 the comment says who may answer" "$c" "write access"
assert_eq "H-032 the ticket is marked as waiting (blocked only)" '["harness:blocked"]' "$(labels "$t1")"
assert_contains "H-032 the ledger records the question for the session" "$(cat "$run/ledger.jsonl")" '"kind":"question"'
assert_eq "H-032 the session is still running until the poll closes it" "yes" "$(alive "$p1" && echo yes || echo no)"

# Other tickets continue: the next poll closes the asking session and takes the next ticket.
t2=$(new_ticket "Other work" blocked)
HO_FAKE_GH_USER=alice gh issue edit "$t2" --repo fake/repo --add-label harness:ready >/dev/null
out=$(tick)
assert_contains "H-032 the poll closes the asking session" "$out" "closed w1"
assert_eq "H-032 the asking session's process has ended" "yes" "$(wait_gone "$p1" && echo yes || echo no)"
assert_eq "H-032 the asking session's record is closed" "closed" "$(rec w1 .status)"
assert_contains "H-032 other ready tickets continue" "$out" "start $t2"
out=$(tick)
assert_eq "H-032 a closed asking session is closed only once" "" "$(printf '%s' "$out" | grep 'closed w1' || true)"
# D14: after the answer a new launch under the same name (its old record removed) is not closed
# by the old question.
rm -f "$run/sessions/w1.json"
launch w1 >/dev/null
p1b=$(rec w1 .pid)
out=$(tick)
assert_eq "H-032 D14 a relaunched session of the same name is not closed by the old question" "" "$(printf '%s' "$out" | grep 'closed w1' || true)"
assert_eq "H-032 D14 the relaunched session keeps running" "yes" "$(alive "$p1b" && echo yes || echo no)"

# An empty question file is refused; nothing is posted and the state does not change.
t3=$(new_ticket "Empty" in-progress)
printf '\n\n' > "$base/empty.md"
assert_exit "H-032 a question file with no question is refused" 64 "$h" tickets ask "$t3" "$base/empty.md"
assert_eq "H-032 the refused ask posts nothing" "0" "$(jq '.comments | length' "$HO_FAKE_GH_DIR/issues/$t3.json")"
assert_eq "H-032 the refused ask keeps the state" '["harness:in-progress"]' "$(labels "$t3")"

# H-032 a session that asked a question and cannot be closed is reported once: one result line
# and one owner-action ledger line. Later ticks keep trying the close without a new report.
jq -cn --arg r "$(basename "$run")" '{run: $r, status: "running", session_id: "not-a-uuid"}' > "$run/sessions/w9.json"
jq -cn --arg r "$(basename "$run")" '{ts: "2026-01-01T00:00:00Z", run: $r, kind: "question", session: "w9", ticket: "1"}' >> "$run/ledger.jsonl"
out=$(tick 2>/dev/null)
assert_contains "H-032 a session that cannot be closed is reported" "$out" "close-failed w9"
assert_eq "H-032 the failed close gets one owner-action line" "1" "$(jq -c 'select(.kind == "owner-action")' "$run/ledger.jsonl" | grep -c 'w9' || true)"
out=$(tick 2>/dev/null)
assert_eq "H-032 the next tick does not report the failed close again" "" "$(printf '%s' "$out" | grep 'w9' || true)"
assert_eq "H-032 still one owner-action line after the next tick" "1" "$(jq -c 'select(.kind == "owner-action")' "$run/ledger.jsonl" | grep -c 'w9' || true)"
# Once the close works, the session is closed and recorded as such.
jq '.status = "closed"' "$run/sessions/w9.json" > "$base/w9.json" && mv "$base/w9.json" "$run/sessions/w9.json"
out=$(tick 2>/dev/null)
assert_contains "H-032 a later close that works is recorded" "$out" "closed w9"
