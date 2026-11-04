# SPEC-safety — boundaries, red lines and cleanup

**Scope.** R1-15 (the one text file of prohibitions), R1-16 (not touching what it did not start, and
its two named cases), Д3 (end-of-run cleanup), and the enforcement question the owner commissioned at
I3 [378]/[381]. This is the build document for those four items: exact paths, formats, field names,
types, defaults, numbered algorithms and worked examples. An implementer should not have to ask a
question to build what is below; every place where I had to invent something he never decided is in
§12, phrased as a question for round 2.

**Date:** 2026-09-19. **Plugin name used throughout:** `orchestrator`.

**Evidence tags.** **VERIFIED** — read in a primary source on this machine, or executed here, by me or
by a cited research document that executed it here today. **CLAIMED** — a document or vendor doc
asserts it and nothing was executed behind it. **INFERRED** — my reasoning from the above.

**Every default in this document is DEFAULT-PROPOSED.** The owner stated almost none of them. Each
carries a one-line rationale where it is defined, and all of them are collected in §10.

---

## 0. Which design this builds on, and where I departed from a judge

### 0.1 The judges disagree, so I say which one I followed

| Judge | 1st | 2nd | 3rd | 4th |
|---|---|---|---|---|
| `JUDGE-fidelity` | **minimal** 8 | reliability 7 | adapters 6 | operability 5 |
| `JUDGE-cost` | **minimal** 9 | operability 7 | reliability 5 | *(adapters scored in its own section)* |
| `JUDGE-survival` | **operability** 8 | adapters 7 | reliability 6 | minimal 5 |

Two of three name `ARCH-minimal`, and the third builds an eleven-graft list **into** minimal
(`JUDGE-cost` §8, "Net effect on the winner's size… ARCH-minimal's ~1,100"). `JUDGE-survival` names
operability and then supplies fourteen grafts, four of which are about exactly this document's
subject. **I took `ARCH-minimal` as the base and grafted the boundary mechanisms from the other
three.** Where a name collides, minimal's name wins and the alias is given.

### 0.2 On this subject the four designs almost agree, which is the strongest signal in the set

All four converge on the same core mechanism — an append-only registry of what the run created,
written at creation time, and a teardown that iterates it and nothing else:

- `ARCH-minimal` §10.1/§11.2 — `owned.ndjson`, *"the compose project name is read from `owned.ndjson`,
  never from the environment"*, *"nothing in this design matches processes by pattern, ever"*.
- `ARCH-operability` §13.2 — *"the orchestrator may stop only a thing whose identifier it wrote into
  the ledger at the moment it created it"*, teardown verified by observation.
- `ARCH-adapters` §11 Layer 1 + Invariant BD-1 — the same rule, plus a **build-failing lint**.
- `ARCH-reliability` §12.2 — the same rule with identity tuples that survive a process death, and
  the explicit *"`COMPOSE_PROJECT_NAME` is never relied on"*.

`C8-boundaries-safety-research.md` §6 Option B reaches the same place independently and prices it at
**zero cost to the owner**. `C8-boundaries-safety-challenge.md` closes with *"the provenance principle
itself is sound… every attack above is against its implementation gaps (A1, A2, A3, A11), not against
the rule."* So §3 below is the union of the four, and its job is to close A1, A2, A3 and A11.

### 0.3 The four places I overruled a judge or a design, and why

1. **`orphan_reclaim` defaults to `off`, not `same_tool_confirm`.** `ARCH-reliability` §12.4 ships
   `same_tool_confirm` and admits in its own §17.5 that *"it is a widening and he did not authorise
   one"*; `JUDGE-fidelity` §5.2 lists it among the four defaults that are "not defensible as his". I
   ship minimal's behaviour — list the residue, print the exact command, touch nothing — and keep
   reliability's two other values as config. §6.7.
2. **No mandatory deny list on sandboxless lanes.** `ARCH-adapters` §11 makes a static destructive-
   command deny list mandatory where `sandbox: false` (Kimi, pi). `JUDGE-fidelity` §3 marks this down:
   *"A mandatory deny list is enforcement machinery in a subset case; it is raised as a question, but
   it ships."* Here it is a key, default off, and preflight prints one line saying that lane has no
   floor beneath the text file. §4.6.
3. **`session.permissions` defaults to `inherit`, and an unrecognised value is a hard config error.**
   This is minimal's §11.1 position, and it is the direct correction of the shipped
   `harness-spawn.sh:32-39`, which defaults to `--dangerously-skip-permissions` *and falls back to it
   for an unrecognised value* (VERIFIED, quoted in C8 §2.3 and C8-A4). §4.5.
4. **I followed `JUDGE-survival` G14 and G6 against minimal, and `JUDGE-cost` G7.** The build-failing
   lint, its added "no teardown argument from the environment" clause, and the rule that a model
   session never creates a process, are all cheap and all close a recorded incident. §3.8, §3.9.

### 0.4 The one thing every reader of this document should hold

The owner's own evidence says prose rules fail, and he asked for prose rules anyway. Both of those are
true and this document does not resolve the contradiction — it builds his decision, prices it, and
puts the contradiction in front of him in §12 with the exact words to answer. The mechanisms in §3
and §6 are **not enforcement**; they are bookkeeping about what the orchestrator itself created, and
they hold whether or not any model obeys anything. That distinction is the spine of the document.

---

## 1. What he decided, verbatim, and what grade of evidence it carries

### 1.1 R1-15 — the red line [357] — **UNRATIFIED**

> «є сенс добавити в архітектуру якийсь текстово писані правила, які не можна, наприклад, порушувати
> … ці виключення повинні читатися в обов'язковому порядку всіма, хто … буде працювати в цьому, з цим
> оркестратором»
> «Має бути якісь визначене місце, де може людина додавати якісь **різного типу** обмеження»
> «На окремо якогось обов'язкової процедури для цього не треба. Достатньо лише одного файлу, який може
> доповнюватись, текстописний»
> «технічні обмеження середовища користувач за потреби налаштовує сам»
> «**Але, так, це максимум**»

VERIFIED as his words. **Unratified:** he closed with a question back to the interviewer («Чи це є
відповідно до твоєго питання»), which the interviewer answered for itself at [358], moving on at
[360]. `extract/corrections.md:72` calls it *"the weakest-grounded answer in the interview"*
(VERIFIED via C8 research §1). Four things are in that answer and `ANALYSIS-01.md` carries two: it
drops **«різного типу»** (a type field he offered) and drops **«це максимум»** (a ceiling). Both are
restored below: the type field in §2.3, the ceiling as the reason nothing in §4 is on by default.

### 1.2 R1-16 — not touching what it did not start [366], [370], [373] — **PARTIAL, unratified in its key clause**

> [366] «в оркестратори **прописаний шлях, до чого він має доступ**»
> [366] «оркестратор має бути якось селфевернес, що він, до чого він може змінювати, а що не може …
> він би не мав зупиняти якісь там тести, які не він запускав»
> [370] «перший кейс … я працюю з іншим, наприклад, іншою папкою, іншим проектом, то цей оркестратор,
> він цього не має трогати. Другий кейс, якщо, наприклад, **в тій самій папці** я паралельно працюю над
> чимось, це не запускав оркестратор, це роблю я, він цього не має зупиняти.»
> [370] «я не хочу якихось детерміністського варіанту для цього, тому що він буде дуже складний
> оверінжиринг, але дуже якісь простий та надійний варіант для цього має бути прописаний в плагіні»
> [373] «Чи якоїсь конфіг... Я би не сказав, **я би це робив якось абстрактно**»

VERIFIED. **The clause the analysis treats as settled — «без складного механізму технічної ізоляції»
[372]/[376] — is the interviewer's, and was never confirmed** (VERIFIED, `extract/corrections.md:96`
via C8 research §1). What he *refused* at [370] was what was described to him at [364]/[365] as
«окреме середовище, з якого він узагалі не має доступу» — a container or a VM. What he *proposed* two
rows earlier was a path list. Those are different things and the difference is the whole of §12 Q1.

### 1.3 Д3 — end of the run [430] — **SETTLED**

> «якщо, наприклад, він там підняв свої якісь там **оркестратори**, якщо він підняв там якісь докер
> контейнери або якісь сервіси … якщо він це сам підняв, то він це повинен і зупинити»
> «щоби не залишати хвостів, і не засоряти систему, працювати намарно, тому що це вже не потрібно»

VERIFIED. His teardown list **starts with nested orchestrators**; `ANALYSIS-01.md` drops that word
(VERIFIED, `extract/by-item.md` Д3 row 2). It collides with R1-10 [300] («якщо раптом одночасно два
якісь оркестратори працюють, то це не окей»). §6.6 handles it as stated and §12 Q12 asks.

Three motives, not one: **no tails, no clutter, no wasted spend.** The third is why §6 tears down even
things that would cost nothing to leave.

### 1.4 The record these decisions are being asked to survive

All VERIFIED in `plugins/harness/docs/FIELD-NOTES.md`:

| Ref | What happened |
|---|---|
| §11.5 | The owner's default stack destroyed by `docker compose down -v` with **no `COMPOSE_PROJECT_NAME` exported**, so it resolved to the default project. Actor never identified. **A session had refused that exact action as owner-only two minutes earlier.** |
| §11.8 | `pkill -f 'playwright test'` killed an unrelated lane, because **every lane's own prompt text contains that literal string**. |
| §11.11 | About **150 orphaned Docker volume pairs** left by a dead prior run. |
| §12.4 | Three detached scripts must export the `gh` account themselves, because **launchd and `nohup` start with no environment**. |
| §12.5 | `QUESTIONS.md` and `JOURNAL.md` **forked into a worktree's own copy**; an owner-facing question sat invisible for an hour. |
| §11.10 | Two local role passwords printed into a session transcript by Playwright's `--trace on`; **no automated secret scan covers tool output or transcripts.** |
| §5.1 | The owner's own container `OOMKilled` by two concurrent validator builds; **no live alert.** |

Two of these (§11.5, §11.8) are R1-16 case 2 violated by the run's own cleanup machinery. §3 makes
both mechanically unreachable. Two of them (§11.10, §5.1) are **outside every boundary in this
document** and are named as such in §11.

---

## 2. The red-line file

### 2.1 Where it lives, and the one rule that matters about the path

```
<redlines.path>          DEFAULT-PROPOSED:  <project-root>/.orchestrator/RULES.md
```

`<project-root>` is the **main checkout**, resolved once at run start by §5.3's algorithm, and never
the lane's worktree.

**Resolution rule (closes C8-A5).** The file is read through the main checkout even when the reader is
a lane whose cwd is a worktree. Implementation, exactly:

```sh
# from anywhere inside the repo or any of its worktrees
main_root() {
  git -C "$1" rev-parse --path-format=absolute --git-common-dir \
    | sed 's#/\.git$##' | sed 's#/\.git/worktrees/.*$##'
}
```

VERIFIED that `git rev-parse --git-common-dir` resolves a linked worktree back to the main `.git`
(git 2.33.0 present on this machine, per `JUDGE-cost` §0.1). `ARCH-minimal` §13 states the same rule
for the same reason: *"read from the MAIN checkout only"* — because FIELD-NOTES §12.5 recorded two
owner-facing files forking into a worktree copy, and a red-line file that forks is a mechanism that
**reports success while doing nothing**, which is the failure class this whole rebuild exists to stop.

**The path is a config value; the file is not.** `redlines.path` resolves through the six snf config
slots (`docs/config-levels.md` §2, VERIFIED): slot 6 `./.claude/shared/plugins/orchestrator.local.json`
beats slot 4 `<config-root>/shared/plugins/orchestrator.json` beats slot 2
`./.claude/shared/plugins/orchestrator.json`. `<config-root>` is `CLAUDE_CONFIG_DIR` verbatim when set,
else `~/.claude` (VERIFIED, OWNER-DECISIONS 3.3). **There is still exactly one file**, as he said —
only one path value wins.

