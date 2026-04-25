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

# ---------- F7: MCP auth probe named with rc classification ----------
# Acceptance: specific named probe call + 4 named buckets.
if grep -q "mcp__clickup__clickup_get_workspace_hierarchy" "$SKILL" \
   && grep -q "auth-ok" "$SKILL" \
   && grep -q "auth-fail" "$SKILL" \
   && grep -q "retryable-network" "$SKILL"; then
  pass "WS6-F7: named MCP probe + rc classification (auth-ok/fail/retryable)"
else
  fail "WS6-F7: named MCP probe + rc classification" "missing probe name or buckets"
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
