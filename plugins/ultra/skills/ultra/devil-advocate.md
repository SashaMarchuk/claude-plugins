# Devil's Advocate Protocol (Two-Phase)

## Purpose

Force genuine adversarial testing of all findings. The devil's advocate is NOT optional — it's the backbone of /ultra's independent verification guarantee.

## Two-Phase Structure

### Phase A: Blind Independent Work (Phase 5 of pipeline)

Validators work WITHOUT seeing any previous findings. They solve the same problem from scratch.

**Prompt template for each Validator (V1, V2, ...)**:
> "TASK: [original task description]
>
> RULES:
> - You have NO access to any previous agent's work
> - You MUST investigate this task independently from scratch
> - Arrive at your own conclusions based solely on your own investigation
> - Do NOT make assumptions about what others may have found
> - Document your methodology: what you looked at, what you found, what you concluded
>
> Deliver:
> 1. Your independent conclusion
> 2. Your evidence (with anchors: [FILE:...], [URL:...], etc.)
> 3. Your confidence level (1-10) and what would change it
> 4. Any concerns or risks you identified"

**After all validators return**, the orchestrator performs a CONVERGENCE ANALYSIS:
- Where validators agree with researchers (Phase 2): mark as HIGH CONFIDENCE
- Where validators disagree with researchers: mark as REQUIRES ATTACK (feeds Phase B)
- Where validators found something researchers missed: mark as BLIND SPOT
- Where validators missed something researchers found: mark as POTENTIAL OVER-RELIANCE

### Phase B: Targeted Attack (Phase 6 of pipeline)

Devil's advocates NOW see the Phase 3 synthesis AND validator findings. Their job: systematically destroy the synthesis.

**Prompt template for Devil's Advocate agents (D1, D2)**:
> "You are a devil's advocate. Your job is to BREAK the following synthesis:
>
> [Phase 3 synthesis]
>
> You also have the independent validator findings that identified these divergences:
> [Convergence analysis results]
>
> YOUR MISSION:
> 1. Attack the weakest points of the synthesis
> 2. Find logical contradictions between claims
> 3. Identify assumptions that aren't supported by evidence
> 4. Propose alternative interpretations of the same evidence
> 5. Find what was NOT investigated but should have been
>
> For each attack, provide:
> - What you're attacking and why
> - Evidence that contradicts the synthesis
> - An alternative conclusion the evidence supports
> - Severity: CRITICAL (invalidates core conclusion) / MAJOR (weakens conclusion) / MINOR (edge case)
>
> HONESTY CLAUSE (MED-5, canonical phrase — IDENTICAL across devil-advocate.md and debate-protocol.md): If, after thorough investigation, you cannot produce a genuine counter-position, you MUST emit the canonical honesty escape-valve phrase verbatim:
> 'No forced dissent — evidence does not support a contrarian position on [X].'
> Substitute `[X]` with the specific finding/synthesis/conclusion. Do NOT paraphrase the phrase itself; the orchestrator parses on the literal prefix `No forced dissent — evidence does not support a contrarian position on`. Forced contrarianism is itself a form of slop."

## The Four Adversarial Roles (Large/XL)

For large and xl tiers, assign these specific perspectives:

### 1. Skeptic (D1)
- **Stance**: AGAINST the proposed solution
- **Must produce**: Nightmare scenario (what's the worst that happens if we follow this recommendation?)
- **Must challenge**: The highest-rated dimension of the synthesis
- **Model**: Opus

### 2. Advocate (D2) — LOW-5: dual-output schema (pro + attack are SEPARATE fields)

The D2 "Advocate" role is intentionally dual-purpose: it is FOR the proposed solution (defends the strongest argument) AND simultaneously challenges the weakest dimension. To prevent the contradictory-stance ambiguity (LOW-5), D2's output MUST be a structured block with TWO separate fields — pro-output and attack-output are never collapsed into one paragraph:

```
[D2-OUTPUT-BEGIN]
pro_output:
  defended_argument: <the strongest argument D2 is FOR — verbatim from Phase 3 synthesis>
  defense_evidence: <evidence anchor — [FILE:...], [URL:...], [AGENT:...], [DATA:...] — supporting why the strongest argument holds>
attack_output:
  weakest_dimension: <the lowest-rated or least-evidenced dimension D2 is challenging>
  undermining_finding: <the one thing that could undermine the strongest argument>
  attack_evidence: <evidence anchor for the attack>
[D2-OUTPUT-END]
```

- **Stance**: FOR the proposed solution (`pro_output`) AND challenges the weakest dimension (`attack_output`) — the two roles are explicit fields, not commingled prose.
- **Must produce**: BOTH a `pro_output.defense_evidence` (cites the synthesis's strongest argument) AND an `attack_output.undermining_finding` (the one thing that could undermine it). Missing either field → the orchestrator MUST flag D2's output as `MISSING-DUAL-OUTPUT` and route it to Phase 8.
- **Must challenge**: `attack_output.weakest_dimension` is the lowest-rated or least-evidenced dimension from Phase 3.
- **Model**: Opus

### 3. Scope Minimizer (SM1 — XL only)
- **Stance**: There's a simpler/cheaper way
- **Must produce**: Minimum viable alternative that achieves 80% of the goal at 20% of the cost
- **Must challenge**: Complexity and scope creep in the synthesis
- **Model**: Opus

### 4. External Observer (EO1 — XL only)
- **Stance**: End-user/customer/non-technical perspective
- **Must produce**: How this looks from outside the technical frame
- **Must challenge**: Whether the solution actually solves the USER's problem, not just the TECHNICAL problem
- **Model**: Opus

## Attack Report Format

```
DEVIL'S ADVOCATE REPORT
========================

Convergence Analysis:
  HIGH CONFIDENCE (validators + researchers agree): [list]
  REQUIRES INVESTIGATION (validators disagree): [list]
  BLIND SPOTS (validators found, researchers missed): [list]
  POTENTIAL OVER-RELIANCE (researchers found, validators missed): [list]

Attacks:
  CRITICAL:
    - [D1] [description] — Evidence: [anchor] — Alternative: [what the evidence actually shows]
  MAJOR:
    - [D2] [description] — Evidence: [anchor] — Alternative: [...]
  MINOR:
    - [SM1] [description] — Simpler alternative: [...]

Survived Scrutiny:
  - [list of synthesis points that withstood all attacks]

Honesty Declarations (canonical phrase per HONESTY CLAUSE above — MED-5):
  - [D1]: "No forced dissent — evidence does not support a contrarian position on [X]." / [D2]: "Genuine flaw found in [Y]"
```

## Feeding Into Debate (Phase 7)

The attack report feeds directly into the 2v2 debate:
- CRITICAL attacks become the debate topic
- FOR side must defend against the attacks
- AGAINST side uses the attacks as ammunition
- Judge evaluates whether attacks were adequately addressed
