# The run wiring end to end (issue #110, T11 #44; tasks.md 8.1, 9.1, 17.1, 17.3): one local
# ticket from ready to merged through "run start" and "run tick", with the fake runtime, the
# fake terminal and the fake gh; a soft stop on the way and a resume.
# H-002 H-003 (intake by the ready state), H-064 (every flow step in order), H-055 (independent
# validator), H-046 (merge confirmed through git), H-042 H-043 H-045 (full profile: push, PR,
# merge, ticket done), H-072 (config gate at start), H-085 H-086 (soft stop text to the
# sessions, the next step does not begin), H-088 (resume), H-079 (the run ends when all is
# done), H-081 (a worker closes when its task ends), H-098 (the orchestrator starts the context
# watcher), D23 D24 (handoff prompt), D32 (start resumes an unfinished run).
h="$HO_PLUGIN_ROOT/bin/harness"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
base=$(cd -P "$PWD" && pwd)
git init -q --bare -b main "$base/remote.git"
git clone -q "$base/remote.git" "$base/proj" 2>/dev/null
proj="$base/proj"
user="$base/user"
mkdir -p "$proj/.harness" "$user" "$base/bin"
printf '.harness/\n' >> "$proj/.git/info/exclude"
printf 'base\n' > "$proj/README.txt"
git -C "$proj" add README.txt && git -C "$proj" commit -qm base && git -C "$proj" push -q origin main
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$user" HO_TICKETS_SOURCE=local
export HO_FAKE_GH_DIR="$base/gh" HO_FAKE_GH_REMOTE="$base/remote.git"
mkdir -p "$HO_FAKE_GH_DIR"
export HO_FAKE_TERM_DIR="$base/term" HO_FAKE_CLAUDE_LOG="$base/claude.log" HO_FAKE_CLAUDE_HOLD=exit HO_FAKE_CLAUDE_HOLD_MAX=600 HO_FAKE_CLAUDE_TRANSCRIPT=1
# The readiness judge (claude -p) answers at once; only launched sessions are held open.
real_claude=$(command -v claude)
cat > "$base/bin/claude" <<SH
#!/bin/bash
for a in "\$@"; do [ "\$a" = -p ] && { unset HO_FAKE_CLAUDE_HOLD; export HO_FAKE_CLAUDE_STDOUT='{"ready": true, "questions": []}'; }; done
exec "$real_claude" "\$@"
SH
# No network: the watch script's outage check reads a fake service that is up.
printf '#!/bin/bash\nprintf 200\n' > "$base/bin/curl"
chmod +x "$base/bin/claude" "$base/bin/curl"
export PATH="$base/bin:$PATH"
jq -n --arg p "$proj" '.projects[$p].hasTrustDialogAccepted = true' > "$HOME/.claude.json"

cat > "$proj/.harness/config.json" <<'JSON'
{"schemaVersion": 2,
 "flow": {"use": "mini"}, "requirements": {"format": "none"},
 "autonomy": {"profile": "full"},
 "terminal": {"app": "tmux", "enter_delay_seconds": 0},
 "session": {"boot_timeout_seconds": 30, "close_timeout_seconds": 5, "boot_grace_seconds": 5, "fatal_hold_seconds": 0},
 "watch": {"service_url": "https://service.invalid/", "internet_url": "https://net.invalid/", "cycle_seconds": 1},
 "limits": {"workers": 1}}
JSON
cat > "$user/config.json" <<'JSON'
{"schemaVersion": 2, "runtime": {"main": "claude-code"},
 "delivery": {"wait_seconds": 2, "message_timeout_seconds": 1},
 "gate": {"use": "t", "list": {"t": {"command": "test -f README.txt"}}}}
JSON
# An own two-step flow (plan, execute), copied from basic.
"$h" flow copy basic mini >/dev/null 2>&1 || true
f="$proj/.harness/flows/mini/flow.json"
jq '.steps |= map(select(.id == "plan" or .id == "execute"))' "$f" > "$f.t" && mv "$f.t" "$f"
printf '## Outcome\nA greeting file.\n\n## Scope\ngreeting.txt\n\n## Acceptance criteria\ngreeting.txt says hello.\n' > "$base/body.md"

