# Permission prompts (H-052; design D37-AUTONOMY-1, D37-AUTONOMY-2, D37-FLOW-8): by default a
# prompt gets no answer and one owner-action line; with session.permission_prompts analyse, a
# prompt the model judges acceptable is accepted once and recorded, and any doubt escalates.
# The screen text and its pattern are synthetic and built here; no runtime screen file is read.
# shellcheck source=sessions-setup.sh
. "$HO_TESTS_DIR/sessions-setup.sh"
# A user runtime profile that is the shipped one with a synthetic screen pattern file.
mkdir -p "$user/runtimes"
jq '.screen_file = "synth.screen.json"' "$HO_PLUGIN_ROOT/runtimes/claude-code.json" > "$user/runtimes/synth.json"
cat > "$user/runtimes/synth.screen.json" <<'JSON'
{"frame_start": "^\\|", "frame_end": "\\|$", "frame_only": "^[+-]+$", "input_box": "^> ",
 "shapes": [{"id": "permission", "anchor": "zq may the step zq run\\?", "last_nonblank": true}]}
JSON
printf '{"schemaVersion": 2, "runtime": {"main": "synth"}}\n' > "$user/config.json"
launch p1 >/dev/null
h1=$(rec p1 .handle)
out="$HO_FAKE_TERM_DIR/$(printf '%s' "$h1" | tr -c 'A-Za-z0-9-' '_')"
show() { printf '\nwork so far\n\nzq may the step zq run?\n' > "$out.out"; }
show2() { printf '\nother work %s\n\nzq may the step zq run?\n' "$1" > "$out.out"; }
perm() { local rc=0; HO_FAKE_CLAUDE_HOLD= "$h" screen "$run" permission p1 2>"$base/err" || rc=$?; echo "rc=$rc"; }
ledger() { cat "$run/ledger.jsonl"; }
enters() { grep -c "^tmux key $h1 Enter$" "$HO_FAKE_TERM_DIR/calls.log" 2>/dev/null || true; }

assert_eq "H-052: the setting is off by default" off "$("$h" config get .session.permission_prompts off)"
show
assert_eq "H-052: a synthetic permission prompt is classified" permission "$("$h" screen "$run" classify "$out.out" 2>/dev/null || true)"
before=$(enters)
r=$(perm)
assert_contains "H-052 D37-AUTONOMY-1: with the default setting the prompt is not answered" "$r" "owner-action"
assert_eq "H-052: no key is pressed with the default setting" "$before" "$(enters)"
assert_eq "D37-AUTONOMY-1: the default writes one owner-action line" 1 "$(ledger | jq -c 'select(.kind == "owner-action" and (.title | test("permission prompt")))' | wc -l | tr -d ' ')"
perm >/dev/null
assert_eq "D37-AUTONOMY-1: the same screen is escalated once" 1 "$(ledger | jq -c 'select(.kind == "owner-action" and (.title | test("permission prompt")))' | wc -l | tr -d ' ')"

# The setting is fixed at run start: analyse set during a run does not answer in that run.
printf '{"schemaVersion": 2, "runtime": {"main": "synth"}, "session": {"permission_prompts": "analyse"}}\n' > "$user/config.json"
show2 live
before=$(enters)
r=$(HO_FAKE_CLAUDE_STDOUT='{"acceptable": true}' perm)
assert_contains "D37-FLOW-8 H-052: analyse set during a run is not used in that run" "$r" "owner-action"
assert_eq "D37-FLOW-8: no key is pressed in a run started with off" "$before" "$(enters)"
assert_eq "D37-FLOW-8: the run stamp holds the setting of its start" off "$(jq -r .permission_prompts "$run/settings.json")"
# A new run under analyse, with its own session.
run=$("$h" run new)
assert_eq "H-052: a run started under analyse stamps analyse" analyse "$(jq -r .permission_prompts "$run/settings.json")"
launch p1 >/dev/null
h1=$(rec p1 .handle)
out="$HO_FAKE_TERM_DIR/$(printf '%s' "$h1" | tr -c 'A-Za-z0-9-' '_')"
# analyse: the model judges the prompt acceptable -> one accept, recorded.
show2 a
before=$(enters)
r=$(HO_FAKE_CLAUDE_STDOUT='{"acceptable": true}' perm)
assert_contains "H-052: under analyse an acceptable prompt is accepted" "$r" "accepted"
assert_eq "D37-AUTONOMY-1: the accept is one key press" $((before + 1)) "$(enters)"
assert_eq "D37-AUTONOMY-1: the ledger records the answer" "accept-once" "$(ledger | jq -r 'select(.kind == "permission-answer") | .answer' | tail -1)"
assert_eq "D37-AUTONOMY-1: the analysis ran without tools" yes "$(grep -q -- '--tools' "$base/claude.log" && echo yes || echo no)"
# analyse: doubt -> escalate, no key.
show2 b
before=$(enters)
r=$(HO_FAKE_CLAUDE_STDOUT='{"acceptable": false}' perm)
assert_contains "H-052: under analyse a doubtful prompt is escalated" "$r" "owner-action"
assert_eq "H-052: a doubtful prompt gets no key" "$before" "$(enters)"
# analyse: the analysis fails -> escalate.
show2 c
r=$(HO_FAKE_CLAUDE_STDOUT='no verdict' perm)
assert_contains "D37-AUTONOMY-1: a failed analysis escalates" "$r" "owner-action"
show2 d
r=$(HO_FAKE_CLAUDE_EXIT=1 HO_FAKE_CLAUDE_STDOUT='{"acceptable": true}' perm)
assert_contains "D37-AUTONOMY-1: an analysis that exits non-zero escalates" "$r" "owner-action"
# A runtime with no accept-once key escalates.
jq 'del(.permission_prompt)' "$user/runtimes/synth.json" > "$base/s.json" && mv "$base/s.json" "$user/runtimes/synth.json"
show2 e
before=$(enters)
r=$(HO_FAKE_CLAUDE_STDOUT='{"acceptable": true}' perm)
assert_contains "D37-AUTONOMY-1: a runtime with no accept-once key escalates" "$r" "owner-action"
assert_eq "D37-AUTONOMY-1: with no accept-once key nothing is pressed" "$before" "$(enters)"
# A bad value is a config error at run start.
printf '{"schemaVersion": 2, "runtime": {"main": "synth"}, "session": {"permission_prompts": "always"}}\n' > "$user/config.json"
assert_exit "D37-AUTONOMY-1: there is no always-accept value (run new refuses it)" 78 "$h" run new
printf '{"schemaVersion": 2, "runtime": {"main": "synth"}}\n' > "$user/config.json"

# D37-FLOW-8: a committed config cannot raise the setting silently.
printf '%s\n' '{"schemaVersion":2,"session":{"permission_prompts":"off"}}' > "$base/pc.json"
jq -s '.[0] * .[1]' "$proj/.harness/config.json" "$base/pc.json" > "$base/c2.json" && mv "$base/c2.json" "$proj/.harness/config.json"
select_config "$proj"
jq '.session.permission_prompts = "analyse"' "$proj/.harness/config.json" > "$base/c2.json" && mv "$base/c2.json" "$proj/.harness/config.json"
rc=0; "$h" config gate >/dev/null 2>"$base/err" || rc=$?
assert_eq "D37-FLOW-8 D37-AUTONOMY-1: off to analyse in a committed config is a raise" 73 "$rc"
assert_contains "D37-FLOW-8: the stop names the permission prompt setting" "$(cat "$base/err")" "session.permission_prompts"
