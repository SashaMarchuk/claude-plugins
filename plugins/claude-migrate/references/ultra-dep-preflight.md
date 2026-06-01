# claude-migrate: /ultra plugin dependency preflight

## Purpose
`claude-migrate` hard-depends on the companion `ultra` plugin. It invokes
`/ultra:run` at three machine validation gates inside `skills/run/SKILL.md`
(GATE 1 pre-split, GATE 2 verify, GATE 3 pre-apply). Without `ultra` installed,
runs cannot pass any gate and the migration cannot complete.

## Primary mechanism: plugin dependency auto-install
Starting with Claude Code v2.1.110, `plugins/claude-migrate/.claude-plugin/plugin.json`
declares `"dependencies": ["ultra"]`. When the user runs
`/plugin install claude-migrate@SashaMarchuk/claude-plugins`, Claude Code resolves
this dependency automatically from the same marketplace and installs `ultra` in the
same step. See: https://code.claude.com/docs/en/plugin-dependencies

Nothing else should normally be required.

## Secondary check (this file's role)
For users on Claude Code < v2.1.110, or when the plugin is loaded ad-hoc with
`--plugin-dir` (no marketplace, no auto-install), or if a user manually uninstalled
`ultra` after the initial install, early skills MUST halt with the message below
BEFORE the user invests time choosing a connector, editing `config.yaml`, or running
`split`. The first machine gate (GATE 1 pre-split) cannot pass without `ultra`, so a
late discovery wastes the whole `init` + `split` + `preflight` investment.

## Preflight detection

Check availability of the `ultra` skill using any of these signals (whichever the
caller has access to):

1. **From the skill tool harness:** Is a skill named `ultra` (e.g. `ultra:run`)
   in the current session's listed skills? If yes, proceed.
2. **From the filesystem (hook or Bash context):**
   - `test -d "${CLAUDE_PLUGIN_ROOT}/../ultra/skills/run"` - NB: this relies on
     the plugin cache layout; prefer (1).
3. **From a probe invocation:** attempt `Skill: ultra:run ...`. If it returns
   "skill not found" or equivalent, treat as unavailable.

If `ultra` appears available -> continue.
If it does NOT appear available -> HALT and print the message below verbatim.
Do NOT advance the state machine. Do NOT call `state.sh set current_step`. Set
`status=blocked` with `blocked_reason=ultra-missing` and stop. A re-invocation of
`init`, `run`, or `resume` after the user installs `ultra` re-runs this check and,
on success, clears the block and continues from the recorded `current_step`.

## Halt message (verbatim)

> `claude-migrate` requires the `ultra` plugin from the same marketplace. Install
> it first:
>
> ```
> /plugin install ultra@SashaMarchuk/claude-plugins
> ```
>
> Then retry your command.
>
> If you already installed it, restart your session or run `/reload-plugins` so
> Claude Code picks it up. On Claude Code v2.1.110+, installing `claude-migrate`
> from the marketplace auto-installs `ultra`; older versions require manual install.

## Maintenance note
This file is the single source of truth for the `ultra` dependency-preflight halt.
Skills that reference it: `skills/init/SKILL.md` (first-touch pointer, before any
setup work), `skills/run/SKILL.md` (GATE 1 pre-split), `skills/resume/SKILL.md`
(re-check on resume), `skills/help/SKILL.md` (first-touch pointer). When editing the
halt message, edit HERE; those SKILL.md files link to this file rather than
duplicating text.
