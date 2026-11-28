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
# D12: the run's autonomy profile must allow the local integration merge (safe, the default, does not).
printf '%s\n' '{"schemaVersion":2,"autonomy":{"profile":"draft-pr"}}' > "$proj/.harness/config.json"
printf '.harness/\n' >> "$proj/.git/info/exclude"
printf 'base\n' > "$proj/shared.txt"
git -C "$proj" add shared.txt && git -C "$proj" commit -qm base
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$PWD/user"
# The gate fails when the merged tree holds a file named BROKEN.
user_gate() {
  printf '%s\n' '{"schemaVersion":2,"gate":{"use":"t","list":{"t":{"command":"test ! -e BROKEN && test -f shared.txt"}}}}' > "$PWD/user/config.json"
}
user_gate
select_config "$proj"
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
# Registry records of this run (lib/sessions.sh writes them on launch): one validator, one worker.
vsid=11111111-1111-4111-8111-111111111111
wsid=22222222-2222-4222-8222-222222222222
mkdir -p "$run/sessions"
srec() { # <name> <role> <session-id>
  jq -n --arg run "$(basename "$run")" --arg n "$1" --arg r "$2" --arg sid "$3" \
    '{schemaVersion: 2, run: $run, name: $n, role: $r, session_id: $sid, status: "running"}' > "$run/sessions/$1.json"
}
srec val validator "$vsid"
srec wrk worker "$wsid"
# as <name> <session-id> <cmd...>: run a command the way a launched session does (the launcher
# exports HO_SESSION_NAME and HO_SESSION_ID).
as() { local n=$1 sid=$2; shift 2; HO_SESSION_NAME=$n HO_SESSION_ID=$sid "$@"; }
lsha() { git -C "$PWD/w-$1" rev-parse HEAD; }
# vtext <lane> <text>: the validator records a verdict for the lane's recorded commit.
vtext() { printf '%b' "$2" | as val "$vsid" "$h" loop "$run" verdict "$1" --sha "$(lsha "$1")"; }
verdict() { # <lane> <first line>
  "$h" loop "$run" ready "$1" --worktree "$PWD/w-$1" >/dev/null || { echo "ready failed for $1" >&2; return 1; }
  vtext "$1" "$2\nevidence\n" >/dev/null
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
assert_eq "H-055: the verdict record is bound to the exact finalize commit" \
  "$run/verdicts/a/$(git -C "$PWD/w-a" rev-parse HEAD).json" "$vp"

# ---- H-055: no merge without a plain "passed" verdict for that commit ---------------------
assert_eq "H-055 verdict missing: the merge step refuses (8.2)" 65 "$(merge_rc a)"
assert_eq "H-055 verdict missing: the integration tip is unchanged" "$base_tip" "$(tip)"
assert_contains "H-055 verdict missing: the message names the missing verdict" "$(cat "$PWD/err")" "no verdict"
vtext a 'failed\nbroken\n' >/dev/null
assert_eq "H-055 fail verdict: the merge step refuses" 65 "$(merge_rc a)"
vtext a 'passed with remarks\nlook at x\n' >/dev/null
assert_eq "H-055 passed-with-remarks verdict: does not merge" 65 "$(merge_rc a)"
assert_eq "H-055 passed-with-remarks verdict: the integration tip is unchanged" "$base_tip" "$(tip)"
vtext a '\n' >/dev/null
assert_eq "H-055: an empty first line is not a verdict" 65 "$(merge_rc a)"
for t in 'passed\r\n' 'passed \n' 'Passed\n' 'passed.\n'; do
  vtext a "$t" >/dev/null
  assert_eq "H-055: a first line [$t] is not a plain passed" 65 "$(merge_rc a)"
done
vtext a 'passed\n' >/dev/null; cp "$vp" "$PWD/vtarget"; rm -f "$vp"; ln -s "$PWD/vtarget" "$vp"
assert_eq "H-055: a verdict that is a link is refused" 65 "$(merge_rc a)"
rm -f "$vp"
# A verdict written for an older commit does not cover a newer tip (PR-9).
vtext a 'passed\n' >/dev/null
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
printf '%s\n' '{"schemaVersion":2,"autonomy":{"profile":"draft-pr"}}' > "$proj/.harness/config.json"
assert_eq "D37-FLOW-8: nothing was merged while the config was refused" "$base_tip" "$(tip)"

# ---- STOP ---------------------------------------------------------------------------------
"$h" state "$run" stop "test" >/dev/null
assert_eq "Rebuild STOP: a stopped run does not merge" 75 "$(merge_rc a)"
"$h" state "$run" resume >/dev/null

# ---- H-055: only the independent validator's verdict counts (validator concern 1 on #43) ------
va=$(lsha a); vf="$run/verdicts/a/$va.json"; cp "$vf" "$PWD/good-verdict"
jq -n --arg s "$va" '{schemaVersion: 2, lane: "a", sha: $s, text: "passed\n"}' > "$vf"
assert_eq "H-055 author: a verdict file written without the engine verb is refused" 65 "$(merge_rc a)"
assert_contains "H-055 author: the refusal names the missing author" "$(cat "$PWD/err")" "validator"
jq --arg sid "$wsid" '.session_id = $sid | .session_name = "wrk"' "$PWD/good-verdict" > "$vf"
assert_eq "H-055 author: a verdict whose author is a worker session is refused" 65 "$(merge_rc a)"
rc=0; printf 'passed\n' | as wrk "$wsid" "$h" loop "$run" verdict a --sha "$va" >/dev/null 2>&1 || rc=$?
assert_eq "H-055 author: a worker session cannot record a verdict" 65 "$rc"
rc=0; printf 'passed\n' | as ghost 33333333-3333-4333-8333-333333333333 "$h" loop "$run" verdict a --sha "$va" >/dev/null 2>&1 || rc=$?
assert_eq "H-055 author: a session that is not in the run's registry cannot record a verdict" 65 "$rc"
rc=0; printf 'passed\n' | "$h" loop "$run" verdict a --sha "$va" >/dev/null 2>&1 || rc=$?
assert_eq "H-055 author: a verdict from outside a session is refused" 65 "$rc"
rc=0; printf 'passed\n' | as val "$vsid" "$h" loop "$run" verdict a --sha "$base_tip" >/dev/null 2>&1 || rc=$?
assert_eq "H-055 author: a verdict for another commit than the recorded one is refused" 65 "$rc"
# A worker's session resumed under a validator record keeps the worker's session ID.
srec val2 validator "$wsid"
rc=0; printf 'passed\n' | as val2 "$wsid" "$h" loop "$run" verdict a --sha "$va" >/dev/null 2>&1 || rc=$?
assert_eq "H-055 author: a worker session resumed as a validator cannot record a verdict" 65 "$rc"
jq --arg sid "$wsid" '.session_id = $sid | .session_name = "val2"' "$PWD/good-verdict" > "$vf"
assert_eq "H-055 author: a verdict of a worker session resumed as a validator is refused" 65 "$(merge_rc a)"
rm -f "$run/sessions/val2.json"
cp "$PWD/good-verdict" "$vf"
# The lane's own worker never validates it.
as val "$vsid" "$h" loop "$run" ready a --worktree "$PWD/w-a" >/dev/null
assert_eq "H-055 author: the lane's own worker session cannot be its validator" 65 "$(merge_rc a)"
"$h" loop "$run" ready a --worktree "$PWD/w-a" >/dev/null
# Links: the verdicts folder, the lane's folder and the file.
mv "$run/verdicts/a" "$PWD/vdir-a"; ln -s "$PWD/vdir-a" "$run/verdicts/a"
assert_eq "H-055 author: a linked verdicts/<lane> folder is refused" 65 "$(merge_rc a)"
rm -f "$run/verdicts/a"; mv "$PWD/vdir-a" "$run/verdicts/a"
mv "$run/verdicts" "$PWD/vdir"; ln -s "$PWD/vdir" "$run/verdicts"
assert_eq "H-055 author: a linked verdicts folder is refused" 65 "$(merge_rc a)"
rm -f "$run/verdicts"; mv "$PWD/vdir" "$run/verdicts"
assert_eq "H-055 author: nothing was merged by a refused verdict" "$base_tip" "$(tip)"

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

# ---- a ledger that cannot be written never reads as success (field note I3) -------------------
lane g g.txt "from g"
"$h" loop "$run" ready g --worktree "$PWD/w-g" >/dev/null
chmod a-w "$run/ledger.jsonl"
rc=$(merge_rc g)
assert_eq "H-055: a refusal whose ledger line fails is not exit 0" "yes" "$([ "$rc" -ne 0 ] && echo yes || echo no)"
chmod u+w "$run/ledger.jsonl"; verdict g passed; chmod a-w "$run/ledger.jsonl"
g_before=$(tip)
rc=$(merge_rc g)
assert_eq "H-046: a merge whose confirmed line cannot be written is not exit 0" "yes" "$([ "$rc" -ne 0 ] && echo yes || echo no)"
assert_eq "H-046: without its ledger line the recorded tip does not move" "$g_before" "$(jq -r .tip "$run/integration.json")"
chmod u+w "$run/ledger.jsonl"
# Issue #129 item 3: a merge commit the engine made and never confirmed (a crash or a failed
# ledger write between the merge and its record) is rolled back by the next merge, which then
# merges again through the gate. It never blocks the lane for good.
g_unrec=$(tip)
assert_eq "#129 H-046: the next merge of the lane recovers the unconfirmed merge and merges again" 0 "$(merge_rc g)"
assert_eq "#129 H-046: the recovery is recorded" 1 "$(ledger_has merge-recovered)"
assert_eq "#129 H-046: the new merge starts from the last confirmed tip" "$g_before" "$(git -C "$proj" rev-parse "$(tip)^1")"
assert_eq "#129 H-046: the new merge holds the lane's finalize commit" "$(lsha g)" "$(git -C "$proj" rev-parse "$(tip)^2")"
assert_eq "#129 H-046: the recovered merge is confirmed in the ledger" "$(tip)" \
  "$(jq -r 'select(.kind == "merge-confirmed" and .lane == "g") | .tip' "$run/ledger.jsonl")"
assert_eq "#129 H-046: the unconfirmed commit is no longer on the branch" 1 \
  "$(git -C "$proj" merge-base --is-ancestor "$g_unrec" "$(tip)" && echo 0 || echo 1)"
# A crash after the merge-confirmed line and before the tip write: the next merge writes the tip.
g_tip=$(tip)
jq --arg t "$g_before" '.tip = $t' "$run/integration.json" > "$PWD/ij.t" && mv "$PWD/ij.t" "$run/integration.json"
lane g2 g2.txt "from g2"; verdict g2 passed
assert_eq "#129 H-046: a confirmed merge whose tip was not written does not refuse the next merge" 0 "$(merge_rc g2)"
assert_eq "#129 H-046: the missing tip write is recorded" 1 "$(ledger_has merge-tip-recovered)"
assert_eq "#129 H-046: the next merge starts from the confirmed tip" "$g_tip" "$(git -C "$proj" rev-parse "$(tip)^1")"
assert_eq "#129 H-046: the recorded tip follows the branch again" "$(tip)" "$(jq -r .tip "$run/integration.json")"
# The tests below start from the tip before lane g.
git -C "$int" reset -q --hard "$g_before"
jq --arg t "$g_before" '.tip = $t' "$run/integration.json" > "$PWD/ij.t" && mv "$PWD/ij.t" "$run/integration.json"

# ---- status ----------------------------------------------------------------------------------
st=$("$h" loop "$run" status)
assert_contains "Rebuild loop status: names the integration tip" "$st" "at $g_before"
assert_contains "Rebuild loop status: lists a confirmed merge" "$st" "merged a "

# ---- a lock with no holder file does not block merges forever ----------------------------------
git -C "$int" reset -q --hard "$g_before"
mkdir "$run/merge.lock"; touch -t 202001010000 "$run/merge.lock"
assert_eq "Rebuild loop lock: a stale lock with no holder is taken over" 69 "$(merge_rc a)"

# ---- validator concerns on #43: verdict after the gate, roll back, git errors, signals, lock ----
cur=$(tip)
gitdir_int=$(git -C "$int" rev-parse --absolute-git-dir)
setgate() { jq -n --arg c "$1" '{schemaVersion: 2, gate: {use: "t", list: {t: {command: $c} } } }' > "$PWD/user/config.json"; }
no_rolled_back() { case $(cat "$PWD/err") in *"rolled back"*) bad "$1" "$(cat "$PWD/err")" ;; *) ok "$1" ;; esac; }

