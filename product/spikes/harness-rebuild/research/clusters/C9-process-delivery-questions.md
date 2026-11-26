# C9 — Round-2 questions: workflow-engine adapter, verification, delivery, observability

Cluster items: **R1-03, R1-12, R1-13, Д4, Д11, R1-17**. Written 2026-09-19.
Source for every gap: `C9-process-delivery-research.md` (§ numbers below) and
`C9-process-delivery-challenge.md` (A1–A11). Owner quotes are verbatim from
`round-1/TRANSCRIPT-01.md` with their `[row]` anchor.

**Ten questions.** Three blockers (implementation forks in opposite directions without them), seven
majors. Nothing here re-asks a decision he made; each one names a hole the challenge pass found in
a decision he already gave, and stops.

**Style contract applied** (from `research/extract/meta.md` §C and `outside-list.md` §14):
one question, asked once; the concrete case ships **with** the question (seven of eighteen round-1
items needed a worked example before he could answer — [113], [227], [242], [289], [340], [353],
[363], [505]); options named and then silence, no recommendation; his vocabulary only
(оркестратор, ран, тікет, ворк трі, ліміт, хардстоп, софтстоп, піар, головна гілка, енвайрмент
верібли, стек); the word «вночі» avoided throughout, because he voided that frame at [054]:
«я б взагалі навіть не фокусувався на тому, що там щось вночі працює … розділити, як автономний ран
та... контрольований».

---

## 1 — blocker — gap — Who declares a тікет finished when the process declares nothing

> Ти сказав, що перевірку робить той процес, який людина налаштувала, і що процес узагалі без
> перевірок теж законний. Але є готові процеси, які про себе нічого не пишуть — просто сесія
> закінчилась. Як оркестратор має зрозуміти, що тікет зроблено, а не що сесія просто вийшла?
>
> A) вихід без помилки — це «зроблено»;
> B) процес зобов'язаний лишити файл або позначку, і без неї тікет висить;
> C) оркестратор питає тебе, коли процес нічого не сказав.

**His decisions being respected, not attacked.** R1-13 [344]: *«оркестратор повинен діяти відповідно
тому сетапу, який в нього є. Якщо в нього, наприклад, get shutdown, то get shutdown сам роб
verifіcation. Якщо в нього щось власне, то ці всі перевірки відбуваються виключно так, як юзер
налаштував»*. R1-03 [118]: *«які дії будуть, за якими, коли перевірка, **чи буде перевірка**»*.

**The hole (challenge A1).** «Done» and «verified» are two different objects. R1-13 assigns the second
to the process; nothing in either answer assigns the first to anyone.

**Evidence that the hole is real, not theoretical.** VERIFIED, research §3.2: the official-marketplace
`feature-dev` process is one 125-line prose command file with **no state file, no status command, no
git, no resumability**; its only progress surface is `TodoWrite` inside the session, and its Phase 5
text reads literally *«DO NOT START WITHOUT USER APPROVAL»*. A worker reaches that line, ends its turn
and exits 0. Under R1-04 [149] the orchestrator then moves the ticket's status on the board; under
R1-12 with the autonomous setting on, it opens and merges a PR containing a design discussion and no
code. Field notes §4.2 records the same shape surviving only because a net existed that R1-13 removes
by design.

**What the answer changes.** A: no marker infrastructure at all, and the engine descriptor needs no
`completion` point. B: every engine descriptor carries a declared completion signal, and engines that
produce none (`feature-dev`) are only runnable in a degraded mode. C: a new escalation class and a
route to Д6's questions surface.

---

## 2 — blocker — collision — Who creates the ворк трі when the chosen process creates its own

> Твоя дефолтна пропозиція — кожне завдання у своєму ворк трі від головної гілки. Але гет шіт дан
> усередині сам нарізає собі ворк трі від віддаленої головної гілки, і коли твоя база з нею не
> збігається, він тихо перемикається на послідовне виконання. Сьогодні обидва варіанти разом не
> працюють. Хто створює ворк трі за замовчуванням, коли обрано гет шіт дан?
>
> A) оркестратор створює, а процес усередині працює послідовно;
> B) процес створює, і оркестратор ворк трі не чіпає взагалі.

