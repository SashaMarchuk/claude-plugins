# RED-night-one — the first unattended night, simulated against the eight specs

**Date:** 2026-09-19. **Method:** one night walked hour by hour against `SPEC-state`, `SPEC-work`,
`SPEC-adapters`, `SPEC-engine`, `SPEC-cli`, `SPEC-config`, `SPEC-safety`, `SPEC-repo`, read in full.
Every stop is a point where the specs are silent, contradict each other, or jointly produce a wrong
outcome. No vague worries: each finding names the file, the section, and what physically happens.

**Evidence tags.** **VERIFIED** — read at a named line in a named spec file in this repository today.
**CLAIMED** — a spec asserts it and I did not re-derive it. **INFERRED** — my reasoning from the above.
Every finding below is VERIFIED as *"the specs say this"*; the tag on each finding marks the strength
of the **consequence** I derive.

---

## 0. The scenario, fixed

Project `<work-project>`, local backend, GSD engine, everything at its shipped default unless named.

**Lanes** (the `SPEC-adapters` §1.9 E1 configuration, plus one):

| id | platform | provider | account | role |
|---|---|---|---|---|
| L1 | claude-code | anthropic-max | cc-<profile-A> | executor |
| L2 | claude-code | glm-coding-pro | zai-personal | executor (ceiling 2, `basis: contract`, ban risk) |
| L3 | codex-cli | openai-prolite | codex-personal | executor |

**Queue**, six items, all `ready`, no dependencies except T-106 → T-101:

`T-101` migration · `T-102` flaky integration fix · `T-103` large refactor · `T-104` auth flow ·
`T-105` sign-in logo · `T-106` docs, blocked on T-101.

**Events**: GLM window exhausts at 01:10 · T-104 asks a question at 02:41 · T-102 fails three times
(00:50, 01:40, 02:30) · owner edits T-105 at 02:00 · the laptop sleeps 04:02 → 04:22.

---

## 1. The night, hour by hour, with every stop marked

### 22:41 — `orchestrator run --mode controlled --max-lanes 2`

`SPEC-cli` §3.2 resolves config, takes the project lock, runs the proof table, creates
`$ORCH_HOME/runs/<work-project>-20260919-224100Z/`, forks the supervisor, prints one line.

**STOP 1.** `$ORCH_HOME` is one of six different roots. `SPEC-cli` §2.4 and §3.2 use `$ORCH_HOME`
and never define its default. `SPEC-config` §5.1 uses `$ORCHESTRATOR_STATE_DIR`, default
`$HOME/.orchestrator`. `SPEC-state` §2.1 uses `${ORCHESTRATOR_STATE_DIR:-$HOME/.orchestrator}`.
`SPEC-work` §1.2 uses `${ORCHESTRATOR_STATE_DIR:-$HOME/.local/state/orchestrator}`. `SPEC-adapters`
§1.3 and §14 make it the **frozen** key `state.root: <config-root>/shared/orchestrator/state`, and
`SPEC-safety` §3.2 uses `<config-root>/orchestrator/state`. `SPEC-repo` §12.1 adds a seventh key name,
`orchestrator.home: $HOME/.orchestrator`, also **frozen**. See finding **11**.

**STOP 2.** Preflight gate ordering is unresolved. `SPEC-adapters` §11.2 gate 6 refuses outright when
two lanes share an account identity; `SPEC-cli` §3.2 step 3 makes the same refusal overridable with
`--allow-shared-account`. `SPEC-config` §7.1 has a third gate list, `SPEC-work` §3.1 a fourth (five
connect probes), `SPEC-safety` §2.6 a fifth (red-line file), `SPEC-engine` §10.3 a sixth (branching
negotiation), `SPEC-repo` §11 a seventh. Nothing merges them, nothing orders them, and each claims
"the first error the owner reads is the first error that exists" (`SPEC-adapters` §11.2). INFERRED:
the owner gets whichever refusal the implementer happened to wire first.

**STOP 3.** Preflight writes `lanes/L1/lane.json`, `lanes/L2/lane.json`, `lanes/L3/lane.json`
(`SPEC-adapters` §1.3, §1.8). The supervisor's claim primitive is `mkdir lanes/<lane_id>` in the same
directory (`SPEC-state` §6.1). Two objects, one namespace. See finding **1**.

**STOP 4.** L3's account `codex-personal` has no live session, so `SPEC-adapters` §8.5 rule 3 forbids
polling it at all and preflight records `capacity.codex-personal: unprovable`. Gate 7 requires
"capacity readable **or** explicitly `None`". `openai-prolite` declares `capacity_model: Window`, so it
is neither. See finding **4**.

### 22:42 — first dispatch

Tick 1. Step 7 of `SPEC-state` §3.2: *"while `live_lanes < max_lanes` and capacity allows and a ready
ticket exists — claim, launch."*

**STOP 5.** Nothing anywhere says **which** of T-101…T-106 is claimed first, or **which lane** it goes
to. `SPEC-adapters` §9.4 is an admission test on a candidate lane; it does not produce a candidate.
`SPEC-work` §4.3 `CLAIM(item)` takes an item and no lane. `SPEC-state` §3.2 step 7 takes neither. See
finding **13**.

**STOP 6.** `--max-lanes 2` writes `concurrency.max_lanes` (`SPEC-cli` §3.2 flag table). The admission
algorithm reads `config.concurrency.max` (`SPEC-adapters` §9.4 steps 4 and 6). `SPEC-repo` §12.1 ships
`concurrency.max_lanes: 2`; `SPEC-adapters` §14 ships `concurrency.max: 2`. Under `DEF-1` /
`O-31` ("a key read at run time that is not in this table is a configuration error, exit 78" —
`SPEC-state` §11, `SPEC-adapters` §14, `SPEC-repo` §12) the owner's flag is a key no register the
admission code reads contains. See finding **20**.

Say the implementer picks T-101 → L1 and T-102 → L3, and defers L2 on the global cap of 2.
`concurrency.deferred` is emitted (`SPEC-adapters` §9.5). L2 — the GLM lane — never starts. Nothing in
any spec breaks the tie again later; there is no fairness rule, no round-robin, no ageing.

### 00:50 — T-102 fails, attempt 1

Codex exits non-zero. `SPEC-state` §3.3: lane → `failed`; task `failed` → `ready` while the budget
remains. Attempt 2 launches.

**STOP 7.** The failure is also a `SPEC-work` event, and `SPEC-work` §2.1 has **five roles** and none
of them is `failed`. The item can only be written `backlog | ready | active | needs-input | done`. The
board (here, the frontmatter) therefore shows T-102 as `active` through all three attempts and after
the budget is exhausted. See finding **6**.

### 01:10 — the GLM quota wall

The meter reads `zai:sasha` → `Window`, `worst.used_pct = 96`, over `capacity.hard_pct`.

**STOP 8.** `SPEC-state` §3.2 and §3.7 have exactly one transition for this:
`["running","paused","capacity.hard_threshold"]` — a **run**-level pause. The lane machine (§3.3) has
no held state; the cause vocabulary (§3.6) has no per-account cause. `SPEC-adapters` §8.7 says
`auth_expired` should "hold every lane on that account" and §8.6 says a `Window` hard threshold should
"pause until `resets_at` + margin" — both per-account statements with no state to write them into. So
either the whole run pauses until 06:00 because one of three accounts is full, or the implementer
invents a lane-level hold that `SPEC-state` §4.4 R5 refuses to journal and `journal.on_illegal_transition:
refuse_and_abort` turns into exit 70. See finding **2**.

