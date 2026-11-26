# L1 — Contract and unit layer

**Spike:** harness-rebuild · **Written:** 2026-09-19 · **Layer:** L1 of the evaluation stack.
**Scope:** the deterministic core — config resolution, the watched control file, stop semantics, the
launch journal and the single-orchestrator lease, ticket readiness, threshold arithmetic, and the
state records needed to resume. **No network, no model, no terminal, no spend.**

**Evidence legend.** **[V]** verified — run on this machine in this session, or read in the source
named. **[C]** claimed — stated by a document I read (FIELD-NOTES, the ground research, ANALYSIS-01)
and not re-derived. **[I]** inferred — my reasoning from the two above, and arguable.

**Sources of truth.** Requirements: `round-1/ANALYSIS-01.md`. Failure corpus: `ground-failure-corpus.md`
(F-nn ids used verbatim below). Technique: `ground-testing-agentic-systems.md`. Substrate:
`ground-what-exists-here.md`. Config precedence: `docs/config-levels.md` and
`docs/decisions/0003-config-precedence-person-over-project.md` in
`<baseline-marketplace>` [V, read here].

---

## 0. The three decisions this layer rests on

Everything below is cheap if these are taken before the first line of the loop is written, and
unbuyable afterwards. They are architecture decisions, not test decisions.

1. **`decide(world) → plan` is a pure function, and `apply(plan)` is somebody else.** The tick does
   not decide and act in one breath. `decide` reads a JSON world on stdin and writes a JSON plan on
   stdout. Every scenario in §3–§9 is then a file pair, and the whole layer needs no processes.
2. **Nothing in `core/` calls the outside world.** No `date`, `curl`, `claude`, `gh`, `tmux`,
   `docker`, `kill`, `ps`, `pgrep`, `osascript`, `$SECONDS`, `$RANDOM`, no absolute binary paths.
   Time comes from `clock.sh now()`, which honours `ORCH_NOW`. The process table comes from
   `ORCH_PROC_PROBE`. This is enforced by a ban-lint (MET-02), which is the one legitimate use of
   grep-over-source in the whole suite.
3. **The resolved config is frozen at run start.** `orch-config.sh resolve` runs once, writes
   `runs/<id>/resolved.json` with a content hash and a per-key provenance map, and nothing re-reads
   the six config slots for the life of the run. Mid-run change arrives through exactly one audited
   channel — the control overlay (§4) — with soft/hard semantics. This makes "what config was this
   run using" a recorded fact rather than a reconstruction, which is what R1-06 part 2 asks for
   ("в реєстрі має записуватись кожен стан").

A fourth, smaller one: **JSON, not YAML.** `yq` is not installed on this machine [C,
ground-what-exists-here V19] and `jq` is. The owner named YAML as *a possible format, not fixed*
(R1-03). A YAML front-end is legitimate later as an adapter that emits JSON; every test in this
document then applies to it unchanged. Putting an untested YAML parser inside the deterministic core
today buys nothing and costs a dependency.

---

## 1. Directory layout and file formats

```
<project>/.orchestrator/
  lease/                        # the lock is the DIRECTORY (mkdir); holder.json sits inside it
    holder.json                 #   {run_id, pid, proc_start, host, started_at, version}
  control/                      # INBOUND. The orchestrator opens this tree READ-ONLY, always.
    settings.json               #   Д7 behaviour overrides — whole document, hash-debounced
    accounts.json               #   R1-07 role → account map
    cmd/<ulid>.json             #   Д12 one command per file, written elsewhere and renamed in
  runs/<run-id>/
    run.json                    # this run's scope config  → config slot 7
    resolved.json               # frozen resolved config + provenance + hash (written once)
    journal.ndjson              # append-only fact log; every line ≤ 1024 bytes
    stop.json                   # stop lattice state + attribution
    control-applied.json        # applied cmd ids, last applied settings hash (idempotence)
    sessions/<name>.json        # registry: role, platform, boot_account, pid, proc_start, cwd,
                                #   ticket, close_owner, spawned_at
    claims/<ticket-id>.json     # ticket claim, carries the holding run_id
    quota/<account>.ndjson      # per-account reading series
    status/                     # OUTBOUND. The only tree the orchestrator writes for humans.
```

**The two-direction rule is the whole point of the layout.** F-10 is the highest-leverage entry in
the corpus: the previous generation truncated the file it watched on every tick
(`harness-run.sh:226` `: > attention.tmp`, `:361` `mv … attention` [C, verified in source by the
corpus]) and silently ate every external write for a whole night. Here, inbound and outbound are
different trees with different owners, and the read-only property is not a convention — it is
asserted by running the tick against a control tree the fixture has chmodded (CTL-01).

**Atomic write, everywhere, one rule.** Any file this system produces is written to `<path>.tmp` in
**the same directory** and `mv`'d into place. No file is ever truncated in place. Verified here [V]:
an atomic-rename writer produced zero malformed observations across 300 writes under a concurrent
reader; a truncate-then-write writer, observed by a cheap `[ -s ]` reader, was caught empty **245
times at zero injected delay** and 92,139 times at 10 ms. That number matters twice — see §11.2 for
why the reader must be cheap.

**The journal line limit is 1024 bytes and it is enforced, not advised.** Measured here [V], 60
concurrent `>>` appenders to one file on this disk:

| Line length | Well-formed lines, per round |
|---|---|
| 200 | 60/60 |
| 1024 | 60/60 |
| 1536 / 2048 / 3072 | 60/60, 60/60 (two rounds each) |
| 4000 | 29/60 · 14/60 · **60/60** |
| 4096 | 57/60 · 11/60 · 12/60 |
| 4200 | 1/60 · 6/60 · **60/60** |

Two conclusions. First, concurrent appends interleave and corrupt somewhere above 3 KB, so a journal
whose records can grow is a journal that silently loses records. `orch-journal.sh append` therefore
**refuses** a line over 1024 bytes with exit 7 and writes the payload to `runs/<id>/blobs/<hash>`
with the line carrying only the reference. Refusal, never truncation — the same lesson as the
terminal's silent 1024-byte `MAX_CANON` cliff [C, ground-testing §11]. Second, and more important:
**a broken mechanism scored 60/60 twice**, at 4000 and at 4200. A green concurrency round is not
evidence. Every concurrency scenario in this layer runs a ladder of injected delays and several
rounds, and a single green round is treated as no result at all (§11.2).

**Module contracts.** Each is a bash script with verbs, reading JSON on stdin or from a rebindable
path, writing JSON on stdout, and exiting with a *typed* code — so a test asserts the reason, not
merely the failure.

| Module | Verbs |
|---|---|
| `core/orch-config.sh` | `resolve`, `explain <key>` |
| `core/orch-control.sh` | `read`, `plan` |
| `core/orch-stop.sh` | `state`, `apply <cmd.json>` |
| `core/orch-lease.sh` | `acquire`, `inspect`, `release` |
| `core/orch-journal.sh` | `append`, `read`, `verify` |
| `core/orch-ready.sh` | `verdict`, `render` |
| `core/orch-threshold.sh` | `verdict`, `series` |
| `core/orch-state.sh` | `snapshot`, `reconcile` |
| `core/orch-decide.sh` | (stdin world → stdout plan) |

```
0  ok                 4  invalid-input        8  lease-held (loser)
2  usage              5  not-ready            9  lease-refused (holder alive but stopped)
3  config-error       6  unknown (typed)      7  corrupt-state
```

**Injection seams.** `ORCH_PROJECT`, `ORCH_CONFIG_ROOT`, `ORCH_RUN` rebind every path — this is the
one property of the old harness worth keeping verbatim (`HARNESS_PROJECT` is why its only ten real
tests exist at all [C]). `ORCH_NOW` is the clock. `ORCH_PROC_PROBE` is the process table.
`ORCH_TEST_DELAY_<SITE>` injects a sleep at a *named* critical instant. `ORCH_RNG_SEED` seeds every
id. All five are read in exactly one place each, and MET-02 asserts that.

---

## 2. How a test is written, how it is run, how it fails loudly

**A scenario is a directory, not a function.**

```
plugins/orchestrator/tests/
  run.sh                    # the PASS=/FAIL= runner that tests/run-all.sh invokes
  EXPECTED-COUNT            # committed integer floor — see MET-01
  lib/assert.bash           # with_project(), with_clock(), with_procs(), diff_json(), normalise()
  cases/<GROUP>/<ID>/
    note.md                 # one paragraph: the requirement, and the F-id it guards
    setup.sh                # optional; builds the fixture beyond the declarative files
    config/…                # slot files to plant
    world.json              # the input
    cmd                     # the module + verb to run, and its argv
    expect.json             # expected stdout, normalised
    expect.exit             # expected exit code
    expect.stderr           # optional; expected warning lines, normalised
  mutations/*.mut
  run-mutations.sh
```

