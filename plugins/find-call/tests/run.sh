#!/usr/bin/env bash
# Regression harness for the /find-call plugin.
# Contract assertions over the plugin source — verifies the generalized,
# config-driven, read-only contract survives in the published files.
# Exits 0 on all-pass, 1 on any FAIL. Final line matches the master-runner
# grep: "PASS=<N>  FAIL=<M>".
#
# Usage:  bash plugins/find-call/tests/run.sh
# Deps:   POSIX shell + grep + (jq if present, else python3 for JSON checks).

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd "$PLUGIN_DIR/../.." && pwd)

SKILL="$PLUGIN_DIR/skills/find-call/SKILL.md"
ALIASES="$PLUGIN_DIR/skills/find-call/references/aliases.md"
CONTRACT="$PLUGIN_DIR/skills/find-call/references/identity-contract.md"
SOURCES="$PLUGIN_DIR/skills/find-call/references/sources.md"
MANIFEST="$PLUGIN_DIR/.claude-plugin/plugin.json"
CMD="$PLUGIN_DIR/commands/find-call.md"
CMD_CONFIG="$PLUGIN_DIR/commands/config.md"
CMD_STATUS="$PLUGIN_DIR/commands/status.md"
CONFIG_IO="$PLUGIN_DIR/scripts/config_io.py"
MARKET="$REPO_ROOT/.claude-plugin/marketplace.json"
README="$REPO_ROOT/README.md"
RUNALL="$REPO_ROOT/tests/run-all.sh"

PASS=0
FAIL=0
FAIL_MSGS=()

pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); FAIL_MSGS+=("$1: $2"); printf 'FAIL  %s — %s\n' "$1" "$2"; }

# JSON validity helper (jq preferred, python3 fallback, else skip-as-pass with note)
json_valid() {
  local f="$1"
  if command -v jq >/dev/null 2>&1; then jq -e . "$f" >/dev/null 2>&1; return $?; fi
  if command -v python3 >/dev/null 2>&1; then python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" >/dev/null 2>&1; return $?; fi
  return 0
}

# ============================================================ Files exist

for f in "$SKILL" "$ALIASES" "$CONTRACT" "$SOURCES" "$MANIFEST" "$CMD" "$CMD_CONFIG" "$CMD_STATUS" "$CONFIG_IO"; do
  if [[ -f "$f" ]]; then pass "FILE: exists $(basename "$(dirname "$f")")/$(basename "$f")"
  else fail "FILE: $f" "missing"; fi
done

# ============================================================ Manifest

if json_valid "$MANIFEST"; then pass "MANIFEST: plugin.json is valid JSON"
else fail "MANIFEST: plugin.json" "invalid JSON"; fi

if grep -q '"name": *"find-call"' "$MANIFEST"; then pass "MANIFEST: name == find-call"
else fail "MANIFEST: name" "name is not find-call"; fi

# ============================================================ Skill frontmatter

if grep -q "^user-invocable: false" "$SKILL"; then pass "SKILL: user-invocable: false (matches clickup/g-event pattern)"
else fail "SKILL: user-invocable" "expected 'user-invocable: false'"; fi

if grep -q "^name: find-call" "$SKILL"; then pass "SKILL: frontmatter name == find-call"
else fail "SKILL: name" "frontmatter name mismatch"; fi

# ============================================================ Config-driven (Step 0)

if grep -q "~/.claude/shared/identity.json" "$SKILL"; then pass "SKILL: reads shared identity.json"
else fail "SKILL: identity read" "no reference to ~/.claude/shared/identity.json"; fi

if grep -q "Step 0 — Load identity" "$SKILL"; then pass "SKILL: has Step 0 identity-load preflight"
else fail "SKILL: Step 0" "no Step 0 identity load"; fi

if grep -qi "Do not HALT" "$SKILL"; then pass "SKILL: degrades gracefully when identity.json missing (no HALT)"
else fail "SKILL: graceful degrade" "no 'Do not HALT' degrade path"; fi

if grep -q "onboard identity" "$SKILL"; then pass "SKILL: points user to clickup/g-event onboard for identity setup"
else fail "SKILL: onboard hint" "no onboard-identity hint"; fi

