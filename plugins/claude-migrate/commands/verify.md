---
argument-hint: "[<run-name>]"
description: "(beta) Re-run the copy-page verification gate on demand: headless byte-exact check of every card plus a cross-model brief-equals-source audit, reconcile the apply results, and flag injection-class briefs. Use when the user types /claude-migrate:verify, or says \"verify the copy page\", \"re-run the migration verify gate\", \"check the briefs match the source\"."
---

Invoke the `claude-migrate:verify` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. `$ARGUMENTS` is the optional `<run-name>`; the skill runs `node bin/verify-copy-page.cjs`, spawns the cross-model validator subprocess (`--model "$VALIDATOR_MODEL"`, which must differ from the distill model), reconciles `apply/*.result.json`, and reports PASS/FAIL.
