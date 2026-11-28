---
description: "Start a harness run in this project: preflight, the orchestrator session and the watch script, then every ready ticket unattended. With an unfinished last run, it resumes that run instead."
argument-hint: "[--workers N] [--standby on|off] [--ticket ID]"
---

Start (or resume) a harness run for this project: $ARGUMENTS

The engine commands below all start with `"${CLAUDE_PLUGIN_ROOT}/bin/harness"`. Run them from the project's main checkout. Write to the person in their agent language (`config language`; English by default).

1. **Start.** Run `run start $ARGUMENTS`. It does every start check itself, in this order: the newest unfinished run of this project (it resumes that run instead of starting a new one, design D32), the config gate, the flow preflight (runtimes logged in, skills installed), a new stamped run, the hooks check, the limits gate, the autonomy start check, the run's local integration branch, the orchestrator session and the watch script.
   - On success it prints `run <run-dir>` and `orchestrator <name>`. Tell the person the run folder, that the orchestrator works unattended in its own terminal, and that `/harness:status`, `/harness:stop` and `/harness:resume` control it.

2. **A start check stopped it.** Do not work around a check. Print the engine's message as it is, then:
   - exit 73 (config gate): nothing is confirmed for this project. Offer `/harness:config`; never pick a flow or a requirements format yourself.
   - exit 74 (limits gate): a usage window is over its threshold. Say when it resets, from the message.
   - exit 76 or 77 (autonomy): the profile waits for a person or does not allow the start; name the profile and the point.
   - exit 78: a config error; show the setting the message names.
   - any other exit: show the message and suggest `/harness:feedback` if it looks like a harness fault.

3. Do nothing else. The orchestrator takes tickets, launches workers and validators, merges and ships as far as the autonomy profile allows. Do not run those steps from this session.
