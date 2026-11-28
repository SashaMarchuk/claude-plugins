# D8 (H-012, H-015): ticket structure is not required. A free-form ready ticket is created with a
# note, never refused; only an empty body cannot be ready.
h="$HO_PLUGIN_ROOT/bin/harness"
export HO_TICKETS_DIR="$PWD/tickets"
printf 'Make the report page export CSV; done when the export test passes.\n' > free.md
rc=0; err=$("$h" tickets add "Free form" free.md 2>&1 >/dev/null) || rc=$?
assert_eq "D8 a free-form ready ticket is created" "0" "$rc"
assert_contains "D8 the missing headings are only a note" "$err" "does not block (D8)"
assert_eq "D8 the free-form ticket is ready" "1" "$("$h" tickets ids ready)"
"$h" tickets claim 1 >/dev/null
assert_exit "D8 a free-form ticket can be released back to ready" 0 "$h" tickets release 1
: > empty.md
assert_exit "an empty body still cannot be ready" 65 "$h" tickets add "Empty" empty.md
