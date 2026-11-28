# Autonomy profiles checked by the engine (tasks.md 14.1): H-036 (profile read once per run),
# H-037 (step gates), H-038 (ready-made plus custom), H-039 (no stage), H-040 (safe default, nothing
# leaves the machine), H-041 (full works), H-042 (ticket stops at the last allowed step), H-047
# (merge gate; classifier only in custom), H-048 (no ready-made deploys to production), H-049
# (production deploy only in the user's own profile); design D12, S8-08a, S8-08b.
h="$HO_PLUGIN_ROOT/bin/harness"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
proj="$PWD/proj"
mkdir -p "$proj/.harness" "$PWD/user"
git -C "$proj" init -q -b main
printf '.harness/\n' >> "$proj/.git/info/exclude"
printf 'base\n' > "$proj/shared.txt"
git -C "$proj" add shared.txt && git -C "$proj" commit -qm base
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$PWD/user" HO_TICKETS_DIR="$proj/.harness/tickets"
printf '%s\n' '{"schemaVersion":2}' > "$PWD/user/config.json"
pcfg() { printf '%s\n' "$1" > "$proj/.harness/config.json"; }
profile() { pcfg "{\"schemaVersion\":2,\"autonomy\":{\"profile\":\"$1\"}}"; }
check_rc() { local rc=0; "$h" autonomy "$run" check "$@" >/dev/null 2>"$PWD/err" || rc=$?; echo "$rc"; }
newrun() { select_config "$proj"; run=$("$h" run new); }
dir="$HO_PLUGIN_ROOT/autonomy"

# ---- the ready-made profile files ------------------------------------------------------------
assert_eq "H-038 D12: four ready-made profiles ship" "draft-pr full gated safe" \
  "$(cd "$dir" && ls ./*.json | sed 's#^\./##; s#\.json$##' | sort | tr '\n' ' ' | sed 's/ $//')"
for p in safe gated draft-pr full; do
  assert_eq "H-048: ready-made profile $p has deploy_production: no" false "$(jq -r .deploy_production "$dir/$p.json")"
  assert_eq "H-047 D12: ready-made profile $p does not use merge: classifier" yes \
    "$(jq -r 'if .merge != "classifier" then "yes" else "no" end' "$dir/$p.json")"
  assert_eq "H-039: ready-made profile $p names no stage environment" 0 "$(grep -ci stage "$dir/$p.json" || true)"
  assert_eq "D12: ready-made profile $p holds every profile field" \
    "allow_zero_tests deploy_production gates merge post_merge pr pr_open push remarks" \
    "$(jq -r 'del(.schemaVersion, .name, .description) | keys | join(" ")' "$dir/$p.json")"
done

# ---- H-040: a new project with no choice uses safe -------------------------------------------
pcfg '{"schemaVersion":2}'
assert_eq "H-040: with no profile chosen the project uses safe" safe "$("$h" autonomy show | jq -r .name)"
assert_eq "H-040: the source of the safe profile is the default" default "$("$h" autonomy show | jq -r .source)"
profile nope
assert_exit "D12: an unknown profile name is a config error" 78 "$h" autonomy show

# ---- safe: no push, no PR, no merge (not even local), ticket ends in needs-review ------------
profile safe
newrun
assert_eq "H-040 safe: push is refused" 77 "$(check_rc push)"
assert_eq "H-040 safe: a draft PR is refused" 77 "$(check_rc pr)"
assert_eq "H-040 safe: a merge into the target is refused" 77 "$(check_rc merge)"
assert_eq "H-040 safe: even a local integration merge is refused" 77 "$(check_rc merge --local --for a)"
assert_eq "H-048 safe: production deploy is refused" 77 "$(check_rc deploy)"
assert_eq "S8-08a: every check writes one ledger line" 5 "$(jq -r .kind "$run/ledger.jsonl" | grep -c '^autonomy-check$' || true)"
# The engine's own merge (lib/loop.sh) asks the profile first.
int="$PWD/int"
"$h" loop "$run" integration --repo "$proj" --base main --worktree "$int" >/dev/null
git -C "$proj" worktree add -q -b lane-a "$PWD/w-a" main
printf 'from a\n' > "$PWD/w-a/a.txt"; git -C "$PWD/w-a" add a.txt; git -C "$PWD/w-a" commit -qm "work a"
git -C "$PWD/w-a" commit -q --allow-empty -m "finalize(a): done"
"$h" loop "$run" ready a --worktree "$PWD/w-a" >/dev/null
rc=0; "$h" loop "$run" merge a >/dev/null 2>"$PWD/err" || rc=$?
assert_eq "H-040 safe: the engine's local merge is refused by the profile" 65 "$rc"
assert_contains "H-040 safe: the refusal names the profile rule" "$(cat "$PWD/err")" "not even a local one"
assert_eq "H-040 safe: the integration branch did not move" "$(git -C "$proj" rev-parse main)" \
  "$(git -C "$proj" rev-parse "refs/heads/$(jq -r .branch "$run/integration.json")")"
