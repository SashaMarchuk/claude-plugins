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
ft_start() {
  local h=$1 f
  f=$(ft_file "$h")
  : > "$f.in"
  HO_FAKE_TERM_HANDLE=$h HO_FAKE_TERM_DIR=$ft_dir nohup sh -c "$2" > "$f.out" 2>&1 < /dev/null &
  printf '%s\n' "$!" > "$f.pid"
}
