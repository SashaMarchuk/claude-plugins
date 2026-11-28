# H-043 (push and PR only when the settings allow), H-044 (the draft PR opening point), H-045 (a
# confirmed merge closes the ticket after its post-merge steps), H-046 (every merge is confirmed
# through git), H-050 (stage release with an automatic smoke test), H-051 (revert or fix after a
# failed smoke test); design D10, D11, S8-07. tasks.md 14.2. A local bare remote and the fake gh;
# nothing reaches GitHub.
. "$HO_TESTS_DIR/ship-setup.sh"

# ---- H-043: remote writes forbidden (safe) ------------------------------------------------------
mkrun safe
t=$(issue "fix the login")
assert_eq "H-043: a push the profile forbids is refused (77)" 77 "$(ship_rc push "$lane" --ticket "$t" --title "Fix the login")"
assert_eq "H-043: nothing reaches the remote until a human pushes" none "$(remote_sha "harness/$t-fix-the-login")"

# ---- S8-07, H-043: push to the ticket branch -----------------------------------------------------
mkrun draft-pr
assert_eq "H-043: the push is allowed under draft-pr" 0 "$(ship_rc push "$lane" --ticket "$t" --title "Fix the login!")"
assert_eq "S8-07: the branch is harness/<ticket>-<short title> and git shows it at the finalize commit" "$sha" "$(remote_sha "harness/$t-fix-the-login")"
cfg draft-pr '{"git": {"branch_prefix": "bot/"}}'
r_prev=$run
mkrun draft-pr '{"git": {"branch_prefix": "bot/"}}'
ship push "$lane" --ticket "$t" --title "Other" >/dev/null
assert_eq "S8-07: the branch prefix is configurable" "$sha" "$(remote_sha "bot/$t-other")"
run=$r_prev lane=l2 sha=$(jq -r .sha "$r_prev/ship/l2.json")

# ---- D10, H-044: no draft PR before the validator passes ---------------------------------------
assert_eq "D10: no draft PR before the validator passes (65)" 65 "$(ship_rc pr "$lane")"
assert_eq "D10: gh was not asked to open a PR" "" "$(grep '^pr' "$HO_FAKE_GH_DIR/calls.log" || true)"
pass
assert_eq "D10: after a passed verdict the PR opens" 0 "$(ship_rc pr "$lane")"
pr=$(jq -r .pr "$run/ship/$lane.json")
assert_eq "D10: the PR is a draft on the ticket branch into main" "true harness/$t-fix-the-login main" "$(prf "$pr" '"\(.isDraft) \(.headRefName) \(.baseRefName)"')"
assert_contains "S8-07: the PR links its ticket and, on GitHub, closes it" "$(prf "$pr" .body)" "Closes #$t"
assert_eq "D10: a profile that never merges does not mark the PR ready" "" "$(grep '^pr	ready' "$HO_FAKE_GH_DIR/calls.log" || true)"

# ---- H-046: a merge git does not confirm keeps the ticket open ---------------------------------
assert_eq "H-046: no merge on the base: not confirmed (70)" 70 "$(ship_rc merged "$lane")"
assert_contains "H-046: it is reported as failed" "$(cat "$base/out")" "merge FAILED"
assert_eq "H-046: the ticket stays open and in progress" "OPEN harness:in-progress" "$(istate "$t")"
# A merge that "reports success" but changed nothing: the PR reads merged with a commit that holds
# some other change.
other=$(git -C "$proj" rev-parse HEAD)
printf 'x\n' > "$proj/unrelated.txt"; git -C "$proj" add unrelated.txt; git -C "$proj" commit -qm unrelated; git -C "$proj" push -q origin main
pr_merged "$pr" "$(git -C "$proj" rev-parse HEAD)"
assert_eq "H-046: a merge reported as done whose commit holds another change is not confirmed (70)" 70 "$(ship_rc merged "$lane")"
assert_eq "H-046: the ticket is still not done" "OPEN harness:in-progress" "$(istate "$t")"

# ---- H-045, D11: a confirmed merge sets the ticket to done and closes it ------------------------
merge_into main merge >/dev/null
assert_eq "H-046: a merge git shows in the base is confirmed" 0 "$(ship_rc merged "$lane")"
assert_eq "H-045: the ticket is done and closed" "CLOSED harness:done" "$(istate "$t")"
assert_contains "H-046: the ledger records the confirmed merge" "$(jq -r .kind "$run/ledger.jsonl")" ship-merge-confirmed

