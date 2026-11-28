# shellcheck shell=bash
# Config lookup (design "Rebuild" reuse list; D28a uses the same order for limit thresholds):
# project value, then user value, then the default. Only a missing key or JSON null falls
# through; false and 0 are real values. A config file that exists must be readable JSON with
# schemaVersion 2, or the engine refuses it (exit 78). It is never skipped silently.
#
#   project config  <project>/.harness/config.json
#   user config     $HO_USER_DIR/config.json   (default $HOME/.claude/harness)

HO_CONFIG_SCHEMA=2
HO_EXIT_CONFIG=78

# ho_project_root needs ho_is_project from lib/select.sh (committed configs and the local
# selection). Load it here, so this file is safe to source alone.
if ! declare -F ho_is_project >/dev/null 2>&1; then
  # shellcheck source=select.sh
  . "$(dirname "${BASH_SOURCE[0]}")/select.sh"
fi

# ho_project_root: print the project folder (the one holding .harness/config.json).
# Order: $HO_PROJECT_DIR, then walk up from $PWD to .harness/config.json or to a
# .harness-project pointer file (a worktree outside the project carries one).
ho_project_root() {
  local d p
  if [ -n "${HO_PROJECT_DIR:-}" ]; then
    ho_is_project "$HO_PROJECT_DIR" && { printf '%s\n' "$HO_PROJECT_DIR"; return 0; }
    printf 'harness: HO_PROJECT_DIR=%s has no .harness/config.json, named config or local selection\n' "$HO_PROJECT_DIR" >&2
    return 1
  fi
  d=$PWD
  while :; do
    if ho_is_project "$d"; then
      # A linked git worktree reads the main checkout's selection (D37-FLOW-5).
      if [ -f "$d/.git" ] && p=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
        case $p in */.git) p=${p%/.git}; ho_is_project "$p" && { printf '%s\n' "$p"; return 0; } ;; esac
      fi
      printf '%s\n' "$d"
      return 0
    fi
    if [ -f "$d/.harness-project" ]; then
      p=$(head -n 1 "$d/.harness-project")
      [ -n "$p" ] && ho_is_project "$p" && { printf '%s\n' "$p"; return 0; }
    fi
    [ "$d" = / ] && break
    d=$(dirname "$d")
  done
  return 1
}

ho_user_config() { printf '%s/config.json\n' "${HO_USER_DIR:-$HOME/.claude/harness}"; }