**His decision.** Д4 [433]: *«Дефолтна пропозиція, щоби абсолютно все виконувати в різних ворк трі …
щоби це ворк трі був з головної гілки»*, and in the same breath *«якщо людина виборне гіт шдан, то там
є воркспейс, **і з цим треба поєднювати**»*.

**The hole (challenge A2).** «з цим треба поєднювати» is a task, not a decision, and today the two
cannot be reconciled — the answer does not say which side gives way.

**Evidence, VERIFIED by execution today.** Under Claude Code, `gsd-tools dispatch-isolation` returns
`harness-worktree`, which per GSD's own `dispatch-isolation-gate.md` means the host creates and binds
the worktree per agent and **«GSD runs no git»**. GSD's escape hatch `worktree.baseRef:"head"` is
**not read by the host** — GSD says so in its own message. In a real GSD project today,
`gsd-tools worktree base-check` returns `{"shouldDegrade": true, "reason": "head-diverged-from-fork"}`
and `dispatch-should-flatten` returns `true`. Field notes §4.3 is the observed version: GSD computed
`gsd/phase-23-tooling-the-harness-and-the-pre-commit-checkers` from a roadmap slug, one word off the
lane branch, and *«left alone `execute-phase` would cut that name fresh from `origin/master` and lose
the merged master tip»*. A **third** owner now exists that did not then: `claude --worktree`
(VERIFIED in `claude --help`).

**What the answer changes.** A costs GSD's intra-phase parallelism (`workflow.use_worktrees: false`)
and gives the orchestrator one base SHA it can assert. B keeps the parallelism and forces the
orchestrator to stop assuming any base, which removes the `EXPECTED_BASE` assertion from its toolkit.
Preflight refusal on mismatch is buildable either way; which side it refuses is his call.

---

## 3 — blocker — default — What the default is when the forge says nothing is protected

> Ти сказав, що правила репозиторію треба поважати — наприклад, якщо туди можна тільки через пул
> реквест. У твоєму ж claude-plugins на гітхабі технічно не заборонено нічого: захисту гілки немає,
> а правило «тільки через піар» лежить текстом у CLAUDE.md, куди машина не дивиться. Що оркестратор
> має робити за замовчуванням, коли гітхаб каже, що прямий пуш дозволено?
>
> A) все одно тільки через піар, поки ти явно не дозволив прямий пуш;
> B) пушити прямо, бо заборони немає;
> C) читати текстові правила проєкту й підкорятися їм.

**His decision.** R1-12 [331]: *«не порушується правило, якщо, наприклад, в репозиторії якісь інші
правила, або, наприклад, обмеження, що там можна зробити тільки пул реквесту, тощо, так далі, і це
дуже важливо розуміти та приймати»*.

**The hole (challenge A3).** The decision binds the orchestrator to rules and never says where rules
are read from — and on his flagship repo the rule exists in exactly one place a machine will not look.

**Evidence, VERIFIED by me today in `SashaMarchuk/claude-plugins`.**
`gh api repos/:owner/:repo/rulesets` → `[]`; `gh api repos/:owner/:repo/branches/main/protection` →
`404 Branch not protected`. The repo's `CLAUDE.md` states work must be *«shipped via PR (no direct
pushes to `main`)»*. An orchestrator that learns rules from the forge would push straight to `main` of
a repository carrying eleven production plugins, and break no rule it could see. Externally visible,
not cheaply reversible, and under Д11 nothing is printed while it happens.

**Collision worth naming in one clause.** R1-15 [357] puts prohibitions in *«лише одного файлу, який
може доповнюватись, текстописний»* and adds *«Але, так, це максимум»* — and the PR-only rule is not in
that file; it is in `CLAUDE.md`, a file no decision in round 1 names.

**What the answer changes.** A is fail-closed: PR-only is the shipped default and direct push needs an
explicit opt-in per project. B is fail-open and needs no rule reader at all. C adds a config-pinned
prose-file path and the parsing risk that comes with it.

---

## 4 — major — gap — Whether the orchestrator checks its own actions, as distinct from the work

