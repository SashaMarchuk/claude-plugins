# C2 — Configuration model, live overrides and the control file · adversarial pass

Cluster: **C2-config-control-plane** · Items: **Д1, Д6, Д7, Д12, R1-07, R1-04**
Date: **2026-09-21** · Read first: `research/clusters/C2-config-control-plane-research.md`

This document attacks. It does not redesign. Every entry names a decision the owner made, the hole in
it, and a concrete situation in which that hole produces a bad outcome. Evidence is marked
**VERIFIED** (I read it in the transcript, the field notes, the plugin source, his marketplace docs,
or ran it on this machine), **CLAIMED** (a third party asserts it), or **INFERRED** (my reasoning,
labelled as mine).

Twelve attacks survived. Five are blockers — the decision, as stated, does not do the job he wants it
to do until the hole is closed. Six are majors — two competent implementers build different things, or
the thing built fails on a night he is asleep. One is minor.

Nothing below overwrites a decision. Where a challenge collides with his own words, both sides are
quoted with their `[row]` anchors.

---

## Index

| # | Attack | Severity |
|---|---|---|
| A1 | `софт`/`хард` means three incompatible things across R1-06, R1-07 and R1-08, and the control file has one word for all three | **blocker** |
| A2 | The one behaviour he marked «дуже важливо» is the one the soft/hard vocabulary cannot express at all | **blocker** |
| A3 | The polled file has at least three writers and one of them is him — an editor save silently erases a stop | **blocker** |
| A4 | Д1's precedence puts an arbitrary repository's committed file above the plugin's defaults, for every key he has not set | **blocker** |
| A5 | The watched config files are written by other plugins and by git — changes arrive with no author and no type | **blocker** |
| A6 | An account switch is a config-root switch, so a control-plane event silently swaps two of the six config slots | major |
| A7 | A live account assignment is never preflighted, though [199] demands the switch be proven before the run | major |
| A8 | `stop-custom` is two execution models under one name, with no stated degradation and no way to know it fired | major |
| A9 | «оркестратор чи контекст вочер» — if the orchestrator polls, the stop is unreadable exactly when it matters | major |
| A10 | The control file lives in the project and Д4 puts every task in a worktree; the fork has already happened once | major |
| A11 | No defaults are named, and run 1's 23:00 answers become run 2's silent global defaults | major |
| A12 | The control file's scope is undefined — per project, per user, or per run — and two runs on one machine collide | minor |

---

## A1 — `софт`/`хард` means three incompatible things, and the control file has one word for all three · **blocker**

**The decision.**

> «і якщо в моменті щось змінюється, то вказується, який тип цієї зміни. Тобто, чи це софт, що це треба
> буде наступні завдання перенести, чи це хард, чи це треба прямо вже зробити і зупинити» — **[195]**

The type is the control file's only verb. Everything the owner wants the file to do — move an account,
change a behaviour, stop the run — is delivered by attaching one of these two words to an edit.

**The hole.** He uses the same two words, in the same session, for three different things, and they do
not agree.

| item | row | what `софт` means there |
|---|---|---|
| R1-07 (this cluster) | **[195]** | *«наступні завдання перенести»* — the run **carries on**, the change applies to the next tasks |
| R1-06 (limits) | **[176]** | *«м'яка дозволяє йому завершитися, але не запускає нових»* — the run **drains and ends** |
| R1-08 (compaction) | **[209]** | *«Лише поточного кроку»* — wait for the current **step**, not the task, then act |

Three boundaries — next task, no new tasks, next step — under one word. And the boundary itself is
declared configurable in a fourth place: *«але це можна налаштовувати, людина може сама налаштувати,
що це означає»* **[209]**.

**Worse: the version that would have reconciled them was never ratified.** The interviewer's
restatement of the hard/soft rule for limits was answered with «Повтори, будь ласка», repeated twice,
and then abandoned for the next restatement — [176]/[177] → [178] → [179]/[180] → [181]
(`../extract/corrections.md:86`, VERIFIED). So the load-bearing vocabulary that R1-07, R1-08 and Д12
all reuse has never been agreed in any single meaning.

**Concrete failure.** 01:40. The owner's Claude account is at 88% weekly and he wants the executor role
moved to a separate account (one he has configured) without disturbing the night. He writes into the polled file:

```
executor.account = <profile-B>
type = soft
```

He means [195]: *the next tasks go to the other account, the run keeps going.* The implementer built
[176]: `soft` = let the current work finish and start nothing new. At 01:55 the last running task
completes, the orchestrator starts nothing, writes its report, and closes every session. He wakes at
07:00 to a run that stopped five hours early, with 31 tickets untouched and a report that says
"soft stop applied at 01:55 as requested". Nothing is wrong with the software. The word did two jobs.

**The reverse costs more.** Same file, he writes `type = hard` for a limits threshold, meaning [176]'s
*«негайно зупиняє поточне завдання»*. The implementer built [195]'s hard — *«прямо вже зробити і
зупинити»* read as "apply the account change now, stopping the current work" — so it kills the session,
relaunches it under the new account, and keeps going against a quota that is about to hit zero.

