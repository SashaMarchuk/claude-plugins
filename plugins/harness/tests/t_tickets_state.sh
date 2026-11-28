# H-030 (D2, S8-27): after every state change exactly one state label remains.
h="$HO_PLUGIN_ROOT/bin/harness"
export HO_FAKE_GH_DIR="$PWD/gh" HO_TICKETS_SOURCE=github HO_TICKETS_REPO=fake/repo
printf '## Outcome\nx\n\n## Scope\ny\n\n## Acceptance criteria\nz\n' > body.md
printf 'why\n' > why.md
state_labels() { jq -r '[.labels[] | select(test("^harness:(ready|in-progress|blocked|needs-review|done)$"))] | join(" ")' "$HO_FAKE_GH_DIR/issues/$1.json"; }
all_labels() { jq -r '.labels | sort | join(" ")' "$HO_FAKE_GH_DIR/issues/$1.json"; }

# All five states, one after another.
"$h" tickets add "Walk" body.md >/dev/null
assert_eq "H-030 github: a new ticket carries only harness:ready" "harness:ready" "$(state_labels 1)"
"$h" tickets claim 1 >/dev/null
assert_eq "H-030 github: claim leaves only harness:in-progress" "harness:in-progress" "$(state_labels 1)"
"$h" tickets block 1 why.md >/dev/null
assert_eq "H-030 github: block leaves only harness:blocked" "harness:blocked" "$(state_labels 1)"
"$h" tickets review 1 >/dev/null
assert_eq "H-030 github: review leaves only harness:needs-review" "harness:needs-review" "$(state_labels 1)"
"$h" tickets "done" 1 >/dev/null
assert_eq "H-030 github: done leaves only harness:done" "harness:done" "$(state_labels 1)"

# Scenario: a ready ticket moves to needs-review.
"$h" tickets add "Ready to review" body.md >/dev/null
"$h" tickets review 2 >/dev/null
assert_eq "H-030 github: ready -> needs-review removes the ready label" "harness:needs-review" "$(state_labels 2)"

# Scenario: done keeps no old label, from the dirty state seen in a past run (field note D7).
"$h" tickets add "Dirty" body.md blocked >/dev/null
gh issue edit 3 --repo fake/repo --add-label harness:in-progress --add-label harness:urgent --add-label bug
"$h" tickets "done" 3 >/dev/null
assert_eq "H-030 github: blocked plus in-progress -> done leaves only harness:done" "harness:done" "$(state_labels 3)"
assert_eq "H-030 github: labels that are not states stay" "bug harness:done harness:urgent" "$(all_labels 3)"

# release goes back to ready with one label.
"$h" tickets add "Release" body.md >/dev/null
"$h" tickets claim 4 >/dev/null
"$h" tickets release 4 >/dev/null
assert_eq "H-030 github: release leaves only harness:ready" "harness:ready" "$(state_labels 4)"

# Claim refuses a ticket that is not ready.
assert_exit "H-030 github: claim of a done ticket exits 65" 65 "$h" tickets claim 1

# The prefix is configurable (D2).
HO_STATE_PREFIX=hx "$h" tickets add "Prefixed" body.md >/dev/null
HO_STATE_PREFIX=hx "$h" tickets claim 5 >/dev/null
assert_eq "H-030 github: a custom prefix also keeps one state label" "hx:in-progress" "$(jq -r '.labels | join(" ")' "$HO_FAKE_GH_DIR/issues/5.json")"

# Local backend: the header keeps exactly one status line.
unset HO_TICKETS_SOURCE HO_TICKETS_REPO
export HO_TICKETS_DIR="$PWD/local/tickets"
status_lines() { awk '/^$/ { exit } /^status:/ { print }' "$(find "$HO_TICKETS_DIR" -name "$1-*.md")" | tr '\n' ' ' | sed 's/ $//'; }
"$h" tickets add "Walk" body.md >/dev/null
assert_eq "H-030 local: a new ticket is ready" "status: ready" "$(status_lines 1)"
"$h" tickets claim 1 >/dev/null
assert_eq "H-030 local: claim -> in-progress" "status: in-progress" "$(status_lines 1)"
"$h" tickets block 1 why.md >/dev/null
assert_eq "H-030 local: block -> blocked" "status: blocked" "$(status_lines 1)"
"$h" tickets review 1 >/dev/null
assert_eq "H-030 local: review -> needs-review" "status: needs-review" "$(status_lines 1)"
"$h" tickets "done" 1 >/dev/null
assert_eq "H-030 local: done -> done" "status: done" "$(status_lines 1)"

# A dirty header with two status lines ends with one.
printf 'title: Dirty\nstatus: blocked\nstatus: in-progress\ncreated: x\n\nbody\nstatus: text in the body\n' > "$HO_TICKETS_DIR/2-dirty.md"
"$h" tickets "done" 2 >/dev/null
assert_eq "H-030 local: blocked plus in-progress -> done leaves one status line" "status: done" "$(status_lines 2)"
assert_contains "H-030 local: body text is untouched" "$(cat "$HO_TICKETS_DIR/2-dirty.md")" "status: text in the body"
assert_eq "H-030 local: ids lists the done tickets" "1 2" "$("$h" tickets ids "done" | tr '\n' ' ' | sed 's/ $//')"