ledger_n() { jq -c "select(.kind == \"$1\")" "$run/ledger.jsonl" 2>/dev/null | wc -l | tr -d ' '; }
# tick: one pass, run the way production runs it: from inside the orchestrator session.
orch_name() { "$h" session "$run" list 2>/dev/null | awk '$2 == "orchestrator" && $3 != "closed" { print $1; exit }'; }
# The poll interval is the orchestrator's "run wait"; here each tick finds the poll due.
tick() {
  local o
  [ ! -f "$run/intake/poll.json" ] || touch -t 200001010000 "$run/intake/poll.json"
  o=$(orch_name)
  HO_SESSION_NAME=$o HO_SESSION_ID=$(jq -r '.session_id // ""' "$run/sessions/$o.json" 2>/dev/null) HO_SESSION_ROLE=orchestrator \
    "$h" run tick "$run" 2>>"$base/tick.err" || echo "tick-exit $?"
}
rec() { jq -r "$2" "$run/orch/$1.json"; }
sid_of() { jq -r .session_id "$run/sessions/$1.json"; }
ho_test_cleanup() {
  local f p
  for f in "$HO_FAKE_TERM_DIR"/*.pid "$proj"/.harness/runs/*/sessions/*.json "$proj"/.harness/runs/*/watch/watch.pid; do
    [ -f "$f" ] || continue
    case $f in *.json) p=$(jq -r '.pid // empty' "$f" 2>/dev/null || true) ;; *) p=$(awk '{print $1}' "$f") ;; esac
    case $p in '' | *[!0-9]*) continue ;; esac
    kill "$p" 2>/dev/null || true
  done
}
trap ho_test_cleanup EXIT

# ---- start ----------------------------------------------------------------------------------
rc=0; "$h" run start >/dev/null 2>"$base/err" || rc=$?
assert_eq "H-072: run start with nothing confirmed stops at the config gate (exit 73)" 73 "$rc"
assert_eq "H-072: the refused start created no run" 0 "$(ls "$proj/.harness/runs" 2>/dev/null | wc -l | tr -d ' ')"
select_config "$proj"
t=$(cd "$proj" && "$h" tickets add "Add a greeting" "$base/body.md" ready 2>/dev/null | sed -n 's/^OK created ticket \([0-9]*\).*/\1/p')
t2=$(cd "$proj" && "$h" tickets add "Add a farewell" "$base/body.md" ready 2>/dev/null | sed -n 's/^OK created ticket \([0-9]*\).*/\1/p')
# Issue #129 item 2: a profile that merges into the run's integration branch needs a gate; the
# start refuses at once instead of letting every ticket run and block at its merge.
cp "$user/config.json" "$base/user-config.keep"
jq 'del(.gate)' "$base/user-config.keep" > "$user/config.json"
rc=0; "$h" run start >/dev/null 2>"$base/err" || rc=$?
assert_eq "#129 H-046: a merging profile with no gate is refused at run start (exit 78)" 78 "$rc"
assert_contains "#129 H-046: the refusal names the missing gate" "$(cat "$base/err")" "gate.use"
assert_eq "#129 H-046: the refused start created no run" 0 "$(ls "$proj/.harness/runs" 2>/dev/null | wc -l | tr -d ' ')"
mv "$base/user-config.keep" "$user/config.json"
out=$("$h" run start 2>"$base/err") || true
run=$(printf '%s\n' "$out" | sed -n 's/^run //p')
assert_eq "#129: the orchestrator gets the run's user config folder" "export HO_USER_DIR=$user" \
  "$(grep '^export HO_USER_DIR=' "$(jq -r .launcher "$run/sessions/orchestrator.json")" | tr -d "'")"
assert_eq "#110: run start prints the new run" yes "$([ -n "$run" ] && [ -f "$run/run.json" ] && echo yes || echo no)"
assert_eq "D23 D24: the handoff prompt is written with the engine path" yes \
  "$(grep -q "$HO_PLUGIN_ROOT/bin/harness" "$run/handoff.md" 2>/dev/null && ! grep -q '@HARNESS@' "$run/handoff.md" && echo yes || echo no)"
assert_eq "#110: the orchestrator session is launched with the handoff prompt" orchestrator \
  "$(jq -r .role "$run/sessions/orchestrator.json" 2>/dev/null)"
