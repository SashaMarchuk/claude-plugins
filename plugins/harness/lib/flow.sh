# shellcheck shell=bash
# Flow configs (H-064 to H-068; tasks 7.1, 7.2). A flow config is data: a folder <name>/
# with flow.json and one prompt file per step. It holds the steps, their order and their
# runners (S8-15, D37-FLOW-3); gates and permissions belong to the autonomy profile, so a
# flow.json that sets one is refused. Ready-made flow configs ("flow profiles") ship in
# <plugin>/flows; a project's own flows live in <project>/.harness/flows. The engine holds no
# flow name and has no default flow (D37-FLOW-1). The role prompts in prompts/ are thin and
# shared by every flow.
#
#   flow.json  {"schemaVersion": 2, "name": "<folder name>", "description": "...",
#               "source": "own" | "system",
#               "system": {"name", "link", "install", "skills": [...], "agents": [...], "steps": [ids]},
#               "install": {"<skill>": "<install step>"},
#               "steps": [{"id", "title", "when": "always" | "questions", "prompt",
#                          "enabled": false, "runtime": "<label>", "kind": "review",
#                          "skills": [...], "agents": [...]}]}
#
# Step order is file order (H-066). "enabled": false switches a step off: it leaves every
# step list, the numbering and the render. "runtime" names the step's runner, a runtime
# profile label (lib/runtime.sh); a step without one uses config runtime.main. "kind":
# "review" marks a review-type step (D37-RUNTIME-2).
# One source of steps per flow (D17, D37-FLOW-2): "source": "own" is an own step list and
# carries no "system"; "source": "system" names a chosen system, whose "system.steps" are
# the ids it owns. Those ids form one block, in that order; harness extra steps go only
# before or after it. A step inside the block, a system step out of order or switched off,
# and a flow with both a system and an own list are config errors (exit 78) that name the
# step and the route: `harness flow copy <flow> <new>` makes an own flow to edit freely.
#
# Placeholders are @NAME@ (upper-case letters, digits, underscores). Rendering is one jq
# pass over the tokens of the template: each value is inserted literally and never scanned
# again, so a value may quote placeholders (field note D3). A value that is not valid UTF-8
# is refused (exit 65), never changed. Only the names in HO_FLOW_MULTILINE_TOKENS may hold
# line breaks; any other value is one line and is refused (exit 65) when it holds a byte
# below 0x20 other than tab, DEL, a Unicode line or paragraph separator (U+0085, U+2028,
# U+2029) or a bidi control (U+202A-U+202E, U+2066-U+2069). TICKET_ID is a number.
# A template token with no value, or an empty one, fails the render and nothing is
# printed. Values reach jq through files, never as one big argument.
#
# Settings: HO_FLOWS_DIR (default <plugin>/flows). Requires lib/common.sh, lib/config.sh,
# lib/tickets.sh (the untrusted fence), jq and iconv.

HO_EXIT_USAGE=64
HO_EXIT_DATA=65
HO_EXIT_FLOW=78
HO_FLOW_SCHEMA=2
HO_FLOW_ROLES="worker validator"
# Every placeholder a template may use. The engine fills the first five itself.
HO_FLOW_ENGINE_TOKENS="FLOW_NAME FLOW_STEP_LIST STEP_ID STEP_TITLE STEP_TEXT"
HO_FLOW_CALLER_TOKENS="RUN_ID TICKET_ID TICKET_TEXT BRANCH BASE WORKDIR STEP_RESULT_FILE VERDICT_FILE"
# The caller values that may span lines. Every other caller value is one line of text.
HO_FLOW_MULTILINE_TOKENS="TICKET_TEXT"

ho_flows_dir() { printf '%s\n' "${HO_FLOWS_DIR:-$HO_ROOT/flows}"; }

