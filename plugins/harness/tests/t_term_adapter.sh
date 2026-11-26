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
s1=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa s2=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
cleanup() { local f; for f in "$base"/term-*/*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null || true; done; return 0; }
trap cleanup EXIT

for backend in tmux iterm2; do
  set_app "$backend"
  export HO_FAKE_TERM_DIR="$base/term-$backend"
  t="Rebuild terminal adapter ($backend)"
  assert_eq "$t: the configured backend is used" "$backend" "$(ho_term_backend)"
  assert_contains "$t: probe works" "$(ho_term_probe)" "backend=$backend"
  h1=$(ho_term_open work ho-worker-a "$launcher" "$o1" "$s1")
  h2=$(ho_term_open work ho-worker-b "$launcher" "$o2" "$s2")
  assert_eq "$t: open returns a handle per session" "yes" "$([ -n "$h1" ] && [ -n "$h2" ] && [ "$h1" != "$h2" ] && echo yes || echo no)"
  f1="$HO_FAKE_TERM_DIR/$(printf '%s' "$h1" | tr -c 'A-Za-z0-9-' '_')"
  i=0; while ! grep -q ready "$f1.out" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  assert_eq "$t: the opened session runs the launcher" "ready" "$(ho_term_capture "$h1" "$o1" "$s1" 5)"
  ho_term_send "$h1" "$o1" "$s1" "/exit"
  ho_term_key "$h1" "$o1" "$s1" escape
  assert_eq "$t: send types the text, then a separate Enter; key presses one key" "/exit
<ESC>" "$(cat "$f1.in")"
  assert_eq "$t: nothing reaches the other session" "" "$(cat "$HO_FAKE_TERM_DIR/$(printf '%s' "$h2" | tr -c 'A-Za-z0-9-' '_').in")"
  # Control bytes (a runtime's send-now chord, D37-LIFECYCLE-4) and the styled capture (H-099).
  : > "$f1.in"
  ho_term_bytes "$h1" "$o1" "$s1" 24 19
  assert_eq "$t: bytes sends each control byte, in order" "<0x18><0x13>" "$(cat "$f1.in")"
  assert_exit "$t: a byte outside 1-31 is refused" 65 ho_term_bytes "$h1" "$o1" "$s1" 65
  : > "$f1.in"
  assert_exit "$t: minor 12: byte 10 (line feed) is refused" 65 ho_term_bytes "$h1" "$o1" "$s1" 24 10
  assert_exit "$t: minor 12: byte 13 (carriage return) is refused" 65 ho_term_bytes "$h1" "$o1" "$s1" 13
  assert_eq "$t: minor 12: a refused set sends no byte at all" "" "$(cat "$f1.in")"
  assert_exit "$t: bytes to a session tagged with another owner is refused" 66 ho_term_bytes "$h1" "$o2" "$s1" 24
  printf '> \033[2mdim\033[0m\n' > "$f1.out"
  case $backend in
    tmux) want=$(printf '> \033[2mdim\033[0m') ;;
    *) want='> dim' ;;
  esac
  assert_eq "$t: a styled capture keeps colour codes where the backend has them" "$want" "$(ho_term_capture "$h1" "$o1" "$s1" 5 styled)"
  assert_eq "$t: a plain capture has no colour codes" "> dim" "$(ho_term_capture "$h1" "$o1" "$s1" 5)"
  : > "$f1.in"
  ho_term_type "$h1" "$o1" "$s1" "/exit"
  assert_eq "$t: type types the text and sends no Enter" "/exit" "$(cat "$f1.in")"
  assert_exit "$t: type to a session tagged with another owner is refused" 66 ho_term_type "$h1" "$o2" "$s1" "/exit"
  : > "$f1.in"
  # Codex P2 (PR #95, round 4): an Enter delay above 10 s, or not a number, is refused (78)
  # before anything is typed.
  jq '.terminal.enter_delay_seconds = 11' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
  assert_exit "$t: an Enter delay above 10 s is refused (78)" 78 ho_term_send "$h1" "$o1" "$s1" "/exit"
  assert_eq "$t: with a refused Enter delay nothing is typed" "" "$(cat "$f1.in")"
  set_app "$backend"
  # The owner tag: a call for another owner, or with no usable owner, does nothing.
  f2="$HO_FAKE_TERM_DIR/$(printf '%s' "$h2" | tr -c 'A-Za-z0-9-' '_')"
  before=$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")
  assert_exit "$t: send to a session tagged with another owner is refused" 66 ho_term_send "$h2" "$o1" "$s1" "/exit"
  assert_exit "$t: a key to a session tagged with another owner is refused" 66 ho_term_key "$h2" "$o1" "$s1" enter
  assert_exit "$t: capture of a session tagged with another owner is refused" 66 ho_term_capture "$h2" "$o1" "$s1" 5
  assert_exit "$t: close of a session tagged with another owner is refused" 66 ho_term_close "$h2" "$o1" "$s1"
  assert_exit "$t: an empty owner is refused" 65 ho_term_close "$h2" "" "$s2"
  assert_exit "$t: an owner that is not a session ID is refused" 65 ho_term_open work ho-worker-x "$launcher" "a b" "$s1"
  assert_exit "$t: an owner with a session ID and a second line is refused" 65 ho_term_close "$h2" "$o2
x\"y" "$s2"
  # The session ID (review of wave 2, R1): the owner's tag with another session ID does nothing.
  assert_exit "$t: send with the owner's tag but another session ID is refused" 66 ho_term_send "$h2" "$o2" "$s1" "/exit"
  assert_exit "$t: a key with the owner's tag but another session ID is refused" 66 ho_term_key "$h2" "$o2" "$s1" enter
  assert_exit "$t: capture with the owner's tag but another session ID is refused" 66 ho_term_capture "$h2" "$o2" "$s1" 5
  assert_exit "$t: close with the owner's tag but another session ID is refused" 66 ho_term_close "$h2" "$o2" "$s1"
  assert_exit "$t: an empty session ID is refused" 65 ho_term_close "$h2" "$o2" ""
  assert_exit "$t: open without a session ID is refused" 65 ho_term_open work ho-worker-x "$launcher" "$o1"
  assert_eq "$t: the other owner's session got nothing and stays open" "no" "$([ -s "$f2.in" ] || [ -f "$f2.closed" ] && echo yes || echo no)"
  assert_eq "$t: refused owner calls never act on the terminal" "$before" "$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")"
  assert_exit "$t: close closes that one session" 0 ho_term_close "$h1" "$o1" "$s1"
  assert_eq "$t: the closed session is gone" "yes" "$([ -f "$f1.closed" ] && echo yes || echo no)"
  assert_exit "$t: a closed handle is not found" 66 ho_term_send "$h1" "$o1" "$s1" "/exit"
  assert_exit "$t: an unknown handle is not found" 66 ho_term_key "nohandle" "$o1" "$s1" enter
  before=$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")
  assert_exit "$t: text with shell or quote characters is refused" 65 ho_term_send "$h2" "$o2" "$s2" 'x"; do shell script "id'
  assert_exit "$t: text with a line break is refused" 65 ho_term_send "$h2" "$o2" "$s2" "/exit
id"
  assert_exit "$t: a title with a quote is refused" 65 ho_term_open work 'a"b' "$launcher" "$o2" "$s2"
  assert_exit "$t: a launcher path with a space is refused" 65 ho_term_open work t "$base/a b.sh" "$o2" "$s2"
  assert_exit "$t: an unknown key is refused" 64 ho_term_key "$h2" "$o2" "$s2" tab
  assert_eq "$t: refused calls never reach the terminal" "$before" "$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")"
done
printf 'not json' > "$HO_RUN_DIR/terminal/windows.json"
assert_exit "Rebuild terminal adapter (iterm2): an unreadable window file still opens the session" 0 ho_term_open work ho-worker-c "$launcher" "$o2" "$s2"
assert_eq "Rebuild terminal adapter (iterm2): the first two sessions of one group share one window" "W1" "$(head -n 1 "$base/term-iterm2/windows")"
assert_eq "Rebuild terminal adapter (iterm2): only the unreadable window file caused a second window" "2" "$(wc -l < "$base/term-iterm2/windows" | tr -d ' ')"

# tmux pane IDs are unique per server only: a pane outside this run's tmux session is refused.
set_app tmux
export HO_FAKE_TERM_DIR="$base/term-tmux"
foreign=$(tmux -L ho-harness new-session -d -s someone-else -n x -P -F '#{pane_id}' "sleep 5")
before=$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")
assert_exit "Rebuild terminal adapter (tmux): a pane of another tmux session is not typed into" 66 ho_term_send "$foreign" "$o1" "$s1" "/exit"
assert_exit "Rebuild terminal adapter (tmux): a pane of another tmux session is not closed" 66 ho_term_close "$foreign" "$o1" "$s1"
assert_eq "Rebuild terminal adapter (tmux): nothing reached the foreign pane" "$before" "$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")"

# H-103, S8-27 (review of wave 2, B1): the tmux server exits with the last pane of a run, and
# the next launch of the same run gets the same pane ID under the same tmux session name. A
# late close or send through the old pane ID must not reach the new session.
export HO_FAKE_TERM_DIR="$base/term-reuse"
ra=$(ho_term_open work ho-worker-a "$launcher" "$o1" "$s1")
rm -rf "$HO_FAKE_TERM_DIR.old" && mv "$HO_FAKE_TERM_DIR" "$HO_FAKE_TERM_DIR.old"   # the server is gone
rb=$(ho_term_open work ho-worker-b "$launcher" "$o2" "$s2")                               # a new server
fb="$HO_FAKE_TERM_DIR/$(printf '%s' "$rb" | tr -c 'A-Za-z0-9-' '_')"
assert_eq "H-103: after a tmux server restart the new session has the old pane ID" "$ra" "$rb"
assert_eq "R1 (tmux): open sets the pane options @ho_tag and @ho_session_id" "$o2 $s2" "$(cat "$fb.tag") $(cat "$fb.sid")"
assert_exit "H-103: a late close through a reused pane ID is refused" 66 ho_term_close "$ra" "$o1" "$s1"
assert_exit "H-103: a late send through a reused pane ID is refused" 66 ho_term_send "$ra" "$o1" "$s1" "/exit"
assert_eq "H-103: the new session behind the reused pane ID got nothing and stays open" "no" "$([ -s "$fb.in" ] || [ -f "$fb.closed" ] && echo yes || echo no)"
assert_exit "H-103: the new session's own owner still closes it" 0 ho_term_close "$rb" "$o2" "$s2"
assert_eq "H-103: that close removed the pane" "yes" "$([ -f "$fb.closed" ] && echo yes || echo no)"
# A pane that cannot be tagged (tmux older than 3.0) is not left running untagged.
rc=0; HO_FAKE_TMUX_NO_TAG=1 ho_term_open work ho-worker-c "$launcher" "$o1" "$s1" >/dev/null 2>&1 || rc=$?
assert_eq "H-103: a tmux pane that cannot be tagged fails the open (exit 70)" "70" "$rc"
assert_contains "H-103: the untagged tmux pane is closed under the check of its own process" "$(tail -n 1 "$HO_FAKE_TERM_DIR/calls.log")" "tmux close"

# iTerm2 session tags (review of wave 2): every session the harness opens carries user.ho_run,
# user.ho_session and user.ho_session_id; a stored window ID is used only while it holds a session of this run.
set_app iterm2
export HO_FAKE_TERM_DIR="$base/term-tags"
it_file() { printf '%s/%s' "$HO_FAKE_TERM_DIR" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9-' '_')"; }
ia=$(ho_term_open work ho-worker-a "$launcher" "$o1" "$s1")
assert_eq "iTerm2 tags (a): the new session carries this run's ID" "$HO_RUN_ID" "$(cat "$(it_file "$ia").var.user.ho_run")"
assert_eq "iTerm2 tags (a): the new session carries its owner" "$o1" "$(cat "$(it_file "$ia").var.user.ho_session")"
assert_eq "iTerm2 tags (a): the new session carries its session ID" "$s1" "$(cat "$(it_file "$ia").var.user.ho_session_id")"
# The person's own session, untagged, under a handle the harness might hold.
mkdir -p "$HO_FAKE_TERM_DIR"; pf=$(it_file PERSON-1)
printf 'W77\n' >> "$HO_FAKE_TERM_DIR/windows"; printf 'W77\n' > "$pf.window"; : > "$pf.in"; printf 'my shell\n' > "$pf.out"
sleep 30 &
printf '%s\n' "$!" > "$pf.pid"
before=$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")
assert_exit "iTerm2 tags (b): send to an untagged session is refused" 66 ho_term_send PERSON-1 "$o1" "$s1" "/exit"
assert_exit "iTerm2 tags (b): capture of an untagged session is refused" 66 ho_term_capture PERSON-1 "$o1" "$s1" 5
assert_exit "iTerm2 tags (b): close of an untagged session is refused" 66 ho_term_close PERSON-1 "$o1" "$s1"
assert_exit "iTerm2 tags (b): a session of this run with another owner is refused" 66 ho_term_close "$ia" "$o2" "$s2"
assert_eq "iTerm2 tags (b): the refused sessions got nothing and stay open" "no no"   "$([ -s "$pf.in" ] || [ -f "$pf.closed" ] && echo yes || echo no) $([ -s "$(it_file "$ia").in" ] || [ -f "$(it_file "$ia").closed" ] && echo yes || echo no)"
assert_eq "iTerm2 tags (b): refused calls never act on the terminal" "$before" "$(wc -l < "$HO_FAKE_TERM_DIR/calls.log")"
printf 'x\n' > "$(it_file PERSON-1).var.user.ho_run"; printf '%s\n' "$o1" > "$(it_file PERSON-1).var.user.ho_session"
assert_exit "iTerm2 tags (b): the owner tag of another run is refused" 66 ho_term_close PERSON-1 "$o1" "$s1"
rm -f "$(it_file PERSON-1)".var.*
# (c) After an app restart the stored window ID names the person's window W77.
jq '.work = "W77"' "$HO_RUN_DIR/terminal/windows.json" > "$base/w.json" && mv "$base/w.json" "$HO_RUN_DIR/terminal/windows.json"
ic=$(ho_term_open work ho-worker-c "$launcher" "$o2" "$s2")
assert_eq "iTerm2 tags (c): a stored window without a session of this run is not reused" "no" "$([ "$(cat "$(it_file "$ic").window")" = W77 ] && echo yes || echo no)"
id=$(ho_term_open work ho-worker-d "$launcher" "$o2" "$s2")
assert_eq "iTerm2 tags (c): a stored window that holds a session of this run is reused" "$(cat "$(it_file "$ic").window")" "$(cat "$(it_file "$id").window")"
rc=0; HO_FAKE_ITERM_NO_VARS=1 ho_term_open work ho-worker-e "$launcher" "$o2" "$s2" >/dev/null 2>&1 || rc=$?
assert_eq "iTerm2 tags (a): a session that cannot be tagged fails the open (exit 70)" "70" "$rc"
assert_contains "iTerm2 tags (a): the untagged session is closed in the same script" "$(tail -n 1 "$HO_FAKE_TERM_DIR/calls.log")" "osascript close"
# (d) iTerm2 resolves a loop reference to a session again on every event, by position. A
# window that comes to the front between the tag check and the action must not move the
# action to another session (review of wave 2, iTerm2 pinning).
export HO_FAKE_TERM_DIR="$base/term-reorder"
qa=$(ho_term_open work ho-worker-a "$launcher" "$o1" "$s1")
qb=$(ho_term_open control ho-orch-b "$launcher" "$o2" "$s2")
fa=$(it_file "$qa") fb=$(it_file "$qb")
assert_eq "iTerm2 pinning (d): the two sessions are in two windows" "yes" "$([ "$(cat "$fa.window")" != "$(cat "$fb.window")" ] && echo yes || echo no)"
HO_FAKE_ITERM_REORDER=1 ho_term_send "$qa" "$o1" "$s1" "/exit" >/dev/null 2>&1 || true
assert_contains "iTerm2 pinning (d): the windows were reordered between check and action" "$(cat "$HO_FAKE_TERM_DIR/calls.log")" "osascript reorder"
assert_eq "iTerm2 pinning (d): nothing is written to the session that moved into the old position" "" "$(cat "$fb.in")"
assert_eq "iTerm2 pinning (d): the text and its Enter reach the checked session" "/exit" "$(cat "$fa.in")"
HO_FAKE_ITERM_REORDER=1 ho_term_close "$qa" "$o1" "$s1" >/dev/null 2>&1 || true
assert_eq "iTerm2 pinning (d): a close after a reorder closes the checked session only" "yes no" \
  "$([ -f "$fa.closed" ] && echo yes || echo no) $([ -f "$fb.closed" ] && echo yes || echo no)"
# (e) R2 (review of wave 2): another session opens between the create and the read of the new
# session's ID, at the new tab's position. A tab reference is a position, so a read through it
# names the other session. The open must tag no session but its own, and with two new
# sessions it cannot tell which one is its own: it fails (70) and tags nothing.
export HO_FAKE_TERM_DIR="$base/term-insert"
ea=$(ho_term_open work ho-worker-a "$launcher" "$o1" "$s1")
for path in tab window; do
  grp=work; [ "$path" = window ] && grp=control
  rc=0; HO_FAKE_ITERM_INSERT=1 ho_term_open "$grp" "ho-worker-$path" "$launcher" "$o2" "$s2" >/dev/null 2>&1 || rc=$?
  ins=$(sed -n 's/^osascript insert \([^ ]*\) .*/\1/p' "$HO_FAKE_TERM_DIR/calls.log" | tail -n 1)
  assert_eq "R2 (new $path): an open that sees two new sessions fails (exit 70)" "70" "$rc"
  assert_eq "R2 (new $path): the session that opened in between is not tagged" "$ins: " "$ins: $(cd "$HO_FAKE_TERM_DIR" && ls -- "$ins".var.* 2>/dev/null || true)"
  assert_eq "R2 (new $path): no session but the first launch's carries a tag" "$ea.var.user.ho_session" \
    "$(cd "$HO_FAKE_TERM_DIR" && ls -- *.var.user.ho_session | tr '\n' ' ' | sed 's/ $//')"
  assert_eq "R2 (new $path): nothing is closed" "" "$(ls "$HO_FAKE_TERM_DIR"/*.closed 2>/dev/null || true)"
done
HO_TERM_BACKEND=iterm2
assert_eq "Rebuild terminal adapter: a backend recorded for a session wins over the config" "iterm2" "$(ho_term_backend)"
unset HO_TERM_BACKEND

set_app terminal
assert_exit "Drop list: the Terminal.app backend is refused" 65 ho_term_backend
set_app other
assert_exit "Rebuild terminal adapter: an unknown backend is refused" 65 ho_term_backend

# Inside 'tell application "iTerm2"' the word "contents" compiles to iTerm2's session
# property, so "contents of x" on a loop item fails with -1728 on the real app (PR #90,
# real-app run). The fake cannot see this, so this check reads the AppleScript text:
# outside the ho_flat handler, no iTerm2 script may use "contents of" or "repeat with x in".
bad=$(awk '/^on ho_flat/,/^end ho_flat/ {next} /contents of|repeat with [a-z0-9_]+ in /' "$HO_PLUGIN_ROOT/lib/term.sh" | grep -v '^ *#' | grep -v '^-- ' || true)
assert_eq "iTerm2 scripts: no 'contents of' or 'repeat with x in' inside the app tell" "" "$bad"
