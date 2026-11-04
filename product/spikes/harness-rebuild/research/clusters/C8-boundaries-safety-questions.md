# C8 — Blast radius, the red-line file, end-of-run cleanup · round-2 questions

Cluster: **C8-boundaries-safety** · Items: **R1-15, R1-16, Д3**, owner instruction **I3**
Date: **2026-09-19** · Round: **2** · Format: **voice, Ukrainian**
Read first: `C8-boundaries-safety-research.md`, then `C8-boundaries-safety-challenge.md`

Ten questions. Five blockers, five majors. Every one is a hole the challenge pass found in a decision
he already made or in a sentence he left unfinished — none re-asks a settled question, and none
carries a recommendation. Where real alternatives exist they are read out as options and the question
stops there.

Evidence marks: **VERIFIED** (read in the transcript, the field notes, the plugin source, or executed
on this machine today), **CLAIMED** (a third party asserts it), **INFERRED**.

**Reading order matters.** Q1 is the crux the owner himself commissioned at [378]. Q10 only exists if
Q1 is answered one way — ask it immediately after Q1 if he takes the OS boundary, and skip it
otherwise. Q2 and Q3 are cheap and sharpen everything below them; ask them early.

**A standing note for whoever runs the interview.** R1-15 was never ratified. The interviewer
restated it at [358]/[359] and moved to R1-16 at [360] with nothing from the owner in between; his own
last words on the item were a question back — «Але, так, це максимум... Чи це є відповідно до твоєго
питання» [357] — which the interviewer answered for itself («Так, це відповідає на питання» [358]).
`extract/corrections.md:72` calls it "the weakest-grounded answer in the interview". The only
«Підтверджую» in this whole cluster is [383], and it confirms commissioning this analysis, not the
rule. So Q1 and Q2 are not challenges to a settled position; they are the confirmation that never
happened.

---

## Q1 — Is a boundary the operating system checks the same "детерміністський варіант" you refused? · **collision · blocker**

> «Ти сказав, що не хочеш детерміністського варіанту, бо це оверінжиринг. Але те, що тобі тоді
> описали — це окреме середовище, контейнер. А ти сам перед тим сказав інше: щоб в оркестраторі був
> прописаний шлях, до чого він має доступ. Є спосіб зробити рівно це — щоб цей список шляхів
> перевіряла сама операційна система, а не модель. Один рядок у налаштуваннях, ставити на мак нічого
> не треба, сесія лишається звичайною сесією у твоєму терміналі. Це для тебе той самий оверінжиринг,
> чи це і є той простий надійний варіант, про який ти казав?»

Options to read out, and stop:
- «той самий оверінжиринг — лишаємось на правилах, написаних текстом»
- «ні, це нормально — хай межу тримає операційна система»

**Why this is the hole.** He refused one thing and proposed another, and they are not the same thing.
What he refused was described to him as a *separate environment*:

