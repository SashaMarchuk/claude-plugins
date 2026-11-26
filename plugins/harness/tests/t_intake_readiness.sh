# Readiness check at every pickup (H-012, H-013; D6 default content, D8 no fixed structure).
# The judge is the main runtime run without a terminal and read-only, from its runtime profile;
# the fake claude prints the verdict set in HO_FAKE_CLAUDE_STDOUT.
. "$HO_TESTS_DIR/intake-setup.sh"
judge_calls() { grep -c '^-p	' "$HO_FAKE_CLAUDE_LOG" 2>/dev/null || true; }
verdicts() { jq -c --arg t "$1" 'select(.kind == "readiness" and .ticket == $t) | .verdict' "$run/ledger.jsonl" | tr '\n' ' '; }

# H-012 a clear free-form ticket with no headings passes and goes to work (D8).
t1=$(ticket "Free form" "" "Please make the report page export CSV. Done when the export test passes and one CSV file lands in out/.")
label alice "$t1" ready
out=$(tick)
assert_contains "H-012 D8 a clear free-form ticket without headings goes to work" "$out" "start $t1"
assert_eq "H-012 the verdict is recorded in the ledger" '"ready" ' "$(verdicts "$t1")"
args=$(grep '^-p	' "$HO_FAKE_CLAUDE_LOG" | tail -1)
assert_contains "H-012 the judge runs read-only (sandbox flags from the runtime profile)" "$args" "--permission-mode	plan"
prompt=$(cat "$HO_FAKE_CLAUDE_LOG")
assert_contains "H-018 the ticket text reaches the judge inside the untrusted fence" "$prompt" "BEGIN TICKET DATA [id $t1]"
assert_contains "H-013 D6 no content set: the judge gets the default list" "$prompt" "- outcome"
assert_contains "H-013 D6 the default list holds the done-check" "$prompt" "- done-check"

# H-012 a hand-set label on a thin ticket: the check runs, and the ticket does not go to work.
t2=$(ticket "Thin" "" "fix it")
label alice "$t2" ready
n0=$(judge_calls)
out=$(HO_FAKE_CLAUDE_STDOUT='{"ready": false, "questions": ["Which page should change?", "How do we tell it is done?"]}' tick)
assert_eq "H-012 the readiness check ran at the pickup of a hand-labelled ticket" "$((n0 + 1))" "$(judge_calls)"
assert_contains "H-012 a thin ticket does not go to work" "$out" "blocked $t2"
assert_eq "H-012 the not-ready verdict is recorded in the ledger" '"not-ready" ' "$(verdicts "$t2")"
assert_eq "H-012 H-030 the thin ticket carries only blocked" '["harness:blocked"]' "$(labels "$t2")"
q=$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t2.json")
assert_contains "H-012 H-032 the open questions are on the ticket, numbered (1)" "$q" "1. Which page should change?"
assert_contains "H-012 H-032 the open questions are on the ticket, numbered (2)" "$q" "2. How do we tell it is done?"

# H-012 every pickup, again after a writer relabels it: a second check and a second verdict.
label alice "$t2" ready
out=$(tick)
assert_contains "H-012 the relabelled ticket is checked again and goes to work" "$out" "start $t2"
assert_eq "H-012 each pickup records its own verdict" '"not-ready" "ready" ' "$(verdicts "$t2")"

# An unreadable or failed verdict is unknown, never ready: the ticket does not start.
t3=$(ticket "Judge fails")
label alice "$t3" ready
out=$(HO_FAKE_CLAUDE_STDOUT='I think it is fine' tick)
assert_eq "H-012 an unparsable verdict does not start the ticket" "" "$(printf '%s' "$out" | grep "start $t3" || true)"
assert_eq "H-012 the unparsable verdict is recorded as unknown" '"unknown" ' "$(verdicts "$t3")"
assert_eq "H-012 the unknown ticket moves to needs-review" '["harness:needs-review"]' "$(labels "$t3")"
t4=$(ticket "Judge exits 1")
label alice "$t4" ready
out=$(HO_FAKE_CLAUDE_EXIT=1 tick)
assert_eq "H-012 a judge that exits non-zero does not start the ticket" "" "$(printf '%s' "$out" | grep "start $t4" || true)"
assert_eq "H-012 the failed judge is recorded as unknown" '"unknown" ' "$(verdicts "$t4")"
t5=$(ticket "Ready with questions")
label alice "$t5" ready
out=$(HO_FAKE_CLAUDE_STDOUT='{"ready": true, "questions": ["Which colour?"]}' tick)
assert_eq "H-012 ready with an open human question is not ready" "" "$(printf '%s' "$out" | grep "start $t5" || true)"
t6=$(ticket "Ready as text")
label alice "$t6" ready
out=$(HO_FAKE_CLAUDE_STDOUT='{"ready": "true", "questions": []}' tick)
assert_eq "H-012 ready given as text is not a verdict" "" "$(printf '%s' "$out" | grep "start $t6" || true)"

# H-013 a project lists its own required content: the judge uses that list.
jq '.tickets.required_content = ["outcome", "a rollback plan"]' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
: > "$HO_FAKE_CLAUDE_LOG"
t7=$(ticket "Own content")
label alice "$t7" ready
tick >/dev/null
prompt=$(cat "$HO_FAKE_CLAUDE_LOG")
assert_contains "H-013 the project's own required content reaches the judge" "$prompt" "- a rollback plan"
assert_eq "H-013 the default list is replaced, not extended" "" "$(printf '%s\n' "$prompt" | grep -x -- '- done-check' || true)"
jq '.tickets.required_content = "outcome"' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
t8=$(ticket "Bad content setting")
label alice "$t8" ready
assert_exit "H-013 required content that is not a list of text is refused (exit 78)" 78 "$h" intake "$run" tick

# The judge runs past tickets.readiness_timeout_seconds: it is stopped, and the verdict is unknown.
jq '.tickets.required_content = null | .tickets.readiness_timeout_seconds = 10' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
age_poll
"$h" intake "$run" tick >/dev/null 2>&1 || true
t9=$(ticket "Slow judge")
label alice "$t9" ready
start=$(date +%s)
out=$(HO_FAKE_CLAUDE_HOLD=ignore HO_FAKE_CLAUDE_HOLD_MAX=120 tick 2>/dev/null)
el=$(( $(date +%s) - start ))
assert_eq "H-012 a judge past the time limit is stopped within the limit plus a margin" "yes" "$([ "$el" -le 25 ] && echo yes || echo "no (${el}s)")"
assert_eq "H-012 a timed-out judge gives the verdict unknown" '"unknown" ' "$(verdicts "$t9")"
assert_eq "H-012 a timed-out judge does not start the ticket" "" "$(printf '%s' "$out" | grep "start $t9" || true)"
jq '.tickets.readiness_timeout_seconds = 5' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
assert_exit "H-012 a judge time limit below 10 seconds is refused" 78 "$h" intake "$run" tick
