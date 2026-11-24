# H-017: unique local ticket numbers under concurrent adds (approved hand patch: ids under a lock).
h="$HO_PLUGIN_ROOT/bin/harness"
printf '## Outcome\nx\n\n## Scope\ny\n\n## Acceptance criteria\nz\n' > body.md

for n in 2 20 50; do
  export HO_TICKETS_DIR="$PWD/q$n/tickets"
  mkdir -p "out$n"
  pids=""
  i=1
  while [ "$i" -le "$n" ]; do
    ( rc=0; "$h" tickets add "Ticket $i of $n" body.md > "out$n/$i.out" 2> "out$n/$i.err" || rc=$?; echo "$rc" > "out$n/$i.rc" ) &
    pids="$pids $!"
    i=$((i + 1))
  done
  for p in $pids; do wait "$p" || true; done
  ok_count=$(cat "out$n"/*.rc | grep -cx 0 || true)
  assert_eq "H-017 $n parallel adds: every add exits 0" "$n" "$ok_count"
  ids=$(sed -n 's/^OK created ticket \([0-9][0-9]*\) .*/\1/p' "out$n"/*.out | sort -n)
  assert_eq "H-017 $n parallel adds: $n distinct ids reported" "$n" "$(printf '%s\n' "$ids" | sort -u | grep -c . || true)"
  assert_eq "H-017 $n parallel adds: ids are exactly 1..$n" "$(seq 1 "$n" | tr '\n' ' ')" "$(printf '%s\n' "$ids" | tr '\n' ' ')"
  files=$(find "$HO_TICKETS_DIR" -maxdepth 1 -name '[0-9]*-*.md' | wc -l | tr -d ' ')
  assert_eq "H-017 $n parallel adds: $n ticket files on disk" "$n" "$files"
  file_ids=$(find "$HO_TICKETS_DIR" -maxdepth 1 -name '[0-9]*-*.md' | sed 's|.*/||; s|-.*||' | sort -u | wc -l | tr -d ' ')
  assert_eq "H-017 $n parallel adds: no two files share an id" "$n" "$file_ids"
  # Every reported id points at the file of the add that reported it (nothing overwritten).
  mism=0
  i=1
  while [ "$i" -le "$n" ]; do
    id=$(sed -n 's/^OK created ticket \([0-9][0-9]*\) .*/\1/p' "out$n/$i.out")
    f=$(find "$HO_TICKETS_DIR" -maxdepth 1 -name "$id-*.md" | head -1)
    [ -n "$f" ] && [ "$(sed -n 's/^title: //p' "$f")" = "Ticket $i of $n" ] || mism=$((mism + 1))
    i=$((i + 1))
  done
  assert_eq "H-017 $n parallel adds: each ticket file holds its own title" "0" "$mism"
  assert_eq "H-017 $n parallel adds: the lock is released" "no" "$( [ -e "$PWD/q$n/.tickets.lock" ] && echo yes || echo no)"
done

# A lock held by a live add makes a second add wait, then give up with 75 and create nothing.
export HO_TICKETS_DIR="$PWD/held/tickets"
mkdir -p "$HO_TICKETS_DIR" "$PWD/held/.tickets.lock"
rc=0; err=$(HO_TICKET_LOCK_WAIT=1 "$h" tickets add "Waits" body.md 2>&1 >/dev/null) || rc=$?
assert_eq "H-017 held lock: add exits 75" "75" "$rc"
assert_contains "H-017 held lock: add says no change was made" "$err" "no change made"
assert_eq "H-017 held lock: no ticket file is written" "0" "$(find "$HO_TICKETS_DIR" -name '*.md' | wc -l | tr -d ' ')"

# An abandoned lock (older than HO_TICKET_LOCK_STALE) is taken over, and the add succeeds.
touch -t 200001010000 "$PWD/held/.tickets.lock"
rc=0; out=$(HO_TICKET_LOCK_STALE=60 "$h" tickets add "After stale" body.md 2>/dev/null) || rc=$?
assert_eq "H-017 stale lock: add exits 0" "0" "$rc"
assert_contains "H-017 stale lock: add creates ticket 1" "$out" "OK created ticket 1 "

# Ids are never reused: after ticket 1 is gone from the list, the next add still gets the next number.
assert_contains "H-017 sequential add: next id follows the highest on disk" "$("$h" tickets add "Second" body.md)" "OK created ticket 2 "
