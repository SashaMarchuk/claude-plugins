# The worker cap holds on every launch path (H-105, D26a). A worker slot is freed only by a
# proven end: every recorded process of the session is gone, or a close is recorded. The age of
# a record is never evidence. Each case below ages records by hours, which would free a slot
# under any age rule, and then counts live worker processes by their own PIDs.
# shellcheck source=sessions-setup.sh
. "$HO_TESTS_DIR/sessions-setup.sh"
cp "$user/config.json" "$base/user.orig.json"
age() { touch -t "$(date -v-1H '+%Y%m%d%H%M' 2>/dev/null || date -d '-1 hour' '+%Y%m%d%H%M')" "$@"; }
acct() {
  jq --arg c "$1" '.accounts = {roles: {default: "acc"}, list: {acc: {env_command: $c}}}' "$base/user.orig.json" > "$user/config.json"
}
wl() { local r=$1 n=$2; shift 2; "$h" session "$r" launch --role worker --name "$n" --cwd "$proj/src" --prompt "$base/prompt.md" "$@"; }
# pid_of <run> <name>: the session PID its launcher reported (kept for cleanup), or nothing.
pid_of() { local p; p=$(cut -d' ' -f1 "$1/sessions/$2.pid" 2>/dev/null || true); [ -z "$p" ] || echo "$p" >> "$base/extra.pids"; printf '%s\n' "$p"; }
# live_workers <run> <names...>: how many of these sessions have a live process (own count).
live_workers() {
  local r=$1 n p c=0
  shift
  for n in "$@"; do
    p=$(pid_of "$r" "$n")
    [ -n "$p" ] && alive "$p" && c=$((c + 1))
  done
  printf '%s\n' "$c"
}
sleep_marks "$base/marks"
# wait_file <file> [tenths]: wait until the file exists.
wait_file() { local i=0; while [ ! -e "$1" ] && [ "$i" -lt "${2:-300}" ]; do sleep 0.1; i=$((i + 1)); done; [ -e "$1" ]; }

# ---- launches that wait with --slot-wait, with records older than any window ----
r=$("$h" run new --workers 1)
wl "$r" w1 >/dev/null
p1=$(pid_of "$r" w1)
# Each launch marks its slot wait (the sleep after a failed try), so the records are aged only
# once all three really wait (issue #109). The two that lose wait out their --slot-wait.
for n in a b c; do
  (c=0; PATH="$base/marks:$PATH" T_SLEEP_MARK="$base/wait-$n" wl "$r" "$n" --slot-wait 20 >/dev/null 2>&1 || c=$?; echo "$c" > "$base/rc-$n") &
done
for n in a b c; do wait_mark "$base/wait-$n" 0.5 || bad "test setup: launch $n does not wait for a slot" ""; done
age "$r"/sessions/a.json "$r"/sessions/b.json "$r"/sessions/c.json
assert_eq "H-105: a launch waiting for a slot reads as starting at any age, never dead" "starting starting starting" \
  "$(for n in a b c; do "$h" session "$r" status "$n" | jq -r .liveness; done | tr '\n' ' ' | sed 's/ $//')"
kill "$p1"
wait_gone "$p1" || bad "test setup: w1 did not end" "$p1"
for n in a b c; do wait_file "$base/rc-$n" 600 || bad "test setup: launch $n did not return" ""; done
assert_eq "H-105: old waiting launches: cap 1 never shows two worker processes" 1 "$(live_workers "$r" a b c)"
assert_eq "H-105: old waiting launches: one launched, two reported no free slot" "0 73 73" \
  "$(cat "$base/rc-a" "$base/rc-b" "$base/rc-c" | sort -n | tr '\n' ' ' | sed 's/ $//')"
assert_eq "H-105: old waiting launches: one worker slot is held" 1 "$(ls "$r/slots/worker" | wc -l | tr -d ' ')"

