# shellcheck shell=bash
# Autonomy profiles (tasks.md 14.1; H-037 to H-042, H-047 to H-049; design D12, S8-08a, S8-08b).
# A profile holds gates and permissions only; the steps live in the flow config (D37-FLOW-3).
# Ready-made profiles are data files in <plugin>/autonomy: safe (the default), gated, draft-pr
# and full. A project or user config selects one with autonomy.profile, or selects "custom"
# and sets every field in autonomy.custom, at its own risk.
#
#   fields   gates             {<point>: "auto" | "human"}; a point is a flow step id or one of
#                              the engine points start, readiness, pr, merge. A point that is
#                              not listed is auto.
#            push              true | false
#            pr                "none" | "draft" | "ready"
#            pr_open           "none" | "after-validator" | <step id>  (when the draft PR opens)
#            merge             "never" | "always" | "classifier" (classifier: custom only)
#            post_merge        true | false (run the project's post-merge steps)
#            deploy_production true | false (false in every ready-made profile)
#            remarks           "human" | "fix"
#            allow_zero_tests  true | false
#
# The engine checks the profile at every step boundary and before push, PR, merge and deploy
# (S8-08a), not per tool call: `harness autonomy check <run-dir> <action>`. The profile is read
# once per run and kept in <run>/autonomy.json, so a config change during a run takes effect at
# the next run (H-036). Every check writes one ledger line.
#
# Migration from 0.6.0 (D12): with no autonomy.profile, guardrails.never_push true selects safe
# and false selects draft-pr. `harness autonomy migrate <file>` reads a 0.6.0 config file
# (schemaVersion 1, which the config lookup refuses) the same way; never_push was true when
# absent in 0.6.0.
#
# Exit codes: 0 allowed, 64 usage, 76 waits for a human approval (a human gate, or the merge
# classifier), 77 the profile does not allow it, 78 config error (unknown profile, a missing or
# bad field). Anything the check cannot read is refused, never allowed.
# Requires lib/common.sh, lib/files.sh, lib/config.sh, lib/run.sh and lib/tickets.sh.

HO_EXIT_HUMAN=76
HO_EXIT_DENIED=77
HO_AU_READY="safe gated draft-pr full"
HO_AU_POINT_RE='^[a-z0-9][a-z0-9-]{0,63}$'

ho_au_err() { printf 'harness: autonomy: %s\n' "$*" >&2; }

ho_au_dir() { printf '%s\n' "${HO_AUTONOMY_DIR:-$HO_ROOT/autonomy}"; }

ho_au_point_ok() { printf '%s' "${1-}" | grep -Eq "$HO_AU_POINT_RE"; }

# ho_au_problems <ready 0|1>: profile JSON on stdin; prints every problem, one per line, or
# nothing. An unknown key is a problem too, so a typo never passes as "not set".
ho_au_problems() {
  jq -r --argjson ready "$1" --arg re "$HO_AU_POINT_RE" '
    def bool($k): if (.[$k] | type) != "boolean" then "\($k) must be true or false" else empty end;
    def one($k; $vals): if (.[$k] | IN($vals[])) then empty else "\($k) must be one of \($vals | join(", "))" end;
    if type != "object" then "the profile is not a JSON object" else
      ([keys[] | select(IN("schemaVersion", "name", "description", "gates", "push", "pr", "pr_open",
          "merge", "post_merge", "deploy_production", "remarks", "allow_zero_tests") | not)
        | "unknown field \(.)"]
      + [if (.gates | type) != "object" then "gates must be an object of point: auto | human"
         else (.gates | to_entries[]
           | if (.key | test($re)) | not then "gate point \(.key) must use a-z 0-9 -"
             elif (.value | IN("auto", "human")) | not then "gate \(.key) must be auto or human"
             else empty end) end]
      + [bool("push"), bool("post_merge"), bool("deploy_production"), bool("allow_zero_tests")]
      + [one("pr"; ["none", "draft", "ready"]), one("merge"; ["never", "always", "classifier"]),
         one("remarks"; ["human", "fix"])]
      + [if (.pr_open | type) == "string" and ((.pr_open | IN("none", "after-validator")) or (.pr_open | test($re)))
         then empty else "pr_open must be none, after-validator or a step id" end]
      + (if $ready == 1 then
          [if .merge == "classifier" then "a ready-made profile never uses merge: classifier (D12)" else empty end,
           if .deploy_production != false then "a ready-made profile never deploys to production (H-048)" else empty end]
        else [] end))[]
    end' 2>/dev/null || echo "the profile is not readable JSON"
}

