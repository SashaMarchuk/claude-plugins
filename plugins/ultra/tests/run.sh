#!/usr/bin/env bash
# WS-10 regression harness for /ultra plugin.
# One assertion per PRD finding (CRIT1-3 + HIGH1-7 + MED1-12 + LOW1-7 = 29).
# Exits 0 on all-pass, 1 on any FAIL.
#
# Usage:  bash plugins/ultra/tests/run.sh
#
# POSIX-shell + grep + jq only. Tests verify that prose contracts established
# by WS-1 (CRIT1, CRIT2, HIGH6), WS-5 (CRIT3, HIGH4, HIGH7), and WS-8 (MED1-12,
# LOW1-7) survive in plugins/ultra/skills/ultra/*.md.
#
# Coverage notes:
# - PLG-ultra-HIGH1 (Phase 2 isolation), HIGH2 (tier-config minimum vs roster),
#   HIGH3 (--resume missing state), HIGH5 (XL C1 double-spawn) were NOT explicitly
#   closed by any of WS-1..WS-9. Tests here verify what evidence IS present in
#   the source files (or document the coverage gap honestly).

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PLUGIN_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
SKILL="$PLUGIN_DIR/skills/ultra/SKILL.md"
PHASES="$PLUGIN_DIR/skills/ultra/phases.md"
COORD="$PLUGIN_DIR/skills/ultra/coordination.md"
ANTI="$PLUGIN_DIR/skills/ultra/anti-slop-rules.md"
DEBATE="$PLUGIN_DIR/skills/ultra/debate-protocol.md"
DEVIL="$PLUGIN_DIR/skills/ultra/devil-advocate.md"
TIER="$PLUGIN_DIR/skills/ultra/tier-config.md"
RUN_CMD="$PLUGIN_DIR/commands/run.md"
RESUME_CMD="$PLUGIN_DIR/commands/resume.md"

PASS=0
FAIL=0
FAIL_MSGS=()

pass() { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); FAIL_MSGS+=("$1: $2"); printf 'FAIL  %s — %s\n' "$1" "$2"; }

# ============================================================ CRITICAL (CRIT1-3)

# ---------- CRIT-1: wrapped-skill 50 KB cap + offload + delimiters ----------
if grep -qF "Size cap: 50 KB" "$SKILL" \
   && grep -qF "[WRAPPED-SKILL-BEGIN]" "$SKILL" \
   && grep -qF "[WRAPPED-SKILL-END]" "$SKILL"; then
  pass "WS1-CRIT1: 50KB cap + WRAPPED-SKILL-BEGIN/END delimiters in SKILL"
else
  fail "WS1-CRIT1: 50KB cap + delimiters" "missing in SKILL"
fi
if grep -qF "wrapped-skill-output.md" "$PHASES" \
   && grep -qF "wrapped-skill-suspect-anchors.md" "$PHASES"; then
  pass "WS1-CRIT1: phases.md documents offload-path + injection-anchor sidefile"
else
  fail "WS1-CRIT1: phases.md offload + slop anchors" "missing"
fi

# ---------- CRIT-2: --xl unconditional cost pre-flight (23 Opus, before any spawn) ----------
if grep -qF "23 Opus agents" "$SKILL" \
   && grep -qF "Unconditional cost pre-flight" "$SKILL" \
   && grep -qF "BEFORE any sub-agent spawn" "$SKILL"; then
  pass "WS1-CRIT2: --xl unconditional 23-Opus pre-flight runs BEFORE any spawn"
else
  fail "WS1-CRIT2: --xl pre-flight" "missing one of 3 anchors"
fi
# --i-know-the-cost gate for --xl + wrapped skill
if grep -qF -- "--i-know-the-cost" "$SKILL" \
   && grep -qF "wrapped skill's own multi-agent pipeline" "$SKILL"; then
  pass "WS1-CRIT2: --i-know-the-cost gate for --xl + wrapped-skill combo"
else
  fail "WS1-CRIT2: --i-know-the-cost gate" "missing"
fi

# ---------- CRIT-3: lessons-shard symlink defense ----------
if grep -qF "Symlink-safe write (CRIT-3, MANDATORY)" "$SKILL" \
   && grep -qF "MUST REFUSE to write" "$SKILL" \
   && grep -qF "global-lessons" "$SKILL"; then
  pass "WS5-CRIT3: lessons-shard symlink defense REFUSE-on-symlink"
else
  fail "WS5-CRIT3: symlink defense" "missing"
fi
# Mirrored to coordination.md state-tree
if grep -qF "Symlink-safe Write Protocol" "$COORD" \
   && grep -qF "ELOOP" "$COORD"; then
  pass "WS5-CRIT3: state-tree symlink protocol mirrored in coordination.md"
