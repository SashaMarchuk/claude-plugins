# JUDGE-survival — how each design behaves on a bad night

**Date:** 2026-09-19. **Axis:** survival. **Method:** walk each of the four designs through the real
failure corpus in `plugins/harness/docs/FIELD-NOTES.md` and score by how many failures it
**structurally prevents** versus how many it **merely discourages**.

**Inputs read in full:** `ARCH-minimal.md`, `ARCH-reliability.md`, `ARCH-adapters.md`,
`ARCH-operability.md`, `plugins/harness/docs/FIELD-NOTES.md`. Supporting claims traced back to
`round-1/ANALYSIS-01.md`, `research/platforms/ADAPTER-CONTRACT.md`, `research/LANDSCAPE.md`,
`research/adoption/ADOPTION-VERDICT.md`.

**Evidence tags.** **VERIFIED** — read in one of the documents named above, or measured by a document
cited there. **CLAIMED** — a design asserts a mechanism will work and nothing was executed behind it.
**INFERRED** — my reasoning from the above. Every design's own mechanisms are, at this stage,
**CLAIMED** by construction: none of the four has been built. What is VERIFIED is the failure record
they are being scored against, and the platform facts each cites.

---

## 0. The scale, stated before it is used

The brief asks for *structurally prevents* versus *merely discourages*, and the distinction only
works if it is sharp. Four levels:

| Level | Definition | Test |
|---|---|---|
| **STRUCTURAL** | The failure is unreachable, because the capability that produced it does not exist in the design, or because a single code path that every instance must pass through refuses it. | Reopening it requires changing code, not configuration. |
| **DEFAULTED** | A correct default prevents it. The mechanism exists and is on. | One config line reopens it. |
| **DISCOURAGED** | A rule, a convention, or a documented principle. Nothing refuses a violation. | A contributor can violate it and the build stays green. |
| **OPEN** | Named and not addressed, or not addressed. | The failure recurs on a default install. |

A design gets no credit for naming a failure it does not close. Three of the four name the
idle-polling lane; two build something that would catch it.

---

## 1. The corpus, as seven concrete nights

Each row is the failure as recorded, with what actually caused it — because the cause is what a
design has to intercept, not the symptom.

| # | Failure | The mechanism behind it (all VERIFIED in FIELD-NOTES) |
|---|---|---|
| **F1** | **Stranded instructions** | A bare Enter does not submit text already on the line; `send` types its own text and destroys what was pending; a background re-invocation discards an idle input line; `send` fails silently above ~200 chars; one recovery attempt (`send " "`) cleared the line without submitting. **Five instructions never delivered.** Two of them were the owner's own — `push master` and `carry on with the queue` — sitting unsubmitted while the engine log recorded them as nudged. A 149-minute stall because an Enter never landed, and *nothing detected it*. (§1.3, §1.4, §11.2, §12.1) |
| **F2** | **A finished session idling 28 hours** | `q-screen-orchestrator`, a question-role session, answered and then stayed registered and idle for one day and four hours. The context watch logged it `finished-awaiting-close` for hours and **had no remit to close it**; the orchestrator that spawned it had moved on. Closed by hand. Its terminal title read as a second orchestrator. (§1.6) |
| **F3** | **Idle-polling burning the window** | `w-phase-19` ran `echo idle` in a loop rather than ending its turn: **3,466 of 3,626 Bash calls** were that literal command, ~1,400/hour for 3¼ hours, adding **445k tokens — 77 % of all context growth in that window** — 274k output, 1.83 bn cached re-reads, session at 91 %. Separately a lane accumulated **58 concurrent `sleep 590` child shells**. Every liveness signal read healthy throughout. It stopped **within one minute** of being told to end its turn. (§3.1, §2.2) |
| **F4** | **A dead orchestrator nobody revived** | The stale-heartbeat nudge is the only escalation the engine has; observed peaks before one fired: 2,808 s in one run and **44,791 s (≈12.4 h)** in the other, with a single orchestrator and no lanes. The previous run ended `orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may sleep)`. A dead run then flagged itself every three minutes **for about five days, 1,085 times**, unresolved. In the 85-minute loop the human-notification watchdog *"had already exited ('run finished') and was never restarted."* (§10.1, §11.1, §11.6, §12.5) |
| **F5** | **Quota read as UNKNOWN for a whole run** | `harness-limits.sh` demands a `.limits` array the live endpoint no longer has, so `snapshot` returns `UNREADABLE` on **every** call; `on_unreadable: proceed` then returns 0 immediately; and `stop_at` is parsed out of the literal string `SESSION=?` so the hard stop **can never fire**. Separately: `weekly_all=unreadable%` on six consecutive ticks and many other days; an `authentication_error` stretch blinding every read with nobody re-authenticating; usage measured against the **wrong account**; a weekly figure falling 26 % → 6 % **from an account switch alone**; and `verdict` returning `UNKNOWN` unless called with `HARNESS_ROLE` prefixed, which detached processes do not inherit. (§11.7, §12.4) |
| **F6** | **A merge that reported success and moved nothing** | `git checkout master` aborts when a tracked file is modified, and one always is (GSD rewrites `.planning/milestone.lock` every phase and leaves it dirty). The merge then ran **on the phase branch against itself** and printed `Already up to date` / `Everything up-to-date`. Both read like success. Caught only because a human checked what `master` actually pointed at. Same class: GSD's verify stage silently skipped for phases 14–18, each `NN-VERIFICATION.md` self-attributing `verified_by: the lane that built the phase`; phase 21 merged before its validator ran; 26 refusal events in an audit log that never occurred. (§4.1, §11.4, §12.7) |
| **F7** | **The owner's Docker stack destroyed** | `docker compose down -v` with no `COMPOSE_PROJECT_NAME` exported landed on the **default** project. Detected only afterwards from image and volume timestamps; the actor was never identified, and a session had refused that exact action as owner-only two minutes earlier. Adjacent: `pkill -f 'playwright test'` killed an unrelated lane because every lane's own prompt contains that literal string; and the owner's own container `OOMKilled` while two `docker compose up --build` ran at once. (§11.5, §11.8, §5.1) |

