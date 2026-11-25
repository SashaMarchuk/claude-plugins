# H-065, H-066, H-067, H-068 (tasks 7.1, editing part): a flow config is a flow folder with one
# step list (S8-15). Own flows live in <project>/.harness/flows/<name>/. Steps can be reordered,
# added, switched off and given a runner. A chosen system owns its steps (D17, D37-FLOW-2).
# The flow config is a file of its own, apart from the autonomy profile (D37-FLOW-3).
h="$HO_PLUGIN_ROOT/bin/harness"
base=$(cd -P "$PWD" && pwd)
proj="$base/proj"
user="$base/user"
fl="$proj/.harness/flows"
mkdir -p "$fl" "$proj/.harness/autonomy" "$user"
printf '{"schemaVersion": 2, "runtime": {"main": "claude-code"}}\n' > "$proj/.harness/config.json"
printf '{"schemaVersion": 2}\n' > "$user/config.json"
# A stand-in autonomy profile: gates and permissions only (D12). No flow verb may write to it.
printf '{"schemaVersion": 2, "name": "safe", "push": false, "pr": "none", "merge": "never"}\n' \
  > "$proj/.harness/autonomy/safe.json"
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$user"
cd "$proj"

# mkflow <name> <flow.json>: a project flow; every listed step gets a prompt file.
mkflow() {
  rm -rf "${fl:?}/$1"
  mkdir -p "$fl/$1/steps"
  printf '%s\n' "$2" > "$fl/$1/flow.json"
  local s
  for s in $(printf '%s' "$2" | jq -r '.steps[]?.id'); do
    printf 'Do step %s of ticket @TICKET_ID@ with care.\n' "$s" > "$fl/$1/steps/$s.md"
  done
}
# step <id> <title>: one step entry.
step() { jq -nc --arg id "$1" --arg t "$2" '{id: $id, title: $t, when: "always", prompt: "steps/\($id).md"}'; }
own=$(jq -nc --argjson a "$(step classify Classification)" --argjson b "$(step plan Planning)" \
  --argjson c "$(step execute Execution)" --argjson d "$(step code-review 'Code review')" \
  --argjson e "$(step ship Shipping)" \
  '{schemaVersion: 2, name: "mine", description: "own flow", source: "own", steps: [$a, $b, $c, $d, $e]}')
edit() { printf '%s' "$own" | jq -c "$1"; }
ids() { "$h" flow steps "$1" 2>&1 | cut -f2 | tr '\n' ' ' | sed 's/ $//'; }
nums() { "$h" flow steps "$1" 2>&1 | cut -f1 | tr '\n' ' ' | sed 's/ $//'; }
printf 't\n' | "$h" tickets fence 7 > "$base/ticket.txt"
vrender() { # the validator prompt of flow $1: it carries the rendered step list
  "$h" flow render "$1" validator --set RUN_ID r --set TICKET_ID 7 --set BRANCH b --set BASE m \
    --set WORKDIR /w --set VERDICT_FILE /v --file TICKET_TEXT "$base/ticket.txt" 2>&1
}
wrender() { # wrender <flow> <step>: the worker prompt of one step
  "$h" flow render "$1" worker --step "$2" --set RUN_ID r --set TICKET_ID 7 --set BRANCH b \
    --set WORKDIR /w --set STEP_RESULT_FILE /s --file TICKET_TEXT "$base/ticket.txt" 2>&1
}

rc=0; out=$("$h" flow list 2>&1) || rc=$?
assert_eq "H-068: flow list in a project with no own flows exits 0" "0" "$rc"
assert_eq "H-068: flow list in a project with no own flows shows the shipped ones" "basic gsd" "$(printf '%s\n' "$out" | tr '\n' ' ' | sed 's/ $//')"
mkflow mine "$own"
assert_eq "H-068: an own project flow is found by its name" "flow mine OK" "$("$h" flow check mine 2>&1)"
assert_eq "H-068: flow list shows shipped and project flows" "basic gsd mine" "$("$h" flow list | tr '\n' ' ' | sed 's/ $//')"
assert_eq "H-065: the step list follows the flow config" "classify plan execute code-review ship" "$(ids mine)"

