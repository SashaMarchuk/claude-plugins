# C3 — Work sources, readiness structure and mid-flight changes

Cluster items: **R1-04, Д2, Д8, Д9**. Research date **2026-09-19**.
Author: research agent. Owner's words are source of truth throughout.

Evidence labels used on every claim:

- **VERIFIED** — I read it in source/docs/schema, or measured it on this machine today. The command
  or file is named so it can be re-run.
- **CLAIMED** — a vendor doc, README or blog asserts it; I did not execute it.
- **INFERRED** — my reasoning from the above. Marked wherever it appears.

Where a figure was measured, the measurement is reproducible from
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/`
(`etag-test.sh`, `ghlist-cost2.sh`, `issue-etag.sh`, `claim-race.sh`, `poll.graphql`).

---

## 1. What the owner decided, quoted

### R1-04 — where work comes from

> «Конкретно поки тільки два режими.» [129]

> «локально, тобто в самому проєкту, якась структура, неважливо яка, але грубо кажучи, якась
> сканбан-дошка, або імітація сканбан-дошки, як саме це все відбувається, і в тому реєстрі будуть
> всі завдання.» [129]

> «Другий варіант - це через підключену якусь дошку. Наприклад, GitHub Issues, або, ClickUp, або
> будь-яка інша тула, і треба просто переконатися, що є доступ до цього ресурсу.» [129]

> «Першим ділом рекомендувати GitHub Issues, тому що для конкретно проекта і напевно в цьому
> перевага.» [129]

Note the hedge. `extract/corrections.md:56` records that «напевно» makes this **a hedged first
recommendation, not a decision**, and that ANALYSIS-01 states it flatly. I keep the hedge.
`extract/by-item.md:72` records the *reason*: the issues live with the project. That reason, not the
brand, is the criterion for judging any other board.

### R1-04 — what makes a task ready

> «структура, якимись або тегами, або що, які потрібно фоловити, наприклад, AI ready, чи ще щось, я
> не знаю, це треба буде, щоби придумав якусь структуру, і її притримувався» [145] / [146]

Two obligations, not one. `extract/outside-list.md:82` makes the second explicit: «і її
притримувався» — **adherence at runtime** is a requirement, separate from designing the structure.
This section of the document is the deliverable he handed forward with «щоби придумав».

### R1-04 — the board is a working surface

> «це має бути якась дошка, яка буде помічником для цього оркестратора, щоби ставити статуси таскам,
> залишати якісь коментарі, тощо, і так далі» [149]

«помічником» — a *helper*, not a queue to read from. Confirmed cleanly at [152] «Ну так, правильно».

### R1-04 — verifying a board on connect

> «треба перевіряти, чи дошка готова до цього, тому що в дошці мають бути якісь певні мінімальний
> набір статусів, які вона може використовувати. … Яка саме структура, це вже людина може
> перевизначити, переконфігурувати в середині плагіну» [153]

In English, the rest of the answer: the statuses can be adapted to a tool such as GSD or superpowers, or be a plain ready / in progress / done.

**Ratification status:** the restatement at [154]/[155] was never answered — the interviewer moved
straight to R1-05 at [156] and the owner said «Гаразд. Повтори питання» about the *next* item.
`extract/corrections.md:85` files this as **unratified**, against ANALYSIS-01 which files it as
SETTLED. Treat the board-status check as the owner's stated intent that still needs a yes.

### R1-04 — config lifecycle

> «… коли вона робить просто ран, то система починає щитувати чи є якісь налаштування глобальні, або на
> проєкті … Якщо чогось немає, то оркестратор задає ці питання для того, щоби їх покрити.» [133]

In English, the rest of the answer: the user configures at first run or with separate config commands without running; this is already the existing architecture of his Claude marketplace, so it is fine as a requirement.

Also **unratified** (`extract/corrections.md:84`): he asked for the *question* to be repeated at
[138], the interviewer repeated R1-04 instead, and this restatement was never re-put.
`extract/meta.md:65` draws out the meaning ANALYSIS-01 loses: **this is not new design work** — he
is pointing at architecture that already exists and saying reuse it.

### Д2 — work added mid-run

> «Він може абсолютно спокійно підібрати. … Точно не знаю, я думаю, що для цього має бути якийсь процес,
> я точно не знаю, але точно може бути таке, що під час цього я докину завдання, його опишу підходить
> для AI, і AI бере це завдання, і виконує» [422]

In English, the rest of the answer: a task tagged ready mid-run is picked up; possibly the agent checks the description is sufficient, implements it if so, and marks it "needs review" if not.

Two «я точно не знаю» in one answer. `extract/by-item.md` reads this correctly: the **mechanism is
open, the behaviour is certain** — pick it up and run it. Confirmed at [426], with the profanity
about repeated questions attached.

### Д8 — a task's description changes mid-flight

> «оркестратор бере це завдання і він може слідкувати за змінами в цьому завданні. … Тому, можливо, є
> сенс запускати слабшу модель, сабагента, який буде це перевіряти і дивитися за цим.» [466]

In English, the rest of the answer: the task may be a local file or a remote ticket; the checking model is configurable (no point spending an expensive model on it); the watcher returns nothing when nothing changed and reports what changed and how when something did.

**Scope of the confirmation matters here.** At [475] he said:

> «На те, що ти перше сказав, так, я підтверджую, потім після того ти повторив питання п'ять чи
> шість разів, і це не окей.» [475]

He confirmed **only the first restatement** ([469]). `extract/meta.md:108` flags that ANALYSIS-01
does not note this scoping. Two fragments of his own were also talked over and lost —
«Тобто, може бути момент» [468] and «з ... підстави чогось в моменті» [471]
(`extract/corrections.md:126,137`) — a Д8 qualifier about acting on a change *in the moment* that no
one ever recovered. **That fragment is an open item, not a settled one.**

### Д9 — the change contradicts finished work

> «Тобто, якщо вже завдання виконане, але воно змінене, то оркестратор задати перевагу тому, щоб зробити
> новий тікет, для того, щоб це. … людина також може налаштовувати цей кейс, як саме він буде хендлитись.» [482]

In English, the rest of the answer: during execution the orchestrator decides whether to change course, stop and restart with new instructions, or finish and file a new ticket; the configurable options are always-new-ticket, hard stop and redo from scratch, or automatic (orchestrator decides).

Confirmed «Так» at [486].

### Two constraints from outside this cluster that bind it

> «цей оркестратор, оцей от плагін, може використовуватись зовсім навіть не для написання коду … може
> таке бути, що десь не буде тестів, і це також окей» [344]

No assumption of a repo, tests, or a build. A readiness contract that requires "acceptance criteria
= tests" violates this.

> «Тому тут нічого надприроднього не потрібно вигадувати» [171]

One of at least four don't-over-engineer statements ([171], [189], [300], [370]). It applies here.

---

## 2. How the world does it

### 2.1 Readiness: what an "AI-ready" ticket contains

**The previous generation already shipped a readiness floor, and it held.** VERIFIED by reading
`plugins/harness/bin/harness-tickets.sh:27-37`: `require_ready_body` refuses `ready` unless the body
carries three headers — Outcome/Goal/Objective, Acceptance criteria (or Definition of Done/DoD), and
Scope. It is deliberately structural, and its own comment says so:

> «This is a STRUCTURAL check, not a judgment of quality — the /harness:add skill and the
> orchestrator still do the real grilling — but it makes "a ticket can't be ready without the
> checklist" an engine guarantee, not just prose.»

VERIFIED by auditing the **live 327-ticket queue** at
`<work>/<work-project>/.harness/tickets/` with the same three greps the engine uses:

| measurement | value |
|---|---|
| tickets in the queue | 327 |
| status histogram | 288 `done`, 17 `needs-review`, 15 `ready`, 7 `blocked`, 0 `in-progress` |
| `ready` tickets passing the floor | **15 of 15** |
| `ready` tickets failing the floor | **0** |
| headers present in all 15 | `## Outcome`, `## Scope`, `## Acceptance criteria` |
| ready-ticket body size (bytes) | min 2,880 · median 3,932 · mean 5,129 · max 20,144 |

