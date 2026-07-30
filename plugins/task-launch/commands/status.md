---
argument-hint: ""
description: "Read-only health check for task-launch — config presence, task source, and whether the task-source transport / transcript loader / configured launcher are available. Writes nothing."
---

Invoke the `task-launch:task-launch` skill via the Skill tool, passing `--status $ARGUMENTS`. The skill runs its `## Mode: --status` flow: reads the config, reports the configured task source, and checks availability of the task-source transport (e.g. `clkup`), the configured transcript loader (e.g. the `find-call` skill), and the configured launcher (default iTerm2), then prints a resolution table. Read-only — it writes nothing.
