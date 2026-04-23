---
argument-hint: ""
description: "Switch the active ClickUp workspace. Updates `~/.claude/clickup/config.json`; re-syncs teammate active flags in shared identity.json."
---

Invoke the `clickup:clickup` skill via the Skill tool, passing `--workspace $ARGUMENTS`. The skill's SKILL.md routes to `references/modes.md#workspace` and handles the downstream teammate active-flag resync.
