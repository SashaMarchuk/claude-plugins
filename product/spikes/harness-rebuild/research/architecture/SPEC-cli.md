# SPEC-cli — command surface and operator experience

**Plugin:** `orchestrator` (renames `harness`, N1 [118]).
**Date:** 2026-09-19. **Status:** implementable specification. An implementer should be able to build
every command below without asking a question; every place where that was not possible is in §12.

**Authority, in this order.** `round-1/ANALYSIS-01.md` and `round-1/TRANSCRIPT-01.md` are the source
of truth for what the owner wants. `<baseline-marketplace>` (`requirements/OWNER-DECISIONS.md`,
`docs/NAMING.md`, `docs/MARKETPLACE-RULES.md`, `docs/config-levels.md`) is the source of truth for
how a plugin in his marketplace is shaped. The three judgments
(`JUDGE-cost.md`, `JUDGE-fidelity.md`, `JUDGE-survival.md`) decide which of the four designs this
builds on. Nothing below replaces a decision of his; where a decision is uncomfortable or impossible
as stated, §11 names the part and the price.

**Evidence tags.** **VERIFIED** — executed on this machine today (2026-09-19), or read in a primary
source on this machine today. **CLAIMED** — a document or vendor page asserts it and I did not run it.
**INFERRED** — my reasoning from the above; an estimate, not a fact, stated so it can be rejected.

