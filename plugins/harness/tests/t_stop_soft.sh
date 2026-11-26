# H-086 (soft stop variants, the current step as the default), H-085 (one stop category reused
# by the slot and launch gates), design D25 (soft:step, soft:task, soft:ticket), D25a (a soft stop
# takes no new ticket or step), D25b (the STOP file applies soft:step). tasks.md 17.1, soft part.
. "$HO_TESTS_DIR/sessions-setup.sh"

ledger_stops() { jq -r 'select(.kind == "stop") | "\(.source) \(.type)"' "$1/ledger.jsonl" | tr '\n' ',' | sed 's/,$//'; }
begin_rc() { local rc=0; "$h" state "$1" begin --ticket "$2" --step "$3" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
wl() { local r=$1 n=$2; shift 2; "$h" session "$r" launch --role worker --name "$n" --cwd "$proj/src" --prompt "$base/prompt.md" "$@"; }
wl_rc() { local rc=0; wl "$@" >/dev/null 2>&1 || rc=$?; echo "$rc"; }
alive_rec() { local p; p=$(jq -r '.pid // empty' "$1/sessions/$2.json" 2>/dev/null); [ -n "$p" ] && alive "$p" && echo yes || echo no; }

# ---- the stop verb: variants, scope, refusals ------------------------------------------------
r=$("$h" run new --workers 5)
assert_exit "H-086: an unknown stop type is refused (64)" 64 "$h" state "$r" stop --type soft:nope
assert_exit "H-086: hard stops are not part of this verb yet (64, #67)" 64 "$h" state "$r" stop --type hard:now
assert_exit "H-086: --ticket goes only with soft:ticket (64)" 64 "$h" state "$r" stop --ticket 5
assert_exit "H-086: a ticket id must be a number (64)" 64 "$h" state "$r" stop --type soft:ticket --ticket 5x
assert_eq "H-086: a refused stop records nothing" "" "$(ledger_stops "$r")"
assert_exit "H-086: a run with no stop reads as not stopped" 1 "$h" state "$r" stopped
assert_exit "H-086: begin needs a ticket and a step (64)" 64 "$h" state "$r" begin --ticket 1
assert_exit "H-086: a step id is a-z 0-9 - only (64)" 64 "$h" state "$r" begin --ticket 1 --step 'Bad Step'
assert_eq "H-086: with no stop, a step may begin" 0 "$(begin_rc "$r" 1 s1)"
assert_eq "H-086: begin records the ticket and the step" "1 s1" \
  "$(jq -r 'select(.kind == "step-begin") | "\(.ticket) \(.step)"' "$r/ledger.jsonl")"

# ---- soft:step (the default): the current step finishes, nothing new starts ------------------
wl "$r" w1 --ticket 1 >/dev/null
assert_eq "test setup: worker w1 of ticket 1 runs" yes "$(alive_rec "$r" w1)"
out=$("$h" state "$r" stop "owner asked")
assert_eq "H-086: a stop without a type is the default soft:step" "verb soft:step" "$(ledger_stops "$r")"
sid=$(jq -r 'select(.kind == "stop") | .stop_id' "$r/ledger.jsonl")
assert_contains "H-086: the stop output names its stop id" "$out" "$sid"
assert_contains "H-086: the stop output says the stop text is not delivered by this verb" "$out" "not delivered"
assert_eq "H-086: the stop id fits the instruction id format of session deliver" yes \
  "$(printf '%s' "$sid" | grep -Eqx '[a-z0-9-]{6,40}' && echo yes || echo no)"
assert_eq "H-086: soft:step lets no new step of the running ticket begin (75)" 75 "$(begin_rc "$r" 1 s2)"
assert_eq "H-086: soft:step lets no new ticket begin (75)" 75 "$(begin_rc "$r" 2 s1)"
assert_eq "H-086: soft:step launches no worker for the running ticket (75)" 75 "$(wl_rc "$r" w2 --ticket 1)"
assert_eq "H-086: soft:step launches no worker without a ticket (75)" 75 "$(wl_rc "$r" w3)"
assert_eq "H-086: the refused launches leave no record" "no no" \
  "$([ -e "$r/sessions/w2.json" ] && echo yes || echo no) $([ -e "$r/sessions/w3.json" ] && echo yes || echo no)"
assert_eq "D25a: the session of the current step keeps running" yes "$(alive_rec "$r" w1)"
assert_eq "D25a: the session of the current step keeps its worker slot" yes "$([ -f "$r/slots/worker/w1.json" ] && echo yes || echo no)"
assert_exit "D25a: the current step may still take the heavy slot to finish" 0 "$h" slot "$r" acquire heavy --holder w1 --op app-build
assert_exit "D25a: the current step may still take a stage slot to finish" 0 "$h" slot "$r" acquire stage:browser --holder w1
assert_eq "H-086: no step-begin was written after the stop" 1 "$(jq -r 'select(.kind == "step-begin") | .ticket' "$r/ledger.jsonl" | wc -l | tr -d ' ')"
assert_exit "H-086: a stopped run reads as stopped" 0 "$h" state "$r" stopped
assert_eq "H-086: stop-state names the variant" "stop soft:step all" \
  "$("$h" state "$r" stop-state | jq -r '"\(.state) \(.type) \(.tickets)"')"

# ---- soft:task: like soft:step in the engine; its own text asks the session to stop sooner ----
r2=$("$h" run new --workers 5)
"$h" state "$r2" begin --ticket 1 --step s1 >/dev/null
o2=$("$h" state "$r2" stop --type soft:task "owner asked")
assert_eq "H-086: soft:task is recorded with its type" "verb soft:task" "$(ledger_stops "$r2")"
assert_eq "H-086: soft:task lets no new step begin (75)" 75 "$(begin_rc "$r2" 1 s2)"
assert_eq "H-086: soft:task lets no new ticket begin (75)" 75 "$(begin_rc "$r2" 3 s1)"
assert_contains "H-086: soft:task has its own stop text (the current task)" "$o2" "task you are working on"
assert_eq "H-086: soft:task and soft:step texts differ" no \
  "$([ "$(printf '%s\n' "$o2" | grep '^text')" = "$(printf '%s\n' "$out" | grep '^text')" ] && echo yes || echo no)"

# ---- soft:ticket for all tickets: each started ticket runs to its end -----------------------
r3=$("$h" run new --workers 5)
"$h" state "$r3" begin --ticket 1 --step s1 >/dev/null
wl "$r3" t1 --ticket 1 >/dev/null
o3=$("$h" state "$r3" stop --type soft:ticket "finish what runs")
assert_eq "H-086: soft:ticket for all is recorded with scope all" "soft:ticket all" \
  "$(jq -r 'select(.kind == "stop") | "\(.type) \(.tickets)"' "$r3/ledger.jsonl")"
assert_contains "H-086: soft:ticket has its own stop text" "$o3" "ticket"
assert_eq "H-086: soft:ticket lets the next step of a started ticket begin" 0 "$(begin_rc "$r3" 1 s2)"
assert_eq "H-086: soft:ticket launches the worker of that next step" 0 "$(wl_rc "$r3" t2 --ticket 1)"
assert_eq "H-086: the worker of the next step runs" yes "$(alive_rec "$r3" t2)"
assert_eq "D25a: soft:ticket starts no new ticket (75)" 75 "$(begin_rc "$r3" 2 s1)"
assert_eq "D25a: soft:ticket launches no worker for a ticket that never began (75)" 75 "$(wl_rc "$r3" t3 --ticket 2)"
assert_eq "D25a: soft:ticket launches no worker that names no ticket (75)" 75 "$(wl_rc "$r3" t4)"
assert_eq "H-086: a ticket id given as 01 is ticket 1" 0 "$(begin_rc "$r3" 01 s3)"

# ---- soft:ticket per ticket: the named tickets run to their end, the others get soft:step -----
r4=$("$h" run new --workers 5)
"$h" state "$r4" begin --ticket 1 --step s1 >/dev/null
"$h" state "$r4" begin --ticket 3 --step s1 >/dev/null
o4=$("$h" state "$r4" stop --type soft:ticket --ticket 1 "only 1")
assert_eq "H-086: a per-ticket stop records its tickets" "soft:ticket 1" \
  "$(jq -r 'select(.kind == "stop") | "\(.type) \(.tickets)"' "$r4/ledger.jsonl")"
assert_contains "H-086: the per-ticket stop output says the other tickets get soft:step" "$o4" "other tickets"
assert_eq "H-086: the named ticket goes on to its next step" 0 "$(begin_rc "$r4" 1 s2)"
assert_eq "H-086: another started ticket gets soft:step and begins no new step (75)" 75 "$(begin_rc "$r4" 3 s2)"
# The newest stop wins: a later soft:step stops the named ticket too.
"$h" state "$r4" stop >/dev/null
assert_eq "H-086: a later soft:step replaces the per-ticket stop" 75 "$(begin_rc "$r4" 1 s3)"

# ---- an unreadable ledger is never read as "may begin" ---------------------------------------
r5=$("$h" run new --workers 5)
printf 'torn{\n' >> "$r5/ledger.jsonl"
assert_eq "I1: an unreadable ledger line refuses begin (75)" 75 "$(begin_rc "$r5" 1 s1)"
assert_eq "I1: an unreadable ledger line refuses a worker launch (75)" 75 "$(wl_rc "$r5" u1 --ticket 1)"

# ---- the STOP file applies soft:step (D25b), also after a looser verb stop ------------------
r6=$("$h" run new --workers 5)
r7=$("$h" run new --workers 5)
"$h" state "$r7" begin --ticket 1 --step s1 >/dev/null
"$h" state "$r7" stop --type soft:ticket >/dev/null
assert_eq "test setup: under soft:ticket ticket 1 may go on" 0 "$(begin_rc "$r7" 1 s2)"
: > "$proj/.harness/STOP"
assert_eq "D25b: with the STOP file no step begins in an active run (75)" 75 "$(begin_rc "$r6" 1 s1)"
assert_eq "D25b: the STOP file is recorded as soft:step" "file soft:step" "$(ledger_stops "$r6")"
assert_eq "D25b: the STOP file launches no worker (75)" 75 "$(wl_rc "$r6" f1 --ticket 1)"
assert_eq "D25b: a STOP file after a soft:ticket stop applies soft:step (75)" 75 "$(begin_rc "$r7" 1 s3)"
assert_eq "D25b: that STOP file is recorded after the verb stop" "verb soft:ticket,file soft:step" "$(ledger_stops "$r7")"
"$h" state "$r7" stop --type soft:ticket >/dev/null 2>&1 || true
assert_eq "D25b: while the STOP file exists a looser verb stop does not loosen it (75)" 75 "$(begin_rc "$r7" 1 s4)"
"$h" state "$r6" stopped >/dev/null || true
assert_eq "D25b: the STOP file is recorded once per run while it stays" 1 \
  "$(jq -r 'select(.kind == "stop" and .source == "file") | .type' "$r6/ledger.jsonl" | wc -l | tr -d ' ')"
rm -f "$proj/.harness/STOP"
