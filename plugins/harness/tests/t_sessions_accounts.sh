# Account labels (D37-SESSIONS-5, H-139; follow-up #89 item 1): the project config names a label
# per role, the user config maps a label to its command (or to the normal login), and no command
# is ever read or run from the project config.
. "$HO_TESTS_DIR/sessions-setup.sh"
p="$base/prompt.md"
cp "$proj/.harness/config.json" "$base/proj.keep.json"
cp "$user/config.json" "$base/user.keep.json"
setp() { jq "$1" "$base/proj.keep.json" > "$proj/.harness/config.json"; select_config "$proj"; }
setu() { jq "$1" "$base/user.keep.json" > "$user/config.json"; }
ulist='.accounts.list = {"work": {"env_command": "echo TEST_ACCT=work"}, "side": {"env_command": "echo TEST_ACCT=side"}, "plain": {"normal_login": true}}'
# The session number lives in a file: go runs inside $(...), so a shell variable would not count.
echo 0 > "$base/n"
nn() { cat "$base/n"; }
go() { # <role> [launch args...]: launch one session; prints its exit code
  local role=$1 rc=0 n; shift; n=$(($(nn) + 1)); echo "$n" > "$base/n"
  HO_FAKE_CLAUDE_SHOW_ENV=TEST_ACCT "$h" session "$run" launch --role "$role" --name "s$n" --cwd "$proj/src" --prompt "$p" "$@" >/dev/null 2>"$base/err" || rc=$?
  echo "$rc"
}
envline() { local i=0; while [ "$(grep -c "^env TEST_ACCT=" "$HO_FAKE_CLAUDE_LOG" 2>/dev/null || echo 0)" -lt "$1" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i + 1)); done; grep '^env TEST_ACCT=' "$HO_FAKE_CLAUDE_LOG" | tail -n 1; }
seen=0

# ---- a project label maps to the user command ----
setp '.accounts = {"roles": {"worker": "work"}}'
setu "$ulist"
assert_eq "D37-SESSIONS-5: a project label launches with the user's command for it" 0 "$(go worker)"
seen=$((seen + 1))
assert_eq "D37-SESSIONS-5: the session runs on that account" "env TEST_ACCT=work" "$(envline $seen)"
assert_eq "D37-SESSIONS-5: the record keeps the label" work "$(rec "s$(nn)" .account)"

# ---- the role lookup order ----
setp '.accounts = {"roles": {"worker": "work"}}'
setu "$ulist | .accounts.roles = {\"worker\": \"side\"}"
assert_eq "D37-SESSIONS-5: test launch" 0 "$(go worker)"; seen=$((seen + 1))
assert_eq "D37-SESSIONS-5: the project role value beats the user role value" "env TEST_ACCT=work" "$(envline $seen)"
setp '.accounts = {"roles": {"default": "work"}}'
setu "$ulist | .accounts.roles = {\"worker\": \"side\"}"
assert_eq "D37-SESSIONS-5: test launch" 0 "$(go worker)"; seen=$((seen + 1))
assert_eq "D37-SESSIONS-5: the user role value beats the project default" "env TEST_ACCT=side" "$(envline $seen)"

# ---- a command or a list in the project config is refused, and nothing runs ----
setu "$ulist"
setp ".accounts = {\"roles\": {\"worker\": \"work\"}, \"x\": {\"env_command\": \"touch $base/ran-a\"}}"
assert_eq "D37-SESSIONS-5: a non-empty env_command anywhere in the project accounts is refused (65)" 65 "$(go worker)"
assert_eq "D37-SESSIONS-5: that command never ran" no "$([ -e "$base/ran-a" ] && echo yes || echo no)"
assert_contains "D37-SESSIONS-5: the message says where the command belongs" "$(cat "$base/err")" "accounts.list.<label>.env_command"
setp ".accounts = {\"list\": {\"work\": {\"env_command\": \"touch $base/ran-b\"}}}"
assert_eq "D37-SESSIONS-5: an accounts.list in the project config is refused (65)" 65 "$(go worker)"
assert_eq "D37-SESSIONS-5: that command never ran either" no "$([ -e "$base/ran-b" ] && echo yes || echo no)"

# ---- the 0.6.0 template shape launches under the normal login ----
setp '.accounts = {"_note": "x", "validator": {"env_command": ""}}'
setu '.'
assert_eq "D37-SESSIONS-5: the 0.6.0 template shape (_note, empty env_command) launches" 0 "$(go worker)"
assert_eq "D37-SESSIONS-5: under the normal login, with no account recorded" null "$(rec "s$(nn)" .account)"

# ---- an unknown label ----
setp '.accounts = {"roles": {"worker": "ghost"}}'
setu "$ulist"
assert_eq "D37-SESSIONS-5: a project label missing from the user list is refused (65)" 65 "$(go worker)"
assert_contains "D37-SESSIONS-5: the message names the label" "$(cat "$base/err")" "ghost"
assert_contains "D37-SESSIONS-5: the message names the config and the key to fill in" "$(cat "$base/err")" "accounts.list.ghost.env_command"

# ---- normal_login ----
setp '.accounts = {"roles": {"worker": "plain"}}'
setu "$ulist"
: > "$base/ran-c"; rm -f "$base/ran-c"
assert_eq "D37-SESSIONS-5: a normal_login entry launches" 0 "$(go worker)"
assert_eq "D37-SESSIONS-5: it records the label" plain "$(rec "s$(nn)" .account)"
assert_eq "D37-SESSIONS-5: it runs no account command (no account line in the launcher)" "" "$(grep -F 'ho_acct=' "$run/launchers/s$(nn).sh" || true)"
setu '.accounts.list = {"both": {"env_command": "echo A=1", "normal_login": true}, "none": {}}'
setp '.accounts = {"roles": {"worker": "both", "validator": "none"}}'
assert_eq "D37-SESSIONS-5: an entry with both a command and normal_login is refused (65)" 65 "$(go worker)"
assert_eq "D37-SESSIONS-5: an entry with neither is refused (65)" 65 "$(go validator)"

# ---- labels ----
setp '.accounts = {"roles": {"worker": "-bad"}}'
assert_eq "D37-SESSIONS-5: a label that starts with - is refused (65)" 65 "$(go worker)"
setp '.accounts = {"roles": {"worker": 5}}'
assert_eq "D37-SESSIONS-5: a label that is not a string is refused (65)" 65 "$(go worker)"

# ---- no accounts anywhere ----
setp '.'
setu '.'
assert_eq "D37-SESSIONS-5: no accounts anywhere launches under the normal login" "0 null" "$(go worker) $(rec "s$(nn)" .account)"

# ---- #89 item 3: a failing command is logged by exit code only ----
setu '.accounts = {"roles": {"default": "bad"}, "list": {"bad": {"env_command": "echo SECRET-TEXT >&2; exit 7"}}}'
assert_eq "test setup: a failing account command refuses the launch" 65 "$(go worker)"
assert_contains "#89: the launcher log names the exit code" "$(cat "$run/logs/launcher.log" 2>/dev/null)" "exit 7"
assert_eq "#89: the launcher log holds none of the command's own output" "" "$(grep -F SECRET-TEXT "$run/logs/launcher.log" || true)"
