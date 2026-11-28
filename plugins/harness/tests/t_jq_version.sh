# The lowest supported jq is 1.7 (issue #117): the entry point refuses an older jq with one clear
# message that names the found version and the minimum (exit 78), before any verb runs. help
# works with any jq. Fake jq binaries report the version; every other call goes to the real jq.
h="$HO_PLUGIN_ROOT/bin/harness"
base=$(cd -P "$PWD" && pwd)
real_jq=$(command -v jq)
fakejq() { # <name> <version line>: a folder whose jq prints that version
  mkdir -p "$base/$1"
  printf '#!/bin/sh\n[ "$1" = --version ] && { echo "%s"; exit 0; }\nexec "%s" "$@"\n' "$2" "$real_jq" > "$base/$1/jq"
  chmod +x "$base/$1/jq"
}
fakejq j16 jq-1.6
fakejq j15 jq-1.5rc2
fakejq j171 jq-1.7.1-apple
fakejq j182 jq-1.8.2
fakejq j110 jq-1.10.0
fakejq jdev jq-master-abc123
for d in j16 j15; do
  rc=0; err=$(PATH="$base/$d:$PATH" "$h" tickets help 2>&1 >/dev/null) || rc=$?
  assert_eq "Issue #117: an older jq ($d) is refused with the config-error code (78)" 78 "$rc"
  assert_contains "Issue #117: the refusal names the found version ($d)" "$err" "$(PATH="$base/$d:$PATH" jq --version)"
  assert_contains "Issue #117: the refusal names the minimum ($d)" "$err" "1.7"
done
assert_eq "Issue #117: the refusal is one line" 1 "$(PATH="$base/j16:$PATH" "$h" tickets help 2>&1 >/dev/null | grep -c .)"
for d in j171 j182 j110 jdev; do
  assert_exit "Issue #117: jq $d is accepted" 0 env PATH="$base/$d:$PATH" "$h" tickets help
done
assert_exit "Issue #117: help works with an older jq" 0 env PATH="$base/j16:$PATH" "$h" help
