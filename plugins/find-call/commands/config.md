---
argument-hint: ""
description: "Configure which tools /find-call uses per source (calendar / docs / transcripts → auto / cli / mcp / off). Interactive — writes ~/.claude/find-call/config.json."
---

Invoke the `find-call:find-call` skill via the Skill tool, passing `--config $ARGUMENTS`. The skill runs its `## Mode: --config` wizard: it reads the current preferences, asks one question per source, and persists the result via `scripts/config_io.py` (guarded atomic write). This is the only command that writes find-call state.
