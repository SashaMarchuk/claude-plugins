---
argument-hint: "[identity | workspace]"
description: "Run the ClickUp onboarding wizard. With no sub-arg: full identity + workspace wizard. With `identity` or `workspace`: re-run just that slice."
---

Invoke the `clickup:clickup` skill via the Skill tool, passing `--onboard $ARGUMENTS`. The skill's SKILL.md defines the `--onboard [identity|workspace]` flow; identity writes `~/.claude/shared/identity.json` (shared with `/gevent`); workspace writes `~/.claude/clickup/config.json`.
