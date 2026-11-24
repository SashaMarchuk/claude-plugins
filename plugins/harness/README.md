# Harness Orchestrator

This branch holds the stable-beta rebuild of the harness plugin. The 0.6.0 engine is removed here, and the new engine is not usable yet. Parts of the old engine come back only from the reuse list in the design, each with a behaviour test shown failing first. The released 0.6.0 code stays on `main`.

## Engine entry point

The engine has one entry script: `bin/harness <verb> [args]`.
Current verbs are `version`, `help`, `selftest`, `config`, `run`, `state` and `tickets`.
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
