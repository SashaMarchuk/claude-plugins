#!/usr/bin/env bash
# Regression harness for the /log-time plugin.
# Contract assertions over the plugin source — verifies the universal,
# config-driven, evidence-only, read-only contract survives in the published
# files. Exits 0 on all-pass, 1 on any FAIL. Final line matches the
# master-runner grep: "PASS=<N>  FAIL=<M>".
#
# Usage:  bash plugins/log-time/tests/run.sh
# Deps:   POSIX shell + grep + (jq if present, else python3 for JSON checks).

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$PLUGIN_DIR/../.." && pwd)

SKILL="$PLUGIN_DIR/skills/log-time/SKILL.md"
GUIDE="$PLUGIN_DIR/skills/log-time/references/config-guide.md"
MANIFEST="$PLUGIN_DIR/.claude-plugin/plugin.json"
CMD="$PLUGIN_DIR/commands/log-time.md"
CMD_ONBOARD="$PLUGIN_DIR/commands/onboard.md"
CMD_CONFIG="$PLUGIN_DIR/commands/config.md"
CMD_STATUS="$PLUGIN_DIR/commands/status.md"
MARKET="$REPO_ROOT/.claude-plugin/marketplace.json"
README="$REPO_ROOT/README.md"
RUNALL="$REPO_ROOT/tests/run-all.sh"

PASS=0
FAIL=0
FAIL_MSGS=()

pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); FAIL_MSGS+=("$1: $2"); printf 'FAIL  %s — %s\n' "$1" "$2"; }

json_valid() {
  local f="$1"
  if command -v jq >/dev/null 2>&1; then jq -e . "$f" >/dev/null 2>&1; return $?; fi
  if command -v python3 >/dev/null 2>&1; then python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" >/dev/null 2>&1; return $?; fi
  return 0
}

# Slice the body of a "## <name>" section (header -> next "## " header).
section_body() { awk -v h="^## $1\$" '$0 ~ h {f=1; next} /^## /{f=0} f' "$SKILL"; }

# ============================================================ Files exist

for f in "$SKILL" "$GUIDE" "$MANIFEST" "$CMD" "$CMD_ONBOARD" "$CMD_CONFIG" "$CMD_STATUS"; do
  if [[ -f "$f" ]]; then pass "FILE: exists $(basename "$(dirname "$f")")/$(basename "$f")"
  else fail "FILE: $f" "missing"; fi
done

# ============================================================ Manifest

if json_valid "$MANIFEST"; then pass "MANIFEST: plugin.json is valid JSON"
else fail "MANIFEST: plugin.json" "invalid JSON"; fi

if grep -q '"name": *"log-time"' "$MANIFEST"; then pass "MANIFEST: name == log-time"
else fail "MANIFEST: name" "name is not log-time"; fi

if grep -q '"version": *"0\.' "$MANIFEST"; then pass "MANIFEST: version is 0.x (beta)"
else fail "MANIFEST: version" "expected a 0.x beta version"; fi

if grep -qi '(beta)' "$MANIFEST"; then pass "MANIFEST: description carries (beta) flag"
else fail "MANIFEST: beta flag" "description missing (beta)"; fi

# ============================================================ Skill frontmatter

if grep -q "^user-invocable: false" "$SKILL"; then pass "SKILL: user-invocable: false (matches clickup/g-event/find-call pattern)"
else fail "SKILL: user-invocable" "expected 'user-invocable: false'"; fi

if grep -q "^name: log-time" "$SKILL"; then pass "SKILL: frontmatter name == log-time"
else fail "SKILL: name" "frontmatter name mismatch"; fi

# ============================================================ Config-driven (the universal core)

if grep -q "~/.claude/log-time/config.md" "$SKILL"; then pass "SKILL: reads free-form config at ~/.claude/log-time/config.md"
else fail "SKILL: config path" "no reference to ~/.claude/log-time/config.md"; fi

if grep -qi "free-form" "$SKILL" && grep -qi "config is the contract\|treat it as instructions" "$SKILL"; then
  pass "SKILL: config is free-form markdown treated as binding instructions"
