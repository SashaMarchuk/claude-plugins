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
# wait_file <file> [tenths]: wait until the file exists.
wait_file() { local i=0; while [ ! -e "$1" ] && [ "$i" -lt "${2:-300}" ]; do sleep 0.1; i=$((i + 1)); done; [ -e "$1" ]; }

# ---- launches that wait with --slot-wait, with records older than any window ----
r=$("$h" run new --workers 1)
wl "$r" w1 >/dev/null
p1=$(pid_of "$r" w1)
for n in a b c; do
  (c=0; wl "$r" "$n" --slot-wait 12 >/dev/null 2>&1 || c=$?; echo "$c" > "$base/rc-$n") &
done
for n in a b c; do wait_file "$r/sessions/$n.json" || bad "test setup: $n has no record" ""; done
sleep 0.5
age "$r"/sessions/a.json "$r"/sessions/b.json "$r"/sessions/c.json
assert_eq "H-105: a launch waiting for a slot reads as starting at any age, never dead" "starting starting starting" \
  "$(for n in a b c; do "$h" session "$r" status "$n" | jq -r .liveness; done | tr '\n' ' ' | sed 's/ $//')"
kill "$p1"
wait_gone "$p1" || bad "test setup: w1 did not end" "$p1"
for n in a b c; do wait_file "$base/rc-$n" 200 || bad "test setup: launch $n did not return" ""; done
assert_eq "H-105: old waiting launches: cap 1 never shows two worker processes" 1 "$(live_workers "$r" a b c)"
assert_eq "H-105: old waiting launches: one launched, two reported no free slot" "0 73 73" \
  "$(cat "$base/rc-a" "$base/rc-b" "$base/rc-c" | sort -n | tr '\n' ' ' | sed 's/ $//')"
assert_eq "H-105: old waiting launches: one worker slot is held" 1 "$(ls "$r/slots/worker" | wc -l | tr -d ' ')"

# ---- a slow account command inside the launch command, record older than any window ----
r=$("$h" run new --workers 1)
# The launch command runs the account command twice: once in its checks, once after the slot
# take. Only the second run of s1 blocks, until the test removes the hold file.
acct '[ -n "${HO_SESSION_NAME:-}" ] || { n=$(cat "'"$base"'/acct.n" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "'"$base"'/acct.n"; [ "$n" != 2 ] || while [ -e "'"$base"'/hold" ]; do sleep 0.1; done; }; echo FOO=bar'
: > "$base/hold"
(c=0; wl "$r" s1 > "$base/s1.out" 2>&1 || c=$?; echo "$c" > "$base/rc-s1") &
wait_file "$r/slots/worker/s1.json" || bad "test setup: s1 took no slot" ""
i=0; while [ "$(cat "$base/acct.n" 2>/dev/null)" != 2 ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
age "$r/sessions/s1.json"
assert_eq "H-105: a launch busy in its account command reads as starting at any age" starting \
  "$("$h" session "$r" status s1 | jq -r .liveness)"
assert_exit "H-105: slow account command: its slot is not freed, so the next worker waits" 73 wl "$r" s2
assert_exit "H-105: a launch whose launch command still runs cannot be closed, however old its record" 65 "$h" session "$r" close s1
rm -f "$base/hold"
wait_file "$base/rc-s1" 300 || bad "test setup: s1 did not return" ""
assert_eq "H-105: the slow launch still starts its session" 0 "$(cat "$base/rc-s1")"
assert_eq "H-105: slow account command: cap 1 never shows two worker processes" 1 "$(live_workers "$r" s1 s2)"

# ---- the launch command is killed while its launcher is still in the account command ----
r=$("$h" run new --workers 1)
acct '[ -n "${HO_SESSION_NAME:-}" ] && sleep 4; echo FOO=bar'
wl "$r" k1 >/dev/null 2>&1 &
lp=$!
i=0; while [ "$(jq -r '.handle // ""' "$r/sessions/k1.json" 2>/dev/null)" = "" ] && [ $i -lt 300 ]; do sleep 0.05; i=$((i + 1)); done
kill -9 "$lp" 2>/dev/null || true; wait "$lp" 2>/dev/null || true
cp "$base/user.orig.json" "$user/config.json"
age "$r/sessions/k1.json"
assert_eq "test setup: the launch command is gone and no session runs yet" "launching no" \
  "$(jq -r .status "$r/sessions/k1.json") $([ -f "$r/sessions/k1.pid" ] && echo yes || echo no)"
assert_eq "H-105: a launcher that is still starting keeps the record starting at any age" starting \
  "$("$h" session "$r" status k1 | jq -r .liveness)"
assert_exit "H-105: killed launch: its slot is not freed, so the next worker waits" 73 wl "$r" k2
wait_file "$r/sessions/k1.pid" 100 || bad "test setup: the k1 launcher did not start its session" ""
sleep 0.5
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