# ---- H-066: reorder ----------------------------------------------------------------------
mkflow mine "$(edit '.steps |= [.[0], .[1], .[3], .[2], .[4]]')"
assert_eq "H-066: a reordered step list is followed" "classify plan code-review execute ship" "$(ids mine)"
assert_eq "H-066: a reordered list is numbered in its new order" "1 2 3 4 5" "$(nums mine)"
out=$(vrender mine || true)
assert_contains "H-066: the rendered step list shows the new order (3)" "$out" "3. Code review (code-review)"
assert_contains "H-066: the rendered step list shows the new order (4)" "$out" "4. Execution (execute)"

# ---- H-066: add steps (a version bump, a connection check, a test audit around review) ----
added=$(edit "$(printf '.steps |= [.[0], %s, .[1], .[2], %s, %s, .[3], %s, .[4]]' \
  "$(step mcp-check 'Connection check')" "$(step version-bump 'Version bump')" \
  "$(step test-audit 'Test audit')" "$(step test-audit-after 'Test audit after review')")")
mkflow mine "$added"
assert_eq "H-066: added steps run where the config places them" \
  "classify mcp-check plan execute version-bump test-audit code-review test-audit-after ship" "$(ids mine)"
out=$(vrender mine || true)
assert_contains "H-066: the test audit comes right before code review" "$out" "6. Test audit (test-audit)
7. Code review (code-review)
8. Test audit after review (test-audit-after)"
assert_contains "H-066: an added step renders its own prompt" "$(wrender mine version-bump)" "Do step version-bump of ticket 7"

# ---- H-066: switch a step off --------------------------------------------------------------
mkflow mine "$(edit '(.steps[] | select(.id == "code-review")) += {enabled: false}')"
assert_eq "H-066: a switched-off step leaves the step list" "classify plan execute ship" "$(ids mine)"
assert_eq "H-066: the list is numbered without the switched-off step" "1 2 3 4" "$(nums mine)"
out=$(vrender mine || true)
assert_eq "H-066: the rendered step list has no switched-off step" "" "$(printf '%s' "$out" | grep -F 'code-review' || true)"
assert_contains "H-066: the step after a switched-off one moves up" "$out" "4. Shipping (ship)"
rc=0; err=$(wrender mine code-review) || rc=$?
assert_eq "H-066: a switched-off step cannot be rendered (exit 64)" "64" "$rc"
assert_contains "H-066: the refusal says the step is switched off" "$err" "switched off"
mkflow mine "$(edit '.steps[1].enabled = "no"')"
assert_exit "H-066: enabled must be true or false (exit 78)" 78 "$h" flow check mine
mkflow mine "$(edit '.steps[] |= . + {enabled: false}')"
assert_exit "H-066: a flow with every step switched off is refused (exit 78)" 78 "$h" flow check mine
# Code review before the PR: shipping (which opens the PR) after review, or the other way round;
# the order is the config's, not the engine's.
mkflow mine "$(edit '.steps |= [.[0], .[1], .[2], .[4], .[3]]')"
assert_eq "H-066: a config may place shipping before code review" "ship code-review" "$(ids mine | awk '{print $4, $5}')"
mkflow mine "$own"
assert_eq "H-066: code review before the PR is an allowed order" "code-review ship" "$(ids mine | awk '{print $4, $5}')"

# ---- H-066: a runner per step --------------------------------------------------------------
mkflow mine "$(edit '.steps[3].runtime = "codex"')"
assert_eq "H-066: a step may name its runner" "flow mine OK" "$("$h" flow check mine 2>&1)"
for bad in '"../x"' '"Codex"' '"-x"' '""' '3'; do
  mkflow mine "$(edit ".steps[3].runtime = $bad")"
  assert_exit "H-066: runner name $bad is refused (exit 78)" 78 "$h" flow check mine
done

# ---- D37-FLOW-3: the flow config holds no autonomy setting ---------------------------------
for key in gates push pr pr_open merge post_merge deploy_production remarks allow_zero_tests permissions autonomy; do
  mkflow mine "$(edit ".$key = true")"
  rc=0; err=$("$h" flow check mine 2>&1) || rc=$?
  assert_eq "H-065: a flow config with autonomy key $key is refused (exit 78)" "78" "$rc"
  assert_contains "H-065: the refusal of $key points to the autonomy profile" "$err" "autonomy profile"
done

