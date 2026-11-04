# C2 — Configuration model, live overrides and the control file

**Cluster:** C2-config-control-plane · **Items:** Д1, Д7, Д12, R1-07 (single watched file), R1-04 (config lifecycle)
**Date:** 2026-09-19 (extended 2026-09-21). **Machine:** owner's Mac, darwin 25.5.0, APFS, node v22.18.0.
**Requirements source:** the owner's own voice interview — `../../round-1/TRANSCRIPT-01.md`, analysed in
`../../round-1/ANALYSIS-01.md`, cross-read in `../extract/`. `[NNN]` is a row in TRANSCRIPT-01.md.

**Evidence tags used throughout:**
**VERIFIED** — I read it in source/docs, or I ran it on this machine and report the result.
**CLAIMED** — a README, vendor doc or blog says so and I did not run it.
**INFERRED** — my reasoning from the above, labelled as mine.

**The owner's words are the source of truth here.** Where I disagree with a decision I say what it does not
answer or what it collides with. I never substitute a preference for his.

---

## 1. What the owner decided, quoted

### 1.1 Д1 — precedence comes from his own marketplace

> «Це треба робити відповідно до того, які є правила в клад маркетплейсі, який я робив для <company>,
> компанії <company>, я робив окремий клад маркетплейс, де я розбудував архітектуру о цих от доступів,
> тощо, так далі, і там є відповіді на ці питання. Наступне питання» — [416]

He named **no repository, no slot count and no rule**. He pointed at an artefact and said the answers are in
it, then closed the topic himself. ANALYSIS-01 appends *"(That is `<baseline-marketplace>`: six config slots,
three levels, personal beats committed.)"* — that identification is the analyst's, not his.

**I checked the identification. It is right, and I read the artefact.** VERIFIED at
`<baseline-marketplace>/docs/config-levels.md` and
`requirements/OWNER-DECISIONS.md`. §2.1 below is what it actually says.

**Ratification:** the interviewer's restatement at [417]/[418] was never answered — the owner had already said
«Наступне питання» at [416]. `../extract/corrections.md:99` files Д1 as unratified.

### 1.2 R1-07 — one file, watched, and changes carry a type

> «Так, потрібно, і це має бути налаштовано через єдиний файл, який оркестратор чи контекст вочер постійно
> дивиться і перевіряє, чи там були якісь зміни, тощо. Можливо, там, наприклад, по даті, перевіряти, коли він
> був змінний, або ще так далі, і відповідно цього робити.» — [195]

In English, the rest of the answer: every change carries a type, soft («наступні завдання перенести») or hard («прямо вже зробити і зупинити»).

Three things, and they are not equally firm:

1. **One file, polled continuously.** Firm. Note he says **«оркестратор чи контекст вочер»** — *which of the
   two* does the polling is left open, and that matters against the single-orchestrator invariant at [300].
2. **mtime is a hedge, not a decision.** «**Можливо**, там, **наприклад**, по даті». ANALYSIS-01 records this
   as "(mtime named as the mechanism)", which `../extract/corrections.md:61` calls a mis-statement, and I
   agree. **The mechanism is open.** §3 is my measured answer to it.
3. **A change carries a type: soft = next tasks, hard = now, stopping current work.** Firm as vocabulary.
   Never ratified as a rule — the parent restatement of that same hard/soft vocabulary for limits (R1-06) was
   asked at [176]/[177] and answered only with «Повтори, будь ласка» (`corrections.md:86`).

And the account-switching addition, ratified at [199]:

> «при конфігурації треба буде… явно пояснити, як саме може відбуватися зміна акаунтів. І для кожної платформи
> це окремо треба пояснювати… це може бути як зміна через те, щоб використовувати інший API ключ, або зміна те,
> що треба використовувати інший акаунт підписки… Наприклад, в моєму випадку це перемикач профілів, який використовує різні
> профілі… перед запуском потрібно переконатися, що це працює, щоби це не було проблемою для користувача» — [199]

The referent is **a profile switcher**. VERIFIED on this machine: one is installed, and its profiles live at
`~/.<switcher>/profiles/<name>/`. §3.6 is what that means for config.

Plus the role allowlist he flagged himself as important, ratified at [279]:

> «коли людина налаштовує провайдери, які використовують та акаунти, вона може вказувати, для чого вони можуть
> використовуватись. Наприклад, що може використовувати тільки для оркестратора, щось може використовуватись
> тільки для екзек'ютора… І це важливий дуже нюанс» — [270]

### 1.3 Д7 — a live edit beats both the run's own choice and the default

> «Це може налаштовуватися користувачем, по дефолту я б рекомендував, що він залишається та чекає на мої
> відповіді» — [455]

> «Тобто, якщо я хочу, щоб прямо зараз це працювало по-іншому, аніж був запущений оцей оркестратор, то це
> окей, оркестратор повинен це зчитувати та приймати. **Це також, і це дуже важливо.**» — [458]

In English, the rest of the answer: if he wants the orchestrator to wait for his answer instead of stopping the run, that holds even if he chose otherwise at the start or the default says otherwise.

This is the load-bearing sentence of the whole cluster. **A mid-run edit outranks the run's start-time choice
AND the stored default.** He marks it «дуже важливо» himself. Unratified ([460]/[462] → [463], `corrections.md:102`).

### 1.4 Д12 — the stop commands write into the polled file

> «Я думаю, що декілька команд, конкретно дві це стоп хард а друге це стоп софт. І... це як окремий скіл
> точніше окрема команда до цього плагіна, для того, щоби зупинити.» — [520]

In English, the rest of the answer: he first proposed one command with a soft flag, and the command writes hard or soft stop into the file the orchestrator polls, which reads it on the next tick.

> «Також думаю що це має бути 3 варіанти, stop-hard, stop-soft, stop-custom що означає прочитати що це
> означає і відповідно зробити. Там користувач може налаштувати що це таке та яка зупинка буде.» — [524]

In English: the custom variant may hold prose rules or commands.

Two self-corrections inside this: one-command-with-a-flag → **two commands**; "skill" → **command of this
plugin**. Then three commands after the session resumed by text. `stop-custom` may be satisfied by **prose
rules or by shell commands** — two different execution models under one name.

**Д12 is the one item the interviewer itself left open:** «Доповнення до Д12 отримано; підтвердження
залишається відкритим» [525].

### 1.5 R1-04 — the config lifecycle

> «… коли вона робить просто ран, то система починає щитувати чи є якісь налаштування глобальні, або на
> проєкті, і відповідно цього дії. Якщо чогось немає, то оркестратор задає ці питання для того, щоби їх
> покрити.» — [133] · **ratified at [133]**

In English, the rest of the answer: the user configures at first run or with separate config commands without running; this is already the existing architecture of his Claude marketplace, so it is fine as a requirement.

Read on a run: **global + project**, use what is there, ask for what is missing. He is explicitly *not*
commissioning new architecture — he is pointing at one that exists.

### 1.6 Д6 — the questions channel is a second, user-placed file

> «людина може налаштовувати собі якийсь єдиний канал для питань. … щоб, грубо кажучи, в лайв режимі я
> міг це прийти і це переглянути, і я розумів, що це скоро потрапить в оркестратор та будуть задійні
> відповідні дії щодо цього» — [449]

In English, the rest of the answer: with the previous harness he made a single file himself and told the orchestrator to append every question, unresolved point, clarification, ready decision awaiting confirmation, and implemented decision needing review; the orchestrator must watch the file for changes; the place is user-defined (GitHub issues with a tag, a task-manager task, or a local file).

Two things ANALYSIS-01 does not record and `../extract/outside-list.md` does:
**this is not speculative — he already built and ran it by hand**, and he states a **latency and
acknowledgement expectation** («я розумів, що це скоро потрапить в оркестратор»). I found that hand-built
channel on disk and read its protocol; it is §2.8.3 below, and it is better than anything I would have
proposed.

