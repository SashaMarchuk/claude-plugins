# SPEC-state — run, lane and task state

**Component:** the orchestrator's state layer. **Date:** 2026-09-19.
**Status:** specification. An implementer should be able to build every file, every algorithm and
every exit code in this document without asking a question. Where a question was unavoidable it is in
§14 and the behaviour until it is answered is a marked default.

**Evidence tags used throughout.**
**VERIFIED** — executed on this machine today (2026-09-19), or read at a named line in a named file.
**CLAIMED** — a source document asserts it and I did not re-execute it.
**INFERRED** — my reasoning from the above.

**Defaults.** The owner stated almost none of the values in this document. Every one that he did not
state is marked **DEFAULT-PROPOSED** with a one-line reason. Nothing marked that way is a decision.
Everything he made configurable stays configurable; §11 is the single register and **nothing outside
§11 may invent a default at runtime** (a rule taken from `ARCH-adapters` §17 via `JUDGE-fidelity` G6,
enforced by a test).

---

## 0. Provenance — which design this builds on, and where the judges disagreed

**Two of three judges name `ARCH-minimal` the winner** (`JUDGE-cost` 9/10 rank 1, `JUDGE-fidelity`
8/10 rank 1). The third, `JUDGE-survival`, ranks it **last** (5/10) and names `ARCH-operability`
first. This spec follows the majority: **`ARCH-minimal` is the base** — one bash supervisor owning all
state, a model invoked only for judgement, no long-lived orchestrator session — and the grafts the
judges named are folded in.

Grafted into this spec, with the source judge:

| Graft | From | Judge | Where it lands here |
|---|---|---|---|
| Claim ordering as a testable invariant | `ARCH-minimal` §4 | survival G13 | §6 |
| `ops.json` as data, two columns plus evidence | `ARCH-reliability` §3.6 | cost G9 + survival G1 | §7.4 |
| Evidence-gated `ok` on mutating ops | `ARCH-reliability` I4 | survival G1 | §4.4 rule R4 |
| `unsafe` idempotency class → escalate, never replay | `ARCH-reliability` §5.4 | survival G10 | §7.5 |
| The sleep fence (`mono` + wake grace) | `ARCH-reliability` §11.2 | survival G3 | §5.8 |
| Doctor steps 2 and 3 (alive-but-not-ticking) | `ARCH-minimal` §10.3 | survival G2 | §5.6 |
| Trip watermark, `O_EXCL` before the action | `ARCH-operability` §2.2 | fidelity G3 | §4.4 rule R6 |
| `control.ack.json` + exit 8 | `ARCH-operability` §3.3 | cost G4, fidelity G9 | §4.8, §9 |
| Dedup key written **into** the side effect | `ARCH-adapters` §3.3 | cost G5 | §4.3, §5.7 |
| `HARVEST` as a third answer | `ARCH-operability` §5 (Sortie ADR 0020) | cost G8 | §3.3 |
| Board write-back restored, readback-only evidence | `ARCH-reliability` §4.3 | fidelity G7 | §3.4 |
| Never log the trigger phrases | `ARCH-adapters` §10.2 | survival G11 | §4.7 |
| Defaults register with `scope` and `apply` columns | `ARCH-adapters` §17 | fidelity G6 | §11 |

**The one place the judges contradict each other and I chose.** `JUDGE-cost` §7 says explicitly *do
not* take reliability's evidence-gated appender ("the bulk of that design's ~3,500–4,500 lines").
`JUDGE-survival` G1 says it is the highest-value graft in the set. **I followed survival, in a
narrowed form**: the gate is one lookup and one refusal inside the single function that appends a
`result` record (§4.4 R4), driven by a ~20-line data file, not a subsystem. What I did **not** take is
reliability's four-phase reconciler, its separate appender process, and its per-invariant mutation
suite. Cost's objection was priced against the whole subsystem; the refusal alone is about fifteen
lines and closes FIELD-NOTES §4.1 — a merge that printed `Already up to date`, exited 0, moved nothing,
and produced a perfectly well-formed success record (VERIFIED, `FIELD-NOTES.md:229`).

**The second disagreement.** Cost keeps minimal's single 60-second cadence; survival wants the stop
latency reliability buys with a 2-second control tick. I take a middle that costs six lines: **one
loop, two cadences** — a full tick every `tick.interval_seconds`, and a cheap control sub-tick every
`tick.control_seconds` that does nothing but `stat` one file (§3.2, §11). Д12 [520] only promises
«на наступному тіку», so this over-delivers rather than deviating.

