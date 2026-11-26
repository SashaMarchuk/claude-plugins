# C8 — Blast radius, the red-line file, and end-of-run cleanup

Cluster items: **R1-15** (the red line), **R1-16** (not touching what it did not start), **Д3** (end of
the run), **owner instruction I3** (a Fable agent must analyse the boundary question and return
options).

Date of research: **2026-09-19**. Everything marked VERIFIED was read in source, in official docs, or
executed on this machine today. Versions on this machine: Claude Code **2.1.278**, codex-cli
**0.152.0**, Docker **28.5.1**, git **2.33.0**, macOS **26.5.2 (25F84)**. Gemini CLI and opencode are
**not installed here** — every claim about them is CLAIMED from their docs, not VERIFIED.

---

## 0. The one thing to read first

The owner asked for options. Before the options, the single fact that reframes the whole question:

**The thing he explicitly does not want to build — a deterministic isolation mechanism — is already
built, already on this machine, and costs one line of JSON.** It is not a container, not a VM, not a
new procedure, and not something he has to maintain. It is the operating system's own sandbox, which
both Claude Code and Codex already ship and already know how to drive.

Executed here today, in a session running `--permission-mode bypassPermissions` (his own default):

| what was attempted | result |
|---|---|
| write to a file in a neighbouring folder | `operation not permitted` — file untouched |
| `docker ps` | `connect: operation not permitted` on the daemon socket |
| `kill -TERM <pid>` against a process the session did not start | `operation not permitted` — process survived |

No prompt, no model judgment, no prose rule. VERIFIED, transcripts in §2.3.

That does not settle the question — the same sandbox also blocks the orchestrator's **own** Docker
work and its **own** teardown (§4.2, §4.3), and that collision is the real design problem. But it
means the choice in front of him is not "simple prose versus over-engineering". It is "which of
several cheap mechanisms, and what do we give up".

---

## 1. What the owner decided, in his own words

### R1-15 — the red line [357]

> "Я думаю, що є сенс добавити в архітектуру якийсь текстово писані або текстово писані правила, які
> не можна, наприклад, порушувати, тощо, так далі, і ці виключення повинні читатися в обов'язковому
> порядку всіма, хто має, хто буде працювати в цьому, з цим оркестратором, і так далі, з цим плагіном."

> "Має бути якісь визначене місце, де може людина додавати якісь різного типу обмеження"

> "Також якщо людині потрібно якісь додаткові різні обмеження, то вона це може робити, власноруч
> налаштовуючи своє середовище. … Достатньо лише одного файлу, який може доповнюватись, текстописний,
> де будуть деталі щодо якихось заборон, виключень, тощо, так далі."

In English, the rest of the answer: agents then simply follow it, and no separate mandatory procedure is needed.

> "Але, так, це максимум"

Four things in that answer, and only two of them survived into `ANALYSIS-01.md`:

1. **One appendable text file, in a defined place, read by everyone.** Recorded.
2. **No separate mandatory procedure in the plugin.** Recorded.
3. **"різного типу обмеження"** — restrictions come in *types*. The analysis flattens this into "one
   text file". A type field is a design hook he offered and nobody picked up. (Corroborated by
   `extract/by-item.md`, R1-15 row 2.)
4. **"Але, так, це максимум"** — this is a *ceiling*, not an endorsement. It is the strongest
   constraint in the item and the analysis drops it entirely (`extract/by-item.md`, R1-15 row 5).

**And R1-15 was never confirmed.** The interviewer restated it at [358]/[359] and moved to R1-16 at
[360] with no answer in between. The owner's own last words on it were a question back to the
interviewer — "Чи це є відповідно до твоєго питання" [357] — which the interviewer answered itself
("Так, це відповідає на питання" [358]). `extract/corrections.md:72` calls this "the weakest-grounded
answer in the interview", filed as SETTLED. Treat R1-15 as **UNRATIFIED**, not settled.

### R1-16 — not touching what it did not start [366], [370], [373]

> [366] "має гендлитися таким чином, що в оркестратори **прописаний шлях, до чого він має доступ**"

> [366] "якщо оркестратор запускається … він виконав роботу для <company> вебсайту. І в середині папці він
> виконує роботу. Якщо є окремо нетворк 3, то він відповідно до них теж не має доступу."

> [366] "оркестратор має бути якось селфевернес, що він, до чого він може змінювати, а що не може, і
> він має працювати тільки з тим, що він працює, і нічого іншого він не мав би доторкатися. Тобто він
> би не мав зупиняти якісь там тести, які не він запускав"

> [370] "перший кейс це те, що наприклад, я працюю вклад коді, але я працюю з іншим, наприклад, іншою
> папкою, іншим проектом, то цей оркестратор, він цього не має трогати. Другий кейс, якщо, наприклад,
> в тій самій папці я паралельно працюю над чимось, це не запускав оркестратор, це роблю я, він цього
> не має зупиняти."

> [370] "я не хочу якихось детерміністського варіанту для цього, тому що він буде дуже складний
> оверінжир... оверінжиринг, але дуже якісь простий та надійний варіант для цього має бути прописаний
> в плагіні, щоб оркестратор розумів, на що він може впливати, що ні"

> [373] / [375] "Чи якоїсь конфіг... Я би не сказав, **я би це робив якось абстрактно**"

Three points that matter for the options and that `ANALYSIS-01.md` does not carry:

- **He named a mechanism himself**: "прописаний шлях, до чого він має доступ" [366] — a written list
  of what it may reach. That is, almost word for word, what `sandbox.filesystem` and cwd confinement
  are. Proposing a path list is therefore **not** substituting my preference for his; it is enforcing
  the one he proposed.
- **He rejected a config knob** [373] and asked for the rule to be *abstract*. So the rule belongs in
  the plugin as a stated invariant; the *medium* that enforces it is per-platform plumbing the plugin
  chooses, not a field he fills in.
- **The "деterministic variant" he rejected** was described to him, at [364]/[365], as "окреме
  середовище, з якого він узагалі не має доступу" — a *separate environment*. That is a container or a
  VM. Nothing in the transcript rejects an OS-level path boundary, because nobody offered him one.
  This is the single most important distinction in this document.

Also: the interviewer's restatement at [372]/[376] — "прості й чіткі правила меж втручання, **без
складного механізму технічної ізоляції**" — **was never confirmed**. He talked over it and redirected
the whole item to this analysis [378], [381]. `extract/corrections.md:96` flags exactly this: the
analysis "presents 'against heavy isolation' as a settled position rather than an unconfirmed
interviewer formulation."