# ho_au_name: print "<profile name> TAB <source>" from the config lookup. A project config that
# sets guardrails.never_push true and no profile of its own selects safe: a user's
# autonomy.profile never overrides it (wave-4 follow-up #110; fail closed).
ho_au_name() {
  local name np proj pf pnp
  if proj=$(ho_project_root 2>/dev/null); then
    pf=$(ho_sel_project_config "$proj") || return 78
    if [ -n "$pf" ]; then
      pnp=$(jq -r 'if (.autonomy.profile // null) == null and .guardrails.never_push == true then "yes" else "no" end' "$pf" 2>/dev/null) || return 78
      [ "$pnp" = no ] || { printf 'safe\tproject guardrails.never_push true\n'; return 0; }
    fi
  fi
  name=$(ho_cfg '.autonomy.profile' '') || return 78
  if [ -n "$name" ]; then printf '%s\tconfig autonomy.profile\n' "$name"; return 0; fi
  np=$(ho_cfg '.guardrails.never_push' '') || return 78
  case $np in
    true) printf 'safe\tmigrated from guardrails.never_push true\n' ;;
    false) printf 'draft-pr\tmigrated from guardrails.never_push false\n' ;;
    '') printf 'safe\tdefault\n' ;;
    *) ho_au_err "guardrails.never_push must be true or false, not $np"; return 78 ;;
  esac
}

# ho_au_resolve: print the selected profile as one JSON object with name and source.
ho_au_resolve() {
  local line name src f prof why ready=1
  line=$(ho_au_name) || return 78
  name=${line%%	*}
  src=${line#*	}
  case " $HO_AU_READY custom " in
    *" $name "*) ;;
    *) ho_au_err "unknown profile $name; use one of $HO_AU_READY or custom"; return 78 ;;
  esac
  if [ "$name" = custom ]; then
    ready=0
    prof=$(ho_cfg '.autonomy.custom' '') || return 78
    [ -n "$prof" ] || { ho_au_err "profile custom needs every field in autonomy.custom"; return 78; }
  else
    f="$(ho_au_dir)/$name.json"
    [ -f "$f" ] && [ ! -L "$f" ] || { ho_au_err "the ready-made profile file $f is missing"; return 78; }
    prof=$(cat "$f") || return 78
    [ "$(printf '%s' "$prof" | jq -r '.name' 2>/dev/null)" = "$name" ] \
      || { ho_au_err "the profile file $f does not name $name"; return 78; }
  fi
  why=$(printf '%s' "$prof" | ho_au_problems "$ready")
  if [ -n "$why" ]; then
    ho_au_err "profile $name is refused: $(printf '%s' "$why" | paste -sd ';' - | sed 's/;/; /g')"
    return 78
  fi
  printf '%s' "$prof" | jq -c --arg n "$name" --arg s "$src" \
    'del(.schemaVersion, .description) | .name = $n | .source = $s'
}

# ho_au_profile: the run's profile, read once and kept in <run>/autonomy.json (H-036).
ho_au_profile() {
  local f="$HO_RUN_DIR/autonomy.json" prof
  [ ! -L "$f" ] || { ho_au_err "$f is a link; a profile is never read through a link"; return 78; }
  if [ -f "$f" ]; then
    prof=$(cat "$f") || return 78
    printf '%s' "$prof" | jq -e 'type == "object" and (.name | type) == "string"' >/dev/null 2>&1 \
      && [ -z "$(printf '%s' "$prof" | jq 'del(.name, .source)' 2>/dev/null | ho_au_problems 0)" ] \
      || { ho_au_err "the run's profile $f is unreadable or damaged"; return 78; }
    printf '%s\n' "$prof"
    return 0
  fi
  prof=$(ho_au_resolve) || return 78
  printf '%s\n' "$prof" | ho_atomic_write "$f" || return 78
  ho_ledger_append autonomy-profile name "$(printf '%s' "$prof" | jq -r .name)" source "$(printf '%s' "$prof" | jq -r .source)"
  printf '%s\n' "$prof"
}

