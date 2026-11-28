# shellcheck shell=bash
# Committed configs and the local selection (H-070, H-071, H-072; design D37-FLOW-4,
# D37-FLOW-5, D37-FLOW-8 (b), S8-16b).
#
#   committed configs  <project>/.harness/config.json        (name "config")
#                      <project>/.harness/config.<name>.json (named for its owner; a-z 0-9 -)
#   local selector     <project>/.harness/local.json, never committed: git ignores this one file
#                      through the clone's local exclude file; the shared .gitignore is unchanged.
#                      {schemaVersion: 2, config: <name> | null,
#                       default: {source: "confirmed" | "user", flow, requirements_format} (config null),
#                       requirements_format: "none" (a declined OpenSpec setup; wins on this machine),
#                       approved: {profile, fields: {<field>: <value>}, digest} (config set),
#                       notified: [<config names already announced>]}
#
# Lookup with a selector: the selected committed config, then the user config, then the shipped
# default (templates/default-config.json). With the default selected, committed configs are not
# read. A selector that names a missing config is a config error; there is no fallback.
# Without a selector the lookup still reads .harness/config.json, so status and config get work,
# but no run starts: `harness config gate` (run new calls it) stops with exit 73 and asks once.
#
# The record (D37-FLOW-8 (b)): the values the selected committed config gives for each field of
# autonomy/ranking/raises.json, with a sha256 digest. The gate compares the committed config with
# it at every run start: a raise, or a change the ranking cannot place, stops the run (73); a
# lowering is accepted and the record updated.
# Requires lib/common.sh and lib/config.sh.

HO_EXIT_CONFIRM=73
HO_SEL_NAME_RE='^[a-z0-9][a-z0-9-]{0,39}$'

ho_sel_err() { printf 'harness: %s\n' "$*" >&2; }

ho_sel_file() { printf '%s/.harness/local.json\n' "$1"; }

ho_sel_ranking() { printf '%s/autonomy/ranking/raises.json\n' "$HO_ROOT"; }

ho_sel_shipped() { printf '%s/templates/default-config.json\n' "$HO_ROOT"; }

ho_sel_name_ok() { printf '%s' "${1-}" | grep -Eq "$HO_SEL_NAME_RE"; }

# ho_sel_config_path <project> <name>: the committed config file for a name.
ho_sel_config_path() {
  if [ "$2" = config ]; then printf '%s/.harness/config.json\n' "$1"; else printf '%s/.harness/config.%s.json\n' "$1" "$2"; fi
}

# ho_sel_list <project>: one line per committed config: <name> TAB <path relative to the project>.
ho_sel_list() {
  local d=$1 f n
  [ -f "$d/.harness/config.json" ] && printf 'config\t.harness/config.json\n'
  for f in "$d"/.harness/config.*.json; do
    [ -f "$f" ] || continue
    n=${f##*/config.}
    n=${n%.json}
    ho_sel_name_ok "$n" || continue
    [ "$n" = config ] && continue
    printf '%s\t.harness/config.%s.json\n' "$n" "$n"
  done
}

# ho_is_project <dir>: 0 when the folder holds a committed config or a selector.
ho_is_project() {
  [ -f "$1/.harness/config.json" ] || [ -f "$1/.harness/local.json" ] || [ -n "$(ho_sel_list "$1")" ]
}

# ho_sel_read <project>: print the selector as compact JSON, nothing when absent; 78 when unreadable.
ho_sel_read() {
  local f
  f=$(ho_sel_file "$1")
  [ -e "$f" ] || return 0
  [ -f "$f" ] && [ ! -L "$f" ] && jq -ce 'select(type == "object" and .schemaVersion == 2
      and ((.config == null) or (.config | type == "string")))' "$f" 2>/dev/null || {
    ho_sel_err "the local selection $f is unreadable; select again with /harness:config"
    return 78
  }
}

