# shellcheck shell=bash
# Notification channels (H-115 to H-123; design D36, S8-28a, D37-FLOW-8, D37-NOTIFICATIONS-1 to
# D37-NOTIFICATIONS-6). The configured tracker stays the source of truth (H-027): a channel only
# carries copies of tracker questions, run events, and replies to the harness's own questions.
#
# Channels (D36): one contract, three operations: send, read_replies, check. A channel is wired
# by "command" or by "mcp":
#   user config     notify.channels.<label> = {"preset": "telegram"|"slack"|"gmail",
#                                              "via": "command", "argv": ["<program>", ...]}
#   user or project notify.channels.<label> = {"preset": ..., "via": "mcp", "mcp": "<connector>"}
# Tokens stay with the channel program or connector in user-level config; the engine never reads
# one. A project config holding a non-empty channel command is refused at start (D37-FLOW-8).
# A user entry wins over a project entry with the same label.
#
# Command contract: the engine runs "<argv...> <operation>" with no shell, 20 s at most.
#   send          message text on stdin; HO_NOTIFY_KIND (question|event|note), HO_NOTIFY_TICKET,
#                 HO_NOTIFY_EVENT and HO_NOTIFY_REPLY_TO in the environment. Exit 0 = sent; the
#                 first stdout line is the channel's message ref (replies name it).
#   read_replies  one JSON object per line: {"id", "reply_to", "sender", "text", "authenticated"}.
#                 The engine skips ids it has read before, so the program may repeat them.
#   check         exit 0 when the connection works (read-only).
# MCP route (agent decision under D37): the engine cannot call a connector, so a session does.
# "send" queues the message in <run>/notify/outbox.jsonl; the session sends it with the connector
# and reports "notify <run> sent <id> <ref>" or "notify <run> failed <id>" (a failure falls back to
# the next channel). Replies come in with "notify <run> inbox <label> <file>" and are read like
# read_replies output.
#
# Selection (H-116, H-121, S8-28a): notify.use (labels; default every channel), notify.priority
# (labels; default the order of setup: user entries, then project entries), notify.questions
# (labels for questions; default every active channel), notify.events.<event> (true or false;
# default true). Events: question, blocked, taken, done, run-ended, limit-pause,
# orchestrator-down. Agent decision under D37 for H-116 next to H-121: a message goes to each
# selected channel; a failed send goes to the next active channel by priority that is not
# selected and not yet tried. When every send fails, the tracker still holds the text.
#
# Replies (H-117 to H-119, H-122, D37-NOTIFICATIONS-2, -3, -5): only a reply to a question this
# run sent counts; any other message is dropped and its text goes nowhere. The first reply read
# for a question is recorded on the ticket with "tickets answer", with its mapped author or as an
# unmapped sender; the intake tick then applies it or moves the ticket to needs-review (H-033,
# H-035). Every later reply to that question gets a note with the tracker link, and is never
# recorded. The sufficiency check and the follow-up round limit (H-117, D37-NOTIFICATIONS-4) stay
# with the session that reads the recorded answer; this file does not judge text.
#
# Run state: <run>/notify/msg/<id>.json, refs.jsonl, seen/<label>, answered/<qid>/, outbox.jsonl,
# inbox/<label>.jsonl, inbox-read/<label>. Exit codes: 64 usage, 69 a check failed, 78 config.

HO_NT_EVENTS="question blocked taken done run-ended limit-pause orchestrator-down"
HO_NT_LABEL_RE='^[a-z0-9][a-z0-9-]{0,39}$'
HO_NT_REF_RE='^[A-Za-z0-9][A-Za-z0-9._:@-]{0,99}$'

ho_nt_err() { printf 'harness notify: %s\n' "$*" >&2; }
ho_nt_presets() { printf '%s/templates/notify-presets.json\n' "$HO_ROOT"; }

# ho_nt_project_file: the project config the lookup reads, or /dev/null.
ho_nt_project_file() {
  local proj
  proj=$(ho_project_root 2>/dev/null) || { echo /dev/null; return 0; }
  ho_project_config_file "$proj"
}

