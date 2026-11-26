# C3 — Adversarial challenge: work sources, readiness structure, mid-flight changes

Date: **2026-09-19**. Adversary pass over cluster C3 (**R1-04**, **Д2**, **Д8**, **Д9**).
Companion to `C3-work-source-research.md`, which holds the options; this file holds only the holes.

**What this file does and does not do.** Every attack below names a concrete failing scenario in the
owner's own environment. None of them proposes a replacement for a decision he made. Where a decision
collides with another decision, or with the previous run's record, both sides are quoted with their
`[row]` anchor. Where I could not establish something, it is marked INFERRED.

**Labels.** VERIFIED = I read it in source on this machine today, or measured it here. CLAIMED = a
doc or README asserts it and I did not execute it. INFERRED = my reasoning from verified parts.

---

## Standing note: two of the four decisions in this cluster were never ratified

`extract/corrections.md:84,85` records both. The **board-status check** was restated at [154]/[155]
and the interviewer moved straight to Р1-05 at [156] with nothing from the owner in between. The
**config lifecycle** was restated at [134]/[137], the owner answered «А повтори, будь ласка, попереднє
питання» [138], the interviewer repeated Р1-04 instead, and the restatement was never re-put.
ANALYSIS-01 files both as SETTLED.

Д8's confirmation is also narrower than it reads. At [475] he said:

> «На те, що ти перше сказав, так, я підтверджую, потім після того ти повторив питання п'ять чи шість
> разів, і це не окей.» [475]

That confirms the **first** restatement ([469]) only. And two of his own fragments were talked over and
lost — «Тобто, може бути момент» [468] and «з ... підстави чогось в моменті» [471]
(`extract/corrections.md:126,137`) — a qualifier about acting on a change *in the moment* that nobody
recovered.

The attacks below treat all of it as binding anyway. That is the adversary's job. But A4, A7 and A8
are levelled at text the owner never said «підтверджую» to.

---

## A1 — The board is a working surface **and** the thing being watched, so the orchestrator's own writes fire its own change detector · **blocker**

**Collides:** [149] × [466].

> «це має бути якась дошка, яка буде помічником для цього оркестратора, щоби ставити статуси таскам,
> залишати якісь коментарі, тощо, і так далі» [149]

> «в нормальному рані, якщо нічого не змінилось, то цей агент просто, типу, нічого назад не поверне»
> [466]

The second requirement is "silent unless the ticket changed". The first requirement is "write to the
ticket, continuously". Built the obvious way, the first defeats the second.

VERIFIED on GitHub (research doc, live against `cli/cli`): `issue.updated_at` equals the last
**comment's** `created_at` for open issues — a comment alone moves it, and the whole-issue ETag moves
with it because the payload embeds `updated_at` and the comment count.

VERIFIED worse on the local backend, by reading `plugins/harness/bin/harness-tickets.sh` today:

```bash
l_comment() { { printf '\n---\n%s harness log:\n' "$(date -u …)"; cat "${2:?body}"; } >> "$(l_file "${1:?id}")"; … }
body_to_file() { … sed '1,/^$/d' "$f" > "$tmp"   # local: strips frontmatter only }
```

A comment is **appended to the ticket file itself**, and the "body" that anything downstream reads is
everything after the frontmatter — the appended log included. So on the local backend the
orchestrator's status comment does not merely bump a timestamp; it **edits the description**. Any
hash, any diff, any cheap model comparing "the description now" against "the description at claim
time" sees a real textual change, because there was one.

**Concrete failure.** 02:14, ticket 41 is active. The orchestrator posts its routine progress comment
[149]. At 02:15 the Д8 watcher wakes, sees the body changed, spends a model call, and reports
«змінилось» with a diff consisting of the orchestrator's own log line. Under Д9 [482] the orchestrator
must now decide whether that change contradicts finished work. Whatever it decides, it writes the
decision to the board — which is another comment, which is another change, at 02:16.

That shape is not hypothetical here. VERIFIED, `FIELD-NOTES.md §11.6`: an **85-minute loop that
nothing internal could break**, in which the deterministic watch matched a banner inside *the
orchestrator's own wrapped prose*, acted, left the screen unchanged, and matched again — «Nothing
internal detected it» — it ended only when an external `SIGTERM` arrived. Same topology: a detector
reading a surface its own actor writes to.

**What it leaves undefined.** What "the description" *is*, as a byte range, on a store where the tool
also writes. Two implementers will split on whether the log belongs to the body, and will build
opposite watchers.

