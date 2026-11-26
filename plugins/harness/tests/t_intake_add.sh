# Terminal intake (H-005, H-006, H-015; D6): /harness:add grills first, then writes the plugin's
# ticket structure and creates the ticket in the configured tracker with its state, and the
# ticket follows the same pickup path as one labelled there by hand.
. "$HO_TESTS_DIR/intake-setup.sh"
cmd="$HO_PLUGIN_ROOT/commands/add.md"

# H-015 D6: the structure the plugin writes.
tpl=$("$h" tickets template)
for head in "## Outcome" "## Scope" "## Acceptance criteria" "## Checks"; do
  assert_contains "H-015 D6 the ticket structure has the heading $head" "$tpl" "$head"
done

# H-006 H-015: a ticket created from the terminal carries the status and the structure at once.
{ printf '%s\n' "$tpl" | sed 's/^What is true.*/Reports export as CSV./'; } > "$base/add.md"
out=$("$h" tickets add "CSV export" "$base/add.md" ready)
t=$(printf '%s' "$out" | sed -n 's/^OK created ticket \([0-9]*\).*/\1/p')
assert_eq "H-006 the terminal-created ticket carries the ready status in the tracker" '["harness:ready"]' "$(labels "$t")"
assert_contains "H-015 the created body already has the plugin's structure" "$(jq -r .body "$HO_FAKE_GH_DIR/issues/$t.json")" "## Checks"

# H-005 one intake flow: the terminal-created ticket is picked up by the same path.
out=$(tick)
assert_contains "H-005 the ticket added from the terminal is picked up by the normal pickup path" "$out" "start $t"
assert_eq "H-005 the same path ran the readiness check" "1" "$(jq -s --arg t "$t" '[.[] | select(.kind == "readiness" and .ticket == $t)] | length' "$run/ledger.jsonl")"

# H-005 local tracker: the same verbs, the same pickup path.
(
  export HO_TICKETS_SOURCE=local HO_TICKETS_DIR="$proj/.harness/tickets"
  unset HO_TICKETS_REPO
  lt=$("$h" tickets add "Local CSV" "$base/add.md" ready | sed -n 's/^OK created ticket \([0-9]*\).*/\1/p')
  out=$(tick)
  assert_contains "H-005 local: the terminal-created ticket is picked up by the same path" "$out" "start $lt"
)

# H-006: the /harness:add command keeps the grilling gate before it creates anything, and it
# creates through the engine verbs that exist.
assert_eq "H-006 the /harness:add command exists" "yes" "$([ -f "$cmd" ] && echo yes || echo no)"
body=$(cat "$cmd" 2>/dev/null || true)
grill=$(printf '%s\n' "$body" | grep -n 'AskUserQuestion' | head -1 | cut -d: -f1 || true)
create=$(printf '%s\n' "$body" | grep -n 'tickets add' | head -1 | cut -d: -f1 || true)
if [ -n "$grill" ] && [ -n "$create" ] && [ "$grill" -lt "$create" ]; then
  ok "H-006 the command grills (asks clarifying questions) before it creates the ticket"
else
  bad "H-006 the command grills (asks clarifying questions) before it creates the ticket" "grill=$grill create=$create"
fi
help=$("$h" tickets help)
for verb in template add; do
  assert_contains "H-015 the command uses the engine verb $verb, which exists" "$body" "bin/harness\" tickets $verb"
  assert_contains "H-015 the engine lists the verb $verb" "$help" "  $verb"
done
assert_contains "H-006 an unanswered blocker creates the ticket as blocked, not guessed" "$body" "blocked"
