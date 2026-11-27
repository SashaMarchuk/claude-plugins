# The repository's master runner, tests/run-all.sh (issue #116): each plugin runner runs once,
# the totals come from that run's last summary line, and one full run at a time holds a lock.
# A copy of run-all runs in a scratch tree with fake plugin runners and a fake npx; its lock is a
# scratch path, so a real full run that is running this file is never waited for.
base=$(cd -P "$PWD" && pwd)
src="$HO_PLUGIN_ROOT/../../tests/run-all.sh"
repo="$base/repo"
mkdir -p "$repo/tests" "$base/bin"
cp "$src" "$repo/tests/run-all.sh"
plugins=$(sed -n 's/^PLUGINS=(\(.*\))$/\1/p' "$src")
printf '#!/bin/sh\nexit 0\n' > "$base/bin/npx"
chmod +x "$base/bin/npx"
# Every fake runner logs each start and end to calls.log with the run's tag (T_TAG). With T_HOLD
# set, the first runner waits while that file exists. The last plugin prints an earlier line with
# other counts, so only the last summary line may count.
first=${plugins%% *}
last=${plugins##* }
for p in $plugins; do
  mkdir -p "$repo/plugins/$p/tests"
  {
    printf '#!/bin/sh\n'
    printf 'printf "%%s start %s\\n" "${T_TAG:-}" >> "%s/calls.log"\n' "$p" "$base"
    if [ "$p" = "$first" ]; then
      printf 'if [ -n "${T_HOLD:-}" ]; then : > "$T_HOLD.started"; while [ -e "$T_HOLD" ]; do sleep 0.1; done; fi\n'
    fi
    if [ "$p" = "$last" ]; then
      printf 'echo "part one: PASS=90  FAIL=9"\n'
      printf 'printf "%%s end %s\\n" "${T_TAG:-}" >> "%s/calls.log"\n' "$p" "$base"
      printf 'echo "%s tests: PASS=2  FAIL=0"\n' "$p"
    else
      printf 'printf "%%s end %s\\n" "${T_TAG:-}" >> "%s/calls.log"\n' "$p" "$base"
      printf 'echo "%s tests: PASS=3  FAIL=0"\n' "$p"
    fi
  } > "$repo/plugins/$p/tests/run.sh"
done
lock="$base/run-all.lock"
ra() { PATH="$base/bin:$PATH" HO_RUN_ALL_LOCK="$lock" bash "$repo/tests/run-all.sh"; }
# wait_for <tenths> <cmd...>: wait until the command succeeds (a generous cap, not a timing check).
wait_for() { local n=$1 i=0; shift; until "$@"; do [ "$i" -lt "$n" ] || return 1; sleep 0.1; i=$((i + 1)); done; }
has() { grep -q -- "$2" "$1" 2>/dev/null; }
nplug=$(printf '%s\n' $plugins | wc -l | tr -d ' ')

# ---- one run per runner, totals from that run's last summary line ----
: > "$base/calls.log"
rc=0; out=$(T_TAG=one ra 2>&1) || rc=$?
assert_eq "run-all: the run passes (exit 0)" 0 "$rc"
assert_eq "run-all: each plugin runner runs exactly once" "$nplug" "$(grep -c '^one start ' "$base/calls.log")"
assert_eq "run-all: no plugin runner runs twice" "" "$(grep '^one start ' "$base/calls.log" | sort | uniq -d)"
assert_contains "run-all: a plugin's totals are its own last summary line" "$out" "/$last: PASS=2  FAIL=0  exit=0"
# Each fake runner but the last says PASS=3; the last says PASS=2; openspec adds one PASS.
assert_contains "run-all: the total is the sum of the last summary lines" "$out" "Total: $(( (nplug - 1) * 3 + 2 + 1 )) PASS / 0 FAIL"
assert_eq "run-all: the lock is released after the run" no "$([ -e "$lock" ] && echo yes || echo no)"

# ---- one full run at a time: a second run waits until the first ends ----
: > "$base/calls.log"
: > "$base/hold"
(T_TAG=A T_HOLD="$base/hold" ra > "$base/a.out" 2>&1; echo $? > "$base/a.rc") &
wait_for 600 test -e "$base/hold.started" || bad "test setup: run A did not start" ""
(T_TAG=B ra > "$base/b.out" 2>&1; echo $? > "$base/b.rc") &
# Proof that B met the lock: it says it waits. Then B has started no runner while A holds it.
if wait_for 600 has "$base/b.out" "waiting"; then ok "run-all lock: a second run says it waits for the first"
else bad "run-all lock: a second run says it waits for the first" "$(cat "$base/b.out")"; fi
assert_contains "run-all lock: the waiting run names the PID it waits for" "$(cat "$base/b.out")" "waiting for PID $(cut -d' ' -f1 "$lock/owner" 2>/dev/null) to end"
assert_eq "run-all lock: the waiting run starts no runner while the first holds the lock" "" "$(grep '^B ' "$base/calls.log" || true)"
rm -f "$base/hold"
wait_for 1200 test -s "$base/a.rc" || bad "test setup: run A did not end" ""
wait_for 1200 test -s "$base/b.rc" || bad "test setup: run B did not end" ""
assert_eq "run-all lock: both runs pass" "0 0" "$(cat "$base/a.rc") $(cat "$base/b.rc")"
# Order, not time: every line of A comes before the first line of B.
lastA=$(grep -n '^A ' "$base/calls.log" | tail -1 | cut -d: -f1)
firstB=$(grep -n '^B ' "$base/calls.log" | head -1 | cut -d: -f1)
assert_eq "run-all lock: the second run starts only after the first has ended" yes "$([ -n "$lastA" ] && [ -n "$firstB" ] && [ "$lastA" -lt "$firstB" ] && echo yes || echo no)"

# ---- a stale lock is taken over in place ----
# The owner line names a live PID with another start time: a reused PID, not the holder.
mkdir "$lock"
printf '%s %s\n' "$$" "Thu Jan  1 00:00:00 1970" > "$lock/owner"
: > "$base/calls.log"
rc=0; out=$(T_TAG=C ra 2>&1) || rc=$?
assert_eq "run-all lock: a lock whose holder is gone (reused PID) is taken over; the run passes" 0 "$rc"
assert_contains "run-all lock: the takeover is reported" "$out" "took over the lock"
assert_eq "run-all lock: the run that took over ran every runner" "$nplug" "$(grep -c '^C start ' "$base/calls.log")"
assert_eq "run-all lock: the taken-over lock is released after the run" no "$([ -e "$lock" ] && echo yes || echo no)"

# A stale lock that another waiter is taking over is never removed by this one.
sh -c 'exit 0' & dead=$!; wait "$dead" || true
mkdir -p "$lock/takeover"
printf '%s %s\n' "$dead" "Thu Jan  1 00:00:00 1970" > "$lock/owner"
: > "$base/calls.log"
(T_TAG=D ra > "$base/d.out" 2>&1; echo $? > "$base/d.rc") &
if wait_for 600 has "$base/d.out" "waiting"; then ok "run-all lock: a lock under takeover by another waiter makes the run wait"
else bad "run-all lock: a lock under takeover by another waiter makes the run wait" "$(cat "$base/d.out")"; fi
assert_eq "run-all lock: a lock under takeover is not removed by a waiter" "$dead" "$(cut -d' ' -f1 "$lock/owner" 2>/dev/null || echo gone)"
rmdir "$lock/takeover"
wait_for 1200 test -s "$base/d.rc" || bad "test setup: run D did not end" ""
assert_eq "run-all lock: after the other takeover ends the run goes on and passes" 0 "$(cat "$base/d.rc")"
assert_eq "run-all lock: that lock is released after the run" no "$([ -e "$lock" ] && echo yes || echo no)"