---

## A2 — The default execution layout forks the local registry, so a lane's board is not the owner's board · **blocker**

**Collides:** [129] × [433] × Д2 [422] × Д8 [466].

> «локально, тобто в самому проєкту, якась структура … якась сканбан-дошка, або імітація
> сканбан-дошки … і в тому реєстрі будуть всі завдання» [129]

> «Дефолтна пропозиція, щоби абсолютно все виконувати в різних ворк трі» [433]

The registry lives *in the project*. The default is that every task runs in its **own git worktree**.
A git worktree is a separate checkout of tracked files.

VERIFIED on this machine, in the owner's own project: all **327** ticket files are tracked in git —
`git ls-files .harness/tickets | wc -l` → `327`, matching `ls .harness/tickets | wc -l` → `327`.
VERIFIED, `bin/harness-tickets.sh:18` and `bin/hlib.sh:15-23`: `TDIR="$(hproject_root)/.harness/tickets"`
and `hproject_root` walks up from `$PWD` to the nearest `.harness/config.json`. Inside a worktree,
that is the **worktree's** copy.

**Concrete failure.** 23:40, three lanes are cut as worktrees from `master`. 00:10 the owner adds
ticket 328, ready, to the trunk — Д2 says «Він може абсолютно спокійно підібрати» [422]. No lane can
see it; each lane's registry is frozen at the commit its worktree was cut from. 01:20 the owner edits
the description of ticket 312, which lane 2 is actively working — Д8's watcher hashes lane 2's own
copy, sees nothing, and stays silent exactly as [466] requires. The silence is correct behaviour and a
wrong answer.

**Second-order, VERIFIED:** every status write dirties a tracked file inside the worktree.
`FIELD-NOTES.md §4.1` records a merge that «reported success and did nothing» precisely because
`git checkout master` aborts when a tracked file is modified, and one always was — the whole incident
was one dirty tracked file. This design supplies 327 more of them, written on every claim, comment and
status change.

**Precedent for the forking itself, VERIFIED:** `FIELD-NOTES.md §12.5` — «`QUESTIONS.md` and
`JOURNAL.md` forked into a worktree's own copy, and a real owner-facing question sat there invisibly
for an hour.»

**What it leaves undefined.** Which checkout owns the registry, and whether a lane may write to it at
all. Nothing in R1-04 or Д4 says.

---

## A3 — Д8 watches only the active task; Д9's headline case is a change to a task that is already done · **blocker**

**Collides:** [466] × [482].

> «оркестратор бере це завдання і він може слідкувати за змінами в цьому завданні … Він під час цього
> слідкує за цим» [466]

> «якщо вже завдання виконане, але воно змінене, то оркестратор задати перевагу тому, щоб зробити
> новий тікет» [482]

Д8 scopes the watcher to a task the orchestrator «бере» and watches «під час цього» — while it is in
flight. Д9's *preferred* branch is the one where the task is already finished. **Nothing in this
cluster says who notices that a finished ticket changed.** The decision that fires most often has no
trigger.

VERIFIED that the obvious implementation cannot see it: `gh_done()` runs `gh issue close`, and every
poll in the shipped engine filters `--state open` (`gh_list`, `gh_list_v`). A done ticket is closed and
therefore invisible to the board poll.

**Concrete failure.** Ticket 274 finishes 22:10 and closes. 23:40 the owner tightens its acceptance
criteria and goes to bed, believing — on the strength of Д9 — that the orchestrator will open a
follow-up. 04:00 the run reaches the end of the ready queue and finishes under Д3. 09:00 the owner
finds a run report that says everything succeeded, the trunk carrying the old behaviour, and no new
ticket. Д9 was configured and never fired.

**The cost of closing the hole is not free either.** If the watcher is widened to every non-done
ticket, then on ClickUp — which the owner named as a first-class option [129] — it costs a full task
fetch per ticket per tick: VERIFIED live in the research pass, `cache-control: no-cache, no-store`, no
ETag, no `lastEditedAt` equivalent, 19,580 bytes for 4 tasks, against a 100 req/min budget. At 327
tickets that is 4 sweeps' worth of budget per tick, forever.

**What it leaves undefined.** The watched set. Active only, active + ready, or everything. Three
implementers, three products, three cost profiles.

---

## A4 — The config-by-asking lifecycle has no listener during an autonomous run · **blocker**

**Collides:** [133] × [508], and unratified on both counts.

