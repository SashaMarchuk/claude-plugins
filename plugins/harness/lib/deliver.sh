# shellcheck shell=bash
# Instruction delivery: messages first, terminal typing as a checked fallback.
# H-101 (messages first, typing as the fallback), H-099 (nothing is typed to wake a session;
# typing only onto an empty input line), H-137 (a byte limit for typed text; longer text
# through a file). Design S8-24, D42b, D42f, D42g, D37-LIFECYCLE-4.
#
#   harness session <run-dir> deliver <name> (--text T | --file F) [--id ID] [--force-send]
#   harness session <run-dir> proof <name> <id>
#
# Every instruction carries a short unique id (S8-24): the engine makes one ("ho-" and 8 hex
# digits) unless the caller passes --id. The text that reaches the session starts with
# "<id>: ". The instruction counts as delivered only when the session's transcript records a
# user turn whose own text carries the id, a queued-command record that carries it, or a reply
# of the session that names it. Any other growth of the transcript proves only that the session
# is alive; it never counts as delivery. A tool result never counts, so a session that reads
# the message file does not confirm itself.
#
# Order of a delivery:
#   1. The message route: the runtime data's message.argv, when it names one. Then the proof.
#   2. The typed fallback, only when the session's screen shows the runtime's idle input line,
#      empty, with no busy mark (D42g). The screen is read, never probed with a test key (H-099).
#      Text of at most terminal.typed_max_bytes bytes (default 800, D42f) inside the safe
#      character set is typed as it is; any other text goes into <run>/messages/<id>.txt and a
#      short line that names the file is typed instead (H-137). Then the proof.
#   3. If neither proves delivery, the instruction is reported as not delivered. Nothing is
#      typed a second time.
# With no readable transcript, nothing is sent at all: delivery could not be checked, and an
# unchecked send is what lost instructions in field notes B1 and B2.
#
# --force-send is the one exception of D42g, for the stop message of a hard stop
# (D37-LIFECYCLE-4): the text may be typed while the session is busy. Once the transcript shows
# the instruction queued, the runtime's send-now chord (force_send.bytes in the runtime data,
# so engine code holds no key name) is sent once, to that session's own terminal only, and only
# when the runtime's version is at least force_send.min_version.
#
# Settings: terminal.typed_max_bytes (800, at most 1000), delivery.wait_seconds (30, how long
# each route waits for the proof), delivery.message_timeout_seconds (30, for the message
# command itself).
# Exit codes: 0 delivered, 1 not delivered (the reason is printed and written to the ledger),
# 64 usage, 65 refused, 66 no such session of this run, 78 runtime data missing.
#
# Requires lib/run.sh, lib/config.sh, lib/files.sh, lib/term.sh and lib/sessions.sh.

HO_DELIVER_MAX_TEXT=65536

ho_deliver_usage() {
  cat >&2 <<'USAGE'
usage: harness session <run-dir> deliver <name> (--text T | --file F) [--id ID] [--force-send]
       harness session <run-dir> proof <name> <id>
USAGE
}

ho_deliver_new_id() {
  printf 'ho-%s\n' "$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
}

ho_deliver_id_ok() {
  printf '%s' "${1-}" | grep -Eq '^[a-z][a-z0-9-]{5,39}$' || {
    printf 'harness: instruction id %s must be 6-40 characters of a-z 0-9 - and start with a letter\n' "${1-}" >&2
    return 65
  }
}

ho_deliver_bytes() { printf '%s' "$1" | LC_ALL=C wc -c | tr -d ' '; }

# ho_deliver_record <name>: the record of a running session of this run, with a live process.
ho_deliver_record() {
  local name=$1 rec owner
  ho_session_name_ok "$name" || return 65
  rec="$HO_RUN_DIR/sessions/$name.json"
  [ -f "$rec" ] || { printf 'harness: no session %s in run %s\n' "$name" "$HO_RUN_ID" >&2; return 66; }
  owner=$(jq -r 'if type == "object" then (.run // "") else "" end' "$rec" 2>/dev/null || echo "")
  [ "$owner" = "$HO_RUN_ID" ] || { printf 'harness: session %s is recorded under run %s, not %s\n' "$name" "${owner:-unreadable}" "$HO_RUN_ID" >&2; return 66; }
  printf '%s\n' "$rec"
}

