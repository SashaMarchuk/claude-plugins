# C7 — Session runtime · round-2 questions

Cluster: **C7-session-runtime** · Item: **R1-11** (asked at [319]/[320], answered at [324], confirmed at [328])
Date: **2026-09-19** · Round: **2** · Format: **voice, Ukrainian**
Read first: `C7-session-runtime-research.md`, then `C7-session-runtime-challenge.md`

Ten questions. Three blockers, seven majors. Every one is a hole the adversarial pass found in a
decision he already made — none re-asks what he settled, none carries a recommendation. Where real
alternatives exist they are read out as options and the question stops there.

Evidence marks: **VERIFIED** (read in the transcript, the field notes, the plugin source, or run on
this machine today), **CLAIMED** (a vendor doc asserts it), **INFERRED**.

**Vocabulary check.** Every term used in the spoken questions below is one he used himself in round 1:
*оркестратор, ран, сесія, тікет, ворктрі, компакт, ліміт, платформа, провайдер, хардстоп,
конфігурація, headless, ask user question, гібрид, контекст вочер, екзек'ютор, код-код, Кодекс,
джемінай, tone of voice*. `cursor-agent` is **not** his word and appears only in the evidence sections,
never in a question to be read aloud.

**Reading order matters.** Q1 decides whether a question from a session is the orchestrator's job or an
escalation. Q2 decides whether headless may run at all without a proven answer channel. Q3–Q10 get
cheaper or narrower depending on those two. Ask them in order.

---

## Q1 — Is a question from a session ever something the orchestrator must refuse? · **collision · blocker**

> «Ти сказав, що оркестратор може відповідати на ask user question, і що це повністю окей. Але
> окремо ти сказав інше: у контрольованому рані будь-які сумніви йдуть зразу до тебе і робота стоїть
> на паузі, поки ти не відпустиш. А питання від сесії — це і є сумнів, просто в тій єдиній формі, в
> якій сесія вміє його висловити. Що з цього правда: оркестратор відповідає завжди, чи є клас
> питань, на які він відповідати не має права і мусить ставити хардстоп і йти до тебе?»

Options to read out, and stop:
- «відповідає завжди, на все»
- «в автономному рані відповідає на все, у контрольованому — не відповідає ні на що, все йде до мене»
- «є список тем, які завжди йдуть до мене, незалежно від режиму рану»

**Why this is the hole.** Two of his own rows collide, and both are confirmed:

> «оркестратор може робити інтерактивність зесіями … якщо він раптом використовує ask user question,
> то оркестратор може відповідати на ці питання, і **це повністю і повністю окей**» — **[324]**
> (VERIFIED — transcript line 420; confirmed at [328], line 424)

> «якщо є якісь сумніви, то коли контрольований, то вони **йдуть зразу до мене** і ставлять умовного
> хардстоп … типу робо каже, що це на паузі, **поки людина не відпустить**, якщо це контрольований
> ран» — **[062]** (VERIFIED — transcript line 142)

Nothing in either answer says which wins. Concrete failure from the challenge (A1): 03:40, controlled
run, the worker asks *"the migration drops `users.legacy_id` — proceed, or keep and backfill?"*. The
orchestrator is a configured answerer, so it answers "proceed". No hard stop is raised, nothing pauses,
and at 09:00 the column is gone and merged. His own rule — doubt reaches him, work holds — never fired,
because the doubt was consumed one layer below where the rule lives.

**Provenance note the room should hear in one clause.** The phrase «в межах налаштованих повноважень»
that softens this in the record is the **interviewer's**, added in the restatement at [325]/[327]
(VERIFIED — transcript lines 421–423; `extract/by-item.md` R1-11 row 3 flags it as not his). He
confirmed the restatement, but he never spoke the qualifier, and he doubled «повністю і повністю окей»
in his own answer. So the qualifier cannot be read as his refusal class — there is none on record.

