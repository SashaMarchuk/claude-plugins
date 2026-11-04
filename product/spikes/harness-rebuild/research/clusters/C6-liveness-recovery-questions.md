# C6 — Liveness, stalls, orchestrator death, resumable state · round-2 questions

Cluster: **C6-liveness-recovery** · Items: **R1-09, R1-10, R1-06 part 3, Д10**
Date: **2026-09-19** · Round: **2** · Format: **voice, Ukrainian**
Read first: `C6-liveness-recovery-research.md`, then `C6-liveness-recovery-challenge.md`

Ten questions. Six blockers, four majors. Every one is a hole the challenge pass found in a decision he
already made, or a mechanism he started naming and was talked over. None re-asks a settled item, and
none carries a recommendation — where real alternatives exist they are read out as options and the
question stops there.

Evidence marks: **VERIFIED** (read in the transcript, the field notes, the plugin source, or measured
on this machine by the C6 research), **CLAIMED** (a third party asserts it), **INFERRED**.

**Ratification context, carried from the research and not re-litigated.** Only two sentences in this
cluster were ever confirmed by him: the launch-journal / prove-dead / no-two-orchestrators statement
(«Та, правильно» **[304]**) and role-restricted accounts («Підтверджую» **[279]**). R1-09, the health
check, the recovery sources, the per-platform recovery and Д10 were all closed over half-finished
sentences. Several questions below bite precisely because the unratified parts were never read back.

**Reading order matters.** Q1 and Q2 are definitions. Both make later questions cheaper, and Q2 in
particular may half-answer Q10 by itself. Ask them first, in this order.

**Vocabulary check.** Every question below uses only words he used himself: оркестратор, ран, тікет,
дошка, компакт, ліміт, провайдер, акаунт, підписка, сесія, журнал, статус-файли, транскрипт, скіл,
екзек'ютор/виконавець, фоллбек. «Журнал» is safe because the interviewer used «журнал запусків» at
[302]–[303] and he confirmed it at [304]. No coined terms, no English.

---

## Q1 — What is "one run"? · **definition · blocker**

> «Ти сказав: два оркестратори одного рану одночасно — це не окей, і це треба відслідковувати й не
> дозволяти. Щоб це заборонити, машина має знати, що таке "один ран". Скажи: якщо я ввечері запустив
> ран на цьому проєкті, а зранку, думаючи що він помер, запускаю другий — це той самий ран, який
> треба заборонити, чи це два різні рани, і їм можна працювати поруч?»

Options to read out, and stop:
- «один проєкт — один ран, другий запуск просто не стартує»
- «ран — це окрема штука зі своїм ім'ям, на одному проєкті їх може бути кілька»
- «кілька можна, але не на одну й ту саму дошку»

**Why this is the hole.** The invariant is ratified and scoped to one run:

> «Дуже важливо, що не може бути такого, що вже якісь існуючі оркестратор і спускається наступний,
> тому що тоді це буде просто нескінченний цикл оркестраторів… якщо раптом одночасно два якісь
> оркестратори працюють, то це не окей» **[300]** · «Це треба відслідковувати і не дозволяти»
> **[301]** · «Та, правильно» **[304]** (VERIFIED — transcript lines 396–400)

Nothing anywhere in round 1 forbids two *runs*. And two runs are not exotic: R1-05 **[160]** lets him
set concurrency, Д4 **[433]** gives each task its own worktree, R1-04 **[129]/[149]** points the run at
a shared board the orchestrator writes statuses and comments to. Two runs obeying the invariant
perfectly still read the same ready tickets and merge to the same trunk.

Measured consequence when two writers hit one allocator in this exact system — FIELD-NOTES §12.6
(VERIFIED, read in the file): *"two concurrent `add` calls could land on the same id and both be told
they succeeded"*, and J-T169-01 measured **two files under one id in five rounds out of five**, with a
twenty-way add producing twenty files under three ids. §4.4 adds: *"An external party moving a
checked-out branch corrupts the tree silently."* A second run is an external party by definition.

**What the answer changes.** The key the single-instance lock is taken on, and therefore whether the
invariant is implementable at all. Keyed on the run directory, two runs coexist and corrupt each
other. Keyed on the project path, a second run is refused — and nothing he said says it may be. This
is the first line of code in the cluster. Challenge A12.

---

## Q2 — «Стан останнього запису» — which record? · **definition · blocker**