ho_flow_usage() {
  cat >&2 <<'USAGE'
usage: harness flow list
       harness flow check <flow>
       harness flow steps <flow>      one line per step: <n> TAB <id> TAB <when> TAB <title>
       harness flow plan <flow>       steps plus TAB <runtime> TAB <mode> TAB <owner> TAB <note> TAB <launch>
       harness flow preflight <flow>  start check: runtimes logged in, skills installed; installs nothing
       harness flow copy <flow> <new> copy a flow into <project>/.harness/flows/<new> as an own flow
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

# ho_flow_project_dir: print <project>/.harness/flows when a project is found, else nothing.
ho_flow_project_dir() {
  local p
  p=$(ho_project_root 2>/dev/null) || return 0
  printf '%s/.harness/flows\n' "$p"
}

# ho_flow_inside_project <path>: 0 when the physical path lies inside the physical project folder.
ho_flow_inside_project() {
  local proj real
  proj=$(ho_project_root 2>/dev/null) && proj=$(cd -P "$proj" 2>/dev/null && pwd -P) || return 1
  real=$(cd -P "$1" 2>/dev/null && pwd -P) || return 1
  case "$real/" in "$proj"/*) return 0 ;; esac
  return 1
}

# ho_flow_locate <name>: print the flow folder, from the project or the shipped flows. A name in
# both places is refused: a project flow never hides a shipped one (exit 78).
ho_flow_locate() {
  local name=$1 shipped pdir proj real
  shipped="$(ho_flows_dir)/$name"
  pdir=$(ho_flow_project_dir)
  if [ -n "$pdir" ] && { [ -e "$pdir/$name" ] || [ -L "$pdir/$name" ]; }; then
    [ ! -e "$shipped/flow.json" ] ||
      ho_flow_fail "$name" "a project flow has the name of a shipped flow ($pdir/$name and $shipped); rename the project flow"
    # A project flow folder must stay inside the project, also through links (of the flow
    # folder, of .harness/flows or of .harness).
    ho_flow_inside_project "$pdir/$name" || ho_flow_fail "$name" "the project flow folder $pdir/$name leads outside the project"
    printf '%s\n' "$pdir/$name"
    return 0
  fi
  printf '%s\n' "$shipped"
}

# Top-level keys of the autonomy profile (D12, D37-FLOW-8 (b)). A flow config never holds them.
HO_FLOW_AUTONOMY_KEYS='["gates","push","pr","pr_open","merge","post_merge","deploy_production","remarks","allow_zero_tests","permissions","autonomy"]'

# The keys a step may hold. Any other key is refused by name, so a typo such as "enable" never
# passes as a step that stays on.
HO_FLOW_STEP_KEYS='["id","title","when","prompt","enabled","runtime","kind","skills","agents"]'
# The keys of the flow file and of its system object; any other key is refused by name too.
# copied_from is written by flow copy.
HO_FLOW_TOP_KEYS='["schemaVersion","name","description","source","system","install","steps","copied_from"]'
HO_FLOW_SYSTEM_KEYS='["name","link","install","skills","agents","steps"]'

# ho_flow_load <name>: check the whole flow; set HO_FLOW_DIR, HO_FLOW_JSON and HO_FLOW_ORIGIN
# (project or shipped). Any problem stops with exit 78 and names the flow. It never falls back
# to another flow.
ho_flow_load() {
  local name=$1 dir f why step_tokens allowed t tok real origin=shipped
  ho_flow_name_ok "$name"
  dir=$(ho_flow_locate "$name") || exit $?
  case $dir in "$(ho_flows_dir)"/*) ;; *) origin=project ;; esac
  [ -f "$dir/flow.json" ] || ho_flow_fail "$name" "flow file not found: $dir/flow.json"
  # Work on the physical folder, so a linked folder or file cannot lead outside it.
  dir=$(cd -P "$dir" && pwd -P) || ho_flow_fail "$name" "cannot open the flow folder"
  f="$dir/flow.json"
  [ ! -L "$f" ] || ho_flow_fail "$name" "flow file is a link: $f"
  # Slurped, so an empty file or two JSON values cannot pass as "nothing wrong" (field note I3).
  why=$(jq -rs --arg name "$name" --argjson schema "$HO_FLOW_SCHEMA" --argjson akeys "$HO_FLOW_AUTONOMY_KEYS" --argjson skeys "$HO_FLOW_STEP_KEYS" --argjson tkeys "$HO_FLOW_TOP_KEYS" --argjson sykeys "$HO_FLOW_SYSTEM_KEYS" '
    def bad($m): $m;
    if length != 1 then "the file must hold exactly one JSON object" else .[0] |
    # Text a terminal shows: no control, line separator or bidi character (as for render values).
    def line: type == "string" and (test("[[:cntrl:]\u0085\u2028\u2029\u202a-\u202e\u2066-\u2069]") | not);
    def rtname: type == "string" and test("\\A[a-z0-9][a-z0-9-]*\\z");
    def skill: type == "string" and test("\\A[a-z0-9][a-z0-9-]*(:[a-z0-9][a-z0-9-]*)?\\z");
    def agent: type == "string" and test("\\A[a-z0-9][a-z0-9-]*\\z");
    def route: "the chosen system owns its steps. To change them, copy its step list into an own flow: harness flow copy \($name) <new-name>";
    if type != "object" then bad("not a JSON object")
    elif .schemaVersion != $schema then bad("schemaVersion must be \($schema)")
    elif .name != $name then bad("name must be the folder name \($name)")
    elif ([keys[] | select(IN($akeys[]))] | length) > 0 then
      bad("\([keys[] | select(IN($akeys[]))] | join(", ")): gates and permissions belong in the autonomy profile, not the flow config")
    elif (keys - $tkeys | length) > 0 then
      bad("unknown key \((keys - $tkeys)[0]) (a flow file may hold only \($tkeys | join(", ")))")
    elif (.system | type) == "object" and ((.system | keys) - $sykeys | length) > 0 then
      bad("unknown key \(((.system | keys) - $sykeys)[0]) in system (system may hold only \($sykeys | join(", ")))")
    elif (.source | IN("own", "system") | not) then bad("source must be own or system")
    elif .source == "own" and has("system") then
      bad("the flow names both a chosen system and an own step list; the harness never merges two lists. Use source system with system.steps, or remove system")
    elif (.steps | type) != "array" or (.steps | length) == 0 then bad("steps must be a non-empty list")
    elif has("install") and ((.install | type) != "object" or (.install | to_entries | any((.key | skill | not) or (.value | line | not)))) then
      bad("install must map skill names to one-line install steps")
    elif ([.steps[] | select(type == "object" and (keys - $skeys | length) > 0)] | length) > 0 then
      ([.steps[] | select(type == "object" and (keys - $skeys | length) > 0)] | first) as $u
      | bad("step \($u.id // "?"): unknown key \(($u | keys) - $skeys | first) (a step may hold only \($skeys | join(", ")))")
    else
      [ .steps[] | select(type != "object"
          or ((.id | type) != "string") or (.id | test("\\A[a-z0-9][a-z0-9-]*\\z") | not)
          or (.title | line | not) or .title == ""
          or (.when | IN("always", "questions") | not)
          or ((.prompt | type) != "string")
          or (.prompt | test("\\A[A-Za-z0-9_-][A-Za-z0-9_./-]*\\z") | not)
          or (.prompt | split("/") | any(. == ".." or . == "."))
          or (has("enabled") and ((.enabled | type) != "boolean"))
          or (has("runtime") and (.runtime | rtname | not))
          or (has("kind") and .kind != "review")
          or (has("skills") and ((.skills | type) != "array" or (.skills | any(skill | not))))
          or (has("agents") and ((.agents | type) != "array" or (.agents | any(agent | not))))) ] as $bad
      | if ($bad | length) > 0 then bad("bad step: \($bad[0] | tojson)")
        elif ([.steps[].id] | unique | length) != (.steps | length) then bad("step ids must be unique")
        elif ([.steps[] | select(.enabled != false)] | length) == 0 then bad("every step is switched off")
        elif .source == "own" then ""
        elif (.system | type) != "object" then bad("source system needs a system object")
        elif (.system.name | line | not) or .system.name == "" then bad("system.name must be one line of text")
        elif (.system | has("link")) and (.system.link | line | not) then bad("system.link must be one line of text")
        elif (.system | has("install")) and (.system.install | line | not) then bad("system.install must be one line of text")
        elif (.system | has("skills")) and ((.system.skills | type) != "array" or (.system.skills | any(skill | not))) then
          bad("system.skills must be a list of skill names (a-z, 0-9, -, one optional plugin: prefix)")
        elif (.system | has("agents")) and ((.system.agents | type) != "array" or (.system.agents | any(agent | not))) then
          bad("system.agents must be a list of agent names (a-z, 0-9, -)")
        elif (.system.steps | type) != "array" or (.system.steps | length) == 0 or (.system.steps | any(type != "string")) then
          bad("system.steps must list the ids of the steps the chosen system owns")
        elif (.system.steps | unique | length) != (.system.steps | length) then
          bad("system.steps names step \(.system.steps | group_by(.) | map(select(length > 1))[0][0]) twice")
        else
          [.steps[].id] as $ids | .system.steps as $own
          | ([$own[] | select(IN($ids[]) | not)] | first) as $missing
          | if $missing != null then bad("system.steps names step \($missing), which is not in steps")
            else
              ([$ids | to_entries[] | select(.value | IN($own[])) | .key]) as $pos
              | ([$ids[($pos | min):($pos | max) + 1][] | select(IN($own[]) | not)] | first) as $inside
              | ([range(0; $own | length) | select($ids[$pos[.]] != $own[.]) | $ids[$pos[.]]] | first) as $moved
              | ([.steps[] | select(.enabled == false and (.id | IN($own[]))) | .id] | first) as $off
              | if $inside != null then bad("step \($inside) is placed inside the chosen system'"'"'s steps; harness steps go only before or after them; \(route)")
                elif $moved != null then bad("step \($moved) is out of the chosen system'"'"'s order (\($own | join(", "))); \(route)")
                elif $off != null then bad("step \($off) belongs to the chosen system and cannot be switched off here; \(route)")
                else "" end
            end
        end
    end end' "$f" 2>/dev/null) || ho_flow_fail "$name" "flow file is unreadable: $f"
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
  HO_FLOW_ORIGIN=$origin
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
  local d root pdir
  root=$(ho_flows_dir)
  [ -d "$root" ] || { printf 'harness: flows folder not found: %s\n' "$root" >&2; exit "$HO_EXIT_FLOW"; }
  pdir=$(ho_flow_project_dir)
  for d in "$root"/*/ ${pdir:+"$pdir"/*/}; do
    if [ -f "$d/flow.json" ]; then basename "$d"; fi
  done | LC_ALL=C sort -u
  return 0
}

# jq: the steps that are on, in order (a switched-off step leaves every list).
HO_JQ_ON='[.steps[] | select(.enabled != false)]'

ho_flow_steps() {
  ho_flow_load "$1"
  jq -r "$HO_JQ_ON"' | to_entries[] | "\(.key + 1)\t\(.value.id)\t\(.value.when)\t\(.value.title)"' "$HO_FLOW_JSON"
}

# ho_flow_copy <flow> <new>: write <project>/.harness/flows/<new> as an own flow (the route of
# D37-FLOW-2). The system's skills stay on the steps it owned, with its install step, so the
# start check still checks them. Writes nothing outside the new folder.
ho_flow_copy() {
  local src=${1-} new=${2-} proj pdir tmp t
  [ -n "$src" ] && [ -n "$new" ] || { ho_flow_usage; exit "$HO_EXIT_USAGE"; }
  ho_flow_name_ok "$new"
  proj=$(ho_project_root 2>/dev/null) || {
    echo "harness: flow copy needs a project (a folder with .harness/config.json)" >&2; exit "$HO_EXIT_FLOW"; }
  pdir="$proj/.harness/flows"
  if [ -e "$(ho_flows_dir)/$new" ]; then
    printf 'harness: %s is the name of a shipped flow; pick another name\n' "$new" >&2; exit "$HO_EXIT_DATA"
  fi
  if [ -e "$pdir/$new" ] || [ -L "$pdir/$new" ]; then
    printf 'harness: the project flow %s exists; it is never overwritten\n' "$pdir/$new" >&2; exit "$HO_EXIT_DATA"
  fi
  ho_flow_load "$src"
  mkdir -p "$pdir" || ho_die "cannot create $pdir"
  ho_flow_inside_project "$pdir" || {
    printf 'harness: %s leads outside the project; nothing is written there\n' "$pdir" >&2; exit "$HO_EXIT_FLOW"; }
  tmp=$(mktemp -d "$pdir/.copy-$new.XXXXXX") || ho_die "mktemp failed in $pdir"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    mkdir -p "$tmp/$(dirname "$t")" && cp -- "$HO_FLOW_DIR/$t" "$tmp/$t" || { rm -rf "$tmp"; ho_die "cannot copy $t"; }
  done <<EOF_PROMPTS
$(jq -r '.steps[].prompt' "$HO_FLOW_JSON")
EOF_PROMPTS
  jq --arg new "$new" --arg src "$src" '
    (.system // null) as $s
    | .name = $new | .source = "own" | .copied_from = $src
    | if $s == null then . else
        ($s.skills // []) as $sk | ($s.agents // []) as $ag
        | .steps |= map(if (.id | IN($s.steps[])) then
            .skills = ((.skills // []) + [$sk[] as $k | select(((.skills // []) | index($k)) == null) | $k])
            | if ($ag | length) > 0 then .agents = ((.agents // []) + [$ag[] as $k | select(((.agents // []) | index($k)) == null) | $k]) else . end
          else . end)
        | if ($s.install // "") != "" and (($sk + $ag) | length) > 0
          then .install = ((.install // {}) + ([($sk + $ag)[] | {key: ., value: $s.install}] | from_entries)) else . end
        | .description = ((.description // "") + " Copied from the flow \($src) as an own flow; \($s.name) no longer owns these steps.")
        | del(.system)
      end' "$HO_FLOW_JSON" > "$tmp/flow.json" || { rm -rf "$tmp"; ho_die "cannot write the copied flow file"; }
  mv "$tmp" "$pdir/$new" || { rm -rf "$tmp"; ho_die "cannot move the copy into place"; }
  printf 'flow %s copied to %s as an own flow\n' "$src" "$pdir/$new"
}

# ho_flow_render <flow> <role> [--step <id>] [--set NAME VALUE]... [--file NAME PATH]...
ho_flow_render() {
  local flow=${1-} role=${2-} step="" name tmpd rc=0 step_prompt=/dev/null role_file
  local -a valargs=()
  [ -n "$flow" ] && [ -n "$role" ] || { ho_flow_usage; exit "$HO_EXIT_USAGE"; }
  shift 2
  ho_flow_load "$flow"
  role_file=$(ho_flow_role_file "$role")
  command -v iconv >/dev/null 2>&1 || ho_die "flow render needs iconv (to check that values are UTF-8); install it"
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
        case " $HO_FLOW_MULTILINE_TOKENS " in
          *" $name "*) ;;
          *) # One line: no line break, CR, other byte below 0x20 or DEL; tab is allowed. No
            # character that some readers take as a line break, and no bidi control.
            if [ "$(LC_ALL=C tr -d '\011\040-\176\200-\377' < "$tmpd/$name" | wc -c)" -ne 0 ] ||
              jq -Rse 'test("[\u0085\u2028\u2029\u202a-\u202e\u2066-\u2069]")' "$tmpd/$name" >/dev/null 2>&1; then
              printf 'harness: the value of %s must be one line, with no control, line separator or bidi characters\n' "$name" >&2
              exit "$HO_EXIT_DATA"
            fi ;;
        esac
        if [ "$name" = TICKET_ID ] && [ -s "$tmpd/$name" ]; then
          case $(cat "$tmpd/$name") in
            *[!0-9]* | ??????????*) printf 'harness: TICKET_ID must be a ticket number (digits only, at most 9)\n' >&2; exit "$HO_EXIT_DATA" ;;
          esac
        fi
        shift 3
        ;;
      *) ho_flow_usage; exit "$HO_EXIT_USAGE" ;;
    esac
  done
  # H-018: ticket text reaches a session only inside the untrusted fence of this ticket.
  # The value must be byte for byte what `harness tickets fence <TICKET_ID>` prints. To
  # check this, take the inner lines, undo the prefix the fence puts on marker lines, fence
  # them again and compare. Any other marker line, a CR or a missing last newline differs.
  if [ -f "$tmpd/TICKET_TEXT" ]; then
    local tid=""
    [ -f "$tmpd/TICKET_ID" ] && tid=$(cat "$tmpd/TICKET_ID")
    if [ -z "$tid" ] ||
      ! LC_ALL=C sed -e '1d' -e '$d' "$tmpd/TICKET_TEXT" |
        LC_ALL=C awk -v mark="$HO_TK_FENCE_MARK" '
          tolower($0) ~ mark && substr($0, 1, 14) == "[ticket-text] " { print substr($0, 15); next }
          { print }' | ho_tk_fence "$tid" > "$tmpd/.fenced" ||
      ! cmp -s "$tmpd/TICKET_TEXT" "$tmpd/.fenced"; then
      printf 'harness: TICKET_TEXT must be exactly the output of harness tickets fence TICKET_ID\n' >&2
      exit "$HO_EXIT_DATA"
    fi
  fi
  if [ "$role" = worker ] && [ -z "$step" ]; then
    printf 'harness: the worker role needs --step <id>\n' >&2
    exit "$HO_EXIT_USAGE"
  fi
  if [ -n "$step" ]; then
    step_prompt=$(jq -r --arg s "$step" '.steps[] | select(.id == $s) | .prompt' "$HO_FLOW_JSON")
    [ -n "$step_prompt" ] || { printf 'harness: flow %s has no step %s\n' "$flow" "$step" >&2; exit "$HO_EXIT_USAGE"; }
    if [ "$(jq -r --arg s "$step" '.steps[] | select(.id == $s) | .enabled != false' "$HO_FLOW_JSON")" != true ]; then
      printf 'harness: step %s is switched off in flow %s\n' "$step" "$flow" >&2
      exit "$HO_EXIT_USAGE"
    fi
    step_prompt="$HO_FLOW_DIR/$step_prompt"
  fi
  # Each value reaches jq as a file (--rawfile V_<NAME>), so a large value is no argument.
  # An empty value counts as no value, so a template that uses it fails the render.
  for name in $HO_FLOW_CALLER_TOKENS; do
    [ -s "$tmpd/$name" ] && valargs+=(--rawfile "V_$name" "$tmpd/$name")
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
        FLOW_STEP_LIST: ([[$c.steps[] | select(.enabled != false)] | to_entries[]
          | "\(.key + 1). \(.value.title) (\(.value.id))"
            + (if .value.when == "questions" then ", only when classification finds open questions" else "" end)]
          | join("\n"))
      }) as $base
    | (if $step == "" then $base
       else ($c.steps[] | select(.id == $step)) as $s
         | ($base + {STEP_ID: $s.id, STEP_TITLE: $s.title}) as $sb
         | ($steptpl | render($sb)) as $st
         | if ($st.missing | length) > 0 then error("missing or empty values: \($st.missing | unique | join(" "))")
           else $sb + {STEP_TEXT: $st.out} end
       end) as $all
    | ($role | render($all)) as $r
    | if ($r.missing | length) > 0 then error("missing or empty values: \($r.missing | unique | join(" "))")
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
    plan) [ $# -eq 1 ] || { ho_flow_usage; exit "$HO_EXIT_USAGE"; }; ho_flow_plan "$1" ;;
    preflight) [ $# -eq 1 ] || { ho_flow_usage; exit "$HO_EXIT_USAGE"; }; ho_flow_preflight "$1" ;;
    copy) [ $# -eq 2 ] || { ho_flow_usage; exit "$HO_EXIT_USAGE"; }; ho_flow_copy "$1" "$2" ;;
    render) ho_flow_render "$@" ;;
    *) ho_flow_usage; exit "$HO_EXIT_USAGE" ;;
  esac
}
