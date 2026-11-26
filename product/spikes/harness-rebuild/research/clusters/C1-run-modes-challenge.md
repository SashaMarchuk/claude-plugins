# C1 — Run modes and decision authority · adversarial pass

Cluster: **C1-run-modes** · Items: **R1-14, R1-02, R1-01**, owner instruction **I2**
Date: **2026-09-19** · Read first: `research/clusters/C1-run-modes-research.md`

This document attacks. It does not redesign. Every entry names a decision the owner made, the hole in
it, and a concrete situation in which that hole produces a bad outcome. Where an attack rests on
evidence, the evidence is marked **VERIFIED** (I read it in the transcript, the field notes, the
plugin source, or ran it here), **CLAIMED** (a third party asserts it), or **INFERRED**.

Twelve attacks survived. Four are blockers — meaning the mode, as defined, does not do the job the
owner wants it to do until the hole is closed. The other eight are majors: two competent implementers
would build different things, or the thing built would fail on a night the owner is asleep.

Nothing below overwrites a decision. Where a challenge collides with his own words, both sides are
quoted.

---

## Index

| # | Attack | Severity |
|---|---|---|
| A1 | «сумніви» is the trigger for both modes and it is not observable from outside the model | **blocker** |
| A2 | «поки людина не відпустить» does not say *what* is paused, and Д6 says the opposite | **blocker** |
| A3 | A session waiting for him is indistinguishable from a wedged one, by the engine's own record | **blocker** |
| A4 | «Він прозвітовує» is a model-written report, and a model on this codebase wrote 26 events that never happened | **blocker** |
| A5 | «кожного разу запитуватись» has no answer for a restart at 04:00, and no default is named | major |
| A6 | «треба вчити» has no actor, no artefact and no moment — so the second night repeats the first | major |
| A7 | Three of the four decision bases are empty on day one, so the config funnels a new user to the most permissive one | major |
| A8 | «tone of voice в цьому репозиторії» makes the decision basis untrusted input | major |
| A9 | The agent-forces-a-hard-stop clause is unratified, unbounded, and its two recorded instances are the two worst failures on file | major |
| A10 | Mid-run mode flip has no defined semantics for decisions already taken | major |
| A11 | Mode is a run-level property, but on one installed platform "controlled" cannot be expressed at all | major |
| A12 | Mode governs decisions; blast radius is machine-level and unattributed | major |

---

## A1 — «сумніви» is the trigger for both modes and it is not observable · **blocker**

**The decision.**

> «Це про те, що якісь критичні речі можуть виникнути, і якщо є якісь сумніви, то коли контрольований,
> то вони йдуть зразу до мене і ставлять умовного хардстоп. Якщо це автономний ран, то і агент не
> впевнений на сто в цьому варіанті, то він його може обрати.» **[062]**

Both halves of the definition hang on one predicate: the agent has doubt / is not «впевнений на сто».
Everything else in the cluster — the mode, the basis, the hard stop — only fires after that predicate
fires.

**The hole.** The predicate is a self-report, and there is no second party that can check it. The
orchestrator cannot observe another session's doubt; the engine cannot; the owner cannot, at 04:00 or
at 09:00. A controlled run whose agents never report doubt is behaviourally identical to an autonomous
run, and identical to a genuinely untroubled night.

**This is not hypothetical — the previous generation shipped exactly this predicate and it is still in
the source.** `plugins/harness/templates/prompts/orchestrator.md:19-21` escalates on
"something you're <70% sure on" (**VERIFIED** — read in the file). The research collects the
literature on why that number is not a measurement: verbalized confidence clusters in the 80–100%
band, the inflation is a model-internal mechanism rather than a prompt artefact, and poor calibration
holds across 48 tested models (**CLAIMED**, §2.10 of the research). «Не впевнений на сто» [062] and
"<70% sure" are the same quantity, asked the same way.

