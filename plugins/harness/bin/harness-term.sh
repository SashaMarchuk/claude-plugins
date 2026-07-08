#!/usr/bin/env bash
# term.sh — terminal backends (iterm2 | terminal | tmux). The only file that talks to a terminal app.
# Usage:
#   term.sh spawn   <group> <title> <launcher-abs-path>   # window per group; later spawns become tabs
#   term.sh send    <tty> <text>                          # text, then a SEPARATE Enter (paste-swallow fix, L5)
#   term.sh key     <tty> <enter|escape>                  # single control key
#   term.sh capture <tty> [lines]                         # tail of session contents (default 40)
#   term.sh close   <tty>                                 # close ONE session; never a window (L11)
#   term.sh probe                                         # verify automation permission works
# Sessions are addressed by tty (window ids drift/collide, L10). Group→window map: state/windows.json.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hlib.sh"

BACKEND=$(cfg '.terminal.app' 'auto')
if [ "$BACKEND" = "auto" ]; then
  if [ -d "/Applications/iTerm.app" ]; then BACKEND=iterm2
  elif [ "$(uname)" = "Darwin" ]; then BACKEND=terminal
  else BACKEND=tmux; fi
fi
FULLSCREEN=$(cfg '.terminal.fullscreen' 'false')

win_file() { printf '%s/state/windows.json\n' "$(hcurrent_run)"; }

win_get() { # win_get <group> → window id or empty
  local f; f=$(win_file)
  [ -f "$f" ] && jq -er --arg g "$1" '.[$g] // empty' "$f" 2>/dev/null || true
}
win_set() { # win_set <group> <id>
  local f tmp; f=$(win_file)
  [ -f "$f" ] || echo '{}' > "$f"
  tmp=$(jq --arg g "$1" --arg id "$2" '.[$g]=$id' "$f") && printf '%s\n' "$tmp" | atomic_write "$f"
}

# ---------------------------------------------------------------------- iterm2
# Launchers are always plain files executed as `bash <path>` — no inline prompt text ever
# reaches AppleScript (L1). Titles/paths are validated to a safe charset instead of escaped.
assert_osa_safe() { # conservative allowlist for strings embedded in AppleScript
  case "${1:?}" in
    *[!A-Za-z0-9._/:@=-]*) echo "ERROR: unsafe char in '$1' (allowed: A-Za-z0-9 . _ / : @ = -)" >&2; return 65 ;;
    *) return 0 ;;
  esac
}

iterm_screen_bounds() { # → "W H" of main display, best effort
  osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null \
    | awk -F', ' '{print $3, $4}' || true
}

