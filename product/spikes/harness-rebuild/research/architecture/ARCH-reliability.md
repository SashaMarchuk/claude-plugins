# ARCH-reliability — the orchestrator designed from its invariants outward

**Lens:** Reliability and state-machine first. **Date:** 2026-09-19.
**Author's remit:** design the whole orchestrator, end to end, through one lens — surviving the night.
**Requirements source of truth:** `../../round-1/ANALYSIS-01.md` with `../../round-1/TRANSCRIPT-01.md`
behind it; corrections graded in `../extract/corrections.md`.
**Reality sources:** `../platforms/ADAPTER-CONTRACT.md` (fifteen platforms, hands-on),
`../LANDSCAPE.md` (seventeen orchestrators, re-read live), `../adoption/ADOPTION-VERDICT.md`,
`../clusters/*-challenge.md`, and `plugins/harness/docs/FIELD-NOTES.md` (34 hours of the previous
generation failing in recorded ways).
**Owner's architecture rules that bind this design:**
`<baseline-marketplace>/requirements/OWNER-DECISIONS.md`
and `docs/config-levels.md` there.

## 0. How to read this

**Evidence tags.** **VERIFIED** — read in a primary source named here, or measured on this machine by
a document cited here. **CLAIMED** — a vendor, README or third party asserts it and nothing was read
behind it. **INFERRED** — my reasoning from the above; it is a design choice, not a fact.

**DEFAULT-PROPOSED.** The owner made nearly everything configurable and stated almost no defaults.
Every default below that he did not state is marked `DEFAULT-PROPOSED` with the failure it protects
against. Section 15 collects all of them in one table, which is the only page he has to review to
accept or reject the lot.

**Tension notes.** Where his decision and the evidence collide, the decision is designed for and the
tension is recorded under a **⚠ TENSION** heading. Nothing here quietly replaces a decision with
something I prefer. Section 17 lists the four places where a decision is not implementable exactly as
stated, says which clause is impossible, and prices keeping it.

**Naming.** The product is the **orchestrator** (N1, [118]). Inside it, three role-words are used
precisely and never interchangeably:

- **conductor** — the deterministic, model-free supervisor process. It holds the run lease, owns the
  journal, applies control, and dispatches. It never reasons.
- **orchestrator agent** — a model session that makes the judgement calls the owner delegated to it
  (R1-09 silence, Д9 conflicts, Д10 restart hygiene, Д3 teardown scope). It holds no lease of its own
  beyond a sub-lease, and it is replaceable mid-run.
- **warden** — the external health check on a different account/provider (R1-10 [246]).

The owner's word «оркестратор» covers the first two. Splitting them is the single largest design move
in this document and §1.2 justifies it against his own invariant.

---

# 1. The invariants

Everything else in this document exists to hold these nine. Each one states the rule, the mechanism
that enforces it, and the test that would catch its violation. An invariant with no mechanism is a
wish; FIELD-NOTES is 704 lines of wishes.

## I1 — Authority follows the lock, not a verdict

**Rule.** Only the process currently holding `run.lock` may dispatch work, mutate a board, write
`control.applied.json`, or append a mutating record to the journal. A process that cannot take the
lock does not act — it does not "decide the holder is dead and proceed".

**Why this shape.** The owner's invariant is *"якщо раптом одночасно два якісь оркестратори працюють,
то це не окей … Це треба відслідковувати і не дозволяти"* [300–302]. Every design that implements it
as *probe → verdict → spawn* inherits C6-A1 and C6-A2: the probe is blind across accounts (VERIFIED:
`claude agents --json` under two `CLAUDE_CONFIG_DIR` profiles returns completely disjoint rosters), and
the third verdict — *the probe errored* — is the recorded norm, not an edge case (VERIFIED,
FIELD-NOTES §11.7: `weekly_all=unreadable%` on six consecutive ticks, and an
`authentication_error` stretch of 1 h 22 m blinding every read). Making the lock itself the authority
removes the verdict from the critical path: the warden does not conclude anything, it *tries to take
the lock*. If it takes it, the previous holder is dead by construction — `flock` dies with its holder,
with no TTL and no heartbeat guess (the `dsh` flock contract, ADOPTION-VERDICT §4 item 7, CLAIMED but
matched by POSIX semantics, VERIFIED for local filesystems).

**Mechanism.** `flock(2)` on `<run>/lease/run.lock`, held open for the conductor's whole life, plus a
**fencing epoch**: `<run>/lease/epoch` holds an integer, incremented under the lock by whoever takes
it. Every journal record carries `lease_epoch`. The journal appender rejects any record whose
`lease_epoch` is lower than the highest already present. A process that lost its lock and did not
notice cannot corrupt the record — its writes are refused, loudly (Qwen's fenced-writer-lease shape,
ADAPTER-CONTRACT §6.7, VERIFIED there).

**Test.** Kill `-9` the conductor; a second conductor must acquire within one `flock` attempt, bump
the epoch, and refuse any late write from the first. `SIGSTOP` the conductor; a second conductor must
**fail** to acquire and exit 5, because a stopped process still holds its lock — which is the correct
answer, since a stopped orchestrator will resume.

## I2 — Only the lock holder is "an orchestrator", and there is exactly one of it

**Rule.** "Two orchestrators" means two lock holders of the same run, or two runs whose scopes
overlap. It does not mean two model sessions. An orchestrator *agent* session is a lane like any
other, with a sub-lease (`lease/agent.lock`) that at most one session holds at a time.

**Why.** R1-10's invariant and R1-08's *"запускати повністю новий оркестратор"* [204] collide head-on
(C6-A3, C5-A5): a context handover **requires** a period in which the old and new orchestrator both
exist, and [204] demands the handover be *guaranteed*. Under I2 they stop colliding, because the thing
that must be singular (the scheduler, the journal writer, the board writer) is the conductor, which
never needs compacting because it holds no context. The agent handover becomes an ordinary lane
replacement.

**Second half.** FIELD-NOTES §1.6 records the owner himself reading a terminal titled
`harness-question-q-screen-orchestrator` as a second orchestrator (VERIFIED). Terminal titles and
session names are therefore part of the invariant's surface: every lane's window title is
`orc/<run-id>/<role>/<lane-id>` and the string `orchestrator` appears in a title only for the lane
holding `agent.lock`.

**Cross-run half (C6-A12, unaddressed in the transcript).** Two *runs* on the same machine against the
same project are also not okay. `~/.local/state/orchestrator/runs.index.jsonl` records every run's
scope (project root, worktree roots, board id, label filter) under `machine.lock`. Preflight refuses to
start a run whose scope intersects a live run's scope, exit 5. Two runs on **disjoint** projects are
allowed and share only the capacity meter (§6.1).

## I3 — No result without an intent; no orphan without a reconciliation

**Rule.** Every operation that changes anything outside the run directory is written to the journal as
an `intent` record **before** it is attempted and a `result` record after. An `intent` with no
`result` is an **orphan** and blocks the lane until reconciled.