> «Ти назвав спосіб перевірити, чи оркестратор живий — дивитися на стан останнього запису, коли
> востаннє щось було. Тебе тоді перебили, і фраза не дописана. Скажи, який саме запис ти мав на
> увазі: останній запис самого оркестратора про себе — тобто він раз на скільки-то секунд каже "я
> живий"; чи останній слід у самій роботі — зрушений тікет, коміт, змінений файл?»

Options to read out, and stop:
- «запис оркестратора про себе»
- «слід у самій роботі»
- «обидва, і вони означають різне»

**Why this is the hole.** This is the **only concrete liveness mechanism proposed anywhere in the
interview**, and `ANALYSIS-01.md` dropped it (VERIFIED — the research states this and I confirmed the
rows). He was cut off mid-sentence three times:

> «Можливо, якісь варіанти, щоби перевіряти **стан останнього запису** тощо, так далі. Тобто»
> **[249]** / «Коли» **[251]** / «останній раз... щось...» **[253]**
> (VERIFIED — transcript lines 337, 339, 341; the interviewer's own question was talking over him on
> lines 338, 340, 342)

The two readings are different products. "The orchestrator says it is alive" is a breathing signal: it
stays fresh through a rate-limit wait, through a useless loop, through the 85-minute incident. "The
last trace in the work" is a progress signal: it goes stale during a legitimately long turn — the C6
research measured **0 bytes of transcript growth over 3 s while a subagent did heavy work**, and a
validator session's measured range is **15 to 40 minutes** (VERIFIED, FIELD-NOTES §6). Conflating them
is exactly the mistake that produced the nudges in Q6.

**What the answer changes.** What the health check reads, what the lease file contains, and whether
"stale" means "dead" or "stuck". If he answers «обидва», Q10's aim is half-decided for free. Research
Q-C6-10.

---

## Q3 — The check runs on a separate account and is blind to the orchestrator's account · **feasibility · blocker**

> «Ти хочеш, щоб раз у N годин прокидався окремий агент на іншій підписці й перевіряв, чи оркестратор
> живий. Я перевірив на твоїй машині: список сесій у Клод Коді показує тільки сесії свого акаунта —
> два профілі бачать зовсім різні списки й один одного не бачать взагалі. Тобто агент з іншого
> акаунта питає "чи живий оркестратор", отримує "не знайдено" і читає це як "мертвий". Що він має
> робити?»

Options to read out, and stop:
- «питати платформу від імені того самого акаунта, на якому працює оркестратор»
- «не питати платформу взагалі, а дивитися тільки те, що видно з машини незалежно від акаунта»
- «питати обома способами, але "не знайдено" ніколи не означає "мертвий"»

**Why this is the hole.** The account difference is not an accident of implementation — it is the
requirement:

> «запускати якогось агента раз в N годин на **якійсь іншій підписці** або з різними варіантами, які
> підписки можуть включитися» **[246]** (VERIFIED — transcript line 334)

> «може використовувати **тільки для оркестратора**, щось може використовуватись тільки для
> екзек'ютора… І це важливий дуже нюанс» **[270]** (VERIFIED — line 358; ratified «Підтверджую» [279])

And the checker has authority to start the run without him:

> «має бути щось, що може допомогти запустити ран і продовжити роботу **без участі в налаштуваннях
> користувача**» **[266]** (VERIFIED — line 354)

**VERIFIED on this machine by the C6 research:** `claude agents --json` run under two
`CLAUDE_CONFIG_DIR` profiles within seconds of each other returned **completely disjoint interactive
rosters** — four sessions each, neither seeing the other's. A probe under the wrong account does not
return "alive elsewhere"; it returns nothing.

The 03:40 shape: the orchestrator is alive on account A, paused in a rate-limit wait — his own named
death mode is the adjacent one, «кредит закінчився, тижневий ліміт» **[266]**. The check wakes on
account B, sees nothing, declares dead, starts a replacement per [266]. At 05:10 the original's window
resets and it resumes mid-turn. Two orchestrators of one run, which is the state he called «не окей».
The design mandates the exact condition that blinds the probe. Challenge A1.

**What the answer changes.** Whether the journal must record each actor's account and environment so a
recoverer can replay the probe *as that actor*, or whether the whole liveness path is built from
account-blind OS facts only. Two different mechanisms; one of them ships the forbidden state.

---

## Q4 — The third verdict: the check could not look · **gap · blocker**

