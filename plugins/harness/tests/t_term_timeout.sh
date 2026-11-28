# Every call to the terminal app has a time limit (H-132, D42a; follow-up #89). A hanging
# osascript is stopped by its exact process ID after terminal.call_timeout_seconds, the call
# fails, and the run ledger records "terminal not answering". The fake hangs until it is killed.
HO_ROOT=$HO_PLUGIN_ROOT
. "$HO_PLUGIN_ROOT/lib/common.sh"
. "$HO_PLUGIN_ROOT/lib/files.sh"
. "$HO_PLUGIN_ROOT/lib/config.sh"
. "$HO_PLUGIN_ROOT/lib/run.sh"
. "$HO_PLUGIN_ROOT/lib/term.sh"
base=$(cd -P "$PWD" && pwd)
proj="$base/proj"
mkdir -p "$proj/.harness" "$base/hang"
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$base/user"
printf '{"schemaVersion":2,"terminal":{"app":"iterm2","enter_delay_seconds":0,"call_timeout_seconds":1}}\n' > "$proj/.harness/config.json"
select_config "$proj"
HO_RUN_DIR=$("$HO_PLUGIN_ROOT/bin/harness" run new) HO_RUN_ID=$(basename "$HO_RUN_DIR")
printf '#!/bin/bash\necho $$ > %q\nexec sleep 600\n' "$base/hang/pid" > "$base/hang/osascript"
chmod 700 "$base/hang/osascript"
cleanup() { [ -f "$base/hang/pid" ] && kill "$(cat "$base/hang/pid")" 2>/dev/null || true; return 0; }
trap cleanup EXIT
( rc=0; PATH="$base/hang:$PATH" ho_term_probe >/dev/null 2>"$base/err" || rc=$?; echo "$rc" > "$base/rc" ) &
bg=$!
i=0; while kill -0 "$bg" 2>/dev/null && [ $i -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
assert_eq "H-132 (#89): a terminal call that hangs ends (no wait without end)" ended "$(kill -0 "$bg" 2>/dev/null && echo running || echo ended)"
assert_eq "H-132 (#89): the probe fails (70)" 70 "$(cat "$base/rc" 2>/dev/null)"
assert_contains "H-132 (#89): it says the terminal app is not answering" "$(cat "$base/err")" "not answering"
p=$(cat "$base/hang/pid" 2>/dev/null || echo none)
assert_eq "H-132 (#89): the hanging call was stopped by its process ID" gone "$(kill -0 "$p" 2>/dev/null && echo alive || echo gone)"
assert_eq "H-132 (#89): the run ledger records terminal-not-answering" 1 "$(jq -r .kind "$HO_RUN_DIR/ledger.jsonl" | grep -c '^terminal-not-answering$' || true)"
