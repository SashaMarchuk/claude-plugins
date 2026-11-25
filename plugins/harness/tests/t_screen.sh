# shellcheck shell=bash
# Screen text: recognition only (H-113 limit notice; H-099 nothing is typed, a dialog is
# reported and a password prompt is never answered, which the design reuse list states;
# H-114 and D28c the STOP-aware wait for the reset).
# Field notes F1 (a match inside a session's own prose) and I2 (screen matching fired on the
# wrong text) are the negative fixtures. PR-5 is "one wait recorded, not one per watch cycle".
# PR-8 is "no resume before the recorded reset time, also while the reading stays unreadable",
# so an unknown reset keeps waiting instead of continuing.
#
# No test prints a fixture, a capture or a ledger value. Every check compares a class word,
# a count or an exit code, so the words a session's screen may hold stay inside the files.
. "$HO_TESTS_DIR/sessions-setup.sh"

fix="$HO_PLUGIN_ROOT/tests/fixtures/screen"
set_cfg() { jq "$2" "$1" > "$base/c.json" && mv "$base/c.json" "$1"; }
set_cfg "$proj/.harness/config.json" '.limits = {"wait_slice_seconds": 1, "resume_margin_seconds": 0, "unknown_hold_seconds": 0}'
trust_root

# cls <fixture>: the class word for one saved fixture file.
cls() { "$h" screen "$run" classify "$fix/$1" 2>/dev/null; }
ledger="$run/ledger.jsonl"
# count <jq-select>: how many ledger lines match.
count() { jq -s --arg k "$1" --arg s "$2" '[.[] | select(.kind == $k and (($s == "") or .shape == $s))] | length' "$ledger"; }

# ---- recognition of the saved fixtures (H-113, acceptance check 1) ---------------------
for f in limit-notice-boxed limit-notice-plain limit-notice-short limit-notice-contraction limit-notice-contraction-typographic; do
  assert_eq "H-113: $f.txt is recognised as the limit notice" "limit" "$(cls "$f.txt")"
done
for f in trust-dialog trust-dialog-after-prose; do
  assert_eq "H-099: $f.txt is recognised as the trust dialog" "trust" "$(cls "$f.txt")"
done
for f in password-prompt password-prompt-sudo; do
  assert_eq "H-099 reuse list: $f.txt is recognised as the prompt the harness never answers" "password" "$(cls "$f.txt")"
done

# ---- a session's own prose never matches (H-113, field notes F1 and I2) ----------------
assert_eq "H-113 (F1): n-prose-quotes-notice.txt does not match" "none" "$(cls n-prose-quotes-notice.txt)"
assert_eq "H-113 (F1): n-prose-wrapped-notice.txt does not match" "none" "$(cls n-prose-wrapped-notice.txt)"
assert_eq "H-113 (F1): n-report-pastes-notice.txt does not match" "none" "$(cls n-report-pastes-notice.txt)"
assert_eq "H-099 (I2): n-report-quotes-dialog.txt does not match" "none" "$(cls n-report-quotes-dialog.txt)"
assert_eq "H-099 (I2): n-prose-mentions-password.txt does not match" "none" "$(cls n-prose-mentions-password.txt)"
assert_eq "H-113 (I2): n-plain-working.txt does not match" "none" "$(cls n-plain-working.txt)"
assert_eq "H-113 (F1): n-report-inside-paragraph.txt does not match" "none" "$(cls n-report-inside-paragraph.txt)"
# A pattern that writes a bracket with a backslash must arrive as those two characters, not
# as a character class: a class would match this short last line.
assert_eq "H-099 (I2): n-prose-short-last-line.txt does not match" "none" "$(cls n-prose-short-last-line.txt)"
# The shape of a notice with the words of a summary: one line, blank above, input line below.
assert_eq "H-113 (F1): n-prose-one-line-summary.txt does not match" "none" "$(cls n-prose-one-line-summary.txt)"
assert_eq "H-113 (F1): n-prose-bare-phrase.txt does not match" "none" "$(cls n-prose-bare-phrase.txt)"
assert_eq "H-113 (F1): n-prose-two-line-summary.txt does not match" "none" "$(cls n-prose-two-line-summary.txt)"
assert_eq "H-113: n-prose-no-reset-line.txt does not match without the reset line" "none" "$(cls n-prose-no-reset-line.txt)"

# ---- unknown is never "nothing found" (field notes I1 and I3) --------------------------
: > "$base/empty.txt"
assert_eq "H-113 (I3): an empty capture reads as unknown" "unknown" "$("$h" screen "$run" classify "$base/empty.txt" 2>/dev/null)"
assert_exit "H-113 (I3): an empty capture exits 66, not 0" 66 "$h" screen "$run" classify "$base/empty.txt"
assert_eq "H-113 (I1): a capture that cannot be read is unknown" "unknown" "$("$h" screen "$run" classify "$base/no-such.txt" 2>/dev/null)"
assert_exit "H-113 (I1): a capture that cannot be read exits 66" 66 "$h" screen "$run" classify "$base/no-such.txt"

