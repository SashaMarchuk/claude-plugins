# Anti-Slop Audit Protocol

## Purpose

The anti-slop audit ensures all /ultra outputs represent genuine independent reasoning, not pattern-matched AI defaults. This is the last quality gate before final synthesis.

## When This Runs

Phase 8 of the /ultra pipeline. After all research, validation, and debate phases.

## Evidence Audit (Core Check)

Every claim in the final synthesis MUST have an evidence anchor. The auditor checks EVERY assertion and classifies it:

### Evidence Anchor Types

| Anchor | Format | Trust Level |
|--------|--------|-------------|
| Code reference | `[FILE:path/file.ts:42]` | HIGH — verifiable |
| External source | `[URL:docs.example.com/api]` | MEDIUM — may change |
| Agent finding | `[AGENT:R3]` | MEDIUM — independent observation |
| Data/metric | `[DATA:latency p99 = 12ms]` | HIGH — if source cited |
| Hypothesis | `[HYPOTHESIS: no evidence located]` | LOW — flagged for user |

### Audit Process

The Anti-Slop Auditor (A1) receives ALL phase outputs and performs:

**Step 1: Claim Extraction**
Identify every factual claim, recommendation, or conclusion in the Phase 3 synthesis and Phase 7 debate verdict.

**Step 2: Evidence Check**
For each claim, verify it has at least one evidence anchor. Flag any claim that:
- Makes a confident assertion with no evidence anchor
- Uses vague language ("generally", "typically", "it's well-known that")
- References "best practices" without citing a specific source
- Copies phrasing from another agent without attribution (cross-agent plagiarism)

**Step 3: Four-Level Artifact Verification**
For the top 5 most important claims, perform deep verification:

1. **EXISTS**: Does the cited evidence actually exist? (Check file paths, URLs)
2. **SUBSTANTIVE**: Is the evidence real content, not a placeholder? (Check for TODO, stub, placeholder, empty response)
3. **WIRED**: Is the evidence actually connected to the claim? (Does the cited code actually implement what's claimed?)
4. **DATA FLOWS**: Is there real data, not hardcoded/mocked responses?

## Slop Indicators

The auditor flags the following patterns as potential slop:

### High-Confidence Slop Flags
- **Unanchored confidence**: "This is clearly the best approach" with no evidence
- **Echo agreement**: Agent restates another agent's conclusion using different words without independent investigation
- **Hedging cascade**: "While there are trade-offs, generally speaking, in most cases..." — vagueness masking lack of analysis
- **Suspiciously similar phrasing**: Two or more "independent" agents use nearly identical wording (suggests pattern-matching, not independent reasoning)

### Medium-Confidence Slop Flags
- **Generic recommendations**: Advice that would apply to ANY project, not specifically this one
- **Missing negatives**: Analysis that found zero downsides, risks, or trade-offs (unrealistic for any non-trivial decision)
- **Premature convergence**: All researchers agreed in Phase 2 without exploring meaningfully different approaches

### Investigation Required
- **Conflicting evidence cited**: Two agents cite evidence that contradicts each other — one must be wrong
- **Outdated sources**: Evidence from sources that may have changed (version-specific docs, old blog posts)

## Audit Output Format

```
ANTI-SLOP AUDIT REPORT
======================

Overall: PASS / WARN / FAIL

Claims Audited: N
  - Fully evidenced: N (X%)
  - Partially evidenced: N (X%)
  - Unanchored: N (X%) ← these are the problem
  - Explicitly hypothetical: N (X%)

Slop Flags:
  HIGH: [list specific flags with citations]
  MEDIUM: [list specific flags with citations]

Artifact Verification (top 5 claims):
  Claim 1: EXISTS ✓ | SUBSTANTIVE ✓ | WIRED ✓ | DATA FLOWS ✓
  Claim 2: EXISTS ✓ | SUBSTANTIVE ✓ | WIRED ✗ (code exists but doesn't implement claimed behavior)
  ...

Cross-Agent Independence Check:
  - R1/R2 similarity: LOW (genuinely independent) ✓
  - R3/R4 similarity: HIGH (suspicious phrasing overlap) ⚠
  ...

Recommendation: [proceed / revise claims N,N / re-investigate claim N]
```

## Tier-Specific Depth

- **Small**: Spot-check top 3 claims only. Skip artifact verification. Skip cross-agent independence check.
- **Medium**: Full claim audit. Spot-check top 5 for artifact verification. Cross-agent check on all researchers.
- **Large**: Full claim audit. Full artifact verification on top 5. Full cross-agent check. Flag + re-investigate any FAIL.
- **XL**: Everything in Large + re-run failed claims through a fresh agent to verify the auditor isn't itself producing slop.
