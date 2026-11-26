# C9 — Adversarial pass: workflow-engine adapter, verification, delivery, observability

Written 2026-09-19. Cluster items: **R1-03, R1-12, R1-13, Д4, Д11, R1-17**.

Method: attack each decision as a hostile reviewer, then discard anything that could not be turned
into a named failing scenario. Eleven survived. No attack below proposes a replacement decision —
each names a hole, a collision or an undefined default, and stops there. The owner's words are the
source of truth; where a decision is quoted it is quoted verbatim with its `[row]` anchor.

Evidence labels: **VERIFIED** = read in source or executed on this machine today ·
**CLAIMED** = asserted by a doc I did not run · **INFERRED** = my reading.

Commands I ran myself for this pass (2026-09-19, in `/Users/sasha-marchuk/Work/claude-plugins`):

```
git --version                                       → git version 2.33.0
gh api repos/:owner/:repo/rulesets                  → []
gh api repos/:owner/:repo/branches/main/protection  → 404 Branch not protected
grep -rln 'telegram|slack|notify|notification' plugins/harness/  → docs/DESIGN.md, docs/FIELD-NOTES.md only
sed -n '146,190p' plugins/harness/bin/harness-run.sh            → do_status --json health rule
sed -n 'hcurrent_run' plugins/harness/bin/hlib.sh               → run resolution from cwd/HARNESS_PROJECT
cat plugins/harness/commands/status.md                          → routes /harness:status through a skill
```

---

## A1 — blocker — Two decisions together leave the orchestrator with no completion oracle

**Decisions attacked.** R1-13 [344]: *"оркестратор повинен діяти відповідно тому сетапу, який в нього
є. Якщо в нього, наприклад, get shutdown, то get shutdown сам роб verifіcation. Якщо в нього щось
власне, то ці всі перевірки відбуваються виключно так, як юзер налаштував"* — plus R1-03 [118]:
*"які дії будуть, за якими, коли перевірка, **чи буде перевірка**"*.

**The hole.** R1-13 delegates verification to the process. R1-03 makes "no verification at all" a
legal process. Nothing in either decision says how the orchestrator learns that a unit of work
*finished*, as distinct from *the session ended*. "Done" is not the same object as "verified", and
neither decision assigns it an owner.

**Concrete failure.** The user configures the official-marketplace `feature-dev` process (VERIFIED,
research §3.2: one 125-line prose command file, **no state file, no status command, no git, no
resumability**, its only progress surface `TodoWrite` inside the session). At 04:12 a worker session
reaches `feature-dev` Phase 3, whose text is literally **"DO NOT START WITHOUT USER APPROVAL"**, ends
its turn and exits 0. The orchestrator sees a clean exit. Under R1-04 [149] it is supposed to move
the ticket's status on the board — *"оркестратор ставить статуси та залишає коментарі"* — so it marks
the ticket done. Under R1-12, with the autonomous trunk setting on, it opens and merges a PR
containing a design discussion and no implementation. Field notes §4.2 records the same shape with a
net still in place — phase 21 reached the trunk without its validator and was only saved because the
orchestrator noticed within a minute and re-ran validation after the fact. R1-13 removes that net by
design, and R1-03 guarantees there are engines that cannot supply one.

**Why it survives scepticism.** It is not an argument that he should impose verification — he decided
that under the evidence [342] and the decision stands. It is that *completion detection* was never
discussed at all. Two implementers will build different things: one treats process exit 0 as done,
one requires a declared marker file and stalls forever against `feature-dev`, which produces none.

**What is undefined:** what "done" is; who declares it; what happens when the engine declares nothing.

---

## A2 — blocker — Д4's default worktree and GSD's worktree ownership cannot both hold, and he named the reconciliation without a solution existing

**Decision attacked.** Д4 [433]: *"Дефолтна пропозиція, щоби абсолютно все виконувати в різних ворк
трі … щоби це ворк трі був з головної гілки"*, and in the same answer *"якщо людина вибере гіт шдан,
то там є воркспейс, **і з цим треба поєднювати**"*.

**The hole.** "з цим треба поєднювати" is a task, not a decision. As of today the two cannot be
reconciled, and the decision does not say which side gives way.

