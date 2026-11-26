# C4 — Quota, limits, providers and accounts per role · round-2 questions

Cluster: **C4-capacity** · Items: **R1-06** (rows `[007]`, `[171]`), **R1-07** (rows `[036]`, `[041]`,
`[195]/[196]`, `[199]`, `[270]`), owner instruction **I1** `[182]/[183]`
Date: **2026-09-19** · Round: **2** · Format: **voice, Ukrainian**
Read first: `C4-capacity-research.md`, then `C4-capacity-challenge.md`

Ten questions. Five blockers, five majors. Every one is a hole the challenge pass found in a decision
he already made, or — in two cases — a question that was written for round 1 and never put to him.
None re-asks something he settled. None carries a recommendation: where real alternatives exist they
are read out flat and the question stops.

Evidence marks: **VERIFIED** (read in the transcript, the field notes, the plugin source, or run on
this machine today), **CLAIMED** (a third party asserts it), **INFERRED**.

**They are numbered in the order they should be asked, not by severity.** Q1 fixes the vocabulary that
Q4, Q7, Q9 and Q10 all spend. Q3 can shrink half the list — if he answers "minimal for v1", stop and
re-scope rather than grinding through Q4–Q7 for a machine he just said not to build yet.

---

## Index

| # | Question | Kind | Priority |
|---|---|---|---|
| Q1 | The three stop modes were never confirmed — he asked for a repeat and the interviewer moved on | ratify | major |
| Q2 | Headroom for his own morning — half of R1-06 was never asked at all | gap | **blocker** |
| Q3 | 34 hours reached 26% of weekly; the quota never bound anything | gap | major |
| Q4 | «80% тижневого» — whose 80%, and what exactly stops | collision | **blocker** |
| Q5 | On pay-as-you-go there is no percentage, no window and no reset to wait for | gap | **blocker** |
| Q6 | Nine of thirteen platforms cannot support a hard stop at all | feasibility | **blocker** |
| Q7 | What happens when the number cannot be read — the shipped default was «proceed» | default | **blocker** |
| Q8 | What must the pre-run check actually prove — two profiles can be one account | definition | major |
| Q9 | «хард» means "stop the run" in one rule and "switch now" in the other | collision | major |
| Q10 | A role-locked account exhausted at 01:00 with a reset days away | gap | major |

---

## Q1 — Read the three stops back and confirm them · **ratify · major**

> «Тоді, коли ми це проходили, ти попросив повторити — і твоє «так» так і не прозвучало, інтерв'юер
> пішов далі. Читаю ще раз, підтвердь або виправ. Хардстоп — зупинити те, що в роботі, прямо зараз.
> Софт стоп — дати поточному завданню дійти до кінця, а нових не запускати. Проміжний — записати
> стан, зберегти сесію, зупинити її повністю, щоб потім продовжити. Так?»

**Why this is the hole.** The substance is his, verbatim at **[171]** (VERIFIED):

> «то це означає хардстоп, що потрібно зупинити завдання прямо вже та й все»
> «Якщо це софт стоп, наприклад, 80 відсотків, то агент може ще почекати, поки виконує це завдання,
> після цього більше не зупиняти»
> «Не знаю, щось проміжне між софт і хардстопом, це про те, аби записати теперішній стан, можливо
> зберегти сесію, і зупинити її повністю, аби потім можна було її продовжити»

What is missing is the **label**. `research/extract/corrections.md` records the mechanics (VERIFIED):
the interviewer put the restatement at **[176]/[177]**, the owner said **«Повтори, будь ласка»**
**[178]**, it was repeated at [179]/[180], and [181] went to the next topic with no answer. The file's
verdict: *"The entire hard/soft stop rule for limits (R1-06) is unratified."*

This vocabulary is then reused across R1-07 (`[195]/[196]` soft/hard changes in the assignment file),
R1-08 (`[204]` soft/hard compaction) and Д12. Four questions below spend it. Confirm it once, at the
top, or every later answer is denominated in a unit nobody agreed to.

**What the answer changes.** Nothing, if he confirms — and that is the point: a confirmed label costs
thirty seconds and removes a shared assumption from four other clusters. If he corrects it, every
downstream design in C4, C5 and Д12 moves.

