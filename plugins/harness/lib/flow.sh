# shellcheck shell=bash
# Flow profiles (H-064; tasks 7.1, 7.2). A flow profile is data: a folder
# <flows>/<name>/ with flow.json and one prompt file per step. The engine holds no
# flow name and has no default flow (D37-FLOW-1). The role prompts in prompts/ are
# thin and shared by every flow.
#
#   flow.json  {"schemaVersion": 2, "name": "<folder name>", "description": "...",
#               "source": "own" | "system",
#               "steps": [{"id", "title", "when": "always" | "questions", "prompt"}]}
#
# "source" is declared here and checked later (H-066, H-067). Step order is file order.
#
# Placeholders are @NAME@ (upper-case letters, digits, underscores). Rendering is one jq
# pass over the tokens of the template: each value is inserted literally and never scanned
# again, so a value may hold any UTF-8 text, placeholders included (field note D3). A value
# that is not valid UTF-8 is refused (exit 65), never changed. A template token with no
# value fails the render and nothing is printed. Values reach jq through files, never as
# one big argument.
#
# Settings: HO_FLOWS_DIR (default <plugin>/flows). Requires lib/common.sh.

HO_EXIT_USAGE=64
HO_EXIT_DATA=65
HO_EXIT_FLOW=78
HO_FLOW_SCHEMA=2
HO_FLOW_ROLES="worker validator"
# Every placeholder a template may use. The engine fills the first five itself.
HO_FLOW_ENGINE_TOKENS="FLOW_NAME FLOW_STEP_LIST STEP_ID STEP_TITLE STEP_TEXT"
HO_FLOW_CALLER_TOKENS="RUN_ID TICKET_ID TICKET_TEXT BRANCH BASE WORKDIR STEP_RESULT_FILE VERDICT_FILE"

ho_flows_dir() { printf '%s\n' "${HO_FLOWS_DIR:-$HO_ROOT/flows}"; }

ho_flow_usage() {
  cat >&2 <<'USAGE'
usage: harness flow list
       harness flow check <flow>
       harness flow steps <flow>      one line per step: <n> TAB <id> TAB <when> TAB <title>
       harness flow render <flow> <role> [--step <id>] [--set NAME VALUE]... [--file NAME PATH]...
roles: worker (needs --step), validator
USAGE
}

ho_flow_fail() { printf 'harness: flow %s: %s\n' "$1" "$2" >&2; exit "$HO_EXIT_FLOW"; }

# ho_flow_name_ok <name>: lower-case letters, digits and dashes only.
ho_flow_name_ok() {
  case ${1-} in
    '' | -* | *[!a-z0-9-]*) printf 'harness: bad flow name [%s]: use a-z, 0-9 and -\n' "${1-}" >&2; exit "$HO_EXIT_USAGE" ;;
  esac
}

# jq: tokens of a template string, in order.
HO_JQ_TOKENS='[match("@[A-Z0-9_]+@"; "g") | .string[1:-1]]'

