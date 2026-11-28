# shellcheck shell=bash
# The run wiring: harness run start|tick|wait|status|stop|resume (issue #110, T11 #44).
#
# Control flow lives here, in engine verbs, never in a long prompt (design Rebuild, drop list).
# The orchestrator session only calls "run tick" and "run wait" in a loop and judges what the
# tick hands it (prompts/orchestrator.md). Every step is an existing verb, called as its own
# process, so each keeps its own checks and exit codes:
#
#   start   the newest unfinished run is resumed (D32), a stopped one is refused (resume lifts a
#           stop); else: config gate (H-072), flow preflight (D31, H-073), run new, hooks check
#           (D42l), limits gate (H-110), autonomy start check (H-036), the run's integration
#           branch (Rebuild reuse list), the handoff prompt (D23, D24), the orchestrator session
#           and the watch script (D22, D23, D32).
#   tick    one pass: the context watcher is alive (H-098); limits are read (H-109); intake takes
#           ready tickets (H-002, H-003); each taken ticket moves one move along its pipeline:
#           step gate (state begin, H-086) and autonomy check per step (H-037), a worker session
#           per flow step with --ticket (H-064), the step result, the finalize commit and
#           "loop ready", an independent validator session (H-055), the verdict, the
#           engine-checked merge (H-046), ship and verify by the autonomy profile (H-042 to H-045,
#           H-053), and the end of the ticket (H-081). Then recovery (H-088, H-091 to H-094) and
#           the lifecycle check (H-079 to H-082).
#   wait    sleep until the next tick is due; a stop or the run end wakes it at once.
#   status  read only: run, stop, sessions, tickets, merges, limits, owner actions.
#   stop    "state stop", then a soft stop's text to every session it covers (H-085, H-086).
#   resume  "state resume", "recover reopen", then the orchestrator and the watch script run.
#
# Per ticket the wiring keeps one record, <run>/orch/<ticket>.json: lane, worktree, branch,
# flow, phase (step, ready, validate, merge, ship, wait-merge, done, blocked) and the current
# step and session. Step results are files, <run>/orch/<ticket>/<step>.result; each finished
# step is also recorded on the ticket ("tickets step", H-028).
#
# Agent decisions (D37), stated in the commit and the CHANGELOG:
#   - The engine writes the finalize(<lane>) commit, after the last flow step's result reads
#     pass and only on a clean tree; "loop ready" then records that commit with the last
#     worker's session ID as the lane's worker, so the validator can never be that worker.
#   - The validator records its verdict itself, with "loop verdict" from inside its session, and
#     the test counts it ran with "verify tests"; the prompt gives both commands.
#   - Merge facts for "ship merge" are built by the engine from its own records: the verdict
#     record, the recorded test counts, the changed paths from git and the PR's check rollup.
#     A PR with no check results is not "green", so a full profile waits for a person there.
#   - "run start" on an unfinished run that a person stopped refuses (75) and names
#     /harness:resume: only resume lifts a stop.

ho_orch_err() { printf 'harness run: %s\n' "$*" >&2; }
ho_orch_h() { HO_PROJECT_DIR=$HO_PROJECT_DIR "$HO_ROOT/bin/harness" "$@"; }
ho_orch_dir() { printf '%s/orch\n' "$HO_RUN_DIR"; }
ho_orch_rec() { printf '%s/orch/%s.json\n' "$HO_RUN_DIR" "$1"; }
ho_orch_get() { jq -r --arg k "$2" '.[$k] // "" | tostring' "$(ho_orch_rec "$1")" 2>/dev/null; }
ho_orch_set() { # <ticket> <jq filter> [jq args]
  local f t
  f=$(ho_orch_rec "$1"); t=$2; shift 2
  jq "$@" "$t" "$f" | ho_atomic_write "$f"
}
ho_orch_lane() { printf 't%s\n' "$1"; }

# ho_orch_bind <run-dir>: open the run and bind its project (the run's config, never the caller's).
ho_orch_bind() {
  ho_run_open "$1"
  HO_PROJECT_DIR=${HO_PROJECT_DIR:-$(dirname "$(dirname "$(dirname "$HO_RUN_DIR")")")}
  export HO_PROJECT_DIR
  ho_session_bind_project || return $?
  ho_tk_bind_project_dir
}

# ho_orch_run_arg [run-dir]: the given run, else the newest unfinished run of this project.
ho_orch_run_arg() {
  if [ -n "${1-}" ]; then printf '%s\n' "$1"; return 0; fi
  ho_rec_last
}

# ho_orch_resume_arg [run-dir]: for resume, the newest unfinished run, else the newest run that a
# stop ended (a soft stop ends the run once its sessions are done; a resume opens it again).
ho_orch_resume_arg() {
  if [ -n "${1-}" ]; then printf '%s\n' "$1"; return 0; fi
  ho_rec_last 2>/dev/null && return 0
  ho_orch_stop_ended && return 0
  ho_orch_err "no unfinished or stopped run in this project; start one with /harness:run"
  return 66
}

# ho_orch_stop_ended: the newest run of this project, when a stop ended it and a ticket it took
# is still in progress.
ho_orch_stop_ended() {
  local d last="" proj t
  proj=$(ho_project_root) || return 66
  for d in "$proj/.harness/runs"/*/; do
    d=${d%/}
    [ -f "$d/run.json" ] && last=$d
  done
  [ -n "$last" ] && [ -f "$last/ledger.jsonl" ] || return 1
  [ "$(jq -r 'select(.kind == "run-end" or .kind == "resume") | "\(.kind) \(.reason // "")"' "$last/ledger.jsonl" 2>/dev/null | tail -n 1)" = "run-end stop" ] || return 1
  for t in $(cd "$proj" && HO_PROJECT_DIR=$proj "$HO_ROOT/bin/harness" tickets ids in-progress 2>/dev/null); do
    if [ -f "$last/orch/$t.json" ]; then printf '%s\n' "$last"; return 0; fi
  done
  return 1
}

# ho_orch_newest: the newest run folder of this project, ended or not.
ho_orch_newest() {
  local d last="" proj
  proj=$(ho_project_root) || return 66
  for d in "$proj/.harness/runs"/*/; do d=${d%/}; [ -f "$d/run.json" ] && last=$d; done
  [ -n "$last" ] && printf '%s\n' "$last"
}

ho_orch_flow() {
  local f
  f=$(ho_cfg '.flow.use' '') || return 78
  [ -n "$f" ] || { ho_orch_err "no flow is selected (flow.use); run /harness:config"; return 78; }
  printf '%s\n' "$f"
}

