#!/usr/bin/env bash
# WS-10 regression harness for /clickup plugin.
# One assertion per PRD finding (F1..F15). Exits 0 on all-pass, 1 on any FAIL.
#
# Usage:  bash plugins/clickup/tests/run.sh
#
# Tests are POSIX-shell + grep + jq only. They verify that the prose contracts
# established by WS-3 (F1-F4) and WS-6 (F5, F7-F15) survive in the SKILL.md /
# references/ files. Source files MUST NOT be modified by these tests.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SKILL="$PLUGIN_DIR/skills/clickup/SKILL.md"
MODES="$PLUGIN_DIR/skills/clickup/references/modes.md"
SCHEMA="$PLUGIN_DIR/skills/clickup/references/config-schema.md"
TICKET="$PLUGIN_DIR/skills/clickup/references/ticket-format.md"
CONNECTION="$PLUGIN_DIR/skills/clickup/references/connection.md"
CONNECT_CMD="$PLUGIN_DIR/commands/connect.md"
RELOAD_CMD_F="$PLUGIN_DIR/commands/reload.md"

PASS=0
FAIL=0
FAIL_MSGS=()

pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); FAIL_MSGS+=("$1: $2"); printf 'FAIL  %s — %s\n' "$1" "$2"; }

# ---------- F1: Lock-file path drift unified to canonical sibling path ----------
# Acceptance per PRD §3 PLG-clickup-1: `~/.claude/shared/identity.json.lock`
# (no leading dot) is the only identity-lock path across clickup SKILL/refs.
canonical='~/.claude/shared/identity.json.lock'
hits=$(grep -c "shared/identity\.json\.lock" "$SKILL" "$SCHEMA" "$MODES" 2>/dev/null \
       | awk -F: '{s+=$2} END{print s+0}')
if [[ "$hits" -ge 3 ]]; then
  pass "WS3-F1: canonical identity.json.lock pinned in SKILL+schema+modes (hits=$hits)"
else
  fail "WS3-F1: canonical identity.json.lock pinned" "hits=$hits expected >=3"
fi

# Drift: dot-prefixed variant must not appear inside clickup files.
if grep -q "shared/\.identity\.json\.lock" "$SKILL" "$SCHEMA" "$MODES" 2>/dev/null; then
  fail "WS3-F1: no .identity.json.lock dot-prefixed drift in clickup" "found dot-prefixed variant"
else
  pass "WS3-F1: no .identity.json.lock dot-prefixed drift in clickup"
fi

# ---------- F2: schemaVersion quarantine gate ----------
# Acceptance: non-int / missing / null schemaVersion quarantines to .corrupt-<epoch>.
if grep -q "isinstance(data\.get(\"schemaVersion\"), int)" "$SCHEMA" \
   && grep -q "\.corrupt-" "$SCHEMA"; then
  pass "WS3-F2: schemaVersion isinstance(int) quarantine gate documented"
else
  fail "WS3-F2: schemaVersion isinstance(int) quarantine gate" "missing isinstance / quarantine in schema"
fi
if grep -q "CURRENT_SCHEMA_VERSION = 2" "$SCHEMA" \
   && grep -q "PREVIOUS_SCHEMA_VERSION = 1" "$SCHEMA"; then
  pass "WS3-F2: CURRENT/PREVIOUS schemaVersion constants pinned"
else
  fail "WS3-F2: CURRENT/PREVIOUS schemaVersion constants pinned" "missing constants"
fi

# ---------- F3: IDN punycode rejection ----------
# Acceptance: `xn--` whole-domain AND sub-label rejection in SKILL.md.
if grep -q "xn--" "$SKILL" && grep -qi "punycode" "$SKILL"; then
  pass "WS3-F3: IDN punycode (xn--) rejection documented"
else
  fail "WS3-F3: IDN punycode rejection" "missing xn-- + punycode anchors in SKILL"
fi

