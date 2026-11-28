# Working brief and the reaction to a ticket that is not ready (T18; H-014, H-016; D7, D8,
# D37-INTAKE-4, D37-INTAKE-5). A judge shim picks its verdict by the ticket title in the prompt.
. "$HO_TESTS_DIR/intake-setup.sh"
mkdir -p "$base/judge"
cat > "$base/judge/claude" <<SHIM
#!/usr/bin/env bash
case "\$*" in
  *"Title: Thin one"*) export HO_FAKE_CLAUDE_STDOUT='{"ready": false, "questions": ["Which page?", "What proves it done?"], "assumptions": [], "brief": ""}' ;;
  *"Title: Gaps"*) export HO_FAKE_CLAUDE_STDOUT='{"ready": true, "questions": [], "assumptions": ["The export goes to out/", "UTF-8 encoding"], "brief": "## Outcome\nCSV export.\n\n## Checks\n- The export test passes."}' ;;
  *"Title: Human gap"*) export HO_FAKE_CLAUDE_STDOUT='{"ready": false, "questions": ["Which customer gets it first?"], "assumptions": ["UTF-8 encoding"], "brief": ""}' ;;
  *) export HO_FAKE_CLAUDE_STDOUT='{"ready": true, "questions": [], "assumptions": [], "brief": "## Outcome\nCSV export.\n\n## Scope\nsrc/report.sh\n\n## Acceptance criteria\n- One report exports.\n\n## Checks\n- The export test passes (inferred)."}' ;;
esac
exec "$HO_TESTS_DIR/fake-bin/claude" "\$@"
SHIM
chmod +x "$base/judge/claude"
jtick() { PATH="$base/judge:$PATH" tick "$@"; }
# rtick <run>: one due tick on another run, through the judge shim.
rtick() { [ ! -f "$1/intake/poll.json" ] || touch -t 200001010000 "$1/intake/poll.json"; PATH="$base/judge:$PATH" "$h" intake "$1" tick; }
body() { jq -r .body "$HO_FAKE_GH_DIR/issues/$1.json"; }
setcfg() { jq "$1" "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"; }
mode() { jq -r --arg t "$1" 'select(.kind == "readiness" and .ticket == $t) | .mode' "$run/ledger.jsonl" | tail -1; }

# H-016 D7 ask (the default under the safe profile): a not-ready ticket goes to blocked with
# numbered questions, and the next ticket is taken in the same tick.
run=$(cd "$proj" && "$h" run new --workers 5)
t1=$(ticket "Thin one")
t2=$(ticket "Clear one")
label alice "$t1" ready
label alice "$t2" ready
out=$(jtick)
assert_contains "H-016 ask: the not-ready ticket goes to blocked" "$out" "blocked $t1"
assert_eq "H-016 H-030 the not-ready ticket carries only blocked" '["harness:blocked"]' "$(labels "$t1")"
q=$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t1.json")
assert_contains "H-016 H-032 numbered questions on the blocked ticket (1)" "$q" "1. Which page?"
assert_contains "H-016 H-032 numbered questions on the blocked ticket (2)" "$q" "2. What proves it done?"
assert_contains "H-016 the next ticket is taken" "$out" "start $t2"
assert_eq "D37-INTAKE-5 no setting, safe profile: the mode is ask" "ask" "$(mode "$t1")"
assert_contains "D37-INTAKE-5 ask: the judge is told to turn every gap into a question" "$(cat "$HO_FAKE_CLAUDE_LOG")" 'do not fill gaps with assumptions'

# H-014 D8 D37-INTAKE-4: the working brief is a fresh comment; the body stays as picked up.
before=$(ticket "Brief body" "" "Make the report export CSV.")
label alice "$before" ready
orig=$(body "$before")
out=$(jtick)
assert_contains "H-014 the briefed ticket starts" "$out" "start $before"
wb=$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$before.json")
assert_eq "H-014 D8 the working brief is a new comment with its own title" "**orchestrator: Working brief**" "$(printf '%s\n' "$wb" | head -n 1)"
assert_contains "H-014 the working brief holds the inferred checks" "$wb" "## Checks"
assert_eq "D8 D37-INTAKE-4 the description stays as picked up" "$orig" "$(body "$before")"
assert_contains "H-014 the judge is asked for the brief with inferred checks" "$(cat "$HO_FAKE_CLAUDE_LOG")" "Name the checks you infer"

