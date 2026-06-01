---
argument-hint: "[<run-name>]"
description: "(beta) Start a new Claude-to-Claude migration: scaffold the run directory, ask where the source is (export folder or live old account) and how to apply it (AUTO browser or copy page only), then hand off to the controller. Use when the user types /claude-migrate:init, or says \"migrate my Claude account\", \"start a Claude migration\", \"move my chats to a new account\"."
---

Invoke the `claude-migrate:init` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. `$ARGUMENTS` is the optional `<run-name>`; the skill scaffolds `<cwd>/.planning/claude-migrate/<run>/`, runs the ultra + Node/Playwright preflight, asks G-INPUT and G-OUTPUT, copies the connector/selectors/config templates, and then hands control to the `run` skill.
