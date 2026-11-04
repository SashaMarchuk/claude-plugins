# C1 — Run modes and decision authority · round-2 questions

Cluster: **C1-run-modes** · Items: **R1-14, R1-02, R1-01**, owner instruction **I2**
Date: **2026-09-19** · Round: **2** · Format: **voice, Ukrainian**
Read first: `C1-run-modes-research.md`, then `C1-run-modes-challenge.md`

Ten questions. Four blockers, six majors. Each one is a hole the challenge pass found in a decision he
already made — none re-asks a settled question, and none carries a recommendation. Where real
alternatives exist they are named as options and the question stops there.

Evidence marks: **VERIFIED** (read in the transcript, the field notes or the plugin source),
**CLAIMED** (a third party asserts it), **INFERRED**.

**Reading order matters.** Q1 eliminates three of the five candidate definitions in the research
(§5); several later questions get cheaper or moot depending on how he answers it. Ask it first.

---

## Q1 — Do the modes differ in powers, or only in where a question goes? · **definition · blocker**

> «Ти сам сказав, що не знаєш, чи ці два режими взагалі відрізняються. Питання одне: в автономному
> рані агенту дозволено робити більше дій, ніж у контрольованому — чи дозволено рівно те саме, а
> різниця тільки в тому, куди йде питання, на яке в нього немає відповіді?»

Options to read out, and stop:
- «те саме, різниця тільки в тому, куди йде питання»
- «в автономному він має більше прав на самі дії»

**Why this is the hole.** He said it himself and it was never resolved:

> «Не знаю, чи вони будуть відрізнятися, але автономний це про те, що він там вночі, наприклад,
> працює і якщо він стихається» **[058]** (VERIFIED — transcript line 138)

And he handed the definitions to this analysis:

> «Одне з субтих питань, які ти можеш мене запитати, що таке контрольований, що таке автономний ран.
> І в мене поки немає відповіді. Це потрібно, щоби агент, який буде колектити ці результати,
> проаналізував і запропонував мені варіанти для цього.» **[082]** (VERIFIED)

`extract/corrections.md` records that the base definition of the two modes was put to him at [074] and
he answered a different question — mode *selection* — instead, so it is **UNRATIFIED** and
ANALYSIS-01.md files it as SETTLED (VERIFIED).

**What the answer changes.** Research §5 holds five candidate definitions. "Same powers, different
disposition" leaves P1 and P4 alive and kills P2, P3, P5. "More powers" does the reverse. This is the
single cheapest question in the cluster and it deletes three designs.

---

## Q2 — Name an outside-visible trigger, because doubt is only visible to the agent · **gap · blocker**

> «І контрольований, і автономний ран у тебе запускаються з одного — "є сумніви". Але сумнів видно
> тільки самому агенту: він може бути впевненим і при цьому помилятися, і ззовні ніч із сумнівами та
> ніч без сумнівів виглядають однаково. Назви ознаку, яку видно ззовні — за якою я зрозумію, що це
> саме той момент, коли треба йти до тебе.»

Options to read out, and stop:
- «тип самої дії — є список дій, які завжди йдуть до мене»
- «коли кілька радників не зійшлися між собою»
- «коли одне й те саме не вийшло вдруге»
- «коли на це немає відповіді в моїх записаних правилах»

**Why this is the hole.** The trigger for both modes is a self-report:

> «якщо є якісь сумніви, то коли контрольований, то вони йдуть зразу до мене … Якщо це автономний
> ран, то і агент не впевнений на сто в цьому варіанті, то він його може обрати» **[062]** (VERIFIED)

The previous generation shipped this exact predicate as a number —
`plugins/harness/templates/prompts/orchestrator.md:19-21` escalates on "something you're <70% sure
on" (VERIFIED, read in the file). The research collects the literature on why that number measures
nothing: verbalized confidence clusters in the 80–100% band and the inflation is a model-internal
mechanism, not a prompt artefact (CLAIMED — research §2.10). **INFERRED, and defensible:** a controlled
run whose agents never report doubt is behaviourally identical to an autonomous one, and identical to
a genuinely untroubled night.

