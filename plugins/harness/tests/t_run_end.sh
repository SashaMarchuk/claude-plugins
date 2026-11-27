# H-079 (a run ends when all tickets are done; standby off by default), H-080 (opt-in standby:
# finished terminals close, the orchestrator watches the tracker, no extra watcher), H-081
# (worker sessions close when their task ends; only what this run started is closed), H-082
# (only review tickets left: workers stop, the orchestrator and the watcher wait), design S8-20a
# (only human-blocked tickets left: on_only_human_blocked, default wait, no nudges),
# D37-LIFECYCLE-3 (the orchestrator and the watcher are exempt until the run ends), S8-27
# (close by exact process). OPEN-9: standby is a config setting with a run flag override.
. "$HO_TESTS_DIR/sessions-setup.sh"
export HO_TICKETS_SOURCE=local

body() { printf '## Outcome\nx\n## Scope\nx\n## Acceptance criteria\nx\n' > "$base/body.md"; echo "$base/body.md"; }
# tk <dir> <state>: add one ticket in that state to a ticket folder.
tk() { HO_TICKETS_DIR=$1 "$h" tickets add "t-$2" "$(body)" "$2" >/dev/null; }
# sess <run> <role> <name>: launch one session of that role.
sess() { "$h" session "$1" launch --role "$2" --name "$3" --cwd "$proj/src" --prompt "$base/prompt.md" >/dev/null; }
pid() { jq -r '.pid // empty' "$1/sessions/$2.json"; }
# up <pid>...: "yes" per live process, "no" per gone one (each waited for up to 5 s if gone).
gone() { wait_gone "$1" && echo gone || echo alive; }
up() { alive "$1" && echo alive || echo gone; }
check() { "$h" lifecycle "$1" check 2>"$base/check.err"; }
# The whole output is read before its first line is taken: a reader that leaves early would
# end the sweep with a broken pipe.
decision() { local o; o=$(check "$1"); printf '%s\n' "$o" | head -n 1; }
nfiles() { find "$1/sessions" "$1/launchers" -type f 2>/dev/null | wc -l | tr -d ' '; }

# A session of another run stays open through every check below (H-081).
other=$("$h" run new --workers 5)
sess "$other" worker x1
px=$(pid "$other" x1)

# ---- settings: standby is off by default, a config setting with a run flag override (OPEN-9) ----
r=$("$h" run new --workers 5)
assert_eq "H-079: standby is off by default" "false default" "$(jq -r '"\(.standby) \(.standby_source)"' "$r/lifecycle.json")"
assert_eq "S8-20a: on_only_human_blocked is wait by default" "wait" "$(jq -r .on_only_human_blocked "$r/lifecycle.json")"
assert_eq "OPEN-9: the standby choice is recorded in the run ledger" "false default" \
  "$(jq -r 'select(.kind == "run-settings") | "\(.standby) \(.standby_source)"' "$r/ledger.jsonl")"
cp "$proj/.harness/config.json" "$base/config.orig.json"
jq '.run = {standby: true}' "$base/config.orig.json" > "$proj/.harness/config.json"
rc1=$("$h" run new --workers 5)
assert_eq "H-079: the owner switches standby on in the configuration" "true config" "$(jq -r '"\(.standby) \(.standby_source)"' "$rc1/lifecycle.json")"
rf=$("$h" run new --workers 5 --standby off)
assert_eq "OPEN-9: the run flag beats the config" "false flag" "$(jq -r '"\(.standby) \(.standby_source)"' "$rf/lifecycle.json")"
n_runs=$(ls "$proj/.harness/runs" | wc -l | tr -d ' ')
jq '.run = {standby: "yes"}' "$base/config.orig.json" > "$proj/.harness/config.json"
assert_exit "OPEN-9: a standby value that is not true or false is a config error (78)" 78 "$h" run new
jq '.run = {on_only_human_blocked: "nudge"}' "$base/config.orig.json" > "$proj/.harness/config.json"
assert_exit "S8-20a: an unknown on_only_human_blocked value is a config error (78)" 78 "$h" run new
cp "$base/config.orig.json" "$proj/.harness/config.json"
assert_exit "OPEN-9: a bad --standby value is a usage error (64)" 64 "$h" run new --standby maybe
assert_eq "OPEN-9: a refused run new leaves no run folder" "$n_runs" "$(ls "$proj/.harness/runs" | wc -l | tr -d ' ')"