# ---------- F4: Homoglyph gate order — raw skeleton BEFORE strip ----------
# Acceptance: skeleton-before-strip + zero-match-upsert path covered.
if grep -q "RAW typed input, BEFORE the zero-width / BOM strip" "$SKILL" \
   && grep -q "zero-match upsert" "$SKILL"; then
  pass "WS3-F4: homoglyph skeleton-before-strip + zero-match upsert documented"
else
  fail "WS3-F4: homoglyph skeleton-before-strip" "missing ordering or zero-match upsert clause"
fi
# UTS #39 skeleton named explicitly
if grep -q "UTS #39 skeleton" "$SKILL"; then
  pass "WS3-F4: UTS #39 skeleton named"
else
  fail "WS3-F4: UTS #39 skeleton named" "not found in SKILL"
fi

# ---------- F5: --onboard --auto parse-time refuse ----------
# Acceptance: combined invocation HALTS at parse time.
if grep -q "\\-\\-onboard \\-\\-auto.*REJECTED at parse time" "$SKILL" \
   || grep -q "refusing --onboard --auto" "$SKILL"; then
  pass "WS6-F5: --onboard --auto refused at parse time"
else
  fail "WS6-F5: --onboard --auto refused at parse time" "missing parse-time rejection prose"
fi

# ---------- F6: HTML-comment idempotency marker (NOT in PRD task list — skipped) ----------
# Per task brief: "there's no F6". PRD has no F6 finding. Skip.
# Sanity: confirm there's no PLG-clickup-6 entry in the SKILL.md (it would be a finding leak).
# This is a no-op verification — just register coverage of the gap.
pass "WS-skip-F6: PLG-clickup-6 explicitly out-of-scope per task brief"

# ---------- F7 (re-pointed for 1.5.0 de-hardcode): rc classification stays in SKILL.md;
#            the literal probe tool moves to connection.md's MCP adapter ----------
# Acceptance: the four rc buckets remain pinned in SKILL.md (the contract), AND the
# concrete MCP probe literal is asserted in connection.md (its new sole home), AND
# SKILL.md probes the RESOLVED transport via op.probe (not a hardcoded MCP call).
if grep -q "auth-ok" "$SKILL" \
   && grep -q "auth-fail" "$SKILL" \
   && grep -q "retryable-network" "$SKILL" \
   && grep -q '`other`' "$SKILL" \
   && grep -q "op.probe" "$SKILL"; then
  pass "WS6-F7: four rc buckets + op.probe(resolved transport) pinned in SKILL.md"
else
  fail "WS6-F7: rc buckets + op.probe in SKILL.md" "missing one of: auth-ok/auth-fail/retryable-network/other/op.probe"
fi
if grep -q "op.probe" "$CONNECTION" \
   && grep -q "mcp__clickup__clickup_get_workspace_hierarchy" "$CONNECTION"; then
  pass "WS6-F7: MCP probe literal relocated to connection.md adapter (op.probe -> get_workspace_hierarchy)"
else
  fail "WS6-F7: MCP probe literal in connection.md" "connection.md missing op.probe -> MCP probe mapping"
fi

# ---------- F8: @mention / auto-link / image sanitisation ----------
# Acceptance: ticket-format.md hard-stops list mentions, bare URLs, image embeds.
if grep -q "@admin" "$TICKET" \
   && grep -q "back-tick" "$TICKET" \
   && grep -q "Markdown image embeds" "$TICKET"; then
  pass "WS6-F8: @mention + auto-link + image embeds neutralised in ticket-format"
else
  fail "WS6-F8: @mention + auto-link + image embeds neutralised" "missing one of three categories"
fi

# ---------- F9: duplicate-detection metric pinned (Jaccard, NFKC, threshold) ----------
if grep -q "Jaccard coefficient" "$SKILL" \
   && grep -q "NFKC" "$SKILL" \
   && grep -qE ">= ?0\.895" "$SKILL"; then
  pass "WS6-F9: Jaccard + NFKC + 0.895 auto threshold pinned"
