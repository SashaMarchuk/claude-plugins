# Launcher guards from the wave-2 security re-check (#89; D37-FLOW-8, D61, H-136): a prompt that
# starts with "-", a repos[] path with a line break, a project folder on PATH, a runtime binary
# in a worktree of a nested repository, and session.permissions in the project config. Also a
# resume blocked by a record that is not running (no test covered it).
. "$HO_TESTS_DIR/sessions-setup.sh"
p="$base/prompt.md"
cp "$proj/.harness/config.json" "$base/proj.keep.json"
setp() { jq "$1" "$base/proj.keep.json" > "$proj/.harness/config.json"; select_config "$proj"; }
echo 0 > "$base/n"
go() { # [launch args...]: launch one worker; prints its exit code
  local rc=0 n; n=$(($(cat "$base/n") + 1)); echo "$n" > "$base/n"
  "$h" session "$run" launch --role worker --name "g$n" --cwd "$proj/src" "$@" >/dev/null 2>"$base/err" || rc=$?
  echo "$rc"
}

# ---- a prompt that starts with "-" never reaches the runtime as a flag ----
printf -- '--dangerously-skip-everything\n' > "$base/flag.md"
assert_eq "D61 (#89): a prompt that starts with - is refused (65)" 65 "$(go --prompt "$base/flag.md")"

# ---- a repos[] path with a line break is refused ----
setp '.repos = [{"path": ".", "worktrees_dir": "wt\nother"}]'
assert_eq "D37-FLOW-8 (#89): a worktrees_dir with a line break is refused (65)" 65 "$(go --prompt "$p")"
setp '.'

# ---- a project folder on PATH is dropped from the launcher's PATH ----
mkdir -p "$proj/tools"
PATH="$proj/tools:$PATH" go --prompt "$p" >/dev/null
assert_eq "D61 (#89): a project folder on the caller's PATH is not in the launcher's PATH" "" \
  "$(grep '^export PATH=' "$run/launchers/g$(cat "$base/n").sh" | grep -F "$proj/tools" || true)"

# ---- a runtime binary in a worktree of a nested repository not listed in repos[] ----
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
git -C "$proj/src" init -q -b main 2>/dev/null || true
mkdir -p "$proj/src/nested"; git -C "$proj/src/nested" init -q -b main
printf 'x\n' > "$proj/src/nested/f"; git -C "$proj/src/nested" add f; git -C "$proj/src/nested" commit -qm x
git -C "$proj/src/nested" worktree add -q "$base/nested-wt" -b side
mkdir -p "$base/nested-wt/bin"; cp "$HO_TESTS_DIR/fake-bin/claude" "$base/nested-wt/bin/claude"
assert_eq "D61 (#89): a runtime binary in a worktree of a nested repository is refused (65)" 65 \
  "$(PATH="$base/nested-wt/bin:$PATH" go --prompt "$p")"

# ---- session.permissions in the project config ----
setp '.session.permissions = false'
assert_eq "D37-FLOW-8 (#89): a project session.permissions false is refused like any other value (65)" 65 "$(go --prompt "$p")"
# The approved record holds the value the person confirmed; that value is used.
setp '.session.permissions = "acceptEdits"'
assert_eq "D37-FLOW-8 (b) (#89): the approved project value is used" 0 "$(go --prompt "$p")"
assert_contains "D37-FLOW-8 (b): the launcher runs in that mode" "$(cat "$run/launchers/g$(cat "$base/n").sh")" "acceptEdits"
# Changed after the confirmation: refused until it is selected again.
jq '.session.permissions = "bypass"' "$base/proj.keep.json" > "$proj/.harness/config.json"
assert_eq "D37-FLOW-8 (b) (#89): a project value that differs from the approved record is refused (65)" 65 "$(go --prompt "$p")"
setp '.'

# ---- a resume is blocked by a record that is not running ----
launch r1 >/dev/null
sid=$(rec r1 .session_id)
for st in boot-failed launch-failed none; do
  if [ "$st" = none ]; then jq 'del(.status)' "$run/sessions/r1.json" > "$base/r.json"
  else jq --arg s "$st" '.status = $s' "$run/sessions/r1.json" > "$base/r.json"; fi
  cat "$base/r.json" > "$run/sessions/r1.json"
  rc=0; "$h" session "$run" launch --role worker --name "r1-$st" --cwd "$proj/src" --resume "$sid" >/dev/null 2>&1 || rc=$?
  assert_eq "H-139 (#89): a resume is refused while another record of the session reads $st" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
done