**Why.** This is the direct counter to the largest failure class on file: *reported success and did
nothing.* FIELD-NOTES §4.1 (a merge printing `Already up to date` / `Everything up-to-date` while
running the phase branch against itself), §11.4 (GSD's verify stage silently skipped for five phases,
each `NN-VERIFICATION.md` self-attributing `verified_by: the lane that built the phase`), §12.7 (26
refusal events in an audit log that never occurred), §11.7 (`#82`, still open: *"the `STOP` write is
still unconditional on the marker write succeeding, so a failed marker write leaves an unattributed
`STOP` on disk"*). All VERIFIED. The discipline is one line — append `start` first, `end` last — and
it converts a false claim of completion into a *detectable orphan* (ADOPTION-VERDICT §4 item 8).

**Mechanism.** §3.3 (journal format), §5.4 (idempotency keys), §11.3 (the reconciler).

## I4 — An `ok` outcome on a mutating operation requires admissible evidence

**Rule.** The journal appender refuses a `result` record with `outcome:"ok"` on any op declared
*mutating* unless it carries at least one evidence object of a kind listed as admissible for that op
in `ops.json`. There is no free-text success.

**Why.** *"Never report unevidenced success"* is one of the five invariants of this lens, and the
field evidence says an exit code is not evidence: Aider `main.py:1133` returns 0 on auth failure, rate
limit and success alike; pi `--mode json` exits 0 on provider failure; GLM exits 0 on quota exhaustion
*with* `subtype:"success"`; MiMoCode's exit code is always 0; `cursor-agent worker kill` reports
success and leaves the process at 100 % CPU (all VERIFIED, ADAPTER-CONTRACT §2.4). Sortie argues the
asymmetry that makes this worth the cost: advancing an empty issue *"moves work in a system you do not
own, removes it from the queue you do own, and puts it in front of a person,"* while withholding
*"leaves it where it was, in a queue you keep watching, with the withholding recorded"* (VERIFIED,
LANDSCAPE §4).

**Admissible evidence kinds** (`ops.json`, §3.6): `process_exit` (code + assertion the pid is gone),
`git_ref` (ref, before, after — read back after the op, never the command's word), `file_digest`
(path + sha256 + size), `http_status` (status + a named body predicate that must be true, never
HTTP 200 alone), `board_readback` (the board re-fetched and the field compared), `transcript_event` (a
typed event at a journal-recorded transcript cursor), `token_drop` (used-token count before and after,
for `compact`), `process_absent` (a pid that no longer exists and whose start-time does not match).

**⚠ TENSION.** R1-13 is explicit that *verification belongs to the configured process* and *"не роби
обмеження те, що вся робота потім буде мати тести"* [344]. I4 does not verify the **work**; it verifies
that **the orchestrator's own operation happened**. A merge either moved a ref or it did not, on any
project, with or without tests. The line is: the engine says whether the ticket is done; the journal
says whether the orchestrator's own step ran. Nothing here imposes a check on his work product.

## I5 — Never lose task state; the journal is the only truth

**Rule.** All run state is derivable from `journal.jsonl` alone. Every other file in the run directory
is a **projection** — rebuildable, never authoritative, and safe to delete.

**Why.** [171]: *"в нас в реєстрі має записуватись кожен стан, його виконання … для того, щоби було
відновити процес і продовжити, навіть руками."* And because the previous generation's status file was
destroyed by its own writer: FIELD-NOTES §2.1, `state/attention` truncated to zero bytes every watch
cycle, *"anything appended to that file by anyone else is destroyed within one watch interval"*, which
silently broke the context watch's only reporting channel all night (VERIFIED).

**Mechanism.** Append-only JSONL, `O_APPEND`, one `write(2)` per record, records capped at 64 KiB
(oversized payloads spill to `blobs/<sha256>` and the record carries the digest). Projections
(`status.json`, `lanes/*/lane.json`, `tickets/*.json`) are written by atomic rename and stamped with
the `seq` they were built from, so a stale projection is detectable rather than believable.
`orchestrator:reconcile --rebuild` regenerates every projection from `seq 0`.

## I6 — Always apply a stop within one control tick

**Rule.** A stop written into `control.yaml` takes effect no later than `tick.control_seconds` after
the write is complete, measured to the *decision*, plus a bounded, recorded deadline to the *effect*.

**Why.** Д12 [520–524]: *"команда записує у файл, який оркестратор читає кожен тік, і зміна
застосовується на наступному тіку."* The previous generation could not do this: its only escalation
was a bare Enter into a terminal, and FIELD-NOTES §1.3 measured **five instructions typed into sessions
that were never delivered**, §1.4 measured the nudge failing to submit stranded text twice, §12.1
recorded a 149-minute stall because an Enter never landed and *"nothing detected it"* (all VERIFIED).

**Mechanism.** §10. The stop path contains no model call, no network call, and no terminal typing.

## I7 — Clean up exactly what you started, and be able to prove what that was after you die

**Rule.** Every external resource the run creates is appended to `resources.jsonl` **before** it is
created, with an owner tag that is a property of the resource itself, not of an environment variable.

**Why.** Д3 [430]: stop what it started, *"щоби не залишати хвостів"*, without touching anything else.
R1-16 [366]: it must not stop tests it did not start. Read together they define a set no run can clean
— things a **previous** run started and did not live to stop (C8-A1), and FIELD-NOTES §11.11 records
the output: *"About 150 orphaned Docker volume pairs left by a dead prior run"* (VERIFIED). Worse,
C8-A2: provenance carried in `COMPOSE_PROJECT_NAME` does not survive a detached teardown process, and
FIELD-NOTES §11.5 records the owner's own default stack destroyed by exactly that (VERIFIED). And
C8-A3: tty and pid are both recycled by the OS, so the previous generation's tty-keyed close could
close the owner's own window (VERIFIED, `harness-term.sh:157`, `harness-run.sh:252`).

**Mechanism.** §12. Owner tags are written *into the resource*: Docker labels
`orc.run=<run-id> orc.project=<sha256(project_root)>` , git worktree paths under a run-scoped prefix,
process groups recorded with `(pid, start_time, argv_sha256)`, files under the run directory. Teardown
matches on the tag, never on a pattern over command lines — FIELD-NOTES §11.8:
`pkill -f 'playwright test'` killed an unrelated lane *because every lane's own prompt text contains
that literal string* (VERIFIED).

## I8 — Three verdicts, never two

**Rule.** Every observation the run acts on is a sum type with an explicit *unknown*, and every
unknown carries a sub-kind and a freshness. Liveness is `LIVE | UNKNOWN | DEAD`. Capacity is
`Window | Credit | Unknown`. Compaction is `proven | unproven | unsupported`. Board state is
`observed | indeterminate`. Nothing collapses an unknown into the adjacent certain value.

**Why.** C6-A2 (the third verdict happens every night), C4-A6 (`unreadable` is not a case he ruled on,
and the shipped default makes the limiter inert — VERIFIED: `harness-limits.sh:55-58` demands a
`.limits` array the live endpoint does not have, so `snapshot` returns `UNREADABLE` on *every* call,
`on_unreadable: proceed` then returns 0 immediately, and `stop_at` is parsed out of the literal string
`SESSION=?` so the hard stop *can never fire*). And claudexor's rule, the best-argued in the field:
*"stale quota never authorizes routing"* (VERIFIED, LANDSCAPE §4).

## I9 — A signal is admissible only where it is known to be sound

**Rule.** Each observation kind carries a declared **basis** and **provenance**, and a decision may
only use signals declared admissible for that decision in `signals.json`. A wrong number is worse than
no number (agent-deck's governing rule, VERIFIED, LANDSCAPE §4).

**Why.** Every cheap observable has a measured false-positive mode in the owner's own run (C6-A4,
VERIFIED throughout FIELD-NOTES): heartbeat age (§1.5 — six healthy sessions nudged; §12.3 — 33 nudges
in 32 hours), shell count (§2.2 — an `until grep … sleep 5` that could never match reads as work),
tool-call cadence (§3.1 — 3,466 of 3,626 Bash calls were the literal string `echo idle`), screen text
(§11.6 — the watch matched a usage-cap banner inside the orchestrator's *own wrapped prose* and looped
for 85 minutes; line 5620 of that log reads `NO ONE IS BEING TOLD`), and git activity (inadmissible by
R1-13/N2 — there may be no repo at all).

---

# 2. Processes, and who starts them

Five process kinds. Three are long-lived; two are transient. **None of them is a daemon the owner has
to install to run a job**, except the warden, which is opt-in.

| # | Process | Model? | Lifetime | Started by | Holds |
|---|---|---|---|---|---|
| P1 | **conductor** | no | the run | `orchestrator:run`, or the warden on takeover | `run.lock`, `lease/epoch` |
| P2 | **lane child** | yes (or no) | one dispatch | the conductor, via a platform adapter | `lanes/<id>/claim.lock` (held by P1 on its behalf) |
| P3 | **adapter** | no | one lane, or pooled | the conductor | nothing |
| P4 | **warden** | usually no | forever, periodic | `launchd` (opt-in) | nothing until takeover |
| P5 | **CLI** | no | one command | the owner | nothing; `status` is read-only |

## 2.1 P1 — the conductor

A single-threaded event loop in **Node** (the marketplace's resolver is already one deterministic Node
program — OWNER-DECISIONS 5.1 — and bash cannot hold a lock across a restart of its own subshells
safely). It is started in the foreground by `orchestrator:run` and re-parents itself via
`setsid`; its stdout is the run log, its stdin is `/dev/null` (ADAPTER-CONTRACT §2.4 invariant 3:
Codex hangs all night without `< /dev/null`; MiMoCode hangs forever — VERIFIED).

It does five things, in this order, every loop:

1. **control tick** (every `tick.control_seconds`, DEFAULT-PROPOSED **2 s**) — re-read `control.yaml`
   and the six config files; apply what changed (§9.3, §10).
2. **heartbeat** (every `tick.heartbeat_seconds`, DEFAULT-PROPOSED **5 s**) — write
   `lease/heartbeat` with wall clock, monotonic clock, `lease_epoch`, and `boot_id`.
3. **observe** (every `tick.lane_seconds`, DEFAULT-PROPOSED **10 s**) — adapter `status`,
   `transcript` from the stored cursor, `readContext`; append observations.
4. **schedule** (every `tick.schedule_seconds`, DEFAULT-PROPOSED **15 s**) — evaluate the run state
   machine, claim and dispatch, rebuild `status.json`.
5. **capacity** (every `tick.capacity_seconds`, DEFAULT-PROPOSED **3600 s** per account, plus
   event-driven) — §6.1.

It never blocks. Every adapter call is a child process with a wall-clock timeout
(ADAPTER-CONTRACT §2.4 invariant 4: `opencode run --attach` hangs with zero bytes on stdout, stderr
*and* the server log, reproduced twice — VERIFIED). A timed-out adapter call becomes an `UNKNOWN`
observation, never a failure verdict.

**It runs no model.** This is the reliability lens's central bet. Everything the owner delegated to
"the orchestrator's judgement" is delegated by the conductor to P2 in the `orchestrator` role, as an
explicit, journalled question with a bounded deadline and a declared fallback (§7.4).

## 2.2 P2 — lane children

One process per dispatch. Five roles, each a config-selectable lane definition:
`orchestrator` (the judging agent), `executor`, `verifier`, `watcher` (Д8's cheap ticket watcher),
`questioner` (answers a session's own question where the platform allows it, R1-11 [324]).

**⚠ TENSION with the owner's model.** He speaks of the orchestrator *spawning and judging* sessions
[231]. Here the conductor spawns and the orchestrator agent judges. His authority model is preserved
— the agent's verdict is what decides — but it arrives as a journalled decision record rather than as
a process action, so a dead agent cannot leave a half-issued kill behind.

## 2.3 P3 — adapters

An adapter is an **executable**, not a library: `adapters/<id>/run`, speaking newline-delimited JSON
on stdin/stdout (§8). A crashing or hanging adapter cannot take the conductor down, and an adapter can
be written in any language by the owner (R1-10 [310]: *"можливо, там використання якогось скіла"*, and
the user may write their own).

## 2.4 P4 — the warden

R1-10 [246]: *"запускати якогось агента раз в N годин на якійсь іншій підписці"*, and [266]: it must be
able to *"запустити ран і продовжити роботу без участі в налаштуваннях користувача"*.

Installed by `orchestrator:warden install` as a `launchd` **`StartInterval`** agent (not `cron`;
`launchd` fires a missed interval after wake, `cron` does not — CLAIMED for the missed-fire behaviour,
VERIFIED that cron does not run on a sleeping machine). Interval
`warden.interval_seconds`, DEFAULT-PROPOSED **900 s**.

**⚠ TENSION.** He said *"раз в N годин"* [246]. C6-A10 is right that hours is longer than every failure
his previous run actually suffered. The key is configurable and `N` is his to set; 900 s is the
proposed default, and the document says so out loud rather than shipping his number and calling it his
choice.

**The warden does not run a model by default** (`warden.probe_kind` DEFAULT-PROPOSED `deterministic`).
Its probe is: take `machine.lock`, read `runs.index.jsonl`, and for each live-claimed run **attempt to
acquire `run.lock` non-blocking**. That is the whole liveness test (I1). It costs zero tokens, it is
immune to the cross-account roster blindness that makes C6-A1 a blocker, and it cannot be defeated by
a quota outage. A model probe (`warden.probe_kind: agent`, on `warden.lane`, a different account per
[246]) is available and is used only for the *escalation* text, never for the verdict.

## 2.5 P5 — the CLI

`orchestrator:status` and `orchestrator:doctor` are pure file readers: zero model tokens, zero network,
and they never take a lock (Д11 [508–514]: the orchestrator outputs nothing; status is pulled from a
separate terminal). Mutating commands (`stop`, `add`, `resume`) write `control.yaml` or the ticket
source under a lock and return; they never act on the run themselves.

---

# 3. The control plane

Two roots. Everything the run needs to recover is in the project root; everything that must be true
across runs on one machine is in the machine root.

## 3.1 Paths

```
# ── machine root ──  ${ORCHESTRATOR_STATE_DIR:-$HOME/.local/state/orchestrator}/
machine.lock                        flock target, guards every mutation of this directory
runs.index.jsonl                    append-only: run_registered / run_scope / run_deregistered
boot.json                           {boot_id, boot_epoch, last_seen_mono, last_wake_epoch}
capacity/<provider>/<account>.json  shared capacity snapshot cache (§6.1)
capacity/<provider>.bucket          token-bucket state for the capacity reader
warden/journal.jsonl                the warden's own append-only record
adapters/                           installed platform adapters (§8)
engines/                            installed engine adapters (§7)

# ── project root ──  <project>/.orchestrator/          (gitignored; created by orchestrator:init)
PROHIBITIONS.md                     R1-15's one text file (path is configurable, §13.4)
runs/<run-id>/                      run-id = <UTC compact>-<4 hex>, e.g. 20260919T2312Z-a7f3
  run.json                          immutable run input: mode, scope, run-scope overrides
  resolved-config.json              the resolver's output, snapshotted at t0, with per-key provenance
  journal.jsonl                     THE record (§3.3)
  blobs/<sha256>                    spilled oversized payloads
  control.yaml                      THE watched file (§3.4)
  control.applied.json              {revision, sha256, applied_at, applied_seq} — written by P1 only
  lease/run.lock                    flock target (I1)
  lease/owner.json                  holder identity (§3.5)
  lease/epoch                       fencing token, integer
  lease/heartbeat                   last beat: wall, mono, epoch, boot_id
  lease/agent.lock                  sub-lease: at most one orchestrator-agent session (I2)
  lanes/<lane-id>/lane.json         projection
  lanes/<lane-id>/claim.lock        flock on the ticket claim (§5.1)
  lanes/<lane-id>/events.jsonl      normalised adapter events (§8.3)
  lanes/<lane-id>/cursor            opaque transcript cursor, atomically replaced
  lanes/<lane-id>/{stdout,stderr}.log
  tickets/<ticket-id>.json          full normalised ticket snapshot (§7.2)
  resources.jsonl                   append-only resource ledger (I7, §12)
  status.json                       projection for the status command
  inbox/                            Д6 questions channel, when kind=local
  reports/<ticket-id>.md            what a finished ticket left behind
```

`<run-id>` is generated by the conductor and is unique per machine; the 4 hex digits close the
same-second collision. `<lane-id>` is `L%02d` in dispatch order, never reused within a run — a reused
lane slug is a recorded failure mode (FIELD-NOTES §11.8: a lane slug reused from an earlier wave
spawned a worker into a stale worktree with a stale prompt, VERIFIED).

## 3.2 Read/write protocol, for every file in the plane

Five rules, applied without exception.

1. **Append-only files** (`journal.jsonl`, `resources.jsonl`, `events.jsonl`, `runs.index.jsonl`) are
   opened `O_WRONLY|O_APPEND|O_CREAT`, one record per `write(2)`, each ≤ 64 KiB so the write is atomic
   on local filesystems (VERIFIED for APFS/ext4 with `O_APPEND` under `PIPE_BUF`-class sizes; CLAIMED
   in general). A truncated last line on read is discarded with a `journal.tail_truncated` observation,
   never repaired in place.
2. **Projections** are written to `<name>.tmp.<pid>` in the same directory, `fsync`ed, and `rename`d
   over the destination. A reader never sees a half-written file, and a writer killed before the
   rename leaves the previous file intact — the same rule the marketplace already imposes on config
   writes (OWNER-DECISIONS 4.11, VERIFIED in `docs/config-levels.md` §7).
3. **Locks** are `flock(2)` on a file whose only purpose is to be locked. A lock is never a lock file
   whose *existence* means anything; existence-gate markers are what produced FIELD-NOTES §11.7's
   unattributed `STOP` on disk (VERIFIED, issue `#82`, open).
4. **Change detection is by content hash, not mtime.** Every watched file's `sha256` is kept in
   memory; a change is a differing digest. **⚠ TENSION:** [195] offers mtime — *"Можливо, там,
   наприклад, по даті, перевіряти, коли він був змінний"* — and `../extract/corrections.md` records
   that ANALYSIS-01 hardened that hedge into a named mechanism when he had prefixed it with
   «Можливо». mtime is defeated by an editor's write-and-rename, by `git checkout` restoring old
   content with a new mtime, and by a partially written file read mid-save (C4-A10). The digest costs
   one read of a file under 64 KiB every 2 s.
5. **Every file the owner may hand-edit is parsed defensively**: a parse failure keeps the last good
   value in force, emits one `control.parse_failed` record with the line and column, and notifies
   through the configured channel — *boot fails loud, reload keeps last good* (the `dsh` settings-file
   protocol, ADOPTION-VERDICT §4 item 9, CLAIMED). A hand-edit mistake at 02:00 must not take the run
   down.

## 3.3 The journal

One JSONL file. Six record kinds. This is the whole durable state of the run (I5).

```jsonc
// intent — written BEFORE the effect is attempted
{"seq":1042,"ts":"2026-09-19T23:41:07.412Z","mono":918233.114,"boot":"F1A0…",
 "run":"20260919T2312Z-a7f3","epoch":3,"actor":"conductor","kind":"intent",
 "op":"git.merge","key":"L07:git.merge:1",
 "subject":{"lane":"L07","ticket":"gh#412"},
 "args":{"from":"gsd/phase-23","into":"main","worktree":"/…/wt-L07"},
 "idem":"sha256:9f2c…","expect":["git_ref"]}

// result — written AFTER, referencing the intent by key
{"seq":1043,…,"kind":"result","for":"L07:git.merge:1","outcome":"ok",
 "evidence":[{"kind":"git_ref","ref":"refs/heads/main",
              "before":"93fdf65…","after":"fc01ef2…","read_back_at":"…"}],
 "cost":{"wall_ms":4211}}

// observation — a reading, never a decision
{"seq":1044,…,"kind":"observation","what":"lane.context",
 "subject":{"lane":"L07"},
 "value":{"used":412331,"window":1000000,"pct":41.2},
 "basis":"raw_window","provenance":{"text":"verbatim","token":"provider_measured"},
 "fresh_at":"…","source":"adapter:claude-code@1.2.0"}

// decision — a judgement, with its inputs and its author
{"seq":1045,…,"kind":"decision","actor":"agent:orchestrator@L01","what":"lane.stall_verdict",
 "subject":{"lane":"L09"},"verdict":"LIVE","because":["obs:1031","obs:1038"],
 "authority":"run.mode=autonomous; rules=PROHIBITIONS.md@sha256:ab…","reported":false}

// control — a change read out of control.yaml or the config files
{"seq":1046,…,"kind":"control","revision":7,"class":"stop","mode":"soft",
 "source":"control.yaml","sha256":"…","author":"cli:orchestrator:stop"}

// note — free text, never load-bearing
{"seq":1047,…,"kind":"note","text":"…"}
```

**Field rules.**

- `seq` is strictly increasing per run. The appender holds an in-process counter and, on startup,
  reads the last line to resume it; a gap is a crash marker, never silently closed.
- `mono` is `CLOCK_MONOTONIC` seconds since boot; `boot` is the machine boot id. Together they make
  every duration in the journal survivable across a sleep, which wall clock alone does not (§11.2).
- `epoch` is the fencing token (I1).
- `idem` is the idempotency key (§5.4): a stable digest of `(op, subject, args)` that lets a replayer
  ask *"did this exact operation already happen?"* rather than *"did something like it?"*.
- `expect` names the evidence kinds that would make this intent's result admissible (I4). It is
  written at intent time, so a later reader can tell what the writer intended to prove before it
  found out whether it could.
- `reported` on a decision record implements R1-14: in an autonomous run the agent may decide and
  *"він прозвітовує, про те, що було таке от рішення"* [062]. The report is a projection over
  `kind:"decision" AND reported:false`, flipped to `true` when it reaches the notification channel.

**Why decisions are journalled separately from results.** C1-A4 is a real hazard: *"«він прозвітовує»
is model-written, and a model here wrote 26 events that never happened"* (FIELD-NOTES §12.7,
VERIFIED). A decision record is therefore never evidence of anything; it is a record that a judgement
was made, with pointers to the observations it was made on, and a projection can replay both.

## 3.4 `control.yaml` — the one watched file

Д12 [520–524] names the mechanism: the command writes into the file the orchestrator reads every tick,
and the change is applied on the next tick. R1-07 [195] puts the account assignments in a watched file
too, and Д7 [455–458] puts behaviour overrides there. Nothing in his answers says these are the same
file. **They are one file here, with three sections**, because a second watched file is a second place
for a stop to get stranded, and FIELD-NOTES §12.5 records a real question channel forking into a
worktree's own copy where *"a real owner-facing question sat invisibly for an hour"* (VERIFIED).
Д6's *questions channel* stays separate and user-placed, because he explicitly allows it to be a
GitHub issue or a tracker task (§13.3).

```yaml
# .orchestrator/runs/<run-id>/control.yaml
revision: 7                 # integer, monotonic; the conductor ignores a revision <= applied
stop:                       # Д12
  mode: soft                # hard | soft | custom | none
  custom: drain-then-report # names a rule in config.stops.custom.<name>; ignored unless mode=custom
  reason: "owner: morning demo needs the account"
  author: "cli:orchestrator:stop"
  at: 2026-09-20T04:10:00Z
assignments:                # R1-07 [195]: roles on accounts
  apply: hard               # hard | soft   — see the disambiguation below
  roles:
    orchestrator: {lane: claude-code/<profile-A>}
    executor:     {lane: claude-code/<profile-B>}
    watcher:      {lane: glm/glm-flash}
behaviour:                  # Д7 [455]: override the run's own choice, mid-run
  when_only_human_blocked: wait     # wait | finish | ask
  max_parallel: 2                   # R1-05 [160]
  intake: open                      # open | frozen   — Д2 mid-run additions
```

**The `hard` disambiguation (C4-A10), stated because his words collide.** [171] uses «хардстоп … зупинити
завдання прямо вже» to mean *stop the run*. [195] uses «хард … прямо вже … зупинити» to mean *apply
this account reassignment now, stopping the affected work to do it*. Both are his. The file therefore
never has a bare `hard` key: **`stop.mode: hard` stops; `assignments.apply: hard` switches.** The CLI
refuses to write a control file containing an ambiguous top-level `hard`. This is a naming decision,
not a semantic one — neither of his meanings is changed.

**Writer protocol.** Any writer (`orchestrator:stop`, the owner's editor, the warden) takes
`flock` on `control.yaml.lock`, re-reads, increments `revision`, writes by atomic rename, releases.
The conductor is a **reader only** of this file; it records what it applied in
`control.applied.json`. That is the fix for FIELD-NOTES §2.1 (the previous generation's status file
was rebuilt from scratch by its own watch loop every cycle, destroying anything anyone else wrote,
VERIFIED).

**Self-write suppression.** The conductor never writes `control.yaml`, so there is no self-trigger
loop. This is deliberate: the previous generation's attention file had the orchestrator as both
writer and watcher.

## 3.5 `lease/owner.json` — identity that survives PID reuse

```json
{"run":"20260919T2312Z-a7f3","epoch":3,"host":"…","boot_id":"F1A0…",
 "pid":41233,"pid_start_ticks":"5081993","argv_sha256":"c1de…",
 "exe":"/opt/homebrew/bin/node","started_at":"2026-09-19T23:12:04Z","kind":"run"}
```

A reclaimer that acquires the flock still reads this file and checks: is `pid` alive, does its start
time match `pid_start_ticks`, does its argv digest match? If all three match while the flock was
free, that is **split brain** — the process is alive and has lost its lock — and the reclaimer
refuses, exits 5, and notifies. This is OpenClaw's `resolveGatewayOwnerStatus` shape, including the
fail-closed behaviour when the cmdline reader is unavailable (ADOPTION-VERDICT §4 item 4, CLAIMED,
reimplemented rather than imported per that document's own advice).

## 3.6 `ops.json` — the operation catalogue

A shipped data file, not code. One entry per operation the conductor can perform:

```json
{"git.merge":   {"mutating":true, "idempotent":"by_ref", "admissible":["git_ref"],
                 "reconcile":"read_ref", "timeout_s":300},
 "board.transition": {"mutating":true,"idempotent":"by_readback","admissible":["board_readback"],
                 "reconcile":"refetch","timeout_s":60},
 "lane.dispatch":{"mutating":true,"idempotent":"by_session_id","admissible":["transcript_event","process_exit"],
                 "reconcile":"probe_session","timeout_s":30},
 "session.compact":{"mutating":true,"idempotent":"within_turn","admissible":["token_drop","transcript_event"],
                 "reconcile":"read_context","timeout_s":600}}
```

Everything I3, I4 and the reconciler (§11.3) need is here, in one reviewable file. Adding an operation
without declaring its evidence and its reconciliation is a load-time error.

---
# 4. The state machines

Three machines, one ledger each: the **run**, the **lane**, and the **ticket**. A fourth, the
**resource**, is a two-state ledger and lives in §12.

Every transition below is a journal record. A state is never stored as the truth; it is computed by
folding the journal, and the fold is a pure function so two readers always agree (I5).

## 4.1 The run

```
                     ┌─────────────── control: stop.mode=hard ───────────────┐
                     │                                                        ▼
  init ─► preflight ─► running ─┬─► draining ──────────────────────────► stopping ─► finished
            │  │                │        ▲                                   │          │
            │  │                │        └── queue empty (Д3) ───────────────┘          │
            │  │                ├─► paused:capacity ──(resetAt reached)──► running      │
            │  │                ├─► paused:control ──(stop cleared)──────► running      │
            │  │                ├─► paused:human ────(inbox answered)────► running      │
            │  │                └─► handover ────────(agent replaced)────► running      │
            │  └── refused ─► aborted (exit 3)                                          │
            └───── scope conflict ─► aborted (exit 5)                        degraded ──┘
```

| State | Meaning | Entered when | May dispatch? | Leaves on |
|---|---|---|---|---|
| `init` | run directory created, lock taken, epoch bumped | `orchestrator:run` | no | preflight starts |
| `preflight` | proving the run can run (§4.4) | after `init` | no | all gates pass / any gate refuses |
| `running` | normal operation | preflight passed | yes | any row below |
| `draining` | finish what is running, start nothing new | `stop.mode=soft`, or queue empty (Д3), or capacity soft threshold | no | last lane reaches a terminal state |
| `paused:capacity` | a hard capacity threshold or a `LimitHit` | §6.1 | no | `resetAt` reached, or credit ceiling raised |
| `paused:control` | `stop.mode=hard` with `resume` allowed | §10 | no | control revision clears the stop |
| `paused:human` | only human-blocked work remains, and `when_only_human_blocked=wait` (Д7) | §7.5 | no | an inbox answer unblocks a ticket, or intake adds ready work |
| `handover` | the orchestrator-agent lane is being replaced (R1-08) | context threshold or agent death | **yes** — the conductor keeps scheduling | successor holds `agent.lock` |
| `stopping` | teardown of what this run started (§12) | `draining` complete, or `stop.mode=hard` | no | teardown ledger fully resolved |
| `finished` | terminal, clean | `stopping` completed with every resource resolved | no | — |
| `degraded` | terminal, but teardown left something unresolved | `stopping` could not prove a resource gone | no | — |
| `aborted` | terminal, never ran | preflight refused, or scope conflict | no | — |

**Two things worth naming.**

`handover` **still dispatches.** That is the whole point of splitting the conductor from the agent
(I2): a context handover of the judging agent is not an outage of the run. Compare C5-A5 and C6-A3,
where the same event forces a design either to violate the single-orchestrator invariant or to stop
the run for the ~7 minutes a compaction takes (VERIFIED, FIELD-NOTES §10.2: J-WATCH-01 measured
67 % → 0 % in about seven minutes).

`degraded` exists because `finished` must mean something. FIELD-NOTES §10.1 records the previous run
ending as `DEAD-RUN` + `STOPPED` at the same timestamp with no distinction between an accidental
teardown and a finish, and then flagging *"STOPPED present with no run.complete — treating as an
accidental teardown, not a finish"* every three minutes **for about five days, 1,085 times**
(VERIFIED). Three terminal states, each with its own exit code, is the fix.

## 4.2 The lane

A lane is one attempt at one ticket on one platform lane. One ticket may have many lanes over a run
(retries, reseeds); a lane never changes its ticket.

```
  queued ─► claimed ─► preparing ─► dispatched ─► working ─┬─► verifying ─► succeeded ─► released
              │           │            │            │      │                             ▲
              │           │            │            │      ├─► waiting:human ────────────┤
              │           │            │            │      ├─► waiting:capacity ─────────┤
              │           │            │            │      ├─► compacting ──► working    │
              │           │            │            │      └─► reseeding ──► dispatched  │
              │           │            │            └────────► failed ──────────────────►┤
              │           │            └──────────────────────► failed                   │
              │           └── prepare refused ─────────────────► abandoned ──────────────┤
              └── claim lost ─────────────────────────────────► abandoned ───────────────┘
                                                                orphaned ──► reconciling ─┘
```

| State | Invariant that holds in it | Exit paths |
|---|---|---|
| `queued` | the ticket is ready by the engine's readiness rule and its dependencies are satisfied | `claimed` |
| `claimed` | `claim.lock` is held; the board says in-progress (if the board is writable) | `preparing`, `abandoned` |
| `preparing` | the worktree, env, services and account are being made ready and **proven** (Д4) | `dispatched`, `abandoned` |
| `dispatched` | an intent exists; a session id exists or is about to; **this is the crash window** (§11.4) | `working`, `failed` |
| `working` | the adapter reports a non-terminal status and the transcript cursor is advancing or the status says so | every row below |
| `waiting:human` | the session asked something only a person can answer; the ticket is parked, the queue is not (Д6) | `working`, `abandoned` |
| `waiting:capacity` | a `LimitHit` was observed in-band, or capacity crossed a hard threshold | `working`, `abandoned` |
| `compacting` | a compaction is in flight; **proof is pending, not assumed** | `working` (proven), `reseeding` (unproven) |
| `reseeding` | close-and-reseed: a new session inherits a summary; the ticket→session map becomes a **lineage** | `dispatched` |
| `verifying` | the engine's own verification step is running (R1-13) | `succeeded`, `failed` |
| `succeeded` | the engine's completion oracle fired **and** every intent has a result | `released` |
| `failed` | a terminal, named failure with a reason code | `released` |
| `abandoned` | the lane never produced work; the ticket returns to the pool, with the abandonment recorded | `released` |
| `orphaned` | recovery found intents with no results (I3) | `reconciling` |
| `reconciling` | the reconciler is establishing what actually happened (§11.3) | `succeeded`, `failed`, `abandoned`, or `human` escalation |
| `released` | the claim lock is released and the resource ledger for this lane is resolved | terminal |

**`waiting:human` is a state, not an outcome.** LANDSCAPE §5 establishes that the field is split and
both sides argued it: Sortie ADR 0025 makes a human-input request a dedicated non-retryable terminal
because *"an unattended run contains no one who can grant permission"*; claudexor parks it as a durable
pending interaction with a timeout and four terminals (`answered | timeout | run_terminal |
interrupted`) and four delivery statuses (`delivered | not_found | already_resolved | rejected`) — both
VERIFIED. The owner's Д6 [449] is unambiguous about which side he is on: independent tasks continue,
and he configures one channel where the answer arrives *live*. So: park the lane, keep the queue
moving, and take claudexor's four-terminal shape verbatim. The one thing Sortie is right about and
that this design imports: **the retry budget must not drain into this state** — a `waiting:human` lane
charges nothing against Д5's three-failure budget (§7.5).

**`compacting` cannot report success without proof.** ADAPTER-CONTRACT §2.3 makes `Proof` mandatory
for `compact` and forbids returning success without it; on four platforms (Amp, Gemini CLI, Cursor,
`dsh`) an external trigger is **impossible** (VERIFIED). The lane therefore falls to `reseeding`, which
is the platform-independent fallback, and the ticket→session mapping is a **list**, not a field
(ADAPTER-CONTRACT §6.3).

## 4.3 The ticket

The ticket machine is the owner's, not mine: R1-04 [145–153] says the structure is to be designed and
the status names are user-overridable and adapt to the chosen process. So the ticket machine is
**declared in config** and the orchestrator holds only the shape:

```
  unknown ─► ready ─► claimed ─► in_progress ─┬─► needs_review ─► done
                ▲                              ├─► blocked ──────┘
                └──────────── released ────────┘
```

`config.board.states` maps each of these seven internal names onto the board's own names; preflight
refuses to start if a required internal name has no mapping, which is R1-04's board-readiness check
[153] made mechanical. **The internal name is what the state machine uses; the board name is what the
board sees.** A board with only `ready / in progress / done` (his plain case) maps `needs_review`,
`blocked` and `claimed` onto comment-only markers, and preflight *says so* rather than pretending.

**Writing back.** R1-04 [149] makes the board a working surface. Every board write is a mutating op
with `board_readback` as its only admissible evidence (I4) — the board is re-fetched and the field
compared, because a tracker API returning 200 is not evidence the transition applied
(ADAPTER-CONTRACT §2.4 invariant 2).

**⚠ TENSION (C3-A1).** The board is both the working surface and the thing watched for changes (Д8),
so the orchestrator's own writes fire its own change detector. Resolution: every board write records
its post-write readback digest in `tickets/<id>.json` as `self_write_digest`, and the watcher ignores a
change whose digest matches. This is content-based self-write suppression, the same rule as §3.4.

## 4.4 Preflight — the gate that refuses

R1-07 [199], R1-17 [395], R1-04 [153] and Д4 [433] all say the same thing in different places:
**verify before you run.** Preflight is one ordered list, each item producing a journal record, and any
`refuse` aborts the run with exit 3 before a single token is spent.

| # | Gate | Refuses when | Owner requirement |
|---|---|---|---|
| 1 | scope | another live run's scope intersects this one | I2, C6-A12 |
| 2 | config | the resolver failed, or a required key is unset with no default | Д1 |
| 3 | prohibitions | the red-line file is missing or unreadable | R1-15 [357] |
| 4 | engine | the configured engine adapter is absent, or its version is unpinned | R1-03 |
| 5 | board | a required internal state has no mapping; or access cannot be proven by a read **and a no-op write** | R1-04 [153] |
| 6 | lanes | for each lane: `preflight(account)` does not prove **which account** would be used, or the binary version is not pinned | R1-07 [199] |
| 7 | account distinctness | two roles that the config separates resolve to the **same account id** | C4-A1 |
| 8 | capacity | `readCapacity` returns `Unknown` for a lane whose role requires prediction | §6.1 |
| 9 | keychain | a Claude Code account that has never been granted keychain access | ADAPTER-CONTRACT §3 F |
| 10 | notify | the configured channel does not deliver a test message | R1-17 [395] |
| 11 | worktree | the default worktree cannot be created, or its env/services do not come up | Д4 [433] |
| 12 | machine | free disk under `preflight.min_disk_gb`, or `memory_pressure -Q` already critical | FIELD-NOTES §5.1 |

**Gate 7 is new and it is not optional.** C4-A1: two profiles can be one account — two config dirs,
two keychain entries, one quota pool. The owner's role-split ([270] *"тільки для оркестратора … І це важливий дуже нюанс"*) is
expressed over **profiles**; quota lives on **accounts**; and his pre-run verification as stated
[199] proves the switch applied, which is true and is not the thing that matters. Gate 7 asks the
question his decision set does not: *are these two roles on different quota pools?* It refuses on a
collision and names both profiles and the shared account id.

**Gate 10's limit, stated honestly (C9-A5).** He said the orchestrator *"повинен лише переконатися, що
це працює"* [395] — one verification. The only recorded notification failure is a channel that was
verified and then died (FIELD-NOTES §11.6: the human-notification watchdog *"had already exited ('run
finished') and was never restarted"*, VERIFIED). So: the gate is one verification, as he said, and the
**delivery of every subsequent notification is itself an op with `http_status` evidence**; a failed
delivery escalates to the terminal log and `status.json`, never to silence. That is not a second
verification; it is not lying about the first.

---

# 5. Claiming and releasing work

## 5.1 The claim

A claim is `flock` on `<run>/lanes/<lane-id>/claim.lock` plus a **claim record** naming the ticket.
Two lanes cannot hold the same ticket because the conductor is single-threaded and the claim index is
in the journal; two *runs* cannot, because their scopes cannot intersect (I2).

Claim order, each step journalled:

1. `intent ticket.claim` with `idem = sha256(run, ticket_id, attempt_n)`.
2. `flock` the lane's claim lock.
3. Write the board transition `ready → claimed` (if the board is writable), with readback evidence.
4. `result ticket.claim ok` carrying the readback.

If step 3 fails, step 4 records `outcome:"partial"` with the reason, the lane goes to `abandoned`, and
the lock is released. **A claim is never held on an unverified board write** — that is how two workers
end up on one ticket after a crash.

## 5.2 The release

Release is the mirror and is idempotent. It runs on every terminal lane state and again during
recovery. It: releases the flock, writes the board transition, resolves every resource the lane owns
(§12), and appends `lane.released`.

**A lane that cannot release cleanly does not silently disappear.** It becomes `released:degraded`,
and the run cannot reach `finished` while any such lane exists — it reaches `degraded` instead.

## 5.3 Concurrency and dependencies

R1-05 [160], with the retraction at [163] honoured: **the user sets the maximum, the system does not
decide it.** `behaviour.max_parallel` (DEFAULT-PROPOSED **2**) is read from control every tick and is
the only ceiling. Dependency-blocked tickets are not claimed.

**⚠ TENSION.** He explicitly deferred machine-resource awareness — *"ресурси машини, поки це заберемо,
це добавимо в майбутнє"* [160]. I honour that: nothing in the scheduler reads CPU or memory. But
FIELD-NOTES §5.1 records his own container `OOMKilled` at `2026-09-13T03:29:01Z` while two
`docker compose up --build` ran at once (VERIFIED), and §12.3 records the watcher's own collector
OOM-killed **26 or more times** with host swap down to ~63 MB free (VERIFIED). The compromise that
does not violate the deferral: preflight gate 12 checks the machine **once, before the run**, and a
single named guard — `limits.max_concurrent_builds`, DEFAULT-PROPOSED **1** — serialises operations a
lane *declares* as heavy (`engine` steps tagged `heavy: true`). That is a declared-cost queue, not
resource awareness, and it is the smallest thing that prevents the one incident that actually happened.
If he wants even that gone, it is one config key set to `0` (unbounded).

## 5.4 Idempotency keys — the thing that makes replay safe

Every mutating op carries `idem`, a digest over `(op, subject, normalised args, attempt)`. The
reconciler (§11.3) uses it to ask *"did this exact operation already happen?"*. Four idempotency
classes, declared per op in `ops.json`:

- `by_ref` — the effect is visible in a ref or a digest. Replay is safe: read the ref. (`git.merge`,
  `git.push`, `file.write`.)
- `by_readback` — the effect is visible by re-fetching the target. Replay is safe after a refetch.
  (`board.transition`, `board.comment` — where the comment carries the `idem` in a hidden marker so a
  duplicate is detectable. FIELD-NOTES §12.6 records the shipped implementation keeping exactly one
  comment, and C3-A12 flags it; the marker is what makes "leave a comment" replay-safe.)
- `by_session_id` — the effect is a session that the client named before launch. Replay is safe on the
  platforms where the client assigns the id (Claude Code, pi, Droid, OpenCode, Qwen — VERIFIED,
  ADAPTER-CONTRACT §3 B); on server-minted platforms (Codex, Kimi, Amp, MiMoCode) there is a crash
  window and the class degrades to `unsafe` (§11.4).
- `unsafe` — replay is not safe and there is no cheap probe. The reconciler escalates to a human via
  the questions channel rather than guessing. `pr.create` is here unless the board carries the PR
  link, because C6-A6 case 2 is real: a crash between opening a PR and recording it produces a second
  PR, and R1-12 [331] *wants* stacked PRs, so nothing downstream finds a duplicate suspicious.

---

# 6. Observation: capacity, context, liveness

Three subsystems. They fail differently, so they are built separately and share only I8 and I9.

## 6.1 Capacity

**The type, not a number.** ADAPTER-CONTRACT §6.1 is the finding that shapes this: three incompatible
models coexist — rolling **window** with a reset time (Claude Code, Codex, Kimi, Copilot, GLM),
**credit** balance with no reset ever (DeepSeek, Amp, Cursor), and **nothing** (pi, Qwen, MiMoCode,
OpenCode, Aider) — all VERIFIED. *"Дочекатись рестарту ліміту і продовжити"* [034–036] is **not
implementable on seven of fifteen platforms**, because there is nothing to wait for.

```
Capacity = Window {used_pct, reset_at, scope}       → policy: pause, auto-resume at reset_at
         | Credit {remaining, unit, ceiling}        → policy: spend ceiling, stop, NOTIFY, no auto-resume
         | Unknown {kind, since, last_good}         → policy: conservative ledger, react only to LimitHit
```

`Unknown.kind` ∈ `throttled | auth_expired | schema_unknown | network | not_supported`. They want
opposite responses and C4-A6 records that collapsing them is how the shipped limiter became inert.

**The meter is a single machine-wide reader.** C4-A3 is VERIFIED and is the sharpest operational
finding in the cluster set: **one** call to `https://api.anthropic.com/api/oauth/usage` with a valid
token returned `rate_limit_error`, because another process on the same machine had probed it a minute
earlier — and the owner's own global `CLAUDE.md` instructs *every* Claude Code session to poll that
endpoint before and during any long-running task. Four readers, a two-call budget.

So: `~/.local/state/orchestrator/capacity/` holds one cache per `(provider, account)` and one token
bucket per provider. **No lane and no agent ever calls a capacity endpoint directly.** The conductor
reads through the meter; the meter enforces `capacity.min_interval_seconds` (DEFAULT-PROPOSED **3600**,
matching ADAPTER-CONTRACT §2.3's *"Cache ≥60 min per account; never poll per session"*) and a bucket
of `capacity.burst` (DEFAULT-PROPOSED **2**). A lane that wants the number reads the cache file.
A read refused by the bucket returns `Unknown{throttled}` from cache — never a fresh call.

**`Unknown` does not authorize dispatch.** claudexor's rule, adopted verbatim: *stale quota never
authorizes routing*; headroom is the **worst** window across every constraint, not the average; and
running out is a typed terminal (`credential_pool_exhausted`), not an error (VERIFIED, LANDSCAPE §4).
Ranking for lane selection: fresh-with-headroom by headroom descending → unknown/stale (eligible but
never ranked as known headroom) → exhausted (never selected).

**The in-band brake.** `detectLimitHit` is required even where `readCapacity` is native, *because
prediction and reaction fail differently* (ADAPTER-CONTRACT §2.3). And the detector must not fire on
prose about limits: ralphex's rule is the one to copy — match **by source**, over a bounded window of
structured CLI diagnostics, never ordinary assistant text, and count a `result` record as diagnostic
only when it authenticates itself (`is_error:true`, `terminal_reason:"api_error"`, or a non-zero
`api_error_status`), explicitly **not** consulting `subtype`, *"since a genuine rate-limit result has
been observed carrying `subtype:\"success\"`"* (VERIFIED, LANDSCAPE §4). FIELD-NOTES §11.6 is the cost
of getting this wrong: an 85-minute loop fed by a usage-cap banner matched inside the orchestrator's
own wrapped prose.

**Thresholds (R1-06.2).** Per account, per window, expressed only where a percentage exists:

| Key | Meaning | Default |
|---|---|---|
| `limits.<window>.soft_pct` | enter `draining`: finish the current task, start nothing new | DEFAULT-PROPOSED **85** |
| `limits.<window>.hard_pct` | enter `paused:capacity` now | DEFAULT-PROPOSED **95** |
| `limits.<window>.reserve_pct` | never spend below this; reserved for the owner's own work | DEFAULT-PROPOSED **10** |
| `limits.credit.ceiling` | spend ceiling per run, in the provider's unit | DEFAULT-PROPOSED **unset → refuse to use a Credit lane until set** |
| `limits.on_unknown` | `hold` \| `proceed` \| `notify_and_hold` | DEFAULT-PROPOSED **`notify_and_hold`** |

`reserve_pct` answers a question **that was never put to him** — `../extract/corrections.md` §F
records that half of R1-06 was dropped by the interviewer and *"there is no answer anywhere in the
transcript about reserving headroom for the owner's own interactive work"*. It is the failure mode that
makes an unattended run eat the subscription he needs in the morning, so it ships with a default and is
listed in §17.5 as needing his ruling.

`limits.on_unknown` defaults to the **opposite** of the shipped product's `proceed`. That is a
deliberate reversal of a shipped default, flagged here rather than slipped in: with `proceed`, the
limiter is provably inert (C4-A6, VERIFIED in source), and the owner's belief that the machine will
stop itself is false all night.

**A reading carries its account.** FIELD-NOTES §12.4: *"A weekly-usage figure can move without any
usage changing"* — repointing the supervisor between accounts dropped the weekly reading from 26 % to
6 % from the switch alone (VERIFIED). Every capacity observation therefore records `account_id`, and a
threshold series is never computed across an account boundary; a switch resets the series and says so.

## 6.2 Context

**The basis problem, first, because it invalidates everything else.** C5-A2 is VERIFIED by reading the
owner's own installed `~/.claude/hooks/gsd-statusline.js`: the status bar he has read all year
normalises against `AUTO_COMPACT_BUFFER_PCT = 16.5` and its own comment says this *"inflates the context
monitor warning messages by ~13 points (#2451)"*. So `percent: 80` means two different occupancies
depending on which number the implementer reads, and the two failure modes are opposite: the platform's
own auto-compact fires first and his threshold never executes once in 34 hours, or the orchestrator
compacts a third too early all night at ~7 minutes a time.

**Resolution.** `context.basis` is an explicit, required config key with values
`raw_window | usable_after_reserve | statusline`. DEFAULT-PROPOSED **`raw_window`**, and
`orchestrator:config` *shows him both numbers for a live session* when he sets the threshold, so he
picks against a number he can see. Every context observation records its `basis` and its two-axis
provenance — `text: verbatim | reconstructed | absent`, `token: provider_measured | tokenizer |
estimated | derived | unknown` — which is agent-deck's rule, adopted because collapsing the two axes
onto one *"forces a lie in one direction"* (VERIFIED, LANDSCAPE §4). A number with no provenance
cannot be constructed.

**Soft and hard (R1-08 [204–213]).**

- `soft` waits for the current **step**, and *what counts as a step is itself configurable* [209]. The
  step boundary is the engine adapter's business (§7.3): it is `engine.step_boundary()`, not a guess
  from a screen. Where the engine cannot name a boundary, soft degrades to "at the next turn
  boundary reported by the adapter", and the degradation is journalled.
- `hard` stops now, compacts, continues [213]. On the four platforms where an external compaction
  trigger is **impossible** (Amp, Gemini CLI, Cursor, `dsh` — VERIFIED), hard is not implementable and
  the lane's capability map says so at preflight; the run either excludes those lanes from
  context-bounded work or accepts soft-only, by `context.on_no_trigger` (`exclude | soft_only`,
  DEFAULT-PROPOSED **`soft_only`**, with a preflight warning).

**"Guaranteed" (his strongest phrase, [204]: «повинен бути механізм, який гарантовано робить цю дію»).**
It is implemented as a three-step ladder with proof at each step, and the ladder is what makes the
guarantee honest:

1. `compact` via the adapter → requires `token_drop` or `transcript_event` proof. A second call inside
   one turn is a no-op, not a second compaction (ADAPTER-CONTRACT §2.3).
2. If unproven within `context.compact_deadline_seconds` (DEFAULT-PROPOSED **600**) → **close and
   reseed**: summarise, open a new session with the summary, append the new session to the ticket's
   session **lineage**. This is the platform-independent fallback and it is built once, centrally.
3. If reseed fails → the lane goes `failed:context_exhausted`, the ticket returns to the pool with a
   recorded reason, and the run notifies. It never continues over-budget.

The guarantee the owner asked for is therefore: *the action always resolves to one of three named
outcomes within a bounded time, and "compacted" is never recorded unproven.* That is the strongest
form available on the field as it exists; §17.1 records where it is weaker than his words.

**Nothing in the previous generation measured context at all** (FIELD-NOTES §3.3: `bin/*.sh` contains
no reference to context, percentages or compaction; VERIFIED), while §3.1 records a lane burning 445k
tokens — 77 % of all context growth in its window — on `echo idle`. This subsystem is unstarted work,
not a research problem.

## 6.3 Liveness and progress (R1-09)

His decision [231] is that **the agent decides**: it looks at the sessions it started, at their
progress, and acts. `../extract/corrections.md` §C records that this was closed over a half-finished
sentence and never ratified; it is designed for anyway.

**The problem is not the judgement, it is the evidence** (C6-A4). Under I9, each signal is declared
with what it can and cannot support:

| Signal | Admissible for | Never admissible for | Why |
|---|---|---|---|
| adapter `status` | `LIVE`, `waiting:human` | `DEAD` | it is the platform's own report; "waiting on a human" is a distinct state from "working" (ADAPTER-CONTRACT §2.2) |
| transcript cursor advance | `LIVE` | `DEAD` | absence of growth is not death — a 14-minute test suite produces nothing |
| process presence + start-time match | `LIVE`, `DEAD` | `progress` | a live process may be wedged |
| journal `intent` without `result` past its op timeout | `stuck` | `DEAD` | the op may be slow |
| heartbeat age | **nothing** | everything | FIELD-NOTES §1.5: a session heartbeats *between* turns; 33 nudges, six of them on demonstrably healthy sessions (VERIFIED) |
| shell / child count | **nothing** | everything | FIELD-NOTES §2.2: a shell that cannot exit reads as work (VERIFIED) |
| screen text | **nothing** | everything | FIELD-NOTES §11.6 (VERIFIED) |
| git activity | **nothing** | everything | inadmissible by R1-13/N2: there may be no repo |

**The verdict is three-valued** (I8) and is computed by the conductor deterministically:

- `LIVE` — adapter status non-terminal, **or** cursor advanced since the last tick.
- `DEAD` — the process is gone (pid absent or start-time mismatch) **and** the adapter reports
  terminal-or-missing **and** no wake event intervened.
- `UNKNOWN` — everything else, including every adapter timeout.

**Only `UNKNOWN` sustained past `liveness.unknown_ceiling_seconds` (DEFAULT-PROPOSED 900) is escalated
to the orchestrator agent**, as an explicit question carrying the observation records and the
admissibility table. The agent answers with a `decision` record; the conductor executes it. This keeps
his delegation ([231], [236] *«врегульовувати»*) exactly as he specified while removing the loop C6-A4
describes — where a 12-minutes-into-a-14-minute-suite validator is judged stalled and restarted, for
ever.

**There is no nudge.** The previous generation's only escalation was a bare Enter into a terminal, and
it is abolished here on the evidence: five instructions never delivered (§1.3), the nudge unable to
submit stranded text (§1.4), `send` silently failing above ~200 characters (§12.1), and a recovery
attempt destroying the very instruction it was recovering (§12.1) — all VERIFIED. An instruction to a
live session is `send(handle, text, mode) → Ack`, and `Ack` is a state machine: `accepted ≠ delivered ≠
processed`, with `accepted` never reported as `delivered` (ADAPTER-CONTRACT §2.3). Where the platform
gives no receipt, the lane's capability map says `intervention: emulated`, and the conductor's only
legal action against it is `stop`.

---
# 7. Driving an engine without owning it

R1-03 [118] is the identity decision: the orchestrator runs **either** one existing process (GSD,
superpowers, another marketplace's tooling) **or** a fully custom one the user defines — *"комбінувати
ні, тут або або"*. R1-13 [344] adds that verification belongs to that process, and N2 [344] forbids
assuming tests, repos or a build at all.

## 7.1 The engine adapter contract

An engine adapter is an executable at `engines/<id>/run` plus a manifest `engines/<id>/engine.json`.
Six operations, NDJSON on stdin/stdout, each with a wall-clock timeout:

| Op | Signature | Contract |
|---|---|---|
| `describe` | `() → {id, version, states[], step_kinds[], owns_worktrees, owns_branches, needs[]}` | static; zero tokens; `needs` is a capability list checked against the lane's `capabilities()` at preflight (ADAPTER-CONTRACT §6.6: a subagent-heavy engine simply will not run on Aider) |
| `readiness` | `(ticket) → {ready: bool, reasons[]}` | the engine decides what "ready" means (R1-04 [145]); the orchestrator never invents it |
| `plan` | `(ticket, workspace) → {steps[]}` | a step is `{id, kind, invoke, boundary, heavy, produces[]}`; for GSD this is a projection of the phase, not a re-plan |
| `invoke` | `(step, lane) → {prompt, env, cwd, expect[]}` | returns *what to say to a session*, never runs anything itself |
| `observe` | `(ticket, workspace) → {step_states{}, artifacts[], accounting{}}` | reads the engine's own records; must distinguish `observed_absent` from `unknown` |
| `oracle` | `(ticket, workspace) → done \| not_done \| indeterminate` | the completion oracle, three-valued (I8) |

**`oracle` is the hardest and it is the one C9-A1 calls a blocker**: two of his decisions together —
verification belongs to the process, and there may be no tests — leave the orchestrator with no
completion oracle of its own. The resolution is that it does not need one: the oracle is the engine's,
and where the engine has none, `oracle` returns `indeterminate` and the ticket goes to `needs_review`
rather than `done`. Sortie's asymmetry argument is the justification and it is quoted in full in I4:
the two errors are not symmetric, so the default is to withhold. `engine.on_indeterminate` is
`needs_review | done | ask` (DEFAULT-PROPOSED **`needs_review`**).

## 7.2 The GSD adapter, concretely

GSD is the engine he names most often and the first one that must work. VERIFIED on this machine:
`~/.claude/gsd-core/` ships `bin/gsd-tools.cjs` with a large `bin/lib/` (including
`claude-orchestration.cjs`, `capability-*.cjs`, `artifacts.cjs`, `clock.cjs`), `workflows/` per
command (`execute-phase`, `plan-phase`, `verify-work`, `autonomous`, `progress`, …), and `templates/`
for `state.md`, `roadmap.md`, `config.json`, `UAT.md`, `VALIDATION.md`, `verification-report.md`.

- `describe` → `owns_worktrees: true` (GSD has its own workspaces — Д4 [433] says the worktree policy
  must align with the chosen process), `needs: [subagents, skills]`.
- `readiness` → a phase in `ROADMAP.md` whose predecessors are complete.
- `plan` → the phase's plan files; a step per plan, with `boundary: "plan"`.
- `invoke` → the `/gsd:*` skill invocation as a prompt, with the phase and plan ids pinned.
- `observe` → reads `.planning/` artifacts: `STATE.md`, `ROADMAP.md`, the phase directory,
  `NN-VERIFICATION.md`.
- `oracle` → `done` only when the phase's verification artifact exists **and** does not self-attribute.
  FIELD-NOTES §11.4 is why that clause is there: GSD's verify stage was silently skipped for phases 14
  to 18, each `NN-VERIFICATION.md` carrying `verified_by: the lane that built the phase`, and *"no
  automated check caught it; manual review did"* (VERIFIED). One string comparison closes it.

**Accounting (R1-06.3 [187–191]).** He said: reference the chosen process's own records, supplement
only what is missing, keep own records only when the process has none, and at config time the agent
must research the process's accounting and *explain why it is asking*. `observe().accounting` is that
reference. **⚠ TENSION:** C6-A7 is right that a reference points at a *claim*, not a witness — GSD's
own record of what it did is written by the same agent that did it. The design keeps his decision
(reference, do not duplicate) and adds exactly one thing: the orchestrator's own journal independently
records the orchestrator's own operations (I3), so recovery reads two records with different authors
and can tell when they disagree. He said *«Я можу помилятись»* about GSD needing almost no extra
bookkeeping [189]; this is the smallest hedge against that.

**⚠ TENSION (C9-A2).** Д4's default — every task in its own worktree off the main branch — and GSD's
own worktree ownership cannot both hold. Resolution: `describe().owns_worktrees` decides, per engine,
and `worktree.policy` (`engine | per_task | none`, DEFAULT-PROPOSED **`engine`** when the engine claims
ownership, **`per_task`** otherwise) makes it explicit. FIELD-NOTES §4.3 shows what happens when both
believe they own it: GSD computed a branch name one word off the lane branch and *"left alone would
have cut a fresh branch from `origin/master` and lost the merged master tip"* (VERIFIED). Preflight
compares the engine's computed branch name against the lane's and refuses on a mismatch.

## 7.3 A custom engine

`engine.kind: custom` reads `engine.steps` from config: an ordered list of
`{id, invoke, boundary, gate?, heavy?}`. A `gate` is a command plus the sentence the agent is told when
it fails — Ralph Orchestrator's `backpressure.gates` shape, which makes "independent verification" a
config file rather than a second agent (VERIFIED, LANDSCAPE §4). Format is **YAML or JSON**; the owner
floated YAML and hedged it in the same breath (*"Можливо, не так, тут треба буде подумати, як саме"*,
[118], recorded in `../extract/corrections.md`), so both are accepted and neither is claimed as his
choice.

**No mixing** (R1-03). `engine.kind` is one value. Config that sets both `engine.id` and
`engine.steps` is a load-time error naming both.

## 7.4 How the conductor asks the agent a question

Every judgement the owner delegated is a **typed question** with a bounded deadline and a declared
fallback. The conductor writes an `intent agent.ask`, dispatches or reuses the orchestrator-agent lane,
and waits at most `agent.decision_deadline_seconds` (DEFAULT-PROPOSED **300**).

```json
{"question":"lane.stall_verdict","subject":{"lane":"L09"},
 "observations":["obs:1031","obs:1038"],"options":["LIVE","UNKNOWN","DEAD","stop_and_requeue"],
 "authority":{"run_mode":"autonomous","may_stop":true,"may_kill_owner_processes":false},
 "fallback":"UNKNOWN","deadline":"2026-09-20T02:31:00Z"}
```

The answer must echo an **offered option id, never free text** (ADAPTER-CONTRACT §2.3, `answer`). On
deadline, the fallback applies and the timeout is journalled. This is the mechanism that keeps
"the orchestrator decides" (R1-09, Д3, Д9, Д10) from becoming "the run hangs on a model that stopped
answering".

## 7.5 Failure budgets and the questions channel

**Д5 [442]: three identical failures → act per configuration.** `failure.identical_threshold`
(DEFAULT-PROPOSED **3**, his number), where "identical" is `(ticket, step.id, reason_code)`. The count
is **durable**: it lives in the journal, not in process memory, so it survives the orchestrator's own
death — OpenClaw's durable-retry-budget-with-a-tombstone design, adopted because *"the case where
looping forever actually happens"* is exactly the one where the counter was in memory
(ADOPTION-VERDICT §4 item 5, CLAIMED). On exhaustion: `failure.on_exhausted` ∈
`notify_and_stop | stop | park` (DEFAULT-PROPOSED **`park`** — the ticket is tombstoned with a reason,
the run continues, and the owner is notified), which is within the shape he allowed
(*"notify and stop, or just stop; anything beyond needs the user's permission"*).

**⚠ TENSION.** He said *«В який момент не знаю»* about when the three-strike rule fires
(`../extract/corrections.md` §B), and delegated the moment to the orchestrator. `park` is the
conservative reading: it does the least, keeps the queue alive, and leaves the decision visible.

**Д6's channel.** `questions.kind` ∈ `local_file | board_issue | tracker_task` with a `path`/`id`. It
is watched by content digest on the control tick. Anything written there by the owner becomes a
`control` record and is routed to the lane waiting on it. A `waiting:human` lane charges **nothing**
against the failure budget — Sortie's point, adopted: where "needs a person", "failed" and "produced
nothing" arrive as one timeout, *"the retry classification that follows sends the attempt back into the
wait it just left"* (VERIFIED, LANDSCAPE §4).

**Д7's default.** `behaviour.when_only_human_blocked`: `wait` (his stated default recommendation),
`finish`, or `ask`. Changeable **during** the run through `control.yaml`, overriding both the run's
initial choice and the default — which is exactly what [455–458] requires and what §9.3 implements.

---

# 8. How a platform adapter plugs in

## 8.1 The three objects

ADAPTER-CONTRACT's structural finding is adopted whole, because it shrinks the work: four of the
fifteen names on the owner's list are **providers**, not platforms — another CLI pointed somewhere else
by environment (VERIFIED).

```
Provider = {id, base_url, auth_ref, model, small_model, context_window,
            capacity_model: Window|Credit|Unknown, monitor_endpoint?, concurrency_ceiling?}
Platform = {adapter_id, binary, version_pin, transport, home_env, capabilities{}}
Account  = {id, platform_home, resolved_account_id, verified_at}
Lane     = Platform × Provider × Account × Role
```

A run is a set of lanes. `orchestrator:doctor` prints the lane table with each lane's capability map
and its resolved account id — which is how gate 7 (§4.4) becomes visible to the owner rather than a
surprise.

## 8.2 Installation

```
~/.local/state/orchestrator/adapters/<id>/
  adapter.json    {id, version, platform, binary, min_platform_version, max_platform_version}
  run             executable; NDJSON request/response on stdin/stdout
```

The conductor loads `adapter.json`, spawns `run` with `--op capabilities` first (ADAPTER-CONTRACT
§2.0: it comes first, derivable without a network call or a model token), and refuses to use an adapter
whose declared `capabilities` disagree with what preflight measures. **An adapter that reports `native`
and then degrades at 03:00 is the single worst failure the contract exists to prevent**, so a
capability whose only implementation is a regex over English prose must be declared `emulated`.

## 8.3 The normalised event vocabulary

The conductor never reads a platform's native records. Each adapter emits one vocabulary
(ADAPTER-CONTRACT §6.2: *"Do not let the orchestrator read platform-native records directly; that is
how one platform's schema change breaks the run loop for all of them"*):

```
turn_started | tool_call | waiting_on_human | waiting_on_tool | compacted |
turn_completed | failed | limit_hit | account_asserted | question_asked | question_answered
```

Each event carries `{ts, mono, cursor, provenance, raw_ref}`. `raw_ref` points into the lane's own
tee'd copy of the native record, so a post-mortem is possible without the run loop depending on it.

## 8.4 The ten invariants an adapter must honour

Imported verbatim from ADAPTER-CONTRACT §2.4, because each is a verified silent-failure mode and none
is a style note: never branch on the exit code; never trust HTTP 200 or a `success` string; always
close or own stdin; always impose an external wall-clock timeout; always pin the version and disable
auto-update; always pin the model explicitly; keep stdout and stderr separate; union the roster across
accounts; re-attach permission and question handlers on every resume; assert teardown by process, not
by the command's word.

**Version pinning is enforced, not advised.** ADAPTER-CONTRACT §6.8 calls auto-update *"the most
under-rated overnight killer"* — Amp shipped five releases in fifteen hours with auto-update on by
default; Copilot, 835 versions in twelve months (VERIFIED). Preflight records every binary's version
in the journal and refuses a lane whose version differs from its pin.

## 8.5 The session layer

ADOPTION-VERDICT's one **adopt** recommendation is `acpx@0.17.0`, pinned, as the session layer, with a
published exit-code contract (`0` ok · `1` agent/runtime · `2` usage · `3` timeout · `4` no session ·
`5` all denied · `130` interrupted) that VERIFIED did not change across 44 published versions.
Under this lens it is worth taking for one reason: it retires the failure *class* that produced six
FIELD-NOTES records — controlling sessions by typing into a TTY and reading the screen back.

It plugs in as an ordinary adapter (`adapters/acpx-claude`, `adapters/acpx-codex`, …), so the design
does not depend on it. **Exit `5` is a first-class lane outcome**, mapping to `waiting:human`, not to
`failed` — the industry is actively closing the door on answering a headless session's question
(DSH disables `AskUserQuestion`; acpx's fixed-choice refusal *"takes precedence over `--approve-all`,
permission policies, and embedding host permission callbacks"*; OpenClaw's `ask_user` is
main-session-only — all CLAIMED, read 2026-09-19).

**⚠ TENSION with R1-11 [324].** He explicitly allows the orchestrator to answer a session's own
`AskUserQuestion`, within configured authority [325]. That remains supported and is a native capability
on eight platforms (Copilot, MiMoCode, Qwen, Droid, Kimi, Cursor ACP, pi, OpenCode — VERIFIED). It is
**not** available on the lane he is most likely to run (Claude Code headless/`--bg`), and on those
lanes the only safe unattended posture is to prevent the question — which weakens R1-02. That is
ADAPTER-CONTRACT §7 question 12 and it is his to answer; §17.5 carries it.

---

# 9. Configuration

## 9.1 Where it lives

The owner's own marketplace rules bind (Д1 [416], and OWNER-DECISIONS 3.1–3.8 / `docs/config-levels.md`
— both VERIFIED). Plugin name: `orchestrator`. Six slots, resolved by the one deterministic Node
resolver, highest slot wins, personal beats committed, per-plugin beats general inside a band:

| Slot | Path |
|---|---|
| 6 | `./.claude/shared/plugins/orchestrator.local.json` |
| 5 | `./.claude/shared/identity.local.json` |
| 4 | `<config-root>/shared/plugins/orchestrator.json` |
| 3 | `<config-root>/shared/identity.json` |
| 2 | `./.claude/shared/plugins/orchestrator.json` |
| 1 | `./.claude/shared/identity.json` |

Advisory only, never a slot: `plugins/orchestrator/config/recommended.json` — the catalogue the
configurator works from, with `strength: weak|strong`, contributing **no value to any resolved config**
(OWNER-DECISIONS 3.8). Connectors the orchestrator declares: `tasks` (the board, weak — GitHub Issues
is his hedged first recommendation, `«напевно»`, `../extract/corrections.md` §B), `notify` (weak),
`questions` (weak), `secrets` (weak).

Reusability decides the file: the board, the notification channel and the account roster are usable by
other plugins and belong in the **general** config; run-loop knobs (ticks, thresholds, stop rules) are
usable by nothing else and belong in `orchestrator.json` (OWNER-DECISIONS 3.4).

## 9.2 The run scope, and why it is not a seventh slot

He requires three scopes — global default, project, this run (R1-12 [331], Д7, cross-cutting §1 of
ANALYSIS-01). His marketplace says **three levels are the whole set and a resolver supports no other**
(OWNER-DECISIONS 3.6, `docs/config-levels.md` §1).

**Resolution, stated as a tension rather than resolved away.** The run scope is **not a config file and
not a slot**. It is *run input*: `orchestrator:run --set behaviour.max_parallel=2 --mode controlled`
writes `runs/<run-id>/run.json`, and the conductor applies it as an overlay **above slot 6** for this
run only. `resolved-config.json` records, per key, which slot or `run.json` supplied it. Nothing is
written into a config file, no seventh slot exists, and the resolver is untouched — but the effective
value for the run does differ from the resolved config, and a reader must look at
`resolved-config.json` to see why. §17.4 records this for his ruling, because it is the one place where
his two rule sets do not compose.

## 9.3 Mid-run change pickup

The cross-cutting requirement that appears more often than any other: *a change made during a run must
be picked up* (Д7, R1-07, Д12).

Every control tick (2 s), the conductor hashes the six config files, `run.json` and `control.yaml`.
On any digest change it re-runs the resolver, diffs the resolved config key by key, and classifies each
changed key by a **class declared in the key's own schema**, not by the file it came from:

| Class | Meaning | Applied |
|---|---|---|
| `tick` | takes effect immediately, no work disturbed | now |
| `next_task` | applies to the next dispatch | at the next claim |
| `next_step` | applies at the engine's next step boundary | at `engine.step_boundary()` |
| `restart_lane` | requires the lane to be stopped and relaunched | per `assignments.apply` |
| `frozen` | cannot change during a run; the change is recorded and refused with one visible line | never |

`frozen` exists because some keys genuinely cannot move: `context.basis` mid-run would make every
threshold in the journal incomparable; `engine.kind` mid-run would leave half a ticket planned by one
process. Sortie's config reload is the precedent — the best in the field — and what makes it good is
*"a documented list of keys that are **not** rebuilt on reload"* (VERIFIED, LANDSCAPE §3C).

**The account change (R1-07 [195]).** `assignments.apply: soft` → class `next_task`. `apply: hard` →
class `restart_lane`: the affected lanes are stopped at the adapter's `hard` semantics, their tickets
requeued with their session lineage recorded, and relaunched on the new account.

**⚠ TENSION, and it is a real bill.** ADAPTER-CONTRACT §3 F is categorical: *"on **every** platform,
changing a running session's account is impossible"* (VERIFIED across fifteen). So R1-07's hard account
change is always stop-and-relaunch with a context re-seed — he pays for the context twice. That is
ADAPTER-CONTRACT §7 question 8 and it is unanswered; the design implements the only thing that exists
and prices it in the journal (`cost.reseed_tokens`).

## 9.4 Asking for what is missing

R1-04 [133]: on a run, read global and project settings, use what is there, **ask for what is missing**
— *"це вже існуюча архітектура для Клод Маркетплейсу"*. And [189]: when the orchestrator asks the user
at config time, it must **explain why it is asking**.

Preflight collects every missing required key into one batch and — in an interactive session — asks
once, through `orchestrator:config`, with the reason per key. **In an unattended run it does not ask;
it refuses with exit 3 and names every missing key.** That is not a weakening of his rule: C3-A4 is
right that the config-by-asking lifecycle has no listener during an autonomous run, and a run that
cannot ask must not substitute (which is also the marketplace's own rule — OWNER-DECISIONS 4.5: *"A run
that cannot ask does not substitute; it skips the source with one visible line"*).

---

# 10. Stops

Д12 [520–524], the one item ANALYSIS-01 correctly labels UNRATIFIED. Three commands, one file, one
tick.

## 10.1 The three verbs

| Verb | Written | Run transition | Lanes | Deadline |
|---|---|---|---|---|
| `stop-soft` | `stop.mode: soft` | `running → draining` | finish current work; start nothing new | none — a lane may run to its natural end |
| `stop-hard` | `stop.mode: hard` | `running → stopping` | `adapter.stop(handle,"hard")` on every lane, then teardown | `stop.hard_deadline_seconds` (DEFAULT-PROPOSED **30**) per lane, then SIGKILL the recorded process group |
| `stop-custom` | `stop.mode: custom, custom: <name>` | per the named rule | per the named rule | per the named rule |

`stop-custom` is his: *"прочитати що це означає і відповідно зробити"* [524], from user-written text
rules or commands. It is `config.stops.custom.<name>`, one of two shapes:

```yaml
stops:
  custom:
    drain-then-report:
      kind: rules          # a text block the orchestrator agent reads and acts on
      text: |
        Let anything with an open PR finish. Stop everything else at the next step boundary.
        Then write a report of what was left and notify me.
    kill-builds:
      kind: commands       # a deterministic list, no model involved
      steps:
        - {op: "lane.stop", where: {step_kind: "build"}, mode: "hard"}
        - {op: "run.drain"}
```

`kind: commands` is deterministic and runs in the conductor. `kind: rules` goes to the orchestrator
agent as a §7.4 question with the text as its authority and the fallback `stop-soft` on deadline — a
custom stop whose model does not answer degrades to the safe verb, never to nothing.

## 10.2 The tick guarantee, precisely

`orchestrator:stop --hard` returns only after: taking `control.yaml.lock`, writing revision N+1 by
atomic rename, and **polling `control.applied.json` until it shows revision ≥ N+1** or
`stop.ack_timeout_seconds` (DEFAULT-PROPOSED **15**) elapses. So the command's own exit code tells the
owner whether the stop was *taken*, not merely *written*. Exit 0 = applied; exit 8 = written but
unacknowledged (the conductor may be dead — the command says so and points at
`orchestrator:doctor`).

Worst-case latency to the decision: one control tick, 2 s. Worst case to effect: 2 s + the adapter's
stop latency + the 30 s kill deadline.

## 10.3 The carve-out

Gas Town's ESTOP carries the rule to copy verbatim: *"The Mayor is exempt from E-stop so it can
coordinate recovery"* (VERIFIED, LANDSCAPE §4). Here: a stop freezes lanes; it does **not** kill the
conductor, and `stop-hard` leaves the conductor alive in `stopping` so that teardown, resource
resolution and the final report all happen. A stop that killed the coordinator would leave exactly the
residue I7 exists to prevent.

`orchestrator:stop --abandon` is the separate, louder verb that also ends the conductor; it is not one
of his three and is named differently so it cannot be reached by accident.

---

# 11. Crash, sleep, and recovery

## 11.1 What survives

| Survives a conductor crash | Survives a reboot | Survives a machine sleep |
|---|---|---|
| `journal.jsonl` (every intent, result, observation, decision) | yes | yes |
| `resources.jsonl` | yes | yes |
| `control.yaml` + `control.applied.json` | yes | yes |
| claim locks | **no** — `flock` dies with its holder, by design (I1) | no | yes (the holder is frozen, not dead) |
| lane child processes | yes, orphaned | no | yes, frozen |
| adapter sessions | yes (where the platform persists them) | depends on the platform | yes |
| projections | yes, possibly stale — rebuilt from the journal | yes | yes |

The deliberate part: **locks do not survive, records do.** A crash therefore always produces the same
shape — a full record and no claims — and recovery is always the same procedure.

## 11.2 The sleep fence

C6-A5 is the failure that ended the previous run, verbatim in the log:
`[2026-09-07T09:08:21Z] watch: orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may
sleep)` (VERIFIED, FIELD-NOTES §10.1). On wake, every staleness reading says dead, the process object
says alive, and **both are correct**.

Mechanism, three parts:

1. Every journal record carries `mono` (`CLOCK_MONOTONIC`) alongside `ts`. Durations are computed on
   `mono`; wall clock is for display only.
2. The conductor detects a **wake** as a tick in which `wall_delta - mono_delta > sleep.gap_seconds`
   (DEFAULT-PROPOSED **60**) — monotonic time does not advance across sleep on macOS, wall clock does
   (VERIFIED behaviour of `CLOCK_MONOTONIC` vs `CLOCK_REALTIME` on Darwin; the specific threshold is
   INFERRED). It writes `observation: machine.wake` with the gap.
3. **A wake invalidates every liveness verdict.** For `sleep.grace_seconds` (DEFAULT-PROPOSED **120**)
   after a wake, no lane may be judged `DEAD` and no capacity reading older than the wake is
   authoritative. Network re-establishment and session resumption happen in that window.

The warden is unaffected, because its probe is the lock, not a clock (I1). `launchd StartInterval`
fires after wake where `cron` would not.

## 11.3 The reconciler

Runs at every conductor start, and on demand via `orchestrator:reconcile`. Four phases:

**Phase 1 — fold.** Read the journal to the last well-formed record. Rebuild run, lane, ticket and
resource states. Record `journal.tail_truncated` if the last line was partial.

**Phase 2 — orphan detection.** Every `intent` with no `result` is an orphan (I3). For each, look up
`ops.json.reconcile`:

| `reconcile` | Probe | Verdicts |
|---|---|---|
| `read_ref` | read the git ref now; compare with `args.before`/`after` | `confirmed_done` / `confirmed_not_done` |
| `refetch` | re-fetch the board item; compare the field | `confirmed_done` / `confirmed_not_done` / `indeterminate` (board unreachable) |
| `probe_session` | `adapter.resume(session_ref)` or list sessions by the client-assigned id | `confirmed_done` / `confirmed_not_done` / `indeterminate` (server-minted id, §11.4) |
| `read_context` | `adapter.readContext`; compare with the pre-compaction reading | `confirmed_done` / `indeterminate` |
| `none` | — | `indeterminate` |

**Phase 3 — decide.** `confirmed_done` → synthesise the missing `result` with the probe as evidence.
`confirmed_not_done` → replay under the same `idem`. `indeterminate` → by idempotency class: `by_ref`
and `by_readback` replay safely; `by_session_id` replays if the id is client-assigned;
**`unsafe` escalates to the questions channel and the lane stays `reconciling`**. It never guesses.

**Phase 4 — adopt or stop (Д10).** For each lane whose child process is still alive: read
`resources.jsonl`, match process groups by `(pid, start_time, argv_sha256)`, and hand the surviving
list to the orchestrator agent as a §7.4 question with options `adopt | stop | wait`. That is Д10 [497]
exactly — *"the orchestrator analyses what those sessions are and decides to stop or wait, within its
permissions"* — with the identity problem solved underneath it, because C8-A3 is right that tty and pid
alone are recycled by the OS.

## 11.4 The crash window that cannot be closed

`dispatched` is the one lane state where recovery is genuinely hard, and only on some platforms.
Where the client names the session id before launch (Claude Code, pi, Droid, OpenCode, Qwen —
VERIFIED), the intent is written with the id and recovery is a probe. Where the server mints it
(Codex, Kimi, Amp, MiMoCode), there is a window between launch and first record in which a crash leaves
a session that exists and cannot be named.

**Policy.** For server-minted lanes, the first `dispatch.window_seconds` (DEFAULT-PROPOSED **45**) of a
lane are declared **unrecoverable by id**; recovery is by **re-dispatch into a fresh workspace**, and
the orphan session is recorded in `resources.jsonl` as `unowned_session` with everything known about it
(platform, account, launch time, cwd) so that teardown can still find it by account listing and the
owner can still find it by hand. On Gemini CLI it is worse and it is stated: a session with no
completed model turn *"is deleted and is unresumable"* (VERIFIED), so an early failure there leaves no
recovery point at all.

## 11.5 Recovery sources

R1-10 [293, 307]: default is the state files; additionally previous sessions and their transcripts; the
user configures which options are allowed and the orchestrator picks.

`recovery.sources` is an ordered allow-list, DEFAULT-PROPOSED **`[journal, engine_artifacts,
transcripts]`**:

1. `journal` — always first, always sufficient for the run's own state (I5).
2. `engine_artifacts` — the engine's `observe()`, which is where the *work's* state lives.
3. `transcripts` — the platform's own record, per-platform (his [310]). **Only usable where the
   transcript is durable**; where it exists only on the pipe (Amp, `dsh`), the adapter must have tee'd
   it to disk under the lane directory and declared that in `capabilities()` (ADAPTER-CONTRACT §3 C) —
   otherwise a dead supervisor destroyed the evidence, which collides with R1-10's own requirement that
   the orchestrator's death be survivable.

The orchestrator agent picks among the allowed sources; the conductor executes. Where the user has
written their own recovery skill for a platform ([312], recorded in `../extract/corrections.md` as
never restated back to him), it is an adapter op: `adapters/<id>/recover`.

## 11.6 Takeover by the warden

The only path by which anything other than `orchestrator:run` starts a conductor.

```
every warden.interval_seconds:
  take machine.lock
  for each run in runs.index.jsonl with state != deregistered:
      try flock(run.lock, non-blocking)
      ├─ FAIL  → LIVE.        record, release, next run.
      └─ OK    → read owner.json
                 ├─ pid alive AND start-time matches AND argv matches
                 │     → SPLIT BRAIN. release the lock, notify, exit 5, DO NOT SPAWN.
                 ├─ a machine.wake within sleep.grace_seconds
                 │     → UNKNOWN. release, retry next interval.
                 └─ otherwise
                       → DEAD. bump epoch, write owner.json, and — holding the lock —
                         exec a conductor in `recover` mode, which inherits the lock fd.
```

The takeover conductor **never re-runs the run from the start**; "start over" means restart the
orchestrator, not redo the work ([300], ratified). It enters `preflight` in `recover` mode, which skips
gates that cost tokens and re-runs gates 1, 5, 6 and 7 — because an account may have expired in the
hours since (C4-A8).

**`warden.on_unknown`** (DEFAULT-PROPOSED **`notify_and_hold`**) is the answer to C6-A2's third verdict,
and it is the direction his own words point: *"якщо раптом одночасно два … це не окей"* [300] is an
absolute, while *"ран зупинився"* [246] is a problem to be solved, and an absolute outranks a problem.
The cost is real and is stated: a run can sit dead until morning if the warden can never resolve
`UNKNOWN`. The mitigation is that `UNKNOWN` here is rare by construction — the probe is a local
`flock`, not a network call, so the outages that produced C6-A2 (429s, expired tokens, cross-account
blindness) cannot reach it.

---

# 12. Ending, and cleaning up what it started

## 12.1 The terminal condition (Д3)

*"No ready work left → finish."* This is requirement R1 in ADOPTION-VERDICT's list, and LANDSCAPE §5
confirms it after a full survey: *"Every tool in the survey that has a real multi-ticket queue is an
explicitly resident daemon"* — Gas Town, Sortie, Symphony, Cyrus, Vibe Kanban, agent-deck and Claude
Squad all return **zero hits** for `drainAndExit | exitWhenIdle | shutdownWhenEmpty | queueEmptyExit`
(VERIFIED). It is unowned by the field and it is one of the things that makes the tool the thing it is.

The condition, evaluated on each schedule tick in `running` or `draining`:

```
queue_drained = (no ticket in ready state after a fresh board fetch)
            AND (no lane in a non-terminal state)
            AND (intake == frozen OR intake_quiet_for >= end.intake_grace_seconds)
            AND (no lane in waiting:human, OR behaviour.when_only_human_blocked != wait)
```

`end.intake_grace_seconds` (DEFAULT-PROPOSED **300**) exists because Д2 allows work to be added
mid-run; without a grace window a run that drains at 03:00 exits thirty seconds before the owner's
02:59 ticket is picked up.

## 12.2 The resource ledger

Written **before** creation, which is the whole trick (I7, and ADOPTION-VERDICT §4 item 8's
"append `start` first"):

```jsonc
{"seq":…,"kind":"intent","op":"resource.create","res":"r14",
 "type":"docker_compose_project","owner_tag":"orc.run=20260919T2312Z-a7f3",
 "identity":{"project":"orc-L07","labels":{"orc.run":"…","orc.project":"sha256:…"}},
 "teardown":{"op":"compose.down","args":{"project":"orc-L07","volumes":true}}}
{"seq":…,"kind":"result","for":"…","outcome":"ok","evidence":[{"kind":"process_exit","code":0}]}
```

Resource types and their identities:

| Type | Identity that survives a process death | Teardown | Proof of teardown |
|---|---|---|---|
| `session` | `(platform, account, session_id)` | `adapter.stop` then assert | `process_absent` + adapter listing |
| `process_group` | `(pgid, leader_start_time, argv_sha256)` | `kill(-pgid, TERM)` then `KILL` | `process_absent` |
| `git_worktree` | absolute path under the run's worktree prefix | `git worktree remove` | `file_digest` of absence |
| `docker_compose_project` | the compose project **name**, and container **labels** | `compose down -v` with the project passed explicitly | `docker ps --filter label=orc.run=…` empty |
| `port_block` | the reserved range, recorded | released by record | — |
| `unowned_session` | whatever is known (§11.4) | listed, never auto-killed | — |

**`COMPOSE_PROJECT_NAME` is never relied on.** The project name is passed on the command line at both
create and teardown, and the containers additionally carry labels, so a teardown performed by a
detached process with no environment cannot resolve to the default project. That is the direct fix for
FIELD-NOTES §11.5 (VERIFIED: the owner's own default stack destroyed by a `docker compose down -v` with
no project exported) and for C8-A2, which points out that teardown is *precisely* the moment most
likely to be run by a detached process.

## 12.3 Teardown

In `stopping`, in this order, each step an op with evidence:

1. Stop lanes (soft or hard per §10), asserting each process gone.
2. Resolve the resource ledger **in reverse creation order**. Each resource gets `resolved:ok`,
   `resolved:absent` (already gone — fine), or `resolved:failed`.
3. Release claims and write final board states.
4. Write `reports/<ticket-id>.md` per ticket and `status.json` final.
5. Deregister from `runs.index.jsonl` under `machine.lock`.
6. Append `run.finished` or `run.degraded`.

**Any `resolved:failed` makes the run `degraded`, exit 6, and names every unresolved resource.** The
run never claims a clean finish it cannot evidence (I4).

## 12.4 Someone else's residue (C8-A1)

Д3 and R1-16 together forbid a run from touching what it did not start, which leaves a previous
crashed run's residue unreclaimable by anyone — and FIELD-NOTES §11.11 records ~150 orphaned Docker
volume pairs from exactly that (VERIFIED).

**`orphan_reclaim`** (DEFAULT-PROPOSED **`same_tool_confirm`**):

| Value | Behaviour |
|---|---|
| `off` | strictly his rule: never touch a previous run's residue. Preflight reports it and refuses on a port or path collision. |
| `same_tool_confirm` | reclaim only resources carrying **this tool's** owner tag, for **this project**, whose owning run's lease is provably dead (the flock is acquirable and the owner pid is gone), and only after an interactive confirmation or an explicit `--reclaim` flag. |
| `same_tool_auto` | as above, unattended. |

This is the narrowest widening of his rule I can justify: it never touches anything without the
orchestrator's own label, and it never acts while the owning run might still be alive. §17.5 records it,
because it is a widening and he did not authorise one.

---

# 13. What the owner sees

Д11 [508–514], with the correction that `../extract/corrections.md` flags as buried:
he first said the orchestrator must output nothing, then corrected himself to **minimum output by
default, user-reconfigurable**. The corrected version governs.

## 13.1 During the run

Nothing. The conductor's stdout goes to `runs/<run-id>/run.log` and nowhere else. No terminal is
opened for the owner. Notifications are sent only for the event classes he enabled.

`notify.on` (DEFAULT-PROPOSED **`[run_finished, run_degraded, stop_applied, needs_human,
failure_budget_exhausted, split_brain]`**) — six classes, each a real thing he would want to know at
03:00 and nothing else. `notify.channel` is a connector (R1-17: Telegram, Slack, Gmail, a call, or just
the terminal). Every delivery is an op with `http_status` evidence; a failed delivery is recorded and
retried with backoff, and a channel that has failed `notify.dead_after` (DEFAULT-PROPOSED **3**)
consecutive times raises `notify.channel_dead` into `status.json` — the one place the run can still
speak.

## 13.2 When he asks

`orchestrator:status` — a file read. Zero tokens, zero network, exit 0. Default output is one screen:

```
run 20260919T2312Z-a7f3   running    started 23:12Z (4h 18m)   engine gsd@2.3.1   mode autonomous
queue   ready 6   claimed 2   blocked 1   done 11
lanes   L07 working   gh#412  claude-code/<profile-B>  ctx 41% (raw)  3h 02m
        L08 waiting:human  gh#418  q: Q-ORCH-07 (28m)
capacity  5h 44% (fresh 12m)   7d 71% (fresh 12m)   reserve 10%
control   revision 7 applied 03:02:11Z    stop none
health    heartbeat 3s   last wake none   orphans 0   degraded resources 0
```

`--json` emits `status.json` verbatim. `--since <seq>` prints the journal tail. `--why <lane>` prints
the observations and decisions behind that lane's current state — which is the thing FIELD-NOTES §11.3
shows is missing when a detector fires wrongly at 04:00 and nobody can tell why.

**⚠ TENSION (C9-A10).** He described running `orchestrator:status` *"in a separate terminal"* [508],
which assumes one run, one project and a working directory — and Д4's worktrees guarantee the working
directory is often wrong. Fix: `orchestrator:status` with no argument reads `runs.index.jsonl` from the
machine root, so it finds runs regardless of cwd, and prints a picker when several are live.

## 13.3 The questions channel

Д6's channel is where the run speaks when it needs him, and it is separate from `control.yaml` because
he explicitly allows it to be a GitHub issue or a tracker task. Reading it is a control-tick digest
check; writing to it is a mutating op with readback evidence.

## 13.4 The red-line file (R1-15)

One text file, mandatory reading for every agent, no enforcement machinery in the plugin
([357]). Path `prohibitions.path`, DEFAULT-PROPOSED **`<project>/.orchestrator/PROHIBITIONS.md`**.

Two mechanisms, both cheap, neither an enforcement machine:

1. **Injection is evidenced.** The file's `sha256` is recorded in the dispatch intent, and the lane's
   prompt carries it. "Every agent read it" becomes a journal fact rather than a hope.
2. **Re-injection after compaction.** OpenClaw's `post-compaction-context.ts` is the design worth
   copying and the reason is specific: *compaction deletes the red lines mid-run*, repeatedly, in a run
   long enough for it to happen. Its details are what make it worth copying rather than reinventing —
   fenced-code-block-aware heading extraction, a bounded 1,800-character budget with UTF-16-safe
   truncation, and **every failure path returning null** so a missing or oversized file degrades to no
   injection rather than to an error (CLAIMED, ADOPTION-VERDICT §4 item 3).

**⚠ TENSION, and it is the sharpest one in the document.** His answer is the direct opposite of the
evidence he was shown: FIELD-NOTES §11.5 records a session refusing a destructive command as owner-only
and the owner's default stack being destroyed by that same command two minutes later, actor never
identified (VERIFIED). ANALYSIS-01 flags the contradiction twice with "see challenges" and there is no
challenges section (`../extract/corrections.md` §I). And R1-15 is the **weakest-grounded answer in the
interview**: never confirmed, and he closed it by asking whether he had even answered the question
[357]. I design for his decision — one file, no machinery — and record that this is the item most in
need of re-opening.

---
# 14. Run modes, defined as a property of the state machine

R1-14 is **OPEN by his instruction** [082]: the collecting agent must analyse and propose definitions
of *controlled* and *autonomous*. `../extract/corrections.md` §B records something stronger — at [058]
he is not sure the two are even different things. So the proposal below is deliberately the smallest
distinction that is mechanically checkable, offered as options rather than as a decision.

The reliability lens gives one natural definition, because the whole design already routes every
judgement through §7.4's typed question with an `authority` block:

**Mode is the value of one field: what happens to a question the run cannot answer from config.**

| | `controlled` | `autonomous` |
|---|---|---|
| a §7.4 question with no config answer | goes to the questions channel; the lane enters `waiting:human` and holds ([062]: *"хардстоп … поки людина не відпустить"*) | goes to the orchestrator agent, which answers from its configured basis and **reports afterwards** ([062]) |
| `authority.may_stop` | true | true — he was explicit that an agent may force a hard stop even in an autonomous run [082] |
| decision basis | config only | config, plus the bases he named [082–094]: written rules, examples of past decisions ("tone of voice"), previous answers to similar questions, the agent's own knowledge of the project |
| `decision.reported` | n/a | false until delivered; the report is the run's obligation |
| the queue | keeps moving (Д6) | keeps moving |

Two things this definition buys, both reliability properties: the mode is a **single field on every
question record**, so a mid-run mode flip has defined semantics for decisions already taken (they are
not re-opened — C1-A10's gap), and a run's whole decision history can be replayed and audited by
filtering `kind:"decision"`.

`run.mode` ∈ `ask | autonomous | controlled` ([075]: config supports three values, overridable per
run). **⚠ TENSION:** `ask` has no answer for a warden takeover at 04:00 (C1-A5) — there is nobody to
ask. `run.mode_on_takeover` (DEFAULT-PROPOSED **`controlled`**) is the fallback, because a recovered
run that asks rather than guesses is the conservative direction, and §17.5 records it as his to rule on.

**Decision bases are untrusted input.** C1-A8 is right: *"tone of voice in this repository"* makes the
decision basis a file an agent reads, and files in a repository are input, not instruction. Every basis
document is loaded with the same untrusted-content fencing the previous generation already applied to
ticket bodies (VERIFIED: `harness-tickets.sh:43-49`, `fence_body` wrapping bodies in an UNTRUSTED-input
sentinel that neutralises embedded fake sentinels), and its digest is recorded in the decision record.

---

# 15. Every default, in one table

The owner stated almost none of these. Each is `DEFAULT-PROPOSED` and each names what it protects
against. This is the review page.

| Key | Default | Class | Protects against |
|---|---|---|---|
| `tick.control_seconds` | 2 | frozen | a stop that takes minutes; Д12 promises "next tick" |
| `tick.heartbeat_seconds` | 5 | tick | a takeover deciding on a stale beat |
| `tick.lane_seconds` | 10 | tick | a finished lane sitting registered (FIELD-NOTES §1.6: 1 day 4 h) |
| `tick.schedule_seconds` | 15 | tick | a drained queue idling |
| `tick.capacity_seconds` | 3600 | tick | 429ing the quota endpoint (C4-A3, VERIFIED) |
| `warden.interval_seconds` | 900 | tick | a dead run sleeping until morning; his "N hours" is longer than every real failure (C6-A10) |
| `warden.probe_kind` | `deterministic` | frozen | cross-account roster blindness (C6-A1, VERIFIED) |
| `warden.on_unknown` | `notify_and_hold` | tick | two orchestrators, which he called «не окей» absolutely |
| `behaviour.max_parallel` | 2 | tick | the only concurrency ceiling he allows is his (R1-05 [163]) |
| `limits.max_concurrent_builds` | 1 | tick | his own container OOM-killed by two parallel builds (FIELD-NOTES §5.1, VERIFIED) |
| `limits.<window>.soft_pct` | 85 | next_task | hitting the wall with work in flight |
| `limits.<window>.hard_pct` | 95 | tick | spending past the point where state can be saved |
| `limits.<window>.reserve_pct` | 10 | tick | the run eating the subscription he needs in the morning — **the sub-question never asked** (`corrections.md` §F) |
| `limits.credit.ceiling` | unset → **refuse** the lane | frozen | a credit lane with no reset and no ceiling spending all night (ADAPTER-CONTRACT §3 E) |
| `limits.on_unknown` | `notify_and_hold` | tick | the shipped `proceed`, which makes the limiter provably inert (C4-A6, VERIFIED) |
| `context.basis` | `raw_window` | frozen | a threshold that never fires, or fires a third too early (C5-A2, VERIFIED) |
| `context.soft_pct` / `hard_pct` | 75 / 90 | next_step / tick | auto-compact firing first and the configured action never running once |
| `context.compact_deadline_seconds` | 600 | tick | "compacting" as a permanent state (J-WATCH-01 measured ~7 min) |
| `context.on_no_trigger` | `soft_only` | frozen | pretending hard mode works on Amp/Gemini/Cursor/`dsh`, where it is impossible (VERIFIED) |
| `liveness.unknown_ceiling_seconds` | 900 | tick | the 33-nudge loop, and the 12-minutes-into-14 restart loop (C6-A4) |
| `sleep.gap_seconds` / `grace_seconds` | 60 / 120 | tick | the exact way the previous run died (FIELD-NOTES §10.1, VERIFIED) |
| `dispatch.window_seconds` | 45 | frozen | a server-minted session that exists and cannot be named (§11.4) |
| `stop.hard_deadline_seconds` | 30 | tick | a hard stop that never completes |
| `stop.ack_timeout_seconds` | 15 | tick | a stop the owner believes was applied and was not |
| `failure.identical_threshold` | 3 | next_task | his number [442] |
| `failure.on_exhausted` | `park` | next_task | stopping a whole run over one bad ticket |
| `agent.decision_deadline_seconds` | 300 | tick | a run hanging on a model that stopped answering |
| `engine.on_indeterminate` | `needs_review` | next_task | advancing an empty issue into a person's queue (Sortie ADR 0020) |
| `worktree.policy` | `engine` if owned, else `per_task` | frozen | two owners of one branch name (FIELD-NOTES §4.3, VERIFIED) |
| `end.intake_grace_seconds` | 300 | tick | exiting thirty seconds before his 02:59 ticket lands (Д2) |
| `orphan_reclaim` | `same_tool_confirm` | tick | ~150 orphaned volume pairs nobody may clean (FIELD-NOTES §11.11, VERIFIED) |
| `notify.on` | 6 classes (§13.1) | tick | both failure directions: silence, and a night of noise |
| `notify.dead_after` | 3 | tick | a verified channel that died mid-run (FIELD-NOTES §11.6, VERIFIED) |
| `run.mode` | `ask` | run input | guessing which mode he wanted |
| `run.mode_on_takeover` | `controlled` | tick | `ask` with nobody to ask at 04:00 (C1-A5) |
| `recovery.sources` | `[journal, engine_artifacts, transcripts]` | tick | recovering from a record the crash destroyed |
| `prohibitions.path` | `<project>/.orchestrator/PROHIBITIONS.md` | frozen | the file forking into a worktree copy (FIELD-NOTES §12.5, VERIFIED) |
| `status.verbosity` | `minimal` | tick | his corrected Д11 [511–514] |

---

# 16. Commands and exit codes

All commands are `orchestrator:<verb>`; the plugin is `orchestrator`.

| Command | Does | Writes |
|---|---|---|
| `config` | the two-question wizard, then the missing-key batch with a reason per key | config slots 3/4 per OWNER-DECISIONS §7 |
| `init` | creates `.orchestrator/`, the prohibitions file, the gitignore entries | project |
| `add` | adds a ticket to the local registry, or a board item | ticket source |
| `run` | preflight, take the lease, run to a terminal state | the run directory |
| `status` | read-only projection | nothing |
| `doctor` | lane table, capability maps, resolved account ids, machine checks | nothing |
| `stop` | `--hard` / `--soft` / `--custom <name>` / `--abandon` | `control.yaml` |
| `resume` | clears a stop, or restarts a conductor over an existing run directory | `control.yaml` |
| `reconcile` | runs §11.3 out of band; `--rebuild` regenerates projections | projections |
| `warden` | `install` / `status` / `uninstall` | `launchd` |

**Exit codes**, one table, stable, never inferred from anything:

| Code | Meaning |
|---|---|
| 0 | success; for `run`, the run reached `finished` |
| 1 | internal error (a bug in the orchestrator) |
| 2 | usage error |
| 3 | preflight refused; every failing gate is named |
| 4 | no such run, or the run directory is unreadable |
| 5 | lease held by another live process, or scope conflict, or split brain |
| 6 | run reached `degraded` — work happened, teardown or evidence did not fully resolve |
| 7 | run ended because the owner stopped it |
| 8 | run ended in `paused:capacity`, or a stop was written but unacknowledged |
| 9 | run ended in `paused:human` — only human-blocked work remained |
| 130 | interrupted |

---

# 17. Where a decision is not implementable exactly as stated

Four. For each: which clause is impossible, and what keeping it would cost.

**17.1 R1-06.1 — *"дочекатись рестарту ліміту і продовжити"*, on seven of fifteen platforms.**
Impossible clause: *wait for the reset*. On pi, Qwen, MiMoCode, OpenCode, Aider, Cursor (personal plan)
and Amp there is no readable remaining capacity and, for the credit platforms, no reset at all — the
model is money, not time (VERIFIED, ADAPTER-CONTRACT §3 E). **Cost of keeping it:** a spend ceiling in
money per run, set by him, plus accepting that such a lane stops and notifies rather than auto-resuming.
This design ships that (`limits.credit.ceiling`, refusing the lane until set) and raises the question.

**17.2 R1-08 — *"повинен бути механізм, який гарантовано робить цю дію"*, in its strongest form.**
Impossible clause: *guaranteed*, on Amp, Gemini CLI, Cursor and `dsh`, where an external compaction
trigger does not exist at all (VERIFIED). **Cost of keeping it:** either exclude those platforms from
any context-bounded work, or accept that on them the guarantee is *"one of three named outcomes within
a bounded time"* rather than *"the compaction happens"* — which is what §6.2 implements. There is also
a smaller impossibility: on `dsh` and Gemini the threshold must be fixed **before** the run and cannot
change during it, which breaks the cross-cutting rule that a mid-run change is picked up (Д7, Д12).

**17.3 R1-07 — a *hard* account change that *"діє негайно"*.**
Impossible clause: *in place*. Changing a running session's account is impossible on **all fifteen**
platforms (VERIFIED). **Cost of keeping it:** stop, relaunch on the new account, and re-seed the
context — paying for the context a second time, per affected lane. §9.3 implements that and prices it
in the journal. The alternative he might prefer is that a hard change waits for the current step, which
is his `soft` and would make the two indistinguishable.

**17.4 The run scope, against his own marketplace rule.**
Impossible clause: *three config scopes*, where his marketplace says **"These three levels are the
whole set. A resolver supports no other level"** (OWNER-DECISIONS 3.6, VERIFIED) and the third of those
is the marketplace level, which supplies no values. **Cost of keeping both rules:** the run scope is
not a config file and not a slot; it is run input applied as an overlay for one run, recorded per key
in `resolved-config.json` (§9.2). Nothing is written into a config file and the resolver is unchanged,
but the effective value for a run can differ from the resolved config, which is a thing a reader must
be told to look for.

## 17.5 Open, and his to rule on

Everything below is designed for with a default and needs a yes or a correction. It is short on purpose.

1. **Headroom reserve for his own work** (`limits.*.reserve_pct`) — the sub-question the interviewer
   dropped; there is no answer anywhere in the transcript (`corrections.md` §F).
2. **`warden.on_unknown`** — hold (his absolute wins, a run may sleep till morning) or take over
   (availability wins, two orchestrators become possible). C6-A2.
3. **`context.basis`** — raw window, or the status-line number he has actually been reading, which
   differs by ~13 points (C5-A2, VERIFIED in his own installed hook).
4. **`orphan_reclaim`** — this design widens his rule narrowly (§12.4); he did not authorise a widening.
5. **`run.mode_on_takeover`** — `ask` has nobody to ask at 04:00 (C1-A5).
6. **Answering a session's own question on Claude Code headless** — supported where the platform allows
   it, impossible on the lane he is most likely to run; the alternative is to prevent the question,
   which weakens R1-02 (ADAPTER-CONTRACT §7 q12).
7. **R1-15, the red-line file** — the weakest-grounded answer in the interview, never confirmed, and the
   direct opposite of the evidence presented with the question (§13.4).
8. **The 22 unratified restatements** in `../extract/corrections.md` §C, several of which this design
   leans on hard — the soft/hard stop vocabulary (R1-06), the per-platform account-switch verification
   (R1-07), the every-task-in-a-worktree default (Д4), and Д12 itself.

---

# 18. What this lens makes worse, what it drops, and where it is weakest

## 18.1 What it makes worse

**It is slower to first light, and the slowness is front-loaded where it is least visible.** The
journal, `ops.json`, the evidence kinds, the reconciler and the resource ledger must all exist before
the first ticket can run end to end, because I3 and I4 are enforced by the appender rather than by
convention. A design that wrote state files and trusted exit codes would run a ticket in a weekend.
This one will not, and the work it front-loads pays off only on the nights something goes wrong.

**It adds latency to every mutating operation.** Two journal records, an `fsync`, and a readback probe
per board write, per merge, per dispatch. On the observed throughput (FIELD-NOTES §9.5: worker sessions
of 1–5 hours) this is noise. On a run of many small tickets it would not be.

**It makes the orchestrator less clever than he described.** He speaks of an agent that watches its
sessions and judges them [231]. Here, the judging happens on a bounded question with an admissibility
table attached, and most of the time the conductor answers deterministically without asking. The agent
is consulted less often than his words imply, and its authority is narrower than "it decides": it
chooses among offered options, and it cannot act — the conductor acts.

**It spends configuration on things he never asked about.** Thirty-eight defaults in §15, most of them
mechanism-level. That is a lot of surface for a man whose stated ideal is that the thing outputs
nothing and asks him nothing. Every one of them is defensible individually and the aggregate is still a
cost he did not sign up for.

**It is macOS-shaped in two places that matter.** The sleep fence (§11.2) and the keychain preflight
gate are written against Darwin behaviour. On Linux the sleep fence is dead code and the keychain gate
is a no-op; on Windows both are wrong. Nothing in his requirements is macOS-specific, so this is the
lens importing the machine.

## 18.2 What it drops

**Anything about making the work good.** Plan quality, review depth, prompt design, model routing for
capability rather than for cost, the whole question of whether a ticket was worth doing — none of it is
here. That is R1-13's decision (verification belongs to the process) used as permission to ignore an
entire half of the product.

**Cost.** ADAPTER-CONTRACT §6.5 says cost asymmetry is *larger* than scheduling asymmetry — Droid's
credit multipliers span 150×, GLM-5.3-Flash undercuts MiMo-V2.5-Pro ~3× on input, and pi on an
Anthropic subscription bills per token as extra usage so "run until the limit" has no natural stopping
point (VERIFIED). This design treats cost as a ceiling to stop at, never as a scheduling input. A
cost-first lens would route model selection per role and per step; here, `costMeter` is optional and
unused except for reporting.

**Throughput.** There is no backfill, no speculative claiming, no work-stealing, no lane pooling, and
the concurrency ceiling is a single integer he sets. FIELD-NOTES §5.3 is the excuse — across 34 hours
the account reached 26 % of its weekly allowance and *"the dependency graph, not the quota, bounded
throughput"* (VERIFIED) — but it is an excuse, not an argument, and it will stop being true on a queue
of independent tickets.

**The interactive half of R1-11.** Everything here assumes a headless or adapter-driven lane. Visible
terminals the owner can type into are supported only as "a lane whose adapter declares
`launchAttached`", and takeover of a headless lane is a handoff (stop → relaunch attached → resume)
that costs one restart. Qwen Code is the only platform in the field with a visible terminal a
supervisor can still drive (VERIFIED), and this design does nothing special with that.

**The Д9 conflict semantics.** "The change contradicts finished work" is routed to the orchestrator
agent as a §7.4 question with his four options and nothing more; there is no machinery for detecting
the contradiction in the first place, which LANDSCAPE §5 confirms nobody has built
(*"Nothing found re-reads a ticket's description mid-run and changes what the agent is doing"*).

**R1-16's second case, almost entirely.** His parallel work in the same folder is confined by
worktrees, process-group identity and labelled containers — which is isolation of *the run*, not
protection of *him*. LANDSCAPE §5 confirms this is unsolved across the entire field and *"must be
invented rather than adopted"*, and he has explicitly routed it to a separate agent for options [378].
This document does not invent it.

## 18.3 The single weakest point

**The conductor is a single process on a single machine, and everything depends on its lock.**

I1 buys a great deal: no verdict in the critical path, no cross-account blindness, no TTL heuristic, a
takeover path that cannot produce two orchestrators. It buys all of that by making one `flock` on one
local file the sole source of authority. Three consequences follow, and the third is the one that
worries me.

*First*, if the lock file's filesystem is not local — a network mount, a synced folder, a container
bind — `flock` semantics degrade and the invariant silently weakens. Preflight can check the filesystem
type and refuse, and it does; but it is a check, not a guarantee.

*Second*, `SIGSTOP` and a wedged-but-alive conductor are indistinguishable from a healthy one, because
both hold the lock. The warden will correctly refuse to take over, for ever. The run stops and nothing
says so until the owner opens the laptop — the exact shape of FIELD-NOTES §11.6's 85-minute loop, where
line 5620 reads `NO ONE IS BEING TOLD`, moved one level down. The mitigation is thin: the warden
compares heartbeat age against the lock and raises `conductor_wedged` after
`warden.wedged_after_seconds`, but it may not act on it, because acting means taking a lock it cannot
take.

*Third, and worst*: **the conductor is deterministic code that I have argued is the trustworthy part,
and its trustworthiness is entirely unearned.** Every failure in FIELD-NOTES §11.3, §11.9 and §12.2 is a
deterministic checker that was wrong and did not know — a probe that could never succeed and never
complained (BSD `find -newermt` with stderr to `/dev/null`, which *"would have declared every healthy
session idle for ever"*), a parser silently substituting a tighter ceiling, a marker detector globbing
the wrong directory, a self-patch script reporting `SYNTAX OK` while its `sed` anchor never matched and
nothing was written, gates found broken only by mutation rather than by failing. All VERIFIED. This
design's response to "a model cannot be trusted at 03:00" is to move the load onto deterministic code,
and the field record says deterministic code fails *more quietly* than a model does, not less. The
mitigations — three-valued verdicts, evidence-gated results, a fencing epoch, a journal that a human
can read — are real, and they are mitigations of the same class of bug in the layer I have made
load-bearing.

The honest statement of the weakest point is therefore not "the lock might fail". It is: **this design
concentrates trust in one small, single-threaded, model-free process, and the only proof that such a
process deserves that trust is the test suite someone has not written yet.** Every invariant in §1
carries a test for exactly this reason, and until those tests exist and are verified by mutation —
breaking each invariant on purpose and confirming the suite goes red — this architecture is a claim,
not a property.