**Concrete failure (VERIFIED mechanism).** Under Claude Code, `gsd-tools dispatch-isolation` returns
`harness-worktree`, which per GSD's own `dispatch-isolation-gate.md` means the host creates and binds
the worktree per agent and **"GSD runs no git"**. GSD's executor worktrees are therefore forked from
`origin/HEAD`, and GSD's own escape hatch `worktree.baseRef:"head"` **is not read by the host** — GSD
says so in its own message. Run against a real GSD project today, `gsd-tools worktree base-check`
returns `{"shouldDegrade": true, "reason": "head-diverged-from-fork", …}` and
`dispatch-should-flatten` returns `true`.

So: the orchestrator honours Д4's default and creates `worktree/ticket-17` off `main` at 03:00. It
dispatches GSD `execute-phase` inside. One of two things happens, both silent:

1. GSD sees HEAD ≠ `origin/HEAD`, degrades to sequential, and the six-plan phase that should have run
   four-wide runs one-wide. Throughput drops by a factor the owner never chose, at 03:00, with Д11
   guaranteeing nothing is printed.
2. Or GSD's sub-worktrees fork from `origin/HEAD` and build the phase on a base that is not the
   orchestrator's base. Field notes §4.3 is this exact failure, observed: GSD computed
   `gsd/phase-23-tooling-the-harness-and-the-pre-commit-checkers` from a roadmap slug, one word off
   the lane branch, and *"left alone `execute-phase` would cut that name fresh from `origin/master`
   and lose the merged master tip"*.

And a **third** owner now exists that did not when the field notes were written: `claude --worktree`
(VERIFIED in `claude --help` today). Three parties can create a worktree for one task, and the
decision names none of them as the owner.

**What is undefined:** who creates the worktree; what base it is cut from; what the orchestrator does
when the engine declares a different base than the one it recorded. Two implementers build opposite
systems from the same sentence.

---

## A3 — blocker — "Respect the repo's rules" has no machine source on his own repositories, and no default is stated

**Decision attacked.** R1-12 [331]: *"не порушується правило, якщо, наприклад, в репозиторії якісь
інші правила, або, наприклад, обмеження, що там можна зробити тільки пул реквесту, тощо, так далі, і
це дуже важливо розуміти та приймати"*.

**The hole.** The decision binds the orchestrator to rules but never says where rules are read from,
and on his own flagship repository the rule exists in exactly one place a machine will not look.

**Concrete failure (VERIFIED by me today, re-runnable).** In `SashaMarchuk/claude-plugins`:
`gh api repos/:owner/:repo/rulesets` → `[]`; `gh api repos/:owner/:repo/branches/main/protection` →
`404 Branch not protected`. Meanwhile the repo's `CLAUDE.md` states the work must be *"shipped via PR
(no direct pushes to `main`)"*. At 04:00, R1-12's autonomous setting on, the orchestrator queries the
forge, correctly concludes nothing is protected, and pushes thirteen merges straight to `main` of a
repository carrying eleven production plugins. It broke no rule it could see. Externally visible,
irreversible without force-pushing a public branch, and nobody is awake — and under Д11 nothing was
printed while it happened.

**The collision.** R1-15 [357] puts prohibitions in *"лише одного файлу, який може доповнюватись,
текстописний"* and adds *"Але, так, це максимум"*. The PR-only rule in this repo is **not** in that
file — it is in `CLAUDE.md`, a file no decision in the interview names. So the one place the rule
lives is neither the forge nor the prohibitions file.

**Where "the user configures it" moves the problem.** Telling the user to declare `protected: [main]`
per project requires them to remember, per repository, a rule they already wrote down somewhere else.
The second time they add a repo at midnight they will not.

**What is undefined:** the source of truth for repo rules, and the default when all machine sources
say "nothing is protected" while prose says otherwise.

---

## A4 — major — Д11's silence plus a pull-only status makes the one failure class that actually happened invisible

**Decision attacked.** Д11 [508]: *"Ні, оркестратор не повинен нічого виводити для мене … якщо я хочу
отримати статус виконання, то я можу запустити окремий термінал, прописати orchestrator двокрапка
статус"*, softened at [512] to *"мінімальну кількість аутпуту і стокінгів"*.