assert_eq "#110: the run has its integration branch" yes "$([ -f "$run/integration.json" ] && echo yes || echo no)"
i=0; while ! "$h" watch "$run" pid-check >/dev/null 2>&1 && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
assert_exit "D32: the watch script runs for the run" 0 "$h" watch "$run" pid-check
rc=0; "$h" run start >"$base/out2" 2>&1 || rc=$?
assert_contains "D32: a second start resumes the unfinished run instead of a new one" "$(cat "$base/out2")" "resume $run"
assert_eq "D32: still one run" 1 "$(ls "$proj/.harness/runs" | wc -l | tr -d ' ')"

# ---- intake and the first step ---------------------------------------------------------------
out=$(tick)
assert_contains "H-098: the first tick starts the context watcher" "$out" "watcher watcher"
assert_contains "H-002: the tick takes the ready ticket" "$out" "start $t"
assert_contains "H-064: the ticket's first flow step starts in a worker session" "$out" "launched $t plan w$t-plan"
assert_eq "H-105: with a worker cap of 1 the second ready ticket is not taken" 0 "$(printf '%s\n' "$out" | grep -c "start $t2" || true)"
assert_eq "H-064: the worker session carries the ticket" "$t" "$(jq -r '.ticket | tostring' "$run/sessions/w$t-plan.json")"
assert_eq "H-086: the step went through the step gate" 1 "$(ledger_n step-begin)"
wt=$(rec "$t" .worktree)
assert_contains "#110: the worker prompt names the step result file" "$(cat "$run/orch/$t/plan.prompt.md")" "$run/orch/$t/plan.result"
assert_eq "#110: the worker works in the ticket's own worktree" "$(rec "$t" .branch)" "$(git -C "$wt" symbolic-ref --short HEAD)"

# ---- a soft stop, then a resume -----------------------------------------------------------
out=$("$h" run stop --type soft:step 2>&1) || true
assert_contains "H-085: run stop records a soft stop" "$out" "soft:step tickets all"
assert_contains "H-085: the stop text goes to the running worker" "$out" "delivered w$t-plan rc"
assert_eq "H-085: the delivery carries the stop id" 1 "$(jq -c --arg n "w$t-plan" 'select(.kind == "deliver-request" and .name == $n) | select((.id // "") | startswith("stop-"))' "$run/ledger.jsonl" | wc -l | tr -d ' ')"
printf 'pass\nplan written\n' > "$run/orch/$t/plan.result"
out=$(tick)
assert_contains "H-086: the current step still finishes under the stop" "$out" "step-done $t plan"
assert_eq "H-081: the finished worker session is closed" closed "$(jq -r .status "$run/sessions/w$t-plan.json")"
out=$(tick)
assert_eq "H-086: the next step does not begin under the stop" 0 "$(printf '%s\n' "$out" | grep -c "launched $t execute" || true)"
assert_contains "H-079 D25a: with no session at work the stopped run ends" "$("$h" run status "$run" 2>&1)" "state: ended"
rc=0; "$h" run start >"$base/out3" 2>&1 || rc=$?
assert_eq "D32: run start does not lift a stop and starts no new run beside it (exit 75)" "75 1" \
  "$rc $(ls "$proj/.harness/runs" | wc -l | tr -d ' ')"
resumes=$(ledger_n resume)
out=$("$h" run resume 2>&1) || true
assert_contains "H-088: run resume opens the stopped run again" "$out" "run $run"
assert_eq "H-088: the resume is recorded" "$((resumes + 1))" "$(ledger_n resume)"
assert_eq "D23: the orchestrator runs again after the resume" yes \
  "$("$h" session "$run" list | awk '$2 == "orchestrator" && $3 != "closed"' | grep -q . && echo yes || echo no)"
out=$(tick)
assert_contains "H-088: after the resume the next step starts" "$out" "launched $t execute w$t-execute"