**Sources read for this spec, in the order they bind:** `round-1/ANALYSIS-01.md` and
`round-1/TRANSCRIPT-01.md` (the owner's own words win over the analysis where they differ) ·
`research/extract/corrections.md` (what he never ratified) · `research/platforms/ADAPTER-CONTRACT.md` ·
`research/LANDSCAPE.md` · `research/adoption/ADOPTION-VERDICT.md` · `plugins/harness/docs/FIELD-NOTES.md` ·
`ARCH-*.md` and `JUDGE-*.md` · `<baseline-marketplace>/docs/config-levels.md` · `~/.claude/gsd-core/`.

---

## 1. Identifiers, clocks and the words this document uses

### 1.1 Identifiers

| Name | Form | Example | Rule |
|---|---|---|---|
| `project_root` | absolute path | `/Users/…/<work-project>` | `dirname` of `git rev-parse --git-common-dir`, resolved with `cd … && pwd -P`. **VERIFIED on git 2.33.0 today**: from inside a worktree this returns the *main* repo's `.git`, so every component resolves to the same project from any lane worktree. |
| `project_key` | 40 hex | `a3f1…` | `printf '%s' "$project_root" \| shasum -a 1 \| cut -c1-40`. Used only to name the lock file. |
| `run_id` | `<slug>-<YYYYMMDD-HHMMSS>Z-<4hex>` | `<work-project>-20260919-224100Z-a7f3` | The 4 hex digits close the same-second collision (`ARCH-reliability` §3.1). Slug is `project_root`'s basename, `[a-z0-9-]`. |
| `lane_id` | `L<NN>-<ticket-slug>` | `L03-t-118` | `NN` is dispatch order, zero-padded, **never reused within a run** — a reused lane slug is a recorded failure (FIELD-NOTES §11.8: a slug reused from an earlier wave spawned a worker into a stale worktree, CLAIMED via `ARCH-reliability` §3.1). The ticket slug makes paths readable. |
| `ticket_id` | opaque, from the source | `gh#412`, `t-118` | Never parsed for meaning. Slugified only when it appears in a path. |
| `session_id` | opaque, from the platform | `0b6c…` | May be client-named (written before launch) or server-minted (observed after). §3.5. |
| `epoch` | positive integer | `4` | The fencing token. §5.3. |
| `seq` | positive integer | `1042` | Strictly increasing per run, one writer only. §4.2. |
| `action_id` | `<run_id>:<epoch>:<lane_id\|run>:<op>:<attempt>` | `sf-…-a7f3:4:L03-t-118:git.merge:1` | The dedup key. Written into the journal **and into the side effect itself** (§4.3). |
| `idem` | `sha256:<64hex>` | `sha256:9f2c…` | Digest over `(op, subject, normalised args)` — deliberately **without** `attempt`, so a replayer can ask "did this exact operation already happen?" rather than "did attempt 2 happen?". |
| `res_id` | `r<NN>` per run | `r14` | Resource ledger key. |

### 1.2 Clocks — and why there are three

Every journal record carries all three. This is not redundancy; each answers a different question and
two of them lie in a case the previous run actually hit.

- **`ts`** — RFC3339 UTC with milliseconds, e.g. `2026-09-19T23:41:07.412Z`. **For display only.**
  Never subtract two of these to get a duration.
- **`mono`** — `CLOCK_MONOTONIC` seconds, 3 decimal places. **Every duration in the system is computed
  on `mono`.** VERIFIED today: `python3` 3.9.6 on this machine exposes `time.monotonic()` and
  `time.CLOCK_MONOTONIC`. On Darwin, monotonic time does not advance while the machine sleeps and wall
  clock does; the difference is how a wake is detected (§5.8).
- **`boot`** — the machine's boot time in epoch seconds, as a decimal string. VERIFIED today:
  `sysctl -n kern.boottime` prints `{ sec = 1788417532, usec = 907116 } Thu Sep  3 13:38:52 2026`;
  parse the `sec =` field. A record whose `boot` differs from the current boot was written before a
  reboot, and **no `mono` value may be compared across a `boot` change.**

Reading them together is what makes FIELD-NOTES §10.1 unreachable. That line —
`watch: orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may sleep)` (VERIFIED,
`FIELD-NOTES.md:419`) — is a wall-clock staleness reading taken across a sleep, and it is how the
previous run ended.

### 1.3 Machine-primitive facts this spec relies on, all VERIFIED today on this machine

| Fact | Consequence |
|---|---|
| `command -v flock` → nothing. `flock(1)` is **not installed**. | The lease holder is 20 lines of Python (§5.1), not a shell call. |
| `/usr/bin/shlock` exists but is PID-based. | Not used. PIDs are recycled. |
| `python3` 3.9.6, `jq` 1.8.1, `git` 2.33.0, `shasum`, `uuidgen` all present. | The whole state layer is bash + jq + one Python file. |
| `ps -o etimes=` → **`ps: etimes: keyword not found`**. | Process start time is read with `ps -o lstart= -p <pid>`, which prints `Sat Sep 19 21:04:55 2026` — **one-second resolution**. §5.2 says what that costs and how argv closes it. |
| `stat -f '%m %z' <path>` works (BSD `stat`). | Change detection is `(mtime, size)` then `sha256`. GNU `stat -c` is **not** available; an implementer must not write it. |
| The 20-line `flock` holder was executed here: two concurrent attempts → the second prints `LOCK HELD: 15675 1789826700 sleep 3` and exits **69**; after the holder exits the next attempt acquires **immediately**; after `kill -9` of the holder the next attempt acquires immediately. | **No TTL, no stale-lock timeout, no heartbeat is needed for correctness.** §5.5. |
| `set -o noclobber; : > file` succeeds once and then exits **1**. | The trip watermark (§4.4 R6) is one line of bash, with no race. |

---

## 2. Where everything lives

**Rule 0: no run state lives inside the repository.** Д4 [433] makes every task its own git worktree,
so anything the run keeps in the work tree forks per lane and the copies diverge. This is not
theoretical — FIELD-NOTES §12.5 records `QUESTIONS.md` and `JOURNAL.md` forking into a worktree's own
copy with a real owner-facing question invisible for an hour (CLAIMED via `ARCH-minimal` §2.1).

### 2.1 Machine root — `${ORCHESTRATOR_STATE_DIR:-$HOME/.orchestrator}/`

```
locks/<project_key>.lock          flock target. Keyed on the PROJECT, not the run (§5.1)
machine.lock                      flock target. Serialises the doctor against itself only
runs/index.tsv                    one line per run, append-then-rewrite under machine.lock
doctor/state.json                 the doctor's own memory between visits (§5.6)
```

`runs/index.tsv`, tab-separated, no header, one line per run:

```
run_id	project_root	run_dir	created_at	state	pid	epoch
```

`state` here is a **cache** of the run's folded state, rewritten on every run transition. It is never
authoritative; `journal.ndjson` is. Its only job is to let the doctor and `orchestrator:status` find
runs without walking `$HOME`.

### 2.2 Run root — `$HOME/.orchestrator/runs/<run_id>/`

```
run.json                      immutable run input: mode, scope, --set overrides, created_at, argv
config.resolved.json          slots 1–6 resolved at t0, with per-key provenance
config.sources.json           the six source paths + (mtime,size,sha256) at last read
config.run.json               run-scope overrides (§2.4)
plan.json                     immutable: per lane, which owner item was weakened or denied (fidelity G5)
ops.json                      the operation catalogue (§7.4). Shipped with the plugin, copied in at t0
triggers.json                 the literals the journal must never contain (§4.7)

lease/
  epoch                       the fencing token. One integer, one line, no newline ambiguity
  owner.json                  holder identity (§5.2)
  heartbeat                   advisory only: {wall, mono, boot, epoch, seq}
journal.ndjson                THE record. Append-only. Single writer. Never rewritten (§4)
blobs/<sha256>                payloads too large for one journal record
resources.ndjson              append-only resource ledger, multi-writer (§6.4)
control.json                  THE watched control file (Д12, Д7, R1-07)
control.lock                  flock target for writers of control.json
control.applied.ndjson        every entry after it was applied, stamped
control.ack.json              projection: the supervisor's reply to whoever wrote control.json
status.json                   projection: what orchestrator:status prints. Zero model tokens
trips/<trip_key>.json         watermark files, created O_EXCL before an action fires (§4.4 R6)
capacity/<account>.json       cached capacity reading + read_at + provenance
answers.ndjson                every answer the orchestrator gave a session (R1-11)
report.md                     written once, at finish

lanes/<lane_id>/              the directory IS the claim (§6)
  epoch                       the epoch this lane is currently fenced to
  start.json                  written BEFORE launch. The single most important file in the system
  sessions.ndjson             session lineage (§3.5)
  steps.ndjson                the lane wrapper's own intent/result pairs
  events.ndjson               the platform's raw structured stream, tee'd
  events.norm.ndjson          normalised to the fixed vocabulary
  engine.ndjson               one line per engine probe (§8)
  stdout.log  stderr.log
  result.json                 written LAST. Its existence is the lane's commit point
lanes.done/<lane_id>/         a lane directory moved here after result.json
```

### 2.3 Project root — `<project_root>/.orchestrator/`

Three human-facing files only, and the orchestrator reads them **from the main checkout**, never from
a worktree copy:

```
RULES.md                      R1-15 red lines. Committed
tickets/*.md                  local registry, only when tickets.source = local
.gitignore                    created by orchestrator:init
```

The Д6 questions channel is **not** here: [449] explicitly allows it to be a GitHub issue or a tracker
task, so its location is config (`questions.channel`) and this spec never assumes a path for it.

### 2.4 The run scope, and why it is not a seventh config slot

Д1 [416] defers configuration wholesale to the owner's own marketplace, and
`<baseline-marketplace>/docs/config-levels.md` §2 states the six slots (VERIFIED: slots 1–6, with
`<config-root>` resolved from `CLAUDE_CONFIG_DIR` or `$HOME/.claude`, and per-plugin files at
`<config-root>/shared/plugins/<plugin>.json`). `requirements/OWNER-DECISIONS.md` 3.6 states that
three levels are the whole set. He also requires a *this run* scope [331]/[075].

**Reconciliation, which changes nothing in the marketplace:** the run scope is not configuration. It
is per-invocation state — `--set key=value` captured into `config.run.json`, layered by the
orchestrator on top of the resolver's output, never written into any config file, and gone when the
run ends. `config.resolved.json` records per key which slot supplied it and whether the run scope
overrode it. Recorded as a tension in §12.

---

## 3. The state machines

Four machines: **run**, **lane**, **task**, **session**. A fifth ledger — the resource — is two states
and lives in §6.4.

### 3.1 Rules that hold for all four

1. **A state is never stored as the truth.** It is computed by folding `journal.ndjson` (§7.2). The
   `state` columns in `index.tsv` and `status.json` are caches, rewritten from the fold.
2. **Every transition is one `transition` record**, carrying `machine`, `subject`, `from`, `to` and
   `cause`. `cause` is drawn from the **closed vocabulary in §3.6**.
3. **The transition table is data, not prose.** `transitions.json` ships with the plugin and lists
   every legal `(machine, from, to, cause)` tuple. The appender refuses a transition that is not in
   it (§4.4 R5). This is what makes the diagrams below executable rather than documentary, and it is
   the cheapest possible defence against the class of bug where a state is entered by an accident of
   control flow.
4. **Terminal means terminal.** A record attempting to leave a terminal state is refused. `finished`
   must mean something: FIELD-NOTES §10.1 records the previous run holding `DEAD-RUN` and `STOPPED`
   at the same timestamp with no way to tell an accidental teardown from a finish, then flagging
   `STOPPED present with no run.complete — treating as an accidental teardown, not a finish` every
   three minutes **for about five days, 1,085 times** (VERIFIED, `FIELD-NOTES.md:551-552`). Three
   distinct terminal states with three distinct exit codes is the fix.
5. **Silence is never success.** No machine has a transition into a success state whose only cause is
   the absence of a signal.

### 3.2 The run

```
                       ┌──────────────── control.stop_now ────────────────┐
                       │                                                   ▼
  starting ─► preflight ─► running ─┬─► draining ───────────────► finishing ─► finished
      │           │                 │      ▲                         │  │
      │           │                 │      └── queue.drained ────────┘  └─► degraded
      │           │                 ├─► paused ──(wake condition)──► running
      │           │                 └────────────────────────────► stopping ─► finishing
      │           └── preflight.refused ─► refused
      └── lease.contended ─────────────────► refused
                          internal.error (anywhere) ─────────────────────► aborted
                          queue.only_blocked & when_only_blocked=finish ─► blocked
```

| State | Entered when (cause) | The tick does | Leaves when (cause) | Terminal |
|---|---|---|---|---|
| `starting` | `run.started` — the lease was acquired, the run dir created, `epoch` bumped | writes `run.json`, `config.resolved.json`, registers in `index.tsv` | always → `preflight` (`preflight.entered`) | no |
| `preflight` | `preflight.entered` | runs the gate list; zero model tokens; every gate emits an `observation` | all gates pass → `running` (`preflight.passed`); any gate refuses → `refused` (`preflight.refused`) | no |
| `refused` | `preflight.refused`, or `lease.contended` (the lock was held) | nothing. **No resource was created.** The run dir holds a refusal record and nothing else | — | **yes** |
| `running` | `preflight.passed`, or a pause's wake condition | the full tick (steps 1–9 below) | see the six rows below | no |
| `paused` | `control.pause`, `capacity.hard_threshold`, `capacity.exhausted`, or `wake.detected` (for `sleep.grace_seconds` only) | reap + observe. **Dispatches nothing.** Re-checks the wake condition every tick | `control.resume`, `capacity.reset_reached`, or the grace expiring → `running` | no |
| `draining` | `control.stop_boundary`, `capacity.soft_threshold`, or `queue.drained` | reap + observe; dispatch nothing; running lanes run to completion | `lanes.all_ended` → `finishing` | no |
| `stopping` | `control.stop_now` | sends `SIGTERM` to every lane wrapper; each wrapper tears down what the ledger lists for it | `lanes.all_ended` → `finishing` (a hard stop still tears down properly) | no |
| `finishing` | `lanes.all_ended` | walks `resources.ndjson` in reverse, stops and **asserts** each; writes `report.md`; deregisters | `teardown.complete` → `finished`; `teardown.unresolved` → `degraded` | no |
| `finished` | `teardown.complete` | — | — | **yes** |
| `degraded` | `teardown.unresolved` — at least one resource could not be proven gone | — | — | **yes** |
| `blocked` | `queue.only_blocked` while `when_only_blocked: finish` | — | — | **yes** |
| `aborted` | `internal.error` — a bug, a refused illegal transition, an unreadable run file | teardown is attempted once, best effort, and its outcome is recorded | — | **yes** |

**`paused` carries a `pause_reason`, not a substate.** Reasons: `control | capacity | wake | human`.
Each has exactly one wake condition, listed above. `ARCH-reliability` splits these into four named
states; `ARCH-minimal` uses one. I follow minimal: four states whose only difference is a field
multiply the transition table by four and buy nothing a `jq` filter does not.

**Why there is no `paused:human` but there is a terminal `blocked`.** Д6 [449] is unambiguous that
independent work continues while something waits on a person, so a lane waiting on a person never
pauses the run. The run only reaches a *human* state when **nothing else is left**, and then Д7 [455]
governs: `when_only_blocked: wait` (his own recommendation, the default) keeps the run in `running`
with an empty dispatch and one notification on entry; `finish` takes the terminal `blocked` state and
exit code 5.

**The tick, in order.** Cheap and deterministic first; the model last and only if something is open.

1. **control sub-tick** (also runs every `tick.control_seconds` between full ticks): `stat`
   `control.json`; if `(mtime,size)` changed, hash it, parse it, apply `apply: now` entries, queue
   `apply: boundary` ones, rewrite `control.ack.json`.
2. **config**: `stat` the six slot files plus `config.run.json` (seven `stat` calls, no resolver run);
   on change, re-resolve and diff; apply keys whose `apply` class allows it (§11), report the rest
   into `control.ack.json.rejected[]`.
3. **reap**: for each lane dir — `result.json` present? pid alive? `ps -o lstart=` matches? Emit
   transitions.
4. **observe** (zero tokens): per live lane, event-file size and mtime, the tail of
   `events.norm.ndjson`, `context.pct` from the last event that carries one, and the engine probe (§8).
5. **rules**: everything with a configured answer, applied with no model — a crossed threshold, three
   identical failures, a delivered answer, a finished lane to release.
6. **judge**: if and only if something is still open, render **one** fact sheet with **all** open items
   and make **one** model call. Otherwise skip entirely, at zero token cost.
7. **dispatch**: while `live_lanes < max_lanes` and capacity allows and a ready ticket exists — claim,
   launch.
8. **write**: append transitions and observations; rewrite `status.json` and `control.ack.json`.
9. **terminal check**: evaluate the drain condition (§3.2 below).

**The drain condition**, evaluated at step 9 in `running` and `draining`:

```
drained = (no lane in a non-terminal state)
      AND (no claimable ready ticket, after a fresh source read)
      AND (intake == frozen OR intake_quiet_for_s >= end.intake_grace_seconds)
      AND (no task in `blocked`, OR when_only_blocked != wait)
```

`end.intake_grace_seconds` exists because Д2 allows work to be added mid-run: without it a run that
drains at 03:00 exits thirty seconds before the owner's 02:59 ticket is picked up.

### 3.3 The lane

A lane is **one attempt at one task on one platform lane**. One task may have several lanes over a run
(a retry, a reseed, an answer arriving); a lane never changes its task.

```
  claimed ─► preparing ─► launching ─► working ─┬─► harvesting ─┬─► done
     │            │           │           │     │               ├─► needs_review
     │            │           │           │     │               └─► failed
     │            │           │           │     ├─► blocked_on_human      (terminal)
     │            │           │           │     ├─► reseeding ─► launching
     │            │           │           │     └─► stopped              (terminal)
     │            │           │           └─► failed
     │            │           └─► failed
     │            └─► failed
     └─► released                                (claim withdrawn before anything launched)

  orphaned ─► reconciling ─┬─► done | failed | released | escalated
```

| State | The marker on disk that proves it | Leaves when (cause) | Terminal |
|---|---|---|---|
| `claimed` | `lanes/<id>/` exists, **no `start.json`** | `start.written` → `preparing`; abandoned → `released` (`claim.withdrawn`) | no |
| `preparing` | `start.json` exists, `start.json.pid` is `null` | worktree, env and services verified → `launching` (`prepare.ok`); any step fails → `failed` (`prepare.failed`) | no |
| `launching` | `start.json.pid` written, no event yet observed | first normalised event, or a named session id → `working` (`launch.ok`); the process exits before either → `failed` (`launch.failed`) | no |
| `working` | pid alive **and** `ps -o lstart= -p <pid>` equals `start.json.pid_lstart` | see the six causes below | no |
| `harvesting` | the process has exited and `result.json` is not yet written | the engine is asked once more (§3.3 below) | no |
| `blocked_on_human` | last normalised event is `waiting_on_human`, **or** the wrapper exited 5 | — the attempt is over; the *task* stays parked (§3.4) | **yes** |
| `reseeding` | a new line in `sessions.ndjson`, predecessor recorded `stopped_for: "reseed"` | successor launched → `launching` (`reseed.launched`) | no |
| `done` | `result.json` with `outcome: "ok"`; dir moved to `lanes.done/` | — | **yes** |
| `needs_review` | `result.json` with `outcome: "indeterminate"` | — | **yes** |
| `failed` | `result.json` with `outcome: "failed"` and a named `reason` | — | **yes** |
| `stopped` | `result.json` with `stopped_by: "control"` | — | **yes** |
| `released` | the lane dir was removed before `start.json` existed | — | **yes** |
| `orphaned` | `start.json` exists, `result.json` does not, and the pid is gone or its start time does not match | `reconcile.started` → `reconciling` | no |
| `reconciling` | a `reconcile` intent is open | §7.5 decides | no |
| `escalated` | the reconciler could not decide and the op class is `unsafe` | — a person is asked, and a new lane may follow | **yes** |

**Outcome is never decided by the exit code alone.** `ADAPTER-CONTRACT` §2.4 invariant 1 records four
platforms that exit **0 on failure** — Aider on auth failure and on rate limit, pi `--mode json` on a
provider failure, GLM on quota exhaustion *with* `subtype: "success"`, and MiMoCode always (CLAIMED,
from that document's own spikes). So the wrapper computes:

```
outcome = f(exit_code, terminal_event_in_events.norm.ndjson, harvest_verdict)
```

If `exit_code` and `terminal_event` disagree, `outcome = "unknown"`, the lane goes to `failed` with
`reason: "contradictory"`, and the fact is on the judge's next fact sheet.

**`harvesting` is the third answer, and it is asymmetric on purpose.** `ARCH-operability` §5, via
Sortie ADR 0020 (`LANDSCAPE` §4, VERIFIED quotation): the handoff transition *"asserts something about
a run's output, and the test applied to it described only the run's exit."* A lane that exits 0, emits
`turn_completed` and produced nothing takes the done path under any exit-based rule. So after the
process exits, the engine is asked once more (§8) and answers **done · not done · undeterminable**:

- `harvest_evidence: observed` (DEFAULT-PROPOSED) — withhold `done` only on **positively observed**
  emptiness. Absence of evidence is not evidence of absence, which is why this is three values and not
  a boolean.
- An **undeterminable** harvest sets `needs_review`, never `done`. Advancing an empty ticket moves work
  in a system the orchestrator does not own and puts it in front of a person; withholding leaves it in
  a queue the orchestrator keeps watching, with the withholding recorded.

**`blocked_on_human` is terminal for the attempt and not for the task**, and this is a deliberate
synthesis of two opposite positions the field argued explicitly (`LANDSCAPE` §4, both VERIFIED):
Sortie ADR 0025 makes a human-input request a dedicated non-retryable terminal, because *"an
unattended run contains no one who can grant permission"*; claudexor parks it as a durable pending
interaction with four terminals (`answered | timeout | run_terminal | interrupted`) and four delivery
statuses (`delivered | not_found | already_resolved | rejected`). The owner's Д6 [449] says which side
he is on for the **queue** — independent work continues — and says nothing about the attempt.
Resolution: **the attempt ends (Sortie), the question is a durable record (claudexor), and a delivered
answer starts a new lane for the same task.** One rule imported from Sortie without modification: a
`blocked_on_human` lane charges **nothing** against Д5's three-failure budget [442], because a budget
that drains into a state no retry can change is a budget that ends a night for no reason.

### 3.4 The task

The task machine is the owner's, not this document's. R1-04 [145–153] says the structure is to be
designed and the status names are user-overridable and adapt to the chosen process. So the
orchestrator holds only the **shape**, and `board.states` maps each internal name onto the source's own
name.

```
  unknown ─► ready ─┬─► claimed ─► in_progress ─┬─► needs_review ─► done
     ▲              │      │           │        ├─► blocked ──────────┘
     └── released ──┴──────┴───────────┘        └─► failed ─► ready   (while budget remains)
```

| State | Entered when | Leaves when |
|---|---|---|
| `unknown` | first seen in the source | readiness evaluated |
| `ready` | readiness rule satisfied (below) | `task.claimed` → `claimed`; readiness lost → `unknown` |
| `claimed` | `mkdir lanes/<lane_id>` succeeded | `start.written` → `in_progress`; `claim.withdrawn` → `ready` |
| `in_progress` | a lane for it reached `launching` | its lane reaches a terminal state |
| `needs_review` | lane `needs_review`, or an indeterminate engine verdict | a person, or a new lane |
| `blocked` | lane `blocked_on_human` | `question.answered` → `ready` (a new lane follows); `question.timeout` → `needs_review` |
| `failed` | lane `failed` | under the budget → `ready` (retry); budget exhausted → stays `failed` and is parked |
| `done` | lane `done`, **and** the board readback confirmed it if the board is writable | terminal |

**Readiness** is the structure he asked someone to design [145]/[146], at grep size:

> A task is ready iff **(a)** its state is the configured ready state — frontmatter `status: ready`
> locally, or the configured label/status on a board — **and (b)** its body, with frontmatter
> stripped, contains every heading in `tickets.ready_requires` — **and (c)** every id in its
> `depends_on:` list is `done`.

**Board write-back is on, and readback is its only admissible evidence.** [149] is ratified («Так, …»
at [149] per `corrections.md`'s ratified list): the board is «помічник для цього оркестратора, щоби
ставити статуси таскам, залишати якісь коментарі». `ARCH-minimal` gives write-back up to avoid the
self-write loop (C3-A1); `JUDGE-fidelity` G7 is right that minimal already ships the fix for that loop
in its own §2.4 and therefore pays for the decision twice. So:

1. Every board write is an op in `ops.json` with `admissible: ["board_readback"]`. A 200 is **not**
   evidence the transition applied (`ADAPTER-CONTRACT` §2.4 invariant 2, CLAIMED). The item is
   re-fetched and the field compared.
2. The post-write readback digest is recorded in the journal as
   `self_write_digest`, and the change detector **ignores a change whose digest it produced**. This is
   the same content-based self-write suppression as §4.8, and it is the one-line fix for the topology
   that produced the 85-minute loop.
3. A board comment carries `action_id` in a trailer (§4.3), so a duplicate after a crash is
   *detectable by reading the board* rather than by trusting the journal.
4. **The orchestrator still never writes into a work item's own body** on the local registry. Status
   lives in the run dir; the ticket file is read-only. C3-A2 measured 327 tracked ticket files with
   every status write dirtying one, and FIELD-NOTES §4.1 records that one dirty tracked file is
   exactly what made a merge print success and move nothing (VERIFIED, `FIELD-NOTES.md:229`).

### 3.5 The session

A session is one platform conversation. **One task maps to a list of sessions, never to one field** —
close-and-reseed is the only context remedy that works on every platform, and Droid mints a *new*
session id after a compaction (`ADAPTER-CONTRACT` §6.3, CLAIMED).

```
  planned ─┬─► named ─────► live ─┬─► ended
           │                      ├─► lost
           └─► unnamed_window ────┘   └─► superseded ─► (successor: planned)
```

| State | Meaning | Entered when | Leaves when |
|---|---|---|---|
| `planned` | the lane intends to launch a session | `start.json` written | an id exists, or the window opens |
| `named` | **the client named the id before launch**, and it is in `start.json` | `session.named` | first event → `live` |
| `unnamed_window` | the **server** mints the id; there is a window between launch and the first record in which a crash leaves a session that exists and cannot be named | `session.window_opened` | id observed in the stream → `live` via `session.observed`; window expires with no id → `lost` |
| `live` | at least one event observed | `session.first_turn` | process exit → `ended`; identity lost → `lost`; reseed/compaction-with-new-id → `superseded` |
| `ended` | the platform ended it | `session.ended` | terminal |
| `lost` | it exists or existed and cannot be named | `session.lost` | terminal. Recorded in `resources.ndjson` as `unowned_session`, **listed and never auto-killed** |
| `superseded` | a successor carries the work | `session.superseded` | terminal for this id; the lineage continues |

Identity ladder, VERIFIED in `ADAPTER-CONTRACT` §3 B: **client names the id before launch** (Claude
Code, pi, Droid, OpenCode, Qwen) → **server mints and the adapter records it atomically** (Codex, Kimi,
Amp, MiMoCode) → **no id at all** (Aider). And one platform is worse than the ladder suggests: on
Gemini CLI a session with **no completed model turn is deleted and is unresumable**, so an early
failure there leaves no recovery point at all.

`orphan.dispatch_window_seconds` (DEFAULT-PROPOSED 45) is the length of `unnamed_window`. Inside it,
recovery is **re-dispatch into a fresh workspace**, never resume — there is nothing to resume by name.

`sessions.ndjson`, one line per session:

```json
{"session_id":"0b6c…","lane":"L03-t-118","platform":"claude","account":"<profile-B>",
 "id_source":"client","state":"live","opened_at":"…","opened_mono":918233.114,
 "predecessor":null,"reason_for_new":null,"transcript_path":"…","transcript_durable":true}
```

`transcript_durable: false` (Amp, DeepSeek `dsh` — the transcript exists only on the pipe) obliges the
adapter to tee it to disk under the lane directory and declare that in `caps.sh`. Otherwise a dead
supervisor destroys the evidence, which collides head-on with R1-10's own requirement that the
orchestrator's death be survivable.

### 3.6 The cause vocabulary — closed, and checked

`cause` on a `transition` record must be one of these. Anything else is refused (§4.4 R5).

**run:** `run.started` · `preflight.entered` · `preflight.passed` · `preflight.refused` ·
`lease.contended` · `lease.acquired` · `lease.taken_over` · `control.stop_now` ·
`control.stop_boundary` · `control.pause` · `control.resume` · `capacity.soft_threshold` ·
`capacity.hard_threshold` · `capacity.exhausted` · `capacity.reset_reached` · `queue.drained` ·
`queue.only_blocked` · `answer.received` · `lanes.all_ended` · `teardown.complete` ·
`teardown.unresolved` · `wake.detected` · `wake.grace_expired` · `internal.error`

**lane:** `lane.claimed` · `claim.withdrawn` · `claim.lost` · `start.written` · `prepare.ok` ·
`prepare.failed` · `launch.ok` · `launch.failed` · `event.waiting_on_human` · `answer.received` ·
`context.threshold` · `compact.proven` · `compact.unproven` · `reseed.launched` · `exit.observed` ·
`harvest.done` · `harvest.empty` · `harvest.indeterminate` · `outcome.contradictory` ·
`timeout.wall` · `control.stop_now` · `control.stop_boundary` · `signal.term` · `pid.gone` ·
`lane.adopted` · `orphan.detected` · `reconcile.started` · `reconcile.resolved` ·
`reconcile.escalated` · `result.written` · `dir.moved`

**task:** `task.discovered` · `ready.satisfied` · `ready.unsatisfied` · `task.claimed` ·
`task.released` · `lane.succeeded` · `lane.failed` · `lane.indeterminate` · `question.raised` ·
`question.answered` · `question.timeout` · `deps.unmet` · `budget.exhausted` · `board.readback_ok` ·
`board.readback_failed`

**session:** `session.named` · `session.window_opened` · `session.observed` · `session.first_turn` ·
`session.ended` · `session.lost` · `session.superseded`

### 3.7 `transitions.json` — the legality table as data

```json
{"run":  [["starting","preflight","preflight.entered"],
          ["preflight","running","preflight.passed"],
          ["preflight","refused","preflight.refused"],
          ["starting","refused","lease.contended"],
          ["running","draining","control.stop_boundary"],
          ["running","draining","capacity.soft_threshold"],
          ["running","draining","queue.drained"],
          ["running","paused","control.pause"],
          ["running","paused","capacity.hard_threshold"],
          ["running","paused","capacity.exhausted"],
          ["running","paused","wake.detected"],
          ["paused","running","control.resume"],
          ["paused","running","capacity.reset_reached"],
          ["paused","running","wake.grace_expired"],
          ["running","stopping","control.stop_now"],
          ["draining","stopping","control.stop_now"],
          ["paused","stopping","control.stop_now"],
          ["draining","finishing","lanes.all_ended"],
          ["stopping","finishing","lanes.all_ended"],
          ["finishing","finished","teardown.complete"],
          ["finishing","degraded","teardown.unresolved"],
          ["running","blocked","queue.only_blocked"],
          ["draining","blocked","queue.only_blocked"],
          ["running","running","lease.taken_over"],
          ["draining","draining","lease.taken_over"],
          ["paused","paused","lease.taken_over"],
          ["*","aborted","internal.error"]],
 "lane": [ … ["working","working","lane.adopted"] … ], "task": [ … ], "session": [ … ]}
```

**Three rules about this file.**

`"*"` is the only wildcard and it is allowed only on the `internal.error` row, because a bug can happen
in any state and refusing to record it would be the wrong failure.

**Self-loops are legal and are declared like any other row.** `running → running` on
`lease.taken_over` and `working → working` on `lane.adopted` are not no-ops: they are the records that
say *this machine is now fenced to a new epoch*, and they must be in the table or §4.4 R5 refuses the
one record a takeover most needs to write.

Terminal states are declared in the same file as
`{"run":{"terminal":["finished","degraded","blocked","refused","aborted"]},
  "lane":{"terminal":["done","needs_review","failed","blocked_on_human","stopped","released","escalated"]},
  "task":{"terminal":["done"]},
  "session":{"terminal":["ended","lost","superseded"]}}`;
a transition out of a terminal state is refused. Note that `task.done` is the **only** terminal task
state: `failed` and `needs_review` return to `ready` while a budget or an answer remains, which is what
makes a retry a new lane rather than a resurrected one.

---

## 4. The journal

### 4.1 Files, and the single-writer rule

| File | Writers | Shape |
|---|---|---|
| `journal.ndjson` | **the lease holder, and nobody else** | append-only, `seq`-ordered |
| `lanes/<id>/steps.ndjson` | that lane's wrapper | append-only, no `seq` |
| `lanes/<id>/events*.ndjson` | that lane's wrapper (tee) | append-only, no `seq` |
| `resources.ndjson` | the lease holder **and** every lane wrapper | append-only, keyed by `res_id` |
| `control.applied.ndjson`, `answers.ndjson`, `decisions` (inside `journal.ndjson`) | the lease holder | append-only |

**Only the process holding `lease/run.lock` appends to `journal.ndjson`.** That is what lets `seq` be a
plain in-process counter with no locking, and it means a fold never has to reconcile interleaved
writers. A lane wrapper that has something to say writes it into its own `steps.ndjson`; the
supervisor's reap step reads it and mirrors what matters into the journal with a proper `seq`.

`resources.ndjson` is the one multi-writer file, because teardown must be able to read **one** file and
because a lane wrapper creates resources the supervisor never sees. Multi-writer safety comes from
three rules: open `O_WRONLY|O_APPEND|O_CREAT`; one record per single `write(2)`; and
`record.max_bytes: 8192` (DEFAULT-PROPOSED), which keeps every record far inside the size at which a
single append is atomic on APFS. That atomicity is **CLAIMED**, not verified here; the mitigation is
that a reader discards any line that does not parse and records `resources.tail_malformed` rather than
repairing it in place.

**No file in this design is ever rewritten in place except the projections** (`status.json`,
`control.ack.json`, `lease/heartbeat`, `lease/owner.json`, `lease/epoch`), and each of those is
replaced by atomic rename. FIELD-NOTES §2.1 and §11.3 record the previous generation's
`state/attention.tmp` being `: >`-truncated **every cycle** at `harness-run.sh` lines 226 and 361
(VERIFIED, `FIELD-NOTES.md:156`), destroying a whole night of a second process's corrections,
discovered by accident.

### 4.2 The envelope — every record, every kind

```jsonc
{"seq":1042,                              // int, strictly increasing per run, one writer
 "ts":"2026-09-19T23:41:07.412Z",         // string, RFC3339 UTC ms. DISPLAY ONLY
 "mono":918233.114,                       // number, CLOCK_MONOTONIC seconds, 3 dp
 "boot":"1788417532",                     // string, kern.boottime sec, decimal
 "run":"<work-project>-20260919-224100Z-a7f3",
 "epoch":4,                               // int, the fencing token in force (§5.3)
 "actor":"supervisor",                    // supervisor | lane:<lane_id> | judge | doctor | cli:<verb>
 "kind":"transition",                     // one of the seven in §4.3
 …kind-specific fields…}
```

`seq` rules: it starts at 1. On startup the appender reads the **last well-formed line** and resumes
from `seq+1`. **A gap is a crash marker and is never silently closed** — the fold records
`journal.seq_gap` with the two bounding values, because a gap means records were lost and a reader
must know that its picture is incomplete.

### 4.3 The seven record kinds

**`transition`** — the only kind the state fold reads.

```json
{"kind":"transition","machine":"lane","subject":{"lane":"L03-t-118","ticket":"t-118"},
 "from":"working","to":"harvesting","cause":"exit.observed",
 "detail":{"exit_code":0,"terminal_event":"turn_completed"}}
```

`machine` ∈ `run | lane | task | session`. `from` is `""` on creation. `detail` ≤ 2 KiB after redaction
(§4.7); anything larger spills to `blobs/`.

**`intent`** — written **before** the effect is attempted.

```json
{"kind":"intent","op":"board.transition","action_id":"sf-…-a7f3:4:L03-t-118:board.transition:1",
 "idem":"sha256:9f2c…","subject":{"lane":"L03-t-118","ticket":"gh#412"},
 "args":{"from":"ready","to":"in progress"},
 "expect":["board_readback"],"ops_version":3,"timeout_s":60}
```

`expect[]` is copied from `ops.json.admissible[]` **at intent time**, so a later reader can tell what
the writer intended to prove before it found out whether it could.

**`result`** — written **after**, referencing the intent by `action_id`.

```json
{"kind":"result","for":"sf-…-a7f3:4:L03-t-118:board.transition:1","outcome":"ok",
 "evidence":[{"kind":"board_readback","field":"status","observed":"in progress",
              "read_back_at":"2026-09-19T23:41:11.802Z"}],
 "cost":{"wall_ms":4211}}
```

`outcome` ∈ `ok | failed | partial | unknown | skipped`. Evidence kinds, and nothing else is
admissible anywhere:

| kind | fields | proves |
|---|---|---|
| `git_ref` | `ref, before, after, read_back_at` | a ref moved, read back after the fact |
| `board_readback` | `field, observed, read_back_at` | the tracker's own value now reads what was written |
| `file_digest` | `path, sha256` or `absent: true` | a file's content, or its absence |
| `process_exit` | `pid, code` | a process this run started exited with a code |
| `process_absent` | `pid, pid_lstart` | `kill -0` fails, or the start time no longer matches |
| `http_status` | `code, predicate, predicate_result` | a named body predicate held, not merely a 200 |
| `transcript_event` | `path, seq, type` | a typed event exists in a durable transcript |
| `token_drop` | `before, after, basis, prov` | a **measured** context drop, with its provenance |

**The dedup key goes into the effect, not only into the journal** (`JUDGE-cost` G5). A board comment
carries `orchestrator-action: <action_id>` as a trailer; a branch the orchestrator itself creates
carries the epoch; a commit the orchestrator itself makes carries `Orchestrator-Action:` and
`Orchestrator-Epoch:` trailers. This is **not** applied to a work commit the agent makes — that is the
engine's business (R1-13 [344]). It means a replayer after a crash asks **the board**, not the journal,
whether a comment was already left. FIELD-NOTES §12.6 and C3-A12 record duplicate-comment handling as
an already-observed hazard.

**`observation`** — a reading, never a decision.

```json
{"kind":"observation","what":"lane.context","subject":{"lane":"L03-t-118"},
 "value":{"used":412331,"window":1000000,"pct":41.2},
 "basis":"raw_window","prov":"measured","age_s":22,"source":"adapter:claude@1.2.0"}
```

`prov` ∈ `measured | estimated | unknown`, and **`missing` is never `zero`**: an absent capacity
reading is `{"kind":"unknown","reason":"…"}`, never `used_pct: 0`.

**`decision`** — a judgement, with its inputs and its author.

```json
{"kind":"decision","actor":"judge","what":"lane.stall_verdict","subject":{"lane":"L09-t-121"},
 "verdict":"wait","because":[1031,1038],"authority":"run.mode=controlled; rules=RULES.md@sha256:ab…",
 "fact_sheet_sha256":"sha256:77e1…","reported":false}
```

**A decision record is never evidence of anything.** It records that a judgement was made and points at
the observations it was made on. The reason this separation is load-bearing: a model in the previous
generation wrote **26 refusal events in an audit log that never happened** (VERIFIED,
`FIELD-NOTES.md:703`). `reported` implements R1-14 [062] — in an autonomous run the agent may decide
and «прозвітовує, про те, що було таке от рішення»; the report is a projection over
`kind:"decision" AND reported:false`, flipped when it reaches the notification channel.

**`control`** — one per entry read out of `control.json`.

```json
{"kind":"control","entry_id":"c-0012","verb":"stop","scope":"run","apply":"now",
 "source_sha256":"sha256:…","author":"cli:orchestrator:stop-hard",
 "disposition":"applied","reason":null}
```

`disposition` ∈ `applied | deferred | rejected`, with `reason` required on the last two. A `rejected`
entry is **always** surfaced in `control.ack.json.rejected[]` and never silently ignored.

**`note`** — free text, never load-bearing, always redacted (§4.7).

### 4.4 The append algorithm, and the six refusal rules

```
append(record):
 1. record.seq   ← ++counter
 2. record.ts    ← now, RFC3339 UTC ms
 3. record.mono  ← CLOCK_MONOTONIC seconds
 4. record.boot  ← cached boot epoch
 5. record.epoch ← read lease/epoch                       # one 8-byte read, every time
 6. if record.epoch ≠ held_epoch:  exit 75                # R1 — the fence, write nothing
 7. apply redaction to every free-text field              # R7
 8. if serialised length > record.max_bytes:              # R3
        spill the largest field to blobs/<sha256>, replace with {"blob":…,"bytes":N}
 9. run refusal rules R2, R4, R5, R6 for this kind
10. one write(2) of the line, O_APPEND, terminated by \n
11. if this kind is in journal.fsync's set:  fsync(fd)    # §4.5
```

**R1 — the fence.** A writer whose in-memory epoch no longer equals `lease/epoch` writes nothing and
exits **75**. This is cooperative; §5.7 states exactly what it does and does not guarantee.

**R2 — no orphan result.** A `result` whose `action_id` has no earlier `intent` in this run's journal
is refused. The lookup is over an in-memory set of open `action_id`s, rebuilt by the fold on startup.

**R3 — size.** `record.max_bytes: 8192` (DEFAULT-PROPOSED). Oversized payloads are content-addressed
into `blobs/<sha256>` and referenced. This keeps every append inside the size where a single
`write(2)` append is atomic in practice, and it stops one pathological transcript line from making the
journal unparseable.

**R4 — the evidence gate.** A `result` with `outcome: "ok"` for an op whose `ops.json` entry has
`mutating: true` is **refused** unless `evidence[]` contains at least one entry whose `kind` is in that
op's `admissible[]`. On refusal the appender writes, in its place, the same result with
`outcome: "unknown"` and `error: "evidence_missing"`, and the caller exits 70.

Two things to keep verbatim from `ARCH-reliability`'s own tension note, because they are what keep this
rule on the right side of R1-13: **this does not verify the work; it verifies that the orchestrator's
own operation happened.** The engine says whether the ticket is done (R1-13 [344] «оркестратор повинен
діяти відповідно тому сетапу, який в нього є … не роби обмеження те, що вся робота потім буде мати
тести»). The orchestrator says whether the orchestrator's own step ran. A merge either moved a ref or
it did not, on any project, with or without tests. The distinction was never put to the owner — §14.

**Adding an op to `ops.json` without declaring its evidence and its reconcile probe is a load-time
error**, so the file cannot rot into a list of unchecked rows.

**R5 — legal transitions only.** A `transition` whose `(machine, from, to, cause)` is not in
`transitions.json` is refused; the appender writes a `note` naming the tuple, and the run takes
`internal.error` → `aborted`, exit 70. `journal.on_illegal_transition: refuse_and_abort`
(DEFAULT-PROPOSED) — the alternative, `record_and_continue`, is available and is the wrong default: a
state machine that accepts a transition it does not know is a state machine whose diagram is fiction.

**R6 — the trip watermark.** Any record that is going to *cause an action* — a judge call, a
notification, a compaction, a stop — first creates `trips/<trip_key>.json` with `set -o noclobber`,
where `trip_key = sha256(predicate, subject, epoch, armed_at)`. **The file is created before the
action, not after.** An existing trip file means the predicate already fired for this arming and the
action does not re-fire. VERIFIED today: `( set -o noclobber; : > f )` succeeds once and then exits 1,
with no race. A ceiling answers *how much*; a watermark answers *again?* — and the 85-minute loop
(FIELD-NOTES §11.6) was a re-firing detector, not a spending one.

**R7 — redaction.** §4.7.

### 4.5 What is fsynced, and when

`fsync(2)` on macOS pushes to the device but does **not** flush the drive's own cache; `F_FULLFSYNC`
does and costs an order of magnitude more. This spec protects against **process death**, which
`fsync` covers, and not against sudden power loss. `journal.fullfsync: false` (DEFAULT-PROPOSED) —
the failure this system actually suffers is a killed process, not a pulled plug, and the previous
run's 34 hours contain no power-loss event.

`journal.fsync: transitions` (DEFAULT-PROPOSED), of `all | transitions | none`:

| Record kind / file | `none` | `transitions` (default) | `all` |
|---|---|---|---|
| `transition` | no | **yes** | yes |
| `intent` for a `mutating: true` op | no | **yes** | yes |
| `result` for a `mutating: true` op | no | **yes** | yes |
| `control` | no | **yes** | yes |
| `decision` | no | no | yes |
| `observation`, `note` | no | no | yes |
| `lease/epoch`, `lease/owner.json` | **always: fsync the temp file, rename, then fsync the directory** | | |
| `lanes/<id>/start.json` | **always: fsync the file, then fsync the lane directory, before launch** | | |
| `lanes/<id>/result.json` | **always: fsync the file, then fsync the lane directory, before the `mv`** | | |
| `resources.ndjson` | **always, per record** — it is the teardown list, and a lost line is a resource nobody will ever stop | | |
| `status.json`, `control.ack.json`, `lease/heartbeat` | never fsynced. Derived, rebuilt every tick | | |

The arithmetic behind the default: at `tick.interval_seconds: 60` with two lanes, a full tick produces
roughly one to four transitions and six to twelve observations. `transitions` fsyncs the few records
whose loss would change the folded state and leaves the readings, which the next tick re-takes anyway.

### 4.6 Size, sampling and truncation

`journal.observation_sampling: on_change` (DEFAULT-PROPOSED), of `on_change | every_tick`: an
observation is written only when its `value` differs from the last observation for the same
`(what, subject)`, **or** when `observation.max_age_s: 900` has elapsed since the last one. The
max-age clause exists so that "nothing changed for four hours" is a positive record rather than a
silence.

Sizing, INFERRED from those defaults: a 34-hour run at 60-second ticks with two lanes produces roughly
2,000 ticks, ~4 transitions per minute at worst and far fewer typically, and with `on_change` sampling
perhaps 12,000–20,000 records at ~350–450 bytes — **5 to 9 MB**. No rotation during a run, and none
after: the journal is the run's record and stays with the run directory.

**Truncation.** A last line that does not parse is **discarded**, an observation `journal.tail_truncated`
is recorded on the next append, and the line is never repaired in place. The same rule applies to every
append-only file.

### 4.7 The journal never contains the strings its own detectors match

`ARCH-adapters` §10.2 non-negotiable 4, via `JUDGE-survival` G11. A governor must never write
`/compact`, `rate-limit`, `usage limit`, `STOP`, or any other literal its own detectors match into a
file its own detectors read.

`triggers.json` ships with the plugin and holds the literal list. `redact_triggers(text)` replaces each
occurrence with `«‹trigger:NAME›»` and is applied to every free-text field of every record —
`note.text`, `transition.detail`, `result.error`, `decision.authority` — before serialisation.
`triggers.redact: true` (DEFAULT-PROPOSED).

Two structural rules sit under it, and they matter more than the redaction:

1. **A detector's input is `events.norm.ndjson` — a closed vocabulary of seven event types — never
   `journal.ndjson` and never a log of prose.** The 85-minute loop read a surface carrying the
   orchestrator's own wrapped prose (FIELD-NOTES §11.6, where line 5620 reads `NO ONE IS BEING TOLD`).
2. **Marker files never carry meaning by existing.** A lock is a `flock` target whose existence means
   nothing; a trip file's existence means exactly one thing and it is namespaced by epoch.
   FIELD-NOTES §11.7 records an unattributed `STOP` file on disk, issue `#82`, open.

### 4.8 The projections, and self-write suppression

Three files are rewritten every tick by atomic rename. **None of them is ever read to determine state.**

**`status.json`** — the pull surface for Д11 [508]. It contains only facts the supervisor can prove,
every number carrying `age_s` and `prov`. **There is no `healthy` field**, and this is deliberate:
C9-A4 shows the previous generation computed `healthy` from an attention file its own watch loop
truncated every cycle, so it would have printed `healthy: true` for all 85 minutes of the loop.
`blocked_on` is a list of named facts and the owner reads the list.

**`control.ack.json`** — the supervisor's reply to whoever wrote `control.json`:

```json
{"schema":1,"read_at":"…","doc_sha256":"sha256:…","epoch":4,
 "applied":["c-0012"],"deferred":[{"id":"c-0013","until":"lane L03 boundary"}],
 "rejected":[{"id":"c-0014","reason":"key context.basis is frozen for this run"}],
 "parse":{"ok":true,"error":null}}
```

`orchestrator:stop-*` writes its entry and then **polls this file** until it shows the entry applied,
or `stop.ack_timeout_seconds: 90` (DEFAULT-PROPOSED — one 60-second tick plus margin) elapses. Exit 0
means applied. **Exit 8 means written but unacknowledged**, and the message names
`orchestrator:doctor`. `ARCH-minimal`'s stop prints *"applied within 60s"*, which is a promise about a
process that may be dead; FIELD-NOTES §11.2 records two real operator instructions recorded as
delivered and never executed.

**`lease/heartbeat`** — advisory, for `status` and for the doctor's stall check. **Never** for deciding
whether to take over.

**Self-write suppression, by content.** The supervisor records the `sha256` of everything it writes to
any watched surface — `control.json` (it never writes it, by design), the board, a ticket body — and a
detected change whose digest it produced is ignored. This is the one-line fix for C3-A1: the
orchestrator's own status comment firing its own change detector, and Д9 then reacting to it, forever.

**Parse failure never takes the run down.** On a `control.json` that does not parse: keep the last good
entries, apply nothing new, set `control.ack.json.parse` with the error and the file's mtime, notify
once. *Boot fails loud; reload keeps last good* — the `dsh` settings-file protocol,
`ADOPTION-VERDICT` §4 item 9 (CLAIMED).

---

## 5. The single-orchestrator lease

R1-10 [300]/[301] is the only requirement in the interview the owner stated as an absolute and then
repeated: «не може бути такого, що вже якісь існуючі оркестратор і спускається наступний, тому що тоді
це буде просто нескінченний цикл оркестраторів … має бути якісь лог файлів, коли що запустилось …
якщо раптом одночасно два якісь оркестратори працюють, то це не окей» · «Це треба відслідковувати і
**не дозволяти**». The restatement at [302] was ratified at [304] («Та, правильно») — one of the
twenty-six confirmations in `corrections.md`'s ratified list. This section is the only part of this
spec standing on a ratified requirement rather than on an unratified restatement.

### 5.1 The lock file and its holder

**One lock per project, not per run.** `~/.orchestrator/locks/<project_key>.lock`.

The holder is `orch-lock.py`, twenty lines, executed and VERIFIED on this machine today:

```python
import fcntl, os, sys, time
lockpath, argv = sys.argv[1], sys.argv[2:]
if argv and argv[0] == '--': argv = argv[1:]
fd = os.open(lockpath, os.O_RDWR | os.O_CREAT, 0o644)
try:
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
except OSError:
    os.lseek(fd, 0, 0)
    sys.stderr.write("LOCK HELD: " + os.read(fd, 4096).decode() + "\n")
    sys.exit(69)
os.ftruncate(fd, 0)
os.write(fd, ("%d %d %s\n" % (os.getpid(), int(time.time()), " ".join(argv))).encode())
os.fsync(fd)
os.set_inheritable(fd, True)
os.execvp(argv[0], argv)
```

Measured behaviour, today, on this machine:

- a second attempt while the first holds prints `LOCK HELD: 15675 1789826700 sleep 3` and exits **69**;
- after the holder exits normally, the next attempt acquires **immediately**;
- after `kill -9` of the holder, the next attempt acquires **immediately**.

**There is no TTL, no stale-lock timeout and no heartbeat in the correctness path.** The lock being
acquirable *is* the proof that the previous supervisor is gone — this is `deepseek-harness`'s
`flock-contract.md` property, which `ADOPTION-VERDICT` §4 item 7 recommends taking as a rule rather
than as code. It also dissolves C6-A2's "third verdict" problem for the takeover path: there is no
probe that can error, because there is no probe.

`flock(1)` is **not installed on this machine** (VERIFIED) and `/usr/bin/shlock` is PID-based, so
neither is an option; this is why the holder is Python.

### 5.2 Identity — `lease/owner.json`

The lock alone answers *is someone holding it*. It does not answer *is the recorded holder still the
process we think it is*, and PIDs are recycled.

```json
{"run":"<work-project>-20260919-224100Z-a7f3","epoch":4,"kind":"run",
 "host":"…","boot":"1788417532",
 "pid":41233,"pid_lstart":"Sat Sep 19 21:04:55 2026","argv_sha256":"sha256:c1de…",
 "exe":"/usr/bin/python3","started_at":"2026-09-19T21:04:55.113Z","started_mono":918233.114}
```

Three fields together are the identity, and each closes a hole the others leave:

- **`pid`** — `kill -0 <pid>` says a process with that number exists.
- **`pid_lstart`** — `ps -o lstart= -p <pid>` says when *that* process started. VERIFIED today:
  `ps -o etimes=` is **not supported** by this macOS `ps` (`ps: etimes: keyword not found`), so
  `lstart` is the only portable start-time field here, and it has **one-second resolution**. A PID
  recycled inside the same second would match — which is why there is a third field.
- **`argv_sha256`** — `sha256` of the holder's full argv, read from `ps -o command= -p <pid>`. A
  recycled PID that happens to land in the same second is not also going to be running the same
  command line.

`host` and `boot` guard the case where the state directory is on a synced or shared volume: a record
from a different host or a different boot is never treated as a live holder.

### 5.3 `lease/epoch` — the fencing token

One file, one integer, no newline ambiguity (write `printf '%d'`, no trailing `\n`; readers accept
either). It starts at `1` on the first acquisition and is **incremented on every successful
acquisition**, including a takeover. It is never decremented and never reset.

Where it appears:
1. Every journal record's `epoch` field.
2. Every `action_id`: `<run_id>:<epoch>:<lane>:<op>:<attempt>`.
3. Every trip key, so a new epoch re-arms every detector exactly once.
4. `lanes/<id>/epoch` — the epoch each lane is currently fenced to, rewritten by the supervisor on
   adoption.
5. The `Orchestrator-Epoch:` trailer on any commit, branch name or board comment the orchestrator
   itself makes.

### 5.4 Acquisition — the algorithm, in order

```
 1. project_root ← dirname(realpath(git rev-parse --git-common-dir))
 2. project_key  ← sha1(project_root)
 3. exec orch-lock.py ~/.orchestrator/locks/<project_key>.lock -- <supervisor argv>
       └─ lock held  → print LOCK HELD line, exit 69.  Nothing is created.
 4. (now holding the lock, as the supervisor process, with the lock fd inherited)
 5. resolve the run: --run <id>, else $ORCH_RUN, else the newest non-terminal run for
    project_root in index.tsv.  None → this is a new run, go to 9.
 6. SPLIT-BRAIN CHECK.  Read runs/<run>/lease/owner.json.  If it exists AND
        owner.host == this host AND owner.boot == current boot
        AND kill -0 owner.pid succeeds
        AND ps -o lstart= -p owner.pid == owner.pid_lstart
        AND sha256(ps -o command= -p owner.pid) == owner.argv_sha256
    then the lock was free while its recorded holder is alive.
        → release the lock, notify, exit 76.  DO NOT ACT.
 7. SLEEP FENCE (takeover path only, §5.8).  If the last journal record's boot differs from the
    current boot and less than sleep.grace_seconds have passed since boot, or a machine.wake
    observation is younger than sleep.grace_seconds → release, exit 77 (UNKNOWN), retry later.
 8. (recovery path) run the fold (§7.2) before touching anything.
 9. epoch ← read lease/epoch (absent → 0); epoch ← epoch + 1
10. write lease/epoch.tmp, fsync, rename over lease/epoch, fsync the lease directory
11. write lease/owner.json.tmp with this process's identity, fsync, rename, fsync the directory
12. append the transition:
       new run  → run: "" → starting        cause=run.started
       takeover → run: <folded state> → <same state>  cause=lease.taken_over   (a declared self-loop,
                  §3.7 — the record that says this run is now fenced to a new epoch)
13. start the heartbeat writer: every lease.heartbeat_seconds, atomic-rename lease/heartbeat
```

Step 6 exists because `flock` is on a **path**, and a path can be replaced. If someone deletes
`locks/<project_key>.lock` while it is held, the next acquirer creates a new inode and gets a lock on
it, while the original holder still holds a lock on the unlinked one. `flock` alone cannot see that;
`owner.json` can. This is OpenClaw's `resolveGatewayOwnerStatus` shape, including its fail-closed
behaviour when the process reader is unavailable (`ADOPTION-VERDICT` §4 item 4, CLAIMED,
reimplemented rather than imported per that document's own advice). **If any of the three identity
reads fails rather than returning a value, the check fails closed: exit 76.**

### 5.5 Stale detection — one authority and two advisories

| Signal | What it proves | Used for |
|---|---|---|
| **`flock` is acquirable** | the previous holder is gone. No timeout, no heuristic | **The only signal that authorises a takeover.** |
| heartbeat age | the holder wrote a heartbeat `N` seconds ago | `orchestrator:status` display; the doctor's stall check |
| `journal.ndjson` byte growth | the holder appended something since the last visit | the doctor's step 2 |

**We never take over on a timeout.** That single line is what makes «не може бути … одночасно два»
structural rather than heuristic, and it is why neither advisory signal can promote itself.

A wedged-but-alive holder — one that keeps its lock and stops doing anything — is the case the lock
alone cannot see, and `ARCH-reliability` §18.3 names it as its own worst case. It is covered by the
doctor's step 2 below, which is `JUDGE-survival`'s highest-value graft from its lowest-ranked design.

### 5.6 Takeover — the doctor

`doctor.enabled: false` (DEFAULT-PROPOSED — it needs a separate account, if the user configures one), on
`launchd` `StartInterval` every `doctor.interval_hours: 2`, under a **different account**, which is
R1-10 [246]. `launchd` fires after a wake where `cron` would not.

```
take machine.lock (non-blocking; already held → exit 0, another doctor is running)
for each run in index.tsv whose state is not terminal:
    try orch-lock.py <project lock> non-blocking
    ├─ FAIL (exit 69) → LIVE
    │     step 2: journal.ndjson size vs the size recorded in doctor/state.json last visit
    │             not grown → the holder is alive and not ticking
    │                       → write {stop, run, now} into control.json; notify; exit 12
    │     step 3: status.json.queue.done_this_run vs last visit
    │             unchanged → NOTIFY ONLY, never kill.  Slow and stuck are not
    │                         distinguishable from outside.  exit 0
    └─ OK (acquired) → read lease/owner.json
          ├─ holder alive AND lstart matches AND argv matches → SPLIT BRAIN
          │      release, notify, exit 76, DO NOT SPAWN
          ├─ a machine.wake within sleep.grace_seconds, or boot changed recently → UNKNOWN
          │      release, notify per doctor.on_unknown, retry next interval, exit 77
          └─ otherwise → DEAD
                 bump epoch, write owner.json, and — STILL HOLDING THE LOCK —
                 exec the supervisor in recover mode, which inherits the lock fd.
                 exit code is the supervisor's.
    record this run's journal size and done counter into doctor/state.json
```

**`exec` while holding the lock is the whole trick**: there is no window between deciding the previous
holder is dead and the new holder taking the lock, because the fd is inherited across `execvp` (the
holder sets it inheritable — VERIFIED in §5.1's script and in its execution today).

**`doctor.on_unknown: notify_and_hold`** (DEFAULT-PROPOSED). This is C6-A2's third verdict and it is
decided in the direction his own words point: «якщо раптом одночасно два … це не окей» [300] is an
absolute, while «ран зупинився» [246] is a problem to be solved, and an absolute outranks a problem.
**The cost is real and is stated:** a run can sit dead until morning if the doctor can never resolve
`UNKNOWN`. The mitigation is that `UNKNOWN` is rare by construction — the probe is a local `flock`, not
a network call, so the outages that produced C6-A2 (429s, expired tokens, cross-account roster
blindness) cannot reach it.

**A takeover never re-runs the run from the start.** «Заново запустити оркестратора» [300], ratified at
[304], means restart the orchestrator, not redo the work. `recover` mode enters preflight with the
token-spending gates skipped and re-runs only the gates that can have gone stale in the intervening
hours — the account gates especially, because an account may have expired.

`run.mode_on_takeover: controlled` (DEFAULT-PROPOSED): `ask` has nobody to ask at 04:00 (C1-A5), and a
recovered run that asks rather than guesses is the conservative direction.

### 5.7 What the fence actually guarantees — and what it does not

The brief asks for the fencing token *"that makes a resurrected orchestrator unable to act on stale
beliefs."* Here is the honest accounting, case by case.

**Enforcement has three layers, and only the second is a guarantee.**

1. **Write-side, cooperative.** Every appender re-reads `lease/epoch` immediately before writing and
   aborts with exit 75 on a mismatch (§4.4 R1). This stops a cooperating process at its *next* write.
   It cannot stop a process that has already written, and it cannot stop a process that is not ours.
2. **Read-side, authoritative.** The fold (§7.2) tracks `max_epoch_seen` and **discards any record
   whose `epoch` is lower than a record already folded**, emitting `fence.stale_record`. Because the
   fold is monotone in epoch and is the only route from the journal to a state, **a stale write cannot
   change the folded state.** This is the guarantee.
3. **Effect-side.** Every external mutating effect carries its epoch in `action_id` (in the board
   comment trailer, in the commit trailer, in the branch name). The reconciler comparing an effect's
   epoch against the current one records `stale_effect` and escalates; it never counts a stale effect
   as a result.

**Which resurrection cases this covers:**

| Case | Who prevents it |
|---|---|
| Two supervisors running at once | **`flock`**, not the fence. The fence is not needed here. |
| A lane wrapper of a dead supervisor still running when a new supervisor takes over | The new supervisor either **adopts** it (pid + lstart + argv all match `start.json`, and it rewrites `lanes/<id>/epoch` to the new epoch, which the wrapper re-reads before each write) or marks it `orphaned` and reconciles. |
| A killed-but-not-dead wrapper waking mid-teardown and writing `result.json` claiming success | `result.json` carries `epoch`; the fold ignores a `result.json` whose epoch is behind `lanes/<id>/epoch`, recording `fence.stale_result`. |
| The doctor running twice | `machine.lock`. |
| A frozen supervisor thawing after a machine sleep | **Nothing needs to**: a frozen process still holds its `flock`, so the doctor correctly reads LIVE and never takes over. The sleep fence (§5.8) exists for the *liveness verdicts*, not for the lease. |
| A supervisor `SIGSTOP`ped by hand and later `SIGCONT`ed | Same as above — it holds its lock throughout, so no second supervisor exists and there is nothing stale to fence. |

**What the fence does not cover, stated plainly:** an effect that a stale process performed *in the
world* and that carries no trailer — a `git push` of a branch, a file written in a worktree, an HTTP
call to something that keeps no record. The epoch cannot reach those. The mitigation is the scope of
what a lane may do: it acts inside its own worktree and its own compose project, both of which are in
the ledger, and the ledger is what teardown reads.

### 5.8 The sleep fence

C6-A5 is the failure that ended the previous run, verbatim in its log:
`[2026-09-07T09:08:21Z] watch: orchestrator dead + no live sessions for 3 ticks — tearing down (Mac
may sleep)` (VERIFIED, `FIELD-NOTES.md:419`). On wake, every staleness reading says dead, the process
object says alive, and **both are correct**.

1. Every journal record carries `mono` and `boot` (§1.2). Durations are computed on `mono`; wall clock
   is display only.
2. The supervisor detects a wake as a tick in which
   `wall_delta − mono_delta > sleep.gap_seconds` (DEFAULT-PROPOSED **60**), and writes
   `observation: machine.wake` with the gap. (Darwin's `CLOCK_MONOTONIC` not advancing across sleep is
   CLAIMED from `ARCH-reliability` §11.2; the threshold is INFERRED.)
3. **A wake invalidates every liveness verdict.** For `sleep.grace_seconds` (DEFAULT-PROPOSED **120**)
   after a wake: no lane may be judged dead, no capacity reading taken before the wake is
   authoritative, and the run may enter `paused` with `pause_reason: wake` if a threshold would
   otherwise have fired. Network re-establishment and session resumption happen inside that window.
4. `caffeinate -i` is bound to **the supervisor's own pid**, never to a watcher's. The previous
   generation bound it to the watch loop, so when the watch died the machine slept (INFERRED from
   C6's reading of the plugin structure).

The doctor is unaffected by all of this, because its probe is the lock and not a clock.

---

## 6. Claiming, launching and releasing — the ordering invariant

This is stated as an invariant something checks, not as a convention, because `JUDGE-survival` G13 is
right that it is the cheapest orphan detector in the whole set: orphan detection becomes a **directory
listing with no journal read and no parse**, which is exactly what a resuming process that does not
yet trust anything on disk needs.

### 6.1 The claim is `mkdir`

`mkdir lanes/<lane_id>` is atomic on POSIX and succeeds exactly once. No lock file, no read-then-write,
no compare-and-swap. C3's research measured the read-then-write shape at **27 winners out of 50**, and
FIELD-NOTES §10.2 records two concurrent adds producing two files under one id in **five rounds out of
five** (both CLAIMED via `ARCH-minimal` §4). `mkdir` is one syscall and cannot do that.

### 6.2 The order, and nothing may be reordered

```
 1. mkdir lanes/<lane_id>                       ← THE CLAIM. Fails → someone has it, move on
 2. append transition task: ready → claimed     (cause task.claimed)
 3. board.transition ready → in progress        (an op; board_readback is its only evidence)
       fails → result outcome:"partial"; rmdir the lane; task returns to ready. A claim is never
       held on an unverified board write — that is how two workers end up on one ticket
 4. write lanes/<id>/epoch                       ← the lane's fence
 5. write lanes/<id>/start.json                 ← BEFORE ANY PROCESS IS LAUNCHED
       fsync the file, then fsync the lane directory
 6. append transition lane: claimed → preparing (cause start.written)
 7. prepare: worktree, env, services — each created resource appended to resources.ndjson
       AS IT IS CREATED, never after a batch
 8. launch. The wrapper execs the platform command in its own foreground, stdin from /dev/null,
    under an external wall-clock timeout, teeing the structured stream to events.ndjson
 9. …the lane runs…
10. write lanes/<id>/result.json                ← LAST. fsync file, fsync directory
11. mv lanes/<lane_id> lanes.done/<lane_id>     ← THE ONLY COMMIT POINT
```

**Nothing is written into the lane directory after `result.json`.** The directory move is the commit.

`start.json`:

```json
{"lane":"L03-t-118","ticket":"t-118","ticket_sha256":"sha256:…","attempt":1,
 "run":"sf-…-a7f3","epoch":4,
 "platform":"claude","account":"<profile-B>","provider":"anthropic",
 "worktree":"/Users/…/.worktrees/L03-t-118","base_ref":"main","base_sha":"93fdf65…",
 "compose_project":"orc-L03-t-118",
 "session_id":"0b6c…","id_source":"client",
 "engine_ref":{ … §8.2 … },
 "cmd":["claude","-p","--verbose","--output-format","stream-json","--session-id","0b6c…","/gsd:execute-phase","30"],
 "argv_sha256":"sha256:…","pid":41977,"pid_lstart":"Sat Sep 19 23:41:02 2026",
 "started_at":"…","started_mono":918233.114,"timeout_s":14400}
```

`pid` and `pid_lstart` are written by the wrapper **after** the fork and **before** the exec of the
platform binary, by re-writing `start.json` once. That is the only rewrite of the file and it is atomic
by rename.

### 6.3 What a crash leaves, by construction

| Crashed after step | On disk | Verdict |
|---|---|---|
| 1 | a lane dir with **no** `start.json` | `released` — nothing had been launched. Remove the dir, the task returns to `ready`. Safe, unconditionally. |
| 5–9 | `start.json` and **no** `result.json` | **`orphaned`** — a detectable orphan, never a false claim of completion. §7.3. |
| 10 | `result.json` present, dir still under `lanes/` | terminal outcome known; finish the move. Idempotent. |
| 11 | dir under `lanes.done/` | nothing to do. |

*Append `start` first, `end` last* is `dsh`'s compaction rule, recommended verbatim by
`ADOPTION-VERDICT` §4 item 8 as the fix for the whole "reported success and did nothing" class.

### 6.4 The resource ledger — written before creation

```jsonc
{"res_id":"r14","lane":"L03-t-118","epoch":4,"type":"docker_compose_project",
 "state":"creating","created_at":"…",
 "identity":{"project":"orc-L03-t-118","labels":{"orc.run":"sf-…-a7f3","orc.lane":"L03-t-118"}},
 "teardown":{"op":"compose.down","args":{"project":"orc-L03-t-118","volumes":true}},
 "assert":{"op":"compose.ps","args":{"filter":"label=orc.run=sf-…-a7f3"},"expect":"empty"}}
{"res_id":"r14","state":"created","at":"…"}
{"res_id":"r14","state":"resolved_ok","at":"…","evidence":{"kind":"process_exit","code":0}}
```

Two states per resource plus a resolution: `creating → created → resolved_{ok|absent|failed}`.
The `creating` line is written **before** the resource exists, so a crash between the two leaves a
resource that may or may not exist, recorded as such, rather than a resource nobody knows about.

| type | identity that survives a process death | teardown | proof |
|---|---|---|---|
| `session` | `(platform, account, session_id)` | adapter `stop` | `process_absent` + adapter listing |
| `process_group` | `(pgid, leader_lstart, argv_sha256)` | `kill -TERM -<pgid>`, then `-KILL` after `stop.hard_grace_seconds` | `process_absent` |
| `git_worktree` | absolute path under the run's worktree prefix | `git worktree remove` | `file_digest` with `absent: true` |
| `docker_compose_project` | the compose project **name** on the command line, plus container labels | `docker compose -p <recorded name> down` | `docker ps -q --filter label=orc.run=<run>` empty |
| `port_block` | the reserved range | released by record | — |
| `unowned_session` | whatever is known (§3.5) | **listed, never auto-killed** | — |

**Two rules, both from the record, both non-negotiable:**

1. **Every identifier in a teardown command comes from a `resources.ndjson` field, never from the
   environment.** FIELD-NOTES §11.5 records the owner's own default Docker stack destroyed by a
   `docker compose down -v` with **`COMPOSE_PROJECT_NAME` absent**, so the command resolved to the
   default project; the actor was never identified, and §12.4 records that detached scripts inherit no
   environment at all. A lint on `pkill`/`killall`/unscoped `docker compose down` would not have caught
   it; a lint on *teardown arguments sourced from the environment* would.
2. **Assert by observation, never by the command's word.** `ADAPTER-CONTRACT` §2.4 invariant 10 records
   `cursor-agent worker kill` reporting success and leaving the process at 100 % CPU (CLAIMED).

Anything that fails to resolve makes the run `degraded` and is named in `report.md` and `status.json` —
never swallowed. And nothing this run did not start is ever touched, in any state (R1-16 [370]): the
ledger *is* the identity, and the orchestrator acts only on a pid it recorded starting whose start time
still matches. FIELD-NOTES §11.8's `pkill -f 'playwright test'` killing an unrelated lane is
structurally unreachable, because **nothing in this design matches processes by pattern, ever.**

---

## 7. Resume without reading a transcript

### 7.1 The resume set — exactly seven things, and no transcript among them

A fresh orchestrator resumes by reading these and nothing else:

| # | Source | Answers |
|---|---|---|
| 1 | `lease/epoch`, `lease/owner.json` | who held it, at what fence |
| 2 | `journal.ndjson`, folded | every machine's state, every open `action_id` |
| 3 | `lanes/*/` — **directory listing only** | which claims are live, which are orphans (§7.3) |
| 4 | `resources.ndjson` | what must be torn down, and how, and how to prove it |
| 5 | `control.json` + `control.applied.ndjson` | which commands are outstanding |
| 6 | `config.resolved.json` + `config.sources.json` | what the run was configured with, and whether it changed |
| 7 | each lane's `start.json.engine_ref`, plus one fresh engine probe | where **the work** stands — which is the engine's business, not the orchestrator's (§8) |

**No transcript is read to determine state.** R1-10 [293]/[310] does want transcripts available —
«попередніх сесій, попередніх транскриптів … для кожної платформи можна налаштовувати, як саме буде
робитись відновлення» — and they stay available: `recovery.sources` (DEFAULT-PROPOSED
`[journal, engine_records, transcripts]`) is an ordered allow-list, and a transcript is used **only to
reseed a session's context**, never to decide what the run's state is. The rule is
`recovery.read_transcripts: never_for_state` (DEFAULT-PROPOSED). The reason is in his own requirement:
on Amp and `dsh` the transcript exists only on the pipe, so a dead supervisor destroys it — a recovery
that needs the transcript is a recovery that fails exactly when it is needed.

### 7.2 The fold — the algorithm

The fold is a **pure function** of the journal, so two readers always agree.

```
fold(journal_path) -> {run, lanes{}, tasks{}, sessions{}, open_actions{}, warnings[]}

 1. state ← {run: null, lanes: {}, tasks: {}, sessions: {}, open_actions: {}, warnings: []}
 2. max_epoch_seen ← 0 ; last_seq ← 0 ; last_boot ← null ; last_mono ← null
 3. for each line in the file, in order:
 4.     if the line does not parse as JSON:
 5.         if it is the LAST line → warnings += journal.tail_truncated ; break
 6.         else                   → warnings += journal.corrupt_line{seq_after: last_seq} ; continue
 7.     if r.seq ≤ last_seq → warnings += journal.seq_regression ; continue
 8.     if r.seq >  last_seq + 1 → warnings += journal.seq_gap{from: last_seq, to: r.seq}
 9.     last_seq ← r.seq
10.     if r.epoch < max_epoch_seen → warnings += fence.stale_record{seq: r.seq} ; CONTINUE  ← the fence
11.     max_epoch_seen ← max(max_epoch_seen, r.epoch)
12.     if r.boot ≠ last_boot and last_boot ≠ null → warnings += machine.reboot{at_seq: r.seq}
13.     last_boot ← r.boot ; last_mono ← r.mono
14.     switch r.kind:
15.       transition:
16.           m ← state[r.machine][subject_key(r)]
17.           if m.state is terminal → warnings += transition.after_terminal ; continue
18.           if (r.machine, m.state, r.to, r.cause) ∉ transitions.json
19.                → warnings += transition.illegal{…} ; continue
20.           m.state ← r.to ; m.since_mono ← r.mono ; m.cause ← r.cause
21.       intent:  open_actions[r.action_id] ← {op, idem, subject, args, expect, seq}
22.       result:  if r.for ∈ open_actions → delete open_actions[r.for]
23.                else warnings += result.orphan{action_id: r.for}
24.       observation | decision | control | note: recorded into per-subject last-value maps only
25. return state
```

Line 10 is the fence (§5.7 layer 2). Line 17 is rule 4 of §3.1. Line 18 is the legality check applied
at read time as well as at write time, because a journal may have been written by an older version of
the plugin whose table was different.

**Cost.** INFERRED: a 34-hour journal of ~20,000 lines folds in well under a second with a single
`jq --stream`-free pass, or in a few hundred milliseconds in Python. The fold runs once per
supervisor start, never per tick.

### 7.3 Orphan detection — a directory listing, with no journal read

This runs **before** the fold, so a resuming process has an answer even if the journal is unreadable:

```
for d in lanes/*/:
    if not exists d/start.json                → RELEASED   (remove d, task returns to ready)
    else if exists d/result.json              → FINISHING  (complete the mv to lanes.done/)
    else:
        read pid, pid_lstart, argv_sha256 from d/start.json
        if kill -0 pid  AND  ps -o lstart= -p pid == pid_lstart
                        AND  sha256(ps -o command= -p pid) == argv_sha256
             → ADOPTABLE   (write d/epoch = new epoch; lane stays `working`)
        else → ORPHANED    (§7.5)
```

Three reads and no parse of anything but one small JSON file per lane. This is what makes recovery
survive a journal the crash left in a state the fold cannot use.

**Adoption is a transition, not a restart.** `lane.adopted` moves the lane to `working` at the new
epoch and the wrapper re-reads `lanes/<id>/epoch` before its next write. Д10 [497] is satisfied
underneath this: the orchestrator «сам повинен проаналізувати, що це таке, навіщо, чи це потрібно
зупинити, чи це потрібно просто почекати» — the *identity* question is answered deterministically by
pid + start time + argv, and only the *judgement* (stop, wait, adopt) goes to the judge, and only for
lanes the deterministic path could not settle.

**Anything alive in the project that is not under `lanes/` is never touched, in any state.** R1-16 case
2 [370], and it is free here because the ledger is the identity.

### 7.4 `ops.json` — the operation catalogue

A shipped data file, not code. This is `JUDGE-cost` G9's narrowed version — the data file, with
`admissible[]` added back per `JUDGE-survival` G1.

```json
{"version": 3,
 "lane.dispatch":     {"mutating":true, "idempotent":"by_session_id", "admissible":["transcript_event","process_exit"], "reconcile":"probe_session", "timeout_s":30},
 "lane.stop":         {"mutating":true, "idempotent":"by_ref",        "admissible":["process_absent"],                  "reconcile":"probe_process", "timeout_s":45},
 "worktree.create":   {"mutating":true, "idempotent":"by_ref",        "admissible":["file_digest"],                     "reconcile":"read_path",     "timeout_s":120},
 "worktree.remove":   {"mutating":true, "idempotent":"by_ref",        "admissible":["file_digest"],                     "reconcile":"read_path",     "timeout_s":120},
 "compose.up":        {"mutating":true, "idempotent":"by_readback",   "admissible":["process_exit","http_status"],      "reconcile":"compose_ps",    "timeout_s":600},
 "compose.down":      {"mutating":true, "idempotent":"by_readback",   "admissible":["process_exit"],                    "reconcile":"compose_ps",    "timeout_s":300},
 "board.transition":  {"mutating":true, "idempotent":"by_readback",   "admissible":["board_readback"],                  "reconcile":"refetch",       "timeout_s":60},
 "board.comment":     {"mutating":true, "idempotent":"by_readback",   "admissible":["board_readback"],                  "reconcile":"refetch",       "timeout_s":60},
 "git.merge":         {"mutating":true, "idempotent":"by_ref",        "admissible":["git_ref"],                         "reconcile":"read_ref",      "timeout_s":300},
 "pr.create":         {"mutating":true, "idempotent":"unsafe",        "admissible":["http_status"],                     "reconcile":"none",          "timeout_s":120},
 "session.compact":   {"mutating":true, "idempotent":"within_turn",   "admissible":["token_drop","transcript_event"],   "reconcile":"read_context",  "timeout_s":600},
 "notify.send":       {"mutating":true, "idempotent":"unsafe",        "admissible":["http_status"],                     "reconcile":"none",          "timeout_s":30},
 "control.apply":     {"mutating":false,"idempotent":"by_ref",        "admissible":[],                                  "reconcile":"none",          "timeout_s":5},
 "engine.probe":      {"mutating":false,"idempotent":"by_ref",        "admissible":[],                                  "reconcile":"none",          "timeout_s":20}}
```

**Idempotency classes**, and what each means for a replayer:

- **`by_ref`** — the effect is visible in a ref or a digest. Replay is safe: read the ref first.
- **`by_readback`** — the effect is visible by re-fetching the target. Replay is safe after a refetch.
  A board comment carries `action_id` in a hidden trailer so a duplicate is detectable.
- **`by_session_id`** — the effect is a session the client named before launch. Replay is safe on the
  platforms where the **client** assigns the id (Claude Code, pi, Droid, OpenCode, Qwen — CLAIMED via
  `ADAPTER-CONTRACT` §3 B). On server-minted platforms (Codex, Kimi, Amp, MiMoCode) it **degrades to
  `unsafe`** inside `orphan.dispatch_window_seconds`.
- **`within_turn`** — the effect is scoped to a model turn that no longer exists after a crash. Never
  replayed; the fallback is reseed.
- **`unsafe`** — replay is not safe and there is no cheap probe. **The reconciler escalates to the Д6
  questions channel and holds the lane; it never replays.** `pr.create` is here unless the board
  carries the PR link, because a crash between opening a PR and recording it produces a second PR, and
  R1-12 [331] *wants* stacked PRs, so nothing downstream finds a duplicate suspicious.

**Adding an op without declaring `admissible[]` and `reconcile` is a load-time error** — the file
cannot rot.

### 7.5 Reconciling an orphan — the decision table

`recovery.probe_before_judge: true` (DEFAULT-PROPOSED). `ARCH-minimal` puts *every* orphan on the
judge's fact sheet, which is a model call per orphan on every restart — and R1-10 [300] makes restarts
an expected event, so that is the one place its otherwise excellent token floor leaks, precisely when
the system is already degraded. A declared probe answers *"did this exact operation already happen?"*
for free in the common cases and escalates only what genuinely cannot be probed.

```
for each open action_id in the fold's open_actions:
 1. op ← ops.json[intent.op]
 2. run op.reconcile with intent.args, under op.timeout_s:
```

| `reconcile` | Probe | Verdicts |
|---|---|---|
| `read_ref` | read the git ref now; compare with `args.before` / `args.after` | `confirmed_done` / `confirmed_not_done` |
| `refetch` | re-fetch the board item; compare the field; look for the `action_id` trailer | `confirmed_done` / `confirmed_not_done` / `indeterminate` (board unreachable) |
| `probe_session` | list sessions by the client-assigned id, or `adapter resume` | `confirmed_done` / `confirmed_not_done` / `indeterminate` (server-minted id) |
| `probe_process` | `kill -0` + `lstart` match | `confirmed_done` (absent) / `confirmed_not_done` (alive) |
| `read_path` | `stat` the path | `confirmed_done` / `confirmed_not_done` |
| `compose_ps` | `docker ps --filter label=orc.run=<run>` | `confirmed_done` / `confirmed_not_done` / `indeterminate` (docker down) |
| `read_context` | adapter `readContext`; compare with the pre-compaction reading | `confirmed_done` / `indeterminate` |
| `none` | — | `indeterminate` |

```
 3. decide:
    confirmed_done      → synthesise the missing `result` with the probe output as evidence.
                          The synthesised result carries actor:"reconciler" and the probe's own
                          evidence kind — it never carries an evidence kind it did not obtain.
    confirmed_not_done  → replay under the SAME idem (not the same action_id: attempt increments).
    indeterminate       → by idempotency class:
                            by_ref, by_readback  → replay (safe by construction)
                            by_session_id        → replay if the id is client-assigned,
                                                   else re-dispatch into a FRESH workspace
                            within_turn          → do not replay; reseed
                            unsafe               → ESCALATE to the Д6 channel, lane stays
                                                   `reconciling`, then `escalated`.  NEVER GUESS.
 4. only lanes still unresolved after step 3 go on the judge's fact sheet, with their last events,
    their worktree's `git status --porcelain`, and their resource list.  Verdicts: resume | reseed |
    release | escalate.
```

### 7.6 Config on resume

Re-resolve the six slots, diff against `config.resolved.json`, and split the diff three ways by the
key's `apply` class (§11): `live` keys take effect at once, `boundary` keys are queued for the next
dispatch, `frozen` keys are **reported into `control.ack.json.rejected[]` and do not take effect for
this run**. A frozen-key edit is never silently ignored.

---

## 8. Engine records are referenced, not duplicated — R1-06 part 3

### 8.1 The rule, in his words

[189], verbatim and ratified with «Так, правильно»:

> «якщо, наприклад, людина налаштувала, що вона користується get shit done, то оркестратору, я думаю,
> що можливо йому нічого не треба окремо записувати, а лише записувати оце **референс** на те, що веде
> get shit done … це має бути дуже простий процес … Для інших, то агент повинен уважно проаналізувати,
> як це працює, і відповідно цього діяти та записувати ці стани для відновлення … Коли він буде людину
> запитувати, він має чітко пояснити, чому він це запитує»

And [171]: «оркестратор має вести ось такий от облік, який **або буде посилатися на облік тієї тулзи**,
яка використовується … **або ж**, якщо такого немає, то він веде свій облік. Якщо … недостатньо, то
ведеться **з посиланням, плюс тої дати, якої не вистачає**.»

**The rule, mechanically:**

1. If the engine keeps a machine-readable record of the work's state, the orchestrator stores a
   **reference** to it — the path, a content digest, and the few cursor fields needed to resume — and
   **nothing else**.
2. If the engine keeps none, the orchestrator keeps its own, in `lanes/<id>/engine.ndjson`.
3. If the engine's record is insufficient, the orchestrator keeps **the reference plus only the missing
   fields**, and those fields must be named in `engine.supplement[]` in config.
4. `engine.supplement: []` (DEFAULT-PROPOSED — empty). **A non-empty value may only be set by the
   `orchestrator:config` verb, which must have researched the engine's own accounting and told the
   owner, in one sentence per field, why that field is missing and what it is for.** That is [189]'s
   research-and-explain duty made mechanical. (`corrections.md` §C records the wider restatement at
   [191] as unratified; the narrower one at [187] got his «Так, правильно» at [189] and that is the one
   this rule implements.)

**What "reference" means concretely: the orchestrator never copies the engine's narrative.** It copies
a digest and at most a dozen scalar cursor fields, and it re-reads the engine on every probe.

### 8.2 `engine_ref` — the schema

Written into `start.json` at claim time, refreshed into `lanes/<id>/engine.ndjson` on every probe:

```json
{"engine":"gsd","engine_version":"…","adapter":"engines/gsd@1",
 "project_dir":"/Users/…/<work-project>",
 "records":[
   {"kind":"state_json","path":".planning/state.json","sha256":"sha256:…","read_at":"…"},
   {"kind":"state_md","path":".planning/STATE.md","sha256":"sha256:…","read_at":"…"},
   {"kind":"roadmap","path":".planning/ROADMAP.md","sha256":"sha256:…","read_at":"…"}],
 "cursor":{"status":"verifying","current_phase":"30","current_phase_name":"…",
           "current_plan":"16","total_plans_in_phase":16,
           "stopped_at":"Completed 30-16-PLAN.md","resume_file":"None",
           "state_head":"5154f24f519f3d816f8c3191c2c1468221699e55",
           "last_date":"2026-09-19T04:54:03.499Z"},
 "supplement":{},
 "probe":{"cmd":["node","…/gsd-tools.cjs","state-snapshot","--project-dir","{{project_dir}}"],
          "exit_contract":"v1","timeout_s":20,"read_at":"…","exit_code":0}}
```

`records[].sha256` is the reference proper: it says *which version of the engine's own record this
orchestrator last saw*, which is all a resumer needs to know whether the engine moved. `cursor` holds
scalars only, and exists because the engine's file may be rewritten between the crash and the resume —
the digest tells you it changed, the cursor tells you where you were.

### 8.3 The GSD binding — every fact here VERIFIED on this machine today

GSD is the engine the owner names most often and the first the orchestrator must drive without owning.

| Fact | Evidence |
|---|---|
| `node ~/.claude/gsd-core/bin/gsd-tools.cjs state-snapshot --project-dir <p>` exits **0** and prints flat JSON with keys `current_phase, current_phase_name, total_phases, current_plan, total_plans_in_phase, status, progress_percent, last_activity, last_activity_desc, decisions, blockers, paused_at, session` | run today against the real `<work-project>` project |
| `session` is `{"last_date":"2026-09-19T04:54:03.499Z","stopped_at":"Completed 30-16-PLAN.md","resume_file":"None"}` — **the three resume anchors, already computed by GSD** | same run |
| `--pick status` prints `verifying` and exits 0, **with no trailing newline** | run today |
| `gsd-tools state --project-dir <p>` returns `{config, state_raw, state_exists, roadmap_exists, config_exists, debug_dir}`; `state_raw` is the literal text of `.planning/STATE.md`, whose frontmatter carries `gsd_state_version: "1.0"`, `current_phase`, `current_plan`, `status`, `stopped_at`, `last_updated`, `last_activity`, **`state_head` (a git SHA)** and a `progress:` block | run today |
| `--pick state_head` **exits 1** — the picker reaches top-level JSON keys only, and `state_head` lives inside `state_raw`'s frontmatter | run today |
| **`gsd-tools` prints warnings on `stderr` and clean JSON on `stdout`.** Today it emitted `gsd-tools: warning: /Users/…/.gsd/defaults.json sets model_profile, … (#3532)` on stderr while stdout began with `{` | run today, both streams isolated |
| `.planning/state.json` exists and carries `{"contract":"1.0.0","flavor":"core","milestone":null,"phases":[{"number","name","status"}…]}` | read today |
| `gsd-tools windows status --project-dir <p>` returns `{"ok":true,"ledger":{"schema_version":1,"open_count":3,…}}` | run today |
| `gsd-tools` accepts `--exit-contract=v1|v2` | `--help`, read today |

**Four implementer instructions that fall straight out of those facts:**

1. **Never merge stderr into stdout when probing GSD.** `2>&1` puts the warning line in front of the
   JSON and breaks the parse. Use `2>/dev/null`, or capture the two streams separately and journal
   stderr as a `note`.
2. **`state-snapshot` is the probe, not `state`.** It is flat, `--pick`-able, and carries the three
   resume anchors. `state` is for `state_head`, which requires parsing `state_raw`'s frontmatter — do
   it once at claim time, not every tick.
3. **Pin the exit contract.** `engine.gsd.exit_contract: v1` (DEFAULT-PROPOSED — it is the documented
   default today, and pinning it stops a GSD upgrade from silently changing what an exit code means).
4. **`--pick` output has no trailing newline.** A bash `$( )` capture is fine; a `read` loop is not.

**The oracle**, mapping GSD's own `status` onto the lane's harvest verdict:

| `state-snapshot.status` | harvest verdict | lane goes to |
|---|---|---|
| `verified`, `complete` | done | `done` |
| `executing`, `planning`, `verifying`, `discussing` | not done | stays `working` (or `needs_review` if the process has exited) |
| `paused`, `blocked` | not done | `blocked_on_human` if `blockers[]` is non-empty |
| anything else, or the probe failing | **undeterminable** | `needs_review` (`engine.on_indeterminate`, DEFAULT-PROPOSED) |

And one clause taken verbatim from `JUDGE-survival` G7, which calls it the cheapest high-value line in
the whole graft list: **`done` requires that the phase's verification artifact exists and does not
self-attribute.** Reject `verified_by: <the lane that built the phase>`. It is one string comparison,
and FIELD-NOTES §11.4 records phases that shipped with the engine reporting done and the verification
self-attributed, where *"no automated check caught it; manual review did."*

**One warning that belongs in the GSD adapter's own file** (CLAIMED via C9-A2): under a host-created
worktree, GSD reports `dispatch-isolation: harness-worktree` and runs no git of its own, and
`worktree base-check` on a real project returns `{"shouldDegrade": true, "reason":
"head-diverged-from-fork"}`. So a lane whose worktree is cut from a base GSD does not expect will
either silently serialise or fork its sub-worktrees from `origin/HEAD`. The probe prints that condition
as part of `cursor`, and preflight refuses to start a GSD lane whose `base_ref` disagrees with GSD's.

### 8.4 An engine with no records

`engine.records: []` in the adapter means the orchestrator keeps its own, in
`lanes/<id>/engine.ndjson`, one line per probe, with the same shape as `cursor`. This is his branch 2
at [171] and it needs no new mechanism.

**The completion oracle is always named out loud in `status.json`.** `completion_oracle` is one of
`engine_probe:<id>` · `process_exit` · `contradictory`. Where a process declares no verification at all
— which R1-03 [118] explicitly makes legal — the oracle is the lane process exiting, and the owner sees
which one he got. That is the honest answer to a gap he created deliberately, and the orchestrator adds
no check of its own to close it.

---

## 9. Exit codes

**One table, stable, never inferred from anything.** The range 0–13 is run outcomes; 64–78 is
`sysexits.h`, which the lock holder already uses (it exits 69, VERIFIED).

### 9.1 `orchestrator:run` and every terminal state

| Code | Terminal state | Meaning |
|---|---|---|
| **0** | `finished` | The queue drained, every lane reached a terminal state, every resource resolved |
| **3** | `finished` after `stopping` | The owner stopped it (`stop-hard` or `stop-soft`), teardown complete |
| **4** | `degraded` | Work happened; **teardown could not prove at least one resource gone**. Every unresolved resource is named |
| **5** | `blocked` | **The question-is-terminal case.** The run ended with only human-blocked work left, and `when_only_blocked: finish`. §9.3 |
| **6** | `paused` at exit | Ended paused on capacity with `capacity.on_exhausted: exit` (not the default) |
| **7** | `aborted` | Internal error during the run; teardown was attempted and its outcome recorded |
| **8** | — | A control entry was **written but unacknowledged** within `stop.ack_timeout_seconds`. Printed by the stop commands, not by `run` |
| **10** | — | The doctor relaunched a dead run (the doctor's own code; the supervisor it spawned reports its own) |
| **12** | — | The doctor found a holder alive and not ticking, and wrote a hard stop |
| **64** | `refused` | Usage error (`EX_USAGE`) |
| **65** | — | A run file is malformed beyond recovery (`EX_DATAERR`) |
| **66** | — | No such run, or the run directory is unreadable (`EX_NOINPUT`) |
| **69** | `refused` | **The lease is held by a live orchestrator** (`EX_UNAVAILABLE`). The holder's pid, start time and argv are printed. Nothing was created |
| **70** | `aborted` | Internal software error — an illegal transition, a refused evidence gate, a bug (`EX_SOFTWARE`) |
| **73** | `refused` | The run directory could not be created (`EX_CANTCREAT`) |
| **75** | — | **Fencing failure**: this process's epoch is stale and it must not act (`EX_TEMPFAIL`). It wrote nothing |
| **76** | `refused` | **Split brain**: the lock was free while the recorded holder is alive, or an identity read failed (`EX_PROTOCOL`). Fail-closed |
| **77** | `refused` | Preflight refused; every failing gate is named (`EX_NOPERM`). Also the doctor's `UNKNOWN` |
| **78** | `refused` | Configuration error — an unrecognised value, a missing required key with no default (`EX_CONFIG`) |
| **130** | `aborted` | `SIGINT` |
| **143** | `aborted` | `SIGTERM` |

### 9.2 The lane wrapper's own exit code, recorded in `result.json`

| Code | Lane state | Meaning |
|---|---|---|
| 0 | `done` | Exit code, terminal event and harvest all agree on success |
| 1 | `failed` | A named failure, with `reason` |
| 2 | `failed` | `reason: "contradictory"` — the exit code and the terminal event disagree |
| 3 | `failed` | `reason: "timeout"` — the external wall-clock timeout fired |
| **5** | **`blocked_on_human`** | **The session asked something only a person can answer, and this platform cannot be answered programmatically.** §9.3 |
| 6 | `needs_review` | The harvest was empty or undeterminable |
| 7 | `stopped` | `stopped_by: "control"` |
| 8 | — | Not terminal: the lane is reseeding and a successor carries on |
| 70 | `failed` | The wrapper itself errored |
| 75 | — | The wrapper's epoch is stale. It wrote nothing and exited |
| 130 / 143 | `stopped` | Signalled |

**These are the wrapper's codes, never the platform's.** `ADAPTER-CONTRACT` §2.4 invariant 1 is
explicit: **never branch on the platform's exit code.** Aider returns 0 on auth failure and on rate
limit; pi `--mode json` returns 0 on a provider failure; GLM returns 0 on quota exhaustion *with*
`subtype: "success"`; MiMoCode always returns 0 (CLAIMED). The adapter's `launch.sh` maps the
platform's code and the terminal normalised event onto the table above, and where the two disagree the
answer is 2, never a guess.

`acpx`'s codes map onto this table without translation — `3` → timeout, `5` → `blocked_on_human`,
`130` → interrupted — which is why `ADOPTION-VERDICT` §5's recommendation can be taken as one legal
value of `launch.sh` rather than as a structural dependency.

### 9.3 The question-is-terminal case, spelled out

This is the case the platform research surfaced and the one the brief singles out.

**The fact.** `ADAPTER-CONTRACT` §3 G (VERIFIED in those spikes, CLAIMED here): a native typed channel
for answering a session's *own* question exists on Copilot (`choices`), MiMoCode (a *question* channel
distinct from *permission*), Qwen, Droid, Kimi, Cursor ACP, pi and OpenCode. Where it is absent — and
it is absent on **Claude Code in `--bg`**, on DeepSeek's SDK lane, and on Gemini CLI headless — *"the
only safe unattended posture is prevent the question"*, and Claude Code's `defer` is print-mode only.
So on the lane the owner is most likely to run tonight, a question the session asks **cannot be
answered by anything**.

**The consequence, stated as state.** A question on such a platform is not a pause the orchestrator can
sit through. It is the end of the attempt:

1. The wrapper observes `waiting_on_human` in `events.norm.ndjson`, or the platform exits 5.
2. The wrapper writes `result.json` with `outcome: "blocked"`, `reason: "question_unanswerable"`, the
   question text (redacted per §4.7) and the offered options if the platform reported any, and exits
   **5**.
3. The lane goes to the terminal state `blocked_on_human`.
4. The **task** goes to `blocked`, not to `failed`, and a pending-question record is written to the Д6
   channel with the four claudexor terminals available to it: `answered | timeout | run_terminal |
   interrupted`, and the delivery of an answer reporting one of `delivered | not_found |
   already_resolved | rejected`.
5. `failures.count_blocked_on_human: false` (DEFAULT-PROPOSED) — this charges **nothing** against Д5's
   three-failure budget [442]. A budget that drains into a state no retry can change is a budget that
   ends a night for nothing.
6. The queue keeps moving. Д6 [449] is explicit that independent tasks continue.
7. When an answer arrives in the channel, the task returns to `ready` and **a new lane** is claimed for
   it — a new attempt, a new `session_id`, a new `attempt` number, with the answer carried in the
   launch prompt.
8. If the run reaches the drain condition with tasks still `blocked`:
   `when_only_blocked: wait` (his own recommendation [455], the default) keeps the run alive with
   `wait_max_minutes: 0` (forever, also his), and fires **one** notification on entering that state —
   because a run behaving exactly as configured is otherwise indistinguishable from a dead one.
   `when_only_blocked: finish` takes the terminal `blocked` state and **exit code 5**.

**Where a platform *can* be answered**, `questions.answer: when_native` (DEFAULT-PROPOSED) lets the
orchestrator answer within its configured authority (R1-11 [324]/[325]), and the answer is recorded in
`answers.ndjson` with the offered option id it echoed — **never free text**, because a free-text answer
into a permission dialog answers a decision on the owner's behalf, which Untrivial AO's `sessionguard`
exists specifically to refuse (`LANDSCAPE` §4, VERIFIED). Every declined question is logged; a silent
decline is the documented killer on Droid.

---

## 10. Worked examples

### 10.1 A clean lane, from claim to done

```
seq   kind        what
1041  transition  task    t-118  ready → claimed        cause=task.claimed        epoch=4
1042  intent      board.transition  action_id=…:4:L03-t-118:board.transition:1  expect=[board_readback]
1043  result      for=…:board.transition:1  outcome=ok  evidence=[board_readback status="in progress"]
1044  transition  lane    L03-t-118  "" → claimed       cause=lane.claimed
      (mkdir lanes/L03-t-118 already succeeded; lanes/L03-t-118/epoch = 4 written)
1045  transition  lane    L03-t-118  claimed → preparing cause=start.written
      (start.json fsynced, lane dir fsynced — BEFORE any process exists)
      resources.ndjson  r14 creating  git_worktree /Users/…/.worktrees/L03-t-118
      resources.ndjson  r14 created
1046  transition  lane    L03-t-118  preparing → launching cause=prepare.ok
1047  intent      lane.dispatch  action_id=…:4:L03-t-118:lane.dispatch:1  expect=[transcript_event,process_exit]
1048  transition  session 0b6c…  "" → named               cause=session.named
1049  transition  lane    L03-t-118  launching → working   cause=launch.ok
1050  transition  session 0b6c…  named → live             cause=session.first_turn
1061  observation lane.context {pct:41.2} basis=raw_window prov=measured age_s=22
1074  observation engine.cursor {status:"executing",current_phase:"30",current_plan:"14"}
…
1310  transition  lane    L03-t-118  working → harvesting  cause=exit.observed  detail={exit_code:0,terminal_event:"turn_completed"}
      (engine probe: status=verified, verification artifact present, not self-attributed)
1311  result      for=…:lane.dispatch:1  outcome=ok  evidence=[process_exit{pid:41977,code:0}]
1312  transition  lane    L03-t-118  harvesting → done     cause=harvest.done
      (result.json fsynced, lane dir fsynced, then mv → lanes.done/L03-t-118)
      (the mv is not a transition; the directory move is the commit point, nothing more)
1313  intent      board.transition  …:4:L03-t-118:board.transition:2  ready→done
1314  result      outcome=ok  evidence=[board_readback status="done"]
1315  transition  task    t-118  in_progress → done        cause=board.readback_ok
```

### 10.2 The supervisor dies mid-merge; the doctor takes over

Supervisor A, epoch 3, writes:

```
 902  intent  git.merge  action_id=run:3:L07:git.merge:1  idem=sha256:9f2c…
                         args={from:"gsd/phase-23", into:"main"}  expect=[git_ref]
```

…and is killed before writing a result. The merge may or may not have happened.

Doctor, two hours later:

```
1. machine.lock acquired
2. orch-lock.py on the project lock → ACQUIRED  (so A is gone)
3. lease/owner.json: pid 40311, lstart "Sat Sep 19 22:41:00 2026"
   kill -0 40311 → fails                        → not split brain
4. last journal record's boot == current boot, no machine.wake in the last 120s → not UNKNOWN
5. DEAD.  epoch 3 → 4, owner.json rewritten, exec the supervisor in recover mode
   HOLDING THE LOCK (the fd is inherited across execvp)
```

Supervisor B, epoch 4:

```
 903  transition  run  running → running  cause=lease.taken_over   ← recorded, not a state change
      (fold: open_actions = {run:3:L07:git.merge:1})
      ops.json["git.merge"].reconcile = read_ref
      probe: git rev-parse refs/heads/main → fc01ef2…  ≠ args.before 93fdf65…
             git merge-base --is-ancestor <head> origin/main → 0
      → confirmed_done
 904  result  for=run:3:L07:git.merge:1  outcome=ok  actor=reconciler
              evidence=[git_ref{ref:"refs/heads/main",before:"93fdf65…",after:"fc01ef2…",
                                read_back_at:"2026-09-20T01:44:02Z"}]
```

**Note what did not happen.** The reconciler did not read a transcript, did not call a model, and did
not trust the journal's silence. It read a ref. And had the probe returned `confirmed_not_done`, the
replay would have used the **same `idem`** with `attempt: 2`, so a third crash still converges.

### 10.3 The fence catching a stale wrapper

Lane `L07` was launched by supervisor A at epoch 3. The wrapper survived A's death and is still
running when B takes over at epoch 4.

```
B's orphan scan:  lanes/L07/ has start.json, no result.json
                  kill -0 41977 → ok ; ps -o lstart= → matches ; argv sha → matches
                  → ADOPTABLE.  B writes lanes/L07/epoch = 4.
 910  transition  lane L07  working → working  cause=lane.adopted   ← recorded via the detail field
```

Ninety seconds later the wrapper finishes and goes to write `result.json`. Before writing it re-reads
`lanes/L07/epoch` → `4`, updates its in-memory epoch, and writes `result.json` with `epoch: 4`. Normal.

Now the bad variant. Suppose B had instead decided the lane was dead (the pid check failed because the
process was in an uninterruptible state) and killed it, and the wrapper thawed afterwards and wrote:

```
lanes/L07/result.json  {"outcome":"ok","epoch":3, …}
```

B's reap step reads it, compares `3` against `lanes/L07/epoch` = `4`, discards it, and appends:

```
 947  note  text="fence.stale_result lane=L07 result_epoch=3 lane_epoch=4; result.json retained
                  as result.stale.json and not folded"
 948  transition  lane L07  working → orphaned  cause=orphan.detected
```

The stale file is **renamed, not deleted** (`result.stale.json`), because it is evidence, and the lane
goes through reconciliation like any other orphan.

### 10.4 A question on a platform that cannot be answered

```
1180  observation  lane.event  {type:"waiting_on_human", prompt_sha256:"sha256:…"}
      caps.sh for this lane: answer=none      → questions.answer=when_native does not apply
1181  transition  lane  L05-t-131  working → blocked_on_human  cause=event.waiting_on_human
      wrapper writes result.json {outcome:"blocked", reason:"question_unanswerable",
                                  question:"«‹trigger:…›» …", options:[]}  and exits 5
1182  transition  task  t-131  in_progress → blocked           cause=question.raised
      → a pending-question record is posted to questions.channel, carrying lane, task,
        attempt, requested_at, timeout_at=null (questions.pending_timeout_minutes: 0)
1183  note  text="queue continues: 4 ready tasks remain"
…three hours later…
2410  observation  questions.answer_observed  {task:"t-131", delivery:"delivered"}
2411  transition  task  t-131  blocked → ready                 cause=question.answered
2412  transition  lane  L09-t-131  "" → claimed                cause=lane.claimed
      (a NEW lane, attempt 2, a new session id, the answer carried in the launch prompt)
```

Had the run drained before the answer arrived, with `when_only_blocked: wait` it would have stayed in
`running` with an empty dispatch and fired one notification. With `finish` it would have reached the
terminal `blocked` and exited **5**.

---

## 11. Every default this spec proposes

None of these is a decision. `scope` is the narrowest config level at which the key may be set;
`apply` is what happens to a mid-run change (`live` = next tick · `boundary` = next dispatch ·
`frozen` = not for this run, reported in `control.ack.json.rejected[]`).

**Nothing outside this table may invent a default at run time.** A key read at run time that is not in
this table and has no resolved value is a configuration error, exit 78.

| Key | DEFAULT-PROPOSED | scope | apply | Protects against |
|---|---|---|---|---|
| `tick.interval_seconds` | `60` | run | live | A tick cheap enough to run all night with no model in it |
| `tick.control_seconds` | `5` | run | live | A stop the owner typed sitting unread for a minute. Д12 only promises "next tick"; this over-delivers |
| `lease.heartbeat_seconds` | `5` | user | live | A status display reading a heartbeat older than the thing it describes |
| `lease.scope` | `project` | user | frozen | Two runs on one board, both claiming, both merging (C6-A12) |
| `journal.fsync` | `transitions` | user | live | Losing a state change to a killed process, without paying fsync on every reading |
| `journal.fullfsync` | `false` | user | frozen | Paying ~10ms per record for power-loss durability this system does not need |
| `journal.record_max_bytes` | `8192` | user | frozen | One pathological line making the journal unparseable |
| `journal.observation_sampling` | `on_change` | run | live | A 34-hour journal of identical readings |
| `observation.max_age_s` | `900` | run | live | "Nothing changed for four hours" being a silence instead of a record |
| `journal.on_illegal_transition` | `refuse_and_abort` | user | frozen | A state machine whose diagram is fiction |
| `triggers.redact` | `true` | user | live | A detector matching the orchestrator's own prose — the 85-minute-loop class |
| `fence.on_stale_record` | `discard_and_record` | user | frozen | A resurrected process changing the folded state |
| `fence.on_stale_effect` | `escalate` | user | live | Counting a stale epoch's side effect as this epoch's result |
| `sleep.gap_seconds` | `60` | user | live | The exact way the previous run ended (FIELD-NOTES §10.1) |
| `sleep.grace_seconds` | `120` | user | live | Every liveness verdict going stale at the same instant on wake |
| `doctor.enabled` | `false` | user | boundary | Off by default: it needs a separate account, if the user configures one |
| `doctor.interval_hours` | `2` | user | boundary | A 4-hour window swallows an 85-minute loop whole (C6-A10) |
| `doctor.on_unknown` | `notify_and_hold` | user | live | Two orchestrators, which he called «не окей» absolutely [300] |
| `doctor.journal_stall_action` | `stop_hard_and_notify` | user | live | A holder alive and not ticking, which the lock alone cannot see |
| `doctor.progress_stall_action` | `notify_only` | user | live | Killing a slow run. Slow and stuck are indistinguishable from outside |
| `recovery.sources` | `[journal, engine_records, transcripts]` | project | boundary | Recovering from a record the crash destroyed |
| `recovery.read_transcripts` | `never_for_state` | user | frozen | A recovery that needs the pipe a dead supervisor was holding |
| `recovery.probe_before_judge` | `true` | run | live | A model call per orphan on every restart, when restarts are expected [300] |
| `orphan.dispatch_window_seconds` | `45` | project | frozen | A server-minted session that exists and cannot be named |
| `orphan.on_unsafe` | `escalate` | user | live | A replayed `pr.create` producing a second PR nothing finds suspicious |
| `claim.on_dir_without_start` | `release` | user | frozen | A claim held on a launch that never happened |
| `harvest_evidence` | `observed` | project | boundary | A lane that exits 0 having produced nothing taking the done path |
| `engine.on_indeterminate` | `needs_review` | project | boundary | Advancing an empty issue into a person's queue (Sortie ADR 0020) |
| `engine.supplement` | `[]` | project | boundary | The orchestrator duplicating records the engine already keeps [189] |
| `engine.gsd.exit_contract` | `v1` | project | frozen | A GSD upgrade silently changing what an exit code means |
| `engine.gsd.probe` | `state-snapshot`, stderr discarded, `timeout_s: 20` | project | boundary | A warning line on stdout breaking the parse (VERIFIED today) |
| `stop.ack_timeout_seconds` | `90` | user | live | An owner believing a stop was applied when it was not |
| `stop.hard_grace_seconds` | `30` | run | live | A hard stop that never completes |
| `when_only_blocked` | `wait` | run | live | His own recommendation [455] |
| `wait_max_minutes` | `0` (forever) | run | live | Also his [455] |
| `questions.answer` | `when_native` | project | boundary | Answering by keystroke with no acknowledgement |
| `questions.pending_timeout_minutes` | `0` (never) | project | live | A question expiring while he sleeps |
| `failures.repeat_threshold` | `3` | project | boundary | His number, exactly [442] |
| `failures.count_blocked_on_human` | `false` | project | boundary | A retry budget draining into a state no retry can change |
| `end.intake_grace_seconds` | `300` | run | live | Exiting thirty seconds before his 02:59 ticket lands (Д2) |
| `run.mode` | `controlled` | run | frozen | He named three values [075] and no default; `ask` has nobody to ask at 04:00 |
| `run.mode_on_takeover` | `controlled` | user | live | A 04:00 relaunch that asks rather than guesses |
| `capacity.on_exhausted` | `pause` | run | live | Ending a night that a reset would have continued [007] |
| `board.writeback` | `true` (board) / `false` (local registry) | project | boundary | The tool's own log inside a ticket body firing its own change detector (C3-A1) |
| `delivery.assert_landed` | `true` | project | boundary | A merge that prints `Already up to date` and moves nothing (FIELD-NOTES §4.1) |

---

## 12. Tensions — decisions of his this spec implements while something stays uncomfortable

None of these is quietly substituted. Each is designed for.

1. **Д12 is the spine of the control plane and it is openly unratified.** The interviewer recorded it
   at [525]: «Доповнення до Д12 отримано; підтвердження залишається відкритим». Every `control` record,
   every `control.ack.json` field and every stop exit code in this document rests on it. It is the one
   item `corrections.md` §C marks as correctly labelled — and twenty-two others in that table are
   marked unratified and *not* labelled, including the hard/soft vocabulary this spec's `apply` field
   inherits.
2. **His three-way stop becomes two states plus a reason.** [171] names hard, soft, and «щось проміжне
   … записати теперішній стан, можливо зберегти сесію, і зупинити її повністю, аби потім можна було її
   продовжити», which he left open («Не знаю»). The intermediate is `paused` + a per-lane reseed here.
   That is the minimum shape that makes the other two implementable; it is not his decision.
3. **The lock keyed on the project refuses two runs on one repository.** This is his absolute read
   literally. The cost is that he cannot run two milestones of one repository concurrently.
4. **The evidence gate checks the orchestrator's own operations, never the work.** R1-13 [344] gives
   verification to the process — «не роби обмеження те, що вся робота потім буде мати тести». The
   distinction between *the engine says the ticket is done* and *the orchestrator says its own step
   ran* is one I am confident is right and that was **never put to him**. §14.
5. **A question is terminal for the attempt and durable for the task.** He spoke to the queue (Д6
   [449]) and not to the attempt. The field is split, with one implementation on each side, and this is
   a synthesis, not a decision he made.
6. **`mono`, `boot`, the fold's fence and `transitions.json` are inventions.** Nothing he said requires
   or forbids any of them. They exist because of what the record shows failed.
7. **Board write-back is restored against `ARCH-minimal`'s removal of it.** [149] is ratified and
   minimal gives it up; `JUDGE-fidelity` G7 is right that minimal already ships the fix for the loop it
   was avoiding. The restoration is faithful to him and is a deviation from the base design.
8. **The board is still not the working surface he described.** [149] pictures the board as the
   orchestrator's own scratch space. Here it is a mirror with readback evidence, the local claim is
   authoritative, and a board write failure degrades `board_sync` without changing execution.
9. **The run scope is not a config level.** He requires three scopes including *this run* [331]/[075];
   his own marketplace states three levels are the whole set. §2.4's reconciliation keeps both rules and
   costs a reader one place to look.

---

## 13. Where a decision is not implementable exactly as stated

**13.1 R1-06.2 — «в нас в реєстрі має записуватись кожен стан».**
*Impossible clause:* **every** state. On the four platforms where the server mints the session id
(Codex, Kimi, Amp, MiMoCode), there is a window between launch and the first record in which a session
exists and provably cannot be named; on Gemini CLI a session with no completed model turn is **deleted
and unresumable**, so an early failure leaves no recovery point at all (CLAIMED,
`ADAPTER-CONTRACT` §3 B). *Cost of keeping it:* restrict lanes to the five platforms where the client
names the id before launch (Claude Code, pi, Droid, OpenCode, Qwen), or accept that on the others the
first 45 seconds recover by **re-dispatch into a fresh workspace** rather than by resume. This spec
ships the second (`orphan.dispatch_window_seconds`) and raises the first as a question.

**13.2 R1-10 — «не може бути такого, що … одночасно два».**
*Impossible clause:* nothing, in the normal case — `flock` makes it structural, with no timeout. But
the guarantee is on a **path**, and a path can be replaced: delete `locks/<project_key>.lock` while it
is held and the next acquirer locks a fresh inode. §5.4 step 6 narrows this to a detectable split brain
that fails closed, and cannot eliminate it. *Cost of closing it completely:* a second identity that is
not a path — a system-wide registry keyed on the git common directory's device and inode, checked on
every acquisition — which adds a second failure mode (a moved or restored repository reads as a
different project) in exchange for closing a hole that requires someone to delete a lock file by hand.
Not taken; stated.

**13.3 Д12 — `stop-hard` «прямо вже».**
*Impossible clause:* *immediately*, mid-turn, on some platforms. On Gemini CLI headless a message into
a live session cannot be delivered at all, and in ACP mode it **aborts the turn** rather than being
added to it; on DeepSeek's ACP lane an instruction mid-prompt is impossible (CLAIMED,
`ADAPTER-CONTRACT` §3 G). *Cost of keeping it:* on those platforms `stop-hard` degrades to **killing
the process**, which the state machine records as `stopped` with `hard_degraded: true` and which
`status.json` prints. The work in flight is lost rather than wound down. The alternative — applying
stops only at task boundaries there — makes `stop-hard` and `stop-soft` indistinguishable on those
lanes.

**13.4 R1-07 — a *hard* account change that acts now.**
*Impossible clause:* *in place*. Changing a live session's account is impossible on **all fifteen**
platforms surveyed (CLAIMED, `ADAPTER-CONTRACT` §3 F). *Cost of keeping it:* stop the lane, relaunch on
the new account, and re-seed the context — paying for that context a second time, per affected lane.
In state terms it is `working → stopped → (new lane) claimed`, and it is priced in the journal as a
`cost.wall_ms` and a fresh session in the lineage.

---

## 14. Needs the owner — round 2, in plain Ukrainian

Everything below is something this spec had to invent because he never decided it. Each is shipped with
a default and needs a yes or a correction. Ready to put to him as written.

1. **Питання, на яке нікому відповісти.** На платформах, де сесія питає, а програмно відповісти
   неможливо (Claude Code у фоновому режимі, DeepSeek, Gemini), я роблю так: **спроба закінчується**,
   тікет лишається в черзі й чекає твоєї відповіді, черга рухається далі, а коли відповідь приходить —
   стартує **нова** сесія з нуля по цьому тікету. Це правильно, чи ти хочеш, щоб сесія стояла живою й
   чекала (і тримала ліміт та контекст)?

2. **Окремий код виходу для «лишилось тільки те, що чекає на тебе».** Я пропоную, щоб ран, який
   доїхав до кінця й має тільки заблоковані людиною тікети, за замовчуванням **лишався чекати**
   (як ти й рекомендував), але щоб існував і варіант «завершитись» з окремим кодом виходу 5. Такий код
   тобі потрібен, чи достатньо просто повідомлення?

3. **Чи «завершено» — це те саме, що «прибрано»?** Якщо вся робота зроблена, але щось із того, що ран
   підняв (докер-проєкт, worktree, сесія), не вдалось довести, що воно зупинене, — я даю окремий
   фінальний стан `degraded` і код виходу 4, а не «успіх». Це те, чого ти хочеш, чи для тебе «робота
   зроблена» = успіх, а недоприбране — це просто рядок у звіті?

4. **Наскільки параноїдально писати на диск.** Я пропоную гарантовано скидати на диск **тільки зміни
   станів** (і те, що треба прибрати), а не кожне вимірювання. Це швидко і переживає вбитий процес.
   Альтернатива — писати геть усе, повільніше. Який варіант?

5. **Стоп: 5 секунд чи наступний тік.** Ти сказав «на наступному тіку». Тік — 60 секунд. Я пропоную
   окремий дешевий підтік на 5 секунд, який тільки перевіряє файл зі стоп-командою, щоб `stop-hard`
   спрацьовував за 5 секунд, а не за хвилину. Лишаємо 5, чи ти хочеш саме 60?

6. **Підтвердження, що стоп дійшов.** Зараз команда `stop` не просто пише у файл, а **чекає**, поки
   оркестратор підтвердить, що прочитав і застосував (до 90 секунд), і повертає інший код виходу,
   якщо підтвердження не прийшло. Це те, що тобі треба о 3-й ночі, чи достатньо «записано у файл»?

7. **Що робити з лінією, яка вийшла успішно, але нічого не зробила.** Я ставлю таку лінію не в
   «готово», а в «на перевірку», і тікет не їде далі. Це правильна сторона обережності, чи тобі
   важливіше, щоб черга рухалась?

8. **Чи має оркестратор перевіряти сам себе.** Ти сказав: перевірка роботи — це справа процесу
   (GSD), і оркестратор не додає своїх перевірок. Але є різниця між «чи зроблено таск» і «чи
   відбулась операція, яку зробив сам оркестратор» — наприклад, мердж, який написав «Already up to
   date» і нічого не перемістив. Я дозволяю оркестратору перевіряти **тільки власні** операції.
   Підтверджуєш цю межу?

9. **Мертвий ран до ранку.** Якщо доктор не може впевнено сказати, живий оркестратор чи ні (наприклад
   одразу після сну Mac), він **нічого не робить** і чекає наступного разу — бо «два оркестратори» ти
   назвав абсолютно недопустимим. Ціна: ран може простояти мертвим до ранку. Приймаєш цю ціну?

10. **Чи може доктор вбити живий, але завислий оркестратор.** Якщо оркестратор живий, тримає замок, але
    нічого не пише в журнал — я пропоную, щоб доктор писав йому жорсткий стоп і повідомляв тебе. А
    якщо він пише в журнал, але робота не рухається — **тільки повідомлення, ніколи не вбивати**.
    Згоден із цим розділенням?

11. **Режим рану після автоматичного перезапуску о 4-й ночі.** Ти назвав три режими, але не сказав,
    який стає дефолтним і що робити, коли ран перезапустився сам і питати нема кого. Я ставлю
    `controlled`. Правильно?

12. **Два рани на одному репозиторії.** Замок стоїть на **проєкті**, а не на рані, тому два рани на
    одному репозиторії неможливі взагалі. Це саме те, що ти мав на увазі, чи ти хочеш мати змогу
    гнати два мілстоуни одного репозиторію паралельно?

13. **Скільки записувати за GSD.** Я перевірив: GSD сам віддає фазу, план, статус, `stopped_at` і
    `resume_file` однією командою. Тому оркестратор зберігає **тільки посилання** на це плюс контрольну
    суму — і нічого свого. Тобі цього достатньо для «відновити навіть руками», чи є щось конкретне,
    чого тобі бракує і що треба дописувати окремо?

14. **Текст питань і відповідей у журналі.** Питання сесії й твоя відповідь — записувати повним
    текстом у журнал рану (зручно читати, але це той самий текст, на який реагують детектори), чи
    тільки посилання на канал і контрольну суму?

15. **Залишки попереднього рану.** Якщо попередній ран помер і лишив по собі докер-томи й worktree,
    цей ран **не чіпає їх** (за твоїм правилом «прибирати тільки те, що сам підняв») — він просто
    показує список і точні команди тобі. Так і лишаємо, чи дозволяєш прибирати те, що явно позначене
    цим інструментом і чий ран точно мертвий?

---

## 15. What this spec does not cover, and where the weakest point is

**Not covered here, by scope:** capacity reading and thresholds, context measurement and compaction,
the judge's fact sheet and prompt, the adapter interface, preflight's full gate list, notification
channels, and the delivery/merge path. Each is another spec; this one owns only state, the journal,
the lease, resume and exit codes.

**The weakest point.** Every guarantee in §4 and §7 depends on the appender being the only route from
an event to a state, and the appender is bash. A contributor who writes one `echo >> journal.ndjson`
outside it bypasses the epoch check, the evidence gate and the transition table in a single line, and
nothing at run time would notice. The defence is a lint rule that fails the build on any write to
`journal.ndjson`, `resources.ndjson` or `lease/*` that is not through the four named helper functions —
which is a rule about the repository, not about the running system, and is therefore the softest thing
in this document. It belongs in the test harness on day one, alongside the three that are already
named: no `pkill`, no `killall`, no `docker compose down` without an explicit `-p`, and no teardown
argument sourced from an environment variable.
