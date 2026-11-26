# shellcheck shell=bash
# Terminal adapter (design "Rebuild" reuse list: one terminal adapter, iTerm2 and tmux).
# The only file that talks to a terminal app. The Terminal.app backend is dropped.
#
# One interface, two backends. A session is addressed by the handle the backend returned
# when it opened the session: an iTerm2 session unique ID or a tmux pane ID. A handle is
# for addressing only; a session's identity is its process ID plus its session ID.
# Handles can be reused (a tmux pane ID after the server restarts, an iTerm2 window ID after
# the app restarts), so open tags the new session with its run, its owner and its session ID,
# and every later call acts only if the handle still carries all three, checked in the same
# call that acts. The owner is a tag made new for each launch: a resume reuses the session ID
# (review of wave 2, N2). The session ID ties the pane or tab to the process the close checks:
# a record that names another session's handle and owner still has its own session ID
# (review of wave 2, R1).
#
#   ho_term_backend                       print the backend: iterm2 or tmux
#   ho_term_open <group> <title> <launcher> <owner> <sid>   open a tab or pane that runs the
#                                         launcher, tag it with run, owner and session ID;
#                                         print the handle
#   ho_term_send <handle> <owner> <sid> <text>  type short control text, then a separate Enter
#   ho_term_type <handle> <owner> <sid> <text>  type short control text, no Enter (the caller
#                                         reads the input line again before ho_term_key enter)
#   ho_term_key <handle> <owner> <sid> enter|escape   press one key
#   ho_term_bytes <handle> <owner> <sid> <code>...    send control bytes (1-31, not 10 or 13)
#   ho_term_capture <handle> <owner> <sid> [lines] [styled]  print the tail of the session's
#                                         screen; "styled" keeps the colour codes where the
#                                         backend has them (tmux), so dim suggested text can be
#                                         told apart from typed text (H-099)
#   ho_term_close <handle> <owner> <sid>  close that one tab or pane (its process must be gone)
#   ho_term_probe                         check that the backend can be driven
#
# Return codes: 0 ok, 64 usage, 65 refused value, 66 handle not found or not tagged with this
# run, owner and session ID, 70 terminal failed.
# Settings: terminal.app = auto | iterm2 | tmux (default auto); terminal.enter_delay_seconds
# (default 2, as in 0.6.0; a whole number from 0 to 10) between typed text and its Enter. Needs HO_RUN_DIR and HO_RUN_ID.

# Values embedded into AppleScript or a tmux command are checked against a small character
# set instead of being escaped.
ho_term_safe() {
  case ${1-} in
    '' | *[!A-Za-z0-9._/:@=%-]*)
      printf 'harness: unsafe terminal value %s (allowed: A-Z a-z 0-9 . _ / : @ = %% -)\n' "${1-}" >&2
      return 65
      ;;
  esac
}

# Typed text: short control strings only (for example the exit command).
ho_term_text_ok() {
  case ${1-} in
    '' | *[!A-Za-z0-9\ ./:_-]*)
      printf 'harness: refusing to type %s (short control text only)\n' "${1-}" >&2
      return 65
      ;;
  esac
}

# The owner is the launch tag from the session's record, and the session ID is the record's
# session ID; both are lower-case UUIDs. An untagged session has empty tags, so an empty value
# would match it: it is refused.
ho_term_owner_ok() {
  case ${1-} in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
      ho_term_safe "${HO_RUN_ID-}" 2>/dev/null && return 0 ;;
  esac
  printf 'harness: terminal owner %s is not a launch tag, or HO_RUN_ID is unsafe\n' "${1-}" >&2
  return 65
}

# HO_TERM_BACKEND, when set, wins over the config: a close uses the backend its session was
# launched with, even if terminal.app changed since.
ho_term_backend() {
  local app
  app=${HO_TERM_BACKEND:-}
  [ -n "$app" ] || app=$(ho_cfg '.terminal.app' auto) || return 70
  case $app in
    iterm2 | tmux) printf '%s\n' "$app" ;;
    auto)
      if [ -d /Applications/iTerm.app ] && command -v osascript >/dev/null 2>&1; then
        echo iterm2
      elif command -v tmux >/dev/null 2>&1; then
        echo tmux
      else
        echo "harness: no terminal backend: install iTerm2 or tmux, or set terminal.app" >&2
        return 70
      fi
      ;;
    terminal)
      echo "harness: terminal.app=terminal (Terminal.app) is not supported; use iterm2 or tmux" >&2
      return 65
      ;;
    *)
      printf 'harness: unknown terminal.app %s; use auto, iterm2 or tmux\n' "$app" >&2
      return 65
      ;;
  esac
}

