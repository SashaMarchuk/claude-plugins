# Issue #108: learn the user's own status line once, so the delivery screen gate (H-099, H-101;
# PR #105 review M1: every line under the input box must be the runtime's status area) also reads
# a custom status line. The shapes are runtime data (D37-RUNTIME-1); the learned ones live in the
# user folder only and are used only for the runtime binary and status line setting they were
# learned with. All screen text here is synthetic: a test runtime names its own pattern file.
. "$HO_TESTS_DIR/sessions-setup.sh"
plug="$base/plugin"
mkdir -p "$plug"
cp -R "$HO_PLUGIN_ROOT/bin" "$HO_PLUGIN_ROOT/lib" "$HO_PLUGIN_ROOT/runtimes" "$HO_PLUGIN_ROOT/.claude-plugin" "$plug/"
jq '.screen_file = "zzsyn.screen.json"' "$plug/runtimes/claude-code.json" > "$plug/runtimes/zzsyn.json"
# The second hold shape has the same marks as the learned status line: learning must never let
# it pass as the status area (it reads as a hold or as unknown; nothing is typed).
jq -n '{shapes: [{id: "limit", anchor: "zz synthetic hold line", companion: ""},
    {id: "trust", anchor: "◆ zz hold ▸ choose ◆ [0-9]+", companion: ""}, {id: "password", anchor: "⟦ zz pass ⟧ ⚙ now", companion: ""}],
  frame_start: "^[─│]", frame_end: "[─│]$", frame_only: "^─+$", input_box: "^(>|❯)( .*)?$",
  status_first_line: "^zz shipped first line$", status_lines: ["^zz shipped mode line$"]}' > "$plug/runtimes/zzsyn.screen.json"
