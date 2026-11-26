# C6 — Liveness, stalls, orchestrator death and resumable state

Cluster items: **R1-09**, **R1-10**, **R1-06 part 3**, **Д10**.
Research date: 2026-09-19. Machine: <host>, macOS 26.5.2 (Darwin 25.5.0, arm64).
Every claim is graded **VERIFIED** (I read it in source, ran it on this machine, or read the primary
doc), **CLAIMED** (a README, blog or project doc asserts it and I did not reproduce it), or
**INFERRED** (my reading).

---

## 1. What the owner decided, quoted

### R1-09 — a silent session

> **[231]** «Агент сам повинен це вирішувати, тобто він дивиться, перевіряє ті сесії, які він
> запустив, які в них прогрес, що вони там зробили, тощо так далі. І відповідно до цього діє»

> **[234] / [236]** «Тобто оркестратор, для цього є щоби..., вирішувати ці питання» / «та
> врегульовувати»

He was asked for a ladder («назви по черзі, від найм'якшого кроку до найжорсткішого») and refused the
shape of the question. No timeout, no first step, no last step. The orchestrator inspects **progress
and work done** in the sessions **it started**, and acts.

**Ratification status — VERIFIED from the transcript:** he never said «так» to R1-09. The interviewer
put the restatement at [233], he began answering underneath it at [234] and [236], and the interviewer
wrote «Гаразд, зафіксував» at [238] over a half-finished sentence. The substance is his; the closure
is not.

### R1-10 — the orchestrator itself dies

The health check, and its purpose:

> **[246]** «І людина може налаштувати, як це повинно перевірятись. … Тобто таким чином, аби це було
> якось детерміністсько в результаті, і щоб, якщо ран зупинився через помилку, те що, наприклад, код
> лежить, то щоб використати якийсь фоллбек, тощо, так далі»

In English, the rest of the answer: the check itself is configurable, for example an agent launched every N hours on another subscription.

The mechanism he offered when pressed on "deterministic", and never finished:

> **[249] / [251] / [253]** «Можливо, якісь варіанти, щоби перевіряти **стан останнього запису** тощо,
> так далі. Тобто» / «Коли» / «останній раз... щось...»

**This is the only concrete liveness mechanism proposed anywhere in the interview, and `ANALYSIS-01.md`
dropped it.** The design in §5 below is built on it.

The fallback requirement:

> **[255]** «Має бути надійний варіант для того, щоби це відновити… якщо, наприклад, людина декілька
> підписок, я скажу там, наприклад, кодекс, GLM код, тощо, так далі, то я думаю, є налаштовані
> фоллбеки на інші провайдери, то не могло б бути такого, що процес зупинився»

He then **downgraded his own statement from a rule to an explanation** and told the interviewer to
stop confirming mid-answer:

> **[258]** «Тут Це не як правило, це лише просто пояснення про те, що оркестратор, він по факту і є
> для того, щоби вирішувати ці питання»

> **[266]** «І має бути варіант перевірки цього та відпрацювання якогось фоллбеку. Тобто має бути щось, що
> може допомогти запустити ран і продовжити роботу **без участі в налаштуваннях користувача**»

In English, the rest of the answer: orchestrators exist to settle such issues, and an orchestrator may stop because, for example, **credits or the weekly limit ran out**.

The interviewer withdrew at [268] («Я передчасно перейшов до підтвердження») and **never re-put it**.
So the health-check-and-fallback requirement is unratified, and its framing "as a rule" was explicitly
rejected by him. The substance survives because he restated it himself at [266].

Note the named death mode: **credits / weekly limit running out — not a crash.** A different detection
problem from a hung process, and the current harness does not distinguish them.

The single-orchestrator invariant, and the only part of R1-10 he actually ratified:

> **[300]** «Дуже важливо, що не може бути такого, що вже якісь існуючі оркестратор і спускається
> наступний, тому що тоді це буде просто **нескінченний цикл оркестраторів**. … Якщо, наприклад,
> запустився оркестратор, або щось запустилось, але воно не спрацювало, **переконуєш що воно не
> спрацювало, а після того запускаєш новий**.»

In English, the rest of the answer: **restart the orchestrator**; keep **a log of what was launched when**; it must be **a reliable and very simple thing**; two orchestrators running at once is not OK.

> **[301]** «Це треба **відслідковувати і не дозволяти**»

> **[304]** «Та, правильно» ← the confirmation, for the launch journal + prove-dead-before-spawn +
> no-two-orchestrators statement. **VERIFIED: this is one of only two ratified sentences in the whole
> cluster.**

Recovery sources — put to him at [307], **never confirmed** (the interviewer said «Підвів до запису.
Що далі?» at [309] and he answered with a new point instead):

> **[293]** «По-друге, людина може вказати, які варіанти для того, щоби відновлюватись. … Якщо,
> наприклад, **по дефолту, то це дивитися в статус файли**, виконання всього цього оркестратора або...
> тощо, так далі.»

In English, the rest of the answer: first, the orchestrator can work this out itself; in Claude Code recovery can mean reviewing previous sessions and transcripts; the point is to **look for options** that help recover a session.

Per-platform recovery — put at [311], answered underneath, **never confirmed** («Зафіксував.» [318]):

> **[310]** «Також для кожної платформи можна налаштовувати, як саме буде робитись відновлення.
> Наприклад, для код-коду це читання транскриптів.»

In English, the rest of the answer: the same for Codex; other platforms may differ, perhaps using a skill.

> **[312] / [314] / [316]** «Тобто людина це може налаштовувати, може написати **свої власні [с]кіли**»
> / «які допоможуть зробити так» / «щоби» ← cut off by the interviewer.

### R1-06 part 3 — state accounting for recovery

> **[171]** «…в нас **в реєстрі має записуватись кожен стан, його виконання** … для того, щоби було
> відновити процес і продовжити, **навіть руками**»

> **[189]** «Але якщо, наприклад, людина налаштувала, що вона користується get shit done, то
> оркестратору, я думаю, що можливо йому нічого не треба окремо записувати, а лише записувати **оце
> референс** на те, що веде get shit done.»

In English, the rest of the answer: he may be wrong, but it must be **a very simple process** that respects the config; for other processes the agent must research how they work, ask the user, and **explain clearly why it is asking**.

Three-way rule, his words: **reference** the chosen process's records / keep **own** records only if
the process has none / **reference plus the missing delta**. Manual resume is an accepted outcome, not
a failure.

### Д10 — restart with executors still alive

> **[497]** «Та оркестратор сам повинен проаналізувати, що це таке, навіщо, чи це потрібно зупинити,
> чи це потрібно просто почекати, коли воно завершиться, тощо, так далі. Тобто це вже, він повинен
> вирішити»

**Unratified** — [500]/[501] put the restatement, the interviewer moved to Д11 at [503] with no answer
in between.

### The constraint that governs everything in this cluster

Four times, in four different items, he said the same thing. Only the last one reached `ANALYSIS-01.md`:

> [171] «тут нічого надприроднього не потрібно вигадувати» · [189] «це має бути дуже простий процес» ·
> **[300] «це має бути надійна річ, дуже проста»** · [370] «я не хочу якихось детерміністського
> варіанту для цього, тому що він буде дуже складний оверінжиринг»

Anything proposed below that is not simple and reliable is wrong by his standard, whatever else it is.

---

## 2. How the world does it

### 2.1 Liveness: why a PID alone is never enough

A PID identifies a process **slot**, not a process. Once the original exits, the number can be reused,
and `kill -0 <pid>` will then report a stranger as alive.

- **VERIFIED on this machine:** `sysctl kern.maxproc` = **6000**, `kern.maxprocperuid` = **4000**. The
  previous harness run spawned thousands of short-lived shells across 34 hours — the field notes record
  a single lane holding **58 concurrent child shells**, each a `sleep 590` poll, "spawned roughly every
  two minutes for two hours" (`FIELD-NOTES.md` §2.2). PID reuse inside a long unattended run is a live
  risk on this box, not a textbook footnote.
- The standard fix is **PID + process start time**. `ps -o lstart` gives it.
  **VERIFIED:** `ps -o pid,lstart,etime -p $$` → `52032  Sat Sep 19 20:16:39 2026  00:05`.
- A **boot id** invalidates every recorded PID after a reboot in one comparison.
  **VERIFIED:** `sysctl -n kern.boottime` → `{ sec = 1788417532, usec = 873575 } Thu Sep 3 13:38:52 2026`.
- `kill -0` also cannot separate "running" from "stopped" (SIGSTOP) or "uninterruptible". `ps -o state=`
  can (`T` = stopped, `U`/`D` = uninterruptible wait).

**Anthropic reached the same conclusion.** Claude Code 2.1.278's own per-session record is
`<CLAUDE_CONFIG_DIR>/sessions/<PID>.json` and it carries `procStart` as a string.
**VERIFIED — read live on this machine:**

```json
{ "pid": 86924, "sessionId": "ac653a10-c035-4b73-acab-a57e21fbeaae",
  "cwd": "/Users/sasha-marchuk/Work/claude-plugins",
  "startedAt": 1789822271103, "procStart": "Sat Sep 19 12:51:09 2026",
  "version": "2.1.278", "peerProtocol": 1,
  "peerFeatures": ["notify_idle","reply_across_default_dirs","artifact_yield"],
  "kind": "interactive", "entrypoint": "cli", "pidDomain": "darwin",
  "messagingSocketPath": "/tmp/cc-socks/86924.sock",
  "name": "claude-plugins-d5", "nameSource": "derived",
  "status": "idle", "updatedAt": …, "statusUpdatedAt": … }
```

`pid` + `procStart` + `pidDomain` is exactly the PID-plus-start-time fence. This is the strongest
single piece of evidence in this document: **the platform the owner is building on already implements
the identity record his launch journal needs, and the orchestrator can simply read it.**

### 2.2 Single-instance enforcement on macOS

| Primitive | Available here | Atomic? | Releases on SIGKILL? | Verdict |
|---|---|---|---|---|
| `flock(1)` | **NO — not shipped on macOS** (VERIFIED: `command -v flock` → not found) | — | — | Do not write Linux-shaped scripts |
| `/usr/bin/lockf` | **YES** (VERIFIED) | yes, `flock(2)` | **YES** (VERIFIED) | **Use this** |
| `/usr/bin/shlock` | YES, but `man shlock` says *"The shlock command is **deprecated**, and lockf(1) should be used instead"* (VERIFIED) | yes (`link(2)`) | no — PID-file semantics | Avoid |
| `mkdir` | YES | **YES** (VERIFIED: second `mkdir` fails) | no | Fallback marker only |
| `ln` hardlink | YES | **YES** (VERIFIED: second `ln` fails) | no | Fallback marker only |
| `set -o noclobber; echo > f` | YES | **YES** (VERIFIED: second `>` fails) | no | Fallback marker only |

The measurement that decides it — run on this machine:

```
$ lockf -t 0 -k lf sleep 5 &        # holder
$ lockf -t 0 -k lf echo "GOT LOCK"  # second acquirer
lockf: lf: already locked           # rc=75
$ lockf -k k sleep 30 & kill -9 $!  # holder SIGKILLed
$ lockf -t 0 -k k echo …
RE-ACQUIRED after SIGKILL           # the lock auto-released
```

**VERIFIED.** `lockf` uses BSD `flock(2)` on an open fd, so the kernel drops the lock when the process
dies **for any reason** — crash, SIGKILL, terminal close, power loss. There is no stale-lock class of
bug to write recovery code for. Every marker-file scheme (`mkdir`, `ln`, noclobber, PID files) has one,
and the previous generation's incident list is full of exactly those bugs.

`man lockf` warnings worth carrying into preflight:
- *"if the lockf utility is being used to facilitate concurrency between a number of processes, it is
  recommended that the **-k** option be used"* — otherwise no lock ordering is guaranteed.
- *"-w Causes lockf to open file for writing rather than reading. This is necessary on filesystems
  (including NFSv4) where a file which has been opened read-only cannot be exclusively locked."*
  **INFERRED consequence:** if `.harness/` (or whatever the orchestrator's state directory is called)
  ever lands inside iCloud Drive, Dropbox or a network share, `flock` semantics are not guaranteed and
  the invariant silently becomes advice. Preflight must refuse a synced or network state directory.

**Codex agrees.** Codex CLI 0.152.0 on this machine uses **zero-byte lock files**, which is the
signature of fd-held `flock(2)` rather than PID files — VERIFIED by `ls -la`:

```
~/.codex/app-server-daemon/daemon.lock            0 bytes
~/.codex/app-server-daemon/app-server.pid.lock    0 bytes
~/.codex/app-server-control/app-server-startup.lock  0 bytes
~/.codex/thread-writer-locks/.coordination.lock   0 bytes
~/.codex/cross-instance-locks/                    (directory, empty)
```

Two independent agent CLIs converged on the same primitive. That is the strongest available argument
for copying it rather than inventing.

### 2.3 Fencing tokens, and why a lock is not enough

Martin Kleppmann, *How to do distributed locking* (2016): a lock holder that **pauses** — GC, a
suspended laptop, a long API wait — cannot tell that it paused, so it can wake up believing it still
holds a lease that has expired and someone else now holds. The fix is a **fencing token**: a
monotonically increasing number issued with every lease. The holder attaches it to every write; the
resource remembers the highest token it has seen and rejects anything lower. Redis Redlock does not
provide one; its UUID tokens are unordered, so a resource cannot tell a current holder from a stale one.

Why this is not academic here. Three pause sources are documented in this very system:
1. **Rate-limit waits.** `harness-run.sh` calls `harness-limits.sh wait` and blocks for up to a
   five-hour window. During that time the orchestrator is a live process doing nothing.
2. **macOS sleep.** The previous run ended with
   `watch: orchestrator dead + no live sessions for 3 ticks — tearing down (Mac may sleep)`
   (`FIELD-NOTES.md` §10.1). `caffeinate` is the mitigation and it is bound to the watch pid — so when
   the watch dies, the Mac sleeps, and every session freezes mid-turn without dying.
3. **The owner's named death mode** — «кредит закінчився, тижневий ліміт» [266]. A credit-exhausted
   orchestrator is *paused*, not dead. It can resume hours later and start writing again.

A lock alone permits: orchestrator A pauses → lease expires → B takes over and merges phase 12 → A
wakes and merges phase 12 again. **The epoch number in §5.2 is the fence that makes A's second write
refusable.**

### 2.4 Supervision trees, restart semantics and crash loops

- **Erlang/OTP `supervisor`** (VERIFIED from the primary doc): *"Assuming the values `MaxR` for
  `intensity` and `MaxT` for `period`, then, if more than `MaxR` restarts occur within `MaxT` seconds,
  the supervisor terminates all child processes and then itself."* Defaults: `intensity` = 1,
  `period` = 5. Restart types: `permanent` (always restarted), `transient` (only on abnormal exit),
  `temporary` (never restarted). Strategies: `one_for_one`, `one_for_all`, `rest_for_one`,
  `simple_one_for_one`.
  **The design lesson is the give-up, not the restart:** a supervisor that cannot stabilise its
  children kills itself rather than loop.
- **systemd `systemd.service(5)`** (VERIFIED from man7.org):
  - `Restart=` takes `no, on-success, on-failure, on-abnormal, on-watchdog, on-abort, always`.
  - `RestartSec=` *"Defaults to 100ms."*
  - Exponential backoff via `RestartSteps=` + `RestartMaxDelaySec=`: the documented example
    `RestartSec=10s / RestartSteps=4 / RestartMaxDelaySec=160s` produces *"10s, 20s, 40s, 80s, 160s,
    160s, 160s, etc."*, ratio `(RestartMaxDelaySec / RestartSec)^(1 / RestartSteps)`.
  - `WatchdogSec=`: *"The service must call sd_notify(3) regularly with `WATCHDOG=1` (i.e. the
    'keep-alive ping'). If the time between two such calls is larger than the configured time, then the
    service is placed in a failed state and it will be terminated with SIGABRT."* — i.e. **the watchdog
    is a liveness lease the service itself renews**, which is precisely [249]'s «стан останнього запису».
  - `systemd.unit(5)`: `StartLimitIntervalSec=`/`StartLimitBurst=` — units that hit the start limit
    *"are not permitted to start any more"*, are *"not attempted to be restarted anymore; however, they
    may still be restarted manually"*, the interval *"may be set to 0 to disable any kind of rate
    limiting"*, and `systemctl reset-failed` flushes the counter.
- **launchd** (VERIFIED from `man 5 launchd.plist` on this machine):
  - `KeepAlive` *"may be set to true to unconditionally keep the job alive"*, or a dictionary of
    conditions which launchd **ORs**; `SuccessfulExit <boolean>` restarts on zero / non-zero exit.
    *"Jobs that exit quickly and frequently when configured to be kept alive will be throttled."*
  - `ThrottleInterval`: *"by default, jobs will not be spawned more than once every 10 seconds."*
  - `KeepAlive` *"implicitly implies RunAtLoad"*.
  - **INFERRED but important:** a LaunchAgent is the only supervisor on macOS that survives the
    terminal being closed, the user logging out of a shell, and the process being killed. `nohup` +
    `&` — which is what `harness-run.sh:93` uses for the watch loop — does not get restarted by anyone.

### 2.5 Crash-recovery state models

- **Event log vs snapshot.** The event log (append-only, never rewritten) is the authority; the
  snapshot is a cache that trades correctness for restart speed. The project's own supervisor doc
  already states this and states it well — **VERIFIED**, `.harness/supervisor/ORCHESTRATION.md`,
  *"The position file … holds the position, never the narrative … The real state is on disk anyway —
  tickets, markers, the registry, `.planning/`, the journal — so a stale position file costs restart
  speed, not correctness."*
- **At-least-once and idempotent replay.** A crash can land between "performed the side effect" and
  "recorded that I performed it". No ordering makes that window disappear; the only fix is that the
  side effect carries a **dedup key** the replayer can look for. Write `intent` **before** the action
  and `result` **after**; on replay, an `intent` with no `result` means *go look for the key*.
- **Evidence the window is real here.** `FIELD-NOTES.md` §11.7 records a three-step regression in the
  supervisor's pause path ending in issue `#82`, still open: *"the `STOP` write is still unconditional
  on the marker write succeeding, so a failed marker write leaves an unattributed `STOP` on disk."*
  That is an unpaired intent/result, in production, in this system.
- **The counter-example to trusting your own log.** `FIELD-NOTES.md` §12.7: *"A security review of a
  single API read found **26 refusal events in the audit log that never occurred**."* A journal is only
  worth what its write discipline is worth.

---

## 3. What is feasible, per platform

Measured on this machine, today. **Only `claude` and `codex` are installed** — VERIFIED:
`gemini`, `glm`, `qwen`, `crush`, `opencode`, `amp`, `aider`, `goose`, `droid` are all absent;
`cursor-agent` is present at `~/.local/bin/cursor-agent` and was not exercised. Everything the owner
said about GLM and Gemini at [255] is therefore **untestable here** and must be carried as an open
question, not designed against.

### 3.1 Claude Code 2.1.278 — far more is available than the previous harness used

**VERIFIED by running it.** `claude agents --json` prints active sessions as JSON, needs no TTY, and
costs nothing:

```
$ /usr/bin/time -p claude agents --json > /dev/null
real 0.19 / 0.18 / 0.18     (three runs)
```

0.18 seconds, **zero tokens**. Two row shapes:

```json
{"pid":35475,"cwd":"…/MNB","kind":"interactive","startedAt":1789743993512,
 "sessionId":"e4ea9e27-…","name":"mnb-60","status":"busy"}

{"id":"56da8644","cwd":"…","kind":"background","startedAt":1785861562856,
 "sessionId":"56da8644-…","name":"…","state":"blocked"}
```

- Interactive rows carry **`pid`** and **`status`**. Observed values: **`busy`, `idle`, `waiting`**.
- Background rows carry **`id`** and **`state`**. Observed values: **`working`, `blocked`, `done`,
  `failed`**. They carry **no pid** — VERIFIED across the union of keys in `~/.claude/jobs/*/state.json`.
- The per-session file adds `waitingFor` when a session is waiting. VERIFIED, read live:
  `"status":"waiting", "waitingFor":"input needed"`. **A machine-readable "this session is blocked on a
  human" flag** — the thing the previous generation had to screen-scrape for and got wrong repeatedly.
- `--all` also returns completed background sessions.

Supporting verbs, VERIFIED from `--help`:
`claude --bg/--background`, `claude attach <id>`, `claude logs <id>` (*"Print the background session's
recent terminal output"*), `claude stop|kill <id>` (*"Its conversation is kept; resume it later with
`claude attach <id>`"*), `claude rm <id>`, `claude respawn <id>|--all` (*"Restart a background session
(or all of them) so it picks up the current Claude binary"*), and `--resume <session-id>` which
*"continues that session in the background under the same ID, **or starts a copy and says so when the
session is already running**"*.

That last clause is a **platform-level single-instance check**, and the project's own doc records the
harder version of it — CLAIMED, `.harness/supervisor/ORCHESTRATION.md`: *"A live session's launcher is
never run a second time. Sessions carry a fixed `--session-id`, and a second `claude` cannot attach to
an id that is already in use — it fails at boot, instantly."* I did not reproduce this (it costs a
session), so it stays CLAIMED. The error string `is already in use.` does exist in the bundled
`cli.js` — VERIFIED, though the bundle I could read is 2.1.37 while the running binary is a Mach-O
arm64 executable at `~/.local/bin/claude` reporting 2.1.278.

**A non-TTY control channel exists.** `messagingSocketPath: /tmp/cc-socks/<pid>.sock` and
`peerFeatures: ["notify_idle","reply_across_default_dirs","artifact_yield"]`. VERIFIED by running
`ListAgents` from inside a session:

```
Peer sessions (3):
  design-analysis [5998b9]  ·  interactive  ·  waiting  ·  started 9m ago
  <work-project>-58   [b3f58b]  ·  interactive  ·  busy     ·  started 5d ago
  acceptance-walk [701f5a]  ·  interactive  ·  idle     ·  started 3h ago
```

**This retires the single worst failure class in the field notes.** §1.3: *"five separate instructions
typed into sessions were never delivered"*; §1.4: the engine's Enter *"does not submit stranded text"*;
§12.1: *"`send` fails silently above roughly 200 characters"* and *"a recovery attempt destroyed the
instruction it was recovering"*; §11.2: *"Two real operator instructions — `push master` and `carry on
with the queue` — sat unsubmitted in two sessions' input boxes while the engine log recorded them as
nudged."* A socket message is delivered or it errors. Nothing strands.

**The trap: the roster is per-account.** VERIFIED by running the same command under two switcher profiles
within seconds of each other:

```
CLAUDE_CONFIG_DIR=…/<profile-A>  → interactive: e4ea9e27, 3e5ee9d8, fe04c8bc, fd818302
CLAUDE_CONFIG_DIR=…/<profile-B>  → interactive: ee3bf681, 7eea3287, ac653a10, 53ff7331
```

Completely disjoint interactive sets. Background jobs (`~/.claude/jobs/`, the real `$HOME`) appear in
both. **A liveness probe run under the wrong account returns "not found", which reads as "dead".** That
is the precise mechanical path to two orchestrators, and it is the answer to the cross-provider
question in §5.5.

`claude` on this machine is a **shell function** installed by a profile switcher, not the binary — VERIFIED via
`which -a claude`. It reads a per-directory binding file in the cwd and `eval`s `<switcher> switch --print-env` before
exec'ing `~/.local/bin/claude`. This confirms the [199] inference: account
switching is `CLAUDE_CONFIG_DIR` plus a per-directory binding. Any journal entry that omits
`CLAUDE_CONFIG_DIR` is not reproducible.

Roster hygiene, measured: across the two active profiles, **9 session files, 9 live PIDs, 0 stale**.
Claude Code cleans up on exit. `/tmp/cc-socks/` does **not**: 24 sockets, **20 live, 4 stale**. So a
socket's existence is not liveness; the roster file plus `procStart` is.

**Still missing: context percentage.** `FIELD-NOTES.md` §3.3 — *"`bin/*.sh` contains no reference to
context, percentages, or compaction"*, and the percentage exists only on the session's own status line.
VERIFIED that this has **not** changed at the platform level: there is no context field anywhere in
`claude agents --json` or in `sessions/<pid>.json`. R1-08's «механізм, який гарантовано робить цю дію»
still has no non-screen source on Claude Code.

### 3.2 Codex CLI 0.152.0

VERIFIED from `--help` and from running it:

- `codex resume <SESSION_ID|name>` and `codex resume --last`; `codex fork`; `codex exec` for
  non-interactive runs; `codex archive` / `codex delete`.
- **`codex queue --thread <UUID|name> --message <TEXT>`** — *"Queue a message for an existing session"*.
  A non-TTY control channel, same class of win as the Claude socket.
- `codex agents` — *"Browse all agent sessions on the shared local app-server daemon"*. **TUI only; I
  found no `--json`.** Machine-readable liveness for Codex therefore comes from the filesystem, not
  from this verb.
- `codex doctor --json` — *"Emit a redacted machine-readable report"*. VERIFIED: `schemaVersion: 1`,
  `overallStatus`, `codexVersion`, and a `checks` map of `{id, category, status, summary, details,
  remediation, durationMs}`. **Cost: ~9.8 s wall clock.** Fine hourly, too slow for a 60 s tick.
  It also discloses the daemon's own liveness convention:
  `app_server.status → "background server is not running"`, with
  `pid file: ~/.codex/app-server-daemon/app-server.pid (missing)`.
- Transcripts: `~/.codex/sessions/YYYY/MM/DD/rollout-<ISO>-<uuid>.jsonl`. VERIFIED structure —
  line 0 is `session_meta` carrying `session_id`, `cwd`, `originator`, `cli_version`, `model_provider`,
  `source`, `thread_source`. Line types in a real 2.2 MB file:
  `{session_meta:1, realtime_item:448, event_msg:705, response_item:330, world_state:4,
  turn_context:124, token_usage_record:130}`.
  **Every line carries `timestamp` and a monotonic `ordinal`.** `ordinal` is a free progress counter
  and a natural per-session fence; `token_usage_record` is a free cost-and-progress signal.
- `~/.codex/session_index.jsonl` — `{id, thread_name, updated_at}` per thread, appended on update.
  A ready-made "last written record" index, exactly [249]'s shape.

### 3.3 Everything else

**Not feasible to design against today.** GLM, Gemini, Kimi and ChatGPT-as-a-platform are named by the
owner at [041] and [255] and **none is installed here**. Per his own instruction at [182]/[183] —
«це має бути оркестратор для всього, і якщо раптом десь немає лімітів, або десь інші ліміти … це треба
буде винести окремими питаннями потім» — each is a separate question, not an assumption. What the
design can do is make the probe a **data field** (§5.1) so an unknown platform costs a config entry
rather than a code change, which is also what [312] asks for («може написати свої власні скіли»).

---

## 4. What is NOT feasible, and why

**1. Detecting a live-but-useless agent deterministically. Not possible with any local signal.**
`FIELD-NOTES.md` §11.6 is the proof: an 85-minute loop in which the watch matched what looked like a
usage-cap banner *inside the orchestrator's own wrapped prose*, pressed Escape and sent `continue`
every ~60 s; *"each zero-second turn left the screen unchanged, so the same text matched again, for
ever … **Nothing internal detected it** — it ended when an external SIGTERM reached the orchestrator."*
Line 5620 of that log reads `NO ONE IS BEING TOLD`. Throughout, the process was alive, the screen was
changing, the heartbeat was fresh and the transcript was growing. Every cheap signal said healthy.
Only an outside judge with memory across ticks can catch this — which is an argument **for** the
owner's [246] cross-subscription agent, and the strongest one available.

**2. A quota read as a liveness signal.** VERIFIED right now: the Anthropic OAuth usage endpoint
returned **HTTP 429** `{"error":{"type":"rate_limit_error"}}` to a well-formed authenticated request.
`FIELD-NOTES.md` §11.7 records `weekly_all=unreadable%` recurring across many separate days and an
`authentication_error` stretch that *"blind[ed] every cap read, with nobody re-authenticating"*, plus a
weekly figure that *"fell from 26% to 6% **from the account switch alone**"*. An unreadable or wrong
quota must map to `UNKNOWN`, never to `dead` and never to `fine`.

**3. Cross-host liveness.** Nothing here works across machines. Recording `host` and `boot_id` makes
the situation *detectable* ("this lease was taken on a machine I am not") but not *resolvable* — only
a network lease service would resolve it, and that is over-engineering by [300]'s standard. The health
check on «якійсь іншій підписці» [246] is safe on the same Mac; the same check on a second Mac is not,
and would need its own design.

**4. `flock` on a synced or network state directory.** See §2.2. Not a bug to fix; a precondition to
enforce in preflight.

**5. Restoring conversation memory across providers.** `claude --resume` and `codex resume` are each
confined to their own platform **and their own account/config dir**. A Codex orchestrator cannot
inherit a Claude orchestrator's context. So the third case the interviewer offered at [291] —
*"основний провайдер недоступний, і відновлення йде через іншого"* — is always a **cold start from
written position**, never a warm resume. The owner never answered that case directly.

**6. Measuring a session's context window without reading its screen.** §3.1. Unchanged since the field
notes were written.

**7. Trusting `ps`/`pgrep` patterns to identify sessions.** `FIELD-NOTES.md` §11.8:
*"`pkill -f 'playwright test'` killed an unrelated lane, because every lane's own prompt text contains
that literal string, so `pgrep`/`pkill` over-match sessions rather than suites."* Process identity must
come from a recorded pid + start time, never from a command-line pattern.

---

## 5. Concrete proposals

Naming note: everything below is scoped to **one run**. "The run" is the unit the invariant at [300]
protects — «два якісь оркестратори» of *one run*.

### 5.1 The launch journal

**One append-only JSONL file per run: `journal.jsonl`. Never rewritten, never truncated, never
globbed away.** That last clause is not decoration: `FIELD-NOTES.md` §2.1 records that
`state/attention.tmp` was `: >` truncated and `mv`'d over **every single watch cycle**, destroying
everything any other process wrote to it, unnoticed all night — *"including a measured rebuttal
written while the orchestrator was weighing killing a 378-test suite at test 240."* And §11.3:
*"`state/attention.tmp` found truncated to zero bytes on every pass."* A journal that any component
rewrites is not a journal.

One line per lifecycle fact. Short lines, `O_APPEND`, no reader ever locks it.

```json
{"seq":41,"at":"2026-09-19T20:11:03.114Z","epoch":7,"event":"orchestrator.claim",
 "run":"20260919-201055",
 "actor":{"provider":"claude-code","account":"<profile-A>",
          "config_dir":"/Users/…/.<switcher>/profiles/<profile>",
          "session_id":"ac653a10-…","pid":86924,
          "proc_start":"Sat Sep 19 12:51:09 2026",
          "host":"<host>","boot_id":"<boot-id>"},
 "probe":{"cmd":["claude","agents","--json"],
          "env":{"CLAUDE_CONFIG_DIR":"/Users/…/.<switcher>/profiles/<profile>"},
          "match":{"sessionId":"ac653a10-…"},
          "alive_when":"row present","status_field":"status"},
 "prev":{"epoch":6,"verdict":"dead","evidence":["pid 61402 absent","lease expired 41m"]}}
```

Event vocabulary, deliberately small:
`run.create` · `orchestrator.claim` · `orchestrator.release` · `orchestrator.evict` ·
`lease.renew` (sampled, not every beat) · `session.spawn` · `session.close` · `session.observe` ·
`step.intent` · `step.result` · `health.probe` · `provider.failover` · `owner.action`.

Four properties, and the reason for each:

1. **`epoch` on every line.** It is the fencing token (§5.2) and it is also the crash-loop detector: N
   `orchestrator.claim` lines within T minutes with no `step.result` between them **is** a restart loop,
   detectable by `grep` and nothing else. This is the answer to the owner's own stated fear —
   «нескінченний цикл оркестраторів» [300].
2. **`probe` is data, not code.** The journal carries *how to ask whether this actor is alive*, in the
   actor's own terms, including its `env`. This is [310] («для кожної платформи можна налаштовувати»)
   and [312] («може написати свої власні скіли») expressed as a field. A platform nobody has installed
   costs one config entry.
3. **`prev` records the verdict and the evidence** for the previous holder being dead. That is
   [300]'s «переконуєш що воно не спрацювало, а після того запускаєш новий» written down — so that a
   later reader, or the owner, can check whether the orchestrator was entitled to start.
4. **`step.intent` before the side effect, `step.result` after**, both carrying an `action_id` of
   `run:epoch:step:attempt`. The dedup key goes **into** the side effect — the ticket comment, the
   branch name, the commit trailer — so a replayer can find it without trusting the journal.

**Accounting, per [189].** For a run configured on GSD the journal does **not** duplicate the process's
state. It records a reference plus a witness anchor. VERIFIED that GSD already publishes one —
`.planning/STATE.md` frontmatter on the <work-project> repo reads:

```yaml
current_phase: 30
current_plan: 16
status: verifying
stopped_at: Completed 30-16-PLAN.md
last_updated: "2026-09-19T04:54:05.017Z"
state_head: 5154f24f519f3d816f8c3191c2c1468221699e55
```

`state_head` is a git SHA. So the journal line is:
`{"event":"step.result","process":"gsd","ref":".planning/STATE.md","state_head":"5154f24…","read_at":"…"}`
— *"нічого не треба окремо записувати, а лише записувати оце референс"* [189], literally.

**One caution the owner should hear.** That same `STATE.md` contains, in its own `last_activity`, the
sentence *"the false claim that state.json is derived from that table withdrawn and the file declared
hand-maintained"*. A process's own record can be hand-maintained, and then a reference to it is a
reference to a claim. The three-way rule at [171] («якщо його недостатньо, то ведеться з посиланням,
плюс тої дати, якої не вистачає») already covers this — the missing piece is *how the orchestrator
decides that a process's record is insufficient*, and that is an open question below.

### 5.2 The lease and the fence

Two files, two jobs. Neither is the journal.

**`run.lock` — the enforcement half.** Held for the orchestrator's entire lifetime by
`lockf -k -t 0 run.lock <orchestrator-command>`. Nothing reads it, nothing parses it, nobody cleans it
up. If a process holds it, an orchestrator is alive; if `lockf -t 0` succeeds, none is. The kernel is
the authority and it is never wrong. **This is the whole of «відслідковувати і не дозволяти» [301]** —
one line of shell, which is what «надійна річ, дуже проста» [300] asks for.

**`lease.json` — the readable half.** Rewritten atomically (tmp + `rename`) every `renew_seconds`
(proposed: 30) by the orchestrator itself:

```json
{"epoch":7,"run":"20260919-201055","renewed_at":"2026-09-19T20:21:09Z","ttl_seconds":180,
 "holder":{"provider":"claude-code","account":"<profile-A>","pid":86924,
           "proc_start":"Sat Sep 19 12:51:09 2026","session_id":"ac653a10-…",
           "host":"<host>","boot_id":"<boot-id>"},
 "position":{"active_steps":["T-118","T-121"],"last_step_result_at":"2026-09-19T20:07:44Z"}}
```

This is **[249] implemented**: «перевіряти стан останнього запису … Коли … останній раз... щось...».
It is also the systemd watchdog pattern (§2.4) with the file taking the place of `sd_notify`.
Note `last_step_result_at` as a separate clock from `renewed_at`: **the lease proves the orchestrator
is breathing; `last_step_result_at` proves the run is moving.** Conflating those two is exactly the
mistake that produced 33 nudges.

**`epoch` is the fencing token.** Monotonic, `max(lease.epoch, max epoch in journal) + 1` at each claim.
Every externally visible act the orchestrator performs carries it:

- ticket status transitions and comments: a trailer line `orchestrator-epoch: 7`
- spawned session names: `o7-w-T118` (so a stray session's epoch is visible in `claude agents --json`
  and in the terminal title — and a stale-epoch session is identifiable at a glance, which the
  `q-screen-orchestrator` incident in `FIELD-NOTES.md` §1.6 shows matters to a human reading titles)
- commits the orchestrator itself makes: a `Orchestrator-Epoch: 7` trailer
- every `step.intent` / `step.result` line

**The rule the fence buys:** *a step may only be committed by the epoch that opened it; anything
arriving from a lower epoch is recorded and discarded, never applied.* Without this, a paused
orchestrator that wakes after a rate-limit wait can merge a phase that the new orchestrator already
merged. With it, the second merge is refusable and, more importantly, **loud**.

**Trade-off, stated honestly.** `lockf` alone is simpler and covers crash and SIGKILL, which is most of
reality. The epoch is the extra 10% that covers *pause*, and pause is the owner's own named death mode
(«кредит закінчився» [266]). Recommendation: ship both, but ship `lockf` first and treat the epoch
trailers as an incremental hardening — an epoch that nothing yet checks still costs nothing and makes
the journal legible.

### 5.3 Progress vs liveness — the signal contract

R1-09 says the orchestrator decides. It cannot decide well on signals whose failure modes are unknown,
and every cheap signal's failure mode **is** known, from this system's own logs:

| Signal | What it actually proves | Documented false positive | Source |
|---|---|---|---|
| `lockf` refused | an orchestrator process exists | none | VERIFIED here |
| `kill -0 pid` | a process with that number exists | PID reuse (maxproc 6000); says nothing about stopped/wedged | VERIFIED here |
| pid + `proc_start` + `boot_id` | **that exact process** | none known | VERIFIED — Claude Code uses it |
| `claude agents --json` `status` | the platform's own idle/busy/waiting | **invisible under the wrong `CLAUDE_CONFIG_DIR`** | VERIFIED here |
| `waitingFor` | the session is blocked on a human | none known | VERIFIED here |
| heartbeat file age | the last **turn boundary** | *"A session heartbeats between turns … The engine's watch loop treats staleness as a stall and nudged six times in this run … every one of those sessions was healthy"* | FN §1.5 |
| transcript mtime / line count | a message was appended | pauses for the whole of a long turn — **measured here: 0 bytes of growth over 3 s while a subagent did heavy work** | measured |
| tool-call cadence | tools are being called | *"3,466 of 3,626 Bash calls were the literal command `echo idle`"*, 1,400/hour, 445k tokens of context burned, zero progress | FN §3.1 |
| shell / child-process count | a command is running | *"A shell that cannot exit reads as work"* — `until grep … sleep 5` against a file finished 45 min earlier; *"no check would ever have called that session parked"* | FN §2.2 |
| git activity in the session's tree | real output landed | silent for planning, research, review, docs — and N2 [344] says there may be no repo at all | FN + [344] |
| screen scrape | nothing reliably | a session's own *report* of a condition matched as the condition → the 85-minute loop; four detector false positives fixed in one day; a non-ASCII space misread as an unsent nudge | FN §11.6, §11.3 |
| board/ticket transition | a status was written | the underlying action may have done nothing — *"A merge reported success and did nothing"* | FN §4.1 |

**Three rules follow, and they are the substance I would put back to the owner under R1-09:**

- **R1. No single signal raises or clears a stall.** A stall verdict needs agreement from at least two
  *independent* signals — independent meaning they cannot both be produced by the same cause. Heartbeat
  age and transcript mtime are **not** independent: a long turn silences both.
- **R2. Any signal the session can author is inadmissible alone.** Screen text, self-reported status,
  a log line the session wrote. This rule alone would have prevented the 85-minute loop, the 45-minute
  banner loop and the *"validator's own quoted warning text triggering a full alarm"* (FN §11.3).
  The project already learned it the expensive way — `ORCHESTRATION.md`: *"It cannot tell a session's
  report of a condition from the condition itself … a session that reports 'no rate-limit banner' every
  cycle gets interrupted every cycle, all night, and never finishes a thought."*
- **R3. Observe before acting, and record the observation.** The 33 nudges (FN §12.3, counted over
  `2026-09-11T22:49Z`–`2026-09-13T06:29Z`) happened because the first observation was also the action.
  A verdict should require the same reading on two consecutive ticks, and the intervening observation
  must survive to the next tick — which is only true if it is journal-appended rather than written to a
  file something else truncates.

**What replaces the nudge.** For Claude Code, nothing needs to be typed at all any more: read `status`
from the roster, and if the session needs something, deliver it over the peer channel
(`SendMessage` / the socket), which either delivers or errors. For Codex: `codex queue --thread …
--message …`. The blind Enter — origin of five lost instructions, one 149-minute stall and one
destroyed recovery attempt — has no remaining job.

### 5.4 The health check, in three layers

The owner proposed one layer [246]. One layer has an N-hour blind window and costs tokens. Three layers
cost almost nothing and each catches what the others cannot. **Only L2 is what he described; L0 and L1
are proposed additions and should be put to him as such.**

**L0 — the orchestrator's own tick. Free, deterministic, every 30–60 s.**
`lockf` held · lease renewed · for each session in the journal, run its recorded `probe` · `kill -0` +
`proc_start` match · `claude agents --json` (0.18 s, 0 tokens) · `last_step_result_at` age.
No model involved. This is the layer that makes R1-09 answerable at all.

**L1 — an outside watchdog on the same machine. Free, deterministic, every 2 min.**
A **LaunchAgent**, not `nohup`. It does exactly three things and **never restarts anything by itself**:
(a) read the lease; (b) if `now − renewed_at > ttl` **and** `lockf -t 0` succeeds, the orchestrator is
gone — append `health.probe` with the verdict and the evidence; (c) if a recovery policy is configured,
invoke the recovery entry point **once**, subject to the respawn budget below.
Why launchd: `FIELD-NOTES.md` §12.4 — *"Three detached scripts must export the `gh` account themselves …
because launchd and `nohup` start with no environment"*. The plist must therefore set
`EnvironmentVariables` explicitly: `PATH`, `CLAUDE_CONFIG_DIR`, `GH_CONFIG_DIR`. Set `ThrottleInterval`
explicitly rather than inheriting the 10 s default.
Also §11.6: the previous generation's watchdog *"had already exited ('run finished') and was never
restarted"* while a loop ran for 85 minutes. `KeepAlive` is what fixes that, and only launchd has it.

**L2 — the owner's agent, on a separate account if he configures one, every N hours. Costs tokens, and earns them.**
This is [246] as he stated it, and it is the **only** layer that can catch a live-but-useless run
(§4.1). It is a *judgement*, not a probe. Give it exactly three inputs and one question:
inputs = the last N hours of `journal.jsonl`, the current `lease.json`, and the ticket board's diff
over the same window; question = *"has this run produced anything in the last N hours, and if not,
why not?"* Verdicts: `progressing` · `stalled-but-recoverable` · `wedged` · `finished` · `unknown`.
It writes its verdict to the journal and, per configuration, either acts or notifies.
Its account must be one **allowlisted for the orchestrator role** — [270] «може використовувати тільки
для оркестратора … І це важливий дуже нюанс» — and proven working before the run — [199] «перед
запуском потрібно переконатися, що це працює».

**Crash-loop budget.** Borrowed from §2.4, sized to the owner's own only number.
Backoff `60s → 120s → 240s`, capped at 15 min (systemd's `RestartSteps` shape). Budget: **3 claims in
60 minutes**; on exhaustion, stop claiming, write `DEAD-RUN`, notify through the configured channel,
and wait for a human. This is Erlang's *"the supervisor terminates all child processes and then itself"*
rather than an infinite retry, and it mirrors systemd's *"not attempted to be restarted anymore;
however, they may still be restarted manually"*.
**Flagged honestly:** «Три рази» [442] was said about *a task failing the same way three times*, not
about orchestrator restarts, and he immediately added «В який момент не знаю». Reusing the number keeps
one vocabulary; it is a proposal, not his decision.

### 5.5 The recovery decision tree

Entered by any agent that believes it should be orchestrator of run R — a fresh start, an L1 watchdog
callback, or an L2 verdict.

```
0. ACQUIRE            lockf -t 0 -k <run>/run.lock
   ├─ refused ........ an orchestrator process is alive. Append orchestrator.claim.refused
   │                   with the reason. EXIT 0. Do not spawn. Do not notify. ← [301]
   └─ acquired ....... continue

1. IDENTIFY THE PREVIOUS HOLDER      (read lease.json + tail of journal.jsonl)
   a. no lease at all ............................ first start of this run → step 2
   b. host ≠ me OR boot_id ≠ current ............. previous holder cannot be evaluated here.
                                                   Not dead — UNKNOWN. → 1e
   c. pid alive AND proc_start matches ........... CONTRADICTION: it is alive but not holding
                                                   the lock. Release, append an alarm, notify
                                                   the owner. NEVER spawn. (Deleted lock file,
                                                   or a state dir on a synced volume.)
   d. pid absent, OR proc_start differs, OR the
      recorded process has no pid (a background
      job) and its platform probe says gone ...... DEAD. Evidence recorded. → step 2
   e. probe unreadable / quota 429 / wrong
      account / unknown platform .................. UNKNOWN. Treat as ALIVE and wait, until
                                                   now − renewed_at > ttl × 3. Then DEAD by
                                                   timeout, and say so in the evidence.

2. FENCE              epoch = max(lease.epoch, max journal epoch) + 1
                      append orchestrator.claim{epoch, actor, probe, prev{verdict, evidence}}
                      write lease.json at the new epoch
                      check the respawn budget; if exhausted → DEAD-RUN + notify + exit

3. REBUILD POSITION   in the configured order — his default first [293]:
                      (1) state files        ← default
                      (2) the process's own records (GSD .planning/, state_head)   ← [189]
                      (3) previous sessions  ← [293]
                      (4) their transcripts  ← [293], [310], per-platform, from `probe`
                      Stop at the first source that answers. Record which one answered.

4. RECONCILE OPEN STEPS      for each step.intent with no step.result at any epoch:
   ├─ dedup key found in the world (ticket comment / branch / commit trailer)
   │        → it happened. Append step.result{recovered:true}. Do not redo.
   ├─ key absent AND the step is declared idempotent    → redo under the new epoch
   └─ key absent AND not idempotent, or ambiguous       → mark the ticket blocked, put the
                                                          question in the questions channel [Д6],
                                                          continue with independent work [Д6]

5. ADOPT THE EXECUTORS  (Д10 — «оркестратор сам повинен проаналізувати» [497])
   for each session.spawn with no session.close, run ITS recorded probe:
   ├─ alive, status busy ......... adopt. Wait. Do not touch. ← [497] «просто почекати»
   ├─ alive, status waiting/blocked → it needs input; answer within authority [324] or escalate
   ├─ alive, status idle, no marker → the orchestrator decides stop-or-wait ← [497]
   └─ gone ....................... its step goes back to step 4

6. RESUME
```

Two notes on the tree:

- **Step 1c is the case nobody writes and everybody hits.** The lock and the lease disagreeing means a
  premise has broken — a state directory on iCloud, a hand-deleted lock, a `kill -9` that left a
  detached child. The right behaviour is to stop and shout, not to guess. The owner's «не окей»
  [300] is about *two running*, and this branch is how you avoid creating exactly that.
- **Step 1e is where over-eagerness kills a run.** VERIFIED today: the quota endpoint returned 429 to a
  valid request. `FIELD-NOTES.md` §11.3 records a probe that *"could never succeed and never
  complained"* — BSD `find -newermt` erroring with stderr to `/dev/null`, *"which would have declared
  every healthy session idle for ever."* **Every probe in this design must distinguish `false` from
  `error`.** A probe that cannot say "I don't know" will eventually say "dead" about a healthy run.

### 5.6 When the recovering agent is a different provider

The specific question, and the sharpest one in the cluster.

**The mechanical hazard, VERIFIED (§3.1):** `claude agents --json` is scoped to `CLAUDE_CONFIG_DIR`.
Two profiles on this machine return **disjoint** interactive rosters. A Codex orchestrator recovering a
Claude orchestrator, or a Claude orchestrator on account B recovering one from account A, that asks
"is it alive?" with its own tooling gets **"not found"** — which reads as dead. That is the shortest
path to «два якісь оркестратори», and it is not hypothetical: it is one environment variable.

**Four rules.**

1. **The OS facts come first, and they are provider-blind.** `lockf`, `kill -0`, `proc_start`, `boot_id`
   work identically whoever asks, as long as it is the same Mac and the same user. **Step 0 of the tree
   is therefore already cross-provider-safe.** Design so that the common case never needs a provider
   probe at all.
2. **A provider probe is run as the actor that started the session, never as the recoverer.** The
   journal carries the probe with its `env`; the recoverer executes it verbatim
   (`CLAUDE_CONFIG_DIR=…/<profile-A> claude agents --json`) and reads the recorded `match`. It never
   substitutes its own. This makes [310]'s per-platform recovery a data lookup and [312]'s user-written
   skill a `probe.cmd` entry.
3. **No probe, no eviction.** If the journal has no probe for an actor, or the probe errors, the
   verdict is UNKNOWN and the only route to DEAD is the lease-TTL timeout (1e), with the evidence
   saying so. An orchestrator may never conclude "dead" from "I couldn't look".
4. **Cross-provider recovery is always cold.** `claude --resume` and `codex resume` do not cross
   platforms or accounts. So the recovering agent starts a **new** session from written position, which
   is why §5.1's position record and §5.5's step 3 ordering carry the whole weight. Practically: keep
   the position file small enough that a cold orchestrator on any provider can read it in one turn, and
   keep `state_head`-style anchors in it so it can verify what it read.

**And the constraint that outranks all four:** the failover target must be an account **allowlisted for
the orchestrator role** [270] and **proven working before the run** [199]. A fallback chain that has
never been exercised is a fallback chain that fails at 03:00. The preflight should actually start and
stop a throwaway session on each configured fallback, not merely check that a key exists.

### 5.7 Detecting that a claimed-done step really happened

R1-13 is settled and not mine to reopen: *"verification belongs to the configured process"* [344], and
the orchestrator imposes no checks of its own. **What follows is deliberately narrower:** how the
orchestrator knows that **its own** bookkeeping actions happened — the merge it performed, the ticket
it transitioned, the session it closed. That is not verification of the work; it is the orchestrator
not lying in its own journal. The evidence that this is a real and separate problem:

- *"A merge reported success and did nothing"* — `git checkout master` aborted on a dirty
  `.planning/milestone.lock`, so the merge ran on the phase branch against itself and printed
  `Already up to date` and `Everything up-to-date`. *"Both read like success."* (FN §4.1)
- *"GSD's verify stage was silently skipped for phases 14 to 18 … No automated check caught it."* (§11.4)
- *"A self-patch script reported `SYNTAX OK` while its `sed` anchor never matched and nothing was
  written."* (§12.2)
- *"A memory-truncated test run reported a clean-looking result. 346 passed, 0 failed — caught only by
  arithmetic."* (§11.5)
- *"26 refusal events in the audit log that never occurred."* (§12.7)
- An entire class of commit gates *"found by mutation rather than by the gate failing."* (§11.9)

**The principle: never accept a claim; accept a witness.** A witness is an artefact produced as a
side effect of the action, which the claimant did not author.

| Action | Claim (rejected) | Witness (accepted) |
|---|---|---|
| merge to trunk | the command's stdout | `git merge-base --is-ancestor <branch> <trunk>` is true **and** `git rev-parse <trunk>` moved |
| a step produced a file | "written" | the path's `mtime` **and** content hash, recorded before and after |
| a test suite ran | the summary line | the runner's own machine-readable report, **plus** `total == passed + failed + skipped` (the arithmetic that caught §11.5) |
| a ticket moved | the API call returned 200 | re-read the ticket; the dedup key from §5.1 is in it |
| a GSD step completed | the session says so | `.planning/STATE.md`'s `state_head` moved to a commit that exists |
| a session closed | `close` returned 0 | the pid is gone **and** the roster row is gone |

**One universal, domain-blind witness is worth building:** record the mtime+hash of the artefacts a
step declared it would produce, before and after. A step that claims done and changed nothing is
detectable without knowing anything about what it was supposed to do — and "changed nothing" is the
exact signature of four of the six incidents above.

**Where this collides with R1-13, stated plainly rather than resolved.** He said «не роби обмеження те,
що вся робота потім буде мати тести» [344] and that the orchestrator adds no checks. A witness rule is
not a test and not a gate — but it *is* the orchestrator declining to believe a session. If he reads
that as the orchestrator imposing its own verification, his decision stands and this section should be
cut to just the three actions the orchestrator performs **itself** (merge, ticket transition, session
close), where nobody could argue it is checking someone else's work. That is the version I would ship
absent a ruling.

---

## 6. Open questions this raises for the owner

Ordered by how much of the design is blocked on the answer.

**Q-C6-1 — R1-09 has no yes.** [231] is his, but [238] «Гаразд, зафіксував» landed on a half-finished
sentence and he never confirmed. Before anything is built on "the orchestrator decides", read it back
and get a yes or a correction.

**Q-C6-2 — Will you accept a signal contract under R1-09?** You said the orchestrator judges progress.
Every cheap signal has a documented false-positive mode in your own field notes (33 nudges; a shell
that can never exit reading as work). Do you accept the three rules in §5.3 — *two independent signals,
nothing the session authored, observe twice before acting* — as the floor the orchestrator judges on?
Or should the orchestrator be free to act on one signal when it decides that is right?

**Q-C6-3 — One health-check layer or three?** You described an agent every N hours on another
subscription [246]. §5.4 adds two free deterministic layers under it, because an N-hour check has an
N-hour blind window and your 85-minute loop happened inside one. Do you want L0 and L1, or is the
cross-subscription agent the whole of it?

**Q-C6-4 — Reserve, or spend to zero?** `questions.md` R1-06 asked *«Чи можна витрачати ліміт до нуля,
чи треба лишати запас на твою власну роботу?»* — **the interviewer dropped the clause at [169]/[170]
and never returned to it.** It belongs here because your named orchestrator death mode is «кредит
закінчився, тижневий ліміт» [266]: whether the orchestrator may spend to zero decides whether that
death is a bug or the design working. And you work in the same account you are asking it to spend.

**Q-C6-5 — Live-but-useless: who has the authority to kill?** A run can be alive, busy, heartbeating and
producing nothing (§4.1 — 85 minutes, nothing internal detected it; 3,466 `echo idle` calls burning 445k
tokens of context). Only an outside judge catches this. May the L2 agent stop a live orchestrator on its
own judgement, or must it always come to you? This is R1-14's autonomy question wearing a different hat.

**Q-C6-6 — UNKNOWN is not DEAD. Confirm the fail-safe direction.** When a liveness probe errors — quota
429 (which happened while I was writing this), wrong account, a platform with no probe — I propose the
orchestrator **waits** rather than spawns, and only converts UNKNOWN to DEAD after the lease has been
expired for 3× its TTL. That trades "the run sits still for a while" against "two orchestrators". Your
[300] says two is «не окей», so I read you as preferring the wait. Confirm, and give me the multiple.

**Q-C6-7 — Restart budget.** How many times may an orchestrator be restarted before the run stops and
comes to you? I propose 3 in 60 minutes with 60/120/240 s backoff, reusing your «Три рази» [442] — but
you said that about a task failing the same way three times, and added «В який момент не знаю». Is the
number transferable?

**Q-C6-8 — Preflight may refuse the state directory.** `flock` is not reliable on iCloud, Dropbox or a
network share, and the whole single-orchestrator invariant rests on it. Should preflight **refuse to
start** a run whose state directory is on a synced volume, or warn and proceed?

**Q-C6-9 — Cross-provider recovery is always a cold start.** The interviewer offered you the case at
[291] (*"основний провайдер недоступний, і відновлення йде через іншого"*) and you answered the general
shape at [293] without addressing it. Confirmed by testing: neither `claude --resume` nor `codex resume`
crosses platforms or accounts. So a cross-provider recovery **never** has the dead orchestrator's
memory. Does that change what you want written into the position file — specifically, how much a cold
orchestrator on any provider must be able to read in one turn?

**Q-C6-10 — «стан останнього запису» [249].** You started to name a mechanism and were talked over;
the analysis lost it. §5.2 implements it as a lease file with two clocks — one for *the orchestrator is
breathing*, one for *the run is moving*. Is that what you meant, or did you mean the last record in the
**work** (a ticket, a commit), not in the orchestrator's own bookkeeping?

**Q-C6-11 — the reference-only accounting assumption.** At [189] you said for GSD «майже нічого не треба
робити» and flagged it yourself: «Я можу помилятись». Verified: GSD does publish `.planning/STATE.md`
with `current_phase`, `status`, `stopped_at`, `last_updated` and a `state_head` git SHA — so a reference
really is close to enough. But that same file, on your own project, records that it is **hand-maintained**
and that a claim about it being derived was withdrawn. So: what makes a process's record *insufficient*,
in your terms, such that the orchestrator starts keeping the delta [171]?

**Q-C6-12 — Д10 has no yes either.** [497] is yours; [500]/[501] were never answered before the
interviewer moved to Д11. Step 5 of the recovery tree is written directly from it and should be
confirmed.

---

## Appendix — commands and files this research actually ran or read

Run on this machine, 2026-09-19:
`command -v flock` (absent) · `man shlock` · `man 1 lockf` · `man 5 launchd.plist` · `man caffeinate` ·
`sysctl kern.boottime kern.maxproc kern.maxprocperuid` · `ps -o pid,lstart,etime` ·
`mkdir`/`ln`/`noclobber`/`lockf` atomicity and SIGKILL-release tests ·
`claude --version` (2.1.278) · `claude --help` · `claude agents --help` · `claude agents --json`
(with and without `--all`, under two `CLAUDE_CONFIG_DIR`s) · `claude respawn/logs/stop --help` ·
`ListAgents` · `codex --version` (0.152.0) · `codex --help` · `codex resume/agents/queue/doctor --help` ·
`codex doctor --json` · Anthropic OAuth usage endpoint (HTTP 429).

Files read:
`~/.claude/jobs/*/state.json`, `~/.claude/jobs/*/timeline.jsonl`, `~/.claude/jobs/pins.json` ·
`~/.claude/daemon/roster.json` · `~/.<switcher>/profiles/*/sessions/<pid>.json` · `/tmp/cc-socks/` ·
`~/.codex/{app-server-daemon,app-server-control,thread-writer-locks,cross-instance-locks,process_manager,ipc}/` ·
`~/.codex/session_index.jsonl` · a 2.2 MB `~/.codex/sessions/.../rollout-*.jsonl` ·
a 2.8 MB Claude Code transcript JSONL ·
`plugins/harness/bin/{hlib.sh,harness-run.sh,harness-state.sh}` ·
`plugins/harness/docs/FIELD-NOTES.md` ·
`<work-project>/.harness/supervisor/ORCHESTRATION.md` · `<work-project>/.planning/STATE.md` ·
`round-1/TRANSCRIPT-01.md` rows [171]–[195], [226]–[320], [493]–[505] ·
`round-1/ANALYSIS-01.md` · `research/extract/{by-item,outside-list,corrections,meta}.md`.

**Not available:** `research/.../scratchpad/context/` (harness-evidence.md, orchestrator-landscape.md,
snf-architecture.md) — **the directory exists and is empty**, so none of that prior research was
re-used and none of it is relied on here.

Web sources (secondary, used only for §2.3–2.4):
- Martin Kleppmann, *How to do distributed locking* — https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html
- Erlang/OTP `supervisor` — https://www.erlang.org/doc/apps/stdlib/supervisor.html
- `systemd.service(5)` — https://man7.org/linux/man-pages/man5/systemd.service.5.html
- `systemd.unit(5)` — https://man7.org/linux/man-pages/man5/systemd.unit.5.html