ho_deliver_profile() {
  local name f
  name=$(jq -r '.runtime // ""' "$1")
  case $name in '' | *[!a-z0-9-]*) printf 'harness: the record names no usable runtime: %s\n' "$name" >&2; return 78 ;; esac
  f="$HO_ROOT/runtimes/$name.json"
  [ -f "$f" ] && jq -e '(.transcript.glob | type == "string") and (.screen.prompt_prefixes | type == "array")' "$f" >/dev/null 2>&1 || {
    printf 'harness: runtime file %s has no transcript or screen data for delivery\n' "$f" >&2
    return 78
  }
  printf '%s\n' "$f"
}

# ho_deliver_transcript <record> <profile>: the session's transcript file, found by its session
# ID under the runtime's config root: the root the session's account sets, else the engine's
# own, else the default under HOME. The path is kept in the record once found.
ho_deliver_transcript() {
  local rec=$1 profile=$2 sid cached glob renv root roots acct out f tab
  cached=$(jq -r '.transcript // ""' "$rec")
  [ -n "$cached" ] && [ -f "$cached" ] && { printf '%s\n' "$cached"; return 0; }
  sid=$(jq -r '.session_id // ""' "$rec")
  ho_session_uuid_ok "$sid" 2>/dev/null || return 1
  glob=$(jq -r '.transcript.glob' "$profile")
  glob=${glob//\{session_id\}/$sid}
  renv=$(jq -r '.transcript.root_env // ""' "$profile")
  roots=""
  acct=$(jq -r '.account // ""' "$rec")
  if [ -n "$acct" ] && [ -n "$renv" ]; then
    tab=$(printf '\t')
    out=$(ho_session_account "$(jq -r '.role // ""' "$rec")" "$acct" 2>/dev/null) || out=""
    if [ -n "$out" ]; then
      out=$(/bin/bash -c "${out#*"$tab"}" 2>/dev/null | ho_account_env_parse 2>/dev/null | awk -F '\t' -v k="$renv" '$1 == k { v = $2 } END { print v }') || out=""
      [ -z "$out" ] || roots="$out"
    fi
  fi
  if [ -n "$renv" ] && [ -n "$(printenv "$renv" 2>/dev/null)" ]; then
    roots="$roots
$(printenv "$renv")"
  fi
  roots="$roots
$HOME/$(jq -r '.transcript.default_root // ".claude"' "$profile")"
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    for f in "$root"/$glob; do
      [ -f "$f" ] || continue
      ho_session_set "$rec" '.transcript = $t' --arg t "$f" >/dev/null 2>&1 || true
      printf '%s\n' "$f"
      return 0
    done
  done <<EOF_ROOTS
$roots
EOF_ROOTS
  return 1
}

ho_deliver_size() { wc -c < "$1" 2>/dev/null | tr -d ' '; }

# ho_deliver_scan <profile> <transcript> <offset> <id>: what the transcript recorded for the id
# after byte <offset>: "delivered user-turn", "delivered queued-command", "delivered reply",
# "queued", or "none". Lines that are not JSON objects are skipped. The id matches only as a
# whole word: "stop-1" is not found inside "stop-10". Ids use a-z 0-9 - only, so the id is
# safe inside the pattern.
ho_deliver_scan() {
  local profile=$1 tr=$2 off=$3 id=$4 out
  out=$(tail -c +"$((off + 1))" "$tr" 2>/dev/null | jq -R -r --arg id "$id" --slurpfile p "$profile" '
    ($p[0].transcript) as $t
    | def texts: if type == "string" then [.]
        elif type == "array" then [.[] | select(type == "object" and .type == "text") | .text | strings]
        else [] end;
      def has_id: any(.[]; test("(^|[^a-z0-9-])" + $id + "($|[^a-z0-9-])"));
    fromjson? | select(type == "object")
    | (.type // "") as $ty
    | if ($t.user_types // [] | any(. == $ty)) and ((.message.content // "") | texts | has_id) then "delivered user-turn"
      elif $ty == "attachment" and (((.attachment.type // "") as $a | $t.delivered_attachments // [] | any(. == $a)))
        and ((.attachment.humanTurn // .humanTurn // false) == true) and ([.attachment | .. | strings] | has_id) then "delivered queued-command"
      elif ($t.reply_types // [] | any(. == $ty)) and ((.message.content // "") | texts | has_id) then "delivered reply"
      elif $ty == ($t.queue_type // "") and (.operation // "") == ($t.queue_enqueue // "") and ([.. | strings] | has_id) then "queued"
      else empty end' 2>/dev/null) || out=""
  case $out in
    *delivered*) printf '%s\n' "$out" | grep -m 1 '^delivered' ;;
    *queued*) echo queued ;;
    *) echo none ;;
  esac
}

# ho_deliver_screen <record> <profile>: read the session's screen and print one word and a
# reason: "empty", "draft <text>", "busy <mark>" or "unknown <why>". Only "empty" lets the typed
# fallback run (D42g). Dim text after the prompt, in the runtime's suggestion style, is
# suggested text and counts as empty (H-099). A backend that keeps no colours (iTerm2) cannot
# tell suggested text from typed text, so any text there counts as a draft.
ho_deliver_screen() {
  local rec=$1 profile=$2 cap plain esc rc sgr k i n line prev next raw text mark p pfx="" prefixes marks
  esc=$(printf '\033')
  cap=$(HO_TERM_BACKEND=$(jq -r '.backend // ""' "$rec") ho_term_capture "$(jq -r '.handle // ""' "$rec")" \
    "$(jq -r '.term_tag // ""' "$rec")" "$(jq -r '.session_id // ""' "$rec")" 60 styled 2>/dev/null) || { echo "unknown the screen could not be read"; return 0; }
  plain=$(printf '%s\n' "$cap" | sed "s/$esc\[[0-9;]*m//g")
  rc=$(jq -r '.screen.rule_char // ""' "$profile")
  sgr=$(jq -r '.screen.suggestion_sgr // ""' "$profile")
  case $sgr in *[!0-9]*) sgr="" ;; esac
  prefixes=$(jq -r '.screen.prompt_prefixes[] | strings' "$profile")
  marks=$(jq -r '.screen.busy_marks[]? | strings' "$profile")
  # The input line: the last line that starts with a prompt prefix and sits between two rule
  # lines. Without it the screen shows a dialog, a notice or something unknown.
  local -a P R
  n=0
  while IFS= read -r line; do P[n]=$line; n=$((n + 1)); done <<EOF_P
$plain
EOF_P
  i=0
  while IFS= read -r line; do R[i]=$line; i=$((i + 1)); done <<EOF_R
$cap
EOF_R
  k=-1
  i=1
  while [ "$i" -lt $((n - 1)) ]; do
    line=${P[i]}
    prev=${P[i - 1]}
    next=${P[i + 1]}
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      case $line in
        "$p"* | "${p% }")
          if ho_deliver_rule "$prev" "$rc" && ho_deliver_rule "$next" "$rc"; then k=$i; pfx=$p; fi
          ;;
      esac
    done <<EOF_PFX
$prefixes
EOF_PFX
    i=$((i + 1))
  done
  if [ "$k" -lt 0 ]; then
    printf 'unknown no idle input line of the runtime is shown (a dialog, a notice or an unknown screen); last lines: %s\n' \
      "$(printf '%s\n' "$plain" | grep -v '^[[:space:]]*$' | tail -n 3 | sed 's/^[[:space:]]*//' | tr '\n' '|' | sed 's/|$//' | cut -c1-200)"
    return 0
  fi
  i=0
  while [ "$i" -lt "$k" ]; do
    while IFS= read -r mark; do
      [ -n "$mark" ] || continue
      case ${P[i]} in *"$mark"*) echo "busy $mark"; return 0 ;; esac
    done <<EOF_BUSY
$marks
EOF_BUSY
    i=$((i + 1))
  done
  raw=${R[k]-}
  [ -z "$sgr" ] || raw=$(printf '%s\n' "$raw" | sed -E "s/$esc\[${sgr}m[^$esc]*($esc\[(0|22)?m|\$)//g")
  text=$(printf '%s\n' "$raw" | sed "s/$esc\[[0-9;]*m//g")
  case $text in "$pfx"*) text=${text#"$pfx"} ;; *) text=${text#"${pfx% }"} ;; esac
  text=$(printf '%s' "$text" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  if [ -n "$text" ]; then
    echo "draft $text"
  else
    echo "empty"
  fi
}

# ho_deliver_rule <line> <rule-char>: 0 when the line is only rule characters (at least three)
# and spaces.
ho_deliver_rule() {
  local l=$1 c=$2 t
  [ -n "$c" ] || return 1
  case $l in *"$c$c$c"*) ;; *) return 1 ;; esac
  t=${l//"$c"/}
  t=$(printf '%s' "$t" | tr -d ' \t')
  [ -z "$t" ]
}

# ho_deliver_version_ge <have> <want>: 0 when the dotted version <have> is at least <want>.
ho_deliver_version_ge() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, ".")
    n = (na > nb) ? na : nb
    for (i = 1; i <= n; i++) { p = x[i] + 0; q = y[i] + 0; if (p > q) exit 0; if (p < q) exit 1 }
    exit 0 }'
}

# ho_deliver_chord <record> <profile> <id>: send the runtime's send-now chord once (D37-LIFECYCLE-4).
ho_deliver_chord() {
  local rec=$1 profile=$2 id=$3 bytes want cmd have rc=0
  # Once per instruction, across both routes: the marker is taken before anything is sent.
  (set -C; : > "$HO_RUN_DIR/messages/$id.chord") 2>/dev/null || return 1
  bytes=$(jq -r '.force_send.bytes // [] | map(tostring) | join(" ")' "$profile")
  want=$(jq -r '.force_send.min_version // ""' "$profile")
  [ -n "$bytes" ] && [ -n "$want" ] || { ho_ledger_append deliver-force-send id "$id" result skipped reason "the runtime data names no send-now chord"; return 1; }
  cmd=$(command -v "$(jq -r '.command // ""' "$profile")" 2>/dev/null || true)
  have=""
  [ -z "$cmd" ] || have=$("$cmd" --version 2>/dev/null | awk 'NR == 1 { print $1 }')
  case $have in '' | *[!0-9.]*) have="" ;; esac
  if [ -z "$have" ] || ! ho_deliver_version_ge "$have" "$want"; then
    ho_ledger_append deliver-force-send id "$id" result skipped reason "runtime version ${have:-unknown} is below $want"
    return 1
  fi
  # shellcheck disable=SC2086
  HO_TERM_BACKEND=$(jq -r '.backend // ""' "$rec") ho_term_bytes "$(jq -r '.handle // ""' "$rec")" \
    "$(jq -r '.term_tag // ""' "$rec")" "$(jq -r '.session_id // ""' "$rec")" $bytes || rc=$?
  ho_ledger_append deliver-force-send id "$id" result "$([ "$rc" -eq 0 ] && echo sent || echo "failed (exit $rc)")"
  [ "$rc" -eq 0 ]
}

# ho_deliver_wait <record> <profile> <transcript> <offset> <id> <force>: wait for the proof.
# Prints the scan result. With force, a queued instruction gets the chord, once per id.
ho_deliver_wait() {
  local rec=$1 profile=$2 tr=$3 off=$4 id=$5 force=$6 st deadline chord=0
  deadline=$(( $(date +%s) + $(ho_cfg_int '.delivery.wait_seconds' 30) ))
  while :; do
    st=$(ho_deliver_scan "$profile" "$tr" "$off" "$id")
    case $st in delivered*) break ;; esac
    if [ "$st" = queued ] && [ "$force" = 1 ] && [ "$chord" -eq 0 ] && [ ! -e "$HO_RUN_DIR/messages/$id.chord" ]; then
      chord=1
      ho_deliver_chord "$rec" "$profile" "$id" || true
    fi
    [ "$(date +%s)" -lt "$deadline" ] || break
    sleep 0.2
  done
  printf '%s\n' "$st"
}

