# GAP-MAP — the single map round 2 is built from

**Date:** 2026-09-21 · **Topic:** harness → orchestrator rebuild · **Round 1 source of truth:**
`round-1/TRANSCRIPT-01.md` (rows `[NNN]`), analysed in `round-1/ANALYSIS-01.md`.

**Inputs consolidated here.** The four extraction passes (`research/extract/{by-item,corrections,
meta,outside-list}.md`), the nine clusters (`research/clusters/C1–C9 × {research,challenge,
questions}.md` — 108 attacks, 90 candidate questions), the fifteen platform profiles and fifteen
spikes plus `research/platforms/ADAPTER-CONTRACT.md`, the two commissioned option papers
(`research/options/{RUN-MODES,BOUNDARIES}-OPTIONS.md`), and `plugins/harness/docs/FIELD-NOTES.md`.

**Evidence grades used throughout.** **VERIFIED** — read in the transcript, in source, in vendor
docs, or executed on this machine. **CLAIMED** — a third party asserts it and nobody ran it.
**INFERRED** — reasoning from verified parts, labelled as such.

**The rule this document obeys.** His words are the source of truth. Nothing below overwrites a
decision he made. Where a challenge collides with his own words, both sides are quoted verbatim with
their `[row]` anchor, and the collision is named — never resolved for him.

---

## 1. What round 1 actually settled

Decisions safe to build on, one line each. **⚠ LOOKS SETTLED** marks anything `ANALYSIS-01.md`
files as SETTLED that the owner never confirmed with a «так», or that he later narrowed, downgraded
or retracted. The ratification audit behind every ⚠ is `extract/corrections.md` §C and
`extract/by-item.md`'s final section — a mechanical pass over all 48 «Підтверджуєш?» restatements.
**26 got an explicit yes. 22 did not.** `ANALYSIS-01.md` defines an `UNRATIFIED` label and uses it
exactly once (Д12).

### Identity and scope

- **The name is orchestrator, not harness.** «Оце от харнес, ми його будемо переназивати на
  оркестратор» [118]. Not a mid-session change: he used «оркестратор» in his first sentence [007],
  six days earlier, and policed his own slip at [133].
- **Not a coding tool.** «може використовуватись зовсім навіть не для написання коду … може таке
  бути, що десь не буде тестів, і це також окей» [344]. No repo, no tests, no build may be assumed.
- **Agnostic to the work content**, stated on day one: «це вже неважливо, воно повинно бути
  агностичним» [007].
- **Everything configurable is mandatory, multi-provider is mandatory** — his own one-sentence
  summary of the whole session: «це повинно все налаштовуватись, і це дуже важливо та обов'язково.
  Воно має працювати для різних провайдерів» [408].
- **Simplicity is a hard constraint, stated four times:** «тут нічого надприроднього не потрібно
  вигадувати» [171] · «це має бути дуже простий процес» [189] · «це має бути надійна річ, дуже
  проста» [300] · «я не хочу якихось детерміністського варіанту … дуже складний оверінжиринг» [370].
- **The night frame is void.** «я б взагалі навіть не фокусувався на тому, що там щось вночі працює
  … це треба просто трошки правильніше розділити, як автономний ран та... контрольований» [054].
  Round 2 must not reintroduce «вночі».

### Process and work source

- **The orchestrator runs the user's configured process — one, never mixed.** «або комбінувати але,
  ні, комбінувати ні, тут або або, або свій, або вже готовий» [118]. GSD, Superpowers, another
  marketplace's tooling, or a fully custom step list. Confirmed [123].
- **Format for a custom process is open,** not YAML: «Можливо, не так, тут треба буде подумати, як
  саме» [118].
- **Two work sources, for now:** a local kanban-shaped registry in the project, or a connected board
  («GitHub Issues, або ClickUp, або будь-яка інша тула»), access verified [129]. Confirmed [133].
  «Конкретно поки тільки два режими» is an explicit, temporary scope.
- **GitHub Issues is a hedged first recommendation** («і напевно в цьому перевага» [129]) — not a
  decision. The stated reason is project-locality, and that reason is the criterion for any other board.
- **The board is a working surface, not a queue:** «дошка, яка буде помічником для цього
  оркестратора, щоби ставити статуси таскам, залишати якісь коментарі» [149]. Confirmed [149]/[152].
- **Readiness is by a defined structure that does not yet exist.** «AI ready» is an example only;
  «це треба буде, щоби придумав якусь структуру, і її притримувався» [145]. Handed forward.
- **Config lifecycle:** a separate `config` command or configuration at first run; on a run, read
  global + project settings, ask only for what is missing [133]. He flags it as already-built
  architecture, not new design. ⚠ **LOOKS SETTLED** — [134]/[137] → [138] «А повтори, будь ласка,
  попереднє питання», and the restatement was never re-put.
- ⚠ **Board minimum-status check** [153] — restated [154]/[155], interviewer moved to Р1-05 at [156]
  with nothing from him in between.

### Run modes and authority

- **Two modes exist and came from him, unprompted** [054]. Controlled: «якщо є якісь сумніви … вони
  йдуть зразу до мене і ставлять умовного хардстоп … це на паузі, поки людина не відпустить» [062].
  Autonomous: «агент не впевнений на сто в цьому варіанті, то він його може обрати. Але потім він
  прозвітовує» [062]. Confirmed [068].
- ⚠ **He is not sure the two modes differ at all:** «Не знаю, чи вони будуть відрізнятися» [058].
  The definitions are **OPEN by his own instruction** [082] — this is I2.
- **Mode selection has three config values** — ask every run / always autonomous / always controlled
  — **overridable per run** [075]. Confirmed [080].
- **Whether the agent may decide at all is a setting; the basis is a second setting** [087]/[092],
  confirmed [101]. Four bases named: written rules + past examples, previous answers to similar
  questions, a tone of voice **in the repository**, the agent's own project knowledge.
- **Tone of voice may answer almost in his place:** «майже замість неї може відповідати … це повністю
  окей» [092].
- ⚠ **The agent may force a hard stop even in an autonomous run** [082] — the restatement carrying it
  ([085]/[086]) got a new condition instead of a «так» [087]. The confirmed restatement [094]→[101]
  covers only the *basis*. `ANALYSIS-01.md` files it SETTLED. **This is the only unbounded authority
  in the design.**
- **A wrong autonomous decision must change future behaviour:** «якщо це не підходить, то треба
  вчити, відповідні дії» [062]. **Absent from `ANALYSIS-01.md` entirely.** No actor, no artefact,
  no moment.

### Capacity, providers, accounts

- **Exhausted limit → wait for the reset, then continue** [007]/[034–036]. Confirmed [036].
- **No binding to Claude's windows:** «Що якщо раптом буде не п'ятигодинне вікно, а десяти годинне
  вікно, або його взагалі не буде? … можливо це буде взагалі pay-as-you-go» [007].
- **Hitting the wall is acceptable *because* state is recorded:** «в нас в реєстрі має записуватись
  кожен стан, його виконання … для того, щоби було відновити процес і продовжити, навіть руками» [171].
  He also flags the risk himself: «Тобто, це складно заменеджити» [171].
- ⚠ **The three stop modes (hard / soft / intermediate)** [171] — restated [176]/[177], he said
  «Повтори, будь ласка» [178], it repeated [179]/[180], and [181] moved on. **The entire hard/soft
  vocabulary that R1-07, R1-08 and Д12 all reuse is unratified.**
- **Three-way accounting rule:** reference the chosen process's records / keep own / reference-plus-
  delta [171]. Confirmed [189]. For GSD a reference may suffice — self-flagged: «Я можу помилятись».
- **Provider = platform, several accounts each** [041]. Confirmed [047].
- **Manual per-role provider assignment is enough initially** [036] — explicitly a v1 concession
  («На початку»), not the end state.
- **The three-role model is his, stated three times and never recorded as a finding:**
  «на кого буде працювати оркестратор, на кого буде працювати скажімо, контекст фочер, на кому
  екзек'ютор буде» [036] · [195] · «три вікна, перше, це контекст вочер, друге, це оркестратор, третє,
  це екзек'ютор» [204].
- **Accounts may be restricted to named roles** — «тільки для оркестратора … тільки для екзек'ютора …
  І це важливий дуже нюанс» [270]. Confirmed [279]. One of only two confirmed sentences in C6.
- **Assignments live in one polled file, changes carry a type (soft/hard)** [195]. Confirmed [199].
- ⚠ **Per-platform account-switch explanation + pre-run verification** [199]/[200]/[201] → [202] went
  straight to R1-08. Unratified.
- **His concrete numbers, absent from `ANALYSIS-01.md`:** 60 % weekly / 5 % five-hour = still safe to
  start; **80 % weekly** as the example threshold — used for *both* soft and hard in adjacent
  sentences [171]. Three identical failures [442] is the only hard number in the interview.

### Context

- **Percentage threshold, user-set, per role and per provider; soft = at the step boundary, hard =
  now; compact or start a wholly new orchestrator; the command and any post-compact prompt are
  configurable** [204]. Only **one** sentence in this whole cluster carries a «так»: [212], covering
  the soft-mode step boundary alone [209].
- **«повинен бути механізм, який гарантовано робить цю дію»** [204] is his own wording and his
  strongest verb in the session — but the *requirement as formulated* sits on a restatement he never
  answered ([220]/[224] → R1-09).
- ⚠ **Thresholds / hard mode / compact-or-new-session / post-compact prompt** — [213]/[217] → the
  interviewer declared **«Підтвердив, зафіксував»** [218] with nothing from him in between.

### Liveness and recovery

- **No timeout ladder — the orchestrator judges.** «Агент сам повинен це вирішувати … він дивиться,
  перевіряє ті сесії, які він запустив, які в них прогрес, що вони там зробили» [231].
  ⚠ Recorded over a half-finished sentence: «Гаразд, зафіксував» [238].
- **Single-orchestrator invariant** [300]: «не може бути такого, що вже якісь існуючі оркестратор і
  спускається наступний, тому що тоді це буде просто нескінченний цикл оркестраторів … Це треба
  відслідковувати і не дозволяти» [301]. **Confirmed «Та, правильно» [304]** — one of only two
  confirmed sentences in C6, and the hardest rule in the interview.