> «коли вона робить просто ран, то система починає щитувати чи є якісь налаштування глобальні, або на
> проєкті … Якщо чогось немає, то оркестратор задає ці питання для того, щоби їх покрити» [133]

> «Ні, оркестратор не повинен нічого виводити для мене. Він має бути... Йому не треба нічо...ніякого
> інпуту вив водити» [508]

A run that discovers a missing setting asks a question. Д11 says the orchestrator outputs nothing and
takes no input. The gap between them is the entire unattended use case.

**Concrete failure.** 23:50 the owner reconnects a board (he did exactly that kind of thing all day),
types the run command, and walks away. The status mapping for one role is missing, so under [133] the
orchestrator asks. Nobody is awake. It blocks.

VERIFIED that nothing rescues it: `FIELD-NOTES.md §11.1` — «The stale-heartbeat nudge is the only
escalation the engine has», with observed peaks before a nudge fired of **2808 s (47 minutes)** and
**44791 s (about 12.4 hours)**, and «Nothing stronger is triggered at any ceiling». VERIFIED,
`§12.1`: a **149-minute stall** because a submit never landed, and «`send` fails silently above
roughly 200 characters» — so even a supervisor trying to answer the question for him may fail
silently. A config prompt is longer than 200 characters.

**Where "the user configures it" moves the problem onto someone who cannot know the answer.** The
question the orchestrator would ask at 23:50 is «which of your board's statuses means in-progress?» —
and the owner's own live ClickUp list (VERIFIED in the research pass) has `review` typed `done` and
`ongoing`/`in progress` both typed `custom`. There is no correct answer available to him at the
terminal; he would have to go and read the board.

**What is the default when he configures nothing?** Unstated. [133] says «оркестратор задає ці
питання», which is the one behaviour Д11 forbids in the unattended case.

---

## A5 — Mid-run intake has no ceiling, no default and no report, and the previous run needed a human to stop it · **major**

> «Він може абсолютно спокійно підібрати … точно може бути таке, що під час цього я докину завдання,
> його опишу підходить для AI, і AI бере це завдання, і виконує» [422]

The behaviour is confirmed and I am not contesting it. The hole is that it has no upper bound, and the
only recorded instance of this exact situation ended with the owner intervening by hand.

VERIFIED, `FIELD-NOTES.md §10.1`: «Mid-run the product owner set a soft pause at 11:15 after the ticket
queue grew from **236 to 327 in a day** (`state/SOFT-PAUSE.md`).» The brake that stopped it was a
human, awake, at 11:15.

**Concrete failure.** 23:00, the owner bulk-files 90 issues generated from a spec, every one carrying
the ready label because they came from one template. Under [422] all 90 are eligible. By 04:00 the
five-hour window is exhausted and the weekly window is materially spent on the thinnest sixty of them.
Nothing was wrong: every ticket was ready by the configured structure, and the orchestrator did exactly
what [422] says.

The limits rules do not save this. They pause, they do not prioritise: «якщо ... виглядає так, що
завдання впирається в те, що впереться в ліміти, то це окей» [171]. A weekly window spent on low-value
work is spent; the pause only decides when the next chunk of it is spent.

**Collides with his own status decision:** Д11 [508] says nothing is pushed to him — «якщо я хочу
отримати статус виконання, то я можу запустити окремий термінал». So the growth signal that made him
intervene last time is available only if he goes looking for it, at a time when by design he is asleep.

**What is the default when he configures nothing?** Unbounded pickup. That is a real choice and it may
be the one he wants — but it is currently the default by omission, not by decision.

---

## A6 — «достатньо опису» hands authorship of readiness to the orchestrator, which cancels «її притримувався» · **major**

**Collides:** [145]/[146] × [422].

> «має бути конкретна структура, якимись або тегами, або що, які потрібно фоловити … це треба буде,
> щоби придумав якусь структуру, і її притримувався» [146]

> «можливо, там буде якийсь процес, що я можу створити таску, агент аналізує, і якщо достатньо опису,
> то він його бере і імплементує. Якщо недостатньо, то він пише, що, типу, needs review» [422]

If a model decides sufficiency, the structure is advisory. If the structure decides, the model's
judgement is decoration. The two answers put the authority in different places and neither says which
one binds when they disagree.

