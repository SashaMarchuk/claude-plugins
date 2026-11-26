# Ground: what exists here — the test substrate an orchestrator would be built on

**Date:** 2026-09-19 · **Scope:** what `claude-plugins` and this machine already provide for testing,
what those things can and cannot prove, and exactly how an orchestrator's tests must differ.

**Evidence labels used throughout:**
- **VERIFIED** — I read the file or ran the command in this session and the output is quoted below.
- **CLAIMED** — asserted by a document I read (FIELD-NOTES, ANALYSIS-01, the task brief) but not
  independently re-run here.
- **INFERRED** — my reasoning from verified facts; flagged as such every time.

---

## 0. Headline

The repo has a real, fast, zero-cost regression substrate (475 assertions, 42 s, no network, no API
spend) and it is **structurally incapable of proving that an orchestrator works**, for three separate
reasons, all VERIFIED here:

1. **80% of the harness plugin's own tests never execute the code they describe** — 41 of 51 are
   `grep` over source text (§2.3). I broke a real check while leaving its string in a comment and the
   test stayed green (§4.1).
2. **The master runner has no floor and aborts silently.** A plugin runner that asserts nothing and
   exits 0 kills the whole aggregate run with no message, and every plugin after it never runs (§3.1).
   This is the FIELD-NOTES "truncated suite read as a pass" class reproduced inside the test harness
   itself.
3. **Nothing in the idiom can observe time, a process, a terminal, or a second copy of anything** —
   which is the entire subject matter of an orchestrator (§5).

Meanwhile Claude Code itself now ships an eval runner (`claude plugin eval`, VERIFIED present at
2.1.278) with six grader types, an ablation arm and cost ceilings — but every case is a real agent run
on the operator's own credential, so it is a *paid, non-deterministic* layer that must sit **on top
of** the free deterministic layer, never in place of it (§6).

---

## 1. Method and what I touched

Run on this machine, `/Users/sasha-marchuk/Work/claude-plugins`, branch `main`, at 2026-09-19.

- Read: `tests/run-all.sh`, `plugins/harness/tests/run.sh` (382 lines, 51 tests),
  `plugins/harness/tests/README.md`, `plugins/interview-handoff/tests/run.sh`, `CLAUDE.md`,
  `CONTRIBUTING.md`, `.claude-plugin/marketplace.json`, `plugins/harness/bin/*.sh` (12 scripts,
  1879 lines), `plugins/harness/docs/FIELD-NOTES.md` (704 lines),
  `product/spikes/harness-rebuild/round-1/ANALYSIS-01.md`.
- Ran: the full suite (timed), the harness suite alone (timed), two source mutations with restore,
  four master-runner probes in a scratch copy, a headless tmux end-to-end session probe,
  `claude plugin eval init --bare` in a scratch plugin, and `strings` over the Claude Code binary.
- **Working tree left clean.** Both mutations were restored from scratchpad copies (never
  `git checkout`, per the house rule) and `git diff --stat -- plugins/harness/bin/` is empty.

**Not verifiable here:** the task brief names a validated evidence summary at
`…/scratchpad/context/harness-evidence.md`. That path is **empty on this machine** (`ls` shows an
empty `context/` directory; `find /private/tmp/claude-501 -name harness-evidence.md` returns nothing).
Everything I attribute to the 34-hour run therefore comes from `FIELD-NOTES.md`, which is present and
carries openable references, and is labelled CLAIMED.

---

## 2. The existing test idiom

### 2.1 The master runner — `tests/run-all.sh` (79 lines) · VERIFIED

```bash
PLUGINS=(clickup g-event ultra ultra-analyzer claude-migrate find-call log-time harness \
         ig-dm-export-analyzer interview-handoff)
```