printf 'body\n' > "$PWD/body.md"
"$h" tickets add "Ticket one" "$PWD/body.md" in-progress >/dev/null
"$h" autonomy "$run" end 1 >/dev/null
assert_contains "H-040 H-042 safe: the ticket ends in needs-review" "$("$h" tickets show 1)" "needs-review"

# ---- gated: human gates after readiness, plan and PR; push and draft PR; no merge -------------
profile gated
newrun
assert_eq "D12 gated: push is allowed" 0 "$(check_rc push)"
assert_eq "D12 gated: a draft PR is allowed" 0 "$(check_rc pr)"
assert_eq "D12 gated: marking the PR ready is refused" 77 "$(check_rc pr-ready)"
assert_eq "D12 gated: a merge is refused" 77 "$(check_rc merge)"
assert_eq "H-037 gated: the plan step waits for a human" 76 "$(check_rc step --step plan --for 1)"
assert_eq "H-037 gated: the readiness point waits for a human" 76 "$(check_rc step --step readiness --for 1)"
assert_eq "H-037 gated: the execute step is not gated" 0 "$(check_rc step --step execute --for 1)"
rc=0; HO_SESSION_NAME=w HO_SESSION_ID=x "$h" autonomy "$run" approve 1 plan >/dev/null 2>&1 || rc=$?
assert_eq "H-037: an approval from inside a harness session is refused" 77 "$rc"
assert_eq "H-037: the gate still waits after the refused approval" 76 "$(check_rc step --step plan --for 1)"
"$h" autonomy "$run" approve 1 plan >/dev/null
assert_eq "H-037: after a human approves, the plan step may pass" 0 "$(check_rc step --step plan --for 1)"
assert_eq "H-037: the approval covers only its own ticket" 76 "$(check_rc step --step plan --for 2)"

# ---- draft-pr: no gates, push and draft PR, then stop ----------------------------------------
profile draft-pr
newrun
assert_eq "H-038 draft-pr: the plan step is not gated" 0 "$(check_rc step --step plan --for 1)"
assert_eq "H-038 draft-pr: push is allowed" 0 "$(check_rc push)"
assert_eq "H-038 draft-pr: a draft PR is allowed" 0 "$(check_rc pr)"
assert_eq "H-038 draft-pr: marking the PR ready is refused" 77 "$(check_rc pr-ready)"
assert_eq "H-038 draft-pr: a merge is refused" 77 "$(check_rc merge)"
assert_eq "H-038 draft-pr: a release (post-merge steps) is refused" 77 "$(check_rc post-merge)"
"$h" tickets add "Ticket two" "$PWD/body.md" in-progress >/dev/null
"$h" autonomy "$run" end 2 >/dev/null
assert_contains "H-042 draft-pr: the ticket stops at needs-review after the draft PR" "$("$h" tickets show 2)" "needs-review"

