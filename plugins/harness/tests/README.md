# Harness Orchestrator tests

`tests/run.sh` first re-runs itself once under `env -i`. The scrubbed run keeps only `HOME` (a fresh temp folder), `TMPDIR`, `LANG=C` and a short `PATH`: `tests/fake-bin`, the folders that hold `jq`, `git` and `bash`, and the system folders. So the tests stay green even when a 0.6.0 launcher has set its own variables or put its `bin/` on `PATH`. Each `t_*.sh` file then runs in its own process and its own temp folder, which is removed afterwards. A file that crashes or checks nothing counts as a failure. The last line is `harness tests: PASS=<n>  FAIL=<m>`.

The engine's own variables use the prefix `HO_`. Tests never call the real `claude`: `tests/fake-bin/claude` comes first on `PATH`. It appends its arguments as one tab-separated line to `$HO_FAKE_CLAUDE_LOG` (default `$HOME/fake-claude.log`), prints `$HO_FAKE_CLAUDE_STDOUT`, and exits with `$HO_FAKE_CLAUDE_EXIT` (default 0). `claude --version` prints `0.0.0 (fake claude)`.

Every test name starts with the requirement ID (for example `H-125`) or the design rule (for example `Rebuild isolation`) that it proves. Helpers are in `tests/lib.sh`: `ok <name>`, `bad <name> <why>`, `assert_eq <name> <expected> <actual>`, `assert_contains <name> <text> <part>` and `assert_exit <name> <code> <cmd...>`.
