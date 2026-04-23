---
argument-hint: "[--auto] [<seed text>]"
description: "Create a ClickUp ticket. Pass --auto for a silent default-only create; otherwise interactive preview + edit + confirm."
---

Invoke the `clickup:clickup` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. This is the skill's default create flow — the skill's own flag parser handles `--auto` if present; otherwise it runs the interactive ticket-create path from its SKILL.md.
