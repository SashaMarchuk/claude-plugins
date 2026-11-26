# C8 — Adversarial challenge: blast radius, the red-line file, end-of-run cleanup

Date: **2026-09-19**. Adversary pass over cluster C8 (**R1-15**, **R1-16**, **Д3**, owner instruction
**I3**). Companion to `C8-boundaries-safety-research.md`, which holds the options; this file holds only
the holes.

**What this file does and does not do.** Every attack below names a concrete failing scenario in the
owner's own environment. None of them proposes a replacement for a decision he made. Where a decision
collides with another decision or with the previous run's record, both sides are quoted with their
`[row]` anchor and source line. Where I could not establish something, it is marked INFERRED.

**Labels.** VERIFIED = I read it in source, in a log-derived record, or in official documentation.
CLAIMED = a README, doc or blog asserts it and I did not execute it. INFERRED = my reasoning from
verified parts.

**One standing note before the attacks, because it changes how much weight the rest can bear.**
R1-15 was never ratified. The interviewer restated it at [358]/[359] and moved to R1-16 at [360] with
nothing from the owner in between; his own last words on the item were a question back —
«Але, так, це максимум... Чи це є відповідно до твоєго питання» [357] — which the interviewer
answered for itself («Так, це відповідає на питання» [358]). R1-16's "без складного механізму
технічної ізоляції" [372]/[376] was likewise never confirmed; he talked underneath it
(«Чи якоїсь конфіг... Я би не сказав, я би це робив якось абстрактно» [373]) and confirmed only the
deferral to this analysis [383]. `extract/corrections.md` records both
(«the weakest-grounded answer in the interview»). The attacks below treat the decisions as binding
anyway — that is the adversary's job — but the twelve of them are being levelled at a position that
carries one owner «Підтверджую», and that «Підтверджую» is about commissioning this document, not
about the rule.

---

## A1 — A crashed run's leftovers are unreclaimable by design · **blocker**

**Collides:** Д3 [430] × R1-16 [366]/[370].

Д3 scopes teardown to provenance: «якщо він це сам підняв, то він це повинен і зупинити» [430].
R1-16 scopes intervention the same way: «він би не мав зупиняти якісь там тести, які не він
запускав» [370]. Put together, they define a set that no run can ever clean: **things a previous run
started and did not live to stop.**

The previous generation did not end on the finish path. VERIFIED, `FIELD-NOTES.md §10.1`: run
`20260831-184751` ended with
`watch: orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may sleep)`, leaving
`DEAD-RUN` and `STOPPED` on disk. VERIFIED, `§11.11`: "About 150 orphaned Docker volume pairs left by
a dead prior run." That is the observed output of exactly this hole.

**Concrete failure.** 03:40, Mac sleeps, orchestrator dies mid-run with three lanes' compose stacks
up. 09:00 the owner starts run N+1. Run N+1's ledger contains nothing about run N's containers, so
under Д3 it may not stop them (it did not start them) and under R1-16 it must not touch them (they are
not its work). The ports collide, the new lanes fail to bring up their stacks, and the only actor
permitted to resolve it is the human the whole tool exists to keep asleep. Each successive crashed run
adds another layer. Nothing in C8 says what a run may do about the *previous* run's residue, and the
two decisions read together say: nothing.

**What it leaves undefined.** Whether "started" means "started by this run" or "started by this
tool, ever". Two implementers will split on that line and produce opposite behaviour on run 2.

---

## A2 — Provenance is carried in an environment that detached processes do not inherit · **blocker**

**Collides:** Д3 [430] × `FIELD-NOTES.md §11.5` × `§12.4`.

"Stop only what you started" has to be implemented by recording *which* thing is yours. For Docker
that identifier is the compose project name, and it travels in an environment variable.

