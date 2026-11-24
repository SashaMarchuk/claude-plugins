# H-064 (tasks 7.1, 7.2): flow profiles `gsd` and `basic`, the flow profile contract and
# the thin role prompts. D37-FLOW-1: no flow-system name in engine code. S8-16a: `basic`
# writes every step out. Field note D3: a value that quotes a placeholder never blocks a render.
h="$HO_PLUGIN_ROOT/bin/harness"
roles="worker validator"
cycle="classify grill plan execute code-review verify ui-check ship"

assert_eq "H-064: both flow profiles ship" "basic gsd" "$("$h" flow list | tr '\n' ' ' | sed 's/ $//')"

# Caller values for a render. The engine fills FLOW_*, STEP_* itself.
printf 'ticket body line 1\nline 2\n' | "$h" tickets fence 41 > ticket.txt
set_args() {
  printf '%s\0' --set RUN_ID 20261125-000000-abcdef --set TICKET_ID 41 \
    --set BRANCH lane/t8 --set BASE trunk --set WORKDIR /work/lane \
    --set STEP_RESULT_FILE /run/step-result --set VERDICT_FILE /run/verdict \
    --file TICKET_TEXT "${TICKET_FILE:-ticket.txt}"
}
render() { set_args | xargs -0 "$h" flow render "$@"; }

for flow in gsd basic; do
  assert_eq "H-064: flow check passes for $flow" "flow $flow OK" "$("$h" flow check "$flow" 2>&1)"

  steps=$("$h" flow steps "$flow" 2>&1 || true)
  assert_eq "H-064: $flow gives the full ordered cycle, ship last" "$cycle" \
    "$(printf '%s\n' "$steps" | cut -f2 | tr '\n' ' ' | sed 's/ $//')"
  assert_eq "H-064: $flow numbers its steps 1..8 in order" "1 2 3 4 5 6 7 8" \
    "$(printf '%s\n' "$steps" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
  assert_eq "H-064: in $flow only the grilling step waits for open questions" "grill" \
    "$(printf '%s\n' "$steps" | awk -F '\t' '$3 == "questions" { print $2 }')"
  assert_eq "H-064: in $flow every other step always runs" "7" \
    "$(printf '%s\n' "$steps" | awk -F '\t' '$3 == "always"' | wc -l | tr -d ' ')"

  all=""
  for step in $cycle; do
    rc=0; out=$(render "$flow" worker --step "$step" 2>&1) || rc=$?
    assert_eq "H-064: $flow worker prompt renders for step $step" "0" "$rc"
    assert_contains "H-064: $flow worker prompt for $step carries its step id" "$out" "($step)"
    all="$all$out"
  done
  rc=0; out=$(render "$flow" validator 2>&1) || rc=$?
  assert_eq "H-064: $flow validator prompt renders" "0" "$rc"
  all="$all$out"
  assert_eq "H-064 (7.2): no leftover @NAME@ placeholder in any rendered $flow prompt" "" \
    "$(printf '%s' "$all" | grep -oE '@[A-Z0-9_]+@' || true)"
  assert_eq "H-064 (7.2): no double-brace token in any rendered $flow prompt" "" \
    "$(printf '%s' "$all" | grep -oE '\{\{|\}\}' || true)"
  assert_contains "H-064: the $flow worker prompt carries the ticket text" "$all" "ticket body line 1
line 2"
  assert_contains "H-064: the $flow validator prompt lists the cycle" "$out" "8. Shipping"
done

# S8-16a: every step of `basic` is written out (a prompt file of its own, with real text).
for step in $cycle; do
  f="$HO_PLUGIN_ROOT/flows/basic/steps/$step.md"
  n=$( [ -f "$f" ] && wc -w < "$f" | tr -d ' ' || echo 0)
  if [ "$n" -ge 30 ]; then ok "S8-16a: basic writes out step $step"; else bad "S8-16a: basic writes out step $step" "$f has $n words"; fi
done

# Shipped templates are plain ASCII and hold no double-brace token.
tpl=$(cd "$HO_PLUGIN_ROOT" && find prompts flows -type f -name '*.md' 2>/dev/null | sort || true)
assert_eq "H-064: 2 role prompts and 16 step prompts ship" "18" "$(printf '%s\n' "$tpl" | grep -c . || true)"
assert_eq "H-064: shipped templates hold no double-brace token" "" \
  "$(cd "$HO_PLUGIN_ROOT" && grep -lE '\{\{|\}\}' $tpl /dev/null || true)"
assert_eq "H-064: shipped templates are plain ASCII" "" \
  "$(cd "$HO_PLUGIN_ROOT" && LC_ALL=C grep -l '[^ -~	]' $tpl /dev/null || true)"

