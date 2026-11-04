# C5 — Context-window management and compaction · round-2 questions

Cluster: **C5-context** · Item: **R1-08** (rows `[204]`, `[209]`, `[212]`), owner instruction **I1** `[182–184]`
Date: **2026-09-19** · Round: **2** · Format: **voice, Ukrainian**
Read first: `C5-context-research.md`, then `C5-context-challenge.md`

Ten questions. Five blockers, five majors. Every one is a hole the challenge pass found in a decision
he already made. None re-asks something he settled, none carries a recommendation, and where real
alternatives exist they are read out flat and the question stops there.

Evidence marks: **VERIFIED** (read in the transcript, the field notes, the supervisor prompts, the
plugin source, a binary's own strings, or a file on this machine), **CLAIMED** (a third party asserts
it), **INFERRED**.

**Reading order matters.** Q1 fixes the unit every other number in this cluster is denominated in —
ask it first, and after he answers, re-read any number he gives later back to him in that unit. Q10 is
housekeeping and should be last, because it may delete a mode and there is no point asking about hard
mode's details after he has removed it.

---

## Index

| # | Question | Kind | Priority |
|---|---|---|---|
| Q1 | Which percentage is his percentage — the two on his machine differ by ~13 points | definition | **blocker** |
| Q2 | What exactly is "guaranteed" — sent, accepted, or the window actually freed | definition | **blocker** |
| Q3 | Who presses the button when the full session is the orchestrator itself | collision | **blocker** |
| Q4 | Does soft mode have a ceiling, or does it wait for ever | gap | **blocker** |
| Q5 | A fresh orchestrator when the old one has not failed — versus «не дозволяти» | collision | **blocker** |
| Q6 | Who announces that the step is finished — the session, or the watcher guessing | gap | major |
| Q7 | What happens when a compact is no longer possible in that session at all | gap | major |
| Q8 | May a session say «зараз мене не чіпай», and for how long | gap | major |
| Q9 | A platform that cannot be compacted from outside at all | feasibility | major |
| Q10 | Three pieces of R1-08 were recorded as confirmed while he was silent | ratify | major |

---

## Q1 — Which percentage is your percentage? · **definition · blocker**

> «Ти сказав: людина налаштовує, при скількох відсотках робиться компакт. На твоїй же машині таких
> відсотків два, і вони розходяться приблизно на тринадцять пунктів — один показує сам Клод Код, коли
> питаєш у нього про контекст, другий малює смужка у твоєму статус-рядку. Коли ти кажеш «вісімдесят»,
> це який із двох?»

Options to read out, and stop:
- «той, що показує сам Клод Код»
- «той, що на смужці в статус-рядку»

**Why this is the hole.** His words:

> «Людина може налаштувати, **при скількох відсотках** відбувається компакт, який буде робити
> оркестратор» — **[204]** (VERIFIED)

"Percent of context" is not one quantity on his own machine. **VERIFIED**, read in
`~/.claude/hooks/gsd-statusline.js:801-802` — the status line normalises against the auto-compact
reserve before drawing the bar:

```js
const usableRemaining = Math.max(0, ((remaining - AUTO_COMPACT_BUFFER_PCT) / (100 - AUTO_COMPACT_BUFFER_PCT)) * 100);
const used = Math.max(0, Math.min(100, Math.round(100 - usableRemaining)));
```

`AUTO_COMPACT_BUFFER_PCT` defaults to **16.5**, and the file's own comment at line 815 says the
normalised value *"inflates the context monitor warning messages by ~13 points"*. So the number he has
been reading all year and the number the platform reports natively are about thirteen points apart.

