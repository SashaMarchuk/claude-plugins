# BOUNDARIES-OPTIONS — should the orchestrator protect what it did not start, and how

**Item R1-16.** Written by a Fable agent on the owner's own standing instruction [378]/[381]:
«запустився фейбл агент, який проаналізує це питання … отримає контекст, що я говорив на цій сесії …
зробить аналіз та порекомендує мені якісь варіант». This is that analysis and recommendation. The
owner's decisions are the source of truth; where a decision has a consequence he may not have seen, I
name the consequence — I do not overrule it.

**Date:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0). claude 2.1.278, codex 0.152.0,
docker 28.5.1, git 2.33.0.

**Evidence tags.**
- **VERIFIED** — I read it in source/docs on this machine today, or I executed it here today.
- **VERIFIED-C8** — executed in `C8-boundaries-safety-research.md` today; I read the transcript, did
  not re-run it.
- **CLAIMED** — a vendor doc or profile asserts it; nothing was executed.
- **INFERRED** — my reasoning from the above.

Everything tagged VERIFIED in §2–§6 without a source is something I ran myself today; the transcripts
are summarised in §7.

---

## 1. What he actually asked for — and the tension inside it, unresolved

### His words, which bind this answer

- **The self-aware boundary, not isolation** [366]: «оркестратор має бути якось селфевернес, що він,
  до чого він може змінювати, а що не може … він би не мав зупиняти якісь там тести, які не він
  запускав».
- **He named a mechanism himself** [366]: «в оркестратори **прописаний шлях, до чого він має
  доступ**» — a written list of what it may reach.
- **Two cases** [370]: (1) he is in Claude Code in a **different folder / project** — the orchestrator
  must not touch it; (2) in the **same folder** he works in parallel himself — the orchestrator must
  not stop his work.
- **The refusal** [370]: «я не хочу якихось детерміністського варіанту для цього, тому що він буде
  дуже складний оверінжиринг, але дуже якісь **простий та надійний варіант** … має бути прописаний в
  плагіні».
- **Abstract, not a config knob** [373]: «Я би не сказав, я би це робив якось абстрактно».
- **R1-15, the red line** [357]: one appendable text file of prohibitions, read by every agent, «на
  окремо якогось обов'язкової процедури … не треба … Достатньо лише одного файлу … Але, так, це
  максимум». Extra technical restrictions the user sets up himself.
- **Д3, end of run** [430]: stop what it started — sessions, containers, services it raised itself —
  «щоби не залишати хвостів», and nothing else.

### The tension, stated plainly and not resolved for him

He wants **prompt-level rules** — a written scope, a written prohibitions file, read by every agent,
no enforcement machinery. Prompt-level rules are **precisely what failed in his own logs**:

- **VERIFIED, FIELD-NOTES §11.5.** His default `<work-project>` stack was destroyed by `docker compose
  down -v` with no `COMPOSE_PROJECT_NAME` set, so it hit the default project. **A session had refused
  that exact command as owner-only two minutes earlier.** Same rule, two sessions, two minutes apart:
  one obeyed, one did not.
- **VERIFIED, header of `~/.claude/hooks/gsd-worktree-path-guard.js`** (a hook he already runs): «The
  prose guard in agents/gsd-executor.md step 0b **is never enforced because the model under load skips
  it.** This hook enforces the constraint at the tooling layer, making it HARD-BLOCKING.» GSD hit
  R1-16's problem, tried R1-15's answer, watched it fail, and moved the rule into a hook.
- **VERIFIED, `~/.claude/settings.json` today:** `permissions.defaultMode = "bypassPermissions"`,
  `sandbox = null`, and **seven** PreToolUse guard hooks already wired (gsd-prompt-guard,
  gsd-read-guard, gsd-workflow-guard, gsd-worktree-path-guard, gsd-agent-isolation-guard,
  gsd-write-guard, gsd-secret-read-guard). So "no enforcement procedure" is not the status quo he is
  protecting — the status quo already has enforcement hooks in it.
- **VERIFIED, `plugins/harness/bin/harness-spawn.sh:32-39`:** the plugin passes
  `--dangerously-skip-permissions` to every session as the default **and** as the fallback for an
  unrecognised value. The plugin is not abstaining from setting the safety posture; it already sets it,
  on every spawn, to the least safe option.

Both halves are true at once: **the rules he wants are the rules his own run proved a model skips
under load, and the "abstract, simple" mechanism he already runs in GSD is a hook.** I do not resolve
this for him. The options below span from "trust the prose anyway" to "let the kernel check the path
he named," and choosing between them is a real choice about what he trusts.