> «чи потрібне окреме середовище, з якого він узагалі не має до неї доступу» **[364]/[365]**
> (VERIFIED — interviewer's words, not his)

> «я не хочу якихось детерміністського варіанту для цього, тому що він буде дуже складний
> оверінжир... оверінжиринг, але дуже якісь простий та надійний варіант для цього має бути прописаний
> в плагіні» **[370]** (VERIFIED)

What he proposed, two rows earlier, was a path list:

> «має гендлитися таким чином, що в оркестратори **прописаний шлях, до чого він має доступ**»
> **[366]** (VERIFIED)

Nobody ever offered him the middle rung. VERIFIED, executed on this machine today under his own
default permission mode (`bypassPermissions`), with `sandbox.enabled: true`: a write to a neighbouring
project returned `operation not permitted` and the file was untouched; `kill -TERM` against a process
the session did not start returned `operation not permitted` and the process survived; `docker ps`
failed on the daemon socket. No prompt, no model cooperation. That is his own [366] sentence, enforced
by the kernel instead of by prose. Research §3.1, §5 fork, §7 Q1.

The interviewer's restatement — «без складного механізму технічної ізоляції» [372]/[376] — was never
confirmed either; he talked underneath it and redirected the item to this analysis (VERIFIED,
`extract/corrections.md:96`).

**What the answer changes.** Everything else in the cluster. Options B and D in the research cost
nothing either way; C, E and F all live or die here. If he says "overengineering", the build ships
prose plus an ownership journal and the record will show he was told what that is worth. If he says
"fine", Q10 becomes mandatory in the same session.

---

## Q2 — «Але, так, це максимум» — a ceiling on the plugin, or a ceiling on you? · **ratify · blocker**

> «Ти сказав про той один текстовий файл: "Але, так, це максимум". Це читається двома способами, і
> вони дають різні інструменти. Перший: плагін не має права робити нічого більшого за цей файл.
> Другий: один файл — це максимум, який ти сам готовий вести руками, а те, що плагін робить сам, без
> твоєї участі, під цю стелю не підпадає. Яке з двох ти мав на увазі?»

Options to read out, and stop:
- «стеля на плагін — більше нічого не будувати»
- «стеля на мене — плагін хай робить сам, скільки треба, аби я вів один файл»

**Why this is the hole.** The clause is load-bearing and ambiguous. Read in place, the subject of the
whole passage is the human's own effort:

> «якщо людині потрібно якісь додаткові різні обмеження, то вона це може робити, **власноруч
> налаштовуючи своє середовище** … Достатньо лише одного файлу, який може доповнюватись, текстописний
> … **Але, так, це максимум**» **[357]** (VERIFIED)

`extract/by-item.md` (R1-15 row 5) records that `ANALYSIS-01.md` dropped the ceiling entirely
(VERIFIED). The research and the challenge both read it as reading 1. Challenge A12 is the whole
attack: this single unconfirmed clause is currently the binding constraint on the tool's entire safety
design, and he was never asked which reading he meant.

**What the answer changes.** Whether options C, E and F in the research are permitted to exist at all.
Reading 1 forbids them; reading 2 leaves them on the table and makes Q1 a technical choice rather than
a licence question. It costs twenty seconds and it decides what may be built.

---

## Q3 — What flag should the plugin pass when you have configured nothing? · **default · blocker**

> «Ти сказав, що технічні обмеження середовища людина за потреби налаштовує сама. Але є одна річ, яку
> налаштовуєш не ти: щоразу, коли плагін піднімає сесію, він сам передає їй прапорець, який вимикає
> всі запити на дозвіл. Це і дефолт, і те, що він ставить, коли в налаштуваннях щось незрозуміле.
> Тобто найнебезпечніший варіант обрано за тебе, і ти цього не бачиш. Що плагін має ставити тут, коли
> ти не налаштував нічого?»

Options to read out, and stop:
- «лишити як є — усі дозволи вимкнені»
- «дозволи лишаються увімкненими, а на запити відповідає оркестратор — так, як ми вже домовились у Р1-11»
- «дефолт залежить від ролі: оркестратору одне, виконавцям інше»

**Why this is the hole.** The decision assumes the plugin abstains. It does not.

> «технічні обмеження середовища користувач за потреби налаштовує сам» **[358]** (VERIFIED —
> interviewer's restatement of [357])

VERIFIED, `plugins/harness/bin/harness-spawn.sh:32-39`, read today:

```sh
perm_flag() {
  case "$(cfg '.session.permissions' 'bypass')" in
    bypass) echo "--dangerously-skip-permissions" ;;
    ...
    *) echo "--dangerously-skip-permissions" ;;
```

The default is `bypass` and the fallback for an unrecognised value is also
`--dangerously-skip-permissions`. Additionally VERIFIED: his `~/.claude/settings.json` sets
`"permissions": {"defaultMode": "bypassPermissions"}` and `~/.codex/config.toml:7` sets
`sandbox_mode = "danger-full-access"`. For R1-15 to be true as stated he would have to know all three
of those facts; nothing surfaces any of them. Challenge A4.

The reason it matters is not theoretical. VERIFIED, `FIELD-NOTES.md §11.5`: his default Docker stack
was destroyed by `docker compose down -v` with no `COMPOSE_PROJECT_NAME` exported — and "a session had
refused that exact action as owner-only two minutes earlier". Two sessions, same command, two minutes
apart, with the prose rule in force: one obeyed, one did not. The file regulates the model's judgment;
this flag regulates whether judgment is consulted at all.

The second option is not invented — it is his own R1-11 decision, confirmed at [328]: «оркестратор
може робити інтерактивність з сесіями … якщо він раптом використовує ask user question, то оркестратор
може відповідати на ці питання» **[324]** (VERIFIED).

**What the answer changes.** One line in the spawn path, and the entire posture of every session the
tool ever starts. It is also the cheapest place where "the user configures it himself" can be made
true instead of nominal.

---

## Q4 — What may a run do about what the previous run left behind? · **gap · blocker**

> «Два твої правила разом дають дірку. Зупиняти треба тільки те, що ран сам підняв. І не чіпати те,
> чого він не запускав. Але минулий ран помер уночі й не зупинив нічого — після нього залишилось
> близько ста п'ятдесяти докерівських томів. Наступного ранку новий ран їх не піднімав, отже за
> твоїми правилами чіпати не може, а порти в нього вже зайняті, і розібратися може тільки людина,
> заради сну якої все це й робиться. Що новий ран має право зробити зі слідами попереднього рану
> цього ж інструменту?»

Options to read out, and stop:
- «нічого — тільки сказати мені й чекати»
- «прибрати сам, якщо це сліди цього ж інструменту, записані в журналі запусків»
- «прибрати, але спершу розбудити мене»

**Why this is the hole.** Two of his decisions read together define a set nothing may ever clean.

> «якщо він це сам підняв, то він це повинен і зупинити … щоби не залишати хвостів, і не засоряти
> систему» **Д3 [430]** (VERIFIED)

> «він би не мав зупиняти якісь там тести, які не він запускав» **R1-16 [366]** (VERIFIED)

VERIFIED, `FIELD-NOTES.md §10.1`: run `20260831-184751` ended with `watch: orchestrator dead + no live
sessions for 3 ticks — tearing down (Mac may sleep)`, leaving `DEAD-RUN` and `STOPPED` on disk.
VERIFIED, `§11.11`: "About 150 orphaned Docker volume pairs left by a dead prior run." This is not a
hypothetical; it is the observed output of exactly this hole, and it compounds with every crashed run.
Challenge A1.

The undefined word is «своє». Two implementers will read it as "started by this run" and "started by
this tool, ever", and produce opposite behaviour on run 2.

**What the answer changes.** Whether the run journal is per-run or per-tool, whether a startup sweep
exists at all, and whether the first thing that happens at 22:30 is cleanup or a blocked queue.

---

## Q5 — How should a session be marked so the orchestrator can stop only its own? · **feasibility · blocker**

> «Щоб зупиняти тільки своє, оркестратор має чимось позначати кожну сесію, яку підняв. Зараз сесії
> піднімаються через айтерм, тому оркестратор їм не батько: він знає тільки номер термінала і номер
> процесу, а обидва ці номери система з часом віддає комусь іншому. Саме тому минулого разу дійшло до
> пошуку за текстом, і воно вбило чужу лінію. Чи можна змінити спосіб запуску сесій так, щоб у кожної
> був свій стійкий ідентифікатор?»

Options to read out, and stop:
- «так, піднімати сесії в іншому менеджері терміналів, де номер не перевикористовується (наприклад tmux)»
- «лишити айтерм, але хай кожна сесія сама пише файл зі своїм номером, і оркестратор вірить тільки цьому файлу»
- «лишити як є — я готовий жити з ризиком»

**Why this is the hole.** Д3 states an intent and names no way to know what is yours.

VERIFIED, `plugins/harness/bin/harness-term.sh:16-110`: sessions are spawned through `osascript` into
iTerm2, so a session is a child of iTerm2, not of the orchestrator — there is no process lineage to
use. VERIFIED, `harness-term.sh:157`: sessions are addressed by tty (`iterm_close() { # <tty> — close
ONE session`). VERIFIED, `harness-run.sh:254`, the source's own comment: `# liveness: the tracked
claude pid (not "any node on the tty" — review MEDIUM)` — the previous generation already discovered
that a tty is not a stable identity, and fixed it in one place only.

VERIFIED, `FIELD-NOTES.md §11.8`: "`pkill -f 'playwright test'` killed an unrelated lane, because
every lane's own prompt text contains that literal string, so `pgrep`/`pkill` over-match sessions
rather than suites." That is the direct consequence of having no identity to address.

The failure this leaves open is R1-16 case 2 committed *by the teardown mechanism itself*: a worker
dies at 01:10 and releases `ttys006`; at 03:00 the owner opens a terminal for his own work and the OS
hands him `ttys006`; at 04:12 teardown walks the registry and closes it. Challenge A3.
(INFERRED, standard POSIX device reuse, not executed here.)

VERIFIED on this machine today: `setsid` does not exist on macOS, but bash `set -m` puts each
background job in its own process group and `kill -TERM -- -<PGID>` terminates that group and nothing
else — which is the exact replacement for `pkill -f`, and which only works for processes the
orchestrator's own shell started, not for terminal-spawned sessions. That is why this is a question
about the spawn mechanism and not about the kill command. Research §3.7.

**What the answer changes.** The spawn path, the run journal's schema, and whether Д3 can be
implemented at all without pattern matching. Note that he confirmed visible terminals are
configurable, not mandatory, at [324]/[328] — so this is not a re-ask of that.

---

## Q6 — Where does the allowed folder come from? · **gap · major**

> «Ти сказав: в оркестраторі прописаний шлях, до чого він має доступ. Але звідки береться сам цей
> шлях — не сказано, і від цього залежить, чи ран узагалі зможе працювати. Уяви: ти запускаєш
> оркестратор із теки плагіна, а тікети — по вебсайту. Одна реалізація візьме теку, з якої ти
> запустив — і тоді кожне завдання впаде на першому ж редагуванні, о пів на одинадцяту, і ніч піде в
> нікуди. Інша візьме теку проєкту з тікета. Третя візьме спільну теку над ними обома — і в межах
> опиняться всі твої проєкти. Звідки цей шлях має братися?»

Options to read out, and stop:
- «з теки проєкту, який вказано в тікеті»
- «з теки, з якої я запустив ран»
- «я називаю її явно на старті рану»

**Why this is the hole.** He named a mechanism and then removed the place where its value is stated:

> «в оркестратори прописаний шлях, до чого він має доступ» **[366]** (VERIFIED)

> «Чи якоїсь конфіг... Я би не сказав, **я би це робив якось абстрактно**» **[373]** (VERIFIED)

A written path of what may be touched is a configuration value. "Abstract" removes the field without
removing the need for one. Д1 [416] defers config precedence to his own marketplace's three-level
rules, which says where a value lives but not what the value is. Challenge A8, with all three
implementations spelled out.

Also undefined and worth catching in his answer if it comes for free: whether the scope is per-run,
per-tikket or per-session, whether a ticket that spans two repositories widens it or is refused, and
whether the run's own state directory is inside or outside.

**What the answer changes.** Whether the first edit of the night succeeds. This is the one hole in the
cluster whose wrong answer costs a whole run rather than causing damage.

---

## Q7 — Where does that one file live, given your own worktree default? · **gap · major**

> «Той один текстовий файл із заборонами — де він має лежати? Якщо в проєкті, то при твоєму ж дефолті
> з ворктрі кожна лінія отримує свою копію, заморожену на момент створення ворктрі. Ти дописуєш
> правило в головну теку, чотири сесії читають свої старі копії і кожна рапортує, що файл прочитано,
> правил стільки-то. Минулого рану так уже сталося з файлом питань — справжнє питання до тебе
> провисіло там годину. Файл має бути один на машину, один на проєкт, чи якось інакше?»

Options to read out, and stop:
- «один на машину, поза проєктами»
- «один на проєкт, але поза ворктрі — і всі ворктрі читають його звідти»
- «в проєкті, як є, і хай кожен ворктрі має свою копію»

**Why this is the hole.** Two of his own decisions collide on the filesystem.

> «Має бути якісь визначене місце … Достатньо лише одного файлу» **R1-15 [357]** (VERIFIED)

> «Дефолтна пропозиція, щоби абсолютно все виконувати в різних ворк трі» **Д4 [433]** (VERIFIED)

VERIFIED, `FIELD-NOTES.md §12.5`: "**`QUESTIONS.md` and `JOURNAL.md` forked into a worktree's own
copy**, and a real owner-facing question sat there invisibly for an hour." The same mechanism applies
to any repo-relative file, and the failure is silent — every lane reports the file read. That is the
exact class `FIELD-NOTES.md §11.4` catalogues: reported success while doing nothing. Challenge A5.

**What the answer changes.** Whether the file is a project artefact or a machine artefact, whether it
is under version control, and whether a per-project file and a per-machine file both exist and have to
merge.

---

## Q8 — Does a rule you add mid-run bind the sessions already running? · **gap · major**

> «Уяви: третя ночі, ти бачиш у статусі, що лінія йде туди, куди не треба, дописуєш заборону у файл і
> лягаєш спати спокійно. Та сесія піднялася об одинадцятій вечора і правила прочитала тоді ж. Питання
> одне: заборона, дописана посеред рану, має діяти на сесії, які вже працюють, чи тільки на ті, що
> піднімуться після неї?»

Options to read out, and stop:
- «тільки на нові сесії»
- «на всі — оркестратор перечитує файл і доносить зміну живим сесіям»
- «на всі, і якщо інакше не виходить — перезапустити сесію»

**Why this is the hole.** R1-15 says the file is read «в обов'язковому порядку» [357] and never says
when. Its natural implementation is injection at spawn, and VERIFIED `FIELD-NOTES.md §8` records the
governing property of spawn-time injection: "A session already booted keeps the account it booted
with; the change reaches the next spawn." (INFERRED that the same holds for prompt text — the
mechanism is identical.)

It collides with two decisions he made later in the same interview: Д7 [455] (the user may change
behaviour during the run and the orchestrator must apply it) and Д12 [520] (the command writes into
the file the orchestrator reads every tick). Challenge A6.

The cost of guessing wrong is asymmetric: he will edit the file at 03:15 *believing* he has stopped
something, and the record will show the rule was in the file before the action.

**What the answer changes.** Re-read cadence, whether the orchestrator can push text into a live
session, and whether "apply a new prohibition" is ever allowed to restart a session mid-task.

---

## Q9 — Which types of restriction should that file have? · **definition · major**

> «Ти сказав, що в тому файлі людина додає обмеження різного типу. Які саме типи — не назвав, а без
> цього все в ньому читається з однаковою вагою. Уяви: поруч стоять "не пушити напряму в головну
> гілку" і "краще не чіпати старі файли". Агент бачить два речення однакової сили, і в автономному
> рані сам вирішує, що тікет просив саме першого. Які типи мають бути?»

Options to read out, and stop:
- «ніколи, без варіантів»
- «тільки з моїм дозволом»
- «попередити і робити далі»

**Why this is the hole.** His own words, dropped by the analysis:

> «Має бути якісь визначене місце, де може людина додавати якісь **різного типу** обмеження»
> **[357]** (VERIFIED)

`extract/by-item.md` (R1-15 row 2) records that `ANALYSIS-01.md` flattened this to "one text file"
(VERIFIED). A flat file of prose has no field that separates an absolute from a preference, and
R1-02/R1-14 grant the autonomous run decision authority over exactly that kind of judgment call.
Challenge A9.

A second failure in the same shape, worth knowing about but not worth a separate question this round:
the file is append-only by design and every incident adds to it. VERIFIED `§3.1` records a lane
spending three quarters of its context window on polling, and VERIFIED `§3.3` records that nothing in
the plugin measures context. An unbounded prohibition list injected into every spawn gets less
attention the longer it gets, and there is no expiry and no measurement. If his answer to the types
question naturally reaches a bound or an expiry, take it; do not prompt for it.

Note for the interviewer, do not read out: his own
`<baseline-marketplace>/docs/config-levels.md` §5 already defines a `never` veto with the needed
semantics — accumulates by union, never disappears silently, warns when it matched nothing (VERIFIED).
If he asks whether something like this exists, that is the honest answer; do not offer it unprompted.

---

## Q10 — Docker: the three-way fork, if the boundary is on · **feasibility · major**

*Ask only if Q1 was answered "хай межу тримає операційна система". Skip entirely otherwise.*

> «Якщо межу тримає операційна система, з докером виходить розвилка, і обійти її не можна — всередині
> такої межі докер недоступний узагалі. З одного боку, та сама команда, що знищила твій стек, просто
> не виконається. З іншого — лінії не піднімуть свої стеки, а ти казав, що для ворктрі має бути
> піднятий стек. Який з трьох варіантів?»

Options to read out, and stop:
- «відкрити докер повністю — і тоді ця межа фактично зникає»
- «вивести докер за межу — вужче, але команда знищення знову можлива»
- «докер тільки оркестратору, виконавцям — ні»

**Why this is the hole.** VERIFIED, executed here today: inside the sandbox `docker ps` fails with
`dial unix …/docker.sock: connect: operation not permitted`. There is no configuration that produces
sandboxed Docker; the official docs state that allowing the socket "effectively grants access to the
host system through the Docker socket". Research §4.2.

And Docker is not optional for him:

> «або що є якісь запущений стек, коротше, оркестратор повинен мати конфігурацію щодо ворк трі»
> **Д4 [433]** (VERIFIED)

Related and VERIFIED in the same test: a sandboxed session could not signal a process **it had itself
started** in an earlier Bash call, because each Bash call is its own sandbox instance. So the boundary
taken alone satisfies R1-16 by breaking Д3's own teardown. The third option above is the only one of
the three that resolves both at once, which is a fact about the options and not a recommendation —
read the three and stop. Research §4.3.

**What the answer changes.** Whether the plugin sets different flags per role (it already does this
for accounts, per R1-07 [276]/[279]), and whether teardown runs inside or outside the boundary.

---

## Deferred — real holes, not asked this round

Recorded so they are not lost, and so the round-2 session stays under an hour.

1. **The file cannot be read at all — refuse to start, or warn and continue?** R1-15 says reading is
   «в обов'язковому порядку» and says nothing about the failure branch. VERIFIED `FIELD-NOTES.md
   §11.9` — "The credential checker silently ignores a bare path argument, so a sweep run without
   `--scan` reads clean over files it never opened" — establishes this codebase's demonstrated house
   style as fail-open. Challenge A5, second half. Cheap; ask it in round 3 or fold it into Q7's answer
   if he volunteers it.
2. **Д3's teardown list starts with «свої якісь там оркестратори» [430], but R1-10 [300] forbids two
   orchestrators at once** («якщо раптом одночасно два якісь оркестратори працюють, то це не окей»,
   confirmed [304]). Either nested orchestrators exist and R1-10 is narrower than its words, or they
   do not and Д3 names a thing that cannot be there. `extract/by-item.md` (Д3 row 2) records that
   `ANALYSIS-01.md` dropped the orchestrator from the teardown list entirely. Challenge A11. This is a
   **definition** question and belongs with the C6 liveness cluster, where R1-10 lives, not here.
3. **Secrets are not a boundary problem and no option in the research covers them.** VERIFIED
   `FIELD-NOTES.md §11.10`: two local role passwords printed in clear text into a session transcript
   by Playwright's own `--trace on`, and "no automated secret scan covers tool output or transcripts";
   a Sentry breadcrumb recorded a Slack webhook secret in a request address. Nothing decided to leak
   anything — a permitted tool, doing its declared job, inside the working directory, wrote a secret
   to a file the run is supposed to write to. No prohibition writable in a text file prevents it.
   Challenge A10. This needs its own item in the round-2 plan, framed as scanning, not as a boundary.
4. **«Якщо є окремо нетворк 3, то він відповідно до них теж не має доступу» [366]** — the
   transcription is corrupted. Most likely "networks" (Docker networks) or "worktrees". The previous
   run's phase-21 validator failed to get a subnet from the shared pool, which makes "networks"
   plausible — but this is a guess and the research refuses to build on it. A one-line **definition**
   question; ask it only if the session has room.
5. **Reads outside the working folder.** VERIFIED here today: `ls /Users/sasha-marchuk/Work` returned
   a listing from inside the boundary. Blocking reads is a separate switch and it will be noisy —
   sessions legitimately read `~/.claude`, `~/.gitconfig`, toolchain caches. Conditional on Q1 and on
   Q10; belongs in round 3.

---

## What is NOT asked, and why

- **Whether the file should exist.** He decided it should, and nothing in the challenge argues against
  it. A1–A12 attack what reads it, when, whether it is one copy, and what it cannot express — never
  its existence.
- **Whether "stop only what you started" is the right rule.** It is the cheapest real improvement
  available and it is the direct fix for both recorded incidents (§11.5's unscoped
  `docker compose down -v`, §11.8's over-matching `pkill -f`). Every question above attacks its
  implementation gaps, not the rule.
- **Whether to scope Docker teardown by project name and to record process groups at spawn.** These
  cost him nothing, contradict nothing he said, and need no decision — they are research Option B,
  entirely inside the plugin. Asking would waste voice time on a question with one answer.
- **Resource contention.** His container was `OOMKilled` by two concurrent validator builds on an 8 GB
  Docker VM (VERIFIED `§5.1`, and "there was no live alert"). No access-control mechanism addresses
  it; the controls are scheduling controls. Out of C8's scope and it must not be sold as covered here
  — it belongs with the capacity cluster.

---

## Source index

**Transcript (VERIFIED):** `round-1/TRANSCRIPT-01.md` rows [276], [279], [300], [304], [324], [328],
[350]–[383], [416], [430], [433], [455], [520].

**Analysis and extracts (VERIFIED):** `round-1/ANALYSIS-01.md` · `research/extract/by-item.md`
(R1-15 rows 2 and 5, R1-16, Д3 row 2, Д4) · `research/extract/corrections.md` §B, §C (lines 72, 96).

**Plugin source, read today (VERIFIED):** `plugins/harness/bin/harness-spawn.sh:32-39` ·
`plugins/harness/bin/harness-term.sh:16-110, 157` · `plugins/harness/bin/harness-run.sh:248-323`.

**Field notes (VERIFIED):** `plugins/harness/docs/FIELD-NOTES.md` §3.1, §3.3, §5.1, §8, §10.1, §10.2,
§11.4, §11.5, §11.8, §11.9, §11.10, §11.11, §12.5.

**Machine state and execution, 2026-09-19 (VERIFIED):** `~/.claude/settings.json`
(`defaultMode: bypassPermissions`, nine guard hooks) · `~/.codex/config.toml:7`
(`sandbox_mode = "danger-full-access"`) · sandbox write/kill/docker/read tests under
`--permission-mode bypassPermissions` · bash `set -m` + `kill -- -PGID` · `setsid` absent on macOS.
All carried from `C8-boundaries-safety-research.md` §3.1, §3.7, §4.2, §4.3, where they were executed.

**Cluster companions:** `C8-boundaries-safety-research.md` (options A–F, §7's ten open questions) ·
`C8-boundaries-safety-challenge.md` (attacks A1–A12).
