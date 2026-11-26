# Round 1 — analysis

Source: `TRANSCRIPT-01.md` (rendered from `TRANSCRIPT-01-ORIGINAL.jsonl`, Codex voice session
`01a09a47-cd54-71a1-a823-1cb40f7bbbfc`, 2026-09-13 → 2026-09-19). Row numbers in `[…]` are the
indices in TRANSCRIPT-01.md. Resource trust: the owner's own words, taken as source of truth.
Interviewer restatements are kept as the confirmation record.

**Labels:** SETTLED (owner confirmed a restatement) · PARTIAL (answered, but part of the item is
still open) · OPEN (explicitly deferred) · UNRATIFIED (answered, never confirmed before the session
ended).

**Headline.** Nearly every answer resolves to *the user configures it*. The system's identity is a
configuration and control plane over other people's workflows and other vendors' agents, not a
workflow of its own. The name changed: **harness → orchestrator** [118].

---

## Naming and scope

- **N1 — Rename. SETTLED.** "Оце от харнес, ми його будемо переназивати на оркестратор" [118].
  Everything below says orchestrator.
- **N2 — Not only code. SETTLED.** "цей оркестратор, оцей от плагін, може використовуватись зовсім
  навіть не для написання коду … може таке бути, що десь не буде тестів, і це також окей" [344].
  No assumption of tests, repos, or a build at all.

---

## The items

### R1-01 — What a finished run must leave behind · SETTLED (as "user-defined")
"Це все залежить, так як це налаштував … конкретної якоїсь вимірюваної штуки тут не може взагалі
бути … могло не виявитися когось з доступу, або ще щось, і ран зупинився, і це не означає, що це
помилка в нас" [062].
**Recorded:** success criteria are the user's configuration; there is no universal measurable
definition of a good night. The plugin's own obligation is to do its job correctly; an external
stop (lost access) is not a plugin failure.
**Surfaced here, not asked:** the autonomous vs controlled run distinction [054], see R1-14.

### R1-02 — What may be delegated · SETTLED
"людина повинна сама налаштовувати, що саме вона може віддавати на автономне виконання, а що
взагалі ні … це, скоріше за все, будуть якісь опитування або перед раном, або для конфігуратора на
глобальній основі" [107].
**Recorded:** the user configures what may run autonomously; the agent's decision authority is a
separate setting. Mechanism (pre-run questionnaire vs global config) still loose.

### R1-03 — Who owns the process · SETTLED
"цей оркестратор, він діє відповідно своїм конфігам … може налаштувати, чи це буде відповідно до
правил ГЕТШЕД … або суперпауерс, або будь-що інше … або ж налаштовується повністю свій … може
налаштовуватись з допомогою якогось ямл файлу … комбінувати ні, тут або або" [118].
**Recorded:** the orchestrator runs a process the user configures: either one existing process
(GSD, superpowers, another marketplace's tooling) **or** a fully custom one where the user defines
the steps, their order and whether there are checks. **No mixing** of a ready process with a custom
one. YAML named as a possible format, not fixed.

### R1-04 — Where work comes from, and what makes it ready · SETTLED + open sub-part
- Source [129]: local registry inside the project (kanban-shaped, "неважливо яка") **or** a
  connected board — "GitHub Issues, або ClickUp, або будь-яка інша тула", access verified.
  GitHub Issues is the first recommendation.
- Readiness [145–147]: by a defined structure the orchestrator follows — tags such as "AI ready"
  are **an example only**; "це треба буде, щоби придумав якусь структуру, і її притримувався".
  **This structure is still to be designed.**
- The board is a working surface, not just a source [149]: the orchestrator sets statuses and
  leaves comments.
- Board readiness check [153]: on connecting a board, verify it has the minimum set of statuses the
  configured process needs; status names are user-overridable and adapt to the chosen process
  ("ready, in progress, done" given as the plain case).
- Config lifecycle [133]: a separate `config` command, or configuration during the first run; on a
  run, read global and project settings, use what is there, ask for what is missing — "це вже
  існуюча архітектура для Клод Маркетплейсу".

### R1-05 — Concurrency · SETTLED, with a retraction
"можна конфігурувати, скільки може паралельно виконуватись … якщо якісь завдання не може
виконуватися, тому що не виконалось одне з попередніх, то його ми не можемо взяти … ресурси машини,
поки це заберемо, це добавимо в майбутнє" [160].
**Retracted by the owner mid-answer** [163]: the idea that the system itself decides that e.g. 100
tasks may all run in parallel — "це от останнє про сто завдань, це забери".
**Recorded:** the user sets the maximum; dependency-blocked tasks do not start; machine-resource
awareness is explicitly deferred to later.

### R1-06 — Limits · SETTLED in four parts
1. Exhausted limit [034–036]: wait for the reset, then continue; no binding to Claude's windows;
   adapt to whatever the provider's scheme is, including none/pay-as-you-go [007].
2. Approaching the limit [171]: it is fine for a task to run into a wall **because state is
   recorded**: "в нас в реєстрі має записуватись кожен стан, його виконання … для того, щоби було
   відновити процес і продовжити, навіть руками". Thresholds are user-set: hard stop (stop the
   running task now), soft stop (let the current task finish, start nothing new), and an
   intermediate "save state, possibly save the session, close it, resume later" — the intermediate
   variant is left **OPEN**.
