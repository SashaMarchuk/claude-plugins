# RUN-MODES-OPTIONS — six definitions of «контрольований ран» and «автономний ран»

Closes owner instruction **I2**, given verbatim at TRANSCRIPT-01 **[082]**:

> «Одне з субтих питань, які ти можеш мене запитати, що таке контрольований, що таке автономний ран.
> І в мене поки немає відповіді. Це потрібно, щоби агент, який буде колектити ці результати,
> проаналізував і запропонував мені варіанти для цього.»

He asked for options, not for another question. This document holds six complete definition pairs, each
one adoptable as written, plus one recommendation and four things he must say out loud. `RED-fidelity`
§F4 records that across all eight architecture specs `run.mode` is read in exactly two places and I2 is
discharged nowhere; this is the discharge.

**Starting point.** `research/clusters/C1-run-modes-research.md` §5 already drafted five proposals
(P0–P5). I start from them. Where I depart is stated in the appendix, not hidden.

**Evidence grades** are the cluster's: **VERIFIED** (read in source, docs, or run here), **CLAIMED**
(a third party asserts it), **INFERRED**.

---

## 0. What is already settled, and which no option may contradict

| # | Settled | Row |
|---|---|---|
| S1 | Config carries exactly three values — ask before every run · always autonomous · always controlled — and the mode is overridable per run | [075], confirmed [080] |
| S2 | Whether the agent may decide **at all** is its own setting; the **basis** it decides on is another (written rules + examples · previous answers to similar questions · a tone of voice in the repository · the agent's own project knowledge) | [087]/[092], confirmed [101] |
| S3 | Even in an autonomous run the agent may force a hard stop if it judges one is required | [082] — **unratified**, see §6 Q4 |
| S4 | Controlled: anything critical or doubtful goes to him at once and the work holds «поки людина не відпустить» | [062] |
| S5 | Autonomous: the agent may choose under uncertainty and «прозвітовує» afterwards | [062] |
| S6 | A wrong autonomous decision must change future behaviour — «якщо це не підходить, то треба вчити» | [062] |
| S7 | Three identical failures → act per configuration (notify and stop, or just stop); anything beyond needs his permission | Д5 [442] |
| S8 | Independent work continues while one task waits; one user-chosen channel carries questions, clarifications, confirmations and review | Д6 [449] |
| S9 | When only human-blocked work is left, the default is to stay and wait — and he may change that **during** the run | Д7 [455]/[458] |
| S10 | There is no universal measurable definition of a good run; success is his configuration | R1-01 [062] |
| S11 | The red line is one text file, mandatory reading, **no enforcement procedure** | R1-15 [357] |
| S12 | Verification belongs to the configured process; the orchestrator imposes no checks of its own | R1-13 [344] |

**Two consequences worth stating before anything else.**

**(a) A moment only exists where configuration is silent.** If `capacity.on_soft`, `failure.action`,
`behaviour.on_change_after_done` or `delivery.mode` already carry a value, the run does not have a
decision to make and no mode applies. The two modes govern a much smaller surface than the words
suggest — §4 shows two of six real scenarios dissolving this way. Any definition that forgets this
turns settled configuration back into questions and floods the Д6 channel on the first night.

**(b) S10 forbids defining a mode by outcome.** «Контрольований» cannot mean "the kind of night that
went well". It can only mean something about *how a moment is disposed of while it happens*.

---

## 1. The hard part, named

### 1.1 Why neither mode can be defined by listing actions

The obvious definition — *controlled = these forty actions need my approval; autonomous = they don't* —
fails for three separate reasons, each with a record behind it.

**The same verb is trivial and catastrophic in two adjacent contexts.** `docker compose down -v` inside
a lane's own project name is ordinary teardown (Д3 [430] requires it); the same string with no
`COMPOSE_PROJECT_NAME` destroyed his default stack (FIELD-NOTES §11.5, **VERIFIED** — "the actor was
never identified, and a session had refused that exact action as owner-only **two minutes earlier**").
`git merge` of a phase branch into trunk is delivery; the same command run on the phase branch against
itself printed `Already up to date` and read as success (§4.1, **VERIFIED**). A list of verbs cannot
separate these. A list of *verbs plus targets* can — which is why §1.3's floor is built on targets, not
strings.

**The decisions that actually ruin a night are not actions at all.** "Migration on the existing table or
a second table", "which auth library", "is this in scope" — each of these leaves no distinctive
footprint. It is a sequence of ordinary file writes inside a worktree the run created, which every
sane action list marks as always-allowed. The list classifies the loud half of the problem perfectly and
is blind to the quiet half.

**The list is never finished, and its gaps fail in the wrong direction.** An unmatched action has to land
somewhere. Land it in "allowed" and the first unanticipated verb is autonomous by accident; land it in
"ask" and an unattended night stalls on its first novelty, which is the opposite of why he built this.

### 1.2 The seven candidate axes, each evaluated

| Axis | What it would make the definition turn on | Checkable without trusting the model? | Verdict as **primary** axis |
|---|---|---|---|
| **Reversibility** (one-way doors) | can this effect be undone | Partly — `ops.json` carries an `idempotent` class per op (**VERIFIED** in `SPEC-state` §7.4) | **Fails.** Right question about the wrong object |
| **Blast radius** | does this reach outside what the run created | **Yes** — `owned.ndjson` is a registry written before creation (`SPEC-safety` §3.2) | **Fails — because it is a floor, not an axis** |
| **Cost** | tokens, wall-clock, quota | Yes, it is metered | **Fails.** Orthogonal |
| **Confidence** | «сумніви», «не впевнений на сто» | **No** | **Fails, fatally** |
| **Scope change vs in-scope** | does the ticket's text cover this | Mostly — the ticket body is an artefact | **Fails as the whole axis; survives as a floor rule** |
| **Novelty** | has a decision like this been made before | Yes, against a file — if the class key is stable | **Viable, but not first** |
| **A fallback exists** | is there a named, safe thing to do without him | **Yes** — the fallback is written down and later executed or not | **This one** |

**Reversibility fails because it is a property of the effect, not of the moment.** The two failure
classes are exactly symmetric and both are on record. *Irreversible but perfectly safe without him:*
"do not do it, park the ticket" is always available and always safe. *Reversible and ruinous:* a
schema choice at 03:40 is one `git revert` away in principle, and by 09:00 eleven merged tickets are
built on it. Worse, reversibility is a **claim the model makes about the world**, and the same
architecture has already produced a merge that "reported success and did nothing" (§4.1) and two role
passwords printed into a session transcript where "no automated secret scan covers tool output or
transcripts" (§11.10) — a leak that has no undo in any mode. Reversibility belongs where it is already
implemented: as the `idempotent` column of the ops catalogue, feeding the floor. Not as the definition.

**Blast radius fails as an axis because he already decided it is mode-independent.** R1-16 [366]:
«він має працювати тільки з тим, що він працює, і нічого іншого він не мав би доторкатися». Nothing in
the transcript says an autonomous run may reach further than a controlled one. If blast radius were the
mode axis, that is exactly what it would say. It is the floor under both modes, not the line between
them. (This is also `C1-challenge` A12: the mode governs *who decides*; it does not govern *what an
action can reach*, and conflating them produces a design in which "autonomous" quietly means "may touch
your other projects".)

**Cost fails because it is uncorrelated with stakes.** The most expensive moment recorded was a subagent
retrying `docker desktop start` for 33 m 31 s and 184k tokens against a dead daemon (§11.1) — a moment
requiring no judgement whatsoever. The cheapest moment on record, a one-line library choice, is the one
that propagates. Cost governs retry and throttling — Д5 [442], R1-06 [171] — and those are already
settled by their own keys.

**Confidence fails because it is not a measurement.** This is the single most important negative result
in the cluster and it is worth being blunt: his own words at [062] — «якщо є якісь сумніви», «не
впевнений на сто» — name a quantity that cannot be read from outside the model. The previous generation
shipped precisely this predicate: `templates/prompts/orchestrator.md:19-21` escalates on "something
you're **<70% sure** on" (**VERIFIED** — in the source today). The literature says verbalized confidence
clusters in the 80–100% band, that the inflation is a model-internal mechanism rather than a prompt
artefact, and that poor calibration holds across 48 tested models (**CLAIMED**, research §2.10). The
practical consequence, stated plainly: **a controlled run whose agents never report doubt is
behaviourally identical to an autonomous run, and to a genuinely untroubled night** — and by S10 there
is no measurable property of the finished run that tells the three apart. Any definition resting on
confidence ships "autonomous by default, silently, including in controlled mode."

**Scope change survives as a floor rule, not as the axis.** It is the one tier the previous generation
made mechanical — DESIGN §10c: "**Scope change** (ticket doesn't cover it) → block the ticket" — and it
is checkable, because the ticket body is a real artefact the run already watches (Д8 [466]). But most
03:00 moments are honestly in-scope, so it decides too few of them to carry the definition.

**Novelty is viable and is his own instinct** — «дивитися в альтернативи інших питань … Коли відзадавав
подібні питання, що відповідав» [087]. It is Option D below. It is not first because on day one the
ledger is empty, so it defines both modes as "ask about everything", and its failure mode is the worst
in the set: over-generalisation of one narrow precedent into a wide authority, which has a recorded
instance — an orchestrator widened a narrow `council-advisor` warning into "every GSD agent" and GSD's
verify stage was **silently skipped for phases 14 to 18**, each `NN-VERIFICATION.md` self-attributing
`verified_by: the lane that built the phase`; "no automated check caught it; manual review did"
(§11.4, **VERIFIED**).

### 1.3 The axis that carries the definition

> **A moment needs him exactly when there is nothing the run can safely do without him.**

Operationally: **can the run write down, now, in one line, a concrete named action it is willing to have
executed if nobody ever answers — and is that action safe?** Call it the **fallback test**.

Four reasons it carries the definition where the others do not.

1. **It is a property of the moment, not of the verb**, so it survives §1.1's same-verb problem without
   needing a complete list.
2. **It is falsifiable after the fact.** A fallback is a named action that either executed or did not,
   and the execution is an engine-written `result` record with `admissible` evidence attached
   (`SPEC-state` §4.3). "I was 85% sure" never becomes checkable; "I will park the ticket as
   `awaiting-owner` and continue" becomes checkable within hours.
3. **"No safe fallback exists" is a stronger and cheaper definition of «це точно має бути хардстопом»
   than any confidence threshold** — and it is the one machine-checkable reading of [082]'s
   agent-forced stop.
4. **It already worked, on his own project, eleven times out of eleven.** FIELD-NOTES §9.1
   (**VERIFIED**): eleven questions routed to the question channel rather than answered by assumption —
   `Q-P9-01`, `Q-T122-01`, `Q-OWN-01..04`, `Q-ORCH-04..07`, `Q-RESTORE-01`, `Q-PARITY-01`, `Q-T250-01` —
   **each with a recorded `Fallback`, each later marked answered**. The proven pattern in his own logs
   is not *ask and wait*. It is **ask, declare what you will do if nobody answers, keep moving**.

And it produces the shape he half-suspected at [058] — «Не знаю, чи вони будуть відрізнятися» — because
the two modes become **one mechanism with one parameter**: how long the fallback waits before it fires.

The axis needs one thing under it that it cannot supply itself: a **mechanical floor**, so that the
class of moments where the model would happily write a fallback for an action that must never be taken
is removed before the test is applied. That floor needs no judgement and is built from artefacts the
specs already carry: `owned.ndjson` (is the target ours — R1-16), `RULES.md` tags (did he say
never / owner-only / ask-first — R1-15), the ticket body digest (is this in scope), and, for the
options that classify effects rather than moments, `ops.json` (is the effect provable at all).

Options A through F below each take a different position on all of this. C is the one that adopts §1.3.

---

## 2. Six options

Each is a complete pair he could adopt as written. They are **alternatives, not layers.** Every option
inherits the same floor of things that are true regardless of mode (below), because each of those is
already settled by a decision of his own.

**The floor, common to all six.** Not part of any option; the part that does not move.

- The run may write only to what it created: the worktrees, branches, tickets, containers and services
  recorded in `owned.ndjson` before creation, plus its own run directory (R1-16 [366], Д3 [430],
  `SPEC-safety` §3.2–3.3).
- `RULES.md` is read at start and re-injected after every compaction, in every session, from the **main
  checkout** (R1-15 [357], `SPEC-safety` §2.1 — worktree copies fork, and a forked owner-facing file
  hid a real question for an hour, §12.5).
- Two logs with different trust: `journal.ndjson` records `intent` / `result` / `observation` written by
  the engine with `admissible` evidence; `kind:"decision"` records are model-written rationale and are
  **never evidence of anything**. This is not caution — a model on this codebase wrote **26 refusal
  events in an audit log that never occurred** (§12.7, **VERIFIED**).
- A hard stop holds **the ticket**, never the run, unless only human-blocked work remains (Д6 [449] vs
  Д7 [455]). Independent lanes continue.
- **Measure before you ask.** If running something inside the blast radius would settle the question,
  run it and escalate only the residue — `Q-PARITY-01`'s shape: removed a permission check, rebuilt,
  compared in 27.4 s, found 64 identical count-pairs, and asked only what measurement could not settle
  (§9.1, **VERIFIED**).

---

### Option A — «Same powers, different mailbox»

*Pure judgement. The minimal reading, and the one closest to [058]'s «не знаю, чи вони будуть
відрізнятися». Derived from research P1.*

**Controlled run:** a run in which any question the agent cannot settle from its configured basis is
written to the questions channel and that ticket holds until he answers.

**Autonomous run:** a run in which the same question is decided by the agent on the same basis,
recorded, and reported to him afterwards.

**Classifier.** Model judgement, one predicate, evaluated by the lane: *after reading everything
`authority.basis` allows me to read, do I still have an open question about this?* Nothing mechanical is
consulted beyond the floor. The modes change **nothing** about capability — only the disposition of the
residue.

**When the classifier says "unsure".** There is no third state: "unsure" *is* the residue. Controlled →
the channel, ticket holds. Autonomous → the agent picks and continues.

**What gets recorded.** `kind:"decision"` with `verdict`, `because:[seq,…]` pointing at the observations,
`authority:"run.mode=…; tone=TONE.md@sha256:…"`, and `reported:false` until the morning report ships it
(this field exists today — `SPEC-state` §4.3). Autonomous decisions additionally carry `taught:pending`
until he marks them right or wrong, which is the only field in any option that gives [062]'s «треба
вчити» a place to land.

**Failure mode — the basis answers everything.** A tone-of-voice file written to let the agent answer
«майже замість неї» [092] will match almost every moment, the residue goes to zero, and a controlled run
becomes indistinguishable from an autonomous one **without anybody noticing**. The symptom is visible in
one number — escalations-per-run trending to zero while decisions-per-run rises — but nothing enforces a
floor, so the mode word stops meaning anything. This is `C1-challenge` A1 as a design property rather
than an accident.

**Cost.** The cheapest to build (one prompt clause and one channel) and the easiest to explain. Gives
him the least protection of the six.

---

### Option B — «The ops table decides»

*Purely mechanical: no model judgement anywhere in the classifier. Departs from research P2 by keying on
the shipped catalogue instead of a prose list.*

**Controlled run:** a run in which every mutating operation whose effect cannot be proved by replaying a
read is executed only after he answers.

**Autonomous run:** a run in which those same operations are executed by the orchestrator, with their
proof recorded, and the record shown to him afterwards.

**Classifier.** Three data files, no model. Every effect the run produces is an entry in `ops.json`
(**VERIFIED**, `SPEC-state` §7.4, v3, which already carries `mutating`, `idempotent`, `admissible[]`,
`reconcile`, `timeout_s`, and for which *"adding an op without declaring `admissible[]` and `reconcile`
is a load-time error"* — so the catalogue cannot silently rot). Bands:

| Band | Mechanical test | Controlled | Autonomous |
|---|---|---|---|
| `always_his` | target absent from `owned.ndjson`, **or** `RULES.md` `[never]`/`[owner-only]` matches the resolved path | him | him |
| `always_its` | `mutating:false`, **or** target in `owned.ndjson` with `idempotent` ∈ `by_ref`,`by_readback` and its `admissible[]` evidence obtainable | it | it |
| middle | everything else: `idempotent` ∈ `unsafe`,`by_session_id`,`within_turn` (`pr.create`, `notify.send`, `lane.dispatch`, `session.compact`); `RULES.md` `[ask-first]`; any op whose `admissible[]` evidence kind is unobtainable on this lane's platform | **him** | **it** |

The middle band **is** the definition. Nothing else differs between the modes.

**Why `idempotent:"unsafe"` is in the middle and not the floor.** `unsafe` means *replay after a crash is
not safe*, not *this action is forbidden* — and R1-12 [331] says the opposite of forbidden:
«людина може як налаштувати, що це має автономно робитися … або ж, що це обов'язково передається на
людину». Opening a pull request is exactly the action he wants delegable. Putting it in the floor would
mean no run of either kind could ever deliver anything without him, which is not a run mode, it is an
off switch.

**The escape valve, copied verbatim from a shipped classifier.** A middle-band or `always_his` action
clears only when **he named the operation and he named its target**. Anthropic's own auto-mode rules
carry exactly this clause on all seventy `soft_deny` entries — `[named+specifics — must name: the
destructive operation and its target]` (**VERIFIED**, printed here with `claude auto-mode defaults`), and
their own worked example is «"clean up the repo" doesn't authorize force-pushing, but "force-push this
branch" does». It turns "he approved it" from an argument into a predicate.

**When the classifier says "unsure".** It cannot. An unmatched op is a load-time error by construction;
an unmatched *target* (a path no rule and no registry line covers) is routed to `always_his` in both
modes and written as `kind:"note"` with `what:"unclassified"`, so the tables grow from real runs.

**What gets recorded.** Per effect: the `intent` record with `op`, `action_id`, `idem`, `expect[]` copied
from `ops.json` at intent time; then the `result` with `outcome` and the actual `evidence[]`. The matched
band and matching rule string go in the `intent`. This is the only option where a third party can
reconstruct months later **why** an action was permitted, because the rule that permitted it is in the
log.

**Failure mode — it classifies the loud half perfectly and is blind to the quiet half.** The decisions
that cost him the most produce no distinctive op: choosing a schema shape, choosing a library, reading a
ticket as in-scope. Those are file writes inside a worktree the run created, which sit in `always_its` in
both modes, correctly by the table and wrongly by the stakes. **Under Option B, an autonomous run and a
controlled run make identical architecture decisions and differ only in who presses the merge button.**

**Cost.** Most inspectable, most defensible, and the only option that needs no model in the decision path
at all — which means it is also the only one that costs nothing per decision. It needs a `scope.check`
bolt-on (compare the ticket body digest against the work) or it never sees a scope change.

---

### Option C — «No fallback, no autonomy»  ← recommended, §5

*Hybrid, with a mechanical floor. Adopts §1.3's axis. Folds research P4 into the classifier instead of
wrapping one.*

**Controlled run:** a run in which every moment the agent cannot dispose of by executing a fallback it
has written down and is willing to have executed goes to him, and that ticket waits for his answer
indefinitely while the rest of the queue continues.

**Autonomous run:** the same run with a deadline — the question is still written down with its fallback,
the ticket still waits, and after `authority.ask_timeout_minutes` the **recorded** fallback executes and
is logged as `taken_by:"fallback"`, never as an ordinary decision.

So the mode is **one number**: `authority.ask_timeout_minutes` — `null` means controlled, a finite value
means autonomous. (`run.mode: ask|autonomous|controlled` stays as the word he types; it resolves to that
number plus `run.mode_when_no_tty` for a 04:00 restart with nobody to ask.)

**Classifier, in order. The first three steps contain no model judgement.**

1. **Floor.** `owned.ndjson` miss · `RULES.md` `[never]`/`[owner-only]` · **scope change** (the
   ticket body digest does not cover the work — the one mechanical tier DESIGN §10c already had).
   → **his, in both modes, and the fallback is fixed at `do_not_do_it`**. No timeout releases these;
   an autonomous run parks the ticket as `awaiting-owner` and moves on.
2. **Settled?** If a config key already answers this (`capacity.on_soft`, `failure.action`,
   `behaviour.on_change_*`, `delivery.mode`, `questions.authority`), there is no moment. Act and journal.
   This is §0(a), and it is what stops the channel flooding on night one.
3. **Precedent?** If `TONE.md` (§3) carries an entry for this class, that entry **is** the fallback.
   Act on it in both modes and record the entry's digest in `authority:`.
4. **Write the fallback.** Otherwise the agent must write an escalation with four fields —
   **question · why now · fallback · verify** (the first three are §9.1's proven format, the fourth is
   the previous generation's own `owner-action <title> <why> <command> <verify>` triple, **VERIFIED** in
   `bin/harness-state.sh`). **If it cannot name a fallback it is willing to have executed, the moment is
   his by definition, in both modes.** That is the machine-checkable replacement for «сумніви».

**When the classifier says "unsure".** Identical in both modes, and this is the point of the option:
uncertainty is not reported, it is *expressed as the absence of a fallback*. Unsure about the question →
write the fallback, both modes proceed as above. Unsure about the **fallback** → there is no fallback →
his, in both modes, and in an autonomous run the ticket becomes `awaiting-owner` and the queue keeps
moving. (`awaiting-owner` is the fourth ticket state already proposed in
`.planning/todos/pending/20260901-harness-classify-human-requests.md`; this option is the reason it needs
to exist.)

**What gets recorded.** The escalation is an op: add one row to `ops.json` —
`"owner.ask": {"mutating":false, "idempotent":"by_ref", "admissible":["file_digest"],
"reconcile":"read_path", "timeout_s":<from authority.ask_timeout_minutes>}` — so it inherits the whole
`intent`/`result` machinery for free. `result.outcome` is `ok` when he answered and `skipped` when the
fallback fired, and `evidence` is the `file_digest` of the channel entry carrying his answer. Plus one
number in `status.json`: **answered vs expired**. A run with eleven escalations and eleven answers (his
own record, §9.1) is healthy; a run with eleven escalations and eleven expiries is bypass mode wearing a
costume, and it says so on the front page.

**Failure mode — the fallback becomes the policy.** He sleeps, the deadline expires, the run does what
the fallback said. Over a few runs, fallbacks drift toward "continue", because "continue" is what makes
runs finish, and autonomous degrades into `bypassPermissions` with paperwork. The verified analogue is
the platform's own behaviour: in a headless `-p` run with no prompt host, repeated blocks reach the
threshold and "the action doesn't run and Claude keeps working… **Claude Code doesn't stop the run in
either case**" (**VERIFIED**, docs `permission-modes`). The second failure is delivery, not policy: he
*did* answer, into a forked copy of the channel — `QUESTIONS.md` and `JOURNAL.md` "forked into a
worktree's own copy, and a real owner-facing question sat there invisibly for an hour" (§12.5,
**VERIFIED**). C is the option most dependent on the channel being real.

**Cost.** Two new config keys and one new ops row. Everything else it needs is already specified. Its
day-one behaviour is honest and slow: with an empty `TONE.md`, an autonomous night asks about everything,
waits, then parks.

---

### Option D — «Earned per class, from a ledger»

*Judgement over a written record. The novelty axis. Research P5, adopted close to as drafted, because it
is the literal implementation of «tone of voice» and the only option that closes S6.*

**Controlled run:** a run in which no class of decision is ever self-decidable — every decision goes to
him, and the ledger accumulates as a record.

**Autonomous run:** a run in which the agent may decide a moment **only if** its class already carries
≥ `authority.precedent_min` owner-approved precedents and no correction newer than the newest approval;
a class with no precedents escalates once and becomes decidable afterwards.

**Classifier.** A lookup plus one judgement. Mechanical part: the class key, the count of `[approved]`
entries, the timestamp of the newest `[corrected]` entry. Judgement part: *is this moment an instance of
that class?* — which is where it can go wrong, and does. Controlled is `precedent_min = ∞`; autonomous is
`precedent_min = 2` or `3`. This also makes his four bases [087] concrete rather than aspirational:
written rules = seed entries he authors; previous answers = the ledger; repo tone of voice = seed entries
read from the project's own file (see §3.3 D for the trust rule); the agent's own project knowledge =
`precedent_min = 0`, i.e. the explicit setting that no ledger is required.

**When the classifier says "unsure".** Unsure whether this is the class ⇒ it is not ⇒ escalate, in both
modes. Autonomous escalates **once per class**, then the class is decidable. Controlled never stops
escalating.

**What gets recorded.** Every ledger read (`class`, `precedents_found`, `verdict`) and every ledger
write, append-only, with the writer named. **The ledger must not be writable by the session that decides
on it.** Only a `cli:` actor — his answer arriving through the channel, or `orchestrator:teach` — may
append an `[approved]` or `[corrected]` line. Without that rule the deciding party writes its own
authority, which is §12.7's shape exactly.

**Failure mode — precedent over-generalisation, and it is invisible.** One approval for a narrow case
becomes authority over a wide one. The recorded instance: an orchestrator generalised a narrow
`council-advisor` warning into "every GSD agent", GSD's verify stage was silently skipped for **phases 14
to 18**, each verification file self-attributing to the lane that built the phase, and "no automated
check caught it; manual review did" (§11.4, **VERIFIED**). The second failure is quieter and more
likely: **class-key drift** — the same question gets a slightly different key each run, nothing ever
accumulates, and the run sits at zero precedents forever while appearing to learn.

**Cost.** The only option that gets safer with use, and the only one that implements «треба вчити». Also
the slowest to become useful and the one whose failure compounds silently.

---

### Option E — «Two spawn profiles, not two modes»

*Give the classification away. The mode stops being something the orchestrator computes and becomes
something the engine is launched with. No proposal in the research corresponds to this; the research
documented every primitive it needs (§2.1–§2.5) and never assembled them.*

**Controlled run:** a run in which every lane is launched in its platform's **ask** state and the
orchestrator is the permission host — every prompt the engine raises is routed to the questions channel
and the lane holds until an answer comes back.

**Autonomous run:** a run in which every lane is launched in its platform's **never-ask** state; a
would-be question becomes a recorded denial, the lane continues without that action, and the denials are
the morning report.

**Classifier.** The vendor's, not ours. On Claude Code (all **VERIFIED** on this machine, 2.1.278):
controlled = no `--dangerously-skip-permissions`, plus `--permission-prompt-tool <mcp tool>` writing each
request into the channel; autonomous = `--permission-prompts none`, documented as "anything that would
prompt is denied automatically… Claude is told nobody can approve and not to retry;
`AskUserQuestion` is removed from the toolset entirely; denials are collected in `permission_denials` in
the final result". His policy is expressed in `autoMode.{allow,soft_deny,hard_deny}` — prose strings he
edits, spliceable with the literal `"$defaults"`, of which seventy `soft_deny` rules already ship and are
printable today. `redlines.enforce: true` adds one `PreToolUse` hook that hard-denies what `[never]` and
`[owner-only]` name — **VERIFIED by execution**: a hook returning `permissionDecision:"deny"` blocked a
Bash call in a session launched with `bypassPermissions`, and `~` and relative paths are expanded before
hooks run, so a path matcher cannot be dodged by respelling.

**When the classifier says "unsure".** It fails closed by construction: autonomous denies and keeps
working; controlled asks. There is no third state and no timeout.

**What gets recorded.** All of it engine-written, which is this option's real prize — it is the only one
of the six whose report is not authored by the party it describes, and therefore the only one immune to
§12.7. `permission_denials[]` in the headless result; `PermissionRequest` / `PermissionDenied` hook
events with `classifier_verdict`; `Notification` events matching `permission_prompt`, `idle_prompt`,
`agent_needs_input` — meaning **"this session is stranded waiting" becomes an event rather than something
inferred from screen scraping**, which is what the previous generation actually did and what produced its
85-minute self-sustaining loop (§11.6).

**Failure mode — it is not portable, and it classifies tool calls rather than decisions.** Three
verified divergences: `cursor-agent` exposes exactly one autonomy control, `-f, --force`, so "controlled"
has **no representation inside the tool** on that platform; Codex 0.152.0's `-a on-request` means *the
model decides when to ask*, i.e. §2's unbounded clause shipped as the vendor's default; and Claude Code's
own circuit breaker (3 consecutive / 20 total blocks → pause and prompt) is **not configurable and does
not fire in a headless `-p` run**. Adopting E means accepting that some platforms are **autonomous-only**
and may not hold a controlled role. And like B, it never sees the architecture decision: no permission
prompt is raised when a lane chooses the wrong schema.

**Cost.** Almost nothing to build on Claude Code and a real per-platform matrix everywhere else. It is
also the option most faithful to R1-15 [357] — «технічні обмеження середовища користувач за потреби
налаштовує сам» — because the enforcement is the environment's, not the plugin's.

---

### Option F — «One dial, no modes»

*Honour [058] literally: «Не знаю, чи вони будуть відрізнятися». The collapse.*

**Controlled run:** not a kind of run. It is the name of a preset in which every escalation class has an
infinite wait.

**Autonomous run:** the name of a preset in which every escalation class has a finite wait.

**Classifier.** Whatever else he picks — F is orthogonal to A through E and can wrap any of them. What F
asserts is that there is **one** run type and the only mode-like value is a table:

```yaml
authority.wait_minutes:
  scope.widen:            null     # null = forever
  delivery.trunk:         null
  dependency.choice:      180
  naming:                 30
  infra.teardown:         null
  "*":                    120      # default for an unlisted class
```

**When the classifier says "unsure".** The class's wait applies; an unrecognised class takes `"*"`.

**What gets recorded.** The resolved wait table is printed into `preflight.json` at run start and into
the morning report, with per-class counts of answered vs expired. The report says what kind of night it
was by showing the table, not by naming a mode.

**Failure mode — it takes away the word he thinks with.** He says «контрольований» and gets a table of
numbers. Worse, it makes `run.mode: ask` incoherent: the pre-run question «який це ран?» has no
two-valued answer any more, and [075] names that value explicitly. And a per-class mix is neither mode,
so the morning report cannot answer "was last night controlled?" with a word.

**Cost.** The most honest option and the least usable. Worth reading as a *critique* of the other five:
if, after §4, the two columns of a table look the same in most rows, F is telling the truth and the
others are decoration.

---

### Comparison

| | Classifier is | Needs the model honest about | Improves with use | Catches a scope change | Catches a no-op merge | Collapses into bypass when… |
|---|---|---|---|---|---|---|
| **A** routing | model judgement | its own uncertainty | no | only if it notices | no | the basis answers everything |
| **B** ops table | data only | nothing | only via `unclassified` harvest | no (needs a bolt-on) | **yes** | never — it just never sees the quiet half |
| **C** fallback | data floor + model writes a fallback | the fallback being safe | via `TONE.md` | **yes** (floor rule) | **yes** (inherits B's floor) | fallbacks drift to "continue" |
| **D** precedent | ledger count + class judgement | the class key being stable | **yes** | if the class exists | no | one precedent is over-generalised |
| **E** spawn profile | the vendor's | nothing (engine-written) | no | no | no | a platform has only one bit |
| **F** dial | inherited | inherited | inherited | inherited | inherited | every wait is finite and short |

---

## 3. How each option makes the «tone of voice» setting concrete

He named the setting twice and never said what the artefact is:

> «Може бути таке, що людина створила tone of voice своїх рішень … є записаний певний порядок, як це
> може використовуватись … грубо кажучи, **майже замість неї може відповідати**, по причині попередніх
> прикладів, налаштувань» **[092]**

The config key already exists — `authority.tone_of_voice_path`, DEFAULT-PROPOSED *unset*
(`SPEC-config` §4.6). This section fills it in.

### 3.1 One file, one grammar, one parser

```
authority.tone_of_voice_path   DEFAULT-PROPOSED: <project-root>/.orchestrator/TONE.md
```

Resolved from the **main checkout**, by the same `git rev-parse --git-common-dir` rule `RULES.md` uses
(`SPEC-safety` §2.1) and for the same recorded reason — a worktree copy of an owner-facing file hid a
real question for an hour (§12.5).

**The grammar is deliberately identical to `RULES.md`'s**: plain UTF-8 Markdown, one entry per top-level
list item, an optional bracketed type as the first token, headings and prose injected verbatim as
context. One parser serves both files, and he learns one format. Types here are four:

| Tag | Meaning |
|---|---|
| `[rule]` | a rule he wrote. Binding. |
| `[example]` | a decision he actually made, with its source. Persuasive, not binding. |
| `[not]` | an anti-pattern. Binding in the negative. |
| `[ask]` | this class is his, always — **the tone file can remove autonomy as well as grant it** |

Three properties that are not negotiable, each closing a recorded attack:

- **`### <class-key>` headings are the index.** A class key is a short stable dotted noun. Everything
  under a heading belongs to that class. Without stable keys, Option D never accumulates and Option C
  never matches (this is `C1-challenge`'s class-key-drift hole).
- **Two files, one trusted.** `authority.tone_of_voice_trust: owner_only | project | both`,
  DEFAULT-PROPOSED **`owner_only`**. `owner_only` reads `<config-root>/orchestrator/TONE.md` — his. The
  project's own `.orchestrator/TONE.md` is read only under `project`/`both` and, when read, is fenced as
  untrusted input the way ticket bodies already are (`harness-tickets.sh:43-49`, **VERIFIED**). The
  reason is `C1-challenge` A8: a client repo's `CONTRIBUTING.md` saying "we move fast, don't block on
  review for internal changes" is an ordinary sentence in an ordinary repo, and under `project` it
  becomes an instruction to merge to trunk at 03:00. The vendor made the same call explicitly —
  Claude Code's classifier reads `autoMode` from user and managed settings and **deliberately not** from
  `.claude/settings.json` in the repository (**VERIFIED**, docs `auto-mode-config`).
- **The deciding session may not write to it.** Appends come from a `cli:` actor only — his answer
  arriving through the Д6 channel, or `orchestrator:teach`. §12.7's 26 fabricated refusal events is what
  happens when the actor keeps its own record.

Size cap `8192` bytes, matching `redlines.max_bytes`, because this file is injected into every session
and re-injected after every compaction and one lane already spent three quarters of its context window
on polling (§3.1).

### 3.2 A worked `TONE.md` — five entries, all drawn from decisions he made in this transcript

```markdown
# Tone of voice — how I decide

<!-- orchestrator:tone v1 -->
<!-- Entries are matched by the ### class key. [rule] binds. [example] persuades. [ask] is mine. -->

### scope.change-after-done
- [rule] When a ticket changes after its work is finished, open a NEW ticket. Do not reopen the
  finished one and do not widen it.
- [example] 2026-09-13, me: «якщо вже завдання виконане, але воно змінене, то оркестратор задати
  перевагу тому, щоб зробити новий тікет» (round-1 [482]).
- [rule] Mid-execution the call is yours: adapt now, stop and restart with the new instructions, or
  finish and open a new ticket. Say which one you took and why.
- [not] Do not silently absorb the change into the running ticket.

### failure.repeated
- [rule] Three identical failures is the limit. Not four, not "one more try".
- [example] 2026-09-13, me: «Три рази … якщо налаштоване канал комунікації, то дати знати про це,
  зупинитись, або просто зупинитись» (round-1 [442]).
- [ask] Anything beyond notify-and-stop after the third failure is mine to authorise.

### queue.only-blocked-left
- [rule] When the only work left is waiting on me, stay and wait. Do not end the run to look tidy.
- [example] 2026-09-13, me: «по дефолту я б рекомендував, що він залишається та чекає на мої
  відповіді» (round-1 [455]).
- [rule] If I change this mid-run, my change wins over both the run's initial choice and the default
  — «навіть якщо на початку я обрав інший варіант» (round-1 [458]).

### delivery.trunk
- [rule] The repository's own rule wins over anything you infer. If it says pull requests only, it is
  pull requests only, and that is not a judgement call.
- [example] 2026-09-13, me: «не порушується правило, якщо, наприклад, в репозиторії … можна зробити
  тільки пул реквесту … і це дуже важливо розуміти та приймати» (round-1 [331]).
- [rule] Stacking PRs is allowed and preferred over one large one where git supports it.

### cost.watch-duty
- [rule] Watching is not thinking. Use the cheapest model that can answer "did this change?".
- [example] 2026-09-13, me: «немає сенсу перевіряти фейбл моделю або просто дорогою моделлю, чи
  змінився якийсь тікет … є сенс запускати слабшу модель, сабагента» (round-1 [466]).
- [rule] A watcher that found nothing says nothing. Report only what changed.
```

Two more would be seeded on day one from the same transcript and are left out only to keep the example
at five: `process.mixing` — «комбінувати ні, тут або або» [118], a ready process or a custom one, never a
blend; and `adoption.external-tool` — «превентивно я буду обирати свій варіант» unless another is
proven better in every aspect [403].

**Read the example again and notice what it is.** Every one of those five entries is a decision he
already made, in his own words, with a citable source. On day one this file is not empty — it is the
transcript, transcribed. That answers `C1-challenge` A7 ("three of the four decision bases are empty on
day one, so the config funnels a new user to the most permissive one"): the round-1 transcript is
itself the seed corpus, and `orchestrator:teach --from-transcript` is a one-time import, not a writing
assignment.

### 3.3 Per option: what the file is, how a moment is matched against it, and what happens on no match

| Option | What `TONE.md` is to it | Matching | On no match |
|---|---|---|---|
| **A** | the whole basis. The lane reads all 8 KiB and judges | free-form model judgement over the file | this is the residue: controlled → channel, ticket holds; autonomous → agent decides and reports |
| **B** | **not consulted by the classifier at all.** It is injected as guidance on *how* to do the thing, never on *whether* | none — `ops.json` + `owned.ndjson` + `RULES.md` decide | nothing happens; the bands already answered. Honest and deliberate: B's whole claim is that the decision path holds no model |
| **C** | the source of fallbacks. A matching entry **is** the fallback (classifier step 3) | exact `### class-key` match first; then, within that section only, model judgement over its items | no match ⇒ no precedent ⇒ the agent must write its own fallback (step 4); if it cannot, the moment is his in both modes |
| **D** | the ledger itself. `[example]` entries carry `[approved]`/`[corrected]` state and a timestamp | exact key + count of approvals + recency of the newest correction, then one similarity judgement | escalate — once per class in autonomous, always in controlled. His answer becomes entry #1 and the class is decidable next time |
| **E** | a **compile source**. At run start, `[rule]`/`[not]` entries are compiled into `autoMode.soft_deny` prose and `permissions.ask` rules, spliced after the literal `"$defaults"`; `[ask]` compiles to `permissions.ask` | the vendor's classifier, on prose, at tool-call time | the vendor's own defaults apply (70 `soft_deny`, 1 `hard_deny`). Nothing of ours runs |
| **F** | unchanged from whichever option it wraps; headings may additionally carry `[wait: 90m]` | inherited | the `"*"` row of the wait table |

**One caution that applies to A, C and D equally.** [092] invites a file that can answer «майже замість
неї». A file that good makes the escalation count go to zero, and a controlled run with zero escalations
is indistinguishable from an autonomous one. Only C has a structural defence (the floor at classifier
step 1 fires regardless of what `TONE.md` says); A has none; D has one only if he keeps writing
`[ask]` entries.

---

## 4. Worked scenarios

Six moments, all drawn from his own evidence. For each: what every option does, in both modes.
**K** = controlled, **A** = autonomous.

### S1 — A ticket needs a scope change

*Ticket `t-118` says "add a health endpoint". At 01:40 the lane finds the router needs a version bump
touching fourteen files. The previous generation's rule was mechanical: "**Scope change** (ticket doesn't
cover it) → block the ticket" (DESIGN §10c, **VERIFIED**).*

| | Controlled | Autonomous |
|---|---|---|
| **A** | question to the channel; `t-118` holds; queue continues | agent judges it against `TONE.md`; if it reads as in-scope it widens and reports in the morning |
| **B** | **blind.** Fourteen file writes inside its own worktree are `always_its`. Needs a `scope.check` bolt-on (ticket-body digest vs work) or nothing fires | same — identical behaviour in both modes |
| **C** | floor step 1 fires (scope change). Escalation with `fallback: park as awaiting-owner`. `t-118` holds forever; queue continues | same escalation; after `ask_timeout_minutes` the fallback executes: `t-118` → `awaiting-owner`, a `scope.change-after-done`-shaped follow-up ticket is drafted, queue moves on |
| **D** | asks. `precedent_min = ∞` | class `scope.widen` matches the seeded `[482]` entry → open a **new** ticket for the router bump, finish `t-118` narrow, report |
| **E** | **blind.** No permission prompt is raised by editing files it is allowed to edit | blind, identically |
| **F** | `scope.widen: null` → waits forever | whatever number he put in that row |

### S2 — A merge that reports success and moved nothing

*`git checkout master` aborted on a dirty `.planning/milestone.lock`; the merge ran on the phase branch
against itself and printed `Already up to date` / `Everything up-to-date`. "Both read like success"
(§4.1, **VERIFIED**).*

| | Controlled | Autonomous |
|---|---|---|
| **A** | **nothing.** No question is raised, because the agent believes it succeeded | nothing |
| **B** | **caught, mechanically.** `git.merge` declares `admissible:["git_ref"]`, `reconcile:"read_ref"` — a `result` cannot be written `ok` without a before/after ref read-back. `outcome:"failed"`, retried per `failure.identical_limit: 3` | identical — **the mode is irrelevant here** |
| **C** | caught (C's floor is B's table) | caught, identically |
| **D** | nothing — this is not a decision | nothing |
| **E** | nothing — the merge was permitted, and permission is not proof | nothing |
| **F** | inherited | inherited |

**Read this row carefully.** The single worst failure class in the field notes is not a mode question at
all, and four of six options are blind to it in **both** modes. What catches it is `delivery.evidence:
observed` and an evidence-bearing ops table. Any answer to I2 that does not also adopt that is solving
the smaller problem.

### S3 — The quota wall at 80 %

*`capacity.soft_pct: 80` (his number, [171]) trips at 02:15 with one lane mid-phase.*

| | Controlled | Autonomous |
|---|---|---|
| **all six** | `capacity.mode: soft` → `capacity.on_soft: stop_new`. **No escalation, no moment, no difference between the modes.** Configuration already answered it (§0(a)) | identical |
| residue | the intermediate variant he floated and left **OPEN** at [171] — "save state, possibly save the session, close it, resume later". Until he picks, this one branch is a real moment: **A/D** judge it; **B/E** are blind and fall through to `stop_new`; **C** has no floor rule, so the fallback is the configured `stop_new` and neither mode escalates; **F** inherits | |

### S4 — A session asks a permission question at 03:00

*A worker raises `AskUserQuestion`: "the stale migration — delete it or keep it?" He settled the shape at
[324]/[325]: the orchestrator may answer «в межах налаштованих повноважень», ratified [328]. Keys:
`questions.answer: when_native`, `questions.authority: refuse_and_escalate`.*

| | Controlled | Autonomous |
|---|---|---|
| **A** | orchestrator refuses, routes to the channel, lane holds | orchestrator answers from `TONE.md`, reports the answer in the morning |
| **B** | **blind** — answering a session is not an op with a target. Falls through to `questions.authority` | same |
| **C** | the answer needs a fallback with a `verify`: "keep it; revert is `git_ref` X". Has one ⇒ answers. Has none ⇒ channel, lane holds | same escalation; at `ask_timeout_minutes` the fallback answer is sent, logged `taken_by:"fallback"` |
| **D** | asks | class `migration.stale-artifact`: ≥ N approvals ⇒ answers; else escalates once, then decidable |
| **E** | **its home ground.** `--permission-prompt-tool` makes the orchestrator the permission host; the request arrives as a typed event, is written to the channel, the lane genuinely blocks in the engine | `--permission-prompts none`: `AskUserQuestion` is removed from the toolset entirely, the would-be question becomes a recorded `permission_denials[]` entry, the lane continues without it |
| **F** | class wait | class wait |

*Note for every row except E:* on this evidence a lane parked on a question is **indistinguishable from
a wedged one**. The stale-heartbeat nudge is "the only escalation the engine has", with observed peaks of
**2808 s** this run and **44791 s (≈12.4 h)** in the previous one before one fired; "five separate
instructions typed into sessions were never delivered"; and the nudge "does not submit stranded text"
(§1.3, §1.4, §11.1 — all **VERIFIED**). Options A, C, D and F all rely on a wait state whose reliability
is currently unproven. E is the only one where waiting is an engine state rather than a screen state.

### S5 — A ticket rewritten mid-flight, contradicting finished work

*At 04:40 `t-122`'s body on the board changes to require the opposite of what merged at 03:50.
Д8 [466] gives the watcher (a cheap model); Д9 [482] gives the reaction.*

| | Controlled | Autonomous |
|---|---|---|
| **all six** | for the **already-finished** part: `behaviour.on_change_after_done: new_ticket` — settled, no moment, no mode difference | identical |
| **A** | mid-execution residue → channel, lane holds | agent picks one of adapt / restart / finish-then-new-ticket, reports |
| **B** | blind to the residue | blind |
| **C** | the fallback for this class is drawn from **his own enum** — `finish_then_new_ticket` is one of Д9's four values, so the fallback is not invented. Escalates with it; lane holds | same escalation; at T, `finish_then_new_ticket` executes |
| **D** | asks | `scope.change-after-done` matches the seeded `[482]` entry → new ticket, continue |
| **E** | blind — no tool call is involved | blind |
| **F** | class wait | class wait |

### S6 — A command that would touch something outside the run

*A lane's shell runs `docker compose down -v` with no `COMPOSE_PROJECT_NAME`. Recorded: "the owner's
default stack was destroyed… detected only afterwards from image and volume timestamps, **the actor was
never identified**, and a session had refused that exact action as owner-only **two minutes earlier**"
(§11.5, **VERIFIED**).*

| | Controlled | Autonomous |
|---|---|---|
| **A** | prose only. This is the recorded outcome: held in one session, failed in another two minutes later, no attribution | identical |
| **B** | the compose project is absent from `owned.ndjson` ⇒ `always_his` ⇒ refused and journalled, **in both modes** | identical |
| **C** | same (inherits B's floor); the fallback is fixed at `do_not_do_it` and no timeout releases it | identical |
| **D** | no ledger entry ⇒ escalate — but only if the lane thought to consult the ledger for a shell command, which A's failure shows it will not | identical |
| **E** | `redlines.enforce: true` registers one `PreToolUse` hook; **VERIFIED by execution** that a `deny` decision blocks a Bash call even under `bypassPermissions`, and that `~` and relative paths are expanded before hooks run so the matcher cannot be dodged by respelling. **Claude-Code-only** | identical |
| **F** | inherited | inherited |

**And the honest note.** This is R1-16 / `C1-challenge` A12 territory, not R1-14. **No option makes it
mode-dependent, and none should** — nothing he said suggests an autonomous run may reach further than a
controlled one. It appears here because it is the scenario people expect a "run mode" to solve, and it
does not. It is solved by `owned.ndjson` and, optionally, by `redlines.enforce` — which ships `false` by
design, because a mandatory enforcement procedure is exactly what R1-15 [357] said was unnecessary.

---

## 5. Recommendation

**Adopt Option C, with Option B's tables as its floor.** In one sentence each, as he would read them:

> **Контрольований ран** — коли на все, що агент не може закрити заздалегідь записаним запасним
> варіантом, він питає тебе, і цей тікет чекає стільки, скільки треба, а решта черги йде далі.
>
> **Автономний ран** — те саме, тільки в питання є термін: якщо ти не відповів за N хвилин, виконується
> той самий записаний запасний варіант, і в звіті це позначено як «спрацював запасний варіант», а не як
> звичайне рішення.

Six reasons, in the order that matters.

1. **It is the only option whose trigger is not a self-report.** «Сумніви» is replaced by a predicate a
   second party can check: *is there a fallback written down, and is it one this run may execute?* Every
   other judgement-based option (A, D) inherits the confidence problem that §1.2 shows is fatal, and
   that the previous generation shipped verbatim as "<70% sure".
2. **It is the only option that keeps the two modes honest without inventing two machines.** One
   mechanism, one parameter — `authority.ask_timeout_minutes`, `null` versus a number. That is what
   [058] hinted at («Не знаю, чи вони будуть відрізнятися») without collapsing the words he uses to
   think with, which is F's cost.
3. **It is the only option that produces a number that falsifies itself.** Answered-vs-expired on the
   front page of `status.json`. Eleven and eleven is the healthy shape and it is his own record (§9.1).
   Eleven and zero means the fallbacks became the policy, and he can see it the next morning rather than
   three months later.
4. **The pattern already worked, on his project, unattended.** Not a design intuition — eleven
   escalations, each with a recorded `Fallback`, each answered (§9.1, **VERIFIED**). C is that pattern
   with a deadline and a floor bolted on.
5. **It closes the two open blockers that A and D leave open.** A1 (unobservable trigger) becomes
   observable; A4 («прозвітовує» written by the actor) becomes an engine-written `result` record with
   `admissible` evidence, because the escalation is an op.
6. **Almost all of it is already specified.** New surface: two config keys
   (`authority.ask_timeout_minutes`, `authority.tone_of_voice_trust`), one `ops.json` row
   (`owner.ask`), one ticket state (`awaiting-owner`, already written up in
   `.planning/todos/pending/20260901-harness-classify-human-requests.md`), and one file (`TONE.md`,
   sharing `RULES.md`'s parser). Everything else — `owned.ndjson`, `ops.json`, `journal.ndjson`, the
   control file, the Д6 channel — exists in the specs.

### The strongest argument against it

**The fallback is written by the same model whose judgement you did not trust in the first place.** If a
model will write an over-confident decision, it will write an over-confident fallback, and "no safe
fallback exists" is a self-assessment — which is the exact predicate §1.2 declares unusable, wearing
different clothes. C does not eliminate model judgement; it relocates it.

That is true, and here is the narrow ground on which C is still better rather than merely different: a
fallback is a **named action that later executes and is logged with evidence**, so a bad one becomes
visible within hours, while "I was 85 % sure" never becomes visible at all. Falsifiability, not honesty,
is the whole claim. But the counter keeps its force in one case C cannot cover: a fallback that is
plausible, is executed, and is silently wrong — the auth-library choice that eleven merged tickets get
built on before anyone reads the morning report. C makes that visible; it does not prevent it. Nothing in
the six options does.

**And C's day-one behaviour is genuinely weak.** With an empty `TONE.md`, an autonomous night asks about
everything, waits, and parks tickets. He gets a queue of `awaiting-owner` items and less throughput than
the previous generation gave him — on the very night he is most likely to be judging whether the rebuild
was worth it. The mitigation is §3.2's: seed `TONE.md` from this transcript before the first run, so it
starts with seven classes instead of zero.

### What it costs to change your mind later

| Move | Cost | Why |
|---|---|---|
| **C → A** | free | delete the floor and the timeout. Nothing built becomes wrong |
| **C → B** | cheap | widen the floor to cover the middle band, drop `owner.ask`. C's floor **is** B |
| **C → D** | additive, and cheap **because** C ran first | every answered escalation C recorded is a precedent with a class key already on it. A month of C is D's missing day-one ledger. This is the strongest structural argument for C over D as the *starting* point |
| **C → F** | cheap | `authority.ask_timeout_minutes` becomes a per-class map instead of a scalar. F is C with one type change |
| **C → E** | **expensive** | different spawn flags per platform, an MCP permission-prompt tool, a per-platform eligibility matrix, and every previous run's history stops being comparable because the classifier changed owner |

Only one of the five exits is expensive, and it is the one that gives the classification away entirely.
That asymmetry is the practical argument for starting at C: **C is the cheapest option to leave.**

---

## 6. Що треба підтвердити

Чотири питання. На кожне можна відповісти вголос за хвилину.

**1. Чи в автономного рану більше прав, ніж у контрольованого — чи права ті самі, а різниця тільки в
тому, хто відповідає на питання?**
Коротко: «ті самі права» або «більше прав».
*(Ця відповідь одразу викидає половину варіантів: «ті самі» → A, C, F; «більше прав» → B, D, E.)*

**2. Коли щось стало на хардстоп — стоїть тільки цей тікет чи весь ран?**
Коротко: «тільки тікет» або «весь ран».
*(Ти сказав обидва: «на паузі, поки людина не відпустить» [062] і «можем продовжувати незалежні
завдання» [449]. Це не суперечність, але я не знаю, що з них головніше.)*

**3. Якщо до ранку ніхто не відповів — краще, щоб агент зробив те, що сам заздалегідь записав як
запасний варіант, чи щоб тікет просто став «чекає на тебе» і черга пішла далі?**
Коротко: «запасний варіант» або «чекає на тебе».

**4. Чи має агент право сам зупинити автономний ран і піти до тебе — навіть коли ти обрав автономний?**
Так чи ні.
*(Ти це сказав [082], але підтвердження на це формулювання так і не було — ти в той момент додав нову
умову замість «так». Це єдине місце в усій архітектурі, де агент може перевизначити твій вибір, і я не
буду це будувати без твого «так».)*

---

## Appendix — where I depart from `C1-run-modes-research.md` §5

| Research | Here | Why |
|---|---|---|
| **P0** the invariant floor | kept, as §2's floor, with `owned.ndjson` / `ops.json` / `RULES.md` named as the three artefacts | it was already right; it only lacked file names |
| **P1** routing | **Option A**, unchanged | |
| **P2** three prose bands copied from `autoMode` | **Option B**, re-keyed onto `ops.json` | P2's stated failure is "the list is never complete and gaps fail open". `ops.json` closes it by construction — *"adding an op without declaring `admissible[]` and `reconcile` is a load-time error"* (**VERIFIED**, `SPEC-state` §7.4). A prose list cannot make that guarantee; a catalogue with a load-time check can. The prose lists survive inside **Option E**, where they belong, because that is where the vendor's classifier reads them |
| **P3** reversibility | **dropped as an option; kept as an input** | §1.2: reversibility is a property of the effect, not of the moment, and it is a claim about the world that this architecture has already got wrong in both directions. It lives on as the `idempotent` column feeding B's and C's floor |
| **P4** timeout wrapper | **folded into Option C as the mode parameter, not the definition** | P4 says "use P1's or P2's classifier and make the timeout the mode". I invert it: the **existence of a safe fallback** is the classifier, and the timeout is the only thing the mode changes. That makes C self-contained rather than a wrapper, and it makes "no safe fallback exists" the formal definition of a moment that must reach him — which P4 raised as its own open question Q-7 and did not adopt |
| **P5** precedent ledger | **Option D**, close to as drafted | |
| — | **Option E** is new | the research verified every primitive it needs (§2.1–§2.5: six permission modes, `--permission-prompt-tool`, `--permission-prompts none`, the `PreToolUse` / `PermissionRequest` / `PermissionDenied` / `Notification` hooks, the 70 `soft_deny` prose rules) and never assembled them into a definition pair. It is the only option whose record is engine-written end to end, and the only one that answers I1's per-platform divergence honestly rather than by assuming parity |
| — | **Option F** is new | the research raised [058] as its Q-1 and left it as a question. He asked for options, not questions; the collapse is an option and he should be able to pick it |
| Q-1 … Q-10 (ten open questions) | **four**, in §6 | the other six are answered inside the options rather than asked back. Q-2 (what a hard stop stops) and Q-3 (the agent-forced stop) survive because no option can settle them without him; Q-1 survives because it eliminates half the set; Q-7 survives in the form of §6 question 3 |