**What two implementers build differently.** One builds a single `type` enum with one meaning. One
builds a per-domain type (`account.type`, `limits.type`, `context.type`), which is three vocabularies
that look like one. The control file he described has no field that distinguishes them.

---

## A2 — The one behaviour he marked «дуже важливо» cannot be expressed by the soft/hard vocabulary · **blocker**

**The decision.** Д7's default, and then the override he emphasised himself:

> «Це може налаштовуватися користувачем, по дефолту я б рекомендував, що він залишається та чекає на
> мої відповіді» — **[455]**

> «якщо раптом, я хочу змінити цю поведінку під час цього запуску або просто в якийсь момент я можу це
> зробити також… оркестратор повинен це зчитувати та приймати. **Це також, і це дуже важливо.**» — **[458]**

In English, the rest of the answer: if he wants the orchestrator to wait for his answer instead of stopping the run, that holds even if he chose otherwise at the start or the default says otherwise.

**The hole.** The thing he wants to change mid-run is *what happens when the run has nothing left but
tasks waiting on him* — that is, **the run's own termination**. R1-07's two types both attach to work:

- `софт` = *«наступні завдання перенести»* [195] — applies to the **next task**.
- `хард` = *«прямо вже зробити і зупинити»* [195] — applies to the **current work**.

Neither names the run's end-of-life. At the exact moment his override matters there is no next task
(that is the precondition of Д7: *«якщо залишилися лише завдання, що чекають твоєї відповіді»* [454])
and no current work to stop. **A `soft` change has nothing to apply to, and a `hard` change stops what
is already not running.** The override he called «дуже важливо» falls between his own two types.

**And Д7 itself is unratified.** [460]/[462] → [463]: the interviewer restated the mid-run-override
rule and then moved to Д8 without an answer (`../extract/corrections.md:102`, VERIFIED). So the most
load-bearing sentence in the cluster is on the record once, in his voice, and never confirmed.

**Concrete failure.** 23:50. He starts the run with `wait_for_answers = false` because he intends to go
to sleep. At 00:30 he wakes, sees in `QUESTIONS.md` that two tasks are blocked on him, decides he will
answer them in the morning, and edits the control file to `wait_for_answers = true` — precisely the
[458] scenario, word for word. The implementer classified the edit as `soft`, because it is not a stop.
Two minutes later the last unblocked task finishes. The orchestrator evaluates the end-of-run
condition. Under the rules as written it has either (a) already read the edit and honoured it, or (b)
queued it for "the next task", of which there is none, and exits. Both implementations are faithful to
[195]. One of them is the behaviour he explicitly said must not happen.

**The second-order hole.** If the answer is "the orchestrator re-evaluates end-of-run against live
config every tick", then a run can never end deterministically: whether a run that stopped at 02:00
would still have been running at 02:01 depends on a file the owner may edit at any time, and Д11 means
nothing tells him which branch was taken:

> «оркестратор не повинен нічого виводити для мене» — **[508]**

---

## A3 — The polled file has three writers and one of them is him · **blocker**

**The decisions, which are the same file.**

> «це має бути налаштовано через **єдиний файл**, який оркестратор чи контекст вочер постійно дивиться» — **[195]**

> «Це в **той файл**, який оркестратор на постійний основі читає… Коли це команда вводиться, то в цьому
> файлі відповідно конфігурується хард стоп чи софт стоп» — **[520]**

So one file carries: account assignments (edited by hand), Д7's live behaviour overrides (edited by
hand), and the stop state (written by `/orchestrator:stop-hard`). The previous generation adds a fourth
writer that he has not repealed: the limit wind-down writes the stop itself
(`harness-run.sh:243-244`, VERIFIED) — *«коли залишок ліміту добігає кінця»*, R1-06.

**The hole.** Nothing in [195] or [520] says who may write, in what order, or how a writer knows what
another writer just put there. His own description of Д6 has him **in the file by hand, live**:

> «щоб, грубо кажучи, **в лайв режимі я міг це прийти і це переглянути**» — **[449]**

**This exact failure is on the record, twice.**

1. **FIELD-NOTES §2.1 (VERIFIED).** `state/attention` was rebuilt from scratch every cycle
   (`: > attention.tmp` then `mv attention.tmp attention`). The context watch wrote corrections there
   all night and *"only discovered this at 2026-09-13T06:58Z, by grepping for a block it had written
   four minutes earlier and getting nothing back."* Cost: **`STALLED` raised against demonstrably
   healthy sessions eight or more times across about seven hours** (§11.3). Two writers, one file, no
   protocol — seven hours of false alarms.
2. **FIELD-NOTES §11.7, issue `#82`, still open (VERIFIED).** *"the `STOP` write is still unconditional
   on the marker write succeeding, so a failed marker write leaves an unattributed `STOP` on disk."*
   Its two predecessors `#65` and `#73` are the same bug in the other direction: an auto-pause that
   resumed instantly, then a fix that made *"a restart landing in that window read `STOP` as a manual
   owner stop and exit instead of resuming."* Three incidents from one missing author field.