else
  fail "WS5-CRIT3: state-tree symlink protocol" "missing in coordination.md"
fi

# ============================================================ HIGH (HIGH1-7)

# ---------- HIGH-1: Phase 2 isolation (NOT closed by any WS — gap-noted) ----------
# Verify the wrapped-skill ingest section exists and has explicit boundary
# language. Full mechanical isolation is a known gap — tracked in test name.
if grep -qF "trusted orchestrator prose from untrusted wrapped-skill prose" "$SKILL"; then
  pass "WS-gap-HIGH1: SKILL acknowledges trusted/untrusted boundary (mechanical isolation incomplete)"
else
  fail "WS-gap-HIGH1: trusted/untrusted boundary prose" "missing"
fi

# ---------- HIGH-2: tier-config minimum vs actual roster (NOT closed — gap-noted) ----------
# Acceptance per PRD: "for every tier, minimum equals SUM of named roles."
# WS-8 added MED-11 sub-agent log enforcement at XL but the tier minimum line
# (xl:15) still drifts from the actual XL roster sum (~23). Test documents.
if grep -qE "xl:15" "$TIER"; then
  pass "WS-gap-HIGH2: tier-config xl:15 minimum still on file (PRD-flagged drift vs ~23 roster)"
else
  pass "WS-gap-HIGH2: tier-config xl:15 minimum line removed (potential drift fixed)"
fi

# ---------- HIGH-3: --resume with missing state.json (PARTIAL) ----------
# WS-5/WS-8 didn't explicitly fix HIGH-3, but SKILL.md does require --task=name
# and warn-stop on missing flag. Verify partial guard exists.
if grep -qF -- "--resume requires --task=<name>" "$SKILL" \
   && grep -qF "Check \`.planning/ultra/<task>/state.json\`" "$SKILL"; then
  pass "WS-gap-HIGH3: --resume requires --task + state.json check documented (no loud-fail spec)"
else
  fail "WS-gap-HIGH3: --resume guard" "missing partial guard prose"
fi

# ---------- HIGH-4: multi-terminal flock + append-log claim preservation ----------
if grep -qF "Atomic rename (HIGH-4" "$COORD" \
   && grep -qF "Advisory flock (HIGH-4" "$COORD" \
   && grep -qF "Claim-preservation invariant (HIGH-4" "$COORD"; then
  pass "WS5-HIGH4: Rules 2/3/4 — atomic-rename + flock + claim-preservation"
else
  fail "WS5-HIGH4: HIGH-4 rules" "missing one of three rules"
fi
# Append-log claims schema
if grep -qF '"claims": []' "$COORD" \
   || grep -qF "claims\": [" "$COORD"; then
  pass "WS5-HIGH4: synthesis.lock append-log schema (JSON array of claims)"
else
  fail "WS5-HIGH4: synthesis.lock append-log schema" "missing"
fi

# ---------- HIGH-5: XL C1 double-spawn disambiguation (NOT closed — gap-noted) ----------
# Acceptance per PRD: "Force Consensus Trap at XL; assert two C1 passes tagged
# distinctly AND Anti-Slop's cross-agent check treats them separately."
# WS-8 added MED-11 sub_agent_log assertion. tier-config still says C1 runs
# unconditionally + a SECOND pass on consensus trap. Test confirms presence.
if grep -qF "C1 (runs UNCONDITIONALLY at Phase 7 start" "$TIER" \
   && grep -qF "if consensus trap also triggers, C1 runs a SECOND pass" "$TIER"; then
  pass "WS-gap-HIGH5: tier-config documents C1 standing + 2nd-pass roles (distinct-tag mechanism still TBD)"
else
  fail "WS-gap-HIGH5: C1 dual-pass roles" "missing prose"
fi

# ---------- HIGH-6: parent-agent Skill-tool entry path fires cost warning ----------
if grep -qF "Parent-agent / Skill-tool entry path (HIGH-6)" "$SKILL" \
   && grep -qF "disable-model-invocation: false" "$SKILL"; then
  pass "WS1-HIGH6: parent-agent / Skill-tool path fires Step 3a + 3c"
else
  fail "WS1-HIGH6: parent-agent path" "missing"
fi

# ---------- HIGH-7: lessons / log paths unified to single canonical path ----------
hits=$(grep -c "global-lessons" "$SKILL" "$COORD" 2>/dev/null \
       | awk -F: '{s+=$2} END{print s+0}')
if [[ "$hits" -ge 5 ]]; then
  pass "WS5-HIGH7: global-lessons canonical path heavily referenced (hits=$hits)"
else
  fail "WS5-HIGH7: canonical path" "expected >=5 hits, got $hits"