# ho_orch_prompt <role> <out>: the static session prompt with the engine path filled in.
ho_orch_prompt() {
  local h="$HO_ROOT/bin/harness"
  sed "s|@HARNESS@|$(printf '%s' "$h" | sed 's/[|&\\]/\\&/g')|g" "$HO_ROOT/prompts/$1.md" | ho_atomic_write "$2"
}

# ---- start --------------------------------------------------------------------------------

ho_orch_watch_start() {
  ho_orch_h watch "$HO_RUN_DIR" pid-check >/dev/null 2>&1 && return 0
  mkdir -p "$HO_RUN_DIR/logs"
  # Detached from this shell: the watch script lives until the run ends (D32).
  ( HO_PROJECT_DIR=$HO_PROJECT_DIR nohup "$HO_ROOT/bin/harness" watch "$HO_RUN_DIR" loop \
      >> "$HO_RUN_DIR/logs/watch.log" 2>&1 < /dev/null & )
  echo "watch started"
}

# ho_orch_orchestrator: launch the orchestrator unless one of this run is alive.
ho_orch_orchestrator() {
  local f name live
  for f in "$HO_RUN_DIR"/sessions/*.json; do
    [ -f "$f" ] || continue
    [ "$(jq -r '.role // ""' "$f" 2>/dev/null)" = orchestrator ] || continue
    name=$(jq -r .name "$f")
    live=$(ho_orch_h session "$HO_RUN_DIR" status "$name" 2>/dev/null | jq -r '.liveness // "unknown"') || live=unknown
    case $live in working | starting) echo "orchestrator $name"; return 0 ;; esac
  done
  if ho_orch_known; then
    # A dead orchestrator of this run comes back the one restart way (D23): resume by ID, else
    # the handoff prompt, within the hourly cap.
    ho_orch_h watch "$HO_RUN_DIR" restart
    return $?
  fi
  ho_orch_h session "$HO_RUN_DIR" launch --role orchestrator --name orchestrator --cwd "$HO_PROJECT_DIR" \
    --prompt "$HO_RUN_DIR/handoff.md" >/dev/null || return $?
  echo "orchestrator orchestrator"
}
ho_orch_known() {
  local f
  for f in "$HO_RUN_DIR"/sessions/*.json; do
    [ -f "$f" ] && [ "$(jq -r '.role // ""' "$f" 2>/dev/null)" = orchestrator ] && return 0
  done
  return 1
}

ho_orch_start() {
  local -a newargs=()
  local last rc=0 flow base run st=0
  while [ $# -gt 0 ]; do
    case $1 in
      --workers | --standby) [ $# -ge 2 ] || { ho_orch_usage; return 64; }; newargs+=("$1" "$2"); shift 2 ;;
      *) ho_orch_usage; return 64 ;;
    esac
  done
  HO_PROJECT_DIR=$(ho_project_root) || { ho_orch_err "no project here (no .harness folder)"; return 66; }
  export HO_PROJECT_DIR
  # D32, H-088: the next start resumes the last unfinished run without asking; a stop a person
  # set is lifted only by /harness:resume.
  if last=$(ho_rec_last 2>/dev/null); then
    ( ho_run_open "$last" >/dev/null 2>&1 && ho_stopped >/dev/null 2>&1 ) || st=$?
    if [ "$st" -eq 0 ]; then
      ho_orch_err "run $(basename "$last") is stopped; /harness:resume lifts the stop and continues it"
      return 75
    fi
    echo "resume $last"
    ho_orch_resume "$last"
    return $?
  fi
  # A run that a stop ended may hold tickets in progress; only /harness:resume continues it.
  if last=$(ho_orch_stop_ended 2>/dev/null); then
    ho_orch_err "run $(basename "$last") was stopped and holds unfinished work; /harness:resume continues it"
    return 75
  fi
  # Each start check stops the start with its own exit code; nothing is created before them.
  ho_orch_h config gate || return $?
  flow=$(ho_orch_flow) || return 78
  ho_orch_h flow preflight "$flow" >/dev/null || return $?
  run=$(ho_orch_h run new ${newargs[@]+"${newargs[@]}"}) || return $?
  ho_run_open "$run"
  ho_session_bind_project || return $?
  # D42l: the hooks check names hooks with no time limit; it never stops the start.
  ho_orch_h session "$HO_RUN_DIR" hooks-check >&2 || true
  rc=0; ho_orch_h limits "$HO_RUN_DIR" gate orchestrator >/dev/null || rc=$?
  [ "$rc" -eq 0 ] || { ho_orch_start_refused limits "$rc"; return "$rc"; }
  rc=0; ho_orch_h autonomy "$HO_RUN_DIR" check start || rc=$?
  [ "$rc" -eq 0 ] || { ho_orch_start_refused autonomy "$rc"; return "$rc"; }
  base=$(git -C "$HO_PROJECT_DIR" symbolic-ref -q --short HEAD 2>/dev/null) || { ho_orch_start_refused "no branch checked out" 65; return 65; }
  rc=0; ho_orch_h loop "$HO_RUN_DIR" integration --repo "$HO_PROJECT_DIR" --base "$base" --worktree "$HO_RUN_DIR/integration" >/dev/null || rc=$?
  [ "$rc" -eq 0 ] || { ho_orch_start_refused integration "$rc"; return "$rc"; }
  # D23, D24: the handoff prompt is the orchestrator's whole state outside the engine records;
  # a restart with no resumable session ID starts from it.
  ho_orch_prompt orchestrator "$HO_RUN_DIR/handoff.md" || return 1
  rc=0; ho_orch_orchestrator || rc=$?
  [ "$rc" -eq 0 ] || { ho_orch_start_refused "orchestrator launch" "$rc"; return "$rc"; }
  ho_orch_watch_start
  printf 'run %s\n' "$HO_RUN_DIR"
}

# A start refused after the run was created ends that run, so the next start does not resume a
# run that never passed its checks.
ho_orch_start_refused() {
  ho_ledger_append start-refused check "$1" rc "$2"
  ho_life_end_once start-refused >/dev/null 2>&1 || true
}

# ---- tick: one ticket ---------------------------------------------------------------------

# ho_orch_steps <ticket>: the enabled steps of the ticket's flow, one id TAB when per line.
ho_orch_steps() {
  ho_orch_h flow steps "$(ho_orch_get "$1" flow)" | awk -F '\t' '{ print $2 "\t" $3 }'
}

# ho_orch_next_step <ticket> [after]: the next step to run, or nothing.
ho_orch_next_step() {
  local t=$1 after=${2-} seen=0 id when q
  q=$(ho_orch_get "$t" questions)
  [ -n "$after" ] || seen=1
  while IFS=$'\t' read -r id when; do
    [ -n "$id" ] || continue
    if [ "$seen" -eq 0 ]; then [ "$id" = "$after" ] && seen=1; continue; fi
    [ "$when" = questions ] && [ "$q" != true ] && continue
    printf '%s\n' "$id"; return 0
  done <<EOF
$(ho_orch_steps "$t")
EOF
}

# ho_orch_session <base>: the newest open session of that base name (a recovery or a reopen
# launches it again under a longer name: <base>-r<n>, <base>-o<n>).
ho_orch_session() {
  local f best="" bt=-1 t n
  [ -n "${1-}" ] || return 0
  for f in "$HO_RUN_DIR"/sessions/"$1".json "$HO_RUN_DIR"/sessions/"$1"-*.json; do
    [ -f "$f" ] || continue
    n=$(basename "$f" .json)
    case $n in "$1" | "$1"-r[0-9]* | "$1"-o[0-9]*) ;; *) continue ;; esac
    # An open record beats a closed one; among equals the newest launch wins.
    t=$(jq -r '(if (.status // "") == "closed" then 0 else 10000000000 end) + ((.created // "1970-01-01T00:00:00Z") | try fromdateiso8601 catch 0)' "$f" 2>/dev/null) || t=0
    [ "$t" -ge "$bt" ] && { best=$n; bt=$t; }
  done
  printf '%s\n' "$best"
}

ho_orch_text() { # <ticket>: the ticket text exactly as "tickets fence" prints it
  ho_orch_h intake "$HO_RUN_DIR" text "$1" | sed '1{/^### Ticket /d;}'
}

ho_orch_claim() {
  local t=$1 lane wt branch flow title d
  if [ -f "$(ho_orch_rec "$t")" ]; then ho_orch_rearm "$t"; return; fi
  lane=$(ho_orch_lane "$t")
  d="$(ho_orch_dir)/$t"
  mkdir -p "$d" || return 1
  wt="$HO_RUN_DIR/worktrees/$lane"
  branch="harness/$HO_RUN_ID/$lane"
  flow=$(ho_orch_flow) || return 78
  title=$(ho_orch_text "$t" | sed -n 's/^Title: //p' | head -n 1)
  local ibr
  ibr=$(jq -r .branch "$HO_RUN_DIR/integration.json")
  mkdir -p "$HO_RUN_DIR/worktrees"
  if [ ! -d "$wt" ]; then
    git -C "$HO_PROJECT_DIR" worktree add -q -b "$branch" "$wt" "$ibr" >/dev/null 2>&1 \
      || { ho_orch_err "cannot create the worktree of ticket $t"; return 1; }
  fi
  jq -n --arg t "$t" --arg lane "$lane" --arg wt "$wt" --arg br "$branch" --arg base "$ibr" --arg flow "$flow" --arg title "${title:-ticket $t}" \
    --arg bsha "$(git -C "$wt" rev-parse HEAD)" \
    '{schemaVersion: 2, ticket: $t, lane: $lane, worktree: $wt, branch: $br, base: $base, base_sha: $bsha, flow: $flow, title: $title,
      phase: "step", step: "", session: "", questions: false}' | ho_atomic_write "$(ho_orch_rec "$t")" || return 1
  ho_orch_set "$t" '.step = $s' --arg s "$(ho_orch_next_step "$t")" || return 1
  ho_ledger_append orch-claim ticket "$t" lane "$lane" flow "$flow"
}

# ho_orch_rearm <ticket>: a ticket of this run that intake hands back (answered, unblocked and
# ready again) continues from the first step whose real result does not exist (H-028, H-033).
ho_orch_rearm() {
  local t=$1 phase steps next id when q
  phase=$(ho_orch_get "$t" phase)
  case $phase in blocked | done) ;; *) return 0 ;; esac
  q=$(ho_orch_get "$t" questions)
  steps=$(ho_orch_steps "$t" | while IFS=$'\t' read -r id when; do
    [ -n "$id" ] || continue
    [ "$when" = questions ] && [ "$q" != true ] && continue
    printf '%s\n' "$id"
  done)
  # shellcheck disable=SC2086 # one step id per word
  next=$(ho_orch_h tickets resume "$t" --repo "$(ho_orch_get "$t" worktree)" $steps 2>/dev/null | head -n 1)
  case $next in
    "next "*) ho_orch_set "$t" '.phase = "step" | .step = $s | .session = "" | .validator = "" | del(.why)' --arg s "${next#next }" ;;
    complete) ho_orch_set "$t" '.phase = "ready" | .session = "" | .validator = "" | del(.why)' ;;
    *) ho_orch_set "$t" '.phase = "step" | .step = $s | .session = "" | .validator = "" | del(.why)' --arg s "$(ho_orch_next_step "$t")" ;;
  esac
  ho_ledger_append orch-rearm ticket "$t" from "$phase" next "${next:-first}"
}

# ho_orch_block <ticket> <state blocked|review> <reason>: the ticket leaves the run's work.
ho_orch_block() {
  local t=$1 how=$2 why=$3 f
  f="$(ho_orch_dir)/$t/why.md"
  printf 'Reason: %s\nNext: A person with write access checks the ticket and sets the ready label to take it again.\n' "$why" > "$f"
  if [ "$how" = review ]; then ho_orch_h tickets review "$t" >/dev/null 2>&1 || true
  else ho_orch_h tickets block "$t" "$f" >/dev/null 2>&1 || true; fi
  ho_orch_set "$t" '.phase = $p | .why = $w' --arg p "$([ "$how" = review ] && echo done || echo blocked)" --arg w "$why"
  ho_ledger_append orch-ticket-left ticket "$t" state "$how" reason "$why"
  printf '%s %s %s\n' "$([ "$how" = review ] && echo needs-review || echo blocked)" "$t" "$why"
}

ho_orch_close() { # <base>: the task of that session ended (H-081)
  local s
  s=$(ho_orch_session "$1")
  [ -n "$s" ] || return 0
  ho_orch_h lifecycle "$HO_RUN_DIR" done "$s" >/dev/null 2>&1 || true
}

ho_orch_launch_step() {
  local t=$1 s=$2 d rc name prompt notes res wt
  d="$(ho_orch_dir)/$t"
  local sbase
  sbase="w$t-$s"
  sbase=${sbase:0:29}
  name=$sbase
  # A step launched again (after an unblock) needs a new name in recovery's -r<n> form; the record
  # keeps the base name, and the newest open session of that base is the step's session.
  [ ! -e "$HO_RUN_DIR/sessions/$name.json" ] || name="$sbase-r$(date +%s)"
  # H-037, H-036: the profile's gate on this step first; a human gate waits, a refusal blocks.
  rc=0; ho_orch_h autonomy "$HO_RUN_DIR" check step --step "$s" --for "$t" >/dev/null 2>&1 || rc=$?
  case $rc in
    0) ;;
    76) echo "wait $t human-gate $s"; return 0 ;;
    77) ho_orch_block "$t" blocked "the autonomy profile does not allow step $s"; return 0 ;;
    *) echo "error $t autonomy-check $s rc $rc"; return 0 ;;
  esac
  rc=0; ho_orch_h limits "$HO_RUN_DIR" gate worker >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || { echo "wait $t limits"; return 0; }
  # The step gate (D25, H-086): a stop refuses the next step; accepted changes come with it (H-023).
  rc=0; notes=$(ho_orch_h state "$HO_RUN_DIR" begin --ticket "$t" --step "$s" 2>/dev/null) || rc=$?
  [ "$rc" -eq 0 ] || { echo "wait $t stopped $s"; return 0; }
  res="$d/$s.result"
  rm -f "$res"
  # Notes handed over by the step gate are kept for this step, so a launch that must wait does
  # not lose them (the gate hands each note over once).
  printf '%s\n' "$notes" | sed -n 's/^change //p' >> "$d/$s.notes"
  wt=$(ho_orch_get "$t" worktree)
  prompt="$d/$s.prompt.md"
  rc=0
  ho_orch_text "$t" > "$d/ticket.txt"
  ho_orch_h flow render "$(ho_orch_get "$t" flow)" worker --step "$s" \
    --set RUN_ID "$HO_RUN_ID" --set TICKET_ID "$t" --file TICKET_TEXT "$d/ticket.txt" \
    --set BRANCH "$(ho_orch_get "$t" branch)" --set BASE "$(ho_orch_get "$t" base)" \
    --set WORKDIR "$wt" --set STEP_RESULT_FILE "$res" > "$prompt" || rc=$?
  [ "$rc" -eq 0 ] || { ho_orch_block "$t" blocked "the worker prompt of step $s cannot be rendered (exit $rc)"; return 0; }
  # Changes accepted since the last step boundary go with the instructions (H-023).
  local line nf
  while IFS= read -r line; do
    case $line in "change "*) nf=${line#change }
      [ -f "$nf" ] && { printf '\n## A change to the ticket, accepted since pickup\n\n'; cat "$nf"; } >> "$prompt" ;;
    esac
  done <<EOF
$(sed 's/^/change /' "$d/$s.notes" 2>/dev/null)
EOF
  rc=0
  ho_orch_h session "$HO_RUN_DIR" launch --role worker --name "$name" --cwd "$wt" --prompt "$prompt" --ticket "$t" >/dev/null 2>"$d/launch.err" || rc=$?
  case $rc in
    0) ho_orch_set "$t" '.session = $n' --arg n "$sbase"; echo "launched $t $s $name" ;;
    73) echo "wait $t worker-slot" ;;
    74 | 75 | 76) echo "wait $t launch-refused $rc" ;;
    *) echo "error $t launch $s rc $rc" ;;
  esac
}

# A step's result: the first line of the result file (prompts/worker.md, Report).
ho_orch_step_result() {
  local t=$1 s=$2 res first next base
  res="$(ho_orch_dir)/$t/$s.result"
  base=$(ho_orch_get "$t" session)
  if [ ! -f "$res" ] || [ -L "$res" ]; then
    local live
    live=$(ho_orch_h session "$HO_RUN_DIR" status "$(ho_orch_session "$base")" 2>/dev/null | jq -r '.liveness // "unknown"') || live=unknown
    case $live in
      dead | closed | unknown) echo "attention $t $(ho_orch_session "$base") $live" ;;
      *) echo "working $t $s" ;;
    esac
    return 0
  fi
  first=$(head -n 1 "$res" | tr -d '\r')
  case $first in
    pass | questions)
      [ "$first" = questions ] && ho_orch_set "$t" '.questions = true'
      # H-028, D2: the step's real result is the worktree's commit after the step.
      ho_orch_h tickets step "$t" "$s" "commit:$(git -C "$(ho_orch_get "$t" worktree)" rev-parse HEAD)" >/dev/null 2>&1 || true
      ho_orch_close "$base"
      next=$(ho_orch_next_step "$t" "$s")
      if [ -n "$next" ]; then
        ho_orch_set "$t" '.step = $s | .session = "" | .last_worker = $w' --arg s "$next" --arg w "$(ho_orch_session "$base")"
      else
        ho_orch_set "$t" '.phase = "ready" | .session = "" | .last_worker = $w' --arg w "$(ho_orch_session "$base")"
      fi
      echo "step-done $t $s"
      ;;
    blocked:*)
      ho_orch_close "$base"
      printf '1. %s\n' "${first#blocked: }" > "$(ho_orch_dir)/$t/questions.md"
      # The worker asked: the question is recorded as the worker's, never the orchestrator's (the
      # next poll closes the asking session, H-032).
      local ws
      ws=$(ho_orch_session "$base")
      HO_SESSION_NAME=$ws HO_SESSION_ID=$(jq -r '.session_id // ""' "$HO_RUN_DIR/sessions/$ws.json" 2>/dev/null) HO_SESSION_ROLE=worker HO_RUN_DIR=$HO_RUN_DIR \
        ho_orch_h tickets ask "$t" "$(ho_orch_dir)/$t/questions.md" >/dev/null 2>&1 || true
      ho_orch_set "$t" '.phase = "blocked" | .why = $w' --arg w "step $s: $first"
      ho_ledger_append orch-ticket-left ticket "$t" state blocked reason "step $s asked a question"
      echo "blocked $t step $s asked a question"
      ;;
    fail:* | *)
      ho_orch_close "$base"
      ho_orch_block "$t" blocked "step $s did not pass: ${first:0:200}"
      ;;
  esac
}

# ready: the finalize commit and "loop ready" (Rebuild: the finalize commit is the only
# completion signal; agent decision: the engine writes it after the last pass).
ho_orch_ready() {
  local t=$1 lane wt w sid subj rc=0
  lane=$(ho_orch_get "$t" lane); wt=$(ho_orch_get "$t" worktree)
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    ho_orch_block "$t" blocked "the worker left uncommitted changes after the last step"; return 0
  fi
  subj=$(git -C "$wt" log -1 --format=%s 2>/dev/null)
  case $subj in
    "finalize($lane):"*) ;;
    *) git -C "$wt" commit -q --allow-empty -m "finalize($lane): every step of flow $(ho_orch_get "$t" flow) passed" \
         || { ho_orch_block "$t" blocked "the finalize commit failed"; return 0; } ;;
  esac
  w=$(ho_orch_get "$t" last_worker)
  sid=$(jq -r '.session_id // ""' "$HO_RUN_DIR/sessions/$w.json" 2>/dev/null)
  HO_SESSION_NAME=$w HO_SESSION_ID=$sid ho_orch_h loop "$HO_RUN_DIR" ready "$lane" --worktree "$wt" --ticket "$t" >/dev/null 2>&1 || rc=$?
  case $rc in
    0) ho_orch_set "$t" '.phase = "validate" | .sha = $s' --arg s "$(git -C "$wt" rev-parse HEAD)"; echo "ready $t $lane" ;;
    75) echo "wait $t stopped ready" ;;
    *) ho_orch_block "$t" blocked "loop ready refused the lane (exit $rc)" ;;
  esac
}

ho_orch_validate() {
  local t=$1 lane sha d vf base name rc first
  lane=$(ho_orch_get "$t" lane); sha=$(ho_orch_get "$t" sha); d="$(ho_orch_dir)/$t"
  vf="$HO_RUN_DIR/verdicts/$lane/$sha.json"
  base=$(ho_orch_get "$t" validator)
  if [ -f "$vf" ] && [ ! -L "$vf" ]; then
    first=$(jq -r '.text | split("\n")[0]' "$vf" 2>/dev/null)
    ho_orch_close "$base"
    case $first in
      passed) ho_orch_set "$t" '.phase = "merge"'; echo "verdict $t passed" ;;
      "passed with remarks")
        local rout
        rc=0; rout=$(ho_orch_h verify "$HO_RUN_DIR" remarks "$lane" 2>/dev/null) || rc=$?
        # Agent decision: the wiring runs no remarks fix round yet; a round the profile opens goes
        # to a person, as remarks: human does (H-058).
        if [ "$rc" -eq 0 ] && [ "${rout#clean:}" != "$rout" ]; then ho_orch_set "$t" '.phase = "merge"'; echo "verdict $t passed"
        else ho_orch_block "$t" review "the verdict has remarks for a person"; fi ;;
      *) ho_orch_block "$t" blocked "the validator verdict is not a pass: ${first:0:200}" ;;
    esac
    return 0
  fi
  if [ -n "$base" ]; then
    local live
    live=$(ho_orch_h session "$HO_RUN_DIR" status "$(ho_orch_session "$base")" 2>/dev/null | jq -r '.liveness // "unknown"') || live=unknown
    case $live in
      dead | closed)
        # Recovery covers workers only; a validator that stopped with no verdict is replaced by a
        # fresh one, at most twice (D37-VERIFICATION-6: a fresh validator judges).
        if [ "$(ho_orch_get "$t" validator_runs)" -ge 3 ] 2>/dev/null; then
          ho_orch_block "$t" blocked "three validator sessions ended with no verdict"
        else
          ho_orch_set "$t" '.validator = ""'; echo "attention $t $(ho_orch_session "$base") $live validator replaced"
        fi ;;
      unknown) echo "attention $t $(ho_orch_session "$base") $live" ;;
      *) echo "validating $t" ;;
    esac
    return 0
  fi
  local runs
  runs=$(ho_orch_get "$t" validator_runs); runs=$(( ${runs:-0} + 1 ))
  name="v$t"
  [ "$runs" -eq 1 ] || name="v$t-$runs"
  ho_orch_text "$t" > "$d/ticket.txt"
  rc=0
  ho_orch_h flow render "$(ho_orch_get "$t" flow)" validator \
    --set RUN_ID "$HO_RUN_ID" --set TICKET_ID "$t" --file TICKET_TEXT "$d/ticket.txt" \
    --set BRANCH "$(ho_orch_get "$t" branch)" --set BASE "$(ho_orch_get "$t" base)" \
    --set WORKDIR "$(ho_orch_get "$t" worktree)" --set VERDICT_FILE "$d/verdict.md" \
    --set LANE "$lane" --set SHA "$sha" > "$d/validator.prompt.md" || rc=$?
  [ "$rc" -eq 0 ] || { ho_orch_block "$t" blocked "the validator prompt cannot be rendered (exit $rc)"; return 0; }
  rc=0
  ho_orch_h session "$HO_RUN_DIR" launch --role validator --name "$name" --cwd "$(ho_orch_get "$t" worktree)" \
    --prompt "$d/validator.prompt.md" --ticket "$t" >/dev/null 2>"$d/launch.err" || rc=$?
  case $rc in
    0) ho_orch_set "$t" '.validator = $n | .validator_runs = ($r | tonumber)' --arg n "$name" --arg r "$runs"; echo "launched $t validator $name" ;;
    73 | 74 | 75 | 76) echo "wait $t validator-launch $rc" ;;
    *) echo "error $t validator launch rc $rc" ;;
  esac
}

ho_orch_merge() {
  local t=$1 lane rc=0
  lane=$(ho_orch_get "$t" lane)
  # D12: the profile decides whether even the local integration merge runs.
  ho_orch_h autonomy "$HO_RUN_DIR" check merge --for "$t" --local >/dev/null 2>&1 || rc=$?
  case $rc in
    0) ;;
    76) echo "wait $t human-gate merge"; return 0 ;;
    *) ho_orch_end "$t"; return 0 ;;
  esac
  rc=0; ho_orch_h loop "$HO_RUN_DIR" merge "$lane" >/dev/null 2>"$(ho_orch_dir)/$t/merge.err" || rc=$?
  case $rc in
    0) ho_orch_set "$t" '.phase = "ship"'; echo "merged $t $lane" ;;
    75) echo "wait $t stopped merge" ;;
    *) ho_orch_block "$t" blocked "the engine-checked merge refused the lane (exit $rc: $(tail -n 1 "$(ho_orch_dir)/$t/merge.err" | cut -c1-160))" ;;
  esac
}

# The ticket's end when the profile stops before a remote merge (H-042): needs-review.
ho_orch_end() {
  local t=$1
  ho_orch_h autonomy "$HO_RUN_DIR" end "$t" >/dev/null 2>&1 || true
  ho_orch_set "$t" '.phase = "done"'
  ho_ledger_append orch-ticket-end ticket "$t" state "$(ho_orch_ticket_state "$t")"
  echo "end $t $(ho_orch_ticket_state "$t")"
}
ho_orch_ticket_state() {
  local s
  for s in done needs-review in-progress blocked ready; do
    ho_orch_h tickets ids "$s" 2>/dev/null | grep -qx "$1" && { echo "$s"; return 0; }
  done
  echo unknown
}

# The merge facts, from the engine's own records (agent decision; issue #110 "merge facts come
# from a caller-supplied file").
ho_orch_facts() {
  local t=$1 lane sha pr out vf tests ci paths
  lane=$(ho_orch_get "$t" lane); sha=$(ho_orch_get "$t" sha)
  out="$(ho_orch_dir)/$t/facts.json"
  vf="$HO_RUN_DIR/verdicts/$lane/$sha.json"
  pr=$(jq -r '.pr // ""' "$HO_RUN_DIR/ship/$lane.json" 2>/dev/null)
  # The newest "tests" record for the lane's commit (lib/verify.sh writes the counts as its proof).
  tests=$(jq -sc --arg sha "$sha" 'map(select(.sha == $sha and .check == "tests")) | last
    | if . == null then null
      else ((.proof // "") | capture("(?<p>[0-9]+) passed, (?<f>[0-9]+) failed, (?<s>[0-9]+) skipped of (?<t>[0-9]+)")? // null) as $c
        | if $c != null then {total: ($c.t | tonumber), failed: ($c.f | tonumber)}
          elif .result == "passed" then {total: 0, failed: 0} else null end end' "$HO_RUN_DIR/verify/$lane.jsonl" 2>/dev/null) || tests=null
  ci=$(gh pr view "$pr" --json statusCheckRollup $(ho_ship_gh_repo) 2>/dev/null \
    | jq -r '(.statusCheckRollup // []) as $c | if ($c | length) > 0 and ($c | all((.conclusion // .state // "") | ascii_upcase | IN("SUCCESS", "NEUTRAL", "SKIPPED"))) then "green" else "unknown" end' 2>/dev/null) || ci=unknown
  paths=$(git -C "$(ho_orch_get "$t" worktree)" diff --name-only "$(ho_orch_get "$t" base_sha)" "$sha" 2>/dev/null | jq -Rsc 'split("\n") | map(select(length > 0))') || paths=null
  jq -n --arg v "$(jq -r '.text | split("\n")[0]' "$vf" 2>/dev/null)" --argjson tests "${tests:-null}" --arg ci "$ci" --argjson paths "${paths:-null}" \
    '{validator: $v, tests: $tests, ci: $ci, open_questions: 0, paths: $paths}' > "$out"
  printf '%s\n' "$out"
}

ho_orch_ship() {
  local t=$1 lane rc=0 merge
  lane=$(ho_orch_get "$t" lane)
  if [ ! -f "$HO_RUN_DIR/ship/$lane.json" ] || [ -z "$(jq -r '.pushed // .branch // ""' "$HO_RUN_DIR/ship/$lane.json" 2>/dev/null)" ]; then
    ho_orch_h ship "$HO_RUN_DIR" push "$lane" --ticket "$t" --title "$(ho_orch_get "$t" title)" >/dev/null 2>"$(ho_orch_dir)/$t/ship.err" || rc=$?
    case $rc in
      0) echo "pushed $t" ;;
      77) ho_orch_end "$t"; return 0 ;;
      75 | 76) echo "wait $t ship-push $rc"; return 0 ;;
      *) ho_orch_block "$t" blocked "ship push failed (exit $rc: $(tail -n 1 "$(ho_orch_dir)/$t/ship.err" | cut -c1-160))"; return 0 ;;
    esac
  fi
  if [ -z "$(jq -r '.pr // ""' "$HO_RUN_DIR/ship/$lane.json" 2>/dev/null)" ]; then
    rc=0; ho_orch_h ship "$HO_RUN_DIR" pr "$lane" >/dev/null 2>"$(ho_orch_dir)/$t/ship.err" || rc=$?
    case $rc in
      0) echo "pr $t #$(jq -r '.pr' "$HO_RUN_DIR/ship/$lane.json")" ;;
      77) ho_orch_end "$t"; return 0 ;;
      75 | 76) echo "wait $t ship-pr $rc"; return 0 ;;
      *) ho_orch_block "$t" blocked "ship pr failed (exit $rc: $(tail -n 1 "$(ho_orch_dir)/$t/ship.err" | cut -c1-160))"; return 0 ;;
    esac
  fi
  merge=$(ho_orch_h autonomy show 2>/dev/null | jq -r '.merge // "never"')
  [ "$merge" != never ] || { ho_orch_end "$t"; return 0; }
  rc=0; ho_orch_h ship "$HO_RUN_DIR" merge "$lane" --facts "$(ho_orch_facts "$t")" >/dev/null 2>"$(ho_orch_dir)/$t/ship.err" || rc=$?
  case $rc in
    0) ho_orch_set "$t" '.phase = "done"'; echo "end $t done" ;;
    75) echo "wait $t stopped ship-merge" ;;
    *) ho_orch_set "$t" '.phase = "wait-merge"'; echo "wait $t merge $(tail -n 1 "$(ho_orch_dir)/$t/ship.err" | cut -c1-160)" ;;
  esac
}

# A PR that waits: a profile that merges tries again with fresh facts (CI may turn green later);
# otherwise each tick asks git whether a person merged it (H-046).
ho_orch_wait_merge() {
  local t=$1 rc=0 lane
  lane=$(ho_orch_get "$t" lane)
  if [ "$(ho_orch_h autonomy show 2>/dev/null | jq -r '.merge // "never"')" != never ] \
      && [ "$(jq -r '.merged // ""' "$HO_RUN_DIR/ship/$lane.json" 2>/dev/null)" = "" ]; then
    ho_orch_h ship "$HO_RUN_DIR" merge "$lane" --facts "$(ho_orch_facts "$t")" >/dev/null 2>"$(ho_orch_dir)/$t/ship.err" || rc=$?
    case $rc in
      0) ho_orch_set "$t" '.phase = "done"'; echo "end $t done" ;;
      *) echo "wait $t merge $(tail -n 1 "$(ho_orch_dir)/$t/ship.err" | cut -c1-160)" ;;
    esac
    return 0
  fi
  ho_orch_h ship "$HO_RUN_DIR" merged "$lane" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then ho_orch_set "$t" '.phase = "done"'; echo "end $t done"; else echo "wait $t merge by a person"; fi
}

ho_orch_advance() {
  local t=$1 phase s
  phase=$(ho_orch_get "$t" phase)
  case $phase in
    step)
      s=$(ho_orch_get "$t" step)
      if [ -z "$s" ]; then ho_orch_set "$t" '.phase = "ready"'; ho_orch_ready "$t"; return; fi
      if [ -z "$(ho_orch_get "$t" session)" ]; then ho_orch_launch_step "$t" "$s"
      else ho_orch_step_result "$t" "$s"; fi ;;
    ready) ho_orch_ready "$t" ;;
    validate) ho_orch_validate "$t" ;;
    merge) ho_orch_merge "$t" ;;
    ship) ho_orch_ship "$t" ;;
    wait-merge) ho_orch_wait_merge "$t" ;;
    *) ;;
  esac
}

# ---- tick ----------------------------------------------------------------------------------

# The context watcher (H-098, D32, D37-SESSIONS-4): the orchestrator starts it and starts it
# again when it stopped. It watches the orchestrator; prompts/watcher.md.
ho_orch_watcher() {
  local s live
  s=$(ho_orch_session watcher)
  if [ -n "$s" ]; then
    live=$(ho_orch_h session "$HO_RUN_DIR" status "$s" 2>/dev/null | jq -r '.liveness // "unknown"') || live=unknown
    case $live in working | starting | unknown) return 0 ;; esac
  fi
  ho_stopped >/dev/null 2>&1 && return 0
  local n=watcher rc=0
  [ -s "$HO_RUN_DIR/watcher.md" ] || ho_orch_prompt watcher "$HO_RUN_DIR/watcher.md" || return 1
  [ -z "$s" ] || n="watcher-r$(date +%s)"
  ho_orch_h session "$HO_RUN_DIR" launch --role watcher --name "$n" --cwd "$HO_PROJECT_DIR" --prompt "$HO_RUN_DIR/watcher.md" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] && echo "watcher $n" || echo "wait watcher-launch $rc"
}

# ho_orch_free: worker places left for new tickets. A ticket between two steps holds no worker
# session, so intake's own count of free slots would take one ticket too many (H-105).
ho_orch_free() {
  local cap n=0 f
  cap=$(ho_orch_h slot "$HO_RUN_DIR" limits 2>/dev/null | jq -r '.workers // 1') || cap=1
  for f in "$(ho_orch_dir)"/*.json; do
    [ -f "$f" ] || continue
    case $(jq -r '.phase // ""' "$f") in done | blocked) ;; *) n=$((n + 1)) ;; esac
  done
  [ "$cap" -gt "$n" ] 2>/dev/null && echo $((cap - n)) || echo 0
}

ho_orch_tick() {
  local line t rc f life
  if ho_run_ended; then echo ended; return 0; fi
  mkdir -p "$(ho_orch_dir)"
  ho_orch_watcher
  ho_orch_h watch "$HO_RUN_DIR" pid-check >/dev/null 2>&1 || ho_orch_watch_start
  ho_orch_h limits "$HO_RUN_DIR" check >/dev/null 2>&1 || true
  # Intake: ready tickets up to the free worker slots (H-002, H-003, H-012).
  rc=0
  while IFS= read -r line; do
    case $line in
      "start "* | "resume "*) t=${line#* }; ho_orch_claim "$t" && echo "${line%% *} $t" || echo "error $t claim" ;;
      "") ;;
      *) echo "intake $line" ;;
    esac
  done < <(ho_orch_h intake "$HO_RUN_DIR" tick --max "$(ho_orch_free)" || echo "intake-exit $?")
  # Each taken ticket moves at most one move per tick (one bounded pass).
  for f in "$(ho_orch_dir)"/*.json; do
    [ -f "$f" ] || continue
    t=$(basename "$f" .json)
    case $(ho_orch_get "$t" phase) in done | blocked) continue ;; esac
    ho_orch_advance "$t"
  done
  # Recovery of stopped sessions (H-088, D20): the engine's fixed order.
  ho_orch_h recover "$HO_RUN_DIR" tick 2>/dev/null | sed -n 's/^/recover /p' || true
  life=$(ho_orch_h lifecycle "$HO_RUN_DIR" check | head -n 1) || true
  echo "lifecycle ${life:-unknown}"
  # The check never closes the session that calls it. When the orchestrator itself sees the end,
  # a detached check closes it a little later, after its turn ends (D37-LIFECYCLE-3).
  case $life in end | ended)
    if [ -n "${HO_SESSION_NAME-}" ]; then
      ( sleep 5
        env -u HO_SESSION_NAME -u HO_SESSION_ID -u HO_SESSION_ROLE HO_PROJECT_DIR="$HO_PROJECT_DIR" \
          "$HO_ROOT/bin/harness" lifecycle "$HO_RUN_DIR" check ) >/dev/null 2>&1 < /dev/null &
    fi ;;
  esac
}

# ---- wait ----------------------------------------------------------------------------------

ho_orch_wait() {
  local max=${1:-60} n=0 iv
  iv=$(ho_orch_h intake "$HO_RUN_DIR" interval --next 2>/dev/null) || iv=60
  [ "$iv" -lt "$max" ] 2>/dev/null || iv=$max
  while [ "$n" -lt "$iv" ]; do
    ho_run_ended && { echo ended; return 0; }
    ho_stopped >/dev/null 2>&1 && { echo stopped; return 0; }
    sleep 1; n=$((n + 1))
  done
  echo due
}

# ---- status ------------------------------------------------------------------------------

ho_orch_status() {
  local f t st
  printf 'run %s (%s)\n' "$HO_RUN_ID" "$HO_RUN_DIR"
  if ho_run_ended; then echo "state: ended"; else
    st=$(ho_orch_h state "$HO_RUN_DIR" stop-state 2>/dev/null) || st=""
    printf 'stop: %s\n' "${st:-none}"
  fi
  echo "sessions:"
  ho_orch_h session "$HO_RUN_DIR" list 2>/dev/null | sed 's/^/  /'
  echo "tickets:"
  for f in "$(ho_orch_dir)"/*.json; do
    [ -f "$f" ] || continue
    t=$(basename "$f" .json)
    jq -r '"  \(.ticket) \(.phase)\(if .phase == "step" then " " + .step else "" end) lane \(.lane)\(if .why then " (" + .why + ")" else "" end)"' "$f"
  done
  echo "merges:"
  ho_orch_h loop "$HO_RUN_DIR" status 2>/dev/null | sed 's/^/  /'
  echo "limits:"
  ho_orch_h limits "$HO_RUN_DIR" status 2>/dev/null | sed 's/^/  /'
  echo "owner actions:"
  ho_ledger_events | jq -r 'select(.kind == "owner-action") | "  \(.title): \(.command)"'
}

# ---- stop ----------------------------------------------------------------------------------

ho_orch_stop() {
  local out rc=0 id type sid text other covered name tk
  out=$(ho_orch_h state "$HO_RUN_DIR" stop "$@") || rc=$?
  printf '%s\n' "$out"
  [ "$rc" -eq 0 ] || return "$rc"
  id=$(printf '%s\n' "$out" | sed -n 's/^stop \(stop-[0-9a-f]*\) \([a-z:]*\) .*/\1/p' | head -n 1)
  type=$(printf '%s\n' "$out" | sed -n 's/^stop stop-[0-9a-f]* \([a-z:]*\) .*/\1/p' | head -n 1)
  case $type in soft:*) ;; *) return 0 ;; esac
  text=$(printf '%s\n' "$out" | sed -n 's/^text: //p; s/^text (tickets [^)]*): //p' | head -n 1)
  other=$(printf '%s\n' "$out" | sed -n 's/^text (other tickets): //p' | head -n 1)
  covered=$(printf '%s\n' "$out" | sed -n 's/^stop stop-[0-9a-f]* [a-z:]* tickets //p' | head -n 1)
  # H-085: the stop text goes to every session the stop covers, by the same route; the
  # orchestrator and the watcher stay (they stop nothing themselves).
  for name in $(ho_stop_sessions); do
    case $(jq -r '.role // ""' "$HO_RUN_DIR/sessions/$name.json") in worker | validator) ;; *) continue ;; esac
    tk=$(jq -r '.ticket // "" | tostring' "$HO_RUN_DIR/sessions/$name.json")
    sid=$text
    if [ -n "$other" ] && [ "$covered" != all ] && ! printf '%s\n' $covered | grep -qx "$tk"; then sid=$other; fi
    # One instruction id per session (an id is used once in a run); each starts with the stop id.
    rc=0; ho_orch_h session "$HO_RUN_DIR" deliver "$name" --text "$sid" --id "$(printf '%s-%s' "$id" "$name" | cut -c1-40 | sed 's/-*$//')" >/dev/null || rc=$?
    printf 'delivered %s rc %s\n' "$name" "$rc"
  done
}