`run.sh` walks `cases/`, and for each case: `mktemp -d`, plant the fixture, run `cmd` with the seams
bound, normalise stdout (`<TS>`, `<PID>`, `<TMP>`, `<DUR>`, `<ULID>`, `<HASH>`), diff against
`expect.json`, compare the exit code, compare stderr if present. A case needing more than that
writes `setup.sh` and `assert.sh`; that escape hatch exists so no scenario gets dropped for being
awkward, and MET-06 caps how many cases may use it.

**Adding a scenario is adding a directory.** No bash is written for the common case. This is the
single property that decides whether the suite grows after the first month [I].

**How it fails loudly.**

- The failure line names the case id, the assertion, and prints a unified diff of normalised
  expected vs actual — never "FAIL H-33".
- On failure the tmpdir is **kept**, and its path is printed. `ORCH_KEEP_TMP=1` keeps it always.
- **A case that executes zero assertions is a failure**, not a pass. The runner counts assertions per
  case and fails a case that made none. This kills the vacuous-by-omission case, which is how a
  suite quietly loses 40 of 51 tests and still reports green [C, ground-what-exists §3.3].
- The runner prints the conservation identity `total == pass + fail + skip` and **fails if it does
  not hold**, and fails if `total < EXPECTED-COUNT`. This is F-32's assertion turned on the suite
  itself: the previous generation shipped five phases on a test run that reported 346 passed of a
  declared 382 [C].
- Exiting on a signal sets the run `incomplete`, never `pass`.

**Registration.** `plugins/orchestrator/tests/run.sh` prints a final
`orchestrator tests: PASS=<n>  FAIL=<m>` and exits 0 iff `FAIL=0` — the contract `tests/run-all.sh`
requires [V, read here]. `orchestrator` is added to its `PLUGINS` array, and MET-03 asserts that,
because a plugin missing from that array is invisible with no warning [V].

**Two prerequisites in `tests/run-all.sh` that L1 must not walk into.** Both verified by the ground
research [C, ground-what-exists §3.1–3.2] and confirmed by reading the file here [V]:

1. It calls `set -e` at lines 41 and 50 believing it restores a flag that was never on. With
   `pipefail` already set, a runner that prints no `PASS=` line kills the master script silently and
   **every later plugin never runs**. L1 must always print its summary line, on every path including
   a signal — and the fix to `run-all.sh` should land in the same PR.
2. It runs every runner **twice** to re-scrape the counts. So every L1 case must be idempotent and
   leave nothing outside its own tmpdir. MET-04 asserts exactly that. A stateful suite that leaks
   would fail on its second invocation and be blamed on flakiness.

---

## 3. CFG — config resolution and the six-slot precedence

**Inherited verbatim** from `docs/config-levels.md` §2–§6 and decision 0003 [V, read here]: six
slots, three bands, a person's own files above the project's committed files, per-plugin above
general inside a band; objects deep-merge, `use` is replaced whole, `never` accumulates as a sorted
deduplicated union; a missing file is an empty slot; an unknown key inside a source block is a
warning that costs only itself; `x-` keys are legal; a config-shaped file outside the table is not
config and produces one warning rather than silence.

**Two deltas this orchestrator adds.**

- **Slot 7 — the run scope.** `runs/<run-id>/run.json`, written by the person starting this run, sits
  **above all six**. It is personal and it is the nearest possible file, which is exactly what the
  band-then-specificity rule already implies. R1-04 and R1-12 both require default/project/per-run.
- **Slot 8 is not a slot.** The live control overlay (§4) is deliberately *not* merged at resolve
  time. It is applied per tick with soft/hard effectivity. Folding it into the merge would make
  "what config is in force" a function of when you asked, which destroys resumability [I].

```
1 ./.claude/shared/identity.json                     committed, project general
2 ./.claude/shared/plugins/orchestrator.json         committed, project per-plugin
3 <config-root>/shared/identity.json                 personal, home, general
4 <config-root>/shared/plugins/orchestrator.json     personal, home, per-plugin
5 ./.claude/shared/identity.local.json               personal, this project, general
6 ./.claude/shared/plugins/orchestrator.local.json   personal, this project, per-plugin
7 .orchestrator/runs/<run-id>/run.json               this run          ← new
─ .orchestrator/control/settings.json                live overlay, §4  ← not merged here
```

`<config-root>` is `CLAUDE_CONFIG_DIR` verbatim when set, else `$HOME/.claude`; always absolute,
never containing `~`.

**CFG-01 · The highest slot that sets a key supplies the value**
Pre: the same key set in all seven slots with seven distinct values. Trigger: `resolve`. Expect: the
slot-7 value, and `provenance["<key>"] == 7`. Assert: resolved value **and** provenance slot, for
each of seven keys seeded one per slot. Catches: requirement-only (Д1). The provenance half is what
makes a later precedence regression name itself.

**CFG-02 · A person's home file beats the project's committed file**
Pre: slot 2 sets `accounts.worker`; slot 3 sets it differently. Trigger: `resolve`. Expect: slot 3.
Assert: value + provenance. Catches: requirement-only — this is decision 0003's deciding case, and
it is the one an implementer gets backwards by instinct.

**CFG-03 · A missing file is an empty slot, not an error, and not a default**
Pre: slots 2, 4, 5, 6, 7 absent. Trigger: `resolve`. Expect: exit 0; result identical to the same
run with those files present and holding `{}`. Assert: byte-identical resolved JSON between the two
runs. Catches: requirement-only (`config-levels` §4).

**CFG-04 · Two runs over identical contents produce identical output**
Pre: a fixture with all seven slots and three `never` arrays. Trigger: `resolve` twice. Expect:
byte-identical stdout, including array order. Assert: `cmp`. Catches: requirement-only — but it is
the property that lets `resolved.json`'s hash mean anything (RES-01).

**CFG-05 · `use` is replaced whole; every other object deep-merges**
Pre: slot 1 `use = {kind: mcp, server: linear}`; slot 3 `use = {kind: cli, command: clkup}`; both
set unrelated sibling keys. Trigger: `resolve`. Expect: `use` is slot 3's object entire, carrying no
`server`; siblings merged. Assert: exact object identity of `use`, and presence of both siblings.
Catches: requirement-only. It is the one exception in the merge rule and therefore the one an
implementer drops.

**CFG-06 · `never` accumulates across a person's files and holds against their own pick**
Pre: slot 3 `never: ["mcp:clickup"]`, slot 5 `never: ["cli:gh"]`, slot 6 `use = {kind:cli, command:gh}`.
Trigger: `resolve`. Expect: the union, sorted, deduplicated; the source is **skipped** with a reason
naming both files; exit 3. Assert: the array, the skip, the reason naming both paths. Catches:
requirement-only (`config-levels` §5) — a self-contradiction the person must settle, which must not
be silently resolved either way.

**CFG-07 · A committed veto cannot strike a tool the person named**
Pre: slot 2 `never: ["cli"]`; slot 4 `use = {kind: cli, command: clkup}`. Trigger: `resolve`. Expect:
`cli:clkup` stands; every other `cli` candidate is still struck. Assert: the pick survives **and** a
second candidate is filtered. Catches: requirement-only — the half-implemented version (drop the
veto entirely once a person sets anything) is the one decision 0003 explicitly rejects.

**CFG-08 · `{"kind":"auto"}` names no tool, so a committed veto still filters detection**
Pre: slot 2 `never: ["mcp"]`; slot 4 `use = {kind: auto}`. Trigger: `resolve`. Expect: detection
proceeds with `mcp` candidates filtered. Assert: the candidate list. Catches: requirement-only.

**CFG-09 · A `never` entry that strikes nothing is reported, never corrected**
Pre: slot 5 `never: ["mcp:clikcup"]` (typo). Trigger: `resolve`. Expect: exit 0, one warning naming
the entry **and the file it was written in**; no file is modified. Assert: stderr line + `cmp` of
every slot file before and after. Catches: requirement-only. The no-modification half is the
important one.

**CFG-10 · An unknown key inside a source block costs only itself**
Pre: slot 4 sets `connectors.tasks.{use, bogus, x-note}`. Trigger: `resolve`. Expect: exit 0;
`bogus` absent from the resolved config with one warning naming key and file; `use` and `x-note`
present; the rest of the file loads. Assert: all four facts. Catches: requirement-only — the failure
mode is a config that refuses to load over one stray key at 3 a.m.

**CFG-11 · A config-shaped file in the wrong directory is not config, and is not silent**
Pre: `./.claude/shared/orchestrator.json` (a path the table does not name) holding a real value.
Trigger: `resolve`. Expect: the value does not appear; one warning names the file. Assert: absence +
the warning. Catches: requirement-only. Silent inertness is the failure being prevented.

