# Urgent ticket out of turn (T19; H-083, H-084, H-105; D3). The label harness:urgent, set by a
# writer, puts a ready ticket first. With no free worker slot the newest lane pauses after its
# current step; the worker cap is never exceeded; one urgent ticket at a time.
. "$HO_TESTS_DIR/intake-setup.sh"
run=$(cd "$proj" && "$h" run new --workers 1)
hold() { mkdir -p "$run/slots/worker"; printf '{"holder": "%s"}\n' "$1" > "$run/slots/worker/$1.json"; }
free() { rm -f "$run/slots/worker/$1.json"; }
urgent() { as "$1" issue edit "$2" --repo fake/repo --add-label harness:urgent >/dev/null; }
starts() { printf '%s\n' "$1" | grep -c '^start ' || true; }

# H-083: with a free slot the urgent ticket starts before any other queued ticket.
t0=$(ticket "Queued first")
tu=$(ticket "Urgent first")
label alice "$t0" ready
label alice "$tu" ready
urgent alice "$tu"
out=$(tick)
assert_contains "H-083 the urgent ticket starts before an older queued ticket" "$out" "start $tu"
assert_eq "H-105 one free slot: only one ticket starts" "1" "$(starts "$out")"
assert_contains "H-083 the urgent start is recorded" "$(jq -c 'select(.kind == "urgent-start")' "$run/ledger.jsonl")" "\"ticket\":\"$tu\""
hold wu
"$h" tickets "done" "$tu" >/dev/null
free wu
tick >/dev/null   # t0 starts now that the urgent one is done
hold w0

# H-084 D3: the cap is full; an urgent ticket pauses the newest lane after its current step.
t2=$(ticket "Urgent second")
label alice "$t2" ready
urgent alice "$t2"
out=$(tick)
assert_contains "H-084 no free slot: the newest lane pauses" "$out" "pause $t0 for $t2"
assert_contains "H-084 the urgent ticket waits for the slot" "$out" "urgent-waiting $t2"
assert_eq "H-105 the cap is never exceeded: nothing starts" "0" "$(starts "$out")"
assert_eq "H-084 the urgent ticket stays ready while it waits" '["harness:ready","harness:urgent"]' "$(labels "$t2")"
rc=0; "$h" state "$run" begin --ticket "$t0" --step execute >/dev/null 2>&1 || rc=$?
assert_eq "H-084 D3 the paused lane begins no next step (soft: after its current step)" "75" "$rc"
out=$(tick)
assert_eq "H-084 a second tick pauses no further lane" "" "$(printf '%s' "$out" | grep '^pause ' || true)"
free w0
out=$(tick)
assert_contains "H-084 the freed slot goes to the urgent ticket" "$out" "start $t2"
hold w2

# D3: one urgent ticket at a time; a second one waits until the first is done.
t3=$(ticket "Urgent third")
label alice "$t3" ready
urgent alice "$t3"
free w2
out=$(tick)
assert_contains "D3 a second urgent ticket waits while the first runs" "$out" "urgent-waiting $t3"
assert_eq "D3 the second urgent ticket does not start" "" "$(printf '%s\n' "$out" | grep -x "start $t3" || true)"
"$h" tickets "done" "$t2" >/dev/null
out=$(tick)
assert_contains "D3 when the first urgent ticket is done, the paused lane is let go" "$out" "unpause $t0"
assert_exit "D3 the let-go lane may begin its next step" 0 "$h" state "$run" begin --ticket "$t0" --step execute
assert_contains "D3 then the second urgent ticket starts" "$out" "start $t3"

# D3: the urgent label also passes the write-access check; a reader's urgent label is no urgency.
"$h" tickets "done" "$t3" >/dev/null
t4=$(ticket "Queued normal")
t5=$(ticket "Reader urgent")
label alice "$t4" ready
label alice "$t5" ready
urgent rita "$t5"
out=$(tick)
assert_contains "D3 a reader's urgent label gives no priority: the older ticket starts" "$out" "start $t4"
assert_contains "D3 the refused urgency is recorded" "$(jq -c 'select(.kind == "urgent-refused")' "$run/ledger.jsonl")" "\"ticket\":\"$t5\""
