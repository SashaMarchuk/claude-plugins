# A stop or a run end that comes while the merge gate runs is caught before the merge is
# confirmed (H-086, H-079, H-046, D25a; wave-4 follow-up #110). The gate itself writes the stop,
# so the order is exact and no clock is involved.
h="$HO_PLUGIN_ROOT/bin/harness"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
proj="$PWD/proj"
mkdir -p "$proj/.harness" "$PWD/user"
git -C "$proj" init -q -b main
printf '%s\n' '{"schemaVersion":2,"autonomy":{"profile":"draft-pr"}}' > "$proj/.harness/config.json"
printf '.harness/\n' >> "$proj/.git/info/exclude"
printf 'base\n' > "$proj/shared.txt"
git -C "$proj" add shared.txt && git -C "$proj" commit -qm base
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$PWD/user"
gate() { jq -n --arg c "$1" '{schemaVersion: 2, gate: {use: "t", list: {t: {command: $c}}}}' > "$PWD/user/config.json"; }
gate true
select_config "$proj"
run=$("$h" run new)
"$h" loop "$run" integration --repo "$proj" --base main --worktree "$PWD/int" >/dev/null
tip() { git -C "$proj" rev-parse "refs/heads/$(jq -r .branch "$run/integration.json")"; }
vsid=11111111-1111-4111-8111-111111111111
mkdir -p "$run/sessions"
jq -n --arg run "$(basename "$run")" --arg sid "$vsid" \
  '{schemaVersion: 2, run: $run, name: "val", role: "validator", session_id: $sid, status: "running"}' > "$run/sessions/val.json"
lane() { # <name>: a lane with one work commit, a finalize commit, ready and a passed verdict
  local n=$1 w="$PWD/w-$1"
  git -C "$proj" worktree add -q -b "lane-$n" "$w" main
  printf '%s\n' "$n" > "$w/$n.txt"; git -C "$w" add "$n.txt"; git -C "$w" commit -qm "work $n"
  git -C "$w" commit -q --allow-empty -m "finalize($n): done"
  "$h" loop "$run" ready "$n" --worktree "$w" >/dev/null
  printf 'passed\nevidence\n' | HO_SESSION_NAME=val HO_SESSION_ID=$vsid "$h" loop "$run" verdict "$n" --sha "$(git -C "$w" rev-parse HEAD)" >/dev/null
}
merge_rc() { local rc=0; "$h" loop "$run" merge "$1" >/dev/null 2>"$PWD/err" || rc=$?; echo "$rc"; }

# ---- the STOP file appears while the gate runs ----
lane a
before=$(tip)
gate "touch $(printf '%q' "$proj/.harness/STOP")"
assert_eq "H-086 (#110): a STOP file that appears while the gate runs refuses the merge (75)" 75 "$(merge_rc a)"
assert_eq "H-086 (#110): the merge is rolled back" "$before" "$(tip)"
assert_eq "H-046 (#110): no merge-confirmed line is written" 0 "$(jq -r .kind "$run/ledger.jsonl" | grep -c '^merge-confirmed$' || true)"
rm -f "$proj/.harness/STOP"
"$h" state "$run" resume >/dev/null 2>&1 || true

# ---- the run ends while the gate runs ----
lane b
before=$(tip)
gate "printf '%s\n' '{\"kind\":\"run-end\",\"reason\":\"test\"}' >> $(printf '%q' "$run/ledger.jsonl")"
assert_eq "H-079 (#110): a run end that comes while the gate runs refuses the merge (75)" 75 "$(merge_rc b)"
assert_eq "H-079 (#110): that merge is rolled back too" "$before" "$(tip)"