**STOP 9.** If the exhausted provider had been `Credit` rather than `Window` — DeepSeek or Amp, both on
the owner's own list — `SPEC-adapters` §8.6 says "**stop and notify a human**; never auto-resume".
`SPEC-state` §11 ships `capacity.on_exhausted: pause` for every variant, and `paused` has exactly three
wake causes (§3.7): `control.resume`, `capacity.reset_reached`, `wake.grace_expired`. A credit balance
produces none of them. See finding **3**.

**STOP 10.** The owner is notified — into `status.json`. See finding **23**.

### 01:40, 02:30 — T-102 fails twice more

`SPEC-engine` §8.5: "identical failure" is `(ticket_id, step_id, reason_code)`, threshold 3,
`failures.on_exhausted: "notify_and_stop"`.

**STOP 11.** Four key names for one knob — `failures.identical_threshold` and `failures.on_exhausted`
(`SPEC-engine` §8.5), `failures.repeat_threshold` and `failures.action` (`SPEC-repo` §12.5),
`failures.repeat_threshold` and `failures.count_blocked_on_human` (`SPEC-state` §11),
`failures.*` as a Live class with no members named (`SPEC-cli` §4.1) — and no spec says **what stops**.
`SPEC-state` §3.4 parks the task and keeps the run alive. `SPEC-engine` and `SPEC-repo` say
`notify_and_stop`. The owner himself said «В який момент не знаю» [442]. See finding **17**.

At 02:30 the run either continues with four live tickets or ends the night with four tickets unstarted.
Both are defensible readings of the shipped defaults.

### 02:00 — the owner edits T-105

He opens `.orchestrator/tickets/0105-sign-in-logo.md`, changes acceptance criterion `#2` from 375px to
390px, saves, goes back to bed.

**STOP 12.** `SPEC-work` §1.2, §2.6 and Appendix A.1 put the local registry at
`<project>/.orchestrator/**items**/*.md`. `SPEC-cli` §3.8 step 6, `SPEC-state` §2.3, `SPEC-config`
§5.1, `SPEC-repo` §3/§13.1 and `SPEC-config`'s own key `tickets.local_dir` all put it at
`<project>/.orchestrator/**tickets**/*.md`. The Tier-0 sweep (`SPEC-work` §6.1) globs `items/`. The
edit is never seen. See finding **7**.

**STOP 13.** Even in the same directory, the floor cannot read the file. `SPEC-work` §2.2 and §2.5 step
1 require a frontmatter **`role:`** key and fail `role-unmapped` without it; `SPEC-state` §3.4,
`SPEC-repo` §13.1 and the migration in `SPEC-repo` §9.4 all write frontmatter **`status: ready`**. See
finding **7**.

Assume both are fixed and the edit lands. `#2` is not ticked, so §10.2 classifies it as an in-flight
adaptation and `change.on_adaptation: adapt` delivers it (§9.5 Tier A). Fine. Now assume `#2` **was**
ticked — the contradiction branch:

**STOP 14.** `change.on_contradiction: finish_then_new` records `{on_harvest: "supersede"}` on
`items/0105.json` and lets the lane finish (`SPEC-work` §10.5, A.3). Two holes. (a) If the lane
**fails** instead of finishing — which is exactly what T-102 did three times — no spec says whether the
pending supersede fires, is dropped, or survives to the retry. (b) The retry re-claims and §4.3 step 8
recomputes `spec_digest` from the **current** file, so attempt 2 works against the *new* spec while a
pending action still promises to supersede it against the *old* one. See finding **18**.

### 02:41 — T-104 asks a question

**STOP 15.** Two specs give opposite behaviour on the same platform in the same night.
`SPEC-state` §9.3 is built on the fact that a question on Claude Code in background mode "**cannot be
answered by anything**": the wrapper exits 5, the lane goes terminal `blocked_on_human`, the task goes
`blocked`. `SPEC-adapters` §5.10 ships `questions.native_tool: disallow-headless` — the core *injects
its own `ask_supervisor` tool and disallows the platform's native ask*, precisely so the question stays
answerable. Under the adapters default the state spec's entire §9.3 path is unreachable; under the state
spec's `questions.answer: when_native` reading `caps.answer = none`, the adapters default is inert.
Nothing reconciles them, and **no spec anywhere defines `ask_supervisor`** — not its schema, not its
injection mechanism, not what a `claude -p --output-format stream-json` session does with it. See
finding **15**.

**STOP 16.** The question needs a channel. `questions.channel` ships **unset** on purpose
(`SPEC-work` §9.2, `SPEC-repo` §12.8: "preflight asks once"). `SPEC-cli` §3.1 MR-15 makes the config
verb **fail closed to non-interactive** and `SPEC-cli` §3.2's `run` algorithm has no step that asks
anything. `SPEC-work` §13.4 forbids asking during a run. `SPEC-state` §9.3 step 4 says the record is
"written to the Д6 channel" with no branch for an unconfigured one. See finding **16**.

**STOP 17.** With the channel configured, the item goes `needs-input` and the claim is **held**
(`SPEC-work` A.4). Now the 02:00 edit case lands on it: §10.1 says
`if item.role == needs-input -> re-run FLOOR. Pass -> ready.` The item returns to `ready` **with the
question still open**, is re-claimed on the next tick, and a second lane starts work on a ticket whose
open question nothing closed. When the answer arrives at 09:12, §9.5 Tier C moves it to `ready` again.
See finding **19**.

### 02:58 — T-105 finishes; the supersede fires

`SPEC-work` §10.3 composes the new item, creates it, reads back id `0155`, and §10.4's
`tickets.machine_authored_ready: false` sets its role to **`backlog`**.