Two cross-cutting classes appear in nearly every row and are scored separately in §3:
**self-sustaining loops** (85 minutes of Escape-and-`continue` fed by the orchestrator's own wrapped
prose, `NO ONE IS BEING TOLD` at line 5620; a 45-minute banner loop; 1,085 flags over five days) and
**sleep** (the way the previous run actually ended).

---

## 2. The walkthrough

### F1 — Stranded instructions

| Design | Level | Mechanism |
|---|---|---|
| **minimal** | STRUCTURAL | §0.3 deletes the whole family: *"no tmux/AppleScript control, no `send`, no `key`, no nudge, no heartbeat file, no attention file, no screen capture."* Liveness is a process the supervisor started. §15.2 states the cost honestly: nothing in the design can talk to a session that is already running. |
| **reliability** | STRUCTURAL | §6.3: *"There is no nudge."* Retains the capability without the failure: `send(handle, text, mode) → Ack`, where `Ack` is a state machine — `accepted ≠ delivered ≠ processed`, and `accepted` may never be reported as `delivered`. Where the platform gives no receipt, the capability map says `intervention: emulated` and **the conductor's only legal action against that lane is `stop`**. |
| **adapters** | STRUCTURAL + DEFAULTED | Same `Ack` contract, and it is **conformance-tested**: §4.5's fixture asserts that an adapter holding only an enqueue receipt reports `accepted` and nothing stronger. `pty.backend: tmux`, AppleScript retired, Terminal.app refused by the old code's own hand. Residue: rung 3 of the context ladder is still a keystroke, gated on preconditions. |
| **operability** | STRUCTURAL + the missing half | Same deletion (§7.3 *"What replaces the nudge: nothing"*), same `Ack`, and the four keystroke preconditions are checked from `ps` rather than read off the screen — including *the input line is empty, because `send` destroys pending text*. Plus the one thing no other design has: **`control.ack.json`**, the pacer's reply naming `applied` / `deferred` / `rejected` per key, which `/orchestrator:stop` reads to tell the owner whether his command landed. That is the direct answer to `push master` and `carry on with the queue` sitting unsubmitted while the log said delivered. |

All four close the engine's half. Only operability closes the operator's half at the level of "your
instruction was applied", and reliability closes it for stops specifically and more strictly —
`orchestrator:stop --hard` polls `control.applied.json` until `revision ≥ N+1` or
`stop.ack_timeout_seconds` (15) elapses, and returns **exit 8** for *written but unacknowledged*.

### F2 — A finished session idling 28 hours

| Design | Level | Mechanism |
|---|---|---|
| **minimal** | STRUCTURAL | The lane is a real process the supervisor started, reaped every tick by `pid` alive + `ps -o lstart=` matching `start.json`. There is no question-role session in the design at all, so the exact session that idled cannot exist. |
| **reliability** | STRUCTURAL | `tick.lane_seconds: 10` is cited against precisely this record. `released` requires the claim lock released *and* the lane's resource ledger resolved; a lane that cannot release becomes `released:degraded`, and **the run cannot reach `finished` while any such lane exists** — it reaches `degraded`, exit 6. |
| **adapters** | STRUCTURAL | §2: *"workers — started by `orchd` (never by `mind` directly)"*. `ENDED` requires every lane `RETIRED` **and** every `ledger.jsonl` entry to have a `teardown.jsonl` verdict. |
| **operability** | DEFAULTED | Has `HARVEST`, terminal lane states, `lane_terminal` as a wake predicate, and ledger-driven teardown — all correct. But **§2.3 says lanes are "started by the brain"** while §2.2 says the brain *"may request"* a spawn. That ambiguity reintroduces exactly the ownership crack that produced F2: a model spawned a session and then moved on. See graft **G6**. |

### F3 — Idle-polling burning the window

This is the hardest row in the corpus, because every cheap signal reads healthy: the process is
alive, the event file is growing briskly, the engine probe says `running`, tool calls are frequent.
The only observable that distinguishes it is *what* the calls are, or *how fast the window fills*.

| Design | Level | Mechanism |
|---|---|---|
| **minimal** | **OPEN** | §15.3 names this as the design's single weakest point, walks the lane through its own fact sheet, and concludes: *"Every fact is true and every fact says healthy."* It proposes a fourth line (`top repeated tool call in the last N events`), says *"I would add it; but that is the point"*, and **does not add it**. Worse, its `context.raw_pct_threshold: 75` would fire a compaction or a reseed — treating the symptom and hiding the defect. |
| **reliability** | **OPEN** | I9 declares tool-call cadence inadmissible **for everything**, which is a rule against *acting* on the signal, not a detector. §6.2 records the 445k tokens and calls the subsystem *"unstarted work, not a research problem"*. Its context ladder would compact the consequence. No refill-rate mechanism anywhere. |
| **adapters** | DEFAULTED | §10.2 non-negotiable 6 is exact: *"Refill rate is a signal, not just level. `Δpct/hour` above a bound is a defect, not a threshold. The 445k-token `echo idle` lane would have been papered over by compaction; it stopped within one minute of being told to end its turn."* Shipped as `context.refill_rate_alarm: 15 pct/hour`. |
| **operability** | DEFAULTED ×2 | Same rule, `ctx_refill_alarm: 20 %/h`, explicitly framed as a **defect predicate, not a compaction predicate** — the brain is woken to tell the lane to end its turn, *"a hundred times cheaper than compacting the consequence."* Plus §14.2 names `echo idle` among the things the design refuses to spend tokens on (*"`Monitor` or ending the turn, never `echo idle`"*). Plus the **sentinel**, every 4 h, on another account, given three inputs and one question: *has this run produced anything in the last N hours, and if not, why not?* — the only judgement in any of the four designs that is not derived from a predicate, and the only component that catches a run that is alive, busy, costing money and producing nothing. |

**This row is the sharpest separator in the whole judgment.** Minimal and reliability are blind to
the failure that consumed three quarters of a lane's context window and 77 % of its growth.

### F4 — A dead orchestrator nobody revived

