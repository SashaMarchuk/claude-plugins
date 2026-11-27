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
#      A message whose outcome is unknown is never typed; a proven failure falls back to
#      typing (H-101). See the route block in ho_session_deliver.
#   2. The typed fallback, only when the session's screen shows the runtime's idle input line,
#      empty, with no busy mark (D42g). The screen is read, never probed with a test key (H-099).
#      Text of at most terminal.typed_max_bytes bytes (default 800, D42f) inside the safe
#      character set is typed as it is; any other text goes into <run>/messages/<id>.txt and a
#      short line that names the file is typed instead (H-137). Then the proof.
#   3. If neither proves delivery, the instruction is reported as not delivered. The engine
#      types an id at most once and never retries by itself.
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
# command itself), delivery.message_kill_grace_seconds (2, between SIGTERM and SIGKILL of a
# stopped message command), terminal.enter_delay_seconds (2, 0 to 10; anything else exits 78).
# Exit codes: 0 delivered, 1 not delivered (the reason is printed and written to the ledger),
# 64 usage, 65 refused, 66 no such session of this run, 78 runtime data missing or a setting
# out of range.
#
# Requires lib/run.sh, lib/config.sh, lib/files.sh, lib/term.sh, lib/sessions.sh, lib/screen.sh and
# lib/runtime.sh.

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

# The id is checked as one whole value by case patterns, never line by line: a newline or any
# other byte outside the set fails (validator B1). The set is spelled out, so no locale can widen
# a range.
ho_deliver_id_ok() {
  local v=${1-}
  case $v in
    [abcdefghijklmnopqrstuvwxyz]*) ;;
    *) v="" ;;
  esac
  case $v in *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) v="" ;; esac
  if [ -z "$v" ] || [ "${#v}" -lt 6 ] || [ "${#v}" -gt 40 ]; then
    echo "harness: an instruction id must be 6-40 characters of a-z 0-9 - and start with a letter" >&2
    return 65
  fi
}

ho_deliver_bytes() { printf '%s' "$1" | LC_ALL=C wc -c | tr -d ' '; }

# ho_deliver_outside_project <folder>: 0 when the folder (resolved) is not the project, its
# worktrees folder or a worktree, nor inside one. The same identity check the launch uses for
# the runtime binary.
ho_deliver_outside_project() {
  ho_session_runtime_path_ok "$1/ho-probe" 2>/dev/null
}

# ho_deliver_not_above_project <folder>: 0 when the folder holds neither the project, its
# worktrees folder nor a worktree. A transcript folder above the project would let a glob or a
# cached path reach a transcript planted inside it (PR #118 validator, minors 1 and 2).
# Folders are compared by identity (-ef), walking up from each project folder.
ho_deliver_not_above_project() {
  local d roots r a
  d=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  roots=$(ho_session_project_roots 2>/dev/null) || return 1
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    a=$r
    while :; do
      [ ! "$a" -ef "$d" ] || return 1
      [ "$a" != / ] || break
      a=$(dirname "$a")
    done
  done <<EOF_ROOTS
$roots
EOF_ROOTS
  return 0
}

# ho_deliver_exec_path <program>: the PATH for a program that delivery runs (the version check
# and the message command): the fixed system folders and the program's own folder, never a
# folder of the project or a worktree, and never the caller's PATH. So a "#!/usr/bin/env bash"
# line cannot pick up an interpreter planted in a project folder (PR #95 review). The
# launch's own PATH is a separate matter (issue #91).
ho_deliver_exec_path() {
  local d p=/usr/bin:/bin:/usr/sbin:/sbin
  d=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || d=""
  case $d in '' | *:* | *"
"*) ;; *) ho_deliver_outside_project "$d" && p="$p:$d" ;; esac
  printf '%s\n' "$p"
}

# ho_deliver_setting <jq-path> <default> <min> <max>: a delivery safety setting. It is read
# from the user config only: a project config that sets it is refused (65), as with
# session.permissions, because a repository must not be able to loosen how delivery decides.
# The value must be a JSON number, a whole number from <min> to <max>; anything else exits 78.
# The settings (PR #95 review, round 7): delivery.wait_seconds (30, 2-3600),
# delivery.message_timeout_seconds (30, 1-600), delivery.message_kill_grace_seconds (2, 0-30),
# terminal.typed_max_bytes (800, 300-1000; 300 leaves room for the pointer line to the file).
ho_deliver_setting() {
  local path=$1 def=$2 min=$3 max=$4 v
  # Presence counts, not truthiness: false or 0 in the project config is refused too.
  v=$(jq -r --arg p "$path" 'if type == "object" then (try getpath($p | ltrimstr(".") | split(".")) catch null) else null end
    | if . == null then "" else "set" end' "$HO_PROJECT_DIR/.harness/config.json" 2>/dev/null) || v=set
  if [ -n "$v" ]; then
    printf 'harness: the project config sets %s; it is a delivery safety setting and belongs in the user config %s\n' "${path#.}" "$(ho_user_config)" >&2
    return 65
  fi
  v=$(ho_cfg_user "$path" | jq -r --arg d "$def" 'if . == null then $d elif type == "number" then tostring else "x" end') || return 78
  case $v in '' | *[!0-9]*) v=x ;; esac
  if [ "$v" = x ] || [ "${#v}" -gt 5 ] || [ "$((10#$v))" -lt "$min" ] || [ "$((10#$v))" -gt "$max" ]; then
    printf 'harness: %s must be a JSON number, a whole number from %s to %s\n' "${path#.}" "$min" "$max" >&2
    return 78
  fi
  printf '%s\n' "$((10#$v))"
}

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
  # The same lookup as the launch (the user's runtimes folder, then the shipped one).
  f=$(ho_rt_file "$name" 2>/dev/null) || f=""
  [ -n "$f" ] && [ -f "$f" ] && jq -e '(.transcript.glob | type == "string") and (.screen.prompt_prefixes | type == "array")' "$f" >/dev/null 2>&1 || {
    printf 'harness: runtime file %s has no transcript or screen data for delivery\n' "$f" >&2
    return 78
  }
  printf '%s\n' "$f"
}