**CFG-12 · A process kind and custom steps in the resolved config is a hard error**
Pre: slot 2 sets `process.kind = "gsd"`; slot 6 adds `process.steps = [...]`. Trigger: `resolve`.
Expect: **exit 3**, message naming both slots and both keys; no resolved config emitted. Assert: exit
code, both slot numbers present in the message, empty stdout. Catches: requirement-only, and it is
the sharpest one in this group — R1-03 is explicit that a ready process and a custom one do not mix
("комбінувати ні, тут або або"), and deep-merge across slots is exactly the mechanism that produces
a mixture nobody wrote. The contradiction is a property of the *resolved* config, so it cannot be
caught by validating files one at a time.

---

## 4. CTL — the watched control file protocol

R1-07, Д7 and Д12 all land on one watched surface, and F-10/F-11/F-12 say this is where the previous
generation lost every external write. The protocol:

- **Inbound is read-only to the orchestrator, always.** Two shapes inside it: `settings.json` and
  `accounts.json`, whole documents read wholesale; and `cmd/<ulid>.json`, one command per file.
- **A command is a file, not a line.** One command per file, written to a tmp path and renamed in, so
  it is never observed half-written and two writers never interfere. A directory spool also makes
  "acted on exactly once" naturally expressible — by command id, in the journal.
- **Change is detected by content hash, never by mtime alone.** mtime has coarse granularity, is
  moved by `touch` and by editors that rewrite unchanged files, and is not moved by a same-second
  edit. `control-applied.json` records `settings_hash` and the set of applied cmd ids.
- **Debounce means silence, not suppression.** An unchanged hash produces no action and no output
  (Д8: silent when nothing changed, reports what changed when something did). A *changed* hash is
  never debounced.
- **Last-good on invalid.** An unparsable `settings.json` keeps the previously applied settings,
  warns once per distinct hash, and never applies half a document.
- **The orchestrator never writes into `control/`.** Not to quarantine, not to acknowledge, not to
  mark read. Acknowledgement goes into the journal and `status/`.

**CTL-01 · The tick runs against a read-only control tree**
Pre: `control/` mode 0500 and `settings.json` mode 0400. Trigger: `orch-control.sh read` then `plan`,
three consecutive ticks. Expect: exit 0 every tick; settings applied. Assert: success, plus `cmp` of
every inbound file before and after. **Both modes are required** — verified here [V]: `chmod 500` on
the directory blocks *creating* a file but a truncating write to an existing file still succeeds;
only `chmod 400` on the file refuses it. A test that chmods the directory alone passes against a
truncating implementation. Catches: F-10 — the single highest-leverage test in the corpus. A
truncate-then-`mv` implementation cannot pass this, because `mv` into a 0500 directory fails.

**CTL-02 · A second writer's append survives a tick**
Pre: a run at tick N. Trigger: another process drops `cmd/<ulid>.json` into the spool, then ten ticks
run. Expect: the command is readable after all ten, and was acted on exactly once. Assert: the file
still exists with identical bytes; the journal holds exactly one `control.applied` record for that
id. Catches: F-10 — the corrections written all night and discovered lost only by grepping for a
block written four minutes earlier [C].

**CTL-03 · The same command is not applied twice**
Pre: `cmd/X.json` already recorded in `control-applied.json`. Trigger: twenty further ticks. Expect:
no action, no output. Assert: journal count for X stays at one; plan is empty on all twenty ticks.
Catches: F-40 — the 85-minute loop that pressed Escape and sent `continue` every 60 s because the
screen it was reacting to never changed [C]. Level-triggered logic on an unchanged input must act
once; this is that property, tested where it is cheap.

**CTL-04 · `decide` on an unchanged world is idempotent**
Pre: any `world.json`. Trigger: `orch-decide.sh` twice, the second time with the first plan's effects
folded into the world. Expect: the second plan is empty. Assert: `plan.actions == []`. Catches: F-40,
F-42 (one condition re-flagged 1085 times over five days [C]). Two lines of test, one whole bug class.

**CTL-05 · A torn `settings.json` never applies half**
Pre: a valid applied settings document. Trigger: a writer that truncates and pauses at
`ORCH_TEST_DELAY_SETTINGS_WRITE` ∈ {0, 1 ms, 10 ms}, while ticks run throughout. Expect: every tick
either keeps the last good document or applies a complete new one; never a partial one, never a
crash. Assert: after each tick, the in-force settings equal one of the two complete documents; a zero
byte or partial parse is a failure. Catches: F-11 — `attention.tmp` found truncated to zero bytes on
every pass, one of the two factors that compounded the 85-minute loop [C]. **The reader in this test
must be cheap.** Verified here [V]: a reader that spawns `jq` per read (≈18 ms) observed **zero** bad
reads against a truncating writer over 300 writes, while a `[ -s ]` reader caught it 245 times at
zero injected delay. An expensive probe hides the bug it is looking for.

**CTL-06 · An invalid command is not obeyed, and is reported once**
Pre: `cmd/Y.json` holding malformed JSON. Trigger: fifty ticks. Expect: no action; exactly one
warning naming the file; nothing written into `control/`. Assert: one stderr line across fifty ticks
(not fifty), the plan empty, `control/` unchanged. Catches: F-42's shape — a condition re-flagged
1085 times over five days, unresolved [C]. The "once" half is the assertion.

**CTL-07 · An unknown command verb is refused, never approximated**
Pre: `cmd/Z.json` with `verb: "stop-softish"`. Trigger: a tick. Expect: exit 4 for that command;
a notify action; no stop. Assert: exit code and the absence of any stop action. Catches: F-16's
class — the honest read and the unsafe action coexisting. An unrecognised control input must not be
rounded to the nearest known one.

**CTL-08 · An unchanged hash produces no output at all**
Pre: settings applied. Trigger: `touch control/settings.json`, then ten ticks. Expect: zero stdout,
zero stderr, zero journal records. Assert: all three empty. Catches: requirement-only (Д8, Д11) —
and it is the test that pins mtime-vs-hash, because a mtime-triggered implementation fails it.

**CTL-09 · A changed hash is applied on the next tick — not this one, not two later**
Pre: settings applied at tick N; the file is rewritten during tick N. Trigger: ticks N, N+1, N+2.
Expect: tick N's plan is computed from the old settings; N+1 applies the new; N+2 is silent. Assert:
the exact tick index of application. Catches: requirement-only (Д7: the change must be picked up
*during* a run, and the run must not half-apply it mid-decision).

**CTL-10 · An account change carries soft or hard, and soft does not disturb live sessions**
Pre: two live sessions on account A. Trigger: `accounts.json` reassigns the role to B with
`mode: soft`. Expect: running sessions keep account A in the registry; only new spawns use B.
Assert: `sessions/*.json` `boot_account` unchanged; the next spawn action carries B. Catches: F-19's
adjacent finding — a session already booted keeps the account it booted with, and the previous
generation had to edit a second script because it watched the watched account by hard-coded path [C].

**CTL-11 · A hard account change stops current work now**
Pre: same. Trigger: `mode: hard`. Expect: stop actions for the affected live sessions in this tick's
plan; no new spawn on the old account. Assert: the action set. Catches: requirement-only (R1-07).

**CTL-12 · The control path resolves to one absolute location, whatever the writer's cwd**
Pre: a project with two git worktrees. Trigger: a simulated session in each worktree writes a command
by relative path. Expect: the orchestrator's single reader sees both; and a configured control path
that resolves differently from two cwds is **rejected at resolve time**, exit 3. Assert: both
commands seen; the bad configuration refused before the run starts. Catches: F-12 — `QUESTIONS.md`
forked into a worktree's own copy and an owner-facing question sat invisible for an hour [C]. Д4's
default (every task in its own worktree) makes this the normal case, not the exception.

**CTL-13 · Commands are applied in a defined order, and it is not directory order**
Pre: three commands whose `issued_at` order differs from their filename order. Trigger: one tick.
Expect: applied in `issued_at` order, ties broken by ulid. Assert: the journal's applied sequence.
Catches: requirement-only [I]. Filesystem readdir order is not sorted and differs between
filesystems; a stop arriving out of order behind a resume is the failure this prevents.

---

## 5. STP — stop-hard, stop-soft, stop-custom