### Д3 — end of the run [430]

> "якщо, наприклад, він там підняв свої якісь там **оркестратори**, якщо він підняв там якісь докер
> контейнери або якісь сервіси … якщо він це сам підняв, то він це повинен і зупинити"

> "щоби не залишати хвостів, і не засоряти систему, працювати намарно, тому що це вже не потрібно"

His teardown list **starts with nested orchestrators** — the analysis lists only sessions, containers
and services (`extract/by-item.md`, Д3 row 2). Three motives, not one: no tails, no clutter, no wasted
spend.

### I3 — the instruction that produced this document [378]

> "Я хочу, щоб по результатам цього колекціону запустився фейбл агент, який проаналізує це питання …
> отримає контекст, що я говорив на цій сесії. І він відповідно зробить аналіз та порекомендує мені
> якісь варіант для цього."

> [381] "він повинен проаналізувати, повернутися до мене і запропонувати якісь варіанти"

---

## 2. The collision, stated plainly

This is the one item in the interview where the owner's answer contradicts his own evidence, so it has
to be put on the table before the options — not to overturn his decision, but because he asked for
options and an option list that ignores this would be useless to him.

### 2.1 Prose rules were already in force during every incident

VERIFIED, `plugins/harness/docs/FIELD-NOTES.md`:

- **§11.5** — "The owner's default stack was destroyed by a `docker compose down -v` run with no
  `COMPOSE_PROJECT_NAME` exported, which landed it on the default project instead of a lane project.
  … the actor was never identified, and **a session had refused that exact action as owner-only two
  minutes earlier**." (`state/INCIDENT-default-stack.md:9-84`)
- **§11.8** — "`pkill -f 'playwright test'` killed an unrelated lane, because every lane's own prompt
  text contains that literal string, so `pgrep`/`pkill` over-match sessions rather than suites."
  (`state/incident-reading-measure-pkill.md:8-55`)
- **§11.10** — "Two local role passwords printed in clear text into a session transcript by
  Playwright's `--trace on` … **no automated secret scan covers tool output or transcripts.**"
- **§5.1** — the owner's own container `<work-project>-app-1` `OOMKilled` at `2026-09-13T03:29:01Z` by two
  concurrent validator builds. "there was no live alert."

The first one is the decisive one. **Two sessions, same command, two minutes apart: one obeyed the
prose rule, one did not.** A rule that a model obeys 50% of the time over a 34-hour run is not a
boundary; it is a coin flip with a good average.

### 2.2 His own ecosystem already concluded this, in writing

VERIFIED — header comment of `~/.claude/hooks/gsd-worktree-path-guard.js`, a hook **he already runs**:

