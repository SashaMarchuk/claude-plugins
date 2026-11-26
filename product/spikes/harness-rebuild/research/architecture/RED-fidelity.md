# RED-fidelity — the specs audited against the owner's own words

**Date:** 2026-09-19. **Scope:** `SPEC-adapters`, `SPEC-cli`, `SPEC-config`, `SPEC-engine`,
`SPEC-repo`, `SPEC-safety`, `SPEC-state`, `SPEC-work` — read in full or in every section that names an
owner item — against `round-1/ANALYSIS-01.md` and, where the analysis and the transcript differ,
against `round-1/TRANSCRIPT-01.md`.

**Method.** Every requirement in `ANALYSIS-01.md` (N1–N2, R1-01…R1-18, Д1…Д12, the six cross-cutting
requirements, the four instructions I1–I4) was located in the specs by owner-item id, by key name and
by quoted Ukrainian. Requirement-id occurrence counts were taken mechanically across the eight specs.
Every Ukrainian quotation below was re-read at its transcript row today; the row number is the line
anchor in `TRANSCRIPT-01.md`.

**Evidence tags.** **VERIFIED** — read in the spec or the transcript on this machine today.
**CLAIMED** — a document asserts it and I did not re-derive it. **INFERRED** — my reasoning.

**What this document is not.** It is not a review of whether the designs are good. Every finding below
is a place where a spec says something other than what he said, says nothing where he said something,
or decides by default something he reserved. Where a spec already flags its own deviation, that is
recorded and the severity is lowered — but a deviation flagged in one spec and contradicted in another
is still a defect, because an implementer cannot build both.

---

## Summary table

| # | Owner item | Finding | Severity |
|---|---|---|---|
| F1 | R1-03 | The one key he said must be his has three different defaults in three specs; two invent a process for him | **blocker** |
| F2 | R1-07, Д7, Д12 | The control file exists in two incompatible designs — two names, two formats, two locks, one of them a utility verified absent | **blocker** |
| F3 | cross-cutting | Five mutually exclusive "this table is the contract" defaults registers, in five namespaces, with conflicting values and conflicting exit codes | **blocker** |
| F4 | R1-14, I2 | The two run modes are an undefined string with almost no behaviour; his explicit instruction to propose definitions is unfulfilled; `ask` is dropped from the CLI | **blocker** |
| F5 | R1-11 | Two specs default to the headless posture he warned about, against a third that defaults the other way | high |
| F6 | R1-15 | The file that needed "no separate mandatory procedure" becomes a hard start gate in one spec and a warning in another | high |
| F7 | R1-16 | The place he refused a deterministic mechanism by name receives the most deterministic mechanism in the set | high |
| F8 | Д4 | The half of Д4 he stated twice — «постійно переконуватись» about env and stack — ships as an empty list in two namespaces | high |
| F9 | R1-09, R1-06 | `lane.max_seconds: 3600` contradicts the only measurement in the set and takes a judgement he gave the orchestrator | high |
| F10 | R1-02, R1-14, Д7 | The shipped defaults, compounded, produce a system that cannot run unattended — and `authority.autonomous_ops: ["*"]` defaults the one thing R1-02 reserves | high |
| F11 | Д6 | «місце визначається користувачем. Крапка» is given a silent default in one spec and asked in two others | medium |
| F12 | R1-01, R1-18 | Neither id occurs anywhere in any spec; R1-01 has no key at all and is replaced by a plugin-owned run verdict | medium |
| F13 | R1-06.3 | The configuration-time research duty is recorded as unratified and then implemented nowhere | medium |
| F14 | Д12 | An unratified vocabulary is hard-coded into three specs; only one keeps it as a table | low |
| F15 | Д11 | Five commands and a PATH shim he never asked for; two of the five are self-flagged | low |

---

## F1 — R1-03: the one key he said must be his has three defaults, and two of them invent a process

**blocker · implemented differently than stated · DEFAULT decides what he configures**

**What he said** [118], VERIFIED:

> «І так, цей оркестратор, він діє **відповідно своїм конфігум**. І людина може налаштувати, чи це
> буде відповідно до правил ГЕТШЕД … Або там може бути, наприклад, суперпауерс, або будь-що інше.
> Тобто, людина може налаштувати, як саме воно буде працювати … або ж налаштовується повністю свій …
> комбінувати але, ні, **комбінувати ні, тут або або**, або свій, або вже готовий, **якщо готовий, то
> який саме**»

**What the specs do.** Three specs ship three different answers to "what happens when he has not said
which process":

| Spec | Key | Default | What the run does |
|---|---|---|---|
| `SPEC-config` §4.3, §7.1 gate 2, §9 | `engine.kind` | **none — the one key with no default** | wizard with a TTY; **exit 3** without one |
| `SPEC-engine` §4.4 step 2, §17 | `process.kind` / `process.engine.id` | `engine` / **`none`** | *"**not an error**: … which means 'the unit of work is the platform's own session and nothing is declared'. Emit `engine.resolved` with `id: "none"` and **continue**"* |
| `SPEC-repo` §12.6 | `engine.id` | **`gsd`** | rationale, verbatim: *"The engine he names most often"* |

`SPEC-config`'s own rationale for refusing to default it is the correct reading and it is in the
document: *"inventing one would be the plugin owning the process, which he forbade."* `SPEC-repo` then
invents it, and `SPEC-engine` invents a null process — «the platform's own session» is itself a
process, chosen by the plugin, for a run where he chose nothing.

