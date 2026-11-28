# Optional requirements format and the project setup command (tasks.md 20.1, project setup part):
# H-074 (a project never depends on the harness), H-076 (requirements.format none | openspec;
# a project without OpenSpec is normal; an openspec/ folder alone decides nothing; grilling may
# ignore the requirements), H-129 (/harness:ai-ready applies AI-development practices and sets up
# no flow system); design D33a, D41, D37-FLOW-7, D37-DISTRIBUTION-1.
h="$HO_PLUGIN_ROOT/bin/harness"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
base=$(cd -P "$PWD" && pwd)
proj="$base/proj"
user="$base/user"
mkdir -p "$proj/.harness" "$user"
git -C "$proj" init -q -b main
printf 'x\n' > "$proj/README.md"
git -C "$proj" add README.md && git -C "$proj" commit -qm base
printf '%s\n' '{"schemaVersion":2}' > "$user/config.json"
export HO_USER_DIR="$user" HO_PROJECT_DIR="$proj"
pcfg() { printf '%s\n' "$1" > "$proj/.harness/config.json"; select_config "$proj"; }
printf 'ticket body\n' | "$h" tickets fence 7 > "$base/ticket.txt"
grill() { # <flow>: the rendered grilling step of the worker prompt
  "$h" flow render "$1" worker --step grill --set RUN_ID r --set TICKET_ID 7 --file TICKET_TEXT "$base/ticket.txt" \
    --set BRANCH b --set BASE m --set WORKDIR /w --set STEP_RESULT_FILE /r --set VERDICT_FILE /v --set LANE t1 --set SHA 0123abc 2>&1 || true
}
plan() {
  "$h" flow render "$1" worker --step plan --set RUN_ID r --set TICKET_ID 7 --file TICKET_TEXT "$base/ticket.txt" \
    --set BRANCH b --set BASE m --set WORKDIR /w --set STEP_RESULT_FILE /r --set VERDICT_FILE /v --set LANE t1 --set SHA 0123abc 2>&1 || true
}

# ---- H-076: a project without OpenSpec is a normal case ----------------------------------------
pcfg '{"schemaVersion":2,"requirements":{"format":"none"}}'
for f in gsd basic; do
  assert_eq "H-076: with format none the $f grilling step adds nothing about OpenSpec" 0 "$(grill $f | grep -ci openspec || true)"
done
mkdir -p "$proj/openspec/specs"
assert_eq "H-076 D37-FLOW-7: an openspec/ folder alone decides nothing" 0 "$(grill gsd | grep -ci openspec || true)"

# ---- D41: with OpenSpec on, one text block is added to the grilling step ----------------------
pcfg '{"schemaVersion":2,"requirements":{"format":"openspec"}}'
assert_eq "D41: with OpenSpec on, the grilling step gets one requirements block" 1 "$(grill gsd | grep -c 'BEGIN REQUIREMENTS BLOCK' || true)"
assert_contains "D41: the block reads the requirements and never adopts them" "$(grill gsd)" "never adopt"
assert_eq "D41: other steps get no requirements block" 0 "$(plan gsd | grep -ci openspec || true)"
pcfg '{"schemaVersion":2,"requirements":{"format":"openspec","use_in_grilling":false}}'
assert_eq "H-076: grilling set to ignore the requirements adds no block" 0 "$(grill gsd | grep -ci openspec || true)"
printf '%s\n' '{"schemaVersion":2,"requirements":{"format":"openspec"}}' > "$user/config.json"
pcfg '{"schemaVersion":2,"requirements":{"format":"none"}}'
assert_eq "H-076: the project format beats the user format" none "$("$h" config get .requirements.format x)"
assert_eq "H-076: the project none wins in the render too" 0 "$(grill gsd | grep -ci openspec || true)"
printf '%s\n' '{"schemaVersion":2}' > "$user/config.json"
rm -rf "$proj/openspec"

# ---- H-076: OpenSpec is set up only after a yes -----------------------------------------------
pcfg '{"schemaVersion":2,"requirements":{"format":"openspec"}}'
"$h" config gate >/dev/null 2>&1 || true
"$h" run new >/dev/null 2>&1 || true
assert_eq "H-076: the engine never creates an openspec/ folder by itself" no "$([ -e "$proj/openspec" ] && echo yes || echo no)"
c="$HO_PLUGIN_ROOT/commands"
assert_contains "H-076: the configuration command sets OpenSpec up only after a yes" "$(cat "$c/config.md")" "only after a yes"
assert_contains "H-076: the project setup command sets OpenSpec up only after a yes" "$(cat "$c/ai-ready.md" 2>/dev/null)" "only after a yes"

# ---- H-074: a clone used without the harness has no harness step ------------------------------
assert_eq "H-074: the harness installs no git hook" "" "$(find "$proj/.git/hooks" -type f ! -name '*.sample' 2>/dev/null)"
assert_eq "H-074: the shared ignore file is not created or changed" no "$([ -e "$proj/.gitignore" ] && echo yes || echo no)"
git -C "$proj" add .harness/config.json
rc=0; env -i HOME="$base" PATH=/usr/bin:/bin GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid \
  git -C "$proj" commit -qm "config" >/dev/null 2>&1 || rc=$?
assert_eq "H-074: plain git works in the project with no harness on PATH" 0 "$rc"
git clone -q "$proj" "$base/clone"
assert_eq "H-074: a fresh clone carries no local selection" no "$([ -e "$base/clone/.harness/local.json" ] && echo yes || echo no)"
assert_eq "H-074: a fresh clone carries no run state" no "$([ -e "$base/clone/.harness/runs" ] && echo yes || echo no)"

# ---- H-129 D33a D37-DISTRIBUTION-1: the project setup command --------------------------------
assert_eq "H-127 D33a: /harness:ai-ready ships" yes "$([ -f "$c/ai-ready.md" ] && echo yes || echo no)"
assert_contains "D33a: its first description line names the configuration command" "$(sed -n '/^description:/p' "$c/ai-ready.md" 2>/dev/null)" "/harness:config"
assert_eq "D33a: /harness:ai-ready has no alias; init stays with the configuration command" 0 "$(grep -l 'commands/ai-ready.md' "$c"/*.md 2>/dev/null | wc -l | tr -d ' ')"
a=$(cat "$c/ai-ready.md" 2>/dev/null)
assert_contains "D37-DISTRIBUTION-1: the setup command sets up no flow system" "$a" "install or configure a flow system"
assert_contains "D33a: the setup command writes no harness config and no local selection" "$a" "no harness config and no local selection"
assert_contains "H-129: CLAUDE.md is reviewed and an AGENTS.md link added when missing" "$a" "AGENTS.md"
assert_contains "H-129: SECURITY.md is added when missing and it fits" "$a" "SECURITY.md"
assert_contains "H-129: hooks may be added where they fit" "$a" "hooks"
