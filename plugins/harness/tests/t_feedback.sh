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
# The send gate is a second check: a changed draft with a fresh code still may not carry a path.
printf 'see %s/notes.txt\n' "$proj" >> "$d/body.md"
cat "$d/title.txt" "$d/body.md" > "$base/all.txt"
rc=0; err=$("$h" feedback send --draft "$d" --code "$(sha16 "$base/all.txt")" --yes 2>&1) || rc=$?
assert_eq "H-140 / D43: send refuses a draft that holds a path outside the plugin (exit 65)" "65" "$rc"
assert_contains "H-140 / D43: the refusal names the kind, not the text" "$err" "a path outside the plugin"
case $err in *"$proj"*) bad "H-140 / D43: the refusal does not print the path" "it did" ;; *) ok "H-140 / D43: the refusal does not print the path" ;; esac
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
# One private shape per line: the line rule removes a whole line, so a second shape on the
# same line would hide a missed rule.
{
  printf 'It hangs. My notes are in %s/notes.md\n' "$proj"
  printf 'and in %s/private.txt.\n' "$HOME"
  printf 'The plugin script %s/lib/run.sh looks wrong.\n' "$HO_PLUGIN_ROOT"
  for t in $tokens; do printf 'Token: %s\n' "$t"; done
  printf 'Mail me at canary@example.com\n'
  printf 'password=hunter2secret\n'
  printf 'I am canaryacct.\n'
} > "$base/d2.txt"
cat >> "$base/d2.txt" <<'EOF'
DB_PASSWORD=canarypw1
client_secret=canarysec2
GITHUB_TOKEN=canarytok3
"api_key": "canarykey4"
blob wJalrXUtnFEMI/K7MDENG/bPxRfiCYcanaryKEYabcd end
cc -I/home/canary/include
see ../../canary/notes.txt
echo hi >/tmp/canary/out.log
open file:///Users/canary/x.html
/home/bob/My canary Acme/file.txt then words
I am Canaryacct,
also CANARYACCT.
EOF
printf '/harness:run hangs after /harness:status; see https://github.com/acme/tools/issues/12345/comments-and-a-long-tail.\n' >> "$base/d2.txt"
rc=0; out=$(cd "$proj" && "$h" feedback preview "$base/d2.txt") || rc=$?
assert_eq "H-140 private: preview exits 0" "0" "$rc"
d=$(draft_of "$out")
rc=0; "$h" feedback send --draft "$d" --code "$(code_of "$out")" --yes >/dev/null || rc=$?
assert_eq "H-140 private: the cleaned draft is sent after a yes" "0" "$rc"
n=$(creates)
stored=$(jq -r '.title, .body' "$HO_FAKE_GH_DIR/issues/$n.json")
shown=$(printf '%s\n' "$out" | sed '/^DRAFT /,$d')
for where in shown stored; do
  txt=${!where}
  leaks=""
  for canary in CANARY Canary canary hunter2secret "$proj" "$HOME" "$base" $tokens; do
    case $txt in *"$canary"*) leaks="$leaks [$canary]" ;; esac
  done
  case $txt in *"$(id -un)"*) [ ${#USER} -ge 3 ] && leaks="$leaks [the login name]" ;; esac
  assert_eq "H-140 / D43 private: the $where text holds no ticket text, path outside the plugin, token or account name" "" "$leaks"
done
assert_contains "H-140 / D43: a path inside the plugin is written relative to the plugin root" "$stored" "plugin-root/lib/run.sh"
assert_contains "H-140: slash commands and a web link in the description reach the issue" "$stored" \
  "/harness:run hangs after /harness:status; see https://github.com/acme/tools/issues/12345/comments-and-a-long-tail."
assert_contains "H-140 / D43 line rule: a line with a path is replaced whole by a placeholder" "$stored" \
  "$(printf '[line removed: path]\n[line removed: path]\nThe plugin script')"
assert_contains "H-140 / D43 line rule: a line with a secret value is replaced whole" "$stored" \
  "$(printf '[line removed: account]\n[line removed: secret]\n[line removed: account]\n[line removed: secret]')"
# Any "/x/y" left after web links and plugin-root paths are taken out is a path that leaked,
# wherever it starts (after a letter, ":" or "/" too).
no_abs_paths() {
  printf '%s\n' "$1" | sed -E 's#https?://[^[:space:]]+##g; s#plugin-root(/[^[:space:]]*)?##g' |
    grep -cE '(/[^/[:space:]]+/[^/[:space:]]|~/)' || true
}
assert_eq "H-140 / D43: no absolute path of two parts or ~ path reaches the issue body" "0" \
  "$(no_abs_paths "$(jq -r .body "$HO_FAKE_GH_DIR/issues/$n.json")")"
assert_contains "D43 summary: the run state is reported" "$stored" "- Last run: not stopped,"
assert_contains "D43 summary: step names are the fixed role names, others counted as other" "$stored" \
  "- Steps (session roles launched): other 1, worker 1"
assert_contains "D43 summary: engine error codes are event kinds with counts" "$stored" "owner-action x1, session-close-failed x1, unreadable x1"
assert_contains "D43 summary: ticket counts per state" "$stored" "- Tickets per state: ready 0, in-progress 0, blocked 1, needs-review 0, done 0"
assert_eq "H-140: the preview leaves the run folder byte-identical" "$before" "$(tree_sum "$run")"
unset USER LOGNAME HO_FAKE_GH_USER HO_TICKETS_REPO

# ---- The description rule: one shape per line, checked by its marker ----------------------
# Every fake secret is built by concatenation, so no whole secret sits in this file. Each line
# holds one shape with a marker word; the check is that the marker does not reach the text.
v_stripe="sk""_live_""ZedStripeLiveMark""4eC39Hq"
v_stripe_t="sk""_test_""ZedStripeTestMark""4eC3"
v_glpat="glp""at-""ZedGitlabMark""x1y2z3w4v5u6"
v_hf="h""f_""ZedHuggingMark""abcdefgh12345678"
v_tg="1234""56789:""AAH""ZedTelegramMark""abcdefghijklmnopq"
v_ya29="ya""29.""a0ZedGoogleMark""AfH6SMBx1yZ2wV3uT4sR5qP6oN7mL8kJ9i"
v_sg="S""G.""ZedSendgridHeadMark1""."
v_sg="${v_sg}ZedSendgridTailMark""abcdefghijklmnopqrstuvwx12345"
v_hook="https://hooks.slack.com/services/""T0ZedSlackTeam/B0ZedSlackBot/""ZedSlackHookMark""XXXXXXXX"
v_hex="dead""beefcafebabe""0123456789abcdef"
v_basic="ZedBasicMark""dXNlcjpwYXNzd29yZA=="
v_lower="zedlowertok""9x2k4m7q1w8e5r3t6y0u"
# marker|line. Round 1 shapes (attempt 1 review), then G1 (paths with brackets, commas or
# quotes) and G2 (credential shapes) of the attempt 2 verdict, then the clarified rule.
cat > "$base/shapes.txt" <<EOF
ZedStripeLiveMark|stripe $v_stripe
ZedStripeTestMark|stripe $v_stripe_t
ZedGitlabMark|gitlab $v_glpat
ZedHuggingMark|hf $v_hf
ZedTelegramMark|telegram $v_tg
ZedGoogleMark|google $v_ya29
ZedSendgridTailMark|sendgrid $v_sg
ZedSlackHookMark|webhook $v_hook
deadbeefcafebabe|hex key $v_hex
ZedBasicMark|Authorization: Basic $v_basic
ZedDbPassMark|DB_PASS=ZedDbPassMark
ZedPhraseMark|passphrase=ZedPhraseMark
ZedFlagPwMark|run --password ZedFlagPwMark now
ZedQuoteTwoMark|password="ZedQuoteOneMark ZedQuoteTwoMark words"
ZedRedisPwMark|redis://:ZedRedisPwMark@localhost:6379
ZedPgPassMark|postgres://ZedPgUserMark:ZedPgPassMark!x@db.internal/app
zedhostmark|host:/Projects/zedhostmark/x
zedlinkmark|-L/Projects/zedlinkmark/lib
zedfilemark|file:///Projects/zedfilemark/x.html
zednasmark|share //nas/zednasmark/f
zedtildemark|~/Documents/Zed Corp/zedtildemark.md
Zedspacemark|and /Projects/My Zedspacemark/s.txt
zedquotemark|and "/Applications/Zed App/zedquotemark"
zedsibmark|sibling $HO_PLUGIN_ROOT-private/tickets/zedsibmark.md
zqm.md|archive /srv/ZedClientProject2026Arch/zqm.md
zbm.xlsx|budget /Projects/acme.io/ZedClient2026Q4MigrationPlan/zbm.xlsx
zedcsvmark|temp /var/folders/8c/lgj8t4xj4fg4st79311kj1f40000gn/T/zedtmp.dir/zedcsvmark.csv
zedhexmark|hex /a/$v_hex/zedhexmark.txt
zedplan|G1 ~/Dropbox (Zed Corp)/clients/zedplan.md
zedplan|G1 /Users/x/Dropbox (Zed Corp)/clients/zedplan.md
Zedacme|G1 /srv/x/Client Files (2026)/Zedacme Budget/zedplan.xlsx
Zed Corp|G1 "/Users/x/Documents/Zed Corp (old)/zedplan.md"
zedspec|G1 <project folder>/docs/Zedclient (draft)/zedspec.md
zedsecret|G1 ~/Documents/Zedacme (old)/zedsecret-plan.md
, Inc|G1 /Volumes/Zed, Inc/a/zedf.md
zedpage|G1 /Users/x/other/app/(auth)/login/zedpage.tsx
zedf|G1 /srv/x/[draft]/zedf
zedg|G1 /srv/x/{a}/zedg
zedz|G1 /opt/x/a;y/zedz
zedmine|G1 /mnt/c/Users/x/it's/zedmine.txt
zedunterminated|G2 password="zedunterminated more
zedbracket|G2 password=[zedbracket]
zeduser|G2 https://zeduser:zed/pw@host.example/x
zedwinmark|rule C:\\Users\\Zed Corp\\zedwinmark.txt
zeduncmark|rule \\\\server\\share\\zeduncmark
zedotheruser|rule ~zedotheruser/a/b
zedfolder|rule /My zedfolder/sub/f
zedhomevar|rule \$HOME/zedhomevar/x
zedrootup|rule $HO_PLUGIN_ROOT/../../zedrootup/x
zedcurluser|rule curl -u zedcurluser:pw https://example.com
zedsession|rule Cookie: session=zedsession
zedlowertok|rule $v_lower
zedcurly|rule “/srv/x/Zed Corp/zedcurly.md”
zedvenv|rule #!/srv/x/zedvenv/bin/python
zedamp|rule cd x&&/srv/x/zedamp
zedsmb|rule smb://nas/Zed Corp/zedsmb.md
zedvscode|rule vscode://file/srv/x/zedvscode
zeddrive2|rule C://Users/x/zeddrive2
zedpwd|rule Pwd=zedpwd
zedprojspec|G1 $proj/docs/Zedclient (draft)/zedprojspec.md
EOF
shapes=$(cat "$base/shapes.txt")
printf '%s\n' "$shapes" | cut -d'|' -f2- > "$base/d3.txt"
cat >> "$base/d3.txt" <<'EOF'
keep read/write and and/or
EOF
printf 'the plugin file %s/lib/feedback.sh and %s\n' "$HO_PLUGIN_ROOT" "$HO_PLUGIN_ROOT" >> "$base/d3.txt"
rc=0; out=$(cd "$proj" && "$h" feedback preview "$base/d3.txt") || rc=$?
assert_eq "H-140 rule: a description with every known shape still gives a preview" "0" "$rc"
shown=$(printf '%s\n' "$out" | sed '/^DRAFT /,$d')
while IFS='|' read -r m line; do
  case $shown in
    *"$m"*) bad "H-140 / D43 rule: [$m] of [${line:0:40}] does not reach the shown text" "it does" ;;
    *) ok "H-140 / D43 rule: [$m] of [${line:0:40}] does not reach the shown text" ;;
  esac
