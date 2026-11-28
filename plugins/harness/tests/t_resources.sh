# Out-of-memory cap lowering and usage history (H-106, H-108; design D26b, D37-LIMITS-1,
# D37-LIMITS-2, D37-LIMITS-4, D37-FLOW-8). The container runtime is a fake built here.
h="$HO_PLUGIN_ROOT/bin/harness"
base=$(cd -P "$PWD" && pwd)
proj="$base/proj"
user="$base/user"
mkdir -p "$proj/.harness" "$user" "$base/bin"
export HO_PROJECT_DIR="$proj" HO_USER_DIR="$user"
printf '{"schemaVersion": 2, "limits": {"workers": 2}}\n' > "$proj/.harness/config.json"
printf '{"schemaVersion": 2}\n' > "$user/config.json"
# A fake container runtime: its record of a container comes from $base/records/<id>.json.
cat > "$base/bin/docker" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_DOCKER_LOG"
[ "$1" = inspect ] && [ -f "$FAKE_RECORDS/$2.json" ] || { echo '[]'; exit 1; }
cat "$FAKE_RECORDS/$2.json"
SH
chmod +x "$base/bin/docker"
mkdir -p "$base/records"
export PATH="$base/bin:$PATH" FAKE_RECORDS="$base/records" FAKE_DOCKER_LOG="$base/docker.log"
rec() { printf '[{"State": {"OOMKilled": %s, "ExitCode": 137}}]\n' "$2" > "$base/records/$1.json"; }
cap() { jq -r .workers "$1/limits.json"; }
events() { jq -c "select(.kind == \"$2\")" "$1/ledger.jsonl" | wc -l | tr -d ' '; }

# ---- H-106: a confirmed stop lowers the cap by one ----
r=$("$h" run new)
rec c-oom1 true
out=$("$h" resources "$r" oom c-oom1 --ticket 7)
assert_eq "H-106: a confirmed out-of-memory stop turns cap 2 into 1" 1 "$(cap "$r")"
assert_contains "D37-LIMITS-4: the stopped task restarts through recovery" "$out" "restarts through recovery"
assert_contains "D37-LIMITS-1: the check reads the runtime's own record of that one container" "$(cat "$base/docker.log")" "inspect c-oom1"
assert_eq "D37-LIMITS-2: the lowering writes one ledger line with the reason" 1 "$(events "$r" cap-lowered)"
assert_eq "D37-LIMITS-2: the configured value stays as it is" 2 "$(jq -r .limits.workers "$proj/.harness/config.json")"
assert_eq "D37-LIMITS-2: a new run starts from the configured value" 2 "$(cap "$("$h" run new)")"

# ---- H-106: the same stop reported twice lowers once ----
r=$("$h" run new --workers 3)
rec c-oom2 true
"$h" resources "$r" oom c-oom2 > /dev/null
"$h" resources "$r" oom c-oom2 > /dev/null
assert_eq "H-106: one stop reported two times turns cap 3 into 2, not 1" 2 "$(cap "$r")"

# ---- H-106: an unconfirmed stop does not lower the cap ----
r=$("$h" run new)
rec c-kill false
"$h" resources "$r" oom c-kill > /dev/null
assert_eq "H-106: a stop the record does not call out of memory leaves the cap" 2 "$(cap "$r")"
"$h" resources "$r" oom c-gone > /dev/null
assert_eq "H-106: a container that is gone (record unreadable) leaves the cap" 2 "$(cap "$r")"
printf 'not json\n' > "$base/records/c-odd.json"
"$h" resources "$r" oom c-odd > /dev/null
assert_eq "H-106: an unclear answer leaves the cap" 2 "$(cap "$r")"
assert_eq "D37-LIMITS-1: each check writes one ledger line" 3 "$(events "$r" oom-check)"
assert_exit "D37-LIMITS-1: only an exact container ID is checked" 64 "$h" resources "$r" oom '-rf'

# ---- H-106: at cap 1 the cap stays 1 and the task restarts ----
r=$("$h" run new --workers 1)
rec c-oom3 true
out=$("$h" resources "$r" oom c-oom3)
assert_eq "H-106: with cap 1 the cap stays 1" 1 "$(cap "$r")"
assert_contains "H-106: at cap 1 the stopped task restarts" "$out" "restarts through recovery"

# ---- D37-FLOW-8: a check command in the project config is refused ----
printf 'touch %s\n' "$base/ran" > "$base/evil.sh"; chmod +x "$base/evil.sh"
jq --arg e "$base/evil.sh" '.limits.oom_check = {argv: [$e, "{container}"], jq: "true"}' "$proj/.harness/config.json" > "$base/c.json"
cp "$proj/.harness/config.json" "$base/good.json"; mv "$base/c.json" "$proj/.harness/config.json"
rc=0; "$h" run new > /dev/null 2> "$base/err" || rc=$?
assert_eq "D37-FLOW-8: a project config with a check command is refused at start" 78 "$rc"
assert_contains "D37-FLOW-8: the message says to move the command to the user config" "$(cat "$base/err")" "keep only limits.oom_check.label"
assert_exit "D37-FLOW-8: the oom check refuses it too" 78 "$h" resources "$r" oom c-oom3
assert_eq "D37-FLOW-8: no command from the project config ran" no "$([ -e "$base/ran" ] && echo yes || echo no)"
cp "$base/good.json" "$proj/.harness/config.json"
# A label from the project maps to a command in the user config.
jq --arg e "$base/evil.sh" '.limits.oom_check.list.mine = {argv: ["/bin/echo", "true"], jq: "."}' "$user/config.json" > "$base/u.json" && mv "$base/u.json" "$user/config.json"
jq '.limits.oom_check = {label: "mine"}' "$proj/.harness/config.json" > "$base/c.json" && mv "$base/c.json" "$proj/.harness/config.json"
r=$("$h" run new)
"$h" resources "$r" oom c-any > /dev/null
assert_eq "D37-FLOW-8: a project label selects a user-config check" 1 "$(cap "$r")"

# ---- H-108 / D26b: usage history and the recommendation ----
assert_contains "D26b: with no history nothing is recommended" "$(cd "$proj" && "$h" resources recommend)" "no recommendation"
line=$("$h" resources "$r" sample)
assert_eq "H-108: a reading holds CPU, memory and process use" true "$(printf '%s' "$line" | jq 'has("cpu_load") and has("mem_pct") and has("procs") and (.procs | type) == "number"')"
printf '{"ts":"x","run":"r","cpu_load":2,"mem_pct":40,"procs":300,"workers":2}\n' >> "$proj/.harness/usage/history.jsonl"
cp "$proj/.harness/config.json" "$base/before.json"
out=$(cd "$proj" && "$h" resources recommend)
assert_contains "D26b: with history a total is recommended" "$out" "total 4"
assert_eq "D26b: the recommendation never changes the owner's config" "$(cat "$base/before.json")" "$(cat "$proj/.harness/config.json")"
