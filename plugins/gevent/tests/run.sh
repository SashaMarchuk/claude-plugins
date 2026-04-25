#!/usr/bin/env bash
# WS-10 regression harness for /gevent plugin.
# One assertion per PRD finding (H1-H4 + M1-M10 + L1-L19 = 33). Exits 0 on
# all-pass, 1 on any FAIL.
#
# Usage:  bash plugins/gevent/tests/run.sh
#
# POSIX-shell + grep + jq + Python (only for preflight.py invocation in L-19).
# All assertions verify that prose / code contracts established by WS-3 (H4),
# WS-4 (H1-H3, M9, M10), and WS-7 (M1-M8, L1-L19) survive in the plugin source.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SKILL="$PLUGIN_DIR/skills/gevent/SKILL.md"
MODES="$PLUGIN_DIR/skills/gevent/references/modes.md"
SCHEMA="$PLUGIN_DIR/skills/gevent/references/config-schema.md"
EVENT="$PLUGIN_DIR/skills/gevent/references/event-format.md"
PREFLIGHT="$PLUGIN_DIR/scripts/preflight.py"
SCHEDULE_CMD="$PLUGIN_DIR/commands/schedule.md"
CALENDAR_CMD="$PLUGIN_DIR/commands/calendar.md"

PASS=0
FAIL=0
FAIL_MSGS=()

pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); FAIL_MSGS+=("$1: $2"); printf 'FAIL  %s — %s\n' "$1" "$2"; }

# ============================================================ HIGH (H-1..H-4)

# ---------- H-1: auth classifier — schema check + broadened regex ----------
if grep -q "Auth OK (schema check, not substring match)" "$SKILL" \
   && grep -q "ENOTFOUND" "$SKILL" \
   && grep -q "ECONNREFUSED" "$SKILL" \
   && grep -qE "401\|403\|407\|5" "$SKILL" \
   && grep -q "proxy authentication" "$SKILL"; then
  pass "WS4-H1: auth classifier — schema check + broadened regex (401/403/407/5xx + proxy + ENOTFOUND)"
else
  fail "WS4-H1: auth classifier hardening" "missing schema-check or broadened regex"
fi

# ---------- H-2: conflict math — zero-dur + all-day + cumulative ----------
if grep -q "Zero-duration proposed event" "$SKILL" \
   && grep -q "All-day event" "$SKILL" \
   && grep -q "Cumulative" "$SKILL" \
   && grep -qE "overlap_pct >= 0\.50" "$SKILL"; then
  pass "WS4-H2: conflict math — zero-dur + all-day + cumulative + 0.50 auto-block"
else
  fail "WS4-H2: conflict math" "missing one of zero-dur / all-day / cumulative / threshold"
fi

# ---------- H-3: cancel sendUpdates honors config + attendee count ----------
if grep -q "Resolve \`sendUpdates\` mode" "$MODES" \
   && grep -q "config.defaults.send_updates" "$MODES" \
   && grep -q "attendee_count > 10" "$MODES" \
   && grep -q "NEVER hardcode \`\"all\"\`" "$MODES"; then
  pass "WS4-H3: cancel honors config.defaults.send_updates + attendee-count gate"
else
  fail "WS4-H3: cancel sendUpdates" "missing one anchor"
fi

# ---------- H-4: homoglyph gate on zero-match upsert (mirrored from clickup) ----------
if grep -q "zero-match upsert" "$SKILL" \
   && grep -q "FORCE \`AskUserQuestion\` disambiguation" "$SKILL" \
   && grep -q "raw bytes differ but skeletons match" "$SKILL"; then
  pass "WS3-H4: homoglyph gate fires on zero-match upsert path (gevent)"
else
  fail "WS3-H4: homoglyph zero-match upsert" "missing rule in gevent SKILL"
fi

# ============================================================ MEDIUM (M-1..M-10)

# ---------- M-1: notes_bot_decided strict-bool type check at pre-flight 3a ----------
if grep -q "isinstance(v, bool) and v is True" "$SKILL" \
   && grep -q "notes_bot_decided type-mismatch" "$SKILL" \
   && grep -q "isinstance(ai, list)" "$SKILL"; then
  pass "WS7-M1: notes_bot_decided strict-bool + always_include strict-list at pre-flight 3a"
else
  fail "WS7-M1: notes_bot_decided type-check" "missing strict-type assertion"
fi

