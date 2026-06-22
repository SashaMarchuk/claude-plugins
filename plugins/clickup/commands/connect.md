---
argument-hint: "[show]"
description: "Investigate which ClickUp transports are available (MCP / clickup-cli / REST), pick which one /clickup uses, and remember the choice. Interactive — writes the connection block in ~/.claude/clickup/config.json. Never silently picks a transport."
---

Invoke the `clickup:clickup` skill via the Skill tool, passing `--connect $ARGUMENTS`. The skill's SKILL.md routes to `references/modes.md#connect`: it probes all three transports in parallel (read-only), presents the findings, asks via `AskUserQuestion` which transport to use first (plus an optional fallback order), and writes the resulting `connection` block into `~/.claude/clickup/config.json` through the existing atomic write helper. Transport choices and per-transport realization are defined in `references/connection.md`. `--connect show` is a read-only alias for the Connection section of `/clickup:status`. Refuses `--connect --auto` at parse time (mirrors `--onboard --auto`): the investigation requires an interactive choice.
