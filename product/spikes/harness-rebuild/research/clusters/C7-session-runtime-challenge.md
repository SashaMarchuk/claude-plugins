# C7 — Session runtime: the adversarial pass

Cluster: **C7-session-runtime** · Item: **R1-11** · Written 2026-09-19
Companion to `C7-session-runtime-research.md`. That document asked what is *possible*. This one asks
what *breaks*.

**Rules I held myself to.** Every attack names a concrete failing scenario, with a time, a state and
an outcome — not a worry. I do not propose a redesign of any decision he made; I name the hole. Where
a decision collides with another of his decisions, both are quoted with their `[row]` anchor. Where it
collides with the previous tool's real 34-hour run, the FIELD-NOTES section is cited. Evidence is
graded **VERIFIED** (read in source, or run on this machine and pasted), **CLAIMED** (a doc says so),
**INFERRED** (my reasoning, marked as mine). Attacks I raised and then killed are in §14, because a
reviewer who reports only survivors is hiding his hit rate.

---

## 0. The decision under attack, verbatim

> «Наприклад, **тільки інтерактивні сесії, або тільки headless
> сесії, тощо, так далі, або гібрид, або переважно інтерактивні і тільки інколи headless**, тощо, так
> далі. … Друге, це те, що **оркестратор може робити інтерактивність зесіями, наприклад, з тим самим
> код-кодом, якщо він раптом використовує ask user question, то оркестратор може відповідати на ці
> питання, і це повністю і повністю окей**» — **[324]**

In English, the rest of the answer: it all depends on configuration, each platform gets its own setting, and running Claude Code invisibly in headless mode is possible **"але з цим треба бути дуже обережним"**.

Confirmed at **[328]** («Так, підтверджую, переходимо до наступного питання») against a restatement
**[325]/[327]** that added a qualifier he never spoke — «в межах налаштованих повноважень». That
phrase is the interviewer's; `research/extract/by-item.md` (R1-11, row 3) flags it as such. Four of
the twelve attacks below exist only because that qualifier is not his. That is not a reason to
silently adopt it — it is a reason to put it to him.

Worth keeping in view: the **question** he was answering was narrower than the answer. R1-11 as asked
at **[319]/[320]** was «Чи потрібно, щоб кожна сесія була у видимому терміналі, **куди ти можеш зайти
і написати руками**, чи частина ролей може працювати невидимо?» — the human walking up to a session
and typing is in the premise, and he did not reject it. Attack A8 lives in that gap.

---

## 1. A1 — BLOCKER — «повністю і повністю окей» has no refusal class, so a controlled run stops being controlled

**The collision, both sides quoted.**

> «оркестратор може відповідати на ці питання, і **це повністю і повністю окей**» — **[324]**
> (`research/extract/outside-list.md` reads the doubling as pre-empting an objection — he expected to
> be argued with and closed the door in advance.)

> «якщо є якісь сумніви, то коли контрольований, то вони **йдуть зразу до мене** і ставлять умовного
> хардстоп … робо каже, що це на паузі, **поки людина не відпустить**, якщо це контрольований ран» — **[062]**

An AskUserQuestion call from a child session **is** «сумнів» in the only form a session can express
one. R1-14 says that doubt goes straight to him and the work holds. R1-11 says the orchestrator
answers it and nothing holds. Both are his, both are confirmed ([080]/[101] and [328]), and nothing
in either answer says which wins.

**Concrete failure.** 03:40, controlled run, one ticket queued. The worker reaches a schema change and
calls AskUserQuestion: *"The migration drops `users.legacy_id`. Proceed, or keep the column and
backfill?"* — two options, both defensible. The orchestrator is a configured question-answerer, the
answer is within its ability, so it answers "Proceed". No hard stop is raised, no notification is
sent (R1-17 [395] is about channels, not triggers), the work does not pause, and at 09:00 the column
is gone and merged. The human's own rule — doubt reaches him, work holds — never fired, because the
doubt was consumed one layer below where the rule lives.