**Concrete failure — a stop that is silently undone.** 01:30. He has the control file open in an editor
because he is doing exactly what [449] describes — reviewing it live. At 01:34 he decides to stop the
run, switches to another terminal, and runs `/orchestrator:stop-hard`. The command rewrites the file
with `stop: hard` ([520]). At 01:36 he switches back to the editor, adds a note to the account section,
and saves — writing his **stale buffer**, which has no stop line in it. The file's digest changes. The
orchestrator reads it on the next tick, sees no stop, sees a changed account section, and classifies
the change as a config edit. The run continues all night. He went to bed believing it was stopped, and
Д11 guarantees nothing told him otherwise.

**Concrete failure — the reverse.** 03:05, the weekly limit hits his configured threshold; the
orchestrator writes its own stop into the polled file, per R1-06. 03:40, the five-hour window resets
and the orchestrator wants to resume, so it clears the stop. But at 03:20 the owner wrote a manual
stop-hard into the same field. The orchestrator cannot tell its own stop from his, clears both, and
resumes a run he stopped. This is `#65`/`#73`/`#82` reproduced exactly, in a design that has not yet
been written.

**What the decision does not answer.** Whether the stop is a field inside the config file (so a
config writer can drop it) or a separate artefact whose existence is the signal; whether a writer
re-reads before writing; whether there is any author attribution at all. [520] says only *«в цьому
файлі відповідно конфігурується хард стоп чи софт стоп»*.

---

## A4 — Д1's precedence puts an arbitrary repository above the plugin's defaults · **blocker**

**The decision.**

> «Це треба робити відповідно до того, які є правила в клад маркетплейсі, який я робив для <company>… там є відповіді на ці питання. Наступне питання» — **[416]**

**The hole.** Following that literally, the six slots are (VERIFIED, `config-levels.md` §"The shape"):

```
slot 6  ./.claude/shared/plugins/<plugin>.local.json   personal project   (highest)
slot 5  ./.claude/shared/identity.local.json           personal project
slot 4  <config-root>/shared/plugins/<plugin>.json     user
slot 3  <config-root>/shared/identity.json             user
slot 2  ./.claude/shared/plugins/<plugin>.json         project committed
slot 1  ./.claude/shared/identity.json                 project committed  (lowest of the six)
```

Slots 1 and 2 are **files inside the checkout, tracked by the project repository** — VERIFIED, the
table in §2 labels them *"committed, tracked by the project repository"*. They rank below his own four
files, which is correct and safe **for a key he has set**. For a key he has **not** set, the highest
slot that defines it is the repository's, and the repository beats the plugin's built-in default.

That design was written for a plugin invoked for seconds, in his own repositories, by him, at a
keyboard — §9 of the same document, VERIFIED: *"On every invocation, the agent executing a plugin reads
the resolved config before that plugin performs any of its own work."* The orchestrator is a process
that runs unattended for thirty-four hours, in whatever repository it is pointed at, with the autonomy
limits of R1-14 and the red lines of R1-15 among its settings.

**Concrete failure.** Night one on a client repository he cloned this afternoon. He has configured the
orchestrator globally (slot 4) with the handful of things he cares about: notification channel, board,
concurrency. He has set nothing in this project. The repository ships
`.claude/shared/plugins/orchestrator.json` — a legitimate-looking committed file, because committing
plugin config is what this marketplace design is *for*. It sets `autonomy: full`,
`questions_channel: docs/agent-questions.md` and `notifications: none`. All three are unset in his own
files, so all three win. At 03:00 the orchestrator merges to `main` without asking, writes its
questions into a file he has never heard of, and notifies nobody. He wakes to a green report.

**And the veto key inverts too.** VERIFIED, `config-levels.md`: `never` accumulates across a person's
files, *"and a committed-project `never` holds against everything except a tool one of the person's own
files names in `use`."* So a repository can also **remove** a capability the orchestrator needs — a
`never` on his notification transport, on a git operation, on a provider — and nothing in the interview
contemplates a third party contributing to the orchestrator's restriction set.

**Where this collides with his own other words.** R1-15:

> «має бути якісь визначене місце, де може людина додавати якісь різного типу обмеження» — **[357]**

*«людина»* — the person. Under Д1's precedence, the repository is also in that place.

**What the decision leaves undefined.** Whether the orchestrator reads slots 1 and 2 at all; whether an
unattended run treats a committed config as trusted input; whether a plugin default outranks a
repository value when the owner is silent. [416] answers none of these — it points at a document and
closes the topic in the same breath, and the interviewer's restatement at [417]/[418] was never
answered ([419] moves to Д2; `../extract/corrections.md:99`, VERIFIED).

---

## A5 — The watched config files are written by other plugins and by git · **blocker**

**The decisions.** Д7 [458]: a change made during the run must be read and applied. R1-04:

> «коли вона робить просто ран, то система починає щитувати чи є якісь налаштування глобальні, або на
> проєкті, і відповідно цього дії» — **[133]** (the one item in this cluster that *is* ratified)

Д1 [416] fixes which files those are. Composing the three: the orchestrator live-watches slots 1–6 for
changes and applies them by type.

**The hole.** Three of those six files are not the orchestrator's. His own design says so explicitly —
VERIFIED, `config-levels.md` §"What a write must do":

> **"A general config file is shared on purpose: plugins in this marketplace write it, and so do
> writers outside this marketplace that this design knows nothing about."**

On this machine that is not theoretical. VERIFIED by grep: `~/.claude/shared/identity.json` — slot 3 —
is read or written by **clickup, g-event, log-time and find-call**, four plugins live in production.
`plugins/clickup/commands/onboard.md:6` states it outright: *"identity writes
`~/.claude/shared/identity.json` (shared with `/g-event`)"*.

And slots 1 and 2 are **tracked files in the working tree** (A4), so `git checkout`, `git merge`,
`git pull` and a branch switch all rewrite them — which is what the orchestrator's own lanes do all
night under Д4.

**So a change can arrive in the watched set with no human author, no intent and no type.** R1-07's
entire mechanism assumes the opposite: *«якщо в моменті щось змінюється, то вказується, який тип цієї
зміни»* [195] — *it is indicated*. By whom, when `/clickup:onboard` wrote it?

**Concrete failure — another plugin.** 02:10. He cannot sleep, opens a second terminal for unrelated
work, and runs `/clickup:onboard identity` to fix a stale list alias. That command rewrites slot 3. The
orchestrator's next tick sees a new digest on a watched file with no `type` field. Two implementers:
one defaults an untyped change to `soft` and quietly reassigns roles at the next task boundary based on
a file that changed for reasons nothing to do with it; the other defaults to `hard` and stops the
current work at 02:10. Neither is wrong by [195]. He gets one of them at random.

**Concrete failure — git.** 04:20. A lane finishes and merges `main` into its worktree to rebase. A
colleague's commit three days ago touched `.claude/shared/identity.json`. Slot 1's content changes
mid-run, under the orchestrator's own hands. Plus the measured wrinkle from the research (§3.2,
VERIFIED on this machine): **rewriting a file with identical content moves its mtime** — so even a
`git checkout` that restores the file byte-for-byte fires the change detector he hedged toward
(*«Можливо, там, наприклад, по даті»* [195]).

**What it does not answer.** Whether an untyped change is soft, hard, or ignored. Whether a change the
orchestrator itself caused counts. Whether the watched set is the six config slots, or only a separate
control file — and if the latter, then Д7's *«навіть якщо в мене в дефолтній налаштуванні інше»* [458]
has no mechanism, because the defaults live in the slots and nobody is watching them.

---

## A6 — An account switch is a config-root switch · major

**The decision.**

> «Наприклад, в моєму випадку це перемикач профілів, який використовує різні профілі» — **[199]**

(VERIFIED: a profile switcher is installed here.)

**The hole.** VERIFIED on this machine:

```
$ <switcher> switch --print-env <profile-A>
export CLAUDE_CONFIG_DIR="<profile-dir>"
```

That is the **only** variable it sets. And `CLAUDE_CONFIG_DIR` is what his own marketplace resolves
`<config-root>` from — VERIFIED, `config-levels.md`: slots 3 and 4 are `<config-root>/shared/…`.

So R1-07's account move — a control-plane event, described in [195] as a routine soft/hard change —
**silently swaps two of the six configuration slots**. The role does not merely bill elsewhere; it
reads a different user-level configuration. Nothing in the interview and nothing in `config-levels.md`
anticipates this.

**Concrete failure.** 02:00, the executor role is moved from `<profile-A>` to `<profile-B>` to spread quota. The
`<profile-B>` profile was set up months ago for other work. Its `<config-root>/shared/plugins/orchestrator.json`
does not exist, so every key the owner had set at the user level for this run — concurrency ceiling,
notification channel, the `never` list he accumulated — reverts to whatever slots 1, 2, 5 and 6 supply,
which under A4 may be the repository's. The executor spawned at 02:01 has a different safety posture
from the one spawned at 01:59, for the same task, in the same run, because he changed an account.

**Where R1-15 makes this sharper.** He asked for a prohibition file:

> «Достатньо лише одного файлу, який може доповнюватись, текстописний, де будуть деталі щодо якихось
> заборон, виключень, тощо» — **[357]**

If that «визначене місце» is under the config root, the red lines move with the billing identity. If it
is in the project, they do not. **He never said which**, and the two answers differ in whether a
2 a.m. account change can remove his only safety floor. ADAPTER-CONTRACT §H is blunt about what is
underneath it (VERIFIED): on a sandbox-less platform the text file is *"the only barrier, and a model
that ignores it has nothing beneath it."*

---

## A7 — A live account assignment is never preflighted · major