---

## Q2 — Can it spend the limit down to zero? · **gap · blocker**

> «Це питання було написане для першого раунду, але його тобі так і не поставили, тому ставлю зараз.
> Коли оркестратор працює вночі — він може з'їдати ліміт до нуля, чи має лишити тобі запас на ранок?
> Якщо запас — скажи, скільки саме лишати.»

Options to read out, and stop:
- «до нуля, мені запас не потрібен»
- «лишати запас — і я назву число»

**Why this is the hole.** `questions.md` R1-06 has two halves. The first was asked. The second was not:

> «**Чи можна витрачати ліміт до нуля, чи треба лишати запас на твою власну роботу?**»

`research/extract/corrections.md` confirms it (VERIFIED): *"Half of R1-06 was dropped by the
interviewer. There is **no answer anywhere in the transcript**."* Every threshold discussed in this
cluster — his own «80% тижневого» included — is a threshold against **exhaustion**. A reserve is a
different number, and possibly a different mechanism (a ceiling on the run, not a floor under him).

His own words make it load-bearing rather than cosmetic, at **[370]** (VERIFIED):

> «Другий кейс, якщо, наприклад, в тій самій папці я паралельно працюю над чимось, це не запускав
> оркестратор, це роблю я, він цього не має зупиняти.»

He states a hard non-interference rule between the run and his own parallel work. Quota is the one
resource where that isolation is physically impossible when both sit on the same account — and Q8
shows he may believe he is isolated when he is not.

And the wait is not short. VERIFIED in today's live read of the usage endpoint: `seven_day.resets_at`
= `2026-09-20T11:59:59+00:00`. A weekly window crossed mid-week does not come back in five hours; it
comes back on a fixed weekly boundary, potentially days later.

**What the answer changes.** Whether the config has one number per account or two (spend ceiling and
reserve floor); whether the run's own threshold is computed on total account usage or on the run's own
share; and whether there is any concept of "this stop was not the run's fault" when *his* typing, not
the run's work, crosses the line. Challenge A12.

---

## Q3 — How much of this belongs in the first version? · **gap · major**

> «Дивись, що показав минулий ран, це твої ж дані. Він ішов тридцять чотири години і з'їв двадцять
> шість відсотків тижневого ліміту — у ліміт не вперся жодного разу. Зупиняли його залежності між
> завданнями, а не ліміти. Ти сам казав, що нічого надприродного вигадувати не треба. Скільки з цієї
> машинерії має бути в першій версії?»

Options to read out, and stop:
- «усе, як я описав — пороги, три стопи, окремо на кожну роль і провайдера»
- «на початку тільки: впертися, записати стан, продовжити після скидання — пороги потім»

**Why this is the hole.** `plugins/harness/docs/FIELD-NOTES.md` §5.3 is titled *"A five-hour token
window is not the constraint"* and records (VERIFIED): across 34 hours the watched account reached **26%**
of its weekly allowance, and *"The dependency graph, not the quota, bounded throughput: of nineteen
phases only two pairs could ever run concurrently."*

Against his own repeated constraint at **[171]** (VERIFIED, and he says it at least four times in the
session — [171], [189], [300], [370]):

> «Тому тут нічого надприроднього не потрібно вигадувати»

And his own recovery rule at [171] already describes the minimal version in full:

> «в нас в реєстрі має записуватись кожен стан, його виконання, що там як, куди, для того, щоби було
> відновити процес і продовжити, навіть руками, або просто продовжити після того, як ліміти онуляться»

**This is not a recommendation and must not be delivered as one.** The limit machinery is his call and
the requirement stands. What the evidence says is that the one measured 34-hour run of the previous
generation spent this machinery on a constraint that never bound. He is the only person who can decide
whether that is a reason to defer it.

**What the answer changes.** Whether Q4–Q7 need answering at all this round. If he takes the second
option, the build is "hit the wall, write state, resume after reset" plus Q2's reserve — and the
per-role, per-provider, per-window threshold system moves to v2. Ask this early for exactly that
reason. Research §6 item 3; the challenge files it under "what this pass did not attack".

