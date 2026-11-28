# H-067 (#101, D37-FLOW-2): harness settings reach a chosen flow system's step only as hints, and
# "flow hints" lists them for the run ledger at start.
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

# ---- H-067: on a step the chosen system owns, a harness setting is only a hint ----
pcfg '{"schemaVersion":2,"requirements":{"format":"openspec"}}'
g=$(grill gsd)
assert_contains "H-067 (#101): on a GSD-owned step the requirements block comes as a hint" "$g" "## Hint from the harness"
assert_contains "H-067 (#101): the hint says the chosen system decides" "$g" "follow the system"
assert_eq "H-067 (#101): the requirements block is still there once, inside the hint" 1 "$(printf '%s\n' "$g" | grep -c 'BEGIN REQUIREMENTS BLOCK' || true)"
assert_eq "H-067 (#101): an own flow gets the block as an instruction, not a hint" 0 "$(grill basic | grep -c 'Hint from the harness' || true)"
assert_eq "H-067 (#101): flow hints lists the hint of the GSD grilling step" "grill	requirements.format=openspec" "$("$h" flow hints gsd)"
assert_eq "H-067 (#101): an own flow has no hints" "" "$("$h" flow hints basic)"
pcfg '{"schemaVersion":2,"requirements":{"format":"none"}}'
assert_eq "H-067 (#101): with nothing to pass there is no hint" "" "$("$h" flow hints gsd)"
assert_eq "H-067: and no hint heading in the step" 0 "$(grill gsd | grep -c 'Hint from the harness' || true)"