That is the strongest single data point in this cluster: **a purely structural, grep-sized readiness
gate survived a real 327-ticket queue with 288 completed tickets and zero violations.** The owner's
«придумав якусь структуру, і її притримувався» is achievable without a model in the loop.

**GitHub Spec Kit** (VERIFIED: read `templates/spec-template.md` via the GitHub API; repo
`github/spec-kit`, MIT, 137,913 stars, last push 2026-09-18) requires, per spec:

- Prioritised user stories (P1/P2/P3), each with an **Independent Test** statement
- **Acceptance Scenarios** in Given/When/Then form
- Edge cases
- Functional requirements as numbered `FR-001: System MUST …`
- An explicit unresolved marker: `[NEEDS CLARIFICATION: …]`

The `[NEEDS CLARIFICATION]` marker is the same idea the owner reached for independently at [422]
(«він пише, що, типу, needs review»), and the previous harness already shipped as the
`needs-review` status — 17 live tickets sit in it today.

**EARS** (Easy Approach to Requirements Syntax) — CLAIMED by multiple 2026 write-ups, and used by
AWS Kiro and `hmbseaotter/agent-specification-toolkit`: requirements in the shape
`WHEN <trigger> THE SYSTEM SHALL <response>`, with variants for ubiquitous / state-driven /
optional / unwanted-behaviour clauses. Its value for an agent is that each clause is independently
checkable; its cost is that it reads badly for non-code work, which item [344] explicitly allows.

**Backlog.md** (VERIFIED: read a real task file from `MrLesk/Backlog.md`, MIT, 6,781 stars, last
push 2026-09-18) is the closest existing thing to the owner's local case — a markdown kanban
designed for humans and agents in a git repo. Its on-disk format:

```
---
id: BACK-200
title: Add Claude Code integration with workflow commands during init
status: To Do
assignee: []
created_date: '2025-07-23'
updated_date: '2025-09-06 21:22'
labels: [enhancement, developer-experience]
dependencies: [task-24.1, task-208]
priority: medium
---

## Description
...

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Claude Code template files are stored in src/templates/claude/
- [ ] #2 backlog init copies .claude directory to user's project
<!-- AC:END -->
```

Three things here are worth copying and one is worth *not* copying:

- **Worth copying:** `dependencies` as a first-class frontmatter list — the owner's R1-05 rule
  («якщо якісь завдання не може виконуватися, тому що не виконалось одне з попередніх, то його ми не
  можемо взяти» [160]) currently has no field to read.
- **Worth copying:** `updated_date` in frontmatter — a change watermark that does not depend on file
  mtime, which any `git checkout`, `rsync` or editor-save rewrites.
- **Worth copying:** the `<!-- AC:BEGIN -->/<!-- AC:END -->` fence with `#N` anchors. A machine can
  rewrite or tick one criterion without touching prose. This repo's own `interview-handoff` plugin
  already landed the same idea ("item-id anchoring", commit `1d46bf0`).
- **Worth NOT copying:** in that real file, `id: BACK-200` but `dependencies: [task-24.1, task-208]`
  — the dependency list uses a *different* id prefix from the id field. VERIFIED by reading the
  file. Id-scheme drift silently breaks dependency resolution. Pick one id shape and validate it.

**GitHub Copilot coding agent** — CLAIMED (GitHub docs and the GitHub Blog): the trigger convention
is **assigning the issue to the agent**, and GitHub's own guidance is to *treat the issue as the
prompt* — clear problem statement, complete acceptance criteria, and directions about which files
change. Repo-level agent instructions live in `AGENTS.md` at the repo root, nestable per
subdirectory. This is the de-facto industry readiness convention as of 2026: **assignee = claim,
body = spec, `AGENTS.md` = process.**