**The lattice.** `running < soft < hard`, and the state only moves up. A `resume` is legal from
`soft` and illegal from `hard` (a hard stop is the human's; only a human clears it). This makes
"hard beats soft" a structural property rather than a code path, and it makes the whole group
table-driven.

**Attribution is mandatory.** Every stop record carries `{cmd_id, source, actor, reason, at}`. A
record missing any of them is **corrupt**: the reader escalates and does **not** stop (exit 7). And
the writer cannot produce one — the record is written as a single atomic rename of a complete
document, so there is no window in which half of it exists.

**STP-01 · stop-soft starts nothing new and lets live work finish**
Pre: two live sessions, three ready tickets, capacity 4. Trigger: `stop-soft`. Expect: plan contains
no spawn; no stop action against the live sessions. Assert: action set by type. Catches:
requirement-only (Д12).

**STP-02 · stop-soft completes the run when the last session ends**
Pre: state `soft`, one live session. Trigger: that session completes. Expect: `run.complete` written
with attribution; teardown limited to what this run started. Assert: the completion record and the
teardown target set. Catches: F-42 — a dead run flagging `STOPPED present with no run.complete` every
three minutes for about five days, 1085 times [C]. That condition exists because stopping and
completing were two unrelated writes; here completion is a transition of the same record.

**STP-03 · stop-hard acts in the tick it arrives**
Pre: two live sessions. Trigger: `stop-hard`. Expect: stop actions for both, in this tick's plan.
Assert: the actions, and that they name only sessions in this run's registry. Catches: requirement-only
(Д12), with the blast-radius half from R1-16.

**STP-04 · Hard beats soft regardless of arrival order**
Pre: `running`. Trigger: the four orderings of {soft, hard} across one and two ticks. Expect: state
`hard` in all four; no ordering yields `soft`. Assert: final state for each of the four rows.
Catches: requirement-only — the cross-cutting soft/hard vocabulary (ANALYSIS §cross-cutting 3). This
is a property, and it is checked after every action of every scenario, not only here (§11.2).

**STP-05 · Resume is legal from soft and refused from hard**
Pre: state `soft`, then state `hard`. Trigger: `resume`. Expect: `running` in the first case; refusal
with exit 4 and an unchanged state in the second. Assert: state + exit code for both. Catches:
requirement-only (R1-14: even in an autonomous run an agent may force a hard stop, and the human
releases it — "поки людина не відпустить").

**STP-06 · stop-custom is carried verbatim and never interpreted by the core**
Pre: a custom rule of free text. Trigger: `stop-custom`. Expect: one `escalate_custom_stop` action
carrying the rule byte-for-byte; no stop, no spawn; state unchanged this tick. Assert: byte equality
of the carried rule, and the absence of any stop action. Catches: requirement-only (Д12), and it is
the boundary test for R1-13: the deterministic core must not guess at the user's prose. A core that
starts pattern-matching custom rules fails this.

**STP-07 · An uninterpretable custom stop fails closed to soft**
Pre: a custom rule the decision layer returns `undecidable` for. Trigger: the tick that receives that
answer. Expect: state `soft` plus a notify action — never `running`. Assert: state + notify.
Catches: F-16 — `UNKNOWN` converted to "carry on" by the policy layer while the read itself was
honest. The same mistake, one layer up. This is the scenario most worth defending in review.

**STP-08 · A stop record without attribution is corrupt, and is not obeyed**
Pre: `stop.json` holding `{state: "hard"}` and nothing else. Trigger: a tick. Expect: exit 7; a
notify action; the run does **not** stop. Assert: exit code, notify present, no stop actions.
Catches: F-23 (`#82`, open at the time of the field notes [C]) — an unattributed `STOP` left on disk
after a failed marker write, the run stopped, and nothing recorded who or why.

**STP-09 · A failed stop write leaves no stop behind**
Pre: the run directory made unwritable at `ORCH_TEST_FAIL_STOP_WRITE`. Trigger: `stop-hard`. Expect:
the command fails loudly (exit 7) and `stop.json` is either absent or the previous complete document —
never a new partial one. Assert: the file's content is one of the two legal values. Catches: F-23's
writer side — the state F-23 rejects on read must also be unreachable on write.

---

## 6. LEA — the single-orchestrator lease

R1-10 states this as an absolute: *"якщо раптом одночасно два якісь оркестратори працюють, то це не
окей."* The previous generation has **no guard of any kind** — the corpus verified
`grep -rniE 'already running|pidfile|singleton'` over `bin/*.sh` returns nothing [C]. So there is
nothing to inherit and everything to specify.

**Mechanism.** `mkdir "$PROJECT/.orchestrator/lease"` is the acquire. Verified exclusive here [V]:
60 concurrent acquirers × 3 rounds at zero delay and × 3 rounds with a 20 ms delay injected between
the `mkdir` and the holder write — **one winner every round, six rounds**. `flock` is absent on
macOS [C]; `noclobber` is equally exclusive [C] and is the fallback. After winning, the holder writes
`holder.json` atomically inside the directory.

**Liveness is proved by pid *and* process start time**, never by name. `ORCH_PROC_PROBE` yields
`pid start_epoch cmdline` rows; the recorded `proc_start` must match. A dead pid, or a live pid whose
start time differs, means stale. Nothing anywhere keys on a process name, a window title or a
`pgrep` pattern — FIELD-NOTES records a `question`-role session whose terminal title read
`harness-question-q-screen-orchestrator`, which the product owner himself read as a second
orchestrator [C].

**LEA-01 · Exactly one winner, under perturbation**
Pre: no lease. Trigger: 60 concurrent `acquire` calls, 3 rounds each at
`ORCH_TEST_DELAY_LEASE_WRITE` ∈ {0, 1 ms, 5 ms, 20 ms}. Expect: exactly one exit-0 per round; 59
exit-8. Assert: the winner count for every one of the twelve rounds. Catches: F-13. **The ladder is
not decoration** — the corpus measured a categorically broken check-then-write primitive passing five
rounds of 100 at zero delay and only failing as the delay widened (1 → 5 → 13 → 26 winners) [C], and
my own append probe here [V] reproduced the same trap from a different direction.

**LEA-02 · The loser exits with a typed code and a message naming the holder**
Pre: lease held. Trigger: `acquire`. Expect: exit 8; stderr names the holder's run id, pid and start
time. Assert: exit code + all three fields. Catches: F-13 — and it is what makes the second
orchestrator's failure legible instead of mysterious.

**LEA-03 · The loser touches nothing**
Pre: lease held; the run tree seeded with a sentinel file and a recorded hash of every path. Trigger:
`acquire` by a second orchestrator, then a full failed startup path. Expect: the tree hash is
unchanged; the sentinel is intact; no session, container or process is acted on. Assert: tree hash
equality and an empty recorded action set from the fake `kill`/`docker` recorders. Catches: F-13 +
R1-16 + Д3 — exclusivity is only half the requirement, and the corpus says so explicitly.

**LEA-04 · A dead holder's lease is reclaimed, with the evidence recorded**
Pre: `holder.json` naming a pid absent from the probe. Trigger: `acquire`. Expect: exit 0; the journal
records the reclaim with the dead pid and the recorded `proc_start`. Assert: acquisition + the
journal record's fields. Catches: F-13 stale-lock, and R1-10's "start over means restart the
orchestrator, not redo the work".

**LEA-05 · A stopped holder is not dead**
Pre: `holder.json` naming a pid the probe reports alive with a matching start time — the shape of an
orchestrator paused inside a quota wait, or `SIGSTOP`ped. Trigger: `acquire`. Expect: exit 9, no
reclaim. Assert: exit code + the lease directory untouched. Catches: F-13 case 2. An orchestrator
waiting out a reset is the normal state under R1-06, so the naive "not responding ⇒ dead" reading
would reclaim a healthy run routinely.

**LEA-06 · A reused pid does not read as alive**
Pre: `holder.json` naming a pid the probe reports alive but with a **different** start time.
Trigger: `acquire`. Expect: exit 0, reclaimed, journal records the start-time mismatch as the reason.
Assert: acquisition + the reason field. Catches: F-13 case 3 — `kill -0` on a recycled pid is the
classic trap and the only defence is the second field.

**LEA-07 · Liveness never keys on a name**
Pre: the probe's table contains a process whose command line is literally
`bash -c 'orchestrator run ...'` and which is not the holder. Trigger: `acquire` against an absent
holder pid. Expect: reclaimed — the impostor is ignored. Assert: acquisition, plus the ban-lint that
`core/orch-lease.sh` contains no `pgrep`, no `pkill`, no `-f` match. Catches: F-13 case 4 and F-45 —
`pkill -f 'playwright test'` killed an unrelated lane because that lane's own prompt text contained
the pattern [C].

**LEA-08 · The health checker cannot revive a live run**
Pre: lease held by a live holder. Trigger: the recovery entry point R1-10 requires (a detached agent
run every N hours). Expect: exit 9, no second orchestrator, one notify. Assert: exit code + no new
lease + the notify. Catches: F-13's first listed precondition — the health-check agent reviving a run
whose orchestrator is alive but quiet is precisely how the owner's "нескінченний цикл оркестраторів"
begins.

**LEA-09 · Every detached entry point survives `env -i`**
Pre: nothing. Trigger: each entry point under `env -i` with only its **declared** environment.
Expect: it either works or fails loudly at startup; it never produces a degraded-but-plausible
result. Assert: exit 0 with correct output, or a non-zero exit naming the missing variable — a
silent partial result is a failure. Catches: F-20 — three detached scripts had to export the `gh`
account themselves because `launchd` and `nohup` start with no environment, and `harness-limits.sh
verdict` returns `UNKNOWN` unless called with `HARNESS_ROLE` prefixed [C]. R1-10's health check is
detached by definition.

**LEA-10 · `declared_env ⊇ actually_read_env`, per component**
Pre: each core module's declared environment list. Trigger: run it under `env -i` with only the
declared set, and again with the declared set minus one variable at a time. Expect: the full declared
set works; each removal fails loudly. Assert: both directions. Catches: F-20's structural fix, and it
is the version that does not rot — a module that grows a new dependency fails the day it is added.

**LEA-11 · Release is idempotent and never releases someone else's lease**
Pre: lease held by run A. Trigger: `release` from run B, then twice from A. Expect: B's release exits
4 and changes nothing; A's first succeeds; A's second exits 0 and is a no-op. Assert: three exit
codes + the lease directory's state after each. Catches: requirement-only [I] — the second-release
case is what a crashed-then-restarted orchestrator does.

---

## 7. JRN — the launch journal

The owner's own words for this (R1-10): *"має бути якісь лог файлів, коли що запустилось."* The
journal is the append-only record of what this run started, and it is the substrate for
"stop only what you started" (R1-16, Д3) and for resume (RES).

**JRN-01 · Concurrent appends do not interleave, across a size ladder**
Pre: an empty journal. Trigger: 60 concurrent `append` calls, 3 rounds, at payload sizes {200, 1024}
bytes. Expect: 60 well-formed lines every round, and the set of ids equals the set written. Assert:
`jq -c .` line count == 60 and the id set. Catches: the mechanism measured here [V] — above ~3 KB
concurrent appends corrupt, and **a broken size scored 60/60 in two separate rounds**, so the ladder
and the rounds are the test, not decoration.

**JRN-02 · A line over the limit is refused, not truncated**
Pre: a record whose serialisation exceeds 1024 bytes. Trigger: `append`. Expect: exit 7; the payload
written to `blobs/<hash>`; the journal line carries the reference and nothing is lost. Assert: exit
code, blob content, the reference, and that the journal line is under the limit. Catches: the same
measurement, plus the shape of F-03 — the terminal's silent truncation above 1024 characters, where
no layer raised an error [C]. Refusal is the contract in both places.

**JRN-03 · Every record names an actor and an effect, and is written after the effect**
Pre: a fixture where the recorded action fails. Trigger: `apply` of one action. Expect: exactly one
record, saying *failed*, carrying the observed evidence. Assert: record count == 1 and its outcome
field. Catches: F-52 — a security review of a single API read found 26 refusal events in the audit
log that never occurred [C]. Logging from intent rather than outcome is the root, and this is its
cheapest test.

**JRN-04 · A retry sequence produces the declared number of records**
Pre: an action configured for three attempts. Trigger: all three fail. Expect: the count the model
declares — one record with three attempts, or three records; either is fine, the test pins it.
Assert: exact count and attempt numbering. Catches: F-52's amplification path (26 phantom events from
one real read [C]).

