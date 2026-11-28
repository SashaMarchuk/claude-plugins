# Local ticket names (H-017; wave-1 follow-ups #88): a skipped name is counted on stderr, a
# dangling link still takes its id, one id on two files is warned about and listed once, a
# relative ticket folder that starts with a tab still lists, and the name check holds in a
# UTF-8 locale too (the runner itself uses LANG=C).
h="$HO_PLUGIN_ROOT/bin/harness"
printf '## Outcome\nx\n\n## Scope\ny\n\n## Acceptance criteria\nz\n' > body.md
export HO_TICKETS_DIR="$PWD/q/tickets"
"$h" tickets add "One" body.md >/dev/null
"$h" tickets add "Two" body.md >/dev/null

# ---- a name with a space or a non-ASCII letter is skipped, and counted ----
cp "$HO_TICKETS_DIR/1-one.md" "$HO_TICKETS_DIR/5-a b.md"
cp "$HO_TICKETS_DIR/1-one.md" "$HO_TICKETS_DIR/6-$(printf '\303\251').md"
out=$("$h" tickets ids 2>"$PWD/err")
assert_eq "H-017: names with a space or a non-ASCII letter are not tickets" "1 2" "$(printf '%s\n' "$out" | tr '\n' ' ' | sed 's/ $//')"
assert_contains "H-017 (#88): ids prints one stderr line with the count of skipped files" "$(cat "$PWD/err")" "2 file(s)"
assert_eq "H-017 (#88): that is one line" 1 "$(grep -c . "$PWD/err")"
out=$(LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 "$h" tickets ids 2>/dev/null)
assert_eq "H-017 (#88): in a UTF-8 locale a non-ASCII name is still no ticket" "1 2" "$(printf '%s\n' "$out" | tr '\n' ' ' | sed 's/ $//')"
rm -f "$HO_TICKETS_DIR/5-a b.md" "$HO_TICKETS_DIR"/6-*.md

# ---- a dangling link takes its id ----
ln -s "$PWD/nowhere.md" "$HO_TICKETS_DIR/7-gone.md"
o=$("$h" tickets add "After the link" body.md)
assert_contains "H-017 (#88): a dangling link N-x.md counts for the next id" "$o" "created ticket 8 "
rm -f "$HO_TICKETS_DIR/7-gone.md"

# ---- one id on two files ----
cp "$HO_TICKETS_DIR/2-two.md" "$HO_TICKETS_DIR/02-copy.md"
out=$("$h" tickets ids 2>"$PWD/err")
assert_eq "H-017 (#88): an id on two files is listed once" "1 2 8" "$(printf '%s\n' "$out" | tr '\n' ' ' | sed 's/ $//')"
assert_contains "H-017 (#88): the second file of one id is warned about" "$(cat "$PWD/err")" "id 2"
rm -f "$HO_TICKETS_DIR/02-copy.md"

# ---- a relative ticket folder that starts with a tab ----
tdir="$(printf '\t')tabbed"
mkdir -p "$PWD/$tdir"
HO_TICKETS_DIR="$tdir" "$h" tickets add "Tabbed" body.md >/dev/null
assert_eq "H-017 (#88): a relative folder that starts with a tab lists its tickets" 1 "$(HO_TICKETS_DIR="$tdir" "$h" tickets ids 2>/dev/null)"
assert_contains "H-017 (#88): list shows it too" "$(HO_TICKETS_DIR="$tdir" "$h" tickets list 2>/dev/null)" "Tabbed"