# ho_deliver_transcript <record> <profile>: the session's transcript file, found by its session
# ID under the config folder the launch recorded (transcript_root). Delivery never runs the
# account command (PR #95 review). The recorded folder is checked again as the launch
# made it: an absolute path with no line break, and a folder. The file found must be a regular,
# readable file inside it. The path is kept in the record once found.
ho_deliver_transcript() {
  local rec=$1 profile=$2 sid cached glob root f fdir
  root=$(jq -r '.transcript_root // ""' "$rec")
  case $root in /*) ;; *) return 1 ;; esac
  case $root in *"
"*) return 1 ;; esac
  [ -d "$root" ] || return 1
  # A folder of the project or a worktree is never a transcript folder: a record there could
  # be planted (validator, PR #95).
  ho_deliver_outside_project "$root" || return 1
  ho_deliver_not_above_project "$root" || return 1
  sid=$(jq -r '.session_id // ""' "$rec")
  ho_session_uuid_ok "$sid" 2>/dev/null || return 1
  # The cached path is resolved first (".." segments and links of its folders), then it counts
  # only inside the resolved root (or the checked data folder below) and only when its file name is <id>.jsonl or a folder on its
  # path is <id>, so it cannot point at another session's transcript (PR #95 review).
  local rroot cdir pre want base rest
  rroot=$(cd "$root" 2>/dev/null && pwd -P) || return 1
  # The runtime's data folder (the glob's fixed leading part) may be a link, as in a
  # multi-account layout, but only to the real folder the launch recorded
  # (transcript_prefix_real). It must still resolve there now and lie outside the project. The
  # glob then runs from that real folder, and no folder below it may be a link. A record
  # without the field gets no link at all. The rest of the glob is never a link either.
  glob=$(jq -r '.transcript.glob' "$profile")
  base=$root rest=$glob
  pre=$(ho_live_transcript_prefix "$glob")
  want=$(jq -r '.transcript_prefix_real // ""' "$rec")
  if [ -n "$pre" ] && [ -n "$want" ]; then
    case $want in /*) ;; *) return 1 ;; esac
    base=$(cd "$root/$pre" 2>/dev/null && pwd -P) || return 1
    [ "$base" = "$want" ] || return 1
    ho_deliver_outside_project "$base" || return 1
    ho_deliver_not_above_project "$base" || return 1
    rest=${glob#"$pre"/}
  fi
  cached=$(jq -r '.transcript // ""' "$rec")
  case $cached in
    /*)
      cdir=$(cd "$(dirname "$cached")" 2>/dev/null && pwd -P) || cdir=""
      # The cached file's own folder is never inside the project or a worktree.
      [ -n "$cdir" ] && ho_deliver_outside_project "$cdir" && cached="$cdir/$(basename "$cached")" || cached=""
      ;;
    *) cached="" ;;
  esac
  local cbase=$base
  [ "$cbase" != "$root" ] || cbase=$rroot
  case $cached in
    "$cbase"/*)
      # Whole name parts only: the file is <id>.jsonl, or a folder on the way is <id>.
      if [ "$(basename "$cached")" = "$sid.jsonl" ] || case "/$(dirname "$cached")/" in */"$sid"/*) true ;; *) false ;; esac; then
        [ -f "$cached" ] && [ ! -L "$cached" ] && [ -r "$cached" ] && { printf '%s\n' "$cached"; return 0; }
      fi
      ;;
  esac
  rest=${rest//\{session_id\}/$sid}
  for f in "$base"/$rest; do
    [ -f "$f" ] && [ ! -L "$f" ] && [ -r "$f" ] || continue
    # No folder below the base may be a link: a linked folder could lead to a planted
    # transcript (PR #95 review). The base itself was checked above.
    ho_deliver_no_link_below "$base" "$f" || continue
    # Nor is the found file's own folder inside the project or a worktree.
    fdir=$(cd "$(dirname "$f")" 2>/dev/null && pwd -P) || continue
    ho_deliver_outside_project "$fdir" || continue
    ho_session_set "$rec" '.transcript = $t' --arg t "$f" >/dev/null 2>&1 || true
    printf '%s\n' "$f"
    return 0
  done
  return 1
}

# ho_deliver_no_link_below <root> <path>: 0 when no folder between <root> and <path> is a link.
ho_deliver_no_link_below() {
  local p=$1 rest=${2#"$1"/} part
  [ "$rest" != "$2" ] || return 1
  while :; do
    case $rest in */*) ;; *) return 0 ;; esac
    part=${rest%%/*}
    rest=${rest#*/}
    p="$p/$part"
    [ ! -L "$p" ] || return 1
  done
}

ho_deliver_size() { { wc -c < "$1"; } 2>/dev/null | tr -d ' '; }

# ho_deliver_grew <transcript> <offset>: yes, no, or unreadable.
ho_deliver_grew() {
  local n
  n=$(ho_deliver_size "$1")
  case $n in '' | *[!0-9]*) echo unreadable ;; *) [ "$n" -gt "$2" ] && echo yes || echo no ;; esac
}

