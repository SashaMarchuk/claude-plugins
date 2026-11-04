# C3 — Work sources, readiness, mid-flight changes · round-2 questions

Cluster: **C3-work-source** · Items: **R1-04, Д2, Д8, Д9**
Date: **2026-09-19** · Round: **2** · Format: **voice, Ukrainian**
Read first: `C3-work-source-research.md`, then `C3-work-source-challenge.md`

Ten questions. Four blockers, six majors. Every one is a hole the challenge pass found in a decision
he already made — none re-asks something he settled, none carries a recommendation. Where real
alternatives exist they are named as options and the question stops there.

Evidence marks: **VERIFIED** (read in the transcript, in the plugin source, or measured on this
machine today), **CLAIMED** (a third party asserts it), **INFERRED**.

**Reading order matters.** Q1 decides where the orchestrator's own writing goes; Q2 decides which
copy of the board is real. Until those two are answered, Q3, Q8 and Q10 have no fixed referent —
there is no way to say what "the ticket changed" even means. Ask them in order.

**Two of the four decisions in this cluster were never confirmed aloud** (VERIFIED,
`research/extract/corrections.md:84,85`): the board-status check ([154]/[155] → the interviewer moved
to Р1-05 at [156]) and the config lifecycle ([134]/[137] → «А повтори, будь ласка, попереднє
питання» [138], and the restatement was never re-put). Q4 and Q7 sit on exactly those two, so
answering them also closes the ratification gap. Nothing here asks him to repeat himself.

---

## Q1 — Where does the orchestrator write, if its own writing is what the watcher sees? · **collision · blocker**

> «Ти хочеш, щоб дошка була помічником оркестратора — щоб він ставив статуси і лишав коментарі. І
> окремо ти хочеш, щоб слідкувач за змінами мовчав, коли нічого не змінилось. Але коментар
> оркестратора — це теж зміна тікета, і слідкувач побачить її як зміну. Куди має писати оркестратор?»

Варіанти, назвати й зупинитися:
- «у сам тікет, як зараз»
- «у сам тікет, але в окремий блок, який слідкувач не читає»
- «в окремий лог рану, а в тікеті лишати тільки статус»

**Why this is the hole.** Two of his own sentences meet on the same bytes.

> «це має бути якась дошка, яка буде помічником для цього оркестратора, щоби ставити статуси таскам,
> залишати якісь коментарі, тощо, і так далі» **[149]** (VERIFIED — transcript line 233)

> «в нормальному рані, якщо нічого не змінилось, то цей агент просто, типу, нічого назад не поверне»
> **[466]** (VERIFIED — line 570)

VERIFIED by measurement in the research pass, live against `cli/cli`: `issue.updated_at` equals the
**last comment's** `created_at` on open issues — a comment alone moves it, and the whole-issue ETag
moves with it, because the payload embeds `updated_at` and the comment count.

VERIFIED worse on the local backend, read in `plugins/harness/bin/harness-tickets.sh:143` today:

```bash
l_comment() { { printf '\n---\n%s harness log:\n' "$(date -u …)"; cat "${2:?body}"; } >> "$(l_file "${1:?id}")"; … }
```

The comment is **appended to the ticket file itself**, and `body_to_file` (line 50) returns
everything after the frontmatter — the appended log included. So locally the orchestrator's status
note does not merely bump a timestamp; it edits the description. Any hash, diff or cheap model
comparing "the description now" against "the description at claim time" sees a real textual change,
because there was one.

The 02:14 shape: the orchestrator comments, the watcher wakes at 02:15, spends a model call, reports
«змінилось» with a diff consisting of its own log line, and Д9 [482] must then decide whether that
contradicts finished work — writing its decision back to the board at 02:16. VERIFIED that this
topology has already run here: `FIELD-NOTES.md §11.6`, an **85-minute loop nothing internal could
break**, in which a deterministic watch matched a banner inside the orchestrator's own wrapped prose,
acted, changed nothing, and matched again; it ended only on an external `SIGTERM`.