---

## Q4 — Whose 80%, and what exactly stops? · **collision · blocker**

> «Ти сказав: хардстоп, коли якийсь ліміт дійшов, наприклад, до вісімдесяти відсотків тижневого. Але
> ролі в тебе сидять на різних акаунтах, і в кожного акаунта свій ліміт. Чий саме ліміт має спрацювати
> і що саме після цього зупиняється?»

Options to read out, and stop:
- «будь-який акаунт перетнув — зупиняється весь ран»
- «зупиняються тільки сесії того акаунта, який перетнув»
- «поріг задається на роль, і зупиняється тільки ця роль»

**Why this is the hole.** [171] is written in the singular — one limit, one number, one stop (VERIFIED):

> «людина може лише налаштовувати хард ліміти, хардстопи, коли якийсь ліміт, наприклад, там , 80%
> тижневого, або що … то це означає хардстоп, що потрібно зупинити завдання прямо вже та й все»

[036] and [041] make the run plural (VERIFIED):

> «на кого буде працювати оркестратор, на кого буде працювати скажімо, контекст фочер, на кому
> екзек'ютор буде» — **[036]**
> «з кожної з цих платформ може бути різна кількість аккаунтів» — **[041]**

Three readings are all defensible from his words, and two implementers ship different machines:

- **Any account crosses → stop the run.** 03:40, the orchestrator's account is at 82% after thirty
  hours of cheap supervision; the executor accounts are at 8%. The whole run dies over the role with
  the least work left. He opens the laptop to a stopped run with 92% of his executor capacity untouched.
- **Per account → stop only that account's sessions.** Same moment. The orchestrator's sessions are
  killed; three executors keep working, finish their phases, and have nobody to merge them or spawn the
  next wave. `FIELD-NOTES.md` §10.1 records this exact end state from the real run (VERIFIED):
  `watch: orchestrator dead + no live sessions for 3 ticks — tearing down`, with `DEAD-RUN` and
  `STOPPED` on disk.

**Two smaller undefineds, worth catching in his answer if he volunteers them.** Whether a threshold
applies to the *worst* bucket on an account or to one named window; and whether soft and hard are two
thresholds on one number or two independent settings — his own example gives both the same value
(«хардстопи … 80% тижневого» and «Якщо це софт стоп, наприклад, 80 відсотків»), at which point they
cannot both fire.

**What the answer changes.** The scope of every threshold in the config, the shape of the stop event,
and whether a role whose account is exhausted can be moved to a healthy one — which collides with
Q10's restriction. Challenge A2.

---

## Q5 — What is the threshold when there is no window? · **gap · blocker**

> «Ти сам сказав, що може бути взагалі pay-as-you-go. Я перевірив, як це виглядає насправді: там немає
> ні відсотків, ні вікна, ні моменту, коли ліміт онуляється — є тільки залишок грошей, який сам собою
> не поповнюється. Усі три твої стопи задані у відсотках вікна, і чекати там нічого. У чому тоді
> задається поріг для такого провайдера?»

Options to read out, and stop:
- «у грошах на один ран»
- «у грошах на добу»
- «такі провайдери взагалі не беруть участі в порогах — вони не отримують ролей, де потрібен стоп»

**Why this is the hole.** His own words at **[007]** (VERIFIED):

> «тут не має бути конкретної прив'язки до Клода, Треба, мати можливість адоптовуватись до нових прав.
> Що якщо раптом буде не п'ятигодинне вікно, а десяти годинне вікно, або його взагалі не буде? Тобто в
> залежності від підписки, можливо це буде взагалі pay-as-you-go»

He treats "no window" as a **shape** to adapt to. It is not a shape — it is the absence of the quantity
all three stop modes are expressed in. VERIFIED from official docs (research §3.4): DeepSeek's
`GET /user/balance` returns `is_available` plus `total_balance` in CNY/USD — no window, no percentage,
no `resets_at`. Amp is credits, same story (CLAIMED, research §3.11). So «просто продовжити після
того, як ліміти онуляться» [171] has no referent: nothing zeroes.