**The hole.** "Status comes from a separate command" says nothing about **who writes the state that
command reads**. A status command is a renderer; its honesty is entirely the daemon's.

**Concrete failure, from the previous generation, VERIFIED in its source.**
`harness-run.sh do_status --json` computes health as exactly this:

```bash
{ [ -s "$run/state/attention" ] || [ "$dead" = true ]; } && healthy=false
```

And field notes §2.1 records `harness-run.sh:226` doing `: > "$run/state/attention.tmp"` **every
cycle**, destroying anything any other process appended — the context watch wrote corrections there
all night and discovered only at 06:58Z that they had been erased. Now put the two together against
field notes §11.6: the 85-minute self-sustaining loop in which the watch matched a fake rate-limit
banner inside the orchestrator's own wrapped prose, pressed Escape and sent `continue` every sixty
seconds, with `attention.tmp` truncated to zero bytes on every pass and
`context-watch.log:5620` reading literally **`NO ONE IS BEING TOLD`**. A pull-only status command
would have printed **`healthy: true`** for all 85 minutes. *"Нічого не детектувало"* — it ended only
when an external `SIGTERM` arrived.

So the decision produces a bad outcome in precisely the case that killed the previous generation: the
daemon is alive, busy, wrong, and reports itself fine. Silence by design plus self-reported health
means nothing in the system is positioned to contradict it.

**What is undefined:** what evidence status is computed from, and whether any of it is independent of
the daemon being judged.

---

## A5 — major — "лише переконатися, що це працює" caps the duty at one verification; the only recorded failure is a channel that was verified and then died

**Decision attacked.** R1-17 [395]: *"Та повинен **лише** переконатися, що це працює"*.

**The hole.** The word *лише* is doing the damage. It caps the orchestrator's duty at a point in
time, and the decision names no point. Preflight-only is the natural reading and it is the one that
fails.

**Concrete failure.** Preflight at 22:00 sends a Telegram message, gets `ok:true` with a `message_id`,
and the run starts. At 02:00 the bot is removed from the group, or the token is rotated, or the
network drops. Every alert from 02:00 onwards 200s into nothing. The orchestrator is satisfied: it
verified the channel. Д11 guarantees the terminal says nothing. The merge-that-moved-nothing (field
notes §4.1) happens at 03:40 and no human learns of it until morning.

This is not hypothetical shape-matching: field notes §11.6 records the human-notification watchdog
that *"had already exited ('run finished') and was never restarted"* while the run was in fact still
looping, and separately a condition that re-fired **1085 times over about five days** unresolved.
**VERIFIED by me today:** `grep -rln 'telegram|slack|notify|notification' plugins/harness/` matches
only `docs/DESIGN.md` and `docs/FIELD-NOTES.md` — the previous plugin contains **no notification code
at all**, so the watchdog that died was a project-side script the plugin never owned or supervised.
The new decision inherits that gap and says nothing about ownership.

**Second half of the same hole: "працює" is undefined.** VERIFIED from the Telegram Bot API docs
(research §2.6): `getMe` *"proves the bot's capabilities and configuration, not operational status"*,
and the Bot API documents **no read receipts for bot-sent messages**. So one implementer ships
`getMe` (which passes for a bot that was kicked from the chat), another ships a real `sendMessage`,
and a third claims "verified delivery" for something that is at most *service accepted*.

**What is undefined:** when verification happens, how often it repeats, and what "works" means at each
of the three provable levels.

---

## A6 — major — R1-17 settles the mechanism and leaves the policy empty; both shippable defaults were observed to fail, and one collides with Д7

**Decision attacked.** R1-17 [395]: *"Людина налаштовує, які типи можуть приходити. Чи коли тільки
щось критичне, чи будь-які сповіщення … Чи це сповіщення будуть тільки просто в терміналі. Це не
важливо"* and *"чи треба взагалі канал якогось зв'язку"*.

**The hole.** The substantive half of R1-17 — what is worth interrupting him for and what waits — was
never answered (extraction notes, by-item R1-17 final row: he redirected the whole question to
configuration; the quiet-hours clause at [394] was asked and never touched). Configuration still
needs a value in the box on first run, and the decision supplies none.