**Why it breaks fidelity.** Under `SPEC-repo`'s register the walking skeleton runs GSD on a project
where he expressed no preference; under `SPEC-engine`'s it runs a bare session with no steps and no
checks, and the oracle then returns `indeterminate` on every lane. Either way the plugin decided the
process. That is the exact thing [118] forbids, and it is decided in a defaults table rather than
in front of him.

**Smallest fix.** Delete the `gsd` and `none` defaults; adopt `SPEC-config`'s rule verbatim in all
three specs (no default, wizard with a TTY, exit 3 without one). If the walking skeleton needs a value
to demonstrate, it sets it in the skeleton's own fixture config, not in the shipped register.

---

## F2 — R1-07 / Д7 / Д12: the control file is specified twice, incompatibly

**blocker · implemented differently than stated**

**What he said.** [195] (R1-07), VERIFIED: role→account assignments live in a file the orchestrator or
the context watcher keeps re-reading, «Можливо, там, наприклад, по даті», carrying a **soft** or
**hard** type. [458] (Д7): «якщо я хочу, щоб прямо зараз це працювало по-іншому … оркестратор
повинен це зчитувати та приймати … навіть якщо на початку я обрав інший варіант». [520]/[524] (Д12):
the stop command writes into **the file the orchestrator reads every tick**, and the change is applied
on the next tick.

This is `ANALYSIS-01`'s cross-cutting requirement 2, and it is the single surface three separate
decisions of his depend on.

**What the specs do.** Two designs, neither reconciled:

| | `SPEC-config` §5 | `SPEC-state` §2.2/§3.2/§7.1, `SPEC-cli` §3.4/§3.8/§3.9, `SPEC-repo` §11, `SPEC-work` A.5 |
|---|---|---|
| File | `control.yaml` | `control.json` |
| Format | YAML, strict vendored subset, ~150-line parser (§5.8) | JSON |
| Model | **declarative document** — `revision`, leaf-diff against `control.applied.json`, flat dotted `overrides:` map, "deleting a key restores the layer below" | **append-entry log** — `entries: []`, *"applied exactly once by id"*, then *"moved to `control.applied.ndjson`"*, entries carry `verb`/`scope`/`apply` |
| Reply | `control.ack.json` | `control.ack.json` (the one thing they agree on) |
| Lock | **lock directory** — §5.4: *"**There is no `flock(1)` on this machine**"* (VERIFIED today), *"So the lock is a directory, not a flock"* | `SPEC-state` §2.2 line: **`control.lock  flock target for writers of control.json`** |

`SPEC-work` §4.1 independently VERIFIES the same absence: *"`flock(1)` is **absent** on this machine —
not on `PATH`, not in `/usr/bin`, not in `/opt/homebrew/bin`."* So `SPEC-state` specifies a writer
protocol built on a utility two sibling specs proved does not exist here.

There is a second, quieter collision: `SPEC-config` §14 Q1 asks him *«YAML тут чи JSON?»* as an open
round-2 question, while four sibling specs have already shipped JSON and written commands against it.
A question that another spec has already answered is not an open question; it is a spec that has not
been read.

**Why it breaks fidelity.** The mechanism is *his* — he specified it in three separate answers. An
implementer reading `SPEC-config` and an implementer reading `SPEC-cli` build two products that cannot
see each other's stops. The declarative and append-entry models are not variants: deleting a key
restores the layer below in one and is a no-op in the other; a repeated stop is idempotent in one and
re-fires in the other unless a trip file exists.

**Smallest fix.** Pick one. The append-entry model matches [524]'s own description («команда пише в
файл, який оркестратор читає кожен тік») more literally than the declarative one; the declarative one
is the only one that implements Д7's «навіть якщо в мене в дефолтній налаштуванні інше» as a
precedence layer. They can be unified — entries for directives, one `overrides` document for values —
but that reconciliation is not written anywhere today. Whatever is chosen, delete the `flock` line.

---

## F3 — Five "this table is the contract" registers, five namespaces, conflicting values

**blocker · implemented differently than stated · DEFAULT decides what he configures**

Five specs each open a defaults register with the same sentence — *"This table is the contract.
Nothing outside it may invent a default at runtime"* — and each mandates a build-time test that walks
the source for literal fallbacks and fails on one that is not a row in **its** table:

`SPEC-config` §4 (test §11.1) · `SPEC-engine` §17 (lint §16.4.1) · `SPEC-adapters` §14 (graft G6) ·
`SPEC-repo` §12 (test `O-31`) · `SPEC-safety` §10 · plus `SPEC-work` §12.2 and `SPEC-cli` §10, which
are registers without the exclusivity claim. `SPEC-cli` §10's closing paragraph makes the fracture
explicit by listing "keys owned by sibling specs" **in `SPEC-repo`'s spelling** (`concurrency.max_lanes`,
`failures.repeat_threshold`, `red_lines.path`, `trunk.policy`) — none of which exist in `SPEC-config`.

### 3a. One value he stated aloud is overridden without acknowledgement

[171], VERIFIED: «людина може лише налаштовувати хард ліміти, хардстопи, коли якийсь ліміт, наприклад,
там, **80% тижневого** … Якщо це софт стоп, наприклад, **80 відсотків**, то агент може ще почекати».

| Spec | `capacity.soft_pct` |
|---|---|
| `SPEC-config` §4.7 | `80` — rationale: *"**his own number** [171]"* |
| `SPEC-repo` §12.3 | `80` — *"**His own number** [171]. Not proposed — stated"* |
| `SPEC-adapters` §14 | **`85`** — rationale: *"room to finish a step"* |