`plugins/orchestrator/config/recommended.json` may carry a suggested `redlines.path` with
`"strength": "weak"`. It is read by the configurator and the builder and **never by the resolver**
(VERIFIED, OWNER-DECISIONS 2.2/2.3 and `docs/config-levels.md` Part Two) — it supplies no value.

### 2.2 The format

Plain UTF-8 Markdown. One rule per list item. Nothing else is parsed.

```markdown
# Red lines

<!-- orchestrator:rules v1 -->

## Absolute
- [never] Ніколи не виконувати `docker compose down` без явного `-p`.
- [never] Не чіпати контейнери та volume проєкту `<work-project>`.
- [never] Не робити міграції на локальній базі.

## Ask first
- [ask-first] Пуш напряму в `master` — тільки після мого підтвердження.
- [owner-only] Ротація або перевипуск будь-яких credentials.

## Preferences
- [prefer] Краще не чіпати файли в `legacy/`.

<!-- anything outside a list item is context for the agent and is injected verbatim -->
```

**Grammar, complete:**

| Element | Rule |
|---|---|
| A rule | a top-level Markdown list item (`- ` or `* `) anywhere in the file |
| Type marker | an optional `[<type>]` as the **first** token of the item, case-insensitive |
| Types | `never` · `ask-first` · `owner-only` · `prefer` |
| Untagged item | takes `redlines.untagged_type` (DEFAULT-PROPOSED **`never`**) |
| Headings, paragraphs, code fences | not rules; injected verbatim as context |
| Encoding | UTF-8; a byte that is not valid UTF-8 makes the file unreadable → §2.6 |

**Why a type field exists at all.** He said it: «Має бути якісь визначене місце, де може людина
додавати якісь **різного типу** обмеження» [357] (VERIFIED). `ANALYSIS-01.md` flattened it to "one
text file" (VERIFIED, `extract/by-item.md` R1-15 row 2). C8-A9's attack is exactly the flattening:
*"не пушити напряму в trunk"* and *"краще не чіпати файли в `legacy/`"* are read as context of equal
weight, and an autonomous-mode agent with configured decision authority (R1-02/R1-14) picks one. A
marker is one bracketed word in a line he was already going to write.

**The semantics borrow his own `never`** from `<baseline-marketplace>/docs/config-levels.md` §5
(VERIFIED): entries accumulate by union, a person's own entries hold against every candidate, an entry
that strikes nothing is **reported, never silently dropped, never auto-corrected**. Here there is one
file rather than six slots, so "accumulate" is trivial — but the "reported when it strikes nothing"
property is kept: §2.7.

### 2.3 What each type means, mechanically

| Type | Meaning to an agent | Meaning to the orchestrator |
|---|---|---|
| `never` | Absolute. Do not do it. If the ticket requires it, stop and escalate. | Injected in every prompt. If `redlines.enforce` is on (§4.6), a matching resolved path is hard-denied. |
| `owner-only` | Only the owner performs this. An agent that believes it is required escalates. | Same injection. Routed to the Д6 questions channel as `owner_action_required`, never auto-retried. |
| `ask-first` | Permitted only after an answer through the Д6 channel. | In `run.mode: autonomous` this **still** blocks and asks — an `ask-first` rule outranks autonomy. That is R1-14 [082]'s «Якщо агент вирішив, що це точно має бути хардстопом … навіть якщо це автономний ран» applied in the one direction he stated. |
| `prefer` | Advisory. Weigh it; it does not block. | Injected. Never blocks, never escalates. |

⚠ **TENSION.** The four-value vocabulary is mine. He said the restrictions have types and did not
enumerate them. §12 Q5 asks him to confirm or replace the list, and §12 Q4 asks about the untagged
default, which is the one place where guessing wrong is expensive in both directions.

### 2.4 Size, and why there is a cap

```
redlines.max_bytes            DEFAULT-PROPOSED: 8192
redlines.on_oversize          DEFAULT-PROPOSED: refuse        # refuse | truncate_and_notify
```

The file is append-only by his design («який може доповнюватись» [357]) and is injected into **every**
session and again after **every** compaction (§2.5). C8-A9's volume attack is real and cited against
FIELD-NOTES §3.1 (VERIFIED: one lane spent three quarters of its context window on polling, and
*"nothing in the plugin measures context"*). 8192 bytes is roughly 1,200 Ukrainian words — about 80
rules — which is a year of incidents. `ARCH-operability` §15 ships the same number for the same
reason. `refuse` rather than `truncate` because a silently truncated prohibition list is the exact
"reported success while doing nothing" shape; truncation is available and notifies.

### 2.5 Injection — the mechanism, per lifecycle event

The file is injected **four** times, and the fourth is the one everybody forgets.

| # | Event | What happens |
|---|---|---|
| 1 | Lane launch | The rendered block (§2.5.1) is prepended to the lane's first turn. Its `sha256` is written into `lanes/<id>/start.json` as `redlines_sha256` **before** the platform is launched. |
| 2 | Reseed (a close-and-relaunch after compaction, or an account change) | Re-rendered and re-injected; the new digest is recorded on the new lane record. |
| 3 | **After every proved compaction** | Re-injected into the next turn. |
| 4 | Orchestrator / judge / watcher turns | The same block is prepended to every model turn the plugin itself makes, because R1-15 says «всіма, хто … буде працювати … з цим оркестратором» [357] — the plugin's own agents are inside that set. |

Event 3 is the one `ARCH-reliability` §13.4 and `ARCH-adapters` §9 both single out, with the same
source: OpenClaw's `post-compaction-context.ts` (CLAIMED, `ADOPTION-VERDICT` §4 item 3). Its details
are worth copying rather than reinventing — fenced-code-block-aware heading extraction, a bounded
character budget with UTF-16-safe truncation, and **every failure path returning null** so a missing
or oversized file degrades to *no injection* rather than to an error. The reason to build it is blunt:
**compaction deletes the red lines mid-run, repeatedly, in a run long enough** — and R1-08 makes long
runs with compaction the normal case.

#### 2.5.1 The rendered block, exactly

```
=== ORCHESTRATOR RED LINES (redlines v1, sha256:3f9c…a2, 1174 bytes, read 2026-09-19T23:12:04Z) ===
These are the owner's own prohibitions. They are read in full before you act.
NEVER          — absolute. If the task requires it, stop and escalate; do not proceed.
OWNER-ONLY     — only the owner does this. Escalate.
ASK-FIRST      — permitted only after an answer arrives through the questions channel.
PREFER         — advisory.

[NEVER]      Ніколи не виконувати `docker compose down` без явного `-p`.
[NEVER]      Не чіпати контейнери та volume проєкту `<work-project>`.
[OWNER-ONLY] Ротація або перевипуск будь-яких credentials.
[ASK-FIRST]  Пуш напряму в `master` — тільки після мого підтвердження.
[PREFER]     Краще не чіпати файли в `legacy/`.

Free text from the file, verbatim:
<…any non-list prose, in file order…>
=== END RED LINES ===
```

The digest in the header is not decoration: it is what makes *"every agent read it"* a journal fact
rather than a hope (`ARCH-reliability` §13.4's first mechanism, adopted). §6.8's proof cites it.

### 2.6 When the file cannot be read — the branch R1-15 does not define

R1-15 says reading is «в обов'язковому порядку» and is silent on the failure branch. C8-A5 notes the
two implementations are opposite, and that *"this codebase's demonstrated house style is the second
one"* (proceed) — VERIFIED against FIELD-NOTES §11.9, where the credential checker silently ignored a
bare path argument and *"reads clean over files it never opened"*.

**Specified: fail closed.**

```
redlines.on_unreadable        DEFAULT-PROPOSED: refuse        # refuse | warn_and_proceed
```

| Condition | Behaviour under `refuse` |
|---|---|
| File absent | Preflight refuses, **exit 78**, message names the resolved absolute path and prints a `orchestrator:init --rules` command that writes the template of §2.2 |
| Unreadable (permissions, bad UTF-8) | Preflight refuses, exit 78, names the path and the errno |
| Over `redlines.max_bytes` | Per `redlines.on_oversize` |
| Readable and empty (zero rules) | **Starts.** Prints one preflight line: `redlines: 0 rules at <path> — nothing is prohibited by the file`. An empty file is a legitimate state and must not be indistinguishable from a missing one. |

### 2.7 Mid-run edits — the honest answer

C8-A6 is the attack: the owner wakes at 03:15, appends a rule, goes back to sleep believing he has
stopped a lane that booted at 23:40. FIELD-NOTES §8 (VERIFIED) establishes the structural property —
*"a session already booted keeps the account it booted with; the change reaches the next spawn"* — and
INFERRED that spawn-time prompt injection inherits it.

```
redlines.apply        DEFAULT-PROPOSED: next_launch   # next_launch | reseed_now | notify_only
redlines.watch        DEFAULT-PROPOSED: true          # poll the file by content hash each tick
```

Behaviour under the default, in numbered steps:

1. Each supervisor tick, `stat` the file; if `mtime` or size changed, read it and compute `sha256`.
2. If the digest differs from `run.redlines_sha256`, append `observation: redlines.changed` to
   `journal.ndjson` with `{from, to, rules_before, rules_after}`.
3. Update `run.redlines_sha256`. Every **subsequent** launch or reseed uses the new text.
4. **Emit one notification** through the configured R1-17 channel, naming every live lane still
   holding the previous digest and its ticket id:
   `redlines changed (5 → 6 rules). 3 lanes still hold the old text: L1 (SFW-214), L3 (SFW-219), L4 (SFW-221). They will pick it up on their next launch or reseed.`
5. Under `reseed_now`, additionally queue a reseed for each such lane at its next step boundary. This
   costs each lane its working memory and makes ticket→session one-to-many; that price is why it is
   not the default.

The notification in step 4 is the whole point: he must not be able to believe a rule has landed when
it has not. This is `notify_only` behaviour, shipped inside the default, and it is free.

⚠ **TENSION.** `next_launch` means a rule he adds at 03:15 does not bind a lane running at 03:22.
That is a real cost of a real platform fact, not a preference. §12 Q3.

### 2.8 What this file cannot do, stated in the file's own template

`orchestrator:init --rules` writes the §2.2 template with this comment at the bottom, because C8-A10's
sharpest point is that the file's *existence* tells him he is protected in classes where it has no
purchase:

```markdown
<!--
This file lists actions an agent must not choose. It cannot cover:
  - a secret printed by a tool doing its declared job (Playwright --trace on put two passwords
    into a transcript; nothing here would have stopped it)
  - resource contention (two builds OOM-killed the owner's own container; this is a scheduling
    control, not a prohibition)
  - what a script does after an agent writes it and runs it in one tool call
  - anything on a platform with no sandbox, where this file is the only barrier
-->
```

---

## 3. The ownership model — making "only what I started" mechanical

### 3.1 The invariant, stated abstractly as he asked [373]

> **The orchestrator may act destructively on a thing only if it wrote that thing's identifier into
> the run registry at the moment it created that thing, and that identifier still resolves to the same
> thing now.**

"Act destructively" means: signal, kill, `down`, `remove`, `prune`, `rm`. **Reading and listing are
not covered** and are always permitted — §6.8's proof depends on being able to list.

Two corollaries that carry the whole design:

- **Nothing is ever identified by pattern.** No `pkill -f`, no `killall`, no `pgrep` over a command
  line, no `docker ps | grep`. FIELD-NOTES §11.8 (VERIFIED) is why: every lane's own prompt text
  contains the string the pattern matched, so the pattern matched sessions rather than the suites.
- **Nothing is ever identified from the environment.** FIELD-NOTES §11.5 and §12.4 (VERIFIED)
  together: the incident was a `docker compose down -v` with `COMPOSE_PROJECT_NAME` unset, and
  detached processes start with no environment at all. §3.9 makes this a build-failing lint.

### 3.2 The registry file

```
<state-root>/runs/<run-id>/owned.ndjson
```

`<state-root>` DEFAULT-PROPOSED `<config-root>/orchestrator/state` — **outside every checkout**, so
that run state never appears in `git status`, never forks into a worktree, and survives
`git clean -fdx` in the project. (`ARCH-minimal` moves run state out of the work tree for the same
reason, citing its own 327 dirty tracked files.)

**Aliases:** `ARCH-operability` and `ARCH-adapters` call this file `ledger.jsonl`;
`ARCH-reliability` calls it `resources.jsonl`. Same object. `owned.ndjson` is the base design's name.

**Write discipline.**

| Property | Rule |
|---|---|
| Append-only | one `O_APPEND` `write(2)` of one line. Never rewritten, never truncated, never `: >`'d. (FIELD-NOTES §2.1: the previous generation truncated `state/attention` every cycle and destroyed a night of another process's corrections — VERIFIED.) |
| Line size | ≤ 4096 bytes. A longer line is a bug; the writer refuses and journals. |
| Encoding | one JSON object per line, no trailing commas, no newlines inside |
| Durability | `fsync` after the `intent` line of a destructive-capable resource (§3.4 step 2), not after every line |
| Readers | never lock; a truncated last line is one lost fact, not a lost file |