# ---- H-081: a worker closes when its task ends; the orchestrator and the watcher stay ---------
export HO_TICKETS_DIR="$base/tk-a"
tk "$HO_TICKETS_DIR" in-progress
sess "$r" orchestrator orch
sess "$r" watcher watch
sess "$r" worker w1
po=$(pid "$r" orch) pw=$(pid "$r" watch) p1=$(pid "$r" w1)
assert_exit "H-081: done closes the worker whose task ended" 0 "$h" lifecycle "$r" done w1
assert_eq "H-081: the worker's own process has ended" gone "$(gone "$p1")"
assert_eq "H-081: the task end is in the ledger" "w1" "$(jq -r 'select(.kind == "session-task-ended") | .name' "$r/ledger.jsonl")"
assert_eq "H-081: while the run goes on the orchestrator and the watcher stay open" "alive alive" "$(up "$po") $(up "$pw")"
assert_exit "D37-LIFECYCLE-3: done refuses the orchestrator (65)" 65 "$h" lifecycle "$r" done orch
assert_exit "D37-LIFECYCLE-3: done refuses the watcher (65)" 65 "$h" lifecycle "$r" done watch
assert_exit "H-081: done refuses a session this run did not start (66)" 66 "$h" lifecycle "$r" done x1
assert_eq "D37-LIFECYCLE-3: the orchestrator and the watcher are still open" "alive alive" "$(up "$po") $(up "$pw")"
assert_eq "H-081: tickets in progress mean work" "work" "$(decision "$r")"

# ---- H-082: only review tickets left: workers stop, the orchestrator and the watcher wait ------
r2=$("$h" run new --workers 5)
export HO_TICKETS_DIR="$base/tk-b"
tk "$HO_TICKETS_DIR" needs-review
tk "$HO_TICKETS_DIR" done
sess "$r2" orchestrator orch
sess "$r2" watcher watch
sess "$r2" worker w1
sess "$r2" validator v1
sess "$r2" question q1
po=$(pid "$r2" orch) pw=$(pid "$r2" watch) p1=$(pid "$r2" w1) pv=$(pid "$r2" v1) pq=$(pid "$r2" q1)
ho=$(rec orch .handle "$r2") hw=$(rec watch .handle "$r2")
: > "$HO_FAKE_TERM_DIR/calls.log"
assert_eq "H-082: with every remaining ticket on review the run waits" "wait-review" "$(decision "$r2")"
assert_eq "H-082: the worker, validator and question sessions stop" "gone gone gone" "$(gone "$p1") $(gone "$pv") $(gone "$pq")"
assert_eq "H-082: the orchestrator and the watcher keep running" "alive alive" "$(up "$po") $(up "$pw")"
assert_eq "S8-20a: the wait sends nothing to the orchestrator or the watcher" "" \
  "$(grep -F -e " $ho " -e " $hw " "$HO_FAKE_TERM_DIR/calls.log" || true)"
assert_eq "H-082: the run has not ended" "" "$(jq -r 'select(.kind == "run-end") | .kind' "$r2/ledger.jsonl")"
tk "$HO_TICKETS_DIR" ready
assert_eq "H-082: a ticket that can go on again means work" "work" "$(decision "$r2")"
assert_eq "H-082: going back to work closes nothing" "alive alive" "$(up "$po") $(up "$pw")"

# ---- S8-20a: only human-blocked tickets left, standby off: wait by default, with no nudges ------
r3=$("$h" run new --workers 5)
export HO_TICKETS_DIR="$base/tk-c"
tk "$HO_TICKETS_DIR" blocked
tk "$HO_TICKETS_DIR" done
sess "$r3" orchestrator orch
sess "$r3" worker w1
po=$(pid "$r3" orch) p1=$(pid "$r3" w1) ho=$(rec orch .handle "$r3")
: > "$HO_FAKE_TERM_DIR/calls.log"
assert_eq "S8-20a: only blocked tickets left means wait" "wait-blocked" "$(decision "$r3")"
assert_eq "S8-20a: the worker stops" gone "$(gone "$p1")"
assert_eq "S8-20a: the orchestrator waits" alive "$(up "$po")"
assert_eq "S8-20a: no nudge goes to the orchestrator" "" "$(grep -F " $ho " "$HO_FAKE_TERM_DIR/calls.log" || true)"
jq '.run = {on_only_human_blocked: "end"}' "$base/config.orig.json" > "$proj/.harness/config.json"
r4=$("$h" run new --workers 5)
cp "$base/config.orig.json" "$proj/.harness/config.json"
assert_eq "S8-20a: with on_only_human_blocked end the run ends" "end" "$(decision "$r4")"