**JRN-05 · `verify` rejects a journal with a malformed or out-of-order line**
Pre: a journal with one truncated line, and one whose sequence goes backwards. Trigger: `verify`.
Expect: exit 7 naming the line number and the defect. Assert: exit code + the line number. Catches:
requirement-only [I] — it is the check that makes a resume refuse a corrupt history rather than
reconstruct a plausible one.

**JRN-06 · The started-set is exactly the journal's spawn records**
Pre: a journal with four spawns, two closes, and a fifth process present in the world that the
journal never recorded. Trigger: `orch-state.sh snapshot`. Expect: `started_set` has four entries;
the fifth is classified `not-mine`. Assert: set equality and the classification. Catches: F-44 and
F-48 — a `docker compose down -v` on the owner's default project with the actor unknown, and ~150
orphaned volume pairs from a dead prior run [C]. Д3's "stop what it started, touch nothing else" is a
set-containment property, and this is the record it is computed from.

---

## 8. RDY — readiness

R1-04 leaves the structure to be designed and says the tag is an example only; R1-04 also makes the
board a working surface with user-overridable status names. So readiness is a pure function of
`(ticket, resolved config, world)` returning `READY` or `NOT_READY(<code>)`, where the codes are a
closed set: `missing-section`, `unknown-status`, `ambiguous-status`, `unmet-dependency`,
`claimed-live`, `blocked`, `needs-review`, `body-too-short`, `id-collision`.

**A closed reason set is the design decision.** The reason travels into the board comment, the status
output and the journal, so a new reason is a deliberate act rather than a new string somebody typed.

**RDY-01 · A ticket missing a required section is not ready, and says which**
Pre: config requires Outcome / Scope / Acceptance; a ticket omits Acceptance. Trigger: `verdict`.
Expect: exit 5, `NOT_READY(missing-section)`, the section named. Assert: code + the named section.
Catches: M2/M3 from the two mutation experiments — disabling the ready floor so any body becomes a
ready ticket passed the old suite 51/51 in one experiment and was caught only by the three tests that
executed the script in the other [C].

**RDY-02 · An unknown status is not ready**
Pre: a ticket in a status absent from the configured status map. Trigger: `verdict`. Expect:
`NOT_READY(unknown-status)`. Assert: the code. Catches: requirement-only — fail closed. R1-04 makes
status names configuration, so an unmapped name is a routine occurrence, not a corruption.

**RDY-03 · Two state labels are ambiguous, never ready**
Pre: a ticket carrying both `done` and `blocked`. Trigger: `verdict`. Expect:
`NOT_READY(ambiguous-status)`. Assert: the code. Catches: F-50 — `harness-tickets.sh done` leaves a
previously blocked issue holding two state labels, because `blocked` is never removed; seen twice
[C].

**RDY-04 · Every transition leaves exactly one state label, from every reachable predecessor**
Pre: the declared transition table. Trigger: apply every legal transition from every reachable state,
exhaustively. Expect: exactly one state label after each. Assert: label count == 1 for every pair.
Catches: F-50 — and the reason it is path-exhaustive rather than an example is that the historical
bug appeared only on `ready → blocked → … → done`. A happy-path example never sees it.

**RDY-05 · A dependency-blocked ticket never becomes ready**
Pre: ticket B depends on A; A is not done. Trigger: `verdict` for B at every status A can hold.
Expect: `NOT_READY(unmet-dependency)` for all of them. Assert: the code across the table. Catches:
requirement-only (R1-05, where the owner retracted machine-resource awareness but kept dependency
blocking). The corpus notes the observed throughput limit was dependencies, not quota [C] — this is
the constraint that actually binds.

**RDY-06 · A ticket claimed by a live session is not ready**
Pre: `claims/7.json` held by a session the probe reports alive. Trigger: `verdict`. Expect:
`NOT_READY(claimed-live)`. Assert: the code. Catches: F-15 adopt-and-duplicate — re-claiming a ticket
a live worker is still executing.

**RDY-07 · Readiness does not depend on the ticket id**
Pre: a ready ticket. Trigger: `verdict` on it and on a copy with a different id. Expect: identical
verdicts and identical reasons. Assert: equality. Catches: requirement-only [I] — a metamorphic
relation, nearly free, and it catches id-dependent logic of the kind that produced F-53's branch name
computed from a slug.

