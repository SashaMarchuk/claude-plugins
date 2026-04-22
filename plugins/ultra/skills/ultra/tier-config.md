# Tier Configuration

## Tier Definitions

### --small
- **Agents**: 5-7 total (core 5 + debate reuse)
- **Models**: All Sonnet
- **State files**: None (no .planning/ files unless --task is specified)
- **Pre-research**: No
- **Agent allocation**:
  - 2-3 Researchers (Sonnet) — R1, R2, R3
  - 1 Validator (Sonnet) — V1
  - 1 Devil's Advocate (Sonnet) — D1
  - Debate: simplified 1v1 + judge — D1 doubles as AG1, R1 doubles as F1, orchestrator acts as J1. No additional agents needed.
  - Anti-slop: orchestrator performs the audit directly (no separate A1 agent)
  - Synthesis: orchestrator handles directly (no S1 agent)
- **Anti-slop**: Evidence audit runs but with reduced depth (spot-check top 3 claims)
- **Execution agents** (Phase 4, if applicable): Sonnet model

### --medium
- **Agents**: 6-10 total
- **Models**: 66% Sonnet, 33% Opus
- **State files**: Optional (create .planning/ultra/<task>/ if --task flag present)
- **Pre-research**: No
- **Agent allocation**:
  - 3-5 Researchers (Sonnet) — R1 through R5
  - 1-2 Validators (Sonnet) — V1, V2
  - 2 Devil's Advocates (Opus) — D1, D2
  - 1 Judge (Opus) — J1
  - Debate: full 2v2 (Sonnet researchers argue, Opus judges)
- **Anti-slop**: Full evidence audit
- **Execution agents** (Phase 4, if applicable): Sonnet for code, Opus for architecture decisions

### --large (DEFAULT)
- **Agents**: 10-15 total
- **Models**: All Opus
- **State files**: Optional (create .planning/ultra/<task>/ if --task flag present, recommended)
- **Pre-research**: No
- **Agent allocation**:
  - 4-6 Researchers (Opus) — R1 through R6
  - 2 Validators (Opus) — V1, V2 (blind validation)
  - 2 Devil's Advocates (Opus) — D1, D2 (attack after seeing findings)
  - 2v2 Debate: 2 FOR (Opus), 2 AGAINST (Opus)
  - 1 Judge (Opus) — J1
  - 1 Anti-Slop Auditor (Opus) — A1
  - 1 Synthesizer (Opus) — S1
- **Anti-slop**: Full evidence audit + contradiction scan
- **Execution agents** (Phase 4, if applicable): Opus model

### --xl / --extralarge
- **Agents**: 15-25 total
- **Models**: All Opus
- **State files**: MANDATORY (.planning/ultra/<task>/ always created)
- **Pre-research**: YES (compass phase — see phases.md Phase 0)
- **Agent allocation**:
  - Phase 0: 3-5 Pre-Researchers (Opus) — PR1 through PR5
  - 5-8 Main Researchers (Opus) — R1 through R8
  - 3 Validators (Opus) — V1, V2, V3 (blind validation)
  - 2 Devil's Advocates (Opus) — D1, D2
  - 1 Contrarian (Opus) — C1 (runs UNCONDITIONALLY at Phase 7 start as a standing critic; if consensus trap also triggers, C1 runs a SECOND pass with the explicit contrarian prompt)
  - 2v2 Debate: 2 FOR, 2 AGAINST (all Opus)
  - 1 Judge (Opus) — J1
  - 1 Anti-Slop Auditor (Opus) — A1
  - 1 Scope Minimizer (Opus) — SM1 (argues for simpler solutions)
  - 1 External Observer (Opus) — EO1 (end-user perspective)
  - 1 Synthesizer (Opus) — S1
- **Anti-slop**: Full protocol (evidence + contradiction + cross-agent independence check)
- **Execution agents** (Phase 4, if applicable): Opus model

## --agents=N Override

When user specifies `--agents=N`:
- N must be >= tier minimum (small:3, medium:6, large:10, xl:15)
- If N < tier minimum, use tier minimum and warn
- Extra agents are distributed proportionally across roles:
  - 50% go to Researchers (more perspectives)
  - 25% go to Validators (more independent checks)
  - 25% go to Devil's Advocates (more attack angles)

## Agent Naming Convention

Every agent gets a unique ID: `{ROLE_PREFIX}{NUMBER}`

| Role | Prefix | Example |
|------|--------|---------|
| Pre-Researcher | PR | PR1, PR2 |
| Researcher | R | R1, R2, R3 |
| Validator | V | V1, V2 |
| Devil's Advocate | D | D1, D2 |
| Contrarian | C | C1 |
| Judge | J | J1 |
| Anti-Slop Auditor | A | A1 |
| Scope Minimizer | SM | SM1 |
| External Observer | EO | EO1 |
| Synthesizer | S | S1 |
| Execution Agent | EX | EX1, EX2 |
| FOR Debater | F | F1, F2 |
| AGAINST Debater | AG | AG1, AG2 |

All agent findings MUST be tagged with their ID. Example:
```
[R3] Found that Redis supports cluster mode with automatic failover...
[D1] CHALLENGE: R3's Redis recommendation ignores the 6-month licensing change...
[V2] INDEPENDENT FINDING: Confirmed Redis cluster viability, but noted memory overhead concern not raised by any researcher...
```
