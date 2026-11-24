# Design Rebuild "separate state": own variable names, one entry script,
# tests in temp folders against a fake claude; never reads 0.6.0 variables.
h="$HO_PLUGIN_ROOT/bin/harness"

assert_eq "Rebuild isolation: selftest passes in the scrubbed runner" "ISOLATION OK" "$("$h" selftest 2>&1)"
assert_eq "Rebuild isolation: runner environment has no HARNESS_ variable" "" "$(env | grep '^HARNESS_' || true)"

rc=0; out=$(HARNESS_PROJECT=/tmp/x "$h" selftest 2>&1) || rc=$?
assert_eq "Rebuild isolation: selftest exits 65 with HARNESS_PROJECT set" "65" "$rc"
assert_contains "Rebuild isolation: selftest names HARNESS_PROJECT" "$out" "ISOLATION FAIL: old variable HARNESS_PROJECT"

rc=0; out=$(HARNESS_USER_DIR=/tmp/x "$h" selftest 2>&1) || rc=$?
assert_eq "Rebuild isolation: selftest exits 65 with HARNESS_USER_DIR set" "65" "$rc"
assert_contains "Rebuild isolation: selftest names HARNESS_USER_DIR" "$out" "ISOLATION FAIL: old variable HARNESS_USER_DIR"

mkdir old-bin
printf '#!/bin/sh\nexit 0\n' > old-bin/harness-run.sh
chmod +x old-bin/harness-run.sh
rc=0; out=$(PATH="$PWD/old-bin:$PATH" "$h" selftest 2>&1) || rc=$?
assert_eq "Rebuild isolation: selftest exits 65 with an old script on PATH" "65" "$rc"
assert_contains "Rebuild isolation: selftest names the old script" "$out" "ISOLATION FAIL: old script harness-run.sh"

assert_eq "Rebuild isolation: claude resolves to the fake" "$HO_PLUGIN_ROOT/tests/fake-bin/claude" "$(command -v claude)"
assert_eq "Rebuild isolation: fake claude --version" "0.0.0 (fake claude)" "$(claude --version)"

tab=$(printf '\t')
HO_FAKE_CLAUDE_LOG="$PWD/claude.log" claude -p "two words" --flag >/dev/null
assert_eq "Rebuild isolation: fake claude records argv tab-separated" "-p${tab}two words${tab}--flag" "$(cat "$PWD/claude.log")"
claude default-log >/dev/null
assert_eq "Rebuild isolation: fake claude logs under the test HOME by default" "default-log" "$(cat "$HOME/fake-claude.log")"
rc=0; out=$(HO_FAKE_CLAUDE_STDOUT="canned" HO_FAKE_CLAUDE_EXIT=3 HO_FAKE_CLAUDE_LOG=/dev/null claude x) || rc=$?
assert_eq "Rebuild isolation: fake claude prints canned stdout" "canned" "$out"
assert_eq "Rebuild isolation: fake claude exits with the set code" "3" "$rc"

hits=$(cd "$HO_PLUGIN_ROOT" && grep -rlE 'HARNESS_PROJECT|HARNESS_USER_DIR|HARNESS_USER_CONFIG' bin lib | grep -v '^lib/isolation.sh$' || true)
assert_eq "Rebuild isolation: only lib/isolation.sh names old variables in bin/ and lib/" "" "$hits"

syntax=""
for f in "$HO_PLUGIN_ROOT"/bin/* "$HO_PLUGIN_ROOT"/lib/*.sh "$HO_PLUGIN_ROOT"/tests/*.sh "$HO_PLUGIN_ROOT"/tests/fake-bin/*; do
  [ -f "$f" ] || continue
  bash -n "$f" 2>/dev/null || syntax="$syntax ${f#"$HO_PLUGIN_ROOT"/}"
done
assert_eq "Rebuild isolation: bash -n passes on every script" "" "$syntax"
