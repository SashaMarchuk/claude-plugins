# GitHub listings (D2, H-079, H-002; follow-ups #110 and #88): a listing that prints nothing is a
# failed listing, never "no tickets"; a listing cut at its limit says so.
h="$HO_PLUGIN_ROOT/bin/harness"
printf '## Outcome\nx\n\n## Scope\ny\n\n## Acceptance criteria\nz\n' > body.md
export HO_FAKE_GH_DIR="$PWD/gh" HO_TICKETS_SOURCE=github HO_TICKETS_REPO=fake/repo
fake=$(command -v gh)
# A gh in front of the fake one that prints nothing and exits 0 for the calls named in
# HO_EMPTY_GH ("issue list" or "api"), as a broken gh or proxy could.
mkdir -p "$PWD/emptygh"
cat > "$PWD/emptygh/gh" <<EOF
#!/bin/bash
case "\${HO_EMPTY_GH-}" in
  api) [ "\$1" = api ] && exit 0 ;;
  ?*) [ "\$1 \$2" = "\$HO_EMPTY_GH" ] && exit 0 ;;
esac
exec "$fake" "\$@"
EOF
chmod 700 "$PWD/emptygh/gh"
eg() { PATH="$PWD/emptygh:$PATH" "$@"; }

"$h" tickets add "One ready" body.md >/dev/null
assert_eq "test setup: the ready ticket is listed" 1 "$("$h" tickets ids ready)"
rc=0; out=$(HO_EMPTY_GH="issue list" eg "$h" tickets ids ready 2>"$PWD/err") || rc=$?
assert_eq "D2 (#110): a listing that prints nothing fails the verb, never reads as no tickets" "1:" "$rc:$out"
assert_contains "D2 (#110): the failure says the listing printed nothing" "$(cat "$PWD/err")" "printed nothing"

# ---- the 200-issue limit is named when it is reached ----
i=2
while [ $i -le 201 ]; do
  jq -n --argjson n "$i" '{number: $n, title: "t\($n)", body: "", state: "OPEN", updatedAt: "2026-01-01T00:00:00Z",
    labels: ["harness:ready"], assignees: [], comments: []}' > "$HO_FAKE_GH_DIR/issues/$i.json"
  i=$((i + 1))
done
out=$("$h" tickets ids ready 2>"$PWD/err")
assert_eq "test setup: the listing stops at 200" 200 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_contains "H-002 (#110, #88): a listing that reaches its limit of 200 warns on stderr" "$(cat "$PWD/err")" "limit of 200"
"$h" tickets ids blocked > /dev/null 2>"$PWD/err"
assert_eq "H-002: a short listing prints no warning" "" "$(cat "$PWD/err")"

# ---- the run-end decision: an open-issue listing that prints nothing is unknown ----
proj="$PWD/proj"
mkdir -p "$proj/.harness" "$PWD/user"
printf '%s\n' '{"schemaVersion":2}' > "$proj/.harness/config.json"
printf '%s\n' '{"schemaVersion":2}' > "$PWD/user/config.json"
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$PWD/user"
select_config "$proj"
for f in "$HO_FAKE_GH_DIR"/issues/*.json; do jq '.labels = ["harness:done"]' "$f" > "$PWD/i.json" && cat "$PWD/i.json" > "$f"; done
run=$("$h" run new)
rc=0; HO_EMPTY_GH=api eg "$h" lifecycle "$run" check >/dev/null 2>&1 || rc=$?
assert_eq "H-079 (#110): an open-issue listing that prints nothing gives unknown (exit 2), never an end" 2 "$rc"
ends=$(jq -r 'select(.kind == "run-end") | .kind' "$run/ledger.jsonl")
assert_eq "H-079 (#110): that unknown ends nothing" none "${ends:-none}"
o=$("$h" lifecycle "$run" check 2>/dev/null || true)
assert_eq "test setup: with a real listing the run ends" end "$(printf '%s\n' "$o" | head -n 1)"
