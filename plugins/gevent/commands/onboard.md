---
argument-hint: "[identity | calendar]"
description: "Run the gevent onboarding wizard. With no sub-arg: full identity + calendar wizard. With `identity` or `calendar`: re-run just that slice."
---

Invoke the `gevent:gevent` skill via the Skill tool, passing `--onboard $ARGUMENTS`. The skill's SKILL.md defines the `--onboard [identity|calendar]` flow; identity writes `~/.claude/shared/identity.json` (shared with `/clickup`); calendar writes `~/.claude/gevent/config.json`.