**And this is not an exotic case — it is the default for two platforms he named at [041].** Qwen's free
OAuth tier closed **2026-04-15** and Qwen is BYOK-only now; Google's consumer Gemini CLI path ended
**2026-06-18** and the documented replacement is a paid key (both CLAIMED, research §3.6/§3.7).

**Concrete failure.** An executor on a pay-as-you-go key enters the loop `FIELD-NOTES.md` §3.1 records
from a real lane (VERIFIED): `w-phase-19` issued **3,466 of its 3,626 Bash calls as the literal command
`echo idle`**, mean interval 2.54 s, for three hours fifteen minutes, producing 274k output tokens and
1.83 billion cached-token re-reads of nothing. There is no window to fill, no percentage to cross and
no reset to wait for. It bills until he wakes up. In the real run it stopped only because a human told
it to.

**What the answer changes.** Whether thresholds are a single global number or per-provider and typed
(percent / currency / credits); whether a run carries a money cap at all; and what the default is for a
provider that reports nothing. Challenge A4, research §4.2.

---

## Q6 — What do we do with a platform that shows nothing? · **feasibility · blocker**

> «Ти просив перевірити, чи це взагалі можливо на різних платформах — я перевірив тринадцять.
> Показують, скільки ліміту лишилось, тільки чотири. Курсор, Копайлот, Квен, Джемінай і ще кілька не
> показують нічого — там про ліміт дізнаєшся тільки тоді, коли вже в нього вперся. Хардстоп на них
> фізично неможливий. Що робити з такою платформою?»

Options to read out, and stop:
- «не давати їй ролі, де я вимагаю хардстоп»
- «давати, але чесно писати в конфігурації, що стоп там буде тільки після того, як вперлося»
- «давати, і не морочити голову»

**Why this is the hole.** This is the direct reply to his own instruction at **[182]/[183]** (VERIFIED):

> «Якщо, наприклад, при різних платформах це буде неможливо, то про це треба говорити і обдумувати, як
> можна це зехендлити … це треба буде винести окремими питаннями потім»

The count, from research §3.13 (mixed VERIFIED / CLAIMED, per platform): four platforms expose a real
remaining-capacity reading (Claude Code, Codex, Z.ai, and Kimi if its path is confirmed); two expose a
balance with no window (DeepSeek, Amp); the rest expose nothing usable to an individual. Cursor
CLI — VERIFIED on this machine by reading its complete `--help`: there is no usage, quota, limit or
balance command at all, and `status` checks authentication, not quota. Copilot's own docs (VERIFIED
absence on the page) document three routes — the IDE, the billing page, the analytics sidebar — and no
REST endpoint for an individual's own remaining quota; on limit-hit it says *"you will be notified with
a message in each of the Copilot interfaces you use"*.

**And the fallback everyone reaches for must not come back.** Reading the limit off the session's own
screen produced two independent multi-hour false-positive loops in the previous generation
(`FIELD-NOTES.md`, VERIFIED): an **85-minute loop** where the watch matched a usage-cap banner inside
*the orchestrator's own wrapped prose*, pressed Escape and sent `continue` every ~60 seconds —
*"Nothing internal detected it — it ended when an external `SIGTERM` reached the orchestrator"* — and a
separate **45-minute** false-positive loop on a healthy orchestrator.

**His own [270] already contains one of the answers**, which is why the first option is phrased in his
words rather than mine:

> «вона може вказувати, для чого вони можуть використовуватись. Наприклад, що може використовувати
> тільки для оркестратора, щось може використовуватись тільки для екзек'ютора … І це важливий дуже
> нюанс»

**What the answer changes.** Whether the config is capability-gated (a provider declares what it cannot
do, and roles requiring that guarantee simply cannot be assigned to it) or uniform-looking with
per-platform meanings underneath. Research §4.1, §5.2; challenge A3/A6 context.

---

## Q7 — What happens when the number cannot be read? · **default · blocker**

> «Буває, що числа ліміту просто не видно — токен протух, провайдер поміняв формат відповіді, або сам
> лічильник відмовив. У старому інструменті за замовчуванням ран у такому разі просто йшов далі, і так
> було кілька діб поспіль: у логах писало «нечитабельно», і ніхто не зупинявся. Що має статися, коли
> число прочитати не вдалося?»

