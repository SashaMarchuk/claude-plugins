---
argument-hint: "[setting] [--auto]"
description: "/interview-handoff:config — two questions on a first run, or name one setting to change just that."
---

Invoke the `interview-handoff:interview-handoff` skill via the Skill tool, passing `--config $ARGUMENTS`. The skill runs its `## Mode: config` flow, which starts at the first question every time and re-asks whether each stored value is still current. This command holds no workflow of its own.