if grep -q "g-event/config.json" "$SKILL" && grep -qi "soft dependency\|optional" "$SKILL"; then
  pass "SKILL: g-event config is a SOFT/optional dependency (defaults.calendar)"
else fail "SKILL: soft dep" "g-event config not documented as optional"; fi

if grep -q "{user.name}" "$SKILL"; then pass "SKILL: uses {user.name} placeholder instead of a hardcoded name"
else fail "SKILL: placeholder" "no {user.name} placeholder"; fi

# ============================================================ Read-only contract

if grep -qi "read-only" "$SKILL"; then pass "SKILL: declares read-only"
else fail "SKILL: read-only" "no read-only declaration"; fi

if grep -q "Never write to .*identity.json" "$SKILL"; then pass "SKILL: explicitly never writes identity.json"
else fail "SKILL: no-write identity" "missing 'never write identity.json' rule"; fi

if grep -qi "Never write time logs\|never write time logs\|Never write to Calendar" "$SKILL"; then
  pass "SKILL: never writes Calendar/Drive/Sembly/time-logs"
else fail "SKILL: no-write assets" "missing no-write asset rule"; fi

# ============================================================ Tooling hard constraints

# Sources are provider-resolved (universal by default, pinnable) — NOT a hardcoded CLI-only ban.
if grep -q "npx @googleworkspace/cli" "$SKILL" \
   && grep -q "sources.calendar" "$SKILL" \
   && grep -qE "auto.*cli.*mcp|cli.*mcp" "$SKILL"; then
  pass "SKILL: calendar/docs are provider-resolved (auto/cli/mcp), not hardcoded CLI-only"
else fail "SKILL: provider model" "source provider model (auto/cli/mcp) not documented in SKILL"; fi

# Preference + fallback (NOT hard pin): config sets order, skill always falls back.
if grep -qi "preference" "$SKILL" && grep -qi "fall back\|fallback" "$SKILL" \
   && grep -qi "get the data\|always falls back\|never a wall\|never a hard\|not a hard" "$SKILL"; then
  pass "SKILL: providers are preference + fallback (config sets order, never forbids fallback)"
else fail "SKILL: preference+fallback" "SKILL does not document preference-with-fallback (looks like hard-pin semantics)"; fi

# Guard against the OLD hard-pin wording regressing back in.
if grep -qi "do NOT fall back\|never fall back\|surface the error rather than" "$SKILL"; then
  fail "SKILL: no hard-pin regression" "found stale hard-pin 'do not fall back' wording in SKILL"
else
  pass "SKILL: no stale hard-pin 'do not fall back' wording"
fi

if grep -qi "preference" "$SOURCES" && grep -qi "fall back\|fallback" "$SOURCES" \
   && grep -qi "get the data\|not a hard\|never a wall" "$SOURCES"; then
  pass "SOURCES: documents preference + fallback model (get the data)"
else fail "SOURCES: preference+fallback" "sources.md missing preference+fallback model"; fi

# WebFetch on Google URLs stays banned under EVERY provider.
if grep -qi "Never .*WebFetch.* Google\|NEVER .*WebFetch.* Google\|WebFetch.* Google URL" "$SKILL"; then
  pass "SKILL: WebFetch on Google URLs banned under any provider"
else fail "SKILL: webfetch ban" "missing 'never WebFetch Google URL' rule"; fi

# Universal-by-default: reads optional find-call/config.json, auto when absent.
if grep -q "~/.claude/find-call/config.json" "$SKILL" && grep -qi "every source is \`auto\`\|universal" "$SKILL"; then
  pass "SKILL: universal-by-default — reads optional find-call/config.json, auto when absent"
else fail "SKILL: source config" "find-call/config.json source resolution not documented in SKILL"; fi

# transcripts: off → notes-only path exists.
if grep -q "transcripts: off\|transcripts\` \?— \`auto\`.*off\|\`off\`" "$SKILL"; then
  pass "SKILL: transcripts can be pinned off (notes-only)"
else fail "SKILL: transcripts off" "no 'transcripts: off' / notes-only pin documented"; fi