Options to read out, and stop:
- «зупинятись і чекати, поки прочитається»
- «йти далі й тільки записати, що не видно»
- «для софт стопу йти далі, для хардстопу зупинятись»

**Why this is the hole.** There is no row in the transcript about a failed reading. Every mode at [171]
assumes the number is there. Meanwhile, VERIFIED in the shipped source today:

- `plugins/harness/bin/harness-limits.sh:52-56` refuses to call a response readable unless it contains
  a `.limits` array. **The live endpoint has no `.limits`** — today's top-level keys are `five_hour`,
  `seven_day`, twenty-odd named buckets and `extra_usage`. So `snapshot` returns `UNREADABLE` on every
  call and `verdict` returns `VERDICT=UNKNOWN SESSION=? WEEKLY=?`.
- `templates/user-config.example.json:34-35` ships `"on_unreadable": "proceed"` — `wait_clear` logs
  "proceeding per config" and returns 0 immediately. The pause never happens.
- `harness-run.sh:240-241` then parses the hard stop out of the literal string `SESSION=?` with
  `sed -n 's/.*SESSION=\([0-9]*\).*/\1/p'`, which yields empty, so the guard fails and **the hard stop
  can never fire** while the parser is broken.

`FIELD-NOTES.md` §11.7 records the operational consequence (VERIFIED): `weekly_all=unreadable%`
recurring — *"six consecutive ticks on `2026-09-06T03:01-03:19Z`, more at 08:36 and 22:48-23:03, single
ticks on the 9th, 10th and 11th"* — plus *"The usage endpoint returned `authentication_error` for an
extended stretch, blinding every cap read, with nobody re-authenticating."* The limit machinery ran for
days on a real project, enforcing nothing, reporting nothing wrong.

**And the worst version is not "unreadable" — it is "readable and wrong."** Z.ai began returning
`CREDIT_LIMIT` rows where consumers expected `TOKENS_LIMIT`, and the tools rendered **0% used** rather
than "unreadable" (CLAIMED, three mutually corroborating reports). 0% reads as plenty of room.

**Two things worth catching if he volunteers them.** Whether "cannot read" is one state or several —
throttled, token expired, format changed, network — because they want opposite responses; and whether
the answer differs per stop class. The third option above is exactly that split.

**What the answer changes.** The default in the config template, and whether a hard stop is allowed to
degrade silently into no stop. This one default is the single largest reliability decision in the
cluster: it is what turned every other mechanism here into decoration for several days of a real run.
Challenge A6, research §5.3.

---

## Q8 — What must the check before the run actually prove? · **definition · major**

> «Ти сказав: перед запуском треба переконатися, що зміна акаунтів працює. Я подивився твою машину.
> Два з п'яти твоїх профілів — це насправді один і той самий акаунт Клода, з одним спільним лімітом.
> І ще: в тебе є налаштування, де Клод Код ходить не в Клода, а на іншу адресу — і тоді лічильник,
> який читає оркестратор, показує акаунт, який нічого не витрачає. Що саме ця перевірка має довести?»

Options to read out, and stop:
- «що перемикання спрацювало — роль пішла на той акаунт, який я вказав»
- «плюс що ролі, які я розніс по акаунтах, справді сидять на різних лімітах»
- «плюс що ліміт, який оркестратор читає, це той самий ліміт, який витрачає сесія»

**Why this is the hole.** His decision, at **[199]** (VERIFIED):

> «Наприклад, в моєму випадку це перемикач профілів, який використовує різні профілі.»
> «перед запуском потрібно переконатися, що це працює, щоби це не було проблемою для користувача»

The unit he configures is a **profile**. The unit that holds quota is an **account**. Nothing he
decided requires the two to be checked against each other, and nothing guarantees they coincide.
**VERIFIED** by reading `oauthAccount` out of each profile's `.claude.json`: two config dirs can share
one account and quota pool — two keychain entries, two OAuth tokens, one weekly window — so per-dir
usage reads can double-count, and a role split across those two is not a split.
Note this **contradicts `C4-capacity-research.md` §3.1**, which treats each profile as a separate
account and builds the per-role allowlist story on that.

