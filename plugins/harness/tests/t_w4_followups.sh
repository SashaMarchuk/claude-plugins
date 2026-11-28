# Wave-4 follow-ups (#110): the lane's ticket comes from the calling worker's own record (H-086,
# D25a), an approval counts only when it is the record "approve" writes (H-037), and a user's
# autonomy.profile never loosens a project's guardrails.never_push: true (D44, H-036).
h="$HO_PLUGIN_ROOT/bin/harness"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
proj="$PWD/proj"
mkdir -p "$proj/.harness" "$PWD/user"
git -C "$proj" init -q -b main
printf '%s\n' '{"schemaVersion":2,"autonomy":{"profile":"gated"}}' > "$proj/.harness/config.json"
printf '.harness/\n' >> "$proj/.git/info/exclude"
printf 'base\n' > "$proj/shared.txt"
git -C "$proj" add shared.txt && git -C "$proj" commit -qm base
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$PWD/user" HO_TICKETS_DIR="$proj/.harness/tickets"
printf '%s\n' '{"schemaVersion":2}' > "$PWD/user/config.json"
select_config "$proj"
run=$("$h" run new)
"$h" loop "$run" integration --repo "$proj" --base main --worktree "$PWD/int" >/dev/null

# ---- loop ready --ticket is the calling worker's own ticket ----
wsid=22222222-2222-4222-8222-222222222222
mkdir -p "$run/sessions"
jq -n --arg run "$(basename "$run")" --arg sid "$wsid" \
  '{schemaVersion: 2, run: $run, name: "wrk", role: "worker", session_id: $sid, status: "running", ticket: "5"}' > "$run/sessions/wrk.json"
w="$PWD/w-a"
git -C "$proj" worktree add -q -b lane-a "$w" main
printf 'a\n' > "$w/a.txt"; git -C "$w" add a.txt; git -C "$w" commit -qm "work a"
git -C "$w" commit -q --allow-empty -m "finalize(a): done"
rc=0; HO_SESSION_NAME=wrk HO_SESSION_ID=$wsid "$h" loop "$run" ready a --worktree "$w" --ticket 6 >/dev/null 2>"$PWD/err" || rc=$?
assert_eq "H-086 D25a (#110): a worker cannot record a lane for another ticket than its own (65)" 65 "$rc"
assert_eq "H-086 (#110): nothing is recorded for that lane" no "$([ -e "$run/lanes/a.json" ] && echo yes || echo no)"
rc=0; HO_SESSION_NAME=wrk HO_SESSION_ID=$wsid "$h" loop "$run" ready a --worktree "$w" --ticket 5 >/dev/null 2>&1 || rc=$?
assert_eq "H-086: its own ticket is recorded" "0 5" "$rc $(jq -r .ticket "$run/lanes/a.json" 2>/dev/null)"

# ---- an approval is the record approve writes, nothing else ----
assert_eq "test setup: the plan step of gated waits for a human (76)" 76 \
  "$(rc=0; "$h" autonomy "$run" check step --step plan --for 7 >/dev/null 2>&1 || rc=$?; echo $rc)"
mkdir -p "$run/approvals"
: > "$run/approvals/7.plan.json"
assert_eq "H-037 (#110): an empty file at the approval path is no approval (76)" 76 \
  "$(rc=0; "$h" autonomy "$run" check step --step plan --for 7 >/dev/null 2>&1 || rc=$?; echo $rc)"
printf '%s\n' '{"schemaVersion":2,"for":"8","point":"plan","approved":"2026-01-01T00:00:00Z"}' > "$run/approvals/7.plan.json"
assert_eq "H-037 (#110): an approval written for another ticket is no approval (76)" 76 \
  "$(rc=0; "$h" autonomy "$run" check step --step plan --for 7 >/dev/null 2>&1 || rc=$?; echo $rc)"
rm -f "$run/approvals/7.plan.json"
"$h" autonomy "$run" approve 7 plan >/dev/null
assert_eq "H-037: the approval approve writes passes the gate" 0 \
  "$(rc=0; "$h" autonomy "$run" check step --step plan --for 7 >/dev/null 2>&1 || rc=$?; echo $rc)"