if grep -qi "never .*opus" "$SKILL" && grep -qi "sonnet" "$SKILL"; then
  pass "SKILL: transcript sub-agents are sonnet (never opus/haiku)"
else fail "SKILL: subagent model" "missing sonnet-only sub-agent rule"; fi

if grep -qi "Sembly" "$SKILL" && grep -qi "if connected\|if the MCP\|not connected\|not available" "$SKILL"; then
  pass "SKILL: Sembly is optional (degrades if MCP not connected)"
else fail "SKILL: sembly optional" "Sembly not documented as optional"; fi

# ============================================================ Anti-slop

if grep -qi "Cite every claim" "$SKILL"; then pass "SKILL: cite-every-claim anti-slop rule present"
else fail "SKILL: cite rule" "missing cite-everything rule"; fi

if grep -qi "Never invent" "$SKILL"; then pass "SKILL: never-invent rule present"
else fail "SKILL: never-invent" "missing never-invent rule"; fi

# Output answers the question directly (no always-on template / boilerplate slop).
if grep -qi "Answer the user's actual question first" "$SKILL" \
   && grep -qi "omit every section\|drop.* section\|don't pad\|no.*boilerplate" "$SKILL"; then
  pass "SKILL: Step 7 answers the question directly, drops irrelevant sections (anti-slop)"
else fail "SKILL: direct output" "Step 7 still mandates a generic always-on template"; fi

# ============================================================ Command shim

if grep -q "find-call:find-call" "$CMD" && grep -q '\$ARGUMENTS' "$CMD"; then
  pass "CMD: shim invokes find-call:find-call with \$ARGUMENTS"
else fail "CMD: shim" "shim does not invoke find-call:find-call / pass \$ARGUMENTS"; fi

# ============================================================ Identity contract doc

if grep -qi "read-only consumer" "$CONTRACT" && grep -qi "never write" "$CONTRACT"; then
  pass "CONTRACT: documents read-only-consumer stance"
else fail "CONTRACT: stance" "identity-contract.md missing read-only-consumer stance"; fi

# sources.md documents the full provider vocabulary + how the config is set.
if grep -q "auto" "$SOURCES" && grep -q "cli" "$SOURCES" && grep -q "mcp" "$SOURCES" \
   && grep -q "off" "$SOURCES" && grep -q "~/.claude/find-call/config.json" "$SOURCES" \
   && grep -qi "find-call:config\|guarded atomic write\|edit it by hand" "$SOURCES"; then
  pass "SOURCES: documents auto/cli/mcp/off + how the config file is set"
else fail "SOURCES: model" "sources.md missing provider vocabulary or config-set note"; fi

# ============================================================ Aliases stateless

if grep -qi "v1.*DISABLED\|v1 stateless\|ships stateless" "$ALIASES"; then
  pass "ALIASES: v1 documented stateless/disabled"
else fail "ALIASES: stateless" "aliases.md does not document v1 stateless"; fi

# ============================================================ Config / status modes (onboard-like UX)

# Mode dispatch present in SKILL.
if grep -q "## Mode: --status" "$SKILL" && grep -q "## Mode: --config" "$SKILL" \
   && grep -qi "Invocation modes" "$SKILL"; then
  pass "SKILL: --status and --config mode sections + dispatch table present"
else fail "SKILL: modes" "missing --status/--config mode sections or dispatch"; fi

# --status is read-only.
# Slice the body of a "## <name>" section (header -> next "## " header), anchored
# at line start so the dispatch-TABLE row (starts with "|") is never matched.
# Avoids the brittle fixed-window grep -A<N> coupling to document layout.
section_body() { awk -v h="^## $1\$" '$0 ~ h {f=1; next} /^## /{f=0} f' "$SKILL"; }

STATUS_SECTION=$(section_body "Mode: --status")
if echo "$STATUS_SECTION" | grep -qi "read-only\|Writes nothing"; then
  pass "SKILL: --status declares read-only / writes nothing"
else fail "SKILL: status read-only" "--status mode not declared read-only"; fi

