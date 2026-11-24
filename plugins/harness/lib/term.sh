# shellcheck shell=bash
# Terminal adapter (design "Rebuild" reuse list: one terminal adapter, iTerm2 and tmux).
# The only file that talks to a terminal app. The Terminal.app backend is dropped.
#
# One interface, two backends. A session is addressed by the handle the backend returned
# when it opened the session: an iTerm2 session unique ID or a tmux pane ID. A handle is
# for addressing only; a session's identity is its process ID plus its session ID.
#
#   ho_term_backend                       print the backend: iterm2 or tmux
#   ho_term_open <group> <title> <launcher>   open a tab or pane that runs the launcher; print the handle
#   ho_term_send <handle> <text>          type short control text, then a separate Enter
#   ho_term_key <handle> enter|escape     press one key
#   ho_term_capture <handle> [lines]      print the tail of the session's screen
#   ho_term_close <handle>                close that one tab or pane (its process must be gone)
#   ho_term_probe                         check that the backend can be driven
#
# Return codes: 0 ok, 64 usage, 65 refused value, 66 handle not found, 70 terminal failed.
# Settings: terminal.app = auto | iterm2 | tmux (default auto); terminal.enter_delay_seconds
# (default 1) between typed text and its Enter. Needs HO_RUN_DIR and HO_RUN_ID.

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
  local group=${1-} title=${2-} launcher=${3-} backend
  [ -n "$group" ] && [ -n "$title" ] && [ -n "$launcher" ] || { echo "harness: term open <group> <title> <launcher>" >&2; return 64; }
  ho_term_safe "$group" && ho_term_safe "$title" && ho_term_safe "$launcher" || return 65
  backend=$(ho_term_backend) || return $?
  "ho_term_${backend}_open" "$group" "$title" "$launcher"
}

ho_term_send() {
  local h=${1-} text=${2-} backend
  ho_term_safe "$h" || return 65
  ho_term_text_ok "$text" || return 65
  backend=$(ho_term_backend) || return $?
  "ho_term_${backend}_send" "$h" "$text"
}

ho_term_key() {
  local h=${1-} key=${2-} backend
  ho_term_safe "$h" || return 65
  case $key in enter | escape) ;; *) echo "harness: key must be enter or escape" >&2; return 64 ;; esac
  backend=$(ho_term_backend) || return $?
  "ho_term_${backend}_key" "$h" "$key"
}

ho_term_capture() {
  local h=${1-} lines=${2:-40} backend
  ho_term_safe "$h" || return 65
  case $lines in '' | *[!0-9]*) echo "harness: lines must be a number" >&2; return 64 ;; esac
  backend=$(ho_term_backend) || return $?
  "ho_term_${backend}_capture" "$h" "$lines"
}

ho_term_close() {
  local h=${1-} backend
  ho_term_safe "$h" || return 65
  backend=$(ho_term_backend) || return $?
  "ho_term_${backend}_close" "$h"
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
# The group's window ID is kept in <run>/sessions/windows.json.
ho_term_windows_file() { printf '%s/sessions/windows.json\n' "$HO_RUN_DIR"; }

ho_term_iterm2_open() {
  local group=$1 title=$2 launcher=$3 f winid out w h
  f=$(ho_term_windows_file)
  mkdir -p "$(dirname "$f")"
  # A missing or unreadable group file only means "no window yet": start a fresh one.
  jq -e 'type == "object"' "$f" >/dev/null 2>&1 || printf '{}\n' | ho_atomic_write "$f" || return 70
  winid=$(jq -r --arg g "$group" '.[$g] // "" | strings' "$f")
  [ -z "$winid" ] || ho_term_safe "$winid" 2>/dev/null || winid=""
  out=$(osascript <<OSA
tell application "iTerm2"
  set w to missing value
  repeat with x in windows
    try
      if (id of x as string) is "$winid" then set w to x
    end try
  end repeat
  if w is missing value then
    set w to (create window with default profile command "/bin/bash $launcher")
    set s to current session of w
  else
    tell w to set t to (create tab with default profile command "/bin/bash $launcher")
    set s to current session of t
  end if
  try
    tell s to set name to "$title"
  end try
  return (id of w as string) & " " & (unique id of s)
end tell
OSA
) || { echo "harness: iTerm2 did not open a session (check the Automation permission)" >&2; return 70; }
  w=${out%% *}
  h=${out#* }
  ho_term_safe "$w" 2>/dev/null && ho_term_safe "$h" 2>/dev/null || { echo "harness: iTerm2 returned no usable session ID" >&2; return 70; }
  # The session already runs: a failed group write only costs the next tab its window.
  jq --arg g "$group" --arg w "$w" '.[$g] = $w' "$f" 2>/dev/null | ho_atomic_write "$f" \
    || echo "harness: warning: could not record the window of group $group" >&2
  printf '%s\n' "$h"
}

# ho_term_iterm2_do <handle> <AppleScript body using s>: run the body against that one session.
ho_term_iterm2_do() {
  local h=$1 body=$2 r
  r=$(osascript <<OSA
tell application "iTerm2"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        try
          if (unique id of s) is "$h" then
            $body
            return "ok"
          end if
        end try
      end repeat
    end repeat
  end repeat
  return "notfound"
end tell
OSA
) || { echo "harness: iTerm2 call failed" >&2; return 70; }
  if [ "$r" = notfound ]; then
    printf 'harness: no iTerm2 session %s\n' "$h" >&2
    return 66
  fi
  printf '%s\n' "$r"
}

ho_term_iterm2_send() {
  ho_term_iterm2_do "$1" "tell s to write text \"$2\" newline NO" >/dev/null || return $?
  sleep "$(ho_cfg_int '.terminal.enter_delay_seconds' 1)"
  ho_term_iterm2_key "$1" enter
}

ho_term_iterm2_key() {
  case $2 in
    enter) ho_term_iterm2_do "$1" 'tell s to write text "" newline YES' >/dev/null ;;
    escape) ho_term_iterm2_do "$1" 'tell s to write text (ASCII character 27) newline NO' >/dev/null ;;
  esac
}

