---
argument-hint: "[--small | --medium | --large | --xl] [--ask | --ask=critical | --ask=all] [--agents=N] [--focus=X] [--task=name] [--terminal=N] [--mode=research|build|review|create|validate] [/wrapped-skill] <task>"
description: "/ultra:run — multi-agent swarm with adversarial validation, structured debates, devil's advocate, and anti-AI-slop checks. Always invoked as /ultra:run (never bare /ultra). Tiers pick agent count + model. Prefix a /skill-name to wrap another skill as Phase 2."
---

Invoke the `ultra:ultra` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. The skill's SKILL.md parses tier flags, `--ask`, `--task`, `--mode`, and the optional wrapped-skill prefix, then — as the main agent — runs the phase pipeline directly, spawning the worker swarm in parallel via the `Agent` tool per `${CLAUDE_SKILL_DIR}/phases.md` + `debate-protocol.md` + `anti-slop-rules.md` + `devil-advocate.md` + `tier-config.md`. The main agent stays the orchestrator/decider; it does NOT delegate the pipeline to a single spawned sub-agent (that would collapse the swarm into sequential role-play).
