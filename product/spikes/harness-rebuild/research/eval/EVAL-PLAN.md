# EVAL-PLAN — how the orchestrator is proven to work, and kept safe to change

**Spike:** harness-rebuild · **Written:** 2026-09-19 · **Supersedes nothing; consolidates:**
`ground-what-exists-here.md`, `ground-failure-corpus.md`, `ground-testing-agentic-systems.md`,
`ground-evaluating-llm-decisions.md`, `L1-contract.md`, `L2-simulation.md`, `L3-chaos.md`,
`L4-judgement.md`, `L5-acceptance.md` (all nine read in full for this document), plus
`research/architecture/BUILD-PLAN.md` §4 and `SPEC-repo.md` §7, which this plan must not contradict.

**Requirement source of truth:** `../../round-1/ANALYSIS-01.md`. Every `R1-nn` / `Дn` / `N2` / `I1`
reference is to that file.

**Evidence legend.** **[V]** verified — read in source or run on this machine by me or by a sibling
document that quotes its command and output, and re-checkable in under a minute. **[C]** claimed —
asserted by `FIELD-NOTES.md` or a document built on it, not re-derived. **[I]** inferred — reasoning
from the two, marked so it can be argued.

**One source named in the brief does not exist.** `…/scratchpad/context/harness-evidence.md` is
absent; `context/` is an empty directory [V, recorded independently by all five sibling documents].
Everything attributed to the 34-hour run reaches this plan through `plugins/harness/docs/FIELD-NOTES.md`
and is **[C]**.

---

## 0. The plan in one page

The previous generation shipped 51 tests, all green, and a 34-hour run that produced roughly sixty
distinct failures [C]. The tests did not fail because the bugs were subtle. They did not fail because
**41 of 51 were `grep` over source text** [V] — a test of a string, not of a behaviour. Two independent
mutation experiments on this machine proved it: one deleted the config-validation feature, left its
sentence in a `# TODO`, and the test named for it stayed green [V]; another killed the rate gate,
neutered the pause wait, disabled session close and disabled the spawn validator, and **four of five
mutations passed 51/51** [V]. A third found six of seven deliberate defects surviving the whole suite
[V].

So this plan is not "more tests". It is five commitments:

1. **Every assertion is admitted only after its mutation has been seen to turn it red**, and the
   mutation is recorded in the test file. A test with no recorded mutation is presumed vacuous and the
   runner refuses it.
2. **Everything that gates a commit is free, offline and under a minute.** The whole deterministic
   stack — L1 contract, L2 simulation, L3 chaos at its gate profile, L4-A replay — is ~2 minutes
   serial, ~1 minute parallel, and **$0.00**. A gate that costs money or minutes stops being run, and
   an unrun suite is worth less than no suite [I, and the repo's own 42.15 s / zero-cost suite is the
   evidence that cheapness is what makes it get run].
3. **Nothing is asserted from an attempt; everything is asserted from an observed effect.** Four of
   the corpus's largest families — a log that says `nudged`, a merge that prints `Already up to date`,
   a `SYNTAX OK` whose anchor never matched, 26 audit-log refusals that never happened — are one
   defect with four faces [C].
4. **The signals are tested, not the judgement.** The record is unambiguous that judgement was not the
   failing part; the signals were [C]. L1–L3 and L5 assert what the orchestrator is *told* and what it
   *did*; only L4 grades what it concluded, and L4 is second in value, not first.
5. **A failed real run leaves the repository red.** Every divergence a real run produces becomes a
   corpus entry, a captured-evidence fixture and a registered failing stub, automatically. That is the
   direct answer to the worst meta-failure on record: a documented fix that was still missing from the
   source thirteen days later [V, still true in `harness-tickets.sh` today].

**The measured shape of the stack.**

| Layer | Question | Cost | Gates |
|---|---|---|---|
| L0 static | does it parse, is the config well-formed, do the banned constructs appear | < 5 s, $0 | commit |
| L1 contract | `decide(world) → plan`, config, control file, stops, lease, journal, readiness, thresholds, resume | ~23 s, 88 cases, $0 | commit |
| L2 simulation | the real supervisor process against a fake world in virtual time | ~64 s serial / ~20 s `-j 4`, 46 scenarios, $0 | commit |
| L3 chaos | the same run with something broken at a chosen instant | 35–55 s gate / 4–7 min full, 37 scenarios, $0 | commit (gate profile) |
| L4 judgement | is the model's verdict right, given a fixed evidence bundle | L4-A < 1 s / 1,403 cases / $0 · L4-B ~$0.85–$14 | commit (A) / PR (B) |
| L5 acceptance | are the run's claims about its own actions independently true | 8 min free · C1 ~35 min · C2 ~4 h | the run itself |

**~251 scenario ids over ~1,540 executed cases, 157 mutations, $0 for everything that blocks a
commit.** The only money in the plan is L4-B (≈ $96/month at a realistic cadence) and the canary's real
sessions (≈ 0.5–1% of a weekly subscription window per C2 pass), both deliberate and both optional.

---

## 1. What "it works" means

### 1.1 The owner's answer, and why it is not an obstacle

R1-01 is settled and it refuses the question as asked: *"Це все залежить, так як це налаштував …
конкретної якоїсь вимірюваної штуки тут не може взагалі бути … могло не виявитися когось з доступу,
або ще щось, і ран зупинився, і це не означає, що це помилка в нас."*

Read precisely, that sentence does not say success is unmeasurable. It says **two different things are
being confused**, and it separates them itself: *"помилка в нас"* — our fault — is one thing, and the
run's outcome is another. A run that stopped because an access token expired is not a plugin failure.
A run that stopped because the plugin read an expired token as `0%` and paused forever **is**.

That is the backbone of this plan.

### 1.2 The split

**Category A — orchestrator invariants.** Properties the orchestrator must hold **regardless of what
the user configured**, because they are properties of the orchestrator's own conduct, not of the work.
They are binary, they are testable without a model, and a violation is a defect in the plugin no matter
how the night went. These are §2's list. They are what "it works" means, and the answer to
*"переконатися, що воно буде працювати"* is: these twelve properties, each proven by a named assertion
whose mutation has been seen to turn it red.

**Category B — configured outcomes.** Whether the tickets got done, whether the tests passed, whether
the PR was good, whether the night was worth it. R1-13 puts these inside the user's configured process
and R1-01 refuses a universal metric for them. **This plan measures none of them**, and the one place
it comes near — did the step the user configured actually *run* — is bookkeeping about the
orchestrator's own actions and is flagged as the single open boundary question (D1, §9).

