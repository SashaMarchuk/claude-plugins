# H-140, D43: /harness:feedback files a problem report as one issue without labels in the
# plugin's own repository, after the person's yes. The technical context is fixed (plugin
# version, runtime version, operating system, a state summary of the last run) and holds no
# private data. Every tracker call goes to the fake gh in tests/fake-bin.
h="$HO_PLUGIN_ROOT/bin/harness"
base=$PWD
proj="$base/proj"
mkdir -p "$proj/.harness"
printf '%s\n' '{"schemaVersion":2,"runtime":{"main":"claude-code"}}' > "$proj/.harness/config.json"
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$base/user" HO_FAKE_GH_DIR="$base/gh"
gh_calls() { cat "$HO_FAKE_GH_DIR/calls.log" 2>/dev/null || true; }
creates() { find "$HO_FAKE_GH_DIR/issues" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

# Checksum of a whole folder: every path, mode and content.
tree_sum() {
  (cd "$1" && find . -print | LC_ALL=C sort | while IFS= read -r p; do
    if [ -d "$p" ]; then printf 'd %s\n' "$p"
    else printf 'f %s %s\n' "$p" "$(cksum < "$p")"; fi
  done) | cksum
}
# The text shown between the "Title:" block and the DRAFT line, exactly as printed.
shown_body() { printf '%s\n' "$1" | awk '/^Title: /{t=1; getline; next} /^DRAFT /{exit} t' | sed '$d'; }
draft_of() { printf '%s\n' "$1" | sed -n 's/^DRAFT //p'; }
code_of() { printf '%s\n' "$1" | sed -n 's/^CODE //p'; }
sha16() { if command -v shasum >/dev/null 2>&1; then shasum -a 256 < "$1"; else sha256sum < "$1"; fi | cut -c1-16; }

# Token fixtures are built by concatenation, so no whole token sits in this file.
t_gh="gh""p_""Ab3dEf6hIj9kLm2nOp5qRs8tUv1wXy4z"
t_pat="github""_pat_""11ABCDEFG0123456789_abcdefghijkl"
t_sk="sk""-""live-ABCDEFGHIJKLMNOPQRSTUVWX"
t_slack="xo""xb-""1234567890-abcdefghij"
t_aws="AK""IA""ABCDEFGHIJKLMNOP"
t_jwt="ey""JhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.c2lnbmF0dXJlLXZhbHVl"
t_long="Zm9vYmFy""ZmFrZWJhc2U2NHRva2VudGV4dGZvcnRlc3Rpbmc1Mjk"
tokens="$t_gh $t_pat $t_sk $t_slack $t_aws $t_jwt $t_long"

# ---- No run yet: the context still comes, and the text says there is no last run ------------
printf 'The run stopped after the first ticket.\n' > "$base/d1.txt"
rc=0; out=$(cd "$proj" && "$h" feedback preview "$base/d1.txt") || rc=$?
assert_eq "H-140 no run: preview exits 0" "0" "$rc"
assert_contains "H-140 no run: the text says there is no last run" "$out" "there is no last run"
assert_contains "H-140 / D43: the text holds the person's description" "$out" "The run stopped after the first ticket."
v=$(jq -r .version "$HO_PLUGIN_ROOT/.claude-plugin/plugin.json")
assert_contains "H-140 / D43: the text holds the plugin version" "$out" "- Plugin version: $v"
assert_contains "H-140 / D43: the text holds the runtime and its version" "$out" "- Runtime: claude-code 0.0.0"
assert_contains "H-140 / D43: the text holds the operating system" "$out" "- Operating system: $(uname -s) $(uname -r)"
repo=$(jq -r .homepage "$HO_PLUGIN_ROOT/.claude-plugin/plugin.json" | sed -E 's#^https://github\.com/([^/]+)/([^/]+).*#\1/\2#')
assert_contains "H-140 / D43: the text names the plugin's own repository and the person's own login" "$out" \
  "filed in $repo under your own GitHub login, with no labels"
assert_eq "H-140: a preview makes no tracker call" "" "$(gh_calls)"

# ---- The person says no: nothing is sent --------------------------------------------------
d=$(draft_of "$out"); c=$(code_of "$out")
assert_exit "H-140 no yes: send without --yes is refused (exit 65)" 65 "$h" feedback send --draft "$d" --code "$c"
assert_exit "H-140 no yes: send with a wrong code is refused (exit 65)" 65 "$h" feedback send --draft "$d" --code 0000000000000000 --yes
assert_exit "H-140 no yes: send with no code is refused (exit 64)" 64 "$h" feedback send --draft "$d" --yes
cp "$d/body.md" "$base/body.keep"
printf 'one more line\n' >> "$d/body.md"
assert_exit "H-140: a draft changed after it was shown is not sent (exit 65)" 65 "$h" feedback send --draft "$d" --code "$c" --yes
cp "$base/body.keep" "$d/body.md"
# The send gate is a second check: a changed draft with a fresh code still may not carry a
# line outside the fixed context fields.
printf -- '- Account: %s\n' "zedacctline" >> "$d/body.md"
cat "$d/title.txt" "$d/body.md" > "$base/all.txt"
rc=0; err=$("$h" feedback send --draft "$d" --code "$(sha16 "$base/all.txt")" --yes 2>&1) || rc=$?
assert_eq "D43 gate: send refuses a draft with a line outside the fixed context fields (exit 65)" "65" "$rc"
assert_contains "D43 gate: the refusal names the kind" "$err" "a line outside the fixed context fields"
case $err in *zedacctline*) bad "D43 gate: the refusal does not print the line" "it did" ;; *) ok "D43 gate: the refusal does not print the line" ;; esac
cp "$base/body.keep" "$d/body.md"
assert_eq "H-140 no yes: nothing was sent" "0" "$(creates)"

