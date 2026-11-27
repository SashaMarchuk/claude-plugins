# Polling interval and the poll script (H-004, D4: default 60 s, one key, minimum 30, back-off
# to 15 minutes on tracker errors, a script polls). Time is tested by ageing the poll record
# with touch -t, never by waiting.
. "$HO_TESTS_DIR/intake-setup.sh"
setcfg() { jq "$1" "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"; }

# H-004 no interval set: the D4 default.
assert_eq "H-004 no interval set: the default is 60 seconds" "60" "$("$h" intake "$run" interval)"
# H-004 the user changes the interval.
setcfg '.tickets.poll_seconds = 45'
assert_eq "H-004 a new interval in the settings is used" "45" "$("$h" intake "$run" interval)"
setcfg '.tickets.poll_seconds = 30'
assert_eq "D4 30 seconds, the minimum, is accepted" "30" "$("$h" intake "$run" interval)"
# D4 minimum 30: below it is refused, never rounded up or replaced by the default.
setcfg '.tickets.poll_seconds = 29'
assert_exit "D4 an interval of 29 seconds is refused (exit 78)" 78 "$h" intake "$run" interval
err=$("$h" intake "$run" interval 2>&1 >/dev/null || true)
assert_contains "D4 the refusal names the minimum" "$err" "at least 30"
assert_exit "D4 tick refuses to poll with an interval below 30" 78 "$h" intake "$run" tick
assert_exit "D4 poll refuses to start with an interval below 30" 78 "$h" intake "$run" poll
setcfg '.tickets.poll_seconds = 0'
assert_exit "D4 an interval of 0 is refused" 78 "$h" intake "$run" interval
setcfg '.tickets.poll_seconds = "sixty"'
assert_exit "D4 a non-number interval is refused" 78 "$h" intake "$run" interval
setcfg '.tickets.poll_seconds = 60.5'
assert_exit "D4 a fractional interval is refused" 78 "$h" intake "$run" interval
setcfg '.tickets.poll_seconds = "60"'
assert_exit "D4 an interval given as text is refused" 78 "$h" intake "$run" interval
# The user config sets it when the project does not.
setcfg 'del(.tickets)'
jq '.tickets.poll_seconds = 120' "$user/config.json" > "$base/u.json" && mv "$base/u.json" "$user/config.json"
assert_eq "H-004 the user config sets the interval when the project does not" "120" "$("$h" intake "$run" interval)"
printf '{"schemaVersion": 2}\n' > "$user/config.json"

# A tick polls only when the interval has passed since the last poll.
"$h" intake "$run" tick >/dev/null
assert_eq "D4 the first tick records its poll" "yes" "$([ -f "$run/intake/poll.json" ] && echo yes || echo no)"
out=$("$h" intake "$run" tick)
assert_contains "D4 a tick within the interval does not poll" "$out" "not-due"
: > "$HO_FAKE_GH_DIR/calls.log"
"$h" intake "$run" tick >/dev/null
assert_eq "D4 a tick that is not due reads nothing from the tracker" "" "$(cat "$HO_FAKE_GH_DIR/calls.log")"
touch -t "$(date -v-50S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '-50 seconds' '+%Y%m%d%H%M.%S')" "$run/intake/poll.json"
out=$("$h" intake "$run" tick)
assert_contains "D4 50 seconds after the last poll: not due yet" "$out" "not-due"
touch -t "$(date -v-65S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '-65 seconds' '+%Y%m%d%H%M.%S')" "$run/intake/poll.json"
out=$("$h" intake "$run" tick)
assert_eq "D4 65 seconds after the last poll: the tick polls" "" "$(printf '%s' "$out" | grep not-due || true)"

# D4 back-off: tracker errors double the wait, up to 15 minutes; a good poll resets it.
age_poll
out=$(HO_FAKE_GH_FAIL="issue list" "$h" intake "$run" tick 2>/dev/null || true)
assert_contains "D4 a tracker error is reported by the tick" "$out" "tracker-error"
assert_eq "D4 one error: the next wait is 120 seconds" "120" "$("$h" intake "$run" interval --next)"
for i in 2 3 4; do age_poll; HO_FAKE_GH_FAIL="issue list" "$h" intake "$run" tick >/dev/null 2>&1 || true; done
assert_eq "D4 four errors: the next wait is 900 seconds (60 * 2^4 capped at 15 minutes)" "900" "$("$h" intake "$run" interval --next)"
for i in 5 6; do age_poll; HO_FAKE_GH_FAIL="issue list" "$h" intake "$run" tick >/dev/null 2>&1 || true; done
assert_eq "D4 more errors: the wait stays at 15 minutes" "900" "$("$h" intake "$run" interval --next)"
touch -t "$(date -v-880S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '-880 seconds' '+%Y%m%d%H%M.%S')" "$run/intake/poll.json"
out=$("$h" intake "$run" tick)
assert_contains "D4 during back-off a tick before the longer wait does not poll" "$out" "not-due"
age_poll
"$h" intake "$run" tick >/dev/null
assert_eq "D4 a good poll resets the wait to the interval" "60" "$("$h" intake "$run" interval --next)"
assert_contains "D4 the ledger records a tracker error" "$(ledger)" '"kind":"poll-error"'

