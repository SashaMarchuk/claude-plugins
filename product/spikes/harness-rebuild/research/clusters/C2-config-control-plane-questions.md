# C2 — Configuration model, live overrides and the control file · round-2 questions

Cluster: **C2-config-control-plane** · Items: **Д1, Д6, Д7, Д12, R1-07, R1-04**
Date: **2026-09-21** · Round: **2** · Format: **voice, Ukrainian**
Read first: `C2-config-control-plane-research.md`, then `C2-config-control-plane-challenge.md`

Ten questions. Six blockers, four majors. Every one of them is a hole the challenge pass found in a
decision he already made — none re-asks something he settled, and none carries a recommendation. Where
real alternatives exist they are read out as options and the question stops there.

Evidence marks: **VERIFIED** (read in the transcript, the field notes, the plugin source, his
marketplace docs, or measured on this machine), **CLAIMED** (a third party asserts it), **INFERRED**.

**Reading order matters.** Q1 decides whether the control plane is one file or one place. Q3, Q5 and
Q10 all read differently after it. Ask it first.

---

## Q1 — «Єдиний файл» — literally one file, or one place he watches? · **definition · blocker**

> «Ти сказав: єдиний файл, який оркестратор постійно дивиться. У тому самому файлі мають лежати і
> призначення акаунтів, і зміни поведінки, які ти робиш руками, і зупинка, яку пише команда, і
> зупинка, яку пише сам оркестратор, коли добігає ліміт. Уяви: пів на другу ночі, файл у тебе
> відкритий у редакторі, ти в іншому терміналі даєш стоп хард, повертаєшся в редактор, дописуєш рядок
> про акаунт і зберігаєш — зверху свого старого тексту, де зупинки немає. Це буквально один файл, чи
> одне місце, за яким він дивиться?»

Options to read out, and stop:
- «буквально один файл на все»
- «одна тека, і в кожному файлі рівно один, хто в нього пише»
- «конфіг окремо, зупинка окремо — і все»

**Why this is the hole.** Two of his own rows put four writers into one artefact (both VERIFIED):

> «це має бути налаштовано через **єдиний файл**, який оркестратор чи контекст вочер постійно
> дивиться» — **[195]**

> «Це в **той файл**, який оркестратор на постійний основі читає… Коли це команда вводиться, то в
> цьому файлі відповідно конфігурується хард стоп чи софт стоп» — **[520]**

And Д6 puts him personally into the file, live, by hand:

> «щоб, грубо кажучи, **в лайв режимі я міг це прийти і це переглянути**» — **[449]** (VERIFIED)

