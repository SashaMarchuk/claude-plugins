#!/usr/bin/env bash
# harness-run.sh — run lifecycle: start | stop | status | resume | watch (internal loop)
# A run is a directory: <project>/.harness/runs/<id>/. The only long-lived processes are the
# deterministic watch loop and caffeinate — both owned by the run, both stopped with it (DESIGN §9).
set -uo pipefail
BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$BIN/hlib.sh"

PROJ=$(hproject_root) || exit 78
HDIR="$PROJ/.harness"

preflight() {
  local fails=0
  command -v jq >/dev/null || { echo "MISSING: jq" >&2; fails=1; }
  command -v claude >/dev/null || { echo "MISSING: claude CLI" >&2; fails=1; }
  [ -f "$HARNESS_USER_CONFIG" ] || { echo "MISSING: user config — run /harness:onboard" >&2; fails=1; }
  if [ "$(cfg '.tickets.source' 'local')" = "github" ]; then
    gh auth status >/dev/null 2>&1 || { echo "MISSING: gh auth (tickets.source=github)" >&2; fails=1; }
  fi
  "$BIN/harness-term.sh" probe >/dev/null || { echo "FAILED: terminal automation probe (grant Automation permission?)" >&2; fails=1; }
  # Terminal.app can't drive stop/watch/auto-resume (no send/key) — warn if it's the resolved backend.
  local be; be=$(cfg '.terminal.app' 'auto')
  if [ "$be" = "terminal" ]; then
    echo "WARN: terminal.app=terminal — graceful stop, stall nudges, and rate-limit auto-resume are unavailable on Terminal.app. Prefer iterm2 or tmux." >&2
  fi
  local ec; ec=$(cfg '.accounts.env_command' '')
  if [ -n "$ec" ]; then
    $ec >/dev/null 2>&1 || { echo "FAILED: accounts.env_command preflight: $ec (L7)" >&2; fails=1; }
  fi
  # First-run bypass-permissions acceptance: --dangerously-skip-permissions blocks on an interactive
  # "I accept" dialog the first time per account. Boot verification would still pass (process exists)
  # while the session sits on the dialog. Warn if we can't confirm prior acceptance (review MEDIUM).
  if [ "$(cfg '.session.permissions' 'bypass')" = "bypass" ]; then
    if ! grep -q 'bypassPermissionsModeAccepted"[[:space:]]*:[[:space:]]*true' "$HOME/.claude.json" 2>/dev/null; then
      echo "WARN: could not confirm 'Bypass Permissions' was accepted for this account. Run 'claude --dangerously-skip-permissions' once interactively and accept, or set session.permissions to 'auto'/'acceptEdits' — otherwise the first spawned session may hang on the acceptance dialog." >&2
    fi
  fi
  for s in "$BIN"/harness-*.sh; do bash -n "$s" || fails=1; done
  [ "$fails" -eq 0 ]
}

