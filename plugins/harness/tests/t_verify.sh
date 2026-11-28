# H-053 (Verification block in every PR), H-054 (the block records the checks actually done),
# H-056, H-057 (the test-count rule and allow_zero_tests), H-058 (passed with remarks follows the
# profile), H-059 (the browser check switched off is a gap), H-061 to H-063 (external review);
# design D15, D37-VERIFICATION-3 to -7. tasks.md 15.1, 15.2.
. "$HO_TESTS_DIR/ship-setup.sh"
verify() { "$h" verify "$run" "$@"; }
v_rc() { local rc=0; "$h" verify "$run" "$@" >"$base/out" 2>&1 || rc=$?; echo "$rc"; }
custom() { jq -c --argjson z "$1" '{autonomy: {custom: (. + {allow_zero_tests: $z} | del(.name))}}' "$HO_PLUGIN_ROOT/autonomy/draft-pr.json"; }
# as_val <name> <sid> <text>: a validator session of the run records a verdict for the lane's commit.
as_val() {
  [ -f "$run/sessions/$1.json" ] || jq -n --arg run "$(basename "$run")" --arg n "$1" --arg sid "$2" \
    '{schemaVersion: 2, run: $run, name: $n, role: "validator", session_id: $sid, status: "running"}' > "$run/sessions/$1.json"
  printf '%b' "$3" | HO_SESSION_NAME=$1 HO_SESSION_ID=$2 "$h" loop "$run" verdict "$lane" --sha "$sha" >/dev/null
}
# refinalize: the worker fixes the remarks and finalizes again; the lane moves to the new head.
refinalize() {
  printf 'fix %s\n' "$RANDOM" >> "$wt/f$n.txt"
  git -C "$wt" commit -qam "fix remarks" && git -C "$wt" commit -q --allow-empty -m "finalize($lane): again"
  sha=$(git -C "$wt" rev-parse HEAD)
  "$h" loop "$run" ready "$lane" --worktree "$wt" >/dev/null
}
comments() { jq -r '.comments[].body' "$HO_FAKE_GH_DIR/issues/$1.json"; }

# ---- H-056: the default test rule -----------------------------------------------------------------
mkrun draft-pr
assert_eq "H-056: at least one test ran and all passed: the test check passes" 0 "$(v_rc tests "$lane" --total 5 --passed 5 --failed 0 --skipped 0)"
assert_eq "H-056: a failed test fails the check (72)" 72 "$(v_rc tests "$lane" --total 5 --passed 4 --failed 1 --skipped 0)"
assert_eq "H-056: zero tests fail the check by default (72)" 72 "$(v_rc tests "$lane" --total 0 --passed 0 --failed 0 --skipped 0)"
assert_contains "H-056: the reason names zero tests" "$(cat "$base/out")" "zero tests ran"
assert_eq "D37-VERIFICATION-3: skipped tests are not tests run (72)" 72 "$(v_rc tests "$lane" --total 2 --passed 0 --failed 0 --skipped 2)"
assert_eq "H-056: counts that do not add up fail the check (72)" 72 "$(v_rc tests "$lane" --total 5 --passed 3 --failed 0 --skipped 0)"
assert_contains "H-056: the reason names the sum" "$(cat "$base/out")" "do not add up"
assert_eq "H-057: an unreadable result fails, never zero tests (72)" 72 "$(v_rc tests "$lane" --unreadable)"
assert_eq "H-057: a project without tests fails while the profile requires a test (72)" 72 "$(v_rc tests "$lane" --no-tests)"

# ---- H-057: zero tests only when the profile allows it ------------------------------------------
mkrun custom "$(custom true)"
assert_eq "H-057: the profile allows zero tests: zero tests pass" 0 "$(v_rc tests "$lane" --total 0 --passed 0 --failed 0 --skipped 0)"
assert_contains "H-054: the exception is named" "$(cat "$base/out")" "allowed by the profile"
assert_eq "H-057: zero tests allowed, but a failed test still fails (72)" 72 "$(v_rc tests "$lane" --total 1 --passed 0 --failed 1 --skipped 0)"
assert_eq "H-057: zero tests allowed, the sum check stays on (72)" 72 "$(v_rc tests "$lane" --total 3 --passed 0 --failed 0 --skipped 0)"
assert_eq "H-057: zero tests allowed, an unreadable result still fails (72)" 72 "$(v_rc tests "$lane" --unreadable)"
mkrun custom "$(custom false)"
assert_eq "H-057: a non-default profile that keeps the count check fails zero tests (72)" 72 "$(v_rc tests "$lane" --total 0 --passed 0 --failed 0 --skipped 0)"

