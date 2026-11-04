# BUILD-PLAN — the orchestrator, decided

**Date:** 2026-09-19. **Status:** the document the owner reads before he decides anything, and the one
an implementer starts from afterwards.

**Authority.** `round-1/ANALYSIS-01.md` is the source of truth for what the owner wants; where it and
`round-1/TRANSCRIPT-01.md` differ, the transcript wins. Item codes (`R1-06`, `Д7`) and row anchors
(`[171]`) are theirs.

**Inputs read in full for this document:** `ARCH-minimal`, `ARCH-reliability`, `ARCH-adapters`,
`ARCH-operability`; `JUDGE-cost`, `JUDGE-fidelity`, `JUDGE-survival`; `SPEC-adapters`, `SPEC-cli`,
`SPEC-config`, `SPEC-engine`, `SPEC-repo`, `SPEC-safety`, `SPEC-state`, `SPEC-work`; `RED-acpx`,
`RED-fidelity`, `RED-night-one`; `platforms/ADAPTER-CONTRACT.md`; `adoption/ADOPTION-VERDICT.md`;
`LANDSCAPE.md`; `eval/ground-failure-corpus.md`; `plugins/harness/docs/FIELD-NOTES.md`;
`<baseline-marketplace>/docs/config-levels.md` and `requirements/OWNER-DECISIONS.md`.
**`research/eval/EVAL-PLAN.md` does not exist.** The eval scenarios in §4 are drawn from
`eval/ground-failure-corpus.md`'s 71 numbered failures and 8 positive controls instead, and §6 records
the gap.

**Evidence tags.** **VERIFIED** — read in a primary artefact or executed on this machine on 2026-09-19
by a document named above. **CLAIMED** — a document asserts it and nothing was run behind it.
**INFERRED** — reasoning from the above. Every mechanism in this plan is **CLAIMED** by construction:
nothing here has been built. What is VERIFIED is the failure record it is written against and the
platform facts it rests on.

**Two rules this document obeys.** Everything the owner made configurable stays configurable, and every
configurable thing carries a stated default, because he stated almost none — §3 is the real output of
this workflow. And where a decision of his is uncomfortable, it is designed for and the discomfort is
recorded; nothing is quietly replaced.

---

## 1. The architecture in one page

### 1.1 The four ideas that carry it

**One.** *Bookkeeping is bash; judgement is one model call.* Every requirement in round 1 is either
deterministic bookkeeping — claim a ticket, read a number, notice a file changed, count to three, stop
what you started — or a judgement the owner deliberately refused to write a rule for («Агент сам
повинен це вирішувати» [231]). A single bash supervisor owns all state and does all bookkeeping. A
model is invoked, at most once per tick, only when a tick has something no configured rule answers, and
it is handed a rendered fact sheet rather than a session. The supervisor never judges; the judge never
holds state. That one line deletes the context-watcher session, the validator session, the
question session, the typing-into-terminals machinery, the heartbeat file, the nudge, and the entire
problem of compacting the orchestrator — because the orchestrator as a long-lived model session no
longer exists.

**Two.** *Liveness is a process, not a screen.* Every unit of work is a real child process the
supervisor started, whose pid and pid start-time are on disk before it launches. Nothing screen-scrapes,
nothing types into a running session, nothing matches a process by pattern. Six FIELD-NOTES failure
records are retired by deleting the capability that produced them (VERIFIED: §1.3–§1.6, §2.2, §11.1,
§11.8, §12.1), and §7 states what that costs.

**Three.** *Nothing claims success without evidence, and "unknown" is a third verdict.* `start` is
written before the act and `result` last, so a crash leaves a detectable orphan rather than a false
claim of completion. A mutating operation cannot be journalled `ok` without an evidence object declared
for it in a data file. A capacity reading that cannot be parsed is `Unknown`, which is a refusal to
schedule, never a zero. A lane that exits 0 having produced nothing goes to review, not to done. This is
the antidote to the largest failure class on record — *reported success and did nothing* — and it stays
on the right side of R1-13 because **it verifies the orchestrator's own operations and never the work**.

**Four.** *Refuse at 22:00 rather than degrade at 03:00.* Everything the run depends on — which account
a spawn will actually use, that two roles are not silently one quota pool, that the notification channel
delivers a real message, that the board accepts a write, that the red-line file is readable, that the
worktree's environment exists, that the adapter does not claim a capability it cannot perform — is
proven before the supervisor forks, with zero model tokens, and each failure refuses by name. What
cannot be refused is *degraded on the record*: `plan.json` names which of his numbered items stopped
holding tonight, on which lane, from what to what.

### 1.2 The component map

```
                    orchestrator:run  ──►  orc-lock.py (fcntl.flock, keyed on the PROJECT)
                                              │  held ⇒ exit 69, naming the holder
                                              ▼
  ┌───────────────────────────── orc-run.sh — THE SUPERVISOR (the only resident process) ────────┐
  │  one tick, in order, cheap first:                                                             │
  │   1 control   stat control.json → apply {verb,scope,apply} entries, exactly once by id        │
  │   2 config    stat the six snf slots + config.run.json → re-resolve, split live/boundary/frozen│
  │   3 reap      per lane: kill -0 pid AND ps -o lstart= matches start.json; result.json present? │
  │   4 observe   event-file growth · context.used_pct · Δpct/h · top repeated tool call · probe   │
  │   5 rules     quota threshold · context threshold · 3 identical failures · answer arrived      │
  │   6 JUDGE     iff something is still open: ONE fact sheet, ONE model call, under a trip        │
  │               watermark and a wake budget.  Skipped on most ticks. Zero tokens otherwise.      │
  │   7 dispatch  scheduler: order → admit → claim (mkdir) → launch                                │
  │   8 write     append journal.ndjson (at + mono) · rewrite status.json · write control.ack.json │
  │   9 terminal  no live lanes AND no claimable ticket AND (no human-blocked OR finish) → drain   │
  └───────────────────────────────────────────────────────────────────────────────────────────────┘
        │ spawns (a model never spawns anything)          │ reads                    │ writes
        ▼                                                 ▼                          ▼
   orc-lane.sh × N                              adapters/<platform>/            ~/.orchestrator/runs/<id>/
   one process per claimed ticket                caps.sh preflight.sh            control.json  control.applied.ndjson
   prepares worktree, execs the platform         launch.sh normalize.sh          control.ack.json  status.json
   in the foreground, stdin </dev/null,          capacity.sh compact.sh          journal.ndjson  decisions.ndjson
   tees the structured stream, writes                                            ledger.jsonl  plan.json
   result.json LAST, tears down its own          probe/<engine>.sh               lanes/<id>/  lanes.done/<id>/
   ledger rows                                   one line, zero tokens           trips/  capacity/  report.md

   orc-status.sh   pure bash + jq over status.json — ZERO model turns, the only thing he reads
   orc-ctl.sh      writes one entry into control.json and polls control.ack.json for the answer
   orc-doctor.sh   launchd, another account: try the lock · journal not growing · work not moving
   orc-preflight.sh  every proof, zero tokens, refuses by name
```

In the project, and read from the **main** checkout only (`git rev-parse --git-common-dir`, VERIFIED on
git 2.33.0): `.orchestrator/RULES.md` (R1-15), `.orchestrator/tickets/*.md` (the local registry), and
the Д6 questions channel wherever he puts it. **Nothing else of the run lives in the repository**, because
Д4 makes every task its own worktree and anything in the tree forks per lane — FIELD-NOTES §12.5 records
`QUESTIONS.md` forking into a worktree copy with a real owner-facing question invisible for an hour
(VERIFIED).

### 1.3 In a paragraph

The orchestrator is a configuration and control plane over other people's workflows and other vendors'
agents, not a workflow of its own — that is the headline of round 1 and it is the shape of the build.
A 60-second bash tick loop holds an OS lock on the project, reads one control file the owner writes
with three commands, resolves his six snf config slots plus a per-invocation run scope, claims tickets
with `mkdir`, and launches one wrapper process per ticket that execs whatever platform command the
configured process names. It drives GSD without owning it by asking GSD's own `gsd-tools` for a one-line
state (VERIFIED working today against a real project at zero token cost), and it drives a custom process
by running an ordered array of commands. It reads quota per account through a per-platform script that
returns a sum type, and context from the platform's own structured event stream. It stops what it
started by walking a ledger it wrote as it created each resource, and asserts each teardown by
observation. And once per tick, if and only if a rule the owner configured does not answer what just
happened, it renders about forty lines of facts with provenance and asks one model one question, records
the verdict with the sha1 of the facts it saw, and does nothing on an unparseable answer. It prints
nothing all night; `orchestrator status` is a bash script.

### 1.4 Where this came from, and the one thing the judges disagreed about

Four architectures were written and judged on three axes. `ARCH-minimal` won cost 9/10 and fidelity
8/10 and came **last** on survival at 5/10; `ARCH-operability` won survival 8/10 and came last on
fidelity. The disagreement is real and it is not a tie: minimal is blind to the two failures that cost
whole nights (the alive-but-useless lane, and the dead orchestrator nobody revived) **on a default
install**, and both blind spots are closed by grafts of a few lines each. Two of three judges ranked
minimal first; all three produced converging graft lists; `SPEC-repo` already encodes minimal-plus-grafts
as a twelve-step build. **This plan is `ARCH-minimal` plus roughly thirty-five grafts, and the grafts
that matter most come from the design that lost on cost.** That is the honest reading: the cheapest
build is not the cheapest system (`JUDGE-cost` §9.4, its own words), and three of reliability's
mechanisms — evidence-gated results, the sleep fence, the non-self-attribution clause — are bought here
at about a tenth of reliability's price.

---

## 2. The decision record

Thirty-three decisions. Each is (context · decision · consequences · alternatives rejected), with the owner's
words where his words settled it. Where a decision resolves a contradiction that `RED-night-one` found
between the eight specs, the finding number is cited.

### Part A — the shape