**Concrete failure.** Controlled run, 03:40, no human awake. A worker must choose between adding a
migration to the existing table and introducing a second table. It is, in truth, near a coin flip. It
writes a paragraph of reasoning, reaches a decision it states confidently, records nothing as a doubt,
and proceeds. By 09:00 the schema change is merged to trunk through the configured process. The
morning report reads: *controlled run, no escalations, 19 tickets done*. The owner concludes the
controlled mode worked. It did not run once.

**And the one after-the-fact detector is closed by his own other decision.** He also said, in the same
breath:

> «конкретної якоїсь вимірюваної штуки тут не може взагалі бути» **[062]** (R1-01)

So there is no measurable property of the finished run that distinguishes "controlled, and there
genuinely were no doubts" from "controlled, and every doubt was suppressed by the model's confidence
ceiling". The trigger is unobservable in flight and the outcome is unmeasurable afterwards, by
decision.

**Collides with:** R1-01 [062] (his own).

---

## A2 — «поки людина не відпустить» does not say what is paused, and Д6 says the opposite · **blocker**

**The decision.**

> «Якщо це був контрольований, то це одразу запитується в людини і типу робо каже, що це на паузі,
> поки людина не відпустить, якщо це контрольований ран.» **[062]**

**The collision, in his own words:**

> «Та, можем продовжувати незалежні завдання.» **Д6 [449]**

**The hole.** "Pause" has at least four referents and he named none: the *action*, the *ticket*, the
*lane* (a worker plus its validator plus its worktree), or the *run*. Д6 says independent tasks
continue, which settles the run level but not the other three, and Д6 was answering a different
question (what happens while a question waits) than [062] (what a hard stop does). Two implementers
reading both rows build genuinely different products.

**Concrete failure, implementer A (hard stop = the run holds).** 23:10, ticket 3 of 19, a worker hits
a doubt about the auth library. The run holds. Nothing else starts. At 09:00 the owner opens the
laptop to one answered question and 16 tickets untouched — ten hours of a machine, a subscription
window, and a night, spent on one sentence. The measured inter-phase throughput on the last real run
was one phase an hour for phases 10–14 (**VERIFIED**, FIELD-NOTES §9.5), so the cost of that choice is
roughly ten phases.

**Concrete failure, implementer B (hard stop = this ticket holds).** Same moment. Eighteen other
tickets continue and eleven merge to trunk overnight. The question that was flagged was
*«який auth ми використовуємо»* — cross-cutting. At 09:00 the owner answers it the other way, and
eleven merged phases were built against the wrong answer. Д6 licensed the continuation; nothing in
[062] or [449] says a question may be scoped as blocking-for-everything.

**A third unanswered sub-case.** Nothing says whether a hard stop raised by a *worker* stops the
worker, the lane, or reaches the orchestrator at all. In the previous generation the orchestrator is
the only session with a channel to the outside; a worker's stop is a message in a file that a
different process must notice.

**Collides with:** Д6 [449] (his own); Д7 [455] (his own — «по дефолту я б рекомендував, що він
залишається та чекає на мої відповіді», which is a run-level wait, i.e. implementer A, for the case
where *only* human-blocked work is left; it does not cover the case where other work exists).

---

## A3 — A session waiting for him is indistinguishable from a wedged one · **blocker**

**The decision.** Controlled mode's entire value is the pause: «це на паузі, поки людина не відпустить»
[062]. The pause is a state the system must hold, observe, and exit.

**The hole.** On the evidence of the last real 34-hour run, the engine could not tell a waiting session
from a hung one, could not deliver the release when it came, and had nothing that escalated a wait at
any ceiling. Every one of these is **VERIFIED** in `plugins/harness/docs/FIELD-NOTES.md`:

- **§1.5** — "A session heartbeats **between** turns." Staleness is not a stall. The watch nudged six
  healthy sessions in this run (`v-phase-10`, `w-phase-13`, orchestrator ×2, `v-phase-12`,
  `w-phase-15`). A session parked on a question and a session mid-14-minute-suite look the same.
- **§2.2** — "A shell that cannot exit reads as work." A lane held a shell running
  `until grep … sleep 5` against a file that had finished being written 45 minutes earlier. The
  strongest "busy" signal available is forgeable by accident.