The second half is the base URL. **VERIFIED**: `~/.config/claude-mimo/env` sets
`ANTHROPIC_BASE_URL=https://token-plan-sgp.xiaomimimo.com/anthropic`, and `harness-limits.sh`'s
`token()` reads the Anthropic OAuth token from the keychain and never consults `ANTHROPIC_BASE_URL`. A
session pointed elsewhere spends someone else's quota while the gate meters an Anthropic account the
session never touches — a number that cannot rise, so the gate stays green all night by construction.
`FIELD-NOTES.md` §11.7 records the real version (VERIFIED): *"my limits position was measuring the wrong
account"*, with the building account reading 94% weekly on the wrong pool.

**What the answer changes.** Whether the preflight is one probe (identity) or three (identity, distinct
quota pools, meter-matches-spender); and whether a "provider" in the config is keyed by binary, by
credential, or by *(binary, address, credential)*. Challenge A1 and A11, research §5.1 and §6 item 12.

---

## Q9 — «Хард» means two different things · **collision · major**

> «Слово «хард» у тебе означає дві різні речі. У правилах лімітів хардстоп — це зупинити роботу. А у
> файлі, де ти перепризначаєш акаунти на ролі, «хард» — це зробити перепризначення прямо зараз, не
> чекаючи наступного тікета. Якщо ти о четвертій ранку впишеш у той файл «хард» — що має статися?»

Options to read out, and stop:
- «зупинити ран»
- «перекинути ролі на новий акаунт прямо зараз — поточні сесії вбити й підняти заново»
- «це мають бути два різні слова, і я їх зараз назву»

**Why this is the hole.** Two decisions, seven rows apart in the same session, use the same words for
different actions (both VERIFIED):

> «якщо в моменті щось змінюється, то вказується, який тип цієї зміни. Тобто, чи це софт, що це треба
> буде наступні завдання перенести, чи це хард, чи це треба прямо вже зробити і зупинити» —
> **[195]/[196]**
> «то це означає хардстоп, що потрібно зупинити завдання прямо вже та й все» — **[171]**

In [195]/[196] «зупинити» is the *means* — you stop the session in order to move it. In [171] it is the
*end*. An implementer reading a config field named `hard` cannot tell which; a user writing `hard` in
the file cannot tell what he is asking for. He edits the file from his phone at 04:10 to move the
executors off an account he needs for a morning demo, writes `hard`, and implementer A halts the run
while implementer B kills three executors mid-turn. Neither is wrong by his words.

**A consequence worth mentioning only if he asks why it matters.** `FIELD-NOTES.md` §12.4 (VERIFIED):
*"A weekly-usage figure can move without any usage changing. When the supervisor was repointed from one
account to another mid-run, the weekly reading fell from 26% to 6% from the account switch alone."* So
whatever «хард» turns out to mean, the limit history is discontinuous across it — a soft stop about to
fire silently un-fires.

**What the answer changes.** The config vocabulary, and whether an immediate reassignment is allowed to
kill sessions mid-turn — which is Q4's stop semantics arriving through a different door.
Challenge A10.

---

## Q10 — A role-locked account is exhausted at 01:00 and resets on Sunday · **gap · major**

> «Ти сказав, що акаунт можна прив'язати до однієї ролі — наприклад, тільки під оркестратора. Тепер
> уяви: о першій ночі саме цей акаунт упирається в тижневий ліміт, а скидається він аж у неділю.
> Решта акаунтів вільні, але їм заборонено бути оркестратором. Що має статися?»

Options to read out, and stop:
- «чекати до скидання, скільки б це не тривало»
- «порушити прив'язку і взяти вільний акаунт»
- «почекати якийсь час, а потім розбудити мене — і я скажу, скільки саме чекати»

**Why this is the hole.** Two of his own decisions, put together, produce an undefined stall (both
VERIFIED):

> «Наприклад, що може використовувати тільки для оркестратора, щось може використовуватись тільки для
> екзек'ютора … І це важливий дуже нюанс» — **[270]**
> «потрібно чекати, коли воно розіб'ється, для того, коли воно розблокується, щоби продовжити всю
> роботу» — **[007]**

