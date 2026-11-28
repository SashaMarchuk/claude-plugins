# Subscription limits per account, thresholds and actions (H-109, H-110, H-111, H-112; design
# D28, D28a, D28b, D29, S8-23). Readings are synthetic status line JSON built here.
# shellcheck source=sessions-setup.sh
. "$HO_TESTS_DIR/sessions-setup.sh"
pcfg="$proj/.harness/config.json"
ucfg="$user/config.json"
cp "$pcfg" "$base/p.orig.json"
cp "$ucfg" "$base/u.orig.json"
setp() { jq "$1" "$base/p.orig.json" > "$pcfg"; }
setu() { jq "$1" "$base/u.orig.json" > "$ucfg"; }
later=$(( $(date +%s) + 3600 ))
# feed <run> <account> <windows-json>: one status line reading, as a session would record it.
feed() { printf '{"model":{"id":"m"},"rate_limits":%s}' "$3" | HO_RUN_DIR=$1 HO_ACCOUNT=$2 "$h" limits record; }
win() { printf '{"used_percentage":%s,"resets_at":%s}' "$1" "${2:-$later}"; }
events() { jq -c "select(.kind == \"$2\")" "$1/ledger.jsonl" | wc -l | tr -d ' '; }
two='{"acct-a": {"normal_login": true}, "acct-b": {"normal_login": true}}'

# ---- H-109: every added account, every window it has ----
setu ".accounts = {list: $two}"
r=$("$h" run new)
out=$(feed "$r" acct-a "{\"five_hour\":$(win 12.5),\"seven_day\":$(win 40),\"odd_window\":$(win 7)}")
assert_eq "D28: with no status line of the user's own the record command prints nothing" "" "$out"
feed "$r" acct-b "{\"seven_day\":$(win 55)}" > /dev/null
st=$("$h" limits "$r" status)
assert_contains "H-109: both added accounts are read (first)" "$st" "acct-a	five_hour	12.5%"
assert_contains "H-109: both added accounts are read (second)" "$st" "acct-b	seven_day	55%"
assert_contains "H-109: a window that is neither 5-hour nor weekly is read under its own name" "$st" "acct-a	odd_window	7%"
assert_eq "H-109: an account with no 5-hour window is not an error" "1" "$(printf '%s\n' "$st" | grep -c '^acct-b')"
assert_eq "H-109: no window reads unknown when every account reported" "0" "$(printf '%s\n' "$st" | grep -c unknown)"

# ---- D28: a harness session keeps the user's own status line ----
mkdir -p "$HOME/.claude"
cat > "$base/userline.sh" <<'SH'
#!/bin/bash
m=$(jq -r .model.id)
printf 'my line \033[2m%s\033[0m  \xe2\x94\x80 tail' "$m"
SH
chmod +x "$base/userline.sh"
jq -n --arg c "$base/userline.sh" '{statusLine: {type: "command", command: $c}}' > "$HOME/.claude/settings.json"
want=$(printf '{"model":{"id":"m"}}' | "$base/userline.sh" | od -An -tx1)
got=$(feed "$r" acct-a "{\"seven_day\":$(win 41)}" | od -An -tx1)
assert_eq "D28: the user's own status line passes through byte for byte" "$want" "$got"
assert_eq "D28: the reading is still kept when the user's line runs" 41 "$(jq -r .windows.seven_day.used "$r/limits/acct-a.json")"
jq -n '{statusLine: {type: "command", command: "echo broken >&2; exit 3"}}' > "$HOME/.claude/settings.json"
rc=0; out=$(feed "$r" acct-a "{\"seven_day\":$(win 42)}") || rc=$?
assert_eq "D28: a failing user status line never fails the record command" 0 "$rc"
assert_eq "D28: a failing user status line never breaks the reading" 42 "$(jq -r .windows.seven_day.used "$r/limits/acct-a.json")"
jq -n --arg h "$h" '{statusLine: {type: "command", command: ($h + " limits record")}}' > "$HOME/.claude/settings.json"
feed "$r" acct-a "{\"seven_day\":$(win 40)}" > /dev/null
assert_eq "D28: a user line that is the record command itself does not call itself again" 40 "$(jq -r .windows.seven_day.used "$r/limits/acct-a.json")"
rm -f "$HOME/.claude/settings.json"