### 2.2 Polling a tracker cheaply

**GitHub conditional requests cost nothing.** VERIFIED by measurement today
(`scratchpad/etag-test.sh`, against `SashaMarchuk/claude-plugins`):

```
== fetch a fresh ETag ==
200 used=1 remaining=4999 etag="2357f5f0…"
== 5 CONDITIONAL (If-None-Match) ==
304 used=1 remaining=4999      <- five times, counter never moves
== 5 UNCONDITIONAL ==
200 used=2 … 200 used=6        <- +1 each
```

Five `304`s consumed **zero** of the 5,000/hour core budget; five plain `200`s consumed five. The
304 also returned an empty body against 31,907 bytes for the `200`.

Two traps found while measuring, both VERIFIED:

1. **The ETag is bound to the exact representation.** Dropping `Accept: application/vnd.github+json`
   turned the same conditional request back into a `200`. Cache the `Accept` header alongside the
   ETag or the conditional silently stops working and you pay full price without noticing.
2. **`GET /rate_limit` returned stale zeros** repeatedly during testing while the endpoint's own
   `x-ratelimit-used` header was accurate. Read budget from the response headers of the call you
   actually made, not from `/rate_limit`.

**The rate budget is not one budget.** VERIFIED from live headers:

| resource | limit | window |
|---|---|---|
| `core` (REST incl. `/issues?labels=`) | 5,000 | per hour |
| `graphql` | 5,000 points | per hour |
| `search` | **30** | **per minute** |
| `code_search` | 10 | per minute |

VERIFIED by measurement (`scratchpad/ghlist-cost2.sh`): `gh issue list --repo … --state all`
consumed **1 core request**; `gh issue list --search "state:open"` consumed **0 core** and instead
hit the **search** resource — a direct `GET /search/issues` call returned
`x-ratelimit-limit: 30, x-ratelimit-resource: search`. **A poller that phrases its readiness query as
a search gets 30/minute; the same query as a label filter gets 5,000/hour.** That is a 160× budget
difference decided by which flag you type.

**One GraphQL query can carry the whole poll for 2 points.** VERIFIED
(`scratchpad/poll.graphql`, live against `cli/cli`): a single query returning 50 open
label-filtered issues with `number, title, updatedAt, lastEditedAt, issueType, labels, assignees,
blockedBy, subIssuesSummary` reported `rateLimit.cost: 2` of 5,000/hour. The same query shape
returning 100 issues with `number` + `lastEditedAt` only reported `cost: 1`.

At a 60-second tick that is 120 points/hour — **2.4% of the GraphQL budget** — for a complete view
of readiness, dependencies and body-change state across the board.

**ClickUp has no conditional requests.** VERIFIED live against the owner's own workspace
(`<workspace-id>`): the response to `GET /api/v2/list/{id}/task` carried

```
cache-control: no-cache, no-store
x-ratelimit-limit: 100
x-ratelimit-remaining: 99
x-ratelimit-reset: 1789824033
```

**No `etag`, no `last-modified`.** Payload was 19,580 bytes for 4 tasks. ClickUp's rate-limit doc
(CLAIMED, `developer.clickup.com/docs/rate-limits`) gives 100 req/min per token on
FreeForever/Unlimited/Business, 1,000 on Business Plus, 10,000 on Enterprise — **per token, per
minute**, with `X-RateLimit-*` headers and HTTP 429 on exhaustion. The live headers match the 100
figure.

ClickUp's substitute for a conditional request is a **watermark**. VERIFIED live:
`GET /api/v2/team/{team_id}/task?date_updated_gt=<unix_ms>` returned 100 tasks with
`last_page: false`, each carrying `date_updated`. `statuses[]=to%20do` also works as a filter.

### 2.3 Detecting a changed *description* specifically

This is the sharpest finding in the cluster, and it contradicts the obvious implementation.

**`updated_at` is not a body-change signal — a comment moves it.** VERIFIED read-only against
`cli/cli`: for three open issues, `issue.updated_at` was **exactly equal** to the last comment's
`created_at` (#14477 `2026-09-19T10:06:09Z`, #12459 `2026-09-19T09:17:31Z`, #9228
`2026-09-18T22:14:01Z`). A whole-issue ETag has the same problem, because the issue payload embeds
`updated_at` and the comment count.

That collides head-on with the owner's own design. He wants the board to be a working surface —
«ставити статуси таскам, залишати якісь коментарі» [149] — **and** a silent change-watcher —
«якщо нічого не змінилось, то цей агент просто, типу, нічого назад не поверне» [466]. Built the
obvious way, **the orchestrator's own status comment fires its own change detector on every tick**,
and the "silent when unchanged" requirement is unreachable.

**GitHub has a field that solves it exactly.** VERIFIED against the live GraphQL schema today
(`__type(name:"Issue")`): `lastEditedAt` exists and is distinct from `updatedAt`. Observed on
`cli/cli#14188`: `lastEditedAt = 2026-08-18T08:41:20Z` while `updatedAt = 2026-08-28T14:29:49Z` —
**ten days apart**. It is `null` when the body was never edited. Comments and labels do not move it.

**GitHub also hands you the previous text for free.** VERIFIED: `userContentEdits` returns
`editedAt`, `editor.login` and `diff` per revision. Despite the field name, `diff` contains the
**full body at that revision**, not a unified diff — so the prior version is retrievable without
storing it yourself, and the actual diff can be computed locally. 7 of 40 scanned open issues had
edit history. (Caveat, INFERRED: `diff` may be `null` for redacted or permission-restricted edits;
handle null.)

