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
assert_contains "Rebuild graceful close: the closed session's own pane is closed" "$(calls)" "tmux close $h1"

# ---- the fake session leaves only on a whole "/exit" line (review of wave 2, N1) ------------
# The engine types the text and sends Enter in two calls; the fake must not leave between them.
launch e1 >/dev/null
pe=$(rec e1 .pid) fe="$HO_FAKE_TERM_DIR/$(printf '%s' "$(rec e1 .handle)" | tr -c 'A-Za-z0-9-' '_').in"
printf '/exit' >> "$fe"
sleep 0.5
assert_eq "N1: the fake session stays while /exit has no Enter yet" "yes" "$(alive "$pe" && echo yes || echo no)"
printf '\n' >> "$fe"
assert_eq "N1: the fake session leaves once the /exit line is complete" "yes" "$(wait_gone "$pe" && echo yes || echo no)"

# ---- H-103, S8-27 (review of wave 2, B1): the pane ID names another session by now -------
# As the session leaves, the tmux server restarts and another session of this run gets the
# same pane ID. The fake acts this out by giving the pane another session's tag.
HO_FAKE_CLAUDE_ON_EXIT='echo 33333333-3333-4333-8333-333333333333 > "$HO_FAKE_TERM_DIR/$(printf %s "$HO_FAKE_TERM_HANDLE" | tr -c A-Za-z0-9- _).tag"' \
  launch c4 >/dev/null
h4=$(rec c4 .handle) p4=$(rec c4 .pid)
assert_exit "H-103: close of a session whose pane ID was taken over succeeds" 0 "$h" session "$run" close c4
assert_eq "H-103: the session's own process has ended" "yes" "$(wait_gone "$p4" && echo yes || echo no)"
assert_eq "H-103: the pane that now belongs to another session is not closed" "" "$(calls | grep -F "tmux close $h4" || true)"
assert_contains "H-103: the skipped pane close is recorded with its reason" "$(grep session-close-terminal-skipped "$run/ledger.jsonl" || true)" "names another session"
assert_eq "H-103: the session is still marked closed" "closed" "$(rec c4 .status)"

# ---- H-103, S8-27 (review of wave 2, N2): a resume reuses the session ID, not the tag -------
launch r1 >/dev/null
sr=$(rec r1 .session_id)
resume_r2() { "$h" session "$run" launch --role worker --name r2 --cwd "$proj/src" --resume "$sr"; }
rc=0; resume_r2 >/dev/null 2>&1 || rc=$?
assert_eq "N2: a resume while a record with that session ID is not closed is refused (65)" "65" "$rc"
assert_eq "N2: the refused resume leaves no record" "no" "$([ -e "$run/sessions/r2.json" ] && echo yes || echo no)"
"$h" session "$run" close r1 >/dev/null || true
resume_r2 >/dev/null 2>&1 || true
hr1=$(rec r1 .handle) hr2=$(rec r2 .handle) pr2=$(rec r2 .pid)
tag_of() { cat "$HO_FAKE_TERM_DIR/$(printf '%s' "$1" | tr -c 'A-Za-z0-9-' '_').tag"; }
assert_eq "N2: after the close the resume starts" "running $sr" "$(rec r2 .status) $(rec r2 .session_id)"
assert_eq "N2: each launch of one session ID tags its pane with its own tag" "yes" \
  "$([ "$(tag_of "$hr1")" != "$(tag_of "$hr2")" ] && [ "$(tag_of "$hr2")" = "$(rec r2 .term_tag)" ] && [ "$(tag_of "$hr2")" != "$sr" ] && echo yes || echo no)"
# A late close of the first launch reaches the resumed launch's pane and process (the pane ID
# was reused, and the process carries the same session ID). It must not type into that pane.
jq --arg h "$hr2" --argjson p "$pr2" '.status = "running" | .handle = $h | .pid = $p' "$run/sessions/r1.json" > "$base/r.json" && mv "$base/r.json" "$run/sessions/r1.json"
rc=0; "$h" session "$run" close r1 >/dev/null 2>&1 || rc=$?
assert_eq "N2: a close of an earlier launch through the resumed launch's pane is refused (70)" "70" "$rc"
assert_eq "N2: nothing is typed into the resumed launch's pane" "" "$(calls | grep -F "send-text $hr2 " || true)"
assert_eq "N2: the resumed launch keeps running" "yes" "$(alive "$pr2" && echo yes || echo no)"
# A record without a launch tag (written before tags were per launch) is not closed through
# its terminal: the session ID alone does not name one launch.
jq 'del(.term_tag)' "$run/sessions/r2.json" > "$base/r.json" && mv "$base/r.json" "$run/sessions/r2.json"
rc=0; "$h" session "$run" close r2 >/dev/null 2>&1 || rc=$?
assert_eq "N2: a record without a launch tag is left open (70)" "70 yes" "$rc $(alive "$pr2" && echo yes || echo no)"

# ---- close uses the backend the session was launched with -----------------------------------
launch c3 >/dev/null
h3=$(rec c3 .handle)
jq '.terminal.app = "iterm2"' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
assert_exit "Rebuild graceful close: a session launched on tmux closes after terminal.app changed" 0 "$h" session "$run" close c3
assert_contains "Rebuild graceful close: the exit command went through tmux" "$(calls)" "tmux send-text $h3 /exit"
assert_eq "Rebuild graceful close: nothing went to iTerm2" "" "$(calls | grep osascript || true)"
jq '.terminal.app = "tmux"' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"