# ho_sel_project_config <project>: print the project config file the lookup reads, or nothing.
ho_sel_project_config() {
  local proj=$1 s name f
  s=$(ho_sel_read "$proj") || return 78
  if [ -z "$s" ]; then
    [ -f "$proj/.harness/config.json" ] && printf '%s\n' "$proj/.harness/config.json"
    return 0
  fi
  name=$(printf '%s' "$s" | jq -r '.config // empty')
  [ -n "$name" ] || return 0
  ho_sel_name_ok "$name" || { ho_sel_err "the local selection names an invalid config: $name"; return 78; }
  f=$(ho_sel_config_path "$proj" "$name")
  [ -f "$f" ] || { ho_sel_err "the selected config $name (${f#"$proj"/}) is missing; it is never replaced by another config. Select again with /harness:config"; return 78; }
  printf '%s\n' "$f"
}

# ho_sel_local_value <jq-path>: a value the selector holds for this machine, or nothing.
# .requirements.format: a recorded "none" wins; .flow.use and .requirements.format: the confirmed
# default's values come after the project and user configs (ho_cfg asks for those with "default").
ho_sel_local_value() {
  local which=$1 path=$2 proj s
  proj=$(ho_project_root 2>/dev/null) || return 0
  s=$(ho_sel_read "$proj" 2>/dev/null) || return 0
  [ -n "$s" ] || return 0
  case $which:$path in
    override:.requirements.format) printf '%s' "$s" | jq -r '.requirements_format // empty' ;;
    default:.requirements.format) printf '%s' "$s" | jq -r '.default.requirements_format // empty' ;;
    default:.flow.use) printf '%s' "$s" | jq -r '.default.flow // empty' ;;
    shipped:*) jq -r "$path // empty" "$(ho_sel_shipped)" 2>/dev/null || true ;;
  esac
}

ho_sel_digest() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else sha256sum | cut -d' ' -f1; fi
}