> "Problem: gsd-executor agents spawned with isolation="worktree" sometimes issue Edit/Write calls
> with absolute paths rooted at the MAIN repository instead of the worktree (issue #260). **The prose
> guard in agents/gsd-executor.md step 0b is never enforced because the model under load skips it.**
> This hook enforces the constraint at the tooling layer, making it HARD-BLOCKING."

GSD hit exactly R1-16's problem, tried exactly R1-15's answer, watched it fail, and moved the
constraint into a hook. He is already running the result: `~/.claude/settings.json` wires
`gsd-worktree-path-guard.js`, `gsd-write-guard.js`, `gsd-read-guard.js`, `gsd-agent-isolation-guard.js`
and `gsd-validate-commit.sh` as `PreToolUse` hooks today (VERIFIED by reading the file).

So "no enforcement procedure in the plugin" is not the status quo he is protecting. The status quo
already has nine enforcement hooks in it. R1-15 would be a step *away* from what he runs.

### 2.3 What the previous generation actually set

VERIFIED, `plugins/harness/bin/harness-spawn.sh:34-38`:

```sh
    bypass) echo "--dangerously-skip-permissions" ;;
    ...
    *) echo "--dangerously-skip-permissions" ;;
```

Every executor session the harness spawned ran with permissions off, by default, with no sandbox. And
`~/.claude/settings.json` sets `"permissions": {"defaultMode": "bypassPermissions"}` globally
(VERIFIED).

This is where "технічні обмеження середовища користувач за потреби налаштовує сам" [357] collides with
itself: **the setting that matters most is not one the user holds — it is one the plugin writes on
his behalf at spawn time.** The plugin is already configuring the safety posture of every session it
starts. It is not abstaining; it is choosing the least safe option and calling that abstention.

That is the honest challenge to R1-15. It does not say his rule is wrong. It says the rule as stated
does not answer who sets the spawn flags — and today the plugin does.

---

## 3. How the world does it — mechanisms ranked by cost to adopt

Ranked cheapest-first. "Cost to the user" means what *he* has to do, not what the plugin has to build.

### 3.1 OS sandbox, Claude Code's built-in Bash sandbox — **cost: one settings key**

VERIFIED from https://code.claude.com/docs/en/sandboxing and executed here.

- macOS: "there is nothing to install: sandboxing uses the built-in Seatbelt framework." Linux/WSL2
  need `bubblewrap` + `socat`.
- Turn on everywhere: `"sandbox": {"enabled": true}` in `~/.claude/settings.json`.
- Default boundary with no path list at all: writes allowed to **the current working directory**, the
  session temp dir, and anything added via `--add-dir` / `permissions.additionalDirectories`.
- Narrow or widen: `sandbox.filesystem.allowWrite`, `denyWrite`, `allowRead`, `denyRead`. Deny wins
  inside a wider allow; the narrower path wins on overlap.
- Network: `sandbox.network.allowedDomains`, `deniedDomains`, `strictAllowlist`.
- Kill the escape hatch: `"allowUnsandboxedCommands": false` ("Strict sandbox mode") — with it off,
  Claude Code ignores the `dangerouslyDisableSandbox` retry parameter entirely.
- Hard-fail instead of silently degrading: `"failIfUnavailable": true`.
- Credentials: `sandbox.credentials.files` / `.envVars` with `mode: "deny"` or `"mask"`. Deny entries
  merge across every settings scope and **no scope can remove one another scope added**.

**Independent of permission mode.** Official wording: "The operating system enforces the sandbox
boundary on the running process, so it holds regardless of what the model chose to run and even if an
allowed command does more than its name suggests." `--dangerously-skip-permissions` decides *whether a
tool call runs*; the sandbox decides *what it can reach once it runs*. They are orthogonal layers.

**Scope**: Bash, PowerShell and Monitor commands **and their child processes**. Subagents "run in the
same process as the parent session and use the same sandbox configuration."

**Verified on this machine, 2026-09-19**, `claude -p … --permission-mode bypassPermissions` with
`sandbox.enabled: true, allowUnsandboxedCommands: false, failIfUnavailable: true`:

- write to a sibling directory → `(eval):1: operation not permitted: …/other-project/NOTES.md`; file
  content unchanged (`owner parallel work`).
- `docker ps` → `dial unix /Users/…/.docker/run/docker.sock: connect: operation not permitted`.
- `kill -TERM <pid>` against a `sleep` started outside the session → `kill … failed: operation not
  permitted`; the process survived.
- `kill -TERM <pid>` against a `sleep` **the same session started in an earlier Bash call** → also
  `operation not permitted`. Each Bash call is its own sandbox instance; signals do not cross between
  them. **This is the one that costs him something** — see §4.3.
- `ls /Users/sasha-marchuk/Work` → **exit 0, listing returned.** Reads outside the cwd are *not*
  blocked by default. `permissions.blockReadsOutsideWorkingDirectories` or `denyRead` is needed for
  that, and it is a separate decision.

### 3.2 Codex's sandbox — **cost: one TOML key, or a command prefix**

VERIFIED (CLI help + executed here). `sandbox_mode` takes `read-only` | `workspace-write` |
`danger-full-access`; `[sandbox_workspace_write]` carries `writable_roots` and `network_access`.
macOS uses Seatbelt; Linux uses bubblewrap/Landlock (CLAIMED, from
https://learn.chatgpt.com/codex/sandboxing).

His current `~/.codex/config.toml` line 7 is **`sandbox_mode = "danger-full-access"`** (VERIFIED).

Executed here:

```
$ cd …/cxtest/mine && codex sandbox -- bash -lc 'echo CLOBBER > ../other/N.md'
bash: ../other/N.md: Operation not permitted
$ codex sandbox -- bash -lc "kill -TERM <outside pid>; docker ps"
kill: (78499) - Operation not permitted
… docker.sock: connect: operation not permitted
```

**`codex sandbox -- <any command>` is a standalone wrapper.** It is a Seatbelt front-end that is
already installed and can wrap *anything*, including a `claude`, `gemini` or `opencode` launch. That
makes it a cross-engine enforcement primitive available today with zero new dependencies. (INFERRED
that wrapping another agent CLI works — the mechanism is generic `exec` under a profile, but I did not
run a full agent under it.) It also takes `-P/--permission-profile`, `--allow-unix-socket <path>` and
`--log-denials`, the last of which prints macOS sandbox denials after exit — useful for tuning a
profile without guesswork.

### 3.3 Permission deny rules — **cost: a few lines; and they are not a boundary**

VERIFIED from https://code.claude.com/docs/en/permission-modes:

> "Deny rules block in every mode, including `bypassPermissions`. … **Allow rules have no effect in
> `bypassPermissions`.**"

Confirmed here: with `"deny": ["Bash(docker compose down:*)"]` under
`--permission-mode bypassPermissions`, the model's call came back
`Permission to use Bash with command docker compose down -v --remove-orphans has been denied.`

**But the same test defeated it in one step.** With `"deny": ["Bash(rm:*)"]` and the same bypass mode,
I asked for `sh -c 'rm -f …/target.txt'`. Result: `EXIT=0`, and the file was gone. VERIFIED, today.

The docs say so themselves: "Bash permission patterns that try to constrain command arguments are
fragile", listing options-before-URL, protocol changes, redirects and variable indirection. Path rules
(`Read`/`Edit` with `//absolute`, `~/home`, gitignore-style globs) are much sounder than command-string
rules, because they match the resolved path rather than the spelling of a command.

Precedence, VERIFIED: managed → `--settings` → `.claude/settings.local.json` → `.claude/settings.json`
→ `~/.claude/settings.json`. Two details that matter here:

- `deny` and `ask` rules apply immediately; `allow` rules and `additionalDirectories` wait for folder
  trust.
- Since v2.1.257, `bypassPermissions` **cannot** be set from project or local settings — only user,
  `--settings`, or managed. `permissions.disableBypassPermissionsMode: "disable"` in managed settings
  removes the mode entirely.

### 3.4 `PreToolUse` deny hooks — **cost: one script; survives bypassPermissions**

VERIFIED by execution here. A hook returning

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",
 "permissionDecisionReason":"…"}}
