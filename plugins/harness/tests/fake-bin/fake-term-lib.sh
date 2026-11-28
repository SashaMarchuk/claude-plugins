# shellcheck shell=bash
# Shared state for the fake terminals (fake tmux, fake osascript). Not a command.
# State lives in $HO_FAKE_TERM_DIR (default $HOME/fake-term):
#   calls.log        one line per call: <tool> <op> <handle> [text]
#   <h>.in           text typed into the session (Enter adds a newline, Escape adds <ESC>)
#   <h>.out          what the session printed
#   <h>.pid          the PID of the command the terminal started
#   <h>.closed       present once the terminal closed the session
#   next             counter for new handles
ft_dir=${HO_FAKE_TERM_DIR:-$HOME/fake-term}
mkdir -p "$ft_dir"
ft_file() { printf '%s/%s' "$ft_dir" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9-' '_')"; }
ft_log() { printf '%s\n' "$*" >> "$ft_dir/calls.log"; }
ft_next() {
  local n
  n=$(cat "$ft_dir/next" 2>/dev/null || echo 0)
  n=$((n + 1))
  printf '%s\n' "$n" > "$ft_dir/next"
  printf '%s\n' "$n"
}
ft_known() { [ -f "$(ft_file "$1").pid" ] && [ ! -f "$(ft_file "$1").closed" ]; }
# ft_start <handle> <shell command>: run the command in the background, like a new tab.
# HO_FAKE_TERM_ENV: the terminal's own environment, one entry per line: NAME=VALUE sets a
# variable for the started command, -NAME removes it. It stands for a tmux server that kept
# the environment of its first start, or an iTerm2 tab that starts a fresh login shell.
ft_start() {
  local h=$1 f line
  local -a envargs=()
  f=$(ft_file "$h")
  : > "$f.in"
  while IFS= read -r line; do
    case $line in '') ;; -*) envargs+=(-u "${line#-}") ;; *) envargs+=("$line") ;; esac
  done <<EOF_FT_ENV
${HO_FAKE_TERM_ENV:-}
EOF_FT_ENV
  HO_FAKE_TERM_HANDLE=$h HO_FAKE_TERM_DIR=$ft_dir nohup env ${envargs[@]+"${envargs[@]}"} sh -c "$2" > "$f.out" 2>&1 < /dev/null &
  printf '%s\n' "$!" > "$f.pid"
}
# ft_screen <handle>: the session's screen. Text typed after the last Enter shows on the input
# line (the last line that starts with ">", or with the runtime's real prompt mark once colour
# codes are set aside, issue #104), after a draft and in place of dim suggested text,
# as a terminal echoes it. HO_FAKE_TERM_ECHO_EXTRA is shown after it too, as if someone typed
# a key between the engine's typing and its check.
ft_screen() {
  local f p=""
  f=$(ft_file "$1")
  if [ -s "$f.in" ] && [ -n "$(tail -c 1 "$f.in" | tr -d '\n')" ]; then
    p=$(tail -n 1 "$f.in" | sed 's/<0x[0-9a-f][0-9a-f]>//g; s/<ESC>//g')
  fi
  [ -z "$p" ] || p="$p${HO_FAKE_TERM_ECHO_EXTRA:-}"
  FT_P=$p awk -v e="$(printf '\033')" '
    { l[NR] = $0; s = $0; gsub(e "\\[[0-9;]*m", "", s) }
    s ~ /^>( |$)/ { k = NR }
    index(s, "\342\235\257") == 1 { k = NR }
    END {
      for (i = 1; i <= NR; i++) {
        if (i == k && ENVIRON["FT_P"] != "") {
          if (index(l[i], e "[2m")) print "> " ENVIRON["FT_P"]
          else if (l[i] == ">") print "> " ENVIRON["FT_P"]
          else print l[i] ENVIRON["FT_P"]
        } else print l[i]
      }
    }' "$f.out"
}