# H-055: the verdict is read again under the merge lock after the gate.
lane r r.txt "from r"; verdict r passed
jq '.text = "failed\n"' "$run/verdicts/r/$(lsha r).json" > "$PWD/vr-failed"
setgate "cp '$PWD/vr-failed' '$run/verdicts/r/$(lsha r).json'"
assert_eq "H-055: a verdict that turns into a fail while the gate runs does not merge" 65 "$(merge_rc r)"
assert_eq "H-055: that merge is rolled back" "$cur" "$(tip)"
assert_contains "H-055: the refusal names the verdict" "$(cat "$PWD/err")" "verdict"

# A commit made on the branch while the gate ran is never thrown away (concern 3).
lane i i.txt "from i"; verdict i passed
setgate "git -C '$int' commit -q --allow-empty -m 'during the gate'; exit 1"
assert_eq "H-046 roll back: a failed gate after the branch moved is left for a person (exit 70)" 70 "$(merge_rc i)"
assert_eq "H-046 roll back: the commit made during the gate is kept" "during the gate" "$(git -C "$proj" log -1 --format=%s "$(tip)")"
assert_contains "H-046 roll back: the message leaves the branch for a person" "$(cat "$PWD/err")" "person"
no_rolled_back "H-046 roll back: a skipped roll back never says rolled back"
git -C "$int" reset -q --hard "$cur"