# ---- a slow account command during the launch, record older than any window ----
r=$("$h" run new --workers 1)
# The account command runs in the launch command's check (fast) and in the launcher, after the
# slot take; the launcher's run blocks until the test removes the hold file. The launch command
# meanwhile waits in its boot check.
acct '[ -z "${HO_SESSION_NAME:-}" ] || while [ -e "'"$base"'/hold" ]; do sleep 0.1; done; echo FOO=bar'
: > "$base/hold"
(c=0; wl "$r" s1 > "$base/s1.out" 2>&1 || c=$?; echo "$c" > "$base/rc-s1") &
wait_file "$r/sessions/s1.launcher" || bad "test setup: the s1 launcher did not record itself" ""
age "$r/sessions/s1.json"
assert_eq "H-105: a launch busy in its account command reads as starting at any age" starting \
  "$("$h" session "$r" status s1 | jq -r .liveness)"
assert_exit "H-105: slow account command: its slot is not freed, so the next worker waits" 73 wl "$r" s2
assert_exit "H-105: a launch whose launch command still runs cannot be closed, however old its record" 65 "$h" session "$r" close s1
rm -f "$base/hold"
wait_file "$base/rc-s1" 300 || bad "test setup: s1 did not return" ""
assert_eq "H-105: the slow launch still starts its session" 0 "$(cat "$base/rc-s1")"
assert_eq "H-105: slow account command: cap 1 never shows two worker processes" 1 "$(live_workers "$r" s1 s2)"
cp "$base/user.orig.json" "$user/config.json"

# ---- the launch command is killed while its launcher is still in the account command ----
r=$("$h" run new --workers 1)
# The launcher's account command waits while the hold file exists, so the kill always lands
# before any session starts, however slow the machine is (issue #109).
acct '[ -z "${HO_SESSION_NAME:-}" ] || while [ -e "'"$base"'/hold-k1" ]; do sleep 0.1; done; echo FOO=bar'
: > "$base/hold-k1"
wl "$r" k1 >/dev/null 2>&1 &
wrap=$!
i=0; while [ "$(jq -r '.handle // ""' "$r/sessions/k1.json" 2>/dev/null)" = "" ] && [ $i -lt 600 ]; do sleep 0.05; i=$((i + 1)); done
# The launch command itself, by the PID it recorded ($! is only the shell around it).
lp=$(jq -r .launch_pid "$r/sessions/k1.json")
assert_eq "test setup: the recorded launch PID is the running launch command" yes \
  "$(ps -o command= -p "$lp" 2>/dev/null | grep -q -- ' launch ' && echo yes || echo no)"
kill -9 "$lp" 2>/dev/null || true; wait "$wrap" 2>/dev/null || true
wait_gone "$lp" || bad "test setup: the launch command did not end" "$lp"
cp "$base/user.orig.json" "$user/config.json"
age "$r/sessions/k1.json"
assert_eq "test setup: the launch command is gone and no session runs yet" "launching no" \
  "$(jq -r .status "$r/sessions/k1.json") $([ -f "$r/sessions/k1.pid" ] && echo yes || echo no)"
assert_eq "H-105: a launcher that is still starting keeps the record starting at any age" starting \
  "$("$h" session "$r" status k1 | jq -r .liveness)"
assert_exit "H-105: killed launch: its slot is not freed, so the next worker waits" 73 wl "$r" k2
rm -f "$base/hold-k1"
wait_file "$r/sessions/k1.pid" 300 || bad "test setup: the k1 launcher did not start its session" ""
i=0; while [ "$("$h" session "$r" status k1 | jq -r .liveness)" != working ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
assert_eq "H-105: killed launch: cap 1 never shows two worker processes" 1 "$(live_workers "$r" k1 k2)"
kp=$(pid_of "$r" k1)
assert_contains "H-105: once its launch command is gone, close ends the session of a launching record" \
  "$("$h" session "$r" close k1 2>&1)" "closed"
assert_eq "H-105: the closed session's process is gone" no "$(alive "$kp" && echo yes || echo no)"
assert_exit "H-105: then the slot is free" 0 wl "$r" k2

# ---- freeing the slot of a dead launch stops a launcher that has not started yet ----
r=$("$h" run new --workers 1)
bash -c 'exit 0' & dp=$!; wait "$dp" || true
mkdir -p "$r/sessions" "$r/slots/worker"
jq -n --arg run "$(basename "$r")" --arg p "$dp" '{schemaVersion: 2, run: $run, name: "d1", role: "worker", session_id: null,
  pid: null, status: "launching", launch_pid: ($p | tonumber), launch_start: "Thu Jan  1 00:00:00 1970"}' > "$r/sessions/d1.json"