else fail "SKILL: free-form contract" "config not documented as free-form binding instructions"; fi

if grep -qi "onboarding is mandatory" "$SKILL" && grep -qi "Never build a time-log without a config" "$SKILL"; then
  pass "SKILL: forces onboarding when config is missing (no log without config)"
else fail "SKILL: forced onboarding" "missing mandatory-onboarding gate for absent config"; fi

# Guard against the old optional-setup wording regressing back in.
if grep -qi "zero-config" "$SKILL"; then
  fail "SKILL: no zero-config regression" "found stale 'zero-config run' wording — setup must be forced"
else pass "SKILL: no stale 'zero-config run' wording"; fi

if grep -q "Do not HALT" "$SKILL"; then
  pass "SKILL: missing identity.json degrades gracefully (no HALT)"
else fail "SKILL: identity degrade" "no 'Do not HALT' path for missing identity.json"; fi

if grep -q "log-time:onboard" "$SKILL" || grep -q -- "--onboard" "$SKILL"; then
  pass "SKILL: points user to onboarding when config is missing"
else fail "SKILL: onboard hint" "no onboarding hint"; fi

# ============================================================ Evidence-only / no assumed target (load-bearing)

if grep -qi "Never fabricate\|never invent" "$SKILL"; then pass "SKILL: never-fabricate/never-invent rule present"
else fail "SKILL: never-invent" "missing never-fabricate rule"; fi

if grep -qi "No assumed daily target\|Never assume a daily target" "$SKILL"; then
  pass "SKILL: no assumed daily target — evidenced-only without config"
else fail "SKILL: no target default" "missing 'no assumed daily target' rule"; fi

# No hardcoded working-day length anywhere in user-facing prose.
PROSE_FILES=("$SKILL" "$GUIDE" "$CMD" "$CMD_ONBOARD" "$CMD_CONFIG" "$CMD_STATUS" "$MANIFEST")
HOURS_HITS=$(grep -nE "[^0-9.]8h|8 hours|eight hours" "${PROSE_FILES[@]}" 2>/dev/null || true)
if [[ -z "$HOURS_HITS" ]]; then
  pass "PROSE: no hardcoded 8h working-day anywhere in published files"
else
  fail "PROSE: 8h leak" "found hardcoded day length: $(echo "$HOURS_HITS" | head -2 | tr '\n' '|')"
fi

# Steady-target is opt-in: skill asks once, routes through --config.
if grep -qi "steady" "$SKILL" && grep -qi "suggest once\|never silently apply" "$SKILL"; then
  pass "SKILL: steady daily target is opt-in (asked once, never silently applied)"
else fail "SKILL: opt-in target" "missing opt-in steady-target ask + adaptive suggestion"; fi

# Date prefix is suggested, never mandatory.
if grep -qi "suggested, not mandatory" "$SKILL"; then
  pass "SKILL: date prefix is suggested-not-mandatory (config can disable)"
else fail "SKILL: date prefix" "date prefix not documented as optional"; fi

# ============================================================ Identity (read-only consumer)

if grep -q "~/.claude/shared/identity.json" "$SKILL" && grep -qi "read-only — this skill never writes it\|never writes it" "$SKILL"; then
  pass "SKILL: reads shared identity.json as a read-only consumer"
else fail "SKILL: identity" "identity.json not documented as read-only consumer"; fi

# ============================================================ Read-only contract

if grep -qi "Read-only against every source" "$SKILL"; then pass "SKILL: declares read-only against every source"
else fail "SKILL: read-only" "no read-only declaration"; fi

if grep -qi "Never write time logs into any tracker\|never writes to the calendar" "$SKILL"; then
  pass "SKILL: never writes time logs / sources — output is paste-ready text"
else fail "SKILL: no-write" "missing never-write-to-sources rule"; fi

# ============================================================ Tooling constraints

if grep -qi "preference" "$SKILL" && grep -qi "fallback\|fall back" "$SKILL" && grep -qi "never a wall" "$SKILL"; then
  pass "SKILL: sources are preference + fallback (never a wall)"