There is a second, quieter cost in the shipped code (challenge A12, VERIFIED, line 106):
`gh_comment` uses `--edit-last`, so the board holds **one** comment per ticket — the latest status,
not a trail. If he answers "separate run log", that loses nothing; if he answers "in the ticket", the
trail question becomes real.

**What the answer changes.** Whether "the description" is a defined byte range at all (challenge
A10), whether the Д8 watcher can ever be silent, and whether the readiness floor's own input can be
polluted by the tool's echo — VERIFIED as possible: the floor is three greps over the whole file
(`require_ready_body`, line 27), and the log is inside the file it greps.

---

## Q2 — Under your own worktree default, which copy of the board is the real one? · **collision · blocker**

> «За дефолтом ти хочеш, щоб абсолютно все виконувалось у різних ворктрі. А локальна дошка лежить у
> самому проєкті — тобто в кожному ворктрі своя копія дошки, заморожена на момент, коли його
> нарізали. Яка копія головна, і чи має лінія право писати в дошку зі свого ворктрі?»

Варіанти, назвати й зупинитися:
- «дошка одна, в основній теці; лінія в неї не пише — пише тільки оркестратор»
- «дошка одна, в основній теці; пишуть у неї всі напряму»
- «дошка живе поза проєктом, окремо від коду»

**Why this is the hole.** Both halves are his.

> «локально, тобто в самому проєкту, якась структура … і в тому реєстрі будуть всі завдання»
> **[129]** (VERIFIED — line 213)

> «Дефолтна пропозиція, щоби абсолютно все виконувати в різних ворк трі» **Д4 [433]** (VERIFIED —
> line 537)

VERIFIED on this machine, in his own project: all **327** ticket files are tracked in git
(`git ls-files .harness/tickets | wc -l` → 327, matching `ls | wc -l` → 327), and
`bin/harness-tickets.sh:18` resolves `TDIR="$(hproject_root)/.harness/tickets"` by walking up from
`$PWD` — inside a worktree, that is the **worktree's** copy.

The failure runs both ways at once. 00:10 he adds ticket 328, ready, to the trunk — Д2 says «Він може
абсолютно спокійно підібрати» [422] — and no lane can see it. 01:20 he edits ticket 312, which lane 2
is working; lane 2's watcher hashes its own frozen copy, sees nothing, and stays silent exactly as
[466] requires. The silence is correct behaviour and a wrong answer.

Second-order, VERIFIED: every status write dirties a tracked file inside the worktree, and
`FIELD-NOTES.md §4.1` records a merge that **reported success and did nothing** precisely because
`git checkout` aborts on a modified tracked file — the whole incident was one dirty tracked file.
This design supplies 327 more of them, rewritten on every claim, comment and status change.
Precedent for the forking itself, VERIFIED, `§12.5`: «`QUESTIONS.md` and `JOURNAL.md` forked into a
worktree's own copy», and a real owner-facing question sat there invisibly for an hour.

Related but not the same question: C8 Q7 asks where the *rules* file lives. This one is the work
registry — the thing the run reads to know what to do.

**What the answer changes.** Whether the local backend needs an out-of-tree path, whether lanes get a
write path to the board at all, and whether mid-run intake (Д2) and mid-flight change watching (Д8)
are even reachable on the backend he named first.

---

## Q3 — Who notices that a finished ticket changed? · **gap · blocker**

> «Слідкувач стежить за завданням, поки воно в роботі. Але твоє головне правило про новий тікет — про
> завдання, яке вже виконане і потім змінилось. Якщо після закриття його ніхто не читає, це правило
> не спрацює жодного разу. За чим має стежити оркестратор: тільки за тим, що в роботі; ще й за
> готовим до запуску; чи й за виконаним теж — і якщо за виконаним, то як довго після завершення?»