# ---- execute, finalize, validator, merge, ship ---------------------------------------------
printf 'hello\n' > "$wt/greeting.txt"
git -C "$wt" add greeting.txt && git -C "$wt" commit -qm "add greeting"
printf 'pass\nexecuted\n' > "$run/orch/$t/execute.result"
out=$(tick)
assert_contains "H-064: the last step is done" "$out" "step-done $t execute"
assert_eq "H-105: a ticket between two steps still holds its place under the cap" 0 "$(printf '%s\n' "$out" | grep -c "start $t2" || true)"
assert_eq "H-028: each finished step is recorded on the ticket, so a resume finds it complete" complete \
  "$(cd "$proj" && "$h" tickets resume "$t" --repo "$wt" plan execute 2>&1)"
out=$(tick)
assert_contains "Rebuild: the engine writes the finalize commit and the lane is ready" "$out" "ready $t t$t"
assert_contains "Rebuild: the lane tip is the finalize commit" "$(git -C "$wt" log -1 --format=%s)" "finalize(t$t):"
assert_eq "H-055: the lane's worker is the last worker session" "$(sid_of "w$t-execute")" "$(jq -r .worker_session "$run/lanes/t$t.json")"
out=$(tick)
assert_contains "H-055: an independent validator session starts" "$out" "launched $t validator v$t"
assert_contains "H-055: the validator prompt gives the verdict command for the exact commit" "$(cat "$run/orch/$t/validator.prompt.md")" \
  "loop \"\$HO_RUN_DIR\" verdict t$t --sha $(rec "$t" .sha)"
# The validator does its part from inside its session.
vs=$(sid_of "v$t")
HO_SESSION_NAME=v$t HO_SESSION_ID=$vs "$h" verify "$run" tests "t$t" --total 1 --passed 1 --failed 0 --skipped 0 >/dev/null
printf 'passed\ngreeting.txt says hello\n' > "$run/orch/$t/verdict.md"
HO_SESSION_NAME=v$t HO_SESSION_ID=$vs "$h" loop "$run" verdict "t$t" --sha "$(rec "$t" .sha)" < "$run/orch/$t/verdict.md" >/dev/null
out=$(tick)
assert_contains "H-055: the tick reads the validator's passed verdict" "$out" "verdict $t passed"
out=$(tick)
assert_contains "H-046: the engine-checked merge into the integration branch" "$out" "merged $t t$t"
assert_eq "H-046: the merge is confirmed in the ledger" 1 "$(ledger_n merge-confirmed)"
# Issue #129 item 3: a pass that finds the lane's merge already confirmed (a tick cut off after
# the merge and before its record) moves the ticket on, never to blocked, and merges nothing.
jq '.phase = "merge"' "$run/orch/$t.json" > "$base/o.t" && mv "$base/o.t" "$run/orch/$t.json"
out=$(tick)
assert_contains "#129 H-046: a confirmed merge is not merged again; the ticket moves on" "$out" "merged $t t$t"
assert_eq "#129 H-046: it is recorded once, and no second merge or refusal is" "1 1 0" \
  "$(ledger_n merge-already-confirmed) $(ledger_n merge-confirmed) $(ledger_n merge-refused)"
assert_eq "#129 H-046: the ticket is not blocked" ship "$(rec "$t" .phase)"
out=$(tick)
assert_contains "H-043: the full profile pushes the ticket branch" "$out" "pushed $t"
assert_contains "H-043: and opens the PR" "$out" "pr $t #1"
assert_contains "H-047: with no CI result yet the merge waits" "$out" "wait $t merge"
assert_contains "H-047: and says why" "$out" "CI is not green"
pf="$HO_FAKE_GH_DIR/prs/1.json"
jq '.statusCheckRollup = [{name: "ci", conclusion: "SUCCESS"}]' "$pf" > "$pf.t" && mv "$pf.t" "$pf"
out=$(tick)
assert_contains "H-045: with green CI the full profile merges and the ticket is done" "$out" "end $t done"
assert_eq "H-046: the remote main holds the change" hello "$(git -C "$base/remote.git" show main:greeting.txt 2>/dev/null)"
assert_contains "H-079: with a ticket still ready the run goes on" "$out" "lifecycle work"
assert_eq "H-045: the ticket is done" "$t" "$(cd "$proj" && "$h" tickets ids done)"
assert_eq "H-045: the ledger has the git-confirmed merge and the ticket end" "1 1" "$(ledger_n ship-merge-confirmed) $(ledger_n ship-ticket-done)"
out=$("$h" run status "$run" 2>&1)
assert_contains "#110: run status lists the ticket as done" "$out" "$t done lane t$t"