# A roll back that fails never says "rolled back" (concern 4).
lane j j.txt "from j"; verdict j passed
setgate "touch '$gitdir_int/index.lock'; exit 1"
assert_eq "H-046 roll back: a failed roll back exits 70" 70 "$(merge_rc j)"
no_rolled_back "H-046 roll back: a failed roll back never says rolled back"
assert_contains "H-046 roll back: a failed roll back leaves the branch for a person" "$(cat "$PWD/err")" "person"
rm -f "$gitdir_int/index.lock"; git -C "$int" reset -q --hard "$cur"

# A git error in the no-op check is an error, not "changed" (concern 5).
user_gate
mkdir -p "$PWD/shim"
cat > "$PWD/shim/git" <<EOS
#!/bin/bash
if [ -n "\${HO_T_FAIL_DIFF:-}" ] && [ "\${*: -3:1}" = --quiet ] && [ "\${*: -1}" != -- ]; then echo "fatal: test shim" >&2; exit 128; fi
exec "$(command -v git)" "\$@"
EOS
chmod +x "$PWD/shim/git"
lane k k.txt "from k"; verdict k passed
assert_eq "H-046 no-op check: a git error is not taken as a change (exit 70)" 70 "$(HO_T_FAIL_DIFF=1 PATH="$PWD/shim:$PATH" merge_rc k)"
assert_eq "H-046 no-op check: after the git error the branch is back at its tip" "$cur" "$(tip)"
assert_eq "H-046 no-op check: no merge was confirmed for that lane" "" "$(jq -r 'select(.kind == "merge-confirmed" and .lane == "k") | .lane' "$run/ledger.jsonl")"