**ClickUp solves it through webhooks, not polling.** CLAIMED (`developer.clickup.com/docs/webhooks`
and `…/webhooktaskpayloads`): 13 task events, including `taskUpdated` and a **separate**
`taskCommentPosted` / `taskCommentUpdated`. A description change appears in `taskUpdated` as a
`history_items` entry with `"field": "content"` plus `before` and `after`. So on ClickUp the
platform will tell you *which field changed and what it was* — no model, no diffing — **if** you can
receive a webhook. Section 4 explains why you usually cannot.

There is no ClickUp equivalent of `lastEditedAt` in the polled task payload. VERIFIED by listing the
task object's keys live: `date_created`, `date_updated`, `date_closed`, `date_done` — no
`date_description_updated`. Whether a ClickUp comment moves `date_updated` is **UNVERIFIED**: I
scanned 100 tasks in the owner's workspace and found none carrying comments, so the test did not
run. Treat it as unknown and assume the worst until measured.

### 2.4 Duplicate claims and idempotent claiming

**The previous generation has no atomic claim, and its source says so.** VERIFIED,
`harness-tickets.sh:98-105`:

```bash
gh_claim() {
  local id="${1:?}"
  # read-verify-then-write; no CAS exists in gh — acceptable for single-operator queues
  gh issue view "$id" … | grep -q "\"$PREFIX:ready\"" || { … return 65; }
  gh issue edit "$id" … --remove-label "$PREFIX:ready" --add-label "$PREFIX:in-progress" …
}
```

`l_claim` (line 144) has the identical read-check-write shape with no lock at all.

**That shape produces N winners, measured.** VERIFIED today on this machine's APFS volume
(`scratchpad/claim-race.sh`), 2/10/50 concurrent workers, each primitive racing for one claim:

| primitive | 2 workers | 10 workers | 50 workers |
|---|---|---|---|
| `mkdir` | **1 winner** | **1 winner** | **1 winner** |
| `ln` (hard link) | **1 winner** | **1 winner** | **1 winner** |
| `set -o noclobber; : > f` | **1 winner** | **1 winner** | **1 winner** |
| `test -e` then write (the current shape) | **2 winners** | **10 winners** | **27 winners** |

**GitHub has an atomic primitive too, and it is not labels.** VERIFIED live: creating a ref that
already exists returns `HTTP 422 {"message":"Reference already exists"}` —

```
POST /repos/SashaMarchuk/claude-plugins/git/refs  {"ref":"refs/heads/main","sha":"fd6125e…"}
HTTP 422  "Reference already exists"
```

Ref creation is compare-and-swap at the storage layer. `201` = you hold the claim, `422` = someone
else does. Labels and assignees have no such guarantee.

**The historical precedent on this exact queue.** VERIFIED from
`<work>/<work-project>/docs/open/HARNESS-TICKET-ID-ALLOCATION.md`: the *same*
read-then-write shape in `l_add` produced, on a 272-ticket scratch queue, **two files under one id
in 5 rounds of 5**, and a twenty-way add produced **20 files under 3 ids** — with **zero non-zero
exits**; both callers were told `OK created ticket 273`. After a `mkdir` lock plus an
id-already-taken refusal, 2-, 20- and 50-way concurrent adds shared an id in **0 of 15 rounds**.
The doc also measured the honest limit: with lock-stealing forced on, the refusal layer alone still
let a duplicate through in 7 of 8 rounds — *"The lock is what makes the allocation correct; the
refusal is what makes a bypass loud instead of silent."*

**That fix is not in the code you would ship.** VERIFIED by md5 across all 11 copies on this machine:

| md5 | copies | has the lock? |
|---|---|---|
| `1c52e8e73505e358f57fc783ad2b1056` | 1 — `~/.claude/plugins/cache/sashamarchuk-plugins/harness/0.6.0/bin/harness-tickets.sh` | **yes** |
| `915c2cd4047c60bf70ca80ad87f91fce` | 9 — incl. **`~/Work/claude-plugins/plugins/harness/bin/harness-tickets.sh`** | no |
| `fcd3561cc71587e561b04f3de27e4a6b` | 1 (older profile-switcher snapshot) | no |

`915c2cd4…` is byte-for-byte the pre-change md5 the fix doc names. One `/plugin update` overwrites
the only good copy. FIELD-NOTES §12.6 predicted exactly this: *"The fix landed only in the installed
plugin copy and not in the source repository, so it reverts on the next sync."* **It has not been
backported.** And `l_claim` was never fixed in any copy.

**Why it has not bitten in production:** VERIFIED from `templates/prompts/orchestrator.md:91` —
only the orchestrator claims (`harness-tickets.sh claim <id>`); workers never do. Duplicate claiming
is prevented today by the **single-claimer convention**, which rests on the owner's own
single-orchestrator invariant: «якщо раптом одночасно два якісь оркестратори працюють, то це не
окей. Це треба відслідковувати і не дозволяти» [300–302]. The convention is load-bearing and
undefended.

**Lease expiry already exists.** VERIFIED, `harness-tickets.sh:183-202`: `stale_report [days=7]`
lists every `in-progress` ticket and releases those idle beyond the cutoff **and** still passing the
readiness floor; the rest print `STUCK … needs a human`. Idleness comes from GitHub `updatedAt`
(`gh_list_v`) or file mtime (`l_list_v`). Two defects, VERIFIED by reading: (a) `gh_comment` uses
`--edit-last --create-if-none`, and any comment bumps `updatedAt`, so **a session that only comments
looks alive forever** — the same `updated_at` confusion as §2.3; (b) FIELD-NOTES line 697 records
that `harness-tickets.sh done` leaves a previously blocked issue holding **two** state labels,
because `blocked` is never removed — seen twice.

### 2.5 Mid-run intake, at real scale

