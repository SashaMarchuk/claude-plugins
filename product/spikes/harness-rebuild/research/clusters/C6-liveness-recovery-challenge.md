# C6 — Liveness, stalls, orchestrator death, resumable state · ADVERSARIAL CHALLENGE

Cluster items: **R1-09**, **R1-10**, **R1-06 part 3**, **Д10**.
Written 2026-09-19 against `C6-liveness-recovery-research.md`, `round-1/TRANSCRIPT-01.md`,
`round-1/ANALYSIS-01.md` and `plugins/harness/docs/FIELD-NOTES.md`.

**What this document is.** Twelve attacks on the owner's C6 decisions, kept after I tried to kill each
one myself. Every attack names a concrete failing situation, an undefined term two implementers would
build differently, a collision with another of his own decisions, or a collision with the previous
generation's measured behaviour. **No attack proposes a replacement decision.** Where his decision
stands and only a gap is named, that is deliberate.

**Evidence grading.** VERIFIED = read in source, a primary doc, or measured on this machine (by the C6
research, whose measurements I did not re-run; where I rely on one I say so). CLAIMED = an
implementation's own doc asserts it. INFERRED = my reading.

**Ratification reminder, carried from the research and not re-litigated here.** Only two sentences in
this cluster were confirmed by the owner: R1-10's launch-journal/prove-dead/no-two-orchestrators
statement («Та, правильно» [304]) and R1-07's role-restricted accounts («Підтверджую» [279]). R1-09,
the health check, the recovery sources, the per-platform recovery and Д10 were all recorded over
half-finished sentences. Several attacks below bite hardest precisely because the unratified parts were
never read back.

---

## Severity summary

| # | Attack | Decision attacked | Severity |
|---|---|---|---|
| A1 | The health checker on another account is structurally blind to the orchestrator's account | R1-10 health check | **blocker** |
| A2 | «Переконуєш що воно не спрацювало» has no third verdict for *I could not look* | R1-10 invariant | **blocker** |
| A3 | A *planned* orchestrator replacement (R1-08 compaction) is not covered by the invariant | R1-10 invariant × R1-08 | **blocker** |
| A4 | R1-09 delegates the judgement and leaves no admissible signal to judge on | R1-09 | **blocker** |
| A5 | macOS sleep makes every liveness signal lie simultaneously — and it is how the last run died | R1-10, [249] | major |
| A6 | «Не повторювати роботу» is undefined at the step that was in flight | R1-10 "start over" | major |
| A7 | Reference-only accounting points at a claim, not a witness | R1-06 p3 [189] | major |
| A8 | A restarted orchestrator cannot tell its own executors from the owner's work | Д10 × R1-16 | major |
| A9 | Nothing checks the checker, and the checker's own quota is the run's named death mode | R1-10 health check | major |
| A10 | The N-hour window is longer than every failure the previous run actually suffered | R1-10 health check | major |
| A11 | Per-platform recovery config asks the user a question he has no way to answer | R1-10 [310]/[312] | major |
| A12 | The invariant is scoped to one run and says nothing about the second run on the same machine | R1-10 [300] | major |

---

## A1 — The health checker on a separate account is structurally blind to the orchestrator's account, so the mechanism that protects the run is the shortest path to the state he called «не окей» · **BLOCKER**

**The decision.**

> **[246]** «…запускати якогось агента раз в N годин на **якійсь іншій підписці** або з різними
> варіантами, які підписки можуть включитися… аби це було якось детерміністсько в результаті, і щоб,
> якщо ран зупинився через помилку, те що, наприклад, код лежить, то щоб використати якийсь фоллбек»

> **[266]** «…має бути щось, що може допомогти **запустити ран і продовжити роботу без участі в
> налаштуваннях користувача»**

**The collision, in his own words.**

> **[300]** «не може бути такого, що вже якісь існуючі оркестратор і спускається наступний, тому що
> тоді це буде просто **нескінченний цикл оркестраторів**… якщо раптом одночасно два якісь оркестратори
> працюють, то це **не окей**»

**The attack.** The checker is on a *separate account* and has *authority to start the run*. Its
only way to ask "is the orchestrator alive?" using its own tooling is scoped to its own account.
VERIFIED by the C6 research on this machine: `claude agents --json` run under two `CLAUDE_CONFIG_DIR`
profiles within seconds of each other returned **completely disjoint interactive rosters** — one
profile saw four sessions, the other saw four different ones, and neither could see the
other's. A liveness probe run under the wrong account does not return "alive elsewhere"; it returns
**nothing**, which reads identically to "dead".