# ho_deliver_scan <profile> <transcript> <offset> <id>: what the transcript recorded for the id
# after byte <offset>: "delivered user-turn", "delivered queued-command", "delivered reply",
# "queued", "dequeued" (it left the queue and was not taken), or "none".
# The id is matched as a literal string (jq split), never as a pattern built from input
# (validator B2), and only as a whole word: no letter of either case, digit, "_", "." or "-"
# may touch it, and no character outside ASCII either (minor 1), so "stop-1" is not found in
# "stop-10" or "stop-1.txt". An id glued to another copy of itself is no whole word (minor 2). The character on each
# side is taken out and tested alone, with no line anchor: "$" in a pattern also matches
# before a final line break, which hid an id at the start of a second line (validator F2). Not counted: lines that
# are not JSON objects, tool results, and user records marked isMeta, isCompactSummary or
# isSidechain (a sidechain record of any type). Each record is judged alone, so one odd record
# hides no other.
ho_deliver_scan() {
  local profile=$1 tr=$2 off=$3 id=$4 out
  out=$(tail -c +"$((off + 1))" "$tr" 2>/dev/null | jq -R -r --arg id "$id" --slurpfile p "$profile" '
    ($p[0].transcript) as $t
    | def texts: if type == "string" then [.]
        elif type == "array" then [.[] | select(type == "object" and .type == "text") | .text | strings]
        else [] end;
      def wordch: length > 0 and (test("[A-Za-z0-9_.-]") or (explode[0] >= 128));
      def word($s): ($s | split($id)) as $q | ($q | length) as $n
        | any(range(0; $n - 1); . as $i
            | ($q[$i][-1:] | wordch | not) and ($q[$i + 1][0:1] | wordch | not)
            and ($i == 0 or $q[$i] != "") and ($i + 1 == $n - 1 or $q[$i + 1] != ""));
      def has_id: any(.[]; word(.));
      def content: if (.message | type) == "object" then (.message.content // "") else "" end;
    fromjson? | select(type == "object") | select((.isSidechain // false) != true)
    | try (
      (.type // "") as $ty
      | if ($t.user_types // [] | any(. == $ty)) and (.isMeta // false) != true and (.isCompactSummary // false) != true
          and (content | texts | has_id) then "delivered user-turn"
        elif $ty == "attachment" and (((.attachment.type // "") as $a | $t.delivered_attachments // [] | any(. == $a)))
          and ((.attachment.humanTurn // .humanTurn // false) == true) and ([.attachment | .. | strings] | has_id) then "delivered queued-command"
        elif ($t.reply_types // [] | any(. == $ty)) and (content | texts | has_id) then "delivered reply"
        elif $ty == ($t.queue_type // "") and (.operation // "") == ($t.queue_enqueue // "") and ([.. | strings] | has_id) then "queued"
        elif $ty == ($t.queue_type // "") and (.operation // "") == ($t.queue_remove // "") and ([.. | strings] | has_id) then "dequeued"
        else empty end) catch empty' 2>/dev/null) || out=""
  case $out in
    *delivered*) printf '%s\n' "$out" | grep -m 1 '^delivered' ;;
    *dequeued*) echo dequeued ;;
    *queued*) echo queued ;;
    *) echo none ;;
  esac
}

# ho_deliver_screen <record> <profile>: read the session's screen and print one word and a
# reason: "empty", "draft <text>", "busy <mark>", "hold <class>" or "unknown <why>". Only "empty"
# (and "busy" for --force-send) lets the typed fallback or the chord run (D42g). The rule is
# fail-closed (PR #95 review, round 7):
#   - Every CSI escape code is stripped first (any parameters, ";" or ":" forms, any final
#     byte); a capture that still holds an escape byte reads as unknown.
#   - The same capture goes to the engine's screen reader (lib/screen.sh), with the pattern
#     file of the session's own runtime. A limit notice, a trust dialog or a password prompt is
#     a hold. If the reader cannot run, the screen reads as unknown.
#   - The input line is a line that starts with a prompt prefix right below a rule line. More
#     than one such line reads as a draft.
#   - The box ends at the LAST line of the whole capture below the input line that equals the
#     opening frame line (the rule line right above the input line) byte for byte, with no line
#     cap. A rule line of another width or character is the person's text. With no equal line
#     the box is not closed and reads as a draft (round 8, B6).
#   - A session launched with a name shows it at the right end of the top rule. That rule
#     opens the box only when the name is the session's own launch name from its record
#     (ho_screen_named_rule); it then stands for the plain rule of the same width, which the
#     closing line must equal. Another name, or a named closing line, is no frame.
#   - The lines above the opening frame are read by the screen reader once more, so a hold
#     above a box that already holds typed text is still a hold (the check before Enter).
#   - The box is empty only if the input line holds no text (dim suggested text in the
#     runtime's suggestion style aside) and every other line inside the box is blank. Any other
#     text inside the box, a rule line included, is the person's text: a draft.
#   - A backend that keeps no colours (iTerm2) cannot tell suggested text from typed text, so
#     any text after the prompt there is a draft.
#   - A busy mark counts above the box and in the runtime's status area under it (issue #104).
#     On a narrow pane the status line is cut short with the profile's cut_mark: a cut part
#     after the last status_separator that is the start of a busy mark counts as that mark.
#   - Every line under the box must be the runtime's status area (ho_screen_status_area): any
#     other line there, a dialog or a notice say, reads as unknown (PR #105 review, M1). A styled capture also shows a busy
#     session by the colour of its prompt (busy_prompt_sgr in the profile), at any width.
#   - Idle is proven, never read from a missing busy mark (PR #105 review round 1): the screen
#     is empty only when the prompt shows the runtime's idle colour (idle_prompt_sgr in the
#     profile). A prompt line with no colour code at all (a plain capture, as iTerm2 gives) or
#     with any other colour reads as unknown, so nothing is typed. A draft is still a draft.
# For the check before Enter, "draft <text>" carries the box text, its lines joined. With the
# third argument "reread", a first line "busy" or "idle" tells whether a busy mark shows.
ho_deliver_screen() {
  local rec=$1 profile=$2 mode=${3-} cap plain esc rc sgr bsgr isgr sep cutm k kend i n line raw text part mark p pfx="" prefixes marks cand=0 csi top busy=""
  esc=$(printf '\033')
  csi="$esc\\[[0-?]*[ -/]*[@-~]"
  cap=$(HO_TERM_BACKEND=$(jq -r '.backend // ""' "$rec") ho_term_capture "$(jq -r '.handle // ""' "$rec")" \
    "$(jq -r '.term_tag // ""' "$rec")" "$(jq -r '.session_id // ""' "$rec")" 60 styled 2>/dev/null) || { echo "unknown the screen could not be read"; return 0; }
  plain=$(printf '%s\n' "$cap" | LC_ALL=C sed -E "s|$csi||g")
  case $plain in *"$esc"*) echo "unknown the screen holds escape codes that cannot be read"; return 0 ;; esac
  local class box
  box=$(ho_screen_box_name "$rec")
  class=$(ho_deliver_classify "$profile" "$plain" "$box")
  case $class in
    none) ;;
    limit | trust | password) echo "hold $class"; return 0 ;;
    *) echo "unknown the screen reader gave no answer"; return 0 ;;
  esac
  rc=$(jq -r '.screen.rule_char // ""' "$profile")
  sgr=$(jq -r '.screen.suggestion_sgr // ""' "$profile")
  case $sgr in *[!0-9]*) sgr="" ;; esac
  bsgr=$(jq -r '.screen.busy_prompt_sgr // "" | strings' "$profile")
  case $bsgr in *[!0-9\;]*) bsgr="" ;; esac
  isgr=$(jq -r '.screen.idle_prompt_sgr // "" | strings' "$profile")
  sep=$(jq -r '.screen.status_separator // "" | strings' "$profile")
  cutm=$(jq -r '.screen.cut_mark // "" | strings' "$profile")
  case $isgr in *[!0-9\;]*) isgr="" ;; esac
  prefixes=$(jq -r '.screen.prompt_prefixes[] | strings' "$profile")
  marks=$(jq -r '.screen.busy_marks[]? | strings' "$profile")
  local -a P R
  n=0
  while IFS= read -r line; do P[n]=$line; n=$((n + 1)); done <<EOF_P
$plain
EOF_P
  i=0
  while IFS= read -r line; do R[i]=$line; i=$((i + 1)); done <<EOF_R
$cap
EOF_R
  # The input line: a prompt-prefix line right below a rule line.
  k=-1
  i=1
  while [ "$i" -lt "$n" ]; do
    line=${P[i]}
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      case $line in
        "$p"* | "${p% }")
          if ho_deliver_rule "${P[i - 1]}" "$rc" || ho_screen_named_rule "${P[i - 1]}" "$rc" "$box" >/dev/null; then
            k=$i; pfx=$p; cand=$((cand + 1)); break
          fi
          ;;
      esac
    done <<EOF_PFX
$prefixes
EOF_PFX
    i=$((i + 1))
  done
  if [ "$k" -lt 0 ]; then
    # A prompt line with text but no frame is still a draft: nothing may be typed.
    i=0
    while [ "$i" -lt "$n" ]; do
      while IFS= read -r p; do
        [ -n "$p" ] || continue
        case ${P[i]} in "$p"?*) echo "draft (no frame)"; return 0 ;; esac
      done <<EOF_PFX2
$prefixes
EOF_PFX2
      i=$((i + 1))
    done
    printf 'unknown no idle input line of the runtime is shown (a dialog, a notice or an unknown screen); last lines: %s\n' \
      "$(printf '%s\n' "$plain" | grep -v '^[[:space:]]*$' | tail -n 3 | sed 's/^[[:space:]]*//' | tr '\n' '|' | sed 's/|$//' | cut -c1-200)"
    return 0
  fi
  [ "$cand" -eq 1 ] || { echo "draft (more than one input line on the screen)"; return 0; }
  # The box ends at the last line below the input line that equals the opening frame line
  # (the rule line right above it) byte for byte. A rule line of another width or another
  # character, typed by the person, is no frame; with no equal line the box is not closed and
  # reads as a draft (validator B6).
  # A top rule that carries the session's own launch name stands for the plain rule of the
  # same width; the closing line must be that plain rule (real end-to-end check).
  top=$(ho_screen_named_rule "${P[k - 1]}" "$rc" "$box") || top=${P[k - 1]}
  kend=-1
  i=$((k + 1))
  while [ "$i" -lt "$n" ]; do
    [ "${P[i]}" != "$top" ] || kend=$i
    i=$((i + 1))
  done
  [ "$kend" -gt "$k" ] || { echo "draft (no closing frame equal to the opening frame)"; return 0; }
  # Every line under the box must be the runtime's status area (PR #105 review, M1).
  if [ "$kend" -lt $((n - 1)) ]; then
    local sdata src=0
    sdata=$(ho_screen_profile_data "$profile" 2>/dev/null) || { echo "unknown the runtime data holds no status area shapes"; return 0; }
    (i=$((kend + 1)); while [ "$i" -lt "$n" ]; do printf '%s\n' "${P[i]}"; i=$((i + 1)); done) | ho_screen_status_area "$sdata" || src=$?
    case $src in
      0) ;;
      1) echo "unknown a line under the input box is not the runtime's status area"; return 0 ;;
      *) echo "unknown the status area under the input box could not be read"; return 0 ;;
    esac
  fi
  # The lines above the opening frame go to the screen reader once more: a hold shown above a
  # box that already holds typed text reads as later text in the whole capture, but not here.
  # The runtime's notification line glued to the top rule is not session text (round 2).
  local above=$((k - 1))
  if [ "$above" -ge 1 ] && [ -n "${P[above - 1]}" ]; then
    local ndata
    if ndata=$(ho_screen_profile_data "$profile" 2>/dev/null) && ho_screen_notification "$ndata" "${P[above - 1]}" "$top"; then
      above=$((above - 1))
    fi
  fi
  if [ "$above" -ge 1 ]; then
    class=$(ho_deliver_classify "$profile" "$(i=0; while [ "$i" -lt "$above" ]; do printf '%s\n' "${P[i]}"; i=$((i + 1)); done)" "$box")
    case $class in
      none) ;;
      limit | trust | password) echo "hold $class"; return 0 ;;
      *) echo "unknown the screen reader gave no answer"; return 0 ;;
    esac
  fi
  # A busy mark above the box.
  i=0
  while [ "$i" -lt "$k" ] && [ -z "$busy" ]; do
    while IFS= read -r mark; do
      [ -n "$mark" ] || continue
      case ${P[i]} in *"$mark"*) busy=$mark; break ;; esac
    done <<EOF_BUSY
