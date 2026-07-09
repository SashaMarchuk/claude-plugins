#!/usr/bin/env bash
# spawn.sh — the only way harness sessions come to life or end.
# Usage:
#   spawn.sh spawn --role <orchestrator|worker|validator|question> --name <slug> \
#                  --cwd <abs-dir> --prompt <abs-file> [--model "<chain>"] [--resume <uuid>] [--print]
#   spawn.sh close <name>     # graceful: /exit → wait for job end → close that session only
#   spawn.sh list             # registry table
# Exit codes: 0 ok · 64 usage · 65 guard-rejected · 66 not-found · 69 boot-failed · 70 terminal-failed
#             75 rate-paused (caller should run `limits.sh wait` and retry)
# Pipeline (order is the contract): guards → rate gate → launcher → lint → sonnet validation →
# terminal spawn → boot verification → registry (DESIGN.md §5).
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$BIN/hlib.sh"

registry_dir() { printf '%s/state/registry\n' "$(hcurrent_run)"; }

slug_ok() { case "${1:?}" in *[!a-z0-9-]*|"") return 1 ;; *) return 0 ;; esac; }

group_for_role() { # role → window group; project/user config .terminal.windows, else default map
  local role="$1" g proj f
  proj=$(hproject_root 2>/dev/null || true)
  for f in "${proj:+$proj/.harness/config.json}" "$HARNESS_USER_CONFIG"; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    g=$(jq -er --arg r "$role" '.terminal.windows // {} | to_entries[] | select(.value[]? == $r) | .key' "$f" 2>/dev/null | head -1)
    [ -n "$g" ] && { printf '%s\n' "$g"; return 0; }
  done
  case "$role" in orchestrator|watch) echo control ;; *) echo work ;; esac
}

perm_flag() {
  case "$(cfg '.session.permissions' 'bypass')" in
    bypass) echo "--dangerously-skip-permissions" ;;
    auto)   echo "--permission-mode auto" ;;
    acceptEdits) echo "--permission-mode acceptEdits" ;;
    dontAsk) echo "--permission-mode dontAsk" ;;
    *) echo "--dangerously-skip-permissions" ;;
  esac
}

default_chain_for_role() {
  case "$1" in
    orchestrator) cfg '.models.orchestrator' 'opus' ;;
    worker)       cfg '.models.worker' 'opus' ;;
    validator)    cfg '.models.validator' 'fable|mythos|opus' ;;
    question)     cfg '.models.question' 'opus' ;;
    *)            echo 'opus' ;;
  esac
}

launcher_home() { # space-free path for launchers (AppleScript embeds it verbatim)
  local run; run=$(hcurrent_run)
  case "$run" in
    # run path has chars AppleScript can't embed (spaces etc.): fall back to a per-run subdir of
    # the shared launchers dir — run-id-scoped so concurrent runs/projects never collide (review LOW).
    *[!A-Za-z0-9._/:@=-]*) local d; d="$HARNESS_USER_DIR/launchers/$(basename "$run")"; mkdir -p "$d"; printf '%s\n' "$d" ;;
    *) printf '%s/launchers\n' "$run" ;;
  esac
}