> Перевірка самої роботи належить процесу — це вирішено. Питання вужче: минулого разу команда злиття
> написала «already up to date», не перенесла нічого, і це виглядало як успіх; жоден процес такого не
> ловить, бо це дія самого оркестратора, а не процесу. Чи має оркестратор перевіряти власні дії — що
> злиття справді зрушило головну гілку, що етап, який він мав запустити, справді запустився?
>
> A) так, свої дії перевіряє завжди, незалежно від процесу;
> B) ні, це теж справа процесу;
> C) тільки для потрапляння в головну гілку, решту — ні.

**His decision, taken under the evidence and standing.** The field evidence was put to him first, at
[342]: a truncated suite read as 346 passing and a merge command that reported success and moved
nothing. He answered [344] anyway, and R1-13 stands. This question does not reopen it.

**The hole (research §4.2, Q3; challenge A1's sharper half).** There are two objects. Verifying *the
work* is the process's job — settled. Verifying *the orchestrator's own actions* was never put to him,
and the process cannot attest to an action it did not take.

**Evidence, VERIFIED from field notes §4.1.** *«`git checkout master` aborts when a tracked file is
modified, and one always is: GSD rewrites `.planning/milestone.lock` during every phase and leaves it
dirty. The merge command that followed then ran on the phase branch against itself and printed
`Already up to date` and `Everything up-to-date`. Both read like success.»* It was caught *«only
because the orchestrator checked what `master` actually pointed at after the push rather than trusting
the exit status»*. Field notes §11.4: GSD's verify stage was **silently skipped for phases 14 to 18**,
each `NN-VERIFICATION.md` self-attributing `verified_by: the lane that built the phase`; *«No automated
check caught it; manual review did.»* The check itself costs zero model tokens and works on projects
with no tests at all — VERIFIED against PR #26 today:
`git merge-base --is-ancestor <headRefOid> origin/<base>` plus `gh pr view --json state`.

**What the answer changes.** A adds a small self-audit layer (merge-landed assertion, stage-ran
assertion, base-SHA assertion) that runs on every delivery. B deletes that layer and accepts the §4.1
failure class by design. C scopes it to delivery only.

---

## 5 — major — collision — Who owns the call when the process returns neither pass nor fail

> Процес не завжди каже «добре» або «погано». Гет шіт дан уміє повернути «зроблено, але дві перевірки
> не підтверджені» або «тут потрібна людина». За одним твоїм рішенням вердикт належить процесу — тоді
> оркестратор іде далі й мерджить; за іншим оркестратор може сам поставити хардстоп. Що має статися
> за замовчуванням в автономному рані?
>
> A) довіряти процесу і йти далі, а «потрібна людина» просто записати;
> B) будь-яке «потрібна людина» від процесу зупиняє тікет і чекає на тебе;
> C) мерджити, але лишити тікет відкритим із позначкою «не перевірено».

**The two decisions that collide (challenge A8).** R1-13 [344] gives the verdict to the process.
R1-14 [082]: *«Якщо агент вирішив, що це точно має бути хардстопом, то такі моменти теж можуть бути,
що відбувається хардстоп, і йдеться до людини, навіть якщо це автономний ран. Таке може бути, і агент
сам буде пробувати детермінувати, коли це робити»*.

**Evidence that the middle verdict exists, VERIFIED** in GSD's `references/honest-verifier.md`: a
non-inferable check with no explicit evidence *«abstains → ⚠️ `insufficient_spec`, flagged, →
`human_needed` — **never `passed`**»*, and in autonomous mode *«it produces a prominent `unverified —
held-out test recommended` flag and the completion line reads 'complete with N unverified non-inferable
checks'»*. Both readings of his own decisions are faithful and they produce opposite outcomes for the
same run.

**What the answer changes.** A makes the engine's word final and the orchestrator a pure runner.
B gives the orchestrator a standing veto driven by an engine signal, and needs a declared mapping from
each engine's vocabulary to «потрібна людина». C is a third state the board and the PR body must both
be able to carry.

---

## 6 — major — default — What ships in the box as the notification set