ho_term_open() {
  local group=${1-} title=${2-} launcher=${3-} owner=${4-} sid=${5-} backend
  [ -n "$group" ] && [ -n "$title" ] && [ -n "$launcher" ] || { echo "harness: term open <group> <title> <launcher> <owner> <sid>" >&2; return 64; }
  ho_term_safe "$group" && ho_term_safe "$title" && ho_term_safe "$launcher" && ho_term_owner_ok "$owner" && ho_term_owner_ok "$sid" || return 65
  backend=$(ho_term_backend) || return $?
  "ho_term_${backend}_open" "$group" "$title" "$launcher" "$owner" "$sid"
}

# ho_term_enter_delay: terminal.enter_delay_seconds as a JSON number, whole, from 0 to 10. A
# string, a non-number or a larger value is refused (78) before anything is typed, so a config value
# cannot hold a send open for long (Codex review, PR #95).
ho_term_enter_delay() {
  local v
  v=$(ho_cfg '.terminal.enter_delay_seconds | if . == null then null elif type == "number" then tostring else "x" end' 2) || return 78
  case $v in '' | *[!0-9]*) v=x ;; esac
  if [ "$v" = x ] || [ "${#v}" -gt 2 ] || [ "$((10#$v))" -gt 10 ]; then
    echo "harness: terminal.enter_delay_seconds must be a whole number from 0 to 10" >&2
    return 78
  fi
  printf '%s\n' "$((10#$v))"
}

ho_term_send() {
  local h=${1-} owner=${2-} sid=${3-} text=${4-} backend
  ho_term_safe "$h" && ho_term_owner_ok "$owner" && ho_term_owner_ok "$sid" || return 65
  ho_term_text_ok "$text" || return 65
  ho_term_enter_delay >/dev/null || return 78
  backend=$(ho_term_backend) || return $?
  "ho_term_${backend}_send" "$h" "$owner" "$sid" "$text"
}

ho_term_type() {
  local h=${1-} owner=${2-} sid=${3-} text=${4-} backend
  ho_term_safe "$h" && ho_term_owner_ok "$owner" && ho_term_owner_ok "$sid" || return 65
  ho_term_text_ok "$text" || return 65
  backend=$(ho_term_backend) || return $?
  "ho_term_${backend}_type" "$h" "$owner" "$sid" "$text"
}

ho_term_key() {
  local h=${1-} owner=${2-} sid=${3-} key=${4-} backend
  ho_term_safe "$h" && ho_term_owner_ok "$owner" && ho_term_owner_ok "$sid" || return 65
  case $key in enter | escape) ;; *) echo "harness: key must be enter or escape" >&2; return 64 ;; esac
  backend=$(ho_term_backend) || return $?
  "ho_term_${backend}_key" "$h" "$owner" "$sid" "$key"
}

# ho_term_bytes: control bytes only (for example a runtime's send-now chord). The byte values
# come from runtime data; the adapter holds no key name (D37-LIFECYCLE-4).
ho_term_bytes() {
  local h=${1-} owner=${2-} sid=${3-} b backend
  ho_term_safe "$h" && ho_term_owner_ok "$owner" && ho_term_owner_ok "$sid" || return 65
  shift 3 2>/dev/null || return 64
  [ $# -gt 0 ] || { echo "harness: bytes needs at least one code" >&2; return 64; }
  for b in "$@"; do
    case $b in '' | *[!0-9]* | 0*) echo "harness: control byte must be 1-31: $b" >&2; return 65 ;; esac
    [ "$b" -ge 1 ] && [ "$b" -le 31 ] || { echo "harness: control byte must be 1-31: $b" >&2; return 65; }
    # 10 and 13 act as Enter: never sent as a control byte (minor 12 of the PR #95 review).
    [ "$b" -ne 10 ] && [ "$b" -ne 13 ] || { echo "harness: control byte $b (line feed or carriage return) is refused" >&2; return 65; }
  done
  backend=$(ho_term_backend) || return $?
  for b in "$@"; do
    "ho_term_${backend}_byte" "$h" "$owner" "$sid" "$b" || return $?
  done
}

