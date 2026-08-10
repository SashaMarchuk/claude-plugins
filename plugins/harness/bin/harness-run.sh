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
  jq -e . "$PROJ/.harness/config.json" >/dev/null 2>&1 || { echo "INVALID: $PROJ/.harness/config.json is not valid JSON — every setting would silently revert to defaults" >&2; fails=1; }
  if [ "$(cfg '.tickets.source' 'local')" = "github" ]; then
    gh auth status >/dev/null 2>&1 || { echo "MISSING: gh auth (tickets.source=github)" >&2; fails=1; }
  fi
  local probe; probe=$("$BIN/harness-term.sh" probe 2>/dev/null) || { echo "FAILED: terminal automation probe (grant Automation permission?)" >&2; fails=1; }
  # Terminal.app can't drive stop/watch/auto-resume (no send/key) — warn whenever it's the RESOLVED
  # backend, even when auto-detected (review LOW), by reading the probe's 'OK backend=<x>' line.
  local be; be=$(printf '%s' "$probe" | sed -n 's/.*backend=//p')
  if [ "$be" = "terminal" ]; then
    echo "WARN: terminal.app=terminal — graceful stop, stall nudges, and rate-limit auto-resume are unavailable on Terminal.app. Prefer iterm2 or tmux." >&2
  fi
  local ec; ec=$(cfg '.accounts.env_command' '')
  if [ -n "$ec" ]; then
    $ec >/dev/null 2>&1 || { echo "FAILED: accounts.env_command preflight: $ec (L7)" >&2; fails=1; }
  fi
  # a literal secret in any accounts*.env_command would be baked into the on-disk launcher AND shipped
  # to the sonnet spawn-validator. env_command must be a COMMAND that prints exports, never the secret.
  local ecfg
  for ecfg in "$PROJ/.harness/config.json" "$HARNESS_USER_CONFIG"; do
    [ -f "$ecfg" ] || continue
    if jq -r '(.accounts // {}) | .. | objects | .env_command? // empty' "$ecfg" 2>/dev/null | grep -qE 'OAUTH_TOKEN=|API_KEY=|SECRET='; then
      echo "REFUSED: an accounts*.env_command in $ecfg embeds a literal credential (OAUTH_TOKEN=/API_KEY=/SECRET=). Point env_command at a command that PRINTS exports; never inline the secret — it would land in the launcher file and the validator prompt." >&2; fails=1
    fi
  done
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
  local cur; cur=$(cat "$HDIR/CURRENT" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$cur" ] && [ -d "$HDIR/runs/$cur" ] && [ ! -f "$HDIR/runs/$cur/STOPPED" ]; then
    echo "ERROR: run $cur looks active — use 'harness-run.sh resume' or stop it first" >&2; exit 65
  fi
  # an empty/whitespace CURRENT (crash between truncate and write) is NOT an active run — fall through
  # and start fresh, self-healing the wedge (review F3).
  preflight || { echo "PREFLIGHT FAILED — fix the items above" >&2; exit 78; }

  local id run tdir
  id=$(run_id_new); run="$HDIR/runs/$id"
  mkdir -p "$run"/{launchers,prompts,state/registry,logs,heartbeats,markers}
  printf '%s\n' "$id" | atomic_write "$HDIR/CURRENT"   # atomic: no truncate-then-write empty-CURRENT window
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

  # reclaim tickets left in-progress by a previous crashed run: report ALL in-progress, and release
  # the ones idle beyond the threshold (default 7d) that still pass the ready floor. Start-time only —
  # mid-run the harness only reports, never sweeps (review 0.6.0 point-2 stranded tickets).
  "$BIN/harness-tickets.sh" stale > "$run/state/stale-at-start.txt" 2>&1 || true
  if [ -s "$run/state/stale-at-start.txt" ]; then
    echo "in-progress ticket sweep at start:"; sed 's/^/  /' "$run/state/stale-at-start.txt"
  fi

  # deterministic watch loop (not an LLM — L9) — start FIRST so caffeinate can bind to it
  nohup "$BIN/harness-run.sh" watch >> "$run/logs/watch.log" 2>&1 &
  printf '%s\n' "$!" > "$run/state/watch.pid"

  # caffeinate bound to the watch pid (-w): if the watch ever dies, macOS releases the sleep
  # assertion automatically, so a dead watch can never leave the Mac awake (review F5).
  if [ "$(cfg '.run.caffeinate' 'true')" = "true" ] && command -v caffeinate >/dev/null; then
    nohup caffeinate -dims -w "$(cat "$run/state/watch.pid")" >/dev/null 2>&1 &
    printf '%s\n' "$!" > "$run/state/caffeinate.pid"
  fi

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
  local run jsonmode=0; [ "${1:-}" = "--json" ] && jsonmode=1
  run=$(hcurrent_run) || exit 66

  if [ "$jsonmode" -eq 1 ]; then
    # machine-readable health for a cron/notifier babysitter: exit 0 healthy, exit 1 when the run
    # needs a human (attention items present or a DEAD-RUN marker). No terminal/network required
    # beyond the limits verdict (review 0.6.0 observability).
    local now h hb att ready inprog dead=false stopped=false healthy=true
    now=$(date +%s)
    hb=$(for h in "$run"/heartbeats/*.epoch; do [ -f "$h" ] || continue
           printf '%s\t%s\n' "$(basename "$h" .epoch)" "$(( now - $(cat "$h") ))"; done \
         | jq -R -s 'split("\n")|map(select(length>0)|split("\t"))|map({(.[0]):(.[1]|tonumber)})|add // {}')
    att=$(jq -R -s 'split("\n")|map(select(length>0))' "$run/state/attention" 2>/dev/null); [ -n "$att" ] || att='[]'
    ready=$("$BIN/harness-tickets.sh" list ready 2>/dev/null \
      | jq -R -s 'split("\n")|map(select(length>0)|split("\t"))|map({id:.[0],title:.[1]})'); [ -n "$ready" ] || ready='[]'
    inprog=$("$BIN/harness-tickets.sh" list in-progress 2>/dev/null \
      | jq -R -s 'split("\n")|map(select(length>0)|split("\t"))|map({id:.[0],title:.[1]})'); [ -n "$inprog" ] || inprog='[]'
    [ -f "$run/DEAD-RUN" ] && dead=true
    [ -f "$run/STOPPED" ] && stopped=true
    { [ -s "$run/state/attention" ] || [ "$dead" = true ]; } && healthy=false
    jq -n --arg run "$(basename "$run")" --arg project "$PROJ" \
          --arg verdict "$("$BIN/harness-limits.sh" verdict)" \
          --argjson hb "$hb" --argjson att "$att" --argjson dead "$dead" --argjson stopped "$stopped" \
          --argjson healthy "$healthy" --argjson ready "$ready" --argjson inprog "$inprog" \
          '{run:$run, project:$project, healthy:$healthy, limits_verdict:$verdict,
            heartbeat_ages:$hb, attention:$att, dead_run:$dead, stopped:$stopped,
            tickets:{ready:$ready, in_progress:$inprog}}'
    [ "$healthy" = true ]; return
  fi

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
  return 0
}

do_resume() {
  local run; run=$(hcurrent_run) || exit 66
  rm -f "$run/STOPPED" "$(hstop_file)"
  preflight || exit 78
  if [ ! -f "$run/state/watch.pid" ] || ! kill -0 "$(cat "$run/state/watch.pid")" 2>/dev/null; then
    nohup "$BIN/harness-run.sh" watch >> "$run/logs/watch.log" 2>&1 &
    printf '%s\n' "$!" > "$run/state/watch.pid"
  fi
  rm -f "$run/DEAD-RUN" "$run/state/dead-ticks"
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
  # Crash-safety: if there is NO orchestrator registry entry (e.g. `start` was killed mid rate-wait
  # before the orchestrator ever booted — the zombie-run case), spawn one fresh from the run's
  # prompt so resume is never a no-op (review MEDIUM).
  if [ ! -e "$run"/state/registry/orchestrator.json ] && [ -f "$run/prompts/orchestrator.md" ]; then
    hlog "resume: no orchestrator in registry — spawning a fresh one"
    "$BIN/harness-spawn.sh" spawn --role orchestrator --name orchestrator --cwd "$PROJ" --prompt "$run/prompts/orchestrator.md" || true
  fi
  echo "OK resumed run $(basename "$run")"
}

# ---------------------------------------------------------------- watch (loop)
watch_tick() {
  local run="$1" stall_min nudge_file
  stall_min=$(cfg_int '.run.stall_minutes' 20)
  : > "$run/state/attention.tmp"

  # caffeinate liveness (L16) — respawn bound to THIS watch loop ($$) so it dies with the watch (F5)
  if [ -f "$run/state/caffeinate.pid" ] && ! kill -0 "$(cat "$run/state/caffeinate.pid")" 2>/dev/null; then
    nohup caffeinate -dims -w "$$" >/dev/null 2>&1 &
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

  local f name tty role pid age tail cwd pwflag pw_prompt modal orch_alive any_alive blocked scope
  orch_alive=0; any_alive=0
  for f in "$run"/state/registry/*.json; do
    [ -f "$f" ] || continue
    name=$(jq -r '.name' "$f"); tty=$(jq -r '.tty' "$f"); role=$(jq -r '.role' "$f"); pid=$(jq -r '.pid // empty' "$f"); cwd=$(jq -r '.cwd' "$f")

    # liveness: the tracked claude pid (not "any node on the tty" — review MEDIUM)
    if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
      echo "DEAD: $name (pid ${pid:-?}) — resume with: harness-run.sh resume" >> "$run/state/attention.tmp"
      continue
    fi
    any_alive=1; [ "$role" = orchestrator ] && orch_alive=1

    # capture the screen ONCE, and decide up front whether this session is sitting at a password
    # prompt — if so, we must NOT nudge/send anything into it (an Enter is an empty credential,
    # and that would break the "never enter a secret" promise; review MEDIUM).
    tail=$("$BIN/harness-term.sh" capture "$tty" 25 2>/dev/null || true)
    pw_prompt=0; modal=0
    printf '%s' "$tail" | grep -qiE 'password:|\[sudo\]|passphrase|sudo password' && { pw_prompt=1; modal=1; }
    # a blind Enter into a trust dialog would accept "Yes, proceed" — the very answer the sonnet
    # gate may decline; treat any trust/password dialog as a modal the nudge must not touch (review LOW).
    printf '%s' "$tail" | grep -qiE 'trust the files in this folder|do you trust' && modal=1

    # a worker that declared itself blocked (worker rule 6) is EXPECTED to be idle — never nudge it,
    # so STALLED spam can't bury real items (review 0.6.0 point-7 blocked-lane).
    blocked=0
    case "$name" in w-*) [ -f "$run/markers/${name#w-}.blocked.done" ] && blocked=1 ;; esac

    # heartbeat staleness → single nudge (Enter), then report; never kill (L18). Skip at a
    # password/trust modal or a self-blocked lane. Before nudging, CROSS-CHECK GIT GROUND TRUTH
    # (DESIGN L18): recent commits/index activity in the session's own tree (or, for the orchestrator
    # at the project root, on any lane branch) = working, not stalled — a long build/test with a quiet
    # heartbeat must not get a blind Enter; likewise skip when the screen shows 'esc to interrupt'
    # (mid-turn). Both cases re-arm the one-shot nudge (review 0.6.0 point-9).
    if [ "$modal" -eq 0 ] && [ "$blocked" -eq 0 ]; then
      age=$("$BIN/harness-state.sh" heartbeat-age "$name" 2>/dev/null || echo never)
      if [ "$age" != "never" ] && [ "$age" -gt $((stall_min*60)) ]; then
        scope="head"; [ "$role" = orchestrator ] && scope="any"
        if git_recent "$cwd" $((stall_min*60)) "$scope" \
           || printf '%s' "$tail" | grep -q 'esc to interrupt'; then
          rm -f "$run/state/nudged-$name"
        else
          nudge_file="$run/state/nudged-$name"
          if [ ! -f "$nudge_file" ] || [ $(( $(date +%s) - $(cat "$nudge_file") )) -gt 3600 ]; then
            "$BIN/harness-term.sh" key "$tty" enter 2>/dev/null || true
            date +%s > "$nudge_file"
            hlog "watch: nudged $name (heartbeat ${age}s stale, no git activity)"
          else
            echo "STALLED: $name heartbeat ${age}s old (already nudged)" >> "$run/state/attention.tmp"
          fi
        fi
      else
        rm -f "$run/state/nudged-$name"
      fi
    fi

    # interactive limit banner: clear only when idle AND not at a password prompt, timing from the
    # API. limits.sh wait waits on the tighter of the 5h/weekly resets (weekly now defaults to a
    # real pause threshold, so a weekly-exhausted session actually waits instead of thrashing).
    if [ "$pw_prompt" -eq 0 ] \
       && printf '%s' "$tail" | grep -qiE 'limit reached|hit your (session|weekly) limit|rate limit' \
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
    if [ "$pw_prompt" -eq 1 ]; then
      echo "PASSWORD-PROMPT: $name ($role) is blocked on a password/sudo prompt — the harness never types secrets. Enter it yourself, or set up passwordless access (see README)." >> "$run/state/attention.tmp"
      pwflag="$run/state/pw-gated-$name"
      if [ ! -f "$pwflag" ]; then
        "$BIN/harness-state.sh" owner-action "Password/sudo prompt in session $name" \
          "an unattended session hit an interactive password/sudo prompt; the harness will not type secrets" \
          "attach to the $role session and enter the credential, OR configure passwordless sudo / docker group so it never prompts" \
          "the session proceeds past the prompt" 2>/dev/null || true
        date +%s > "$pwflag"
      fi
    fi
  done

  # Dead-run fallback (review HIGH): if the orchestrator crashed before it could set run.complete,
  # nothing else ever tears the run down — caffeinate would keep the Mac awake indefinitely and the
  # next /harness:run would refuse. If the orchestrator is dead AND no session is alive for a few
  # consecutive ticks, tear down (so the Mac can sleep) and leave a loud DEAD-RUN marker.
  local deadf="$run/state/dead-ticks"
  if [ "$orch_alive" -eq 0 ] && [ "$any_alive" -eq 0 ] && [ -e "$run"/state/registry/orchestrator.json ]; then
    local dt; dt=$(( $(cat "$deadf" 2>/dev/null || echo 0) + 1 )); echo "$dt" > "$deadf"
    echo "DEAD-RUN: orchestrator and all workers are gone (tick $dt/3) — run '/harness:resume' to revive, or the watch will tear down and let the Mac sleep." >> "$run/state/attention.tmp"
    if [ "$dt" -ge 3 ]; then
      hlog "watch: orchestrator dead + no live sessions for $dt ticks — tearing down (Mac may sleep)"
      [ -f "$run/state/caffeinate.pid" ] && kill "$(cat "$run/state/caffeinate.pid")" 2>/dev/null || true
      printf 'orchestrator died before completion; watch tore the run down after %s idle ticks\n' "$dt" > "$run/DEAD-RUN"
      date -u '+%Y-%m-%dT%H:%M:%SZ' > "$run/STOPPED"
    fi
  else
    rm -f "$deadf"
  fi
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
    local wiv; wiv=$(cfg_int '.run.watch_interval_seconds' 60); [ "$wiv" -lt 1 ] && wiv=60  # never 0 → busy-spin
    sleep "$wiv"
  done
}

case "${1:?usage: harness-run.sh start|stop|status|resume|watch}" in
  start)  do_start ;;
  stop)   do_stop ;;
  status) shift; do_status "$@" ;;
  resume) do_resume ;;
  watch)  do_watch ;;
  *) echo "usage: harness-run.sh start|stop|status|resume|watch" >&2; exit 64 ;;
esac