```

on exit 0 (or simply exiting 2) blocked a Bash call in a session launched with
`--permission-mode bypassPermissions`. The target file was never created. Hooks fire for MCP tools
(`mcp__<server>__<tool>`) and inside subagents (the payload carries `agent_id` / `agent_type`), and
`~` and relative paths are expanded **before** hooks run, so a path matcher cannot be dodged by
respelling.

Caveat, VERIFIED from the sandbox-environments doc: **hooks themselves run unconstrained on the host**
and outside the Bash sandbox. A hook is a policy check, not a containment wall — and a session that can
write `.claude/hooks/` can disarm it. (The Bash sandbox blocks writes to `.claude` config paths from
inside the sandbox, which closes that specific loop; see §3.1's protected-paths list.)

This is the mechanism that makes the red-line file *real* without giving him a second file or a second
procedure: one hook, shipped by the plugin, reads his one file.

### 3.5 Git worktree confinement — **cost: already his default**

Д4 [433]: "Дефолтна пропозиція, щоби абсолютно все виконувати в різних ворк трі". VERIFIED from
`FIELD-NOTES.md §7` that the previous run did this for parallel lanes (`<work-project>-phase-13`, `-22`,
`-23`), each with its own compose project and a port block 100 apart.

A worktree is **not** an enforcement mechanism on its own — nothing stops a session `cd`-ing out of it;
`FIELD-NOTES.md §11.8` records GSD computing a branch name one word off and a lane spawning into a
stale worktree. What a worktree *does* is make a cheap boundary **sufficient**: if each task's session
has `cwd` = its own worktree, then the sandbox's zero-configuration default (writes confined to cwd)
is already the right rule, with no path list to maintain and nothing to keep in sync. That is the
combination that turns his case 2 into case 1.

Caveat: worktrees live *outside* the repo directory, so an orchestrator whose cwd is the main checkout
needs each worktree in `additionalDirectories` — or, better, never needs them, because each worker
session is launched with cwd already set to its own worktree.

### 3.6 Docker compose project scoping — **cost: one env var per lane**

VERIFIED on this machine right now:

```
$ docker ps -a --format '{{.Names}}\t{{.Label "com.docker.compose.project"}}'
<work-project>-app-1        <work-project>
<work-project>-postgres-1   <work-project>
```

His stack is running, labelled `com.docker.compose.project=<work-project>`. `docker ps --filter
label=com.docker.compose.project=<name>` works (VERIFIED). `docker compose -p <name> down` scopes a
teardown to one project.

The incident was precisely the absence of this: `docker compose down -v` with no
`COMPOSE_PROJECT_NAME` exported "landed it on the default project instead of a lane project". The fix
is mechanical and free: every container the run creates is created under a run-scoped project name, and
teardown never names a project the run did not create.

What labels cannot do: they do not stop a bare `docker compose down` typed without `-p`, and they do
not stop resource contention — the owner's app was **OOM-killed** by two concurrent builds (§5.1), not
torn down. Labels are for teardown scoping, not for protection.

### 3.7 Process-group ownership — **cost: a few lines in the spawn helper**

VERIFIED here (bash, macOS 26.5.2): `setsid` **does not exist** on macOS, but `set -m` in bash puts
each background job in its own process group, and `kill -TERM -- -<PGID>` terminates that group and
nothing else:

```
spawned pid=80476 pgid=80476 (own pgid=80466)
GROUP KILL SENT
DEAD (group kill worked)
```

This is the direct, exact replacement for `pkill -f '<pattern>'`. The rule it enforces — *stop only
identifiers you recorded at spawn time* — is both the answer to R1-16 case 2 and the answer to Д3, and
it is the cheapest item in this whole document.

**Its structural limit**, and this is important: `plugins/harness/bin/harness-term.sh` spawns sessions
through **`osascript` into iTerm2** (VERIFIED, lines 59-110). A session started that way is a child of
iTerm2, not of the orchestrator's shell. It has no process-group relationship to the orchestrator at
all. That is *why* the previous generation reached for `pkill -f` and *why* it over-matched. Any
option built on process lineage has to carry a separate identity for terminal-spawned sessions — an
iTerm session id, a tmux pane id, or a pidfile the spawned session writes itself.

### 3.8 A wrapper PATH shim for dangerous binaries — **cost: low to write, weak to rely on**

Put a directory first on `PATH` containing a `docker` (or `pkill`) wrapper that refuses the dangerous
forms and `exec`s the real binary otherwise.

- Prevents: the *accidental* spelling — a bare `docker compose down` with no project.
- Does not prevent: `/usr/local/bin/docker …`, `env -i`, a script that resets `PATH`, or anything
  reached over the Docker socket directly. INFERRED, but not seriously contestable.
- Cross-platform: works identically for every engine, because it is a property of the shell, not the
  agent. That is its one real advantage.

Honest placement: a good *ergonomic* guard-rail and a terrible *security* boundary. Worth it only as
an inner layer inside something that actually holds.

### 3.9 `sandbox-exec` directly — **cost: medium, and it is deprecated**

VERIFIED from `man sandbox-exec` on this machine:

> "The sandbox-exec command is **DEPRECATED**. Developers who wish to sandbox an app should instead
> adopt the App Sandbox feature…"

It still works and is what Claude Code and Codex use underneath. Writing raw `.sb` profiles by hand is
strictly worse than letting either CLI generate one: same enforcement, much more to maintain, and an
Apple deprecation notice on top. **Do not build on this directly.** Use §3.1 or §3.2, which are the
supported front-ends to the same kernel facility.

### 3.10 Whole-process isolation — **cost: low to high, and it is the shape he ruled out**

Three rungs, VERIFIED from https://code.claude.com/docs/en/sandbox-environments:

| approach | isolates | needs Docker | setup |
|---|---|---|---|
| Sandboxed Bash tool (§3.1) | Bash/PowerShell/Monitor + children | no | minimal on macOS |
| **Sandbox runtime** (`@anthropic-ai/sandbox-runtime`) | the whole process: file tools, hooks, MCP servers | **no** | low |
| Dev container / custom container | full dev environment | yes | medium–high |
| Virtual machine | full OS | no | high |

The **sandbox runtime** is the interesting middle rung and the one nobody described to him. `npx
@anthropic-ai/sandbox-runtime claude` wraps the entire Claude Code process in the same Seatbelt
isolation, so hooks and MCP servers are inside the boundary too — and it is a *command prefix*, not an
environment to build. Its defaults are aggressive (network denied, writes confined to built-in runtime
paths) and it needs `~/.srt-settings.json` granting the project dir, `~/.claude`, `~/.claude.json` and
`/tmp`. It is a **beta research preview** and its config format may change (CLAIMED, from the doc).

Its own free wins, CLAIMED from the doc: `denyWrite` beats `allowWrite`; it denies `.git/hooks`,
`.git/config`, `.mcp.json`, `.claude/commands`, `.claude/agents` and shell startup files at the project
root with no configuration. On macOS those denies are checked *at write time*, so they cover
repositories created mid-session.

The trap, quoted: "Without a valid `~/.srt-settings.json`, the runtime starts anyway, blocks network
access, and confines writes to built-in runtime paths… **Don't take a clean start as proof your
settings loaded.**" Exactly the "nothing fails with success" failure mode `FIELD-NOTES.md §11.4` is
full of.

---

## 4. What is feasible per platform

### 4.1 Per-engine capability table

| | Claude Code 2.1.278 | Codex 0.152.0 | Gemini CLI | opencode |
|---|---|---|---|---|
| OS-enforced filesystem boundary | **yes**, `sandbox.enabled` (Seatbelt) — VERIFIED | **yes**, `sandbox_mode="workspace-write"` + `codex sandbox` — VERIFIED | **yes**, `SEATBELT_PROFILE` (`permissive-open` default / `strict`), or `sandbox: docker\|podman` — CLAIMED | **no OS sandbox found** — CLAIMED |
| Deny rules that survive auto-approve | **yes** — VERIFIED | permission profiles (`-P`) + `execpolicy` — CLAIMED | `tools.exclude`, e.g. `ShellTool(rm -rf)` — CLAIMED | **yes**: "deny verdicts are never overridden by auto-approval modes" — CLAIMED |
| Programmatic pre-tool deny hook | **yes**, `PreToolUse` — VERIFIED | hooks exist (`--dangerously-bypass-hook-trust`, `allow_managed_hooks_only`) — CLAIMED | not found | not found |
| Standalone sandbox wrapper for any command | via `@anthropic-ai/sandbox-runtime` (beta) | **`codex sandbox -- <cmd>`** — VERIFIED | `sandbox-exec`-based, engine-internal — CLAIMED | n/a |
| Network egress allowlist | `sandbox.network.allowedDomains` + `strictAllowlist` — VERIFIED (config) | `[sandbox_workspace_write] network_access` — CLAIMED | container-level — CLAIMED | not found |
| Credential file/env protection | `sandbox.credentials` — VERIFIED (config) | not found | not found | not found |

Sources for the CLAIMED cells: Gemini CLI configuration docs
(google-gemini.github.io/gemini-cli/docs/get-started/configuration.html) —
`tools.core` allowlist with `ShellTool(ls -l)` syntax, `tools.exclude` denylist, `tools.allowed`
(`run_shell_command(git)`), `--approval-mode default|auto_edit|yolo`, `GEMINI_SANDBOX=true|false|docker|podman|<command>`,
`SEATBELT_PROFILE=permissive-open|strict` plus custom `.gemini/sandbox-macos-*.sb` profiles. opencode
permissions doc (opencode.ai/docs/permissions) — `permission` block in `opencode.json`, verdicts
`allow`/`ask`/`deny`, pattern maps on `bash`/`edit`/`read`/`webfetch`, **last-match-wins**, and deny
holding under `--auto`. Codex `execpolicy` and security pages resolve to
learn.chatgpt.com and I could not retrieve their full text today — treat Codex's hook and execpolicy
details as the least-verified cells in the table.

**Portability conclusion.** The mechanisms that exist on *every* engine are:

1. a **deny/exclude list** (every engine has one, every one of them matches command strings, and
   §3.3's `sh -c` test shows what that is worth);
2. an **OS sandbox** — on three of four engines, all three on macOS via the same Seatbelt kernel
   facility, reachable from outside the engine with `codex sandbox --` for the fourth;
3. **process and container ownership discipline** — which lives entirely in the plugin's own spawn and
   teardown code and is therefore engine-independent by construction.

Only #2 and #3 are boundaries. #3 is the only one that is *fully* under the plugin's control, needs
nothing from the user, and works identically everywhere. That ranking should drive the choice.

### 4.2 The Docker collision — the one real cost of the sandbox

VERIFIED: inside the sandbox, the Docker daemon socket is unreachable. `docker ps` fails. Therefore
`docker compose down -v` — the command that destroyed his stack — is **structurally impossible** in a
sandboxed session.

It is also impossible for the orchestrator to do its legitimate work: Д4 requires "якийсь запущений
стек" [433], and the previous run's lanes each brought up their own compose project.

The ways out, with their honest prices:

- **`sandbox.network.allowUnixSockets` for the docker socket.** Restores Docker fully — and the docs
  are blunt: "allowing access to `/var/run/docker.sock` effectively grants access to the host system
  through the Docker socket." That is not a partial re-opening; it is a complete one.
- **`sandbox.excludedCommands` for `docker`.** Narrower than opening the socket, but the `docker`
  binary then runs entirely outside the boundary, so a bare `docker compose down` is back on the table
  and needs §3.6 and/or a deny rule to catch it.
- **Split the roles.** Sandbox the *worker* sessions (which edit code and run tests); leave the
  *orchestrator* unsandboxed as the only role permitted to touch Docker, with its teardown scoped by
  §3.6. Smallest blast radius per role, and it matches R1-07's existing role model — but it needs the
  plugin to set different flags per role, which it already does for accounts.

There is no configuration that gives him sandboxed Docker. This is a genuine fork in the road and it
belongs in his hands, not mine.

### 4.3 The teardown collision

VERIFIED: a sandboxed session could not signal a process **it had itself started** in an earlier Bash
call. Each Bash call gets its own sandbox instance and signals do not cross.

So the sandbox, taken alone, satisfies "do not stop what you did not start" (R1-16) by also breaking
"stop what you did start" (Д3). Ways out:

- run teardown through the engine's own background-task machinery rather than bare `kill`;
- list the teardown script in `sandbox.excludedCommands`;
- give the orchestrator role no sandbox and make it the only role that tears anything down (§4.2's
  third option again).

INFERRED, not tested: whether Claude Code's own `run_in_background` / `TaskStop` path is exempt. Worth
five minutes before any option that leans on it.

---

## 5. What is NOT feasible, and why

1. **A prose rule that reliably stops a destructive command.** Refuted by his own run: the same command
   refused by one session and executed by another two minutes later, with the rule in force
   (`FIELD-NOTES.md §11.5`). Refuted a second time, independently, inside GSD:
   `gsd-worktree-path-guard.js` exists because "the prose guard … is never enforced because the model
   under load skips it." VERIFIED both.
2. **A command-string deny list as a boundary.** Demonstrated bypass here today: `Bash(rm:*)` denied,
   `sh -c 'rm -f …'` deleted the file, exit 0, under his own default permission mode. The official
   docs call these patterns "fragile" and list four evasion classes. VERIFIED.
3. **`pgrep`/`pkill` pattern matching to identify a run's own processes.** Structurally broken, not
   merely risky: every lane's prompt text contains the strings the patterns match, so the pattern
   matches sessions rather than the suites it means to kill (`FIELD-NOTES.md §11.8`). VERIFIED.
4. **Protecting against resource contention with any access-control mechanism.** The owner's container
   was `OOMKilled` by two concurrent builds on an 8 GB Docker VM — nothing about permissions, paths or
   labels addresses it. The controls are scheduling controls: serialise image builds, cap lane count,
   watch `memory_pressure -Q` (`FIELD-NOTES.md §5.1`, §5.2). VERIFIED. **This is out of C8's scope and
   should not be sold as covered by any option below.**
5. **Secret-leak prevention by sandboxing.** The passwords reached a transcript through Playwright's
   own `--trace on` output, inside the workspace, written by an allowed tool. Every boundary in this
   document permits that write. `sandbox.credentials` protects credential *files and env vars from
   being read*; it does nothing about a tool that prints a secret it legitimately holds. The gap
   `FIELD-NOTES.md §11.10` names — "no automated secret scan covers tool output or transcripts" — is a
   scanning problem, not a boundary problem. VERIFIED.
6. **Blocking reads outside the working directory by default.** `ls /Users/sasha-marchuk/Work` returned
   a listing inside the sandbox. Read confinement is a separate, deliberate switch
   (`permissions.blockReadsOutsideWorkingDirectories` or `denyRead`), and it will be noisy — most
   sessions legitimately read `~/.claude`, `~/.gitconfig`, toolchain caches. VERIFIED.
7. **`sandbox-exec` as a thing to build on.** Deprecated by Apple (VERIFIED in the man page on this
   machine). Use the engines' front-ends.
8. **Any process-lineage mechanism applied to terminal-spawned sessions.** `harness-term.sh` launches
   through `osascript` into iTerm2; the session is iTerm2's child, not the orchestrator's. VERIFIED.
   Group-kill and sandbox inheritance both stop at that boundary, and any option that needs them has to
   carry an explicit session identity instead.

---

## 6. Six options

Each stated as the owner asked: **rule · enforcement medium · what it still cannot stop · setup cost ·
which of his two cases it covers.**

Case 1 = his other projects / other folders. Case 2 = his own parallel work in the same folder.

---

### Option A — The stated maximum: one file, read by all, nothing enforced

*This is R1-15 exactly as he gave it, written out so the others can be compared against it.*

- **Rule.** One appendable text file in a defined place. Every agent reads it before acting, and the
  run refuses to start if it cannot be read. Restrictions carry a **type** (his own "різного типу
  обмеження" [357]) — e.g. `never-touch`, `ask-first`, `owner-only` — so a rule's severity is
  machine-readable even when its enforcement is not.
- **Medium.** Prose, injected into every session's system prompt at spawn; the type field is the only
  structure.
- **Cannot stop.** Anything. Demonstrated twice in his own evidence (§5.1, §5.2). A model under load at
  hour 20 of a 34-hour run skips it, and there is no signal when it does.
- **Setup cost.** Zero for him. Smallest possible plugin change.
- **Covers.** Case 1: no. Case 2: no. Both by good behaviour only.
- **Honest note.** This is the only option that changes nothing about how the last run failed. Its real
  value is as the **policy layer** every other option reads from — not as a boundary.

---

### Option B — Ownership ledger: stop only what you recorded starting

- **Rule, stated abstractly as he asked [373]:** *the orchestrator may stop only a thing whose
  identifier it wrote into the run ledger at the moment it created it.* No pattern matching, ever — no
  `pkill -f`, no `killall`, no `docker compose down` without an explicit project name the run created.
  Nothing else is stoppable, so nothing else can be stopped by accident.
- **Medium.** The plugin's own spawn and teardown code. At spawn: `set -m` + record the PGID
  (§3.7); for terminal sessions, record the iTerm session id / tmux pane id that `harness-term.sh`
  already receives; for containers, record the compose project name and a `label=orchestrator.run=<id>`
  (§3.6). Teardown iterates the ledger and nothing else. One lint rule in the test harness fails the
  build if `pkill`, `killall`, or an unscoped `docker compose down` appears anywhere in plugin source.
- **Cannot stop.** File writes and deletions — this option is entirely about processes, containers and
  services. It also cannot stop a *session* from running `pkill` itself; it constrains the
  orchestrator, not its children. And it cannot recover a run whose ledger was lost, so the ledger must
  be append-only on disk and survive an orchestrator restart (which R1-10's launch journal already
  requires).
- **Setup cost.** **Zero for him.** Entirely inside the plugin. No settings, no per-platform config,
  identical on every engine.
- **Covers.** Case 1: partially — it will not stop another project's containers, but it says nothing
  about files. Case 2: **yes, precisely** — this is the exact fix for the `pkill` incident and for the
  unscoped `docker compose down`, the two incidents where his parallel work was hit.
- **Honest note.** This is the cheapest real improvement in the document and the closest thing to
  "дуже якісь простий та надійний варіант … прописаний в плагіні" [370]. It should be in every option
  below; it is listed separately only so its cost is visible as zero.

---

### Option C — Make the red-line file executable: one hook reads his one file

- **Rule.** The file from Option A stays exactly as he specified — one place, user-maintained,
  appendable, the only thing he ever edits. The plugin adds **one** `PreToolUse` guard that reads that
  same file and hard-denies what the file's `never-touch` entries name.
- **Medium.** A single hook, shipped by the plugin, registered at spawn — the same shape as the nine
  GSD guards already in `~/.claude/settings.json`. Match on resolved **paths**, not command strings
  (§3.3: paths are sound, command strings are not). Fail **closed** — GSD's own `hook-exit.js` makes
  this an explicit, required declaration per hook, and the reasoning in its header is worth reusing
  verbatim.
- **Cannot stop.** Anything outside the tool-call surface: a script the agent writes and then runs does
  one tool call, and the hook sees the script's path, not what is inside it. Command-string rules stay
  bypassable via `sh -c` (VERIFIED). Hooks run unsandboxed on the host, so a session that can write
  `.claude/hooks/` can disarm them — closed only if Option E's sandbox is also on. And it is
  **Claude-Code-only**: Codex hooks are plausible but unverified, Gemini and opencode have no equivalent
  (§4.1).
- **Setup cost.** Zero for him — he already writes the file; the plugin ships the hook. **But it is
  exactly the "окрема обов'язкова процедура" he said was unnecessary** [357], which is why it is a
  choice for him and not a recommendation.
- **Covers.** Case 1: yes, for file paths, if he names those paths. Case 2: partially — it can protect
  named paths, and nothing about processes.
- **Honest note.** This is the smallest change that makes his own decision load-bearing instead of
  advisory. It adds no file, no format and no habit; it only makes the file he already wants have
  teeth. It also has a property none of the others do: **it fails loudly and names the rule that
  fired**, so he learns which prohibitions actually get tested.

---

### Option D — Worktree anchoring: make "the same folder" stop being the same folder

- **Rule.** Every task runs in its own git worktree, off the main branch, with cwd set to that worktree
  at spawn — his own Д4 default [433], promoted from a recommendation to the boundary mechanism. His
  parallel work stays in the main checkout. The orchestrator writes only inside worktrees it created,
  plus the run's own state directory.
- **Medium.** The spawn path sets cwd; the worktree registry is part of the run ledger from Option B,
  so worktree removal at Д3 teardown is scoped the same way as everything else. Optionally paired with
  Option E, where the sandbox's zero-configuration default (writes confined to cwd) then needs no path
  list at all.
- **Cannot stop.** A session that `cd`s out of its worktree — unless Option E is on. The shared Docker
  daemon, shared host ports, shared package caches. And the known failure mode from his own run: a
  branch name computed one word off, or a lane slug reused from an earlier wave spawning into a stale
  worktree (`FIELD-NOTES.md §11.8`) — so worktree identity has to be verified at spawn, not assumed.
  It also forks files: `QUESTIONS.md` and `JOURNAL.md` "forked into a worktree's own copy" last run
  (§12), and owner-facing files must live outside the worktree or be explicitly synced.
- **Setup cost.** Zero for him — it is already his stated default. Real work in the plugin to make
  worktree creation, environment readiness ("постійно переконуватись" [433]) and removal reliable.
- **Covers.** Case 1: no, on its own. Case 2: **yes, structurally** — it converts his hardest case into
  his easiest one, because after this the run and his parallel work are no longer in the same
  directory at all.
- **Honest note.** This is the only option that makes case 2 tractable *without* an enforcement
  mechanism. It is also the one that most needs the others: a worktree is a convention until something
  enforces cwd.

---

### Option E — Turn on the OS sandbox the engines already ship

- **Rule.** *Every session the orchestrator starts runs inside the operating system's own boundary,
  anchored to the directory that session was given.* No path list he maintains, no new file, no new
  concept — the default boundary is "the folder you are working in".
- **Medium.** Per engine, set by the plugin at spawn, not by him:
  - Claude Code: `sandbox.enabled: true`, `allowUnsandboxedCommands: false`, `failIfUnavailable: true`,
    passed via `--settings` on the spawn line so it never depends on the state of his global file.
  - Codex: `-c sandbox_mode="workspace-write"` with `writable_roots` set to the task's worktree — his
    config is `danger-full-access` today (VERIFIED), so this is a real change.
  - Gemini: `SEATBELT_PROFILE=permissive-open` (CLAIMED to confine writes to the project folder).
  - opencode: no OS sandbox found — either wrap it with `codex sandbox --` or accept that this engine
    is outside the boundary and say so out loud.
- **Cannot stop.** Reads outside the working directory (VERIFIED: `ls ~/Work` succeeded) unless he
  also accepts `blockReadsOutsideWorkingDirectories` and its noise. Anything the boundary must be
  opened for — and **Docker is exactly that** (§4.2): sandboxed Docker does not exist, so he must pick
  socket-open, `excludedCommands`, or orchestrator-only-Docker. It also breaks the orchestrator's own
  teardown of its background children (§4.3, VERIFIED). Hooks and MCP servers run outside it. And on
  Linux it needs `bubblewrap` + `socat` installed, so a Linux user's first run differs from his.
- **Setup cost.** **One line, if the plugin sets it.** Nothing to install on macOS. The expensive part
  is not setup — it is the Docker decision, which is a design decision he has to make once.
- **Covers.** Case 1: **yes, completely and demonstrably** — verified here today, under his own
  permission mode, with no prompt and no model cooperation. Case 2: **yes for processes and for file
  writes** — a sandboxed session cannot signal his processes (VERIFIED) and cannot write outside its
  own directory (VERIFIED). Not for Docker, if Docker is opened.
- **Honest note, and it is the crux of this document.** What he rejected at [370] was described to him
  at [364]/[365] as "окреме середовище, з якого він узагалі не має доступу" — a separate environment.
  This is not that. It is the path list he himself asked for at [366] — "в оркестратори прописаний
  шлях, до чого він має доступ" — with the OS doing the checking instead of the model. Whether that
  still counts as the "детерміністський варіант" he refused is **his call, not mine**, and it is the
  first question in §7.

---

### Option F — Whole-process isolation (the shape he ruled out, priced honestly)

- **Rule.** The entire agent process — tools, hooks, MCP servers, everything — runs inside one
  boundary: `npx @anthropic-ai/sandbox-runtime claude`, a dev container, or a VM.
- **Medium.** A command prefix (sandbox runtime) or a container image.
- **Cannot stop.** Very little inside its scope. But: the sandbox runtime is a **beta research
  preview** whose config format may change; it "starts anyway" with a broken settings file and confines
  writes to built-in paths, so a clean start proves nothing (CLAIMED, quoted §3.10); a container needs
  Docker, which is the resource that is already contended on this machine; and none of it addresses the
  OOM contention that killed his app.
- **Setup cost.** Sandbox runtime: low but real — an `~/.srt-settings.json` granting the project dir,
  `~/.claude`, `~/.claude.json`, `/tmp`, plus `api.anthropic.com`, `claude.ai`, `platform.claude.com`.
  Container/VM: medium to high, and per engine.
- **Covers.** Case 1 and case 2: both, completely.
- **Honest note.** Recorded for completeness because it is the only rung that also contains hooks and
  MCP servers, and because "оверінжиринг" [370] was said about a *sandbox* description, not about
  this — he has never actually been shown this rung. I am not recommending it. Option E gets most of
  its protection at a fraction of its cost, and Option F's beta status is a poor fit for something that
  must run unattended for 34 hours.

---

### How they combine

They are layers, not alternatives. The cheapest coherent stack, in the order the cost rises:

**B** (zero cost, pure plugin, fixes both recorded incidents)
→ **D** (already his default; turns case 2 into case 1)
→ **A** (his file, as the policy source)
→ **E** (one line; the only thing that holds when the model does not)
→ **C** (makes A enforceable, Claude-Code-only)
→ **F** (only if he ever wants hooks and MCP servers inside the boundary too).

**B and D cost him nothing and contradict nothing he said.** If he adopts only those two, the `pkill`
incident and the `docker compose down -v` incident both become impossible, and R1-15 stands exactly as
he gave it. That is the recommendation if he wants to change as little as possible. E is where the real
protection is, and it is also where the real decision is.

---

## 7. Open questions this raises for the owner

Ordered by how much downstream design they unblock. Ukrainian, as he prefers for questions.

1. **Межа, яку встановлює операційна система — це той самий "детерміністський варіант", який ти
   відкинув?**
   На [364]/[365] тобі описали *окреме середовище* (контейнер/VM). Але на [366] ти сам запропонував
   механізм: "в оркестратори прописаний шлях, до чого він має доступ". Вбудований пісочний режим — це
   рівно твій список шляхів, який перевіряє ядро ОС, а не модель. Один рядок конфігу, нічого
   встановлювати на macOS, сесія так і залишається звичайною сесією у твоєму терміналі. **Це все ще
   оверінжиринг, чи це і є той простий надійний варіант?** Усе інше в цьому документі залежить від
   цієї відповіді.

2. **Docker: три варіанти, треба обрати один.** Всередині пісочниці docker.sock недоступний — та сама
   команда, що знищила твій стек, просто не виконається. Але й лейни не піднімуть свої стеки.
   (а) відкрити сокет — це повертає повний доступ до хоста; (б) вивести `docker` з пісочниці —
   вужче, але `docker compose down` знову можливий; (в) пісочниця лише для виконавців, Docker — тільки
   для оркестратора, зі скоупленим teardown. Варіанта "Docker у пісочниці" не існує.

3. **"Але, так, це максимум" [357] — це стеля для тебе, чи стеля для того, що *ти* налаштовуєш?**
   Це різні речі. Плагін уже сьогодні ставить `--dangerously-skip-permissions` кожній сесії
   (`harness-spawn.sh:38`) — тобто він уже вирішує за тебе, тільки в найнебезпечніший бік. Якщо стеля
   стосується твоєї роботи, а не роботи плагіна, то варіанти B/D/E нічого не порушують.

4. **R1-15 лишилось непідтвердженим.** Ти закінчив питанням "Чи це є відповідно до твоєго питання"
   [357], і інтерв'юер відповів сам собі [358]. Формально це не зафіксована відповідь. **Підтверджуєш
   її як є — чи переглядаєш у світлі §2?**

5. **"різного типу обмеження" [357] — які саме типи?** Ти сказав, що обмеження бувають різних типів, і
   аналіз це загубив. Мінімум, який видно з інцидентів: *ніколи* (докерівський стек), *тільки з
   дозволом* (пуш у trunk), *попередити* (зупинка чужого процесу). Твій власний `never` з
   `<baseline-marketplace>/docs/config-levels.md` §5 уже має потрібну семантику: накопичується
   об'єднанням, ніколи не зникає тихо, і попереджає, якщо нічого не зачепив. **Брати цю семантику?**

6. **Читання за межами робочої теки — блокувати?** Зараз ні: `ls ~/Work` із пісочниці працює.
   Заблокувати можна, але сесії легально читають `~/.claude`, `~/.gitconfig`, кеші тулчейну — буде шум.
   **Це важливо для тебе, чи запис — достатня межа?**

7. **Сесії стартують через `osascript` в iTerm2** (`harness-term.sh`), тобто вони — діти iTerm2, а не
   оркестратора. Саме тому минулого разу дійшло до `pkill -f`. **Чи можна перейти на tmux (або на
   pidfile, який пише сама сесія) для тих сесій, які оркестратор має вміти зупиняти?** Без цього
   "зупиняти тільки своє" (Д3) тримається на записаному ідентифікаторі, а не на спорідненості
   процесів.

8. **Д3 [430] починається з "свої якісь там оркестратори".** Вкладені оркестратори в списку teardown —
   але R1-10 [300] каже, що двох одночасних оркестраторів бути не може. **Що саме тут малося на увазі:
   вкладені оркестратори як окрема роль, чи це той самий журнал запусків з R1-10?**

9. **"Якщо є окремо нетворк 3, то він відповідно до них теж не має доступу" [366]** — розшифровка
   зіпсована. Найімовірніше "networks" (докерівські мережі) або "worktrees". У попередньому рані
   валідатор фази 21 не зміг отримати підмережу зі спільного пулу, тож "мережі" виглядають
   правдоподібно — але я не вгадую. **Що ти мав на увазі?**

10. **Секрети — це не питання меж, і жоден варіант вище їх не закриває.** Паролі потрапили в транскрипт
    через власний `--trace on` Playwright, всередині робочої теки, дозволеним інструментом. Потрібен
    сканер виводу/транскриптів, а не межа. **Це окремий пункт для раунду 2?**

---

## 8. Source index

**Read on this machine (VERIFIED):**
`plugins/harness/docs/FIELD-NOTES.md` §5.1, §5.2, §7, §11.4, §11.5, §11.8, §11.9, §11.10, §12 ·
`plugins/harness/bin/harness-spawn.sh:34-38` · `plugins/harness/bin/harness-term.sh:16-110` ·
`plugins/harness/bin/harness-run.sh:41-46` · `~/.claude/settings.json` (permissions.defaultMode =
`bypassPermissions`; nine PreToolUse/PostToolUse guard hooks) · `~/.claude/hooks/gsd-worktree-path-guard.js`
(header) · `~/.claude/hooks/lib/hook-exit.js` (fail-open vs fail-closed policy) · `~/.codex/config.toml:7`
(`sandbox_mode = "danger-full-access"`) · `man sandbox-exec` (DEPRECATED) ·
`<baseline-marketplace>/docs/config-levels.md` §4–§6 (the `never` veto) ·
`round-1/TRANSCRIPT-01.md` rows [355]–[383], [430], [433] · `round-1/ANALYSIS-01.md` ·
`research/extract/{by-item,corrections,outside-list,meta}.md`.

**Executed on this machine, 2026-09-19 (VERIFIED):** `claude -p` with a `PreToolUse` deny hook under
`--permission-mode bypassPermissions` (blocked) · the same with `permissions.deny` (blocked) · the same
with `Bash(rm:*)` denied and `sh -c 'rm -f …'` requested (**not** blocked, file deleted) ·
`sandbox.enabled` write/kill/docker/read tests · `codex sandbox --` write/kill/docker tests ·
`docker ps -a --format '{{.Label "com.docker.compose.project"}}'` · bash `set -m` + `kill -- -PGID` ·
`setsid` absent.

**Official documentation (VERIFIED as published text):**
code.claude.com/docs/en/{hooks,permissions,permission-modes,sandboxing,sandbox-environments} ·
`claude --help` (2.1.278) · `codex --help`, `codex sandbox --help`, `codex exec --help` (0.152.0).

**Third-party documentation (CLAIMED, not executed here):**
google-gemini.github.io/gemini-cli/docs/get-started/configuration.html ·
opencode.ai/docs/permissions · learn.chatgpt.com/codex/sandboxing ·
github.com/anthropic-experimental/sandbox-runtime (via the Claude Code sandbox-environments page).

**Not retrievable today:** Codex's `execpolicy` and security pages redirect to learn.chatgpt.com and
did not return their configuration detail. Codex hook and execpolicy behaviour is the least-verified
material in this document and should be checked directly against `codex` on the machine before any
option depends on it.