**Why this is the hole.** Д8 scopes the watcher to the task the orchestrator «бере», «під час цього»:

> «оркестратор бере це завдання і він може слідкувати за змінами в цьому завданні … Він під час
> цього слідкує за цим» **[466]** (VERIFIED)

Д9's *preferred* branch is the one where the task is already finished:

> «якщо вже завдання виконане, але воно змінене, то оркестратор задати перевагу тому, щоб зробити
> новий тікет» **[482]** (VERIFIED — line 586, confirmed «Так» [486])

Nothing in the cluster says who notices. The decision he stated as the default has no trigger.
VERIFIED that the obvious implementation cannot see it: `gh_done()` runs `gh issue close`, and every
poll in the shipped engine filters `--state open` (`gh_list`, `gh_list_v`) — a done ticket is closed
and therefore invisible to the board poll.

22:10 ticket 274 closes. 23:40 he tightens its acceptance criteria and goes to bed believing Д9 will
file a follow-up. 04:00 the run reaches the end of the queue and finishes clean. 09:00: a report that
says everything succeeded, the trunk carrying the old behaviour, and no new ticket.

Widening the watched set is not free, and the cost is platform-shaped. VERIFIED live: ClickUp sends
`cache-control: no-cache, no-store`, no ETag, and 19,580 bytes for four tasks against a 100 req/min
budget — at 327 tickets, watching everything costs four sweeps' worth of budget per tick, for ever.
On GitHub the same widening is nearly free: one GraphQL poll returning 50 label-filtered issues with
`updatedAt`/`lastEditedAt` measured **2 points** of 5,000 per hour (VERIFIED, `scratchpad/poll.graphql`).

**What the answer changes.** The watched set, and therefore the poll cost profile, on every backend.
Three readings of [466] produce three different products. It also decides whether Д9's stated default
branch is implementable at all.

---

## Q4 — A setting is missing at 23:50 and nobody is awake · **default · blocker**

> «Ти сказав: коли людина просто робить ран, система читає налаштування, і якщо чогось немає —
> оркестратор ставить питання, щоб це покрити. І окремо ти сказав, що під час рану оркестратор нічого
> тобі не виводить і нічого в тебе не питає. Уяви: 23:50, ти щойно підключив дошку, запустив ран і
> пішов спати, а одного налаштування бракує. Що він робить?»

Варіанти, назвати й зупинитися:
- «взагалі не стартує ран і каже це одразу, поки я ще за кермом»
- «стартує, але бере тільки ті завдання, для яких цього налаштування не треба»
- «бере власний дефолт, записує рішення і йде далі»

**Why this is the hole.** The two rows are his, and the gap between them is the entire unattended use
case.

> «коли вона робить просто ран, то система починає щитувати чи є якісь налаштування глобальні, або
> на проєкті … Якщо чогось немає, то оркестратор задає ці питання для того, щоби їх покрити»
> **[133]** (VERIFIED — line 217; **unratified**, `corrections.md:84`)

> «Ні, оркестратор не повинен нічого виводити для мене … Йому не треба нічо...ніякого інпуту вив
> водити» **Д11 [508]** (VERIFIED — line 612; his own correction at [511] narrows it to «мінімальну
> кількість аутпуту», not to a question channel)

VERIFIED that nothing in the previous generation rescues a blocked prompt: `FIELD-NOTES.md §11.1` —
«The stale-heartbeat nudge is the only escalation the engine has», with observed peaks before a nudge
fired of **2808 s (47 minutes)** and **44791 s (about 12.4 hours)**, and «Nothing stronger is
triggered at any ceiling». VERIFIED, `§12.1`: a **149-minute stall** because a submit never landed,
and «`send` fails silently above roughly 200 characters» — a config prompt is longer than 200
characters, so even a supervisor trying to answer for him can fail silently.

