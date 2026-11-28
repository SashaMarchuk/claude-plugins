# No code path types a key to wake a session (H-099, design "Rebuild" drop list: the stall rule
# and every typed wake-up). Engine code reaches a terminal only through lib/term.sh. Outside it,
# the calls that type are the exit command of a graceful close (H-081) and the checked typed
# fallback of instruction delivery (H-101, lib/deliver.sh): its typed line, the Enter after the
# second screen read, and the send-now chord of a hard stop (D37-LIFECYCLE-4); and the one
# accept-once key of a permission prompt under the analyse setting (H-052). No key is
# pressed anywhere else, and no other code talks to a terminal app directly.

# The three checked typing calls of delivery (H-101), each allowed as this exact line only.
ALLOW_TYPE='  HO_TERM_BACKEND=$backend ho_term_type "$h" "$tag" "$sid" "$line" 2>/dev/null || rc=$?'
ALLOW_ENTER='  HO_TERM_BACKEND=$backend ho_term_key "$h" "$tag" "$sid" enter 2>/dev/null || rc=$?'
ALLOW_CHORD="  HO_TERM_BACKEND=\$(jq -r '.backend // \"\"' \"\$rec\") ho_term_bytes \"\$(jq -r '.handle // \"\"' \"\$rec\")\" \\"
# The one accept-once key of a permission prompt under session.permission_prompts analyse
# (H-052, D37-AUTONOMY-1), allowed as this exact line only, in ho_perm_handle.
ALLOW_PERM="  HO_TERM_BACKEND=\$(jq -r '.backend // \"\"' \"\$rec\") ho_term_key \"\$(jq -r '.handle // \"\"' \"\$rec\")\" \"\$(jq -r '.term_tag // \"\"' \"\$rec\")\" \"\$(jq -r '.session_id // \"\"' \"\$rec\")\" enter || {"
# allowed_count <root> <line>: how many times that exact line appears in engine code.
allowed_count() { cat "$1"/bin/* "$1"/lib/*.sh | grep -c -x -F -e "$2" || true; }

# scan <root>: print "<file>:<line>:<function>: <text>" for every typing call outside the allowed
# place, then "scanned <n>" with the number of files read.
scan() {
  local root=$1 f n=0
  for f in "$root"/bin/* "$root"/lib/*.sh; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    if [ "$(basename "$f")" = term.sh ]; then
      # The adapter itself: typing calls only inside the send and key functions, which the
      # close path above is the one caller of. Opening, reading and closing type nothing.
      awk -v file="${f#"$root"/}" '
        /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { fn = $0; sub(/\(\).*/, "", fn) }
        /^[ \t]*#/ { next }
        /ho_term_[a-z0-9_]*(send|key)|send-keys|keystroke|write text/ {
          if (fn ~ /^ho_term_(send|key|type|bytes)$/ || fn ~ /^ho_term_[a-z0-9]+_(send|key|type|byte)$/) next
          printf "%s:%d:%s: %s\n", file, NR, fn, $0
        }' "$f"
      continue
    fi
    ALLOW_TYPE=$ALLOW_TYPE ALLOW_ENTER=$ALLOW_ENTER ALLOW_CHORD=$ALLOW_CHORD ALLOW_PERM=$ALLOW_PERM awk -v file="${f#"$root"/}" '
      BEGIN { ALLOW_TYPE = ENVIRON["ALLOW_TYPE"]; ALLOW_ENTER = ENVIRON["ALLOW_ENTER"]; ALLOW_CHORD = ENVIRON["ALLOW_CHORD"]; ALLOW_PERM = ENVIRON["ALLOW_PERM"] }
      /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { fn = $0; sub(/\(\).*/, "", fn) }
      /^[ \t]*#/ { next }
      /ho_term_send|ho_term_key|ho_term_type|ho_term_bytes|ho_term_[a-z0-9]+_(send|key|type|byte)|send-keys|keystroke|write text|osascript|tmux / {
        if (fn == "ho_session_close" && $0 ~ /ho_term_send "\$handle" "\$tag" "\$sid" "\$exitcmd"/) next
        # Each allowed line is matched as a whole line, so a second call after ";" on it is
        # caught; the counts below make sure each allowed line exists exactly once.
        if (fn == "ho_session_deliver" && $0 == ALLOW_TYPE) next
        if (fn == "ho_session_deliver" && $0 == ALLOW_ENTER) next
        if (fn == "ho_deliver_chord" && $0 == ALLOW_CHORD) next
        if (fn == "ho_perm_handle" && $0 == ALLOW_PERM) next
        printf "%s:%d:%s: %s\n", file, NR, fn, $0
      }' "$f"
  done
  printf 'scanned %s\n' "$n"
}

