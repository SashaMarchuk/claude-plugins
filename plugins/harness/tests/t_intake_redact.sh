# H-018 (#110): an e-mail address in the readiness judge's output never reaches the ticket. The
# runtime adds the signed-in account's address to the judge's context, and an injected ticket
# could ask the judge to repeat it in a question. Each address is replaced by a fixed mark; the
# question itself stays, so a question is never lost (a lost question could read as "ready").
. "$HO_TESTS_DIR/intake-setup.sh"
at='@'
addr="owner.name${at}mail.example.invalid"
t1=$(ticket "Address in a question")
label alice "$t1" ready
v=$(jq -cn --arg a "$addr" '{ready: true, questions: ["Should the report go to \($a) or to the team?"]}')
out=$(HO_FAKE_CLAUDE_STDOUT="$v" tick)
q=$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t1.json")
assert_eq "H-018 (#110): no e-mail address reaches the ticket" "" "$(printf '%s\n' "$q" | grep -F "$at" || true)"
assert_contains "H-018 (#110): the question is still posted, with the address replaced" "$q" "1. Should the report go to [address removed] or to the team?"
assert_eq "H-012 (#110): the question keeps the ticket not ready (blocked)" '["harness:blocked"]' "$(labels "$t1")"