# ---- Yes: one issue, no labels, exactly the shown text ------------------------------------
rc=0; res=$("$h" feedback send --draft "$d" --code "$c" --yes) || rc=$?
assert_eq "H-140 yes: send exits 0" "0" "$rc"
assert_contains "H-140 yes: send prints the issue link" "$res" "OK filed https://github.com/fake/repo/issues/1"
assert_eq "H-140 yes: exactly one issue is created" "1" "$(creates)"
assert_eq "H-140 yes: the issue has no labels" "[]" "$(jq -c .labels "$HO_FAKE_GH_DIR/issues/1.json")"
assert_eq "H-140 yes: the call passes no label" "0" "$(gh_calls | grep -c -- '--label' || true)"
assert_contains "H-140 yes: the issue goes to the plugin's own repository" "$(gh_calls | grep '^issue	create' | head -n 1)" "--repo	$repo	"
assert_eq "H-140 yes: the issue body is the shown text, byte for byte" "$(shown_body "$out")" \
  "$(jq -j .body "$HO_FAKE_GH_DIR/issues/1.json")"
assert_eq "H-140 yes: the issue title is the shown title" "$(printf '%s\n' "$out" | sed -n 's/^Title: //p')" \
  "$(jq -r .title "$HO_FAKE_GH_DIR/issues/1.json")"
assert_eq "H-140 yes: the draft is removed after the send" "no" "$([ -e "$d" ] && echo yes || echo no)"

# ---- A failed tracker call keeps the draft ------------------------------------------------
out=$(cd "$proj" && "$h" feedback preview "$base/d1.txt"); d=$(draft_of "$out")
rc=0; HO_FAKE_GH_FAIL="issue create" "$h" feedback send --draft "$d" --code "$(code_of "$out")" --yes >/dev/null 2>&1 || rc=$?
assert_eq "H-140: a failed tracker call exits 1" "1" "$rc"
assert_eq "H-140: a failed tracker call keeps the draft" "yes" "$([ -f "$d/body.md" ] && echo yes || echo no)"
rm -rf "$d"

