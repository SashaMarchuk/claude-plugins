# H-024 (D13): every report is a new comment; no earlier comment is edited or deleted.
# Approved hand patch: "issue comment" without --edit-last. The fake gh keeps real comment
# state and implements --edit-last, so a regression would rewrite a stored comment.
h="$HO_PLUGIN_ROOT/bin/harness"
export HO_FAKE_GH_DIR="$PWD/gh" HO_TICKETS_SOURCE=github HO_TICKETS_REPO=fake/repo
printf '## Outcome\nx\n\n## Scope\ny\n\n## Acceptance criteria\nz\n' > body.md
comments() { jq -c '[.comments[].body]' "$HO_FAKE_GH_DIR/issues/$1.json"; }

"$h" tickets add "Comment test" body.md >/dev/null

# Scenario: two roles report on the same ticket (both sign in as one account).
printf 'worker: hand-off\n' > worker.md
printf 'validator: verdict passed\n' > validator.md
"$h" tickets comment 1 worker.md >/dev/null
before=$(comments 1)
"$h" tickets comment 1 validator.md >/dev/null
after=$(comments 1)
assert_eq "H-024 two roles: the ticket shows two separate comments" "2" "$(jq -n "$after | length")"
assert_eq "H-024 two roles: the worker hand-off is unchanged" "$(jq -n -c "$before[0]")" "$(jq -n -c "$after[0]")"
assert_contains "H-024 two roles: the verdict is the new last comment" "$(jq -n -r "$after[1]")" "validator: verdict passed"
assert_eq "H-025 the new comment opens with the visible role and event line" "**harness: report**" "$(jq -n -r "$after[1]" | head -n 1)"

# Scenario: a role reports twice.
printf 'validator: second verdict\n' > validator2.md
"$h" tickets comment 1 validator2.md >/dev/null
again=$(comments 1)
assert_eq "H-024 same role twice: the second report is a new comment" "3" "$(jq -n "$again | length")"
assert_eq "H-024 same role twice: the earlier comments stay byte-identical" "$after" "$(jq -n -c "$again[0:2]")"

# State changes that report (block) or close (done) also only add.
printf 'blocked: question 1\n' > why.md
"$h" tickets claim 1 >/dev/null
"$h" tickets block 1 why.md >/dev/null
"$h" tickets "done" 1 >/dev/null
final=$(comments 1)
assert_eq "H-024 block and done: earlier comments stay byte-identical" "$again" "$(jq -n -c "$final[0:3]")"
assert_contains "H-024 block: the reason is one new comment" "$(jq -n -r "$final[3]")" "blocked: question 1"
assert_eq "H-025 block: the reason comment opens with the visible line" "**harness: blocked**" "$(jq -n -r "$final[3]" | head -n 1)"

edits=$(grep -E -- '--edit-last|--delete|^api	|^issue	comment	delete' "$HO_FAKE_GH_DIR/calls.log" || true)
assert_eq "H-024 no gh call edits or deletes a comment" "" "$edits"
assert_eq "H-024 every report used plain issue comment" "4" "$(grep -c '^issue	comment	' "$HO_FAKE_GH_DIR/calls.log" || true)"

# Local backend: a comment appends; the earlier bytes of the file stay as they were.
unset HO_TICKETS_SOURCE HO_TICKETS_REPO
export HO_TICKETS_DIR="$PWD/local/tickets"
"$h" tickets add "Local comments" body.md >/dev/null
"$h" tickets comment 1 worker.md >/dev/null
f=$(find "$HO_TICKETS_DIR" -name '1-*.md')
cp "$f" snapshot.md
"$h" tickets comment 1 validator.md >/dev/null
size=$(wc -c < snapshot.md | tr -d ' ')
assert_eq "H-024 local: the earlier log is a byte-identical prefix" "$(cat snapshot.md | od -c)" "$(head -c "$size" "$f" | od -c)"
assert_contains "H-024 local: the new report is appended" "$(tail -c +"$((size + 1))" "$f")" "validator: verdict passed"