**Why "the user configures it" does not close it.** He made the *basis* for an answer configurable —
tone of voice, previous similar answers, repository documents, the agent's own project knowledge
([087] line 167, [092] line 172). A basis tells you **how** to answer, not **whether this one is yours
to answer**. No configured predicate for "refuse and escalate" exists, and he named none.

**What the answer changes.** Whether "controlled run" is a real mode or a label. If the orchestrator
answers everything, the entire C1 controlled/autonomous distinction is decorative at the level where
work actually gets decided.

---

## Q2 — May a session start headless when the orchestrator cannot prove it can answer it? · **feasibility · blocker**

> «Я це перевірив на твоїй машині сьогодні. Якщо код-код запущений невидимо, викликає ask user
> question, а оркестратор просто дозволяє цей виклик — сесія отримує відповідь "користувач відповів
> на твої питання" з **порожнім** списком відповідей і йде далі, так ніби її спитали. Тихо, без
> помилки. А на джемінай каналу для таких питань взагалі не існує — питання приходить просто текстом,
> і сесія висить. Питання: чи можна взагалі стартувати сесію невидимо, якщо оркестратор не має
> гарантованого способу відповісти на її питання?»

Options to read out, and stop:
- «ні — невидимо можна тільки там, де канал для питань гарантовано є»
- «так, але тоді оркестратор забирає в сесії рідний ask user question і дає замість нього свій
  інструмент для питань»
- «так, як є — хай іде далі, я приймаю цей ризик»

**Why this is the hole.** He flagged the danger himself and could not know what it was:

> «можна конфігурувати, що щось буде невидимо, наприклад самому код-коду, запускати його в headless
> режимі. **Але з цим треба бути дуже обережним**» — **[324]** (VERIFIED — line 420)

This is the specific thing. **VERIFIED by running it today** (research §4.1) — an allowed
`AskUserQuestion` in a headless Claude Code session returns:

```json
"content":"User has answered your questions: . You can now continue with the user's answers in mind."
"tool_use_result":{"questions":[…],"answers":{}}
```

`answers: {}`, and the sentence ends on a bare period where the answer should be. The child model in
that run *noticed* — "the function result says 'User has answered your questions: .' without showing
what the answer was. This is unusual…" — and completed the task anyway.

**And his own verification decision removes the net.**

> «ці всі перевірки відбуваються **виключно так, як юзер налаштував** … **не роби обмеження** те, що
> вся робота потім буде мати тести» — **[344]** (VERIFIED — line 442)

No user's process contains a test for "did my agent receive the answer it thinks it received". That is
not a category any test framework has. FIELD-NOTES is the precedent for this exact shape: a merge that
printed `Already up to date` and moved nothing (§4.1, line 229); GSD's verify silently skipped for
phases 14–18, each verification file self-attributing `verified_by: the lane that built the phase`,
"No automated check caught it" (§11.4) — all VERIFIED in the file.

**The second half of the question is not Claude-specific.** ACP — the protocol Gemini CLI speaks —
standardises **permissions** and has **no question primitive** at all (CLAIMED, confirmed absent across
two ACP doc pages; research §4.2). `cursor-agent` has exactly one switch, `-f / --force`, and no
per-request channel (VERIFIED, `--help`). So the configuration surface will happily accept a
combination that is structurally impossible, and nothing on record requires the orchestrator to refuse
it at launch. That is challenge A12, folded in here rather than asked separately.

**A verified escape exists and is named as option two, not recommended.** Disallowing the native tool
and injecting an MCP tool the orchestrator owns produced a clean answer with no `is_error` and no
phantom (research §4.1/P2, run end to end). MCP is supported by Claude Code, Codex, Gemini CLI and
opencode, so one implementation covers every platform — including the two that expose no question event
at all. Option three is his to take; it is stated as he framed it, as a risk he accepts.

**What the answer changes.** Whether the rebuild ships a question-channel precondition on session
launch, and whether it ever ships its own asking tool. This is the single decision that sets how much
of an unattended night is trustworthy.

---

## Q3 — Who answers the orchestrator? · **gap · blocker**

