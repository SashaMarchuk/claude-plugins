# ultra-analyzer: /ultra plugin dependency preflight

## Purpose
`ultra-analyzer` hard-depends on the companion `ultra` plugin. It invokes `Skill: ultra`
at two validation gates inside `skills/run/SKILL.md` (Gate 1 pre-discover, Gate 2
pre-synthesize). Without `ultra` installed, runs cannot complete.

## Primary mechanism: plugin dependency auto-install
Starting with Claude Code v2.1.110, `plugins/ultra-analyzer/.claude-plugin/plugin.json`
declares `"dependencies": ["ultra"]`. When the user runs
`/plugin install ultra-analyzer@SashaMarchuk/claude-plugins`, Claude Code resolves
this dependency automatically from the same marketplace and installs `ultra` in the
same step. See: https://code.claude.com/docs/en/plugin-dependencies

Nothing else should normally be required.

## Secondary check (this file's role)
For users on Claude Code < v2.1.110, or when the plugin is loaded ad-hoc with
`--plugin-dir` (no marketplace, no auto-install), or if a user manually uninstalled
`ultra` after the initial install, early skills MUST halt with the message below
BEFORE the user invests time editing `config.yaml` and `seeds.md`.

## Preflight detection

Check availability of the `ultra` skill using any of these signals (whichever the
caller has access to):

1. **From the skill tool harness:** Is the skill named `ultra` in the current
   session's listed skills? If yes, proceed.
2. **From the filesystem (hook or Bash context):**
   - `test -d "${CLAUDE_PLUGIN_ROOT}/../ultra/skills/run"` — NB: this relies on
     the plugin cache layout; prefer (1).
3. **From a probe invocation:** attempt `Skill: ultra ...`. If it returns
   "skill not found" or equivalent, treat as unavailable.

If `ultra` appears available → continue.
If it does NOT appear available → HALT and print the message below verbatim.
Do NOT advance any state machine. Do NOT begin long-running setup work.

## Halt message (verbatim)

> `ultra-analyzer` requires the `ultra` plugin from the same marketplace. Install
> it first:
>
> ```
> /plugin install ultra@SashaMarchuk/claude-plugins
> ```
>
> Then retry your command.
>
> If you already installed it, restart your session or run `/reload-plugins` so
> Claude Code picks it up. On Claude Code v2.1.110+, installing `ultra-analyzer`
> from the marketplace auto-installs `ultra`; older versions require manual install.

## Maintenance note
This file is the single source of truth for the dependency-preflight halt.
Skills that reference it: `skills/run/SKILL.md` (Gate 1),
`skills/init/SKILL.md` (first-touch pointer), `skills/help/SKILL.md` (first-touch
pointer). When editing the halt message, edit here; those SKILL.md files link
to this file rather than duplicating text.