# ---- H-110 / H-112: thresholds are off unless set ----
feed "$r" acct-a "{\"five_hour\":$(win 99),\"seven_day\":$(win 99)}" > /dev/null
assert_exit "H-110: with thresholds off nothing pauses below a limit" 0 "$h" limits "$r" gate worker
assert_eq "H-112: with thresholds off no window is over a threshold (no reserve)" "0" "$("$h" limits "$r" check | grep -c '	over')"

# ---- H-110: 90% on any window pauses spawns and stops nothing ----
setp '.limits.thresholds = {"*": 90}'
r=$("$h" run new)
feed "$r" acct-a "{\"five_hour\":$(win 20),\"odd_window\":$(win 91.5)}" > /dev/null
feed "$r" acct-b "{\"seven_day\":$(win 10)}" > /dev/null
assert_exit "H-110: 90% on any window refuses a worker start (spawns paused)" 74 "$h" limits "$r" gate worker
assert_exit "H-110: the orchestrator is not a spawn the pause holds back" 0 "$h" limits "$r" gate orchestrator
r_main=$run; run=$r
rc=0; launch w-paused > "$base/paused.err" 2>&1 || rc=$?
run=$r_main
assert_eq "H-110: a worker launch in a paused run exits 74" 74 "$rc"
assert_contains "H-110: the refusal names the window and the threshold" "$(cat "$base/paused.err")" "acct-a odd_window 91.5% >= 90%"
assert_eq "H-110: the paused worker got no session record" "no" "$([ -e "$r/sessions/w-paused.json" ] && echo yes || echo no)"
assert_exit "H-110: a pause stops nothing (the run is not stopped)" 1 "$h" state "$r" stopped
assert_eq "H-110: a pause records no stop line" 0 "$(events "$r" stop)"
"$h" limits "$r" check > /dev/null
"$h" limits "$r" check > /dev/null
assert_eq "D28b: one crossing is one ledger line, not one per check" 1 "$(events "$r" limits-over)"
# The reading's reset time passes: the reading no longer counts, so the pause lifts.
feed "$r" acct-a "{\"odd_window\":$(win 95 $(( $(date +%s) - 5 )))}" > /dev/null
assert_exit "D28b: a window whose reset time passed reads unknown and the pause lifts" 0 "$h" limits "$r" gate worker
assert_contains "D28b: that window shows unknown, not OK" "$("$h" limits "$r" status)" "acct-a	odd_window	unknown"

# ---- H-110: each window has its own threshold; project beats user per window (D28a) ----
setp '.'
setu ".accounts = {list: $two} | .limits.thresholds = {five_hour: 80, seven_day: 90}"
r=$("$h" run new)
feed "$r" acct-a "{\"five_hour\":$(win 80),\"seven_day\":$(win 85)}" > /dev/null
feed "$r" acct-b "{\"seven_day\":$(win 10)}" > /dev/null
st=$("$h" limits "$r" check)
assert_contains "H-110: the 5-hour threshold at 80% triggers" "$st" "five_hour	80%	"
assert_eq "H-110: the weekly threshold at 90% triggers nothing at 85%" "0" "$(printf '%s\n' "$st" | grep seven_day | grep -c '	over')"
setp '.limits.thresholds = {five_hour: 95}'
assert_exit "D28a: the project setting for a window beats the user setting" 0 "$h" limits "$r" gate worker
setp '.limits.thresholds = {five_hour: 101}'
assert_exit "H-110: a threshold above 100% never triggers" 0 "$h" limits "$r" gate worker
setp '.limits.thresholds = {five_hour: {at: 50, action: "explode"}}'
assert_exit "H-110: an unknown action is a config error" 78 "$h" limits "$r" gate worker