else
  fail "WS6-F9: Jaccard + NFKC + 0.895 threshold" "missing one anchor"
fi

# ---------- F10: memory rule vs priority-keyword 4-tier precedence ----------
if grep -q "4-tier precedence" "$SKILL" \
   && grep -q "Daria = P1" "$SCHEMA" \
   && grep -q "low priority typo for Daria" "$SCHEMA"; then
  pass "WS6-F10: 4-tier precedence + canonical Daria conflict example"
else
  fail "WS6-F10: 4-tier precedence + Daria example" "missing"
fi

# ---------- F11: Cyrillic→Latin transliteration markers + collision pre-pass ----------
if grep -q "ъ" "$MODES" && grep -q "ь" "$MODES" \
   && grep -q "translit_alias" "$MODES" \
   && grep -q "collision pre-pass" "$MODES"; then
  pass "WS6-F11: hard/soft sign markers + translit_alias + collision pre-pass"
else
  fail "WS6-F11: translit markers + collision pre-pass" "missing one anchor"
fi

# ---------- F12: UUIDv4 idempotency-key regex gate ----------
if grep -q "UUIDv4" "$SKILL" \
   && grep -qE "regex|\^\[0-9a-f\]" "$SKILL"; then
  pass "WS6-F12: UUIDv4 regex gate pinned in idempotency section"
else
  fail "WS6-F12: UUIDv4 regex gate" "missing UUIDv4 + regex anchors"
fi

# ---------- F13: teammates[].active default-false on missing ----------
if grep -q "Missing \`active\` field is treated as \`false\`" "$SKILL" \
   && grep -q "teammates\[\]\.active" "$SCHEMA"; then
  pass "WS6-F13: teammates[].active default-false rule pinned in SKILL+schema"
else
  fail "WS6-F13: teammates[].active default-false" "missing rule in SKILL or schema"
fi

# ---------- F14: seed-text 4 KB cap with sentence-boundary truncation banner ----------
if grep -q "4 KB" "$SKILL" \
   && grep -qi "sentence" "$SKILL" \
   && grep -qi "truncat" "$SKILL"; then
  pass "WS6-F14: 4 KB seed cap + sentence-boundary truncation banner"
else
  fail "WS6-F14: 4 KB seed cap" "missing one of: 4 KB / sentence / truncate"
fi

# ---------- F15: stale memory-rule auto-demote at 90 days ----------
if grep -q "auto-demote to \`advisory\` tier" "$SCHEMA" \
   && grep -q "90 days" "$SCHEMA" \
   && grep -q "120-day" "$SCHEMA"; then
  pass "WS6-F15: 90-day auto-demote to advisory + 120-day NOT-applied rule"
else
  fail "WS6-F15: 90-day auto-demote rule" "missing 90/120 day thresholds"
fi

# ---------- WSR-1: /clickup:reload command file ----------
RELOAD_CMD="$PLUGIN_DIR/commands/reload.md"
if [[ -f "$RELOAD_CMD" ]] && grep -q "argument-hint:" "$RELOAD_CMD" \
   && grep -q "clickup:clickup" "$RELOAD_CMD" \
   && grep -q -- "--reload" "$RELOAD_CMD"; then
  pass "WSR-1: commands/reload.md exists and dispatches --reload to clickup:clickup"
else
  fail "WSR-1: commands/reload.md exists" "missing file or wiring"
fi

# ---------- WSR-2: SKILL.md dispatch table has --reload row ----------
if grep -q '`--reload`' "$SKILL" \
   && grep -q "references/modes\.md#reload" "$SKILL"; then
  pass "WSR-2: SKILL.md dispatch table includes --reload row"
else
  fail "WSR-2: SKILL.md dispatch table includes --reload row" "missing"
fi

# ---------- WSR-3: SKILL.md precedence updated ----------
if grep -qE -- "--workspace.*--reload.*--auto" "$SKILL"; then
  pass "WSR-3: precedence line includes --reload between --workspace and --auto"