# ---- H-103, S8-27 (review of wave 2, R1): a record that carries another session's handle and tag
# The record of f1 keeps its own session ID, process ID and PID file, but names the handle and
# the launch tag of f2. The pane or tab of f2 carries the session ID of f2, so close must not
# type into it. Nor may a record with the handle, tag, session ID and PID of f2 but the PID file
# of f1: that PID file does not name the session ID of f2.
setcfg() { jq "$1" "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"; }
for be in tmux iterm2; do
  setcfg ".terminal.app = \"$be\""
  launch "f1$be" >/dev/null
  launch "f2$be" >/dev/null
  pf1=$(rec "f1$be" .pid) pf2=$(rec "f2$be" .pid) hf2=$(rec "f2$be" .handle)
  cp "$run/sessions/f1$be.json" "$base/f1.orig"
  jq --arg h "$hf2" --arg t "$(rec "f2$be" .term_tag)" '.handle = $h | .term_tag = $t' "$base/f1.orig" > "$run/sessions/f1$be.json"
  rc=0; "$h" session "$run" close "f1$be" >/dev/null 2>&1 || rc=$?
  assert_eq "R1 ($be): close of a record with another session's handle and tag is refused (70)" "70" "$rc"
  assert_eq "R1 ($be): nothing is typed into the other session" "" "$(calls | grep -F "send-text $hf2 " || true)"
  assert_eq "R1 ($be): both processes stay alive" "yes yes" "$(alive "$pf1" && echo yes || echo no) $(alive "$pf2" && echo yes || echo no)"
  jq --arg h "$hf2" --arg t "$(rec "f2$be" .term_tag)" --arg s "$(rec "f2$be" .session_id)" --argjson p "$pf2" \
    '.handle = $h | .term_tag = $t | .session_id = $s | .pid = $p' "$base/f1.orig" > "$run/sessions/f1$be.json"
  rc=0; "$h" session "$run" close "f1$be" >/dev/null 2>&1 || rc=$?
  assert_eq "R1 ($be): close of a record whose PID file does not name its session ID is refused (70)" "70" "$rc"
  assert_eq "R1 ($be): that record types nothing, and both processes stay alive" "yes yes" \
    "$([ -z "$(calls | grep -F "send-text $hf2 " || true)" ] && alive "$pf2" && echo yes || echo no) $(alive "$pf1" && echo yes || echo no)"
  cp "$base/f1.orig" "$run/sessions/f1$be.json"
  rc=0; "$h" session "$run" close "f1$be" >/dev/null 2>&1 || rc=$?
  assert_eq "R1 ($be): the restored record still closes its own session" "0 closed yes" "$rc $(rec "f1$be" .status) $(alive "$pf2" && echo yes || echo no)"
done
setcfg '.terminal.app = "tmux"'

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
assert_eq "Rebuild graceful close: a close leaves its flag for the launcher" "yes" "$([ -e "$run/sessions/g1.closing" ] && echo yes || echo no)"
lines=$(wc -l < "$HO_FAKE_CLAUDE_LOG")
rc=0; /bin/bash "$(rec g1 .launcher)" 2>/dev/null || rc=$?
assert_eq "Rebuild graceful close: after a close the launcher starts no further attempt" "0 $lines" "$rc $(wc -l < "$HO_FAKE_CLAUDE_LOG")"

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

# ---- records that cannot be trusted are not closed ---------------------------------------
launch k1 >/dev/null
pk=$(rec k1 .pid)
jq '.status = "launching"' "$run/sessions/k1.json" > "$base/r.json" && mv "$base/r.json" "$run/sessions/k1.json"
assert_exit "Rebuild graceful close: a session still launching is not closed" 65 "$h" session "$run" close k1
jq '.status = "running" | .session_id = ""' "$run/sessions/k1.json" > "$base/r.json" && mv "$base/r.json" "$run/sessions/k1.json"
assert_exit "S8-27: a record without a session ID is refused, not marked closed" 66 "$h" session "$run" close k1
assert_eq "S8-27: the session behind an unusable record keeps running" "yes" "$(alive "$pk" && echo yes || echo no)"
assert_eq "S8-27: an unusable record is not marked closed" "running" "$(rec k1 .status)"

# ---- H-103: the engine has no pattern kill -------------------------------------------------
# The bracketed pattern keeps this file itself out of the issue's grep for pattern kills.
assert_eq "H-103: engine code holds no name-pattern kill or process search" "" "$(grep -rnE 'p[k]ill|kill[a]ll|p[g]rep' "$HO_PLUGIN_ROOT/bin" "$HO_PLUGIN_ROOT/lib" "$HO_PLUGIN_ROOT/runtimes" || true)"

# ---- a session launched from a user runtime profile closes with that profile (review round 2, Codex 4701861993)
mkdir -p "$user/runtimes"
jq '.exit_command = "/exit"' "$HO_PLUGIN_ROOT/runtimes/claude-code.json" > "$user/runtimes/my-cc.json"
cp "$HO_PLUGIN_ROOT/runtimes/claude-code.screen.json" "$user/runtimes/claude-code.screen.json"
printf '{"schemaVersion": 2, "runtime": {"main": "my-cc"} }\n' > "$user/config.json"
launch u1 >/dev/null
pu=$(rec u1 .pid)
assert_eq "D37-RUNTIME-2: a session launched from a user runtime profile records that profile" "my-cc" "$(rec u1 .runtime)"
assert_exit "D37-RUNTIME-2: a session launched from a user runtime profile closes cleanly" 0 "$h" session "$run" close u1
assert_eq "D37-RUNTIME-2: that session's process has ended" "yes" "$(wait_gone "$pu" && echo yes || echo no)"
printf '{"schemaVersion": 2, "runtime": {"main": "claude-code"} }\n' > "$user/config.json"
