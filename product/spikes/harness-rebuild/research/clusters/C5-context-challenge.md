# C5 — Context-window management and compaction · adversarial pass

Cluster: **C5-context** · Item: **R1-08** (rows `[204]`, `[209]`, `[212]`) · Date: **2026-09-19**
Read first: `research/clusters/C5-context-research.md`

This document attacks. It does not redesign. Every entry names a decision the owner made, the hole in
it, and a concrete situation in which that hole produces a bad outcome. Evidence is marked
**VERIFIED** (read in the transcript, the field notes, the supervisor prompts, the plugin source, or a
file on this machine), **CLAIMED** (a third party asserts it), or **INFERRED**.

Twelve attacks survived. Five are blockers — the decision, as stated, cannot be executed on the
platform he named, or it contradicts another decision he made. Six are majors: two competent
implementers would build different things, or the thing built fails on a night nobody is awake. One
is minor.

Nothing below overwrites a decision. Where a challenge collides with his own words, both sides are
quoted verbatim with their row anchor.

**One fidelity note that shadows the whole cluster.** Of the four R1-08 restatements, two were never
answered. At `[213]`/`[214]` he said «Повтори ще раз»; the interviewer repeated at `[217]` and then
declared **«Підтвердив, зафіксував. Що далі?»** `[218]` — *he said nothing in between*. At
`[220]`/`[221]` he said «Яке наступне питання? Чи повтори будь ласка», it repeated at `[224]` and
moved to R1-09. So the phrase the research leans hardest on — the guaranteed-execution requirement as
*formulated* — is the interviewer's sentence, not his. His own words at `[204]` are safe and are what
this document attacks. Ratified in this cluster: only `[212]` «Так, правильно», and only for soft
mode's step boundary. (**VERIFIED** — `research/extract/corrections.md` §C; transcript rows read
directly.)

---

## Index

| # | Attack | Severity |
|---|---|---|
| A1 | «гарантовано робить цю дію» names an adjective, not an observable — and the only trigger on his platform is typed text that is measured to fail silently | **blocker** |
| A2 | «при скількох відсотках» — there are two percentages on his own machine, ~13 points apart, and he never says which one | **blocker** |
| A3 | «компакт, який буде робити оркестратор» — the orchestrator cannot do it to itself, and `[195]` leaves the actor open | **blocker** |
| A4 | Soft mode's «поточного кроку» is unobservable from outside, and least observable in exactly the session that fills fastest | **blocker** |
| A5 | «запускати повністю новий оркестратор» collides head-on with the single-orchestrator invariant at `[300]`/`[301]`, and the path was measured to fail twice | **blocker** |
| A6 | Hard mode's «зупинити … і продовжити» has no safe point and no definition of what continues | major |
| A7 | «софт хард» means three different things in three answers, in a system he wants driven by one file | major |
| A8 | A compaction and a stall are the same observation, and the stall response destroys the post-compact prompt | major |
| A9 | «кастомний скіл» has no completion signal and no obligation to free anything | major |
| A10 | The only universally available verification is the one reading that lies — and re-firing on it is what makes compaction permanently impossible | major |
| A11 | There is no default, and «людина налаштовує» hands the user a number whose right value depends on things he cannot see | major |
| A12 | On Claude Code 2.1.278, the exact read path his threshold needs removes the idle signal his soft mode needs | minor |

---

## A1 — «гарантовано робить цю дію» names an adjective, not an observable · **blocker**

**The decision.**

> «І якщо, наприклад, оркестратор наблизився до того числа, ну або, чи перейшов це число, то **повинен
> бути механізм, який гарантовано робить цю дію**, і відпрацьовує так, що сесія компактиться, тощо, і
> так далі» — `[204]`

**The hole.** The sentence defines a trigger («наблизився … чи перейшов це число») and an action
(«цю дію»), and then asserts a property of the mechanism. It names **no observable that says the
action happened**, and **no behaviour for when it did not**. Two implementers read this two ways:
one builds fire-and-forget — send the command, log `compact sent`, move on — and satisfies every word
of the sentence; the other builds detect → act → verify → escalate. Both can point at `[204]`.