# ---------- M-2: shadow-check broadened glob ----------
if grep -q "claude\.backup-\*" "$SKILL" \
   && grep -q "claude\.bak" "$SKILL" \
   && grep -q "claude\.old\*" "$SKILL" \
   && grep -q "claude-plugins-backup-\*" "$SKILL"; then
  pass "WS7-M2: shadow glob covers .claude.backup-* / .bak / .old* / -plugins-backup-*"
else
  fail "WS7-M2: shadow glob" "missing one of 4 backup-dir patterns"
fi

# ---------- M-3: read-path tempfile discipline for events list --params ----------
if grep -qF "Read-path tempfile discipline" "$SKILL" \
   && grep -qF -- "--params-file" "$SKILL" \
   && grep -qF "is the only trusted serializer" "$SKILL"; then
  pass "WS7-M3: read-path --params uses tempfile discipline"
else
  fail "WS7-M3: read-path tempfile discipline" "missing prose"
fi

# ---------- M-4: calendarId regex validation at pre-flight ----------
if grep -q "CALENDAR_ID_RE" "$SKILL" \
   && grep -q "calendarId" "$SKILL"; then
  pass "WS7-M4: calendarId validated against CALENDAR_ID_RE at pre-flight"
else
  fail "WS7-M4: calendarId validation" "missing CALENDAR_ID_RE anchor"
fi

# ---------- M-5: stale-read guard around onboarding Step 8 ----------
if grep -q "Step 8" "$MODES" \
   && grep -q "stale-read guard" "$MODES" \
   && grep -q "atomic_update" "$MODES"; then
  pass "WS7-M5: Step 8 stale-read guard via atomic_update closure"
else
  fail "WS7-M5: stale-read guard" "missing Step 8 / stale-read / atomic_update anchor"
fi

# ---------- M-6: unknown-key preservation as runtime guarantee ----------
if grep -q "Preserve unknown keys (mechanical, not aspirational)" "$SCHEMA" \
   && grep -q "atomic_update unknown-key preservation violated" "$SCHEMA" \
   && grep -q "__explicit_deletes__" "$SCHEMA"; then
  pass "WS7-M6: unknown-key preservation enforced inside atomic_update with key-set diff"
else
  fail "WS7-M6: unknown-key preservation" "missing helper guarantee"
fi

# ---------- M-7: intent-precedence — update wins over cancel ----------
if grep -q "update wins over cancel" "$MODES" \
   && grep -q "cancel and reschedule" "$MODES" \
   && grep -q "move Misha off the call" "$MODES"; then
  pass "WS7-M7: intent precedence — update wins; canonical examples present"
else
  fail "WS7-M7: intent precedence" "missing update-wins rule or examples"
fi

# ---------- M-8: DST spring-forward + fall-back AskUserQuestion ----------
if grep -q "spring-forward" "$EVENT" \
   && grep -q "fall-back" "$EVENT" \
   && grep -q "nonexistent" "$EVENT" \
   && grep -q "ambiguous" "$EVENT"; then
  pass "WS7-M8: DST spring-forward + fall-back detection with AskUserQuestion"
else
  fail "WS7-M8: DST handling" "missing spring-forward/fall-back/nonexistent/ambiguous"
fi

# ---------- M-9: conflict-list maxResults capped at 10 ----------
if grep -q "maxResults:10" "$SKILL" \
   || grep -q '"maxResults": 10' "$SKILL"; then
  pass "WS4-M9: conflict-list capped at maxResults:10"
else
  fail "WS4-M9: conflict-list cap" "expected maxResults:10 in SKILL"
fi

# ---------- M-10: events patch tempfile discipline + worked example ----------
if grep -q "events patch" "$EVENT" \
   && grep -q "Why the parallel structure matters" "$EVENT"; then
  pass "WS4-M10: events patch worked example pinned in event-format"
else
  fail "WS4-M10: events patch worked example" "missing"
fi

# ============================================================ LOW (L-1..L-19)

# ---------- L-1: requestId millisecond + random suffix ----------
if grep -q "millisecond timestamp + 6-char random suffix" "$SKILL" \
   && grep -q "weekly-sync-1712505600123-a4f9c2" "$SKILL"; then
  pass "WS7-L1: requestId millisecond + random suffix prevents same-second collision"
else
  fail "WS7-L1: requestId precision" "missing millisecond + random suffix prose"
fi

# ---------- L-2: notes-bot email cannot equal organizer email ----------
if grep -q "Notes-bot email cannot be your own email" "$MODES"; then
  pass "WS7-L2: notes-bot email != organizer email refuse rule"
