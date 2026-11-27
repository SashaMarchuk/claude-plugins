# Intake by label with the write-access check (tasks.md 12.1; H-002, H-003, H-008, H-009,
# H-011; D2 order; D37-INTAKE-9). The fake gh records who set each label, as the events
# endpoint does, and answers the collaborator permission endpoint from perms.json.
. "$HO_TESTS_DIR/intake-setup.sh"

# H-003: a label set by a writer during a live run is picked up on the next poll.
t1=$(ticket "CSV export")
out=$(tick)
assert_eq "H-003 first poll: a ticket without the ready label is not taken" "" "$(printf '%s' "$out" | grep -E '^(start|needs-review)' || true)"
label alice "$t1" ready
out=$(tick)
assert_contains "H-003 next poll: the ticket a writer labelled ready is taken" "$out" "start $t1"
assert_eq "H-002 H-030 the taken ticket carries only in-progress" '["harness:in-progress"]' "$(labels "$t1")"

# H-002: a comment that looks like a run command does not trigger pickup.
t2=$(ticket "Comment trigger")
printf '/harness run\nharness:ready\n' > "$base/cmd.md"
as alice issue comment "$t2" --repo fake/repo --body-file "$base/cmd.md" >/dev/null
out=$(tick)
assert_eq "H-002 a run command in a comment does not pick the ticket up" "" "$(printf '%s' "$out" | grep -E " $t2\$" || true)"
assert_eq "H-002 the commented ticket keeps its state (no label)" '[]' "$(labels "$t2")"

# H-008 H-011: triage and read access are not enough; the ticket moves to needs-review.
judge_calls() { grep -c '^-p	' "$HO_FAKE_CLAUDE_LOG" 2>/dev/null || true; }
for who in tom rita; do
  t=$(ticket "Set by $who")
  label "$who" "$t" ready
  j0=$(judge_calls)
  out=$(tick)
  assert_eq "H-008 D2 the $who ticket text never reaches the readiness judge" "$j0" "$(judge_calls)"
  assert_contains "H-008 H-011 a label set by $who ($(jq -r --arg w "$who" '.[$w]' "$HO_FAKE_GH_DIR/perms.json")) moves the ticket to needs-review" "$out" "needs-review $t"
  assert_eq "H-011 H-030 the $who ticket carries only needs-review" '["harness:needs-review"]' "$(labels "$t")"
  assert_eq "H-011 the $who ticket is not claimed (no assignee)" "[]" "$(jq -c .assignees "$HO_FAKE_GH_DIR/issues/$t.json")"
done
# H-026 D5: the needs-review move posts one comment with the change, the reason and the next step.
c=$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t.json")
assert_contains "H-026 D5 the needs-review comment names the change" "$c" "ready -> needs-review"
assert_contains "H-026 D5 the needs-review comment gives the reason" "$c" "no confirmed write access"
assert_contains "H-026 D5 the needs-review comment says what a writer does next" "$c" "set the ready label again"

# H-009: an unknown user (the access query answers 404) counts as read-only.
t3=$(ticket "Unknown person")
label stranger "$t3" ready
j0=$(judge_calls)
out=$(tick)
assert_eq "H-009 D2 the unknown user's ticket never reaches the readiness judge" "$j0" "$(judge_calls)"
assert_contains "H-009 an unknown user's label moves the ticket to needs-review" "$out" "needs-review $t3"
# H-009: the code host does not answer the access query.
t4=$(ticket "Access query fails")
label alice "$t4" ready
out=$(HO_FAKE_GH_FAIL_API=/collaborators/ tick)
assert_contains "H-009 a failed access query counts as read-only" "$out" "needs-review $t4"
assert_eq "H-009 the failed-query ticket is not in progress" '["harness:needs-review"]' "$(labels "$t4")"

# H-011 second scenario: a writer reviews the ticket and sets ready again; the newest label decides.
label alice "$t3" ready
out=$(tick)
assert_contains "H-011 a writer's later ready label takes the reviewed ticket" "$out" "start $t3"
assert_eq "H-011 H-030 only in-progress remains after the writer's approval" '["harness:in-progress"]' "$(labels "$t3")"

# The newest ready event decides: a writer first, then a read-only person sets it again.
t5=$(ticket "Newest event")
label alice "$t5" ready
as alice issue edit "$t5" --repo fake/repo --remove-label harness:ready >/dev/null
label rita "$t5" ready
out=$(tick)
assert_contains "H-008 the newest ready label decides (read-only after a writer)" "$out" "needs-review $t5"

# H-008: maintain and admin are write access or higher.
for who in maya olga; do
  t=$(ticket "Set by $who")
  label "$who" "$t" ready
  out=$(tick)
  assert_contains "H-008 a label set by $who is taken" "$out" "start $t"
done

# H-008 interim rule (OPEN-INTAKE-1): a bot account with its own write access, no allow-list.
t6=$(ticket "Bot trigger")
label 'ci-bot[bot]' "$t6" ready
out=$(tick)
assert_contains "H-008 a bot with its own write access sets ready: taken" "$out" "start $t6"

# H-009: a login of an unexpected shape never reaches the API path and counts as read-only.
t7=$(ticket "Odd login")
label '../../x' "$t7" ready
out=$(tick)
assert_contains "H-009 a login of an unexpected shape counts as read-only" "$out" "needs-review $t7"
assert_eq "H-009 the odd login never reached an API path" "" "$(grep -F 'collaborators/../' "$HO_FAKE_GH_DIR/calls.log" || true)"