> «Ти сказав і підтвердив: перш ніж запускати новий оркестратор, треба переконатися, що старий не
> працює. Але є третій випадок, якого в правилі немає — перевірка не змогла відповісти. Токен протух,
> ліміт віддав помилку, для тієї платформи перевірки взагалі немає. Минулого разу читання лімітів було
> сліпим більше години поспіль і ніхто цього не помітив. Що робити в цьому випадку?»

Options to read out, and stop:
- «чекати, поки не з'ясується — хай ран стоїть»
- «почекати якийсь час, і якщо так і не з'ясувалось — вважати мертвим і запускати новий» (і тоді
  скажи, скільки чекати)
- «вважати мертвим одразу»

**Why this is the hole.** The ratified rule has exactly two buckets:

> «Якщо, наприклад, запустився оркестратор, або щось запустилось, але воно не спрацювало,
> **переконуєш що воно не спрацювало, а після того запускаєш новий**» **[300]** (VERIFIED)

*Convinced it is dead* and *not convinced*. "The probe errored" is not an edge case here, it is the
recorded norm:

- **VERIFIED today by the C6 research:** the Anthropic OAuth usage endpoint returned **HTTP 429** to a
  well-formed authenticated request.
- FIELD-NOTES §11.7 (VERIFIED, read in the file): `weekly_all=unreadable%` recurred across many
  separate days — six consecutive ticks on `2026-09-06T03:01–03:19Z`, more at 08:36 and 22:48–23:03,
  single ticks on the 9th, 10th and 11th.
- FIELD-NOTES §11.7: the usage endpoint returned `authentication_error` from `2026-09-02T13:52Z` to
  `15:14Z` — **one hour twenty-two minutes**, *"blinding every cap read, with nobody re-authenticating."*
- FIELD-NOTES §11.3: a detector probe (BSD `find -newermt`, stderr to `/dev/null`) *"could never
  succeed and never complained"* and *"would have declared every healthy session idle for ever."*

Both implementers are faithful to his words and both ship a disaster. Error→dead spawns a second
orchestrator onto a live run. Error→not-convinced means the orchestrator actually died at 02:50 and he
opens the laptop at 08:00 to five hours of nothing, which fails R1-01 outright.

**Sharpening, if he asks which way he already leaned.** «не окей» [300] is an absolute; «ран
зупинився» [246] is a problem to be solved. Read strictly, the absolute outranks the problem. Do not
volunteer this — say it only if he asks what his own answers imply.

**What the answer changes.** Whether the system has a third state at all, and if so the timeout that
converts it. Without a ruling, nothing in the recovery path can be written. Challenge A2.

---

## Q5 — The planned replacement is not a death, and the invariant only covers deaths · **collision · blocker**

> «Ти сказав дві речі, і вони стикаються. Перша: коли оркестратор упирається в поріг контексту, можна
> замість компакту запускати повністю новий оркестратор, і має бути механізм, який гарантовано це
> робить. Друга: два оркестратори одного рану одночасно — не окей. Але старий оркестратор не може
> вийти посеред кроку — минулого разу компакт на місці займав близько семи хвилин. Хто кого чекає?»

Options to read out, and stop:
- «новий стартує тільки після того, як старий справді вийшов»
- «новий стартує одразу, старий дороблює свій крок і мовчки виходить»
- «старий сам запускає нового і, поки не запустив, не виходить»

**Why this is the hole.** Both decisions are his, and the second one's vocabulary is entirely about
failure — «якщо… воно не спрацювало», «переконуєш що воно не спрацювало». A context handover is not a
failure: the outgoing orchestrator is healthy, busy, and about to be replaced by a process it launches
itself.

> «це може налаштовуватись, таким чином, що оркестратор можна **як компактити, так і запускати
> повністю новий оркестратор**, що також може бути окей… І якщо, наприклад, оркестратор наблизився до
> того числа, ну або, чи перейшов це число, то **повинен бути механізм, який гарантовано робить цю
> дію**» **[204]** (VERIFIED — transcript line 288)

The "guaranteed" clause pushes an implementer toward *spawn the successor first, confirm later*, which
is the two-orchestrator state by construction. Measured: J-WATCH-01 timed compact-in-place at
**67% → 0% in about seven minutes** (VERIFIED, FIELD-NOTES §10.2), and FIELD-NOTES §1.1/§1.2 record
that **a session cannot compact itself** and `/compact` lands only when the target has no shell
running — so the predecessor cannot exit on command mid-turn.