# ---- H-110: the configured action runs ----
setu ".accounts = {list: $two}"
setp '.limits.thresholds = {seven_day: {at: 90, action: "soft_stop_step"}}'
r=$("$h" run new)
feed "$r" acct-a "{\"seven_day\":$(win 90)}" > /dev/null
feed "$r" acct-b "{\"seven_day\":$(win 1)}" > /dev/null
out=$("$h" limits "$r" check)
assert_contains "H-110: a soft-stop threshold records the soft stop and prints its text" "$out" "Soft stop: finish the step"
assert_eq "H-110: the soft stop is soft:step" "soft:step" "$("$h" state "$r" stop-state | jq -r .type)"
"$h" limits "$r" check > /dev/null
assert_eq "H-110: the same crossing records one stop only" 1 "$(events "$r" stop)"
setp '.limits.thresholds = {five_hour: {at: 95, action: "hard_stop"}}'
r=$("$h" run new)
feed "$r" acct-a "{\"five_hour\":$(win 96)}" > /dev/null
feed "$r" acct-b "{\"seven_day\":$(win 1)}" > /dev/null
out=$("$h" limits "$r" check)
assert_contains "H-110: a hard_stop threshold says it is not built yet" "$out" "hard_stop is not built yet"
assert_exit "H-110: until hard stops exist, hard_stop pauses spawns" 74 "$h" limits "$r" gate worker
assert_eq "H-110: the hard_stop fallback is recorded as a decision" 1 "$(events "$r" decision)"

# ---- H-111 / D28b: an unreadable limit does not stop work ----
setp '.limits.thresholds = {"*": 90}'
r=$("$h" run new)
feed "$r" acct-a "{\"seven_day\":$(win 30)}" > /dev/null
printf 'not json' | HO_RUN_DIR=$r HO_ACCOUNT=acct-b "$h" limits record > "$base/rec.out"; rc=$?
assert_eq "H-111: an unreadable status line never fails the status line command" 0 "$rc"
st=$("$h" limits "$r" status)
assert_contains "D28b: an account with no reading shows unknown in status" "$st" "acct-b	-	unknown"
"$h" limits "$r" check > /dev/null
"$h" limits "$r" check > /dev/null
assert_eq "D28b: unknown is recorded once in the run ledger" 1 "$(events "$r" limits-unknown)"
r_main=$run; run=$r
rc=0; launch w-unknown > /dev/null 2>&1 || rc=$?
run=$r_main
assert_eq "H-111: with a limit unknown a worker still starts" 0 "$rc"
args=$(grep -F -- "--session-id	$(rec w-unknown .session_id "$r")" "$HO_FAKE_CLAUDE_LOG" | head -n 1)
assert_contains "D28: the session starts with the status line settings file" "$args" "--settings	$r/status-line-settings.json"
assert_contains "D28: the status line command is the harness record command" "$(jq -r .statusLine.command "$r/status-line-settings.json")" "limits record"
assert_contains "D28: the launcher names the account the status line records under" "$(cat "$r/launchers/w-unknown.sh")" "export HO_ACCOUNT='default'"

# ---- H-112 / D29: no shipped reserve; S8-23: the endpoint read is off by default ----
tpl=$(cat "$HO_PLUGIN_ROOT"/templates/*-config.example.json)
assert_eq "H-112: the shipped configs hold no threshold value" "[]" "$(jq -sc '[.[] | .limits.thresholds // {} | to_entries[]]' "$HO_PLUGIN_ROOT"/templates/*-config.example.json)"
assert_eq "D29: the shipped configs hold no reserve setting" "0" "$(printf '%s' "$tpl" | grep -ci reserve)"
assert_eq "S8-23: the user template ships the endpoint read switched off" "false" "$(jq -r .limits.endpoint_read "$HO_PLUGIN_ROOT/templates/user-config.example.json")"
setu ".accounts = {list: {\"acct-c\": {\"normal_login\": true}}}"
setp ".limits.endpoint_read = true | .limits.endpoint_command = \"touch $base/endpoint-ran\""
r=$("$h" run new)
"$h" limits "$r" status > /dev/null
assert_eq "S8-23/D61: a project config cannot switch the endpoint read on" "no" "$([ -e "$base/endpoint-ran" ] && echo yes || echo no)"
setp '.'
setu ".accounts = {list: {\"acct-c\": {\"normal_login\": true}}} | .limits.endpoint_read = true | .limits.endpoint_command = \"printf '{\\\"windows\\\":{\\\"seven_day\\\":{\\\"used\\\":33,\\\"resets_at\\\":$later}}}'\""
assert_contains "S8-23: the opt-in endpoint read from the user config is used when no reading exists" "$("$h" limits "$r" status)" "acct-c	seven_day	33%"