# ---- H-067: a chosen system owns its steps ---------------------------------------------------
sys=$(jq -nc --argjson a "$(step classify Classification)" --argjson b "$(step plan Planning)" \
  --argjson c "$(step execute Execution)" --argjson d "$(step ship Shipping)" \
  '{schemaVersion: 2, name: "sys", description: "d", source: "system",
    system: {name: "Acme Flow", link: "https://example.invalid/acme", install: "see the Acme docs",
             skills: ["acme-plan", "acme-run"], steps: ["plan", "execute"]},
    steps: [$a, $b, $c, $d]}')
sedit() { printf '%s' "$sys" | jq -c "$1"; }
mkflow sys "$sys"
assert_eq "H-068: a system the harness has not seen before is accepted" "flow sys OK" "$("$h" flow check sys 2>&1)"
mkflow sys "$(sedit "$(printf '.steps |= [%s] + .[0:3] + [%s] + .[3:]' "$(step pre 'Before')" "$(step bump 'Version bump')")")"
assert_eq "H-067: harness extra steps go before or after the system's steps" "pre classify plan execute bump ship" "$(ids sys)"
sys_bad() { # sys_bad <label> <jq edit> <needle>...: exit 78, the message holds every needle
  local label=$1 rc=0 err n
  mkflow sys "$(sedit "$2")"
  shift 2
  err=$("$h" flow check sys 2>&1) || rc=$?
  assert_eq "H-067: $label stops at start (exit 78)" "78" "$rc"
  for n in "$@"; do assert_contains "H-067: the stop for $label names [$n]" "$err" "$n"; done
}
sys_bad "a step inside the system's steps" "$(printf '.steps |= .[0:2] + [%s] + .[2:]' "$(step audit 'Test audit')")" \
  "audit" "harness flow copy sys"
sys_bad "the system's steps in another order" '.steps |= [.[0], .[2], .[1], .[3]]' "harness flow copy sys"
sys_bad "a system step switched off" '.steps[1].enabled = false' "plan" "harness flow copy sys"
sys_bad "a system step list that names a missing step" '.system.steps += ["nope"]' "nope"
sys_bad "a system step list with a repeated step" '.system.steps = ["plan", "plan"]' "plan"
sys_bad "a chosen system without its step list" 'del(.system.steps)' "system.steps"
mkflow sys "$(sedit '.source = "own"')"
rc=0; err=$("$h" flow check sys 2>&1) || rc=$?
assert_eq "H-067: a config with a system and an own step list stops (exit 78)" "78" "$rc"
assert_contains "H-067: that stop says the lists are never merged" "$err" "never merges"
mkflow sys "$(sedit '.steps[1].runtime = "codex"')"
assert_eq "H-067: a system step may still name its runner" "flow sys OK" "$("$h" flow check sys 2>&1)"
assert_eq "H-067: the shipped gsd flow keeps its system steps in one block" "flow gsd OK" "$("$h" flow check gsd 2>&1)"
assert_eq "H-067: gsd marks the steps its system owns" "grill plan execute code-review verify ui-check" \
  "$(jq -r '.system.steps | join(" ")' "$HO_PLUGIN_ROOT/flows/gsd/flow.json")"
for bad in '.system.install = "run \u202ehs.lave"' '.system.link = "x\u2028y"' '.steps[0].title = "A\u2029B"' \
  '.system.name = "A\u0085B"'; do
  mkflow sys "$(sedit "$bad")"
  assert_exit "H-073: printed flow text [$bad] with a line separator or bidi control is refused (exit 78)" 78 "$h" flow check sys
done
for bad in '.system.name = "A\u001b[31m"' '.system.install = "line one\nline two"' '.system.link = "x\u0007"' \
  '.system.skills = ["../etc"]' '.system.skills = ["a b"]'; do
  mkflow sys "$(sedit "$bad")"
  assert_exit "H-073: flow data [$bad] is refused (exit 78)" 78 "$h" flow check sys
done

# ---- flow copy: the route out of a chosen system, and H-065 (the profile stays unchanged) ----
snap() { (cd "$base" && find proj/.harness user -type f ! -path 'proj/.harness/flows/*' | LC_ALL=C sort | while IFS= read -r f; do
  printf '%s %s\n' "$(cksum < "$f" | tr -s ' ' '-')" "$f"; done); }