> Ти сказав, що типи сповіщень людина налаштовує сама. Але щось має стояти в коробці на першому рані,
> і цього ти ще не називав. Три ситуації з автономного рану: оркестратор став на питанні і чекає
> відповіді; сам оркестратор впав; злиття пройшло, але нічого не перенесло. Які з них мають одразу
> піти в канал зв'язку, а які можуть просто лежати в статусі, поки ти сам не глянеш?

**His decision.** R1-17 [395]: *«Людина налаштовує, які типи можуть приходити. Чи коли тільки щось
критичне, чи будь-які сповіщення … Чи це сповіщення будуть тільки просто в терміналі. Це не важливо»*
and *«чи треба взагалі канал якогось зв'язку»*.

**The hole (challenge A6; extraction notes, `by-item.md` R1-17 final row).** The substantive half of
R1-17 — what is worth interrupting him for and what waits — was **never answered**; he redirected the
whole item to configuration, and the quiet-hours clause at [394] was asked and never touched.
Configuration still needs a value on first run, and the event taxonomy is the orchestrator's, not his:
«злиття пройшло, але нічого не перенесло» is not a category a first-time user can name in a wizard.

**Evidence that both naive defaults were observed to fail.** Empty default: field notes §4.1, a merge
that printed *«Already up to date»* and moved nothing — a night that produced nothing, discovered in
the morning. Everything-default: field notes §11.6, one unresolved condition re-fired **1085 times**
over about five days.

**Collision worth one clause, not a lecture.** R1-17 makes *no channel at all* legal; Д7 [455] defaults
to *«він залишається та чекає на мої відповіді»*. Together, a run can wait indefinitely for an answer
to a question nobody was told exists — Д6's questions file is a pull surface, and his own expectation
there was live pickup.

**What the answer changes.** The shipped default event list, and whether `notifications: none` stays
legal in combination with settings that can block a run indefinitely.

---

## 7 — major — gap — When the channel check happens, and how often

> Ти сказав, що оркестратор має лише переконатися, що канал зв'язку працює. Не сказано коли: минулого
> разу сторож, який мав тебе повідомляти, тихо вийшов посеред рану, і далі ніхто нікому нічого не
> казав. Коли перевіряти канал?
>
> A) один раз на старті рану, і все;
> B) на старті й далі регулярно, а якщо відвалився — просто записати це в статус;
> C) на старті й далі регулярно, і якщо відвалився — зупинити ран.

**His decision.** R1-17 [395]: *«Та повинен **лише** переконатися, що це працює»*.

**The hole (challenge A5).** The word *лише* caps the duty at a point in time and the answer names no
point. Preflight-only is the natural reading and it is the one that fails.

**Evidence, VERIFIED.** Field notes §11.6: the human-notification watchdog *«had already exited ('run
finished') and was never restarted»* while the run was still looping, with `context-watch.log:5620`
reading literally **`NO ONE IS BEING TOLD`**; the loop ended only when an external `SIGTERM` arrived.
And `grep -rl 'telegram|slack|notify|notification' plugins/harness/` matches only `docs/DESIGN.md` and
`docs/FIELD-NOTES.md` — the previous plugin contained **no notification code at all**, so the watchdog
that died was a project-side script the plugin never owned.

**A second, smaller thing this answer settles.** «працює» has three provable levels and only two are
reachable: credential valid (`getMe` / `auth.test`), service accepted (`message_id` / `ts`), human
acknowledged. VERIFIED from the Telegram Bot API: `getMe` *«proves the bot's capabilities and
configuration, not operational status»*, and the Bot API documents **no read receipts for bot-sent
messages**; Slack has none either (CLAIMED). So «verified» can never honestly mean «he saw it» without
an explicit acknowledgement he performs.

**What the answer changes.** A needs no liveness machinery. B adds a periodic re-check and an attention
item. C makes a dead channel a run-stopping condition, which is the only option under which a silent
orchestrator cannot outlive its ability to reach him.

---

## 8 — major — collision — What the continuous stack check is allowed to DO

> Ти сказав, що оркестратор має постійно переконуватись, що потрібні енвайрмент верібли й запущений
> стек на місці. І ти ж сказав, що він не має чіпати те, що не він запускав. Минулого разу твій докер
> контейнер вбило по пам'яті посеред рану — він був твій, не оркестратора. Що оркестратор має зробити
> в цю секунду?
>
> A) підняти стек сам;
> B) притримати тікет і чекати на тебе;
> C) повідомити тебе і йти далі по інших тікетах;
> D) підіймати тільки те, що підіймав сам, а чуже — лише повідомити.

