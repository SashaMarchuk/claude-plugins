---
argument-hint: "[--auto | --onboard [identity|workspace] | --status | --workspace | --memory [add|list|remove|clear]] [<seed text>]"
description: "Create or manage ClickUp tickets. --onboard runs identity+workspace wizard; --auto creates silently with defaults; --status health-checks both config files; --workspace switches active ClickUp workspace; --memory manages learned rules."
---

Invoke the `clickup:clickup` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. The skill's SKILL.md defines the flag precedence (onboard > status > memory > workspace > auto > default) and the full onboarding + ticket-create flow. Pre-flight reads `~/.claude/shared/identity.json` + `~/.claude/clickup/config.json`; if either is missing in `--auto` mode, HALT with a one-line fix-command hint; in interactive mode, redirect to the appropriate `--onboard` sub-wizard.
