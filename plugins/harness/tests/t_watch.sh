# The watch script: outage monitor and dead-orchestrator restart (H-095, H-096, H-097, H-098;
# design D22, D23, D32, D37-SESSIONS-3, D37-SESSIONS-4). The service is a fake curl built here.
# shellcheck source=sessions-setup.sh
. "$HO_TESTS_DIR/sessions-setup.sh"
mkdir -p "$base/bin"
cat > "$base/bin/curl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_HTTP_LOG"
case $(cat "$FAKE_HTTP_STATE" 2>/dev/null) in
  up) printf '200' ;;
  busy) printf '529' ;;
  *) printf '000'; exit 7 ;;
esac
SH
chmod +x "$base/bin/curl"
export PATH="$base/bin:$PATH" FAKE_HTTP_STATE="$base/http" FAKE_HTTP_LOG="$base/http.log"
pcfg="$proj/.harness/config.json"
jq '.watch = {service_url: "https://service.invalid/", internet_url: "https://net.invalid/", back_wait_seconds: 0}
    | .delivery = {wait_seconds: 2, message_timeout_seconds: 1}' "$pcfg" > "$base/c.json" && mv "$base/c.json" "$pcfg"
events() { jq -c "select(.kind == \"$2\")" "$1/ledger.jsonl" | wc -l | tr -d ' '; }
orch() { "$h" session "$1" launch --role orchestrator --name "$2" --cwd "$proj/src" --prompt "$base/prompt.md" > /dev/null; }
die() {
  local p i=0
  p=$(jq -r .pid "$1/sessions/$2.json")
  kill "$p" 2>/dev/null || true
  wait_gone "$p" || true
  while [ "$("$h" session "$1" status "$2" | jq -r .liveness)" != dead ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
}
hook() { jq -cn --arg sid "$(jq -r .session_id "$1/sessions/$2.json")" --arg e "$3" --argjson t "$(date +%s)" \
  '{t: $t, ts: "x", event: $e, session_id: $sid}' >> "$1/hooks.jsonl"; }

# ---- H-095 / D22: during an outage no prompt is sent and no session starts ----
r=$("$h" run new)
orch "$r" orch
echo up > "$FAKE_HTTP_STATE"
assert_eq "D22: both checks up reads up" up "$("$h" watch "$r" outage-check --now)"
assert_eq "D22: while up the next check is in 5 minutes" 300 "$(jq -r .interval "$r/watch/state.json")"
assert_contains "D22: the service and the internet are both checked" "$(cat "$FAKE_HTTP_LOG")" "https://net.invalid/"
assert_eq "D22: the next check waits until it is due" up "$(echo down > "$FAKE_HTTP_STATE"; "$h" watch "$r" outage-check)"
assert_eq "D22: a service that cannot be reached reads down" down "$("$h" watch "$r" outage-check --now)"
assert_eq "D22: while down the next check is in 60 seconds" 60 "$(jq -r .interval "$r/watch/state.json")"
assert_eq "H-096: the change is recorded once" 1 "$(events "$r" outage-begin)"
"$h" watch "$r" outage-check --now > /dev/null
assert_eq "H-096: a second down check adds no line" 1 "$(events "$r" outage-begin)"
claude_before=$(wc -l < "$HO_FAKE_CLAUDE_LOG" | tr -d ' ')
rc=0; "$h" session "$r" deliver orch --text "do the next step" > /dev/null 2>&1 || rc=$?
assert_eq "H-095: during an outage no prompt is sent (exit 76)" 76 "$rc"
assert_eq "H-095: nothing reached the session's messages" 0 "$(ls "$r/messages" 2>/dev/null | wc -l | tr -d ' ')"
r_main=$run; run=$r; rc=0; launch w-out > /dev/null 2>&1 || rc=$?; run=$r_main
assert_eq "D22: during an outage no new session starts (exit 76)" 76 "$rc"
assert_eq "D22: an outage opens a wait, so the retry clock stops" 1 "$(events "$r" wait-begin)"
"$h" watch "$r" cycle > /dev/null
assert_eq "H-096: the watch script runs no model session" "$claude_before" "$(wc -l < "$HO_FAKE_CLAUDE_LOG" | tr -d ' ')"
echo busy > "$FAKE_HTTP_STATE"
assert_eq "D22: a service answering 5xx still reads down" down "$("$h" watch "$r" outage-check --now)"

# ---- H-097 / D37-SESSIONS-3: back; the orchestrator's hook event is the marker ----
echo up > "$FAKE_HTTP_STATE"
"$h" watch "$r" outage-check --now > /dev/null
assert_eq "H-096: the service coming back is recorded once" 1 "$(events "$r" outage-end)"
sleep 1; hook "$r" orch PreToolUse
out=$("$h" watch "$r" back-check)
assert_contains "H-097: a hook event from the orchestrator after the outage marks it back" "$out" "is back"
assert_eq "D37-SESSIONS-3: an orchestrator that continued by itself gets no message" 0 "$(events "$r" back-message)"
# A second outage; this time no hook event comes: one message, then the event marks it back.
echo down > "$FAKE_HTTP_STATE"; "$h" watch "$r" outage-check --now > /dev/null
sleep 1; echo up > "$FAKE_HTTP_STATE"; "$h" watch "$r" outage-check --now > /dev/null
sleep 1
"$h" watch "$r" back-check > /dev/null
assert_eq "H-096: with no hook event one \"service is back\" message is sent" 1 "$(events "$r" back-message)"
sleep 1; hook "$r" orch PostToolUse
"$h" watch "$r" back-check > /dev/null
assert_eq "H-097: the first hook event after the message marks it back" 2 "$(events "$r" orchestrator-back)"
"$h" watch "$r" back-check > /dev/null
assert_eq "H-097: after the marker no more messages go out" 1 "$(events "$r" back-message)"
# Three messages at most; then the restart path.
echo down > "$FAKE_HTTP_STATE"; "$h" watch "$r" outage-check --now > /dev/null
sleep 1; echo up > "$FAKE_HTTP_STATE"; "$h" watch "$r" outage-check --now > /dev/null
for i in 1 2 3 4; do sleep 1; "$h" watch "$r" back-check > /dev/null 2>&1 || true; done
assert_eq "D22: the message repeats at most 3 times" 4 "$(events "$r" back-message)"
assert_eq "D37-SESSIONS-4: with no event after 3 messages the orchestrator is not back" 1 "$(events "$r" orchestrator-not-back)"
assert_eq "D37-SESSIONS-4: after 3 messages with no event the orchestrator is closed and resumed" 1 "$(events "$r" orchestrator-restart)"
assert_eq "D37-SESSIONS-4: the idle restart resumed the same session ID" "$(jq -r .session_id "$r/sessions/orch.json")" "$(jq -r .session_id "$r/sessions/$(jq -r 'select(.kind == "orchestrator-restart") | .name' "$r/ledger.jsonl").json")"

# ---- H-098 / D23: a dead orchestrator is restarted at most 3 times per hour ----
r=$("$h" run new)
orch "$r" boss
die "$r" boss
"$h" watch "$r" cycle > /dev/null 2>&1
assert_eq "D23: the watch script restarts a dead orchestrator" 1 "$(events "$r" orchestrator-restart)"
newest=$(jq -r 'select(.kind == "orchestrator-restart") | .name' "$r/ledger.jsonl" | tail -n 1)
assert_contains "D23: the restart resumes the session by its ID" "$(grep -F -- "--resume" "$HO_FAKE_CLAUDE_LOG" | tail -n 1)" "$(jq -r .session_id "$r/sessions/$newest.json")"
assert_exit "D37-SESSIONS-4: a live orchestrator is left alone" 0 "$h" watch "$r" restart
assert_eq "D37-SESSIONS-4: the live check started nothing" 1 "$(events "$r" orchestrator-restart)"
for i in 1 2 3; do
  newest=$(jq -r 'select(.kind == "orchestrator-restart") | .name' "$r/ledger.jsonl" | tail -n 1)
  die "$r" "$newest"
  sleep 1
  "$h" watch "$r" restart > /dev/null 2>&1 || true
done
assert_eq "H-098: at most 3 restarts in an hour" 3 "$(events "$r" orchestrator-restart)"
assert_eq "D37-SESSIONS-4: the used-up cap writes one owner-action line" 1 "$(events "$r" owner-action)"
"$h" watch "$r" restart > /dev/null 2>&1 || true
assert_eq "D37-SESSIONS-4: the cap stays used up, with no second owner-action line" "3 1" "$(events "$r" orchestrator-restart) $(events "$r" owner-action)"

# ---- D37-SESSIONS-4: a soft stop does not hold back the restart; a refused launch is deferred ----
r=$("$h" run new)
orch "$r" lead
die "$r" lead
"$h" state "$r" stop "testing a soft stop" > /dev/null
"$h" watch "$r" restart > /dev/null 2>&1 || true
assert_eq "D37-SESSIONS-4: during a soft stop the orchestrator is restarted as usual" "0" "$(jq -r 'select(.kind == "orchestrator-restart") | .rc' "$r/ledger.jsonl")"
r=$("$h" run new)
orch "$r" lead2
die "$r" lead2
printf '{"ts":"x","run":"%s","kind":"outage-begin"}\n' "$(basename "$r")" >> "$r/ledger.jsonl"
"$h" watch "$r" restart > /dev/null 2>&1 || true
assert_eq "D22: nothing restarts during an outage" 0 "$(events "$r" orchestrator-restart)"

# ---- D32: the orchestrator and the context watcher check the watch script's process ----
jq '.watch.cycle_seconds = 1' "$pcfg" > "$base/c.json" && mv "$base/c.json" "$pcfg"
r=$("$h" run new)
assert_exit "D32: with no watch script running, pid-check exits 1" 1 "$h" watch "$r" pid-check
"$h" watch "$r" loop --cycles 4 > /dev/null 2>&1 &
lp=$!
echo "$lp" >> "$base/extra.pids"
i=0; while [ ! -s "$r/watch/watch.pid" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
assert_exit "D32: while the watch script runs, pid-check exits 0" 0 "$h" watch "$r" pid-check
assert_exit "D32: a second watch script for the run is refused" 65 "$h" watch "$r" loop --cycles 1
wait "$lp" 2>/dev/null || true
assert_exit "D32: after the watch script ends, pid-check exits 1" 1 "$h" watch "$r" pid-check
assert_eq "D32: the plugin installs nothing into the operating system" "" "$(grep -lE 'launchctl|LaunchAgents' "$HO_PLUGIN_ROOT/lib/watch.sh" || true)"
