# H-055 (merge requires an independent "passed" verdict), H-046 (every merge is confirmed
# through git), design Rebuild reuse list (local integration branch per run with the gate
# re-run on the merged tree; the finalize commit is the only completion signal), D11, PR-4,
# field notes C1 (dirty tracked file, no-op merge), C5 (never move a checked-out branch by ref)
# and I3 (nothing checked is never OK). tasks.md 8.1 and 8.2.
h="$HO_PLUGIN_ROOT/bin/harness"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
proj="$PWD/proj"
mkdir -p "$proj/.harness" "$PWD/user"
git -C "$proj" init -q -b main
printf '%s\n' '{"schemaVersion":2}' > "$proj/.harness/config.json"
printf '.harness/\n' >> "$proj/.git/info/exclude"
printf 'base\n' > "$proj/shared.txt"
git -C "$proj" add shared.txt && git -C "$proj" commit -qm base
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$PWD/user"
# The gate fails when the merged tree holds a file named BROKEN.
user_gate() {
  printf '%s\n' '{"schemaVersion":2,"gate":{"use":"t","list":{"t":{"command":"test ! -e BROKEN && test -f shared.txt"}}}}' > "$PWD/user/config.json"
}
user_gate
run=$("$h" run new)
int="$PWD/int"
tip() { git -C "$proj" rev-parse "refs/heads/$(jq -r .branch "$run/integration.json")"; }
merge_rc() { local rc=0; "$h" loop "$run" merge "$1" >/dev/null 2>"$PWD/err" || rc=$?; echo "$rc"; }
ledger_has() { jq -r .kind "$run/ledger.jsonl" | grep -c "^$1\$" || true; }

# lane <name> <file> <content> [allow-empty]: a worktree branch with one work commit and a finalize commit.
lane() {
  local n=$1 w="$PWD/w-$1"
  git -C "$proj" worktree add -q -b "lane-$n" "$w" main
  if [ -n "${2-}" ]; then printf '%s\n' "$3" > "$w/$2"; git -C "$w" add "$2"; git -C "$w" commit -qm "work $n"; fi
  git -C "$w" commit -q --allow-empty -m "finalize($n): done"
}
verdict() { # <lane> <first line>
  local p
  p=$("$h" loop "$run" ready "$1" --worktree "$PWD/w-$1") || { echo "ready failed for $1" >&2; return 1; }
  printf '%s\nevidence\n' "$2" > "$p"
}

# ---- integration branch ----------------------------------------------------------------
assert_exit "Rebuild integration: a missing base is refused" 65 "$h" loop "$run" integration --repo "$proj" --base nope --worktree "$int"
"$h" loop "$run" integration --repo "$proj" --base main --worktree "$int" >/dev/null
assert_eq "Rebuild integration: the branch starts at the base" "$(git -C "$proj" rev-parse main)" "$(tip)"
assert_eq "Rebuild integration: the worktree has the integration branch checked out" \
  "refs/heads/$(jq -r .branch "$run/integration.json")" "$(git -C "$int" symbolic-ref HEAD)"
assert_exit "Rebuild integration: a second integration branch for the same run is refused" 65 \
  "$h" loop "$run" integration --repo "$proj" --base main --worktree "$PWD/int2"
base_tip=$(tip)

# ---- the finalize commit is the only completion signal ------------------------------------
lane a a.txt "from a"
git -C "$PWD/w-a" commit -q --allow-empty -m "more work after finalize"
assert_exit "Rebuild completion: a lane whose tip is not a finalize commit is not ready" 65 "$h" loop "$run" ready a --worktree "$PWD/w-a"
git -C "$PWD/w-a" reset -q --hard HEAD~1
git -C "$PWD/w-a" commit -q --allow-empty -m "finalize(b): wrong lane"
assert_exit "Rebuild completion: a finalize commit of another lane does not count" 65 "$h" loop "$run" ready a --worktree "$PWD/w-a"
git -C "$PWD/w-a" reset -q --hard HEAD~1
printf 'dirty\n' >> "$PWD/w-a/a.txt"
assert_exit "Rebuild completion: a lane with a dirty tree is not ready" 65 "$h" loop "$run" ready a --worktree "$PWD/w-a"
git -C "$PWD/w-a" checkout -q -- a.txt
assert_exit "Rebuild completion: a lane name that is not a plain name is refused" 65 "$h" loop "$run" ready ../a --worktree "$PWD/w-a"
vp=$("$h" loop "$run" ready a --worktree "$PWD/w-a")
assert_eq "H-055: the verdict path is bound to the exact finalize commit" \
  "$run/verdicts/a/$(git -C "$PWD/w-a" rev-parse HEAD).md" "$vp"