# A stopped run does not poll; the poll loop ends at once with exit 75.
"$h" state "$run" stop "test stop" >/dev/null
assert_exit "H-003 a stopped run: tick exits 75" 75 "$h" intake "$run" tick
start=$(date +%s)
rc=0; "$h" intake "$run" poll >/dev/null 2>&1 || rc=$?
assert_eq "H-003 a stopped run: poll exits 75" "75" "$rc"
assert_eq "H-003 a stopped run: poll ends without waiting an interval" "yes" "$([ $(( $(date +%s) - start )) -lt 20 ] && echo yes || echo no)"

# H-079 D37-LIFECYCLE-3: a run that has ended (a run-end ledger line, here for all-done) claims
# nothing: tick and poll exit 75, as for a stop, and a ready ticket stays ready. A resume after the
# end lets intake take work again.
run2=$(cd "$proj" && "$h" run new)
jq -cn --arg r "$(basename "$run2")" '{ts: "2026-01-01T00:00:00Z", run: $r, kind: "run-end", reason: "all-done"}' >> "$run2/ledger.jsonl"
te=$(ticket "After the end")
label alice "$te" ready
rc=0; out=$("$h" intake "$run2" tick) || rc=$?
assert_eq "H-079 an ended run: tick exits 75" "75" "$rc"
assert_contains "H-079 an ended run: tick says the run has ended" "$out" "ended"
assert_eq "H-079 an ended run claims no ticket" '["harness:ready"]' "$(labels "$te")"
# The poll runs in the background and is ended after 20 s, so a poll that never stops fails here.
"$h" intake "$run2" poll >/dev/null 2>&1 & pp=$!
i=0; while kill -0 "$pp" 2>/dev/null && [ "$i" -lt 100 ]; do sleep 0.2; i=$((i + 1)); done
kill "$pp" 2>/dev/null || true
rc=0; wait "$pp" || rc=$?
assert_eq "H-079 an ended run: poll exits 75" "75" "$rc"
"$h" state "$run2" resume >/dev/null
out=$("$h" intake "$run2" tick)
assert_contains "H-079 after a resume the ended run takes work again" "$out" "start $te"

# H-086 D25a: a ticket that intake took before a soft:ticket stop counts as begun, so its first
# step and its worker may still start; a ticket intake did not take stays refused.
"$h" state "$run2" stop --type soft:ticket "finish what runs" >/dev/null
rc=0; "$h" state "$run2" begin --ticket "$te" --step plan >/dev/null 2>&1 || rc=$?
assert_eq "H-086 D25a a ticket picked up before a soft:ticket stop may begin its first step" "0" "$rc"
rc=0; "$h" state "$run2" begin --ticket 999 --step plan >/dev/null 2>&1 || rc=$?
assert_eq "H-086 D25a a ticket not picked up before the soft:ticket stop does not begin (75)" "75" "$rc"

# H-005 local tickets: with HO_TICKETS_DIR unset, intake reads the ticket folder of the run's own
# project, never the folder of the place it is called from.
(
  export HO_TICKETS_SOURCE=local
  unset HO_TICKETS_REPO HO_TICKETS_DIR
  other="$base/other"
  mkdir -p "$other/.harness"
  printf '{"schemaVersion": 2}\n' > "$other/.harness/config.json"
  la=$(cd "$proj" && ticket "Local in the run's project" ready)
  lb=$(cd "$other" && ticket "Local in another project" ready)
  run3=$(cd "$proj" && "$h" run new)
  out=$(cd "$other" && "$h" intake "$run3" tick)
  assert_contains "H-005 intake takes the ready ticket of the run's own project" "$out" "start $la"
  sb=$(sed -n '/^$/q; s/^status: //p' "$(find "$other/.harness/tickets" -name "$lb-*.md")")
  assert_eq "H-005 intake leaves a ticket of another project untouched" "ready" "$sb"
  sa=$(sed -n '/^$/q; s/^status: //p' "$(find "$proj/.harness/tickets" -name "$la-*.md")")
  assert_eq "H-005 the run's own ticket is the one claimed" "in-progress" "$sa"
)


# D25a H-086: a stop recorded while the first ticket's readiness check runs stops the tick before
# the next claim; the tickets after it stay ready.
run4=$(cd "$proj" && "$h" run new --workers 5)
mkdir -p "$base/stop-shim"
cat > "$base/stop-shim/claude" <<SHIM
#!/usr/bin/env bash
# The first judge records a stop, as an owner would while it runs; then the fake claude answers.
[ -e "$base/stop-shim/done" ] || { : > "$base/stop-shim/done"; "$h" state "$run4" stop "stop during the judge" >/dev/null; }
exec "$HO_TESTS_DIR/fake-bin/claude" "\$@"
SHIM
chmod +x "$base/stop-shim/claude"
ts1=$(ticket "Before the stop")
ts2=$(ticket "After the stop")
label alice "$ts1" ready
label alice "$ts2" ready
rc=0; out=$(PATH="$base/stop-shim:$PATH" "$h" intake "$run4" tick) || rc=$?
assert_eq "D25a a stop during the tick allows exactly one claim" "1" "$(jq -c 'select(.kind == "pickup")' "$run4/ledger.jsonl" | grep -c . || true)"
assert_eq "D25a the ticket after the stop is not claimed" '["harness:ready"]' "$(labels "$ts2")"
assert_contains "D25a the tick says the run is stopped" "$out" "stopped"
assert_eq "D25a a tick that sees a stop before a claim exits 75" "75" "$rc"