# H-014 tickets.normalize body: the description is replaced; no brief comment.
setcfg '.tickets.normalize = "body"'
t3=$(ticket "Rewrite me" "" "Make the report export CSV.")
label alice "$t3" ready
n0=$(ncomments "$t3")
jtick >/dev/null
assert_contains "H-014 normalize body: the description is the brief" "$(body "$t3")" "## Acceptance criteria"
assert_eq "H-014 normalize body: no Working brief comment" "" "$(comments "$t3" | grep -F 'Working brief' || true)"
# H-014 tickets.normalize off: no structured version at all.
setcfg '.tickets.normalize = "off"'
t4=$(ticket "No brief" "" "Make the report export CSV.")
label alice "$t4" ready
jtick >/dev/null
assert_eq "H-014 normalize off: no Working brief comment" "" "$(comments "$t4" | grep -F 'Working brief' || true)"
assert_eq "H-014 normalize off: the description is unchanged" "Make the report export CSV." "$(body "$t4")"
assert_contains "H-014 normalize off: the judge is told to leave the brief empty" "$(cat "$HO_FAKE_CLAUDE_LOG")" 'Leave "brief" empty.'
setcfg '.tickets.normalize = "sideways"'
assert_exit "H-014 an unknown normalize value is refused (exit 78)" 78 "$h" intake "$run" tick
setcfg 'del(.tickets.normalize)'

# H-016 D37-INTAKE-5: under the full profile the default is assume.
setcfg '.autonomy.profile = "full"'
runF=$(cd "$proj" && "$h" run new --workers 5)
t5=$(ticket "Gaps")
label alice "$t5" ready
out=$(rtick "$runF")
assert_contains "H-016 assume: a ticket with every gap filled starts" "$out" "start $t5"
assert_eq "D37-INTAKE-5 no setting, full profile: the mode is assume" "assume" "$(jq -r --arg t "$t5" 'select(.kind == "readiness" and .ticket == $t) | .mode' "$runF/ledger.jsonl")"
a=$(comments "$t5")
assert_contains "H-016 assume: every assumption is listed on the ticket (1)" "$a" "The export goes to out/"
assert_contains "H-016 assume: every assumption is listed on the ticket (2)" "$a" "UTF-8 encoding"
assert_contains "H-016 assume: the judge is told to fill gaps" "$(cat "$HO_FAKE_CLAUDE_LOG")" "Fill every gap you can infer"
t6=$(ticket "Human gap")
label alice "$t6" ready
out=$(rtick "$runF")
assert_contains "H-016 assume: a question only a human can answer blocks the ticket" "$out" "blocked $t6"
assert_contains "H-016 assume: the human question is numbered on the ticket" "$(jq -r '.comments[-1].body' "$HO_FAKE_GH_DIR/issues/$t6.json")" "1. Which customer gets it first?"

# H-016 a set value always wins over the profile default.
setcfg '.tickets.readiness.on_not_ready = "ask"'
runA=$(cd "$proj" && "$h" run new --workers 5)
t7=$(ticket "Set ask")
label alice "$t7" ready
rtick "$runA" >/dev/null
assert_eq "H-016 the project's own setting wins over the full profile" "ask" "$(jq -r --arg t "$t7" 'select(.kind == "readiness" and .ticket == $t) | .mode' "$runA/ledger.jsonl")"
setcfg '.tickets.readiness.on_not_ready = "maybe"'
assert_exit "H-016 an unknown reaction is refused (exit 78)" 78 rtick "$runA"

# H-014 local backend, normalize body: the description changes and the comment log is kept.
(
  unset HO_TICKETS_SOURCE HO_TICKETS_REPO
  export HO_TICKETS_DIR="$base/local/tickets"
  printf 'Make the report export CSV.' > "$base/lb.md"
  lt=$("$h" tickets add "Local brief" "$base/lb.md" blocked | sed -n 's/^OK created ticket \([0-9]*\).*/\1/p')
  printf 'note\n' > "$base/n.md"
  "$h" tickets comment "$lt" "$base/n.md" >/dev/null
  printf '## Outcome\nCSV export.\n' > "$base/brief.md"
  ( . "$HO_PLUGIN_ROOT/lib/common.sh"; . "$HO_PLUGIN_ROOT/lib/tickets.sh"; ho_tk_settings; ho_tk_set_body "$lt" "$base/brief.md" )
  shown=$("$h" tickets show "$lt")
  assert_contains "H-014 local body: the description is replaced" "$shown" "## Outcome"
  assert_eq "H-014 local body: the old description is gone" "" "$(printf '%s' "$shown" | grep -F 'Make the report export CSV.' || true)"
  assert_eq "H-014 local body: the comment log is kept" "1" "$("$h" tickets comments "$lt" | grep -c . || true)"
)