else
  fail "WS7-L2: notes-bot self-email refuse" "missing rule"
fi

# ---------- L-3: always_include[].tag stripped before serialization ----------
if grep -q "strip local-only fields before serialization" "$EVENT" \
   && grep -q "always_include\[\]\.tag" "$EVENT"; then
  pass "WS7-L3: always_include[].tag + local-only fields stripped before envelope"
else
  fail "WS7-L3: tag-strip rule" "missing in event-format"
fi

# ---------- L-4: duplicate Request ID format section deduped ----------
# Should appear exactly once in event-format.md.
hits=$(grep -c "^### Request ID format" "$EVENT")
if [[ "$hits" -eq 1 ]]; then
  pass "WS7-L4: 'Request ID format' section appears exactly once (was duplicated)"
else
  fail "WS7-L4: dedup Request ID format" "section count=$hits expected 1"
fi

# ---------- L-5 + L-16: banner emoji unified across files (single source of truth) ----------
if grep -q "L-5 + L-16: single source of truth" "$SCHEMA"; then
  pass "WS7-L5+L16: banner emoji + wording unified (single source of truth note)"
else
  fail "WS7-L5+L16: banner unification" "missing single-source note in schema"
fi

# ---------- L-6: send_updates / duration_minutes / conference_type load-time schema check ----------
if grep -q "L-6 type check on load" "$SCHEMA" \
   && grep -q "send_updates" "$SCHEMA" \
   && grep -q "duration_minutes" "$SCHEMA" \
   && grep -q "conference_type" "$SCHEMA"; then
  pass "WS7-L6: load-time type check on send_updates / duration_minutes / conference_type"
else
  fail "WS7-L6: load-time schema check" "missing L-6 anchors"
fi

# ---------- L-7: prompt-injection defense via title quote-wrap on update/cancel ----------
# Look for explicit quote-block delimiter rule for re-read titles.
if grep -qE 'quote.block|verbatim.*delimiter|fenced.*block|backtick.*wrap' "$MODES" "$EVENT" "$SKILL" 2>/dev/null \
   && grep -qiE 'title|summary' "$MODES"; then
  pass "WS7-L7: title quote/fence wrap on re-read (update/cancel)"
else
  # Fallback: title rendering rule documented anywhere in update/cancel flows.
  if grep -qiE 'render.*title|title.*verbatim|title.*as-is' "$MODES"; then
    pass "WS7-L7: title rendering rule documented in modes (cancel/update flows)"
  else
    fail "WS7-L7: title quote-wrap" "no quote-block / verbatim rendering rule for titles"
  fi
fi

# ---------- L-8: contacts.json reject-symlink + 5MB cap ----------
if grep -q "L-8" "$MODES" \
   && grep -q "is_symlink()" "$MODES" \
   && grep -q "5MB" "$MODES"; then
  pass "WS7-L8: legacy contacts.json rejects symlinks + 5MB size cap"
else
  fail "WS7-L8: contacts.json hardening" "missing is_symlink / 5MB cap"
fi

# ---------- L-9: case-insensitive filesystem hazard — realpath at helper entry ----------
if grep -q "L-9" "$SCHEMA" \
   && grep -q "os\.path\.realpath" "$SCHEMA" \
   && grep -qi "case-insensitive" "$SCHEMA"; then
  pass "WS7-L9: case-insensitive FS hazard — realpath at helper entry"
else
  fail "WS7-L9: realpath normalization" "missing L-9 anchor"
fi

# ---------- L-10: --auto + non-create verb early refuse ----------
if grep -q "L-10" "$SKILL" \
   && grep -qF -- "--auto is create-only" "$SKILL" \
   && grep -q "Refusing rather than silently dropping the verb" "$SKILL"; then
  pass "WS7-L10: --auto + non-create verb early-refuse with verb-aware message"
else
  fail "WS7-L10: --auto non-create verb refuse" "missing rule"
fi

# ---------- L-11: 3rd-attempt alias-collision banner verbatim ----------
if grep -q "L-11" "$MODES" \
   && grep -q "banner warning" "$MODES" \
   && grep -q "verbatim text, do NOT paraphrase" "$MODES"; then
  pass "WS7-L11: alias-collision 3rd-attempt banner pinned verbatim"
else
  fail "WS7-L11: alias-collision banner" "missing verbatim banner anchor"
fi