### 1.7 The constraint that governs every proposal below

Four times, on four different items, he asked for the simple thing:

> «тут нічого надприроднього не потрібно вигадувати» [171] · «це має бути дуже простий процес» [189] ·
> «це має бути надійна річ, дуже проста» [300] · «я не хочу якихось детерміністського варіанту для цього,
> тому що він буде дуже складний оверінжиринг, але дуже якісь простий та надійний варіант» [370]

`../extract/outside-list.md` §12.1 flags this as a design constraint on the whole build, recorded in
ANALYSIS-01 only as a local remark on R1-16. I have treated it as binding, and §5 proposes the cheap
mechanism over the clever one wherever the measurements allow.

---

## 2. How the world does it

### 2.1 His own marketplace — `<baseline-marketplace>` (VERIFIED, read on this machine)

`docs/config-levels.md`, `docs/config-levels.json`, `shared/scripts/resolve-config.mjs`,
`requirements/OWNER-DECISIONS.md`.

**Six slots, three bands, highest wins:**

```
slot 6  ./.claude/shared/plugins/<plugin>.local.json    personal project band  (highest)
slot 5  ./.claude/shared/identity.local.json            personal project band
slot 4  <config-root>/shared/plugins/<plugin>.json      user band
slot 3  <config-root>/shared/identity.json              user band
slot 2  ./.claude/shared/plugins/<plugin>.json          project committed band
slot 1  ./.claude/shared/identity.json                  project committed band (lowest)
```

Two axes: **band first** (committed < user < personal-project), **specificity second** inside a band
(per-plugin beats general). `<config-root>` = `CLAUDE_CONFIG_DIR` verbatim when set, else `~/.claude`.

The rules worth carrying over, each VERIFIED in that document:

- **Merge semantics.** Objects deep-merge key by key. One exception: `use` is replaced as one whole value.
  `never` accumulates as a sorted, deduplicated union. Anything else: highest slot that sets it wins.
- **A veto key.** `never` removes a candidate from consideration and accumulates across a person's own files;
  a committed-project `never` holds against everything **except** a tool one of the person's own files names
  in `use`. This is the closest existing analogue to R1-15's prohibition file, and ANALYSIS-01 omits it.
- **Atomic writes and a lock, spelled out.** A write "takes a lock at `<destination>.lock`, the path every
  other writer of that file uses, and releases it however the write ends; re-reads the file once the lock is
  held and merges into that read; preserves every key it does not recognise at every depth…; and **replaces
  the file atomically, by a temporary file in the same directory renamed over the destination**. A reader is
  never blocked by a write, never sees a half written file, and a write killed before the rename leaves the
  previous file intact." And: "**The lock is a recommendation; the destination is not.**"
- **The owner's own words behind that**, `OWNER-DECISIONS.md` 4.11: *"Yes, this .lock and so on is needed for
  simultaneous modification"*.
- **Unknown keys cost only themselves.** "One unknown key never costs more than itself. The rest of the file
  loads, the source the key sits in resolves from its remaining keys, and no config ever fails over one key."
  Unknown keys warn; `x-`-prefixed keys are accepted and merge normally.
- **A file in the wrong place is not silently inert** — it emits one warning naming the file.
- **A missing file is an empty slot**, and resolution is deterministic: identical inputs, identical output.
- **The resolver never writes.** VERIFIED in code: `resolve-config.mjs` imports only `existsSync, readFileSync`
  from `node:fs`. Every atomicity and locking rule above is prose the *agent* must obey, with nothing enforcing it.
- **Precedence finishes before availability.** If the winning value names a tool that is not present, the
  resolved value is still that tool; `fallback` (`ask` | `auto` | `skip`, default `ask`) decides from there.
- **Default write destination is the person's own file at the user level, never the project's.** An agent
  writes no committed project file. A write into a layer a higher layer would shadow is announced first.

**And what it does not have.** I grepped `OWNER-DECISIONS.md` for a per-run scope, live reload, watching, or
mid-run override. **There is nothing.** The design is read-once-per-invocation: *"On every invocation, the
agent executing a plugin reads the resolved config before that plugin performs any of its own work"* (§9), for
a plugin invocation that lasts seconds. It also closes the level count: *"These three levels are the whole
set… A resolver supports no other level"*, and 3.6 says of the level he removed: *"do not build it, do not
reserve a path for it, do not mention it as an option."*

**This is the central finding of the cluster, and it is a question for him, not a correction:** Д1 points at a
design that answers global-vs-project precedence completely and says nothing at all about the two things the
orchestrator actually needs — **a "this run" scope, and a config that changes while a 34-hour process is
running.** See §6 Q1.

### 2.2 Claude Code's own settings (VERIFIED — `code.claude.com/docs/en/settings`, fetched 2026-09-19)

Precedence, highest first:

1. **Managed settings** (`managed-settings.json`, MDM, console)
2. **Command line** — `claude --settings`, *"for one session"*
3. **Project local** — `.claude/settings.local.json`
4. **Shared project** — `.claude/settings.json`
5. **User** — `~/.claude/settings.json`

Mechanisms worth stealing:

- **Live reload is the default and it is documented as such:** *"Claude Code watches your settings files and
  reloads them when they change, so it applies most edits to the running session without a restart, including
  edits to `permissions`, `hooks`, and credential helpers such as `apiKeyHelper`."*
- **A change hook.** *"Claude Code runs the `ConfigChange` hook for each settings-file change it detects"*,
  matchers `user_settings`, `project_settings`, `local_settings`, `policy_settings`, `skills`. This is a
  ready-made audit/notify point.
- **A documented split between live keys and start-pinned keys.** *"Claude Code reads some keys only once, at
  session start, so an edit to one of them doesn't reach the running session"* — `model`, `effortLevel`,
  `modelSettings`. **And each start-pinned key is given a runtime command as its live channel**: `/model`,
  `/effort`. That is exactly the shape of Д12: the file is the state, the command is the way to change it now.
- **A watch-registration caveat, admitted in the docs:** *"Claude Code also loads a settings file you create
  mid-session if its folder existed when the session started."* Watches bind to directories.
- **A four-tier invalid-config policy**, and the tiers differ on purpose:
  - *Settings Error* — whole file invalid → interactive dialog: fix with Claude's help, exit, or continue
    without the broken settings.
  - *Settings Warning* — individual entries invalid → *"Claude Code skips those values and keeps the rest of
    the file in effect."*
  - *Managed settings* — invalid entries *"fall back to a stricter value until you fix them."*
  - *Configuration error* — `~/.claude.json` unparseable → copied to
    `~/.claude/backups/.claude.json.corrupted.<timestamp>`, offer to reset; and *"copy back one of the five
    most recent `.claude.json.backup.<timestamp>` files… which Claude Code saves before it writes the file."*
  - **The unattended path fails open:** *"A `-p` run shows no dialog… Claude Code skips the broken file or
    values and continues with the rest."* For an orchestrator, that is the dangerous branch — §4.3.
  - **The security tier fails closed** (stricter value). *Fail open for preferences, fail closed for
    restrictions* is the principle, and it is worth adopting verbatim.
