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
#   <run>/sessions/<name>.launcher "<pid> <start time>" of the launcher, written by it first
#   <run>/sessions/<name>.ended    written by the launcher when it ends with no session left
#   <run>/sessions/<name>.transcript_root
#                                  the transcript folder, worked out by the launcher in the
#                                  session's own folder and environment; copied into the record
#   <run>/sessions/<name>.transcript_prefix_real
#                                  where the runtime's data folder below it resolved at launch
#                                  (it may be a link); copied into the record
#   <run>/sessions/<name>.closing  present while a close is under way (stops model fallback)
#   <run>/sessions/<name>.failed   written by the launcher when the session could not start
#   <run>/launchers/<name>.sh      the generated launcher
#   <run>/logs/launcher.log        what the launchers report
#
# The launch command comes from the runtime profile named by runtime.main, read from the user
# folder or the plugin's runtimes/ (lib/runtime.sh, D37-RUNTIME-1). Accounts come from the user config only (agent decision, T7).
# Exit codes: 64 usage, 65 refused, 66 not found or another run's session, 69 the session
# did not start, 70 terminal failed, 71 the process facts cannot be read (nothing changed),
# 73 no free worker slot, 75 the run is stopped, 78 config, 1 close timed out.
#
# Requires lib/files.sh, lib/config.sh, lib/run.sh, lib/term.sh and lib/isolation.sh.

HO_SESSION_ROLES="orchestrator watcher worker validator question"

