---
argument-hint: "[<plain-text change, e.g. 'add a skip rule for declined events'>]"
description: "Update the log-time config in natural language — add/change/remove a source, target, day rule, or output preference. Shows the diff and confirms before writing."
---

Invoke the `log-time:log-time` skill via the Skill tool, passing `--config $ARGUMENTS`. The skill reads `~/.claude/log-time/config.md`, applies the requested change to the relevant section, shows the user a before/after diff, and writes only after explicit confirmation. This (plus `--onboard`) is the only path that writes the config file.