# ---- H-079: all tickets done, standby off: the run ends, every session of this run closes -------
r5=$("$h" run new --workers 5)
export HO_TICKETS_DIR="$base/tk-d"
tk "$HO_TICKETS_DIR" done
sess "$r5" orchestrator orch
sess "$r5" watcher watch
sess "$r5" worker w1
po=$(pid "$r5" orch) pw=$(pid "$r5" watch) p1=$(pid "$r5" w1)
osid=$(rec orch .session_id "$r5")
# The orchestrator itself asks: it cannot wait for its own close, so it is left for last and
# named in the output.
out=$(HO_SESSION_NAME=orch HO_SESSION_ID=$osid "$h" lifecycle "$r5" check)
assert_eq "H-079: all tickets done with standby off ends the run" "end" "$(printf '%s\n' "$out" | head -n 1)"
assert_eq "H-079: the run end is in the ledger with its reason" "all-done" "$(jq -r 'select(.kind == "run-end") | .reason' "$r5/ledger.jsonl")"
assert_eq "D37-LIFECYCLE-3: at run end the worker and the watcher close" "gone gone" "$(gone "$p1") $(gone "$pw")"
assert_eq "D37-LIFECYCLE-3: the calling orchestrator is left to end its own session" alive "$(up "$po")"
assert_contains "D37-LIFECYCLE-3: the output names the calling session" "$out" "self orch"
assert_eq "H-079: an ended run stays ended" "ended" "$(decision "$r5")"
assert_exit "H-079: an outside caller closes the orchestrator at run end" 0 "$h" session "$r5" close orch
assert_eq "H-079: the orchestrator's process has ended" gone "$(gone "$po")"
r6=$("$h" run new --workers 5)
sess "$r6" orchestrator orch
p6=$(pid "$r6" orch)
assert_eq "H-079: a check from outside the run's sessions ends the run" "end" "$(decision "$r6")"
assert_eq "D37-LIFECYCLE-3: then the orchestrator closes too" gone "$(gone "$p6")"

# ---- H-079: a close that fails at the run end is tried again by the next check ---------------
r5b=$("$h" run new --workers 5)
sess "$r5b" worker w1
sess "$r5b" worker w2
p1=$(pid "$r5b" w1) p2=$(pid "$r5b" w2)
cp "$r5b/sessions/w2.json" "$base/w2.json"
jq 'del(.term_tag)' "$base/w2.json" > "$r5b/sessions/w2.json"
out=$(check "$r5b")
assert_eq "H-079: the run ends" "end" "$(printf '%s\n' "$out" | head -n 1)"
assert_contains "H-079: a session that could not be closed is named as left open" "$out" "left-open w2"
assert_eq "H-079: the other worker closed" gone "$(gone "$p1")"
assert_eq "test setup: w2 is still running" alive "$(up "$p2")"
cp "$base/w2.json" "$r5b/sessions/w2.json"
assert_eq "H-079: the next check still reads ended" "ended" "$(decision "$r5b")"
assert_eq "H-079: and it closes the session left open at the run end" gone "$(gone "$p2")"

# ---- D37-LIFECYCLE-3: a worker that calls check at run end is named once ----------------------
r5c=$("$h" run new --workers 5)
sess "$r5c" worker w1
wsid=$(rec w1 .session_id "$r5c")
out=$(HO_SESSION_NAME=w1 HO_SESSION_ID=$wsid "$h" lifecycle "$r5c" check)
assert_eq "D37-LIFECYCLE-3: the calling worker is named once" 1 "$(printf '%s\n' "$out" | grep -c '^self w1')"
HO_SESSION_NAME=w1 HO_SESSION_ID=$wsid "$h" lifecycle "$r5c" check >/dev/null
assert_eq "D37-LIFECYCLE-3: its self line is written to the ledger once" 1 \
  "$(jq -r 'select(.kind == "session-close-self-skipped") | .name' "$r5c/ledger.jsonl" | wc -l | tr -d ' ')"
"$h" session "$r5c" close w1 >/dev/null 2>&1 || true

