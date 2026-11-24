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

# ho_project_root: print the project folder (the one holding .harness/config.json).
# Order: $HO_PROJECT_DIR, then walk up from $PWD to .harness/config.json or to a
# .harness-project pointer file (a worktree outside the project carries one).
ho_project_root() {
  local d p
  if [ -n "${HO_PROJECT_DIR:-}" ]; then
    [ -f "$HO_PROJECT_DIR/.harness/config.json" ] && { printf '%s\n' "$HO_PROJECT_DIR"; return 0; }
    printf 'harness: HO_PROJECT_DIR=%s has no .harness/config.json\n' "$HO_PROJECT_DIR" >&2
    return 1
  fi
  d=$PWD
  while :; do
    [ -f "$d/.harness/config.json" ] && { printf '%s\n' "$d"; return 0; }
    if [ -f "$d/.harness-project" ]; then
      p=$(head -n 1 "$d/.harness-project")
      [ -n "$p" ] && [ -f "$p/.harness/config.json" ] && { printf '%s\n' "$p"; return 0; }
    fi
    [ "$d" = / ] && break
    d=$(dirname "$d")
  done
  return 1
}

ho_user_config() { printf '%s/config.json\n' "${HO_USER_DIR:-$HOME/.claude/harness}"; }

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
ho_config_files() {
  local proj user
  user=$(ho_user_config)
  if proj=$(ho_project_root 2>/dev/null); then
    ho_config_file_check "$proj/.harness/config.json"
    printf '%s\n' "$proj/.harness/config.json"
  elif [ -n "${HO_PROJECT_DIR:-}" ]; then
    ho_project_root >/dev/null || true
    exit "$HO_EXIT_CONFIG"
  fi
  ho_config_file_check "$user"
  [ -f "$user" ] && printf '%s\n' "$user"
  return 0
}

# ho_cfg <jq-path> [default]: project value, else user value, else default.
ho_cfg() {
  local path=${1:?jq path required} def=${2-} files f v
  files=$(ho_config_files) || exit $?
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

# harness config get [--int] <jq-path> [default] | harness config check
ho_config_main() {
  case ${1-} in
    get)
      shift
      if [ "${1-}" = --int ]; then shift; ho_cfg_int "$@"; else ho_cfg "$@"; fi
      ;;
    check)
      ho_config_files >/dev/null
      echo "config OK"
      ;;
    *)
      printf 'usage: harness config get [--int] <jq-path> [default] | harness config check\n' >&2
      exit 64
      ;;
  esac
}