**The decision, in his own words, is a preflight requirement:**

> «І це треба налаштовувати, та переконувати, що це працює. Тобто, **перед запуском** потрібно
> переконатися, що це працює, щоби це не було проблемою для користувача» — **[199]** · ratified

**Against which:**

> «якщо в моменті щось змінюється» — **[195]**

**The hole.** The verification is bound to *«перед запуском»*. The assignment is editable *«в моменті»*.
Nothing covers the case that matters most: an account named for the first time at 02:00, by a hand-edit,
in a file whose whole purpose is that it is applied without restarting anything.

**Concrete failure.** 02:00, he adds `executor.account = <profile-B>` to the polled file. That profile's
OAuth token expired three weeks ago — he last used it in August. The orchestrator applies the change
and spawns the next executor under it. FIELD-NOTES §11.7 (VERIFIED) records exactly this class of
event surviving for hours: *"The usage endpoint returned `authentication_error` for an extended
stretch, blinding every cap read, with nobody re-authenticating. 2026-09-02T13:52-15:14Z"*, and
separately *"my limits position was measuring the wrong account"*. Each spawn dies in seconds. The
orchestrator's liveness check reads a session that died at launch as a stall (FIELD-NOTES §1.5:
*"Heartbeat staleness is not a stall"* is a note about the inverse error, and §11.3 records eight false
`STALLED`s in seven hours). The night is spent respawning into a dead account, and Д11 means nothing is
printed.

**And on macOS there is a worse branch.** ADAPTER-CONTRACT §F (VERIFIED as read): *"On macOS, Claude
Code may raise a **Keychain GUI dialog** on an account that has never been granted access — an
unattended run blocks on a dialog nobody sees."* At 04:00 that is not a failure the run recovers from;
it is a modal window on a locked screen.

**And the hard variant cannot be honoured at all.** ADAPTER-CONTRACT §F, VERIFIED: *"on **every**
platform, changing a *running* session's account is impossible — so R1-07's **hard** account change
('applies now, stops current work') is always a stop-and-relaunch with a context re-seed, never an
in-place switch."* [195] describes `хард` as *«треба прямо вже зробити»*. What is actually done is kill
the session, lose its context window, relaunch, and re-seed from a written position — which is R1-08's
and R1-10's whole problem surface, invoked by what looks like a one-line config edit. The decision
offers the user a knob whose real cost is invisible from the knob.

---

## A8 — `stop-custom` is two execution models under one name · major

**The decision.**

> «думаю що це має бути 3 варіанти, stop-hard, stop-soft, stop-custom що означає прочитати що це
> означає і відповідно зробити. Там користувач може налаштувати що це таке та яка зупинка буде. Там
> омжуть бути **текстописні правила чи команди**.» — **[524]**

**The hole is in «чи».** Prose rules require a model to read and interpret them. Commands require a
shell to run them. These have opposite failure modes, opposite latencies, opposite trust properties —
and one name.

**Д12 is the one item the interviewer itself left open** — [525]: *«Доповнення до Д12 отримано;
підтвердження залишається відкритим»* (VERIFIED, `../extract/corrections.md:105`). The session ended
mid-answer at [520] and resumed by typed text at [524] (`corrections.md:139`).

**Concrete failure — prose, at the worst moment.** His custom rule reads: *"finish anything within ten
minutes of done, push its branch, open a draft PR, then stop."* 03:00, the weekly limit reaches 100% —
which is one of the main reasons a stop fires at all. The orchestrator must now make a model call to
interpret that paragraph. Its own account is the one that just ran out. The interpretation fails, or
falls back to a different account (A6, A7), or is attempted by a cheaper model that reads "ten minutes"
against a task with no elapsed-time record. Nothing in [524] says what happens when the interpretation
cannot be made. The three plausible degradations — stop hard, carry on, retry — are as far apart as
outcomes get, and an implementer picks one.

**Concrete failure — prose, non-determinism.** Same rule, two nights. Night one the orchestrator reads
"finish anything within ten minutes of done" as "let the running tasks complete" and runs another 40
minutes. Night two it reads it as "kill anything not nearly finished" and stops in 90 seconds. Both are
faithful readings. The owner has no way to know which he got, because Д11 forbids output:

> «оркестратор не повинен нічого виводити для мене» — **[508]**

and because **a model-written record of its own behaviour is not evidence on this codebase**:
FIELD-NOTES §12.7, VERIFIED — *"A security review of a single API read found 26 refusal events in the
audit log that never occurred."*

**Concrete failure — commands.** The custom stop is a shell command. FIELD-NOTES §11.8 (VERIFIED):
*"`pkill -f 'playwright test'` killed an unrelated lane, because every lane's own prompt text contains
that literal string, so `pgrep`/`pkill` over-match sessions rather than suites."* A user-written stop
command is exactly where that pattern gets written, and R1-16 is his rule against it:

> «він би не мав зупиняти якісь там тести, які не він запускав» — **[366]**