done <<< "$shapes"
assert_eq "H-140 / D43 rule: no absolute path of two parts reaches the shown text" "0" "$(no_abs_paths "$shown")"
assert_eq "H-140 / D43 rule: every shape line became one placeholder line" "$(printf '%s\n' "$shapes" | wc -l | tr -d ' ')" \
  "$(printf '%s\n' "$shown" | grep -cE '^\[line removed: (path|secret|account)\]$' || true)"
assert_contains "H-140 rule: a word pair with one slash stays" "$shown" "keep read/write and and/or"
assert_contains "H-140 / D43 rule: a plugin file stays relative to the plugin root" "$shown" "the plugin file plugin-root/lib/feedback.sh and plugin-root"
# Cleaning is a fixed point: the shown description, sent in again, comes out the same.
desc_of() { shown_body "$1" | awk '/^---$/{exit} {print}'; }
desc_of "$out" > "$base/d3b.txt"
rc=0; out2=$(cd "$proj" && "$h" feedback preview "$base/d3b.txt") || rc=$?
assert_eq "H-140 rule: the shown text passes the privacy check when sent in again" "0" "$rc"
assert_eq "H-140 rule: cleaning the shown text again changes nothing" "$(desc_of "$out")" "$(desc_of "$out2")"
rm -rf "$(draft_of "$out")" "$(draft_of "$out2")"