# Field note D3: values go in literally and are never scanned again.
weird='quote @LANE@ and {{RUN_ID}} & \1 \\ $(id) `id` %s
second line @STEP_ID@'
printf '%s\n' "$weird" | "$h" tickets fence 41 > weird.txt
out=$(TICKET_FILE=weird.txt set_args | xargs -0 "$h" flow render basic validator 2>&1 || true)
assert_contains "Field note D3: a value that quotes placeholders goes in byte for byte" "$out" "$weird"
rc=0; TICKET_FILE=weird.txt set_args | xargs -0 "$h" flow render basic validator >/dev/null 2>&1 || rc=$?
assert_eq "Field note D3: a value that quotes placeholders does not block the render" "0" "$rc"

# A template token with no value fails the render, names the token and prints nothing.
rc=0; err=$("$h" flow render basic validator --set RUN_ID x 2>&1 >/dev/null) || rc=$?
assert_eq "H-064 (7.2): a missing value fails the render (exit 65)" "65" "$rc"
assert_contains "H-064 (7.2): the failure names the missing placeholder" "$err" "TICKET_ID"
assert_eq "H-064 (7.2): a failed render prints no prompt" "" "$("$h" flow render basic validator 2>/dev/null || true)"
assert_exit "H-064: the worker role needs a step" 64 "$h" flow render basic worker
assert_exit "H-064: an unknown step is refused" 64 "$h" flow render basic worker --step nope
assert_exit "H-064: an unknown role is refused" 64 "$h" flow render basic nope
assert_exit "H-064: the caller cannot set an engine value" 64 "$h" flow render basic validator --set FLOW_NAME x
assert_exit "H-064: the caller cannot set an undeclared name" 64 "$h" flow render basic validator --set NOT_DECLARED x

# H-068 scenario "The chosen flow cannot be loaded": a missing or broken flow stops and is named.
assert_exit "H-064: flow verbs have no default flow" 64 "$h" flow steps
rc=0; err=$("$h" flow steps nosuch 2>&1) || rc=$?
assert_eq "H-068: a missing flow file stops (exit 78)" "78" "$rc"
assert_contains "H-068: the stop names the missing flow" "$err" "nosuch"
for name in ../flows/gsd Gsd 'a b' ''; do
  assert_exit "H-064: flow name [$name] is refused" 64 "$h" flow steps "$name"
done

# Contract checks, against flow folders built in this temp dir.
export HO_FLOWS_DIR="$PWD/flows"
mk() { # mk <name> <flow.json>; every step file exists with a little text
  mkdir -p "flows/$1/steps"
  printf '%s\n' "$2" > "flows/$1/flow.json"
  for s in a b; do printf 'Do step %s for @TICKET_ID@.\n' "$s" > "flows/$1/steps/$s.md"; done
}
good='{"schemaVersion":2,"name":"t","description":"d","source":"own","steps":[{"id":"a","title":"A","when":"always","prompt":"steps/a.md"},{"id":"b","title":"B","when":"always","prompt":"steps/b.md"}]}'
mk t "$good"
assert_eq "H-064: a well-formed test flow passes the check" "flow t OK" "$("$h" flow check t 2>&1)"
assert_eq "H-064: steps keep the file order" "a b" "$("$h" flow steps t | cut -f2 | tr '\n' ' ' | sed 's/ $//')"
check_bad() { # check_bad <label> <jq edit> [after-mk command]
  rm -rf flows/t; mk t "$(printf '%s' "$good" | jq -c "$2")"
  [ -z "${3:-}" ] || eval "$3"
  local rc=0 err
  err=$("$h" flow check t 2>&1) || rc=$?
  assert_eq "H-064: flow check refuses $1 (exit 78)" "78" "$rc"
  assert_contains "H-064: the refusal of $1 names the flow" "$err" "flow t"
}
check_bad "schemaVersion 1" '.schemaVersion = 1'
check_bad "a name that is not the folder name" '.name = "other"'
check_bad "an unknown source" '.source = "both"'
check_bad "an empty step list" '.steps = []'
check_bad "a duplicate step id" '.steps[1].id = "a"'
check_bad "a bad step id" '.steps[0].id = "A b"'
check_bad "an unknown when" '.steps[0].when = "sometimes"'
check_bad "a step prompt outside the flow folder" '.steps[0].prompt = "../t/steps/a.md"'
check_bad "an absolute step prompt" '.steps[0].prompt = "/etc/hosts"'
check_bad "a missing step prompt" '.steps[0].prompt = "steps/none.md"'
check_bad "an undeclared placeholder in a step" '.' 'printf "@NOT_DECLARED@\n" > flows/t/steps/a.md'
check_bad "a double-brace token in a step" '.' 'printf "{{TICKET_ID}}\n" > flows/t/steps/b.md'
check_bad "an engine placeholder in a step" '.' 'printf "@STEP_TEXT@\n" > flows/t/steps/b.md'
rm -rf flows/t; mk t "$good"; printf 'not json' > flows/t/flow.json
rc=0; "$h" flow steps t >/dev/null 2>&1 || rc=$?
assert_eq "H-068: an unreadable flow file stops (exit 78)" "78" "$rc"
# Review findings on the first T8 draft, each shown failing on that draft (the large value
# fails there only where one argument is limited, as on Linux; it guards the temp-file path).
mkdir -p outside && printf 'SECRET outside the flow\n' > outside/a.md
check_bad "a step prompt behind a linked folder" '.steps[0].prompt = "linked/a.md"' 'ln -s "$PWD/outside" flows/t/linked'
check_bad "a newline in a title" '.steps[0].title = "A\n9\tevil\tquestions\tX"'
check_bad "a step id that ends in a newline" '.steps[1].id = "a\n"'
rm -rf flows/t; mk t "$good"; mv flows/t outside/t2; ln -s "$PWD/outside/t2" flows/t
assert_eq "H-064: a linked flow folder is read from its real place" "flow t OK" "$("$h" flow check t 2>&1)"
rm -f flows/t; mk t "$good"
printf 'Step @STEP_ID@ is @STEP_TITLE@; quoted: @RUN_ID@.\n' > flows/t/steps/a.md
OLDPWD_T=$PWD; printf 't\n' | "$h" tickets fence 1 > ticket1.txt
rc=0; out=$("$h" flow render t worker --step a --set RUN_ID '@STEP_TEXT@ @TICKET_ID@ {{x}}' --set TICKET_ID 1 \
  --set WORKDIR /w --set BRANCH b --set STEP_RESULT_FILE /r --file TICKET_TEXT "$OLDPWD_T/ticket1.txt" 2>&1) || rc=$?