> «Оркестратор відповідає на питання всіх сесій. А хто відповідає на питання самого оркестратора? Ти
> сказав, що другий оркестратор — це заборонено, бо буде нескінченний цикл оркестраторів. Значить,
> о четвертій ночі, коли оркестратор сам упреться в питання, а тебе немає — хто йому відповідає?»

Options to read out, and stop:
- «ніхто — оркестратор взагалі не має права ставити питання, він завжди вирішує сам»
- «той агент, що раз у N годин перевіряє, чи ран живий — він і відповідає»
- «ран стає на паузу і чекає мене до ранку»

**Why this is the hole.** The mode is per platform, and the orchestrator runs on a platform — nothing
in [324] exempts it. When *it* asks, there is by construction nobody above it, and his own invariant
forbids creating one:

> «не може бути такого, що вже якісь існуючі оркестратор і спускається наступний, тому що тоді це
> буде просто **нескінченний цикл оркестраторів**» — **[300]** (VERIFIED — line 396) ·
> «Це треба відслідковувати і **не дозволяти**» — **[301]** (line 397)

> «має бути щось, що може допомогти запустити ран і продовжити роботу **без участі в налаштуваннях
> користувача**» — **[266]** (VERIFIED — line 354)

Concrete failure (A3): 04:55, the orchestrator running headless hits a conflict between the ticket and
the repository rule he called «дуже важливо» ([331] — only PRs allowed here). It asks *"merge directly
or open a PR?"*, receives `answers:{}` per Q2's verified behaviour, reads the empty answer as
permission, and merges direct to `master`. Lower probability than Q1/Q2 — it needs the orchestrator
itself to ask — but the largest blast radius in the cluster: it is the process that merges to trunk,
spawns and closes sessions, and decides recovery.

**Option two is not currently that agent.** The health-check he described is specified as a *liveness*
probe, not an answering authority:

> «запускати якогось агента раз в N годин на якійсь іншій підписці … аби це було якось детерміністсько
> в результаті» — **[246]** (VERIFIED — line 334)

Choosing it here gives it a second job it does not have yet. FIELD-NOTES §10.1 is the reason this
matters: on the last real run the orchestrator was itself the component that died and had to be
replaced five times — it is not a reliable narrator of its own state, and here it has no supervisor at
all (VERIFIED).

**What the answer changes.** Whether the design has a second, differently-privileged actor at all, or
whether the orchestrator is defined as a component that never asks.

---

## Q4 — Which "invisible" does headless mean? · **definition · major**

> «Ти сказав "запускати код-код в headless режимі". Я перевірив — невидимих режимів у код-коду
> декілька, і вони не однакові. В одному оркестратор може вести з сесією повноцінний діалог скільки
> завгодно. В іншому, фоновому, сесію видно в списку, з ім'ям і станом, але надіслати їй **нічого не
> можна** — заблокована сесія розблоковується лише тим, що хтось до неї підключається. Який із них ти
> маєш на увазі, коли кажеш headless — той, з яким можна говорити, чи той, який просто невидимий?»

Options to read out, and stop:
- «той, з яким оркестратор може говорити»
- «той, що просто невидимий — і тоді всі дозволи вирішуються наперед, до старту»
- «обидва, і це ще одне налаштування»

**Why this is the hole.** He specified a *property* («щось буде невидимо»), not a runtime. **VERIFIED**
on this machine (research §3.1) that Claude Code 2.1.278 has four things that satisfy it: one-shot
`-p`; a long-lived `-p --input-format stream-json --output-format stream-json` process that keeps state
across turns (I ran a two-turn conversation through one and it remembered); `claude --bg` with a real
registry; and a detached PTY, invisible until attached.

They differ on exactly the axis his second sentence depends on. **VERIFIED** (§4.3): `claude --bg`
exposes `agents`, `attach`, `logs`, `stop`, `rm`, `respawn`, `--resume` and **no send or answer verb**;
`claude agents --json` reported `"state":"blocked"` on two of his own real background sessions while I
looked.