**Where "the user configures it" moves the problem onto someone who cannot know.** The event taxonomy
is the orchestrator's, not his: "merge reported success but the ref did not move", "engine returned
`human_needed`", "lane heartbeat stale but shell count non-zero" are categories a first-time user has
no vocabulary for. Asking them to enumerate notification types before their first run is asking them
to name events they have never seen.

**Concrete failure, second run.** Run one is configured with no types because the wizard could not
name any. On run two either (a) the orchestrator is silent when the merge did nothing — field notes
§4.1, *"Already up to date"* and *"Everything up-to-date"*, both of which *"read like success"* — and
he finds out at 09:00 that a night produced nothing; or (b) the implementer defaults to "everything"
and reproduces §11.6's 1085 repeats. Both defaults were observed in the real run.

**The collision with his own Д7.** R1-17 makes *no channel at all* a legal configuration. Д7 [455]
sets the default behaviour when only human-blocked work remains: *"по дефолту я б рекомендував, що він
залишається та чекає на мої відповіді"*. A run with `notifications: none` and Д7's default waits
indefinitely for an answer to a question nobody was told exists. Д6's questions file [449] is where
the question lands, but Д6 is a *pull* surface he has to think to open. At 04:00 nothing pushes, and
by his own account of Д6 the expectation is live pickup — *"в лайв режимі я міг це прийти і це
переглянути"* — which is a latency promise in the opposite direction.

**What is undefined:** the shipped default event set, and whether "no channel" is legal in
combination with settings that can block a run indefinitely.

---

## A7 — major — "постійно переконуватись" creates a detector with no legal action

**Decision attacked.** Д4 [433]: *"І **постійно переконуватись**, що всі ті енвайрмент верібли, які
потрібні, вони запущені відповідно, тощо, так далі … або що є **якісь запущений стек**"*.

**The hole.** Three things are undefined and each changes the build: how often "постійно" is; who
declares which env vars and which stack are "потрібні"; and what the orchestrator does when the check
fails mid-task. The third is the one that bites, because his other decisions have already removed the
obvious answers.

**Concrete failure, taken from the real run.** Field notes §11.5: the owner's own container
`<work-project>-app-1` was `OOMKilled` (exit 137) at `2026-09-13T03:29:01Z` while the `v-phase-21`
validator ran two `docker compose up --build` at once; *"Detected only by correlating timestamps with
`docker inspect OOMKilled=true` — there was no live alert"*. A continuous stack check fires at
03:29:05. Then what?

- Restart the stack? Д3 [430] scopes teardown to *"якщо він це сам підняв"* and R1-16 [370] is
  explicit that his own parallel work is out of bounds: *"якщо, наприклад, в тій самій папці я
  паралельно працюю над чимось, це не запускав оркестратор, це роблю я, він цього не має зупиняти"*.
  The dead container is **his**, not the orchestrator's. Restarting it violates R1-16.
- Hold the lane? Then a lane sits blocked until morning and, under R1-17 with no channel configured
  (A6), nobody is told.
- Escalate? R1-13 says verification belongs to the process and the process knows nothing about his
  Docker stack.

The decision asks for a detector and every action it could take is forbidden by a different decision
of his. Two implementers will pick different horns.

**A second edge in the same record.** Field notes §11.5 also records the owner's default stack
destroyed by a `docker compose down -v` with **no `COMPOSE_PROJECT_NAME` exported**, landing it on the
default project; *"the actor was never identified, and a session had refused that exact action as
owner-only two minutes earlier"*. A continuously-running environment repairer is a new actor of
exactly that class, and the decision does not bound what it may execute.

---

## A8 — major — "no mixing" is clean as a rule about process definition and silent about every integration seam

**Decision attacked.** R1-03 [118]: *"або комбінувати але, ні, комбінувати ні, тут або або, або свій,
або вже готовий, якщо готовий, то який саме"*.