$marks
EOF_BUSY
    i=$((i + 1))
  done
  # A busy mark under the box, whole or cut short with "…" (issue #104).
  i=$((kend + 1))
  while [ "$i" -lt "$n" ] && [ -z "$busy" ]; do
    line=${P[i]}
    line=${line%"${line##*[! ]}"}
    while IFS= read -r mark; do
      [ -n "$mark" ] || continue
      case $line in *"$mark"*) busy=$mark; break ;; esac
      case $line in
        *"$cutm")
          [ -n "$cutm" ] && [ -n "$sep" ] || continue
          part=${line%"$cutm"}
          part=${part##*"$sep"}
          part=${part#"${part%%[! ]*}"}
          if [ -n "$part" ]; then case $mark in "$part"*) busy=$mark; break ;; esac; fi
          ;;
      esac
    done <<EOF_BUSY2
$marks
EOF_BUSY2
    i=$((i + 1))
  done
  # The prompt in the busy colour (a styled capture only; a plain one has no colour codes).
  if [ -z "$busy" ] && [ -n "$bsgr" ]; then
    case ${R[k]-} in "$esc[${bsgr}m"*) busy="the busy prompt colour" ;; esac
  fi
  # The input line: dim suggested text aside, then the prompt prefix off.
  raw=${R[k]-}
  [ -z "$sgr" ] || raw=$(printf '%s\n' "$raw" | LC_ALL=C sed -E "s/$esc\\[${sgr}m[^$esc]*($esc\\[(0|22)?m|\$)//g")
  text=$(printf '%s\n' "$raw" | LC_ALL=C sed -E "s|$csi||g")
  case $text in "$pfx"*) text=${text#"$pfx"} ;; *) text=${text#"${pfx% }"} ;; esac
  text=$(printf '%s' "$text" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  # Every other line inside the box must be blank; a rule line there is the person's text.
  i=$((k + 1))
  while [ "$i" -lt "$kend" ]; do
    part=$(printf '%s' "${P[i]}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    text="$text$part"
    i=$((i + 1))
  done
  # In "reread" mode (the check before Enter) the first line says whether a busy mark shows.
  [ "$mode" != reread ] || { [ -n "$busy" ] && echo busy || echo idle; }
  [ -z "$text" ] || { echo "draft $text"; return 0; }
  [ -z "$busy" ] || { echo "busy $busy"; return 0; }
  # Idle is proven by the idle prompt colour; anything else reads as unknown.
  case ${R[k]-} in
    *"$esc["*) ;;
    *) echo "unknown the screen shows no colour, so idle is not proven"; return 0 ;;
  esac
  [ -n "$isgr" ] || { echo "unknown the runtime data names no idle prompt colour, so idle is not proven"; return 0; }
  case ${R[k]-} in
    "$esc[${isgr}m$pfx"* | "$esc[${isgr}m${pfx% }") ;;
    *) echo "unknown the prompt does not show the idle colour, so idle is not proven"; return 0 ;;
  esac
  echo "empty"
}