- **Lists merge instead of overriding**, with named exceptions where order carries meaning
  (`fallbackModel` is an ordered chain, so *"Claude Code takes the whole value from the highest-precedence file
  that defines it"*). Relevant to the orchestrator's own model OR-chains.
- **A stricter-wins escape from the top tier:** *"For a few security-sensitive keys, Claude Code honors a
  stricter value from a lower level over a managed value."*
- **Environment variables are not a level.** *"which one applies is decided per pair, not by level"*.
- **An honest limitation:** `/status` lists which files loaded but *"doesn't show which file supplied each
  key"*; `claude doctor` lists rejected entries. Worth beating — §5.4.

**The divergence he needs to see.** Claude Code puts the home-folder **User** file at the *bottom*; his own
marketplace puts the user band *above* the committed project band. Both agree personal-project beats
shared-project. They disagree about the home folder, and Д1 points at one of them while the orchestrator lives
inside the other. §6 Q2.

### 2.3 OpenAI Symphony — `SPEC.md` (VERIFIED, downloaded 2026-09-19, 2312 lines)

This is a normative spec for exactly the problem, and §6.2 is the best single answer I found:

> Dynamic reload is REQUIRED:
> - The software MUST detect `WORKFLOW.md` changes.
> - On change, it MUST re-read and re-apply workflow config and prompt template without restart.
> - The software MUST attempt to adjust live behavior to the new config (for example polling cadence,
>   concurrency limits, active/terminal states, codex settings, workspace paths/hooks, and prompt content for
>   future runs).
> - Reloaded config applies to future dispatch, retry scheduling, reconciliation decisions, hook execution,
>   and agent launches.
> - Implementations are not REQUIRED to restart in-flight agent sessions automatically when config changes.
> - Implementations SHOULD also re-validate/reload defensively during runtime operations (for example before
>   dispatch) in case filesystem watch events are missed.
> - **Invalid reloads MUST NOT crash the service; keep operating with the last known good effective
>   configuration and emit an operator-visible error.**

And §13.6, which is the snapshot rule stated as a MUST:

> Tool specs, adapter selection, and effective tracker settings MUST be bound to one session snapshot. **A
> workflow reload applies to future sessions; it MUST NOT make an in-flight session advertise one provider and
> execute another.**

Validation is split in two (§6.3): **startup validation fails startup**; **per-tick dispatch validation**
*"skip[s] dispatch for that tick, keep[s] reconciliation active, and emit[s] an operator-visible error."*
So a bad edit mid-run stops *new work* and leaves *supervision* running. That is the right shape for Д12's
soft stop, and it is stronger than anything the previous harness does.

Note the belt-and-braces admission: **watch events are expected to be missed**, so re-validate on the tick anyway.

### 2.4 Sortie (CLAIMED — `docs.sortie-ai.com`, fetched 2026-09-19)

Same family: a `WORKFLOW.md` with YAML front matter plus a prompt template, *"Sortie watches this file"*, and
*"Changes to the workflow are applied without restart."* The docs do **not** state the detection mechanism,
what happens to in-flight sessions, or how an invalid edit is handled. Treat as a second data point that
live reload is the expected behaviour in this class of tool, not as a design source.

### 2.5 Gas Town — `ESTOP` (VERIFIED, source read via `gh`, `internal/estop/estop.go`, `internal/cmd/estop.go`, `internal/daemon/daemon.go`)

The closest existing thing to Д12, and it solves the exact bug the previous harness has.

- **A sentinel file `ESTOP` at the town root**, plus per-scope `ESTOP.<rigName>`.
- **The content carries who, when and why:** `Activate` writes `trigger \t RFC3339-timestamp \t reason \n`,
  with `TriggerManual = "manual"` and `TriggerAuto = "auto"`.
- **The gate is existence; the content is only metadata.** `IsActive` is `os.Stat` alone. A torn or
  unparseable file can never fail to stop the run.
- **A partial read fails safe.** `parse("")` returns `&Info{Trigger: TriggerManual}` — an empty file is read
  as a *manual* stop, the most restrictive interpretation.
- **An automatic clear cannot clear a human stop.** `Deactivate(onlyAuto=true)` refuses:
  `"E-stop was manually triggered — use 'gt thaw' to clear"`.
- **The coordinator is exempt:** *"The Mayor is exempt from E-stop so it can coordinate recovery"*, and in the
  command, *"The Mayor and overseer are exempt so they can coordinate recovery."*
- **Checked first, every tick, before anything else.** In `daemon.go`: *"The daemon stays alive (to maintain
  Dolt, etc.) but does NOT restart any agents. This prevents fighting the E-stop by auto-spawning sessions that
  were intentionally frozen."* → `if estop.IsActive(d.config.TownRoot) { … return }`.
- **Declaring and actuating are separate, and declaring always succeeds:** when tmux is unavailable it prints
  *"tmux not available — ESTOP file created but cannot freeze sessions"*.
- **A read-only status verb:** `gt estop status` — *"This is read-only and never freezes agents."* (matches Д11).
- **A third stop semantic the owner has not named:** sessions are frozen with **SIGTSTP**, *"Context is
  preserved — no work is lost"*, and `gt thaw` resumes. That is neither hard nor soft — it is *pause*. §6 Q5.
- **One gap:** `os.WriteFile(…, 0644)` is not a temp+rename. A reader can in principle catch a partial line —
  which is precisely why the fail-safe parse above exists.

### 2.6 ralphex (CLAIMED from `llms.txt`; the signal handler VERIFIED in source)

Chosen deliberately as the *opposite* model to Symphony.

- **Precedence is `local → global → embedded`, per file**, across prompts and agents:
  `.ralphex/` (project) → `~/.config/ralphex/` → compiled-in defaults.
- **Deletion cannot disable anything:** *"embedded defaults are always the baseline, so deleting an agent file
  does not disable it. To disable a specific agent, remove its `{{agent:name}}` reference from the prompt
  files, not the agent file itself."* The opposite of the marketplace's "a missing file is an empty slot".
- **The run scope is CLI flags**, and the global root is relocatable by env: `--config-dir`, `RALPHEX_CONFIG_DIR`.
  It also honours `CLAUDE_CONFIG_DIR` for alternate Claude installs.
- **Two different invalid-config policies, split by source:** invalid *CLI* combinations *"fail with a clear
  error at startup"*; *"Config-only conflicts (e.g., `executor = codex` plus `external_review_tool = codex`)
  are automatically resolved by forcing `external_review_tool = none`, with a warning printed to stderr."*
- **Schema evolution without migrations:** *"Users who customized `codex_limit_patterns`… keep their
  customization on update — comment the line out to inherit the new embedded default."* A user-set value
  survives an upgrade; commenting it out re-inherits. `--init` writes a config of **commented-out defaults**,
  so the file documents every key without setting one. `--upgrade` semantically merges new defaults into
  customised files.
- **No config hot reload.** Config is bound at start; what reloads every iteration is the **plan file**.
  *"The prompt file reloads the plan and specs cleanly every run, so the agent reads the current state of the
  files instead of a cluttered history of earlier attempts."*
- **The stop is a signal, not a file.** VERIFIED in `cmd/ralphex/break_unix.go`: `SIGQUIT` (Ctrl+\) on a
  buffered channel of size 1, drop-if-full, *"used for manual termination of review and task loops"*.
  **A signal needs a pid and a live terminal.** For an unattended run you walk back to in the morning, a file
  works and a signal does not — which is an argument *for* the owner's Д12 choice, not against it.

### 2.7 Kubernetes `AtomicWriter` (VERIFIED, `kubernetes/kubernetes` `pkg/volume/util/atomic_writer.go`)

The industrial answer to *"a change spanning several files must be seen as one change"*:

> AtomicWriter handles atomically projecting content for a **set of files** into a target directory. … The
> visible files in this volume are symlinks to files in the writer's data directory. Actual files are stored in
> a hidden timestamped directory which is symlinked to by the data directory. … This scheme allows the files to
> be **atomically updated by changing the target of the data directory symlink**. Consumers of the target
> directory can monitor the `..data` symlink … to receive events when the content in the volume is updated.

And the honest caveat, in the same comment:

> **AtomicWriter offers no concurrency guarantees and must be synchronized by the caller.**

Even the reference implementation pushes single-writer discipline onto the caller — which is exactly what the
owner already decided in `OWNER-DECISIONS` 4.11.

### 2.8 The previous generation, and the run that is on disk (VERIFIED)

#### 2.8.1 What `plugins/harness/` actually does

- **Precedence is two layers, and it runs the other way to the marketplace.** `hlib.sh:48-58`:
  `cfg <jq-path> <default>` → **project value, else user value, else default**. Project beats user. The
  marketplace ranks the user band *above* the committed project band. Both are the owner's; they disagree.
- **Per-key fallthrough, not a merge.** Each `cfg` call runs its own `jq` against each file in turn. There is
  no deep merge, no `never`, no `.local` file, no run scope.
- **Live reload already exists — by accident.** `cfg` is a function that reads the file on every call, and the
  watch loop calls it inside the tick (`harness-run.sh:225,237,368,400`). So `run.stall_minutes`,
  `limits.stop_at`, `guardrails.sonnet_trust_check` and `run.watch_interval_seconds` are **already** picked up
  mid-run. Nobody designed this and nothing documents it.
- **`schemaVersion` is decorative.** It is written into both config templates and **read by nothing** — zero
  references across `bin/`, `skills/`, `commands/`.
- **Validation happens once, at preflight, and the comment says what the failure costs.**
  `harness-run.sh:17`: `jq -e . "$PROJ/.harness/config.json" … || "INVALID: … is not valid JSON — every setting
  would silently revert to defaults"`. There is no equivalent check on a tick.
- **The STOP signal is a zero-content sentinel.** `hlib.sh:77,105` — `hstop_file()` is
  `<project>/.harness/STOP`, and `stop_requested()` is `[ -f … ]`. It carries no who, no when, no why, and
  **three different actors write it**: the owner's `/harness:stop`, the watch loop's `limits.stop_at`
  wind-down (`harness-run.sh:243-244`), and the supervisor's pause path.
- **`atomic_write` exists and is correct in shape** (`hlib.sh:156-160`): `mktemp` in the destination's own
  directory, `cat > tmp && mv tmp f`. It is used for `CURRENT` and little else; no fsync, no trap cleanup, and
  `mktemp`'s 0600 mode is inherited by the destination.
- **Credentials are kept out of config by an explicit refusal.** `harness-run.sh:32-38` refuses to start if any
  `accounts*.env_command` embeds `OAUTH_TOKEN=`/`API_KEY=`/`SECRET=`, because *"it would land in the launcher
  file and the validator prompt"*. `env_command` must be **a command that prints exports**, e.g.
  `<switcher> switch --print-env <profile-A>`, and the generated launcher `eval`s it at spawn.

#### 2.8.2 What the 34-hour run proved (`plugins/harness/docs/FIELD-NOTES.md`, validated against logs)

- **The unattributed STOP file cost real incidents.** §11.7: the supervisor's wall-clock pause fallback was
  pinned to a fixed past epoch, so an unreadable quota read resumed a paused run immediately (`#65`); the fix
  moved the epoch lookup between the two pause writes, so *"a restart landing in that window read `STOP` as a
  manual owner stop and exited instead of resuming"* (`#73`); and *"the `STOP` write is still unconditional on
  the marker write succeeding, so a failed marker write leaves an unattributed `STOP` on disk"* (`#82`, open).
  **Gas Town's `manual` vs `auto` prefix is the fix for all three.**
- **A shared file with two writers silently destroyed one of them.** §2.1: `state/attention` is rebuilt from
  scratch every cycle — `: > attention.tmp` then `mv attention.tmp attention` — so *"anything appended to that
  file by anyone else is destroyed within one watch interval."* The context watch wrote corrections there all
  night and found out by grepping for a block it had written four minutes earlier and getting nothing back.
  §11.3 records **`STALLED` raised against demonstrably healthy sessions eight or more times across about seven
  hours** because the corrections never persisted. The watcher prompt now carries a rule headed
  **"Never use `state/attention` as your channel."**
- **The questions channel forked into a worktree.** §12.5 and `ORCHESTRATION.md:489-494`: a lane running in a
  worktree wrote a real owner-facing question into *its own copy* of `docs/open/QUESTIONS.md`; the owner was
  told to open the main checkout's copy, where it was not. *"for an hour there were two."* Twenty-three journal
  entries were on the wrong side too. **This is the direct collision between Д6 (one file) and Д4 (every task
  in its own worktree), and it has already happened once.**
- **Unlocked id allocation collided every time.** §10.2 `J-T169-01`: two concurrent adds against a 272-ticket
  queue produced two files under one id **in five rounds out of five**; a twenty-way add produced twenty files
  under three ids. After a lock was added, two-, twenty- and fifty-way adds never collided.
- **An audit log recorded 26 refusal events that never occurred** (§12.7). An audit trail is not self-verifying.
- **A fix that lived only in the installed copy reverts on the next sync** (§12.6).
- The owner had already run a **manual soft pause** mid-run: `state/SOFT-PAUSE.md` (§10.1). Д12 is him
  formalising something he has done by hand.

#### 2.8.3 The hand-built questions channel — read it before designing a new one

`<work>/<work-project>/docs/open/{QUESTIONS.md, ANSWERS.md, README.md}`. VERIFIED by reading
the files. This is the «єдиний файлик» of [449], and it is a complete protocol:

- **Two files, one writer each.** Agents append to `QUESTIONS.md`. The owner writes `ANSWERS.md`.
  *"**It never edits `ANSWERS.md`.** The product owner's voice session writes that file and build sessions
  never write to it."*
- **Append-only, stable ids.** *"Append new blocks at the end. Never reorder, never delete."* Id shape
  `Q-<ORIGIN>-<NN>`.
- **Single-writer per record, not per file.** *"Only the session that wrote an entry changes its `Status`."*
  That is what makes concurrent appends safe.
- **Every question carries its own default.** The block format is
  `Origin / Status / Blocks / Fallback / Question`, and **`Fallback:` is what the orchestrator will do if the
  answer never comes.** A deferral is an answer: *"If the answer is a deferral — later, or I don't know — that
  is the answer. Take the fallback, set `Status` to `answered`, and record the fallback as the decision."*
- **A 60-second poll, and work continues meanwhile.** *"The waiting session re-runs that check every 60 seconds
  and works on anything unblocked in between."* Two signals are accepted as "answered" — a matching `## <id>`
  heading in `ANSWERS.md`, or a `Decision:` line in the entry itself — read by one `awk` one-liner.
- **Nothing is deleted.** A question that stops mattering gets `Status: dropped` and one line of why.
- **Absolute paths, main checkout, always** (`ORCHESTRATION.md:489`), *"whatever directory that lane is running
  in"*, and *"At merge, take the main checkout's version of both files whole."*

`ORCHESTRATION.md` also gives the fourth file and its rule: `.harness/supervisor/ORCH-HANDOFF.md`, the position
file, *"which only the orchestrator writes"*.

**So four channels already exist in practice, each with exactly one writer** — and `harness-state.sh` opens with
the same principle for state: *"the coordination triad: markers + heartbeats + decision/owner logs — three
channels, never one overloaded file."*

---

## 3. What is feasible on this machine — measured, not assumed

Everything in this section I ran. Scratch files under
`/private/tmp/claude-501/…/scratchpad/fstest/`.

### 3.1 mtime resolution is nanoseconds on APFS — but only if you ask for it

```
$ echo a > f.txt; stat -f '%m %Fm' f.txt   → 1789823984 1789823984.281298463
$ echo b > f.txt; stat -f '%m %Fm' f.txt   → 1789823984 1789823984.284078538
```

Two writes 3 ms apart. **The integer mtime is identical; the float mtime differs.**