**The hole.** The rule settles where the *steps* come from. It says nothing about the seam where the
orchestrator's own authority meets the engine's verdicts — and two of his other decisions put
orchestrator behaviour on top of GSD's, which is a mix under any operational reading:
Д4 [433] *"там є воркспейс, і з цим треба поєднювати"* and R1-12 [331] *"ці конфігурації повинні
працювати приблизно по такому самому флоу, як це працює зараз в Git Shodan"*.

**Concrete failure.** VERIFIED from GSD's `references/honest-verifier.md`: a non-inferable check with
no explicit evidence *"abstains → ⚠️ `insufficient_spec`, flagged, → `human_needed` — never
`passed`"*, and in autonomous mode *"it produces a prominent `unverified — held-out test recommended`
flag and the completion line reads 'complete with N unverified non-inferable checks'"*. At 04:00 the
engine hands back exactly that. Under R1-13 the verdict belongs to the process, and the process's
verdict is "complete, with unverified checks" — so the orchestrator merges. Under R1-14 [082] the
orchestrator may force a stop and *"агент сам буде пробувати детермінувати, коли це робити"* — so it
escalates and the run parks until morning. Both readings are faithful to a decision of his; they
produce opposite outcomes for the same night. Field notes §11.4 is the recorded version of the first
reading: *"GSD's verify stage was silently skipped for phases 14 to 18"*, each `NN-VERIFICATION.md`
self-attributing `verified_by: the lane that built the phase`, and *"No automated check caught it;
manual review did."*

**What is undefined:** which side owns the escalation decision when the engine reports a
not-quite-failure. "Або або" answers a question about process authorship and is read, wrongly, as
answering this one.

---

## A9 — major — stacked PRs are named as a capability with no precondition, no eligibility rule and no refusal path

**Decision attacked.** R1-12 [331]: *"оркестратор має за можливості гіта, а саме те, що там можна
піари стакати, і він це теж може використовувати"*.

**The hole.** A capability is granted and nothing says when it applies, what it requires, or what
happens when the requirement is missing.

**Concrete failure (VERIFIED preconditions, today, on his machine).** `git --version` → **2.33.0**, so
`rebase.updateRefs` / `--update-refs` (Git 2.38+) does not exist here; `which gt spr ghstack git-spr`
→ none installed. The orchestrator stacks three tickets: `t-17 → t-18 → t-19`. At 04:10 a review bot
forces a change on `t-17`; the orchestrator rebases it. Without `--update-refs`, `t-18` and `t-19`
still point at the pre-rebase commits. `gh pr merge` on `t-18` then lands a diff that re-applies
`t-17`'s superseded commits, or conflicts in a way the autonomous path has no rule for. Nothing prints
(Д11); no process verifies merge topology (R1-13); and field notes §4.1 establishes that a merge that
achieved nothing prints `Already up to date` and *"reads like success"*, caught last time *"only
because the orchestrator checked what `master` actually pointed at after the push rather than trusting
the exit status"* — a check R1-13 assigns to nobody.

**Eligibility is undefined too.** Dependency information exists — R1-05 [160]: *"якщо якісь завдання
не може виконуватися, тому що не виконалось одне з попередніх, то його ми не можемо взяти"* — but
nothing links it to stacking. Two implementers: one stacks every concurrent ticket (creating false
dependencies between independent work and serialising the merge order), one never stacks.

**What is undefined:** the git-version precondition, the refusal behaviour when it is absent, and
which tickets are eligible.

---

## A10 — minor — "another terminal, `orchestrator:status`" assumes one run, one project and a cwd, and Д4 guarantees the cwd is wrong

**Decision attacked.** Д11 [508]: *"я можу запустити окремий термінал, прописати orchestrator
двокрапка статус і таким чином я отримую статус теперішнього"*.

**The hole.** "теперішнього" has no addressing scheme. Which run, on a machine running two.

**Concrete failure (VERIFIED in the previous generation's source).** `hproject_root()` resolves from
`$HARNESS_PROJECT` or by walking up from cwd for `.harness/config.json`, and its own error text reads:
*"If you are in a worktree, export HARNESS_PROJECT=<project-root> (the launcher sets this
automatically)."* Д4's default puts **every task in its own worktree**. So the user opens a terminal
at 04:00, happens to be in a lane worktree (the natural place to be if they were looking at the work),
and status either errors or resolves to a different run. `hcurrent_run()` additionally returns rc 2
when more than one non-`STOPPED` run directory exists — a shared machine or a crashed prior run puts
it there.