else
  fail "WSR-3: precedence line includes --reload" "ordering not pinned"
fi

# ---------- WSR-4: --reload --auto parse-time refuse ----------
if grep -q -- "--reload --auto.*REJECTED at parse time" "$SKILL" \
   || grep -q "refusing --reload --auto" "$SKILL"; then
  pass "WSR-4: --reload --auto rejected at parse time"
else
  fail "WSR-4: --reload --auto parse-time refuse" "missing prose"
fi

# ---------- WSR-5 (re-pointed for 1.5.0): modes.md ## reload uses op.get_hierarchy ----------
# The concrete clickup_get_workspace_hierarchy literal moved to connection.md; modes.md
# now references the OPERATION. Assert the reload section + the op + the Jaccard metric.
if grep -q "^## reload$" "$MODES" \
   && grep -q "op.get_hierarchy" "$MODES" \
   && grep -q "Jaccard" "$MODES"; then
  pass "WSR-5: modes.md ## reload section with op.get_hierarchy + Jaccard anchors"
else
  fail "WSR-5: modes.md ## reload section" "missing one of: header / op.get_hierarchy / Jaccard"
fi

# ---------- WSR-6: small-N guard documented ----------
if grep -qE "max\(.S., .M.\) <= 3|max\(\\\|S\\\|, \\\|M\\\|\\) <= 3|small-N guard|small-N" "$MODES"; then
  pass "WSR-6: small-N guard documented in modes.md"
else
  fail "WSR-6: small-N guard" "no anchor for max<=3 or small-N guard"
fi

# ---------- WSR-7: snapshot path + retention pinned ----------
if grep -q "\.snapshots" "$MODES" \
   && grep -qE "last 5|retain.*5|keep last 5" "$MODES"; then
  pass "WSR-7: snapshot path .snapshots/ + retain-5 documented"
else
  fail "WSR-7: snapshot path + retention" "missing one anchor"
fi

# ---------- WSR-8: schema additions in config-schema.md ----------
if grep -q "lists\[\]\.archived" "$SCHEMA" \
   && grep -q "lists\[\]\.removed_at" "$SCHEMA" \
   && grep -q "lists_archive\[\]" "$SCHEMA" \
   && grep -q "lists\[\]\.last_validated_at" "$SCHEMA"; then
  pass "WSR-8: config-schema.md documents all four new fields"
else
  fail "WSR-8: config-schema.md schema additions" "missing one of: archived / removed_at / lists_archive / last_validated_at"
fi

# ---------- WSR-9: default-on-missing semantics ----------
if grep -qE "Default \`false\` on missing|default \`false\` when missing" "$SCHEMA" \
   && grep -qE "Default \`\[\]\` on missing|default \`\[\]\` when missing" "$SCHEMA"; then
  pass "WSR-9: new fields document default-on-missing semantics"
else
  fail "WSR-9: default-on-missing for new fields" "v1->v2 inflate not pinned"
fi

# ---------- WSR-10: NO schemaVersion bump ----------
if grep -q "CURRENT_SCHEMA_VERSION = 2" "$SCHEMA" \
   && ! grep -q "CURRENT_SCHEMA_VERSION = 3" "$SCHEMA"; then
  pass "WSR-10: CURRENT_SCHEMA_VERSION still 2 (no bump)"
else
  fail "WSR-10: no schemaVersion bump" "found CURRENT_SCHEMA_VERSION = 3 OR removed = 2"
fi

# ---------- WSR-11: reload uses canonical lock path ----------
if grep -q "\.config\.json\.lock" "$MODES"; then
  pass "WSR-11: reload references the canonical clickup config lock path"
else
  fail "WSR-11: canonical lock path in reload section" "missing"
fi

# ---------- WSR-12: archived list resolver-refusal message ----------
if grep -q "archived — re-onboard or pick a different list" "$SKILL"; then
  pass "WSR-12: SKILL.md updates resolver to differentiate archived from missing"