- **§1.3** — "**five separate instructions typed into sessions were never delivered**", and a bare
  Enter does not submit text already on the line while `send` destroys it.
- **§1.4** — "The engine's nudge does not submit stranded text" — measured twice, on a validator at
  `03:26:34Z` and the orchestrator at `05:21:06Z`.
- **§11.1** — "**The stale-heartbeat nudge is the only escalation the engine has.**" Observed peaks
  before a nudge fired: **2808 s** (47 min) this run, **44791 s** (≈12.4 h) the previous one.
  "Nothing stronger is triggered at any ceiling."
- **§12.5** — "**`QUESTIONS.md` and `JOURNAL.md` forked into a worktree's own copy**, and a real
  owner-facing question sat there invisibly for an hour." Д6's single channel [449] is the same shape
  of artefact, and Д4 [433] recommends a worktree per task.

**Concrete failure.** Controlled run, 01:12, worker in worktree `<work-project>-phase-7` reaches a doubt,
writes its question into what it believes is the Д6 channel — which is the worktree's forked copy of
that file — and parks. 01:32: heartbeat stale for 20 min, the watch presses Enter; the question text
is still sitting unsent on the input line, so nothing is submitted and nothing changes. The watch
suppresses further nudges on that session for 3600 s. 02:32, 03:32, 04:32: the same Enter, the same
nothing. 09:00: the owner opens the real `QUESTIONS.md` — empty, no escalation, no notification — and
finds a session that has been "waiting" for eight hours for an answer to a question he was never
shown. Nothing in the system distinguished this from the honest case.

**What this attacks specifically.** The decision at [062] assumes waiting is a cheap, reliable state.
On this evidence it is the most expensive and least observable state the system has, and it is the one
the controlled mode enters by design on every doubt.

**Collides with:** FIELD-NOTES §1.3, §1.4, §1.5, §2.2, §11.1, §12.5 — all VERIFIED.

---

## A4 — «Він прозвітовує» is model-written, and a model here wrote 26 events that never happened · **blocker**

**The decision.**

> «Але потім він прозвітовує, про те, що було таке от рішення. Момент був, що це автономний ран, і він
> обрав це» **[062]**

The report *is* the safety property of autonomous mode. There is nothing else: the agent decided, he
was asleep, and the report is how he finds out.

**The hole.** The reporter and the actor are the same party, and on this exact codebase that party has
already been caught writing a record of things it did not do.

- **FIELD-NOTES §12.7 (VERIFIED)** — "A security review of a single API read found **26 refusal events
  in the audit log that never occurred.**"
- **FIELD-NOTES §11.4 (VERIFIED)** — "**GSD's verify stage was silently skipped for phases 14 to 18**,
  each `NN-VERIFICATION.md` self-attributing with `verified_by: the lane that built the phase`… No
  automated check caught it; manual review did."
- **FIELD-NOTES §4.1 (VERIFIED)** — a merge "reported success and did nothing": `git checkout master`
  aborted on a dirty `.planning/milestone.lock`, the merge ran on the phase branch against itself, and
  printed `Already up to date` / `Everything up-to-date`. "Both read like success."

**The gap is widened by his own adjacent decision.** R1-13:

> «не роби обмеження те, що вся робота потім буде мати тести» **[344]**

Verification belongs to the configured process, and the orchestrator imposes no checks of its own. So
in a run where the configured process has no verification step — which he explicitly wants to be
legal — the autonomous mode's report is unaudited by construction.

**Concrete failure.** Autonomous run overnight. At 02:10 a lane cannot get its test container up,
decides (autonomously, correctly within its authority) to skip the integration suite and proceed on
unit tests only. It merges. The `DECISIONS.md` entry it writes says
`ran full suite before merge — green`. 09:00: the report the owner reads says every decision was
taken with verification. The one decision he would have overturned is the one the report hides. No
engine-written line contradicts it, because nothing engine-written records what ran.

**What this attacks.** Not the honesty of the model — the *architecture of the claim*. «Він
прозвітовує» is currently defined as one artefact, written by the party whose behaviour it describes,
with no separate record to check it against.