# ho_sel_record <config-file>: the record of the approved profile, {profile, fields, digest}.
ho_sel_record() {
  local f=$1 prof pj body
  prof=$(jq -r '.autonomy.profile // (.guardrails.never_push | if . == true then "safe" elif . == false then "draft-pr" else empty end) // empty' "$f" 2>/dev/null) || return 78
  pj=null
  case " $HO_AU_READY " in
    *" $prof "*) [ -n "$prof" ] && pj=$(jq -c . "$(ho_au_dir)/$prof.json" 2>/dev/null) || pj=null ;;
  esac
  [ "$prof" != custom ] || pj=$(jq -c '.autonomy.custom // null' "$f")
  body=$(jq -cS --slurpfile r "$(ho_sel_ranking)" --argjson p "$pj" --arg name "$prof" '
    . as $c
    | {profile: (if $name == "" then null else $name end),
       fields: (reduce ($r[0].fields | keys[]) as $k ({};
         . + {($k): (if ($k | startswith("autonomy.")) and $k != "autonomy.always_human_paths"
                     then (($p // {})[$k | ltrimstr("autonomy.")])
                     else ($c | try getpath($k | split(".")) catch null) end)}))}' "$f" 2>/dev/null) || return 78
  printf '%s' "$body" | jq -c --arg d "$(printf '%s' "$body" | ho_sel_digest)" '. + {digest: $d}'
}

# ho_sel_raises <old-record> <new-record>: print each raised field, one per line.
ho_sel_raises() {
  jq -rn --argjson o "$1" --argjson n "$2" --slurpfile r "$(ho_sel_ranking)" '
    def idx($l; $v): first(range(0; $l | length) as $i | select($l[$i] == $v) | $i) // null;
    def raised($rule; $old; $new):
      if $old == $new then false
      elif $new == null then false
      elif $old == null then true
      elif $rule.kind == "order" then
        (idx($rule.order; $old)) as $a | (idx($rule.order; $new)) as $b
        | if $a == null or $b == null then true else $b > $a end
      elif $rule.kind == "gates" then
        if ($old | type) != "object" or ($new | type) != "object" then true
        else any($old | to_entries[]; .value == "human" and ($new[.key] // "auto") != "human") end
      elif $rule.kind == "add" then
        if ($old | type) != "array" or ($new | type) != "array" then true else (($new - $old) | length) > 0 end
      elif $rule.kind == "remove" then
        if ($old | type) != "array" or ($new | type) != "array" then true else (($old - $new) | length) > 0 end
      elif $rule.kind == "lower" then
        if ($old | type) != "number" or ($new | type) != "number" then true else $new < $old end
      elif $rule.kind == "from" then $new != $rule.safe
      else true end;
    $r[0].fields | to_entries[] | select(raised(.value; $o.fields[.key]; $n.fields[.key])) | .key'
}

# ho_sel_write <project> <json>: write the selector and make sure git ignores it (only it).
ho_sel_write() {
  local proj=$1 json=$2 f prefix common
  f=$(ho_sel_file "$proj")
  [ ! -L "$proj/.harness" ] && [ ! -L "$f" ] || { ho_sel_err "$f or its folder is a link; nothing is written through it"; return 77; }
  mkdir -p "$proj/.harness" || return 1
  printf '%s\n' "$json" | jq . | ho_atomic_write "$f" || return 1
  git -C "$proj" rev-parse --git-dir >/dev/null 2>&1 || return 0
  git -C "$proj" check-ignore -q .harness/local.json 2>/dev/null && return 0
  prefix=$(git -C "$proj" rev-parse --show-prefix 2>/dev/null) || prefix=""
  common=$(git -C "$proj" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  [ -d "$common" ] || return 0
  mkdir -p "$common/info" && printf '/%s.harness/local.json\n' "$prefix" >> "$common/info/exclude"
}

# ho_sel_main_checkout: the folder a selector goes in when no project is found yet: the main
# checkout of the git repository here, else the current folder.
ho_sel_main_checkout() {
  local common top
  if [ -n "${HO_PROJECT_DIR:-}" ]; then printf '%s\n' "$HO_PROJECT_DIR"; return 0; fi
  if top=$(git rev-parse --show-toplevel 2>/dev/null); then
    common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=""
    case $common in */.git) printf '%s\n' "${common%/.git}"; return 0 ;; esac
    printf '%s\n' "$top"; return 0
  fi
  printf '%s\n' "$PWD"
}

ho_sel_human_only() {
  if [ -n "${HO_SESSION_ID-}" ] || [ -n "${HO_SESSION_NAME-}" ]; then
    ho_sel_err "a config is selected by a person, never from inside a harness session"
    return 77
  fi
}

# ---- select <name> | select --default [--flow F] [--format openspec|none] -----------------------
ho_sel_select() {
  local proj f rec flow="" format="" shipped
  ho_sel_human_only || return
  if [ "${1-}" = --default ]; then
    shift
    while [ $# -gt 0 ]; do
      case $1 in
        --flow) [ $# -ge 2 ] && ho_sel_name_ok "$2" || { ho_sel_err "--flow needs a flow name of a-z 0-9 -"; return 64; }; flow=$2; shift 2 ;;
        --format) case ${2-} in openspec | none) format=$2 ;; *) ho_sel_err "--format must be openspec or none"; return 64 ;; esac; shift 2 ;;
        *) ho_config_usage; return 64 ;;
      esac
    done
    shipped=$(ho_sel_shipped)
    [ -n "$flow" ] || flow=$(jq -r '.flow.use' "$shipped")
    [ -n "$format" ] || format=$(jq -r '.requirements.format' "$shipped")
    proj=$(ho_project_root 2>/dev/null) || proj=$(ho_sel_main_checkout)
    ho_sel_write "$proj" "$(jq -nc --arg f "$flow" --arg r "$format" --arg ts "$(ho_now)" \
      '{schemaVersion: 2, config: null, default: {source: "confirmed", flow: $f, requirements_format: $r}, selected: $ts}')" || return
    printf 'selected the confirmed default: flow %s, requirements %s\n' "$flow" "$format"
    return 0
  fi
  [ $# -eq 1 ] && ho_sel_name_ok "$1" || { ho_config_usage; return 64; }
  proj=$(ho_project_root 2>/dev/null) || { ho_sel_err "no project here (no .harness folder with a config)"; return 78; }
  f=$(ho_sel_config_path "$proj" "$1")
  [ -f "$f" ] || { ho_sel_err "no committed config named $1 (${f#"$proj"/})"; return 78; }
  ho_config_file_check "$f"
  rec=$(ho_sel_record "$f") || { ho_sel_err "cannot read the recorded fields of $f"; return 78; }
  ho_sel_write "$proj" "$(jq -nc --arg n "$1" --argjson a "$rec" --arg ts "$(ho_now)" \
    '{schemaVersion: 2, config: $n, approved: $a, selected: $ts}')" || return
  printf 'selected %s; approved profile: %s\n' "$1" "$(printf '%s' "$rec" | jq -r '.profile // "none (the user config or the safe default)"')"
}

# ---- save-default [--flow F] [--format openspec|none]: the confirmation for other projects -------
ho_sel_save_default() {
  local u flow="" format="" shipped
  ho_sel_human_only || return
  while [ $# -gt 0 ]; do
    case $1 in
      --flow) [ $# -ge 2 ] && ho_sel_name_ok "$2" || { ho_sel_err "--flow needs a flow name of a-z 0-9 -"; return 64; }; flow=$2; shift 2 ;;
      --format) case ${2-} in openspec | none) format=$2 ;; *) ho_sel_err "--format must be openspec or none"; return 64 ;; esac; shift 2 ;;
      *) ho_config_usage; return 64 ;;
    esac
  done
  shipped=$(ho_sel_shipped)
  [ -n "$flow" ] || flow=$(jq -r '.flow.use' "$shipped")
  [ -n "$format" ] || format=$(jq -r '.requirements.format' "$shipped")
  u=$(ho_user_config)
  ho_config_file_check "$u"
  mkdir -p "$(dirname "$u")" || return 1
  { if [ -f "$u" ]; then cat "$u"; else echo '{"schemaVersion": 2}'; fi; } \
    | jq --arg f "$flow" --arg r "$format" '.confirmed_default = {flow: $f, requirements_format: $r}' \
    | ho_atomic_write "$u" || return 1
  printf 'saved the confirmed default in %s: flow %s, requirements %s\n' "$u" "$flow" "$format"
}