# ho_nt_project_cmd_check: refuse a project config that wires a channel by command (D37-FLOW-8).
ho_nt_project_cmd_check() {
  local pf
  pf=$(ho_nt_project_file)
  if jq -e '(.notify.channels // {}) | type == "object" and any(.[]; type == "object" and
        (((.argv // []) | length > 0) or ((.command // "") | length > 0)))' "$pf" >/dev/null 2>&1; then
    printf 'harness: the project config %s wires a notification channel by command (notify.channels). No command from it runs. Move the command to the user config %s under notify.channels.<label> and keep only the channel label in the project config.\n' \
      "$pf" "$(ho_user_config)" >&2
    return 78
  fi
}

# ho_nt_defined: true when any config defines a channel (cheap; no validation).
ho_nt_defined() {
  local uf pf
  uf=$(ho_user_config 2>/dev/null) || uf=/dev/null
  pf=$(ho_nt_project_file)
  jq -e '(.notify.channels // {}) | type == "object" and length > 0' "$uf" >/dev/null 2>&1 ||
    jq -e '(.notify.channels // {}) | type == "object" and length > 0' "$pf" >/dev/null 2>&1
}

# ho_nt_channels: the active channels as one JSON array in priority order:
#   [{label, preset, via, argv|mcp}]. Exit 78 on a bad entry or setting.
ho_nt_channels() {
  local uf pf use prio out
  ho_nt_project_cmd_check || return 78
  uf=$(ho_user_config); [ -f "$uf" ] || uf=/dev/null
  pf=$(ho_nt_project_file)
  use=$(ho_cfg '.notify.use | if . == null then null else tojson end' null) || return 78
  prio=$(ho_cfg '.notify.priority | if . == null then null else tojson end' null) || return 78
  out=$(jq -cn --slurpfile u <(jq -c '.notify.channels // {}' "$uf" 2>/dev/null || echo '{}') \
      --slurpfile p <(jq -c '.notify.channels // {}' "$pf" 2>/dev/null || echo '{}') \
      --argjson use "$use" --argjson prio "$prio" --arg re "$HO_NT_LABEL_RE" '
    def entries(o): if (o | type) == "object" then (o | to_entries) else error("notify.channels must be an object") end;
    (entries($u[0]) | map(.value.from = "user")) as $ue
    | (entries($p[0]) | map(select(.key as $k | ($ue | map(.key) | index($k)) == null)) | map(.value.from = "project")) as $pe
    | [$ue[], $pe[]]
    | map(. as $e | $e.value as $v
        | if ($e.key | test($re)) | not then error("channel label \($e.key) must use a-z 0-9 - and not start with -")
          elif ($v | type) != "object" then error("channel \($e.key) must be an object")
          elif (["telegram", "slack", "gmail"] | index($v.preset)) == null then error("channel \($e.key): preset must be telegram, slack or gmail")
          elif $v.via == "command" then
            (if ($v.argv | type) == "array" and ($v.argv | length) > 0 and all($v.argv[]; type == "string" and length > 0)
             then {label: $e.key, preset: $v.preset, via: "command", argv: $v.argv}
             else error("channel \($e.key): via command needs argv, a list of strings, in the user config") end)
          elif $v.via == "mcp" then
            (if ($v.mcp | type) == "string" and ($v.mcp | test("^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$"))
             then {label: $e.key, preset: $v.preset, via: "mcp", mcp: $v.mcp}
             else error("channel \($e.key): via mcp needs the connector name in mcp") end)
          else error("channel \($e.key): via must be command or mcp") end)
    | (map(.label)) as $all
    | (if $use == null then $all elif ($use | type) == "array" then $use else error("notify.use must be a list of labels") end) as $on
    | (if $prio == null then [] elif ($prio | type) == "array" then $prio else error("notify.priority must be a list of labels") end) as $pr
    | ($on | map(select(type != "string" or (($all | index(.)) == null)))) as $bad
    | if ($bad | length) > 0 then error("notify.use names no channel: \($bad | map(tostring) | join(", "))") else . end
    | map(select(.label as $l | $on | index($l)))
    | sort_by((.label as $l | ($pr | index($l)) // 1000), (.label as $l | $all | index($l)))' 2>&1) || {
    ho_nt_err "config: ${out#jq: error (at <unknown>): }"
    return 78
  }
  printf '%s\n' "$out"
}

# ho_nt_event_on <event>: notify.events.<event>, default on (S8-28a).
ho_nt_event_on() {
  local v
  v=$(ho_cfg ".notify.events[\"$1\"]" true 2>/dev/null) || v=true
  [ "$v" != false ]
}

# ho_nt_exec <out-file> <in-file> <argv...>: run with no shell, 20 s at most; the exit code.
ho_nt_exec() {
  local out=$1 in=$2 pid i=0 rc=0
  shift 2
  ( exec "$@" < "$in" > "$out" 2>/dev/null ) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124; fi
  wait "$pid" || rc=$?
  return "$rc"
}

ho_nt_dir() { mkdir -p "$HO_RUN_DIR/notify/$1" && printf '%s/notify/%s\n' "$HO_RUN_DIR" "$1"; }
ho_nt_id_new() { printf '%s-%s\n' "$(date +%s)" "$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"; }

# ho_nt_send_one <channel-json> <msg-id> <text-file>: send through one channel. Prints the ref
# on success; returns 1 on failure. Message fields come from the message record.
ho_nt_send_one() {
  local ch=$1 id=$2 tf=$3 rec via out ref rc=0
  local -a argv=()
  rec=$(cat "$HO_RUN_DIR/notify/msg/$id.json")
  via=$(jq -r .via <<<"$ch")
  if [ "$via" = mcp ]; then
    jq -cn --arg id "$id" --argjson ch "$ch" --argjson r "$rec" --rawfile text "$tf" \
      '{id: $id, label: $ch.label, mcp: $ch.mcp, kind: $r.kind, ticket: $r.ticket, event: $r.event, reply_to: $r.reply_to, text: $text}' \
      >> "$(ho_nt_dir .)/outbox.jsonl" || return 1
    printf '%s\n' "$id"
    return 0
  fi
  while IFS= read -r el; do argv+=("$el"); done < <(jq -r '.argv[]' <<<"$ch")
  out=$(mktemp "${TMPDIR:-/tmp}/ho-notify.XXXXXX") || return 1
  HO_NOTIFY_KIND=$(jq -r .kind <<<"$rec") HO_NOTIFY_TICKET=$(jq -r .ticket <<<"$rec") \
    HO_NOTIFY_EVENT=$(jq -r .event <<<"$rec") HO_NOTIFY_REPLY_TO=$(jq -r .reply_to <<<"$rec") \
    ho_nt_exec "$out" "$tf" "${argv[@]}" send || rc=$?
  ref=$(head -n 1 "$out" | tr -d '\r')
  rm -f "$out"
  [ "$rc" -eq 0 ] || return 1
  printf '%s' "$ref" | grep -Eq "$HO_NT_REF_RE" || ref=$id
  printf '%s\n' "$ref"
}

# ho_nt_try <msg-id> <label>: one send, recorded in the message, the ledger and (for a question)
# refs.jsonl. 0 = sent or queued.
ho_nt_try() {
  local id=$1 label=$2 f ch ref rec
  f="$HO_RUN_DIR/notify/msg/$id.json"
  rec=$(cat "$f")
  ch=$(jq -c --arg l "$label" '.channels[] | select(.label == $l)' <<<"$rec")
  ho_atomic_write "$f" < <(jq -c --arg l "$label" '.tried += [$l]' <<<"$rec") || return 1
  if ref=$(ho_nt_send_one "$ch" "$id" "$HO_RUN_DIR/notify/msg/$id.txt"); then
    if [ "$(jq -r .kind <<<"$rec")" = question ]; then
      jq -cn --arg l "$label" --arg ref "$ref" --argjson r "$rec" '{label: $l, ref: $ref, qid: $r.qid, ticket: $r.ticket}' \
        >> "$(ho_nt_dir .)/refs.jsonl"
    fi
    ho_ledger_append notify-sent channel "$label" message "$id" kind "$(jq -r .kind <<<"$rec")" ticket "$(jq -r .ticket <<<"$rec")" event "$(jq -r .event <<<"$rec")"
    return 0
  fi
  ho_ledger_append notify-failed channel "$label" message "$id" ticket "$(jq -r .ticket <<<"$rec")"
  return 1
}

# ho_nt_fallback <msg-id>: send through the next active channel by priority that is neither a
# selected target nor tried yet (H-121). 0 when one took it.
ho_nt_fallback() {
  local id=$1 l
  while :; do
    l=$(jq -r '. as $r | [.channels[].label | select(. as $x | (($r.targets + $r.tried) | index($x)) == null)] | first // empty' \
      "$HO_RUN_DIR/notify/msg/$id.json")
    [ -n "$l" ] || return 1
    ho_nt_try "$id" "$l" && return 0
  done
}

# ho_nt_deliver <kind> <ticket> <event> <text-file> [qid] [reply-to] [only-label]: send one message.
# Prints "sent <n>" (the channels that took it). No active channel: nothing happens.
ho_nt_deliver() {
  local kind=$1 ticket=$2 event=$3 tf=$4 qid=${5-} reply=${6-} only=${7-} chans sel id n=0 t
  chans=$(ho_nt_channels) || return 78
  [ "$(jq length <<<"$chans")" -gt 0 ] || return 0
  if [ -n "$only" ]; then
    sel=$(jq -c --arg l "$only" '[.[] | select(.label == $l) | .label]' <<<"$chans")
  elif [ "$kind" = question ]; then
    sel=$(ho_cfg '.notify.questions | if . == null then null else tojson end' null) || return 78
    sel=$(jq -c --argjson q "$sel" 'if $q == null then map(.label) else [.[].label | select(. as $l | $q | index($l))] end' <<<"$chans")
  else
    sel=$(jq -c 'map(.label)' <<<"$chans")
  fi
  id=$(ho_nt_id_new)
  ho_nt_dir msg >/dev/null || return 1
  cp "$tf" "$HO_RUN_DIR/notify/msg/$id.txt" || return 1
  jq -cn --arg kind "$kind" --arg ticket "$ticket" --arg event "$event" --arg qid "$qid" --arg reply "$reply" \
    --argjson ch "$chans" --argjson sel "$sel" --arg only "$only" \
    '{kind: $kind, ticket: $ticket, event: $event, qid: $qid, reply_to: $reply, channels: $ch, targets: $sel, tried: [],
      fallback: ($only == "")}' | ho_atomic_write "$HO_RUN_DIR/notify/msg/$id.json" || return 1
  for t in $(jq -r '.[]' <<<"$sel"); do
    if ho_nt_try "$id" "$t"; then n=$((n + 1))
    elif [ -z "$only" ] && ho_nt_fallback "$id"; then n=$((n + 1)); fi
  done
  if [ "$n" -eq 0 ]; then
    ho_ledger_append notify-undelivered message "$id" kind "$kind" ticket "$ticket" note "every channel failed; the tracker holds the text"
  fi
  echo "sent $n"
}

# ---- questions and events (the hooks call these; they never fail their caller) --------------

# ho_nt_question <ticket> <numbered-lines-file>: mirror a question just posted to the tracker
# (H-116). The numbered lines are the exact lines of the tracker comment.
ho_nt_question() {
  local id=$1 lf=$2 tf qid rc=0
  ho_nt_event_on question || return 0
  tf=$(mktemp "${TMPDIR:-/tmp}/ho-nq.XXXXXX") || return 1
  {
    printf 'Ticket %s needs answers from a person before the work can go on:\n\n' "$id"
    cat "$lf"
    printf '\nReply to this message to answer. The answer is recorded on the ticket: %s\n' "$(ho_nt_link "$id")"
  } > "$tf"
  qid="$id-$(ho_nt_id_new)"
  ho_nt_deliver question "$id" question "$tf" "$qid" || rc=$?
  rm -f "$tf"
  return "$rc"
}

# ho_nt_event <event> <ticket|-> <text>: announce a run event if it is switched on (H-120).
ho_nt_event() {
  local ev=$1 t=${2:--} text=$3 tf rc=0
  ho_nt_event_on "$ev" || return 0
  tf=$(mktemp "${TMPDIR:-/tmp}/ho-ne.XXXXXX") || return 1
  printf 'harness: %s\n' "$text" > "$tf"
  [ "$t" = - ] || printf '%s\n' "$(ho_nt_link "$t")" >> "$tf"
  ho_nt_deliver event "$t" "$ev" "$tf" || rc=$?
  rm -f "$tf"
  return "$rc"
}

# ho_nt_link <ticket>: where the ticket lives in the tracker.
ho_nt_link() {
  if [ "${HO_TK_SOURCE:-}" = github ] && [ -n "${HO_TK_REPO:-}" ]; then
    printf 'https://github.com/%s/issues/%s\n' "$HO_TK_REPO" "$1"
  else
    printf 'ticket %s in the configured tracker\n' "$1"
  fi
}

# ho_nt_hook <function> [args...]: call from other files. Needs a run (HO_RUN_DIR) and a defined
# channel; otherwise it does nothing. Never prints and never fails the caller.
ho_nt_hook() {
  [ -n "${HO_RUN_DIR:-}" ] && [ -d "${HO_RUN_DIR:-/nonexistent}" ] || return 0
  ho_nt_defined || return 0
  ( HO_NT_IN_HOOK=1; ho_run_open "$HO_RUN_DIR" && "$@" ) >/dev/null 2>&1 || true
  return 0
}

# ho_nt_ledger_event <kind> [key value]...: map a run ledger line to an event (S8-28a). Called by
# ho_ledger_append after the line is written.
ho_nt_ledger_event() {
  local kind=$1 t=- reason="" type="" key=""
  [ -z "${HO_NT_IN_HOOK:-}" ] || return 0
  case $kind in pickup | run-end | stop | limits-over | orchestrator-down) ;; *) return 0 ;; esac
  shift
  while [ $# -ge 2 ]; do
    case $1 in ticket) t=$2 ;; reason) reason=$2 ;; type) type=$2 ;; key) key=$2 ;; esac
    shift 2
  done
  case $kind in
    pickup) ho_nt_hook ho_nt_event taken "$t" "ticket $t was taken into work" ;;
    run-end) ho_nt_hook ho_nt_event run-ended - "the run ended ($reason)" ;;
    stop) ho_nt_hook ho_nt_event run-ended - "the run is stopping ($type): $reason" ;;
    limits-over) ho_nt_hook ho_nt_once "limit-$key" ho_nt_event limit-pause - "a subscription limit paused new work ($key)" ;;
    orchestrator-down) ho_nt_hook ho_nt_event orchestrator-down - "the orchestrator is down and is not restarted again this hour; run /harness:resume" ;;
  esac
}