And the question it would ask at 23:50 is one he cannot answer from the terminal. VERIFIED from his
own live ClickUp list `[AUT] Developmental Tasks`: `review` is typed **`done`**, `ongoing` and
`in progress` are both `custom`, `backlog` is `open` while `to do` is `unstarted`. "Which of your
statuses means in progress?" has no correct answer available without opening the board.

Note: he is not being asked to repeat [133]. The question is what the run does when [133] fires and
Д11 forbids the output.

**What the answer changes.** Whether configuration is a hard precondition of `run` (a preflight that
refuses), a per-ticket filter, or a defaulting engine that must then have a written default for every
setting. These are three different startup paths, and the third one obliges us to design defaults for
everything in this cluster.

---

## Q5 — May the agent write `ready` on a ticket you created? · **collision · major**

> «Ти хочеш структуру, якої тікет має дотримуватись, щоб його взяли. І окремо ти сказав, що агент
> читає новий тікет і, якщо опису достатньо, бере його і імплементує. Питання про право: чи може
> агент сам поставити "ready" тікету, який створив я, — чи він має право тільки написати
> "needs review", а "ready" ставлю тільки я?»

**Why this is the hole.** Two answers put the authority in different places, and neither says which
one binds when they disagree.

> «має бути конкретна структура, якимись або тегами, або що, які потрібно фоловити … це треба буде,
> щоби придумав якусь структуру, і її притримувався» **[146]** (VERIFIED — line 230)

> «можливо, там буде якийсь процес, що я можу створити таску, агент аналізує, і якщо достатньо
> опису, то він його бере і імплементує. Якщо недостатньо, то він пише, що, типу, needs review»
> **Д2 [422]** (VERIFIED — line 524; «Точно не знаю» twice in the same answer, and the restatement at
> [424] explicitly left sufficiency **open**)

If a model decides sufficiency, the structure is advisory. If the structure decides, the model's
judgement is decoration.

The expensive direction: 02:00, ticket 331 reads in full «Fix the footer — it looks wrong on mobile».
No outcome, no scope, no criteria. A cheap model judges the intent obvious, a lane spends four hours
and a chunk of the weekly window, and at 09:00 there is nothing to compare the result against — Д9
cannot help either, because no criterion was contradicted: none existed.

The inverse is equally live. VERIFIED, `FIELD-NOTES.md §11.4`: GSD's verify stage was **silently
skipped for phases 14 to 18**, each verification file self-attributing `verified_by: the lane that
built the phase`, because an orchestrator generalised a narrow warning into a broad rule — «No
automated check caught it; manual review did.» A model-judged gate is the same class of actor.