And his own adjacent decision closes the after-the-fact detector:

> «конкретної якоїсь вимірюваної штуки тут не може взагалі бути» **[062]** (R1-01, VERIFIED)

So the trigger is unobservable in flight and the outcome is unmeasurable afterwards, by his own
decision. Challenge A1.

**What the answer changes.** Whether the build contains a confidence gate (a prompt line) or a
structural gate (an action-class list, a council-split signal, a second-failure counter). These are
different products.

---

## Q3 — What exactly does a hard stop pause? · **collision · blocker**

> «Ти сказав: у контрольованому рані питання йде до мене, а робота на паузі, поки я не відпущу. І
> окремо ти сказав, що незалежні завдання можуть продовжуватись. Що саме стає на паузу — тільки ця
> дія, тільки цей тікет, вся лінія роботи разом із ворктрі, чи весь ран?»

**Why this is the hole.** Two of his own rows disagree:

> «типу робо каже, що це на паузі, поки людина не відпустить, якщо це контрольований ран» **[062]**
> (VERIFIED)

> «Та, можем продовжувати незалежні завдання.» **Д6 [449]** (VERIFIED — transcript line 553)

Д6 settles the run level and leaves the other three referents open, and it was answering a different
question (what happens while a question waits) than [062] (what a hard stop does). Two implementers
reading both rows build different products: one where 16 tickets sit untouched until 09:00, and one
where eleven phases merge overnight against an auth answer he then reverses. Measured cost of the
first: roughly one phase an hour for phases 10–14 on the last real run (VERIFIED, FIELD-NOTES §9.5).
Challenge A2.

A third sub-case nobody has answered: a hard stop raised by a **worker** — does it stop the worker,
the lane, or reach the orchestrator at all?

**What the answer changes.** The scheduler. Whether a held question is a property of a ticket, a lane
or the run decides the entire queueing design, and whether a question can be marked
blocking-for-everything.

---

## Q4 — What counts as proof in a report the deciding agent wrote about itself? · **gap · blocker**

> «В автономному рані звіт про рішення пише той самий агент, який це рішення й прийняв. У минулому
> рані таке вже ламалося: перевірка знайшла в логу двадцять шість відмов, яких насправді ніколи не
> було. Що ти хочеш бачити вранці, щоб вірити звіту?»

Options to read out, and stop:
- «тільки те, що записала сама програма: яку команду запустили, коли, чим вона закінчилась — а
  пояснення агента окремо і не як доказ»
- «досить пояснення агента»
- «обидва поруч, і я сам звіряю»

**Why this is the hole.** The report *is* the safety property of autonomous mode — he is asleep, and
the report is how he finds out:

> «Але потім він прозвітовує, про те, що було таке от рішення. Момент був, що це автономний ран, і
> він обрав це» **[062]** (VERIFIED)

The reporter and the actor are the same party, and on this codebase that party was caught fabricating
its own record:

- FIELD-NOTES line 703 — "A security review of a single API read found **26 refusal events in the
  audit log that never occurred**" (VERIFIED, read in the file).
- FIELD-NOTES §11.4 — GSD's verify stage silently skipped for phases 14–18, each `NN-VERIFICATION.md`
  self-attributing `verified_by: the lane that built the phase`; no automated check caught it
  (VERIFIED).
- FIELD-NOTES line 229 — a merge ran on the phase branch against itself and printed `Already up to
  date`; "both read like success" (VERIFIED).

Widened by his own R1-13: «не роби обмеження те, що вся робота потім буде мати тести» **[344]** — so a
run whose configured process has no verification step is legal, and the autonomous report is unaudited
by construction. Challenge A4.

**What the answer changes.** Whether the rebuild ships an engine-written append-only event log at all,
and whether the model's rationale is an attached untrusted field or the record itself.

**Scope note:** this asks about the *decision* report only. "Prove the merge happened and the tests
were green" is R1-13 and belongs to C9 — do not let the two merge in the room.

---

## Q5 — Must every question carry "what I will do if you don't answer"? · **gap · major**