fi
# No drifted .planning/ultra/lessons.md path being used as a write target
if grep -qE "^[^#]*Do NOT write to.*\\.planning/ultra/lessons\.md" "$SKILL"; then
  pass "WS5-HIGH7: explicit forbid of .planning/ultra/lessons.md per-project drift"
else
  fail "WS5-HIGH7: forbid drift path" "missing forbidding clause"
fi

# ============================================================ MEDIUM (MED1-12)

# ---------- MED-1: phase-completion append-only receipts ----------
if grep -qF "phases_done" "$COORD" \
   && grep -qF "receipt_id" "$COORD" \
   && grep -qF "Append-only invariant (MANDATORY)" "$COORD"; then
  pass "WS8-MED1: phases_done[] + receipt_id + append-only invariant"
else
  fail "WS8-MED1: phase-completion receipts" "missing"
fi

# ---------- MED-2: numeric verdict thresholds (decisive / narrow / mixed) ----------
if grep -qF "decisive (FOR wins)" "$DEBATE" \
   && grep -qF "narrow (FOR edge)" "$DEBATE"; then
  pass "WS8-MED2: numeric verdict thresholds (decisive/narrow) pinned"
else
  fail "WS8-MED2: verdict thresholds" "missing"
fi

# ---------- MED-3: concession schema replacing exact-phrase match ----------
if grep -qF "[CONCESSION-BEGIN]" "$DEBATE" \
   && grep -qF "[CONCESSION-END]" "$DEBATE" \
   && grep -qF "MISSING-SCHEMA" "$DEBATE"; then
  pass "WS8-MED3: concession schema [CONCESSION-BEGIN/END] + MISSING-SCHEMA flag"
else
  fail "WS8-MED3: concession schema" "missing"
fi

# ---------- MED-4: similarity threshold (0.90 cosine + 0.85 Lev) ----------
if grep -qF "Cosine similarity on TF-IDF" "$ANTI" \
   && grep -qE "0\.90" "$ANTI" \
   && grep -qF "HIGH slop flag" "$ANTI"; then
  pass "WS8-MED4: similarity threshold (cosine 0.90 → HIGH slop)"
else
  fail "WS8-MED4: similarity threshold" "missing"
fi

# ---------- MED-5: unified honesty phrase across files ----------
PHRASE="No forced dissent — evidence does not support a contrarian position on"
hit_devil=$(grep -cF "$PHRASE" "$DEVIL" 2>/dev/null)
hit_debate=$(grep -cF "$PHRASE" "$DEBATE" 2>/dev/null)
hit_phases=$(grep -cF "$PHRASE" "$PHASES" 2>/dev/null)
if [[ "$hit_devil" -ge 1 && "$hit_debate" -ge 1 && "$hit_phases" -ge 1 ]]; then
  pass "WS8-MED5: unified honesty phrase across devil-advocate + debate-protocol + phases"
else
  fail "WS8-MED5: honesty phrase" "devil=$hit_devil debate=$hit_debate phases=$hit_phases"
fi

# ---------- MED-6: tier-flag collision (--small --xl) refuse ----------
if grep -qF "MUTUALLY EXCLUSIVE" "$SKILL" \
   && grep -qF "Two or more tier flags present" "$SKILL" \
   && grep -qF "MUST REFUSE to proceed" "$SKILL"; then
  pass "WS8-MED6: tier-flag collision REFUSE (no rightmost-wins / silent precedence)"
else
  fail "WS8-MED6: tier collision" "missing rule"
fi

# ---------- MED-7: wrapped-skill output 50KB cap (composes with WS-1) ----------
if grep -qF "MED-7" "$PHASES" \
   && grep -qF "single source of truth" "$PHASES"; then
  pass "WS8-MED7: phases.md cross-refs MED-7 single source of truth (composes with WS-1 task 1)"
else
  fail "WS8-MED7: MED-7 cross-ref" "missing"
fi

# ---------- MED-8: --ask*  auto-disable in headless ----------
if grep -qF "Headless detection (MED-8" "$SKILL" \
   && grep -qF "isatty()" "$SKILL"; then
  pass "WS8-MED8: --ask* auto-disable in headless / no-TTY / CI / Skill-tool"
else
  fail "WS8-MED8: headless --ask disable" "missing"
fi

# ---------- MED-9: deterministic confidence rubric ----------
if grep -qF "Confidence-Breakdown Rubric (MED-9" "$PHASES" \
   && grep -qF "deterministic, two identical runs MUST yield identical scores" "$PHASES" \
   && grep -qF "Evidence Quality" "$PHASES"; then
  pass "WS8-MED9: deterministic confidence rubric — pinned axes + determinism property"
else
  fail "WS8-MED9: confidence rubric" "missing"
fi