- **«Запускати спочатку» = restart the orchestrator, not redo the work** [300]. Confirmed.
- **Prove the old one failed, then spawn** [300].
- **Recovery default = state files; extras = previous sessions and transcripts; per-platform
  configurable; the user may write their own recovery skills** [293]/[310]/[312].
  ⚠ Both closed by the interviewer's own «Підвів до запису» [309] and «Зафіксував» [318].
- ⚠ **Health check + provider fallbacks** [246]/[255]: he **actively downgraded this** — «Це не як
  правило, це лише просто пояснення» [258] — and the interviewer withdrew its own confirmation
  attempt: «Я передчасно перейшов до підтвердження» [268]. Never re-put. `ANALYSIS-01.md` records it
  as a SETTLED requirement. **This is the largest single mis-label in the analysis.**
- **His one concrete liveness mechanism, dropped by the analysis:** «перевіряти стан останнього
  запису» [249] — cut off three times [249]/[251]/[253] and never completed.
- **Recovery must need no user involvement:** «без участі в налаштуваннях користувача» [266].
- ⚠ **Д10, restart with live executors** [497] — [500]/[501] → [503] rolled into Д11. Unratified.
  «в межах дозволених повноважень» is the interviewer's gloss, not his.

### Session runtime, delivery, boundaries

- **Visibility is per-platform configuration, four modes,** including his own invention «переважно
  інтерактивні і тільки інколи headless»; headless allowed **with his own warning** «з цим треба бути
  дуже обережним» [324]. Confirmed [328].
- **The orchestrator may answer a child session's AskUserQuestion** — «і це повністю і повністю окей»
  [324], doubled. ⚠ The qualifier «в межах налаштованих повноважень» in the record is the
  **interviewer's** [325]/[327], not his.
- **No universal merge gate:** «не має конкретного обмеження, як це саме повинно працювати» [334].
  Autonomous or mandatory handoff is a setting; repository rules bind and he flags this «дуже
  важливо»; PR stacking is named as a capability to use; settings follow GSD's flow [331].
  Confirmed [336].
- **Verification belongs to the configured process. The orchestrator imposes no checks of its own**
  [344]. Confirmed [348]. **Taken under the evidence** — the field failures were read to him at [342]
  and did not move him. Do not reopen it.
- ⚠ **The red line:** one appendable text file, in «якісь визначене місце», mandatory reading by all,
  «різного типу обмеження», no enforcement procedure, «Але, так, це максимум» [357]. **Never
  confirmed** — [358]/[359] → [360]; his own last words were a question back: «Чи це є відповідно до
  твоєго питання» [357], which the interviewer answered for itself. `extract/corrections.md` calls it
  *"the weakest-grounded answer in the interview"*.
- **Boundaries, PARTIAL by design.** Two cases [370]: another project/folder, and his own parallel
  work in the same folder. He proposed a mechanism — «в оркестратори прописаний шлях, до чого він має
  доступ» [366] — and rejected config for it: «Я би не сказав, я би це робив якось абстрактно» [373].
  Redirected to a Fable agent [378]; **only the deferral was confirmed** [383].
- ⚠ **Notifications** [395] — user configures the channel (Telegram, Slack, Gmail, a phone call,
  terminal-only, or **none at all**); the orchestrator's only duty is to verify it works.
  [396]/[397] → [398] went straight to R1-18. Unratified — and the substantive half of R1-17 (*what
  is worth waking him for*) was never answered.
- ⚠ **R1-18, build-your-own:** «превентивно я буду обирати свій варіант» [403] — the bar for adopting
  a third-party tool is «працює краще, ніж мій **у всіх аспектах**», which as stated is unmeetable.
  The interviewer declared «Р1-18 підтверджено» [406]; he never said so.

### The Д-series (raised at his own request [408])

- ⚠ **Д1 config precedence** → his the company Claude marketplace [416]. Unratified; he named no repo.
- **Д2 mid-run intake:** ready work added during a run is picked up [422]. Confirmed [426].
  The description-sufficiency / `needs review` process is **OPEN** («Точно не знаю» twice).
- **Д3 end of run:** finish, and stop what it started — his list begins with «свої якісь там
  оркестратори», then containers, then services — «щоби не залишати хвостів» [430]. Confirmed [433].
- ⚠ **Д4 worktrees:** configurable, reconciled with GSD's workspaces, **default = absolutely
  everything in its own worktree off the main branch**, with env vars and a running stack
  **continuously** verified [433]. The interviewer declared «Прийнято, зафіксував» [437].
- **Д5 repeated failure:** three identical failures → notify+stop or just stop; «В який момент не
  знаю» [442]. Confirmed [445].
- ⚠ **Д6 questions channel:** independent tasks continue; one user-placed channel carrying questions,
  clarifications, confirmations **and review of finished work**, watched live [449]. Unratified —
  but it is the **only pattern in the session he had already built and run by hand** («в мене так
  було, коли я … працював з гарнесом» [449]), which should outweigh its label.
- ⚠ **Д7 only-blocked-work-left:** default stay and wait; a mid-run override beats both the run's
  choice and the default, «і це дуже важливо» [458]. Unratified — [460]/[462] → [463].
- **Д8 mid-flight ticket change:** watch the active task's source, configurable cheap model, silent
  when unchanged, report the diff when changed [466]. Confirmed — **but scoped**: «На те, що ти перше
  сказав, так, я підтверджую, потім після того ти повторив питання п'ять чи шість разів» [475]
  confirms the **first** restatement only. Two of his own fragments were talked over and lost:
  «Тобто, може бути момент» [468], «з ... підстави чогось в моменті» [471].
- **Д9 contradicting change:** prefer a new ticket for finished work; mid-execution the orchestrator
  chooses among three; the whole case is configurable [482]. Confirmed [486].
- ⚠ **Д10** [497], ⚠ **Д11** [508]→[512]/[514] (the *corrected* «мінімальний вивід» version is the
  binding one by his own last-said-wins rule [003], and it is unratified), ⚠ **Д12** [520]/[524] —
  three stop commands, `stop-custom` reading his own «текстописні правила чи команди», applied on the
  next tick of the polled file. The interviewer itself left Д12 open [525].

---

## 2. Corrections to `ANALYSIS-01.md`

### 2.1 The label problem (the big one)

`ANALYSIS-01.md` defines **SETTLED = "owner confirmed a restatement"** and then applies it to
restatements he never confirmed. Mechanical count over every «Підтверджуєш?» and the next `ME:` row:
**22 of 48 got no yes.** In **6** of those the interviewer announced its own confirmation —
«Підтвердив, зафіксував» [218], «Гаразд, зафіксував» [238], «Підвів до запису» [309], «Зафіксував»
[318], «Р1-18 підтверджено» [406], «Прийнято, зафіксував» [437]. The fifteen blocks are listed in
`extract/meta.md` §G1. **Eleven of the eighteen R1 items and six of the twelve Д items carry at least
one sub-part he never ratified.** Nothing in §1 above changes a decision; it changes the **confidence
grade** on 22 of them.

### 2.2 Outright mis-statements

| Where | `ANALYSIS-01.md` says | The transcript says |
|---|---|---|
| R1-10, health check | "fallbacks to other providers **must exist** … [255, 266]", SETTLED | He refused that reading: «Це не як правило, це лише просто пояснення про те, що оркестратор, він по факту і є для того, щоби вирішувати ці питання» [258], then «Так, дослухай мене, будь ласка, до кінця» [266]; the interviewer withdrew: «Я передчасно перейшов до підтвердження» [268]. Never re-put. **Should be UNRATIFIED and partly disowned.** |
| R1-07, change detection | "(mtime **named as the mechanism**)" | A hedge: «**Можливо**, там, **наприклад**, по даті, перевіряти, коли він був змінний, або ще так далі» [195]. Measured here: `stat -f '%m'`, `date -r` and `find -newer` **miss two writes in the same second**; a rewrite with identical content **moves** mtime. The mechanism is open, not chosen. |
| Д1 | "(That is `<baseline-marketplace>`: six config slots, three levels, personal beats committed.)" — inline, under a SETTLED label | He named **no repository and no rules**: «клад маркетплейс, який я робив для <company> … там є відповіді на ці питання» [416]. The identification is correct (VERIFIED at `<baseline-marketplace>/docs/config-levels.md`) but it is **INFERRED and must be labelled**, and it **omits the `never` veto key** — the closest existing analogue to R1-15's prohibition file. |
| Headline | "The name changed: harness → orchestrator [118]" | He said «оркестратор» in his **first sentence** [007], six days earlier, and self-corrected a slip at [133]. [118] ratified existing usage. Decision same, provenance wrong. |
| R1-11 | "within configured authority [325]" | «в межах налаштованих повноважень» is the **interviewer's** phrasing [325]/[327]. His own answer attaches **no condition** and doubles «повністю і повністю окей» [324]. |
| Mechanics | "repeated the question … the owner called out **three times**" | **15** duplication instances, **8** call-outs ([340], [351], [386]/[387], [400], [426], [466], [475], [505]), **2** with profanity. Plus a separate interruption complaint, «Так, дослухай мене, будь ласка, до кінця» [266]. |
| Mechanics | "The interviewer **twice** mislabelled an item [188, 190]" | Once ([188]) plus its self-correction ([190]). Separately: [188] **invented a question that was not on the list**, and he answered it at [189] — so that answer is an answer to an unapproved question. |
| Mechanics | cites [275]–[278] as a restatement landing on half an answer | That one ended in a real «Підтверджую» [279]. The content is legitimately settled; the example is wrong. |
| R1-09, R1-15 | "see challenges" (lines 125 and 188) | **There is no challenges section in the file.** The two sharpest tensions the analyst identified were flagged and never delivered. |

### 2.3 Questions that were never asked, and halves that were dropped

- **R1-06's second half** — «Чи можна витрачати ліміт до нуля, чи треба лишати запас на твою власну
  роботу?» — was never put to him ([169]/[170] asked only the first half). **There is no answer
  anywhere in the transcript.** R1-06 is filed "SETTLED in four parts". This is the hole that lets an
  unattended run eat the subscription he needs in the morning.
