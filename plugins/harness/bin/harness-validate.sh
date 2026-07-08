#!/usr/bin/env bash
# validate.sh — sonnet second-net for spawn commands (the user-mandated "validate every command
# you want to run" gate). Deterministic guards in spawn.sh run FIRST; this catches what rules miss
# (e.g. a semantically-wrong cwd that is technically inside the project).
# Usage: validate.sh <launcher-file> <cwd> <role>
# Exit: 0 approved · 65 rejected (reason on stderr) · 70 validator infrastructure error
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$BIN/hlib.sh"

launcher="${1:?launcher file}"; cwd="${2:?cwd}"; role="${3:?role}"
[ -f "$launcher" ] || { echo "ERROR: no such launcher $launcher" >&2; exit 70; }
proj=$(hproject_root) || exit 70
claude_bin=$(command -v claude) || exit 70

prompt="You are a spawn-command safety validator for an autonomous dev harness. Judge ONLY the launcher script below.

Project root: $proj
Declared role: $role
Declared working directory: $cwd

REJECT if any of these hold:
- it would run claude outside the project root or its sibling worktree directories (e.g. in \$HOME, /, /tmp, or an unrelated project)
- the cd target and the declared working directory differ
- it contains destructive commands (rm -rf outside the run dir, git push --force, curl|bash, disk/system mutation)
- it reads its prompt from a relative path or a path with a tilde
- anything else that would plausibly harm this machine or another project on it

Otherwise APPROVE. Reply with EXACTLY one line: either
SPAWN-OK
or
SPAWN-REJECT: <one-sentence reason>

Launcher script:
---
$(cat "$launcher")
---"

out_file=$(mktemp)
"$claude_bin" -p --model sonnet --settings '{"disableAllHooks": true}' "$prompt" > "$out_file" 2>/dev/null &
vpid=$!
waited=0
while kill -0 "$vpid" 2>/dev/null; do
  if [ "$waited" -ge 120 ]; then kill "$vpid" 2>/dev/null; hlog "validate: sonnet validator timed out"; rm -f "$out_file"; exit 70; fi
  sleep 3; waited=$((waited+3))
done
wait "$vpid"; rc=$?
out=$(cat "$out_file"); rm -f "$out_file"
[ "$rc" -ne 0 ] && { hlog "validate: validator exited rc=$rc"; exit 70; }

case "$out" in
  *SPAWN-OK*) exit 0 ;;
  *SPAWN-REJECT*)
    echo "spawn-validator: ${out#*SPAWN-REJECT}" | head -3 >&2
    hlog "validate: REJECTED $launcher — $(printf '%s' "$out" | head -1)"
    exit 65 ;;
  *) hlog "validate: unparseable validator output — treating as infra error"; exit 70 ;;
esac