# ---- H-080: standby on: finished terminals close, the orchestrator keeps watching -------------
r7=$("$h" run new --workers 5 --standby on)
sess "$r7" orchestrator orch
sess "$r7" watcher watch
sess "$r7" worker w1
sess "$r7" validator v1
po=$(pid "$r7" orch) pw=$(pid "$r7" watch) p1=$(pid "$r7" w1) pv=$(pid "$r7" v1)
# The orchestrator may read only the first line; the sweep still closes every finished session.
assert_eq "H-080: all tickets done with standby on enters standby" "standby" "$(check "$r7" | head -n 1)"
assert_eq "H-080: the finished worker terminals close" "gone gone" "$(gone "$p1") $(gone "$pv")"
assert_eq "H-080: the orchestrator and the watcher keep running" "alive alive" "$(up "$po") $(up "$pw")"
assert_eq "H-080: standby does not end the run" "" "$(jq -r 'select(.kind == "run-end") | .kind' "$r7/ledger.jsonl")"
before=$(nfiles "$r7")
assert_eq "H-080: a second check stays in standby" "standby" "$(decision "$r7")"
assert_eq "H-080: standby starts no extra terminal or session" "$before" "$(nfiles "$r7")"
tk "$HO_TICKETS_DIR" ready
assert_eq "H-080: a new ready ticket in standby means work" "work" "$(decision "$r7")"
assert_eq "H-080: the orchestrator is still running" alive "$(up "$po")"

# ---- a soft stop ends the run once its allowed work is done (D37-LIFECYCLE-3, D25) -------------
r8=$("$h" run new --workers 5)
export HO_TICKETS_DIR="$base/tk-e"
tk "$HO_TICKETS_DIR" in-progress
sess "$r8" orchestrator orch
sess "$r8" worker w1
po=$(pid "$r8" orch) p1=$(pid "$r8" w1)
"$h" state "$r8" stop >/dev/null
assert_eq "D25a: a stopped run with a running worker is stopping" "stopping" "$(decision "$r8")"
assert_eq "D25a: stopping closes nothing" "alive alive" "$(up "$po") $(up "$p1")"
"$h" lifecycle "$r8" done w1 >/dev/null
assert_eq "D37-LIFECYCLE-3: once nothing the stop allows runs, the run ends" "end" "$(decision "$r8")"
assert_eq "D37-LIFECYCLE-3: the run end names the stop" "stop" "$(jq -r 'select(.kind == "run-end") | .reason' "$r8/ledger.jsonl")"
assert_eq "D37-LIFECYCLE-3: the orchestrator closes at that run end" gone "$(gone "$po")"

# ---- a ticket list that cannot be read is never "all done" ---------------------------------------
r9=$("$h" run new --workers 5)
sess "$r9" worker w1
p9=$(pid "$r9" w1)
rc=0; HO_TICKETS_SOURCE=nowhere "$h" lifecycle "$r9" check >/dev/null 2>&1 || rc=$?
assert_eq "I3: an unreadable ticket list gives unknown (exit 2)" 2 "$rc"
ends=$(jq -r 'select(.kind == "run-end") | .kind' "$r9/ledger.jsonl")
assert_eq "I3: unknown closes nothing and ends nothing" "alive none" "$(up "$p9") ${ends:-none}"

# ---- a missing ticket folder is never "all done" ------------------------------------------------
r10=$("$h" run new --workers 5)
sess "$r10" orchestrator orch
p10=$(pid "$r10" orch)
rc=0; HO_TICKETS_DIR="$base/no-such-folder" "$h" lifecycle "$r10" check >/dev/null 2>&1 || rc=$?
assert_eq "I3: a missing ticket folder gives unknown (exit 2)" 2 "$rc"
assert_eq "I3: and closes nothing" alive "$(up "$p10")"

# ---- H-081: a record of another run inside this run's folder is never closed ------------------
cp "$other/sessions/x1.json" "$r10/sessions/x1.json"
"$h" lifecycle "$r10" done x1 >/dev/null 2>&1 || true
HO_TICKETS_DIR="$base/tk-d" "$h" lifecycle "$r10" check >/dev/null 2>&1 || true
assert_eq "H-081: a copied record of another run is left alone by done and by the run-end sweep" alive "$(up "$px")"
rm -f "$r10/sessions/x1.json"

