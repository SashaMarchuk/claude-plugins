# Acceptance (issue #40): a launcher with a wrong role, account or folder cannot be produced.
# Design "Rebuild" reuse list: guarded cd, per-role account. Account mismatch rules are the
# agent decision recorded for T7 (accounts come from the user config only).
. "$HO_TESTS_DIR/sessions-setup.sh"

# refused <name> <test-name> <code> <launch args...>: the launch exits <code>, and no launcher,
# no registry record and no terminal call are left behind.
refused() {
  local name=$1 what=$2 code=$3 rc=0 before
  shift 3
  before=$(calls | wc -l)
  "$h" session "$run" launch --name "$name" "$@" >/dev/null 2>&1 || rc=$?
  assert_eq "$what: generation fails" "$code" "$rc"
  assert_eq "$what: no launcher is written" "no" "$([ -e "$run/launchers/$name.sh" ] && echo yes || echo no)"
  assert_eq "$what: no registry record is left" "no" "$([ -e "$run/sessions/$name.json" ] && echo yes || echo no)"
  assert_eq "$what: no terminal is opened" "$before" "$(calls | wc -l)"
}
p="$base/prompt.md"

# ---- wrong role ---------------------------------------------------------------------
refused r1 "Rebuild launcher wrong role (admin)" 65 --role admin --cwd "$proj/src" --prompt "$p"
refused r2 "Rebuild launcher missing role" 64 --cwd "$proj/src" --prompt "$p"
refused r3 "Rebuild launcher role with shell text" 65 --role 'worker;id' --cwd "$proj/src" --prompt "$p"

# ---- wrong folder -------------------------------------------------------------------
mkdir -p "$base/outside" "$proj/src/a\$(id)"
ln -s "$base/outside" "$proj/link-out"
refused f1 "Rebuild launcher folder outside the project" 65 --role worker --cwd "$base/outside" --prompt "$p"
refused f2 "Rebuild launcher missing folder" 65 --role worker --cwd "$proj/missing" --prompt "$p"
refused f3 "Rebuild launcher relative folder" 65 --role worker --cwd proj/src --prompt "$p"
refused f4 "Rebuild launcher symlink out of the project" 65 --role worker --cwd "$proj/link-out" --prompt "$p"
refused f5 "Rebuild launcher home folder" 65 --role worker --cwd "$HOME" --prompt "$p"
refused f6 "Rebuild launcher dot-dot escape" 65 --role worker --cwd "$proj/src/../../outside" --prompt "$p"
refused f7 "Rebuild launcher missing prompt file" 65 --role worker --cwd "$proj/src" --prompt "$base/none.md"
refused 'Bad Name' "Rebuild launcher bad session name" 65 --role worker --cwd "$proj/src" --prompt "$p"

# A folder name with shell text is inside the project, so it is allowed, but it can only
# ever be a literal folder name in the launcher.
HO_FAKE_CLAUDE_SHOW_ENV=PWD "$h" session "$run" launch --role worker --name f9 --cwd "$proj/src/a\$(id)" --prompt "$p" >/dev/null
assert_eq "Rebuild launcher guarded cd: shell text in a folder name stays literal" "env PWD=$(cd -P "$proj/src/a\$(id)" && pwd)" \
  "$(grep '^env PWD=' "$HO_FAKE_CLAUDE_LOG" | tail -n 1)"

# ---- wrong account ------------------------------------------------------------------
cat > "$user/config.json" <<'JSON'
{"schemaVersion": 2, "runtime": {"main": "claude-code"},
 "accounts": {"roles": {"default": "main", "validator": "second", "question": "ghost", "watcher": "broken", "orchestrator": "junk"},
              "list": {"main": {"env_command": "echo TEST_ACCT=main"},
                       "second": {"env_command": "printf 'export TEST_ACCT=\"second\"\\n'"},
                       "broken": {"env_command": "exit 3"},
                       "junk": {"env_command": "echo not an assignment"}}}}
JSON
cp "$user/config.json" "$base/u.json"
jq '.accounts.roles.default = "a$(touch x)"' "$base/u.json" > "$user/config.json"
refused a0 "Rebuild per-role account: an account name with shell text" 65 --role worker --cwd "$proj/src" --prompt "$p"
cp "$base/u.json" "$user/config.json"
refused a1 "Rebuild per-role account: a worker asked to run on the validator's account" 65 --role worker --account second --cwd "$proj/src" --prompt "$p"
refused a2 "Rebuild per-role account: a role mapped to an unknown account" 65 --role question --cwd "$proj/src" --prompt "$p"
refused a3 "Rebuild per-role account: an account command that fails" 65 --role watcher --cwd "$proj/src" --prompt "$p"
refused a4 "Rebuild per-role account: an account command that prints no assignment" 65 --role orchestrator --cwd "$proj/src" --prompt "$p"
HO_FAKE_CLAUDE_SHOW_ENV=TEST_ACCT "$h" session "$run" launch --role validator --name a5 --cwd "$proj/src" --prompt "$p" >/dev/null
assert_eq "Rebuild per-role account: the validator runs on its own account" "env TEST_ACCT=second" "$(grep '^env TEST_ACCT=' "$HO_FAKE_CLAUDE_LOG" | tail -n 1)"
assert_eq "Rebuild per-role account: the registry names the account" "second" "$(jq -r .account "$run/sessions/a5.json")"
HO_FAKE_CLAUDE_SHOW_ENV=TEST_ACCT "$h" session "$run" launch --role worker --account main --name a6 --cwd "$proj/src" --prompt "$p" >/dev/null
assert_eq "Rebuild per-role account: a worker on the default account" "env TEST_ACCT=main" "$(grep '^env TEST_ACCT=' "$HO_FAKE_CLAUDE_LOG" | tail -n 1)"
assert_eq "Rebuild per-role account: the account command's output is not written into the launcher" "" "$(grep -F 'TEST_ACCT=second' "$run/launchers/a5.sh" || true)"

# Accounts in the project config (inside the repository) are refused, not silently used.
jq '.accounts = {"roles": {"default": "main"}, "list": {"main": {"env_command": "echo TEST_ACCT=repo"}}}' "$proj/.harness/config.json" > "$base/c.json"
mv "$base/c.json" "$proj/.harness/config.json"
refused a7 "Rebuild per-role account: accounts set in the project config" 65 --role worker --cwd "$proj/src" --prompt "$p"
