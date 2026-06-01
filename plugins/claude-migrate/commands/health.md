---
argument-hint: "[<run-name>]"
description: "(beta) Diagnose a stuck Claude migration: detect stale locks, orphaned in-progress units, counter drift, and corrupt state, then propose repairs without applying them. Use when the user types /claude-migrate:health, or says \"the migration is stuck\", \"check the migration health\", \"why won't the run advance\"."
---

Invoke the `claude-migrate:health` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. `$ARGUMENTS` is the optional `<run-name>`; the skill inspects the run for common failure modes and prints proposed fixes. It never auto-applies a repair.