# ---- H-081: no check closed the session of the other run ---------------------------------------
assert_eq "H-081: the session of another run is never closed" alive "$(up "$px")"
assert_eq "H-081: its record is untouched" running "$(rec x1 .status "$other")"

# ---- D2, H-079: a ticket in no known state is never "all done" ---------------------------------
# The queue lists it, but not under one of the five states, so the run cannot tell whether it is
# done: the decision is unknown (exit 2), as for a queue that cannot be read.
r11=$("$h" run new --workers 5)
sess "$r11" worker w1
p11=$(pid "$r11" w1)
tk "$base/tk-f" done
tk "$base/tk-f" done
f11=$(ls "$base/tk-f"/2-*.md)
sed 's/^status: done$/status: paused/' "$f11" > "$base/t11.md" && cat "$base/t11.md" > "$f11"
rc=0; HO_TICKETS_DIR="$base/tk-f" "$h" lifecycle "$r11" check >/dev/null 2>&1 || rc=$?
assert_eq "D2: a local ticket whose state is none of the five gives unknown (exit 2)" 2 "$rc"
ends=$(jq -r 'select(.kind == "run-end") | .kind' "$r11/ledger.jsonl")
assert_eq "D2: that unknown closes nothing and ends nothing" "alive none" "$(up "$p11") ${ends:-none}"
sed 's/^status: paused$/status: done/' "$f11" > "$base/t11.md" && cat "$base/t11.md" > "$f11"
assert_eq "H-079: once that ticket reads done the same queue ends the run" "end" "$(HO_TICKETS_DIR="$base/tk-f" decision "$r11")"

# GitHub: an open issue with a harness label but no state label is a ticket in no known state.
# An issue with no harness label at all is not a harness ticket and does not hold the run.
export HO_FAKE_GH_DIR="$base/gh"
gh_check() { HO_TICKETS_SOURCE=github HO_TICKETS_REPO=fake/repo "$h" lifecycle "$1" check 2>"$base/check.err"; }
r12=$("$h" run new --workers 5)
HO_TICKETS_SOURCE=github HO_TICKETS_REPO=fake/repo "$h" tickets add "t-done" "$(body)" done >/dev/null
gh issue create --repo fake/repo --title "not a harness ticket" --body-file "$(body)" >/dev/null
gh issue create --repo fake/repo --title "urgent, no state" --body-file "$(body)" --label harness:urgent >/dev/null
rc=0; gh_check "$r12" >/dev/null || rc=$?
assert_eq "D2: an open issue with a harness label but no state label gives unknown (exit 2)" 2 "$rc"
ends=$(jq -r 'select(.kind == "run-end") | .kind' "$r12/ledger.jsonl")
assert_eq "D2: that unknown ends nothing" "none" "${ends:-none}"
gh issue edit 3 --repo fake/repo --add-label harness:done >/dev/null
o=$(gh_check "$r12" || true)
assert_eq "H-079: once it carries a state label the run ends; an unlabelled issue does not hold it" "end" "$(printf '%s\n' "$o" | head -n 1)"

# ---- H-079: an ended run launches nothing new; a recorded resume opens it again ----------------
r13=$("$h" run new --workers 5)
assert_eq "test setup: the run ends" "end" "$(HO_TICKETS_DIR="$base/tk-f" decision "$r13")"
assert_exit "H-079: an ended run refuses a new session launch (75)" 75 sess "$r13" worker late1
assert_exit "H-079: an ended run refuses a session resume too (75)" 75 \
  "$h" session "$r13" launch --role worker --name late2 --cwd "$proj/src" --resume 0b6f2a8e-1c3d-4e5f-8a9b-0c1d2e3f4a5b
assert_eq "H-079: the refused launches leave no record" "" "$(ls "$r13/sessions" 2>/dev/null | grep -E '^late' || true)"
"$h" state "$r13" resume >/dev/null
assert_exit "H-079: after a recorded resume the run launches again" 0 sess "$r13" worker late3

# ---- H-079: checks that run at the same time write one run end ----------------------------------
r14=$("$h" run new --workers 5)
for i in 1 2 3 4 5 6 7 8; do HO_TICKETS_DIR="$base/tk-f" "$h" lifecycle "$r14" check >/dev/null 2>&1 & done
wait
assert_eq "H-079: eight checks at the same time write exactly one run-end line" 1 \
  "$(jq -r 'select(.kind == "run-end") | .kind' "$r14/ledger.jsonl" | wc -l | tr -d ' ')"