**ADR-01 · The supervisor is bash and the model is a one-shot judge.**
*Context.* Every requirement splits into bookkeeping or judgement, and the previous generation failed
hardest at bookkeeping done by a model: 26 refusal events written into an audit log that never occurred,
a merge that printed `Already up to date`, a status command that spends a model turn to read a JSON file
bash already wrote (all VERIFIED, FIELD-NOTES §12.7, §4.1; `commands/status.md`). He asked four separate
times for the least machinery that works — «тут нічого надприроднього не потрібно вигадувати» [171],
«це має бути дуже простий процес» [189], «це має бути надійна річ, дуже проста» [300], «дуже якийсь
простий та надійний варіант» [370]. Only the last reached `ANALYSIS-01`.
*Decision.* One bash supervisor owns all state and does all bookkeeping. A model is invoked at most once
per tick, on a rendered fact sheet, only when nothing configured answers. The supervisor never judges,
the judge never holds state.
*Consequences.* Zero tokens on a tick where nothing is open, which is most ticks. R1-08's hardest case —
compacting the orchestrator — does not arise, because there is no orchestrator context window.
**Tension:** he pictured three windows [036], [195], [204]; he cannot open the orchestrator's window and
read what it is thinking. He reads `status.json`, `journal.ndjson` and `decisions.ndjson`.
*Rejected.* A resident orchestrator session (ARCH-operability's `brain`): it reintroduces the compaction
deadlock against the single-orchestrator invariant, and `C5-A3/A5` show that deadlock is unresolvable.

**ADR-02 · `judge.mode: oneshot | resident` — his choice, restored as a switch.**
*Context.* [204] gives him a choice about the orchestrator itself: «оркестратор можна як компактити, так
і запускати повністю новий оркестратор … і людина може це налаштовувати». ADR-01 deletes the object the
choice applies to. `JUDGE-fidelity` calls this the largest single deletion of stated configurability in
the set.
*Decision.* Ship `judge.mode`, DEFAULT `oneshot`. `resident` keeps one long-lived judge session woken over
the adapter's channel, subject to the same `roles.orchestrator` context threshold and the same
close-and-reseed path. Built in a later milestone; the key exists from day one and `config show` prints it.
*Consequences.* The central bet is unchanged and a configurable he named twice in one breath is not lost.
*Rejected.* Deleting the key (minimal); picking `resident` by default (operability) — neither keeps both
his sentence and the cost.

**ADR-03 · Roles survive as model+account pins, not as windows.**
*Context.* R1-07 [270]/[276] restricts a provider or account to named roles; [204] sets a compaction
threshold per role; Д8 [466] wants a cheap model for watch duties. All three are role-scoped settings, and
none of them requires the role to be a session.
*Decision.* `roles.{orchestrator,watcher,executor}` are pins carrying `{platform, provider, account,
model, context.raw_pct_threshold}`. The judge resolves `judge.model` from `roles.watcher`; the lanes
resolve from `roles.executor`.
*Consequences.* Per-role thresholds work (C5-A11 measured refill rates differing 13× by role, VERIFIED).
Two of his three windows are no longer sessions — the tension is ADR-01's.

**ADR-04 · The single-orchestrator invariant is an OS lock, keyed on the project.**
*Context.* «якщо раптом одночасно два якісь оркестратори працюють, то це не окей. Це треба відслідковувати
і не дозволяти» [300–302]. VERIFIED on this machine: `flock(1)` is **not installed**; `/usr/bin/shlock` is
PID-based and PID-recyclable; `python3` 3.9.6 is present. An 18-line Python holder using `fcntl.flock` was
written and executed: the second attempt prints `LOCK HELD: <pid> <epoch> <argv>` and exits 69, and the
next attempt acquires immediately after the holder dies — no TTL, no stale-lock timeout, no heartbeat.
*Decision.* `bin/orc-lock.py` holds an exclusive lock on `~/.orchestrator/locks/<sha1(project-root)>.lock`
and `execvp`s the supervisor. The lock *being acquirable* is the proof that a previous supervisor is gone.
*Consequences.* Recovery is deterministic with no third verdict (C6-A2's "the probe errored" cannot arise,
because there is no probe). **Two runs against one project are refused**, exit 69 naming the holder — he
cannot run two milestones of one repository concurrently. That is his absolute read taken literally, and
it is round-2 question **B7**.
*Rejected.* A detector. FIELD-NOTES shows every detector in the system being wrong at least once
(VERIFIED); `ground-failure-corpus` F-13 recommends the hard invariant for exactly that reason.

**ADR-05 · Run state lives at `$HOME/.orchestrator`, not in the repo and not under `<config-root>`.**
*Context.* `RED-night-one` finding 11: the eight specs name **six** different state roots, two of them
`frozen`-class keys with different names, so they cannot be reconciled at run time. Two put it under
`<config-root>`. VERIFIED: on this machine `CLAUDE_CONFIG_DIR` is a profile switcher's profile directory and the
account switcher works by moving it — so state under `<config-root>` moves with the profile, and the
doctor that R1-10 [246] requires *«на якійсь іншій підписці»* resolves a different root and finds no run
at all.
*Decision.* One root: `orchestrator.home: $HOME/.orchestrator`, `frozen`. One run-id format:
`<project-slug>-<YYYYMMDD-HHMMSSZ>-<4 hex>`. One `index.tsv` shape, 7 columns, documented once.
*Consequences.* It is *not* where this repo's other plugins keep state (`~/.claude/<plugin>/`), so a user
looking there will not find it. That is round-2 question **C4**.

### Part B — one object model (resolving the spec set's contradictions)

**ADR-06 · Two different things were called "Lane". They are now Slot and Lane.**
*Context.* `RED-night-one` finding 1, the most severe in the set. `SPEC-adapters` defines
`Lane = Platform × Provider × Account × Role`, created at preflight, immutable for the run, one per
runnable slot, at `lanes/<id>/`. `SPEC-state` defines a lane as *"one attempt at one task"*, created by
`mkdir lanes/<lane_id>` **as the claim**, at the same path. The orphan scan removes any directory under
`lanes/` with no `start.json` — which is every one of the adapter's objects, forever. The first resume
deletes all three platforms' resolved lane records.
*Decision.* **Slot** = Platform × Provider × Account × Role, resolved at preflight, immutable for the
run, at `slots/<slot-id>/`. **Lane** = one attempt at one ticket, created by `mkdir lanes/<lane-id>`,
at `lanes/<lane-id>/`. One event file name (`events.ndjson` raw, `events.norm.ndjson` normalised), one
session lineage file (`sessions.ndjson`, keyed on lane, appended per reseed).
*Consequences.* Every stop command, every status line and every report speaks one vocabulary. The word
the owner sees is round-2 question **C5** — «лінія» is not his word, and `SPEC-adapters` §16.1 admits it.
*Rejected.* Keeping both and disambiguating by path depth. An implementer reading two specs builds two
products.

**ADR-07 · One work-item vocabulary, in one transitions file.**
*Context.* `RED-night-one` finding 6. `SPEC-work` has five roles (`backlog | ready | active |
needs-input | done`) and states *"`blocked` is not a role"* and has no `failed`. `SPEC-state` has eight
task states with `blocked` and `failed` both load-bearing. On the simulated night the first Д9 supersede
creates an item as `backlog`, `task.discovered → backlog` is not a legal tuple, the journal refuses the
record, and `journal.on_illegal_transition: refuse_and_abort` ends the run at 02:58 with four tickets
unfinished — **because the owner edited a finished ticket**.
*Decision.* One table: `unknown | backlog | ready | claimed | in_progress | needs_review | blocked |
failed | done`, and one `config/transitions.json` that both the journal appender and the work layer read.
The local registry directory is `.orchestrator/tickets/` (six specs against one) and the frontmatter key
is `status:` (five specs against one) — finding 7, where the mismatch alone makes the owner's 02:00 edit
permanently invisible and Д8 and Д9 never fire on any night.
*Consequences.* Nothing else; this is a deletion of duplicate vocabulary, not a design change.

**ADR-08 · One control plane: `control.json`, append-entry, JSON, applied exactly once by id.**
*Context.* `RED-night-one` finding 8 and `RED-fidelity` F2. Two designs exist: `control.yaml`
(declarative document, leaf-diff, a vendored ~150-line YAML parser, a `mkdir` lock directory, 10 s poll)
and `control.json` (append-entry log, `flock`, 5 s sub-tick). A `stop-hard` typed at 03:30 is written by
one and never read by the other; the acknowledgement loop — the single feature both are proudest of —
times out by construction. `SPEC-config` §14 Q1 asks the owner YAML-or-JSON while four sibling specs have
already shipped JSON.
*Decision.* `control.json`, append-entry. [524] describes exactly that mechanism — the command writes into
the file the orchestrator reads every tick, and the change applies on the next tick. Write protocol: take
`orc-lock.py control.lock`, re-read under the lock, append, write a sibling temp file, `rename()`. Read
protocol: `stat`, then parse on change; a parse failure **keeps the last good entries, applies nothing
new, and sets `status.json.control_error`** — it never takes the run down. Every applied entry moves to
`control.applied.ndjson` and is removed from `entries`; **an entry is applied exactly once, by id**.
*Consequences.* The re-fire class behind the 85-minute loop (FIELD-NOTES §11.6, VERIFIED) is structurally
closed. He hand-edits JSON, which is worse than YAML at 02:00 — mitigated because the three commands
exist so he does not have to. Д7's «навіть якщо на початку я обрав інший варіант» [458] is served by a
`{verb:"set"}` entry, which beats `config.run.json` by construction. **Do not spend a round-2 question on
YAML-vs-JSON**; it is a disagreement between our own documents.

**ADR-09 · Soft and hard keep their command names and lose their single file field.**
*Context.* He uses «хард»/«софт» in three items with three granularities and two opposite
post-conditions — [171] stop-the-task-and-the-run-stops, [195] apply-a-change-now, [204]
interrupt-and-continue — and wants one file to carry all of them. A single `hard` field is
unimplementable without guessing which meaning he wrote. Д12 is the one item `ANALYSIS-01` marks
**UNRATIFIED** outright: «підтвердження залишається відкритим» [525].
*Decision.* The file carries `verb` + `scope` + `apply` as three orthogonal fields. **His command names
are unchanged** and the mapping lives in data: `stop.verb_map` in `config/defaults.json`.
`stop-hard → {stop, run, now}`, `stop-soft → {stop, run, boundary}`, `stop-custom → {custom, run, custom,
ref}`.
*Consequences.* If round 2 changes what «хард» means, that is a table edit, not a rewrite. If he
hand-edits `control.json` he writes three fields rather than one.

**ADR-10 · One ledger, one defaults register, one exit table, and the lint names the real file.**
*Context.* `RED-night-one` findings 10, 20, 21. The resource ledger is `owned.ndjson` in four specs and
`resources.ndjson` in the one that defines its schema — so teardown walks an empty file, every compose
project and worktree is left running, and the CLEANUP-PROOF prints an empty table under a heading
asserting that unauthorised destruction is *"unreachable"*. Worse: the build-failing lint that is the
whole safety story — *every identifier in a teardown command comes from a field in the ledger* — names
`owned.ndjson`, so a teardown built from the other file passes the lint by not being the file the lint
knows about. Separately, **seven** registers each claim *"this table is the contract"* and contradict
each other on live values, and `degraded` is exit 4 in one spec, 6 in another, while the exit table that
ships a build-failing test assigns 4 = NO_RUN and 6 = WRONG_PHASE.
*Decision.* One ledger: **`ledger.jsonl`**, with `SPEC-state`'s two-phase `creating → created` protocol
and per-record `fsync`, and the lint rewritten against that name. One defaults register:
`config/defaults.json`, the table in §3 below; a key read at run time that is not in it is exit 78, and
a literal fallback in source fails the build. One exit table, in `SPEC-cli`'s numbering, enforced by one
test.
*Consequences.* Four tables are deleted. No design changes.

### Part C — the queue, and the scheduler that nobody wrote

**ADR-11 · The claim is `mkdir`, and the ordering is an invariant with a test.**
*Context.* C3 measured the read-then-write claim at **27 winners out of 50**; FIELD-NOTES §10.2 records
two concurrent adds producing two files under one ticket id in **five rounds of five** (both VERIFIED).
*Decision.* `mkdir lanes/<lane-id>` is the claim — one syscall, succeeds exactly once. Then `start.json`
**before the platform is launched** (ticket, ticket digest, platform, account, worktree, base sha,
compose project, session id where the client may name it, cmd, `started_at`, `mono_started`). Then
launch, appending each created resource to `ledger.jsonl` as it is created. Then `result.json` **last**.
Then `mv lanes/<id> lanes.done/<id>` — the only commit point. Nothing is written after `result.json`.
*Consequences.* A crash leaves a detectable orphan, never a false claim of completion, and orphan
detection is a directory listing with no journal read and no parse — which is what a resuming process
needs when it cannot yet trust anything else on disk.

**ADR-12 · The scheduler is written down, because no spec wrote one.**
*Context.* `RED-night-one` finding 13, its own words: *"the single largest hole in the set: the thing
the plugin is for has no algorithm."* Dispatch is one clause — *"while live lanes < max and capacity
allows and a ready ticket exists, claim and launch"* — and nothing anywhere says which ticket, to which
slot, in what order, with what fairness. On a night with six tickets and three heterogeneous platforms,
one slot is always deferred and nothing ever un-defers it. Also unresolved: whether `Role.max_concurrent`
and `concurrency.max_lanes` are one ceiling counted once or two counted twice.
*Decision.* Explicit and deliberately dull. **Order:** ready tickets sorted by `(priority asc,
dependency-depth desc, id asc)`, where priority is an optional frontmatter integer defaulting to 100.
**Admission:** a ticket is admitted to a slot when the slot's capacity allows, the slot's adapter
declares every capability the ticket's requirements need, and `live_lanes < concurrency.max_lanes`
globally **and** `< roles.<role>.max_concurrent` for that slot — two ceilings, both counted, both named.
**Affinity:** a retry returns to the slot that failed it unless the failure reason is
`capacity | auth | posture`, in which case it may move; a move is journalled and starts a new session in
the lineage. **Starvation:** a slot deferred for `scheduler.starve_minutes` is given the next admissible
ticket ahead of the ordering, once, and the override is journalled.
*Consequences.* This is INFERRED design, not his decision, and it is the largest thing in this plan he
never spoke to. It is round-2 question **B5**.
*Rejected.* Leaving it to the implementer — which is what the spec set does, and it produces a different
product per implementer.

**ADR-13 · Readiness is a grep, and it discharges the assignment he gave.**
*Context.* «має бути конкретна структура, якимись або тегами, або що … це треба буде, щоби придумав
якусь структуру, і її притримувався» [146]. Two of the four architectures never delivered one.
*Decision.* A ticket is ready iff **(a)** its frontmatter `status:` equals the configured ready state,
**and (b)** its body with frontmatter stripped contains every heading in `tickets.ready_requires`,
**and (c)** every id in `depends_on:` resolves to a ticket whose status is `done`. Re-checked on **every**
transition including release, which is what «її притримувався» means operationally.
*Consequences.* DEFAULT `["Outcome","Acceptance","Scope"]` — the previous generation's three headings,
measured clean across 327 tickets, 288 done, 15 of 15 ready tickets passing, zero violations (VERIFIED).
A machine-authored ticket (Д9's supersede) is created `backlog`, never `ready`; that is round-2 question
**C6**.

**ADR-14 · The board is a mirror; the local ticket body is never written.**
*Context.* [149] frames the board as the orchestrator's «помічник» — a working surface for statuses and
comments. Against it: C3-A1, where the orchestrator's own status comment fires its own change detector
and Д9 reacts to it forever — the same topology as the 85-minute loop; C3-A2's 327 tracked ticket files,
every status write dirtying one; and FIELD-NOTES §4.1, where one dirty tracked file is exactly what made
a merge report success and move nothing (all VERIFIED).
*Decision.* The local claim is authoritative and the board write follows and is allowed to fail: a failure
sets `status.json.board_sync: "degraded"`, notifies once, and changes nothing about execution. On a
**board** the orchestrator sets statuses and leaves comments as he asked, with `board_readback` as the
only admissible evidence that a transition applied and the post-write digest recorded so the detector
ignores its own change. On the **local registry** the orchestrator writes the frontmatter `status:` key
and nothing else; the whole log trail lives in the run directory.
*Consequences.* His «помічник» survives where it is cheap (a board, via API, touching no file) and is
reduced where it is dangerous (a tracked file in a worktree). **Tension recorded:** a human reading the
board at 09:00 may see a state the run has moved past. Round-2 question **C1**.
*Rejected.* Board-as-source-of-truth: C3-A9 shows it failing at 03:00 on a read-scoped token with three
lanes' real work invisible and a second run re-claiming it.

**ADR-15 · Д8 is three tiers, and the model is reached only on a confirmed body diff.**
*Context.* «немає сенсу перевіряти фейбл моделю … чи змінився якийсь тікет … можливо, є сенс запускати
слабшу модель, сабагента … і в нормальному рані, якщо нічого не змінилось, то цей агент просто, типу,
нічого назад не поверне» [466] — unusually specific for this interview.
*Decision.* Tier 0, free: GitHub `If-None-Match` → 304 at zero quota; local `stat` + sha256 of the body
region. Tier 1, deterministic: `lastEditedAt` / body sha against the watermark taken at claim, to tell a
body edit from a label or a comment. Tier 2, and only then: the cheapest configured model, **on the
textual diff only**, never on two full bodies. Watermarks live in the run directory and **never** on the
board — writing them into the body moves `lastEditedAt` and the detector triggers itself.
*Consequences.* His «нічого назад не поверне» becomes structural (no model is invoked at all) rather than
behavioural. Costed spread: ~$14 per 8-hour night for a frontier model reading every body every tick,
~$1.42 for the cheapest model, **~$0.01** for tiers 0–1 with the model only on a confirmed change
(CLAIMED, C3 §5.3, from a measured median body of 3,932 bytes).

### Part D — money, context, liveness

**ADR-16 · `Capacity = Window | Credit | Unknown`, per account, with a per-account hold.**
*Context.* Three incompatible quota models coexist (VERIFIED, ADAPTER-CONTRACT §6.1): rolling window with
a reset (Claude, Codex, Kimi, Copilot, GLM), credit balance with no reset (DeepSeek, Amp, Cursor), and
nothing at all (pi, Qwen, MiMoCode, OpenCode, Aider). His own [007] admits it («можливо це буде взагалі
pay-as-you-go»). `RED-night-one` findings 2 and 3: the spec set has exactly one place to put a wall — the
**run**-level `paused` state — so one account filling at 01:10 idles two healthy accounts for five hours;
and `paused` on a credit provider has no legal exit at all, so the run sits there until a human types a
stop and Д3's clean finish never runs.
*Decision.* Capacity is keyed on `(platform, base_url, account)` and readings are never compared across
keys. A wall is a **per-slot `held` state** with its own `resume_at`, three causes in the transition
table, and no effect on other slots. `Window`: soft threshold → stop admitting to that slot; hard → stop
its lanes; exhausted → `held` until `reset_epoch + margin`, then auto-resume. `Credit`: a spend ceiling
per run; on breach, `held` with **no auto-resume** and a notification, because there is nothing to wait
for. `Unknown`: `hold_dispatch`.
*Consequences.* «дочекатись рестарту ліміту і продовжити» [007] survives as one state and one comparison,
and it stops being a lie on a credit platform. The cost of keeping his R1-06.1 literally is one lane
state, three causes and three transition rows.

**ADR-17 · A standby account gets one bootstrap dispatch.**
*Context.* `RED-night-one` finding 4, a deadlock the specs ship: an idle account cannot be polled at all
(an unused profile's OAuth token is stale and returns `authentication_error`, VERIFIED), so preflight
records it `unprovable`; `capacity.on_unknown: hold_dispatch` then holds its dispatch; the reading can
only become provable if a session runs under that account; the session can only run if dispatch is
allowed. With three slots and a cap of two, one slot is *always* a standby, and it is dead on arrival —
the CLI spec even ships the symptom in its own worked render.
*Decision.* The **first** dispatch to an account with no successful reading this run is permitted. The
reading is then taken in-band from that session's own events, and `hold_dispatch` applies only after a
reading has once succeeded and then gone stale or become unreadable.
*Consequences.* One window of blind spend per account per run, bounded by one lane. That is strictly less
exposure than the third platform never running.

**ADR-18 · `Unknown` is a refusal to schedule and never a zero.**
*Context.* VERIFIED, FIELD-NOTES §11.7: `harness-limits.sh` demands a `.limits` array the live endpoint no
longer has, so `snapshot` returns `UNREADABLE` on every call; `on_unreadable: proceed` then returns 0
immediately; and `stop_at` is parsed out of the literal string `SESSION=?`, so the hard stop **can never
fire**. The limiter was provably inert for days while reporting nothing wrong. Adjacent: Z.ai's
`TOKENS_LIMIT` → `CREDIT_LIMIT` rename rendered **0 % used**, which reads as plenty of room.
*Decision.* `capacity.on_unknown: hold_dispatch` — finish what is running, start nothing new, notify once
— inverting the shipped `proceed`. **Enumerate buckets, never name them**: take every bucket carrying a
utilisation and act on the worst, so a rename survives without a code change. A threshold naming a bucket
the provider stopped reporting is a **configuration error**, loud at preflight and loud again on the
first tick that cannot find it. And the adapter conformance check refuses, exit 65, when `readCapacity`
returns a scalar rather than the sum type or lets an unparseable 200 become zero.
*Consequences.* A flaky endpoint can idle a good night — bounded by `capacity.unknown_grace_minutes: 30`,
after which it notifies rather than sitting silent. Also required: `capacity.cache_seconds: 900`, one read
per account per tick maximum, because C4-A3 is a VERIFIED measurement that a *single* well-formed call to
the Anthropic OAuth usage endpoint returned `rate_limit_error` — and his own global `CLAUDE.md` instructs
*every* Claude Code session to poll that endpoint. The cache protects the reader from the run's own fleet.

**ADR-19 · Context is read from the event stream; hard compaction is close-and-reseed; the scale is a
required key.**
*Context.* «повинен бути механізм, який гарантовано робить цю дію» [204] — the strongest words in the
interview. Four platforms (Amp, Gemini CLI, Cursor, dsh) have **no external compaction trigger at all**
(CLAIMED, ADAPTER-CONTRACT §3 D). And C5-A2 is VERIFIED on his machine: two different percentages exist,
~13 points apart, because his own GSD status line normalises away the auto-compact buffer.
*Decision.* `context.used_pct` is read from `events.norm.ndjson` where the platform emits it — no status
line, no screen capture, no `/context` call, no token spend. Soft mode is a threshold set on the platform
at launch. **Hard mode is close-and-reseed and that is the universal path**: stop the lane, write
`handoff.md` from its own last normalised events plus the ticket body plus `RULES.md`, launch a successor
on the same ticket, append to `sessions.ndjson`. The proof is structural — a new session line and a
predecessor `result.json` with `stopped_for: "reseed"` — never a "did the percentage drop" check, which
C5-A10 shows returns false negatives *during* the operation it verifies and trips Claude Code's
`failure_breaker_open` after three, making the session permanently uncompactable. `context.basis` is a
**required** key (`raw_window | usable_after_reserve | statusline`) and `config set` prints both numbers
for a live session at the moment he chooses a threshold.
*Consequences.* His guarantee holds, at the price of paying for the context a second time and ticket→session
becoming a lineage rather than a field. That is the whole price and `plan.json` names it per slot. Round-2
questions **C2** and **C3**. Also restored as **his** key, which all four architectures turned into plugin
behaviour: `context.post_compact_prompt` [204], DEFAULT = the red-line re-injection, `null` disables.

**ADR-20 · Liveness is three free signals plus two lines, and nothing is nudged.**
*Context.* The hardest row in the failure corpus. `w-phase-19` issued **3,466 of its 3,626 Bash calls as
the literal command `echo idle`**, ~1,400/hour for 3¼ hours, adding **445k tokens — 77 % of all context
growth in that window** — reaching 91 %; a lane accumulated **58 concurrent `sleep 590` child shells**;
and every liveness signal read healthy throughout. It stopped **within one minute** of being told to end
its turn (all VERIFIED, FIELD-NOTES §3.1, §2.2). Separately, the nudge nudged six healthy sessions
because a session heartbeats *between* turns and a validator running a 14-minute suite does not heartbeat
at all (§1.5).
*Decision.* Three signals, all free: process identity (`kill -0` **and** `ps -o lstart=` matching
`start.json`, because a pid alone is recyclable); event-file growth, which moves *during* a turn; and the
engine probe. **Plus two lines in the renderer**: `Δpct/hour` over the last three ticks, and **the top
repeated tool call in the last N events**. `ctx_refill_alarm` is a **defect** predicate that wakes the
judge to tell the lane to end its turn — never a compaction predicate that hides it. Silence is: alive,
event file not grown for `liveness.silence_minutes`, last normalised event not `waiting_on_human`. A
silent lane becomes an item on a fact sheet. **Nothing is nudged, and nothing types into a running
session, ever.**
*Consequences.* The lane that burned three quarters of a window reads `repeats: Bash "echo idle" × 187`
and `+26 pct/hour, alarm at 20` on the fact sheet instead of reading healthy on all three signals. The
capability to talk to a running session is gone with the nudge — §7.

**ADR-21 · A trip watermark before the wake, and a budget on the wakes.**
*Context.* The dominant shape in the corpus is the self-sustaining loop: 85 minutes of Escape-and-
`continue` fed by a banner matched inside the orchestrator's **own wrapped prose**, with
`NO ONE IS BEING TOLD` at line 5620, ended only by an external `SIGTERM`; a 45-minute banner loop;
**1,085 identical flags over five days** (all VERIFIED).
*Decision.* Before any wake, create `trips/<sha1(predicate, subject, run_epoch, armed_at)>.json` with
`set -o noclobber`. A trip already present does not re-fire. On top: `judge.max_calls_per_tick: 1`,
`judge.max_calls_per_hour: 12`, and on exhaustion **notify, raise an attention item, and keep ticking** —
a budget that silently stops the only thing that judges is worse than the loop it prevents. Plus one
absolute rule: **a governor never writes a string its own detectors match into a file its own detectors
read.** Write `context action` and `none|present`, never `/compact` or `rate-limit`. Build-failing lint.
*Consequences.* A ceiling answers *how much*; a watermark answers *again?* The 85-minute loop's mechanism
was re-firing on its own effect, not volume.

**ADR-22 · Durations are computed on a monotonic clock, with a fence after a wake.**
*Context.* VERIFIED, FIELD-NOTES §10.1: the previous run ended
`orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may sleep)`. Sleep is literally how
it died. On wake every staleness reading says dead and the process object says alive, and both are correct.
*Decision.* Every journal record carries `mono` beside `at`; every duration is computed on `mono` and wall
clock is display only. A tick where `wall_delta − mono_delta > sleep.gap_seconds` writes
`observation: machine.wake`, and for `sleep.grace_seconds` afterwards **no lane may be judged dead and no
capacity reading taken before the wake is authoritative.** `caffeinate -i` is bound to the **supervisor's
own pid**, not to a watcher's — the previous generation bound it to the watch loop, so when the watch
died the machine slept (INFERRED).
*Consequences.* This also resolves `RED-night-one` finding 14: the lane timeout is on `mono` too, and
there is one value, not `3600` in one spec and `14400` in another. Given the measured distribution — a
worker session per phase ran **58 min to 3 h 20** (VERIFIED, FIELD-NOTES §6) — a one-hour wall clock kills
most real lanes. `lane.max_seconds: 14400` with the judge owning silence below it, which is what [231]
says.

### Part E — truth, and blast radius

**ADR-23 · No `ok` on a mutating operation without admissible evidence — and only for the
orchestrator's own operations.**
*Context.* The largest failure class on record. `git checkout master` aborts when a tracked file is
modified, and one always is (GSD rewrites `.planning/milestone.lock` every phase and leaves it dirty), so
the merge ran on the phase branch against itself and printed `Already up to date` — which reads like
success and exits 0. Caught only because a human checked what `master` pointed at (VERIFIED, §4.1).
*Decision.* `config/ops.json` is a **data file**: one row per mutating operation declaring `mutating`,
`idempotency`, `admissible[]`, `reconcile`, `timeout_s`. The one function that appends a `step.result`
**refuses** `outcome: "ok"` on a mutating op carrying no evidence object of a declared admissible kind.
Adding an op without declaring its evidence is a **load-time error**. Evidence kinds in the first build:
`process_absent`, `file_digest`, `git_ref {ref, before, after, read_back_at}`, `board_readback`. On an
orphan whose idempotency class is `unsafe`, **escalate to the Д6 channel and hold the lane — never
replay** (the worked case: a crash between opening a PR and recording it produces a second PR, and R1-12
[331] *wants* stacked PRs, so nothing downstream finds a duplicate suspicious).
*Consequences.* **Keep this sentence verbatim wherever it is written up:** *evidence gating does not
verify the work; it verifies that the orchestrator's own operation happened.* A merge either moved a ref
or it did not, on any project, with or without tests — which is exactly what N2 [344] requires of anything
the orchestrator adds. **This distinction was never put to him**, and it is round-2 question **A2**. If he
rejects it, this ADR, ADR-24 and ADR-25 all come out, and the build accepts that a silently skipped
verification stage can ship five phases again.
*Rejected.* Reliability's full form — eight evidence kinds, four idempotency classes, a four-phase
reconciler — at ~3,500–4,500 lines plus a mutation test per invariant. The narrow form buys the three
cases that actually bit.

**ADR-24 · The merge-landed assertion: two oracles, six lines.**
*Decision.* At the delivery step only:
`git merge-base --is-ancestor "$HEAD" "origin/$BASE"` **and**
`gh pr view "$PR" --json state --jq .state = MERGED`. Plus `EXPECTED_BASE=$(git rev-parse HEAD)` captured
before dispatch and asserted inside the worktree, and `gh pr merge --match-head-commit`. A failed
assertion is a lane `failed` with `reason: "merge_unproven"`, never a retry. Never parse a test summary.
*Consequences.* A branch merged into itself fails the second oracle instantly. CLAIMED working against
this repository's own PR #26. Six lines against a failure that cost a whole night each time it fired.
Gated on round-2 question **A2**, as ADR-23 is.

**ADR-25 · HARVEST — a third answer between the exit code and done; and the oracle does not believe a
self-attributed verdict.**
*Context.* Two halves. First: four platforms exit 0 on failure (Aider on auth failure and rate limit; pi
`--mode json` on provider failure; GLM on quota exhaustion *with* `subtype:"success"`; MiMoCode always —
VERIFIED in those spikes), so outcome is `f(exit_code, terminal_event)` and a disagreement is
`failed: "contradictory"`. But that covers disagreement, not **agreement that is wrong** — a lane that
exits 0, emits `turn_completed`, and produced nothing. Second: phases 14–18 each shipped with a
`NN-VERIFICATION.md` self-attributing `verified_by: the lane that built the phase`, and *"no automated
check caught it; manual review did"* (VERIFIED, §11.4).
*Decision.* A `HARVEST` lane state in which the **engine**, not the exit code, is asked, with three
answers — done, not done, undeterminable. `harvest_evidence: observed` withholds `done` only on
**positively observed emptiness** (no commit, no file change in the worktree, no engine state advance);
an undeterminable harvest sets `needs_review`, never `done`. And `state=done` from the GSD probe is
accepted only when the verification artifact exists **and does not self-attribute** — one string
comparison, the cheapest high-value line in the whole graft set.
*Consequences.* Sortie's asymmetry is the argument and it is a cost argument: advancing an empty ticket
*"moves work in a system you do not own, removes it from the queue you do own, and puts it in front of a
person"*, while withholding *"leaves it where it was, in a queue you keep watching, with the withholding
recorded."* One error costs a morning; the other costs a tick. Three values, never a boolean, because
absence of evidence is not evidence of absence. The self-attribution clause is round-2 question **A3**.

**ADR-26 · Every teardown identifier comes from the ledger, and two lints fail the build.**
*Context.* VERIFIED, FIELD-NOTES §11.5: the owner's default Docker stack was destroyed by a
`docker compose down -v` with **no `COMPOSE_PROJECT_NAME` exported**, so the command resolved to the
default project — his. The actor was never identified, and a session had refused that exact action as
owner-only two minutes earlier. §11.8: `pkill -f 'playwright test'` killed an unrelated lane because every
lane's own prompt contains that literal string. §12.4: detached scripts inherit **no environment at all**.
*Decision.* Teardown walks `ledger.jsonl` in reverse, stops each entry, and **asserts by observation, not
by the command's word** (ADAPTER-CONTRACT §2.4 invariant 10 records `cursor-agent worker kill` reporting
success and leaving the process at 100 % CPU). Two build-failing lints: **(a)** `pkill`, `killall` and an
unscoped `docker compose down` do not appear anywhere in plugin source; **(b)** **no teardown command may
be constructed from an environment variable — every identifier in a teardown command comes from a field
in `ledger.jsonl`.** Lint (a) alone would not have caught the recorded incident; lint (b) would. Residue
from a *previous* run is **never touched** — it is listed with one exact command per item for him to run,
because Д3 and R1-16 together define a set nobody may clean (~150 orphaned volume pairs observed, §11.11).
*Consequences.* A grep asserting that a string is **absent** is one of the very few checks that cannot
pass vacuously — which matters more in this repository than in most, because its own memory rule records
that the harness greps prose and tests can pass vacuously.
*Honest limit.* The ledger constrains the orchestrator, not its children. A lane can still run `pkill`
itself, and on Kimi and pi there is no sandbox beneath the text file.

**ADR-27 · The plugin abstains from permissions, and the red-line file warns rather than refuses.**
*Context.* «На окремо якогось обов'язкової процедури для цього не треба. Достатньо лише одного файлу,
який може доповнюватись, текстописний … технічні обмеження середовища користувач за потреби налаштовує
сам … Але, так, це максимум» [357]. Against that: VERIFIED in the shipped source,
`harness-spawn.sh:32-39` defaults to `--dangerously-skip-permissions` **and falls back to it for an
unrecognised value** — the most dangerous option chosen for him, twice. And `RED-fidelity` F6: one spec
warns when the red-line file is absent and one **refuses to start**, exit 78 — which is precisely the
«окрема обов'язкова процедура» the sentence rules out, arriving as a default in the spec that owns the file.
*Decision.* `session.permissions: inherit` — the orchestrator passes no permission flag at all and the
platform uses his own settings; an unrecognised value is a config error, never a silent bypass. Preflight
prints the *effective* posture it detected from the platform's own report, so he sees what he is running
with. The red-line file: `red_lines.on_unreadable: warn_and_proceed` and `on_oversize:
truncate_and_notify` as shipped defaults, with the fail-closed values available. One file, read from the
main checkout, mandatory reading for every agent, no enforcement machinery.
*Consequences.* **Tension, stated plainly:** a flat prose file has no field separating an absolute from a
preference, and nothing writable in it would have prevented Playwright's `--trace on` printing two local
role passwords into a transcript (VERIFIED, §11.10). The file cannot cover that class and this design does
not pretend it can. What the design adds is not enforcement, it is bookkeeping — a recorded ledger and a
teardown that touches only it, which bounds the blast radius of the *cleanup* path, the path that actually
destroyed his stack. The untagged-line question and the «це максимум» reading are round-2 questions **A4**
and **A5**.

### Part F — dependencies, process, and proof

**ADR-28 · The engine has no default, and mixing is a one-line refusal.**
*Context.* «комбінувати ні, тут або або, або свій, або вже готовий, якщо готовий, то який саме» [118].
`RED-fidelity` F1: three specs ship three different answers to "what if he has not said which process" —
no default with a wizard, `none` (a bare session with no steps, which is itself a process the plugin
chose), and **`gsd`** with the rationale *"the engine he names most often"*. Under two of the three, the
plugin decides his process in a defaults table.
*Decision.* `process.kind ∈ engine | steps`, both set is a config error, exit 78 — [118] as one check.
`engine.id` has **no default**: the config wizard asks with a TTY and the run exits 3 without one. The
walking skeleton sets `gsd` in its own fixture config, not in the shipped register.
*Consequences.* A fresh install cannot run silently on a process he did not choose. One extra question at
first run, which [133] already authorises: *«читає глобальні і проектні налаштування, використовує що є,
питає те, чого бракує»*.

**ADR-29 · The engine is driven by a probe that costs nothing, and the orchestrator adds no check of its
own.**
*Context.* C9-A1 is a blocker in the *requirements*, not the implementation: R1-13 [344] gives
verification to the process, R1-03 [118] makes "no verification at all" a legal process, and **nothing
anywhere says how the orchestrator learns that work finished** as distinct from the session ending.
*Decision.* `probe/<engine>.sh` prints **one line** and exits 0: `state=running|blocked|done|failed` plus
a `detail=`. For GSD it is about 25 lines around `gsd-tools`, VERIFIED working today against a real
project: `state` carries `status`, `current_phase`, `current_plan`, `stopped_at`, `last_updated` and a git
SHA; `runtime-identity` pins the engine version into the journal; `--exit-contract=v1` is pinned so an
upgrade cannot silently change what an exit code means; `windows status` gives GSD's own
`human_needed` / `insufficient_spec` escalation — a ready-made predicate at zero tokens. When there is no
probe the oracle is the process exiting and **`status.json` says so**: `"completion_oracle":
"process_exit"`. He sees which one he got.
*Consequences.* R1-06.3's rule — reference the chosen process's records, keep your own only where there
are none [171]/[189] — is satisfied by construction. One warning belongs in the GSD probe's own file
(VERIFIED, C9-A2): under a host-created worktree GSD returns `dispatch-isolation: harness-worktree`, runs
no git of its own, and `worktree base-check` returns `{"shouldDegrade": true, "reason":
"head-diverged-from-fork"}` — so a lane cut from a base GSD does not expect will silently serialise or
fork its sub-worktrees from `origin/HEAD`. Preflight refuses a GSD lane whose base disagrees. **Д4's «з
цим треба поєднювати» is an assignment he gave, not a decision he made**, and it is round-2 question **B3**.

**ADR-30 · `acpx` is adopted behind a five-verb interface, off by default, and both halves are pinned.**
*Context.* `ADOPTION-VERDICT` §3 recommends adopting `acpx@0.17.0` pinned as the session layer. `RED-acpx`
re-verified it hands-on and found **the recommendation stands and four of its load-bearing claims are
wrong** — see §6.2 below. The run-ending one: `acpx claude` does not load user settings
(`CLAUDE_CODE_DEFAULT_SETTING_SOURCES = ["project","local"]`, VERIFIED in source), which is where GSD,
every one of his plugins, his hooks and his permissions live. He would have found out at 03:00 when a
lane could not find `/gsd:execute-phase`. And "pin acpx" pins the Claude adapter to exactly `0.76.0`
while upstream shipped `0.77.0`, `0.78.0` and `0.79.0` in the three days around it, resolved through
`npx -y` **at agent launch, over the network, inside the run**.
*Decision.* `acpx` is one legal value of an adapter's `launch.sh` — `adapters/acpx-claude/` — behind a
five-verb `SessionLane` interface (`ensure`, `prompt`, `cancel`, `status`, `close`) that nothing else in
the orchestrator may import. DEFAULT **off**: the skeleton drives `claude -p --verbose --output-format
stream-json` directly. If it is on: `ACPX_CLAUDE_INCLUDE_USER_SETTINGS=1`, a lane-local
`.claude/settings.json` in each worktree disabling singleton plugins by name (starting with the
orchestrator itself), the adapter pinned explicitly and **pre-installed** rather than `npx`-ed at launch,
a version-equality preflight assertion, and an exit-code contract **test** in this repo rather than a
CHANGELOG read (`RED-acpx` Finding 5b: an exit code was renumbered 4→5 in code and never appeared in the
CHANGELOG).
*Consequences.* R1-18 is cleared — «превентивно я буду обирати свій варіант» [403] — because this is opt-in
and the exit path is a day. The exit is cheap in code and expensive in concepts; the interface is what
makes it a day instead of four. **The first experiment to run, before any orchestrator code:** ensure a
session in a worktree with the env var and ask it to list its slash commands. If `/gsd:execute-phase` is
absent with the fix applied, this adoption is impossible and nothing else about it matters.
*Rejected.* `ADOPTION-VERDICT` "Change 2" — the architectural fork built on the claim that a headless
question is terminal. `RED-acpx` Finding 3 shows the refusal is gated on `agentInfo.name ===
"antigravity-acp"` and a Claude question becomes an ACP elicitation that is *cancelled*, not fatal. The
fork is retracted; see ADR-31.

**ADR-31 · A question is terminal for the attempt and durable for the task.**
*Context.* Two specs give opposite behaviour on the platform he will actually run tonight
(`RED-night-one` finding 15): one builds its whole design on *"a question cannot be answered by anything"*
(exit 5, lane terminal, task blocked), the other injects an `ask_supervisor` tool to keep it answerable —
and **no spec anywhere defines `ask_supervisor`**: not its schema, not its injection, not what a
`claude -p --output-format stream-json` process does with it. `LANDSCAPE` §5 corrects the adoption
verdict here too: the field is **split, with both sides argued explicitly**, not unanimous.
*Decision.* The attempt ends; the **task** holds its claim and goes `blocked`; the queue moves on (Д6
[449]); a pending-question record with a **required fallback** goes to the Д6 channel; when the answer
arrives a new session starts on the same ticket in the lineage. `questions.answer: when_native` — the
orchestrator answers only where the platform supports it natively, within configured authority, which is
what [324] plus his ratified «в межах налаштованих повноважень» at [328] permits. `ask_supervisor` is
**deferred, named, and not built**; so is the acpx runtime transport that is the only working R8
implementation found in the whole research.
*Consequences.* A lane that asks at 02:41 finishes in the morning rather than overnight. `questions.channel`
ships **unset with preflight asking once** — «місце визначається користувачем. Крапка» [449] — and
`RED-night-one` finding 16 is closed by making preflight's question mandatory before a first run rather
than by inventing a silent path: a run with no channel and `when_only_blocked: wait` waits forever for an
answer to a question nobody can see.

**ADR-32 · He sees nothing until he asks, and the default channel is honestly labelled as not reaching him.**
*Context.* «оркестратор не повинен нічого виводити для мене … я можу запустити окремий термінал,
прописати orchestrator двокрапка статус … І це все, що треба» [508], corrected by him at [511]/[512] to
«мінімальну кількість аутпуту і стокінгів». Against it: R1-17 [395] says the notification channel must be
*proven working*, which means sending a real message. And `RED-night-one` finding 23: the shipped
`notify.channel: terminal` *"always verifies"*, so every tier passes while five events on a real night
land in a JSON file on a sleeping laptop.
*Decision.* During the run: nothing. `orchestrator:status` is a **bash script**, not a skill and not a
command that invokes a skill — ten status checks in a night cost **zero** model turns (the previous
generation routes an identical bash+jq status through a skill, VERIFIED). Notifications are the only
push, opt-in, and the channel is proven by **delivering a real message** — a `getMe`-shaped check is
refused as proof, because C9-A5 records Telegram's `getMe` passing for a bot that had been kicked from the
chat. DEFAULT `notify.channel: terminal`, **and preflight prints one line saying out loud that the
terminal channel reaches nobody while he is asleep**, whenever `when_only_blocked: wait` is also set.
`notify_max_per_run: 40` with `notify_coalesce_minutes: 30`, aimed by name at the 1,085-identical-alerts
case. There is **no `healthy` field** in `status.json`: the previous generation computed `healthy` from an
attention file its own watch loop truncated every cycle, so it would have printed `healthy: true` for all
85 minutes of the loop in which `NO ONE IS BEING TOLD` was written to the log (VERIFIED). A surface that
cannot express health cannot lie about it; `blocked_on` is a list of named facts.
*Consequences.* R1-17's substantive half — *what is worth waking him for* — was never answered, so the
seven-event list is **proposed** and preflight prints it with an invitation to cut it. Round-2 question
**B6**.

**ADR-33 · No test enters the suite until its mutation has been seen to turn it red.**
*Context.* VERIFIED twice over: FIELD-NOTES §11.9 records every commit gate in the previous generation
found broken **by mutation rather than by failing**; `ground-failure-corpus` §1.2 records that **six of
seven deliberate defects survive the whole 51-test suite**; and this repository's own memory rule says the
harness greps prose and tests can pass vacuously. `ARCH-reliability` §18.3 states the consequence for all
four architectures: *"until those tests exist and are verified by mutation, this architecture is a claim,
not a property."*
*Decision.* Every invariant in this plan carries a named mutation. The mutation is executed and observed
to fail before the test is considered to exist. `orchestrator` goes into the `PLUGINS` array of
`tests/run-all.sh` at WS-0, before there is any code to violate the lints.
*Consequences.* This is the one decision that makes every other decision checkable, and it is why the
build estimate in §4 is higher than `JUDGE-cost`'s.

---

## 3. Defaults the owner never chose

**This table is the contract.** A key read at run time that is not a row here is exit 78; a literal
fallback anywhere in source fails the build. `orchestrator:config show` prints every row with its value,
its source file, its slot, its scope, its apply class, and a `(proposed)` marker — so he can audit every
invented number in one screen.

**Reading the columns.** `HIS` marks a value he stated out loud, with the row anchor; everything else is
**DEFAULT-PROPOSED** and is a proposal with a reason, not a decision. **Damage** is how badly it hurts to
get it wrong: **Night-ending** (the run is lost or his machine is harmed), **High** (a night is wasted or
he is misled about something that matters), **Medium** (money, latency or a wrong-but-recoverable state),
**Low** (annoyance). Apply classes: **live** = next tick · **boundary** = next lane launch · **frozen** =
reported and never applied mid-run.

### 3.1 Run shape and scheduling

| Key | Default | Scope / apply | Protects against | Damage if wrong |
|---|---|---|---|---|
| `tick.interval_seconds` | `60` | run / live | A tick cheap enough to run all night with no model in it; one-minute worst-case stop latency | Medium — too low burns machine, too high delays every stop |
| `tick.control_seconds` | `5` | run / live | His «на наступному тіку» [520] at a latency he can feel. A `stop-hard` should not wait 60 s | Medium |
| `run.mode` | `controlled` (of `ask \| autonomous \| controlled`) | run / boundary | He named three values [075] and no default. `ask` cannot be the default: a 04:00 restart has nobody to ask | **High** — the whole character of the product (see §6 R-3) |
| `run.mode_on_takeover` | `controlled` | run / boundary | A doctor relaunch at 04:00 inheriting `ask` and blocking on nobody | High |
| `concurrency.max_lanes` | `2` | project / live | Two lanes ran cleanly twice in the record (phases 12/13 and 21/22, spawned 11 s and 13 s apart, no port or state collision); two concurrent image builds OOM-killed his own container | Medium — `1` loses throughput he has, `4` risks his machine |
| `limits.max_concurrent_builds` | `1` | project / live | Serialises only steps a lane **declares** `heavy: true`. The incident was two `docker compose up --build` at once, not two lanes | Medium. **Tension:** touches the axis he retracted at [163]; `0` disables |
| `roles.<role>.max_concurrent` | `executor: 2`, others `1` | project / live | A second ceiling, counted separately from the global one, so "is this one cap or two" has an answer | Low |
| `scheduler.order` | `(priority asc, depth desc, id asc)` | project / live | An undefined queue order producing a different product per implementer | Medium |
| `scheduler.starve_minutes` | `90` | project / live | A slot deferred by a global cap that nothing ever un-defers | Medium |
| `scheduler.retry_affinity` | `same_slot_unless(capacity\|auth\|posture)` | project / live | A retry bouncing between platforms and forking the session lineage | Low |
| `orchestrator.home` | `$HOME/.orchestrator` | user / frozen | State a profile switch can move, so a doctor on a second account cannot find the run (VERIFIED: `CLAUDE_CONFIG_DIR` is a profile switcher's profile dir here) | **Night-ending** — the watchdog is blind |
| `config.user_band_home_fallback` | `true` | user / frozen | Under a profile switcher, snf slots 3 and 4 resolve to files that do not exist, so the user band is silently empty and indistinguishable from "he configured nothing" (VERIFIED) | High. **Deviation from Д1**, disclosed (round-2 **C7**) |

### 3.2 Work intake

| Key | Default | Scope / apply | Protects against | Damage if wrong |
|---|---|---|---|---|
| `tickets.source` | `local` | project / frozen | The skeleton has no board; local is the only source proven end to end | Low |
| `tickets.local_dir` | `<project>/.orchestrator/tickets` | project / frozen | Six specs said `tickets/`, one said `items/`; under the minority spelling the owner's edits are invisible forever | **Night-ending** if wrong — Д8 and Д9 never fire |
| `tickets.ready_requires` | `["Outcome","Acceptance","Scope"]` | project / live | A one-line ticket eating four hours. Measured clean across 327 tickets, 288 done, 15/15 ready passing, zero violations | Medium |
| `tickets.ready_status` | `ready` | project / live | The frontmatter key is `status:`, not `role:` — a mismatch fails the floor on line 1 of every ticket | **Night-ending** if wrong |
| `tickets.max_claims_per_run` | `0` (unbounded) | run / live | **HIS behaviour** [422]: Д2 is unconditional pickup. A cap is a brake he did not ask for | Low |
| `tickets.notify_on_queue_growth` | `50` | project / live | The 236→327 overnight queue growth that needed him to set a pause by hand. A notification is not a brake; it is the signal he acted on | Low |
| `tickets.machine_authored_ready` | `false` (Д9's new ticket is `backlog`) | project / live | The orchestrator creating work for itself and taking it the same night | Medium |
| `board.writeback` | `true` for a board, **`false` body / `true` frontmatter status** for the local registry | project / boundary | The tool's own log inside a ticket body firing its own change detector; 327 dirty tracked files | High |
| `board.on_missing_status` | `refuse_connect` | project / boundary | Creating statuses on somebody else's board at 04:00. He asked for the check [153] and not for the remedy | Medium (round-2 **C8**) |
| `watch.tier0_interval` | every tick | run / live | Paying a model to read an unchanged ticket. A 304 or a `stat` is free | Medium — ~$14/night vs ~$0.01 |
| `watch.scout_model` | the cheapest model the pinned provider offers | user / boundary | Д8 [466] made a key rather than an instinct | Medium |
| `watch.scout_input` | `diff_only` | run / live | Sending two full bodies where a diff answers the question | Low |
| `watch.after_done_hours` | `24` | project / live | Д9 is about work **already finished**; the watcher stopping at completion never sees the change it exists for | Medium (round-2 **C9**) |

### 3.3 Capacity

| Key | Default | Scope / apply | Protects against | Damage if wrong |
|---|---|---|---|---|
| `capacity.soft_pct` | `80` — **HIS** [171] | user / live | Not proposed. Stated. One spec shipped 85 with no note; that is corrected here | High |
| `capacity.hard_pct` | `95` | user / live | He used 80 for *both* soft and hard in one breath, which cannot both hold | High |
| `capacity.on_unknown` | `hold_dispatch` | user / live | The shipped `on_unreadable: proceed`, which made the limiter **provably inert for days** while reporting nothing wrong | **Night-ending** — this is the single largest fix available |
| `capacity.unknown_grace_minutes` | `30` | user / live | `hold_dispatch` silently idling a whole night on one 429 | Medium |
| `capacity.cache_seconds` | `900` | user / live | A measured single well-formed call returning `rate_limit_error` because four standing pollers exist on this machine — including every Claude session, per his own global `CLAUDE.md` | High |
| `capacity.bootstrap_dispatch` | `true` (one blind dispatch per unproven account per run) | user / live | The deadlock that makes every standby account permanently unschedulable | **Night-ending** — a third platform dead on arrival |
| `capacity.reserve_pct` | `0`, **and preflight prints the question every run until he answers** | user / live | Inventing a reserve for an account he also works in. The sub-question was dropped by the interviewer (VERIFIED) | High — the run can eat the limit he needs at 09:00 |
| `capacity.credit_ceiling_usd` | `null` = **refuse to dispatch to a credit lane until a ceiling is set** | user / boundary | "Wait for the reset" waits forever on a credit platform; all three of his stop modes are expressed in a percentage that does not exist there | **Night-ending** on DeepSeek/Amp |
| `capacity.margin_s` | `90` | user / live | Resuming at the exact reset second and being refused | Low |
| `capacity.bucket_selection` | `worst_of_all_reported` (enumerate, never name) | user / live | A provider renaming a bucket and the reader returning 0 % used — which reads as plenty of room | High |

### 3.4 Context and compaction

| Key | Default | Scope / apply | Protects against | Damage if wrong |
|---|---|---|---|---|
| `context.basis` | `raw_window` — **required, never inferred** (of `raw_window \| usable_after_reserve \| statusline`) | user / boundary | Two percentages ~13 points apart on his machine. A threshold is meaningless without its scale | High |
| `context.raw_pct_threshold` | `75`, **per role** | user / boundary | Refill rates differing 13× by role (8 %/h watch, 26 %/h worker, 2 %/h orchestrator, measured); acting before the platform pre-empts | Medium |
| `context.mode` | `soft`, with `context.fallback: reseed` | user / boundary | Hard mode is not implementable at all on four platforms | Medium |
| `context.post_compact_prompt` | the red-line re-injection; `null` disables | user / boundary | **[204] names this as HIS setting** and all four architectures turned it into plugin behaviour | Low, but it is his key |
| `ctx_refill_alarm` | `20` (%/h) — a **defect** predicate, not a compaction predicate | run / live | The lane that is alive, busy, spending money and producing nothing. Compacting it hides the defect | **High** — 445k tokens, 77 % of a window, undetected |
| `facts.repeat_window_events` | `200` | run / live | The same tool call repeated thousands of times reading as work | High |

### 3.5 Liveness, judgement, failure, time

| Key | Default | Scope / apply | Protects against | Damage if wrong |
|---|---|---|---|---|
| `liveness.silence_minutes` | `20` | run / live | Long enough not to fire on a 14-minute test suite (the previous `stall_minutes`) | Medium |
| `lane.max_seconds` | `14400` (4 h), on `mono` | run / live | Measured worker sessions ran 58 min – 3 h 20. A one-hour wall clock kills most real lanes; a wall clock at all kills them across a sleep | High |
| `judge.mode` | `oneshot` (of `oneshot \| resident`) | user / boundary | Keeps the central bet; restores the choice [204] gives him as a switch rather than a rebuild | Low |
| `judge.model` | the `roles.watcher` pin | user / boundary | His cheap-model instinct [466] | Medium |
| `judge.timeout_s` | `120` | run / live | A hung model call holding a tick | Low |
| `judge.max_calls_per_tick` | `1` | run / live | More than one question per tick is a conversation, and the judge holds no state | Low |
| `judge.max_calls_per_hour` | `12` | run / live | A judge in a disagreement loop spending the night | Medium |
| `judge.trip_scope` | `(predicate, subject, run_epoch, armed_at)`, `O_EXCL` **before** the wake | run / live | A detector re-firing on its own effect — the mechanism of the 85-minute loop, not its volume | **High** |
| `judge.on_budget_exhausted` | `notify` + `blocked_on`, **keep ticking** | run / live | A budget that silently stops the only thing that judges | High |
| `judge.on_unparseable` | `defer` | run / live | A malformed verdict acting. Waiting is always the fail-safe | Medium |
| `failures.repeat_threshold` | `3` — **HIS** [442] | project / live | Not proposed. Stated | — |
| `failures.action` | `notify_and_stop` (of the two he offered) | project / live | He offered notify+stop or just stop; the noisier one is safer at 03:00. No third option invented | Medium |
| `failures.scope` | `task` (park the ticket, keep the run) | project / live | **He said «В який момент не знаю» [442].** Three specs shipped three different answers; `run` would kill four good tickets because one was flaky | **High** (round-2 **A6**) |
| `failures.count_at` | task terminal, not step failure | project / live | Counting ten in-step retries as three failures | Medium |
| `sleep.gap_seconds` | `60` | run / live | A wake read as a stall. **Sleep is how the previous run actually ended** | **Night-ending** |
| `sleep.grace_seconds` | `120` | run / live | Every liveness reading going stale at the same instant on wake | Night-ending |
| `sentinel.interval_hours` | `0` (off) | user / boundary | Off because it needs a separate account, if the user configures one. It is the only judgement in the set not derived from a pre-written predicate — the thing that catches a run that is alive and useless | Medium (round-2 **B4**) |
| `doctor.enabled` | `false` | user / boundary | Same reason. **This is the default that reopens the dead-orchestrator class**, which is how the last run ended | **Night-ending** (round-2 **A7**) |
| `doctor.interval_hours` | `2` | user / boundary | A four-hour window swallows an 85-minute loop whole | Medium |
| `doctor.on_wedged_alive` | `stop_hard_and_notify` (journal not growing) / `notify_only` (work not moving) | user / boundary | Slow and stuck are not distinguishable from outside; a wedged holder keeps its lock forever and nobody is told | High |

### 3.6 Execution, engine, delivery

| Key | Default | Scope / apply | Protects against | Damage if wrong |
|---|---|---|---|---|
| `process.kind` | `engine` (of `engine \| steps`, both set = exit 78) | project / frozen | R1-03's «комбінувати ні, тут або або» [118] | Low |
| `engine.id` | **no default — asked at config, exit 3 without a TTY** | project / frozen | The plugin choosing his process in a defaults table, which [118] forbids | **High** — this is the key he said must be his |
| `engine.gsd.probe_calls` | `[smart-entry, state, windows status]` | project / boundary | Six subprocess calls per lane per tick where three answer | Low |
| `engine.gsd.exit_contract` | `v1` | project / boundary | A GSD upgrade silently changing what an exit code means | Medium |
| `engine.accounting` | `reference` (of `reference \| supplement \| own`), **decided by running the engine's `records` point first and showing him what it found** | project / boundary | R1-06.3's research duty [189]–[192], which one spec marks UNRATIFIED and nothing implements | Medium |
| `harvest_evidence` | `observed` (of `observed \| strict \| off` — never a boolean) | run / live | A lane that exits 0 having produced nothing taking the done path | High |
| `process.on_indeterminate` | `needs_review` | run / live | An undeterminable harvest reading as done | High |
| `worktree.enabled` | `true` — **HIS** [433] | project / boundary | «абсолютно все виконувати в різних ворк трі» | — |
| `worktree.base_ref` | the repo's default branch — **HIS** [433] | project / boundary | «з головної гілки» | — |
| `worktree.owner` | `orchestrator` | project / boundary | Keeps his stated default; costs GSD's intra-phase parallelism. **There is no configuration that gives both today** | High (round-2 **B3**) |
| `worktree.env_proof` | **asked at config, with "nothing to prove" as an explicit recorded answer** — never an empty list | project / boundary | The half of Д4 he stated twice — «постійно переконуватись, що всі ті енвайрмент верібли … запущені» — shipping as a silent no-op | High |
| `worktree.stack_probe` | same | project / boundary | Same | High |
| `worktree.on_stack_down_midrun` | `hold_and_notify` | run / live | A container the task depends on dying at 03:00 and the lane working against nothing | Medium (round-2 **C10**) |
| `worktree.remove_on_done` | `false` | project / boundary | Removing a tree with uncommitted work is irreversible; preflight lists leftovers instead | Medium |
| `session.permissions` | `inherit` | user / boundary | The shipped `--dangerously-skip-permissions` default **and its bypass-on-unknown fallback**. R1-15 [357] taken literally | **Night-ending** |
| `trunk.policy` | `pr_only` | project / boundary | On his own repos no machine source states the rule (`rulesets` → `[]`, `branches/main/protection` → 404) while `CLAUDE.md` says PR-only | Medium |
| `delivery.assert_landed` | `true` | project / live | A merge that prints `Already up to date` and moves nothing | High (gated on round-2 **A2**) |
| `stacked_prs` | `false` | project / boundary | `--update-refs` needs git ≥ 2.38; **this machine has 2.33.0** (VERIFIED). Enabling it silently re-applies superseded commits | High |
| `dedup.trailer_prefix` | `orchestrator-action:` | run / live | A replayed board comment or commit after a crash | Medium |
| `recovery.probe_before_judge` | `true` | run / live | A model call per orphan on every restart, when R1-10 makes restarts an expected event | Medium |
| `ops.on_undeclared_op` | `load_error` | — | `ops.json` rotting silently | High |

### 3.7 Platform and adapter

| Key | Default | Scope / apply | Protects against | Damage if wrong |
|---|---|---|---|---|
| `platform.default_adapter` | `claude` | user / boundary | The first night depending on anything not installed and authenticated today | Low |
| `adapter.verify_max_age_hours` | `0` (verify at every run start), live half **read-only** | user / boundary | An adapter that reports `native` and degrades at 03:00. Two specs shipped `null` = never and `0` = every run; `0` with a read-only live half costs nothing | Medium. **Note:** three capacity calls at 22:41 against an endpoint measured to throttle after two is itself a hazard — the live half must not spend capacity reads |
| `negotiate.on_unknown` | `impossible` | user / boundary | A new requirement passing silently on every adapter written before it. An old adapter fails **forward** | High |
| `negotiate.on_undocumented` | `probe_then_impossible` | user / boundary | Telling him a platform "declares no X" when the resolver failed. `undocumented ≠ impossible` | Medium |
| `version.on_mismatch` | `{patch: warn, minor: refuse}` | user / boundary | Amp shipped five releases in fifteen hours; Copilot 835 versions in twelve months. A run that starts on one flag surface and finishes on another is indistinguishable from a bug in the orchestrator | High |
| `version.autoupdate` | `assert_only` — **we never edit his files; we refuse and name the line** | user / boundary | Silently rewriting his own platform config | Medium |
| `attach.enabled` | `false` (headless-first) | project / boundary | **This is the largest single deviation from a decision he confirmed** ([324], ratified [328]). Takeover of a running headless lane is a handoff costing one restart | High (round-2 **B2**) |
| `runtime.<platform>.visibility` | `mostly_interactive` where the platform supports it | project / boundary | His own words. The three keys in the spec set do not compose; this one is authoritative and `spawn.transport` derives from it | High |
| `acpx.enabled` | `false` | user / boundary | A dependency on the critical path before one experiment has been run | Medium |
| `acpx.version` / `adapters.claude_acp.version` | `0.17.0` / `0.76.0`, **both pinned, adapter pre-installed** | user / boundary | Pinning one and resolving the other through `npx -y` at agent launch, over the network, at 03:00 | High |
| `acpx.include_user_settings` | `true` (`ACPX_CLAUDE_INCLUDE_USER_SETTINGS=1`) | user / boundary | A session with no GSD, no plugins, no hooks and no permissions — discovered at 03:00 | **Night-ending**. Overrides a deliberate safety default of the dependency, on purpose, in writing |
| `acpx.disable_plugins` | `["harness@…", "orchestrator@…"]` in a lane-local `.claude/settings.json` | project / boundary | Singleton contention and the orchestrator spawning itself | High |
| `acpx.turn_timeout_seconds` | `3600` | run / live | acpx's own default is **no timeout at all**, so exit 3 — the most valuable code it has — never fires | High |
| `acpx.ttl_seconds` | `60` | run / live | acpx's default `300` leaves a detached queue-owner process per session for five minutes, which blurs the terminal condition and must be counted in teardown | Medium |
| `acpx.session_identity_drift` | `fail` | run / live | A dead queue owner silently falling back to a brand-new empty session — *reported success and started over* — still exiting 0 | High |

### 3.8 People, channels, output, safety

| Key | Default | Scope / apply | Protects against | Damage if wrong |
|---|---|---|---|---|
| `questions.channel` | **unset → preflight asks once and will not start a first run without an answer** | project / boundary | «місце визначається користувачем. Крапка» [449]. A silent default occupies ground he explicitly reserved; no default at all strands every question | **Night-ending** either way if handled carelessly |
| `questions.answer` | `when_native` | user / boundary | Answering by keystroke with no acknowledgement. The field is split and refusing is the cheap side | Medium |
| `questions.require_fallback` | `true` | run / live | A question with no stated "what if nobody answers" — 11 of 11 of his own production questions carried one | Medium |
| `questions.default_deadline_hours` | `0` (never auto-fires) | run / live | Something happening at 04:00 that he did not authorise. Cost: a question can stand until morning | Medium (round-2 **C11**) |
| `authority.may_decide` | `false` | run / boundary | R1-14: whether the agent may decide at all is itself his setting | High — compounds, see §6 R-3 |
| `authority.autonomous_ops` | **asked, no default** | run / boundary | «людина повинна сама налаштовувати, що саме вона може віддавати на автономне виконання» [107] — one spec shipped `["*"]`, i.e. everything, for the one list he said he must write | **High** |
| `authority.basis` | `[]` + a hand-maintained `<project>/.orchestrator/CORRECTIONS.md` read into it | run / boundary | The deciding party writing its own precedent. [062]'s «треба вчити» is absent from the analysis entirely | Medium — and it is not the learning loop he described |
| `when_only_blocked` | `wait`, `wait_max_minutes: 0` — **HIS** [455] | run / live | His own recommendation, overridable **during** the run | — |
| `when_only_blocked.hold_tick_seconds` | `60` (**not 300**) | run / live | The held state ticking at 300 s while the stop ack waits 90 s, so **every** stop during the state he is most likely to interrupt returns "unacknowledged" — in the spec's own worked example | High |
| `notify.channel` | `terminal`, **plus a printed preflight line saying it reaches nobody while he sleeps** | user / live | `none` + wait-forever + silence = an indefinite block nobody is told about; `terminal` alone = the same thing passing three verification tiers | **High** |
| `notify.events` | `["run_stopped","quota_hard","capacity_unknown_grace","repeated_failure","only_blocked_work_left","board_sync_degraded","doctor_relaunched"]` | user / live | R1-17's substantive half was never answered. Printed with an invitation to cut it | Medium (round-2 **B6**) |
| `notify.max_per_run` / `.coalesce_minutes` | `40` / `30` | run / live | One condition re-flagged **1,085 times over five days** | Medium |
| `notify.probe_message` | `true` | user / boundary | A channel that answers `getMe` for a bot kicked from the chat. Proving it costs one message he did not ask for — Д11 vs R1-17, resolved inside his words | Medium |
| `red_lines.path` | `<project>/.orchestrator/RULES.md`, read from the **main checkout** | project / boundary | The worktree fork that hid an owner-facing question for an hour | High |
| `red_lines.on_unreadable` | `warn_and_proceed` | project / boundary | «На окремо якогось обов'язкової процедури для цього не треба» [357]. One spec refuses to start, exit 78 — which *is* a mandatory procedure | High (round-2 **A5**) |
| `red_lines.on_oversize` | `truncate_and_notify`, `max_bytes: 8192` | project / boundary | Refusing the run because he appended the rule that crossed 8 KiB, to a file he described as «який може доповнюватись» | Medium |
| `red_lines.untagged_type` | **asked, no default** | project / boundary | Reading a plain bullet he wrote as a preference as an absolute prohibition, or the reverse | High (round-2 **A4**) |
| `red_lines.apply` | `next_launch` | project / boundary | A mid-run edit reaching a running lane requires a reseed; quiet by default, with `now` available | Medium |
| `boundaries.sandbox` | **no default — preflight prints the six-rung ladder and the question** | project / boundary | I3 [378]/[381] asked for **options to choose from**, not a decision. Shipping a default on every rung delivers the options already decided | High (round-2 **A1**) |
| `boundaries.orphan_reclaim` | `off` (never touch a previous run's residue) | project / live | His rule, literally. Reclaiming is a **widening he did not authorise** and belongs behind a flag, not in front of one | Medium (round-2 **C12**) |
| `report.scorecard` | `true` | run / live | A probe that can never succeed and never complains (BSD `find -newermt "-10 minutes"` errors out and with stderr to `/dev/null` returns empty **every time**) | High |
| `report.mark_unfired_as` | `unproven` — **never `clean`** | run / live | Reading zero firings as health | High |
| `report.auto_tuning` | `false` — the scorecard is a report, never an actuator | run / live | A system that retunes itself overnight is one whose behaviour he cannot predict | Medium |
| `status.during_run` | `silent` — **HIS** [508] | run / live | His words, corrected by him at [512] to «мінімальна кількість аутпуту» | — |
| `stop.verb_map` | `{"stop-hard":{stop,run,now}, "stop-soft":{stop,run,boundary}, "stop-custom":{custom,run,custom}}` | user / live | **Д12 is UNRATIFIED.** A round-2 change to his vocabulary must be a table edit, not a rewrite | Low, by construction |
| `stop.ack_timeout_seconds` | `90` (one tick plus margin) | run / live | Him believing a stop was applied when it was not — two of his own real instructions were logged as delivered and never executed | High |
| `custom.timeout_s` | `120` | run / live | A custom stop script holding the tick forever | Low |
| `stop.custom_may_exec` | `true` for `kind: commands`, `false` for `kind: rules` | user / boundary | Text he wrote being executed, or a script he wrote being ignored. He named both forms [524] | Medium (round-2 **C13**) |
| `shim.install` | `ask_once` | user / — | A slash command costs one model turn every time; a `~/.local/bin/orchestrator` shim makes status free from any terminal. Writing to his PATH without asking | Low (round-2 **C14**) |

**Count: 88 keys. Seven are HIS** (`capacity.soft_pct: 80`, `failures.repeat_threshold: 3`,
`when_only_blocked: wait`, `worktree.enabled: true`, `worktree.base_ref`, `tickets.max_claims_per_run: 0`,
plus `status.during_run: silent`). **Six have no default at all and are asked** (`engine.id`,
`authority.autonomous_ops`, `questions.channel`, `red_lines.untagged_type`, `boundaries.sandbox`,
`worktree.env_proof`) — each is a place where inventing a value would decide something he reserved.
Everything else is proposed.

**Three defaults compound into a product he did not ask for, and preflight must say so in one line.**
`run.mode: controlled` + `authority.may_decide: false` + `questions.answer: when_native` +
`questions.default_deadline_hours: 0` + `when_only_blocked: wait` + `wait_max_minutes: 0` +
`status.during_run: silent` = *the first uncertainty becomes a question; the question has no deadline;
the agent may not decide; the run waits forever; and nothing is printed.* Each row is a correct reading of
one of his answers and the sum is a wrong reading of the product, because [062] describes the autonomous
run as a first-class mode. Preflight prints:
`this configuration will park on the first question and wait indefinitely; nothing will be printed.`

---

## 4. The build order

Eight milestones. Each is **independently demonstrable** — one command a person runs, one thing they look
at — and each leaves `bash tests/run-all.sh` green. The order is chosen so nothing is built before the
thing it is proven against. **Eval scenarios** name entries from
`research/eval/ground-failure-corpus.md` (`F-nn` failures, `P-nn` positive controls) and the four
deterministic doubles it specifies: `SESSION-DOUBLE` (a fake agent session — a process with a tty, a
scriptable buffer, a transcript, and a recorded inbox of everything actually submitted to it),
`CLOCK-DOUBLE`, `PROVIDER-DOUBLE`, `WORLD-DOUBLE`. **No test in tiers 1–3 costs a paid API call**, and
**no test enters the suite until its named mutation has been seen to turn it red** (ADR-33).

Estimates are **INFERRED** and should be read as ratios, not dates. `JUDGE-cost` warns its own numbers may
be uniformly low, because the previous generation was *smaller* than three of the four designs while being
demonstrably insufficient (1,879 lines of bash, VERIFIED).

---

### M0 — Reconciliation. No code. *(~1 day)*

The eight specs contradict each other on the object model, the work-item vocabulary, the control file,
the ledger name, the state root, the run-id format, the exit table and seven defaults registers.
`RED-night-one` walks one ordinary night and finds twenty-six places where the specs are silent,
contradict, or jointly produce a wrong outcome. **Every one of them fails on the first night rather than
the hundredth, and none of them is a design change.**

**Build:** `docs/GLOSSARY.md` (Slot vs Lane, ADR-06) · `config/transitions.json` (one task vocabulary,
ADR-07) · `config/defaults.json` (§3 of this document, one register) · the exit table, once · `docs/
RATIFICATION.md`, one row per owner item this build rests on, carrying ratified-with-his-verbatim-yes or
unratified-with-the-restatement-he-never-answered.

**Exit criterion.** Each of `RED-night-one`'s 26 findings and `RED-fidelity`'s 15 is closed in writing —
resolved by an ADR above, or explicitly accepted with the cost named. Nothing whose *vocabulary* is
unratified is built as anything but a data table.

**Eval:** none. This is paper, and it is the cheapest day in the plan.

---

### M1 — The floor: lock, config, journal, clock, status. *(~4 days)*

**Build.** WS-0 scaffold + plugin registration + `orchestrator` added to the `PLUGINS` array of
`tests/run-all.sh` (VERIFIED: 79 lines, the array is the gate) + **both build-failing lints land before
there is any code to violate them** — no `pkill`/`killall`/unscoped `docker compose down`, and no
detector trigger-phrase written into a file a detector reads. WS-1 `orc-lock.py` (18 lines). WS-2
`orc-config.sh` + `config/defaults.json` over the six snf slots plus the home-band fallback plus
`config.run.json`. WS-3 `orclib.sh` (atomic write, sha1, journal append, the `mono` clock), the run
directory, `index.tsv`, `orc-status.sh`, and `orc-run.sh --once`.

**Exit criterion.** `orc-run.sh --once` on a project with no tickets writes one journal line carrying both
`at` and `mono`; `status.json` exists and **has no `healthy` field**; `orc-status.sh` prints twelve lines
with zero model turns; a second `orc-lock.py` prints the holder and exits 69, and a third acquires
immediately after the first dies; `pmset sleepnow`, wake, tick again, and `observation: machine.wake`
appears with the measured gap.

**Eval.** F-13 (two orchestrators alive at once — no guard exists today; *mutation:* remove the lock
acquire, assert two supervisors start). F-11 (a staging file observed as zero bytes mid-write; *mutation:*
replace atomic rename with a truncating write). F-20 (detached processes inherit no environment; run the
supervisor under `env -i` and assert it still resolves config). F-49 (a documented fix living only in the
installed copy — this is **live now** in the current plugin). F-21/22/23 + the sleep fence, on
`CLOCK-DOUBLE`: inject a 20-minute wall gap with a 60-second mono gap and assert **no** lane is judged
dead. **P-06** (a correction record type exists and is not destroyed by a control rewrite).

---

### M2 — The queue and the meter. *(~2 days)*

**Build.** `orc-tickets.sh` (readiness as a grep, dependency resolution) and
`capacity/anthropic-subscription.sh` (the one-line sum type), plus the scheduler's ordering and admission
functions as pure functions with no side effects.

**Exit criterion.** `orc-tickets.sh ready` over a five-ticket fixture prints exactly the three ready ids
and, for each rejection, **the clause that failed**. `capacity/*.sh <account>` prints one line; with the
network unplugged it prints `kind=unknown reason=<why>` and **never** `used_pct=0`. The scheduler, given
a fixture queue and three slots, produces a deterministic assignment and a starvation override after the
configured interval.

**Eval.** F-16 (quota UNKNOWN for a whole run with `proceed`; on `PROVIDER-DOUBLE` return malformed JSON
and assert `hold_dispatch`; *mutation:* flip to `proceed` and assert the test goes red). F-17/F-18/F-19
(measured against the wrong account; `authentication_error` blinding every read; a figure moving 26 % → 6 %
from an account switch alone — assert every reading carries its `(platform, base_url, account)` key and
that readings are never compared across keys). The Z.ai rename case: return `CREDIT_LIMIT` where
`TOKENS_LIMIT` was and assert the reader **raises** rather than reporting 0 %. F-51 (ticket-id allocation
unlocked → duplicate ids, **live now**). F-50 (`blocked` never removed on `done`). F-57 (a ticket body
containing template tokens subverting a spawn).

---

### M3 — Adapter, preflight, and the honest refusal. *(~3 days)*

**Build.** `adapters/claude/` (six scripts), `bin/orc-preflight.sh`, `config/requirements.json` — the one
place platforms are **not** named, one row per owner item (`R1-08.hard-compact`, `R1-07.account-switch`,
`R1-11.answer-question`, each with `axis`, `needed_when`, `on_impossible`, `degrade_to`, `owner_item`) —
and `orchestrator:adapter verify`, plus the immutable `plan.json` with `weakened[]` and `denied[]`.

**Exit criterion.** Preflight refuses, by name and at the point of the break, on each of: the lock held;
two roles resolving to one account identity; a threshold on a bucket the provider no longer reports; a
notification channel that answers `getMe` and cannot post; an unreadable `RULES.md` (warn, per ADR-27);
a missing worktree base ref or a missing declared env var; a missing probe under `process.kind: engine`.
**Nothing is created on a refusal.** `plan.json` names, per slot, which of his numbered items got weaker
and to what.

**Eval.** F-70 (a backend silently lacking the capability the run depends on — assert
`negotiate.on_unknown: impossible` makes a new requirement row fail every old adapter closed, at 22:00).
F-36 (`SYNTAX OK` while the anchor never matched). The account-distinctness gate, against the case
where two profiles are **one** account — two config dirs,
two keychain entries, **one quota pool**; *mutation:* remove the gate and assert the per-role thresholds
silently compute against a shared pool. F-60 (a status-line regex missing a new model name — assert the
adapter never reports `native` for a capability whose only implementation is a regex over English prose).

---

### M4 — The lane, the probe, and no `ok` without evidence. *(~4 days)*

**Build.** `orc-lane.sh`, the claim/dispatch half of `orc-run.sh`, `probe/gsd.sh` + `probe/none.sh`,
`config/ops.json` and the single appender that refuses.

**Exit criterion.** A fake adapter whose `launch.sh` is `sleep 3; echo '{"type":"turn_completed"}'` runs
end to end: `start.json` appears **before** the pid exists, `ledger.jsonl` grows as resources are created,
`result.json` arrives **last**, the directory moves. Twenty concurrent claims on one ticket id: exactly
one wins. `probe/gsd.sh` prints one line in under a second with no network against a real `<work-project>`
worktree. Hand-edit `ops.json` to drop `admissible` from one row and the load fails; make a teardown call
return success while the process is still alive and the appender **refuses** to write `ok`.

**Eval.** F-29 (a merge reports success and does nothing — on a scratch git repo, merge a branch into
itself, assert `merge_unproven`; *mutation:* remove the ancestor check and assert red). F-30 (a configured
step silently skipped, artefact self-attributes — fixture a `NN-VERIFICATION.md` with
`verified_by: the lane that built the phase` and assert `state=done` becomes
`state=blocked detail=verification_self_attributed`). F-32 / F-33 (a truncated test run reads as a pass;
a collection crash reports "No tests found" — assert the orchestrator **never parses a test summary**).
F-35 (an empty scope reported as a clean pass → `harvest_evidence: observed`). F-31 (work reaching the
trunk before its validation ran). F-15 (restart with executors alive: adopt-and-duplicate or tear down —
against a populated process table, assert adoption when `(pid, pid_start)` matches and `orphaned`
otherwise). F-53/F-54/F-55 (a branch name one word off; a launcher whose fields disagree; a reused slug
into a stale worktree). **P-04** (two lanes at once with no port or state collision — the observed
positive control, spawned 11 s apart). **P-03** (a timeout never force-kills a busy session).

---

### M5 — The control plane, the clean stop, and the first unattended night. *(~3 days)*

**Build.** `orc-ctl.sh`, `control.json` / `control.applied.ndjson` / `control.ack.json`, the three stop
verbs through `stop.verb_map`, the teardown walker, and the terminal condition.

**Exit criterion — and this is the first end-to-end demonstrable run.** With a lane live, type
`orchestrator:stop --soft` in a second terminal: within 90 seconds `control.ack.json` lists it in
`applied`, `status.json.phase` is `draining`, no new lane is dispatched, and the live one finishes. Then
`config set process.kind steps` and watch it arrive in `rejected` as `frozen`. A run whose fake lane
creates a compose project and a worktree drains, and teardown emits
`docker compose -p <the ledger's name> down` **with `COMPOSE_PROJECT_NAME` set to something else in the
environment**, asserts both by observation, writes `report.md`, deregisters, releases the lock, exits 0.

**Eval.** F-10 (the control file rebuilt each tick, destroying external writes — write an entry from a
second process mid-tick and assert it survives; *mutation:* replace append-and-move with rewrite-from-state
and assert red). F-09 (no delivery receipt exists — sent and arrived are one variable; assert
`control.ack.json` distinguishes `applied` / `deferred` / `rejected` and that the stop command returns a
different exit code for *written but unacknowledged*). F-44 (`docker compose down -v` on the default
project — on `WORLD-DOUBLE`, assert the recorder saw `-p <ledger name>`; *mutation:* source the project
name from `$COMPOSE_PROJECT_NAME` and assert the **lint** goes red, not just the test). F-45 (`pkill -f`
matching the lane whose prompt contains the pattern — assert the string `pkill` does not appear in source
at all). F-48 (~150 orphaned volume pairs from a dead prior run — assert they are listed with exact
commands and **not touched**). F-14 (a finished session closed by nobody, 28 h observed). F-42 (one
condition re-flagged 1,085 times — assert coalescing). F-12 (a channel forking into a worktree copy — read
`RULES.md` and the questions channel from the main checkout and assert a worktree copy is ignored).

---

### M6 — Judgement, the watchdog, and the first real night. *(~3.5 days)*

**Build.** `bin/orc-judge.sh`, the fact-sheet renderer with the two `Δpct/hour` + `top repeated tool call`
lines, the trip watermark, the wake budget, `bin/orc-report.sh` with the detector scorecard, and
`bin/orc-doctor.sh`. Then **run the thing**, against the checklist below, and write what happened into a
new, conclusion-free `plugins/orchestrator/docs/FIELD-NOTES.md`.

**Exit criterion.** A fixture lane goes silent: one fact sheet is rendered, one model call is made, one
verdict lands in `decisions.ndjson` with the sha1 of the fact sheet it saw, and one file appears under
`trips/`. Tick again: **no second call**. Delete the trip file: it fires once more. `report.md`'s
scorecard lists every predicate and marks the ones that never fired **`unproven`, never `clean`**. The
doctor, on a second account, acquires the lock when the supervisor is dead and relaunches; finds the
journal not growing and writes `{stop, run, now}`; finds work not moving and **notifies only**.

**Eval.** F-38 (3,466 of 3,626 calls were `echo idle`, 77 % of context growth — replay the real transcript
fixture and assert the fact sheet carries `repeats: Bash "echo idle" × N` and `+26 pct/hour`, and that the
verdict path is *tell the lane to end its turn*, **not** compact; *mutation:* remove the repeat line and
assert the scenario reads healthy again). F-40 (an 85-minute loop matching a banner in the orchestrator's
own prose — assert the trip watermark blocks the second firing and that no detector string is ever
written). F-24 / F-25 / F-26 / F-27 (heartbeat staleness read as a stall; a shell that can never exit
reading as work; a retry loop indistinguishable from work; ready work + free capacity + no progress and
no rule fires). F-28 (the only escalation is a nudge; 12.4 h observed before one fired — assert **nothing
is nudged** and that the escalation is a fact sheet). F-61 (a probe that can never succeed and never
complains — assert the scorecard reports it `unproven`; this is the test that catches BSD
`find -newermt "-10 minutes"` erroring to `/dev/null` and returning empty every time). F-41 (the notifier
exited and was never restarted). F-59 / F-62 / F-63 (a detector globbing the wrong directory and reporting
a clean zero; a parser substituting a tighter default; unicode and quoted-text false positives).
**P-01** and **P-08** (an escalation path exists and is reachable from a worker; the run report surfaces
its own gaps).

**The first-night checklist** — every line must be true of one real run:
1. `run` acquires the lock; a second invocation exits 69 naming the holder.
2. Preflight proves the account identity, refuses on a shared account, and prints
   `(platform, base_url, account-identity)` per role.
3. Exactly one `lanes/<id>/` per claimed ticket, `start.json` before the pid exists.
4. `events.norm.ndjson` grows during the turn and carries a real `context.used_pct`.
5. `probe/gsd.sh` prints a `state=` line every tick at zero model cost.
6. A `stop-soft` in a second terminal appears in `control.ack.json` as `applied` within 90 s.
7. The run drains, tears down exactly what `ledger.jsonl` lists, asserts each teardown by observation,
   writes `report.md`, deregisters, releases the lock, exits 0.
8. `orc-status.sh` run ten times during the night: **zero** model turns.
9. The scorecard marks unfired predicates `unproven`.
10. `bash tests/run-all.sh` is green, and every mutation was observed to turn it red.

---

### M7 — The second platform and the provider lane. *(~3 days, deliberately after the first night)*

**Build.** `adapters/codex/` — a different vendor, a different protocol, a different account model, and
the honest test of whether the adapter interface is an abstraction or a Claude Code wrapper with extra
steps. Then a **provider lane**: GLM or DeepSeek behind the Claude Code driver, which needs one new method
(`env_for(provider)`) plus one small quota reader and is *a configuration change, not a feature* — the
highest value-per-hour move in the entire platform scan.

**Exit criterion.** One night with two slots on two vendors, and one night with a provider lane whose
`Capacity` variant is `Credit` and whose ceiling refusal is observed at preflight. `orchestrator:adapter
verify codex` passes against fixtures and one read-only live smoke.

**Eval.** The entire Rank-A delivery family is **untested-by-history on any platform but Claude Code**;
the corpus says so explicitly. Treat every one of them as unproven on Codex until this milestone's
fixtures exist. Codex-specific, from the platform research: pin `-m`, pin `-s`, pin
`-c approval_policy`, and redirect stdin from `/dev/null` on every spawn — without the first the run fails
100 %, without the last it hangs all night (CLAIMED, `codex-cli-spike.md`).

---

### 4.1 What is deliberately not built yet, and what each costs

| Not built | Why now | What it costs |
|---|---|---|
| **Board backend (GitHub Issues, ClickUp)** | The local registry is the only source proven end to end, and R1-04 names GitHub Issues as a *recommendation*, not a requirement | He runs from local tickets. **ClickUp is a known problem** even later: it has no free "did anything change" check and no description-change field, against a 100-req/min budget (VERIFIED) — round-2 **C15** |
| **Interactive / attached lanes** | Headless-first is the largest single deviation from a decision he confirmed, and it is the one that makes liveness a process rather than a screen | He cannot walk up to a lane and type into it without paying a stop–relaunch–reseed handoff. Round-2 **B2** |
| **`ask_supervisor` injection and the acpx runtime transport** | `ask_supervisor` has no schema, no injection mechanism and no event kind anywhere in the spec set; the runtime transport is the only working R8 implementation found and it forecloses the CLI contract | A question at 02:41 waits until morning instead of being answered. This is the single feature that would make the tool distinctive, and it is named as deferred rather than dropped |
| **`acpx` on by default** | One experiment decides whether it is possible at all (ADR-30) | The terminal-séance class stays retired anyway, because nothing types into sessions; acpx buys process-tree reaping and a seven-code contract, both real |
| **The doctor on by default, and the sentinel** | Both need **a separate account, if the user configures one** | **This is the plan's worst default** and §6 R-1 says so: it reopens the failure class that ended the last run. It must be the first thing he turns on |
| **The resident judge (`judge.mode: resident`)** | Keeps the central bet | No cross-ticket memory: "this is the third time this week" exists only where the renderer includes it |
| **Stacked PRs** | `--update-refs` needs git ≥ 2.38; this machine has 2.33.0 | R1-12's «піари стакати» is unavailable until git is upgraded, and enabling it now silently re-applies superseded commits |
| **A sandbox / enforcement ladder** | I3 asked for **options to choose from** [378]/[381], and shipping a default on every rung delivers them already decided | R1-16 case 2 — his parallel work in the same folder — stays unsolved. `LANDSCAPE` §5 confirms it is unsolved across the entire field and must be invented |
| **The learning loop** | «якщо це не підходить, то треба вчити» [062] is the only place in the session where feedback changes future behaviour, and it is absent from `ANALYSIS-01` entirely | A hand-maintained `CORRECTIONS.md` read into the decision basis, and nothing more. **The system does not learn by itself, and the deciding party is never allowed to write to the basis it decides on** |
| **A secret scanner over tool output and transcripts** | It is a scanning problem, not a boundary problem | Two local role passwords reached a transcript through Playwright's own `--trace on`, inside the working directory, by a permitted tool, following every rule. Nothing in this plan covers it. Round-2 **C16** |

**Total: ~23.5 engineer-days to M6**, one person who knows this repository, against `JUDGE-cost`'s
~12–18-day estimate for the same core. The difference is the mutation gate, the two verify paths, M0, and
the first real night. **Treat the order as the deliverable and the dates as an estimate.**

---

## 5. What round 2 must decide

Forty-one round-2 questions exist across the eight specs, the adapter contract and the two red teams.
Deduplicated, they are thirty-one. Below they are split into the ones that **genuinely block building**
and the ones that do not, and the blocking list is in **rank order**. The `A…` / `B…` / `C…` labels are
ids used elsewhere in this document; the order on the page is the ranking, not the label.

**Three things round 2 must not be asked**, because they are disagreements between our own documents and
not questions for him: YAML or JSON for the control file (four specs already shipped JSON; ADR-08 settles
it); which of six state roots is right (ADR-05); and whether `capacity.soft_pct` is 80 or 85 (he said 80
at [171]).

### 5.1 Блокери — без відповіді на це неможливо будувати

**A8 · Що таке «контрольований» і що таке «автономний» ран.**
Ти сам попросив, щоб я приніс тобі варіанти, а не вирішував за тебе [082]. Ось один, і другого поки
немає. Режим — це політика над **однією подією**: оркестратор зараз має діяти, і жодне налаштоване
правило не дає відповіді. «Контрольований» кладе цей момент у канал питань і тримає **цей** тікет — решта
тікетів ідуть далі, як ти й просив у Д6. «Автономний» дозволяє судді вирішити і дописує рішення разом із
фактами, які він бачив. Чесна ціна цього варіанту: він **вужчий**, ніж твої слова. Сесія, яка впевнено
помиляється, до цього моменту ніколи не дійде, і в готовому рані не буде нічого, що відрізняє «сумнівів
не виникло» від «всі сумніви задушили». Це твій вибір — прийняти, змінити чи відкинути.
→ *Блокує:* `run.mode`, `authority.*`, весь шлях ескалації, звіт про рішення, і кожне інше питання про
режим рану. Це передумова, а не одне з питань.

**A2 · Чи має оркестратор перевіряти свої власні дії.**
Ти вирішив, що перевірку роботи робить процес, і я цього не чіпаю. Але є вужча річ. Мердж, який зробив
**сам оркестратор**, надрукував «Already up to date» і не переніс нічого — гілку злили саму з собою.
Жоден процес цього не перевіряв, бо дію зробив не процес. Я хочу дозволити оркестратору перевіряти
**тільки власні операції**: що мердж справді зрушив гілку, що крок, який він мав запустити, запустився,
що те, що він мав зупинити, зупинилось. Роботу агента він не перевіряє і тестів не вимагає. Це шість
рядків і воно працює без тестів і без репозиторію особливого вигляду. Це в межах твого правила, чи це вже
те, чого ти не хотів?
→ *Блокує:* `ops.json`, перевірку мерджу, `harvest_evidence` і пункт A3. Якщо «ні» — чотири механізми
виходять з плану, і ми свідомо приймаємо, що мовчки пропущена стадія перевірки може знову випустити
п'ять фаз.

**A7 · Який саме другий акаунт для сторожа.**
Ти казав: «запускати якогось агента раз в N годин на якійсь іншій підписці» [246]. Сторож — це ~60 рядків,
він не читає квоту і не питає модель: він просто пробує взяти замок. Якщо взяв — оркестратор мертвий, і
це доведено, без таймаутів і без здогадок. Але він мусить жити під **іншим** акаунтом, і назвати цей
акаунт можеш тільки ти. Зараз сторож **вимкнений за замовчуванням** — і це означає, що саме той клас
поломки, яким закінчився попередній ран, відкритий на чистій інсталяції.
→ *Блокує:* єдиний захист від мертвого рану. Це найгірший дефолт у всьому плані.

**A9 · Що саме можна віддавати на автономне виконання.**
Твої слова: «людина повинна сама налаштовувати, що саме вона може віддавати на автономне виконання, а що
взагалі ні» [107]. Це єдиний список, про який ти сказав, що його маєш писати ти. Я **не** поставив
дефолту — один із варіантів архітектури поставив «усе», що є рівно протилежним до твоєї фрази. Питання:
цей список — це перелік типів дій (мердж, видалення, зміна чужого тікета, витрати грошей), чи перелік
тікетів/проєктів, чи щось третє?
→ *Блокує:* форму ключа `authority.autonomous_ops` і майстер налаштування.

**A6 · Три невдачі поспіль — що саме зупиняється.**
Ти дав рівно два варіанти — повідомити і зупинитись, або просто зупинитись — і сказав, що все поза цими
двома потребує твого дозволу. Але ти також сказав «В який момент не знаю» [442]. Три специфікації
написали три різні відповіді: зупинити **тікет** і вести ран далі, зупинити **ран**, або зупинити
**лінію** (що вже нічого не означає, бо вона й так закінчилась). Я поставив «зупинити тікет, ран іде
далі», бо інакше один флакі-тікет о 02:30 вбиває чотири здорові. Правильно?
→ *Блокує:* `failures.scope`. Різниця між цими двома прочитаннями — це чотири зроблені тікети або чотири
незроблені.

**A10 · Запас ліміту для тебе самого.**
Це питання інтерв'юер тоді загубив, і воно не потрапило в аналіз. Зараз оркестратор може витратити ліміт
до нуля, і зранку тобі може не лишитись нічого на власну роботу. Треба лишати запас — і якщо так, скільки
відсотків? Поки ти не відповіси, префлайт друкує це питання щоразу.
→ *Блокує:* нічого технічно, і блокує **твій ранок**. Я не буду вигадувати резерв на акаунті, в якому ти
сам працюєш.

**A5 · «Але, так, це максимум» — два прочитання.**
Про файл заборон ти сказав цю фразу [357], і її можна прочитати двома способами. Перший: плагін не має
права робити нічого більшого за цей файл — ні пісочниць, ні списків заборонених команд, нічого. Другий:
один файл — це максимум, який **ти сам** готовий вести руками, а те, що плагін робить сам, без твоєї
участі, під цю стелю не підпадає. Яке з двох?
→ *Блокує:* A1, A4, і взагалі те, скільки цей плагін має права робити. Одна специфікація на цій підставі
**відмовляється стартувати**, якщо файлу заборон немає — а це рівно та «окрема обов'язкова процедура»,
яку твоя ж фраза виключає. Я поставив «попередити і працювати далі».

**A1 · Межа доступу: той простий варіант, який ти сам назвав.**
Ти сказав, що не хочеш детерміністського варіанту, бо це оверінжиринг [370]. Але те, що тобі тоді описали,
— це **окреме середовище, контейнер**. А двома рядками раніше ти сам сказав інше: щоб «в оркестраторі був
прописаний шлях, до чого він має доступ» [366]. Є спосіб зробити рівно це — щоб цей список шляхів
перевіряла операційна система, а не модель: один рядок у налаштуваннях, нічого встановлювати не треба,
сесія лишається звичайною сесією. Це для тебе той самий оверінжиринг, чи це і є той простий надійний
варіант, про який ти казав? Я **не** поставив дефолту на жодну сходинку — ти просив варіанти на вибір
[378]/[381], а не рішення.
→ *Блокує:* R1-16 і весь пункт I3. І чесно: другий твій випадок — твоя власна паралельна робота в тій
самій папці — **не закривається жодним із варіантів**, і в усьому обстеженому полі його не закриває ніхто.

**A11 · Канал питань: де він.**
Ти закінчив цю відповідь словом «Крапка»: місце визначається користувачем [449]. Тому я **не** поставив
дефолту — і це означає, що ран, запущений зі скрипта чи з крона, стартує без каналу, а о 02:41 питання
нікуди не потрапляє і ран чекає вічно на відповідь, якої ніхто не побачить. Пропозиція:
`<project>/.orchestrator/QUESTIONS.md` як **підказку**, яку префлайт показує і просить підтвердити, і
перший ран не стартує, поки ти не вибрав. Плюс одна деталь із твоєї ж практики: на <work-project> у тебе
реально працювали **два** файли — в один сесії писали питання, в другий ти писав відповіді, і сесіям туди
писати було заборонено. Я зробив один файл із двома огорожами всередині. Так зручніше, чи два файли, як
було?
→ *Блокує:* Д6 цілком, і `when_only_blocked: wait` без каналу перетворює ран на тиху вічність.

**A3 · Вердикт, підписаний тим, хто робив роботу.**
У тому рані п'ять фаз пройшли з файлом перевірки, де написано «перевірив той, хто це й робив». Ніхто цього
не спіймав, крім людини очима. Я зробив так, що оркестратор читає вердикт процесу, але **не приймає**
його, якщо в записі стоїть, що перевіряв той самий виконавець. Це одне порівняння рядків. Це нормально,
чи це вже втручання в перевірку, яку ти віддав процесу?
→ *Блокує:* оракул завершення для GSD. Залежить від відповіді на A2.

**A4 · Рядок без помітки у файлі заборон.**
У файлі заборон я зробив помітки типів: `never`, `owner-only`, `ask-first`, `prefer` — бо ти сам сказав,
що обмеження бувають «різного типу» [357]. Якщо ти напишеш рядок **без** помітки — як його читати? Як
абсолютну заборону чи як побажання? Я поставив «як абсолютну заборону», бо помилка в інший бік коштувала
тобі стека. І окремо: чотирьох типів досить, чи типи інші?
→ *Блокує:* як плагін читає твій власний файл. Залежить від A5.

### 5.2 Важливі, але не блокують перший ран

**B2 · Видимість сесій.** Ти назвав чотири варіанти і попередив, що з headless «треба бути дуже обережним»
[324], і підтвердив це [328]. Я зробив headless-first, а перехоплення живої лінії — це зупинка,
перезапуск і перезалив контексту. **Це найбільше відхилення від підтвердженого тобою рішення в усьому
плані.** Лишаємо, чи інтерактивні вікна потрібні тобі з першої ночі?

**B3 · Ворк трі: що віддаємо.** Твоя дефолтна пропозиція — кожне завдання в своєму ворк трі від головної
гілки [433]. Гет шіт дан усередині сам нарізає собі ворк трі від віддаленої головної гілки, і коли твоя
база з нею не збігається, він **тихо** перемикається на послідовне виконання — це перевірено сьогодні на
твоєму ж проєкті. Сьогодні обидва варіанти разом не працюють. A) оркестратор створює ворк трі, ГСД
всередині працює послідовно (зараз стоїть це); B) ГСД створює сам, оркестратор ворк трі не чіпає.
«З цим треба поєднювати» — це завдання, яке ти дав, а не рішення, яке ти прийняв.

**B4 · Вартовий раз на чотири години.** Один виклик моделі кожні чотири години, на іншому акаунті, з трьома
входами і **одним** питанням: «чи цей ран щось зробив за останні N годин, і якщо ні — чому?» Це ~8 викликів
за ніч і це єдине судження в усьому плані, яке не виведене з наперед написаного предиката — тобто єдине,
що ловить ран, який живий, зайнятий, витрачає гроші й не виробляє нічого. Зараз вимкнено, бо потребує
другого акаунта (див. A7). Вмикаємо?

**B5 · Порядок черги.** Жодна специфікація не написала планувальника: нічого не каже, який тікет беруть
першим, на яку платформу, і що робить лінія, яку весь час відсувають. Я зробив: порядок за
(пріоритет, глибина залежностей, id); повтор іде на ту саму платформу, крім випадків ліміту чи
авторизації; лінія, яку відсували довше 90 хвилин, отримує наступний тікет поза чергою, один раз, і це
пишеться в журнал. Це **моя** вигадка від початку до кінця. Годиться?

**B6 · За що будити тебе вночі.** Ти сказав, що сповіщення мають бути, але не сказав, за що саме. Я вибрав
сім подій: ран зупинився · жорсткий ліміт · ліміт неможливо прочитати довше пів години · три однакові
падіння · лишилася тільки заблокована людиною робота · дошка розсинхронилася · сторож перезапустив
мертвий ран. Що з цього прибрати і чого бракує? І окремо: чи є тихі години, коли не приходить нічого —
навіть про те, що ран помер?

**B7 · Два рани на одному репозиторії.** Замок стоїть на **проєкті**, а не на рані, тому два рани на
одному репозиторії неможливі взагалі. Це саме те, що ти мав на увазі під «двох оркестраторів бути не
може», чи ти хочеш мати змогу гнати два мілстоуни одного репозиторію паралельно?

**B8 · `acpx` — вмикати чи ні.** Є готовий шар для запуску сесій, який знімає цілий клас минулих поломок.
Перевірка показала дві речі: він **не завантажує твої користувацькі налаштування** за замовчуванням — а
там живуть ГСД, усі твої плагіни, хуки і дозволи — і «запінити acpx» не пінить адаптер, який реально
запускає твій код. Обидва лікуються, обидва в плані. Я зробив його вимкненим і додав **один експеримент,
який треба провести до першого рядка коду**: підняти сесію з виправленням і спитати, чи бачить вона
`/gsd:execute-phase`. Якщо ні — усе це не має сенсу. Проводимо?

### 5.3 Можна відповісти пізніше

| # | Питання | Що зараз |
|---|---|---|
| **C1** | Куди оркестратор пише свої коментарі — на дошці коментує, у локальний файл пише лише один рядок статусу, весь лог тримає окремо. Так, чи лог має лишатись у самому файлі завдання? | дошка = дзеркало |
| **C2** | Пороги контексту — на якій шкалі? На твоїй машині два числа розходяться на ~13 пунктів, і статус-рядок весь рік показував одне з них. Показувати обидва в момент, коли ти ставиш поріг? | `context.basis` обов'язковий |
| **C3** | Один тікет — ланцюжок сесій. Там, де компакт ззовні запустити не можна, єдиний спосіб — закрити сесію і відкрити нову з підсумком. Це ок для твого обліку? | ланцюжок, не поле |
| **C4** | Стан рану лежить у `~/.orchestrator/`, а не там, де в решти твоїх плагінів — бо інакше сторож на другому акаунті фізично його не знайде. Прийнятний компроміс? | `$HOME/.orchestrator` |
| **C5** | Як це називати. Всередині є об'єкт «лінія» = платформа + провайдер + акаунт + роль. Тобі зручніше «лінія», «сесія» чи інакше? | «лінія» / Slot |
| **C6** | Тікет, який оркестратор створив сам собі (Д9) — він створюється як `backlog` і чекає на тебе зранку, а не береться тієї ж ночі. Правильно? | `backlog` |
| **C7** | Конфіг під перемикачем профілів: у жодному профілі немає теки `shared/`, тож два з шести слотів завжди порожні. Я читаю обидва місця і показую, звідки що взялося. Це відступ від твоїх же правил — лишаємо? | fallback увімкнено |
| **C8** | Дошці бракує потрібного статусу: відмовитись підключати, створити статуси самому, чи працювати без нього? | відмовитись |
| **C9** | Скільки стежити за тікетом після завершення (Д9 — про вже зроблену роботу)? Доба, тиждень, чи поки живий ран? | 24 години |
| **C10** | Стек, від якого залежить завдання, впав о 3-й ночі: тримати й чекати, написати тобі й тримати, чи не звертати уваги? | тримати й повідомити |
| **C11** | Чи має питання мати дедлайн за замовчуванням, після якого спрацьовує fallback? Зараз ні — ран просто чекає, як ти й просив. | без дедлайну |
| **C12** | Залишки мертвого попереднього рану (~150 томів минулого разу): бачить, показує точну команду на кожен пункт, не чіпає. Чи дозволяєш прибирати те, що явно позначене цим інструментом і чий ран точно мертвий? | не чіпає |
| **C13** | `stop-custom`: якщо ти вкажеш виконуваний файл — запустити його; якщо текст — віддати моделі перекласти в команди. Дозволяєш запускати твої скрипти, чи лише текст? | обидва, текст fail-closed |
| **C14** | Щоб `orchestrator status` працював у звичайному терміналі **безкоштовно**, треба покласти виконуваний файл у `~/.local/bin/`. Слеш-команда завжди коштує один хід моделі. Ставимо? | питає один раз |
| **C15** | ClickUp не вміє дешево відповідати «чи змінилось» і не має окремого поля про зміну опису — щоб дізнатись, треба щоразу тягнути завдання цілком, при бюджеті 100 запитів/хв. На GitHub це безкоштовно. Приймаємо ціну, опитуємо рідше, чи кажемо «ClickUp — для читання і статусів, не для стеження»? | не збудовано |
| **C16** | Паролі минулого разу потрапили в транскрипт через власний `--trace on` Playwright — усередині робочої теки, дозволеним інструментом, за всіма правилами. Жодна межа і жоден файл заборон цього не закриває: потрібен сканер виводу. Окремий пункт на наступний раунд? | не закрито |
| **C17** | GLM на тарифі Max пише «2+» одночасних сесій, що не є числом, і після трьох порушень акаунт банять. Яке число ставимо жорсткою стелею? | `2` |
| **C18** | Kimi пулить усі пристрої й ключі в один пул квоти — дві лінії на одному акаунті не подвоюють швидкість, вони ділять її навпіл. Заводимо окремі акаунти чи тримаємо одну лінію? | попередження |
| **C19** | Оновлення платформ: патч — попередити і працювати; мінорна чи мажорна — не стартувати, поки не підтвердиш. Прийнятна жорсткість? І чи дозволяєш нам вимикати автооновлення в **твоїх** файлах, чи ми лише кажемо, який рядок змінити? | `patch: warn, minor: refuse`, твої файли не чіпаємо |
| **C20** | Ім'я і міграція: новий плагін `orchestrator`, старий `harness` лишається недоторканим поруч; ти видаляєш його сам, коли новий відпрацює нормальну ніч. Так, чи одразу позначити старий застарілим? | живуть поруч |
| **C21** | Дві команди, яких ти не називав: `sync` (перечитати дошку, коли там перейменували статуси) і `remove` (прибрати конфіг і стан). Обидві є в базовому наборі твого маркетплейсу. Потрібні? | є |
| **C22** | Що вважати «кроком» у софт-режимі. Для ГСД — його власна межа кроку; для процесу без кроків я поставив «кінець ходу». Ок? | кінець ходу |

---

## 6. Risk register

Ranked by probability × damage. **Mitigation in the plan** names the milestone that carries it;
**residual** is what is left over and is *not* mitigated anywhere. Probability is INFERRED throughout,
from the failure record's own recurrence ranking.

### 6.1 The register

| # | How it fails | P | Damage | Mitigation **in the plan** | Residual, **not** mitigated |
|---|---|---|---|---|---|
| **R-1** | **The run dies and nothing revives it.** The doctor and the sentinel both ship **off**, because both need a separate account, if the user configures one. This is exactly how the previous 34-hour run ended, and afterwards a dead run flagged itself every three minutes for about five days, 1,085 times, unresolved | High | Night-ending | The doctor is built at M6 and is ~60 lines; its whole health check is *try to take the lock*, with no TTL and no heuristic, plus two steps nobody else has (journal not growing → hard stop; work not moving → notify only, never kill). `caffeinate -i` bound to the supervisor's own pid. The sleep fence at M1 | **The default is `false`.** Until he answers A7, a dead run stays dead until morning. The plan's own worst default, named as such |
| **R-2** | **The fact sheet is the ceiling.** Everything removed from the model moves into bash, and everything bash cannot see the model is never shown. The run's worst recorded lane — 3,466 of 3,626 Bash calls as `echo idle`, 445k tokens, 77 % of a window — reads *healthy* on process-alive, event-file-growing and engine-probe | High | High | Two lines in the renderer (`Δpct/hour` and the top repeated tool call) turn that exact lane into a defect on the sheet; `ctx_refill_alarm` is a **defect** predicate that tells the lane to end its turn rather than a compaction predicate that hides it; the detector scorecard reports an unfired predicate as **`unproven`, never `clean`** | **The coverage is still exactly the list of things someone thought to render.** The next failure of this shape will be one nobody rendered. The sentinel (B4) is the only mechanism in the whole research that is not derived from a pre-written predicate, and it is off |
| **R-3** | **The compound defaults produce a system that cannot run unattended.** `controlled` + `may_decide: false` + no question deadline + wait forever + silence = park on the first uncertainty and wait, with nothing printed. Every row is a correct reading of one of his answers | High | High | Preflight prints the compound in one sentence; `authority.autonomous_ops` and `questions.channel` have **no default** and are asked; A8 and A9 are the top two blocking questions | Nothing stops him accepting all seven defaults and getting a product he did not want. The compound line is a warning, not a gate |
| **R-4** | **The notification reaches nobody.** `notify.channel: terminal` *always* verifies, so all three verification tiers pass while five events on a real night land in a JSON file on a sleeping laptop | High | High | Preflight prints one line saying so whenever `when_only_blocked: wait` is also set; the channel proof is a **real delivered message**, and a `getMe`-shaped check is refused (a bot kicked from the chat still passes `getMe`) | A printed line at 22:41 is not a delivered message at 03:12. Until he configures a real channel, Д11's silence and Д7's wait-forever compose into an indefinite block nobody is told about |
| **R-5** | **M0 is skipped and the spec set is built as written.** Six state roots, two control planes, two ledger names, two "Lane"s, two task vocabularies, seven defaults registers and two exit tables. The simulated night dies at 02:58 because he edited a finished ticket, teardown walks a file that does not exist, and the owner's 02:00 edit is in a directory nothing reads | Medium | Night-ending | M0 is one day, it is first, it is paper, and its exit criterion is that all 41 red-team findings are closed in writing | If M0 is treated as optional because it produces no demo, everything downstream is built twice. This is the cheapest day in the plan and the easiest to skip |
| **R-6** | **The judge's verdict is unaudited.** It is recorded with the sha1 of the fact sheet it saw, so a wrong verdict is reconstructible afterwards — but nothing contradicts it in flight | Medium | High | `judge.on_unparseable: defer`; waiting is the fail-safe everywhere; the trip watermark stops a verdict re-firing on its own effect; `decisions.ndjson` makes every verdict replayable | **R1-13 [344] forbids the orchestrator adding checks of its own**, and this is his decision taken under the evidence at [342]. The cost lands here and it is not mitigated. It is his to revisit |
| **R-7** | **The invariants are claims, not properties.** Every commit gate in the previous generation was found broken **by mutation rather than by failing**, and six of seven deliberate defects survive the current 51-test suite | Medium | High | ADR-33: no test enters the suite until its named mutation has been seen to turn it red; both blast-radius lints land at M1, before there is code to violate them; a grep asserting a string is **absent** is one of the very few checks that cannot pass vacuously | Mutation coverage extends to the invariants somebody thought to write. `ARCH-reliability`'s own sentence applies to this plan as much as to its author's: *"until those tests exist and are verified by mutation, this architecture is a claim, not a property"* |
| **R-8** | **acpx removes GSD from every session it starts.** `CLAUDE_CODE_DEFAULT_SETTING_SOURCES = ["project","local"]` excludes user settings, where `enabledPlugins`, `hooks`, `permissions`, `skillOverrides` and his whole plugin set live | Medium | Night-ending *if adopted* | acpx is **off by default**; `ACPX_CLAUDE_INCLUDE_USER_SETTINGS=1` is mandatory when on; a lane-local `.claude/settings.json` re-disables singleton plugins by name; a preflight gate asks a throwaway session to list its slash commands and fails the run if `/gsd:execute-phase` is absent; **one experiment decides the whole adoption before any code** | Whether user-level *skills* survive the exclusion was **not settled** — `~/.claude/skills/gsd-*` is where ~70 GSD skills actually live, and `skillOverrides` is definitely lost. That is the single highest-value thing to test first, and it is untested |
| **R-9** | **Two heavy lanes starve the machine his own stack runs on.** His container was `OOMKilled` by two concurrent `docker compose up --build` on an 8 GB Docker VM, with no live alert | Medium | High | `limits.max_concurrent_builds: 1`, serialising only steps a lane **declares** `heavy: true` — a declared-cost queue, not resource awareness, so it stays inside his deferral at [163] while closing the one incident that actually happened; `concurrency.max_lanes: 2` keeps the parallelism that worked twice | **Machine-resource awareness is explicitly deferred by him** [160]/[163]. Two heavy lanes that do not declare themselves heavy can still do it. No access-control mechanism addresses resource contention and this plan does not pretend one does |
| **R-10** | **His own parallel editing in the same checkout.** R1-16 case 2 | Medium | High | Nothing. Process-and-container ownership via the ledger and worktree anchoring reduce it to the file level and stop there | **Unsolved across the entire surveyed field** — thirteen of eighteen tools isolate with a worktree and not one protects the human's concurrent edits in the same checkout. He routed this to a separate agent [378]/[381]. It must be invented; this plan does not invent it |
| **R-11** | **Secrets reach a place nobody scans.** Two local role passwords printed in clear text into a session transcript by Playwright's own `--trace on` — inside the working directory, by a permitted tool, following every rule | Medium | High | Nothing | No line writable in the red-line file would have prevented it. It is a **scanning** problem, not a boundary problem, and no design in the set covers it. C16 |
| **R-12** | **A lane runs `pkill` itself.** The ledger constrains the orchestrator, not its children | Medium | Medium | The build lint covers plugin source; the red-line file is read by every agent | A lint cannot lint what a model types into a shell at 03:00, and on Kimi and pi there is no sandbox beneath the text file at all |
| **R-13** | **The platform moves under the run.** Amp shipped five releases in fifteen hours; Copilot 835 versions in twelve months; Kimi auto-updates by default, staging binaries in the background | Medium | Medium | `version.on_mismatch: {patch: warn, minor: refuse}`; the version is pinned in preflight and recorded in the journal on every platform in every process; `version.autoupdate: assert_only` — we refuse and name the line rather than editing his files | On several platforms auto-update can only be disabled by editing his own config, which this plan refuses to do. A refusal at 22:41 is the whole defence |
| **R-14** | **The scheduler is my invention and he rejects it.** Queue order, slot affinity and the starvation bound are the largest thing here he never spoke to | Medium | Medium | Three pure functions with no side effects, all three configurable, all three journalled when they fire; B5 asks him directly | If the answer is "I wanted something else entirely", M4 and M5 are unaffected and only the ordering changes. Cheap to be wrong about |
| **R-15** | **A neglected adapter keeps declaring `native` after the platform has moved.** The manifest is a claim with no independent oracle, written by the same author from the same reading as its own fixtures, and trusted at exactly the hour when nobody is watching | Low | High | `orchestrator:adapter verify` fails exit 65 when `compact` returns success without a proof, when `send` reports anything stronger than `accepted` from an enqueue receipt, and when `readCapacity` returns a scalar or lets an unparseable 200 become zero; `negotiate.on_unknown: impossible` makes a new requirement fail **every old adapter closed**, so a neglected adapter fails **forward** | That is a containment, not a cure, and the spec that proposes it says so. Building only two adapters is a discipline, not a mechanism — nothing refuses a third that nobody has time to maintain |
| **R-16** | **One `echo >> journal.ndjson` outside the appender.** Every guarantee about evidence, epochs and legal transitions depends on the appender being the only route from an event to a state, and the appender is bash | Low | High | A lint that fails the build on any write to `journal.ndjson`, `ledger.jsonl` or the lease that is not through the four named helper functions | It is a rule about the repository, not about the running system, and it is the softest thing in the whole design |
| **R-17** | **Round 2 changes what «хард» means.** Д12 is the one item the analysis marks UNRATIFIED outright | Low | Low | The vocabulary lives in `stop.verb_map`, a data table. A change is a table edit, not a rewrite; `docs/RATIFICATION.md` records which items rest on an unratified restatement | Twenty-two other restatements in the corrections record are unratified and **not** labelled, including the hard/soft vocabulary this design's `apply` field inherits. The register makes them visible; it does not make them true |
| **R-18** | **The estimate is wrong in the same direction the last one was.** The previous generation was *smaller* than three of the four designs while being demonstrably insufficient | High | Low | The order is the deliverable, not the dates. The first end-to-end run is at **M5**, not M6 — a ticket goes in, a lane runs, the queue drains, teardown asserts, the process exits 0 — and M6's judge and watchdog are things the run works without, badly, for one night | Nothing. Treat every number as a ratio |

### 6.2 Where the research disagrees with itself, and which side I trust

Four places. In every one of them the later document read the code and the earlier one did not, and in
every one I trust the later document.

**1. Quota sensing that drives an action.** `ADOPTION-VERDICT` §5 lists R4 as one of four requirements
with *"no working implementation anywhere"* and says *"only a 473-star project has the whole thing."*
`LANDSCAPE` §5 checked the field and found it **solved four times over**: claudexor's
`limit_action: auto | fail | ask | rotate` resolving by credential kind so a spent subscription never
falls through to a metered key; Gas Town's `quota_dog` ticker driving keychain swaps and session
restarts; ralphex's `wait_on_limit`; ralph-claude-code parsing Claude's `rate_limit_event` for
`status:"rejected"` and distinguishing the plan limit from the Extra Usage quota. **I trust `LANDSCAPE`**
— it names files and line numbers and the verdict names none. What is genuinely missing inside R4 is
narrower and this plan should say it precisely: **nobody implements save-and-resume**, and the best
sensing in the field is attached to nothing. That changes the plan's emphasis, not its shape: ADR-16
stands, and claudexor's rotation policy is worth reading before anyone writes a third one.

**2. Board write-back.** `ADOPTION-VERDICT` §5 says *"only Symphony has even specified it."* Symphony
specified the **opposite** — its SPEC §11 is *"a portable read kernel for scheduling"* and instructs
implementers *"do not add generic comment/state/attachment CRUD merely to make providers look alike"* —
while four projects implement or specify write-back (Cyrus, Sortie, ralph-claude-code, and Paperclip with
an entire normative specification for it). **I trust `LANDSCAPE`.** The real gap is the clause after the
semicolon: **nothing anywhere re-reads a ticket's *description* mid-run and changes what the agent is
doing.** That is Д8 and Д9, it is genuinely unowned, and ADR-15 is where this build spends its
differentiation.

**3. Whether a headless question is terminal.** `ADOPTION-VERDICT` "Change 2" reads the field as unanimous
— *"in a headless session, a question is a terminal outcome, not something to answer"* — and builds an
architectural fork on it. Two documents contradict it independently. `LANDSCAPE` §5 finds the field
**split, with both sides argued explicitly**: Sortie ADR 0025 makes a human-input request a dedicated
non-retryable terminal on the ground that *"an unattended run contains no one who can grant permission"*,
while claudexor parks it as a durable pending interaction with four resolution terminals, answerable later
from the CLI. `RED-acpx` then shows the specific evidence the verdict cited is misread: the refusal is
gated on `agentInfo.name === "antigravity-acp"`, a Claude question becomes an ACP elicitation that the CLI
*cancels* rather than failing, and exit 5 requires *every* permission in the turn to have been denied with
none approved. **I trust both correcting documents** — one read four codebases, the other ran the binary.
Consequence: ADR-31 keeps the terminal-for-the-attempt shape because it is the cheap and safe side, but it
keeps it as **a choice with a stated cost**, not as a fact about the industry, and the acpx runtime
transport is recorded as the only working R8 implementation found rather than as a closed door.

**4. `acpx`'s stability, and the real version risk.** `ADOPTION-VERDICT` justifies pinning with
*"40 `### Breaking` sections in 44 releases"*. `RED-acpx` parsed the changelog: **36 of the 40 headers are
empty template artefacts**, there are **three** released breaking changes in the project's entire history,
and **zero** to subcommand names, exit codes or `--format json` in 43 releases. The rule (pin) is right and
the stated reason is fiction. Meanwhile the verdict's proof that exit codes are stable — a CHANGELOG grep
— is the exact method that cannot see the one real exit-code change, which happened in code
(`PERMISSION_DENIED` 4→5) and never reached the CHANGELOG. And the actual risk it missed entirely:
pinning acpx pins the Claude adapter to exactly `0.76.0` while upstream shipped `0.77.0`, `0.78.0` and
`0.79.0` in the three days around it, resolved through `npx -y` **at agent launch**. **I trust
`RED-acpx`** — it cloned the repository, ran `git log -L` over the exit-code block across 613 commits,
installed the package and executed the exit codes on this machine, including breaking the process-tree
cleanup on purpose with a deliberately leaked grandchild (it held; exit 3 on the nose, both descendants
reaped). ADR-30 is written against its findings, not the verdict's.

**One more disagreement, internal to the judging.** The three judges ranked the four architectures in
three different orders, and `JUDGE-survival` ranked this plan's base design **last**. That is not noise
and it is not resolved by averaging. Its case is specific: minimal is blind to the alive-but-useless lane
and ships its own excellent watchdog **off**. Both are closed here by grafts of a few lines — and the
watchdog is still off, which is why R-1 is the top risk in the register rather than a footnote.

---

## 7. What I would do differently from the old harness, and why

Ten things. Each is tied to something the field notes actually recorded, not to a preference.

**1. Nothing types into a running session, ever.** The old harness drove terminals: `send`, `key`, a
nudge, a heartbeat file, an attention file, screen capture. It produced five instructions that were never
delivered — **two of them his own**, `push master` and `carry on with the queue`, sitting unsubmitted in
an input box while the engine log recorded them as nudged — a 149-minute stall because an Enter never
landed with nothing detecting it, silent truncation above ~200 characters, and one recovery attempt that
cleared the pending line without submitting it. The new design deletes the capability. *What it costs:*
nothing in this design can talk to a session that is already running except through the adapter's own
protocol channel, and taking over a lane is a stop–relaunch–reseed handoff. That is the largest single
deviation from a decision he confirmed, and it is round-2 question **B2**.

**2. Liveness is a process I started, not a screen I read.** The old harness inferred life from a
heartbeat that fires *between* turns — so a validator running a 14-minute suite does not heartbeat at all,
and the watch nudged six healthy sessions, 33 nudges in the run, one every 62 minutes. The new design
checks `kill -0` **and** the pid start time against what was written before launch, and watches the event
file grow **during** a turn. *And it adds the one signal the old design's successor still would not have
had:* the top repeated tool call in the last 200 events, which is the only thing that separates
`w-phase-19` — 3,466 of 3,626 Bash calls as `echo idle`, 445k tokens, 77 % of a window — from a healthy
lane. It was stopped within one minute of being told to end its turn, by a human reading a transcript.

**3. The claim is one syscall.** The old allocator is unlocked and produced two files under one ticket id
in five rounds of five; the read-then-write shape measures 27 winners out of 50. `mkdir` cannot do that.
And the ordering around it — `start` before the launch, `result` last, the directory move as the only
commit — turns a crash into a **detectable orphan** instead of a false claim of completion, which is the
generic form of the merge that printed `Already up to date`.

**4. `unknown` is a verdict, not a zero.** The old limiter demands a `.limits` array the live endpoint no
longer has, so every read returns `UNREADABLE`; `on_unreadable: proceed` then returns 0 immediately; and
the hard stop is parsed out of the literal string `SESSION=?`, so it **can never fire**. It was provably
inert for days while reporting nothing wrong. The new default is `hold_dispatch`, buckets are enumerated
rather than named, a threshold on a vanished bucket is a loud configuration error, and a reading is keyed
on `(platform, base_url, account)` so it cannot be compared across a switch that moved the number 26 % → 6 %
by itself.

**5. Status costs nothing.** The old plugin routes `status` through a skill while the bash underneath it
already produces the JSON — ten status checks in a night is ten model turns. The new one is a bash script.
And `status.json` has **no `healthy` field**, because the old one computed `healthy` from an attention file
its own watch loop truncated every cycle, and would therefore have printed `healthy: true` throughout the
85 minutes in which `NO ONE IS BEING TOLD` was being written to the log.

**6. Nothing is rewritten in place.** The old `state/attention` was `: >`-truncated every cycle, destroying
a whole night of a second process's corrections, discovered by accident at 06:58Z. Here `journal.ndjson`,
`ledger.jsonl`, `decisions.ndjson` and `control.applied.ndjson` are append-only and only `status.json` —
a derived view — is replaced, atomically.

**7. Every identifier in a destructive command comes from a file, never from the environment.** The old
run destroyed his default Docker stack with a `docker compose down -v` that had no `COMPOSE_PROJECT_NAME`
exported, so it resolved to *his* project; the actor was never identified; a session had refused that exact
action as owner-only two minutes earlier; and separately `pkill -f 'playwright test'` killed an unrelated
lane because every lane's own prompt contains that string. Two build-failing lints, and the second one —
**no teardown argument may come from the environment** — is the one that would have caught the incident
that actually happened.

**8. A detector may not fire twice on its own effect.** The 85-minute loop, the 45-minute banner loop and
the condition flagged 1,085 times over five days are all one shape. A budget bounds the bill; a watermark
written `O_EXCL` **before** the action bounds the loop. And a governor never writes a string its own
detectors match into a file its own detectors read — the 85-minute loop matched a banner inside the
orchestrator's **own wrapped prose**.

**9. Durations are computed on a clock that does not jump.** The previous run ended
`orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may sleep)`. On wake, every staleness
reading says dead and the process object says alive, and both are correct. `mono` beside `at` on every
record, a 120-second grace after a detected wake during which nothing may be judged dead, and
`caffeinate -i` bound to the supervisor rather than to a watcher that can die first.

**10. Every check must be broken on purpose before it counts.** Every commit gate in the old generation was
found broken **by mutation rather than by failing**, and six of seven deliberate defects survive its
51-test suite today. A suite that greps prose can pass vacuously, which this repository's own working notes
already record. So: no test exists until its mutation has been seen to turn it red, and the two rules that
protect his machine land in the build **before there is any code to violate them**.

**And one thing I would keep.** The old run was not a failure — thirteen phases merged in the first 34
hours, eleven questions escalated to a channel rather than answered by assumption, two lanes ran
concurrently twice with no port or state collision, a timeout never force-killed a busy session, a process
gap was disclosed rather than buried, and the configured process's own plan checker and code review caught
real defects before they shipped. Those are the positive controls, they belong in the suite as regression
guards, and several of them are exactly what the new failure tests could break.

---

## 8. The four things to do before any code is written

1. **M0.** One day, paper, and every downstream milestone is built twice without it.
2. **The acpx experiment** (ADR-30, R-8): one throwaway session in a worktree, with and without
   `ACPX_CLAUDE_INCLUDE_USER_SETTINGS=1`, asked to list its available slash commands and skills. One cheap
   turn. It decides whether that adoption is possible at all, and nothing else about it matters until it
   is run.
3. **Put the eleven blocking questions of §5.1 to him**, in that order, starting with A8 — because round 2
   cannot ask him to ratify definitions of «контрольований» and «автономний» that nobody drafted, and
   because no question of the form *"is this default right?"* is answerable until §3 is the only register
   that exists.
4. **Write `docs/RATIFICATION.md`** before the first commit, so that nothing whose vocabulary is
   unratified gets built as anything but a data table.
