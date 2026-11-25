# shellcheck shell=bash
# Sessions: launcher generation, the session registry and graceful close.
# Design "Rebuild" reuse list: launcher generation (clean PATH, guarded cd, per-role account,
# fixed session ID, one registry record per session), the model-chain parser and graceful
# close. S8-27: a session's identity is its process ID plus its session ID, never its
# terminal. H-100: sessions run interactively in a terminal. H-103: a process is stopped
# only through its exact process ID; nothing here matches processes by name.
#
#   <run>/sessions/<name>.json     the registry record, one per session; its term_tag (new for
#                                  each launch) and its session_id are the tags of the
#                                  session's pane or tab
#   <run>/sessions/<name>.pid      "<pid> <run-id> <session-id>", written by the launcher
#   <run>/sessions/<name>.closing  present while a close is under way (stops model fallback)
#   <run>/sessions/<name>.failed   written by the launcher when the session could not start
#   <run>/launchers/<name>.sh      the generated launcher
#   <run>/logs/launcher.log        what the launchers report
#
# The launch command comes from a runtime data file, runtimes/<runtime.main>.json
# (D37-RUNTIME-1). Accounts come from the user config only (agent decision, T7).
# Exit codes: 64 usage, 65 refused, 66 not found or another run's session, 69 the session
# did not start, 70 terminal failed, 73 no free worker slot, 75 the run is stopped, 78 config,
# 1 close timed out.
#
# Requires lib/files.sh, lib/config.sh, lib/run.sh, lib/term.sh and lib/isolation.sh.

HO_SESSION_ROLES="orchestrator watcher worker validator question"

ho_session_usage() {
  cat >&2 <<'USAGE'
usage: harness session <run-dir> <verb> [args]
  launch --role R --name N --cwd DIR (--prompt FILE | --resume SESSION-ID) [--account A] [--model "a|b"]
         [--slot-wait SECONDS]   a worker waits this long for a worker slot (default 0); exit 73
                                 when the worker cap stays reached
  close <name>        ask the session to exit, wait for its exact process to end; never forced
  list                one line per session: name role status pid session-id handle
  status [name]       liveness facts, one JSON line per session (working, starting, dead,
                      closed, unknown); a silent session with a live process reads as working
  read <name> transcript|screen [--lines N]
                      the tail of the session's transcript or screen, fenced as untrusted;
                      reads only, never types
USAGE
}

# Quote one value for the generated launcher (single quotes; safe in every bash version).
ho_q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

ho_session_name_ok() {
  case ${1-} in
    '' | -* | *[!a-z0-9-]*) printf 'harness: session name must use a-z 0-9 - and not start with -: %s\n' "${1-}" >&2; return 65 ;;
  esac
  [ "${#1}" -le 40 ] || { echo "harness: session name is longer than 40 characters" >&2; return 65; }
}

# The role must equal one role of the list; "worker validator" is no role.
ho_session_role_ok() {
  local r
  for r in $HO_SESSION_ROLES; do
    [ "${1-}" = "$r" ] && return 0
  done
  printf 'harness: unknown role %s (roles: %s)\n' "${1-}" "$HO_SESSION_ROLES" >&2
  return 65
}

# ho_model_chain <chain>: the "a|b|c" parser. One model per line, in order; blanks dropped.
ho_model_chain() {
  local chain=${1-} m out="" IFS='|'
  for m in $chain; do
    m=$(printf '%s' "$m" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$m" ] || continue
    case $m in
      *[!A-Za-z0-9._:\[\]-]*) printf 'harness: model %s has characters outside A-Z a-z 0-9 . _ : [ ] -\n' "$m" >&2; return 65 ;;
      -*) printf 'harness: model %s starts with "-"; a model name may not look like a command-line flag\n' "$m" >&2; return 65 ;;
    esac
    out="$out$m
"
  done
  [ -n "$out" ] || { echo "harness: the model chain is empty" >&2; return 65; }
  printf '%s' "$out"
}

# ho_runtime_profile: print the runtime data file named by config runtime.main. No fallback.
ho_runtime_profile() {
  local name f
  name=$(ho_cfg '.runtime.main' '')
  [ -n "$name" ] || { echo "harness: config runtime.main is not set; set it to a file name in runtimes/ (without .json)" >&2; return 78; }
  case $name in *[!a-z0-9-]*) printf 'harness: runtime.main %s is not a runtime name\n' "$name" >&2; return 78 ;; esac
  f="$HO_ROOT/runtimes/$name.json"
  [ -f "$f" ] || { printf 'harness: no runtime file %s\n' "$f" >&2; return 78; }
  jq -e 'type == "object" and .schemaVersion == 2
    and (.command | type == "string" and length > 0)
    and ([.argv.new, .argv.resume, .argv.model, .argv.title, .argv.prompt] | all(type == "array" and all(type == "string" and (test("\n") | not))))
    and (.permissions | type == "object")
    and (.exit_command | type == "string" and length > 0 and (test("\n") | not))' "$f" >/dev/null 2>&1 || {
    printf 'harness: runtime file %s is not a valid schemaVersion 2 runtime\n' "$f" >&2
    return 78
  }
  printf '%s\n' "$f"
}