And **every percentage in the field record is of unstated provenance**: the previous generation read
context off the screen (`FIELD-NOTES.md` §3.3 — "it is printed on every session's own status line, and
the watch loop already captures every screen each cycle"; the cycle lines record `ctx=NN%`, VERIFIED).
66 %, 73 %, 74 %, 91 %, 95 % — all of them screen numbers.

**What the answer changes.** Whether 80 in his config is compared against `100 - remaining_percentage`
or against the normalised bar value. Get it backwards one way and the platform's own auto-compact
fires *before* his threshold is ever reached, so his mechanism never executes once in a whole night and
the report reads identically to "nothing needed it" (challenge A2). Get it backwards the other way and
a 1M-window orchestrator compacts about a third earlier than he meant, repeatedly, at roughly seven
minutes a time (`J-WATCH-01`: 67 % → 0 % in about seven minutes, VERIFIED `FIELD-NOTES.md` §10.2).

It also cannot be settled by convention across platforms: Codex ships
`model_auto_compact_token_limit_scope` with a `body_after_prefix` mode that charges only "sampled
output and later growth after the carried window prefix" (VERIFIED in the schema `codex app-server
generate-json-schema` produced on this machine), so the same configured `80` means different occupancy
on Claude Code and on Codex. Ask him for the unit once and print it next to every threshold thereafter.

---

## Q2 — What exactly has to be guaranteed? · **definition · blocker**

> «Ти сказав: має бути механізм, який гарантовано робить цю дію. Минулого разу команда компакту дійшла
> один раз із трьох, і два провали були беззвучні — в логу все одно було написано, що відправлено. Що
> саме має бути гарантовано?»

Options to read out, and stop:
- «що команду відправили»
- «що сесія її прийняла»
- «що вікно справді звільнилося і число впало»

**Why this is the hole.** His words:

> «І якщо, наприклад, оркестратор наблизився до того числа, ну або, чи перейшов це число, то **повинен
> бути механізм, який гарантовано робить цю дію**, і відпрацьовує так, що сесія компактиться» — **[204]**
> (VERIFIED)

The sentence names a trigger and an action and then asserts a property of the mechanism. It names **no
observable that says the action happened**, and **no behaviour for when it did not**. Two implementers
read it two ways: one sends the command, logs `compact sent` and moves on — satisfying every word; the
other builds detect → act → verify → escalate. Both can point at `[204]`.

The evidence says the first reading fails on his own platform. All **VERIFIED** in `FIELD-NOTES.md`:

- `/compact` landed on **one of three attempts** on the same session in one day (§1.2). Attempt 2 —
  empty input line, no child shells — went 73 % → 0 % in ~90 s. Attempts 1 and 3 had shells running:
  nothing happened, and attempt 3's session then drifted 91 % → 95 % and auto-compacted.
- **Five separate instructions typed into sessions were never delivered** in one run (§1.3).
- `send` **fails silently above roughly 200 characters** — an ~1100-character message produced no error
  and never appeared (§12.1).
- A 149-minute stall happened because an Enter never landed on a pane, and **nothing detected it**
  (§12.1).

Every one of those failures is silent; the sender sees success. And the distinction is real elsewhere
too — opencode's own documentation says outright (**CLAIMED**): *"The response confirms admission; it
does not wait for the summary."*

**What the answer changes.** Whether the build contains a verification stage and an escalation ladder
at all, or a single fire-and-forget call. That is roughly the difference between a state machine
persisted on disk and one function. Challenge A1.

---

## Q3 — Who presses the button when the full session is the orchestrator itself? · **collision · blocker**

> «Ти сказав, що компакт робить оркестратор. Але сам собі оркестратор компакт зробити не може — модель
> не вміє написати команду у свій власний рядок вводу, а саме оркестратор ти й називав як приклад
> того, хто впирається в поріг. Хто тоді це робить за нього?»

Options to read out, and stop:
- «контекст вочер»
- «окремий процес поза сесіями, який не є сесією»
- «оркестратор робить це всім іншим, а йому — хтось окремий»

**Why this is the hole.** Two of his own rows point different ways:

> «Людина може налаштувати, при скількох відсотках відбувається компакт, **який буде робити
> оркестратор**» — **[204]** (VERIFIED)

> «це має бути налаштовано через єдиний файл, який **оркестратор чи контекст вочер** постійно дивиться
> і перевіряє» — **[195]** (VERIFIED)

`[195]` leaves the actor open; `[204]` names the orchestrator — and the same answer names the
orchestrator as the *subject*: «якщо, наприклад, **оркестратор** наблизився до того числа». The
constraint that makes this impossible is stated as the governing constraint of the entire previous
generation, **VERIFIED**, `FIELD-NOTES.md` §1.1: *"A model has no way to put text on its own input
line."*

And the previous generation's workaround contradicts itself in its own documents. `WATCHER-PROMPT.md`
line ~162 (VERIFIED, read on this machine) tells the context watch: *"**So compact yourself, on your
own initiative, at about 85 per cent.** Run `/compact` in your own session"* — while §1.2 records that
`/compact` lands **only when the target has no child shell running**, and the only mechanism a session
has for typing into its own tty *is* a shell.

The failure shape is already on file. `FIELD-NOTES.md` §11.6, VERIFIED: an 85-minute self-sustaining
loop that *nothing internal detected*, ended only by an external `SIGTERM`, with line 5620 of that log
reading **`NO ONE IS BEING TOLD`**. A session that reads its own threshold, agrees it is exceeded and
has no verb writes about it — which consumes more context — and re-checks.

**What the answer changes.** Whether the trigger lives inside the session fleet or in a supervising
process outside it. That decides the whole topology, and it decides whether the orchestrator is a
participant in the context mechanism or only its subject.

---

## Q4 — Does soft mode have a ceiling, or does it wait for ever? · **gap · blocker**

> «Софт — це дочекатися завершення кроку. Але минулого разу одна сесія три з половиною години крутила
> порожній цикл, ні разу не завершила крок і дійшла до дев'яноста одного відсотка — софт так і не
> спрацював би жодного разу. Чи має бути в софта верхня межа, після якої він перестає чекати?»

Options to read out, and stop:
- «так, друге, вище число — дійшло до нього, більше не чекаємо»
- «так, час — почекали стільки-то і більше не чекаємо»
- «ні, чекати завжди, хай платформа сама розбирається, якщо не дочекались»

**Why this is the hole.** This is the only ratified statement in the cluster, so the *decision* stands;
the hole is what happens when its wait condition is never satisfied:

> «Лише поточного кроку, але це можна налаштовувати, людина може сама налаштувати, що це означає»
> — **[209]**, ratified «Так, правильно» **[212]** (VERIFIED)

The killing scenario is measured, not hypothetical. `FIELD-NOTES.md` §3.1, **VERIFIED**: lane
`w-phase-19` spent **3 466 of 3 626 Bash calls** on the literal command `echo idle`, mean interval
2.54 s, ~1 400 an hour, for three and a quarter hours. It added **445 k tokens of context — 77 % of all
context growth in that window** — and reached **91 %**. It committed nothing in that time, never went
idle, and never crossed a step boundary. Soft mode would have armed correctly at the threshold and
waited correctly until the platform's own auto-compact took the decision instead.

Refill rates make the slack very different per session, all **VERIFIED**, `FIELD-NOTES.md` §3.2: the
context watch ran **9 % → 91 % in about ten hours** (~8 %/hour); a worker lane hit **91 % in three and
a half hours** (~26 %/hour); the orchestrator was at **64 % after thirty hours** (~2 %/hour). At
26 %/hour, a soft threshold of 80 leaves about **46 minutes** — shorter than a single worker phase,
which ran 58 minutes to 3 h 20 m on the last run (§6). So on a perfectly healthy lane the step boundary
may simply not arrive before the wall.

**What the answer changes.** Whether the state machine has one threshold or two, and whether soft mode
can promote itself to hard. Challenge A4.

---

## Q5 — A fresh orchestrator when the old one has not failed · **collision · blocker**

> «Ти дозволив замість компакту піднімати повністю новий оркестратор. І окремо ти сказав: новий можна
> запускати тільки переконавшись, що попередній не спрацював, а два одночасно — не окей, це треба
> відслідковувати і не дозволяти. Але коли просто заповнилось вікно, попередній не зламався — він
> живий і тримає роботу. Що робити з живим, перш ніж підняти нового?»

Options to read out, and stop:
- «спершу закрити старого, і тільки потім піднімати нового»
- «підняти нового відразу, а старий догортає те, що вже почав, і гасне сам»
- «в цьому випадку взагалі не піднімати нового — тільки компакт»

**Why this is the hole.** Both decisions are his, and they collide:

> «оркестратор можна як компактити, так і **запускати повністю новий оркестратор**, що також може бути
> окей, і людина може це налаштовувати» — **[204]** (VERIFIED)

> «Дуже важливо, що **не може бути такого, що вже якісь існуючі оркестратор і спускається наступний**
> … Якщо, наприклад, запустився оркестратор, або щось запустилось, але воно не спрацювало,
> **переконуєш що воно не спрацювало, а після того запускаєш новий** … якщо раптом одночасно два якісь
> оркестратори працюють, то це не окей» — **[300]**, and «**Це треба відслідковувати і не дозволяти**»
> — **[301]** (VERIFIED)

`[300]` makes replacement conditional on proving the previous orchestrator failed. In the R1-08 case it
has **not** failed — it is healthy, mid-run and merely full — so the precondition can never be
satisfied, and `[301]` upgrades the invariant from detection to enforcement.

The previous generation hit this exact wall and left a written verdict. `WATCHER-PROMPT.md` lines
113–124, **VERIFIED** on this machine: *"**The close-and-respawn procedure this section used to carry
does not work on this setup, and it was proved not to work rather than assumed.** `harness-spawn.sh
close` deliberately never force-closes a session that has a running job, and **this orchestrator always
holds an armed monitor** … the `spawn` that follows fails with `session orchestrator already
registered`. … It was tried twice on 2026-09-02; both times the handoff was written and the replacement
failed."*

A second, quieter hole in the same sentence, worth raising only if he opens it: «повністю новий» does
not say what the new one inherits, and a fresh session that re-runs the old launcher **resumes the
wedged conversation, because the session id is baked into it** (`ORCH-HANDOFF.md` trap 3, VERIFIED) —
which satisfies the words and defeats the purpose.

**What the answer changes.** Whether the registry guard required by `[301]` gets an exemption path, and
whether "fresh orchestrator" is a close-then-start or an overlap-then-drain. Those are different
products, and one of them was already measured to fail on this setup. Challenge A5.

---

## Q6 — Who announces that the step finished? · **gap · major**

> «Хто має сказати, що крок завершився — сама сесія пише про це кудись, чи той, хто стежить, має
> здогадатися ззовні по тому, що сесія затихла? Бо ззовні видно тільки тишу, а тиша бреше: минулого
> разу одна сесія сорок п'ять хвилин трималася зайнятою на циклі, який уже ніколи не міг завершитися.»

Options to read out, and stop:
- «сама сесія оголошує — і це вимога до процесу, який вона виконує»
- «ззовні, по тиші»
- «сесія оголошує, а тиша лишається запасним варіантом, якщо оголошення немає»

**Why this is the hole.** The step boundary is a property of the *supervised* session's internal state,
and the thing that must wait for it is outside that session. He moved the definition to the user —

> «але це можна налаштовувати, людина може сама налаштувати, що це означає» — **[209]** (VERIFIED)

— but **nothing in `[204]` or `[209]` obliges the supervised session to *emit* a boundary**, so the
user is being handed a detection problem, for an engine he did not write, to be tested at a moment he
is asleep.

The externally visible signals are forgeable by accident, in ordinary operation. All **VERIFIED**,
`FIELD-NOTES.md`:

- §2.2 — a lane held one shell running `until grep … sleep 5` against a file that had finished being
  written **forty-five minutes earlier**: "The pattern could never match, the loop could never end, and
  no check would ever have called that session parked."
- §2.2 — a different lane accumulated **58 concurrent child shells**, each a `sleep 590` poll.
- §1.5 — "A session heartbeats **between** turns. A validator running a 14-minute suite … does not
  heartbeat at all." Six healthy sessions were nudged on that basis in one run.

**What the answer changes.** If the session announces, then "emit a step-boundary marker" becomes a
requirement on every configured process (Get Shit Done, Superpowers, or his own), which is a contract
he has to write into R1-03's process definition. If the watcher infers it, the build needs a busy/idle
probe good enough to survive the three cases above — on Claude Code 2.1.278 that is `claude agents
--json`, which reports `status: busy|idle` per session and **does not require a TTY** (VERIFIED by
execution on this machine), and which is a different piece of work.

---

## Q7 — What happens when a compact is no longer possible in that session at all? · **gap · major**

> «У Клод Кода є стани, з яких компакт у цій сесії вже ніколи не спрацює: коли незмінна частина
> контексту сама більша за поріг, коли компакт тричі підряд не допоміг, і коли компакт вимкнений
> зовсім. Твоя настройка каже «роби компакт». Що має статися, коли компакт у цій сесії більше
> неможливий?»

Options to read out, and stop:
- «мовчки підняти нову сесію і працювати далі»
- «розбудити мене»
- «зупинити цю лінію роботи і чекати до ранку»

**Why this is the hole.** His answer has no branch for a configured action that can never succeed:

> «користувач повинен це налаштувати. Та явно, чітко вказати» — **[204]** (VERIFIED)

Four real states, all **VERIFIED** in the 2.1.278 binary's own strings:

1. **Prefix overflow** — `autocompact: fixed prefix ~${prefixTokens} > threshold ${thresholdTokens} — compaction cannot help`.
   When the un-summarisable prefix (system prompt, tool definitions, memory files, skills) already
   exceeds the threshold, compacting frees nothing. This is a *configuration* failure as much as a
   runtime one, and this machine runs roughly twenty MCP servers and well over a hundred skills
   (VERIFIED — this session's own tool and skill listing).
2. **Thrash breaker** — verbatim: *"Autocompact is thrashing: the context refilled to the limit within
   3 turns of the previous compact, 3 times in a row."*
3. **Failure breaker** — N consecutive failures → `failure_breaker_open`; auto-compact stops trying.
4. **`DISABLE_COMPACT`**, documented in the binary as *"DISABLE_COMPACT also disables manual
   `/compact`"* — a session launched by a wrapper that sets it will accept the keystroke and do nothing,
   indefinitely.

Two of those are permanent for the life of the session. And the road into them is short: a verification
that returns a false negative during the very operation it is verifying re-fires the trigger, and three
of those in a row make the session permanently uncompactable by both his mechanism and the platform's.
That false negative is documented on this machine — `~/.claude/hooks/gsd-context-monitor.js`, VERIFIED:
*"a render during the compaction stamps the OLD `remaining_percentage` with a current time"*.

**What the answer changes.** Whether the config needs a per-role fallback action, and whether a
dead-ended session is a night-time notification (which belongs with R1-17 `[395]`, where he said the
user configures which events notify) or a silent recovery. Challenge A10.

---

## Q8 — May a session say «зараз мене не чіпай», and for how long? · **gap · major**

> «Хард — це зупинити прямо зараз. Але буває момент, коли файл навмисно зламаний: його ламають, щоб
> перевірити, що тест ловить поломку, і знає про це тільки сама сесія. Якщо хард спрацює саме там,
> поломка залишиться в коді і ніхто вже не знатиме, що її треба відкотити. Чи може сесія сказати
> «зараз не чіпай» — і якщо так, то наскільки максимум?»

Options to read out, and stop:
- «так, і без обмеження — чекати, поки сама відпустить»
- «так, але не довше якогось строку, потім все одно зупиняти»
- «ні, хард є хард»

**Why this is the hole.** His words:

> «Чи хард, прямо вже зупинити, зробити компакт, і продовжити» — **[204]** (VERIFIED; the restatement
> at `[213]`/`[217]` was never answered — see Q10)

The project this tool was built against has a rule that forbids exactly that at certain moments.
`ORCHESTRATION.md` lines 161–164, **VERIFIED** on this machine:

> "**Never compact with a mutation applied** — restore it, confirm the tree is clean with `git status
> --porcelain`, and only then compact. A compact that lands mid-mutation can leave deliberately-broken
> code in the tree with nothing left that knows to undo it."

Hard mode is defined as ignoring that, and the memory that a file is currently broken lives in the
session and nowhere else. "A later gate will catch it" is not supported by the record: the previous
generation merged a phase before its validator ran (`FIELD-NOTES.md` §11.4, `2026-09-13T03:26:23Z`,
VERIFIED) and shipped five phases whose verify stage was silently skipped.

The same lock is what makes the platform's own auto-compaction unsafe here — it fires whenever it
likes and cannot honour any such marker (**INFERRED** from §2.4 of the research, and the reason it is
worth asking rather than assuming).

**What the answer changes.** Whether the build needs a session-written "unsafe to interrupt" marker
with a timeout and an owner, or hard mode is unconditional. If he says yes, this also decides whether
our threshold must sit safely below the platform's auto-compact point so that ours is the only
compaction that ever happens. Challenge A6.

---

## Q9 — A platform that cannot be compacted from outside at all · **feasibility · major**

> «Ти казав: те саме для Кодексу, те саме для інших платформ. Кодекс справді вміє все, що ти просиш —
> його сесію можна скомпактити ззовні однією командою. А є платформи, де так не можна взагалі: у
> Джеміні немає нічого, чим його скомпактити ззовні, і його власний поріг не змінюється без
> перезапуску. Що робити з такою платформою?»

Options to read out, and stop:
- «для неї замість компакту завжди нова сесія»
- «не підтримувати її взагалі»
- «хай людина сама пише для неї свій скіл, а ми лише запускаємо»

**Why this is the hole — and why it is asked separately.** He instructed that exactly this be raised as
its own question:

> «Якщо, наприклад, при різних платформах це буде неможливо, то про це треба говорити і обдумувати, як
> можна це зехендлити. Платформи — це, наприклад, Клод, Кодекс, GLM … це не впирається в те, що я
> сказав, що воно буде якось поламане, то це треба буде винести окремими питаннями потім, як це
> вирішити» — **I1 [182–183]** (VERIFIED)

The capability gap, per platform:

| | Read the % from outside | Compact it from outside | Confirm it happened | Prompt after |
|---|---|---|---|---|
| Claude Code 2.1.278 | **yes, three ways** (VERIFIED) | **no RPC** — only typing into a tty, or its own auto-compact | **yes** — PostCompact hook, `compact_boundary` in the transcript | **yes** — SessionStart(`compact`) hook |
| Codex CLI 0.152 | **yes** — `token_count` with `model_context_window` in the rollout (VERIFIED) | **yes** — `thread/compact/start` (VERIFIED in the generated schema; the daemon was not running here, so specified not executed) | **yes** — `thread/compacted` | **yes** — `codex queue --thread … --message …` |
| Gemini CLI | partly — OTLP telemetry to a file (VERIFIED in source) | **no documented external trigger** | PreCompress hook fires but **cannot block** | hook returns `systemMessage` only — **no context injection** |
| opencode | partly (CLAIMED) | **yes** — `POST /api/session/{id}/compact` (CLAIMED) | events only | yes |

Gemini CLI specifics, **VERIFIED** from `google-gemini/gemini-cli@main` read on 2026-09-19:
`packages/cli/src/config/settingsSchema.ts` — `model.compressionThreshold`, default `0.5`,
**`requiresRestart: true`**; `packages/core/src/hooks/types.ts` — `PreCompressOutput {suppressOutput?,
systemMessage?}`, i.e. no veto and no context injection.

**What the answer changes.** Whether "works for all sessions" is a promise the config must keep
uniformly, or a per-platform capability table the user sees at config time. It also decides whether a
role may be placed on a platform where his chosen action cannot execute — and whether the tool refuses
that placement or accepts it with a downgrade.

---

## Q10 — Three pieces of R1-08 were written down while you were silent · **ratify · major**

> «Одна технічна річ. У першому раунді після твоєї відповіді інтерв'юер двічі сам сказав «підтвердив,
> зафіксував» — а ти в ці моменти нічого не відповідав, ти просив повторити. Тому три речі стоять у
> записі як твої, але твого «так» під ними немає: що хард означає зупинити зараз, скомпактити і
> продовжити; що для оркестратора можна обрати або компакт, або нову сесію; і що після компакту може
> йти промпт. Що з цього справді твоє?»

**Why this is the hole.** **VERIFIED**, `research/extract/corrections.md` §C and the transcript rows
read directly:

- At `[213]`/`[214]` the interviewer restated thresholds, scope and hard mode. He said «Повтори ще раз»
  `[215]`. It repeated at `[217]` and then declared **«Підтвердив, зафіксував. Що далі?»** `[218]` —
  **he said nothing in between**.
- At `[220]`/`[221]` it restated compact-or-new-session, the choice of command or custom skill, the
  post-compact prompt, and the guaranteed-execution clause. He said «Яке наступне питання? Чи повтори
  будь ласка» `[222]`, it repeated at `[224]`, and moved to R1-09.

His own words at `[204]` are his and are safe. The only «Так, правильно» anywhere in this cluster is
`[212]`, and it covers the soft-mode step boundary alone. The post-compact prompt in particular has
never been discussed beyond that unratified restatement, and the whole of R1-06's soft/hard vocabulary
— the base definition the other clusters reuse — is itself unratified (`[176]`–`[181]`, VERIFIED).

**What the answer changes.** Potentially it deletes hard mode, or the fresh-session option, or the
post-compact prompt, which would make Q5 and Q8 moot. Ask it **last** for that reason: if it is asked
first and he drops hard mode, the earlier questions are wasted, and if it is asked last and he keeps
everything, nothing is lost.

---

## Surviving gaps NOT turned into questions, and why

Listed so the next round can pick them up rather than lose them.

1. **A custom compaction skill has no completion signal and no obligation to free anything (challenge
   A9) — the top candidate if a slot frees up.** He allowed it explicitly: «якою командою, чи це
   офіційна … чи це кастомний скіл» **[204]** (VERIFIED). A native `/compact` produces runtime-emitted
   proof — a PostCompact hook with the summary in hand, and a `compact_boundary` transcript record
   (VERIFIED in the 2.1.278 hook schema). A custom skill produces none of that, is ordinary model work,
   and *consumes* context on the way to freeing it. A skill that writes an excellent handoff and does
   not compact is a fully valid configuration under `[204]`, and the supervisor would read no drop,
   conclude failure, and fire again. Partly covered obliquely by Q2 (what counts as guaranteed) and Q7
   (what happens when the action cannot succeed), which is why it lost the cut.

2. **«Софт» and «хард» mean three different things in three of his answers (challenge A7).** Limits
   `[171]`: soft = finish the task, take no more, and the run **stops**. Config change `[195]`: soft =
   move it to the next tasks. Context `[204]`/`[209]`: soft = wait for the step, compact, and
   **continue**. Two opposite post-conditions, three granularities, and he wants it all driven from
   «єдиний файл» `[195]` (all VERIFIED). The 23:00 scenario is real: he writes `hard` meaning `[171]`
   and the context subsystem reads it with its `[204]` meaning. This is cross-cluster vocabulary —
   C1 already asks what a hard stop pauses — so it belongs in a consolidation pass, not in C5 alone.

3. **He cannot know the right number, because it only means something against a refill rate.** Measured
   rates on one machine differ by an order of magnitude — 8 %/hour, 26 %/hour, 2 %/hour (VERIFIED,
   `FIELD-NOTES.md` §3.2). The build question this raises — should the orchestrator measure
   Δpercent/hour and warn, lower the threshold, or ignore it — is genuinely open and is the largest
   single context finding in the field notes (the `echo idle` lane: 445 k tokens, 77 % of all context
   growth in its window, VERIFIED §3.1). It is quoted inside Q4 as evidence rather than asked, because
   Q4's ceiling question has to be settled first.

4. **There is no default and no first-run behaviour for the context section.** Partly answered already
   by his own architecture answer: «Якщо чогось немає, то оркестратор задає ці питання для того, щоби
   їх покрити» **[133]** (VERIFIED) — so the configurator asks. What remains open is whether the
   context threshold is on the must-ask list before an unattended night run, or may be left empty. Ask
   it with the other config-lifecycle questions, not here.

5. **A compaction and a stall are the same observation from outside (challenge A8).** A compaction takes
   minutes and produces no output (67 % → 0 % in about seven minutes, `J-WATCH-01`, VERIFIED), and a
   session heartbeats *between* turns (§1.5). So the liveness watch nudges a healthy compaction — and
   the nudge is destructive: a bare Enter does **not** submit stranded text (§1.4), and `send` types its
   own text and **destroys** whatever was pending (§1.3). Measured context: 33 nudges in one run
   (§12.3), `STALLED` raised against healthy sessions eight or more times across about seven hours
   (§11.3). This belongs to **C6-liveness-recovery**, which owns R1-09's silence ladder.

6. **Installing a status line to read the percentage removes the `esc to interrupt` footer hint
   (challenge A12, minor).** The published doc says so (**CLAIMED**), and `WATCHER-PROMPT.md` line 126
   gates the whole compaction procedure on exactly that string (VERIFIED). The replacement exists and is
   better — `claude agents --json` (VERIFIED by execution) — so this is an implementation note, not a
   question for him. Version-bound: true of 2.1.278 on 2026-09-19, and four versions shipped on this
   machine inside four days.

7. **Whether hitting a permanent compaction dead-end is notification-worthy at night** rides on R1-17
   `[395]`, where he said the user configures which event types notify (VERIFIED). Q7's options include
   «розбудити мене», so it is asked obliquely; the general notification taxonomy is not C5's.

---

## Interviewer notes for the voice session

- **Ask Q1 first, and then use his unit for the rest of the session.** Every later number he says has to
  be recorded in the unit he picks, or the round produces thresholds of unknown provenance — which is
  exactly what the last run's records are.
- **Ask Q10 last.** It can delete hard mode, the fresh-session option or the post-compact prompt, and
  Q5 and Q8 are about those.
- **Vocabulary that is his and is safe to use:** оркестратор, ран, тікет, дошка, ворктрі, компакт,
  ліміт, провайдер, акаунт, сесія, хардстоп, софтстоп, поріг, вікно, скіл, промпт, конфіг, контекст
  вочер, екзек'ютор, Клод Код, Кодекс. Nothing else in English. He has **not** said "Gemini" — Q9
  introduces it once, in Cyrillic, as a fact about a platform.
- **Do not name a preferred option.** Every options list above is neutral in order: read them flat and
  stop talking.
- **Numbers that are safe to quote**, all VERIFIED in the file: ~13 points (the two percentages); one of
  three attempts; 3 466 of 3 626 `echo idle` calls / 91 % / three and a half hours; 45 minutes (the
  shell that could never exit); 85 minutes (the loop nobody broke); seven minutes (a compaction). **Do
  not quote a total count of context actions** — the previous generation measured none, because nothing
  in it measured context at all (`FIELD-NOTES.md` §3.3, VERIFIED).
- **If he answers a question by redesigning**, let him — his words are the source of truth — but get the
  option back before moving on.
- **Q3 and Q5 are the two he is most likely to wave off** as already answered. He did answer adjacent
  questions; neither hole is closed. Say the one-clause reason and let him decide.