One correction the research and the analysis both need, restored here from the transcript:
**«без складного механізму технічної ізоляції» [372]/[376] is the interviewer's phrasing and he never
confirmed it** — he talked over it and redirected the whole item to this analysis [378]. What he
*refused* at [370] was described to him at [364]/[365] as «окреме середовище, з якого він узагалі не
має доступу» — a container or a VM. Nobody offered him an OS-level path boundary. That distinction is
the hinge of §5.

---

## 2. Mechanism inventory — every way to bound what a process can touch, cheapest first

"Cost to set up once" = what **he** does once. "Cost per run" = the recurring tax. "Off Claude Code"
= does it work on Codex, Gemini, Kimi, pi, etc. Each row ends with the specific FIELD-NOTES incident it
would or would not have stopped.

### 2.1 Naming & labelling conventions (run-scoped names + docker labels)
- **Prevents:** teardown hitting the wrong thing, *if* every created object carries a run-scoped name.
  `docker compose -p orc-<run>-<lane>` + labels `orc.run=<id>`; teardown filters on the label.
- **Setup once:** zero (plugin-internal).
- **Per run:** zero.
- **Off Claude Code:** yes — it is a property of how the plugin invokes `docker`/`git`, engine-agnostic.
- **Incident:** **would have stopped §11.5** (the destroyed stack — a scoped `-p` never touches the
  default project). VERIFIED today: his live stack is labelled `com.docker.compose.project=<work-project>`,
  and `docker ps --filter label=…` works. **Would not stop** §5.1 (OOM), §11.10 (secrets).

### 2.2 Process-group ownership (`set -m` + group kill)
- **Prevents:** killing a process the run did not start, by killing *a recorded process group* instead
  of a pattern.
- **Setup once:** zero. **Per run:** zero.
- **Off Claude Code:** yes — pure shell in the spawn helper.
- **VERIFIED today:** `setsid` is **absent** on macOS; `set -m` puts each background job in its own
  group and `kill -TERM -- -<PGID>` kills that group and nothing else (`child pid=23958 pgid=23958
  own_pgid=23912 → GROUP KILL WORKED`).
- **Incident:** the exact replacement for the `pkill -f 'playwright test'` that **killed an unrelated
  lane, §11.8**. But its structural limit is also in the logs: **VERIFIED, `harness-term.sh:59-110`**
  the previous generation spawns sessions through `osascript` into iTerm2, so a session is *iTerm2's*
  child, not the orchestrator's — which is *why* it reached for `pkill` and why it over-matched. Group
  ownership needs a different identity (a pidfile the session writes, an iTerm/tmux id) for
  terminal-spawned sessions.

### 2.3 A run-scoped registry of everything spawned ("ownership ledger")
- **Prevents:** stopping/removing anything whose identifier the run did not write down at creation. No
  pattern matching, ever. This is Д3 made mechanical.
- **Setup once:** zero. **Per run:** one append per created resource; negligible.
- **Off Claude Code:** yes — it is the plugin's own bookkeeping, identical on every engine. **This is
  the only real boundary that is fully under the plugin's control and needs nothing from the user.**
- **Incident:** **would have stopped both §11.5 and §11.8** — teardown iterates the ledger, so a thing
  with no line cannot be named, and a thing with a line is named by its recorded identity, never by a
  pattern. Also fixes **§11.11** (150 orphaned volumes become findable). **Would not stop** file
  writes, a lane running `pkill` itself, §5.1, §11.10.

### 2.4 Path allow-lists as prose (the scope he named at [366])
- **Prevents:** on paper, everything outside a written path. In practice, only what a model chooses to
  honour.
- **Setup once:** he writes the path list once. **Per run:** injected into every prompt.
- **Off Claude Code:** yes as text; enforcement nowhere.
- **Incident:** this *is* the class that failed in **§11.5** (a written owner-only rule, obeyed once,
  skipped once) and in the GSD prose guard that became a hook. A written path with no checker is a
  hope, not a boundary.

### 2.5 Git worktree confinement (Д4's own default)
- **Prevents:** nothing by itself — but it makes a cheap boundary *sufficient*: if each task's session
  has cwd = its own worktree (a sibling dir off main), the run's writes are not in his folder at all,
  and the sandbox's zero-config default (writes confined to cwd) becomes the right rule with no path
  list to maintain.