# ho_account_env_parse: read an account command's output on stdin; print "KEY<tab>VALUE" lines.
# Only KEY=VALUE lines (an "export " prefix and one pair of quotes are allowed). Keys are
# upper case; PATH and HO_* cannot be set. Fails on any other line, or when there is none.
# This one function also runs inside every generated launcher, so both sides agree.
ho_account_env_parse() {
  local l k v n=0 tab
  tab=$(printf '\t')
  while IFS= read -r l || [ -n "$l" ]; do
    l=${l%"$(printf '\r')"}
    [ -n "$l" ] || continue
    l=${l#export }
    case $l in *=*) ;; *) return 1 ;; esac
    k=${l%%=*}
    v=${l#*=}
    case $k in '' | [0123456789]* | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]* | PATH | HO_*) return 1 ;; esac
    case $v in *"$tab"*) return 1 ;; esac
    case $v in
      \"*\") v=${v#\"}; v=${v%\"} ;;
      \'*\') v=${v#\'}; v=${v%\'} ;;
    esac
    printf '%s\t%s\n' "$k" "$v"
    n=$((n + 1))
  done
  [ "$n" -gt 0 ]
}

# ho_cfg_user <jq-path>: a value from the user config only (compact JSON; null when unset).
ho_cfg_user() {
  local f
  f=$(ho_user_config)
  ho_config_file_check "$f"
  [ -f "$f" ] || { echo null; return 0; }
  # No "// null" here: that would turn a real false into "unset" (PR #90 re-check).
  jq -c "$1" "$f"
}

# ho_session_account <role> <requested>: print "<account>\t<env-command>", or nothing when no
# account is configured. Refuses (65) a mismatch, an unknown account, or a command that fails.
ho_session_account() {
  local role=$1 want=$2 proj mapped cmd out
  proj="$HO_PROJECT_DIR/.harness/config.json"
  if jq -e '.accounts != null' "$proj" >/dev/null 2>&1; then
    printf 'harness: accounts are set in the project config %s; accounts belong in the user config only\n' "$proj" >&2
    return 65
  fi
  mapped=$(ho_cfg_user ".accounts.roles[\"$role\"] // .accounts.roles.default" | jq -r '. // ""')
  if [ -z "$mapped" ]; then
    [ -z "$want" ] && return 0
    printf 'harness: --account %s given, but no account is configured for role %s\n' "$want" "$role" >&2
    return 65
  fi
  case $mapped in *[!a-z0-9-]* | -*) printf 'harness: account name %s must use a-z 0-9 -\n' "$mapped" >&2; return 65 ;; esac
  if [ -n "$want" ] && [ "$want" != "$mapped" ]; then
    printf 'harness: role %s runs on account %s, not %s\n' "$role" "$mapped" "$want" >&2
    return 65
  fi
  cmd=$(ho_cfg_user ".accounts.list[\"$mapped\"].env_command" | jq -r 'strings // ""')
  [ -n "$cmd" ] || { printf 'harness: account %s (role %s) has no env_command in accounts.list\n' "$mapped" "$role" >&2; return 65; }
  out=$(/bin/bash -c "$cmd" 2>/dev/null) || { printf 'harness: the env_command of account %s failed\n' "$mapped" >&2; return 65; }
  printf '%s\n' "$out" | ho_account_env_parse >/dev/null || {
    printf 'harness: the env_command of account %s must print KEY=VALUE lines only\n' "$mapped" >&2
    return 65
  }
  printf '%s\t%s\n' "$mapped" "$cmd"
}

# ho_session_clean_path: absolute PATH entries only, each once, without folders that hold a
# 0.6.0 engine script.
ho_session_clean_path() {
  local out="" dir s rest skip
  rest="$(ho_sanitize_path "${PATH-}"):"
  while [ -n "$rest" ]; do
    dir=${rest%%:*}
    rest=${rest#*:}
    [ -n "$dir" ] || continue
    case ":$out:" in *":$dir:"*) continue ;; esac
    skip=0
    for s in $HO_OLD_SCRIPTS; do
      [ -e "$dir/$s" ] && { skip=1; break; }
    done
    [ "$skip" -eq 0 ] && out="${out:+$out:}$dir"
  done
  printf '%s\n' "$out"
}

# ho_session_project_roots: print the physical folders a runtime binary may not live in: the
# project, each configured repos[].worktrees_dir, and every git worktree of the project
# repository and of each configured repo (D37-FLOW-8, Codex security review of #90).
ho_session_project_roots() {
  local proj cfg d r
  proj=$(cd "$HO_PROJECT_DIR" && pwd -P) || return 1
  cfg="$HO_PROJECT_DIR/.harness/config.json"
  printf '%s\n' "$proj"
  {
    jq -r '.repos[]? | objects | .worktrees_dir | strings' "$cfg" 2>/dev/null || true
  } | while IFS= read -r d; do
    [ -n "$d" ] || continue
    case $d in /*) ;; *) d="$proj/$d" ;; esac
    (cd "$d" 2>/dev/null && pwd -P) || true
  done
  {
    printf '%s\n' "$proj"
    jq -r '.repos[]? | objects | .path | strings' "$cfg" 2>/dev/null || true
  } | while IFS= read -r r; do
    [ -n "$r" ] || continue
    case $r in /*) ;; *) r="$proj/$r" ;; esac
    { git -C "$r" worktree list --porcelain 2>/dev/null || true; } | sed -n 's/^worktree //p' | while IFS= read -r d; do
      (cd "$d" 2>/dev/null && pwd -P) || true
    done
  done
}

# ho_session_runtime_path_ok <cmdpath>: refuse (65) a runtime binary that is, or links to, a
# file inside the project, its worktrees folder or a worktree of the project repository.
# Folders are compared as physical paths; every link on the way is checked.
ho_session_runtime_path_ok() {
  local f=$1 d t root roots a n=0
  roots=$(ho_session_project_roots) || { echo "harness: cannot read the project folder" >&2; return 65; }
  while :; do
    d=$(cd "$(dirname "$f")" 2>/dev/null && pwd -P) || { printf 'harness: cannot resolve the runtime command path %s\n' "$f" >&2; return 65; }
    # Folders are compared by identity (-ef), walking up from the binary folder, so
    # another letter case or Unicode form of the same folder cannot pass.
    while IFS= read -r root; do
      [ -n "$root" ] || continue
      a=$d
      while :; do
        if [ "$a" -ef "$root" ]; then
          printf 'harness: the runtime command resolves to %s, inside %s; a runtime binary from the project, its worktrees folder or a worktree is never run. Put the runtime first on PATH from a folder outside the project.\n' "$f" "$root" >&2
          return 65
        fi
        [ "$a" = / ] && break
        a=$(dirname "$a")
      done
    done <<EOF_ROOTS
$roots
EOF_ROOTS
    [ -L "$f" ] || return 0
    n=$((n + 1))
    [ "$n" -le 40 ] || { printf 'harness: the runtime command %s has too many links\n' "$1" >&2; return 65; }
    t=$(readlink "$f") || return 65
    case $t in /*) f=$t ;; *) f="$d/$t" ;; esac
  done
}

ho_session_new_id() {
  local u
  if u=$(uuidgen 2>/dev/null); then
    printf '%s\n' "$u" | tr 'A-F' 'a-f'
  else
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n' | sed 's/^\(.\{8\}\)\(.\{4\}\).\(.\{3\}\).\(.\{3\}\)\(.\{12\}\).*/\1-\2-4\3-a\4-\5/'
    echo
  fi
}