jq -n --arg run "$(basename "$r")" '{run: $run, kind: "worker", holder: "d1", op: null, since: "x"}' > "$r/slots/worker/d1.json"
assert_eq "H-090: a launching record whose launch and launcher are both gone reads dead" dead "$("$h" session "$r" status d1 | jq -r .liveness)"
assert_exit "H-105: its slot is freed for the next worker" 0 wl "$r" d2
assert_eq "H-105: the freed launch is told not to start (close flag written before the slot is freed)" yes \
  "$([ -f "$r/sessions/d1.closing" ] && echo yes || echo no)"

# ---- a record with no recorded launch process is never proof of an end ----
r=$("$h" run new --workers 1)
mkdir -p "$r/sessions" "$r/slots/worker"
jq -n --arg run "$(basename "$r")" '{schemaVersion: 2, run: $run, name: "o1", role: "worker", session_id: null, pid: null, status: "launching"}' > "$r/sessions/o1.json"
jq -n --arg run "$(basename "$r")" '{run: $run, kind: "worker", holder: "o1", op: null, since: "x"}' > "$r/slots/worker/o1.json"
age "$r/sessions/o1.json"
assert_eq "H-090: an old launching record with no launch process recorded reads unknown, never dead" unknown \
  "$("$h" session "$r" status o1 | jq -r .liveness)"
assert_exit "H-105: its slot is kept" 73 wl "$r" o2
cp "$base/user.orig.json" "$user/config.json"

# ---- review round 1 (PR #99) ----
mkdir -p "$base/noproc" "$base/selfps"
printf '#!/bin/sh\nexit 1\n' > "$base/noproc/ps"
chmod +x "$base/noproc/ps"
# selfps: a process view that holds only the caller's own process and its parents, as in a
# sandbox. The caller sees itself, so a probe of its own PID passes.
cat > "$base/selfps/ps" <<'PS'
#!/bin/sh
for t in "$@"; do :; done
a=$$
while [ -n "$a" ] && [ "$a" != 0 ] && [ "$a" != 1 ]; do
  [ "$a" = "$t" ] && exec /bin/ps "$@"
  a=$(/bin/ps -o ppid= -p "$a" 2>/dev/null | tr -d ' ')
done
exit 1
PS
chmod +x "$base/selfps/ps"

# Close with no readable process table changes nothing.
r=$("$h" run new --workers 1)
wl "$r" n1 >/dev/null
np=$(pid_of "$r" n1)
rc=0; PATH="$base/noproc:$PATH" "$h" session "$r" close n1 >/dev/null 2>&1 || rc=$?
assert_eq "H-105: close with no readable process table refuses: non-zero exit, record running, slot held, process alive" \
  "refused running held alive" \
  "$([ "$rc" -ne 0 ] && echo refused || echo "rc=0") $(jq -r .status "$r/sessions/n1.json") $([ -f "$r/slots/worker/n1.json" ] && echo held || echo freed) $(alive "$np" && echo alive || echo gone)"
assert_exit "H-105: after that close the next worker still waits" 73 wl "$r" n2
assert_eq "H-105: close with no readable process table: cap 1 never shows two worker processes" 1 "$(live_workers "$r" n1 n2)"