- **Setup once:** zero — it is already his stated default [433]. **Per run:** worktree create/verify/
  remove; real plugin work, no user tax.
- **Off Claude Code:** yes (git, engine-agnostic).
- **Incident:** converts §11.8's case-2 (his parallel work in the same folder) into case-1. **But
  §12.5** recorded `QUESTIONS.md`/`JOURNAL.md` forking into a worktree copy and an owner question
  sitting invisible for an hour — so owner-facing files must live *outside* worktrees. And **§11.8**
  also recorded a branch computed one word off and a lane spawning into a stale worktree — identity
  must be verified at spawn. A worktree is a convention until something enforces cwd (§2.9).

### 2.6 Docker compose project scoping (`-p` + label filter)
- **Prevents:** a teardown escaping the run's own containers.
- **Setup once:** zero. **Per run:** one env/name per lane.
- **Off Claude Code:** yes.
- **Incident:** **§11.5 exactly.** What it cannot do: stop a bare `docker compose down` typed with no
  `-p`, and stop resource contention — his app was **OOM-killed (§5.1)**, not torn down. Labels are for
  teardown scoping, not protection.

### 2.7 PreToolUse deny hooks
- **Prevents:** a specified tool call, before it runs — and it **survives `bypassPermissions`**.
- **Setup once:** zero for him (plugin ships the hook); it reads his one file. **Per run:** one hook
  process per tool call; cheap.
- **Off Claude Code:** **no.** Claude-Code-only; Codex hooks are plausible-unverified, Gemini/opencode
  have no equivalent (CLAIMED, ADAPTER-CONTRACT §I).
- **Incident:** the mechanism GSD moved its skipped prose guard into, and it holds
  (VERIFIED-C8: a `permissionDecision:"deny"` hook blocked a Bash call under bypassPermissions; `~` and
  relative paths are expanded *before* hooks run, so a path matcher cannot be dodged by respelling).
  **Would not stop §11.10** (a secret printed by an allowed tool doing its declared job). Caveat: hooks
  run **unconstrained on the host**, so a session that can write `.claude/hooks/` can disarm one unless
  a sandbox also blocks that path.

### 2.8 Permission deny-lists (`permissions.deny`)
- **Prevents:** a command *spelling*. As a boundary: no.
- **Setup once:** a few lines. **Per run:** zero.
- **Off Claude Code:** partial (every engine has a deny/exclude list; all match strings).
- **Incident:** **VERIFIED-C8:** `Bash(rm:*)` denied under bypassPermissions, then `sh -c 'rm -f …'`
  deleted the file, exit 0. The docs call these patterns "fragile" and list four evasion classes. Path
  rules (`Edit`/`Read` on absolute/glob paths) are sound; command-string rules are not. Usable as an
  ergonomic guard-rail inside something that holds — never as the boundary.

### 2.9 PATH shims for dangerous binaries (`docker`/`pkill` wrapper first on PATH)
- **Prevents:** the *accidental* spelling — a bare `docker compose down` with no project.
- **Setup once:** low (ship a wrapper dir). **Per run:** zero.
- **Off Claude Code:** yes (property of the shell).
- **Incident:** would have blunted §11.5's accidental form. Walk-arounds are trivial:
  `/usr/local/bin/docker`, `env -i`, a script that resets PATH, the socket directly (INFERRED, not
  contestable). Good ergonomics, weak boundary.

### 2.10 `sandbox-exec` directly
- **VERIFIED today, `man sandbox-exec`:** «The sandbox-exec command is **DEPRECATED**.» It still works
  and is what Claude Code and Codex use underneath. Writing raw `.sb` profiles is strictly worse than
  the engines' front-ends. **Do not build on this directly.**

### 2.11 OS sandbox (Seatbelt via the engine's own front-end) — the path list he named, kernel-checked
- **Prevents:** writes outside the session's directory, signals to processes the session did not start,
  and reaching the docker socket — **regardless of what the model chose to run.**
- **Setup once:** **one settings key**; nothing to install on macOS. **Per run:** zero.
- **Off Claude Code:** Claude Code `sandbox.enabled` (VERIFIED); Codex `sandbox_mode="workspace-write"`
  and the standalone `codex sandbox -- <cmd>` wrapper (VERIFIED); Gemini/Qwen Seatbelt (CLAIMED);
  **Kimi, pi, opencode, Aider have no OS sandbox** (CLAIMED, ADAPTER-CONTRACT §H) — there, wrap with
  `codex sandbox --` or the lane is outside the boundary.
