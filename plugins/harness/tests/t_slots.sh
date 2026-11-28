# Worker cap, heavy-work slot and stage limits, enforced by the engine (H-104, H-105, H-107,
# design D26, D26a).
# shellcheck source=sessions-setup.sh
. "$HO_TESTS_DIR/sessions-setup.sh"
cfg="$proj/.harness/config.json"
cp "$cfg" "$base/config.orig.json"
setcfg() { jq "$1" "$base/config.orig.json" > "$cfg"; }
limit() { "$h" slot "$1" limits | jq -r "$2"; }
# wl <run> <name> [args]: launch a worker in another run.
wl() { local r=$1 n=$2; shift 2; "$h" session "$r" launch --role worker --name "$n" --cwd "$proj/src" --prompt "$base/prompt.md" "$@"; }
# holder <run> <name> [owner-pid]: a session record that is still launching; its launch process
# is the given one, by default a process that lives for the whole test (a live holder).
# bg_proc: start a long sleep outside this shell's jobs (a bare "wait" below must not wait for
# it) and print its PID; cleanup stops it by that PID.
bg_proc() { local p; p=$( (sleep 3000 > /dev/null 2>&1 & echo $!) ); echo "$p" >> "$base/extra.pids"; printf '%s\n' "$p"; }
owner=$(bg_proc)
pstart() { LC_ALL=C TZ=UTC ps -o lstart= -p "$1" | sed 's/^ *//; s/ *$//'; }
holder() {
  local p=${3:-$owner}
  mkdir -p "$1/sessions"
  jq -n --arg run "$(basename "$1")" --arg n "$2" --argjson p "$p" --arg ps "$(pstart "$p")" '{schemaVersion: 2, run: $run, name: $n, role: "worker",
    session_id: "11111111-2222-4333-8444-555555555555", pid: null, pid_file: "/nonexistent", status: "launching",
    launch_pid: $p, launch_start: $ps}' > "$1/sessions/$2.json"
}
working_workers() { "$h" session "$1" status | jq -r 'select(.role == "worker" and .liveness == "working") | .name' | wc -l | tr -d ' '; }

# ---- H-104: where the cap comes from ----
setcfg 'del(.limits)'
r=$("$h" run new)
assert_eq "H-104: with no cap set anywhere the cap is 1" 1 "$(limit "$r" .workers)"
assert_eq "H-107 (D26): with no limits set the heavy and browser limits are 1" "1 1" "$(limit "$r" '"\(.heavy) \(.stages.browser)"')"
setcfg '.limits = {workers: 2}'
r=$("$h" run new)
assert_eq "H-104: the project config sets the cap" 2 "$(limit "$r" .workers)"
r=$("$h" run new --workers 3)
assert_eq "H-104: a cap set at launch beats the project config" 3 "$(limit "$r" .workers)"
assert_exit "H-104: the minimum cap is 1 (launch option)" 64 "$h" run new --workers 0
setcfg '.limits = {workers: 0}'
assert_exit "H-104: the minimum cap is 1 (config)" 78 "$h" run new
setcfg '.limits = {stages: {browser: "many"}}'
assert_exit "H-107: a stage limit must be a whole number" 78 "$h" run new
cp "$base/config.orig.json" "$cfg"

# ---- H-105 / D26a: two starts race for the last slot, many rounds ----
r=$("$h" run new --workers 1)
for i in 1 2 3; do
  (c=0; wl "$r" "a$i" >/dev/null 2>&1 || c=$?; echo "$c" > "$base/rc-a$i") &
  (c=0; wl "$r" "b$i" >/dev/null 2>&1 || c=$?; echo "$c" > "$base/rc-b$i") &
  wait
  got="$(cat "$base/rc-a$i") $(cat "$base/rc-b$i")"
  case $got in
    "0 73" | "73 0") ok "H-105 (D26a): round $i: one start won the last slot, the other was told to wait ($got)" ;;
    *) bad "H-105 (D26a): round $i: one start won the last slot, the other was told to wait" "$got" ;;
  esac
  assert_eq "H-105: round $i: cap 1 never shows two worker sessions at once" 1 "$(working_workers "$r")"
  win=a$i
  [ "$(cat "$base/rc-a$i")" = 0 ] || win=b$i
  "$h" session "$r" close "$win" >/dev/null 2>&1 || bad "test setup: close $win failed"
done
assert_eq "H-105: the losing starts left no session record" 3 "$(ls "$r/sessions"/*.json | wc -l | tr -d ' ')"
assert_eq "H-105: the losing starts wrote no launcher, so no terminal ran one" 3 "$(ls "$r/launchers"/*.sh | wc -l | tr -d ' ')"

