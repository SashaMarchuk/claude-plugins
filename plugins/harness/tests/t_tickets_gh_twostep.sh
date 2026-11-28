# GitHub ticket verbs (D2, D11, H-030; wave-1 follow-ups #88): done tickets are listed although
# done closes the issue; show tells an outage from a missing ticket; a two-step verb that fails
# half way leaves no half state (blocked with no reason, or done while still open).
h="$HO_PLUGIN_ROOT/bin/harness"
printf '## Outcome\nx\n\n## Scope\ny\n\n## Acceptance criteria\nz\n' > body.md
printf 'why\n' > why.md
export HO_FAKE_GH_DIR="$PWD/gh" HO_TICKETS_SOURCE=github HO_TICKETS_REPO=fake/repo
labels() { jq -c '[.labels[]] | sort' "$HO_FAKE_GH_DIR/issues/$1.json"; }
"$h" tickets add "First" body.md >/dev/null
"$h" tickets add "Second" body.md >/dev/null
"$h" tickets claim 1 >/dev/null
"$h" tickets claim 2 >/dev/null

# ---- done is listed ----
"$h" tickets done 1 >/dev/null
assert_eq "D11 (#88): a done ticket is listed by ids done, although done closed the issue" 1 "$("$h" tickets ids done 2>/dev/null)"

# ---- show: an outage is not "no ticket" ----
rc=0; "$h" tickets show 99 >/dev/null 2>&1 || rc=$?
assert_eq "D2: show of a missing ticket exits 66" 66 "$rc"
rc=0; HO_FAKE_GH_FAIL="issue view" "$h" tickets show 2 >/dev/null 2>"$PWD/err" || rc=$?
assert_eq "D2 (#88): show during a tracker outage is not 'no ticket' (69)" 69 "$rc"
assert_eq "D2 (#88): its message does not say there is no ticket" "" "$(grep -i 'no ticket' "$PWD/err" || true)"

# ---- two-step verbs ----
rc=0; HO_FAKE_GH_FAIL="issue comment" "$h" tickets block 2 why.md >/dev/null 2>&1 || rc=$?
assert_eq "test setup: block fails when its reason cannot be posted" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
assert_eq "H-030 (#88): a block whose reason was not posted leaves the ticket unblocked" '["harness:in-progress"]' "$(labels 2)"
rc=0; HO_FAKE_GH_FAIL="issue close" "$h" tickets done 2 >/dev/null 2>&1 || rc=$?
assert_eq "test setup: done fails when the issue cannot be closed" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
assert_eq "D11 (#88): a done whose close failed is not left done while open" '["harness:in-progress"]' "$(labels 2)"
"$h" tickets done 2 --keep-open >/dev/null
assert_eq "D11: done --keep-open still sets done and leaves the issue open" '["harness:done"] OPEN' "$(labels 2) $(jq -r .state "$HO_FAKE_GH_DIR/issues/2.json")"
