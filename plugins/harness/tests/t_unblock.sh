# Unblock command and label cleanup, with careful dedicated tests (H-031, H-030; build-time
# rule R10.3; tasks.md 13.2). OPEN-10 decided under D37: the command is "unblock". Its trigger
# is the ready label, set by a writer on a blocked ticket (the same label-only trigger as
# pickup, H-002), or the terminal verb "harness tickets unblock <id>", which checks the
# signed-in account.
. "$HO_TESTS_DIR/intake-setup.sh"
state_labels() { jq -c '[.labels[] | select(startswith("harness:"))] | sort' "$HO_FAKE_GH_DIR/issues/$1.json"; }

# H-031 a writer unblocks a blocked ticket by setting the ready label.
t1=$(ticket "Writer unblocks" blocked)
label alice "$t1" ready
out=$(HO_FAKE_CLAUDE_STDOUT='{"ready": false, "questions": ["Still unclear?"]}' tick)
assert_contains "H-031 a writer's ready label on a blocked ticket unblocks it" "$out" "unblocked $t1"
assert_eq "H-031 R10.3 after unblock no blocked label remains (judge sent it back to blocked: one label)" '["harness:blocked"]' "$(state_labels "$t1")"
t1b=$(ticket "Writer unblocks, ready" blocked)
label alice "$t1b" ready
out=$(tick)
assert_contains "H-031 the unblocked ticket is then picked up" "$out" "start $t1b"
assert_eq "H-031 R10.3 after unblock exactly one state label remains" '["harness:in-progress"]' "$(state_labels "$t1b")"
assert_contains "H-026 the unblock is recorded in a status comment" "$(comments "$t1b")" "blocked -> ready"

# H-031 a person without write access tries to unblock: the ticket stays blocked.
for who in rita tom; do
  t=$(ticket "Non-writer $who" blocked)
  label "$who" "$t" ready
  out=$(tick)
  assert_contains "H-031 $who cannot unblock: the ticket stays blocked" "$out" "kept-blocked $t"
  assert_eq "H-031 R10.3 the stray ready label is removed; only blocked remains ($who)" '["harness:blocked"]' "$(state_labels "$t")"
  assert_eq "H-031 the ticket $who tried to unblock is not claimed" "[]" "$(jq -c .assignees "$HO_FAKE_GH_DIR/issues/$t.json")"
done
c=$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t.json")
assert_contains "H-031 the refusal says why" "$c" "no confirmed write access"
assert_contains "H-031 the refusal says who can unblock" "$c" "person with write access"

# H-031 access cannot be confirmed (the query fails): stays blocked.
t2=$(ticket "Query fails" blocked)
label alice "$t2" ready
out=$(HO_FAKE_GH_FAIL_API=/collaborators/ tick)
assert_contains "H-031 unconfirmed access: the ticket stays blocked" "$out" "kept-blocked $t2"
assert_eq "H-031 R10.3 unconfirmed access: only blocked remains" '["harness:blocked"]' "$(state_labels "$t2")"
# The events cannot be read: the setter is unknown, so it stays blocked.
t3=$(ticket "Events fail" blocked)
label alice "$t3" ready
out=$(HO_FAKE_GH_FAIL_API=/events tick)
assert_contains "H-031 the label setter cannot be read: the ticket stays blocked" "$out" "kept-blocked $t3"

# A stale ready label: set by a writer before the ticket was blocked does not unblock it.
t4=$(ticket "Stale" ready)
as alice issue edit "$t4" --repo fake/repo --add-label harness:blocked >/dev/null
assert_eq "R10.3 setup: the ticket carries ready and blocked" '["harness:blocked","harness:ready"]' "$(state_labels "$t4")"
out=$(tick)
assert_contains "H-031 a ready label older than the block does not unblock" "$out" "kept-blocked $t4"
assert_eq "R10.3 the stale ready label is removed" '["harness:blocked"]' "$(state_labels "$t4")"

# R10.3 stray state labels and a non-state label: after unblock exactly one state label, and
# the other label survives.
t5=$(ticket "Strays" blocked)
as alice issue edit "$t5" --repo fake/repo --add-label harness:needs-review --add-label area:docs >/dev/null
label alice "$t5" ready
out=$(tick)
assert_contains "R10.3 a blocked ticket with stray state labels is unblocked by a writer" "$out" "start $t5"
assert_eq "R10.3 exactly one state label remains" '["harness:in-progress"]' "$(state_labels "$t5")"
assert_contains "R10.3 a label that is not a state label survives" "$(labels "$t5")" "area:docs"

