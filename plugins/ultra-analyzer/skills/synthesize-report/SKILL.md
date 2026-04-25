---
name: synthesize-report
description: Opus synthesis across all PASS findings into synthesis/REPORT.md. Triangulates redundancy pairs, flags divergence without averaging, produces Top-N compelling findings with narrative + curated quotes. Runs after Gate 2 (/ultra pre-synthesize) approves.
model: opus
allowed-tools: Bash, Read, Write, Glob
---

# Role
REPORT SYNTHESIS. Runs ONCE at end of pipeline. Sole output: `synthesis/REPORT.md`.

# Invocation
  /ultra-analyzer:synthesize-report <run-path>

# Inputs
1. `<run-path>/state/manifest.json`
2. `<run-path>/findings/*.md` — filter to those with PASS verdict in `validation/findings/*.json`
3. `<run-path>/topics/done/*.md` — topic specs for included findings
4. `<run-path>/topics/failed/*.md` — for Appendix B
5. `<run-path>/config.yaml` + `<run-path>/seeds.md` — for coverage assessment

# Mode branch: SINGLE vs CHUNKED

Before loading anything:
```bash
du -sk <run-path>/findings/
```

- If total findings size < 400 KB → SINGLE mode: load all findings, produce one REPORT.md in one pass.
- If >= 400 KB → CHUNKED mode:
  - Pass 1: produce `synthesis/REPORT.draft-chunks/{p1,p2,p3}.md` (one chunk per priority tier, each reading only its tier's findings).
  - Pass 2: merge pass that reads only the three chunks + manifest + reconcile notes, produces final REPORT.md.

# Triangulation (redundancy pairs)

For each pair in manifest.redundancy_pairs:
1. Load both findings files.
2. Compare:
   - Direction: same sign? (+/+, -/-, or +/-)
   - Magnitude: within 2x?
   - Confidence: both >=0.6?
3. Write `<run-path>/synthesis/reconcile/<pair-id>.md` with outcome:
   - **REPLICATED**: same direction, within 2x magnitude → merge as single finding with doubled evidence weight.
   - **DIRECTION-CONFIRMED-MAGNITUDE-UNCERTAIN**: same direction, 2-3x magnitude divergence → report direction only, flag magnitude as uncertain.
   - **DIVERGENT**: opposite direction OR >3x magnitude divergence → flag in report as unresolved, rename both topics to `pending/<name>__divergence-reconcile.md` for a stronger-model retry run. DO NOT AVERAGE.

# Evidence weight score (0-8) per included finding

- Sample size: >500 = ✓✓ (2), 100-500 = ✓ (1), <100 = ⚠ (0)
- Validator: PASS = ✓ (1), PASS-with-warning = ⚠ (0)
- Redundancy: triangulated REPLICATED = ✓✓ (2), solo = ✓ (1), divergent = ⚠ (0)
- Citation quality: all numeric claims cite = ✓✓ (2), some uncited flagged = ⚠ (0)

Sum → 0-8. Include in report only findings with score >= 4. Score 4-5 noted as moderate evidence; >= 6 as strong.

# REPORT.md structure (MANDATORY sections in order)

```markdown
# <Project Name> — Analyzer Report
_Generated YYYY-MM-DD, N findings included, M excluded as FAIL, K divergent pairs._

## §0 Evidence bases (MANDATORY FIRST SECTION)
<Denominator accounting from T000-equivalent finding if present.>
<Every subsequent percentage must specify subset, NOT bare "% of users".>

## Executive summary
<3-6 paragraphs, P1 first.>

## Top N for the decision-maker call
<For each of top N (N=5 by default, configurable) most-compelling findings:>
- Headline (specific, quantitative, <20 words)
- Narrative interpretation (2-3 sentences — correlation framing only, never causation)
- Supporting quotes (1-2 verbatim, ≤200 chars, with citation anchor)
- Confidence + evidence weight

## P1: <primary domain — most detail>
### Finding 1.1 ...

## P2: <secondary domain — compressed>

## P3: <tertiary — appendix-style tables>

## Curated quotes
<10 verbatim ≤200 chars each, chosen to illustrate P1 patterns.>

## Divergent findings requiring human review
<From triangulation DIVERGENT outcomes. Never hidden by averaging.>

## Honest-ambiguity statement
<If the P1 answer is weak or ambiguous, say so explicitly. Do NOT manufacture a thesis to meet expectations.>

## Audit-trail note
<One paragraph: every number in this report traces to a topic file in topics/done/, queries listed in the topic, and validator verdict in validation/findings/. Fully reproducible.>

## Appendix A — Topics run
<Table: topic ID, priority, complexity, model, verdict, one-line summary.>

## Appendix B — Topics failed
<Table: topic ID, reason, retry count.>

## Appendix C — Coverage
<Table: unit (collection/file/etc.), topic count, notes.>
```

# Hard rules
- NEVER cite a finding with verdict=FAIL.
- NEVER mark a report PASS if any included finding has an empty / placeholder
  `## Contradictions with hypothesis` section (closes M-5). The validator's
  Step 3a refuses such findings at verdict time, but synthesize-report MUST
  re-check at compose time as defense-in-depth: any included finding whose
  contradictions body is whitespace-only or matches a placeholder
  (none / n/a / tbd / pending / `-`) FAILs the report compose with reason
  `empty-contradictions in TNNN`. Re-run validator on those topics first.
- NEVER introduce conclusions not supported by at least one PASS finding.
- NEVER hide a divergent pair by averaging — always flag explicitly.
- EVERY numeric claim in REPORT carries [DATA:...] or [AGENT:TNNN] anchor.
- If any finding claims "% of X" without subset qualifier → flag it, rewrite with explicit subset. Fake precision is slop.
- Before the Top-N section, confirm each candidate has a non-trivial denominator (>=100 records AND >=5% of its subset).
- If seeds.md explicitly excluded causation claims, report must use correlation framing only. Label every claim "correlation" or "observational pattern" — never "causes" or "leads to".
- The composite "signal of value" construct must count only components the adapter actually supports with user-linkable data. If a signal source lacks user linkage, report it as collection-level only.