# ho_user_dir: the user config folder this command runs with (HO_USER_DIR, else the default
# under HOME), resolved once: one absolute path, no line break or tab, no trailing slash.
# Issue #129: a run records it, every session it launches gets it, and a command of the run
# that runs with another folder is refused (ho_run_user_dir_check).
ho_user_dir() {
  local d=${HO_USER_DIR:-$HOME/.claude/harness}
  case $d in
    *$'\n'* | *$'\t'*) echo "harness: HO_USER_DIR has a line break or a tab" >&2; return 65 ;;
    /*) ;;
    *) printf 'harness: HO_USER_DIR must be an absolute folder path, not %s\n' "$d" >&2; return 65 ;;
  esac
  while [ "$d" != / ] && [ "${d%/}" != "$d" ]; do d=${d%/}; done
  printf '%s\n' "$d"
}

# ho_run_user_dir_check [warn]: 0 when the open run recorded no user config folder (a run of an
# older engine) or the one this command runs with. Else 65 with the run's folder named: the
# gate, accounts, limits and channels of a run come from one user config. With "warn" (a read
# only verb) the mismatch is printed and 0 returned. The recorded folder is never adopted: run
# state is writable by sessions, and the user config holds commands (agent decision, D37).
ho_run_user_dir_check() {
  local recd cur
  recd=$(jq -r '.userDir // "" | strings' "$HO_RUN_DIR/run.json" 2>/dev/null) || recd=""
  [ -n "$recd" ] || return 0
  cur=$(ho_user_dir) || return 65
  [ "$recd" = "$cur" ] && return 0
  if [ -d "$recd" ] && [ -d "$cur" ] && [ "$(cd -P "$recd" && pwd -P)" = "$(cd -P "$cur" && pwd -P)" ]; then return 0; fi
  printf 'harness: run %s was started with the user config folder %s, and this command runs with %s. Run it with HO_USER_DIR=%s; nothing was changed.\n' \
    "$HO_RUN_ID" "$recd" "$cur" "$recd" >&2
  [ "${1-}" = warn ] && return 0
  return 65
}

# ho_config_file_check <file>: 0 if absent or valid schema 2; else print why and exit 78.
ho_config_file_check() {
  local f=$1 v
  [ -e "$f" ] || return 0
  if ! v=$(jq -r 'if type == "object" then (.schemaVersion | tojson) else error("not an object") end' "$f" 2>/dev/null); then
    printf 'harness: config %s is unreadable (not a JSON object). Fix it or copy a template from templates/.\n' "$f" >&2
    exit "$HO_EXIT_CONFIG"
  fi
  if [ "$v" != "$HO_CONFIG_SCHEMA" ]; then
    printf 'harness: config %s has schemaVersion %s; this engine needs schemaVersion 2. A 0.6.0 config is schemaVersion 1: start from templates/*-config.example.json and set schemaVersion 2.\n' "$f" "$v" >&2
    exit "$HO_EXIT_CONFIG"
  fi
}

# ho_config_files: print the config files in lookup order (project first), each checked.
# The project file is the selected committed config (lib/select.sh), none on the confirmed
# default, or .harness/config.json while nothing is selected yet.
ho_config_files() {
  local proj user pf
  user=$(ho_user_config)
  if proj=$(ho_project_root 2>/dev/null); then
    pf=$(ho_sel_project_config "$proj") || exit "$HO_EXIT_CONFIG"
    if [ -n "$pf" ]; then
      ho_config_file_check "$pf"
      printf '%s\n' "$pf"
    fi
  elif [ -n "${HO_PROJECT_DIR:-}" ]; then
    ho_project_root >/dev/null || true
    exit "$HO_EXIT_CONFIG"
  fi
  ho_config_file_check "$user"
  [ -f "$user" ] && printf '%s\n' "$user"
  return 0
}

# ho_project_config_file <project>: the project config file the lookup reads, or /dev/null.
ho_project_config_file() {
  local pf
  pf=$(ho_sel_project_config "$1" 2>/dev/null) || pf=""
  printf '%s\n' "${pf:-/dev/null}"
}

# ho_cfg <jq-path> [default]: project value, else user value, else default. With a local
# selection, a declined OpenSpec setup comes first for .requirements.format, and the confirmed
# default and then the shipped default config come after the user value (D37-FLOW-7).
ho_cfg() {
  local path=${1:?jq path required} def=${2-} files f v proj
  files=$(ho_config_files) || exit $?
  v=$(ho_sel_local_value override "$path")
  [ -z "$v" ] || { printf '%s\n' "$v"; return 0; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    v=$(jq -r "$path" "$f" 2>/dev/null) || {
      printf 'harness: cannot read %s from config %s\n' "$path" "$f" >&2
      exit "$HO_EXIT_CONFIG"
    }
    [ "$v" = null ] && continue
    printf '%s\n' "$v"
    return 0
  done <<EOF_FILES
$files
EOF_FILES
  v=$(ho_sel_local_value default "$path")
  [ -z "$v" ] || { printf '%s\n' "$v"; return 0; }
  if proj=$(ho_project_root 2>/dev/null) && [ -f "$(ho_sel_file "$proj")" ]; then
    v=$(ho_sel_local_value shipped "$path")
    [ -z "$v" ] || { printf '%s\n' "$v"; return 0; }
  fi
  printf '%s\n' "$def"
}

# ho_cfg_int <jq-path> <default>: a plain non-negative integer, read base 10.
# Anything else is reported on stderr and the default is used.
ho_cfg_int() {
  local path=${1:?jq path required} def=${2:?integer default required} v
  v=$(ho_cfg "$path" "$def") || exit $?
  case $v in
    '' | *[!0-9]*)
      printf 'harness: config %s=%s is not a non-negative integer; using %s\n' "$path" "$v" "$def" >&2
      printf '%s\n' "$def"
      ;;
    *) printf '%s\n' "$((10#$v))" ;;
  esac
}

ho_config_usage() {
  cat >&2 <<'USAGE'
usage: harness config get <jq-path> [default] | config get --int <jq-path> <default> | config check
       harness config list                       the committed configs: <name> TAB <path>
       harness config select <name>              use a committed config on this machine (and record
                                                 the approved profile, D37-FLOW-8)
       harness config select --default [--flow F] [--format openspec|none]
       harness config save-default [--flow F] [--format openspec|none]   for projects with no config
       harness config format openspec|none       the requirements format on this machine
       harness config status                     the local selection, as JSON
       harness config gate [--unattended]        the start check: 0 may start, 73 stops and asks
       harness config language                   the agent language (English by default)
USAGE
}

# harness config get <jq-path> [default] | config get --int <jq-path> <default> | config check
ho_config_main() {
  case ${1-} in
    get)
      shift
      if [ "${1-}" = --int ]; then
        shift
        [ -n "${1-}" ] && [ -n "${2-}" ] || { ho_config_usage; exit 64; }
        ho_cfg_int "$@"
      else
        [ -n "${1-}" ] || { ho_config_usage; exit 64; }
        ho_cfg "$@"
      fi
      ;;
    check)
      ho_config_files >/dev/null
      echo "config OK"
      ;;
    list)
      local proj
      proj=$(ho_project_root 2>/dev/null) || exit 0
      ho_sel_list "$proj"
      ;;
    select) shift; ho_sel_select "$@" || exit $? ;;
    save-default) shift; ho_sel_save_default "$@" || exit $? ;;
    format) shift; [ $# -eq 1 ] || { ho_config_usage; exit 64; }; ho_sel_format "$1" || exit $? ;;
    status)
      local proj s
      proj=$(ho_project_root 2>/dev/null) || { echo '{"selected": false}'; exit 0; }
      s=$(ho_sel_read "$proj") || exit 78
      if [ -n "$s" ]; then printf '%s\n' "$s"; else echo '{"selected": false}'; fi
      ;;
    gate) shift; ho_sel_gate "$@" || exit $? ;;
    language) ho_sel_language || exit $? ;;
    *) ho_config_usage; exit 64 ;;
  esac
}