# The approval is named in the ledger, not read as "not gated" (#58 verdict item 6).
assert_eq "H-037 (#110): the ledger says the gate passed by a human approval" "plan was approved by a human" \
  "$(jq -r 'select(.kind == "autonomy-check" and .for == "7" and .result == "0") | .reason' "$run/ledger.jsonl" | tail -n 1)"

# ---- H-040: only the safe profile refuses the engine's local merge (#58 verdict item 8) ----
# A gate and a passed verdict are set, so nothing but the profile can refuse.
jq -n '{schemaVersion: 2, gate: {use: "t", list: {t: {command: "true"}}}}' > "$PWD/user/config.json"
vsid=11111111-1111-4111-8111-111111111111
jq -n --arg run "$(basename "$run")" --arg sid "$vsid" \
  '{schemaVersion: 2, run: $run, name: "val", role: "validator", session_id: $sid, status: "running"}' > "$run/sessions/val.json"
printf 'passed\nevidence\n' | HO_SESSION_NAME=val HO_SESSION_ID=$vsid "$h" loop "$run" verdict a --sha "$(git -C "$w" rev-parse HEAD)" >/dev/null
printf '%s\n' '{"schemaVersion":2,"autonomy":{"profile":"safe"}}' > "$proj/.harness/config.json"
select_config "$proj"
rs=$("$h" run new)
cp "$run/integration.json" "$rs/integration.json"; mkdir -p "$rs/lanes" "$rs/sessions" "$rs/verdicts"
cp "$run/lanes/a.json" "$rs/lanes/"; cp -R "$run/verdicts/a" "$rs/verdicts/"
jq --arg r "$(basename "$rs")" '.run = $r' "$run/sessions/val.json" > "$rs/sessions/val.json"
jq --arg r "$(basename "$rs")" '.run = $r' "$run/sessions/wrk.json" > "$rs/sessions/wrk.json"
rc=0; "$h" loop "$rs" merge a >/dev/null 2>"$PWD/err" || rc=$?
assert_eq "H-040 safe (#110): with a gate and a passed verdict the safe profile still refuses the local merge (65)" 65 "$rc"
assert_contains "H-040 safe: the profile is what refused it" "$(cat "$PWD/err")" "not even a local one"
rc=0; "$h" loop "$run" merge a >/dev/null 2>"$PWD/err" || rc=$?
assert_eq "H-040: the same lane merges under gated, so only the profile refused it" 0 "$rc"

# ---- D44: the stricter never_push wins over a user's profile ----
printf '%s\n' '{"schemaVersion":2,"guardrails":{"never_push":true}}' > "$proj/.harness/config.json"
printf '%s\n' '{"schemaVersion":2,"autonomy":{"profile":"full"}}' > "$PWD/user/config.json"
assert_eq "D44 (#110): a user's autonomy.profile full does not loosen a project's never_push: true" safe "$("$h" autonomy show | jq -r .name)"
printf '%s\n' '{"schemaVersion":2,"guardrails":{"never_push":true},"autonomy":{"profile":"draft-pr"}}' > "$proj/.harness/config.json"
assert_eq "D44: the project's own profile is the project's own choice" draft-pr "$("$h" autonomy show | jq -r .name)"

# ---- an ended run says only that it has ended (cosmetic, #110) ----
printf '%s\n' '{"schemaVersion":2,"autonomy":{"profile":"draft-pr"}}' > "$proj/.harness/config.json"
printf '%s\n' '{"schemaVersion":2}' > "$PWD/user/config.json"
select_config "$proj"
re=$("$h" run new)
printf '%s\n' '{"kind":"run-end","reason":"test"}' >> "$re/ledger.jsonl"
printf 'x\n' > "$PWD/p.md"
rc=0; "$h" session "$re" launch --role worker --name e1 --cwd "$proj" --prompt "$PWD/p.md" >/dev/null 2>"$PWD/err" || rc=$?
assert_eq "H-079 (#110): a launch in an ended run says only that the run has ended (75)" "75 1 0" \
  "$rc $(grep -c 'has ended' "$PWD/err") $(grep -c 'is stopped' "$PWD/err" || true)"
rc=0; "$h" state "$re" begin --ticket 1 --step plan >/dev/null 2>"$PWD/err" || rc=$?
assert_eq "H-079 (#110): a step begin in an ended run says only that the run has ended (75)" "75 1 0" \
  "$rc $(grep -c 'has ended' "$PWD/err") $(grep -c 'is stopped' "$PWD/err" || true)"
