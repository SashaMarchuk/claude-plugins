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

# A user value false is a value, not "unset": it is refused, never replaced by bypass
# (PR #90 re-check, B2).
set_cfg "$ucfg" '.session.permissions = false'
set_cfg "$pcfg" 'del(.session.permissions)'
rc=0; launch pf >/dev/null 2>&1 || rc=$?
assert_eq "D37-FLOW-8: a user session.permissions false is refused (exit 65), never bypass" "65" "$rc"
assert_eq "D37-FLOW-8: no launch with false got the bypass flag" "" "$(grep -F -- '--dangerously-skip-permissions' "$HO_FAKE_CLAUDE_LOG" | grep -F "pf" || true)"
set_cfg "$ucfg" '.session.permissions = "dontAsk"'
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
refused() { # the project folder is dropped from PATH, so its binary is never chosen
  local name=$1 dir=$2 out
  rm -f "$base/stub-ran"
  out=$(PATH="$dir:$PATH" launch "$name" 2>&1 >/dev/null; echo "rc=$?")
  assert_eq "$3: the project binary never ran" "no" "$([ -e "$base/stub-ran" ] && echo yes || echo no)"
  assert_eq "$3: the launcher never names the project binary" "no" "$(grep -qF "$dir" "$run/launchers/$name.sh" 2>/dev/null && echo yes || echo no)"
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

# Another spelling of the same project folder on PATH (letter case on a case-insensitive
# volume) is still the project: folders are compared by identity (PR #90 re-check, B1).
alt="$(dirname "$proj")/$(basename "$proj" | tr 'a-z' 'A-Z')"
if [ "$alt" != "$proj" ] && [ -d "$alt/bin" ] && [ "$alt" -ef "$proj" ]; then
  rm -f "$base/stub-ran"
  out=$(PATH="$alt/bin:$PATH" launch b6 2>&1 >/dev/null; echo "rc=$?")
  assert_eq "D37-FLOW-8: the project folder in another letter case on PATH never reaches the launcher" "no" "$(grep -qF "$alt/bin" "$run/launchers/b6.sh" 2>/dev/null && echo yes || echo no)"
  assert_eq "D37-FLOW-8: the project binary reached through another spelling never ran" "no" "$([ -e "$base/stub-ran" ] && echo yes || echo no)"
else
  ok "D37-FLOW-8: case check skipped (this volume is case-sensitive)"
fi

# Any helper, not only the runtime: a project tmux or uuidgen first on PATH never runs,
# because every project folder is dropped from PATH before a verb starts (PR #90, Codex).
mkdir -p "$proj/helpers"
for tool in tmux uuidgen git jq; do
  printf '%s\n' '#!/bin/sh' "touch \"$base/helper-ran-$tool\"" 'exit 1' > "$proj/helpers/$tool"
  chmod 755 "$proj/helpers/$tool"
done
PATH="$proj/helpers:$base/outbin:$PATH" launch b7 >/dev/null 2>&1 || true
for tool in tmux uuidgen git jq; do
  assert_eq "D37-FLOW-8: a project $tool first on PATH never runs" "no" "$([ -e "$base/helper-ran-$tool" ] && echo yes || echo no)"
done
assert_eq "D37-FLOW-8: the session with project helpers first on PATH still starts" "running" "$(rec b7 .status)"