- **VERIFIED by me today, under his own `bypassPermissions`,** with
  `sandbox.enabled:true, allowUnsandboxedCommands:false, failIfUnavailable:true`:

  | attempt | cwd under `~/Work` | cwd under `/tmp` |
  |---|---|---|
  | write to a **sibling** dir | **blocked** — `operation not permitted`, file untouched | **allowed** — file clobbered |
  | write **inside** cwd | allowed | allowed |
  | `kill -TERM` an outside pid | blocked | blocked |
  | `docker ps` (daemon socket) | blocked | blocked |
  | `ls ~/Work` (read outside cwd) | allowed | allowed |

  **My own correction to the C8 research, and it is load-bearing:** the sandbox confines writes to
  **cwd + the session temp dir + the system temp dir**. C8 reported the sibling write as denied without
  the temp-dir carve-out; it is denied under `~/Work` (the real case) and *allowed* under `/tmp`. So the
  confinement holds for real project paths — **but if a worktree or cwd were ever placed under `/tmp`,
  the sandbox would not confine writes there.** Д4's siblings-under-`~/Work` design keeps confinement
  intact; a `/tmp` worktree would silently void it. Codex's `codex sandbox --` is stricter — it blocked
  the `/tmp` sibling write too (VERIFIED today).
- **Incident:** in a sandboxed session **§11.5 is structurally impossible** (the socket is unreachable,
  so `docker compose down -v` cannot run) and **§11.8's cross-session kill is impossible**. **Would not
  stop §5.1** (OOM), **§11.10** (a write inside the workspace). Two real costs: sandboxed Docker does
  not exist (the socket is blocked for legitimate work too), and a sandboxed session cannot signal a
  process it itself started in an earlier Bash call (each Bash call is its own sandbox instance —
  VERIFIED-C8) — so teardown must be done by the unsandboxed supervisor, not by a sandboxed lane.

### 2.12 Whole-process isolation: sandbox runtime / dev container / VM
- **Prevents:** almost everything in its scope — file tools, hooks and MCP servers are all inside the
  boundary, not just Bash.
- **Setup once:** `npx @anthropic-ai/sandbox-runtime claude` needs an `~/.srt-settings.json` (low but
  real); container/VM medium-to-high, per engine. **Per run:** container build/boot; on this machine
  Docker is already the contended resource (§5.1).
- **Off Claude Code:** container/VM yes; the sandbox runtime is Claude-Code-shaped.
- **Incident:** stops §11.5/§11.8 completely. **Would not stop §5.1** (OOM is contention, not access).
  The sandbox runtime is a **beta research preview** whose config format may change and which «starts
  anyway» with a broken settings file (CLAIMED) — a poor fit for 34 unattended hours. This is the shape
  he ruled out; priced honestly, not recommended.

**Two things nothing in this table touches, stated so no option below implies otherwise:**
- **§5.1 resource contention (OOM).** No access-control mechanism addresses it; the controls are
  scheduling controls (cap concurrent builds, watch `memory_pressure -Q`). Out of scope for R1-16.
- **§11.10 secrets in transcripts.** A permitted tool (`--trace on`) wrote passwords into a file the
  run is supposed to write to. Every boundary here permits that write. This is a scanning problem, not
  a boundary problem.

---

## 3. The options — six complete answers, genuinely different in what they trust

Each is a coherent whole he could pick and repeat from memory. Case 1 = his other projects/folders.
Case 2 = his own parallel work in the same folder.

---

### Option 1 — Trust the file (pure convention, zero mechanism)

- **Rule, in one sentence:** «Every agent reads my one prohibitions file before acting, and behaves.»
  R1-15 exactly as given — one appendable text file, read by all, no enforcement.
- **What enforces it:** nothing but the model. The file is injected into every prompt.
- **Case 1:** by good behaviour only. **Case 2:** by good behaviour only.
- **Cannot stop:** anything, when a model under load skips the rule — demonstrated twice in his own
  logs (§11.5, the GSD prose guard). No signal when it is skipped.
- **Setup first time:** zero. **Ongoing:** zero.
- **On a no-sandbox platform (Kimi, pi):** identical — the file was never a mechanism, so nothing is
  lost, and nothing was ever held.
- **Philosophy:** trust. This is the only option that changes nothing about how the last run failed.
  Its real worth is as the **policy source** every other option reads from.

---

### Option 2 — Ownership ledger (mechanical, small, pure-plugin)