# ---- no pattern data at all reads as unknown (field notes I1 and I3) -------------------
mkdir -p "$base/nodata"
cp -R "$HO_PLUGIN_ROOT/bin" "$HO_PLUGIN_ROOT/lib" "$HO_PLUGIN_ROOT/runtimes" "$base/nodata/"
rm -f "$base/nodata/runtimes/claude-code.screen.json"
assert_eq "H-113 (I1): with no pattern file a screen reads as unknown" "unknown" \
  "$("$base/nodata/bin/harness" screen "$run" classify "$fix/limit-notice-boxed.txt" 2>/dev/null)"
assert_exit "H-113 (I1): with no pattern file classify exits 78" 78 \
  "$base/nodata/bin/harness" screen "$run" classify "$fix/limit-notice-boxed.txt"

# ---- the STOP-aware wait (H-114, D28c, PR-8) -------------------------------------------
past=$(( $(date -u '+%s') - 10 ))
assert_exit "H-114: a reset time that has passed ends the wait at once" 0 "$h" screen "$run" wait "$past"
assert_eq "H-114: the wait records one result line" "1" "$(count limit-wait "")"
rc=0; "$h" screen "$run" wait unknown >/dev/null 2>&1 || rc=$?
assert_eq "H-114 (F4): an unknown reset reports unknown (exit 2), never continue" "2" "$rc"
: > "$proj/.harness/STOP"
rc=0; "$h" screen "$run" wait "$(( $(date -u '+%s') + 600 ))" >/dev/null 2>&1 || rc=$?
assert_eq "H-114 (D25b): a STOP ends the wait (exit 75)" "75" "$rc"
rm -f "$proj/.harness/STOP"
"$h" state "$run" resume >/dev/null

# A reset that cannot be an epoch is refused, never read as "reset reached" (PR #97 review).
for v in 0 9999999999999999999 09; do
  assert_exit "H-114 (PR-8): a reset of $v is refused (exit 64)" 64 "$h" screen "$run" wait "$v"
done

# An awk that cannot run the patterns as written reads unknown, loudly (PR #97 review).
mkdir -p "$base/badawk"
printf '#!/bin/sh\nexit 1\n' > "$base/badawk/awk"
chmod 755 "$base/badawk/awk"
rc=0; out=$(PATH="$base/badawk:$PATH" "$h" screen "$run" classify "$fix/limit-notice-boxed.txt" 2>"$base/selftest.err") || rc=$?
assert_eq "H-113 (I1): an awk that fails the self-test reads unknown, not none" "unknown" "$out"
assert_eq "H-113 (I1): an awk that fails the self-test exits 70" "70" "$rc"
assert_eq "H-113 (I1): the self-test failure says why" "1" "$(grep -c 'does not run the screen patterns' "$base/selftest.err" || true)"

# ---- pre-trust: inside the project only (reuse list) -----------------------------------
assert_exit "H-099 reuse list: a folder inside the project is pre-trusted" 0 "$h" screen "$run" pretrust "$proj/src"
assert_eq "H-099 reuse list: the trust record names the folder inside the project" "1" \
  "$(jq --arg p "$(cd "$proj/src" && pwd -P)" '[.projects | to_entries[] | select(.key == $p and .value.hasTrustDialogAccepted == true)] | length' "$HOME/.claude.json")"
outside="$base/outside"
mkdir -p "$outside"
assert_exit "H-099 reuse list: a folder outside the project is refused (exit 65)" 65 "$h" screen "$run" pretrust "$outside"
assert_eq "H-099 reuse list: nothing outside the project reaches the trust record" "0" \
  "$(jq --arg p "$(cd "$outside" && pwd -P)" '[.projects | to_entries[] | select(.key == $p)] | length' "$HOME/.claude.json")"

# ---- a live session: read the screen, act, and type nothing -----------------------------
# The screen is fed by appending a saved fixture to the fake terminal's own output file.
trust_root
launch w1 >/dev/null
hfile="$HO_FAKE_TERM_DIR/$(printf '%s' "$(rec w1 .handle)" | tr -c 'A-Za-z0-9-' '_')"
assert_eq "H-099 reuse list: the launch pre-trusted its own working folder" "1" \
  "$(jq --arg p "$(cd "$proj/src" && pwd -P)" '[.projects | to_entries[] | select(.key == $p and .value.hasTrustDialogAccepted == true)] | length' "$HOME/.claude.json")"
assert_eq "H-099 reuse list: the launch recorded no skipped pre-trust" "0" "$(count pretrust-skipped "")"

assert_exit "H-114 (PR-8): watch --reset with no value prints usage (exit 64)" 64 "$h" screen "$run" watch w1 --reset
assert_exit "H-114 (PR-8): watch --reset 0 is refused (exit 64)" 64 "$h" screen "$run" watch w1 --reset 0