# D2 order: access check, then claim and comment, then the readiness check (from the call log).
t8=$(ticket "Order")
label alice "$t8" ready
: > "$HO_FAKE_GH_DIR/calls.log"; : > "$HO_FAKE_CLAUDE_LOG"
tick >/dev/null
perm_line=$(grep -n "collaborators/alice/permission" "$HO_FAKE_GH_DIR/calls.log" | head -1 | cut -d: -f1)
claim_line=$(grep -n "^issue	edit	$t8	.*harness:in-progress" "$HO_FAKE_GH_DIR/calls.log" | head -1 | cut -d: -f1)
comment_line=$(grep -n "^issue	comment	$t8	" "$HO_FAKE_GH_DIR/calls.log" | head -1 | cut -d: -f1)
if [ -n "$perm_line" ] && [ -n "$claim_line" ] && [ -n "$comment_line" ] && [ "$perm_line" -lt "$claim_line" ] && [ "$claim_line" -lt "$comment_line" ]; then
  ok "D2 order: the access check comes before the claim, the claim before its comment"
else
  bad "D2 order: the access check comes before the claim, the claim before its comment" "perm=$perm_line claim=$claim_line comment=$comment_line"
fi
c=$(jq -r '.comments[0].body' "$HO_FAKE_GH_DIR/issues/$t8.json")
assert_contains "D2 the pickup comment is posted at the claim" "$c" "picked up"
assert_eq "D2 the readiness judge ran once for the pickup" "1" "$(grep -c '^-p	' "$HO_FAKE_CLAUDE_LOG" || true)"
assert_eq "D2 the ledger records the pickup before the readiness verdict" "pickup readiness" "$(jq -r --arg t "$t8" 'select((.kind == "pickup" or .kind == "readiness") and .ticket == $t) | .kind' "$run/ledger.jsonl" | tr '\n' ' ' | sed 's/ $//')"

# H-008 D37-INTAKE-9: a configured target repository where the person has no write access.
jq '.tickets.target_repos = ["fake/repo", "fake/api"]' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
t9=$(ticket "Two repos" "" "## Outcome
Change the API in fake/api and the docs.

## Scope
fake/api

## Acceptance criteria
The API test passes.")
label alice "$t9" ready
out=$(HO_FAKE_GH_FAIL_API=repos/fake/api/ tick)
assert_contains "D37-INTAKE-9 no readable access on a named target repository: needs-review" "$out" "needs-review $t9"
c=$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t9.json")
assert_contains "D37-INTAKE-9 the one comment names the repository" "$c" "fake/api"
assert_eq "D37-INTAKE-9 exactly one comment on the refused ticket" "1" "$(ncomments "$t9")"
t9b=$(ticket "Repo name in other case" "" "## Outcome
Change Fake/API too.

## Scope
Fake/API

## Acceptance criteria
Test passes.")
label alice "$t9b" ready
out=$(HO_FAKE_GH_FAIL_API=repos/fake/api/ tick)
assert_contains "D37-INTAKE-9 a target repository named in another letter case is still checked" "$out" "needs-review $t9b"
t10=$(ticket "One repo" "" "## Outcome
Docs only in this repository.

## Scope
docs/

## Acceptance criteria
Docs build.")
label alice "$t10" ready
out=$(HO_FAKE_GH_FAIL_API=repos/fake/api/ tick)
assert_contains "D37-INTAKE-9 a ticket that names no other target repository is taken" "$out" "start $t10"

# The ledger records each intake verdict with the trigger author.
assert_contains "H-011 the ledger records the needs-review verdict" "$(ledger)" "\"ticket\":\"$t4\""

# A tracker step that fails after the claim is never silent: one result line and a ledger line.
t11=$(ticket "Comment fails")
label alice "$t11" ready
out=$(HO_FAKE_GH_FAIL="issue comment" tick 2>/dev/null || true)
assert_contains "D2 a failed pickup comment prints an error line for the ticket" "$out" "error $t11"
assert_contains "D2 a failed pickup comment is recorded in the ledger" "$(jq -c --arg t "$t11" 'select(.kind == "pickup-error" and .ticket == $t)' "$run/ledger.jsonl")" '"step":"pickup-comment"'

# D2 H-030: a ready label on a ticket that is already in progress or done is no new pickup. The
# harness keeps the state it has, removes the stray ready label (one state label at a time) and
# records it once; it claims nothing and runs no readiness check.
for st in in-progress done; do
  t=$(ticket "Stray ready on $st" "$st")
  label alice "$t" ready
  : > "$HO_FAKE_CLAUDE_LOG"
  out=$(tick)
  assert_contains "D2 a ready label on the $st ticket is not a pickup" "$out" "kept-$st $t"
  assert_eq "D2 H-030 the $st ticket keeps only its own state label" "[\"harness:$st\"]" "$(labels "$t")"
  assert_eq "D2 the $st ticket gets no picked-up comment" "" "$(comments "$t" | grep 'picked up' || true)"
  assert_eq "D2 no readiness check runs for the $st ticket" "" "$(cat "$HO_FAKE_CLAUDE_LOG")"
  assert_eq "D2 the stray ready label on the $st ticket is recorded once" "1" "$(jq -c --arg t "$t" 'select(.kind == "pickup-skipped" and .ticket == $t)' "$run/ledger.jsonl" | grep -c . || true)"
  out=$(tick)
  assert_eq "D2 the next tick says nothing more about the $st ticket" "" "$(printf '%s' "$out" | grep -w "$t" || true)"
done
# H-011 a writer's ready label on a needs-review ticket is the approval and stays a pickup.
t=$(ticket "Approved after review" needs-review)
label alice "$t" ready
out=$(tick)
assert_contains "H-011 a writer's ready label on a needs-review ticket is taken" "$out" "start $t"