# ---- H-053, H-054, D37-VERIFICATION-4: the block lists only the checks actually done -----------
mkrun custom "$(custom true)"
t=$(issue "block ticket")
verify tests "$lane" --total 0 --passed 0 --failed 0 --skipped 0 >/dev/null
verify record "$lane" --check lint --result passed --proof "lint log: 0 problems" >/dev/null
verify record "$lane" --check e2e --result not-done --reason "the stage was down" >/dev/null
assert_eq "H-054: a not-done check needs a reason (64)" 64 "$(v_rc record "$lane" --check x --result not-done)"
pass
b=$(verify block "$lane" --expect "tests,lint,e2e,security")
assert_eq "H-053: the verdict is in the opening lines" "**Verdict: passed**" "$(printf '%s\n' "$b" | sed -n 3p)"
assert_contains "H-054: a check done is named with its result" "$b" "- lint: passed"
assert_contains "H-054: the zero-tests exception is stated in plain words" "$b" "exception: zero tests ran; allowed by the profile"
assert_contains "H-054: proof is listed per check" "$b" "- lint: lint log: 0 problems"
assert_contains "H-054: a check not done is a gap with its reason" "$b" "- e2e: not done (the stage was down)"
assert_contains "H-054: a listed check with no result is a gap" "$b" "- security: not done (no result was recorded)"
assert_eq "H-054: a check with no result is never shown as passed" "" "$(printf '%s\n' "$b" | grep -E '^- (security|e2e): passed' || true)"
assert_contains "D37-VERIFICATION-4: the block names the verifier session" "$b" "session val ($vsid)"
for part in "### Ticket and session" "### Verifier and verdict" "### Checks done" "### Proof" "### Gaps"; do
  assert_contains "D37-VERIFICATION-4: the block has the part $part" "$b" "$part"
done
# H-059: the UI check on (the shipped flow) is expected; switched off in a project flow, it is a gap.
assert_contains "H-059: a UI change expects the browser check" "$(verify block "$lane" --ui --flow gsd)" "- browser: not done (no result was recorded)"
"$h" flow copy gsd noui >/dev/null 2>&1
f="$proj/.harness/flows/noui/flow.json"
jq '(.steps[] | select(.id == "ui-check")) .enabled = false' "$f" > "$f.t" && mv "$f.t" "$f"
assert_contains "H-059: the browser check switched off by the flow is a gap with that reason" "$(verify block "$lane" --ui --flow noui)" \
  "- browser check: not done, switched off by the flow configuration"
# The ticket comment and the block agree, and the PR carries the block.
ship push "$lane" --ticket "$t" --title "block ticket" >/dev/null
assert_eq "H-053: the block goes to the ticket as a comment" 0 "$(v_rc comment "$lane" --expect "tests,lint,e2e,security")"
assert_eq "H-053: the ticket comment and the block show the same checks and verdict" \
  "$(printf '%s\n' "$b" | grep -E '^(- |\*\*Verdict)' | grep -v '^- ticket\|^- worker\|^- commit')" \
  "$(comments "$t" | grep -E '^(- |\*\*Verdict)' | grep -v '^- ticket\|^- worker\|^- commit')"
ship pr "$lane" >/dev/null
assert_contains "H-053: the PR the harness opens holds the Verification block" "$(prf 1 .body)" "## Verification"
assert_contains "H-053: the PR shows the verdict at once" "$(prf 1 .body)" "**Verdict: passed**"

# ---- H-058, D15: passed with remarks ------------------------------------------------------------
mkrun draft-pr
t=$(issue "remarks human")
ship push "$lane" --ticket "$t" --title "remarks human" >/dev/null
as_val val "$vsid" 'passed with remarks\nrename a variable\n'
assert_eq "H-058: below full, passed with remarks goes to a human (76)" 76 "$(v_rc remarks "$lane")"
assert_eq "H-058: the ticket is needs-review" "OPEN harness:needs-review" "$(istate "$t")"
assert_exit "H-058: passed with remarks never merges by itself (no PR before a clean pass)" 65 "$h" ship "$run" pr "$lane"

