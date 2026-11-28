# Recovery: the fixed order for a dead session, attempts, the wait for a limit reset and the
# reboot case (H-088, H-091, H-092, H-093, H-094, H-114; design D14, D20, D21, D28c, D32,
# D37-LIFECYCLE-1, D37-LIFECYCLE-2, D37-SESSIONS-1, D42h).
# shellcheck source=sessions-setup.sh
. "$HO_TESTS_DIR/sessions-setup.sh"
export HO_TICKETS_DIR="$proj/.harness/tickets" HO_FAKE_CLAUDE_TRANSCRIPT=1
pcfg="$proj/.harness/config.json"
jq '.recovery = {waits_seconds: [0, 0, 0], late_hours: 0}' "$pcfg" > "$base/c.json" && mv "$base/c.json" "$pcfg"
printf '## Outcome\nWork.\n## Scope\nAll.\n## Acceptance criteria\nDone.\n' > "$base/body.md"
# ticket <title>: a claimed (in-progress) ticket; prints its id.
ticket() { local id; id=$("$h" tickets add "$1" "$base/body.md" | sed -n "s/.*created ticket \([0-9]*\).*/\1/p"); "$h" tickets claim "$id" > /dev/null; printf '%s\n' "$id"; }
# work <run> <name> <ticket>: a worker session of the ticket in the run.
work() { "$h" session "$1" launch --role worker --name "$2" --cwd "$proj/src" --prompt "$base/prompt.md" --ticket "$3" > /dev/null; }
# die <run> <name>: the session's process ends (stopped by its exact PID), then reads dead.
die() {
  local p i=0
  p=$(jq -r .pid "$1/sessions/$2.json")
  kill "$p" 2>/dev/null || true
  wait_gone "$p" || true
  while [ "$("$h" session "$1" status "$2" | jq -r .liveness)" != dead ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
}
events() { jq -c "select(.kind == \"$2\")" "$1/ledger.jsonl" | wc -l | tr -d ' '; }
args_of() { grep -F -- "$(jq -r .session_id "$1/sessions/$2.json")" "$HO_FAKE_CLAUDE_LOG" | head -n 1; }

# ---- H-092 / D14: resume by ID once, then a new session with the context pack ----
r=$("$h" run new)
t=$(ticket "Recover me")
work "$r" w1 "$t"
sid1=$(jq -r .session_id "$r/sessions/w1.json")
die "$r" w1
out=$("$h" recover "$r" tick)
assert_contains "H-092: a dead session is first resumed by its ID" "$out" "attempt 1 resume"
assert_contains "H-092: the resume runs the runtime's resume by the old session ID" "$(grep -F -- "--resume	$sid1" "$HO_FAKE_CLAUDE_LOG" | head -n 1)" "--resume	$sid1"
assert_eq "H-092: the resumed session is recorded under the ticket" "$t" "$(jq -r .ticket "$r/sessions/w1-r1.json")"
die "$r" w1-r1
out=$("$h" recover "$r" tick)
assert_contains "H-092: after the one resume a new session starts" "$out" "attempt 2 new"
pack="$r/recovery/$t.pack.md"
assert_contains "D14: the context pack holds the ticket text" "$(cat "$pack")" "Recover me"
assert_contains "D14: the context pack names the old session ID" "$(cat "$pack")" "$(jq -r .session_id "$r/sessions/w1-r1.json")"
assert_contains "D14: the context pack names the worktree" "$(cat "$pack")" "Worktree: $proj/src"
case $(args_of "$r" w1-r2) in *--resume*) bad "D14: the new session is not a resume" "it resumed" ;; *) ok "D14: the new session is not a resume" ;; esac
assert_eq "D20: every attempt has one ledger line" 2 "$(events "$r" recover-attempt)"
out=$("$h" recover "$r" tick)
assert_eq "D20: a working session is left alone" 2 "$(events "$r" recover-attempt)"

# ---- H-093 / D20: a human-stop signal prevents the restart ----
r=$("$h" run new)
t=$(ticket "Stopped by a person")
work "$r" w2 "$t"
die "$r" w2
: > "$proj/.harness/STOP"
out=$("$h" recover "$r" tick)
rm -f "$proj/.harness/STOP"
assert_contains "H-093: a STOP file leaves the ticket stopped" "$out" "left stopped (stop)"
assert_eq "H-093: with a STOP file nothing is restarted" 0 "$(events "$r" recover-attempt)"
r=$("$h" run new)
t=$(ticket "Label changed by hand")
work "$r" w3 "$t"
die "$r" w3
"$h" tickets release "$t" > /dev/null
out=$("$h" recover "$r" tick)
assert_contains "H-093: a ticket label changed by hand leaves the ticket stopped" "$out" "left stopped (ticket state ready)"
assert_eq "H-093: after a hand-changed label nothing is restarted" 0 "$(events "$r" recover-attempt)"