iterm_spawn() { # <group> <title> <launcher>
  local group="$1" title="$2" launcher="$3" winid newid cmd
  assert_osa_safe "$title"; assert_osa_safe "$launcher"
  cmd="/bin/bash $launcher"
  winid=$(win_get "$group")
  newid=$(osascript <<OSA
tell application "iTerm2"
  activate
  set target to missing value
  if "$winid" is not "" then
    repeat with w in windows
      try
        if (id of w as string) is "$winid" then set target to w
      end try
    end repeat
  end if
  if target is missing value then
    set target to (create window with default profile command "$cmd")
    try
      tell current session of target to set name to "$title"
    end try
  else
    tell target
      set t to (create tab with default profile command "$cmd")
      try
        tell current session of t to set name to "$title"
      end try
    end tell
  end if
  return (id of target as string)
end tell
OSA
) || { echo "ERROR: iTerm spawn failed (check Automation permission: System Settings → Privacy & Security → Automation)" >&2; return 70; }
  [ -n "$newid" ] && win_set "$group" "$newid"
  # fullscreen best-effort on first window of a group only
  if [ "$FULLSCREEN" = "true" ] && [ -z "$winid" ]; then
    local wh; wh=$(iterm_screen_bounds)
    if [ -n "$wh" ]; then
      osascript >/dev/null 2>&1 <<OSA || true
tell application "iTerm2"
  repeat with w in windows
    try
      if (id of w as string) is "$newid" then set bounds of w to {0, 0, ${wh% *}, ${wh#* }}
    end try
  end repeat
end tell
OSA
    fi
  fi
}

iterm_session_do() { # <tty> <applescript-body-using-variable s>; runs body against the matching session
  local tty="$1" body="$2"
  assert_osa_safe "$tty"
  osascript <<OSA
tell application "iTerm2"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        try
          if (tty of s) is "$tty" then
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
}

iterm_send() { # <tty> <text> — newline=false, then a separate Enter after a beat (L5)
  local tty="$1" text="$2" r
  if printf '%s' "$text" | LC_ALL=C grep -q '[^A-Za-z0-9 ./:_-]'; then
    echo "ERROR: unsafe control text '$text' (send is for short control strings only)" >&2; return 65
  fi
  r=$(iterm_session_do "$tty" "tell s to write text \"$text\" newline NO")
  [ "$r" = "ok" ] || { echo "ERROR: session $tty not found" >&2; return 66; }
  sleep 2
  iterm_key "$tty" enter
}

iterm_key() { # <tty> <enter|escape>
  local tty="$1" key="$2" r
  case "$key" in enter|escape) ;; *) echo "bad key" >&2; return 64 ;; esac
  if [ "$key" = "enter" ]; then
    r=$(iterm_session_do "$tty" "tell s to write text \"\" newline YES")
  else
    r=$(iterm_session_do "$tty" "tell s to write text (ASCII character 27) newline NO")
  fi
  [ "$r" = "ok" ] || { echo "ERROR: session $tty not found" >&2; return 66; }
}

iterm_capture() { # <tty> [lines]
  local tty="$1" lines="${2:-40}" out
  out=$(iterm_session_do "$tty" "return (contents of s)") || return 66
  [ "$out" = "notfound" ] && { echo "ERROR: session $tty not found" >&2; return 66; }
  # iTerm returns the whole screen buffer padded with blank rows — drop trailing blanks first
  printf '%s\n' "$out" | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' | tail -n "$lines"
}

iterm_close() { # <tty> — close ONE session; caller guarantees its job already ended
  local tty="$1" r
  r=$(iterm_session_do "$tty" "tell s to close")
  [ "$r" = "ok" ] || { echo "ERROR: session $tty not found (already closed?)" >&2; return 66; }
}

# ------------------------------------------------------------------ Terminal.app
term_app_spawn() { # <group> <title> <launcher> — Terminal.app has weaker addressing; new window per spawn
  local launcher="$3"
  assert_osa_safe "$launcher"
  osascript >/dev/null <<OSA || { echo "ERROR: Terminal.app spawn failed" >&2; return 70; }
tell application "Terminal"
  activate
  do script "exec /bin/bash $launcher"
end tell
OSA
}
term_app_by_tty() { # <tty> <verb: capture|close|send-enter>
  local tty="$1" verb="$2"
  assert_osa_safe "$tty"
  case "$verb" in
    capture) osascript -e "tell application \"Terminal\" to get contents of (first tab of (first window whose tty of selected tab is \"$tty\"))" 2>/dev/null ;;
    close)   osascript -e "tell application \"Terminal\" to close (first window whose tty of selected tab is \"$tty\")" 2>/dev/null ;;
  esac
}