The previous generation ran exactly this experiment and lost. `FIELD-NOTES.md` §2.1 (VERIFIED):
`state/attention` was rebuilt from scratch every cycle, so *"anything appended to that file by anyone
else is destroyed within one watch interval"* — the context watch wrote corrections there all night and
found out by grepping for a block it had written four minutes earlier and getting nothing back. Cost,
§11.3: **`STALLED` raised against demonstrably healthy sessions eight or more times across about seven
hours**. Against that, his own hand-built questions channel already uses **four files with one writer
each** and works (VERIFIED, `<work-project>/docs/open/{QUESTIONS,ANSWERS,README}.md`: *"It never edits
`ANSWERS.md`"*, append-only, one writer per record).

Note what makes the concrete failure above silent rather than loud: the file's digest **does** change
when he saves his stale buffer, so every change detector fires — it just reports the wrong change.
Challenge A3.

**What the answer changes.** The whole layout of the control plane, whether the stop is a field inside
a config file or an artefact whose existence is the signal, and whether any write needs a lock at all.
`lockf(1)` exists on this machine and `flock(1)` does not (VERIFIED, measured) — but one-writer-per-file
needs neither.

---

## Q2 — «Софт» in that file does two different jobs · **collision · blocker**

> «У цьому файлі слово "софт" робить дві різні речі. Коли ми говорили про ліміти, софт означало: дати
> поточному завданню дійти до кінця, а нових не запускати — тобто ран завершується. А коли ми
> говорили про зміни в цьому файлі, софт означало: перенести це на наступні завдання — тобто ран іде
> далі. Пів на другу ночі ти пишеш у файл, що екзек'ютор переїжджає на другий акаунт, і ставиш
> "софт". Що має статися?»

Options to read out, and stop:
- «ран іде далі, просто наступні завдання беруть новий акаунт»
- «ран доробляє поточне і завершується»
- «це мають бути два різні слова, і я їх зараз назву»

**Why this is the hole.** Same word, same session, two incompatible boundaries (both VERIFIED):

> «чи це софт, що це треба буде **наступні завдання перенести**, чи це хард, чи це треба прямо вже
> зробити і зупинити» — **[195]** (the run carries on)

> «м'яка **дозволяє йому завершитися, але не запускає нових**» — **[176]** (the run drains and ends)

And a third boundary in a fourth place: R1-08's soft is *«Лише поточного кроку»* **[209]**, with the
step itself declared configurable — *«але це можна налаштовувати, людина може сама налаштувати, що це
означає»* [209] (VERIFIED).

**The version that would have reconciled them was never agreed.** `extract/corrections.md` (VERIFIED):
the restatement of the hard/soft rule for limits went [176]/[177] → «Повтори, будь ласка» [178] →
repeated [179]/[180] → [181] moved on. *"The entire hard/soft stop rule for limits (R1-06) is
unratified."*

The concrete cost of guessing: at 01:40 he types `софт` meaning "next tasks go to the other account".
The implementer built [176]. At 01:55 the last running task finishes, nothing starts, the report says
*"soft stop applied at 01:55 as requested"*, and he wakes at 07:00 to 31 untouched tickets and a run
that ended five hours early. Challenge A1.

**Scope note for the interviewer:** the **хард** half of this collision is asked in
`C4-capacity-questions.md` Q9. Do not ask both. If he answers both here, take it and tell C4.

**What the answer changes.** Whether the control file has one type vocabulary or one per domain, and
therefore whether an account move, a limit stop and a compaction can share a field at all.

---

## Q3 — May the orchestrator clear a stop he did not write? · **gap · major**

> «Зупинку в цьому файлі пишете двоє: ти — руками або командою — і сам оркестратор, коли ліміт добіг
> до твого порога. Третя ночі: оркестратор сам себе зупинив по ліміту. Пів на четверту ліміт відпустив
> і він хоче продовжити. Але о третій двадцять ти вписав туди свою зупинку. Чи має він право її зняти,
> якщо не знає, чия вона?»

Options to read out, and stop:
- «мою зупинку може зняти тільки я»
- «нехай знімає будь-яку, якщо ліміт відпустив»
- «його зупинки і мої — це різні речі, вони не мають жити в одному місці»

**Why this is the hole.** [520] says only *«в цьому файлі відповідно конфігурується хард стоп чи софт
стоп»* — no author, no clearing rule. The previous generation has the same design and three logged
incidents from it, `FIELD-NOTES.md` §11.7 (all VERIFIED):

- `#65` — the pause fallback was pinned to a fixed past epoch, so an unreadable quota read **resumed a
  paused run immediately**;
- `#73` — the fix moved the epoch lookup between the two pause writes, so *"a restart landing in that
  window read `STOP` as a manual owner stop and exited instead of resuming"*;
- `#82`, **still open** — *"the `STOP` write is still unconditional on the marker write succeeding, so
  a failed marker write leaves an unattributed `STOP` on disk."*

VERIFIED in this repo: `hlib.sh:77,105` — `hstop_file()` is `<project>/.harness/STOP` and
`stop_requested()` is `[ -f … ]`, a zero-content sentinel with **three** writers (`/harness:stop`, the
limit wind-down at `harness-run.sh:243-244`, and the supervisor's pause path). One five-character
author field is the difference. Challenge A3.

**What the answer changes.** Whether the stop carries who/when/why or is a bare sentinel, and whether
the run can ever auto-resume. It also decides what an unreadable or half-written stop means — the
research's measured position is that a torn read of a JSON control file silently returns **every**
default (§3.5, VERIFIED by running it), so a stop that has to be parsed to be obeyed is a stop that can
be missed.

---

## Q4 — The change he called «дуже важливо» arrives when there is no next task and nothing running · **gap · blocker**

> «Ти сказав — і підкреслив, що це дуже важливо — що якщо ти під час рану захотів, аби оркестратор
> чекав на твої відповіді і не зупиняв ран, то він має це зчитати й прийняти, навіть якщо на старті ти
> обрав інше. Але цей момент настає саме тоді, коли нових завдань уже немає і нічого не виконується:
> ні "наступних завдань", ні "поточної роботи", до яких твої софт і хард чіпляються. Коли оркестратор
> уже вирішує, що ран закінчено — він має ще раз перечитати це налаштування?»

Options to read out, and stop:
- «так, перечитує перед самим завершенням і слухається останнього, що там написано»
- «ні, діє те, що було обрано на старті рану»
- «перечитує, але тільки якщо я явно позначив цю зміну як хард»

**Why this is the hole.** The decision, verbatim (VERIFIED):

> «якщо раптом, я хочу змінити цю поведінку під час цього запуску або просто в якийсь момент я можу це
> зробити також… оркестратор повинен це зчитувати та приймати. **Це також, і це дуже важливо.**» — **[458]**

In English, the rest of the answer: if he wants the orchestrator to wait for his answer instead of stopping the run, that holds even if he chose otherwise at the start or the default says otherwise.

The precondition of Д7 is that only answer-waiting tasks remain. At that instant `софт` (*«наступні
завдання»* [195]) has nothing to apply to, and `хард` (*«прямо вже зробити і зупинити»* [195]) stops
what is already not running. **The one behaviour he marked «дуже важливо» falls between his own two
types.** Challenge A2.

**And Д7 itself was never confirmed.** `extract/corrections.md` (VERIFIED): the restatement at
[460]/[462] was followed by [463] moving to Д8 with no answer. ANALYSIS-01 files it as SETTLED.

**The second-order hole, worth naming only if he asks why it matters:** if the answer is "re-read every
tick", then no run ends deterministically — whether a run that stopped at 02:00 would still be running
at 02:01 depends on a file he may edit at any time, and Д11 (*«оркестратор не повинен нічого виводити
для мене»* [508], VERIFIED) means nothing tells him which branch was taken.

**What the answer changes.** Whether end-of-run is evaluated against the config the run started with or
against the file as it stands, and therefore whether "the run is over" is a decision or a race.

---

## Q5 — A watched file changed and nobody attached a type · **default · blocker**

> «Ти сказав: коли щось змінюється, вказується тип цієї зміни — софт чи хард. Але ті файли з
> налаштуваннями пишеш не тільки ти. У той самий спільний файл пишуть інші твої плагіни, а файли
> всередині проєкту переписує сам гіт, коли лінія робить мердж у своєму ворктрі. Друга ночі: ти в
> іншому терміналі запустив налаштування іншого плагіна, спільний файл змінився — а типу в цій зміні
> немає. Що має зробити оркестратор?»

Options to read out, and stop:
- «нічого — без типу зміна не рахується»
- «вважати софт і застосувати на наступному завданні»
- «вважати хард і зупинити те, що робиться зараз»
- «перестати брати нову роботу і чекати, поки я скажу»

**Why this is the hole.** R1-07's mechanism assumes a human author on every change:

> «якщо в моменті щось змінюється, то **вказується, який тип цієї зміни**» — **[195]** (VERIFIED)

His own marketplace says the opposite about these files — VERIFIED, `config-levels.md`:
*"A general config file is shared on purpose: plugins in this marketplace write it, and so do writers
outside this marketplace that this design knows nothing about."* VERIFIED by grep on this machine:
`~/.claude/shared/identity.json` is read or written by **clickup, g-event, log-time and find-call**,
four plugins live in production; `plugins/clickup/commands/onboard.md:6` states it outright. And the
two project-level files are **tracked**, so `git checkout`, `merge`, `pull` and a branch switch rewrite
them — which is what his own lanes do all night under Д4's worktree default [433].

Measured on this machine (research §3.2, VERIFIED): **rewriting a file with identical content moves its
mtime**, so even a `git checkout` that restores the file byte-for-byte fires the detector he hedged
toward (*«Можливо, там, наприклад, по даті»* [195]). Challenge A5.

**What the answer changes.** Whether the watched set is the shared config files at all or only a
separate control file — and if only the control file, then Д7's *«навіть якщо в мене в дефолтній
налаштуванні інше»* [458] has no mechanism, because the defaults live in the shared files and nobody is
watching them.

---

## Q6 — Does a config file committed in a repository he did not write get obeyed? · **gap · blocker**

> «За правилами твого маркетплейсу файл із налаштуваннями, який лежить усередині проєкту і закомічений
> у репозиторій, теж є одним із рівнів. Для будь-чого, що ти сам не виставив, виграє саме він. Уяви: ти
> клонував чужий репозиторій сьогодні вдень і запустив на ньому ран. У ньому лежить такий файл, і в
> ньому написано: повна автономія, канал питань — ось цей файл, сповіщень не слати. Ти нічого з цього
> не виставляв. Чи має оркестратор це слухати?»

Options to read out, and stop:
- «так, це звичайний рівень, як і всі інші»
- «так, але не для прав і заборон — там виграє моє або дефолт плагіна»
- «ні, чужий репозиторій не налаштовує оркестратора, поки я не дозволив»

**Why this is the hole.** Д1 hands precedence to his marketplace and closes the topic in the same
breath:

> «Це треба робити відповідно до того, які є правила в клад маркетплейсі… там є відповіді на ці
> питання. **Наступне питання**» — **[416]** (VERIFIED; unratified — the restatement at [417]/[418] was
> never answered, `corrections.md`)

I read that marketplace. VERIFIED, `config-levels.md`: slots 1 and 2 are *"committed, tracked by the
project repository"* and they rank below his own four files — correct and safe **for a key he has
set**, and the winning value **for a key he has not**. The document was written for a plugin invoked
for seconds, in his own repositories, by him, at a keyboard (§9: *"On every invocation, the agent
executing a plugin reads the resolved config before that plugin performs any of its own work"*). The
orchestrator runs unattended for thirty-four hours in whatever repository it is pointed at.

**The veto key inverts too.** VERIFIED, same document: `never` accumulates, and *"a committed-project
`never` holds against everything except a tool one of the person's own files names in `use`"* — so a
repository can also **remove** a capability the run needs. That collides with R1-15, where the person is
the one who adds restrictions: *«має бути якісь визначене місце, де може **людина** додавати якісь
різного типу обмеження»* **[357]** (VERIFIED). Challenge A4.

**What the answer changes.** Whether the resolver reads the two project-committed slots at all, and
whether "trusted input" is a property of a file's level or of who wrote it. It is also the one place
where following Д1 literally produces an unattended run configured by a stranger.

---

## Q7 — Where does an answer he gives at midnight land? · **collision · blocker**

> «Ти підтвердив, що налаштування можуть бути типовими, проєктними або перевизначеними для конкретного
> рану. А маркетплейс, на який ти послався, каже прямо: рівнів рівно три, четвертого немає і не робити.
> І ще одне: коли оркестратор о пів на дванадцяту ночі питає тебе про те, чого бракує, твоя відповідь
> за тими ж правилами лягає в твій файл на всю машину — на всі проєкти. Через два тижні ти запускаєш
> ран на клієнтському репозиторії, оркестратор бачить цю відповідь і вже нічого не питає. Куди має
> лягати відповідь, яку ти даєш під час рану?»

Options to read out, and stop:
- «є окремий рівень "цей ран", він вищий за все і зникає разом із раном»
- «лягає в мої налаштування на всю машину і діє далі»
- «під час рану взагалі нічого не записується назавжди»

**Why this is the hole.** Two of his own answers, and one of them is ratified:

> «налаштування можуть бути типовими, проєктними чи **перевизначеними для конкретного запуску**» —
> **[335]**, confirmed *«Так, підтверджую»* **[336]** (VERIFIED)

> «Це треба робити відповідно до того, які є правила в клад маркетплейсі» — **[416]** (VERIFIED)

And that marketplace closes the set — VERIFIED, `config-levels.md`: *"These three levels are the whole
set… A resolver supports no other level"*, and of a level he removed, `OWNER-DECISIONS.md:169`:
*"do not build it, do not reserve a path for it, do not mention it as an option."*

The write destination is the second half, and it is not negotiable in that design either — VERIFIED,
same document: an answer goes to `<config-root>/shared/identity.json` or
`<config-root>/shared/plugins/<plugin>.json`, both **user level**, *"one person's settings on one
machine, and they apply in every project that person opens"*, and *"An answer is always written, and
always into the one file the list above resolves to."* Composed with R1-04 — *«Якщо чогось немає, то
оркестратор задає ці питання»* **[133]**, ratified — a tired yes on a scratch repository at 23:40
becomes the silent default on a client repository two weeks later, and [133] correctly does not ask,
because nothing is missing.

There is a third edge in the same place: that design's safety valve is *"A write into a layer that a
higher layer would shadow is announced first… **Nothing is written until the person chooses**"* — and
at 04:00 nobody chooses. Challenge A11, research Q1.

**What the answer changes.** Whether a run scope exists at all, which is the difference between Д7's
*«навіть якщо на початку я обрав інший варіант»* [458] being expressible and not: if the run's own
choice is written into the same user-level file as the default, then "the live edit beats the run's
choice" and "the live edit beats the default" are edits to the same value and nothing orders them.

---

## Q8 — Moving a role to another account moves his settings with it · **feasibility · major**

> «Коли ти міняєш акаунт через профіль, міняється рівно одна річ — тека, з якої читаються налаштування.
> І це та сама тека, звідки оркестратор бере твої особисті налаштування. Тобто о другій ночі ти
> перекидаєш екзек'ютора на робочий акаунт — і разом з акаунтом він отримує інші налаштування: інший
> поріг, інший канал, інший список заборон, або взагалі порожньо, бо в тому профілі ти оркестратора
> ніколи не налаштовував. Як має бути?»

Options to read out, and stop:
- «налаштування мають лишатися мої, які б акаунти не крутилися»
- «нехай кожен профіль має свої налаштування — це нормально»
- «якщо акаунт тягне за собою інші налаштування — не стартувати і сказати мені про це до запуску»

**Why this is the hole.** His own mechanism, named by him:

> «Наприклад, в моєму випадку це **перемикач профілів**, який використовує різні профілі» — **[199]**
> (VERIFIED; a profile switcher is installed here)

Measured on this machine (VERIFIED):

```
$ <switcher> switch --print-env <profile-A>
export CLAUDE_CONFIG_DIR="<profile-dir>"
```

That is the **only** variable it sets — and `CLAUDE_CONFIG_DIR` is exactly what his marketplace
resolves `<config-root>` from, i.e. **two of the six config slots** (VERIFIED, `config-levels.md`). So
an account move, described in [195] as a routine soft/hard change, silently swaps the person's own
configuration layer. Nothing in the interview and nothing in `config-levels.md` anticipates it.

R1-15 makes it sharper: if the one prohibitions file (*«Достатньо лише одного файлу»* **[357]**,
VERIFIED) lives under the config root, the red lines move with the billing identity; if it lives in the
project, they do not. He never said which. Challenge A6.

**What the answer changes.** Whether the run pins one config root for its whole life independently of
which account a role uses, and whether an account whose profile has no orchestrator config is a startup
refusal or a silent reversion.

---

## Q9 — What does a custom stop degrade to when it cannot be read or run? · **gap · major**

> «Ти сказав: стоп-кастом — це прочитати, що ти там написав, і зробити відповідно, і що там можуть бути
> або текстові правила, або команди. Обидва можуть не спрацювати. Щоб прочитати текстове правило,
> потрібна модель — а зупинка часто спрацьовує саме тоді, коли акаунт вичерпано. А команда може впасти,
> зависнути або вбити чуже. Що має статися, якщо твій кастомний стоп не вдалося ні прочитати, ні
> виконати?»

Options to read out, and stop:
- «тоді просто хардстоп»
- «тоді просто софтстоп»
- «нічого не робити і чекати мене»

**Why this is the hole.** The decision, verbatim, and the «чи» is the problem:

> «думаю що це має бути 3 варіанти, stop-hard, stop-soft, stop-custom що означає прочитати що це
> означає і відповідно зробити. Там користувач може налаштувати що це таке та яка зупинка буде. Там
> омжуть бути **текстописні правила чи команди**.» — **[524]** (VERIFIED)

Prose needs a model call at the moment the run is most likely failing; a command needs a shell and has
no defined exit contract. Two execution models, one name, no stated degradation. **Д12 is the one item
the interviewer itself left open** — *«Доповнення до Д12 отримано; підтвердження залишається
відкритим»* **[525]** (VERIFIED), after the session was cut mid-answer at [520] and resumed by typed
text at [524].

The command branch has a logged precedent here: `FIELD-NOTES.md` §11.8 (VERIFIED) —
*"`pkill -f 'playwright test'` killed an unrelated lane, because every lane's own prompt text contains
that literal string, so `pgrep`/`pkill` over-match sessions rather than suites."* A user-written stop
command is precisely where that pattern gets written, and R1-16 is his own rule against it:
*«він би не мав зупиняти якісь там тести, які не він запускав»* **[366]** (VERIFIED). Challenge A8.

**What the answer changes.** The stop parser, and whether a custom stop that was meant to *slow the run
down* is allowed to become a full halt when it cannot be interpreted. It also decides whether a custom
stop runs once or on every tick while the stop stands.

---

## Q10 — How does he learn that his edit landed — or that it was broken? · **default · major**

> «Ти сказав, що хочеш приходити в лайв режимі і розуміти, що це скоро потрапить в оркестратор. І
> окремо ти сказав, що оркестратор нічого тобі не виводить. Тоді питання: як ти дізнаєшся, що твоя
> правка доїхала — і особливо, що вона зламана, не застосувалася, і всю ніч діяли старі налаштування?»

Options to read out, and stop:
- «нехай дописує просто в той самий файл, що прийняв або не прийняв — я побачу очима»
- «нехай пише в окремий журнал, я гляну його командою статус, коли захочу»
- «зламана правка — це привід порушити тишу і написати мені в канал сповіщень»
- «нічого не треба»

**Why this is the hole.** He stated the expectation himself and no mechanism was ever named:

> «щоб, грубо кажучи, в лайв режимі я міг це прийти і це переглянути, і **я розумів, що це скоро
> потрапить в оркестратор** та будуть задійні відповідні дії щодо цього» — **[449]** (VERIFIED)

Against Д11:

> «оркестратор не повинен нічого виводити для мене» — **[508]** (VERIFIED; his own correction at
> [511]–[514] narrows this to minimal output, and that corrected version is unratified per
> `corrections.md`)

Measured here, and it is why "broken" is the dangerous case (research §3.5, VERIFIED by running it): a
JSON control file caught mid-save makes **every** setting in that layer revert to its built-in default
for that tick, silently — and because keys are read one at a time, a save straddling two reads yields a
**mixed** config inside one tick. `harness-run.sh:17` says this out loud about the current
implementation: *"INVALID … is not valid JSON — every setting would silently revert to defaults"*, and
that check runs **once, at preflight**, never on a tick.

And a self-written record is not evidence on this codebase: `FIELD-NOTES.md` §12.7 (VERIFIED) — *"A
security review of a single API read found 26 refusal events in the audit log that never occurred."*
So whatever he picks, the acknowledgement has to be something he can see rather than something the
orchestrator asserts. Research Q8.

**What the answer changes.** Whether the orchestrator writes back into the file it read, keeps a
separate journal, or is allowed one exception to Д11's silence. It also decides what an invalid edit
does to the tick — keep the last good config and carry on, or stop taking new work until he looks.

---

## Surviving gaps NOT turned into questions, and why

Listed so a later round can pick them up rather than lose them.

1. **A mid-run account assignment is never checked before it is used (challenge A7, major).** His
   verification duty is bound to *«**перед запуском** потрібно переконатися, що це працює»* **[199]**
   (VERIFIED, ratified), while the assignment is editable *«в моменті»* [195]. The failure: at 02:00 he
   names a profile whose token expired in August, every spawn dies in seconds, the liveness check reads
   a session that died at launch as a stall, and Д11 means nothing is printed. `FIELD-NOTES.md` §11.7
   records the class surviving for hours (*"The usage endpoint returned `authentication_error` for an
   extended stretch, blinding every cap read"*), and `ADAPTER-CONTRACT.md` §F adds a worse branch on
   macOS: *"Claude Code may raise a **Keychain GUI dialog** on an account that has never been granted
   access."* **Left out because `C4-capacity-questions.md` Q8 owns the pre-run check** and this is its
   mid-run twin; ask it in C4's session if there is room.
2. **The control file inside a worktree (challenge A10, major).** Д4's default is *«абсолютно все
   виконувати в різних ворк трі»* **[433]**; a tracked control file forks per lane, and a stop edited in
   the wrong copy is never seen. This has already happened: `FIELD-NOTES.md` §12.5 (VERIFIED) —
   *"`QUESTIONS.md` and `JOURNAL.md` forked into a worktree's own copy, and a real owner-facing question
   sat there invisibly for an hour"*, with twenty-three journal entries on the wrong side.
   **Left out because `C8-boundaries-safety-questions.md` Q7 asks the same shape for the prohibitions
   file and `C3-work-source-questions.md` Q2 for the board** — a third asking invites "I already
   answered that". Whatever he answers there generalises here; record it against Д12 as well.
3. **The control plane's scope (challenge A12, minor).** Two runs on one machine — `<work-project>` and
   `claude-plugins` — and one `/orchestrator:stop-hard`. If the file is user-scoped both stop; if
   project-scoped and the terminal's directory is wrong, the other one stops. Partly absorbed by Q1 and
   Q7; worth one sentence if Q1 goes quickly.
4. **A fourth stop verb: freeze (research Q5).** Gas Town's E-stop suspends with **SIGTSTP** —
   *"Context is preserved — no work is lost"* — and resumes with `gt thaw` (VERIFIED in source). For a
   limit pause that is strictly better than a hard stop, because it keeps the context window a hard stop
   throws away. **Left out deliberately: he named three variants [524], and proposing a fourth is a
   recommendation.** If `C4-capacity-questions.md` Q1's third "intermediate" stop (*«записати
   теперішній стан, можливо зберегти сесію, і зупинити її повністю»* [171]) gets ratified, this is the
   same thing and needs no question.
5. **Which direction the user band ranks (research Q2).** His marketplace puts the user band **above**
   the committed project band; the existing harness does the opposite (`hlib.sh:48-58`: project, else
   user, else default — VERIFIED); Claude Code puts the user file lowest of five. Д1 settles it by
   pointing at the marketplace, so re-asking would re-open something he closed. Q6 asks the one
   consequence that actually bites. The inversion of the current harness's behaviour is a **migration
   note**, not a question.
6. **Backups, retention and secrets in the control plane (research Q9).** Claude Code keeps five
   timestamped backups per config file and that is what makes its recovery path work (VERIFIED,
   vendor docs). Backups of an accounts file are also a record of which account ran what, kept where
   nothing scans it — `FIELD-NOTES.md` §11.10, *"Secrets that reached a place nobody scans."* The
   existing refusal rule (`harness-run.sh:32-38`: an `env_command` must **print** exports, never embed
   `OAUTH_TOKEN=`/`API_KEY=`/`SECRET=`) is the right invariant to extend, but it is not worth a voice
   question until Q1 fixes the layout.
7. **Whether the questions channel's default should be a GitHub issue because it cannot fork
   (research Q10).** Folded into item 2; it is a consequence of where the file sits, not of the
   protocol, and the protocol he already built by hand is stronger than anything I would propose.

---

## Interviewer notes for the voice session

- **Ask Q1 first.** Q3, Q5 and Q10 all read differently once he has said whether the control plane is
  one file or one place.
- **Vocabulary that is his and is safe to use:** оркестратор, ран, тікет, дошка, ворктрі, компакт,
  ліміт, провайдер, акаунт, сесія, хардстоп, софтстоп, профіль, конфіг, екзек'ютор, контекст вочер.
  «стоп-кастом» only because he typed `stop-custom` himself at [524]. Nothing else in English.
- **Do not name a preferred option.** Every list above is flat: read them in the order written and stop
  talking.
- **Do not ask the хард half of Q2** — `C4-capacity-questions.md` Q9 owns it.
- **Do not present mtime as his decision.** He hedged it — *«**Можливо**, там, **наприклад**, по даті»*
  [195] — and `corrections.md` flags ANALYSIS-01's "(mtime named as the mechanism)" as a mis-statement.
  If he asks how a change is detected, say the mechanism is open and has been measured, and do not
  spend a question on it. (For the record, measured here: two writes 3 ms apart share an identical
  integer mtime, so second-granularity detection **loses a stop written in the same second as an
  earlier edit**; and a rewrite with identical content moves mtime, so it over-reports too.)
- **Numbers that are safe to quote, all VERIFIED in `FIELD-NOTES.md`:** eight or more false `STALLED`
  alarms across about seven hours; an owner-facing question invisible for an hour; 26 refusal events in
  the audit log that never occurred. **Do not quote a count of escalated questions** — the field notes
  say eleven and enumerate thirteen ids.
- **Ratification status to keep in your pocket.** Д1, Д6, Д7, Д12 and the R1-06 hard/soft vocabulary
  are **all** unratified (VERIFIED, `extract/corrections.md`), and ANALYSIS-01 files four of them as
  SETTLED. He may say "I already answered that". He did — the restatement was never confirmed. Say that
  in one short clause and let him decide; do not argue.
- **If he starts redesigning mid-answer**, let him — his words are the source of truth — but bring him
  back to the option before moving on, or the round produces prose instead of a decision.
- **Q4 is the one to protect.** It is the sentence he himself marked «дуже важливо», and it is the one
  most likely to be waved through as already answered.

---

## Sources

**Transcript** — `../../round-1/TRANSCRIPT-01.md`, rows [133], [171], [176], [195], [199], [204],
[209], [270], [300], [335], [336], [357], [366], [416], [433], [449], [455], [458], [508], [520],
[524], [525].
**Analysis and extraction** — `../../round-1/ANALYSIS-01.md`; `../extract/corrections.md`.
**Cluster documents** — `C2-config-control-plane-research.md` §§2.1, 2.8, 3.1–3.10, 4.1–4.9, 6;
`C2-config-control-plane-challenge.md` A1–A12.
**Sibling clusters checked for overlap** — `C3-work-source-questions.md` Q2, Q4;
`C4-capacity-questions.md` Q1, Q4, Q8, Q9; `C8-boundaries-safety-questions.md` Q7.
**Field evidence (VERIFIED)** — `../../../../plugins/harness/docs/FIELD-NOTES.md` §§2.1, 11.3, 11.7,
11.8, 11.10, 12.5, 12.7.
**His marketplace (VERIFIED, read on this machine)** —
`<baseline-marketplace>/docs/config-levels.md`;
`requirements/OWNER-DECISIONS.md:169`.
**This repository (VERIFIED)** — `plugins/harness/bin/hlib.sh`; `plugins/harness/bin/harness-run.sh`;
`plugins/clickup/commands/onboard.md:6`.
**Platform contract** — `../platforms/ADAPTER-CONTRACT.md` §F, §G, §H.
**Measured on this machine, 2026-09-19/21** — `<switcher> switch --print-env`; `stat -f '%m'` vs `%Fm` on
APFS; mtime on an identical-content rewrite; torn reads under `jq`.

**Currency note.** The profile-switcher, filesystem and plugin-grep measurements are of this machine as it
stands on 2026-09-21. The `ADAPTER-CONTRACT` findings were gathered 2026-09-19 against CLIs that ship
daily to weekly; the Keychain-dialog behaviour in particular is a macOS/Claude Code interaction that
could change in any release.
