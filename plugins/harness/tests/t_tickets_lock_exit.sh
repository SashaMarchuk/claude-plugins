# Design reuse list (ticket queue, locked writes) and field note I3: a failure under the
# ticket lock must never read as success. The EXIT trap must keep the real exit code.
cat > probe.sh <<PROBE
set -euo pipefail
HO_TICKETS_SOURCE=local
HO_TICKETS_DIR="$PWD/q/tickets"
export HO_TICKETS_SOURCE HO_TICKETS_DIR
. "$HO_PLUGIN_ROOT/lib/tickets.sh"
ho_tk_settings
boom() { echo "\$ho_undefined_variable_for_test"; }
fails() { return 7; }
rc=0; ho_tk_locked boom >/dev/null 2>&1 || rc=\$?
echo "boom=\$rc"
rc=0; ho_tk_locked fails >/dev/null 2>&1 || rc=\$?
echo "fails=\$rc"
PROBE
out=$(bash probe.sh 2>/dev/null || true)
case $out in *"boom=0"*|"") bad "Reuse ticket lock: an unbound variable under the lock exits non-zero" "[$out]" ;; *) ok "Reuse ticket lock: an unbound variable under the lock exits non-zero" ;; esac
assert_contains "Reuse ticket lock: a failing function under the lock keeps its exit code" "$out" "fails=7"
assert_eq "Reuse ticket lock: the lock is released after a failure" "" "$(ls -d q/.tickets.lock 2>/dev/null || true)"