Concrete failure (A4): the implementer reads "headless", picks the backgrounded mode — the one the
vendor markets as backgrounded, ships a registry for, and which matches «щось буде невидимо» most
literally — and the orchestrator's whole answering design has no channel to it. FIELD-NOTES is the
precedent for how that looks from outside: a `question`-role session finished and sat registered and
idle for **one day and four hours** with nobody to close it (§1.6, line 142), and a stale heartbeat
peaked at **44791 s, about 12.4 hours**, before anything fired (§11.1, line 462). Both VERIFIED. The
run looks alive the whole time.

**What the answer changes.** Whether his second requirement — the orchestrator answers questions — is
achievable or impossible on the mode the implementer picks. Two implementers, two products, both
faithful to [324].

---

## Q5 — What does «інколи» measure? · **gap · major**

> «Один із режимів ти придумав сам: "переважно інтерактивні і тільки інколи headless". Це єдиний із
> чотирьох, який не налаштування, а правило — хтось мусить вирішувати по кожній окремій сесії, куди
> вона піде. Що таке "інколи" — що саме воно міряє?»

Options to read out, and stop:
- «тип роботи в тікеті»
- «скільки сесій уже відкрито — просто ліміт на кількість видимих вікон»
- «час доби — вночі невидимі, вдень видимі»
- «оркестратор вирішує сам, по ситуації»

**Why this is the hole.** The mode is his own invention — the interviewer's list did not contain it:

> «або гібрид, або **переважно інтерактивні і тільки інколи headless**» — **[324]** (VERIFIED — line 420)

He named no predicate, no budget, no flag and no default, and both honest readings collapse the mode
(A6). **Reading 1**, a per-ticket opt-in: no ticket ever sets it, because tickets are written by him
and by agents that do not know the flag exists — so mode four is operationally identical to mode one
for the life of the project and the capability is dead code. **Reading 2**, time-based, which is what
the *purpose* of the tool suggests: at 23:00 the whole fleet flips, and the run's entire unattended
stretch — which is all of it — executes in the mode he flagged «треба бути дуже обережним», with Q2's
verified corruption live the whole night. Mode four becomes mode two every night.