- **R1-14's third clause** — «І що має статися із задачею, поки вона чекає на твою відповідь?» —
  never asked. Answered only obliquely five items later by Д6 [449], for the *queue*, not the task.
  And **R1-14 was never asked as a question at all**: every record ([074], [078], [085], [094]) is a
  restatement of material he volunteered while answering R1-01.
- **R1-01's "where" half** — «і де саме лежати» — unanswered.
- **R1-17's substantive half** — what is worth waking him for — unanswered; he redirected the whole
  item to configuration. The quiet-hours clause was asked at [394] and never touched.
- **The night frame was silently dropped from three items** — R1-02 asked as «віддавати на автономне
  виконання» [105], R1-12 as «робота» [329], R1-17 as «Що під час автономної роботи» [384]. Permitted
  by his brief and consistent with [054], but it is a scope change across three items that nothing
  records.

### 2.4 Content present in the transcript and absent from the analysis

- **The learning loop** — «якщо це не підходить, то треба вчити, відповідні дії» [062]. The only
  place in the entire session where feedback changes future behaviour, and the missing half of «він
  прозвітовує». Absent.
- **The three-role model** — orchestrator / context watcher / executor — stated at [036], [195] and
  [204], the last time as three concrete terminal windows with per-window thresholds. It diverges
  from the shipped four-role model (`orchestrator`, `worker`, `validator`, `question`, plus a separate
  context watch — VERIFIED, `harness-spawn.sh:42-49`). Absent as a finding.
- **The simplicity constraint** stated four times ([171], [189], [300], [370]) — only the last is
  recorded, and only as a local remark on R1-16.
- **His concrete numbers** — 60 % weekly / 5 % five-hour as "safe to start", 80 % weekly as the
  example threshold [171]. Absent.
- **«Але, так, це максимум»** [357] — dropped. It is currently the load-bearing constraint on the
  whole safety design, and it is ambiguous (see §3, C-13).
- **«різного типу обмеження»** [357] — flattened to "one text file". Typed restrictions is a design
  hook that was dropped.
- **«Має бути якісь визначене місце»** [357] — the path is part of the contract.
- **Д3's teardown list begins with «свої якісь там оркестратори»** [430]; the analysis lists only
  sessions, containers and services.
- **Д4's «постійно»** and **«якісь запущений стек»** [433] — compressed to "necessary services",
  losing both the continuity and the running-stack requirement.
- **Д6's provenance** — «в мене так було, коли я робив, працював з гарнесом» [449]. The **only**
  "this already worked for me" data point in the session, and it should outweigh untested ideas.
  With it, a latency expectation: «в лайв режимі я міг це прийти і це переглянути, і я розумів, що це
  скоро потрапить в оркестратор» [449].
- **«це має бути оркестратор для всього»** [182] — the scope stated at its widest.
- **His permission to be contradicted** — «я ну все вірю, але воно може не сходитися з дійсністю»
  [182]. Recorded as instruction I1 without the permission framing, which is the most load-bearing
  clause in it.
- **His own one-sentence summary** [408], never cited.
- **I4's corrected intent** [409] — he does **not** want answers from the process; he wants to *tell*,
  have it recorded, and have it shape the build. The analysis keeps only the superseded version.
- **The opening monologue is paused, not finished** [009]/[031] — he never resumed it. Round 2 must
  reopen it, after the recap he needed at [019] following the six-day gap.
- **Unresolved transcription that must not be guessed:** «[profile switcher]» [199] = **a profile switcher** (VERIFIED on this
  machine); «медпоколка» [118] ≈ marketplace, stated with «наприклад»; «нетворк 3»
  [366] — **unresolved**, plausibly Docker networks or worktrees; «стокінгів» [512] — the interviewer
  read it as «токенів» [515] and he never confirmed that reading.

---

## 3. Collisions — pairs of his own decisions that cannot both hold

Each row: both quotes, and the concrete case where they meet.

**C-01 · What a hard stop holds.**
«типу робо каже, що це **на паузі, поки людина не відпустить**, якщо це контрольований ран» [062]
× «Та, можем **продовжувати незалежні завдання**» Д6 [449].
*Case:* 23:10, ticket 3 of 19, a worker doubts the auth library. Implementer A holds the run — at
09:00 he has one answered question and 16 untouched tickets, ten hours gone (measured throughput on
the last real run: about one phase an hour for phases 10–14, FIELD-NOTES §9.5). Implementer B holds
only the ticket — eleven phases merge overnight against an auth answer he reverses at 09:00. A third
sub-case nobody covered: a hard stop raised by a *worker* — does it stop the worker, the lane, or
reach the orchestrator at all?

**C-02 · «Софт» means three different boundaries.**
«чи це софт, що це треба буде **наступні завдання перенести**» R1-07 [195] — *the run carries on*
× «м'яка **дозволяє йому завершитися, але не запускає нових**» R1-06 [176] — *the run drains and ends*
× «**Лише поточного кроку**» R1-08 [209] — *and the step itself is configurable*.
*Case:* 01:40, he writes `executor.account = work-2, type = soft` meaning [195]. The implementer
built [176]. At 01:55 the last task finishes, nothing starts, the report says "soft stop applied at
01:55 as requested", and he wakes at 07:00 to 31 untouched tickets. Nothing is wrong with the
software; the word did two jobs. **And the restatement that would have reconciled them was never
ratified** ([176]–[181]).

**C-03 · «Хард» means stop vs switch.**
«це означає **хардстоп**, що потрібно зупинити завдання прямо вже та й все» [171]
× «чи це хард, чи це треба **прямо вже зробити і зупинити**» [195] — where «зупинити» is the *means*,
not the end.
*Case:* 04:10, he edits the assignment file from his phone to move the executors off an account he
needs for a morning demo, and writes `hard`. Implementer A halts the run. Implementer B kills three
executors mid-turn and respawns them. Neither is wrong by his words.

**C-04 · A fresh orchestrator is not a death.**
«оркестратор можна як компактити, так і **запускати повністю новий оркестратор**» [204]
× «якщо… воно не спрацювало, **переконуєш що воно не спрацювало, а після того запускаєш новий** …
якщо раптом одночасно два якісь оркестратори працюють, то це не окей» [300] · «Це треба
відслідковувати і **не дозволяти**» [301].
*Case:* 04:00, the orchestrator is at 82 % context. It has **not** failed — it is healthy, busy and
merely full — so [300]'s precondition can never be satisfied and [301] forbids the spawn. The close
also refuses: VERIFIED in `WATCHER-PROMPT.md` 113–124, *"proved not to work rather than assumed …
tried twice on 2026-09-02; both times the handoff was written and the replacement failed."* **Both
exits are closed by his own rules and no rung below them is defined.**

**C-05 · The orchestrator cannot compact itself.**
«компакт, **який буде робити оркестратор**» [204] × the same answer names the orchestrator as the
*subject*: «якщо, наприклад, **оркестратор наблизився до того числа**» [204], and [195] leaves the
actor open («оркестратор **чи** контекст вочер»).
*Case:* VERIFIED, FIELD-NOTES §1.1 — *"A model has no way to put text on its own input line"*, and
§1.2 — `/compact` lands only when the target has no shell running, while the only way a session types
into its own tty **is** a shell. The session reads its own threshold, agrees, has no verb, writes
about it (consuming context), and re-checks. FIELD-NOTES §11.6 is that shape at 85 minutes, ended
only by an external `SIGTERM`, log line 5620: `NO ONE IS BEING TOLD`.

**C-06 · The orchestrator answers the doubt the controlled mode exists to escalate.**
«якщо він раптом використовує ask user question, то оркестратор може відповідати на ці питання, і це
**повністю і повністю окей**» [324] × «якщо є якісь сумніви, то коли контрольований, то вони **йдуть
зразу до мене**» [062].
*Case:* 03:40, controlled run. A worker asks *"the migration drops `users.legacy_id` — proceed or
backfill?"*. The orchestrator is a configured answerer, so it answers. No hard stop, no notification,
nothing pauses; at 09:00 the column is gone and merged. **His rule never fired because the doubt was
consumed one layer below where the rule lives.**

**C-07 · The board is both the surface written to and the thing watched.**
«дошка, яка буде помічником … щоби **ставити статуси таскам, залишати якісь коментарі**» [149]
× «якщо нічого не змінилось, то цей агент просто, типу, **нічого назад не поверне**» [466].
*Case:* VERIFIED on GitHub, `issue.updated_at` equals the last comment's `created_at`, and the
whole-issue ETag moves with it. VERIFIED worse locally: `harness-tickets.sh` appends the comment
**into the ticket file itself**, and `body_to_file` returns everything after the frontmatter — so the
orchestrator's status note **edits the description**. 02:14 it comments; 02:15 the watcher spends a
model call and reports «змінилось» with a diff of its own log line; 02:16 Д9 writes its decision back
to the board, which is another change.

**C-08 · The registry lives in the project; the default runs every task in a worktree.**
«локально, тобто в самому проєкту, якась структура … і в тому реєстрі будуть всі завдання» [129]
× «Дефолтна пропозиція, щоби **абсолютно все виконувати в різних ворк трі**» Д4 [433].
*Case:* VERIFIED on this machine — all **327** ticket files are tracked in git, and `hproject_root`
resolves by walking up from `$PWD`, which inside a worktree is the worktree's copy. 00:10 he adds
ticket 328, ready — no lane can see it. 01:20 he edits ticket 312, which lane 2 is working — lane 2's
watcher hashes its own frozen copy, sees nothing and stays silent exactly as [466] requires. **The
silence is correct behaviour and a wrong answer.** Precedent: FIELD-NOTES §12.5, `QUESTIONS.md`
forked into a worktree copy and a real owner-facing question sat there invisibly for an hour. **The
same collision applies to the control file [520], the prohibitions file [357] and the Д6 channel
[449].**

**C-09 · The configurator asks; the run is forbidden to ask.**
«Якщо чогось немає, то **оркестратор задає ці питання** для того, щоби їх покрити» [133]
× «Ні, оркестратор **не повинен нічого виводити** для мене … Йому не треба ніякого інпуту виводити»
[508].
*Case:* 23:50, he connects a board, starts a run and walks away. One status mapping is missing. Under
[133] the orchestrator asks. Nobody is awake. VERIFIED that nothing rescues it: FIELD-NOTES §11.1,
*"the stale-heartbeat nudge is the only escalation the engine has"*, peaks of 2808 s and 44791 s;
§12.1, `send` **fails silently above roughly 200 characters** — and a config prompt is longer than
that. And the question it would ask is one he cannot answer from a terminal: on his own live ClickUp
list `review` is typed **`done`**, `ongoing` and `in progress` are both `custom`.

