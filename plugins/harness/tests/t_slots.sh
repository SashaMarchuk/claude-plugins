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
# holder <run> <name>: a session record that is still launching (a live holder).
holder() {
  mkdir -p "$1/sessions"
  jq -n --arg run "$(basename "$1")" --arg n "$2" '{schemaVersion: 2, run: $run, name: $n, role: "worker",
    session_id: "11111111-2222-4333-8444-555555555555", pid: null, pid_file: "/nonexistent", status: "launching"}' > "$1/sessions/$2.json"
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
(c=0; wl "$r" c2 --slot-wait 30 >/dev/null 2>&1 || c=$?; echo "$c" > "$base/rc-c2") &
waiter=$!
sleep 2
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
sleep 7 # past the model-fallback gap (boot_grace_seconds 5 + 5)
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
(c=0; "$h" slot "$r" acquire heavy --holder h2 --op app-build --wait 30 >/dev/null 2>&1 || c=$?; echo "$c" > "$base/rc-h2") &
waiter=$!
sleep 1.5
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