**His decisions.** Д4 [433]: *«І **постійно переконуватись**, що всі ті енвайрмент верібли, які
потрібні, вони запущені відповідно … або що є **якісь запущений стек**»*. R1-16 [370]: *«якщо,
наприклад, в тій самій папці я паралельно працюю над чимось, це не запускав оркестратор, це роблю я,
він цього не має зупиняти»*. Д3 [430] scopes teardown to *«якщо він це сам підняв»*.

**The hole (challenge A7).** He asked for a detector, and every action it could take is closed off by a
different decision of his: restarting his container violates R1-16; holding the lane is invisible under
R1-17-with-no-channel; escalating to the process is meaningless because the process knows nothing about
his Docker stack.

**Evidence, VERIFIED from field notes §11.5.** `<work-project>-app-1` was `OOMKilled` (exit 137) at
`2026-09-13T03:29:01Z` while the `v-phase-21` validator ran two `docker compose up --build` at once;
*«Detected only by correlating timestamps with `docker inspect OOMKilled=true` — there was no live
alert»*. The same section records his default stack destroyed by a `docker compose down -v` with **no
`COMPOSE_PROJECT_NAME` exported**, and *«the actor was never identified»*. A continuously-running
environment repairer is a new actor of exactly that class.

**What the answer changes.** A and D make the orchestrator an actor that runs `docker compose up`
unattended, which needs its own bounded command list. B and C make it a pure reporter, and then the
frequency of «постійно» only sets how fast a lane stalls.

---

## 9 — major — ratify — The output decision was never confirmed, and «minimum» has no unit

> Останнє, що ти сказав про вивід: за замовчуванням мінімум виводу й мінімум витрат на нього, але
> людина може переналаштувати. Підтвердити вголос ти не встиг — сесія пішла далі. Підтверджуєш це як
> остаточне, і чи означає «мінімум витрат», що команда статусу має бути звичайним скриптом, який
> взагалі не піднімає модель?

**His words.** [508]: *«Ні, оркестратор не повинен нічого виводити для мене … якщо я хочу отримати
статус виконання, то я можу запустити окремий термінал, прописати orchestrator двокрапка статус»*,
softened at [512]/[514] to *«Дефолтний варіант, що оркестратор використовує мінімальну кількість
аутпуту і стокінгів для цього»* … *«Але людина може це переналаштовувати»*.

**Why it is unratified (challenge A11; `corrections.md`:104).** The interviewer asked *«Це остаточний
варіант, підтверджуєш?»* at [515]/[516] and the next line is Д12. His own rule [003] —
*«Пізніше сказане перемагає раніше сказане»* — makes the softened version binding, but the two versions
imply different architectures: «нічого не виводити» permits a tick loop with no model in it at all,
«мінімальну кількість» leaves a model in the loop at an unspecified rate.

**Evidence that the product already violates the intent undetectably, VERIFIED today.**
`plugins/harness/commands/status.md` reads in full: *«Invoke the `harness:harness` skill via the Skill
tool, passing `--status $ARGUMENTS` through verbatim.»* So asking for status **spends a model turn** —
while `harness-run.sh do_status --json` underneath it is pure bash + jq, its own comment reading
*«machine-readable health for a cron/notifier babysitter: exit 0 healthy, exit 1 when the run needs a
human. No terminal/network required beyond the limits verdict»*. The zero-cost path exists and the
command in front of it does not use it. Under the decision as worded, nobody can say that is wrong.

**Note for the interviewer, not for him.** «стокінгів» at [512] is an unresolved transcription
(`meta.md` open thread 5); the interviewer read it as «токенів» at [515] and he did not object. The
question above is phrased so his answer settles the requirement either way — do **not** ask him to
define the word.