# ------------------------------------------------------------------------ spawn
do_spawn() {
  local role="" name="" cwd="" prompt="" chain="" resume="" printmode=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --role) role="$2"; shift 2 ;;
      --name) name="$2"; shift 2 ;;
      --cwd) cwd="$2"; shift 2 ;;
      --prompt) prompt="$2"; shift 2 ;;
      --model) chain="$2"; shift 2 ;;
      --resume) resume="$2"; shift 2 ;;
      --print) printmode=1; shift ;;
      *) echo "ERROR: unknown arg $1" >&2; return 64 ;;
    esac
  done
  [ -n "$role" ] && [ -n "$name" ] && [ -n "$cwd" ] || { echo "usage: spawn.sh spawn --role R --name N --cwd D --prompt F" >&2; return 64; }
  slug_ok "$name" || { echo "ERROR: name must be a-z0-9- slug: $name" >&2; return 65; }
  case "$role" in orchestrator|worker|validator|question) ;; *) echo "ERROR: unknown role $role" >&2; return 65 ;; esac

  # -- deterministic guards (L2/L3) --
  local run PROJ; run=$(hcurrent_run) || return 66
  PROJ=$(hproject_root) || return 66
  stop_requested && { echo "REJECTED: STOP file present" >&2; return 65; }
  assert_safe_cwd "$cwd" || return 65
  # cwd is embedded into the generated launcher as `cd "$cwd"`; a real dir name containing a
  # command substitution would execute at launcher runtime. Screen it (belt for the resolved path).
  case "$cwd" in *['`$;&|<>()!*?']*|*'"'*) echo "ERROR: cwd contains shell metacharacters — refusing: $cwd" >&2; return 65 ;; esac
  if [ -z "$resume" ]; then
    [ -n "$prompt" ] || { echo "ERROR: --prompt required unless --resume" >&2; return 64; }
    assert_abs "$prompt" "prompt file" || return 65
    [ -s "$prompt" ] || { echo "ERROR: prompt file missing/empty: $prompt" >&2; return 65; }
    case "$prompt" in *"'"*) echo "ERROR: prompt path may not contain single quotes" >&2; return 65 ;; esac
    # An unfilled template placeholder ({{LANE}} etc.) would poison every engine call the
    # session makes (marker names, heartbeat names). Refuse before spawning (review HIGH).
    if grep -q '{{' "$prompt"; then
      echo "ERROR: prompt still contains an unfilled {{placeholder}}: $prompt" >&2
      grep -n '{{' "$prompt" | head -3 >&2; return 65
    fi
  fi
  [ -f "$(registry_dir)/$name.json" ] && { echo "ERROR: session '$name' already registered" >&2; return 65; }

  # -- rate gate: pause new spawns, never running ones (L13) --
  local vline v
  vline=$("$BIN/harness-limits.sh" verdict); v=$(printf '%s' "$vline" | sed -n 's/.*VERDICT=\([A-Z]*\).*/\1/p')
  if [ "$v" = "PAUSE" ]; then
    hlog "spawn $name: rate-paused ($vline)"
    echo "PAUSED: $vline" >&2
    echo "Run: limits.sh wait   — then retry this spawn." >&2
    return 75
  fi
  if [ "$v" = "UNKNOWN" ] && [ "$(cfg '.limits.on_unreadable' 'proceed')" = "hold" ]; then
    echo "PAUSED: usage API unreadable and limits.on_unreadable=hold" >&2; return 75
  fi

  # -- resolve models --
  [ -n "$chain" ] || chain=$(default_chain_for_role "$role")
  local models_lines rest
  models_lines=$("$BIN/harness-model.sh" resolve "$chain") || return 65
  rest=$("$BIN/harness-model.sh" rest "$chain")

  # -- generate launcher (L1: prompt stays in its file; launcher is lintable bash) --
  local uuid ldir launcher title env_cmd claude_bin grace pflag extra=""
  uuid="${resume:-$(uuidgen | tr 'A-Z' 'a-z')}"
  ldir=$(launcher_home); mkdir -p "$ldir"
  launcher="$ldir/$name.sh"
  title="harness-$role-$name"
  env_cmd=$(cfg '.accounts.env_command' '')
  claude_bin=$(command -v claude || true)
  [ -n "$claude_bin" ] || { echo "ERROR: claude binary not on PATH" >&2; return 65; }
  grace=$(cfg '.session.boot_grace_seconds' '45')
  pflag=$(perm_flag)
  [ "$printmode" = 1 ] && { extra="-p"; [ -n "$rest" ] && extra="-p --fallback-model $rest"; }

  {
    echo '#!/usr/bin/env bash'
    echo "# generated by harness spawn.sh — session $name ($role), run $(basename "$run")"
    echo 'set -uo pipefail'
    echo "LOG=\"$run/logs/launcher.log\""
    echo "note(){ printf '[%s %s] %s\\n' \"\$(date -u '+%H:%M:%S')\" \"$name\" \"\$*\" | tee -a \"\$LOG\" >&2; }"
    echo "export PATH=\"$PATH\""
    # workers/validators run in sibling worktrees with no .harness/ — hand them the project root
    # so every engine call they make resolves (CRITICAL: worktree can't reach the engine otherwise).
    echo "export HARNESS_PROJECT=\"$PROJ\""
    echo "cd \"$cwd\" || { note 'FATAL: cd failed — refusing to start claude (L3)'; sleep 30; exit 66; }"
    if [ -n "$env_cmd" ]; then
      echo "if envout=\$($env_cmd 2>>\"\$LOG\"); then eval \"\$envout\"; note 'account env applied'; else note 'FATAL: accounts.env_command failed (L7)'; sleep 30; exit 9; fi"
    fi
    echo "MODELS=($(printf '%s\n' "$models_lines" | tr '\n' ' '))"
    echo "GRACE=$grace"
    echo 'for m in "${MODELS[@]}"; do'
    echo '  t0=$(date +%s)'
    if [ -n "$resume" ]; then
      echo "  note \"resuming session $uuid model=\$m\""
      echo "  \"$claude_bin\" --resume \"$uuid\" --model \"\$m\" -n \"$title\" $pflag $extra"
    else
      echo "  note \"starting model=\$m session=$uuid\""
      echo "  \"$claude_bin\" --model \"\$m\" --session-id \"$uuid\" -n \"$title\" $pflag $extra \"\$(cat '$prompt')\""
    fi
    echo '  rc=$?; dt=$(( $(date +%s) - t0 ))'
    echo '  if [ "$rc" -ne 0 ] && [ "$dt" -le "$GRACE" ]; then note "boot failed rc=$rc after ${dt}s — falling back from $m"; continue; fi'
    echo '  note "claude exited rc=$rc after ${dt}s"; exit "$rc"'
    echo 'done'
    echo 'note "FATAL: every model candidate failed at boot"; sleep 30; exit 69'
  } > "$launcher"
  chmod +x "$launcher"
  bash -n "$launcher" || { echo "ERROR: generated launcher failed bash -n (bug — report this)" >&2; return 65; }

  # pointer so a worker in a sibling worktree can find the project even without the env var
  [ -e "$cwd/.harness-project" ] || printf '%s\n' "$PROJ" > "$cwd/.harness-project" 2>/dev/null || true

  # pre-trust the cwd so the session doesn't stall on "Do you trust the files in this folder?"
  # (deterministic belt — only trusts dirs inside the project; the watch monitor is the backstop).
  "$BIN/harness-trust.sh" pretrust "$cwd" >/dev/null 2>&1 || true

  # -- sonnet validation (second net; deterministic guards already passed) --
  # NOTE: capture the validator's exit status DIRECTLY. `if ! cmd; then rc=$?` would capture the
  # status of the `!` negation (always 0), silently swallowing a REJECT (review CRITICAL).
  if [ "$(cfg '.guardrails.sonnet_validation' 'true')" = "true" ]; then
    local vrc
    "$BIN/harness-validate.sh" "$launcher" "$cwd" "$role"; vrc=$?
    if [ "$vrc" -eq 65 ]; then
      echo "REJECTED by spawn-validator — see message above" >&2; return 65
    elif [ "$vrc" -ne 0 ]; then
      hlog "spawn $name: validator infra error (rc=$vrc) — proceeding on deterministic guards"
    fi
  fi

  # -- spawn + boot verification (L4) --
  local group; group=$(group_for_role "$role")
  "$BIN/harness-term.sh" spawn "$group" "$title" "$launcher" || return 70
  local total_wait i pid tty
  total_wait=$(( grace * $(printf '%s\n' "$models_lines" | wc -l | tr -d ' ') + 45 ))
  i=0
  while [ "$i" -lt "$total_wait" ]; do
    if [ -n "$resume" ]; then
      pid=$(pgrep -f -- "--resume $uuid" | head -1 || true)
    else
      pid=$(pgrep -f -- "--session-id $uuid" | head -1 || true)
    fi
    [ -n "$pid" ] && break
    sleep 3; i=$((i+3))
  done
  if [ -z "${pid:-}" ]; then
    hlog "spawn $name: BOOT-FAILED after ${total_wait}s — launcher log tail:"
    tail -5 "$run/logs/launcher.log" >&2 || true
    return 69
  fi
  tty=$(ps -o tty= -p "$pid" | tr -d ' ')
  mkdir -p "$(registry_dir)"
  jq -n --arg name "$name" --arg role "$role" --arg group "$group" --arg tty "$tty" \
        --arg sid "$uuid" --arg cwd "$cwd" --arg chain "$chain" --arg launcher "$launcher" \
        --arg pid "$pid" --arg at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '{name:$name, role:$role, group:$group, tty:$tty, pid:($pid|tonumber), session_id:$sid, cwd:$cwd, model_chain:$chain, launcher:$launcher, started_at:$at}' \
    | atomic_write "$(registry_dir)/$name.json"
  hlog "spawn $name: BOOT-VERIFIED pid=$pid tty=$tty session=$uuid model_chain=$chain"
  # A resumed session restores its transcript but sits idle until prompted — kick it back to work
  # (a bare Enter is a no-op; review HIGH). Fresh spawns already carry their prompt in the launcher.
  if [ -n "$resume" ]; then
    sleep 3
    "$BIN/harness-term.sh" send "$tty" "continue" 2>/dev/null || true
    hlog "spawn $name: resume kick sent"
  fi
  echo "OK name=$name tty=$tty session=$uuid"
}