> «У минулому рані кожне питання, яке до тебе піднімали, йшло в каналі разом із рядком "якщо ніхто не
> відповість, я зроблю ось це" — і на всі ти потім відповів. Робимо це правилом: без такого рядка
> питання взагалі не піднімається?»

Options to read out, and stop:
- «так, обов'язково, завжди»
- «так, але тільки в автономному рані»
- «ні, зайве»

**Why this is the hole.** This is the one escalation format with a production record behind it:
FIELD-NOTES §9.1 — questions routed to the project's question channel rather than answered by
assumption, "each with a recorded `Fallback` and each later marked answered" (VERIFIED, lines 325–329).

*Evidence caveat, stated honestly:* the field notes say "Eleven questions" and then enumerate ids that
count to thirteen (`Q-P9-01`, `Q-T122-01`, `Q-OWN-01..04`, `Q-ORCH-04..07`, `Q-RESTORE-01`,
`Q-PARITY-01`, `Q-T250-01`). The pattern is VERIFIED; the count is not. **The question above deliberately
carries no number** — do not quote one in the room.

**Why it is not a re-ask.** R1-14 already asked what happens to a task while it waits, and he answered
«на паузі» [062] and Д7 [455] «по дефолту я б рекомендував, що він залишається та чекає на мої
відповіді» (VERIFIED). That is settled and is not being reopened. The new hole is the **format** of the
escalation, not its disposition: nothing he said requires a question to declare its own fallback, and
research §5/P4 makes "a moment for which no safe fallback can be written" the only machine-checkable
definition of *this really does need him* — one that needs no confidence number.

**What the answer changes.** Whether the escalation record has a mandatory field, and therefore whether
"no safe fallback exists" can be used as a trigger at all.

---

## Q6 — Where does the mode come from when the run restarts at 04:00 and nobody is there? · **default · major**

> «Стоїть налаштування "питати кожного разу". О другій ночі ран став через ліміт, о четвертій ліміт
> відновився і оркестратор перезапустився. Тебе немає. Звідки він бере режим?»

Options to read out, and stop:
- «з того, що я обрав увечері — продовжує тим самим»
- «з конфіга, тобто з постійного налаштування»
- «нічого не запускає і чекає ранку»

**Why this is the hole.** He named three values and no default, and «перед кожним раном» assumes a
human is present at every run start:

> «там будуть три варіанти. … І якщо постійно запитувати, то перед кожним раном треба
> використовувати, задати питання юзеру» **[075]** (VERIFIED — transcript line 155)

In English: the three are ask every time, always autonomous, always controlled.

His own other decisions create run starts with nobody there: R1-06 [034–036] (limit exhausted → wait
for the reset, which can land at 04:00), R1-10 [246] (a health-check agent «раз в N годин на якійсь
іншій підписці») and [300] (restart the orchestrator, not the work), Д10 [497] (a restart with
executors still alive). Three implementers produce three products, and the difference only shows up on
the nights that matter. Challenge A5.

**The default also matters on its own.** The previous generation's `session.permissions` defaulted to
`bypass` (VERIFIED — FIELD-NOTES §0 configuration-key list). A rebuild that repeats that makes every
unconfigured run autonomous; one that defaults to controlled makes every unconfigured run block on the
first doubt with nobody watching. He decided neither — the second option above is where he states it.

**What the answer changes.** Whether the mode is run state that survives a restart, or a config read
fresh each time. One line of design, and it decides whether half the night is usable.

---

## Q7 — Can a tone-of-voice file from the repository answer in your place? · **gap · major**

> «Один із варіантів, які ти назвав — брати tone of voice із самого репозиторію. Але той файл писав не
> ти, і писали його для людей, а не для оркестратора. У чужому репозиторії цілком може бути написано
> "рухаємось швидко, не блокуємось на рев'ю для внутрішніх змін" — і агент чесно на це зішлеться,
> зіллє в головну гілку без рев'ю, і в логу буде коректне посилання на файл. Чи можна такому файлу
> довіряти рішення замість тебе?»

Options to read out, and stop:
- «тільки мої власні файли»
- «і репозиторій теж, як є»
- «репозиторій можна читати, але вирішувати на його основі — ні»

