# No code path types a key to wake a session (H-099, design "Rebuild" drop list: the stall rule
# and every typed wake-up). Engine code reaches a terminal only through lib/term.sh. Outside it,
# the one call that types is the exit command of a graceful close (H-081); no key is pressed
# anywhere else, and no other code talks to a terminal app directly.

# scan <root>: print "<file>:<line>:<function>: <text>" for every typing call outside the allowed
# place, then "scanned <n>" with the number of files read.
scan() {
  local root=$1 f n=0
  for f in "$root"/bin/* "$root"/lib/*.sh; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    [ "$(basename "$f")" = term.sh ] && continue
    awk -v file="${f#"$root"/}" '
      /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { fn = $0; sub(/\(\).*/, "", fn) }
      /^[ \t]*#/ { next }
      /ho_term_send|ho_term_key|ho_term_[a-z0-9]+_(send|key)|send-keys|keystroke|write text|osascript|tmux / {
        if (fn == "ho_session_close" && $0 ~ /ho_term_send "\$handle" "\$tag" "\$sid" "\$exitcmd"/) next
        printf "%s:%d:%s: %s\n", file, NR, fn, $0
      }' "$f"
  done
  printf 'scanned %s\n' "$n"
}

out=$(scan "$HO_PLUGIN_ROOT")
files=$(printf '%s\n' "$out" | sed -n 's/^scanned //p')
if [ "${files:-0}" -ge 10 ]; then ok "H-099: the typing scan read every engine file ($files)"; else bad "H-099: the typing scan read every engine file" "$files"; fi
assert_eq "H-099: no code path types or presses a key into a session, except the exit command of close" "" "$(printf '%s\n' "$out" | grep -v '^scanned ' || true)"
assert_eq "H-099: the close path is the only caller of ho_term_send" 1 "$(cat "$HO_PLUGIN_ROOT"/bin/* "$HO_PLUGIN_ROOT"/lib/*.sh | grep -v '^[[:space:]]*#' | grep -c 'ho_term_send "\$handle"' || true)"
assert_eq "Rebuild drop list: no stall rule, nudge or wake-up in engine code" "" \
  "$(cat "$HO_PLUGIN_ROOT"/bin/* "$HO_PLUGIN_ROOT"/lib/*.sh | grep -v '^[[:space:]]*#' | grep -iwE 'stall|stalled|nudge|nudged|wake|waking|wake-up' || true)"

# The scan catches a planted violation, so an empty result above means something.
mkdir -p plant/bin plant/lib
cp "$HO_PLUGIN_ROOT"/bin/* plant/bin/
cp "$HO_PLUGIN_ROOT"/lib/*.sh plant/lib/
printf 'ho_live_poke() {\n  ho_term_key "$handle" "$tag" "$sid" enter\n}\n' >> plant/lib/liveness.sh
assert_contains "H-099: the scan finds a planted wake-up key" "$(scan "$PWD/plant")" "lib/liveness.sh"
printf 'ho_x() {\n  tmux -L ho-harness send-keys -t x " "\n}\n' > plant/lib/liveness.sh
assert_contains "H-099: the scan finds a direct terminal call outside the adapter" "$(scan "$PWD/plant")" "ho_x"
