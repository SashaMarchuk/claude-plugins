# H-100 (interactive terminal sessions by default) and the design "Rebuild" reuse list:
# launcher generation (clean PATH, guarded cd, per-role account, fixed session ID) and one
# registry record per session. S8-27: identity is process ID plus session ID.
. "$HO_TESTS_DIR/sessions-setup.sh"
uuid_re='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

# ---- a default worker launch is an interactive session in a terminal ----------------
mkdir -p "$base/oldbin"
: > "$base/oldbin/harness-spawn.sh"
out=$(PATH=".:rel/bin:$base/oldbin:$PATH" launch w1)
assert_contains "H-100: launch reports the session" "$out" "name=w1"
assert_contains "H-100: the worker opens in a terminal, not in print mode" "$(calls)" "tmux new-session"
sid=$(rec w1 .session_id)
pid=$(rec w1 .pid)
assert_eq "H-100: the registry records the session as running" "running" "$(rec w1 .status)"
assert_eq "Rebuild launcher: the session ID is a fixed UUID" "yes" "$(printf '%s' "$sid" | grep -Eq "$uuid_re" && echo yes || echo no)"
assert_eq "S8-27: the registry holds the session's live process ID" "yes" "$(alive "$pid" && echo yes || echo no)"
assert_contains "S8-27: the recorded process is the session started with that session ID" "$(ps -o command= -p "$pid")" "$sid"
args=$(head -n 1 "$HO_FAKE_CLAUDE_LOG")
assert_contains "Rebuild launcher: the session starts with its fixed session ID" "$args" "--session-id	$sid"
assert_contains "H-100: the prompt file's text reaches the session" "$args" "do the work"
assert_eq "H-100: no print mode flag" "" "$(printf '%s' "$args" | tr '\t' '\n' | grep -x -- '-p' || true)"
assert_eq "Rebuild launcher: the registry record carries this run's ID" "$(basename "$run")" "$(rec w1 .run)"
assert_eq "Rebuild launcher: the registry records the terminal handle for addressing only" "yes" "$([ -n "$(rec w1 .handle)" ] && echo yes || echo no)"
assert_eq "Drop list: no terminal device is recorded as identity" "null" "$(rec w1 .tty)"

