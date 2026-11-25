# D37-FLOW-8 (trust boundary for committed config), interim fail-closed step until the local
# approval record exists (Codex security review of #90): the session launcher never takes the
# permission mode or the runtime binary from the project.
. "$HO_TESTS_DIR/sessions-setup.sh"
set_cfg() { jq "$2" "$1" > "$base/c.json" && mv "$base/c.json" "$1"; }
pcfg="$proj/.harness/config.json"
ucfg="$user/config.json"

# ---- permission mode: user config or shipped default only ----------------------------
set_cfg "$ucfg" '.session.permissions = "dontAsk"'
set_cfg "$pcfg" '.session.permissions = "bypass"'
err=$(launch p1 2>&1 >/dev/null; echo "rc=$?")
assert_contains "D37-FLOW-8: a project permission mode refuses the launch (exit 65)" "$err" "rc=65"
assert_contains "D37-FLOW-8: the refusal says to move the mode to the user config" "$err" "user config"
assert_eq "D37-FLOW-8: a refused permission mode writes no launcher" "no" "$([ -e "$run/launchers/p1.sh" ] && echo yes || echo no)"
assert_eq "D37-FLOW-8: a refused permission mode writes no registry record" "no" "$([ -e "$run/sessions/p1.json" ] && echo yes || echo no)"
assert_eq "D37-FLOW-8: a refused permission mode starts no runtime" "" "$(grep -F -- '-n	ho-worker-p1' "$HO_FAKE_CLAUDE_LOG" 2>/dev/null || true)"

set_cfg "$pcfg" '.session.permissions = ""'
launch p2 >/dev/null
assert_contains "D37-FLOW-8: an empty project placeholder is ignored; the user mode is used" "$(grep -F "$(rec p2 .session_id)" "$HO_FAKE_CLAUDE_LOG" | head -n 1)" "--permission-mode	dontAsk"

set_cfg "$pcfg" 'del(.session.permissions)'
launch p3 >/dev/null
args=$(grep -F "$(rec p3 .session_id)" "$HO_FAKE_CLAUDE_LOG" | head -n 1)
assert_contains "D37-FLOW-8: the user mode dontAsk reaches the session" "$args" "--permission-mode	dontAsk"
assert_eq "D37-FLOW-8: the user mode dontAsk gives no bypass flag" "" "$(printf '%s' "$args" | tr '\t' '\n' | grep -x -- '--dangerously-skip-permissions' || true)"

# ---- runtime binary: never a file inside the project, its worktrees folder or a worktree ----
# stub <dir>: an executable claude that only leaves a marker file when it runs.
stub() {
  mkdir -p "$1"
  printf '%s\n' '#!/bin/sh' "touch \"$base/stub-ran\"" 'exit 0' > "$1/claude"
  chmod 755 "$1/claude"
}
refused() {
  local name=$1 dir=$2 out
  out=$(PATH="$dir:$PATH" launch "$name" 2>&1 >/dev/null; echo "rc=$?")
  assert_contains "$3: refused (exit 65)" "$out" "rc=65"
  assert_contains "$3: the refusal names the path" "$out" "$dir/claude"
  assert_eq "$3: the project binary never ran" "no" "$([ -e "$base/stub-ran" ] && echo yes || echo no)"
  assert_eq "$3: no launcher is written" "no" "$([ -e "$run/launchers/$name.sh" ] && echo yes || echo no)"
}
stub "$proj/bin"
refused b1 "$proj/bin" "D37-FLOW-8: a claude in a project bin folder first on PATH"

git -C "$proj" init -q
git -C "$proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$proj" worktree add -q "$base/lane-wt" -b lane 2>/dev/null
stub "$base/lane-wt/bin"
refused b2 "$base/lane-wt/bin" "D37-FLOW-8: a claude inside a git worktree of the project"

set_cfg "$pcfg" '.repos = [{"name": "app", "path": ".", "worktrees_dir": "../wts"}]'
stub "$base/wts/x/bin"
refused b3 "$base/wts/x/bin" "D37-FLOW-8: a claude inside the configured worktrees folder"

# A symlink to the project binary from outside is refused too.
mkdir -p "$base/linkbin"
ln -s "$proj/bin/claude" "$base/linkbin/claude"
out=$(PATH="$base/linkbin:$PATH" launch b4 2>&1 >/dev/null; echo "rc=$?")
assert_contains "D37-FLOW-8: a symlink outside the project to a project binary is refused" "$out" "rc=65"

mkdir -p "$base/outbin"
printf '%s\n' '#!/bin/sh' "exec \"$HO_TESTS_DIR/fake-bin/claude\" \"\$@\"" > "$base/outbin/claude"
chmod 755 "$base/outbin/claude"
PATH="$base/outbin:$PATH" launch b5 >/dev/null
assert_eq "D37-FLOW-8: a runtime binary outside the project still launches" "running" "$(rec b5 .status)"
assert_eq "D37-FLOW-8: the launcher runs the binary outside the project" "yes" "$(grep -qF "$base/outbin/claude" "$run/launchers/b5.sh" && echo yes || echo no)"