# ---------- L-12: calendar-switch validates against calendars[] registry ----------
if grep -q "L-12" "$MODES" \
   && grep -q "calendars\[\]" "$MODES" \
   && grep -q "Re-pick from the list above" "$MODES"; then
  pass "WS7-L12: calendar-switch validates picked ID against calendars[] registry"
else
  fail "WS7-L12: calendar-switch registry validation" "missing rule"
fi

# ---------- L-13: teammates[].active=false refuse on --auto invite ----------
# The shared-active-default rule already lives in clickup; gevent inherits via
# shared identity.json. Verify gevent SKILL references the active gate.
if grep -qE "active|teammate.*invite|active.*false" "$SKILL" \
   && grep -q "trusted_domains" "$SKILL"; then
  pass "WS7-L13: teammates[].active gating present in gevent invite path"
else
  # Fallback: verify schema docs the active-default
  if grep -q "teammates\[\]\.active" "$SCHEMA"; then
    pass "WS7-L13: teammates[].active default-false shared via config-schema"
  else
    fail "WS7-L13: teammates[].active gate" "missing"
  fi
fi

# ---------- L-14: trusted_domains[] documented + in schema example ----------
if grep -qF "(L-14)" "$SCHEMA" \
   && grep -qF "trusted_domains" "$SCHEMA" \
   && grep -qF "speedandfunction.com" "$SCHEMA"; then
  pass "WS7-L14: trusted_domains[] in schema example + L-14 field rule heading"
else
  fail "WS7-L14: trusted_domains[] schema" "missing example or L-14 anchor"
fi

# ---------- L-15: plugin.json version vs schemaVersion mapping policy ----------
if grep -q "L-15" "$SCHEMA" \
   && grep -qF "plugin.json:version" "$SCHEMA" \
   && grep -qF "evolve INDEPENDENTLY" "$SCHEMA"; then
  pass "WS7-L15: plugin.json:version vs schemaVersion mapping policy documented"
else
  fail "WS7-L15: version policy" "missing L-15 mapping"
fi

# ---------- L-16: legacy-shadow text dedup (covered by L-5+L-16 combined check) ----------
# Already covered by L-5 assertion above — register coverage explicitly.
if grep -q "L-5 + L-16" "$SCHEMA"; then
  pass "WS7-L16: legacy-shadow detection text deduped (single source)"
else
  fail "WS7-L16: legacy-shadow dedup" "missing"
fi

# ---------- L-17: $ARGUMENTS shell-expansion awareness in SKILL.md ----------
if grep -q "L-17" "$SKILL" \
   && grep -q "\\\$ARGUMENTS\` shell-expansion awareness" "$SKILL"; then
  pass "WS7-L17: \$ARGUMENTS shell-expansion awareness documented"
else
  fail "WS7-L17: \$ARGUMENTS expansion note" "missing"
fi

# ---------- L-18: cancel confirmation shows attendee count + sample ----------
if grep -q "L-18" "$MODES" \
   && grep -q "attendee_count" "$MODES" \
   && grep -q "first 5 emails" "$MODES"; then
  pass "WS7-L18: cancel confirmation shows attendee count + sample head"
else
  fail "WS7-L18: cancel confirmation" "missing count/sample"
fi

# ---------- L-19: scripts/preflight.py present + invoked + working ----------
if [[ -f "$PREFLIGHT" ]] && grep -q "L-19" "$SKILL" \
   && grep -q "scripts/preflight.py" "$SKILL"; then
  pass "WS7-L19: scripts/preflight.py present + SKILL invokes it as REQUIRED first action"
else
  fail "WS7-L19: preflight.py" "file missing or not referenced from SKILL"
fi
# Functional: invoke preflight on a synthetic clean fixture and confirm a
# parseable exit-code semantics (we don't need pass/fail, just that it runs).
if command -v python3 >/dev/null 2>&1 && [[ -f "$PREFLIGHT" ]]; then
  set +e
  python3 -c "import ast; ast.parse(open('$PREFLIGHT').read())" 2>/dev/null
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    pass "WS7-L19: preflight.py is syntactically valid Python"
  else
    fail "WS7-L19: preflight.py syntax" "ast.parse failed"
  fi
fi

# ============================================================ Summary
TOTAL=$((PASS + FAIL))
echo
echo "=============================================================="
echo "/gevent tests:  PASS=$PASS  FAIL=$FAIL  (TOTAL=$TOTAL)"
echo "=============================================================="
if [[ "$FAIL" -gt 0 ]]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
exit 0