**Category C — fidelity claims.** "The double behaves like the real thing." Not an invariant and not an
outcome; a claim about the test apparatus that can be false while every test is green. It has its own
tier (L5's conformance work and the `n/a`-declaration rule) because the record contains a measured case
where it inverted a verdict: a `read`-loop fake agent **submits** text stranded on its input line and
real Claude Code **does not** [V, measured twice from two directions], and five operator instructions
were lost to believing the fake [C]. A suite built only on doubles would have "proved" the nudge works.

### 1.3 The three shapes a Category-A violation takes

Naming them makes the invariant list readable, because nearly every entry in the failure corpus is one
of three shapes:

- **It claimed an effect it did not have.** F-07 (`nudged`, nothing delivered), F-29 (a merge that
  printed `Already up to date` on the phase branch against itself, exit 0, trunk untouched), F-36
  (`SYNTAX OK` while the `sed` anchor never matched — *"the third such case that day"*), F-52 (26
  refusal events in an audit log from one real read) [all C].
- **It read an absence as an answer.** F-16 (`UNKNOWN` quota + `on_unreadable: proceed` → hours of
  blind running, VERIFIED in the old source), F-33 (`No tests found` from an import-time crash read as
  zero failures), F-35 (`OK, 0 files compared` from the wrong cwd), F-47 (a collector OOM-killed 26+
  times while its consumer kept reporting normally), F-59 (a detector globbing the wrong directory and
  reporting a clean zero) [all C]. **One rule retires all five: an empty result is never a clean
  result.**
- **It acted on something that was not its own.** F-44 (`docker compose down -v` with no
  `COMPOSE_PROJECT_NAME`, the owner's default stack destroyed, **actor never identified**), F-45
  (`pkill -f 'playwright test'` killing an unrelated lane because every lane's prompt text contains
  that literal string), F-48 (~150 orphaned volume pairs from a dead prior run) [all C].

### 1.4 The verdict vocabulary, and why it has four values

A run ends `CLEAN | DEGRADED | FAILED | UNVERIFIABLE`.

`UNVERIFIABLE` is the load-bearing one and it is the whole lesson of §1.3's second shape. "No
divergences were found" and "the auditor never ran" must be distinguishable in the artifact, or the
report becomes the next `346 passed / 0 failed of a declared 382` [C]. Section 5 of the morning
artifact therefore prints its emptiness as a measurement: *"1,284 effect-records checked against 9
probes; 0 divergent"*, never a blank.

---

## 2. The invariant list

Twelve. The brief named seven; five more are added because the evidence forces them, and each addition
says why. Every row has: the property, the requirement it serves, the layer and assertion ids that
prove it, **the mutation that must make the proof fail**, and what the proof does not cover.

Format note: an invariant is not proven by one test at one layer. It is proven by a **ladder** — a
cheap deterministic assertion, a scenario against a fake world, a chaos scenario that breaks the world
at the dangerous instant, and (for three of them) a conservation identity over a real run. The ladder
is the point: L2's own verified result is that **a categorically broken lock passed five rounds of 100
concurrent acquirers** and only failed as the race window widened [V]. A green test at one rung is not
evidence.

---

### I-01 · Never two orchestrators of one run

**Requirement:** R1-10, stated by the owner as an absolute — *"якщо раптом одночасно два якісь
оркестратори працюють, то це не окей. Це треба відслідковувати і не дозволяти."* Also Д10.

**Why it is first:** the previous generation has **no guard of any kind** —
`grep -rniE 'already running|pidfile|singleton|another orchestrator'` over `bin/*.sh` returns nothing
[V]. There is nothing to inherit. The owner named the consequence himself: *"це буде просто
нескінченний цикл оркестраторів."*

| | |
|---|---|
| **Proved by** | L1 `LEA-01…LEA-08`, `LEA-11` · L2 `L2-LIFE-01`, `L2-LIFE-02` · L3 `C-15`…`C-19` · L5 `A-08`, `K-01` |
| **Mechanism** | `mkdir` or `noclobber` (VERIFIED exclusive, 1 winner per round at 0/1/5/20 ms injected delay, six rounds of 60 [V]). **`flock` is absent on macOS** [V]; `shlock` and `lockf` are present. Liveness is proved by **pid + process start time + run id**, never by a name, a window title or a `pgrep` pattern |
| **Mutations that must turn it red** | `M-lea-naive` replace the lock with `[ ! -f "$LOCK" ] && echo $$ > "$LOCK"` → `LEA-01`/`L2-LIFE-01` red **at delay ≥ 1 ms only, green at 0** [V] · `M-lea-name` key liveness on `pgrep -f orchestrator` → `LEA-07` red · `M-lea-pid-only` drop `proc_start` → `LEA-06` red · `M-lea-stopped` treat a non-responding holder as dead → `LEA-05` red · `MC-01` delete the `owner.json` identity check → `C-17` red |
| **Does not cover** | A race narrower than the smallest injected delay. Two machines sharing a state directory on a synced volume (`host` + `boot` fields exist for it; untested) [C]. PID reuse inside the same second — plantable as a fixture, not producible |

Three details that are not optional, each earned by measurement:

- **The delay ladder is the test, not the parallelism.** Naive check-then-write passed 5×100 at delay 0
  and leaked 5 → 13 → 26 winners at 1 → 5 → 20 ms [V]; a second probe leaked **8 winners at zero
  delay** on the same primitive [V]. The size of the natural window is a property of the exact code, so
  a chaos suite may not assume it will be lucky.
- **A `SIGSTOP`ped holder still holds its lock and must not be reclaimed** [V]. A supervisor paused
  inside a quota wait is the *normal* state under R1-06; "not responding ⇒ dead" would reclaim a
  healthy run routinely.
- **Exclusivity is half the requirement.** `LEA-03` asserts the **loser touches nothing**: the run
  tree's hash is unchanged, the sentinel intact, and the fake `kill`/`docker` recorders saw an empty
  action set.

---

### I-02 · Never touch what it did not start

**Requirement:** R1-16 (PARTIAL by the owner's deliberate choice — he ruled out heavy isolation:
*"я не хочу якихось детерміністського варіанту … але дуже якийсь простий та надійний варіант"*), Д3
(*"щоби не залишати хвостів"*).

**Why:** this is the only invariant whose violation is **irreversible**. F-44 destroyed the owner's own
stack with `-v`, and the actor was never identified, so no post-mortem was possible [C].

| | |
|---|---|
| **Proved by** | L1 `JRN-06`, `RES-06` (the property `acted_on ⊆ started_set`, checked after **every action of every scenario**, not only here) · L2 `L2-RAD-01`…`L2-RAD-03`, `L2-LIFE-04` · L3 `C-13`, `C-36` · L5 `V-03`, `K-08` (the decoys), `A-11` |
| **Mechanism** | the simple version the owner asked for: **an ownership label plus a refusal**, not a sandbox. Everything created carries a run-id label at creation; teardown enumerates **by label**, aborts the whole operation if any target is unlabelled, refuses to run at all with an implicit scope, and records actor + run id + target list *before* executing. Process targeting is by recorded pid with a parentage check, never by pattern |
| **Mutations** | `M-RAD-default` let cleanup fall back to the default project when the scope variable is unset → `L2-RAD-01` red · `M-RAD-pkill` add one `pkill -f "<descriptive pattern>"` → `L2-RAD-02` red **and** the `O-40` ban-lint red · `M-RAD-memory` track created resources in memory only → `L2-RAD-03` red · `MC-28/MC-29` teardown falls back to the default compose project / sources an identifier from the environment → `C-36` red |
| **Does not cover** | **Indirect** violation. F-46: two concurrent `docker compose up --build` OOM-killed the owner's container on port 3000 in **31 seconds**; no command touched it [C]. R1-05 explicitly defers machine-resource awareness, so the testable obligation is detection and attribution only, and that deferral is recorded as a **visible waiver** (§7), not as silence |

**One verified trap that makes this invariant's test vacuous if missed:** `kill` is a bash builtin and a
PATH shim does not intercept it [V]. `BASH_ENV` + `enable -n kill` intercepts the SUT, child `bash` and
subshells (3/3) but **not** `sh -c` (0/3) [V]. Hence the canary rule: `L2-RAD-02` does not run unless
the `kill`-shim canary has just proved the shim is live, and `M-SIM-canary` (delete `enable -n kill`)
must turn **the canary** red and **not** `L2-RAD-02` — which is exactly the vacuity that proves the
mechanism.

---

### I-03 · Never lose a task's state

**Requirement:** R1-06 part 2, in the owner's words — *"в нас в реєстрі має записуватись кожен стан,
його виконання … для того, щоби було відновити процес і продовжити, навіть руками."* Recoverable **by
hand** is part of the requirement, which is why the records are plain JSON a person can read.

| | |
|---|---|
| **Proved by** | L1 `RES-01`…`RES-09`, `JRN-01`…`JRN-06`, `CTL-05` · L2 `L2-LIFE-03` (crash at every step), `L2-LIFE-04`, `L2-QUO-06` · L3 `C-12` (crash at each of the 11 claim-ordering steps × 3 lane shapes = 75 cycles), `C-14`, `C-26`, `C-32`, `C-33` · L5 `V-10` |
| **Mechanism** | one write rule — **write to `<path>.tmp` in the same directory and `mv` into place; never truncate in place**. Ordering: `start` before the act, `result` last, so a crash leaves a detectable orphan rather than a false completion. Crash-at-every-step is a loop over enumerated steps, not eleven hand-written tests |
| **Mutations** | `M-ctl-truncate` / `MC-03` replace the atomic rename with a direct redirect → `CTL-05`, `RES-02`, `C-22`, `C-32` red · `M-jrn-truncate` truncate an over-long journal line instead of refusing → `JRN-02` red · `M-QUO-order` / `MC-10` swap the two writes of the pause path so a crash between them reads as a manual stop → `L2-QUO-06` crash loop red · `M-res-trust` make reconcile trust the registry without checking liveness → `RES-03/04/05` red |
| **Does not cover** | Real `ENOSPC`. `hdiutil attach -nomount ram://4096` succeeded and `mount` failed without privileges [V], so short writes that return success, `fsync` failing after `write` succeeded, and a rename failing between two good files are **not exercised**; the read-only-directory half is real (the kernel produces the error) and is kept as a shim-fidelity control |

Two measurements that set the shape of the tests here:

- **Concurrent appends corrupt above ~3 KB, and a broken size scored 60/60 twice** [V] (at 4000 and at
  4200 bytes, in separate rounds). So the journal line limit is 1024 bytes, **enforced by refusal**
  with the payload written to a blob and the line carrying a reference — never truncation — and every
  concurrency scenario runs a ladder × 3 rounds, with a single green round treated as no result.
- **The probe must be cheaper than the window it is looking for** [V]. A `jq`-per-read observer
  (~18 ms) saw **zero** torn reads against a truncating writer over 300 writes; a `[ -s ]` observer saw
  **245** at zero injected delay, and 92,139 at 10 ms. An expensive probe hides the bug it is looking
  for.

---

### I-04 · Never report success it cannot evidence

**Requirement:** R1-13 (verification of the *work* belongs to the configured process — this invariant
is about the orchestrator's own operations), R1-06 part 2, Д11.

**Why:** this is the largest family in the record and the one the owner was shown and did not act on
[C, ANALYSIS R1-13]. §1.3's first shape, four faces, one rule.

| | |
|---|---|
| **Proved by** | L1 `JRN-03`, `JRN-04` · L2 `L2-DEL-06`, `L2-CTX-02`, `L2-DET-02` · L3 `C-06`, `C-14` · L5 `V-01` (ledger veracity = 1.000, a **gate**), `V-05` (ref movement), `V-09` (fixed points) |
| **Mechanism** | the **LEDGER-CONTRACT**: one record per *effect*, and no record may claim an effect without an `evidence` block naming a **primary source the orchestrator does not write** — a first-party hook receipt, the session's own transcript, `git reflog`, the board's API read back, the OS process table, the raw usage body. A component that cannot name one emits `verified: false`, which the audit counts as an unverifiable claim, and unverifiable claims are a failure, not a pass. Emit **from the observation site, never from the attempt site** |
| **Mutations** | `M-04` strip the `evidence` block from one emit site → `V-01` red · `M-05` / `M-jrn-intent` move the log line above the confirmation → `V-01`, `V-02`, `JRN-03` red · `M-14` report merge success on exit status 0 → `V-05` red · `M-CTX-verify` report compact success without the post-condition re-read → `L2-CTX-02` red |
| **Does not cover** | A primary source that itself lies. A board API returning a stale read, a transcript missing a turn, a hook that silently did not fire — each defeats the audit invisibly. Mitigation: probes are cross-checked in pairs where two independent sources exist; where only one exists, the identity is marked **`single-witness`** in the report and is not treated as confirmation |

**The three first-party receipts this rests on are VERIFIED present** in the Claude Code 2.1.278 binary:
`UserPromptSubmit`, `PostCompact`/`PreCompact`, `SessionEnd` [V]. They matter because they are written
by the vendor's client, not by the component under audit, and are therefore unforgeable by it.

---

### I-05 · Never exceed a configured quota threshold

**Requirement:** R1-06 in four parts, including *"including none/pay-as-you-go"*.

| | |
|---|---|
| **Proved by** | L1 `THR-01`…`THR-12` · L2 `L2-QUO-01`…`L2-QUO-07` · L3 `C-03`, `C-04`, `C-05`, `C-09` · L4 `J3` (the unreadable-quota bundle must be an `ASK`, never an `ACT` on an assumed zero) · L5 `A-03`, `K-04`, `D2` |
| **Mechanism** | a typed sum: `OK | SOFT | HARD | UNKNOWN(Unauthenticated\|Unreachable\|Malformed\|Absent) | NotApplicable | MISMATCH`. Every reading is **labelled with the account it came from** and a label mismatch against the role being decided is a hard error, not a warning. An account switch **closes one series and opens another** and emits no crossing event. `NotApplicable` for a provider with no scheme is a first-class verdict, never `UNKNOWN` |
| **Mutations** | `M-thr-unknown-ok` / `M-QUO-open` / `M-10` map `UNKNOWN` to `OK` → `THR-02/04/05`, `L2-QUO-01`, `K-04` red — **this is the mutation the old suite passed 51/51** [V] · `M-thr-null-zero` coerce `null` to 0 → `THR-02` red · `M-QUO-401` / `M-12` collapse `401` into the generic branch → `THR-04`, `L2-QUO-02` red · `M-QUO-label` / `M-11` drop the account label → `THR-07/08`, `L2-QUO-03/04` red · `M-QUO-na` map `NotApplicable` to `UNKNOWN` → `L2-QUO-05` red · `M-thr-resume-past` / `M-QUO-epoch` pin the resume fallback to a fixed past epoch → `THR-09/10` red |
| **Does not cover** | **Which schema is live.** The shipped parser wants `.limits[].group/.percent`; the owner's own `CLAUDE.md` documents `five_hour.utilization`; fed the documented shape the shipped parser returns `UNKNOWN`; and the live endpoint returns HTTP 401 `authentication_error` right now, so neither could be confirmed [V]. A cassette of the wrong schema replays confidently forever. Only a scheduled live re-record with a schema diff catches this (D11, §9) |

Four things this invariant is not, each from a recorded failure:

- It is **not** "stop when the number is high". F-21: the wall-clock fallback was pinned to a fixed
  *past* epoch, so an unreadable read **resumed a paused run immediately** [C]. The property is
  `paused ⇒ resume_at > pause_at`, swept over epoch 0, far past, far future and a DST boundary.
- It is **not** satisfied by an honest read. F-16's code was careful — it failed closed to `UNKNOWN`
  and its comment said *"never OK-by-default"* — and then the **policy** layer's default `proceed`
  converted it into "carry on" [V in the old source]. `STP-07` is the same mistake one layer up: an
  undecidable custom stop must fail closed to `soft`, never to `running`.
- It is **not** measured once. `UNKNOWN` for N consecutive reads must escalate, because a threshold
  that never fires is indistinguishable from a healthy account [C: `weekly_all=unreadable%` recurring
  across many separate days].
- The run record must distinguish **"quota was fine"** from **"quota was never read"** (`THR-06`), or
  a post-mortem cannot tell them apart — the previous run's records could not.

---

### I-06 · Always apply a stop command within one tick

**Requirement:** Д12 (`stop-hard` / `stop-soft` / `stop-custom`, UNRATIFIED — the session ended there),
Д7 (behaviour changed *during* a run), R1-07 (account reassignment, soft/hard).

**Why:** the control file is **the operator's only brake on an unattended run**, and the previous
generation destroyed it on every tick. `harness-run.sh:226` truncates `attention.tmp` and `:361` `mv`s
over the live file [V in the old source]; the context watcher wrote corrections there all night and
discovered the loss only by grepping for a block it had written four minutes earlier [C]. Line 5620 of
that log reads `NO ONE IS BEING TOLD`.

| | |
|---|---|
| **Proved by** | L1 `CTL-01`…`CTL-13`, `STP-01`…`STP-09` · L2 `L2-CTL-01`…`L2-CTL-05` · L3 `C-21`…`C-26` · L5 `A-06`, `K-06` |
| **Mechanism** | **inbound and outbound are different trees with different owners.** The orchestrator opens the inbound tree read-only, always. A command is a **file**, not a line — written to a tmp path and renamed in, so it is never observed half-written and two writers never interfere, and "acted on exactly once" is expressible by command id. Change is detected by **content hash**, never by mtime alone. The stop lattice is `running < soft < hard`, monotone up, with `resume` legal from `soft` and refused from `hard`, which makes "hard beats soft" structural rather than a code path. Every stop record carries `{cmd_id, source, actor, reason, at}` and a record missing any of them is **corrupt**: the reader escalates and does **not** stop |
| **Mutations** | `M-ctl-write` / `MC-04` / `M-06` point the status writer at the inbound path → `CTL-01` red **immediately** · `M-ctl-mtime` / `M-BRD-mtime` trigger on mtime instead of hash → `CTL-08/09` red · `M-ctl-twice` drop the applied-id check → `CTL-03/04` red · `M-stp-soft-wins` / `MC-06` let a later soft downgrade a hard → `STP-04` red · `M-stp-attr` accept a stop record with no attribution → `STP-08` red · `M-stp-undecidable-open` make an undecidable custom stop fail **open** → `STP-07` red · `M-ctl-relpath` / `M-08` resolve the control path relative to cwd → `CTL-12` red |
| **Does not cover** | Whether the *human* can find the file. And nothing here grades a `stop-custom` rule's prose: `STP-06` asserts the core carries it **byte-for-byte** and never interprets it, which is the R1-13 boundary in this layer |

**The cheapest high-value test in the entire plan is `CTL-01`, and it costs one `chmod`:** run the tick
against a control tree at mode 0500 with the file at 0400 and require success. A truncate-then-rewrite
implementation cannot pass, because the `mv` into a 0500 directory fails. **Both modes are required** —
verified here: `chmod 500` on the directory blocks *creating* a file, but a truncating write to an
existing file still succeeds; only `chmod 400` on the file refuses it [V]. A test that chmods only the
directory passes against a truncating implementation.

---

### I-07 · Always clean up what it started

**Requirement:** Д3 — no ready work left → finish, and on finishing stop **what it started**, *"щоби не
залишати хвостів"*, without touching anything else. Д4 (worktrees), R1-16.

| | |
|---|---|
| **Proved by** | L1 `JRN-06`, `RES-06`, `RES-07`, `RES-08` · L2 `L2-LIFE-05`, `L2-RAD-03` · L3 `C-34`, `C-36` · L5 `V-10`, `A-11`, `K-08`, `D6` |
| **Mechanism** | cleanup is **idempotent and resumable from labels alone**, never from in-memory state, because a run that dies before cleanup is how the previous runs actually ended [C: the directory holds `DEAD-RUN` and `STOPPED`]. Every session has exactly one recorded **close-owner**, and ownership **falls back** when the owner dies |
| **Mutations** | `M-LIFE-owner` remove the fallback owner → `L2-LIFE-05` second arm red · `M-res-reap-busy` let the reaper close a busy session → `RES-08` red · `MC-30` treat an absent resource as a failure instead of `resolved_absent` → `C-34` red |
| **Does not cover** | Resource classes nobody labelled because nobody thought of them. The label rule is only as complete as the ledger's list of creation sites, and `O-41`'s lint (no teardown identifier constructed from an environment variable) is what keeps that list honest |

**This invariant has a positive control that the fix for it is most likely to break.** P-03: four
sessions in the real run hit `job still running after timeout — LEAVING SESSION OPEN (never
force-close)` and were later found finished on their own [C]. `RES-07` (reap a finished session whose
owner died) and `RES-08` (never close a busy one) are written as a **pair** and must be run together,
because the natural implementation of the first breaks the second.

---

### The five added invariants

The brief's seven are the ones the owner would name. These five are the ones the record forces, and
each is added with its evidence.

---

### I-08 · An absence is never an answer

**Requirement:** implied by R1-06, R1-09, R1-13, and by N2 (a run with no tests, no repo, no build).

**Why:** five separate corpus entries are the same bug — F-33 (`No tests found` from an import-time
crash), F-35 (`OK, 0 files compared` from a subdirectory; a tracked-tree sweep claiming exit 0 against
1,242 bytes of real diff), F-47 (the watcher's collector OOM-killed 26+ times while its consumer read
the empty result as health), F-59 (a marker detector globbing the wrong directory and reporting a clean
zero for several cycles), F-61 (BSD `find -newermt` erroring with stderr to `/dev/null`, **which would
have declared every healthy session idle for ever**) [all C].

| | |
|---|---|
| **Proved by** | L1 `THR-02/03/06`, `RDY-02` · L2 `L2-CTX-03`, `L2-QUO-01`, `L2-QUO-07` · L3 `C-31` · L5 `V-06`, `A-01`, and the `n/a`-declaration rule |
| **Mechanism** | three rules. (a) Every probe carries a **positive control** in the suite — a fixture it is known to match — so a probe that can never match fails at build time. (b) A result of zero units is `suspect` unless zero is **declared expected**. (c) `n/a` must be declared **in advance** in the run profile; an undeclared `n/a` at audit time is `UNVERIFIABLE`, never a pass. This last one is what makes N2's no-repo/no-tests case safe rather than silently unguarded |
| **Mutations** | `M-CTX-default` return `0%` when status-line parsing fails instead of `unreadable` → `L2-CTX-03` red · `M-15` accept the process's summary line without the conservation arithmetic → `V-06` red · break a probe's syntax → its positive control red |
| **Does not cover** | An absence nobody declared a probe for at all |

**The conservation identity is the general form and it is arithmetic, not judgement:**
`declared_total == passed + failed + skipped + not_reached`. The historical fixture is free — 382
declared, 346 passed, 0 failed, 35 never-reached, and the missing test was not even in the
never-reached list; it was caught by **subtraction, by a human**, after host memory pressure killed the
runner [C]. The same identity is turned on this plan's own runner (§6, `MET-01`).

---

### I-09 · Every waiting state is bounded and every ladder terminates at a human

**Requirement:** R1-09 (delegated to the orchestrator's judgement, no fixed ladder), R1-17
(notifications), Д5 (three identical failures), Д11.

**Why:** the observed peak before any escalation fired was **44,791 seconds — about 12.4 hours** — with
a single orchestrator and no lanes [C]; a dead run flagged the same condition **1,085 times over about
five days** [C]; a recovery component polled `run is stopped — holding` every 180 s for 32 minutes
while doing nothing [C]; and the human-notification watchdog had exited on "run finished" and was never
restarted, during the 85-minute runaway [C].

| | |
|---|---|
| **Proved by** | L1 `THR-05` · L2 `L2-LIV-04`, `L2-LIV-05`, `L2-DET-03`, `L2-OBS-02` · L3 `C-02`, `C-20`, `C-31` · L5 `V-07`, `V-08`, `A-04` |
| **Mechanism** | the ladder is an ordered, tested sequence with a **terminal rung that always fires**; there is no path through it that ends in silence. Findings **deduplicate with a count** (one record with `count=100`, not 100 records) and escalate on persistence. A finding that **no available action can resolve** is reported as such at *first* detection, not on a timer. Every hold **names what would end it**. The notifier is heartbeat-verified, not assumed, and its absence escalates by a second route |
| **Mutations** | `M-LIV-rung` / `MC-23` delete the terminal rung → `L2-LIV-04`, `V-07` red · `M-DET-emit` / `MC-27` emit on every tick instead of deduplicating → `L2-DET-03`, `V-08` red · `M-OBS-cfg` check the notifier's configuration instead of its liveness → `L2-OBS-02` red · `MC-24` remove the repetition counter → `C-02`, `C-07` red |
| **Does not cover** | Anything longer than the canary horizon. A 4-hour C2 is structurally blind to a 12.4-hour delay and to a five-day re-flag; only the permanent audit on real runs sees those |

**`L2-LIV-05` is the single most valuable scenario in this invariant** and it is worth stating why: the
global backstop — *ready work + free capacity + no progress for T ⇒ escalate* — is asserted **with
every detector deliberately stubbed to return `healthy`**. It does not depend on any detector being
right, and the record shows every detector in the system being wrong at some point [C]. `J-SUP-34` is
its fixture: 35+ minutes idle with eight ready tickets and no lanes, because the watcher classified the
state as "held", which was in the vocabulary and in no action rule.

---

### I-10 · A corrective action is bounded and fixed-point aware

**Requirement:** R1-09, Д5, and Kubernetes-controller discipline (level-triggered, idempotent
reconciliation) [C].

**Why:** the 85-minute self-sustaining loop is the most instructive single incident in the record [C].
A watch matched what looked like a usage-cap banner **inside the orchestrator's own wrapped prose**,
pressed Escape and sent `continue` about every sixty seconds; each zero-second turn left the screen
unchanged, **so the same text matched again** — a closed loop with a fixed point. It ran 21:53 → 23:21
and ended only when an external `SIGTERM` arrived. A **second 45-minute instance** occurred in the other
run, which is why this is a class and not an anecdote.

| | |
|---|---|
| **Proved by** | L1 `CTL-03`, `CTL-04` (`decide()` on an unchanged world produces an empty plan — two lines of test, one whole bug class) · L2 `L2-DET-01`, `L2-DET-02` · L3 `C-07` · L5 `V-09` |
| **Mechanism** | three independent defences, because the incident had three independent causes and any one of them would have broken it: a **repetition bound** per (target, trigger) with escalation; **fixed-point detection** (an action whose post-condition was "the state changes" and whose state did not change is recorded *ineffective*); and a **supervised notifier**. Plus two lints: a detector never matches over a region that can contain quoted text, and **no logging helper may write a detector's own trigger string into a file a detector reads** (`O-43`) |
| **Mutations** | `M-DET-count` remove the repetition counter → `L2-DET-02` red · `M-DET-anchor` / `MC-25` match the banner anywhere on the screen instead of anchoring to the last non-empty line → `L2-DET-01` red · `MC-26` let a log line contain the detector's own trigger string → `C-07` red |
| **Does not cover** | A loop whose observed state *does* change slightly each cycle |

**This is the cheapest retirement in the plan.** A sibling reproduced the mechanism exactly in three
lines: `grep -qE 'usage limit reached|limit will reset at'` fires on `Claude usage limit reached…` ✓,
on `I checked and the session had a usage limit reached banner, so I paused.` ✗, and on
`> NOTE: watch for "limit will reset at" in the pane` ✗; a last-non-empty-line anchor passes all three
[V]. **Three lines of test would have prevented 85 minutes of a self-sustaining loop.**

---

### I-11 · Verify before you run; refuse at 22:00 rather than degrade at 03:00

**Requirement:** a cross-cutting pattern the owner states four separate times — account switching
(R1-07, *"verified to work before a run starts"*), the notification channel (R1-17, *"повинен лише
переконатися, що це працює"*), board statuses (R1-04), worktree environment (Д4).

| | |
|---|---|
| **Proved by** | L1 `CFG-12`, `CTL-12`, `LEA-09`, `LEA-10` · L2 `L2-QUO-02` (second arm), `L2-QUO-07`, `L2-PLT-02` (config arm), `L2-OBS-02` · L5 `A-01`…`A-10`, `A-14` |
| **Mechanism** | preflight proves, with **zero model tokens**, and refuses **by name at the point of the break**: the lock; an authenticated call per account with the identity label matched to its role; the notification channel by round-trip nonce, not by configuration; the board's minimum status set and a write read back; every declared step resolving **and dry-running**; the red-line file readable and present in **the production renderer's output**; the worktree base ref and declared env vars; the adapter's capability set against what the configured process needs. Nothing is created on a refusal. What cannot be refused is **degraded on the record**: `plan.json` names which numbered requirement stopped holding tonight, on which lane, from what to what |
| **Mutations** | `M-03` truncate the discovered line ceiling to a hardcoded 200 → `A-07` red (and it proves the ceiling is *discovered*) · `M-PLT-claim` have an adapter declare a capability it does not implement → `L2-PLT-02` config arm red — **this is the old suite's M6, which it passed 51/51** [V] · point a declared step at a non-existent command → `A-02` red · remove the include from the **renderer** → `A-09` red |
| **Does not cover** | A capability that works at 22:00 and stops at 03:00 |

**Two environment hazards make this invariant concrete on this machine, both VERIFIED:** `find`
resolves to **`bfs` 4.1.1** on the interactive PATH but to `/usr/bin/find` under `env -i` — which is
what `launchd` and `nohup` give a detached process — and the two do not accept the same flags; and
`/tmp` is a symlink that `find` will not descend, so a `/tmp`-rooted freshness probe returns empty for
ever, which is the **same symptom** as F-61 from a **second, independent cause** [V]. `grep` is
shadowed too, and `date` is BSD. Hence `LEA-09`/`LEA-10`: every detached entry point runs under `env -i`
with only its **declared** environment, and `declared_env ⊇ actually_read_env` is asserted per
component by removing one variable at a time.

---

### I-12 · The suite cannot silently shrink

**Requirement:** none in ANALYSIS-01. This one is about the plan defending itself, and it is here
because the failure it prevents is the one that actually happened: not a wrong answer, but **a suite
that stopped asking the question**.

**Why:** three measured defects in the repo's own master runner [V]. (a) `tests/run-all.sh` calls
`set -e` at lines 41 and 50 believing it restores a flag that was never on; with `pipefail` already
active, a runner that prints no `PASS=` line **kills the master script silently and every later plugin
never runs** — reproduced with `PLUGINS=(fakep goodp)`: exit 1, no message, no summary, and `goodp`
never executed. (b) There is **no floor** on assertion count: a runner printing `PASS=1 FAIL=0` is
accepted and aggregated. (c) Every runner is executed **twice**. And a plugin absent from the `PLUGINS`
array is invisible with no warning — `orchestrator` is **not in that array today** [V], so the
registration test fails before it passes, which is the correct order.

| | |
|---|---|
| **Proved by** | L1 `MET-01`…`MET-06` · L2 §7.3's six mechanisms (canaries, a committed `EXPECT_SCENARIOS` floor, attribution before execution, `bash -n`+`shellcheck` over every scenario, an internal idempotence pass, leak detection) · L3 `MC-00` (the meta-mutation), `O-CH-01` · L4 gates 4 and 5 (conservation identity, corpus floor + sha256 digest) · L5 `RUNNER-CONTRACT`, `P-01`…`P-04` |
| **Mechanism** | a committed count floor per layer; the conservation identity `total == pass + fail + skip` asserted on the suite itself; an `EXIT` trap that prints `PASS=/FAIL=` on **every** path including abort; a case that executes **zero assertions is a failure, not a pass**; the corpus digest; the escape-hatch cap (≤15% of cases may be hand-written bash, or the drift back to 37 greps starts again); and the registration assertions (`marketplace.json` lists it, `PLUGINS` contains it) |
| **Mutations** | `M-SIM-floor` delete two scenario files without updating the floor → the floor check red · `MC-00` make `fp()` unconditionally return 0 → **every chaos scenario declaring `expect_fired` reports `VACUOUS` and the layer goes red** · `M-29/M-30` delete or edit a corpus case → the **digest** gate red, not the score · `M-31` make the replay runner exit 0 unconditionally → the runner self-check red · `M-32` remove `orchestrator` from `PLUGINS` → the registration test red |
| **Does not cover** | A test that is present, executes, asserts, and asserts the wrong thing. That is what the mutation gate is for, and the mutation gate is what `MC-00` defends |

**L3's `expect_fired` rule deserves naming as the general idea.** A scenario declares which fault points
must have fired and how often; **the runner checks the ledger against that declaration before it
evaluates a single assertion**, and a mismatch is verdict `VACUOUS`, counted as FAIL. It is the
mutation rule's structural twin: *you cannot assert on a fault you cannot prove happened*. Unlike the
mutation rule it costs nothing and runs on every pass.

---

## 3. The five layers

### L1 — contract and unit · ~23 s · 88 cases · $0

**Proves:** the deterministic core, as pure functions over files. Config resolution across the six snf
slots plus a run scope, with **per-key provenance** so a precedence regression names itself. The
watched control file as a protocol, not a config file: read-only inbound, one command per file,
hash-not-mtime, applied exactly once, applied on the *next* tick. The stop lattice. The single-
orchestrator lease. The append-only journal. Readiness as a closed reason set. Threshold arithmetic
with typed unknowns. The state records needed to resume, including crash-at-every-step of the pause
path. And its own defences: a count floor, a conservation identity, a ban-lint over `core/`, the
installed-copy drift check.

**Costs:** ~23 s serial for 88 cases (measured units on this machine: a bash script calling `jq` once
is **30 ms**, a bare `jq` **18 ms**, `mktemp -d` + `rm -rf` **6 ms**, a 60-way concurrent round
**~0.4 s** [V]). Its mutation gate is ~25 s for 28 mutations, because the runner supports
`--only <ids>` — running the whole suite per mutation would be ~11 minutes, which is a gate that runs
never. Authoring: the seams are a day if taken up front and a rewrite if not; the runner and
`assert.bash` a day; the 88 cases about four days.

**Cannot catch:** it tests `decide()`, not `apply()`. A plan that is correct and never executed is
invisible here, and the corpus's own judgement is that the majority of real failures were in
**adapters**, not orchestration logic [C]. Nothing about a real terminal, a real agent or a real
vendor. No proof that the fakes resemble reality. No proof that production calls the seams at the right
*moments* — the ban-lint proves `date` is absent from `core/`, not that the tick asks the clock at the
right points. No schema truth. No judgement, by design. And **concurrency is sampled, not proved**: the
delay ladders mitigate, they do not prove, and a race narrower than the smallest injected delay is
invisible.

---

### L2 — simulation · ~64 s serial / ~20 s at `-j 4` · 46 scenarios · $0

**Proves:** the **real orchestrator process**, unaware it is in a simulation, against a fake world in
virtual time. Three stub agent CLIs on PATH chosen to span the axes R1-07/R1-11 name — `claude`
(interactive TUI over a pty), `codex` (TUI *or* headless), `glm` (**headless only, no quota scheme at
all**, no resume) — so an adapter abstraction that only ever met Claude Code fails here rather than at
03:00 against a real account. A behaviour scripting format where the fifteen shipped session behaviours
are **data, not code** (adding the sixteenth costs eight lines). A virtual clock: two shims and one
file turned twelve `sleep 600` calls — two simulated hours — into **0.678 s** real, with `date` moving
in lockstep [V], so the 44,791-second stall is a scenario rather than a legend. A fake board with two
backends behind one stub, because the bug is **divergence between backends**, and the same scenario
file runs against both. Quota cassettes including the real `401 authentication_error` body. A world
recorder for blast radius.

**Costs:** measured floors — stub session spawn→ready **0.60 s** (10 samples), world-only scaffold
**15 ms** (200 samples), a complete prototype scenario including tmux spawn, delivery attempt,
read-back and teardown **1.16 s failing / 1.83 s passing** [V]. A second full pass under `env -i` is
owed (+~64 s) because the environment hazards are real. The mutation gate is ~3 minutes for 44
mutations. Build: ~6.5 working days for one implementer who already has the seams.

**Cannot catch:** **stub fidelity, and it can invert a verdict — measured twice, from two directions.**
(a) A `read`-loop fake submits stranded text on a bare Enter; the real TUI does not [V]. (b) The
1024-byte silent send ceiling is a property of the **stub's line discipline**, not of the terminal:
same tmux, same payloads, a canonical-mode stub drops 1024 bytes silently while a raw-mode stub
delivers 16,000 bytes byte-exact and `tmux send-keys` refuses **loudly** above ~17,000 with
`command too long` [V]. A real Claude Code TUI is in raw mode. So a simulation shipping only the
obvious fake would "prove" a chunk-below-1024 rule the real client does not need **and miss the real
ceiling entirely**. Line-discipline mode is therefore a declared scenario parameter and every delivery
scenario runs in both. Also outside L2: `sh -c` escapes the `kill` interception (0/3) [V]; `$SECONDS`,
`$EPOCHREALTIME` and `read -t` are builtins that bypass the clock shim; GUI terminal backends cannot be
driven headlessly at all — and the one recorded backend that **cannot type at all** is a GUI backend
[V in the old source]; real resource exhaustion is injected, which tests the handler, not the trigger.

---

### L3 — chaos · 35–55 s gate / 4–7 min full / 60–90 s crash · 37 scenarios · $0

**Proves:** the same run **with something broken at a chosen instant**, deterministically and offline.
Its mechanism is a six-line `fp()` fault point shipped in production source (bash 3.2 offers no
portable interposition), a line-oriented fault plan, and a 25-point catalogue of which **eleven are
exactly the eleven steps of the claim-ordering invariant**, which turns "crash at every step" into a
table-driven loop rather than eleven hand-written tests. Four fault families need no hook at all and
are therefore the layer's most durable tests, because no refactor can disable them: `SIGKILL` and
`SIGSTOP` of the supervisor from outside, a second orchestrator started deliberately, the lock path
unlinked while held, the state directory made read-only.

**Costs:** measured primitives [V] — `bash -c ':'` **2.5 ms**, `python3 -c 'pass'` **29 ms**, one `jq`
**16 ms**, 5 rounds of 40 concurrent claims **0.23 s**, 11 filesystem crash shapes **0.11 s**. The
consequence for the design is hard: **the fault runtime may not call `jq`**, because 16 ms per fault
point hit is more than every other cost in the layer combined. Production overhead of shipping the hook
is **10.5 µs per call when disabled** [V]. Build ~7.5–9.5 days, assuming L2 exists — and if L2 does not
exist, L3 is not buildable, which is the correct dependency.

**Cannot catch:** real out-of-space (unreachable without privileges on this machine [V]); **which clock
freezes across a real machine sleep** — the sources exist and are readable, but if production picks
wrong, *every scenario in the sleep/wake group passes and the bug ships*; the network faked at the
adapter boundary rather than the socket, so "no timeout on a socket read" is invisible; a genuinely
same-second recycled PID; memory pressure and OOM; and **accumulation over a real long run** — fd
leaks over 3,000 ticks, a journal outgrowing what the fold can read, a tmux server dying when its last
pane closes. Virtual time is why this layer is affordable and it is exactly why it cannot see those.

**The number that justifies the whole layer** [V]: a truncate-then-write writer sampled by a concurrent
reader was caught short-or-empty **4 times in 300 writes**; with a 2 ms fault injected between the
truncate and the write it was caught **276 times in 60**. *A chaos scenario without a fault point is a
coin toss with good odds.*

---

### L4 — judgement · L4-A < 1 s / 1,403 cases / $0 · L4-B ~$0.85–$14 · 42 scenarios

**Proves:** the six places where behaviour is produced by a model reasoning over evidence rather than
by a rule — stalled-or-thinking, ticket-ready, escalate-or-decide, does-this-change-contradict-finished-
work, is-this-inside-my-boundary, did-this-step-really-succeed. It rests on one seam: every judgement
goes through `judge(kind, evidence, policy) → {verdict, confidence, evidence[], rule_cited?}`, reaching
the model through one replaceable command speaking **batched JSONL**. That seam makes the same golden
case file drive a stub judge (free) and a real one (paid). **The corpus is real, free and larger than
anyone claimed: 1,329 cases built in 0.23 s from run directories already on disk** [V], because a
heartbeat that resumed is a mechanically provable false stall.

**Costs:** L4-A is **under a second** for 1,403 cases and adds ~2% to the repo's 42 s suite, so there is
no argument for not running it on every commit — *provided* the protocol is batched: the same work
through per-case subprocesses takes **50.9 s**, a 460× penalty [V], and a 51-second gate is one that
gets skipped. L4-B: smoke ~$0.85, full ~$8.60, hard (12 cases × 10 runs) ~$14; ≈ **$96/month** at 20
prompt changes, 6 PRs and 2 releases. `--ablation none` (the default `with-without` doubles every case
to answer a question this layer does not ask), `--judge-model sonnet` (the tool's own guide says not to
use a small judge and not the agent's own family; the upgrade is ~1.4% of the tier's cost), and
`--max-cost-usd` **in the committed command, never in someone's shell history**.

**Cannot catch:** **a bad signal, which is the failure that actually happened.** Every case in the
corpus is a *correct* observation of the world; the run's expensive failures were probes that could
never match, parsers that silently substituted a tighter default, detectors globbing the wrong
directory. A judgement layer that is perfect on false inputs makes confident wrong decisions. Also: its
stall corpus is **100% one class** — auto-adjudication can prove a session came back, never that one
was truly stuck — so the recall floor for `STALLED`/`RUNAWAY` rests on **twelve hand-curated cases**
and must be read as a tripwire, not a metric. 573 of its escalate labels are "nobody reversed it",
which is not approval. It is single-vendor (`claude plugin eval` runs a Claude Code child and cannot
test the others). And it tests what a model decides, not what the orchestrator then does — a correct
`HARD_STOP` that does not stop a task is a passing L4 case and a failed night.

**Two measured facts that set this layer's rules.** A degenerate judge — always `WORKING`, always
`ACT`, always confidence 0.95 — scores **90.7% "accuracy"** on the corpus [V]. So **no overall accuracy
number may appear in this suite's output**; the gates are per-class recall floors and a false-positive
ceiling, with the majority baseline printed beside every score, always. And **delta-over-baseline
cannot be a gate**: on a single-class group the baseline is 1.000 and no judge can ever beat it, which
is the same defect as a test that can never fail [V].

---

### L5 — acceptance and live canary · 8 min free · C1 ~35 min · C2 ~4 h

**Proves:** the only question that is the orchestrator's own business and that the entire failure
record says it got wrong — **is every claim the orchestrator made about its own actions independently
true?** The mechanism is a post-hoc reconciliation audit by an auditor that **shares no code with the
runtime** and re-derives what happened from nine primary sources the orchestrator does not write.
Around it: fourteen free preflight gates before every real run; a bounded fault schedule for the canary
(`faultd` runs outside the run's process tree and writes its own log, which the audit reads as a
primary source, so the orchestrator cannot anticipate a fault and D3 can exclude injected interventions
from human ones); ten conservation identities that run on **every real run, forever**, not only on
canaries; three binary gates and nine dials, each printed with its baseline; a morning artifact whose
first line is the verdict and whose first section is *what needs you*; and a promotion rule requiring
**two consecutive green canaries, the second on unprepared machine state with a different machine
fingerprint**.

**Costs:** everything free is free — preflight, the rehearsal profile, the audit, the report, the
mutation pass and the corpus ingester make **zero model calls**, and that is the property that decides
whether the layer gets run. The canary costs real sessions: C1 ≈ 2 short workers, C2 ≈ 12 across four
hours, estimated at **0.1–0.2%** and **0.5–1%** of a weekly subscription window respectively [I] —
estimates whose replacement by measurement is canary 1's job.

**Cannot catch:** anything longer than the canary's horizon (the peaks that mattered were 12.4 hours
and five days). Rare non-determinism — **two green canaries are two samples**, and a green `A-08` must
never be cited as proof of exclusivity; that proof lives in L1/L3's delay sweeps. Quality of the work,
by R1-13 and correctly. **Platforms other than the one the canary ran on** — a green C2 on Claude Code
interactive says *nothing* about Codex headless, GLM or Gemini, and this is the largest unknown in the
whole design. Non-code runs. A shared blind spot where a primary source itself lies. Fault fidelity: a
shimmed token revocation is not a real expiry and a `kill -9` is not a Mac going to sleep — which is
how the previous run actually ended [C]. And cost accounting it did not produce: R1-06 part 3 says to
reference the configured process's own records, and L5 reads them and **cannot validate them**.

**What the canary is actually buying, stated plainly:** a C2 pass costs about four hours and around 1%
of a weekly window. The alternative it is compared against is a 34-hour run that produced ~60 distinct
failures, an 85-minute runaway, 12.4 hours of a dead night, a destroyed default Docker stack and a lost
operator instruction — and whose 51-test suite caught none of it [C].

---

## 4. The scenario catalogue

**251 scenario ids across five layers, deduplicated into 124 contracts.** A contract is one thing that
must hold; the ids beside it are the rungs that prove it at different fidelities, from a sub-second
pure function to a four-hour real run. The dedup is the point: `LEA-01`, `L2-LIFE-01`, `C-16` and
`A-08` are not four tests of four things, they are four rungs under **one** invariant, and only the
ladder proves it.

**The fourteen families.** `LC` lifecycle · `CP` control plane · `CQ` capacity · `CX` context ·
`DV` delivery · `LV` liveness · `DT` detectors · `WK` work intake · `BR` blast radius · `EV` evidence ·
`PL` platform · `OB` observability · `JG` judgement · `SD` suite defences. A contract id is a family
code plus a number (`CP16`); a **layer** id always carries a hyphen (`CTL-01`, `C-17`, `A-08`), so the
two can never be confused.

**Column key.** **Ids** — layer 1 ids are bare (`CTL-01`), layer 2 ids are prefixed (`L2-CTL-01`),
layer 3 ids are `C-nn`, layer 4 ids are `Jn-nn`, layer 5 ids are `A-nn` / `K-nn` / `V-nn` / `P-nn`.
**Req** — the ANALYSIS-01 item defended. **Descends from** — the recorded failure (`F-nn` from
`ground-failure-corpus.md`, `P-nn` for a positive control to preserve) or `[V]` for a defect measured
on this machine during the spike. **●** — one of the twenty that must pass before the first unattended
overnight run (§4.2). **†** — architecture-conditional, see open decision **D3**.

### 4.1 The table

#### LC · Identity, lease and lifecycle

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| LC1 | Exclusive acquisition, one winner at every rung of the delay ladder | `LEA-01` · `L2-LIFE-01` · `C-16` · `A-08` | R1-10 | F-13, and the naive-lock-passes-at-delay-0 result [V] | ● |
| LC2 | The loser exits with a typed code naming the holder, and touches nothing | `LEA-02` `LEA-03` · `C-15` | R1-10, R1-16 | F-13 | ● |
| LC3 | Dead is reclaimed; `SIGSTOP`ped is not; a reused pid does not read as alive | `LEA-04` `LEA-05` `LEA-06` · `L2-LIFE-02` · `C-18` | R1-10 | F-13 cases 2–3; `SIGSTOP` holder verified [V] | ● |
| LC4 | Liveness never keys on a process name, title or `pgrep` pattern | `LEA-07` (+ the `O-40` ban-lint) | R1-10, R1-16 | F-13 case 4, F-45, and the `harness-question-q-screen-orchestrator` title read as a second orchestrator |  |
| LC5 | The health checker cannot revive a live run; two doctors do not both fire | `LEA-08` · `C-19` | R1-10 | F-13's first listed precondition |  |
| LC6 | The lock path unlinked while held does not produce two holders | `C-17` | R1-10 | split brain reproduced here: 2 live holders [V] |  |
| LC7 | Release is idempotent and never releases someone else's lease | `LEA-11` | R1-10 | [I] — what a crashed-then-restarted orchestrator does |  |
| LC8 | Restart classifies `mine-alive` / `mine-dead` / `not-mine` **before** claiming anything | `RES-03` `RES-04` `RES-05` · `L2-LIFE-04` · `C-13` · `K-02` | Д10, R1-10, R1-16 | F-15, both directions | ● |
| LC9 | Supervisor and child both die: an ambiguous op escalates, it does not replay | `C-14` | R1-10 | F-15 |  |
| LC10 | Orchestrator killed mid-tick or machine rebooted: revived, nothing redone | `C-11` · `K-01` | R1-10 | F-13, F-15 |  |
| LC11 | Crash at **every** step of the claim and pause paths leaves a legal state | `RES-09` · `L2-LIFE-03` `L2-QUO-06` · `C-12` `C-26` | R1-10, R1-06 | F-21 / F-22 / F-23 — one bug fixed twice, badly, the third still open | ● |
| LC12 | Every session has one close-owner, ownership falls back, a **busy** session is never force-closed | `RES-07` `RES-08` · `L2-LIFE-05` · `V-10` | Д3, R1-16 | F-14 (idle 1 d 4 h) and **P-03** preserved |  |
| LC13 | Every detached entry point survives `env -i`; `declared_env ⊇ actually_read_env` | `LEA-09` `LEA-10` · `L2-QUO-07` · `A-01` | R1-06, R1-10, R1-17 | F-20, F-61; `find`→`bfs` vs `/usr/bin/find`, `/tmp` symlink, BSD `date` [V] |  |

#### CP · The control plane, stops and config

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| CP1 | A tick against a **read-only** inbound tree succeeds (dir 0500 **and** file 0400) | `CTL-01` · `L2-CTL-01` · `A-06` | Д12, Д7, R1-07 | F-10 — `NO ONE IS BEING TOLD` | ● |
| CP2 | A second writer's command survives N ticks and is acted on **exactly once** | `CTL-02` `CTL-03` · `L2-CTL-02` · `C-25` · `K-06` | Д12, Д6 | F-10 | ● |
| CP3 | Every state write is atomic; no reader ever observes a torn or zero-byte document | `CTL-05` `RES-02` · `L2-CTL-03` · `C-22` `C-32` `C-33` | Д12 | F-11; and the cheap-probe result (245 vs 0 catches) [V] | ● |
| CP4 | `decide()` on an unchanged world produces an empty plan | `CTL-04` | R1-09 | F-40, F-42 |  |
| CP5 | Change is triggered by content hash, never mtime, and applies on the **next** tick | `CTL-08` `CTL-09` · `C-21` · `L2-BRD-04` arm 1 | Д7, Д8, Д11 | F-40 (level- vs edge-triggered) | ● |
| CP6 | An invalid or unknown command is refused once, never approximated, never obeyed | `CTL-06` `CTL-07` · `C-23` | Д12 | F-42 (1,085 re-flags), F-16's class |  |
| CP7 | Commands apply in `issued_at` order, not directory order | `CTL-13` | Д12 | [I] — readdir order is not sorted |  |
| CP8 | The control and question channels resolve to one absolute path from every cwd | `CTL-12` · `L2-CTL-05` · `A-06` arm 2 | Д6, Д4 | F-12 — a question invisible for an hour |  |
| CP9 | An account change carries soft/hard; soft leaves live sessions on their **boot** account | `CTL-10` `CTL-11` · `K-05` | R1-07 | F-19 and its adjacent finding |  |
| CP10 | Hard beats soft under **any** interleaving | `STP-04` · `L2-CTL-04` · `C-24` | Д12, R1-06, R1-07, R1-08 | the cross-cutting soft/hard vocabulary, never once tested | ● |
| CP11 | `stop-soft` starts nothing new, lets live work finish, and completes as one record | `STP-01` `STP-02` | Д12, Д3 | F-42 (`STOPPED` with no `run.complete`) |  |
| CP12 | `stop-hard` acts in the tick it arrives, against this run's registry only | `STP-03` | Д12, R1-16 | — |  |
| CP13 | Resume is legal from soft and refused from hard | `STP-05` | R1-14 | *"поки людина не відпустить"* |  |
| CP14 | `stop-custom` is carried **byte-for-byte** and never interpreted by the core | `STP-06` | Д12, R1-13 | the R1-13 boundary in this layer |  |
| CP15 | An undecidable custom stop fails closed to `soft`, never to `running` | `STP-07` | Д12 | F-16, one layer up |  |
| CP16 | A stop record without attribution is corrupt on read and unreachable on write | `STP-08` `STP-09` | Д12 | F-23 (`#82`, open) | ● |
| CP17 | The highest slot that sets a key supplies the value, with per-key provenance | `CFG-01` `CFG-02` `CFG-03` `CFG-04` | Д1 | decision 0003 — the case an implementer gets backwards |  |
| CP18 | `use` replaces whole, `never` unions and holds, a committed veto cannot strike a personal pick | `CFG-05` `CFG-06` `CFG-07` `CFG-08` `CFG-09` | Д1 | `config-levels` §5 |  |
| CP19 | An unknown key costs only itself; a config-shaped file outside the table is not silent | `CFG-10` `CFG-11` | Д1 | a config that refuses to load over one stray key at 3 a.m. |  |
| CP20 | A resolved config holding both a process **kind** and custom **steps** is a hard error | `CFG-12` | R1-03 | *"комбінувати ні, тут або або"* — a mixture deep-merge produces that nobody wrote |  |
| CP21 | The resolved config is frozen and hashed at run start; mid-run change arrives only via the overlay | `RES-01` | R1-06 p2 | [I] — what makes a resume reproduce the run it resumes |  |

#### CQ · Capacity and quota

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| CQ1 | The boundary is exactly where the config says, including fractional percents | `THR-01` · `L2-CTX-04` | R1-06, R1-08 | the shipped gate's own near-miss comment [C] |  |
| CQ2 | `null`, a string and malformed JSON are `UNKNOWN(Malformed)`, never a number | `THR-02` `THR-03` | R1-06 | the live `authentication_error` → naive `jq` → `null` [V] |  |
| CQ3 | `401` is `UNKNOWN(Unauthenticated)`, routed immediately; preflight makes a real authenticated call | `THR-04` · `L2-QUO-02` · `C-03` · `A-03` · `K-04` | R1-06, R1-07 | F-18 — 82 minutes blind | ● |
| CQ4 | `UNKNOWN` never becomes `OK`; N consecutive unknowns escalate; the record says `reads=0 usable` | `THR-05` `THR-06` · `L2-QUO-01` · `C-04` | R1-06 | F-16 — **the mutation the old suite passed 51/51** [V] | ● |
| CQ5 | Every reading is labelled with its account; a mismatch against the role is a hard error | `THR-07` · `L2-QUO-03` | R1-06, R1-07 | F-17 — 94% weekly read on a pool nothing ran on | ● |
| CQ6 | An account switch closes one series and opens another, emitting no crossing event | `THR-08` · `L2-QUO-04` · `C-05` | R1-06, R1-07, Д7 | F-19 — 26% → 6% from the switch alone |  |
| CQ7 | `paused ⇒ resume_at > pause_at` for every clock value; exactly one resume, at the right tick | `THR-09` `THR-10` · `C-09` `C-10` | R1-06, Д12 | F-21 (`#65`) — an unreadable read resumed a paused run at once | ● |
| CQ8 | A provider with no scheme is `NotApplicable`, never `UNKNOWN`, and gates nothing | `THR-12` · `L2-QUO-05` | R1-06 p1, I1 | no historical record — pay-as-you-go is untested by history |  |
| CQ9 | An unrecognised response schema is reported as unrecognised, not as health | `L2-QUO-01` schema arms | R1-06 | the live `.limits[]` vs `five_hour.utilization` divergence [V] — see **D11** |  |

#### CX · Context and compaction

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| CX1 | Context thresholds carry soft/hard semantics per role and per platform; soft waits for the configured step boundary | `THR-11` · `L2-CTX-04` | R1-08 | F-37 — **nothing measured context at all** [V in the old source] |  |
| CX2 | Compaction is gated on the shell count read from the status line, and deferral is reported | `L2-CTX-01` | R1-08 | F-08 — three attempts consumed as ordinary text, 91%→95%→auto-compact |  |
| CX3 | Compaction is a transaction with a post-condition re-read; failure escalates | `L2-CTX-02` | R1-08 | F-39; R1-08's *"механізм, який гарантовано робить цю дію"* |  |
| CX4 | Status-line parsing yields a number or an explicit `unreadable`; N unreadables escalate | `L2-CTX-03` | R1-08, R1-11 | F-60 (`Opus 4.8`), F-62 (a scrolled-off `timeout 1800s` halving the ceiling), F-63 |  |
| CX5 | Context growth is attributable to repeated identical calls | `L2-LIV-03` · the D9 dial | R1-08, Д11, Д8 | F-38 — 3,466 of 3,626 calls were `echo idle`, 77% of growth |  |

#### DV · The instruction channel †

> **† These seven are architecture-conditional.** `BUILD-PLAN` §1.1 idea two — *liveness is a process,
> not a screen* — deletes typing into running sessions, and with it six FIELD-NOTES failure records.
> If that decision stands, DV1–DV5 are **retired by deletion of the capability**, not tested, and their
> replacement is the control-ack contract (CP2) plus the adapter's structured event stream. DV6 and DV7
> survive in changed form and become *more* important, because the receipt moves from a transcript
> read-back to the event stream and the lane's exit. **Do not build E1–E5 before D3 is settled.**

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| DV1 † | A bare Enter does not submit a stranded line; the failure is recorded as a failure | `L2-DEL-01` · `K-03` | R1-08, R1-09, Д12 | F-01, F-07 — five instructions lost, logged as delivered |  |
| DV2 † | A write refuses over a non-empty input line and surfaces the pending text | `L2-DEL-02` | R1-08, Д12 | F-02 — a human's `push master` destroyed |  |
| DV3 † | The per-backend ceiling is **discovered at startup**; every payload arrives byte-identical or is refused loudly | `L2-DEL-03` · `A-07` | R1-08 | F-03; the 1024-byte canonical-mode cliff and the ~17 KB loud refusal [V] |  |
| DV4 † | The recovery ladder is transactional: the text ends in the inbox or on the line, never in neither | `L2-DEL-04` | R1-08 | F-04 |  |
| DV5 † | Identity is read back off the target before any write | `L2-DEL-05` | R1-09, R1-10 | F-06 — 149 minutes undetected from pane drift |  |
| DV6 | The receipt is the transcript or the event stream, never the screen | `L2-DEL-06` · `V-02` | R1-08, R1-09 | F-05, F-09 |  |
| DV7 | One `deliver`/`instruct` contract across every adapter and backend; an incompatible pairing is refused at config time | `L2-PLT-02` | R1-08, R1-11, I1 | F-09, F-70 — a backend that cannot type at all [V in the old source] |  |

#### LV · Liveness and escalation

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| LV1 | A healthy long turn is not a stall; no single signal authorises an intervention | `L2-LIV-01` · `C-02` | R1-09 | F-24 — six false nudges; `STALLED` raised 8+ times against healthy sessions |  |
| LV2 | A child alive past a ceiling with an unchanged output stream is `suspect`, not `busy` | `L2-LIV-02` | R1-09 | F-25 — `until grep … sleep 5` on a pattern that could never match |  |
| LV3 | Failures are normalised before counting; three identical fire **once**, three different fire none | `L2-LIV-03` · `K-09` | Д5, R1-09 | F-26 — 33 m 31 s and 184k tokens against a dead daemon |  |
| LV4 | The escalation ladder is ordered, bounded, and has a terminal rung that always reaches the human | `L2-LIV-04` · `C-02` · `V-07` | R1-09, R1-17 | F-28 — observed peak **44,791 s** before a nudge |  |
| LV5 | **Ready work + free capacity + no progress for T ⇒ escalate**, asserted with every detector stubbed healthy | `L2-LIV-05` | R1-09, Д6, Д7 | F-27 (`J-SUP-34`) — 35+ min idle with eight ready tickets | ● |
| LV6 | A machine sleep is detected as `wall_delta − mono_delta`; no lane is judged dead across it | `C-08` `C-11` | R1-09, R1-10 | the previous run ended *"(Mac may sleep)"* |  |
| LV7 | Alive-and-not-ticking is a distinct, reported condition | `C-20` | R1-10, Д11 | F-43 — a recovery component holding politely for 32 minutes |  |

#### DT · Detectors and loops

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| DT1 | A detector never matches its own subject matter quoted in prose | `L2-DET-01` · `C-07` | R1-09 | F-40's root cause, F-63 — four false positives in one day |  |
| DT2 | Corrective action is bounded per (target, trigger) and fixed-point aware | `L2-DET-02` · `V-09` | R1-09 | F-40 — 85 minutes, ended by external `SIGTERM`; a 45-minute second instance |  |
| DT3 | Findings dedupe with a count; an unresolvable finding is said **once**, at first detection; every hold names what would end it | `L2-DET-03` · `V-08` | Д11, R1-17 | F-42 (1,085 over five days), F-43 |  |
| DT4 | No logging helper writes a detector's trigger string into a file a detector reads | `O-43` lint · `MC-26` | R1-09 | F-40 |  |

#### WK · Work intake

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| WK1 | Readiness is a pure function returning a **closed** reason set; a missing section names itself | `RDY-01` | R1-04, Д2 | the ready-floor mutation, caught only by the three executing tests [V] |  |
| WK2 | An unknown status, or two state labels, is never ready | `RDY-02` `RDY-03` | R1-04 | F-50 |  |
| WK3 | Every transition from every reachable predecessor leaves exactly one label, on **both** backends | `RDY-04` · `L2-BRD-02` · `A-05` | R1-04 | F-50 — visible only on `ready → blocked → … → done` |  |
| WK4 | A dependency-blocked ticket never becomes ready | `RDY-05` | R1-05 | the observed throughput constraint was dependencies, not quota |  |
| WK5 | A ticket claimed by a live session is not ready | `RDY-06` | Д10, R1-05 | F-15 adopt-and-duplicate |  |
| WK6 | Readiness is independent of the id, and of a consistent status renaming | `RDY-07` `RDY-08` | R1-04 | F-53 — a branch name computed from a slug |  |
| WK7 | A hostile ticket body is bound as **data**, renders inert, and does not change the verdict | `RDY-09` · `L2-BRD-03` · `C-30` | R1-04, Д2, R1-15 | F-57 — `{{HBIN}}` in a body blocked a spawn; the workaround was logged unsafe |  |
| WK8 | N concurrent claims/adds produce N distinct ids at every rung of the ladder, or refuse | `RDY-10` · `L2-BRD-01` · `C-35` | R1-04, Д2, R1-05 | F-51 / F-49 — **live in this repository today** [V] | ● |
| WK9 | A mid-flight ticket change is silent when nothing changed and named when something did | `L2-BRD-04` · `C-29` · `K-07` | Д8, Д9 | the Д8 failure direction, both ways |  |
| WK10 | Board faults — rate limit, stale read, unreachable for K ticks — do not produce a false claim or a lost claim | `C-27` `C-28` `C-31` | R1-04, Д6 | F-29's shape at the board boundary |  |
| WK11 | Waiting does not block the queue: an independent sibling runs its full lifecycle, a dependent never starts, and an answer written to the channel mid-run is picked up live | `K-10` | Д6, Д7, R1-05 | F-27, F-12; preserves **P-01** (eleven questions routed rather than guessed) |  |

#### BR · Blast radius and teardown

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| BR1 | No destructive command runs with an implicit scope; teardown enumerates by label and aborts whole on an unlabelled target | `L2-RAD-01` · `V-03` · `K-08` | R1-16, Д3 | F-44 — the owner's stack destroyed, **actor never identified** | ● |
| BR2 | Targeting is by recorded pid with a parentage check; no `pkill -f`/`pgrep -f` anywhere in source | `L2-RAD-02` · `LEA-07` · `O-40`/`O-41` lints | R1-16 | F-45 — killed an unrelated lane by its own prompt text | ● |
| BR3 | Orphans from a dead prior run are enumerated and reclaimed **by label alone**; unlabelled is refused | `L2-RAD-03` · `C-36` · `A-11` | Д3, R1-16 | F-48 — ~150 orphaned volume pairs |  |
| BR4 | `started_set` is exactly the journal's spawn records, and `acted_on ⊆ started_set` after every action | `JRN-06` `RES-06` | R1-16, Д3 | F-44, F-45, F-48 — the simple version the owner asked for |  |
| BR5 | A worktree deleted under a running session resolves as `resolved_absent`, not as a failure or a retry | `C-34` | Д4, Д3 | — |  |
| BR6 | A run refuses to report a verdict on a tree that changed under it | `C-37` · `A-13` | R1-05, R1-16 | F-71 — verified by accident during this spike: a contaminated tree gave a confident wrong answer three times [V] |  |
| BR7 | Machine headroom is recorded from `memory_pressure -Q`, not swap occupancy; detection only | `A-12` | R1-05 (deferred) | F-46 — OOM-killed in 31 seconds, found by correlating timestamps afterwards |  |

#### EV · Evidence and bookkeeping

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| EV1 | Every record is written **after** the effect, names an actor, and carries the evidence it observed | `JRN-03` `JRN-04` · `V-01` (gate G1) · `C-06` | R1-06 p2, Д11 | F-07, F-52 — 26 refusal events from one real read | ● |
| EV2 | Concurrent appends do not interleave; an over-long line is **refused**, never truncated | `JRN-01` `JRN-02` | R1-10 | measured corruption above ~3 KB, and 60/60 twice on a broken size [V] |  |
| EV3 | `verify` rejects a malformed or out-of-order journal rather than reconstructing a plausible history | `JRN-05` | R1-06 p2 | [I] |  |
| EV4 ‡ | A merge is a **ref movement**, not an exit code | `V-05` · layer 4 `JG15` | R1-12, R1-13 | F-29 — `Already up to date` on the phase branch against itself |  |
| EV5 ‡ | `declared_total == passed + failed + skipped + not_reached`; zero units is `suspect`; a signal exit is `incomplete` | `V-06` · layer 4 `JG15` | R1-13 | F-32 (346/382), F-33, F-35 |  |
| EV6 ‡ | Every declared step reached a terminal state or is recorded `skipped` with a reason; a self-attributed artefact is flagged non-independent | `V-04` · layer 4 `JG15` | R1-13, R1-03 | F-30 (five phases, builder-only verification, **caught by manual review**), F-31, F-36 |  |
| EV7 | Every declared step **resolves and dry-runs** at preflight, and what it resolved to is recorded | `A-02` | R1-03, R1-17 | F-34 — a check that existed only as prose; F-65 |  |

> **‡ EV4, EV5 and EV6 are the open boundary.** They are written as bookkeeping about the orchestrator's
> own actions and never as a judgement about the user's work, but R1-13 was not put to the owner in
> those terms. See **D1**. If he rejects the distinction, these three rows come out and the design
> accepts that a silently skipped verification stage can ship five tickets again.

#### PL · Platform and adapters

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| PL1 | argv, env and cwd match their golden per (platform × role × mode); every identifier in a spawn descriptor names the **same** unit | `L2-PLT-01` · `A-10` | R1-07, R1-11, I1 | F-54 (session id said phase 5, cwd said phase 4), F-55 |  |
| PL2 | Lane environments are ready and port blocks are disjoint under concurrent allocation | `A-10` | Д4, R1-05 | F-54; preserves **P-04** (two lanes, no collision) |  |
| PL3 | A provider process that dies mid-turn or hangs silently produces a typed result, never `ok` | `C-01` `C-02` | R1-09, Д5 | the council-advisor that hung 40 minutes and never returned |  |

#### OB · Observability, notification, silence

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| OB1 | Silent by default; verbosity changes printing and **never** decisions (byte-identical decision logs) | `L2-OBS-01` | Д11 | the metamorphic relation every other scenario rests on |  |
| OB2 | The channel is round-tripped by nonce before the run, and the notifier is supervised with a second route | `L2-OBS-02` · `A-04` | R1-17 | F-41 — the notifier had exited and was never restarted, during the 85-minute loop |  |
| OB3 | The red-line file's content appears in **the production renderer's output** for every role | `A-09` · layer 4 `JG11` | R1-15 | F-34's class; the H-33 vacuity shape [V] |  |
| OB4 | The morning artifact is rendered from the machine record, never hand-written, and its emptiness is a measurement | L5 §8 | Д11, R1-17 | F-52 — a record that becomes fiction |  |

#### JG · Judgement (layer 4; all replay cases are free, the live-judge arm is paid)

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| JG1 | No false stall on the 617-case auto corpus; heartbeat age may not be the sole basis | `J1-01` `J1-02` | R1-09 | 617 provable false stalls at a 600 s rule [V] |  |
| JG2 | A forged busy signal, a poller and a retry loop are not work (hard set) | `J1-03` `J1-04` `J1-05` | R1-09 | F-25, F-38, F-26 |  |
| JG3 | The verdict vocabulary is total; the backstop does not consult the classifier | `J1-06` `J1-07` | R1-09 | F-27 |  |
| JG4 | Finished is not parked; a busy session is never force-closed | `J1-08` | Д3, R1-09 | F-14, **P-03** |  |
| JG5 | Self-reference is not evidence | `J1-09` | R1-09 | F-40 |  |
| JG6 | Confidence is calibrated; a judge that says 0.95 to everything fails | `J1-10` | R1-14 | the degenerate judge scoring 90.7% [V] |  |
| JG7 | Structure is not readiness; degraded copies are caught | `J2-01` `J2-02` `J2-03` | R1-04 | header-presence scores 0.385 vs a 0.436 baseline [V] |  |
| JG8 | Ticket text is hostile input; tokens are data; no invention; statuses are the board's; dependencies beat structure | `J2-04` `J2-05` `J2-06` `J2-07` `J2-08` | R1-04, Д2 | F-57 |  |
| JG9 | Owner-actions replay (the ASK class), decisions replay (weakly), and the self-corrected set | `J3-01` `J3-02` `J3-08` | R1-14 | `OWNER-ACTIONS.md` is the pre-labelled positive class |  |
| JG10 | The **same** fixture under `controlled` and `autonomous` does not both come back `ACT` | `J3-03` | R1-14, R1-02 | the drift where an autonomous run asks nobody anything |  |
| JG11 | The red line is absolute in **both** modes | `J3-04` | R1-15 | R1-15's one mandatory file |  |
| JG12 | The reason cites a rule, not caution; below the floor it asks; the bars are asymmetric | `J3-05` `J3-06` `J3-07` | R1-14 | killing a healthy lane cost 35 min and four uncommitted files; leaving a runaway cost 85 min |  |
| JG13 | Silence on a no-op; additive is not contradictory; a reversal is; the reaction is configured; and it is graded at the **cheap tier it will run on** | `J4-01`…`J4-05` | Д8, Д9 | the Д8 failure direction |  |
| JG14 | Not mine; the compose case; a pattern is not an identity; teardown is set containment; prior debris is not mine either | `J5-01`…`J5-05` | R1-16, Д3 | F-44 (H-12: the **same action** labelled correctly two minutes earlier), F-45, F-48 |  |
| JG15 | Success text is not success; conservation; a crash is not an empty pass; prose is not a step; `SYNTAX OK` is not applied — **and the `J6` rubric does not grade the work** | `J6-01`…`J6-06` | R1-13 | F-29, F-32, F-33, F-34, F-36; the last is the **negative test** that pins the boundary |  |

#### SD · The suite's own defences

| # | Contract | Ids | Req | Descends from | ● |
|---|---|---|---|---|---|
| SD1 | A committed count floor, `total == pass + fail + skip`, `PASS=/FAIL=` printed on every exit path including abort, and a zero-assertion case is a **failure** | `MET-01` · L2 `EXPECT_SCENARIOS` · L4 gate 4 · L5 `RUNNER-CONTRACT` | — | F-32, and the master runner's silent abort and missing floor [V] |  |
| SD2 | The ban-lint over `core/` — the one legitimate use of grep, because it asserts **absence** | `MET-02` · `O-40`…`O-44` | — | the H-33 mutation: feature deleted, sentence left in a `# TODO`, test green [V] |  |
| SD3 | Self-registration: listed in `marketplace.json` **and** in the `PLUGINS` array | `MET-03` · `M-32` | — | a plugin absent from that array is invisible with no warning; `orchestrator` is absent today [V] |  |
| SD4 | No leakage and idempotence under double invocation | `MET-04` · L2 §7.3(5) | — | `run-all.sh` runs every runner twice [V] |  |
| SD5 | The installed copy matches the source tree, per file | `MET-05` · `A-14` | — | F-49 — still missing from source thirteen days later [V] |  |
| SD6 | At most 15% of cases may use the hand-written escape hatch | `MET-06` | — | the drift that turned a suite into 37 greps |  |
| SD7 | `expect_fired` is checked **before** any assertion; `MC-00` (disable `fp()`) must turn the whole chaos layer red | L3 §2.4 · `MC-00` `MC-00b` · `O-CH-01` | — | a fault that silently stopped firing is the chaos layer's characteristic vacuity |  |
| SD8 | Canaries prove the doubles are live before each group; deleting `enable -n kill` must break the **canary** and not the scenario | L2 §7.3(1) · `M-SIM-canary` | — | `kill` is a builtin and a PATH shim never sees it [V] |  |
| SD9 | The corpus carries a per-group floor and a sha256 digest over sorted case ids | L4 gate 5 · `M-29` `M-30` | — | a fixture edited to make a case pass |  |
| SD10 | Change classification is mechanical, an unmapped path defaults to `safety`, and the required canary class ran with the matching fault | `P-01` `P-02` `P-03` | — | F-21/22/23 — a fix whose own failure mode was never exercised |  |
| SD11 | A failed run files itself: corpus entry, evidence fixture, registered failing stub, repo red | `P-04` | — | F-49, and the meta-failure this whole spike exists to fix |  |

**Coverage check.** 124 contracts over 251 ids: layer 1 88 (CFG 12, CTL 13, STP 9, LEA 11, JRN 6,
RDY 10, THR 12, RES 9, MET 6) · layer 2 46 · layer 3 37 · layer 4 42 scenarios over 1,403 cases ·
layer 5 38 (A 14, K 10, V 10, P 4). Every id above appears exactly once. The twelve invariants of §2
map onto the families as: I-01→LC · I-02→BR · I-03→LC11/CP3/EV2 · I-04→EV · I-05→CQ · I-06→CP ·
I-07→LC12/BR3 · I-08→CQ2/CQ4/CX4/EV5 · I-09→LV/DT3 · I-10→CP4/DT · I-11→LC13/CQ3/EV7/PL/OB2/OB3 ·
I-12→SD.

### 4.2 The twenty that must pass before the first unattended overnight run

Selection rule, applied honestly: a gate earns its place if the failure it guards would (a) destroy
something irreversibly, (b) blind or wedge the whole night, or (c) corrupt the record so badly that the
night could not be diagnosed afterwards. Everything else is a good test and can wait.

| # | Gate | Guards against | Class |
|---|---|---|---|
| 1 | **LC1** exclusive lock under the delay ladder | F-13 — *"нескінченний цикл оркестраторів"* | wedge |
| 2 | **LC2** the loser touches nothing | F-13 + R1-16 | irreversible |
| 3 | **LC3** dead vs `SIGSTOP`ped vs reused pid | F-13 — reclaiming a healthy paused run | wedge |
| 4 | **LC8** classify before claiming | F-15 — adopt-and-duplicate or tear-down-and-lose | lost work |
| 5 | **LC11** crash at every step leaves a legal state | F-21/22/23 | record |
| 6 | **CP1** read-only inbound tick | F-10 — the only brake, silently eaten | wedge |
| 7 | **CP2** an external command survives and acts once | F-10 | wedge |
| 8 | **CP3** atomic writes, no torn read | F-11 — compounded the 85-minute loop | record |
| 9 | **CP5** hash-triggered, applied next tick | F-40 — edge-triggered logic on unchanged input | wedge |
| 10 | **CP10** hard beats soft | Д12 across four requirements, never tested | brake |
| 11 | **CP16** no unattributed stop | F-23 — a run stopped and nothing recorded who or why | record |
| 12 | **CQ3** `401` typed and refused at preflight | F-18 — 82 minutes blind | blind |
| 13 | **CQ4** `UNKNOWN` never `OK`, N unknowns escalate | F-16 — hours blind, across many days | blind |
| 14 | **CQ5** readings labelled by account | F-17 — deciding about the wrong pool | blind |
| 15 | **EV1** no record of an effect without its observed evidence | F-07, F-29, F-36, F-52 — the attempt-reported-as-effect class | record |
| 16 | **CQ7** pause/resume arithmetic across the clock sweep | F-21 — resumed immediately into the wall | wedge |
| 17 | **LV5** the liveness backstop, detectors stubbed healthy | F-27 — 35+ min idle with eight ready tickets | dead night |
| 18 | **WK8** concurrent claim/id allocation | F-51 — **live in the repo today** | lost work |
| 19 | **BR1** no destructive command with an implicit scope | F-44 — the owner's stack, actor unknown | irreversible |
| 20 | **BR2** no `pkill -f`; targeting by pid + parentage | F-45 — killed an unrelated lane | irreversible |

**EV1 is in the twenty for a second reason as well.** It is not only the defence against the largest
failure class; it is the **contract that makes the other nineteen checkable after the fact**. Without
it a failed night produces a diary rather than a record, nothing in §7's feedback loop can run, and the
first real night teaches nothing.

**Four things that are prerequisites, not gates.** They must exist before the first of the twenty is
written, and counting them as gates would flatter the list: **SD1** (the runner contract — without it a
suite that loses tests reports green), **SD2** (the ban-lints — they must land *before there is code to
violate them*), **SD3** (registration — `orchestrator` is not in `PLUGINS` today, so this fails before
it passes), and the free **preflight suite A-01…A-09**, which gates *the run* every night rather than
gating *the plan*.

**Five that nearly made the twenty, and why they did not.** `LV4` terminal escalation rung — a dead
night is bad, a destroyed stack is worse, and `LV5` already guarantees the night does not silently stop
mattering. `DV6`/`DV7` delivery receipt — architecture-conditional on decision **D3**; if the interactive lane
ships, `DV6` displaces `LV4` immediately. `LC13` `env -i` — the component it most protects (the doctor) is
off by default on night one, which `BUILD-PLAN` itself calls the plan's worst default. `SD5` installed-
copy drift — free, and it belongs in the runner rather than on the gate list. `CX3` compaction post-
condition — the headless architecture changes what compaction even is, so it waits on the same
decision as the DV family. And `CQ6`, the phantom-headroom event on an account switch, which sat in the
twenty until `EV1` displaced it: its failure manufactures a wrong signal rather than losing the night,
and it only bites with two or more accounts in play, which night one need not have. **If night one runs
two accounts, put `CQ6` back and drop `CQ1`.**

---

## 5. Build order

### 5.1 The rule the order obeys

**Nothing is built before the thing it is proven against, and the earliest implementation work is
already covered.** `BUILD-PLAN` §4 sequences the product in eight milestones and already names eval
scenarios per milestone. This plan does not invent a second order; it says which assertions land in
which milestone, and which parts of the stack can wait.

The order also obeys a second rule that is not obvious: **the four seams come first and they are
architecture, not test code.** Every layer document says the same thing independently, and it is the
only claim in this plan that is unbuyable later.

| Seam | What it is | Without it |
|---|---|---|
| `decide(world) → plan` / `apply(plan)` | the tick decides in a pure function and acts somewhere else | every L1 case needs a process; 10,000 world states become 10,000 runs |
| `now()` via one clock module, honouring an env override | no module calls `date`, `$SECONDS` or `time.time()` | `faketime` is **not installed** and has no clean path on modern macOS [V]; every timing test pays real seconds |
| `resolve_bin <name>` | every external binary resolves through one function | a shim only intercepts what resolves through `PATH`; hardcoded paths escape silently |
| `judge(kind, evidence, policy)` over **batched** JSONL | one function, one replaceable command | per-case subprocesses cost 50.9 s where batching costs 0.07 s [V] — a 460× penalty that turns L4-A from a gate into a skip |

Plus two contracts that are the same kind of decision: the **LEDGER-CONTRACT** (§2 I-04) and the
six-line `fp()` fault point (§3 L3), the second of which is a genuine trade the owner should see rather
than discover — an execution path in the shipped supervisor that an environment variable enables, at
10.5 µs per call when disabled [V], with a preflight refusal so it can never be live in a real run
(**D2**).

### 5.2 The cheapest possible day-one version

**Half a day, ~200 lines, and it catches a live bug.** This is the smallest thing that is worth having,
and it is worth building even if the rest of this plan is never built.

1. `plugins/orchestrator/tests/run.sh` with the **runner contract** and nothing else in it: an `EXIT`
   trap that prints `PASS=<n> FAIL=<m>` on every path including abort; a committed `EXPECTED-COUNT`
   floor; the conservation identity `total == pass + fail + skip`; a failure line that names the case,
   the assertion and a unified diff of normalised expected vs actual; the tmpdir **kept** on failure
   and its path printed; and a case that executes zero assertions counted as a **failure**.
2. `lib/assert.bash` with three helpers: `with_project()` (a whole fake project in a `mktemp -d`),
   `with_clock()` (`ORCH_NOW`), `with_procs()` (`ORCH_PROC_PROBE`).
3. **One case: WK8.** N concurrent ticket adds must produce N distinct ids, at 2, 20 and 50, across a
   `0 / 1 ms / 5 ms / 20 ms` delay ladder, three rounds each.
4. `run-mutations.sh` with **one** mutation — remove the id-allocation lock — and the discipline that
   makes it honest: `cp -R` to a scratch directory (**never** `git checkout`, the tree may hold
   uncommitted work), a `python3` patcher that **asserts its anchor matched**, `bash -n` on the mutant,
   `run.sh --only <ids>`, restore, confirm with `git diff --stat`.

**Why this one case.** It fails against the source as it stands today: `l_add()` in
`plugins/harness/bin/harness-tickets.sh` allocates ids with an unlocked read-then-write, `grep -nE
'lock|flock|LOCK'` over that file returns only the word `blocked`, and the documented fix landed only
in the installed copy and is **still missing from the repository thirteen days later** [V]. Historical
rates: two concurrent adds produced two files under one id in **five rounds of five**; a twenty-way add
produced twenty files under three ids [C].

So the day-one harness demonstrates, in one command, all four things the whole plan claims: that a test
can fail for the reason it names; that the failure is legible; that the mutation gate works; and that
the old suite's 51 green tests were not evidence. **A test that fails before it passes is the cheapest
possible proof that the machinery is real.**

### 5.3 The staged order, mapped to the product milestones

| Milestone | Product (from `BUILD-PLAN` §4) | Eval landing with it | Cumulative gate cost |
|---|---|---|---|
| **M0** reconciliation, no code | glossary, one transitions table, one defaults register, the exit table, ratification | **nothing** — this is paper, and the cheapest day in the plan | — |
| **M1** the floor: lock, config, journal, clock, status | the scaffold, `PLUGINS` registration, **both ban-lints before there is code to violate them** | day-one harness (§5.2) · **SD1 SD2 SD3 SD4** · **LC1 LC2 LC3 LC7** · **CP1 CP2 CP3 CP17…CP21** · **EV2 EV3** · **LC13** · **SD5** | ~10 s |
| **M2** the queue and the meter | readiness, capacity, the scheduler as pure functions | **WK1…WK6 WK8** · **CQ1…CQ9** · **LC11** (the pause path's crash points) · **WK7** | ~20 s |
| **M3** adapter, preflight, honest refusal | adapters, preflight, the requirements table, `plan.json` | **EV7** · **PL1 PL2** · **DV7** config arm · **OB2 OB3** · preflight `A-01…A-10` · **SD7** wiring (`fp()` + `points.tsv` + `O-CH-01`) | ~35 s + preflight |
| **M4** the lane, the probe, no `ok` without evidence | lane, claim/dispatch, probes, `ops.json` | **EV1 EV4 EV5 EV6** ‡ · **BR4** · **LC8 LC9 LC10 LC12** · **PL3** · layer 2 groups F, G | ~60 s |
| **M5** the control plane, the clean stop, the first unattended night | `orc-ctl.sh`, the three stop verbs, the teardown walker | **CP4…CP16** in full · **BR1 BR2 BR3 BR5** · **OB1** · **WK9 WK10** · layer 3 groups D, E, F at the `gate` profile | ~2 min |
| **M6** judgement, the watchdog, the first real night | the judge, the fact sheet, the report, the doctor | **LV1…LV7** · **DT1…DT4** · **CX1…CX5** · **L4-A** in full · layer 5 audit + `V-01…V-10` + `render.sh` + **SD11** ingest | ~2.5 min free + L4-B tagged |
| **M7** the second platform, the provider lane | `adapters/codex/`, a provider lane | **PL1** expanded to the full matrix · **DV7** per adapter · **CQ8** per scheme · **SD10** promotion classes | ~3 min |

**The twenty night-one gates are complete at the end of M5.** That is the intended reading of the
table: M1–M5 is exactly the work that makes a first unattended overnight run defensible, and M6's
judgement layer is what makes the *second* night better than the first.

### 5.4 What can wait, and what it costs to wait

| Deferred | Until | What waiting costs |
|---|---|---|
| **L4-B** (the paid arm) | a prompt exists that is worth regression-testing | Prompt regressions are caught as a *consequence* on the run that suffers them (`V-04`), not before. That is how five phases shipped with builder-only verification [C] |
| **L3 `full` and `crash` profiles** | pre-release | The `gate` profile is 37 scenarios at one repetition; the wider sweeps find the races the gate's single rung misses |
| **The canary C2** | the first promotion of a `safety`-class change | Every change ships on L1–L4 evidence alone, which is real evidence about the world the doubles model and no evidence about the real one |
| **The `soak` profile** | ever, honestly | Accumulation over 34 hours is invisible to every layer here. The first real long night is the test |
| **Cross-vendor judgement comparison** | a second adapter exists (M7) | `claude plugin eval` cannot test Codex/GLM/Gemini. That is a second tool and a new dependency the owner has a standing position against (R1-18) |
| **DV1…DV5** (the delivery family) | **D3** is settled | If the interactive lane ever ships without them, the largest failure family in the record reopens with no coverage at all |

### 5.5 What the eval stack costs to build

Stated because the honest number is uncomfortable. L1 ~6 days (seams 1, runner 1, 88 cases 4) · L2
~6.5 days · L3 ~7.5–9.5 days · L4 ~1 day to the five assertions that matter, ~3 to the whole thing ·
L5 ~4–6 days. **≈ 25–30 engineer-days for the full stack**, against `BUILD-PLAN`'s ~23.5 days for the
product to M6. Two things follow, and both are in §5.3 already: the stack is **staged with the
product**, never built as a block; and the estimates should be read as ratios, since a sibling warns
its own numbers may be uniformly low because the previous generation was *smaller* than three of the
four candidate designs while being demonstrably insufficient (1,879 lines of bash) [V].

---

## 6. How this plugs into the repo

### 6.1 Fix the master runner first, in the same PR as the first test file

Three measured defects in `tests/run-all.sh`, all reproduced in a scratch copy [V]:

1. **Silent abort.** Lines 41 and 50 call `set -e` believing they restore a flag that was never on.
   With `pipefail` already active, `grep -oE "PASS=[0-9]+"` on a runner that printed no `PASS=` line
   exits 1, propagates, and kills the master script. Reproduced: exit 1, **no message, no summary, no
   named plugin, and the next plugin never ran.** `harness` is 8th of 10; a silent death at position 1
   skips it entirely.
2. **No floor.** A runner printing `PASS=1 FAIL=0` is accepted and aggregated. Nothing compares against
   a baseline or a per-plugin minimum. This is F-32 reproduced inside the test harness itself.
3. **Double execution.** Every runner runs twice to re-scrape counts. Harmless for greps; for a
   stateful suite that creates tmux sessions, lock files, git repos and pid files it is a 2× cost
   multiplier **and** a correctness requirement, and a test that leaks would fail on the second pass
   and be blamed on flakiness.

The fix is a handful of lines: capture each runner's output **once** and parse the counts from that
capture; drop the two `set -e` lines; read a per-plugin minimum from a committed file and fail below
it; name the plugin before running it and print its outcome after. It must land **before** a stateful
64-second suite goes behind it, or the new plugin can take the whole aggregate down without a word.

### 6.2 Registration — five points, two of them asserted by the plugin on itself

`orchestrator` is **not** in the `PLUGINS` array today [V], so `N3` fails before it passes. The five
points, from `CONTRIBUTING.md` and observed in-tree: `plugins/orchestrator/.claude-plugin/plugin.json`
(semver, `0.x` + `(beta)` prefix while beta) · one entry in `.claude-plugin/marketplace.json` · README,
CHANGELOG, LICENSE in the plugin dir · `plugins/orchestrator/tests/run.sh` **and** the name in
`PLUGINS=(...)` · a row in the root README's plugins table. The plugin asserts the second and fourth on
itself (`MET-03`), because those two lines are the only defence against it silently dropping out of
coverage.

### 6.3 Entry points, and what each one gates

| Entry point | Contents | Cost | Runs |
|---|---|---|---|
| `plugins/orchestrator/tests/run.sh` | L0 static + L1 (88) + L2 (46, `-j 4`) + L3 `--profile gate` (37) + L4-A (1,403 cases) | **~2 min serial, ~1 min parallel, $0** | every commit, inside `bash tests/run-all.sh` |
| `plugins/orchestrator/tests/run.sh --env-i` | the same suite under a scrubbed environment | +~64 s, $0 | pre-PR |
| `plugins/orchestrator/tests/mutations.sh` | 157 mutations, each running only its named ids | **~7 min, $0** | pre-PR, and on any change to a mutated contract |
| `plugins/orchestrator/tests/chaos/run.sh --profile full,crash` | the wider fault sweeps | 5–9 min, $0 | pre-release |
| `plugins/orchestrator/tests/real.sh` | real tmux, real git worktrees, real docker, CLI conformance | 5–15 min, $0 | pre-release, manual |
| `claude plugin eval plugins/orchestrator --tag judgement …` | L4-B smoke / full / hard | $0.85 / $8.60 / $14 | prompt change / PR / release |
| `orchestrator:preflight` | `A-01…A-14` | 20–40 s, $0 | **before every real run** — it gates the run, not the repo |
| `orchestrator:audit` + `render.sh` | `V-01…V-10`, the morning artifact | 10–25 s, $0 | **after every real run, forever** |
| `orchestrator:canary --profile C1\|C2` | preflight + rehearsal + a real bounded run + audit | 35 min / ~4 h; ~0.1–1% of a weekly window | promotion only |

**The load-bearing property of this table is the first row: the commit gate is under two minutes and
costs nothing.** The repo's existing 475-assertion suite takes 42.15 s at zero cost, and that is why it
gets run [V]. Any version of this plan that puts a paid call, or five minutes, in front of a commit
will be `--skip`ped within a fortnight, and an unrun suite is worth less than no suite.

### 6.4 CI versus local — and the honest problem with CI here

**There is no CI.** `.github/workflows` does not exist [V]; the suite runs when a human types
`bash tests/run-all.sh`. For an unattended orchestrator that regresses at 03:00, that is material.

The complication is that **a Linux runner would test a different machine than the one that runs the
orchestrator**, and this plan's own evidence says the difference is where the bugs are: `find` resolves
to `bfs 4.1.1` interactively and `/usr/bin/find` under `env -i`, with incompatible flags; `/tmp` is a
symlink `find` will not descend; `date` is BSD (`-v` works, `-d` fails); `flock` is absent and `shlock`
present; `memory_pressure` is the right meter and swap occupancy is not; `/bin/bash` is **3.2.57** [all
V]. A green Linux CI would prove the suite passes somewhere nobody runs.

Three options, ranked:

1. **A macOS-runner workflow for L0 + L1 + L4-A only** — free, offline, no secrets, ~25 s. It cannot run
   L2/L3 faithfully (tmux servers, process tables, a private tmux server per scenario) but it catches
   the single most common regression: someone pushes and the deterministic core is red.
2. **A local pre-push hook** running the same three layers, plus the mutation gate on any file named in
   a `.mut` target. Zero infrastructure, zero cost, and it runs on the machine that matters.
3. **Both**, with the hook as the real gate and CI as the second pair of eyes.

**Recommendation: (2) now, (1) when the plugin is public enough that someone else pushes to it.** This
is **D13**; the deciding fact is whether anyone but the owner will ever open a PR against this plugin.

### 6.5 How model-dependent evals stay optional

Four mechanisms, and the first is the one that matters:

1. **L4-A is model-free and carries most of the contract.** *Given a verdict, does the orchestrator do
   the right thing with it* — a confidence that gates nothing, a `SOFT_STOP` that stops a running task,
   a mode setting that changes nothing — is deterministic and sits below the API line. So the paid arm
   can be skipped for a month without the judgement layer going dark.
2. **Never in `run-all.sh`.** L4-B is a separate command with a `--tag`, and `run-all.sh` never invokes
   `claude plugin eval`. The defaults alone justify this: `runs: 3 × ablation 2 arms` = **six real
   agent sessions per case** on the operator's own credential, sharing one rate limit with the
   operator's actual work; a 20-case suite is 120 sessions per invocation [V].
3. **`--max-cost-usd` lives in the committed command, never in someone's shell history.** The ceiling
   is checked *before each run launches*, so an overrun is bounded to the runs in flight, and exit 2
   carries partial results. For a tool whose entire subject matter is runaway spend, the ceiling is
   part of the command.
4. **Free graders carry the load.** Four of the six grader types — `regex`, `tool_used`, `tool_order`,
   `file_exists` — cost nothing beyond the agent run. Of ~60 grader lines across the L4-B cases, **12
   are `llm`**, and only where a rubric genuinely needs judgement. The suite is cheap by construction,
   not by cutting coverage.

One committed convention on top: `--judge-model sonnet`, because the default judge is `haiku` and the
tool's own authoring guide says not to use a small judge and not the agent's own model family
(self-preference), and the upgrade costs ~$0.006 per run — ~1.4% of the tier [V]. There is no budget
argument for a weak judge.

---

## 7. Feedback loop

### 7.1 The failure this loop exists to prevent

Not a wrong answer. **A run that failed, was understood, and left nothing behind that could fail
again.** The record has it twice over: a ticket-id locking fix that was documented as landed, applied
to the installed copy, and is still missing from the source thirteen days later [V]; and a whole
subsystem whose commit gates were found broken *by mutation rather than by failing*, a lesson that was
learned in one place and never generalised [C].

### 7.2 A failed run files itself

`orchestrator:audit` on any verdict other than `CLEAN` invokes `corpus/ingest.sh`. Per divergence:

1. **Signature.** `sha256(kind ∥ component ∥ evidence_source ∥ failure_class)` over **normalised**
   text — timestamps, ids, pids, paths and durations stripped. The normalisation is **the same
   function Д5 needs** (three failures differing only in a timestamp must be recognised as identical),
   so it is written once and tested once, in `LV3`.
2. **Known signature** → increment `occurrences`, append the run id. At `occurrences ≥ 2`, mark the
   entry's existing regression test **`INSUFFICIENT`** and surface it in section 1 of every morning
   artifact. *A test exists and the bug recurred, therefore the test is vacuous.* This is the house
   mutation rule run backwards, and it is the mechanism that stops a grep-shaped test standing in for
   coverage a second time.
3. **New signature** → write three things: `corpus/entries/F-<n>.md` from the corpus's own template
   (precondition · trigger · wrong behaviour · assertion · substrate · **mutation** · catches), with
   everything except `assertion` and `mutation` pre-filled from captured evidence;
   `corpus/fixtures/F-<n>/` holding the primary-evidence bundle (transcript slice, screen capture,
   ledger slice, the raw usage body redacted, git state, the argv recorder's log, the fault daemon's
   log slice); and `tests/regressions/F-<n>.sh` — a **registered, failing stub** whose failure message
   names the file to complete and the fixture to assert against.
4. **The repository goes red.** `bash tests/run-all.sh` fails until a human or an agent writes the
   assertion. **Discharge requires the assertion *and* its mutation to have been observed red.**

**Redact at capture time, never at commit time.** Transcript-derived fixtures are exactly where
credentials reach git: two local role passwords were printed in clear text into a session transcript by
Playwright's own `--trace on`, inside the working directory, by a permitted tool, following every rule,
and **no automated secret scan covered tool output or transcripts** [C]. The ingester runs the
credential scanner over every captured artefact before writing it and quarantines rather than commits
on a hit. This repository's own CLAUDE.md already requires a credential check before staging; screen
captures and transcripts are a new artefact class that rule does not cover.

### 7.3 The one product decision that makes the corpus grow instead of age

**The orchestrator writes every live judgement to a JSONL decision log in the graded envelope, with its
raw evidence bundle attached.** Then every run auto-generates the next golden dataset, adjudicated by
what happened afterwards.

This is not speculative; it is a measurement. The previous generation produced a free labelled dataset
**by accident**, because one watcher happened to write parseable structured lines: 617 provably false
stalls and 1,329 total cases, extracted in **0.23 s for $0** [V]. And the same measurement contains the
warning: the two large runs' `context-watch.log` files use **incompatible formats**, and the extractor
built for one yields **zero rows** on the other [V]. The corpus was free because of an accident that
did not happen twice. Make the log a schema and the accident becomes a property.

It is the cheapest line item in the whole rebuild and it has the longest compounding payoff.

### 7.4 Six mechanisms that keep the corpus from rotting

| # | Mechanism | The rot it prevents |
|---|---|---|
| 1 | **Fixtures are frozen files in the repo, never reads of a live run directory** | A golden set that reads the live directory changes under you and its scores stop being comparable between two runs of the suite. One of the source run directories was **still being written to during the spike** [V] |
| 2 | **A per-group count floor and a sha256 digest over sorted case ids** | A fixture edited or deleted to make a case pass. `M-29`/`M-30` must turn the **digest** gate red, not the score |
| 3 | **A held-out run**, never built against | Prompts get tuned to what you can see; the held-out set is the only thing that says whether the tuning generalised. This design holds out the **larger** run (336 sessions, 465 decisions), which is the honest choice and the expensive one (**D6**) |
| 4 | **A scheduled, opt-in, non-blocking re-record job** against the live APIs, failing loudly on a schema diff | A cassette that never re-records is a test of what the API *used to* do. This is the only tier allowed to touch the network, it never gates a commit, and it is what turns the unresolved `.limits[]` vs `five_hour.utilization` divergence from a mystery into an alert (**D11**) |
| 5 | **The `INSUFFICIENT` rule** (§7.2 step 2) | A test that exists, runs, asserts, and asserts the wrong thing. The recurrence is the evidence |
| 6 | **Add the fixture before the fix**, and re-run the whole case set on **every prompt edit** | A documented fix going missing from the code. The only thing that notices is a case that fails when it is absent |

And one habit that is not a mechanism but decides whether any of them get used: **never let a new
suite go all-green quietly.** Three judgement cases written in this spike scored 1.00 across fifteen
runs on first authoring, cost $1.08, and taught nothing [V]. A suite that scores perfectly on the day
it is written is not a passing suite; it is an unwritten one.

---

## 8. What this plan does not cover

Ranked by how likely each is to produce a false green.

1. **Fidelity: the doubles are not the things, and the gap has inverted a verdict twice, measured from
   two directions.** A `read`-loop fake agent submits text stranded on its input line and real Claude
   Code does not [V]; and the 1024-byte silent send ceiling is a property of the *stub's line
   discipline*, not of the terminal — a raw-mode stub delivers 16,000 bytes byte-exact where a
   canonical-mode stub drops 1,024 silently [V]. Every scenario that touches a session, a platform CLI
   or delivery is **protocol-true and behaviour-blind**. The only answer is a small real-CLI
   conformance tier whose whole job is to check that the fakes still match reality on the handful of
   behaviours the fakes assert, and it is the one place money is unavoidable.

2. **Concurrency is sampled, not proved.** A categorically broken check-then-write lock passed **five
   rounds of 100 concurrent acquirers** at zero injected delay and only failed as the window widened
   [V]; a second probe leaked 8 winners at delay 0 on the same primitive [V]; concurrent appends scored
   **60/60 twice at a payload size that is demonstrably broken** [V]. The delay ladders mitigate. A
   race narrower than the smallest injected delay, or at a window nobody thought to place, is
   invisible, and the stronger instruments — a deterministic hypervisor, a model checker — are out of
   scope for a single-operator Mac.

3. **Five physical realities that cannot be produced here.** Real `ENOSPC` (`mount` fails without
   privileges [V]), so short writes that return success and `fsync` failing after `write` succeeded are
   unexercised. **Which clock freezes across a real machine sleep** — the sources exist and are
   readable, but if production picks wrong, *every sleep/wake scenario passes and the bug ships*.
   Socket-level network faults (half-open TCP, DNS resolving after 30 s, a TLS handshake that hangs, a
   body that stalls mid-stream), so "no timeout on a socket read" is invisible. A genuinely same-second
   recycled PID. And memory pressure / OOM, which R1-05 defers anyway.

4. **Accumulation over a real long run.** Virtual time is why L2 and L3 are affordable and exactly why
   they cannot see: file-descriptor leaks over 3,000 ticks, a journal outgrowing what the fold can
   read, a log filling a disk over 34 hours, a tmux server dying when its last pane closes, context
   filling because a lane spent 3,466 of 3,626 Bash calls on `echo idle`. The observed peaks that
   mattered were **12.4 hours** before an escalation and a condition re-flagged **1,085 times over five
   days** [C]; a four-hour canary is structurally blind to both. The honest answer is the permanent
   audit on real runs, not a longer canary.

5. **The quality of the work, deliberately — and the boundary is open.** R1-13 puts verification inside
   the configured process and the owner heard the evidence and did not change his answer. `EV4`/`EV5`/`EV6`
   sit on that boundary as bookkeeping about the orchestrator's own actions, and the distinction was
   never put to him in those terms (**D1**).

6. **Every platform except Claude Code.** R1-07 names Codex, GLM, Gemini, Kimi and ChatGPT and
   instruction I1 requires per-platform feasibility checks. **No adapter other than Claude Code has any
   evidence behind it**, the entire delivery family is a property of driving a terminal, and headless
   may retire that family entirely and introduce a different one nobody has data for. This plan
   provides the *shape* — one `deliver` property table run per adapter, one capability matrix, one
   quota sum type with a `NotApplicable` arm — and none of the evidence. **It is the largest unknown in
   the design.**

7. **Non-code runs.** N2 is explicit that the orchestrator may run where there is no repository, no
   build and no tests. Roughly a third of the failure corpus assumes git or a test runner; the
   throughput baseline (0.38 landed/h) does not transfer; and there is **no evidence at all** about a
   non-code run. `C1-nocode` and the declared-`n/a` rule keep a green result from *implying* coverage,
   which is the best this plan can do. The first non-code run is unguarded and saying so is the point.

8. **Board backends beyond GitHub labels and local files.** ClickUp is named in R1-04 and has no record
   and no stub, and is a known problem even later: no free "did anything change" check and no
   description-change field, against a 100-req/min budget [V, platform research].

9. **GUI terminal backends.** Terminal.app and iTerm2 need a real windowing session; L2 covers tmux and
   headless only. The one recorded backend that **cannot type at all** is a GUI backend [V in the old
   source], so this gap sits directly over a known failure.

10. **A primary source that itself lies.** The audit's independence is real — the auditor shares no code
    with the runtime and every probe reads something the runtime does not write — but a board API
    returning a stale read, a transcript missing a turn, or a hook that silently did not fire defeats it
    invisibly. Where two independent sources exist the probes are cross-checked; where one exists the
    identity is marked `single-witness` and is **not** treated as confirmation.

11. **Prompt regressions, before the run that suffers them.** The mechanism by which five phases shipped
    with builder-only verification was an orchestrator generalising a narrow warning into "every GSD
    agent" [C]. `EV6` catches the consequence on the night it happens. Catching the cause needs L4-B
    against the twelve hard fixtures, which is exactly the tier that costs money and is optional.

12. **Machine-resource awareness**, deferred by the owner's explicit retraction (R1-05). Recorded as a
    **visible waiver** with a detection-only obligation (`BR7`), not as silence, because the last time
    such a risk was implicit the owner's own container was OOM-killed in 31 seconds and nobody noticed
    for half an hour.

13. **Two machines.** `host` and `boot` fields exist so a state directory on a synced volume cannot be
    misread. Everything here runs on one machine; that guard is untested.

14. **Secrets in the artefacts the orchestrator produces.** §7.2 redacts at capture time inside the
    ingester. Nothing in this plan scans a *live* run's transcripts, screen captures and tool output,
    and that is how two passwords reached a transcript last time — inside the working directory, by a
    permitted tool, following every rule.

15. **Whether the requirements are the right ones.** This plan tests ANALYSIS-01 precisely, and
    ANALYSIS-01 contains an **UNRATIFIED** item the whole control plane rests on (Д12, the session ended
    before confirmation), an **OPEN** sub-part the readiness family rests on (R1-04's structure, *"це
    треба буде, щоби придумав якусь структуру"*), and two items the owner deferred to a later analysis
    (R1-14's definitions of controlled and autonomous; R1-16's boundary options). Testing an unratified
    requirement precisely is not the same as testing the right requirement, and no amount of mutation
    coverage closes that gap.

16. **The plan's own cost.** ≈ 25–30 engineer-days for the full stack against ≈ 23.5 for the product to
    M6 (§5.5). Staging it with the milestones is the mitigation; it is not a refutation.

---

## 9. Open decisions

Each is marked **OPEN**, with what would settle it. Three of them (**D1**, **D3**, **D12**) block work
that is otherwise ready to start.

**D1 · The Family-6 boundary — does the orchestrator check its own bookkeeping?** · **blocking**
`EV4` (a merge is a ref movement), `EV5` (result conservation) and `EV6` (step coverage) are written as
bookkeeping about the orchestrator's **own** actions and never as a judgement about the work. R1-13 was
settled the other way, and the evidence behind the question was explained to the owner and did not
change his answer. But the distinction — *checks on the work* versus *checks on whether the step I was
configured to run actually ran* — was never put to him in those terms.
**Settled by:** one question in round 2, phrased as the distinction rather than as the evidence. If he
rejects it, `EV4`/`EV5`/`EV6`, `V-04`/`V-05`/`V-06` and layer 4's `JG15` come out, and the design accepts that a
silently skipped verification stage can ship five tickets again.

**D2 · Is `fp()` in production source acceptable?**
The chaos layer's precision depends on a six-line fault point shipped in `orclib.sh`, because bash 3.2
offers no portable interposition. Cost: 10.5 µs per call when disabled [V], plus a preflight refusal so
it can never be live in a real run. It is an execution path in the shipped supervisor that an
environment variable enables, and the owner should see that rather than discover it.
**Settled by:** the owner's yes/no. A no costs C-12's crash-at-a-chosen-instant precision and leaves
only the external faults — roughly a third of the layer's value.

**D3 · Does the interactive lane exist, and therefore does the delivery family?** · **blocking**
`BUILD-PLAN` §1.1 chose *liveness is a process, not a screen*, which deletes typing into running
sessions and retires six FIELD-NOTES records by removing the capability that produced them. L2's group
A, layer 5's `A-07`/`K-03` and §4's rows DV1–DV5 are all written for an architecture that types. They are the
largest failure family in the record and they are either **retired by deletion** or **the single most
important group to build**, depending on one decision.
**Settled by:** confirming headless-first as an ADR, and then either (a) deleting DV1–DV5 and rewriting
DV6/DV7 around the event stream and the lane's exit, or (b) scheduling round-2 item B2 (the attached
lane) and building DV1–DV5 before it ships. Doing neither is the expensive outcome.

**D4 · May the L4 corpus live in this repository?**
1.3 MB derived from another project's run directories, including ticket bodies and owner-action
records, in a public plugin marketplace repo. `redact.sh` handles credentials; it does not handle
provenance.
**Settled by:** the owner's call between committing it, a private fixtures repo, or a synthesised
corpus that loses exactly the realism that makes it worth having.

**D5 · The recall floors and the calibration gate are policy, not arithmetic.**
`ASK ≥ 0.90` says one escalation in ten may be missed; `NEEDS_HUMAN ≥ 0.60` says four in ten may be.
Both numbers were chosen to be passable by an 88%-accurate judge [V]. Separately: the calibration gate
currently fails a judge that says 0.8 and is right 99% of the time — over-confidence is clearly a
defect, under-confidence mostly costs unnecessary escalations.
**Settled by:** the owner setting the floors (they encode how much unattended risk he wants) and saying
whether under-confidence gates or only reports.

**D6 · Which run is held out?**
The design holds out the **larger** of the two (336 sessions, 465 decisions), which is honest and
expensive.
**Settled by:** confirm, or invert.

**D7 · Does the chaos gate profile run on every commit?**
~45 s, which before the `run-all.sh` fix means ~90 s and a tripling of the repo's suite time.
**Settled by:** fixing the double execution first (§6.1), then deciding. Recommendation: yes, on every
commit, after the fix.

**D8 · Is the LEDGER-CONTRACT acceptable as an architectural constraint?**
Everything in L5 rests on it — no record may claim an effect without naming a primary source the
orchestrator does not write. It costs nothing at write time and cannot be retrofitted cheaply.
**Settled by:** the owner's yes. A no reduces L5 to reading the orchestrator's own diary.

**D9 · How long is C2, and does the canary get its own account?**
Four hours is a guess balanced against ~1% of a weekly window; the failures that hurt most clustered
after hour 8. And R1-07 already allows restricting a provider/account to named roles, so a promotion
pass need not compete with the owner's own work for one rate limit.
**Settled by:** a separate account, if the user configures one (which is also what the doctor needs, and
`BUILD-PLAN` calls its absence the plan's worst default), and picking a horizon.

**D10 · Corpus debt: hard red or acknowledged red?**
§7.2 leaves `run-all.sh` failing until the assertion is written, with a one-line acknowledgement that
then prints in every morning artifact until discharged. Softer than a hard block, harder than a TODO.
**Settled by:** the owner's preference, and it is reversible either way.

**D11 · Which quota schema is live?**
The shipped parser wants `.limits[].group/.percent`; the owner's own global `CLAUDE.md` documents
`five_hour.utilization`; fed the documented shape the shipped parser returns `UNKNOWN`; and the live
endpoint returned HTTP 401 `authentication_error` from this machine, so neither could be confirmed [V].
If the parser is stale, the quota gate has been failing closed — safe, but blind — and R1-06's
thresholds have **never actually fired on real data**.
**Settled by:** one authenticated call with a fresh token, recorded as the first cassette, plus the
re-record job of §7.4(4).

**D12 · Who fixes `tests/run-all.sh`, and when?** · **blocking**
Silent abort, no floor, double execution — all measured [V]. A stateful 64-second suite behind the
silent-abort bug is a trap, and the fix is a handful of lines.
**Settled by:** landing it in the same PR as the orchestrator's first test file, which is the
recommendation, or as a standalone PR first. It must not land *after*.

**D13 · CI, and on what runner?**
No `.github/workflows` exists. A Linux runner would test a different machine than the one that runs the
orchestrator, and this plan's evidence says the difference is where the bugs are (§6.4).
**Settled by:** whether anyone but the owner will ever open a PR against this plugin. If no —
a local pre-push hook is enough. If yes — a macOS-runner workflow for L0 + L1 + L4-A.

---

## 10. The sentence to keep

A sibling judge asked for one sentence to be kept verbatim in `docs/DESIGN.md`, and it applies to this
document before it applies to anything else:

> **Until those tests exist and are verified by mutation, this architecture is a claim, not a
> property.**

The same is true of `MC-00`: until someone disables `fp()` and watches the chaos layer go red, that
layer is a claim too. And of the day-one harness: until `WK8` has been seen to fail against the source
as it stands today, every number in this plan is an argument rather than a measurement.

**The first thing to do is the ten-minute one.** Write the concurrent-id test, run it against
`plugins/harness/bin/harness-tickets.sh`, and watch it fail.