- **Rule:** «The orchestrator may stop or remove only a thing whose id it wrote down when it created
  it — never by pattern, never from an env var.»
- **What enforces it:** the plugin's own spawn/teardown code. At spawn, record the process group
  (`set -m`, §2.2), the compose project name + `orc.run` label (§2.6), the worktree path; teardown
  iterates that ledger and nothing else. A build-failing lint rejects `pkill`, `killall`, an unscoped
  `docker compose down`, and any teardown argument taken from `$ENV`.
- **Case 1:** partial — it will not stop another project's containers or files, but it guarantees the
  run never *acts destructively* on anything it did not create. **Case 2:** **yes, exactly for
  processes and containers** — this is the precise fix for the `pkill` (§11.8) and unscoped
  `docker compose down` (§11.5) incidents, the two places his parallel work was actually hit. Also
  makes Д3 honest and cleans up §11.11's orphans.
- **Cannot stop:** file writes (it is about processes/containers/worktrees), and a *lane* running
  `pkill` inside its own tool call (it constrains the orchestrator, not its children).
- **Setup first time:** **zero.** **Ongoing:** zero.
- **On a no-sandbox platform:** **works unchanged** — it is pure plugin bookkeeping, engine-agnostic.
- **Philosophy:** provenance. The cheapest real improvement available, and the closest thing to «дуже
  якісь простий та надійний варіант … прописаний в плагіні» [370]. It belongs under every option below.

---

### Option 3 — Worktree anchoring (mechanical, small–medium)

- **Rule:** «Every task runs in its own git worktree, a sibling of the repo, off the main branch; the
  run writes only inside worktrees it created and its own state dir. My parallel work stays in the main
  checkout.»
- **What enforces it:** the spawn path sets cwd to a fresh worktree, verified at spawn (branch + base
  SHA match, path is new — §11.8's stale-worktree and one-word-off-branch failures made real); the
  worktree registry is part of Option 2's ledger, so removal at Д3 is scoped the same way. Owner-facing
  files (the red-line file, the questions channel) live **outside** worktrees (§12.5).
- **Case 1:** no, alone. **Case 2:** **yes, structurally** — after this, the run and his parallel work
  are no longer in the same directory, so "same folder" stops being the same folder. It is the only
  option that makes case 2 tractable *without* an enforcement layer.
- **Cannot stop:** a session `cd`-ing out of its worktree (a convention until §2.11 enforces cwd); the
  shared Docker daemon, ports, package caches; and it does not confine files in the *main* checkout,
  which his parallel edits may share.
- **Setup first time:** **zero** — already his Д4 default. **Ongoing:** worktree lifecycle is plugin
  work; no user tax, plus the honest cost that owner-facing files must be kept out of worktrees.
- **On a no-sandbox platform:** works — git is engine-agnostic; but "cannot `cd` out" is unenforced
  there.
- **Philosophy:** separation. Move the run out of his blast radius rather than police it.

---

### Option 4 — Give the file teeth (mechanical, semantic, Claude-Code-only)

- **Rule:** «My one file stays exactly as I wrote it — but the plugin blocks, at the tool layer,
  whatever I marked `never`.»
- **What enforces it:** **one** `PreToolUse` hook, shipped by the plugin, that reads the *same* file
  (no second file, no new habit) and hard-denies tool calls whose resolved **path** matches a `never`
  entry. It matches paths, not command strings (§2.8: command strings are bypassable via `sh -c`). Fail
  closed. This is the shape GSD already uses for its skipped prose guard.
- **Case 1:** yes, for file paths he names. **Case 2:** partial — protects named paths; nothing about
  processes (pair with Option 2 for that).
- **Cannot stop:** anything off the tool-call surface — a script the agent writes then runs is one tool
  call and the hook sees the script's path, not its contents; §11.10's secret leak; and it is
  **Claude-Code-only** (§2.7).
- **Setup first time:** zero for him (he already writes the file; the plugin ships the hook). **But it
  is exactly the «окрема обов'язкова процедура» he said was unnecessary [357]** — which is why it is a
  choice for him, not a default. **Ongoing:** zero.
- **On a no-sandbox platform:** the hook does not exist off Claude Code, so the file drops back to
  Option 1 there.
- **Philosophy:** make his own words load-bearing. It adds no file and no format; it only makes the
  file he already wants enforce itself, and it **fails loudly, naming the rule that fired** — so he
  learns which prohibitions actually get tested.

---

### Option 5 — Kernel boundary (mechanical, thorough, one flag)

- **Rule:** «Every session the orchestrator starts can only reach the folder it was given — the OS
  enforces it, not the model.»
- **What enforces it:** the operating system's own sandbox, set by the plugin at spawn (never a file he
  maintains):
  - Claude Code: `--settings '{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false,"failIfUnavailable":true}}'` (VERIFIED effective today).
  - Codex: `-c sandbox_mode="workspace-write"` with `writable_roots` = the worktree — his config is
    `danger-full-access` today (VERIFIED), so this is a real change.
  - No-sandbox engines: wrap with `codex sandbox -- <cmd>` (VERIFIED standalone Seatbelt front-end;
    INFERRED that it wraps another agent CLI cleanly), or accept the lane is outside the boundary and
    say so.