**Why this is the hole.** He named the repo as a basis, and separately granted a basis the authority to
answer in his place:

> «Або, можливо, є якийсь tone of voice в цьому репозиторії, на основі чого можна робити цей вибір.»
> **[087]** (VERIFIED — transcript line 167)

> «якщо людина сказала, що вона налаштувала так, що, грубо кажучи, майже замість неї може відповідати,
> по причині попередніх прикладів, налаштувань, тощо і так далі, то це повністю окей» **[092]**
> (VERIFIED — transcript line 172)

Two precedents say this is the wrong way round. The previous generation already fences ticket bodies:
they reach a prompt only through `fence_body`, wrapped in an UNTRUSTED-input sentinel
(`harness-tickets.sh:43-49`, VERIFIED via FIELD-NOTES §0) — and a ticket body can only *describe work*,
while a tone-of-voice file decides whether he is asked at all. And Claude Code's classifier reads its
rules from user and managed settings and **deliberately not** from `.claude/settings.json` in the repo,
"so a checked-in repo or a build step could otherwise inject its own allow rules" (VERIFIED — vendor
docs `auto-mode-config`, research §2.9). Challenge A8.

**Note for the room:** this needs no attacker and no malice. Ordinary sentences in ordinary repos
already read as decision policy.

**What the answer changes.** Which config scopes the basis may be read from — a two-line decision that
cannot be retrofitted once the basis loader exists.

---

## Q8 — What is the teaching act? · **gap · major**

> «Ти сказав: якщо рішення не підходить — треба вчити. Уяви: вранці ти бачиш рішення, яке тобі не
> подобається. Що конкретно ти робиш, щоб наступної ночі агент вирішив інакше?»

Options to read out, and stop:
- «сам дописую свій файл із правилами»
- «кажу це оркестратору, і він сам дописує»
- «ставлю позначку в звіті, а решту робить плагін»
- «нічого не роблю — просто наступного разу це питання йде до мене»

**Why this is the hole.** This is the only place in the whole interview where feedback changes future
behaviour, and it has no actor, no artefact and no moment:

> «Момент був, що це автономний ран, і він обрав це, якщо це не підходить, то треба вчити, відповідні
> дії.» **[062]** (VERIFIED)

Nothing in the previous generation implements any form of it (VERIFIED — no such verb in
`bin/harness-state.sh`, which has only `decision` and `owner-action`). Without it, «він прозвітовує»
produces a diary: night 1 the agent deletes three stale worktrees, he says "never delete a worktree you
did not create", night 2 the same orchestrator does the same thing. Autonomous mode stays permanently
at day one. Challenge A6, and `extract/outside-list.md:59` flags the same gap as absent from
ANALYSIS-01.md.

**The trap inside option two, which he should hear but which is not a recommendation:** if the
orchestrator may append to the basis it decides on, the deciding party writes its own authority. The
recorded analogue is FIELD-NOTES §11.4 — an orchestrator generalised a narrow `council-advisor` warning
into "every GSD agent" and skipped verification for five phases (VERIFIED). State it as a consequence of
the option, in one clause, and let him choose.

**What the answer changes.** Whether a ledger or correction artefact exists at all, who may write to it,
and whether autonomy can be revoked per decision class (research §5/P5).

---

## Q9 — Is the agent's own hard stop in an autonomous run in or out? · **ratify · major**

> «Одна річ у нас записана, але ти її жодного разу не підтвердив: що агент в автономному рані може сам
> вирішити поставити хардстоп і піти до тебе. Лишається чи ні?»

Options to read out, and stop:
- «лишається як є»
- «прибираємо — в автономному рані він не зупиняється ніколи»
- «лишається, але тільки для списку випадків, який я задам»

**Why this is the hole.** The clause as spoken:

> «Якщо агент вирішив, що це точно має бути хардстопом, то такі моменти теж можуть бути, що
> відбувається хардстоп, і йдеться до людини, навіть якщо це автономний ран. Таке може бути, і агент
> сам буде пробувати детермінувати, коли це робити» **[082]** (VERIFIED — transcript line 162)