# ho_au_always_human: the "always a human" path list (S8-08b): the project and the user lists
# together, so neither layer can drop a path the other names. One pattern per line.
ho_au_always_human() {
  local files f list
  files=$(ho_config_files) || return 78
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    list=$(jq -c '.autonomy.always_human_paths // []' "$f" 2>/dev/null) || list=bad
    printf '%s' "$list" | jq -e 'type == "array" and all(type == "string" and length > 0 and (test("[\u0000-\u001f]") | not))' >/dev/null 2>&1 \
      || { ho_au_err "autonomy.always_human_paths in $f must be a list of path patterns"; return 78; }
    printf '%s' "$list" | jq -r '.[]'
  done <<EOF_FILES
$files
EOF_FILES
}

# ho_au_merge_conditions <profile> <facts-file>: print every S8-08b condition that does not hold,
# one per line. A missing or unreadable fact fails its condition.
ho_au_merge_conditions() {
  local prof=$1 facts=$2 pats p pat out
  if [ -L "$facts" ] || [ ! -f "$facts" ] || ! jq -e 'type == "object"' "$facts" >/dev/null 2>&1; then
    echo "no readable merge facts"; return 0
  fi
  out=$(jq -r --argjson zero "$(printf '%s' "$prof" | jq '.allow_zero_tests')" '
    def int: type == "number" and . == floor and . >= 0;
    (if .validator == "passed" then empty else "no clean validator pass" end),
    (if (.tests | type) == "object" and (.tests.total | int) and (.tests.failed | int) then
       (if .tests.failed == 0 then empty else "\(.tests.failed) test(s) failed" end),
       (if .tests.total > 0 or $zero then empty else "zero tests ran" end)
     else "the test count is unknown" end),
    (if .ci == "green" then empty else "CI is not green" end),
    (if (.open_questions | int) and .open_questions == 0 then empty else "an open question is not answered (or the count is unknown)" end),
    (if (.paths | type) == "array" and (.paths | all(type == "string" and (test("[\u0000-\u001f]") | not)))
     then empty else "the changed paths are unknown" end)' "$facts" 2>/dev/null) || out="the merge facts cannot be read"
  [ -z "$out" ] || printf '%s\n' "$out"
  jq -e '(.paths | type) == "array" and (.paths | all(type == "string" and (test("[\u0000-\u001f]") | not)))' "$facts" >/dev/null 2>&1 || return 0
  pats=$(ho_au_always_human) || { echo "the always-a-human list cannot be read"; return 0; }
  [ -n "$pats" ] || return 0
  out=""
  while IFS= read -r p; do
    while IFS= read -r pat; do
      [ -n "$pat" ] || continue
      # shellcheck disable=SC2254 # the pattern is a glob on purpose
      case $p in $pat) out="${out}${out:+, }$p"; break ;; esac
    done <<EOF_PATS
$pats
EOF_PATS
  done <<EOF_PATHS
$(jq -r '.paths[]' "$facts")
EOF_PATHS
  [ -z "$out" ] || echo "a path on the always-a-human list changed: $out"
}

ho_au_approval_file() { printf '%s/approvals/%s.%s.json\n' "$HO_RUN_DIR" "$1" "$2"; }