**Where it collides with the evidence.** On Claude Code, the only way to compact another session is
to type into its tty, and typed text is the single most failure-prone verb in the whole previous
generation. All **VERIFIED** in `FIELD-NOTES.md`:

- `/compact` landed on **one of three attempts** on the same session in one day. Attempt 1: empty
  input line, shells running → "no change; command consumed as an ordinary message". Attempt 2: empty
  line, no shells → 73 % → 0 % in ~90 s. Attempt 3: empty line, two shells → no change over 4.5
  minutes, and the session **drifted 91 % → 95 % and auto-compacted** (§1.2).
- **Five separate instructions typed into sessions were never delivered** across one run (§1.3).
- A bare Enter does not submit stranded text; `send` types its own text and **destroys** whatever was
  pending; a background task re-invoking the session **discards** an idle input line (§1.3).
- `send` **fails silently above roughly 200 characters** — an ~1100-character message produced no
  error and never appeared (§12.1).
- A 149-minute stall happened because `send`'s Enter never landed on a pane, and **nothing detected
  it**; the owner eventually pushed master himself (§12.1).

Every one of those failures is *silent*. The sender sees success.

**Concrete failure.** 03:48. Orchestrator crosses 80 %. The watcher runs
`harness-term.sh send <tty> "/compact"`. The orchestrator happens to hold two child shells — a
`docker compose up --build` and a poll — so the string is consumed as an ordinary chat message. The
watcher's log line reads `context action sent`. Nothing re-checks. By 05:30 the session is at 95 % and
the platform's own auto-compact fires in the middle of a merge. The morning report says the context
mechanism ran once and succeeded. It never ran at all. This is not a hypothetical: it is attempt 3 in
§1.2, reproduced verbatim.