Measured counterweight, and the reason this question is about *authority* rather than about the
structure itself: a purely structural, grep-sized floor held across **327 tickets, 288 of them done,
15 of 15 `ready` tickets passing, zero violations** (VERIFIED, research §2.1, audited today with the
engine's own three greps).

**What the answer changes.** Whether the sufficiency judge is a promoter or only a demoter — and
therefore whether a human's ticket can enter the run without a human ever having marked it ready.

---

## Q6 — Two of your own sentences about mid-flight changes were talked over · **gap · major**

> «У відповіді про зміни в тікеті ти двічі почав говорити, і тебе обидва рази перебили: "Тобто, може
> бути момент" і "з ... підстави чогось в моменті". Це ніде не записане. Що ти тоді хотів сказати —
> за якої умови оркестратор має реагувати на зміну прямо в моменті, а не чекати?»

**Why this is the hole.** VERIFIED in the transcript, lines 572 and 575:

> «Тобто, може бути момент» **[468]**

> «з ... підстави чогось в моменті» **[471]**

Both are recorded as lost in `corrections.md` (rows [471] and section E, VERIFIED): «A Д8 qualifier
about acting on a change in-flight, lost under the repeated question», and neither appears in
ANALYSIS-01.

His confirmation of Д8 is also narrower than it reads:

> «На те, що ти перше сказав, так, я підтверджую, потім після того ти повторив питання п'ять чи
> шість разів, і це не окей.» **[475]** (VERIFIED — line 579)

That confirms the **first** restatement ([469]) only — watch the active ticket, configurable model,
silent when unchanged, report what changed when it did. The in-the-moment qualifier was never inside
anything he confirmed.

This is the one question in the set that recovers his own words rather than probing a design. It is
cheap and it may collapse Q3 or change Д9's branch conditions outright.

**What the answer changes.** Whether a detected change acts immediately or waits for a boundary —
which is the difference between Д9's «прямо зараз змінити стратегію» and «дочекатися кінця, і
все-таки через новий тікет» [482] being chosen by a rule instead of by the orchestrator's mood.

---

## Q7 — The board is missing a status the process needs · **gap · major**

> «Людина підключає дошку, а на ній немає статусу, який потрібен налаштованому процесу. Що робить
> оркестратор: відмовляється підключати дошку і каже, чого бракує; сам створює потрібні статуси на
> дошці; чи працює з тим, що є, і каже, якої ролі в нього немає? На спільній дошці створення статусів
> — це зміна для всіх, хто там працює.»

**Why this is the hole.** He required the check and never named the failure verb:

> «треба перевіряти, чи дошка готова до цього, тому що в дошці мають бути якісь певні мінімальний
> набір статусів, які вона може використовувати … Яка саме структура, це вже людина може
> перевизначити, переконфігурувати в середині плагіну» **[153]** (VERIFIED — line 237; **unratified**,
> `corrections.md:85` — the restatement at [154]/[155] was followed by the interviewer moving to
> Р1-05 at [156])

VERIFIED that the shipped engine already picked one of the three answers silently:
`harness-tickets.sh:73-85`, `gh_labels_bootstrap` runs `gh label create … --force` for five labels.
On a shared repository, or a shared ClickUp list, that is an externally visible schema change to
someone else's board, made at 04:00 with nobody awake. On ClickUp a status set is a list-level
property: changing it changes it for every task in the list.

That collides with his own principle:

> «він би не мав зупиняти якісь там тести, які не він запускав» **[366]** / «це не запускав
> оркестратор, це роблю я, він цього не має зупиняти» **[370]** (VERIFIED — line 470)

And "proceed with a partial mapping" has its own measured trap: on his live list `review` is typed
`done` (VERIFIED). A lane finishes at 03:00, the process says «move to review for a human», the board
shows `review`, the orchestrator reads type `done` and marks the work complete. The run reports
thirteen tickets done, one of which nobody ever reviewed.

Answering this also ratifies [153], which was never confirmed aloud.

**What the answer changes.** Whether connecting a board is a read-only conversation, a write to
someone else's workspace, or a degraded mode — and whether the status mapping has to be confirmed by
the person rather than derived, since status **names** carry no semantics on either platform and even
ClickUp's `type` is set by whoever built the list.

---

## Q8 — ClickUp cannot answer «чи змінилось» cheaply, and GitHub can · **feasibility · major**

> «Ти сам просив казати, коли щось не сходиться з дійсністю на конкретній платформі. Перевірив
> сьогодні: у ClickUp немає дешевого способу спитати "чи змінилось" — щоб побачити зміну опису, треба
> щоразу тягнути завдання цілком, а ліміт там сто запитів на хвилину. Те, що точно каже, що змінився
> саме опис, — це вебхук, а ноутбук його не приймає. На GitHub це безкоштовно. Що робимо з ClickUp?»

Варіанти, назвати й зупинитися:
- «платимо цю ціну, стежимо так само»
- «стежимо на ClickUp рідше, ніж на GitHub»
- «ClickUp підтримуємо для читання і статусів, але без стеження за змінами, і кажемо це вголос»

**Why this is the hole.** He named ClickUp himself, in the same sentence as GitHub:

> «Другий варіант - це через підключену якусь дошку. Наприклад, GitHub Issues, або, ClickUp, або
> будь-яка інша тула, і треба просто переконатися, що є доступ до цього ресурсу. Та й все.»
> **[129]** (VERIFIED — line 213)

And he issued the standing instruction this question exists to satisfy:

> «Тут ще, ти коли будеш це аналізувати, я про це не говорю, і я ну все вірю, але воно може не
> сходитися з дійсністю.» **I1 [182]/[183]** (VERIFIED, `corrections.md`)

Measured live today against his own workspace `<workspace-id>` (VERIFIED): `GET /api/v2/list/{id}/task`
returns `cache-control: no-cache, no-store`, **no `etag`, no `last-modified`**,
`x-ratelimit-limit: 100` per minute, 19,580 bytes for four tasks. The task object's date keys are
`date_created`, `date_updated`, `date_closed`, `date_done` — **no description-change field**. Whether
a ClickUp comment moves `date_updated` is **UNVERIFIED** (no commented task was found in the 100
scanned), so it must be assumed to move it.

GitHub, VERIFIED the same day: `If-None-Match` → `304` consumed **zero** of the 5,000/hour core
budget across five repeats, and `lastEditedAt` exists in the live GraphQL schema, distinct from
`updatedAt` — observed ten days apart on `cli/cli#14188` — moving only on a body edit.
`userContentEdits[].diff` even returns the full previous body, so the prior text costs nothing to
keep. CLAIMED (ClickUp docs): the only precise ClickUp signal is the webhook `history_items` entry
with `"field": "content"` — and neither platform's webhook can reach a laptop with no public ingress,
which is also why «нічого надприроднього не потрібно вигадувати» [171] argues against building one.

**What the answer changes.** Whether the product promises one behaviour on every board or an honest
per-backend capability table — and, if the promise is uniform, how much of the 100 req/min budget the
Д8 watcher is allowed to spend before the board stops being usable for anything else.

---

## Q9 — Ninety ready tickets land at 23:00 · **default · major**

> «Минулого разу черга за день виросла з 236 до 327 тікетів, і зупинив це ти сам, руками, вдень. А
> тепер те саме вночі: об 11-й вечора на дошку падає 90 тікетів, усі позначені готовими, бо
> зроблені з одного шаблону. Оркестратор бере все підряд, поки не впреться в ліміт, чи в рані має
> бути стеля — скільки завдань він має право почати за один ран?»

**Why this is the hole.** The behaviour is confirmed and is not being contested:

> «Він може абсолютно спокійно підібрати … точно може бути таке, що під час цього я докину завдання,
> його опишу підходить для AI, і AI бере це завдання, і виконує» **Д2 [422]** (VERIFIED)

The hole is that it has no upper bound, and the only recorded instance ended with a human
intervening. VERIFIED, `FIELD-NOTES.md §10.1`: «Mid-run the product owner set a soft pause at 11:15
after the ticket queue grew from **236 to 327 in a day** (`state/SOFT-PAUSE.md`).»

The limit rules do not cover this, by his own design — they pause, they do not prioritise:

> «якщо … виглядає так, що завдання впирається в те, що впереться в ліміти, то це окей» **[171]**
> (VERIFIED — line 255)

A weekly window spent on the thinnest sixty tickets is spent; the stop only decides when the next
chunk is spent. And Д11 closes the escape hatch: «якщо я хочу отримати статус виконання, то я можу
запустити окремий термінал» [508] — the growth signal that made him intervene last time is available
only if he goes looking, at a time when by design he is asleep.

Unbounded pickup may genuinely be what he wants. Right now it is the default by omission rather than
by decision.

**What the answer changes.** Whether the scheduler has an intake counter at all, whether the ceiling
is per run or per hour, and whether queue growth becomes a reported number in the status pull he
described at [508].

---

## Q10 — May the orchestrator take a ticket it wrote itself, in the same run? · **gap · major**

> «Коли завдання змінилось, оркестратор сам створює новий тікет. Чи має він право взяти цей свій же
> тікет у роботу в тому самому рані — чи такий тікет чекає, поки ти зранку на нього подивишся?»

**Why this is the hole.** Two confirmed answers close a loop between them.

> «оркестратор, скоріш за все, зробить просто нове завдання, для того, щоби внести ці зміни»
> **Д9 [482]** (VERIFIED, confirmed «Так» [486])

> «Він може абсолютно спокійно підібрати» **Д2 [422]** (VERIFIED, confirmed [426])

A Д9 ticket has to be `ready` to ever run; Д2 says anything that becomes ready during the run is
picked up during the run. So the orchestrator can file work for itself, claim it, and — if its own
watcher misreads the next change (Q1) — file more.

That this is a real failure mode and not a debating point is VERIFIED three times in the previous
run: the 85-minute Escape/continue loop nothing internal broke (`§11.6`); a dead run flagging the
same condition every three minutes **for about five days, 1085 times, unresolved** (`§11.6`); and an
unwedge process polling «run is stopped — holding» every 180 s for 32 minutes while doing nothing
(`§11.6`). The misreading half is VERIFIED too — `§12.2`: a status-line regex that missed `Opus 4.8`,
a merge-equivalence gate that diffed **554 unrelated files**, and a self-patch that reported
`SYNTAX OK` while its `sed` anchor never matched.

A second question rides on the same answer and is deliberately not asked aloud this round: whether a
follow-up may itself produce a follow-up, and how deep that may go. If he answers «чекає до ранку»,
the chain question disappears entirely.

**What the answer changes.** Whether machine-authored tickets are a separate class with their own
eligibility rule, and whether the intake counter from Q9 counts them.

---

## Considered and not asked this round

Recorded so the list reads as filtered rather than merely generated.

- **«Першим ділом рекомендувати GitHub Issues»** — not asked. It is hedged («і **напевно** в цьому
  перевага» [129]) and `corrections.md:56` already files it as a hedged first recommendation, not a
  decision. There is nothing settled there to hole.
- **«Конкретно поки тільки два режими»** — not asked. He scoped it explicitly and temporarily.
  Attacking a stated scope is not a question.
- **What "переконатися, що є доступ" checks** (read / comment / status write / create) — dropped
  after testing it. The concrete failure is real (a read-only token passes the 23:00 connect check,
  then 403s on a status write at 03:00, leaving the board claiming every finished ticket is still
  ready, and a morning run re-claims done work), but the answer is predictable — "check everything
  the run will need" — so it changes little. The genuinely open half is Q8, on a board he named.
- **Which readiness headings to use** (`## Outcome` / `## Scope` / `## Acceptance criteria`, anchored
  checklist items, a `[NEEDS CLARIFICATION]` blocker) — not asked as a question. He handed the
  structure forward himself («щоби придумав якусь структуру» [145]/[146]), so proposing one is the
  deliverable, not the interview. Research §5.1 holds it, grounded in the 327-ticket measurement. The
  part that is genuinely his to decide — who may bypass it — is Q5.
- **The atomic claim** (`mkdir` locally, `refs/heads/claim/<id>` on GitHub) — not asked. It is a
  measured implementation defect (27 winners out of 50 for the shipped read-then-write shape; the
  id-allocator fix present only in the installed cache copy, md5 `915c2cd4…` still in the source
  repo), and his single-orchestrator rule [300]/[301] already addresses the design level. It belongs
  in a build decision, not in his voice session.
- **Whether a dead run's `in-progress` tickets are releasable in the morning** — held back. The
  ticket-state half is real (`stale_report` defaults to **7 days**, VERIFIED at line 184, and derives
  idleness from `updatedAt`/mtime, which the orchestrator's own comments bump), but C6 Q9 already
  asks him the session-ownership version of the same morning, and two questions about the same 09:00
  would burn voice time. Q1's answer decides most of it: if status notes stop touching the ticket,
  idleness becomes measurable again.