**C-10 · The continuous environment check has no legal action.**
«І **постійно переконуватись**, що всі ті енвайрмент верібли … або що є якісь **запущений стек**» [433]
× «якщо, наприклад, в тій самій папці я паралельно працюю над чимось, це не запускав оркестратор, це
роблю я, **він цього не має зупиняти**» [370] × «якщо він це **сам підняв**, то він це повинен і
зупинити» [430].
*Case:* VERIFIED, FIELD-NOTES §11.5 — his own `<work-project>-app-1` was `OOMKilled` (exit 137) at
`2026-09-13T03:29:01Z` while a validator ran two `docker compose up --build` at once, *"there was no
live alert"*. The check fires at 03:29:05. Restart it → violates R1-16, it is **his** container. Hold
the lane → invisible under R1-17 with no channel. Escalate to the process → the process knows nothing
about his Docker stack. **Every action the detector could take is forbidden by a different decision.**

**C-11 · A crashed run's leftovers are unreclaimable by design.**
«якщо він це сам підняв, то він це повинен і зупинити» [430] × «він би не мав зупиняти якісь там
тести, **які не він запускав**» [366].
*Case:* VERIFIED, FIELD-NOTES §10.1 — the previous run ended `watch: orchestrator dead + no live
sessions for 3 ticks — tearing down (Mac may sleep)`; §11.11 — *"About 150 orphaned Docker volume
pairs left by a dead prior run."* Run N+1 did not start them, so under Д3 it may not stop them and
under R1-16 it must not touch them. The ports collide and only the human the tool exists to keep
asleep can resolve it. **Each crashed run adds a layer.** The undefined word is «своє»: started by
*this run*, or by *this tool, ever*.

**C-12 · Teardown's first item is a role another decision forbids.**
«якщо, наприклад, він там підняв **свої якісь там оркестратори**» [430] × «якщо раптом одночасно два
якісь оркестратори працюють, то це не окей» [300], confirmed [304].
Either nested orchestrators exist and [300] is narrower than its words, or they do not and Д3's list
names a thing that cannot be there.

**C-13 · «Це максимум» — a ceiling on the plugin, or on him.**
«якщо людині потрібно якісь додаткові різні обмеження, то вона це може робити, **власноруч
налаштовуючи своє середовище** … Достатньо лише одного файлу … **Але, так, це максимум**» [357].
Read one way it forbids the plugin from building anything beyond the file. Read in place — the
subject of the whole passage is the human's own effort — it caps only what **he** will maintain.
*Case:* the two readings license opposite products; he was never asked which; and this single
unconfirmed clause is currently the binding constraint on the entire safety design.

**C-14 · A written path is a config value; "abstract" removes the field, not the need.**
«в оркестратори **прописаний шлях, до чого він має доступ**» [366] × «Чи якоїсь конфіг... Я би не
сказав, я би це робив **якось абстрактно**» [373].
*Case:* he launches from `~/Work/claude-plugins` while the tickets target `<work-project>`. Implementer A
scopes to cwd — every task fails at its first edit at 22:30. Implementer B scopes to the ticket's
project — wrong the moment a ticket spans two repos. Implementer C scopes to `~/Work` — the boundary
now contains every project he owns, which is case 1 inverted.

**C-15 · Moving an account moves his settings.**
«Наприклад, в моєму випадку це **[profile switcher]**, який використовує різні профілі» [199] × «Має бути якісь
визначене місце, де може людина додавати … обмеження» [357] × Д1's precedence [416].
*Case:* VERIFIED here — `<switcher> switch --print-env <profile>` sets **exactly one** variable,
`CLAUDE_CONFIG_DIR`, which is what his own marketplace resolves `<config-root>` from, i.e. **two of
the six config slots**. So a "routine soft/hard account change" silently swaps the person's own
configuration layer. If the prohibitions file lives under the config root, **the red lines move with
the billing identity**. He never said which.

**C-16 · Verification is bound to before the run; the assignment is editable during it.**
«**перед запуском** потрібно переконатися, що це працює» [199] (confirmed) × «якщо **в моменті** щось
змінюється» [195].
*Case:* 02:00 he adds `executor.account = <profile-B>`; that profile's OAuth token expired in August.
VERIFIED here: one profile has a keychain entry that yields **no readable access token at all**, and
another returns `authentication_error`. Every spawn dies in seconds; the liveness check
reads a session that died at launch as a stall; Д11 means nothing is printed.

**C-17 · Platform axis vs role axis.**
«**Під кожну платформу своє налаштування**, і це окей» [324] × «в мене є Клод Код, і допустимо, **три
вікна** … для кожного з них можу вказати, який буде поріг компакту» [204].
[204]'s three windows are all one platform; the platform axis cannot separate them. His role taxonomy
recurs at [036], [195] and [204], and the previous generation already routed **accounts per role**,
not per platform (FIELD-NOTES §8).

**C-18 · "No channel" is legal; "stay and wait" is the default.**
«чи треба взагалі канал якогось зв'язку» [395] × «по дефолту я б рекомендував, що він **залишається
та чекає** на мої відповіді» Д7 [455].
*Case:* a run configured with `notifications: none` and Д7's default waits indefinitely for an answer
to a question nobody was told exists. Д6's file is a **pull** surface, while his own stated
expectation there was live pickup [449].

---

## 4. Infeasible as stated

Requirements that no platform, or only Claude Code, can satisfy. Source: the fifteen platform profiles
and spikes, `ADAPTER-CONTRACT.md` §1/§3/§6, and probes executed on this machine on 2026-09-19/21.
This section is the discharge of instruction **I1**.