- **Case 1:** **yes, demonstrably** — VERIFIED today: a write to a neighbouring project returned
  `operation not permitted`, file untouched. **Case 2:** **yes for processes and for file writes** —
  VERIFIED: a sandboxed session cannot signal his processes and cannot write outside its own directory
  (under `~/Work`). Not for the shared Docker daemon if it is reopened.
- **Cannot stop:** reads outside cwd (VERIFIED: `ls ~/Work` succeeds) unless he also accepts
  `blockReadsOutsideWorkingDirectories` and its noise; §5.1 OOM; §11.10 secrets. **And it forces a
  Docker decision:** sandboxed Docker does not exist (the socket is blocked), so lanes cannot bring up
  their own stacks — he must pick socket-open (full host access, blunt), exclude-docker (narrower, but
  a bare `down` returns), or Docker-only-for-the-unsandboxed-orchestrator (smallest blast radius, needs
  per-role flags the plugin already sets for accounts). Teardown must run in the unsandboxed supervisor.
- **Setup first time:** **one line, if the plugin sets it; nothing to install on macOS.** The expensive
  part is the Docker decision, made once. **Ongoing:** zero.
- **On a no-sandbox platform:** **this is where it degrades** — Kimi/pi/opencode/Aider have no OS
  sandbox and Kimi's hooks fail open (CLAIMED, ADAPTER-CONTRACT §H). The lane must be wrapped with
  `codex sandbox --`, or confined to a worktree (Option 3) with the ledger (Option 2) as the only
  floor, and preflight must say so out loud.
- **Philosophy:** let the OS check the list. **This is the path list he named himself at [366]** —
  «прописаний шлях, до чого він має доступ» — with the kernel doing the checking instead of the model.
  Whether that is the «детерміністський варіант» he refused (a *container*, per [364]/[365]) or the
  «простий надійний варіант» he asked for is **his call** — see §5.

---

### Option 6 — Whole-process isolation (the shape he ruled out, priced honestly)

- **Rule:** «The whole agent — tools, hooks, MCP servers — runs inside one boundary: a sandbox-runtime
  prefix, a dev container, or a VM.»
- **What enforces it:** a command prefix (`npx @anthropic-ai/sandbox-runtime claude`) or a container
  image.
- **Case 1 and 2:** both, completely.
- **Cannot stop:** §5.1 OOM. And the sandbox runtime is beta (config may change; «starts anyway» on a
  broken settings file — CLAIMED); a container needs the Docker that is already contended here.
- **Setup first time:** low (sandbox runtime, an `~/.srt-settings.json`) to high (container/VM per
  engine). **Ongoing:** container build/boot per run.
- **On a no-sandbox platform:** the container path works anywhere; the sandbox runtime is Claude-shaped.
- **Philosophy:** total containment. Recorded for completeness and because «оверінжиринг» [370] was
  said about *this* shape. **Not recommended** — Option 5 gets most of the protection at a fraction of
  the cost, and beta software is a poor fit for an unattended overnight run.

**How they layer (they are not exclusive):** Option 2 (zero cost, fixes both recorded incidents) →
Option 3 (his default; turns case 2 into case 1) → Option 1 (his file, as the policy source) → Option
5 (one line; the only thing that holds when the model does not) → Option 4 (makes the file enforceable,
Claude-Code-only) → Option 6 (only if he ever wants hooks/MCP inside the boundary). **Options 2 and 3
cost him nothing and contradict nothing he said.**

---

## 4. The honest comparison

