# Phase Pipeline

All tiers run ALL phases. Agent count and depth vary by tier. Phases are STRICTLY sequential — no phase starts until the previous phase completes. Within each phase, all agents launch in PARALLEL.

## Phase 0: Pre-Research (XL ONLY)

**Purpose**: Compass, not GPS. Expand the scope of investigation without dictating steps.

**Agents**: PR1-PR5 (Opus)
**Input**: Raw task description
**Output**: Briefing document with:
- Landscape overview: what exists, what approaches are used
- Critical questions the main research must answer
- Initial hypotheses to prove or disprove
- Directions to look (NOT specific steps to take)

**Rules**:
- NEVER prescribe a methodology — only point to territories worth exploring
- NEVER rank solutions — that's for the main research to determine
- Focus on expanding awareness: "Look at X because..." not "Do X then Y then Z"
- Each PR agent explores a DIFFERENT dimension of the problem space
- Output feeds into Phase 1 as additional context, not constraints

## Phase 1: Scope Analysis

**Purpose**: Understand the task, detect type, plan the investigation.

**Agents**: Orchestrator handles this directly (no sub-agents)
**Input**: Task description + pre-research briefing (if XL)
**Output**:
- Task type: research / build / review / create / validate
- Focus area: auto-detected or from --focus flag
- Key questions to answer
- Success criteria for this /ultra run
- If wrapping a skill: how to brief that skill

**Rules**:
- If `--ask=all`, pause here and sync with user via AskUserQuestion before proceeding
- If --mode is specified, use it instead of auto-detection
- Scope analysis must complete before ANY agents launch

**Note**: Bare `--ask` (start sync) is handled by the launcher (SKILL.md Step 3), not the orchestrator. `--ask=critical` does NOT pause here.

## Phase 2: Parallel Research / Exploration

**Purpose**: Multiple independent agents explore the problem space simultaneously.

**Agents**: R1-R{N} (model per tier config)
**Input**: Task + scope analysis. Each agent gets IDENTICAL context.
**Output**: Individual findings files tagged by agent ID

**CRITICAL ISOLATION RULE**: Each researcher agent MUST receive identical context and MUST NOT see other agents' outputs. Include this in every researcher prompt:
> "You are one of N researchers working independently. You MUST NOT see or reference other agents' work. Arrive at your own conclusions based solely on your investigation."

**If wrapping a skill**: The wrapped skill (e.g., /deep-research) replaces this phase. The orchestrator uses the `Skill` tool to invoke the wrapped skill, passing the task description + scope analysis as arguments. The skill's output becomes this phase's output. Note: when wrapping a skill that has its own multi-agent pipeline (like /deep-research), that skill's internal validation is separate from /ultra's Phases 5-8 — both run independently.

**If multi-terminal**: Before starting, check `.planning/ultra/<task>/claims/` for territory already claimed by other terminals. Claim unclaimed territory via lock files. After 3-5 steps, re-verify your claims are still unique.

## Phase 3: Synthesis & Plan

**Purpose**: Merge all researcher findings into a coherent picture.

**Agents**: Orchestrator handles directly for small/medium. S1 (Synthesizer) for large/xl.

**--ask=all behavior**: If `--ask=all`, pause after synthesis and show the merged findings + proposed approach before proceeding.
**Input**: All Phase 2 findings
**Output**:
- Merged findings with convergence/divergence analysis
- Where researchers agreed (convergence = signal)
- Where researchers disagreed (divergence = the real finding)
- Proposed approach/solution/answer
- If task requires execution: detailed plan

**Rules**:
- Track which findings came from which agent (traceability)
- Divergence between isolated agents is MORE interesting than convergence
- Do NOT smooth over disagreements — surface them explicitly

## Phase 4: Execution (if applicable)

**Purpose**: Implement the plan if the task requires building/creating something.

**Agents**: Execution agents (EX prefix). Model follows tier config: small=Sonnet, medium=Sonnet, large=Opus, xl=Opus. Agent count depends on task scope — the orchestrator decides based on the plan from Phase 3.
**Input**: Phase 3 synthesis + plan
**Output**: Implemented artifacts (code, documents, configurations, etc.)

**Rules**:
- Only runs if task type is build/create/implement
- For research/review/validate tasks, this phase is a no-op (skip to Phase 5)
- If --ask=critical or --ask=all, pause before execution and show the plan via AskUserQuestion

**--ask=all behavior**: If `--ask=all`, also pause AFTER execution completes to show what was built before proceeding to validation.

## Phase 5: Blind Validation

**--ask=all behavior**: If `--ask=all`, pause before blind validation and show convergence preview.