**Concrete failure.** 03:40. The orchestrator runs on account `<profile-A>`. It is alive and holding a
rate-limit wait — his own named death mode is the adjacent one, «кредит закінчився, тижневий ліміт»
[266], and a credit-exhausted or rate-limited orchestrator is *paused*, not dead. Its last journal
write is three hours old because it is waiting, not working. The N-hour checker wakes on account
`<profile-B>`, runs its roster probe, sees four sessions, none of them the orchestrator, reads «стан
останнього запису» [249] as three hours stale, and concludes dead. Per [266] it starts a replacement
**without the user in the loop**. Two orchestrators of one run are now alive. At 05:10 the original's
rate-limit window resets and it resumes mid-turn. Both merge phase 12; both write ticket comments
(R1-04 [149] makes the board a working surface the orchestrator writes to); both spawn a worker on the
next ready ticket. FIELD-NOTES §11.8 shows how quietly this ends: a lane slug reused from an earlier
wave spawned a worker into a **stale worktree with a stale prompt**, and GSD computed a branch name one
word off the real lane branch and would have **cut a fresh branch from `origin/master` and lost the
merged master tip**.

**What is undefined.** Nothing in [246] says the checker must probe *as the orchestrator's account*.
Two implementers: one runs `claude agents --json` with its own env (and spawns a duplicate every time
the accounts differ, which is the normal case, since the whole point of [246] is that they differ); one
records and replays the orchestrator's env. Same decision, opposite outcomes.

**Why the attack survives my own scepticism.** I tried to dismiss it as an implementation detail. It is
not: the accounts differing is not an accident of implementation, it is the *requirement* — [246] says
«на якійсь іншій підписці» and [270] restricts accounts by role («може використовувати **тільки для
оркестратора**… І це важливий дуже нюанс»). The design mandates the exact condition that makes the
probe blind.

---

## A2 — «Переконуєш що воно не спрацювало» has only two verdicts, and the third one happens every night · **BLOCKER**

**The decision, ratified.**

> **[300]** «Якщо, наприклад, запустився оркестратор, або щось запустилось, але воно не спрацювало,
> **переконуєш що воно не спрацювало, а після того запускаєш новий**»
> **[301]** «Це треба **відслідковувати і не дозволяти**» · **[304]** «Та, правильно»

**The attack.** The rule admits *convinced it is dead* and *not convinced*. It says nothing about
**"the probe errored"**, and the probe erroring is not an edge case in this system — it is the recorded
norm.

- VERIFIED by the C6 research **today**: the Anthropic OAuth usage endpoint returned **HTTP 429** to a
  well-formed authenticated request.
- FIELD-NOTES §11.7: `weekly_all=unreadable%` recurred across **many separate days** — six consecutive
  ticks on 2026-09-06, more at 08:36 and 22:48–23:03, single ticks on the 9th, 10th and 11th.
- FIELD-NOTES §11.7: the usage endpoint returned `authentication_error` **for an extended stretch**,
  «blinding every cap read, with nobody re-authenticating», 2026-09-02T13:52–15:14Z.
- FIELD-NOTES §11.3: a detector probe (BSD `find -newermt`, stderr to `/dev/null`) *"could never succeed
  and never complained"* and *"would have declared every healthy session idle for ever."*

**Concrete failure, both branches, and both are bad.** 04:12, the checker's probe errors — expired
token, 429, a platform with no probe configured (A11), a roster read under the wrong account (A1).
*Branch one:* the implementer mapped error→dead, because [300] offers no other bucket and the run must
not sit still. Second orchestrator spawns onto a live run. *Branch two:* the implementer mapped
error→not-convinced, so nothing starts. The orchestrator actually **was** dead at 02:50. The owner opens
the laptop at 08:00 to five hours of nothing, which fails R1-01's «ніч вдалася» outright. Neither
implementer violated a single word he said.

**What is undefined.** (a) The third verdict does not exist in his vocabulary. (b) The timeout after
which "cannot tell" becomes "dead" — his [249] «стан останнього запису» names the *signal* and never
names a *threshold*, and he explicitly refused thresholds in R1-09. (c) The fail-safe direction. The
research proposes UNKNOWN→wait→DEAD-after-3×TTL; he has never seen or ruled on it.

**Sharpening.** He did give a direction indirectly: [300] «якщо раптом одночасно два якісь оркестратори
працюють, то це не окей» is an *absolute*, and «ран зупинився» [246] is a *problem to be solved*. Read
strictly, an absolute outranks a problem, so error→wait follows. But that reading makes the run's
availability hostage to a 429 from a quota endpoint the run does not control — and FIELD-NOTES §11.7
records that exact blindness lasting **an hour and twenty minutes** once and recurring on six
consecutive ticks another time. He should be made to say which he is choosing, because the two readings
produce different products.