Six plausible predicates exist (count, concurrency budget, ticket class, clock, authority coverage,
the orchestrator's own judgement) and nothing on record breaks the tie.

**What the answer changes.** Whether mode four is a scheduler input, a per-ticket field, or a runtime
judgement — three different pieces of code, and the difference only shows up on the nights that matter.

---

## Q6 — What runs when nothing is configured? · **default · major**

> «Уся ця відповідь — "залежить від конфігурації". Уяви: я ставлю плагін на чисту машину, нічого не
> налаштовую і просто запускаю ран. Що має статися з коробки?»

Options to read out, and stop:
- «все інтерактивно — усі сесії у видимих вікнах»
- «все невидимо»
- «взагалі не стартує, поки я явно не вкажу режим»

**Why this is the hole.** He answered "it is configurable" to a question about what the system *does*,
and a configurable answer is complete only when it names the value at zero configuration. His general
instinct is quoted often and points at neither option: «нічого надприроднього не потрібно вигадувати»
[171], «це має бути надійна річ, **дуже проста**» [300] (VERIFIED — line 396).

The two candidates fail in opposite directions (A7). **Default interactive**: twelve sessions, twelve
windows on a machine that is also his workstation — FIELD-NOTES §9.5 records nineteen phases with
worker sessions of 58 minutes to 5 h 31 m over 34 hours (VERIFIED) — plus the PTY delivery failure
family in §1.3/§11.2. **Default invisible**: the new user gets Q2's silent corruption on their first
night and has no window in which the evidence would have been visible.

The first-run user is also exactly the person who cannot make this choice: the information needed —
does my platform have an answer channel, does my work ask questions — is only available *after* the run
that would teach it. And the previous generation's `session.permissions` defaulted to `bypass`
(VERIFIED — FIELD-NOTES §0 configuration-key list), so "the default nobody chose" already has a track
record here.

**What the answer changes.** The first-run experience on every install, including his own second
machine.

---

## Q7 — Does visibility hang on the platform or on the role? · **collision · major**

> «Ти сказав "під кожну платформу своє налаштування". Але в питанні про компакт ти описав інше: у тебе
> три вікна код-коду — контекст вочер, оркестратор і екзек'ютор — і для кожного свої налаштування. Це
> ж одна платформа. Якщо режим сесій чіпляється до платформи, то оркестратор і всі його екзек'ютори
> будуть однакові — або всі видимі, або всі невидимі. До чого чіпляється видимість: до платформи чи
> до ролі?»

Options to read out, and stop:
- «до платформи, як я сказав»
- «до ролі, а платформа — це вже деталь»
- «є значення на платформу, і роль може його перебити»

**Why this is the hole.** Both halves are his, in different items, and they are different keys:

> «**Під кожну платформу своє налаштування**, і це окей» — **[324]** (VERIFIED — line 420)

> «якщо, наприклад, в мене є Клод Код, і допустимо, **три вікна, перше, це контекст вочер, друге, це
> оркестратор, третє, це екзек'ютор**, чогось, то я для кожного з них можу вказати, який буде поріг
> компакту» — **[204]** (VERIFIED — line 288)

[204]'s three windows are all one platform; the platform axis cannot separate them. His role taxonomy
recurs at [036] (line 116), [195] (line 279) and [204] and never appears in ANALYSIS-01.md at all
(VERIFIED — `extract/by-item.md`). The previous tool already found the platform axis insufficient and
routed **accounts per role** — `orchestrator`, `worker`, `validator`, `question` — not per platform
(VERIFIED, FIELD-NOTES §8).

Concrete failure (A5): an implementer keying on [324] literally writes one value for Claude Code and
every worker in the run opens a visible window. Not silent — he sees nineteen windows and complains —
but the config cannot express the setup he described on day one.

**What the answer changes.** The shape of the configuration file, and whether a per-role override
exists at all. It cannot be retrofitted once the config schema ships.

---

## Q8 — Who owns a session's input line? · **gap · major**

> «У сесії один рядок вводу, а охочих у нього писати тепер троє: ти сам, коли заходиш і пишеш руками;
> оркестратор, коли відповідає на ask user question; і механізм компакту, який ти назвав гарантованим.
> У минулому рані двоє таких уже стикались: текст, що лежав у рядку, просто затирався, обидва писали в
> лог, що все вийшло, і п'ять інструкцій так і не дійшли. Хто головний на цьому рядку?»

Options to read out, and stop:
- «оркестратор — і поки він відповідає, компакт чекає»
- «компакт — він може перебивати будь-що, він же гарантований»
- «людина — якщо я сам у цьому вікні, туди ніхто більше не пише»

**Why this is the hole.** Three writers were specified in three different items, each assuming sole use.
His own words for the third:

> «повинен бути **механізм, який гарантовано робить цю дію**» — **[204]** (VERIFIED — line 288), and
> FIELD-NOTES §1.1: `/compact` is typed into a session's terminal **by another process**.

And R1-11's question presumed the first — «куди ти можеш зайти і **написати руками**» [319] (VERIFIED —
line 415) — which he did not reject.

**What already happened, measured** (FIELD-NOTES §1.3, five occurrences, VERIFIED): a bare Enter does
not submit text already sitting on the line; `send <tty> "<text>"` types its own text and submits, so it
**destroys** whatever was pending; whatever sits on an idle input line when a background task
re-invokes the session is discarded. §11.2 records a **thirteenth consecutive** stranded `continue` on
the orchestrator's input line, "sitting beside a live Playwright run it could have corrupted".