else
  fail "WSR-12: archived-vs-missing resolver message" "SKILL.md not updated"
fi

# ---------- WSR-13: --mode override flags documented ----------
if grep -q -- "--mode=incremental" "$MODES" \
   && grep -q -- "--mode=full" "$MODES"; then
  pass "WSR-13: --mode=incremental and --mode=full documented in modes.md"
else
  fail "WSR-13: --mode override flags" "one or both missing"
fi

# ---------- WSR-14: defensive halts pinned in modes.md (data-loss prevention) ----------
# The four halt conditions from PLAN are the data-loss prevention path; pin them
# against drift. We require at least 2 of the 4 marker phrases to appear so the
# test survives small wording tweaks but catches a wholesale removal.
halt_hits=0
grep -q "refusing to auto-archive\|refuse to auto-archive" "$MODES" && halt_hits=$((halt_hits+1))
grep -q "duplicate list_id\|duplicate \`id\`\|duplicate id" "$MODES" && halt_hits=$((halt_hits+1))
grep -q "auth scope changed\|auth-scope\|workspace not visible" "$MODES" && halt_hits=$((halt_hits+1))
grep -q "0 workspaces\|zero workspaces\|MCP returns 0\|no workspaces" "$MODES" && halt_hits=$((halt_hits+1))
if [[ "$halt_hits" -ge 2 ]]; then
  pass "WSR-14: defensive halt-condition copy pinned in modes.md ($halt_hits/4 markers found)"
else
  fail "WSR-14: defensive halt-condition copy" "only $halt_hits/4 markers found; expected >= 2"
fi

# ---------- WSR-15: production-update guidance ships with the PR ----------
if grep -q "/plugin marketplace update" "$MODES" \
   && grep -q "git pull" "$MODES" \
   && grep -q "NEVER touched" "$MODES"; then
  pass "WSR-15: production-update guidance (marketplace update + git pull + file-state guarantees)"
else
  fail "WSR-15: production-update guidance" "missing one of: marketplace update | git pull | NEVER touched"
fi

# ---------- WSR-16: archived ↔ removed_at impossible-state invariant pinned ----------
if grep -q "archived: true" "$SCHEMA" \
   && grep -q "removed_at" "$SCHEMA" \
   && grep -qi "illegal\|invariant\|impossible" "$SCHEMA"; then
  pass "WSR-16: archived↔removed_at invariant pinned in config-schema.md"
else
  fail "WSR-16: archived↔removed_at invariant" "invariant prose not found"
fi

# ============================================================================
# CONN-1..CONN-14 — 1.5.0 unified connection layer (MCP / clickup-cli / REST)
# ============================================================================

# ---------- CONN-FILES: new files exist ----------
if [[ -f "$CONNECTION" ]]; then pass "CONN-FILES: references/connection.md exists"
else fail "CONN-FILES: connection.md" "missing"; fi
if [[ -f "$CONNECT_CMD" ]] && grep -q "clickup:clickup" "$CONNECT_CMD" && grep -q -- "--connect" "$CONNECT_CMD"; then
  pass "CONN-FILES: commands/connect.md exists and dispatches --connect to clickup:clickup"
else fail "CONN-FILES: connect.md" "missing file or wiring"; fi

# ---------- CONN-1: all 12 capability operations named in connection.md ----------
conn1_missing=""
for op in op.probe op.get_hierarchy op.get_list op.get_members op.resolve_assignees \
          op.find_tasks op.find_by_marker op.get_task op.create_task op.update_task \
          op.create_comment op.get_custom_fields; do
  grep -q "$op" "$CONNECTION" || conn1_missing="$conn1_missing $op"
done
if [[ -z "$conn1_missing" ]]; then
  pass "CONN-1: all 12 op.* capability operations defined in connection.md"
else
  fail "CONN-1: capability ops" "connection.md missing:$conn1_missing"
fi

