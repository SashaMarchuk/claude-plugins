# Design Rebuild reuse list: the STOP file, decision log and owner-action log merged into one
# append-only run ledger; every marker carries the run ID. S8-27 (run IDs in stale markers),
# PR-1 (a foreign marker is ignored), field note D1 (appended lines survive),
# "Separate state": a run without a stamp is refused and left byte-identical.
h="$HO_PLUGIN_ROOT/bin/harness"
proj="$PWD/proj"
mkdir -p "$proj/.harness"
printf '%s\n' '{"schemaVersion":2}' > "$proj/.harness/config.json"
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$PWD/user"

# Checksum of a whole folder: every path (files, folders, empty folders), file modes and contents.
tree_sum() {
  (cd "$1" && find . -print | LC_ALL=C sort | while IFS= read -r p; do
    if [ -d "$p" ]; then printf 'd %s\n' "$p"
    elif [ -L "$p" ]; then printf 'l %s %s\n' "$p" "$(readlink "$p")"
    else printf 'f %s %s %s\n' "$p" "$([ -x "$p" ] && echo x || echo -)" "$(cksum < "$p")"
    fi
  done) | cksum
}

# ---- a new run is stamped ----------------------------------------------------
run=$("$h" run new)
id=$(basename "$run")
assert_eq "Rebuild run: a new run lives under .harness/runs" "$proj/.harness/runs/$id" "$run"
assert_eq "Rebuild run: the stamp has schemaVersion 2" "2" "$(jq -r .schemaVersion "$run/run.json")"
assert_eq "Rebuild run: the stamp names the run ID of its folder" "$id" "$(jq -r .runId "$run/run.json")"
assert_exit "Rebuild run: a stamped run passes the check" 0 "$h" state "$run" check
run2=$("$h" run new)
assert_eq "Rebuild run: two runs started in the same second get different IDs" "no" "$([ "$run" = "$run2" ] && echo yes || echo no)"
assert_eq "Rebuild run: the ledger starts with a run-start line" "run-start" "$(head -1 "$run/ledger.jsonl" | jq -r .kind)"