**Every default in this document is `DEFAULT-PROPOSED`** with a one-line rationale, because the owner
stated almost none of them. §10 is the single register; nothing outside §10 may invent a default at
run time (adopting `ARCH-adapters` §17's contract rule, per `JUDGE-fidelity` G6).

---

## 0. Which design this builds on, and where the judges disagree

| Judge | Winner | Score |
|---|---|---|
| `JUDGE-cost` | `ARCH-minimal` | 9 / 10 |
| `JUDGE-fidelity` | `ARCH-minimal` | 8 / 10 |
| `JUDGE-survival` | `ARCH-operability` | 8 / 10 (`ARCH-minimal` last, 5 / 10) |

**Base: `ARCH-minimal`,** two judges of three, and both of the two that measured fidelity to his
words and cost to build. **The operator surface is grafted wholesale from `ARCH-operability`,**
because the operator surface is the one thing that design was aimed at and the one axis it won.

Where the judges disagree and I had to choose:

| Disagreement | Followed | Why |
|---|---|---|
| Three stop commands (`ARCH-minimal` §9) vs one `stop --hard\|--soft\|--custom` (`ARCH-operability` §1.1) | **minimal — three commands** | He named three verbs out loud, twice ([520], [524]). `NAMING.md` R3 permits verbs outside the baseline and no check fails them. The tension is recorded in §11.1 and the question is put to him in §12 Q1 |
| Exit code `2`: "ambiguous run address" (minimal §12) vs "status is stale" (operability §1.1) | **minimal — `2` is ambiguous** | Run addressing is cross-command; staleness belongs to one command. Staleness gets its own code `5` (§2.5) |
| `report.md`, one file (minimal §12) vs three morning files (operability §14.3) | **operability's content in minimal's place** | Two files plus one machine patch, all in the run directory under `$HOME`, never in the checkout (§6) |
| `doctor.enabled: false` (minimal §13) vs "shipping it off reopens a whole failure class" (`JUDGE-survival` §4) | **neither verbatim — `auto`** | `auto` turns the doctor on only when preflight proves a second, distinct account. Closes the class without inventing an account he never nominated |
| `tuning.patch` applied automatically (nowhere) vs never (cost G10) | **never auto-applied** | A system that retunes itself overnight is one he cannot predict. `config --apply-tuning` is the only path (§6.3) |

Unanimous grafts this document implements: `control.ack.json` (cost G4, fidelity G9), the detector
scorecard with `unproven ≠ clean` (cost G10), `mono` beside `at` on every record and the sleep fence
(survival G3), proof age as a dispatch gate (survival G4), `capacity.reserve_pct: 0` shipped **with
the question printed** (survival G12).

---

## 1. Package layout, and the one thing that is not a slash command

### 1.1 Files

```
plugins/orchestrator/
  .claude-plugin/plugin.json
  commands/
    config.md        run.md          status.md
    stop-hard.md     stop-soft.md    stop-custom.md
    resume.md        add.md          ask.md
    report.md        sync.md         remove.md
  skills/orchestrator/SKILL.md          # user-invocable: false  (NAMING R4)
  bin/
    orc.sh                              # the single entry point; verb dispatch
    orc-lib.sh                          # arg parsing, addressing, exit codes, output helpers
    orc-status.sh   orc-ctl.sh   orc-add.sh   orc-ask.sh
    orc-report.sh   orc-verify.sh orc-preflight.sh
    orc-run.sh      orc-lane.sh  orc-lock.py    # the supervisor and its lock (not commands)
  channels/<kind>/{meta.json,verify.sh,send.sh,receipt.sh}   # §7
  adapters/<platform>/…                                      # ARCH-minimal §7.1, out of scope here
  config/recommended.json               # advisory only; supplies no value (OWNER-DECISIONS 3.8)
  tests/
```

`plugin.json` `"command"` field is `` `/orchestrator:run` `` (NAMING R7).

### 1.2 The honest correction about "zero model tokens"

`ARCH-minimal` §12 and `ARCH-operability` §1.1 both state that `/orchestrator:status` costs zero
model tokens. **As written, that is impossible.** A Claude Code slash command is a prompt template:
invoking it starts a model turn by construction, whatever the body says. What the two designs are
really asserting — and what is achievable — is that *no agent is dispatched and no reasoning happens*;
the turn is one Bash call and a verbatim relay.

So the surface is two layers, and the spec is explicit about which claim belongs to which:

| Layer | Invocation | Model cost |
|---|---|---|
| **The script** (canonical) | `bash "$CLAUDE_PLUGIN_ROOT/bin/orc.sh" status` , or the shim `orchestrator status` | **zero.** VERIFIED-able by a test that runs it with no model in the process tree |
| **The slash command** (convenience) | `/orchestrator:status` | **exactly one turn**, no agent dispatch, no tool loop |

He described the script layer himself: «я можу запустити окремий термінал, прописати orchestrator
двокрапка статус» [508]. A separate terminal is not a Claude session. **`config` therefore offers,
once, to install a shim** at `shim.path` so `orchestrator status` works in any terminal:

```sh
#!/bin/sh
exec bash "<resolved plugin root>/bin/orc.sh" "$@"
```

`DEFAULT-PROPOSED shim.path: ~/.local/bin/orchestrator` — the conventional user bin directory, no
sudo, no PATH edit if it is already there; `config` prints the one `export PATH` line if it is not.
`DEFAULT-PROPOSED shim.install: ask_once` (`ask_once | always | never`) — writing an executable onto
his PATH without asking is not something a plugin may do.

### 1.3 The skill/command split, and one named departure

`NAMING.md` R6 and MR-9: the command file delegates to the backing skill and passes `$ARGUMENTS`
verbatim. That is right for every command whose behaviour is a workflow. It is wrong for the
commands whose whole point is that nothing thinks.

**The rule this spec adopts:**

- A command whose body needs judgement (`config`, `run`, `resume`, `add --grill`, `report --explain`)
  **delegates to `orchestrator:orchestrator`** with `$ARGUMENTS` verbatim. Standard R6 shape.
- A command whose body is a fixed read or a fixed write (`status`, `stop-hard`, `stop-soft`,
  `stop-custom`, `ask`, `report`, `sync --check`, `add` without `--grill`) **runs one Bash call and
  prints its output verbatim.** It names no skill and dispatches no agent.

This is a deliberate, recorded departure from R6, permitted by OWNER-DECISIONS 6.4 and 7.5 (the
baseline is a recommendation; departures are built and recorded in the PR for the reviewer). The
reason is a VERIFIED regression in the plugin this replaces: `plugins/harness/commands/status.md`
reads *"Invoke the `harness:harness` skill via the Skill tool, passing `--status $ARGUMENTS`"*, while
`harness-run.sh do_status --json` underneath it is pure bash and `jq`. Ten status checks in a night
cost ten skill dispatches. Д11 [508] is the owner saying the opposite.

**Test CMD-1 (build-failing):** no file under `commands/` in the zero-work list above may contain the
strings `Skill tool`, `Agent`, `Task`, or `subagent`. **Test CMD-2:** `bin/orc.sh status` exits 0 or a
code from §2.5 when run under `env -i` with only `PATH`, `HOME` and `ORCH_RUN` set (FIELD-NOTES §12.4:
detached scripts inherit no environment at all).

Worked example, `commands/status.md`:

```markdown
---
description: "/orchestrator:status — the run's state, from the file the supervisor writes. Reads only; never starts, stops or changes anything."
argument-hint: "[--run <id>] [--json] [--lanes] [--why <lane>] [--proofs] [--cost] [--ack]"
allowed-tools:
  - Bash
---

Run exactly this, once, and print its stdout verbatim with no commentary, no summary and no
interpretation. Do not read any other file. Do not call any other tool.

    bash "$CLAUDE_PLUGIN_ROOT/bin/orc.sh" status $ARGUMENTS

If the command exits non-zero, print its stderr verbatim and say nothing else.
```

Worked example, `commands/config.md`:

```markdown
---
description: "/orchestrator:config — set up or change the orchestrator's settings, and prove the things it will need tonight actually work."
argument-hint: "[--verify [--only <proof>]] [--apply-tuning [<run-id>]] [--show] [--where]"
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
---

Invoke the `orchestrator:orchestrator` skill via the Skill tool, passing `--config $ARGUMENTS`
through verbatim. The skill carries the full workflow; this command is just the clean
`/orchestrator:config` entry point.
```

---

## 2. The grammar every command shares

### 2.1 The verbs, and their conformance to the the company baseline

`NAMING.md` R3: the lifecycle verbs `config`, `status`, `sync`, `remove`, `resume` are the recommended
baseline, not a closed set; a verb outside it fails no check; what MR-17 forbids is minting a synonym
for a verb already in the baseline.

| Command | Baseline? | MR-17 synonym check | Model | Safe while a run is live? |
|---|---|---|---|---|
| `/orchestrator:config` | **yes** (MR-13, verb fixed) | — | skill | **SAFE-WITH-EFFECT** — §4.1 |
| `/orchestrator:run` | **yes** (NAMING R2) | — | skill, once | **REFUSED**, exit 73 |
| `/orchestrator:status` | **yes** (MR-17) | `doctor` is an alias, never shipped as a name | script | **SAFE** (read-only) |
| `/orchestrator:stop-hard` | no | not a synonym of any baseline verb | script | **SAFE** — this is its purpose |
| `/orchestrator:stop-soft` | no | as above | script | **SAFE** |
| `/orchestrator:stop-custom` | no | as above | script (the *supervisor* may spend one turn) | **SAFE** |
| `/orchestrator:resume` | **yes** (MR-17) | — | skill, once | **REFUSED**, exit 73 |
| `/orchestrator:add` | no | not a synonym | script (`--grill` → skill) | **SAFE** |
| `/orchestrator:ask` | no | not a synonym | script | **SAFE** |
| `/orchestrator:report` | no | **not** a synonym of `status`: `status` is live state and writes nothing; `report` renders an artifact for an ended run | script (`--explain` → skill) | **SAFE** for a finished run; **REFUSED** for a live one unless `--partial` |
| `/orchestrator:sync` | **yes** (MR-17) | — | skill | **REFUSED**, exit 73, unless `--force` |
| `/orchestrator:remove` | **yes** (MR-17) | `clean` is an alias, never a name | skill | **REFUSED**, exit 73 |

Deliberately **not** shipped: `init`, `onboard`, `setup`, `doctor`, `reload`, `clean`, `pause`, `stop`.
`onboard`/`setup` are natural-language aliases of `config` (ADR 0001); the first run of `config` **is**
the wizard (MR-14). `doctor`/`reload`/`clean` are aliases of `status`/`sync`/`remove`. `pause` is not a
separate command: it is `stop-soft --pause` (§3.6). A bare `stop` is not shipped, because shipping it
alongside `stop-hard`/`stop-soft` would be exactly the synonym MR-17 forbids. **Migration note:** the
previous plugin's `/harness:init` and `/harness:onboard` both map to `/orchestrator:config`;
`/harness:stop` maps to `/orchestrator:stop-soft`.

### 2.2 Argument grammar

```
orchestrator <verb> [<positional>] [--flag[=value] …]
```

- Long flags only. No single-letter flags except `-h` (`--help`) and `-` (stdin, `add` only). Rationale:
  a one-letter flag typed at 03:00 into the wrong verb is the cheapest way to do the wrong thing.
- `--flag value` and `--flag=value` are both accepted. `--no-<flag>` negates any boolean flag.
- `--` ends flag parsing; everything after it is positional.
- An unknown flag is **exit 64**, never ignored. The message names the flag and lists the verb's flags.
- A flag that is valid for another verb produces exit 64 with the line
  `--why is a flag of "status", not of "stop-hard"`.

**Global flags, accepted by every verb:**

| Flag | Type | Meaning |
|---|---|---|
| `--run <id>` | string | address a specific run (§2.4) |
| `--project <path>` | path | resolve the run from this project instead of cwd |
| `--json` | bool | one JSON document on stdout, nothing else; diagnostics to stderr |
| `--quiet` | bool | print nothing on success; the exit code is the whole answer |
| `--no-color` | bool | never emit ANSI |
| `--help` / `-h` | bool | usage for this verb, exit 0 |
| `--version` | bool | `orchestrator <plugin version> · schema <n>`, exit 0 |

`NO_COLOR` in the environment implies `--no-color`. Colour is emitted only when stdout is a tty **and**
`NO_COLOR` is unset **and** `--no-color` is absent.

**Environment:** `ORCH_RUN` (a run id, the fallback for `--run`), `ORCH_HOME`
(DEFAULT-PROPOSED `~/.orchestrator`, overridable so a test can run against a scratch tree),
`CLAUDE_CONFIG_DIR` (read by the resolver only, `docs/config-levels.md` §2). **No other environment
variable changes behaviour**, and no teardown or destructive argument is ever read from the
environment (survival G14; FIELD-NOTES §11.5 — a `docker compose down -v` with `COMPOSE_PROJECT_NAME`
absent destroyed the owner's own stack).

### 2.3 The output contract (Д11)

Д11 [508], corrected by him at [511]/[512] from «нічого не виводити» to «мінімальна кількість аутпуту
і стокінгів». Seven rules, each testable:

- **OUT-1 — during a run, nothing.** After `run` detaches, no orchestrator process holds a tty; every
  process's stdout and stderr go to files under the run directory. **Test OUT-1 (build-failing):** a
  bare `echo` or `printf` writing to fd 1 outside the `out()` / `log_*` helpers in `bin/orc-run.sh`,
  `bin/orc-lane.sh` fails the build.
- **OUT-2 — a ceiling per command, on success.** `run`: 1 line. `stop-*`: 1 line. `add`: 1 line.
  `ask --answer`: 1 line. `sync --check`: the diff, capped at `output.max_lines`. `status`: the render
  (§5.2). `config`: the wizard, which he asked for. Everything else: 0.
- **OUT-3 — `--json` is exclusive.** Exactly one JSON document on stdout, `\n`-terminated. Every
  human line, warning and error goes to stderr. A command that cannot produce its JSON prints
  `{"schema":1,"ok":false,"error":{"code":<exit>,"message":"…"}}` and exits with that code.
- **OUT-4 — `--quiet` prints nothing on success.** Errors still go to stderr.
- **OUT-5 — every error is one line on stderr**, and it names the run id (or `no run`), what failed,
  and the next command to run. Worked example:
  `orchestrator: control entry c-0012 written but not acknowledged in 90s — run: <work-project>-20260919-224100Z — next: orchestrator status --ack`
- **OUT-6 — no verdict words the file cannot support.** No command prints `healthy`, `ok`, `fine` or
  `all good` about a run. `status.json` has no `healthy` field (`ARCH-minimal` §2.3) because the
  previous generation computed `healthy=false` from an attention file its own loop truncated every
  cycle (FIELD-NOTES §2.1, VERIFIED) and would have printed `healthy: true` through 85 minutes of a
  loop whose log line read `NO ONE IS BEING TOLD`. The render lists facts; the owner reads the list.
- **OUT-7 — no secret is ever printed.** Any resolved value whose key path matches
  `secrets.redact_keys` renders as `••••` plus the pointer it came from (an env var name or a file
  path). `DEFAULT-PROPOSED secrets.redact_keys: ["*token*","*secret*","*password*","*api_key*","*.key"]`
  — glob match on the dotted key path, case-insensitive, because MR-23 stores secrets as pointers and
  a pointer printed is harmless while a value printed is not.
- **OUT-8 — `unknown` is printed as `unknown`, never as `0`.** A missing capacity reading is
  `kind:"unknown"` with a reason. `agent-deck`'s rule: *a wrong token number is worse than no token
  number* (LANDSCAPE §4).

`DEFAULT-PROPOSED output.verbosity: normal` (`quiet | normal`) — his Д11 [512] asks for minimal output;
`normal` is already about twelve lines and `quiet` is available per invocation.
`DEFAULT-PROPOSED output.max_lines: 40` — a status render that scrolls is one he stops reading.

### 2.4 Run addressing — the algorithm

Every verb resolves a run before it does anything. Numbered, deterministic, no model.

1. If `--run <id>` is given, use it. Go to 6.
2. If `$ORCH_RUN` is set and non-empty, use it. Go to 6.
3. Resolve the project root:
   a. `base = --project` if given, else `$PWD`.
   b. `common = git -C "$base" rev-parse --git-common-dir 2>/dev/null`. **VERIFIED today on git
      2.33.0:** from the toplevel this returns the *relative* string `.git`, and from inside a linked
      worktree it returns the **main** repository's git dir — which is what makes running `status`
      from a lane worktree at 04:00 resolve to the right run. Because it can be relative, resolve it:
      `common_abs = (cd "$base" && cd "$common" && pwd -P)`.
   c. `project_root = dirname(common_abs)`, then `pwd -P` it. If git is absent or `$base` is not a
      repository, `project_root = (cd "$base" && pwd -P)`.
4. Read `$ORCH_HOME/runs/index.tsv`. Select rows whose column 2 equals `project_root` **and** whose
   column 5 (state) is in `{starting, running, draining, paused, stopping}`.
5. Zero rows → widen to any state, newest first, and take the newest. Still zero → **exit 4**
   (`no run for /path/to/project`). More than one row in step 4's live set → print one line per
   candidate (`id`, `state`, `started`, `run_dir`) and **exit 2**.
6. `run_dir = $ORCH_HOME/runs/<id>`. If it does not exist → **exit 4**. If `status.json` is unreadable
   or its `schema` is greater than this build's → **exit 70** naming both numbers.

`index.tsv` is tab-separated, one row per run, appended under the same lock as `control.json`
(§3.4), columns: `run_id · project_root · run_dir · created_at · state · pid`. A row's `state` is
rewritten in place by the supervisor only; every other writer appends.

### 2.5 Exit codes — one table, for every command

No command exits with a code outside this table. **Test EXIT-1 (build-failing):** every `exit`
literal in `bin/` is one of these.

| Code | Name | Meaning |
|---|---|---|
| **0** | OK | it worked |
| **1** | ANSWER_NEGATIVE | it worked, and the answer is a named negative: `status` — a human is needed; `ask` — nothing is open; `sync --check` — nothing to reconcile |
| **2** | AMBIGUOUS | more than one run matches the address; the candidates were printed |
| **3** | REJECTED | the supervisor read the entry and refused it; the reason is in `control.ack.json.rejected[]` |
| **4** | NO_RUN | no run matches the address |
| **5** | STALE | `status.json` is older than `status.stale_after_ticks × tick.interval_seconds`. The render was still printed |
| **6** | WRONG_PHASE | the run exists but its phase does not accept this command (e.g. `stop-soft` on a `finished` run) |
| **8** | UNACKED | written to `control.json`, not acknowledged within `stop.ack_timeout_seconds` |
| **64** | USAGE | bad arguments (`EX_USAGE`) |
| **69** | UNAVAILABLE | preflight refused, or a required proof failed (`EX_UNAVAILABLE`) |
| **70** | INTERNAL | a schema or invariant this build cannot honour (`EX_SOFTWARE`) |
| **73** | LOCKED | the project lock is held by a live run (`EX_CANTCREAT`) |
| **75** | TEMPFAIL | refused for now; the evidence is named in the journal (`EX_TEMPFAIL`) |
| **77** | NOPERM | refused by a red line or by the permission posture (`EX_NOPERM`) |
| **78** | CONFIG | a configuration error; the key and the file are named (`EX_CONFIG`) |

Exit `1` is deliberately *not* a general error code. A shell user's `cmd || handle` idiom must not
treat "a human is needed" as a crash, and must not treat a crash as "a human is needed"; separating
them is the whole value of the table.

### 2.6 The lock, and why it is not `flock`

**VERIFIED today on this machine: there is no `flock` binary** (`command -v flock` → not found; macOS
ships none). `ARCH-minimal` names `orch-lock.py`; this spec pins it.

- Lock path: `$ORCH_HOME/locks/<sha1(project_root)>.lock`. **VERIFIED:**
  `printf '%s' /Users/sasha-marchuk/Work/claude-plugins | shasum -a 1` →
  `5439fbb6cc15e8e305fca9ec286be30474066936`. No trailing newline in the input; no trailing slash on
  the path.
- Primitive: `bin/orc-lock.py`, `python3` + `fcntl.flock(LOCK_EX|LOCK_NB)`. **VERIFIED: `python3` is
  present (3.9.6)** and `fcntl` is in its standard library. The lock file's body is
  `{"pid":…,"pid_started_at":…,"boot_id":…,"run_id":…,"at":…}`, rewritten by the holder each tick.
- The lock is keyed on the **project**, not the run (`ARCH-minimal` §10.4), which is what makes the
  single-orchestrator invariant R1-10 [300] («якщо раптом одночасно два якісь оркестратори працюють,
  то це не окей») checkable by one non-blocking acquire.
- `status --probe` attempts a **non-blocking** acquire and releases immediately. Succeeding means no
  supervisor is alive; it never relaunches anything and never writes.
- Every other command that must not race a writer (`stop-*`, `add`, `ask --answer`, `sync`) takes
  `control.lock` (a second, finer lock in the run directory), never the project lock.

`DEFAULT-PROPOSED lock.acquire_timeout_seconds: 10` — long enough to outlast one atomic rename, short
enough that a stuck command at 03:00 fails instead of hanging.

---

## 3. The commands, one by one

### 3.1 `/orchestrator:config`

**Purpose.** MR-12 to MR-15: re-runnable management of every setting, and the wizard on first run.
Also the only place the **proofs** (§7.3, §3.2) can be run on demand.

**Arguments**

| Flag | Type | Default | Meaning |
|---|---|---|---|
| *(none)* | — | — | the wizard: re-ask every setting already present (OWNER-DECISIONS 6.2), ask what is missing |
| `--show` | bool | false | print the resolved config with each key's winning slot; writes nothing |
| `--where` | bool | false | print the six slot paths and which exist; writes nothing |
| `--verify` | bool | false | run the proof table (§3.2 step 3) and write `proofs.json`; writes no config |
| `--only <proof>` | string | — | with `--verify`, run one proof by name |
| `--apply-tuning [<run-id>]` | string | last run | show `tuning.patch.json` as a diff and, on confirmation, write it |
| `--set <key>=<value>` | repeatable | — | write one key non-interactively to `scope`'s file |
| `--scope <s>` | enum | `user-plugin` | which of the six slots a write lands in: `project-shared \| project-plugin \| user-shared \| user-plugin \| local-shared \| local-plugin` |
| `--unset <key>` | repeatable | — | remove a key from `scope`'s file |

**Where a write lands.** `docs/config-levels.md` §2 is the canonical path list; this spec links to it
and does not copy it. The mapping from `--scope` to slot is: `project-shared`→1, `project-plugin`→2,
`user-shared`→3, `user-plugin`→4, `local-shared`→5, `local-plugin`→6. `<plugin>` is `orchestrator`, so
the per-plugin files are `./.claude/shared/plugins/orchestrator.json`,
`<config-root>/shared/plugins/orchestrator.json` and their `.local` counterparts.
`DEFAULT-PROPOSED config.default_scope: user-plugin` — slot 4 is one person's settings on one machine
for this one plugin, which is what almost every answer in this interview is; it is above the
committed band (precedence §4) so it never fights a project's file, and it is not gitignored-personal,
so `config --show` on another project still finds it.

**Shared-surface rule (MR-13).** A value the wizard collects that belongs to the *shared cross-plugin*
surface — `connectors.*` (the board, the notification transport, the questions channel) and
`teammates` — is written to the **shared** file at the same band (slot 3 or 1), never to the plugin's
own file. Everything else goes to the plugin file. The wizard states which file each answer is going
to, before it writes.

**Headless (MR-15).** Detect the run model by explicit signals in order — a positive interactive
signal; `--yes` / `--headless` / `claude -p` / `--non-interactive`; a scheduler, cron or hook context
— **never from a bare TTY probe**, and on ambiguity fail closed to non-interactive. Non-interactive
`config` with no `--set`/`--unset`/`--show`/`--where`/`--verify` prints exactly one line —
`config needs an interactive session — run /orchestrator:config interactively` — and exits **0**. It
is a no-op, not a failure. With `--set`/`--unset` it writes and exits 0; with `--verify` it verifies
and exits 0 or 69.

**Safe while a run is live: SAFE-WITH-EFFECT.** Writes land in the six files, and the supervisor picks
them up on the next tick by the class table in §4.1. `config` prints one line per changed key naming
its class — `live`, `boundary` or `frozen` — and for a `frozen` key it prints the refusal in advance:
`process.kind is frozen for run <work-project>-20260919-224100Z — it takes effect on the next run`. It
still writes the file; refusing the write would mean the owner cannot prepare tomorrow's config while
tonight runs.

**Exit codes.** 0 · 64 usage · 69 a required proof failed under `--verify` · 78 a value is invalid for
its key (the key, the value and the file are named).

**Worked example**

```
$ orchestrator config --verify --only channel
channel.telegram-main    credential   proven     getMe → bot id 7712… (11ms)
channel.telegram-main    delivery     proven     message_id 41822 at 14:05:11Z
channel.phone-oncall     credential   proven     test_command exit 0 (2.1s)
channel.phone-oncall     delivery     UNPROVABLE no receipt: meta.json declares receipt=false
3 proofs run · 2 proven · 1 unprovable · written ~/.orchestrator/proofs/<project-sha>.json
```

### 3.2 `/orchestrator:run`

**Purpose.** Preflight, then detach. One line, then silence for the rest of the night.

**Arguments**

| Flag | Type | Default | Meaning |
|---|---|---|---|
| `--mode <m>` | enum | from config | `controlled \| autonomous` for this run only (R1-14 [075]) |
| `--set <key>=<value>` | repeatable | — | run-scope override, captured to `config.run.json`, never written to a config file (§4.2) |
| `--max-lanes <n>` | int | from config | shorthand for `--set concurrency.max_lanes=<n>` |
| `--only <ticket>` | repeatable | — | restrict the claimable set to these ids |
| `--dry-run` | bool | false | run preflight, print the plan and the proof table, start nothing, exit 0 or 69 |
| `--allow-shared-account` | bool | false | proceed although two roles the config separates resolve to one account identity |
| `--allow-readonly-board` | bool | false | proceed although the board proved read but not write |
| `--force-proofs` | bool | false | re-run every proof even if `proofs.json` is fresh |

**Algorithm**

1. Resolve config (six slots, mandatory read, OWNER-DECISIONS 5.1). Apply `--set` into
   `config.run.json`. Validate every key against the register in §10; an unknown key is **exit 78**,
   never ignored, and an `x-` prefixed key is ignored silently (the marketplace's escape hatch).
2. Acquire the project lock non-blockingly. Held → print the holding run id and pid, **exit 73**.
3. Run the proof table. A proof whose recorded result in
   `$ORCH_HOME/proofs/<sha1(project_root)>.json` is younger than `proofs.max_age_hours` is reused;
   everything else is re-run. `DEFAULT-PROPOSED proofs.max_age_hours: 24` (survival G4) — a platform
   that auto-updated since yesterday is the most under-rated overnight killer (ADAPTER-CONTRACT §6.8),
   and a day is short enough to catch it and long enough not to re-send a notification every evening.
   The table is `ARCH-operability` §1.4's, unchanged; the refusals that matter to this spec are:
   - two roles the config separates resolve to **one account identity** → refuse 69 unless
     `--allow-shared-account`. **C4-A1: two profiles can be the same
     account.** "The switch worked" and "these roles are on separate quota pools" are
     different claims, and only the second one matters.
   - the notification channel does not **deliver** → refuse 69 if `notify.required`. A credential
     check alone is refused as proof (§7.3).
   - the board proves **read** but not **write** → refuse 69 unless `--allow-readonly-board`.
   - `RULES.md` unreadable → refuse 69. R1-15 [357] makes reading it «в обов'язковому порядку»; the
     undefined failure branch (C8-A5) is defined here as *refuse*, the fail-closed side.
4. Create `$ORCH_HOME/runs/<run-id>/`, write `config.resolved.json`, `config.run.json`,
   `config.sources.json`, `plan.json` (including `weakened[]` and `denied[]`, each row carrying the
   owner item it weakens — fidelity G5), an empty `control.json`, and append the row to `index.tsv`.
   `run-id = <project-slug>-<YYYYMMDD-HHMMSS>Z`.
5. `nohup bash bin/orc-run.sh "$run_dir" >/dev/null 2>&1 &`, disown. The supervisor takes the project
   lock from the parent by inheriting the open descriptor, so there is no window in which the lock is
   free.
6. Print **one line**, then return the shell.

**Output — the one line**, and nothing else:

```
run <work-project>-20260919-224100Z · 6 ready · 2 lanes · capacity ok (<profile-B> 62%) · 1 weakened · ~/.orchestrator/runs/<work-project>-20260919-224100Z
```

If `plan.json.weakened[]` is non-empty the count is printed and one further line per weakened item is
printed **only** with `--dry-run`; otherwise `status --plan` shows them. If `capacity.reserve_pct` is
at its default of `0`, preflight prints one extra line, deliberately (survival G12):

```
note: capacity.reserve_pct = 0 — this run may spend your subscription to zero. Unasked question: «Чи можна витрачати ліміт до нуля, чи треба лишати запас на твою власну роботу?»
```

**Safe while a run is live: REFUSED (73).**
**Exit codes.** 0 detached · 64 usage · 69 preflight refused (the failing proofs are printed) · 73
locked · 78 config invalid.

### 3.3 `/orchestrator:status`

**Purpose.** The pull surface. Д11 [508] in one command. Reads; writes nothing (MR-17's `status`
contract).

**Arguments**

| Flag | Type | Meaning |
|---|---|---|
| *(none)* | — | the render, §5.2 |
| `--json` | bool | `status.json` **re-emitted through the render's own filter** (§5.3), not cat'd |
| `--lanes` | bool | the lane table only |
| `--why <lane>` | string | the last fact sheet the judge saw for that lane, its verdict and its reason, from `decisions.ndjson` |
| `--proofs` | bool | the proof table with each proof's age |
| `--plan` | bool | `plan.json`: what was weakened and denied, per owner item |
| `--cost` | bool | the supervision spend and the budget counters |
| `--ack` | bool | the last `control.ack.json`: what was applied, deferred, rejected |
| `--attention` | bool | the attention list only; exit 1 if non-empty |
| `--probe` | bool | non-blocking lock probe (§2.6): is a supervisor actually alive? |
| `--watch [<s>]` | int | re-render every `<s>` seconds (default 10). Still zero model; a plain `sleep` loop |

**Where it reads from — the complete list.** Nothing else, ever.

1. `$ORCH_HOME/runs/index.tsv` — addressing only.
2. `<run>/status.json` — every run fact in the render.
3. `<run>/control.ack.json` — `--ack`, and the one ack line in the default render.
4. `<run>/decisions.ndjson` — `--why` only.
5. `<run>/plan.json` — `--plan` only.
6. `$ORCH_HOME/proofs/<sha1(project_root)>.json` — `--proofs` only.
7. The lock file — `--probe` only.

It never reads the process table, never runs `git`, never touches the board, never reads a transcript,
never calls a platform. That is what makes the script layer cost nothing and what makes it safe to run
from inside a worktree at 04:00.

**Staleness.** `status.json` carries `written_at` and `written_mono`. If
`now − written_at > status.stale_after_ticks × supervisor.interval_s`, the render prints the staleness
in the header **and exits 5** — after printing. Staleness is a fact displayed, never a verdict acted
on (FIELD-NOTES §1.5: heartbeat staleness is not a stall, and treating it as one produced 33 nudges to
healthy sessions). `DEFAULT-PROPOSED status.stale_after_ticks: 3` — one missed tick is normal jitter,
three is a writer that stopped.

**Exit codes.** 0 nothing needs a human · 1 `attention[]` is non-empty or a lane is `needs-input` ·
2 ambiguous · 4 no run · 5 stale (render still printed) · 64 usage · 70 schema too new.

### 3.4 `/orchestrator:stop-hard`

Writes **one entry** into `control.json` and exits. **It signals no process.** The file is the
actuation channel and the tick is the clock — his mechanism, verbatim (Д12 [520]).

Entry written: `{"verb":"stop","scope":"run","apply":"now"}`.

| Flag | Type | Default | Meaning |
|---|---|---|---|
| `--lane <id>` | repeatable | — | narrow the scope to `lane:<id>`; the run keeps going |
| `--reason <text>` | string | — | recorded in the entry and in `report.md` |
| `--abandon` | bool | false | also stop the supervisor itself, leaving the run `dead` for `resume` |
| `--no-wait` | bool | false | do not poll for the ack; exit 0 as soon as the entry is written |
| `--timeout <s>` | int | `stop.ack_timeout_seconds` | how long to poll for the ack |

**Effect (the supervisor's side, stated so the operator knows what the command promises).** Each lane
wrapper gets `SIGTERM`; its trap tears down exactly what `owned.ndjson` lists for that lane, writes
`result.json` with `stopped_by:"control"`; then the run tears down and the supervisor exits, releasing
the lock. **The supervisor is exempt from its own stop until teardown completes** — Gas Town's ESTOP
carve-out, the one line that keeps a hard stop from orphaning everything it was meant to clean.
`--abandon` removes the carve-out and is the louder verb.

**The acknowledgement (cost G4, fidelity G9 — both judges independently).** After writing, the command
polls `<run>/control.ack.json` until the entry id appears in `applied[]`, `deferred[]` or `rejected[]`,
or `--timeout` elapses.

| Observed | Prints | Exit |
|---|---|---|
| in `applied[]` | `c-0012 stop hard applied at 23:41:07Z · 2 lanes stopping` | 0 |
| in `deferred[]` | `c-0012 deferred until <boundary>` | 0 |
| in `rejected[]` | `c-0012 rejected: <reason>` | 3 |
| timeout | `c-0012 written, not acknowledged in 90s — next: orchestrator status --probe` | 8 |

This replaces `ARCH-minimal`'s `applied within 60s`, which is *a promise about a process that may be
dead*. FIELD-NOTES §11.2 records two real operator instructions — `push master` and
`carry on with the queue` — sitting unsubmitted in input boxes while the engine's log recorded them as
delivered. Exit 8 is the operator-visible form of that failure.

`DEFAULT-PROPOSED stop.ack_timeout_seconds: 90` — one 60 s tick plus margin.
**Safe while a run is live: SAFE.** Exit codes: 0 · 3 · 4 · 6 (run already `finished`) · 8 · 64.

### 3.5 `/orchestrator:stop-soft`

Entry written: `{"verb":"stop","scope":"run","apply":"boundary"}`. Effect: `running` → `draining`.
Dispatch stops; live lanes run to completion. Same flags, ack behaviour and exit codes as `stop-hard`,
minus `--abandon`.

`--pause` changes the verb to `pause`, not `stop`: `{"verb":"pause","scope":"run","apply":"now"}` →
phase `paused`, dispatch nothing, keep observing, keep lanes alive. The quota-exhaustion path uses the
same state with `resume_at` set, so «дочекатись рестарту ліміту і продовжити» [007] is one state and
one comparison rather than a subsystem. Un-pausing is `--pause=off`, which writes `{"verb":"resume"}`.
Pause is not a separate command (§2.1).

### 3.6 `/orchestrator:stop-custom <ref>`

His own definition [524]: «Там можуть бути текстописні правила чи команди». Two execution models under
one name.

**Argument resolution — numbered, and the command resolves nothing it cannot name.**

1. If `<ref>` names a key in `stops.custom` in the resolved config, replace `<ref>` with that key's
   value and continue at step 2. One level of indirection only; a second lookup is **exit 64**.
2. If `<ref>` is a path that exists:
   a. and is executable → model = `exec`.
   b. and is not executable → model = `text`, contents read (capped at `custom.max_bytes`).
3. If `<ref>` is not a path and contains whitespace → model = `text`, `<ref>` itself is the text.
4. Otherwise → **exit 64**, printing the keys defined in `stops.custom`.

The command writes
`{"verb":"custom","scope":"run","apply":"custom","model":"exec|text","ref":"<absolute path or inline>","sha256":"…"}`
and exits. **The command never executes anything.** Execution happens in the supervisor, which is where
the blast radius, the ledger and the red lines are.

**What the supervisor then does**, stated here because it is what the command is promising:

- `exec`: run it with the run directory as cwd, `ORCH_RUN` exported, under `custom.timeout_s`. Exit
  code and output are journalled. It may itself write control entries — that is how a user composes a
  custom stop out of the vocabulary.
- `text`: hand it to the judge with the current fact sheet and one instruction — *translate this into
  zero or more control entries from the allowed vocabulary; anything you cannot translate, report and
  do nothing about.* Untranslatable text produces a journal line, a notification, and **no action**.
  A custom stop that cannot be executed inside the blast radius is **refused loudly** and the run falls
  back to `stop-soft` rather than doing something adjacent.

`DEFAULT-PROPOSED custom.timeout_s: 120` · `custom.max_bytes: 8192` · `custom.fallback: stop_soft`
(`stop_soft | none`) — refusing loudly and then draining is safer at 03:00 than refusing and
continuing to dispatch.

**This is the only stop verb that can cost a model turn**, and it costs exactly one, inside the
supervisor, not in the command.

### 3.7 `/orchestrator:resume`

**Purpose.** R1-10 [300]: «start over» means restart the orchestrator, not redo the work.

| Flag | Type | Default | Meaning |
|---|---|---|---|
| `<run-id>` | positional | last run for this project | which run to re-enter |
| `--from <source>` | enum | `state` | `state \| sessions \| transcripts \| ask` — R1-10 [293]/[307]: state files by default, previous sessions and their transcripts additionally, the user configures which are allowed and the orchestrator picks |
| `--epoch-bump` | bool | true | increment `epoch`, so every trip watermark and dedup key from the previous epoch is dead |
| `--dry-run` | bool | false | print the recovery decision per orphan and exit |
| `--adopt-lanes` | enum | `ask` | `ask \| stop \| wait` — Д10 [497]: the orchestrator analyses what those sessions are and decides to stop or wait, within its permissions |

**Algorithm**

1. Acquire the project lock non-blockingly. Held → **exit 73**, naming the live run. (This is the
   single-orchestrator invariant, R1-10 [300]. There is no `--force` for it.)
2. Read `status.json`, `journal.ndjson`, `owned.ndjson`, `lanes/*/start.json` and `ops.json`.
3. For each orphan (a `start.json` with no `result.json`, or an `action_id` with no result), run the
   **declared probe** from `ops.json` — `read_ref | refetch | probe_session | read_context | none` —
   and resolve it deterministically. Only the residue reaches the judge
   (`DEFAULT-PROPOSED recovery.probe_before_judge: true`, cost G9). An orphan whose declared
   `reconcile` is `none` escalates to the Д6 channel and is **never replayed**.
4. Apply the sleep fence before judging anything dead (survival G3): if
   `wall_delta − mono_delta > sleep.gap_seconds` since the last record, write `machine.wake` and hold
   every liveness and capacity verdict for `sleep.grace_seconds`. Sleep is literally how the previous
   run ended (FIELD-NOTES §10.1).
5. Bump `epoch`, write a new `start` record, launch the supervisor exactly as `run` step 5 does.
6. Print one line.

**Safe while a run is live: REFUSED (73).** Exit codes: 0 · 4 · 64 · 73 · 75 (refused, evidence named
in the journal) · 78.

### 3.8 `/orchestrator:add`

**Purpose.** Д2 [422]: work added mid-run is picked up if it is ready by the configured process's
rules. This is the command that adds it.

| Flag | Type | Default | Meaning |
|---|---|---|---|
| `<description>` | positional | — | the title, or the whole body with `--body -` |
| `--title <t>` | string | first line of the description | |
| `--body <t\|->` | string | — | `-` reads the body from stdin |
| `--file <path>` | path | — | read title and body from a file |
| `--id <ticket>` | string | — | do not create anything; enqueue an item that already exists on the board |
| `--after <id>` | repeatable | — | a dependency; the item is not claimable until those are done (R1-05 [160]) |
| `--priority <p>` | string | from config | passed through to the source verbatim |
| `--label <l>` | repeatable | — | passed through verbatim |
| `--grill` | bool | false | spend one model turn assessing description sufficiency before writing |
| `--ready` | bool | false | write the ready marker even if the readiness floor fails (override) |

**Algorithm**

1. Resolve the run (§2.4). A run is **not** required: `add` works with no run in progress and simply
   writes to the source.
2. Resolve the ticket source from config: `tickets.source ∈ local | board`.
3. Evaluate the **deterministic readiness floor** — zero model — against
   `tickets.ready_requires`: the body must contain a non-empty section for each named heading.
   `DEFAULT-PROPOSED tickets.ready_requires: ["Outcome","Acceptance","Scope"]` — measured clean over
   327 of his own tickets (C3-A6); the failure it prevents is a one-line ticket eating four hours.
4. If the floor fails and `--ready` was not given, apply `add.on_not_ready`.
   `DEFAULT-PROPOSED add.on_not_ready: park` (`park | reject | ready`) — write the item, mark it
   `needs-review`, do **not** enqueue it. Д2's description-sufficiency check is **OPEN by his own
   instruction** [424], and parking is the only one of the three that neither guesses a sufficiency
   rule nor throws his text away.
5. Allocate the id **under `control.lock`**, re-reading the highest existing id inside the lock. This
   is not optional: FIELD-NOTES §12.6 records that the previous generation's id allocator had no
   locking, so concurrent `add` calls could land on the same id **and both be told they succeeded**,
   and records that the fix landed only in the installed copy and reverts on the next sync.
6. Write. Local source → `<project>/.orchestrator/tickets/<id>.md`, written to the **main checkout**
   (resolved via `--git-common-dir`, §2.4 step 3), never into a worktree copy (FIELD-NOTES §12.5: a
   channel forked into a worktree and hid a real owner-facing question for an hour). Board source →
   create the item and set the ready label/status through the board adapter, and carry the dedup
   trailer `orchestrator-action: <run>:<epoch>:add:<id>` inside the created object (cost G5) so a
   replay after a crash asks the board rather than the journal.
7. If a run is live, append `{"verb":"intake","scope":"ticket:<id>"}` to `control.json` so the next
   tick sees it without waiting for a board poll.
8. Print one line.

**Output**

```
t-204 added · ready · local · enqueued into <work-project>-20260919-224100Z (c-0013)
t-205 added · needs-review (missing: Acceptance) · not enqueued · edit it and run: orchestrator add --id t-205
```

`--grill` is the only model-spending path and it is **off by default**, because the previous
generation's `add` grilled by default and Д2's sufficiency rule is the part he explicitly left open.

**Safe while a run is live: SAFE.** Exit codes: 0 · 1 (written but parked) · 64 · 69 (the source
refused the write) · 78.

### 3.9 `/orchestrator:ask`

**Purpose.** Д6 [449]: one channel for questions, clarifications, confirmations and review of finished
work, which the orchestrator watches for changes and takes into account live. `ask` is a convenience
over it; **the channel remains answerable by hand**, and that is a requirement, not a nicety — the
command must never become the only way in.

| Flag | Type | Meaning |
|---|---|---|
| *(none)* | — | list the open items: id, lane, ticket, age, the question text, the anchor |
| `--answer <id> <text>` | string | write an answer into the channel in the channel's own idiom |
| `--answer <id> -` | — | read the answer body from stdin |
| `--json` | bool | machine form |
| `--all` | bool | include answered items |

Answering writes into the channel (a local file section, a GitHub issue comment, a tracker task —
whatever `questions.channel` names) **under `control.lock`**, records the sha of what it wrote for
self-write suppression, and appends `{"verb":"answer","scope":"ticket:<id>"}` to `control.json` so the
next tick reads it without waiting for the channel poll.

Exit codes: 0 · 1 nothing is open · 4 no run and no channel configured · 64 · 69 the channel write
failed.

### 3.10 `/orchestrator:report`

| Flag | Type | Default | Meaning |
|---|---|---|---|
| `<run-id>` | positional | last run for this project | which run |
| `--path` | bool | false | print the artifact paths and nothing else (so `open $(orchestrator report --path)` works) |
| `--next` | bool | false | print `next-run.md` instead of `report.md` |
| `--tuning` | bool | false | print `tuning.patch.json` as a human diff |
| `--render` | bool | false | re-render the artifacts from `journal.ndjson` (for a run whose supervisor died before writing them) |
| `--partial` | bool | false | allow `--render` against a live run; the artifacts are written with `partial: true` |
| `--explain` | bool | false | one model turn: a prose summary of `next-run.md`. Off by default |

Exit codes: 0 · 4 no run · 6 the run is live and `--partial` was not given · 64.

### 3.11 `/orchestrator:sync`

MR-17's `sync` contract: reconcile stored config against the live system, preserving the user's
aliases. For this plugin that is three object maps that go stale: the **board's status names**
(R1-04 [153] — status names are user-overridable and adapt to the chosen process), the **account
inventory** per platform, and the **capacity buckets** each account reports.

| Flag | Type | Default | Meaning |
|---|---|---|---|
| `--check` | bool | **true** | detect and print the diff; write nothing |
| `--apply` | bool | false | write the reconciled map, preserving every user-set override |
| `--only <what>` | enum | all | `board \| accounts \| capacity` |
| `--force` | bool | false | permit `--apply` while a run is live |

`--check` is the default because a `sync` that writes by default is a `sync` that silently changes what
tonight's run means. Exit 1 when there is nothing to reconcile. **Safe while a run is live: `--check`
SAFE; `--apply` REFUSED (73) unless `--force`,** because the supervisor is using the status map it
booted with and rewriting it mid-run makes its board writes land on names that no longer exist.

### 3.12 `/orchestrator:remove`

MR-17's `remove`: uninstall hygiene, this plugin's own files only.

| Flag | Type | Default | Meaning |
|---|---|---|---|
| `--what <w>` | enum | `state` | `state \| config \| all` |
| `--runs <sel>` | string | `finished` | `finished \| all \| older-than:<days> \| <run-id>` |
| `--dry-run` | bool | **true** | list exactly what would be deleted; delete nothing |
| `--force` | bool | false | actually delete |
| `--keep-reports` | bool | true | keep `report.md` / `next-run.md` even when the run directory goes |

`--dry-run` is the default and `--force` is required to delete anything. It **never** touches:
anything outside `$ORCH_HOME` and the six config files; any worktree; any Docker resource; the
project's `RULES.md` or `tickets/`. **Safe while a run is live: REFUSED (73).** Exit codes: 0 · 4 · 64
· 73 · 77 (a path outside the permitted set was requested).

---

## 4. Running commands while a run is live

### 4.1 The class table — what a mid-run change does and when

Every configuration key belongs to exactly one class. The class is a property of the key, declared in
§10, not a judgement made at the time.

| Class | Keys | Applies |
|---|---|---|
| **Live** | `concurrency.*`, every threshold, `judge.*`, `notify.*`, `when_only_blocked`, `questions.*`, `output.*`, `failures.*` | **next tick** |
| **Boundary** | `roles.*.account`, `roles.*.model`, `process.*`, `context.*`, `red_lines.*`, `worktree.*` | **next lane launch**; a live lane keeps what it booted with |
| **Frozen** | project root, `process.kind`, `tickets.source`, `run id`, `engine.kind` | **reported, never applied**; the run must end first |

The Boundary row is not a preference, it is a platform fact: **ADAPTER-CONTRACT §3 F records that
changing a running session's account is impossible on all fifteen platforms**, and FIELD-NOTES §8
records the same thing measured — *a session already booted keeps the account it booted with*. An
`apply:now` account change is therefore a **stop + relaunch + reseed**, which pays for the context a
second time. R1-07 [195] asks for exactly that «hard» behaviour, so the command supports it and says
the price first:

```
$ orchestrator config --set roles.executor.account=<profile-B> --apply now
roles.executor.account is a boundary key. Applying it now means: stop lane t-118, relaunch it on
<profile-B>, and re-seed its context from scratch (~18k tokens, measured last launch).
Write the entry anyway? [y/N]
```

Every class a command touches is reported in `control.ack.json` — `applied[]`, `deferred[{key,until}]`,
`rejected[{key,reason}]` — so a Frozen edit is **always surfaced in `rejected[]`, never silently
ignored**.

### 4.2 The run scope, and where it does not fit the marketplace

He requires three scopes including *this run* [331]/[075]; `snf` states that its three levels are the
whole set (OWNER-DECISIONS 3.6). The reconciliation changes nothing in `snf`: **the run scope is not
configuration.** It is per-invocation state — `--set` arguments captured into `config.run.json`,
layered on top of the resolver's output by the orchestrator itself, never written to any config file,
gone when the run ends. `config --show` prints it as a separate, clearly-labelled band above the six
slots, so he can see what this run is actually using. Recorded as a tension in §11.4.

### 4.3 The full matrix

| Command | Run live | Run paused | Run draining | No run |
|---|---|---|---|---|
| `config` (read flags) | SAFE | SAFE | SAFE | SAFE |
| `config` (writes) | SAFE-WITH-EFFECT §4.1 | same | same | SAFE |
| `config --verify` | SAFE — but it **sends a real notification** (§7.3); the command says so first | same | same | SAFE |
| `run` | REFUSED 73 | REFUSED 73 | REFUSED 73 | SAFE |
| `status` | SAFE | SAFE | SAFE | 4 |
| `stop-hard` / `stop-soft` | SAFE | SAFE | SAFE | 4 |
| `stop-custom` | SAFE | SAFE | SAFE | 4 |
| `resume` | REFUSED 73 | REFUSED 73 | REFUSED 73 | SAFE |
| `add` | SAFE | SAFE | SAFE (parked, not claimed) | SAFE |
| `ask` | SAFE | SAFE | SAFE | SAFE if a channel is configured |
| `report` | 6 unless `--partial` | 6 unless `--partial` | 6 unless `--partial` | SAFE |
| `sync --check` | SAFE | SAFE | SAFE | SAFE |
| `sync --apply` | REFUSED 73 | REFUSED 73 | REFUSED 73 | SAFE |
| `remove` | REFUSED 73 | REFUSED 73 | REFUSED 73 | SAFE |

---

## 5. The status contract

### 5.1 `status.json` — the document

Written atomically every tick by **one writer** (the supervisor) — temp file in the same directory,
then `rename()`. It is the **only** run-fact source any command reads. It contains only facts the
supervisor can prove.

| Field | Type | Notes |
|---|---|---|
| `schema` | int | `1`. A reader whose build is older than the document's schema exits 70 |
| `run_id` | string | |
| `project` | string | absolute path, `pwd -P` resolved |
| `run_dir` | string | absolute path |
| `written_at` | string | RFC3339 UTC, `Z`, second precision |
| `written_mono` | number | `CLOCK_MONOTONIC` seconds. Every duration is computed on this; wall clock is for display only (survival G3) |
| `epoch` | int | restart counter; every trip key and dedup key is scoped by it |
| `boot_id` | string | the machine's boot identity; a change means a reboot, not a sleep |
| `supervisor` | object | `{pid:int, pid_started_at:string, ticks:int, last_tick_at:string, interval_s:int}` |
| `mode` | enum | `controlled \| autonomous` |
| `phase` | enum | `starting \| running \| draining \| paused \| stopping \| finished \| dead` |
| `resume_at` | string\|null | set when `phase = paused` by a quota window |
| `engine` | object | `{kind:"engine"\|"custom", id:string, version:string\|null, exit_contract:string\|null}` |
| `completion_oracle` | string | e.g. `engine_probe:gsd`. Named out loud so the render can say what "done" meant |
| `lanes` | array | §5.1.1 |
| `queue` | object | `{ready:int, blocked_by_deps:int, blocked_on_human:int, active:int, done_this_run:int, arrived_since_start:int}` |
| `capacity` | array | §5.1.2 |
| `proofs` | array | `{name, verdict:"proven"\|"failed"\|"unprovable", at, age_s, detail}` |
| `weakened` | array | `{owner_item, axis, from, to, consequence, lane}` — fidelity G5 |
| `attention` | array | `{id, at, kind, subject, text, anchor}` — append-only within a tick; **never truncated and rebuilt** |
| `blocked_on` | array[string] | machine tokens, e.g. `judge_budget_exhausted`, `capacity_unknown` |
| `control` | object | `{last_entry_id, applied_at, ack:{read_at, doc_sha256, applied[], deferred[], rejected[], parse}}` |
| `control_error` | string\|null | a parse failure keeps the last good entries and lands here |
| `board` | object | `{source, mode:"read_write"\|"read_only"\|"degraded"\|"none", last_sync_at, error}` |
| `budgets` | object | `{judge_calls_hour, judge_calls_hour_max, wakes_hour, wakes_hour_max, notifies_run, notifies_run_max}` |
| `cost` | object | `{supervision_usd:number, prov, work_usd:number\|null}` |
| `notify` | array | `{name, kind, required:bool, tier1:"proven"\|"failed"\|null, tier2:…, last_receipt, last_error}` |
| `last_judge` | object\|null | `{at, verdict, lane, reason, fact_sheet_sha1}` |

**There is no `healthy` field, and adding one is a build failure.** See OUT-6.

**Every measured number carries `prov` (`measured \| estimated \| unknown`) and `age_s`.**
`missing ≠ zero`: an absent capacity reading is `{"kind":"unknown","reason":"…"}`, never
`{"used_pct":0}`. The shipped predecessor degraded `weekly_all` to `unreadable%` and then treated that
state as benign (C4 §3.1b, VERIFIED); this is the structural fix.

#### 5.1.1 A lane

`{id, ticket, ticket_title, state, pid, pid_started_at, platform, account, worktree, base_sha,
compose_project, session_id, started_at, events_last_grew_at, attempt:int, heavy:bool,
context:{pct:number, basis:"raw_window"|"usable_after_reserve"|"statusline", prov, age_s,
refill_pct_per_hour:number|null}, engine:{state, detail, age_s},
harvest:{verdict:"done"|"not_done"|"undeterminable", evidence, at}|null,
question:{text, anchor, since}|null}`

`state ∈ claiming | spawning | working | needs-input | harvesting | draining | done | failed | orphaned`.
`context.basis` is **required, never inferred** (fidelity G10): two percentages about 13 points apart
exist on his machine (C5-A2) and a threshold set against the wrong one is a threshold that never fires.
`context.refill_pct_per_hour` exists because of the single worst lane on record — `w-phase-19` issued
**3,466 of its 3,626 Bash calls as the literal command `echo idle`**, added 445k tokens and reached
91%, and read as healthy against every liveness signal (`JUDGE-cost` §9.2).

#### 5.1.2 A capacity row

`{account, platform, kind:"window"|"credit"|"none"|"unknown", bucket, used_pct:number|null,
remaining:number|null, reset_at:string|null, read_at, age_s, prov, reason:string|null}`

`kind:"none"` is a real answer (pay-as-you-go, [007]) and is not a failure.

### 5.2 The human render

Derived from `status.json` and nothing else. Worked example, the default render:

```
run <work-project>-20260919-224100Z · project <work-project> · engine gsd 1.14.0 · epoch 7 · mode controlled
started 22:41 · 4h 12m ago · phase RUNNING · written 19s ago · oracle engine_probe:gsd

capacity  claude-code/<profile-B>   window  62% used · resets 11:59Z   (read 11m ago, measured)
          claude-code/<profile-A>   window   7% used · resets 17:50Z   (read 11m ago, measured)
          glm/main                 window  unknown — never proven this run
queue     ready 6 · active 2 · needs-input 1 · blocked-by-deps 2 · done 13 · (+3 since start)

lanes
  t-118  gsd:execute-phase  wt <work-project>-p22  ctx 61% raw (+9%/h)  working      1h 04m
  t-121  gsd:plan-phase     wt <work-project>-p23  ctx 18% raw (+4%/h)  working        22m
  t-119  --                                                          needs-input  3h 41m
         "which of the two auth flows is canonical?" → QUESTIONS.md#Q-14

attention 1
  ! capacity read for glm/main has never succeeded this run — that lane is unschedulable

control   c-0013 applied 14:02:11Z · 0 deferred · 0 rejected
budgets   judge 4/12 this hour · notifies 3/40 this run
cost      supervision $0.41 (measured) · work — (not measured on subscription lanes)
```

Four rules the render obeys, each traceable to a recorded failure:

1. **`written Ns ago` is printed in the header, always.** A JSON file goes stale the moment its writer
   dies and then shows the last good state as though it were current.
2. **Staleness is displayed, never acted on** (FIELD-NOTES §1.5).
3. **`unknown` is printed as `unknown`, never as `0`** (OUT-8).
4. **A `needs-input` lane prints the question and the anchor into the channel.** He can read the whole
   of his obligation from one screen.

Fifth rule, added here: **no detector's own trigger string is ever printed into a file a detector
reads** (survival G11). The render is written to a terminal, but `--json > file` and `--watch` into a
log are both ordinary operator habits, and the 85-minute loop (FIELD-NOTES §11.6) was a detector
matching the orchestrator's own wrapped prose. The render therefore prints `context action: none` and
never the literal `/compact`, `rate-limit` or `usage limit`.

### 5.3 `--json` is filtered, not `cat`

`status --json` re-emits `status.json` through the render's own projection: it adds
`{"stale":bool,"stale_s":int,"exit":int}` at the top level and **drops** any key the build does not
know. A future supervisor writing a field this build cannot interpret must not leak that field into a
machine consumer as though it were understood. `status --json --raw` is the escape hatch that cats the
file, and it is the only way to see unknown fields.

---

## 6. The morning artifact

Written to the run directory at `finished`, **and at every stop** — a stop that leaves no report is a
bug. Also on demand with `report --render`.

```
~/.orchestrator/runs/<run-id>/report.md            # what happened
~/.orchestrator/runs/<run-id>/next-run.md          # what to change
~/.orchestrator/runs/<run-id>/tuning.patch.json    # the machine form of next-run §2
```

`DEFAULT-PROPOSED report.copy_to: null` — the artifacts stay in the run directory under `$HOME` and are
**not** copied into the checkout. Д4 makes every task its own worktree, so anything written into the
repository forks per lane and the copies diverge; FIELD-NOTES §12.5 records exactly that, with a real
owner-facing question invisible for an hour. `report --path` prints the paths so
`open "$(orchestrator report --path)"` is one command.

### 6.1 `report.md` — position, never narrative

Eight sections, all mechanical:

1. **Header** — run id, project, engine and version, mode, epoch(s), start, end, wall duration, the
   reason it ended (`queue_empty | stop_hard | stop_soft | stop_custom | crash | quota`).
2. **Tickets by final state**, with the reason for every non-`done` one, and the completion oracle that
   decided each.
3. **Delivery** — the trunk's before and after sha, every PR with its merge verdict, and for each the
   result of the landed assertion (cost G6). A PR that reports `MERGED` whose head is not an ancestor
   of the base is `merge_unproven`, a lane failure, never a retry. This checks the orchestrator's own
   operation, not the work (§11.3).
4. **Escalations** — each question, when it was raised, how long it blocked, whether it was answered
   and by what.
5. **Pauses** — every `paused` window, its cause and its duration.
6. **Left running, deliberately** — every `owned.ndjson` entry not torn down, with its exact
   identifier, and one exact command per item for the owner to run. Residue from a *previous* run is
   listed under its own run id and is **never** reclaimed (C8-A1: about 150 orphaned Docker volume
   pairs were observed, FIELD-NOTES §11.11).
7. **Proofs** — every proof that was `unprovable` at preflight and whether it bit during the night.
8. **Capacity** — the position per account at start and at end.

### 6.2 `next-run.md` — four sections (cost G10 / operability §14.3)

1. **Detector scorecard.** Per detector: firings, confirmed, false, never-fired. **A detector with zero
   confirmed firings is reported as `unproven`, not as `clean`.** `DEFAULT-PROPOSED
   report.mark_unfired_as: unproven`. The case that makes this non-theoretical: BSD
   `find -newermt "-10 minutes"` errors out, and with stderr to `/dev/null` returns empty every time,
   which would have declared every healthy session idle for ever (FIELD-NOTES §11.3) — a probe that
   could never succeed and never complained.
2. **Threshold traffic.** Every threshold that armed, how often, and whether the trip changed anything.
   A context threshold that armed eleven times and compacted once is a badly placed threshold, and that
   fact is visible nowhere else.
3. **Where the time and the tokens went.** Per lane: wall clock, judge wakes attributable to it, scout
   invocations, compactions and reseeds, and the ratio of waiting-on-human to working.
4. **What the owner had to do.** Every `owner.action` record: questions answered and how long they
   blocked, hand edits to `control.json`, manual interventions. **This is the list whose shrinking is
   the actual measure of the product.**

`DEFAULT-PROPOSED report.scorecard: true` — it costs counters during the night and one `jq` render at
the end, and it is the cheapest way to discover which of the plugin's own probes are dead.

### 6.3 `tuning.patch.json`

A proposed patch against the config, derived **only** from `next-run.md` §2, in the shape
`[{"key":…, "from":…, "to":…, "because":"<section-2 row>"}]`. **Nothing is ever applied
automatically.** `DEFAULT-PROPOSED tuning.auto_apply: false` and the key exists so that the answer is
visible rather than implicit — a system that retunes itself overnight is one whose behaviour he cannot
predict. The only path is `config --apply-tuning`, which prints the diff and asks.

---

## 7. Notifications — the channel abstraction and its verification

R1-17 [395]: «людина може налаштувати, що буде якийсь канал для зв'язку, наприклад, телеграм, слек,
джімейл … може бути навіть умовно якийсь дзвінок … Чи це сповіщення будуть тільки просто в терміналі …
Людина налаштовує, які типи можуть приходити», and the orchestrator «повинен лише переконатися, що це
працює».

### 7.1 The abstraction — a directory of scripts, not a vendor list

A channel **kind** is a directory. The plugin knows nothing about Telegram, Slack or a phone call;
OWNER-DECISIONS §2 (agnosticism) forbids a vendor being named in plugin code.

```
channels/<kind>/
  meta.json      {"kind":"…","version":1,"needs":["…"],"receipt":true|false,
                  "two_way":true|false,"timeout_s":20}
  verify.sh      # tier 1. argv: none. env: the channel's resolved keys. → one JSON line
  send.sh        # stdin: the message JSON below. → one JSON line
  receipt.sh     # optional; argv[1] = a receipt id → one JSON line. Absent ⇒ receipt:false
```

**Contracts.** `verify.sh` prints `{"ok":bool,"identity":string,"detail":string}` and exits 0 on ok.
`send.sh` prints `{"ok":bool,"receipt":string|null,"detail":string}` and exits 0 on accepted.
`receipt.sh` prints `{"state":"accepted"|"unknown"|"failed","detail":string}`. Each must print
**exactly one JSON line on stdout and nothing else**, must finish within `meta.json.timeout_s`, and
must write every diagnostic to stderr. A script that violates any of these is treated as `ok:false`
with `detail:"contract violation: …"`, never as a success.

**The message JSON given to `send.sh` on stdin:**

```json
{"schema":1,"run_id":"<work-project>-20260919-224100Z","at":"2026-09-20T03:11:04Z",
 "event":"only_blocked_work_left","severity":"warn",
 "subject":"orchestrator: only human-blocked work left",
 "text":"3 tickets are waiting on you; nothing else is claimable.",
 "anchor":"QUESTIONS.md#Q-14","dedup_key":"only_blocked:epoch7","run_dir":"/Users/…"}
```

`severity ∈ info | warn | urgent`. `dedup_key` is scoped by `epoch`, so a restart legitimately
re-notifies and a loop does not.

**Kinds shipped in the plugin: `terminal`, `file`, `command` — and no others.**

| Kind | `send.sh` does | Receipt |
|---|---|---|
| `terminal` | appends one line to `journal.ndjson` and pushes onto `status.json.attention[]` | the attention id |
| `file` | appends the message to `channels.<name>.path`, under a lock | the byte offset |
| `command` | runs `channels.<name>.send_command` with the message on **stdin** and the fields as `ORCH_MSG_*` env vars | whatever the command prints on stdout, trimmed |

Telegram, Slack, email and the phone call [395] are all `command` channels. Their recipes (the exact
`curl`, the exact `verify_command`) live in `config/recommended.json`, which is **advisory and supplies
no value to any resolved config** (OWNER-DECISIONS 3.8): the wizard offers a recipe, the user accepts
it, and the accepted text becomes *his* configuration in *his* file. Nothing vendor-specific is ever
read at run time from the marketplace.

**Configuration shape:**

```json
{ "notify": {
    "required": true,
    "channels": {
      "terminal":      { "kind": "terminal" },
      "telegram-main": { "kind": "command",
                         "send_command":   ["curl","-sS","-X","POST","https://…/sendMessage","-d","@-"],
                         "verify_command": ["curl","-sS","https://…/getMe"],
                         "secret_env": "TELEGRAM_BOT_TOKEN" } },
    "routes": [ {"events":["*"], "min_severity":"warn", "to":["terminal"]},
                {"events":["run_stopped","quota_hard"], "min_severity":"info", "to":["telegram-main"]} ],
    "events": ["run_stopped","quota_hard","capacity_unknown_grace","repeated_failure",
               "only_blocked_work_left","board_sync_degraded","doctor_relaunched"],
    "max_per_run": 40, "coalesce_minutes": 30, "timeout_seconds": 20,
    "recheck_minutes": 120, "quiet_hours": null, "deadman": null } }
```

`secret_env` is a **pointer** (MR-23); the token itself never appears in any config file, in
`status.json`, in the journal or in any render (OUT-7).

### 7.2 Routing, and the caps

A message is delivered to every route whose `events` glob matches and whose `min_severity` is met. If
no route matches, it goes to `terminal`.

`DEFAULT-PROPOSED notify.channels: {"terminal":{"kind":"terminal"}}` and
`DEFAULT-PROPOSED notify.channel default = terminal`, **not `none`** — with no channel at all, Д7's
default (wait forever) plus Д11's silence is a run that blocks indefinitely with nobody told, which is
C9-A6's exact collision. `terminal` always verifies, so OWNER-DECISIONS 6.1 (a plugin must work with no
config) still holds.

`DEFAULT-PROPOSED notify.max_per_run: 40` and `notify.coalesce_minutes: 30` — FIELD-NOTES §11.6
records **1,085 identical alerts** for one unresolved condition over about five days. 1,085 identical
alerts is a product failure before it is an API failure. Coalescing is by `dedup_key`: the second and
subsequent messages within the window are suppressed and a single `(×N since HH:MM)` suffix is added to
the next one that does go.

`DEFAULT-PROPOSED notify.events`: the seven listed above — all of them things that end or stall a
night. **R1-17's substantive half — what is worth waking him for — was never answered** (`by-item.md`
R1-17 final row, VERIFIED), so this list is proposed and preflight prints it with a one-line invitation
to cut it. `DEFAULT-PROPOSED notify.quiet_hours: null` — the interviewer asked at [394] and the answer
was skipped; inventing a window in which he is not told a run died is worse than telling him. Both go
to §12.

### 7.3 Verification — three tiers, and what each one actually proves

He said «повинен лише переконатися, що це працює». The word "працює" has three meanings and they are
routinely conflated:

| Tier | What runs | What it proves | When |
|---|---|---|---|
| **1 credential** | `verify.sh` | the token works. **Nothing about reachability of the human** | preflight, and every `notify.recheck_minutes` |
| **2 delivery** | `send.sh` with a real probe message; the receipt is stored | the message reached the service. Labelled *delivered*, **never** *seen* | preflight, once per run |
| **3 liveness** | tier 1 re-run on a schedule, and optionally a dead-man's switch | the channel is still working; the dead-man's switch also survives the orchestrator dying | during the run |

**A tier-1-only check is refused as proof for any channel with `required: true`.** VERIFIED against
`core.telegram.org/bots/api` (fetched 2026-09-19): `getMe` returns the bot's capability fields and the
docs state it proves *"the bot's capabilities and configuration, not operational status"* — it passes
for a bot that has been kicked from the chat (C9-A5). CLAIMED for Slack: `auth.test` is documented as
an authentication check. **Neither Telegram nor Slack exposes a read receipt for a bot-sent message**
(VERIFIED for Telegram from the API docs; CLAIMED for Slack), so *delivered* is the ceiling on both and
the render must never say *seen*.

**Algorithm, as run by `run` step 3 and by `config --verify`:**

1. For each configured channel, in declaration order:
2. Resolve its keys. A `secret_env` whose variable is unset → `failed`, reason `secret_env unset: NAME`,
   and the name of the variable is printed, never its value.
3. Run `verify.sh` under `meta.json.timeout_s`. Non-zero, a timeout, or a non-conforming stdout →
   `tier1: failed`.
4. If `meta.json.receipt` is false → `tier2: unprovable`, and record it. A channel that cannot produce
   a receipt (a phone call) is not thereby disqualified; it is recorded as unprovable and printed as
   such.
5. Otherwise run `send.sh` with the probe message
   (`event:"preflight_probe"`, `severity:"info"`, text naming the run id and the local time). Store the
   receipt in `proofs.json`.
6. Decide the run:
   - any channel with `required: true` not reaching `tier2: proven` (or `tier2: unprovable` with
     `tier1: proven`) → **preflight refuses, exit 69.** A run that cannot reach him is a run he will not
     know has stopped.
   - `notify.required: false` → downgrade the failing channel to `terminal`, record it in
     `status.json.notify[]` and in `report.md` §7, and start.
7. Write `proofs.json` with `{name, verdict, at, detail, receipt}` per channel.

`DEFAULT-PROPOSED notify.required: true` — with the default channel set being `{terminal}`, which
always verifies, this costs nothing on a fresh install and refuses loudly the moment he configures a
real channel that does not work.
`DEFAULT-PROPOSED notify.recheck_minutes: 120` — cheap (tier 1 is one call), and two hours is short
enough that a revoked token is found before the night ends.
`DEFAULT-PROPOSED notify.deadman: null` (opt-in; a URL to ping every `deadman.interval_minutes`) —
INFERRED that it is the only pattern that survives the orchestrator itself dying, which is precisely
the case FIELD-NOTES records; it is null by default because it sends run metadata off the machine and
that is his call, not the plugin's.

### 7.4 The knowing collision with Д11

Tier 2 sends a message he did not ask for, and Д11 says the orchestrator prints nothing unless asked.
`ARCH-operability` §16.4 is right that these two requirements collide. **The resolution: tier 2 runs
only inside `run` and `config --verify`, both of which he invoked.** Nothing during the night sends an
unrequested message except a routed event he configured. The probe message names itself as a probe and
carries the run id so it is not mistaken for a real alert. This is a minimal, knowing, one-message-per-
run violation and it is recorded in §11.5 rather than hidden.

---

## 8. Marketplace conformance checklist

| Rule | How this spec satisfies it |
|---|---|
| NAMING R1 — at least one command file | twelve |
| NAMING R2 / R3 — `run`, and baseline verbs where they fit | `run`, `config`, `status`, `resume`, `sync`, `remove` are baseline; `stop-hard`, `stop-soft`, `stop-custom`, `add`, `ask`, `report` are outside it, permitted, and none is a synonym of a baseline verb (§2.1) |
| NAMING R4 — backing skill hidden | `skills/orchestrator/SKILL.md`, `user-invocable: false`, `disable-model-invocation: false` |
| NAMING R5 — kebab-case, no prefix | `orchestrator` |
| NAMING R6 — command delegates to the skill | honoured for the five judgement commands; **named departure** for the seven zero-work ones, §1.3, recorded in the PR |
| NAMING R7 — `plugin.json.command` mirrors the invocation | `` `/orchestrator:run` `` |
| MR-9 — `$ARGUMENTS` verbatim | every command file |
| MR-12 / MR-13 — the config surface is `/orchestrator:config` | §3.1; it touches the shared `connectors` surface, so the command form is mandatory, not optional |
| MR-14 — re-runnable, wizard on first run, idempotent | §3.1; no state file has to be deleted to change a setting |
| MR-15 — headless-safe | §3.1, explicit signals in order, never a bare TTY probe, fail closed to non-interactive |
| MR-17 — `status` writes nothing; `sync` preserves aliases; `remove` is uninstall hygiene; `resume` resumes | §3.3, §3.11, §3.12, §3.7 |
| MR-23 — secrets as pointers | `secret_env`, and OUT-7 |
| OWNER-DECISIONS 2 — agnosticism | no vendor named in plugin code; channels are `command` + recipes in `recommended.json` (§7.1); platforms are adapters |
| OWNER-DECISIONS 3.8 — `recommended.json` advises, never supplies | nothing reads it at run time |
| OWNER-DECISIONS 6.1 — works with no config | the default channel set is `{terminal}`; the wizard asks what is missing; `run` refuses only on a proof, never on an absent optional key |
| repo rule — the plugin must be in `tests/run-all.sh`'s `PLUGINS` array | otherwise nothing covers it |

**Build-failing tests this spec requires**, beyond CMD-1/CMD-2/EXIT-1/OUT-1 above:

- **LINT-BD1** — `pkill`, `killall`, and `docker compose down` without an explicit `-p` may not appear
  anywhere in plugin source. Plus the clause neither prior design had: **no teardown command may be
  constructed from an environment variable — every identifier in a teardown command comes from a field
  in `owned.ndjson`** (survival G14). The recorded incident was not a `pkill`; it was
  `docker compose down -v` with `COMPOSE_PROJECT_NAME` absent, so the command resolved to the default
  project — the owner's.
- **LINT-ECHO** — no detector trigger string (`/compact`, `rate-limit`, `usage limit`) is written by
  any renderer into any file a detector reads (survival G11).
- **DEF-1** — every key read anywhere in `bin/` appears in §10. A key with no row fails the build;
  nothing outside §10 may invent a default at run time.
- **MUT-1** — each of the above is verified by **mutation**: break the invariant on purpose and
  confirm the suite goes red. This repo's own memory rule records that its harness greps prose and
  tests can pass vacuously; FIELD-NOTES §11.9 records that every commit gate in the previous
  generation was found broken by mutation rather than by failing. Until MUT-1 passes, every claim in
  this section is a claim, not a property.

---

## 9. Worked session — one night, from the operator's side

```
$ orchestrator config
… wizard: board, channel, accounts, process, thresholds … (interactive, the only chatty command)

$ orchestrator run --mode controlled --max-lanes 2
run <work-project>-20260919-224100Z · 6 ready · 2 lanes · capacity ok (<profile-B> 62%) · 0 weakened · ~/.orchestrator/runs/<work-project>-20260919-224100Z
note: capacity.reserve_pct = 0 — this run may spend your subscription to zero. Unasked question: «Чи можна витрачати ліміт до нуля, чи треба лишати запас на твою власну роботу?»

# … four hours of nothing at all …

$ orchestrator status                      # from a lane worktree; addressing still resolves
… the render of §5.2 …                     # exit 1: t-119 needs input

$ orchestrator ask
Q-14  t-119  3h 41m  which of the two auth flows is canonical?  → QUESTIONS.md#Q-14

$ orchestrator ask --answer Q-14 "the session-cookie one; drop the bearer path"
Q-14 answered · QUESTIONS.md#Q-14 · queued as c-0014

$ orchestrator add "Retire the bearer auth path" --body - <<'EOF'
## Outcome
The bearer path is gone and nothing references it.
## Acceptance
Test suite green; grep for BEARER_ returns nothing outside docs.
## Scope
apps/api only.
EOF
t-204 added · ready · local · enqueued into <work-project>-20260919-224100Z (c-0015)

$ orchestrator stop-soft --reason "morning"
c-0016 stop soft applied at 07:02:11Z · draining · 2 lanes running

$ orchestrator status --json | jq -r '.phase, .queue.ready'
draining
5

$ orchestrator report --path
/Users/…/.orchestrator/runs/<work-project>-20260919-224100Z/report.md
/Users/…/.orchestrator/runs/<work-project>-20260919-224100Z/next-run.md

$ orchestrator config --apply-tuning
liveness.silence_minutes  20 → 35   because: silence detector fired 9 times, 0 confirmed
context.raw_pct_threshold 75 → 82   because: threshold armed 11 times, compacted once
apply these 2? [y/N]
```

---

## 10. The defaults register

Every default this document proposes, in one place, with its class (§4.1), its scope and what it
protects against. **Nothing outside this table may invent a default at run time** (test DEF-1). None of
these is a decision of his; each is one line for him to overturn.

| Key | DEFAULT-PROPOSED | Class | Scope | Rationale (what it protects against) |
|---|---|---|---|---|
| `shim.install` | `ask_once` | — | user | Writing an executable onto his PATH without asking is not a plugin's call |
| `shim.path` | `~/.local/bin/orchestrator` | — | user | The conventional user bin; no sudo, no PATH edit if it is already there |
| `output.verbosity` | `normal` (`quiet\|normal`) | Live | user | Д11 [512] asks for minimal output; `normal` is already ~12 lines |
| `output.max_lines` | `40` | Live | user | A status render that scrolls is one he stops reading |
| `secrets.redact_keys` | `["*token*","*secret*","*password*","*api_key*","*.key"]` | Live | user | A pointer printed is harmless; a value printed is not (MR-23) |
| `status.stale_after_ticks` | `3` | Live | user | One missed tick is jitter; three is a writer that stopped |
| `lock.acquire_timeout_seconds` | `10` | Live | user | A stuck command at 03:00 should fail, not hang |
| `stop.ack_timeout_seconds` | `90` | Live | user | One 60 s tick plus margin, so exit 8 means something |
| `custom.timeout_s` | `120` | Boundary | user | A custom stop script that never returns is a stop that never happens |
| `custom.max_bytes` | `8192` | Boundary | user | Text too large to hand a judge with a fact sheet |
| `custom.fallback` | `stop_soft` (`stop_soft\|none`) | Live | user | Refusing loudly then draining beats refusing then dispatching |
| `config.default_scope` | `user-plugin` (slot 4) | — | user | One person, one machine, this plugin — what almost every answer in the interview is |
| `proofs.max_age_hours` | `24` | Boundary | user | A platform that auto-updated since yesterday (ADAPTER-CONTRACT §6.8) |
| `tickets.ready_requires` | `["Outcome","Acceptance","Scope"]` | Live | project | A one-line ticket eating four hours; measured clean over 327 of his tickets |
| `add.on_not_ready` | `park` (`park\|reject\|ready`) | Live | project | Д2's sufficiency rule is OPEN [424]; parking neither guesses it nor throws his text away |
| `report.copy_to` | `null` | Live | project | A worktree fork that hid an owner-facing question for an hour (FIELD-NOTES §12.5) |
| `report.scorecard` | `true` | Live | user | A probe that can never succeed and never complains (FIELD-NOTES §11.3) |
| `report.mark_unfired_as` | `unproven` (never `clean`) | Live | user | Reading zero firings as health |
| `tuning.auto_apply` | `false` | Live | user | A system that retunes itself overnight is one he cannot predict |
| `notify.channels` | `{"terminal":{"kind":"terminal"}}` | Live | user | `none` + wait-forever + silence = an indefinite block nobody is told about (C9-A6) |
| `notify.required` | `true` | Live | user | Free on a fresh install; refuses loudly the moment a real channel does not work |
| `notify.events` | the seven in §7.1 | Live | user | R1-17's substantive half was never answered; printed for him to cut |
| `notify.max_per_run` | `40` | Live | user | 1,085 identical alerts over five days (FIELD-NOTES §11.6) |
| `notify.coalesce_minutes` | `30` | Live | user | As above, by `dedup_key` |
| `notify.timeout_seconds` | `20` | Live | user | A hanging `curl` must not hold a tick |
| `notify.recheck_minutes` | `120` | Live | user | A revoked token found before the night ends; tier 1 is one call |
| `notify.quiet_hours` | `null` | Live | user | The question was asked at [394] and skipped; a window in which he is not told a run died is worse than being told |
| `notify.deadman` | `null` (opt-in) | Live | user | The only pattern that survives the orchestrator dying; it sends metadata off the machine, so it is his call |
| `capacity.reserve_pct` | `0`, **and preflight prints the question** | Live | user | Inventing a reserve for an account he also works in. The sub-question was dropped by the interviewer (survival G12) |
| `doctor.enabled` | `auto` (`auto\|true\|false`) | Boundary | user | `auto` = on only when preflight proves a second, distinct account. Closes the dead-orchestrator class without inventing an account |
| `sync.default_action` | `check` | — | user | A `sync` that writes by default silently changes what tonight's run means |
| `remove.default_action` | `dry_run` | — | user | Deleting state on a typo |

Keys owned by sibling specs and referenced here only so this document is readable — their defaults
live in those documents, not in this register: `tick.interval_seconds` (60), `run.mode`
(`controlled`), `concurrency.max_lanes` (2), `capacity.soft_pct`/`hard_pct` (80/95),
`capacity.on_unknown` (`hold_dispatch`), `context.raw_pct_threshold` (75) and `context.basis`,
`context.post_compact_prompt`, `judge.max_calls_per_hour` (12), `judge.trip_scope`,
`harvest_evidence` (`observed`), `failures.repeat_threshold` (3), `when_only_blocked` (`wait`),
`worktree.enabled` (true), `trunk.policy` (`pr_only`), `delivery.assert_landed` (true),
`sleep.gap_seconds` (60) / `sleep.grace_seconds` (120), `red_lines.path`, `session.permissions`
(`inherit`).

---

## 11. Tensions — decisions kept, discomfort recorded

### 11.1 Three stop commands, and what it costs

He named three verbs, twice ([520], [524]). `NAMING.md` §5 lists *"ship two commands for one action"*
as a Don't, and a reviewer could read `stop-hard` / `stop-soft` / `stop-custom` that way. They are
implemented as three commands because he named three, because they have three different
post-conditions rather than one action with a modifier, and because R3 permits verbs outside the
baseline. **The cost:** three files instead of one, three entries in his slash menu instead of one, and
a reviewer conversation. **What is refused:** shipping a bare `stop` alongside them, which would be
exactly the synonym MR-17 forbids. The question goes to him in §12 Q1, and switching to
`stop --hard` later is a one-day change because all three commands are the same six lines over
`orc-ctl.sh`.

### 11.2 "Zero model tokens" is impossible for a slash command

§1.2 states the correction rather than repeating the claim. **The part that is impossible:** a slash
command that costs nothing. **The part that is kept:** no agent dispatch, no tool loop, no reasoning —
one Bash call and a verbatim relay. **What it costs to keep the whole of what he described:** the
shim, so a plain terminal gets the genuinely free path, and one `ask_once` question at config time.

### 11.3 A landed-merge assertion is the orchestrator checking itself

R1-13 [344] gives verification to the configured process and he held that position with the evidence
in front of him. §6.1 §3 still asserts that a merge moved a ref. The distinction that keeps this on the
right side of his decision: **the engine says whether the ticket is done; the orchestrator says whether
the orchestrator's own step ran.** A merge either moved a ref or it did not, on any project, with or
without tests — which is what N2 [344] («може таке бути, що десь не буде тестів») requires of anything
the orchestrator adds. **The discomfort is real and the distinction was never put to him**
(`ARCH-operability` §16.6). §12 Q6.

### 11.4 The run scope is not configuration

He requires three scopes [331]/[075]; `snf` says its three levels are the whole set
(OWNER-DECISIONS 3.6). §4.2 resolves it by making the run scope per-invocation state rather than a
fourth level, which changes nothing in his marketplace. **The cost:** a `--set` he makes tonight is
gone tomorrow, and there is no file he can edit to change it mid-run except `control.json`. That is
deliberate — the alternative is a fourth config level his own rules forbid.

### 11.5 Tier 2 verification sends a message he did not ask for

Д11 and R1-17 collide; §7.4 resolves it by confining tier 2 to commands he invoked. **One message per
run per required channel, self-identifying as a probe.** That is the knowing violation, and it is the
minimum that makes «переконатися, що це працює» mean anything more than "the token parses".

### 11.6 `sync` and `remove` are commands he never asked for

Both are in the the company baseline and both are earned by real state (a renamed board status; a run directory
tree under `$HOME`), but he named neither. They are specified so an implementer is not blocked, and
both are behind conservative defaults (`check`, `dry_run`). §12 Q11.

---

## 12. Needs the owner — round 2, in plain Ukrainian

Everything here is something I had to invent because he never decided it. Each is phrased as a question
he can answer in one sentence.

1. **Стопи.** Три окремі команди — `/orchestrator:stop-hard`, `/orchestrator:stop-soft`,
   `/orchestrator:stop-custom` — чи одна команда `/orchestrator:stop` з прапорцями `--hard`, `--soft`,
   `--custom`? Ти назвав три, я зробив три; яка з двох форм тобі зручніша о 3-й ночі?

2. **Статус із звичайного терміналу.** Слеш-команда в Клоді завжди коштує один хід моделі — це не
   обійти. Щоб «orchestrator status» працював у звичайному терміналі безкоштовно, треба покласти
   виконуваний файл у `~/.local/bin/orchestrator`. Ставити його (питаю один раз при налаштуванні), чи
   тобі вистачить слеш-команди?

3. **Що варте того, щоб тебе розбудити.** Три ситуації о 3-й ночі: (а) оркестратор зупинився на
   питанні до тебе; (б) впав сам оркестратор; (в) злиття пройшло, але нічого не перенесло. Яка з них
   будить тебе одразу, а яка чекає до ранку?

4. **Тихі години.** Чи є проміжок часу, коли сповіщення не приходять взагалі — навіть про те, що ран
   помер? Чи краще будити завжди?

5. **Запас ліміту.** Чи можна витрачати ліміт до нуля, чи треба лишати запас на твою власну роботу
   вранці? Якщо треба — скільки відсотків?

6. **Чи перевіряє оркестратор сам себе.** Ти сказав: перевірки — це справа процесу, не оркестратора.
   Але є вужча річ: чи має оркестратор перевірити, що **його власне** злиття реально перенесло коміти
   (шість рядків, працює без тестів і без репозиторію особливого вигляду)? Це не перевірка роботи, це
   перевірка його власної дії. Дозволяєш?

7. **Тікет, доданий командою `add`, з недостатнім описом.** Зараз я роблю так: записую його, ставлю
   мітку «needs-review» і **не** ставлю в чергу. Три альтернативи: (а) так і лишити; (б) відмовити і
   нічого не записувати; (в) все одно ставити в чергу. Що з цього?

8. **Чи має `add` тебе грилити.** У старому харнесі `add` допитував тебе, поки опис не ставав
   достатнім. Зараз я зробив це вимкненим за замовчуванням (`--grill` вмикає). Лишити вимкненим?

9. **Ранкові файли.** `report.md` і `next-run.md` лежать у run-директорії під `~/.orchestrator/`, а не
   в проєкті — бо в проєкті вони роздвоюються по worktree. Тобі так нормально, чи хочеш копію в
   репозиторії?

10. **Конфіг під час рану.** Зараз `config` можна запускати під час активного рану: він пише в файли, а
    оркестратор підхоплює на наступному тіку, і команда одразу каже, які ключі спрацюють зараз, які на
    наступному лейні, а які лише наступного рану. Чи має вона натомість відмовлятись писати, поки ран
    живий?

11. **Дві команди, яких ти не називав.** `sync` — перечитати дошку, коли там перейменували статуси.
    `remove` — прибрати конфіг і стан плагіна. Обидві є в базовому наборі твого маркетплейсу. Потрібні
    вони тобі взагалі, чи викинути?

12. **`stop-custom` і твої скрипти.** Зараз, якщо ти вкажеш виконуваний файл, оркестратор його
    запустить. Якщо текст — віддасть моделі перекласти в команди. Чи дозволяєш йому запускати твої
    скрипти, чи хочеш лише текстовий варіант?

13. **Коди виходу.** Я зробив таблицю кодів (0 — ок, 1 — треба людина, 8 — команда записана, але
    оркестратор її не підтвердив, 73 — вже є живий ран, і так далі). Ти будеш ними користуватись у
    своїх скриптах, чи це зайве і достатньо тексту?

14. **Ім'я і міграція.** Плагін називається `orchestrator`, старий — `harness`. Ім'я плагіна це його
    реєстровий ключ, тому це не перейменування, а новий плагін. Ти ставиш новий і видаляєш старий, чи
    хочеш, щоб вони якийсь час жили поруч?

15. **Ран без жодного конфігу.** За правилами твого маркетплейсу плагін має працювати без конфігу.
    Зараз без конфігу канал сповіщень — це просто термінал (рядок у журналі), а `run` відмовляється
    стартувати лише якщо провалилась доказова перевірка. Це правильний мінімум, чи без конфігу він
    взагалі не має стартувати?
