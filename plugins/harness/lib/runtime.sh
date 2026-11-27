# shellcheck shell=bash
# Runtime profiles, the per-step launch plan and the start check (H-073, H-075, H-078, H-102;
# tasks 19.1; D30, D31, D37-RUNTIME-1, D37-RUNTIME-2, D37-RUNTIME-3).
#
# A runtime profile is one data file per tool: runtimes/<label>.json. It is read from the
# user folder ($HO_USER_DIR/runtimes) first, then from the plugin's runtimes/ folder, and
# never from a project (D37-FLOW-8: it holds launch lines). Engine code names no runtime; a
# flow step names a label, and a step without one uses config runtime.main.
#
#   "modes"          ["interactive", "noninteractive"]: what the tool can run.
#   "argv"           interactive launch: new, resume, model, title, prompt (lib/sessions.sh)
#   "noninteractive" {"argv": [...], "prompt": [...], "resume": [...]}: launch without a terminal
#   "sandbox"        {"read-only": [...]}: flags for a review step that runs without a terminal;
#                    "no-tools": [...] runs with no tool at all (the readiness judge, lib/intake.sh)
#   "skill_call", "session_log", "limits", "capabilities": the other D31 fields (data only here)
#   "config_dir"     {"env": "<VAR>", "default": "{home}/..."}: the tool's own folder
#   "check"          {"argv": [...], "expect": "<regex>", "timeout_seconds": n}: present and
#                    logged in when it exits 0 within the time and, if set, prints a match
#   "skill_paths"    path patterns ({config_dir}, {home}, {skill}); "plugin_skill_paths" for a
#                    "plugin:name" skill ({plugin}, {name}). A skill is installed when one matches.
#   "agent_paths"    path patterns ({config_dir}, {home}, {agent}) for an agent a flow names.
#   "install"        the install and login step to print. Nothing is ever installed.
#
# Mode (D30, H-102): a step runs interactively in a terminal when its runtime can. Otherwise
# it runs without a terminal: a review step (kind "review") runs read-only; any other step is
# the stated exception of D37-RUNTIME-2 and is marked experimental.
#
# Requires lib/common.sh, lib/config.sh, lib/flow.sh and lib/sessions.sh (account and binary
# guards). Exit codes: 78 config or profile error, 69 the start check found missing items.

HO_EXIT_UNAVAILABLE=69

# ho_rt_file <label>: print the runtime profile file for a label (user folder first).
ho_rt_file() {
  local label=${1-} udir f
  case $label in
    '' | -* | *[!a-z0-9-]*) printf 'harness: bad runtime name [%s]: use a-z, 0-9 and -\n' "$label" >&2; exit "$HO_EXIT_FLOW" ;;
  esac
  udir=$(dirname "$(ho_user_config)")
  for f in "$udir/runtimes/$label.json" "$HO_ROOT/runtimes/$label.json"; do
    [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
  done
  printf 'harness: runtime profile %s not found (looked in %s/runtimes and %s/runtimes; a project cannot add one)\n' \
    "$label" "$udir" "$HO_ROOT" >&2
  exit "$HO_EXIT_FLOW"
}

