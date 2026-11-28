# shellcheck shell=bash
# Subscription limits per account (H-109, H-110, H-111, H-112; design D28, D28a, D28b, D29,
# S8-23, D37-LIMITS-5).
#
# Reading source (D28): the status line data of each session. A session's status line command
# is "harness limits record"; it reads the runtime's status line JSON on stdin and keeps one
# reading per account. Where the windows sit in that JSON is runtime data
# (runtimes/<name>.json: status_line.windows, .used, .resets; D37-RUNTIME-1). Every window
# present is kept under the name the account reports; none is named in engine code.
#
#   <run>/limits/<account>.json        the newest reading of a session of this run
#   <user dir>/limits/<account>.json   the newest reading outside a run
#   <run>/limits-state.json            the last check, so a change is recorded once
#
# A reading: {schemaVersion, account, ts, windows: {<name>: {used: <percent>, resets_at: <epoch|null>}}}
#
# Thresholds (H-110, D28a): optional, per window, under limits.thresholds.<window>, or
# limits.thresholds["*"] for every window without its own key. A value is a percent, or
# {"at": <percent>, "action": <action>}. Lookup per window: project <window>, project "*",
# user <window>, user "*". Nothing set means off: no threshold action and no reserve (D29).
# A value above 100 never triggers.
# Actions: pause_spawns (the default), soft_stop_step, soft_stop_ticket, hard_stop. hard_stop
# arrives with the hard stops of a later release; until then it pauses spawns and records why.
#
# Unknown (D28b): no reading, an unreadable one, a window whose used percent is not a number,
# or a window whose reset time has passed (the reading no longer says anything) reads
# "unknown". Unknown is recorded once in the run ledger when it begins, shown as unknown in
# status, never as OK, and never blocks a start (H-111).
#
# The direct endpoint read (S8-23) is an opt-in fallback, off by default: only the user config
# can switch it on (limits.endpoint_read: true) and name its command (limits.endpoint_command),
# which prints a reading as JSON for the account in HO_ACCOUNT. A project config is never read
# for it (D61: repository files are not trusted).
#
# Exit codes: 64 usage, 74 a worker start refused because a threshold paused spawns,
# 78 config error.
#
# Requires lib/config.sh, lib/run.sh and lib/sessions.sh (ho_cfg_user, ho_runtime_profile).

HO_LIMITS_ACTIONS="pause_spawns soft_stop_step soft_stop_ticket hard_stop"
HO_EXIT_PAUSED=74

ho_limits_user_dir() { printf '%s/limits\n' "${HO_USER_DIR:-$HOME/.claude/harness}"; }

ho_limits_account_ok() { printf '%s' "${1-}" | grep -Eqx '[a-z0-9][a-z0-9-]{0,39}'; }

# ho_limits_record: read the status line JSON on stdin, keep the reading, then run the user's
# own status line command with the same stdin and print its output unchanged, so a harness
# session keeps the user's line (the screen reader expects its shape: status_first_line). The
# user's command is the one in the settings the session would otherwise load
# (status_line.user_settings and .user_command in runtime data, {config_dir} as the session
# gets it). With none, nothing is printed. A failure of the reading or of the user's command
# never fails the other, and the status line command always exits 0.
ho_limits_record() {
  local in profile
  in=$(cat) || in=""
  profile=$(ho_runtime_profile 2>/dev/null) || return 0
  printf '%s' "$in" | ho_limits_keep "$profile" 2>/dev/null || true
  ho_limits_user_line "$profile" "$in" || true
  return 0
}