# ---- resume ------------------------------------------------------------------------------

ho_orch_resume() {
  local yes=() rc=0
  [ "${2-}" = --yes ] && yes=(--yes)
  ho_orch_bind "$1" || return $?
  if ho_run_ended && [ "$(ho_ledger_events | jq -r 'select(.kind == "run-end") | .reason // ""' | tail -n 1)" != stop ]; then
    ho_orch_err "run $HO_RUN_ID has ended; start a new one with /harness:run"; return 75
  fi
  ho_orch_h config gate || return $?
  ho_orch_h state "$HO_RUN_DIR" resume || return $?
  ho_orch_h recover "$HO_RUN_DIR" reopen ${yes[@]+"${yes[@]}"} || { rc=$?; return "$rc"; }
  [ -s "$HO_RUN_DIR/handoff.md" ] || ho_orch_prompt orchestrator "$HO_RUN_DIR/handoff.md" || return 1
  ho_orch_orchestrator || return $?
  ho_orch_watch_start
  printf 'run %s\n' "$HO_RUN_DIR"
}

ho_orch_usage() {
  cat >&2 <<'USAGE'
usage: harness run new [--workers N] [--standby on|off]   create a stamped run (no session)
       harness run start [--workers N] [--standby on|off]
                      every start check, a new run (or the unfinished last run, resumed), its
                      integration branch, the orchestrator session and the watch script
       harness run tick <run-dir>     one pass of the run loop (the orchestrator calls it)
       harness run wait <run-dir> [max-seconds]
                                      sleep until the next tick is due (due, stopped, ended)
       harness run status [run-dir]   read only: run, stop, sessions, tickets, merges, limits
       harness run stop [run-dir] [--type T] [--ticket ID]... [--message TEXT] [reason]
                                      record a stop; a soft stop's text goes to each session it covers
       harness run resume [run-dir] [--yes]
                                      lift the stop, reopen sessions, orchestrator and watch script run
exit: 64 usage, 66 no project or no unfinished run, 73 config gate, 74 limits gate,
      75 stopped or ended, 76/77 autonomy, 78 config error
USAGE
}

