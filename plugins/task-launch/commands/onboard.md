---
argument-hint: ""
description: "Set up task-launch — task source, folder map, launcher, coding tool, default launch mode, and other defaults. Writes ~/.claude/task-launch/config.json."
---

Invoke the `task-launch:task-launch` skill via the Skill tool, passing `--onboard $ARGUMENTS`. The skill runs its `## Mode: --onboard` flow: it interactively builds `~/.claude/task-launch/config.json` (task source, folder map, launcher, coding tool, default launch mode — `all` or `one` — and the remaining defaults), previews the JSON, and atomic-writes on your confirm. This is the only flow that writes the whole config; the run flow may add a remembered folder or save your launch-mode default, each only on an explicit yes.