**Where "the user configures it" moves the problem onto someone who cannot know the answer.** *«Там
користувач може налаштувати що це таке»* [524]. To write a correct custom stop, the user must know:
which boundaries a session can be interrupted at on each platform (ADAPTER-CONTRACT §G: on Gemini CLI
headless *"a mid-run prompt aborts the turn"*); whether their command runs before or after sessions are
signalled; what happens if it exits non-zero; and whether it runs once or every tick while the stop
stands. None of that is knowable from the outside, and there is no listed platform on which it is the
same.

---

## A9 — «оркестратор чи контекст вочер» — the polling actor is undecided, and it is the whole reliability argument · major

**The decision.**

> «це має бути налаштовано через єдиний файл, який **оркестратор чи контекст вочер** постійно дивиться» — **[195]**

**The hole.** This reads like a shrug about implementation detail. It is not: it decides whether a stop
works when the orchestrator is the thing that is broken.

**Concrete failure — the orchestrator polls, and is compacting.** R1-08's hard mode, in his words:
*«хард, прямо вже зупинити, зробити компакт, і продовжити»* [204]. During a compact the orchestrator is
not ticking. FIELD-NOTES §1.1 and §1.2 (VERIFIED): *"A session cannot compact itself"*, and
*"`/compact` lands only when the target has no shell running."* So the compaction of the orchestrator
is itself an operation of uncertain duration driven from outside. He writes `stop-hard` at 03:02; the
orchestrator is mid-compact; the stop is read at 03:11 or not at all.

**Concrete failure — the orchestrator polls, and is dead.** R1-10 says a dead orchestrator is restarted:
*«Заново запустити оркестратора»* [300]. He writes `stop-hard` at 03:00 into a file nothing is reading,
because the orchestrator died at 02:48. The liveness watcher, which is not reading the control file
either (that was the other branch of «чи»), relaunches per R1-10. Now either (a) the new orchestrator
reads the stop and exits, the watcher sees a dead orchestrator again, and relaunches — a loop; or (b)
the relaunch path treats a stop older than its own start as stale and clears it, and the run he stopped
resumes. FIELD-NOTES §12.5 records the shape of (a) already happening: *"A 45-minute false-positive
rate-limit-banner loop on a healthy orchestrator… re-detecting and re-issuing resume kicks about every
66 seconds."*

**And (b) collides head-on with his hardest invariant.** [300]:

> «не може бути такого, що вже якісь існуючі оркестратор і спускається наступний, тому що тоді це буде
> просто нескінченний цикл оркестраторів… якщо раптом одночасно два якісь оркестратори працюють, то це
> не окей»

If the watcher polls the control file (the other branch of «чи»), the invariant is satisfied but a
second actor now sits between him and the run, and [300] governs only the orchestrator — it says
nothing about how many watchers there may be, or what happens when the watcher is the one that dies.

**What two implementers build.** One puts the poll in the orchestrator's tick loop, which is the simple
thing he asked for four times (*«це має бути надійна річ, дуже проста»* [300]) and fails in the two
scenarios above. One puts it in the watcher, which survives both and adds an actor to a design whose
single-instance rule is his most emphatic. He said «чи»; both are his.

---

## A10 — The control file is in the project, and Д4 puts every task in a worktree · major

**The decisions that collide.**

> «Це в той файл, який оркестратор на постійний основі читає» — **[520]**

> «Дефолтна пропозиція, щоби **абсолютно все виконувати в різних ворк трі**» — **[433]**

And Д6, which puts a second user-placed file into the same collision:

> «це може бути локальний файл… **місце визначається користувачем**» — **[449]**

**The hole.** A git worktree gives every lane its own copy of every tracked file. A path resolved
relative to the current directory resolves to a different file per lane. Nothing detects it.

**This has already happened, once, and it is on the record.** FIELD-NOTES §12.5 (VERIFIED):
*"**`QUESTIONS.md` and `JOURNAL.md` forked into a worktree's own copy**, and a real owner-facing
question sat there invisibly for an hour."* `ORCHESTRATION.md:489-494` records the rule the run then
grew: absolute path into the main checkout, always, *"whatever directory that lane is running in"*, and
*"At merge, take the main checkout's version of both files whole."* Twenty-three journal entries were
on the wrong side too.

**For a question channel that cost an hour. For a stop file it costs the night.**

**Concrete failure.** 01:15. He is reviewing the run. His editor's project root is
`~/Work/.../<work-project>-phase-7` — the lane worktree — because that is where the diff he was reading
lives. He opens the control file from the sidebar and sets `stop: hard`. It is a tracked file, so the
worktree has a copy, and the copy is what he edited. The orchestrator polls the main checkout. Nothing
changes. He closes the laptop.

**The command path is not obviously safer.** [520] says the stop is issued by a command:
*«окрема команда до цього плагіна»*. A command resolves its target from its own working directory. The
existing harness's `hproject_root` already has to special-case this (`hlib.sh` carries
`_is_project_worktree`, VERIFIED), which means the previous generation met the problem and patched it
rather than designed it away. Nothing in [520] says the command must resolve to the main checkout, and
a reimplementation that uses `git rev-parse --show-toplevel` in a worktree gets the worktree.