VERIFIED, FIELD-NOTES §10.1: in the previous run the queue grew **236 → 327 tickets in one day**,
and the owner's own response was to set a **soft pause** (`state/SOFT-PAUSE.md`). VERIFIED,
FIELD-NOTES §10.2 `J-SUP-34`: the orchestrator once sat idle 35+ minutes with **eight ready tickets
and no lanes** because the watcher logged it "held" rather than "parked".

Both bear directly on Д2. Unbounded intake is not hypothetical here; it happened, and a human had to
stop it.

---

## 3. What is feasible, per platform

Legend: ✅ native · ⚙️ possible with work · ❌ not available.

| capability | local files | GitHub Issues | ClickUp |
|---|---|---|---|
| Readiness marker | ✅ frontmatter key / body headers (**V**) | ✅ label, assignee, `issueType` (**V**) | ✅ status, tag, custom field (**V**) |
| Status model the process can map onto | ⚙️ free text, you define it | ✅ labels — arbitrary names | ✅ statuses carry a **`type`**: `open`/`unstarted`/`custom`/`done`/`closed` (**V**) |
| Dependency edges | ⚙️ must add a field | ✅ `blockedBy`/`blocking`, `parent`, `subIssues`, `subIssuesSummary`; mutations `addBlockedBy`/`removeBlockedBy`/`addSubIssue` (**V**, live schema) | ✅ `dependencies` field present on the task object (**V**) |
| Free "nothing changed" poll | ✅ mtime / content hash, zero cost | ✅ `If-None-Match` → 304, **0 quota** (**V**) | ❌ no ETag; `cache-control: no-cache, no-store` (**V**) |
| Body-change signal isolated from comments | ✅ hash the body region | ✅ `lastEditedAt` (**V**) | ❌ polled; ✅ via webhook `history_items.field == "content"` (**C**) |
| Previous body text without storing it | ❌ | ✅ `userContentEdits[].diff` = full prior body (**V**) | ❌ |
| Atomic claim (compare-and-swap) | ✅ `mkdir` / `ln` / `noclobber` — 1 winner at 50-way (**V**) | ✅ `POST /git/refs` → 422 if taken (**V**); ❌ on labels/assignees | ❌ none found |
| Orchestrator writes status + comments | ✅ file write / append | ✅ labels + `gh issue comment` (**V**, in use) | ✅ `comment` + `task update` via `clickup-cli` (**V**, installed 0.13.0) |
| Watermark / incremental listing | ✅ mtime, or an `updated` field | ✅ `since=`, `sort=updated`, or GraphQL `orderBy` (**V**) | ✅ `date_updated_gt=<unix_ms>` (**V**) |
| Full-board poll cost | free | **2 points** / 5,000 per hour (**V**) | **1 req** / 100 per minute (**V**) |
| Mid-run additions visible | ✅ next directory scan | ✅ next poll | ✅ next poll |
| Push notification | ❌ | ⚙️ webhook — needs ingress | ⚙️ webhook — needs ingress |

Verified on this machine: `gh` 2.92.0 authenticated as `SashaMarchuk` with scopes
`gist, project, read:org, repo, write:packages`; `clickup-cli` 0.13.0 at `/usr/local/bin/clickup-cli`
authenticated against workspace `<workspace-id>`; **`flock(1)` is absent** — not on `PATH`, not in
`/usr/bin` or `/opt/homebrew/bin` — which independently confirms the `mkdir`-lock choice made in the
ticket-169 fix.

A live ClickUp list's statuses, VERIFIED (`[AUT] Developmental Tasks`):

```
backlog      type=open        to do        type=unstarted
ongoing      type=custom      in progress  type=custom
on hold      type=custom      blocked      type=custom
review       type=done        Closed       type=closed
```

Note `review` is typed `done`. Status **names carry no semantics**; only `type` does, and even `type`
is set by whoever built the list.

---

## 4. What is NOT feasible, and why

**Webhooks, for this product.** Both platforms support them; neither can reach a laptop. An
unattended overnight run on the owner's machine has no public ingress, and adding a tunnel means a
hosted relay, a stable URL, a secret to rotate and a component that is down when the laptop sleeps —
against «нічого надприроднього не потрібно вигадувати» [171]. **Polling is the only universally
feasible mechanism**, and every proposal below assumes it. This is also the largest single
capability the ClickUp backend loses, because ClickUp's *only* precise description-change signal is
the webhook `history_items.field == "content"`.

**Cheap change detection on ClickUp.** VERIFIED: no ETag, `cache-control: no-cache, no-store`, no
`lastEditedAt`-equivalent in the payload, 19,580 bytes for 4 tasks. Watching N active ClickUp tasks
costs N full task fetches per tick against a **100 req/min** budget. There is no free "nothing
changed" answer. This is a genuine platform divergence, and it is exactly the kind the owner
instructed the collector to raise as its own question rather than assume away (I1, [182–184]).

**A search-phrased readiness query at any useful tick rate.** VERIFIED: the `search` resource is
**30 requests per minute**. A 60-second tick is survivable; anything finer, or several repos, is not.
Phrase readiness as a label/state filter (core, 5,000/hr) or GraphQL (5,000 points/hr), never as a
search.

**Compare-and-swap on a GitHub label or assignee.** VERIFIED absent; the shipped code documents the
gap itself. Any claim built on "read the label, then write the label" is a race — measured at 27
winners out of 50 for the equivalent local shape. A claim needs `POST /git/refs` (or the
single-claimer invariant, stated and defended).

**`updated_at` / whole-issue ETag as a description-change detector.** VERIFIED false on GitHub: a
comment alone sets `updated_at` to the comment's `created_at`. Since the owner requires the
orchestrator to comment on the board [149], this detector would fire on the orchestrator's own
writes and could never be silent. Unknown but assume-broken on ClickUp.