ho_orch_main() {
  local verb=${1-} run rc=0
  [ $# -gt 0 ] && shift
  case $verb in
    new) ho_run_new "$@" ;;
    start) ho_orch_start "$@" || rc=$? ;;
    tick | wait)
      [ $# -ge 1 ] || { ho_orch_usage; exit 64; }
      ho_orch_bind "$1" || exit $?
      shift
      if [ "$verb" = tick ]; then ho_orch_tick || rc=$?; else ho_orch_wait "$@" || rc=$?; fi ;;
    status)
      HO_PROJECT_DIR=${HO_PROJECT_DIR:-$(ho_project_root 2>/dev/null || true)}
      run=$(ho_orch_run_arg "${1-}" 2>/dev/null || ho_orch_newest) || { ho_orch_err "no run in this project"; exit 66; }
      ho_orch_bind "$run" || exit $?
      ho_orch_status || rc=$? ;;
    stop)
      run=""
      case ${1-} in /* | ./* | ../*) run=$1; shift ;; esac
      HO_PROJECT_DIR=${HO_PROJECT_DIR:-$(ho_project_root 2>/dev/null || true)}
      run=$(ho_orch_run_arg "$run") || exit 66
      ho_orch_bind "$run" || exit $?
      ho_orch_stop "$@" || rc=$? ;;
    resume)
      run=""
      case ${1-} in /* | ./* | ../*) run=$1; shift ;; esac
      HO_PROJECT_DIR=${HO_PROJECT_DIR:-$(ho_project_root 2>/dev/null || true)}
      run=$(ho_orch_resume_arg "$run") || exit 66
      ho_orch_resume "$run" "$@" || rc=$? ;;
    *) ho_orch_usage; exit 64 ;;
  esac
  exit "$rc"
}
