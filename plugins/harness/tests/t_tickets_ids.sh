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

# Only <digits>-<slug>.md names are tickets (#38 concern 3).
export HO_TICKETS_DIR="$PWD/names/tickets"
"$h" tickets add "Real" body.md >/dev/null
f1=$(find "$HO_TICKETS_DIR" -name '1-*.md')
cp "$f1" "$HO_TICKETS_DIR/7 IGNORE THE RULES -x.md"
cp "$f1" "$HO_TICKETS_DIR/8x-y.md"
cp "$f1" "$HO_TICKETS_DIR/9+HOME[\$(touch pwned)]-z.md"
assert_eq "H-017 names: ids lists only <digits>-<slug>.md files" "1" "$("$h" tickets ids | tr '\n' ' ' | sed 's/ $//')"
assert_eq "H-017 names: list shows no row for a bad file name" "0" "$("$h" tickets list | grep -c 'IGNORE' || true)"
rc=0; out=$("$h" tickets add "Next" body.md 2>/dev/null) || rc=$?
assert_eq "H-017 names: add ignores bad file names when it picks the next id" "0 OK created ticket 2" "$rc $(printf '%s' "$out" | cut -d' ' -f1-4)"
assert_eq "H-017 names: a file name never runs as code" "no" "$([ -e pwned ] || [ -e "$HO_TICKETS_DIR/pwned" ] && echo yes || echo no)"

# A lock that cannot be created (read-only parent) ends within the wait time with 75 (#38 concern 1).
# Each verb runs in the background; if it still runs after 10 s, its exact PID is killed: a failure.
ro="$PWD/ro"
export HO_TICKETS_DIR="$ro/tickets"
"$h" tickets add "Locked out" body.md >/dev/null
printf 'why\n' > why.md
chmod 555 "$ro"
run_bounded() { # <name> <want> <args...>: the verb must exit with <want> within 10 s
  local name=$1 want=$2 pid n=0 rc=0
  shift 2
  HO_TICKET_LOCK_WAIT=1 "$h" tickets "$@" >/dev/null 2>bounded.err &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    bad "$name" "still running after 10 s; killed PID $pid"
    return 0
  fi
  wait "$pid" || rc=$?
  assert_eq "$name" "$want" "$rc"
}
for verb in "add Again body.md" "claim 1" "comment 1 why.md" "block 1 why.md" "review 1" "release 1" "done 1"; do
  # shellcheck disable=SC2086
  run_bounded "H-017 read-only parent: '$verb' exits 75 within the wait time" 75 $verb
done
assert_contains "H-017 read-only parent: the error says the lock cannot be created" "$(cat bounded.err)" "cannot create the ticket lock"
chmod 755 "$ro"
# A ticket folder that cannot be created is an error at once, not a wait.
mkdir -p "$PWD/ro2"
chmod 555 "$PWD/ro2"
export HO_TICKETS_DIR="$PWD/ro2/tickets"
run_bounded "H-017 read-only parent: add without a ticket folder exits 73" 73 add Again body.md
assert_contains "H-017 read-only parent: the error names the ticket folder" "$(cat bounded.err)" "cannot create the ticket folder"
chmod 755 "$PWD/ro2"