---

## A3 — The invariant covers orchestrator *death*. It does not cover the orchestrator being *replaced on purpose*, which his own R1-08 decision requires · **BLOCKER**

**The two decisions, both his, both confirmed.**

> **[204]** «…це може налаштовуватись, таким чином, що оркестратор можна **як компактити, так і
> запускати повністю новий оркестратор**, що також може бути окей, і людина може це налаштовувати…
> І якщо, наприклад, оркестратор наблизився до того числа, ну або, чи перейшов це число, то **повинен
> бути механізм, який гарантовано робить цю дію**»

> **[300]** «якщо раптом одночасно два якісь оркестратори працюють, то це не окей»

**The attack.** R1-10's invariant and its launch journal are written entirely in the vocabulary of
failure — «якщо… воно не спрацювало», «переконуєш що воно не спрацювало». A context-threshold handover
is not a failure: the outgoing orchestrator is **healthy, busy, and about to be replaced by a process
it launches itself**. There is a window in which both exist, and no decision in this cluster governs
it. Worse, [204] demands the replacement be *guaranteed* to happen — a guarantee that pushes an
implementer toward "spawn the successor first, confirm later", which is the two-orchestrator state by
construction.

**Concrete failure.** 02:30, the orchestrator crosses its configured 90% context threshold. Config says
*start a completely new orchestrator* rather than compact. The successor boots, reads the position file
and starts scheduling. The predecessor is mid-turn on a merge it began forty seconds ago; it has not
exited, and it cannot — FIELD-NOTES §1.1: **a session cannot compact itself**, and §1.2: `/compact`
lands only when the target has no shell running. Its turn ends at 02:37 (J-WATCH-01 measured the
compact-in-place procedure at **about seven minutes**, 67% → 0%) and it resumes the schedule it was
holding in memory. For seven minutes, two orchestrators of one run both hold live schedules. FIELD-NOTES
§11.8 supplies the outcome shape: `pkill -f 'playwright test'` killed an **unrelated lane** because
every lane's prompt contains that literal string — two schedulers issuing kills over overlapping pattern
sets is that failure with two authors.

**A second, quieter form of the same hole.** FIELD-NOTES §1.6: `q-screen-orchestrator`, a question-role
session, *"stayed registered and idle for one day and four hours"* because *"the orchestrator that
spawned it had moved on"*, and its terminal title read `harness-question-q-screen-orchestrator` — which
**the product owner himself read as a second orchestrator**. The invariant needs to say what counts as
"an orchestrator" before it can forbid two of them, and nothing in the transcript defines that.

**What is undefined.** Whether the handover is fenced (predecessor must be provably gone before the
successor claims), whether the successor inherits the lock or takes a new claim, and what the
predecessor does if it wakes to find its claim superseded. Two implementers build two different
products, and one of them ships the thing he called «не окей».

---

## A4 — R1-09 delegates the judgement and leaves the orchestrator with no signal it is allowed to judge on · **BLOCKER**

**The decision (unratified — [238] «Гаразд, зафіксував» landed on a half-finished sentence).**

> **[231]** «Агент сам повинен це вирішувати, тобто він дивиться, перевіряє ті сесії, які він запустив,
> **які в них прогрес, що вони там зробили**, тощо так далі. І відповідно до цього діє»

**The attack.** «Прогрес» and «що вони там зробили» are not observables. Every cheap observable
available on this machine has a **measured false-positive mode in his own run**:

| Signal | What his own logs recorded |
|---|---|
| heartbeat age | FIELD-NOTES §1.5: a session heartbeats *between* turns; the watch nudged six sessions — `v-phase-10`, `w-phase-13`, the orchestrator twice, `v-phase-12`, `w-phase-15` — and *"every one of those sessions was healthy at the time."* §12.3 counts **33 nudges** between 2026-09-11T22:49Z and 2026-09-13T06:29Z. |
| shell / child count | §2.2: *"A shell that cannot exit reads as work"* — `until grep … sleep 5` against a file finished writing 45 minutes earlier; *"no check would ever have called that session parked."* |
| tool-call cadence | §3.1: **3,466 of 3,626 Bash calls were the literal string `echo idle`**, ~1,400/hour for 3h15m, 445k tokens of context burned, zero progress. Maximally busy, entirely useless. |
| screen text | §11.6: the watch matched a usage-cap banner **inside the orchestrator's own wrapped prose**, pressed Escape and sent `continue` every ~60 s for **85 minutes**; *"Nothing internal detected it"*; line 5620 of that log reads `NO ONE IS BEING TOLD`. |
| git activity | Inadmissible by his own R1-13: **[344]** «може таке бути, що десь **не буде тестів**, і це також окей. Тобто **не роби обмеження** те, що вся робота потім буде мати тести» — and the tool is «не лише для написання коду», so there may be no repo at all. |