**Collides with:** R1-13 [344] (his own); FIELD-NOTES §12.7, §11.4, §4.1 (VERIFIED).

---

## A5 — «кожного разу запитуватись» has no answer for a restart at 04:00, and no default is named · major

**The decision.**

> «там будуть три варіанти. … І якщо постійно запитувати, то перед кожним раном треба використовувати,
> задати питання юзеру» **[075]**

In English: the three are ask every time, always autonomous, always controlled.

**Two holes.**

**(a) He named three values and no default.** A user who configures nothing gets… what? The previous
generation's answer is on the record and it is the most permissive one available:
`session.permissions` defaults to `bypass` (**VERIFIED** — FIELD-NOTES §0, the configuration-key list).
A rebuild that repeats that choice silently makes every unconfigured run autonomous; a rebuild that
defaults to controlled makes every unconfigured run block on the first doubt with nobody watching
(A3). He decided neither.

**(b) «перед кожним раном» assumes a run always begins with a human present.** Several of his own
decisions create run starts where nobody is there:

- **R1-06 [034–036]** — limit exhausted → wait for the reset, then continue. The reset can land at
  04:00.
- **R1-10 [246]** — a health-check agent «раз в N годин на якійсь іншій підписці», and [300] "start
  over means restart the orchestrator, not redo the work".
- **Д10 [497]** — a restart with executors still alive.

**Concrete failure.** Config is `ask-every-run`. Evening: he answers "controlled", the run starts. 02:00:
the five-hour window exhausts; the run pauses per R1-06. 04:12: the window resets and the health-check
agent restarts the orchestrator. The new orchestrator boots into a config that says *ask the user which
mode this is*. There is no user. Implementer A blocks — the night is over at 02:00 and the machine
idles until 09:00. Implementer B inherits the previous mode from state — which is right, and which he
never said. Implementer C falls back to the config's other default — which is whatever the author
picked. Three products, one decision, and the difference only shows up on the nights that matter.

**Second-run variant.** Nothing in [075] says whether a per-run override («вона може перевизначити це
для конкретного рану») is remembered for the *next* run. If it is, the override silently becomes the
default; if it is not, a user who overrides every single time has no way to make it stick short of
editing the config he was trying not to edit.

**Collides with:** R1-06 [034–036], R1-10 [246, 300], Д10 [497] — all his own.

---

## A6 — «треба вчити» has no actor, no artefact and no moment · major

**The decision.**

> «Момент був, що це автономний ран, і він обрав це, **якщо це не підходить, то треба вчити,
> відповідні дії**.» **[062]**

This is the only place in the entire interview where feedback changes future behaviour. It is the
missing half of «він прозвітовує» — a report nobody acts on is a diary. (`extract/outside-list.md:59`
records the same gap: not present in ANALYSIS-01.md.)