Concrete failure (A8): 02:47. A worker raises the question dialog — **VERIFIED** shape, options 1–2
plus `3. Type something` plus `4. Chat about this`. The orchestrator decides to answer "2". In the same
window the compaction threshold trips and `/compact` goes into the same pane. Either the dialog is open
and `/compact` is consumed through option 3 and **becomes the answer to the question**, or the
compaction send lands first and wipes the pending keystroke, and the dialog is answered by nobody —
while both writers' logs record success.

*Honest scoping note for the room, not to be read aloud:* those five failures are recorded against the
**iTerm2/AppleScript** path, not tmux. On tmux + 2.1.278 I could not reproduce them — a bare Enter
submitted, and a message typed into a busy session was visibly **queued** and later ran in order,
nothing lost (VERIFIED, research §3.1.5). The collision above does not depend on which backend is used;
the five-lost-instructions figure does. Do not generalise it in the room beyond "two senders already
collided".

**What the answer changes.** Whether the design needs a per-session write lock and a queue, or whether
one writer is simply declared to win. Both are small; choosing neither is what produced §11.2.

---

## Q9 — Must the orchestrator's answer be marked as its own? · **gap · major**

> «Я перевірив: коли оркестратор відповідає замість тебе, у транскрипті сесії записано "користувач
> відповів на питання" — рівно так само, як коли відповідаєш ти. Різниці не видно взагалі. А ти
> сказав, що агент може вирішувати на основі твоїх попередніх відповідей на схожі питання. Тоді на
> другу ніч він вчиться на своїх власних вчорашніх здогадках, вважаючи їх твоїми. Чи має відповідь
> оркестратора бути позначена як його, а не твоя?»

Options to read out, and stop:
- «так — і в основу для наступних рішень беруться тільки мої власні відповіді»
- «так, позначена, але вчитися можна на обох»
- «ні, різниці не треба»

**Why this is the hole.** **VERIFIED** (research §3.1.6a) — after the orchestrator sent a single
keystroke, the child session recorded:

```
⏺ User answered Claude's questions:
  ⎿  · Which environment should we deploy to? → Production
```

No marker distinguishes that from him typing it. Put next to the two places he made the system learn
from past decisions:

> «якщо це не підходить, то **треба вчити**, відповідні дії» — **[062]** (VERIFIED — line 142)

> «Це може бути якийсь tone of voice, або дивитися в альтернативи інших питань … **Коли відзадавав
> подібні питання, що відповідав, і на основі цього відповідати**» — **[087]** (VERIFIED — line 167),
> and «майже замість неї може відповідати, по причині попередніх прикладів» — **[092]** (line 172)

Concrete failure (A10): night one the orchestrator answers eleven questions from project knowledge;
four are wrong but harmless, and all eleven are recorded as his. Night two the configured basis is
"previous answers to similar questions", so the orchestrator reads its own four wrong answers as his
precedent. Meanwhile [062]'s corrective loop cannot run at all: at 09:00 he reads "User answered:
Production" and has no way to know it was not him, so there is nothing to correct. FIELD-NOTES §2.1 is
the precedent for a correction channel silently going nowhere: `state/attention` was rebuilt from
scratch every watch cycle and a whole night of the context watch's corrections went to `/dev/null`,
found by accident (VERIFIED).

**What the answer changes.** Whether an answer ledger exists — question, options, answer, authority
basis, timestamp, and who gave it — and whether the learning loop he asked for is implementable at all.

---

## Q10 — May the orchestrator answer a session it did not start? · **gap · major**

> «Ти сказав: якщо я в тій самій папці паралельно щось роблю сам, оркестратор цього не має чіпати. Але
> список сесій на машині цього не розрізняє — твоє власне вікно і його вікна лежать там поруч, однакові.
> Уяви: о дев'ятій вечора ран живий, ти працюєш у своєму вікні, твоя сесія показує ask user question, і
> ти відходиш на чай. Оркестратор має право на неї відповісти?»

Options to read out, and stop:
- «ні — тільки ті сесії, які він сам запустив»
- «так, якщо це та сама папка і той самий ран»
- «так, на будь-яку — це ж однаково моя машина»