# A process view that sees the caller but not the session is no proof of an end.
r=$("$h" run new --workers 1)
wl "$r" v1 >/dev/null
vp=$(pid_of "$r" v1)
assert_eq "H-090: a view that cannot see the session reads unknown, never dead" unknown \
  "$(PATH="$base/selfps:$PATH" "$h" session "$r" status v1 | jq -r .liveness)"
assert_eq "H-090: that status poll leaves the record running and writes no death" "running 0" \
  "$(jq -r .status "$r/sessions/v1.json") $(grep -c '"session-dead"' "$r/ledger.jsonl" || true)"
assert_exit "H-105: a launch under that view finds no free slot" 73 env PATH="$base/selfps:$PATH" "$h" session "$r" launch \
  --role worker --name v2 --cwd "$proj/src" --prompt "$base/prompt.md"
assert_eq "H-105: narrow process view: cap 1 never shows two worker processes" 1 "$(live_workers "$r" v1 v2)"
rc=0; PATH="$base/selfps:$PATH" "$h" session "$r" close v1 >/dev/null 2>&1 || rc=$?
assert_eq "H-105: close under that view does not mark the live worker closed" "running held" \
  "$(jq -r .status "$r/sessions/v1.json") $([ -f "$r/slots/worker/v1.json" ] && echo held || echo freed)"

# A stop recorded while a launch waits for a slot ends the wait; no worker starts.
r=$("$h" run new --workers 1)
wl "$r" t1 >/dev/null
tp=$(pid_of "$r" t1)
(c=0; wl "$r" t2 --slot-wait 20 >/dev/null 2>&1 || c=$?; echo "$c" > "$base/rc-t2") &
wait_file "$r/sessions/t2.json" || bad "test setup: t2 has no record" ""
"$h" state "$r" stop "test stop" >/dev/null
kill "$tp"; wait_gone "$tp" || bad "test setup: t1 did not end" "$tp"
wait_file "$base/rc-t2" 250 || bad "test setup: t2 did not return" ""
assert_eq "H-105: a stop during the slot wait ends the launch with exit 75 and starts nothing" "75 no" \
  "$(cat "$base/rc-t2") $([ -f "$r/sessions/t2.pid" ] && echo yes || echo no)"
assert_eq "H-105: the waiting launch holds no slot after the stop" no "$([ -f "$r/slots/worker/t2.json" ] && echo yes || echo no)"