# ----------------------------------------------------------------------- tmux
tmux_session() { printf 'harness-%s\n' "$(basename "$(hcurrent_run)")"; }
tmux_spawn() { # <group> <title> <launcher>
  local ses title="$2" launcher="$3"
  ses=$(tmux_session)
  if ! tmux has-session -t "$ses" 2>/dev/null; then
    tmux new-session -d -s "$ses" -n "$title" "/bin/bash $launcher"
  else
    tmux new-window -t "$ses" -n "$title" "/bin/bash $launcher"
  fi
}
tmux_pane_by_tty() { # <tty> → pane id
  tmux list-panes -a -F '#{pane_tty} #{pane_id}' 2>/dev/null | awk -v t="/dev/$1" '$1==t{print $2; exit}'
}
tmux_send() { local p; p=$(tmux_pane_by_tty "$1") || true; [ -n "$p" ] || { echo "ERROR: pane for $1 not found" >&2; return 66; }
  tmux send-keys -t "$p" "$2"; sleep 2; tmux send-keys -t "$p" Enter; }
tmux_key() { local p k; p=$(tmux_pane_by_tty "$1"); [ -n "$p" ] || { echo "ERROR: pane for $1 not found" >&2; return 66; }
  case "$2" in enter) k=Enter ;; escape) k=Escape ;; *) return 64 ;; esac; tmux send-keys -t "$p" "$k"; }
tmux_capture() { local p; p=$(tmux_pane_by_tty "$1"); [ -n "$p" ] || { echo "ERROR: pane for $1 not found" >&2; return 66; }
  tmux capture-pane -p -t "$p" | tail -n "${2:-40}"; }
tmux_close() { local p; p=$(tmux_pane_by_tty "$1"); [ -n "$p" ] || { echo "ERROR: pane for $1 not found" >&2; return 66; }
  tmux kill-pane -t "$p"; }

# -------------------------------------------------------------------- dispatch
# tty args are accepted with or without the /dev/ prefix; normalized to short form (ttysNNN).
norm_tty() { printf '%s\n' "${1#/dev/}"; }

cmd="${1:?usage: term.sh spawn|send|key|capture|close|probe ...}"; shift || true
case "$BACKEND:$cmd" in
  *:probe)
    case "$BACKEND" in
      iterm2)   osascript -e 'tell application "iTerm2" to count windows' >/dev/null || exit 70 ;;
      terminal) osascript -e 'tell application "Terminal" to count windows' >/dev/null || exit 70 ;;
      tmux)     tmux -V >/dev/null || exit 70 ;;
    esac
    echo "OK backend=$BACKEND" ;;
  iterm2:spawn)   iterm_spawn "${1:?group}" "${2:?title}" "${3:?launcher}" ;;
  iterm2:send)    iterm_send "/dev/$(norm_tty "${1:?tty}")" "${2:?text}" ;;
  iterm2:key)     iterm_key "/dev/$(norm_tty "${1:?tty}")" "${2:?key}" ;;
  iterm2:capture) iterm_capture "/dev/$(norm_tty "${1:?tty}")" "${2:-40}" ;;
  iterm2:close)   iterm_close "/dev/$(norm_tty "${1:?tty}")" ;;
  terminal:spawn)   term_app_spawn "${1:?group}" "${2:?title}" "${3:?launcher}" ;;
  terminal:capture) term_app_by_tty "$(norm_tty "${1:?tty}")" capture | tail -n "${2:-40}" ;;
  terminal:close)   term_app_by_tty "$(norm_tty "${1:?tty}")" close ;;
  terminal:send|terminal:key)
    echo "ERROR: send/key not supported on Terminal.app backend — use iterm2 or tmux for watch features" >&2; exit 64 ;;
  tmux:spawn)   tmux_spawn "${1:?group}" "${2:?title}" "${3:?launcher}" ;;
  tmux:send)    tmux_send "$(norm_tty "${1:?tty}")" "${2:?text}" ;;
  tmux:key)     tmux_key "$(norm_tty "${1:?tty}")" "${2:?key}" ;;
  tmux:capture) tmux_capture "$(norm_tty "${1:?tty}")" "${2:-40}" ;;
  tmux:close)   tmux_close "$(norm_tty "${1:?tty}")" ;;
  *) echo "usage: term.sh spawn|send|key|capture|close|probe" >&2; exit 64 ;;
esac