# The tip check after the gate (concern 8).
lane m m.txt "from m"; verdict m passed
setgate "git -C '$int' commit -q --allow-empty -m 'moved by the gate'"
assert_eq "H-046 tip after the gate: a branch moved while the gate ran is not confirmed (exit 70)" 70 "$(merge_rc m)"
assert_eq "H-046 tip after the gate: the branch is left where it was moved" "moved by the gate" "$(git -C "$proj" log -1 --format=%s "$(tip)")"
assert_eq "H-046 tip after the gate: the recorded tip does not move" "$cur" "$(jq -r .tip "$run/integration.json")"
git -C "$int" reset -q --hard "$cur"

# The git confirmation block (concern 8): a merge that git does not show is rolled back.
user_gate
mkdir -p "$PWD/hooks"; printf '#!/bin/sh\ngit update-ref HEAD HEAD^\n' > "$PWD/hooks/post-merge"; chmod +x "$PWD/hooks/post-merge"
git -C "$proj" config core.hooksPath "$PWD/hooks"
lane n n.txt "from n"; verdict n passed
assert_eq "H-046 confirmation: a merge that git does not confirm is a failure (exit 70)" 70 "$(merge_rc n)"
assert_contains "H-046 confirmation: the message says git does not confirm it" "$(cat "$PWD/err")" "does not confirm"
assert_eq "H-046 confirmation: the branch is at its old tip" "$cur" "$(tip)"
# The hook moved the branch outside the engine and left the merged files staged; the engine
# does not reset over them (they are not the tree of a commit it knows), it leaves them.
assert_contains "H-046 confirmation: what git left is left for a person" "$(cat "$PWD/err")" "left for a person"
git -C "$proj" config --unset core.hooksPath
git -C "$int" reset -q --hard "$cur"

# TERM to the caller stops the merge subshell and the gate (concern 6).
lane p p.txt "from p"; verdict p passed
rm -f "$PWD/gate.pid" "$PWD/gsleep.pid"
setgate "echo \$\$ > '$PWD/gate.pid'; sleep 30 & echo \$! > '$PWD/gsleep.pid'; wait"
confirmed_before=$(ledger_has merge-confirmed)
"$h" loop "$run" merge p >/dev/null 2>"$PWD/err" & hp=$!
n=0; while [ ! -s "$PWD/gsleep.pid" ] && [ "$n" -lt 600 ]; do sleep 0.1; n=$((n + 1)); done
[ -s "$PWD/gsleep.pid" ] || bad "test setup: the gate did not start" ""
kill -TERM "$hp"
rc=0; wait "$hp" || rc=$?
assert_eq "H-046 signal: a merge stopped by TERM exits 75" 75 "$rc"
sleep 0.5
assert_eq "H-046 signal: no merge is confirmed after TERM" "$confirmed_before" "$(ledger_has merge-confirmed)"
assert_eq "H-046 signal: the branch is back at its tip" "$cur" "$(tip)"
assert_eq "H-046 signal: the merge lock is released" "no" "$([ -e "$run/merge.lock" ] && echo yes || echo no)"
for f in gate.pid gsleep.pid; do
  p=$(cat "$PWD/$f" 2>/dev/null || echo 0)
  if [ "$p" != 0 ] && ! ps -o pid= -p "$p" >/dev/null 2>&1; then ok "H-103 signal: the gate process ($f) is stopped"; else
    bad "H-103 signal: the gate process ($f) is stopped" "pid $p"; [ "$p" = 0 ] || kill -KILL "$p" 2>/dev/null || true; fi
done
user_gate
assert_eq "H-046 signal: a retry after the stop merges" 0 "$(merge_rc p)"
cur=$(tip)

# A stale lock that another waiter is taking over is never removed (concern 7).
lane q q.txt "from q"; verdict q passed
sh -c 'exit 0' & dead=$!; wait "$dead" || true
mkdir "$run/merge.lock"; echo "$dead" > "$run/merge.lock/pid"; mkdir "$run/merge.lock/takeover"
"$h" loop "$run" merge q >/dev/null 2>"$PWD/err" & hp=$!
sleep 1.5
assert_eq "Rebuild loop lock: a lock under takeover by another waiter is not removed" "$dead" "$(cat "$run/merge.lock/pid" 2>/dev/null || echo gone)"
rmdir "$run/merge.lock/takeover" 2>/dev/null || true
rc=0; wait "$hp" || rc=$?
assert_eq "Rebuild loop lock: after the takeover ends the merge goes on" 0 "$rc"
assert_eq "Rebuild loop lock: the lock is released after the merge" "no" "$([ -e "$run/merge.lock" ] && echo yes || echo no)"
u=$("$h" loop 2>&1 || true)
assert_contains "Rebuild loop usage: exit 78 is documented" "$u" "78 config error"
assert_contains "Rebuild loop usage: exit 75 covers a held merge lock" "$u" "lock"