| # | The requirement, in his words | What is actually true | Grade |
|---|---|---|---|
| **F-01** | «потрібно чекати, коли воно розіб'ється … щоби продовжити всю роботу» [007] | **Not implementable on 7 of 15 platforms.** DeepSeek's `/user/balance` returns `total_balance` in CNY/USD — no window, no percentage, no `resets_at`; Amp is credits; pi, Qwen, MiMoCode, OpenCode, Aider, Cursor-on-personal expose **nothing**. There is nothing to wait for: the model is money, not time. | VERIFIED docs + spikes |
| **F-02** | «хардстоп, коли якийсь ліміт … 80% тижневого» [171] | A percentage does not exist on a credit model. And on the platform nominated as the *reference*, the field does not keep its meaning: **7,379 `rate_limits` records on his own disk** — on `plus`, `primary` is the 5 h window in 471 records and the **weekly** window in 1,098; on his current `prolite` plan **3,030 of 3,030** report weekly only with `secondary: null`; the same window is reported as both 299 and 300 minutes. A threshold naming "the five-hour window" can stop matching anything, silently, with no error. Also: `rate_limit_reached_type` and `spend_control_reached` are `null` in **7,379 of 7,379** records — neither in-band signal's non-null shape has ever been observed here. | VERIFIED, parsed on this machine |
| **F-03** | «хард, прямо вже зупинити, зробити компакт, і продовжити» [204] | **No external compaction trigger exists at all** on Amp, Gemini CLI, Cursor and DeepSeek `dsh`. Only soft mode via a threshold set **before** the run and unchangeable during it — which breaks Д7/Д12's rule that a mid-run change must be picked up. The universal fallback is close-and-reseed, which makes one ticket **many** sessions. | VERIFIED/CLAIMED per platform |
| **F-04** | «повинен бути механізм, який **гарантовано** робить цю дію» [204] | On Claude Code the only way to compact another session is to type into its tty, and typed text is the most failure-prone verb on record: `/compact` landed on **one of three attempts** on the same session in one day; **five separate instructions were never delivered** in one run; a bare Enter does not submit stranded text; `send` **destroys** what was pending; `send` **fails silently above ~200 characters**; a 149-minute stall happened because an Enter never landed and **nothing detected it**. Every failure is silent — the sender sees success. | VERIFIED, FIELD-NOTES §1.2–§1.5, §12.1 |
| **F-05** | «компакт, який буде робити оркестратор» [204], applied to the orchestrator itself | *"A model has no way to put text on its own input line"*, and `/compact` lands only when the target has no shell running — while the only self-typing mechanism **is** a shell. The previous generation's own watcher prompt instructs the opposite and contradicts itself in the same document. | VERIFIED |
| **F-06** | «якщо в моменті щось змінюється» — a **hard** account change [195] | **On every one of the fifteen platforms, changing a running session's account is impossible.** A hard account change is always stop → relaunch → re-seed context, i.e. paying for the window again — invoked by what looks like a one-line config edit. | VERIFIED, ADAPTER §3 F |
| **F-07** | Controlled mode as a run-level property [075] | On `cursor-agent` there is exactly **one** autonomy control — `-f, --force` — no ask state, no escalation hook, no permission-prompt tool. "Controlled" has no representation inside the tool. Codex's `-a on-request` means **the model decides when to ask** (his own unratified [082] clause, shipped as a vendor default). Claude Code's circuit breaker is **not configurable and does not fire in a headless `-p` run**. | VERIFIED here + vendor docs |
| **F-08** | «оркестратор може відповідати на ці питання» [324] | A headless Claude Code session whose `AskUserQuestion` is **allowed** receives `"User has answered your questions: ."` with `"answers":{}` — a bare period where the answer should be. The child model noticed and completed the task anyway. `claude --bg` exposes `agents/attach/logs/stop/rm/respawn/--resume` and **no send or answer verb**; a `blocked` background session is unblocked only by attaching. ACP (Gemini CLI) standardises **permissions** and has **no question primitive at all**. Gemini headless: a mid-run prompt **aborts the turn**. | VERIFIED by execution |
| **F-09** | «запускати якогось агента раз в N годин на якійсь іншій підписці» [246] | `claude agents --json` under two `CLAUDE_CONFIG_DIR` profiles returned **completely disjoint rosters** — four sessions each, neither seeing the other's. A probe under the wrong account does not return "alive elsewhere"; it returns **nothing**, which reads as dead. The design *mandates* the account difference [246]/[270], so it mandates the blindness. And a scheduled waker **does not run on a sleeping laptop** — the one mechanism meant to catch sleep is the one that cannot. | VERIFIED |
| **F-10** | «людина може конфігурувати, скільки може паралельно виконуватись» [160] | On **GLM** concurrency is a **plan term**, not a technical limit: Lite 1, Pro 1–2, Max 2+, and **three violations → account ban**. On **Kimi** all devices and all API keys share **one pool** — two lanes on one account do not double throughput, they halve each other. | CLAIMED vendor terms |
| **F-11** | Д8's silent change-watcher, on «будь-яка інша тула» [129] | **ClickUp cannot answer "did the description change" cheaply.** Measured live against his workspace: `cache-control: no-cache, no-store`, **no ETag, no `last-modified`**, 100 req/min, 19,580 bytes for four tasks, and the task object's date keys are `date_created`/`date_updated`/`date_closed`/`date_done` — **no description-change field**. The only precise signal is a webhook a laptop with no public ingress cannot receive. GitHub is nearly free by comparison: `If-None-Match` → 304 consumed **zero** of 5,000/hour across five repeats, and `lastEditedAt` is distinct from `updatedAt` (observed ten days apart), with `userContentEdits[].diff` returning the previous body. **One of the two boards he named cannot satisfy Д8 the way the other can.** | VERIFIED live |
| **F-12** | «там можна піари стакати, і він це теж може використовувати» [331] | `git --version` on his machine is **2.33.0**; `--update-refs` / `rebase.updateRefs` needs **2.38+**. `which gt spr ghstack git-spr` → none installed. A forced change on the bottom PR silently strands the ones above it, and a merge that achieved nothing prints `Already up to date`, which *"reads like success"*. | VERIFIED here |
| **F-13** | «ролі можуть сидіти на різних акаунтах» [195]/[270] | On **Cursor** with a browser login, multiple accounts on one machine are impossible — the keychain namespace is the hard-coded literal `"cursor"` and `CURSOR_CONFIG_DIR` does not scope it; only API keys work. On **OpenCode** a Claude subscription **cannot drive a session at all** (no Anthropic OAuth) — that is a bill, not an inconvenience. And on **his own machine** two config dirs can resolve to **the same underlying account** (same `accountUuid`). A role split across those two is not a split, and his pre-run check as specified cannot detect it. | VERIFIED here |
| **F-14** | Any unattended run under Claude Code on macOS | The first read of a never-granted account's credential may raise a **Keychain GUI dialog** — an unattended run blocks on a modal nobody sees. Codex, Droid, Kimi and Qwen have no keychain and cannot fail this way. | VERIFIED field scan |
| **F-15** | «одна межа, яку тримає система» + Д4's running stack [433] | **There is no sandboxed Docker.** Inside the OS boundary `docker ps` fails with `connect: operation not permitted`, and allowing the socket *"effectively grants access to the host system"*. Also: a sandboxed session could not signal a process **it had itself started** in an earlier Bash call, because each Bash call is its own sandbox instance — so the boundary alone satisfies R1-16 **by breaking Д3's teardown**. | VERIFIED by execution |
| **F-16** | «це має бути оркестратор для всього» [182] | **Today, only three agent CLIs exist on this machine at all:** `claude` 2.1.278 (current), `codex` 0.152.0 (three releases behind) and `cursor-agent` (**372 days old, not logged in**). Copilot CLI — the strongest platform in the scan on capability — returns `access_type_sku: "no_access"` on his account. The Xiaomi MiMo key in `~/.config/claude-mimo/env` returns **401** today. Gemini's consumer path **ended 2026-06-18**; the successor (`agy`) has unknown flags. Qwen's free OAuth tier closed **2026-04-15**. Everything else is a fresh install (145 MB–748 MB). | VERIFIED |
| **F-17** | The meter measures the spender | `~/.config/claude-mimo/env` sets `ANTHROPIC_BASE_URL=…xiaomimimo.com/anthropic`, and `harness-limits.sh`'s `token()` reads the Anthropic OAuth token from the keychain and **never consults `ANTHROPIC_BASE_URL`**. A session pointed elsewhere spends someone else's quota while the gate meters an Anthropic account the session never touches — a number that **cannot rise**, so the gate stays green all night by construction. FIELD-NOTES §11.7 records the real version: *"my limits position was measuring the wrong account"*, with the building account reading 94 % weekly on the wrong pool. | VERIFIED here |
| **F-18** | Polling the quota endpoint at all | A **single** well-formed authenticated call to `api.anthropic.com/api/oauth/usage` returned `{"error":{"type":"rate_limit_error"}}` on this machine, about a minute after another agent's probe sequence. His own global `CLAUDE.md` instructs **every** Claude Code session to poll that endpoint before and during any long task — so three roles plus the orchestrator's gate plus a watcher cycle all contend for a ~2-call budget. Whether the throttle is per-token or per-IP is **UNKNOWN**; if per-IP, rotating accounts to read quota buys nothing. | VERIFIED here |

**Two platform-independent consequences to carry into the build.** (a) `Capacity = Window | Credit |
Unknown` must be a first-class sum type with a policy per variant — `Window` → pause until `resetAt`;
`Credit` → hard spend ceiling, stop, notify, **no auto-resume**; `Unknown` → local ledger and never
give that lane a role whose capacity must be predicted. (b) Close-and-reseed turns ticket→session from
one-to-one into **one-to-many**, so the ledger must be a lineage, not a field.

---

## 5. Undefined defaults

Every place where "the user configures it" has no stated default, ranked by how often a user would
hit it. Rank 1 is "every install, first night".

| # | The setting | What he said | Default today / what happens with nothing | Where |
|---|---|---|---|---|
| 1 | **Run mode at zero config** | three values named [075] | **None stated.** The previous generation's `session.permissions` defaulted to **`bypass`** — every unconfigured run autonomous | C1 A5 |
| 2 | **Permission flag at spawn** | «технічні обмеження середовища користувач за потреби налаштовує сам» [357] | VERIFIED `harness-spawn.sh:32-39`: `--dangerously-skip-permissions` is the **default and the fallback for an unrecognised value**. His `~/.claude/settings.json` sets `defaultMode: bypassPermissions`; `~/.codex/config.toml:7` sets `sandbox_mode = "danger-full-access"`. For R1-15 to be true he would have to know all three | C8 A4 |
| 3 | **Visibility at zero config** | four modes, per platform [324] | None. Interactive → 19 windows on his workstation; headless → F-08's silent corruption on night one | C7 A7 |
| 4 | **Which percentage, and per-role thresholds** | «при скількох відсотках» [204] | None — and there are **two** percentages on his machine, ~13 points apart (`gsd-statusline.js:801-802`, `AUTO_COMPACT_BUFFER_PCT = 16.5`, its own comment: *"inflates … by ~13 points"*). Measured refill rates differ by an order of magnitude: 8 %/h, 26 %/h, 2 %/h | C5 A2, A11 |
| 5 | **What happens when the quota number cannot be read** | nothing in the transcript | Shipped default `"on_unreadable": "proceed"` — and `harness-limits.sh:55-58` requires a `.limits` array the live endpoint does not have, so `snapshot` returns `UNREADABLE` on **every** call. `weekly_all=unreadable%` recurred across many days; the limiter ran for days enforcing nothing | C4 A6 |
| 6 | **A missing setting at run time, unattended** | «оркестратор задає ці питання» [133] | Undefined against Д11's silence. Refuse to start / filter tickets / self-default — three different startup paths | C3 A4 |
| 7 | **Where a run-time answer is written** | «перевизначені для конкретного запуску» [335], confirmed [336] | Д1's marketplace closes the level set at three and writes every answer to a **user-level** file: *"one person's settings on one machine … they apply in every project"*. A tired yes on a scratch repo at 23:40 becomes the silent default on a client repo two weeks later, and [133] correctly does not ask | C2 A11 |
| 8 | **An untyped change on a watched file** | «вказується, який тип цієї зміни» [195] | Undefined. `~/.claude/shared/identity.json` is written by **clickup, g-event, log-time and find-call**; the two project slots are **tracked files** that `git checkout/merge/pull` rewrite — and a rewrite with identical content **moves mtime** | C2 A5 |
| 9 | **Intake ceiling per run** | «Він може абсолютно спокійно підібрати» [422] | Unbounded, by omission. The only recorded instance needed a human: the queue grew **236 → 327 in a day** and he set a soft pause at 11:15, awake | C3 A5 |
| 10 | **The Д8 watched set** | «слідкує за цим» [466] | Undefined: active only / active + ready / everything. Each is a different cost profile per backend, and Д9's *preferred* branch (a finished ticket that changed) has **no trigger at all** | C3 A3 |
| 11 | **Notification event set on first run** | «людина налаштовує, які типи» [395] | None. Both naive defaults were observed to fail: empty → a merge that moved nothing, discovered in the morning; everything → one condition re-fired **1085 times over five days** | C9 A6 |
| 12 | **Channel re-verification cadence** | «повинен **лише** переконатися, що це працює» [395] | Preflight-only is the natural reading. The human-notification watchdog *"had already exited ('run finished') and was never restarted"* while the run was still looping | C9 A5 |
| 13 | **Health-check interval N, and its account** | «раз в N годин на якійсь іншій підписці» [246] | None. N ≥ 2 h swallows the 85-minute loop whole; N small spends the account [270] reserves for the orchestrator | C6 A9, A10 |
| 14 | **Stall threshold / corroboration** | «Агент сам повинен це вирішувати» [231] | None. Every cheap observable has a measured false-positive: 33 nudges in one run, `STALLED` against healthy sessions 8+ times in ~7 hours, a shell that could never exit reading as work for 45 minutes, 3,466 of 3,626 Bash calls being `echo idle` | C6 A4 |
| 15 | **Third verdict timeout** (probe errored) | two buckets only [300] | None. The endpoint returned `authentication_error` for **1 h 22 m** once, and 429 today | C6 A2 |
| 16 | **`stop-custom` degradation** | «текстописні правила **чи** команди» [524] | None. Prose needs a model call exactly when the account is exhausted; a command has no exit contract. The three plausible degradations are as far apart as outcomes get | C2 A8 |
| 17 | **Where the prohibitions file lives, and what a failed read means** | «якісь визначене місце» [357] | Neither stated. Reading is «в обов'язковому порядку» with no failure branch; this codebase's demonstrated house style is **fail-open** (§11.9: a sweep *"reads clean over files it never opened"*) | C8 A5 |
| 18 | **The scope root for the written path** | «прописаний шлях» [366], «абстрактно» [373] | None — three defensible derivations, one of which fails every task at 22:30 | C8 A8 |
| 19 | **Board-check failure verb** | «треба перевіряти, чи дошка готова» [153] | The shipped code already picked one silently: `gh label create … --force` for five labels — an externally visible schema change to someone else's board at 04:00 | C3 A7 |
| 20 | **Machine sleep** | never discussed | `run.caffeinate: true` is an **inherited config default nobody decided**, and `caffeinate` is bound to the watch pid — when the watch dies the Mac sleeps and everything freezes without dying. That is how the last run ended | C6 A5 |
| 21 | **Worktree owner** | «з цим треба поєднювати» [433] | Undecided between three parties: the orchestrator, GSD (`dispatch-isolation` → `harness-worktree`, *"GSD runs no git"*, and its `worktree.baseRef:"head"` escape hatch **is not read by the host**), and `claude --worktree` | C9 A2 |
| 22 | **Stacking eligibility** | a capability granted [331] | None. Stack everything concurrent (false dependencies, serialised merges) or never stack | C9 A9 |
| 23 | **Mid-run mode-flip arrival semantics** | «може перевизначити … для конкретного рану» [075], Д7 [458] | None. He has soft/hard vocabulary for limits, accounts, compaction and stops — **never for modes**. And already-spawned workers hold a prompt file written at spawn that nothing re-reads | C1 A10 |
| 24 | **Machine-authored ticket eligibility** | Д9 [482] × Д2 [422] | None. The orchestrator can file work for itself, claim it, and file more | C3 A8 |