# ---- full: merges only when every S8-08b condition holds -------------------------------------
profile full
newrun
assert_eq "H-041 full: push is allowed" 0 "$(check_rc push)"
assert_eq "H-041 full: marking the PR ready is allowed" 0 "$(check_rc pr-ready)"
assert_eq "H-041 full: post-merge steps are allowed" 0 "$(check_rc post-merge)"
assert_eq "H-048 full: production deploy is refused" 77 "$(check_rc deploy)"
assert_eq "S8-08b full: a merge without facts is refused" 77 "$(check_rc merge)"
good='{"validator":"passed","tests":{"total":12,"failed":0},"ci":"green","open_questions":0,"paths":["src/a.sh"]}'
facts() { printf '%s\n' "$good" | jq -c "$1" > "$PWD/facts.json"; }
facts .
assert_eq "H-041 S8-08b full: with every condition held the merge is allowed" 0 "$(check_rc merge --facts "$PWD/facts.json")"
for c in '.validator = "passed with remarks"|validator' '.tests.failed = 1|failed test' '.tests.total = 0|zero tests' \
    '.ci = "pending"|CI' '.open_questions = 1|open question' 'del(.paths)|changed paths' 'del(.tests)|test count' 'del(.ci)|CI missing'; do
  facts "${c%%|*}"
  assert_eq "S8-08b full: a merge is refused when one condition fails (${c#*|})" 77 "$(check_rc merge --facts "$PWD/facts.json")"
done
printf '%s\n' '{"schemaVersion":2,"autonomy":{"always_human_paths":["src/*"]}}' > "$PWD/user/config.json"
facts .
assert_eq "S8-08b full: a change on the always-a-human list is refused (user list)" 77 "$(check_rc merge --facts "$PWD/facts.json")"
assert_contains "S8-08b full: the refusal names the path" "$(cat "$PWD/err")" "src/a.sh"
facts '.paths = ["docs/x.md"]'
assert_eq "S8-08b full: a change outside the list may merge" 0 "$(check_rc merge --facts "$PWD/facts.json")"
printf '%s\n' '{"schemaVersion":2}' > "$PWD/user/config.json"
facts '.tests = 12'
assert_eq "S8-08b full: tests that are not an object with counts are refused" 77 "$(check_rc merge --facts "$PWD/facts.json")"
facts '.tests = "x"'
assert_eq "S8-08b full: a test count jq cannot read is refused, never taken as held" 77 "$(check_rc merge --facts "$PWD/facts.json")"
printf '%s\n' 'not json' > "$PWD/facts.json"
assert_eq "S8-08b full: unreadable facts are refused" 77 "$(check_rc merge --facts "$PWD/facts.json")"
"$h" tickets add "Ticket three" "$PWD/body.md" in-progress >/dev/null
"$h" autonomy "$run" end 3 >/dev/null
assert_contains "H-045: under full the ticket waits for the confirmed merge, not needs-review" "$("$h" tickets show 3)" "in-progress"

# ---- custom: the user sets every field ---------------------------------------------------------
custom() { pcfg "$(jq -cn --argjson c "$1" '{schemaVersion: 2, autonomy: {profile: "custom", custom: $c}}')"; }
base='{"gates":{},"push":false,"pr":"none","pr_open":"none","merge":"never","post_merge":false,"deploy_production":false,"remarks":"human","allow_zero_tests":false}'
custom "$(printf '%s' "$base" | jq -c '.gates = {"execute": "human"}')"
newrun
assert_eq "H-037 custom: a human gate after execution stops there" 76 "$(check_rc step --step execute --for 4)"
assert_eq "H-037 custom: the step before it is not gated" 0 "$(check_rc step --step plan --for 4)"
custom "$(printf '%s' "$base" | jq -c '.gates = {"start": "human"}')"
newrun
assert_eq "H-037 custom: a ticket may not start without a human" 76 "$(check_rc start --for 4)"
custom "$(printf '%s' "$base" | jq -c 'del(.remarks)')"
assert_exit "H-038 custom: a custom profile with a missing field is refused" 78 "$h" autonomy show
custom "$(printf '%s' "$base" | jq -c '.mergee = "always"')"
assert_exit "D12 custom: an unknown field is refused, never ignored" 78 "$h" autonomy show
custom "$(printf '%s' "$base" | jq -c '.gates = {"plan": "maybe"}')"
assert_exit "D12 custom: a gate value other than auto or human is refused" 78 "$h" autonomy show
custom "$(printf '%s' "$base" | jq -c '.merge = "classifier" | .push = true')"
newrun
assert_eq "H-047 custom: the classifier merge waits for a human" 76 "$(check_rc merge --facts "$PWD/facts.json")"
custom "$(printf '%s' "$base" | jq -c '.merge = "always"')"
newrun
assert_eq "H-043 custom: no push but merge always still allows a local integration merge" 0 "$(check_rc merge --local --for a)"
facts '.tests.total = 0'
custom "$(printf '%s' "$base" | jq -c '.merge = "always" | .allow_zero_tests = true')"
newrun
assert_eq "D12 custom: allow_zero_tests lets a merge with zero tests pass" 0 "$(check_rc merge --facts "$PWD/facts.json")"
custom "$(printf '%s' "$base" | jq -c '.deploy_production = true')"
newrun
assert_eq "H-049 custom: production deploy without a configured deployment is refused" 77 "$(check_rc deploy)"
pcfg "$(jq -cn --argjson c "$(printf '%s' "$base" | jq -c '.deploy_production = true')" '{schemaVersion: 2, deploy: {use: "prod"}, autonomy: {profile: "custom", custom: $c}}')"
newrun
assert_eq "H-049 custom: the user's own profile may deploy when deployment is configured" 0 "$(check_rc deploy)"