# ho_au_gate_point <profile> <for> <point>: 0 when the point is auto or approved, else 76.
ho_au_gate_point() {
  local g f
  g=$(printf '%s' "$1" | jq -r --arg p "$3" '.gates[$p] // "auto"')
  [ "$g" = human ] || return 0
  [ -n "$2" ] || return "$HO_EXIT_HUMAN"
  f=$(ho_au_approval_file "$2" "$3")
  [ -f "$f" ] && [ ! -L "$f" ] && [ ! -L "$HO_RUN_DIR/approvals" ] || return "$HO_EXIT_HUMAN"
}

# ho_au_decide <profile> <action> <for> <step> <facts> <local 0|1>: sets HO_AU_RC and HO_AU_WHY.
ho_au_decide() {
  local prof=$1 action=$2 for=$3 step=$4 facts=$5 local=$6 push pr merge rc conds dep
  HO_AU_RC=0
  HO_AU_WHY=""
  push=$(printf '%s' "$prof" | jq -r .push)
  pr=$(printf '%s' "$prof" | jq -r .pr)
  merge=$(printf '%s' "$prof" | jq -r .merge)
  case $action in
    start | step)
      [ "$action" = start ] && step=start
      ho_au_gate_point "$prof" "$for" "$step" || { HO_AU_RC=$?; HO_AU_WHY="$step is a human gate: a human approves it with harness autonomy approve"; return; }
      HO_AU_WHY="$step is not gated" ;;
    push)
      [ "$push" = true ] || { HO_AU_RC=$HO_EXIT_DENIED; HO_AU_WHY="the profile allows no push; nothing leaves this machine"; return; }
      HO_AU_WHY="push is allowed" ;;
    pr | pr-ready)
      case $action:$pr in
        *:none) HO_AU_RC=$HO_EXIT_DENIED; HO_AU_WHY="the profile opens no PR"; return ;;
        pr-ready:draft) HO_AU_RC=$HO_EXIT_DENIED; HO_AU_WHY="the profile opens a draft PR only; a human marks it ready"; return ;;
      esac
      [ "$push" = true ] || { HO_AU_RC=$HO_EXIT_DENIED; HO_AU_WHY="the profile allows no push, so no PR can open"; return; }
      # The pr gate is passed after the draft PR opens: a human approves the PR before it is
      # marked ready (D12 gated opens its draft and stops there).
      if [ "$action" = pr-ready ]; then
        ho_au_gate_point "$prof" "$for" pr || { HO_AU_RC=$?; HO_AU_WHY="pr is a human gate: a human approves the PR with harness autonomy approve before it is marked ready"; return; }
      fi
      HO_AU_WHY="a $pr PR is allowed" ;;
    merge)
      if [ "$local" = 1 ]; then
        # The run's local integration merge: refused only when nothing may leave the machine
        # and nothing may merge (D12 safe: "not even a local integration merge").
        if [ "$push" != true ] && [ "$merge" = never ]; then
          HO_AU_RC=$HO_EXIT_DENIED; HO_AU_WHY="the profile allows no push and no merge, so it merges into no branch, not even a local one"; return
        fi
        HO_AU_WHY="a local integration merge is allowed"; return
      fi
      case $merge in
        never) HO_AU_RC=$HO_EXIT_DENIED; HO_AU_WHY="the profile never merges; a human merges"; return ;;
        classifier) HO_AU_RC=$HO_EXIT_HUMAN; HO_AU_WHY="the merge classifier is not part of this engine yet, so the merge waits for a human"; return ;;
      esac
      ho_au_gate_point "$prof" "$for" merge || { HO_AU_RC=$?; HO_AU_WHY="merge is a human gate: a human approves it with harness autonomy approve"; return; }
      [ -n "$facts" ] || { HO_AU_RC=$HO_EXIT_DENIED; HO_AU_WHY="a merge needs the merge facts (--facts) to check the mechanical conditions"; return; }
      conds=$(ho_au_merge_conditions "$prof" "$facts")
      [ -z "$conds" ] || { HO_AU_RC=$HO_EXIT_DENIED; HO_AU_WHY="merge refused: $(printf '%s' "$conds" | paste -sd ';' - | sed 's/;/; /g')"; return; }
      HO_AU_WHY="every mechanical merge condition holds" ;;
    post-merge)
      [ "$(printf '%s' "$prof" | jq -r .post_merge)" = true ] || { HO_AU_RC=$HO_EXIT_DENIED; HO_AU_WHY="the profile runs no post-merge steps"; return; }
      HO_AU_WHY="post-merge steps are allowed" ;;
    deploy)
      [ "$(printf '%s' "$prof" | jq -r .deploy_production)" = true ] || { HO_AU_RC=$HO_EXIT_DENIED; HO_AU_WHY="the profile never deploys to production"; return; }
      rc=0; dep=$(ho_cfg '.deploy.use' '') || rc=$?
      [ "$rc" -eq 0 ] || { HO_AU_RC=78; HO_AU_WHY="the deploy setting cannot be read"; return; }
      [ -n "$dep" ] || { HO_AU_RC=$HO_EXIT_DENIED; HO_AU_WHY="the project has no deployment configured (deploy.use)"; return; }
      HO_AU_WHY="production deploy is allowed by the user's own profile" ;;
    *) HO_AU_RC=$HO_EXIT_DENIED; HO_AU_WHY="unknown action $action" ;;
  esac
}

