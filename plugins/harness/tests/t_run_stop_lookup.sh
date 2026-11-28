# The STOP file lookups of a run (H-086, D25b; wave-1 follow-ups #88). Each of the three places
# finds STOP on its own: beside the logical run path, beside the physical run path, and in the
# run's own project as recorded in run.json at start. Another project's STOP never stops it.
# Every check runs from outside any project with no HO_PROJECT_DIR, each on a fresh run: a STOP
# file once seen is recorded in the ledger as a stop and would answer every later check.
h="$HO_PLUGIN_ROOT/bin/harness"
base=$(cd -P "$PWD" && pwd)
export HO_USER_DIR="$base/user"
mkdir -p "$base/user" "$base/outside"
mkproj() { mkdir -p "$1/.harness"; printf '%s\n' '{"schemaVersion":2}' > "$1/.harness/config.json"; select_config "$1"; }
stopped() { local rc=0; (cd "$base/outside" && env -u HO_PROJECT_DIR "$h" state "$1" stopped >/dev/null 2>&1) || rc=$?; echo "$rc"; }

# ---- the project, as recorded in run.json ----
p1="$base/p1"; mkproj "$p1"
mkdir -p "$base/far-runs"; ln -s "$base/far-runs" "$p1/.harness/runs"
r1=$(cd "$p1" && HO_PROJECT_DIR="$p1" "$h" run new)
assert_eq "H-086 (#88): run.json records the run's project" "$p1" "$(jq -r '.project // ""' "$r1/run.json")"
phys="$base/far-runs/$(basename "$r1")"
assert_eq "test setup: without a STOP file the run is not stopped" 1 "$(stopped "$phys")"
: > "$p1/.harness/STOP"
assert_eq "H-086 (#88): a linked runs folder opened by its physical path from outside sees the project STOP" 0 "$(stopped "$phys")"
rm -f "$p1/.harness/STOP"

# ---- another project's STOP file does not stop this run ----
p2="$base/p2"; mkproj "$p2"
r2=$(cd "$p2" && HO_PROJECT_DIR="$p2" "$h" run new)
p3="$base/p3"; mkproj "$p3"
: > "$p3/.harness/STOP"
rc=0; (cd "$p3" && env -u HO_PROJECT_DIR "$h" state "$r2" stopped >/dev/null 2>&1) || rc=$?
assert_eq "H-086 (#88): a STOP file of the caller's other project does not stop this run" 1 "$rc"
rm -f "$p3/.harness/STOP"

# ---- the logical path alone ----
mkdir -p "$base/alias/.harness"; ln -s "$p2/.harness/runs" "$base/alias/.harness/runs"
r4=$(cd "$p2" && HO_PROJECT_DIR="$p2" "$h" run new)
: > "$base/alias/.harness/STOP"
assert_eq "H-086 (#88): STOP beside the logical run path alone stops the run" 0 "$(stopped "$base/alias/.harness/runs/$(basename "$r4")")"
rm -f "$base/alias/.harness/STOP"

# ---- the physical path alone ----
# The recorded project is p1; STOP beside the physical path (far-runs' parent) is not in p1.
r5=$(cd "$p1" && HO_PROJECT_DIR="$p1" "$h" run new)
: > "$base/STOP"
assert_eq "H-086 (#88): STOP beside the physical run path alone stops the run" 0 "$(stopped "$p1/.harness/runs/$(basename "$r5")")"
rm -f "$base/STOP"

# ---- marker set on a folder ----
mkdir -p "$r2/markers/lane-q.done"
rc=0; "$h" state "$r2" marker set lane-q.done >/dev/null 2>&1 || rc=$?
assert_eq "Rebuild run (#88): marker set fails when a folder stands at the marker path" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
rc=0; "$h" state "$r2" marker check lane-q.done >/dev/null 2>&1 || rc=$?
assert_eq "Rebuild run: that marker reads as not set" 1 "$rc"