| Design | Level | Mechanism |
|---|---|---|
| **minimal** | **OPEN on a default install** | The doctor is excellent — *"try to take the lock"*, no TTL, no heuristic, ~40 lines, immune to the cross-account roster blindness that makes a model probe useless. And it ships **`doctor.enabled: false`** with `interval_hours: 2`. §10.3 rationalises this (*"a doctor that never runs simply means a dead run stays dead until morning"*), which is a restatement of the failure, not a fix. |
| **reliability** | DEFAULTED | Warden installed by `orchestrator:warden install` (opt-in), `launchd StartInterval` at 900 s, probe = non-blocking `flock`, split-brain detected from `owner.json` (`pid` + `pid_start_ticks` + `argv_sha256`), takeover `exec`s a conductor in recover mode **inheriting the lock fd**. Best takeover mechanics in the set. Two costs: `warden.on_unknown: notify_and_hold` can leave a run dead till morning; and §18.3 self-diagnoses the wedged case — a `SIGSTOP`ped or wedged-but-alive conductor holds the lock, the warden correctly refuses forever, and *"`NO ONE IS BEING TOLD`, moved one level down."* |
| **adapters** | DEFAULTED+ | `sentinel.interval_minutes: 30`, and **`sentinel.required: true` when any lane's `capacity_model` is `Window`** — i.e. effectively mandatory on the lane he will actually run, with the right reason (*"a window exhaustion is exactly when the primary provider cannot run its own health check"*). Crash-loop refusal before claiming: N=3 `orchestrator.claim` lines in T=15 m with no `step.result` between → refuse, notify, hold. |
| **operability** | DEFAULTED++ | The warden is installed by `/orchestrator:run` itself, as a **LaunchAgent with `KeepAlive: true`** and explicit `EnvironmentVariables` for `PATH`, `CLAUDE_CONFIG_DIR`, `GH_CONFIG_DIR` — both halves of the recorded failure, cited by name: §12.4 (three detached scripts had to export their own `gh` account because launchd and `nohup` start with no environment) and §11.6 (*"the watchdog had already exited ('run finished') and was never restarted"*). Cadence **120 s**. Recovery tree step 1c holds and notifies on a contradiction (*a live process that did not hold the lock*) rather than picking a story. `claim_budget: 3 claims / 60 min` with 60→120→240 s backoff, Erlang-shaped. Plus the 4-hourly sentinel for wedged-but-alive. |

### F5 — Quota read as UNKNOWN for a whole run

All four invert the shipped `on_unreadable: proceed`, which is the single largest fix available and
the reason none of them scores below DEFAULTED. They differ on whether anything would **notice** the
silent-schema case.

| Design | Level | Mechanism |
|---|---|---|
| **minimal** | DEFAULTED | `Capacity = Window \| Credit \| Unknown`, `on_unknown: hold_dispatch`, `unknown_grace_minutes: 30`, `cache_seconds: 900`. Its best line closes the `stop_at`-can-never-fire half: *"A threshold naming a bucket the provider stopped reporting is a **configuration error**, surfaced in preflight and again on the first tick that cannot find it — never a silent no-op."* Preflight prints the resolved `(platform, base_url, account-identity)` per role, and the meter is chosen by that triple rather than by the binary's name — which kills the wrong-account half. No conformance test, no bucket enumeration, no after-the-fact report. |
| **reliability** | DEFAULTED+ | I8's sum type with five `Unknown` sub-kinds (`throttled \| auth_expired \| schema_unknown \| network \| not_supported`) *"because they want opposite responses"*. *"Stale quota never authorizes routing"*; headroom is the **worst** window across every constraint; a single machine-wide meter with `min_interval_seconds: 3600` and a burst of 2, so **no lane and no agent ever calls a capacity endpoint directly**. Every observation records `account_id` and a threshold series never crosses an account boundary. Preflight gate 8 refuses a lane whose role requires prediction when capacity is `Unknown`; gate 7 catches the shared-account case. |
| **adapters** | DEFAULTED, verging on STRUCTURAL | The only design with a **mechanical** catch: `orchestrator:adapter verify <id>` fails with exit 65 if `readCapacity` returns a scalar rather than the sum type, or if a 200 it cannot parse returns zero instead of raising — *"Z.ai's `TOKENS_LIMIT`→`CREDIT_LIMIT` rename rendered **0 % used**, which reads as plenty of room."* Plus **"enumerate buckets, never name them"** (take every bucket carrying a utilization, stop on the worst), which survives a rename without a code change, and `adapter.verify_max_age_hours: 24` gating dispatch. |
| **operability** | DEFAULTED+ | Same bucket enumeration; a parse yielding nothing is `Unknown`, which is a **refusal to schedule**; measured throttle data (8 rapid calls → 3–8 rate-limited, still limited at t+167 s) drives `capacity_ttl: 3600`, one account per tick, jittered, with mandatory backoff. Honest about the limit of R1-07: *"an idle account cannot be polled at all"* → preflight records `capacity.<account>: unprovable` rather than pretending. And the one after-the-fact catch nobody else has: **`NEXT-RUN.md`'s detector scorecard reports a probe that never once returned a positive as *unproven*, not as clean** — which is the only mechanism in the four that would surface "this read was `UNKNOWN` for the entire run" as a stated fact. |

### F6 — A merge that reported success and moved nothing

All four adopt *append `start` first, `end` last* (minimal: `start.json` before launch, `result.json`
last; the others: `step.intent` / `step.result` with an `action_id`), which converts a crash into a
detectable orphan. That is the shared floor and it is not what this row tests. This row tests whether
anything checks that the effect **landed**.