ho_session_uuid_ok() {
  printf '%s' "${1-}" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' || {
    printf 'harness: session ID %s is not a lower-case UUID\n' "${1-}" >&2
    return 65
  }
}

# ho_session_identity <pid> <session-id>: 0 when that exact process is alive and its own
# command line carries the session ID. A reused PID or a dead process fails.
ho_session_identity() {
  local pid=${1-} sid=${2-} cmd
  case $pid in '' | *[!0-9]*) return 1 ;; esac
  [ -n "$sid" ] || return 1
  cmd=$(ps -o command= -p "$pid" 2>/dev/null) || return 1
  case $cmd in *"$sid"*) return 0 ;; esac
  return 1
}

# ho_session_pidfile_pid <pid-file> <session-id>: the PID the launcher reported for this run and
# session, or nothing.
ho_session_pidfile_pid() {
  local p r s
  [ -f "$1" ] || return 0
  read -r p r s < "$1" 2>/dev/null || return 0
  [ "$r" = "$HO_RUN_ID" ] && [ "$s" = "$2" ] && printf '%s\n' "$p"
  return 0
}

# ho_session_current_pid <record>: the exact live process of the session, or nothing; reads
# only. The launcher's PID file wins when it names a newer live process of the same run and
# session (model fallback).
ho_session_current_pid() {
  local rec=$1 sid pid fpid
  sid=$(jq -r '.session_id // ""' "$rec")
  pid=$(jq -r '.pid // ""' "$rec")
  fpid=$(ho_session_pidfile_pid "$(jq -r '.pid_file // ""' "$rec")" "$sid")
  if [ -n "$fpid" ] && [ "$fpid" != "$pid" ] && ho_session_identity "$fpid" "$sid"; then
    pid=$fpid
  fi
  ho_session_identity "$pid" "$sid" && printf '%s\n' "$pid"
  return 0
}

# ho_session_live_pid <record>: as ho_session_current_pid, and the record is brought up to date.
ho_session_live_pid() {
  local rec=$1 pid
  pid=$(ho_session_current_pid "$rec")
  if [ -n "$pid" ] && [ "$pid" != "$(jq -r '.pid // ""' "$rec")" ]; then
    ho_session_set "$rec" '.pid = ($p | tonumber)' --arg p "$pid" || return 1
  fi
  [ -z "$pid" ] || printf '%s\n' "$pid"
  return 0
}

# ho_session_set <record> <jq-filter> [jq args]: rewrite one record atomically.
ho_session_set() {
  local rec=$1 filter=$2 new
  shift 2
  new=$(jq "$@" "$filter" "$rec") || { printf 'harness: cannot update %s\n' "$rec" >&2; return 1; }
  printf '%s\n' "$new" | ho_atomic_write "$rec"
}

