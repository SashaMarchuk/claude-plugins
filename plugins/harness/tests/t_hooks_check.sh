# The start check names other hooks with no time limit (H-089 scenario "Another hook in the
# user's settings has no time limit"; design D42l). It reads the settings the sessions will load,
# names each hook with no time limit or one above preflight.hook_timeout_max_seconds (default
# 10) in one attention notice, records one owner action, never edits the settings, and by
# default lets the run start (preflight.hooks: warn); "stop" refuses the start.
# shellcheck source=sessions-setup.sh
. "$HO_TESTS_DIR/sessions-setup.sh"
chk() { "$h" session "$run" hooks-check "$@"; }
cfg() { jq "$1" "$proj/.harness/config.json" > "$base/cfg.json" && mv "$base/cfg.json" "$proj/.harness/config.json"; }
owner_actions() { grep -c '"kind":"owner-action"' "$run/ledger.jsonl" 2>/dev/null || true; }

# ---- no settings with hooks: nothing to name ----
out=$(chk 2>&1) && rc=0 || rc=$?
assert_eq "H-089 (D42l): with no hooks in the settings the check passes" "0" "$rc"
assert_contains "H-089 (D42l): the check says the hooks are fine" "$out" "hooks OK"
assert_eq "H-089 (D42l): no owner action when nothing is found" "0" "$(owner_actions)"

# ---- user and project settings with hooks: one notice, one owner action, no edit ----
mkdir -p "$HOME/.claude" "$proj/.claude"
cat > "$HOME/.claude/settings.json" <<'JSON'
{"hooks": {
  "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "fast-check", "timeout": 5}]}],
  "Stop": [{"hooks": [{"type": "command", "command": "no-limit-hook --token SECRETVALUE"}]}],
  "SessionStart": [{"hooks": [{"type": "command", "command": "slow-hook", "timeout": 30}]}]}}
JSON
cat > "$proj/.claude/settings.local.json" <<'JSON'
{"hooks": {"PostToolUse": [{"hooks": [{"type": "command", "command": "project-hook", "timeout": 600}]}]}}
JSON
sum_before=$(cksum "$HOME/.claude/settings.json" "$proj/.claude/settings.local.json")
out=$(chk 2>&1) && rc=0 || rc=$?
assert_eq "H-089 (D42l): by default the run still starts (exit 0)" "0" "$rc"
assert_contains "H-089 (D42l): the notice is an attention notice" "$out" "attention"
assert_contains "H-089 (D42l): a hook with no time limit is named" "$out" "Stop no-limit-hook"
assert_contains "H-089 (D42l): a hook above the maximum of 10 s is named" "$out" "SessionStart slow-hook (timeout 30)"
assert_contains "H-089 (D42l): a hook in the project's settings is named" "$out" "PostToolUse project-hook (timeout 600)"
assert_eq "H-089 (D42l): a hook within the maximum is not named" "" "$(printf '%s' "$out" | grep fast-check || true)"
assert_eq "H-089 (D42l): one notice names three hooks" "3" "$(printf '%s\n' "$out" | grep -c '^  ' || true)"
assert_eq "H-089 (D42l): exactly one owner action is recorded" "1" "$(owner_actions)"
assert_eq "H-089 (D42l): the settings are never edited" "$sum_before" "$(cksum "$HOME/.claude/settings.json" "$proj/.claude/settings.local.json")"
assert_eq "H-089: no hook command text reaches the run ledger" "0" "$(grep -c 'SECRETVALUE\|no-limit-hook' "$run/ledger.jsonl" || true)"

# ---- the maximum and the mode are settings ----
cfg '.preflight.hook_timeout_max_seconds = 700'
out=$(chk 2>&1) || true
assert_eq "H-089 (D42l): preflight.hook_timeout_max_seconds moves the maximum" "1" "$(printf '%s\n' "$out" | grep -c '^  ' || true)"
cfg 'del(.preflight) | .preflight.hooks = "stop"'
out=$(chk 2>&1) && rc=0 || rc=$?
assert_eq "H-089 (D42l): preflight.hooks stop refuses the start (exit 69)" "69" "$rc"
assert_eq "H-089 (D42l): stop still edits nothing" "$sum_before" "$(cksum "$HOME/.claude/settings.json" "$proj/.claude/settings.local.json")"
cfg '.preflight.hooks = "maybe"'
assert_exit "H-089 (D42l): a preflight.hooks value other than warn or stop is refused (exit 78)" 78 chk
cfg 'del(.preflight)'

# ---- a settings file that cannot be read is named, never skipped silently ----
printf 'not json' > "$proj/.claude/settings.json"
out=$(chk 2>&1) && rc=0 || rc=$?
assert_eq "H-089: an unreadable settings file does not stop a warn check" "0" "$rc"
assert_contains "H-089 (field note I1): an unreadable settings file is named as not read" "$out" "cannot be read"
rm -f "$proj/.claude/settings.json"