| | Stops stack-destruction class (§11.5, §11.8) | Stops same-folder class (case 2) | Works off Claude Code | His time cost | Can annoy him in normal work | What breaks when it misfires |
|---|---|---|---|---|---|---|
| **1 Trust the file** | No — the class that failed in his logs | No | As text, yes; as a boundary, nowhere | Zero | None | Nothing — and stops nothing; a skipped rule is silent |
| **2 Ownership ledger** | **Yes** — stop only recorded ids | **Yes** (processes/containers) | **Yes** (pure plugin) | **Zero** | None | A lost ledger orphans the run's own resources (append-only on disk fixes it) |
| **3 Worktree anchoring** | Indirectly (run leaves his folder) | **Yes** (structurally, for files the run makes) | Yes (git) | Zero (his default) | Slight — owner files must not sit in a worktree, or they fork (§12.5) | A stale/misnamed worktree runs the wrong code (verify at spawn) |
| **4 File with teeth** | Only what he names as paths | Partial (named paths) | **No** (Claude-Code-only) | Zero (plugin ships hook) | Low — a mis-scoped `never` blocks a legitimate write, but it says which rule fired | A wrong path rule hard-blocks real work; a session that writes `.claude/hooks` disarms it |
| **5 Kernel boundary** | **Yes** — `down -v` and cross-kill become impossible | **Yes** (writes + signals) | Claude/Codex/(Gemini,Qwen claimed); **not** Kimi/pi/opencode/Aider without a wrapper | One line (plugin) + one Docker decision | Medium — no sandboxed Docker; blocks a lane's own `docker logs`; reads still open | Over-tight roots fail legitimate writes; the Docker fork, chosen wrong, either reopens the host or lets `down` back in |
| **6 Whole-process isolation** | Yes | Yes | Container yes; runtime Claude-shaped | Low→high per engine | High — beta config, container overhead, competes for the contended Docker | Beta «starts anyway» misconfigured and silently confines to default paths |

None of the six stops **§5.1 (OOM)** or **§11.10 (secrets in transcripts)** — both are outside R1-16
and named here so no row is read as covering them.

---

## 5. My recommendation

**Ship Options 2 + 3 as the always-on floor, and turn on Option 5 (the kernel boundary) for the
sessions the orchestrator starts, defaulting to Docker-only-for-the-orchestrator.** Options 2 and 3
cost him nothing, contradict nothing he said, and between them make the two incidents that actually hit
his parallel work — the unscoped `docker compose down -v` and the over-matching `pkill` — mechanically
impossible, while leaving R1-15 standing exactly as he gave it. That alone is the "простий надійний
варіант … прописаний в плагіні" he asked for, and it is where I would stop if he wants to change as
little as possible. But Options 2 and 3 are provenance and separation, not enforcement: they govern
what the *orchestrator* does and where the run's files land, and they do nothing when a *lane* itself
runs a destructive command in its own tool call. Option 5 is the only mechanism I **verified today,
under his own `bypassPermissions`, holding without any model cooperation** — a sandboxed session could
not write to a neighbouring project, could not kill an outside process, and could not reach the Docker
socket — and it is not the "separate environment" he refused; it is the very path list he proposed at
[366], with the kernel checking it instead of the model. It costs one line the plugin sets, nothing to
install on macOS, and the session stays an ordinary session in his terminal.

**The strongest argument against it:** Option 5 is, by any honest reading, a *deterministic* mechanism
— the kernel deny is exactly the determinism he said he did not want, and the Docker collision it
forces (there is no sandboxed Docker; lanes cannot raise their own stacks without a real concession) is
new operational complexity he did not ask for and that could itself break a night. If his refusal at
[370] extends to *any* kernel-enforced boundary and not only to containers, then Option 5 is off the
table and the recommendation collapses to Options 2 + 3 plus, at most, Option 4 on Claude-Code lanes.

**The single question the recommendation hinges on:** is an OS-level path boundary — his own written
list, checked by the operating system rather than by the model — the simple reliable variant he asked
for, or the over-engineered deterministic one he refused? Everything above the 2+3 floor depends on
that one answer, and it is Q1 below.

---

## 6. What I need from him — three questions (Ukrainian, answerable out loud in under a minute)

1. **Про межу, яку ставить операційна система.** Коли ти казав, що не хочеш «детерміністського
   варіанту», тобі описували окреме середовище — контейнер. Але ти сам перед тим сказав інше: щоб в
   оркестраторі був «прописаний шлях, до чого він має доступ». Є спосіб зробити рівно це — щоб цей
   список шляхів перевіряла сама операційна система, а не модель. Один рядок у налаштуваннях, на мак
   нічого ставити не треба, сесія лишається звичайною сесією у твоєму терміналі, і я сьогодні
   перевірив — вона реально не дає сесії писати в чужу папку чи вбити чужий процес. **Це для тебе той
   самий оверінжиринг, чи це і є той простий надійний варіант, про який ти казав?**