# ---- H-094 / D21: attempts run out -> blocked with one comment ----
jq '.recovery = {attempts: 1, waits_seconds: [0], late_hours: 0}' "$pcfg" > "$base/c.json" && mv "$base/c.json" "$pcfg"
r=$("$h" run new)
t=$(ticket "Keeps dying")
work "$r" w4 "$t"
die "$r" w4
"$h" recover "$r" tick > /dev/null
die "$r" w4-r1
out=$("$h" recover "$r" tick)
assert_contains "H-094: when the attempts run out the ticket is blocked" "$out" "ticket $t blocked"
assert_eq "H-094: the ticket is in blocked" "$t" "$("$h" tickets ids blocked | grep -x "$t")"
"$h" recover "$r" tick > /dev/null
assert_eq "H-094: the block wrote one comment" 1 "$("$h" tickets show "$t" | grep -c 'Recovery attempts ran out')"
assert_eq "D37-SESSIONS-1: with the late attempt off, nothing more is tried" 1 "$(events "$r" recover-attempt)"
jq '.recovery = {waits_seconds: [3600]}' "$pcfg" > "$base/c.json" && mv "$base/c.json" "$pcfg"
r=$("$h" run new)
t=$(ticket "Waits first")
work "$r" w5 "$t"
die "$r" w5
out=$("$h" recover "$r" tick)
assert_contains "D21: the configured wait comes before the first attempt" "$out" "waits before attempt 1"
jq '.recovery = {waits_seconds: [0, 0, 0], late_hours: 0}' "$pcfg" > "$base/c.json" && mv "$base/c.json" "$pcfg"

# ---- D37-LIMITS-4 / D21: a launch refused for now is not an attempt; the ticket waits ----
jq '.recovery = {attempts: 1, waits_seconds: [0], late_hours: 0}' "$pcfg" > "$base/c.json" && mv "$base/c.json" "$pcfg"
r=$("$h" run new --workers 1)
ta=$(ticket "Waits for a slot")
tb=$(ticket "Holds the slot")
work "$r" wa "$ta"
die "$r" wa
"$h" slot "$r" list > /dev/null
work "$r" wb "$tb"
out=$("$h" recover "$r" tick)
assert_contains "D37-LIMITS-4: with no free slot the restart waits" "$out" "ticket $ta waits: the launch was refused for now (rc 73)"
assert_eq "D37-LIMITS-4: the refused launch counts no attempt" 0 "$(jq -r .attempts "$r/recovery/$ta.json")"
"$h" session "$r" close wb > /dev/null 2>&1
out=$("$h" recover "$r" tick)
assert_contains "D37-LIMITS-4: when the slot is free the stopped task restarts" "$out" "ticket $ta: attempt 1 resume rc 0"
assert_eq "D37-LIMITS-4: the waiting ticket was not blocked" "" "$("$h" tickets ids blocked | grep -x "$ta" || true)"

# ---- D20: a run-level stop is not sticky ----
jq '.recovery = {waits_seconds: [0, 0, 0], late_hours: 0}' "$pcfg" > "$base/c.json" && mv "$base/c.json" "$pcfg"
r=$("$h" run new)
t=$(ticket "Stop then resume")
work "$r" ws "$t"
die "$r" ws
"$h" state "$r" stop "pause for a moment" > /dev/null
"$h" recover "$r" tick > /dev/null
"$h" recover "$r" tick > /dev/null
assert_eq "D20: a stop leaves the ticket, with one ledger line" 1 "$(events "$r" recover-left)"
"$h" state "$r" resume > /dev/null
out=$("$h" recover "$r" tick)
assert_contains "D20: after a resume of the run the ticket is recovered" "$out" "attempt 1"

# ---- D37-SESSIONS-1: the late attempt ----
jq '.recovery = {attempts: 1, waits_seconds: [0], late_hours: 12}' "$pcfg" > "$base/c.json" && mv "$base/c.json" "$pcfg"
r=$("$h" run new)
t=$(ticket "Late attempt")
work "$r" wl "$t"
die "$r" wl
"$h" recover "$r" tick > /dev/null
die "$r" wl-r1
"$h" recover "$r" tick > /dev/null
assert_eq "D37-SESSIONS-1: the late attempt is due 12 hours after the block" 43200 "$(jq -r '.late_due - .clock' "$r/recovery/$t.json")"
out=$("$h" recover "$r" tick)
assert_eq "D37-SESSIONS-1: before it is due nothing more is tried" 1 "$(events "$r" recover-attempt)"
jq -c '.clock = .late_due' "$r/recovery/$t.json" > "$base/s.json" && mv "$base/s.json" "$r/recovery/$t.json"
out=$("$h" recover "$r" tick)
assert_contains "D37-SESSIONS-1: when due, one late attempt with a new session" "$out" "late attempt for ticket $t"
assert_eq "D37-SESSIONS-1: the late attempt is a new session with the context pack" new "$(jq -r 'select(.kind == "recover-attempt") | .how' "$r/ledger.jsonl" | tail -n 1)"
latest=$(jq -r 'select(.kind == "recover-attempt") | .name' "$r/ledger.jsonl" | tail -n 1)
die "$r" "$latest"
"$h" recover "$r" tick > /dev/null
"$h" recover "$r" tick > /dev/null
assert_eq "D37-SESSIONS-1: a failed late attempt writes one ledger line" 1 "$(events "$r" recover-late-failed)"
assert_eq "D37-SESSIONS-1: and no second comment" 1 "$("$h" tickets show "$t" | grep -c 'Recovery attempts ran out')"
jq '.recovery = {waits_seconds: [0, 0, 0], late_hours: 0}' "$pcfg" > "$base/c.json" && mv "$base/c.json" "$pcfg"