ho_term_capture() {
  local h=${1-} owner=${2-} sid=${3-} lines=${4:-40} styled=${5-} backend
  ho_term_safe "$h" && ho_term_owner_ok "$owner" && ho_term_owner_ok "$sid" || return 65
  case $lines in '' | *[!0-9]*) echo "harness: lines must be a number" >&2; return 64 ;; esac
  case $styled in '' | styled) ;; *) echo "harness: capture mode must be styled or empty" >&2; return 64 ;; esac
  backend=$(ho_term_backend) || return $?
  "ho_term_${backend}_capture" "$h" "$owner" "$sid" "$lines" "$styled"
}

ho_term_close() {
  local h=${1-} owner=${2-} sid=${3-} backend
  ho_term_safe "$h" && ho_term_owner_ok "$owner" && ho_term_owner_ok "$sid" || return 65
  backend=$(ho_term_backend) || return $?
  "ho_term_${backend}_close" "$h" "$owner" "$sid"
}

ho_term_probe() {
  local backend
  backend=$(ho_term_backend) || return $?
  case $backend in
    iterm2) osascript -e 'tell application "iTerm2" to count windows' >/dev/null 2>&1 || { echo "harness: iTerm2 cannot be driven (check the Automation permission)" >&2; return 70; } ;;
    tmux) ho_tmux -V >/dev/null 2>&1 || { echo "harness: tmux cannot be run" >&2; return 70; } ;;
  esac
  printf 'terminal OK backend=%s\n' "$backend"
}


# ---------------------------------------------------------------------- iTerm2
# The first session of a group opens a window; later sessions of the group open tabs in it.
# The group's window ID is kept in <run>/terminal/windows.json (outside sessions/, so no
# session name can collide with it). Window IDs are reused after iTerm2 restarts, so a
# stored window is used only while it still holds a session tagged with this run.
# Every session the harness opens carries three iTerm2 session variables: user.ho_run (the
# run ID), user.ho_session (the owner, the launch tag) and user.ho_session_id (the session ID).
# A session without all three is never written to, read or closed.
ho_term_windows_file() { printf '%s/terminal/windows.json\n' "$HO_RUN_DIR"; }