# A slot whose holder reads unknown has an owner's way out, at a terminal only.
r=$("$h" run new --workers 1)
mkdir -p "$r/sessions" "$r/slots/worker"
jq -n --arg run "$(basename "$r")" '{schemaVersion: 2, run: $run, name: "u1", role: "worker", session_id: null, pid: null, status: "launching"}' > "$r/sessions/u1.json"
jq -n --arg run "$(basename "$r")" '{run: $run, kind: "worker", holder: "u1", op: null, since: "x"}' > "$r/slots/worker/u1.json"
# notty <cmd...>: run the command in a new session, with no terminal at all.
notty() { perl -e 'use POSIX; POSIX::setsid(); exec @ARGV or exit 127' "$@"; }
assert_exit "H-105: a forced worker release with no terminal is refused" 65 notty "$h" slot "$r" release worker --holder u1 --force
# answer <text> <cmd...>: run the command on a terminal (script); once it has printed anything (its
# prompt, or a refusal), type the text until it is done (issue #109: no fixed typing window).
# The exit is the command's own: the typing loop ends by a broken pipe once the command is done.
answer() {
  local a=$1 st scr i=0
  shift
  scr=$(mktemp "$base/answer.XXXXXX")
  { while [ ! -s "$scr" ] && [ $i -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
    for _ in $(seq 1 60); do printf '%s\n' "$a" || break; sleep 0.5; done; } 2>/dev/null \
    | script -q /dev/null "$@" > "$scr" 2>&1 && st=0 || st=${PIPESTATUS[1]}
  return "$st"
}
rc=0; answer nope "$h" slot "$r" release worker --holder u1 --force || rc=$?
assert_eq "H-105: a wrong answer at the terminal releases nothing" "65 held" "$rc $([ -f "$r/slots/worker/u1.json" ] && echo held || echo freed)"
rc=0; answer u1 "$h" slot "$r" release worker --holder u1 --force || rc=$?
assert_eq "H-105: the owner releases the slot of a holder that reads unknown, with a ledger line" "0 freed 1" \
  "$rc $([ -f "$r/slots/worker/u1.json" ] && echo held || echo freed) $(grep -c '"slot-force-released"' "$r/ledger.jsonl" || true)"
assert_eq "H-105: the forced release tells the launch not to start" yes "$([ -f "$r/sessions/u1.closing" ] && echo yes || echo no)"
wl "$r" u2 >/dev/null
rc=0; answer u2 "$h" slot "$r" release worker --holder u2 --force || rc=$?
assert_eq "H-105: a working worker's slot cannot be force-released" "65 held" "$rc $([ -f "$r/slots/worker/u2.json" ] && echo held || echo freed)"

# ---- review round 2 (PR #99) ----
# An end file next to a live worker decides nothing while the session process may still run.
r=$("$h" run new --workers 1)
wl "$r" e1 >/dev/null
ep=$(pid_of "$r" e1)
: > "$r/sessions/e1.ended"
rc=0; PATH="$base/selfps:$PATH" "$h" session "$r" launch --role worker --name e2 --cwd "$proj/src" --prompt "$base/prompt.md" >/dev/null 2>&1 || rc=$?
assert_eq "H-105: a forged end file under a narrow view frees no slot: the next launch gets 73, one worker runs" "73 1" \
  "$rc $(live_workers "$r" e1 e2)"
assert_eq "H-090: a narrow view with an end file next to a live worker reads unknown, never dead" unknown \
  "$(PATH="$base/selfps:$PATH" "$h" session "$r" status e1 | jq -r .liveness)"
rm -f "$r/sessions/e1.ended"
# A real end under the same narrow view still reads dead: the kernel says no such process.
kill "$ep"; wait_gone "$ep" || bad "test setup: e1 did not end" "$ep"
i=0; while [ "$(PATH="$base/selfps:$PATH" "$h" session "$r" status e1 | jq -r .liveness)" != dead ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
assert_eq "H-090: a worker that really ended reads dead under a narrow view too" dead \
  "$(PATH="$base/selfps:$PATH" "$h" session "$r" status e1 | jq -r .liveness)"

# A heavy-slot wait for a session closed during the wait takes nothing (Codex review of PR #99).
r=$("$h" run new --workers 3)
wl "$r" q1 >/dev/null
wl "$r" q2 >/dev/null
assert_exit "test setup: q1 takes the heavy slot" 0 "$h" slot "$r" acquire heavy --holder q1 --op image-build
(c=0; PATH="$base/marks:$PATH" T_SLEEP_MARK="$base/wait-q2" "$h" slot "$r" acquire heavy --holder q2 --op app-build --wait 60 >/dev/null 2>&1 || c=$?; echo "$c" > "$base/rc-q2") &
wait_mark "$base/wait-q2" 0.5 || bad "test setup: q2 does not wait for the heavy slot" ""
assert_contains "test setup: q2 is closed while it waits" "$("$h" session "$r" close q2 2>&1)" "closed"
"$h" slot "$r" release heavy --holder q1 >/dev/null
wait_file "$base/rc-q2" 600 || bad "test setup: the q2 acquire did not return" ""
assert_eq "H-107: a wait for a session closed meanwhile ends non-zero and records no slot for it" "nonzero none" \
  "$([ "$(cat "$base/rc-q2")" -ne 0 ] && echo nonzero || echo zero) $([ -f "$r/slots/heavy/q2.json" ] && echo held || echo none)"

# The forced release reads the holder again after the answer: a holder that came alive is kept.
r=$("$h" run new --workers 1)
mkdir -p "$r/sessions" "$r/slots/worker"
jq -n --arg run "$(basename "$r")" '{schemaVersion: 2, run: $run, name: "f1", role: "worker", session_id: null, pid: null, status: "launching"}' > "$r/sessions/f1.json"
jq -n --arg run "$(basename "$r")" '{run: $run, kind: "worker", holder: "f1", op: null, since: "x"}' > "$r/slots/worker/f1.json"
fo=$( (sleep 3000 > /dev/null 2>&1 & echo $!) ); echo "$fo" >> "$base/extra.pids"
fs=$(LC_ALL=C TZ=UTC ps -o lstart= -p "$fo" | sed 's/^ *//; s/ *$//')
: > "$base/f1.screen"
# Once the prompt shows, the record gains a live launch command, then the name is typed.
{ i=0; while ! grep -q 'Type the session name' "$base/f1.screen" 2>/dev/null && [ $i -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
  jq --argjson p "$fo" --arg s "$fs" '.launch_pid = $p | .launch_start = $s' "$r/sessions/f1.json" > "$base/f1.json" && mv "$base/f1.json" "$r/sessions/f1.json"
  for _ in $(seq 1 60); do printf 'f1\n' || break; sleep 0.5; done; } 2>/dev/null \
  | script -q /dev/null "$h" slot "$r" release worker --holder f1 --force > "$base/f1.screen" 2>&1 && rc=0 || rc=${PIPESTATUS[1]}
assert_eq "H-105: a holder that reads starting after the answer keeps its slot, and no close flag is left" "65 held no" \
  "$rc $([ -f "$r/slots/worker/f1.json" ] && echo held || echo freed) $([ -f "$r/sessions/f1.closing" ] && echo yes || echo no)"
kill "$fo" 2>/dev/null || true

# The usage of slot acquire names every exit of a wait.
assert_contains "H-105: the slot usage names exit 75 for a stopped run" "$("$h" slot 2>&1 || true)" "75"

# A process table that cuts long command lines (procps at the terminal width) needs -ww.
mkdir -p "$base/cutps"
cat > "$base/cutps/ps" <<'PS'
#!/bin/sh
case " $* " in *" -ww "*) exec /bin/ps "$@" ;; esac
case "$*" in *command=*) /bin/ps "$@" | cut -c1-30; exit 0 ;; esac
exec /bin/ps "$@"
PS
chmod +x "$base/cutps/ps"
r=$("$h" run new --workers 1)
wl "$r" c1 >/dev/null
assert_eq "H-090: a long command line is read whole, so a live worker reads working" working \
  "$(PATH="$base/cutps:$PATH" "$h" session "$r" status c1 | jq -r .liveness)"
assert_exit "H-105: and its slot is kept" 73 env PATH="$base/cutps:$PATH" "$h" session "$r" launch --role worker --name c2 --cwd "$proj/src" --prompt "$base/prompt.md"

# ---- review round 3 (PR #99), narrowed by H-086 and D25a ----
# A stop gates every slot kind, on a no-wait acquire and during a wait. The test holds the slot
# lock while it records the stop and frees the slot, so the waiter's next try sees both at once.
# A soft stop lets a session that already runs finish its step, so its heavy and stage waits get
# the slot; an unknown stop state refuses every kind.
r=$("$h" run new --workers 3)
wl "$r" s1 >/dev/null
wl "$r" s2 >/dev/null
assert_exit "test setup: s1 takes the heavy slot" 0 "$h" slot "$r" acquire heavy --holder s1 --op image-build
assert_exit "test setup: s1 takes the stage slot" 0 "$h" slot "$r" acquire stage:browser --holder s1
(c=0; PATH="$base/marks:$PATH" T_SLEEP_MARK="$base/wait-sh" "$h" slot "$r" acquire heavy --holder s2 --op app-build --wait 60 >/dev/null 2>&1 || c=$?; echo "$c" > "$base/rc-sh") &
(c=0; PATH="$base/marks:$PATH" T_SLEEP_MARK="$base/wait-ss" "$h" slot "$r" acquire stage:browser --holder s2 --wait 60 >/dev/null 2>&1 || c=$?; echo "$c" > "$base/rc-ss") &
wait_mark "$base/wait-sh" 0.5 || bad "test setup: the heavy acquire does not wait" ""
wait_mark "$base/wait-ss" 0.5 || bad "test setup: the stage acquire does not wait" ""
i=0; until mkdir "$r/slots/.lock" 2>/dev/null; do sleep 0.05; i=$((i + 1)); [ $i -lt 200 ] || break; done
"$h" state "$r" stop "test stop" >/dev/null
"$h" slot "$r" release heavy --holder s1 >/dev/null
"$h" slot "$r" release stage:browser --holder s1 >/dev/null
rm -rf "$r/slots/.lock"
wait_file "$base/rc-sh" 600 || bad "test setup: the heavy wait did not return" ""
wait_file "$base/rc-ss" 600 || bad "test setup: the stage wait did not return" ""
assert_eq "D25a: a soft stop during a heavy wait of a running session gives it the slot" "0 held" \
  "$(cat "$base/rc-sh") $([ -f "$r/slots/heavy/s2.json" ] && echo held || echo none)"
assert_eq "D25a: a soft stop during a stage wait of a running session gives it the slot" "0 held" \
  "$(cat "$base/rc-ss") $([ -f "$r/slots/stage-browser/s2.json" ] && echo held || echo none)"
assert_exit "H-105: a soft stop still launches no new worker (75)" 75 wl "$r" s3
"$h" slot "$r" release heavy --holder s2 >/dev/null
"$h" slot "$r" release stage:browser --holder s2 >/dev/null
printf 'torn{\n' >> "$r/ledger.jsonl"
assert_exit "H-107: a heavy acquire with an unknown stop state gives 75" 75 "$h" slot "$r" acquire heavy --holder s2 --op app-build
assert_exit "H-107: a stage acquire with an unknown stop state gives 75" 75 "$h" slot "$r" acquire stage:lint --holder s2
assert_eq "H-107: an unknown stop state records no heavy or stage slot" 0 "$(ls "$r/slots/heavy" "$r/slots/stage-lint" 2>/dev/null | grep -c json || true)"

# The transcript folder is the one the session itself uses: an account command that builds it
# from $PWD runs in the session's folder, and only once for the launch command's own check.
cp "$base/user.orig.json" "$base/user.r3.json"
jq --arg c '[ -n "${HO_SESSION_NAME:-}" ] || echo x >> "'"$base"'/acct-runs"; echo CLAUDE_CONFIG_DIR=$PWD/account-config' \
  '.accounts = {roles: {default: "acc"}, list: {acc: {env_command: $c}}}' "$base/user.r3.json" > "$user/config.json"
r=$("$h" run new --workers 3)
: > "$base/acct-runs"
HO_FAKE_CLAUDE_TRANSCRIPT=1 wl "$r" p1 >/dev/null
assert_eq "H-090: the recorded transcript folder is the session's own (\$PWD is the session's folder)" "$proj/src/account-config" "$(jq -r .transcript_root "$r/sessions/p1.json")"
assert_eq "H-090: that session's transcript is found" present "$("$h" session "$r" status p1 | jq -r .transcript_state)"
assert_eq "H-090: the launch command runs the account command once (its check), not again for the transcript" 1 "$(wc -l < "$base/acct-runs" | tr -d ' ')"
# The split between liveness and delivery (PR #95): liveness reads this folder inside the
# project, but delivery refuses a transcript folder inside the project or a worktree, because a
# record or a note there could be planted. Its proof finds no transcript and sends nothing.
rc=0; o=$("$h" session "$r" proof p1 ho-split0001 2>&1) || rc=$?
assert_eq "H-090, H-101: delivery refuses a transcript folder inside the project that liveness reads (exit 1)" "1" "$rc"
assert_contains "H-101: the refusal says no transcript was found for delivery" "$o" "no transcript of session p1"
cp "$base/user.r3.json" "$user/config.json"