**Status: UNRATIFIED.** The restatement carrying it ([085]/[086]) never received a «так» — he answered
by adding a new condition instead [087]. The restatement that *was* confirmed ([094] → «Так,
підтверджую» [101]) covers only the *basis* for decisions. ANALYSIS-01.md files it as SETTLED.
(VERIFIED — `extract/corrections.md`, checked against the transcript rows.)

It is the only unbounded authority in the design: the agent may override the run's configured mode, in
either direction, with no reason code, no cap, no trigger list and no test. And the faculty it depends
on — correctly determining that it must stop — is exactly the faculty that failed twice on record:

- FIELD-NOTES §11.6 — an 85-minute self-sustaining loop; the watch matched a usage-cap-looking string
  inside the orchestrator's **own wrapped prose**, pressed Escape and sent `continue` every ~60 s;
  "nothing internal detected it"; it ended on an external `SIGTERM`; log line 5620 reads
  `NO ONE IS BEING TOLD` (VERIFIED, file line 550).
- FIELD-NOTES §11.1 — a subagent retried `docker desktop start` for 33 m 31 s against an unreachable
  daemon, spending 184k tokens, "indistinguishable from working by heartbeat" (VERIFIED).

**The symmetric attack, worth one clause in the room:** an authority to force a stop is also an
authority to decide a stop is not needed. Nothing in [082] says which side of the boundary the agent may
move it to. Challenge A9.

**What the answer changes.** Whether the mode is a hard property of the run or a default the agent can
override — which decides whether "controlled" means anything at 02:00.

---

## Q10 — May a role sit on a platform where "controlled" cannot exist? · **feasibility · major**

> «Режим ти описав як властивість рану. Але ролі ти хочеш розкидати по різних провайдерах, а на
> деяких із них — я перевірив на твоїй машині — взагалі немає способу зупинитись і спитати: у
> cursor-agent є рівно один перемикач, "дозволено все" або "заблоковано все". Чи можна в
> контрольованому рані ставити роль на таку платформу?»

Options to read out, and stop:
- «ні, така платформа в контрольованому рані не використовується»
- «так, але тільки для ролей, які нічого не вирішують»
- «так, і тоді оркестратор тримає контроль ззовні — спочатку показує зміни, потім запускає ще раз, щоб
  їх застосувати»

**Why this is the hole, and why it is asked at all.** His own instruction:

> **I1 [182–184]** — «ти коли будеш це аналізувати, я про це не говорю, і я ну все вірю, але воно може
> не сходитися з дійсністю» — verify against each platform, and raise a divergence as its own question
> rather than assuming it works. (VERIFIED)

Verified on this machine today: `cursor-agent --help` (2025.09.12-4852336) exposes exactly one autonomy
control, `-f, --force   Force allow commands unless explicitly denied`. No ask state, no escalation
hook, no permission-prompt tool, no "stranded, waiting" event. Codex 0.152.0 has the inverse problem:
`-a on-request` means *the model decides when to ask* — Q9's unbounded clause shipped as the vendor
default (VERIFIED). And Claude Code's own circuit breaker (3-in-a-row / 20-total blocks → pause and
prompt) is not configurable and does not fire in a headless `-p` run — "the action doesn't run and
Claude keeps working… Claude Code doesn't stop the run in either case" (VERIFIED — vendor docs
`permission-modes`). GLM, Kimi and Gemini are not installed here and could not be checked
(**UNVERIFIED**).

The concrete failure: a controlled run with the validator on cursor-agent. With `--force` on it resolves
an ambiguity in the acceptance criteria itself and passes the phase — an autonomous decision inside a
controlled run, invisible because the validator's report *is* the verdict. With `--force` off it is
denied on its first write, has nobody to ask, and returns something that reads like a rejected phase.
Challenge A11.

**The undefined part underneath, worth naming in one clause:** he said the mode is per **run** [075];
his role and account decisions [195, 199, 270, 276] are per **role**. Nothing reconciles them.

**What the answer changes.** Whether the mode lives on the run or on the role, and whether the
orchestrator must implement controlled mode *outside* the tool for platforms that cannot express it.