# ---- the runtime's config folder variable moves the user settings ----
mkdir -p "$base/cfgdir"
printf '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "moved-hook"}]}]}}\n' > "$base/cfgdir/settings.json"
out=$(CLAUDE_CONFIG_DIR="$base/cfgdir" "$h" session "$run" hooks-check 2>&1) || true
assert_contains "H-089 (D42l): the user settings follow the runtime's config folder variable" "$out" "moved-hook"

# ---- a settings file the check cannot read is a finding, never "hooks OK" (D42l) ----
# Its hooks were not checked, so the check cannot say they are fine.
mkdir -p "$base/away"
mv "$HOME/.claude/settings.json" "$base/away/user.json"
mv "$proj/.claude/settings.local.json" "$base/away/local.json"
printf '{bad' > "$proj/.claude/settings.local.json"
n0=$(owner_actions)
out=$(chk 2>&1) && rc=0 || rc=$?
assert_eq "H-089 (D42l): an unreadable settings file alone does not stop a warn check (exit 0)" "0 no" \
  "$rc $(printf '%s' "$out" | grep -q 'hooks OK' && echo yes || echo no)"
assert_eq "H-089 (D42l): an unreadable settings file records one owner action" "$((n0 + 1))" "$(owner_actions)"
cfg '.preflight.hooks = "stop"'
assert_exit "H-089 (D42l): with preflight.hooks stop an unreadable settings file refuses the start (exit 69)" 69 chk
printf '{"hooks": []}\n' > "$proj/.claude/settings.local.json"
out=$(chk 2>&1) && rc=0 || rc=$?
assert_eq "H-089 (D42l): settings whose hooks are not an object refuse a stop check (exit 69)" "69" "$rc"
assert_contains "H-089 (D42l): the notice says the hooks are not an object" "$out" "hooks is not an object"
cfg 'del(.preflight)'
rm -f "$proj/.claude/settings.local.json"
mv "$base/away/user.json" "$HOME/.claude/settings.json"
mv "$base/away/local.json" "$proj/.claude/settings.local.json"

# ---- issue #129 item 4: the settings of the account folder the sessions get ----
# With an account per role, a session's config folder comes from the account command, never
# from the caller's variable (the launch rule, issue #119). The check reads that folder, for
# every role, each folder once.
mkdir -p "$base/caller-cfg" "$base/acct-orch" "$base/acct-work"
printf '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "caller-only-hook"}]}]}}\n' > "$base/caller-cfg/settings.json"
printf '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "orch-acct-hook"}]}]}}\n' > "$base/acct-orch/settings.json"
printf '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "work-acct-hook"}]}]}}\n' > "$base/acct-work/settings.json"
cp "$user/config.json" "$base/user-config.keep"
jq -n --arg o "$base/acct-orch" --arg w "$base/acct-work" '{schemaVersion: 2, runtime: {main: "claude-code"},
  accounts: {roles: {default: "orch", worker: "work"},
    list: {orch: {env_command: ("echo CLAUDE_CONFIG_DIR=" + $o)}, work: {env_command: ("echo CLAUDE_CONFIG_DIR=" + $w)}}}}' > "$user/config.json"
out=$(CLAUDE_CONFIG_DIR="$base/caller-cfg" "$h" session "$run" hooks-check 2>&1) || true
assert_contains "#129 H-089 (D42l): the orchestrator's account folder is read" "$out" "orch-acct-hook"
assert_contains "#129 H-089 (D42l): the worker's account folder is read" "$out" "work-acct-hook"
assert_eq "#129 H-089 (D42l): the caller's folder, which no session gets, is not read" "" "$(printf '%s' "$out" | grep caller-only-hook || true)"
assert_eq "#129 H-089 (D42l): each folder is read once" 1 "$(printf '%s\n' "$out" | grep -c 'orch-acct-hook' || true)"
jq '.accounts.list.orch.env_command = "exit 3"' "$user/config.json" > "$base/u.t" && mv "$base/u.t" "$user/config.json"
out=$(CLAUDE_CONFIG_DIR="$base/caller-cfg" "$h" session "$run" hooks-check 2>&1) && rc=0 || rc=$?
assert_eq "#129 H-089: an account whose folder cannot be worked out is a finding, never hooks OK" "0 no" \
  "$rc $(printf '%s' "$out" | grep -q 'hooks OK' && echo yes || echo no)"
assert_contains "#129 H-089: the notice names the role whose settings were not checked" "$out" "role orchestrator"
mv "$base/user-config.keep" "$user/config.json"