# ho_limits_keep <profile>: the reading of stdin, kept for $HO_ACCOUNT.
ho_limits_keep() {
  local profile=$1 acct=${HO_ACCOUNT:-default} w u r dir reading
  ho_limits_account_ok "$acct" || acct=default
  w=$(jq -r '.status_line.windows // empty' "$profile")
  u=$(jq -r '.status_line.used // empty' "$profile")
  r=$(jq -r '.status_line.resets // empty' "$profile")
  [ -n "$w" ] && [ -n "$u" ] && [ -n "$r" ] || return 0
  reading=$(jq -c --arg w "$w" --arg u "$u" --arg r "$r" --arg acct "$acct" --argjson ts "$(date +%s)" '
      def epoch: if type == "number" then floor
        elif type == "string" then (try (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) catch null)
        else null end;
      (getpath($w | ltrimstr(".") | split(".")) // {}) as $win
      | if ($win | type) != "object" then error("no windows") else . end
      | {schemaVersion: 2, account: $acct, ts: $ts,
         windows: ($win | with_entries(select(.key | test("^[A-Za-z0-9_-]{1,40}$"))
           | .value = (if (.value | type) == "object" then {used: .value[$u], resets_at: (.value[$r] | epoch)} else {used: null, resets_at: null} end)))}') \
    || return 0
  if [ -n "${HO_RUN_DIR:-}" ] && [ -f "$HO_RUN_DIR/run.json" ]; then dir="$HO_RUN_DIR/limits"; else dir=$(ho_limits_user_dir); fi
  mkdir -p "$dir" && [ ! -L "$dir/$acct.json" ] && printf '%s\n' "$reading" | ho_atomic_write "$dir/$acct.json"
}

# ho_limits_user_line <profile> <stdin-text>: run the user's own status line command.
ho_limits_user_line() {
  local profile=$1 in=$2 cdir sf key cmd
  # A user line that is itself this command must not call itself again.
  [ -z "${HO_LIMITS_IN_RECORD:-}" ] || return 0
  sf=$(jq -r '.status_line.user_settings // ""' "$profile")
  key=$(jq -r '.status_line.user_command // ""' "$profile")
  [ -n "$sf" ] && [ -n "$key" ] || return 0
  cdir=$(ho_rt_config_dir "$profile" "" 2>/dev/null) || return 0
  sf=${sf//\{config_dir\}/$cdir}
  [ -f "$sf" ] || return 0
  cmd=$(jq -r "$key | strings" "$sf" 2>/dev/null) || return 0
  [ -n "$cmd" ] || return 0
  printf '%s' "$in" | HO_LIMITS_IN_RECORD=1 /bin/bash -c "$cmd" 2>/dev/null || true
}

# ho_limits_accounts: the accounts to read: every label in the user config's accounts.list,
# "default" (the normal login) when the list is empty, and any account with a reading in this
# run (a role on the normal login).
ho_limits_accounts() {
  {
    ho_cfg_user '.accounts.list // {} | if type == "object" then keys[] else empty end' | jq -r 'strings'
    case $(ho_cfg_user '.accounts.list // {} | if type == "object" then length else 0 end') in '' | 0 | null) echo default ;; esac
    for f in "$HO_RUN_DIR/limits"/*.json; do [ -f "$f" ] && basename "$f" .json; done
  } | while IFS= read -r a; do ho_limits_account_ok "$a" && printf '%s\n' "$a"; done | sort -u
}

# ho_limits_reading <account>: the newest readable reading (run, user dir, or the opt-in
# endpoint command); "null" when there is none.
ho_limits_reading() {
  local a=$1 best=null f r cmd
  for f in "$HO_RUN_DIR/limits/$a.json" "$(ho_limits_user_dir)/$a.json"; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    r=$(jq -c 'select(type == "object" and (.windows | type) == "object" and (.ts | type) == "number")' "$f" 2>/dev/null) || continue
    [ -n "$r" ] || continue
    best=$(jq -cn --argjson a "$best" --argjson b "$r" 'if $a == null or $b.ts > $a.ts then $b else $a end')
  done
  if [ "$best" = null ] && [ "$(ho_cfg_user '.limits.endpoint_read')" = true ]; then
    cmd=$(ho_cfg_user '.limits.endpoint_command' | jq -r 'strings // ""')
    if [ -n "$cmd" ]; then
      r=$(HO_ACCOUNT=$a /bin/bash -c "$cmd" 2>/dev/null | jq -c --arg a "$a" --argjson ts "$(date +%s)" \
        'select(type == "object" and (.windows | type) == "object") | {schemaVersion: 2, account: $a, ts: $ts, windows}' 2>/dev/null) || r=""
      [ -n "$r" ] && best=$r
    fi
  fi
  printf '%s\n' "$best"
}

# ho_limits_threshold <window>: {"at": N, "action": A} or null. Exit 78 on a bad value.
ho_limits_threshold() {
  local w=$1 files f key v
  files=$(ho_config_files) || return 78
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    for key in "$w" '*'; do
      v=$(jq -c --arg k "$key" '.limits.thresholds[$k] // null' "$f" 2>/dev/null) || v=bad
      [ "$v" = null ] && continue
      v=$(printf '%s' "$v" | jq -c 'if type == "number" then {at: ., action: "pause_spawns"}
          elif type == "object" and (.at | type) == "number" then {at, action: (.action // "pause_spawns")}
          else error("bad") end' 2>/dev/null) || v=bad
      if [ "$v" = bad ] || ! printf '%s' "$v" | jq -e --arg acts "$HO_LIMITS_ACTIONS" '.at >= 0 and (.action | IN($acts | split(" ")[]))' >/dev/null 2>&1; then
        printf 'harness: config %s limits.thresholds["%s"] must be a percent or {"at": <percent>, "action": one of %s}\n' "$f" "$key" "$HO_LIMITS_ACTIONS" >&2
        return 78
      fi
      printf '%s\n' "$v"
      return 0
    done
  done <<EOF_FILES
$files
EOF_FILES
  echo null
}

# ho_limits_eval: the verdict for every account and window, as one JSON object:
# {ts, rows: [{account, window, used, resets_at, state: ok|over|unknown, at, action}]}
ho_limits_eval() {
  local now a reading rows='[]' w t names
  now=$(date +%s)
  for a in $(ho_limits_accounts); do
    reading=$(ho_limits_reading "$a")
    if [ "$reading" = null ]; then
      rows=$(jq -cn --argjson r "$rows" --arg a "$a" '$r + [{account: $a, window: "-", used: null, resets_at: null, state: "unknown", at: null, action: null}]')
      continue
    fi
    names=$(printf '%s' "$reading" | jq -r '.windows | keys[] | select(test("^[A-Za-z0-9_-]{1,40}$"))')
    [ -n "$names" ] || rows=$(jq -cn --argjson r "$rows" --arg a "$a" '$r + [{account: $a, window: "-", used: null, resets_at: null, state: "unknown", at: null, action: null}]')
    for w in $names; do
      t=$(ho_limits_threshold "$w") || return 78
      rows=$(jq -cn --argjson r "$rows" --argjson rd "$reading" --arg a "$a" --arg w "$w" --argjson t "$t" --argjson now "$now" '
        ($rd.windows[$w]) as $x
        | ($x.used | if type == "number" then . else null end) as $u
        | ($x.resets_at | if type == "number" then . else null end) as $rs
        | (if $u == null or ($rs != null and $rs <= $now) then "unknown"
           elif $t != null and $t.at <= 100 and $u >= $t.at then "over" else "ok" end) as $st
        | $r + [{account: $a, window: $w, used: $u, resets_at: $rs, state: $st, at: ($t.at // null), action: ($t.action // null)}]')
    done
  done
  jq -cn --argjson r "$rows" --argjson now "$now" '{ts: $now, rows: $r}'
}

# ho_limits_apply <verdict>: record what changed since the last check and run the actions.
# Prints one line per action taken. Never fails because of a reading.
ho_limits_apply() {
  local v=$1 prev sf="$HO_RUN_DIR/limits-state.json" key row a w used at act rs st
  prev='{"rows":[]}'
  [ -f "$sf" ] && [ ! -L "$sf" ] && prev=$(jq -c 'select(type == "object" and (.rows | type) == "array")' "$sf" 2>/dev/null) && [ -n "$prev" ] || prev='{"rows":[]}'
  # One ledger line when a window becomes unknown, starts or ends a crossing (D28b).
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    a=$(jq -r .account <<<"$row"); w=$(jq -r .window <<<"$row"); st=$(jq -r .state <<<"$row")
    used=$(jq -r '.used // "?"' <<<"$row"); at=$(jq -r '.at // ""' <<<"$row"); act=$(jq -r '.action // ""' <<<"$row")
    rs=$(jq -r '.resets_at // ""' <<<"$row")
    case $st in
      unknown) ho_ledger_append limits-unknown account "$a" window "$w" ;;
      ok) ho_ledger_append limits-clear account "$a" window "$w" used "$used" ;;
      over)
        key="$a/$w/$rs"
        ho_ledger_append limits-over account "$a" window "$w" used "$used" at "$at" action "$act" resets_at "$rs" key "$key"
        case $act in
          soft_stop_step | soft_stop_ticket)
            ho_stop_read
            if [ "$HO_STOP_STATE" != stop ]; then
              local type=soft:step
              [ "$act" = soft_stop_ticket ] && type=soft:ticket
              echo "limits: account $a window $w at ${used}% (threshold ${at}%): soft stop"
              ho_state_stop --type "$type" "limit threshold: account $a window $w at ${used}% (threshold ${at}%)"
            fi
            ;;
          hard_stop)
            ho_ledger_append decision title "limit threshold set to hard_stop" \
              reason "hard stops are not part of this engine yet; spawns are paused instead (account $a window $w at ${used}%)"
            echo "limits: account $a window $w at ${used}% (threshold ${at}%): hard_stop is not built yet; spawns paused"
            ;;
          *) echo "limits: account $a window $w at ${used}% (threshold ${at}%): spawns paused" ;;
        esac
        ;;
    esac
  done <<EOF_ROWS
$(jq -cn --argjson p "$prev" --argjson v "$v" '
    ($p.rows | map({key: "\(.account)/\(.window)", value: .}) | from_entries) as $old
    | $v.rows[] | . as $r | ($old["\(.account)/\(.window)"] // {state: "none"}) as $o
    | select(.state != $o.state and (.state != "ok" or $o.state == "over"))')
EOF_ROWS
  printf '%s\n' "$v" | ho_atomic_write "$sf" 2>/dev/null || true
}

# ho_limits_paused <verdict>: 0 when a window is over a threshold whose action pauses spawns.
ho_limits_paused() {
  printf '%s' "$1" | jq -e 'any(.rows[]; .state == "over" and (.action == "pause_spawns" or .action == "hard_stop"))' >/dev/null 2>&1
}

# ho_limits_gate <role>: may a session of this role start? Only workers are gated (the worker cap
# counts workers too). 0 yes, 74 a threshold paused spawns, 78 a bad threshold config. An
# unreadable limit never refuses (H-111).
ho_limits_gate() {
  local v rc=0
  [ "$1" = worker ] || return 0
  v=$(ho_limits_eval) || rc=$?
  [ "$rc" -ne 78 ] || return 78
  [ "$rc" -eq 0 ] && [ -n "$v" ] || return 0
  ho_limits_apply "$v" >/dev/null 2>&1 || true
  if ho_limits_paused "$v"; then
    printf 'harness: a limit threshold paused spawns (%s); the worker was not launched and waits until the window resets or drops below its threshold\n' \
      "$(printf '%s' "$v" | jq -r '[.rows[] | select(.state == "over") | "\(.account) \(.window) \(.used)% >= \(.at)%"] | join(", ")')" >&2
    return "$HO_EXIT_PAUSED"
  fi
  return 0
}

# ho_limits_status_lines <verdict>: one line per account and window; unknown is never OK.
ho_limits_status_lines() {
  printf '%s' "$1" | jq -r '.rows[] | "\(.account)\t\(.window)\t\(if .used == null or .state == "unknown" then "unknown" else "\(.used)%" end)\t\(if .resets_at == null then "-" else (.resets_at | todate) end)\t\(.state)\(if .at != null then "\tthreshold \(.at)% \(.action)" else "" end)"'
}

# ho_limits_wait <account> [--until EPOCH]: the STOP-aware wait for a hit limit (H-114, D28c).
# The reset time is --until, else the one an open wait of this account recorded (PR-8: a reading
# that turns unreadable or disagrees does not move it), else the latest reset of the account's
# windows at 100% (else of all its windows), else limits.unknown_wait_seconds (900) from now. One
# wait-begin line, one wait-end line (PR-5: one wait, not one line per cycle). The D21 attempt
# clock stops while the wait is open (lib/recover.sh). Exit 0 at the reset time plus
# limits.resume_margin_seconds (60): the caller continues the run with no owner action, a
# session by its ID (D37-LIFECYCLE-1). Exit 75 when a STOP arrives during the wait.
ho_limits_wait() {
  local a=${1-} until="" slice margin now left st reading
  shift || true
  ho_limits_account_ok "$a" || { echo "harness: limits wait needs an account label (a-z 0-9 -)" >&2; return 64; }
  while [ $# -gt 0 ]; do
    case $1 in
      --until) [ $# -ge 2 ] && case $2 in '' | *[!0-9]*) false ;; esac || { echo "harness: --until needs epoch seconds" >&2; return 64; }; until=$2; shift 2 ;;
      *) ho_limits_usage; return 64 ;;
    esac
  done
  slice=$(ho_cfg_int '.limits.wait_slice_seconds' 30) || return 78
  [ "$slice" -ge 1 ] || slice=1
  margin=$(ho_cfg_int '.limits.resume_margin_seconds' 60) || return 78
  local open
  open=$(ho_ledger_events | jq -sr --arg a "$a" '[.[] | select((.kind == "wait-begin" or .kind == "wait-end") and .reason == "limit" and .account == $a)] | last // {} | if .kind == "wait-begin" then .until else "" end')
  if [ -n "$open" ]; then
    until=$open
  else
    if [ -z "$until" ]; then
      reading=$(ho_limits_reading "$a")
      until=$(printf '%s' "$reading" | jq -r 'if . == null then "" else
          ([.windows[] | select((.used | type) == "number" and .used >= 100) | .resets_at | numbers] | max)
          // ([.windows[] | .resets_at | numbers] | max) // "" end' 2>/dev/null) || until=""
      [ -n "$until" ] || until=$(( $(date +%s) + $(ho_cfg_int '.limits.unknown_wait_seconds' 900) ))
    fi
    ho_ledger_append wait-begin reason limit account "$a" until "$until"
  fi
  echo "limits: account $a waits until $(jq -rn --argjson u "$until" '$u | todate') (+${margin}s)"
  while :; do
    st=0; ho_stopped 2>/dev/null || st=$?
    if [ "$st" -eq 0 ]; then
      ho_ledger_append wait-end reason limit account "$a" result stopped
      echo "limits: a stop ended the wait of account $a"
      return 75
    fi
    now=$(date +%s)
    left=$(( until + margin - now ))
    if [ "$left" -le 0 ]; then
      ho_ledger_append wait-end reason limit account "$a" result reset
      echo "limits: account $a reset; continue"
      return 0
    fi
    [ "$left" -le "$slice" ] || left=$slice
    sleep "$left"
  done
}

ho_limits_usage() {
  cat >&2 <<'USAGE'
usage: harness limits record                 status line command: read the runtime's status line
                                             JSON on stdin and keep the reading of $HO_ACCOUNT
       harness limits <run-dir> check        read every account, record changes in the run
                                             ledger and run the threshold actions
       harness limits <run-dir> status       one line per account and window (unknown is never OK)
       harness limits <run-dir> gate [role]  exit 0 a start may go ahead, 74 spawns are paused
       harness limits <run-dir> wait <account> [--until EPOCH]
                                             wait for a hit limit to reset; 0 continue, 75 a
                                             stop ended the wait
USAGE
}

ho_limits_main() {
  local v rc=0
  [ "${1-}" = record ] && { ho_limits_record; return 0; }
  [ $# -ge 2 ] || { ho_limits_usage; exit 64; }
  ho_run_open "$1"
  case $2 in
    check)
      v=$(ho_limits_eval) || exit $?
      ho_limits_apply "$v"
      ho_limits_status_lines "$v"
      ;;
    status)
      v=$(ho_limits_eval) || exit $?
      ho_limits_status_lines "$v"
      ;;
    gate) ho_limits_gate "${3:-worker}" || rc=$?; exit "$rc" ;;
    wait) shift 2; ho_limits_wait "$@" || rc=$?; exit "$rc" ;;
    *) ho_limits_usage; exit 64 ;;
  esac
}