Two specs correctly mark 80 as not-a-proposal. `SPEC-adapters` ships 85 with no note that it is
overriding a number he said. That is the cleanest single instance in the set of a DEFAULT-PROPOSED
quietly replacing a value of his.

### 3b. The exit-code tables contradict each other, and two claim to be the only one

`SPEC-config` §7.1: *"Exit-code table, **used by every command in this plugin**"*.
`SPEC-state` §9: *"**One table, stable, never inferred from anything.**"*

| Code | `SPEC-config` §7.1 | `SPEC-state` §9.1 | `SPEC-safety` §6.9 | `SPEC-engine` §16.1 |
|---|---|---|---|---|
| 3 | missing required config | `finished` after `stopping` — **the owner stopped it** | — | — |
| 4 | — | `degraded` | — | — |
| 5 | split brain | `blocked` (only human-blocked work left) | — | — |
| 6 | — | ended `paused` on capacity | **`degraded`** | — |
| 65 | validation | run file malformed | `orc_destroy` refused | contract violation |
| 70 | **preflight refused** | internal software error | teardown unassertable | environment |
| 71 | another orchestrator | — | — | — |
| 75 | lock timeout | **fencing failure** | **residue collision, refused to start** | — |
| 77 | — | **preflight refused** | — | — |
| 78 | config unparseable | config error | **preflight refusal** | — |

`degraded` is 4 and 6. Preflight refusal is 70, 77, 78 and 65. "Another orchestrator holds the lock"
is 71 in one spec and 69 in two others. Exit 3 means "you forgot a config key" in one and "your stop
worked" in another. A morning script, a doctor and a `launchd` wrapper cannot all be right.

### 3c. Run state lives in five places, and one of them is ruled out by a sibling's measurement

| Spec | Run-state root |
|---|---|
| `SPEC-config` §5.1, `SPEC-state` §2.1 | `${ORCHESTRATOR_STATE_DIR:-$HOME/.orchestrator}` |
| `SPEC-repo` §12.1 | `orchestrator.home: $HOME/.orchestrator` |
| `SPEC-work` §1.2 | `${ORCHESTRATOR_STATE_DIR:-$HOME/.local/state/orchestrator}` |
| `SPEC-adapters` §14 | `<config-root>/shared/orchestrator/state` |
| `SPEC-safety` §3.2 | `<config-root>/orchestrator/state` |

`SPEC-repo` §4.2 gives a VERIFIED reason against the `<config-root>` form: `CLAUDE_CONFIG_DIR` is a
profile switcher's profile directory on this machine and the account switcher works by moving it, so run state
under `<config-root>` moves with the profile. That is not a style preference — R1-10 [246] requires a
health check *«на якійсь іншій підписці»*, and a doctor on the other account resolves a different
`<config-root>` and finds no run at all. Two specs put run state exactly there.

### 3d. Same concept, different key names — an incomplete list

| Concept | `SPEC-config` | `SPEC-repo` / `SPEC-cli` | `SPEC-engine` | `SPEC-work` | `SPEC-adapters` | `SPEC-safety` |
|---|---|---|---|---|---|---|
| lane ceiling (R1-05) | `lanes.max` | `concurrency.max_lanes` | — | — | `concurrency.max` | — |
| three failures (Д5) | `failure.identical_limit` / `.action` | `failures.repeat_threshold` / `.action` | `failures.identical_threshold` / `.on_exhausted` | — | — | — |
| worktree owner (Д4) | `worktree.owner` | `worktree.enabled` | `branching.owner` | — | — | `boundaries.worktree` |
| red lines (R1-15) | `redlines.path` | `red_lines.path` | — | — | — | `redlines.path` |
| readiness (R1-04) | `tickets.ready_requires` | `tickets.ready_requires` | — | `tasks.ready_requires` | — | — |
| local registry dir | `.orchestrator/tickets` | `.orchestrator/tickets` | — | **`.orchestrator/items`** | — | — |
| trunk (R1-12) | `delivery.mode` / `.evidence` | `trunk.policy` / `delivery.assert_landed` | — | — | — | — |

### 3e. Conflicting values on the same concept