# ---- A realistic report does not get worse (the attempt 2 verdict's over-removal table) ------
cat > "$base/d4.txt" <<'EOF'
The run stopped. I ran bash plugins/harness/tests/run.sh
plugins/harness/tests/t_deliver.sh, line 212
.harness/runs/20261126-163833/state
PASS/FAIL/SKIP was 3/1/0. Roles: orchestrator/worker/validator. It works on macOS/Linux, not on WSL.
harness tests: PASS=1828  FAIL=1
max_tokens=4096
TCP/IP/UDP stack
Ratio 1/2/3
/harness:run hangs after /harness:status
at lib/run.sh:120 in ho_run_open
run 20261126-163833-abc123 on branch harness/feedback-3 at commit b28c2b3
see https://github.com/acme/tools/issues/12345
see https://github.com/ZedOwner42/claude-plugins/issues/92
id 123e4567-e89b-12d3-a456-426614174000
read/write and/or a/b I/O
passed=true passes: 3 bypass: no
tokens: 150000 used, --max-tokens 100, token_count=12
echo hi >/dev/null 2>/dev/stderr
// comment and </details> and +/- and a / b and "/"
EOF
rc=0; out=$(cd "$proj" && "$h" feedback preview "$base/d4.txt") || rc=$?
assert_eq "H-140 realistic report: preview exits 0" "0" "$rc"
shown=$(shown_body "$out")
while IFS= read -r line; do
  if printf '%s\n' "$shown" | grep -qxF -- "$line"; then ok "H-140 realistic report: [${line:0:48}] stays as written"
  else bad "H-140 realistic report: [${line:0:48}] stays as written" "changed"; fi
