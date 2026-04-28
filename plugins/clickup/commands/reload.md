---
argument-hint: "[--mode=incremental | --mode=full]"
description: "Reconcile ~/.claude/clickup/config.json lists against the active ClickUp workspace. Detects renames, adds, archived/missing lists; preserves aliases; auto-routes huge diffs to the onboard wizard."
---

Invoke the `clickup:clickup` skill via the Skill tool, passing `--reload $ARGUMENTS`. The skill's SKILL.md routes to `references/modes.md#reload`. Reads the active workspace hierarchy via `mcp__clickup__clickup_get_workspace_hierarchy`, computes a diff against `~/.claude/clickup/config.json` `lists[]` BY `id`, snapshots current config to `~/.claude/clickup/.snapshots/<ISO>.json`, and applies changes atomically through the existing `atomic_update` helper. Refuses `--reload --auto` at parse time (mirrors `--onboard --auto`); refuses if MCP returns 0 workspaces or 0 lists when stored has > 0 (auth-scope changed — never auto-archive entire config).