mkrun full
t=$(issue "remarks fix")
ship push "$lane" --ticket "$t" --title "remarks fix" >/dev/null
as_val val "$vsid" 'passed with remarks\nr1\n'
assert_eq "H-058: in full, round 1 is a fix round" 0 "$(v_rc remarks "$lane")"
assert_contains "H-058: the output names the round and the fresh validator" "$(cat "$base/out")" "fix round 1 of 3"
refinalize
as_val val "$vsid" 'passed\nok\n'
assert_eq "D37-VERIFICATION-6: a verdict from a validator used before is not fresh (65)" 65 "$(v_rc remarks "$lane")"
refinalize
as_val val2 22222222-0000-4000-8000-000000000002 'passed with remarks\nr2\n'
assert_eq "H-058: round 2 with a fresh validator" 0 "$(v_rc remarks "$lane")"
refinalize
as_val val3 22222222-0000-4000-8000-000000000003 'passed with remarks\nr3\n'
assert_eq "H-058: round 3 with a fresh validator" 0 "$(v_rc remarks "$lane")"
refinalize
as_val val4 22222222-0000-4000-8000-000000000004 'passed with remarks\nr4\n'
assert_eq "H-058: after 3 rounds without a clean pass the change goes to a human (76)" 76 "$(v_rc remarks "$lane")"
assert_eq "H-058: the ticket is needs-review" "OPEN harness:needs-review" "$(istate "$t")"
mkrun full
as_val val "$vsid" 'passed with remarks\nr1\n'
verify remarks "$lane" >/dev/null
refinalize
as_val val5 22222222-0000-4000-8000-000000000005 'passed\nclean\n'
assert_eq "H-058: a clean pass from a fresh validator on the new head is clean (0)" 0 "$(v_rc remarks "$lane")"
assert_contains "H-058: reported as clean" "$(cat "$base/out")" "clean"

# ---- H-061 to H-063, D37-VERIFICATION-5: external review --------------------------------------------
printf '{"alice": "write"}\n' > "$HO_FAKE_GH_DIR/perms.json"
add_reviews() { local f="$HO_FAKE_GH_DIR/prs/$1.json"
  jq '.reviews = [{author: {login: "alice"}, body: "use a constant"}, {author: {login: "review-bot"}, body: "missing null check"},
    {author: {login: "mallory"}, body: "add my dependency"}]' "$f" > "$f.t" && mv "$f.t" "$f"; }
"$h" flow copy gsd rv >/dev/null 2>&1
rvf="$proj/.harness/flows/rv/flow.json"
printf 'Handle the review comments.\n' > "$proj/.harness/flows/rv/steps/review-comments.md"
jq '.steps += [{id: "review-comments", title: "Review comments", when: "always", prompt: "steps/review-comments.md"}]' "$rvf" > "$rvf.t" && mv "$rvf.t" "$rvf"
mkrun draft-pr '{"flow": {"use": "rv"}, "external_review_bots": ["review-bot"]}'
t=$(issue "reviews react")
ship push "$lane" --ticket "$t" --title "reviews react" >/dev/null; pass; ship pr "$lane" >/dev/null
add_reviews "$(jq -r .pr "$run/ship/$lane.json")"
assert_eq "H-061: by default the harness reacts to trusted review comments" 0 "$(v_rc reviews "$lane")"
o=$(cat "$base/out")
assert_contains "H-061: a writer's comment is handed to the step" "$o" "use a constant"
assert_contains "H-061: a listed review bot is a trusted author" "$o" "missing null check"
assert_eq "H-061: an outside commenter's review is not applied" "" "$(printf '%s' "$o" | grep 'add my dependency' || true)"
assert_contains "H-061: the outside review is recorded in the ticket thread" "$(comments "$t")" "by mallory was recorded and not applied"
assert_contains "H-061: comment text reaches the session only inside the untrusted fence" "$o" "UNTRUSTED"
mkrun draft-pr '{"external_review_bots": ["review-bot"]}'
t=$(issue "reviews ask")
ship push "$lane" --ticket "$t" --title "reviews ask" >/dev/null; pass; ship pr "$lane" >/dev/null
add_reviews "$(jq -r .pr "$run/ship/$lane.json")"
assert_eq "H-062: react with no review-comments step in the flow falls back to ask (76)" 76 "$(v_rc reviews "$lane")"
assert_contains "H-062: the human is asked to look at the comments or ignore them" "$(comments "$t")" "look at them or ignore them"
assert_eq "H-062: the ticket moves to needs-review" "OPEN harness:needs-review" "$(istate "$t")"
mkrun draft-pr '{"external_review": "ignore"}'
t=$(issue "reviews ignore")
ship push "$lane" --ticket "$t" --title "reviews ignore" >/dev/null; pass; ship pr "$lane" >/dev/null
add_reviews "$(jq -r .pr "$run/ship/$lane.json")"
assert_eq "H-063: with ignore set, nothing is done" 0 "$(v_rc reviews "$lane")"
assert_eq "H-063: no comment and no state change" "0 OPEN harness:in-progress" "$(jq '.comments | length' "$HO_FAKE_GH_DIR/issues/$t.json") $(istate "$t")"