else fail "SKILL: preference+fallback" "missing preference-with-fallback model"; fi

if grep -qi "do NOT fall back\|never fall back\|surface the error rather than" "$SKILL"; then
  fail "SKILL: no hard-pin regression" "found stale hard-pin 'do not fall back' wording"
else pass "SKILL: no stale hard-pin 'do not fall back' wording"; fi

if grep -qi "Never use WebFetch on Google URLs\|never .*WebFetch.* Google" "$SKILL"; then
  pass "SKILL: WebFetch on Google URLs banned"
else fail "SKILL: webfetch ban" "missing WebFetch-on-Google ban"; fi

if grep -q "FIRST LINE + LAST LINE ONLY" "$SKILL" && grep -qi "Never read full session JSONL" "$SKILL"; then
  pass "SKILL: session JSONL read is first/last line only"
else fail "SKILL: jsonl guard" "missing first/last-line-only session rule"; fi

if grep -qi "sonnet" "$SKILL" && grep -qi "never opus" "$SKILL"; then
  pass "SKILL: gather sub-agents are sonnet (never opus/haiku)"
else fail "SKILL: subagent model" "missing sonnet-only sub-agent rule"; fi

if grep -qi "never print, echo, or log the secret\|Never print credential values" "$SKILL"; then
  pass "SKILL: custom-source credentials never printed"
else fail "SKILL: secrets" "missing credential-hygiene rule for custom sources"; fi

# find-call pairing recommended for call evidence.
if grep -q "find-call" "$SKILL" && grep -qi "recommend" "$SKILL"; then
  pass "SKILL: recommends calendar connection + find-call plugin for call depth"
else fail "SKILL: find-call rec" "missing find-call recommendation"; fi

# ============================================================ Modes

if grep -qi "Invocation modes" "$SKILL" && grep -q "## Mode: --onboard" "$SKILL" \
   && grep -q "## Mode: --config" "$SKILL" && grep -q "## Mode: --status" "$SKILL"; then
  pass "SKILL: dispatch table + --onboard/--config/--status mode sections present"
else fail "SKILL: modes" "missing mode sections or dispatch table"; fi

ONBOARD_SECTION=$(section_body "Mode: --onboard")
if echo "$ONBOARD_SECTION" | grep -qi "skippable" && echo "$ONBOARD_SECTION" | grep -qi "Sources" \
   && echo "$ONBOARD_SECTION" | grep -qi "Targets" && echo "$ONBOARD_SECTION" | grep -qi "Day rules" \
   && echo "$ONBOARD_SECTION" | grep -qi "Output style"; then
  pass "SKILL: onboarding has 4 named steps, each skippable"
else fail "SKILL: onboard steps" "onboarding missing the 4 skippable steps"; fi

if echo "$ONBOARD_SECTION" | grep -qi "explicit confirmation"; then
  pass "SKILL: onboarding writes config only after explicit confirmation"
else fail "SKILL: onboard confirm" "onboarding missing confirm-before-write"; fi

STATUS_SECTION=$(section_body "Mode: --status")
if echo "$STATUS_SECTION" | grep -qi "read-only\|writes nothing"; then
  pass "SKILL: --status declares read-only / writes nothing"
else fail "SKILL: status read-only" "--status not declared read-only"; fi

CONFIG_SECTION=$(section_body "Mode: --config")
if echo "$CONFIG_SECTION" | grep -qi "only write path" && echo "$CONFIG_SECTION" | grep -qi "diff" \
   && echo "$CONFIG_SECTION" | grep -qi "confirmation"; then
  pass "SKILL: --config is a diff-confirmed write path (easy updates)"
else fail "SKILL: config mode" "--config missing diff + confirm + only-write-path"; fi

# ============================================================ Command shims

if grep -q "log-time:log-time" "$CMD" && grep -q '\$ARGUMENTS' "$CMD"; then
  pass "CMD: log-time.md shim invokes log-time:log-time with \$ARGUMENTS"
else fail "CMD: shim" "log-time.md does not invoke skill with \$ARGUMENTS"; fi