# --config is the single guarded write path via the helper script.
CONFIG_SECTION=$(section_body "Mode: --config")
if echo "$CONFIG_SECTION" | grep -q "config_io.py --set" \
   && echo "$CONFIG_SECTION" | grep -qi "only write"; then
  pass "SKILL: --config is the single write path (config_io.py --set)"
else fail "SKILL: config write" "--config mode does not route writes through config_io.py"; fi

# Command shims pass the right flags.
if grep -q "find-call:find-call" "$CMD_CONFIG" && grep -q -- "--config" "$CMD_CONFIG"; then
  pass "CMD: config.md shim passes --config"
else fail "CMD: config shim" "config.md does not pass --config to find-call:find-call"; fi

if grep -q "find-call:find-call" "$CMD_STATUS" && grep -q -- "--status" "$CMD_STATUS"; then
  pass "CMD: status.md shim passes --status"
else fail "CMD: status shim" "status.md does not pass --status to find-call:find-call"; fi

# config_io.py: valid Python + guarded atomic write + value validation.
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import ast,sys; ast.parse(open('$CONFIG_IO').read())" 2>/dev/null; then
    pass "SCRIPT: config_io.py is syntactically valid Python"
  else fail "SCRIPT: config_io syntax" "ast.parse failed"; fi
fi

if grep -q "fcntl.flock" "$CONFIG_IO" && grep -q "os.replace" "$CONFIG_IO" \
   && grep -q "tempfile" "$CONFIG_IO" && grep -q "os.fsync" "$CONFIG_IO"; then
  pass "SCRIPT: config_io.py uses guarded atomic write (flock + tmp + fsync + os.replace)"
else fail "SCRIPT: atomic write" "config_io.py missing flock/tmp/fsync/os.replace discipline"; fi

if grep -q "CALENDAR_VALUES" "$CONFIG_IO" && grep -q "DOCS_VALUES" "$CONFIG_IO" \
   && grep -q "KNOWN_TRANSCRIPT_PROVIDERS" "$CONFIG_IO"; then
  pass "SCRIPT: config_io.py validates calendar/docs/transcripts provider values"
else fail "SCRIPT: validation" "config_io.py missing value validation sets"; fi

# Functional: --show on an empty HOME reports no config; --set rejects bad values
# and writes good ones. Uses a throwaway HOME so the user's real config is never touched.
if command -v python3 >/dev/null 2>&1; then
  TMP_HOME=$(mktemp -d)
  CFG="$TMP_HOME/.claude/find-call/config.json"
  set +e
  SHOW_OUT=$(HOME="$TMP_HOME" python3 "$CONFIG_IO" --show 2>/dev/null); show_rc=$?
  HOME="$TMP_HOME" python3 "$CONFIG_IO" --set calendar=bogus  >/dev/null 2>&1; cal_bad_rc=$?
  HOME="$TMP_HOME" python3 "$CONFIG_IO" --set docs=bogus      >/dev/null 2>&1; docs_bad_rc=$?
  HOME="$TMP_HOME" python3 "$CONFIG_IO" --set transcripts=    >/dev/null 2>&1; tr_bad_rc=$?
  HOME="$TMP_HOME" python3 "$CONFIG_IO" --set calendar=cli transcripts=off >/dev/null 2>&1; good_rc=$?
  GOOD_JSON=$(cat "$CFG" 2>/dev/null)  # snapshot before later steps mutate the file
  POP_OUT=$(HOME="$TMP_HOME" python3 "$CONFIG_IO" --show 2>/dev/null)
  # wrong-shape JSON (a hand-edit gone wrong) must be quarantined, not crash the writer
  mkdir -p "$(dirname "$CFG")"; printf '[1,2,3]' > "$CFG"
  HOME="$TMP_HOME" python3 "$CONFIG_IO" --set docs=off >/dev/null 2>&1; wrongshape_rc=$?
  ls "$(dirname "$CFG")"/config.json.corrupt-* >/dev/null 2>&1; quarantined_rc=$?
  set -e
  if [[ "$show_rc" -eq 0 ]] && echo "$SHOW_OUT" | grep -q '"exists": false'; then
    pass "SCRIPT(func): --show on empty HOME reports exists:false, exit 0"
  else fail "SCRIPT(func): --show empty" "rc=$show_rc out=$SHOW_OUT"; fi
  if [[ "$cal_bad_rc" -ne 0 && "$docs_bad_rc" -ne 0 && "$tr_bad_rc" -ne 0 ]]; then
    pass "SCRIPT(func): --set rejects invalid calendar/docs/transcripts values (non-zero exit)"
  else fail "SCRIPT(func): bad value" "a bogus value was accepted (cal=$cal_bad_rc docs=$docs_bad_rc tr=$tr_bad_rc)"; fi
  if [[ "$good_rc" -eq 0 ]] \
     && echo "$GOOD_JSON" | grep -q '"calendar": "cli"' && echo "$GOOD_JSON" | grep -q '"transcripts": "off"'; then
    pass "SCRIPT(func): --set writes valid prefs (calendar AND transcripts) atomically"
  else fail "SCRIPT(func): good write" "config not written with both keys (rc=$good_rc)"; fi
  if echo "$POP_OUT" | grep -q '"exists": true' && echo "$POP_OUT" | grep -q '"calendar": "cli"'; then
    pass "SCRIPT(func): --show on populated HOME reports exists:true + persisted value"
  else fail "SCRIPT(func): --show populated" "out=$POP_OUT"; fi
  if [[ "$wrongshape_rc" -eq 0 && "$quarantined_rc" -eq 0 ]] && grep -q '"docs": "off"' "$CFG"; then
    pass "SCRIPT(func): wrong-shape JSON is quarantined + rewritten, no crash"
  else fail "SCRIPT(func): wrong-shape" "rc=$wrongshape_rc quarantined_rc=$quarantined_rc"; fi
  rm -rf "$TMP_HOME"