### 3.3 The line shapes — three kinds

```jsonc
// 1. intent — written BEFORE the thing exists
{"seq":41,"at":"2026-09-19T23:12:04Z","mono":81234.918,"kind":"intent","res":"r14",
 "run":"20260919T231204Z-a7f3c1","lane":"L1","type":"docker_compose_project",
 "identity":{"project":"orc-a7f3c1-l1",
             "labels":{"orc.run":"20260919T231204Z-a7f3c1","orc.project":"sha256:9b2e…","orc.lane":"L1"}},
 "teardown":{"op":"compose.down","args":{"project":"orc-a7f3c1-l1","volumes":true}},
 "probe":{"op":"compose.ps","args":{"project":"orc-a7f3c1-l1"}}}

// 2. created — written AFTER creation returns, carrying the RESOLVED identity
{"seq":42,"at":"…","mono":81236.402,"kind":"created","res":"r14",
 "identity":{"project":"orc-a7f3c1-l1","container_ids":["3f1a…","9c04…"]}}

// 3. resolved — written by teardown (§6), one per resource, never more than one
{"seq":211,"at":"…","mono":121004.7,"kind":"resolved","res":"r14",
 "verdict":"gone","evidence":{"probe":"docker ps -q --filter label=orc.run=20260919T231204Z-a7f3c1",
                              "stdout_bytes":0,"at":"…"}}
```

**Intent before creation is the whole trick** (`ARCH-reliability` §12.2; `ADOPTION-VERDICT` §4 item 8's
*"append `start` first"*). A crash between `intent` and `created` leaves a line with a `probe` — so the
next run can *ask* whether the thing exists, instead of guessing. A crash after creation with no
`intent` leaves an orphan nobody can ever find, which is FIELD-NOTES §11.11's 150 volume pairs.

**Field types.**

| Field | Type | Notes |
|---|---|---|
| `seq` | int, monotonic per run | assigned by the single writer (§3.7) |
| `at` | RFC3339 UTC string | display only |
| `mono` | float seconds, `CLOCK_MONOTONIC` | every duration is computed on this; graft G3 from `JUDGE-survival`. A wake is `wall_delta − mono_delta > 60 s`, and for 120 s after a wake **no resource may be judged absent** — otherwise a sleeping Mac makes every probe read "already gone" and teardown records a clean finish it never performed |
| `kind` | `"intent" \| "created" \| "resolved"` | |
| `res` | string, `r<n>` unique per run | the handle every other file uses |
| `run` | run id | |
| `lane` | lane id or `null` for run-level resources | |
| `type` | one of §3.4's seven | |
| `identity` | object, shape per type | §3.4 |
| `teardown` | object `{op, args}` | `op` is from a **closed set** (§6.3); `args` values are literals, never `$VAR` |
| `probe` | object `{op, args}` | read-only; must be safe to run at any time |
| `verdict` | `"gone" \| "absent" \| "failed" \| "left_deliberately"` | on `kind:"resolved"` only |

### 3.4 The seven resource types and their identities

An identity is only an identity if it **survives the death of the process that created it** and cannot
be recycled onto something else. That rule disqualifies pid alone and tty alone — C8-A3's attack:
a tty released at 01:10 is handed to the owner's own new window at 03:00, and teardown at 04:12 closes
it mid-edit.

| Type | Identity fields | Why it is not recyclable | Teardown op | Proof of teardown |
|---|---|---|---|---|
| `process` | `pid`, `pid_start`, `argv_sha256` | `pid_start` is the process's own start time; a recycled pid has a different one | `signal` | `kill -0` fails, **or** `ps -o lstart=` no longer matches `pid_start` |
| `process_group` | `pgid`, `leader_start`, `argv_sha256` | as above, on the group leader | `signal_group` | no member remains whose `(pid,start)` matched |
| `session` | `platform`, `account_profile`, `session_id`, plus the `process` fields | the platform's own id; `client`-assigned where the adapter says so (ADAPTER-CONTRACT §2.0 `idAssignment`) | `adapter_stop` | adapter listing no longer shows it **and** the process proof above |
| `docker_compose_project` | `project` (name) **and** labels `orc.run`, `orc.project`, `orc.lane` | the name is run-scoped and never the default; the labels make the containers self-identifying | `compose_down` | `docker ps -aq --filter label=orc.run=<id> --filter label=orc.lane=<lane>` empty |
| `git_worktree` | absolute `path` under `boundaries.worktree_root`, `branch`, `base_sha` | the path is created by this run under a prefix nothing else writes to | `worktree_remove` | path absent **and** `git worktree list --porcelain` no longer names it |
| `port_block` | `first`, `count` | a record, not a thing; released, never killed | `release_record` | n/a |
| `unowned` | whatever is known | **never torn down.** Recorded so it can be listed. | — | — |

**Getting `pid_start` on macOS**, exactly (VERIFIED shape; `ps` is present on macOS 26.5.2):

```sh
pid_start() { ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/^ *//'; }
argv_sha() { ps -o command= -p "$1" 2>/dev/null | shasum -a 256 | cut -d' ' -f1; }
```

`ARCH-reliability` §12.2 uses `(pgid, leader_start_time, argv_sha256)`; this is the same tuple with
the commands written out.

### 3.5 Process groups: `setsid` does not exist here

**VERIFIED** (C8 research §3.7, executed on macOS 26.5.2): `setsid` is **absent**; `set -m` in bash
puts each background job in its own process group, and `kill -TERM -- -<PGID>` terminates that group
and nothing else. Measured output: `spawned pid=80476 pgid=80476 (own pgid=80466)` → `GROUP KILL SENT`
→ `DEAD (group kill worked)`.

Spawn helper, exactly:

```sh
orc_spawn() {            # $1=lane $2...=command
  local lane="$1"; shift
  set -m                                   # each background job gets its own pgid
  "$@" </dev/null >>"$LOG" 2>&1 &
  local pid=$!
  local pgid; pgid=$(ps -o pgid= -p "$pid" | tr -d ' ')
  set +m
  orc_owned intent  "$lane" process_group "$pgid" "$(pid_start "$pid")" "$(argv_sha "$pid")"
  orc_owned created "$lane" process_group "$pgid"
  printf '%s\n' "$pgid"
}
```

`</dev/null` is not optional: ADAPTER-CONTRACT §2.1 requires `launchHeadless` to run with
*"stdin closed or held by the adapter — never inherited"*, and an inherited stdin is one of the ways
FIELD-NOTES §1.3's stranded-instruction family happens.

### 3.6 The structural limit: terminal-spawned sessions have no lineage

**VERIFIED** (`plugins/harness/bin/harness-term.sh:16-110`): the previous generation spawns sessions
through `osascript` into iTerm2. A session started that way is **a child of iTerm2, not of the
orchestrator**. It has no process-group relationship to the run at all — which is precisely *why* the
previous generation reached for `pkill -f` and *why* it over-matched (FIELD-NOTES §11.8).

```
spawn.transport       DEFAULT-PROPOSED: process     # process | terminal
```

| Value | Identity | Consequence |
|---|---|---|
| `process` (default) | `process_group` per §3.5 — real lineage, real group kill | The owner cannot watch a lane in a terminal window or type into it |
| `terminal` | **a pidfile the session writes itself**, plus the pane/session id the launcher received, plus `(pid, pid_start, argv_sha256)` read back from that pidfile — **never lineage, never the tty** | He gets a window; teardown holds an identity that a tty recycle cannot corrupt |

Under `terminal`, teardown closes the pane **only** when the pidfile's `(pid, pid_start)` still
matches a live process. If the process is gone, the pane is **left open** and reported, because a pane
whose process died may now be his. That is C8-A3 closed at its exact mechanism.

### 3.7 Only the supervisor creates, therefore only the supervisor reaps

Graft **G6** from `JUDGE-survival`, taken against `ARCH-operability`'s own ambiguity:

> **No process, container, worktree or session is ever created by a model session. The supervisor
> creates it, writes the registry line, and owns the handle. A model may only *request* a spawn.**

The reason is FIELD-NOTES §1.6 (VERIFIED): `q-screen-orchestrator` answered its question and then sat
registered and idle for **28 hours**, because the context watch that saw it *"had no remit to close
it"* and the orchestrator that spawned it had moved on. Under this rule the creator and the reaper are
the same process by construction, so a resource with no reaper cannot exist.

**This is testable:** exactly one function in the codebase (`orc_owned_create`) appends a `created`
line, and exactly one function (`orc_destroy`) executes a teardown op. §3.9's lint asserts that no
other file calls a spawn primitive.

### 3.8 The single destructive code path

```sh
orc_destroy() {                       # $1 = res id, e.g. r14
  local res="$1" line op
  line=$(orc_owned_lookup "$res") || { orc_journal refuse "no registry line for $res"; return 64; }
  [ "$(printf '%s' "$line" | jq -r '.kind')" = created ] || { orc_journal refuse "…"; return 64; }
  orc_owned_resolved_absent "$res"   || { orc_journal refuse "already resolved: $res"; return 64; }
  op=$(printf '%s' "$line" | jq -r '.teardown.op')
  case "$op" in
    signal|signal_group|adapter_stop|compose_down|worktree_remove|release_record) ;;
    *) orc_journal refuse "unknown teardown op: $op"; return 64 ;;
  esac
  orc_destroy_"$op" "$line"          # arguments come ONLY from $line
}
```

Four refusals, all cheap, all in one place: no registry line; a line that never reached `created`; a
resource already resolved (idempotency — a replayed teardown after a crash is a no-op, not a second
kill); and an unknown op. **Every destructive action in the plugin goes through this function.**

### 3.9 The build-failing lint (BD-1, plus the clause that would actually have caught the incident)

Graft **G14** from `JUDGE-survival`, which takes `ARCH-adapters`'s Invariant BD-1 and adds the clause
neither design had. `JUDGE-cost` §8 carries the same rule as a build rule rather than a setting.

`tests/lint-blast-radius.sh` — runs in `tests/run-all.sh`, **fails the build**:

