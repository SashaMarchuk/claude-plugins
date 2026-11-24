# Field note I3 ("OK with nothing done") and the PR #87 review: a failed gh call or file
# step gives a non-zero exit and no OK line; an unreadable ticket file is never rewritten;
# ids are read in base 10 with at most 9 digits.
h="$HO_PLUGIN_ROOT/bin/harness"
printf '## Outcome\nx\n\n## Scope\ny\n\n## Acceptance criteria\nz\n' > body.md
printf 'why\n' > why.md

# assert_fails <name> <args...>: the verb exits non-zero and prints no OK line.
assert_fails() {
  local name=$1 rc=0 out
  shift
  out=$("$h" tickets "$@" 2>/dev/null) || rc=$?
  if [ "$rc" -ne 0 ] && ! printf '%s\n' "$out" | grep -q '^OK'; then ok "$name"
  else bad "$name" "exit $rc, stdout [$out]"; fi
}

# ---- GitHub: a failed gh step fails the verb -------------------------------------
export HO_FAKE_GH_DIR="$PWD/gh" HO_TICKETS_SOURCE=github HO_TICKETS_REPO=fake/repo
ncomments() { jq '.comments | length' "$HO_FAKE_GH_DIR/issues/$1.json"; }
"$h" tickets add "Outage" body.md >/dev/null
"$h" tickets claim 1 >/dev/null
HO_FAKE_GH_FAIL="issue comment" assert_fails "B1 github: block fails when the reason comment is not posted" block 1 why.md
assert_eq "B1 github: no comment was stored" "0" "$(ncomments 1)"
HO_FAKE_GH_FAIL="issue comment" assert_fails "B1 github: comment fails when gh issue comment fails" comment 1 why.md
"$h" tickets add "Ready for claim" body.md >/dev/null
HO_FAKE_GH_FAIL="issue edit" assert_fails "B1 github: claim fails when gh issue edit fails" claim 2
HO_FAKE_GH_FAIL="issue edit" assert_fails "B1 github: review fails when gh issue edit fails" review 1
HO_FAKE_GH_FAIL="issue close" assert_fails "B1 github: done fails when gh issue close fails" "done" 1
HO_FAKE_GH_FAIL="issue create" assert_fails "B1 github: add fails when gh issue create fails" add "Lost" body.md
HO_FAKE_GH_FAIL="label create" assert_fails "B1 github: bootstrap fails when gh label create fails" bootstrap
HO_FAKE_GH_FAIL="issue list" assert_fails "B1 github: ids fails when gh issue list fails" ids
unset HO_TICKETS_SOURCE HO_TICKETS_REPO

# ---- Local: an unreadable ticket file stays byte-identical -----------------------
export HO_TICKETS_DIR="$PWD/unread/tickets"
"$h" tickets add "Keep me" body.md >/dev/null
"$h" tickets comment 1 why.md >/dev/null
f=$(find "$HO_TICKETS_DIR" -name '1-*.md')
before=$(cksum < "$f")
chmod 000 "$f"
for verb in "claim 1" "comment 1 why.md" "block 1 why.md" "review 1" "release 1" "done 1" "show 1"; do
  # shellcheck disable=SC2086
  assert_fails "Unreadable ticket file: '$verb' exits non-zero with no OK" $verb
done
chmod 644 "$f"
assert_eq "Unreadable ticket file: the file stays byte-identical" "$before" "$(cksum < "$f")"
assert_eq "Unreadable ticket file: no temp file stays" "" "$(find "$HO_TICKETS_DIR" -name '.*' -type f)"

# An unreadable comment or reason file is refused before anything is written.
cp why.md secret.md
chmod 000 secret.md
assert_fails "Unreadable body file: comment exits non-zero" comment 1 secret.md
assert_fails "Unreadable body file: block exits non-zero" block 1 secret.md
assert_fails "Unreadable body file: add exits non-zero" add "Hidden" secret.md blocked
chmod 644 secret.md
assert_eq "Unreadable body file: the ticket file stays byte-identical" "$before" "$(cksum < "$f")"
assert_eq "Unreadable body file: add created no ticket" "1" "$(find "$HO_TICKETS_DIR" -name '[0-9]*-*.md' | wc -l | tr -d ' ')"

# ---- Local ids: base 10, at most 9 digits ----------------------------------------
export HO_TICKETS_DIR="$PWD/padded/tickets"
mkdir -p "$HO_TICKETS_DIR"
printf 'title: Padded\nstatus: ready\ncreated: x\n\n' > "$HO_TICKETS_DIR/08-padded.md"
cat body.md >> "$HO_TICKETS_DIR/08-padded.md"
sed 's/Padded/Ten/' "$HO_TICKETS_DIR/08-padded.md" > "$HO_TICKETS_DIR/010-ten.md"
sed 's/Padded/Huge/' "$HO_TICKETS_DIR/08-padded.md" > "$HO_TICKETS_DIR/1234567890-huge.md"
sed 's/Padded/Overflow/' "$HO_TICKETS_DIR/08-padded.md" > "$HO_TICKETS_DIR/99999999999999999999-o.md"
assert_eq "Ids: 08 and 010 are tickets 8 and 10; names over 9 digits are not tickets" "8 10" "$("$h" tickets ids 2>&1 | tr '\n' ' ' | sed 's/ $//')"
assert_contains "Ids: show 8 finds 08-padded.md" "$("$h" tickets show 8 2>&1)" "Title: Padded"
assert_contains "Ids: show 08 is ticket 8" "$("$h" tickets show 08 2>&1)" "### Ticket 8 "
assert_contains "Ids: show 10 finds 010-ten.md" "$("$h" tickets show 10 2>&1)" "Title: Ten"
rc=0; out=$("$h" tickets add "After padded" body.md 2>&1) || rc=$?
assert_eq "Ids: add after 08 and 010 creates ticket 11" "0 OK created ticket 11" "$rc $(printf '%s' "$out" | cut -d' ' -f1-4)"
assert_exit "Ids: an id over 9 digits is refused" 64 "$h" tickets show 1234567890

# ---- The id guard names only the id, never a raw file name ------------------------
mkdir -p guard/tickets
: > 'guard/tickets/1-$(touch pwned)-name.md'
cat > probe.sh <<PROBE
set -euo pipefail
HO_TICKETS_SOURCE=local
HO_TICKETS_DIR="$PWD/guard/tickets"
export HO_TICKETS_SOURCE HO_TICKETS_DIR
. "$HO_PLUGIN_ROOT/lib/tickets.sh"
ho_tk_settings
ho_tk_l_max_id() { echo 0; }   # a stale maximum, as after a bypassed lock
rc=0; ho_tk_locked ho_tk_l_add_locked "Race" "$PWD/body.md" ready || rc=\$?
echo "rc=\$rc"
ho_tk_l_write "$PWD/guard/tickets/1-HOSTILE name.md" false || true
PROBE
err=$(bash probe.sh 2>&1 || true)
assert_contains "Id guard: an id already on disk exits 70" "$err" "rc=70"
assert_contains "Id guard: the error names the id" "$err" "ticket id 1 is already on disk"
case $err in *pwned*|*name.md*|*HOSTILE*) bad "Id guard: the error does not print the file name" "[$err]" ;; *) ok "Id guard: the error does not print the file name" ;; esac