**What is undefined, precisely.** Whether a *question from a child session* is (a) an event the
orchestrator resolves, or (b) an escalation trigger, or (c) either, depending on run mode. Two
implementers reading [324] and [062] will build different systems and both can defend themselves from
the transcript. The machinery for (b) already exists in his own words — «Якщо агент вирішив, що це
точно має бути хардстопом … відбувається хардстоп, і йдеться до людини, **навіть якщо це автономний
ран**» [082] — but that is the agent deciding about *itself*, not the orchestrator classifying a
question it received.

**Why "the user configures it" does not save this.** He gave the authority *basis* as configurable —
tone of voice, past answers, repository documents, project knowledge [087]/[092] — but a basis tells
you *how to answer*, not *whether this one is yours to answer*. There is no configured predicate for
"refuse and escalate", and he named none.

**Severity: blocker.** It decides whether "controlled run" is a real mode or a label. Everything in
C1 is built on that distinction.

---

## 2. A2 — BLOCKER — headless AskUserQuestion is answered with nothing, and his verification decision guarantees nothing will notice

**VERIFIED, run on this machine** (research §4.1). A headless Claude Code session whose
AskUserQuestion call is *allowed* receives:

```json
"content":"User has answered your questions: . You can now continue with the user's answers in mind."
"tool_use_result":{"questions":[…],"answers":{}}
```

`answers: {}`. The sentence ends in a bare period where the answer should be. The child model in that
run noticed — *"the function result says 'User has answered your questions: .' without showing what
the answer was. This is unusual…"* — and completed the task anyway.

**The collision is with his own verification decision.**

> «оркестратор повинен діяти відповідно тому сетапу, який в нього є … ці всі перевірки відбуваються
> **виключно так, як юзер налаштував** … **не роби обмеження** те, що вся робота потім буде мати
> тести, і що є якийсь готовий воркфлоу» — **[344]**

The orchestrator imposes no checks of its own. So the only thing that could catch a session that
built on a phantom answer is the user's own process — and no user's process contains a test for "did
my agent receive the answer it thinks it received". It is not a category any test framework has.

**FIELD-NOTES says this exact failure shape is the one that actually happens.** §4.1: a merge printed
`Already up to date` / `Everything up-to-date` and moved nothing; caught only because someone checked
what `master` pointed at afterwards. §11.4: GSD's verify stage was silently skipped for phases 14–18,
each `NN-VERIFICATION.md` self-attributing `verified_by: the lane that built the phase`; "No automated
check caught it; manual review did." §11.4 again: a tracked-tree sweep claimed exit 0 against 1242
bytes of real diff.

**Concrete failure.** 02:15, autonomous run, `claude` configured `headless` for this platform per
[324]. Worker on an auth ticket asks: *"Session cookies or JWT?"*. Told it was answered, given
nothing, it picks JWT, writes 400 lines, GSD's verify runs and passes (the code is internally
consistent), the phase merges. At 09:00 the owner finds a JWT implementation in a codebase that uses
cookies everywhere, and a transcript that says the user answered the question.

**The hole.** He said «з цим треба бути дуже обережним» about headless without naming what to be
careful *about* — reasonably, since he had no way to know this. But the decision as recorded
("headless is a configurable per-platform mode") ships this behaviour as a default-reachable state,
and his own no-extra-checks decision removes the net under it. **Nothing in the record says the
orchestrator must guarantee a question channel exists before it launches a session headless.**

**Severity: blocker.** This is silent corruption, unattended, at scale, on the mode whose entire
purpose is running while nobody watches.

---

## 3. A3 — BLOCKER — a headless *orchestrator* asks into the void, and the single-orchestrator invariant closes the only exit

«Тільки headless сесії» is a valid setting, applied «під кожну платформу» [324] — and the
orchestrator runs on a platform. Nothing in the answer exempts the orchestrator from the mode
configured for its platform.

**Collision, his side both times.**

> «не може бути такого, що вже якісь існуючі оркестратор і спускається наступний, тому що тоді це
> буде просто нескінченний цикл оркестраторів» — **[300]** · «Це треба відслідковувати і **не
> дозволяти**» — **[301]**

> «має бути щось, що може допомогти запустити ран і продовжити роботу **без участі в налаштуваннях
> користувача**» — **[266]**

