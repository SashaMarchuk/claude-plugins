# Design Rebuild reuse list: config lookup (project, then user, then default),
# schemaVersion 2 config templates; D28a reuses the same lookup order.
h="$HO_PLUGIN_ROOT/bin/harness"

proj="$PWD/proj"
user="$PWD/user"
mkdir -p "$proj/.harness" "$proj/sub/deeper" "$user"
export HO_USER_DIR="$user"

printf '%s\n' '{"schemaVersion":2,"a":{"x":"project"},"zero":0,"off":false,"nul":null}' > "$proj/.harness/config.json"
printf '%s\n' '{"schemaVersion":2,"a":{"x":"user","y":"user"},"zero":5,"off":true,"nul":"user"}' > "$user/config.json"

get() { (cd "$proj/sub/deeper" && "$h" config get "$@"); }

assert_eq "Rebuild reuse config: a project value beats a user value" "project" "$(get .a.x default)"
assert_eq "Rebuild reuse config: a user value beats the default" "user" "$(get .a.y default)"
assert_eq "Rebuild reuse config: the default is used when no file has the key" "default" "$(get .a.z default)"
assert_eq "Rebuild reuse config: a project 0 is honoured, not overridden" "0" "$(get .zero 9)"
assert_eq "Rebuild reuse config: a project false is honoured, not overridden" "false" "$(get .off true)"
assert_eq "Rebuild reuse config: a project null falls through to the user value" "user" "$(get .nul default)"
assert_eq "Rebuild reuse config: the project is found by walking up from a subfolder" "project" "$(get .a.x default)"
assert_eq "Rebuild reuse config: HO_PROJECT_DIR names the project from anywhere" "project" "$(HO_PROJECT_DIR="$proj" "$h" config get .a.x default)"
assert_eq "Rebuild reuse config: with no project, the user value wins over the default" "user" "$(cd "$PWD" && "$h" config get .a.x default)"
assert_eq "Rebuild reuse config: with no project and no user file, the default is used" "default" "$(HO_USER_DIR="$PWD/none" "$h" config get .a.x default)"

# D28a: limit thresholds use the same order (project, then user, then default).
printf '%s\n' '{"schemaVersion":2,"limits":{"pause_at":70}}' > "$user/config.json"
assert_eq "D28a: a user threshold beats the shipped default" "70" "$(get .limits.pause_at 90)"
printf '%s\n' '{"schemaVersion":2,"limits":{"pause_at":50}}' > "$proj/.harness/config.json"
assert_eq "D28a: a project threshold beats the user threshold" "50" "$(get .limits.pause_at 90)"

# Integer reads: plain non-negative integers only, base 10.
printf '%s\n' '{"schemaVersion":2,"n":"08","bad":"20m","neg":-1}' > "$proj/.harness/config.json"
assert_eq "Rebuild reuse config: an integer with a leading zero reads as base 10" "8" "$(get --int .n 3)"
assert_eq "Rebuild reuse config: a non-integer value falls back to the default" "3" "$(get --int .bad 3 2>/dev/null)"
assert_contains "Rebuild reuse config: a non-integer value is reported" "$(get --int .bad 3 2>&1 >/dev/null)" ".bad"
assert_eq "Rebuild reuse config: a negative value falls back to the default" "3" "$(get --int .neg 3 2>/dev/null)"

# schemaVersion 2 is required in every config file that exists.
for body in '{"schemaVersion":1,"a":1}' '{"a":1}' '{"schemaVersion":"2","a":1}'; do
  printf '%s\n' "$body" > "$proj/.harness/config.json"
  rc=0; err=$(get .a d 2>&1 >/dev/null) || rc=$?
  assert_eq "Rebuild reuse config: project config $body is refused (exit 78)" "78" "$rc"
  assert_contains "Rebuild reuse config: the refusal of $body names the file" "$err" "$proj/.harness/config.json"
  assert_contains "Rebuild reuse config: the refusal of $body asks for schemaVersion 2" "$err" "schemaVersion 2"