# ---- review round 1 -------------------------------------------------------------------------
cur=$(tip)
# A flag with no value is a usage error, never a hang (Codex finding 3).
for f in --repo --base --worktree; do
  "$h" loop "$run" integration "$f" >/dev/null 2>&1 & hp=$!
  n=0; while kill -0 "$hp" 2>/dev/null && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
  if kill -0 "$hp" 2>/dev/null; then kill -KILL "$hp" 2>/dev/null || true; wait "$hp" 2>/dev/null || true; rc=hang
  else rc=0; wait "$hp" || rc=$?; fi
  assert_eq "Rebuild integration: $f with no value is a usage error (exit 64)" 64 "$rc"
done

# A roll back never throws away uncommitted edits (Codex finding 1).
lane t t.txt "from t"; verdict t passed
setgate "printf 'kept edit\n' >> '$int/shared.txt'; exit 1"
assert_eq "H-046 roll back: uncommitted edits in the integration worktree are left for a person (exit 70)" 70 "$(merge_rc t)"
assert_contains "H-046 roll back: the uncommitted edit is kept" "$(cat "$int/shared.txt")" "kept edit"
assert_contains "H-046 roll back: the message names the uncommitted edits" "$(cat "$PWD/err")" "uncommitted"
no_rolled_back "H-046 roll back: kept edits never say rolled back"
git -C "$int" checkout -q -- shared.txt; git -C "$int" reset -q --hard "$cur"

# A detached HEAD is named as the cause (validator minor 5).
lane u u.txt "from u"; verdict u passed
setgate "git -C '$int' checkout -q --detach; exit 1"
assert_eq "H-046 roll back: a detached HEAD is left for a person (exit 70)" 70 "$(merge_rc u)"
assert_contains "H-046 roll back: the message says the branch is not checked out" "$(cat "$PWD/err")" "does not have"
git -C "$int" checkout -q "$(jq -r .branch "$run/integration.json")"; git -C "$int" reset -q --hard "$cur"

# A signal during the merge-confirmed ledger line does not cut the merge short (validator minor 2).
user_gate
mkdir -p "$PWD/tshim"
cat > "$PWD/tshim/tail" <<EOS
#!/bin/bash
if [ -e "$PWD/stall-armed" ]; then rm -f "$PWD/stall-armed"; touch "$PWD/stalling"
  i=0; while [ -e "$PWD/stall-hold" ] && [ \$i -lt 600 ]; do sleep 0.1; i=\$((i + 1)); done; fi
exec "$(command -v tail)" "\$@"
EOS
chmod +x "$PWD/tshim/tail"
lane v v.txt "from v"; verdict v passed
rm -f "$PWD/stalling"
: > "$PWD/stall-hold"
setgate "test -f shared.txt && touch '$PWD/stall-armed'"
PATH="$PWD/tshim:$PATH" "$h" loop "$run" merge v >/dev/null 2>"$PWD/err" & hp=$!
n=0; while [ ! -e "$PWD/stalling" ] && [ "$n" -lt 600 ]; do sleep 0.1; n=$((n + 1)); done
[ -e "$PWD/stalling" ] || bad "test setup: the merge-confirmed line did not start" ""
# The shim holds the line until the signal is sent: the signal lands inside it, at any load.
kill -TERM "$hp"
rm -f "$PWD/stall-hold"
rc=0; wait "$hp" || rc=$?
assert_eq "H-046 signal: TERM during the merge-confirmed line lets the merge finish (exit 0)" 0 "$rc"
assert_eq "H-046 signal: that merge has its merge-confirmed line" "v" "$(jq -r 'select(.kind == "merge-confirmed" and .lane == "v") | .lane' "$run/ledger.jsonl")"
assert_eq "H-046 signal: the recorded tip follows the branch" "$(tip)" "$(jq -r .tip "$run/integration.json")"
user_gate

