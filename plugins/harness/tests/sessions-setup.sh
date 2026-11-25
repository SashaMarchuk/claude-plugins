# shellcheck shell=bash
# Shared setup for the session tests (sourced by t_sessions_*.sh; not a test file).
# A project with a tmux-fake terminal, a worker cap high enough for every session a test starts, the fake claude held open until it reads "/exit",
# short timeouts, and one stamped run in $run. Every process a test starts is stopped at
# the end by its exact process ID.
h="$HO_PLUGIN_ROOT/bin/harness"
base=$(cd -P "$PWD" && pwd)
proj="$base/proj"
user="$base/user"
mkdir -p "$proj/.harness" "$proj/src" "$user"
cat > "$proj/.harness/config.json" <<'JSON'
{"schemaVersion": 2,
 "terminal": {"app": "tmux", "enter_delay_seconds": 0},
 "session": {"boot_timeout_seconds": 30, "close_timeout_seconds": 5, "boot_grace_seconds": 5, "fatal_hold_seconds": 0},
 "limits": {"workers": 50}}
JSON
cat > "$user/config.json" <<'JSON'
{"schemaVersion": 2, "runtime": {"main": "claude-code"}}
JSON
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$user"
# A slow or briefly sleeping machine must not end a held fake session before its check:
# hold up to 10 min (cleanup stops every process by its exact PID anyway) and allow a
# 30 s boot. Tests that need a boot failure set their own short timeout.
export HO_FAKE_TERM_DIR="$base/term" HO_FAKE_CLAUDE_LOG="$base/claude.log" HO_FAKE_CLAUDE_HOLD=exit HO_FAKE_CLAUDE_HOLD_MAX=600
# trust_root: the person has trusted the project folder once in the runtime (the runtime's
# own state file in the scratch HOME). Pre-trust of a working folder needs that consent.
trust_root() { jq -n --arg p "$proj" '.projects[$p].hasTrustDialogAccepted = true' > "$HOME/.claude.json"; }
trust_root
run=$("$h" run new)
printf 'do the work\n' > "$base/prompt.md"

# launch <name> [args...]: launch a worker in $proj/src with the shared prompt.
launch() {
  local name=$1
  shift
  "$h" session "$run" launch --role worker --name "$name" --cwd "$proj/src" --prompt "$base/prompt.md" "$@"
}
# rec <name> <jq>: read a field from a registry record.
rec() { jq -r "$2" "${3:-$run}/sessions/$1.json"; }
alive() { ps -o pid= -p "$1" >/dev/null 2>&1; }
calls() { cat "$HO_FAKE_TERM_DIR/calls.log" 2>/dev/null || true; }
# wait_gone <pid>: up to 5 s.
wait_gone() {
  local i=0
  while alive "$1" && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  ! alive "$1"
}
ho_test_cleanup() {
  local f p
  for f in "$HO_FAKE_TERM_DIR"/*.pid "$base"/proj/.harness/runs/*/sessions/*.json "$base"/extra.pids; do
    [ -f "$f" ] || continue
    case $f in
      *.json) p=$(jq -r '.pid // empty' "$f" 2>/dev/null || true) ;;
      *) p=$(cat "$f") ;;
    esac
    for p in $p; do
      case $p in '' | *[!0-9]*) continue ;; esac
      kill "$p" 2>/dev/null || true
    done
  done
}
trap ho_test_cleanup EXIT