A quieter second form, and the one that already bit him: FIELD-NOTES §1.6 — `q-screen-orchestrator`
*"stayed registered and idle for one day and four hours"* because *"the orchestrator that spawned it
had moved on"*, and its terminal title read `harness-question-q-screen-orchestrator`, which **the
product owner himself read as a second orchestrator** (VERIFIED, read in the file). The invariant has
to say what counts as "an orchestrator" before it can forbid two.

**What the answer changes.** Whether the handover is fenced, whether the successor inherits the lock or
takes a fresh claim, and what the predecessor does if it wakes to find its claim superseded. Challenge A3.

---

## Q6 — On how many signals may the orchestrator act? · **gap · blocker**

> «Ти сказав: оркестратор сам дивиться, який у сесій прогрес і що вони зробили, і відповідно діє.
> Проблема в тому, що минулого разу кожна проста ознака хоч раз збрехала. Сесія, яка три години підряд
> запускала пусту команду, виглядала найзайнятішою за всіх. А здорові сесії, які просто довго думали,
> виглядали зависшими — їх перебили тридцять три рази за півтори доби. Скільки ознак має зійтися,
> перш ніж оркестратор щось зробить із сесією?»

Options to read out, and stop:
- «однієї досить, він сам вирішує»
- «треба, щоб дві незалежні ознаки сказали те саме»
- «дві незалежні, і та сама картина двічі поспіль»

**Why this is the hole.** The decision is his and it was **never ratified** — [238] «Гаразд,
зафіксував» landed on a half-finished sentence:

> «Агент сам повинен це вирішувати, тобто він дивиться, перевіряє ті сесії, які він запустив, **які в
> них прогрес, що вони там зробили**, тощо так далі. І відповідно до цього діє» **[231]**
> (VERIFIED — transcript line 317; his continuation at [234]/[236] «Тобто оркестратор, для цього є
> щоби… вирішувати ці питання» / «та врегульовувати», closed at [238])

«Прогрес» is not an observable. Every cheap observable on this machine has a measured false-positive
mode in his own run (all VERIFIED, read in FIELD-NOTES):

| Signal | What his own logs recorded |
|---|---|
| heartbeat age | §1.5: a session heartbeats *between* turns; the watch nudged six sessions and *"every one of those sessions was healthy at the time."* §12.3 counts **33 nudges** between `2026-09-11T22:49Z` and `2026-09-13T06:29Z`, across phases 10 to 22. |
| shell / child count | §2.2: *"A shell that cannot exit reads as work"* — `until grep … sleep 5` against a file that finished writing **forty-five minutes earlier**; *"no check would ever have called that session parked."* |
| tool-call cadence | §3.1: **3,466 of 3,626 Bash calls in `w-phase-19` were the literal command `echo idle`**, ~1,400/hour for 3h15m, 445k tokens of context burned, zero progress. Maximally busy, entirely useless. |
| screen text | §11.6: the watch matched a usage-cap banner **inside the orchestrator's own wrapped prose**, pressed Escape and sent `continue` every ~60 s for **85 minutes**; *"Nothing internal detected it"*; line 5620 of that log reads `NO ONE IS BEING TOLD`. |
| git activity | Ruled inadmissible by his own R1-13 **[344]**: «може таке бути, що десь не буде тестів, і це також окей. Тобто не роби обмеження…» — and the tool is not only for code, so there may be no repo at all. |

Two implementers reading [231]: one polls transcript mtime on a 10-minute threshold and reproduces the
33 nudges; one reads the platform roster and never touches a `busy` session, and never catches a wedge.
Both are faithful. There is no third reading available from his words.

**What the answer changes.** Whether the build contains a stall threshold at all, and whether a verdict
needs corroboration. This is the difference between a system that interrupts healthy work all night and
one that cannot notice a wedge. Challenge A4.

---

## Q7 — The step that was half done · **gap · major**

> «Ти підтвердив: перезапускаємо оркестратор, а не повторюємо роботу. Але крок, який був у процесі в
> момент падіння, не "зроблений" і не "не початий". Новий оркестратор бачить у записах "почав зливати"
> і не бачить "злив". Що він має з таким кроком робити?»

Options to read out, and stop:
- «піти й подивитися в самому проєкті, чи це вже сталося, і не повторювати»
- «просто повторити — повтор безпечніший за пропуск»
- «позначити тікет заблокованим і лишити мені на ранок»