# ---- terminal verb: harness tickets unblock <id> checks the signed-in account -------------
t6=$(ticket "Terminal writer" blocked)
assert_exit "H-031 the terminal unblock by a writer succeeds" 0 env HO_FAKE_GH_USER=alice "$h" tickets unblock "$t6"
assert_eq "H-031 R10.3 terminal unblock: only ready remains" '["harness:ready"]' "$(state_labels "$t6")"
t7=$(ticket "Terminal reader" blocked)
assert_exit "H-031 the terminal unblock by a read-only account is refused (exit 65)" 65 env HO_FAKE_GH_USER=rita "$h" tickets unblock "$t7"
assert_eq "H-031 R10.3 refused terminal unblock: the ticket stays blocked" '["harness:blocked"]' "$(state_labels "$t7")"
assert_exit "H-031 the terminal unblock with unconfirmed access is refused" 65 env HO_FAKE_GH_USER=alice HO_FAKE_GH_FAIL_API=/collaborators/ "$h" tickets unblock "$t7"
assert_exit "H-031 the terminal unblock with an unreadable account is refused" 65 env HO_FAKE_GH_FAIL_API=user "$h" tickets unblock "$t7"
assert_eq "R10.3 after refused unblocks: still only blocked" '["harness:blocked"]' "$(state_labels "$t7")"
t8=$(ticket "Not blocked" needs-review)
assert_exit "H-031 unblock of a ticket that is not blocked is refused (exit 65)" 65 env HO_FAKE_GH_USER=alice "$h" tickets unblock "$t8"
assert_eq "R10.3 the refused not-blocked ticket keeps its state" '["harness:needs-review"]' "$(state_labels "$t8")"
assert_exit "H-031 unblock of a missing ticket fails" 66 env HO_FAKE_GH_USER=alice "$h" tickets unblock 999

# Local backend: the terminal verb moves blocked to ready with one status line.
(
  export HO_TICKETS_SOURCE=local HO_TICKETS_DIR="$base/local"
  unset HO_TICKETS_REPO
  lt=$(ticket "Local blocked" blocked)
  assert_exit "H-031 local: unblock of a blocked ticket succeeds" 0 "$h" tickets unblock "$lt"
  f=$(find "$base/local" -name "$lt-*.md")
  assert_eq "H-030 local: exactly one status line, ready" "status: ready" "$(sed -n '/^$/q; /^status:/p' "$f")"
  assert_exit "H-031 local: unblock of a ready ticket is refused" 65 "$h" tickets unblock "$lt"
)

# H-031 a person unblocks, never a harness session: inside a session (the launcher exports
# HO_SESSION_ID and HO_SESSION_NAME) the terminal unblock is refused (exit 77, as autonomy
# approve) and the ticket stays blocked, even when the signed-in account can write.
t9=$(ticket "Session tries to unblock" blocked)
assert_exit "H-031 unblock from inside a session (session name) is refused (exit 77)" 77 env HO_FAKE_GH_USER=alice HO_SESSION_NAME=w1 "$h" tickets unblock "$t9"
assert_exit "H-031 unblock from inside a session (session id) is refused (exit 77)" 77 env HO_FAKE_GH_USER=alice HO_SESSION_ID=0b7c5f2e-1d1a-4c49-9a57-3f0e8d6a2b11 "$h" tickets unblock "$t9"
assert_eq "H-031 R10.3 the ticket a session tried to unblock stays blocked" '["harness:blocked"]' "$(state_labels "$t9")"
err=$(env HO_FAKE_GH_USER=alice HO_SESSION_NAME=w1 "$h" tickets unblock "$t9" 2>&1 >/dev/null || true)
assert_contains "H-031 the refusal says a person unblocks" "$err" "person"
(
  export HO_TICKETS_SOURCE=local HO_TICKETS_DIR="$base/local"
  unset HO_TICKETS_REPO
  lt2=$(ticket "Local blocked, session" blocked)
  assert_exit "H-031 local: unblock from inside a session is refused (exit 77)" 77 env HO_SESSION_NAME=w1 "$h" tickets unblock "$lt2"
)
