# JUDGE-cost — the four designs judged on what they cost to build and to run

**Date:** 2026-09-19. **Axis:** cost to build and cost to run.
**Judged:** `ARCH-minimal.md`, `ARCH-reliability.md`, `ARCH-adapters.md`, `ARCH-operability.md`, each read in
full.
**Authority:** `../../round-1/ANALYSIS-01.md` is the source of truth for what the owner wants. Nothing below
proposes changing a decision of his; where a decision makes something expensive, the price is named and the
decision is kept.

**Evidence tags.** **VERIFIED** — read in a primary source, or executed on this machine today (2026-09-19).
**CLAIMED** — a document asserts it and I did not run it behind them. **INFERRED** — my reasoning from the
above; it is an estimate, not a fact, and is stated so it can be rejected.

**Scoring direction.** 10 = cheapest to build, cheapest to run, cheapest to change, and maintainable by one
person. 1 = the opposite. A design is *not* penalised for the requirements it satisfies; it is penalised for
the machinery it needs per requirement satisfied, and for machinery whose cost recurs.

---

## 0. What I measured, and the six sub-measures

The brief names six things. I scored each separately before scoring the whole, because three of the four
designs are cheap on some and expensive on others, and an aggregate hides that.

| # | Sub-measure | How I judged it |
|---|---|---|
| **C1** | **How much code** | Lines to the first unattended night with **one** platform, **one** engine, **one** board — not the full fleet. Estimates are INFERRED from each document's own component lists and from the previous generation's measured size. |
| **C2** | **How much of it is subtle** | Code where a silent wrong answer is possible and a test would not obviously catch it. Weighted heavily, because the repo's own memory rule is that its harness greps prose and *"tests can pass vacuously"*, so subtle code here is not covered by the reflex of writing a test. |
| **C3** | **New vs borrowed** | Borrowed = a named artefact that already exists and runs (`acpx`, GSD's `gsd-tools`, the existing bash, `flock` semantics, `jq`). New = must be written and then maintained. A borrowed *pattern* (four lines of bash copied from a doc) counts as new code with a cheap design; only a borrowed *artefact* counts as borrowed. |
| **C4** | **Tokens per hour of supervision** | The recurring bill. Both the floor (a quiet hour) and the ceiling (a detector in a loop), because the previous generation's failures were ceilings, not floors. |
| **C5** | **Time to the first real overnight run** | The date the owner can leave it running. This is the measure he will feel first. |
| **C6** | **Cost to change once it exists** | Per new platform, per new engine, per new requirement, per new default. Plus: can one person hold it in their head. |

### 0.1 The shared baseline, so the deltas are honest

Every one of the four must build the same irreducible core, and none of them gets credit for it:

config resolution over the six snf slots · preflight proofs (account identity, board statuses, notification
channel, worktree env, red-line file) · a claim primitive · one platform launcher · a tick loop reading one
control file · teardown driven by a ledger of what was created · a zero-token status renderer · a GSD probe ·
a notification sender.

**INFERRED baseline: ~1,000–1,400 lines and roughly 10–15 engineer-days** for one person who already knows
this repository. Every number in §1–§4 is measured **against that baseline**, not from zero.

Two measured anchors for calibration, both VERIFIED on this machine today:

- The previous generation is **1,879 lines of bash** across `plugins/harness/bin/*.sh`, **4,336 lines** across
  all its `.sh` / `.md` / `.json`, in **36 files** — and `FIELD-NOTES.md` records it failing across 34 hours in
  ways every one of these four designs is written to prevent. So ~1,900 lines of bash is a *demonstrated*
  build size for this problem and a *demonstrated* failure size.
- `git 2.33.0`, `node v22.18.0`, `python3 3.9.6`, `jq 1.8.1` present; **`flock(1)` is not installed**. So every
  design's lock rests on either the 18-line Python holder (`ARCH-minimal` §1, VERIFIED written and executed
  there) or Node's own `flock`. That is a real, shared, ~20-line cost nobody can skip.

---

## 1. ARCH-minimal — **9 / 10**

| | |
|---|---|
| **C1 code** | ~1,100 lines bash + 18 lines Python, one platform, one engine. **Baseline + ~0.** |
| **C2 subtlety** | Low. The subtle parts are `normalize.sh` (one `jq` program per platform), the reap check (`kill -0` **and** `ps -o lstart=` matched against `start.json`), self-write suppression by content hash, and the fact-sheet renderer. Four small places, each in one file. |
| **C3 borrowed** | Highest ratio of the four. `flock` semantics as a rule not a library; `mkdir` as the claim (one syscall, no code); GSD's own `gsd-tools state` as the completion oracle (~5 lines, VERIFIED executed against a real project); `acpx` available as **one legal value** of `launch.sh` rather than a dependency; the previous generation's readiness headings, measured clean over 327 tickets. |
| **C4 tokens/hour** | The best **floor** of the four: *literally zero on a tick where nothing is open*, which is most ticks. Ceiling is `judge.max_calls_per_hour: 30` on the cheap `watcher` pin. |
| **C5 first night** | Fastest. INFERRED **~12–18 engineer-days**. The claim is `mkdir`, the oracle is a GSD command that runs today, status is `bash` + `jq`, preflight is one script. |
| **C6 cost to change** | Cheapest. New platform = a directory of six small scripts. New provider (GLM, DeepSeek, Kimi-as-endpoint) = a config row, no code. New default = one line. |

