# Graceful close (design "Rebuild" reuse list), S8-27 (close by process ID plus session ID),
# H-103 (stop only the exact process ID), PR-3 (a gone session is marked closed and no
# terminal is touched). Acceptance (issue #40): close refuses a session of another run.
. "$HO_TESTS_DIR/sessions-setup.sh"

# ---- graceful close of a live session --------------------------------------------------
launch c1 >/dev/null
launch c2 >/dev/null
p1=$(rec c1 .pid) p2=$(rec c2 .pid) h1=$(rec c1 .handle)
assert_exit "Rebuild graceful close: close of a live session succeeds" 0 "$h" session "$run" close c1
assert_eq "Rebuild graceful close: the session's own process has ended" "yes" "$(wait_gone "$p1" && echo yes || echo no)"
assert_eq "Rebuild graceful close: the record is marked closed" "closed" "$(rec c1 .status)"
assert_contains "Rebuild graceful close: the exit command was typed into that session's terminal only" "$(calls)" "send-text $h1 /exit"
assert_eq "Rebuild graceful close: nothing was typed into another session" "" "$(calls | grep send-text | grep -vF " $h1 " || true)"
assert_eq "H-103: a similar session of the same run keeps running" "yes" "$(alive "$p2" && echo yes || echo no)"
assert_eq "H-103: the similar session's record is untouched" "running" "$(rec c2 .status)"
assert_contains "Rebuild graceful close: the ledger records the close" "$(cat "$run/ledger.jsonl")" '"kind":"session-close"'
assert_exit "Rebuild graceful close: closing a closed session again is a no-op" 0 "$h" session "$run" close c1

# ---- close refuses a session recorded under another run ID ---------------------------------
run2=$("$h" run new)
"$h" session "$run2" launch --role worker --name x1 --cwd "$proj/src" --prompt "$base/prompt.md" >/dev/null
px=$(rec x1 .pid "$run2")
cp "$run2/sessions/x1.json" "$run/sessions/x1.json"
before=$(calls | wc -l)
rc=0; out=$("$h" session "$run" close x1 2>&1) || rc=$?
assert_eq "S8-27: close of a session recorded under another run ID is refused" "66" "$rc"
assert_contains "S8-27: the refusal names the other run" "$out" "$(basename "$run2")"
assert_eq "S8-27: the other run's session keeps running" "yes" "$(alive "$px" && echo yes || echo no)"
assert_eq "S8-27: nothing is typed or closed for the other run's session" "$before" "$(calls | wc -l)"
assert_eq "S8-27: the planted record is not changed" "running" "$(rec x1 .status)"
assert_contains "S8-27: the refusal is recorded in this run's ledger" "$(cat "$run/ledger.jsonl")" '"kind":"session-close-refused"'
assert_exit "S8-27: a name only another run knows is not found here" 66 "$h" session "$run" close nobody

# ---- PR-3: the process is gone; the record is closed and no terminal is touched ------------
launch g1 >/dev/null
pg=$(rec g1 .pid)
kill "$pg"
wait_gone "$pg" || true
before=$(calls | wc -l)
assert_exit "PR-3: closing a session whose process is gone succeeds" 0 "$h" session "$run" close g1
assert_eq "PR-3: the record is marked closed" "closed" "$(rec g1 .status)"
assert_eq "PR-3: no close or typing is sent to any terminal" "$before" "$(calls | wc -l)"

# ---- a recorded PID now held by another process is not that session ------------------------
launch g2 >/dev/null
pg2=$(rec g2 .pid)
sleep 30 &
other=$!
printf '%s\n' "$other" >> "$base/extra.pids"
jq --argjson p "$other" '.pid = $p' "$run/sessions/g2.json" > "$base/r.json" && mv "$base/r.json" "$run/sessions/g2.json"
kill "$pg2"
wait_gone "$pg2" || true
before=$(calls | wc -l)
assert_exit "S8-27: a reused PID without the session ID counts as gone" 0 "$h" session "$run" close g2
assert_eq "H-103: the unrelated process that holds the PID is untouched" "yes" "$(alive "$other" && echo yes || echo no)"
assert_eq "S8-27: no terminal call for a session whose identity no longer matches" "$before" "$(calls | wc -l)"

# ---- a busy session that ignores the exit command is left open -----------------------------
HO_FAKE_CLAUDE_HOLD=ignore launch b1 >/dev/null
pb=$(rec b1 .pid) hb=$(rec b1 .handle)
jq '.session.close_timeout_seconds = 1' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
assert_exit "Rebuild graceful close: a session still busy at the timeout is reported" 1 "$h" session "$run" close b1
assert_eq "Rebuild graceful close: the busy session is left open, never forced" "yes" "$(alive "$pb" && echo yes || echo no)"
assert_eq "Rebuild graceful close: the busy session stays recorded as running" "running" "$(rec b1 .status)"
assert_eq "Rebuild graceful close: the busy session's terminal is not closed" "" "$(calls | grep -F "close $hb" || true)"
assert_contains "Rebuild graceful close: the timeout is recorded in the ledger" "$(cat "$run/ledger.jsonl")" '"kind":"session-close-timeout"'

# ---- H-103: the engine has no pattern kill -------------------------------------------------
assert_eq "H-103: engine code holds no pkill, killall or pgrep" "" "$(grep -rnE 'pkill|killall|pgrep' "$HO_PLUGIN_ROOT/bin" "$HO_PLUGIN_ROOT/lib" "$HO_PLUGIN_ROOT/runtimes" || true)"