---

## 6. The ranked question set for round 2

**26 questions**, deduplicated across the nine clusters (90 candidates in, 26 out), ordered so that
answering one does not pre-empt another. Blocks A–F are the reading order. Each carries **kind ·
priority · cluster · the one-line reason it exists**.

### Block A — vocabulary and licence (everything downstream is denominated in these)

| # | Question | Kind · Priority · Cluster | Why it exists |
|---|---|---|---|
| **Q-01** | Does an autonomous run have **more powers**, or the same powers with a different mailbox for questions it cannot answer? | definition · blocker · C1 (I2) | He said he does not know they differ — «Не знаю, чи вони будуть відрізнятися» [058] — and handed the definitions to this analysis [082]. The answer deletes three of the six definition pairs in `RUN-MODES-OPTIONS.md` outright. |
| **Q-02** | When a hard stop fires, what is held — the action, the ticket, the lane with its worktree, or the whole run? And if a *worker* raises it, does it reach the orchestrator at all? | collision · blocker · C1/C2 | C-01. Two of his own rows disagree and the difference is 16 untouched tickets versus eleven phases merged on an answer he reverses. |
| **Q-03** | Read back the three stops and confirm them — and then: «софт» currently means three different boundaries in three of your answers. One word or three? | ratify + collision · blocker · C4/C2/C5 | C-02 and C-03. The load-bearing vocabulary that R1-07, R1-08 and Д12 all reuse was never ratified ([176]–[181]); four other questions spend it. |
| **Q-04** | Which percentage is your percentage — the one Claude Code reports, or the bar in your status line? They are ~13 points apart on your machine. | definition · blocker · C5 | Get it backwards one way and the platform's own auto-compact fires before your threshold is ever reached, so the mechanism never runs once in a night and the report reads identically to "nothing needed it". |
| **Q-05** | What is "one run"? If you start one in the evening and, thinking it died, start another in the morning — same run to be refused, or two runs that may coexist? | definition · blocker · C6 | «Не дозволяти» [300]/[301] cannot be implemented until "a run" has an identity. Keyed on the directory, two runs corrupt each other; keyed on the project, a second milestone is refused — and nothing says it may not be. |
| **Q-06** | «Але, так, це максимум» — a ceiling on what the plugin may build, or a ceiling on what **you** will maintain by hand? | ratify · blocker · C8 | C-13. This single unconfirmed clause is currently the binding constraint on the entire safety design, and it decides whether Q-26 is even a permitted conversation. |

### Block B — authority and escalation

| # | Question | Kind · Priority · Cluster | Why it exists |
|---|---|---|---|
| **Q-07** | Name a trigger that is visible from **outside** the agent (doubt is not), and: must every escalation carry a written line saying what will happen if nobody answers? | gap · blocker · C1 | The trigger for both modes is a self-report. The previous generation shipped it as "<70 % sure". The one escalation format with a production record behind it is his own: every question carrying a recorded `Fallback`, each later answered. |
| **Q-08** | Is a question from a child session ever something the orchestrator must **refuse** and escalate — or does it answer everything? | collision · blocker · C7 | C-06. If it answers everything, "controlled run" is a label, not a mode, at the layer where work is actually decided. |
| **Q-09** | May a repository you did not write decide for you — its tone-of-voice document as a decision basis, and its committed plugin config as a settings layer? | gap · blocker · C1/C2 | Both follow from decisions of his ([087] and Д1 [416]), and together they let a client repo cloned this afternoon set `autonomy: full`, redirect the questions channel and silence notifications — all three unset in his own files, so all three win. Claude Code's own classifier deliberately does **not** read repo settings, for this exact reason. |
| **Q-10** | Ratify: may the agent decide on its own that an autonomous run must hard-stop and come to you? | ratify · major · C1 | The only unbounded authority in the design, filed SETTLED but never confirmed [085]/[086]→[087]. And the faculty it relies on is the one that failed twice on record (85 min; 33 m 31 s and 184k tokens against a dead daemon). |
| **Q-11** | «Треба вчити» — what is the teaching act? And must the orchestrator's answer be marked as **its own**, not yours? | gap · major · C1/C7 | Merged because the second makes the first unimplementable: a child transcript records `User answered Claude's questions` identically whoever answered, so on night two the basis "previous answers to similar questions" reads the machine's own guesses as his precedent, and his corrective loop has nothing to correct. |

### Block C — proof, completion, delivery

| # | Question | Kind · Priority · Cluster | Why it exists |
|---|---|---|---|
| **Q-12** | Does the orchestrator check **its own** actions — that the merge moved the branch, that what it started started, that what it stopped stopped? And what counts as evidence in a report written by the actor? | gap · blocker · C9/C1 | Not a reopening of R1-13 — that is about *the work*. A process cannot attest to an action it did not take. The merge that printed `Already up to date` and moved nothing was caught only by checking what `master` pointed at; a model on this codebase wrote **26 refusal events that never occurred**. The check costs zero model tokens and works on projects with no tests. |
| **Q-13** | Who declares a ticket **finished** when the configured process declares nothing — and what happens when it returns "done, with unverified checks" or "human needed"? | gap · blocker · C9 | "Done" and "verified" are different objects; R1-13 assigns the second and nobody the first. The official-marketplace `feature-dev` process has **no state file, no status command, no git**, and a phase whose text reads *"DO NOT START WITHOUT USER APPROVAL"* — a clean exit at that line currently reads as success. |
| **Q-14** | GitHub says nothing is protected; `CLAUDE.md` says PR-only. What is the default? | default · blocker · C9 | VERIFIED today on his flagship repo: `rulesets` → `[]`, `branches/main/protection` → `404`. An orchestrator that learns rules from the forge pushes thirteen merges to `main` of a repo carrying eleven production plugins, and breaks no rule it could see. |
| **Q-15** | Who creates the worktree when the chosen process creates its own? | collision · blocker · C9/Д4 | «З цим треба поєднювати» [433] is a task, not a decision, and today the two cannot be reconciled: GSD's `dispatch-isolation` returns `harness-worktree` and *"GSD runs no git"*, its `baseRef:"head"` escape hatch is not read by the host, and on a real project `base-check` returns `{"shouldDegrade": true}` — so the phase silently runs one-wide, or forks from a base the orchestrator never recorded. |

### Block D — the control plane and the filesystem

| # | Question | Kind · Priority · Cluster | Why it exists |
|---|---|---|---|
| **Q-16** | «Єдиний файл» — literally one file, or one **place** with one writer per file? And may the orchestrator clear a stop it did not write? | definition · blocker · C2 | Four writers in one artefact, one of them him, live, by hand. The previous generation ran this experiment and lost: `state/attention` was rebuilt every cycle, destroying everything others wrote, costing 8+ false `STALLED` alarms across ~7 hours. The unattributed-`STOP` bug is issue `#82`, **still open**. His own hand-built questions channel already uses four files with one writer each, and works. |
| **Q-17** | Under your worktree default, which copy is the real one — the board, the control file, the prohibitions file, the questions channel? | collision · blocker · C2/C3/C8 | C-08, asked once for all four rather than four times. It has already happened: `QUESTIONS.md` forked into a worktree copy and a real owner-facing question sat there invisibly for an hour. For a question channel that cost an hour; for a stop file it costs the night. |
| **Q-18** | Where does an answer you give at midnight land — is there a "this run" scope at all? And what does the run do when a setting is missing at 23:50 and nobody is awake? | collision + default · blocker · C2/C3 | C-09. He confirmed a per-run scope [335]/[336]; the marketplace he deferred to closes the set at three and writes every answer to a **machine-wide** file. Without a run scope, Д7's "the live edit beats the run's choice" and "beats the default" are edits to the same value with nothing ordering them. |
| **Q-19** | A watched file changed and nobody attached a type — another plugin wrote it, or git rewrote it in a lane. What then? | default · blocker · C2 | R1-07's whole mechanism assumes a human author on every change. His own marketplace says the opposite in writing, and four of his production plugins write the shared file. |

### Block E — liveness

