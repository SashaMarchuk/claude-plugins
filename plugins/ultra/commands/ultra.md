---
argument-hint: "[--small | --medium | --large | --xl] [--ask | --ask=critical | --ask=all] [--agents=N] [--focus=X] [--task=name] [--terminal=N] [--resume] [--mode=research|build|review|create|validate] [/wrapped-skill] <task description>"
description: "Multi-agent swarm with adversarial validation, structured debates, devil's advocate, and anti-AI-slop checks. Tiers --small/--medium/--large/--xl pick agent count + model. --ask syncs once; --ask=critical/all pause at decision points. --task=name enables state tracking + multi-terminal coordination. --resume continues from last checkpoint. Prefix a /skill-name to wrap another skill as Phase 2."
---

Invoke the `ultra:ultra` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. The skill's SKILL.md is a minimal launcher: it parses flags, reads protocol files (phases, debate, anti-slop, devil-advocate, tier-config) from `${CLAUDE_SKILL_DIR}`, and composes an orchestrator prompt. Per this repo's global-lessons, prefer flat-swarm in the main context over delegated orchestrators if sub-agent spawning is unavailable; the launcher automatically handles both paths.