**What Д6 adds.** *«місце визначається користувачем»* [449] means the questions channel may be a path
he chose. A path inside the repository forks. A GitHub issue cannot fork. The decision permits both and
distinguishes neither, so whether his answer reaches the run depends on a choice he made during
onboarding for unrelated reasons.

---

## A11 — No defaults are named, and the first run's 23:00 answers become every later run's silent global default · major

**The decision.**

> «людина сама налаштовує цей оркестратор, конфіг при першому запуску, або просто конфігурує його без
> жодного запуску… коли вона робить просто ран, то система починає щитувати чи є якісь налаштування
> глобальні, або на проєкті, і відповідно цього дії. **Якщо чогось немає, то оркестратор задає ці
> питання для того, щоби їх покрити**» — **[133]** · ratified

**The hole — part one: the question count is unbounded, because everything is configurable.** Across
this interview, *«це налаштовується»* or its equivalent is the answer to R1-03, R1-05, R1-08, R1-11,
R1-12, R1-13, R1-17, Д7 and Д12. The compaction answer alone [204] names five separate knobs per role
per platform (threshold, mode, compact-or-respawn, which command or skill, whether a prompt follows).
There is exactly **one** named default in the whole cluster — Д7's *«по дефолту я б рекомендував, що він
залишається та чекає»* [455].

So on a first run, [133] fires for nearly everything. That is a wizard standing between the owner and
sleep at 23:00, and it collides with the constraint he stated four separate times:

> «тут нічого надприроднього не потрібно вигадувати» **[171]** · «це має бути **дуже простий процес**» **[189]** ·
> «це має бути надійна річ, **дуже проста**» **[300]** · «я не хочу якихось детерміністського варіанту для
> цього, тому що він буде дуже складний оверінжиринг, але дуже якісь простий та надійний варіант» **[370]**

The alternative — the orchestrator picks silently — is the thing [133] exists to prevent.

**The hole — part two: where the answers land, and what that means on the second run.** Д1 sends this
to his marketplace, whose write rule is VERIFIED in `config-levels.md`:

| condition | destination |
|---|---|
| one of the person's own files already sets this key | that same file |
| the setting is usable by more than this one plugin, or its reach is not established | `<config-root>/shared/identity.json`, **slot 3** |
| anything else | `<config-root>/shared/plugins/<plugin>.json`, **slot 4** |

Both fallbacks are **user level** — *"one person's settings on one machine, and they apply in every
project that person opens."* And: *"An answer is always written, and always into the one file the list
above resolves to. That destination is not negotiable."*

**Concrete failure.** 23:40, first run, on a scratch repository. The orchestrator asks whether it may
merge to the main branch by itself. He is tired, it is a toy repo, he says yes. The answer is written
to slot 4 — his machine, every project. Two weeks later he points the orchestrator at a client
repository. [133] checks for settings, finds one, and **does not ask**. At 03:00 it merges to the
client's `main`. Nothing was wrong: the rule is "use what is there, ask for what is missing", and it was
not missing.

**And the marketplace's own safety valve requires a human.** VERIFIED, same section: *"A write into a
layer that a higher layer would shadow is announced first… **Nothing is written until the person
chooses.**"* At 04:00 nobody chooses. If a run-time answer must be persisted mid-run, the orchestrator
either blocks on a prompt nobody sees, or breaks his own rule. [133] does not say which, because it was
written for a configure-then-run flow, not for a process that keeps asking at 04:00.

**What it leaves undefined.** Whether "this run" is a scope at all. His marketplace closes the level set
— VERIFIED, `config-levels.md`: *"These three levels are the whole set… A resolver supports no other
level"*, and of a level he removed, `OWNER-DECISIONS.md:169`: *"do not build it, do not reserve a path
for it, do not mention it as an option."* Yet Д7 [458] requires a live edit to beat *«якщо на початку я
обрав інший варіант»* — the run's own start-time choice — which presupposes that the run's choice is a
distinguishable thing. If the run's choice is written into slot 4, then Д7's "the live edit beats the
run's choice" and "the live edit beats the default" are edits to the same file, and there is no rule
that orders them.

---

## A12 — The control file's scope is undefined · minor

**The decision names no scope.**

> «єдиний файл, який оркестратор чи контекст вочер постійно дивиться» — **[195]**

Whereas R1-04 [133] establishes that configuration is *«глобальні, або на проєкті»* and R1-12 adds a
third: *«налаштування можуть бути типовими, проєктними чи перевизначеними для конкретного запуску»*
[335], confirmed at [336].

**The hole.** An implementer reading [195] and [133] together naturally puts the control file at the
same levels as everything else. But precedence is meaningless for an event. Whether `~/.orchestrator/STOP`
and `./.orchestrator/STOP` both exist, which wins, and whether a merge rule even applies to a stop,
is unaddressed.