**Why this is the hole.** The ratified rule partitions *done* from *not started* and says nothing about
the window a crash lands in by definition:

> «**Заново запустити оркестратора**» **[300]**, in answer to «"запускати спочатку" означає створити
> нову сесію оркестратора чи заново виконати всю роботу прогону?» **[298]** (VERIFIED — lines 394–396)

And his recovery default reads a record written either before or after the side effect, with no way to
tell which:

> «Якщо, наприклад, **по дефолту, то це дивитися в статус файли**» **[293]** (VERIFIED — line 389)

The window is open in production today — FIELD-NOTES §11.7 records a three-step regression in the
supervisor's pause path ending in issue **`#82`, open**: *"the `STOP` write is still unconditional on
the marker write succeeding, so a failed marker write leaves an unattributed `STOP` on disk"*
(VERIFIED). Three 04:00 shapes, and the successor cannot tell them apart: a merge that already
succeeded (harmless to repeat), a PR that already opened (repeating opens a **second** PR, and R1-12
**[331]** wants PR stacking, so nothing flags it), and a worker that was already spawned (repeating
puts a **second worker in the same worktree**, which is FIELD-NOTES §11.8's stale-worktree incident
with two authors).

**The collision to name in one clause if he asks.** He also said, about the work: «в нас в реєстрі має
записуватись **кожен стан, його виконання**… для того, щоби було відновити процес і продовжити, **навіть
руками**» **[171]**. "Every state" and "reference only" [189] are in tension exactly here — the chosen
process's records tell you which plan was running, never which of the orchestrator's own side effects
had already fired. Challenge A6.

**What the answer changes.** Whether every externally visible action must carry a key a replayer can
search for, or whether steps are simply assumed safe to repeat.

---

## Q8 — What makes someone else's records insufficient? · **definition · major**

> «Ти сказав: якщо людина користується гет шит дан, оркестратору, можливо, нічого свого писати не
> треба, досить посилання на його записи — і сам додав, що можеш помилятись. Ось що знайшлося: гет шит
> дан справді пише свій стан, але той самий файл на твоєму проєкті позначений як такий, що ведеться
> руками, а минулого разу злиття відрапортувало успіх і не злило нічого. Що для тебе робить чужі
> записи недостатніми?»

Options to read out, and stop:
- «досить посилання, і це нормально»
- «до кожного посилання оркестратор дописує свій слід — конкретний коміт чи файл, який він бачив»
- «свій слід тільки на те, що оркестратор робить сам — злиття, статус тікета, закриття сесії»

**Why this is the hole, and it is the one place he asked to be checked.**

> «якщо, наприклад, людина налаштувала, що вона користується get shit done, то оркестратору, я думаю,
> що можливо йому **нічого не треба окремо записувати, а лише записувати оце референс**… **Я можу
> помилятись**, але це має бути **дуже простий процес**» **[189]** (VERIFIED)

> «Якщо, наприклад, то облік, який веде… і його **недостатньо**, то ведеться з посиланням, **плюс тої
> дати, якої не вистачає**» **[171]** (VERIFIED — transcript line 320)

**VERIFIED by the C6 research on the real project:** GSD does publish `.planning/STATE.md` with
`current_phase`, `current_plan`, `status`, `stopped_at`, `last_updated` and a `state_head` git SHA — so
a reference really is close to enough. **And the same file, on his own repository, records in its own
`last_activity` that a claim about it being derived was withdrawn and the file declared
hand-maintained.** A reference to a hand-maintained file is a reference to whatever the last agent
asserted. Three measured reasons that is not safe to restart from (all VERIFIED in FIELD-NOTES):
§4.1 *"A merge reported success and did nothing"* — `git checkout master` aborted on a dirty
`.planning/milestone.lock`, which GSD rewrites every phase, so the merge ran on the phase branch
against itself and printed `Already up to date`; §11.4 *"GSD's verify stage was silently skipped for
phases 14 to 18… No automated check caught it"*; §12.7 *"26 refusal events in the audit log that never
occurred."*

Nothing anywhere defines **how the orchestrator decides a record is insufficient** — and he handed that
judgement to a configuring agent asking the user a question the user cannot answer either.

**Note if he pushes back.** Option three is deliberately narrow: it is the orchestrator not lying in
its own journal about its own bookkeeping, not the orchestrator checking someone's work — which R1-13
**[344]** forbids. Say that only if he raises the collision. Challenge A7, research Q-C6-11.