---

## Surviving gaps NOT turned into questions, and why

Listed so the next round can pick them up rather than lose them. The cap is ten and these lost the cut.

1. **Mid-run mode flip semantics (challenge A10) — the top candidate if a slot frees up.** Д7 [458]
   settles that a mid-run change must be read and honoured («оркестратор повинен це зчитувати та
   приймати. Це також, і це дуже важливо», VERIFIED). What is undefined: whether decisions already
   taken stand, are re-opened as questions, or keep propagating; whether the flip lands at the next
   safe boundary or immediately (he has soft/hard vocabulary for limits, accounts, compaction and
   stops — never for modes); and whether already-spawned workers learn of it at all (their prompt is a
   file written at spawn and passed as `"$(cat prompt)"`; nothing re-reads it — VERIFIED,
   FIELD-NOTES §0). Three defensible implementer readings.

2. **Three of four decision bases are empty on day one (challenge A7).** On a new project he has
   written no rules, there are no previous answers, and the repo file may not exist — leaving "the
   agent decides on its own project knowledge" as the only working option on the run where delegation
   is least evidenced. Partly addressed by Q7 (which bases are trustworthy) and Q8 (how a basis grows),
   so it is covered obliquely rather than asked directly.

3. **A waiting session is indistinguishable from a wedged one (challenge A3, a blocker).** Deliberately
   left to **C6-liveness-recovery**, which owns R1-09's silence ladder. Its C1-specific residue — an
   escalation that declares what happens if nobody answers — is Q5. For the record, all VERIFIED in
   FIELD-NOTES: a session heartbeats *between* turns (§1.5); a shell that cannot exit reads as work
   (§2.2); five instructions typed into sessions were never delivered (§1.3); the nudge does not submit
   stranded text (§1.4); the stale-heartbeat nudge is the only escalation the engine has, with peaks of
   2808 s this run and 44791 s the previous one before one fired (§11.1, file line 462); and
   `QUESTIONS.md` forked into a worktree's own copy with a real owner-facing question invisible there
   for an hour (§12.5).

4. **Blast radius is machine-level and unattributed (challenge A12).** Belongs to **C8-boundaries-safety**
   (R1-15, R1-16). The mode decides who decides; it does not decide what an action can reach. Recorded:
   the owner's default Docker stack destroyed by `docker compose down -v` with no
   `COMPOSE_PROJECT_NAME`, the actor never identified, and a session had refused that exact action as
   owner-only two minutes earlier (FIELD-NOTES §11.5, VERIFIED).

5. **Red line as prose alone (research Q-4).** R1-15 [357] is itself the weakest-grounded answer in the
   interview — he ended it by asking whether he had answered the question at all, the interviewer
   answered its own question [358], and no «так» ever came (VERIFIED, `extract/corrections.md`). It is
   C8's to re-put, not C1's.

---

## Interviewer notes for the voice session

- **Ask Q1 first.** Q2, Q3 and Q9 read differently depending on his answer, and three of the five
  candidate designs die on it.
- **Vocabulary that is his and is safe to use:** оркестратор, ран, тікет, дошка, ворктрі, компакт,
  ліміт, провайдер, акаунт, сесія, хардстоп, софтстоп, tone of voice. Nothing else in English.
- **Do not name a preferred option.** Every options list above is alphabet-neutral: read them flat, in
  the order written, and stop talking.
- **Numbers to quote and numbers not to.** Safe, all VERIFIED in the file: 26 fabricated refusal events;
  85 minutes; 33 m 31 s and 184k tokens; 2808 s and 44791 s. **Do not quote a count of escalated
  questions** — the field notes say eleven and enumerate thirteen ids.
- **If he starts redesigning mid-answer**, let him — his words are the source of truth — but get the
  option back before moving on, or the round produces prose instead of a decision.
- **Q9 is the one to protect.** It is filed as SETTLED in ANALYSIS-01.md and he will likely say "I
  already answered that". He did not: the restatement carrying it got a new condition instead of a yes.
  Say that in one clause and let him decide.