**What it leaves undefined.** Whether "guaranteed" means the action was *issued*, *admitted*, or
*produced a freed window*. Those are three different products. (**CLAIMED**, opencode's own doc, which
states the distinction outright: *"The response confirms admission; it does not wait for the
summary."*)

---

## A2 — «при скількох відсотках» — there are two percentages, ~13 points apart · **blocker**

**The decision.**

> «Людина може налаштувати, при скількох відсотках відбувається компакт» — `[204]`

**The hole.** "Percent of context" is not one quantity on his own machine, and he does not say which.
**VERIFIED by reading `~/.claude/hooks/gsd-statusline.js`** (his installed GSD status line):

```js
const usableRemaining = Math.max(0, ((remaining - AUTO_COMPACT_BUFFER_PCT) / (100 - AUTO_COMPACT_BUFFER_PCT)) * 100);
const used = Math.max(0, Math.min(100, Math.round(100 - usableRemaining)));   // line 801-802
```

and its own comment at line 815, verbatim: the normalised value *"inflates the context monitor warning
messages by ~13 points (#2451)"*. `AUTO_COMPACT_BUFFER_PCT` defaults to 16.5.

So the number on the bar he has been reading all year and the number `/context` reports differ by
about thirteen points. **The previous generation's thresholds were read off a screen** —
`FIELD-NOTES.md` §3.3: "it is printed on every session's own status line, and the watch loop already
captures every screen each cycle", and the cycle lines record `ctx=NN%` (**VERIFIED**). Every
percentage in the field record — 66 %, 73 %, 74 %, 91 %, 95 % — is therefore of unstated provenance
relative to whatever the rebuild computes.

**Concrete failure.** He configures `percent: 80` meaning the bar he knows. The implementer reads raw,
matching `/context`. 80 raw ≈ 93 on his bar. Claude Code's own auto-compact reserve sits at ~16.5 %,
so the platform fires **before** his threshold is ever reached, every time, in the middle of whatever
the session is doing. His hard mode never executes once in a 34-hour run; his soft mode never
executes once; the run report records zero context actions, which reads identically to "the run never
needed one". The feature is configured, shipped, and dead.

**The mirror failure is worse.** If the implementer reads *normalised* and he meant raw, 80 on the bar
is ~67 raw, and a 1 M-window orchestrator compacts roughly a third earlier than intended — losing
working memory repeatedly through a night for no reason, at ~7 minutes per compaction (`J-WATCH-01`,
67 % → 0 % in about seven minutes, **VERIFIED** `FIELD-NOTES.md` §10.2).

**And it cannot be settled by convention**, because the two platforms he names disagree at the source:
Claude Code's `used_percentage` is computed over the full window, while Codex ships
`model_auto_compact_token_limit_scope` with a `body_after_prefix` mode that explicitly charges only
"sampled output and later growth after the carried window prefix" (**VERIFIED**, research §2.5). The
same configured `80` means different occupancy on each.

---

## A3 — «компакт, який буде робити оркестратор» — the actor cannot act on itself · **blocker**

**The decision.**

> «Людина може налаштувати, при скількох відсотках відбувається компакт, **який буде робити
> оркестратор**» — `[204]`

**The collision with his own earlier answer**, which leaves the actor open rather than settling it:

> «це має бути налаштовано через єдиний файл, який **оркестратор чи контекст вочер** постійно дивиться
> і перевіряє» — `[195]`

**The hole.** He names the orchestrator as the actor at `[204]`, and the list of things needing a
compaction at `[204]` explicitly **includes the orchestrator**: «якщо, наприклад, оркестратор
наблизився до того числа». A model cannot put text on its own input line — `FIELD-NOTES.md` §1.1,
**VERIFIED**, stated as the governing constraint of the whole previous generation: *"A model has no
way to put text on its own input line."* So the one session he cared about most cannot be compacted
by the actor he named.

**And the previous generation's workaround is self-contradictory in its own documents.**
`WATCHER-PROMPT.md` line ~162 (**VERIFIED**, read on this machine) tells the context watch:

> "**So compact yourself, on your own initiative, at about 85 per cent.** Run `/compact` in your own
> session"

while `FIELD-NOTES.md` §1.2 records that `/compact` lands **only when the target has no shell
running** — and the only mechanism a session has for typing into its own tty *is* a shell. The two
attempts that failed had shells running; the one that worked did not. Either the instruction is
self-defeating, or it depends on a timing exception nobody wrote down. Nothing in `[204]` resolves
which.

**Concrete failure.** 04:10, no human. Config, faithfully transcribed from `[204]`:
`roles.orchestrator: {percent: 80, action: compact, actor: orchestrator}`. The orchestrator reaches
81 %. It reads its own threshold, agrees it is exceeded, and has no verb. It writes a line saying so —
consuming more context — re-checks, agrees again, writes again. The field record already contains this
exact shape: an 85-minute self-sustaining loop that *"nothing internal detected"*, ended only by an
external `SIGTERM`, with line 5620 of the log reading **`NO ONE IS BEING TOLD`** (§11.6, **VERIFIED**).

**What it leaves undefined for two implementers.** One builds a separate watcher process that owns the
trigger for every session including the orchestrator — which contradicts «який буде робити
оркестратор». The other makes every session responsible for its own window — which is what
`ORCHESTRATION.md` line 150 actually did (*"A lane watches its own context window, because nothing
else does"*, **VERIFIED**) and which §1.1 says is impossible. Both are defensible readings of the
transcript.

---

## A4 — soft mode's «поточного кроку» is least observable in the session that needs it most · **blocker**

**The decision**, and the only ratified statement in this cluster:

> «Лише поточного кроку, але це можна налаштовувати, людина може сама налаштувати, що це означає»
> — `[209]`, ratified «Так, правильно» `[212]`

**The hole.** The step boundary is a property of the *supervised* session's internal state, and the
thing that must wait for it is *outside* that session. The only externally visible signals are
busy/idle and the shell count, and the field record establishes that both are forgeable — **by
accident, in ordinary operation**:

- **VERIFIED**, §2.2: a lane held one shell running `until grep … sleep 5` against a file that had
  finished being written **forty-five minutes earlier**. "The pattern could never match, the loop
  could never end, and no check would ever have called that session parked."
- **VERIFIED**, §2.2: a different lane accumulated **58 concurrent child shells**, each a `sleep 590`
  poll, spawned roughly every two minutes for two hours.
- **VERIFIED**, §1.5: "A session heartbeats **between** turns. A validator running a 14-minute suite
  … does not heartbeat at all." The engine nudged six healthy sessions on that basis in one run.

**The scenario that kills soft mode is already on file, measured.** `w-phase-19` (§3.1, **VERIFIED**):
**3,466 of 3,626 Bash calls were the literal command `echo idle`**, mean interval 2.54 s, ~1,400 an
hour, for three and a quarter hours. It added **445k tokens of context — 77 % of all context growth in
that window** — and reached **91 %**. It committed nothing during that time; it never went idle; it
never crossed a step boundary.

**Concrete failure.** Soft mode, `step = "plan committed"`, threshold 75 %. 13:50 the lane starts
polling. 14:30 it crosses 75 %. The watcher arms and waits for the step boundary, correctly, as
configured. 17:05 the lane is at 91 % having produced nothing, and the platform's auto-compact takes
the decision instead — mid-poll, and the polling resumes afterwards. Soft mode behaved exactly as
specified and never fired. **The session that most needed the mechanism is the one for which the
mechanism's wait condition is never satisfiable.**

**And «людина може сама налаштувати, що це означає» is where the problem is moved, not solved.** The
user must define a step boundary that a *different process* can observe, for a session running an
engine he did not write, at a moment he is asleep. Nothing in `[204]` or `[209]` obliges the
supervised session to *emit* a boundary, so the definition is a detection problem handed to the
person least able to test it.

---

## A5 — «запускати повністю новий оркестратор» collides with the invariant at `[300]`/`[301]` · **blocker**

**The two decisions, both his.**

> «оркестратор можна як компактити, так і **запускати повністю новий оркестратор**, що також може бути
> окей, і людина може це налаштовувати» — `[204]`

> «Дуже важливо, що **не може бути такого, що вже якісь існуючі оркестратор і спускається наступний**,
> тому що тоді це буде просто нескінченний цикл оркестраторів. … Якщо, наприклад, запустився
> оркестратор, або щось запустилось, але воно не спрацювало, **переконуєш що воно не спрацювало, а
> після того запускаєш новий**. … якщо раптом одночасно два якісь оркестратори працюють, то це не
> окей» — `[300]`, and «**Це треба відслідковувати і не дозволяти**» — `[301]`

**The hole.** `[300]` makes replacement conditional on **proving the previous orchestrator failed**.
In the R1-08 case the previous orchestrator has **not** failed — it is healthy, mid-run, holding
lanes, and merely full. The precondition `[300]` demands can never be satisfied, and `[301]` upgrades
the invariant from detection to **enforcement** («не дозволяти»). So the guard he specified in R1-10
forbids the action he permitted in R1-08, and neither answer knows about the other.

**The previous generation hit exactly this and left a written verdict.** `WATCHER-PROMPT.md` lines
113–124, **VERIFIED** on this machine:

> "**The close-and-respawn procedure this section used to carry does not work on this setup, and it
> was proved not to work rather than assumed.** `harness-spawn.sh close` deliberately never
> force-closes a session that has a running job, and **this orchestrator always holds an armed
> monitor** — so the close can never complete, and the `spawn` that follows fails with
> `session orchestrator already registered`. Worse, each attempt sends `/exit`, which raises the
> background-work dialog and **blocks the orchestrator at a prompt it did not choose to face**.
> Attempting it manufactures the exact outage this watch exists to prevent. It was tried twice on
> 2026-09-02; both times the handoff was written and the replacement failed."

**Concrete failure.** 04:00. Orchestrator at 82 %, config says `action: fresh-session` because that is
what he chose for this role. The registry still holds `orchestrator`. The launch guard required by
`[301]` refuses the new one, correctly. The close refuses, correctly, because a monitor is armed. The
compact path was not configured for this role, because he chose the other option. **Both exits are
closed by his own rules, and no rung below them is defined.** The run holds at 82 %, then drifts, and
the first person to learn of it is him at 09:00. Reference for the shape: §11.6, five days of a dead
run flagging the same line 1,085 times, unresolved.

**A second, quieter hole in the same decision.** «Запустити повністю новий оркестратор» does not say
what the new one inherits. `ORCHESTRATION.md` line 117 says the handoff *"exists because the watcher
restarts the orchestrator when its context fills"* — so the position file is the inheritance — but
`[204]` never mentions a position file, and the lane-level evidence shows a fresh session re-running
the old launcher **resumes the wedged conversation, because the session id is baked into it**
(`ORCH-HANDOFF.md` trap 3, **VERIFIED** via research §5.4). A "wholly new orchestrator" that silently
resumes the full session it was meant to replace satisfies the words and defeats the purpose.

---

## A6 — hard mode's «зупинити … і продовжити» has no safe point and no definition of *what* continues · major

**The decision.**

> «Чи хард, прямо вже зупинити, зробити компакт, і продовжити» — `[204]`
> (restated at `[213]`/`[217]` and **never ratified** — see the fidelity note)

**Two holes, both load-bearing.**

**(a) "Stop now" has no safe point.** The one project this tool was built against has a rule that
forbids it outright at certain moments. `ORCHESTRATION.md` lines 161–164, **VERIFIED**:

> "**Never compact with a mutation applied** — restore it, confirm the tree is clean with
> `git status --porcelain`, and only then compact. A compact that lands mid-mutation can leave
> deliberately-broken code in the tree with nothing left that knows to undo it."

Hard mode is defined as ignoring exactly that — it stops *now*, by definition. The memory that a file
is currently broken lives in the session and nowhere else.

**Concrete failure.** 02:30, mutation testing: a check is being proved by breaking the file it guards.
Hard mode trips at 85 %. The turn is interrupted, the session is compacted, the summary says "was
verifying the coverage gate". The restore never happens. The lane continues, commits, the phase
merges. The tree now contains deliberately-broken bytes and **nothing left in the system knows they
are a mutation**. The previous generation already merged a phase before its validator ran (§11.4,
`2026-09-13T03:26:23Z`, **VERIFIED**) and shipped five phases whose verify stage was silently skipped —
so "a later gate will catch it" is not supported by the record.

**(b) «продовжити» is undefined.** After a hard interrupt the interrupted step exists only in the
pre-compaction context. Two implementers: one re-issues the interrupted instruction verbatim (and on
Claude Code, by typing it — inheriting every failure in A1, and `send` silently truncating above ~200
characters, §12.1); the other sends nothing and lets the session read a summary and improvise. The
second is what actually happened in practice, and the supervisor prompts all warn about it
independently — `WATCHER-PROMPT.md` line 29: *"after a compact you hold a summary of your
instructions, not the instructions … the checks are exact, and a paraphrase of them is not good
enough"* (**VERIFIED**).

**(c) And the interrupt verb itself has a history.** On Claude Code the only external stop is Escape
into the tty. §11.6: the deterministic watch pressed **Escape and sent `continue` about every sixty
seconds for 85 minutes** against a healthy orchestrator, because it matched a banner inside the
orchestrator's own wrapped prose. Hard mode institutionalises that key.

---

## A7 — «софт хард» means three different things in three answers, in a system he wants driven by one file · major

**Three of his own answers, all within twenty minutes of transcript:**

| Where | His words | Soft means | Hard means | Post-condition |
|---|---|---|---|---|
| R1-06, limits `[171]` | «людина може лише налаштовувати хард ліміти, хардстопи … це означає хардстоп, що потрібно зупинити завдання прямо вже та й все. Якщо це софт стоп … агент може ще почекати, поки виконує це завдання, після цього більше не зупиняти» | finish the **task**, start no more | stop the task now | the run **stops** |
| R1-07, config change `[195]` | «чи це софт, що це треба буде наступні завдання перенести, чи це хард, чи це треба прямо вже зробити і зупинити» | applies to the **next tasks** | apply now and stop | the change is **applied** |
| R1-08, context `[204]` | «софт - це коли завершується, тоді робиться компакт. Чи хард, прямо вже зупинити, зробити компакт, і продовжити» | after the **step** `[209]` | stop now, compact | the run **continues** |

**The hole.** Same two words, three granularities (task / next tasks / step) and two opposite
post-conditions (stop vs. continue). And he wants the whole thing driven through one file:

> «це має бути налаштовано через **єдиний файл**, який оркестратор чи контекст вочер постійно дивиться
> і перевіряє, чи там були якісь зміни» — `[195]`

**Concrete failure.** At 23:00 he edits the single file mid-run and writes `mode: hard`, meaning what
he meant at `[171]` — *stop the task, I want the machine quiet*. The context subsystem reads the same
key with its `[204]` meaning, interrupts the executor, compacts it, and **continues**. The limits
subsystem reads it with its `[171]` meaning and stops the queue. He wakes to a run that both stopped
and kept working, with an executor that was interrupted mid-step for no reason the log can explain.

**Why this is not pedantry.** The R1-06 soft/hard rule — the one that defines the vocabulary the other
two reuse — is itself **unratified**: at `[178]` he said «Повтори, будь ласка», it was repeated at
`[179]`/`[180]`, and the interviewer moved on to a different restatement without ever getting an
answer (**VERIFIED**, `corrections.md` §C). So the base definition of the shared vocabulary has no
confirmation anywhere in the transcript, and each cluster is inventing its own.

---

## A8 — a compaction and a stall are the same observation, and the stall response destroys the prompt · major

**The decision this collides with** is his own answer to the adjacent question:

> «Агент сам повинен це вирішувати, тобто він дивиться, перевіряє ті сесії, які він запустив, які в
> них прогрес, що вони там зробили, тощо так далі. І відповідно до цього діє» — `[231]` (R1-09,
> also unratified — the interviewer wrote «Гаразд, зафіксував» over him mid-sentence at `[238]`)

**The hole.** A compaction takes minutes and produces no output: measured 67 % → 0 % in **about seven
minutes** (`J-WATCH-01`), 73 % → 0 % in ~90 s, 74 % → 7 % in ~2 minutes (**VERIFIED**, §10.2, §1.2,
research §5.4). During it the session does not heartbeat — §1.5: "A session heartbeats **between**
turns." So a healthy compaction is indistinguishable from the silence R1-09 exists to punish, and
`[204]` says nothing about announcing one.

**And the punishment is destructive.** §1.4, **VERIFIED**: the engine's nudge presses a bare Enter,
which "does **not** submit stranded text" — measured twice. §12.1, **VERIFIED**: a recovery attempt ran
`send " "`, which "cleared the line without submitting — the pending text … was confirmed absent from
the transcript afterwards". §1.3: `send` "types its own text and submits — so it **destroys** whatever
was pending".

**Concrete failure.** 03:55, hard-mode compact on the orchestrator, seven minutes. At minute three the
liveness watch sees a stale heartbeat and nudges. At minute five it escalates and `send`s `continue`,
which overwrites the post-compact instruction the context procedure had queued. The compaction
finishes; the orchestrator holds a summary, receives the word `continue`, and improvises from a
paraphrase of its own brief. The field record already holds the exact ingredients: **33 nudges in one
run** (§12.3), **`STALLED` raised against demonstrably healthy sessions eight or more times across
about seven hours** (§11.3), and **a thirteenth consecutive stranded `continue` on the orchestrator's
input line, sitting beside a live Playwright run it could have corrupted** (§11.2).

**The previous generation knew and patched it by prose.** `ORCHESTRATION.md`: *"Say in your heartbeat
that you compacted and at what percentage, so the watch does not read the quiet as a stall"*
(**VERIFIED**). That is a model being asked to remember a courtesy, which §11.4 shows is not a control:
five phases' verify stage was skipped because a session generalised a prose warning.

---

## A9 — «кастомний скіл» has no completion signal and no obligation to free anything · major

**The decision.**

> «Якщо людина обирає лише компакт, то вона також може налаштовувати, як саме він буде компактитись,
> **якою командою, чи це офіційна, наприклад, якщо це Клод Код, чи це кастомний скіл**» — `[204]`

**The hole.** A native `/compact` produces runtime-emitted evidence that it completed — on Claude Code
a `PostCompact` hook with the summary in hand, and a `compact_boundary` record in the transcript
(**VERIFIED** in the 2.1.278 binary's hook schema; research §2.3). A **custom skill produces none of
that.** It is ordinary model work: it reads files, writes files, and ends. Nothing in the decision
obliges it to reduce the window at all, and a skill that writes an excellent handoff and then does not
compact is a fully valid configuration under `[204]`.

Worse, a custom skill is also **input-line text**, so it inherits every delivery failure in A1 — plus
one of its own: running it *consumes* context on the way to freeing it.

**Concrete failure.** He configures `command: /my-context-handoff` for the orchestrator, because he
prefers his own summary shape. 02:00, threshold trips, the skill is typed in and lands. It reads the
state, writes a 400-line handoff, ends its turn — and the window is now **higher** than when it
started. The supervisor sees no drop, concludes the action failed, and fires again. And again. Each
firing adds context. By 04:00 the session is at 96 % with nine handoff revisions on disk.

**And on Claude Code there is a configuration that silently kills both options at once**: the
`DISABLE_COMPACT` environment variable is documented in the binary as *"DISABLE_COMPACT also disables
manual `/compact`"* (**VERIFIED**, research §2.4). A session launched by a wrapper that sets it will
accept the keystroke and do nothing, indefinitely — and `[204]` has no branch for "the configured
command is not available on this session".

---

## A10 — the only universal verification is the reading that lies, and re-firing on it is what makes compaction permanently impossible · major

**The decision this is aimed at** is `[204]`'s guarantee again, but the attack is specific: the
mechanism must decide whether the action worked, and on any platform without a completion hook the
only available test is *"did the percentage drop"*.

**That test is known to be wrong, in writing, on this machine.** `gsd-context-monitor.js` carries a
watermark and explains why (**VERIFIED**, quoted in research §2.3):

> "the statusline re-writes the bridge on every render, and **a render during the compaction stamps the
> OLD `remaining_percentage` with a current time**. The watermark records the compaction's START, so
> 'newer than the watermark' alone still admits a mid-compaction render."

And the previous generation's procedure does exactly the forbidden thing — `WATCHER-PROMPT.md` step 4:
*"**Wait for the context percentage to drop** before doing anything else"* (**VERIFIED**).

**The hole.** `[204]` says the action must be guaranteed; it does not say the trigger fires **once per
crossing**. Nothing in it makes the mechanism idempotent. Combine that with a verification that can
return a false negative during the very operation it is verifying, and the loop is closed.

**Concrete failure, and it is terminal.** 01:40, threshold trips, `/compact` lands and begins. At
01:41 a status render republishes 84 % with a fresh timestamp. The supervisor reads it, concludes the
compaction failed, and fires again. Claude Code's auto-compact path has a **thrash breaker**, verbatim
in the binary (**VERIFIED**, research §2.4): *"Autocompact is thrashing: the context refilled to the
limit within 3 turns of the previous compact, 3 times in a row."* There is also a **failure breaker** —
N consecutive failures → `failure_breaker_open`, i.e. auto-compact stops trying — and a **prefix
overflow** case: *"autocompact: fixed prefix … > threshold … — compaction cannot help"*.

So a verification bug does not merely waste a cycle: **three of them in a row make that session
permanently uncompactable, by both his mechanism and the platform's**, for the rest of the night.
`[204]` names no state in which the configured action is impossible, so the config has no branch for
it and the mechanism keeps trying the thing that can no longer work — which is precisely the 85-minute
loop of §11.6, reached by a different road.

**And the prefix-overflow case is a *configuration* failure, not a runtime one.** A session born with
enough MCP servers, plugins, skills and memory files that the un-summarisable prefix already exceeds
the compaction threshold can never be rescued by compaction at all. This machine runs roughly twenty
MCP servers and well over a hundred skills (**VERIFIED** — this session's own tool and skill listing).
Nothing in `[204]` measures the prefix before choosing a threshold.

---

## A11 — there is no default, and «людина налаштовує» hands over a number whose right value he cannot see · major

**The decision.**

> «користувач повинен це налаштувати. Та явно, чітко вказати» — `[204]`

**The hole, part one: there is no default anywhere in this cluster.** He says the user must configure
it explicitly. The plugin must nevertheless behave on the first run, before anyone has configured
anything, and `[204]` does not say what it does then. The neighbouring answer that would settle it is
itself empty: Д1 defers the whole precedence question to a marketplace repo he names no rules for —
«там є відповіді на ці питання. Наступне питання» `[416]` — and is **unratified** (`[417]`/`[418]` →
`[419]`, the interviewer moved straight to Д2; **VERIFIED**, `corrections.md` §C).

**Concrete failure (first run, and second run).** A user installs the plugin and starts an overnight
run without touching the context section. Nothing trips, because no threshold exists. The platform's
own auto-compact governs the night — at its number, in the middle of whatever is running, violating
the mutation rule every time it fires. The run report prints a context policy section because the
config schema has one. On the second run he lowers a number in a file that was never being read.

**The hole, part two: he cannot know the right number.** A threshold is only meaningful against a
refill rate, and the measured rates differ by an order of magnitude (**VERIFIED**, §3.2):

- the context watch: **9 % → 91 % in about ten hours** — roughly 8 %/hour at a 120-second cycle;
- a worker lane: **91 % in three and a half hours** — ~26 %/hour, three quarters of it polling;
- the orchestrator: **64 % after thirty hours**, and it had already been compacted once — ~2 %/hour.

At 8 %/hour, a soft threshold of 80 % leaves about 150 minutes of slack before the wall. At 26 %/hour
it leaves **46 minutes** — less than the 58-minute-to-3h20m span of a single worker phase (§6), so
soft mode's step boundary may not arrive before the wall on a perfectly healthy lane. **Three sessions
on the same machine need three different numbers, and the difference is invisible at configuration
time.** «Людина налаштовує» is where this problem is *placed*, not where it is *solved* — and the one
signal that would actually distinguish these cases, Δpercent/hour, is nowhere in `[204]`.

---

## A12 — on Claude Code 2.1.278, the read path his threshold needs removes the idle signal his soft mode needs · minor

**The two requirements**, both from `[204]`/`[209]`: an exact percentage to compare against a
threshold, and a step/idle boundary to wait for in soft mode.

**The hole.** On Claude Code the exact, event-driven read is the `statusLine` payload, which carries
`context_window.used_percentage` (**VERIFIED** in the 2.1.278 binary's payload builder). Installing a
status line to capture it costs the footer hints: per the published doc (**CLAIMED**), *"With a custom
status line configured, Claude Code stops showing most of the footer's keyboard hints, including
`esc to interrupt`"*. And `WATCHER-PROMPT.md` line 126 gates the entire compaction procedure on
exactly that string (**VERIFIED**): *"Only when the capture shows the orchestrator idle — no
`esc to interrupt` on screen."*

**Concrete failure.** The implementer installs the status-line bridge to satisfy the threshold
requirement. The screen-based idle check silently starts returning "idle" for every session, forever —
a false-clean of exactly the shape §11.3 already records for BSD `find -newermt`, *"which would have
declared every healthy session idle for ever"*. Soft mode now fires mid-turn on every session, which
is hard mode, which is not what was configured.

**Why minor rather than major**: the replacement exists and is better — `claude agents --json` reports
`status: busy|idle` per session and **does not require a TTY** (**VERIFIED by execution**, research
§2.2). The attack is that nothing in `[204]` warns that the two requirements are coupled, so an
implementer can satisfy one and break the other without noticing. Also platform-version-bound: this is
a fact about 2.1.278 on 2026-09-19, and Claude Code shipped four versions on this machine inside four
days.

---

## What this cluster needs from him before anyone builds it

Not proposals — the four questions whose absence produced five of the blockers above.

1. **Which percentage is his percentage** (A2) — the raw `/context` number, or the bar he has been
   reading, ~13 points apart.
2. **Who holds the trigger** (A3) — he named the orchestrator at `[204]` and left it open at `[195]`,
   and the orchestrator cannot act on itself.
3. **Whether the fresh-orchestrator option is exempt from `[301]`'s «не дозволяти»** (A5), given that
   the orchestrator being replaced has not failed and `[300]` requires proof of failure first.
4. **What the mechanism does when the configured action is impossible** (A10) — `DISABLE_COMPACT`,
   prefix overflow, thrash breaker, failure breaker. `[204]` has no branch for a configured action
   that can never succeed, and two of those four states are permanent.

And a fidelity item to put to him directly, from `corrections.md` §C: **the guaranteed-execution
requirement as formulated was never confirmed** — his words at `[204]` are his, the sentence at
`[220]`/`[224]` is the interviewer's, and the only «Так, правильно» in this cluster is `[212]`, which
covers the step boundary alone.
