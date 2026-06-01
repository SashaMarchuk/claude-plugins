---
argument-hint: "[<run-name>]"
description: "(beta) Advance a Claude migration by one step: the controller reads current_step, dispatches the next stage, runs the /ultra machine-gates, and blocks (never prompts) at interactive gates. Use when the user types /claude-migrate:run, or says \"continue the migration\", \"advance the run\", \"keep migrating\"."
---

Invoke the `claude-migrate:run` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. `$ARGUMENTS` is the optional `<run-name>`; the skill is the non-interactive controller that advances one step of the state machine and, when a human decision is due, sets `status=blocked` and names the `confirm` (or `resume`) command instead of asking a question itself.