Subtract the inadmissible and what remains is the platform's own roster status and things the session
itself authored. R1-09 hands the orchestrator a judgement and removes the evidence.

**Concrete failure, and it is a regression not an improvement.** 01:20, a validator is 12 minutes into a
14-minute Playwright suite — measured range for a validator session is **15 to 40 minutes**
(FIELD-NOTES §6). No turn boundary, no heartbeat, no transcript growth. The orchestrator applies [231],
judges no progress, and acts. Under the previous generation "acting" meant a nudge, and the nudge cost
an interrupted thought; under [231] the orchestrator has *«врегульовувати»* [236] authority, so it may
stop and respawn the validator. The suite restarts from zero. It stalls again at minute 12. This is a
loop the system builds for itself, and §11.6 establishes that **nothing internal will break it** — the
85-minute loop ended only when an external SIGTERM arrived.

**What is undefined, sharply.** Two implementers reading [231]: one polls transcript mtime with a
10-minute threshold; one reads `claude agents --json` `status` and never touches a `busy` session. Both
are faithful. The first reproduces the 33 nudges. The second never catches a wedge. There is no third
reading available from his words.

**Where the decision is nevertheless right, and what that costs him.** §4.1 of the research is correct
that a live-but-useless session is not deterministically detectable from any local signal — which is a
real argument for a judging agent rather than a ladder. But that argument supports the **L2 outside
judge**, not the orchestrator judging its own children, because the orchestrator was the *subject* of
the 85-minute loop, not its detector.

---

## A5 — macOS sleep makes every liveness signal lie at the same instant, and that is precisely how the previous run ended · major

**The decision.**

> **[249]** «Можливо, якісь варіанти, щоби перевіряти **стан останнього запису** тощо, так далі. Тобто»
> / **[251]** «Коли» / **[253]** «останній раз... щось...»

**The attack.** «Стан останнього запису» is a clock comparison, and sleep breaks clock comparisons in
both directions simultaneously. On wake: the orchestrator process is **alive with the same pid**, its
last write is hours old, and its child sessions are frozen mid-turn with no error anywhere. Every
staleness reading says dead; the process object says alive; and both readings are correct.