done < "$base/d4.txt"
rm -rf "$(draft_of "$out")"

# ---- The title cut forms no shape of its own ---------------------------------------------
printf 'The status verb is slow when it runs on a box: harness status >/dev/null took 9 s\n' > "$base/d6.txt"
rc=0; out=$(cd "$proj" && "$h" feedback preview "$base/d6.txt") || rc=$?
assert_eq "H-140 title: a first line cut inside /dev/null still gives a preview (exit 0)" "0" "$rc"
assert_contains "H-140 title: the cut title falls back to the plain title" "$out" "Title: Harness feedback: problem report"
assert_contains "H-140 title: the full line stays in the body" "$out" "harness status >/dev/null took 9 s"
rm -rf "$(draft_of "$out")"

# ---- No false refusal: the plugin's own files as descriptions give a preview ---------------
for f in README.md lib/feedback.jq tests/t_feedback.sh; do
  rc=0; out=$(cd "$proj" && "$h" feedback preview "$HO_PLUGIN_ROOT/$f" 2>&1) || rc=$?
  assert_eq "H-140 rule: [$f] as a description gives a preview (exit 0)" "0" "$rc"
  rm -rf "$(draft_of "$out")"
done

# ---- A short account name does not touch the fixed context ---------------------------------
rc=0; out=$(cd "$proj" && USER=tim LOGNAME=tim "$h" feedback preview "$base/d1.txt") || rc=$?
assert_eq "H-140 account rule: the account name tim still gives a preview (exit 0)" "0" "$rc"
assert_contains "H-140 account rule: with the account tim the runtime line stays" "$out" "- Runtime: claude-code 0.0.0"
assert_contains "H-140 account rule: with the account tim the steps line stays" "$out" "- Steps (session roles launched):"
rm -rf "$(draft_of "$out")"
printf 'Timing is off for timothy.\n' > "$base/d5.txt"
out=$(cd "$proj" && USER=tim LOGNAME=tim "$h" feedback preview "$base/d5.txt")
assert_contains "H-140 account rule: the account name glued to other letters removes the line" "$(shown_body "$out")" "[line removed: account]"
rm -rf "$(draft_of "$out")"

