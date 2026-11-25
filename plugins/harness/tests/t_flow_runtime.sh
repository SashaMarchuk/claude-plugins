# H-075, H-078, H-102, H-073 (tasks 19.1; D30, D31, D37-RUNTIME-1, D37-RUNTIME-2, D37-RUNTIME-3):
# each flow step may name a runtime profile; `flow plan` shows each step's runtime, mode and
# launch line from profile data; `flow preflight` checks logins and skills at start, lists
# every missing item with its install step, and installs nothing. Tests use the fake runtimes.
h="$HO_PLUGIN_ROOT/bin/harness"
base=$(cd -P "$PWD" && pwd)
proj="$base/proj"
user="$base/user"
fl="$proj/.harness/flows"
mkdir -p "$fl" "$user/runtimes" "$base/cc" "$base/cx"
printf '{"schemaVersion": 2, "runtime": {"main": "claude-code"}}\n' > "$proj/.harness/config.json"
printf '{"schemaVersion": 2}\n' > "$user/config.json"
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$user" CLAUDE_CONFIG_DIR="$base/cc" CODEX_HOME="$base/cx"
export HO_FAKE_CLAUDE_LOG="$base/claude.log" HO_FAKE_CODEX_LOG="$base/codex.log"
cd "$proj"

mkflow() {
  rm -rf "${fl:?}/$1"
  mkdir -p "$fl/$1/steps"
  printf '%s\n' "$2" > "$fl/$1/flow.json"
  local s
  for s in $(printf '%s' "$2" | jq -r '.steps[]?.id'); do printf 'Do %s for @TICKET_ID@.\n' "$s" > "$fl/$1/steps/$s.md"; done
}
step() { jq -nc --arg id "$1" --arg t "$2" '{id: $id, title: $t, when: "always", prompt: "steps/\($id).md"}'; }
rev=$(jq -nc --argjson a "$(step classify Classification)" --argjson b "$(step plan Planning)" \
  --argjson c "$(step execute Execution)" --argjson d "$(step code-review 'Code review')" \
  --argjson e "$(step ui-check 'UI check')" --argjson f "$(step ship Shipping)" \
  '{schemaVersion: 2, name: "rev", description: "d", source: "own", steps: [$a, $b, $c, $d, $e, $f]}
   | (.steps[] | select(.id == "code-review" or .id == "ui-check")) += {kind: "review"}')
redit() { printf '%s' "$rev" | jq -c "$1"; }
col() { "$h" flow plan "$1" 2>&1 | awk -F '\t' -v id="$2" -v c="$3" '$2 == id { print $c }'; }

# ---- H-075: code review on the second runtime, every other step on the main runtime ------------
mkflow rev "$(redit '(.steps[] | select(.id == "code-review")) += {runtime: "codex"}')"
rc=0; plan=$("$h" flow plan rev 2>&1) || rc=$?
assert_eq "H-075: flow plan renders (exit 0)" "0" "$rc"
assert_eq "H-075: code review runs on codex" "codex" "$(col rev code-review 5)"
assert_eq "H-075: every other step runs on the main runtime" "claude-code claude-code claude-code claude-code claude-code" \
  "$(printf '%s\n' "$plan" | awk -F '\t' '$2 != "code-review" { print $5 }' | tr '\n' ' ' | sed 's/ $//')"
assert_eq "H-075: the plan keeps the step order" "classify plan execute code-review ui-check ship" \
  "$(printf '%s\n' "$plan" | cut -f2 | tr '\n' ' ' | sed 's/ $//')"
assert_contains "H-075: the codex review step launches through codex exec" "$(col rev code-review 9)" "codex exec"
assert_contains "H-075 (D37-RUNTIME-2): a review step on codex runs read-only" "$(col rev code-review 9)" "read-only"
assert_contains "H-075: the other steps launch the main runtime" "$(col rev plan 9)" "claude"
# H-102 (D30): interactive by default; codex steps run without a terminal (D37-RUNTIME-2).
assert_eq "H-102: steps on the main runtime are interactive" "interactive" "$(col rev plan 6)"
assert_eq "H-102: a review step on codex runs non-interactively" "noninteractive" "$(col rev code-review 6)"
assert_eq "H-102: a review step on codex is not experimental" "-" "$(col rev code-review 8)"
assert_eq "H-102: a review step on the main runtime stays interactive" "interactive" "$(col rev ui-check 6)"
mkflow rev "$(redit '(.steps[] | select(.id == "execute" or .id == "ui-check")) += {runtime: "codex"}')"
assert_eq "H-075: UI review can run on codex" "codex noninteractive" "$(col rev ui-check 5) $(col rev ui-check 6)"
assert_eq "H-075 (D37-RUNTIME-2): execution on codex is marked experimental" "experimental" "$(col rev execute 8)"
assert_eq "H-075: execution on codex runs only where the config names it" "claude-code" "$(col rev plan 5)"

# ---- runtime profiles: data files from the plugin or the user folder, never the project ---------
mkflow rev "$(redit '.steps[1].runtime = "no-such-rt"')"
rc=0; err=$("$h" flow plan rev 2>&1) || rc=$?
assert_eq "D37-RUNTIME-1: an unknown runtime stops the plan (exit 78)" "78" "$rc"
assert_contains "D37-RUNTIME-1: the stop names the runtime" "$err" "no-such-rt"
mkdir -p "$proj/.harness/runtimes"
jq '.command = "evil"' "$HO_PLUGIN_ROOT/runtimes/claude-code.json" > "$proj/.harness/runtimes/proj-rt.json"
mkflow rev "$(redit '.steps[1].runtime = "proj-rt"')"
assert_exit "D37-FLOW-8: a runtime profile in the project is never read (exit 78)" 78 "$h" flow plan rev
jq '.command = "codex"' "$HO_PLUGIN_ROOT/runtimes/codex.json" > "$user/runtimes/my-rt.json"
mkflow rev "$(redit '.steps[1].runtime = "my-rt"')"
assert_eq "D37-RUNTIME-2: a user may add a runtime profile" "my-rt" "$(col rev plan 5)"
printf '{"schemaVersion": 2, "command": "x"}\n' > "$user/runtimes/thin.json"
mkflow rev "$(redit '.steps[1].runtime = "thin"')"
assert_exit "D37-RUNTIME-2: a runtime profile without the start-check fields is refused (exit 78)" 78 "$h" flow plan rev
printf '{"schemaVersion": 2}\n' > "$proj/.harness/config.json"
mkflow rev "$rev"
rc=0; err=$("$h" flow plan rev 2>&1) || rc=$?
assert_eq "D37-RUNTIME-2: a step with no runtime and no runtime.main stops (exit 78)" "78" "$rc"
assert_contains "D37-RUNTIME-2: the stop names runtime.main" "$err" "runtime.main"
printf '{"schemaVersion": 2, "runtime": {"main": "claude-code"}}\n' > "$proj/.harness/config.json"
for f in claude-code codex; do
  assert_eq "D37-RUNTIME-2: shipped profile $f has every D31 field" "true" \
    "$(jq '[has("command", "modes", "skill_call", "config_dir", "session_log", "limits", "capabilities", "check", "skill_paths", "install")] | all' \
      "$HO_PLUGIN_ROOT/runtimes/$f.json" 2>&1)"
done

# ---- start check (H-073, H-078, D37-RUNTIME-3) --------------------------------------------------
sys=$(jq -nc --argjson a "$(step classify Classification)" --argjson b "$(step plan Planning)" \
  --argjson c "$(step code-review 'Code review')" --argjson d "$(step ship Shipping)" \
  '{schemaVersion: 2, name: "sys", description: "d", source: "system",
    system: {name: "Acme Flow", link: "https://example.invalid/acme", install: "npx acme-flow-installer",
             skills: ["acme-plan", "acme-review"], steps: ["plan", "code-review"]},
    steps: [$a, $b, ($c + {kind: "review", runtime: "codex"}), $d]}')
mkflow sys "$sys"
skill_cc() { mkdir -p "$base/cc/skills/$1" && printf 'x\n' > "$base/cc/skills/$1/SKILL.md"; }
skill_cx() { mkdir -p "$base/cx/skills/$1" && printf 'x\n' > "$base/cx/skills/$1/SKILL.md"; }
for s in acme-plan acme-review; do skill_cc "$s"; skill_cx "$s"; done
: > "$base/claude.log"; : > "$base/codex.log"
rc=0; out=$("$h" flow preflight sys 2>&1) || rc=$?
assert_eq "H-073: everything present lets work start (exit 0)" "0" "$rc"
assert_contains "H-073: the start check says OK" "$out" "start check OK"
assert_contains "H-078: the main runtime's login was checked" "$(cat "$base/claude.log")" "auth	status"
assert_contains "H-078: the second runtime's login was checked" "$(cat "$base/codex.log")" "login	status"

rm -rf "$base/cx/skills/acme-review" "$base/cc/skills/acme-plan"
: > "$base/claude.log"; : > "$base/codex.log"
rc=0; out=$(HO_FAKE_CODEX_LOGGED_OUT=1 "$h" flow preflight sys 2>&1) || rc=$?
assert_eq "H-073: a missing skill or login stops before work starts (exit 69)" "69" "$rc"
assert_contains "H-078: a runtime that is not logged in is named" "$out" "runtime codex: not logged in"
assert_contains "H-078: its install and login step is printed" "$out" "codex login"
assert_contains "H-073: a skill missing for the second runtime is named" "$out" "skill acme-review for runtime codex"
assert_contains "H-073: a skill missing for the main runtime is named" "$out" "skill acme-plan for runtime claude-code"
assert_contains "H-073: the missing skill's install step is printed" "$out" "npx acme-flow-installer"
assert_contains "D37-RUNTIME-3: install text from a project flow is marked as not checked" "$out" "not checked"
assert_eq "D37-RUNTIME-3: every missing item comes in one list" "3" "$(printf '%s\n' "$out" | grep -c '^- ' || true)"
assert_eq "D37-RUNTIME-3: the start check installs nothing" "" \
  "$(cat "$base/claude.log" "$base/codex.log" | grep -vE '^(auth	status|login	status)$' || true)"
for s in acme-plan acme-review; do skill_cc "$s"; skill_cx "$s"; done

# A login check that answers "logged out" with exit 0 still fails (fail closed on the output).
rc=0; out=$(HO_FAKE_CLAUDE_LOGGED_OUT=lie "$h" flow preflight sys 2>&1) || rc=$?
assert_eq "D37-RUNTIME-3: a login check whose output says logged out stops (exit 69)" "69" "$rc"
assert_contains "D37-RUNTIME-3: that stop names the main runtime" "$out" "runtime claude-code: not logged in"
# A login check that does not answer in time counts as missing; its process is stopped.
jq '.check.timeout_seconds = 1' "$HO_PLUGIN_ROOT/runtimes/codex.json" > "$user/runtimes/slow.json"
mkflow sys "$(printf '%s' "$sys" | jq -c '.steps[2].runtime = "slow"')"
for s in acme-plan acme-review; do skill_cx "$s"; done
t0=$(date +%s)
rc=0; out=$(HO_FAKE_CODEX_SLEEP=30 "$h" flow preflight sys 2>&1) || rc=$?
t1=$(date +%s)
assert_eq "I1: a login check that does not answer stops the start (exit 69)" "69" "$rc"
assert_contains "I1: the stop says the check did not answer" "$out" "did not answer"
if [ $((t1 - t0)) -lt 15 ]; then ok "I1: the time limit holds (under 15 s)"; else bad "I1: the time limit holds (under 15 s)" "took $((t1 - t0)) s"; fi
# A runtime command that is not installed is named with its install step.
jq '.command = "ho-no-such-runtime"' "$HO_PLUGIN_ROOT/runtimes/codex.json" > "$user/runtimes/ghost.json"
mkflow sys "$(printf '%s' "$sys" | jq -c '.steps[2].runtime = "ghost"')"
rc=0; out=$("$h" flow preflight sys 2>&1) || rc=$?
assert_eq "D37-RUNTIME-3: a runtime that is not installed stops (exit 69)" "69" "$rc"
assert_contains "D37-RUNTIME-3: the stop names the missing command" "$out" "runtime ghost: command ho-no-such-runtime not found"
# A runtime binary inside the project is never run.
mkdir -p "$proj/bin"
cp "$HO_TESTS_DIR/fake-bin/codex" "$proj/bin/ho-proj-runtime"
jq '.command = "ho-proj-runtime"' "$HO_PLUGIN_ROOT/runtimes/codex.json" > "$user/runtimes/inproj.json"
mkflow sys "$(printf '%s' "$sys" | jq -c '.steps[2].runtime = "inproj"')"
: > "$base/codex.log"
rc=0; out=$(PATH="$proj/bin:$PATH" "$h" flow preflight sys 2>&1) || rc=$?
assert_eq "D37-FLOW-8: a runtime binary inside the project stops the start (exit 69)" "69" "$rc"
assert_eq "D37-FLOW-8: that binary is never run" "" "$(cat "$base/codex.log")"
# Accounts: the login and skill checks read the config folder the worker's account sets.
mkflow sys "$sys"
mkdir -p "$base/cc2/skills"
jq -n --arg d "$base/cc2" '{schemaVersion: 2, accounts: {roles: {worker: "work"},
  list: {work: {env_command: ("printf \"CLAUDE_CONFIG_DIR=" + $d + "\\n\"")}}}}' > "$user/config.json"