# ho_deliver_classify <profile> <plain-text> [<box-name>]: the engine's screen reader on that
# text, with the pattern file of the given runtime and the session's launch name. The text lives in the run's screen folder only while it is
# read; a trap removes it if this step is stopped. Prints the class word, or "unknown".
ho_deliver_classify() {
  local profile=$1 sdir class
  sdir="$HO_RUN_DIR/screen"
  mkdir -p "$sdir" && chmod 700 "$sdir" 2>/dev/null || true
  HO_DELIVER_CFILE=$(umask 077 && mktemp "$sdir/.deliver.XXXXXX" 2>/dev/null) || { echo unknown; return 0; }
  trap 'rm -f "$HO_DELIVER_CFILE"' EXIT HUP INT TERM
  printf '%s\n' "$2" > "$HO_DELIVER_CFILE"
  unset HO_SCREEN_SELFTEST
  class=$(ho_screen_classify "$HO_DELIVER_CFILE" "$profile" "${3-}" 2>/dev/null) || class=unknown
  rm -f "$HO_DELIVER_CFILE"
  trap - EXIT HUP INT TERM
  printf '%s\n' "$class"
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

# ho_deliver_version_of <runtime-path>: the first word of "<runtime> --version", run with the
# fixed PATH in its own process group; after 5 s the group gets SIGTERM, the grace, then
# SIGKILL, and nothing is printed.
ho_deliver_version_of() {
  local cmd=$1 out pid deadline rc=0
  out=$(umask 077 && mktemp "$HO_RUN_DIR/logs/.version.XXXXXX" 2>/dev/null) || return 0
  set -m
  PATH=$(ho_deliver_exec_path "$cmd") "$cmd" --version < /dev/null > "$out" 2>/dev/null &
  pid=$!
  set +m
  deadline=$(( $(date +%s) + 5 ))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      ho_deliver_stop_group "$pid"
      { wait "$pid"; } 2>/dev/null || true
      rm -f "$out"
      return 0
    fi
    sleep 0.1
  done
  { wait "$pid"; } 2>/dev/null || rc=$?
  [ "$rc" -eq 0 ] && /usr/bin/awk 'NR == 1 { print $1 }' "$out"
  rm -f "$out"
  return 0
}

# ho_deliver_version_ge <have> <want>: 0 when the dotted version <have> is at least <want>.
ho_deliver_version_ge() {
  /usr/bin/awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, ".")
    n = (na > nb) ? na : nb
    for (i = 1; i <= n; i++) { p = x[i] + 0; q = y[i] + 0; if (p > q) exit 0; if (p < q) exit 1 }
    exit 0 }'
}