ho_term_iterm2_open() {
  local group=$1 title=$2 launcher=$3 owner=$4 sid=$5 f winid out w h
  f=$(ho_term_windows_file)
  mkdir -p "$(dirname "$f")"
  # A missing or unreadable group file only means "no window yet": start a fresh one.
  jq -e 'type == "object"' "$f" >/dev/null 2>&1 || printf '{}\n' | ho_atomic_write "$f" || return 70
  winid=$(jq -r --arg g "$group" '.[$g] // "" | strings' "$f")
  [ -z "$winid" ] || ho_term_safe "$winid" 2>/dev/null || winid=""
  # iTerm2 resolves a reference again on every event, and a loop variable or a created tab is
  # a position that names another session once windows or tabs move. So every reference here
  # ends in a filter on an identity: "first window whose id is <W>", and "first session of
  # (tab <k> of <that window>) whose unique ID is <U>". Such a reference reaches that one window
  # or session, or fails; it never reaches another one. Loops run over values only (IDs and
  # counts). The new session is found by value too (review of wave 2, R2): the IDs of the
  # windows, or of the sessions of the window, are read before and after the create, inside one
  # tell, and exactly one new ID must appear. Otherwise nothing is tagged or closed.
  # The stored window is used only while it holds a session tagged with this run. The new
  # session is tagged through its unique ID, only while it carries no tag yet; if the tags
  # cannot be set, it is closed the same way.
  out=$(osascript <<OSA
-- No "contents of" and no "repeat with x in" inside the iTerm2 tell: there "contents"
-- compiles to the session property of iTerm2 and fails with -1728 on the real app.
-- Loops inside the tell walk by index with "item i of".
on ho_flat(xs)
  set out to {}
  repeat with x in xs
    set v to (contents of x)
    if class of v is list then
      repeat with y in v
        set end of out to (contents of y)
      end repeat
    else
      set end of out to v
    end if
  end repeat
  return out
end ho_flat

tell application "iTerm2"
  set wid to missing value
  if "$winid" is not "" then
    try
      set cand to ("$winid" as integer)
      repeat with k from 1 to (count of tabs of (first window whose id is cand))
        set us to (unique ID of every session of (tab k of (first window whose id is cand)))
        repeat with j from 1 to (count of us)
          set u1 to (item j of us)
          try
            tell (first session of (tab k of (first window whose id is cand)) whose unique ID is u1)
              if (variable named "user.ho_run") is "$HO_RUN_ID" then set wid to cand
            end tell
          end try
        end repeat
      end repeat
    end try
  end if
  if wid is missing value then
    set ws0 to (id of every window)
    create window with default profile command "/bin/bash $launcher"
    set ws1 to (id of every window)
    set nws to {}
    repeat with i from 1 to (count of ws1)
      set x to (item i of ws1)
      if ws0 does not contain x then set end of nws to x
    end repeat
    if (count of nws) is not 1 then return "ambiguous " & (count of nws) & " new windows"
    set wid to (item 1 of nws)
    set us0 to {}
    tell (first window whose id is wid)
      set us1 to (unique ID of every session of every tab)
    end tell
  else
    tell (first window whose id is wid)
      set us0 to (unique ID of every session of every tab)
      create tab with default profile command "/bin/bash $launcher"
      set us1 to (unique ID of every session of every tab)
    end tell
  end if
  set f0 to my ho_flat(us0)
  set fresh to {}
  set f1 to my ho_flat(us1)
  repeat with i from 1 to (count of f1)
    set x to (item i of f1)
    if f0 does not contain x then set end of fresh to x
  end repeat
  if (count of fresh) is not 1 then return "ambiguous " & (count of fresh) & " new sessions"
  set u to (item 1 of fresh)
  repeat with k from 1 to (count of tabs of (first window whose id is wid))
    if (unique ID of every session of (tab k of (first window whose id is wid))) contains u then
      tell (first session of (tab k of (first window whose id is wid)) whose unique ID is u)
        set clean to true
        set vns to {"user.ho_run", "user.ho_session", "user.ho_session_id"}
        repeat with i from 1 to (count of vns)
          set v to ""
          try
            set v to (variable named (item i of vns))
          end try
          if v is not missing value and v is not "" then set clean to false
        end repeat
        if not clean then return "taken"
        set tagged to false
        try
          set variable named "user.ho_run" to "$HO_RUN_ID"
          set variable named "user.ho_session" to "$owner"
          set variable named "user.ho_session_id" to "$sid"
          set tagged to true
        end try
        if not tagged then
          close
          return "notag"
        end if
        try
          set name to "$title"
        end try
      end tell
      return (wid as string) & " " & u
    end if
  end repeat
  return "lost"
end tell
OSA
) || { echo "harness: iTerm2 did not open a session (check the Automation permission)" >&2; return 70; }
  case $out in
    notag)
      echo "harness: iTerm2 could not tag the new session (session variables need iTerm2 3.3 or later); it was closed" >&2
      return 70
      ;;
    lost)
      echo "harness: the new iTerm2 session was gone before it could be tagged" >&2
      return 70
      ;;
    ambiguous*)
      printf 'harness: iTerm2 open saw %s, not exactly one; nothing was tagged or closed\n' "${out#ambiguous }" >&2
      return 70
      ;;
    taken)
      echo "harness: the new iTerm2 session already carries a tag; nothing was tagged or closed" >&2
      return 70
      ;;
  esac
  w=${out%% *}
  h=${out#* }
  ho_term_safe "$w" 2>/dev/null && ho_term_safe "$h" 2>/dev/null || { echo "harness: iTerm2 returned no usable session ID" >&2; return 70; }
  # The session already runs: a failed group write only costs the next tab its window.
  jq --arg g "$group" --arg w "$w" '.[$g] = $w' "$f" 2>/dev/null | ho_atomic_write "$f" \
    || echo "harness: warning: could not record the window of group $group" >&2
  printf '%s\n' "$h"
}