# ---- H-046 squash merge; D11 close_on_merge false -----------------------------------------------
mkrun draft-pr '{"close_on_merge": false}'
t2=$(issue "second")
ship push "$lane" --ticket "$t2" --title second >/dev/null; pass; ship pr "$lane" >/dev/null
pr2=$(jq -r .pr "$run/ship/$lane.json")
pr_merged "$pr2" "$(merge_into main squash)"
assert_eq "H-046: a squash merge whose commit carries the same change is confirmed" 0 "$(ship_rc merged "$lane")"
assert_eq "D11: with close_on_merge false the ticket is done and left open" "OPEN harness:done" "$(istate "$t2")"

# ---- H-045: post-merge steps the profile does not run keep the ticket in progress ---------------
user_cfg "{\"smoke\": {\"use\": \"s\", \"list\": {\"s\": {\"command\": \"test ! -e $base/smoke-fail\"}}}}"
mkrun draft-pr
t3=$(issue "third")
ship push "$lane" --ticket "$t3" --title third >/dev/null; pass; ship pr "$lane" >/dev/null
merge_into main merge >/dev/null
assert_eq "H-045: a confirmed merge with a smoke test the profile does not run waits for a human (76)" 76 "$(ship_rc merged "$lane")"
assert_eq "H-045: the ticket stays in progress" "OPEN harness:in-progress" "$(istate "$t3")"

# ---- H-050: stage release, the smoke test starts by itself ---------------------------------------
git -C "$proj" push -q origin main:stage
mkrun full '{"stage": {"allow": true, "branch": "stage"}}'
t4=$(issue "fourth")
ship push "$lane" --ticket "$t4" --title fourth >/dev/null; pass; ship pr "$lane" >/dev/null
pr4=$(jq -r .pr "$run/ship/$lane.json")
assert_eq "H-050: with a stage release allowed the PR goes into the stage branch" stage "$(prf "$pr4" .baseRefName)"
assert_eq "D10: a profile that may merge marks the PR ready" false "$(prf "$pr4" .isDraft)"
merge_into stage merge >/dev/null
assert_eq "H-050: the confirmed stage merge runs the smoke test and then sets done" 0 "$(ship_rc merged "$lane")"
assert_contains "H-050: the smoke test started without a human" "$(jq -r .kind "$run/ledger.jsonl")" smoke-passed
assert_eq "H-045: done only after the smoke test passed" "CLOSED harness:done" "$(istate "$t4")"

# ---- H-051: a failed smoke test runs the configured reaction ------------------------------------
: > "$base/smoke-fail"
mkrun full '{"smoke": {"on_fail": "fix"}}'
t5=$(issue "fifth")
ship push "$lane" --ticket "$t5" --title fifth >/dev/null; pass; ship pr "$lane" >/dev/null
merge_into main merge >/dev/null
assert_eq "H-051: a failed smoke test fails the post-merge step (72)" 72 "$(ship_rc merged "$lane")"
assert_eq "H-051: reaction fix: a fix is due for the ticket" "$t5" "$(jq -r 'select(.kind == "smoke-fix-due") | .ticket' "$run/ledger.jsonl")"
assert_eq "H-045: after a failed smoke test the ticket is not done" "OPEN harness:in-progress" "$(istate "$t5")"
mkrun full '{"smoke": {"on_fail": "revert"}}'
t6=$(issue "sixth")
ship push "$lane" --ticket "$t6" --title sixth >/dev/null; pass; ship pr "$lane" >/dev/null
merge_into main merge >/dev/null
assert_eq "H-051: reaction revert also fails the step (72)" 72 "$(ship_rc merged "$lane")"
git -C "$proj" fetch -q origin
assert_eq "H-051: reaction revert: the change is reverted on the base" "no" \
  "$(git -C "$proj" cat-file -e "origin/main:f$n.txt" 2>/dev/null && echo yes || echo no)"
assert_eq "H-051: the earlier merged changes stay" yes "$(git -C "$proj" cat-file -e "origin/main:f2.txt" 2>/dev/null && echo yes || echo no)"
assert_eq "H-051: the reverted ticket is not done" "OPEN harness:in-progress" "$(istate "$t6")"