# ---- Private data stays out (a private project's run) -------------------------------------
# Canaries in every free-text place: ledger values, a marker, a ticket title and body, the
# project path, HOME, the account names, the ticket repository and the tracker login.
export USER=canaryacct LOGNAME=canaryacct HO_FAKE_GH_USER=canary-gh-login HO_TICKETS_REPO=canary-org/canary-repo
run=$("$h" run new)
"$h" state "$run" decision "CANARY-DECISION-TITLE" "reason with $proj/src/a.ts and $t_gh"
"$h" state "$run" owner-action "CANARY-OWNER" "why $t_aws" "deploy --token $t_sk" "verify at $HOME/x"
"$h" state "$run" marker set canary-lane.pr-ready
{
  jq -cn --arg r "$(basename "$run")" '{ts: "2026-01-01T00:00:00Z", run: $r, kind: "session-launch",
    name: "CANARY-SESSION", role: "worker", session_id: "CANARY-SID", account: "canaryacct"}'
  jq -cn --arg r "$(basename "$run")" '{ts: "2026-01-01T00:00:00Z", run: $r, kind: "session-launch",
    name: "x", role: "CANARYROLE", session_id: "y", account: "z"}'
  jq -cn --arg r "$(basename "$run")" --arg p "$proj" '{ts: "2026-01-01T00:00:00Z", run: $r,
    kind: "session-close-failed", name: "CANARY-NAME", reason: ("CANARY-REASON at " + $p)}'
  jq -cn --arg r "$(basename "$run")" '{ts: "2026-01-01T00:00:00Z", run: $r,
    kind: "CANARY TICKET TEXT in a kind", reason: "x"}'
  printf '%s\n' "not json CANARY-BROKEN-LINE $t_pat"
} >> "$run/ledger.jsonl"
mkdir -p "$proj/.harness/tickets"
printf '## Goal\nCANARY-TICKET-BODY secret plan\n\n## Acceptance\n- [ ] it works\n' > "$base/tb.md"
(cd "$proj" && HO_TICKETS_DIR="$proj/.harness/tickets" "$h" tickets add "CANARY-TICKET-TITLE private" "$base/tb.md" blocked >/dev/null 2>&1) || true
before=$(tree_sum "$run")
# Owner decision 2026-11-27 on #92: the description is sent as written; the person answers for what they paste. Private
# values here are the person's own words and reach the issue unchanged.
{
  printf 'It hangs. My notes are in %s/notes.md\n' "$proj"
  printf 'Token: %s, I am canaryacct, mail canary@example.com\n' "$t_gh"
  printf '/harness:run hangs after /harness:status; see https://github.com/acme/tools/issues/12345\n'
} > "$base/d2.txt"
rc=0; out=$(cd "$proj" && "$h" feedback preview "$base/d2.txt") || rc=$?
assert_eq "H-140 private: preview exits 0" "0" "$rc"
d=$(draft_of "$out")
rc=0; "$h" feedback send --draft "$d" --code "$(code_of "$out")" --yes >/dev/null || rc=$?
assert_eq "H-140 private: the draft is sent after a yes" "0" "$rc"
n=$(creates)
body=$(jq -r .body "$HO_FAKE_GH_DIR/issues/$n.json")
assert_eq "H-140 owner decision 2026-11-27: the description reaches the issue exactly as written" "$(cat "$base/d2.txt")" \
  "$(printf '%s\n' "$body" | awk '/^---$/{exit} {print}' | sed '$d')"
assert_contains "H-140 owner decision 2026-11-27: the title is the first line of the description, as written" \
  "$(jq -r .title "$HO_FAKE_GH_DIR/issues/$n.json")" "Harness feedback: It hangs. My notes are in"
# The title cut at 70 counts characters, so a multi-byte character is never split.
zh=""; for i in $(seq 1 70); do zh="${zh}Ж"; done; zh70=$zh; zh="${zh}ЖЖЖЖЖЖЖЖЖЖ"
printf '%s\n' "$zh" > "$base/d9.txt"
rc=0; out9=$(cd "$proj" && "$h" feedback preview "$base/d9.txt") || rc=$?
assert_eq "H-140 title: a non-Latin first line gives a preview (exit 0)" "0" "$rc"
assert_eq "H-140 title: a non-Latin first line is cut at 70 whole characters" "Harness feedback: $zh70" \
  "$(printf '%s\n' "$out9" | sed -n 's/^Title: //p')"
rm -rf "$(draft_of "$out9")"
# Only the context is checked: it holds no value of the private run.
ctx=$(printf '%s\n' "$body" | sed -n '/^Technical context/,$p')
leaks=""
for canary in CANARY Canary canary "$proj" "$HOME" "$base" $tokens; do
  case $ctx in *"$canary"*) leaks="$leaks [$canary]" ;; esac
done
assert_eq "H-140 / D43 private: the added context holds no ticket text, path, token or account name" "" "$leaks"
assert_contains "D43 summary: the run state is reported" "$ctx" "- Last run: not stopped,"
assert_contains "D43 summary: step names are the fixed role names, others counted as other" "$ctx" \
  "- Steps (session roles launched): other 1, worker 1"
assert_contains "D43 summary: engine error codes are event kinds with counts" "$ctx" "owner-action x1, session-close-failed x1, unreadable x1"
assert_contains "D43 summary: ticket counts per state" "$ctx" "- Tickets per state: ready 0, in-progress 0, blocked 1, needs-review 0, done 0"
assert_eq "H-140: the preview leaves the run folder byte-identical" "$before" "$(tree_sum "$run")"
unset USER LOGNAME HO_FAKE_GH_USER HO_TICKETS_REPO