| Concept | Values |
|---|---|
| `adapter.verify_max_age_hours` | `null` = never (adapters) · **`0` = verify at every run start** (repo) · `24` (config) · **`0` = not gated at all** (engine §17). The same literal `0` means opposite things in two registers |
| stop-ack timeout | `90` s (cli §10, repo §12.8) · **`20` s** (config §4.10 `stops.ack_timeout_s`, "two polls") |
| judge calls per hour | `12` (repo §12.5, cli §10) · **`30`** (config §4.12) |
| context refill alarm | `15` %/h (config, adapters) · **`20`** %/h (repo) |
| capacity poll | `capacity.poll_min_seconds: 3600` (config, adapters) · **`capacity.cache_seconds: 900`** (repo) |
| worktree at finish | `remove_on_done: false` (config §4.5, repo §12.6 — *"removing a tree with uncommitted work"*) · **`boundaries.worktree_on_finish: remove`** (safety §10) |
| Д9 mid-execution | `behaviour.on_change_mid_execution: **orchestrator**` (config §4.10, citing [482]'s first-listed option) · `change.on_contradiction: **finish_then_new**` (work §10.5, which explicitly rejects `auto` because it *"needs a model call on every change"*) |
| doctor (R1-10) | `doctor.enabled: **true** when a distinct account resolves` (config §4.9) · `**false**` (repo §12.8) · `**auto**` (cli §10) · `sentinel.interval_hours: 0` = off (repo §12.5) |
| intake cap (Д2) | `tickets.intake_cap: 0` unbounded (config) · `intake.cap: 20` when capped (work) · `tickets.max_claims_per_run: 0` (repo) |

**Why it breaks fidelity.** `ANALYSIS-01`'s cross-cutting requirement 1 is that everything is
configurable at three scopes. Configurability is only real if a key has one name and one value. As
written, the mandated tests contradict each other: the `SPEC-engine` lint fails the build on
`lanes.max`, the `SPEC-config` test fails it on `process.kind`, and both are required.

**Smallest fix.** One register, one file, one namespace, in the plugin repo, with each row citing the
owner item and the spec that owns the behaviour. Every spec's table becomes a view of it. This is not
a refactor of the designs; it is the deletion of four tables.

---

## F4 — R1-14: the two run modes have no definition and almost no behaviour; I2 is unfulfilled

**blocker · silently dropped**

**What he said** [082], VERIFIED, and it is an instruction, not an answer:

> «Одне з субтих питань, які ти можеш мене запитати, **що таке контрольований, що таке автономний
> ран. І в мене поки немає відповіді. Це потрібно, щоби агент, який буде колектити ці результати,
> проаналізував і запропонував мені варіанти для цього.**»

`ANALYSIS-01` records this as **I2**, one of four explicit instructions about what happens after the
session. And [062] states the behaviour the definitions have to carry: controlled → «вони йдуть зразу
до мене і ставлять умовного хардстоп … це на паузі, поки людина не відпустить»; autonomous → «агент не
впевнений на сто в цьому варіанті, то він його може обрати. Але потім **він прозвітовує**».

**What the specs do.** Across all eight specs, `run.mode` is read in exactly two places:

- `SPEC-engine` §6.2 step 2: *"If `run.mode = autonomous` and `start.autonomous` is declared, use it"* —
  i.e. it picks `/gsd:autonomous` instead of `/gsd:execute-phase`.
- `SPEC-cli` §5.1: `status.json` carries a `mode` field.

Nothing else. No spec defines what counts as «якісь критичні речі» or «сумніви». No spec defines what
«поки людина не відпустить» means mechanically — which lane states hold, what releases them. No spec
defines what «прозвітовує» produces (`SPEC-state` §4.3 has a `reported` flag on a decision record and
one sentence saying it *"implements R1-14 [062]"*, with no report artifact). No spec proposes options
for the definitions, which is what he asked for.

A grep for `R1-14` across the eight specs returns nine hits, of which six are cross-references and
three are the `run.mode` row itself.

**And one of his three values is dropped.** [075] names exactly three: «Перше, це кожного разу
запитуватись. Друге, це постійно автономний. Третє, це постійно контрольований.»

- `SPEC-config` §4.6 / §8.1: `run.mode: ask | autonomous | controlled` ✓
- `SPEC-cli` §3.2: `--mode <m>` is documented as `controlled | autonomous`
- `SPEC-cli` §5.1 `status.json`: `mode` enum is `controlled | autonomous`

So the surface he actually types at and the document he actually reads both lost `ask` — the value
that carries «перед кожним раном треба … задати питання юзеру».

**Why it breaks fidelity.** R1-14 is the flagship distinction of the whole interview and it is
currently a string. An implementer building to these specs ships a system in which switching to
`autonomous` changes one slash command and nothing else. The owner's own instruction — analyse and
return options — is the one instruction of the four that nothing discharges.

**Smallest fix.** Round 2 cannot ask him to ratify definitions that nobody drafted. Draft two or three
concrete definitions (what classes of decision escalate, what holds, what the report contains) as
options and put them in front of him; restore `ask` to the CLI and to `status.json`.

---

## F5 — R1-11: two specs default to the posture he explicitly warned about

**high · implemented differently than stated · DEFAULT decides what he configures**

**What he said** [324], VERIFIED:

> «можна конфігурувати, що щось буде невидимо, наприклад самому код-коду, запускати його в headless
> режимі. **Але з цим треба бути дуже обережним.** … Наприклад, тільки інтерактивні сесії, або тільки
> headless сесії … або гібрид, або переважно інтерактивні і тільки інколи headless … **Під кожну
> платформу своє налаштування** … Основа в тому, що це можна налаштовувати.»

**What the specs do.**

| Spec | Key | Default | Consequence |
|---|---|---|---|
| `SPEC-config` §4.11 | `runtime.<platform>.visibility` | `mostly_interactive` | faithful; explicitly names `ARCH-minimal`'s headless-first as *"its largest deviation"* |
| `SPEC-repo` §12.7 | `attach.enabled` | `false` | *"**Headless-first.** Takeover of a running headless lane is a handoff and costs one restart"* |
| `SPEC-safety` §3.6, §10 | `spawn.transport` | `process` | *"**The owner cannot watch a lane in a terminal window or type into it**"* |

`SPEC-safety`'s reason is honest and technically strong — `osascript`-spawned sessions are iTerm2's
children, which is exactly why the previous generation reached for `pkill -f` (FIELD-NOTES §11.8). But
it is the plugin's convenience, and it converts his default «переважно інтерактивні» into "never
interactive" as a shipped value, on the one axis where he attached a warning.

The three keys also do not compose: `runtime.claude-code.visibility: interactive` with
`spawn.transport: process` is contradictory, and no spec says which wins.

**Smallest fix.** One key, `runtime.<platform>.visibility`, with `spawn.transport` derived from it and
the lineage cost printed at preflight rather than taken by default. Default `mostly_interactive` per
`SPEC-config`.

---

## F6 — R1-15: the file that needed no mandatory procedure becomes a hard start gate — in one spec

**high · more elaborate than he asked for · two specs contradict each other**

**What he said** [357], VERIFIED, and note the closing clause:

> «Має бути якісь визначене місце, де може людина додавати якісь **різного типу** обмеження … Також
> якщо людині потрібно якісь додаткові різні обмеження, то вона це може робити, власноруч
> налаштовуючи своє середовище … **На окремо якогось обов'язкової процедури для цього не треба.
> Достатньо лише одного файлу, який може доповнюватись, текстописний** … **Але, так, це максимум**»

**What the specs do.**

| | `SPEC-config` §7.1 gate 15 | `SPEC-safety` §2.6, §10 |
|---|---|---|
| Red-line file absent | **warn** — *"R1-15 makes the file optional; **it is his decision**"* | **`redlines.on_unreadable: refuse` → preflight refuses, exit 78** |

So under one spec a fresh install runs; under the other it cannot start until he has written
`RULES.md`. That is precisely «окрема обов'язкова процедура», which the sentence rules out, arriving
as a default in the spec that owns the file.

Two further defaults in `SPEC-safety` §10 decide the content of his own file for him:

- `redlines.untagged_type: **never**` — a plain bullet he writes as a preference is executed as an
  absolute prohibition. `SPEC-safety` §2.3 flags the four-value vocabulary as its own and §12 Q4 asks
  about the untagged default, which is correct — but the shipped behaviour still reads his sentences
  in the strongest possible sense by default.
- `redlines.max_bytes: 8192` + `redlines.on_oversize: **refuse**` — appending the rule that crosses
  8 KiB refuses the run, on a file he described as «який може доповнюватись».

**What `SPEC-safety` gets right and should be kept.** §1.1 restores two things `ANALYSIS-01` dropped
from [357] — «різного типу» and «це максимум» — and cites the transcript for both. That is the right
kind of correction and it is why the type grammar exists at all. The problem is not the grammar; it is
that three of its defaults fail closed on a requirement whose whole content was "nothing mandatory".

**Smallest fix.** `redlines.on_unreadable: warn_and_proceed` and `on_oversize: truncate_and_notify` as
shipped defaults, with the fail-closed values available; align `SPEC-config` gate 15 and `SPEC-safety`
§2.6 on one behaviour; `redlines.untagged_type: prefer` or leave it unset and ask at W§10.

---

## F7 — R1-16: he refused a deterministic mechanism by name; he gets the most deterministic one in the set

**high · more elaborate than he asked for**

**What he said** [370], VERIFIED:

> «перший кейс … я працюю з іншим, наприклад, іншою папкою, іншим проектом, то цей оркестратор, він
> цього не має трогати. Другий кейс, якщо, наприклад, в тій самій папці я паралельно працюю над
> чимось … він цього не має зупиняти. І це має бути чітко описано. Тобто, ну, це просто, типу, **я не
> хочу якихось детерміністського варіанту для цього, тому що він буде дуже складний оверінжиринг, але
> дуже якісь простий та надійний варіант** для цього має бути прописаний в плагіні»

and [373]: «Чи якоїсь конфіг… Я би не сказав, **я би це робив якось абстрактно**».

**What the spec does.** `SPEC-safety` §3 ships, for this requirement:

- an append-only ownership registry with three line kinds (`intent` / `created` / `resolved`), the
  `intent` line written **before** the resource exists and `fsync`ed;
- seven resource types, each with a non-recyclable identity tuple — `(pid, pid_start, argv_sha256)`,
  `(pgid, leader_start, argv_sha256)`, compose project name **plus** three labels, worktree path plus
  branch plus `base_sha`;
- a per-type teardown op drawn from a closed set, each with its own proof probe;
- `CLOCK_MONOTONIC` beside the wall clock on every line, plus a sleep fence: `sleep.gap_seconds: 60`,
  `sleep.grace_seconds: 120`, during which *"no resource may be judged absent"*;
- a single destructive code path with five numbered refusal rules (§3.8);
- six build-failing lints (§3.9);
- and §4's six-rung enforcement ladder with sandbox keys, a Docker fork with three values, and a
  per-platform posture table across twelve platforms.

**The counter-argument, which is in the spec and is fair.** §1.2 shows that what he was offered at
[364]/[365] and refused was «окреме середовище, з якого він узагалі не має доступу» — a container or a
VM — and that «оверінжиринг» was said about *that*, not about a ledger. It also correctly notes that
the clause `ANALYSIS-01` treats as settled — "no complex technical isolation mechanism" — is the
interviewer's and was never confirmed. Most of §3 is also justified by **Д3**, which is SETTLED and
does require knowing what the run created.

**Why it is still a finding.** Three things:

1. He asked, two rows earlier [366], for the simple variant by name: «в оркестратори **прописаний
   шлях, до чого він має доступ**» — a path list. Nothing ships that as the mechanism; the path list
   appears only as `boundaries.write_roots: []` under a sandbox that is off.
2. §3 is presented as covering R1-16 (§5.1, §5.2 Part 1 cite it directly), so the requirement whose
   answer was "simple and abstract" is discharged by the most machinery in the specification set.
3. **I3 is only half discharged.** [378]/[381]: «агент … візьме весь контекст цієї сесії,
   проаналізує це питання і поверне варіанти для вибору». `SPEC-safety` §4.1 does produce a ranked
   six-option table with costs — that is the right artifact. But it also ships a default for every
   rung, so the options arrive already decided, and §5.2 Part 3 states plainly that the case he
   actually named second is **not covered by any of them**.

**Smallest fix.** Keep §3 and attribute it to Д3, where it belongs. Present §4.1's ladder as the I3
deliverable with **no shipped default** on `boundaries.sandbox` — preflight prints the table and the
question, as §4.3 already proposes — and add the path-list rung he named at [366] as its own row.

---

## F8 — Д4: the clause he stated twice ships as an empty list

**high · silently dropped**

**What he said** [433], VERIFIED:

> «Дефолтна пропозиція, щоби абсолютно все виконувати в різних ворк трі. **І постійно переконуватись,
> що всі ті енвайрмент верібли, які потрібні, вони запущені** відповідно … Тобто так, щоби це ворк
> трі був з головної гілки, з потрібними енвайрмент веріблами, тощо, **або що є якісь запущений
> стек**»

Two obligations, not one: a worktree per task off main, **and** continuous proof that its environment
and its stack are up.

**What the specs do.**

| Spec | Key | Default |
|---|---|---|
| `SPEC-config` §4.5 | `worktree.env_proof` | `[]` — preflight only *warns* when empty |
| `SPEC-engine` §17 | `branching.required_env` | `[]` — *"inventing required variables for an unseen project is exactly the overreach N2 forbids"* |
| `SPEC-engine` §17 | `branching.stack_probe` | `null` — *"the orchestrator does not guess what stack a project needs"* |

Both rationales are reasonable in isolation and both are true: the plugin cannot know which variables
a project needs. But the net effect is that the shipped configuration verifies **nothing** about
environment or stack, on the clause he added twice in one breath, while the same specs ship
`assertions.enabled` with all seven on and `redlines.on_unreadable: refuse`. The things he did not ask
for default on; the thing he asked for defaults off.

`SPEC-engine` §10.4 does specify the per-lane health loop properly (four `git` calls plus the declared
probes, per tick, no model) — the mechanism exists. It simply has nothing to run.

**Smallest fix.** Make `worktree.env_proof` a **wizard-required** answer at W§6 whenever
`worktree.enabled` (i.e. always, under Д4's default), with "nothing to prove" as an explicit, recorded
answer rather than an empty default. Same for `branching.stack_probe`. One question at 22:41 beats a
silent no-op at 03:00, and it is the shape [133] already authorises: *"use what is there, ask for what
is missing"*.

---

## F9 — `lane.max_seconds: 3600` contradicts the only measurement in the set and takes a judgement he gave away

**high · DEFAULT decides what he configures**

**What he said** [231], VERIFIED (R1-09): «**Агент сам повинен це вирішувати**, тобто він дивиться,
перевіряє ті сесії, які він запустив, які в них прогрес, що вони там зробили … І відповідно до цього
діє.» `ANALYSIS-01` records it as **no fixed timeout ladder**.

**What the spec does.** `SPEC-adapters` §14: `lane.max_seconds: **3600**` — *"a lane with no terminal
event in an hour is a defect, not a long tail."*

**The measurement, from a sibling spec.** `SPEC-engine` §17, `steps.default_timeout: 60m`: *"Measured:
a worker session per phase ran **58 min – 3 h 20** (FIELD-NOTES §6); 60 min is a floor a user will
raise deliberately."*

So on the only distribution anyone measured, a one-hour lane wall clock terminates most real lanes.
And `SPEC-repo` §11 WS-11 shows the correct handling of the same signal: a silent lane becomes an item
on a fact sheet and *"nothing is nudged"* — the judge decides. `SPEC-adapters` bypasses that entirely
with a hard kill.

`SPEC-state` §9.2 code 3 (`reason: "timeout"` — *"the external wall-clock timeout fired"*) wires the
lane wrapper to it, so this is not an inert key.

**Smallest fix.** Either raise it well past the measured tail (`4h`) or, better, make it `null` and let
the judge own it, which is what [231] says and what `SPEC-repo` already builds.

---

## F10 — The shipped defaults compound into a system that cannot run unattended

**high · DEFAULT decides what he configures**

No single default below is indefensible; each has a stated rationale. The finding is that **no spec
names their compound effect**, and the compound effect decides the product's character.

| Key | Default | Spec |
|---|---|---|
| `run.mode` | `controlled` | config §4.6, repo §12.1 |
| `run.mode_when_no_tty` | `controlled` | config §4.6 |
| `authority.may_decide` | `false` | config §4.6 |
| `authority.basis` | `[]` | config §4.6 |
| `questions.authority` | `refuse_and_escalate` | config §4.11, adapters §14 |
| `behaviour.when_only_human_blocked` | `wait` | config §4.10, work §12.2, repo §12.8 |
| `behaviour.wait_max_minutes` | `0` (forever) | config §4.10 |
| `questions.default_deadline_hours` | `0` (never) | work §12.2 |
| `process.on_indeterminate` | `needs_review` | engine §17 |
| `status.during_run` | `silent` | config §4.11 |

A fresh install, on the shipped defaults: the first uncertainty becomes a question; the question has
no deadline; the agent may not decide; the run waits forever; and nothing is printed. That is a
correct reading of each individual answer of his and a wrong reading of the product — he is building
an **unattended overnight orchestrator**, and [062] describes the autonomous run as a first-class mode,
not an opt-in.

**And one default decides the exact thing R1-02 reserves.** [107], VERIFIED: «**людина повинна сама
налаштовувати, що саме вона може віддавати на автономне виконання, а що взагалі ні**».
`SPEC-config` §4.6 ships `authority.autonomous_ops: **["*"]`** — *everything* is delegable — with no
rationale for the permissive direction (the neighbouring row's "he called it a restriction, not a
requirement" argument is written for `accounts.<id>.roles`, not for this key). So the one list he said
he must write himself defaults to "all", while the permission that governs whether it is ever consulted
(`authority.may_decide`) defaults to `false`. Both directions are decided, in opposite senses, by
defaults.

**Smallest fix.** Print the compound at preflight in one line — *"this configuration will park on the
first question and wait indefinitely; nothing will be printed"* — and make `authority.autonomous_ops`
a W§5 question with no default rather than `["*"]`. Both are consistent with [133]'s "ask for what is
missing".

---

## F11 — Д6: «місце визначається користувачем. Крапка» gets a silent default in one spec

**medium · DEFAULT decides what he configures**

**What he said** [449], VERIFIED, closing the answer: «Це може бути що завгодно, і це може
конфігуруватись. Це також може бути як github issues, з якимось окремим тегом, або це може [бути
таска в таск менеджері] … І це може бути налаштовано інше, аніж … таск менеджер, який використовує
оркестратор. Тобто **місце визначається користувачем. Крапка**.» And, in the same answer, the mechanism
he wants: «А **ми йому можемо задати питання**, чи хоче він якийсь єдиний канал».

**What the specs do.**

| Spec | Key | Default |
|---|---|---|
| `SPEC-config` §4.1 | `connectors.questions.use` | `{kind:"file", path:"<project>/.orchestrator/QUESTIONS.md"}` |
| `SPEC-work` §12.2, §9.2 | `questions.channel` | **no default value; preflight asks once** — *"The question is asked once, the answer is written to his own config file, and it does not come back"* |
| `SPEC-repo` §12.8 | `questions.channel` | unset → preflight asks once |

`SPEC-config`'s reason is real (OWNER-DECISIONS 6.1: a plugin must run with no config at all). But he
closed this item with the word «Крапка» and named asking as the mechanism, and `SPEC-work` implements
both. A silent default here is the clearest case in the set of a DEFAULT-PROPOSED occupying ground he
explicitly reserved.

**Smallest fix.** Adopt `SPEC-work`'s handling: offer `<project>/.orchestrator/QUESTIONS.md` as the
suggested answer at W§9, record what he picks, and do not resolve it silently. Zero-config still runs,
because the wizard runs.

---

## F12 — R1-01 and R1-18 occur nowhere in any spec

**medium · silently dropped**

A mechanical grep for the requirement ids across all eight specs returns **zero** occurrences of
`R1-01` and **zero** of `R1-18`. (Every other id occurs at least once; R1-03 occurs 25 times, Д1 89.)

### R1-01 — what a finished run must leave behind

[062], VERIFIED: «І щодо питання, типу що має статися, щоби зранку щось було успішно, **це все
залежить, як людина це налаштувала власноруч, тобто конкретної якоїсь вимірюваної штуки тут не може
взагалі бути** … могло не виявитися когось з доступу, або ще щось, і ран зупинився, **і це не означає,
що це помилка в нас** … Ми повинні переконувати, що це працює, що цей плагін виконує свою роботу.»

Two obligations follow: (a) the success definition is a **user configuration**, and (b) an external
stop must not read as the plugin's failure.

Neither is implemented. A grep for any `run.success*` / `success_criteria` key across the eight specs
returns nothing — there is no key by which he states what a finished run must leave behind. Instead
`SPEC-state` §3.2 and §9.1 ship a plugin-owned terminal vocabulary (`finished | degraded | blocked |
aborted | refused`) whose predicates are the plugin's own, and `SPEC-safety` §6.4 adds that *"any
`failed` makes the run `degraded`"* on a teardown assertion. And obligation (b) is inverted at
`SPEC-config` §7.1 gate 8 / `SPEC-adapters` §11.2: an account whose switch can no longer be proven —
which is «не виявилося когось з доступу», his own example — refuses the run with a non-zero exit and a
`refused` terminal state.

This may be the right engineering. It is not what he said, and no spec records the gap.

### R1-18 — adopting an existing tool

[403]: «Інші сервіси я можу обрати тоді, коли я переконався, що він працює краще, ніж мій у всіх
аспектах. Тому зараз скажу, що **превентивно я буду обирати свій варіант**.»

`SPEC-repo` §10 adopts `acpx@0.17.0` on `ADOPTION-VERDICT`'s recommendation. In substance the handling
is careful and probably passes: it is **opt-in** (`platform.default_adapter: claude`), it is one legal
value of an adapter's `launch.sh`, the dependency is pinned with `acpx.on_version_drift: refuse`, the
exit path is costed at under an hour, and test `O-47` pins that the string `acpx` appears nowhere in
`bin/`. But the requirement it has to clear is never named, in the one place in the specification set
where an external tool enters the design. A reader checking "did we honour R1-18" has nothing to grep.

**Smallest fix.** Add an R1-01 section to `SPEC-cli` or `SPEC-state` that (a) introduces a
user-supplied success statement — even if it is only prose carried into `report.md` — and (b) separates
`refused-because-the-world-changed` from `refused-because-the-plugin-is-wrong` in the exit table. Add
one paragraph to `SPEC-repo` §10 citing R1-18 and stating why opt-in clears it.

---

## F13 — R1-06.3: the configuration-time research duty is recorded as unratified and then implemented nowhere

**medium · silently dropped**

**What he said** [189]–[192], VERIFIED in the narrow form at [189] and expanded immediately after: at
configuration time the agent researches what the chosen process already records, agrees with the user
what is actually needed, and **explains why it is asking** — «він має чітко пояснити, чому він це
запитує». `ANALYSIS-01` records the GSD assumption («майже нічого не треба робити») as *an assumption
to verify*.

**What the specs do.** The explanation half is implemented well: `SPEC-config` §6.2 requires every
wizard question to carry a `why` string drawn from the key's rationale, and §11.3 tests it. The
**research** half is not. `SPEC-engine` §1 marks *"the config-time research duty [191]/[192]"* as
**UNRATIFIED** and then never returns to it; `SPEC-config` §4.3 ships `engine.accounting:
reference | supplement | own` with default `reference`, asked at W§2 as a plain three-way question.
Nothing inspects what the chosen engine records before proposing an answer — even though
`SPEC-engine` §5.6's `records` point is exactly the machinery that would tell it, and §13 demonstrates
reading GSD's `STATE.md` frontmatter live.

**Smallest fix.** W§2 runs the engine's declared `records` and `identity` points before asking, and
shows what it found: *"GSD already records X, Y, Z; the orchestrator will reference those and add
nothing. Correct?"* That is his sentence, and the probes already exist.

---

## F14 — Д12's unratified vocabulary is hard-coded into three specs

**low · self-flagged in one place**

Д12 is the one item `ANALYSIS-01` labels **UNRATIFIED** outright: «Доповнення до Д12 отримано;
підтвердження залишається відкритим» [525].

`SPEC-repo` §12.8 handles this correctly by shipping `stop.verb_map` as data — *"a round-2 change to
his vocabulary must be a table edit, not a rewrite"*. The other three do not: `SPEC-cli` §3.4–§3.6
ships three named commands, `SPEC-config` §5.3/§5.6 ships a `stop:` section with `verb`/`custom`/
`scope` plus validation rules V3 and V9 written around those verb names, and `SPEC-state` §3.2 ships
`control.stop_now` / `control.stop_boundary` as cause codes in the run state machine.

`SPEC-config` §12.12 lists Д12 among the unratified items and says *"Nothing whose vocabulary is
unratified should be built before round 2 re-confirms it"* — which is the right rule, stated in the
document that also hard-codes it.

**Smallest fix.** Adopt `SPEC-repo`'s `stop.verb_map` everywhere; the three commands become three rows.

---

## F15 — Commands and a PATH shim he never asked for

**low · more elaborate than he asked for**

**What he said** [508], VERIFIED: «оркестратор не повинен нічого виводити для мене … якщо я хочу
отримати статус виконання, то я можу запустити окремий термінал, прописати orchestrator двокрапка
статус і таким чином я отримую статус теперішнього … **І це все, що треба**.» Plus the `config` verb
[133] and the three stops [520]/[524].

`SPEC-cli` §3 ships twelve commands. Four are his (`config`, `run`, `status`, the three stops count as
three); `resume` follows from R1-10. Invented: **`add`**, **`ask`**, **`report`**, **`sync`**,
**`remove`**, plus `shim.install: ask_once` writing an executable to `~/.local/bin/orchestrator`.
`SPEC-cli` §11.6 flags `sync` and `remove` as *"commands he never asked for"* — correct, and the same
flag is owed to `add` and `ask`.

This is low severity because each is cheap and none changes a decision of his. It is listed because
"І це все, що треба" is a ceiling he stated, in the same shape as «це максимум» at [357], and both
ceilings are currently exceeded without being quoted.

---

## Requirements confirmed faithfully implemented

Recorded so this document is not read as a verdict on the whole set. Each was checked against his
words, not against the analysis.

| Item | Where | Note |
|---|---|---|
| **N2** — not only code | `SPEC-engine` §14 (worked example B, no git, no tests), §11.1 test 3; `SPEC-work` §2.4 *"Deliberately not required: tests, a repository, a branch, a build"* | The strongest fidelity work in the set. `branching.owner: none` and the skipped-not-failed assertions are exactly [344] |
| **R1-13** — verification belongs to the process | `SPEC-engine` §2, §11.4's grep-for-absence lint | The forbidden-verbs lint is the right mechanism; both additions (§11 assertions, §8.4 self-attribution) are flagged three times each and asked at Q3/Q4 |
| **Д3** — stop only what it started | `SPEC-safety` §6, and §1.3's restoration of «оркестратори» as the **first** word of his teardown list, which `ANALYSIS-01` dropped | A correction of the analysis from the transcript, in his favour |
| **R1-15's dropped clauses** | `SPEC-safety` §1.1 restores «різного типу» and «це максимум» from [357] | Same shape as above |
| **Д8** — cheap model for the watch | `SPEC-work` §8.1's three tiers; the model is reached only after two deterministic filters | «нічого назад не поверне» achieved structurally rather than behaviourally, which is stronger than he asked for in the direction he wanted |
| **I1** — per-platform feasibility | `SPEC-adapters` §6 `requirements.json` + `plan.json.weakened[]`/`denied[]`, every row carrying `owner_item` | Discharges the instruction as given |
| **Д6's fallback field** | `SPEC-work` §9.1, `questions.require_fallback: true` | Grounded in 11-of-11 from his own production run |
| **R1-05's retraction** | `SPEC-config` §12.10 names `lanes.max_heavy` as touching the axis he retracted at [163] and offers `0` to disable | Correct handling of a retraction |

---

## The three things round 2 must not be asked until these are fixed

1. **F4.** He cannot ratify definitions of "controlled" and "autonomous" that nobody drafted. Drafting
   the options is I2 and it is the precondition for every question about run mode.
2. **F1 / F3.** Any question of the form "is this default right?" is unanswerable while the same key
   has three names and three values. One register first.
3. **F2.** `SPEC-config` §14 Q1 asks him YAML-or-JSON for the control file. Four sibling specs have
   already shipped JSON. Resolve it internally; do not spend a round-2 question on a disagreement
   between our own documents.