done
printf 'not json{' > "$proj/.harness/config.json"
rc=0; err=$(get .a d 2>&1 >/dev/null) || rc=$?
assert_eq "Rebuild reuse config: an unreadable project config is refused, not skipped" "78" "$rc"
assert_contains "Rebuild reuse config: the unreadable refusal names the file" "$err" "$proj/.harness/config.json"

printf '%s\n' '{"schemaVersion":2}' > "$proj/.harness/config.json"
printf '%s\n' '{"schemaVersion":1,"a":1}' > "$user/config.json"
rc=0; err=$(get .a d 2>&1 >/dev/null) || rc=$?
assert_eq "Rebuild reuse config: a schema 1 user config is refused even when the project file lacks the key" "78" "$rc"
assert_contains "Rebuild reuse config: the user refusal names the file" "$err" "$user/config.json"
rc=0; (cd "$proj" && "$h" config check) >/dev/null 2>&1 || rc=$?
assert_eq "Rebuild reuse config: config check fails on a schema 1 user config" "78" "$rc"
printf '%s\n' '{"schemaVersion":2}' > "$user/config.json"
assert_exit "Rebuild reuse config: config check passes when both files are schema 2" 0 env HO_PROJECT_DIR="$proj" "$h" config check

# Shipped templates are schema 2 and pass the engine's own check.
for t in project-config.example.json user-config.example.json; do
  assert_eq "Rebuild reuse templates: $t has schemaVersion 2" "2" "$(jq -r .schemaVersion "$HO_PLUGIN_ROOT/templates/$t")"
done
mkdir -p tproj/.harness tuser
cp "$HO_PLUGIN_ROOT/templates/project-config.example.json" tproj/.harness/config.json
cp "$HO_PLUGIN_ROOT/templates/user-config.example.json" tuser/config.json
assert_exit "Rebuild reuse templates: both templates pass config check" 0 env HO_PROJECT_DIR="$PWD/tproj" HO_USER_DIR="$PWD/tuser" "$h" config check

# A worktree outside the project finds it through a .harness-project pointer file.
printf '%s\n' '{"schemaVersion":2,"a":{"x":"project"}}' > "$proj/.harness/config.json"
mkdir -p lane-wt/deep
printf '%s\n' "$proj" > lane-wt/.harness-project
assert_eq "Rebuild reuse config: a .harness-project pointer leads a worktree to the project" "project" "$(cd lane-wt/deep && "$h" config get .a.x default)"
printf '%s\n' "$PWD/nowhere" > lane-wt/.harness-project
assert_eq "Rebuild reuse config: a pointer to a folder without config is not a project" "default" "$(cd lane-wt/deep && "$h" config get .a.x default 2>/dev/null)"

# HO_PROJECT_DIR naming a folder without config is refused the same way by get and check.
mkdir empty-proj
rc=0; HO_PROJECT_DIR="$PWD/empty-proj" "$h" config get .a d >/dev/null 2>&1 || rc=$?
assert_eq "Rebuild reuse config: get refuses an HO_PROJECT_DIR without config (exit 78)" "78" "$rc"
rc=0; HO_PROJECT_DIR="$PWD/empty-proj" "$h" config check >/dev/null 2>&1 || rc=$?
assert_eq "Rebuild reuse config: check refuses an HO_PROJECT_DIR without config (exit 78)" "78" "$rc"

# config get without a key is a usage error (PR #87 review).
for form in "get" "get --int"; do
  rc=0
  # shellcheck disable=SC2086
  err=$("$h" config $form 2>&1 >/dev/null) || rc=$?
  assert_eq "Rebuild reuse config: 'config $form' with no key exits 64" "64" "$rc"
  assert_contains "Rebuild reuse config: 'config $form' with no key prints usage" "$err" "usage: harness config get"
done
