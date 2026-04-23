---
argument-hint: ""
description: "Health-check both ClickUp config files (~/.claude/shared/identity.json and ~/.claude/clickup/config.json) plus MCP auth. Read-only."
---

Invoke the `clickup:clickup` skill via the Skill tool, passing `--status $ARGUMENTS`. The skill's SKILL.md routes to `references/modes.md#status` — never mutates state.