# ho_deliver_message <profile> <record> <id> <file>: run the runtime's message command, if
# any. 0 sent, 1 failed, 2 no route.
ho_deliver_message() {
  local profile=$1 rec=$2 id=$3 file=$4 sid el pid deadline rc=0
  local -a argv
  jq -e '.message.argv | type == "array" and length > 0 and all(type == "string")' "$profile" >/dev/null 2>&1 || return 2
  sid=$(jq -r '.session_id' "$rec")
  argv=()
  while IFS= read -r el; do
    el=${el//\{session_id\}/$sid}
    el=${el//\{instruction_id\}/$id}
    el=${el//\{text_file\}/$file}
    argv+=("$el")
  done <<EOF_ARGV
$(jq -r '.message.argv[]' "$profile")
EOF_ARGV
  "${argv[@]}" < /dev/null > /dev/null 2>> "$HO_RUN_DIR/logs/deliver.log" &
  pid=$!
  deadline=$(( $(date +%s) + $(ho_cfg_int '.delivery.message_timeout_seconds' 30) ))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 0.1
  done
  wait "$pid" || rc=$?
  [ "$rc" -eq 0 ] || return 1
}

# ho_deliver_typed_line <id> <text> <file>: the line to type. The text itself when it is one
# line of safe characters within the byte limit, else a short line that names the file.
ho_deliver_typed_line() {
  local id=$1 text=$2 file=$3 max line
  max=$(ho_cfg_int '.terminal.typed_max_bytes' 800)
  [ "$max" -le 1000 ] || max=1000
  line="$id: $text"
  if [ "$(ho_deliver_bytes "$line")" -le "$max" ] && ho_term_text_ok "$line" 2>/dev/null; then
    printf 'direct\t%s\n' "$line"
    return 0
  fi
  line="$id: read the file $file and follow the instruction in it"
  if [ "$(ho_deliver_bytes "$line")" -le "$max" ] && ho_term_text_ok "$line" 2>/dev/null; then
    printf 'file\t%s\n' "$line"
    return 0
  fi
  return 1
}

ho_deliver_not() {
  local id=$1 name=$2 reason=$3
  shift 3
  ho_ledger_append deliver-failed id "$id" name "$name" reason "$reason" "$@"
  printf 'NOT-DELIVERED id=%s session=%s: %s\n' "$id" "$name" "$reason"
  return 1
}

ho_session_deliver() {
  local name="" text="" file="" id="" force=0 have_text=0
  name=${1-}
  [ -n "$name" ] && shift || { ho_deliver_usage; return 64; }
  while [ $# -gt 0 ]; do
    case $1 in
      --text) [ $# -ge 2 ] || { ho_deliver_usage; return 64; }; text=$2; have_text=1; shift 2 ;;
      --file) [ $# -ge 2 ] || { ho_deliver_usage; return 64; }; file=$2; shift 2 ;;
      --id) [ $# -ge 2 ] || { ho_deliver_usage; return 64; }; id=$2; shift 2 ;;
      --force-send) force=1; shift ;;
      *) printf 'harness: unknown deliver argument %s\n' "$1" >&2; ho_deliver_usage; return 64 ;;
    esac
  done
  if [ -n "$file" ]; then
    [ "$have_text" -eq 0 ] || { echo "harness: give --text or --file, not both" >&2; return 64; }
    [ -f "$file" ] && [ -r "$file" ] || { printf 'harness: cannot read %s\n' "$file" >&2; return 65; }
    text=$(cat "$file") || return 65
  fi
  [ -n "$text" ] || { echo "harness: the instruction text is empty" >&2; return 64; }
  [ "$(ho_deliver_bytes "$text")" -le "$HO_DELIVER_MAX_TEXT" ] || { printf 'harness: the instruction is longer than %s bytes\n' "$HO_DELIVER_MAX_TEXT" >&2; return 65; }
  if [ -n "$id" ]; then ho_deliver_id_ok "$id" || return 65; else id=$(ho_deliver_new_id); fi
  local rec profile tr off msg st rc pid screen
  rec=$(ho_deliver_record "$name") || return $?
  profile=$(ho_deliver_profile "$rec") || return $?
  [ "$(jq -r '.status // ""' "$rec")" = running ] || { printf 'harness: session %s is not running\n' "$name" >&2; return 65; }
  pid=$(ho_session_live_pid "$rec") || return 1
  [ -n "$pid" ] || ho_deliver_not "$id" "$name" "the session's process is gone" || return 1
  mkdir -p "$HO_RUN_DIR/messages" "$HO_RUN_DIR/logs"
  msg="$HO_RUN_DIR/messages/$id.txt"
  # One id, one instruction: an id that was used before is refused, so a proof always points
  # at exactly one instruction.
  (set -C; printf '%s: %s\n' "$id" "$text" > "$msg") 2>/dev/null || { printf 'harness: instruction id %s was used before in this run\n' "$id" >&2; return 65; }
  tr=$(ho_deliver_transcript "$rec" "$profile") || tr=""
  [ -n "$tr" ] || ho_deliver_not "$id" "$name" "no transcript of the session to check delivery against; nothing was sent" || return 1
  off=$(ho_deliver_size "$tr")
  ho_ledger_append deliver-request id "$id" name "$name" bytes "$(ho_deliver_bytes "$text")" force_send "$force"

  # ---- 1. the message route ----
  rc=0
  ho_deliver_message "$profile" "$rec" "$id" "$msg" || rc=$?
  case $rc in
    0)
      ho_ledger_append deliver-message id "$id" result sent
      st=$(ho_deliver_wait "$rec" "$profile" "$tr" "$off" "$id" "$force")
      case $st in
        delivered*)
          ho_ledger_append deliver-confirmed id "$id" name "$name" route message proof "${st#delivered }"
          printf 'DELIVERED id=%s session=%s route=message proof=%s\n' "$id" "$name" "${st#delivered }"
          return 0
          ;;
      esac
      ho_ledger_append deliver-message id "$id" result unconfirmed transcript_grew "$([ "$(ho_deliver_size "$tr")" -gt "$off" ] && echo yes || echo no)" state "$st"
      ;;
    2) ho_ledger_append deliver-message id "$id" result "no message route in the runtime data" ;;
    *) ho_ledger_append deliver-message id "$id" result failed ;;
  esac

  # ---- 2. the typed fallback (D42g, H-099, H-137) ----
  screen=$(ho_deliver_screen "$rec" "$profile")
  case $screen in
    empty) ;;
    busy*)
      [ "$force" -eq 1 ] || ho_deliver_not "$id" "$name" "the session is busy; nothing was typed, the instruction waits" screen "$screen" || return 1
      ;;
    draft*) ho_deliver_not "$id" "$name" "the input line holds text typed by the user; nothing was typed" screen draft || return 1 ;;
    *) ho_deliver_not "$id" "$name" "nothing was typed; ${screen#unknown }" screen unknown || return 1 ;;
  esac
  local typed mode line
  typed=$(ho_deliver_typed_line "$id" "$text" "$msg") || ho_deliver_not "$id" "$name" "the message file path cannot be typed; nothing was typed" || return 1
  mode=${typed%%"$(printf '\t')"*}
  line=${typed#*"$(printf '\t')"}
  rc=0
  HO_TERM_BACKEND=$(jq -r '.backend // ""' "$rec") ho_term_send "$(jq -r '.handle // ""' "$rec")" \
    "$(jq -r '.term_tag // ""' "$rec")" "$(jq -r '.session_id' "$rec")" "$line" 2>/dev/null || rc=$?
  [ "$rc" -eq 0 ] || ho_deliver_not "$id" "$name" "the terminal refused the typed line (exit $rc)" || return 1
  ho_ledger_append deliver-typed id "$id" name "$name" mode "$mode" bytes "$(ho_deliver_bytes "$line")"
  st=$(ho_deliver_wait "$rec" "$profile" "$tr" "$off" "$id" "$force")
  case $st in
    delivered*)
      ho_ledger_append deliver-confirmed id "$id" name "$name" route typed proof "${st#delivered }"
      printf 'DELIVERED id=%s session=%s route=typed proof=%s\n' "$id" "$name" "${st#delivered }"
      return 0
      ;;
  esac
  [ "$st" != queued ] || ho_deliver_not "$id" "$name" "the session queued the instruction and has not taken it yet; check again with proof, do not send it again" state "$st" || return 1
  ho_deliver_not "$id" "$name" "no transcript entry carries the instruction id" state "$st" \
    transcript_grew "$([ "$(ho_deliver_size "$tr")" -gt "$off" ] && echo yes || echo no)"
}

# proof <name> <id>: the S8-24 check alone, for an instruction the caller sent itself (for
# example with the runtime's own message tool). Exit 0 only when delivered.
ho_session_proof() {
  local name=${1-} id=${2-} rec profile tr st
  [ -n "$name" ] && [ -n "$id" ] || { ho_deliver_usage; return 64; }
  ho_deliver_id_ok "$id" || return 65
  rec=$(ho_deliver_record "$name") || return $?
  profile=$(ho_deliver_profile "$rec") || return $?
  tr=$(ho_deliver_transcript "$rec" "$profile") || { printf 'harness: no transcript of session %s\n' "$name" >&2; return 1; }
  st=$(ho_deliver_scan "$profile" "$tr" 0 "$id")
  printf '%s id=%s session=%s\n' "$st" "$id" "$name"
  case $st in delivered*) return 0 ;; esac
  return 1
}