# ---- format openspec|none: the requirements format for this project on this machine --------------
ho_sel_format() {
  local proj s
  ho_sel_human_only || return
  case ${1-} in openspec | none) ;; *) ho_config_usage; return 64 ;; esac
  proj=$(ho_project_root 2>/dev/null) || { ho_sel_err "no local selection here; select a config first"; return 78; }
  s=$(ho_sel_read "$proj") || return 78
  [ -n "$s" ] || { ho_sel_err "no local selection here; select a config first"; return 78; }
  ho_sel_write "$proj" "$(printf '%s' "$s" | jq -c --arg r "$1" '.requirements_format = $r')" || return
  printf 'requirements format for this project on this machine: %s\n' "$1"
}

# ---- gate [--unattended]: the start check of H-072 and D37-FLOW-8 (b) -----------------------------
ho_sel_stop() {
  local unattended=$1
  shift
  ho_sel_err "$*"
  [ "$unattended" = 0 ] || ho_sel_err "attention: an unattended start found no confirmation it may use; it picks nothing and waits for a person to run /harness:config"
  return "$HO_EXIT_CONFIRM"
}

ho_sel_gate() {
  local unattended=0 proj s name f rec new raises list ud body found
  [ "${1-}" != --unattended ] || unattended=1
  proj=$(ho_project_root 2>/dev/null) || proj=""
  if [ -n "$proj" ] && [ -e "$(ho_sel_file "$proj")" ]; then
    s=$(ho_sel_read "$proj") || { ho_sel_stop "$unattended" "the local selection cannot be read; select again with /harness:config"; return; }
    name=$(printf '%s' "$s" | jq -r '.config // empty')
    if [ -n "$name" ]; then
      f=$(ho_sel_config_path "$proj" "$name")
      if ! ho_sel_name_ok "$name" || [ ! -f "$f" ] || ! jq -e 'type == "object" and .schemaVersion == 2' "$f" >/dev/null 2>&1; then
        ho_sel_stop "$unattended" "the selected config $name is missing or unreadable; the harness does not fall back to another config. Select again with /harness:config"; return
      fi
      rec=$(printf '%s' "$s" | jq -c '.approved // empty')
      if [ -z "$rec" ]; then
        ho_sel_stop "$unattended" "the selection of $name holds no record of the approved profile (as after an upgrade). Select it again with /harness:config"; return
      fi
      body=$(printf '%s' "$rec" | jq -cS '{profile, fields}' 2>/dev/null) || body=""
      if [ -z "$body" ] || [ "$(printf '%s' "$body" | ho_sel_digest)" != "$(printf '%s' "$rec" | jq -r '.digest // ""')" ]; then
        ho_sel_stop "$unattended" "the record of the approved profile does not match its digest. Select $name again with /harness:config"; return
      fi
      new=$(ho_sel_record "$f") || { ho_sel_stop "$unattended" "cannot read the recorded fields of the selected config $name"; return; }
      raises=$(ho_sel_raises "$rec" "$new") || raises="the record cannot be compared"
      if [ -n "$raises" ]; then
        ho_sel_stop "$unattended" "the committed config $name now gives more autonomy than was approved on this machine: $(printf '%s' "$raises" | paste -sd ',' - | sed 's/,/, /g'). Review the change and select it again with /harness:config"; return
      fi
      if [ "$(printf '%s' "$new" | jq -c '.digest')" != "$(printf '%s' "$rec" | jq -c '.digest')" ]; then
        ho_sel_write "$proj" "$(printf '%s' "$s" | jq -c --argjson a "$new" '.approved = $a')" || return 1
        ho_sel_err "notice: the committed config $name lowered a recorded setting; the record is updated"
      fi
      return 0
    fi
    # The confirmed default: a config committed later is announced once and not used (case 4).
    found=""
    while IFS="$(printf '\t')" read -r name f; do
      [ -n "$name" ] || continue
      printf '%s' "$s" | jq -e --arg n "$name" '(.notified // []) | index($n)' >/dev/null && continue
      found="$found${found:+ }$name"
      ho_sel_err "notice: the repository now holds the config $f. This machine keeps the confirmed default until you select it with /harness:config"
    done <<EOF_LIST
$(ho_sel_list "$proj")
EOF_LIST
    if [ -n "$found" ]; then
      ho_sel_write "$proj" "$(printf '%s' "$s" | jq -c --arg f "$found" '.notified = ((.notified // []) + ($f | split(" ")) | unique)')" || return 1
    fi
    return 0
  fi
  if [ -n "$proj" ]; then list=$(ho_sel_list "$proj"); else list=""; fi
  if [ -n "$list" ]; then
    ho_sel_stop "$unattended" "this project has no confirmed config on this machine. The repository holds: $(printf '%s\n' "$list" | cut -f2 | paste -sd ',' - | sed 's/,/, /g'). Run /harness:config to use one (or harness config select <name>); a saved user default never accepts a committed config"
    return
  fi
  ud=$(ho_cfg_user_default) || ud=""
  if [ -n "$ud" ]; then
    proj=${proj:-$(ho_sel_main_checkout)}
    ho_sel_write "$proj" "$(printf '%s' "$ud" | jq -c --arg ts "$(ho_now)" \
      '{schemaVersion: 2, config: null, default: {source: "user", flow: .flow, requirements_format: .requirements_format}, selected: $ts}')" || return 1
    ho_sel_err "notice: using the confirmed default from your user settings: flow $(printf '%s' "$ud" | jq -r .flow), requirements $(printf '%s' "$ud" | jq -r .requirements_format)"
    return 0
  fi
  ho_sel_stop "$unattended" "nothing is configured for this project. The default is the $(jq -r '.flow.use' "$(ho_sel_shipped)") flow with $(jq -r '.requirements.format' "$(ho_sel_shipped)") requirements. Confirm it, or pick another flow or format, with /harness:config (it recommends a flow you already use); or confirm the default with harness config select --default"
}

# ho_cfg_user_default: the user config's confirmed default {flow, requirements_format}, or nothing.
ho_cfg_user_default() {
  local u
  u=$(ho_user_config)
  [ -f "$u" ] || return 0
  jq -ce '.confirmed_default | select(type == "object" and (.flow | type == "string") and (.requirements_format | IN("openspec", "none")))' "$u" 2>/dev/null || true
}

# ho_sel_language: the agent language (H-077), English by default. A language name of at most
# 40 bytes on one line, with no control byte and no @ (it is filled into the role prompts).
ho_sel_language() {
  local l
  l=$(ho_cfg '.agent.language' 'English') || return 78
  if [ -z "$l" ] || [ "${#l}" -gt 40 ] || printf '%s' "$l" | LC_ALL=C grep -q '[[:cntrl:]@]'; then
    ho_sel_err "agent.language must be a language name on one line (at most 40 bytes); using English"
    l=English
  fi
  printf '%s\n' "$l"
}