3. Accounting [187–191]: reference the chosen process's own records (GSD has its own), supplement
   only what is missing, keep own records only when the process has none. At configuration time the
   agent must research the chosen process's accounting, agree with the user what is needed, and
   explain why it is asking. For GSD "майже нічого не треба робити" is an assumption to verify.
4. Feasibility across platforms [182–184] — **instruction to the collector**: verify these
   requirements against each platform (Claude, Codex, GLM, …); where a platform has different
   limits or none, raise the divergence as its own question rather than assuming it works.

### R1-07 — Accounts and roles · SETTLED
- Roles may sit on different accounts; assignments live in **one file the orchestrator or the
  context watcher keeps re-reading** for changes (mtime named as the mechanism) [195].
- A change carries a type: **soft** (applies to the next tasks) or **hard** (applies now, stops
  current work) [195].
- Per-platform switching mechanics must be explained and configured with the user at config/first
  run — API key, subscription account, or profile ("в моєму випадку це [profile switcher], який використовує
  різні профілі") — and **verified to work before a run starts** [199].
- Provider/account may be restricted to named roles — "лише для оркестратора або лише для
  виконавця" [270, 276].
- Provider = platform: "кодекс, чат джіпіті, кімі, GLM, джемінай" and each may hold several
  accounts [041]. Initially manual assignment per role is enough [036].

### R1-08 — Context exhaustion · SETTLED
"людина може налаштувати, при скількох відсотках відбувається компакт … софт - це коли завершується,
тоді робиться компакт. Чи хард, прямо вже зупинити, зробити компакт, і продовжити" [204].
The threshold also applies to all sessions or differs per provider and per orchestrator; the orchestrator may be compacted or replaced by a fresh one; the compact command (official or a custom skill) and an optional post-compact prompt are configurable [204].
Soft mode waits for **the current step**, and what counts as a step is itself configurable [209].
Hard mode stops now, compacts, continues [213].
**Recorded, and note the strength of it:** "повинен бути механізм, який гарантовано робить цю дію".

### R1-09 — A silent session · SETTLED (delegated to the orchestrator)
"Агент сам повинен це вирішувати, тобто він дивиться, перевіряє ті сесії, які він запустив, які в них
прогрес, що вони там зробили, тощо так далі. І відповідно до цього діє" [231], "оркестратор, для
цього є щоби вирішувати ці питання та врегульовувати" [234, 236].
**Recorded:** no fixed timeout ladder. The orchestrator judges progress of the sessions it started
and acts. (No mechanism named — see challenges.)

### R1-10 — The orchestrator itself dies · SETTLED in three parts
- Health check is configurable: "запускати якогось агента раз в N годин на якійсь іншій підписці"
  [246]; the check must be reliable/deterministic, and fallbacks to other providers must exist so
  one provider's failure does not leave the run stopped [255, 266] — "має бути щось, що може
  допомогти запустити ран і продовжити роботу без участі в налаштуваннях користувача".
- **Single-orchestrator invariant** [300–302]: "не може бути такого, що вже якісь існуючі
  оркестратор і спускається наступний, тому що тоді це буде просто нескінченний цикл оркестраторів
  … має бути якісь лог файлів, коли що запустилось … якщо раптом одночасно два якісь оркестратори
  працюють, то це не окей. Це треба відслідковувати і не дозволяти."
- "Start over" means **restart the orchestrator, not redo the work** [300].
- Recovery sources [293, 307]: default = state files; additionally previous sessions and their
  transcripts; the user configures which options are allowed and the orchestrator picks.
- Per platform [310]: recovery mechanism configured separately — transcripts for Claude Code and
  Codex, "можливо, там використання якогось скіла" elsewhere; the user may write their own skills.

### R1-11 — Visible terminals · SETTLED
"можна конфігурувати, що щось буде невидимо, наприклад самому код-коду, запускати його в headless
режимі. Але з цим треба бути дуже обережним … тільки інтерактивні сесії, або тільки headless …
або гібрид … Під кожну платформу своє налаштування" [324].
Plus: "оркестратор може робити інтерактивність з сесіями, наприклад … якщо він раптом використовує
ask user question, то оркестратор може відповідати на ці питання, і це повністю окей" [324] — within
configured authority [325].

### R1-12 — Reaching the trunk · SETTLED
"людина може як налаштувати, що це має автономно робитися … або ж, що це обов'язково передається на
людину … не порушується правило, якщо, наприклад, в репозиторії … можна зробити тільки пул
реквести … оркестратор має за можливості гіта, а саме те, що там можна піари стакати" [331].
Settings default/project/per-run, "приблизно по такому самому флоу, як це працює зараз в [GSD]".
**No universal gate** — "не має конкретного обмеження, як це саме повинно працювати" [334].

### R1-13 — Proving that work really happened · SETTLED (delegated to the process)
"оркестратор повинен діяти відповідно тому сетапу, який в нього є. Якщо в нього get shit done, то
[він] сам робить verification. Якщо в нього щось власне, то ці всі перевірки відбуваються виключно
так, як юзер налаштував … не роби обмеження те, що вся робота потім буде мати тести" [344].
**Recorded:** verification belongs to the configured process. The orchestrator imposes no checks of
its own. (The evidence behind the question — a merge that did nothing, a truncated suite read as a
pass — was explained [342] and did not change the answer.)

### R1-14 — Autonomy and escalation · SETTLED in four parts
- Two run modes [062]: **controlled** — anything critical or doubtful goes to the human immediately
  and the work holds ("хардстоп … поки людина не відпустить"); **autonomous** — the agent may
  choose under uncertainty and reports the decision afterwards ("він прозвітовує, про те, що було
  таке от рішення").
- Mode selection [075]: config supports three values — ask before every run, always autonomous,
  always controlled — and the mode is overridable per run.
- Whether the agent may decide at all is itself a setting, **and so is the basis it decides on**
  [082, 087, 092, 094]: user-written rules and examples of past decisions ("tone of voice" —
  "людина створила tone of voice своїх рішень … майже замість неї може відповідати"), previous
  answers to similar questions, or the agent's own knowledge of the project.
- Even in an autonomous run the agent may force a stop: "Якщо агент вирішив, що це точно має бути
  хардстопом … відбувається хардстоп, і йдеться до людини, навіть якщо це автономний ран" [082].
- **OPEN, by the owner's instruction** [082]: the exact definitions of controlled and autonomous —
  "це потрібно, щоби агент, який буде колектити ці результати, проаналізував і запропонував мені
  варіанти для цього".

### R1-15 — The red line · SETTLED
"є сенс добавити в архітектуру якийсь текстово писані правила, які не можна порушувати … ці
виключення повинні читатися в обов'язковому порядку всіма … Достатньо лише одного файлу, який може
доповнюватись, текстописний … На окремо якогось обов'язкової процедури для цього не треба … технічні
обмеження середовища користувач за потреби налаштовує сам" [357].
**Recorded:** one text file, mandatory reading for every agent. No enforcement machinery in the
plugin. (This is the direct opposite of the evidence presented in the question — see challenges.)

### R1-16 — Not touching what it did not start · PARTIAL, deliberately
Two cases named [370]: work in **another project/folder**, and **the owner's own parallel work in
the same folder**. "оркестратор має бути якось селфевернес, що він, до чого він може змінювати …
він би не мав зупиняти якісь там тести, які не він запускав" [366]. Explicitly **against**
heavy isolation: "я не хочу якихось детерміністського варіанту для цього, тому що він буде дуже
складний оверінжиринг, але дуже якісь простий та надійний варіант … має бути прописаний в плагіні"
[370].
**Owner's instruction** [378, 381]: after collect, a **Fable agent** takes the whole session context,
analyses this question and comes back with options to choose from.

### R1-17 — Notifications · SETTLED
"людина може налаштувати, що буде якийсь канал для зв'язку, наприклад, телеграм, слек, джімейл …
може бути навіть умовно якийсь дзвінок … Чи це сповіщення будуть тільки просто в терміналі … Людина
налаштовує, які типи можуть приходити" and the orchestrator "повинен лише переконатися, що це
працює" [395].

### R1-18 — Adopting an existing tool · SETTLED
"Інші сервіси я можу обрати тоді, коли я переконався, що він працює краще, ніж мій у всіх аспектах.
Тому зараз скажу, що превентивно я буду обирати свій варіант" [403].

---

## Additions raised outside the list (Д-series, all in the same session)

- **Д1 — Config precedence. SETTLED.** Follow the rules of his own Claude marketplace for <company>:
  "там є відповіді на ці питання" [416]. (That is `<baseline-marketplace>`: six config
  slots, three levels, personal beats committed.)
- **Д2 — Work added mid-run. SETTLED.** Picked up if ready by the configured process's rules; a
  description-sufficiency check and a "needs review"-style marker are **OPEN** [422, 424].
- **Д3 — End of the run. SETTLED.** No ready work left → finish. On finishing, stop **what it
  started** — sessions, docker containers, services — "щоби не залишати хвостів", without touching
  anything else [430].
- **Д4 — Worktrees. SETTLED.** Configurable and aligned with the chosen process (GSD has its own
  workspaces); **default recommendation: every task in its own worktree off the main branch**, with
  the environment variables and services it needs verified as ready [433].
- **Д5 — Repeated failure. SETTLED.** Three identical failures → act per configuration: notify
  through the configured channel and stop, or just stop; deciding anything beyond that needs the
  user's permission [442].
- **Д6 — Waiting does not block the queue. SETTLED.** Independent tasks continue. The user may
  configure **one channel for questions, clarifications, confirmations and review of finished
  work** — a local file, a GitHub issue with a tag, a task in the tracker — and the orchestrator
  watches it for changes and takes answers into account live, even when it is a different place
  from the task board [449].
- **Д7 — Only human-blocked work left. SETTLED.** Configurable; **default recommendation: stay and
  wait**. The user may change this behaviour **during** the run and the orchestrator must read and
  apply the change, overriding both the run's initial choice and the default [455, 458].
- **Д8 — A task's description changes mid-flight. SETTLED.** Watch the active task's source (local
  file or remote ticket). **Which model does the watching is configurable** — "немає сенсу
  перевіряти фейбл моделю … чи змінився якийсь тікет" — a cheaper subagent is the suggested shape.
  Silent when nothing changed; reports what changed when something did [466].
- **Д9 — The change contradicts finished work. SETTLED.** Prefer a **new ticket** for changes to
  work already done. Mid-execution the reaction is configurable: adapt now, stop and restart,
  finish then open a new ticket, or let the orchestrator choose [482].
- **Д10 — Restart with executors still alive. SETTLED.** The orchestrator analyses what those
  sessions are and decides to stop or wait, within its permissions [497].
- **Д11 — Status output. SETTLED.** "оркестратор не повинен нічого виводити для мене … якщо я хочу
  отримати статус виконання, то я можу запустити окремий термінал, прописати orchestrator двокрапка
  статус" [508]. Default: minimal output and minimal tokens spent on it; configurable [512, 514].
- **Д12 — Manual pause and stop. UNRATIFIED — the session ended here.** Two commands named first,
  then three [520, 524]: `stop-hard`, `stop-soft`, `stop-custom`, where custom means "прочитати що
  це означає і відповідно зробити" from user-written text rules or commands. Mechanism: the command
  writes into **the file the orchestrator reads every tick**, and the change is applied on the next
  tick. The interviewer recorded it as open: "Доповнення до Д12 отримано; підтвердження залишається
  відкритим" [525].

---

## Cross-cutting requirements that appear again and again

1. **Everything is configurable, at three scopes** — global default, project, this run — and a
   change made *during* a run must be picked up (Д7, R1-07, Д12).
2. **The control file.** A single file the orchestrator re-reads on a tick carries account
   assignments (R1-07), stop commands (Д12), and behaviour overrides (Д7). The questions channel
   (Д6) is a second such file, user-placed. Nothing in the answers says these are the same file.
3. **Soft / hard as a general vocabulary.** It appears for limits (R1-06), context (R1-08), account
   changes (R1-07) and stops (Д12) — always: hard = act now, soft = at the next safe boundary,
   custom = read the user's own rule.
4. **The orchestrator decides** where the owner declined to specify a rule: silence (R1-09),
   restart hygiene (Д10), conflicting updates (Д9), what to stop at the end (Д3).
5. **Verify before you run.** Account switching (R1-07), notification channel (R1-17), board
   statuses (R1-04), worktree environment (Д4) — each must be proven working before the run, not
   assumed.
6. **Cost-awareness as a first-class setting.** Cheap models for watch duties (Д8), minimal output
   (Д11), supervision on a separate account (R1-07).

---

## Explicit instructions the owner gave about what happens after this session

- **I1 [182–184]:** the collector must test every requirement for feasibility per platform and
  raise each divergence as its own question.
- **I2 [082]:** the collector must analyse and propose concrete definitions of "controlled" and
  "autonomous" runs.
- **I3 [378, 381]:** a Fable agent must take the whole session context, analyse the boundary
  question (R1-16) and return options to choose from.
- **I4 [408]:** he expects more grilling — he asked for further questions because "є ще контекст,
  яким я би хотів поділитися".

## Interview-mechanics defects observed (own the fix before round 2)

- The voice layer **repeated the same question 2–6 times** in a row [339, 350, 399, 465, 481, 504],
  which the owner called out three times [400, 426, 475]. Written text was
  correct; the spoken rendering duplicated it. Round 2 must not reproduce this.
- Several confirmations were spoken while the owner was still talking [259–265, 275–278], so a
  restatement landed on half an answer.
- The interviewer twice mislabelled an item (R1-07 used for a state-keeping question) [188, 190].