| Design | Level | Mechanism |
|---|---|---|
| **minimal** | DISCOURAGED | `outcome = f(exit_code, terminal_event)`; a disagreement is `failed: "contradictory"`; *"silence is never success."* Moving run state outside the work tree removes one cause (its own 327 dirty tracked files) but not GSD's `milestone.lock`. There is **no merge-landed assertion**, deliberately: §15.3 records that *"the judge's verdict is unaudited… R1-13 forbids the orchestrator adding checks of its own. That is his decision… and the cost lands here."* That reading is too broad — R1-13 is about verifying the *work*, not the orchestrator's own git operations. |
| **reliability** | **STRUCTURAL** | I4: **the journal appender refuses a `result` record with `outcome:"ok"` on any op declared mutating unless it carries an admissible evidence object**, with admissibility declared per op in `ops.json` — `git.merge` admits only `git_ref` `{ref, before, after, read_back_at}`, *"read back after the op, never the command's word."* Adding an operation without declaring its evidence and its reconciliation is a **load-time error**. And ⚠TENSION draws the line correctly: *"I4 does not verify the work; it verifies that the orchestrator's own operation happened. A merge either moved a ref or it did not, on any project, with or without tests."* This is the single strongest mechanism in the four documents. |
| **adapters** | DEFAULTED+ | §9.5 ships the concrete script, VERIFIED working against PR #26: `git merge-base --is-ancestor "$HEAD" "origin/$BASE"` plus `gh pr view --json state --jq .state = MERGED`. **Two independent oracles**, and a branch merged into itself fails the second one instantly. Plus `EXPECTED_BASE=$(git rev-parse HEAD)` captured before dispatch and asserted inside the worktree, `gh pr merge --match-head-commit`, and *"never parse a test summary."* Excellent for this op; nothing forces the next mutating op to carry evidence. |
| **operability** | DISCOURAGED/DEFAULTED | §8.1 states the principle — *"It does verify **its own** actions — that a merge moved the branch, that a step it dispatched actually started"* — and §16.6 flags honestly that the distinction was never put to the owner. §13.2 verifies teardown by observation. But the assertion itself is not written down, and the `action_id`-in-the-side-effect trick proves an attempt was recorded, not that a ref moved. The FIELD-NOTES merge would have produced a perfectly well-formed `step.result`. |

### F7 — The owner's Docker stack destroyed

Two halves: **destroying** what it did not start, and **starving** the machine his own stack runs on.

| Design | Destroy | Starve | Mechanism |
|---|---|---|---|
| **minimal** | DEFAULTED | **OPEN** | *"The compose project name is read from `owned.ndjson`, never from the environment"*; *"nothing in this design matches processes by pattern, ever"*; previous-run residue is listed with one exact command per item, never reclaimed. Correct and complete as a rule — with no build guard behind it. §15.1 concedes the OOM: *"two heavy lanes can still OOM his own container exactly as they did."* |
| **reliability** | DEFAULTED+ | **DEFAULTED** | Owner tags written **into** the resource (Docker labels `orc.run=`, `orc.project=sha256(root)`), project name passed on the command line at both create and teardown, process identity `(pgid, leader_start_time, argv_sha256)`, `orphan_reclaim: same_tool_confirm`. And the only answer to the starve half that does not cost parallelism: **`limits.max_concurrent_builds: 1`**, serialising only steps a lane *declares* `heavy: true` — *"a declared-cost queue, not resource awareness, and the smallest thing that prevents the one incident that actually happened"*, with the tension against his deferral at [160] recorded. |
| **adapters** | **STRUCTURAL** | **OPEN** | **Invariant BD-1:** *"`pkill`, `killall`, and an unscoped `docker compose down` do not appear anywhere in plugin source. **A lint rule in the test harness fails the build if they do.**"* That is the strongest form available — a convention a contributor cannot violate green. §19.6 declines the starve half explicitly on the owner's authority. |
| **operability** | **STRUCTURAL** | DEFAULTED, expensively | Same ledger rule, stated abstractly as he asked (*"the orchestrator may stop only a thing whose identifier it wrote into the ledger at the moment it created it"*), same lint, teardown verified by observation, and the honest limit: *"it constrains the orchestrator, not its children — a lane can still run `pkill` itself."* Its answer to the starve half is `lanes.max: 1` **per account** — the most conservative default in the set, which prevents the OOM by preventing the parallelism FIELD-NOTES §9.3 shows working cleanly twice. |

---

## 3. The two cross-cutting classes

### 3a. Self-sustaining loops

The dominant shape in the corpus: 85 minutes of Escape-and-`continue` fed by a banner matched inside
the orchestrator's **own wrapped prose**, ended only by an external `SIGTERM`; a 45-minute banner
loop on a healthy orchestrator; 1,085 identical flags over five days; an unwedge process polling
`run is stopped — holding` every 180 s for 32 minutes while doing nothing.

| Design | Level | What bounds the loop |
|---|---|---|
| **minimal** | DEFAULTED | Control entries applied **exactly once, by id**, and removed from `entries` when applied. Self-write suppression by content hash. `judge.max_calls_per_tick: 1` and `judge.max_calls_per_hour: 30` — a real ceiling. `judge.on_unparseable: defer`; *"waiting is the fail-safe everywhere."* No per-detector watermark, no crash-loop detector on the supervisor. |
| **reliability** | **weakest** | Monotonic control revision; the conductor is a **reader only** of `control.yaml`, so there is no self-trigger; content-hash detection; `self_write_digest` on board writes; a durable failure budget in the journal that survives the conductor's own death. But: **no wake budget, no per-detector ceiling, no crash-loop detector named anywhere.** `agent.decision_deadline_seconds` bounds one question, not a sequence of them. Against a corpus dominated by this class, that is the gap that costs it the ranking. |
| **adapters** | DEFAULTED+ | `epoch` on every journal line **is** the crash-loop detector — N `orchestrator.claim` lines in T minutes with no `step.result` between is a restart loop findable by `grep`; shipped as `crashloop.n: 3 / .window: 15m`, refuse to start, notify, hold. **Idempotency by watermark** `(session_id, threshold, armed_at)` written *before* acting, generalised to *"any detector that re-reads its own effect must be idempotent per trip."* Bounded escalation ending at a human: *"the failure mode is not acting wrongly; it is acting the same way for ever."* And non-negotiable 4, which nobody else has: **never log the trigger phrases** — *"a governor that prints `/compact` or `rate-limit` on its own screen gets matched by its own detector."* |
| **operability** | **strongest** | `trip_key = (predicate, subject, epoch, armed_at)` written to `state/trips/<sha>.json` with `O_EXCL` **before** the wake, the watermark rule generalised from compaction to every detector. **`brain_max_wakes_per_hour: 12`** — *"a budget converts 'acting the same way for ever' into 'acting twelve times and then telling someone'."* `claim_budget: 3/60 min` with capped backoff. And the only bound on the *alert* side: `notify_max_per_run: 40` plus `notify_coalesce_minutes: 30`, aimed by name at the 1,085-identical-alerts case, *"a product failure before it is an API failure."* |

### 3b. Sleep