fi

# ============================================================ NO PERSONAL DATA LEAK (load-bearing generalization gate)
# Scans the user-facing PROSE files: skill + references + all three command
# shims. The manifest author field ("Sasha Marchuk") is legitimate attribution
# and is NOT scanned; this scanner's own pattern string (in run.sh) is excluded
# too. Anything matching here is a real generalization miss: a personal first
# name, local home path, org email-domain, or real attendee/project codename
# (MNB, [AUT] event-tag) that should have been genericized.
LEAK_PROSE_FILES=("$SKILL" "$ALIASES" "$CONTRACT" "$SOURCES" "$CMD" "$CMD_CONFIG" "$CMD_STATUS")
LEAK_HITS=$(grep -rniE "sashko|sasha-marchuk|speedandfunction|/Users/[a-z-]*marchuk|tom mcroi|cultural indicator|MNB|\[AUT\]" "${LEAK_PROSE_FILES[@]}" 2>/dev/null || true)
if [[ -z "$LEAK_HITS" ]]; then
  pass "NO-LEAK: no personal identifiers (name/email-domain/local-path/real-attendees) in skill prose"
else
  fail "NO-LEAK: personal data" "found identifiers: $(echo "$LEAK_HITS" | head -3 | tr '\n' '|')"
fi

# ============================================================ Marketplace + repo wiring

if json_valid "$MARKET" && grep -q '"name": *"find-call"' "$MARKET" && grep -q '"./plugins/find-call"' "$MARKET"; then
  pass "MARKET: marketplace.json registers find-call with correct source"
else fail "MARKET: registration" "find-call not registered (or invalid JSON / wrong source)"; fi

if grep -qE "PLUGINS=\(.*find-call.*\)" "$RUNALL"; then
  pass "RUNALL: find-call added to master runner PLUGINS array"
else fail "RUNALL: wiring" "find-call not in tests/run-all.sh PLUGINS"; fi

if grep -q "plugins/find-call" "$README" && grep -qi "find-call" "$README"; then
  pass "README: find-call listed in plugins table"
else fail "README: listing" "find-call not in root README"; fi

# ============================================================ Summary
TOTAL=$((PASS + FAIL))
echo
echo "=============================================================="
echo "/find-call tests:  PASS=$PASS  FAIL=$FAIL  (TOTAL=$TOTAL)"
echo "=============================================================="
if [[ "$FAIL" -gt 0 ]]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
exit 0