# ---- ready-made files are guarded too -----------------------------------------------------------
mkdir -p "$PWD/au"
cp "$dir"/*.json "$PWD/au/"
jq '.deploy_production = true' "$dir/full.json" > "$PWD/au/full.json"
profile full
assert_exit "H-048: a ready-made profile that deploys to production is refused" 78 env HO_AUTONOMY_DIR="$PWD/au" "$h" autonomy show
jq '.merge = "classifier"' "$dir/full.json" > "$PWD/au/full.json"
assert_exit "H-047 D12: a ready-made profile with the classifier is refused" 78 env HO_AUTONOMY_DIR="$PWD/au" "$h" autonomy show

# ---- a damaged run profile is refused, never read as empty -------------------------------------
profile full
newrun
check_rc push >/dev/null
: > "$run/autonomy.json"
assert_eq "H-036: an empty run profile is a config error, not an allow" 78 "$(check_rc merge --local --for a)"
printf '%s\n' '"text"' > "$run/autonomy.json"
assert_eq "H-036: a run profile that is not an object is a config error" 78 "$(check_rc step --step plan)"

# ---- the pr gate: a draft opens, marking it ready waits for a human -----------------------------
custom "$(printf '%s' "$base" | jq -c '.push = true | .pr = "ready" | .gates = {"pr": "human"}')"
newrun
assert_eq "H-037 custom: with a pr gate the draft PR may open" 0 "$(check_rc pr --for 5)"
assert_eq "H-037 custom: with a pr gate marking the PR ready waits for a human" 76 "$(check_rc pr-ready --for 5)"
"$h" autonomy "$run" approve 5 pr >/dev/null
assert_eq "H-037 custom: after approval the PR may be marked ready" 0 "$(check_rc pr-ready --for 5)"

# ---- H-036: a run keeps the profile it read at its start ---------------------------------------
profile safe
newrun
check_rc push >/dev/null
profile full
assert_eq "H-036: a config change during a run does not raise that run's profile" 77 "$(check_rc push)"
newrun
assert_eq "H-036: the next run reads the changed profile" 0 "$(check_rc push)"

# ---- migration from 0.6.0 (D12) ---------------------------------------------------------------
printf '%s\n' '{"schemaVersion":1,"workflow":"gsd","guardrails":{"owner_gated":true,"never_push":true}}' > "$PWD/old-true.json"
printf '%s\n' '{"schemaVersion":1,"guardrails":{"never_push":false}}' > "$PWD/old-false.json"
printf '%s\n' '{"schemaVersion":1,"workflow":"gsd"}' > "$PWD/old-none.json"
assert_eq "D12 migration: a 0.6.0 config with never_push: true loads as safe" safe "$("$h" autonomy migrate "$PWD/old-true.json")"
assert_eq "D12 migration: a 0.6.0 config with never_push: false loads as draft-pr" draft-pr "$("$h" autonomy migrate "$PWD/old-false.json")"
assert_eq "D12 migration: a 0.6.0 config without never_push (default true) loads as safe" safe "$("$h" autonomy migrate "$PWD/old-none.json")"
pcfg '{"schemaVersion":2,"guardrails":{"never_push":true}}'
assert_eq "D12 migration: never_push: true kept in a config selects safe" safe "$("$h" autonomy show | jq -r .name)"
pcfg '{"schemaVersion":2,"guardrails":{"never_push":false}}'
assert_eq "D12 migration: never_push: false kept in a config selects draft-pr" draft-pr "$("$h" autonomy show | jq -r .name)"
pcfg '{"schemaVersion":2,"guardrails":{"never_push":false},"autonomy":{"profile":"safe"}}'
assert_eq "D12 migration: autonomy.profile wins over never_push" safe "$("$h" autonomy show | jq -r .name)"

# ---- H-036: a check from another project uses the run's own project, never the caller's ------
# The run's profile is read once, from the project the run belongs to. A caller standing in a
# project set to full must not lift a safe run to full, nor cache full into the run.
profile safe
select_config "$proj"; runA=$("$h" run new)
projB="$PWD/projB"
mkdir -p "$projB/.harness"
printf '%s\n' '{"schemaVersion":2,"autonomy":{"profile":"full"} }' > "$projB/.harness/config.json"
rc=0; (cd "$projB" && env -u HO_PROJECT_DIR "$h" autonomy "$runA" check push >/dev/null 2>&1) || rc=$?
assert_eq "H-036: a check from another project set to full does not allow push in a safe run (77)" 77 "$rc"
assert_eq "H-036: the run's profile is cached from its own project (safe)" safe \
  "$(jq -r '.name // .profile // empty' "$runA/autonomy.json" 2>/dev/null)"
rc=0; (cd "$projB" && HO_PROJECT_DIR="$projB" "$h" autonomy "$runA" check push >/dev/null 2>&1) || rc=$?
assert_eq "H-036: HO_PROJECT_DIR naming another project is refused for a run-specific check (65)" 65 "$rc"
# The engine's own merge reads the profile too: from another project it still reads the run's.
profile safe
select_config "$proj"; runM=$("$h" run new)
"$h" loop "$runM" integration --repo "$proj" --base main --worktree "$PWD/int-m" >/dev/null
git -C "$proj" worktree add -q -b lane-m "$PWD/w-m" main
printf 'from m\n' > "$PWD/w-m/m.txt"; git -C "$PWD/w-m" add m.txt; git -C "$PWD/w-m" commit -qm "work m"
git -C "$PWD/w-m" commit -q --allow-empty -m "finalize(m): done"
"$h" loop "$runM" ready m --worktree "$PWD/w-m" >/dev/null
rc=0; (cd "$projB" && env -u HO_PROJECT_DIR "$h" loop "$runM" merge m >/dev/null 2>"$PWD/err-m") || rc=$?
assert_eq "H-036: a loop merge from another project set to full is refused by the run's safe profile (65)" 65 "$rc"
assert_eq "H-036: the merge caches the run's own profile (safe)" safe "$(jq -r '.name // empty' "$runM/autonomy.json" 2>/dev/null)"

# H-042 H-036: "autonomy <run> end <ticket>" called from another project with HO_TICKETS_DIR unset
# ends the ticket of the run's own project, never a ticket in the caller's folder.
ta=$("$h" tickets add "End from elsewhere" "$PWD/body.md" in-progress | sed -n 's/^OK created ticket \([0-9]*\).*/\1/p')
bf="$PWD/body.md"
for i in $(seq 1 "$ta"); do
  (cd "$projB" && env -u HO_TICKETS_DIR "$h" tickets add "B ticket $i" "$bf" in-progress >/dev/null)
done
rc=0; (cd "$projB" && env -u HO_PROJECT_DIR -u HO_TICKETS_DIR "$h" autonomy "$runA" end "$ta" >/dev/null 2>&1) || rc=$?
assert_eq "H-042 an end from another project succeeds for the run's ticket" 0 "$rc"
assert_contains "H-042 the run's own ticket ends in needs-review" "$("$h" tickets show "$ta")" "needs-review"
assert_contains "H-042 the caller's ticket with the same number is untouched" \
  "$(cd "$projB" && env -u HO_TICKETS_DIR "$h" tickets show "$ta")" "in-progress"
