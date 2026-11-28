# Committed configs and the local selection (tasks.md 20.1, config part): H-070 (named
# committed configs, the selected one is used), H-071 (a local, untracked file selects it),
# H-072 (a missing confirmation stops a start and asks once; no silent pick, no fallback),
# H-077 (agent language, English by default), H-127/H-128 (/harness:config, onboard and init
# kept as aliases); design D33a, D37-FLOW-4, D37-FLOW-5, D37-FLOW-8 (b) (the record of the
# approved profile and its raise check at run start) and wave-4 follow-up #110 (a user
# autonomy.profile never overrides a project guardrails.never_push true).
h="$HO_PLUGIN_ROOT/bin/harness"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
base=$(cd -P "$PWD" && pwd)
proj="$base/proj"
user="$base/user"
mkdir -p "$proj/.harness" "$user"
git -C "$proj" init -q -b main
printf 'node_modules/\n' > "$proj/.gitignore"
printf '%s\n' '{"schemaVersion":2}' > "$user/config.json"
export HO_USER_DIR="$user"
unset HO_PROJECT_DIR
hp() { (cd "$proj" && "$h" "$@"); }
rc_of() { local rc=0; "$@" >"$base/out" 2>"$base/err" || rc=$?; echo "$rc"; }
sel() { jq -r "$1" "$proj/.harness/local.json"; }

# ---- H-070: two named configs, the selected one is used ---------------------------------------
printf '%s\n' '{"schemaVersion":2,"who":"shared","autonomy":{"profile":"safe"}}' > "$proj/.harness/config.json"
printf '%s\n' '{"schemaVersion":2,"who":"alice","autonomy":{"profile":"gated"}}' > "$proj/.harness/config.alice.json"
printf '%s\n' '{"schemaVersion":2,"who":"bob"}' > "$proj/.harness/config.bob.json"
assert_eq "H-070: config list names every committed config" "alice bob config" "$(hp config list | cut -f1 | sort | tr '\n' ' ' | sed 's/ $//')"

# ---- H-072: no local selection and a committed config: a start stops and offers it -------------
assert_eq "H-072 D37-FLOW-4: run new with no local selection stops (exit 73)" 73 "$(rc_of hp run new)"
assert_contains "H-072: the stop names the committed configs it found" "$(cat "$base/err")" "config.alice.json"
assert_contains "H-072: the stop names the configuration skill" "$(cat "$base/err")" "/harness:config"
assert_eq "H-072: the stop creates no run folder" 0 "$(find "$proj/.harness" -maxdepth 1 -name runs | wc -l | tr -d ' ')"
assert_eq "H-072: the stop writes no selector by itself" no "$([ -e "$proj/.harness/local.json" ] && echo yes || echo no)"
assert_eq "H-072: an unattended start stops too (exit 73)" 73 "$(rc_of hp config gate --unattended)"
assert_contains "H-072: an unattended start raises an attention notice" "$(cat "$base/err")" "attention"

# A user default never accepts a committed config.
printf '%s\n' '{"schemaVersion":2,"confirmed_default":{"flow":"gsd","requirements_format":"openspec"}}' > "$user/config.json"
assert_eq "H-072: a saved user default does not accept a committed config" 73 "$(rc_of hp run new)"
printf '%s\n' '{"schemaVersion":2}' > "$user/config.json"

# Inside a harness session nobody selects.
assert_eq "D37-FLOW-8: a selection is never written from inside a harness session" 77 "$(HO_SESSION_ID=x rc_of hp config select alice)"

# ---- H-071: the selection is local and untracked ----------------------------------------------
cp "$proj/.gitignore" "$base/gitignore.before"
assert_eq "H-071: config select alice succeeds" 0 "$(rc_of hp config select alice)"
assert_eq "H-071: the selector names the config, not a path" alice "$(sel .config)"
assert_eq "D37-FLOW-5: the selector holds no absolute path" no "$(grep -q "$base" "$proj/.harness/local.json" && echo yes || echo no)"
assert_eq "H-071: git ignores the selector" 0 "$(rc_of git -C "$proj" check-ignore -q .harness/local.json)"
assert_eq "H-071: the shared ignore file is unchanged" same "$(cmp -s "$proj/.gitignore" "$base/gitignore.before" && echo same || echo changed)"
assert_eq "D37-FLOW-5: only the selector is excluded, not the folder" 1 "$(rc_of git -C "$proj" check-ignore -q .harness/config.alice.json)"
hp config select alice >/dev/null 2>&1
assert_eq "D37-FLOW-5: selecting twice adds the exclude line once" 1 "$(grep -c 'local.json' "$proj/.git/info/exclude")"
assert_eq "H-070: the selected config is used" alice "$(hp config get .who x)"
assert_eq "H-070: the other committed configs are ignored" x "$(hp config get .nothere x)"
assert_eq "H-070: the selected config's profile is used" gated "$(hp autonomy show | jq -r .name)"