**Purpose**: Independent agents solve the same problem WITHOUT seeing Phase 2-4 output.

**Agents**: V1-V{N} (per tier config)
**Input**: ONLY the original task description + scope analysis. NO Phase 2-4 findings.
**Output**: Independent conclusions

**CRITICAL**: This is the first half of the two-phase verification. Validators work completely blind — they cannot see what researchers found or what was built. They must arrive at their own conclusions.

**Prompt for each validator**:
> "You are an independent validator. You have ONLY the original task description. Investigate this task from scratch and reach your own conclusions. Do NOT assume any prior work has been done. Your job is to provide a completely independent perspective."

**After validators return**: Compare validator conclusions against Phase 3 synthesis:
- Where they agree: HIGH CONFIDENCE finding
- Where they disagree: REQUIRES INVESTIGATION in Phase 6

## Phase 6: Devil's Advocate Attack

**Purpose**: Actively try to break the Phase 3 synthesis using validator insights.

**Agents**: D1-D{N} (per tier config)
**Input**: Phase 3 synthesis + Phase 5 validator findings + all divergences
**Output**: Attack report — specific flaws, contradictions, blind spots

**See `devil-advocate.md` for full protocol.**

**The Four Adversarial Roles** (for large/xl tiers with enough agents):
1. **Skeptic (D1)**: Argue AGAINST the proposed solution. Must produce nightmare scenario.
2. **Advocate (D2)**: Argue FOR but challenge the weakest dimension.
3. **Scope Minimizer (SM1, xl only)**: Argue for simpler/cheaper approach.
4. **External Observer (EO1, xl only)**: End-user perspective, outside technical frame.

Each role includes the honesty escape valve:
> "If you genuinely cannot find significant flaws, say so explicitly. Forced contrarianism is itself a form of slop."

## Phase 7: 2v2 Debate

**Purpose**: Structured adversarial debate to stress-test the strongest findings.

**Agents**: F1, F2 (FOR) vs AG1, AG2 (AGAINST) + J1 (Judge)
**Input**: Phase 3 synthesis + Phase 6 attack report
**Debate topic**: The most contentious finding or the proposed solution

**--ask=all behavior**: If `--ask=all`, pause after debate and show verdict before anti-slop audit.
**--ask=critical behavior**: If `--ask=critical` AND the debate produces a DECISIVE verdict against the proposed solution, pause and ask user whether to proceed or revise.

**See `debate-protocol.md` for full 3-round protocol with mandatory concession tracking.**

**Consensus Trap Detection**: If >80% of all agents (across Phases 2-7) agree:
- Automatically spawn a Contrarian agent (C1) whose ONLY job is to find reasons the consensus is wrong
- C1 must produce at least 3 counterarguments
- If C1 cannot find genuine counterarguments, note "Consensus validated — no forced dissent needed"

## Phase 8: Anti-Slop Audit

**Purpose**: Verify that all outputs are genuine reasoning, not pattern-matching.

**Agents**: A1 (Anti-Slop Auditor)
**Input**: ALL phase outputs (2 through 7)
**Output**: Slop audit report with pass/fail per phase

**See `anti-slop-rules.md` for full evidence audit protocol.**

**Core check**: Every claim in the final synthesis must have an evidence anchor:
- `[FILE:path:line]` — cites specific code or document
- `[URL:source]` — cites external source
- `[AGENT:ID]` — cites another agent's independent finding
- `[HYPOTHESIS: no evidence located]` — explicitly marked as unverified

Unanchored confident assertions = automatic slop flag.

## Phase 9: Final Synthesis

**Purpose**: Produce the executive summary incorporating all phase outputs.

**Agents**: Orchestrator handles directly
**Input**: All phase outputs + debate verdict + anti-slop audit
**Output**:
- Executive summary (2-5 paragraphs)
- Confidence breakdown:
  - Evidence Quality: X/10
  - Agent Consensus: X/10
  - Survived Devil's Advocate: X/10
  - Anti-Slop Pass: X/10
- Dissenting opinions (if any survived debate)
- Recommended next steps
- Written to `.planning/ultra/<task>/summary.md` (for medium+ tiers, or when --task flag is present)
- For small tier without --task: summary is returned to main context only, no file written

**State tracking**: After completing this phase, update `state.json` with all phases marked complete. For single-terminal runs without `--task`, skip state tracking.

**Goal-Backward Verification**: Before finalizing, spot-check top 3 claims against actual evidence. Any "I verified X" must be confirmed against the actual artifact. Do NOT trust summaries — verify what actually exists.