typed_before=$(wc -c < "$hfile.in" | tr -d ' ')
cat "$fix/limit-notice-boxed.txt" >> "$hfile.out"
assert_eq "H-113: the limit notice is recognised on a live session" "limit" "$("$h" screen "$run" watch w1 --reset unknown 2>/dev/null)"
assert_eq "H-114 (PR-5): the limit notice is recorded once" "1" "$(count screen limit)"
assert_eq "H-114 (PR-8): the recorded notice carries the reset the reader gave" "unknown" \
  "$(jq -s -r '[.[] | select(.kind == "screen" and .shape == "limit")] | last | .reset // ""' "$ledger")"
waits_after_first=$(count limit-wait "")
rc=0; "$h" screen "$run" watch w1 --reset unknown >/dev/null 2>&1 || rc=$?
assert_eq "H-114 (PR-8): a second look with an unknown reset waits again, never continue (exit 2)" "2" "$rc"
assert_eq "H-113 (F1): the same screen on a second look adds no second line" "1" "$(count screen limit)"
assert_eq "H-114 (PR-5): the same screen on a second look adds no second result line" "$waits_after_first" "$(count limit-wait "")"
rc=0; "$h" screen "$run" watch w1 --reset "$past" >/dev/null 2>&1 || rc=$?
assert_eq "H-114: a look whose reset time has passed ends the wait (exit 0)" "0" "$rc"
waits_after_reset=$(count limit-wait "")
rc=0; "$h" screen "$run" watch w1 --reset unknown >/dev/null 2>&1 || rc=$?
assert_eq "H-114 (PR-5): once that screen reached its reset, a later look waits no more (exit 0)" "0" "$rc"
assert_eq "H-114 (PR-5): and it adds no further result line" "$waits_after_reset" "$(count limit-wait "")"
assert_eq "H-099: nothing was typed into the session" "$typed_before" "$(wc -c < "$hfile.in" | tr -d ' ')"
assert_eq "H-099: no text was sent to the terminal" "0" "$(grep -c 'send-text' "$HO_FAKE_TERM_DIR/calls.log" || true)"
assert_eq "H-099: no key was sent to the terminal" "0" "$(grep -c 'tmux key' "$HO_FAKE_TERM_DIR/calls.log" || true)"
assert_eq "H-113 (I2): the screen was read on each of the four looks" "4" "$(grep -c 'tmux capture' "$HO_FAKE_TERM_DIR/calls.log" || true)"
assert_eq "H-099 (I4): no screen text reaches the run ledger" "0" "$(grep -c 'HO-SENTINEL-NO-SCREEN-BYTES' "$ledger" || true)"

cat "$fix/password-prompt.txt" >> "$hfile.out"
assert_eq "H-099 reuse list: the prompt is recognised on a live session" "password" "$("$h" screen "$run" watch w1 2>/dev/null)"
assert_eq "H-099 reuse list: the prompt becomes one owner action" "1" "$(count owner-action "")"
assert_eq "H-099 reuse list: the prompt was not answered" "$typed_before" "$(wc -c < "$hfile.in" | tr -d ' ')"

# Only the project's own consent in the trust file, so a regression that trusts the working
# folder on the dialog changes it (the launch above already wrote that folder).
trust_root
trust_cks_before=$(cksum < "$HOME/.claude.json")
cat "$fix/trust-dialog.txt" >> "$hfile.out"
assert_eq "H-099: the trust dialog is recognised on a live session" "trust" "$("$h" screen "$run" watch w1 2>/dev/null)"
assert_eq "H-099: the trust dialog becomes an owner action, never an answer" "2" "$(count owner-action "")"
assert_eq "H-099: a recognised dialog trusts nothing: the trust file is unchanged" "$trust_cks_before" "$(cksum < "$HOME/.claude.json")"
assert_eq "H-099: still nothing typed after three recognised screens" "$typed_before" "$(wc -c < "$hfile.in" | tr -d ' ')"
assert_eq "H-099: still no text or key sent" "0" \
  "$(grep -c 'send-text\|tmux key' "$HO_FAKE_TERM_DIR/calls.log" || true)"

cat "$fix/n-plain-working.txt" >> "$hfile.out"
assert_eq "H-113 (F1): an ordinary working screen needs no action" "none" "$("$h" screen "$run" watch w1 2>/dev/null)"

# ---- a session on its own account: nothing is written to the wrong trust file -----------
mkdir -p "$proj/src2" "$base/acct"
acct_cmd="printf CLAUDE_CONFIG_DIR=$base/acct\\n"
jq --arg c "$acct_cmd" '.accounts.roles.default = "a1" | .accounts.list.a1.env_command = $c' \
  "$user/config.json" > "$base/u.json" && mv "$base/u.json" "$user/config.json"
launch w2 --cwd "$proj/src2" >/dev/null
assert_eq "H-099 (D37-SESSIONS-5): a session with its own account records a skipped pre-trust" "1" "$(count pretrust-skipped "")"
assert_eq "H-099 (D37-SESSIONS-5): nothing was written for that folder in this account's place" "0" \
  "$(jq --arg p "$(cd "$proj/src2" && pwd -P)" '[.projects // {} | to_entries[] | select(.key == $p)] | length' "$HOME/.claude.json")"
