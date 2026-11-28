# The test runner runs against a chosen jq (issue #117): HO_TEST_JQ names the jq binary, the
# scrubbed run finds exactly that jq first on PATH, and a bad value stops the runner instead of
# falling back to another jq. A copy of run.sh runs in a scratch tree with one probe test file.
base=$(cd -P "$PWD" && pwd)
tree="$base/tree/tests"
mkdir -p "$tree/fake-bin" "$base/jqs"
cp "$HO_TESTS_DIR/run.sh" "$HO_TESTS_DIR/lib.sh" "$tree/"
probe_out="$base/probe.txt"
# The probe records which jq the scrubbed run sees and passes one assertion. The scrubbed run
# keeps no caller variable, so the probe's output path is written into the probe itself.
printf 'jq --version > "%s"\nok "probe ran"\n' "$probe_out" > "$tree/t_probe.sh"
real_jq=$(command -v jq)
printf '#!/bin/sh\n[ "$1" = --version ] && { echo jq-chosen-9.9; exit 0; }\nexec "%s" "$@"\n' "$real_jq" > "$base/jqs/jq-chosen"
chmod +x "$base/jqs/jq-chosen"
printf '#!/bin/sh\nexit 3\n' > "$base/jqs/jq-broken"
chmod +x "$base/jqs/jq-broken"
# runner [VAR=VALUE...]: the copy of run.sh from a fresh, unscrubbed start.
runner() { env -u HO_TEST_SCRUBBED "$@" bash "$tree/run.sh" 2>&1; }

rm -f "$probe_out"; rc=0; out=$(runner HO_TEST_JQ="$base/jqs/jq-chosen") || rc=$?
assert_eq "Issue #117: the runner passes with a chosen jq (exit 0)" 0 "$rc"
assert_eq "Issue #117: the tests see the chosen jq first on PATH" "jq-chosen-9.9" "$(cat "$probe_out" 2>/dev/null)"
assert_contains "Issue #117: the runner names the jq it runs against" "$out" "jq: jq-chosen-9.9"
assert_eq "Issue #117: the summary stays the last line" "harness tests: PASS=1  FAIL=0" "$(printf '%s\n' "$out" | tail -1)"

rm -f "$probe_out"; rc=0; out=$(runner HO_TEST_JQ="$base/jqs/no-such-jq") || rc=$?
assert_eq "Issue #117: a missing chosen jq stops the runner (exit 1)" 1 "$rc"
assert_eq "Issue #117: a missing chosen jq runs no test" no "$([ -e "$probe_out" ] && echo yes || echo no)"
assert_contains "Issue #117: a missing chosen jq is named" "$out" "HO_TEST_JQ"

rm -f "$probe_out"; rc=0; out=$(runner HO_TEST_JQ="$base/jqs/jq-broken") || rc=$?
assert_eq "Issue #117: a chosen jq that does not answer --version stops the runner" 1 "$rc"
assert_eq "Issue #117: a broken chosen jq runs no test" no "$([ -e "$probe_out" ] && echo yes || echo no)"

rm -f "$probe_out"; rc=0; out=$(runner HO_TEST_JQ=jq) || rc=$?
assert_eq "Issue #117: a chosen jq must be an absolute path" 1 "$rc"

# Without HO_TEST_JQ the first jq on PATH is used, as before.
rm -f "$probe_out"; rc=0; out=$(runner) || rc=$?
assert_eq "Issue #117: without a chosen jq the runner still passes" 0 "$rc"
assert_eq "Issue #117: without a chosen jq the tests see the first jq on PATH" "$(jq --version)" "$(cat "$probe_out" 2>/dev/null)"