assert_eq "H-064: a step prompt may use its own step id and title" "0" "$rc"
assert_contains "Field note D3: a worker step value goes in literally, in both render passes" "$out" \
  "Step a is A; quoted: @STEP_TEXT@ @TICKET_ID@ {{x}}."
awk 'BEGIN { for (i = 0; i < 40000; i++) printf "0123456789abcdefghijklmnopqrstuvwxyz\n" }' | "$h" tickets fence 41 > big.txt
rc=0; out=$(TICKET_FILE=big.txt set_args | HO_FLOWS_DIR= xargs -0 "$h" flow render basic validator --set RUN_ID late 2>&1) || rc=$?
assert_eq "H-064: a 1.4 MB ticket value followed by --set renders" "0" "$rc"
assert_contains "H-064: the large value arrives whole" "$out" "$(tail -n 2 big.txt | head -n 1)"
printf 'ab\377\376cd' > bad.txt
rc=0; out=$(HO_FLOWS_DIR= "$h" flow render basic validator --set RUN_ID r --file TICKET_TEXT bad.txt 2>&1) || rc=$?
assert_eq "H-064: a value that is not UTF-8 is refused, not changed (exit 65)" "65" "$rc"
assert_contains "H-064: the refusal names the value" "$out" "TICKET_TEXT"
# H-018: ticket text reaches a session only inside the fence of this same ticket.
printf 'raw ticket text\n' > raw.txt
for f in raw.txt ticket1.txt; do
  rc=0; err=$(HO_FLOWS_DIR= "$h" flow render basic validator --set RUN_ID r --set TICKET_ID 41 --set BRANCH b \
    --set BASE m --set WORKDIR /w --set VERDICT_FILE /v --file TICKET_TEXT "$f" 2>&1 >/dev/null) || rc=$?
  assert_eq "H-018: ticket text $f that is not fenced for ticket 41 is refused (exit 65)" "65" "$rc"
  assert_contains "H-018: the refusal of $f names TICKET_TEXT" "$err" "TICKET_TEXT"
done
unset HO_FLOWS_DIR

# D37-FLOW-1: engine code holds no flow-system name, in text or in file names. The one
# exception is the 0.6.0 script list in lib/isolation.sh, which names old scripts to refuse them.
names='gsd|get-shit-done|superpowers'
hits=$(cd "$HO_PLUGIN_ROOT" && grep -rniE "$names" bin lib prompts | grep -v '^lib/isolation.sh:[0-9]*:HO_OLD_SCRIPTS=' || true)
assert_eq "D37-FLOW-1: engine code names no flow system" "" "$hits"
assert_eq "D37-FLOW-1: no engine file is named after a flow system" "" \
  "$(cd "$HO_PLUGIN_ROOT" && find bin lib prompts | grep -iE "$names" || true)"
