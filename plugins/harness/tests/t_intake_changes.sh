# Ticket changes through comments (T20; H-019 to H-023; D9, D37-INTAKE-2, D37-INTAKE-3,
# D37-INTAKE-6, D37-INTAKE-7, D37-FLOW-8 (c)). The intake tick reads new comments on the run's
# in-progress tickets; a writer's change waits as a note for the next step boundary.
. "$HO_TESTS_DIR/intake-setup.sh"
setcfg() { jq "$1" "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"; }
say() { printf '%s\n' "$3" > "$base/say.md"; as "$1" issue comment "$2" --repo fake/repo --body-file "$base/say.md" >/dev/null; }
take() { local t; t=$(ticket "$1"); label alice "$t" ready; tick >/dev/null; printf '%s\n' "$t"; }
nissues() { find "$HO_FAKE_GH_DIR/issues" -name '*.json' | wc -l | tr -d ' '; }
begin() { "$h" state "$run" begin --ticket "$1" --step "$2"; }

# H-019 H-020 H-023 D37-INTAKE-3: a writer's change is detected while the work runs and
# reaches the worker as a note at the next step boundary.
t1=$(take "Change by writer")
assert_eq "H-019 the taken ticket is in progress" '["harness:in-progress"]' "$(labels "$t1")"
say alice "$t1" "Please also add a header row."
out=$(tick)
assert_contains "H-019 H-020 the writer's change is applied" "$out" "change-applied $t1"
assert_contains "H-019 the ledger knows who wrote the change" "$(jq -c --arg t "$t1" 'select(.kind == "change" and .ticket == $t)' "$run/ledger.jsonl")" '"by":"alice"'
b=$(begin "$t1" execute)
assert_contains "D37-INTAKE-3 the step gate opens as before" "$b" "may begin"
note=$(printf '%s\n' "$b" | sed -n 's/^change //p')
assert_eq "H-023 the step boundary hands the note to the worker" "yes" "$([ -n "$note" ] && [ -f "$note" ] && echo yes || echo no)"
assert_contains "H-023 the note holds the change text" "$(cat "$note")" "add a header row"
assert_contains "H-018 the note text is inside the untrusted fence" "$(cat "$note")" "BEGIN TICKET DATA [id $t1]"
assert_eq "D37-INTAKE-3 a note is handed over once" "" "$(begin "$t1" verify | grep '^change ' || true)"
out=$(tick)
assert_eq "H-019 a seen comment is not handled again" "" "$(printf '%s' "$out" | grep "change-.* $t1" || true)"

# A plain comment from the harness's own account is a person's (one-person setup): a change.
say harness-bot "$t1" "Also sort the rows."
out=$(tick)
assert_contains "H-019 a plain comment from the signed-in account is a change" "$out" "change-applied $t1"
assert_eq "D13 the harness's own reports are never changes" "1" "$(printf '%s\n' "$out" | grep -c "change-.* $t1" || true)"

# H-021 D37-INTAKE-2: a non-writer's change becomes a new linked ticket in needs-review; the
# running work does not change.
t2=$(take "Change by reader")
n0=$(nissues)
say rita "$t2" "Make it export XML instead."
out=$(tick)
new=$(printf '%s\n' "$out" | sed -n "s/^change-ticket $t2 //p")
assert_eq "H-021 one new ticket is created" "$((n0 + 1))" "$(nissues)"
assert_eq "D37-INTAKE-2 the new ticket starts in needs-review" '["harness:needs-review"]' "$(labels "$new")"
assert_contains "H-021 the new ticket links to the source comment" "$(jq -r .body "$HO_FAKE_GH_DIR/issues/$new.json")" "#$t2, comment"
assert_eq "H-021 the running ticket keeps its state" '["harness:in-progress"]' "$(labels "$t2")"
assert_eq "H-021 no note reaches the running work" "" "$(begin "$t2" execute | grep '^change ' || true)"