**Concrete failure, in the direction that costs most.** 02:00, ticket 331 reads in full: "Fix the
footer — it looks wrong on mobile". It carries no Outcome, no Scope, no acceptance criteria. Under the
structure it is not ready. Under [422] a cheap model reads it, judges the description sufficient
because the intent is obvious, and a lane spends four hours and a chunk of the weekly window
restructuring the layout system. At 09:00 there is nothing to compare the result against, because the
ticket never stated what "right" was — and Д9 cannot help, because no criterion was contradicted:
none existed.

**The inverse is equally live.** VERIFIED, `FIELD-NOTES.md §11.4`: GSD's verify stage was «silently
skipped for phases 14 to 18», each verification file self-attributing `verified_by: the lane that built
the phase`, because an orchestrator **generalised a narrow warning** into a broad rule. «No automated
check caught it; manual review did.» A model-judged gate is the same class of actor that produced that.

**Undefined:** whether the sufficiency judge may write `ready` on a human's ticket, or only ever move
it to needs-review and leave promotion to the human. [422] can be read either way, and the two readings
produce different products.

---

## A7 — «мінімальний набір статусів» names no minimum, no failure verb, and status names carry no meaning · **major**

Unratified ([154]/[155] → [156]).

> «треба перевіряти, чи дошка готова до цього, тому що в дошці мають бути якісь певні мінімальний
> набір статусів, які вона може використовувати … Яка саме структура, це вже людина може
> перевизначити, переконфігурувати в середині плагіну» [153]

Three things are underdetermined at once: what the minimum set *is*, what the check *does* when the
board fails, and what a status *means*.

VERIFIED from the owner's own live ClickUp list `[AUT] Developmental Tasks`: `review` is typed
**`done`**; `ongoing` and `in progress` are both typed `custom`; `backlog` is typed `open` while
`to do` is typed `unstarted`. Names carry no semantics, and `type` is set by whoever built the list.

**Concrete failure.** The connect check maps by `type` and binds `review` → done. 03:00, a lane finishes
and the process says "move to review for a human". The board now shows `review`; the orchestrator reads
type `done` and marks the work complete; Д9 never fires because nothing was contradicted; the run
finishes clean at 04:00 and reports thirteen tickets done, one of which nobody ever reviewed.

**The failure verb is the sharper hole.** [153] says the check must happen. It does not say what the
check *does* on a board that lacks a needed status. The three available answers are all bad in
different ways, and two implementers will pick different ones:

- **Refuse to connect** — at 23:50, in a wizard nobody is watching (see A4).
- **Create the missing statuses** — which is what the shipped engine already does. VERIFIED,
  `harness-tickets.sh:73-85`: `gh_labels_bootstrap` runs `gh label create … --force` for five labels.
  On a shared repository, or a shared ClickUp list, that is an externally visible schema change to
  other people's board, made at 04:00 with nobody awake. On ClickUp a status set is a list-level
  property; changing it changes it for every task in the list.
- **Proceed with a partial mapping** — which silently loses whichever role has no home.

**Collides with [370]:** «він би не мав зупиняти якісь там тести, які не він запускав» — the principle
that the tool does not act on what is not its own. A label or status it creates on a board it did not
build is the same category.

---

## A8 — Д9's new tickets enter Д2's pool, and nothing bounds the chain · **major**

**Collides:** [482] × [422].

> «оркестратор, скоріш за все, зробить просто нове завдання, для того, щоби внести ці зміни» [482]

> «Він може абсолютно спокійно підібрати» [422]

A ticket created by Д9 has to be `ready` to ever be executed. Д2 says anything that becomes ready
during the run is picked up during the run. So the orchestrator can file work for itself, claim it,
and — if a further change arrives, or if its own watcher misreads one — file more.

**Concrete failure at 04:00 with no human awake.** The watcher (A1) sees the orchestrator's own status
comment as a body change. Tier-2 judgement decides it touches a ticked acceptance criterion. Д9 files
ticket 332 «apply the change». Working 332 produces status comments on 332, which its watcher sees as
changes to 332, which files 333.

That this is a real failure mode and not a debating point is VERIFIED three times over in the previous
run: the 85-minute Escape/continue loop nothing internal broke (`§11.6`); a dead run flagging the same
condition every three minutes **for about five days, 1085 times, unresolved** (`§11.6`); and an unwedge
process polling «run is stopped — holding» every 180 s for 32 minutes while doing nothing (`§11.6`).
And the misread half is VERIFIED too — `§12.2` records a status-line regex that missed `Opus 4.8`, a
merge-equivalence gate that diffed **554 unrelated files**, and a self-patch that reported `SYNTAX OK`
while its `sed` anchor never matched.