**File mtime as a durable local change watermark.** INFERRED, but firmly: `git checkout`, `git
stash`, `rsync`, a branch switch and most editors rewrite mtime without changing content, and the
previous generation already ran tickets inside per-task git worktrees (Д4, [433]). FIELD-NOTES also
records `QUESTIONS.md` and `JOURNAL.md` **forking into a worktree's own copy**, leaving a real
owner-facing question invisible for an hour. mtime is a cheap *hint*; a content hash is the answer.

**"Acceptance criteria" meaning "tests".** Ruled out by the owner at [344]. Any readiness contract
that hard-requires a test command fails on the non-code projects he explicitly reserved.

---

## 5. Concrete proposals

### 5.1 The readiness contract

One contract, three storage backends. Every field has exactly one writer. **Nothing here is
platform-specific**; §5.2 is the mapping.

**States — five, and they are roles, not names.**

| role | meaning | who writes it |
|---|---|---|
| `backlog` | exists, not offered to the orchestrator | human |
| `ready` | may be claimed **now** | human, or orchestrator on a passing sufficiency check |
| `active` | claimed, being worked | **orchestrator only** |
| `needs-input` | stopped, waiting on a human | orchestrator |
| `done` | finished | orchestrator |

`needs-input` is one state covering both of the owner's cases — Д2's «needs review» for a thin
description [422] and R1-14's hard stop. Add a `reason` field rather than a sixth state.

**Fields.**

| field | required | writer | purpose |
|---|---|---|---|
| `id` | yes | board | stable cross-reference; **never reused** |
| `title` | yes | human | — |
| `state` | yes | per table above | the state machine |
| `ready_marker` | yes | human | the thing that means "AI may take this" — label, tag, status, or field |
| `body` | yes | human | the spec; must carry the three sections below |
| `dependencies` | no | human | ids that must be `done` first (R1-05 [160]) |
| `claim` | no | **orchestrator only** | `{holder, run_id, taken_at, heartbeat_at}` |
| `body_digest` | no | **orchestrator only** | sha256 of the normalised body at claim time (Д8) |
| `source_watermark` | no | **orchestrator only** | `lastEditedAt` / `date_updated` / file hash at claim time |
| `origin` | no | orchestrator | for a ticket it opened itself under Д9 — `{supersedes: <id>}` |

**Body — three required sections, and one optional one.** Keep the previous generation's three
verbatim, because they are already proven on 327 tickets and already in the owner's muscle memory:

- `## Outcome` — what is true when this is finished. Prose. No format imposed.
- `## Scope` — what this ticket may touch, and what it must not.
- `## Acceptance criteria` — a checklist. Each item gets a stable anchor, Backlog.md style:

```markdown
## Acceptance criteria
<!-- AC:BEGIN -->
- [ ] #1 <one checkable statement>
- [ ] #2 <one checkable statement>
<!-- AC:END -->
```

- `## Open questions` — optional; **any `[NEEDS CLARIFICATION: …]` marker anywhere in the body
  forces `needs-input` and blocks `ready`.** Borrowed from spec-kit; it gives the human and the
  orchestrator one shared way to say "not yet".

Deliberately **not** required: EARS, Gherkin, a test command, a repo, a branch. Each criterion is a
sentence a human can check. EARS or Given/When/Then remain available to anyone who wants them — the
contract does not care — which is what keeps [344] satisfied.

**The gate, in two layers**, exactly the split that already works:

1. **Structural floor — deterministic, no model.** `state` may become `ready` only if the body
   carries `## Outcome`, `## Scope`, `## Acceptance criteria`, at least one `- [ ]` item inside the
   AC fence, no `[NEEDS CLARIFICATION]` marker, and every `dependencies` id resolves. Runs in
   milliseconds, costs nothing, and — measured — held across 327 tickets.
2. **Sufficiency judgement — a model, only above the floor.** This is the owner's Д2 «агент
   аналізує, і якщо достатньо опису, то він його бере» [422]. It runs *after* the floor passes, and
   its only outcomes are "claim it" or "`needs-input` with a named gap".

The floor is what «її притримувався» [146] means operationally: it is checked on every transition,
not once at creation. **Re-check the floor before release too** — the shipped `gh_release`/`l_release`
already do this (`harness-tickets.sh:152,161`), and it is the right instinct.

### 5.2 Mapping the contract to each backend

| contract field | local file | GitHub Issues | ClickUp |
|---|---|---|---|
| `id` | leading number in `<id>-<slug>.md` | issue number | task id (or `custom_id`) |
| `state` | `state:` frontmatter | label `<prefix>:<state>` | status, mapped by **`type`** not name |
| `ready_marker` | `state: ready` | label `<prefix>:ready` | tag or status of `type=unstarted` |
| `body` | after frontmatter | issue body | `description` |
| `dependencies` | `dependencies:` list | `blockedBy` (native) | `dependencies` (native) |
| `claim` | `claim/<id>.d` dir via `mkdir` | ref `refs/heads/claim/<id>` | assignee + a `claim` custom field |
| `body_digest` | `body_digest:` frontmatter | orchestrator state file | orchestrator state file |
| `source_watermark` | body sha256 | `lastEditedAt` | `date_updated` |
| comments | append below a `---` rule | `gh issue comment` | `clickup-cli comment` |

**On the board-readiness check [153]** — check by **role, not by name**. Ask the configured process
which of the five roles it needs, then require a mapping for each. On ClickUp the status `type`
(`open`/`unstarted`/`custom`/`done`/`closed`) is the natural anchor and it is already in the API
(VERIFIED), but the live example above shows `review` typed `done` — so **present the proposed
mapping to the user and have them confirm it**, rather than deriving it silently. That keeps the
owner's «ці статуси можна конфігурувати також власноруч … людина може перевизначити» [153] as the
authority and makes the check a conversation, not a rejection.

**On `body_digest` and `source_watermark` living outside the ticket on remote boards:** writing them
into the issue body would itself edit the body and move `lastEditedAt` — the detector would trigger
itself. Keep them in the run's own state, never on the board.