**What the answer changes.** Whether a model may appear in the status path at all, and therefore
whether `orchestrator:status` is a shell script or a skill.

---

## 10 — major — feasibility — Stacked піари are named as a capability the machine cannot support today

> Ти сказав, що оркестратор може користуватися можливістю гіта стакати піари. На твоїй машині гіт
> версії 2.33 — він не вміє тримати стек, коли нижній піар доводиться переробляти, і жодного окремого
> інструмента для стека не встановлено. Тобто верхні піари поїдуть. Що робити?
>
> A) вимагати новішого гіта на старті рану, інакше не стартувати;
> B) стакати тільки коли ти прямо попросив у тікеті, а інакше кожен тікет окремим піаром від головної
>    гілки;
> C) не стакати автоматично ніколи.

**His decision.** R1-12 [331]: *«оркестратор має за можливості гіта, а саме те, що там можна піари
стакати, і він це теж може використовувати»*.

**The hole (challenge A9).** A capability is granted and nothing says what it requires, when it
applies, or what happens when the requirement is missing.

**Evidence, VERIFIED on his machine today.** `git --version` → **2.33.0**, so `--update-refs` /
`rebase.updateRefs` (Git 2.38+) does not exist here; `which gt spr ghstack git-spr` → none installed;
GitHub's own `gh-stack` extension is in private preview (CLAIMED, 2026-04) and too early to depend on.
The zero-dependency fallback that does work here is `git config branch.<name>.gh-merge-base <parent>`,
which `gh pr create` reads automatically (VERIFIED from `gh pr create --help`, gh 2.92.0) — it builds a
stack but does not maintain one through a rebase. Failure shape without it: `t-17 → t-18 → t-19`, a
forced change on `t-17`, and `gh pr merge` on `t-18` re-applying superseded commits — nothing prints
(Д11), no process verifies merge topology (R1-13), and field notes §4.1 establishes that a merge which
achieved nothing *«reads like success»*.

**Eligibility, the second undefined half.** R1-05 [160] has dependency information —
*«якщо якісь завдання не може виконуватися, тому що не виконалось одне з попередніх, то його ми не
можемо взяти»* — and nothing links it to stacking. Option B is the one that makes eligibility his call
rather than the implementer's; that is why it is offered, not recommended.

**What the answer changes.** A adds a hard preflight requirement on his machine. B and C make stacking
opt-in and let the orchestrator ship without any stack-maintenance code.

---

## Considered and not asked this round

- **The addressing scheme for `оркестратор:статус`** (challenge A10, minor). VERIFIED in the previous
  generation: `hproject_root()` resolves from `$HARNESS_PROJECT` or by walking up from cwd, and
  `hcurrent_run()` returns rc 2 when more than one non-`STOPPED` run exists — while Д4's default puts
  every task in its own ворк трі, so the natural place to stand is the wrong one. Real, but it does not
  fork the architecture: an implementer can ship `--run <name>` plus a machine-wide registry and be
  right under every answer he could give. Ask only if a slot frees up.
- **The file format and home of a custom process** (research Q7). He hedged YAML himself in the same
  breath — *«Можливо, не так, тут треба буде подумати, як саме»* [118] — so there is no decision to
  attack, and Д1 [416] already routes config placement to the the owner's company marketplace
  architecture he built. Asking risks re-asking something he considers answered.
- **His unfinished sentence at [334]** — *«Також дуже …»*, over which the interviewer's restatement ran
  (`corrections.md`:136). A point he flagged as very important about reaching the trunk was never made.
  Worth recovering, but it is an open prompt rather than a named hole, and questions 3, 4 and 10 already
  cover the trunk surface. Best used as an opener or a closer for the trunk block, not as one of the ten.
- **Quiet hours** (asked at [394], never answered). Deliberately dropped: attacking their absence
  attacks the night frame he voided at [054].
- **"He should not allow a process with no checks"** — that would substitute a preference for a
  decision he took with the field evidence in front of him [342]/[344]. Question 1 attacks the
  *completion* gap instead, which he was never asked about.