| detector | two writes in the same second | verdict |
|---|---|---|
| `stat -f '%m'`, `date -r`, `find -newer` | **MISSED** | unusable for a control file |
| `stat -f '%Fm'` (APFS nanoseconds) | detected | usable |
| `shasum -a 256` | detected | usable |

**Concretely: the naive reading of the owner's own hedge — «по даті, перевіряти, коли він був змінний» with
second granularity — loses a stop command written in the same second as an earlier edit.** VERIFIED.

### 3.2 mtime also reports changes that did not happen

Rewriting a file with **identical content** moves its mtime (VERIFIED: float mtime moved, sha256 unchanged).
An editor that saves on a timer, a `git checkout` that touches the file, a sync tool — each produces a
spurious "the user changed the control file" event. **A content hash does not have this failure mode.**

### 3.3 `fs.watch` on a file path dies the first time the file is replaced atomically

This is the most important mechanical finding in the cluster. Four writes to one file, watched two ways
(node v22.18.0, macOS/FSEvents):

```
writes:  (1) in-place   (2) temp+rename   (3) in-place   (4) temp+rename

FILE watch on 'd/ctl.json' : ["change", "rename"]                      ← writes 3 and 4 produced NOTHING
DIR  watch on 'd'          : ["change:d", "rename:ctl.json" ×2,
                              "rename:.tmp", "rename:ctl.json" ×3,
                              "rename:.tmp2", "rename:ctl.json" ×2]    ← 10 events for 4 changes
```

- **Watching the file path and writing it atomically are mutually destructive.** The watch is bound to the old
  inode; after the first `rename` the watcher is deaf and *reports nothing at all* — no error, no close event.
  Since atomic writing is exactly what you must do (§3.4), a file watch is the wrong tool.
- **A directory watch sees everything but is noisy**: 10 raw events for 4 logical changes, including events
  for the temp files themselves, and a first event naming the *directory*, not the file. It needs both a
  name filter and coalescing. This is what debounce is for, and it is the only reason you would need debounce.
- Symphony's spec anticipates this exactly: *"re-validate/reload defensively during runtime operations … in
  case filesystem watch events are missed."*

### 3.4 Atomic replace works; in-place rewrite produces torn reads

300 writes of a ~2 KB JSON file while a reader ran `jq -e .` 400 times:

```
torn reads with temp+rename : 0 / 400
torn reads with in-place '>' : 1 / 400
```

One observation is a small number and I report it as such — but the direction matches the POSIX guarantee
that `rename(2)` within a filesystem is atomic, and matches both the owner's own marketplace rule and
`hlib.sh:atomic_write`. **In-place rewrite of a control file is a real hazard, and it is free to avoid.**

### 3.5 A torn read does not fail loudly — it silently returns every default

```
$ printf '{"limits": {"stop_at": 80}, "run": {"watch_int' > torn.json
$ jq -r '.limits.stop_at' torn.json
jq: parse error: Unfinished string at EOF at line 1, column 46
$ v=$(jq -r '.limits.stop_at' torn.json 2>/dev/null) || echo "READ FAILED -> falls through to DEFAULT"
READ FAILED -> falls through to DEFAULT
```

This is `hlib.sh:_cfg_read` exactly. **A control file caught mid-save makes every setting in that layer revert
to its built-in default for that tick, silently.** And because `cfg` is called per key, several times per tick,
a save straddling two `cfg` calls yields a **mixed** config: some keys real, some default, within one tick.
VERIFIED both by reading `hlib.sh:41-58` and by running it.

### 3.6 Locking: `flock(1)` does not exist on macOS; `lockf(1)` does and works

```
$ which flock  → not found
$ which lockf  → /usr/bin/lockf
$ which shlock → /usr/bin/shlock   (man page: "deprecated, and lockf(1) should be used instead")

$ ( lockf -t 0 lock.f sh -c 'sleep 2' ) &   ;   lockf -t 0 lock.f sh -c 'echo B'
lockf: lock.f: already locked           → rc 75
```

- `lockf` uses **BSD `flock(2)` semantics**, and the man page is explicit: *"the mere existence of the file is
  not considered to constitute a lock."* The lock is held by the kernel and **released when the holding process
  dies**, so a crashed writer leaves no stale lock. That is the property an unattended run needs.
- `shlock` self-heals stale locks by `kill(2)`-probing the recorded PID, but it is deprecated.
- Python's `fcntl.flock` is available if a writer is not a shell script.
- **A bare `.lock` *file* whose existence means "locked" is the one design to avoid** — it is precisely what
  strands a run when the writer dies. The owner's marketplace already says *"The lock is a recommendation; the
  destination is not."*

### 3.7 No file-watching CLI is installed

`fswatch` — not found. `inotifywait` — not found (Linux-only anyway). Watching therefore means either a node
process (§3.3, and it is the wrong tool) or polling.

### 3.8 Polling is free at this system's cadence

```
200 × stat                 → 0.508 s wall   (~2.5 ms each)
200 × stat + shasum -a256  → 3.400 s wall   (~17 ms each)
```

Ten control files hashed every tick ≈ **0.17 s**, against a 60-second tick: **~0.3 %**. The watch loop's real
cost is its own LLM context re-read, not `stat`. **There is no performance argument for FSEvents here**, and
polling is the simple, reliable variant the owner asked for four times (§1.7).

### 3.9 `find` inside a Claude Code session is not the `find` you tested

FIELD-NOTES §11.3 records: *"BSD `find -newermt "-10 minutes"` errors out, and with stderr routed to
`/dev/null` it returns empty every time — which would have declared every healthy session idle for ever."*

I reproduced the failure, and found the cause is **not** BSD find:

```
$ find . -newermt "-10 minutes"            → bfs: error: Invalid timestamp.   (0 results with 2>/dev/null)
$ /usr/bin/find . -newermt "-10 minutes"   → works, lists files
$ type find
find is a shell function from …/shell-snapshots/snapshot-zsh-….sh
```

**Inside a Claude Code bash session `find` is a shim, not `/usr/bin/find`.** The same script behaves
differently in a plain terminal and inside a session. Any change-detection command the orchestrator runs
through a session must use an absolute path to the binary, or use `stat`, which is not shadowed. The existing
harness already sanitises `PATH` in its generated launchers; this is why that matters. **This is a correction
to FIELD-NOTES §11.3's attribution, not to its observation.**

### 3.10 The account switch *is* a config-root switch

VERIFIED, and it is not obvious:

```
$ <switcher> switch --print-env <profile-A>
export CLAUDE_CONFIG_DIR="<profile-dir>"
```