| # | Pattern, in any plugin source file (`.sh`, `.js`, `.mjs`, `.md` command bodies) | Why |
|---|---|---|
| 1 | `pkill` | FIELD-NOTES §11.8 |
| 2 | `killall` | same class |
| 3 | `docker compose down` / `docker-compose down` **without** an adjacent `-p` or `--project-name` | FIELD-NOTES §11.5 |
| 4 | `docker system prune` · `docker volume prune` · `docker image prune` · `docker network prune` **without** a `--filter label=orc.run=` | unscoped by construction |
| 5 | `git clean` · `git checkout .` · `git reset --hard` outside a path known to be a run-created worktree | the main checkout is his |
| 6 | **any teardown command whose arguments contain a `$` expansion of an environment variable** | **the added clause** |

Rule 6 is the important one and rules 1–3 would not have caught the recorded incident. The incident
was `docker compose down -v` with `COMPOSE_PROJECT_NAME` **absent**, so the command resolved to the
default project — the owner's (VERIFIED, FIELD-NOTES §11.5). A lint on the three verbs is blind to it.
A lint on *teardown arguments sourced from the environment* is not, and FIELD-NOTES §12.4 establishes
the general case: **detached scripts inherit no environment at all.**

Implementation note: rule 6 is checked against the bodies of `orc_destroy_*` functions plus anything
lexically inside a `teardown` JSON literal. A false positive is fixed by moving the value into a
registry field, which is the behaviour the rule exists to force.

### 3.10 What the registry does not cover, said plainly

**Files.** The registry is about processes, containers, worktrees and sessions. It says nothing about
a file write. `LANDSCAPE.md` §5 (VERIFIED) confirms that no tool in the surveyed field protects a
human's concurrent edits in the same checkout, and that this *"must be invented rather than adopted"*.
This document does not invent it. §5.2 says exactly how far the cheap mechanisms get.

