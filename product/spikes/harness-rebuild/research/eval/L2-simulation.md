# L2 — Simulation harness

**Layer:** L2 · **Date:** 2026-09-19 · **Scope:** a fake world in which the real orchestrator process
runs, unaware. Stub agent CLIs on PATH, scripted session behaviours, a virtual clock, a fake board,
and quota endpoints drivable to any state.

**Evidence labels.** **[V]** verified — I ran it on this machine in this session, output quoted.
**[C]** claimed — asserted by a document I read (`ground-*.md`, `FIELD-NOTES.md`, `ANALYSIS-01.md`).
**[I]** inferred — my reasoning from the two, marked so it can be argued.

A note on one source named in the brief: `…/scratchpad/context/harness-evidence.md` **does not exist
on this machine** [V] — `find` across the whole scratchpad tree returns nothing, and all three
sibling ground documents record the same absence independently. Everything attributed to the 34-hour
run therefore comes from `FIELD-NOTES.md` via `ground-failure-corpus.md` and is **[C]**.

---

## 0. Headline

Six things decide whether this layer is worth building, and I measured all six rather than asserting
them.

1. **A scenario fits in 12 lines and it discriminates.** I built a working prototype — stub agent,
   world, directives, assertions — and ran one scenario against two orchestrators: a naive one that
   logs `nudged` from the attempt, and a fixed one that reads back. Naive **exit=1** with
   `FAIL S-DELIV-01 log missing: delivery-failed` / `FAIL S-DELIV-01 log must not say: nudged`;
   fixed **exit=0**. [V] That is F-01/F-07 — the largest failure family in the record — caught by a
   12-line file, in 1.2 s, for nothing. Prototype preserved at
   `…/scratchpad/l2proto/` (`sim/lib/agent.py`, `sim/lib/simlib.sh`, `scen/S-DELIV-01.sim`, `sut/{naive,fixed}.sh`).
2. **Time is free and the whole fake world moves together.** A `sleep` shim that advances a world
   clock file turned `for i in 1..12; do sleep 600; done` — two simulated hours — into **0.678 s**
   real, with `date -u` reporting `00:26:40 → 02:26:40`. [V] A `date` shim fabricates *now* from the
   same file and passes relative arithmetic through correctly (`date -u -v-8d` computed off the fake
   now). [V]
3. **The single most important fidelity fact in this layer, and it is new.** The 1024-byte silent
   send ceiling that `ground-testing-agentic-systems.md` §11 identifies as `MAX_CANON` **is a
   property of the stub's line discipline, not of the terminal.** Same tmux, same payloads, two
   stubs:

   | chars | canonical-mode stub (`read` loop) | raw-mode stub (`tty.setraw`) |
   |---|---|---|
   | 100 / 1023 | delivered | delivered |
   | **1024** | **silently dropped** | **delivered** |
   | 2000 / 5000 / 8000 / 12000 / 16000 | silently dropped | delivered, byte-exact |
   | 17000+ | — | refused **loudly**: `tmux send-keys` → rc=1 `command too long` |

   [V] A real Claude Code TUI is in raw mode. So a simulation shipping only the obvious `read`-loop
   fake would "prove" a chunk-below-1024 rule the real client does not need, and would miss the real
   ceiling entirely. **Line-discipline mode is a declared scenario parameter here, and every delivery
   scenario runs in both modes.** This is the same class of error as §5.1 of
   `ground-what-exists-here.md` (a naive fake submits stranded text where the real TUI does not) —
   found twice now, from two directions, which is why §9 of this document is written the way it is.
4. **`kill` is a bash builtin and a PATH shim does not intercept it.** [V] A blast-radius scenario
   that shims `kill` and asserts "nothing was killed" therefore **passes vacuously**. The fix is
   `BASH_ENV=<preload>` with `enable -n kill`, which I verified intercepts the SUT, child `bash`
   processes and subshells — 3 of 3 — but **not** `sh -c`, which is 0 of 3. [V] Hence the canary
   rule in §7.3: every group that depends on a double asserts the double is alive before it asserts
   anything about the orchestrator.
5. **Cost of a full pass over 46 scenarios: ~64 s serial, ~20 s at `-j 4`, $0.00.** No model call, no network beyond
   `127.0.0.1`. Measured floors: a stub session spawn→ready is **0.60 s** (10 samples); a world-only
   scenario scaffold is **15 ms** (200 samples). [V]
6. **This layer must not be added to `tests/run-all.sh` until that runner is fixed.** It executes
   every plugin runner **twice** and dies silently with no message if a runner prints no `PASS=`
   line, skipping every later plugin [V, sibling; §3.1–3.3 of `ground-what-exists-here.md`]. A
   stateful 64-second suite behind that is a 128-second suite that can vanish without a word.

---

## 1. What this layer is, and what it is not

**L2 owns:** scenarios that need the *real orchestrator process* running against a *fake world* over
*simulated time*. Processes, terminals, files, locks, clocks, HTTP, concurrency.

**L2 does not own, and inherits from / defers to:**

| Not L2 | Belongs to | Why |
|---|---|---|
| `decide(world) → plan` table cases | L1 unit | pure function, no world needed, 10 000 cases in seconds |
| Detector regexes over recorded screens | L1 unit | pure function of a captured string |
| Config-precedence tables (Д1) | L1 unit | pure |
| Does the real `claude` CLI still behave like the stub | L4 conformance | only a real CLI can answer |
| Is the orchestrator's *judgement* good (R1-09, R1-14) | L5 LLM eval | needs a model |
| The mutation gate itself | L3 | it runs L1+L2 under mutation |

L2 duplicates two L1 concerns on purpose and says so: the status-line parser (L2-CTX-03) and the
banner detector (L2-DET-01) are unit-tested at L1 *and* driven end-to-end here, because the
85-minute loop [C] was not a parser bug in isolation — it was a parser bug **plus** an unbounded
action loop, and only the running system exhibits the second half.

**The requirement this layer exists to honour.** The orchestrator under test must not know it is a
simulation. Concretely: **no orchestrator source file may read any `SIM_*` variable.** That is
checkable, and it is the one legitimate use of `grep` under the house rule (grep may prove absence,
never presence): `grep -rn 'SIM_' plugins/orchestrator/{bin,lib}/ && fail`. Everything the
simulation does to the orchestrator is done through PATH, `BASH_ENV`, `HOME`, cwd, and the
environment variables the orchestrator legitimately reads anyway.

---

## 2. Directory layout

```
plugins/orchestrator/
  tests/
    run.sh                      # tier 0+1+2 entry point; last line: PASS=<n>  FAIL=<m>
    lib/assert.bash             # shared with L1
    sim/
      run-scenarios.sh          # the L2 runner (§7)
      bin/                      # fake binaries, prepended to PATH
        claude codex glm        #   the three agent platforms (§3)
        gh curl                 #   board + quota transports (§5, §6)
        date sleep              #   the virtual clock (§4)
        docker ps pkill kill    #   the world recorder (§8)
        preload.bash            #   BASH_ENV: `enable -n kill`; nothing else
      lib/
        agent.py                # the pty stub agent core, ~250 lines (§3.2)
        simlib.sh               # scenario directives + assertions, bash 3.2 (§7.1)
        world.sh                # build / teardown / leak-check a world (§7.2)
        quotad.py               # 127.0.0.1 HTTP stub, file-driven (§6)
        board.sh                # fake board: local files + `gh api` surface (§5)
      behaviours/               # named session behaviours, *.beh (§3.3)
      fixtures/
        screens/                # recorded status lines and panes
        usage/                  # quota cassettes, redacted at record time
        transcripts/            # recorded .jsonl, for recovery-parser fixtures
        tickets/                # hostile ticket bodies
      scenarios/                # *.sim — one scenario per file (§7.1)
      goldens/                  # normalised argv / launcher / decision-log goldens
    mutations/                  # *.mut — L3's meta-gate reads these (§10)
```

**Why bash 3.2 is a hard constraint.** `/bin/bash` on this machine is **3.2.57** [V]. No associative
arrays, no `mapfile`, no `${var^^}`. Every line of `simlib.sh` and every `.sim` file must run under
it, and `shellcheck` must be clean. `python3` is **3.9.6** system-installed [V] — the stub agent may
use it; the scenario language may not require it.

**Toolchain, verified on this machine.** Present: `tmux 3.6a`, `expect`, `script`, `python3 3.9.6`
(with `pty`), `jq`, `gh`, `docker`, `shellcheck`, `perl`, `sqlite3`, `timeout`/`gtimeout`, `stdbuf`,
`shlock`, `lockf`. **Absent: `socat`, `flock`, `bats`, `faketime`, `yq`.** [V] `timeout` lives in
`/usr/local/bin`, so it is **not on the `env -i` PATH** — anything L2 runs under a scrubbed
environment must not depend on it.

---

## 3. The stub agents

### 3.1 The interface the orchestrator sees

