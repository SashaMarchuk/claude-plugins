---
argument-hint: ""
description: "Health-check both ClickUp config files (~/.claude/shared/identity.json and ~/.claude/clickup/config.json) plus the resolved connection transport (MCP / clickup-cli / REST). Read-only."
---

Invoke the `clickup:clickup` skill via the Skill tool, passing `--status $ARGUMENTS`. The skill's SKILL.md routes to `references/modes.md#status` — never mutates state. The output includes a ClickUp connection block (live `op.probe()` per transport, where the preferred transport resolves to, and REST-token presence — never the value).