# ---- check <action> [--for ID] [--step ID] [--facts FILE] [--local] -------------------------
ho_au_check() {
  local action=${1-} for="" step="" facts="" local=0 prof tag name
  shift || true
  case $action in start | step | push | pr | pr-ready | merge | post-merge | deploy) ;; *) ho_au_usage; return 64 ;; esac
  while [ $# -gt 0 ]; do
    case $1 in
      --local) local=1; shift ;;
      --for | --step | --facts)
        [ $# -ge 2 ] && [ -n "$2" ] || { ho_au_usage; return 64; }
        case $1 in --for) for=$2 ;; --step) step=$2 ;; *) facts=$2 ;; esac
        shift 2 ;;
      *) ho_au_usage; return 64 ;;
    esac
  done
  [ "$action" != step ] || [ -n "$step" ] || { ho_au_err "check step needs --step <id>"; return 64; }
  [ -z "$step" ] || ho_au_point_ok "$step" || { ho_au_err "step id must use a-z 0-9 -: $step"; return 64; }
  [ -z "$for" ] || ho_au_point_ok "$for" || { ho_au_err "--for must be a ticket id or lane name of a-z 0-9 -: $for"; return 64; }
  [ "$local" = 0 ] || [ "$action" = merge ] || { ho_au_usage; return 64; }
  prof=$(ho_au_profile) || return 78
  ho_au_decide "$prof" "$action" "$for" "$step" "$facts" "$local"
  name=$(printf '%s' "$prof" | jq -r .name)
  tag=$action
  [ "$local" = 0 ] || tag="$action-local"
  ho_ledger_append autonomy-check action "$tag" point "$step" for "$for" profile "$name" result "$HO_AU_RC" reason "$HO_AU_WHY"
  if [ "$HO_AU_RC" -eq 0 ]; then
    printf 'allowed: %s (profile %s)\n' "$HO_AU_WHY" "$name"
  else
    ho_au_err "$tag refused under profile $name: $HO_AU_WHY"
  fi
  return "$HO_AU_RC"
}