**A lane running `pkill` itself.** The registry constrains the orchestrator, not its children.
`ARCH-operability` §13.2 states it plainly and it is true here. On a platform with a sandbox that is
covered by §4.4; on Kimi and pi there is no sandbox and R1-15's text file is the only barrier
(VERIFIED, ADAPTER-CONTRACT §H: *"Kimi: no container, no seccomp, no filesystem jail, and hooks fail
open, so a crashed guard permits; pi: no sandbox"*).

---

## 4. Enforcement options, ranked by cost, with a default posture per platform

### 4.1 The ranking

From `C8-boundaries-safety-research.md` §3 and §6. "Cost to him" is what *he* must do, not what the
plugin must build. All row facts are VERIFIED by execution on this machine on 2026-09-19 unless
tagged otherwise.

| # | Mechanism | Cost to him | Covers case 1 | Covers case 2 | Default |
|---|---|---|---|---|---|
| **B** | **Ownership registry** (§3) | **zero** — entirely inside the plugin, identical on every engine | processes/containers only | **yes, exactly** — this is the `pkill` and the unscoped `down` | **ON, not configurable** |
| **D** | **Worktree anchoring** (§5.4) — his own Д4 default [433] promoted to the boundary | **zero** — already his stated default | no, alone | **yes, structurally** — the run stops being in his folder | **ON** (`boundaries.worktree: true`) |
| **A** | **The one text file** (§2) — R1-15 exactly as given | zero (he already writes it) | no | no | **ON, as specified** |
| **E** | **OS sandbox**, anchored to the lane's cwd | **one line, set by the plugin**; nothing to install on macOS | **yes, demonstrably** | **yes for processes and for writes** | **OFF** — §4.3 |
| **C** | **One `PreToolUse` hook that reads his one file** | zero (plugin ships the hook) | yes, for named paths | partial | **OFF** (`redlines.enforce: false`) |
| **F** | Whole-process isolation (sandbox runtime / container / VM) | low to high, per engine | yes | yes | **not shipped** — §4.7 |
| — | Command-string deny lists | a few lines | **no — not a boundary** | no | **never used as a boundary** |
| — | PATH shims for `docker`/`pkill` | low | no | no | **not shipped** |
| — | `sandbox-exec` directly | medium | — | — | **never** — deprecated by Apple (VERIFIED, `man sandbox-exec`) |

**Why command-string deny rules are listed and not used.** VERIFIED on this machine today: with
`"deny": ["Bash(rm:*)"]` under `--permission-mode bypassPermissions`, a request for
`sh -c 'rm -f …/target.txt'` returned `EXIT=0` and the file was gone. Claude Code's own docs call
these patterns *"fragile"* and list four evasion classes. They may be used as an **ergonomic**
guard-rail inside something that holds; they may never be cited as a boundary in any status output,
report or preflight line. That is a wording rule with teeth: §6.8's proof never claims a deny rule
prevented anything.

### 4.2 B and D cost him nothing and contradict nothing he said

This is the recommendation if he wants to change as little as possible, and it is what ships by
default. C8 research §6 reaches the same conclusion: *"If he adopts only those two, the `pkill`
incident and the `docker compose down -v` incident both become impossible, and R1-15 stands exactly as
he gave it."*

### 4.3 Why the sandbox key ships OFF although the evidence favours it

VERIFIED, executed on this machine today under **his own** `bypassPermissions` default, with
`sandbox.enabled: true, allowUnsandboxedCommands: false, failIfUnavailable: true`:

| Attempt | Result |
|---|---|
| write to a file in a neighbouring project | `operation not permitted`; file content unchanged |
| `docker ps` | `connect: operation not permitted` on the daemon socket |
| `kill -TERM <pid>` against a process the session did not start | `operation not permitted`; process survived |
| `kill -TERM <pid>` against a process **the same session started in an earlier Bash call** | also `operation not permitted` — each Bash call is its own sandbox instance |
| `ls /Users/sasha-marchuk/Work` | **exit 0, listing returned** — reads outside cwd are not blocked by default |

That is his own [366] sentence — «в оркестратори прописаний шлях, до чого він має доступ» — with the
kernel checking the list instead of the model. It is the strongest mechanism available and it costs
one line.

**It ships off anyway**, because R1-15 as recorded says «На окремо якогось обов'язкової процедури для
цього не треба» and R1-16 as recorded is read as against isolation. The thing he *refused* at [370]
was described to him at [364]/[365] as «окреме середовище» — a container — and **nobody ever offered
him this rung**. That is §12 Q1, and it is the first question of round 2 because everything in this
section below B and D depends on the answer.

Handling pattern borrowed from `JUDGE-survival` **G12**: ship the neutral value **and print the open
question in preflight**, so the decision is in front of him rather than buried in a default:

```
boundary: sandbox OFF (boundaries.sandbox=off). Open question for round 2 —
  «Межа, яку перевіряє операційна система, — це той самий детерміністський варіант, який ти відкинув,
   чи це і є той простий надійний варіант, про який ти казав?»
```

### 4.4 The sandbox keys, specified so that turning it on is one value

```
boundaries.sandbox            DEFAULT-PROPOSED: off        # off | workers | all
boundaries.sandbox_docker     DEFAULT-PROPOSED: orchestrator_only
                                                           # socket_open | exclude_docker | orchestrator_only
boundaries.block_reads_outside DEFAULT-PROPOSED: false
boundaries.write_roots        DEFAULT-PROPOSED: []          # extra absolute paths; the lane's cwd is always included
```

| `boundaries.sandbox` | Meaning |
|---|---|
| `off` | The plugin passes no sandbox flag. The platform uses the user's own settings. |
| `workers` | Lane sessions are sandboxed and anchored to their worktree; the supervisor and any orchestrator-role session are not. |
| `all` | Everything the plugin starts is sandboxed. **Note §4.4.2 before choosing this.** |

Per-engine, set by the plugin at spawn, passed on the spawn line so it never depends on the state of
his global files:

| Engine | Flag the plugin passes when sandboxing is on |
|---|---|
| Claude Code | `--settings` with `{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false,"failIfUnavailable":true}}` (VERIFIED as effective) |
| Codex | `-c sandbox_mode="workspace-write"` with `[sandbox_workspace_write] writable_roots` = the lane's worktree (VERIFIED; his `~/.codex/config.toml:7` is `danger-full-access` today, so this is a real change) |
| Gemini CLI | `SEATBELT_PROFILE=permissive-open` (CLAIMED) |
| opencode, Kimi, pi, Aider | **no OS sandbox exists.** Either wrap with `codex sandbox -- <cmd>` (VERIFIED as a standalone Seatbelt front-end that is already installed; INFERRED that wrapping another agent CLI works — the mechanism is generic `exec` under a profile, not executed against a full agent) or accept the lane is outside the boundary and say so in preflight. |

#### 4.4.1 The Docker fork — there is no configuration that gives sandboxed Docker

VERIFIED: inside the sandbox the daemon socket is unreachable, so `docker compose down -v` is
**structurally impossible** — and so is every lane bringing up its own stack, which Д4 [433] requires.

| Value | What it does | Price |
|---|---|---|
| `socket_open` | `sandbox.network.allowUnixSockets` for the docker socket | The docs are blunt: allowing `/var/run/docker.sock` *"effectively grants access to the host system through the Docker socket."* Not a partial reopening. |
| `exclude_docker` | `sandbox.excludedCommands` for `docker` | Narrower; the `docker` binary then runs wholly outside the boundary, so an unscoped `down` is back on the table and needs §3 and a deny rule to catch it |
| `orchestrator_only` (**default**) | Lanes are sandboxed and never touch Docker; the supervisor is the only actor permitted to bring stacks up and down, with every project name from the registry | Smallest blast radius per role, and it matches the role model the plugin already has for accounts. Costs: a lane cannot run `docker compose logs` for its own stack without asking. |

This default only takes effect when `boundaries.sandbox` is not `off`. §12 Q8 puts the fork to him.

#### 4.4.2 The teardown collision, and how this spec avoids it

VERIFIED: a sandboxed session could not signal a process **it had itself started** in an earlier Bash
call, because each Bash call is its own sandbox instance. Taken alone, the sandbox satisfies R1-16 by
breaking Д3.

**It does not bite here**, because of §3.7: the *supervisor* creates every process and the supervisor
is never sandboxed under `workers`, and under `all` the teardown path is listed in
`sandbox.excludedCommands`. A lane never needs to signal anything, because a lane never creates
anything. This is the second place where G6 pays for itself.

### 4.5 `session.permissions` — the flag the plugin passes when he has configured nothing

```
session.permissions      DEFAULT-PROPOSED: inherit    # inherit | prompt | bypass
```

`inherit` means **the plugin passes no permission flag at all** and the platform uses his own
settings. That is [357] read literally: «технічні обмеження середовища користувач за потреби
налаштовує сам».

**An unrecognised value is a config error that refuses the run (exit 78). It is never a silent
fallback.** VERIFIED, `plugins/harness/bin/harness-spawn.sh:32-39`:

```sh
perm_flag() {
  case "$(cfg '.session.permissions' 'bypass')" in
    bypass) echo "--dangerously-skip-permissions" ;;
    ...
    *) echo "--dangerously-skip-permissions" ;;
```

The shipped plugin defaults to the maximum-blast-radius flag **and** falls back to it on an
unrecognised value. That is C8-A4: the plugin is not abstaining from configuring the environment; it
configures it on every spawn and picks the least safe option both times.

⚠ **TENSION, and it is the honest one.** `inherit` on this machine means *no boundary*, because his
own `~/.claude/settings.json` sets `"permissions": {"defaultMode": "bypassPermissions"}` and his
`~/.codex/config.toml:7` sets `sandbox_mode = "danger-full-access"` (both VERIFIED). So the faithful
default and the safe default are different values, and I shipped the faithful one. **Preflight prints
the effective posture it detected from the platform's own report**, so he sees what he is actually
running with rather than what the plugin chose:

```
posture: claude-code/<profile-A>  permissions=bypassPermissions (from ~/.claude/settings.json)  sandbox=off
posture: codex/work              sandbox_mode=danger-full-access (from ~/.codex/config.toml:7)
```

§12 Q6 is this question, and it is a blocker.

### 4.6 `redlines.enforce` — making his own file load-bearing, off by default

```
redlines.enforce         DEFAULT-PROPOSED: false
redlines.enforce_match   DEFAULT-PROPOSED: paths_only    # paths_only | paths_and_commands
```

When on, the plugin registers **one** `PreToolUse` hook that reads the same file and hard-denies what
its `[never]` and `[owner-only]` entries name. VERIFIED by execution today: a hook returning
`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",…}}` on exit 0 blocked
a Bash call in a session launched with `--permission-mode bypassPermissions`; `~` and relative paths
are expanded **before** hooks run, so a path matcher cannot be dodged by respelling.

`paths_only` is the default match mode and the reason is in §4.1: path rules match a resolved path;
command-string rules match a spelling and were defeated in one step. `paths_and_commands` exists and
is labelled advisory in its own preflight line.

Three honest limits, printed when it is turned on: hooks run **unconstrained on the host and outside
the Bash sandbox**, so a hook is a policy check and not a containment wall; a session that can write
`.claude/hooks/` can disarm it unless the sandbox is also on; and it is **Claude-Code-only** — Codex
hooks are plausible and unverified, Gemini and opencode have no equivalent (VERIFIED/CLAIMED per
C8 §4.1).

It is off because it is exactly «окрема обов'язкова процедура» he said was unnecessary. §12 Q2 is
whether that ceiling was on the plugin or on him.

### 4.7 What is not shipped

- **Whole-process isolation (Option F).** The sandbox runtime is a **beta research preview** whose
  config format may change, and whose own doc says *"Without a valid `~/.srt-settings.json`, the
  runtime starts anyway, blocks network access, and confines writes to built-in runtime paths…
  Don't take a clean start as proof your settings loaded"* (CLAIMED). A thing that starts clean and
  is not configured is the exact failure class this rebuild exists to remove, and 34 unattended hours
  is a poor place for a beta. Recorded because it is the only rung that also contains hooks and MCP
  servers, and because «оверінжиринг» [370] was said about a *container*, not about this.
- **PATH shims** for `docker`/`pkill`. Good ergonomics, terrible boundary: `/usr/local/bin/docker`,
  `env -i`, a script that resets `PATH`, or the socket directly all walk past it (INFERRED, not
  seriously contestable).
- **`sandbox-exec` directly.** Deprecated by Apple (VERIFIED in the man page here). Use the engines'
  front-ends, which are supported wrappers around the same kernel facility.

### 4.8 Recommended default posture, per platform

Read the `sandbox` bit from the adapter's own `capabilities()` map (ADAPTER-CONTRACT §2.0). This table
is what preflight prints; it changes nothing by itself while `boundaries.sandbox: off`.

| Platform | `sandbox` | Default posture today | If he turns the sandbox on |
|---|---|---|---|
| Claude Code | true | B + D + A; `permissions: inherit` | `--settings` sandbox, anchored to the worktree |
| Codex CLI | true | B + D + A | `-c sandbox_mode="workspace-write"`, `writable_roots` = worktree |
| Droid | true | B + D + A | per its own sandbox config (CLAIMED) |
| Qwen Code | true (Seatbelt) | B + D + A | `SEATBELT_PROFILE` (CLAIMED) |
| Cursor CLI | true (best in field, **install 372 days old and not logged in**) | **not dispatchable** until upgraded | — |
| Copilot CLI | true (fail-closed hazard) | B + D + A | per its config (CLAIMED) |
| Gemini CLI | true | B + D + A | `SEATBELT_PROFILE=permissive-open` (CLAIMED) |
| Amp | capable, **defaults unsafe** | B + D + A, and preflight prints the unsafe-default warning | per its config |
| OpenCode | **no OS sandbox found** | B + D + A + the §4.8.1 line | wrap with `codex sandbox --` (INFERRED) |
| **Kimi Code** | **false — no sandbox, hooks fail open** | B + D + A + the §4.8.1 line | wrap with `codex sandbox --` (INFERRED) |
| **pi** | **false — no sandbox** | B + D + A + the §4.8.1 line | wrap with `codex sandbox --` (INFERRED) |
| Aider | weak | leaf executor only | — |

#### 4.8.1 The line printed for a lane with `sandbox: false`

```
lane L3 (kimi/personal): this platform has no OS sandbox and its hooks fail open.
  On this lane the red-line file is the only barrier. A model that ignores it has nothing beneath it.
  To narrow what this lane may be given, set lanes.L3.eligibility; to give it teeth, set redlines.enforce.
```

That is a statement, not a restriction. `ARCH-adapters` ships a **mandatory** deny list here and
`JUDGE-fidelity` marks it down for shipping enforcement machinery in a subset case. Naming the fact
costs nothing and changes no decision of his.

---

## 5. The two named cases

### 5.1 Case 1 — «іншою папкою, іншим проектом» [370]

**Covered, mechanically, for everything the orchestrator itself does**, by §3: there is no code path
that can name a process, container or worktree that is not in this run's registry, and everything in
the registry was created by this run inside this project's scope. Not covered for what a *lane* does
inside its own tool calls, unless `boundaries.sandbox` is on — where it is VERIFIED covered
completely (§4.3's first row: a write to a neighbouring project returned `operation not permitted`).

**Worked example.** He has `~/Work/other-project` with its own compose stack `other-project`, up.
The run targets `~/Work/<work-project>`.

1. Preflight resolves `project.root = /Users/sasha-marchuk/Work/<work-project>` (§5.3) and prints it.
2. Every compose project the run creates is named `orc-<run6>-<lane>` and carries
   `orc.project=sha256(project.root)`.
3. Teardown iterates `owned.ndjson`. `other-project` has no line, so `orc_destroy` cannot be called
   with it — there is no `res` id to pass (§3.8 refusal 1).
4. §6.8's proof records: `containers present: 7 · ours: 5 · torn down: 5 · left untouched: 2`.

### 5.2 Case 2 — «в тій самій папці я паралельно працюю над чимось» [370]

This is the hard one, and the honest answer has three parts.

**Part 1 — processes and containers: covered exactly.** This is the case that actually bit twice.

- `pkill -f 'playwright test'` cannot be written (§3.9 lint rule 1), and could not resolve to
  anything if it were, because identity is a registry line, not a pattern (§3.1).
- `docker compose down -v` with no project cannot be written (lint rule 3) and its arguments cannot
  come from the environment (lint rule 6).
- **A7's gate is closed too**, and this one is new here. FIELD-NOTES §10.2 (J-ORCH-45) recorded
  validators told to *"hold suites until `ps` shows zero playwright-test processes before gating"* —
  which, when he runs a suite by hand at 01:50, either stalls the night or kills his suite. **Rule:
  any wait-for-quiescence gate waits only on registry entries, never on a machine-wide `ps`.**
  Config: `gates.quiescence_scope: run_only` (DEFAULT-PROPOSED). His process is invisible to the gate,
  which is the correct behaviour in both directions.

**Part 2 — files created by the run: converted into case 1.** §5.4's worktree anchoring means the
run's edits are not in his folder at all.

**Part 3 — files in the main checkout: NOT covered, and nobody covers it.** VERIFIED,
`LANDSCAPE.md` §5: *"Thirteen of the eighteen rows… are `yes` or `partial` on worktree isolation. Not
one of them protects the human's concurrent edits in the same checkout… Confirmed unsolved, and
confirmed as something that must be invented rather than adopted."* `ARCH-adapters` §19 says the same:
*"They do nothing about files."* With `boundaries.sandbox` on, a lane confined to its worktree cannot
write to the main checkout at all — which is the nearest thing to a solution available, and it is the
`workers` value of one key. Without it, nothing in this document stops a lane writing a file he has
open. **That is stated in preflight, once:**

```
boundary: the run's own worktrees are separate from your checkout. Nothing here prevents a lane
  writing a file in <project-root> that you have open. boundaries.sandbox=workers would.
```

### 5.3 Where the allowed folder comes from (closes C8-A8)

C8-A8's attack is that three implementers derive the scope root three ways and build three products.
**Specified, in order, first match wins:**

1. `--project <path>` on the command line.
2. `project.root` from the resolved config (six slots, §2.1).
3. The git toplevel of the **main checkout** of the directory the run was launched from, via §2.1's
   `main_root()`.

Then, unconditionally:

4. If the resolved root does not contain the configured work source (the board's project, the ticket
   directory), **preflight refuses, exit 78**, naming both paths. This is the case where he launches
   from `~/Work/claude-plugins` while the tickets target `<work-project>`; implementer A's version
   silently spends the night failing at the first edit.
5. The scope root is **per run**, not per task and not per session. A ticket that names a path outside
   it is **refused at claim time**, with the ticket left ready and one notification. Widening requires
   a config change and a new run.
6. `<state-root>` is **outside** the scope root by construction (§3.2), and is always writable.

The common-ancestor derivation (`~/Work`) is forbidden: it inverts case 1 into "the boundary contains
every project he owns".

### 5.4 Worktree anchoring

Д4 [433] «Дефолтна пропозиція, щоби абсолютно все виконувати в різних ворк трі» promoted from a
recommendation to the boundary mechanism, per C8 Option D.

```
boundaries.worktree            DEFAULT-PROPOSED: true
boundaries.worktree_root       DEFAULT-PROPOSED: <dirname(project.root)>/<basename(project.root)>.orc/<run-id>/
boundaries.worktree_on_finish  DEFAULT-PROPOSED: remove       # remove | keep | keep_if_dirty
boundaries.worktree_base       DEFAULT-PROPOSED: the repository's default branch
```

A **sibling** directory, not one inside the checkout: a worktree inside the repo makes `git status` in
the main tree noisy for him, and the previous run's own worktrees were siblings
(`<work-project>-phase-13`, `-22`, `-23`, VERIFIED FIELD-NOTES §7).

Three rules that come straight out of the record:

1. **Worktree identity is verified at spawn, never assumed.** FIELD-NOTES §11.8 (VERIFIED): GSD
   computed a branch name one word off; a lane slug reused from an earlier wave spawned a worker into
   a **stale worktree with a stale prompt**. Before launch, assert that the worktree path is new (or
   is registry-owned by this lane), that `git -C <wt> rev-parse --abbrev-ref HEAD` equals the intended
   branch, and that `git -C <wt> rev-parse HEAD` equals the recorded `base_sha`. Any mismatch refuses
   the launch and journals; it does not "fix" the name.
2. **Owner-facing files never live inside a worktree.** FIELD-NOTES §12.5 (VERIFIED): `QUESTIONS.md`
   and `JOURNAL.md` forked, and a real question sat invisible for an hour. The red-line file (§2.1),
   the Д6 questions channel, the control file and the run report all live under `<state-root>` or the
   main checkout.
3. **A worktree is a convention until something enforces cwd.** Stated here so nobody reads §5.2
   part 2 as stronger than it is: a lane can `cd` out of its worktree unless `boundaries.sandbox` is
   on.

---

## 6. End-of-run cleanup (Д3)

### 6.1 The terminal condition

Checked every tick:

```
FINISH  when   no lane in a non-terminal state
         AND   no claimable ready ticket
         AND   (intake frozen OR intake quiet for >= cleanup.intake_grace_seconds)
         AND   (no human-blocked item OR behaviour.when_only_human_blocked != wait)
```

```
cleanup.intake_grace_seconds   DEFAULT-PROPOSED: 300
```

Rationale: Д2 allows work to be added mid-run, and without a grace window a run that drains at 03:00
exits thirty seconds before his 02:59 ticket is picked up. (Value taken from `ARCH-reliability` §12.1;
the reasoning is his Д2, not mine.)

`LANDSCAPE.md` §5 records that this exact behaviour — *"run a queue unattended for hours, stop cleanly
when it empties, and kill only what you started"* — returns **zero hits** for
`drainAndExit | exitWhenIdle | shutdownWhenEmpty | queueEmptyExit` across every multi-ticket tool
surveyed (VERIFIED). It is nine lines here because the queue and the lane set are both directories.

### 6.2 The algorithm

Run state `finishing`. Numbered, and this is the build order.

1. **Freeze intake.** Append `run.finishing` to `journal.ndjson`. No new claims.
2. **Sleep fence.** If the last tick's `wall_delta − mono_delta > sleep.gap_seconds` (**60**,
   DEFAULT-PROPOSED), append `machine.wake` and **wait `sleep.grace_seconds` (120,
   DEFAULT-PROPOSED) before proceeding.** No resource may be judged absent inside the grace window.
   Graft G3 from `JUDGE-survival`. Without it, `[2026-09-07T09:08:21Z] watch: orchestrator dead + no
   live sessions for 3 ticks — tearing down (Mac may sleep)` — the way the previous run actually ended
   (VERIFIED, FIELD-NOTES §10.1) — becomes a teardown that reads every probe as "already gone" and
   records a clean finish it never performed.
3. **Stop lanes**, soft or hard per the stop verb in force. A soft finish lets each lane reach its
   step boundary; a hard stop signals immediately. Each lane's own resources are resolved by its
   wrapper's trap first, so most of step 4 is already done by the time the supervisor gets there.
4. **Walk `owned.ndjson` in reverse `seq` order.** For each `res` with a `created` line and no
   `resolved` line, call `orc_destroy <res>` (§3.8), then **assert** by §6.3's proof, then append the
   `resolved` line. Reverse order matters: a compose project is torn down before the worktree its
   `docker-compose.yml` lives in.
5. **Self-exclusion.** Skip any entry whose identity resolves to the supervisor's own process, process
   group or session. The supervisor is exempt from its own teardown until step 8 (`ARCH-minimal`
   §9.1's carve-out). This is what stops A11's "the fifth orchestrator kills the fourth's entry, or
   its own".
6. **Release claims and write final board states.**
7. **Write the proof** (§6.8) and the run report.
8. **Deregister and exit.** The supervisor releases the lock last.

### 6.3 The closed set of teardown ops, with their exact commands and proofs

Every command below takes **every** argument from the registry line. None reads the environment.

| `op` | Command | Assertion (run after, never trusted from the exit code) |
|---|---|---|
| `signal` | `kill -TERM <pid>`; after `cleanup.grace_seconds` (**30**, DEFAULT-PROPOSED) `kill -KILL <pid>` | `kill -0 <pid>` fails, **or** `ps -o lstart= -p <pid>` no longer equals `pid_start` |
| `signal_group` | `kill -TERM -- -<pgid>`; then `kill -KILL -- -<pgid>` | no pid in `ps -o pid=,lstart= -g <pgid>` matches the recorded leader tuple |
| `adapter_stop` | `adapter.stop(handle, mode)` | adapter listing no longer names the session **and** the `signal` proof on its recorded pid |
| `compose_down` | `docker compose -p <project> down` (`-v` only when `cleanup.remove_volumes: true`) | `docker ps -aq --filter label=orc.run=<run> --filter label=orc.lane=<lane>` returns zero bytes |
| `worktree_remove` | `git -C <project.root> worktree remove --force <path>` | `test ! -e <path>` **and** `git worktree list --porcelain` does not name it |
| `release_record` | none | n/a |

**Assert by observation, not by the command's word.** ADAPTER-CONTRACT §2.4 invariant 10 records
`cursor-agent worker kill` reporting success and leaving the process at 100 % CPU (VERIFIED). The
same class produced FIELD-NOTES §4.1's merge that printed `Already up to date` and moved nothing.

```
cleanup.remove_volumes    DEFAULT-PROPOSED: true
```
Rationale: FIELD-NOTES §11.11 recorded **about 150 orphaned Docker volume pairs** from a dead run —
his «не засоряти систему» [430]. It is safe here only because the project name is run-scoped; it was
catastrophic in the incident only because the project name was the default.

### 6.4 Verdicts, and what makes a run `degraded`

| Verdict | Meaning |
|---|---|
| `gone` | the assertion passed after the teardown ran |
| `absent` | the probe found it already gone before teardown — fine, and recorded distinctly |
| `left_deliberately` | config said so (`worktree_on_finish: keep`, a `port_block`) |
| `failed` | the teardown ran and the assertion did not pass |

**Any `failed` makes the run `degraded`, exit 6, and the report names every unresolved resource with
the exact command to finish it by hand.** The run never claims a clean finish it cannot evidence.
Nothing is ever swallowed: FIELD-NOTES §11.4's whole inventory is "reported success while doing
nothing".

### 6.5 Crash-safety of the cleanup path itself

Teardown may itself be executed by a restarted supervisor or by the warden — which is C8-A2's sharpest
point, because that process starts with **no environment at all** (VERIFIED, FIELD-NOTES §12.4). Three
properties make that safe:

1. Every identifier is on disk in `owned.ndjson`, never in a variable (§3.3, lint rule 6).
2. `orc_destroy` refuses a resource that already has a `resolved` line (§3.8), so a replayed teardown
   is a no-op rather than a second kill.
3. An `intent` line with no `created` line is **probed, not destroyed**: run its `probe`, and if the
   probe finds the thing, promote it to `created` with the observed identity and then tear it down;
   if the probe finds nothing, resolve it `absent`. This is the only place a resource enters the
   registry after the fact, and it enters through a read.

**The `unsafe` class** (graft G10 from `JUDGE-survival`): a resource whose teardown is not provably
idempotent and whose replay could duplicate an irreversible external effect is declared
`idempotency: "unsafe"` in its `intent` line. On a crash-recovery pass, an `unsafe` orphan is
**escalated to the Д6 questions channel and held — never replayed.** None of the seven types in §3.4
is `unsafe` today; the field exists so that the first op that is cannot silently take the replay path.

### 6.6 Nested orchestrators (Д3's first word, R1-10's prohibition)

Д3's teardown list starts with «свої якісь там **оркестратори**» [430]. R1-10 [300] forbids two
orchestrators running at once, confirmed at [304]. Both VERIFIED.

**Specified as stated, which means the case is representable and cannot arise today:**

- `type: "session"` with `role: "orchestrator"` is a legal registry entry, so Д3's sentence has
  something to refer to.
- The run-level lock (one per project) makes a second *supervisor* impossible; a second orchestrator
  *session* is refused at claim time by the same invariant.
- Step 5's self-exclusion means a restarted supervisor that inherited a run (Д10 [497]) never stops
  its own process or the entry describing it.
- Therefore the list is honoured, the prohibition is honoured, and the only orchestrator entry a
  teardown will ever act on is a **stale record from a previous supervisor of this same run**, which
  is exactly what Д10's restart hygiene wants removed.

§12 Q12 asks whether that is what he meant, because two readings of his sentence are live.

### 6.7 The previous run's residue (C8-A1)

Д3 scopes teardown to provenance and R1-16 scopes intervention the same way; read together, **a
crashed run's leftovers are unreclaimable by anyone**. FIELD-NOTES §11.11's 150 orphaned volume pairs
is the observed output of this hole (VERIFIED).

```
cleanup.orphan_reclaim   DEFAULT-PROPOSED: off     # off | same_tool_confirm | same_tool_auto
```

| Value | Behaviour |
|---|---|
| `off` (**default**) | **Strictly his rule.** Preflight lists the residue and prints **one exact command per item**. Nothing is touched. If residue collides with a port or a worktree path this run needs, preflight **refuses** (exit 75) rather than reclaiming. |
| `same_tool_confirm` | Reclaim only resources carrying **this tool's** `orc.run` label, for **this** `orc.project`, whose owning run's lock is provably free, and only after an explicit `--reclaim` or an interactive yes. |
| `same_tool_auto` | The same, unattended. |

Preflight output under the default:

```
residue from run 20260911T212252Z-4b1e (lock free, supervisor gone):
  12 containers   docker compose -p orc-4b1e-l2 down -v
  2 worktrees     git -C /Users/…/<work-project> worktree remove --force /Users/…/<work-project>.orc/…/L2
  150 volumes     docker volume rm $(docker volume ls -q --filter label=orc.run=20260911T212252Z-4b1e)
  (cleanup.orphan_reclaim=off — nothing was touched)
```

`ARCH-reliability` ships `same_tool_confirm` as its default and admits in its own open list that it is
*"a widening and he did not authorise one"*. I ship `off` and put the question to him (§12 Q9). The
honest cost of `off`: each crashed run leaves another layer, and the only actor permitted to clear it
is the human the tool exists to keep asleep.

### 6.8 The proof that nothing of his was touched

Written to `<state-root>/runs/<run-id>/CLEANUP-PROOF.md` at step 7, rendered by **bash + jq, zero
model tokens**. It has three parts, and the third is the one that makes it a proof rather than a log.

#### Part A — every destructive action, and the line that authorised it

One row per action, joined from `journal.ndjson` and `owned.ndjson`:

| action | res | type | identity (as recorded at creation) | created | command run | assertion | verdict |
|---|---|---|---|---|---|---|---|
| 1 | r14 | docker_compose_project | `orc-a7f3c1-l1` labels `orc.run=20260919T231204Z-a7f3c1` | 23:12:06Z | `docker compose -p orc-a7f3c1-l1 down -v` | `docker ps -aq --filter label=orc.run=…` → 0 bytes | `gone` |
| 2 | r11 | process_group | pgid 80476, leader start `Fri Sep 19 23:11:58 2026` | 23:11:58Z | `kill -TERM -- -80476` | no member matches the leader tuple | `gone` |
| 3 | r09 | git_worktree | `/Users/…/<work-project>.orc/20260919T231204Z-a7f3c1/L1`, branch `orc/L1-SFW-214`, base `9b2e1f0` | 23:11:55Z | `git -C /Users/…/<work-project> worktree remove --force …` | path absent; not in `worktree list` | `gone` |

**The structural claim this table rests on:** a destructive command can only be executed by
`orc_destroy` (§3.8), `orc_destroy` refuses without a `created` line, and `tests/lint-blast-radius.sh`
fails the build if any destructive verb appears anywhere else in plugin source (§3.9). So **a row with
no authorising line is not merely absent from this table — it is unreachable.** That is the difference
between an audit log and a proof, and FIELD-NOTES §11.9 is the reason to insist on it: every commit
gate in that inventory was found broken *by mutation*, not by failing.

#### Part B — the negative side: what was present and left alone

Read-only enumeration, run **after** teardown:

```sh
docker ps -a  --format '{{.ID}}\t{{.Label "com.docker.compose.project"}}\t{{.Label "orc.run"}}'
docker volume ls --format '{{.Name}}\t{{.Label "orc.run"}}'
git -C "$PROJECT_ROOT" worktree list --porcelain
```

```
containers present after teardown: 7
  ours (orc.run=20260919T231204Z-a7f3c1): 0    — all 5 torn down, verdicts above
  other runs of this tool:               0
  not ours (no orc.run label):           7     — LEFT UNTOUCHED
    <work-project>-app-1        project=<work-project>
    <work-project>-postgres-1   project=<work-project>
    …
worktrees present: 1
  main checkout /Users/sasha-marchuk/Work/<work-project> — LEFT UNTOUCHED
  ours: 0 (2 removed)
```

VERIFIED that this enumeration works on this machine: `docker ps -a --format '{{.Names}}\t{{.Label
"com.docker.compose.project"}}'` returned `<work-project>-app-1  <work-project>` and
`<work-project>-postgres-1  <work-project>` today. **Listing is not acting** (§3.1), so Part B does not
violate R1-16 — but it is the one place this spec reads outside the run's own scope, and §12 Q13 puts
that to him.

#### Part C — the claims this proof does NOT make

Printed inside the file, because a proof that overstates itself is worse than none:

```
This proves what the orchestrator itself destroyed and that each destruction matched a resource it
created. It does not prove:
  - that no lane process wrote or deleted a file outside its worktree (nothing here watches files;
    boundaries.sandbox=workers would enforce it)
  - that no lane ran a destructive command inside its own tool call (the registry constrains the
    orchestrator, not its children)
  - that no secret reached a transcript (see the red-line file's own footer)
  - anything about resources created by a previous run (cleanup.orphan_reclaim=off)
```

#### Part D — where he sees it

Д11 [512] «мінімальну кількість аутпуту і стокінгів». So: **nothing is printed during the run.** The
proof file is written; `orchestrator:status --proof` prints Part B's four summary lines and the count
of `failed` verdicts, in bash, with zero model turns. **One** notification is sent through the R1-17
channel only when a verdict is `failed` or residue was refused — never on a clean finish.

```
cleanup.notify_on_clean   DEFAULT-PROPOSED: false
cleanup.proof             DEFAULT-PROPOSED: true
```

### 6.9 Exit codes

| Code | Meaning |
|---|---|
| 0 | finished; every registry entry `gone`, `absent` or `left_deliberately` |
| 6 | **degraded** — work happened, at least one teardown verdict is `failed`; every one named |
| 64 | `orc_destroy` refused (no line / not created / already resolved / unknown op) — a bug, journalled, run continues |
| 69 | the project lock is held; the holder is named; nothing was done |
| 70 | a teardown could not be asserted at all (the probe itself failed) |
| 75 | refused to start: residue from a previous run collides with a port or path this run needs, and `orphan_reclaim: off` |
| 78 | preflight refusal (red-line file unreadable, scope root mismatch, unrecognised `session.permissions`, …) |

---

## 7. Worked example — one full night, end to end

`run-id = 20260919T231204Z-a7f3c1`, `project.root = /Users/sasha-marchuk/Work/<work-project>`, two lanes,
`boundaries.sandbox: off`, everything else at its default.

**23:12:03** Preflight. Resolves `redlines.path` → `/Users/…/<work-project>/.orchestrator/RULES.md` through
the main checkout; reads 1,174 bytes, 5 rules, `sha256:3f9c…a2`. Prints the posture lines of §4.5 and
the open-question line of §4.3. Lists residue from run `…4b1e` and finds no port collision. Starts.

**23:11:55 → 23:12:06** Lane L1 comes up, in this order and no other:
`mkdir claims/SFW-214.d` → `owned.ndjson` intent `r09` (worktree) → `git worktree add` → created `r09`
→ intent `r11` (process_group) → `set -m` spawn → created `r11` with pgid 80476 and its leader start
time → `lanes/L1/start.json` carrying `redlines_sha256:3f9c…a2` **before the platform is launched** →
launch → the lane brings up its stack → intent `r14` (compose project `orc-a7f3c1-l1`, labels) →
`docker compose -p orc-a7f3c1-l1 up -d` → created `r14` with the container ids.

**01:50** He runs a Playwright suite by hand in the main checkout. L2's validator reaches its
quiescence gate. Under `gates.quiescence_scope: run_only` the gate looks only at registry entries,
sees none of its own running, and proceeds. His suite is invisible to it and survives. *(Under the
previous generation's machine-wide `ps` rule this is the fork where the night either stalls or his
suite dies.)*

**03:15** He appends `- [never] Не робити міграції на локальній базі.` The supervisor's next tick sees
the digest change, journals `redlines.changed 5 → 6`, and notifies:
`3 lanes still hold the old text: L1 (SFW-214), L2 (SFW-219). They will pick it up on their next launch or reseed.`
He knows the rule has not landed yet. *(Under a silent implementation he goes back to sleep believing
it has.)*

**04:02** L1 compacts. Compaction proof received; the §2.5.1 block is re-injected into the next turn,
now with 6 rules and the new digest. The rule lands here.

**05:40** Queue drains. `cleanup.intake_grace_seconds` expires at 05:45. `finishing`.

**05:45:01** Sleep fence: `wall_delta − mono_delta = 0.3 s`, no wake, proceed.

**05:45:02 → 05:45:41** Reverse walk: `r14` → `docker compose -p orc-a7f3c1-l1 down -v` → assert label
filter empty → `gone`. `r11` → `kill -TERM -- -80476`, group dead in 1.2 s → `gone`. `r09` →
`git worktree remove --force` → path absent → `gone`. Same for L2's three. The supervisor's own pgid
appears in no entry (§3.7 means it never created itself).

**05:45:42** `CLEANUP-PROOF.md`: 6 actions, 6 `gone`, 0 `failed`; Part B reports
`containers present: 7 · ours: 0 · not ours: 7 — LEFT UNTOUCHED`, naming `<work-project>-app-1` and
`<work-project>-postgres-1`. No notification is sent, because `cleanup.notify_on_clean: false` and nothing
failed. Exit 0.

**What he sees in the morning:** nothing, until he types `orchestrator:status --proof`. That is Д11.

---

## 8. The build order, smallest useful first

1. `owned.ndjson` writer + `orc_owned_lookup` + the seven identity shapes (§3.2–§3.4). ~120 lines.
2. `orc_spawn` with `set -m` and the pid/start/argv tuple (§3.5). ~25 lines.
3. `orc_destroy` and the six teardown ops with their assertions (§3.8, §6.3). ~140 lines.
4. `tests/lint-blast-radius.sh`, six rules (§3.9). ~60 lines. **Verify it by mutation**: write each
   forbidden pattern into a scratch file on purpose and confirm the build goes red.
5. The red-line reader, renderer and digest (§2.1–§2.5). ~90 lines.
6. Preflight's five refusals for this cluster (§2.6, §4.5, §5.3, §6.7). ~70 lines.
7. Teardown walk, verdicts, `CLEANUP-PROOF.md` (§6.2, §6.8). ~130 lines.
8. Worktree anchoring with the three spawn assertions (§5.4). ~80 lines.
9. The sandbox keys, unused while off (§4.4). ~50 lines.
10. `redlines.enforce`'s single hook, off (§4.6). ~70 lines.

INFERRED **~835 lines**, within `JUDGE-cost`'s envelope for the whole system (~1,350–1,400 against the
previous generation's measured 1,879 lines of bash).

**Step 4's mutation check is not optional.** This repository's own memory rule is that its harness
greps prose and *"tests can pass vacuously"*, and FIELD-NOTES §11.9 records that **every** commit gate
in that inventory was discovered broken by mutation rather than by failing. Until each invariant here
has been broken on purpose and the suite has gone red, this specification is a claim, not a property.

---

## 9. Tensions carried forward, in one list

Numbered so he can overturn them individually.

1. **§2.3's four restriction types are mine.** He said types exist and named none.
2. **§2.7's `next_launch`** means a rule added at 03:15 does not bind a lane running at 03:22. Platform
   fact, mitigated by a notification, not solved.
3. **§4.5's `inherit`** is the faithful default and, on his machine today, the least protective one.
   The faithful value and the safe value are different, and I shipped faithful.
4. **§4.3 ships the sandbox off** although it is the only mechanism verified to hold. That is his
   recorded decision, and Q1 is the first question of round 2.
5. **§5.2 part 3 is not covered by anything here**, and `LANDSCAPE.md` confirms nobody covers it.
6. **§6.7's `off`** honours his rule and guarantees residue accumulates across crashed runs.
7. **§6.8 Part B reads outside the run's scope** to prove a negative. Reading is not acting, and it is
   still the one place the tool looks at things that are his.
8. **§2.4's cap** bounds a file he said may grow without bound.
9. **§4.6's hook is precisely «окрема обов'язкова процедура»** he said was unnecessary. It ships off,
   and it ships.
10. **R1-15 and the key clause of R1-16 are both unratified.** Everything above is built on two answers
    he never confirmed, one of which he ended by asking whether it answered the question.

---

## 10. Defaults register — every key this spec introduces

**Nothing outside this table may invent a default at runtime.** (Discipline borrowed from
`ARCH-adapters` §17, which `JUDGE-fidelity` §5.1 rates the strictest in the set.)
Scope: **U** user slots 3–4 · **P** project slots 1–2 · **L** personal-project slots 5–6 · **R** per run.
Apply: **now** · **next-launch** · **next-run**.

| Key | Type | DEFAULT-PROPOSED | Scope | Apply | Rationale (one line) |
|---|---|---|---|---|---|
| `redlines.path` | path | `<project-root>/.orchestrator/RULES.md`, read from the **main checkout** | U P L | next-launch | A worktree fork hid an owner-facing question for an hour (FN §12.5) |
| `redlines.untagged_type` | enum | `never` | U P L | next-launch | Fail closed: a preference read as absolute stalls a task; an absolute read as a preference destroyed a stack |
| `redlines.max_bytes` | int | `8192` | U P L | next-launch | Injected in every session and after every compaction; ~80 rules is a year of incidents |
| `redlines.on_oversize` | enum | `refuse` | U P L | next-run | A silently truncated prohibition list is "reported success while doing nothing" |
| `redlines.on_unreadable` | enum | `refuse` | U P L | next-run | R1-15 says reading is mandatory; the fail-closed branch is the only one that honours that |
| `redlines.apply` | enum | `next_launch` | U P L R | now | A running session keeps what it booted with (FN §8); the notification makes that visible |
| `redlines.watch` | bool | `true` | U P L | now | Detecting the change is what makes the notification possible |
| `redlines.enforce` | bool | `false` | U P L | next-launch | It is exactly the separate mandatory procedure he said was unnecessary [357] |
| `redlines.enforce_match` | enum | `paths_only` | U P L | next-launch | A command-string deny was defeated by `sh -c` in one step, VERIFIED today |
| `boundaries.sandbox` | enum | `off` | U P L | next-launch | R1-15/R1-16 as recorded; the question is §12 Q1 |
| `boundaries.sandbox_docker` | enum | `orchestrator_only` | U P L | next-launch | Smallest blast radius of the three; there is no sandboxed Docker |
| `boundaries.block_reads_outside` | bool | `false` | U P L | next-launch | Sessions legitimately read `~/.claude`, `~/.gitconfig`, toolchain caches; it would be noisy |
| `boundaries.write_roots` | path[] | `[]` | U P L | next-launch | The lane's cwd is always included; extra roots are a deliberate widening |
| `boundaries.worktree` | bool | `true` | U P L | next-run | His own Д4 default [433] |
| `boundaries.worktree_root` | path | `<dirname(root)>/<basename(root)>.orc/<run-id>/` | U P L | next-run | A sibling keeps the main tree's `git status` clean; the previous run used siblings |
| `boundaries.worktree_base` | string | the repository's default branch | U P L R | next-run | Д4 «off the main branch» |
| `boundaries.worktree_on_finish` | enum | `remove` | U P L R | next-run | Д3's «не засоряти систему»; `keep_if_dirty` exists for a lane that died with work |
| `gates.quiescence_scope` | enum | `run_only` | U P L | now | A machine-wide `ps` either stalls the night or kills his suite (FN §10.2) |
| `session.permissions` | enum | `inherit` | U P L R | next-launch | [357] read literally; an unrecognised value is a config error, never a silent bypass |
| `spawn.transport` | enum | `process` | U P L | next-launch | Real lineage; `osascript`-spawned sessions are iTerm2's children, which is why the last run reached for `pkill` |
| `cleanup.intake_grace_seconds` | int | `300` | U P L R | now | Д2 allows mid-run additions; without it a 03:00 drain misses his 02:59 ticket |
| `cleanup.grace_seconds` | int | `30` | U P L | now | TERM before KILL; enough for a trap to write its own teardown |
| `cleanup.remove_volumes` | bool | `true` | U P L | next-run | ~150 orphaned volume pairs from one dead run (FN §11.11); safe only because the project name is run-scoped |
| `cleanup.orphan_reclaim` | enum | `off` | U P L R | next-run | His rule, strictly; the widening is offered, not shipped |
| `cleanup.proof` | bool | `true` | U P L | next-run | Zero tokens, and it is the only after-the-fact evidence of what was destroyed |
| `cleanup.notify_on_clean` | bool | `false` | U P L | now | Д11 [512]: minimum output; a clean finish is not news |
| `sleep.gap_seconds` | int | `60` | U P L | now | Graft G3; a wake must not make every probe read "already gone" |
| `sleep.grace_seconds` | int | `120` | U P L | now | Same; no resource may be judged absent inside the window |

**Not a setting, a build rule:** `pkill`, `killall`, an unscoped `docker compose down`, an unfiltered
`docker … prune`, `git clean`/`git checkout .`/`git reset --hard` outside a run-created worktree, and
**any teardown argument expanded from an environment variable** fail `tests/run-all.sh` (§3.9).

---

## 11. What this specification does not close

Named, because a safety document that implies coverage is its own quiet failure.

1. **Secrets reaching a place nobody scans.** FIELD-NOTES §11.10 (VERIFIED): two local role passwords
   printed in clear text into a session transcript by Playwright's `--trace on`, and *"no automated
   secret scan covers tool output or transcripts."* Nothing writable in the red-line file prevents it;
   a permitted tool doing its declared job wrote a secret to a file the run is supposed to write to.
   It is a **scanning** problem, not a boundary problem. §12 Q15.
2. **File-level collision with his own editing in the same checkout** (R1-16 case 2, part 3). Reduced
   to process-and-container ownership plus worktree anchoring; the file half is unsolved across the
   entire surveyed field (VERIFIED, `LANDSCAPE.md` §5) and is not invented here.
3. **A lane running `pkill` itself.** The registry constrains the orchestrator, not its children. On
   Kimi and pi there is no sandbox beneath the text file at all.
4. **Resource contention.** His own container was `OOMKilled` by two concurrent builds on an 8 GB
   Docker VM, with no live alert (VERIFIED, FIELD-NOTES §5.1). No access-control mechanism addresses
   it; the controls are scheduling controls (`limits.max_concurrent_builds` with `heavy: true` step
   tags, `JUDGE-survival` G5). **Out of this document's scope and it must not be sold as covered.**
5. **The mutation class.** Every commit gate in FIELD-NOTES §11.9 was found broken by mutation rather
   than by failing. Until §8 step 4 is done and each invariant here has been broken on purpose,
   everything above is a claim.

---

## 12. Needs the owner — round 2

Each is a thing I had to decide that he never did. Ukrainian, ready to read out. Ordered by how much
downstream design each unblocks.

**Q1 — blocker.** «Ти сказав, що не хочеш детерміністського варіанту, бо це оверінжиринг. Але те, що
тобі тоді описали — це окреме середовище, контейнер. А ти сам перед тим сказав інше: щоб в
оркестраторі був прописаний шлях, до чого він має доступ. Є спосіб зробити рівно це — щоб цей список
шляхів перевіряла сама операційна система, а не модель. Один рядок у налаштуваннях, ставити на мак
нічого не треба, сесія лишається звичайною сесією у твоєму терміналі. Це для тебе той самий
оверінжиринг, чи це і є той простий надійний варіант, про який ти казав?»

**Q2 — blocker.** «Ти сказав про той один текстовий файл: "Але, так, це максимум". Це читається двома
способами. Перший: плагін не має права робити нічого більшого за цей файл. Другий: один файл — це
максимум, який ти сам готовий вести руками, а те, що плагін робить сам, без твоєї участі, під цю
стелю не підпадає. Яке з двох ти мав на увазі?»

**Q3 — blocker.** «Щоразу, коли плагін піднімає сесію, він сам передає їй прапорець, який вимикає всі
запити на дозвіл — і це і дефолт, і те, що він ставить, коли в налаштуваннях щось незрозуміле. Тобто
найнебезпечніший варіант обрано за тебе. Я поставив дефолтом "не передавати нічого, хай працюють твої
власні налаштування". Це правильно, чи ти хочеш щось інше?»

**Q4 — blocker.** «У файлі заборон я зробив помітки типу: `never`, `owner-only`, `ask-first`,
`prefer`. Якщо ти напишеш рядок без помітки — як його читати? Як абсолютну заборону чи як побажання?
Я поставив "як абсолютну заборону", бо помилка в інший бік коштувала тобі стека.»

**Q5 — major.** «Ти казав, що обмеження бувають різних типів. Я вигадав чотири: ніколи, тільки ти,
спершу спитати, краще не треба. Цього досить, чи типи інші?»

**Q6 — major.** «Правило, яке ти додаси у файл о третій ночі, не дійде до сесії, яка стартувала о
пів на дванадцяту — вона тримає той текст, з яким запустилась. Я зробив так: вона підхопить нове
правило при наступному запуску або перезасіванні, а тобі одразу приходить повідомлення, які саме
лейни ще тримають старий текст. Чи цього достатньо, чи такі сесії треба перезапускати одразу — ціною
втрати їхньої робочої пам'яті?»

**Q7 — major.** «Цей файл — один, і в ньому немає різниці між "це правило проєкту, спільне для всіх"
і "це моє особисте правило". У твоїх же власних правилах конфігурації така різниця є. Тобі потрібні
два рівні заборон, чи одного файлу справді досить?»

**Q8 — major.** «Docker: якщо межу вмикати, то всередині пісочниці docker.sock недоступний — та сама
команда, що знищила твій стек, просто не виконається. Але й лейни не піднімуть свої стеки. Три
варіанти: (а) відкрити сокет — це повертає повний доступ до хоста; (б) вивести `docker` з пісочниці —
вужче, але `docker compose down` знову можливий; (в) пісочниця лише для виконавців, Docker — тільки
для оркестратора. Я поставив (в). Варіанта "Docker у пісочниці" не існує.»

**Q9 — major.** «Попередній ран впав і лишив по собі контейнери й близько 150 томів. За твоїм
правилом новий ран не має права їх чіпати, бо не він їх піднімав. Зараз я зробив так: він їх бачить,
показує тобі точну команду на кожен пункт і не чіпає нічого. Це правильно, чи можна дозволити йому
прибирати те, що має мітку цього ж інструмента і чий ран точно мертвий?»

**Q10 — major.** «Сесії минулого разу стартували через iTerm2, тому вони діти iTerm2, а не
оркестратора — саме через це дійшло до `pkill`. Я зробив дефолтом старт процесом, без вікна: межа
стає справжньою, але ти не зможеш дивитися в вікно лейна й друкувати туди. Прийнятно, чи тобі
потрібні вікна?»

**Q11 — major.** «Звідки береться папка, у межах якої ран взагалі має право діяти? Я зробив: спершу
`--project`, потім значення з конфіга, потім головний чекаут тієї папки, звідки ти запустив. І якщо ця
папка не містить проєкту, з якого беруться тікети, ран не стартує взагалі. Це правильна поведінка?»

**Q12 — major.** «У Д3 твій список того, що треба зупинити, починається зі слова "оркестратори". А в
Р1-10 ти сказав, що двох оркестраторів одночасно бути не може. Що саме малося на увазі: вкладені
оркестратори як окрема роль, чи це просто старий запис у журналі запусків, який треба прибрати?»

**Q13 — minor.** «Щоб довести тобі, що нічого твого не зачепили, наприкінці рану я читаю список усіх
контейнерів і воркітрі на машині — саме читаю, нічого не роблю — і записую: стільки було, стільки
наших, стільки прибрали, стільки лишили недоторканими. Це єдине місце, де інструмент дивиться на речі
поза своїм ранoм. Це нормально?»

**Q14 — minor.** «Наприкінці рану воркітрі за замовчуванням видаляються. Але якщо лейн помер із
незакомміченою роботою — видалити її чи лишити папку? Я поставив "видаляти", бо ти казав не лишати
хвостів.»

**Q15 — minor.** «Паролі минулого разу потрапили в транскрипт через власний `--trace on` Playwright —
всередині робочої теки, дозволеним інструментом, за всіма правилами. Жодна межа і жоден файл заборон
цього не закриває: потрібен сканер виводу й транскриптів. Це окремий пункт для наступного раунду?»

**Q16 — minor.** «У рядку [366] розшифровка зіпсована: "якщо є окремо нетворк 3, то він відповідно до
них теж не має доступу". Найімовірніше ти казав про докерівські мережі або про воркітрі. Що ти мав на
увазі?»

---

## 13. Source index

**Read on this machine for this document:**
`round-1/ANALYSIS-01.md` (R1-13 … Д12) · `round-1/TRANSCRIPT-01.md` rows via the analysis and the
cluster documents ·
`research/clusters/C8-boundaries-safety-{research,challenge,questions}.md` ·
`research/architecture/{ARCH-minimal,ARCH-operability,ARCH-adapters,ARCH-reliability}.md` (boundary,
ledger, teardown and red-line sections) ·
`research/architecture/{JUDGE-fidelity,JUDGE-survival,JUDGE-cost}.md` in full ·
`research/platforms/ADAPTER-CONTRACT.md` §§1–3 (capability tables, `sandbox` bit, H-axis ladder) ·
`research/LANDSCAPE.md` §5 · `plugins/harness/docs/FIELD-NOTES.md` §§5.1, 7, 8, 10.1, 10.2, 11.4,
11.5, 11.8, 11.9, 11.10, 11.11, 12.4, 12.5 ·
`<baseline-marketplace>/docs/config-levels.md` §§1–6 (six slots, `<config-root>` resolution, the
`never` veto's accumulate-and-report semantics) ·
`<baseline-marketplace>/requirements/OWNER-DECISIONS.md` §2 (agnosticism, recommendation strength).

**Facts taken as VERIFIED from a document that executed them here on 2026-09-19** (C8 research §§2–4,
which records the transcripts): the sandbox write/kill/docker/read tests under `bypassPermissions`;
the `Bash(rm:*)` deny defeated by `sh -c`; the `PreToolUse` deny hook holding under
`bypassPermissions`; `codex sandbox --` write/kill/docker tests; `docker ps -a` compose labels on this
machine; bash `set -m` plus `kill -- -PGID`; `setsid` absent; `man sandbox-exec` DEPRECATED;
`~/.claude/settings.json` `defaultMode: bypassPermissions` with nine guard hooks;
`~/.codex/config.toml:7` `sandbox_mode = "danger-full-access"`;
`harness-spawn.sh:32-39` and `harness-term.sh:16-110`.

**CLAIMED, not executed:** Gemini CLI `SEATBELT_PROFILE`; opencode permission verdicts; Codex
`execpolicy` and hook behaviour (the least-verified material in C8 and to be checked against `codex`
on the machine before anything depends on it); `@anthropic-ai/sandbox-runtime` behaviour;
OpenClaw's `post-compaction-context.ts` internals.

**INFERRED and flagged in place:** that `codex sandbox --` wrapping another agent CLI works (§4.4);
that spawn-time prompt injection inherits FIELD-NOTES §8's "a booted session keeps what it booted
with" property (§2.7); the ~835-line build estimate (§8).
