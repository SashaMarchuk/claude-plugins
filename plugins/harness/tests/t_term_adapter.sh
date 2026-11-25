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
o1=11111111-1111-4111-8111-111111111111 o2=22222222-2222-4222-8222-222222222222
cleanup() { local f; for f in "$base"/term-*/*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; done; return 0; }
trap cleanup EXIT

for backend in tmux iterm2; do
  set_app "$backend"
  export HO_FAKE_TERM_DIR="$base/term-$backend"
  t="Rebuild terminal adapter ($backend)"
  assert_eq "$t: the configured backend is used" "$backend" "$(ho_term_backend)"
  assert_contains "$t: probe works" "$(ho_term_probe)" "backend=$backend"
  h1=$(ho_term_open work ho-worker-a "$launcher" "$o1")
  h2=$(ho_term_open work ho-worker-b "$launcher" "$o2")
  assert_eq "$t: open returns a handle per session" "yes" "$([ -n "$h1" ] && [ -n "$h2" ] && [ "$h1" != "$h2" ] && echo yes || echo no)"
  f1="$HO_FAKE_TERM_DIR/$(printf '%s' "$h1" | tr -c 'A-Za-z0-9-' '_')"
  i=0; while ! grep -q ready "$f1.out" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  assert_eq "$t: the opened session runs the launcher" "ready" "$(ho_term_capture "$h1" "$o1" 5)"
  ho_term_send "$h1" "$o1" "/exit"
  ho_term_key "$h1" "$o1" escape
  assert_eq "$t: send types the text, then a separate Enter; key presses one key" "/exit
<ESC>" "$(cat "$f1.in")"
  assert_eq "$t: nothing reaches the other session" "" "$(cat "$HO_FAKE_TERM_DIR/$(printf '%s' "$h2" | tr -c 'A-Za-z0-9-' '_').in")"
  # The owner tag: a call for another owner, or with no usable owner, does nothing.
  f2="$HO_FAKE_TERM_DIR/$(printf '%s' "$h2" | tr -c 'A-Za-z0-9-' '_')"
  before=$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")
  assert_exit "$t: send to a session tagged with another owner is refused" 66 ho_term_send "$h2" "$o1" "/exit"
  assert_exit "$t: a key to a session tagged with another owner is refused" 66 ho_term_key "$h2" "$o1" enter
  assert_exit "$t: capture of a session tagged with another owner is refused" 66 ho_term_capture "$h2" "$o1" 5
  assert_exit "$t: close of a session tagged with another owner is refused" 66 ho_term_close "$h2" "$o1"
  assert_exit "$t: an empty owner is refused" 65 ho_term_close "$h2" ""
  assert_exit "$t: an owner that is not a session ID is refused" 65 ho_term_open work ho-worker-x "$launcher" "a b"
  assert_exit "$t: an owner with a session ID and a second line is refused" 65 ho_term_close "$h2" "$o2
x\"y"
  assert_eq "$t: the other owner's session got nothing and stays open" "no" "$([ -s "$f2.in" ] || [ -f "$f2.closed" ] && echo yes || echo no)"
  assert_eq "$t: refused owner calls never act on the terminal" "$before" "$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")"
  assert_exit "$t: close closes that one session" 0 ho_term_close "$h1" "$o1"
  assert_eq "$t: the closed session is gone" "yes" "$([ -f "$f1.closed" ] && echo yes || echo no)"
  assert_exit "$t: a closed handle is not found" 66 ho_term_send "$h1" "$o1" "/exit"
  assert_exit "$t: an unknown handle is not found" 66 ho_term_key "nohandle" "$o1" enter
  before=$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")
  assert_exit "$t: text with shell or quote characters is refused" 65 ho_term_send "$h2" "$o2" 'x"; do shell script "id'
  assert_exit "$t: text with a line break is refused" 65 ho_term_send "$h2" "$o2" "/exit
id"
  assert_exit "$t: a title with a quote is refused" 65 ho_term_open work 'a"b' "$launcher" "$o2"
  assert_exit "$t: a launcher path with a space is refused" 65 ho_term_open work t "$base/a b.sh" "$o2"
  assert_exit "$t: an unknown key is refused" 64 ho_term_key "$h2" "$o2" tab
  assert_eq "$t: refused calls never reach the terminal" "$before" "$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")"
done
printf 'not json' > "$HO_RUN_DIR/terminal/windows.json"
assert_exit "Rebuild terminal adapter (iterm2): an unreadable window file still opens the session" 0 ho_term_open work ho-worker-c "$launcher" "$o2"
assert_eq "Rebuild terminal adapter (iterm2): the first two sessions of one group share one window" "W1" "$(head -n 1 "$base/term-iterm2/windows")"
assert_eq "Rebuild terminal adapter (iterm2): only the unreadable window file caused a second window" "2" "$(wc -l < "$base/term-iterm2/windows" | tr -d ' ')"

# tmux pane IDs are unique per server only: a pane outside this run's tmux session is refused.
set_app tmux
export HO_FAKE_TERM_DIR="$base/term-tmux"
foreign=$(tmux -L ho-harness new-session -d -s someone-else -n x -P -F '#{pane_id}' "sleep 5")
before=$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")
assert_exit "Rebuild terminal adapter (tmux): a pane of another tmux session is not typed into" 66 ho_term_send "$foreign" "$o1" "/exit"
assert_exit "Rebuild terminal adapter (tmux): a pane of another tmux session is not closed" 66 ho_term_close "$foreign" "$o1"
assert_eq "Rebuild terminal adapter (tmux): nothing reached the foreign pane" "$before" "$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")"

# H-103, S8-27 (review of wave 2, B1): the tmux server exits with the last pane of a run, and
# the next launch of the same run gets the same pane ID under the same tmux session name. A
# late close or send through the old pane ID must not reach the new session.
export HO_FAKE_TERM_DIR="$base/term-reuse"
ra=$(ho_term_open work ho-worker-a "$launcher" "$o1")
rm -rf "$HO_FAKE_TERM_DIR.old" && mv "$HO_FAKE_TERM_DIR" "$HO_FAKE_TERM_DIR.old"   # the server is gone
rb=$(ho_term_open work ho-worker-b "$launcher" "$o2")                               # a new server
fb="$HO_FAKE_TERM_DIR/$(printf '%s' "$rb" | tr -c 'A-Za-z0-9-' '_')"
assert_eq "H-103: after a tmux server restart the new session has the old pane ID" "$ra" "$rb"
assert_exit "H-103: a late close through a reused pane ID is refused" 66 ho_term_close "$ra" "$o1"
assert_exit "H-103: a late send through a reused pane ID is refused" 66 ho_term_send "$ra" "$o1" "/exit"
assert_eq "H-103: the new session behind the reused pane ID got nothing and stays open" "no" "$([ -s "$fb.in" ] || [ -f "$fb.closed" ] && echo yes || echo no)"
assert_exit "H-103: the new session's own owner still closes it" 0 ho_term_close "$rb" "$o2"
assert_eq "H-103: that close removed the pane" "yes" "$([ -f "$fb.closed" ] && echo yes || echo no)"
# A pane that cannot be tagged (tmux older than 3.0) is not left running untagged.
rc=0; HO_FAKE_TMUX_NO_TAG=1 ho_term_open work ho-worker-c "$launcher" "$o1" >/dev/null 2>&1 || rc=$?
assert_eq "H-103: a tmux pane that cannot be tagged fails the open (exit 70)" "70" "$rc"
assert_contains "H-103: the untagged tmux pane is closed under the check of its own process" "$(tail -n 1 "$HO_FAKE_TERM_DIR/calls.log")" "tmux close"

# iTerm2 session tags (review of wave 2): every session the harness opens carries user.ho_run
# and user.ho_session; a stored window ID is used only while it holds a session of this run.
set_app iterm2
export HO_FAKE_TERM_DIR="$base/term-tags"
it_file() { printf '%s/%s' "$HO_FAKE_TERM_DIR" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9-' '_')"; }
ia=$(ho_term_open work ho-worker-a "$launcher" "$o1")
assert_eq "iTerm2 tags (a): the new session carries this run's ID" "$HO_RUN_ID" "$(cat "$(it_file "$ia").var.user.ho_run")"
assert_eq "iTerm2 tags (a): the new session carries its owner" "$o1" "$(cat "$(it_file "$ia").var.user.ho_session")"
# The person's own session, untagged, under a handle the harness might hold.
mkdir -p "$HO_FAKE_TERM_DIR"; pf=$(it_file PERSON-1)
printf 'W77\n' >> "$HO_FAKE_TERM_DIR/windows"; printf 'W77\n' > "$pf.window"; : > "$pf.in"; printf 'my shell\n' > "$pf.out"
sleep 30 &
printf '%s\n' "$!" > "$pf.pid"
before=$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")
assert_exit "iTerm2 tags (b): send to an untagged session is refused" 66 ho_term_send PERSON-1 "$o1" "/exit"
assert_exit "iTerm2 tags (b): capture of an untagged session is refused" 66 ho_term_capture PERSON-1 "$o1" 5
assert_exit "iTerm2 tags (b): close of an untagged session is refused" 66 ho_term_close PERSON-1 "$o1"
assert_exit "iTerm2 tags (b): a session of this run with another owner is refused" 66 ho_term_close "$ia" "$o2"
assert_eq "iTerm2 tags (b): the refused sessions got nothing and stay open" "no no"   "$([ -s "$pf.in" ] || [ -f "$pf.closed" ] && echo yes || echo no) $([ -s "$(it_file "$ia").in" ] || [ -f "$(it_file "$ia").closed" ] && echo yes || echo no)"
assert_eq "iTerm2 tags (b): refused calls never act on the terminal" "$before" "$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")"
printf 'x\n' > "$(it_file PERSON-1).var.user.ho_run"; printf '%s\n' "$o1" > "$(it_file PERSON-1).var.user.ho_session"
assert_exit "iTerm2 tags (b): the owner tag of another run is refused" 66 ho_term_close PERSON-1 "$o1"
rm -f "$(it_file PERSON-1)".var.*
# (c) After an app restart the stored window ID names the person's window W77.
jq '.work = "W77"' "$HO_RUN_DIR/terminal/windows.json" > "$base/w.json" && mv "$base/w.json" "$HO_RUN_DIR/terminal/windows.json"
ic=$(ho_term_open work ho-worker-c "$launcher" "$o2")
assert_eq "iTerm2 tags (c): a stored window without a session of this run is not reused" "no" "$([ "$(cat "$(it_file "$ic").window")" = W77 ] && echo yes || echo no)"
id=$(ho_term_open work ho-worker-d "$launcher" "$o2")
assert_eq "iTerm2 tags (c): a stored window that holds a session of this run is reused" "$(cat "$(it_file "$ic").window")" "$(cat "$(it_file "$id").window")"
rc=0; HO_FAKE_ITERM_NO_VARS=1 ho_term_open work ho-worker-e "$launcher" "$o2" >/dev/null 2>&1 || rc=$?
assert_eq "iTerm2 tags (a): a session that cannot be tagged fails the open (exit 70)" "70" "$rc"
assert_contains "iTerm2 tags (a): the untagged session is closed in the same script" "$(tail -n 1 "$HO_FAKE_TERM_DIR/calls.log")" "osascript close"
HO_TERM_BACKEND=iterm2
assert_eq "Rebuild terminal adapter: a backend recorded for a session wins over the config" "iterm2" "$(ho_term_backend)"
unset HO_TERM_BACKEND

set_app terminal
assert_exit "Drop list: the Terminal.app backend is refused" 65 ho_term_backend
set_app other
assert_exit "Rebuild terminal adapter: an unknown backend is refused" 65 ho_term_backend
