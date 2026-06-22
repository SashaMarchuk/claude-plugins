---
argument-hint: "[--mode=incremental | --mode=full]"
description: "Reconcile ~/.claude/clickup/config.json lists against the active ClickUp workspace. Detects renames, adds, archived/missing lists; preserves aliases; auto-routes huge diffs to the onboard wizard."
---

Invoke the `clickup:clickup` skill via the Skill tool, passing `--reload $ARGUMENTS`. The skill's SKILL.md routes to `references/modes.md#reload`. Reads the active workspace hierarchy via `op.get_hierarchy` (the resolved transport — MCP / clickup-cli / REST — per `references/connection.md`), computes a diff against `~/.claude/clickup/config.json` `lists[]` BY `id`, snapshots current config to `~/.claude/clickup/.snapshots/<ISO>.json`, and applies changes atomically through the existing `atomic_update` helper. Refuses `--reload --auto` at parse time (mirrors `--onboard --auto`); refuses if the transport returns 0 workspaces or 0 lists when stored has > 0 (auth-scope changed — never auto-archive entire config).