# ho_session_launcher_write <file> <args...>: print the launcher text. All values arrive checked.
ho_session_launcher_text() {
  local name=$1 role=$2 account=$3 acct_cmd=$4 sid=$5 cwd=$6 prompt=$7 pidfile=$8 closing=$9
  local log=${10} path=${11} grace=${12} hold=${13} cmdpath=${14} attempts=${15}
  printf '#!/bin/bash\n'
  printf '# ho-launcher run=%s name=%s role=%s account=%s session=%s\n' "$HO_RUN_ID" "$name" "$role" "${account:--}" "$sid"
  printf '# Generated by the harness engine. Do not edit; launch it again instead.\n'
  printf 'set -u\n'
  printf 'HO_LOG=%s\n' "$(ho_q "$log")"
  printf 'ho_note() { printf '"'"'[%%s %%s] %%s\\n'"'"' "$(date -u +%%H:%%M:%%S)" %s "$*" >> "$HO_LOG"; printf '"'"'%%s\\n'"'"' "$*" >&2; }\n' "$(ho_q "$name")"
  printf 'ho_fatal() { ho_note "FATAL: $2"; printf '"'"'%%s\\n'"'"' "$2" > %s; sleep %s; exit "$1"; }\n' "$(ho_q "${pidfile%.pid}.failed")" "$hold"
  printf 'unset %s\n' "$HO_OLD_VARS"
  printf 'export PATH=%s\n' "$(ho_q "$path")"
  printf 'export HO_PROJECT_DIR=%s HO_RUN_DIR=%s HO_RUN_ID=%s\n' "$(ho_q "$HO_PROJECT_DIR")" "$(ho_q "$HO_RUN_DIR")" "$(ho_q "$HO_RUN_ID")"
  printf 'export HO_SESSION_NAME=%s HO_SESSION_ROLE=%s HO_SESSION_ID=%s\n' "$(ho_q "$name")" "$(ho_q "$role")" "$(ho_q "$sid")"
  printf 'cd -- %s || ho_fatal 66 "cannot enter the working folder; the session was not started"\n' "$(ho_q "$cwd")"
  if [ -n "$account" ]; then
    declare -f ho_account_env_parse
    printf 'ho_acct=$(/bin/bash -c %s 2>>"$HO_LOG") || ho_fatal 9 "the account command failed; the session was not started"\n' "$(ho_q "$acct_cmd")"
    printf 'ho_acct=$(printf '"'"'%%s\\n'"'"' "$ho_acct" | ho_account_env_parse) || ho_fatal 9 "the account command printed no usable KEY=VALUE line"\n'
    printf 'while IFS="$(printf '"'"'\\t'"'"')" read -r ho_k ho_v; do export "$ho_k=$ho_v"; done <<HO_ACCT\n$ho_acct\nHO_ACCT\n'
    printf 'ho_note %s\n' "$(ho_q "account $account applied")"
  fi
  if [ -n "$prompt" ]; then
    printf 'HO_PROMPT=$(cat %s) || ho_fatal 65 "cannot read the prompt file"\n' "$(ho_q "$prompt")"
  fi
  # Each attempt writes its own PID, then becomes the session process (exec), so the PID
  # recorded is exactly the session's process.
  printf 'ho_attempt() {\n'
  printf '  /bin/sh -c '"'"'printf "%%s %%s %%s\\n" "$$" "$1" "$2" > "$3.tmp" && mv -f "$3.tmp" "$3" || exit 70; shift 3; exec "$@"'"'"' ho-session %s %s %s "$@"\n' \
    "$(ho_q "$HO_RUN_ID")" "$(ho_q "$sid")" "$(ho_q "$pidfile")"
  printf '}\n'
  printf '%s\n' "$attempts" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '[ -e %s ] && { ho_note "a close is under way; not starting"; exit 0; }\n' "$(ho_q "$closing")"
    printf 'ho_t0=$(date +%%s)\n'
    printf 'ho_note %s\n' "$(ho_q "starting session $sid")"
    printf 'ho_attempt %s %s\n' "$(ho_q "$cmdpath")" "$line"
    printf 'ho_rc=$?; ho_dt=$(( $(date +%%s) - ho_t0 ))\n'
    printf 'if [ "$ho_rc" -eq 0 ] || [ "$ho_dt" -gt %s ] || [ -e %s ]; then ho_note "session ended rc=$ho_rc after ${ho_dt}s"; exit "$ho_rc"; fi\n' "$grace" "$(ho_q "$closing")"
    printf 'ho_note "start failed rc=$ho_rc after ${ho_dt}s; trying the next model"\n'
  done
  printf 'ho_fatal 69 "every model in the chain failed to start"\n'
}

# ho_session_attempts <profile> <sid> <title> <perm-mode> <resume 0|1> <models>: one line per
# attempt, each the quoted argv for the launcher. {prompt} becomes "$HO_PROMPT".
ho_session_attempts() {
  local profile=$1 sid=$2 title=$3 perm=$4 resume=$5 models=$6 m el line
  # "*" stands for "no model argument" (it is not a valid model name).
  [ -n "$models" ] || models='*'
  printf '%s\n' "$models" | while IFS= read -r m; do
    [ -n "$m" ] || continue
    [ "$m" = '*' ] && m=""
    line=""
    while IFS= read -r el; do
      case $el in
        '{prompt}') line="$line \"\$HO_PROMPT\"" ;;
        *'{prompt}'*) echo "harness: runtime argv may use {prompt} only as a whole element" >&2; exit 78 ;;
        *) line="$line $(ho_q "$el")" ;;
      esac
    done <<EOF_ARGV
$(jq -r --arg sid "$sid" --arg model "$m" --arg title "$title" --arg perm "$perm" --arg resume "$resume" '
    def fill: gsub("\\{session_id\\}"; $sid) | gsub("\\{model\\}"; $model) | gsub("\\{title\\}"; $title);
    (if $resume == "1" then .argv.resume else .argv.new end)
    + (if $model != "" then .argv.model else [] end)
    + .argv.title
    + .permissions[$perm]
    + (if $resume == "1" then [] else .argv.prompt end)
    | map(fill) | .[]' "$profile")
EOF_ARGV
    printf '%s\n' "${line# }"
  done
}

# H-105, D26a: a worker launch takes a worker slot before anything is opened, and every failed
# launch gives it back. The slot is held from then until close, or until the session reads dead.
ho_session_launch() {
  local rc=0
  HO_SLOT_TAKEN=""
  ho_session_launch_one "$@" || rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$HO_SLOT_TAKEN" ]; then ho_slot_give worker "$HO_SLOT_TAKEN"; fi
  return "$rc"
}