**Justification.** This design is the only one whose total build is smaller than the thing it replaces while
doing more, and the reason is structural rather than rhetorical: it deletes the *category* of expensive
machinery by deleting the long-lived model session. With no orchestrator session there is no context window to
compact, no compaction-into-a-tty procedure, no handover that collides with the single-orchestrator invariant,
no heartbeat file, no nudge, no attention file, and no second orchestrator — and each of those is not one
feature but a subsystem with its own failure modes, which the other three designs must each build and then
defend. What remains is bash over directories, where the claim is a syscall that cannot produce two winners,
the completion oracle is a command the owner's own engine already ships, the lock is 18 lines of Python that
were actually executed, and the status command is the same `bash` + `jq` the previous generation already wrote
correctly before routing it through a skill. Its token floor is genuinely zero and its ceiling is a declared
integer, so the bill is predictable in both directions. The honest deduction — and it is the only one — is that
its safety rests on a fact sheet whose coverage is exactly the list of things someone thought to render, and
its own §15.3 proves the point against the run's worst recorded lane; but that is a cost of *omission*, fixable
by adding a line to a renderer, not a cost of *structure*. Nothing here is clever enough to need its author.

---

## 2. ARCH-operability — **7 / 10**

| | |
|---|---|
| **C1 code** | INFERRED ~2,200–2,800 lines. **Baseline + ~1.5×.** Six process kinds, twelve decision predicates, a three-tier change detector, a launchd agent, a notification spool with backoff and coalescing, three morning artifacts plus a tuning patch renderer. |
| **C2 subtlety** | Medium-high, concentrated in two places. The **twelve predicates** are, in the document's own words, *"unvalidated prose"* — and its §17.3 names them as the design's weakest point. The **comment-and-anchor-preserving leaf merge of `control.yaml`** is the fiddliest single routine in any of the four documents: YAML round-trip with comment preservation does not exist in bash, so this silently imports a Node or Python dependency the design never prices. |
| **C3 borrowed** | Second-highest, and the best *specific* borrow in the whole set: GSD's machine-readable surface. VERIFIED here today — `gsd-tools` exposes `progress`, `smart-entry`, `state`, `runtime-identity`, `worktree`, `windows`, `dispatch-isolation`, with `--pick`, `--project-dir`, `--json-errors` and **`--exit-contract=v1\|v2`**. `runtime-identity` returns `{"packageName":"@opengsd/gsd-core","version":"1.14.0"}`. That is an engine adapter that is three subprocess calls and zero tokens, borrowed whole. |
| **C4 tokens/hour** | **The best ceiling of the four, and the only one with arithmetic.** `brain_max_wakes_per_hour: 12` is a hard cap that converts a runaway detector from *spends the night* into *spends twelve wakes and tells someone*. Tier-0/1 deterministic change detection is costed against real ticket sizes: ~$14 per 8-hour night frontier-per-tick → ~$1.42 cheapest-model → **~$0.01 tiered** (CLAIMED from C3 §5.3, derived from measured body sizes). Total supervision claimed *"well under $1"* for 34 hours. |
| **C5 first night** | INFERRED **~25–40 engineer-days**. Slower than minimal, and the slowness is in parts (notifier, warden, scout, artifacts) that can each be stubbed, so a partial build still runs a night. |
| **C6 cost to change** | Medium. The hot/warm/cold key classes and the single-writer table are genuinely cheap discipline that pays forever. Against that: twelve predicates are twelve things to keep in sync with every new signal, and the design needs a scorecard to find out which of them work. |

**Justification.** This is the only design that treats the recurring bill as a first-class object and does the
arithmetic out loud, and on an axis called cost that counts for a great deal: the wake budget, the trip
watermark written before the wake, the three-tier change ladder with the model reached only on a confirmed
diff, and the per-role model pins together turn the owner's cost instinct (Д8, Д11) from a preference into a
mechanism with a number attached. Its GSD adapter is the single cheapest high-value component in any of the
four documents, because it is borrowed rather than written and I verified today that every command it names
exists. What it costs is a fleet: six process kinds, a launchd agent, a lease, a journal, a ledger, a spool and
a control file, each individually simple and collectively more than one head holds — the document says this
itself — plus one genuinely expensive hidden item, the comment-preserving YAML merge, which is the kind of
routine that works for its author and confuses everyone else. And its cheapness has a shape: the design buys a
low bill by replacing continuous model attention with twelve predicates written in advance, so its failure
mode is a night that ticks 4,080 times, spends nothing, breaks no invariant and produces nothing. That is a
cheap night and an expensive morning.

---

## 3. ARCH-reliability — **5 / 10**