VERIFIED, `FIELD-NOTES.md §11.5`: "The owner's default stack was destroyed by a `docker compose down
-v` run with no `COMPOSE_PROJECT_NAME` exported, which landed it on the default project instead of a
lane project. … the actor was never identified, and a session had refused that exact action as
owner-only two minutes earlier." VERIFIED, `§12.4`: three detached scripts —
`overnight-supervisor.sh`, `harness-watchdog.sh`, `harness-unwedge.sh` — "must export the `gh` account
themselves … because launchd and `nohup` start with no environment."

**Concrete failure.** Teardown at end-of-run is precisely the moment most likely to be executed by a
detached or restarted process — the orchestrator may be dead (A1), so a watchdog performs it. That
process starts with no environment. `COMPOSE_PROJECT_NAME` is unset. `docker compose down -v` resolves
to the default project, which on this machine is `<work-project>` (VERIFIED in the research doc's live
`docker ps` output: `<work-project>-app-1` labelled `com.docker.compose.project=<work-project>`). **The rule
intended to prevent the 22:51Z incident re-creates it, on the cleanup path, at 04:00, with nobody
awake.**

**What it leaves undefined.** Д3 states a property of intent. It does not state that the identifier
must be recorded at creation time, persisted outside process memory, and re-read at teardown — which
is the only form in which the property survives the process that held it dying.

---

## A3 — "Stop only what you started" has no identity that is not reusable · **blocker**

**Collides:** Д3 [430] × `FIELD-NOTES.md §11.8` × the previous generation's addressing scheme.

VERIFIED, `plugins/harness/bin/harness-term.sh:157`: sessions are addressed by tty —
`iterm_close() { # <tty> — close ONE session; ... }`, and `harness-run.sh:252` reads `.tty` and `.pid`
out of each registry entry. VERIFIED, `harness-run.sh:254`, the source's own comment:
`# liveness: the tracked claude pid (not "any node on the tty" — review MEDIUM)` — the previous
generation already discovered that a tty is not a stable identity for one thing, and fixed it in one
place only.

A tty device name is recycled by the OS. A pid is recycled by the OS. And lineage is unavailable:
sessions are spawned through `osascript` into iTerm2 (VERIFIED, `harness-term.sh:16-110`), so a
session is a child of iTerm2, not of the orchestrator — which is *why* the previous generation reached
for pattern matching and why VERIFIED `§11.8` records
"`pkill -f 'playwright test'` killed an unrelated lane, because every lane's own prompt text contains
that literal string."

**Concrete failure.** A worker session dies at 01:10; its `/dev/ttys006` is released. At 03:00 the
owner opens a terminal for his own parallel work and the OS hands him `ttys006`. At 04:12 the run
finishes and teardown walks the registry and issues `close ttys006`. His window closes mid-edit. This
is R1-16 case 2 — «в тій самій папці я паралельно працюю над чимось … він цього не має зупиняти»
[370] — violated *by the mechanism that implements Д3*, not by a rule being ignored.

**What it leaves undefined.** Everything about identity. Two implementers will pick tty, pid, pgid,
iTerm session id or a self-written pidfile, and only some of those are safe. The decision says
"stop what you started" and names no way to know.

---

## A4 — «технічні обмеження середовища користувач … налаштовує сам» is already false: the plugin sets them, in the least safe direction · **blocker**

**Collides:** R1-15 [357] × `plugins/harness/bin/harness-spawn.sh:32-39`.

The decision: «якщо людині потрібно якісь додаткові різні обмеження, то вона це може робити,
власноруч налаштовуючи своє середовище. І далі агенти, протім, будуть просто цьому підслідковувати»
[357].

VERIFIED, `harness-spawn.sh:32-39`, read today:

```sh
perm_flag() {
  case "$(cfg '.session.permissions' 'bypass')" in
    bypass) echo "--dangerously-skip-permissions" ;;
    ...
    *) echo "--dangerously-skip-permissions" ;;
```

The default is `bypass`, and the fallback for an unrecognised value is also `--dangerously-skip-permissions`.
The plugin is not abstaining from configuring the environment. It configures it on every spawn, and
picks the maximum-blast-radius setting both as the default and as the error case.

**Concrete failure.** The owner writes into his red-line file: "ніколи не виконувати
`docker compose down`". A worker spawned at 02:00 with permissions bypassed runs it anyway. That is
not hypothetical: VERIFIED `§11.5` records two sessions, the same command, two minutes apart, one
refusing it as owner-only and one executing it, **with the prose rule in force**. The red-line file
regulates the model's judgment; the flag the plugin passes regulates whether judgment is consulted at
all, and the plugin sets that one.

**Where "the user configures it" moves the problem onto a user with no way to know.** For the owner
to make R1-15 true he would have to know that `.session.permissions` exists, that it defaults to
`bypass`, and that his own `~/.claude/settings.json` sets `"defaultMode": "bypassPermissions"` and
his `~/.codex/config.toml:7` sets `sandbox_mode = "danger-full-access"` (both VERIFIED in the research
doc). Nothing surfaces any of that to him. **The default when he configures nothing is: no boundary,
on every engine, silently.**

---

## A5 — The one file forks, and reports success while doing nothing · **blocker**

**Collides:** R1-15 [357] × Д4 [433] × `FIELD-NOTES.md §12.5`.

R1-15: «Достатньо лише одного файлу, який може доповнюватись, текстописний» [357], in
«якісь визначене місце» [357], «читатися в обов'язковому порядку всіма» [357].
Д4: «Дефолтна пропозиція, щоби абсолютно все виконувати в різних ворк трі» [433].

VERIFIED, `FIELD-NOTES.md §12.5`: "**`QUESTIONS.md` and `JOURNAL.md` forked into a worktree's own
copy**, and a real owner-facing question sat there invisibly for an hour."

**Concrete failure.** The red-line file lives at a repo-relative path — the natural reading of
«визначене місце». Every worktree gets a frozen copy at creation. At 02:40 the owner appends
"не чіпати Redis" to the file in the main checkout. Four lanes are running in worktrees. All four
read their own copy, all four log "red-line file: read, 11 rules", and none of them has the rule that
was added. The owner has a mechanism that tells him it is working while it is not — the exact class
`FIELD-NOTES.md §11.4` is an inventory of ("reported success while doing nothing").

**What it leaves undefined, separately.** What happens when the file cannot be read at all. R1-15
says reading is «в обов'язковому порядку» and says nothing about the failure branch. One implementer
refuses to start the run; another logs a warning and proceeds unbounded. Given VERIFIED `§11.9` —
"The credential checker silently ignores a bare path argument, so a sweep run without `--scan` reads
clean over files it never opened" — this codebase's demonstrated house style is the second one.

---

## A6 — A mid-run edit never reaches a session that is already running · **major**

**Collides:** R1-15 [357] × Д7 [455]/Д12 [520] × `FIELD-NOTES.md §8`.

The owner established elsewhere that mid-run changes must be picked up: Д7 — the user may change
behaviour during the run and the orchestrator must read and apply it; Д12 — the command writes into
the file the orchestrator reads every tick. R1-15 establishes a file that is «читається в
обов'язковому порядку» but says nothing about when, and its most natural implementation is injection
into the session prompt at spawn.

VERIFIED, `FIELD-NOTES.md §8`: "A session already booted keeps the account it booted with; the change
reaches the next spawn." The same structural property applies to anything injected at spawn.

**Concrete failure.** 03:15. The owner wakes, sees in the status output that a lane is heading toward
his database, appends «ніколи не робити міграції на локальній базі» to the red-line file, and goes
back to sleep believing he has stopped it. The lane booted at 23:40. It holds the previous text. It
runs the migration at 03:22. He will not find out until morning, and the record will show the rule was
in the file before the action.

**What it leaves undefined.** Re-read cadence, and whether a prohibition added mid-run binds
in-flight sessions or only the next spawn. Two implementers build opposite behaviour, and only one of
them matches what the owner will assume when he edits the file at 03:15.

---

## A7 — Case 2 is not decidable by any path rule, and the decision offers no other discriminator · **major**

**Collides:** R1-16 [370] × R1-16 [366] × `FIELD-NOTES.md §10.2 (J-ORCH-45)`.

His two cases: «перший кейс … іншою папкою, іншим проектом, то цей оркестратор, він цього не має
трогати. Другий кейс, якщо, наприклад, **в тій самій папці** я паралельно працюю над чимось, це не
запускав оркестратор, це роблю я, він цього не має зупиняти» [370]. The mechanism he named is
positional: «в оркестратори прописаний шлях, до чого він має доступ» [366].

A path is exactly what case 2 does not distinguish. Both processes are in the same directory, using
the same files, the same node_modules, the same ports.

VERIFIED, `FIELD-NOTES.md §10.2 (J-ORCH-45)`: "Validators were told to hold suites until `ps` shows
zero playwright-test processes before gating."

**Concrete failure.** 01:50, the owner runs a Playwright suite by hand in his own terminal, in the
repo. A validator reaches its gate and applies the J-ORCH-45 rule. `ps` never shows zero. Two
outcomes, both bad and both compatible with the decision as written: (a) it waits — and Д7's default
is «залишитись і чекати», so the queue stands still until he wakes up, burning the night the run
existed to use; or (b) it decides the process is stale and kills it, which is case 2 verbatim. The
only signal that separates his suite from the run's is a recorded identity, which belongs to Д3's
ledger, and **nothing in the interview connects R1-16 to Д3**.

---

## A8 — «абстрактно», not a config — but the scope root has to come from somewhere · **major**

**Collides:** R1-16 [366] × R1-16 [373] × Д1 [416].

[366]: «в оркестратори прописаний шлях, до чого він має доступ» — a written path.
[373]: «Чи якоїсь конфіг... Я би не сказав, я би це робив якось абстрактно».
Д1 [416] defers all config precedence to his own marketplace's three-level rules.

A written path of what may be touched is a configuration value. Saying it should be abstract removes
the place where its value is stated without removing the need for one.

**Concrete failure.** He launches the orchestrator from `~/Work/claude-plugins` (its own repo, where
he is working on the plugin) while the tickets target `<work-project>`. Implementer A derives scope from
the process cwd: the run may write to the plugin repo and may not write to the project it was asked to
work on — every task fails at its first edit, at 22:30, and the run spends the night failing. Implementer
B derives it from the git toplevel of the ticket's project: correct here, wrong the moment a ticket
spans two repos. Implementer C derives it from `~/Work` because that is the common ancestor: the
boundary now contains every project he owns, which is case 1 inverted.

**What it leaves undefined.** Whether the scope is per-run, per-task or per-session; whether a task in
another repository widens it or is refused; whether the orchestrator's own state directory is inside
or outside. Three implementers, three products, no line in the interview that picks one.

---

## A9 — The file has no schema, so severity and volume both degrade it · **major**

**Collides:** R1-15 [357] («різного типу обмеження») × R1-14/R1-02 (the autonomous run's decision
authority) × `FIELD-NOTES.md §3.1`.

He said the restrictions come in types — «Має бути якісь визначене місце, де може людина додавати
якісь **різного типу** обмеження» [357] — and `extract/by-item.md` (R1-15 row 2) records that
`ANALYSIS-01.md` flattened this to "one text file". A flat file of prose has no field that
distinguishes an absolute from a preference.

**Concrete failure (severity).** The file contains "не пушити напряму в trunk" and "краще не чіпати
файли в `legacy/`". An autonomous-mode agent — and R1-02/R1-14 grant it decision authority the user
configures — reads both as context of equal weight, decides the ticket explicitly asked for a trunk
push, and pushes. Nothing in the file's shape marked one of the two as non-negotiable. This is
`§11.5`'s coin flip given a second way to land tails.

**Concrete failure (volume).** The file is append-only by design («який може доповнюватись» [357])
and every incident adds to it. After a year it is several thousand words, injected into every spawn a
run makes — and VERIFIED `§3.1` records a lane spending three quarters of its context window on
polling, with VERIFIED `§3.3` "nothing in the plugin measures context". The longer the prohibition
list grows, the less of it is attended to, and there is no bound, no expiry and no measurement.

---

## A10 — The prohibitions file cannot express the harm that actually happened · **major**

**Collides:** R1-15 [357] × `FIELD-NOTES.md §11.10`.

VERIFIED, `§11.10`: "**Two local role passwords printed in clear text into a session transcript** by
Playwright's `--trace on` while diagnosing a timeout. … **no automated secret scan covers tool output
or transcripts.**" And: "A Sentry breadcrumb recorded the address of every outgoing request, and one
such address was a Slack webhook secret."

No prohibition writable in a text file prevents either. Nothing decided to leak anything; a permitted
tool, doing its declared job, inside the working directory, wrote a secret to a file the run is
supposed to write to. The red-line file is a list of actions an agent must not choose. The event had
no choice in it.

**Concrete failure.** The owner, acting on R1-15 in good faith, writes "ніколи не виводити паролі в
лог". The next run enables `--trace on` to diagnose a flaky test at 03:00, and the same leak occurs.
He now has a written rule, a run that obeyed every written rule, and leaked credentials. This is the
sharpest form of "the user configures it, and has no way to know the right answer": he cannot
enumerate what the file *cannot* cover, so the file's existence tells him he is protected in a class
where it has no purchase at all.

---

## A11 — Teardown's first item is a role that another decision forbids · **major**

**Collides:** Д3 [430] × R1-10 [300] × Д10 [497].

Д3, verbatim, and note where his list starts: «якщо, наприклад, він там підняв **свої якісь там
оркестратори**, якщо він підняв там якісь докер контейнери або якісь сервіси … якщо він це сам
підняв, то він це повинен і зупинити» [430].

R1-10, confirmed at [304]: «не може бути такого, що вже якісь існуючі оркестратор і спускається
наступний, тому що тоді це буде просто нескінченний цикл оркестраторів … якщо раптом одночасно два
якісь оркестратори працюють, то це не окей. Це треба відслідковувати і не дозволяти» [300].

Either nested orchestrators exist (and R1-10's invariant is narrower than its words) or they do not
(and Д3's teardown list names a thing that cannot be there). `extract/by-item.md` (Д3 row 2) records
that `ANALYSIS-01.md` dropped the orchestrator from the teardown list entirely, so the flattening has
already happened once.

**Concrete failure.** R1-10 also says "start over" means restarting the orchestrator, not redoing the
work [300], and Д10 [497] has a restarted orchestrator inheriting live executors. Orchestrator #2
inherits run state whose ledger records "orchestrator" as a started thing. At the end of the run it
walks the ledger and issues a stop against an entry that is itself. Whether that is the fifth
orchestrator of the run killing the fourth's stale registry entry or killing its own process depends
entirely on which identity the ledger stored — see A3, where the decision names none.

---

## A12 — «Але, так, це максимум» is being read as a ceiling on the plugin; it may be a ceiling on him · **major**

**Collides:** R1-15 [357] × R1-15 [357] — the sentence against itself.

Two readings of «Але, так, це максимум» [357], immediately after «Достатньо лише одного файлу»:

1. *The plugin may do no more than ship one file.* This is how the research and the analysis read it.
2. *One file is the maximum **he** will maintain.* Read with the sentence it follows —
   «якщо людині потрібно якісь додаткові різні обмеження, то вона це може робити, власноруч
   налаштовуючи своє середовище» [357] — the subject of the whole passage is the human's own effort,
   not the plugin's scope.

The two readings license opposite products, and he was never asked which. The attack is not that one
reading is right; it is that **this single ambiguous clause is currently the load-bearing constraint
on the entire safety design of the tool**, and it sits inside the answer he himself ended by asking
whether it answered the question [357], and that no «так» ever closed [358]/[359]→[360].

**Concrete failure.** Reading 1 is implemented. Six months on, after an incident, the owner asks why
the tool did not stop it and is told his own ceiling forbade the mechanism — a ceiling he stated once,
in a sentence about his own configuration effort, which he never confirmed and which no one ever put
back to him in the other reading. The cost of the ambiguity is paid entirely on the night it matters.

---

## Not attacks — two things that survive

Stated for the owner's benefit, because an adversary that only attacks is not useful:

- **The provenance principle itself is sound and is the cheapest real improvement available.** "Stop
  only what you recorded starting" is the direct fix for both recorded incidents (`§11.5` unscoped
  `docker compose down -v`, `§11.8` over-matching `pkill -f`). Every attack above is against its
  *implementation gaps* (A1, A2, A3, A11), not against the rule.
- **"One place the human writes prohibitions" is the correct policy surface.** A1–A12 attack what
  reads it, when, whether it is one copy, and what it cannot express. None of them argues the file
  should not exist.

## Source index

**Read on this machine today (VERIFIED):** `plugins/harness/bin/harness-spawn.sh:28-39` ·
`plugins/harness/bin/harness-term.sh:16,155-165,174-234` · `plugins/harness/bin/harness-run.sh:248-323` ·
`plugins/harness/docs/FIELD-NOTES.md` §1.6, §2.2, §3.1, §3.3, §5.1, §7, §8, §10.1, §10.2, §11.1–§11.11,
§12.3–§12.7 · `round-1/TRANSCRIPT-01.md` rows [350]–[383], [425]–[435] ·
`round-1/ANALYSIS-01.md` · `research/extract/by-item.md` (R1-15, R1-16, Д3, Д4) ·
`research/extract/corrections.md` §B, §C · `research/clusters/C8-boundaries-safety-research.md`.

**Taken from the C8 research document as already-VERIFIED there, not re-executed here:**
`~/.claude/settings.json` (`defaultMode: bypassPermissions`, nine guard hooks) ·
`~/.codex/config.toml:7` (`sandbox_mode = "danger-full-access"`) ·
live `docker ps` labels (`com.docker.compose.project=<work-project>`) ·
the sandbox / deny-rule / hook execution tests.

**INFERRED, flagged in place:** that spawn-time prompt injection inherits `§8`'s "a booted session
keeps what it booted with" property (A6); that a released tty is reassignable to a new window within a
run's lifetime (A3) — standard POSIX device reuse, not executed here.
