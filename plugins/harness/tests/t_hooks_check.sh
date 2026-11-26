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