For each name it runs `plugins/<name>/tests/run.sh`, then **runs it a second time** to scrape
`PASS=<N>`/`FAIL=<M>` out of the captured output (lines 39 and 49; the comment even says "a second
invocation is < 1s"). It sums the two numbers, prints an aggregate block, and exits non-zero if any
total is non-zero or any runner exited non-zero.

Contract a runner must honour, and nothing more:
- exit 0 for green, non-zero for red;
- print a final line matching `PASS=<N>` and `FAIL=<M>` (both greps must hit, see §3.1).

`task-launch` has **no** `tests/run.sh` and is **not** in `PLUGINS` — it is uncovered by owner
decision (matches the memory note). A plugin absent from the array is invisible to the suite: no
warning, no count.

### 2.2 The per-plugin idiom · VERIFIED

Every runner is a single flat bash script. Two dialects, both hand-rolled, no framework
(`bats` is **not installed** on this machine — VERIFIED):

- **harness dialect:** `ok()`/`bad()` helpers, a `t=H-NN` variable per test, id in the message.
- **everything else** (interview-handoff, ultra-analyzer, …): `pass()`/`fail()` helpers, a
  `FAIL_MSGS` array, labelled path variables at the top, and a `json_valid`/`json_query` shim that
  falls back from `jq` to `python3`.

The interview-handoff runner states the limit of the idiom in its own header, unprompted:

> SCOPE: these are file contracts, not behaviour tests. They cannot run a grill, resolve a real skill,
> or reproduce the two-copies incident that produced 0.4.1 … Behavioural coverage is still owed.

That is the honest description of the whole substrate.

### 2.3 The harness plugin's 51 tests, classified · VERIFIED

I split `run.sh` per `t=H-NN` block and classified by whether the block **executes plugin code**
(sources `hlib.sh`, or invokes `bin/harness-*.sh` with a verb) versus only reads its text:

| Class | Count | Ids |
|---|---|---|
| **Behavioural** — runs the code, asserts on output/state | **10** | H-29, H-39, H-40, H-41, H-42, H-43, H-44, H-45, H-46, H-49 |
| **Static analysis** — `bash -n`, `shellcheck`, `jq -e .` (real, but semantics-blind) | 4 | H-1, H-2, H-3, H-6 |
| **grep over source text** — asserts a string exists or is absent | **37** | the rest |

So **~20% of the suite touches running code.** The behavioural ten are genuinely good and are the
template to keep (see §7.1). Two nuances worth carrying forward:

- **H-49 already does dependency injection**: it writes `printf '#!/bin/sh\nexit 7\n' > $tmp/bin/curl`,
  prefixes `PATH`, and asserts `status --json` exit codes. That is the fake-binary-on-PATH idiom, in
  the repo, working, today.
- **H-24 simulates the production path instead of calling it**: it re-implements `do_start`'s
  placeholder substitution with its own `sed` line rather than invoking the engine. It is the only
  end-to-end-flavoured test and it can drift from the code it claims to guard the moment the real
  substitution changes shape. INFERRED: it would not catch a C1 recurrence that moved to a different
  substitution mechanism.

### 2.4 How a new plugin is wired in · VERIFIED (CONTRIBUTING.md §"Adding a plugin" + observed in-tree)

Five mechanical steps; interview-handoff's own tests assert the last two on itself:

1. `plugins/<name>/.claude-plugin/plugin.json` (semver; `0.x` + `(beta)` prefix for beta).
2. One entry in `.claude-plugin/marketplace.json` `plugins[]` (`name`, `description`, `author.name`,
   `source: "./plugins/<name>"`, `category`, `homepage`).
3. `README.md`, `CHANGELOG.md`, `LICENSE` in the plugin dir.
4. `plugins/<name>/tests/run.sh` **and** register `<name>` in `PLUGINS=(...)` in `tests/run-all.sh`.
5. A row in the root `README.md` plugins table.

Self-checks worth copying verbatim into a new plugin's suite (VERIFIED, they exist in
interview-handoff): `marketplace.json: <name> listed` and `run-all.sh: <name> in the PLUGINS array`.
Those two lines are the only defence against a plugin silently dropping out of coverage.

There is **no CI**: `.github/workflows` does not exist. The suite runs when a human types
`bash tests/run-all.sh`. INFERRED, and material: an unattended orchestrator that regresses at 03:00
has nothing watching it.

### 2.5 What a test file actually looks like

The two shapes, verbatim from the tree.

*Grep-style (the 37):*
```bash
# H-33 (F4): preflight validates project config JSON
t=H-33
if grep -q 'is not valid JSON' "$ROOT/bin/harness-run.sh"; then
  ok "$t preflight validates project config (F4)"
else bad "$t" "F4 config validation missing"; fi
```