# ---- review round 2 -------------------------------------------------------------------------
user_gate
cur=$(tip)
# B1: an untracked or ignored file at a path the merge deleted is never overwritten.
lane w1 gone.txt "gone"; verdict w1 passed
assert_eq "B1 setup: the integration branch gets gone.txt" 0 "$(merge_rc w1)"
cur=$(tip)
dlane() { # <name> [ignore]: a lane from the integration tip that deletes gone.txt
  local n=$1 w="$PWD/w-$1"
  git -C "$proj" worktree add -q -b "lane-$n" "$w" "$cur"
  git -C "$w" rm -q gone.txt
  printf '%s.txt\n' "$n" > "$w/$n.txt"; git -C "$w" add "$n.txt"
  if [ -n "${2-}" ]; then printf 'gone.txt\n' > "$w/.gitignore"; git -C "$w" add .gitignore; fi
  git -C "$w" commit -qm "work $n"; git -C "$w" commit -q --allow-empty -m "finalize($n): done"
}
dlane w2; verdict w2 passed
setgate "printf 'PRECIOUS\n' > '$int/gone.txt'; exit 1"
assert_eq "B1: an untracked file at a deleted path is left for a person (exit 70)" 70 "$(merge_rc w2)"
assert_eq "B1: the untracked file is kept" "PRECIOUS" "$(cat "$int/gone.txt" 2>/dev/null)"
no_rolled_back "B1: a kept untracked file never says rolled back"
rm -f "$int/gone.txt"; git -C "$int" reset -q --hard "$cur"
dlane w3 ignore; verdict w3 passed
assert_eq "B1: an ignored file at a deleted path is left for a person (exit 70)" 70 "$(merge_rc w3)"
assert_eq "B1: the ignored file is kept" "PRECIOUS" "$(cat "$int/gone.txt" 2>/dev/null)"
rm -f "$int/gone.txt"; git -C "$int" reset -q --hard "$cur"
# Minor 1: an unrelated untracked file is refused before any reset, and the message says so.
lane w4 w4.txt "from w4"; verdict w4 passed
setgate "printf 'x\n' > '$int/unrelated.txt'; exit 1"
assert_eq "B1: an unrelated untracked file is left for a person (exit 70)" 70 "$(merge_rc w4)"
assert_contains "B1: the message says nothing was reset" "$(cat "$PWD/err")" "nothing is reset"
case $(cat "$PWD/err") in *failed\ in*) bad "B1: the message does not claim a failed roll back" "$(cat "$PWD/err")" ;;
  *) ok "B1: the message does not claim a failed roll back" ;; esac
rm -f "$int/unrelated.txt"; git -C "$int" reset -q --hard "$cur"

# B2: TERM or HUP to the whole process group during the merge-confirmed line.
user_gate
for sig in TERM HUP; do
  l=g$(printf %s "$sig" | tr A-Z a-z)
  lane "$l" "$l.txt" "from $sig" >/dev/null; verdict "$l" passed
  rm -f "$PWD/stalling"
  : > "$PWD/stall-hold"
  setgate "test -f shared.txt && touch '$PWD/stall-armed'"
  set -m
  PATH="$PWD/tshim:$PATH" "$h" loop "$run" merge "$l" >/dev/null 2>"$PWD/err" & hp=$!
  set +m
  n=0; while [ ! -e "$PWD/stalling" ] && [ "$n" -lt 600 ]; do sleep 0.1; n=$((n + 1)); done
  [ -e "$PWD/stalling" ] || bad "test setup: the merge-confirmed line did not start ($sig)" ""
  kill "-$sig" -- "-$hp" 2>/dev/null || true
  rm -f "$PWD/stall-hold"
  rc=0; wait "$hp" || rc=$?
  assert_eq "B2: $sig to the whole group during the merge-confirmed line lets the merge finish (exit 0)" 0 "$rc"
  assert_eq "B2: after $sig to the group the merge has its merge-confirmed line" "$l" \
    "$(jq -r --arg l "$l" 'select(.kind == "merge-confirmed" and .lane == $l) | .lane' "$run/ledger.jsonl")"
  assert_eq "B2: after $sig to the group the recorded tip follows the branch" "$(tip)" "$(jq -r .tip "$run/integration.json")"
  git -C "$int" reset -q --hard "$(jq -r .tip "$run/integration.json")"
done
user_gate
cur=$(tip)

# Codex 4701970612: a signal while the gate's worktree is made stops the merge before the gate.
cat > "$PWD/shim/git" <<EOS
#!/bin/bash
if [ -n "\${HO_T_SLOW_WT:-}" ] && [ "\$3" = worktree ] && [ "\$4" = add ]; then touch "$PWD/wt-adding"
  i=0; while [ -e "$PWD/wt-hold" ] && [ \$i -lt 600 ]; do sleep 0.1; i=\$((i + 1)); done; fi