# ho_term_iterm2_do <handle> <owner> <sid> <AppleScript body>: run the body against that one
# session, only if it carries this run's tag, the owner's tag and the session ID. The body runs
# inside a tell to the session's pinned reference (see open), right after the check in the same
# tell, so every event of check and body reaches the session with that unique ID or fails.
ho_term_iterm2_do() {
  local h=$1 owner=$2 sid=$3 body=$4 r
  r=$(osascript <<OSA
tell application "iTerm2"
  set wids to (id of every window)
  repeat with i from 1 to (count of wids)
    set w1 to (item i of wids)
    set n to 0
    try
      set n to (count of tabs of (first window whose id is w1))
    end try
    repeat with k from 1 to n
      set hit to false
      try
        set hit to ((unique ID of every session of (tab k of (first window whose id is w1))) contains "$h")
      end try
      if hit then
        tell (first session of (tab k of (first window whose id is w1)) whose unique ID is "$h")
          set ho_tag to ""
          try
            set ho_tag to (unique ID) & "/" & (variable named "user.ho_run") & "/" & (variable named "user.ho_session") & "/" & (variable named "user.ho_session_id")
          end try
          if ho_tag is not "$h/$HO_RUN_ID/$owner/$sid" then return "notmine"
          $body
        end tell
        return "ok"
      end if
    end repeat
  end repeat
  return "notfound"
end tell
OSA
) || { echo "harness: iTerm2 call failed" >&2; return 70; }
  case $r in
    notfound) printf 'harness: no iTerm2 session %s\n' "$h" >&2; return 66 ;;
    notmine) printf 'harness: iTerm2 session %s does not carry tag %s and session ID %s of run %s; nothing was done\n' "$h" "$owner" "$sid" "$HO_RUN_ID" >&2; return 66 ;;
  esac
  printf '%s\n' "$r"
}

ho_term_iterm2_type() {
  ho_term_iterm2_do "$1" "$2" "$3" "write text \"$4\" newline NO" >/dev/null
}

ho_term_iterm2_send() {
  ho_term_iterm2_type "$1" "$2" "$3" "$4" || return $?
  local d
  d=$(ho_term_enter_delay) || return 78
  sleep "$d"
  ho_term_iterm2_key "$1" "$2" "$3" enter
}

ho_term_iterm2_key() {
  case $4 in
    enter) ho_term_iterm2_do "$1" "$2" "$3" 'write text "" newline YES' >/dev/null ;;
    escape) ho_term_iterm2_do "$1" "$2" "$3" 'write text (ASCII character 27) newline NO' >/dev/null ;;
  esac
}

ho_term_iterm2_byte() {
  ho_term_iterm2_do "$1" "$2" "$3" "write text (ASCII character $4) newline NO" >/dev/null
}

# iTerm2 "contents" has no colours, so a styled capture is a plain one there.
ho_term_iterm2_capture() {
  local out
  out=$(ho_term_iterm2_do "$1" "$2" "$3" 'return contents') || return $?
  # iTerm2 pads the screen with blank rows: drop trailing blank lines first.
  printf '%s\n' "$out" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' | tail -n "$4"
}

ho_term_iterm2_close() { ho_term_iterm2_do "$1" "$2" "$3" 'close' >/dev/null; }

# ------------------------------------------------------------------------ tmux
# The harness uses its own tmux server (socket ho-harness), one tmux session per run, and one
# window per harness session. Pane IDs are unique only while the server lives: after it exits
# and starts again, a new pane can get the same ID under the same session name. So open tags
# each pane with its owner and its session ID (pane options @ho_tag and @ho_session_id, tmux 3.0
# or later), and every call that reaches a pane checks pane ID, tmux session (named after the
# run), owner and session ID inside the same tmux command that acts.
ho_tmux() { tmux -L ho-harness "$@"; }
ho_term_tmux_session() { printf 'ho-%s\n' "$HO_RUN_ID"; }
HO_TMUX_OWNER_FMT='#{pane_id}/#{session_name}/#{@ho_tag}/#{@ho_session_id}'
HO_TMUX_NOT_MINE=ho-not-this-session

# ho_term_tmux_if <pane> <format> <expected> <tmux command>: the tmux server runs the command
# only if the format, expanded for that pane, equals <expected>. Prints what the command
# prints. Returns 66 when the pane is missing or the check fails (nothing was run).
ho_term_tmux_if() {
  local out
  out=$(ho_tmux if-shell -F -t "$1" "#{==:$2,$3}" "$4" "display-message -p $HO_TMUX_NOT_MINE" 2>/dev/null) || return 66
  [ "$out" != "$HO_TMUX_NOT_MINE" ] || return 66
  printf '%s' "$out"
}

ho_term_tmux_refused() {
  printf 'harness: tmux pane %s does not carry tag %s and session ID %s of run %s; nothing was done\n' "$1" "$2" "$3" "$HO_RUN_ID" >&2
  return 66
}

