# Harness Orchestrator

This branch holds the stable-beta rebuild of the harness plugin. The 0.6.0 engine is removed here, and the new engine is not usable yet. Parts of the old engine come back only from the reuse list in the design, each with a behaviour test shown failing first. The released 0.6.0 code stays on `main`.

## Engine entry point

The engine has one entry script: `bin/harness <verb> [args]`.
Current verbs are `version`, `help`, `selftest`, `config`, `run`, `state`, `tickets`, `session` and `flow`.
Run `bin/harness help` for the list.

## Ticket queue

`bin/harness tickets <verb>` runs the ticket queue. Run `bin/harness tickets help` for the verbs.
It has two backends: GitHub issues with one `<prefix>:<state>` label, and local files in a folder.
The five states are `ready`, `in-progress`, `blocked`, `needs-review` and `done`.
Every state change leaves exactly one state label.
Ticket titles, bodies and comments are printed only inside the untrusted fence.
A report is always a new comment; no comment is edited or deleted.
Settings: `HO_TICKETS_SOURCE` (`local` or `github`), `HO_TICKETS_REPO`, `HO_TICKETS_DIR`, `HO_STATE_PREFIX` (default `harness`), `HO_TICKET_LOCK_WAIT` and `HO_TICKET_LOCK_STALE`.

## Variable names

The new engine's own environment variables use the prefix `HO_` (Harness Orchestrator), for example `HO_HOME`.
It never reads any `HARNESS_*` variable from the 0.6.0 engine.
`bin/harness selftest` fails when a 0.6.0 variable is set or a 0.6.0 engine script is on `PATH`.

## Config and run state

- **Config lookup.** A project value beats a user value, and a user value beats the engine default. The project config is `<project>/.harness/config.json`. The user config is `$HO_USER_DIR/config.json`, by default `~/.claude/harness/config.json`. Only a missing key or `null` falls through to the next layer. Every config file must have `"schemaVersion": 2`; any other file is refused (exit 78) and the message names the file. The templates are in `templates/`.
- **Run stamp.** `bin/harness run new` creates `<project>/.harness/runs/<run-id>/` with a `run.json` stamp. Every `bin/harness state <run-dir> ...` verb checks the stamp first. A folder without a valid stamp, such as a 0.6.0 run, is refused (exit 66) and nothing in it changes.
- **Run ledger.** `ledger.jsonl` in the run folder holds decisions, owner actions, stops, resumes and marker events, one JSON line each. Lines are only appended, under a lock, and every line carries the run ID.
- **Markers.** Each marker file holds the run ID. A marker without this run's ID is ignored and logged once as foreign.
- **STOP file.** `<project>/.harness/STOP` still works. It is recorded in the ledger as the default soft stop. A new run and `state ... resume` are refused while it exists.

## Sessions

`bin/harness session <run-dir> <verb>` launches, lists and closes sessions of one run.

- **Launch.** `launch --role R --name N --cwd DIR --prompt FILE` (or `--resume SESSION-ID`), with optional `--account A` and `--model "a|b"`. Roles are `orchestrator`, `watcher`, `worker`, `validator` and `question`. The working folder must be inside the project or a worktree of it. The engine writes a launcher to `<run>/launchers/<name>.sh` and opens it in a terminal. The launcher has a clean PATH, a guarded `cd`, the role's account and a fixed session ID. It tries each model of the chain in turn when a start fails. Each attempt writes its own process ID, so the registry holds the exact process.
- **Registry.** `<run>/sessions/<name>.json` is the one record per session. It holds the run ID, the process ID, the session ID, the role, the account and the terminal handle. A session's identity is its process ID plus its session ID. The terminal handle is used only to reach the session.
- **Close.** `close <name>` refuses a record of another run (exit 66). A session whose process is gone is only marked closed. A live session gets the runtime's exit command typed into its own terminal, and the close counts only when that exact process has ended. A session still busy after `session.close_timeout_seconds` (default 90) is left open (exit 1) and never forced. Known limit: close does not clear text already sitting on the session's input line (field note B1); such a close times out and the session stays open. No process is ever matched by name.
- **Runtime.** The launch command, its arguments and the exit command come from `runtimes/<runtime.main>.json`. `runtime.main` must be set; the project template sets it.
- **Accounts.** Accounts are read from the user config only: `accounts.roles.<role>` (or `accounts.roles.default`) names an account, and `accounts.list.<name>.env_command` prints `KEY=VALUE` lines for it. A launch fails when `--account` differs from the role's account, or when the account is unknown or its command fails.
- **Terminal.** `terminal.app` is `auto`, `iterm2` or `tmux`. With tmux the harness uses its own server (`tmux -L ho-harness`) and one tmux session per run, named `ho-<run-id>`; attach with `tmux -L ho-harness attach -t ho-<run-id>`. Other settings: `session.permissions` (default `bypass`), `session.boot_timeout_seconds` (120), `session.boot_grace_seconds` (45), `session.fatal_hold_seconds` (30), `terminal.enter_delay_seconds` (2), and `models.<role>` for the default chain.