2. **Про Docker, якщо межу вмикати.** Всередині цієї межі docker-сокет недоступний — та сама команда,
   що знищила твій стек, просто не виконається. Але й лейни тоді не піднімуть свої стеки. Три виходи:
   (а) відкрити сокет — це повертає повний доступ до хоста; (б) вивести `docker` з-під межі — вужче,
   але «docker compose down» знову можливий; (в) межа лише для виконавців, а Docker чіпає тільки сам
   оркестратор, зі скоупленим прибиранням. **Який із трьох?**

3. **Про твій файл заборон — чи давати йому зуби.** Твоє правило — один текстовий файл, який усі
   читають, без окремої процедури. Але у твоїх власних логах модель під навантаженням цей файл
   пропускала. Я можу лишити його рівно таким, як ти сказав, — просто текст, який усі читають; або
   додати одну невидиму перевірку, яка читає **той самий** файл і жорстко блокує те, що ти позначив
   «ніколи» (працює тільки в Claude Code). **Лишаємо файл суто як домовленість, чи даємо йому зуби?**

---

## 7. What I verified myself today (transcripts summarised)

- **Claude Code OS sandbox** under `--permission-mode bypassPermissions`, `sandbox.enabled:true,
  allowUnsandboxedCommands:false, failIfUnavailable:true`: cwd under `~/Work` — sibling write **blocked**
  (`operation not permitted`, file untouched), in-cwd write **ok**; cwd under `/tmp` — sibling write
  **allowed** (system-temp carve-out); outside-pid `kill` **blocked** both times; `docker ps` socket
  **blocked** both times; `ls ~/Work` **allowed** both times. (Corrects C8's blanket "sibling write
  denied".)
- **`codex sandbox -- bash -lc …`**: `/tmp` sibling write **blocked** (stricter than Claude), outside
  `kill` **blocked**, `docker ps` **blocked**, `ls ~/Work` **allowed**. Standalone Seatbelt wrapper,
  already installed.
- **`set -m` + `kill -TERM -- -<PGID>`** kills only the group; **`setsid` absent**; **`flock` absent**
  on this machine.
- **`~/.claude/settings.json` and the active switcher profile:** `defaultMode: bypassPermissions`,
  `sandbox: null`, seven PreToolUse guard hooks wired (incl. `gsd-worktree-path-guard.js`, whose header
  states the prose guard «is never enforced because the model under load skips it»).
- **`~/.codex/config.toml`:** `sandbox_mode = "danger-full-access"`, `model = "gpt-6-astra"`.
- **`plugins/harness/bin/harness-spawn.sh:32-39`:** default and unrecognised-value fallback both
  `--dangerously-skip-permissions`. **`harness-term.sh`:** sessions spawned via `osascript` into iTerm2.
  No `pkill`/`killall`/`compose down` currently in `bin/`.
- **`docker ps`** labels: `<work-project>-app-1`, `<work-project>-postgres-1` → `com.docker.compose.project=<work-project>`.
- **`git rev-parse --git-common-dir`** from a linked worktree resolves to the main `.git` (so a red-line
  file can be read through the main checkout and not fork).
- **`man sandbox-exec`:** DEPRECATED.

**Taken as VERIFIED-C8** (executed in the C8 research today, not re-run by me): a `PreToolUse`
`deny` hook holds under `bypassPermissions`; `permissions.deny Bash(rm:*)` defeated by `sh -c 'rm -f …'`.

**Source index:** `round-1/TRANSCRIPT-01.md` rows [357], [362]–[383], [430], [433] ·
`round-1/ANALYSIS-01.md` R1-15/R1-16/Д3 · `research/clusters/C8-boundaries-safety-{research,challenge}.md` ·
`research/architecture/SPEC-safety.md` §§2–6 · `research/architecture/RED-fidelity.md` F6/F7 ·
`research/platforms/ADAPTER-CONTRACT.md` §§1, 3(H), 6.4 · `plugins/harness/docs/FIELD-NOTES.md`
§§5.1, 7, 8, 11.5, 11.8, 11.10, 11.11, 12.5 · `~/.claude/settings.json` · `~/.codex/config.toml` ·
`~/.claude/hooks/gsd-worktree-path-guard.js`.