ho_term_iterm2_capture() {
  local out
  out=$(ho_term_iterm2_do "$1" 'return (contents of s)') || return $?
  # iTerm2 pads the screen with blank rows: drop trailing blank lines first.
  printf '%s\n' "$out" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' | tail -n "$2"
}

ho_term_iterm2_close() { ho_term_iterm2_do "$1" 'tell s to close' >/dev/null; }

# ------------------------------------------------------------------------ tmux
# The harness uses its own tmux server (socket ho-harness), one tmux session per run, and one
# window per harness session. Pane IDs are unique only within one server, so every call
# that reaches a pane first checks that the pane belongs to this run's tmux session.
ho_tmux() { tmux -L ho-harness "$@"; }
ho_term_tmux_session() { printf 'ho-%s\n' "$HO_RUN_ID"; }

ho_term_tmux_open() {
  local title=$2 launcher=$3 ses h
  ses=$(ho_term_tmux_session)
  ho_term_safe "$ses" || return 65
  if ho_tmux has-session -t "$ses" 2>/dev/null; then
    h=$(ho_tmux new-window -d -t "$ses" -n "$title" -P -F '#{pane_id}' "/bin/bash '$launcher'") || { echo "harness: tmux did not open a window" >&2; return 70; }
  else
    h=$(ho_tmux new-session -d -s "$ses" -n "$title" -P -F '#{pane_id}' "/bin/bash '$launcher'") || { echo "harness: tmux did not open a session" >&2; return 70; }
  fi
  ho_term_safe "$h" 2>/dev/null || { echo "harness: tmux returned no usable pane ID" >&2; return 70; }
  printf '%s\n' "$h"
}

# ho_term_tmux_mine <pane>: 0 when the pane exists and belongs to this run's tmux session.
ho_term_tmux_mine() {
  local ses
  ses=$(ho_tmux display-message -p -t "$1" '#{session_name}' 2>/dev/null) || ses=""
  [ "$ses" = "$(ho_term_tmux_session)" ] && return 0
  printf 'harness: no tmux pane %s in run %s\n' "$1" "$HO_RUN_ID" >&2
  return 66
}

ho_term_tmux_send() {
  ho_term_tmux_mine "$1" || return 66
  ho_tmux send-keys -t "$1" -l "$2" 2>/dev/null || { printf 'harness: no tmux pane %s\n' "$1" >&2; return 66; }
  sleep "$(ho_cfg_int '.terminal.enter_delay_seconds' 1)"
  ho_term_tmux_key "$1" enter
}

ho_term_tmux_key() {
  local k
  case $2 in enter) k=Enter ;; escape) k=Escape ;; esac
  ho_term_tmux_mine "$1" || return 66
  ho_tmux send-keys -t "$1" "$k" 2>/dev/null || { printf 'harness: no tmux pane %s\n' "$1" >&2; return 66; }
}

ho_term_tmux_capture() {
  local out
  ho_term_tmux_mine "$1" || return 66
  out=$(ho_tmux capture-pane -p -t "$1" 2>/dev/null) || { printf 'harness: no tmux pane %s\n' "$1" >&2; return 66; }
  printf '%s\n' "$out" | tail -n "$2"
}

ho_term_tmux_close() {
  ho_term_tmux_mine "$1" || return 66
  ho_tmux kill-pane -t "$1" 2>/dev/null || { printf 'harness: no tmux pane %s\n' "$1" >&2; return 66; }
}