exec "$(command -v git)" "\$@"
EOS
chmod +x "$PWD/shim/git"
lane x1 x1.txt "from x1"; verdict x1 passed
rm -f "$PWD/wt-adding" "$PWD/gate2.pid" "$PWD/gate2.release"
: > "$PWD/wt-hold"
# The gate would wait until the test releases it, so a merge that waited for the gate could not
# end on its own: the merge ending while the gate was never released proves the stop did not
# wait for it (no clock involved).
setgate "echo \$\$ > '$PWD/gate2.pid'; while [ ! -e '$PWD/gate2.release' ]; do sleep 0.1; done"
HO_T_SLOW_WT=1 PATH="$PWD/shim:$PATH" "$h" loop "$run" merge x1 >/dev/null 2>"$PWD/err" & hp=$!
n=0; while [ ! -e "$PWD/wt-adding" ] && [ "$n" -lt 600 ]; do sleep 0.1; n=$((n + 1)); done
[ -e "$PWD/wt-adding" ] || bad "test setup: the gate worktree was not being made" ""
# The shim holds the worktree step until the signal is sent: the signal lands inside it.
kill -TERM "$hp"
rm -f "$PWD/wt-hold"
n=0; while kill -0 "$hp" 2>/dev/null && [ "$n" -lt 1200 ]; do sleep 0.1; n=$((n + 1)); done
if kill -0 "$hp" 2>/dev/null; then waited=yes; : > "$PWD/gate2.release"; else waited=no; fi
rc=0; wait "$hp" || rc=$?
assert_eq "H-046 signal: a signal while the gate worktree is made stops the merge (exit 75)" 75 "$rc"
assert_eq "H-046 signal: the gate never starts after that signal" "no" "$([ -e "$PWD/gate2.pid" ] && echo yes || echo no)"
assert_eq "H-046 signal: the stop does not wait for the gate (it ended with the gate never released)" no "$waited"
p=$(cat "$PWD/gate2.pid" 2>/dev/null || echo 0); [ "$p" = 0 ] || kill -KILL "$p" 2>/dev/null || true
assert_eq "H-046 signal: the branch is back at its tip" "$cur" "$(tip)"
user_gate

# Minor 3: the git confirmation block, by exit code. A hook adds a commit on top of the merge.
mkdir -p "$PWD/hooks2"
printf '#!/bin/sh\ngit update-ref HEAD "$(git commit-tree "HEAD^{tree}" -p HEAD -m "made by a hook")"\n' > "$PWD/hooks2/post-merge"
chmod +x "$PWD/hooks2/post-merge"
git -C "$proj" config core.hooksPath "$PWD/hooks2"
lane y1 y1.txt "from y1"; verdict y1 passed
assert_eq "H-046 confirmation: a merge with an extra commit on top is not confirmed (exit 70)" 70 "$(merge_rc y1)"
assert_eq "H-046 confirmation: the commit made by the hook is kept" "made by a hook" "$(git -C "$proj" log -1 --format=%s "$(tip)")"
assert_eq "H-046 confirmation: no merge-confirmed line for that lane" "" "$(jq -r 'select(.kind == "merge-confirmed" and .lane == "y1") | .lane' "$run/ledger.jsonl")"
git -C "$proj" config --unset core.hooksPath
git -C "$int" reset -q --hard "$cur"

# ---- issue #102: run-loop follow-ups of wave 3 ------------------------------------------------
user_gate
cur=$(tip)
# Item 1: a signal that ends git merge after its commit (here a post-merge hook stops its git)
# leaves a commit that is provably this merge; it is rolled back, never left for a person.
mkdir -p "$PWD/hooks3"
printf '#!/bin/sh
kill -TERM "$PPID"
sleep 1
' > "$PWD/hooks3/post-merge"; chmod +x "$PWD/hooks3/post-merge"
git -C "$proj" config core.hooksPath "$PWD/hooks3"
lane z1 z1.txt "from z1"; verdict z1 passed
assert_eq "#102 H-046: a git merge stopped after its commit is not confirmed (exit 70)" 70 "$(merge_rc z1)"
assert_eq "#102 H-046: its merge commit is rolled back to the last confirmed tip" "$cur" "$(tip)"
assert_contains "#102 H-046: the message says rolled back" "$(cat "$PWD/err")" "rolled back"
git -C "$proj" config --unset core.hooksPath
assert_eq "#102 H-046: the next merge of the lane goes through" 0 "$(merge_rc z1)"
cur=$(tip)
# Item 9: a post-merge hook that detaches HEAD does not get a confirmed merge.
printf '#!/bin/sh
git checkout -q --detach
' > "$PWD/hooks3/post-merge"
git -C "$proj" config core.hooksPath "$PWD/hooks3"
lane z2 z2.txt "from z2"; verdict z2 passed
assert_eq "#102 H-046: a merge after which HEAD is detached is not confirmed (exit 70)" 70 "$(merge_rc z2)"
assert_eq "#102 H-046: no merge-confirmed line for that lane" "" "$(jq -r 'select(.kind == "merge-confirmed" and .lane == "z2") | .lane' "$run/ledger.jsonl")"
git -C "$proj" config --unset core.hooksPath
git -C "$int" checkout -q "$(jq -r .branch "$run/integration.json")"; git -C "$int" reset -q --hard "$cur"
# Item 6 (a): the roll back is reset --keep, so a local edit that appears just before it is kept.
cat > "$PWD/shim/git" <<EOS
#!/bin/bash
case " \$* " in *" reset "*) [ -z "\${HO_T_DIRTY:-}" ] || printf 'local edit\n' > "\$HO_T_DIRTY" ;; esac
exec "$(command -v git)" "\$@"
EOS
chmod +x "$PWD/shim/git"
lane z3 z3.txt "from z3"; verdict z3 passed
setgate "exit 1"
assert_eq "#102 H-046: a roll back that meets a local edit is left for a person (exit 70)" 70 \
  "$(HO_T_DIRTY="$int/z3.txt" PATH="$PWD/shim:$PATH" merge_rc z3)"