**Why this is the hole.** He forbade this in a different item, about files and tests, not dialogs:

> «в тій самій папці **я паралельно працюю над чимось, це не запускав оркестратор, це роблю я**, він
> цього не має зупиняти» — **[370]** (VERIFIED — line 470) ·
> «оркестратор має бути якось **селфевернес**, що він, до чого він може змінювати» — **[366]** (line 466)

Against [324], which scopes the interaction to nothing in particular.

**The enabling fact is VERIFIED** (research §3.1): `claude agents --json` on this machine returned his
own interactive sessions alongside background ones —
`{"pid":35475,"kind":"interactive",…,"status":"busy"}` next to
`{"id":"8402872a","kind":"background","state":"blocked"}`. It is the best session inventory available
on the platform and it does not distinguish "mine" from "his". The same is true of any pane-scanning
approach: a pane with a question dialog on it looks identical whoever opened it. FIELD-NOTES §1.6 shows
the inverse confusion already happened — a `question`-role session's terminal title read
`harness-question-q-screen-orchestrator` and **the product owner read it as a second orchestrator**
(VERIFIED).

**What the answer changes.** Whether session ownership is a tracked, enforced property from day one, or
whether the orchestrator is allowed to use the platform's native inventory as its work list.

---

## Surviving gaps NOT turned into questions, and why

Listed so a later round can pick them up rather than lose them.

1. **A9 — an answer sent as keystrokes has no acknowledgement.** VERIFIED that `send-keys -l '2'`
   answers the dialog cleanly, and equally verified that nothing confirms it to the sender: the
   orchestrator learns it landed only by scraping the pane, and §4.4 measures how unreliable that read
   is — the spinner verb is randomised (`Pollinating…`, `Baked for 2s`, `Churned for 29s`,
   `Cooked for 3s`), `capture-pane -p` returned **empty for several seconds on a live pane**,
   `#{pane_current_command}` was `2.1.278` rather than `claude`, and everything reflows at a different
   window width. Cut because his likely answer ("obviously it must be verified") changes little, and
   because Q8 already forces the input-line design where the fix lives. **Carry it to the build, not to
   the interview.**

2. **The backend choice — tmux instead of iTerm2/AppleScript.** A proposal, not a hole, so it is not a
   question here (research P4). Worth putting to him as a decision at build time: `claude --tmux`
   exists and "uses iTerm2 native panes when available" (VERIFIED, `--help`), so tmux-in-iTerm2 keeps
   the look he actually uses while gaining a scriptable control channel. One live bug to fix regardless:
   `harness-term.sh:197-198` sends `tmux send-keys -t "$p" "$2"` with **no `-l`**, so any argument
   colliding with a tmux key name (`Up`, `Enter`, `Space`, `Escape`, `Tab`, `BSpace`) is delivered as
   that key, not as text (VERIFIED in source).

3. **The first-run trust dialog.** VERIFIED: a fresh interactive `claude` in an unseen directory blocks
   on "Quick safety check: Is this a project you created or one you trust?" with no protocol event
   behind it; `-p` skips it. A PTY orchestrator must answer it before its worker exists — in a fresh
   ворктрі that is every session. Owned by the spawn cluster, and the previous tool already shipped a
   `harness-trust.sh` for it, so it is a build note, not a question.

4. **`claude --remote-control` and native session inventories.** `claude agents --json`,
   `codex agents` / `thread/list` and opencode's session status are better registries than the one the
   previous tool maintained by hand (VERIFIED for the first two). Whether to adopt them per platform or
   keep one uniform registry is an architecture question for the build, and asking it in a voice round
   would cost a minute and change nothing he can judge out loud.

5. **Codex's `approvalsReviewer: "auto_review"`** — a vendor-shipped subagent that decides approvals on
   the user's behalf with a "risk-based decision framework" (VERIFIED, generated schema). It is his idea
   already built, but under *their* policy. Only worth asking after Q1 fixes whose authority applies;
   asking both in one round would confuse the two.