Three executables on PATH — `claude`, `codex`, `glm` — chosen to span the axes R1-07/R1-11 name.

| | `claude` | `codex` | `glm` (the exotic one) |
|---|---|---|---|
| Surface | interactive TUI over a pty | TUI **or** `--print` headless | **headless only**, JSON-lines on stdout |
| Line discipline | raw | raw | n/a — stdin is a pipe, not a tty |
| Status line | `<model>  ctx NN%  N shells` | `ctx: NN%` on a separate line | no status line; `{"ctx_pct":NN}` events |
| Quota endpoint | `/api/oauth/usage` | `/v1/usage` | **none — pay-as-you-go** |
| Session identity | `--session-id <uuid>` | `--session <name>` | `--run-id <n>` |
| Resume | `--resume <id>` | `--continue` | no resume; state file only |
| Account switching | env token | profile dir | `GLM_API_KEY` |

The divergences are deliberate. `glm` having **no quota scheme at all** is R1-06's explicit case
("including none/pay-as-you-go"); headless-only is R1-11's; no-resume is R1-10's per-platform
recovery. An adapter abstraction that only ever met Claude Code will fail against `glm` in this
layer rather than at 03:00 against a real account.

Every stub does three things before anything else:

```
printf '%s\t%s\t%s\t%s\n' "$SIM_AGENT_ID" "$PWD" "$(env_fingerprint)" "$*" >> "$SIM_WORLD/argv.log"
```

argv, cwd and a fingerprint of the environment variables the platform cares about. That one line is
the whole of L2-PLT-01 and it catches F-54 (a launcher whose session id said phase 5 while it `cd`'d
into the phase-4 worktree [C]) in microseconds.

### 3.2 The stub agent core (`agent.py`)

One process per session. Responsibilities:

- **Own the pty in a declared line-discipline mode** (`raw` | `canonical`), because §0.3 proves the
  mode changes the answer.
- **Maintain a screen file** `agents/<id>.screen`, rendered from a format string, so the
  orchestrator's screen scraper reads a real capture and the scenario can assert on what it read.
- **Maintain a submitted-inbox** `agents/<id>.inbox` — one JSON line per turn the agent actually
  accepted. **This is the ground truth of delivery.** Nothing else in this layer is.
- **Maintain a transcript** `agents/<id>.jsonl` in the platform's own transcript shape, so the
  orchestrator's F-05 confirmation ("read the transcript, not the screen") has something to read,
  and so the R1-10 transcript-recovery parser has a fixture.
- **Run its timeline against the *virtual* clock**, not wall time. The agent polls
  `$SIM_WORLD/clock` every 10 ms of real time and fires any timeline event whose virtual time has
  passed. When the orchestrator's `sleep 600` jumps the clock, the agent catches up in the same
  10 ms. Without this coupling the agents would be the only thing in the world still living in real
  time.
- **Apply a submit policy** — the model of TUI input semantics:

  | policy | bare Enter on a non-empty input line | oversize payload |
  |---|---|---|
  | `tui` | **strands** the text, no turn (real Claude Code [C], reproduced [V]) | raw: delivered |
  | `canonical` | submits it (a naive `read`-loop fake [V]) | **silently dropped at 1024** [V] |
  | `swallow` | consumes the keystroke, no turn, text stays | drops everything |
  | `echo` | submits, and echoes the text back into the screen | delivered |

### 3.3 The behaviour scripting format (`behaviours/*.beh`)

Line-oriented, no parser beyond `while read`, `shellcheck`-clean, diffable. Statics first, then a
timeline in **virtual seconds since session start**, then input reactions.

```
# behaviours/fills-context.beh
mode         raw
submit       tui
status       "{model}  ctx {ctx}%  {shells} shells"
model        "Opus 4.8"
ctx          12
shells       0
AT 0     print     "FAKE AGENT READY"
AT 0     heartbeat
AT 300   ctx       41
AT 1200  ctx       78
AT 2400  ctx       91
AT 2400  heartbeat
ON  "/compact"     compact_if shells==0 else consume_as_text
ON  "^continue$"   heartbeat
```

**Verbs.** `print <text>` · `heartbeat` · `ctx <n>` · `shells <n>` · `status <fmt>` · `model <name>`
· `banner <text>` · `ask <question>` · `silent <secs|forever>` · `exit <code>` ·
`spawn_child "<cmd>"` · `spawn_child_loop "<cmd>" every <s>` · `fail_with "<stderr>"` ·
`submit <policy>` · `strand "<text>"` · `rename_pane <name>`.

**Reactions.** `ON "<regex>" <verb...>`, plus the two compound reactions the corpus demands:
`compact_if shells==0 else consume_as_text` (F-08) and `answer_then_idle` (the finished-and-idle
case, F-14).

**The shipped behaviour library** — exactly the eight the brief names, plus seven the failure corpus
forces:

| Behaviour | What it does | Corpus |
|---|---|---|
| `finishes` | works, heartbeats, prints a completion marker, idles | P-03 |
| `stalls-silent` | heartbeats twice, then nothing, forever | F-24, F-28 |
| `dies-midturn` | accepts a turn, prints two lines, `exit 1` | R1-09, Д10 |
| `asks-question` | `ask "which database?"` then idles awaiting an answer | Д6, P-01 |
| `quota-wall` | prints a real usage-cap banner as the last line, then idles | R1-06 |
| `fills-context` | ctx climbs 12→41→78→91 over 40 simulated minutes | F-37, F-39 |
| `banner-in-prose` | prints `I saw a "usage limit reached" banner, so I paused.` mid-screen | **F-40, F-63** |
| `exit-zero-empty` | prints `READY`, does nothing, `exit 0` | F-29, F-33 |
| `tui-strands` | `submit tui` + pre-loaded `strand` text | F-01, F-02, F-04 |
| `swallow-compact` | `shells 1`; `/compact` consumed as ordinary text | F-08 |
| `long-turn` | one 14-simulated-minute turn with no heartbeat, then finishes | **F-24** |
| `poll-forever` | `spawn_child_loop "until grep X f; do sleep 5; done" every 0` | **F-25** |
| `retry-identical` | 40 structurally identical failures, timestamps differing | F-26, Д5 |
| `echo-idle` | 3 466 identical `echo idle` tool lines, mean 2.54 s apart | **F-38** |
| `drifted-pane` | renames its pane; its identity token no longer matches the registry | **F-06** |

Every one of these is data, not code. Adding the sixteenth costs eight lines.

---

## 4. The virtual clock

Two shims and one file. `$SIM_WORLD/clock` holds an epoch integer.

**`bin/date`** — fabricates *now* from the file, delegates to `/bin/date` whenever the caller is
parsing a supplied timestamp rather than asking for the present (`-j`, `-r`, `-d`, `-f`):

```sh
[ -n "${SIM_WORLD:-}" ] && [ -f "$SIM_WORLD/clock" ] || exec /bin/date "$@"
for a in "$@"; do case "$a" in -r|-j|-f|-d|--date) exec /bin/date "$@";; esac; done
exec /bin/date -r "$(cat "$SIM_WORLD/clock")" "$@"
```

Verified working for `+%s`, `-u +%Y-%m-%dT%H:%M:%SZ`, bare `date`, relative arithmetic
`-u -v-8d +%Y%m%d%H%M` computed off the fake now, and pass-through of `-j -f`. [V]

**`bin/sleep`** — the virtual scheduler. Advances the clock by the requested amount and returns
immediately, recording the request:

```sh
n=$(cat "$SIM_WORLD/clock"); echo $(( n + ${1%.*} )) > "$SIM_WORLD/clock"
echo "SLEEP $1" >> "$SIM_WORLD/sleeps"; exit 0
```

Twelve `sleep 600` calls — two simulated hours — completed in **0.678 s** with the clock and `date`
moving in lockstep. [V] A 34-hour run is therefore a few seconds of wall time, and the 44 791-second
stall that `FIELD-NOTES` records as the real observed peak [C] is a scenario, not a legend.

**Three holes, stated because a hidden hole is worse than a known one.** [V]

- `$SECONDS` and `$EPOCHREALTIME` are **shell builtins** — unshimmable. Design rule, lintable: no
  orchestrator component reads them.
- `read -t <n>` is a **builtin** and will block for real seconds. Design rule: the tick loop waits
  via `sleep`, never `read -t`. Also lintable.
- A component written in Python or Node calling `time.time()` bypasses both shims entirely. Hence
  the clock is **two mechanisms, not one**: the PATH shim catches shell code that never cooperated,
  and a declared `now()` seam plus `ORCH_CLOCK_FILE` covers everything else. L2 asserts they agree:
  a canary scenario advances the clock and asserts every component's reported "now" moved.

---

## 5. The fake board

Two backends behind one stub, because F-50 and §12.2 of `ground-testing-agentic-systems.md` both say
the bug is *divergence between backends*, not either backend alone.

