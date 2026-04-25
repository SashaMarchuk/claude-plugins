# 2v2 Debate Protocol with Mandatory Concession Tracking

## When This Runs

Phase 7 of the /ultra pipeline. After blind validation (Phase 5) and devil's advocate attack (Phase 6).

## Debate Setup

**Topic**: The most contentious finding OR the proposed solution from Phase 3 synthesis.

**Participants**:
- **F1, F2** (FOR): Argue that the proposed solution/finding is correct
- **AG1, AG2** (AGAINST): Argue that it is wrong, incomplete, or there's a better alternative
- **J1** (Judge): Evaluates both sides, tracks concessions, delivers verdict

For small tier: simplified to 1v1 + judge (F1 vs AG1 + J1).

## Three-Round Format

### Round A: Opening Arguments

Each side presents exactly 3 points with mandatory evidence citations.

**Prompt for FOR agents (F1, F2)**:
> "You are arguing FOR the following position: [POSITION]. Present exactly 3 arguments supporting this position. Each argument MUST include an evidence citation: [FILE:path:line], [URL:source], [AGENT:ID finding], or [DATA:specific metric]. Arguments without evidence citations will be discarded."

**Prompt for AGAINST agents (AG1, AG2)**:
> "You are arguing AGAINST the following position: [POSITION]. Present exactly 3 arguments against this position or in favor of an alternative. Each argument MUST include an evidence citation. Arguments without evidence citations will be discarded."

Launch F1, F2, AG1, AG2 in PARALLEL. They must NOT see each other's arguments.

### Round B: Rebuttals with Mandatory Concessions

Each side receives the opposing side's arguments and must respond.

**MANDATORY CONCESSION RULE**: Each agent MUST use the exact phrase `"I concede [X]"` for any point where the opposing evidence is stronger than their position. Agents who refuse to concede ANY point when evidence clearly favors the opponent are flagged for intellectual dishonesty.

**Prompt for rebuttal agents**:
> "You have seen the opposing side's 3 arguments with evidence. For each argument:
> 1. If their evidence is stronger than your position on this point, you MUST write: 'I concede [their point]' followed by why.
> 2. If you can counter their evidence, present your counter-evidence with citations.
> 3. If the point is genuinely debatable, state why and what additional evidence would resolve it.
>
> Intellectual honesty is paramount. Refusing to concede when evidence is clear is itself a form of slop."

### Round C: Final Statements

Each side delivers a final statement that MUST incorporate their Round B concessions.

**Prompt**:
> "Deliver your final statement. You MUST acknowledge your Round B concessions and explain how your overall position holds despite them. If your concessions undermined your core argument, say so honestly."

## Judge Evaluation

After all three rounds, J1 receives the complete transcript and evaluates:

**Prompt for Judge (J1)**:
> "You are the judge. Review the complete 3-round debate transcript.
>
> Score each side on:
> 1. **Evidence quality** (0-10): How well-cited were the arguments?
> 2. **Intellectual honesty** (0-10): Did they concede when evidence demanded it?
> 3. **Argument survival** (0-10): How many original arguments survived rebuttal?
> 4. **Concession impact** (0-10): How damaging were the concessions to each side's core position?
>
> Deliver your verdict:
> - Which side wins and by how much (decisive / narrow / mixed)? Apply the deterministic threshold table below — do NOT pick subjectively.
> - What is the concession-adjusted conclusion?
> - Are there unresolved points that need escalation?"

### Verdict Threshold Table (MED-2, MANDATORY — deterministic, not judge-feel)

The judge MUST classify the verdict using the following numeric rule. Compute the **per-axis signed delta**: `Δ_i = score_FOR_i − score_AGAINST_i` for each of the 4 axes (Evidence quality, Intellectual honesty, Argument survival, Concession impact). Each `Δ_i ∈ [-10, +10]`. Compute the **sum delta**: `Σ = Δ_1 + Δ_2 + Δ_3 + Δ_4`, with `Σ ∈ [-40, +40]`. Compute the **sign-agreement count**: `K = number of axes where sign(Δ_i) is the same as sign(Σ)` (treat `Δ_i = 0` as agreeing with `Σ`'s sign).

| Verdict | Rule | Example |
|---|---|---|
| **decisive (FOR wins)** | `Σ ≥ +8` AND `K = 4` (all four axes lean FOR) | `Δ = (+3, +2, +2, +2)` → `Σ=+9`, `K=4` → decisive FOR |
| **decisive (AGAINST wins)** | `Σ ≤ −8` AND `K = 4` (all four axes lean AGAINST) | `Δ = (−2, −3, −2, −2)` → `Σ=−9`, `K=4` → decisive AGAINST |
| **narrow (FOR edge)** | `+1 ≤ Σ ≤ +7` OR (`Σ ≥ +8` AND `K < 4`) | `Δ = (+2, +1, +1, 0)` → `Σ=+4`, `K=4` → narrow FOR |
| **narrow (AGAINST edge)** | `−7 ≤ Σ ≤ −1` OR (`Σ ≤ −8` AND `K < 4`) | `Δ = (−2, −1, −1, 0)` → `Σ=−4` → narrow AGAINST |
| **mixed** | `Σ = 0` OR signs of `Δ_i` are split (`K ≤ 2`) regardless of `Σ` | `Δ = (+5, −4, +3, −4)` → `Σ=0`, `K=2` → mixed |

**Worked example (acceptance criterion)**: 4-axis sum `Σ = +4` (e.g. `Δ = (+2, +1, +1, 0)`) → row 3 → **narrow FOR**. The judge MUST output `narrow` for this case; outputting `decisive` or `mixed` is a protocol violation flagged by Phase 8.

**Tie rule**: if `Σ = 0` exactly, the verdict is `mixed` regardless of `K` — there is no "judge picks the side that argued better"; ties surface as mixed and feed Phase 9 as an unresolved finding requiring user adjudication when `--ask=critical` or `--ask=all`.

**Anti-slop verification**: Phase 8 (Anti-Slop Audit, `anti-slop-rules.md`) recomputes the verdict from the 4-axis scores and FAILs the audit if the judge's stated verdict disagrees with the deterministic rule. The judge cannot override the table.

## Concession Tracker

The orchestrator maintains a concession tracker:

```
CONCESSION LOG:
- F1 conceded: [point] because [evidence]
- AG2 conceded: [point] because [evidence]
- F2 refused to concede [point] despite [evidence] → FLAG: intellectual dishonesty
```

The concession log is a PRIMARY output signal — it reveals which positions actually survived scrutiny. Include it in the Phase 9 synthesis.

## Consensus Trap Detection

After the debate, if >80% of ALL agents across Phases 2-7 agree on the same conclusion:

1. Spawn Contrarian agent (C1) with this prompt:
> "Every agent in this pipeline has agreed on [CONCLUSION]. Your ONLY job is to find reasons this consensus is wrong. You MUST produce at least 3 genuine counterarguments. If you truly cannot find valid counterarguments after thorough investigation, state: 'Consensus validated — no forced dissent needed.'"

2. If C1 produces valid counterarguments, add them to the final synthesis as "Unresolved contrarian concerns."
3. If C1 validates the consensus, note it as "Consensus stress-tested and confirmed."