h="$plug/bin/harness"
printf '{"schemaVersion": 2, "runtime": {"main": "zzsyn"}, "delivery": {"wait_seconds": 2, "message_timeout_seconds": 5, "message_kill_grace_seconds": 1}}\n' > "$user/config.json"
export HO_FAKE_CLAUDE_TRANSCRIPT=1
fout() { printf '%s/%s.out' "$HO_FAKE_TERM_DIR" "$(printf '%s' "$(rec "$1" .handle)" | tr -c 'A-Za-z0-9-' '_')"; }
fin() { printf '%s/%s.in' "$HO_FAKE_TERM_DIR" "$(printf '%s' "$(rec "$1" .handle)" | tr -c 'A-Za-z0-9-' '_')"; }
inbytes() { wc -c < "$(fin "$1")" | tr -d ' '; }
trof() { ls "$HOME"/.claude/projects/*/"$(rec "$1" .session_id).jsonl" 2>/dev/null | head -n 1; }
start() {
  local i=0
  launch "$1" >/dev/null
  while [ -z "$(trof "$1")" ] && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
}
R='──────────────────────────────'
IC=$(printf '\033[39m')
# idle <status lines...>: an idle screen of the test runtime with these lines under the box.
idle() { printf 'earlier output\n\n%s\n%s> \n%s\n' "$R" "$IC" "$R"; for l in "$@"; do printf '%s\n' "$l"; done; }
learned="$user/screen/zzsyn.learned.json"
perm() { if stat -c %a / >/dev/null 2>&1; then stat -c %a "$1"; else stat -f %Lp "$1"; fi; }
learn() { "$h" screen "$run" learn "$@"; }

start s1
idle '◆ zz-proj ▸ main ◆ 12%' 'zz shipped mode line' > "$(fout s1)"
# ---- before: a custom status line fails closed ------------------------------------------------
out=$("$h" session "$run" deliver s1 --text "run the tests" 2>&1) && rc=0 || rc=$?
assert_eq "#108 H-099: an unknown status line under the box gets nothing typed (exit 1, 0 bytes)" "1 0" "$rc $(inbytes s1)"
assert_contains "#108: the refusal says how to learn the status line" "$out" "harness screen <run> learn <session>"

# ---- preview: shows what was learned, stores nothing -------------------------------------------
rc=0; out=$(learn s1) || rc=$?
assert_eq "#108: the preview exits 0" 0 "$rc"
assert_contains "#108: the preview shows the learned line" "$out" "line 1 under the input box: ◆ zz-proj ▸ main ◆ 12%"
assert_contains "#108: the preview names the frame width" "$out" "frame width 30"
assert_eq "#108: a shipped line is not learned again" "" "$(printf '%s\n' "$out" | grep -F 'zz shipped mode line' || true)"
code=$(printf '%s\n' "$out" | sed -n 's/^CODE //p')
assert_eq "#108: the preview stores nothing" no "$([ -e "$learned" ] && echo yes || echo no)"
assert_exit "#108: --yes with a wrong code stores nothing (exit 65)" 65 learn s1 --yes --code 0000000000000000
assert_eq "#108: still nothing stored" no "$([ -e "$learned" ] && echo yes || echo no)"
assert_exit "#108: --yes needs the code (exit 64)" 64 learn s1 --yes

# ---- confirm: stored in the user folder, used by delivery --------------------------------------
rc=0; out=$(learn s1 --yes --code "$code") || rc=$?
assert_eq "#108: the confirmed learn exits 0" 0 "$rc"
assert_eq "#108: the shape is stored in the user folder" yes "$([ -f "$learned" ] && echo yes || echo no)"
assert_eq "#108: the stored file is private (mode 600)" 600 "$(perm "$learned")"
assert_eq "#108: the stored file keeps no screen text" "" "$(grep -F 'zz-proj' "$learned" || true)"
assert_eq "#108: nothing is written into the project" "" "$(find "$proj" -name '*learned*' 2>/dev/null)"
# The same status line with other words and numbers now reads; the instruction is typed.
start s2
idle '◆ other-proj ▸ dev/branch_2 ◆ 99%' 'zz shipped mode line' > "$(fout s2)"
out=$("$h" session "$run" deliver s2 --text "run the tests" 2>&1) && rc=0 || rc=$?
assert_eq "#108 H-099: the learned status line with new values reads; the instruction is typed (exit 0)" 0 "$rc"
assert_contains "#108: it went by the typed route" "$out" "route=typed"
# Another set of symbols under the box still fails closed.
start s3
idle '◆ zz-proj ▸ main ◆ 12%' 'Choose: [1] keep | [2] drop' > "$(fout s3)"
out=$("$h" session "$run" deliver s3 --text "run the tests" 2>&1) && rc=0 || rc=$?
assert_eq "#108 H-099: a line with other symbols under the box still gets nothing typed" "1 0" "$rc $(inbytes s3)"
# A hold above the box is still a hold.
start s4
printf '\nzz synthetic hold line\n\n%s\n%s> \n%s\n◆ zz-proj ▸ main ◆ 12%%\n' "$R" "$IC" "$R" > "$(fout s4)"
out=$("$h" session "$run" deliver s4 --text "run the tests" 2>&1) && rc=0 || rc=$?
assert_eq "#108 H-099: a hold above the box is still a hold with a learned status line" "1 0" "$rc $(inbytes s4)"

# A hold line with the same marks as the learned status line, right under the closing frame.
start s4b
idle '◆ zz hold ▸ choose ◆ 2' > "$(fout s4b)"
out=$("$h" session "$run" deliver s4b --text "run the tests" 2>&1) && rc=0 || rc=$?
assert_eq "#108 H-099: a hold with the learned marks right under the box gets nothing typed" "1 0" "$rc $(inbytes s4b)"
assert_exit "#108: a hold line under the box is never learned as the status line (exit 75)" 75 learn s4b
# A two-line custom status line, and below it a hold with the marks of its second line.
start s4c
idle '◆ zz-proj ▸ main ◆ 12%' '⟦ ctx ⟧ ⚙ 3' > "$(fout s4c)"
out=$(learn s4c); learn s4c --yes --code "$(printf '%s\n' "$out" | sed -n 's/^CODE //p')" >/dev/null
idle '◆ zz-proj ▸ main ◆ 12%' '⟦ ctx ⟧ ⚙ 4' > "$(fout s4c)"
out=$("$h" session "$run" deliver s4c --text "run the tests" 2>&1) && rc=0 || rc=$?
assert_eq "#108: a learned two-line status line reads (exit 0)" 0 "$rc"
start s4d
idle '◆ zz-proj ▸ main ◆ 12%' '⟦ ctx ⟧ ⚙ 3' '⟦ zz pass ⟧ ⚙ now' > "$(fout s4d)"
out=$("$h" session "$run" deliver s4d --text "run the tests" 2>&1) && rc=0 || rc=$?
assert_eq "#108 H-099: a hold with the marks of a learned second line, below it, gets nothing typed" "1 0" "$rc $(inbytes s4d)"
# A line whose only marks are one ASCII bracket pair is too loose to learn.
start s4e
idle '[model] branch' > "$(fout s4e)"
assert_exit "#108: a line whose only marks are one bracket pair is not learned (exit 65)" 65 learn s4e

# ---- stale: a changed status line setting sets the learned shape aside ---------------------------
mkdir -p "$HOME/.claude"
printf '{"statusLine": {"type": "command", "command": "echo changed"}}\n' > "$HOME/.claude/settings.json"
start s5
idle '◆ zz-proj ▸ main ◆ 12%' > "$(fout s5)"
out=$("$h" session "$run" deliver s5 --text "run the tests" 2>&1) && rc=0 || rc=$?
assert_eq "#108: after a status line setting change the learned shape is not used (exit 1, 0 bytes)" "1 0" "$rc $(inbytes s5)"
rc=0; out=$(learn s5) || rc=$?
code=$(printf '%s\n' "$out" | sed -n 's/^CODE //p')
learn s5 --yes --code "$code" >/dev/null
out=$("$h" session "$run" deliver s5 --text "run the tests" 2>&1) && rc=0 || rc=$?
assert_eq "#108: learned again, it is used again (exit 0)" 0 "$rc"
rm -f "$HOME/.claude/settings.json"

# ---- refusals ----------------------------------------------------------------------------------
start s6
idle 'plain words only 12' > "$(fout s6)"
rm -f "$learned"
assert_exit "#108: a status line with fewer than two symbols is not learned (exit 65)" 65 learn s6
assert_eq "#108: nothing stored for it" no "$([ -e "$learned" ] && echo yes || echo no)"
start s7
printf 'earlier output\n\n%s\n%s> half typed\n%s\n◆ a ▸ b ◆\n' "$R" "$IC" "$R" > "$(fout s7)"
assert_exit "#108: a screen that is not idle is not learned from (exit 75)" 75 learn s7
start s8
idle 'zz shipped first line' 'zz shipped mode line' > "$(fout s8)"
assert_contains "#108: a status line the shipped shapes read needs nothing" "$(learn s8)" "nothing to learn"