# H-022: the author chooses the reaction with a first line.
t3=$(take "Change as new ticket")
say alice "$t3" "harness:new-ticket
Add a PDF export later."
out=$(tick)
new3=$(printf '%s\n' "$out" | sed -n "s/^change-ticket $t3 //p")
assert_eq "H-022 harness:new-ticket gives a new linked ticket" "yes" "$([ -n "$new3" ] && echo yes || echo no)"
assert_contains "H-022 the writer's new ticket goes through normal intake (taken in the same tick)" "$out" "start $new3"
assert_eq "H-022 the running work gets no note" "" "$(begin "$t3" execute | grep '^change ' || true)"

# H-022 D37-INTAKE-6: the launch setting ignore; a per-comment harness:apply overrides it.
setcfg '.tickets.changes.mode = "ignore"'
t4=$(take "Ignored change")
say alice "$t4" "Rename the file."
out=$(tick)
assert_contains "H-022 mode ignore: the change is ignored" "$out" "change-ignored $t4"
say alice "$t4" "harness:apply
Rename the file after all."
out=$(tick)
assert_contains "H-022 a first line harness:apply overrides the launch mode" "$out" "change-applied $t4"
setcfg '.tickets.changes.mode = "sometimes"'
assert_exit "H-022 an unknown change mode is refused (exit 78)" 78 tick
setcfg 'del(.tickets.changes)'

# D37-INTAKE-6: after the merge a writer's change becomes a new linked ticket, also with apply.
t5=$(take "Merged ticket")
mkdir -p "$run/lanes"
printf '{"lane": "l5", "ticket": "%s"}\n' "$t5" > "$run/lanes/l5.json"
printf '{"kind": "merge-confirmed", "lane": "l5", "sha": "abc", "tip": "def"}\n' >> "$run/ledger.jsonl"
say alice "$t5" "harness:apply
One more tweak."
out=$(tick)
assert_contains "D37-INTAKE-6 after the merge a change becomes a new ticket, even with harness:apply" "$out" "change-ticket $t5 "

# D37-FLOW-8 (c): an accepted change that names a target repository needs its author's access there.
setcfg '.tickets.target_repos = ["fake/repo", "fake/api"]'
t6=$(take "Target change")
say alice "$t6" "Also change fake/api."
out=$(HO_FAKE_GH_FAIL_API=repos/fake/api/ tick)
assert_contains "D37-FLOW-8 a change naming a target without confirmed access is not applied" "$out" "needs-review $t6"
assert_eq "D37-FLOW-8 the ticket moves to needs-review" '["harness:needs-review"]' "$(labels "$t6")"
assert_contains "D37-FLOW-8 the comment names the repository" "$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t6.json")" "fake/api"
setcfg 'del(.tickets.target_repos)'

# D37-INTAKE-7: a description edit is no change; the first one gets one comment asking for a comment.
t7=$(take "Edited description")
n0=$(ncomments "$t7")
printf 'A new description.\n' > "$base/nd.md"
as alice issue edit "$t7" --repo fake/repo --body-file "$base/nd.md"
out=$(tick)
assert_eq "D37-INTAKE-7 the first description edit gets one comment" "$((n0 + 1))" "$(ncomments "$t7")"
assert_contains "D37-INTAKE-7 the comment asks for the change as a comment" "$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t7.json")" "as a comment"
printf 'Another description.\n' > "$base/nd.md"
as alice issue edit "$t7" --repo fake/repo --body-file "$base/nd.md"
tick >/dev/null
assert_eq "D37-INTAKE-7 a later edit gets no further comment" "$((n0 + 1))" "$(ncomments "$t7")"
assert_eq "D37-INTAKE-7 an edit is no note for the worker" "" "$(begin "$t7" execute | grep '^change ' || true)"
assert_contains "D37-INTAKE-7 the session text keeps the description as picked up" "$("$h" intake "$run" text "$t7")" "Export reports as CSV."
assert_eq "D37-INTAKE-7 the edited description never reaches the session text" "" "$("$h" intake "$run" text "$t7" | grep -F 'Another description' || true)"