## Flow profiles

A flow profile is a ready-made flow data file. Two ship: `gsd` and `basic`. Each lives in `flows/<name>/` as `flow.json` plus one prompt file per step. Both give the default cycle (H-064): classification, discussion (grilling) only when classification finds open questions, planning, execution, code review, verification, UI check and shipping, in that order. `basic` writes every step out as a plain prompt and needs no flow system. `gsd` runs the middle steps through GSD, which must be installed; classification and shipping stay harness steps.

- `bin/harness flow list` prints the shipped flows. `flow check <flow>` checks the flow file, every step prompt and the role prompts. `flow steps <flow>` prints the ordered steps, one per line: number, id, `always` or `questions`, title.
- `bin/harness flow render <flow> <role> [--step <id>] [--set NAME VALUE]... [--file NAME PATH]...` prints a role prompt. The roles are `worker` (one step; needs `--step`) and `validator`. The role prompts are in `prompts/` and are the same for every flow.
- Placeholders have the form `@NAME@`. The engine fills `FLOW_NAME`, `FLOW_STEP_LIST`, `STEP_ID`, `STEP_TITLE` and `STEP_TEXT`. The caller sets `RUN_ID`, `TICKET_ID`, `TICKET_TEXT`, `BRANCH`, `BASE`, `WORKDIR`, `STEP_RESULT_FILE` and `VERDICT_FILE`. `TICKET_TEXT` must be the fenced text of ticket `TICKET_ID`, as `harness tickets show` or `harness tickets fence <id>` prints it; anything else is refused (exit 65). A placeholder with no value fails the render (exit 65), and nothing is printed. Values must be UTF-8 text (anything else is refused with exit 65, never changed; `render` uses `iconv` to check this). They are inserted as they are and never scanned again, so ticket text that quotes a placeholder is safe. Each value reaches jq through a temp file, so a large ticket is no problem.
- There is no default flow. A missing or broken flow stops with exit 78 and names the flow. Engine code (`bin/`, `lib/`, `prompts/`) names no flow system; such names live only in flow data.
- Selecting a flow, editing its steps and naming a step's runner come later (H-065 to H-068). `HO_FLOWS_DIR` points at another flows folder.

## Tests

Run the plugin tests from the repository root:

```bash
bash plugins/harness/tests/run.sh
```

The last line is `harness tests: PASS=<n>  FAIL=<m>`. See `tests/README.md` for how the runner isolates each test.

## Field notes for contributors

`plugins/harness/docs/FIELD-NOTES.md` records what the 0.6.0 engine did in two long unattended runs.
You do not need to read it before every change.
Read the matching section before you change one of these areas, and when you write tests for it:

- session liveness, recovery, closing sessions — section A
- sending instructions to a session — section B
- merge, validation, git operations — section C
- tickets, labels, run state files — section D
- more than one worker, heavy work, Docker — section E
- subscription limits, the limit banner, pause and resume — section F
- worker cap defaults, usage history, timeouts — section G
- any detector, probe or gate that reads a screen, a log or an exit code — section I

Each record names the requirement or design decision it relates to, or says that none fits.
A record is covered when a test fails without the fix.
