---
argument-hint: "<run-name>"
description: "(beta) Resume an interrupted Claude migration from its last checkpoint: re-read state, requeue orphaned units, re-rename seeded-but-unrenamed chats, re-poll awaited turns, re-run any gate left blocked, then hand back to the controller. Use when the user types /claude-migrate:resume, or says \"resume my migration\", \"pick up where I left off\", \"I dropped the export, continue\"."
---

Invoke the `claude-migrate:resume` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. `$ARGUMENTS` is the required `<run-name>`; the skill prints a progress dump, performs crash-safe recovery (orphan requeue, dedupe-probe on `opened` units, rename-only on `seeded` units, re-poll on `awaited_ok`, re-run blocked interactive gates), then hands control to the `run` skill.