ho_session_launch_one() {
  local role="" name="" cwd="" prompt="" account="" chain="" resume="" slot_wait=0
  while [ $# -gt 0 ]; do
    case $1 in
      --role | --name | --cwd | --prompt | --account | --model | --resume | --slot-wait)
        [ $# -ge 2 ] || { ho_session_usage; return 64; }
        case $1 in
          --role) role=$2 ;; --name) name=$2 ;; --cwd) cwd=$2 ;; --prompt) prompt=$2 ;;
          --account) account=$2 ;; --model) chain=$2 ;; --resume) resume=$2 ;; --slot-wait) slot_wait=$2 ;;
        esac
        shift 2
        ;;
      *) printf 'harness: unknown launch argument %s\n' "$1" >&2; ho_session_usage; return 64 ;;
    esac
  done
  [ -n "$role" ] && [ -n "$name" ] && [ -n "$cwd" ] || { ho_session_usage; return 64; }
  [ -n "$prompt" ] || [ -n "$resume" ] || { echo "harness: launch needs --prompt or --resume" >&2; return 64; }
  case $slot_wait in '' | *[!0-9]*) echo "harness: --slot-wait must be whole seconds" >&2; return 64 ;; esac

  # ---- guards: nothing is written before all of them pass ----
  ho_session_role_ok "$role" || return 65
  ho_session_name_ok "$name" || return 65
  local stopped=0
  ho_stopped || stopped=$?
  [ "$stopped" -eq 1 ] || { echo "harness: the run is stopped (or its stop state is unknown); no session is launched" >&2; return 75; }
  ho_assert_safe_cwd "$cwd" "$HO_PROJECT_DIR" || return 65
  cwd=$(cd "$cwd" && pwd -P) || return 65
  case $cwd in *$'\n'*) echo "harness: working folder name has a line break" >&2; return 65 ;; esac
  if [ -n "$resume" ]; then
    ho_session_uuid_ok "$resume" || return 65
    prompt=""
  else
    ho_assert_abs "$prompt" "prompt file" || return 65
    [ -f "$prompt" ] && [ -s "$prompt" ] && [ -r "$prompt" ] || { printf 'harness: prompt file missing or empty: %s\n' "$prompt" >&2; return 65; }
  fi
  local profile perm cmd cmdpath models acct acct_name="" acct_cmd=""
  profile=$(ho_runtime_profile) || return $?
  # D37-FLOW-8: the permission mode is never read from the project config (interim, fail
  # closed, until the local approval record of D37-FLOW-8 (b) exists).
  perm=$(jq -r 'if (.session.permissions // null) == null or .session.permissions == "" then "" else "set" end' \
    "$HO_PROJECT_DIR/.harness/config.json" 2>/dev/null) || perm=set
  if [ -n "$perm" ]; then
    printf 'harness: the project config %s sets session.permissions. A project config may not set the permission mode until the local approval record exists; move session.permissions to the user config %s\n' \
      "$HO_PROJECT_DIR/.harness/config.json" "$(ho_user_config)" >&2
    return 65
  fi
  perm=$(ho_cfg_user '.session.permissions' | jq -r 'if . == null then "" elif type == "string" then . else tojson end') || return 78
  [ -n "$perm" ] || perm=bypass
  jq -e --arg p "$perm" '.permissions[$p] | type == "array"' "$profile" >/dev/null 2>&1 || {
    printf 'harness: session.permissions %s is not known to runtime %s\n' "$perm" "$(basename "$profile" .json)" >&2
    return 65
  }
  [ -n "$chain" ] || chain=$(ho_cfg ".models[\"$role\"]" '')
  models=""
  if [ -n "$chain" ]; then models=$(ho_model_chain "$chain") || return 65; fi
  acct=$(ho_session_account "$role" "$account") || return 65
  if [ -n "$acct" ]; then
    acct_name=${acct%%"$(printf '\t')"*}
    acct_cmd=${acct#*"$(printf '\t')"}
  fi
  cmd=$(jq -r .command "$profile")
  cmdpath=$(command -v "$cmd" 2>/dev/null || true)
  case $cmdpath in /*) ;; *) printf 'harness: the runtime command %s is not on PATH\n' "$cmd" >&2; return 65 ;; esac
  ho_session_runtime_path_ok "$cmdpath" || return 65
  local path
  path=$(ho_session_clean_path)
  [ -n "$path" ] || { echo "harness: PATH has no usable absolute entry" >&2; return 65; }

  # ---- reserve the one registry record for this name ----
  local sdir="$HO_RUN_DIR/sessions" rec
  mkdir -p "$sdir" "$HO_RUN_DIR/logs"
  rec="$sdir/$name.json"
  if ! (set -C; : > "$rec") 2>/dev/null; then
    printf 'harness: session %s is already registered in run %s\n' "$name" "$HO_RUN_ID" >&2
    return 65
  fi
  # The worker cap: counted and taken under the slot lock, while the name is reserved.
  if [ "$role" = worker ]; then
    local src=0
    ho_slot_take worker "$name" "" "$((10#$slot_wait))" || src=$?
    if [ "$src" -ne 0 ]; then
      rm -f "$rec"
      [ "$src" -eq "$HO_SLOT_NOSLOT" ] && printf 'harness: the worker cap (%s) is reached; %s was not launched and waits for a free slot\n' "$(ho_slot_limit worker)" "$name" >&2
      return "$src"
    fi
    HO_SLOT_TAKEN=$name
  fi

  local sid tag ldir launcher title pidfile closing group attempts
  sid=${resume:-$(ho_session_new_id)}
  # The terminal tag is new for every launch. A resume reuses the session ID, so the session ID
  # cannot tell this launch's pane or tab from the one of an earlier launch (review N2).
  tag=$(ho_session_new_id)
  ho_session_uuid_ok "$tag" || { rm -f "$rec"; return 70; }
  # A resume never runs beside a launch of the same session ID that is not closed. The record
  # carries the session ID before the check, so of two resumes that race, at least one sees
  # the other and stops.
  if [ -n "$resume" ]; then
    jq -n --arg run "$HO_RUN_ID" --arg name "$name" --arg sid "$sid" --arg pidfile "$sdir/$name.pid" --arg ts "$(ho_now)" \
      '{schemaVersion: 2, run: $run, name: $name, session_id: $sid, pid: null, pid_file: $pidfile, status: "launching", created: $ts}' \
      | ho_atomic_write "$rec" || { rm -f "$rec"; return 1; }
    local f other=""
    for f in "$sdir"/*.json; do
      [ -f "$f" ] && [ "$f" != "$rec" ] || continue
      if [ "$(jq -r --arg sid "$sid" 'if type == "object" and .session_id == $sid and .status != "closed" then "yes" else "" end' "$f" 2>/dev/null)" = yes ]; then
        other=$(basename "$f" .json)
        break
      fi
    done
    if [ -n "$other" ]; then
      rm -f "$rec"
      printf 'harness: session %s of run %s has session ID %s and is not closed; close it before a resume\n' "$other" "$HO_RUN_ID" "$sid" >&2
      return 65
    fi
  fi
  ldir="$HO_RUN_DIR/launchers"
  ho_term_safe "$ldir/$name.sh" 2>/dev/null || ldir="${HO_USER_DIR:-$HOME/.claude/harness}/launchers/$HO_RUN_ID"
  ho_term_safe "$ldir/$name.sh" || { rm -f "$rec"; return 65; }
  mkdir -p "$ldir"
  launcher="$ldir/$name.sh"
  title="ho-$role-$name"
  pidfile="$sdir/$name.pid"
  closing="$sdir/$name.closing"
  case $role in orchestrator | watcher) group=control ;; *) group=work ;; esac
  attempts=$(ho_session_attempts "$profile" "$sid" "$title" "$perm" "$([ -n "$resume" ] && echo 1 || echo 0)" "$models") || { rm -f "$rec"; return 78; }

  ho_session_launcher_text "$name" "$role" "$acct_name" "$acct_cmd" "$sid" "$cwd" "$prompt" "$pidfile" "$closing" \
    "$HO_RUN_DIR/logs/launcher.log" "$path" "$(ho_cfg_int '.session.boot_grace_seconds' 45)" \
    "$(ho_cfg_int '.session.fatal_hold_seconds' 30)" "$cmdpath" "$attempts" > "$launcher.tmp" || { rm -f "$rec" "$launcher.tmp"; return 1; }
  # The launcher must say exactly what was asked for, or it is not used.
  if ! /bin/bash -n "$launcher.tmp" 2>/dev/null \
    || [ "$(sed -n 2p "$launcher.tmp")" != "# ho-launcher run=$HO_RUN_ID name=$name role=$role account=${acct_name:--} session=$sid" ] \
    || ! grep -qxF "cd -- $(ho_q "$cwd") || ho_fatal 66 \"cannot enter the working folder; the session was not started\"" "$launcher.tmp"; then
    rm -f "$rec" "$launcher.tmp"
    echo "harness: the generated launcher does not match the request; nothing was launched" >&2
    return 65
  fi
  chmod 700 "$launcher.tmp" && mv -f "$launcher.tmp" "$launcher" || { rm -f "$rec" "$launcher.tmp"; return 1; }

  local backend troot acct_env=""
  backend=$(ho_term_backend) || { local rc=$?; rm -f "$rec"; return "$rc"; }
  # H-090: where this session's transcript lives, read later by its session ID (lib/liveness.sh).
  [ -z "$acct_cmd" ] || acct_env=$(/bin/bash -c "$acct_cmd" 2>/dev/null || true)
  troot=$(ho_live_transcript_root "$profile" "$acct_env")
  jq -n --arg run "$HO_RUN_ID" --arg name "$name" --arg role "$role" --arg account "$acct_name" \
    --arg runtime "$(basename "$profile" .json)" --arg sid "$sid" --arg cwd "$cwd" --arg launcher "$launcher" \
    --arg pidfile "$pidfile" --arg chain "$chain" --arg backend "$backend" --arg ts "$(ho_now)" --arg tag "$tag" \
    --arg troot "$troot" \
    '{schemaVersion: 2, run: $run, name: $name, role: $role, account: (if $account == "" then null else $account end),
      runtime: $runtime, session_id: $sid, pid: null, backend: $backend, handle: null, term_tag: $tag, cwd: $cwd,
      launcher: $launcher, pid_file: $pidfile, model_chain: $chain, status: "launching", created: $ts,
      transcript_root: (if $troot == "" then null else $troot end)}' \
    | ho_atomic_write "$rec" || { rm -f "$rec"; return 1; }
  ho_ledger_append session-launch name "$name" role "$role" session_id "$sid" account "$acct_name"

  local handle rc=0
  handle=$(ho_term_open "$group" "$title" "$launcher" "$tag" "$sid") || rc=$?
  if [ "$rc" -ne 0 ]; then
    ho_session_set "$rec" '.status = "launch-failed"' || rm -f "$rec"
    ho_ledger_append session-launch-failed name "$name" reason "terminal did not open"
    return "$rc"
  fi
  ho_session_set "$rec" '.handle = $h' --arg h "$handle" || { printf 'harness: session %s opened as %s but its record could not be written\n' "$name" "$handle" >&2; return 1; }

  # ---- boot check: the launcher reports the PID; it must be alive with this session ID ----
  local deadline pid="" last="" stable=0
  deadline=$(( $(date +%s) + $(ho_cfg_int '.session.boot_timeout_seconds' 120) ))
  while [ "$(date +%s)" -le "$deadline" ]; do
    pid=$(ho_session_pidfile_pid "$pidfile" "$sid")
    if [ -n "$pid" ] && ho_session_identity "$pid" "$sid"; then
      if [ "$pid" = "$last" ]; then stable=$((stable + 1)); else stable=0; last=$pid; fi
      [ "$stable" -ge 2 ] && break
    fi
    sleep 0.2
  done
  if [ "$stable" -lt 2 ]; then
    ho_session_set "$rec" '.status = "boot-failed"' || true
    ho_ledger_append session-boot-failed name "$name" session_id "$sid"
    printf 'harness: session %s did not start; see %s\n' "$name" "$HO_RUN_DIR/logs/launcher.log" >&2
    return 69
  fi
  ho_session_set "$rec" '.pid = ($p | tonumber) | .status = "running" | .started = $ts' --arg p "$pid" --arg ts "$(ho_now)" || {
    printf 'harness: session %s runs as pid %s but its record could not be written\n' "$name" "$pid" >&2
    return 1
  }
  ho_ledger_append session-started name "$name" session_id "$sid" pid "$pid" handle "$handle"
  printf 'OK name=%s pid=%s session=%s handle=%s\n' "$name" "$pid" "$sid" "$handle"
}

# Graceful close: refuse another run's session; a gone process is only marked closed (PR-3);
# a live one is asked to exit through its own terminal, and the close counts only when that
# exact process has ended. A session still busy at the timeout is left open, never forced.
ho_session_close() {
  local name=${1-} rec owner status sid pid handle tag profile exitcmd
  [ -n "$name" ] || { ho_session_usage; return 64; }
  ho_session_name_ok "$name" || return 65
  rec="$HO_RUN_DIR/sessions/$name.json"
  [ -f "$rec" ] || { printf 'harness: no session %s in run %s\n' "$name" "$HO_RUN_ID" >&2; return 66; }
  owner=$(jq -r 'if type == "object" then (.run // "") else "" end' "$rec" 2>/dev/null || echo "")
  if [ "$owner" != "$HO_RUN_ID" ]; then
    ho_ledger_append session-close-refused name "$name" found "${owner:-unreadable}"
    printf 'harness: session %s is recorded under run %s, not %s; refusing to close it\n' "$name" "${owner:-unreadable}" "$HO_RUN_ID" >&2
    return 66
  fi
  status=$(jq -r '.status // ""' "$rec")
  [ "$status" = closed ] && { printf 'session %s already closed\n' "$name"; return 0; }
  # A launch rewrites its record within the boot timeout; a record left "launching" for
  # longer belongs to a launch that died, and may be closed.
  if [ "$status" = launching ] && [ -z "$(find "$rec" -mmin +10 2>/dev/null)" ]; then
    printf 'harness: session %s is still launching; close it once the launch has finished\n' "$name" >&2
    return 65
  fi
  sid=$(jq -r '.session_id // ""' "$rec")
  if ! ho_session_uuid_ok "$sid" 2>/dev/null || [ -z "$(jq -r '.pid_file // ""' "$rec")" ]; then
    printf 'harness: the record of session %s has no usable session ID or PID file; nothing was closed\n' "$name" >&2
    return 66
  fi
  # The flag comes first: from now on the launcher starts no further model attempt, so a
  # session cannot come back between the liveness check and the close.
  local closing="$HO_RUN_DIR/sessions/$name.closing"
  : > "$closing" || return 1
  sleep 0.3
  pid=$(ho_session_live_pid "$rec") || return 1
  if [ -z "$pid" ]; then
    ho_session_set "$rec" '.status = "closed" | .closed = $ts | .closed_reason = "process-gone"' --arg ts "$(ho_now)" || return 1
    ho_ledger_append session-close name "$name" session_id "$sid" result process-gone
    ho_slot_give_all "$name"
    printf 'session %s: process already gone; marked closed\n' "$name"
    return 0
  fi
  handle=$(jq -r '.handle // ""' "$rec")
  [ -n "$handle" ] || { rm -f "$closing"; printf 'harness: session %s has no terminal handle; left open\n' "$name" >&2; return 70; }
  # The terminal is reached only through this launch's own tag and the session ID together.
  tag=$(jq -r '.term_tag // ""' "$rec")
  ho_session_uuid_ok "$tag" 2>/dev/null || {
    rm -f "$closing"
    ho_ledger_append session-close-failed name "$name" reason "the record has no terminal tag; nothing typed"
    printf 'harness: the record of session %s has no terminal tag; left open\n' "$name" >&2
    return 70
  }
  # The process the close waits for must be the one the launcher reported for this session:
  # the PID file names this run and session ID, the same process ID, and that process's
  # command line holds the session ID. The pane or tab carries the session ID too, so a record
  # that names another session's terminal is refused there (review of wave 2, R1).
  if [ "$(ho_session_pidfile_pid "$(jq -r '.pid_file // ""' "$rec")" "$sid")" != "$pid" ] || ! ho_session_identity "$pid" "$sid"; then
    rm -f "$closing"
    ho_ledger_append session-close-failed name "$name" reason "the PID file does not name process $pid of this session; nothing typed"
    printf 'harness: the PID file of session %s does not name its process %s; left open\n' "$name" "$pid" >&2
    return 70
  fi
  profile="$HO_ROOT/runtimes/$(jq -r '.runtime // ""' "$rec").json"
  exitcmd=$(jq -r '.exit_command // ""' "$profile" 2>/dev/null || true)
  [ -n "$exitcmd" ] || { rm -f "$closing"; printf 'harness: no exit command for session %s; left open\n' "$name" >&2; return 78; }
  # Reach the session through the backend it was launched with.
  HO_TERM_BACKEND=$(jq -r '.backend // ""' "$rec")
  ho_ledger_append session-close-request name "$name" session_id "$sid" pid "$pid"
  local rc=0
  ho_term_send "$handle" "$tag" "$sid" "$exitcmd" || rc=$?
  if [ "$rc" -ne 0 ]; then
    rm -f "$closing"
    if [ "$rc" -eq 66 ]; then
      ho_ledger_append session-close-failed name "$name" reason "terminal $handle is not this session's; nothing typed"
    else
      ho_ledger_append session-close-failed name "$name" reason "exit command not delivered"
    fi
    printf 'harness: could not reach the terminal of session %s; left open\n' "$name" >&2
    return 70
  fi
  local deadline
  deadline=$(( $(date +%s) + $(ho_cfg_int '.session.close_timeout_seconds' 90) ))
  while ho_session_identity "$pid" "$sid"; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      rm -f "$closing"
      ho_ledger_append session-close-timeout name "$name" session_id "$sid" pid "$pid"
      printf 'harness: session %s (pid %s) is still busy; left open, never forced. Close it again later.\n' "$name" "$pid" >&2
      return 1
    fi
    sleep 0.2
  done
  # The session process has ended. If a new process of the same session appeared anyway, the
  # terminal is left alone. Otherwise its tab or pane is closed (it may have closed by itself),
  # but only while it still carries this session's tag: its handle may name another session by
  # now (H-103, S8-27). A skipped close is recorded with its reason.
  if [ -n "$(ho_session_live_pid "$rec")" ]; then
    ho_ledger_append session-close-timeout name "$name" session_id "$sid" reason "a new process of the session is running"
    printf 'harness: session %s started a new process during the close; left open\n' "$name" >&2
    return 1
  fi
  rc=0
  ho_term_close "$handle" "$tag" "$sid" 2>/dev/null || rc=$?
  if [ "$rc" -ne 0 ]; then
    ho_ledger_append session-close-terminal-skipped name "$name" session_id "$sid" handle "$handle" \
      reason "$([ "$rc" -eq 66 ] && echo "the handle is gone or names another session" || echo "terminal call failed (exit $rc)")"
  fi
  ho_session_set "$rec" '.status = "closed" | .closed = $ts | .closed_reason = "exited"' --arg ts "$(ho_now)" || return 1
  ho_ledger_append session-close name "$name" session_id "$sid" result exited
  ho_slot_give_all "$name"
  printf 'session %s closed\n' "$name"
}

# For a running session, list shows the process that runs now: after a model fallback that is
# the newer process the launcher reported, and the record is brought up to date.
ho_session_list() {
  local f line cur
  printf 'NAME\tROLE\tSTATUS\tPID\tSESSION\tHANDLE\n'
  for f in "$HO_RUN_DIR"/sessions/*.json; do
    [ -f "$f" ] || continue
    cur=""
    [ "$(jq -r '.status // ""' "$f" 2>/dev/null)" = running ] && cur=$(ho_session_live_pid "$f" 2>/dev/null)
    line=$(jq -r --arg cur "$cur" '[.name, .role, .status, (if $cur != "" then $cur else (.pid // "-" | tostring) end), .session_id, (.handle // "-")] | @tsv' "$f" 2>/dev/null || true)
    [ -n "$line" ] || line="$(basename "$f" .json)	-	unreadable"
    # A launcher that could not start its session leaves a .failed note.
    [ -f "${f%.json}.failed" ] && line="$line	(start failed: $(head -n 1 "${f%.json}.failed"))"
    printf '%s\n' "$line"
  done
}

# harness session <run-dir> <verb> [args]: the run stamp is checked first; the project is the
# one that holds the run.
ho_session_main() {
  [ $# -ge 2 ] || { ho_session_usage; exit 64; }
  ho_run_open "$1"
  local verb=$2 proj
  shift 2
  proj=$(cd "$HO_RUN_DIR/../../.." && pwd -P)
  [ -f "$proj/.harness/config.json" ] || { printf 'harness: run %s is not inside a project with .harness/config.json\n' "$HO_RUN_DIR" >&2; exit 78; }
  if [ -n "${HO_PROJECT_DIR:-}" ] && [ "$(cd "$HO_PROJECT_DIR" 2>/dev/null && pwd -P)" != "$proj" ]; then
    printf 'harness: run %s belongs to project %s, not HO_PROJECT_DIR=%s\n' "$HO_RUN_DIR" "$proj" "$HO_PROJECT_DIR" >&2
    exit 65
  fi
  export HO_PROJECT_DIR=$proj
  local rc=0
  case $verb in
    launch) ho_session_launch "$@" || rc=$? ;;
    close) ho_session_close "$@" || rc=$? ;;
    list) ho_session_list ;;
    status) ho_live_status "$@" || rc=$? ;;
    read) ho_live_read "$@" || rc=$? ;;
    *) ho_session_usage; rc=64 ;;
  esac
  exit "$rc"
}