# ho_rt_check <file>: exit 78 unless the file is a whole runtime profile.
ho_rt_check() {
  local f=$1 why
  why=$(jq -rs '
    def strs: type == "array" and all(type == "string" and (test("[[:cntrl:]]") | not));
    def line: type == "string" and length > 0 and (test("[[:cntrl:]]") | not);
    if length != 1 then "the file must hold exactly one JSON object" else .[0] |
    if type != "object" then "not a JSON object"
    elif .schemaVersion != 2 then "schemaVersion must be 2"
    elif (.command | line | not) then "command must be one line of text"
    elif (.modes | type) != "array" or (.modes | length) == 0 or (.modes | any(IN("interactive", "noninteractive") | not)) then
      "modes must list interactive and/or noninteractive"
    elif (.modes | index("interactive")) != null and ((.argv.new | strs | not) or (.argv.prompt | strs | not)) then
      "an interactive runtime needs argv.new and argv.prompt"
    elif (.modes | index("noninteractive")) != null and ((.noninteractive.argv | strs | not) or (.noninteractive.prompt | strs | not)) then
      "a non-interactive runtime needs noninteractive.argv and noninteractive.prompt"
    elif has("sandbox") and ((.sandbox | type) != "object" or (.sandbox | to_entries | any(.value | strs | not))) then
      "sandbox must map names to argument lists"
    elif ([.skill_call, .session_log, .limits, .install] | any(line | not)) then
      "skill_call, session_log, limits and install must be one line of text each"
    elif (.capabilities | type) != "object" then "capabilities must be an object"
    elif (.config_dir.default | line | not)
      or ((.config_dir | has("env")) and (.config_dir.env | (type != "string") or (test("\\A[A-Z_][A-Z0-9_]*\\z") | not))) then
      "config_dir needs a default and, if set, an env variable name"
    elif has("account_env") and ((.account_env | type) != "array" or (.account_env | any((type != "string") or (test("\\A[A-Z_][A-Z0-9_]*\\z") | not)))) then
      "account_env must list variable names"
    elif (.check.argv | strs | not) or ((.check | has("expect")) and (.check.expect | line | not)) then
      "check needs argv, and an optional expect"
    elif (.check | has("timeout_seconds")) and ((.check.timeout_seconds | type) != "number"
      or .check.timeout_seconds != (.check.timeout_seconds | floor) or .check.timeout_seconds < 1 or .check.timeout_seconds > 600) then
      "check.timeout_seconds must be a whole number of seconds from 1 to 600, not \(.check.timeout_seconds | tojson)"
    elif (.skill_paths | strs | not) or (.skill_paths | length) == 0 then "skill_paths must list at least one path pattern"
    elif has("plugin_skill_paths") and (.plugin_skill_paths | strs | not) then "plugin_skill_paths must be a list of path patterns"
    elif has("agent_paths") and ((.agent_paths | strs | not) or (.agent_paths | length) == 0) then "agent_paths must list at least one path pattern"
    else "" end end' "$f" 2>/dev/null) || why="not readable JSON"
  [ -z "$why" ] || { printf 'harness: runtime profile %s is not valid: %s\n' "$f" "$why" >&2; exit "$HO_EXIT_FLOW"; }
}

# ho_flow_plan_rows <flow>: after ho_flow_load, one JSON line per step that is on:
# {n, id, when, title, runtime, file, mode, owner, note, launch, kind, skills, agents}.
ho_flow_plan_rows() {
  local main row rt f n=0 errf
  main=$(ho_cfg '.runtime.main' '') || exit $?
  errf=$(mktemp "${TMPDIR:-/tmp}/ho-plan-err.XXXXXX") || ho_die "mktemp failed"
  # shellcheck disable=SC2064
  trap "rm -f '$errf'" EXIT
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    n=$((n + 1))
    rt=$(printf '%s' "$row" | jq -r --arg main "$main" '.runtime // $main')
    if [ -z "$rt" ]; then
      printf 'harness: flow %s: step %s names no runtime and config runtime.main is not set\n' \
        "$HO_FLOW_NAME" "$(printf '%s' "$row" | jq -r .id)" >&2
      exit "$HO_EXIT_FLOW"
    fi
    f=$(ho_rt_file "$rt") || exit $?
    ho_rt_check "$f"
    printf '%s' "$row" | jq -c --arg n "$n" --arg rt "$rt" --arg f "$f" --slurpfile p "$f" '
      $p[0] as $p
      | (if ($p.modes | index("interactive")) != null then "interactive" else "noninteractive" end) as $mode
      | (if $mode == "interactive" then [$p.command] + $p.argv.new + $p.argv.prompt
         else [$p.command] + $p.noninteractive.argv
           + (if .kind == "review" then ($p.sandbox["read-only"] // null) else [] end)
           + $p.noninteractive.prompt end) as $launch
      | if $mode == "noninteractive" and .kind == "review" and (($p.sandbox["read-only"] | type) != "array") then
          error("review step \(.id) runs without a terminal on runtime \($rt), so it must run read-only, and the profile has no sandbox.read-only")
        else {n: ($n | tonumber), id, when, title, runtime: $rt, file: $f, mode: $mode, owner, kind: (.kind // ""),
              skills: (.skills // []), agents: (.agents // []),
              note: (if $mode == "noninteractive" and .kind != "review" then "experimental" else "-" end),
              launch: ($launch | join(" "))} end' 2>"$errf" || {
      printf 'harness: flow %s: cannot plan step %s: %s\n' "$HO_FLOW_NAME" "$(printf '%s' "$row" | jq -r .id)" \
        "$(sed -e 's/^jq: error (at <stdin>:[0-9]*): //' "$errf")" >&2
      exit "$HO_EXIT_FLOW"
    }
  done <<EOF_ROWS
$(jq -c '(.system.steps // []) as $own | .steps[] | select(.enabled != false)
  | . + {owner: (if (.id | IN($own[])) then "system" else "harness" end)}' "$HO_FLOW_JSON")
EOF_ROWS
}

# harness flow plan <flow>: the flow's steps with runtime, mode, owner, note and launch line.
ho_flow_plan() {
  local rows
  ho_flow_load "$1"
  HO_FLOW_NAME=$1
  rows=$(ho_flow_plan_rows "$1") || exit $?
  printf '%s\n' "$rows" | jq -r '"\(.n)\t\(.id)\t\(.when)\t\(.title)\t\(.runtime)\t\(.mode)\t\(.owner)\t\(.note)\t\(.launch)"'
}

# ho_rt_probe <seconds> <outfile> <cmd...>: run cmd with stdin from /dev/null and a time limit.
# Returns its exit code, or 124 when it did not answer in time; then the process group it was
# started in is stopped, so a child it left behind goes too (H-103: by exact ID, never by name).
ho_rt_probe() {
  local t=$1 out=$2 pid i=0 rc=0
  shift 2
  ho_group_start "$@" < /dev/null > "$out" 2>&1
  pid=$HO_GROUP_PID
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$i" -ge $((t * 10)) ]; then
      ho_group_stop "$pid"
      return 124
    fi
    sleep 0.1
    i=$((i + 1))
  done
  wait "$pid" || rc=$?
  return "$rc"
}

# ho_rt_home <account-pairs>: the HOME a launched session gets. The launcher keeps the
# terminal's HOME and exports the account's variables on top (lib/sessions.sh), so the
# account's HOME wins over the caller's.
ho_rt_home() {
  local h
  h=$(printf '%s\n' "$1" | awk -F '\t' '$1 == "HOME" { v = $2 } END { print v }')
  [ -n "$h" ] || h=${HOME-}
  printf '%s\n' "$h"
}

# ho_rt_config_dir <profile> <account-pairs>: the tool's own folder, as a launched session gets
# it (issue #119): from the account's variables; with no account, from the caller's environment;
# then the profile default under the session's HOME. With an account the launcher removes the
# runtime's account variables (ho_session_account_env_names) before the account command, so the
# caller's value of such a variable is not used here either.
ho_rt_config_dir() {
  local f=$1 pairs=$2 var dir=""
  var=$(jq -r '.config_dir.env // ""' "$f")
  if [ -n "$var" ]; then
    dir=$(printf '%s\n' "$pairs" | awk -F '\t' -v k="$var" '$1 == k { v = $2 } END { print v }')
    if [ -z "$dir" ] && { [ -z "$pairs" ] || ! ho_session_account_env_names "$f" | grep -qxF "$var"; }; then
      dir=$(printenv "$var" || true)
    fi
  fi
  [ -n "$dir" ] || dir=$(jq -r --arg home "$(ho_rt_home "$pairs")" '.config_dir.default | gsub("\\{home\\}"; $home)' "$f")
  printf '%s\n' "$dir"
}

# harness flow preflight <flow>: the start check of D37-RUNTIME-3. Every runtime a step uses
# must be on PATH (outside the project) and logged in; every skill a step names (and, for a
# system's steps, the system's skills) must be installed for that step's runtime. The whole
# check runs first; then every missing item is printed in one list with its install step, and
# the exit is 69. Nothing is installed. Install text from a project flow is printed marked as
# not checked, because anyone who can write to the repository can change it.
ho_flow_preflight() {
  local flow=$1 rows proj acct="" pairs="" missing="" tmpd rt f cmd cmdpath t rc expect out tmo
  local -a envs=() argv=()
  local a
  ho_flow_load "$flow"
  HO_FLOW_NAME=$flow
  proj=$(ho_project_root 2>/dev/null) || { echo "harness: the start check needs a project (a folder with .harness/config.json)" >&2; exit "$HO_EXIT_FLOW"; }
  HO_PROJECT_DIR=$proj
  rows=$(ho_flow_plan_rows "$flow") || exit $?
  tmpd=$(mktemp -d "${TMPDIR:-/tmp}/ho-preflight.XXXXXX") || ho_die "mktemp failed"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpd'" EXIT
  # The checks run with the account of the worker role, as the steps will (D37-SESSIONS-5).
  # ho_session_account runs the account command once and keeps what it printed; it is not run
  # again here.
  HO_SESSION_ACCOUNT_ENV=""
  # It runs as in the launcher, with the account variables of the runtime sessions launch on
  # (runtime.main) removed (issue #119).
  local mainprof
  mainprof=$(ho_runtime_profile 2>/dev/null) || mainprof=""
  ho_session_account worker "" "$mainprof" > "$tmpd/acct" || exit $?
  acct=$(cat "$tmpd/acct")
  if [ -n "$acct" ]; then
    pairs=$(printf '%s\n' "$HO_SESSION_ACCOUNT_ENV" | ho_account_env_parse) || {
      echo "harness: the account command of the worker role printed no usable KEY=VALUE line" >&2; exit "$HO_EXIT_DATA"; }
    while IFS= read -r t; do [ -n "$t" ] && envs+=("${t%%"$(printf '\t')"*}=${t#*"$(printf '\t')"}"); done <<EOF_ENV
$pairs
EOF_ENV
  fi
  add() { missing="$missing- $1
"; }
  local src_note=""
  [ "$HO_FLOW_ORIGIN" != project ] || src_note=" (from the project flow $HO_FLOW_JSON, not checked)"

  # Runtimes, each once, in step order.
  for rt in $(printf '%s\n' "$rows" | jq -r '.runtime' | awk '!seen[$0]++'); do
    f=$(ho_rt_file "$rt")
    cmd=$(jq -r .command "$f")
    t=$(jq -r '.install' "$f")
    # Look the command up on the same clean PATH a launched session gets.
    cmdpath=$(PATH=$(ho_session_clean_path) command -v "$cmd" 2>/dev/null || true)
    case $cmdpath in
      /*) ;;
      *) add "runtime $rt: command $cmd not found. Install step: $t"; continue ;;
    esac
    if ! ho_session_runtime_path_ok "$cmdpath" 2>/dev/null; then
      add "runtime $rt: command $cmd resolves to $cmdpath, inside the project; it is never run. Install step: $t"
      continue
    fi
    # A whole number (ho_rt_check); floor prints 1.0 or 2e1 the way shell arithmetic reads it.
    tmo=$(jq -r '(.check.timeout_seconds // 20) | floor' "$f")
    argv=()
    # With an account, the login check runs without the caller's account variables, as the
    # launcher removes them before the account command (issue #119); the account's own come after.
    local -a unsets=()
    if [ -n "$pairs" ]; then
      while IFS= read -r a; do [ -n "$a" ] && unsets+=(-u "$a"); done <<EOF_UNSET
$(ho_session_account_env_names "$f")
EOF_UNSET
    fi
    while IFS= read -r a; do [ -n "$a" ] && argv+=("$a"); done <<EOF_ARGV
$(jq -r '.check.argv[]' "$f")
EOF_ARGV
    rc=0
    ho_rt_probe "$tmo" "$tmpd/check.out" \
      /usr/bin/env ${unsets[@]+"${unsets[@]}"} PATH="$(ho_session_clean_path)" ${envs[@]+"${envs[@]}"} "$cmdpath" ${argv[@]+"${argv[@]}"} || rc=$?
    expect=$(jq -r '.check.expect // ""' "$f")
    if [ "$rc" -eq 124 ]; then
      add "runtime $rt: the login check did not answer within $tmo s. Install step: $t"
    elif [ "$rc" -ne 0 ]; then
      add "runtime $rt: not logged in (the login check exited $rc). Install step: $t"
    elif [ -n "$expect" ] && ! jq -Rse --arg re "$expect" 'test($re)' "$tmpd/check.out" >/dev/null 2>&1; then
      add "runtime $rt: not logged in (the login check output does not show a login). Install step: $t"
    fi
  done

  # Skills: (skill, runtime) pairs, each once.
  local need skill dir home pattern found install
  need=$(printf '%s\n' "$rows" | jq -r --slurpfile flow "$HO_FLOW_JSON" '
    ($flow[0].system.skills // []) as $sys
    | (.skills + (if .owner == "system" then $sys else [] end))[] as $s | "\($s)\t\(.runtime)"' | awk '!seen[$0]++')
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    skill=${t%%"$(printf '\t')"*}
    rt=${t#*"$(printf '\t')"}
    f=$(ho_rt_file "$rt")
    home=$(ho_rt_home "$pairs")
    dir=$(ho_rt_config_dir "$f" "$pairs")
    found=0
    while IFS= read -r pattern; do
      [ -n "$pattern" ] || continue
      if compgen -G "$pattern" >/dev/null 2>&1; then found=1; break; fi
    done <<EOF_PAT
$(jq -r --arg d "$dir" --arg home "$home" --arg s "$skill" '
  ($s | split(":")) as $p
  | (if ($p | length) == 2 then (.plugin_skill_paths // []) else .skill_paths end)[]
  | gsub("\\{config_dir\\}"; $d) | gsub("\\{home\\}"; $home) | gsub("\\{skill\\}"; $s)
  | gsub("\\{plugin\\}"; $p[0]) | gsub("\\{name\\}"; ($p[1] // $p[0]))' "$f")
EOF_PAT
    if [ "$found" -eq 0 ]; then
      install=$(jq -r --arg s "$skill" '.install[$s] // (if ((.system.skills // []) | index($s)) != null then .system.install else null end) // ""' "$HO_FLOW_JSON")
      if [ -n "$install" ]; then install="Install step: $install$src_note"; else install="No install step given in the flow."; fi
      add "skill $skill for runtime $rt: not installed in $dir. $install"
    fi
  done <<EOF_NEED
$need
EOF_NEED

  # Agents (H-073: every technology the flow names): (agent, runtime) pairs, each once, as for
  # skills. A runtime whose profile has no agent_paths cannot show an agent, so it counts as missing.
  need=$(printf '%s\n' "$rows" | jq -r --slurpfile flow "$HO_FLOW_JSON" '
    ($flow[0].system.agents // []) as $sys
    | (.agents + (if .owner == "system" then $sys else [] end))[] as $s | "\($s)\t\(.runtime)"' | awk '!seen[$0]++')
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    skill=${t%%"$(printf '\t')"*}
    rt=${t#*"$(printf '\t')"}
    f=$(ho_rt_file "$rt")
    install=$(jq -r --arg s "$skill" '.install[$s] // (if ((.system.agents // []) | index($s)) != null then .system.install else null end) // ""' "$HO_FLOW_JSON")
    if [ -n "$install" ]; then install="Install step: $install$src_note"; else install="No install step given in the flow."; fi
    if [ "$(jq -r 'has("agent_paths")' "$f")" != true ]; then
      add "agent $skill for runtime $rt: cannot be checked, because the runtime profile $f gives no agent_paths. $install"
      continue
    fi
    dir=$(ho_rt_config_dir "$f" "$pairs")
    found=0
    while IFS= read -r pattern; do
      [ -n "$pattern" ] || continue
      if compgen -G "$pattern" >/dev/null 2>&1; then found=1; break; fi
    done <<EOF_APAT
$(jq -r --arg d "$dir" --arg home "$(ho_rt_home "$pairs")" --arg a "$skill" '.agent_paths[]
  | gsub("\\{config_dir\\}"; $d) | gsub("\\{home\\}"; $home) | gsub("\\{agent\\}"; $a)' "$f")
EOF_APAT
    [ "$found" -eq 1 ] || add "agent $skill for runtime $rt: not installed in $dir. $install"
  done <<EOF_ANEED
$need
EOF_ANEED

  printf '%s\n' "$rows" | jq -r 'select(.note == "experimental")
    | "experimental, untested: step \(.id) runs on \(.runtime) without a terminal and is not a review step (D37-RUNTIME-2)"'
  if [ -n "$missing" ]; then
    printf 'start check for flow %s: %s missing; nothing was installed:\n%s' "$flow" "$(printf '%s' "$missing" | grep -c '^- ')" "$missing"
    exit "$HO_EXIT_UNAVAILABLE"
  fi
  printf 'start check OK: flow %s, runtimes %s\n' "$flow" "$(printf '%s\n' "$rows" | jq -r '.runtime' | awk '!seen[$0]++' | tr '\n' ' ' | sed 's/ $//')"
}