# ho_nt_once <key> <cmd...>: run the command once per run for the key.
ho_nt_once() {
  local k
  k=$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_')
  shift
  mkdir "$(ho_nt_dir once)/$k" 2>/dev/null || return 0
  "$@"
}

# ho_nt_state_event <ticket> <state>: blocked, needs-review and done (S8-28a). A question sets
# blocked too; its own mirror is the message, so "tickets ask" skips this one (HO_NT_ASKING).
ho_nt_state_event() {
  case $2 in
    blocked) [ -n "${HO_NT_ASKING:-}" ] || ho_nt_hook ho_nt_event blocked "$1" "ticket $1 is blocked and waits for a person" ;;
    needs-review) ho_nt_hook ho_nt_event blocked "$1" "ticket $1 was sent to needs-review" ;;
    done) ho_nt_hook ho_nt_event done "$1" "ticket $1 is done" ;;
  esac
  return 0
}

# ---- identity (H-122, D37-NOTIFICATIONS-3) ------------------------------------------------------

# ho_nt_sender_login <preset> <sender> <authenticated>: the account for a channel sender, from the
# one identity map in the user config. Exactly one entry must match; otherwise nothing (unmapped).
# Gmail: the sender address against the entry's emails, only when the channel reports passing
# sender authentication. Telegram and Slack: senders.<preset>.
ho_nt_sender_login() {
  local preset=$1 sender=$2 auth=$3 uf a
  [ -n "$sender" ] || return 0
  uf=$(ho_user_config 2>/dev/null) || return 0
  [ -f "$uf" ] && [ ! -L "$uf" ] || return 0
  if [ "$preset" = gmail ]; then
    [ "$auth" = true ] || return 0
    a=$(jq -r --arg s "$sender" '[(.identities // [])[] | select(type == "object" and (.emails | type) == "array"
        and any(.emails[]; type == "string" and ascii_downcase == ($s | ascii_downcase)))]
        | if length == 1 then .[0].account // empty else empty end' "$uf" 2>/dev/null) || a=""
  else
    a=$(jq -r --arg p "$preset" --arg s "$sender" '[(.identities // [])[] | select(type == "object"
        and (.senders | type) == "object" and ((.senders[$p] // null) | tostring) == $s)]
        | if length == 1 then .[0].account // empty else empty end' "$uf" 2>/dev/null) || a=""
  fi
  ho_tk_login_ok "$a" && printf '%s\n' "$a"
  return 0
}

# ---- replies (H-117, H-118, H-119, H-120) -------------------------------------------------------

# ho_nt_read <channel-json> <out-file>: the channel's replies as JSON lines.
ho_nt_read() {
  local ch=$1 out=$2 label via inb
  local -a argv=()
  label=$(jq -r .label <<<"$ch")
  via=$(jq -r .via <<<"$ch")
  if [ "$via" = mcp ]; then
    inb="$HO_RUN_DIR/notify/inbox/$label.jsonl"
    [ -f "$inb" ] || { : > "$out"; return 0; }
    cp "$inb" "$out"
    return 0
  fi
  while IFS= read -r el; do argv+=("$el"); done < <(jq -r '.argv[]' <<<"$ch")
  ho_nt_exec "$out" /dev/null "${argv[@]}" read_replies || { ho_ledger_append notify-read-failed channel "$label"; return 1; }
}

# ho_nt_poll: read every active channel once; record first answers, note later ones. Prints
# "answer <ticket> <label>", "late <ticket> <label>" lines.
ho_nt_poll() {
  local chans ch label preset raw line id reply sender text auth ref qid ticket newest login body sf
  chans=$(ho_nt_channels) || return 78
  [ -f "$HO_RUN_DIR/notify/refs.jsonl" ] || return 0
  raw=$(mktemp "${TMPDIR:-/tmp}/ho-nr.XXXXXX") || return 1
  for ch in $(jq -c '.[]' <<<"$chans"); do
    label=$(jq -r .label <<<"$ch"); preset=$(jq -r .preset <<<"$ch")
    ho_nt_read "$ch" "$raw" || continue
    sf="$(ho_nt_dir seen)/$label"
    touch "$sf"
    while IFS= read -r line; do
      line=$(jq -c 'select(type == "object")' <<<"$line" 2>/dev/null) || continue
      [ -n "$line" ] || continue
      id=$(jq -r '.id // "" | tostring' <<<"$line")
      printf '%s' "$id" | grep -Eq "$HO_NT_REF_RE" || continue
      grep -Fqx -- "$id" "$sf" && continue
      reply=$(jq -r '.reply_to // "" | tostring' <<<"$line")
      ref=$(jq -c --arg l "$label" --arg r "$reply" 'select(.label == $l and .ref == $r)' "$HO_RUN_DIR/notify/refs.jsonl" | tail -n 1)
      if [ -z "$reply" ] || [ -z "$ref" ]; then
        # Not a reply to an open question: no answer, no ticket, no action (D37-NOTIFICATIONS-2).
        ho_ledger_append notify-ignored channel "$label" message "$id"
        printf '%s\n' "$id" >> "$sf"
        continue
      fi
      qid=$(jq -r .qid <<<"$ref"); ticket=$(jq -r .ticket <<<"$ref")
      newest=$(jq -r --arg t "$ticket" 'select(.ticket == $t) | .qid' "$HO_RUN_DIR/notify/refs.jsonl" | tail -n 1)
      if [ "$qid" = "$newest" ] && mkdir -p "$HO_RUN_DIR/notify/answered" && mkdir "$HO_RUN_DIR/notify/answered/$qid" 2>/dev/null; then
        sender=$(jq -r '.sender // "" | tostring' <<<"$line")
        auth=$(jq -r '.authenticated == true' <<<"$line")
        text=$(jq -r '.text // "" | tostring' <<<"$line")
        login=$(ho_nt_sender_login "$preset" "$sender" "$auth")
        body=$(mktemp "${TMPDIR:-/tmp}/ho-na.XXXXXX") || return 1
        printf '%s\n' "${text:0:4000}" | LC_ALL=C tr -d '\000-\010\013-\037\177' > "$body"
        if [ -n "$login" ]; then
          ho_tickets answer "$ticket" "$login" "$body" >/dev/null || { rm -f "$body"; rmdir "$HO_RUN_DIR/notify/answered/$qid"; echo "error $ticket $label"; continue; }
        else
          local sid
          sid=$(printf '%s:%s' "$preset" "$sender" | LC_ALL=C tr -c 'A-Za-z0-9@._:+-' '_' | cut -c 1-100)
          ho_tickets answer "$ticket" - "$body" "$sid" >/dev/null || { rm -f "$body"; rmdir "$HO_RUN_DIR/notify/answered/$qid"; echo "error $ticket $label"; continue; }
          login=-
        fi
        rm -f "$body"
        printf '%s\n' "$id" >> "$sf"
        ho_ledger_append notify-answer channel "$label" ticket "$ticket" question "$qid" by "$login"
        echo "answer $ticket $label"
      else
        # A later answer is never applied: the sender gets the tracker link (H-119).
        printf '%s\n' "$id" >> "$sf"
        body=$(mktemp "${TMPDIR:-/tmp}/ho-nl.XXXXXX") || return 1
        printf 'Answers to this question are already recorded: %s\nYour reply was not applied. Make any change directly in the tracker.\n' \
          "$(ho_nt_link "$ticket")" > "$body"
        ho_nt_deliver note "$ticket" - "$body" "" "$id" "$label" >/dev/null || true
        rm -f "$body"
        ho_ledger_append notify-late channel "$label" ticket "$ticket" question "$qid" message "$id"
        echo "late $ticket $label"
      fi
    done < "$raw"
  done
  rm -f "$raw"
}

# ---- connections check (H-123, D36) -------------------------------------------------------------

# notify check: one line per active channel and owner actions for the missing ones. Read-only.
ho_nt_check() {
  local chans ch label via fail=0 out uf
  chans=$(ho_nt_channels) || return 78
  if [ "$(jq length <<<"$chans")" -eq 0 ]; then
    echo "no channel: questions and answers stay in the tracker"
    return 0
  fi
  for ch in $(jq -c '.[]' <<<"$chans"); do
    label=$(jq -r .label <<<"$ch"); via=$(jq -r .via <<<"$ch")
    if [ "$via" = mcp ]; then
      echo "channel $label: mcp $(jq -r .mcp <<<"$ch"): the session checks the connector before the build"
      continue
    fi
    local -a argv=()
    while IFS= read -r el; do argv+=("$el"); done < <(jq -r '.argv[]' <<<"$ch")
    out=$(mktemp "${TMPDIR:-/tmp}/ho-nc.XXXXXX") || return 1
    if ho_nt_exec "$out" /dev/null "${argv[@]}" check; then
      echo "channel $label: ok"
    else
      fail=1
      echo "channel $label: the connection check failed"
      jq -r --arg p "$(jq -r .preset <<<"$ch")" '.[$p].owner_actions[]? | "  owner action: " + .' "$(ho_nt_presets)"
    fi
    rm -f "$out"
  done
  uf=$(ho_user_config)
  if ! jq -e '(.identities // null) | type == "array" and length > 0' "$uf" >/dev/null 2>&1; then
    echo "identity map: missing in the user config, so every channel author is unmapped (identities)"
  fi
  [ "$fail" -eq 0 ] || return 69
}

# ---- mcp route reports --------------------------------------------------------------------------

ho_nt_mcp_report() { # sent|failed <msg-id> [ref]
  local what=$1 id=${2-} ref=${3-} rec label
  printf '%s' "$id" | grep -Eq '^[0-9]+-[0-9a-f]{8}$' || { ho_nt_err "unknown message id: $id"; return 64; }
  rec="$HO_RUN_DIR/notify/msg/$id.json"
  [ -f "$rec" ] || { ho_nt_err "unknown message id: $id"; return 64; }
  label=$(jq -r --arg id "$id" 'select(.id == $id) | .label' "$HO_RUN_DIR/notify/outbox.jsonl" 2>/dev/null | tail -n 1)
  if [ "$what" = sent ]; then
    printf '%s' "$ref" | grep -Eq "$HO_NT_REF_RE" || { ho_nt_err "sent needs the channel's message ref"; return 64; }
    if [ "$(jq -r .kind "$rec")" = question ]; then
      jq -cn --arg l "$label" --arg ref "$ref" --slurpfile r "$rec" '{label: $l, ref: $ref, qid: $r[0].qid, ticket: $r[0].ticket}' \
        >> "$HO_RUN_DIR/notify/refs.jsonl"
    fi
    echo "OK sent $id"
  else
    ho_ledger_append notify-failed channel "$label" message "$id" route mcp
    if [ "$(jq -r .fallback "$rec")" = true ] && ho_nt_fallback "$id"; then echo "OK fell back $id"; else echo "OK failed $id"; fi
  fi
}

ho_nt_inbox() { # <label> <json-lines-file>
  local label=${1-} f=${2-}
  printf '%s' "$label" | grep -Eq "$HO_NT_LABEL_RE" || { ho_nt_err "bad label: $label"; return 64; }
  [ -f "$f" ] || { ho_nt_err "no file: $f"; return 64; }
  jq -c 'select(type == "object")' "$f" >> "$(ho_nt_dir inbox)/$label.jsonl" || { ho_nt_err "the file must hold JSON objects"; return 64; }
  echo "OK inbox $label"
}

ho_nt_usage() {
  cat >&2 <<'USAGE'
usage: harness notify check                         read-only connections check before the build (H-123)
       harness notify channels                      the active channels in priority order, as JSON
       harness notify <run-dir> event <event> <ticket|-> <text>   announce one run event (if on)
       harness notify <run-dir> question <ticket> <lines-file>    mirror a posted question
       harness notify <run-dir> poll                read replies once; record first answers
       harness notify <run-dir> sent <id> <ref> | failed <id>     mcp route: the session reports a send
       harness notify <run-dir> inbox <label> <file>              mcp route: replies the session read
events: question blocked taken done run-ended limit-pause orchestrator-down
USAGE
}

ho_notify_main() {
  case ${1-} in
    check) ho_nt_check ;;
    channels) ho_nt_channels ;;
    help | -h | --help) ho_nt_usage 2>&1 ;;
    '') ho_nt_usage; return 64 ;;
    *)
      ho_run_open "$1"; shift
      ho_tk_settings 2>/dev/null || true
      case ${1-} in
        event)
          [ $# -eq 4 ] || { ho_nt_usage; return 64; }
          case " $HO_NT_EVENTS " in *" $2 "*) ;; *) ho_nt_err "unknown event: $2"; return 64 ;; esac
          ho_nt_event "$2" "$3" "$4" ;;
        question) [ $# -eq 3 ] && [ -f "$3" ] || { ho_nt_usage; return 64; }; ho_nt_question "$2" "$3" ;;
        poll) ho_nt_poll ;;
        sent) [ $# -eq 3 ] || { ho_nt_usage; return 64; }; ho_nt_mcp_report sent "$2" "$3" ;;
        failed) [ $# -eq 2 ] || { ho_nt_usage; return 64; }; ho_nt_mcp_report failed "$2" ;;
        inbox) [ $# -eq 3 ] || { ho_nt_usage; return 64; }; ho_nt_inbox "$2" "$3" ;;
        *) ho_nt_usage; return 64 ;;
      esac ;;
  esac
}