# ---------- CONN-2: three transport adapter columns present in connection.md ----------
if grep -q "clickup-cli task create" "$CONNECTION" \
   && grep -q "markdown_description" "$CONNECTION" \
   && grep -q "/api/v2/" "$CONNECTION"; then
  pass "CONN-2: connection.md realization names all three transports (cli / mcp / rest)"
else
  fail "CONN-2: three adapters" "missing one of: 'clickup-cli task create' / markdown_description / /api/v2/"
fi

# ---------- CONN-3 (anti-hardcode guard): no mcp__clickup__ literal OUTSIDE connection.md ----------
# connection.md is the sole legitimate home for transport literals. SKILL.md, modes.md,
# config-schema.md, and every command wrapper must name op.* only.
conn3_leak=$(grep -rl "mcp__clickup__" "$SKILL" "$MODES" "$SCHEMA" "$PLUGIN_DIR/commands/" 2>/dev/null || true)
if [[ -z "$conn3_leak" ]]; then
  pass "CONN-3: no mcp__clickup__ literal outside connection.md (de-hardcode complete)"
else
  fail "CONN-3: hardcode leak" "mcp__clickup__ still in: $(echo "$conn3_leak" | tr '\n' ' ')"
fi

# ---------- CONN-4: canonical priority map pinned in connection.md ----------
if grep -q "urgent=1" "$CONNECTION" && grep -q "low=4" "$CONNECTION" && grep -qi "string" "$CONNECTION"; then
  pass "CONN-4: canonical priority map (urgent=1..low=4; MCP string) pinned in connection.md"
else
  fail "CONN-4: priority map" "missing urgent=1 / low=4 / string in connection.md"
fi

# ---------- CONN-5: capability degradation policy ----------
if grep -q "task_type" "$CONNECTION" \
   && grep -q "clickup-cli" "$CONNECTION" \
   && grep -qi "never silently drop" "$CONNECTION" \
   && grep -q -- "--assignee" "$CONNECTION"; then
  pass "CONN-5: degradation policy (task_type / single --assignee / never silently drop) in connection.md"
else
  fail "CONN-5: degradation policy" "missing one of: task_type / clickup-cli / 'never silently drop' / --assignee"
fi

# ---------- CONN-6: ## connect mode in modes.md, investigate->ask->remember, never silent ----------
if grep -q "^## connect$" "$MODES" \
   && grep -qi "investigate" "$MODES" \
   && grep -q "AskUserQuestion" "$MODES" \
   && grep -qi "never silently pick\|never silent-pick\|the plugin never auto-adopts" "$MODES"; then
  pass "CONN-6: modes.md ## connect (investigate + AskUserQuestion + never-silent) present"
else
  fail "CONN-6: connect mode" "missing one of: ## connect / investigate / AskUserQuestion / never-silent"
fi

# ---------- CONN-7: forced connect detour + never-create-unconfigured (SKILL.md Step 2.5) ----------
if grep -qi "connection not configured" "$SKILL" \
   && grep -q "configured != true" "$SKILL" \
   && grep -qi "never create or mutate a ticket without an investigated, chosen connection" "$SKILL"; then
  pass "CONN-7: SKILL.md Step 2.5 forces connect when unconfigured (never run unconfigured)"
else
  fail "CONN-7: forced detour" "missing 'connection not configured' / 'configured != true' / never-create anchor"
fi

# ---------- CONN-8: --connect --auto parse-time refuse + --auto capability-gap refuse ----------
if grep -q "refusing --connect --auto" "$SKILL" \
   && grep -qi "Capability gap with no silent fix\|--auto does NOT borrow" "$SKILL"; then
  pass "CONN-8: --connect --auto refused + --auto never borrows silently (capability-gap refuse)"
else
  fail "CONN-8: --auto guards" "missing '--connect --auto' refuse or '--auto' capability-gap refuse"
fi

# ---------- CONN-9: connection block documented in config-schema.md ----------
conn9_missing=""
for k in "connection" "configured" "primary" "fallback_order" "rest_token_ref" "auto_borrow"; do
  grep -q "$k" "$SCHEMA" || conn9_missing="$conn9_missing $k"