**Concrete failure — one machine, two runs.** He runs the orchestrator overnight on `<work-project>` and on
`claude-plugins` (he does both; this repository is in production with a 475-test harness). At 02:00 he
decides the `claude-plugins` run is going badly and runs `/orchestrator:stop-hard`. If the control file
is user-scoped, both stop. If it is project-scoped and his terminal's cwd was wrong, the other one
stops. Either way one run he wanted is dead and one he wanted dead is running, and Д11 means neither
tells him.

**Concrete failure — the detector he hedged toward.** Measured on this machine (research §3.1, VERIFIED):

| detector | two writes in the same second | verdict |
|---|---|---|
| `stat -f '%m'`, `date -r`, `find -newer` | **missed** | unusable |
| `stat -f '%Fm'` (APFS nanoseconds) | detected | usable |

His own hedge is *«Можливо, там, наприклад, по даті, перевіряти, коли він був змінний»* [195] — and
ANALYSIS-01 recorded this as the mechanism, which `../extract/corrections.md:61` flags as a
mis-statement. Read at second granularity it loses a stop written in the same second as a preceding
edit — the `stop-hard`-typed-immediately-after-a-config-tweak case, which is exactly how a person uses
one file for both. And per research §3.9, VERIFIED here: *inside a Claude Code bash session `find` is a
shim, not `/usr/bin/find`*, so the detection command behaves differently in his terminal and in the
run's.

This is minor only because the mechanism is openly hedged and the research measured a working
replacement. It is listed because ANALYSIS-01 currently carries it as a decision.

---

## What I did not attack, and why

- **That the run must pick up a mid-run change at all (Д7).** It is the strongest requirement in the
  cluster, he marked it «дуже важливо» himself, and every comparable tool agrees: Symphony's SPEC makes
  dynamic reload a MUST, Claude Code watches its own settings files and reloads them live, Sortie
  claims the same. The attacks above are about *what* reloads and *how a change is attributed*, never
  about whether.
- **That the stop should be a file rather than a signal.** ralphex uses `SIGQUIT` (VERIFIED in
  `cmd/ralphex/break_unix.go`); a signal needs a pid and a live terminal, and the owner's whole premise
  is a run he walks back to in the morning. His choice is better than the alternative and I could not
  make it fail.
- **That precedence should follow his marketplace (Д1) at all.** A4 attacks one consequence of applying
  it literally to an unattended process in a foreign repository. The ranking itself — a person's own
  files above the project's, personal-project highest — survived everything I aimed at it.
- **That the questions channel is user-placed (Д6).** He has already built and run it by hand, and the
  protocol on disk (`docs/open/{QUESTIONS,ANSWERS}.md`: append-only, one writer per record, a `Fallback:`
  on every question, a 60-second poll) is stronger than anything I would have proposed. A10 attacks
  where the file sits, not how it works.

---

## Sources

**Transcript** — `../../round-1/TRANSCRIPT-01.md`, rows [133], [171], [176], [189], [195], [199],
[204], [209], [270], [300], [335], [357], [366], [370], [416], [433], [449], [455], [458], [508],
[520], [524], [525].
**Analysis and extraction** — `../../round-1/ANALYSIS-01.md`; `../extract/corrections.md:61,86,99,101,102,105,139,180`.
**Cluster research** — `C2-config-control-plane-research.md` §§2.1, 2.8, 3.1–3.10, 4.1–4.9.
**Field evidence (VERIFIED)** — `../../../../plugins/harness/docs/FIELD-NOTES.md` §§1.1, 1.2, 1.5, 2.1,
11.3, 11.7, 11.8, 12.5, 12.7.
**His marketplace (VERIFIED, read on this machine)** —
`<baseline-marketplace>/docs/config-levels.md`
(the slot table, the write-destination table, the shared-file warning, the lock rule, "these three
levels are the whole set"); `requirements/OWNER-DECISIONS.md:169`.
**This repository (VERIFIED)** — `plugins/harness/bin/hlib.sh` (`cfg`, `hstop_file`, `stop_requested`,
`atomic_write`, `_is_project_worktree`); `plugins/harness/bin/harness-run.sh:243-244`;
`plugins/clickup/commands/onboard.md:6`; grep for `shared/identity.json` across `plugins/`.
**Platform contract** — `../platforms/ADAPTER-CONTRACT.md` §F, §G, §H, §6.4, §6.7.
**Measured on this machine, 2026-09-19/21** — `<switcher> switch --print-env`; `stat -f '%m'` vs `%Fm` on
APFS; mtime on identical-content rewrite; `find` shim inside a Claude Code session.

**Currency note.** The profile-switcher, filesystem and plugin-grep measurements are of this machine as it
stands on 2026-09-21. The ADAPTER-CONTRACT findings quoted for A7 were gathered 2026-09-19 against CLIs
that ship daily to weekly; the account-switch impossibility is a property of how these tools bind
credentials at process start and is unlikely to move, but the Keychain-dialog behaviour is a
macOS/Claude Code interaction that could change in any release.