# ---- the launcher itself ---------------------------------------------------------
launcher=$(rec w1 .launcher)
path_line=$(grep '^export PATH=' "$launcher")
assert_eq "Rebuild launcher: PATH has no relative or empty entry" "" "$(printf '%s' "${path_line#export PATH=}" | tr -d "'" | tr ':' '\n' | grep -v '^/' || true)"
assert_eq "Rebuild launcher: PATH drops a folder that holds a 0.6.0 engine script" "" "$(printf '%s' "$path_line" | grep -F "$base/oldbin" || true)"
assert_contains "Rebuild launcher: the cd is guarded and stops the launch on failure" "$(grep '^cd ' "$launcher")" "|| ho_fatal"
assert_contains "Rebuild launcher: 0.6.0 variables are removed" "$(cat "$launcher")" "unset HARNESS_PROJECT"
assert_exit "Rebuild launcher: the generated launcher is valid bash" 0 bash -n "$launcher"

# ---- one registry record per session, each with process ID and session ID ------------
launch w2 >/dev/null
launch w3 >/dev/null
n=0 bad_recs="" pids="" sids=""
for f in "$run"/sessions/*.json; do
  n=$((n + 1))
  p=$(jq -r .pid "$f") s=$(jq -r .session_id "$f")
  if ! alive "$p" || ! printf '%s' "$s" | grep -Eq "$uuid_re" || ! ps -o command= -p "$p" | grep -qF -- "$s"; then
    bad_recs="$bad_recs $(basename "$f")"
  fi
  pids="$pids $p" sids="$sids $s"
done
assert_eq "S8-27: three launches give three registry records" "3" "$n"
assert_eq "S8-27: every record holds a live process ID and its own session ID" "" "$bad_recs"
assert_eq "S8-27: process IDs are distinct" "3" "$(printf '%s\n' $pids | sort -u | wc -l | tr -d ' ')"
assert_eq "S8-27: session IDs are distinct" "3" "$(printf '%s\n' $sids | sort -u | wc -l | tr -d ' ')"
assert_exit "Rebuild launcher: a second launch under a registered name is refused" 65 launch w1
assert_eq "Rebuild launcher: the refused duplicate leaves the record unchanged" "$sid" "$(rec w1 .session_id)"

# ---- a session named like the iTerm2 window map is an ordinary session ---------------------
jq '.terminal.app = "iterm2"' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
launch windows >/dev/null
launch windows-b >/dev/null
assert_contains "Rebuild launcher: a session named windows is listed" "$("$h" session "$run" list)" "windows	worker	running"
assert_eq "Rebuild launcher: its record is a session record" "windows" "$(rec windows .name)"
jq '.terminal.app = "tmux"' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"

# ---- resume by ID keeps the given session ID ----------------------------------------
rid=0b9e4e1c-5d4f-4a8e-9a43-0123456789ab
"$h" session "$run" launch --role worker --name w4 --cwd "$proj/src" --resume "$rid" >/dev/null
assert_eq "Rebuild launcher: a resume launch records the given session ID" "$rid" "$(rec w4 .session_id)"
assert_contains "Rebuild launcher: a resume launch starts the runtime's resume form" "$(grep -F "$rid" "$HO_FAKE_CLAUDE_LOG" | head -n 1)" "--resume	$rid"
assert_exit "Rebuild launcher: a resume ID that is not a UUID is refused" 65 "$h" session "$run" launch --role worker --name w5 --cwd "$proj/src" --resume 'x;y'

# ---- the session's account folder is the caller's, never the terminal's (issue #119) --------
# An iTerm2 tab starts a fresh login shell, and a tmux server keeps the environment of its
# first start. So the launcher sets the runtime's account variables (account_env in the
# runtime data) to the caller's values, or removes them when the caller has none.
ax="$base/acct-x"
mkdir -p "$ax"
jq -n --arg p "$proj" '.projects[$p].hasTrustDialogAccepted = true' > "$ax/.claude.json"
# envlog <name>: what the session process saw (the fake claude logs it right after its argv).
envlog() { grep -A1 -F -- "--session-id	$(rec "$1" .session_id)" "$HO_FAKE_CLAUDE_LOG" | grep -m1 '^env CLAUDE_CONFIG_DIR=' || true; }
CLAUDE_CONFIG_DIR=$ax HO_FAKE_TERM_ENV="CLAUDE_CONFIG_DIR=$base/acct-term" HO_FAKE_CLAUDE_SHOW_ENV=CLAUDE_CONFIG_DIR launch e1 >/dev/null
assert_eq "#119: the session gets the caller's account folder, not the terminal's other one" "env CLAUDE_CONFIG_DIR=$ax" "$(envlog e1)"
assert_eq "#119: transcript_root is the caller's account folder" "$ax" "$(rec e1 .transcript_root)"
assert_contains "#119: the launcher sets the account folder itself" "$(cat "$(rec e1 .launcher)")" "export CLAUDE_CONFIG_DIR='$ax'"
CLAUDE_CONFIG_DIR=$ax HO_FAKE_TERM_ENV="-CLAUDE_CONFIG_DIR" HO_FAKE_CLAUDE_SHOW_ENV=CLAUDE_CONFIG_DIR launch e2 >/dev/null
assert_eq "#119: the session gets the caller's account folder when the terminal has none" "env CLAUDE_CONFIG_DIR=$ax" "$(envlog e2)"
assert_eq "#119: transcript_root follows it" "$ax" "$(rec e2 .transcript_root)"
HO_FAKE_TERM_ENV="CLAUDE_CONFIG_DIR=$base/acct-stale" HO_FAKE_CLAUDE_SHOW_ENV=CLAUDE_CONFIG_DIR launch e3 >/dev/null
assert_eq "#119: a caller with no account folder: the terminal's stale one is removed" "env CLAUDE_CONFIG_DIR=" "$(envlog e3)"
assert_eq "#119: transcript_root is then the runtime's default folder" "$HOME/.claude" "$(rec e3 .transcript_root)"
assert_contains "#119: the launcher removes the variable" "$(cat "$(rec e3 .launcher)")" "unset CLAUDE_CONFIG_DIR"
cp "$user/config.json" "$base/user.keep.json"
jq --arg c "echo CLAUDE_CONFIG_DIR=$base/acct-a" '.accounts = {roles: {default: "acc"}, list: {acc: {env_command: $c}}}' "$base/user.keep.json" > "$user/config.json"
CLAUDE_CONFIG_DIR=$ax HO_FAKE_TERM_ENV="CLAUDE_CONFIG_DIR=$base/acct-term" HO_FAKE_CLAUDE_SHOW_ENV=CLAUDE_CONFIG_DIR launch e4 >/dev/null
assert_eq "#119: the role's account command still wins over the caller's folder" "env CLAUDE_CONFIG_DIR=$base/acct-a" "$(envlog e4)"
assert_eq "#119: transcript_root is the account command's folder" "$base/acct-a" "$(rec e4 .transcript_root)"
jq --arg c "echo HOME=$base/acct-home" '.accounts = {roles: {default: "acc"}, list: {acc: {env_command: $c}}}' "$base/user.keep.json" > "$user/config.json"
CLAUDE_CONFIG_DIR=$ax HO_FAKE_TERM_ENV="CLAUDE_CONFIG_DIR=$base/acct-term" HO_FAKE_CLAUDE_SHOW_ENV=CLAUDE_CONFIG_DIR launch e5 >/dev/null
assert_eq "#119: an account that sets only HOME gets no folder from the caller or the terminal" "env CLAUDE_CONFIG_DIR=" "$(envlog e5)"
assert_eq "#119: transcript_root is then the default folder under the account's HOME" "$base/acct-home/.claude" "$(rec e5 .transcript_root)"
jq '.accounts = {roles: {default: "acc"}, list: {acc: {env_command: "echo \"CLAUDE_CONFIG_DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude-work}\""}}}' "$base/user.keep.json" > "$user/config.json"
CLAUDE_CONFIG_DIR=$ax HO_FAKE_TERM_ENV="CLAUDE_CONFIG_DIR=$base/acct-term" HO_FAKE_CLAUDE_SHOW_ENV=CLAUDE_CONFIG_DIR launch e9 >/dev/null
assert_eq "#119: an account command that falls back on the variable gets its own folder in the launcher" "env CLAUDE_CONFIG_DIR=$HOME/.claude-work" "$(envlog e9)"
cp "$base/user.keep.json" "$user/config.json"
bad_dir="$base/a
b"
assert_exit "#119: an account folder with a line break is refused" 65 env CLAUDE_CONFIG_DIR="$bad_dir" "$h" session "$run" launch --role worker --name e6 --cwd "$proj/src" --prompt "$base/prompt.md"
assert_exit "#119: a relative account folder is refused" 65 env CLAUDE_CONFIG_DIR=rel/dir "$h" session "$run" launch --role worker --name e7 --cwd "$proj/src" --prompt "$base/prompt.md"
assert_eq "#119: the refusal never prints the value" "" "$(env CLAUDE_CONFIG_DIR=rel/secret-x "$h" session "$run" launch --role worker --name e8 --cwd "$proj/src" --prompt "$base/prompt.md" 2>&1 | grep -F secret-x || true)"
assert_eq "#119: the record keeps the caller's account folder" "$ax" "$(rec e1 '.account_env.CLAUDE_CONFIG_DIR')"
assert_eq "#119: the record shows a caller with none as null" "true" "$(rec e3 '.account_env | has("CLAUDE_CONFIG_DIR") and .CLAUDE_CONFIG_DIR == null')"
assert_eq "#119: with an account the record keeps no caller folder" "null" "$(rec e4 '.account_env')"
# A profile without account_env falls back to config_dir.env and transcript.root_env.
printf '%s\n' '{"config_dir": {"env": "FAKE_HOME_X"}, "transcript": {"root_env": "FAKE_ROOT_Y"}}' > "$base/rt-noaenv.json"
assert_eq "#119: without account_env the folder variables of the profile are used" "FAKE_HOME_X	/x FAKE_ROOT_Y " "$(FAKE_HOME_X=/x bash -c '. "$1/lib/sessions.sh" 2>/dev/null; ho_session_account_env "$2"' _ "$HO_PLUGIN_ROOT" "$base/rt-noaenv.json" | tr '\n' ' ')"

# ---- model chain a|b: a start failure falls through, the PID is the one that runs ------
jq '.models.worker = "m-bad | m-good"' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
HO_FAKE_CLAUDE_FAIL_MODEL=m-bad launch w6 >/dev/null
assert_contains "Rebuild model chain: the first model is tried first" "$(grep -F "$(rec w6 .session_id)" "$HO_FAKE_CLAUDE_LOG" | head -n 1)" "--model	m-bad"
assert_contains "Rebuild model chain: a start failure falls through to the next model" "$(grep -F "$(rec w6 .session_id)" "$HO_FAKE_CLAUDE_LOG" | tail -n 1)" "--model	m-good"
w6pid=$(awk '{print $1}' "$run/sessions/w6.pid")
assert_contains "S8-27: after a fallback the launcher reports the running process" "$(ps -o command= -p "$w6pid")" "m-good"
# Codex review of #90 (P2): the first model passes the boot check, then fails within the
# grace time; list shows the process that runs now, not the first one.
HO_FAKE_CLAUDE_FAIL_MODEL=m-bad HO_FAKE_CLAUDE_FAIL_AFTER=2 launch w11 >/dev/null
first=$(rec w11 .pid)
i=0; now=$first
while [ "$now" = "$first" ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); now=$(awk '{print $1}' "$run/sessions/w11.pid"); done
assert_eq "S8-27: after a late fallback the launcher reports a new process" "yes" "$([ "$now" != "$first" ] && alive "$now" && echo yes || echo no)"
assert_contains "S8-27: session list shows the process that runs now" "$("$h" session "$run" list | grep '^w11	')" "	running	$now	"
assert_eq "S8-27: after list the registry holds the process that runs now" "$now" "$(rec w11 .pid)"
jq '.session.boot_timeout_seconds = 3' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
assert_exit "Rebuild model chain: a launch where every model fails to start reports it" 69 env HO_FAKE_CLAUDE_FAIL_MODEL=m-only "$h" session "$run" launch --role worker --name w10 --cwd "$proj/src" --prompt "$base/prompt.md" --model m-only
assert_eq "Rebuild model chain: the failed launch is recorded as boot-failed" "boot-failed" "$(rec w10 .status)"
assert_eq "H-105: a boot-failed launch stops its launcher from starting the session later" yes "$([ -f "$run/sessions/w10.closing" ] && echo yes)"
assert_contains "Rebuild model chain: the launcher leaves a start-failed note that list shows" "$("$h" session "$run" list)" "start failed"
assert_exit "Rebuild model chain: an empty chain is refused" 65 launch w7 --model ' | '
assert_exit "Rebuild model chain: a model name with shell characters is refused" 65 launch w8 --model 'a;b'

# ---- the session record keeps the ticket the session works on (H-086, D25a) ---------------
# A soft:ticket stop decides from the record's ticket whether this session's work may go on.
launch wt --ticket 07 >/dev/null
assert_eq "H-086: the running session's record keeps its ticket" "running 7" "$(rec wt '"\(.status) \(.ticket)"')"
assert_eq "H-086: a session launched with no ticket records none" "null" "$(rec w1 .ticket)"
"$h" session "$run" close wt >/dev/null 2>&1 || true

# ---- a stopped run launches nothing -------------------------------------------------
"$h" state "$run" stop "test" >/dev/null
before=$(calls | wc -l)
assert_exit "Rebuild launcher: a launch during a stop is refused" 75 launch w9
assert_eq "Rebuild launcher: a refused launch opens no terminal" "$before" "$(calls | wc -l)"

# ---- a model name never becomes a command-line flag (PR #90 review, D37-FLOW-8) --------
# Checked on the parser itself: by this point the run above is stopped, so a launch would
# end at the STOP check before it reads the model.
for bad in "--dangerously-skip-permissions" "-p" "m-good|--permission-mode"; do
  rc=0; bash -c '. "$1/lib/sessions.sh" 2>/dev/null; ho_model_chain "$2"' _ "$HO_PLUGIN_ROOT" "$bad" >/dev/null 2>&1 || rc=$?
  assert_eq "Rebuild model chain: a model in [$bad] that starts with - is refused (exit 65)" "65" "$rc"
done
assert_eq "Rebuild model chain: a normal chain still parses" "m-a m-b " "$(bash -c '. "$1/lib/sessions.sh" 2>/dev/null; ho_model_chain "m-a|m-b"' _ "$HO_PLUGIN_ROOT" | tr '\n' ' ')"