# ---- Allow-list context: a private value next to each field does not appear ----------------
# Run state and engine error codes: a stop event and an error event carry private reasons.
jq -cn --arg r "$(basename "$run")" '{ts: "2026-01-01T00:00:00Z", run: $r, kind: "session-dead", reason: "zederrreason /Users/x"}' >> "$run/ledger.jsonl"
jq -cn --arg r "$(basename "$run")" '{ts: "2026-01-01T00:00:00Z", run: $r, kind: "stop", reason: "zedstopreason", by: "zedstopper"}' >> "$run/ledger.jsonl"
# A made-up event kind is not copied.
jq -cn --arg r "$(basename "$run")" '{ts: "2026-01-01T00:00:00Z", run: $r, kind: "zedclient-billing-export-failed"}' >> "$run/ledger.jsonl"
rc=0; out=$(cd "$proj" && "$h" feedback preview "$base/d1.txt") || rc=$?
assert_eq "D43 allow-list: a preview over private ledger values exits 0" "0" "$rc"
assert_contains "D43 allow-list run state: a stop is reported as stopped" "$out" "- Last run: stopped,"
assert_contains "D43 allow-list error codes: the error kind is counted" "$out" "session-dead x1"
for m in zedstopreason zedstopper zederrreason zedclient; do
  case $out in
    *"$m"*) bad "D43 allow-list: the ledger value [$m] is not copied" "it was" ;;
    *) ok "D43 allow-list: the ledger value [$m] is not copied" ;;
  esac
done
rm -rf "$(draft_of "$out")"
# Runtime version: only a version-shaped word of the runtime's output is kept.
rc=0; out=$(cd "$proj" && HO_FAKE_CLAUDE_VERSION="0.0.0 /Users/zedverpath (zedvername)" "$h" feedback preview "$base/d1.txt") || rc=$?
assert_contains "D43 allow-list runtime version: the version word is kept" "$out" "- Runtime: claude-code 0.0.0"
case $out in
  *zedver*) bad "D43 allow-list runtime version: other words of the runtime output are not copied" "they were" ;;
  *) ok "D43 allow-list runtime version: other words of the runtime output are not copied" ;;
esac
rm -rf "$(draft_of "$out")"
# OS name: each uname word must have its shape, or it shows as unknown.
mkdir -p "$base/fakeuname"
cat > "$base/fakeuname/uname" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in -s) echo "Darwin zedosname" ;; -r) echo "25.5.0/zedrelname" ;; -m) echo "arm64" ;; *) echo "Darwin zedhost" ;; esac
EOF
chmod +x "$base/fakeuname/uname"
rc=0; out=$(cd "$proj" && PATH="$base/fakeuname:$PATH" "$h" feedback preview "$base/d1.txt") || rc=$?
assert_eq "D43 allow-list OS: a preview with odd uname words exits 0" "0" "$rc"
assert_contains "D43 allow-list OS: a word with the wrong shape shows as unknown" "$out" "- Operating system: unknown unknown arm64"
case $out in
  *zedosname*|*zedrelname*|*zedhost*) bad "D43 allow-list OS: other uname words are not copied" "they were" ;;
  *) ok "D43 allow-list OS: other uname words are not copied" ;;
esac
rm -rf "$(draft_of "$out")"
# Plugin version: a manifest version with the wrong shape shows as unknown.
cp -R "$HO_PLUGIN_ROOT" "$base/pcopy"
jq '.version = "1.0.0 zedvermark"' "$HO_PLUGIN_ROOT/.claude-plugin/plugin.json" > "$base/pcopy/.claude-plugin/plugin.json"
rc=0; out=$(cd "$proj" && "$base/pcopy/bin/harness" feedback preview "$base/d1.txt") || rc=$?
assert_eq "D43 allow-list plugin version: a preview with an odd version exits 0" "0" "$rc"
assert_contains "D43 allow-list plugin version: it shows as unknown" "$out" "- Plugin version: unknown"
case $out in
  *zedvermark*) bad "D43 allow-list plugin version: the odd version is not copied" "it was" ;;
  *) ok "D43 allow-list plugin version: the odd version is not copied" ;;