`[2026-09-07T09:08:21Z] watch: orchestrator dead + no live sessions for 3 ticks — tearing down (Mac
may sleep)` is how the previous run ended. On wake every staleness reading says dead and the process
object says alive, and both are correct.

| Design | Level | Mechanism |
|---|---|---|
| **minimal** | DEFAULTED | `caffeinate -i` bound to the **supervisor's own pid** (the previous generation bound it to the watch loop, so when the watch died the machine slept); `boot_epoch` from `sysctl -n kern.boottime` plus `last_tick`, and a gap longer than `3 × interval` is journalled as `sleep_gap` with every liveness verdict across it **discarded rather than trusted**. |
| **reliability** | **STRUCTURAL, and the only complete one** | Every journal record carries `mono` (`CLOCK_MONOTONIC`) beside `ts`; all durations are computed on `mono` and wall clock is display only. A wake is `wall_delta − mono_delta > sleep.gap_seconds` (60). For `sleep.grace_seconds` (120) after a wake, **no lane may be judged `DEAD` and no capacity reading older than the wake is authoritative.** The warden is unaffected because its probe is a lock, not a clock, and `launchd StartInterval` fires after wake where `cron` would not. |
| **adapters** | DISCOURAGED | `boot_id` on journal lines; no sleep fence. |
| **operability** | DISCOURAGED | `caffeinate -i` bound to the pacer's pid; `boot_id`; recovery tree step 1b records the limitation when `boot_id` differs. **No sleep fence** — and with `warden_seconds: 120` against `lease_ttl: 180`, this is precisely the configuration that mis-fires on wake. Without graft **G3**, operability's warden is more dangerous than minimal's. |

---

## 4. Scores

### ARCH-operability — **8 / 10**

The only design with **zero OPEN entries across the seven named failures**, and it earns that on
defaults rather than on prose. It is the only one that bounds every loop-capable component with an
explicit budget (`brain_max_wakes_per_hour: 12`, `claim_budget: 3/60 min`, `notify_max_per_run: 40`
with coalescing) rather than relying on each detector being individually correct — which matters
because the corpus is dominated by loops, not by one-shot mistakes. It is the only one that catches
the idle-polling class **twice**, once deterministically (`ctx_refill_alarm` as a *defect* predicate
that wakes the brain to tell the lane to end its turn, not a compaction predicate that hides it) and
once semantically (the 4-hourly sentinel's single question, the only judgement in any of the four not
derived from a pre-written predicate). Its warden is installed by `run` rather than opted into, at
120 s, with `KeepAlive: true` and explicit `EnvironmentVariables` — the two specific mechanisms
behind the watchdog that exited and was never restarted, and behind the detached scripts that
inherited no environment. `control.ack.json` closes the half of F1 that the other three leave open:
whether the *owner's* instruction was applied. And `NEXT-RUN.md`'s detector scorecard is the only
mechanism anywhere in the set that reports a probe which never once returned a positive as
**unproven rather than clean** — the after-the-fact catch for F5 and for the `find -newermt` class.
It is marked down for three things: F6 is a principle rather than an assertion; there is no sleep
fence, which is a live hazard at its own tick cadence; and §2.3 lets the brain start lanes, which is
the exact ownership crack that produced F2. Its self-diagnosed weakness — *"this design's failure
mode is quiet"* — is real and is the right one to worry about, but it is the only design that ships
three named compensators for it.

### ARCH-adapters — **7 / 10**