assert_eq "#102 H-046: the local edit is never overwritten by the roll back" "local edit" "$(cat "$int/z3.txt" 2>/dev/null)"
git -C "$int" reset -q --hard "$cur"; rm -f "$int/z3.txt"
user_gate
# Item 6 (b) and item 4: an ignored file in the integration worktree refuses the merge before
# git merge runs (65); nothing is merged. A global excludes entry such as .DS_Store counts too.
printf '*.ign\n' >> "$proj/.git/info/exclude"
: > "$int/before.ign"
lane z4 z4.txt "from z4"; verdict z4 passed
assert_eq "#102 H-046: an ignored file in the integration worktree refuses the merge (65)" 65 "$(merge_rc z4)"
assert_contains "#102 H-046: the refusal names ignored files" "$(cat "$PWD/err")" "ignored files included"
assert_eq "#102 H-046: nothing was merged" "$cur" "$(tip)"
rm -f "$int/before.ign"
# Item 6 (c) and item 5: a gate that writes an ignored file into the integration worktree by
# absolute path gets no confirmed merge; the branch is left for a person (70).
setgate "touch '$int/after.ign'"
assert_eq "#102 H-046: an ignored file written by the gate leaves the merge unconfirmed (70)" 70 "$(merge_rc z4)"
assert_eq "#102 H-046: no merge-confirmed line for that lane" "" "$(jq -r 'select(.kind == "merge-confirmed" and .lane == "z4") | .lane' "$run/ledger.jsonl")"
rm -f "$int/after.ign"; git -C "$int" reset -q --hard "$cur"
user_gate

# ---- H-086, D25a: soft stops and the merge ------------------------------------------------
# soft:step and soft:task refuse the merge; soft:ticket merges the lane of a ticket that began
# before the stop, and only that lane.
lane st1 st1.txt "from st1"; verdict st1 passed
"$h" loop "$run" ready st1 --worktree "$PWD/w-st1" --ticket 7 >/dev/null
lane st2 st2.txt "from st2"; verdict st2 passed
"$h" loop "$run" ready st2 --worktree "$PWD/w-st2" --ticket 8 >/dev/null
lane st3 st3.txt "from st3"; verdict st3 passed
assert_eq "H-086: ready records the lane's ticket" "7" "$(jq -r .ticket "$run/lanes/st1.json")"
"$h" state "$run" begin --ticket 7 --step s1 >/dev/null
"$h" state "$run" begin --ticket 8 --step s1 >/dev/null
"$h" state "$run" stop --type soft:task >/dev/null
assert_eq "H-086: soft:task refuses the merge of a started ticket (75)" 75 "$(merge_rc st1)"
"$h" state "$run" stop --type soft:ticket --ticket 7 >/dev/null
assert_eq "D25a: a per-ticket soft:ticket stop refuses the lane of another ticket (75)" 75 "$(merge_rc st2)"
assert_eq "D25a: a soft:ticket stop refuses a lane that names no ticket (75)" 75 "$(merge_rc st3)"
before=$(tip)
assert_eq "H-086: soft:ticket merges the lane of the covered ticket, so it runs to its end" 0 "$(merge_rc st1)"
assert_eq "H-086: that merge is confirmed by git" "$(lsha st1)" "$(git -C "$proj" rev-parse "$(tip)^2")"
assert_eq "H-086: the merge started from the earlier tip" "$before" "$(git -C "$proj" rev-parse "$(tip)^1")"
"$h" state "$run" stop >/dev/null
assert_eq "H-086: the default soft:step refuses every merge (75)" 75 "$(merge_rc st2)"
"$h" state "$run" resume >/dev/null

# ---- H-079: an ended run merges nothing and begins no step, until a recorded resume ------------
mkdir -p "$PWD/no-tickets"
HO_TICKETS_DIR="$PWD/no-tickets" "$h" lifecycle "$run" check >/dev/null 2>&1 || true
assert_eq "test setup: the run has ended" 1 "$(ledger_has run-end)"
before=$(tip) confirmed_before=$(ledger_has merge-confirmed)
assert_eq "H-079: an ended run refuses a merge (75)" 75 "$(merge_rc st2)"
assert_eq "H-079: the refused merge leaves the integration branch and the ledger as they were" "$before $confirmed_before" \
  "$(tip) $(ledger_has merge-confirmed)"
assert_exit "H-079: an ended run refuses a new step (75)" 75 "$h" state "$run" begin --ticket 9 --step s1
assert_eq "H-079: no step-begin is written after the run end" 0 \
  "$(jq -r 'select(.kind == "run-end" or (.kind == "step-begin" and .ticket == "9")) | .kind' "$run/ledger.jsonl" | grep -c step-begin || true)"
"$h" state "$run" resume >/dev/null
assert_exit "H-079: after a recorded resume a step begins again" 0 "$h" state "$run" begin --ticket 9 --step s1
assert_eq "H-079: after a recorded resume the merge goes through" 0 "$(merge_rc st2)"
