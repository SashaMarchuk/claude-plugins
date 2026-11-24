# Design Rebuild "separate state": own variable names, one entry script,
# tests in temp folders against a fake claude; never reads 0.6.0 variables.
h="$HO_PLUGIN_ROOT/bin/harness"

assert_eq "Rebuild isolation: selftest passes in the scrubbed runner" "ISOLATION OK" "$("$h" selftest 2>&1)"
assert_eq "Rebuild isolation: runner environment has no HARNESS_ variable" "" "$(env | grep '^HARNESS_' || true)"

. "$HO_PLUGIN_ROOT/lib/isolation.sh"
for v in $HO_OLD_VARS HARNESS_SOMETHING_NEW; do
  rc=0; out=$(env "$v=/tmp/x" "$h" selftest 2>&1) || rc=$?
  assert_eq "Rebuild isolation: selftest exits 65 with $v set" "65" "$rc"
  assert_contains "Rebuild isolation: selftest names $v" "$out" "ISOLATION FAIL: old variable $v"
done

mkdir old-bin
for sname in $HO_OLD_SCRIPTS; do
  rm -f old-bin/*
  printf '#!/bin/sh\nexit 0\n' > "old-bin/$sname"
  chmod +x "old-bin/$sname"
  rc=0; out=$(PATH="$PWD/old-bin:$PATH" "$h" selftest 2>&1) || rc=$?
  assert_eq "Rebuild isolation: selftest exits 65 with old $sname on PATH" "65" "$rc"
  assert_contains "Rebuild isolation: selftest names old $sname" "$out" "ISOLATION FAIL: old script $sname"
done

# An empty PATH component means the current folder (found by Codex review on PR #86).
mkdir cwd-old && printf '#!/bin/sh\nexit 0\n' > cwd-old/harness-run.sh && chmod +x cwd-old/harness-run.sh
for where in trailing leading middle; do
  case $where in
    trailing) p="$PATH:" ;;
    leading) p=":$PATH" ;;
    middle) p=$(printf '%s' "$PATH" | sed 's/:/::/') ;;
  esac
  rc=0; out=$(cd cwd-old && PATH="$p" "$h" selftest 2>&1) || rc=$?
  assert_eq "Rebuild isolation: a $where empty PATH component counts as the current folder" "65" "$rc"
done

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

hits=$(cd "$HO_PLUGIN_ROOT" && grep -rlE 'HARNESS_[A-Z_]+' bin lib | grep -v '^lib/isolation.sh$' || true)
assert_eq "Rebuild isolation: only lib/isolation.sh names old variables in bin/ and lib/" "" "$hits"

syntax=""
for f in "$HO_PLUGIN_ROOT"/bin/* "$HO_PLUGIN_ROOT"/lib/*.sh "$HO_PLUGIN_ROOT"/tests/*.sh "$HO_PLUGIN_ROOT"/tests/fake-bin/*; do
  [ -f "$f" ] || continue
  bash -n "$f" 2>/dev/null || syntax="$syntax ${f#"$HO_PLUGIN_ROOT"/}"
done
assert_eq "Rebuild isolation: bash -n passes on every script" "" "$syntax"