out=$(scan "$HO_PLUGIN_ROOT")
files=$(printf '%s\n' "$out" | sed -n 's/^scanned //p')
if [ "${files:-0}" -ge 10 ]; then ok "H-099: the typing scan read every engine file ($files)"; else bad "H-099: the typing scan read every engine file" "$files"; fi
assert_eq "H-099: no code path types or presses a key into a session, except the exit command of close" "" "$(printf '%s\n' "$out" | grep -v '^scanned ' || true)"
for a in "$ALLOW_TYPE" "$ALLOW_ENTER" "$ALLOW_CHORD" "$ALLOW_PERM"; do
  assert_eq "H-099, H-101: each allowed delivery typing line exists exactly once: $(printf '%s' "$a" | cut -c1-60)" 1 "$(allowed_count "$HO_PLUGIN_ROOT" "$a")"
done
assert_eq "H-099: the close path is the only caller of ho_term_send" 1 "$(cat "$HO_PLUGIN_ROOT"/bin/* "$HO_PLUGIN_ROOT"/lib/*.sh | grep -v '^[[:space:]]*#' | grep -c 'ho_term_send "\$handle"' || true)"
assert_eq "Rebuild drop list: no stall rule, nudge or wake-up in engine code" "" \
  "$(cat "$HO_PLUGIN_ROOT"/bin/* "$HO_PLUGIN_ROOT"/lib/*.sh | grep -v '^[[:space:]]*#' | grep -iwE 'stall|stalled|nudge|nudged|wake|waking|wake-up' || true)"

# The scan catches a planted violation, so an empty result above means something.
# plant_check <label> <file> <line-to-add-after-function-head> <function>: copy the engine, add
# the line as the first line of the function, and expect the scan or the counts to catch it.
plant_check() {
  local label=$1 file=$2 add=$3 fn=$4 caught=no
  rm -rf plant-x && mkdir -p plant-x/bin plant-x/lib
  cp "$HO_PLUGIN_ROOT"/bin/* plant-x/bin/ && cp "$HO_PLUGIN_ROOT"/lib/*.sh plant-x/lib/
  ADD=$add FN=$fn awk '{ print } $0 ~ "^" ENVIRON["FN"] "\\(\\) *\\{" { print ENVIRON["ADD"] }' "$HO_PLUGIN_ROOT/lib/$file" > "plant-x/lib/$file"
  [ -n "$(scan "$PWD/plant-x" | grep -v '^scanned ' || true)" ] && caught=yes
  for a in "$ALLOW_TYPE" "$ALLOW_ENTER" "$ALLOW_CHORD" "$ALLOW_PERM"; do
    [ "$(allowed_count "$PWD/plant-x" "$a")" = 1 ] || caught=yes
  done
  assert_eq "H-099: a planted $label is caught" yes "$caught"
}
plant_check "second copy of the allowed Enter line" deliver.sh "$ALLOW_ENTER" ho_session_deliver
plant_check "second copy of the allowed type line" deliver.sh "$ALLOW_TYPE" ho_session_deliver
plant_check "allowed type line with a second call after ;" deliver.sh '  ho_term_type "$h" "$tag" "$sid" "$line"; ho_term_key "$h" "$tag" "$sid" escape' ho_session_deliver
plant_check "second accept-once key in the permission handler" permission.sh "$ALLOW_PERM" ho_perm_handle
plant_check "second byte call in the chord" deliver.sh '  ho_term_bytes "$(jq -r .handle "$rec")" "$t" "$s" 13' ho_deliver_chord
mkdir -p plant/bin plant/lib
cp "$HO_PLUGIN_ROOT"/bin/* plant/bin/
cp "$HO_PLUGIN_ROOT"/lib/*.sh plant/lib/
printf 'ho_live_poke() {\n  ho_term_key "$handle" "$tag" "$sid" enter\n}\n' >> plant/lib/liveness.sh
assert_contains "H-099: the scan finds a planted wake-up key" "$(scan "$PWD/plant")" "lib/liveness.sh"
printf 'ho_x() {\n  tmux -L ho-harness send-keys -t x " "\n}\n' > plant/lib/liveness.sh
assert_contains "H-099: the scan finds a direct terminal call outside the adapter" "$(scan "$PWD/plant")" "ho_x"
cp "$HO_PLUGIN_ROOT"/lib/liveness.sh plant/lib/liveness.sh
printf 'ho_term_tmux_poke() {\n  ho_tmux send-keys -t "$1" Enter\n}\n' >> plant/lib/term.sh
assert_contains "H-099: the scan finds a wake-up key planted inside the terminal adapter" "$(scan "$PWD/plant")" "lib/term.sh"
cp "$HO_PLUGIN_ROOT"/lib/term.sh plant/lib/term.sh
printf 'ho_term_tmux_open2() {\n  ho_term_tmux_key "$h" "$owner" "$sid" enter\n}\n' >> plant/lib/term.sh
assert_contains "H-099: the scan finds a key press planted in a terminal function that is not send or key" "$(scan "$PWD/plant")" "ho_term_tmux_open2"