if grep -q "log-time:log-time" "$CMD_ONBOARD" && grep -q -- "--onboard" "$CMD_ONBOARD"; then
  pass "CMD: onboard.md shim passes --onboard"
else fail "CMD: onboard shim" "onboard.md does not pass --onboard"; fi

if grep -q "log-time:log-time" "$CMD_CONFIG" && grep -q -- "--config" "$CMD_CONFIG"; then
  pass "CMD: config.md shim passes --config"
else fail "CMD: config shim" "config.md does not pass --config"; fi

if grep -q "log-time:log-time" "$CMD_STATUS" && grep -q -- "--status" "$CMD_STATUS"; then
  pass "CMD: status.md shim passes --status"
else fail "CMD: status shim" "status.md does not pass --status"; fi

# ============================================================ Config guide (mock-only reference)

if grep -qi "illustrative mock data" "$GUIDE" && grep -qi "fictional" "$GUIDE"; then
  pass "GUIDE: declares all examples are illustrative mock data"
else fail "GUIDE: mock disclaimer" "config-guide missing mock-data disclaimer"; fi

if grep -q "## Sources" "$GUIDE" && grep -q "## Targets" "$GUIDE" \
   && grep -q "## Day rules" "$GUIDE" && grep -q "## Output style" "$GUIDE"; then
  pass "GUIDE: covers Sources / Targets / Day rules / Output style sections"
else fail "GUIDE: sections" "config-guide missing a convention section"; fi

if grep -qi "logs evidenced time only" "$GUIDE"; then
  pass "GUIDE: documents evidenced-only default when no target set"
else fail "GUIDE: evidenced-only" "config-guide missing evidenced-only default note"; fi

# ============================================================ NO PERSONAL DATA LEAK (load-bearing generalization gate)
# Scans user-facing PROSE files: skill + reference + all command shims + manifest
# description. The manifest author field ("Sasha Marchuk") is legitimate
# attribution and excluded via pattern choice. Anything matching here is a real
# generalization miss: a personal name, org domain, local path, personal tool,
# real ticket/task id, or real project codename that should have been mock data.
LEAK_PROSE_FILES=("$SKILL" "$GUIDE" "$CMD" "$CMD_ONBOARD" "$CMD_CONFIG" "$CMD_STATUS")
LEAK_HITS=$(grep -rniE "sashko|sasha-marchuk|speedandfunction|/Users/[a-z-]*marchuk|geekbot|GEEK_BOT|U07524|Bangkok|86c9|66248|65150|66250|tom mcroi|cultural indicator|MNB|\[AUT\]|Misha|Feanix|Apostrophe|TDE" "${LEAK_PROSE_FILES[@]}" 2>/dev/null || true)
if [[ -z "$LEAK_HITS" ]]; then
  pass "NO-LEAK: no personal identifiers/settings in published prose"
else
  fail "NO-LEAK: personal data" "found identifiers: $(echo "$LEAK_HITS" | head -3 | tr '\n' '|')"
fi

# ============================================================ Marketplace + repo wiring

if json_valid "$MARKET" && grep -q '"name": *"log-time"' "$MARKET" && grep -q '"./plugins/log-time"' "$MARKET"; then
  pass "MARKET: marketplace.json registers log-time with correct source"
else fail "MARKET: registration" "log-time not registered (or invalid JSON / wrong source)"; fi

if grep -qE "PLUGINS=\(.*log-time.*\)" "$RUNALL"; then
  pass "RUNALL: log-time added to master runner PLUGINS array"
else fail "RUNALL: wiring" "log-time not in tests/run-all.sh PLUGINS"; fi

if grep -q "plugins/log-time" "$README"; then
  pass "README: log-time listed in plugins table"
else fail "README: listing" "log-time not in root README"; fi

# ============================================================ Summary
TOTAL=$((PASS + FAIL))
echo
echo "=============================================================="
echo "/log-time tests:  PASS=$PASS  FAIL=$FAIL  (TOTAL=$TOTAL)"
echo "=============================================================="
if [[ "$FAIL" -gt 0 ]]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
exit 0