# The loser waits, then starts as soon as the slot is free.
wl "$r" c1 >/dev/null
sleep_marks "$base/marks"
# The waiter marks each sleep after a failed try: the check below runs once it really waits.
(c=0; PATH="$base/marks:$PATH" T_SLEEP_MARK="$base/wait-c2" wl "$r" c2 --slot-wait 60 >/dev/null 2>&1 || c=$?; echo "$c" > "$base/rc-c2") &
waiter=$!
wait_mark "$base/wait-c2" 0.5 || bad "test setup: c2 does not wait for a slot" ""
assert_eq "H-105: a start that waits for the slot has not launched yet" "" "$(cat "$base/rc-c2" 2>/dev/null || true)"
assert_eq "H-105: while one waits, only one worker runs" 1 "$(working_workers "$r")"
"$h" session "$r" close c1 >/dev/null
wait "$waiter"
assert_eq "H-105: the waiting start launched once the slot was free" 0 "$(cat "$base/rc-c2")"
assert_eq "H-105: still one worker at a time" 1 "$(working_workers "$r")"

# A dead worker gives its slot back without a close.
p=$(jq -r .pid "$r/sessions/c2.json")
kill "$p"
wait_gone "$p" || bad "test setup: c2 did not end" "$p"
# The launcher may still try the next model; it ends (or gives up) at once, as no model is left.
i=0; while [ "$("$h" session "$r" status c2 | jq -r .liveness)" = starting ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
assert_exit "H-105: a worker whose process died frees its slot" 0 wl "$r" c3
assert_contains "H-105: the freed slot is in the ledger" "$(grep slot-freed "$r/ledger.jsonl")" '"holder":"c2"'

# A non-worker session takes no worker slot.
assert_exit "H-105: a validator start takes no worker slot" 0 "$h" session "$r" launch --role validator --name v1 --cwd "$proj/src" --prompt "$base/prompt.md"
assert_exit "H-105: worker slots cannot be taken by hand" 65 "$h" slot "$r" acquire worker --holder v1

# ---- H-107 / D26: the heavy slot ----
r=$("$h" run new --workers 3)
for n in h1 h2 h3 g1 g2; do holder "$r" "$n"; done
assert_eq "D26: the shipped heavy list has six types" 6 "$("$h" slot "$r" heavy-ops | wc -l | tr -d ' ')"
assert_exit "H-107: the first heavy job takes the slot" 0 "$h" slot "$r" acquire heavy --holder h1 --op image-build
assert_exit "H-107: a second heavy job does not start while the first runs" 73 "$h" slot "$r" acquire heavy --holder h2 --op app-build
(c=0; PATH="$base/marks:$PATH" T_SLEEP_MARK="$base/wait-h2" "$h" slot "$r" acquire heavy --holder h2 --op app-build --wait 60 >/dev/null 2>&1 || c=$?; echo "$c" > "$base/rc-h2") &
waiter=$!
wait_mark "$base/wait-h2" 0.5 || bad "test setup: h2 does not wait for the heavy slot" ""
assert_eq "H-107: the second heavy job waits" "" "$(cat "$base/rc-h2" 2>/dev/null || true)"
"$h" slot "$r" release heavy --holder h1 >/dev/null
wait "$waiter"
assert_eq "H-107: the second heavy job starts when the first ends" 0 "$(cat "$base/rc-h2")"
assert_exit "H-107: an operation that is not on the list is refused as heavy" 65 "$h" slot "$r" acquire heavy --holder h3 --op browser-e2e
assert_exit "H-107: a heavy slot needs an operation type" 64 "$h" slot "$r" acquire heavy --holder h3
assert_exit "H-107: only a session of the run holds a slot" 66 "$h" slot "$r" acquire heavy --holder nobody --op app-build

# ---- H-107: the orchestrator extends the list but never raises a limit ----
before=$("$h" slot "$r" limits)
assert_exit "H-107: a list entry cannot carry a limit" 65 "$h" slot "$r" heavy-add 'heavy=5' 'try to raise'
assert_exit "H-107: a list entry cannot carry an option" 65 "$h" slot "$r" heavy-add '--limit' '2'
assert_exit "H-107: a list entry cannot be a number" 65 "$h" slot "$r" heavy-add '2' 'two'
assert_exit "H-107: the orchestrator adds a heavy type" 0 "$h" slot "$r" heavy-add browser-e2e 'judged heavy on this project'
assert_contains "H-107: the added type counts as heavy" "$("$h" slot "$r" heavy-ops)" browser-e2e
assert_eq "H-107: adding to the list raised no limit" "$before" "$("$h" slot "$r" limits)"
assert_exit "H-107: the added type waits for the one heavy slot like the others" 73 "$h" slot "$r" acquire heavy --holder h3 --op browser-e2e
assert_contains "H-107: the extension is in the ledger" "$(grep heavy-op-added "$r/ledger.jsonl")" '"op":"browser-e2e"'

# ---- H-107: the browser stage limit, while others continue ----
assert_exit "H-107: one ticket enters the browser stage" 0 "$h" slot "$r" acquire stage:browser --holder g1
assert_exit "H-107: a second ticket waits at the browser stage" 73 "$h" slot "$r" acquire stage:browser --holder g2
assert_exit "H-107: other stages continue meanwhile" 0 "$h" slot "$r" acquire stage:ui-check --holder g2
assert_exit "H-107: a stage id must be a-z 0-9 -" 65 "$h" slot "$r" acquire 'stage:../x' --holder g2

# A stage race over many rounds: never two holders of the one slot.
races_bad=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  holder "$r" "x$i"; holder "$r" "y$i"
  (c=0; "$h" slot "$r" acquire stage:e2e --holder "x$i" >/dev/null 2>&1 || c=$?; echo "$c" > "$base/rx") &
  (c=0; "$h" slot "$r" acquire stage:e2e --holder "y$i" >/dev/null 2>&1 || c=$?; echo "$c" > "$base/ry") &
  wait
  got="$(cat "$base/rx") $(cat "$base/ry")"
  n=$(ls "$r/slots/stage-e2e"/*.json 2>/dev/null | wc -l | tr -d ' ')
  if { [ "$got" = "0 73" ] || [ "$got" = "73 0" ]; } && [ "$n" = 1 ]; then :; else races_bad=1; bad "D26a: stage race round $i" "$got, $n holders"; fi
  "$h" slot "$r" release stage:e2e --holder "x$i" >/dev/null
  "$h" slot "$r" release stage:e2e --holder "y$i" >/dev/null
done
assert_eq "D26a: ten races for one slot each gave it to exactly one taker" 0 "$races_bad"

# A holder that is gone frees its slots.
rm -f "$r/sessions/h2.json"
assert_exit "H-107: the heavy slot of a session with no record is freed" 0 "$h" slot "$r" acquire heavy --holder h3 --op browser-e2e

# A launch that died while its record still says launching frees its slot once its launch process
# is gone, and not before, however old the record is.
k1p=$(bg_proc)
holder "$r" k1 "$k1p"; holder "$r" k2
assert_exit "H-105: a launching holder takes a slot" 0 "$h" slot "$r" acquire stage:lint --holder k1
touch -t "$(date -v-1H '+%Y%m%d%H%M' 2>/dev/null || date -d '-1 hour' '+%Y%m%d%H%M')" "$r/sessions/k1.json"
assert_exit "H-105: a launching holder whose launch process lives keeps it, however old its record" 73 "$h" slot "$r" acquire stage:lint --holder k2
kill "$k1p"; wait_gone "$k1p" || bad "test setup: the k1 launch process did not end" "$k1p"
assert_exit "H-105: once its launch process is gone, its slot is freed" 0 "$h" slot "$r" acquire stage:lint --holder k2

# ---- H-105: a failed launch whose session process runs keeps its worker slot ----
# pidof <run> <name>: the PID the launcher reported, kept for cleanup (a failed launch's record
# has no PID).
pidof_s() { local p; p=$(cut -d' ' -f1 "$1/sessions/$2.pid" 2>/dev/null || true); [ -z "$p" ] || echo "$p" >> "$base/extra.pids"; printf '%s\n' "$p"; }
# The terminal starts the launcher, then the open fails (the pane cannot be tagged) after the
# session is already up.
r=$("$h" run new --workers 1)
rc=0; HO_FAKE_TMUX_NO_TAG=1 HO_FAKE_TMUX_NO_TAG_DELAY=3 wl "$r" f1 >/dev/null 2>&1 || rc=$?
fp=$(pidof_s "$r" f1)
assert_eq "test setup: the open failed while the session process ran" "70 launch-failed yes" \
  "$rc $(jq -r .status "$r/sessions/f1.json") $(alive "$fp" && echo yes || echo no)"
assert_eq "H-105: a failed launch whose session runs keeps its worker slot" yes "$([ -f "$r/slots/worker/f1.json" ] && echo yes || echo no)"
assert_exit "H-105: the next worker waits for that slot" 73 wl "$r" f2
assert_eq "H-105: cap 1 never shows two worker sessions after a failed open" 1 "$(working_workers "$r")"
kill "$fp"; wait_gone "$fp" || bad "test setup: f1 did not end" "$fp"
assert_exit "H-105: once that session process ends, its slot is free" 0 wl "$r" f2

# A session that boots around the boot timeout (validator finding 1): at every timing, cap 1
# never shows two workers, and a working late session still holds its slot.
cp "$user/config.json" "$base/user.orig.json"
setcfg '.session.boot_timeout_seconds = 2'
for s in 1.7 2.0 2.3 2.6; do
  r=$("$h" run new --workers 1)
  jq --arg s "$s" '.accounts = {roles: {default: "acc"}, list: {acc: {env_command: ("[ -n \"${HO_SESSION_NAME:-}\" ] && sleep " + $s + "; echo FOO=bar")}}}' \
    "$base/user.orig.json" > "$user/config.json"
  rc1=0; wl "$r" l1 >/dev/null 2>&1 || rc1=$?
  sleep 1.5
  cp "$base/user.orig.json" "$user/config.json"
  rc2=0; wl "$r" l2 >/dev/null 2>&1 || rc2=$?
  lp=$(pidof_s "$r" l1); pidof_s "$r" l2 >/dev/null
  n=$(working_workers "$r")
  l1v=$("$h" session "$r" status l1 | jq -r .liveness)
  if [ "$n" -le 1 ]; then ok "H-105: boot at ${s}s with a 2s boot timeout: at most one worker runs (l1 rc $rc1, l2 rc $rc2)"
  else bad "H-105: boot at ${s}s with a 2s boot timeout: at most one worker runs" "$n working, l1 rc $rc1, l2 rc $rc2"; fi
  # Which way a timing goes depends on the machine's load, so each timing gives the same results
  # whichever way it went (issue #109).
  held=$([ -f "$r/slots/worker/l1.json" ] && echo yes || echo no)
  if [ "$l1v" != working ] || [ "$held" = yes ]; then ok "H-105: boot at ${s}s: a working late session holds its slot (l1 $l1v)"
  else bad "H-105: boot at ${s}s: a working late session holds its slot" "l1 working, slot $held"; fi
  if [ "$l1v" = working ] && [ "$rc1" -ne 0 ]; then
    co=$("$h" session "$r" close l1 2>&1 || true)
    case $co in *closed*) cl=yes ;; *) cl=no ;; esac
    assert_eq "H-105: boot at ${s}s: close ends a late session whose launch failed and gives its slot back" "yes no" \
      "$cl $([ -f "$r/slots/worker/l1.json" ] && echo yes || echo no)"
  else ok "H-105: boot at ${s}s: close ends a late session whose launch failed and gives its slot back (l1 $l1v, rc $rc1)"; fi
  [ -z "$lp" ] || kill "$lp" 2>/dev/null || true
done
cp "$base/user.orig.json" "$user/config.json"
cp "$base/config.orig.json" "$cfg"

# ---- H-105 / H-090: a launch command killed after the terminal opened (validator finding 2) ----
# Its record still says launching. Past the launch window its live session is not dead.
r=$("$h" run new --workers 1)
# The launch command itself is killed (not a shell around it), as when a tool call times out.
# The launcher's account command waits while the hold file exists, so the launch is in its boot
# check when it is killed, however slow the machine is (issue #109).
jq --arg hold "$base/hold-k3" '.accounts = {roles: {default: "acc"}, list: {acc: {env_command: ("[ -z \"${HO_SESSION_NAME:-}\" ] || while [ -e \"" + $hold + "\" ]; do sleep 0.1; done; echo FOO=bar")}}}' \
  "$base/user.orig.json" > "$user/config.json"
: > "$base/hold-k3"
"$h" session "$r" launch --role worker --name k3 --cwd "$proj/src" --prompt "$base/prompt.md" >/dev/null 2>&1 &
lp=$!
i=0; while [ "$(jq -r '.handle // ""' "$r/sessions/k3.json" 2>/dev/null)" = "" ] && [ $i -lt 600 ]; do sleep 0.05; i=$((i + 1)); done
kill -9 "$lp" 2>/dev/null || true; wait "$lp" 2>/dev/null || true
cp "$base/user.orig.json" "$user/config.json"
rm -f "$base/hold-k3"
i=0; while [ ! -s "$r/sessions/k3.pid" ] && [ $i -lt 600 ]; do sleep 0.05; i=$((i + 1)); done
i=0; while ! alive "$(pidof_s "$r" k3)" && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
kp=$(pidof_s "$r" k3)
assert_eq "test setup: the record says launching and the session runs" "launching yes" "$(jq -r .status "$r/sessions/k3.json") $(alive "$kp" && echo yes || echo no)"
touch -t "$(date -v-1H '+%Y%m%d%H%M' 2>/dev/null || date -d '-1 hour' '+%Y%m%d%H%M')" "$r/sessions/k3.json"
assert_eq "H-090: a launching record past the launch window with a live session reads as working" working "$("$h" session "$r" status k3 | jq -r .liveness)"
assert_exit "H-105: its worker slot is not freed, so the next worker waits" 73 wl "$r" k4
kill "$kp"; wait_gone "$kp" || bad "test setup: k3 did not end" "$kp"
assert_eq "H-090: once its session ends, the old launching record reads as dead" dead "$("$h" session "$r" status k3 | jq -r .liveness)"
assert_exit "H-105: then the slot is free" 0 wl "$r" k4