### 5.3 Change detection — three tiers, model last

This preserves the owner's decision («має бути налаштування, якою моделькою перевіряти» [466],
«слабшу модель, сабагента» [466]) and makes the tier he actually cares about — the silent one —
cost nothing.

**Tier 0 — did anything change at all?** Free or near-free.
GitHub: one conditional request per active ticket (`If-None-Match`, remember the `Accept` header) —
**304, zero quota**; or fold all active tickets into the single 2-point GraphQL poll.
Local: stat + read + sha256 of the body region.
ClickUp: one `date_updated_gt` sweep for the whole board, 1 request of 100/min.
→ nothing changed: **silent, no model, no tokens.** This is «нічого назад не поверне» [466],
achieved deterministically.

**Tier 1 — did the *description* change, as opposed to a comment or a label?** Still no model.
GitHub: compare `lastEditedAt` against `source_watermark`. Local: compare the body sha256.
ClickUp: fetch the task, hash `description`, compare.
→ only a comment or label moved: silent.

**Tier 2 — what changed, and does it matter?** Now, and only now, a model.
Compute the textual diff locally first — on GitHub the previous body comes free from
`userContentEdits[].diff`, so the model never has to reconstruct it. Hand the model the **diff**,
not the two full bodies, and ask one question: does this change the Outcome, the Scope, or any
acceptance criterion — and which anchors (`#1`, `#2`…)?
→ this is where the owner's configurable cheap model belongs, and where «звітувати про те, що
змінилось, як змінилось» [466] is produced.

**What that saves.** Ready-ticket bodies measured on the live queue: median 3,932 bytes, mean 5,129,
max 20,144. At ~4 bytes/token (**INFERRED** — exact figures need `messages.count_tokens`; no
Anthropic credential is present on this machine, so I could not measure) a median body is ~1,000
input tokens. Pricing from the bundled `claude-api` reference (cached 2026-06-24): Haiku 4.5
$1.00/MTok in, Sonnet 5 $2.00, Opus 5 $5.00, Fable 5.1 $10.00.

| watcher design | per check | 1 ticket, 8h @ 60s tick | 3 lanes |
|---|---|---|---|
| Fable 5.1 reads the body every tick | ~$0.010 | ~$4.72 | ~$14.16 |
| Haiku 4.5 reads the body every tick | ~$0.001 | ~$0.47 | ~$1.42 |
| **Tiers 0–1 deterministic, model only on a real change** | **$0** | **~$0.00** | **~$0.01** |

(INFERRED, from the measured byte sizes and the quoted prices.) The owner's instinct — «немає сенсу
перевіряти фейбл моделю» [466] — is right by a factor of ten. The tiering makes it a factor of
several hundred, because the common case stops calling a model at all. **His decision stands: the
watcher model is configurable. Tiers 0–1 only decide when it is worth waking.**

### 5.4 Claiming

**Default — the single-claimer rule, stated and enforced.** Only the orchestrator moves a ticket to
`active`; executors never claim. This is what the previous generation already relies on
(`orchestrator.md:91`) and it follows directly from the owner's single-orchestrator invariant [300].
Make it an explicit invariant with a check, not an undocumented convention.

**Belt and braces — an atomic claim that costs almost nothing.** Because the single-claimer rule is
one crashed-and-restarted orchestrator away from being violated (Д10, [497]):

- local: `mkdir .claims/<id>.d` — **1 winner at 50-way, measured**
- GitHub: `POST /git/refs {"ref":"refs/heads/claim/<id>"}` — **422 if taken, measured**
- ClickUp: no CAS exists; fall back to assignee + re-read, and **say so in the config output** rather
  than implying a guarantee that is not there

Write `{holder, run_id, taken_at, heartbeat_at}` into the claim and refresh `heartbeat_at` on a tick.