| # | Question | Kind · Priority · Cluster | Why it exists |
|---|---|---|---|
| **Q-20** | «Стан останнього запису» — the orchestrator's own "I am alive" record, or the last trace in the **work**? And how many independent signals must agree before it acts on a session? | definition + gap · blocker · C6 | Recovers the only concrete liveness mechanism proposed in the whole interview, cut off three times [249]/[251]/[253] and dropped by the analysis. The two readings are different products — one stays fresh through a useless loop, the other goes stale during a legitimately long turn. |
| **Q-21** | The third verdict: the probe **could not look**. Wait, or call it dead after N? And which account does the checker probe as? | gap + feasibility · blocker · C6 | F-09 and C6 A2. His rule has two buckets and the third is the recorded norm. Error→dead spawns a second orchestrator onto a live run; error→wait means five hours of nothing, which fails R1-01 outright. |
| **Q-22** | A planned replacement is not a death. When the window fills, who waits for whom — given «переконуєш що воно не спрацювало» and «не дозволяти»? | collision · blocker · C5/C6 | C-04. Both exits are closed by his own rules, and the close-and-respawn path was **proved not to work** on this setup, twice, on 2026-09-02. |

### Block F — what the platforms cannot do (discharge of I1)

| # | Question | Kind · Priority · Cluster | Why it exists |
|---|---|---|---|
| **Q-23** | Can the run spend the limit to zero, or must it leave you a reserve — and how much? | gap · blocker · C4 | **Written for round 1 and never asked.** Every threshold in the design is a threshold against *exhaustion*; a reserve is a different number and possibly a different mechanism. And it is the one resource where his own non-interference rule [370] is physically impossible when the run and his morning share an account — which F-13 shows he may believe is not the case when it is. |
| **Q-24** | Seven of fifteen platforms cannot report remaining capacity at all, and credit platforms have no window, no percentage and no reset. What do such lanes get — and how do you cap money? | feasibility · blocker · C4 + ADAPTER §7 | F-01, F-02, F-10. This is the single largest divergence in the field and it is the direct reply to his own instruction: «якщо раптом десь немає лімітів … це треба буде винести окремими питаннями потім» [182]. |
| **Q-25** | Four platforms cannot be compacted from outside; **none** can change a live session's account; some cannot be answered at all. Do such platforms get roles, degraded roles, or none? | feasibility · blocker · C5/C7 + ADAPTER §7 | F-03, F-06, F-07, F-08. It also decides whether "works for all sessions" is a promise the config keeps uniformly or a per-platform capability table the user sees at config time — and whether close-and-reseed (one ticket → many sessions) is acceptable to his accounting. |
| **Q-26** | Is an OS-checked list of paths — **your own written path list**, checked by the kernel instead of by the model — the simple reliable variant you asked for, or the determinism you refused? And what flag should the plugin pass when you configured nothing? | collision + default · blocker · C8 (I3) | C-14 and undefined-default #2. **Nobody ever offered him the middle rung**: what he refused at [370] was described to him at [364]/[365] as «окреме середовище» — a container. Meanwhile the plugin already sets his safety posture on every spawn, to the least safe option, and he cannot see it. Ask last, because Q-06 licenses it. |

### If the session must be short — the twelve to keep

**Q-01, Q-02, Q-03, Q-05, Q-06, Q-07, Q-09, Q-12, Q-17, Q-20, Q-23, Q-26.**

Why these twelve: four are vocabulary that everything else is denominated in (Q-01, Q-02, Q-03,
Q-05); one is the licence that decides what may be built at all (Q-06); three close blockers whose
answers no research can supply because they are preferences, not facts (Q-07, Q-09, Q-23); and four
are the cheapest single decisions with the widest blast radius (Q-12 — a self-audit layer that costs
zero tokens and catches the failure class that ended the last run; Q-17 — one answer covering four
artefacts that have all already forked once; Q-20 — the only liveness mechanism he proposed, and it
was lost; Q-26 — I3's crux, and the one place where his stated refusal may not cover what was
actually built).

Dropped from the twelve with reasons: Q-04 and Q-19 are proposable (§7 P-08, P-10). Q-08, Q-10,
Q-11 all narrow once Q-01 is answered. Q-13, Q-14, Q-15, Q-22, Q-24, Q-25 are answerable in writing
from the research and only need a veto. Q-16, Q-18, Q-21 follow mechanically from Q-17 and Q-20.

---

## 7. Decisions I would propose rather than ask

Where the research gives a clearly right answer and asking him would waste the session. Each is
stated as a proposal he can **veto**, with its evidence — never as something already decided.

**P-01 · The ownership floor: a run-scoped ledger written before creation, plus worktree anchoring.**
Every session, worktree, branch, container and service is recorded with a durable identifier *before*
it exists, and the run acts only on what it recorded. Evidence: this is the direct fix for both
recorded incidents — the unscoped `docker compose down -v` that destroyed his default stack with *"the
actor never identified"*, and `pkill -f 'playwright test'` killing an unrelated lane *"because every
lane's own prompt text contains that literal string"*. It costs him nothing, contradicts nothing he
said, is pure plugin code, and leaves R1-15 standing exactly as given. `BOUNDARIES-OPTIONS.md` Options
2 + 3. **The one thing that must still be asked is where the boundary is *enforced* — Q-26.**

**P-02 · The ten adapter invariants, as hard rules.** Never branch on an exit code (Aider returns 0 on
auth failure, rate limit and success alike; pi `--mode json` exits 0 on provider failure; GLM exits 0
on quota exhaustion *with* `subtype:"success"`; MiMoCode's exit code is always 0). Never trust HTTP
200 or a `success` string. Always close or own stdin (Codex hangs all night without `< /dev/null`).
Always impose an external wall-clock timeout. Always pin the version and disable auto-update (Amp
shipped five releases in fifteen hours; Copilot 835 versions in twelve months). Always pin the model
(inheriting his `~/.codex/config.toml` produced a **100 %-failing** run). Keep stdout and stderr
separate. Union the roster across accounts. Re-attach permission and question handlers on every
resume. Assert teardown by process, not by the command's word (`cursor-agent worker kill` reports
success and leaves the process at 100 % CPU). **All VERIFIED per platform; none is a preference.**

**P-03 · Two logs with different trust.** An engine-written `journal.ndjson` carrying `intent` /
`result` / `observation` with admissible evidence, and model-written `decision` records that are
**never evidence of anything**. Evidence: a security review of a single API read found **26 refusal
events in the audit log that never occurred**; GSD's verify stage was silently skipped for phases
14–18, each file self-attributing `verified_by: the lane that built the phase`, with *"no automated
check"* catching it. This is the architecture that makes Q-12's answer implementable whichever way he
answers it.

**P-04 · One normalised event vocabulary per adapter** — `turn_started / tool_call / waiting_on_human
/ compacted / turn_completed / failed` — and the orchestrator never reads platform-native records
directly. Evidence: transcript formats share no shape across the fifteen platforms (JSONL, SQLite,
server-side API only, SSE + store, markdown prose). Without it, one platform's schema change breaks
the run loop for all of them. And **"waiting on a human" must be a distinct state from "working"** —
conflating them is how an overnight run dies quietly.

**P-05 · The ticket ledger keys on `ticket_id`, and `(platform, account, session_id)` is a list.**
Evidence: close-and-reseed is the only compaction fallback that works on every platform (F-03), and it
turns one ticket into many sessions. Three platforms let the client name the id; five mint it
server-side; Aider has none. Never use a platform id as the primary key.

**P-06 · `orchestrator:status` is a shell script, not a skill.** Evidence: his own «мінімальну
кількість аутпуту і стокінгів» [512], against the VERIFIED fact that `commands/status.md` reads in
full *"Invoke the `harness:harness` skill … passing `--status` through verbatim"* — so asking for
status **spends a model turn** — while `harness-run.sh do_status --json` underneath it is pure bash
and jq. The zero-cost path already exists and the command in front of it does not use it.

**P-07 · The prohibitions file, the control file and the questions channel resolve to an absolute path
in the main checkout, always, whatever directory a lane runs in; at merge, the main checkout's version
wins whole.** This is not a design — it is the rule his own project **grew** after `QUESTIONS.md` and
`JOURNAL.md` forked and twenty-three journal entries landed on the wrong side. Q-17 then only has to
answer *where* the file lives, not how path resolution works.

**P-08 · Change detection: content digest plus `stat -f '%Fm'` (APFS nanoseconds), never `stat -f
'%m'` / `date -r` / `find -newer`.** Evidence measured here: the second-granularity detectors **miss
two writes in the same second** — which is exactly the shape of `stop-hard` typed right after a config
tweak — and a rewrite with identical content **moves** mtime, so they over-report too. Also: inside a
Claude Code bash session `find` is a shim, not `/usr/bin/find`, so the same command behaves
differently in his terminal and in the run's. **And correct the record: he only hedged mtime
(«Можливо, наприклад») — `ANALYSIS-01.md` hardened it into a decision.**

**P-09 · One writer per file, rather than locks.** `lockf(1)` exists on this machine and `flock(1)`
does not — but one-writer-per-file needs neither, and it is what his own hand-built questions channel
already does (`docs/open/{QUESTIONS,ANSWERS,README}.md`: append-only, one writer per record, *"It
never edits `ANSWERS.md`"*). Also: a torn read of a JSON control file silently returns **every**
default for that tick, and because keys are read one at a time, a save straddling two reads yields a
**mixed** config inside one tick.

**P-10 · The questions channel ships with a default shape, and the default is his own field-proven
one:** two files, append-only, one writer each, a mandatory `Fallback:` line on every question, a
~60-second poll. Evidence: he already built and ran this by hand on `<work-project>` — «в мене так було,
коли я … працював з гарнесом» [449] — and it is the only pattern in the interview with production
evidence behind it. He still chooses *where* it lives (Д6 is explicit that the place is his), but "no
channel configured" should not be reachable by accident on a run started from a script.

**P-11 · Seed `TONE.md` from this transcript before the first run.** Evidence: on day one, three of
his four decision bases are structurally empty (no written rules yet, no previous answers, a repo file
that may not exist), leaving "the agent decides on its own project knowledge" as the only working
option on the very run where delegation is least evidenced. The transcript already contains at least
seven decision classes he stated in his own words (scope change after done, repeated failure,
only-blocked-left, trunk delivery, watch-duty cost, new-ticket preference, teardown scope). Seeding
costs nothing and removes the worst day-one behaviour of every option in `RUN-MODES-OPTIONS.md`.

**P-12 · Preflight refuses to dispatch to a lane not proven today, and verifies the account *after*
launch from the platform's own report** (`initialize.account.email`, `auth_changed`,
`apiKeySource=="env"`), not from the variable it set. And it compares **`accountUuid`, not profile
name** — two config dirs can resolve to the same underlying account, so a role split
across them is not a split. His own requirement [199] demands the switch be proven before a run
starts; this is the only form of that check that catches F-13 and F-17.