# ---- H-055: no merge without a plain "passed" verdict for that commit ---------------------
assert_eq "H-055 verdict missing: the merge step refuses (8.2)" 65 "$(merge_rc a)"
assert_eq "H-055 verdict missing: the integration tip is unchanged" "$base_tip" "$(tip)"
assert_contains "H-055 verdict missing: the message names the missing verdict" "$(cat "$PWD/err")" "no verdict"
printf 'failed\nbroken\n' > "$vp"
assert_eq "H-055 fail verdict: the merge step refuses" 65 "$(merge_rc a)"
printf 'passed with remarks\nlook at x\n' > "$vp"
assert_eq "H-055 passed-with-remarks verdict: does not merge" 65 "$(merge_rc a)"
assert_eq "H-055 passed-with-remarks verdict: the integration tip is unchanged" "$base_tip" "$(tip)"
printf '\n' > "$vp"
assert_eq "H-055: an empty first line is not a verdict" 65 "$(merge_rc a)"
rm -f "$vp"; printf 'passed\n' > "$PWD/vtarget"; ln -s "$PWD/vtarget" "$vp"
assert_eq "H-055: a verdict that is a link is refused" 65 "$(merge_rc a)"
rm -f "$vp"
# A verdict written for an older commit does not cover a newer tip (PR-9).
printf 'passed\n' > "$vp"
printf 'later\n' > "$PWD/w-a/later.txt"; git -C "$PWD/w-a" add later.txt; git -C "$PWD/w-a" commit -qm "later"
git -C "$PWD/w-a" commit -q --allow-empty -m "finalize(a): again"
assert_eq "H-055: a verdict for an older commit does not cover the new tip" 65 "$(merge_rc a)"
assert_eq "H-055: the stale verdict left the integration tip unchanged" "$base_tip" "$(tip)"
verdict a passed

# ---- clean trees (field note C1) ------------------------------------------------------------
printf 'edited\n' >> "$int/shared.txt"
assert_eq "H-046 dirty tree: a dirty tracked file in the integration worktree refuses the merge" 65 "$(merge_rc a)"
assert_eq "H-046 dirty tree: the integration tip is unchanged" "$base_tip" "$(tip)"
git -C "$int" checkout -q -- shared.txt
printf 'x\n' > "$int/stray.txt"
assert_eq "H-046 dirty tree: an untracked file in the integration worktree refuses the merge" 65 "$(merge_rc a)"
rm -f "$int/stray.txt"
printf 'edited\n' >> "$PWD/w-a/a.txt"
assert_eq "H-046 dirty tree: a dirty lane worktree refuses the merge" 65 "$(merge_rc a)"
git -C "$PWD/w-a" checkout -q -- a.txt

# ---- gate configuration (D37-FLOW-8) --------------------------------------------------------
printf '%s\n' '{"schemaVersion":2}' > "$PWD/user/config.json"
assert_eq "H-046 gate: with no gate configured the merge is refused, never passed" 65 "$(merge_rc a)"
printf '%s\n' '{"schemaVersion":2,"gate":{"list":{"t":{"command":"true"}}}}' > "$proj/.harness/config.json"
user_gate
assert_eq "D37-FLOW-8: a gate command in the project config refuses the merge" 65 "$(merge_rc a)"
assert_contains "D37-FLOW-8: the message says to move the command to the user config" "$(cat "$PWD/err")" "user config"
printf '%s\n' '{"schemaVersion":2}' > "$proj/.harness/config.json"
assert_eq "D37-FLOW-8: nothing was merged while the config was refused" "$base_tip" "$(tip)"

# ---- STOP ---------------------------------------------------------------------------------
"$h" state "$run" stop "test" >/dev/null
assert_eq "Rebuild STOP: a stopped run does not merge" 75 "$(merge_rc a)"
"$h" state "$run" resume >/dev/null