ho_term_tmux_open() {
  local title=$2 launcher=$3 owner=$4 sid=$5 ses out h ppid
  ses=$(ho_term_tmux_session)
  ho_term_safe "$ses" || return 65
  if ho_tmux has-session -t "$ses" 2>/dev/null; then
    out=$(ho_tmux new-window -d -t "$ses" -n "$title" -P -F '#{pane_id} #{pane_pid}' "/bin/bash '$launcher'") || { echo "harness: tmux did not open a window" >&2; return 70; }
  else
    out=$(ho_tmux new-session -d -s "$ses" -n "$title" -P -F '#{pane_id} #{pane_pid}' "/bin/bash '$launcher'") || { echo "harness: tmux did not open a session" >&2; return 70; }
  fi
  h=${out%% *}
  ppid=${out#* }
  ho_term_safe "$h" 2>/dev/null || { echo "harness: tmux returned no usable pane ID" >&2; return 70; }
  case $ppid in '' | *[!0-9]*) echo "harness: tmux returned no pane process ID" >&2; return 70 ;; esac
  # Tag the pane. The check names the pane's own first process and two empty tags, so the tags
  # can land only on this new pane. If it fails, the pane is closed under the same check.
  if ! ho_term_tmux_if "$h" '#{pane_id}/#{session_name}/#{pane_pid}/#{@ho_tag}/#{@ho_session_id}' "$h/$ses/$ppid//" \
    "set-option -p -t $h @ho_tag $owner ; set-option -p -t $h @ho_session_id $sid" >/dev/null; then
    ho_term_tmux_if "$h" '#{pane_id}/#{session_name}/#{pane_pid}' "$h/$ses/$ppid" "kill-pane -t $h" >/dev/null || true
    echo "harness: tmux could not tag the new pane (it ended at once, or tmux is older than 3.0); nothing is left open" >&2
    return 70
  fi
  printf '%s\n' "$h"
}

ho_term_tmux_type() {
  ho_term_tmux_if "$1" "$HO_TMUX_OWNER_FMT" "$1/$(ho_term_tmux_session)/$2/$3" "send-keys -t $1 -l '$4'" >/dev/null \
    || { ho_term_tmux_refused "$1" "$2" "$3"; return 66; }
}

ho_term_tmux_send() {
  ho_term_tmux_type "$1" "$2" "$3" "$4" || return $?
  local d
  d=$(ho_term_enter_delay) || return 78
  sleep "$d"
  ho_term_tmux_key "$1" "$2" "$3" enter
}

# A byte goes as one hex key (send-keys -H, tmux 3.0 or later), so it is never read as a key name.
ho_term_tmux_byte() {
  ho_term_tmux_if "$1" "$HO_TMUX_OWNER_FMT" "$1/$(ho_term_tmux_session)/$2/$3" "send-keys -t $1 -H $(printf '%02x' "$4")" >/dev/null \
    || { ho_term_tmux_refused "$1" "$2" "$3"; return 66; }
}

ho_term_tmux_key() {
  local k
  case $4 in enter) k=Enter ;; escape) k=Escape ;; esac
  ho_term_tmux_if "$1" "$HO_TMUX_OWNER_FMT" "$1/$(ho_term_tmux_session)/$2/$3" "send-keys -t $1 $k" >/dev/null \
    || { ho_term_tmux_refused "$1" "$2" "$3"; return 66; }
}

# Capture reads under the same check, in one tmux command. A screen that shows only the refusal
# marker reads as a refusal, which is the safe side.
ho_term_tmux_capture() {
  local out e=""
  [ "${5-}" != styled ] || e="-e "
  out=$(ho_term_tmux_if "$1" "$HO_TMUX_OWNER_FMT" "$1/$(ho_term_tmux_session)/$2/$3" "capture-pane ${e}-p -t $1") \
    || { ho_term_tmux_refused "$1" "$2" "$3"; return 66; }
  printf '%s\n' "$out" | tail -n "$4"
}

ho_term_tmux_close() {
  ho_term_tmux_if "$1" "$HO_TMUX_OWNER_FMT" "$1/$(ho_term_tmux_session)/$2/$3" "kill-pane -t $1" >/dev/null \
    || { ho_term_tmux_refused "$1" "$2" "$3"; return 66; }
}
