---
name: ultra
description: |
  Multi-agent swarm with adversarial validation, structured debates, devil's advocate,
  and anti-AI-slop checks. Use when maximum rigor is needed: research, implementation,
  validation, creation, or any complex task requiring independent verification.
  Supports tiers (--small/--medium/--large/--xl), multi-terminal coordination,
  and wrapping other skills.
disable-model-invocation: false
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
  - Agent
  - Skill
  - AskUserQuestion
  - WebSearch
  - WebFetch
---

# /ultra — Multi-Agent Swarm with Adversarial Validation

You are the launcher for /ultra. Your job is MINIMAL: parse arguments, read supporting files, compose an orchestrator prompt, spawn ONE orchestrator agent, and display its result. Keep the main context window CLEAN.

## Step 1: Parse Arguments from $ARGUMENTS

Extract these flags (order-independent, case-insensitive):

| Flag | Values | Default |
|------|--------|---------|
| `--small` / `--medium` / `--large` / `--xl` | Tier selection | `--large` |
| `--ask` | Sync at start only | off |
| `--ask=critical` | Pause at critical decisions | off |
| `--ask=all` | Pause at every phase | off |
| `--agents=N` | Override agent count (cannot go below tier minimum) | tier default |
| `--focus=X` | Override auto-detected focus area | auto-detect |
| `--task=name` | Shared task ID for multi-terminal coordination | none |
| `--terminal=N` | Terminal instance number for parallel runs | none |
| `--resume` | Continue from last checkpoint | off |
| `--mode=X` | Override task type (research/build/review/create) | auto-detect |

**Wrapped skill detection**: If $ARGUMENTS contains a `/skill-name` (e.g., `/deep-research`), extract it as the wrapped skill. The wrapped skill replaces Phase 2 (Research).

Everything remaining after flag extraction is the **task description**.

## Step 2: Read Supporting Files

Read these files from `${CLAUDE_SKILL_DIR}`:
1. `tier-config.md` — resolve tier settings (agent counts, models, features)
2. `phases.md` — phase pipeline definition
3. If `--task` and `--terminal` flags present: `coordination.md` — multi-terminal rules
4. `debate-protocol.md` — debate rules (passed to orchestrator for Phase 7)
5. `anti-slop-rules.md` — evidence audit rules (passed to orchestrator for Phase 8)
6. `devil-advocate.md` — adversarial protocol (passed to orchestrator for Phases 5-6)

## Step 3: Handle --ask (Start Sync)

Only if `--ask` (bare, no `=value`) is present, use AskUserQuestion BEFORE spawning the orchestrator:
- Present your understanding of the task
- Show the tier configuration and agent count
- Show the detected task type and focus area
- Ask if this matches their intent

`--ask=critical` and `--ask=all` do NOT trigger this pre-flight sync — they are passed to the orchestrator for in-pipeline pauses only.

## Step 4: Check for --resume

If `--resume` is present:
- Requires `--task=<name>`. If no `--task`, warn user: "--resume requires --task=<name>" and stop.
- Check `.planning/ultra/<task>/state.json` for previous progress
- If exists, include the state in the orchestrator prompt so it resumes from last completed phase
- Also include the original tier from `state.json` to maintain consistency (don't switch tiers mid-run)
- If no state file, warn user and start fresh

## Step 5: Spawn Orchestrator

Launch ONE Agent with `model: "opus"` and `run_in_background: false`. The orchestrator prompt must include:
- The full task description
- All resolved tier settings
- All protocol files content (phases, debate, anti-slop, devil-advocate)
- Coordination rules if multi-terminal
- The --ask level for the orchestrator to respect
- Previous state if --resume
- Lessons from `~/.claude/skills/ultra/global-lessons.md` if it exists
- If wrapping a skill: instruct the orchestrator to use the `Skill` tool to invoke the wrapped skill during Phase 2, passing the scope analysis as $ARGUMENTS. The wrapped skill's output becomes Phase 2's output.

**Critical instruction in orchestrator prompt**: "Return ONLY an executive summary to the main context. All detailed findings go to .planning/ultra/<task>/ files."

**State tracking instruction**: "After completing each phase, write/update `.planning/ultra/<task>/state.json` with current progress." (See state.json format in coordination.md)

## Step 6: Display Result

When the orchestrator returns:
1. Display the executive summary (2-5 paragraphs)
2. Display the confidence breakdown:
   - Evidence Quality: X/10
   - Agent Consensus: X/10
   - Survived Devil's Advocate: X/10
   - Anti-Slop Pass: X/10
3. Display recommended next steps
4. If `--task` was provided OR tier is medium+: note the file path `.planning/ultra/<task>/summary.md`
5. For small tier without `--task`: no file path (findings were not persisted)

## Self-Improvement

After displaying results, append a 2-3 line entry to `~/.claude/skills/ultra/global-lessons.md` (create if it doesn't exist). Format: `## YYYY-MM-DD: task-name [project-name] (--tier, mode)`. Include: what tier was used, whether the pipeline was effective, any issues encountered. The `[project-name]` tag should be derived from the project directory name or git remote.

## Quick Reference

```
/ultra 'find the best caching solution for this project'
/ultra --small 'best way to implement this feature'
/ultra --xl --task=migration --terminal=1 'plan database migration strategy'
/ultra --large --focus=security 'review this authentication module'
/ultra --large /deep-research 'evaluate monitoring solutions'
/ultra --resume --task=migration
```
