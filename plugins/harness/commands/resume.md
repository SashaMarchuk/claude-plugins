---
description: "Resume the last harness run of this project after a stop, a crash, a reboot or a quit terminal app: lift the stop, reopen sessions by their ID and restart the orchestrator and the watch script."
argument-hint: "[run folder, optional]"
---

Resume a harness run: $ARGUMENTS

1. Run `"${CLAUDE_PLUGIN_ROOT}/bin/harness" run resume $ARGUMENTS` from the project's main checkout. With no argument it takes the newest unfinished run of this project (`recover last`).
   It records the resume (refused while the run's STOP file exists), reopens every session whose process is gone by its recorded ID and account, makes sure the orchestrator and the watch script run, and prints one line per action.

2. If it stops:
   - the STOP file exists: tell the person its path; it must be removed first. Never remove it yourself.
   - no unfinished run: say so and offer `/harness:run`.
   - `recovery.ask_first` is set (exit 77): ask the person with AskUserQuestion whether to resume; on yes run `run resume --yes $ARGUMENTS`.

3. Report what came back: the run, the sessions reopened, the orchestrator and the watch script. `/harness:status` shows the rest.
