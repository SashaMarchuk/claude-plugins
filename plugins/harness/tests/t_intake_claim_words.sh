# The words after a failed claim say what is known (D2, H-030, H-031; #110). When the claim
# fails and the state cannot be read after it, the ticket may still be ready: the owner action
# says "may be in progress", the ledger state is unknown, and a blocked comment names no
# in-progress start state.
. "$HO_TESTS_DIR/intake-setup.sh"
mk_shim() { # <dir> <view-fail-count after the failed claim; "all" for every one>
  mkdir -p "$1"
  cat > "$1/gh" <<SHIM
#!/usr/bin/env bash
case " \$* " in
  *" issue edit "*"--add-assignee"*) : > "$1/claimed"; echo "simulated outage" >&2; exit 1 ;;
  *" issue view "*)
    if [ -e "$1/claimed" ]; then
      n=\$(cat "$1/views" 2>/dev/null || echo 0); n=\$((n + 1)); echo "\$n" > "$1/views"
      if [ "$2" = all ] || [ "\$n" -le "$2" ]; then echo "simulated outage" >&2; exit 1; fi
    fi ;;
esac
exec "$HO_TESTS_DIR/fake-bin/gh" "\$@"
SHIM
  chmod +x "$1/gh"
}
# ---- the tracker stays down: the move to blocked fails too ----
mk_shim "$base/down" all
t1=$(ticket "Claim during an outage")
label alice "$t1" ready
out=$(PATH="$base/down:$PATH" tick 2>/dev/null || true)
assert_contains "test setup: the pickup fails" "$out" "error $t1"
oa=$(jq -r --arg t "$t1" 'select(.kind == "owner-action") | .title' "$run/ledger.jsonl" | grep -F "ticket $t1 " | tail -n 1)
assert_eq "D2 (#110): the owner action says the ticket may be in progress, not that it is" "ticket $t1 may be in progress (or still ready) with no worker" "$oa"
assert_contains "D2 (#110): the ledger state of that pickup error is unknown" \
  "$(jq -c --arg t "$t1" 'select(.kind == "pickup-error" and .ticket == $t)' "$run/ledger.jsonl")" '"state":"unknown"'
assert_eq "test setup: the ticket really is still ready" '["harness:ready"]' "$(labels "$t1")"

# ---- the state read fails once, the move to blocked works (the same, still ready ticket) ----
mk_shim "$base/once" 1
out=$(PATH="$base/once:$PATH" tick 2>/dev/null || true)
assert_eq "test setup: the ticket is moved to blocked" '["harness:blocked"]' "$(labels "$t1")"
c=$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t1.json")
assert_eq "D2 (#110): the blocked comment does not claim an in-progress start state" "" "$(printf '%s\n' "$c" | grep -F '"from":"in-progress"' || true)"
assert_contains "D2 (#110): it names the start state as unknown" "$c" '"from":"unknown"'