Its central bet is the right one for a bad night: **convert a 03:00 degradation into a 22:00
refusal.** Capability negotiation as a run phase, `negotiate.on_unknown: impossible`, and a `plan.json`
whose `weakened[]` and `denied[]` arrays name exactly which of the owner's decisions stopped holding
tonight and what each degraded to — written into an immutable file he can read at any hour with no
model in the path. It is the only design with a **mechanical** catch for the lying-manifest class:
`orchestrator:adapter verify` fails exit 65 when `compact` returns success without a `Proof`, when
`send` reports anything stronger than `accepted` from an enqueue receipt, or when `readCapacity`
returns a scalar or lets an unparseable 200 become zero — which is the schema drift behind F5, caught
by a test rather than by a policy. `BD-1` is the strongest single form in the set for F7's destroy
half: a build-failing lint, not a convention. Its crash-loop detector, per-trip watermarks and the
never-log-the-trigger-phrase rule bound the loop class well. It is marked down for declining F7's
starve half outright (§19.6, on the owner's authority, defensibly), for a sentinel at 30 minutes
against operability's 120 seconds, for having no sleep fence, and for the weakness it names itself:
**the manifest is a claim with no independent oracle**, written by the same author from the same
reading as the conformance fixtures, and trusted at exactly the hour when nobody is watching.

### ARCH-reliability — **6 / 10**

It has the best **per-operation** guarantees of any design here, and by a distance. I4 — the journal
appender refusing `outcome:"ok"` on a mutating op without admissible evidence, with admissibility
declared per op in a shipped data file and an undeclared op being a load-time error — is the single
strongest mechanism in all four documents, and it closes F6 generically rather than one script at a
time. Its sleep fence is the only complete one and it prevents the exact way the previous run ended.
Its GSD `oracle` is the only place in the four where the silently-skipped verification is closed
(`done` only when the verification artifact exists **and does not self-attribute** — one string
comparison). Its `Unknown` sub-kinds, worst-window headroom rule and single machine-wide meter are
the most careful treatment of F5 short of a conformance test. Its reconciler is the only one with an
`unsafe` idempotency class that escalates rather than replaying an irreversible external effect. And
yet it ranks third on **survival**, because survival is a property of the run, not of an operation:
it has no wake budget, no per-detector ceiling and no crash-loop detector, against a corpus whose
dominant failure is acting the same way for ever; its warden is opt-in and defaults to holding on
`UNKNOWN`; it is blind to F3; and §18.3 is a fair self-assessment that I will not improve on — *"this
design's response to 'a model cannot be trusted at 03:00' is to move the load onto deterministic
code, and the field record says deterministic code fails **more quietly** than a model does, not
less… this architecture is a claim, not a property"* until a mutation-tested suite exists that nobody
has written. It is the richest donor of grafts in the set, and that matters more than its rank.

### ARCH-minimal — **5 / 10**

It retires six FIELD-NOTES records at a stroke by deleting the capability that produced them — no
typing into sessions, no screen capture, no heartbeat file, no attention file, no nudge, and no
long-lived orchestrator session with a context window, which also dissolves the single hardest
requirement in the set (compacting the orchestrator). Its crash shape is the cleanest of the four:
`mkdir` as the claim (one syscall, against a measured 27-winners-out-of-50 for the read-then-write
shape), `start.json` before launch, `result.json` last, the directory move as the only commit, and
lock-acquisition as the **proof** that the previous supervisor is gone — no TTL, no heuristic, no
third verdict. Fewest moving parts means fewest things that fail quietly, and that is a genuine
survival property. But on the bad night this corpus describes it is blind where it matters most. It
names F3 as its own weakest point and does not build the fix, while its context threshold would
compact the evidence away. Its doctor — the best-argued health check in the four — ships **off**,
which reopens F4 on a default install. It has no merge-landed assertion, having read R1-13 more
broadly than R1-13 says. And its OOM answer is a cap plus an optional hook, with the incident
conceded. It is the design that would go wrong in the fewest ways and would also have gone right in
the fewest.

---

## 5. Ranking

| Rank | Design | Score | The one-line reason |
|---|---|---|---|
| **1** | **ARCH-operability** | **8** | Zero OPEN entries across the seven; budgets every loop; catches the alive-but-useless lane twice; watchdog on by default at 120 s. |
| **2** | **ARCH-adapters** | **7** | Refuses at 22:00 instead of degrading at 03:00, and is the only one that *tests* a capability claim rather than trusting it. |
| **3** | **ARCH-reliability** | **6** | Best guarantee per operation in the set; second-weakest at the run level, because nothing bounds a loop and the warden holds. |
| **4** | **ARCH-minimal** | **5** | Deletes six failures by deleting the capability, then leaves the two that cost whole nights open by default. |

**Tiebreak, stated because 2 and 3 are close.** On any single mutating operation, reliability is the
better design and I would not argue otherwise. Adapters is ranked above it because the corpus is not
a corpus of single operations — it is a corpus of nights, and the things that ended nights were loops
(85 minutes, 45 minutes, 1,085 flags, 4.5 days), silence (`NO ONE IS BEING TOLD`), and capabilities
that reported `native` and were not. Adapters bounds all three; reliability bounds the first not at
all.

---

## 6. Grafts — what the losers have that the winner should take

Fourteen, ordered by what each is worth on a bad night. Each names the source, the target, and why it
beats operability's version.

### G1 — Evidence-gated results and `ops.json`
**From** ARCH-reliability §1 I4 + §3.6. **Into** operability's journal appender and `runs/<run-id>/`.
**What:** ship `ops.json` as a data file — one entry per mutating operation declaring `mutating`,
`idempotent`, `admissible[]`, `reconcile`, `timeout_s` — and make the function that appends a
`step.result` **refuse** `outcome:"ok"` on a mutating op that carries no evidence object of an
admissible kind. Evidence kinds: `git_ref {ref, before, after, read_back_at}`, `board_readback`,
`file_digest`, `http_status` + a named body predicate, `process_exit`, `process_absent`,
`token_drop`, `transcript_event`. Adding an op without declaring its evidence is a **load-time
error**.
**Why it beats operability's version:** operability has the principle (§8.1) and the
`step.intent`/`step.result` pair with the `action_id` written into the side effect. Both are good and
neither closes F6. `intent`/`result` proves an attempt was *recorded*; the FIELD-NOTES merge produced
a perfectly well-formed result, because `Already up to date` exits 0. The `action_id`-in-the-side-
effect trick proves the attempt reached the side effect, not that a ref moved. Reliability's version
is a refusal in the one code path every result must pass through, it is declared in data rather than
in code, and it generalises to every future operation for free instead of needing someone to remember
the assertion. Keep reliability's ⚠TENSION paragraph verbatim when this is written up: *I4 does not
verify the work; it verifies that the orchestrator's own operation happened* — that is the sentence
that keeps it on the right side of R1-13, and operability's §16.6 already flags that the distinction
was never put to the owner.

### G2 — The doctor's second and third steps
**From** ARCH-minimal §10.3, steps 2 and 3. **Into** operability's warden (`bin/orc-warden.sh`,
`warden_seconds: 120`).
**What:** when the lock is **held** (so the holder is alive), do two more things. (2) Compare
`journal.jsonl`'s byte size against the value the warden recorded on its last visit; not grown ⇒ the
supervisor is alive but not ticking ⇒ write `stop: hard` into `control.yaml` and notify. (3) Compare
`status.json`'s completed-work counter across two visits; unchanged ⇒ **notify only, never kill**,
because slow and stuck are not distinguishable from outside.
**Why it beats operability's version:** operability's warden does exactly one thing — read the lease
and try the lock — and therefore has the same blind spot reliability names as its own worst case in
§18.3: a wedged-but-alive holder keeps its lock forever, the warden keeps correctly refusing, and
nobody is told. Step 2 is the **only mechanism in any of the four designs** that acts on that state,
and it costs one `stat` and one integer in the warden's own state file. Step 3 is the correct
restraint on it. This is the highest-value graft from the lowest-ranked design.

### G3 — The sleep fence
**From** ARCH-reliability §11.2. **Into** operability's journal line shape and the pacer's tick.
**What:** carry `mono` (`CLOCK_MONOTONIC` seconds) beside `at` on every journal record and compute
every duration on `mono`, wall clock for display only. Detect a wake as a tick where
`wall_delta − mono_delta > sleep.gap_seconds` (**60**, DEFAULT-PROPOSED) and write
`observation: machine.wake` with the gap. For `sleep.grace_seconds` (**120**, DEFAULT-PROPOSED) after
a wake: **no lane may be judged dead, and no capacity reading taken before the wake is
authoritative.**
**Why it beats operability's version:** operability has `boot_id`, which catches a reboot and not a
sleep — and sleep is literally how the previous run ended. Worse, operability's numbers make it
acute: `lease_ttl: 180` against `warden_seconds: 120` means that on wake the lease looks expired and
every liveness reading goes stale at the same instant, which is the precise input to
`orchestrator dead + no live sessions for 3 ticks — tearing down`. Without this graft, operability's
fast warden is a liability rather than an asset. Minimal's `sleep_gap` (§10.3) is the same idea and
weaker: it discards verdicts across the gap but does not fence capacity readings, and reliability's
does both.