# ---- approve <for> <point>: a human approves one gated point -------------------------------
ho_au_approve() {
  local for=${1-} point=${2-} d="$HO_RUN_DIR/approvals"
  [ $# -eq 2 ] && ho_au_point_ok "$for" && ho_au_point_ok "$point" || { ho_au_usage; return 64; }
  # A launched session carries these; an approval from inside one is not a human's.
  if [ -n "${HO_SESSION_ID-}" ] || [ -n "${HO_SESSION_NAME-}" ]; then
    ho_au_err "an approval is given by a human, never from inside a harness session"
    return "$HO_EXIT_DENIED"
  fi
  [ ! -L "$d" ] || { ho_au_err "$d is a link; nothing is written through it"; return "$HO_EXIT_DENIED"; }
  mkdir -p "$d" || return 1
  jq -n --arg for "$for" --arg point "$point" --arg ts "$(ho_now)" '{schemaVersion: 2, for: $for, point: $point, approved: $ts}' \
    | ho_atomic_write "$(ho_au_approval_file "$for" "$point")" || return 1
  ho_ledger_append autonomy-approved for "$for" point "$point"
  printf 'approved %s for %s\n' "$point" "$for"
}

# ---- end <ticket>: the ticket stops at the last step the profile allows (H-042) --------------
ho_au_end() {
  local id=${1-} prof name
  [ $# -eq 1 ] && [ -n "$id" ] || { ho_au_usage; return 64; }
  prof=$(ho_au_profile) || return 78
  name=$(printf '%s' "$prof" | jq -r .name)
  if [ "$(printf '%s' "$prof" | jq -r .merge)" = never ]; then
    ho_tickets review "$id" || return
    ho_ledger_append autonomy-end ticket "$id" profile "$name" state needs-review
    return 0
  fi
  printf 'profile %s may merge: ticket %s is set to done only after a confirmed merge and its post-merge steps (H-045)\n' "$name" "$id"
}

# ---- migrate <0.6.0 config file> ----------------------------------------------------------
ho_au_migrate() {
  local f=${1-} v
  [ $# -eq 1 ] && [ -n "$f" ] || { ho_au_usage; return 64; }
  [ -f "$f" ] && [ ! -L "$f" ] || { ho_au_err "no such config file: $f"; return 78; }
  v=$(jq -r 'if type != "object" then error("x") else (.guardrails.never_push | if . == null then "absent" else tojson end) end' "$f" 2>/dev/null) \
    || { ho_au_err "$f is not a readable JSON object"; return 78; }
  case $v in
    true | absent) echo safe ;;
    false) echo draft-pr ;;
    *) ho_au_err "guardrails.never_push in $f must be true or false, not $v"; return 78 ;;
  esac
}

ho_au_usage() {
  cat >&2 <<'USAGE'
usage: harness autonomy show                          the profile the config selects, as JSON
       harness autonomy list                          the ready-made profiles
       harness autonomy migrate <0.6.0-config>        the profile a 0.6.0 config becomes
       harness autonomy <run-dir> check <action> [--for ID] [--step ID] [--facts FILE] [--local]
              actions: start, step --step ID, push, pr, pr-ready, merge, post-merge, deploy
       harness autonomy <run-dir> approve <for> <point>   a human approves one gated point
       harness autonomy <run-dir> end <ticket>        needs-review when the profile never merges
exit: 0 allowed, 64 usage, 76 waits for a human, 77 not allowed by the profile, 78 config error
USAGE
}

ho_autonomy_main() {
  local rc=0 verb
  case ${1-} in
    show) [ $# -eq 1 ] || { ho_au_usage; exit 64; }; ho_au_resolve || exit $?; exit 0 ;;
    list) [ $# -eq 1 ] || { ho_au_usage; exit 64; }
      for verb in $HO_AU_READY; do jq -r '"\(.name)\t\(.description)"' "$(ho_au_dir)/$verb.json"; done; exit 0 ;;
    migrate) shift; ho_au_migrate "$@" || exit $?; exit 0 ;;
    '' | help | -h | --help) ho_au_usage; exit 64 ;;
  esac
  [ $# -ge 2 ] || { ho_au_usage; exit 64; }
  ho_run_open "$1"
  # A run-specific check reads the config of the project the run belongs to, never the caller's
  # (H-036): the profile is read once from there. HO_PROJECT_DIR naming another project is refused.
  ho_session_bind_project || exit $?
  # "end" moves a local ticket: the folder of the run's own project, never the caller's.
  ho_tk_bind_project_dir
  verb=$2
  shift 2
  case $verb in
    check) ho_au_check "$@" || rc=$? ;;
    approve) ho_au_approve "$@" || rc=$? ;;
    end) ho_au_end "$@" || rc=$? ;;
    *) ho_au_usage; rc=64 ;;
  esac
  exit "$rc"
}