**Local backend.** `$SIM_WORLD/board/<id>` — one file per ticket, `key=value` lines plus a body after
a blank line. Exactly the shape a real local registry would use, so the orchestrator's real local
driver runs unmodified against it.

**GitHub backend.** `bin/gh` intercepts the verbs the orchestrator actually uses and serves them from
the same `board/` directory:

```
gh issue list --label ready --json number,title,labels
gh issue edit <n> --add-label in-progress --remove-label ready
gh issue comment <n> --body-file -
gh api repos/:owner/:repo/issues/<n>
```

Every call is logged to `$SIM_WORLD/gh.log` with argv and stdin, so a scenario can assert on *what
the orchestrator told the board*, which is R1-04's "the board is a working surface" made testable.
Fault modes are driven from `$SIM_WORLD/board.faults`: `500`, `403 rate limit`, `timeout`,
`stale-etag`, `label-write-succeeds-but-does-not-persist` (the board equivalent of F-29 — an
operation reporting success without an effect).

**Both backends run the same scenario file.** `board_backend local|github` is a scenario directive;
the runner expands any scenario carrying `meta backends both` into two runs. A divergence is a FAIL
naming the field that differed. That is the model-based test of §12.2, and it is what would have
caught `done` leaving `blocked` in place [C].

---

## 6. Quota endpoints

`lib/quotad.py` — a ~60-line `http.server` on `127.0.0.1:<port>`, reading its entire response table
from `$SIM_WORLD/quota/<platform>.json` **on every request**, so a scenario flips the world's quota
state mid-run without restarting anything. Verified: served `{"five_hour":{"utilization":91}}` in
**13 ms**, then returned `401` on the next request after a file write, no restart. [V]

`bin/curl` routes any request whose host matches a configured production hostname to the local stub
and records the full request to `$SIM_WORLD/http.log`; everything else it refuses with a loud error,
so **a scenario can never accidentally reach the network**.

Drivable states, one cassette each: `ok`, `session-89/90/90.0001/91`, `weekly-99.5` (fractional
percents are real [C]), `null-percent`, `string-percent`, `malformed-json`, `empty-body`,
`401 authentication_error`, `429`, `hang` (accept, never respond), `connection-refused`,
`schema-old` (`.limits[].group/.percent`) and `schema-new` (`five_hour.utilization`).

**The last two are not hypothetical.** `ground-testing-agentic-systems.md` §4.3 records that the
shipped parser wants one shape while the owner's own `CLAUDE.md` documents the other, that the live
endpoint 401s so neither could be confirmed, and that fed the documented shape the shipped parser
returns `UNKNOWN` [V, sibling]. L2 cannot resolve which is live — that needs a working token and
belongs to L4's re-record job. What L2 **can** do, and must, is assert that the orchestrator
distinguishes *"this body is a schema I do not recognise"* from *"this body says I am fine"*. A
cassette of the wrong schema, replayed forever, is confidently wrong; a cassette that fails a schema
conformance check the day the shape changes is an alert. L2-QUO-01 asserts the conformance check
exists.

`glm` has no endpoint. Requesting a verdict for a `glm` role must return a typed
`NotApplicable`, not `UNKNOWN`, and must not gate anything — R1-06's "including none".

---

## 7. How a test is written, run, and how it fails loudly

### 7.1 The scenario file

One file, one scenario, sourced by the runner. The prototype below is the real thing, reduced: 12
lines, and it separates a correct orchestrator from an incorrect one. [V]

```sh
. "$SIM_LIB"
meta id        L2-DEL-01
meta title     bare Enter does not submit a stranded line
meta catches   F-01 F-07
meta mutation  M-DEL-readback
meta needs     pty
world_time     2026-09-19T02:00:00Z
project        git dirty=.planning/milestone.lock
board_ticket   T-1 ready "fix the footer"
agent          w1 platform=claude role=worker behaviour=tui-strands strand="carry on with the queue"
quota          claude 200 usage/ok-12-30.json
control_file   ""
run_orchestrator --ticks 3
assert_inbox   w1 count=0
assert_log     contains='delivery-failed w1'
assert_log     absent='nudged'
assert_no_leaks
```

**Directives** (all bash 3.2 functions in `simlib.sh`; `meta` lines are also greppable without
running, so the runner can index the suite): `meta` · `world_time` · `clock_advance` ·
`project <git|plain> [dirty=…] [worktrees=N]` · `board_ticket <id> <status> <title> [body=file]` ·
`board_backend` · `board_fault` · `agent <id> platform= role= behaviour= [mode=] [strand=] [ctx=] [shells=]`
· `quota <platform> <http-code> <cassette>` · `control_file <content>` · `control_append <line>` ·
`notify_channel <ok|401|timeout>` · `world_process <cmd>` (a process the orchestrator did **not**
start) · `crash_at <step>` · `delay <name> <seconds>` (the race-window injector) ·
`run_orchestrator [--ticks N] [--until EXPR] [--env-i]` · `restart_orchestrator`.

**Assertions**: `assert_inbox` · `assert_screen` · `assert_log` · `assert_argv` · `assert_gh` ·
`assert_http` · `assert_notified` · `assert_state` · `assert_killed_set` · `assert_golden` ·
`assert_exit` · `assert_idempotent` · `assert_no_leaks` · `assert_untouched <world_process>`.

### 7.2 The world

`world.sh` builds a `mktemp -d` containing `agents/ board/ quota/ run/ project/ home/`, then runs the
orchestrator with:

```
PATH="$SIM/bin:$PATH"          BASH_ENV="$SIM/bin/preload.bash"
HOME="$W/home"                 ORCH_PROJECT="$W/project"   ORCH_USER_DIR="$W/home/.orchestrator"
SIM_WORLD="$W"                 # read by the stubs only — never by the orchestrator (§1)
cd "$W/project"
```

`preload.bash` contains exactly one statement — `enable -n kill` — because that is the only way a
PATH shim for `kill` is ever reached [V]. Each scenario gets a **private tmux server**
(`tmux -L sim-$$`), which sidesteps the verified hazard that closing the last pane kills the shared
tmux server [V, sibling] and makes `-j 4` safe.

### 7.3 Loud failure — six mechanisms, each aimed at a recorded silent-pass