# ---- the second ticket: a question blocks it, an unblock lets it continue -----------------
out=$(tick)
assert_contains "H-105: the freed place takes the second ticket" "$out" "launched $t2 plan w$t2-plan"
printf 'blocked: which farewell text?\n' > "$run/orch/$t2/plan.result"
out=$(tick)
assert_contains "H-032: a step that needs an answer blocks the ticket with the question" "$out" "blocked $t2 step plan"
assert_eq "H-032: the ticket is blocked" "$t2" "$(cd "$proj" && "$h" tickets ids blocked)"
assert_eq "H-032: the question is the worker's, not the orchestrator's" "w$t2-plan" \
  "$(jq -r --arg t "$t2" 'select(.kind == "question" and (.ticket | tostring) == $t) | .session' "$run/ledger.jsonl" | tail -n 1)"
out=$(tick)
assert_contains "H-082: with only a blocked ticket left the run waits" "$out" "lifecycle wait-blocked"
assert_eq "H-082: the orchestrator stays while the run waits" yes "$([ -n "$(orch_name)" ] && echo yes || echo no)"
(cd "$proj" && "$h" tickets unblock "$t2" >/dev/null 2>&1)
out=$(tick)
assert_contains "H-031 H-028: after an unblock the ticket is taken again" "$out" "start $t2"
assert_contains "H-028: it continues at the step with no result" "$out" "launched $t2 plan"
# The rest of the second ticket, the way sessions would do it.
wt2=$(rec "$t2" .worktree)
for i in $(seq 1 14); do
  for s2 in plan execute; do
    if [ -s "$run/orch/$t2/$s2.prompt.md" ] && [ ! -f "$run/orch/$t2/$s2.result" ]; then
      [ "$s2" = plan ] || { printf 'bye\n' > "$wt2/farewell.txt"; git -C "$wt2" add farewell.txt; git -C "$wt2" commit -qm "add farewell"; }
      printf 'pass\n' > "$run/orch/$t2/$s2.result"
    fi
  done
  v=$(rec "$t2" '.validator // ""')
  if [ -n "$v" ] && [ ! -f "$run/verdicts/t$t2/$(rec "$t2" .sha).json" ]; then
    vsid=$(sid_of "$v")
    HO_SESSION_NAME=$v HO_SESSION_ID=$vsid "$h" verify "$run" tests "t$t2" --total 1 --passed 1 --failed 0 --skipped 0 >/dev/null
    printf 'passed\nok\n' | HO_SESSION_NAME=$v HO_SESSION_ID=$vsid "$h" loop "$run" verdict "t$t2" --sha "$(rec "$t2" .sha)" >/dev/null
  fi
  pf="$HO_FAKE_GH_DIR/prs/2.json"
  [ ! -f "$pf" ] || { jq '.statusCheckRollup = [{name: "ci", conclusion: "SUCCESS"}]' "$pf" > "$pf.t" && mv "$pf.t" "$pf"; }
  out=$(tick)
  case $out in *"lifecycle end"*) break ;; esac
done
assert_contains "H-079: in the tick where the last ticket is done, the run ends" "$out" "lifecycle end"
assert_eq "H-045: both tickets are done" "$t $t2" "$(cd "$proj" && "$h" tickets ids done | tr '\n' ' ' | sed 's/ $//')"
assert_eq "H-079: the run end is recorded" "all-done" "$(jq -r 'select(.kind == "run-end") | .reason' "$run/ledger.jsonl" | tail -n 1)"
i=0; while [ -n "$(orch_name)" ] && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
assert_eq "D37-LIFECYCLE-3: at the end the orchestrator and the watcher close (the orchestrator after its turn)" "" \
  "$("$h" session "$run" list | awk '($2 == "orchestrator" || $2 == "watcher") && $3 != "closed" { print $1 }')"
assert_eq "#110: a tick after the end says ended" ended "$(tick)"
rc=0; "$h" run resume "$run" >/dev/null 2>&1 || rc=$?
assert_eq "H-079: a run that ended with all done is not resumed" 75 "$rc"