**What it leaves undefined.** Whether machine-authored tickets are eligible for pickup in the run that
created them; whether a generation counter exists; and who is allowed to file the *second* follow-up
for the same original ticket. Nothing in Д9 says.

---

## A9 — «будь-яка інша тула» is a support promise with no floor, and «переконатися, що є доступ» is undefined · **major**

> «Наприклад, GitHub Issues, або, ClickUp, або будь-яка інша тула, і треба просто переконатися, що є
> доступ до цього ресурсу. Та й все.» [129]

In English, the rest of the answer: the second option is a connected board, any kanban board at all.

«Та й все» sets the bar at access. But this cluster then requires four further capabilities of the
same board: set statuses [149], leave comments [149], expose a readiness marker [146], and permit a
**silent** description-change check [466]. Access does not imply any of them.

VERIFIED, and this is not a hypothetical board: ClickUp — named by the owner in the same sentence —
has no conditional requests (`cache-control: no-cache, no-store`, no ETag), no description-change
field in the polled payload (`date_created`, `date_updated`, `date_closed`, `date_done` and nothing
else), and its only precise description-change signal is the webhook `history_items.field == "content"`
(CLAIMED, ClickUp docs), which a laptop with no public ingress cannot receive. **One of the two boards
he named by name cannot satisfy Д8 the way GitHub can.**

**Concrete failure on the access check itself.** 23:00 the connect step verifies access with a read —
that is what "verify access" most naturally means, and it is the only check that cannot damage
anything. 03:00 the orchestrator tries to move a status and gets 403, because the token is
read-scoped, or because the ClickUp list is in a Space the token's seat cannot write to. Under Д5 it
retries three times [442] and stops. Three lanes have finished real work; the board still shows every
one of those tickets as ready; at 09:00 the queue is a lie in the opposite direction, and a second run
started in the morning re-claims work that is already done.

**What it leaves undefined.** What "access" is verified against — read, comment, status-write, create,
close — and what the *floor* is for calling a board supported. Without a floor, "supports any kanban
board" means "silently degrades on most of them", and the degradation is invisible until 03:00.

---

## A10 — The local ticket file is spec, state and log in one, with no defined body region · **major**

> «якась сканбан-дошка, або імітація сканбан-дошки, як саме це все відбувається, і в тому реєстрі
> будуть всі завдання» [129] — «неважливо яка» [129]

"The shape does not matter" is fine for a human. It is not fine for a structure that must be
«притримувався» [146] by a program and diffed by a watcher [466].

VERIFIED in the shipped engine, which is the only existing instance of this decision: the readiness
floor is three greps over the whole file —

```bash
grep -qiE '^#+ *(outcome|goal|objective)'                              "$f" || miss="$miss outcome"
grep -qiE '^#+ *(acceptance( criteria)?|accept|definition of done|dod)' "$f" || miss="$miss acceptance-criteria"
grep -qiE '^#+ *(scope|in scope)'                                      "$f" || miss="$miss scope"
```

— and `l_comment` appends the run log to that same file, and `body_to_file` returns everything after
the frontmatter. So the floor's inputs include the tool's own log.

**Concrete failure.** A human strips ticket 210's `## Scope` section while rewriting it at 23:30. It
should now fail the floor. But the orchestrator commented on it earlier, and the comment quoted the
ticket's own headings back (which the engine does routinely — VERIFIED, `FIELD-NOTES.md §10.2`,
`J-ORCH-37`: a ticket body quoting the harness's own template tokens broke a spawn, and `J-ORCH-39`
records the attribution error that followed). The grep matches the quoted heading in the log. The floor
passes. `stale_report` releases the ticket back to `ready` on the strength of a floor check that was
reading the tool's own echo, and a lane picks up a ticket with no scope at 04:00.

**What it leaves undefined.** Where the description ends and the log begins, on the backend the owner
named *first*. Until that boundary exists, Д8's «чи змінилось завдання» has no referent on local
tickets, and the readiness floor has no fixed input.

---

## A11 — A dead run's board writes are indistinguishable from a live run's, and the shipped staleness default is seven days · **major**

**Collides:** [149] × [300]/[301] × Д10 [497].

> «щоби ставити статуси таскам, залишати якісь коментарі» [149]

> «якщо раптом одночасно два якісь оркестратори працюють, то це не окей. Це треба відслідковувати і не
> дозволяти» [300] / «Це треба відслідковувати і не дозволяти» [301]