| | |
|---|---|
| **C1 code** | INFERRED ~3,500–4,500 lines of Node, **plus a mutation test per invariant** that the document itself makes load-bearing. **Baseline + ~3×.** |
| **C2 subtlety** | **The highest of the four.** The journal appender does not record results, it *refuses* them: an `outcome:"ok"` on a mutating op is rejected unless it carries an admissible evidence object declared for that op in `ops.json`. Around it sit eight evidence kinds, four idempotency classes, a four-phase reconciler with a per-op probe, a fencing epoch checked on every append, split-brain detection over `(pid, start-time, argv digest)`, and a sleep fence computed from `wall_delta − mono_delta` against a boot id. Every one of those is correct. Every one of those is code nobody but its author will ever read voluntarily. |
| **C3 borrowed** | Moderate. The *ideas* are borrowed heavily and well (Qwen's fenced writer lease, OpenClaw's owner identity and durable retry budget, claudexor's four-terminal interaction store, agent-deck's provenance, Sortie's reload classes) — but they arrive as **designs to reimplement**, which the document is honest about, so they land in C1 as new code, not in C3 as borrowed artefacts. |
| **C4 tokens/hour** | Floor: zero, the conductor is model-free. **Ceiling: unbounded** — there is no wake budget anywhere, only a 900 s `unknown_ceiling` and a 300 s decision deadline. Separately, and uniquely, it has a real *machine* bill: a **2-second** control tick that hashes six config files plus `control.yaml` is ~1,800 loop iterations and ~12,600 file hashes per hour, 30× operability's cadence and 120× minimal's — bought to make a stop land in 2 s when the owner asked for *"на наступному тіку"*. |
| **C5 first night** | Slowest but one, and the document concedes the axis in its own words: *"A design that wrote state files and trusted exit codes would run a ticket in a weekend. This one will not."* INFERRED **~40–60 engineer-days**, because I3 and I4 are enforced by the appender rather than by convention, so the journal, `ops.json`, the evidence kinds, the reconciler and the resource ledger must all exist before the first ticket runs end to end. |
| **C6 cost to change** | Mixed, and it contains the best single change-discipline mechanism in the set. `ops.json` makes adding an operation a **data row** that must declare its evidence and its reconciliation, with omission a load-time error. That is cheap and it is right. The offsetting cost is that every new mutating capability now owes an evidence kind and a reconcile probe, so the per-feature price is permanently higher than in any other design. |

**Justification.** This design is expensive in the way that is hardest to argue against, because what it buys
is the elimination of the largest and most costly failure class on record — *reported success and did
nothing* — and a night lost to a phantom merge costs more than an appender does. But on this axis the bill is
plainly the second-largest and it is front-loaded exactly where it is least visible: nothing runs until the
enforcement machinery exists, so there is no partial build that survives a night, and the design's own §18.3
states the remaining liability precisely — *"the only proof that such a process deserves that trust is the
test suite someone has not written yet"*, which this repository's own memory rule makes worse, since contract
tests here can pass vacuously and must each be broken on purpose to be believed. Nine invariants × one mutation
test each is a second project sitting behind the first. The 2-second tick is the tell: it is a 30× recurring
machine cost bought to over-satisfy a latency the owner expressed as *one tick*, and a design that spends 30×
on a promise nobody asked to be tightened will spend similarly elsewhere. The parts worth having here are
separable from the parts that cost — which is exactly what the graft list does with them.

---

## 4. ARCH-adapters — **4 / 10**

| | |
|---|---|
| **C1 code** | INFERRED ~4,000–5,500 lines for **two** platforms and three engine descriptors, plus a fixture corpus. **Baseline + ~4×, and it is the only one whose C1 keeps growing after launch.** Seventeen operations × each platform, a ten-axis capability manifest with a five-value vocabulary, `probes.json`, a `normalize` executable, a conformance runner, `requirements.json`, a negotiation phase producing an immutable `plan.json`, eight engine points × three descriptors, twenty-four event kinds with two-axis provenance mandatory on every number, an injected MCP `ask_supervisor` server, and a tmux pty backend. |
| **C2 subtlety** | High, and — uniquely — **replicated**. The subtle rules (never branch on the CLI's exit code; `undocumented ≠ impossible ≠ unknown`; `accepted ≠ delivered ≠ processed`; `compact` must return a `Proof`; `missing ≠ zero`) are correct and they must hold in *every* adapter, written by *whoever* adds a platform. The document predicts its own erosion: two-axis provenance *"will be the first thing an adapter author skips."* |
| **C3 borrowed** | The *specification* is borrowed whole from `ADAPTER-CONTRACT.md`, which is genuine and substantial. The **implementations are all new**, fifteen times over. `acpx` is taken correctly as a transport rather than a seam, which is the cheapest thing in the document. |
| **C4 tokens/hour** | Floor zero (`orchd` is tokenless) and `liveness.ask_mind_when: signals_conflict OR action_is_destructive` is a good, cheap predicate. No ceiling and no arithmetic. And it carries **the only standing bill in the set that exists even when no run is happening**: `adapter.verify_max_age_hours: 24` gates dispatch on a conformance pass *today*, and that pass includes a **live smoke against the configured account** — one launched session per adapter per day, forever. |
| **C5 first night** | Slowest, and the document says so without flinching: *"It delays the first working night. Nothing runs until at least one adapter passes conformance and one engine descriptor is written… An owner who wants a run tonight will experience adapter-first as an obstacle, and he would be right."* INFERRED **~50–70 engineer-days** to two platforms. |
| **C6 cost to change** | **Split, and this is the fairest thing to say about it.** For the change it optimises — a new platform, and above all a new *provider* behind an existing platform — it is by a distance the cheapest of the four: GLM, DeepSeek-as-lane, Kimi-as-endpoint and MiMo-as-model are config rows with no new adapter, which the research itself calls the highest value-per-hour move in the scan. For a new **requirement**, it is the most expensive: a row in `requirements.json` that every existing manifest answers `unknown`, which degrades closed, so every adapter must be revisited before the requirement passes anywhere. |

**Justification.** The seam placement in this document is right and the analysis behind it is the strongest in
the set, but on a cost axis the design buys generality the owner does not yet need at a price that never stops
being paid. He runs Claude Code tonight and Codex soon; fifteen platforms is a research finding produced by his
own instruction to the *collector* (I1, [182–184]) to test feasibility per platform — which is a question about
what to promise, not an instruction to ship fifteen adapters. Against that near-term need, this design spends
four times the baseline before the first night, maintains 255 contract points (17 ops × 15 platforms) against a
field where Amp shipped five releases in fifteen hours and Copilot 835 versions in twelve months, and then
commits to a *daily* live conformance smoke per adapter to keep the dispatch gate open. Its own weakest-point
section names the thing that makes the whole expenditure fragile: the manifest is a claim with no independent
oracle, written by the same author, tested against fixtures recorded the same day, and trusted at exactly the
hour when nobody is watching — so the largest build cost in the set buys a safety property that rests on a
single unverified assertion. The half of this document that is nearly free — Provider ≠ Platform, the
five-value capability vocabulary, `acpx` as transport — is worth taking today. The other half is worth taking
the week a second platform actually earns its place.

---

## 5. Ranking

| Rank | Design | Score | The one-line reason |
|---|---|---|---|
| **1** | **ARCH-minimal** | **9** | Smaller than the thing it replaces while doing more, because it deletes the long-lived model session and every subsystem that existed to keep one alive. Zero-token floor, fastest first night, cheapest to change, nothing that needs its author. |
| **2** | ARCH-operability | 7 | The only design that costs its own recurring bill in numbers, and the only one with a hard ceiling on model wakes. Pays for it with a six-process fleet and one hidden dependency. |
| **3** | ARCH-reliability | 5 | Buys the elimination of the most expensive failure class at the second-highest build price, front-loaded before the first night, with a test suite behind it that is itself a project. |
| **4** | ARCH-adapters | 4 | Highest build cost, the only *standing daily* cost, 255 contract points against the fastest-moving field in the set — spent on generality that is a year early, with the safety property resting on an unverified claim. |

**Spread, stated honestly.** The gap from 1 to 2 is real but small: operability is minimal plus a cost
discipline and a fleet, and half of its fleet is optional. The gap from 2 to 3 and 4 is large and is about
*when the owner gets a working night*, which on this axis dominates everything else.

---

## 6. The graft list — what to take from the losers into ARCH-minimal

Ordered by value per line of code. Each names the file, the protocol, the state and the command, says what it
costs, and says why it beats the winner's version rather than merely differing from it. Every graft that adds
a knob carries a **DEFAULT-PROPOSED**, because the owner stated almost none.

---

### G1 — The trip watermark and the wake budget
**From:** `ARCH-operability` §2.2.
**Take:** `state/trips/<sha>.json` created `O_EXCL` **before** the wake, keyed
`(predicate, subject, epoch, armed_at)`; plus `brain_max_wakes_per_hour` enforced by a counter file; on
exhaustion the loop **stops waking, raises an attention item, notifies, and keeps ticking**.
**Into:** `orch-run.sh` step 6, alongside the existing `judge.max_calls_per_tick` / `_per_hour`.
**Cost:** ~15 lines of bash (`set -o noclobber` create, a counter file, one `jq` line into `status.json`).

**Why it beats minimal's version.** Minimal already has `judge.max_calls_per_hour: 30`, which bounds *the
bill*. It does not bound *the loop*. A detector that re-reads its own effect — the topology that produced
FIELD-NOTES §11.6's 85-minute loop, where line 5620 reads `NO ONE IS BEING TOLD` — will burn all thirty calls
every hour, for ever, and minimal's status surface will show a judge that is working normally. The trip key
makes the same subject unable to re-fire at all, and the budget-exhaustion path is the thing that speaks. It
is the cheapest line-for-line safety in any of the four documents.
**DEFAULT-PROPOSED:** `judge.max_calls_per_hour: 12` (down from minimal's 30, taking operability's number) ·
`judge.trip_scope: (item, subject, run_epoch)` · on exhaustion `notify` + `status.json.blocked_on += judge_budget_exhausted`.

---

### G2 — Three-tier change detection, with the model reached only on a diff
**From:** `ARCH-operability` §6.4 (and §2.4 for the scout).
**Take:** tier 0 — *did anything change at all*, free: GitHub `If-None-Match` → **304 at zero quota**, or the
board folded into one 2-point GraphQL poll; local: `stat` + sha256 of the body region; ClickUp: one
`date_updated_gt` sweep. Tier 1 — *body or just a comment/label*: compare `lastEditedAt` / body sha256 against
`source_watermark` taken at claim time. Tier 2 — the cheap-model scout, **on the textual diff only**, never on
two full bodies (on GitHub the previous body is free from `userContentEdits[].diff`). `body_digest` and
`source_watermark` live in the run directory and **never on the board**.
**Into:** `orch-run.sh` step 4 (observe), plus a `roles.watcher` model pin that minimal already has.
**Cost:** ~40 lines plus one `curl` header per active ticket per tick.

**Why it beats minimal's version.** Minimal implements Д8 as `stat` + a content hash with self-write
suppression — correct for *detecting*, silent about *what happens next*, which is that the change lands on the
judge's fact sheet and is reasoned about by a model. Operability's ladder is the same detection plus a
deterministic answer to "was it the description or a label", so the model is reached on a real body change and
is handed a diff rather than a document. The costed difference is the largest single per-hour lever in any of
the four: **~$14 per 8-hour night** for a frontier model reading every body every tick, **~$1.42** for the
cheapest model, **~$0.01** for tiers 0–1 with the model only on a confirmed change (CLAIMED, C3 §5.3, derived
from a measured median body of 3,932 bytes). Minimal's own instinct is right; this is the arithmetic that makes
it several hundred times right.
**DEFAULT-PROPOSED:** `watch.tier0_interval: every tick` · `watch.scout_model: the cheapest model the pinned
provider offers` (Д8 [466], his instinct, made a key) · `watch.scout_input: diff_only` · storing watermarks on
the board: **refused, not configurable** — writing them into the body moves `lastEditedAt` and the detector
triggers itself (C3-A1).

---

### G3 — The GSD probe as six named commands with the contract pinned
**From:** `ARCH-operability` §8.3 and `ARCH-adapters` §9.2.
**Take:** replace minimal's *"about five lines"* `probe/gsd.sh` with the verified surface. **VERIFIED on this
machine today:** `gsd-tools` exposes `progress`, `smart-entry`, `state`, `runtime-identity`, `worktree`,
`windows`, `dispatch-isolation`, with global `--pick <field>`, `--project-dir`, `--json-errors` and
**`--exit-contract=v1|v2`**; `runtime-identity` returns `{"packageName":"@opengsd/gsd-core","version":"1.14.0"}`.
Specifically take: `runtime-identity` → the engine version pinned into `start.json` and `journal.ndjson`;
`--exit-contract=v1` → pinned, so a GSD upgrade cannot silently change what the probe's exit code means;
`worktree base-check` → `{shouldDegrade, reason, headSha, forkRef, forkSha}`, which is the Д4/C9-A2 collision
detected before dispatch instead of at 03:00; `windows status` → GSD's own `human_needed` /
`insufficient_spec` escalation, i.e. a **ready-made `engine_escalation` predicate at zero tokens**.
**Into:** `probe/gsd.sh`, growing from ~5 lines to ~25.
**Cost:** twenty lines. No new dependency. Three to six subprocess calls per lane per tick, zero tokens.

**Why it beats minimal's version.** Minimal's probe reads `gsd-tools state` and prints one line — correct, and
it leaves three free things on the table. Without `runtime-identity` the journal cannot say which engine
version produced a record, which is the cheapest half of R1-06.3's *"reference the process's own records"*.
Without `--exit-contract` pinning, GSD's own versioned exit codes are an unpinned dependency inside the one
place minimal trusts completely. Without `windows status`, minimal invents nothing for `engine.needs_human`
and a blocked phase reads as `state=running` until the lane exits. This is the single best borrow available
anywhere in the four documents and it costs less than any of them spend describing it.
**DEFAULT-PROPOSED:** `engine.gsd.exit_contract: v1` · `engine.gsd.probe_calls: [smart-entry, state, windows
status]` per tick, with `runtime-identity` and `worktree base-check` at **preflight and dispatch only**, not
per tick.

---

### G4 — `control.ack.json`, with reliability's exit codes on top
**From:** `ARCH-operability` §3.3 (the file) + `ARCH-reliability` §10.2 (the contract).
**Take:** the supervisor writes `control.ack.json` every tick by atomic rename —
`{schema, read_at, doc_sha256, epoch, applied[], deferred[{key,until}], rejected[{key,reason}], parse}` — and
`orch-ctl.sh` **polls it after writing** until it shows the entry applied, or `stop.ack_timeout_seconds`
elapses. **Exit 0 = applied. Exit 8 = written but unacknowledged**, with the message naming
`orchestrator:doctor`.
**Into:** `orch-run.sh` step 8 (write) and all three stop commands.
**Cost:** ~20 lines: one `jq` write in the tick, one poll loop in the command.

**Why it beats minimal's version.** Minimal's stop command prints
`written to control.json (c-0012); applied within 60s`. That is a *promise about a process that may be dead*,
and it is indistinguishable from the exact failure the previous generation kept producing — FIELD-NOTES §11.2
records two real operator instructions, `push master` and `carry on with the queue`, sitting unsubmitted in
input boxes while the engine's log recorded them as delivered. An ack file converts the promise into an exit
code the owner can see at 03:00 without opening anything, and it also gives `deferred[]` and `rejected[]`
somewhere to live, which minimal's boundary/frozen config classes currently have no surface for.
**DEFAULT-PROPOSED:** `stop.ack_timeout_seconds: 90` (minimal's tick is 60 s, so one tick plus margin) ·
`control.ack.path: <run>/control.ack.json` · frozen-key edits are **always** surfaced in `rejected[]`, never
silently ignored.

---

### G5 — The dedup key written into the side effect itself
**From:** `ARCH-adapters` §3.3 property 4 and `ARCH-operability` §3.5 property 3.
**Take:** `action_id = run:epoch:lane:step:attempt`, written as `step.intent` before the effect and
`step.result` after — **and carried inside the effect**: a trailer in the ticket comment, the branch name, and
an `Orchestrator-Epoch:` / `Orchestrator-Action:` trailer on any commit the orchestrator itself makes.
**Into:** `orch-lane.sh` and wherever `orch-run.sh` writes to the board.
**Cost:** a formatted string, plus a `grep` in the recovery path. Under 20 lines.

**Why it beats minimal's version.** Minimal has the discipline for *lanes* — `start.json` before launch,
`result.json` last, so a crash leaves a detectable orphan. It stops at the lane boundary. The orchestrator's
own mutating acts outside the run directory — a board transition, a comment, a merge — carry no key at all, so
after a crash a replayer has to trust `journal.ndjson` to know whether a comment was already left, and
FIELD-NOTES §12.6 plus C3-A12 record duplicate-comment handling as a real, already-observed hazard. Putting the
key in the effect means the replayer asks the *board*, not the journal. This is the one piece of
`ARCH-reliability`'s I3 that survives without the appender, and it is the cheapest piece.
**DEFAULT-PROPOSED:** `dedup.trailer_prefix: "orchestrator-action:"` · applied to board comments and to
orchestrator-authored commits; **not** applied to a work commit the agent makes, which is the engine's
business.

---

### G6 — The merge-landed assertion, six lines, already verified
**From:** `ARCH-adapters` §9.5.
**Take:** verbatim, at the delivery step:

```bash
BASE=$(gh pr view "$PR" --json baseRefName --jq .baseRefName)
HEAD=$(gh pr view "$PR" --json headRefOid  --jq .headRefOid)
git fetch origin "$BASE"
git merge-base --is-ancestor "$HEAD" "origin/$BASE" \
  || fail "PR $PR reports merged; $HEAD is NOT an ancestor of origin/$BASE"
[ "$(gh pr view "$PR" --json state --jq .state)" = MERGED ] || fail "PR $PR is not MERGED"
```

Plus its sibling: capture `EXPECTED_BASE=$(git rev-parse HEAD)` before dispatch and assert it inside the
worktree.
**Into:** `orch-lane.sh`, delivery step only.
**Cost:** six lines. CLAIMED working against this repository's own PR #26 (C9 §5.3).

**Why it beats minimal's version.** Minimal has no version, by design: R1-13 [344] gives verification to the
process, and minimal honours that absolutely. But the distinction `ARCH-reliability` draws in its I4 tension
note is the one that matters here and minimal never draws it — *the engine says whether the ticket is done; the
orchestrator says whether the orchestrator's own step ran*. A merge either moved a ref or it did not, on any
project, with or without tests, which is exactly what N2 [344] requires of anything the orchestrator adds. This
does not check the work. It checks that the orchestrator's own merge happened, and it is the direct fix for
FIELD-NOTES §4.1 — the merge that printed `Already up to date` and moved nothing. Two independent oracles, six
lines, and the §4.1 failure mode (a branch merged into itself) fails the second one instantly.
**DEFAULT-PROPOSED:** `delivery.assert_landed: true` · `delivery.mode: pr_only` (minimal already proposes this
for C9-A3's reason: `gh api …/rulesets` → `[]` and `…/branches/main/protection` → 404 while `CLAUDE.md` says
PR-only) · a failed assertion is a lane `failed` with `reason:"merge_unproven"`, never a retry.
**Flag for the owner:** this is a check the orchestrator performs on itself, and `ARCH-operability` §16.6 is
right that the distinction was never put to him. It belongs in round 2.

---

### G7 — The no-pattern-matching lint rule
**From:** `ARCH-operability` §13.2 and `ARCH-adapters` Invariant BD-1.
**Take:** `pkill`, `killall`, and an unscoped `docker compose down` **fail the build** if they appear anywhere
in plugin source.
**Into:** `tests/run-all.sh`, which already exists in this repository — **VERIFIED**: 79 lines, with a
`PLUGINS=(…)` array that the new plugin must be added to.
**Cost:** one `grep -rE` and an exit code. Under 10 lines.

**Why it beats minimal's version.** Minimal reaches the same outcome by construction — teardown walks
`owned.ndjson` and touches nothing else, and its §10.2 correctly says FIELD-NOTES §11.8's
`pkill -f 'playwright test'` killing an unrelated lane is *unreachable* because nothing matches processes by
pattern. That is true of the design as written and it is a **property of discipline, not of the artefact**. A
grep-for-absence makes it a property of the build. It matters more here than in any other repository, because
this repo's own memory rule records that its harness greps prose and tests can therefore pass vacuously —
and a grep asserting that a string is *absent* is one of the very few checks that cannot pass vacuously.
**DEFAULT-PROPOSED:** not configurable. This is a build rule, not a setting.

---

### G8 — `HARVEST`: a third answer between exit code and done
**From:** `ARCH-operability` §5 (`harvest_evidence`), via Sortie ADR 0020.
**Take:** a lane state between `working` and `done` in which the **engine**, not the exit code, is asked, with
three answers — done · not done · undeterminable — and `harvest_evidence: observed` meaning *withhold `done`
only on positively observed emptiness*.
**Into:** `orch-lane.sh`'s outcome computation and the lane state machine in §3.2.
**Cost:** one lane state, one extra engine probe call at terminal. ~25 lines.

**Why it beats minimal's version.** Minimal computes `outcome = f(exit_code, terminal_event)` and sends a
disagreement to `failed:contradictory` — which is right, and covers the four platforms that exit 0 on failure.
It does not cover **agreement that is wrong**: a lane that exits 0, emits `turn_completed`, and produced
nothing. Both of minimal's oracles are about the *run's exit*; neither is about the *run's output*. Sortie's
asymmetry is the argument and it is a cost argument: advancing an empty ticket *"moves work in a system you do
not own, removes it from the queue you do own, and puts it in front of a person"*, while withholding *"leaves
it where it was, in a queue you keep watching, with the withholding recorded."* One of those errors costs the
owner a morning; the other costs a tick.
**DEFAULT-PROPOSED:** `harvest_evidence: observed` (three values — `observed | strict | off` — never a
boolean, because absence of evidence is not evidence of absence) · an undeterminable harvest sets
`needs_review`, not `done`, matching `engine.on_indeterminate` in `ARCH-reliability` §7.1.

---

### G9 — `ops.json`, but only two columns of it
**From:** `ARCH-reliability` §3.6 and §11.3 phase 2.
**Take:** the **data file, not the appender**. One row per mutating operation carrying `{timeout_s, reconcile}`,
where `reconcile` ∈ `read_ref | refetch | probe_session | read_context | none`. On restart, an orphan
(`start.json` with no `result.json`, or an `action_id` with no result) runs its declared probe and resolves
deterministically; only the residue goes to the judge.
**Into:** a ~20-line JSON file plus a `case` statement in `orch-run.sh`'s recovery path.
**Cost:** ~35 lines total. **Do not take** the evidence-gated appender, the eight evidence kinds, the four
idempotency classes or the four-phase reconciler.

**Why it beats minimal's version.** Minimal's §10.2 puts *every* orphaned lane onto the judge's fact sheet with
verdicts `resume | reseed | release | escalate`. That is a model call per orphan on every restart, and R1-10
[300] makes restarts an expected event rather than an exception — so minimal's restart path is the one place
its otherwise excellent token floor leaks, and it leaks precisely when the system is already degraded. A
declared probe answers *"did this exact operation already happen?"* for free in the common cases (read the ref;
refetch the board item; look up a client-assigned session id) and escalates only what genuinely cannot be
probed. Cheaper per restart **and** more correct, because a probe of the world beats a model's reading of a
fact sheet about the world.
**DEFAULT-PROPOSED:** `recovery.probe_before_judge: true` · per-op `timeout_s` declared in `ops.json`, with an
undeclared op refused at load (reliability's rule, kept — it costs one line and prevents the file rotting) ·
unprobeable orphans (`reconcile: none`) escalate to the Д6 channel, **never** replay.

---

### G10 — The detector scorecard in the morning artifact
**From:** `ARCH-operability` §14.3, `NEXT-RUN.md` section 1.
**Take:** per detector — firings, confirmed, false, never-fired — and the rule that **a detector with zero
confirmed firings is reported as `unproven`, not as `clean`.** Plus section 2's threshold traffic (a context
threshold that armed eleven times and compacted once is a badly placed threshold).
**Into:** `report.md`, rendered once at finish from counters already in `journal.ndjson`.
**Cost:** counters in the tick plus a `jq` render. ~30 lines, run once.

**Why it beats minimal's version.** Minimal's `report.md` says what happened. It does not say whether
minimal's own probes work — and minimal's §15.3 concedes that its coverage *"is exactly the list of things
someone thought to render."* FIELD-NOTES §11.3 is the case that makes this non-theoretical: BSD
`find -newermt "-10 minutes"` errors out, and with stderr to `/dev/null` returns empty every time, which
*"would have declared every healthy session idle for ever"* — a probe that could never succeed and never
complained. A scorecard is the cheapest possible way to discover which renders are dead, and it costs nothing
during the night, which is the constraint that matters.
**DEFAULT-PROPOSED:** `report.scorecard: true` · `report.mark_unfired_as: unproven` · **no**
`tuning.patch.yaml` auto-application — operability is right that a system which retunes itself overnight is one
whose behaviour he cannot predict; the scorecard is a report, not an actuator.

---

### G11 — Three capability values instead of two
**From:** `ARCH-adapters` §4.2, whose own source is GSD's `host-integration.cjs`.
**Take:** `caps.sh`'s vocabulary becomes `native | emulated | impossible | unknown | undocumented`, with two
rules: an out-of-vocabulary value validates but never propagates into an effective axis, and **`undocumented`
≠ `impossible`** — a missing declaration and a declared absence are different facts reported with different
words. `negotiate.on_unknown: impossible` — an undeclared axis degrades **closed**.
**Into:** `adapters/<id>/caps.sh` and `orch-preflight.sh` §7.2.
**Cost:** three enum values and one comparison. Under 15 lines.

**Why it beats minimal's version.** Minimal's `caps.sh` prints `compact=native|none`, and preflight refuses
what caps forbid — which handles a *declared* absence perfectly. It has no answer for an axis an adapter never
mentions, and that gap is the one that grows: every new requirement added later will pass silently on every
adapter written before it. Adapters' version makes an old adapter fail closed against a new requirement at
preflight, at 22:00, rather than degrading at 03:00. It is the cheapest fifteen lines of the entire
adapter-first thesis, and the shape is one the owner's own engine already speaks, which is the best argument
for it.
**DEFAULT-PROPOSED:** `negotiate.on_unknown: impossible` · `negotiate.on_undocumented: probe_then_impossible`
(run `probes.json` if one exists, else treat as impossible) · the refusal message names the lane, the axis and
the owner item, which minimal's preflight already does for declared absences.

---

## 7. What to leave behind, and what leaving it costs

Named explicitly, because on a cost axis the refusals are half the judgement.

| Not grafted | From | What it would cost | What leaving it costs |
|---|---|---|---|
| The evidence-gated journal appender, eight evidence kinds, four idempotency classes, the four-phase reconciler | reliability §3.3–§3.6, §11.3 | The bulk of that design's ~3,500–4,500 lines, plus a mutation test per invariant | The *general* guarantee that no `ok` exists without evidence. G5, G6 and G9 buy back the three specific cases that actually bit (merge, comment, orphan); the rest of the class stays uncovered and that is a real, accepted gap |
| The 2-second control tick and its 5-sub-loop cadence | reliability §2.1 | ~1,800 iterations and ~12,600 file hashes per hour | Stop latency stays at one 60 s tick — which is what the owner asked for (*"на наступному тіку"*, Д12 [520]), and G4's ack makes it verifiable |
| Capability negotiation, `requirements.json`, the immutable `plan.json`, `weakened[]`/`denied[]` | adapters §5 | A negotiation phase before the first night, and a PREFLIGHT that can refuse for reasons he never asked about | The pre-run record of which requirements were weakened. Mitigated at ~10% of the price: minimal's preflight already refuses on a declared absence, and G11 extends that to undeclared ones |
| The conformance suite, the fixture corpus, `adapter.verify_max_age_hours: 24` | adapters §4.5 | A second product, plus a **daily live smoke per adapter, for ever** | Version drift is caught by minimal's existing version pin rather than by a daily proof. Weaker, and roughly free |
| Two-axis provenance mandatory on every number | adapters §6.2 | Friction on every field of every adapter — which its own §20 predicts authors will skip | Minimal already carries `prov: measured\|estimated\|unknown` and `age_s` on every number in `status.json`, which is the 80% that matters |
| The six-process fleet: separate scout, sentinel, notifier, warden, brain | operability §2 | Four more process kinds to supervise, plus a launchd agent | Minimal's doctor (~40 lines, *"try to take the lock"*) covers the warden. The **sentinel is the real loss** — see §9 |
| The comment-and-anchor-preserving YAML leaf merge | operability §3.3 | An unpriced Node/Python YAML round-trip dependency | Minimal's `control.json` is JSON with an append-only `entries[]` array, written under a lock and moved to `control.applied.ndjson` — no merge is needed, and hand-editing JSON is worse than YAML. Accepted |
| `statusLine`-based context bridge | operability §7.2 | Editing the owner's own `settings.json`, which needs his explicit yes | Minimal reads `context.used_pct` from the normalised event stream, which needs no permission and no edit to his environment |

---

## 8. Every default the grafts introduce, in one table

None of these is a decision. Each says what it protects against, per the rule that everything configurable
needs a stated default.

| Key | DEFAULT-PROPOSED | Graft | Protects against |
|---|---|---|---|
| `judge.max_calls_per_hour` | **12** (down from minimal's 30) | G1 | A judge in a disagreement loop spending the night |
| `judge.trip_scope` | `(item, subject, run_epoch)`, `O_EXCL` before the wake | G1 | A detector re-firing on its own effect — the 85-minute-loop topology |
| `judge.on_budget_exhausted` | `notify` + `status.json.blocked_on`, keep ticking | G1 | A budget that silently stops the only thing that judges |
| `watch.tier0_interval` | every tick (a 304 or a `stat` is free) | G2 | Paying a model to read an unchanged ticket |
| `watch.scout_model` | the cheapest model the pinned provider offers | G2 | Д8 [466], made a key rather than an instinct |
| `watch.scout_input` | `diff_only` | G2 | Sending two full bodies where a diff answers the question |
| `engine.gsd.exit_contract` | `v1` | G3 | A GSD upgrade silently changing what an exit code means |
| `engine.gsd.probe_calls` | `[smart-entry, state, windows status]` per tick | G3 | Six subprocess calls per lane per tick where three answer |
| `stop.ack_timeout_seconds` | **90** (one 60 s tick plus margin) | G4 | An owner believing a stop was applied when it was not |
| `dedup.trailer_prefix` | `orchestrator-action:` | G5 | A replayed board comment after a crash |
| `delivery.assert_landed` | `true` | G6 | A merge that prints `Already up to date` and moves nothing |
| `delivery.mode` | `pr_only` | G6 | The repo where machine sources say nothing is protected and `CLAUDE.md` says PR-only |
| `harvest_evidence` | `observed` (of `observed \| strict \| off`) | G8 | A lane that exits 0 having produced nothing taking the done path |
| `recovery.probe_before_judge` | `true` | G9 | A model call per orphan on every restart, when restarts are expected |
| `report.scorecard` | `true` | G10 | A probe that can never succeed and never complains |
| `report.mark_unfired_as` | `unproven` (never `clean`) | G10 | Reading zero firings as health |
| `negotiate.on_unknown` | `impossible` | G11 | A new requirement passing silently on every adapter written before it |
| `negotiate.on_undocumented` | `probe_then_impossible` | G11 | Telling the owner a platform "declares no X" when the resolver failed |
| *(build rule, not a setting)* | `pkill` / `killall` / unscoped `docker compose down` fail the build | G7 | The two recorded incidents where his own work was destroyed |

**Net effect on the winner's size.** INFERRED: the eleven grafts add **~250–290 lines** to
`ARCH-minimal`'s ~1,100, i.e. ~1,350–1,400 lines — still **below the previous generation's measured 1,879
lines of bash** (VERIFIED), while adding a bounded token budget, a costed change detector, a verified engine
probe, an acknowledged stop, a replay-safe board, a proven merge, a build-enforced blast radius, a third
harvest answer, a deterministic restart path, a self-audit and a fail-closed capability lattice.

---

## 9. Where this judgement is weak

**9.1 I am scoring build estimates, not builds.** C1 and C5 are INFERRED throughout. The only calibration
point is the previous generation's measured 1,879 lines, and it was *smaller* than three of these four designs
while being demonstrably insufficient — so my estimates may be uniformly low in the same direction its author's
were. Every number in this file should be read as a ratio between the four, which I am confident about, not as
a date, which I am not.

**9.2 The winner's cheapness and its weakest point are the same property.** `ARCH-minimal` is cheap because
bash renders the facts and the model only judges what bash rendered. Its §15.3 proves the cost against the
run's worst recorded lane — `w-phase-19`, which issued **3,466 of its 3,626 Bash calls as the literal command
`echo idle`**, added 445k tokens, reached 91%, and reads as *healthy* against every one of minimal's three
signals. My graft list does not close that. G10's scorecard finds a dead detector *after* the night; G2's
refill-rate sibling (`Δpct/hour` as a **defect** predicate, `ARCH-operability` §7.2, `ctx_refill_alarm:
20 %/h`) is the one line that would have caught it, and I should have made it a twelfth graft rather than a
parenthesis. Treat it as one: **G2b — add `Δpct/hour` and `top repeated tool call in the last N events` to the
fact sheet renderer, DEFAULT-PROPOSED `ctx_refill_alarm: 20 %/h`.** Two lines in a renderer, and it is the
cheapest coverage in this document.

**9.3 I priced the sentinel out and I am not sure that is right.** `ARCH-operability` §2.6's sentinel — one
model call every four hours, on a different account, with exactly three inputs and exactly one question
(*"has this run produced anything in the last N hours, and if not, why not?"*) — is the only judgement in any of
the four designs that is not derived from a predicate somebody wrote in advance. It is 8–9 calls in a 34-hour
run. On a cost axis that is nearly free, and it is the only thing that catches the run that is alive, busy,
spending money and producing nothing. I left it out of the graft list because minimal's doctor covers the
*dead* case, and then wrote §9.2, which is the *useless* case. **It should probably be G12, at
`sentinel_hours: 4`.**

**9.4 The axis itself has a blind spot, and it favours the winner.** Cost-to-run is not only tokens and
machine time; it is also the owner's mornings. `ARCH-reliability` scores 5 here and would score highest on an
axis called *nights not lost*, because the failure class it eliminates — reported success and did nothing — is
the one that costs a whole night each time it fires, and FIELD-NOTES records it firing repeatedly. If the
judges on the other axes come back with reliability first, the right reading is not that I was wrong, but that
**the cheapest build is not the cheapest system**, and grafts G5, G6 and G9 are the specific places where the
two axes can be bought off against each other at roughly a tenth of reliability's price.