### G4 — `orchestrator:adapter verify` and the 24-hour dispatch gate
**From** ARCH-adapters §4.5 and §4.2. **Into** operability's `bin/` and its preflight proof table.
**What:** a shell script that runs the adapter's operations against recorded fixtures plus a live
smoke test against the configured account, exit `0` pass / `65` contract violation (named) / `70`
environment. The three checks that carry it: **`compact` must return a `Proof`** (a typed event, a
durable transcript entry, or a *measured* token drop with provenance) — success without proof is exit
65; **`send` must report `accepted` and nothing stronger** when the adapter holds only an enqueue
receipt; **`readCapacity` must return the sum type, never a scalar**, and a 200 it cannot parse must
raise rather than return zero. Then: `adapter.verify_max_age_hours: 24`, and a lane whose adapter has
not passed verify **today is not dispatchable**.
**Why it beats operability's version:** operability's §9.2 carries the identical rule — *"never report
`native` for a capability whose only implementation is a regex over English prose"* — and nothing that
tests it. Its preflight proves *facilities* (the binary is present, the channel delivered a message);
it never proves the adapter will not lie about `compact` at 03:00. The `readCapacity` check is the
mechanical catch for F5's silent-schema half, which operability handles correctly as **policy**
(`limits.on_unreadable: hold`) and cannot **notice**. The 24-hour gate is the answer to Amp's five
releases in fifteen hours and Copilot's 835 versions in twelve months — *"a run that starts on one
flag surface and finishes on another is indistinguishable from a bug in the orchestrator."*

### G5 — `limits.max_concurrent_builds` with `heavy: true` step tags
**From** ARCH-reliability §5.3. **Into** operability's scheduler; replaces `lanes.max: 1`.
**What:** keep `lanes.max: 2` and add one named guard — `limits.max_concurrent_builds: 1`
(DEFAULT-PROPOSED) — that serialises only the operations a lane *declares* heavy in its engine step
definition (`heavy: true`). If the owner wants even that gone it is one key set to `0`.
**Why it beats operability's version:** operability answers the OOM with `lanes.max: 1` per account,
which prevents the incident by preventing the parallelism FIELD-NOTES §9.3 shows working cleanly
twice — phases 12/13 and 21/22, spawned eleven and thirteen seconds apart, **no port or state
collision in either pair**. The incident was two `docker compose up --build` at the same moment, not
two lanes. Reliability's version is a declared-cost queue rather than resource awareness, so it stays
inside his deferral at [160] while closing the only resource incident that actually happened, and it
keeps the throughput. Carry reliability's ⚠TENSION note with it.

### G6 — `orchd` spawns workers; the model never does
**From** ARCH-adapters §2 (table row 3, *"spawns … never by `mind` directly"*) and §8.1's
single-claimer rule. **Into** operability §2.2/§2.3, which currently contradict each other.
**What:** make it an invariant with a test. The brain **requests** a spawn or a stop; the pacer
executes it, writes the ledger line, and owns the handle. No process is ever created by a model
session.
**Why it beats operability's version:** operability's §2.3 says lanes are *"Started by: the brain"*
while §2.2 lists spawn among things the brain *"may request"*. That ambiguity is not cosmetic — F2
happened because a model-spawned session outlived the model's attention and the process that could
have closed it *"had no remit"*. Under the graft the pacer is the only creator and therefore the only
reaper, and the resident/ephemeral brain choice stops being load-bearing for resource ownership.

### G7 — The GSD oracle's non-self-attribution clause
**From** ARCH-reliability §7.2. **Into** operability's GSD adapter (§8.3), beside the branch-name
equality assertion it already has.
**What:** `oracle → done` only when the phase's verification artifact exists **and does not
self-attribute** — reject `verified_by: the lane that built the phase`. One string comparison.
**Why it beats operability's version:** operability's `signals()` plus `harvest_evidence: observed`
asks the engine whether it is done and believes the answer, withholding only on *positively observed*
emptiness. Phases 14–18 were not empty; they shipped with the engine reporting done and the
verification self-attributed, and FIELD-NOTES §11.4 is explicit that *"no automated check caught it;
manual review did."* This is the cheapest high-value line in the entire graft list.

### G8 — Preflight gate 7, account distinctness
**From** ARCH-reliability §4.4 gate 7 (and minimal §11.1, same finding). **Into** operability's
preflight proof table (§1.4), as a new required proof.
**What:** refuse to start when two roles the configuration separates resolve to the **same** account
id, naming both profiles and the shared id, unless `--allow-shared-account`.
**Why it beats operability's version:** operability proves `account.<platform>/<name>` — *which*
account a spawn would use, from the platform's own report, after a throwaway launch. That is the
right proof and it is not the question that matters. Two profiles can be one account — two config
dirs, two keychain entries, **one quota pool**. Without gate 7, operability's per-role capacity
thresholds and its own rule that *"readings are never compared across accounts"* both compute
correctly against a pool that is silently shared, which is F5's wrong-account half wearing a clean
preflight.

### G9 — `requirements.json` and `plan.json.weakened[] / denied[]`
**From** ARCH-adapters §5.1–§5.3. **Into** operability's preflight, as the output of it.
**What:** a requirements table in the core — the one place platforms are *not* named — with a row per
owner item (`R1-08.hard-compact`, `R1-06.wait-for-reset`, `Д12.stop-hard-midturn`, …), each carrying
`axis`, `needed_when`, `on_impossible ∈ deny-role | degrade | ask | refuse-run`, `degrade_to`, and
`owner_item`. Negotiate against each lane's downgraded capability map, write the result into an
**immutable** `plan.json`, and print `weakened[]` and `denied[]` at start and in `status.json`.
**Why it beats operability's version:** operability's proof table proves *facilities*; this table
proves *his decisions*. The difference shows up at 04:00 when he wants to know not "did the channel
work" but "is the guaranteed-compaction thing he asked for still holding on lane L4 tonight, and if
not what did it become" — answerable from a file, with no model. The second property is the one that
survives maintenance: **adding a requirement row makes every existing manifest answer `unknown`, and
`negotiate.on_unknown: impossible` degrades that closed**, so a new safety rule cannot silently pass
on an old adapter. Nothing in operability has that property.