# The send gate on its own: a draft edited after the preview, with a fresh code, is refused.
out=$(cd "$proj" && "$h" feedback preview "$base/d1.txt"); d=$(draft_of "$out")
cp "$d/body.md" "$base/body3.keep"
for shape in "$v_stripe" "$v_tg" "$v_hook" "redis://:ZedRedisPwMark@localhost" "DB_PASS=ZedDbPassMark" \
  "Authorization: Basic $v_basic" "$v_hex" "host:/Projects/zedhostmark/x" "-L/Projects/zedlinkmark/lib" \
  "//nas/zednasmark/f" "$HO_PLUGIN_ROOT-private/tickets/zedsibmark.md" "~/Dropbox (Zed Corp)/x" \
  "password=[zedbracket]" "https://zeduser:zed/pw@host.example/x" "a note in plain words"; do
  # A copy per shape, so a wrongly sent draft cannot take the next check's draft with it.
  rm -rf "$base/gd"; cp -R "$d" "$base/gd"
  printf 'edited %s\n' "$shape" >> "$base/gd/body.md"
  cat "$base/gd/title.txt" "$base/gd/body.md" > "$base/all.txt"
  rc=0; err=$("$h" feedback send --draft "$base/gd" --code "$(sha16 "$base/all.txt")" --yes 2>&1) || rc=$?
  assert_eq "H-140 / D43 gate: the send gate refuses an edited draft with [${shape:0:24}...] (exit 65)" "65" "$rc"
  case $err in
    *"private data ("*) ok "H-140 / D43 gate: the refusal names the kind for [${shape:0:24}...]" ;;
    *) bad "H-140 / D43 gate: the refusal names the kind for [${shape:0:24}...]" "$err" ;;
  esac
done
# An edit above the context block goes through the same line rule.
cp "$base/body3.keep" "$d/body.md"
{ printf 'see ~/Dropbox (Zed Corp)/x\n'; cat "$base/body3.keep"; } > "$d/body.md"
cat "$d/title.txt" "$d/body.md" > "$base/all.txt"
assert_exit "H-140 / D43 gate: a path added to the description part is refused (exit 65)" 65 \
  "$h" feedback send --draft "$d" --code "$(sha16 "$base/all.txt")" --yes
rm -rf "$d"

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