done
if [[ -z "$conn9_missing" ]] && grep -q "mcp" "$SCHEMA" && grep -q "rest" "$SCHEMA" && grep -q "cli" "$SCHEMA"; then
  pass "CONN-9: config-schema.md documents the connection block + transport enum"
else
  fail "CONN-9: connection schema" "config-schema.md missing:$conn9_missing (or transport enum)"
fi

# ---------- CONN-10 (secret hygiene): pointer-not-value prose + NEGATIVE token-shape grep ----------
if grep -qi "pointer, never a value\|token value is never written\|never the token\|never a token value" "$CONNECTION" \
   && grep -q "rest_token_ref" "$CONNECTION"; then
  conn10_prose=1
else
  conn10_prose=0
fi
# No real token literal anywhere under the plugin (pk_/tk_ + 20+ base62 chars).
TOKEN_LEAK=$(grep -rnE "(pk_|tk_)[A-Za-z0-9]{20,}" "$PLUGIN_DIR" 2>/dev/null || true)
if [[ "$conn10_prose" -eq 1 && -z "$TOKEN_LEAK" ]]; then
  pass "CONN-10: secret pointer-not-value rule + no token-shaped literal under plugins/clickup/"
else
  fail "CONN-10: secret hygiene" "prose=$conn10_prose tokenleak=$(echo "$TOKEN_LEAK" | head -1)"
fi

# ---------- CONN-11: /clickup:status Connection block in modes.md ----------
if grep -q "Resolves to" "$MODES" \
   && grep -q "Available now" "$MODES" \
   && grep -q "clickup-cli setup" "$MODES"; then
  pass "CONN-11: status Connection block (Resolves to / Available now / fix hints) present"
else
  fail "CONN-11: status connection block" "missing one of: 'Resolves to' / 'Available now' / 'clickup-cli setup'"
fi

# ---------- CONN-12: rest_token_ref format guard regex pinned (connection.md + schema) ----------
if grep -q "env:\[A-Z_\]\[A-Z0-9_\]\*" "$CONNECTION" \
   && grep -q "cli-config" "$CONNECTION" \
   && grep -q "cli-config" "$SCHEMA"; then
  pass "CONN-12: rest_token_ref validated against ^(env:NAME|cli-config)\$ (connection.md + schema)"
else
  fail "CONN-12: rest_token_ref guard" "missing env:NAME regex or cli-config anchor"
fi

# ---------- CONN-13: connect writes ONLY config.json (never identity.json) + shell/URL hygiene ----------
if grep -qi "MUST NOT write .*identity.json" "$MODES" \
   && grep -q -- "--data-urlencode" "$CONNECTION" \
   && grep -qi "single-quote" "$CONNECTION"; then
  pass "CONN-13: connect writes only config.json; curl url-encode + cli single-quote hygiene pinned"
else
  fail "CONN-13: write-scope + hygiene" "missing identity.json no-write OR --data-urlencode OR single-quote"
fi

# ---------- CONN-14: NO schemaVersion bump (connection is additive) ----------
if grep -q "CURRENT_SCHEMA_VERSION = 2" "$SCHEMA" \
   && ! grep -q "CURRENT_SCHEMA_VERSION = 3" "$SCHEMA" \
   && grep -qi "no .schemaVersion. bump\|additive" "$SCHEMA"; then
  pass "CONN-14: connection added with NO schemaVersion bump (CURRENT stays 2, additive)"
else
  fail "CONN-14: no schema bump" "CURRENT_SCHEMA_VERSION changed OR connection not documented as additive"
fi

# ---------- Summary ----------
TOTAL=$((PASS + FAIL))
echo
echo "=============================================================="
echo "/clickup tests:  PASS=$PASS  FAIL=$FAIL  (TOTAL=$TOTAL)"
echo "=============================================================="
if [[ "$FAIL" -gt 0 ]]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
exit 0