# ---- D37-FLOW-8 (b): the record of the approved profile ---------------------------------------
assert_eq "D37-FLOW-8: the selection records the approved profile" gated "$(sel .approved.profile)"
assert_eq "D37-FLOW-8: the record keeps the values next to the digest" draft "$(sel '.approved.fields["autonomy.pr"]')"
assert_eq "D37-FLOW-8: the record carries a digest" yes "$(sel '.approved.digest | if test("^[0-9a-f]{64}$") then "yes" else "no" end')"
run=$(hp run new 2>"$base/err") || run=""
assert_eq "H-072 D37-FLOW-8: with the selection and its record, run new starts" yes "$([ -n "$run" ] && [ -d "$run" ] && echo yes || echo no)"

# A raise in the committed config stops the next start and names the field.
printf '%s\n' '{"schemaVersion":2,"who":"alice","autonomy":{"profile":"full"}}' > "$proj/.harness/config.alice.json"
assert_eq "D37-FLOW-8: a raised profile stops the run at start" 73 "$(rc_of hp run new)"
assert_contains "D37-FLOW-8: the stop names a raised field" "$(cat "$base/err")" "autonomy.merge"
assert_contains "D37-FLOW-8: a human gate made automatic is named" "$(cat "$base/err")" "autonomy.gates"
assert_contains "D37-FLOW-8: the stop asks to select again with the configuration skill" "$(cat "$base/err")" "/harness:config"
assert_eq "D37-FLOW-8: the record is not changed by a raise" gated "$(sel .approved.profile)"
# A lowering is accepted and the record is updated (draft-pr to safe lowers every field).
printf '%s\n' '{"schemaVersion":2,"who":"alice","autonomy":{"profile":"draft-pr"}}' > "$proj/.harness/config.alice.json"
hp config select alice >/dev/null 2>&1
printf '%s\n' '{"schemaVersion":2,"who":"alice","autonomy":{"profile":"safe"}}' > "$proj/.harness/config.alice.json"
assert_eq "D37-FLOW-8: a lowered profile starts" 0 "$(rc_of hp run new)"
assert_eq "D37-FLOW-8: a lowering updates the record" safe "$(sel .approved.profile)"
# Each recorded field type.
raise_of() { # <committed-config-json-after>: select the base, write the change, print the gate rc
  printf '%s\n' "$1" > "$proj/.harness/config.alice.json"; hp config select alice >/dev/null 2>&1
  printf '%s\n' "$2" > "$proj/.harness/config.alice.json"; rc_of hp config gate
}
assert_eq "D37-FLOW-8: on_not_ready ask to assume is a raise" 73 \
  "$(raise_of '{"schemaVersion":2,"tickets":{"readiness":{"on_not_ready":"ask"}}}' '{"schemaVersion":2,"tickets":{"readiness":{"on_not_ready":"assume"}}}')"
assert_eq "D37-FLOW-8: on_not_ready assume to ask is a lowering" 0 \
  "$(raise_of '{"schemaVersion":2,"tickets":{"readiness":{"on_not_ready":"assume"}}}' '{"schemaVersion":2,"tickets":{"readiness":{"on_not_ready":"ask"}}}')"
assert_eq "D37-FLOW-8: an added review bot is a raise" 73 \
  "$(raise_of '{"schemaVersion":2,"external_review_bots":["a"]}' '{"schemaVersion":2,"external_review_bots":["a","b"]}')"