The board carries `in-progress` as a fact about the world. Nothing in C3 says which run put it there,
when, or whether that run is alive. The single-orchestrator invariant [300] is what makes the state
readable — and Д10 [497] concedes that the orchestrator restarts with executors still running, which is
the case where the invariant is under strain.

VERIFIED that the previous generation ends this way rather than cleanly: `FIELD-NOTES.md §10.1` —
`[2026-09-07T09:08:21Z] watch: orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may
sleep)`, leaving `DEAD-RUN` and `STOPPED` on disk.

VERIFIED that the shipped recovery cannot resolve it quickly: `stale_report` defaults to **7 days**
(`stale_report() { local days="${1:-7}" … }`), and idleness is derived from `updatedAt` on GitHub
(`gh_list_v`) or file mtime locally (`l_list_v`) — **both of which the orchestrator's own comments
bump**. A ticket abandoned by a dead run therefore looks alive for a week, and looks freshly alive
every time anything commented on it.

**Concrete failure, the "second run" case.** 03:40 the Mac sleeps mid-run. Tickets 88, 91 and 104 sit
`in-progress` with the orchestrator's own comments claiming progress. 09:00 the owner starts run N+1.
Those three tickets are not `ready`, so run N+1 does not touch them; they are not stale by the
seven-day rule, so nothing releases them; and their last comment says work is under way, so a human
reading the board believes it. They are invisible to both the tool and the person until the following
week.

**And the inverse, on a shared machine.** If two orchestrators do overlap — which [300] forbids and
Д10 concedes can happen — the second sees the first's `in-progress` labels as its own abandoned work,
because nothing on the board identifies the writer. VERIFIED that attribution failures of exactly this
kind happened: `FIELD-NOTES.md §11.5`, the destroyed default stack — «the actor was never identified».

---

## A12 — The only shipped implementation of «залишати якісь коментарі» keeps exactly one comment · **minor**

> «щоби ставити статуси таскам, залишати якісь коментарі, тощо, і так далі» [149]

VERIFIED, `harness-tickets.sh`:

```bash
gh_comment() { gh issue comment "$1" --repo "$REPO" --body-file "$2" --edit-last --create-if-none …; }
```

`--edit-last` **overwrites the orchestrator's previous comment**. The board therefore holds one comment
per ticket, containing the most recent status, not a trail.

**Concrete failure.** 09:00, the owner opens ticket 91 to understand why a lane stopped at 02:00. The
comment says what the orchestrator thought at 03:55. The reasoning at 02:00, and the decision Д9 made
at 02:40, are gone. The board — the «помічник» — has no memory of its own assistance.

Minor because it is an implementation choice, not a hole in the decision. It is listed because the
decision's value to the owner is a readable trail at 09:00, and the existing code does not produce one;
whoever rebuilds this will inherit the shape unless it is named.

---

## Attacks I dropped after testing them

Recorded so the list can be trusted as filtered, not merely generated.

- **"GitHub Issues is a decision, and it is the wrong one."** Dropped. It is hedged —
  «Першим ділом рекомендувати GitHub Issues, тому що для конкретно проекта і **напевно** в цьому
  перевага» [129] — and `extract/corrections.md:56` already records it as a hedged first
  recommendation. There is no decision there to attack, and the stated reason (the issues live with the
  project) is sound on its own terms.
- **"Two sources is too few."** Dropped. «Конкретно поки тільки два режими» [129] scopes it explicitly
  and temporarily. Attacking a stated scope is not an attack.
- **"The cheap watcher model will be wrong about what changed."** Dropped as a standalone: it is a vague
  worry until it has a trigger, and the triggers that matter are already A1 (it is fired by the tool's
  own writes) and A8 (its error compounds). The model's accuracy on a real human edit is a quality
  question, not a design hole.
- **"Readiness by tag is too weak."** Dropped. The measured evidence runs the other way: a purely
  structural, grep-sized floor held across **327 tickets, 288 of them done, with 15 of 15 `ready`
  tickets passing and zero violations** (research doc §2.1). The hole is not the floor's weakness; it
  is what counts as its input (A10) and who may bypass it (A6).
- **"No atomic claim, so tickets will be double-claimed."** Dropped from this cluster's list as an
  *attack on a decision*: it is a real and measured defect (27 winners of 50 for the read-then-write
  shape; the id allocator fix still absent from the source repo, md5 `915c2cd4…`), but it belongs to
  the implementation, and the owner's own single-orchestrator rule [300] addresses the design. It
  appears here only as the mechanism inside A11.