# ---- H-114 / D28c: a hit limit waits for the reset and continues; a STOP ends the wait ----
jq '.limits.wait_slice_seconds = 1 | .limits.resume_margin_seconds = 0' "$pcfg" > "$base/c.json" && mv "$base/c.json" "$pcfg"
r=$("$h" run new)
start=$(date +%s)
rc=0; "$h" limits "$r" wait acct-a --until $((start + 2)) > "$base/wait.out" || rc=$?
assert_eq "H-114: the wait ends at the reset time and the run continues (exit 0)" 0 "$rc"
assert_eq "H-114: the wait lasted until the reset time" yes "$([ $(( $(date +%s) - start )) -ge 2 ] && echo yes || echo no)"
assert_eq "PR-5: one wait is one begin line and one end line" "1 1" "$(events "$r" wait-begin) $(events "$r" wait-end)"
assert_contains "H-114: the wait ends on the reset" "$(jq -c 'select(.kind == "wait-end")' "$r/ledger.jsonl")" '"result":"reset"'
( sleep 1; : > "$proj/.harness/STOP" ) &
rc=0; "$h" limits "$r" wait acct-a --until $(( $(date +%s) + 600 )) > /dev/null || rc=$?
wait
rm -f "$proj/.harness/STOP"
assert_eq "D28c: a STOP during the wait ends it (exit 75)" 75 "$rc"
# D21: the attempt clock stops while a wait is open.
"$h" state "$r" resume > /dev/null
t=$(ticket "Clock stops")
work "$r" w6 "$t"
"$h" recover "$r" tick > /dev/null
jq -c '.last_tick -= 100' "$r/recovery/$t.json" > "$base/s.json" && mv "$base/s.json" "$r/recovery/$t.json"
printf '{"ts":"x","run":"%s","kind":"wait-begin","reason":"outage"}\n' "$(basename "$r")" >> "$r/ledger.jsonl"
"$h" recover "$r" tick > /dev/null
assert_eq "D21: the attempt clock does not run during an open wait" 0 "$(jq -r .clock "$r/recovery/$t.json")"
printf '{"ts":"x","run":"%s","kind":"wait-begin","reason":"limit"}\n{"ts":"x","run":"%s","kind":"wait-end","reason":"outage"}\n' "$(basename "$r")" "$(basename "$r")" >> "$r/ledger.jsonl"
printf '{"ts":"x","run":"%s","kind":"wait-begin","reason":"outage"}\n{"ts":"x","run":"%s","kind":"wait-end","reason":"outage"}\n' "$(basename "$r")" "$(basename "$r")" >> "$r/ledger.jsonl"
jq -c '.last_tick -= 100' "$r/recovery/$t.json" > "$base/s.json" && mv "$base/s.json" "$r/recovery/$t.json"
"$h" recover "$r" tick > /dev/null
assert_eq "D21: an outage that ends inside a limit wait does not start the clock" 0 "$(jq -r .clock "$r/recovery/$t.json")"

# ---- H-088 / D32 / D37-LIFECYCLE-2: after a reboot nothing starts by itself ----
assert_eq "D32: the plugin installs nothing that starts it at login" "" "$(grep -rIlE 'launchctl|LaunchAgents|crontab|systemctl' "$HO_PLUGIN_ROOT/lib" "$HO_PLUGIN_ROOT/bin" "$HO_PLUGIN_ROOT/hooks" || true)"
r=$("$h" run new)
t=$(ticket "After reboot")
work "$r" w7 "$t"
work "$r" w8 "$t"
sid7=$(jq -r .session_id "$r/sessions/w7.json")
die "$r" w7
assert_eq "D37-LIFECYCLE-2: the next start finds the last unfinished run" "$r" "$(cd "$proj" && "$h" recover last)"
jq '.recovery.ask_first = true' "$pcfg" > "$base/c.json" && mv "$base/c.json" "$pcfg"
assert_exit "H-088: with ask-first on, reopen asks and starts nothing" 77 "$h" recover "$r" reopen
assert_eq "H-088: the ask started nothing" 0 "$(events "$r" reopen)"
out=$("$h" recover "$r" reopen --yes)
assert_contains "D42h: a session whose process is gone is resumed by its recorded ID" "$out" "reopen w7 session $sid7 rc 0"
assert_eq "D42h: a live session is left alone" 0 "$(printf '%s\n' "$out" | grep -c 'reopen w8')"
out=$("$h" recover "$r" reopen --yes)
assert_eq "D42h: a reopened session is not reopened twice" "nothing to reopen" "$out"
