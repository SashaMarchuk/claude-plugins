# Config lookup edges (design Rebuild reuse list; wave-1 follow-ups #88): the text "null" is a
# value, not a missing one; "config get" takes a plain key only, never a jq program; --int
# refuses numbers too long for 64 bits.
h="$HO_PLUGIN_ROOT/bin/harness"
proj="$PWD/proj"
user="$PWD/user"
mkdir -p "$proj/.harness" "$user"
export HO_USER_DIR="$user" HO_PROJECT_DIR="$proj"
printf '%s\n' '{"schemaVersion":2,"word":"null","big":123456789012345678901,"n":42}' > "$proj/.harness/config.json"
printf '%s\n' '{"schemaVersion":2,"word":"user"}' > "$user/config.json"

assert_eq "Rebuild reuse config (#88): a project value that is the text null is used, not skipped" null "$("$h" config get .word default)"
rc=0; out=$("$h" config get '$ENV.HOME' x 2>"$PWD/err") || rc=$?
assert_eq "Rebuild reuse config (#88): a key that is a jq program is refused (64)" "64:" "$rc:$out"
rc=0; "$h" config get '.n | . + 1' x >/dev/null 2>&1 || rc=$?
assert_eq "Rebuild reuse config (#88): a key with a pipe is refused (64)" 64 "$rc"
assert_eq "Rebuild reuse config: a plain nested key still works" 42 "$("$h" config get .n x)"
out=$("$h" config get --int .big 7 2>"$PWD/err")
assert_eq "Rebuild reuse config (#88): --int with a number above 64 bits uses the default" 7 "$out"
assert_contains "Rebuild reuse config (#88): and says so" "$(cat "$PWD/err")" "not a non-negative integer"
assert_eq "Rebuild reuse config: --int reads a normal number" 42 "$("$h" config get --int .n 7)"