**What the answer changes.** Whether the journal is a pointer file or a pointer plus a witness, and
whether recovery can trust what it reads.

---

## Q9 — After a restart, whose sessions are these? · **collision · major**

> «Ти сказав дві речі. Перша: після перезапуску оркестратор сам розбирається, що робити з виконавцями,
> яких він запустив — зупинити чи дочекатися. Друга: те, що в тій самій папці запустив ти сам, він
> чіпати не має. Але після перезапуску він нічого не пам'ятає, а запис про останню запущену сесію міг
> не встигнути лягти. Він бачить живу сесію в папці рану і не може сказати, чия вона. Що робити з
> такою сесією?»

Options to read out, and stop:
- «не чіпати нічого, чого немає в журналі»
- «вважати своїм усе, що в папці рану»
- «спитати мене і чекати відповіді»

**Why this is the hole.** Both sides are his, and they meet at the worst moment.

> «Та оркестратор сам повинен проаналізувати, що це таке, навіщо, чи це потрібно зупинити, чи це
> потрібно просто почекати, коли воно завершиться… Тобто це вже, він повинен вирішити» **Д10 [497]**
> (VERIFIED — transcript line 601; **unratified** — [500]/[501] put the restatement and the interviewer
> moved to Д11 at [503] with no answer between)

> «якщо, наприклад, **в тій самій папці я паралельно працюю над чимось, це не запускав оркестратор, це
> роблю я, він цього не має зупиняти**… я **не хочу якихось детерміністського варіанту** для цього,
> тому що він буде дуже складний оверінжиринг, але дуже якісь **простий та надійний** варіант»
> **[370]** (VERIFIED — line 470)

> «оркестратор має бути якось **селфевернес**, що він, до чого він може змінювати… він би не мав
> зупиняти якісь там тести, які **не він запускав**» **[366]** (VERIFIED — line 466)

«Селфевернес» is memory, and by [300] a restarted orchestrator is a new session with none. Its only
route to "these are mine" is the journal — the same journal that is missing exactly the entries written
closest to the crash (Q7). And it cannot be complete even in principle for some session kinds:
**VERIFIED by the C6 research**, `claude agents --json` *background* rows carry `id` and `state` and
**no pid at all**. Meanwhile [370] forbids the one heuristic that would fill the gap, and FIELD-NOTES
§11.8 shows he is right to: *"`pkill -f 'playwright test'` killed an unrelated lane, because every
lane's own prompt text contains that literal string."*

A third state nobody named: FIELD-NOTES §1.6 — a finished session *"stayed registered and idle for one
day and four hours"*. Even a perfect journal yields a list mixing alive, finished and idle with no field
that separates them. Challenge A8.

**What the answer changes.** The adoption rule after every restart, and whether stopping a process the
orchestrator did not personally start sits inside default authority at 04:00 or routes to the Д6
questions channel.

---

## Q10 — The laptop sleeps · **gap · major**

> «Коли макбук засинає, оркестратор і всі його сесії завмирають, але не вмирають, а той агент, що
> перевіряє раз у N годин, узагалі не спрацьовує, бо машина спить. Минулий ран так і закінчився —
> останній запис у логу: "оркестратор мертвий, живих сесій немає, згортаємось, мак міг заснути". Що
> має робити ран?»

Options to read out, and stop:
- «не давати машині заснути, поки ран живий»
- «спати разом з машиною, а після пробудження не рахувати час сну за простій»

**Why this is the hole.** His liveness mechanism [249] is a clock comparison, and sleep breaks clock
comparisons in both directions at the same instant: on wake the orchestrator process is **alive with
the same pid**, its last write is hours old, and its children are frozen mid-turn with no error
anywhere. Every staleness reading says dead; the process object says alive; both are correct.

**VERIFIED, FIELD-NOTES §10.1** — the previous run's ending, verbatim:
`[2026-09-07T09:08:21Z] watch: orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may
sleep)`, with `DEAD-RUN` and `STOPPED` written at that timestamp. **VERIFIED** that the current plugin
already made this choice by accident and nobody ever decided it: FIELD-NOTES §1 records that
`harness-run.sh` *"owns the watch loop and `caffeinate`"* and that the watch loop *"runs under `nohup`,
keeps its pid at `state/watch.pid`, and **binds `caffeinate` to itself**"* — so the moment the watch
dies, the Mac is free to sleep, and everything else freezes without dying. `run.caffeinate` `true` is
an inherited config default, not a decision he made.