# ---- every marker and every ledger line carries the run ID (S8-27) -------------
"$h" state "$run" marker set lane-a.pr-ready
"$h" state "$run" marker set lane-b.blocked
"$h" state "$run" decision "pick x" "because y"
"$h" state "$run" owner-action "deploy" "needs a secret" "make deploy" "site is up"
"$h" state "$run" marker clear lane-b.blocked
assert_exit "S8-27: a marker set by this run reads as set" 0 "$h" state "$run" marker check lane-a.pr-ready
assert_exit "S8-27: a cleared marker reads as not set" 1 "$h" state "$run" marker check lane-b.blocked
n=0; missing=""
for m in "$run"/markers/*; do
  [ -f "$m" ] || continue
  n=$((n + 1))
  [ "$(jq -r .run "$m" 2>/dev/null)" = "$id" ] || missing="$missing $(basename "$m")"
done
assert_eq "S8-27: the engine wrote at least one marker file" "yes" "$([ "$n" -gt 0 ] && echo yes || echo no)"
assert_eq "S8-27: every marker file written by the engine contains the run ID" "" "$missing"
assert_eq "Rebuild ledger: every ledger line carries the run ID" "" "$(jq -r --arg id "$id" 'select(.run != $id) | .kind' "$run/ledger.jsonl")"
assert_eq "Rebuild ledger: every ledger line has a time" "" "$(jq -r 'select((.ts // "") == "") | .kind' "$run/ledger.jsonl")"
assert_eq "Rebuild ledger: the decision line keeps its reason" "because y" "$(jq -r 'select(.kind == "decision") | .reason' "$run/ledger.jsonl")"
assert_eq "Rebuild ledger: the owner-action line keeps its command" "make deploy" "$(jq -r 'select(.kind == "owner-action") | .command' "$run/ledger.jsonl")"

# ---- PR-1: a marker without this run's ID is foreign --------------------------
printf '%s\n' "{\"run\":\"$(basename "$run2")\",\"name\":\"lane-c.done\"}" > "$run/markers/lane-c.done"
printf 'Mon Nov 24 2026\n' > "$run/markers/lane-d.done"
assert_exit "PR-1: a marker with another run's ID reads as not set" 1 "$h" state "$run" marker check lane-c.done
assert_exit "PR-1: a marker with no run ID (0.6.0 shape) reads as not set" 1 "$h" state "$run" marker check lane-d.done
"$h" state "$run" marker check lane-c.done || true
assert_eq "PR-1: each foreign marker is logged once in the ledger, not on every check" "lane-c.done lane-d.done" \
  "$(jq -r 'select(.kind == "marker-foreign") | .name' "$run/ledger.jsonl" | tr '\n' ' ' | sed 's/ $//')"
assert_exit "PR-1: a foreign marker does not stop this run's own markers" 0 "$h" state "$run" marker check lane-a.pr-ready
assert_exit "Rebuild run: a bad marker name is refused" 65 "$h" state "$run" marker set "../escape"
rc=0; "$h" state "$run" marker clear lane-c.done >/dev/null 2>&1 || rc=$?
assert_eq "PR-1: clear does not remove another run's marker" "1 yes" "$rc $([ -f "$run/markers/lane-c.done" ] && echo yes)"
: > "$run/markers/lane-f.done"
assert_exit "S8-27: an empty marker file reads as not set" 1 "$h" state "$run" marker check lane-f.done
long=$(printf '%5000s' | tr ' ' x)
assert_exit "Rebuild ledger: a line over 4000 bytes is refused, not split" 65 "$h" state "$run" decision big "$long"

# ---- the ledger only grows ------------------------------------------------------
grew_ok=yes
check_grows() {
  local before after
  before=$(cat "$run/ledger.jsonl"; printf x)
  "$@" >/dev/null 2>&1 || true
  after=$(cat "$run/ledger.jsonl"; printf x)
  before=${before%x}; after=${after%x}
  case $after in "$before"*) ;; *) grew_ok="no after: $*" ;; esac
}
printf '%s\n' '{"ts":"t","run":"'"$id"'","kind":"note","by":"another writer"}' >> "$run/ledger.jsonl"
check_grows "$h" state "$run" marker set lane-e.done
check_grows "$h" state "$run" marker clear lane-e.done
check_grows "$h" state "$run" marker check lane-c.done
check_grows "$h" state "$run" decision "t" "multi
line reason"
check_grows "$h" state "$run" owner-action a b c d
check_grows "$h" state "$run" stop "owner asked"
assert_eq "Rebuild ledger: no verb rewrites or removes an earlier line" "yes" "$grew_ok"
assert_eq "D1: a line appended by another writer survives later writes" "another writer" "$(jq -r 'select(.kind == "note") | .by' "$run/ledger.jsonl")"
assert_eq "Rebuild ledger: a multi-line reason stays on one ledger line" "multi
line reason" "$(jq -r 'select(.kind == "decision" and .title == "t") | .reason' "$run/ledger.jsonl")"
bad_lines=$(while IFS= read -r l; do printf '%s' "$l" | jq -e . >/dev/null 2>&1 || echo bad; done < "$run/ledger.jsonl")
assert_eq "Rebuild ledger: every ledger line is valid JSON" "" "$bad_lines"

# Parallel writers each get exactly one whole line, even near the line cap
# (bash can split one printf of about 4 KB into several writes).
big=$(printf '%3800s' | tr ' ' y)
lines_before=$(wc -l < "$run2/ledger.jsonl")
i=0
while [ $i -lt 40 ]; do "$h" state "$run2" decision "p$i" "$big" & i=$((i + 1)); done
wait
assert_eq "Rebuild ledger: 40 parallel writers add 40 lines" "$((lines_before + 40))" "$(($(wc -l < "$run2/ledger.jsonl")))"
assert_eq "Rebuild ledger: 40 parallel lines are all whole JSON" "40" "$(jq -cR 'fromjson? | select(.reason == "'"$big"'") | .title' "$run2/ledger.jsonl" | sort -u | wc -l | tr -d ' ')"
assert_eq "Rebuild ledger: no lock is left behind" "" "$(ls -A "$run2" | grep lock || true)"
mkdir "$run2/ledger.jsonl.lock"
touch -t 202001010000 "$run2/ledger.jsonl.lock"
assert_exit "Rebuild ledger: a lock left by a killed writer is taken over" 0 "$h" state "$run2" decision stale-lock ok

# ---- STOP: the file is kept for users and recorded in the ledger -----------------
assert_exit "H-086: a run with no STOP reads as not stopped" 1 "$h" state "$run2" stopped
: > "$proj/.harness/STOP"
assert_exit "H-086: the STOP file stops the run" 0 "$h" state "$run2" stopped
"$h" state "$run2" stopped || true
assert_eq "H-086: the STOP file is recorded once in the ledger, as the default soft stop" "soft:step" \
  "$(jq -r 'select(.kind == "stop" and .source == "file") | .type' "$run2/ledger.jsonl" | tr '\n' ' ' | sed 's/ $//')"
assert_exit "Rebuild ledger: resume is refused while the STOP file exists" 75 "$h" state "$run2" resume
assert_exit "Rebuild run: a new run is refused while the STOP file exists" 75 "$h" run new
rm "$proj/.harness/STOP"
assert_exit "Rebuild ledger: a recorded stop stays in force after the STOP file is gone" 0 "$h" state "$run2" stopped
"$h" state "$run2" resume
assert_exit "Rebuild ledger: resume after a stop reads as not stopped" 1 "$h" state "$run2" stopped
assert_exit "Rebuild ledger: the stop verb stops a run" 0 "$h" state "$run" stopped
assert_eq "Rebuild ledger: the stop verb records its reason" "owner asked" "$(jq -r 'select(.kind == "stop") | .reason' "$run/ledger.jsonl")"
printf '{"ts":"t","run":"%s","kind":"sto' "$(basename "$run2")" >> "$run2/ledger.jsonl"
rc=0; err=$("$h" state "$run2" stopped 2>&1) || rc=$?
assert_eq "I1: an unreadable ledger line makes the stop check unknown (exit 2), never not-stopped" "2" "$rc"
assert_contains "I1: the unknown stop check says the ledger is unreadable" "$err" "unreadable"
"$h" state "$run2" decision after-torn ok
assert_eq "Rebuild ledger: a line appended after a torn line is still whole" "ok" "$(jq -cR 'fromjson? | select(.title == "after-torn") | .reason' "$run2/ledger.jsonl" | tr -d '"')"

# ---- a 0.6.0 run, or any run without a valid stamp, is refused and left byte-identical
old="$proj/.harness/runs/20261124-174036"
mkdir -p "$old/launchers" "$old/prompts" "$old/state" "$old/logs" "$old/heartbeats" "$old/markers"
printf '\n## 2026-11-24T17:50:00Z - pick\nwhy\n' > "$old/DECISIONS.md"
printf '2026-11-24T18:00:00Z\n' > "$old/markers/lane.pr-ready.done"
printf '2026-11-24T18:00:00Z step\n' > "$old/heartbeats/w-lane"
printf '#!/bin/sh\n' > "$old/launchers/w-lane.sh"; chmod +x "$old/launchers/w-lane.sh"
copy="$PWD/copy-0.6.0"
cp -Rp "$old" "$copy"
bad_stamp="$proj/.harness/runs/bad-stamp"
mkdir -p "$bad_stamp" "$proj/.harness/runs/wrong-id" "$proj/.harness/runs/schema1"
printf 'not json' > "$bad_stamp/run.json"
printf '%s\n' '{"schemaVersion":2,"engine":"harness-orchestrator","runId":"other"}' > "$proj/.harness/runs/wrong-id/run.json"
printf '%s\n' '{"schemaVersion":1,"engine":"harness-orchestrator","runId":"schema1"}' > "$proj/.harness/runs/schema1/run.json"
: > "$proj/.harness/STOP"
for target in "$copy" "$bad_stamp" "$proj/.harness/runs/wrong-id" "$proj/.harness/runs/schema1" "$PWD/missing-run"; do
  label=$(basename "$target")
  sum_before=$([ -e "$target" ] && tree_sum "$target" || echo none)
  refused=yes; said=yes
  for verb in "check" "marker set x.done" "marker clear lane.pr-ready" "marker check lane.pr-ready" \
              "decision t r" "owner-action a b c d" "stop r" "stopped" "resume"; do
    rc=0
    # shellcheck disable=SC2086
    err=$("$h" state "$target" $verb 2>&1 >/dev/null) || rc=$?
    [ "$rc" -eq 66 ] || refused="no: $verb exit $rc"
    case $err in *"refusing run folder"*) ;; *) said="no: $verb" ;; esac
  done
  assert_eq "Rebuild separate state: every state verb refuses $label with exit 66" "yes" "$refused"
  assert_eq "Rebuild separate state: the refusal of $label says why" "yes" "$said"
  assert_eq "Rebuild separate state: $label is byte-identical after the refusals" "$sum_before" "$([ -e "$target" ] && tree_sum "$target" || echo none)"
done
rm "$proj/.harness/STOP"
assert_eq "Rebuild separate state: the copied 0.6.0 run still matches the original" "$(tree_sum "$old")" "$(tree_sum "$copy")"

# I1: an unreadable line early in a long ledger still makes the stop check unknown.
run3=$("$h" run new)
printf 'garbage\n' >> "$run3/ledger.jsonl"
i=0
while [ $i -lt 40 ]; do "$h" state "$run3" decision "q$i" "$big"; i=$((i + 1)); done
rc=0; "$h" state "$run3" stopped >/dev/null 2>&1 || rc=$?
assert_eq "I1: an unreadable early line in a long ledger makes the stop check unknown (exit 2)" "2" "$rc"

# A lock held by a dead writer is taken over at once, not after a minute.
sh -c 'exit 0' &
dead=$!
wait "$dead" || true
mkdir "$run3/ledger.jsonl.lock"
printf '%s\n' "$dead" > "$run3/ledger.jsonl.lock/pid"
t0=$(date +%s)
rc=0; "$h" state "$run3" decision dead-lock ok >/dev/null 2>&1 || rc=$?
t1=$(date +%s)
assert_eq "Rebuild ledger: a lock held by a dead writer is taken over" "0" "$rc"
assert_eq "Rebuild ledger: taking over a dead writer's lock takes under 5 s" "yes" "$([ $((t1 - t0)) -lt 5 ] && echo yes || echo no)"
assert_eq "Rebuild ledger: the line after a dead writer's lock is written" "ok" "$(jq -cR 'fromjson? | select(.title == "dead-lock") | .reason' "$run3/ledger.jsonl" | tr -d '"')"

# After a torn line, the owner's resume or stop makes the stop state known again.
"$h" state "$run3" resume
rc=0; "$h" state "$run3" stopped >/dev/null 2>&1 || rc=$?
assert_eq "I1: a resume after an unreadable line makes the stop state known again (not stopped)" "1" "$rc"
printf 'torn{' >> "$run3/ledger.jsonl"
rc=0; "$h" state "$run3" stopped >/dev/null 2>&1 || rc=$?
assert_eq "I1: an unreadable line after the last resume makes the stop state unknown again" "2" "$rc"
"$h" state "$run3" stop "owner"
assert_exit "I1: a stop after an unreadable line reads as stopped" 0 "$h" state "$run3" stopped

# A bare run ID or ./<id>, typed inside .harness/runs, still finds the STOP file (#37 concern 1).
run4=$("$h" run new)
id4=$(basename "$run4")
: > "$proj/.harness/STOP"
for form in "$id4" "./$id4"; do
  rc=0; (cd "$proj/.harness/runs" && "$h" state "$form" stopped >/dev/null 2>&1) || rc=$?
  assert_eq "H-086: run path '$form' typed inside .harness/runs sees the STOP file (stopped exits 0)" "0" "$rc"
  rc=0; (cd "$proj/.harness/runs" && "$h" state "$form" resume >/dev/null 2>&1) || rc=$?
  assert_eq "H-086: run path '$form' typed inside .harness/runs refuses resume while STOP exists (exit 75)" "75" "$rc"
done
rm "$proj/.harness/STOP"

# marker set writes its ledger line first: when the ledger cannot be written, no marker appears.
chmod 444 "$run4/ledger.jsonl"
rc=0; "$h" state "$run4" marker set lane-z.done >/dev/null 2>&1 || rc=$?
chmod 644 "$run4/ledger.jsonl"
assert_eq "Rebuild ledger: marker set fails when the ledger cannot be written" "yes" "$([ "$rc" -ne 0 ] && echo yes || echo no)"
assert_eq "Rebuild ledger: no marker exists without its ledger line" "no" "$([ -e "$run4/markers/lane-z.done" ] && echo yes || echo no)"

# A symlinked path to the run folder still finds the STOP file (PR #87 review, Codex P2).
run6=$("$h" run new)
ln -s "$proj/.harness/runs" "$PWD/runs-link"
: > "$proj/.harness/STOP"
rc=0; "$h" state "$PWD/runs-link/$(basename "$run6")" stopped >/dev/null 2>&1 || rc=$?
assert_eq "H-086: a run path through a symlink sees the STOP file (stopped exits 0)" "0" "$rc"
rc=0; "$h" state "$PWD/runs-link/$(basename "$run6")" resume >/dev/null 2>&1 || rc=$?
assert_eq "H-086: a run path through a symlink refuses resume while STOP exists (exit 75)" "75" "$rc"
rm "$proj/.harness/STOP"

# A project whose .harness/runs is itself a link to another place: STOP in the
# project still stops the run (PR #87 re-check, B2).
proj2="$PWD/proj2"; mkdir -p "$proj2/.harness" "$PWD/elsewhere-runs"
cp "$proj/.harness/config.json" "$proj2/.harness/config.json"
ln -s "$PWD/elsewhere-runs" "$proj2/.harness/runs"
run8=$(cd "$proj2" && HO_PROJECT_DIR="$proj2" "$h" run new)
assert_eq "H-086 setup: a run starts in a project with a linked runs folder" "yes" "$([ -n "$run8" ] && [ -d "$run8" ] && echo yes || echo no)"
: > "$proj2/.harness/STOP"
rc=0; (cd "$proj2" && HO_PROJECT_DIR="$proj2" "$h" state "$run8" stopped) >/dev/null 2>&1 || rc=$?
assert_eq "H-086: a linked runs folder still sees the project STOP file (stopped exits 0)" "0" "$rc"
rc=0; (cd "$proj2" && HO_PROJECT_DIR="$proj2" "$h" state "$run8" resume) >/dev/null 2>&1 || rc=$?
assert_eq "H-086: a linked runs folder refuses resume while STOP exists (exit 75)" "75" "$rc"
rm "$proj2/.harness/STOP"

# TERM while an append holds the ledger lock: the lock is freed, the process exits 143 and
# appends nothing (PR #87 review, Codex P2). A fake tail holds the append inside the lock.
run7=$("$h" run new)
real_tail=$(command -v tail)
mkdir -p slow-bin
cat > slow-bin/tail <<SLOW
#!/bin/sh
: > "$PWD/tail.ready"
n=0
while [ ! -e "$PWD/tail.go" ] && [ "\$n" -lt 100 ]; do sleep 0.1; n=\$((n + 1)); done
exec "$real_tail" "\$@"
SLOW
chmod +x slow-bin/tail
lines=$(wc -l < "$run7/ledger.jsonl" | tr -d ' ')
PATH="$PWD/slow-bin:$PATH" "$h" state "$run7" decision "late" "must not land" >/dev/null 2>&1 &
pid=$!
n=0
while [ ! -e tail.ready ] && [ "$n" -lt 100 ]; do sleep 0.1; n=$((n + 1)); done
kill -TERM "$pid" 2>/dev/null || true
: > tail.go
rc=0; wait "$pid" || rc=$?
assert_eq "Rebuild ledger: TERM under the ledger lock exits 143" "143" "$rc"
assert_eq "Rebuild ledger: TERM under the ledger lock appends nothing" "$lines" "$(wc -l < "$run7/ledger.jsonl" | tr -d ' ')"
assert_eq "Rebuild ledger: TERM under the ledger lock frees the lock" "no" "$([ -e "$run7/ledger.jsonl.lock" ] && echo yes || echo no)"

# A run folder whose ledger, markers or stamp is a link is refused, and nothing is
# appended through the link (PR #87, Codex security finding on d21e455).
for what in ledger markers stamp; do
  runL=$("$h" run new)
  printf 'outside\n' > "$PWD/outside-$what.txt"; cp "$PWD/outside-$what.txt" "$PWD/outside-$what.before"
  case $what in
    ledger)  rm "$runL/ledger.jsonl"; ln -s "$PWD/outside-$what.txt" "$runL/ledger.jsonl" ;;
    markers) rm -rf "$runL/markers"; mkdir -p "$PWD/outside-markers"; ln -s "$PWD/outside-markers" "$runL/markers" ;;
    stamp)   mv "$runL/run.json" "$PWD/stamp-$what.json"; ln -s "$PWD/stamp-$what.json" "$runL/run.json" ;;
  esac
  rc=0; "$h" state "$runL" stop >/dev/null 2>&1 || rc=$?
  assert_eq "Rebuild ledger: a run with a linked $what is refused (exit 66)" "66" "$rc"
  assert_eq "Rebuild ledger: nothing is written through a linked $what" "same" "$(cmp -s "$PWD/outside-$what.txt" "$PWD/outside-$what.before" && [ -z "$(ls -A "$PWD/outside-markers" 2>/dev/null)" ] && echo same || echo changed)"
done