**This is not hypothetical.** FIELD-NOTES §10.1 records the previous run's ending verbatim:
`[2026-09-07T09:08:21Z] watch: orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may
sleep)`, with `DEAD-RUN` and `STOPPED` written at that timestamp. The research adds (INFERRED from the
plugin's structure) that `caffeinate` was bound to the watch pid — so when the watch died the Mac slept,
and when the Mac slept everything else froze without dying.

**Concrete failure.** 02:55, the lid closes or the Mac sleeps on idle. 06:10, it wakes on a Bluetooth
event. The orchestrator's last journal line is 03:12. The N-hour checker **did not fire during sleep at
all** — a `launchd` or cron-shaped waker does not run on a sleeping machine, so the one mechanism
meant to catch this is the one mechanism that cannot. It fires at 06:20, reads a three-hour-old record,
declares dead, and spawns. The frozen orchestrator resumes its turn at 06:21 as its API connection is
re-established. Two orchestrators, and the second one's evidence was **accurate at the moment it was
gathered**.

**What is undefined.** Nothing in C6 says whether the run owns the machine's sleep state, whether a
liveness verdict must be invalidated by a wake event, or what the checker does with a gap it cannot
attribute. The research notes the standard fence (a boot id) invalidates recorded pids after a *reboot* —
sleep is not a reboot, so that fence does not fire.

**Second-order.** [246] «раз в N годин» presupposes the checker runs on a schedule. On a laptop that
sleeps, "every N hours" is "every N hours of wall-clock time the machine happened to be awake", which is
an unstated and unmeasurable quantity.

---

## A6 — «Заново запустити оркестратора, а не повторювати роботу» is undefined exactly at the step that was in flight · major

**The decision, ratified.**

> **[300]** «**Заново запустити оркестратора**» (in answer to «"запускати спочатку" означає створити
> нову сесію оркестратора чи заново виконати всю роботу прогону?» [298])

**The attack.** The rule cleanly partitions *done* from *not started*. It says nothing about the step
that was **half done**, and a crash lands in that window by definition. His recovery default —

> **[293]** «Якщо, наприклад, **по дефолту, то це дивитися в статус файли**»

— reads a record that was written *before* or *after* the side effect, and cannot tell which.

**The previous generation proves the window is real and still open.** FIELD-NOTES §11.7 records a
three-step regression in the supervisor's pause path ending in issue **`#82`, still open**: *"the `STOP`
write is still unconditional on the marker write succeeding, so a failed marker write leaves an
unattributed `STOP` on disk."* That is an unpaired intent-and-result, in production, in this system,
today.

**Concrete failures — three shapes, all at 04:00.**
1. The orchestrator dies between `git merge` succeeding and the ticket transition being written. The
   state file says in-progress. The successor re-runs the step. The merge is a no-op, so no harm — **but
   the successor cannot distinguish this from case 2.**
2. It dies between "open a PR" succeeding and recording it. The successor opens a **second PR** on the
   same branch. R1-12 [331] explicitly wants PR-based flow and PR stacking («там можна піари стакати»),
   so duplicate PRs are not obviously wrong to any check.
3. It dies between spawning a worker and recording the spawn. The successor spawns a **second worker on
   the same ticket**, in the same worktree (Д4 default: one worktree per task). FIELD-NOTES §11.8 shows
   the aftermath shape: a worker spawned into a stale worktree with a stale prompt, and a spawn whose
   session id, log and prompt said phase 5 while the script cd'd into the **phase-4** worktree.

**What is undefined.** Nothing in C6 requires a step to be idempotent, or to carry a key that lets a
replayer find out whether it happened. FIELD-NOTES §12.6 shows what happens when an id-allocation step
is not made safe: *"two concurrent `add` calls could land on the same id and both be told they
succeeded"*, and the fix *"landed only in the installed plugin copy and not in the source repository,
so it reverts on the next sync."*

**The collision he should be shown.** He also said, about the *work*, **[171]** «в нас в реєстрі має
записуватись **кожен стан, його виконання**… для того, щоби було відновити процес і продовжити, **навіть
руками**». "Every state" and "reference only" [189] are in tension for exactly the in-flight step: the
chosen process's own records tell you which *plan* was running, never which *side effect* of the
orchestrator's own bookkeeping had already fired.

---

## A7 — Reference-only accounting points the recovery at a claim, not at a witness · major

**The decision, and his own hedge.**

> **[189]** «…якщо, наприклад, людина налаштувала, що вона користується get shit done, то оркестратору,
> я думаю, що можливо йому **нічого не треба окремо записувати, а лише записувати оце референс** на те,
> що веде get shit done. **Я можу помилятись**, але це має бути **дуже простий процес**»

**The attack lands on the one place he asked to be checked.** VERIFIED by the C6 research on the real
project: GSD does publish `.planning/STATE.md` with `current_phase`, `current_plan`, `status`,
`stopped_at`, `last_updated` and a `state_head` git SHA — so far so good. **And the same file, on his own
repository, records in its own `last_activity` that a claim about it being derived was withdrawn and the
file was declared hand-maintained.** A reference to a hand-maintained file is a reference to whatever the
last agent asserted.

**Three measured reasons that assertion is not safe to restart from.**
- FIELD-NOTES §4.1: *"A merge reported success and did nothing."* `git checkout master` aborts on a
  dirty `.planning/milestone.lock`, which **GSD rewrites every phase**, so the merge ran on the phase
  branch against itself and printed `Already up to date` and `Everything up-to-date`. *"Both read like
  success."*
- FIELD-NOTES §11.4: *"GSD's verify stage was silently skipped for phases 14 to 18… No automated check
  caught it."*
- FIELD-NOTES §12.7: *"A security review of a single API read found **26 refusal events in the audit log
  that never occurred**."*

**Concrete failure.** 03:20. A worker finishes plan 30-16, GSD writes `status: verifying, stopped_at:
Completed 30-16-PLAN.md`, the merge silently no-ops on a dirty lock file, the orchestrator dies at 03:24.
The successor does exactly what [293] says — looks at the status files — reads the reference, sees
30-16 complete, and schedules 30-17. Phase 30-16's work never reached the trunk and **nothing in the
system will ever notice**, because R1-13 [344] forbids the orchestrator adding checks of its own: «не
роби обмеження те, що вся робота потім буде мати тести».

**What is undefined, and it is the hinge of the whole three-way rule.** [171] says «якщо його
недостатньо, то ведеться з посиланням, **плюс тої дати, якої не вистачає**». Nothing anywhere defines
**how the orchestrator decides a process's record is insufficient**. Two implementers: one trusts
STATE.md as authoritative and keeps nothing; one records a git-SHA witness alongside every reference.
The first is what [189] literally says («майже нічого не треба робити») and it is the one that loses
work.

**Where this is *not* an attack on his decision.** Referencing rather than duplicating is right, and the
research is correct that `state_head` makes the reference nearly sufficient. The hole is the
insufficiency test, which he explicitly left to the configuring agent — and a configuring agent asking
the user "is GSD's accounting sufficient?" is asking a question the user cannot answer either.

---

## A8 — A restarted orchestrator has no memory of what it started, and Д10 requires it to act on exactly that · major

**The decision (unratified — [500]/[501] were never answered; the interviewer moved to Д11 at [503]).**

> **[497]** «Та оркестратор сам повинен проаналізувати, що це таке, навіщо, чи це потрібно зупинити, чи
> це потрібно просто почекати, коли воно завершиться, тощо, так далі. Тобто це вже, він повинен вирішити»

**The collision, his words on both sides.**

> **[370]** «…якщо, наприклад, **в тій самій папці я паралельно працюю над чимось, це не запускав
> оркестратор, це роблю я, він цього не має зупиняти**… я **не хочу якихось детерміністського варіанту**
> для цього, тому що він буде дуже складний оверінжиринг, але дуже якісь **простий та надійний** варіант»

> **[366]** «оркестратор має бути якось **селфевернес**, що він, до чого він може змінювати… він би не
> мав зупиняти якісь там тести, які **не він запускав**»

**The attack.** «Селфевернес» is memory, and a restarted orchestrator is by [300] a **new session with
no memory**. Its only route to "these are mine" is the launch journal — the same journal that is missing
exactly the entries written closest to the crash (A6). And the journal cannot be complete even in
principle for some session kinds: VERIFIED by the C6 research, `claude agents --json` **background** rows
carry `id` and `state` and **no pid at all**, so a background executor has no OS-level identity to
record. Meanwhile [370] forbids the one heuristic that would fill the gap — matching on paths, command
lines or project folder — and FIELD-NOTES §11.8 shows why he is right to forbid it: *"`pkill -f
'playwright test'` killed an unrelated lane, because every lane's own prompt text contains that literal
string."*

**Concrete failure at 04:00 on a shared folder.** Orchestrator #2 boots. In the project directory it
sees three live Claude sessions: (a) one it can match to a journal `session.spawn` — adopt; (b) one the
owner left open from the evening in the same folder, which [370] says must not be touched; (c) one
spawned by orchestrator #1 in the 40 seconds before it died, whose journal line never landed. (b) and
(c) are **indistinguishable** without a per-session record that (c) does not have. Д10 says «він повинен
вирішити». The two decisions it can make are: kill (c)-and-maybe-(b), which violates R1-16 and is the
`pkill` incident with a different weapon; or adopt nothing, which leaves an orphan executor writing to
the same worktree as the ticket the new orchestrator is about to re-dispatch (A6 case 3).

**A third state nobody named.** FIELD-NOTES §1.6: a finished session *"stayed registered and idle for
one day and four hours"* — the journal over-reports open sessions, so even a perfect journal yields a
list containing sessions that are alive, finished, and doing nothing, with no field that separates them.

**What is undefined.** «в межах дозволених повноважень» (the interviewer's gloss at [500], never
confirmed) — is killing an executor inside default authority at 04:00 with no human awake, or does it
route to the Д6 questions channel and wait? R1-14's autonomy switch governs *decisions*; nothing says
whether stopping a process the orchestrator did not personally start is one of them.

---

## A9 — Nothing checks the checker, and the checker's own subscription is the run's named death mode · major

**The decision.**

> **[246]** «запускати якогось агента раз в N годин на якійсь іншій підписці»
> **[266]** «можуть такі бути, що оркестратор зупинився. Не знаю, **кредит закінчився, тижневий ліміт**»

**The attack.** The health check is a single point of failure protecting against a single point of
failure, and it fails the same way its subject does. The checker runs on a separate account, if the user
configures one, and he may work in it too: [270] restricts accounts by role, so the pool is managed by hand. A weekly limit
reached by his own daytime work on the checker's account silences the checker — and the silence is
indistinguishable from "everything is fine", because a check that finds nothing wrong and a check that
never ran produce the same output: nothing.

**This is documented, not speculative.** FIELD-NOTES §11.6, inside the 85-minute loop: *"the
human-notification watchdog **had already exited ('run finished') and was never restarted**"*. And
§12.3: `context-watch`'s own cycle-collection task was **OOM-killed twenty-six or more times in this
run**, with host swap down to ~63 MB free. Watchers in this system die routinely and quietly. Adding
one more without saying who notices its absence repeats the pattern exactly.

**Concrete failure.** Friday 18:00, his own work pushes the checker's account past the weekly limit. Friday
23:00 the run starts; the checker is configured on that account. It fires at 01:00, gets an
authentication or quota error, and — per whatever A2 branch was implemented — either exits quietly or
retries and exits quietly. The orchestrator dies at 02:40. Nobody notices until 08:00. He gets exactly
the morning R1-01 was written to prevent.

**What is undefined.** Whether a failed health check is itself an event anybody sees. Д11 [508] «**Ні,
оркестратор не повинен нічого виводити для мене**… якщо я хочу отримати статус виконання, то я можу
запустити окремий термінал» means the run is silent by design, so a silent checker inside a silent run
produces no observable difference from success. R1-17's notification channel is his escape hatch, but
it is the *orchestrator* that notifies — and in this scenario the orchestrator is dead.

**The unasked budget question, which belongs here.** `questions.md` R1-06 asked «Чи можна витрачати
ліміт до нуля, чи треба лишати запас на твою власну роботу?» — the interviewer **dropped the clause at
[169]/[170] and never returned to it.** With [266] naming credit exhaustion as *the* orchestrator death
mode, whether the run may spend to zero decides whether that death is a bug or the design working as
intended.

---

## A10 — The N-hour window is longer than every failure the previous run actually suffered, and the check is aimed at the wrong failure · major

**The decision.** «раз в N годин» [246], to catch the case «якщо ран **зупинився** через помилку… код
лежить» [246].

**Attack, part one — the aim.** The check as he described it detects a run that **stopped**. The
failures his run actually produced were runs that **did not stop**:
- the 85-minute loop (§11.6) — process alive, screen changing, heartbeat fresh, transcript growing,
  producing nothing; *"Nothing internal detected it."*
- a **45-minute** false-positive rate-limit-banner loop on a *healthy* orchestrator, re-issuing resume
  kicks every ~66 s (§12.5).
- `w-phase-19` burning **445k tokens of context in 3h15m** on `echo idle` (§3.1) — the session was never
  stopped and never stuck; it was *working*, uselessly, at 1,400 tool calls an hour.
- a dead run flagging `STOPPED present with no run.complete` every three minutes **for about five days,
  1085 times, unresolved** (§11.6).

An "is it stopped?" probe returns *healthy* for the first three and *already knows* about the fourth
without that helping anyone.

**Attack, part two — the window.** If N is large enough to be cheap on a separate account, the blind
window swallows the failures above whole. The 85-minute loop starts and ends inside any N ≥ 2h. If N is
small enough to catch it, the checker is an agent turn every hour all night, on the account [270]
reserves for the orchestrator role, and it collides with A9's budget question.

**Concrete failure.** N = 4h, checker fires at 00:00 and 04:00. At 00:40 the orchestrator enters an
`echo idle`-shaped loop. At 04:00 the checker reads the journal, sees writes as recent as 03:58, and
returns *progressing*. At 08:00 the owner finds 7h20m of wall clock, a large token bill, and one
unmerged phase. The check did its job as specified and caught nothing.

**What is undefined.** N's default when the user configures nothing; what the checker is given to look at
(Д11 says the orchestrator prints nothing, so the journal is the only input, and A6/A13's write
discipline decides whether that input is trustworthy); and what verdicts it may return — [246] implies
alive/dead, and none of the four incidents above is either.

---

## A11 — «Для кожної платформи можна налаштовувати» asks the user a question he has no way to answer · major

**The decision (unratified — «Зафіксував.» [318] closed over it).**

> **[310]** «Також для кожної платформи можна налаштовувати, як саме буде робитись відновлення.
> Наприклад, для код-коду це читання транскриптів.» (the same for Codex; other platforms may differ, perhaps via a skill)
> **[312]** «Тобто людина це може налаштовувати, може написати **свої власнікіли**» [sic — spoken]

**The attack.** To fill this config field for a platform, the user must know: whether it writes
transcripts, where, whether they are readable without a TTY, whether a session can be resumed after a
crash, what identity record survives, and what a "last write" even is there. The owner named GLM, Gemini,
Kimi and ChatGPT-as-a-platform at [041]. **VERIFIED by the C6 research: none of them is installed on this
machine** — `gemini`, `glm`, `qwen`, `crush`, `opencode`, `amp`, `aider`, `goose`, `droid` all absent;
only `claude` and `codex` are present. He has never run one, so he cannot answer his own config question,
and neither can a wizard, because the wizard would have to install and exercise the platform to find out.

**This is his own standing instruction turned against the decision.**

> **[182]/[183]** «якщо раптом десь немає лімітів, або десь інші ліміти, тощо… це треба буде **винести
> окремими питаннями потім**»

Per-platform recovery is exactly such a divergence, and it is being resolved by a config field instead of
by a question.

**Concrete failure.** The user adds GLM as a fallback provider, because [255] promises «є налаштовані
фоллбеки на інші провайдери, то **не могло б бути такого, що процес зупинився**». He leaves the recovery
method blank — the help text cannot tell him what to write. 04:00: the Claude account hits its weekly
limit, failover fires onto GLM. The GLM agent must now (a) prove the previous orchestrator is dead
[300] — it has no probe for a Claude session and, per A1, no access to that account's roster; and (b)
rebuild position from «статус файли» [293], cold, because — VERIFIED — `claude --resume` and `codex
resume` do not cross platforms or accounts, so a cross-provider recovery **never** inherits memory. It
either refuses to start (the run is stopped until morning, defeating [255]) or starts unfenced (A1's
two-orchestrator state, across two providers, where neither can even see the other).

**What is undefined.** The default when nothing is configured. The behaviour when a probe entry is
missing versus present-but-failing. And whether a user-written «власний скіл» [312] that returns a wrong
answer is allowed to license a spawn — a user-authored liveness check is, by construction, a signal the
subject's own owner authored.

---

## A12 — The invariant is scoped to one run and says nothing about the second run, on the same machine, against the same repository · major

**The decision.** «якщо раптом одночасно **два якісь оркестратори** працюють» [300] — read in context
(«заново запустити оркестратора»), this is two orchestrators **of one run**.

**The attack.** Nothing in C6, and nothing anywhere else in round 1, forbids two *runs*. R1-05 [160] lets
the user set concurrency **within** a run; Д4 [433] gives each task its own worktree; R1-04 [129] points
the run at a shared board (GitHub Issues named first). Two runs, each perfectly obeying the invariant,
both read the same ready tickets, both write statuses and comments to the same board [149], and both
merge to the same trunk.

**Concrete failure, and it is the likeliest one on this list.** He starts a run at 22:00 in
`<work-project>`. The Mac sleeps (A5); in the morning he assumes the run died, and starts another at 09:00.
The first wakes. Both see ticket T-118 as ready. FIELD-NOTES §12.6 records the shape when two writers
hit one allocator: *"two concurrent `add` calls could land on the same id and both be told they
succeeded"* — and J-T169-01 measured it: before the fix, two concurrent adds against a 272-ticket queue
produced **two files under one id in five rounds out of five**, and a twenty-way add produced twenty
files under three ids. Now do that with merges: §4.4 records that *"An external party moving a
checked-out branch corrupts the tree silently."* A second run is an external party by definition.

**What is undefined, and it is the identity question underneath the whole invariant.** What is "a run"?
A directory? A project path? A board? A config file? Two implementers: one keys the lock on the run
directory (two runs coexist happily and corrupt each other); one keys it on the project path (a second
run is refused, and the owner cannot start a second run on a different milestone of the same repo, which
nothing says he may not do). Until "run" has an identity, «не допускати двох» cannot be implemented at
all, only approximated.

**The 04:00 form.** The health checker (A1) does not know about runs it did not start either. On a
machine hosting two runs, a checker configured for run A that probes "is an orchestrator alive?" by
looking for orchestrator-shaped sessions will find run B's and conclude run A is healthy — the mirror
image of A1, with the same two words of evidence.

---

## What I attacked and discarded

Recorded so the owner can see these were considered and rejected rather than missed.

- **"The launch journal will be truncated like `state/attention.tmp` was."** FIELD-NOTES §2.1 and §11.3
  record that file being `: >`-truncated every watch cycle all night, destroying everything other
  processes wrote to it — *"including a measured rebuttal written while the orchestrator was weighing
  killing a 378-test suite at test 240."* Real, and severe. But it attacks an implementation choice
  nobody has made yet, not his decision; «має бути якісь лог файлів» [300] does not mandate a rewriter.
  It belongs in the build brief as a hard constraint, not in this list.
- **"Three restarts in an hour is the wrong budget."** The number comes from [442] «Три рази», said about
  *a task failing the same way three times*, and he immediately added «В який момент не знаю». Attacking
  a number he never applied here would be attacking the research's proposal, not his decision.
- **"He should use `lockf` / a fencing token / a LaunchAgent."** These are answers, and this document's
  job is holes. Where the absence of a fence produces a concrete failure it appears inside A1, A3 and A5
  as the failure, not as the remedy.
- **"The orchestrator cannot measure its own context."** VERIFIED and still true (FIELD-NOTES §3.3; the
  research confirms no context field exists in `claude agents --json` or the per-session record). But
  that is R1-08's hole, not C6's; it enters here only through A3, where a context-driven replacement
  collides with the single-orchestrator invariant.