**RDY-08 · Consistently renamed statuses yield identical verdicts**
Pre: the same ticket set under two status maps that are a pure renaming of each other. Trigger:
`verdict` on all of them. Expect: the verdicts correspond one-to-one. Assert: the mapping. Catches:
requirement-only (R1-04's user-overridable status names) — it is the test that proves the names are
configuration rather than constants hiding behind a lookup.

**RDY-09 · A hostile ticket body renders inert, and does not change the verdict**
Pre: bodies containing the orchestrator's own template tokens, a fence sentinel, 10k characters, ANSI
escapes, and a paragraph claiming to be a system message. Trigger: `render` and `verdict`. Expect: a
golden rendered prompt per body with the tokens neutralised; verdicts unchanged from the benign
control. Assert: golden diff + verdict equality. Catches: F-57 — a ticket whose body quoted the
harness's own template tokens broke a spawn [C]. This is also the single test class the old suite
did have (its `H-44`), and it earned its place: it was the one mutation of seven that the suite
caught [C].

**RDY-10 · Concurrent `add` never produces a duplicate id**
Pre: an empty ticket store. Trigger: 2, 20 and 50 concurrent `add` calls, 3 rounds each, across the
`ORCH_TEST_DELAY_ID_ALLOC` ladder. Expect: `count(distinct ids) == count(adds)` every round, and an
allocator that cannot guarantee uniqueness **refuses** rather than colliding. Assert: the id counts
and the refusal path. Catches: F-51 / F-49 — **and this one needs no mutation, because the bug is
live in this repository right now**: `l_add()` in `plugins/harness/bin/harness-tickets.sh` allocates
with an unlocked read-then-write, a documented fix landed only in the installed copy, and the source
`grep` for any locking primitive returns only the word `blocked` [C, verified by the corpus]. Two
concurrent adds produced two files under one id in five rounds of five; twenty adds produced twenty
files under three ids [C]. **Write this test first and watch it fail against the current source.**

---

## 9. THR — soft and hard threshold arithmetic

R1-06 (limits) and R1-08 (context) are the same arithmetic with different inputs, and R1-08 is the
one the owner stated most strongly: *"повинен бути механізм, який гарантовано робить цю дію."*
Nothing in the previous plugin measures context at all — `grep` over `bin/*.sh` for
`compact|ctx=|context.?window` returns only token-quota percentages [C, verified by the corpus].

`orch-threshold.sh verdict` takes a *reading* and *thresholds* and returns
`OK | SOFT | HARD | UNKNOWN(<type>) | MISMATCH`, where the unknown types are `Unauthenticated`,
`Unreachable`, `Malformed`, `Absent`.

**THR-01 · The boundary is exactly where the config says**
Pre: `soft=90, hard=97`. Trigger: readings 89.99, 90, 90.01, 96.99, 97, 97.01. Expect: OK, SOFT,
SOFT, SOFT, HARD, HARD — with `>=` stated in the case and pinned by the 90 and 97 rows. Assert: all
six. Catches: the near-miss the shipped code's own comment describes — an integer comparison would
error on a fractional percent and, with stderr discarded, silently take the no-pause branch [C]. A
clock and a boundary you can sit exactly on is the only way to see an off-by-one at a threshold.

**THR-02 · `null` is not zero**
Pre: a body whose percent field is JSON `null`. Trigger: `verdict`. Expect: `UNKNOWN(Malformed)`,
exit 6. Assert: the typed result. Catches: V15 of `ground-evaluating-llm-decisions` [C] — the
documented quota command returns `authentication_error` today, a naive `jq` turns that into `null`,
and a reader that coerces `null` to 0 proceeds into a wall. This fixture was produced by accident and
costs nothing.

**THR-03 · A string percent is not a number**
Pre: `percent: "97"`. Trigger: `verdict`. Expect: `UNKNOWN(Malformed)`. Assert: the typed result.
Catches: the shipped gate already gets this right and no test proves it [C] — four references to
`harness-limits.sh` in the old suite, all greps, one of them grepping for the literal string
`all(type=="number")`.

**THR-04 · A 401 is `Unauthenticated`, not generic unknown**
Pre: an auth-error body. Trigger: `verdict`. Expect: `UNKNOWN(Unauthenticated)` and a routing hint to
the notification channel, distinct from the `Unreachable` path. Assert: the type and the route.
Catches: F-18 — 82 minutes of blind operation while nobody re-authenticated, because an auth error
and an unreachable endpoint collapsed into one verdict [C].

**THR-05 · `UNKNOWN` never becomes `OK`, and consecutive unknowns escalate**
Pre: `unknown_escalate_after: 3`. Trigger: five consecutive unknown readings, clock advanced between
each. Expect: no `OK` at any point; a notify at the third; the configured stop semantics applied.
Assert: the verdict sequence and the tick index of the escalation. Catches: F-16 — the old code fails
closed to `UNKNOWN` and then the policy default `proceed` converts it into "carry on", and the run
continued blind for hours across many separate days [C]. **The old suite passed the mutation that
turns `UNKNOWN` into `OK` 51/51** [C].

**THR-06 · The run record distinguishes "quota was fine" from "quota was never read"**
Pre: a run where every reading was unknown. Trigger: `series` at run end. Expect: a record that says
`reads=0 usable`, not a healthy-looking zero. Assert: the field. Catches: F-16(c) — so a post-mortem
can tell the two apart, which the previous run's records could not.

**THR-07 · A reading is labelled with its account, and a mismatch is a hard error**
Pre: a reading for account A; a verdict requested for role `worker` bound to account B. Trigger:
`verdict`. Expect: `MISMATCH`, exit 4 — not a warning. Assert: exit code. Catches: F-17 — *"my limits
position was measuring the wrong account"*, with the building account reading 94% weekly on the wrong
pool [C].

**THR-08 · An account switch starts a new series and emits no crossing event**
Pre: a series for account A near a threshold. Trigger: reassignment to B, whose reading is far below.
Expect: A's series closed, B's opened, **no** threshold-crossing event at the switch. Assert: both
series and the empty event list. Catches: F-19 — the weekly reading fell from 26% to 6% from the
account switch alone, manufacturing a "we have headroom again" signal [C].

**THR-09 · Paused implies `resume_at > pause_at`, for every clock value**
Pre: the pause path. Trigger: `ORCH_NOW` swept over epoch 0, a far-past value, now, a far-future
value, and a DST boundary; with and without a readable reset timestamp. Expect: in every case a
paused run has `resume_at` strictly after `pause_at`, and no resume occurs in the same tick as the
pause. Assert: the property, per clock value. Catches: F-21 (`#65`) — the wall-clock fallback pinned
to a fixed **past** epoch, so an unreadable read resumed a paused run immediately, the exact opposite
of pausing [C].

**THR-10 · Exactly one resume, at the right tick, after a reset**
Pre: paused with `resume_at = now + 3600`. Trigger: the clock advanced to 3599, 3600, 3601, then ten
further ticks. Expect: no resume at 3599; exactly one resume at or after 3600; none of the ten
further ticks resumes again. Assert: the resume count and its tick index. Catches: F-21/F-22's family
— a three-step regression in one time-handling path, none of it caught by a test [C].

**THR-11 · Context thresholds carry the same semantics, per platform and per role**
Pre: `context.soft=70, hard=90` globally, `hard=80` for role `orchestrator`. Trigger: readings across
the boundaries for two roles. Expect: the role override wins for the orchestrator and the global
holds for the worker; SOFT waits for the configured step boundary, HARD acts this tick. Assert: the
verdict matrix plus the step-boundary predicate. Catches: F-37 — nothing measured context at all,
while the percentage was printed on every session's own status line the watch loop was already
capturing [C]. R1-08 also makes *what counts as a step* configurable, and that predicate is here.

**THR-12 · A provider with no limits is a first-class case**
Pre: a provider configured `scheme: none` (pay-as-you-go). Trigger: `verdict`. Expect: `OK` with
`reason: no-scheme` — never `UNKNOWN`, and never a fabricated percentage. Assert: the verdict and the
reason. Catches: requirement-only (R1-06 part 1, and instruction I1's per-platform divergence rule).
Without it, the first non-Claude platform makes the whole quota layer read `UNKNOWN` forever, which
by THR-05 escalates a healthy run to a stop.

---

## 10. RES — the state records needed to resume

R1-06 part 2, in the owner's words: *"в нас в реєстрі має записуватись кожен стан, його виконання …
для того, щоби було відновити процес і продовжити, навіть руками"* — recoverable **by hand** is part
of the requirement, which is why these are plain JSON files a person can read, not a database.

**RES-01 · The resolved config is frozen and hashed at run start**
Pre: a run started. Trigger: edit slot 3 mid-run, then ten ticks. Expect: the run's behaviour is
unchanged; `resolved.json` and its hash are unchanged; the change reaches the run only if it is made
through the control overlay. Assert: hash equality + behaviour. Catches: requirement-only [I], and it
is what makes a resume reproduce the run it is resuming rather than a new one.

**RES-02 · Every state write is atomic**
Pre: each of the nine state paths. Trigger: a concurrent reader loops for the duration of 100 writes,
across the `ORCH_TEST_DELAY_STATE_WRITE` ladder. Expect: every observation is a complete well-formed
document. Assert: zero partial observations, with a **cheap** reader (§11.2). Catches: F-11, and the
general class of a half-written registry entry read as truth.

**RES-03 · Reconcile classifies before it claims**
Pre: a registry with a live registered worker, a dead registered worker, and an unregistered live
process. Trigger: `reconcile` on start. Expect: `mine-alive`, `mine-dead`, `not-mine` respectively,
and **no ticket claimed** until classification completes. Assert: the three classifications and the
ordering (no claim record predates the classification record in the journal). Catches: F-15 — both
failure directions the previous generation could produce, adopt-and-duplicate and tear-down-and-lose
[C].

**RES-04 · A live worker's ticket is not re-claimed**
Pre: as above. Trigger: `reconcile` then a spawn decision. Expect: that ticket is `NOT_READY(claimed-live)`.
Assert: the verdict. Catches: F-15 direction one, and R1-10's "restart the orchestrator, not redo the
work".

**RES-05 · A dead worker's ticket is released exactly once**
Pre: a dead registered worker holding a claim. Trigger: `reconcile`, twice. Expect: one release record
in the journal; the second reconcile is a no-op. Assert: record count == 1. Catches: F-15 direction
two, plus the idempotence property that F-40 and F-42 are made of.

**RES-06 · An unregistered process is left alone**
Pre: a live process in the world that the journal never recorded — the owner's own parallel work.
Trigger: `reconcile`, and a full teardown. Expect: classified `not-mine`; absent from every teardown
target set. Assert: set containment: `acted_on ⊆ started_set`. Catches: F-44, F-45, F-48 — the
`docker compose down -v` on the owner's default stack, the `pkill -f` that matched a lane by its own
prompt text, and ~150 orphaned volumes [C]. R1-16 is explicit that the owner does not want heavy
isolation, only *"дуже простий та надійний варіант"* — a set-containment assertion is that variant.

**RES-07 · Every session has a named close-owner, and ownership falls back**
Pre: a session registered with `close_owner: orchestrator-1`; that owner dead. Trigger: `reconcile`,
clock advanced past the reap threshold. Expect: the session is still reaped, by the fallback owner,
and the close is attributed. Assert: the close record's actor. Catches: F-14 — a finished
question-role session stayed registered and idle for **one day and four hours**, logged
`finished-awaiting-close` for hours by a watcher with no remit to close it [C].

**RES-08 · A reaper never closes a busy session**
Pre: a session past the reap threshold whose world state says busy. Trigger: `reconcile`. Expect: no
close. Assert: the absence. Catches: **P-03**, a positive control — `close-without-force` worked in
the real run, and four sessions that hit `LEAVING SESSION OPEN (never force-close)` were later found
finished on their own [C]. RES-07 is exactly the change most likely to break it, so they are tested
together.

**RES-09 · Crash at every step of the pause path leaves a legal state**
Pre: the pause path's steps enumerated. Trigger: for each step N, run to N, simulate a crash,
restart, inspect. Expect: the recovered state is one of the declared legal states, and **never**
"manual stop" when no human issued one. Assert: legality + the attribution field, per crash point.
Catches: F-22 (`#73`) — the fix for `#65` placed the epoch lookup between the two writes that record
a pause, so a restart landing in that window read `STOP` without its companion marker and exited
instead of resuming [C]. The corpus names this trio the single best acceptance test for the state
layer, and it is cheap: a 30-step path is 30 sub-second tests.

---

## 11. MET — the suite's defences against itself

**MET-01 · The count floor and the conservation identity**
The runner fails if `total < EXPECTED-COUNT` (committed) or if `total != pass + fail + skip`, and
reports `incomplete` rather than `pass` on a signal exit. Catches: F-32 — 346 passed of a declared
382, caught by arithmetic and not by the gate [C] — and the master runner's own missing floor [V].

**MET-02 · The ban-lint over `core/`**
No `date`, `curl`, `claude`, `codex`, `gh`, `tmux`, `docker`, `kill`, `pkill`, `ps`, `pgrep`,
`osascript`, `$SECONDS`, `$RANDOM`, no absolute binary path, and no write redirection whose target
resolves under `control/`. **This is the one place grep-over-source is permitted, because it asserts
absence.** A grep that asserts a behaviour is *present* proves only that a string exists in a file:
the ground research deleted the config-validation feature, left the sentence in a `# TODO`, and the
test named for it stayed green [C].

**MET-03 · Self-wiring**
`orchestrator` is listed in `.claude-plugin/marketplace.json` and in `tests/run-all.sh`'s `PLUGINS`
array. Catches: a plugin absent from that array is invisible to the 475-test suite with no warning
and no count [V].

**MET-04 · No leakage, and idempotence under double invocation**
The suite hashes the repository tree and lists `$TMPDIR` before and after; both must match. It then
runs itself twice and asserts identical results. Catches: `run-all.sh` executes every runner twice
[V], so a leaking stateful suite would fail on the second pass and be blamed on flakiness.

**MET-05 · Installed-copy drift**
Compare `plugins/orchestrator/` against the installed copy under the Claude config root; report every
differing file. Catches: F-49 — a documented ticket-locking fix that landed only in the installed copy
and was still missing from source thirteen days later [C]. It is filesystem-only and free, so it
belongs here rather than in a slower tier.

**MET-06 · The escape hatch is capped**
At most 15% of cases may use `setup.sh` + `assert.sh` instead of the declarative shape, and the
runner fails above that. Catches: the drift back to hand-written bash, which is how the previous
suite became 37 greps [C]. [I], and the number is a judgement call.

### 11.1 Every test carries its mutation, in the file

Each case's `note.md` ends with a `MUTATION:` line naming the exact edit that must turn it red. **A
case with no recorded mutation is presumed vacuous and the runner refuses it.** This is the repo's own
house rule, mechanised instead of remembered — and §12 is the machine that checks it.

### 11.2 Properties checked after every action of every scenario

Not a group, a cross-cutting assertion the runner applies everywhere. No property-based framework is
adopted on day one: `hypothesis` and `pytest` are absent from this machine [C] and a Python venv is a
dependency the plugin does not otherwise need. The properties live in `assert.bash` and run after
every action of every case, which is where most of the value is.

1. `acted_on ⊆ started_set` — R1-16, Д3.
2. `stop_state` is monotone up the lattice, except an explicit legal resume — Д12.
3. `live_sessions ≤ concurrency.max` — R1-05.
4. A ticket with an unmet dependency is never claimed — R1-05.
5. `decide()` on an unchanged world produces an empty plan — §9.1 of the technique research.
6. Nothing under `control/` is ever opened for writing — F-10.
7. Every journal record's actor exists in the registry or is `human`.

And two rules about concurrency tests specifically, both earned by measurement here:

- **A single green round is not a result.** Verified [V]: 60 concurrent appends scored 60/60 at a
  payload size that is demonstrably broken, twice, and the corpus records a categorically broken lock
  passing five rounds of 100 [C]. Every concurrency group runs a delay ladder × 3 rounds, and the
  ladder is what does the work.
- **The probe must be cheaper than the window it is looking for.** Verified [V]: a `jq`-per-read
  observer (~18 ms) saw **zero** torn reads against a truncating writer over 300 writes; a `[ -s ]`
  observer saw 245 at zero injected delay.

---

## 12. The mutation gate

`tests/mutations/<id>.mut`:

```
target:      core/orch-threshold.sh
apply:       s/VERDICT=UNKNOWN/VERDICT=OK/
expect_fail: THR-02, THR-04, THR-05
```

`run-mutations.sh` for each mutation: copy the plugin tree to `mktemp -d` (**never** `git checkout` —
the tree may hold uncommitted work), apply the edit with a `python3` patcher that **asserts the
anchor matched** and aborts if it did not, confirm the mutant still parses with `bash -n`, run
`tests/run.sh --only <the named ids>`, and fail unless every named id went red. It also reports any
*other* id that went red, as information rather than a failure — an over-broad mutation is a design
smell worth seeing.

The asserting patcher matters: FIELD-NOTES records a `sed` whose anchor never matched while the
script reported `SYNTAX OK` [C], which is a mutation experiment that proves nothing and looks like a
pass.

**The mutations, one per assertion group.**

| Id | Edit | Must fail |
|---|---|---|
| M-cfg-order | reverse the band order (committed above personal) | CFG-01, CFG-02 |
| M-cfg-use-merge | deep-merge `use` instead of replacing it whole | CFG-05 |
| M-cfg-never-override | make `never` take the highest slot instead of unioning | CFG-06, CFG-07 |
| M-cfg-key-fatal | make an unknown key fail the whole file | CFG-10 |
| M-cfg-mix-allow | drop the process-kind/steps contradiction check | CFG-12 |
| M-ctl-write | point the status writer at the inbound path | CTL-01, CTL-02 |
| M-ctl-mtime | trigger on mtime instead of content hash | CTL-08, CTL-09 |
| M-ctl-twice | drop the applied-id check | CTL-03, CTL-04 |
| M-ctl-truncate | replace atomic rename with truncate-then-write | CTL-05, RES-02 |
| M-ctl-readdir | apply commands in directory order | CTL-13 |
| M-ctl-relpath | resolve the control path relative to cwd | CTL-12 |
| M-stp-soft-wins | let a later soft downgrade a hard | STP-04 |
| M-stp-custom-parse | pattern-match the custom rule text in core | STP-06 |
| M-stp-undecidable-open | make an undecidable custom stop fail **open** | STP-07 |
| M-stp-attr | accept a stop record with no attribution | STP-08 |
| M-lea-naive | replace `mkdir` with check-then-write | LEA-01 |
| M-lea-name | key liveness on `pgrep -f orchestrator` | LEA-07 |
| M-lea-pid-only | drop `proc_start` from the liveness check | LEA-06 |
| M-lea-stopped | treat a non-responding holder as dead | LEA-05 |
| M-jrn-truncate | truncate an over-long line instead of refusing | JRN-02 |
| M-jrn-intent | emit the record before the action | JRN-03 |
| M-rdy-floor | make the section check return ready always | RDY-01 |
| M-rdy-label | remove one label-clearing call on a transition | RDY-03, RDY-04 |
| M-thr-unknown-ok | turn `UNKNOWN` into `OK` | THR-02, THR-04, THR-05 |
| M-thr-null-zero | coerce `null` to 0 | THR-02 |
| M-thr-resume-past | pin the fallback resume epoch to a fixed past value | THR-09, THR-10 |
| M-res-trust | make reconcile trust the registry without checking liveness | RES-03, RES-04, RES-05 |
| M-res-reap-busy | let the reaper close a busy session | RES-08 |

(Twenty-eight rows; the table is the gate's contents, and it grows with the suite. The rule is one
mutation per assertion group, and a group with no possible mutation is a vacuous group that must be
redesigned or deleted.)

**Four groups had to be redesigned during this write-up because they could not be broken.** Recording
them, because the same instinct will produce more:

- *"The resolver reads six files."* Nothing to break. Replaced by CFG-01's provenance assertion,
  which fails the moment a slot stops contributing.
- *"The control file is watched."* Nothing to break. Replaced by CTL-08/CTL-09, which pin the trigger
  mechanism (hash, not mtime) and the exact tick of application.
- *"State is recorded for resume."* Nothing to break. Replaced by RES-09, which crashes at every step
  and asserts the recovered state is legal.
- *"Only one orchestrator runs."* Breakable, but not by a test that merely starts two — the corpus
  and my own probes both show parallelism alone passing against broken primitives. Replaced by
  LEA-01's delay ladder.

---

## 13. Cost

**Money: $0.00.** Nothing in L1 calls a model, a network endpoint, a terminal or a paid API. MET-02
makes that structural rather than a promise, and LEA-09 runs the suite under `env -i`, which is the
environment an unattended run actually gets.

**Seconds, from measurement on this machine [V]:**

| Unit | Measured |
|---|---|
| one `bash` script that calls `jq` once | **30 ms** (100 invocations in 3.02 s) |
| one bare `jq` | 18 ms |
| `mktemp -d` + `rm -rf` | 6 ms |
| one 60-way concurrent round | ~0.4 s |

**Process spawn dominates, and it is the one design constraint the cost model imposes:** one `jq`
program per case, never a pipeline of `jq` calls per assertion. A case that shells out five times
costs 150 ms; the same case with one `jq -n` program costs 30 ms.

| Group | Cases | Estimated |
|---|---|---|
| CFG | 12 | 0.5 s |
| CTL | 13 | 3.5 s (CTL-05 runs a delay ladder) |
| STP | 9 | 0.4 s |
| LEA | 11 | 6.0 s (LEA-01 is 12 rounds of 60-way) |
| JRN | 6 | 3.0 s (JRN-01 is 6 rounds of 60-way) |
| RDY | 10 | 4.0 s (RDY-10 is 9 concurrent rounds) |
| THR | 12 | 0.5 s |
| RES | 9 | 2.5 s (RES-09 is ~30 crash points) |
| MET | 6 | 2.0 s (MET-04 hashes the tree; MET-05 diffs the installed copy) |
| **Total, 88 cases** | | **≈ 23 s** |

**But `tests/run-all.sh` invokes every runner twice** [V], so L1 costs the repo **≈46 s** — more than
doubling its current 42 s. The fix is four lines: capture the output once and parse the counts from
that capture instead of re-running. It should land in the same PR as the plugin, and it is worth more
than it costs, because the double invocation will get worse with every layer added above this one.

**The mutation gate: ≈ 25 s.** 28 mutations × (tree copy 0.2 s + `--only` run of 2–3 named ids
≈ 0.7 s). Running the *whole* suite per mutation would be 28 × 23 s ≈ 11 min, which is why
`--only <ids>` is part of the runner's contract rather than an optimisation. At 25 s the gate runs on
every commit; at 11 min it runs never [I].

**Authoring cost, honestly.** The seams (§0) are a day if taken up front and a rewrite if not. The
runner and `assert.bash` are a day. The 88 cases are mostly directories: I would budget three days
for the first thirty and a day for the rest, because the first thirty are where the fixture helpers
get written. RDY-10 should be written first, on its own, because it fails against the current source
today and that is the cheapest possible demonstration that the machinery works.

---

## 14. Honest limits — what L1 cannot catch

Every one of these is L1's inheritance to the layer above it. Naming them is the point.

**L1 tests `decide()`. It does not test `apply()`.** A plan that is correct and never executed is
invisible here. Everything about actually spawning, sending, closing, merging and notifying belongs
to L2. This is the single largest gap and it is deliberate: the corpus's own judgement is that the
majority of real failures were in adapters, not orchestration logic [C].

**Nothing about a real terminal or a real agent.** The 1024-byte `MAX_CANON` delivery cliff, the bare
Enter that does not submit in the real Claude Code TUI, `send` overwriting pending text, the
delivery-receipt contract — all measured, all real [C, V in the technique research], and all outside
this layer. Family 1 of the corpus, nine entries, is entirely L2's.

**No proof that the fakes resemble reality.** A `now()` that returns what the test says and a process
probe that returns what the fixture says prove arithmetic, not truth. The ground research found a case
where a naive fake agent's behaviour was the *opposite* of the real CLI's and would have inverted a
test's verdict [C]. A small real-CLI conformance tier is owed, and it is the only place money is
spent.

**No proof that production calls the seams at the right moments.** MET-02 bans `date` from `core/`.
It cannot prove the tick loop asks the clock at the right points, or that a module outside `core/`
does not bypass the seam. That is a property of the loop, which is L2.

**No schema truth.** THR-02/03/04 prove the parser's behaviour on fixtures. They cannot tell you which
fixture is current. There is an unresolved divergence right now [C]: the shipped parser wants
`.limits[].group/.percent`, the owner's own `CLAUDE.md` documents `five_hour.utilization`, and the
live endpoint returned HTTP 401 when the ground research probed it, so neither could be confirmed. A
recorded cassette with a scheduled re-record and a schema diff is the only instrument that catches
this, and it necessarily touches the network.

**No judgement, by design.** R1-09 delegates silence-handling to the orchestrator; R1-14 makes
autonomy a configured policy; R1-13 says verification belongs to the configured process. L1 asserts
what the orchestrator is *told* and asserts nothing about what it decides. The corpus is explicit that
judgement was not the failing part — the **signals** were [C].

**Concurrency is sampled, not proved.** L1 mitigates with delay ladders and rounds because measurement
here showed a broken mechanism scoring 60/60 twice [V]. Mitigation is not proof. A race narrower than
the smallest injected delay is invisible to this layer, and the only stronger instruments — a
deterministic hypervisor, a model checker — are out of scope for a single-operator Mac [C].

**Only one platform has evidence behind it.** Every F-id in this document comes from one vendor's
CLI. R1-07 names Codex, GLM, Gemini and others, and instruction I1 requires per-platform feasibility
checks. THR-12 is the only scenario here written for a second platform's semantics, and it is written
from the requirement, not from a record.

**No evidence at all about a non-code run.** N2 is explicit that the orchestrator may be used where
there are no tests, no repository and no build. RDY, THR, CFG, CTL, STP, LEA and JRN are all
code-agnostic; RES-06's containment property is not, since it assumes a process/container world. The
first non-code run is unguarded and the corpus says so [C].

**Two things L1 deliberately does not defend.** Machine-resource awareness is explicitly deferred by
the owner (R1-05, retracted mid-answer). And the red-line file (R1-15) gets exactly one assertion in
this layer — that the file's path resolves and its content reaches every rendered prompt (RDY-09's
golden) — because the owner ruled out enforcement machinery in the plugin. Whether a model *obeys* it
is a paid eval, three layers up.

---

## 15. Build order

1. **RDY-10 alone.** It fails against the current source today. Ship the failing test, then the lock.
2. **The seams** (§0) and `assert.bash`. Nothing else is affordable until these exist.
3. **CTL-01, CTL-02, CTL-05** — the control-file protocol. Highest leverage in the corpus, cheapest to
   build, and the channel every other requirement depends on.
4. **LEA-01…LEA-07** — the lease. The invariant the owner stated as absolute and the one with no
   implementation to inherit.
5. **THR** in full, then **STP**, then **RES-09**. The corpus names the F-21/22/23 trio the best
   single acceptance test for the state layer.
6. **CFG**, **JRN**, **MET**. Then wire the mutation gate and run it before the first PR.