The 06:20 shape: the N-hour check **did not fire during sleep at all** — a scheduled waker does not run
on a sleeping machine, so the one mechanism meant to catch this is the one mechanism that cannot. It
fires on wake, reads a three-hour-old record, declares dead and spawns. The frozen orchestrator resumes
its turn one minute later. Two orchestrators, and the second one's evidence was **accurate at the moment
it was gathered**.

**Second-order, worth one clause if he asks why it matters for N.** «раз в N годин» presupposes wall
clock. On a laptop that sleeps, "every N hours" is "every N hours the machine happened to be awake" —
an unstated and unmeasurable quantity. Challenge A5.

**What the answer changes.** Whether the run takes over the machine's power state for its whole
duration, and whether a wake event invalidates every liveness verdict taken before it.

---

## Considered and deliberately not asked

Recorded so he can see these were weighed, not missed.

- **Who notices that the health check itself went silent** (challenge A9, **major**). The check is a
  single point of failure protecting a single point of failure, and it fails the same way its subject
  does: its account is his, he works in it by day, and a weekly limit reached at 18:00 silences it —
  silence being indistinguishable from "everything is fine". Documented precedent, VERIFIED:
  FIELD-NOTES §11.6, inside the 85-minute loop, *"the human-notification watchdog had already exited
  ('run finished') and was never restarted"*; §12.3, `context-watch`'s own collector **OOM-killed
  twenty-six or more times in this run**. **Held for round 3 because its answer depends on Q3 and Q4** —
  if he rules that "not found" never means dead and that an unreadable probe means wait, a silent check
  degrades to "the run sits still", which is a decision he will already have made.
- **May the run spend the limit to zero, or must it leave him a reserve** (research Q-C6-4). The
  interviewer **dropped this clause from R1-06 at [169]/[170] and never returned to it** (VERIFIED —
  transcript line 326 asks only the first half). It belongs here because his named orchestrator death
  mode is «кредит закінчився, тижневий ліміт» **[266]**, so the answer decides whether that death is a
  bug or the design working. **Routed to the C4-capacity cluster** rather than asked twice.
- **What the N-hour check is looking for** — a run that *stopped*, versus a run that is *alive and
  producing nothing* (challenge A10). His words aim it at «якщо ран зупинився через помилку» [246],
  while the failures his run actually produced were the 85-minute loop, a 45-minute false-positive
  banner loop on a healthy orchestrator, and 445k tokens of `echo idle` — none of which is "stopped".
  **Folded into Q2:** if he answers that «стан останнього запису» means the last trace in the *work*,
  he has already aimed the check at "is it moving". Re-ask in round 3 only if he answers «запис
  оркестратора про себе».
- **Per-platform recovery config asks him a question he cannot answer** (challenge A11). «для кожної
  платформи можна налаштовувати, як саме буде робитись відновлення» [310] / «може написати свої
  власні скіли» [312] — but **VERIFIED**: of the platforms he named at [041]/[255], only `claude` and
  `codex` are installed on this machine; `gemini`, `glm`, `qwen`, `crush`, `opencode`, `amp`, `aider`,
  `goose`, `droid` are all absent. He has never run one. His own standing instruction at [182]/[183]
  already routes this: «якщо раптом десь немає лімітів, або десь інші ліміти… це треба буде **винести
  окремими питаннями потім**». Asking now would ask him to invent an answer.
- **Cross-provider recovery is always a cold start** (research Q-C6-9). VERIFIED: neither
  `claude --resume` nor `codex resume` crosses platforms or accounts, so a recovery on a different
  provider **never** inherits the dead orchestrator's memory. This is a fact to tell him, not a question
  to ask him — it constrains what the position file must contain, and that belongs in the build brief.
- **"He should use a kernel lock / a fencing token / a LaunchAgent."** Answers, not holes. The research
  holds them; the interview does not need them.
- **"The journal will get truncated the way `state/attention.tmp` was."** Real and severe — FIELD-NOTES
  §2.1/§11.3 record that file being `: >`-truncated **every watch cycle all night**, destroying
  everything other processes wrote to it, *"including a measured rebuttal written while the orchestrator
  was weighing killing a 378-test suite at test 240."* But it attacks an implementation choice nobody
  has made yet, not a decision of his. It belongs in the build brief as a hard constraint.