# ------------------------------------------------------------------------ close
do_close() { # graceful close protocol (L11): /exit → wait for job end → close that session only
  local name="${1:?name required}" reg tty pid deadline
  reg="$(registry_dir)/$name.json"
  [ -f "$reg" ] || { echo "ERROR: '$name' not in registry (never close sessions we don't own — L12)" >&2; return 66; }
  tty=$(jq -r '.tty' "$reg"); pid=$(jq -r '.pid // empty' "$reg")
  # job-end = the tracked claude pid is gone (NOT "any node on the tty" — MCP/dev-server node
  # children share the tty and would mask completion; review MEDIUM).
  job_alive() { [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; }
  if ! job_alive; then
    hlog "close $name: claude pid ${pid:-?} already gone — removing registry entry"
    rm -f "$reg"; "$BIN/harness-term.sh" close "$tty" 2>/dev/null || true; return 0
  fi
  # A claude session mid-turn ignores /exit, so interrupt to idle first (Escape), then /exit.
  # Two rounds: the first Escape cancels a running turn; the second /exit lands on the idle prompt.
  deadline=$(( $(now_epoch) + $(cfg '.session.close_timeout_seconds' '90') ))
  local sent_exit=0
  while [ "$(now_epoch)" -lt "$deadline" ]; do
    if ! job_alive; then
      "$BIN/harness-term.sh" close "$tty" || true
      rm -f "$reg"
      hlog "close $name: closed cleanly"
      return 0
    fi
    if printf '%s' "$("$BIN/harness-term.sh" capture "$tty" 6 2>/dev/null)" | grep -q 'esc to interrupt'; then
      "$BIN/harness-term.sh" key "$tty" escape 2>/dev/null || true   # cancel the running turn
      sent_exit=0
    elif [ "$sent_exit" -eq 0 ]; then
      "$BIN/harness-term.sh" send "$tty" "/exit" 2>/dev/null || true  # idle → ask it to exit
      sent_exit=1
    fi
    sleep 5
  done
  hlog "close $name: job still running after timeout — LEAVING SESSION OPEN (never force-close, L11)"
  echo "WARN: $name still busy; left open. Re-run close later or inspect tty $tty." >&2
  return 1
}

do_list() {
  local d; d=$(registry_dir)
  [ -d "$d" ] || { echo "(no sessions)"; return 0; }
  printf '%-20s %-12s %-8s %-10s %s\n' NAME ROLE GROUP TTY SESSION
  local f
  for f in "$d"/*.json; do
    [ -f "$f" ] || continue
    jq -r '[.name,.role,.group,.tty,.session_id] | @tsv' "$f" \
      | awk -F'\t' '{printf "%-20s %-12s %-8s %-10s %s\n",$1,$2,$3,$4,$5}'
  done
}

case "${1:?usage: spawn.sh spawn|close|list}" in
  spawn) shift; do_spawn "$@" ;;
  close) shift; do_close "$@" ;;
  list)  do_list ;;
  *) echo "usage: spawn.sh spawn|close|list" >&2; exit 64 ;;
esac