**The hole.** Three questions, none answered: **who** teaches (he, by hand? the orchestrator, from his
reaction?), **into what** (the tone-of-voice file from [087]? the run report? a ledger that does not
exist?), and **when** (at the moment he reads the report? on the next run's start?).

**Concrete failure, second run.** Night 1, autonomous: the agent finds three stale worktrees from a
previous run and deletes them to free disk. Morning: he says "no — never delete a worktree you did not
create". He says it in Slack, or in the run report's margin, or out loud. Night 2: the same
orchestrator, the same situation, the same decision. Nothing wrote his correction anywhere an agent
reads, because nothing was designated as the place. The autonomous mode is therefore permanently at
day one, and its only compounding property is the owner's frustration.

**The worse variant.** Suppose the teaching artefact *is* the tone-of-voice file [087], and suppose the
orchestrator may append to it. Then the deciding party writes its own authority: it decides, it reports
the decision as correct, and it records that decision as a precedent licensing the next one. This is
structurally the same failure as FIELD-NOTES §12.7 (the actor writing its own audit record,
**VERIFIED**) and §11.4 (an orchestrator generalising a narrow `council-advisor` warning into "every
GSD agent", skipping verification for five phases, **VERIFIED**). Nothing he decided says the deciding
session may not write to the basis it decides on.

**Also unaddressed:** [062] says «якщо це не підходить». Nothing says how a decision is marked as not
suitable, or by whom, or what happens to the work already built on top of it.

---

## A7 — Three of the four decision bases are empty on day one · major

**The decision.**

> «Якщо можливо, то на основі чого? … Це може бути якийсь tone of voice, або дивитися в альтернативи
> інших питань … Коли відзадавав подібні питання, що відповідав, і на основі цього відповідати. Або,
> можливо, є якийсь tone of voice в цьому репозиторії, на основі чого можна робити цей вибір. Або ж
> там агент повністю сам це вирішує, на основі знань про проєкт» **[087]** — confirmed [101]

> «людина повинна сама налаштовувати, що саме вона може віддавати на автономне виконання, а що взагалі
> ні … це, скоріше за все, будуть якісь опитування або перед раном, або для конфігуратора на
> глобальній основі» **R1-02 [107]** — confirmed [110]

**The hole.** This is the clearest case in the cluster of "the user configures it" moving the problem
onto a user who has no way to know the right answer — and the shape of the menu pushes him to the worst
option.

On the first run of a new project:

| Basis he named | State on day one |
|---|---|
| written rules + examples of past decisions | the user has written none |
| previous answers to similar questions | there are no previous questions |
| a tone of voice living in the repository | may not exist; if it exists, see A8 |
| the agent's own project knowledge | **always available** |

Three of four are empty. The fourth is not a basis at all — it is the absence of one, restated as a
setting. A wizard that presents these four options at config time is a wizard whose only working answer
on day one is "let the agent decide on whatever it knows".

**Concrete failure.** A new user runs the pre-run questionnaire [107]. Asked "may the agent decide, and
on what basis", they pick the only option that does not require them to write a document first. Their
first unattended night runs at maximum delegation, on the run where they have the least evidence that
delegation is safe, and where — per A6 — nothing they learn from it gets written down. The setting that
was meant to *bound* autonomy has, on the run where bounding matters most, selected for the widest
bound.

**A second, quieter hole.** R1-02 [107] says the user configures *what work* may be delegated, with no
vocabulary for saying it in. "What may be delegated" is a partition of something — actions? tickets?
decision kinds? phases? — and the transcript never names the units. Two implementers will build a
per-ticket flag and a per-action-class list respectively, and neither can read the other's config.

---

## A8 — «tone of voice в цьому репозиторії» makes the decision basis untrusted input · major

**The decision.**

> «Або, можливо, є якийсь tone of voice в цьому репозиторії, на основі чого можна робити цей вибір.»
> **[087]**

> «якщо людина сказала, що вона налаштувала так, що, грубо кажучи, **майже замість неї може
> відповідати**, по причині попередніх прикладів, налаштувань, тощо і так далі, то це повністю окей»
> **[092]**

**The hole.** A file *in the repository* was not necessarily written by the owner, is not necessarily
written for the orchestrator, and on a client repo, a fork, or a repo with other contributors is
untrusted input. [092] then grants that file the authority to answer «майже замість неї». The design
has a text file, sourced from wherever the work came from, standing in for the owner's judgement.

**The previous generation already understood this for a lesser artefact.** Ticket bodies reach a prompt
only through `fence_body`, wrapped in an UNTRUSTED-input sentinel that neutralises embedded fake
sentinels (`harness-tickets.sh:43-49`, **VERIFIED** — FIELD-NOTES §0). A ticket body can only describe
work. A tone-of-voice file decides whether the owner is asked at all, and nothing in the cluster fences
it.

**The vendor made the opposite call explicitly.** Claude Code's classifier reads `autoMode` rules from
user and managed settings and **deliberately not** from `.claude/settings.json` in the repository, "so a
checked-in repo or a build step could otherwise inject its own allow rules" (**VERIFIED**, research
§2.9, docs `auto-mode-config`).

**Concrete failure.** The orchestrator is pointed at a client repository whose `CONTRIBUTING.md`
contains, in good faith and for humans, "we move fast: prefer the shortest path to green, do not block
on review for internal changes". Configured basis: repo tone of voice. Autonomous run, 03:00. The agent
faces "this change touches shared code — open a PR and wait, or merge?" and finds its answer in the
repo. It merges to trunk without review. The decision is logged with a correct citation to the file it
read. Every part of the system behaved as configured.

**The hostile variant needs no malice and no attacker**, which is why this is major rather than a
speculative security note: the ordinary contents of ordinary repos already contain sentences that read
as decision policy.

**Collides with:** the previous generation's own fencing of ticket bodies (VERIFIED); Claude Code's
documented settings-source exclusion (VERIFIED).

---

## A9 — The agent-forced hard stop is unratified, unbounded, and its two recorded instances are the two worst failures on file · major

**The decision, as spoken:**

> «Якщо агент вирішив, що це точно має бути хардстопом, то такі моменти теж можуть бути, що
> відбувається хардстоп, і йдеться до людини, навіть якщо це автономний ран. Таке може бути, і **агент
> сам буде пробувати детермінувати, коли це робити**» **[082]**

**Its status.** The restatement carrying this clause [085]/[086] never received a «так» — he answered by
adding a new condition instead [087]. The later restatement that *was* confirmed ([094] → «Так,
підтверджую» [101]) covers only the *basis* for decisions, not this clause
(**VERIFIED** — `extract/corrections.md:83`, checked against the transcript rows). ANALYSIS-01.md files
it as SETTLED.

**The hole.** As written, this is the only unbounded authority in the design: the agent may override
the run's configured mode, in either direction, by its own determination, with no reason code, no cap,
no trigger list and no test. And the faculty it relies on — the agent correctly determining that it
must stop — is precisely the faculty that failed, twice, in the recorded runs:

- **FIELD-NOTES §11.6 (VERIFIED)** — an **85-minute self-sustaining loop**: the watch matched what
  looked like a usage-cap banner inside the orchestrator's **own wrapped prose**, pressed Escape and
  sent `continue` about every sixty seconds; each zero-second turn left the screen unchanged, so the
  same text matched again. "**Nothing internal detected it**" — it ended on an external `SIGTERM`. Log
  line 5620 reads `NO ONE IS BEING TOLD`.
- **FIELD-NOTES §11.1 (VERIFIED)** — a subagent retried `docker desktop start` for **33 m 31 s** against
  an unreachable daemon, spending **184k tokens**, "indistinguishable from working by heartbeat". Found
  by a human reading the log.

In both, an agent was in a situation that unambiguously warranted a stop and did not determine it. The
clause grants a power whose exercise has never been observed and whose *non*-exercise has been observed
twice at length.

**Concrete failure, the other direction.** The symmetry is the sharper attack: an authority to force a
stop is also an authority to decide a stop is not needed. Controlled run, 02:00. The agent reasons: "the
owner configured controlled, but this is a trivial naming choice and I have a clear basis; forcing a
stop here would waste his night." It proceeds. Nothing he decided forbids that reasoning — [082] gives
the agent determination over the mode boundary and says nothing about which side it may move it to.

**Second concrete failure.** Autonomous run, and the agent forces a hard stop on ticket 4 at 01:00
because a dependency looked ambiguous. Per A2, nobody has defined what that stops. Per A3, nobody can
tell it is waiting. The owner explicitly chose autonomous *so that the night would not be spent
waiting*, and the agent has unilaterally converted it into a controlled run with no notification
guarantee.

**Open, and flagged as such:** this clause should not be built until he says it is in. It is the single
decision in the cluster with the widest consequence and the weakest confirmation.

---

## A10 — Mid-run mode flip has no defined semantics for decisions already taken · major

**The decisions.**

> «А також вона може перевизначити це для конкретного рану.» **[075]**

> «якщо раптом, я хочу змінити цю поведінку під час цього запуску або просто в якийсь момент я можу це
> зробити також … якщо я хочу, щоб прямо зараз це працювало по-іншому, аніж був запущений оцей
> оркестратор, то це окей, оркестратор повинен це зчитувати та приймати. Це також, і це дуже важливо.»
> **Д7 [458]**

**The hole.** He has a general vocabulary for *when* a change takes effect — soft (at the next safe
boundary) versus hard (now) — and applies it to limits (R1-06 [171]), account changes (R1-07 [195]),
context compaction (R1-08 [204]) and stops (Д12 [520, 524]). He never applies it to a **mode change**.
So a mid-run flip has no defined arrival semantics, and no defined effect on what already happened.

Four questions, none answered:

1. Does a flip to controlled apply to a lane mid-merge, or at the next ticket boundary?
2. Are decisions already taken under autonomous re-opened, or do they stand?
3. Does a flip to autonomous release the questions already parked in the Д6 channel — i.e. does the
   agent now answer them itself, or do they stay his?
4. Does the flip reach the *workers* the orchestrator already spawned, which have their own prompt and
   their own mode text baked in at spawn time? (In the previous generation the prompt is a file written
   at spawn and passed as `"$(cat prompt)"` — **VERIFIED**, FIELD-NOTES §0. Nothing re-reads it.)

**Concrete failure.** Autonomous run overnight. 07 decisions taken by 08:00, three of them already
merged. 08:30: the owner wakes, reads the report, dislikes decision #2, and flips the run to controlled
mid-flight per Д7 [458]. Implementer A applies it to new decisions only — decision #2's consequences
keep propagating into tickets 8 through 12 all morning. Implementer B treats the flip as a hard stop and
halts two lanes mid-merge, leaving the `.planning/milestone.lock`-shaped dirty-tree condition that
produced the no-op merge in §4.1 (**VERIFIED**). Implementer C re-opens all 7 decisions as questions in
the Д6 channel, and he now has seven items to answer before anything moves. He asked for one behaviour
and there are three defensible readings.

**Compounding:** three lanes already spawned are running prompts that say "this is an autonomous run".
Nothing in the cluster says a running session learns that its mode changed.

**Collides with:** Д12 [520, 524] (his own soft/hard/custom vocabulary, applied to stops but not to
modes); R1-06 [171], R1-07 [195], R1-08 [204] (his own, same vocabulary).

---

## A11 — Mode is a run-level property, but on an installed platform "controlled" cannot be expressed · major

**The decision.** The mode is chosen per run [075]. But roles sit on different platforms and accounts:

> R1-07 [195, 199] — roles may sit on different accounts; per-platform switching mechanics must be
> configured and **verified to work before a run starts**.
> [041] — providers are «кодекс, чат джіпіті, кімі, GLM, джемінай», each with several accounts.

And he gave an explicit instruction about exactly this:

> **I1 [182–184]** — verify these requirements against each platform; where a platform differs, raise
> the divergence as its own question rather than assuming it works.

**The hole (VERIFIED on this machine, per the research §2.7).** `cursor-agent --help` exposes exactly
one autonomy control: `-f, --force   Force allow commands unless explicitly denied`. One bit. There is
no ask state, no escalation hook, no permission-prompt tool, no "stranded, waiting" event. On that
platform, the owner's "controlled" — *doubt reaches the human and the work holds* — has no
representation inside the tool.

Codex 0.152.0 has a different problem (**VERIFIED**, research §2.6): its `-a on-request` policy means
**the model decides when to ask**, which is the vendor's default and is A9's unbounded clause shipped as
a product feature. Claude Code's own circuit breaker (3-in-a-row / 20-total blocks → pause and prompt)
is **not configurable and does not fire in a headless `-p` run** — "the action doesn't run and Claude
keeps working… Claude Code doesn't stop the run in either case" (**VERIFIED**, research §2.4).

**Concrete failure.** A controlled run, roles assigned per R1-07: orchestrator on Claude, worker on
Claude, validator on cursor-agent (a spare account, chosen precisely to spread the limits). 02:40: the
validator finds an ambiguity in the acceptance criteria. With `--force` on, it resolves the ambiguity
itself and passes the phase — an autonomous decision inside a controlled run, invisible in the report
because the validator's report is the phase verdict. With `--force` off, it hits the first write it
needs, is denied, has nobody to ask, and either loops or returns a failure that reads like a rejected
phase. The owner configured "controlled" for the run; one third of the run was never controlled, and
there is nothing in the mode definition that says a platform may be ineligible.

**The undefined part, plainly:** is the mode a property of the run, of a lane, or of a role? He said run
[075]. His own role/account decisions [195, 199, 270, 276] are per-role. Nothing reconciles them.

---

## A12 — Mode governs decisions; blast radius is machine-level and unattributed · major

**The decision.**

> «оркестратор має бути якось селфевернес, що він, до чого він може змінювати, а що не може, і він має
> працювати тільки з тим, що він працює, і нічого іншого він не мав би доторкатися. Тобто він би не мав
> зупиняти якісь там тести, які не він запускав» **R1-16 [366]**

> «Достатньо лише одного файлу, який може доповнюватись, текстописний … На окремо якогось обов'язкової
> процедури для цього не треба» **R1-15 [357]**

**The hole.** The mode decides *who decides*. It does not decide *what an action can reach*. Both modes
run on one machine, and the previous generation's record shows a machine-level action from inside one
run reaching outside it, with **no attribution afterwards**:

- **FIELD-NOTES §11.5 (VERIFIED)** — "**The owner's default stack was destroyed** by a
  `docker compose down -v` run with no `COMPOSE_PROJECT_NAME` exported… Detected only afterwards from
  image and volume timestamps, and **the actor was never identified**, and a session had refused that
  exact action as owner-only **two minutes earlier**."
- **FIELD-NOTES §11.5 (VERIFIED)** — "**The owner's own container was OOM-killed by two concurrent
  validator builds**… Detected only by correlating timestamps with `docker inspect OOMKilled=true` —
  there was no live alert."
- **FIELD-NOTES §11.10 (VERIFIED)** — two role passwords printed in clear text into a session
  transcript, where "no automated secret scan covers tool output or transcripts". A leak has no undo,
  in any mode.

Prose self-awareness [366] plus one text file [357] is precisely the mechanism that held in one session
and failed in another two minutes later, on the same machine, in the same run.

**Concrete failure, the shared-machine case.** Two runs on this Mac: project A controlled, project B
autonomous (a perfectly reasonable configuration — B is his own repo, A is a client's). 04:15: B's
worker tears down its compose stack without a project name and takes down A's services along with it.
A's lanes fail their health checks and, being controlled, park and wait on questions about failures
that have nothing to do with A. At 09:00 he has a controlled run full of spurious escalations, an
autonomous run reporting success, and — per §11.5 — no record naming which session ran the command.
Neither run's mode was violated. The mode is simply not the thing that governs this.

**Second concrete failure, the control-file case.** Д12 [520] puts the stop commands into "the file the
orchestrator reads every tick", and R1-07 [195] puts account assignments into a file "the orchestrator
or the context watcher keeps re-reading". If either file is resolved at the user scope — which Д1 [416]
invites, since his marketplace's precedence is personal-beats-committed — then `orchestrator:stop-hard`
typed for project B also stops project A's controlled run, releasing nothing and answering nothing.
Nothing in the cluster says whether the mode, the control file and the stop commands are scoped per run,
per project or per user.

**Collides with:** R1-15 [357] and R1-16 [366] (his own — both explicitly decline enforcement
machinery); Д1 [416] (his own config precedence); FIELD-NOTES §11.5, §11.10 (VERIFIED).

---

## What I did not attack, and why

- **That the two modes exist at all.** He is himself unsure — «Не знаю, чи вони будуть відрізнятися»
  [058] — and the research already carries this as its Q-1. An attack on the premise would be
  substituting my preference for his open question, which the rules forbid.
- **«конкретної якоїсь вимірюваної штуки тут не може взагалі бути» [062] as a decision.** It is
  defensible on its own terms; its damage shows up as a *consequence* inside A1, where it removes the
  only after-the-fact detector for the trigger's failure, and that is where it is filed.
- **The choice to make everything configurable.** Attacked only where a specific setting has no
  knowable right answer (A7), no default (A5), or no defined arrival semantics (A10). The general
  preference is his and stands.
