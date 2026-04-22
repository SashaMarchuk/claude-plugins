# /ultra Validation Gates

/ultra (adversarial multi-agent swarm) is **expensive**. The pipeline invokes it at exactly **two** gates where the cost is justified by downstream risk.

## Gate 1: pre-discover

**When:** After `/ultra-analyzer:init`, before topic generation.
**Why:** Bad seeds = bad topics = bad findings. A flawed `config.yaml` or insufficient `seeds.md` cascades through the entire run. Cheap to catch now, expensive to catch after 50 topics are analyzed.

**What /ultra validates:**
- `seeds.md` has enough P1/P2/P3 investigation seeds (minimums per priority tier)
- `connector.md` implements all 6 contract operations with concrete, runnable instructions; auth / env vars declared (not hardcoded)
- `forbidden_fields` list is plausible (not empty, not suspiciously too-small)
- Citation anchor format is unambiguous
- Budget tiers are realistic for corpus size

**Tier:** driven by the active profile (`state.profile.ultra_gate_tier`). Small profile uses `--small`; large (default) uses `--large`; xl uses `--xl`. Change with `/ultra-analyzer:set-profile`.

**Invocation (inside `skills/run/SKILL.md`):**
```
/ultra $ULTRA_TIER --task=analyzer-gate1-<run-name> "Review this analyzer run bootstrap for soundness. Specifically: (1) are seeds sufficient in count and domain-grounding for P1/P2/P3? (2) does connector.md implement all 6 operations with concrete runnable instructions? (3) are auth / env vars declared (not hardcoded)? (4) are forbidden_fields plausible? Produce PASS or FAIL with specific remediation. Config: <cat config.yaml>. Seeds: <cat seeds.md>. Connector: <cat connector.md>."
```

**Verdict handling:**
- **PASS** → state.json `ultra_gates["pre-discover"].verdict = "PASS"`, advance to discover.
- **FAIL** → pause, write remediation report, require user edit of config/seeds, then re-run gate.

## Gate 2: pre-synthesize

**When:** After all topics analyzed + validated, before Opus synthesis.
**Why:** Synthesis is the most expensive step (Opus on full findings corpus) AND the most hallucination-prone (narrative generation). Catching bad findings before they contaminate the report saves both cost and reputation.

**What /ultra validates:**
- Coverage: do findings actually address the seed questions, or did topics drift?
- Evidence base (§0): is T000-equivalent denominator accounting present and coherent?
- Redundancy pairs: are divergent pairs flagged for human review, not averaged?
- Validator PASS rate is healthy (>80%). Low PASS rate = systematic problem upstream.
- No silent failure modes: does any finding claim "% of users" without denominator?

**Tier:** same as Gate 1 — driven by `state.profile.ultra_gate_tier`. If you want asymmetric gates (lighter Gate 1, heavier Gate 2), manually edit `state.json::profile.ultra_gate_tier` between gates or set a stricter profile before Gate 2.

**Invocation:**
```
/ultra $ULTRA_TIER --task=analyzer-gate2-<run-name> "Review findings corpus before synthesis. Seeds were: <cat seeds.md>. Findings at: <ls findings/>. Validator verdicts at: <ls validation/findings/>. Specifically: (1) coverage vs seeds, (2) denominator discipline, (3) divergent pair handling, (4) any finding that should FAIL but slipped PASS. Produce PASS or revise list."
```

**Verdict handling:**
- **PASS** → advance to synthesize.
- **FAIL with revise-list** → requeue affected topics with specific fix reasons, re-run those, re-gate.

## Why NOT at other steps

| Step | Why no /ultra |
|---|---|
| discover | Generates topics from seeds — if seeds passed Gate 1, topic generation is mechanical. Single Sonnet call suffices. |
| analyze (per topic) | Workers are budget-bound, query-deterministic, validator-checked. Swarm would be 10× cost for no signal. |
| validate | Validator uses a DIFFERENT model than worker (Haiku vs Sonnet) — cross-model check is already the validation signal. Swarm is redundant. |

## Cost discipline

Running /ultra at 2 gates per run vs every step = ~80% cost reduction while preserving the value of adversarial validation exactly where it matters (config review + pre-narrative audit).