ho_session_usage() {
  cat >&2 <<'USAGE'
usage: harness session <run-dir> <verb> [args]
  launch --role R --name N --cwd DIR (--prompt FILE | --resume SESSION-ID) [--account A] [--model "a|b"]
         [--slot-wait SECONDS]   a worker waits this long for a worker slot (default 0); exit 73
                                 when the worker cap stays reached
         [--ticket ID]           the ticket the session works on; under a soft:ticket stop only
                                 a session of a ticket begun before the stop starts
  close <name>        ask the session to exit, wait for its exact process to end; never forced
  list                one line per session: name role status pid session-id handle
  deliver <name> (--text T | --file F) [--id ID] [--force-send]
                      send one instruction: message first, typing as a checked fallback
  proof <name> <id>   whether the session's transcript proves that instruction delivered
  status [name]       liveness facts, one JSON line per session (working, starting, dead,
                      closed, unknown); a silent session with a live process reads as working
  read <name> transcript|screen [--lines N]
                      the tail of the session's transcript or screen, fenced as untrusted;
                      reads only, never types
  hooks-check         the start check: name hooks in the settings sessions load that have no
                      time limit or one above the maximum; never edits them (D42l)
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
  f=$(ho_rt_file "$name") || return 78
  jq -e 'type == "object" and .schemaVersion == 2
    and (.command | type == "string" and length > 0)
    and ([.argv.new, .argv.resume, .argv.model, .argv.title, .argv.prompt] | all(type == "array" and all(type == "string" and (test("\n") | not))))
    and (.permissions | type == "object")
    and (.exit_command | type == "string" and length > 0 and (test("\n") | not))
    and ((.account_env // []) | type == "array" and all(type == "string" and test("\\A[A-Z_][A-Z0-9_]*\\z")))' "$f" >/dev/null 2>&1 || {
    printf 'harness: runtime file %s is not a valid schemaVersion 2 runtime\n' "$f" >&2
    return 78
  }
  printf '%s\n' "$f"
}

# ho_session_account_env <profile>: the runtime's account variables with the caller's values
# (issue #119). The names come from the runtime data: account_env, or else config_dir.env and
# transcript.root_env. One line per name: "NAME<tab>VALUE", or "NAME" alone when the caller has
# no value (an empty value counts as none). The launcher sets each one, or removes it, so a
# session's account never depends on what the terminal inherited: an iTerm2 tab starts a fresh
# login shell, and a tmux server keeps the environment of its first start. These variables
# hold folders, never secrets: a value must be one absolute path, or the launch is refused (65).
# ho_session_account_env_names <profile>: those names, one per line (the start check uses them too).
ho_session_account_env_names() {
  jq -r '(.account_env // [.config_dir.env, .transcript.root_env]) | map(strings) | unique | .[]' "$1"
}

# ho_session_account_cmd <profile> <command>: run an account command as the launcher runs it,
# with the runtime's account variables removed (the launcher unsets them first), so a command
# that reads one of them gets the same answer in the launch check, the start check and the
# launcher. With no profile it runs as it is.
ho_session_account_cmd() {
  local -a u=()
  local v
  if [ -n "$1" ]; then
    for v in $(ho_session_account_env_names "$1"); do u+=(-u "$v"); done
  fi
  /usr/bin/env ${u[@]+"${u[@]}"} /bin/bash -c "$2"
}

ho_session_account_env() {
  local profile=$1 var val
  for var in $(ho_session_account_env_names "$profile"); do
    case $var in [!A-Z_]* | *[!A-Z0-9_]* | PATH | HO_*)
      printf 'harness: account_env name %s in runtime %s is not a variable the harness may set\n' "$var" "$profile" >&2; return 65 ;;
    esac
    val=$(printenv "$var" 2>/dev/null; printf x) || val=x
    val=${val%x}
    val=${val%$'\n'}
    if [ -z "$val" ]; then printf '%s\n' "$var"; continue; fi
    case $val in
      *$'\n'* | *$'\t'*) printf 'harness: %s has a line break or a tab; the session was not launched\n' "$var" >&2; return 65 ;;
      /*) ;;
      *) printf 'harness: %s must be an absolute folder path; the session was not launched\n' "$var" >&2; return 65 ;;
    esac
    printf '%s\t%s\n' "$var" "$val"
  done
}

# ho_session_account_env_lines <account-env> <account>: the launcher lines for them. With an
# account command the variables are removed, and the command sets what it sets: the caller's
# folder belongs to the caller's account, not the role's.
ho_session_account_env_lines() {
  local line
  printf '%s\n' "$1" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    case $line in
      *$'\t'*) if [ -n "$2" ]; then printf 'unset %s\n' "${line%%$'\t'*}"; else printf 'export %s=%s\n' "${line%%$'\t'*}" "$(ho_q "${line#*$'\t'}")"; fi ;;
      *) printf 'unset %s\n' "$line" ;;
    esac
  done
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

# ho_session_account_name <role>: the account the user config maps the role to, or nothing.
ho_session_account_name() {
  ho_cfg_user ".accounts.roles[\"$1\"] // .accounts.roles.default" | jq -r '. // ""'
}

# ho_session_account <role> <requested> [profile]: print "<account>\t<env-command>", or nothing when no
# account is configured. Refuses (65) a mismatch, an unknown account, or a command that fails.
ho_session_account() {
  local role=$1 want=$2 profile=${3-} proj mapped cmd out
  proj=$(ho_project_config_file "$HO_PROJECT_DIR")
  if jq -e '.accounts != null' "$proj" >/dev/null 2>&1; then
    printf 'harness: accounts are set in the project config %s; accounts belong in the user config only\n' "$proj" >&2
    return 65
  fi
  mapped=$(ho_session_account_name "$role") || return 78
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
  out=$(ho_session_account_cmd "$profile" "$cmd" 2>/dev/null) || { printf 'harness: the env_command of account %s failed\n' "$mapped" >&2; return 65; }
  printf '%s\n' "$out" | ho_account_env_parse >/dev/null || {
    printf 'harness: the env_command of account %s must print KEY=VALUE lines only\n' "$mapped" >&2
    return 65
  }
  # The variables as printed, for a caller that must not run the command a second time.
  HO_SESSION_ACCOUNT_ENV=$out
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
# repository and of each configured repo (D37-FLOW-8, security review of #90).
ho_session_project_roots() {
  local proj cfg d r
  proj=$(cd "$HO_PROJECT_DIR" && pwd -P) || return 1
  cfg=$(ho_project_config_file "$HO_PROJECT_DIR")
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
  cmd=$(ps -ww -o command= -p "$pid" 2>/dev/null) || return 1
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
  local log=${10} path=${11} grace=${12} hold=${13} cmdpath=${14} attempts=${15} profile=${16} aenv=${17}
  printf '#!/bin/bash\n'
  printf '# ho-launcher run=%s name=%s role=%s account=%s session=%s\n' "$HO_RUN_ID" "$name" "$role" "${account:--}" "$sid"
  printf '# Generated by the harness engine. Do not edit; launch it again instead.\n'
  printf 'set -u\n'
  printf 'HO_LOG=%s\n' "$(ho_q "$log")"
  printf 'ho_note() { printf '"'"'[%%s %%s] %%s\\n'"'"' "$(date -u +%%H:%%M:%%S)" %s "$*" >> "$HO_LOG"; printf '"'"'%%s\\n'"'"' "$*" >&2; }\n' "$(ho_q "$name")"
  printf 'ho_fatal() { ho_note "FATAL: $2"; printf '"'"'%%s\\n'"'"' "$2" > %s; sleep %s; exit "$1"; }\n' "$(ho_q "${pidfile%.pid}.failed")" "$hold"
  printf 'unset %s\n' "$HO_OLD_VARS"
  ho_session_account_env_lines "$aenv" "$account"
  printf 'export PATH=%s\n' "$(ho_q "$path")"
  printf 'export HO_PROJECT_DIR=%s HO_RUN_DIR=%s HO_RUN_ID=%s\n' "$(ho_q "$HO_PROJECT_DIR")" "$(ho_q "$HO_RUN_DIR")" "$(ho_q "$HO_RUN_ID")"
  printf 'export HO_SESSION_NAME=%s HO_SESSION_ROLE=%s HO_SESSION_ID=%s\n' "$(ho_q "$name")" "$(ho_q "$role")" "$(ho_q "$sid")"
  # D28: the account label the status line records its limits under (lib/limits.sh).
  printf 'export HO_ACCOUNT=%s\n' "$(ho_q "${account:-default}")"
  # Issue #129: the user config folder of the run, so "run tick" inside a session reads the same
  # gate, accounts, limits and channels as the start (checked by the launch).
  printf 'export HO_USER_DIR=%s\n' "$(ho_q "$(ho_user_dir)")"
  # H-089 (D37-SESSIONS-2): the mark the liveness hook needs; without it the hook does nothing.
  # A config read that fails keeps every event on, never silently none.
  local hook_events
  hook_events=$(ho_live_hook_events) || hook_events=$HO_LIVE_HOOK_EVENTS_ALL
  printf 'export HO_HOOK_LOG=%s HO_HOOK_EVENTS=%s\n' "$(ho_q "$(ho_live_hook_log)")" "$(ho_q "$hook_events")"
  # H-105: before anything slow, the launcher records itself (PID and start time), then reads
  # the close flag. A slot is freed only after its close flag is written and no process of the
  # session is found (lib/slots.sh), so a launcher either counts as alive or starts nothing.
  declare -f ho_proc_start
  printf 'ho_self=$(ho_proc_start "$$")\n'
  printf '[ -n "$ho_self" ] && printf '"'"'%%s %%s\\n'"'"' "$$" "$ho_self" > %s && mv -f %s %s || ho_fatal 70 "cannot record the launcher process; the session was not started"\n' \
    "$(ho_q "${pidfile%.pid}.launcher.tmp")" "$(ho_q "${pidfile%.pid}.launcher.tmp")" "$(ho_q "${pidfile%.pid}.launcher")"
  printf '[ -e %s ] && { ho_note "a close is under way; not starting"; : > %s; exit 0; }\n' "$(ho_q "$closing")" "$(ho_q "${pidfile%.pid}.ended")"
  printf 'cd -- %s || ho_fatal 66 "cannot enter the working folder; the session was not started"\n' "$(ho_q "$cwd")"
  if [ -n "$account" ]; then
    declare -f ho_account_env_parse
    printf 'ho_acct=$(/bin/bash -c %s 2>>"$HO_LOG") || ho_fatal 9 "the account command failed; the session was not started"\n' "$(ho_q "$acct_cmd")"
    printf 'ho_acct=$(printf '"'"'%%s\\n'"'"' "$ho_acct" | ho_account_env_parse) || ho_fatal 9 "the account command printed no usable KEY=VALUE line"\n'
    printf 'while IFS="$(printf '"'"'\\t'"'"')" read -r ho_k ho_v; do export "$ho_k=$ho_v"; done <<HO_ACCT\n$ho_acct\nHO_ACCT\n'
    printf 'ho_note %s\n' "$(ho_q "account $account applied")"
  fi
  # H-090: the transcript folder, worked out here, after the cd and the account's variables, so
  # it is the folder the session itself uses (an account command may build it from $PWD or set
  # HOME). One function for the rule (lib/liveness.sh); the account command runs only here.
  declare -f ho_live_transcript_root
  printf 'ho_troot=$(ho_live_transcript_root %s "" 2>/dev/null) || ho_troot=""\n' "$(ho_q "$profile")"
  # Issue #103: a unique temp name (mktemp, mode 600) in the same folder, and a log line when
  # no folder could be worked out, so a missing transcript is never silent.
  printf 'if [ -z "$ho_troot" ]; then ho_note "no transcript folder could be worked out; liveness reads the transcript as missing"\n'
  printf 'else ho_t=$(mktemp %s 2>/dev/null) && { printf '"'"'%%s\n'"'"' "$ho_troot" > "$ho_t" && mv -f "$ho_t" %s || rm -f "$ho_t"; } 2>/dev/null || true; fi\n' \
    "$(ho_q "${pidfile%.pid}.transcript_root.XXXXXX")" "$(ho_q "${pidfile%.pid}.transcript_root")"
  # The runtime's data folder below it (the glob's fixed leading part) may be a link in a
  # multi-account layout. Where it resolves now is recorded once, here, so delivery accepts
  # that one link only while it still leads to the same real folder (lib/deliver.sh).
  declare -f ho_live_transcript_prefix
  printf 'ho_tpre=$(ho_live_transcript_prefix %s)\n' "$(ho_q "$(jq -r '.transcript.glob // ""' "$profile" 2>/dev/null)")"
  printf 'ho_treal=""; [ -z "$ho_troot" ] || [ -z "$ho_tpre" ] || ho_treal=$(cd "$ho_troot/$ho_tpre" 2>/dev/null && pwd -P) || ho_treal=""\n'
  printf '[ -z "$ho_treal" ] || { ho_t=$(mktemp %s 2>/dev/null) && { printf '"'"'%%s\n'"'"' "$ho_treal" > "$ho_t" && mv -f "$ho_t" %s || rm -f "$ho_t"; }; } 2>/dev/null || true\n' \
    "$(ho_q "${pidfile%.pid}.transcript_prefix_real.XXXXXX")" "$(ho_q "${pidfile%.pid}.transcript_prefix_real")"
  if [ -n "$prompt" ]; then
    printf 'HO_PROMPT=$(cat %s) || ho_fatal 65 "cannot read the prompt file"\n' "$(ho_q "$prompt")"
  fi
  # Each attempt writes its own PID, then becomes the session process (exec), so the PID
  # recorded is exactly the session's process. Between the two it looks for the close flag
  # once more: a launch that gave up writes the flag first and reads the PID file after, so
  # either the launch sees this process, or this process sees the flag and never starts.
  printf 'ho_attempt() {\n'
  printf '  /bin/sh -c '"'"'printf "%%s %%s %%s\\n" "$$" "$1" "$2" > "$3.tmp" && mv -f "$3.tmp" "$3" || exit 70; [ -e "$4" ] && exit 0; shift 4; exec "$@"'"'"' ho-session %s %s %s %s "$@"\n' \
    "$(ho_q "$HO_RUN_ID")" "$(ho_q "$sid")" "$(ho_q "$pidfile")" "$(ho_q "$closing")"
  printf '}\n'
  printf '%s\n' "$attempts" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '[ -e %s ] && { ho_note "a close is under way; not starting"; : > %s; exit 0; }\n' "$(ho_q "$closing")" "$(ho_q "${pidfile%.pid}.ended")"
    printf 'ho_t0=$(date +%%s)\n'
    printf 'ho_note %s\n' "$(ho_q "starting session $sid")"
    printf 'ho_attempt %s %s\n' "$(ho_q "$cmdpath")" "$line"
    printf 'ho_rc=$?; ho_dt=$(( $(date +%%s) - ho_t0 ))\n'
    printf 'if [ "$ho_rc" -eq 0 ] || [ "$ho_dt" -gt %s ] || [ -e %s ]; then ho_note "session ended rc=$ho_rc after ${ho_dt}s"; : > %s; exit "$ho_rc"; fi\n' "$grace" "$(ho_q "$closing")" "$(ho_q "${pidfile%.pid}.ended")"
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
$(jq -r --arg sid "$sid" --arg model "$m" --arg title "$title" --arg perm "$perm" --arg resume "$resume" --arg sl "${HO_SL_FILE-}" '
    def fill: gsub("\\{session_id\\}"; $sid) | gsub("\\{model\\}"; $model) | gsub("\\{title\\}"; $title) | gsub("\\{status_settings\\}"; $sl);
    (if $resume == "1" then .argv.resume else .argv.new end)
    + (if $model != "" then .argv.model else [] end)
    + .argv.title
    + (if $sl != "" then (.status_line.argv // []) else [] end)
    + .permissions[$perm]
    + (if $resume == "1" then [] else .argv.prompt end)
    | map(fill) | .[]' "$profile")
EOF_ARGV
    printf '%s\n' "${line# }"
  done
}

# H-105, D26a: a worker launch takes a worker slot before anything is opened. The slot is held
# from then until close, or until the session reads dead or closed. A failed launch gives it
# back only when its session reads dead (or never got a record): a session can come up at the
# boot timeout, or after a terminal open that failed late, and while its process runs it holds
# the slot. A failed open and a boot time-out write the close flag before they return, so the
# launcher starts no session after this check (see ho_attempt in the launcher).
ho_session_launch() {
  local rc=0 rec v
  HO_SLOT_TAKEN=""
  ho_session_launch_one "$@" || rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$HO_SLOT_TAKEN" ]; then
    rec="$HO_RUN_DIR/sessions/$HO_SLOT_TAKEN.json"
    v=dead
    [ ! -f "$rec" ] || v=$(ho_live_verdict "$rec")
    case $v in
      dead | closed) ho_slot_give worker "$HO_SLOT_TAKEN" ;;
      *)
        ho_ledger_append slot-kept kind worker holder "$HO_SLOT_TAKEN" reason "launch failed but the session reads $v"
        printf 'harness: session %s reads %s after the failed launch; it keeps its worker slot until it is closed or ends\n' "$HO_SLOT_TAKEN" "$v" >&2
        ;;
    esac
  fi
  return "$rc"
}

ho_session_launch_one() {
  local role="" name="" cwd="" prompt="" account="" chain="" resume="" slot_wait=0 ticket=""
  while [ $# -gt 0 ]; do
    case $1 in
      --role | --name | --cwd | --prompt | --account | --model | --resume | --slot-wait | --ticket)
        [ $# -ge 2 ] || { ho_session_usage; return 64; }
        case $1 in
          --role) role=$2 ;; --name) name=$2 ;; --cwd) cwd=$2 ;; --prompt) prompt=$2 ;;
          --account) account=$2 ;; --model) chain=$2 ;; --resume) resume=$2 ;; --slot-wait) slot_wait=$2 ;;
          --ticket) ticket=$(ho_stop_ticket_arg "$2") || return 64 ;;
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
  # A stopped run launches nothing new (H-086, D25a). Only a soft:ticket stop lets a session of a
  # ticket that began before the stop start, so that ticket can run to its end.
  # H-110 (D28): a limit threshold whose action pauses spawns refuses a worker start (74). An
  # unreadable limit never refuses (H-111). It runs first, so a soft stop it records is seen below.
  local lrc=0
  ho_limits_gate "$role" || lrc=$?
  [ "$lrc" -eq 0 ] || return "$lrc"
  # D22: no new session while the service is down.
  if ho_watch_outage_open; then echo "harness: the service is down (an outage is open in the run ledger); no session is launched" >&2; return "$HO_EXIT_OUTAGE"; fi
  local stopped=0
  # D37-SESSIONS-4: during a soft stop the orchestrator still has work, so it and the context
  # watcher may be (re)started under a soft stop; an unknown stop state still refuses.
  case $role in
    orchestrator | watcher) ho_stop_gate_soft || stopped=$? ;;
    *) ho_stop_gate "$ticket" || stopped=$? ;;
  esac
  [ "$stopped" -eq 0 ] || { echo "harness: the run is stopped (or its stop state is unknown); no session is launched" >&2; return 75; }
  # An ended run launches nothing (H-079); a recorded resume ("state <run> resume") opens it again.
  ! ho_run_ended || { echo "harness: the run has ended; no session is launched (record a resume to open it again)" >&2; return 75; }
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
  local profile perm cmd cmdpath models acct acct_name="" acct_cmd="" udir
  # Issue #129: a session gets the run's user config folder, never another one.
  ho_run_user_dir_check || return 65
  udir=$(ho_user_dir) || return 65
  profile=$(ho_runtime_profile) || return $?
  # D37-FLOW-8: the permission mode is never read from the project config (interim, fail
  # closed, until the local approval record of D37-FLOW-8 (b) exists).
  perm=$(jq -r 'if (.session.permissions // null) == null or .session.permissions == "" then "" else "set" end' \
    "$(ho_project_config_file "$HO_PROJECT_DIR")" 2>/dev/null) || perm=set
  if [ -n "$perm" ]; then
    printf 'harness: the project config %s sets session.permissions. A project config may not set the permission mode until the local approval record exists; move session.permissions to the user config %s\n' \
      "$(ho_project_config_file "$HO_PROJECT_DIR")" "$(ho_user_config)" >&2
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
  acct=$(ho_session_account "$role" "$account" "$profile") || return 65
  if [ -n "$acct" ]; then
    acct_name=${acct%%"$(printf '\t')"*}
    acct_cmd=${acct#*"$(printf '\t')"}
  fi
  local aenv
  aenv=$(ho_session_account_env "$profile") || return 65
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
  # Files of an earlier launch of this name (its record was removed) must not speak for this one.
  rm -f "$sdir/$name.pid" "$sdir/$name.closing" "$sdir/$name.failed" "$sdir/$name.launcher" "$sdir/$name.ended" \
    "$sdir/$name.transcript_root" "$sdir/$name.transcript_prefix_real"
  # The reserved record says "launching" and names this launch command (PID and start time)
  # from its first write. It reads dead only once this command, the launcher and the session
  # process are all gone (lib/liveness.sh), never by its age: a launch may wait for a slot or
  # for its account command for as long as it needs.
  local launch_pid=$$ launch_start pid_ns
  pid_ns=$(ho_live_ns)
  launch_start=$(ho_proc_start "$launch_pid")
  [ -n "$launch_start" ] || { rm -f "$rec"; echo "harness: cannot read the start time of the launch process; nothing was launched" >&2; return 1; }
  jq -n --arg run "$HO_RUN_ID" --arg name "$name" --arg role "$role" --arg ts "$(ho_now)" \
    --argjson lp "$launch_pid" --arg ls "$launch_start" --arg ns "$pid_ns" --arg ticket "$ticket" \
    '{schemaVersion: 2, run: $run, name: $name, role: $role, session_id: null, pid: null, status: "launching", created: $ts,
      launch_pid: $lp, launch_start: $ls, pid_ns: $ns, ticket: (if $ticket == "" then null else $ticket end)}' \
    | ho_atomic_write "$rec" || { rm -f "$rec"; return 1; }
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
    # A stop recorded while this launch waited ends it here: no worker starts in a stopped run.
    stopped=0
    ho_stop_gate "$ticket" || stopped=$?
    if [ "$stopped" -ne 0 ]; then
      rm -f "$rec"
      echo "harness: the run was stopped (or its stop state is unknown) while the launch waited; no session is launched" >&2
      return 75
    fi
    if ho_run_ended; then
      rm -f "$rec"
      echo "harness: the run ended while the launch waited; no session is launched" >&2
      return 75
    fi
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
      --argjson lp "$launch_pid" --arg ls "$launch_start" --arg ns "$pid_ns" --arg ticket "$ticket" \
      '{schemaVersion: 2, run: $run, name: $name, session_id: $sid, pid: null, pid_file: $pidfile, status: "launching", created: $ts,
        launch_pid: $lp, launch_start: $ls, pid_ns: $ns, ticket: (if $ticket == "" then null else $ticket end)}' \
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
  # Pre-trust the working folder before the session starts (reuse list: pre-trust inside the
  # project only), and only with the person's consent: the project folder must already be
  # trusted in the runtime (PR #97 review). Without that consent nothing is written and the
  # launch stops with one owner action. Any other failure to pre-trust is not a launch
  # failure: the runtime then holds the folder itself, its dialog shows on the screen and
  # becomes an owner action (lib/screen.sh), and nothing is ever typed into it.
  local trust_rc=0 trust_why=""
  if [ -n "$acct_cmd" ]; then
    # The account command may move the runtime config folder for this session only, and the
    # engine cannot read that folder without running the command a second time. So nothing
    # is written, and the runtime's own trust hold applies.
    trust_rc=78
    trust_why="the account command may move the runtime config folder"
  else
    ho_screen_pretrust "$cwd" >/dev/null 2>&1 || trust_rc=$?
    trust_why="exit $trust_rc"
  fi
  if [ "$trust_rc" -eq 77 ]; then
    rm -f "$rec"
    ho_ledger_append pretrust-refused name "$name" cwd "$cwd" reason "the project is not trusted in the runtime"
    ho_ledger_append owner-action title "project not trusted in the runtime" \
      why "the harness trusts a working folder only after you have trusted the project once yourself" \
      command "open the project once in the runtime and accept its trust question" \
      verify "the next launch of session $name starts"
    printf 'harness: the project %s is not trusted in the runtime; open it once in the runtime and accept its trust question. Session %s was not launched.\n' "$HO_PROJECT_DIR" "$name" >&2
    return 77
  fi
  [ "$trust_rc" -eq 0 ] || ho_ledger_append pretrust-skipped name "$name" cwd "$cwd" reason "$trust_why"
  # D28: the status line of each session records its account's limits (lib/limits.sh). The
  # settings file comes from runtime data (status_line.settings); a runtime without it gets none.
  local sl_file=""
  if jq -e '(.status_line.settings | type) == "object" and (.status_line.argv | type) == "array"' "$profile" >/dev/null 2>&1; then
    sl_file="$HO_RUN_DIR/status-line-settings.json"
    jq --arg cmd "$(ho_q "$HO_ROOT/bin/harness") limits record" \
      '.status_line.settings | walk(if type == "string" then gsub("\\{record_command\\}"; $cmd) else . end)' "$profile" \
      | ho_atomic_write "$sl_file" || { rm -f "$rec"; return 1; }
  fi
  attempts=$(HO_SL_FILE=$sl_file ho_session_attempts "$profile" "$sid" "$title" "$perm" "$([ -n "$resume" ] && echo 1 || echo 0)" "$models") || { rm -f "$rec"; return 78; }

  ho_session_launcher_text "$name" "$role" "$acct_name" "$acct_cmd" "$sid" "$cwd" "$prompt" "$pidfile" "$closing" \
    "$HO_RUN_DIR/logs/launcher.log" "$path" "$(ho_cfg_int '.session.boot_grace_seconds' 45)" \
    "$(ho_cfg_int '.session.fatal_hold_seconds' 30)" "$cmdpath" "$attempts" "$profile" "$aenv" > "$launcher.tmp" || { rm -f "$rec" "$launcher.tmp"; return 1; }
  # The launcher must say exactly what was asked for, or it is not used.
  if ! /bin/bash -n "$launcher.tmp" 2>/dev/null \
    || [ "$(sed -n 2p "$launcher.tmp")" != "# ho-launcher run=$HO_RUN_ID name=$name role=$role account=${acct_name:--} session=$sid" ] \
    || ! grep -qxF "cd -- $(ho_q "$cwd") || ho_fatal 66 \"cannot enter the working folder; the session was not started\"" "$launcher.tmp" \
    || [ "$(grep -E '^(export|unset) ' "$launcher.tmp" | grep -vE '^(unset HARNESS_|export (PATH|HO_))')" != "$(ho_session_account_env_lines "$aenv" "$acct_name")" ]; then
    rm -f "$rec" "$launcher.tmp"
    echo "harness: the generated launcher does not match the request; nothing was launched" >&2
    return 65
  fi
  chmod 700 "$launcher.tmp" && mv -f "$launcher.tmp" "$launcher" || { rm -f "$rec" "$launcher.tmp"; return 1; }

  local backend
  backend=$(ho_term_backend) || { local rc=$?; rm -f "$rec"; return "$rc"; }
  # H-090: the transcript folder is worked out by the launcher in the session's own folder and
  # environment (<name>.transcript_root), and copied into the record once the session runs.
  jq -n --arg run "$HO_RUN_ID" --arg name "$name" --arg role "$role" --arg account "$acct_name" \
    --arg runtime "$(basename "$profile" .json)" --arg sid "$sid" --arg cwd "$cwd" --arg launcher "$launcher" \
    --arg pidfile "$pidfile" --arg chain "$chain" --arg backend "$backend" --arg ts "$(ho_now)" --arg tag "$tag" \
    --arg rpath "$cmdpath" --argjson lp "$launch_pid" --arg ls "$launch_start" --arg ns "$pid_ns" --arg aenv "$aenv" \
    --arg ticket "$ticket" --arg udir "$udir" \
    '{schemaVersion: 2, run: $run, name: $name, role: $role, account: (if $account == "" then null else $account end),
      account_env: (if $account != "" then null else ($aenv | split("\n") | map(select(. != "") | split("\t") | {key: .[0], value: .[1]}) | from_entries) end),
      runtime: $runtime, runtime_path: $rpath, session_id: $sid, pid: null, backend: $backend, handle: null, term_tag: $tag, cwd: $cwd,
      launcher: $launcher, pid_file: $pidfile, model_chain: $chain, status: "launching", created: $ts,
      transcript_root: null, launch_pid: $lp, launch_start: $ls, pid_ns: $ns, ticket: (if $ticket == "" then null else $ticket end),
      user_dir: $udir}' \
    | ho_atomic_write "$rec" || { rm -f "$rec"; return 1; }
  ho_ledger_append session-launch name "$name" role "$role" session_id "$sid" account "$acct_name" ticket "$ticket"

  # A worker opens a terminal only while it holds its slot. Only a proven end frees a slot, and
  # this launch is alive, so this holds; the check keeps any later change from opening a worker
  # without one.
  if [ "$role" = worker ] && [ ! -f "$HO_RUN_DIR/slots/worker/$name.json" ]; then
    rm -f "$rec"
    printf 'harness: %s no longer holds a worker slot; nothing was opened\n' "$name" >&2
    return "$HO_SLOT_NOSLOT"
  fi
  local handle rc=0
  handle=$(ho_term_open "$group" "$title" "$launcher" "$tag" "$sid") || rc=$?
  if [ "$rc" -ne 0 ]; then
    : > "$closing" 2>/dev/null || true
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
    # The flag comes before the slot decision: from here on the launcher starts no session,
    # so a session that reads dead now stays dead and its slot can be given back.
    : > "$closing" 2>/dev/null || true
    ho_session_set "$rec" '.status = "boot-failed"' || true
    ho_ledger_append session-boot-failed name "$name" session_id "$sid"
    printf 'harness: session %s did not start; see %s\n' "$name" "$HO_RUN_DIR/logs/launcher.log" >&2
    return 69
  fi
  local troot=""
  troot=$(head -n 1 "$sdir/$name.transcript_root" 2>/dev/null) || troot=""
  case $troot in /*) ;; *) troot="" ;; esac
  local treal=""
  treal=$(head -n 1 "$sdir/$name.transcript_prefix_real" 2>/dev/null) || treal=""
  case $treal in /*) ;; *) treal="" ;; esac
  # Issue #103: the session can rewrite its notes before this copy, so the record keeps only a
  # checked value (ho_live_transcript_root_ok), and the notes are removed here, so nothing reads
  # them after the record holds the folder.
  rm -f "$sdir/$name.transcript_root" "$sdir/$name.transcript_prefix_real"
  if [ -n "$troot" ] && ! ho_live_transcript_root_ok "$troot"; then
    ho_ledger_append transcript-root-refused name "$name" reason "the transcript folder is not one absolute path"
    troot="" treal=""
  fi
  if [ -n "$treal" ] && ! ho_live_transcript_root_ok "$treal"; then treal=""; fi
  ho_session_set "$rec" '.pid = ($p | tonumber) | .status = "running" | .started = $ts
      | (if $t != "" then .transcript_root = $t else . end)
      | (if $t != "" and $r != "" then .transcript_prefix_real = $r else . end)' --arg p "$pid" --arg ts "$(ho_now)" --arg t "$troot" --arg r "$treal" || {
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
  # Close marks a session closed and frees its slots only on proof (lib/liveness.sh). A caller
  # that cannot read the process facts of this record changes nothing.
  if ! ho_live_view_ok "$rec"; then
    printf 'harness: the process table cannot be read here, so session %s cannot be checked; nothing was closed\n' "$name" >&2
    return 71
  fi
  # A launching record may be closed once the launch command that wrote it is gone (its own
  # check, not the record's age). Its session, if one runs, is then closed as any other.
  if [ "$status" = launching ] && [ "$(ho_live_launch_cmd_state "$rec")" != gone ]; then
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
  local sstate
  sstate=$(ho_live_session_state "$rec")
  if [ "$sstate" = unknown ]; then
    rm -f "$closing"
    printf 'harness: the process of session %s can be neither seen nor proven gone from here; nothing was closed\n' "$name" >&2
    return 71
  fi
  pid=""
  [ "$sstate" = gone ] || pid=$(ho_session_live_pid "$rec") || return 1
  if [ "$sstate" = gone ]; then
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
  # The same profile lookup as the launch (user folder first, then the plugin).
  profile=$(ho_rt_file "$(jq -r '.runtime // ""' "$rec")" 2>/dev/null) || profile=""
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
  while [ "$(ho_live_sid_state "$pid" "$sid")" != gone ]; do
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
  if [ "$(ho_live_session_state "$rec")" != gone ]; then
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

# ho_session_capture <name> <out-file>: write the tail of that session's screen to a file,
# through the backend the session was launched with and only while the terminal still carries
# this session's tag and session ID. The text goes to a file, never to standard output, so a
# screen never lands in a log, a ledger line or a terminal (field notes I2, I4).
#   0 written, 66 no such session or the terminal is not this session's, 70 the terminal failed.
ho_session_capture() {
  local name=${1-} out=${2-} rec handle tag sid lines rc=0
  [ -n "$name" ] && [ -n "$out" ] || { echo "harness: session capture <name> <out-file>" >&2; return 64; }
  ho_session_name_ok "$name" || return 65
  rec="$HO_RUN_DIR/sessions/$name.json"
  [ -f "$rec" ] || { printf 'harness: no session %s in run %s\n' "$name" "$HO_RUN_ID" >&2; return 66; }
  [ "$(jq -r 'if type == "object" then (.run // "") else "" end' "$rec" 2>/dev/null || echo "")" = "$HO_RUN_ID" ] \
    || { printf 'harness: session %s is not recorded under run %s; its screen is not read\n' "$name" "$HO_RUN_ID" >&2; return 66; }
  handle=$(jq -r '.handle // ""' "$rec")
  tag=$(jq -r '.term_tag // ""' "$rec")
  sid=$(jq -r '.session_id // ""' "$rec")
  [ -n "$handle" ] || { printf 'harness: session %s has no terminal handle; its screen cannot be read\n' "$name" >&2; return 66; }
  lines=$(ho_cfg_int '.screen.capture_lines' 40)
  HO_TERM_BACKEND=$(jq -r '.backend // ""' "$rec")
  export HO_TERM_BACKEND
  ho_term_capture "$handle" "$tag" "$sid" "$lines" > "$out.tmp" 2>/dev/null || rc=$?
  unset HO_TERM_BACKEND
  if [ "$rc" -ne 0 ]; then
    rm -f "$out.tmp"
    printf 'harness: could not read the screen of session %s (exit %s)\n' "$name" "$rc" >&2
    return "$rc"
  fi
  mv "$out.tmp" "$out" || return 1
  chmod 600 "$out" 2>/dev/null || true
}

# ho_session_bind_project: find the project that holds the open run, check it and export it.
ho_session_bind_project() {
  local proj
  proj=$(cd "$HO_RUN_DIR/../../.." && pwd -P)
  ho_is_project "$proj" || { printf 'harness: run %s is not inside a harness project\n' "$HO_RUN_DIR" >&2; return 78; }
  if [ -n "${HO_PROJECT_DIR:-}" ] && [ "$(cd "$HO_PROJECT_DIR" 2>/dev/null && pwd -P)" != "$proj" ]; then
    printf 'harness: run %s belongs to project %s, not HO_PROJECT_DIR=%s\n' "$HO_RUN_DIR" "$proj" "$HO_PROJECT_DIR" >&2
    return 65
  fi
  export HO_PROJECT_DIR=$proj
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
  local verb=$2
  shift 2
  ho_session_bind_project || exit $?
  local rc=0
  case $verb in
    launch) ho_session_launch "$@" || rc=$? ;;
    close) ho_session_close "$@" || rc=$? ;;
    list) ho_session_list ;;
    deliver) ho_session_deliver "$@" || rc=$? ;;
    proof) ho_session_proof "$@" || rc=$? ;;
    status) ho_live_status "$@" || rc=$? ;;
    read) ho_live_read "$@" || rc=$? ;;
    hooks-check) ho_live_hooks_check "$@" || rc=$? ;;
    *) ho_session_usage; rc=64 ;;
  esac
  exit "$rc"
}
