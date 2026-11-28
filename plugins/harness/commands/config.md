---
description: "Configure the harness for this project and for you: flow, requirements format, autonomy and every other harness setting, and which committed config this machine uses. To prepare a repository for AI development instead, use /harness:ai-ready."
argument-hint: "[what you want to change, optional]"
---

Fit the harness to this project (H-127, H-128). Stay short: ask only what you cannot read. Use AskUserQuestion for every question, at most 4 per round, with concrete options and the recommended one first. Write in the person's agent language (`"${CLAUDE_PLUGIN_ROOT}/bin/harness" config language`; English by default). If `$ARGUMENTS` names one setting, change only that one and skip the rest.

The engine commands below all start with `"${CLAUDE_PLUGIN_ROOT}/bin/harness"`. Run them from the project's main checkout.

1. **Read what exists.** Run `config list` (the committed configs: `.harness/config.json` and `.harness/config.<name>.json`, each named for its owner) and `config status` (this machine's local selection). Read the user config (`~/.claude/harness/config.json`). Check the person's memory and installed tools for a flow system they already use (for example a GSD install, its skills or a `.planning/` folder).

2. **Committed configs exist.** Offer to use one. Show each name, its flow, its requirements format and its autonomy profile (`autonomy show` after a selection, or read `autonomy.profile`). A saved user default never accepts a committed config; only the person's yes does. On yes: `config select <name>`. That writes `.harness/local.json`, which git ignores through the clone's local exclude file only, and records the approved autonomy profile, so the first start does not stop again (D37-FLOW-8). If the person declines, go on to step 3 and build a new config.

3. **No committed config, or a new one.** Recommend the flow the person already uses, if you found one, and say whether the README lists it as tested (`flow list` shows the shipped flows; the tested list is in the plugin README). If you found more than one, name a tested one first. An untested flow is still recommended, with a plain note that it is not tested with the harness. If you found none, offer the default for one confirmation: the `gsd` flow with `openspec` requirements. The other choice is an own flow started from `basic` (`flow copy basic <new>`). Never select a flow yourself; the person makes the final choice.
   - Requirements format (`requirements.format`): `openspec` or `none`. With `openspec` and no `openspec/` folder in the project, offer to set OpenSpec up and do it only after a yes. On no: `config format none`. Ask whether grilling should use the requirements (`requirements.use_in_grilling`, default true).
   - To use the default without writing a project config: `config select --default` (add `--flow <name>` or `--format none` for another choice). Then ask whether to save the same confirmation for other projects: `config save-default` with the same flags.

4. **Walk the settings** (every setting the plugin offers; skip what the person already has and does not want to change). Write the answers into the project config (`.harness/config.json`, or `.harness/config.<owner>.json` when the person wants a config named for them) or into the user config, as the person chooses, each file with `"schemaVersion": 2`:
   - Autonomy: `autonomy.profile` — `safe` (the default; nothing leaves the machine), `gated`, `draft-pr`, `full`, or `custom` with every field in `autonomy.custom`. `autonomy list` describes them. The "always a human" paths: `autonomy.always_human_paths`.
   - Permission mode: `session.permissions` (`bypass`, `auto`, `acceptEdits`, `dontAsk`), user config only.
   - Permission prompts: `session.permission_prompts` — `off` (the default; the harness never answers and escalates) or `analyse` (a model accepts a clearly acceptable prompt once and escalates any doubt).
   - Limits: the worker cap `limits.workers` (default 1), `limits.heavy`, `limits.stages.<id>`. Offer a threshold of 90% for every usage window, and switch thresholds on only after a yes (H-110).
   - Run end: `run.standby` (true or false) and `run.on_only_human_blocked` (`wait` or `end`).
   - Runtime and terminal: `runtime.main`, `terminal.app`.
   - Agent language: `agent.language` (English by default).
   - Commands (account commands, gate commands, channels wired by a command) go in the user config only; a project config may only name their label (D37-FLOW-8).

5. **Newcomer note.** If the project config will be committed and `.harness/README.md` does not exist, offer to copy `${CLAUDE_PLUGIN_ROOT}/templates/harness-folder-README.md` there, so a newcomer learns that the harness is optional and how to set it up (design D19). Do not change the project's own README.

6. **Check and finish.** Run `config check`. If you wrote or changed a committed config, select it again with `config select <name>`, so the record of the approved profile matches what the person saw. Run `config gate`; it prints nothing on success. Tell the person which config this machine uses now, and that committing the project config lets other machines reuse it after their own short `/harness:config`.
