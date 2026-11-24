# Design Rebuild "one entry script": harness <verb> [args].
h="$HO_PLUGIN_ROOT/bin/harness"

assert_exit "Rebuild entry: help exits 0" 0 "$h" help
assert_contains "Rebuild entry: help lists the selftest verb" "$("$h" help)" "selftest"
assert_exit "Rebuild entry: unknown verb exits 64" 64 "$h" no-such-verb
assert_exit "Rebuild entry: no verb exits 64" 64 "$h"

err=$("$h" no-such-verb 2>&1 >/dev/null || true)
assert_contains "Rebuild entry: unknown verb prints usage on stderr" "$err" "usage: harness <verb>"

ln -s "$h" "$PWD/harness-link"
assert_eq "Rebuild entry: finds its root through a symlink" "$("$h" version)" "$("$PWD/harness-link" version)"
