---
argument-hint: "[<run-name>]"
description: "(beta) Show a Claude migration's current status read-only: the pipeline step, queue counters, gate verdicts, and the single next action to take. Use when the user types /claude-migrate:progress, or says \"how is the migration going\", \"migration status\", \"where am I in the migration\"."
---

Invoke the `claude-migrate:progress` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. `$ARGUMENTS` is the optional `<run-name>`; the skill reads `state.json` and the queue directories and prints a human-readable status block. It is read-only and never mutates state.