before=$(snap)
rc=0; out=$("$h" flow copy gsd my-gsd 2>&1) || rc=$?
assert_eq "D37-FLOW-2: flow copy writes an own flow (exit 0)" "0" "$rc"
c="$fl/my-gsd/flow.json"
assert_eq "D37-FLOW-2: the copy is an own flow named for its folder" "own my-gsd gsd false" \
  "$(jq -r '"\(.source) \(.name) \(.copied_from) \(has("system"))"' "$c" 2>&1)"
assert_eq "D37-FLOW-2: the copy keeps every step in order" "$(ids gsd)" "$(ids my-gsd)"
assert_eq "H-073: the copy keeps the system's skills on the system's steps" "gsd-phase" \
  "$(jq -r '.steps[] | select(.id == "plan") | .skills[0]' "$c" 2>&1)"
# Edit the copy: a test audit inside the former system block, and the UI check switched off.
jq "$(printf '.steps |= .[0:4] + [%s] + .[4:] | (.steps[] | select(.id == "ui-check")) += {enabled: false}' \
  "$(step test-audit 'Test audit')")" "$c" > "$c.new" && mv "$c.new" "$c"
printf 'Audit the tests of ticket @TICKET_ID@.\n' > "$fl/my-gsd/steps/test-audit.md"
assert_eq "H-066: the copied flow takes a step between former system steps" \
  "classify grill plan execute test-audit code-review verify ship" "$(ids my-gsd)"
"$h" flow check my-gsd >/dev/null 2>&1 || true
vrender my-gsd >/dev/null 2>&1 || true
"$h" flow plan my-gsd >/dev/null 2>&1 || true
assert_eq "H-065: changing the flow config leaves the autonomy profile and every other config file unchanged" \
  "$before" "$(snap)"
assert_exit "D37-FLOW-2: flow copy refuses to overwrite a project flow (exit 65)" 65 "$h" flow copy gsd my-gsd
assert_exit "D37-FLOW-2: flow copy refuses a shipped flow name (exit 65)" 65 "$h" flow copy gsd basic
assert_exit "D37-FLOW-2: flow copy refuses a bad name (exit 64)" 64 "$h" flow copy gsd ../x
assert_exit "D37-FLOW-2: flow copy needs a project (exit 78)" 78 env -u HO_PROJECT_DIR sh -c 'cd / && "$0" flow copy gsd x' "$h"

# ---- project flows: no shadowing, no way out of the project --------------------------------
mkflow basic "$(edit '.name = "basic"')"
rc=0; err=$("$h" flow check basic 2>&1) || rc=$?
assert_eq "H-068: a project flow with a shipped flow's name is refused (exit 78)" "78" "$rc"
assert_contains "H-068: that refusal names the flow" "$err" "basic"
rm -rf "${fl:?}/basic"
mkdir -p "$base/outside/ext/steps"
printf '%s\n' "$(edit '.name = "ext"')" > "$base/outside/ext/flow.json"
for s in classify plan execute code-review ship; do printf 'x @TICKET_ID@\n' > "$base/outside/ext/steps/$s.md"; done
ln -s "$base/outside/ext" "$fl/ext"
assert_exit "H-068: a project flow folder that links out of the project is refused (exit 78)" 78 "$h" flow check ext
rm -f "$fl/ext"
# The flows folder itself linked out of the project: no flow is read from there, none written.
mv "$fl" "$base/outside/a-flows"
mkdir -p "$base/outside/a-flows/ext2/steps"
cp "$base/outside/ext/flow.json" "$base/outside/a-flows/ext2/flow.json"; cp "$base/outside/ext/steps/"* "$base/outside/a-flows/ext2/steps/"
jq '.name = "ext2"' "$base/outside/a-flows/ext2/flow.json" > "$base/x.json" && mv "$base/x.json" "$base/outside/a-flows/ext2/flow.json"
ln -s "$base/outside/a-flows" "$fl"
assert_exit "H-068: a flow in a linked-out flows folder is refused (exit 78)" 78 "$h" flow check ext2
rc=0; "$h" flow copy basic newone >/dev/null 2>&1 || rc=$?
assert_eq "D37-FLOW-2: flow copy refuses a linked-out flows folder (exit 78)" "78" "$rc"
assert_eq "D37-FLOW-2: flow copy wrote nothing outside the project" "no" "$([ -e "$base/outside/a-flows/newone" ] && echo yes || echo no)"
