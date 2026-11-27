# The fake claude's hold loop does no work while nothing it reads changes (issue #116): it runs
# its transcript step only when the typed input or the busy mark changed. Ticks and steps are
# counted through HO_FAKE_CLAUDE_STEP_LOG; every wait is for an event, with a generous cap.
base=$(cd -P "$PWD" && pwd)
fake="$HO_TESTS_DIR/fake-bin/claude"
term="$base/term"
mkdir -p "$term" "$base/cfg" "$base/cwd"
sid=11111111-2222-4333-8444-555555555555
in="$term/h1.in"
: > "$in"
log="$base/steps.log"
: > "$log"
(cd "$base/cwd" && HO_FAKE_TERM_DIR="$term" HO_FAKE_TERM_HANDLE=h1 HO_FAKE_CLAUDE_HOLD=exit HO_FAKE_CLAUDE_HOLD_MAX=600 \
  HO_FAKE_CLAUDE_TRANSCRIPT=1 HO_FAKE_CLAUDE_STEP_LOG="$log" CLAUDE_CONFIG_DIR="$base/cfg" HO_FAKE_CLAUDE_LOG="$base/claude.log" \
  exec "$fake" --session-id "$sid" > /dev/null 2>&1) &
fp=$!
echo "$fp" > "$base/fake.pid"
trap 'kill "$(cat "$base/fake.pid")" 2>/dev/null || true' EXIT
tr="$base/cfg/projects/$(printf '%s' "$base/cwd" | tr -c 'A-Za-z0-9' '-')/$sid.jsonl"
cnt() { grep -c "^$1\$" "$log" 2>/dev/null || true; }
# wait_for <tenths> <cmd...>: wait until the command succeeds.
wait_for() { local n=$1 i=0; shift; until "$@"; do [ "$i" -lt "$n" ] || return 1; sleep 0.1; i=$((i + 1)); done; }
ticks_past() { [ "$(cnt tick)" -ge "$1" ]; }
has() { grep -q -- "$2" "$1" 2>/dev/null; }

# Idle: many ticks, one step (the first look).
wait_for 1200 ticks_past 20 || bad "test setup: the fake made no 20 ticks" "$(cnt tick)"
assert_eq "fake claude: with its input unchanged it runs no transcript step after the first look" 1 "$(cnt step)"

# A typed line is a change: it is stepped once and recorded as a user turn.
printf 'hello there\n' >> "$in"
if wait_for 1200 has "$tr" '"content":"hello there"'; then ok "fake claude: a typed line still becomes a user turn"
else bad "fake claude: a typed line still becomes a user turn" "$(cat "$tr" 2>/dev/null)"; fi
s1=$(cnt step)
t1=$(cnt tick)
wait_for 1200 ticks_past $((t1 + 20)) || bad "test setup: the fake made no 20 more ticks" ""
assert_eq "fake claude: after the change is handled, unchanged input runs no more steps" "$s1" "$(cnt step)"

# The busy mark alone is a change: a line queued while busy is released when the mark goes.
: > "$term/h1.busy"
printf 'queued one\n' >> "$in"
wait_for 1200 has "$tr" '"operation":"enqueue"' || bad "fake claude: a line typed while busy is queued" ""
rm -f "$term/h1.busy"
if wait_for 1200 has "$tr" '"type":"queued_command"'; then ok "fake claude: removing the busy mark alone releases the queue"
else bad "fake claude: removing the busy mark alone releases the queue" "$(cat "$tr" 2>/dev/null)"; fi

# /exit is a change too: the fake ends.
printf '/exit\n' >> "$in"
n=0; while kill -0 "$fp" 2>/dev/null && [ "$n" -lt 1200 ]; do sleep 0.1; n=$((n + 1)); done
assert_eq "fake claude: a typed /exit ends the held fake" no "$(kill -0 "$fp" 2>/dev/null && echo yes || echo no)"