### G10 — The `unsafe` idempotency class
**From** ARCH-reliability §5.4 and §11.3 phase 3. **Into** operability's recovery tree (§12.4), at
step 5.
**What:** declare an idempotency class per mutating op — `by_ref`, `by_readback`, `by_session_id`,
`unsafe` — and on an orphan whose class is `unsafe`, **escalate to the Д6 questions channel and hold
the lane**, never replay.
**Why it beats operability's version:** operability's step 5 searches the `action_id` in the side
effect itself — the ticket comment trailer, the branch name, the commit trailer — which is excellent
where the side effect has somewhere to carry a trailer and silent where it does not. Reliability's
worked example is exact: a crash between opening a PR and recording it produces a second PR, and
R1-12 [331] *wants* stacked PRs, so nothing downstream finds a duplicate suspicious. Operability's
tree has no branch for *"replay might duplicate an irreversible external effect"*; it has `alive`,
`alive but moved on`, and `dead`.

### G11 — Never log the trigger phrases
**From** ARCH-adapters §10.2, non-negotiable 4. **Into** operability's logging helpers.
**What:** a governor never writes `/compact`, `rate-limit`, `usage limit` or any other string its own
detectors match into a file its own detectors read. Write `context action` and `none|present`.
**Why it beats operability's version:** operability's self-write suppression is by content hash and
protects `control.yaml` only. The 85-minute loop never read `control.yaml` — it read a surface
carrying the orchestrator's own wrapped prose. Operability deletes screen-scraping, so that exact
loop is gone; but its journal, its `--why <lane>` render and the sentinel's input (*"the last N hours
of `journal.jsonl`"*) still echo detector strings into text that a later reader matches. The rule
costs one line and closes the class rather than the instance.

### G12 — `capacity.reserve_pct` shipped as a printed open question
**From** ARCH-minimal §5.1 (the *handling*, not reliability's number). **Into** operability's defaults
register and preflight output.
**What:** `capacity.reserve_pct: 0`, **and preflight prints one line naming it as an open question
with the exact wording to put to him** — «Чи можна витрачати ліміт до нуля, чи треба лишати запас на
твою власну роботу?», the sub-question `extract/corrections.md` §F records the interviewer dropped.
**Why it beats operability's version:** operability's defaults register has no reserve at all, so the
run can eat the subscription he needs in the morning — a survival failure for the owner even on a
night the run survives. Reliability ships `reserve_pct: 10` as a silent default for a question never
put to him, which is the thing all four documents promised not to do. Minimal's handling is the only
correct one: ship the neutral value and surface the question.

### G13 — The claim ordering as an invariant, not a convention
**From** ARCH-minimal §4 and §10.1. **Into** operability's lane machine (§5) and claim protocol
(§6.3).
**What:** state the ordering as a testable invariant: `mkdir` the claim → write `start.json`
**before** the platform is launched (carrying ticket, ticket digest, platform, account, worktree,
base sha, compose project, session id where the client names it, cmd) → launch → append every created
resource to the ledger **as it is created** → write `result.json` **last** → `mv` the directory to
done. Nothing is written after `result.json`, and the directory move is the only commit point.
**Why it beats operability's version:** operability has `mkdir claims/<id>.d` for the local backend
and `SPAWNING` as a real state — both correct — but the ordering lives in prose rather than as a
property something checks. Minimal's version makes orphan detection a directory listing with no
journal read and no parse, which is what you want from a warden or a resuming process that may not
trust anything else on disk yet. It is the cheapest orphan detector in the four documents.

### G14 — BD-1 as a named build-failing invariant, plus the clause operability omits
**From** ARCH-adapters §11 Invariant BD-1. **Into** operability's test harness lint (§13.2).
**What:** name the invariant, list the three literal patterns (`pkill`, `killall`, `docker compose
down` without an explicit `-p`), and fail the build on any of them in plugin source. **Then add the
clause neither design has:** no teardown command may be constructed from an environment variable —
every identifier in a teardown command must come from a `ledger.jsonl` field.
**Why it beats operability's version:** operability already claims the same lint, so this is mostly a
matter of naming it and pinning the patterns. The added clause is the real graft: the recorded
incident was not a `pkill`, it was `docker compose down -v` **with `COMPOSE_PROJECT_NAME` absent**, so
the command resolved to the default project — the owner's. A lint on the three verbs would not have
caught it. A lint on *teardown arguments sourced from the environment* would, and FIELD-NOTES §12.4
establishes the general case: detached scripts inherit no environment at all.

---

## 7. What nothing in the set survives

Named because a graft list that implies full coverage would be its own quiet failure.

1. **Secrets reaching a place nobody scans.** FIELD-NOTES §11.10: two local role passwords printed in
   clear text into a session transcript by Playwright's `--trace on`; *"no automated secret scan
   covers tool output or transcripts."* None of the four covers it. Minimal is the only one that says
   so out loud (§14.5: *"no line writable in [the red-line file] would have prevented"* it).
2. **File-level collision with the owner's own editing in the same checkout** (R1-16 case 2). All four
   reduce it to process-and-container isolation via worktrees and the ledger, and all four state that
   files are untouched. LANDSCAPE §5 confirms it is unsolved across the entire field and must be
   invented. Nobody invents it here.
3. **A lane running `pkill` itself.** Operability §13.2 states it plainly: the ledger *"constrains the
   orchestrator, not its children."* BD-1 lints plugin source; it cannot lint what a model types into
   a shell at 03:00. R1-15's one text file is the only barrier, and on Kimi and pi there is no sandbox
   beneath it.
4. **The commit-gate mutation class** (FIELD-NOTES §11.9): every one of those gates was found broken
   by mutation rather than by failing. No design in the set proposes mutation-testing its own
   checkers, and reliability §18.3 is the honest statement of the consequence for all four:
   *"until those tests exist and are verified by mutation — breaking each invariant on purpose and
   confirming the suite goes red — this architecture is a claim, not a property."* That sentence
   applies to the winner as much as to its author's own design, and it applies to every graft above.