*Behavioural (the 10) — builds a fixture project, runs the real code, asserts state:*
```bash
# H-46: stale releases a >7d-idle in-progress ticket back to ready
t=H-46; f=""
tmp=$(mktemp -d); mkdir -p "$tmp/.harness/tickets"
printf '{"tickets":{"source":"local"}}' > "$tmp/.harness/config.json"
printf 'title: x\nstatus: in-progress\n\n## Outcome\no\n## Scope\ns\n## Acceptance criteria\na\n' \
  > "$tmp/.harness/tickets/1-x.md"
touch -t "$(date -v-8d +%Y%m%d%H%M)" "$tmp/.harness/tickets/1-x.md"
HARNESS_PROJECT="$tmp" "$ROOT/bin/harness-tickets.sh" stale 2>/dev/null | grep -q '^RELEASED' \
  || f="8d-idle not released"
[ -z "$f" ] && ok "$t stale 7-day reclaim sweep" || bad "$t" "$f"
```

The enabling design choice is `HARNESS_PROJECT` / `HARNESS_USER_DIR`: **every path the engine reads is
environment-rebindable**, so a whole fake project fits in a `mktemp -d`. That single property is the
most valuable thing in the repo for testing an orchestrator and it must be preserved (§7.1).

### 2.6 Timings measured on this machine · VERIFIED

| What | Wall time |
|---|---|
| `bash tests/run-all.sh` (475 assertions, 10 plugins) | **42.15 s** real / 21.51 user / 16.03 sys |
| `bash plugins/harness/tests/run.sh` alone (51 tests) | 5.18 s |
| `bash plugins/ultra-analyzer/tests/run.sh` alone (68 tests) | 6.52 s |
| `bash plugins/interview-handoff/tests/run.sh` alone (39 tests) | 0.25 s |

Result: `Total: 475 PASS / 0 FAIL`, exit 0. Roughly half the 42 s is the double execution (§3.2):
unique test work is ~21 s.

Cost: **zero.** No network, no model call, no terminal spawned. That property is the reason the suite
gets run at all, and any new layer that breaks it will stop being run. INFERRED but strongly.

---

## 3. Defects in the existing harness itself, found here

These are not theoretical. Each was reproduced in a scratch copy of `run-all.sh` in the scratchpad.

### 3.1 A silent runner aborts the whole suite, and every later plugin never runs · VERIFIED

`run-all.sh` calls `set -e` twice (lines 41 and 50) intending to *restore* it — but it was never on,
so those lines **switch it on**. Immediately after, with `set -o pipefail` already active:

```bash
pass_n=$(echo "$out" | grep -oE "PASS=[0-9]+" | tail -1 | cut -d= -f2)
```

If the runner printed no `PASS=` line, `grep` exits 1, `pipefail` propagates it, `set -e` kills the
master script. Reproduced with `PLUGINS=(fakep goodp)` and a `fakep` runner of
`#!/usr/bin/env bash\nexit 0`:

```
==================================================================
>>> /fakep
==================================================================
=== exit=1 ===
### does goodp ever run? ###
0
```

No error message, no aggregate summary, no named plugin, **and `goodp` was never executed.** A reader
sees exit 1 and assumes "a test failed somewhere". `harness` is 8th of 10 in the array; a silent death
at position 1 skips it entirely.

### 3.2 Every runner is executed twice · VERIFIED

Lines 39 and 49. Harmless for pure greps; for an orchestrator's tests — which will create tmux
sessions, lock files, git repos and pid files — the second execution is a correctness requirement
(idempotence) and a 2× cost multiplier on anything paid. INFERRED consequence: a test that leaks a
tmux session would fail on its second run and be blamed on flakiness.

### 3.3 There is no floor on assertion count · VERIFIED

A runner printing exactly `tests: PASS=1  FAIL=0` and exiting 0 is reported as
`/fakep: PASS=1  FAIL=0  exit=0 … Total: 1 PASS / 0 FAIL`. Nothing compares the count against the
previous run, a committed baseline, or a per-plugin minimum. A suite that silently loses 40 of its 51
tests reports green. This is exactly the failure class FIELD-NOTES §11.4 records in production
("a truncated suite read as a pass"; 346 passed / 0 failed out of a declared 382, caught by
arithmetic, not by the gate).

---

## 4. Mutation checking in practice — two runs, verbatim

The house rule is "break the contract on purpose and see the test fail". Here is what that actually
looks like on both classes of test, and why the distinction matters.

### 4.1 Mutation A — a grep test passes vacuously · VERIFIED

Target: H-33, "preflight validates project config (F4)". I **deleted the validation** from
`bin/harness-run.sh` and left the sentence in a comment:

```diff
-  jq -e . "$PROJ/.harness/config.json" >/dev/null 2>&1 || { echo "INVALID: … is not valid JSON …" >&2; fails=1; }
+  # TODO: re-enable — was: config.json is not valid JSON
+  true
```

```
baseline:              PASS  H-33 preflight validates project config (F4)
MUTATION A (gutted):   PASS  H-33 preflight validates project config (F4)
restored:              PASS  H-33 preflight validates project config (F4)
```

**The feature is gone and the test is green.** The only mutation H-33 detects is deleting the *string*
— i.e. it tests a comment. This is the single most important measured fact in this document: the house
mutation rule, applied to a grep test, only ever proves that a string is present somewhere in a file.

### 4.2 Mutation B — a behavioural test fails honestly · VERIFIED

Target: H-39, `cfg_int` numeric-knob validation. I narrowed the rejecting case in `bin/hlib.sh` from
`''|*[!0-9]*)` to `'')`, so `"20m"` is no longer rejected:

```
MUTATION B:  FAIL  H-39 — no WARN on bad value
restored:    PASS  H-39 cfg_int numeric-knob validation
```

Correct failure, with a message that names the broken behaviour rather than the missing string.

### 4.3 The operational shape of a mutation check here

1. `cp <file> $SCRATCH/<file>.orig` — **never** `git checkout`, the tree may hold uncommitted work.
2. Apply the mutation with a `python3` heredoc that `assert`s the old text was found (a silent
   no-match `sed` is itself a FIELD-NOTES failure mode: §12.2, "SYNTAX OK while the anchor never
   matched").
3. Run only the affected runner (5 s), grep for the one test id.
4. `cp` back from scratch; confirm with `git diff --stat` on the touched directory.

Total ~30 s per mutation. Cheap enough to be a gate, and nothing about it needs a model.

---

## 5. Why none of this can test an orchestrator

The eight capabilities the brief names — queue, multi-platform sessions, thresholds, death-survival,
mid-run config, engine-agnostic workflow, silence, non-interference — are **all** properties of a
running system over time. Enumerated against what the idiom can observe:

| Orchestrator property (ANALYSIS-01) | Can the current idiom see it? |
|---|---|
| R1-05 concurrency cap; dependency-blocked tasks never start | No — needs ≥2 concurrent fake sessions and a clock |
| R1-06 hard/soft/intermediate limit semantics | No — needs an injectable quota source **and** injectable time |
| R1-07 control file re-read on tick; soft vs hard account change | No — needs a tick loop and mid-run mutation |
| R1-08 "a mechanism that **guarantees** the compact happens" | No — needs a session whose context can be driven to a threshold |
| R1-09 silent session judged and acted on | No — needs a fake session that *looks* busy but is not |
| R1-10 single-orchestrator invariant, survive own death | No — needs process kill + restart + a race |
| R1-16 / Д3 touch only what it started | No — needs a control process it did **not** start, and a survival assertion |
| Д7/Д12 behaviour changed **during** a run, applied next tick | No — needs a long-lived process under test |
| Д11 prints nothing unless asked | Partly — output can be asserted, but only over a real run |

There is a second, subtler gap that the tmux probe below makes concrete.

### 5.1 Headless session driving works here — and a naive fake agent tests the wrong thing · VERIFIED

`tmux 3.6a` is installed. `harness-term.sh` already has a full tmux backend (spawn/send/key/capture/
close) and it is the **only** file that talks to a terminal — a clean seam. I drove a fake agent
through it end to end with no API call:

```
OK backend=tmux
session=harness-b32b6989-R1   tty=/dev/ttys013
--- capture ---            FAKE AGENT READY
--- send "hello world" ---  hello world / GOT[hello world]
--- key enter (empty) ---   GOT[]
--- type "stranded" without Enter, then key enter ---
                            stranded
                            GOT[stranded]
```

The last three lines are the finding. FIELD-NOTES §1.3/§1.4 (CLAIMED, from the 34-hour run) record
that in a **real** Claude Code session a bare Enter does **not** submit text already sitting on the
input line — five operator instructions were lost that way, and the engine's own nudge left stranded
text on the line twice, measured. My fake agent — an ordinary `read` loop — **does** submit it.

So a test built on a naive fake agent would assert "nudge delivers the pending instruction", pass, and
be wrong in production. INFERRED, and it is the highest-leverage testing insight in this document:

> A fake agent must reproduce the *TUI input semantics* of the thing it stands in for, or the contract
> under test must be moved off "did we send?" onto "did we **observe** it land?".

The second option is strictly better and is free: the orchestrator's contract becomes
*never treat a send as delivered without a read-back*, which a fake agent that deliberately drops
input can prove, deterministically, in milliseconds.

Also observed: `term.sh close` on the last pane kills the tmux **server** (`no server running`) —
a fixture-teardown hazard for any suite that runs sessions.

### 5.2 What FIELD-NOTES says no test would have caught (CLAIMED, but it is the specification)

These are the bugs that a new suite exists to catch. Each is a testable invariant, and none of them is
a string in a file:

- a merge that printed `Already up to date` / `Everything up-to-date` and did nothing (§4.1);
- a validator skipped for one phase out of nineteen, detected by the orchestrator, not by a check
  (§4.2); GSD's verify stage silently skipped for phases 14–18 (§11.4);
- an 85-minute Escape/`continue` loop caused by the watch matching a rate-limit banner **inside the
  orchestrator's own wrapped prose**; nothing internal detected it; it ended by external SIGTERM
  (§11.6);
- `state/attention` truncated to zero bytes every cycle, destroying the only correction channel all
  night — line 5620 of that log reads `NO ONE IS BEING TOLD` (§2.1, §11.3);
- a probe using BSD-incompatible `find -newermt` with stderr to `/dev/null`, which would have declared
  every healthy session idle for ever (§11.3);
- a shell stuck in `until grep … sleep 5` against a pattern that could never match, reading as work
  (§2.2); 58 concurrent `sleep 590` children in one lane;
- a lane spending 3,466 of 3,626 Bash calls on the literal string `echo idle` — 77% of its context
  growth (§3.1);
- **nothing in the plugin measures context at all** — no `bin/*.sh` mentions compaction or percentages,
  while the number is printed on every session's own status line (§3.3);
- a documented ticket-id locking fix that **landed only in the installed copy, never in the source
  repo**, so it reverts on the next sync (§12.6);
- an audit log holding 26 refusal events that never happened (§12.7).

INFERRED: the common shape is **a check that cannot fail**. Every one of these is a detector, a gate
or a report that returned "fine" while the underlying action did not happen. That, not "does the
feature work", is what an orchestrator's test suite is for.

---

## 6. Eval tooling available in Claude Code itself · VERIFIED at v2.1.278

### 6.1 `claude plugin eval` — present, real, and paid

```
claude plugin eval [options] [target]
  Run eval cases (<eval dir>/**/case.yaml or prompt.md + graders/*.md …) against a plugin
  and report scored results.
```

Verified details:

- **Case format.** A case directory holds `case.yaml`, or `prompt.md` + `graders/*.md`.
  `claude plugin eval init --bare <name>` (run here, offline, in a scratch plugin) produced exactly:
  `evals/<name>/prompt.md` with frontmatter `max_turns: 10`,
  `allowed_tools: [Read, Glob, Grep, Skill]`, and `evals/<name>/graders/criteria.md` with
  `type: llm`, `weight: 1`. No network call, no cost.
- **Six grader types**, enforced by the loader
  (`frontmatter must include "type:" (regex | tool_order | tool_used | file_exists | llm | baseline)`).
  `regex` supports `contains | not_contains | count:N`; `tool_order` asserts a before/after relation
  in the trace; `baseline` takes `baseline_file`. INFERRED: the first four are **free** (they run over
  the transcript and filesystem); `llm` and `baseline` call a judge (`--judge-model`, default `haiku`).
- **Ablation.** `--ablation with-without` (the default whenever a plugin resolves) adds a no-plugin
  baseline arm and reports the delta; graders marked `with-only` (incl. `tool_used: Skill`) become a
  plugin-fired indicator rather than part of the score. This is the only mechanism on the machine that
  answers "does the plugin change anything at all?".
- **Cost controls.** `--max-cost-usd` (hard ceiling, exit 2, checked before each launch; paid graders
  are skipped for a breaching run while free graders still score it), `--runs <n>` (default
  `case.runs ?? 3`), `-j/--concurrency 1-8` ("each run is a full claude child on your own credential,
  so they share one rate limit"), `--case <glob>`, `--tag`, `--threshold <0..1>` (exit 1 below).
- **MCP mocking.** `mocks/<server>/<tool>.md` stand-ins, `--mocks record|off`,
  `--allow-real-servers`, plus an agent-responder shape (`_server.md` with `type: agent`,
  `tools: [...]`) and a per-run mock call budget.
- **Isolation.** `scaffold_script` is opt-in (`--scaffold`); `Bash/Write/Edit/WebFetch/mcp__*` need an
  explicit `--allow-tools` grant; first run in an untrusted plugin dir prompts (`--trust-plugin` for
  CI). Shell tools run in an OS sandbox; real MCP servers do not.
- **Output.** `aggregate-result.json` + a self-contained `report.html` (schema v4), published to
  claude.ai unless `--no-publish`.

**Cost reality, INFERRED from the verified defaults:** one case = `runs × arms` full agent sessions =
3 × 2 = **6 real Claude sessions by default**. A 20-case suite is 120 sessions per invocation. On a
single-operator machine sharing one rate limit with the operator's actual work, this cannot be the
default gate. It belongs behind a flag, a tag filter and a `--max-cost-usd`, run deliberately.

**No plugin in this repo has an `evals/` directory** (VERIFIED: `find . -type d -name evals` is empty;
no `plugin.json` sets `experimental.evals`). This capability is entirely unused here today.

### 6.2 Hooks as in-session probes · VERIFIED

Eleven hook events exist in the binary: `PreToolUse`, `PostToolUse`, `UserPromptSubmit`,
`SessionStart`, `SessionEnd`, `Stop`, `SubagentStart`, `SubagentStop`, `Notification`, **`PreCompact`**,
**`PostCompact`**.

Two plugins here already ship `hooks/hooks.json` (`ultra-analyzer`, `claude-migrate`), both
`PostToolUse`/`Write` matchers that only `printf` a warning and always exit 0. So the wiring pattern is
already proven in-tree.

Why this matters to an orchestrator specifically (INFERRED, but directly against ANALYSIS-01):
- `PreCompact`/`PostCompact` are the only *first-party* signal that a compaction happened. R1-08 demands
  "a mechanism that **guarantees** this action"; a `PostCompact` hook writing a marker file turns that
  guarantee into an assertion, and the same marker is what a test reads.
- `SubagentStart`/`SubagentStop` bound the "silent session" question (R1-09) without screen-scraping.
- `Stop` / `SessionEnd` give a deterministic "this session is finished" event — FIELD-NOTES §1.6 records
  a finished session sitting registered and idle for **one day and four hours** because nothing emitted
  that event.
- `UserPromptSubmit` is a **delivery receipt**: it fires only when text is actually submitted. That is
  the direct, free, deterministic answer to §5.1 and to the five lost instructions in FIELD-NOTES §1.3.

### 6.3 Headless driving primitives · VERIFIED in `claude --help`

`--print`, `--output-format text|json|stream-json`, `--input-format stream-json`, `--session-id <uuid>`,
`--resume`, `--fork-session`, `--bg` (returns an id for `claude attach|logs|stop|rm`, `claude agents`
lists them), `--max-turns`, `--permission-mode`, `--plugin-dir <path|.zip>` (load a plugin for one
session only), `--settings`, `--mcp-config` + `--strict-mcp-config`, `--agents <json>`, `--bare`,
`--restricted`, `--add-dir`.

`--plugin-dir` is the one that changes test design: a case can load the orchestrator **from the working
tree** without installing it, so "the fix lives only in the installed copy" (FIELD-NOTES §12.6) becomes
structurally impossible in a test.

### 6.4 Machine inventory · VERIFIED

Present: `tmux 3.6a`, `shellcheck`, `jq`, `gh`, `python3`, `git`, `claude 2.1.278`.
Absent: `bats`, `yq`, `faketime`.

`faketime` being absent is load-bearing: **time cannot be faked at the process level on this machine
today.** Either the orchestrator injects its own clock (a `now()` seam), or every timing test pays real
wall-clock seconds. INFERRED: a `now()` seam is the only affordable answer, and it must be a design
requirement, not a test trick.

---

## 7. What an orchestrator's tests must do differently

### 7.1 Reusable unchanged

Take these across without modification:

1. **The runner contract** — flat bash, `PASS=/FAIL=` final line, exit 0/non-zero. It is trivially
   satisfiable and keeps the plugin inside `run-all.sh`. *(But fix §3.1 first, or a new stateful suite
   will silently take the whole aggregate down.)*
2. **`HARNESS_PROJECT` / `HARNESS_USER_DIR` path rebinding.** Every state root reachable from an env
   var is why the behavioural ten exist at all. Non-negotiable for the rebuild.
3. **The `mktemp -d` fixture-project pattern** (H-42, H-44, H-45, H-46) — a whole project, config,
   tickets and run dir in a temp tree, torn down in the same block.
4. **Fake-binary-on-PATH injection** (H-49's stub `curl`). Generalises directly to a fake `claude`,
   `codex`, `gh`, `docker`.
5. **The self-wiring assertions** — `marketplace.json: <name> listed`, `run-all.sh: <name> in PLUGINS`.
6. **`bash -n` + `shellcheck -S warning` over every script** (H-1, H-2), and version/CHANGELOG
   discipline (H-3).
7. **The mutation procedure of §4.3** — scratch copy, asserting patcher, single-runner rerun, restore.

### 7.2 What has to be new

A three-tier architecture. Tier 1 is the gate; tiers 2 and 3 are opt-in.

**Tier 1 — deterministic, offline, in `run-all.sh`, seconds.** Everything here runs with zero model
calls. It needs four seams *designed into the orchestrator*, which is the real conclusion of this
document:

| Seam | Why | Testing payoff |
|---|---|---|
| `now()` — a single injectable clock | `faketime` absent (§6.4) | thresholds, ticks, stall ceilings, 7-day sweeps become instant |
| **Agent adapter** — one interface per platform (Claude Code, Codex, GLM, …) | R1-07, R1-11 | a fake adapter that can be *scripted to misbehave*: drop input, go silent, report done without doing, die mid-turn |
| **Quota/context source** — read through one function | R1-06, R1-08 | inject 89%/90%/91%, unreadable, `authentication_error`, wrong-account (FIELD-NOTES §11.7) |
| **Control-file tick** — a pure function `(state, file) → actions` | R1-07, Д7, Д12 | soft/hard/custom semantics testable without a running loop |

With those, tier 1 can assert the things that actually failed in production: the single-orchestrator
invariant under a real double-start race; hard-stop killing the current task and soft-stop letting it
finish; a control-file edit taking effect on the next tick; "stop only what you started" with a
control process the fixture started itself; a detector that must fire on a scripted-silent adapter and
must **not** fire on a scripted-busy one.

**Tier 2 — session-level, still free, opt-in (`ORCH_TEST_TMUX=1`), tens of seconds.** Real tmux, fake
agent processes. Proves the terminal layer, session identity, close/teardown, and the read-back
contract of §5.1. Must be idempotent (§3.2) and must not kill the tmux server on teardown.

**Tier 3 — `claude plugin eval`, paid, tagged, never in `run-all.sh`.** Reserve it for what only a real
model can answer: does the skill fire at all (`--ablation`, `tool_used: Skill`); does the orchestrator
prompt obey the red-line file (R1-15); does it escalate instead of guessing (FIELD-NOTES §9.1, eleven
questions routed rather than assumed); does it stay silent (Д11). Use `--max-cost-usd`,
`--runs 1` for routine passes, and free graders (`regex`, `tool_used`, `tool_order`, `file_exists`)
wherever an LLM judge is not strictly required.

### 7.3 Two rules to adopt outright

- **Every assertion must be mutation-proved at authoring time**, and the mutation recorded in a
  comment next to the test (`# MUTATION: narrow cfg_int's reject case → FAIL "no WARN on bad value"`).
  A test with no recorded mutation is presumed vacuous. §4.1 is the proof that this is not pedantry.
- **Ban the anti-check.** No assertion may be satisfiable by a string in a comment. Practically: a test
  may `grep` source only to assert something is *absent* (a ban), never to assert a behaviour is
  *present*. H-33 is the counter-example; H-4 (a naming ban) is the legitimate use.

---

## 8. The five things that most change how this should be tested

1. **A grep test proves a comment exists.** Measured, §4.1: the config-validation feature was deleted
   and H-33 stayed green because the sentence survived in a `# TODO`. 41 of the harness's 51 tests are
   this shape. The rebuild's gate has to be "does the code do it", and grep is admissible only for
   proving something is *absent*.
2. **The master runner itself has the bug it is meant to catch.** Measured, §3.1: a runner that asserts
   nothing and exits 0 silently aborts the whole aggregate — no message, no summary, and every later
   plugin never runs. There is also no floor on assertion count (§3.3) and every runner is executed
   twice (§3.2). Fix these before adding a stateful suite, and add a per-plugin minimum count.
3. **A naive fake agent tests the wrong contract.** Measured, §5.1: driven through the real tmux
   backend, an ordinary `read`-loop fake **does** submit stranded text on a bare Enter; FIELD-NOTES
   records that a real Claude session **does not**, which cost five operator instructions. The fix is a
   design rule, not a fixture: the orchestrator must never treat a send as delivered without a
   read-back, and `UserPromptSubmit` (§6.2) is a free, deterministic delivery receipt.
4. **Testability is four seams, and they are architecture decisions, not test code.** `now()`,
   an agent adapter, a quota/context source, and a pure `(state, file) → actions` tick. Without them,
   nothing in ANALYSIS-01's list (§5 table) is observable — and `faketime` is not installed here
   (§6.4), so the clock seam in particular cannot be retrofitted from outside.
5. **Claude Code now ships an eval runner, and it must sit on top of the free layer, not replace it.**
   `claude plugin eval` exists at 2.1.278 with six grader types, an ablation arm, mocks and cost
   ceilings — but defaults to 3 runs × 2 arms = 6 real sessions per case on the operator's own rate
   limit, and no plugin here uses it yet. Tier it: free deterministic gate always; paid eval tagged,
   budgeted and deliberate.

---

## 9. Verified on this machine (index)

| # | Fact | How |
|---|---|---|
| V1 | Full suite: 475 PASS / 0 FAIL, exit 0, **42.15 s** real | `bash tests/run-all.sh` timed |
| V2 | harness 51 tests in 5.18 s; ultra-analyzer 68 in 6.52 s; interview-handoff 39 in 0.25 s | timed individually |
| V3 | 10 of 51 harness tests execute plugin code; 37 are grep-over-source; 4 are lint/parse | per-block classification of `run.sh` |
| V4 | Deleting the config-JSON check while keeping its text in a comment leaves **H-33 green** | mutation A, restored |
| V5 | Narrowing `cfg_int`'s reject case makes **H-39 FAIL** with a behavioural message | mutation B, restored |
| V6 | A runner that exits 0 printing nothing **silently aborts the master suite**; later plugins never run | scratch `run-all.sh`, `PLUGINS=(fakep goodp)` |
| V7 | A runner claiming `PASS=1 FAIL=0` is accepted; no floor, no baseline | same scratch harness |
| V8 | Each plugin runner is executed **twice** per master run (lines 39, 49) | source + timing |
| V9 | `harness-term.sh` drives a fake agent end to end over **tmux 3.6a**, headless, no API call | spawn/capture/send/key/close probe |
| V10 | A `read`-loop fake agent **does** submit stranded text on a bare Enter (`GOT[stranded]`) — opposite of the real TUI | same probe |
| V11 | `term.sh close` on the last pane kills the tmux **server** | same probe |
| V12 | `claude plugin eval` exists at 2.1.278; `init --bare` writes `prompt.md` (`max_turns: 10`, `allowed_tools: [Read, Glob, Grep, Skill]`) + `graders/criteria.md` (`type: llm`, `weight: 1`), offline | run in a scratch plugin |
| V13 | Grader types are exactly `regex \| tool_order \| tool_used \| file_exists \| llm \| baseline`; `regex` takes `contains \| not_contains \| count:N` | loader error strings in the binary |
| V14 | Defaults: `runs = case.runs ?? 3`, `--ablation with-without` (2 arms), judge `haiku`, `--max-cost-usd`, `--threshold 1.0`, `-j 1..8` | `--help` |
| V15 | 11 hook events incl. **`PreCompact`/`PostCompact`**, `SubagentStart/Stop`, `UserPromptSubmit` | binary string inventory |
| V16 | No `evals/` dir and no `experimental.evals` anywhere in this repo | `find` / `grep` |
| V17 | No CI: `.github/workflows` does not exist | `ls` |
| V18 | `task-launch` has no `tests/run.sh` and is not in `PLUGINS` | `ls` + source |
| V19 | Installed: tmux, shellcheck, jq, gh, python3, git. **Missing: `bats`, `yq`, `faketime`** | `command -v` |
| V20 | `--plugin-dir`, `--session-id`, `--resume`, `--bg`, `--print`, `--output-format stream-json`, `--max-turns` all present | `--help` |
| V21 | The evidence file named in the brief (`…/scratchpad/context/harness-evidence.md`) **does not exist** on this machine | `ls`, `find` |
| V22 | Working tree left clean after both mutations | `git diff --stat -- plugins/harness/bin/` |