esac
rm -rf "$(draft_of "$out")" "$base/pcopy"
# Runtime label: only a runtime the plugin ships is named; a user profile's own name is not.
mkdir -p "$base/user/runtimes"
cp "$HO_PLUGIN_ROOT/runtimes/codex.json" "$base/user/runtimes/zedprivate-rt.json"
cp "$proj/.harness/config.json" "$base/config.keep2"
printf '%s\n' '{"schemaVersion":2,"runtime":{"main":"zedprivate-rt"}}' > "$proj/.harness/config.json"
rc=0; out=$(cd "$proj" && "$h" feedback preview "$base/d1.txt") || rc=$?
assert_eq "D43 allow-list runtime label: a user runtime gives a preview (exit 0)" "0" "$rc"
assert_contains "D43 allow-list runtime label: a user runtime shows as unknown" "$out" "- Runtime: unknown"
case $out in
  *zedprivate*) bad "D43 allow-list runtime label: the user runtime name is not copied" "it was" ;;
  *) ok "D43 allow-list runtime label: the user runtime name is not copied" ;;
esac
rm -rf "$(draft_of "$out")" "$base/user/runtimes/zedprivate-rt.json"
cp "$base/config.keep2" "$proj/.harness/config.json"

# ---- Broken state still gives a report ----------------------------------------------------
cp "$proj/.harness/config.json" "$base/config.keep"
printf 'not json\n' > "$proj/.harness/config.json"
rc=0; out=$(cd "$proj" && "$h" feedback preview "$base/d1.txt" 2>/dev/null) || rc=$?
assert_eq "H-140: a broken config still gives a preview (exit 0)" "0" "$rc"
assert_contains "H-140: with a broken config the runtime is unknown" "$out" "- Runtime: unknown"
rm -rf "$(draft_of "$out")"
# A runtime label with no shipped or user profile is not copied: it may be a private name.
printf '%s\n' '{"schemaVersion":2,"runtime":{"main":"zedclient-runtime"}}' > "$proj/.harness/config.json"
rc=0; out=$(cd "$proj" && "$h" feedback preview "$base/d1.txt" 2>/dev/null) || rc=$?
assert_eq "D43 round 1: a runtime label with no profile still gives a preview (exit 0)" "0" "$rc"
assert_contains "D43 round 1: a runtime label with no profile is shown as unknown" "$out" "- Runtime: unknown"
case $out in
  *zedclient*) bad "D43 round 1: the label with no profile does not reach the text" "it does" ;;
  *) ok "D43 round 1: the label with no profile does not reach the text" ;;
esac
rm -rf "$(draft_of "$out")"
cp "$base/config.keep" "$proj/.harness/config.json"

old="$base/old"
mkdir -p "$old/.harness/runs/20260101-000000-abc123"
printf '%s\n' '{"schemaVersion":2}' > "$old/.harness/config.json"
printf 'STATE=running\n' > "$old/.harness/runs/20260101-000000-abc123/state.env"
before=$(tree_sum "$old")
rc=0; out=$(cd "$old" && HO_PROJECT_DIR="$old" "$h" feedback preview "$base/d1.txt") || rc=$?
assert_eq "H-140: a project with only an unstamped (0.6.0) run folder gives a preview" "0" "$rc"
assert_contains "H-140: an unstamped run folder is not a last run" "$out" "there is no last run"
assert_eq "H-140: the unstamped run folder is left byte-identical" "$before" "$(tree_sum "$old")"
rm -rf "$(draft_of "$out")"

# ---- Usage ---------------------------------------------------------------------------------
: > "$base/empty.txt"
assert_exit "H-140: an empty description is refused (exit 64)" 64 "$h" feedback preview "$base/empty.txt"
assert_exit "H-140: a missing description file is refused (exit 74)" 74 "$h" feedback preview "$base/nope.txt"
assert_exit "H-140: send with no draft folder is refused (exit 66)" 66 "$h" feedback send --draft "$base/nope" --code 0 --yes
assert_contains "H-140: the help lists the feedback verb" "$("$h" help)" "feedback"

# ---- The command file shows first and sends only after a yes --------------------------------
cmd="$HO_PLUGIN_ROOT/commands/feedback.md"
assert_eq "H-140: the /harness:feedback command file exists" "yes" "$([ -f "$cmd" ] && echo yes || echo no)"
assert_contains "H-140: the command builds a preview first" "$(cat "$cmd")" "feedback preview"
assert_contains "H-140: the command passes --yes only after a yes" "$(cat "$cmd")" "Pass \`--yes\` only after the person said yes"
assert_eq "H-140: the final number of issues is two (one per yes)" "2" "$(creates)"