[270] constrains *which* account may serve a role. [007]/[171] say an exhausted role waits for its
reset. Neither says whether the restriction is a hard constraint or a preference, and neither bounds
the wait. VERIFIED today: `seven_day.resets_at` is a **weekly boundary** (`2026-09-20T11:59:59Z` for
his active pool), so a mid-week crossing is a multi-day wait, not a five-hour one. The machine idles
with most of its capacity unusable and nobody is told, because waiting is the designed behaviour and
there is no event for "waiting longer than makes sense".

**And from outside, a waiting run and a dead run look identical.** `FIELD-NOTES.md` §11.6 records a real
five-day, 1085-repetition loop over exactly that ambiguity (VERIFIED): *"`STOPPED` present with no
`run.complete` — treating as an accidental teardown, not a finish"*. There is also a collision with his
single-orchestrator invariant at **[300]** — «не може бути такого, що вже якісь існуючі оркестратор і
спускається наступний» — since nothing says whether a *waiting* orchestrator counts as alive.

**What the answer changes.** Whether role restrictions are hard or soft; whether there is a maximum
wait after which waiting becomes escalating; and whether a stalled run emits anything at all. Without a
number here, the honest implementation is an unbounded idle. Challenge A9, research §4.1 context.

---

## Held back, with reasons

Recorded so the gaps are visible rather than implied. None of these is cosmetic; each lost to something
above on "does the answer change what gets built this round".

- **Codex's `primary` field does not keep its meaning.** VERIFIED across **7,379** `rate_limits` records
  on his disk: on `plus`, `primary` is the 5h window in 471 records and the weekly window in 1,098; on
  his current `prolite` plan, 3,030 of 3,030 records report weekly only with `secondary: null`; and the
  same window is reported as both 299 and 300 minutes. So a threshold configured against "the
  five-hour window" can stop matching anything, silently, with no error and no log line. **Fold this
  into Q7's answer** — if he says "a reading that does not parse must be loud", a threshold that names a
  window nobody reports is the same class of event. If he says "proceed", ask it separately next round.
  Also VERIFIED: `rate_limit_reached_type` and `spend_control_reached` are `null` in 7,379 of 7,379
  records — neither in-band signal's non-null shape has ever been observed on this machine.
- **A standby account's token goes stale during the very wait [171] designs for.** VERIFIED: a listed profile can have
  a keychain entry that yields no readable token at all, and another can return
  `authentication_error` from the usage endpoint because its token is stale — tokens refresh only when
  Claude Code actually runs under that profile. So the 21:50 preflight is green and the 11:00 resume
  finds an expired credential with nobody awake. Held back because Q8's third option and Q10's third
  option together largely determine the answer; it is a one-line confirm next round.
- **The quota endpoint is itself rate-limited, and his global `CLAUDE.md` tells every session to poll
  it.** VERIFIED: a single call returned `{"error":{"type":"rate_limit_error"}}` on this machine today,
  roughly a minute after another agent's probe sequence; a cooldown probe every 15s was still limited at
  t+167s. Whether the throttle is per-token or per-IP is **UNKNOWN**. This is an engineering constraint
  on the reader (single-flight, cache, poll the active account only), not a question for him — unless
  Q3 keeps the full machinery, in which case "who is allowed to poll" becomes a real question.
- **Which "Kimi" and which "Gemini", and whether Qwen stays on the list.** Kimi's quota path is UNKNOWN;
  Gemini's consumer path ended 2026-06-18 and the replacement has no documented quota surface; Qwen's
  free tier closed 2026-04-15. Q5 and Q6 already force the policy for all three without naming them, and
  a per-platform shopping list is a poor use of voice minutes. Ask in writing.
- **The intermediate stop mode's mechanism.** He left it open himself with «Не знаю» [171], and the
  research finding is that it is gated by whether a platform can reopen a *specific* session later —
  `--resume` / `resume` / `--session` / `--resume [chatId]` all VERIFIED — which is a session-runtime
  question, not a quota one. Q1 reads the mode back to him; the mechanism belongs to C7.