# ho_deliver_chord <record> <profile> <id>: send the runtime's send-now chord once (D37-LIFECYCLE-4).
ho_deliver_chord() {
  local rec=$1 profile=$2 id=$3 bytes want cmd have rc=0
  # The chord passes the same screen gate as typing: only an empty input line or a busy
  # session. A hold, a draft, an unknown screen or a reader that cannot run gets no chord.
  local gate
  gate=$(ho_deliver_screen "$rec" "$profile")
  case $gate in
    empty | busy*) ;;
    *) ho_ledger_append deliver-force-send id "$id" result skipped reason "the screen gate is closed (${gate%% *})"; return 1 ;;
  esac
  # Once per instruction, across both routes: the marker is taken before anything is sent.
  (set -C; : > "$HO_RUN_DIR/messages/$id.chord") 2>/dev/null || return 1
  # Numbers 1-31 only, never 10 (line feed) or 13 (carriage return): a chord must not act as
  # Enter (minor 12). Any other value, a string included, refuses the whole chord.
  bytes=$(jq -r '.force_send.bytes // [] | if length > 0 and all(type == "number" and . == floor and . >= 1 and . <= 31 and . != 10 and . != 13)
    then map(tostring) | join(" ") else "" end' "$profile" 2>/dev/null) || bytes=""
  want=$(jq -r '.force_send.min_version // ""' "$profile")
  [ -n "$bytes" ] && [ -n "$want" ] || { ho_ledger_append deliver-force-send id "$id" result skipped reason "the runtime data names no usable send-now chord"; return 1; }
  # The version comes from the runtime the launch checked and recorded, checked again here;
  # never from a PATH lookup, which a folder the project controls could win (PR #95 review).
  cmd=$(jq -r '.runtime_path // ""' "$rec")
  case $cmd in /*) ;; *) cmd="" ;; esac
  if [ -n "$cmd" ] && { [ ! -x "$cmd" ] || ! ho_session_runtime_path_ok "$cmd" 2>/dev/null; }; then cmd=""; fi
  have=""
  # The version check runs in its own process group under a time limit of 5 s, like the
  # message command; on a timeout the version is unknown and no chord is sent (PR #95 review).
  [ -z "$cmd" ] || have=$(ho_deliver_version_of "$cmd")
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
# Prints the scan result, or "unreadable". With force, a queued instruction gets the chord, once
# per id, whatever happened to the command that sent it (validator N3).
ho_deliver_wait() {
  local rec=$1 profile=$2 tr=$3 off=$4 id=$5 force=$6 st deadline chord=0
  deadline=$(( $(date +%s) + ${HO_DELIVER_WAIT:-30} ))
  while :; do
    # A transcript that cannot be read gives no answer at all, never "none" (validator N2).
    if head -c 1 "$tr" > /dev/null 2>&1; then
      st=$(ho_deliver_scan "$profile" "$tr" "$off" "$id")
    else
      st=unreadable
    fi
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
# any. 0 exited 0, 1 exited non-zero, 4 timed out, 5 ended by a signal, 2 no route, 3 refused
# before start (the
# command is missing, not executable, inside the project, or names a "#!" interpreter that is
# missing). Only 2 and 3 mean "not started": no process ever ran.
# The command runs in its own process group. On timeout, and also after a non-zero exit (for
# what is left of the group), the group gets SIGTERM, a grace of
# delivery.message_kill_grace_seconds (default 2), then SIGKILL, so the call returns within the
# timeout plus the grace (PR #95 review, validator N4). Only that exact group is signalled, and
# the shell's own notice of a stopped job is not printed.
ho_deliver_message() {
  local profile=$1 rec=$2 id=$3 file=$4 sid el pid deadline grace cmd rc=0
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
  cmd=$(command -v -- "${argv[0]}" 2>/dev/null || true)
  case $cmd in /*) ;; *) return 3 ;; esac
  [ -f "$cmd" ] && [ -x "$cmd" ] || return 3
  ho_session_runtime_path_ok "$cmd" 2>/dev/null || return 3
  # A script whose "#!" line names a missing interpreter cannot start (an exec failure).
  local first interp
  first=$(head -c 256 "$cmd" 2>/dev/null | head -n 1) || first=""
  case $first in
    '#!'*)
      interp=${first#'#!'}
      interp=${interp# }
      interp=${interp%% *}
      [ -f "$interp" ] && [ -x "$interp" ] || return 3
      ;;
  esac
  # set -m gives the background job a process group of its own (its ID is the job's PID).
  set -m
  PATH=$(ho_deliver_exec_path "$cmd") "$cmd" "${argv[@]:1}" < /dev/null > /dev/null 2>> "$HO_RUN_DIR/logs/deliver.log" &
  pid=$!
  set +m
  deadline=$(( $(date +%s) + ${HO_DELIVER_MSG_TIMEOUT:-30} ))
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      ho_deliver_stop_group "$pid"
      { wait "$pid"; } 2>/dev/null || true
      return 4
    fi
    sleep 0.1
  done
  { wait "$pid"; } 2>/dev/null || rc=$?
  [ "$rc" -eq 0 ] && return 0
  # A failed command may have left processes in its group: they are stopped before the
  # transcript is judged, so nothing of it can write later.
  ho_deliver_stop_group "$pid"
  # An exit by a signal (128+N) says nothing about whether the hand-off happened: unknown.
  [ "$rc" -gt 128 ] && return 5
  return 1
}

# ho_deliver_stop_group <pgid>: SIGTERM to that exact process group, a bounded grace, then
# SIGKILL. A group that is already gone is left alone.
ho_deliver_stop_group() {
  local g=$1 grace
  kill -0 -- "-$g" 2>/dev/null || return 0
  kill -TERM -- "-$g" 2>/dev/null || true
  grace=$(( $(date +%s) + ${HO_DELIVER_GRACE:-2} ))
  while kill -0 -- "-$g" 2>/dev/null && [ "$(date +%s)" -lt "$grace" ]; do sleep 0.1; done
  kill -KILL -- "-$g" 2>/dev/null || true
}

# ho_deliver_typed_line <id> <text> <file>: the line to type. The text itself when it is one
# line of safe characters within the byte limit, else a short line that names the file.
ho_deliver_typed_line() {
  local id=$1 text=$2 file=$3 max line
  max=${HO_DELIVER_MAX_BYTES:-800}
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

# ho_deliver_not <id> <name> <reason> <detail> [ledger pairs]: the detail (for example what the
# screen showed) is printed only, never written to the ledger, so screen text such as a draft
# never reaches it.
ho_deliver_not() {
  local id=$1 name=$2 reason=$3 detail=$4
  shift 4
  ho_ledger_append deliver-failed id "$id" name "$name" reason "$reason" "$@"
  printf 'NOT-DELIVERED id=%s session=%s: %s%s\n' "$id" "$name" "$reason" "${detail:+; $detail}"
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
    case $file in -*) echo "harness: a --file name may not start with -" >&2; return 65 ;; esac
    [ -f "$file" ] && [ -r "$file" ] || { printf 'harness: cannot read %s\n' "$file" >&2; return 65; }
    text=$(cat -- "$file") || return 65
  fi
  [ -n "$text" ] || { echo "harness: the instruction text is empty" >&2; return 64; }
  [ "$(ho_deliver_bytes "$text")" -le "$HO_DELIVER_MAX_TEXT" ] || { printf 'harness: the instruction is longer than %s bytes\n' "$HO_DELIVER_MAX_TEXT" >&2; return 65; }
  if [ -n "$id" ]; then ho_deliver_id_ok "$id" || return 65; else id=$(ho_deliver_new_id); fi
  local delay
  delay=$(ho_term_enter_delay) || return 78
  HO_DELIVER_WAIT=$(ho_deliver_setting .delivery.wait_seconds 30 2 3600) || return $?
  HO_DELIVER_MSG_TIMEOUT=$(ho_deliver_setting .delivery.message_timeout_seconds 30 1 600) || return $?
  HO_DELIVER_GRACE=$(ho_deliver_setting .delivery.message_kill_grace_seconds 2 0 30) || return $?
  HO_DELIVER_MAX_BYTES=$(ho_deliver_setting .terminal.typed_max_bytes 800 300 1000) || return $?
  local rec profile tr off msg tmp st rc pid screen
  rec=$(ho_deliver_record "$name") || return $?
  profile=$(ho_deliver_profile "$rec") || return $?
  [ "$(jq -r '.status // ""' "$rec")" = running ] || { printf 'harness: session %s is not running\n' "$name" >&2; return 65; }
  pid=$(ho_session_live_pid "$rec") || return 1
  [ -n "$pid" ] || ho_deliver_not "$id" "$name" "the session's process is gone" "" || return 1
  mkdir -p "$HO_RUN_DIR/messages" "$HO_RUN_DIR/logs"
  msg="$HO_RUN_DIR/messages/$id.txt"
  [ ! -e "$msg" ] || { printf 'harness: instruction id %s was used before in this run\n' "$id" >&2; return 65; }
  # No readable transcript, nothing sent (H-101): the file must exist, be readable and read.
  tr=$(ho_deliver_transcript "$rec" "$profile") || tr=""
  off=""
  [ -z "$tr" ] || { head -c 1 "$tr" > /dev/null 2>&1 && off=$(ho_deliver_size "$tr"); }
  case $off in '' | *[!0-9]*) ho_deliver_not "$id" "$name" "no readable transcript of the session to check delivery against; nothing was sent" "" || return 1 ;; esac
  # One id, one instruction. The file is written to a temp file in the same folder, mode 600,
  # then linked into place; the link fails if the id was used before (no clobber).
  tmp=$(umask 077 && mktemp "$HO_RUN_DIR/messages/.tmp.XXXXXX") || return 1
  printf '%s: %s\n' "$id" "$text" > "$tmp" || { rm -f "$tmp"; return 1; }
  if ! ln "$tmp" "$msg" 2>/dev/null; then
    rm -f "$tmp"
    printf 'harness: instruction id %s was used before in this run\n' "$id" >&2
    return 65
  fi
  rm -f "$tmp"
  ho_ledger_append deliver-request id "$id" name "$name" bytes "$(ho_deliver_bytes "$text")" force_send "$force"

  # ---- 1. the message route ----
  # A message whose outcome is unknown is never typed; a proven failure falls back to typing
  # (H-101). After any start, the transcript is read with the same bounded wait.
  #   - the id was seen (delivered, queued or dequeued): reported; never typed;
  #   - known failure, so the typed route runs with all its checks: the command could not
  #     start (no process ran), or it exited non-zero, its group is gone, and the transcript is
  #     readable and holds no record of the id;
  #   - unknown (a timeout, an exit by a signal, exit 0 with no proof, or an unreadable
#     transcript): one
  #     owner-action line, nothing typed, no retry.
  rc=0
  ho_deliver_message "$profile" "$rec" "$id" "$msg" || rc=$?
  case $rc in
    2) ho_ledger_append deliver-message id "$id" result "no message route in the runtime data" ;;
    3) ho_ledger_append deliver-message id "$id" result "refused before start (command missing, not executable, inside the project, or its interpreter is missing)" ;;
    *)
      local how=sent
      case $rc in 1) how="failed (non-zero exit)" ;; 4) how="timed out and stopped" ;; 5) how="ended by a signal" ;; esac
      ho_ledger_append deliver-message id "$id" result "$how"
      st=$(ho_deliver_wait "$rec" "$profile" "$tr" "$off" "$id" "$force")
      case $st in
        delivered*)
          ho_ledger_append deliver-confirmed id "$id" name "$name" route message proof "${st#delivered }"
          printf 'DELIVERED id=%s session=%s route=message proof=%s\n' "$id" "$name" "${st#delivered }"
          return 0
          ;;
      esac
      ho_ledger_append deliver-message id "$id" result unconfirmed transcript_grew "$(ho_deliver_grew "$tr" "$off")" state "$st"
      ho_deliver_pending "$id" "$name" "$st" || return 1
      if [ "$rc" -eq 1 ] && [ "$st" = none ]; then
        ho_ledger_append deliver-message id "$id" result "proven failure: non-zero exit, group gone, no record of the id; typed fallback"
      else
        ho_ledger_append owner-action title "check instruction $id of session $name" \
          why "the message command was started ($how) and its outcome is unknown; it is not sent again" \
          command "harness session $HO_RUN_DIR proof $name $id" verify "proof prints delivered, or the owner sends the instruction again by hand"
        ho_deliver_not "$id" "$name" "unknown, not sent again: the message command was started ($how) but its outcome is unknown" "" state "$st"
        return 1
      fi
      ;;
  esac

  # ---- 2. the typed fallback (D42g, H-099, H-137) ----
  screen=$(ho_deliver_screen "$rec" "$profile")
  case $screen in
    empty) ;;
    draft*) ho_deliver_not "$id" "$name" "the input line holds text typed by the user; nothing was typed" "" screen draft || return 1 ;;
    hold*) ho_deliver_not "$id" "$name" "the screen shows a ${screen#hold } hold (D42g); nothing was typed and no Enter was sent" "" screen "$screen" || return 1 ;;
    busy*)
      [ "$force" -eq 1 ] || ho_deliver_not "$id" "$name" "the session is busy; nothing was typed, the instruction waits" "" screen busy || return 1
      ;;
    *) ho_deliver_not "$id" "$name" "the screen shows no idle input line; nothing was typed" "${screen#unknown }" screen unknown || return 1 ;;
  esac
  local typed mode line h tag sid backend
  typed=$(ho_deliver_typed_line "$id" "$text" "$msg") || ho_deliver_not "$id" "$name" "the message file path cannot be typed; nothing was typed" "" || return 1
  mode=${typed%%"$(printf '\t')"*}
  line=${typed#*"$(printf '\t')"}
  h=$(jq -r '.handle // ""' "$rec") tag=$(jq -r '.term_tag // ""' "$rec") sid=$(jq -r '.session_id' "$rec") backend=$(jq -r '.backend // ""' "$rec")
  rc=0
  HO_TERM_BACKEND=$backend ho_term_type "$h" "$tag" "$sid" "$line" 2>/dev/null || rc=$?
  [ "$rc" -eq 0 ] || ho_deliver_not "$id" "$name" "the terminal refused the typed line (exit $rc)" "" || return 1
  sleep "$delay"
  # Enter goes only when the input line holds exactly the typed text and nothing more: a key
  # pressed or a dialog opened in between gets no Enter (D42g).
  screen=$(ho_deliver_screen "$rec" "$profile" reread)
  local rbusy=""
  case $screen in
    busy"
"* | idle"
"*) rbusy=${screen%%"
"*}; screen=${screen#*"
"} ;;
  esac
  # A hold, or a busy mark on a delivery that is not a forced stop, gets no Enter; the typed
  # text stays on the input line, which the owner is told (validator, round 8).
  if [ "${screen%% *}" = hold ] || { [ "$rbusy" = busy ] && [ "$force" -eq 0 ]; }; then
    # The ledger gets a fixed phrase and the class word only, never screen text (round 9, B7).
    local seen="a busy mark"
    case $screen in "hold limit" | "hold trust" | "hold password") seen="a ${screen#hold } hold" ;; esac
    ho_ledger_append owner-action title "typed text waits on the input line of session $name" \
      why "$seen appeared before Enter; instruction $id was typed and no Enter was sent" \
      command "harness session $HO_RUN_DIR list" verify "the input line of session $name is cleared or sent by the owner"
    ho_deliver_not "$id" "$name" "the screen changed before Enter ($seen); no Enter was sent, and the typed text sits on the input line" "" screen "${screen%% *}" || return 1
  fi
  if ! ho_deliver_line_is "$screen" "$line"; then
    ho_deliver_not "$id" "$name" "the input line did not hold exactly the typed text before Enter; no Enter was sent, and the typed text may still sit on the input line" "" screen "${screen%% *}" || return 1
  fi
  rc=0
  HO_TERM_BACKEND=$backend ho_term_key "$h" "$tag" "$sid" enter 2>/dev/null || rc=$?
  [ "$rc" -eq 0 ] || ho_deliver_not "$id" "$name" "the terminal refused the Enter key (exit $rc)" "" || return 1
  ho_ledger_append deliver-typed id "$id" name "$name" mode "$mode" bytes "$(ho_deliver_bytes "$line")"
  st=$(ho_deliver_wait "$rec" "$profile" "$tr" "$off" "$id" "$force")
  case $st in
    delivered*)
      ho_ledger_append deliver-confirmed id "$id" name "$name" route typed proof "${st#delivered }"
      printf 'DELIVERED id=%s session=%s route=typed proof=%s\n' "$id" "$name" "${st#delivered }"
      return 0
      ;;
  esac
  ho_deliver_pending "$id" "$name" "$st" || return 1
  ho_deliver_not "$id" "$name" "no transcript entry carries the instruction id" "" state "$st" \
    transcript_grew "$(ho_deliver_grew "$tr" "$off")"
}

# ho_deliver_pending <id> <name> <state>: 1 (and the report) when the transcript shows the
# instruction queued or taken off the queue without delivery; nothing is sent again then.
ho_deliver_pending() {
  case $3 in
    queued) ho_deliver_not "$1" "$2" "the session queued the instruction and has not taken it yet; check again with proof, do not send it again" "" state queued ;;
    dequeued) ho_deliver_not "$1" "$2" "the instruction left the session's queue without a proof of delivery; it is not sent again" "" state dequeued ;;
    *) return 0 ;;
  esac
}

# ho_deliver_line_is <screen-state> <line>: 0 when the input line holds exactly <line>. A long
# line wraps onto more screen lines, where the terminal may drop a space at the wrap, so a
# match with all spaces removed counts too.
ho_deliver_line_is() {
  case $1 in "draft "*) ;; *) return 1 ;; esac
  [ "${1#draft }" = "$2" ] && return 0
  [ "$(printf '%s' "${1#draft }" | tr -d ' ')" = "$(printf '%s' "$2" | tr -d ' ')" ]
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