# ---- happy path: merge confirmed by git (H-046, 8.1) ----------------------------------------
lane_tip=$(git -C "$PWD/w-a" rev-parse HEAD)
assert_eq "H-046 confirmed: a passed verdict on clean trees merges" 0 "$(merge_rc a)"
new_tip=$(tip)
assert_eq "H-046 confirmed: the first parent of the new tip is the old tip" "$base_tip" "$(git -C "$proj" rev-parse "$new_tip^1")"
assert_eq "H-046 confirmed: the second parent is the validated finalize commit" "$lane_tip" "$(git -C "$proj" rev-parse "$new_tip^2")"
assert_eq "H-046 confirmed: the lane's file is in the integration branch" "from a" "$(git -C "$proj" show "$new_tip:a.txt")"
assert_eq "H-046 confirmed: the ledger records one confirmed merge" 1 "$(ledger_has merge-confirmed)"
assert_eq "H-046 confirmed: the ledger line names the merge commit" "$new_tip" \
  "$(jq -r 'select(.kind == "merge-confirmed") | .tip' "$run/ledger.jsonl")"
assert_eq "H-046 confirmed: the integration worktree is clean after the gate" "" "$(git -C "$int" status --porcelain)"
assert_eq "H-046 confirmed: the recorded tip follows the branch" "$new_tip" "$(jq -r .tip "$run/integration.json")"

# ---- no-op merges are failures (8.2, field note C1) ------------------------------------------
assert_eq "H-046 no-op: merging an already merged lane reports a failure" 69 "$(merge_rc a)"
assert_eq "H-046 no-op: the tip is unchanged" "$new_tip" "$(tip)"
lane b
verdict b passed
assert_eq "H-046 no-op: a merge that changes no file reports a failure, not success" 69 "$(merge_rc b)"
assert_eq "H-046 no-op: the empty merge is rolled back" "$new_tip" "$(tip)"
assert_eq "H-046 no-op: the integration worktree is clean after the roll back" "" "$(git -C "$int" status --porcelain)"
assert_eq "H-046 no-op: no confirmed merge was recorded" 1 "$(ledger_has merge-confirmed)"

# ---- a conflict aborts and leaves the branch unchanged (PR-4) -------------------------------
lane c a.txt "from c"
verdict c passed
assert_eq "PR-4: a merge conflict is a failure" 70 "$(merge_rc c)"
assert_eq "PR-4: after the conflict the integration tip is unchanged" "$new_tip" "$(tip)"
assert_eq "PR-4: after the conflict the integration tree is clean" "" "$(git -C "$int" status --porcelain)"
assert_eq "PR-4: no merge is left in progress" "no" "$(git -C "$int" rev-parse -q --verify MERGE_HEAD >/dev/null && echo yes || echo no)"

# ---- the gate re-runs on the merged tree ------------------------------------------------------
lane d BROKEN "x"
verdict d passed
assert_eq "Rebuild integration gate: a merged tree that fails the gate is a failure" 72 "$(merge_rc d)"
assert_eq "Rebuild integration gate: the failed merge is rolled back" "$new_tip" "$(tip)"
assert_eq "Rebuild integration gate: the tree is clean after the roll back" "" "$(git -C "$int" status --porcelain)"
# A gate that dirties its tree does not dirty the integration worktree.
printf '%s\n' '{"schemaVersion":2,"gate":{"use":"t","list":{"t":{"command":"printf x >> shared.txt; touch junk"}}}}' > "$PWD/user/config.json"
lane e e.txt "from e"
verdict e passed
assert_eq "Rebuild integration gate: a gate that writes files still merges" 0 "$(merge_rc e)"
assert_eq "Rebuild integration gate: the gate's writes do not reach the integration worktree" "" "$(git -C "$int" status --porcelain)"
user_gate
e_tip=$(tip)

# ---- a tip moved outside the engine is refused (interrupted merge, field note C5) -------------
printf 'by hand\n' > "$int/hand.txt"; git -C "$int" add hand.txt; git -C "$int" commit -qm "by hand"
lane f f.txt "from f"
verdict f passed
assert_eq "H-046: a tip that the engine did not record refuses the next merge" 65 "$(merge_rc f)"
assert_contains "H-046: the message names the unrecorded tip" "$(cat "$PWD/err")" "tip"
git -C "$int" reset -q --hard "$e_tip"
git -C "$proj" update-ref "refs/heads/$(jq -r .branch "$run/integration.json")" "$base_tip"
assert_eq "Field note C5: a checked-out branch moved by ref refuses the merge" 65 "$(merge_rc f)"
git -C "$proj" update-ref "refs/heads/$(jq -r .branch "$run/integration.json")" "$e_tip"
assert_eq "H-046: once the tip is back the merge goes through" 0 "$(merge_rc f)"
assert_eq "H-046: every confirmed merge has its own ledger line" 3 "$(ledger_has merge-confirmed)"