That single variable is:
- what the profile switcher changes to switch account (R1-07's mechanism, «перемикач профілів, який використовує різні профілі»);
- what Claude Code uses for *"your settings, session history, and plugins"*;
- and what his own marketplace resolves `<config-root>` from — i.e. **slots 3 and 4 of six**.

**So an account switch silently swaps two of the six config slots.** A role moved to another account does not
merely bill elsewhere; it reads a different user-level configuration. Nothing in the interview or in
`config-levels.md` anticipates this. §6 Q4.

One more measured wrinkle: **`<switcher> switch --print-env <name>` prints nothing when the target is already
active.** A launcher that treats empty output as failure will refuse to start a session that is already on the
correct account. (The current `harness-spawn.sh` does `if envout=$(...); then eval "$envout"` — it tests the
exit code, not emptiness, so it is safe. A reimplementation might not be.)

### 3.11 Across platforms

A sibling document has already done this axis properly and I will not re-derive it:
`../platforms/ADAPTER-CONTRACT.md` §F and §G. The two findings that bind this cluster:

- **"on *every* platform, changing a *running* session's account is impossible — so R1-07's *hard* account
  change ('applies now, stops current work') is always a stop-and-relaunch with a context re-seed, never an
  in-place switch."**
- **The application boundary for a control-file change is platform-dependent.** Where an instruction cannot be
  delivered mid-turn (Gemini CLI headless: *"a mid-run prompt aborts the turn"*), *"`stop-hard` degrades to
  'kill the process', and Д6's «враховує відповіді наживо» becomes 'at the next task boundary'."*

---

## 4. What is NOT feasible, and why

**4.1 A hard account change applied in place to a running session.** No platform supports it
(`../platforms/ADAPTER-CONTRACT.md` §F). `hard` for an account can only ever mean *stop the session, relaunch
it under the new identity, re-seed its context*. The control file can express the intent; the orchestrator
cannot honour it without a restart. R1-07's soft variant («наступні завдання») is the one that is actually
cheap, because the account is applied in the generated launcher at spawn.

**4.2 One file that is simultaneously live config, a command inbox, a question channel and an audit log.**
Not because it is inelegant — because it has been tried here and lost data. `state/attention` had two writers
and a truncating rebuild, and it destroyed the context watch's corrections for a whole night while raising
eight false `STALLED` alarms (§2.8.2). The owner's requirement is *«єдиний файл, який оркестратор… постійно
дивиться»* — **one thing the orchestrator watches**, which several files with one writer each satisfies, and
which one multi-writer file does not.

**4.3 Silent-fallback-to-defaults as the response to an invalid edit.** Measured in §3.5. It is also how Claude
Code's own `-p` path behaves (*"skips the broken file or values and continues"*) — fail-open is fine for a
preference and catastrophic for a stop command. The fix is the Gas Town split: **the gate is existence, the
content is metadata** (§2.5), so an unparseable stop file still stops.

**4.4 `fs.watch` on a control-file path, combined with atomic writes.** §3.3. Choose one, and since atomic
writes are non-negotiable, the watch must be on the directory or must be a poll.

**4.5 mtime alone as the change detector.** It both misses (§3.1, same-second writes at second granularity)
and over-reports (§3.2, identical-content rewrite). It is a fine *cheap gate*; it is not a decision procedure.

**4.6 A guarantee that a control file edited anywhere is the one the orchestrator reads.** Д4's default is
*«абсолютно все виконувати в різних ворк трі»*; a lane in a worktree that edits `docs/open/QUESTIONS.md`
edits its own copy. This already cost an hour of an owner-facing question being invisible (§2.8.2). Nothing
detects it automatically. The only known mitigation is the rule the run adopted: **absolute path into the main
checkout, never the relative one**, plus *"at merge, take the main checkout's version whole."*

**4.7 Attributing an effective value to the file that supplied it — if you copy Claude Code's design.** Its
own docs concede `/status` *"doesn't show which file supplied each key."* With six-plus slots and a live
reload this is the question the owner will ask first when something behaves unexpectedly at 3 a.m. It is
feasible, but only if the resolver is written to record provenance from the start (§5.4).

**4.8 Schema versioning that nothing reads.** `schemaVersion: 1` exists in both harness config templates and
is referenced nowhere in the codebase (§2.8.1). A version field is not a migration strategy; ralphex's
comment-out-to-inherit plus a semantic `--upgrade` merge is (§2.6).

**4.9 A trustworthy audit trail that is written by the same actor whose behaviour it records, with no
cross-check.** FIELD-NOTES §12.7: *"A security review of a single API read found 26 refusal events in the
audit log that never occurred."*

---

## 5. Proposals

Design constraints I have held to: his simplicity rule (§1.7), his marketplace precedence (Д1), one thing to
watch (R1-07), a live edit that beats both the run's choice and the default (Д7), commands that write into the
watched file (Д12).

### 5.1 P1 — The file layout

**Two planes, kept apart, because they have different writers, lifetimes and failure modes.**

```
CONFIGURATION PLANE  — layered, merged, versioned; the orchestrator RE-READS it
  slot 1  ./.claude/shared/identity.json                    project committed  (lowest)
  slot 2  ./.claude/shared/plugins/orchestrator.json        project committed
  slot 3  <config-root>/shared/identity.json                user
  slot 4  <config-root>/shared/plugins/orchestrator.json    user
  slot 5  ./.claude/shared/identity.local.json              personal project
  slot 6  ./.claude/shared/plugins/orchestrator.local.json  personal project     (highest of the six)
                                                            ← exactly his marketplace, unchanged
  slot 7  .orchestrator/runs/<run-id>/run-config.json       THIS RUN             (new — see §6 Q1)

CONTROL PLANE — flat, unlayered, one writer each; the orchestrator POLLS it every tick
  .orchestrator/control/
    STOP                  written by: the stop commands, and by the orchestrator itself (limit wind-down)
    accounts.json         written by: the owner / the config command
    overrides.json        written by: the owner / the config command   (Д7 live behaviour overrides)
    ANSWERS.md            written by: THE OWNER ONLY — the orchestrator never writes it
    QUESTIONS.md          written by: sessions only  — append-only      (Д6; owner-relocatable)
    JOURNAL.md            written by: everyone       — append-only, audit of every applied change
    .snapshot/            written by: the orchestrator — the pinned effective config, per §5.3
```

Design notes, each traceable to evidence above:

- **Why the control plane is not layered.** Precedence exists to reconcile *durable preferences* from several
  people and places. A stop command has no preferences to reconcile — it is an event. Layering it would mean a
  project-committed file could countermand the owner's live stop, which is absurd. So: config is merged,
  control is flat and always wins.
- **Why several files, not one.** One writer per file is what makes concurrency safe without locks for the
  append-only files, and it is the rule the field-proven channel already enforces (§2.8.3). It also satisfies
  *«єдиний файл… постійно дивиться»* read as *one thing to watch*: `.orchestrator/control/` is one directory,
  one poll, one glob.
- **Why `ANSWERS.md` is in the list.** Because the one hard rule of the working channel is that the agent
  never writes it. Naming it makes the rule enforceable.
- **Paths are absolute, in the main checkout, always** — §4.6. Every launcher already exports
  `HARNESS_PROJECT`; the successor exports the control directory the same way, and a session that resolves the
  control path relatively is a bug.

**`STOP` — the Gas Town shape, because it fixes three recorded incidents:**

```
<trigger>\t<RFC3339 timestamp>\t<mode>\t<actor>\t<reason>

manual	2026-09-19T21:04:11Z	stop-soft	owner:/orchestrator:stop-soft	winding down before I go out
auto	2026-09-19T23:51:02Z	stop-hard	orchestrator:limits.stop_at=95	weekly at 95%
```

- **Existence is the gate; content is metadata.** `[ -f STOP ]` stops the run whatever the content says. An
  unparseable or half-written STOP still stops.
- **An empty or unparseable STOP parses as `manual` + `stop-hard`** — the most restrictive reading, exactly
  Gas Town's `parse("")`. A torn write can never *downgrade* a stop.
- **`auto` may be cleared automatically; `manual` may not.** This is `#65`/`#73`/`#82` (§2.8.2) fixed by a
  five-character prefix.
- `stop-custom` names a rule file: `mode = stop-custom:<name>`, resolving to
  `.orchestrator/control/stops/<name>.md`. **If that file is missing or unreadable, it degrades to
  `stop-hard`, never to "carry on"** — [524] leaves both prose and commands legal, which is §6 Q6.
- A scoped stop is `STOP.<lane>`, as Gas Town scopes per rig.
- **The orchestrator itself is exempt from its own STOP** and stays alive to wind down, close sessions and
  write the report — Gas Town's Mayor exemption, and the *"daemon stays alive … but does NOT restart any
  agents"* rule.

### 5.2 P2 — The change protocol

Seven steps. Steps 2–4 are the ones the evidence forces.

**1. Write (single-writer discipline).** Every write to any control or config file is
`mktemp` in the destination's own directory → write → `mv` over the destination. Never `>` in place (§3.4).
Multi-writer files (`JOURNAL.md`, `QUESTIONS.md`) are **append-only** and are `>>`-appended, never rewritten;
no file in this design is ever truncate-and-rebuilt, because that is what broke `state/attention` (§2.8.2).
Where a genuine read-modify-write is needed, take `lockf -t 10 <dest>.lock` (§3.6) — kernel-held, so a dead
writer leaves nothing stale — and **proceed without the lock if `lockf` is unavailable, saying so in one
line**, which is his own marketplace's rule (*"The lock is a recommendation; the destination is not"*).

**2. Detect (cheap gate, then a decision).** Per tick, per watched file:
`(size, mtime-with-nanoseconds)` → if unchanged, done, ~2.5 ms. If changed, `shasum -a 256` → if the digest
equals the last applied digest, **it is a touch, not a change: ignore it** (§3.2). Only a new digest is a
change. **No FSEvents, no fswatch, no fs.watch** — §3.3 shows a file watch dies on the first atomic write,
§3.8 shows the poll costs ~0.3 % of a tick, and Symphony's spec tells implementations to re-validate on the
tick anyway because watch events get missed. Content hashing also makes **debounce unnecessary**: an editor's
three-event save collapses to one digest change by construction.

**3. Validate, and never crash on a bad edit.** Symphony's rule, adopted verbatim: *"Invalid reloads MUST NOT
crash the service; keep operating with the last known good effective configuration and emit an
operator-visible error."* Concretely, and split the way Claude Code splits it:

| what is wrong | what happens |
|---|---|
| a control/config file is unparseable | **keep the last good effective config**, do not fall through to defaults (§3.5, §4.3); write one `JOURNAL.md` line; notify on the configured channel; **skip dispatch for that tick and keep supervision running** (Symphony §6.3) |
| one key is invalid, the file parses | skip that key, keep the rest, warn — his marketplace's *"one unknown key never costs more than itself"* |
| an unknown key | accept if `x-`-prefixed, warn otherwise; never fail the file |
| `STOP` is unparseable | **stop anyway**, as `manual`/`stop-hard` (§5.1) |
| a **restriction** is invalid (`never`, the red-line file, an autonomy limit) | **fail closed** — apply the stricter value, Claude Code's managed-settings rule |

The last row is the principle: **fail open for preferences, fail closed for restrictions.**

**4. Classify the change, then apply it at the boundary its type names.** A change carries a type (R1-07):

| type | when it applies | what it may touch |
|---|---|---|
| `hard` | this tick | stop current work; for an account, *stop-and-relaunch with a context re-seed* (§4.1) |
| `soft` | at the next safe boundary | the next task / the next spawn — what counts as a "step" is itself configurable [209] |
| `custom` | read the owner's rule and act | prose or commands [524] |

**And the boundary is per-platform, not universal** (`ADAPTER-CONTRACT.md` §G): where an instruction cannot be
delivered mid-turn, `hard` degrades to killing the process, and that degradation is **announced in
`JOURNAL.md` at configuration time and again when it fires**, never discovered at 3 a.m.

**5. Never break an in-flight session's coherence.** Symphony's MUST, adopted: a reload *"applies to future
sessions; it MUST NOT make an in-flight session advertise one provider and execute another."* See §5.3.

**6. Acknowledge, because he asked for it.** [449]: *«я розумів, що це скоро потрапить в оркестратор»*. On
applying a change the orchestrator appends one line to `JOURNAL.md` and sets a matching field in the file it
read (`applied_at`, or `Status: answered` for a question). **The owner's evidence that his edit landed is that
the file he edited changed back.** This closes the loop without any output the owner has to watch — which is
Д11's requirement («оркестратор не повинен нічого виводити для мене»).

**7. Audit.** One append-only `JOURNAL.md` line per applied change:
`<timestamp> <file> <digest-before>→<digest-after> <type> <actor> <what changed> <applied|deferred|rejected>`.
Three cheap hardenings the record demands: keep the **previous version of every file it replaces**
(`<file>.<timestamp>.bak`, last five — Claude Code keeps exactly five and it is what makes its recovery path
work); **record the digest, not a description**, so the log cannot claim an event that did not happen
(FIELD-NOTES §12.7); and **have the status command recompute state from the files, never from the journal.**

### 5.3 P3 — Precedence, the run scope, and the snapshot

**Precedence.** Slots 1–6 exactly as his marketplace defines them, unchanged, including deep-merge,
`use`-replaced-whole, `never`-accumulates, and the veto (§2.1). This is Д1 honoured literally.

**Slot 7 — this run — is new, and it is the part Д1 does not cover** (§2.1, §6 Q1). It is the run's own
`run-config.json`, written once at start from the answers to any pre-run questions plus any per-run flags. It
sits above the six because that is what "for this run" means, and it is the analogue of Claude Code's
`--settings` level (*"for one session"*) and of ralphex's CLI flags.

**The snapshot, and how it reconciles with Д7.** Three tiers, and the split is the whole answer:

| tier | pinned or live | why |
|---|---|---|
| **Pinned for the run** — worktree layout, the chosen process (GSD / custom), the board and its status map, the notification channel | pinned at start into `.snapshot/`, and **re-verified, not re-read** | these were *proven working before the run started* (R1-07 [199], R1-17 [395], R1-04 [153], Д4 [433]); changing them mid-flight invalidates work already done |
| **Pinned per session** — model, account/provider, permissions, role | pinned at **spawn**, into the launcher | §4.1: no platform can change them in place. Symphony's §13.6 MUST |
| **Live every tick** — everything else: concurrency ceiling, limit thresholds, stall minutes, watch cadence, autonomy mode, Д7's wait-or-finish, the stop file, account *assignments* for future spawns | re-read, hashed, applied by type | Д7 [458]: the live edit beats the run's start choice **and** the default |

**The reconciliation, in one sentence the owner can check:** *the run pins what it proved before it started
and what a session cannot change about itself; everything else is live, and a live edit beats both the run's
own choice and the stored default.*

**No surprises, made concrete.** `/orchestrator:status` prints, for every setting, **the effective value, the
slot it came from, whether it is pinned or live, and — for a pinned one — what the live files now say and when
it would take effect.** That is the one thing Claude Code's `/status` cannot do (§4.7), it is cheap if
provenance is recorded during the merge, and it is what makes a seven-slot live-reloading config
debuggable at 3 a.m. It costs nothing at run time because it only runs when asked (Д11).

### 5.4 Smaller decisions, with their trade-offs

| decision | chosen | rejected | trade-off accepted |
|---|---|---|---|
| change detection | poll: `(size, ns-mtime)` gate → sha256 decide | FSEvents / `fs.watch` / `fswatch` | up to one tick of latency (≤60 s); buys: survives atomic writes, no watch re-arming, no debounce, no extra dependency, ~0.3 % of a tick |
| control file format | `STOP` = TSV line; the rest JSON | all-JSON | one bespoke parser; buys: a STOP that is readable and writable with `printf` and cannot fail to parse |
| stop delivery | a file the commands write | signal (ralphex `SIGQUIT`) | needs a poll; buys: works with no pid, across terminals, and survives an orchestrator restart |
| lock | `lockf`, optional | a `.lock` sentinel file | needs `lockf` present; buys: no stale lock when a writer dies (§3.6) |
| schema evolution | commented-out defaults + `x-` keys + a read `schemaVersion` gate that **warns**, never refuses | silent version bumps (today's dead `schemaVersion`) | an old config keeps working; buys: the owner is told, not blocked |
| multi-file atomicity | a `sequence` integer bumped by the writer; the orchestrator applies a tick only when every file's sequence matches | K8s `..data` symlink swap (§2.7) | a little bookkeeping; buys: a change spanning `accounts.json` + `overrides.json` is never half-applied, without symlink trickery |

---

## 6. Open questions for the owner

Ordered by how much of the design they block. Each names what it collides with; none proposes an answer as
settled.

**Q1 — Is there a "this run" scope, and where does it sit?** *(blocks P3 entirely)*
Д1 sends the answer to his marketplace [416]. I read it: it defines **three levels and closes the set** — *"a
resolver supports no other level"* — and of the level he removed, *"do not build it, do not reserve a path for
it, do not mention it as an option."* But R1-07, Д7 and Д12 all require a scope for *this run*, and R1-12 says
settings are *«default/project/per-run»*. **Slot 7 is an addition to a design he declared closed.** Does the
run scope go above all six (my §5.3 proposal), or does a run write its choices into slot 5/6 and accept that
they outlive the run?

**Q2 — Which direction does the user band rank?** *(blocks the resolver)*
His marketplace: **user band above the committed project band**, personal-project highest. Claude Code:
**user lowest**, project-local highest. The existing harness: **project above user** (`hlib.sh:48-58`) — which
contradicts the marketplace. Three of his own reference points, two orderings. Д1 says follow the marketplace;
confirming that means the orchestrator **inverts the harness's current behaviour**, which is a migration note.

**Q3 — Is the control plane one file or one directory?** *(blocks P1)*
He said *«єдиний файл»* [195] and *«той файл, який оркестратор на постійний основі читає»* [520]. The record
says a single multi-writer file loses data: `state/attention` destroyed the context watch's corrections for a
night and caused eight false alarms (FIELD-NOTES §2.1, §11.3), and his own working channel already uses
**four files with one writer each** (§2.8.3). Does *«єдиний файл»* mean literally one file, or **one place the
orchestrator watches**? I have assumed the latter and I may be wrong.

**Q4 — An account switch also switches the config root. Intended?** *(blocks R1-07's mechanics)*
VERIFIED: `<switcher> switch --print-env` sets only `CLAUDE_CONFIG_DIR`, and that variable is what his marketplace
resolves slots 3 and 4 from (§3.10). **Moving a role to another account silently changes two of its six config
slots.** Should the orchestrator (a) pin the config root separately from the account so config follows the
person and not the billing identity, (b) accept per-account config as a feature, or (c) refuse to start when a
role's account implies a config root that differs from the run's?

**Q5 — Is there a third stop: freeze?** *(extends Д12)*
He named `stop-hard`, `stop-soft`, `stop-custom` [524]. Gas Town's E-stop is neither: **SIGTSTP**, *"Context is
preserved — no work is lost"*, resumed with `gt thaw`. For a limit pause (R1-06) that is strictly better than
a hard stop, because it keeps the context window that a hard stop throws away. Does `stop-soft` already mean
this, or is freeze a fourth verb?

**Q6 — What does `stop-custom` degrade to when its rule cannot be read or executed?** *(blocks the STOP parser)*
[524] allows *«текстописні правила чи команди»* — prose to be interpreted, or commands to be run. Those are
two execution models: prose needs a model call at exactly the moment the run may be failing; a command may
fail, hang, or need an account that is out of quota. My §5.1 degrades to `stop-hard`. **That is my choice, not
his**, and it is the safest but not obviously the one he wants — a custom stop meant to *slow down* would then
become a full halt.

**Q7 — Who polls: the orchestrator or the context watcher?** *(blocks P2 step 2)*
He said *«оркестратор чи контекст вочер»* [195] and left it open. It matters: if the watcher polls, the
control plane keeps working while the orchestrator is compacting or dead — which is exactly when a stop is
most needed — but it puts a second actor between the owner and the run. The single-orchestrator invariant
[300] governs the orchestrator; it says nothing about the watcher.

**Q8 — Does a control-file change deserve a notification?** *(touches R1-17, Д11)*
Д11 is emphatic: *«оркестратор не повинен нічого виводити для мене»* [508]. But an **invalid** edit made at
23:00 that leaves the run on its last good config is something he would want to know about before morning —
R1-17 says he configures what is worth waking him for. Is "your edit did not apply" one of those, or does it
wait for `/orchestrator:status`?

**Q9 — How long does the orchestrator keep replaced versions, and where?** *(touches R1-15, audit)*
Claude Code keeps five timestamped backups per config file and that is what makes its recovery path work.
Backups of `accounts.json` are also **a record of which account ran what, kept where nothing scans it** —
FIELD-NOTES §11.10 already records *"Secrets that reached a place nobody scans."* The `env_command` rule
(§2.8.1) keeps credentials out of config by design; does that rule extend to the control plane and its backups
as a stated invariant?

**Q10 — Is `QUESTIONS.md` in the control plane or outside it?** *(touches Д6, Д4)*
He said the questions channel is user-placed and may be a GitHub issue or a tracker task, *«місце визначається
користувачем»* [449]. My §5.1 gives it a default path inside `.orchestrator/control/` while leaving it
relocatable. But the worktree fork (§2.8.2, §4.6) is a property of *where the file is*, not of the protocol —
a GitHub issue cannot fork, a file in the repo can. Should the **default** for the questions channel be a
GitHub issue precisely because it cannot fork, with the local file as the fallback?

---

## Appendix — sources

**Read on this machine (VERIFIED)**
- `<baseline-marketplace>/docs/config-levels.md`, `docs/config-levels.json`, `shared/scripts/resolve-config.mjs`, `requirements/OWNER-DECISIONS.md`
- `~/Work/claude-plugins/plugins/harness/bin/{hlib.sh,harness-run.sh,harness-spawn.sh,harness-state.sh,harness-tickets.sh}`, `templates/{user,project}-config.example.json`, `docs/FIELD-NOTES.md`
- `<work>/<work-project>/.harness/supervisor/{ORCHESTRATION.md,WATCHER-PROMPT.md}`, `<work>/<work-project>/docs/open/{QUESTIONS.md,README.md}`
- `../../round-1/{TRANSCRIPT-01.md,ANALYSIS-01.md}`, `../extract/{by-item,outside-list,corrections}.md`, `../platforms/ADAPTER-CONTRACT.md`
- a profile switcher (v-unknown, `<switcher> list`, `<switcher> switch --print-env`), `lockf(1)`, `shlock(1)`, `stat(1)`, node v22.18.0

**Fetched (VERIFIED as read; primary)**
- `https://raw.githubusercontent.com/openai/symphony/main/SPEC.md` — 2312 lines, downloaded 2026-09-19
- `https://code.claude.com/docs/en/settings`, `https://code.claude.com/docs/en/hooks` — 2026-09-19
- `gastownhall/gastown` — `internal/estop/estop.go`, `internal/cmd/estop.go`, `internal/daemon/daemon.go` (via `gh api`)
- `kubernetes/kubernetes` — `pkg/volume/util/atomic_writer.go` (via `gh api`)
- `umputun/ralphex` — `llms.txt`, `cmd/ralphex/break_unix.go`

**CLAIMED only (vendor documentation, not run)**
- `https://docs.sortie-ai.com/` — hot reload asserted, mechanism undocumented
- `umputun/ralphex` `llms.txt` for config precedence and upgrade semantics (the signal handler is VERIFIED source)

**A note on currency.** Symphony's SPEC, the Gas Town source and the Claude Code settings docs were read on
2026-09-19; all three are actively developed (gastown's repo showed a push the same day). The measurements in
§3 are of this machine as it stands and would need re-running on a different filesystem — the nanosecond mtime
result in particular is an APFS property and does not hold on HFS+ or on a network mount.