**P-13 · Build order: Claude Code adapter → Codex → a provider lane (GLM or DeepSeek behind the Claude
Code driver) before any third CLI.** Evidence: Claude Code is the only lane that can run tonight
(installed, current, authenticated through the profile switcher, and GSD lives there). Codex is the
honest test of whether `PlatformAdapter` is an abstraction or a Claude Code wrapper — different vendor,
different protocol, different account model, tier-1 on every axis, **no keychain** (so it removes the
F-14 class of overnight failure entirely). A provider lane is a configuration change, not a feature,
and it exercises the `Provider` × `Platform` split and the `Window | Credit` type as working code.

---

## 8. What the owner asked for explicitly

Four standing instructions. Three were commissioned in the transcript; the fourth is how he wants
round 2 to run.

### I1 — feasibility per platform, and every divergence as its own question

> «Тут ще, ти коли будеш це аналізувати, я про це не говорю, і **я ну все вірю, але воно може не
> сходитися з дійсністю** … колектор, який це буде отримувати, повинен аналізувати. Якщо, наприклад,
> при різних платформах це буде неможливо, то про це треба говорити і обдумувати, як можна це
> зехендлити … це треба буде **винести окремими питаннями потім**, як це вирішити» — **[182]/[183]**,
> confirmed [186].

**Answered by:** `research/platforms/` — fifteen platform profiles, fifteen executed spikes,
`00-field-scan.md`, and `ADAPTER-CONTRACT.md` (a ten-axis capability matrix, the four non-negotiables
isolated per platform, seventeen adapter operations, graceful-degradation ladders naming **which of
his requirements quietly becomes false** on each axis, six cross-platform hazards, and §7's eighteen
divergence questions already written in Ukrainian).

**Consolidated here:** §4, eighteen entries.
**Carried into round 2 as:** Q-24 (quota: no reading, or money not time), Q-25 (compaction,
account switching, answering), and as evidence inside Q-14, Q-15 and Q-26.
**Still open and it is his to decide, not ours:** which platforms he will pay for or install before
adapters are written — Copilot CLI (`no_access`, signup open), Cursor (372-day-old build, not logged
in), the MiMo key (401 today), Gemini's successor `agy` (flags unknown), and the standalone Codex
install (`chatgpt.com/codex/install.sh`), which is the highest-value single experiment in the scan
because it would give the orchestrator **a supervisor that survives its own death**.
**Note the framing he gave and the analysis dropped:** «я ну все вірю, але воно може не сходитися з
дійсністю» is him *pre-authorising the contradiction*. §4 is not an objection to his requirements; it
is the thing he asked for.

### I2 — definitions of «контрольований» and «автономний»

> «Одне з субтих питань, які ти можеш мене запитати, що таке контрольований, що таке автономний ран.
> **І в мене поки немає відповіді.** Це потрібно, щоби агент, який буде колектити ці результати,
> **проаналізував і запропонував мені варіанти** для цього.» — **[082]**

**Answered by:** `research/options/RUN-MODES-OPTIONS.md` — six complete definition pairs, each
adoptable as written (A «Same powers, different mailbox» · B «The ops table decides» · C «No fallback,
no autonomy» · D «Earned per class, from a ledger» · E «Two spawn profiles, not two modes» · F «One
dial, no modes»), a twelve-row table of what no option may contradict, a floor common to all six, six
worked scenarios, a concrete `TONE.md` grammar with five entries drawn from his own decisions, and a
recommendation: **Option C with Option B's tables as its floor**, in one sentence each —

> «Контрольований ран — коли на все, що агент не може закрити заздалегідь записаним запасним
> варіантом, він питає тебе, і цей тікет чекає стільки, скільки треба, а решта черги йде далі.
> Автономний ран — те саме, тільки в питання є термін: якщо ти не відповів за N хвилин, виконується
> той самий записаний запасний варіант, і в звіті це позначено як «спрацював запасний варіант».»

He asked for options, not a decision, so the recommendation is offered with its **strongest
counter-argument stated in the same document** (the fallback is written by the same model whose
judgement you did not trust) and a table of what it costs to change his mind later — four of five
exits are cheap or free.

**Carried into round 2 as:** Q-01 (the answer that deletes three of the six), Q-02, Q-07, Q-10.

### I3 — a Fable agent on the boundary question, returning options

> «Я хочу, щоб по результатам цього колекціону запустився фейбл агент, який проаналізує це питання …
> просто отримає контекст, що я говорив на цій сесії. І він відповідно зробить аналіз та
> **порекомендує мені якісь варіант** … він повинен проаналізувати, **повернутися до мене і
> запропонувати якісь варіанти**» — **[378]/[381]**, confirmed [383].

**Answered by:** `research/options/BOUNDARIES-OPTIONS.md` — a twelve-entry mechanism inventory, six
complete options (trust the file · ownership ledger · worktree anchoring · give the file teeth ·
kernel boundary · whole-process isolation), an honest comparison table that names what each one
**cannot** stop, seven live probes run on this machine, and a recommendation (**2 + 3 as the always-on
floor; 5 for the sessions the orchestrator starts, Docker-only-for-the-orchestrator**) with its own
strongest counter-argument stated: *"Option 5 is, by any honest reading, a deterministic mechanism —
the kernel deny is exactly the determinism he said he did not want."*

**The correction that makes this document worth reading:** «без складного механізму технічної
ізоляції» [372]/[376] is the **interviewer's** phrasing and he never confirmed it — he talked
underneath it («Я би не сказав, я би це робив якось абстрактно» [373]) and confirmed only the
deferral. What he *refused* at [370] was described to him at [364]/[365] as «окреме середовище, з
якого він узагалі не має доступу» — a container or a VM. **Nobody offered him an OS-level path
boundary, which is the mechanism he proposed himself two rows earlier** («в оркестратори прописаний
шлях, до чого він має доступ» [366]). VERIFIED here under his own `bypassPermissions`: a write to a
neighbouring project returned `operation not permitted`, `kill -TERM` against a foreign process
returned `operation not permitted`, `docker ps` failed on the socket — no prompt, no model cooperation.

**Carried into round 2 as:** Q-26 (the hinge), Q-06 (the licence it needs), and the Docker three-way
fork as a follow-up asked **only** if Q-26 is answered "let the operating system hold it".

### I4 — more grilling, and the correction to it

> «Я хочу, щоб ти коротко підсумував, використав скіл гріл мі або грілінг, і задав мені потенційні
> питання … я відчуваю, що є ще контекст, яким я би хотів поділитися» — **[408]**, immediately
> corrected: «Ой, точніше, **які я би хотів розказати тобі для того, щоб ти це записав і це впливало
> на майбутнє**» — **[409]**.

By his own last-said-wins rule [003], **[409] supersedes [408]**: he does not want answers from the
process; he wants to *tell*, to have it recorded, and to have it shape the build. `ANALYSIS-01.md`
keeps only the superseded version. Round 2's job is therefore extraction, not exchange — and the
Д-series exists at his request, not the interviewer's initiative.

**Three mechanics he stated that round 2 must honour, and round 1 broke:**
one question, asked **once**, and **re-worded** rather than repeated when it does not land («Тихо.
Один раз, один раз задай мені питання, але перезадай мені якось по-іншому, тому що воно дуже складно
звучить» [390]); **the concrete case ships with the question** — seven of the eighteen items were
unanswerable until the interviewer supplied one ([113], [227], [242], [289], [340], [353], [363],
[505]); **silence while he speaks** ([266], [368], [390]); **drive from the list, never «Що далі?»** —
asked eight times, which forced him to pull every question himself seven times; and **wait for the
«так»** — fifteen round-1 records do not have one. The repetition defect was called out **eight**
times, twice with profanity, and his direct order — «дуже уважно розберись, чому ти це робиш» [426] —
was never carried out: the interviewer's own diagnosis was *"причину цього збою я поки не встановив"*
[428], and the repeats continued through [504].

**And one thing round 2 owes him before anything else:** the opening monologue is **paused, not
finished** — «Давай будемо вважати що я просто поставив паузу розповіді» [031] — and he never resumed
it. He also needed a recap after the six-day gap («Справді не пам'ятаю, де я зупинився» [019]).
Reopen the narration first, then the list.

---

## Coda — relationship to the round-2 package already on disk

`round-2/{questions,context,prompt}.md` and `round-2/options/` were written on 2026-09-21 before this
map existed; that package carries **27 items** in four blocks. It and this map agree on substance —
every one of its blockers appears here — and differ in three ways worth reconciling before the
session runs:

1. **It does not carry the ratification audit.** Its Block А re-confirms three items (Д12, the
   agent-forced hard stop, the intermediate stop). §1 and §2.1 above show **22** unratified
   restatements, of which R1-15 (the red line), R1-06's stop vocabulary, R1-17 and R1-10's health
   check are the four that other decisions are built on.
2. **It resolves two things this map keeps open.** Its R2-04 offers a single definition of the two
   modes; `RUN-MODES-OPTIONS.md` holds six, and he asked for **варіанти** [082]. Its R2-27 states the
   lock is already on the project; Q-05 above treats "what is one run" as still his to decide.
3. **It is missing four blockers named here:** Q-12 (does the orchestrator check its own actions — it
   has this as R2-05, so this one is covered), Q-13 (who declares a ticket finished when the process
   declares nothing), Q-17 (which copy of a forked file is real — it asks this only for the questions
   channel, at R2-12), and Q-19 (an untyped change on a watched file).

Neither set should simply replace the other. The merge that loses nothing is: keep the round-2
package's Ukrainian wording and its platform block (В), insert Q-13, Q-17 and Q-19, and open Block А
with the four unratified items named in §2.1 rather than three.