assert_eq "D37-FLOW-8: a removed always-a-human path is a raise" 73 \
  "$(raise_of '{"schemaVersion":2,"autonomy":{"always_human_paths":["a/*","b/*"]}}' '{"schemaVersion":2,"autonomy":{"always_human_paths":["a/*"]}}')"
assert_eq "D37-FLOW-8: a lowered wait limit is a raise" 73 \
  "$(raise_of '{"schemaVersion":2,"external_review":{"wait":{"total_minutes":30}}}' '{"schemaVersion":2,"external_review":{"wait":{"total_minutes":10}}}')"
assert_eq "D37-FLOW-8: a human gate made automatic is a raise" 73 \
  "$(raise_of '{"schemaVersion":2,"autonomy":{"profile":"gated"}}' '{"schemaVersion":2,"autonomy":{"profile":"custom","custom":{"gates":{},"push":false,"pr":"none","pr_open":"none","merge":"never","post_merge":false,"deploy_production":false,"remarks":"human","allow_zero_tests":false}}}')"
assert_eq "D37-FLOW-8: a value the ranking cannot place is a raise" 73 \
  "$(raise_of '{"schemaVersion":2,"tickets":{"readiness":{"on_not_ready":"ask"}}}' '{"schemaVersion":2,"tickets":{"readiness":{"on_not_ready":"maybe"}}}')"
assert_eq "D37-FLOW-8: a dropped always-a-human list is a raise" 73 \
  "$(raise_of '{"schemaVersion":2,"autonomy":{"always_human_paths":["a/*"]}}' '{"schemaVersion":2}')"
assert_eq "D37-FLOW-8: a dropped profile is a raise (a looser user profile could apply)" 73 \
  "$(raise_of '{"schemaVersion":2,"autonomy":{"profile":"safe"}}' '{"schemaVersion":2}')"
assert_eq "D37-FLOW-8: a change of a setting that is not recorded starts" 0 \
  "$(raise_of '{"schemaVersion":2,"who":"a"}' '{"schemaVersion":2,"who":"b"}')"
# A selection without a record (as after an upgrade), or with a damaged record, stops once.
hp config select alice >/dev/null 2>&1
jq 'del(.approved)' "$proj/.harness/local.json" > "$base/l" && mv "$base/l" "$proj/.harness/local.json"
assert_eq "D37-FLOW-8: a selection of a committed config with no record stops" 73 "$(rc_of hp config gate)"
hp config select alice >/dev/null 2>&1
jq '.approved.fields["autonomy.push"] = false' "$proj/.harness/local.json" > "$base/l" && mv "$base/l" "$proj/.harness/local.json"
assert_eq "D37-FLOW-8: a record whose values do not match its digest stops" 73 "$(rc_of hp config gate)"
hp config select alice >/dev/null 2>&1

# A selector committed to the repository is no confirmation.
git -C "$proj" add -f .harness/local.json
assert_eq "D37-FLOW-5: a selector tracked by git stops the start" 73 "$(rc_of hp config gate)"
assert_contains "D37-FLOW-5: the stop says the selection is tracked" "$(cat "$base/err")" "tracked by git"
git -C "$proj" rm -q --cached .harness/local.json
assert_eq "D37-FLOW-5: an untracked selector starts again" 0 "$(rc_of hp config gate)"

# ---- H-072: a selection that names a missing config: no fallback -------------------------------
mv "$proj/.harness/config.alice.json" "$base/alice.keep"
assert_eq "H-072: a selection of a missing config stops the start" 73 "$(rc_of hp run new)"
assert_eq "H-072: a missing selected config is not replaced by another config" 78 "$(rc_of hp config get .who x)"
mv "$base/alice.keep" "$proj/.harness/config.alice.json"

# ---- H-071: worktrees read the selector of the main checkout ----------------------------------
git -C "$proj" add .gitignore .harness/config.json .harness/config.alice.json .harness/config.bob.json
git -C "$proj" commit -qm configs
git -C "$proj" worktree add -q "$base/wt" -b wt
assert_eq "D37-FLOW-5: a worktree has no selector of its own" no "$([ -e "$base/wt/.harness/local.json" ] && echo yes || echo no)"
printf '%s\n' "$proj" > "$base/wt/.harness-project"
assert_eq "D37-FLOW-5: a worktree reads the main checkout's selection" "$(hp config get .who x)" "$(cd "$base/wt" && "$h" config get .who x)"

# ---- the default path: nothing committed ------------------------------------------------------
p2="$base/p2"
mkdir -p "$p2"
git -C "$p2" init -q -b main
assert_eq "H-072: with nothing configured anywhere, run new stops" 73 "$(cd "$p2" && rc_of "$h" run new)"
assert_contains "H-072: the stop offers the default flow" "$(cat "$base/err")" "gsd"
assert_contains "H-072: the stop offers the default requirements format" "$(cat "$base/err")" "openspec"
assert_contains "H-072: the stop names the configuration skill" "$(cat "$base/err")" "/harness:config"
assert_eq "H-072: config select --default records the confirmation" 0 "$(cd "$p2" && rc_of "$h" config select --default)"
assert_eq "H-072: the selector records the confirmed default" "null confirmed gsd openspec" \
  "$(jq -r '[.config, .default.source, .default.flow, .default.requirements_format] | map(tostring) | join(" ")' "$p2/.harness/local.json")"
assert_eq "H-072: on the confirmed default, run new starts" 0 "$(cd "$p2" && rc_of "$h" run new)"
assert_eq "H-076 D37-FLOW-7: the confirmed default format reads as openspec" openspec "$(cd "$p2" && "$h" config get .requirements.format none)"
assert_eq "D37-FLOW-7: a declined OpenSpec setup records none on this machine" 0 "$(cd "$p2" && rc_of "$h" config format none)"
assert_eq "D37-FLOW-7: the local none wins" none "$(cd "$p2" && "$h" config get .requirements.format x)"
# A config committed later: kept selection, one notice.
printf '%s\n' '{"schemaVersion":2,"who":"late"}' > "$p2/.harness/config.late.json"
assert_eq "H-072: a config committed after a start on the default keeps the selection" 0 "$(cd "$p2" && rc_of "$h" config gate)"
assert_contains "H-072: one notice names the new config" "$(cat "$base/err")" "config.late.json"
(cd "$p2" && "$h" config gate >/dev/null 2>"$base/err2")
assert_eq "H-072: the notice is printed once" "" "$(grep -F config.late.json "$base/err2" || true)"
assert_eq "H-072: the new config is not used until selected" x "$(cd "$p2" && "$h" config get .who x)"
# A saved user default: the run starts without a question.
p3="$base/p3"
mkdir -p "$p3"
git -C "$p3" init -q -b main
assert_eq "H-072: config save-default writes the confirmation into the user config" 0 "$(cd "$p3" && rc_of "$h" config save-default)"
assert_eq "H-072: the saved user default holds the flow and the format" "gsd openspec" "$(jq -r '.confirmed_default | "\(.flow) \(.requirements_format)"' "$user/config.json")"
assert_eq "H-072: with a saved user default and nothing committed, run new starts" 0 "$(cd "$p3" && rc_of "$h" run new)"
assert_eq "H-072: the selector records that the confirmation came from the user settings" user "$(jq -r .default.source "$p3/.harness/local.json")"
printf '%s\n' '{"schemaVersion":2}' > "$user/config.json"

# ---- H-077: agent language --------------------------------------------------------------------
assert_eq "H-077: the default agent language is English" English "$(hp config language)"
printf '%s\n' '{"schemaVersion":2,"agent":{"language":"Ukrainian"}}' > "$user/config.json"
assert_eq "H-077: a selected language is used" Ukrainian "$(hp config language)"
printf '%s\n' '{"schemaVersion":2}' > "$user/config.json"
printf 'ticket body\n' | "$h" tickets fence 1 > "$base/ticket.txt"
r=$("$h" flow render basic worker --step "$("$h" flow steps basic | head -1 | cut -f2)" \
  --set RUN_ID r --set TICKET_ID 1 --file TICKET_TEXT "$base/ticket.txt" --set BRANCH b --set BASE m --set WORKDIR /w \
  --set STEP_RESULT_FILE /r --set VERDICT_FILE /v --set LANE t1 --set SHA 0123abc 2>&1) || true
assert_contains "H-077: the worker prompt tells the agent to communicate in English by default" "$r" "Communicate in English"

# ---- #110: a user's autonomy.profile never overrides a project's never_push true --------------
printf '%s\n' '{"schemaVersion":2,"guardrails":{"never_push":true}}' > "$proj/.harness/config.alice.json"
hp config select alice >/dev/null 2>&1
printf '%s\n' '{"schemaVersion":2,"autonomy":{"profile":"full"}}' > "$user/config.json"
assert_eq "#110 D12: a user profile does not override a project never_push true" safe "$(hp autonomy show | jq -r .name)"
printf '%s\n' '{"schemaVersion":2,"guardrails":{"never_push":false}}' > "$proj/.harness/config.alice.json"
hp config select alice >/dev/null 2>&1
assert_eq "D12: a user profile still beats a project never_push false" full "$(hp autonomy show | jq -r .name)"
printf '%s\n' '{"schemaVersion":2}' > "$user/config.json"

# ---- H-127 D33a: the skill and its aliases ----------------------------------------------------
c="$HO_PLUGIN_ROOT/commands"
assert_eq "H-127: /harness:config ships" yes "$([ -f "$c/config.md" ] && echo yes || echo no)"
for a in onboard init; do
  assert_contains "D33a: /harness:$a still runs the config skill" "$(cat "$c/$a.md" 2>/dev/null)" 'commands/config.md'
done
assert_contains "D33a: the first description line names the other skill" "$(sed -n '/^description:/p' "$c/config.md" 2>/dev/null)" "/harness:ai-ready"
assert_contains "H-128: the skill offers the limit thresholds at 90%" "$(cat "$c/config.md" 2>/dev/null)" "90%"
assert_contains "H-077: the skill offers the agent language, English by default" "$(cat "$c/config.md" 2>/dev/null)" "agent.language"
