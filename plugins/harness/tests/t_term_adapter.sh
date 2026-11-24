# Design "Rebuild" reuse list: one terminal adapter interface with two backends, iTerm2 and
# tmux, both driven here through the same calls against fakes. The Terminal.app backend is
# dropped (design drop list).
HO_ROOT=$HO_PLUGIN_ROOT
. "$HO_PLUGIN_ROOT/lib/common.sh"
. "$HO_PLUGIN_ROOT/lib/files.sh"
. "$HO_PLUGIN_ROOT/lib/config.sh"
. "$HO_PLUGIN_ROOT/lib/run.sh"
. "$HO_PLUGIN_ROOT/lib/term.sh"
base=$(cd -P "$PWD" && pwd)
proj="$base/proj"
mkdir -p "$proj/.harness"
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$base/user"
set_app() { printf '{"schemaVersion":2,"terminal":{"app":"%s","enter_delay_seconds":0}}\n' "$1" > "$proj/.harness/config.json"; }
set_app tmux
HO_RUN_DIR=$(ho_run_new) HO_RUN_ID=$(basename "$HO_RUN_DIR")
launcher="$base/l.sh"
printf '#!/bin/bash\necho ready\nsleep 20\n' > "$launcher"
cleanup() { local f; for f in "$base"/term-*/*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; done; return 0; }
trap cleanup EXIT

for backend in tmux iterm2; do
  set_app "$backend"
  export HO_FAKE_TERM_DIR="$base/term-$backend"
  t="Rebuild terminal adapter ($backend)"
  assert_eq "$t: the configured backend is used" "$backend" "$(ho_term_backend)"
  assert_contains "$t: probe works" "$(ho_term_probe)" "backend=$backend"
  h1=$(ho_term_open work ho-worker-a "$launcher")
  h2=$(ho_term_open work ho-worker-b "$launcher")
  assert_eq "$t: open returns a handle per session" "yes" "$([ -n "$h1" ] && [ -n "$h2" ] && [ "$h1" != "$h2" ] && echo yes || echo no)"
  f1="$HO_FAKE_TERM_DIR/$(printf '%s' "$h1" | tr -c 'A-Za-z0-9-' '_')"
  i=0; while ! grep -q ready "$f1.out" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  assert_eq "$t: the opened session runs the launcher" "ready" "$(ho_term_capture "$h1" 5)"
  ho_term_send "$h1" "/exit"
  ho_term_key "$h1" escape
  assert_eq "$t: send types the text, then a separate Enter; key presses one key" "/exit
<ESC>" "$(cat "$f1.in")"
  assert_eq "$t: nothing reaches the other session" "" "$(cat "$HO_FAKE_TERM_DIR/$(printf '%s' "$h2" | tr -c 'A-Za-z0-9-' '_').in")"
  assert_exit "$t: close closes that one session" 0 ho_term_close "$h1"
  assert_eq "$t: the closed session is gone" "yes" "$([ -f "$f1.closed" ] && echo yes || echo no)"
  assert_exit "$t: a closed handle is not found" 66 ho_term_send "$h1" "/exit"
  assert_exit "$t: an unknown handle is not found" 66 ho_term_key "nohandle" enter
  before=$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")
  assert_exit "$t: text with shell or quote characters is refused" 65 ho_term_send "$h2" 'x"; do shell script "id'
  assert_exit "$t: text with a line break is refused" 65 ho_term_send "$h2" "/exit
id"
  assert_exit "$t: a title with a quote is refused" 65 ho_term_open work 'a"b' "$launcher"
  assert_exit "$t: a launcher path with a space is refused" 65 ho_term_open work t "$base/a b.sh"
  assert_exit "$t: an unknown key is refused" 64 ho_term_key "$h2" tab
  assert_eq "$t: refused calls never reach the terminal" "$before" "$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")"
done
printf 'not json' > "$HO_RUN_DIR/sessions/windows.json"
assert_exit "Rebuild terminal adapter (iterm2): an unreadable window file still opens the session" 0 ho_term_open work ho-worker-c "$launcher"
assert_eq "Rebuild terminal adapter (iterm2): the first two sessions of one group share one window" "W1" "$(head -n 1 "$base/term-iterm2/windows")"
assert_eq "Rebuild terminal adapter (iterm2): only the unreadable window file caused a second window" "2" "$(wc -l < "$base/term-iterm2/windows" | tr -d ' ')"

# tmux pane IDs are unique per server only: a pane outside this run's tmux session is refused.
set_app tmux
export HO_FAKE_TERM_DIR="$base/term-tmux"
foreign=$(tmux -L ho-harness new-session -d -s someone-else -n x -P -F '#{pane_id}' "sleep 5")
before=$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")
assert_exit "Rebuild terminal adapter (tmux): a pane of another tmux session is not typed into" 66 ho_term_send "$foreign" "/exit"
assert_exit "Rebuild terminal adapter (tmux): a pane of another tmux session is not closed" 66 ho_term_close "$foreign"
assert_eq "Rebuild terminal adapter (tmux): nothing reached the foreign pane" "$before" "$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")"
HO_TERM_BACKEND=iterm2
assert_eq "Rebuild terminal adapter: a backend recorded for a session wins over the config" "iterm2" "$(ho_term_backend)"
unset HO_TERM_BACKEND

set_app terminal
assert_exit "Drop list: the Terminal.app backend is refused" 65 ho_term_backend
set_app other
assert_exit "Rebuild terminal adapter: an unknown backend is refused" 65 ho_term_backend
