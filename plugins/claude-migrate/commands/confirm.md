---
argument-hint: "<run-name>"
description: "(beta) Confirm what migrates and answer the interactive gates when the run is blocked: pick keep/skip chats and project grouping, naming, onboarding protocol, memories, acknowledge cost, log in / re-offer the browser accelerator, then clear the block and resume. Use when the user types /claude-migrate:confirm, or says \"confirm what migrates\", \"approve the migration\", \"answer the migration gate\"."
---

Invoke the `claude-migrate:confirm` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. `$ARGUMENTS` is the required `<run-name>`; the skill runs the AskUserQuestion round for whichever gate is blocked (the filter-gate set G-FILTER/G-NAMING/G-ONBOARD/G-MEMORIES plus G-COST, or G-AUTO-REOFFER and G-LOGIN/G-BROWSER), persists the answers to `state.decisions`, clears the block, and hands control to the `run` skill.