**STOP 18.** `backlog` is not a state in `SPEC-state`'s task machine (§3.4: `unknown | ready | claimed |
in_progress | needs_review | blocked | failed | done`) and `task.discovered → backlog` is not a tuple in
`transitions.json` (§3.7). `SPEC-state` §4.4 R5 refuses the record, writes a `note`, and
`journal.on_illegal_transition: refuse_and_abort` takes the run to `aborted`, **exit 70**, mid-night,
with four tickets unfinished. See finding **6**.

### 03:30 — the owner wakes, checks, and changes his mind

He runs `orchestrator status`, sees T-104 waiting, and (per `SPEC-work` Appendix A.5) runs
`orchestrator:set when_only_blocked=finish`.

**STOP 19.** There is no `orchestrator:set`. `SPEC-cli` §3 defines twelve commands and `set` is not one
of them. Nor are `pause`, `doctor`, `init`, `connect`, `show`, `adapter verify`, `engine verify`,
`status --proof` or `migrate-tickets`, all of which other specs instruct the owner or the implementer to
run. `SPEC-config` §5.5 step 10 tells him, in the failure message he will actually read at 03:30, to
"run `/orchestrator:doctor`". See finding **12**.

**STOP 20.** He types `orchestrator stop-soft` instead. That writes an entry to `control.json`
(`SPEC-cli` §3.4, `SPEC-state` §4.8, `SPEC-repo`). The supervisor, per `SPEC-config` §5.9, polls
`control.yaml` — a different file, a different format (restricted YAML vs JSON), a different lock (a
`mkdir` lock directory vs a `flock` target), and a different cadence (`control.poll_seconds: 10` vs
`tick.control_seconds: 5`). The reply file is `control.applied.json` in one spec and
`control.applied.ndjson` in the other. See finding **8**.

**STOP 21.** Assume one file. The run has been held since 03:12 on `when_only_blocked: wait`, whose
`hold_tick_seconds` is **300** (`SPEC-work` §12.2). The stop command polls for an ack for
`stop.ack_timeout_seconds: 90` (`SPEC-state` §11, `SPEC-cli` §3.4, `SPEC-repo` §12.8). `SPEC-work`'s own
worked example A.5 shows the entry written at 03:30:11 and applied at 03:35:00 — **289 seconds**. The
command exits **8** ("written, not acknowledged") every single time, in the spec's own example. See
finding **9**.

### 04:02 → 04:22 — the laptop sleeps

On wake, one tick fires with `wall_delta ≈ 1200 s` and `mono_delta ≈ 60 s`. `SPEC-state` §5.8 detects
the wake (`> sleep.gap_seconds: 60`), writes `machine.wake`, and holds every liveness verdict for
`sleep.grace_seconds: 120`. This part works, and it is the best-specified thing in the whole set.

**STOP 22.** The lane timeout does not use `mono`. `SPEC-state` §1.2 is categorical — *"Every duration
in the system is computed on `mono`"*, *"never subtract two of these to get a duration"* — and then
§3.6 names the lane cause `timeout.wall` and §6.2's canonical `start.json` carries `timeout_s: 14400`
under an *"external wall-clock timeout"* (§6.2 step 8). `SPEC-adapters` §5.1 makes this doctrine —
*"Every timeout is an external wall clock imposed by the core"* — and §5.6 sets `lane.max_seconds: 3600`.
A 20-minute sleep is exactly where wall and mono diverge, and 3600 and 14400 are exactly where the two
specs diverge. See finding **14**.

**STOP 23.** Nothing detects a supervisor that did not come back. `doctor.enabled` is `false`
(`SPEC-state` §11, `SPEC-repo` §12.8) and `auto` (`SPEC-cli` §10) — and `SPEC-state` §5.6 runs it on
`launchd` under a **different account** the owner has not nominated. On the shipped default the
dead-orchestrator class, which is the failure that ended the previous 34-hour run, is uncovered. CLAIMED
by the specs themselves (`SPEC-state` §11 rationale: "off by default: it needs a separate account, if the user configures
one").

### 05:45 — drain and teardown

`SPEC-safety` §6.1's terminal condition holds; §6.2 runs.

**STOP 24.** Step 4 *"walks `owned.ndjson` in reverse `seq` order"*. The lane wrappers wrote
`resources.ndjson` (`SPEC-state` §2.2, §4.1, §6.4, twelve occurrences). `owned.ndjson` does not exist.
Teardown iterates an empty file, every verdict is vacuous, and §6.8's CLEANUP-PROOF Part A prints an
empty table under the heading *"a row with no authorising line is not merely absent from this table — it
is unreachable"*. The build lint `LINT-BD1` (`SPEC-cli` §8, `SPEC-safety` §3.9) guards only the
`owned.ndjson` name, so the file that actually holds the Docker projects and worktrees is unguarded. See
finding **10**.

**STOP 25.** Step 2 *"**wait** `sleep.grace_seconds` (120) before proceeding"* — a blocking sleep inside
the supervisor's own tick, while `SPEC-state` models the same fence as a non-blocking `paused` state
with a `wake.grace_expired` transition. A `stop-hard` typed during those 120 seconds is unread. INFERRED.

**STOP 26.** The run finishes `degraded`. `SPEC-state` §9.1 says that is **exit 4**; `SPEC-safety` §6.9
says **exit 6**. `SPEC-cli` §2.5 — the table that claims *"No command exits with a code outside this
table"* and ships a build-failing test for it — defines 4 as `NO_RUN` and 6 as `WRONG_PHASE`. The owner's
`|| handler` reads "no run for /path" or "wrong phase" for a night that did work and left a container
running. See finding **21**.

### 09:00 — the morning

`report.md` §6 *"Left running, deliberately"* reads from `owned.ndjson` (empty). §5.2's render prints
`glm/main window unknown — never proven this run` with the attention line *"that lane is
unschedulable"* — the spec ships the symptom of finding **4** in its own worked example.

---

## 2. The findings, most severe first

### 1. `<run-root>/lanes/<lane-id>/` holds two incompatible objects, and the orphan scan deletes one
**Lives in:** `SPEC-state` §2.2, §6.1, §6.2, §7.3, §11 (`claim.on_dir_without_start: release`) ·
`SPEC-adapters` §1.3, §1.8, §7.1 (EV-1).

`SPEC-adapters` defines `Lane = Platform × Provider × Account × Role`, one per **runnable slot**,
created at preflight, `immutable for the run`, living at `<run-root>/lanes/<lane-id>/` with
`lane.json`, `events.jsonl`, `handles/`, `sessions.jsonl`. `SPEC-state` defines a lane as *"one attempt
at one task"*, id `L<NN>-<ticket-slug>`, created by `mkdir lanes/<lane_id>` **as the claim**, living at
the same path with `start.json`, `events.ndjson`, `events.norm.ndjson`, `result.json`.

Three consequences, all mechanical:

- **Deletion.** `SPEC-state` §7.3 runs *before the fold*, on a directory listing: `if not exists
  d/start.json → RELEASED (remove d)`. `lanes/L1/`, `lanes/L2/`, `lanes/L3/` have no `start.json`, ever.
  The first resume, takeover or doctor relaunch removes the resolved lane records, the normalised event
  streams and the ticket→session lineages for all three platforms. VERIFIED from the two texts; INFERRED
  as to the destruction.
- **The detector reads a file nobody writes.** `SPEC-adapters` EV-1 is absolute: *"The core opens no
  platform-native transcript, ever. It reads `<run-root>/lanes/<lane-id>/events.jsonl` and nothing
  else."* `SPEC-state` §4.7 is equally absolute: *"A detector's input is `events.norm.ndjson`."* Two
  filenames, two directory keys (platform-slot vs ticket-attempt), one claimed single source of truth.
- **Session lineage is keyed twice.** `SPEC-adapters` §5.6 writes `sessions.jsonl` keyed on ticket, many
  rows per ticket, inside the platform lane. `SPEC-state` §3.5 writes `sessions.ndjson` keyed on lane,
  inside the attempt lane. `SPEC-state` §3.3 requires *"a lane never changes its task"*; `SPEC-adapters`
  §1.1 requires *"one lane runs many sessions over a night"* across tickets. The two statements cannot
  both describe one directory.

**Cost to fix:** rename one object. The adapter's object is the one the owner never named
(`SPEC-adapters` §16.1 admits this) and the one whose vocabulary leaks into every stop command.

### 2. One account's quota wall pauses the entire run, and the alternative cannot be journalled
**Lives in:** `SPEC-state` §3.2, §3.3, §3.6, §3.7, §4.4 R5, §11 · `SPEC-adapters` §8.4 (CAP-1), §8.6,
§8.7.

`SPEC-adapters` makes capacity strictly per account — CAP-1: *"The core refuses to compare two readings
whose keys differ"* — and every policy in §8.6/§8.7 is phrased per account (*"hold every lane on that
account"*). `SPEC-state` provides exactly one place to put that: the **run** machine's `paused` state,
entered by `capacity.hard_threshold` / `capacity.exhausted`, whose tick *"Dispatches nothing"*.

At 01:10 the GLM window fills. Either:
(a) the run pauses until 06:00 and the two healthy accounts — Anthropic at 10%, OpenAI at 12% — do
nothing for five hours; or
(b) the implementer holds only L2. There is no lane state for "held on capacity" (§3.3 lists fifteen
lane states; none of them), no cause in the closed vocabulary (§3.6), and therefore no legal
`transition` record. §4.4 R5 refuses it and `journal.on_illegal_transition: refuse_and_abort` (§11) takes
the run to `aborted`, exit 70.

`concurrency.deferred` (`SPEC-adapters` §9.5) is the nearest existing signal and it is an *event*, not a
state: it says "not dispatched this tick", not "this account is walled until 06:00".

**Cost to keep the owner's R1-06.1 («дочекатись рестарту ліміту і продовжити») as stated:** a per-account
`held` lane state, three causes in §3.6, three rows in `transitions.json`, and a `resume_at` per account
rather than per run.

### 3. `paused` on a credit provider has no legal exit
**Lives in:** `SPEC-state` §3.2, §3.6, §3.7, §11 (`capacity.on_exhausted: pause`) · `SPEC-adapters` §8.1,
§8.6, §14 (`capacity.spend_ceiling_usd`).

`SPEC-adapters` §8.1 is built around the fact that *"A scheduler written against 'pause until
`resets_at`' will **wait forever** on a credit platform"*, and §8.6 therefore specifies
*"**stop and notify a human**; never auto-resume"* for `Credit`. `SPEC-state` ships one default for all
variants — `capacity.on_exhausted: pause` — and `paused`'s only wake causes are `control.resume`,
`capacity.reset_reached` and `wake.grace_expired`. A credit balance emits none. The run sits in `paused`
until a human types a stop, `when_only_blocked` never evaluates (the drain condition in §3.2 is only
checked in `running` and `draining`), and Д3's clean finish never runs.

`SPEC-adapters` §8.6's start-time refusal on a `Credit` lane with no ceiling narrows but does not close
this: a lane **with** a ceiling still exhausts it.

### 4. A standby account can never become schedulable — the third platform is dead on arrival
**Lives in:** `SPEC-adapters` §8.5 rule 3, §8.7, §8.9, §11.2 gate 7, §14 · `SPEC-cli` §5.2 ·
`SPEC-repo` §12.3.

The chain, every link quoted from a spec:

1. §8.5 rule 3: *"Poll the active account only. An idle account cannot be polled at all"* — an unused
   profile's OAuth token is stale and returns `authentication_error` (VERIFIED in that document).
   Preflight records `capacity.<account>: unprovable`.
2. §14: `capacity.on_unknown: hold_dispatch`, `capacity.unknown_grace_minutes: 30`.
3. Dispatch to L3 is therefore held. After 30 minutes the grace expires and it is held permanently.
4. A reading can only become provable if a session runs under that account. A session can only run if
   dispatch is allowed. **Deadlock.**

With `concurrency.max: 2` and three lanes, at least one lane is *always* a standby account. The two that
start are provable; the third never is, whichever it is. `SPEC-cli` §5.2's own worked render prints the
outcome — `glm/main window unknown — never proven this run` — with the attention line *"that lane is
unschedulable"*, and treats it as a display case rather than as the defect it is.

**Cost to fix:** a bootstrap exemption — the first dispatch to an unprovable account is permitted, the
reading is taken in-band from the first session's own events (§8.5 rule 5 already prefers this), and the
hold applies only after a reading has once succeeded and then gone stale.

### 5. Two claim orderings, both declared build-failing invariants, contradicting on the same step
**Lives in:** `SPEC-state` §6.2 (*"nothing may be reordered"*) · `SPEC-work` §4.3 (`INV-CLAIM-ORDER`,
*"a reordering fails the build"*) · `SPEC-work` §5.4 · `SPEC-state` §3.4.

| | `SPEC-state` §6.2 | `SPEC-work` §4.3 |
|---|---|---|
| the claim | `mkdir lanes/<lane_id>` in the run dir | `mkdir claims/<item-id>.d`, **project-scoped, outlives the run** (§4.2) |
| board write | step 3, **before** `start.json`; on failure *"rmdir the lane; task returns to ready. A claim is never held on an unverified board write"* | step 10, **after** everything; *"ADVISORY. Failure degrades `board_sync`; **DOES NOT abort**"* |
| re-read | absent | step 8, mandatory, closes the edit race |
| board CAS | absent | step 7, `refs/heads/orch-claim/<id>` |

A third variant appears in `SPEC-safety` §7's worked night: `mkdir claims/SFW-214.d` → `owned.ndjson`
intent → worktree → process group → `lanes/L1/start.json`.

These are not stylistic. On the local backend at 22:42 the two specs disagree about whether a failed
frontmatter write releases the ticket, and `board.writeback` itself is `true` in `SPEC-work` §12.2 and
**`false` for the local registry** in `SPEC-state` §11 and `SPEC-repo` §12.2 — so under one spec the
step that the other makes load-bearing does not happen at all.

### 6. Two task vocabularies; the first Д9 supersede aborts the run
**Lives in:** `SPEC-state` §3.4, §3.6, §3.7, §4.4 R5, §11 · `SPEC-work` §2.1, §10.3, §10.4, §12.2.

`SPEC-work`'s five roles: `backlog | ready | active | needs-input | done`, and *"**`blocked` is not a
role**"*, and there is no `failed`.
`SPEC-state`'s task machine: `unknown | ready | claimed | in_progress | needs_review | blocked | failed |
done`, with `blocked` and `failed` both load-bearing (§9.3 step 4; §3.4's retry budget).

Three collisions fire on this night:

- **02:58, fatal.** `tickets.machine_authored_ready: false` creates item 0155 as `backlog`.
  `task.discovered → backlog` is not in `transitions.json`; §4.4 R5 refuses; `refuse_and_abort` →
  `aborted`, **exit 70**. The run dies at 02:58 with four tickets unfinished, because the owner edited a
  finished ticket.
- **02:41.** A question puts the task in `blocked` (`SPEC-state` §9.3) and the item in `needs-input`
  (`SPEC-work` §9). Two records, two names, one ticket.
- **02:30.** Budget exhaustion parks the task in `failed` (`SPEC-state` §3.4) and leaves the item in
  `active` forever (`SPEC-work` has no role to move it to). At 09:00 the board says a dead ticket is
  being worked on.

### 7. The owner's 02:00 edit is invisible: wrong directory, wrong frontmatter key
**Lives in:** `SPEC-work` §1.2, §2.2, §2.5, §2.6, Appendix A.1 · `SPEC-state` §2.3, §3.4 · `SPEC-cli`
§3.8 · `SPEC-config` §5.1 and key `tickets.local_dir` · `SPEC-repo` §3, §9.4, §13.1.

Two independent breaks, either of which alone is sufficient:

- **Directory.** `SPEC-work` reads `<project>/.orchestrator/items/*.md`. Every other spec writes
  `<project>/.orchestrator/tickets/*.md`, including `SPEC-cli`'s `add` (§3.8 step 6) and `SPEC-repo`'s
  migration (§9.4: *"copy your local ticket queue into `<project>/.orchestrator/tickets/`"*). The
  Tier-0 sweep (`SPEC-work` §6.1: `find items/ -newermt`) returns nothing, forever. Д8 and Д9 never fire
  on any night.
- **Frontmatter key.** `SPEC-work` §2.2/§2.5 step 1 requires `role:` and fails `role-unmapped` without
  it. `SPEC-state` §3.4 reads *"frontmatter `status: ready` locally"*; `SPEC-repo` §13.1's shipped
  ticket carries `status: ready`. Every ticket written by `add` and every ticket migrated from the old
  plugin fails the floor on line 1.

Also: `tasks.ready_requires` (`SPEC-work` §12.2) vs `tickets.ready_requires` (`SPEC-cli` §10,
`SPEC-repo` §12.2, `SPEC-config` §4.4, `SPEC-state` §3.4). Same three headings, two key names, and both
registers declare themselves the contract.

### 8. There are two control planes, in two formats, with two locks and two cadences
**Lives in:** `SPEC-config` §5.1–§5.11 · `SPEC-state` §3.2, §4.3, §4.8, §11 · `SPEC-cli` §2.6, §3.4,
§3.5, §3.6 · `SPEC-repo`.

| | `SPEC-config` §5 | `SPEC-state` / `SPEC-cli` / `SPEC-repo` |
|---|---|---|
| file | `control.yaml`, restricted YAML subset + a vendored ~150-line parser (§5.8) | `control.json` |
| lock | `control.yaml.lock.d/` — a **`mkdir` directory lock** with a holder-identity triple (§5.4) | `control.lock`, a **`flock`** target via `orc-lock.py` (`SPEC-cli` §2.6) |
| reader state | `control.applied.json` (§5.10) | `control.applied.ndjson` (`SPEC-state` §2.2) |
| cadence | `control.poll_seconds: 10` (§4.12) | `tick.control_seconds: 5` (`SPEC-state` §11) |
| shape | typed sections `stop:`/`pause:`/`roles:`/`behaviour:`/`intake:` + flat `overrides:` (§5.3) | a list of entries `{verb, scope, apply}` with `entry_id` (`SPEC-state` §4.3, `SPEC-cli` §3.4) |
| classes | `hard | soft | next-run` (§5.7) | `live | boundary | frozen` (`SPEC-state` §11, `SPEC-cli` §4.1) |

`SPEC-config` §5.4 even says *"All four designs say take `flock`. There is no `flock(1)` on this
machine"* and switches to a directory lock — while `SPEC-state` §5.1 and `SPEC-cli` §2.6 solve the same
verified fact with `python3` + `fcntl.flock` and pin it as *"the primitive"*. Both are correct about the
machine; they are locking different files with different primitives.

A `stop-hard` typed at 03:30 is written by `SPEC-cli`'s command into a file `SPEC-config`'s supervisor
never reads. The acknowledgement loop (both specs' proudest feature — it exists because
FIELD-NOTES §11.2 records two of the owner's own instructions recorded as delivered and never executed)
therefore times out by construction.

### 9. The stop acknowledgement times out whenever it matters most
**Lives in:** `SPEC-work` §12.2 (`when_only_blocked.hold_tick_seconds: 300`) and Appendix A.5 ·
`SPEC-state` §11 (`stop.ack_timeout_seconds: 90`) · `SPEC-cli` §3.4 · `SPEC-repo` §12.8.

The held state — nothing but human-blocked work left, which is exactly the 03:00 state this night
reaches — ticks every **300 s** and *"does exactly two things: poll the questions channel and re-read the
control file"*. The stop command polls for an ack for **90 s** and exits **8** otherwise, printing
*"written, not acknowledged — next: `orchestrator status --probe`"*.

`SPEC-work`'s own Appendix A.5 demonstrates it: entry written 03:30:11, applied 03:35:00. The owner's
every stop, resume and setting change during the held state returns the failure code that is supposed to
mean *the supervisor may be dead*. He will learn to ignore exit 8, which is the one signal the design
spends the most effort earning.

`SPEC-state`'s 5-second control sub-tick would fix it — and `SPEC-work` §12.2's held tick overrides it
with no cross-reference in either direction.

### 10. Teardown walks a file that does not exist; the blast-radius lint guards the wrong name
**Lives in:** `SPEC-safety` §3.3, §6.2 step 4, §6.5, §6.8, §3.9 · `SPEC-cli` §6.1 §6, §8 (LINT-BD1) ·
`SPEC-config` §5.1 · `SPEC-repo` · `SPEC-state` §2.2, §4.1, §4.5, §6.4.

`SPEC-safety` (9 occurrences), `SPEC-cli` (4), `SPEC-config` (2) and `SPEC-repo` (2) name the resource
ledger **`owned.ndjson`**. `SPEC-state` (12 occurrences) names it **`resources.ndjson`** and is the spec
that actually defines its schema, its two-phase `creating → created` protocol, its multi-writer rules,
its per-record `fsync` (*"it is the teardown list, and a lost line is a resource nobody will ever
stop"*), and its seven resource types.

At 05:45 `SPEC-safety` §6.2 step 4 walks `owned.ndjson` in reverse. It is empty or absent. Every compose
project, every worktree and every process group created during the night is left running, and §6.8's
CLEANUP-PROOF prints an empty Part A under a heading asserting that an unauthorised destruction is
*"unreachable"* — which is true, and useless, because no destruction happened at all.

Worse, the build-failing lint that is the whole safety story — *"no teardown command may be constructed
from an environment variable — **every identifier in a teardown command comes from a field in
`owned.ndjson`**"* (`SPEC-cli` §8 LINT-BD1, `SPEC-safety` §3.9 rule 6) — names `owned.ndjson`. A
teardown built from `resources.ndjson` passes the lint by not being the file the lint knows about. The
recorded incident this lint exists for (FIELD-NOTES §11.5: `docker compose down -v` with
`COMPOSE_PROJECT_NAME` absent destroying the owner's own stack) is not covered by the rule as written.

### 11. Six state roots, four run-id formats, three `index.tsv` shapes — `status` cannot find the run
**Lives in:** `SPEC-cli` §2.4, §3.2 step 4 · `SPEC-config` §5.1 · `SPEC-state` §1.1, §2.1 ·
`SPEC-work` §1.2 · `SPEC-adapters` §1.3, §14 · `SPEC-safety` §3.2 · `SPEC-repo` §12.1.

**Roots:** `$ORCH_HOME` (undefined) · `${ORCHESTRATOR_STATE_DIR:-$HOME/.orchestrator}` ·
`${ORCHESTRATOR_STATE_DIR:-$HOME/.local/state/orchestrator}` ·
`<config-root>/shared/orchestrator/state/<project-key>` (**frozen** key `state.root`) ·
`<config-root>/orchestrator/state` · `$HOME/.orchestrator` (**frozen** key `orchestrator.home`). Two of
the six are `frozen`-class keys with different names and different values, so they cannot be reconciled
at run time by configuration.

**Run ids:** `<work-project>-20260919-224100Z-a7f3` (`SPEC-state` §1.1, 4 hex to close the same-second
collision) · `<work-project>-20260919-224100Z` (`SPEC-cli` §3.2 step 4, no hex) · `20260919-210411`
(`SPEC-adapters` §1.3, no slug, no hex) · `20260919T231204Z-a7f3c1` (`SPEC-safety` §7, 6 hex, `T`
separator) · `20260919-214000` (`SPEC-engine` §7.2).

**`index.tsv`:** 7 columns with `epoch` (`SPEC-state` §2.1) · 6 with `pid` (`SPEC-cli` §2.4) · 5
(`SPEC-config` §5.1, `SPEC-work` §1.2).

`SPEC-cli` §2.4's addressing algorithm — the one path every command takes — reads column 2 for the
project root and column 5 for the state out of a file three specs write differently, under a root it
never defines. At 04:30 `orchestrator status` exits **4**, `no run for /path`, while the run is alive.

### 12. Eleven commands are referenced by other specs and defined by none
**Lives in:** `SPEC-cli` §3 (the twelve defined) vs `SPEC-config` §5.5 step 10, §5.15, §6.1 ·
`SPEC-work` §3.1, §5.1, Appendix A.5 · `SPEC-state` §2.3, §4.8, §5.6 · `SPEC-safety` §2.6, §6.8 ·
`SPEC-adapters` §12 · `SPEC-engine` §16.3 · `SPEC-repo` §9.2, §13.5.

Defined: `config run status stop-hard stop-soft stop-custom resume add ask report sync remove`.

Referenced and undefined: `orchestrator:set` (`SPEC-work` A.5 — the exact command the owner is told to
type at 03:30) · `orchestrator:pause` and `orchestrator:resume` as control writers (`SPEC-config` §5.5)
· `orchestrator:doctor` (`SPEC-config` §5.5 step 10's failure message, `SPEC-state` §4.8) ·
`orchestrator:init` and `init --rules` (`SPEC-state` §2.3, `SPEC-config` §5.1, `SPEC-safety` §2.6 —
printed in a preflight refusal) · `orchestrator:connect` (`SPEC-work` §3.1, the only place the board is
probed) · `orchestrator:show <id>` (`SPEC-work` §5.1, the only way to read the local log trail) ·
`orchestrator:status --proof` (`SPEC-safety` §6.8 Part D) · `orchestrator:adapter verify <id>`
(`SPEC-adapters` §12, and the remedy printed in a version-mismatch refusal) ·
`orchestrator:engine verify <id>` (`SPEC-engine` §16.3) · `config migrate-tickets` (`SPEC-repo` §9.2,
§13.5) · `config --audit`, `--promote`, `--explain`, `--doctor`, `--check`, `--import-harness`
(`SPEC-config` §6.1, none of which appear in `SPEC-cli` §3.1's flag table).

Every refusal message that ends *"run X to fix it"* is a dead end, and `SPEC-adapters` §10.2 is explicit
that *"a refusal the owner cannot act on in one command at 22:00 is a refusal that will be disabled."*

### 13. No spec assigns a ticket to a platform
**Lives in:** `SPEC-state` §3.2 step 7 · `SPEC-adapters` §9.4, §18 · `SPEC-work` §4.3 · `SPEC-repo` §12.

The dispatch step is one clause: *"while `live_lanes < max_lanes` and capacity allows and a ready ticket
exists — claim, launch."* `SPEC-adapters` §9.4 is an admission **test** on a candidate — it answers
*may this lane take one more* — and §18 explicitly defers *"the run state machine, the tick loop, the
judge and the liveness governor"* to an **orchestration spec that does not exist in this set**.

Undefined, on a night with six tickets and three heterogeneous platforms:
queue order (id? arrival? dependency depth? none is stated) · lane affinity (does a retry go back to the
platform that failed it?) · whether a ticket may move platform between attempts, and what that does to
`engine_ref` and to the session lineage · how the deferred lane (finding **6** of `SPEC-adapters` §9.6's
worked example) ever gets work when the two others are permanently busy · whether `Role.max_concurrent`
(`SPEC-adapters` §1.8: executor `2`) and `concurrency.max` (`2`) are the same ceiling counted once or two
ceilings counted twice.

This is the single largest hole in the set: the thing the plugin is *for* has no algorithm.

### 14. Wall-clock lane timeouts contradict the mono-only rule, across the exact 20 minutes that matter
**Lives in:** `SPEC-state` §1.2, §3.6 (`timeout.wall`), §6.2 step 8 and the `start.json` example
(`timeout_s: 14400`), §9.2 code 3 · `SPEC-adapters` §5.1, §5.6 (`lane.max_seconds: 3600`), §7.3, §14.

`SPEC-state` §1.2: *"**Every duration in the system is computed on `mono`.**"* … *"Never subtract two of
these [wall clocks] to get a duration."* The sleep fence (§5.8) is built entirely on this, and it is why
FIELD-NOTES §10.1 becomes unreachable.

`SPEC-adapters` §5.1: *"Every timeout is an **external wall clock** imposed by the core."*
§5.6: `lane.max_seconds: 3600`. `SPEC-state` §6.2's canonical `start.json`: `timeout_s: 14400`.

At 04:02 a lane is 3h40m into a 4h budget. The machine sleeps 20 minutes. Under the wall-clock reading it
is killed at 04:22 having done 3h40m of work; under the mono reading it has 20 minutes left. `SPEC-state`
names the cause `timeout.wall`, so the wall reading is the one the journal is built for — and it is the
one §1.2 forbids. The two numbers, 3600 and 14400, differ by a factor of four and both are
DEFAULT-PROPOSED in registers that each claim *"nothing outside this table may invent a default."*

### 15. The question path specifies two opposite behaviours on the platform he will actually run
**Lives in:** `SPEC-state` §3.3, §9.3, §11 (`questions.answer: when_native`) · `SPEC-adapters` §5.10,
§14 (`questions.native_tool: disallow-headless`, `questions.authority: refuse-and-escalate`) ·
`SPEC-work` §9.5, §13.3 · `SPEC-repo` §12.8.

`SPEC-state` §9.3 builds the whole terminal-question design on *"on the lane the owner is most likely to
run tonight, a question the session asks **cannot be answered by anything**"*: exit 5, lane terminal,
task `blocked`, new lane on answer.

`SPEC-adapters` §5.10 ships the default that removes that premise: *"where the platform cannot be
answered programmatically in the mode we are running (Claude Code `--bg`, DeepSeek SDK lane, Gemini
headless), the core **injects its own `ask_supervisor` tool and disallows the platform's native ask**"*,
explicitly *"to preserve [324] instead of trading it away."*

Under (A) the lane ends and the ticket waits until 09:12. Under (B) the orchestrator answers within its
authority at 02:41 and the ticket finishes overnight. These are different products. Nothing chooses.

And `ask_supervisor` is a name with no referent: no spec defines its JSON schema, how it is injected into
a `claude -p --output-format stream-json` process, how its calls surface in the 28-kind normalised event
vocabulary (`SPEC-adapters` §7.2 has `question.raised`/`question.answered` but no tool-injection kind),
or what happens when the model ignores it and asks in prose.

### 16. `questions.channel` has no default, and nothing can ask for one at 22:00 headless
**Lives in:** `SPEC-work` §9.2, §13.4 · `SPEC-repo` §12.8 · `SPEC-cli` §3.1 (MR-15), §3.2 ·
`SPEC-state` §9.3 step 4, §2.3.

`questions.channel` ships **unset**; `SPEC-work` §9.2 says *"preflight asks once"* and §13.4 says
*"every question this component can ask is asked at `connect` or `preflight`, never during a run"*.
`SPEC-cli` §3.1 makes the config verb **fail closed to non-interactive** on ambiguity and §3.2's `run`
algorithm contains no asking step at all. `orchestrator:connect` does not exist (finding **12**).

So a run started from a script, a cron, a hook, or `claude -p` — the unattended case the whole product is
for — starts with no channel. At 02:41 `SPEC-state` §9.3 step 4 says *"a pending-question record is
written to the Д6 channel"* and specifies no branch for its absence. The question exists in
`questions/<qid>.json` (`SPEC-work` §9.6's mirror) and reaches nobody; `when_only_blocked: wait` with
`wait_max_minutes: 0` then keeps the run alive forever waiting for an answer to a question that was never
posted anywhere a person looks.

`SPEC-work` §9.2 offers `<project>/.orchestrator/QUESTIONS.md` *"as the suggestion preflight offers, not
as a silent default"*. That distinction costs the night. Making it a real default with a printed line
would cost nothing and is what `SPEC-adapters` §8.8 does for `capacity.reserve_pct`.

### 17. "Three failures, then stop" — four key names and three different things stopping
**Lives in:** `SPEC-engine` §8.5 · `SPEC-repo` §12.5 · `SPEC-state` §3.4, §11 · `SPEC-cli` §4.1, §10 ·
`SPEC-work` §4.6.

Keys: `failures.identical_threshold` + `failures.on_exhausted` (engine) · `failures.repeat_threshold` +
`failures.action` (repo) · `failures.repeat_threshold` + `failures.count_blocked_on_human` (state) ·
`failures.*` named as a Live class with no members (cli §4.1) and deferred to a sibling spec (cli §10).

Behaviour at 02:30, after T-102's third identical failure:
- `SPEC-state` §3.4: the task stays `failed` and *"is parked"*. The run continues. T-101, T-103, T-105 and
  T-106 finish.
- `SPEC-engine` §8.5 and `SPEC-repo` §12.5: `notify_and_stop`. If that is the run, four tickets die
  because one was flaky. If it is the lane, it is a no-op — the lane already ended.
- `SPEC-engine` §8.5 also records the owner's own words: *"**Recorded as his, not decided here:** *when*
  the rule fires — «В який момент не знаю» [442]"*, and then ships a default anyway without naming the
  scope.

This is a decision the owner explicitly declined to make, and the specs have shipped three answers to it
rather than one question.

### 18. The `finish_then_new` pending action has no defined behaviour on a failed or retried lane
**Lives in:** `SPEC-work` §10.5, §4.3 step 8, Appendix A.3 · `SPEC-state` §3.3, §3.4.

`change.on_contradiction: finish_then_new` is the shipped default and its mechanism is
*"a pending action is recorded on `items/0412.json`: `{on_harvest: "supersede", anchors: ["#2"]}`"*,
fired when the lane reaches HARVEST.

Unspecified, and all three cases occur on an ordinary night:
- The lane **fails** (T-102's shape). No harvest, no fire. Is the pending action dropped, or does it
  survive to attempt 2? Nothing says. If it survives, it will supersede a ticket against criteria the
  retry has already implemented.
- The lane **retries**. §4.3 step 8 recomputes `spec_digest` from the current file at claim time, so
  attempt 2 works against the **new** spec — which is the `adapt` branch's behaviour arriving by accident
  inside the `finish_then_new` branch, and it makes the supersede a duplicate of work already done.
- The lane is **stopped** by the owner. `stopped` is terminal and is not `harvesting`; the action never
  fires and the owner's 02:00 edit silently evaporates.

### 19. An edit to a question-blocked item re-claims it with the question still open
**Lives in:** `SPEC-work` §10.1, §9.5 Tier C, §9.6, §2.5 · `SPEC-state` §3.4.

`SPEC-work` §10.1: *"`if item.role == needs-input` → re-run FLOOR. Pass → `ready`."* That branch makes no
reference to the item's open question. The claim was deliberately **held** (§A.4: *"rmdir the claim? NO.
The claim is held; the item is parked"*), so §4.3 step 5's `mkdir` returns EEXIST and the re-claim SKIPs
— unless the reclaim path in §4.5 step 1 refreshed it as ours, in which case the interaction between
"held claim" and "role back to ready" is undefined in both directions.

If it does re-claim: a second attempt starts on a ticket whose blocking question (*"which of the two auth
flows is canonical?"*) is unanswered, the mirror still says `Status: open`, and when the answer lands at
09:12 Tier C moves the item to `ready` a third time. Nothing closes the question when the item leaves
`needs-input` by a route other than an answer.

### 20. The three "this table is the contract" registers contradict each other on live values
**Lives in:** `SPEC-state` §11 · `SPEC-adapters` §14 · `SPEC-repo` §12 · `SPEC-cli` §10 · `SPEC-work`
§12.2 · `SPEC-safety` §10 · `SPEC-config` §4 · `SPEC-engine` §17.

Seven registers, each asserting *"nothing outside this table may invent a default at run time"*, each
backed by a build-failing test (`DEF-1`, `O-31`, `G6`). Sampled conflicts, all on keys this night reads:

| Knob | Values / names in conflict |
|---|---|
| soft capacity threshold | `capacity.soft_pct: 85` (adapters §8.6, §14) vs `80` (repo §12.3, config §4.7 — and repo marks 80 *"**his own number** [171]. Not proposed — stated"*) |
| context refill alarm | `context.refill_rate_alarm: 15 %/h` (adapters §5.12.1, §14) vs `ctx_refill_alarm: 20 %/h` (repo §12.4) |
| context threshold | `context.percent` per role 75/85/66 (adapters §5.12.2) vs `context.raw_pct_threshold: 75` (repo §12.4, cli §10) |
| global lane cap | `concurrency.max` (adapters §9.4, §14) vs `concurrency.max_lanes` (cli §3.2, §10; repo §12.1) |
| readiness headings | `tasks.ready_requires` (work §12.2) vs `tickets.ready_requires` (cli, repo, config, state) |
| capacity cache | `capacity.cache_seconds: 900` (repo §12.3) vs `capacity.poll_min_seconds: 3600` + `capacity.max_age_seconds: 5400` (adapters §8.5, §14) |
| live adapter verify | `adapter.verify_max_age_hours: null` — *"never on a calendar"* (adapters §12.1, §14) vs `0` — *"verify at every run start"* (repo §12.7) |
| doctor | `doctor.enabled: false` (state §11, repo §12.8) vs `auto` (cli §10, a third value neither other spec defines) |
| `run.mode` apply class | `frozen` (state §11) vs `boundary` (repo §12.1) vs `next-run` (config §5.7) |
| `run.mode` domain | `controlled | autonomous` (cli §3.2) vs three values incl. `ask` (state §5.6 rationale, repo §12.1) |
| `harvest_evidence` | `project`/`boundary` (state §11) vs `run`/`live` (repo §12.6) |
| `when_only_blocked` | `when_only_blocked` + `wait_max_minutes` (state, repo) vs `when_only_blocked.max_minutes` + `.hold_tick_seconds` (work §12.2) vs `behaviour.when_only_human_blocked` (config §5.3) |

The `adapter.verify_max_age_hours` row is the sharpest: `0` means the **live** half runs at every run
start — *"one short session + one capacity call per adapter"* (`SPEC-adapters` §12.1). With three
adapters that is three capacity calls at 22:41, against a channel `SPEC-adapters` §8.5 rule 2 measured as
*"calls 1–2 succeeded, calls 3–8 returned `rate_limit_error`"* with a recovery still limited at t+167 s.
The verification step exhausts the budget the run needs to schedule itself.

### 21. Exit codes collide on the outcome this night actually produces
**Lives in:** `SPEC-state` §9.1 · `SPEC-safety` §6.9 · `SPEC-cli` §2.5 (and its build-failing `EXIT-1`) ·
`SPEC-config` §5.5 · `SPEC-work`.

`degraded` — work happened, at least one resource could not be proven gone — is **exit 4** in
`SPEC-state` §9.1 and **exit 6** in `SPEC-safety` §6.9. `SPEC-cli` §2.5, the table that says *"No command
exits with a code outside this table"* and enforces it at build time, assigns **4 = NO_RUN** and
**6 = WRONG_PHASE**.

Other collisions in the same three tables: `SPEC-state` 5 = `blocked` (the question-is-terminal case) vs
`SPEC-cli` 5 = STALE. `SPEC-state` 69 = lease held vs `SPEC-cli` 69 = UNAVAILABLE/preflight refused vs
`SPEC-safety` 69 = project lock held. `SPEC-state` 77 = preflight refused vs `SPEC-cli` 77 = NOPERM
(red line) vs `SPEC-safety` 78 = preflight refusal. `SPEC-config` §5.5 exit 65 for a parse failure vs
`SPEC-cli` 65 unassigned.

A wrapper script that branches on the exit code — which `SPEC-cli` §2.5 explicitly designs for
(*"A shell user's `cmd || handle` idiom must not treat 'a human is needed' as a crash"*) — reads a
degraded night as either "no such run" or "wrong phase".

### 22. The judge is specified nowhere, and its record has two homes
**Lives in:** `SPEC-adapters` §18 · `SPEC-state` §3.2 step 6, §4.3, §15 · `SPEC-repo` §12.5 ·
`SPEC-cli` §3.3, §5.1 · `SPEC-engine` §9.3 step 7.

`SPEC-state` §3.2's tick step 6 is one sentence — *"render **one** fact sheet with **all** open items and
make **one** model call"* — and §15 removes it from scope: *"Not covered here, by scope: … the judge's
fact sheet and prompt."* `SPEC-adapters` §18 defers it to *"the orchestration spec"*. `SPEC-repo` §12.5
ships ten `judge.*` defaults and no algorithm. No spec in the set defines: what a fact sheet contains,
what the model is asked, what verdict vocabulary it may return, how `run.mode: controlled` constrains it,
how `judge.on_unparseable: defer` interacts with a deferred lane, or what `liveness.silence_minutes: 20`
is measured against (`mono`? event-file mtime? both?).

At 03:15, when a lane has been silent for 22 minutes because the machine is about to sleep, the only
component that can decide *stop, wait, or adopt* — a decision `SPEC-state` §7.3 and Д10 [497] both hand
to it explicitly — has ten tuning knobs and no body.

Its record has two homes: `SPEC-state` §4.1 puts `decisions` **inside `journal.ndjson`** as a record
kind; `SPEC-cli` §3.3 reads `<run>/decisions.ndjson` for `--why`. `orchestrator status --why <lane>` at
03:00 reads a file the journal spec says does not exist.

### 23. The default notification channel reaches nobody, and the design knows it
**Lives in:** `SPEC-cli` §7.1, §7.2, §7.3, §10 · `SPEC-repo` §12.8 · `SPEC-state` §9.3 step 8.

`notify.channels` defaults to `{"terminal": {"kind": "terminal"}}` and `notify.required: true`.
The `terminal` kind's `send.sh` *"appends one line to `journal.ndjson` and pushes onto
`status.json.attention[]`"*. It *"always verifies"*, so tier 1, tier 2 and preflight all pass.

Tonight's five notify events — the quota wall at 01:10, the third failure at 02:30, the question at
02:41, `only_blocked_work_left` at 03:12, and the degraded teardown at 05:45 — all land in a JSON file on
a sleeping laptop. `SPEC-cli` §7.2 is explicit that the alternative was worse (*"`none` + wait-forever +
silence = an indefinite block nobody is told about"*), and §12 Q3/Q4 put the real question to the owner.
But the shipped default satisfies `notify.required: true` while delivering nothing, which is exactly the
shape of failure the three verification tiers exist to prevent — the *"tier-1-only check refused as
proof"* rule (§7.3) applied to credentials and not to reachability.

### 24. `--max-lanes 2` with three configured lanes starves one platform for the whole night
**Lives in:** `SPEC-adapters` §9.4 steps 5–6, §9.5, §9.6, §14 · `SPEC-state` §3.2 step 7 · `SPEC-repo`
§12.1.

`concurrency.max: 2` is global across every lane. With three platform lanes, one is always deferred.
`concurrency.deferred` makes the deferral **visible** (§9.5's whole purpose) but nothing makes it
**temporary**: there is no ageing, no round-robin, no per-lane starvation bound. `SPEC-adapters` §9.6's
own worked example says *"the ticket stays claimable so another lane on another provider may take it"* —
which describes a scheduler that does not exist (finding **13**).

Two further ambiguities in the counting: step 5 says *"Count live sessions matching `key` **from the
ledger, not from a roster**"* and no spec defines which of `SPEC-state` §3.5's seven session states
(`planned | named | unnamed_window | live | ended | lost | superseded`) count as live — `unnamed_window`
is a session that exists and cannot be named, and counting it wrong on a contractual GLM ceiling is the
difference between a deferral and a banned account. And `Role.executor.max_concurrent: 2`
(`SPEC-adapters` §1.8) may be the same ceiling as `concurrency.max: 2` counted once, or a second ceiling
counted twice; nothing says.

### 25. The teardown's sleep fence blocks the tick; the state spec's does not
**Lives in:** `SPEC-safety` §6.2 step 2 · `SPEC-state` §3.2, §3.7, §5.8 · `SPEC-adapters` §7.3.

`SPEC-safety` §6.2 step 2: *"append `machine.wake` and **wait `sleep.grace_seconds` (120)** before
proceeding."* `SPEC-state` models the identical fence as a non-blocking state — `running → paused`
(`wake.detected`), `paused → running` (`wake.grace_expired`) — precisely so the control sub-tick keeps
running. If the 04:22 wake lands during `finishing`, the supervisor blocks for two minutes inside its own
tick, reading no control file and answering no stop. INFERRED, but the two texts are unambiguous.

### 26. Board write-back is `true`, `false` and "frontmatter only" for the same local registry
**Lives in:** `SPEC-work` §5.1, §12.2 · `SPEC-state` §3.4, §11 · `SPEC-repo` §12.2 · `SPEC-config` §4.4.

`SPEC-work` §12.2: `board.writeback: true`, *"on `local` it means the frontmatter key only"*, and §5.1
puts the trail in `${STATE}/projects/<pkey>/items/<id>.log.md`.
`SPEC-state` §11 and `SPEC-repo` §12.2: `board.writeback` is **`true` for a board source, `false` for the
local registry**, and `SPEC-state` §3.4 point 4 says *"The orchestrator still **never writes into a work
item's own body** on the local registry… the ticket file is read-only."*

With `false`, the frontmatter `role:`/`status:` key is never written, so the ticket the orchestrator is
working on still reads `ready` — and `SPEC-work` §2.1 makes `active` *"**orchestrator only**"* and the
floor's `ready → active` transition (§2.5) the thing that stops a second claim. On a crash-and-restart
(Д10 [497], an expected event per R1-10 [300]) the project-scoped claim directory is the only defence
left, and finding **5** shows the two specs disagree about where that directory even is.

---

## 3. What survives

Stated plainly, because a red team that finds only faults is not reporting a night.

- **The sleep fence** (`SPEC-state` §5.8, `SPEC-adapters` §7.3) is correct and is the one place the
  previous generation's terminal failure is genuinely unreachable. `mono` + `boot` + a grace window is
  the right shape, and three specs agree on the numbers (60 / 120).
- **The lease** (`SPEC-state` §5.1–§5.7) is the strongest section in the set: a `flock` with no TTL, a
  split-brain check that fails closed, a read-side fence in the fold that makes the guarantee
  structural rather than cooperative, and an honest table of what it does not cover.
- **The claim as `mkdir`** is measured (1 winner of 50, both `SPEC-state` §1.3 and `SPEC-work` §4.1) and
  right, in both specs, independently.
- **Evidence-gated `ok` on mutating ops** (`SPEC-state` §4.4 R4, `SPEC-work` §5.5) closes the
  "reported success and did nothing" class in about fifteen lines, and `ops.json` as data rather than
  code keeps it from rotting.
- **The three-value capability vocabulary** (`native | emulated | impossible`, plus `undocumented` and
  `unknown` in `SPEC-adapters` §4.3) with `negotiate.on_unknown: impossible` makes a neglected adapter
  fail *forward*. `SPEC-adapters` §6.4's ordering argument is the best single paragraph in the set.
- **`plan.json.weakened[]` / `denied[]`** naming the owner's item that stopped holding tonight is the
  right answer to a real problem and appears, consistently, in four specs.
- **Д8's three tiers** (`SPEC-work` §8.1) turn a $14/night watcher into $0.01 with a deterministic
  silence that is achieved rather than hoped for. That is the cleanest piece of engineering in the set,
  and finding **7** means it never runs.

## 4. The shortest path to a survivable night one

In order, because each unblocks the next:

1. **One object model.** Rename `SPEC-adapters`'s `Lane` (it is not the owner's word by its own
   admission, §16.1) and settle `lanes/` — findings **1**, **13**, **24**.
2. **One vocabulary for a work item.** Merge `SPEC-work`'s five roles and `SPEC-state`'s eight task
   states into one table with one transition file — findings **6**, **7**, **26**.
3. **One control plane, one ledger, one root, one run-id, one exit table** — findings **8**, **10**,
   **11**, **21**.
4. **Per-account capacity states**, and a bootstrap exemption for an unprovable standby — findings **2**,
   **3**, **4**.
5. **Write the scheduler and the judge.** Both are referred to as existing and neither exists — findings
   **13**, **22**.
6. **Merge the seven defaults registers into one file** and make `DEF-1` read it — finding **20**.

Nothing in 1–6 is a design change. Every one of them is a reconciliation the eight specs left to whoever
builds them, and every one of them fails on the first night rather than on the hundredth.