This has a recorded analogue: field notes §12.5, *"`QUESTIONS.md` and `JOURNAL.md` forked into a
worktree's own copy, and a real owner-facing question sat there invisibly for an hour"*. A
cwd-resolved status surface reproduces that shape for the status channel itself.

**Where it collides.** R1-10 [300–302] forbids two orchestrators over the same work — *"якщо раптом
одночасно два якісь оркестратори працюють, то це не окей"* — but says nothing about two runs in two
projects, which is a normal state on one laptop.

**What is undefined:** how a status request names the run it wants.

---

## A11 — minor — Д11's binding version is unratified and has no unit, and the shipped product already violates its intent without being detectable

**Decision attacked.** Д11 [512]/[514]: *"Дефолтний варіант, що оркестратор використовує мінімальну
кількість аутпуту і стокінгів для цього. І все … Але людина може це переналаштовувати"*.

**The hole.** Two problems, both small individually.

First, the corrected version was **never confirmed**: the interviewer asked *"Це остаточний варіант,
підтверджуєш?"* at [515]/[516] and the next line is Д12 (corrections.md:104). His own rule
[003] — *"Пізніше сказане перемагає раніше сказане"* — makes the soft version binding, but the two
versions imply different architectures. *"Нічого не виводити"* [508] permits a tick loop with no
model in it at all; *"мінімальну кількість"* leaves a model in the loop at an unspecified rate.

Second, "minimal" has no unit, so no implementation can be shown to violate it.

**Concrete failure, present today (VERIFIED).** `plugins/harness/commands/status.md` reads, in full:
*"Invoke the `harness:harness` skill via the Skill tool, passing `--status $ARGUMENTS` through
verbatim."* So asking for status **spends a model turn** — while `harness-run.sh do_status --json`
underneath it is pure bash + jq and its own comment reads *"machine-readable health for a
cron/notifier babysitter… No terminal/network required beyond the limits verdict"*. The zero-cost path
exists and the command in front of it does not use it. Under the decision as worded, nobody can say
that is wrong: one model turn per status query is arguably "minimal". Checking status ten times in a
night costs ten turns, on a run whose whole design point is not spending tokens on chatter.

**What is undefined:** whether "minimal" is a budget, a rate, or a prohibition — and therefore whether
a model may be in the status path at all.

---

## Attacks I considered and discarded

- *"YAML is the wrong format"* — he hedged it himself in the same breath (*"Можливо, не так, тут треба
  буде подумати, як саме"* [118]), so there is no decision to attack. Format is open, not wrong.
- *"He should not let the user define a process with no checks"* — that is substituting my preference
  for his decision under evidence [342]/[344]. What survives instead is A1, which attacks the
  *completion* gap, not the verification decision.
- *"Notifications should have quiet hours"* — he voided the night frame at [054]: *"я б взагалі навіть
  не фокусувався на тому, що там щось вночі працює … розділити, як автономний ран та контрольований"*.
  Attacking the absence of quiet hours attacks a frame he rejected.
- *"Terminal-only notifications are useless"* — he said *"Це не важливо"* [395] about the channel
  choice, and for a controlled run in front of a human it is true. The failing case is the autonomous
  one, which A6 already carries.
- *"One worktree per task will exhaust the machine"* — R1-05 [160] already caps concurrency by
  configuration and he explicitly deferred machine-resource awareness (*"це от останнє про сто
  завдань, це забери"* [163]). It is a deferred item, not a hole.

---

## Where these attacks land against the open questions already recorded

A1 sharpens Q3 (does the orchestrator verify its own actions) into a narrower one: *who declares a
unit of work finished when the process declares nothing*. A2 is Q4 with the mechanism named. A3 is Q6
plus the finding that the rule lives in `CLAUDE.md`, a file no decision mentions. A5, A6 and A11 are
Q2 and Q8. A7 and A9 add two questions not on that list: what the continuous verifier is permitted to
*do*, and what the orchestrator does when a named git capability is unavailable.