The orchestrator is the thing that answers everyone else's questions. When *it* asks — an
AskUserQuestion, a permission prompt, an MCP elicitation — there is by construction nobody above it,
and by [300]/[301] nobody may be spawned to become that. Headless, per A2's verified behaviour, it is
told it was answered and proceeds. With the orchestrator's blast radius: it is the process that
merges to trunk (R1-12 [331]), that spawns and closes sessions, that decides recovery [293].

**Concrete failure.** 04:55. The orchestrator, running headless, hits a conflict between the ticket
and the repository rule he called «дуже важливо» ([331]: "only PRs allowed here"). It asks *"Merge
directly or open a PR?"*, receives `answers:{}`, reads the empty answer as permission, and merges
direct to `master`. FIELD-NOTES §10.1 records that the previous run's orchestrator was itself the
component that died and had to be replaced five times — the orchestrator is not a reliable narrator
of its own state, and here it has no supervisor at all.

**Undefined.** Who answers the orchestrator. The three candidate answers all exist in his material
and none is chosen: the human (but then autonomous runs stop at 05:00), a health-check agent «раз в N
годин на якійсь іншій підписці» [246] (but that agent is specified as a *liveness* probe, not an
answering authority), or nobody (A2's corruption, with root privileges).

**Severity: blocker.** Lower probability than A1/A2 — it needs the orchestrator itself to ask — but
the worst blast radius in the cluster, and `[300]` structurally forbids the obvious fix.

---

## 4. A4 — MAJOR — "headless" names four different Claude Code runtimes, and the most natural one cannot be answered at all

He said «запускати його в headless режимі» [324] as if Claude Code had one such mode. **VERIFIED** it
has four (research §3.1): one-shot `-p`; long-lived `-p --input-format stream-json --output-format
stream-json`; `claude --bg` with a real registry; and a detached PTY, which is invisible until someone
attaches and is therefore also "headless" in the sense the question asked ("не у видимому терміналі").

They differ on the exact axis his second sentence depends on. **VERIFIED** (§4.3): `claude --bg`
exposes `agents`, `attach`, `logs`, `stop`, `rm`, `respawn`, `--resume` and **no send/answer verb**;
`claude agents --json` reported `"state":"blocked"` on two of the owner's own real background sessions
while I looked. A blocked background session is unblocked only by `claude attach <id>` — that is, by
ceasing to be headless.

**Concrete failure.** The implementer reads "headless" and picks `--bg`, which is the mode Claude Code
actually markets as backgrounded, ships a registry for, and which matches «щось буде невидимо» most
literally. 01:10: worker blocks on a permission prompt. The orchestrator's answering logic has no
channel to it. FIELD-NOTES §1.6 is the precedent for what happens next: a `question`-role session
finished and sat registered and idle for **one day and four hours** with nobody to close it; §11.1
records a stale heartbeat peaking at **44791 s (12.4 hours)** before anything fired. The ticket is
still unstarted at 09:00 and the run looks alive the whole time.

**The hole.** "Headless" is not a runtime, it is a property. He specified the property. The decision
does not say which runtime realises it, and the choice determines whether his *second* requirement —
the orchestrator answers questions — is achievable or impossible. Two implementers, two systems, both
faithful to [324].

**Severity: major.** Deterministic once the wrong runtime is chosen, and the wrong one is the
better-signposted one.

---

## 5. A5 — MAJOR — per-platform is the wrong axis, and his own three-window example cannot be expressed in it

> «**Під кожну платформу своє налаштування**, і це окей» — **[324]**

> «якщо, наприклад, в мене є Клод Код, і допустимо, **три вікна, перше, це контекст вочер, друге, це
> оркестратор, третє, це екзек'ютор**, чогось, то я для кожного з них можу вказати, який буде поріг
> компакту, і як саме компакт повинен відбуватися» — **[204]**

Both are his. [204] configures *per window inside one platform*; [324] configures *per platform*. They
are different keys. And [204]'s three windows are all Claude Code — the platform axis cannot separate
them.

**Concrete failure.** He wants what he already had: an orchestrator he can look at and type into, and
thirteen workers he does not want thirteen windows for. An implementer keying on [324] literally
writes `platforms.claude.mode = "interactive"`, and every worker in the run opens a visible terminal.
FIELD-NOTES §9.5 shows nineteen phases, worker sessions of 58 minutes to 5 h 31 m, two lanes
overlapping — that is 19 windows over 34 hours on a machine that is also his workstation. FIELD-NOTES
§8 is the corroboration that the previous tool already found the platform axis insufficient: accounts
were routed **per role** (`orchestrator`, `worker`, `validator`, `question`), not per platform, and
mid-run every role was moved, which "reaches the next spawn" only.

**The hole.** He named one axis and demonstrated a second in a different answer. Nothing says how they
compose, which wins, or whether a role override exists. `research/extract/by-item.md` records the
role taxonomy «контекст вочер / оркестратор / екзек'ютор» recurring at [036], [195] and [204] and never
appearing in the analysis at all.

**Severity: major.** Not silent — the user sees 19 windows and complains — but it makes the config
unable to express his own stated setup on day one.

---

## 6. A6 — MAJOR — «тільки інколи headless» has no predicate, and both honest readings collapse the mode

> «або гібрид, або **переважно інтерактивні і тільки інколи headless**» — **[324]**

This is his own invention; the interviewer's list did not contain it. It is the only one of the four
modes that is a *policy* rather than a setting: something must decide, per session, which way this one
goes. He named no predicate, no budget, no flag, no default.

**Concrete failure, reading 1.** The implementer makes it a per-ticket opt-in. No ticket sets it,
because tickets are written by him and by agents that do not know the flag exists (FIELD-NOTES: ticket
bodies are gated on Outcome/Acceptance/Scope headers, nothing else). "Mostly interactive, occasionally
headless" is operationally identical to "only interactive" for the life of the project, and the
capability he asked for is dead code.

**Concrete failure, reading 2.** The implementer makes it time-based — headless when no human is
likely awake — which is the reading the *purpose* of the tool suggests. At 23:00 the whole fleet flips
to headless. That means the run's entire unattended stretch, which is all of it, executes in the mode
he flagged «треба бути дуже обережним», with A2's verified corruption live the whole time. Mode 4
becomes mode 2 every night.

**Undefined.** What "інколи" measures — count, concurrency budget, ticket class, time of day,
authority coverage, or the orchestrator's own judgement. Six plausible predicates, no tiebreak.

**Severity: major.** Reading 2 silently activates a blocker-severity behaviour on a mode chosen
*because* it sounded cautious.

---

## 7. A7 — MAJOR — nothing states the default, and the two candidate defaults fail in opposite directions

Everything in R1-11 is «залежить від конфігурації» [324]. Nowhere in the transcript does he say what
runs when the user configures nothing. His general instinct is quoted often and points at neither
option: «Тому тут **нічого надприроднього** не потрібно вигадувати» [171], «це має бути надійна річ,
**дуже проста**» [300].

**Concrete failure, default = interactive.** First run on a second machine. The user installs and runs
without a config. Twelve sessions open twelve terminal windows. The run also inherits the PTY failure
family recorded in FIELD-NOTES §1.3 / §11.2 — five instructions never delivered, two real operator
instructions (`push master`, `carry on with the queue`) sitting unsubmitted while the engine logged
them as nudged — and, if the machine sleeps, the ending of FIELD-NOTES §10.1: `watch: orchestrator
dead + no live sessions for 3 ticks — tearing down (Mac may sleep)`.

**Concrete failure, default = headless.** The same user gets A2 on their first night and does not know
it: their sessions are told they were answered and continue, and no window exists in which the
evidence would have been visible on screen.

**The hole.** He answered "it is configurable" to a question about what the system *does*. The
configurable answer is complete only if it names the value at zero configuration, and the first-run
experience is exactly where the user has no way to know which answer is right for them — the
information needed (does my platform have an answer channel? does my work ask questions?) is not
available to them before the run that would teach it.

**Severity: major.** Every new install lands here, including his own second machine and any teammate.

---

## 8. A8 — MAJOR — the input line has three writers and no owner, and the loser is destroyed silently

R1-11's question presumed a terminal «куди ти можеш зайти і **написати руками**» [319]; he did not
reject it. His answer adds a second writer: the orchestrator answering questions. R1-08 adds a third:

> «повинен бути **механізм, який гарантовано робить цю дію**» (compaction at a threshold) — **[204]**,
> and FIELD-NOTES §1.1: `/compact` is typed into a session's terminal **by another process**.

**FIELD-NOTES on what happens when two of them collide** (§1.3, measured, five occurrences):
- a bare Enter does **not** submit text already sitting on the line (iTerm2/AppleScript path);
- `send <tty> "<text>"` types its own text and submits — so it **destroys** whatever was pending;
- whatever sits on an idle input line when a background task re-invokes the session is **discarded**.

§11.2: a **thirteenth consecutive** stranded `continue` on the orchestrator's input line, "sitting
beside a live Playwright run it could have corrupted".

**Concrete failure.** 02:47. A worker raises the AskUserQuestion dialog (**VERIFIED** shape, §3.1.6a:
options 1–2, plus `3. Type something`, plus `4. Chat about this`). The orchestrator decides to answer
"2". In the same window the context-watch's compaction threshold trips and it sends `/compact` into
the same pane. Two outcomes, both real: the dialog is open, so `/compact` is consumed as free-form
text via option 3 and becomes **the answer to the question** — the worker is told the user's answer is
"/compact"; or the compaction send lands first, wipes the pending keystroke, and the dialog is
answered by nobody while both writers' logs record success. The owner walking up and typing at 08:30
is a third path into the same failure.

**The hole.** No decision anywhere assigns ownership of a session's input line, or sequences
answering against compaction. Both capabilities were specified in different items, each assuming sole
use.

**Severity: major.** Mechanically verified in the previous run; the new capability adds a writer to a
channel that already lost five messages.

---

## 9. A9 — MAJOR — an answer sent as keystrokes has no acknowledgement, so "answered" is unverifiable

**VERIFIED** (§3.1.6a) that `tmux send-keys -t <pane> -l '2'` answers the dialog cleanly and the
session records `User answered Claude's questions: … → Production`. What is **not** available is any
confirmation *to the sender*. The orchestrator learns the answer landed only by scraping the pane
again — and §4.4 measures how unreliable that reading is: the spinner verb is randomised
(`Pollinating…`, `Baked for 2s`, `Churned for 29s`, `Cooked for 3s`), `capture-pane -p` returned
**empty for several seconds on a live pane**, `#{pane_current_command}` was `2.1.278` rather than
`claude`, and everything reflows at a different window width.

**Concrete failure.** 03:12. The orchestrator reads a dialog, sends `2`, and the capture that follows
comes back empty (verified as a real state). It retries; by then the dialog is gone and the `2` lands
on the idle input line as the literal character `2`. A later stale-heartbeat nudge presses Enter —
FIELD-NOTES §1.4 measured exactly this nudge twice, on a validator at `03:26:34Z` and the orchestrator
at `05:21:06Z` — and the worker receives a user message consisting of the single character `2`. It
interprets it as best it can and continues.

**A live bug in the old code that makes it worse** (research §3.1.5, VERIFIED in source):
`harness-term.sh:197-198` does `tmux send-keys -t "$p" "$2"` with **no `-l`**, so any argument that
collides with a tmux key name (`Up`, `Enter`, `Space`, `Escape`, `Tab`, `BSpace`) is delivered as that
*key*, not as text. A free-form answer through `3. Type something` is one word away from this.

**The hole.** The decision says the orchestrator *may* answer. It does not say an answer must be
proven delivered, nor what the orchestrator does when it cannot tell. FIELD-NOTES' running total for
unconfirmed sends in a single run is five lost instructions and thirteen consecutive stranded ones.

**Severity: major.**

---

## 10. A10 — MAJOR — the answer is recorded as the human's, so his own learning loop trains on the orchestrator's guesses

**VERIFIED** (§3.1.6a): after the orchestrator answers, the child session's transcript reads

```
⏺ User answered Claude's questions:
  ⎿  · Which environment should we deploy to? → Production
```

There is no marker distinguishing that from the owner typing it. Now put it next to the two places he
said the system must learn from past decisions:

> «якщо це не підходить, то **треба вчити**, відповідні дії» — **[062]**

> «Це може бути якийсь tone of voice, або дивитися в альтернативи інших питань … **Коли відзадавав
> подібні питання, що відповідав, і на основі цього відповідати**» — **[087]**

**Concrete failure, on the second run.** Night one: the orchestrator answers eleven questions from
project knowledge; four are wrong but harmless. The transcripts record all eleven as the user's
answers. Night two, the configured authority basis is "previous answers to similar questions" [087] —
so the orchestrator reads its own four wrong answers as the owner's precedent and generalises from
them. The «tone of voice» he described as «майже замість неї може відповідати» [092] is now partly a
recording of the machine imitating itself. Meanwhile [062]'s corrective loop cannot run at all: at
09:00 he reads "User answered: Production" and has no way to know it was not him, so there is nothing
to correct.

**The hole.** He required the learning loop and the precedent-based authority; he did not require that
answers be recorded, attributed, or distinguishable from his own. Without that, both requirements are
unimplementable and the second one is actively harmful. (FIELD-NOTES §2.1 is the precedent for
"the channel where corrections were written was silently destroyed": `state/attention` was rebuilt
from scratch every watch cycle and a whole night of the context watch's corrections went to
`/dev/null` — discovered by accident.)

**Severity: major.** Compounding, and invisible in exactly the artefact he would review.

---

## 11. A11 — MAJOR — the orchestrator can answer a session it did not start, which he forbade in another item

> «в тій самій папці **я паралельно працюю над чимось, це не запускав оркестратор, це роблю я**, він
> цього не має зупиняти» — **[370]** · «оркестратор має бути якось селфевернес, що він, до чого він
> може змінювати» — **[366]**

Against: «оркестратор може робити інтерактивність зесіями» [324], with no scoping clause.

**The enabling fact is VERIFIED** (§3.1): `claude agents --json` on this machine returned the owner's
own interactive sessions alongside background ones — `{"pid":35475,"kind":"interactive",…,
"status":"busy"}` next to `{"id":"8402872a","kind":"background","state":"blocked"}`. It is the best
session inventory available and it does not distinguish "mine" from "his". The same is true of any
PTY-scan approach: a pane with a Claude dialog on it looks the same whoever opened it.

**Concrete failure.** 21:40, the run is live and he is working in his own Claude Code window in the
same repository. His session raises AskUserQuestion — *"Two approaches to this refactor, which?"* —
and he steps away to make tea. The orchestrator's answering loop enumerates sessions, sees an
unanswered dialog, and answers it. He returns to a decision he did not make, recorded as his.
FIELD-NOTES §1.6 shows the inverse confusion already happened once: a `question`-role session's
terminal title read `harness-question-q-screen-orchestrator` and **the product owner read it as a
second orchestrator.**

**The hole.** "The orchestrator interacts with sessions" was never scoped to *its own* sessions, and
the platform's native inventory actively invites the wider reading. He forbade exactly this in R1-16
but in a different item, about tests and files, not dialogs.

**Severity: major.** Requires him to be working concurrently — which [370] says explicitly that he
does.

---

## 12. A12 — MINOR — for two of the platforms the capability is not merely unconfigured, it does not exist, and the user cannot know that

«Під кожну платформу своє налаштування» [324] presumes each platform *has* the settings. Two do not:

- **Gemini CLI.** ACP standardises **permission** (`session/request_permission`, four option kinds)
  and nothing else interactive; there is **no question primitive** (CLAIMED, confirmed absent across
  two ACP doc pages, research §4.2). A clarifying question arrives as ordinary assistant prose in a
  `session/update` chunk. Headless Gemini has no `--input-format` at all (**VERIFIED** in
  `packages/cli/src/config/config.ts`) — one prompt per process.
- **cursor-agent.** Only `-f`, "Force allow commands unless explicitly denied" (**VERIFIED**,
  `--help`). No per-request channel of any kind.

**Concrete failure.** The user, having been told the orchestrator answers sessions' questions, sets
`gemini: headless` for a cheap platform on a second lane. The Gemini worker needs a clarification,
writes it as prose, and waits. The orchestrator is watching for a protocol event that this platform
never emits. The lane hangs. FIELD-NOTES §11.1 gives the shape of the aftermath: a subagent retried
against an unreachable daemon for **33 m 31 s** spending 184k tokens, "indistinguishable from working
by heartbeat", and was found only by reading the log by hand.

**Where "the user configures it" moves the problem.** The user has no way to know that ACP lacks a
question method. That fact took a protocol-doc read to establish. The configuration surface will
happily accept a combination that is structurally impossible, and nothing in the decision requires the
orchestrator to refuse it at launch.

**Severity: minor**, and I argued myself down to it: it is detectable at configure time, it affects
platforms he may never use, and it fails loudly (a hang) rather than silently (A2). It stays on the
list because it is the clearest case in the cluster of configurability being offered where capability
does not exist.

---

## 13. Ranked summary

| # | Severity | Attack | Primary collision |
|---|---|---|---|
| A1 | blocker | No refusal class for questions; controlled run stops being controlled | [324] vs [062] |
| A2 | blocker | Headless AskUserQuestion is answered with `answers:{}`; no check will catch it | [324] vs [344]; FIELD-NOTES §4.1, §11.4 |
| A3 | blocker | A headless orchestrator asks into the void; no second orchestrator allowed | [324] vs [300]/[301], [266] |
| A4 | major | "Headless" is four runtimes; `--bg` is invisible **and** unanswerable | [324] internal; FIELD-NOTES §1.6, §11.1 |
| A5 | major | Per-platform axis cannot express his own three-window setup | [324] vs [204]; FIELD-NOTES §8 |
| A6 | major | «Тільки інколи» has no predicate; both readings collapse the mode | [324] internal |
| A7 | major | No default at zero configuration; the two candidates fail oppositely | [324] vs [171]/[300] |
| A8 | major | Three writers on one input line, no owner; the loser is destroyed | [324] vs [204]/[319]; FIELD-NOTES §1.3, §11.2 |
| A9 | major | Keystroke answers have no acknowledgement; delivery unverifiable | FIELD-NOTES §1.3, §1.4, §11.2; research §4.4 |
| A10 | major | Answers recorded as the human's; learning loop trains on the machine | [324] vs [062]/[087]/[092]; FIELD-NOTES §2.1 |
| A11 | major | Can answer sessions it did not start | [324] vs [370]/[366]; FIELD-NOTES §1.6 |
| A12 | minor | Gemini/cursor-agent cannot be answered; config accepts the impossible | [324] vs research §4.2 |

**Three questions for him, extracted from the above, in his own frame.** (1) Is a child session's
question ever an escalation rather than a task — and does the answer differ between controlled and
autonomous? (A1, A3.) (2) When you said «дуже обережним», did you mean what A2 measures — and if the
orchestrator cannot guarantee a question channel, may it still launch headless? (3) «Інколи» — count,
clock, ticket class, or the orchestrator's own judgement? (A6.)

---

## 14. Attacks I raised and killed

Recorded so the survivors can be weighed against the failures.

1. **"Headless saves no money and wastes quota invisibly."** Killed: FIELD-NOTES §5.3 shows the
   5-hour token window was never the binding constraint (26% of the weekly allowance across 34 hours);
   the dependency graph bounded throughput. Visibility has no measurable quota cost, so there is no
   attack here.
2. **"Interactive sessions cost memory and will OOM his machine."** Killed as a C7 attack: FIELD-NOTES
   §5.1's OOM kill was caused by two concurrent `docker compose up --build`, not by terminals; §2.2
   priced 58 stray child shells at ~75 MB and 0% CPU. Terminal count is not the resource problem. It
   belongs to C4, not here.
3. **"He should not let the orchestrator answer questions at all."** Killed on the rules: that is
   substituting my preference for his decision. He said «повністю і повністю окей» twice. A1 attacks
   the *missing refusal class*, not the capability.
4. **"tmux is the wrong choice / AppleScript must go."** Killed as a C7 *attack*: it is a proposal,
   and it is already P4 in the research. A8 and A9 attack what the decision leaves undefined about
   delivery regardless of backend.
5. **"The trust dialog blocks every new worktree."** VERIFIED real (research §4.6; the previous tool
   needed a whole `harness-trust.sh` for it, FIELD-NOTES §0) — but it is a *launch* concern, owned by
   C6/spawn, and the previous tool already solved it. Folded into A4 as supporting evidence rather
   than kept as its own attack.
6. **"Answering questions breaks the red-line file."** Killed as too vague to bite: [357] is prose
   read by every agent, and an orchestrator answering a question is as bound by it as any other agent.
   There is no *concrete* scenario where answering specifically defeats the file that is not already
   A1 (authority) or A2 (fabrication).