# ho_flow_load <name>: check the whole flow profile; set HO_FLOW_DIR and HO_FLOW_JSON.
# Any problem stops with exit 78 and names the flow. It never falls back to another flow.
ho_flow_load() {
  local name=$1 dir f why step_tokens allowed t tok real
  ho_flow_name_ok "$name"
  dir="$(ho_flows_dir)/$name"
  [ -f "$dir/flow.json" ] || ho_flow_fail "$name" "flow file not found: $dir/flow.json"
  # Work on the physical folder, so a linked folder or file cannot lead outside it.
  dir=$(cd -P "$dir" && pwd -P) || ho_flow_fail "$name" "cannot open the flow folder"
  f="$dir/flow.json"
  [ ! -L "$f" ] || ho_flow_fail "$name" "flow file is a link: $f"
  why=$(jq -r --arg name "$name" --argjson schema "$HO_FLOW_SCHEMA" '
    def bad($m): $m;
    if type != "object" then bad("not a JSON object")
    elif .schemaVersion != $schema then bad("schemaVersion must be \($schema)")
    elif .name != $name then bad("name must be the folder name \($name)")
    elif (.source | IN("own", "system") | not) then bad("source must be own or system")
    elif (.steps | type) != "array" or (.steps | length) == 0 then bad("steps must be a non-empty list")
    else
      [ .steps[] | select(type != "object"
          or ((.id | type) != "string") or (.id | test("\\A[a-z0-9][a-z0-9-]*\\z") | not)
          or ((.title | type) != "string") or .title == "" or (.title | test("[[:cntrl:]]"))
          or (.when | IN("always", "questions") | not)
          or ((.prompt | type) != "string")
          or (.prompt | test("\\A[A-Za-z0-9_-][A-Za-z0-9_./-]*\\z") | not)
          or (.prompt | split("/") | any(. == ".." or . == "."))) ] as $bad
      | if ($bad | length) > 0 then bad("bad step: \($bad[0] | tojson)")
        elif ([.steps[].id] | unique | length) != (.steps | length) then bad("step ids must be unique")
        else "" end
    end' "$f" 2>/dev/null) || ho_flow_fail "$name" "flow file is unreadable: $f"
  [ -z "$why" ] || ho_flow_fail "$name" "$why ($f)"
  allowed=" $HO_FLOW_ENGINE_TOKENS $HO_FLOW_CALLER_TOKENS "
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    [ -f "$dir/$t" ] && [ ! -L "$dir/$t" ] || ho_flow_fail "$name" "step prompt is not a plain file: $dir/$t"
    real=$(cd -P "$(dirname "$dir/$t")" && pwd -P) || ho_flow_fail "$name" "cannot open the folder of $dir/$t"
    case "$real/" in "$dir"/*) ;; *) ho_flow_fail "$name" "step prompt leads outside the flow folder: $dir/$t" ;; esac
    if grep -qE '\{\{|\}\}' "$dir/$t"; then ho_flow_fail "$name" "double-brace token in $dir/$t; use @NAME@"; fi
    step_tokens=$(jq -Rsr "$HO_JQ_TOKENS | .[]" "$dir/$t") || ho_flow_fail "$name" "cannot read $dir/$t"
    for tok in $step_tokens; do
      case $allowed in *" $tok "*) ;; *) ho_flow_fail "$name" "undeclared placeholder @$tok@ in $dir/$t" ;; esac
      [ "$tok" != STEP_TEXT ] || ho_flow_fail "$name" "a step prompt cannot use @STEP_TEXT@ ($dir/$t)"
    done
  done <<EOF_STEPS
$(jq -r '.steps[].prompt' "$f")
EOF_STEPS
  HO_FLOW_DIR=$dir
  HO_FLOW_JSON=$f
}

# ho_flow_role_file <role>: the role prompt, checked against the declared tokens.
ho_flow_role_file() {
  local role=$1 f tok allowed
  case " $HO_FLOW_ROLES " in *" $role "*) ;; *) printf 'harness: unknown role [%s]; roles: %s\n' "$role" "$HO_FLOW_ROLES" >&2; exit "$HO_EXIT_USAGE" ;; esac
  f="$HO_ROOT/prompts/$role.md"
  [ -f "$f" ] || ho_die "role prompt not found: $f"
  allowed=" $HO_FLOW_ENGINE_TOKENS $HO_FLOW_CALLER_TOKENS "
  for tok in $(jq -Rsr "$HO_JQ_TOKENS | .[]" "$f"); do
    case $allowed in *" $tok "*) ;; *) ho_die "undeclared placeholder @$tok@ in $f" ;; esac
  done
  printf '%s\n' "$f"
}

ho_flow_list() {
  local d
  for d in "$(ho_flows_dir)"/*/; do
    [ -f "$d/flow.json" ] && basename "$d"
  done
  return 0
}

ho_flow_steps() {
  ho_flow_load "$1"
  jq -r '.steps | to_entries[] | "\(.key + 1)\t\(.value.id)\t\(.value.when)\t\(.value.title)"' "$HO_FLOW_JSON"
}

# ho_flow_render <flow> <role> [--step <id>] [--set NAME VALUE]... [--file NAME PATH]...
ho_flow_render() {
  local flow=${1-} role=${2-} step="" name tmpd rc=0 step_prompt=/dev/null role_file
  local -a valargs=()
  [ -n "$flow" ] && [ -n "$role" ] || { ho_flow_usage; exit "$HO_EXIT_USAGE"; }
  shift 2
  ho_flow_load "$flow"
  role_file=$(ho_flow_role_file "$role")
  tmpd=$(mktemp -d "${TMPDIR:-/tmp}/ho-flow.XXXXXX") || ho_die "mktemp failed"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpd'" EXIT
  while [ $# -gt 0 ]; do
    case $1 in
      --step) [ $# -ge 2 ] || { ho_flow_usage; exit "$HO_EXIT_USAGE"; }; step=$2; shift 2 ;;
      --set | --file)
        [ $# -ge 3 ] || { ho_flow_usage; exit "$HO_EXIT_USAGE"; }
        name=$2
        case " $HO_FLOW_CALLER_TOKENS " in
          *" $name "*) ;;
          *) printf 'harness: cannot set %s; settable names: %s\n' "$name" "$HO_FLOW_CALLER_TOKENS" >&2; exit "$HO_EXIT_USAGE" ;;
        esac
        if [ "$1" = --set ]; then
          printf '%s' "$3" > "$tmpd/$name" || ho_die "cannot write a temp file"
        else
          [ -f "$3" ] && [ -r "$3" ] || { printf 'harness: cannot read value file for %s: %s\n' "$name" "$3" >&2; exit "$HO_EXIT_USAGE"; }
          cat -- "$3" > "$tmpd/$name" || ho_die "cannot write a temp file"
        fi
        if ! iconv -f UTF-8 -t UTF-8 < "$tmpd/$name" >/dev/null 2>&1; then
          printf 'harness: the value of %s is not valid UTF-8 text\n' "$name" >&2
          exit "$HO_EXIT_DATA"
        fi
        shift 3
        ;;
      *) ho_flow_usage; exit "$HO_EXIT_USAGE" ;;
    esac
  done
  if [ "$role" = worker ] && [ -z "$step" ]; then
    printf 'harness: the worker role needs --step <id>\n' >&2
    exit "$HO_EXIT_USAGE"
  fi
  if [ -n "$step" ]; then
    step_prompt=$(jq -r --arg s "$step" '.steps[] | select(.id == $s) | .prompt' "$HO_FLOW_JSON")
    [ -n "$step_prompt" ] || { printf 'harness: flow %s has no step %s\n' "$flow" "$step" >&2; exit "$HO_EXIT_USAGE"; }
    step_prompt="$HO_FLOW_DIR/$step_prompt"
  fi
  # Each value reaches jq as a file (--rawfile V_<NAME>), so a large value is no argument.
  for name in $HO_FLOW_CALLER_TOKENS; do
    [ -f "$tmpd/$name" ] && valargs+=(--rawfile "V_$name" "$tmpd/$name")
  done
  jq -nj --arg flow "$flow" --arg step "$step" ${valargs[@]+"${valargs[@]}"} \
    --slurpfile cfg "$HO_FLOW_JSON" --rawfile role "$role_file" --rawfile steptpl "$step_prompt" '
    def render($v):
      . as $t
      | reduce (match("@[A-Z0-9_]+@"; "g")) as $m ({out: "", pos: 0, missing: []};
          ($m.string[1:-1]) as $k
          | .out += $t[.pos:$m.offset]
          | (if $v | has($k) then .out += $v[$k] else .missing += [$k] end)
          | .pos = $m.offset + $m.length)
      | .out += $t[.pos:];
    $cfg[0] as $c
    | ($ARGS.named | with_entries(select(.key | startswith("V_")) | .key |= .[2:])) as $vals
    | ($vals + {
        FLOW_NAME: $flow,
        FLOW_STEP_LIST: ([$c.steps | to_entries[]
          | "\(.key + 1). \(.value.title) (\(.value.id))"
            + (if .value.when == "questions" then ", only when classification finds open questions" else "" end)]
          | join("\n"))
      }) as $base
    | (if $step == "" then $base
       else ($c.steps[] | select(.id == $step)) as $s
         | ($base + {STEP_ID: $s.id, STEP_TITLE: $s.title}) as $sb
         | ($steptpl | render($sb)) as $st
         | if ($st.missing | length) > 0 then error("missing values: \($st.missing | unique | join(" "))")
           else $sb + {STEP_TEXT: $st.out} end
       end) as $all
    | ($role | render($all)) as $r
    | if ($r.missing | length) > 0 then error("missing values: \($r.missing | unique | join(" "))")
      else $r.out end
  ' 2>"$tmpd/.err" || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'harness: flow %s, role %s: cannot render: %s\n' "$flow" "$role" \
      "$(sed -e 's/^jq: error (at <unknown>): //' "$tmpd/.err")" >&2
    exit "$HO_EXIT_DATA"
  fi
}

ho_flow_main() {
  local verb=${1-}
  [ $# -gt 0 ] && shift
  case $verb in
    list) ho_flow_list ;;
    check)
      [ $# -eq 1 ] || { ho_flow_usage; exit "$HO_EXIT_USAGE"; }
      ho_flow_load "$1"
      local r
      for r in $HO_FLOW_ROLES; do ho_flow_role_file "$r" >/dev/null; done
      printf 'flow %s OK\n' "$1"
      ;;
    steps) [ $# -eq 1 ] || { ho_flow_usage; exit "$HO_EXIT_USAGE"; }; ho_flow_steps "$1" ;;
    render) ho_flow_render "$@" ;;
    *) ho_flow_usage; exit "$HO_EXIT_USAGE" ;;
  esac
}