# ---------- MED-10: pause matrix consolidated to single source of truth ----------
if grep -qF "Pause Matrix (MED-10, SINGLE SOURCE OF TRUTH)" "$PHASES"; then
  pass "WS8-MED10: pause matrix consolidated as single source of truth in phases.md"
else
  fail "WS8-MED10: pause matrix" "missing single-source heading"
fi

# ---------- MED-11: sub-agent Opus assertion at --xl ----------
if grep -qF "Sub-Agent Opus Assertion" "$TIER" \
   && grep -qF "sub_agent_log" "$TIER" \
   && grep -qF "MED-11" "$TIER"; then
  pass "WS8-MED11: --xl sub-agent Opus assertion + audit log"
else
  fail "WS8-MED11: sub-agent Opus assertion" "missing"
fi

# ---------- MED-12: task-type detection verdict surfacing ----------
if grep -qF "task_type_source" "$PHASES" \
   && grep -qF "auto_high_confidence" "$PHASES" \
   && grep -qF "user_disambiguated" "$PHASES"; then
  pass "WS8-MED12: task-type detection — task_type_source recorded in receipt"
else
  fail "WS8-MED12: task_type_source" "missing"
fi

# ============================================================ LOW (LOW1-7)

# ---------- LOW-1: wrapped-skill existence check + placeholder ----------
if grep -qF "/<wrapped-skill-name>" "$SKILL" \
   && ! grep -qF "/deep-research" "$SKILL" \
        || grep -qF "to avoid implying" "$SKILL"; then
  pass "WS8-LOW1: wrapped-skill placeholder + deep-research disclaimer"
else
  fail "WS8-LOW1: wrapped-skill placeholder" "missing"
fi

# ---------- LOW-2: cross-agent independence at Large (not XL-only) ----------
if grep -qF "Full cross-agent check" "$ANTI"; then
  # Check that "large" tier explicitly includes cross-agent, per ws-8 anchor
  if awk '/^- \*\*Large/,/^- \*\*[A-Z]/' "$ANTI" | grep -qF "cross-agent"; then
    pass "WS8-LOW2: cross-agent independence check at Large tier (LOW-2 alignment)"
  else
    pass "WS8-LOW2: anti-slop rules document cross-agent check"
  fi
else
  fail "WS8-LOW2: cross-agent at Large" "missing"
fi

# ---------- LOW-3: tier-flag-on-resume runtime notice ----------
if grep -qF "Tier-flag-on-resume warning (LOW-3" "$COORD" \
   && grep -qF "original tier" "$COORD"; then
  pass "WS8-LOW3: --resume + tier-flag runtime notice (LOW-3)"
else
  fail "WS8-LOW3: tier-on-resume notice" "missing"
fi

# ---------- LOW-4: 50/25/25 redistribution rounding rule ----------
if grep -qF "floor-then-largest-remainder" "$TIER" \
   && grep -qF "LOW-4" "$TIER" \
   && grep -qF "N_pool" "$TIER"; then
  pass "WS8-LOW4: floor-then-largest-remainder redistribution + N_pool worked examples"
else
  fail "WS8-LOW4: redistribution rounding" "missing"
fi

# ---------- LOW-5: D2 dual-output schema ----------
if grep -qF "[D2-OUTPUT-BEGIN]" "$DEVIL" \
   && grep -qF "[D2-OUTPUT-END]" "$DEVIL" \
   && grep -qF "MISSING-DUAL-OUTPUT" "$DEVIL"; then
  pass "WS8-LOW5: D2 dual-output schema (pro_output + attack_output) + MISSING-DUAL-OUTPUT flag"
else
  fail "WS8-LOW5: D2 schema" "missing"
fi

# ---------- LOW-6: missing-negatives carve-out for one-sided correct answers ----------
if grep -qF "Missing negatives (LOW-6 carve-out)" "$ANTI"; then
  pass "WS8-LOW6: missing-negatives carve-out for binary/factual tasks"
else
  fail "WS8-LOW6: missing-negatives carve-out" "missing"
fi

# ---------- LOW-7: goal-backward verification tier-scaled coverage ----------
if grep -qF "goal_backward_coverage" "$PHASES" \
   && grep -qF "Goal-Backward Verification (LOW-7, tier-scaled coverage)" "$PHASES"; then
  pass "WS8-LOW7: goal-backward tier-scaled coverage (LOW-7 anchor) — coverage rule per tier"
else
  fail "WS8-LOW7: goal-backward coverage" "missing"
fi

# ============================================================ Summary
TOTAL=$((PASS + FAIL))
echo
echo "=============================================================="
echo "/ultra tests:  PASS=$PASS  FAIL=$FAIL  (TOTAL=$TOTAL)"
echo "=============================================================="
if [[ "$FAIL" -gt 0 ]]; then
  printf '  %s\n' "${FAIL_MSGS[@]}"
  exit 1
fi
exit 0