do_start() {
  stop_requested && { echo "STOP file present ($(hstop_file)) — remove it to start a run" >&2; exit 65; }
  if [ -f "$HDIR/CURRENT" ] && [ -d "$HDIR/runs/$(cat "$HDIR/CURRENT")" ] && [ ! -f "$HDIR/runs/$(cat "$HDIR/CURRENT")/STOPPED" ]; then
    echo "ERROR: run $(cat "$HDIR/CURRENT") looks active — use 'harness-run.sh resume' or stop it first" >&2; exit 65
  fi
  preflight || { echo "PREFLIGHT FAILED — fix the items above" >&2; exit 78; }

  local id run tdir
  id=$(run_id_new); run="$HDIR/runs/$id"
  mkdir -p "$run"/{launchers,prompts,state/registry,logs,heartbeats,markers}
  printf '%s\n' "$id" > "$HDIR/CURRENT"
  hlog "run $id: created"

  # copy prompt templates into the run (shipped templates are never edited in place)
  tdir="$(dirname "$BIN")/templates/prompts"
  local f base
  for f in "$tdir"/*.md; do
    base=$(basename "$f")
    sed -e "s|{{HBIN}}|$BIN|g" -e "s|{{PROJECT_ROOT}}|$PROJ|g" -e "s|{{RUN_DIR}}|$run|g" \
        -e "s|{{RUN_ID}}|$id|g" "$f" > "$run/prompts/$base"
  done
  # the GSD driving guide lives with the skill; copy it beside the prompts so sessions can read it
  local gref; gref="$(dirname "$BIN")/skills/harness/references/gsd-workflow.md"
  [ -f "$gref" ] && sed -e "s|{{HBIN}}|$BIN|g" -e "s|{{RUN_DIR}}|$run|g" "$gref" > "$run/prompts/gsd-workflow.md"

  # limits snapshot for the morning report
  "$BIN/harness-limits.sh" verdict > "$run/state/limits-at-start.txt" || true

  # caffeinate: harness-managed, no -t (L16); watch respawns it if it dies
  if [ "$(cfg '.run.caffeinate' 'true')" = "true" ] && command -v caffeinate >/dev/null; then
    nohup caffeinate -dims >/dev/null 2>&1 &
    printf '%s\n' "$!" > "$run/state/caffeinate.pid"
  fi

  # deterministic watch loop (not an LLM — L9)
  nohup "$BIN/harness-run.sh" watch >> "$run/logs/watch.log" 2>&1 &
  printf '%s\n' "$!" > "$run/state/watch.pid"

  # orchestrator — if the account is rate-paused at start (exit 75), WAIT for the reset and retry
  # rather than aborting: starting a run at 91% is the exact go-to-sleep case (pause-not-stop, review HIGH).
  local rc
  while :; do
    stop_requested && { echo "STOP requested during startup" >&2; do_stop; exit 65; }
    "$BIN/harness-spawn.sh" spawn --role orchestrator --name orchestrator \
      --cwd "$PROJ" --prompt "$run/prompts/orchestrator.md"; rc=$?
    [ "$rc" -eq 0 ] && break
    if [ "$rc" -eq 75 ]; then
      hlog "run $id: rate-paused at start — waiting for reset before spawning the orchestrator"
      "$BIN/harness-limits.sh" wait || { echo "wait aborted (STOP?) — stopping run" >&2; do_stop; exit 65; }
      continue
    fi
    echo "ERROR: orchestrator failed to boot (rc=$rc) — stopping run" >&2; do_stop; exit "$rc"
  done
  hlog "run $id: started (watch pid $(cat "$run/state/watch.pid"))"
  echo "OK run=$id — watch it with: harness-run.sh status"
}

do_stop() {
  local run; run=$(hcurrent_run) || exit 66
  touch "$(hstop_file)"
  hlog "stop: STOP set — closing sessions gracefully"
  # workers first, orchestrator last (reverse dependency order)
  local f name role
  for pass in workers orchestrator; do
    for f in "$run"/state/registry/*.json; do
      [ -f "$f" ] || continue
      name=$(jq -r '.name' "$f"); role=$(jq -r '.role' "$f")
      case "$pass:$role" in
        workers:orchestrator) continue ;;
        orchestrator:*) [ "$role" = orchestrator ] || continue ;;
      esac
      "$BIN/harness-spawn.sh" close "$name" || true
    done
  done
  [ -f "$run/state/watch.pid" ] && kill "$(cat "$run/state/watch.pid")" 2>/dev/null || true
  [ -f "$run/state/caffeinate.pid" ] && kill "$(cat "$run/state/caffeinate.pid")" 2>/dev/null || true
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$run/STOPPED"
  rm -f "$(hstop_file)"
  hlog "stop: run $(basename "$run") stopped"
}

do_status() {
  local run; run=$(hcurrent_run) || exit 66
  echo "run: $(basename "$run")   project: $PROJ"
  echo "limits: $("$BIN/harness-limits.sh" verdict)"
  echo; "$BIN/harness-spawn.sh" list
  echo; echo "heartbeat ages:"
  local h
  for h in "$run"/heartbeats/*.epoch; do
    [ -f "$h" ] || continue
    printf '  %-24s %ss ago\n' "$(basename "$h" .epoch)" "$(( $(date +%s) - $(cat "$h") ))"
  done
  if [ -f "$run/state/attention" ]; then echo; echo "ATTENTION:"; sed 's/^/  /' "$run/state/attention"; fi
  echo; echo "tickets ready:"; "$BIN/harness-tickets.sh" list ready 2>/dev/null | sed 's/^/  /' || true
  echo "tickets in-progress:"; "$BIN/harness-tickets.sh" list in-progress 2>/dev/null | sed 's/^/  /' || true
}

do_resume() {
  local run; run=$(hcurrent_run) || exit 66
  rm -f "$run/STOPPED" "$(hstop_file)"
  preflight || exit 78
  if [ ! -f "$run/state/watch.pid" ] || ! kill -0 "$(cat "$run/state/watch.pid")" 2>/dev/null; then
    nohup "$BIN/harness-run.sh" watch >> "$run/logs/watch.log" 2>&1 &
    printf '%s\n' "$!" > "$run/state/watch.pid"
  fi
  local f name sid role cwd pid
  for f in "$run"/state/registry/*.json; do
    [ -f "$f" ] || continue
    pid=$(jq -r '.pid // empty' "$f")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then continue; fi   # tracked claude pid alive
    name=$(jq -r '.name' "$f"); sid=$(jq -r '.session_id' "$f")
    role=$(jq -r '.role' "$f"); cwd=$(jq -r '.cwd' "$f")
    hlog "resume: $name is dead — respawning with --resume $sid"
    rm -f "$f"
    "$BIN/harness-spawn.sh" spawn --role "$role" --name "$name" --cwd "$cwd" --resume "$sid" || true
  done
  echo "OK resumed run $(basename "$run")"
}

# ---------------------------------------------------------------- watch (loop)
watch_tick() {
  local run="$1" stall_min nudge_file
  stall_min=$(cfg '.run.stall_minutes' '20')
  : > "$run/state/attention.tmp"

  # caffeinate liveness (L16)
  if [ -f "$run/state/caffeinate.pid" ] && ! kill -0 "$(cat "$run/state/caffeinate.pid")" 2>/dev/null; then
    nohup caffeinate -dims >/dev/null 2>&1 &
    printf '%s\n' "$!" > "$run/state/caffeinate.pid"
    hlog "watch: caffeinate respawned"
  fi

  # opt-in hard stop (default null = never — the harness pauses, it does not stop, unless told).
  local stop_at vline s w
  stop_at=$(cfg '.limits.stop_at' 'null')
  if [ "$stop_at" != "null" ]; then
    vline=$("$BIN/harness-limits.sh" verdict)
    s=$(printf '%s' "$vline" | sed -n 's/.*SESSION=\([0-9]*\).*/\1/p')
    w=$(printf '%s' "$vline" | sed -n 's/.*WEEKLY=\([0-9]*\).*/\1/p')
    if { [ -n "$s" ] && [ "$s" -ge "$stop_at" ] 2>/dev/null; } || { [ -n "$w" ] && [ "$w" -ge "$stop_at" ] 2>/dev/null; }; then
      hlog "watch: limits.stop_at=$stop_at reached ($vline) — winding down the run"
      touch "$(hstop_file)"
    fi
  fi

  local f name tty role pid age tail cwd pwflag
  for f in "$run"/state/registry/*.json; do
    [ -f "$f" ] || continue
    name=$(jq -r '.name' "$f"); tty=$(jq -r '.tty' "$f"); role=$(jq -r '.role' "$f"); pid=$(jq -r '.pid // empty' "$f")

    # liveness: the tracked claude pid (not "any node on the tty" — review MEDIUM)
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
      echo "DEAD: $name (pid ${pid:-?}) — resume with: harness-run.sh resume" >> "$run/state/attention.tmp"
      continue
    fi

    # heartbeat staleness → single nudge (Enter), then report; never kill (L18)
    age=$("$BIN/harness-state.sh" heartbeat-age "$name" 2>/dev/null || echo never)
    if [ "$age" != "never" ] && [ "$age" -gt $((stall_min*60)) ]; then
      nudge_file="$run/state/nudged-$name"
      if [ ! -f "$nudge_file" ] || [ $(( $(date +%s) - $(cat "$nudge_file") )) -gt 3600 ]; then
        "$BIN/harness-term.sh" key "$tty" enter 2>/dev/null || true
        date +%s > "$nudge_file"
        hlog "watch: nudged $name (heartbeat ${age}s stale)"
      else
        echo "STALLED: $name heartbeat ${age}s old (already nudged)" >> "$run/state/attention.tmp"
      fi
    fi

    tail=$("$BIN/harness-term.sh" capture "$tty" 25 2>/dev/null || true)

    # interactive limit banner: clear only when idle, timing from the API (L8/L9)
    if printf '%s' "$tail" | grep -qiE 'limit reached|hit your (session|weekly) limit|rate limit' \
       && ! printf '%s' "$tail" | grep -q 'esc to interrupt'; then
      hlog "watch: limit banner on $name — waiting for reset via API"
      "$BIN/harness-limits.sh" wait || true
      "$BIN/harness-term.sh" key "$tty" escape 2>/dev/null || true
      sleep 2
      "$BIN/harness-term.sh" send "$tty" "continue" 2>/dev/null || true
      hlog "watch: sent resume to $name after reset"
    fi

    # trust dialog: answer ONLY after a Sonnet check confirms the session's cwd is inside the
    # project (pretrust normally prevents this; this is the backstop). Never blanket-trust.
    if printf '%s' "$tail" | grep -qiE 'trust the files in this folder|do you trust'; then
      cwd=$(jq -r '.cwd' "$f")
      if "$BIN/harness-trust.sh" inside "$cwd" >/dev/null 2>&1 && trust_ok_sonnet "$name" "$cwd" "$tail"; then
        "$BIN/harness-term.sh" key "$tty" enter 2>/dev/null || true   # default selection = "Yes, proceed"
        hlog "watch: trust dialog on $name — confirmed cwd $cwd inside project, answered yes"
      else
        echo "TRUST-PROMPT: $name is asking to trust $cwd — NOT auto-answered (outside project or Sonnet declined); answer it yourself" >> "$run/state/attention.tmp"
      fi
    fi

    # password / sudo prompt: NEVER type a secret. Owner-gate it (DESIGN §secrets).
    if printf '%s' "$tail" | grep -qiE 'password:|\[sudo\]|passphrase|sudo password'; then
      echo "PASSWORD-PROMPT: $name ($role) is blocked on a password/sudo prompt — the harness never types secrets. Enter it yourself, or set up passwordless access (see README)." >> "$run/state/attention.tmp"
      local pwflag="$run/state/pw-gated-$name"
      if [ ! -f "$pwflag" ]; then
        "$BIN/harness-state.sh" owner-action "Password/sudo prompt in session $name" \
          "an unattended session hit an interactive password/sudo prompt; the harness will not type secrets" \
          "attach to the $role session and enter the credential, OR configure passwordless sudo / docker group so it never prompts" \
          "the session proceeds past the prompt" 2>/dev/null || true
        date +%s > "$pwflag"
      fi
    fi
  done
  mv "$run/state/attention.tmp" "$run/state/attention" 2>/dev/null || true
}

# Sonnet gate for the trust dialog: a second opinion that the folder is legitimately part of this
# run before we answer yes. Deterministic `inside` check already passed; this catches oddities.
trust_ok_sonnet() { # <name> <cwd> <screen-tail>
  local name="$1" cwd="$2" tail="$3" claude_bin out
  [ "$(cfg '.guardrails.sonnet_trust_check' 'true')" = "true" ] || return 0
  claude_bin=$(command -v claude) || return 0   # can't check → rely on the deterministic inside test
  out=$("$claude_bin" -p --model sonnet --settings '{"disableAllHooks": true}' \
    "A harness session named '$name' is showing Claude Code's 'trust the files in this folder?' dialog for the directory: $cwd . This directory has ALREADY been verified to be inside the operator's configured harness project (a git worktree or the project root the harness itself created). Should the harness answer YES to trust it? Answer TRUST-YES only if nothing about the path looks like a system/home/unrelated location; otherwise TRUST-NO. Reply with exactly one token: TRUST-YES or TRUST-NO." 2>/dev/null) || return 0
  case "$out" in *TRUST-YES*) return 0 ;; *) hlog "watch: Sonnet declined trust for $cwd"; return 1 ;; esac
}

do_watch() {
  local run; run=$(hcurrent_run) || exit 66
  hlog "watch: started (pid $$)"
  while :; do
    stop_requested && { hlog "watch: STOP — exiting"; exit 0; }
    [ -f "$run/STOPPED" ] && { hlog "watch: run stopped — exiting"; exit 0; }
    # normal completion: the orchestrator sets the run.complete marker → tear the run down so
    # caffeinate stops (the Mac can sleep) and the next /harness:run isn't blocked (review H1).
    # Inlined (not `do_stop`, which would kill this very watch pid mid-teardown): close every
    # session, stop caffeinate, mark STOPPED, then exit ourselves.
    if [ -f "$run/markers/run.complete.done" ]; then
      hlog "watch: run.complete — tearing down (closing sessions, stopping caffeinate)"
      touch "$(hstop_file)"
      local rf rn
      for rf in "$run"/state/registry/*.json; do
        [ -f "$rf" ] || continue; rn=$(jq -r '.name' "$rf")
        "$BIN/harness-spawn.sh" close "$rn" >/dev/null 2>&1 || true
      done
      [ -f "$run/state/caffeinate.pid" ] && kill "$(cat "$run/state/caffeinate.pid")" 2>/dev/null || true
      date -u '+%Y-%m-%dT%H:%M:%SZ' > "$run/STOPPED"
      rm -f "$(hstop_file)"
      hlog "watch: teardown complete — run $(basename "$run") stopped, Mac may sleep"
      exit 0
    fi
    watch_tick "$run" || hlog "watch: tick error (continuing)"
    sleep "$(cfg '.run.watch_interval_seconds' '60')"
  done
}

case "${1:?usage: harness-run.sh start|stop|status|resume|watch}" in
  start)  do_start ;;
  stop)   do_stop ;;
  status) do_status ;;
  resume) do_resume ;;
  watch)  do_watch ;;
  *) echo "usage: harness-run.sh start|stop|status|resume|watch" >&2; exit 64 ;;
esac