**Release.** Keep `stale_report`'s shape — release only if idle beyond the threshold **and** the
readiness floor still passes; otherwise print `STUCK … needs a human`. Two fixes it needs, both
VERIFIED as present defects: drive idleness from **`heartbeat_at` in the claim**, never from
`updatedAt` (which the orchestrator's own comments bump), and **remove the previous state label** on
transition so a ticket cannot hold `blocked` and `done` at once.

**Id allocation.** Backport the ticket-169 `mkdir` lock plus the id-already-taken refusal into
`~/Work/claude-plugins`, or reimplement it in the new orchestrator. Today the source repo carries the
defective allocator (md5 `915c2cd4…`) and one `/plugin update` destroys the only fixed copy. Keep the
doc's own rule as contract: **nobody writes an id they have not read back from the tool's output** —
there is no reservation verb, on purpose.

### 5.5 Mid-run intake (Д2), with the brake the evidence asks for

The behaviour he confirmed is not in question: added work is picked up if ready. What the answer does
not cover is **volume** — and the previous run's queue grew 236 → 327 in a day and the owner stopped
it by hand.

Proposal, as a setting with a default, in his own soft/hard vocabulary:

- `intake: open` — pick up anything that becomes `ready`, no ceiling.
- `intake: capped` *(suggested default)* — pick up new work until N tickets have been started this
  run, then hold further arrivals in `ready` and report the backlog in `orchestrator:status`.
- `intake: frozen` — work only the set that was ready at start.

And, regardless of mode, **surface the growth**: if the ready count rises while the run is working,
that belongs in the status pull he described at [508], because it is the signal that made him
intervene last time.

This does not overwrite his decision — «Він може абсолютно спокійно підібрати» stays the default
behaviour. It names the case his answer does not reach.

### 5.6 Д9 — the contradiction case

His rule is already precise: for finished work, **prefer a new ticket**; mid-execution, the
orchestrator chooses among adapt / stop-and-restart / finish-then-new-ticket; and the whole case is
configurable including an explicit automatic mode [482]. Two mechanical pieces make it executable:

1. **Link the tickets.** A ticket opened under Д9 carries `origin: {supersedes: <id>}`, and on GitHub
   should use the native `blockedBy`/`subIssues` edges (VERIFIED present) rather than a prose "see
   also". Otherwise the record of *why* a second ticket exists survives only in comments.
2. **Decide on anchors, not on prose.** Tier 2 already reports which acceptance-criterion anchors the
   edit touched. A change that touches only unticked criteria is an in-flight adaptation; a change
   that touches a **ticked** criterion is the contradiction case and takes the configured branch.
   This gives the orchestrator's «вирішує» something concrete to decide on.

---

## 6. Open questions for the owner

1. **Two restatements in this cluster were never answered.** The board-status check ([154]/[155] →
   [156]) and the config lifecycle ([134]/[137] → [138]) are recorded as SETTLED in ANALYSIS-01 but
   were never confirmed aloud. Should round 2 re-put them, or do you want them taken as settled?

2. **The board-as-working-surface collides with the silent watcher.** You want the orchestrator to
   comment on tickets [149] and you want the change-watcher silent when nothing changed [466]. A
   comment moves `updated_at` (measured). §5.3 solves it with `lastEditedAt` / body hashing — but is
   commenting on the ticket itself what you want, or would a separate run log do, leaving the ticket
   untouched except for status?

3. **A Д8 qualifier of yours was lost.** At [468] and [471] you said «Тобто, може бути момент» and
   «з ... підстави чогось в моменті» while the interviewer talked over you, and it was never
   recovered. It reads like a condition on when a mid-flight change may be acted on. What was it?

4. **Readiness structure — confirm or replace.** §5.1 proposes `## Outcome` / `## Scope` /
   `## Acceptance criteria` with anchored checklist items, plus `[NEEDS CLARIFICATION]` as the
   blocker. The three headers are the previous generation's, and they held on 327 tickets with zero
   violations. Is that the structure you want «придумав», or do you want something else invented?

5. **Who may set `ready`?** Your Д2 answer implies the orchestrator may promote a ticket it judges
   sufficiently described [422]. Should it be allowed to write `ready` on a human's ticket, or only
   ever move it to `needs-input` and leave promotion to you?

6. **ClickUp's divergence, per your instruction I1 [182–184].** ClickUp has no conditional requests,
   no description-change field, 100 req/min, and its only precise description-change signal is a
   webhook a laptop cannot receive. Watching an active ClickUp ticket therefore costs a full task
   fetch per tick, forever. Accept the cost, poll ClickUp more slowly than GitHub, or state that
   ClickUp is supported for reading and status writes but not for mid-flight change watching?

7. **Claim strength.** Is the single-orchestrator invariant enough on its own, or do you want the
   atomic claim (`mkdir` locally, `refs/heads/claim/<id>` on GitHub) as a second layer? It is cheap,
   but it adds a claim artefact to your repo's refs.

8. **Intake ceiling.** Your queue once grew 236 → 327 in a day and you soft-paused it yourself. Do
   you want `intake: capped` as the default (§5.5), or is unlimited pickup genuinely what you want
   with the growth merely reported?

9. **The backport.** `~/Work/claude-plugins/plugins/harness/bin/harness-tickets.sh` still carries the
   defective id allocator (md5 `915c2cd4…`); the fix exists only in the installed cache copy and one
   `/plugin update` destroys it. Fix it in the old plugin now, or let it die with the rebuild?

---

## Sources

Primary, read or measured directly:

- `plugins/harness/bin/harness-tickets.sh` (source repo, v0.6.0) and
  `~/.claude/plugins/cache/sashamarchuk-plugins/harness/0.6.0/bin/harness-tickets.sh` (installed)
- `plugins/harness/docs/FIELD-NOTES.md`; `plugins/harness/templates/prompts/orchestrator.md`
- `<work>/<work-project>/docs/open/HARNESS-TICKET-ID-ALLOCATION.md`
- `<work>/<work-project>/.harness/tickets/` — 327 live tickets
- GitHub REST + GraphQL, live (`api.github.com`), 2026-09-19 — headers, schema introspection,
  `rateLimit.cost`, `POST /git/refs`
- ClickUp API v2, live (`api.clickup.com`), workspace `<workspace-id>` — headers, list statuses,
  `date_updated_gt`, task object keys
- `github/spec-kit` `templates/spec-template.md`; `MrLesk/Backlog.md` `backlog/tasks/back-200 …md`
- local concurrency measurements on APFS; `gh` 2.92.0, `clickup-cli` 0.13.0, `flock` absent
- bundled `claude-api` skill — model IDs and pricing (cached 2026-06-24)

Vendor documentation (CLAIMED, not executed):

- [ClickUp rate limits](https://developer.clickup.com/docs/rate-limits)
- [ClickUp webhooks](https://developer.clickup.com/docs/webhooks) ·
  [task webhook payloads](https://developer.clickup.com/docs/webhooktaskpayloads)
- [GitHub Copilot: assigning issues to coding agent](https://github.blog/ai-and-ml/github-copilot/assigning-and-completing-issues-with-coding-agent-in-github-copilot/)
- [GitHub docs: assign Copilot to an issue](https://github.com/github/docs/blob/main/content/copilot/how-tos/use-copilot-agents/coding-agent/assign-copilot-to-an-issue.md)
- [GitHub changelog: dependencies on issues](https://github.blog/changelog/2025-08-21-dependencies-on-issues/)
- [GitHub GraphQL issues reference](https://docs.github.com/en/graphql/reference/issues)
- [github/spec-kit](https://github.com/github/spec-kit) · [Backlog.md](https://github.com/MrLesk/Backlog.md)
- [agent-specification-toolkit (EARS/SHALL)](https://github.com/hmbseaotter/agent-specification-toolkit)