rc=0; out=$("$h" flow preflight sys 2>&1) || rc=$?
assert_eq "D31: skills are checked in the worker account's config folder (exit 69)" "69" "$rc"
assert_contains "D31: the account's missing skill is named" "$out" "skill acme-plan for runtime claude-code"
printf '{"schemaVersion": 2}\n' > "$user/config.json"
# Execution on codex is reported as experimental at start.
mkflow sys "$(printf '%s' "$sys" | jq -c '.steps[1].runtime = "codex"')"
rc=0; out=$("$h" flow preflight sys 2>&1) || rc=$?
assert_eq "D37-RUNTIME-2: an experimental step does not stop the start (exit 0)" "0" "$rc"
assert_contains "D37-RUNTIME-2: the start output marks it experimental and untested" "$out" "experimental, untested: step plan"

# ---- H-073: the shipped gsd flow links its system and vendors nothing ---------------------------
g="$HO_PLUGIN_ROOT/flows/gsd"
assert_eq "H-073: the gsd flow links its system and gives the install step" "true" \
  "$(jq '.system | (.link | type == "string" and length > 0) and (.install | type == "string" and length > 0)' "$g/flow.json")"
assert_eq "H-073: the gsd flow folder holds no copy of the system" "flow.json $(cd "$g" && ls steps | sed 's#^#steps/#' | tr '\n' ' ' | sed 's/ $//')" \
  "$(cd "$g" && find . -type f | sed 's#^\./##' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