1. **Canaries first (F-61's positive-control rule).** `L2-CANARY-*` run before every group and prove
   the doubles are live: the `kill` shim records a real `kill -0`; the clock shim moves `date`; the
   quota stub answers; the pty agent reaches `READY`. **A dead canary fails its whole group.**
   Without this, §0.4's builtin-`kill` hole makes an entire blast-radius group green forever.
2. **A declared floor.** `run-scenarios.sh` reads `EXPECT_SCENARIOS` from a committed file and fails
   if the discovered `.sim` count differs. This is the direct fix for the measured defect that a
   runner claiming `PASS=1 FAIL=0` is accepted with no baseline [V, sibling], and for
   `FIELD-NOTES`' 346-of-382 incident [C].
3. **Attribution before execution.** The runner prints `>>> <id>` *before* running each scenario and
   a `<<< <id> ok|FAIL|TIMEOUT` after. A scenario that hangs or aborts is named. This is the fix for
   the measured silent abort that skipped every later plugin [V, sibling].
4. **`bash -n` and `shellcheck` over every `.sim`** in tier 0, so a scenario with a syntax error is a
   FAIL, never a silent skip.
5. **Idempotence is asserted, not hoped for.** The runner executes the suite twice by default and
   diffs the results; a difference is a FAIL. `run-all.sh` runs every plugin twice anyway [V,
   sibling], so a leaked tmux session or lock file would otherwise show up as flake and be blamed on
   the harness.
6. **Leak detection after every scenario.** No surviving `tmux -L sim-*` server, no child processes
   under the scenario's pgid, world directory removed. A leak is a FAIL attributed to the scenario
   that leaked.

Final line, for `run-all.sh` compatibility: `orchestrator sim: PASS=<n>  FAIL=<m>`.

---

## 8. The world recorder (blast radius)

Four shims write to `$SIM_WORLD/world.log`: `kill`, `pkill`, `ps`, `docker`. `ps` serves a synthetic
process table the scenario populates, including — critically — processes the orchestrator did **not**
start, with command lines that deliberately contain the patterns the orchestrator might match on.
This is F-45 reproduced exactly: `pkill -f 'playwright test'` killed an unrelated lane because every
lane's own prompt text contained that literal string [C].

`assert_killed_set` compares the recorded target set against the set the scenario declares the
orchestrator started. It is a **set-containment** assertion: `killed ⊆ started`. `assert_untouched`
is its negative twin for a specific foreign process.

Docker is recorded, never run: `docker compose down -v` is an argv assertion, not a container.

---

## 9. Scenario catalogue

46 scenarios, 11 groups. Each: precondition · trigger · expected · assertion · what it catches.
`[pty]` marks a scenario that spawns stub sessions (~0.6 s floor each); everything else is
world-only (~15 ms).

### A · Delivery — the largest family in the record

**L2-DEL-01 · Bare Enter does not submit a stranded line** `[pty]`
- **Pre** a session in `submit tui` mode with `carry on with the queue` sitting unsent on its line.
- **Trigger** the watch decides the session is stale and issues its escalation keystroke.
- **Expect** no turn is created; the orchestrator records a delivery failure and escalates.
- **Assert** `assert_inbox w1 count=0` · `assert_log contains='delivery-failed'` · `assert_log absent='nudged'`.
- **Catches** F-01, F-07 — five operator instructions lost in one run, logged as delivered [C].
  **Proven discriminating here: naive SUT exit=1, fixed SUT exit=0.** [V]

**L2-DEL-02 · `send` refuses to type over a non-empty line** `[pty]`
- **Pre** `PENDING` on the line — in the recorded case, a human's own `push master` [C].
- **Trigger** any automated `send "NEW"`.
- **Expect** a distinct `line-busy` status; `PENDING` preserved and surfaced to the control channel.
- **Assert** `assert_inbox w1 count=0` · `assert_screen w1 contains='PENDING'` · `assert_log contains='line-busy'`.
- **Catches** F-02.

**L2-DEL-03 · Delivery-ceiling sweep, both line disciplines** `[pty]`
- **Pre** one fresh session per size per mode.
- **Trigger** payloads of 10, 100, 200, 500, 1023, 1024, 2000, 5000 characters.
- **Expect** every payload either arrives byte-identical or is **refused loudly**; the backend's
  ceiling is *discovered at startup*, not assumed.
- **Assert** inbox content hash equals the payload hash, or an explicit `payload-too-large` record —
  never exit 0 with an empty inbox.
- **Catches** F-03, and the §0.3 finding: canonical mode drops 1024 **silently**, raw mode does not,
  and `tmux send-keys` refuses **loudly** above ~16 KB [V]. A suite that tests one mode is wrong
  about the other.

**L2-DEL-04 · The recovery ladder is transactional** `[pty]`
- **Pre** a failed delivery, text still on the line.
- **Trigger** the recovery ladder runs every rung.
- **Expect** at the end the captured text is either in the inbox or still on the line — never in
  neither.
- **Assert** `assert_inbox` ∪ `assert_screen` covers the captured string; a run where both miss is a FAIL.
- **Catches** F-04 — a recovery that cleared the line without submitting, destroying what it was
  recovering [C].

**L2-DEL-05 · Identity read-back before delivery** `[pty]`
- **Pre** behaviour `drifted-pane`: the session renames its pane so the registry's addressing is stale.
- **Trigger** any delivery.
- **Expect** refusal with an identity mismatch, not a blind write to whatever now holds that address.
- **Assert** `assert_inbox w1 count=0` · `assert_inbox w2 count=0` · `assert_log contains='identity-mismatch'`.
- **Catches** F-06 — a 149-minute undetected stall from pane drift [C].

**L2-DEL-06 · The transcript, not the screen, is the receipt** `[pty]`
- **Pre** behaviour `echo`: the stub paints the text onto the screen but writes no transcript turn.
- **Trigger** a delivery.
- **Expect** delivery reported **failed** — screen echo is not evidence.
- **Assert** `assert_log contains='delivery-failed'` while `assert_screen contains='<text>'` holds.
- **Catches** F-05, F-07.

### B · Liveness — the signals, never the judgement

Per `ground-failure-corpus.md` §11, R1-09 delegates the decision to the orchestrator; these
scenarios assert only **what it is told**.

**L2-LIV-01 · A healthy long turn is not a stall** `[pty]`
- **Pre** behaviour `long-turn`: one 14-simulated-minute turn, no heartbeat, but a live child process
  and growing file output.
- **Trigger** the stall ceiling elapses (virtual clock).
- **Expect** `no-action`. Every combination in the decision table where any progress indicator is
  positive must yield `no-action`.
- **Assert** `assert_inbox w1 count=0` · `assert_log absent='STALLED'`.
- **Catches** F-24 — six false nudges in one run, `STALLED` raised eight or more times against
  demonstrably healthy sessions [C], and the false positive is what *triggers* the whole delivery
  family.

**L2-LIV-02 · A shell that can never exit is `suspect`, not `busy`** `[pty]`
- **Pre** behaviour `poll-forever`: `until grep X f; do sleep 5; done` against a file finished 45
  simulated minutes ago.
- **Trigger** the child-lifetime ceiling elapses.
- **Expect** classification `suspect`, reported; the orchestrator decides what to do, the test does
  not care.
- **Assert** `assert_state session=w1 classification=suspect` · `assert_log contains='suspect'`.
- **Catches** F-25 — invisible to every detector simultaneously, and it also blocks compaction (F-08).

**L2-LIV-03 · Identical failures are counted after normalisation; repetition is reported**
- **Pre** behaviours `retry-identical` (40 failures differing only in timestamp) and `echo-idle`
  (3 466 identical calls, mean 2.54 s apart — the real measured numbers [C]).
- **Trigger** the stream.
- **Expect** Д5 fires **exactly once** at three; three *structurally different* failures do not fire;
  the repetition detector reports the `echo idle` run and attributes the context growth to it.
- **Assert** `assert_notified count=1` · a negative arm with varied errors asserting `count=0` ·
  `assert_state repetition.top_command='echo idle' repetition.count>=3000`.
- **Catches** F-26 (33 m 31 s and 184 k tokens retrying an unreachable daemon [C]), F-38 (77 % of one
  lane's context growth [C]).

**L2-LIV-04 · The escalation ladder has a terminal rung that reaches the human** `[pty]`
- **Pre** behaviour `stalls-silent`; a notification recorder.
- **Trigger** advance the virtual clock along the configured thresholds, then past the last one.
- **Expect** each rung fires once in order; the final rung **always** fires; no path ends in silence.
- **Assert** `assert_notified` sequence equals the golden ladder; a run reaching the ceiling with zero
  notifications is a FAIL.
- **Catches** F-28 — the ladder had one rung, and the observed peak before any nudge was 44 791 s
  (12.4 h) [C].

**L2-LIV-05 · The global liveness backstop, independent of every detector**
- **Pre** eight ready tickets, zero running lanes, orchestrator idle, all detectors deliberately
  stubbed to return `healthy`.
- **Trigger** T elapses.
- **Expect** escalation anyway. *Ready work + free capacity + no progress for T ⇒ escalate* must hold
  even when the classifier is wrong.
- **Assert** `assert_notified contains='idle-with-ready-work'`.
- **Catches** F-27 — 35+ minutes idle with eight ready tickets because the state was `held`, which no
  rule covered [C]. The corpus calls this the highest-value single test in its family, precisely
  because it does not depend on any detector being right.

### C · Context

**L2-CTX-01 · Compact is gated on the shell count** `[pty]`
- **Pre** behaviour `swallow-compact`, `shells 1`.
- **Trigger** the ctx threshold is crossed.
- **Expect** compact **deferred** and reported as deferred; with `shells 0`, attempted.
- **Assert** `assert_inbox w1 absent='/compact'` in the first arm; present in the second.
- **Catches** F-08 — three attempts in one day consumed as ordinary text while the session drifted
  91 %→95 % and auto-compacted [C].

**L2-CTX-02 · Compact is a transaction with a post-condition** `[pty]`
- **Pre** two arms: a stub that compacts (ctx 91→8) and one that does not.
- **Trigger** the threshold.
- **Expect** before/after percentages recorded; the non-compacting arm reports failure and escalates.
- **Assert** `assert_state compact.before=91 compact.after=8` · non-compacting arm:
  `assert_log contains='compact-failed'` and `assert_notified count>=1`.
- **Catches** F-39, and it is the testable form of R1-08's "повинен бути механізм, який гарантовано
  робить цю дію".

**L2-CTX-03 · Status-line parsing, end to end** `[pty]`
- **Pre** stubs painting `Opus 4.8`, a wrapped line, a non-ASCII space, an unknown model name, and a
  line scrolled out of the capture window.
- **Trigger** a normal tick.
- **Expect** a percentage, or an explicit `unreadable`/`unknown` — never a silent default; N
  consecutive unreadable reads escalate.
- **Assert** per-fixture parse result; `assert_log absent='ctx=0%'` for every unreadable fixture;
  `assert_notified` after N.
- **Catches** F-60 (`Opus 4.8` missed a regex, three validators degraded silently [C]), F-62 (a
  scrolled-off `timeout 1800s` silently became a 900 s default, halving the stall ceiling [C]), F-63.

**L2-CTX-04 · Soft and hard threshold semantics at the boundary** `[pty]`
- **Pre** thresholds soft=85, hard=90; a stub whose ctx is driven to 84.9, 85, 85.0001, 89.9, 90, 91.
- **Trigger** the virtual clock.
- **Expect** soft waits for the configured step boundary; hard acts now; each fires **once**.
- **Assert** `assert_state` transitions equal the golden table; duplicate firings are a FAIL.
- **Catches** the boundary class the corpus records as a near-miss in the shipped quota gate, where an
  integer comparison with `2>/dev/null` would have silently taken the no-pause branch [C].

### D · Quota

**L2-QUO-01 · Unreadable never becomes OK, and blindness escalates**
- **Pre** cassettes `malformed-json`, `401`, `hang`, `null-percent`, `string-percent`, `schema-old`
  against a `schema-new` parser.
- **Trigger** every tick.
- **Expect** `UNKNOWN` in all six, never `OK`; N consecutive unknowns trigger the configured
  notification and stop semantics; the run record distinguishes *quota was fine* from *quota was
  never read*.
- **Assert** `assert_state quota.verdict=UNKNOWN` per cassette · `assert_notified count=1` after N ·
  `assert_state quota.reads_ok=0 quota.reads_unknown>=N`.
- **Catches** F-16 — `weekly_all=unreadable%` recurring across many days while `limits.on_unreadable`
  defaulted to `proceed` [C, and VERIFIED in the old source]. **The old 51-test suite passed this
  mutation 51/51** [V, sibling].

**L2-QUO-02 · `401` is `Unauthenticated`, not `Unknown`**
- **Pre** the `401 authentication_error` cassette — which is, verbatim, what the live endpoint
  returned on this machine [V, sibling].
- **Trigger** a read.
- **Expect** a typed error routed immediately to the notification channel; and the pre-run
  verification must make a real authenticated call per configured account and refuse to start on 401
  — not merely check that a key is present.
- **Assert** `assert_state quota.error=Unauthenticated` · `assert_notified` · a second arm:
  `assert_exit run_orchestrator != 0` with `assert_log contains='preflight: account claude/pool unauthenticated'`.
- **Catches** F-18 — 82 minutes of blind operation [C].

**L2-QUO-03 · A reading is labelled with the account it came from**
- **Pre** two accounts with different utilisations; roles `orchestrator` and `worker` bound to
  different ones.
- **Trigger** a verdict request for `worker`.
- **Expect** the record carries `worker`'s account identifier; a mismatch is a hard error.
- **Assert** `assert_state quota.account=<worker-acct>` · mismatch arm asserts a non-zero exit.
- **Catches** F-17 — a healthy reading for one account used to decide about another [C].

**L2-QUO-04 · An account switch starts a new series and emits no phantom event**
- **Pre** readings recorded for account A at 26 %; a mid-run control-file reassignment to B at 6 %.
- **Trigger** the reassignment (soft).
- **Expect** A's series closes, B's begins; **no** threshold-crossing event; already-running sessions
  stay attributed to their **boot** account, only new spawns use the new one.
- **Assert** `assert_state series.A.closed=true series.B.len=1` · `assert_notified count=0` ·
  `assert_state session.w1.account=<A>`.
- **Catches** F-19 — a weekly reading falling 26 %→6 % from an account switch alone [C].

**L2-QUO-05 · A platform with no quota scheme**
- **Pre** a `glm` role; no endpoint exists.
- **Trigger** a verdict request.
- **Expect** `NotApplicable`, not `UNKNOWN`; nothing is gated; no escalation.
- **Assert** `assert_state quota.glm=NotApplicable` · `assert_notified count=0` · `assert_log absent='UNKNOWN'`.
- **Catches** the R1-06 case no historical record covers at all — pay-as-you-go. A design that
  collapses "no limits" into "unknown limits" would pause the run for ever.

**L2-QUO-06 · Pause and resume across the reset boundary, with crash points**
- **Pre** quota at 97 %, reset at `now+3600`; the pause path enumerated into steps.
- **Trigger** the pause; then advance the clock to reset−1, reset, reset+1; separately, crash at
  **every** instruction boundary of the pause path and restart.
- **Expect** `paused ⇒ resume_at > pause_at` always; exactly one resume, never in the pause tick;
  after any crash the recovered state is legal and is **never** "manual owner stop" when no human
  issued one; a `STOP` with no attribution is rejected as corrupt and escalated, not obeyed.
- **Assert** a clock sweep including the epoch, far past, far future and a DST boundary; a crash-point
  loop; `assert_state stop.attributed_by!=""`.
- **Catches** F-21 / F-22 / F-23 — one bug fixed twice, badly, the third still open [C]. The corpus
  names this trio the single best acceptance test for the state layer.

**L2-QUO-07 · A detached entry point under a scrubbed environment**
- **Pre** `run_orchestrator --env-i`: `env -i` plus only the variables the component **declares** it
  needs.
- **Trigger** startup of each detached entry point (health-checker, notifier, watch).
- **Expect** either success or a loud startup failure — never a plausible-looking degraded result.
- **Assert** `declared_env ⊇ actually_read_env` for each component; `assert_log absent='UNKNOWN'`
  unless the scenario asked for it; a silent degradation is a FAIL.
- **Catches** F-20 — `launchd`/`nohup` start with no environment, and three scripts had to export
  their `gh` account themselves [C]. Also catches the verified environment hazards: `find` resolves to
  `bfs 4.1.1` interactively but `/usr/bin/find` under `env -i`, with different flag dialects, and
  `timeout` is in `/usr/local/bin` and simply absent from the scrubbed PATH [V].

### E · Control file and stops

**L2-CTL-01 · A tick against a read-only inbound file must succeed**
- **Pre** the inbound control file `chmod 0444`.
- **Trigger** three ticks.
- **Expect** success. An implementation that truncates-and-rewrites the file it reads **cannot** pass
  this, which is the point.
- **Assert** `assert_exit 0` · `assert_log absent='Permission denied'`.
- **Catches** F-10 — the control file rebuilt from scratch every tick, silently destroying every
  external write all night; line 5620 of that log reads `NO ONE IS BEING TOLD` [C]. Verified in the
  old source at `harness-run.sh:226`/`:361` [C]. The corpus calls this the highest-leverage test it
  contains, and it costs one `chmod`.

**L2-CTL-02 · An appended command survives N ticks and acts exactly once**
- **Pre** an empty control file; a second process appends `stop-soft` at tick 2.
- **Trigger** ten ticks.
- **Expect** the command is still readable after tick 10 and was acted on once.
- **Assert** `assert_state stop.mode=soft stop.applied_count=1` · the file still contains the line.
- **Catches** F-10, Д12.

**L2-CTL-03 · No reader ever observes a torn or zero-byte control file**
- **Pre** a concurrent reader looping for the duration of 100 writes.
- **Trigger** 100 writes, with `delay control-write 0.005` widening the window.
- **Expect** only complete, well-formed documents observed; "empty", "absent" and "unreadable" are
  three distinguishable states.
- **Assert** zero torn observations; a `truncate-then-write` implementation fails within a few
  iterations.
- **Catches** F-11 — the staging file found truncated to zero bytes on every pass, one of the two
  factors compounding the 85-minute runaway [C].

**L2-CTL-04 · Hard beats soft, under any interleaving**
- **Pre** a soft stop pending.
- **Trigger** a hard stop written in the same tick, and in the next, and before.
- **Expect** hard wins in all orderings; applied at the next tick, not the current one and not two
  later.
- **Assert** a table over the interleavings; `assert_state` per row.
- **Catches** Д12/Д7/R1-07 — the soft/hard vocabulary appears in four separate requirements and has
  never been tested once.

**L2-CTL-05 · The channel resolves to one absolute location from every cwd**
- **Pre** `project git worktrees=2`; a simulated session in each worktree writes a question by
  relative path.
- **Trigger** the orchestrator's single channel reader.
- **Expect** both questions seen; and a channel path that resolves differently from two cwds is
  **rejected at configuration time**.
- **Assert** `assert_state questions.count=2` · a second arm asserting a non-zero exit at config time.
- **Catches** F-12 — `QUESTIONS.md` forked into a worktree copy and an owner-facing question sat
  invisible for an hour [C]. Д4's worktree default makes this the normal case.

### F · Lifecycle

**L2-LIFE-01 · Two orchestrators race, across a delay ladder**
- **Pre** none.
- **Trigger** 50 concurrent starts × 3 rounds, at `delay lock-acquire` of 0, 1 ms, 5 ms, 20 ms.
- **Expect** exactly one winner **every round at every delay**; the loser exits non-zero with a
  reason and **touches nothing**.
- **Assert** `winners==1` per round · `assert_untouched` for every session the winner owns ·
  `assert_killed_set empty` for the loser.
- **Catches** F-13 — and note the result that makes the delay ladder non-optional: a categorically
  broken check-then-write lock **passed 5 rounds of 100 concurrent acquirers with no injected
  delay**, and only failed as the delay widened (1 → 5 → 13 → 26 winners at 0 → 1 ms → 5 ms → 20 ms)
  [V, sibling]. Parallelism alone proves nothing. `flock` is absent on macOS; `mkdir` and
  `set -o noclobber` were both exclusive 1/1/1 [V, sibling].

**L2-LIFE-02 · Stale-lock recovery distinguishes dead, stopped and reused**
- **Pre** three arms: holder `SIGKILL`ed; holder `SIGSTOP`ped (a paused orchestrator inside a quota
  wait); a lock whose pid now belongs to an unrelated process.
- **Trigger** a second start.
- **Expect** acquire · refuse · refuse. Liveness keys on the lock's pid + boot time + run id, never
  on a process name or `pgrep` pattern.
- **Assert** per-arm acquisition outcome · `assert_log absent='pgrep'`.
- **Catches** F-13 tests 2–4.

**L2-LIFE-03 · Crash at every step; the invariants hold**
- **Pre** a scenario enumerated into ~14 steps.
- **Trigger** `crash_at N` for every N, then restart.
- **Expect** after each: exactly one orchestrator; no ticket in-progress without a live session; no
  ticket lost; nothing unstarted touched; no duplicate work; no half-written state record.
- **Assert** the invariant set after every crash point; any violation names N.
- **Catches** F-22, F-15, and this is the tier that most directly answers "convince me it will work"
  [C].

**L2-LIFE-04 · Restart with executors still alive** `[pty]`
- **Pre** three stub sessions — one registered and live, one registered and dead, one **unregistered**
  — and a fresh orchestrator.
- **Trigger** start.
- **Expect** classification `mine-alive` / `mine-dead` / `not-mine`; the live one's ticket is not
  re-claimed; the dead one's is released exactly once; the unregistered one is left strictly alone.
- **Assert** `assert_state` per session · `assert_untouched unregistered`.
- **Catches** F-15 — adopt-and-duplicate and tear-down-and-lose, both reachable in the previous
  generation [C]; Д10.

**L2-LIFE-05 · A finished session is reaped by its recorded owner, and busy ones never are** `[pty]`
- **Pre** behaviour `finishes` for one session, `long-turn` for another; a recorded owner per session.
- **Trigger** advance past the reap threshold; second arm: kill the **owner** first.
- **Expect** the finished session is closed and deregistered, attributed in the log; ownership falls
  back when the owner dies; the busy session is **never** force-closed.
- **Assert** `assert_state w_finished.closed_by=<owner>` · `assert_state w_long.open=true` ·
  `assert_log absent='force'`.
- **Catches** F-14 (a finished session registered and idle for **one day and four hours** [C]) while
  protecting P-03, the positive control that close-without-force worked and must not regress.

### G · Board

**L2-BRD-01 · Concurrent ticket-id allocation**
- **Pre** an empty board.
- **Trigger** 2, 20 and 50 concurrent `add`s, at `delay id-alloc` 0 / 1 ms / 5 ms / 20 ms.
- **Expect** `count(distinct ids) == count(adds)` at every rung; an allocator that cannot guarantee
  uniqueness must **error**, not collide silently.
- **Assert** distinct-id count per rung.
- **Catches** F-49 / F-51 — **and this one is live in the current repository right now.** The lock is
  documented as fixed, exists only in the installed copy, and `l_add()` in
  `plugins/harness/bin/harness-tickets.sh` still does an unlocked read-then-write [V, sibling].
  Historical rates: two concurrent adds produced two files under one id in **5 of 5** rounds; a
  twenty-way add produced twenty files under three ids [C]. **This scenario should be written first
  and watched to fail against the existing source** — it is the cheapest possible demonstration that
  the layer works.

**L2-BRD-02 · Status is single-valued across every reachable path, on both backends**
- **Pre** `meta backends both`; the full transition graph.
- **Trigger** every transition from every reachable predecessor state, including
  `ready → blocked → in-progress → done`.
- **Expect** exactly one status label after each; both backends agree field by field.
- **Assert** label count == 1 per transition · a cross-backend diff.
- **Catches** F-50 — `done` leaving a previously blocked issue holding **two** labels, seen twice,
  and it appears only on a specific path, which is exactly why example tests missed it [C].

**L2-BRD-03 · A hostile ticket body is data, never template text**
- **Pre** fixture bodies containing `{{HBIN}}`, `{{RUN_DIR}}`, the fence sentinels, a spoofed
  close-sentinel, 10 000 characters, ANSI escapes, and a body claiming to be a system message.
- **Trigger** a spawn.
- **Expect** the rendered prompt's structure is unchanged; the spawn is not blocked and not subverted.
- **Assert** `assert_golden prompt` after normalisation.
- **Catches** F-57 — a spawn refused because a ticket quoted the harness's own tokens, and the
  workaround was logged as unsafe [C]. `H-44` is the one old test that catches its own mutation and
  is the model to copy.

**L2-BRD-04 · A description that changes mid-flight** `[pty]`
- **Pre** an in-progress ticket; a cheap watcher.
- **Trigger** two arms — the board is rewritten identically, and the board is genuinely edited.
- **Expect** silence when nothing changed; a report naming what changed when something did.
- **Assert** `assert_log absent='changed'` in arm one · `assert_log contains='ticket T-1 changed: acceptance criteria'` in arm two.
- **Catches** Д8, and the whole class of detectors that fire on mtime rather than content.

### H · Blast radius

**L2-RAD-01 · No destructive command runs with an implicit scope**
- **Pre** `COMPOSE_PROJECT_NAME` unset; labelled and unlabelled resources in the target set.
- **Trigger** the end-of-run cleanup that Д3 makes mandatory.
- **Expect** refusal rather than defaulting; cleanup enumerates by run-id label and **aborts the whole
  operation** if any target is unlabelled; every destructive action records actor, run id and target
  list *before* executing.
- **Assert** `assert_world_log absent='compose down'` in the unset arm · abort + report in the
  unlabelled arm · an attribution record present before every recorded destructive call.
- **Catches** F-44 — the owner's own default stack destroyed by `docker compose down -v`, detected
  only afterwards from image timestamps, **and the actor was never identified** [C].

**L2-RAD-02 · Pattern matching never selects a session by its prompt text** `[pty]`
- **Pre** a stub session whose command line contains `playwright test` (because its prompt does), plus
  a foreign `world_process` containing the same string.
- **Trigger** any cleanup of a subprocess.
- **Expect** neither is selected; targeting is by recorded pid plus an ownership/parentage check.
- **Assert** `assert_killed_set ⊆ started` · `assert_untouched foreign` · plus a **ban-grep** that no
  shipped path uses `pkill -f`/`pgrep -f` with a non-anchored pattern.
- **Catches** F-45 — `pkill -f 'playwright test'` killed an unrelated lane [C]. **Note the canary
  dependency:** without §7.3's live-`kill`-shim canary this scenario is vacuous, because `kill` is a
  builtin and the shim is never reached [V].

**L2-RAD-03 · Teardown containment and orphan reclaim by label**
- **Pre** labelled resources from a previous dead run; foreign processes and containers present.
- **Trigger** a fresh run's startup and its end-of-run teardown.
- **Expect** the previous run's resources are enumerated and reclaimed **by label**; anything
  unlabelled is refused; the teardown target set is a subset of what this run started; a startup
  report lists orphans.
- **Assert** set containment · `assert_untouched` per foreign resource · `assert_log contains='orphans from run <id>: N'`.
- **Catches** F-48 (~150 orphaned volume pairs from a dead prior run [C]), Д3, R1-16.

### I · Detectors and loops

**L2-DET-01 · A banner in the orchestrator's own prose does not fire the detector** `[pty]`
- **Pre** behaviour `banner-in-prose`, plus a screen quoting the pattern inside a report, plus a real
  banner as the last non-empty line, plus a non-ASCII space variant.
- **Trigger** a tick.
- **Expect** fire on the real banner only.
- **Assert** four fixtures, one positive, three negative.
- **Catches** F-40's root cause and F-63 — four detector false positives fixed in one day [C]. The
  mechanism was reproduced verbatim by a sibling: a `usage limit reached|limit will reset at` regex
  fires on the orchestrator's own prose, and a last-non-empty-line anchor passes all three [V].

**L2-DET-02 · Corrective action is bounded and fixed-point aware** `[pty]`
- **Pre** a stub whose screen never changes no matter what is sent.
- **Trigger** the corrective action that F-40 ran every ~60 s for 85 minutes.
- **Expect** at most N repetitions against the same target with the same trigger, then escalate and
  stop repeating; an action whose post-condition is "the screen changes" and whose screen did not
  change is recorded as **ineffective**; reconciling an unchanged world twice acts once.
- **Assert** action count ≤ N · `assert_notified count=1` · `assert_idempotent`.
- **Catches** F-40 — 85 minutes, ended only by an external `SIGTERM`, with a second 45-minute instance
  in another run [C].

**L2-DET-03 · Findings dedupe with a count; unresolvable findings are said once**
- **Pre** a condition that persists across 100 ticks and that no available action can resolve.
- **Trigger** 100 ticks.
- **Expect** one record with `count=100`, not 100 records; escalation past a threshold; a finding no
  actor can resolve is reported as such at **first** detection, not on a timer; every waiting state is
  bounded and names what would end it.
- **Assert** record count == 1 · `assert_notified` once · `assert_state hold.awaiting!=""`.
- **Catches** F-42 (the same condition flagged **1 085 times over five days** [C]), F-43 (a recovery
  component that held politely for 32 minutes for a condition nothing would change [C]).

### J · Silence, notification, and the watchdog's watchdog

**L2-OBS-01 · Silent by default; verbosity changes printing, never decisions**
- **Pre** one scenario, run twice: `output=silent` and `output=verbose`.
- **Trigger** identical worlds and seeds.
- **Expect** silent-mode stdout is **empty**; the decision logs are byte-identical after
  normalisation.
- **Assert** `assert_golden stdout=empty` · a diff of the two normalised decision logs.
- **Catches** Д11, and it is the metamorphic relation worth the most here: it proves observability
  does not alter behaviour, which is the assumption every other scenario in this layer rests on.

**L2-OBS-02 · The channel is round-tripped before the run, and the notifier is supervised**
- **Pre** three channel arms — `ok`, `401`, `timeout`; then a run in which the notifier process is
  killed mid-flight.
- **Trigger** run start; then the kill; then advance the clock.
- **Expect** the run **refuses to start** in the `401` and `timeout` arms; the notifier's absence is
  escalated by a second route within a bounded time.
- **Assert** `assert_exit != 0` in two arms · `assert_notified via=fallback` after the kill.
- **Catches** F-41 — the human-notification watchdog had exited on "run finished" and was never
  restarted, during the 85-minute loop [C]; R1-17's "повинен лише переконатися, що це працює".

### K · Platform matrix

**L2-PLT-01 · argv, env and cwd golden per (platform × role × mode)** `[pty]`
- **Pre** `{claude, codex, glm} × {orchestrator, worker, validator, question} × {interactive, headless}`,
  minus the pairs the capability matrix forbids.
- **Trigger** a spawn of each.
- **Expect** every identifier in a spawn descriptor — session id, cwd, prompt, branch, log path,
  ticket id — refers to the **same** unit; the argv matches its golden after normalisation.
- **Assert** `assert_argv` per cell · `assert_golden launcher` · a pure-function internal-consistency
  check over the descriptor.
- **Catches** F-54 (a launcher whose fields disagreed — session id said phase 5, cwd said phase 4 [C])
  and F-55; and it is instruction **I1**, per-platform feasibility, made mechanical.

**L2-PLT-02 · `deliver()` is one contract across every adapter and backend** `[pty]`
- **Pre** the same delivery property table run against all three platforms and every terminal backend.
- **Trigger** `deliver(session, text)`.
- **Expect** after `Delivered`, the text appears in that session's **transcript** as a user turn within
  a bounded virtual time; after `Refused` or `Failed`, the session state is unchanged and nothing was
  consumed. An adapter that returns `Delivered` without a transcript read fails. A backend lacking a
  verb the configured process needs is **rejected at configuration time**, not degraded during the
  run.
- **Assert** the shared property table per adapter · a config arm asserting a non-zero exit on an
  incompatible pairing.
- **Catches** F-09 (the missing abstraction that makes eight other bugs possible), F-70 (a backend
  that silently cannot type at all, verified in the old source at `harness-term.sh:228` [C]), and the
  corpus's warning that **no adapter other than Claude Code has any evidence behind it**.

---

## 10. Mutation check — the exact break that must turn each group red

`tests/mutations/*.mut`, consumed by L3. A group whose mutation leaves every test green is a vacuous
group and is redesigned, not shipped.

| # | Group | The exact change to the implementation | Must turn red |
|---|---|---|---|
| M-DEL-readback | A | In `lib/deliver.sh`, return `Delivered` from the terminal driver's exit status; delete the inbox/transcript re-read. | L2-DEL-01, -04, -06, K/PLT-02 |
| M-DEL-busy | A | Delete the pre-write "is the input line empty" check. | L2-DEL-02 |
| M-DEL-chunk | A | Make the transport drop any payload over N bytes and return 0. | L2-DEL-03 |
| M-DEL-ident | A | Skip the pane identity read-back before delivery. | L2-DEL-05 |
| M-LIV-signal | B | Remove **any one** input from the liveness decision table (heartbeat age, mid-turn flag, recent output, file/git activity, child activity). | L2-LIV-01 (the row for the removed input) |
| M-LIV-exists | B | Classify a child process as `busy` on existence alone, without the progress qualifier. | L2-LIV-02 |
| M-LIV-raw | B | Compare raw error strings instead of normalised ones in the three-strikes counter. | L2-LIV-03 negative arm |
| M-LIV-rung | B | Delete the terminal rung of the escalation ladder. | L2-LIV-04 |
| M-LIV-backstop | B | Delete the global `ready-work + free-capacity + no-progress` invariant, leaving only the classifier. | L2-LIV-05 |
| M-CTX-gate | C | Remove the shell-count gate from the compact procedure. | L2-CTX-01 |
| M-CTX-verify | C | Report compact success without the post-condition percentage re-read. | L2-CTX-02 |
| M-CTX-default | C | Return `0%` when status-line parsing fails instead of `unreadable`. | L2-CTX-03 |
| M-QUO-open | D | Map `UNKNOWN` to `OK` (this is the old suite's M3, which it passed 51/51 [V]). | L2-QUO-01 |
| M-QUO-401 | D | Collapse `401` into the generic unknown branch. | L2-QUO-02 |
| M-QUO-label | D | Drop the account label from the quota record. | L2-QUO-03, -04 |
| M-QUO-na | D | Map `NotApplicable` to `UNKNOWN` for a platform with no endpoint. | L2-QUO-05 |
| M-QUO-epoch | D | Pin the wall-clock resume fallback to a fixed past epoch (the historical `#65`). | L2-QUO-06 |
| M-QUO-order | D | Swap the two writes in the pause path so a crash between them reads as a manual stop (`#73`). | L2-QUO-06 crash loop |
| M-QUO-env | D | Remove one declared environment export from a detached entry point. | L2-QUO-07 |
| M-CTL-write | E | Point the status writer at the inbound control path (truncate-then-rewrite). | L2-CTL-01 immediately, -02, -03 |
| M-CTL-atomic | E | Replace the atomic `rename()` with truncate-then-write. | L2-CTL-03 |
| M-CTL-order | E | Make a pending soft stop win over a hard stop arriving later. | L2-CTL-04 |
| M-CTL-cwd | E | Resolve the question-channel path relative to cwd. | L2-CTL-05 |
| M-LIFE-lock | F | Replace the exclusive lock with `[ ! -f "$LOCK" ] && echo $$ > "$LOCK"`. | L2-LIFE-01 **at delay ≥ 1 ms only** — at delay 0 it passes, which is the whole point [V] |
| M-LIFE-pgrep | F | Key the liveness check on `pgrep -f orchestrator` instead of the lock record. | L2-LIFE-02 |
| M-LIFE-trust | F | Make restart reconciliation trust the registry without checking process liveness. | L2-LIFE-04 |
| M-LIFE-owner | F | Remove the fallback owner for session reaping. | L2-LIFE-05 second arm |
| M-BRD-lock | G | Remove the ticket-id allocation lock — **i.e. use the code that is in the repository today** [V]. | L2-BRD-01 |
| M-BRD-label | G | Delete one label-clearing call on the `done` path. | L2-BRD-02 (only via the exhaustive path walk) |
| M-BRD-subst | G | Substitute the ticket body into the prompt template as text instead of binding it as data. | L2-BRD-03 |
| M-BRD-mtime | G | Trigger the mid-flight change detector on mtime instead of content hash. | L2-BRD-04 arm one |
| M-RAD-default | H | Let cleanup fall back to the default project when the scope variable is unset. | L2-RAD-01 |
| M-RAD-pkill | H | Add one `pkill -f "<descriptive pattern>"` call to a cleanup path. | L2-RAD-02 |
| M-RAD-memory | H | Track created resources in memory only, not by label. | L2-RAD-03 |
| M-DET-anchor | I | Match the rate-limit pattern anywhere on the screen instead of anchoring to the last non-empty line. | L2-DET-01 |
| M-DET-count | I | Remove the repetition counter from the corrective-action path. | L2-DET-02 |
| M-DET-emit | I | Emit a finding on every tick instead of deduplicating with a count. | L2-DET-03 |
| M-OBS-print | J | Make one decision depend on the output mode. | L2-OBS-01 |
| M-OBS-cfg | J | Check the notifier's configuration instead of its liveness; skip the pre-run round-trip. | L2-OBS-02 |
| M-PLT-claim | K | Have an adapter declare a capability it does not implement (the old suite's M6, passed 51/51 [V]). | L2-PLT-02 config arm |

**Four mutations of the harness itself**, because §7.3's mechanisms are code too and must also be
breakable:

| # | The change | Must turn red |
|---|---|---|
| M-SIM-canary | Delete `enable -n kill` from `preload.bash`. | the `kill`-shim canary — and **not** L2-RAD-02, which is exactly the vacuity this proves [V] |
| M-SIM-floor | Delete two `.sim` files without updating `EXPECT_SCENARIOS`. | the runner's floor check |
| M-SIM-clock | Make `bin/sleep` sleep for real. | the clock canary, and the suite's wall time |
| M-SIM-leak | Skip `tmux kill-session` in teardown. | `assert_no_leaks`, and the second (idempotence) pass |

---

## 11. Cost

**Measured floors on this machine** [V]: stub session spawn→ready **0.60 s** (10 samples,
6.04 s total); world-only scenario scaffold **15 ms** (200 samples, 2.95 s total); a complete
prototype scenario including tmux spawn, delivery attempt, polling read-back and teardown
**1.16 s (failing) / 1.83 s (passing)**; two simulated hours of `sleep` **0.678 s**; quota stub
response **13 ms**.

| Component | Count | Each | Total |
|---|---|---|---|
| `[pty]` scenarios | 21 | ~1.6 sessions × 0.60 s + ~0.5 s interaction | ~31 s |
| world-only scenarios | 25 | ~0.25 s | ~6 s |
| L2-LIFE-03 crash loop (delta over its base cost) | 14 crash points | ~0.9 s | ~12 s |
| L2-LIFE-01 lock race (delta) | 4 delay rungs × 3 rounds × 50 | — | ~6 s |
| L2-DEL-03 length sweep (delta) | 8 sizes × 2 modes | 0.65 s | ~9 s |
| **Full pass, serial** | 46 scenarios | | **~64 s** |
| **Full pass, `-j 4`** | private tmux server per scenario | | **~20 s** |

**Money: $0.00.** No model call, no paid API, no network beyond `127.0.0.1`. Nothing in this layer
needs a credential; the `401` cassette is a recorded file, not a live request.

**Three cost caveats that are load-bearing.**

1. **`tests/run-all.sh` executes every plugin runner twice** [V, sibling], so adding L2 unchanged
   costs **~128 s**, tripling the 42 s suite. The double execution is *also* a correctness
   requirement (idempotence), which is why §7.3 asserts idempotence internally and the runner should
   be fixed to scrape counts from the first run rather than re-running.
2. **The suite must run a second time under `env -i`** (L2-QUO-07 aside, as a whole-suite arm),
   because the environment hazards are real and verified: `find` is `bfs` interactively and
   `/usr/bin/find` when detached, with incompatible flags; `/tmp` is a symlink `find` will not
   descend; `timeout` is not on the scrubbed PATH [V]. Budget a second ~64 s pass.
3. **The mutation gate (L3) is a separate entry point**, ~44 mutations × (tree copy + affected
   scenarios ≈ 4 s) ≈ **3 minutes**, run pre-PR, not per commit.

---

## 12. Honest limits — what this layer cannot catch

The next layer inherits all of these. They are ranked by how likely each is to cause a false green.

1. **Stub fidelity, and it can invert a verdict.** Measured twice, from two directions: a
   canonical-mode stub drops 1024 bytes silently while a raw-mode stub does not [V, here], and a
   `read`-loop stub submits stranded text on a bare Enter while the real TUI does not [V, sibling].
   L2 proves the orchestrator handles *the semantics it was told about*. Whether the real CLI has
   those semantics is L4's question, and **a small conformance tier is not optional** — it is what
   keeps this whole layer honest. Recommended shape: one conformance case per declared stub
   behaviour, run pre-release against one real account.
2. **`sh -c` escapes the `kill` interception.** `BASH_ENV` + `enable -n kill` covers the SUT, child
   `bash` and subshells (3/3) but not `sh -c` (0/3) [V]. An orchestrator that shells out via `sh`
   would have its kills invisible to L2. Mitigated by a canary and a ban-lint, not eliminated.
3. **Shell builtins and non-shell runtimes bypass the clock.** `$SECONDS`, `$EPOCHREALTIME` and
   `read -t` are builtins; `time.time()` in a Python component ignores both shims [V]. L2 covers this
   with a declared `now()` seam plus a lint, which is a discipline, not a guarantee.
4. **The quota schema question is unresolved and L2 cannot resolve it.** The shipped parser and the
   owner's own `CLAUDE.md` document different shapes, and the live endpoint 401s [V, sibling]. A
   cassette of the wrong schema replays confidently forever. L2 can only assert that an unrecognised
   schema is *reported as unrecognised*; only L4's live re-record job can say which is current.
5. **Model behaviour and decision quality are entirely out of scope.** R1-09's silence judgement,
   R1-14's escalation, Д9's contradiction handling — L2 asserts what the orchestrator is **told**,
   never what it concludes. Everything about conclusions belongs to the LLM-eval layer, and the
   corpus's closing note is the reason: "the record shows that judgement was not the failing part —
   the **signals** were" [C].
6. **Races only in the windows someone widened.** The verified result is unambiguous: a broken lock
   passed 5 rounds of 100 concurrent acquirers at delay 0 [V, sibling]. L2's delay ladder finds the
   races at the injection points an implementer thought to place. Unplaced windows are invisible, and
   no amount of parallelism substitutes.
7. **GUI terminal backends cannot be driven here.** Terminal.app and iTerm2 need a real windowing
   session; L2 covers tmux and headless only. The one recorded backend that *cannot type at all* is a
   GUI backend [C], so this gap sits directly over a known failure.
8. **Real resource exhaustion is not simulated.** OOM kills, swap pressure, disk-full — F-46, F-47
   and the 26 OOM-killed collector subprocesses [C] are only reachable here as *injected* failures,
   which tests the handler, not the trigger. And per FIELD-NOTES §5.2, swap occupancy is the wrong
   meter on macOS anyway.
9. **Non-code runs have no coverage anywhere.** N2 is explicit that the orchestrator may run where
   there is no repo, no tests and no build. Roughly a third of the failure corpus assumes git or a
   test runner, and the corpus has **no evidence at all** about a non-code run [C]. L2 inherits that
   blindness; the first non-code run will be unguarded.
10. **Board backends beyond GitHub labels and local files are unmodelled.** ClickUp, which R1-04
    names, has no record and no stub here [C].
11. **L2 tests the orchestrator, not the configured process.** R1-13 puts GSD/superpowers/custom
    verification outside the orchestrator's remit, and L2 respects that boundary. The consequence is
    stated plainly: the commit-gate family F-65…F-69 — gates that could not fail loudly — is out of
    scope by decision, and **the corpus flags this as question one for round 2** [C]. If the owner
    accepts the bookkeeping/verification distinction, L2-BRD and a step-coverage scenario grow; if he
    rejects it, a silently skipped verification stage can ship five phases again.

---

## 13. Build order and effort

Strictly sequenced so that something discriminating exists on day one.

| # | Piece | Lines | Effort | Why here |
|---|---|---|---|---|
| 1 | `L2-BRD-01` against the **existing** repo | ~30 | 1 h | The bug is live [V]. A test that fails before it passes is the cheapest proof the layer works. |
| 2 | `simlib.sh` + `world.sh` + runner skeleton with the floor, canaries and leak check | ~400 | 1 d | §7.3 is what separates this from the suite it replaces. |
| 3 | `bin/date`, `bin/sleep` + clock canary | ~30 | 1 h | Verified working already [V]; unlocks every timing scenario. |
| 4 | `agent.py` + the behaviour format + the 15 shipped behaviours | ~250 + 15×8 | 1.5 d | The highest-value single artefact; ~20 scenarios depend on it. |
| 5 | Group A (delivery), both line-discipline modes | 6 scenarios | 0.5 d | Largest failure family; prototype already proven [V]. |
| 6 | `quotad.py` + cassettes + `bin/curl`; group D | ~140 | 0.5 d | Old suite passed this mutation 51/51 [V]. |
| 7 | `board.sh` + `bin/gh`; groups G, E | ~200 | 1 d | Control file is the operator's only brake. |
| 8 | World recorder + `preload.bash`; groups H, F | ~150 | 1 d | Needs the canary from step 2 or it is vacuous [V]. |
| 9 | Groups B, C, I, J, K | 16 scenarios | 1 d | |
| 10 | `mutations/*.mut` + the 44 mutation files | ~120 + 44 | 0.5 d | The test of the tests. |

**Total ≈ 6.5 working days** for one implementer who already has the seams. The seams themselves —
`decide`/`apply`, `resolve_bin`, `now()`, `deliver()` — are **not** L2's cost; they are architecture
decisions that must exist before the first line of the loop is written, and they cannot be
retrofitted cheaply.

**The prototype in `…/scratchpad/l2proto/` is step 2 and part of steps 3–5 already standing**: a stub
agent with both line disciplines, a 12-line scenario, the assertion vocabulary, and two orchestrators
— one that passes and one that fails — built and measured in under an hour. [V]
