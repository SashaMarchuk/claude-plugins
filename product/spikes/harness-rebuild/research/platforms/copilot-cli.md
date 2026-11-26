# GitHub Copilot CLI — platform profile for a provider-agnostic orchestrator

**Date of research:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0, arm64).
**Version examined:** `@github/copilot` **1.0.86**, published **2026-09-17** (npm `latest`).
**Prerelease channel:** `1.0.87-0`. **Package created:** 2025-09-25. **835 published versions.**

**Evidence tags:**
- **VERIFIED** — run on this machine, read in official GitHub docs source, or read in package metadata.
- **CLAIMED** — asserted by a README or marketing page only.
- **UNKNOWN** — could not be established in this pass.

**Method note.** Flag names below were obtained by installing 1.0.86 into an isolated sandbox
(`$SCRATCH/copilot-sandbox`) with a fake `HOME` and `COPILOT_HOME`, and running the binary's own
`--help`, `help <topic>` and subcommand help. Protocol facts were obtained by *speaking* to the
CLI's ACP server over stdio and reading its real JSON-RPC responses. Nothing in `~/.copilot` or any
other owner config was modified; no authenticated agent run was started; **no owner quota was
spent** (an unauthenticated `-p` run exits 1 before any model call — VERIFIED).

---

## 0. Executive summary: this is the strongest orchestrator target in the field so far

Copilot CLI is not a terminal chat program with a headless flag bolted on. It is a **Rust runtime
with two first-class machine control planes**, and GitHub ships an official multi-language SDK
whose entire purpose is driving it from another program.

The five axes the owner called non-negotiable come out like this:

| Non-negotiable axis | Verdict | Mechanism |
|---|---|---|
| **E. Read remaining quota** | **YES — best in field** | `account.getQuota` RPC → `entitlementRequests`, `usedRequests`, `remainingPercentage`, `resetDate` |
| **F. Switch account per role** | **YES — best in field** | Per-session `gitHubToken` on one runtime; or `COPILOT_HOME` per account; or `COPILOT_GITHUB_TOKEN` env |
| **D. Compaction from outside + proof** | **YES** | `/compact` over ACP; proof via `session.compaction_complete` (`preCompactionTokens`/`postCompactionTokens`/`summaryContent`) and the `preCompact` hook |
| **B. Resume exactly after a crash** | **YES, with a caveat** | `--session-id <uuid>` names the session *before* it exists; `COPILOT_ENABLE_INTERRUPTED_SESSION_RESTORE=1` for crash restore (opt-in, see §B) |
| **G. Answer the session's own question** | **YES — the only clean answer in the field** | `user_input.requested` / `user_input.completed` protocol events with `requestId`, `question`, `choices` |

**The single most important finding:** the owner has *already run this control plane*. His
`~/.copilot/logs/process-1789304552095-73204.log`, dated **2026-09-13**, reads:

```
2026-09-13T13:02:32.105Z [INFO] Starting CLI in server mode (stdio)
2026-09-13T13:02:32.108Z [INFO] Starting CLI in stdio mode (Rust JSON-RPC engine)
2026-09-13T13:02:32.123Z [INFO] CLI server ready (stdio mode, Rust JSON-RPC engine)
2026-09-13T14:20:59.337Z [INFO] Destroying 0 active sessions
```

I reproduced that exact log line on this machine with `copilot --server --stdio` (VERIFIED). That
is the Copilot SDK transport. Something on this machine — an IDE, the Copilot desktop app, or an
SDK client — spawned the runtime and held it for **78 minutes** on 2026-09-13, then shut it down
gracefully. The orchestrator's hardest surface is already installed and exercised here.

**The counterweight:** the binary is **not currently on PATH** (VERIFIED), it is a **145 MB single
Mach-O executable**, releases land **near-daily**, and there is a fail-closed enterprise-policy path
that can silently disable `--allow-all` (see §H). Details below.

---

## A. LAUNCH

### Headless / non-interactive — VERIFIED

```bash
copilot -p "PROMPT" --allow-all-tools
copilot --prompt "PROMPT" --allow-all-tools
echo "PROMPT" | copilot            # piped stdin; ignored if -p is also given
```

`--allow-all-tools` is **required for non-interactive mode** — the CLI's own help says so verbatim:
*"Allow all tools to run automatically without confirmation; required for non-interactive mode."*
(VERIFIED, `copilot --help`.)

| Flag | Exact text from `--help` | Note |
|---|---|---|
| `-p, --prompt <text>` | Execute a prompt in non-interactive mode (exits after completion) | |
| `-s, --silent` | Output only the agent response (no stats), useful for scripting with `-p` | |
| `--output-format <format>` | Output format: 'text' (default) or 'json' (JSONL, one JSON object per line) | possible values: `text`, `json` |
| `--stream <mode>` | Enable or disable streaming mode | possible values: `on`, `off` |
| `--no-ask-user` | Disable the `ask_user` tool (agent works autonomously without asking questions) | |
| `--usage-output-file <file>` | Write final usage statistics as JSON to the specified file | **undocumented in the web docs; only in `--help`** |
| `--share [<path>]` | Share session to markdown file after completion in non-interactive mode (default: `./copilot-session-<id>.md`) | |
| `--share-gist` | Share session to a secret GitHub gist after completion | |
| `-C <directory>` | Change working directory before doing anything else | |
| `--attachment <path>` | Attach a file to the initial prompt; only valid in non-interactive mode | repeatable |

**Exit codes.** `-p` exits **non-zero** when the run fails due to LLM backend errors — auth failures,
quota exhaustion, network issues (VERIFIED: changelog entry for that behaviour; and empirically an
unauthenticated `-p` run returned **exit=1** on this machine).

**Structured output.** `--output-format json` emits JSONL, one object per line (VERIFIED, docs +
`--help`). **The exact per-line event schema is not published in the web docs** (UNKNOWN in this
pass). The strong inference — not verified — is that it mirrors the SDK session-event taxonomy in
§C, since both are generated from the same CLI schema.

### Visible terminal the owner can attach to — VERIFIED

```bash
copilot                                 # interactive TUI
copilot -i "PROMPT"                     # interactive mode, auto-executes this prompt
```

`-i, --interactive <prompt>` starts the TUI *and* runs a prompt — exactly the "launch it visible,
seed it, let the owner type into it later" shape the harness needs.

The CLI is multiplexer-aware. `COPILOT_MULTIPLEXER` accepts `tmux`, `herdr`, or `none` and overrides
autodetection (VERIFIED, `copilot help environment`). The help text explicitly warns that herdr
panes inherit the herdr server's `TMUX` and that `COPILOT_MULTIPLEXER=tmux` is the usual fix for
nested tmux. **An orchestrator that launches sessions inside tmux should set this explicitly** rather
than trusting detection.

Useful launch-time companions: `--banner`, `--no-color`, `NO_COLOR`, `--screen-reader`,
`--plain-diff`, `--mouse/--no-mouse`, `terminalProgress` (OSC 9;4 progress in the tab title),
`updateTerminalTitle` (shows current intent in the terminal title — free progress signal for a
human watching), and `keepAlive: "on" | "busy" | "off"` which **prevents the machine sleeping during
an overnight run** (VERIFIED, `copilot help config`). That last one matters: it is the only platform
in this scan that ships its own caffeinate.

### Machine control planes — VERIFIED by running them

Two, and they are different protocols:

**1. ACP (Agent Client Protocol) server — `--acp`.** Public preview. Open standard
(agentclientprotocol.com), so a single orchestrator adapter written for ACP drives Copilot *and*
any other ACP agent.

```bash
copilot --acp                    # defaults to stdio
copilot --acp --stdio            # explicit
copilot --acp --port 3000        # TCP, binds 127.0.0.1 by default
```

`--stdio` and `--port` are **mutually exclusive** — VERIFIED by running it:
`Cannot specify both --stdio and --port for ACP mode.`

**2. SDK runtime server — `--server` (with `--stdio` or `--port`).** This flag is **hidden from
`--help`** but real and accepted (VERIFIED). It is the transport `@github/copilot-sdk` uses.
Running `copilot --server` with no port produced, on this machine:

```
CLI server listening on port 61922
Warning: No COPILOT_CONNECTION_TOKEN was set, so connections will be accepted from any client
```

**`COPILOT_CONNECTION_TOKEN` appears in no documentation and no help topic** (VERIFIED: zero hits in
the full dump of `copilot help environment` and `copilot --help`). It is a shared-secret gate on the
server port. **An orchestrator that runs a TCP control plane must set it**, or any local process can
drive the agent.

Other hidden-but-accepted flags found by probing (VERIFIED — each accepted where a bogus flag is
rejected with `error: unexpected argument`): `--stdio`, `--server`, `--port <port>`,
`--prefer-version`, `--sandbox`, `--no-sandbox`, `--worktree`, `--connect`. The changelog explains
why: *"`--no-auto-login` and `--no-sandbox` stay supported but remain hidden from help, as they were
before the clap port."*

### Fleet mode — VERIFIED

`--fleet` runs the prompt with *parallel subagent orchestration*, combinable with `-p`, `-i`, or
piped stdin. **Not supported in ACP server mode** (VERIFIED, docs). Concurrency is bounded by
`COPILOT_SUBAGENT_MAX_CONCURRENT` (default **32**, range 1–256) and `COPILOT_SUBAGENT_MAX_DEPTH`
(default **4**, range 1–128).

---

## B. IDENTITY & RESUME

### The orchestrator can name a session before it exists — VERIFIED

```
--session-id <id>
```

From the command reference, verbatim: *"Use an exact session or task ID when you do not want
`--resume`'s broader matching by ID prefix or session name. If the ID matches an existing session or
task, that session or task is resumed. **If nothing matches, a new session is created only when the
value is a valid UUID.** Names and ID prefixes do not create new sessions."*

This is the property that matters most for a supervisor: **generate a UUID, record it in the
orchestrator's own state, launch with it, and never scrape an id out of stdout.** The same UUID then
serves as the resume handle, the on-disk directory name, and the correlation key across restarts.

The docs warn: *"Do not combine this option with other session-selection or session-starting options
such as `--resume`, `--continue`, or `--connect`, because they compete to decide which session to
open or create."*

Over the SDK the equivalent is `client.createSession({ sessionId: "long-workflow-123", ... })`
(VERIFIED) — note the SDK accepts a **non-UUID string** there, unlike the CLI flag.

### The full resume surface — VERIFIED

| Flag | Behaviour |
|---|---|
| `-r, --resume[=VALUE]` | Resume by session ID, **ID prefix (7+ hex chars)**, or session name (exact, case-insensitive). Bare `--resume` opens an interactive picker and **requires a TTY**. |
| `--continue` | Resume the most recent session in the current working directory, falling back to the globally most recent session. |
| `-n, --name <name>` | Name a new session; `--resume` can then find it by that name. |
| `--connect[=SESSION-ID]` | Connect to a **remote** session or task. Conflicts with `--resume` and `--continue`. |
| `-w, --worktree[=NAME]` | Create/reuse an isolated Git worktree under `<repo>.worktrees/` and run there. Conflicts with `--resume`, `--continue`, `--connect`. |

**A trap worth designing around (VERIFIED, docs):** *"If multiple sessions exist and the picker
can't be shown (for example under `-p`, a non-TTY `-i`, or piped stdin), the CLI exits with an error
instead of silently starting a new session."* Good — it fails loudly rather than forking a ghost
session. But it means **an orchestrator must always pass an explicit `--resume=<ID>` or `--continue`,
never a bare `--resume`.**

`--resume=<exact UUID>` is also the fast path: the changelog records *"Speed up startup when
resuming an existing local session by its exact UUID with `--resume`."*

Over ACP: `session/load` exists and `agentCapabilities.loadSession: true` — VERIFIED by reading the
live `initialize` response from the running server.

### What survives a crash — VERIFIED, with one caveat

Session state lives on disk in `~/.copilot/session-state/<session-id>/`, so the conversation itself
survives a process kill or reboot. Resume from a clean start works via `--resume=<uuid>`.

The caveat is the *automatic* restore of a session that was mid-turn when the process died:

> *"If a session was still open when its CLI process went away—for example, due to a crash or a
> machine restart—the next `copilot` startup can offer to restore it... **A session whose agent was
> mid-turn automatically resumes that work once restored.** This restore behavior is temporarily
> opt-in while its startup dialog is reworked. Set the `COPILOT_ENABLE_INTERRUPTED_SESSION_RESTORE`
> environment variable to `1` to enable it."*

Two consequences for an unattended orchestrator:
1. **Set `COPILOT_ENABLE_INTERRUPTED_SESSION_RESTORE=1`** in the launch environment, or a crashed
   mid-turn session will not pick its work back up.
2. It is delivered as a **startup dialog** — i.e. it wants a TTY. Whether it degrades gracefully
   under `-p` is **UNKNOWN**. For a headless supervisor the more reliable pattern is: kill, then
   relaunch with the recorded `--session-id=<uuid>` and a fresh prompt that says "continue".

Resilience the platform gives for free (VERIFIED, changelog 1.0.86 and earlier):
- *"Resume sessions even when transcript files contain recoverable corruption"* (2026-09-17)
- *"Sessions containing events with non-URL strings in URL/URI fields resume without a 'Session file
  is corrupted' error"*
- Resuming a long session is read once at startup in parallel across cores — a benchmarked
  **230 MB, 74k-event transcript** loads in **under a second** (CLAIMED by changelog, vendor
  benchmark). That is a meaningful number for a harness that resumes all night.

**Not solved:** *"**No session locking** — Concurrent access to same session is undefined"*
(VERIFIED, SDK persistence docs; mitigation given is "implement application-level locking or
queue"). **The orchestrator owns this.** If two workers ever resume the same `--session-id`, the
platform will not stop them.

---

## C. TRANSCRIPT

### On disk — VERIFIED (from the official config-directory reference)

```
~/.copilot/session-state/<session-id>/events.jsonl     # the event log
~/.copilot/session-state/<session-id>/                 # plus plans, checkpoints, tracked files
~/.copilot/session-store.db                            # SQLite, cross-session data
~/.copilot/command-history-state/                      # command history
~/.copilot/logs/process-<epoch-ms>-<pid>.log           # per-process log
```

Verbatim from the docs: *"Contains session history data, organized by session ID in subdirectories.
Each session directory stores an event log (`events.jsonl`) and workspace artifacts (plans,
checkpoints, tracked files). This data enables session resume (`--resume` or `--continue`)."*

Legacy location, still honoured and migrated on resume: `~/.copilot/history-session-state`
(VERIFIED — the format switch landed in **0.0.342, 2025-10-15**).

The whole tree relocates with **`COPILOT_HOME`** (VERIFIED), which is what makes per-account
isolation work — see §F.

Process logs are pruned automatically at startup to prevent unbounded growth (VERIFIED, changelog).
The log directory can be redirected per-run with `--log-dir <directory>` and the verbosity set with
`--log-level <none|error|warning|info|debug|all|default>`.

### Can a supervisor read progress live? — YES, three ways

**1. Tail `events.jsonl`.** It is JSONL and append-structured. Usage metrics are persisted into it
after each session ends (VERIFIED, changelog: *"Session usage metrics (requests, tokens, code
changes) are now persisted to `events.jsonl` after each session ends"*).

**2. Subscribe to the live event stream** over the SDK server or ACP. This is the real answer. The
published event taxonomy (VERIFIED, SDK streaming-events reference) is unusually complete:

| Event | Key data fields | Why an orchestrator cares |
|---|---|---|
| `assistant.turn_start` / `assistant.turn_end` | `turnId` | turn boundaries |
| `assistant.message` | `messageId`, `content`, `toolRequests?`, `outputTokens?` | what it said |
| `assistant.usage` | `model`, `inputTokens`, `outputTokens`, `cost`, `duration` | per-call spend (ephemeral) |
| `tool.execution_start` / `_complete` | `toolCallId`, `toolName`, `success`, `error?` | what it actually did |
| `session.usage_info` | **`tokenLimit`, `currentTokens`, `messagesLength`** | **live context fullness (§D)** |
| `session.compaction_start` / `_complete` | `success`, `preCompactionTokens`, `postCompactionTokens`, `summaryContent`, `compactionTokensUsed`, `requestId` | **compaction proof (§D)** |
| `session.usage_checkpoint` | `totalNanoAiu`, `totalPremiumRequests?` | running spend |
| `session.idle` | `aborted?` | **the reliable "done" signal** |
| `session.task_complete` | `summary?` | semantic "done" (best-effort) |
| `session.error` | `errorType`, `message`, `statusCode?` | failure classification |
| `session.shutdown` | `shutdownType`, `codeChanges`, `modelMetrics` | final accounting |
| `permission.requested` / `.completed` | `requestId`, `permissionRequest`, `result.kind` | **§G** |
| `user_input.requested` / `.completed` | `requestId`, `question`, `choices?` | **§G — the agent's own question** |
| `elicitation.requested` / `.completed` | `requestId`, `message`, `requestedSchema` | structured info request |
| `session_limits_exhausted.requested` / `.completed` | `maxAiCredits`, `usedAiCredits`, `response.action` | **§E — in-band budget stop** |
| `subagent.started` / `.completed` / `.failed` | `agentName`, `durationMs`, `totalTokens`, `totalToolCalls` | fleet visibility |
| `command.queued` / `.completed` | `requestId`, `command` | slash command dispatch |
| `abort` | `reason` | cancellation |

Note the `Ephemeral` column in the source: `assistant.usage`, `session.usage_info`, `session.idle`,
`user_input.*`, `elicitation.*` and `command.*` are **ephemeral — delivered live but not replayed on
resume**. A supervisor that reconnects to a session must re-read state via RPC
(`session.usage.getMetrics`, `session.metadata.contextInfo`) rather than expecting a replay.

**3. OpenTelemetry.** Set `COPILOT_OTEL_FILE_EXPORTER_PATH=/path/to.jsonl` and the runtime writes
every trace and metric as JSON-lines to a file with no collector at all (VERIFIED,
`copilot help monitoring`). Span tree is `invoke_agent → plan → chat <model> / execute_tool <tool>`,
following the OTel GenAI semantic conventions, with **subagent invocations linked into the same
trace via context propagation**. Metrics include `gen_ai.client.token.usage`,
`gen_ai.invoke_agent.tool_calls`, `github.copilot.code.lines_added` / `lines_removed`. For an
orchestrator that wants one uniform telemetry pipe across many sessions, this is cheaper than
parsing transcripts.

### Export — VERIFIED

`--share [<path>]` writes the whole transcript to Markdown after a non-interactive run (default
`./copilot-session-<id>.md`); `--share-gist` publishes it as a secret gist. Since 1.0.85,
*"Exporting a resumed session with `--share` or `--share-gist` writes the whole transcript instead of
only the latest run."* There is also a **semantic JSONL interchange format** with
`copilot sessions import <transcript.jsonl>` (flags: `--dry-run`, `--output json`,
`--working-directory`, `--name`) and `copilot memories import <memories.jsonl>` (VERIFIED by running
`--help` on both). That is a genuine cross-tool transcript import path — rare in this field.

---

## D. CONTEXT

This is the axis the owner's current harness fails at. Copilot answers all three halves of it:
**read**, **trigger**, and **proof**.

### Read how full the context window is — VERIFIED, and it is free

Four independent reads, none of which costs a model call:

1. **`session.usage_info` event** — `currentTokens`, `tokenLimit`, `messagesLength`. Emitted
   *"whenever the context-window size changes"*. Push, live, zero cost.
2. **`session.metadata.contextInfo` RPC** — on-demand pull, *"for example, right after resuming a
   session"*. Returns `totalTokens`, `promptTokenLimit`, `systemTokens`, `conversationTokens`,
   `toolDefinitionsTokens`. Pass `0` for `promptTokenLimit`/`outputTokenLimit` to use runtime
   defaults. **Returns `null` until the session has initialised** (system prompt and tool metadata
   cached) — a supervisor must tolerate that. Marked **experimental** in the generated RPC surface;
   in .NET it raises diagnostic `GHCP001`.
3. **`/context` over ACP** — the docs are explicit: *"informational commands such as `/usage` or
   `/context` return their output without invoking the model"*. Text, not structured, but free.
4. **Custom status line** — `settings.json` key `statusLine` with `type: "command"`,
   `command: <script>`, `refreshInterval: <seconds>`. *"The command receives the current session
   status as JSON on stdin and should print the status line to stdout."* The changelog confirms
   *"Status line script now includes context window fields that match the model badge and `/context`
   output."* **This is a polling read that works even for a session the orchestrator did not spawn**
   — install a status-line script that writes the JSON to a file the supervisor watches. The exact
   stdin JSON schema is **UNKNOWN** (not published; would need one authenticated run to capture).

There is also a `recomputeContextTokens` RPC (`session.metadata.recomputeContextTokens`), likewise
experimental.

### Trigger compaction from outside — VERIFIED

| Route | How | Notes |
|---|---|---|
| **ACP** | send `/compact` as a prompt — a single text content block | **The documented, supported route.** `/compact` is in the advertised `available_commands_update` list. Accepts optional focus instructions. |
| **SDK** | `session.send("/compact")` | `command.queued` / `command.completed` events exist, so slash commands dispatch over the SDK too. Not shown in an official example — **CLAIMED by inference**, not verified end-to-end. |
| **Threshold config** | `infiniteSessions: { enabled: true, backgroundCompactionThreshold: 0.80, bufferExhaustionThreshold: 0.95 }` on `createSession` | Ratios 0.0–1.0, not token counts. Lets the orchestrator *tune when* compaction fires instead of commanding it. |
| **Default behaviour** | automatic at ~80%, hard pause at ~95% | *"When your conversation reaches approximately 80% of the context window's capacity, Copilot automatically starts compacting the context in the background... If the context fills to approximately 95% before compaction finishes, Copilot pauses briefly to wait for compaction to complete."* |

**`session/compact` is NOT an ACP method** — VERIFIED by probing the live server: it returned
`-32601 "Method not found": session/compact`. Compaction over ACP goes through the prompt channel as
a slash command, not through a dedicated RPC. Do not guess otherwise.

### Proof it happened — VERIFIED, and it is unusually good

Four independent receipts:

1. **`session.compaction_complete` event** carries `success`, `error?`, `preCompactionTokens`,
   `postCompactionTokens`, `preCompactionMessagesLength`, `summaryContent`, `compactionTokensUsed`
   (`{input, output, cachedInput}`), and `requestId`. A before/after token count **is** the proof.
2. **`preCompact` hook** fires on manual *and* automatic compaction, with a `matcher` on the trigger.
   Its payload is exact:
   ```typescript
   { sessionId, timestamp, cwd, transcriptPath, trigger: "manual" | "auto", customInstructions }
   ```
   `trigger` distinguishes an orchestrator-commanded compaction from an automatic one — that is
   precisely "proof it was *my* compaction". `transcriptPath` hands the supervisor the file.
3. **Checkpoints on disk.** *"Every time compaction happens—whether automatically or manually—a
   checkpoint is created... stored as a numbered, titled file in your session's workspace."* Read
   them with `/session checkpoints` and `/session checkpoints <N>` — and `/session` is available over
   ACP (use the explicit subcommand: `/session info`, not bare `/session`). Since 1.0.86,
   *"Automatic compaction now saves a checkpoint that appears in `/session checkpoints`."*
4. **OpenTelemetry.** *"chat spans after a successful compaction carry
   `gen_ai.conversation.compacted=true`, and the summary is emitted as a `CompactionPart` in
   `gen_ai.input.messages`."*

### Custom compaction

There is **no custom-compaction hook that replaces the summariser** (`preCompact` is
notification-only — *"No — notification only"* in the output-processed column). The available
customisation is:
- **Focus instructions**: `/compact <focus instructions>` shapes the summary (VERIFIED, changelog:
  *"`/compact` accepts optional focus instructions to shape the compaction summary"*).
- **`history.clearContext` RPC** — a harder reset that *"preserves the session identity, system and
  developer messages, configuration, and event log while removing the model-facing conversation"*,
  seeded by a required `prompt` that becomes the first user message. Emits `session.context_cleared`
  with `messagesCleared`. **Restriction (VERIFIED):** *"`clearContext` is a tool-handler primitive.
  The runtime rejects calls made without a tool call in flight, calls with an empty seed prompt, and
  calls on remote sessions."* So an external supervisor **cannot call it directly** — it must be
  wrapped in a custom tool with `isTerminal: true` that the model invokes. That is the
  GSD-style "handoff" primitive, but the *agent* has to pull the trigger, not the orchestrator.

**Related knob worth knowing:** `COPILOT_LARGE_OUTPUT_THRESHOLD_BYTES` (default `20480` = 20 KiB).
Tool output above it is written to a temp file and the model sees a path plus a preview instead of
the full text. That is the single biggest lever on context burn rate in a long unattended run.

---

## E. QUOTA — the owner's hardest requirement, and Copilot answers it

### Programmatic read of REMAINING capacity — VERIFIED

`account.getQuota` — a **Server-scope RPC**, not session-scope, so it can be called on a connection
with no session open.

> *"`account.getQuota` reports the authenticated user's **remaining Copilot entitlement**. The
> result's `quotaSnapshots` map is keyed by quota type—commonly `premium_interactions`, `chat`, and
> `completions`. Use it to show users how much of their monthly allowance is left, or to gate work
> before they hit a limit."*

Per-snapshot fields (VERIFIED, official field table):

| Field | Type | Meaning |
|---|---|---|
| `entitlementRequests` | number | Requests included in the entitlement, or **`-1` for unlimited** |
| `usedRequests` | number | Requests used so far this period |
| `remainingPercentage` | number | Percentage of the entitlement remaining |
| `resetDate` | string | **ISO 8601 date when the quota resets** |

```typescript
const { quotaSnapshots } = await client.rpc.account.getQuota({});
const premium = quotaSnapshots["premium_interactions"];
// premium.usedRequests / premium.entitlementRequests, premium.remainingPercentage, premium.resetDate
```

**Warning from the docs, which an adapter must honour:** *"The `quotaSnapshots` keys are runtime
strings that the SDK type system does not validate, so guard your lookups."* Do not hard-code
`premium_interactions` without a fallback.

**And this is the axis-E/axis-F crossover, VERIFIED:** *"To read quota for a specific user rather
than the connection's global auth context (for example, in a multi-tenant backend), pass that user's
GitHub token to `getQuota`."* **One supervisor process can poll the remaining quota of every configured account without spawning a session per account.** Nothing else in this scan does that.

### What windows exist — VERIFIED

- **Monthly entitlement** of **AI credits** (current billing platform) or **premium requests**
  (legacy billing platform). `resetDate` is exposed per snapshot.
- **Weekly limits** exist as a distinct thing: *"`/usage` shows quota progress bars for session and
  **weekly** limits"* (VERIFIED, changelog).
- **Per-model rate limits** and **integration limits** are separately classified — the
  `continueOnAutoMode` setting acts on *"eligible rate limit errors (per-model, weekly, or
  integration limits)"* but explicitly *"does not apply to global rate limits, generic 429s, or BYOK
  providers."*
- **Opt-in per-session soft cap**: `--max-ai-credits <credits>`, minimum **30**. Accounting caveat
  from `copilot help limits`, verbatim: *"The AI credit limit is a soft cap: usage is known only
  after a model response returns. A response can therefore exceed or exhaust the limit before the CLI
  can observe that it has done so; the next model call is then blocked."* And: *"Hidden model work
  such as compaction counts toward `--max-ai-credits`."*
- **Autopilot continuation cap**: `--max-autopilot-continues <count>`, default **5** — a *turn*
  budget rather than a credit budget.

### Is a limit-hit signalled in-band? — YES, VERIFIED

- **Session budget**: `session_limits_exhausted.requested` (`requestId`, `maxAiCredits`,
  `usedAiCredits`) → the orchestrator answers with `session_limits_exhausted.completed`
  (`response.action`, `response.additionalAiCredits?`, `response.maxAiCredits?`). **This is a
  request/response pair, not a notification — the supervisor can top the budget up and continue,
  programmatically, without a human.** That is a genuinely unusual capability.
- **Account/plan limits**: surface as `session.error` with `errorType`, `message`, `statusCode?`; and
  under `-p`, as a **non-zero exit code** (VERIFIED). *"Rate limit errors now show retry timing in
  user-friendly messages"* (changelog) — so a reset time is present in the message text, though
  **whether it is exposed as a structured field is UNKNOWN**.
- **Auto-degrade**: `continueOnAutoMode: true` makes eligible rate-limit errors *"trigger an
  automatic switch to auto mode and retry"* rather than pausing. For an overnight queue this is the
  difference between finishing on a cheaper model and stopping at 02:00.
- Warnings are raised at **50% and 95%** of capacity (changelog), and the session-limits timeline at
  **50 / 75 / 90%**, including the line *"If this session continues, the next model call is final;
  tools will be disabled."*

### Post-hoc accounting — VERIFIED

- `--usage-output-file <file>` writes **final usage statistics as JSON** at the end of a run, with
  **per-agent metrics** since 1.0.86 (changelog: *"Add per-agent usage metrics to
  `--usage-output-file` JSON output"*). Schema **UNKNOWN** — undocumented on the web; one real run
  would capture it.
- `session.usage.getMetrics` RPC (experimental) for accumulated AI-credit and token totals.
- OTel span `github.copilot.session.shutdown` carries
  `github.copilot.total_premium_requests`, `lines_added`, `lines_removed`, `files_modified_count`.
- `models.list` RPC exposes **per-model AI credit pricing**, so cost can be estimated *before*
  dispatching work.

### The REST API path — VERIFIED, but it is the wrong tool

These endpoints exist (VERIFIED — GitHub returned
`documentation_url: .../rest/billing/usage#get-billing-usage-report-for-a-user` when probed):

```
GET /users/{username}/settings/billing/ai_credit/usage
GET /users/{username}/settings/billing/premium_request/usage
GET /users/{username}/settings/billing/usage
GET /users/{username}/settings/billing/usage/summary
```

Two reasons not to build on them:
1. They require the **`user` scope**, which the owner's current `gh` token does not have (VERIFIED:
   the probe returned *"This API operation needs the `user` scope"*). Granting it is a real decision.
2. **They report consumed usage, not remaining entitlement** — fields are `grossQuantity`,
   `netQuantity`, `grossAmount`, `netAmount`, `pricePerUnit`, with **no remaining/included quota
   metric** (VERIFIED). They also only apply *"if the user has purchased their own Copilot plan"* —
   org- or enterprise-managed licences report at org/enterprise level instead.

**Use `account.getQuota`. It is the only source that gives remaining capacity and a reset date.**

---

## F. ACCOUNTS — also best in field

### Several accounts on one machine — VERIFIED, three mechanisms of increasing quality

**1. Environment token (simplest).** Precedence, verbatim from `copilot help environment`:
`COPILOT_GITHUB_TOKEN` → `GH_TOKEN` → `GITHUB_TOKEN`. Supported token types: *"fine-grained personal
access tokens (v2 PATs) with the 'Copilot Requests' permission, OAuth tokens from the GitHub Copilot
CLI app, and OAuth tokens from the GitHub CLI (`gh`) app. **Classic personal access tokens (`ghp_`)
are not supported.**"*

The owner's `gh` token is `gho_…` — a GitHub CLI OAuth token, i.e. **a supported type** (VERIFIED:
`gh auth status` shows `Token: gho_…` for account `SashaMarchuk`). So
`GH_TOKEN=$(gh auth token) copilot -p …` is a working per-account launch today, with **no new
credential to create** — though the `gh` token's scopes (`gist, project, read:org, repo,
write:packages`) do **not** include `user`, which only matters for the REST billing path, not for the
CLI itself. Whether that token carries Copilot entitlement is **UNKNOWN** (untested — would require
an authenticated run).

One documented exception: *"in Codespaces, the auto-injected `GITHUB_TOKEN` (a user-to-server token)
does not take precedence over a `/login` account."*

**2. `COPILOT_HOME` per account (full isolation).** *"Override the directory where configuration and
state files are stored; defaults to `$HOME/.copilot`."* Everything moves with it — `settings.json`,
`config.json` (which holds `loggedInUsers`), `session-state/`, `permissions-config.json`,
`mcp-config.json`, `skills/`, `agents/`, `hooks/`, `logs/`. A legacy `--config-dir=DIRECTORY` flag
also exists; the docs say *"The `--config-dir` option is a legacy option. Prefer `COPILOT_HOME`."*
Resolution order for `permissions-config.json` is published explicitly: `--config-dir` → `COPILOT_HOME`
→ `~/.copilot`.

`COPILOT_CACHE_HOME` separately relocates the cache (marketplace, auto-update packages).

This is directly analogous to the owner's existing `CLAUDE_CONFIG_DIR` / profile-switcher machinery — **the same
orchestrator concept transfers with no new design.**

**3. Per-session `gitHubToken` on one runtime (the good one).** VERIFIED from the SDK multi-tenancy
guide:

```typescript
const session = await client.createSession({
    sessionId: `user-${user.id}-${crypto.randomUUID()}`,
    model: "gpt-5.4",
    gitHubToken: user.githubToken,      // <-- per-session account
});
```

The guide's own option table lists *"Per-session `gitHubToken` — Scoping auth to the requesting user
— **Prefer this over a single shared user token.**"* Companion options: `baseDirectory` (isolates
`COPILOT_HOME` per runtime instance; *"Ignored when connecting to an existing runtime"*),
`sessionIdleTimeoutSeconds`, `sessionFs` (route session storage off local disk), `mode: "empty"`
(**required for multi-user scenarios** — disables ambient OS tools and CLI defaults; the guide says
explicitly *"Do not use the default `mode: "copilot-cli"` for shared servers"*), and
`RuntimeConnection.forUri(url)` to share one already-running runtime.

**This means one supervisor process, one runtime, N sessions, each on a different GitHub account,
each with its own quota readable via `getQuota(userToken)`.** That is exactly the fleet shape the
owner described, and Copilot is the only platform in this scan that ships it as a supported feature
rather than a workaround.

### Credential storage — VERIFIED

`copilot login` stores the token *"securely in the system credential store"* (macOS Keychain). Fallback:
*"If a credential store is not found or there is an issue using it, the token will be stored in a
plain text config file under `~/.copilot/`."* Non-interactive login paths:

```bash
copilot login --with-token < token.txt       # reads token from stdin
copilot login --device-code                  # OAuth device flow (default in SSH/CI/headless)
copilot login --web-flow                     # browser flow (default on local desktop)
copilot login --host https://example.ghe.com # GHE Cloud with data residency
```

**Headless-relevant:** the CLI **auto-detects** remote/headless environments (SSH, Codespaces, dev
containers, CI, headless Linux) and defaults to device code there. And crucially, *"Copilot login
will also use an authentication token found in environment variables. This method is most suitable
for 'headless' use such as automation."* — so an orchestrator never needs to drive an interactive
login at all.

`config.json` holds **`loggedInUsers`** (plural), and the interactive `/user [show|list|switch]`
command manages that list. Switching accounts has a documented side effect worth knowing
(VERIFIED, config-dir reference): managed settings are *server-fetched per account* and are
**cleared on account switch**; MDM device policy is **never** cleared.

### Can a RUNNING session's account be changed? — NO

`/user switch` is an **interactive slash command only**. It is not in the `available_commands_update`
list documented for ACP (the docs name `/login` among commands that *"depend on the interactive
terminal interface and are not handled by the ACP server"*), there is no `copilot user` subcommand
(VERIFIED — the subcommand list is `app, login, help, init, update, version, sessions, memories,
plugin, mcp, skill, instruction, lsp, completion`), and the SDK's `gitHubToken` is set at
`createSession` time.

**Workaround and its cost:** close the session and open a new one on the other account with the same
`sessionId`/`--session-id`. Session state is on disk under `COPILOT_HOME`, so if the two accounts
share a `COPILOT_HOME` the transcript survives the switch; if they have separate `COPILOT_HOME`s (the
safer isolation), the transcript does **not** follow and the orchestrator must re-seed context.
**Cost: one compaction-summary-sized re-prompt per account switch.** Pick one: isolation or
cross-account resume. This is the only place where the owner's existing Claude Code setup (where
every switcher profile symlinks into one shared content store, so resume works across accounts) is
*ahead* of what Copilot gives out of the box — and the fix is the same trick: share
`session-state/` between `COPILOT_HOME`s by symlink. **Untested — UNKNOWN whether Copilot tolerates
that.**

---

## G. INTERVENTION — the axis the current harness fails, answered three ways

The field notes record a harness nudge that cannot submit stranded text. Copilot has no such
problem, because text does not go through a keyboard.

### 1. Send an instruction into a RUNNING session, and know it arrived — VERIFIED

The SDK exposes two delivery modes on `MessageOptions` (VERIFIED, official API reference table):

| Mode | Effect | During active turn | During idle |
|---|---|---|---|
| `"immediate"` (**steering**) | Inject into current turn | Injected **before next LLM call** | Starts a new turn immediately |
| `"enqueue"` (**queueing**, default) | Queue for next turn | Waits in **FIFO queue** | Starts a new turn immediately |

```typescript
const msgId = await session.send({ prompt: "Refactor the auth module to use sessions" });
// while it is working:
await session.send({ prompt: "Actually, use JWT tokens instead", mode: "immediate" });
```

**`session.send()` returns a message id** — that is the arrival receipt. The docs also describe the
failure mode honestly: *"If a steering message arrives after the turn completes, it's automatically
moved to the queue."* So a steer is never lost; it may merely land a turn later. An orchestrator
should treat the returned id as "accepted", and `assistant.turn_start`/`user.message` events as
"observed".

Best-practice guidance from the docs, which an orchestrator should encode: *"Don't over-steer—multiple
rapid steering messages can degrade turn quality."*

Over ACP the equivalent is `session/prompt` (VERIFIED it exists: probing with bad params returned
`-32602 Invalid params` with a Zod error naming `sessionId` and `prompt`, not `method not found`).

### 2. Answer a permission prompt programmatically — VERIFIED, two independent routes

**Route A — protocol callback.** In the SDK: `onPermissionRequest` on `createSession`. The ACP
equivalent is the client-side `session/request_permission` method, which the client (i.e. the
orchestrator) implements. In the official ACP example the handler is one line:

```typescript
async requestPermission(params) { return { outcome: { outcome: "cancelled" } }; }
```

Observable as `permission.requested` (`requestId`, `permissionRequest`) → `permission.completed`
(`requestId`, `result.kind`). Correlated by `requestId`. This is exactly the shape the owner asked
for: *"a protocol event rather than typing on a screen."*

**Route B — the `permissionRequest` hook, which needs no protocol client at all.** VERIFIED, and
this is the sleeper finding:

> *"The `permissionRequest` hook fires before the permission service runs—before rule checks, session
> approvals, auto-allow/auto-deny, and user prompting. If hooks return `behavior: "allow"` or
> `"deny"`, that decision short-circuits the normal permission flow... Use it to approve or deny tool
> calls programmatically—**especially useful in CLI pipe mode (`-p`) and other CLI CI usages where no
> interactive prompt is available.**"*

Output contract:

| Field | Values | Meaning |
|---|---|---|
| `behavior` | `"allow"`, `"deny"` | approve or deny |
| `message` | string | reason fed back to the LLM when denying |
| `interrupt` | boolean | with `"deny"`, **stops the agent entirely** |

Return `{}` to fall through to normal handling. For command hooks, **exit code 2 is treated as a
deny**. Hooks can be `command`, `exec` (no shell), or **`http`** — an HTTP hook POSTs the JSON
payload to a configured URL and reads the decision from the response. **That is a supervisor-decides
permission loop with zero protocol code**: point every session's `permissionRequest` hook at the
orchestrator's local HTTP endpoint. (For `preToolUse` and `permissionRequest`, the hook URL **must
be `https://`** — the docs are explicit, *"because the response can grant tool permissions."*)

One documented hole: **sandbox-bypass requests cannot be auto-approved.** *"for any request that asks
to escape the sandbox (`requestSandboxBypass: true` in `toolInput`), a hook `allow` does not
pre-approve the request... Only `deny` still propagates."* If the sandbox is on, an unattended run
will stall on any command that needs to leave it.

### 3. Answer the session's OWN clarifying question — VERIFIED

This is the part almost no platform in this scan gets right. Copilot models `ask_user` as a **tool**,
and surfaces it as a correlated protocol request:

```
user_input.requested   → { requestId, question, choices? }
user_input.completed   → { requestId }
elicitation.requested  → { requestId, message, requestedSchema }
elicitation.completed  → { requestId }
```

A supervisor answers by responding to `requestId`. **The `choices` array means the orchestrator can
answer a multiple-choice question without inventing free text** — the single most useful detail here.

Three fallbacks, in descending order of cleanliness:
- **`notification` hook with `matcher: "elicitation_dialog"` or `"permission_prompt"`.** Its output
  contract is `{ additionalContext?: string }` and *"the text is injected into the session as a
  prepended user message. **This can trigger further agent processing if the session is idle.**"*
  That is a working out-of-band answer channel for a session the orchestrator did not spawn. Notification
  types, verbatim: `shell_completed`, `shell_detached_completed`, `agent_completed`, `agent_idle`,
  `permission_prompt`, `elicitation_dialog`.
- **`preToolUse` hook matching `ask_user`** — deny with `permissionDecisionReason` carrying the
  answer. Crude; the model receives it as a denial message.
- **`--no-ask-user`** — refuse the whole category. The autopilot doc notes the trade-off plainly:
  *"the agent must make decisions on its own, rather than asking for your input."*

### 4. Keep it going — VERIFIED

`agentStop` / `subagentStop` hooks can **block and force another turn**. Guardrail, verbatim:
*"An `agentStop` hook that always blocks no longer loops indefinitely: the CLI now ends the turn
after **8 consecutive blocks**, and `agentStop` hooks receive a `stop_hook_active` flag so they can
detect a forced continuation and self-limit."* So an orchestrator that wants "don't stop until the
tests pass" has a supported mechanism with a built-in escape hatch.

### 5. Cancel — a gap

`session/cancel` returned **`-32601 "Method not found"`** when sent as a JSON-RPC *request* to the
live ACP server (VERIFIED). In the ACP spec `session/cancel` is a **notification** (no `id`), so this
is very likely a framing issue rather than a missing feature — but **as a request it does not exist,
and an adapter that sends it with an `id` will get an error.** Whether it works as a notification is
**UNKNOWN** (not tested). The SDK exposes an `abort` event (`reason`) and `session.idle` carries
`aborted?`, so cancellation clearly exists somewhere in the surface. Interactively it is Ctrl+C /
Esc. **Do not guess the cancel path — test it before relying on it.**

### 6. Remote control — CLAIMED, and worth a look

`--remote` *"Enable remote control of your session from GitHub web and mobile"*; `--remote-export`
exports read-only; `--connect[=SESSION-ID]` connects to a remote session or task; `/delegate` sends
the session to GitHub to open a PR. *"require the remote sessions feature to be available on your
account."* Not tested. If it works, it is a free out-of-band supervision channel — the owner could
watch an overnight run from his phone.

---

## H. GUARDRAILS

### Permission model — VERIFIED, and it is the most granular in this scan

Two independent layers, and the docs are careful about the distinction:

**Layer 1 — tool *visibility* (what the model can see):**
`--available-tools [<tools>...]` (allowlist; disables everything else) and
`--excluded-tools [<tools>...]` (denylist). *"These filters decide which tools the model can see."*

**Layer 2 — tool *approval* (what runs without asking):**
`--allow-tool`, `--deny-tool`, `--allow-all-tools`. *"Denial rules always take precedence over allow
rules, **even `--allow-all-tools`**."* And, importantly, *"These flags control approval prompts and
do not expose tools that were filtered out by `--available-tools`/`--excluded-tools`."*

Pattern syntax is `kind(argument)`:

| Kind | Example | Semantics |
|---|---|---|
| `shell(command:*?)` | `shell(git:*)`, `shell(npm test)` | Wildcard matches the **stem**, so `shell(git:*)` matches `git push` but **not** `gitea`. Approval for `git`/`gh` is per first-level subcommand. |
| `write(path?)` | `write(.env)`, `write(/abs/path/.env)` | **A relative path matches by trailing path components** — `write(.env)` matches `.env` in *any* directory. Use an absolute path to scope to one location. |
| `read` | | Auto-approved in interactive sessions. |
| `url(domain-or-url?)` | `url(https://*.github.com)` | **Protocol-aware**: approving `https://example.com` does **not** allow `http://example.com`. Bare domains default to `https://`. |
| `memory` | | Storing new facts to persistent memory. |
| `<mcp-server>(tool?)` | `github(create_issue)` | Omit the tool to cover the whole server. |

Canonical combination from the CLI's own examples:
```bash
copilot --allow-tool='shell(git:*)' --deny-tool='shell(git push)'
```

Path gating: file access defaults to cwd + subdirectories + system temp dir. `--add-dir <directory>`
extends it (**and loads that directory's `.github/skills` and `.github/agents` as trusted config** —
note that side effect); `--allow-all-paths` disables verification; `--disallow-temp-dir` removes the
automatic temp grant.

Secrets: `--secret-env-vars [<vars>...]` strips named env vars from shell/MCP environments and
redacts them from output. `GITHUB_TOKEN` and `COPILOT_GITHUB_TOKEN` are **redacted by default**
(VERIFIED).

Persistence: approvals are saved per-location in `~/.copilot/permissions-config.json`, keyed by
**absolute path** (Git root for a repo; linked worktrees resolve to the main repo root and therefore
*share* permissions with it; submodules use their own directory). The schema is fully published —
`locations.<key>.tool_approvals[].kind` ∈ `commands, read, write, mcp, mcp-sampling, memory,
custom-tool, extension-management, extension-permission-access`. **An orchestrator can pre-seed this
file to grant exactly what a job needs without any prompt and without `--yolo`.** That is the right
unattended posture. Note the file *"doesn't support deny rules, 'ask' rules, default modes, URL rules,
tool filtering"* — those stay on the command line.

### Permission modes — VERIFIED

`defaultPermissionMode` ∈ `"manual"` (default: writes and commands prompt, reads auto-approve),
`"assisted"` (an LLM safety judge auto-approves what it judges safe), `"allow-all"`. Also
`--assisted-approval` / `COPILOT_ASSISTED_APPROVAL`, which *"Takes precedence over
`--allow-all-tools` when the judge engages; requires `--experimental` or
`enabledFeatureFlags.AUTO_APPROVAL`."*

Agent modes: `--mode <interactive|plan|autopilot>`, `--autopilot`, `--plan`, and
`--plan --mode autopilot` to *"auto-approve the plan and implement it autonomously."* For harnesses
that can only inject environment variables there is `COPILOT_PLAN_THEN_AUTOPILOT=1` — **which reads
like it was built for exactly this orchestrator's use case.**

### What it will do unattended without asking

With `--allow-all` / `--yolo` (`= --allow-all-tools --allow-all-paths --allow-all-urls`):
**everything.** The autopilot doc says it plainly: *"this gives the CLI permission to make any
changes it deems necessary to complete the task, including altering and deleting files."*

With autopilot but *without* full permissions: *"Copilot will automatically deny any tool requests
that require approval, which may prevent it from completing certain tasks."* — i.e. it degrades to
silent failure rather than blocking. **For an unattended run this is the worse outcome**, because the
job burns credits and produces nothing. Grant permissions properly (pre-seeded
`permissions-config.json` or explicit `--allow-tool` patterns) rather than relying on autopilot to
cope.

### Sandboxing — VERIFIED, experimental

Powered by **Microsoft Execution Containers (MXC)**. macOS backend is **Seatbelt (`sandbox-exec`)**,
so it works on this machine without extra installs. Linux needs `bwrap` 0.5.0+ plus `slirp4netns`,
util-linux 2.35+, `iptables`/`ip6tables` and `/dev/net/tun`.

Policy lives under the `sandbox` key in `settings.json`: `enabled`, `addCurrentWorkingDirectory`,
`allowDevToolAccess`, `allowBypass`, `auth.git` / `auth.gh`, `sandboxMcpServers` /
`sandboxLspServers`, `userPolicy.filesystem.{readwritePaths,readonlyPaths,deniedPaths}`,
`userPolicy.network.{allowOutbound,allowLocalNetwork}`,
`userPolicy.seatbelt.keychainAccess` (macOS).

Honest caveats the docs volunteer:
- *"the sandbox still inherits your shell environment apart from a fixed blocklist, so other
  credentials already present in your environment (for example `AWS_ACCESS_KEY_ID`) remain visible to
  sandboxed commands."*
- `allowDevToolAccess` (on by default) grants read access to `~/.npmrc`, `~/.m2/settings.xml` and
  similar — *"sandboxed commands can read those config files — including any registry tokens they
  hold."*
- *"Remote (HTTP/SSE) MCP servers are never sandboxed."*
- **Unattended landmine:** *"If sandboxing is already on when you start a session on a host that
  can't run it... every sandboxed shell command and every sandboxed MCP/LSP server fails."*

### The fail-closed enterprise-policy trap — VERIFIED ON THIS MACHINE

This is the most important operational finding in this section. Running the CLI unauthenticated in my
sandbox produced this in the process log:

```
[managedSettings] applied: bypass-permissions mode DISABLED by enterprise policy
  (fail-closed: policy could not be determined) — /allow-all and permission escalation are now blocked
```

There is no MDM policy on this device (`device MDM: no policy present on this device`) and no
enterprise. The block happened **because the policy could not be determined** — the server fetch was
skipped for want of an authenticated host. **The design is fail-closed: unknown policy ⇒ no
`--allow-all`.**

Implication for an unattended overnight run: **a network blip, an expired token, or a GitHub API
hiccup at startup can silently strip `--yolo` from a job**, and the session will then auto-deny
everything it cannot do unprompted. A mitigating changelog entry exists — *"Interactive `--yolo`
startup remains available before authentication when no managed policy evidence is present"* — but
the log above shows the fail-closed path is live. **An orchestrator must verify its permission
posture after launch (via `/permissions` state or the first `permission.requested` event) rather than
assuming the flag took.**

### Hooks as guardrails — VERIFIED

Events: `sessionStart`, `sessionEnd`, `userPromptSubmitted`, `userPromptTransformed`, `preToolUse`,
`postToolUse`, `postToolUseFailure`, `permissionRequest`, `preMcpToolCall`, `preCompact`,
`notification`, `agentStop`, `subagentStart`, `subagentStop`, `errorOccurred`.

Locations: `~/.copilot/hooks/`, repo `.github/hooks/*.json`, inline under the `hooks` key in
`settings.json` (user level) or `.github/copilot/settings.json` (repo level). Claude-format
PascalCase names and nested hook groups are accepted, with a published tool-name mapping
(`bash`→`Bash`, `view`→`Read`, `create`→`Write`, `edit`→`Edit`, `grep`→`Grep`, `glob`→`Glob`,
`task`→`Agent`).

Types: `command` (with `bash` / `powershell` / `command` / `exec` + `args`, `cwd`, `env`,
`timeoutSec` default **30**), `http` (POST JSON to a URL, with `headers` and `allowedEnvVars`),
`prompt` (auto-submit text).

**Read this limitation before designing around prompt hooks:** *"Prompt hooks... are only supported
on `sessionStart`... **They do not fire on resume, and they do not fire in non-interactive prompt
mode (`-p`).**"* So a prompt hook is a *seeding* mechanism for a fresh interactive session, **not** a
mid-run injection channel. Mid-run injection is §G's steering/queueing.

Hardening details worth knowing: hook output is **bounded at 10 MiB per invocation**; a
`preToolUse` hook exiting with **code 2 denies** the call; *"preToolUse hook errors now deny the tool
call instead of silently allowing execution"*; hooks can receive the current OTel `traceparent` and
emit correlated spans; `disableAllHooks` kills every hook; an `allowManagedHooksOnly` policy exists
for enterprises.

### Secure-by-default in `-p` mode — VERIFIED, and easy to trip over

In prompt mode, repository-controlled configuration is **off by default** and must be opted into:

| Variable | Set to `true` to… |
|---|---|
| `GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS` | load repository hooks in `-p` |
| `GITHUB_COPILOT_PROMPT_MODE_WORKSPACE_MCP` | load workspace MCP sources in `-p` |
| `GITHUB_COPILOT_PROMPT_MODE_EXTENSIONS` | load project extensions / extension-management tools in `-p` |

*"Repository hooks also load automatically when the folder is already trusted or `COPILOT_ALLOW_ALL`
is set."* And `COPILOT_ALLOW_ALL` has a subtlety the help text spells out precisely: setting it to
**exactly `"true"`** *"additionally trusts the working directory without prompting, which loads that
directory's skills, plugins, MCP servers, and hooks, including hooks that run shell commands; the
other truthy spellings (`1`, `yes`, `on`, `y`) only auto-approve tools."*

**That is a real security cliff: `COPILOT_ALLOW_ALL=true` executes repo-controlled shell code;
`COPILOT_ALLOW_ALL=1` does not.** An orchestrator must choose the spelling deliberately and document
why.

---

## I. EXTENSIBILITY

### MCP — VERIFIED, first-class

Config sources and precedence: user `~/.copilot/mcp-config.json`; workspace `.mcp.json` or
`.github/mcp.json` (**workspace wins on name conflict**); plugin-contributed.

```bash
copilot mcp add <name> -- <command> [args...]            # stdio (default)
copilot mcp add --transport http <name> <url>            # http | sse
copilot mcp list | get <name> | remove | enable | disable
#   --env KEY=VALUE   --header "Authorization: Bearer …"   --tools "*"|"a,b"|""   --timeout <ms>   --json
```

Per-run overrides: `--additional-mcp-config <json|@file>` (repeatable, later wins, augments the user
config, `~/` expands, relative `@` paths resolve against the **session working directory**),
`--disable-mcp-server <name>`, `--enable-mcp-server <name>` (this run only, nothing persisted),
`--disable-builtin-mcps`.

**GitHub's own MCP server ships enabled by default** with a curated subset of tools; widen it with
`--enable-all-github-mcp-tools`, `--add-github-mcp-toolset <toolset|all>`, `--add-github-mcp-tool
<tool|*>`. There is also `--allow-all-mcp-server-instructions` (by default only allowlisted servers'
initialization instructions reach the system prompt — a prompt-injection control worth keeping on).

Over ACP, *"ACP clients can now provide MCP servers (stdio, HTTP, SSE) when starting or loading
sessions"* — `session/new` takes an `mcpServers` array (VERIFIED: omitting it returns
`"mcpServers": {"_errors": ["Invalid input: expected array, received undefined"]}`).

### Skills, agents, instructions, plugins — VERIFIED

**Skills** (`SKILL.md` per subdirectory) are discovered from `.github/skills/`, `.agents/skills/`,
**`.claude/skills/`** (!), `~/.copilot/skills/`, `~/.agents/skills/`, plugins, and
`copilot skill add <file|url|directory>`. `COPILOT_SKILLS_DIRS` adds more.

**That `.claude/skills/` discovery path is a material finding for this repo.** The owner's existing
GSD/harness skill corpus is authored as `.claude/skills` — **Copilot CLI reads that directory
directly.** A GSD-style workflow engine could plausibly run inside Copilot with no port. *Whether the
frontmatter and tool vocabulary are compatible enough for GSD to actually execute is* **UNKNOWN** *and
is the highest-value follow-up experiment in this profile.*

**Custom agents**: `.agent.md` files in `.github/agents/` (project, wins) or `~/.copilot/agents/`
(personal). Selected with `--agent <agent>` or `/agent`. Per-subagent model/effort/contextTier via
`subagents.agents.<agent-name>` (each field can be `"inherit"`). Since 1.0.86, agents can opt into
repo instruction files with `include-custom-instructions: true` in frontmatter — and the recognised
set is **`AGENTS.md`, `copilot-instructions.md`, and `CLAUDE.md`** (VERIFIED). Copilot reads
`CLAUDE.md`.

**Instructions**: `~/.copilot/copilot-instructions.md` (global), `~/.copilot/instructions/*.instructions.md`,
repo `.github/copilot-instructions.md`, plus `COPILOT_CUSTOM_INSTRUCTIONS_DIRS`. Disable with
`--no-custom-instructions`. Inspect the resolved set with `copilot instruction list` or `/instructions`.

**Plugins**: `copilot plugin install|uninstall|update|list|enable|disable`, plus
`copilot plugin marketplace browse <name>`. Two marketplaces ship by default — `copilot-plugins`
(`github/copilot-plugins`) and `awesome-copilot` (`github/awesome-copilot`). Local development via
`--plugin-dir <directory>` (repeatable). Plugins can bundle skills, agents, hooks, MCP servers and
LSP servers, and expand `${PLUGIN_ROOT}`.

**Extensions**: `~/.copilot/extensions/`, with `--extension-sdk-path` to override the bundled
`@github/copilot-sdk` injected into extension subprocesses — i.e. extensions are themselves SDK
clients.

**LSP**: `~/.copilot/lsp-config.json` or repo `.github/lsp.json`; servers are *not* bundled.
Inspect with `copilot lsp list` or `/lsp`.

### BYOK — VERIFIED, and strategically important

Setting `COPILOT_PROVIDER_BASE_URL` switches the CLI off GitHub's model routing entirely, and
**GitHub authentication is then not required**. Supported types: `openai` (default — covers Ollama,
vLLM, Foundry Local), `azure`, `anthropic`. Wire APIs `completions` (default) or `responses`;
transports `http` or `websockets`.

```bash
COPILOT_PROVIDER_TYPE=anthropic \
COPILOT_PROVIDER_BASE_URL=https://api.anthropic.com \
COPILOT_PROVIDER_API_KEY=sk-ant-… \
COPILOT_MODEL=claude-sonnet-4-20250514 \
copilot
```

**This is the same environment-variable trick the field scan found for Xiaomi MiMo** — which means
Copilot CLI is *also* a generic front-end for the owner's MiMo/Kimi/GLM endpoints, not only for
GitHub's models. `COPILOT_PROVIDER_API_KEY_COMMAND` runs a shell command to mint a **fresh key per
request** (for short-lived credentials), and `COPILOT_PROVIDER_HEADERS` injects gateway/tenant
headers. A `providers.json` registry (`COPILOT_PROVIDERS_CONFIG`, default
`<COPILOT_HOME>/providers.json`) supersedes the env vars when present.

`COPILOT_OFFLINE=true` skips **all** network access — auth, telemetry, web tools, GitHub MCP,
auto-update — and requires a local provider. That is a genuinely airtight offline mode.

Caveat for an orchestrator: *"BYOK re-authentication — API keys aren't persisted"* on session resume
(VERIFIED); the mitigation is to re-supply them on every resume. And `continueOnAutoMode` *"does not
apply to... BYOK providers."*

### Model catalogue — VERIFIED (from `copilot help config`, 2026-09-19)

`claude-sonnet-5`, `claude-fable-5.1`, `claude-fable-5`, `claude-opus-5`, `claude-opus-4.8`,
`claude-opus-4.8-fast`, `claude-opus-4.7`, `claude-sonnet-4.6`, `claude-haiku-4.5`, `gpt-6-astra`,
`gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`,
`gpt-5.3-codex`, `gpt-5-mini`, `mai-code-1.1-flash`, `gemini-3.8-flash`, `gemini-3.7-flash`,
`gemini-3.6-flash`, `gemini-3.5-flash`, `grok-4.5`, `kimi-k3`, `kimi-k2.7-code`.

**Strategic note for the rebuild:** the field scan treats Claude, Gemini, Kimi and GPT as separate
*platforms* requiring separate adapters. Copilot CLI reaches **all of them through one adapter, one
account and one quota**. If the orchestrator's goal is model diversity rather than account diversity,
Copilot collapses most of the adapter matrix. `--model auto` with `--auto-tier
<efficiency|balance|intelligence>` delegates the choice; `--reasoning-effort
<none|minimal|low|medium|high|xhigh|max>` and `--context <default|long_context>` tune it. Model
precedence is published: custom agent → `--model` → `COPILOT_MODEL` → `settings.json` → default.

### Can a GSD-style, subagent-heavy engine run inside it? — probably, with caveats

For: `.claude/skills/` and `CLAUDE.md` are read natively; subagents are first-class
(`--agent`, `subagent.*` events, `COPILOT_SUBAGENT_MAX_CONCURRENT=32`, depth 4); `--fleet` gives
parallel orchestration; hooks cover the lifecycle; MCP is fully wired.
Against: subagent *depth* defaults to 4 and *concurrency* to 32, so a deeply nested engine needs
tuning; `--fleet` is **not supported in ACP mode**; and skill/agent frontmatter compatibility with
GSD is **UNKNOWN**.

---

## J. OPERATIONAL REALITY

### Cost model — VERIFIED

Two billing platforms coexist:
- **Current: AI credits.** *"Each time you interact with Copilot in Copilot CLI's interactive
  interface, or use Copilot CLI programmatically, AI credits are consumed based on the number of
  tokens processed."* Per-model pricing shown in `/model` as per-token input / cached-input / output
  costs; readable programmatically via `models.list`.
- **Legacy: premium requests.** The package README still says *"Each time you submit a prompt to
  GitHub Copilot CLI, your monthly quota of premium requests is reduced by one."* Per-model
  multipliers apply.

Which platform the owner's account is on is **UNKNOWN** — `account.getQuota` answers it in one call.
An active Copilot subscription is required (CLAIMED, README), and an org/enterprise admin can disable
Copilot CLI entirely by policy.

**The cost shape that matters for an overnight queue:** autopilot spends without human involvement,
and *"Hidden model work such as compaction counts toward `--max-ai-credits`."* Defend with
`--max-ai-credits` (min 30) **and** `--max-autopilot-continues` (default 5) — they cap different
things, and both are needed.

### Maturity — VERIFIED

| Signal | Value |
|---|---|
| Version | 1.0.86, released 2026-09-17 |
| First publish | 2025-09-25 (~12 months old) |
| Versions published | **835** |
| Changelog entries | 172 dated releases |
| Recent cadence | 1.0.83 (Sep 4) → 1.0.85 (Sep 16) → 1.0.86 (Sep 17) — **near-daily** |
| Repo | `github/copilot-cli`, **11,184 stars**, pushed 2026-09-18, not archived |
| Open issues | **2,343** |
| License | proprietary — `"SEE LICENSE IN LICENSE.md"`, GitHub API reports `NOASSERTION` |
| ACP support | **public preview and subject to change** (docs say so explicitly) |
| SDK RPCs `session.usage.getMetrics`, `session.metadata.contextInfo`, `recomputeContextTokens` | **experimental** (`GHCP001` in .NET) |

The repo README's own framing: *"We're still early in our journey"*, *"We're building quickly. Expect
frequent updates."*

**Read the star count correctly.** 11k stars against OpenCode's 208k and DeepSeek Harness's 229k
looks small — but this is a *closed-source* CLI whose repo exists mainly for issues and releases. The
1,600+ issues-per-year rate and 835 releases are the real engagement signal. Do not rank it by stars.

### Install footprint — VERIFIED on this machine

```
@github/copilot                     4 files,  12,968 bytes unpacked   (a loader + optionalDependencies)
@github/copilot-darwin-arm64        1 Mach-O binary, 149,952,304 bytes  (145 MB)
```

The npm package is a thin `npm-loader.js` that `spawnSync`s the platform binary; eight platform
packages exist (`linux-x64/arm64`, `linuxmusl-x64/arm64`, `darwin-x64/arm64`, `win32-x64/arm64`).
Bundled: ripgrep, and **tgrep** (Microsoft's trigram-indexed search, auto-enabled inside a git repo
above **50,000 files** on this platform). Install took **~2 minutes** on this machine.

Install routes: `curl -fsSL https://gh.io/copilot-install | bash` (honours `PREFIX` and `VERSION`),
`brew install copilot-cli` (or `copilot-cli@prerelease`), `winget install GitHub.Copilot`,
`npm install -g @github/copilot` (or `@prerelease`).

Node requirement: the npm loader needs Node (the binary bundles **Node v24.20.0** internally —
VERIFIED from the process log); `engines` is unset in package.json.

### Current state on this machine — VERIFIED

| Fact | Value |
|---|---|
| Binary on PATH | **No** (`which copilot` → not found) |
| `~/.copilot/` | exists, **8 KB total** |
| `~/.copilot/config.json` | `{"firstLaunchAt": "2026-08-11T09:30:12.931Z"}` only |
| `~/.copilot/logs/` | one file, `process-1789304552095-73204.log`, last touched **2026-09-13 21:20** |
| `~/.copilot/session-state/` | **absent** — no session has ever been completed under this HOME |
| What the log shows | a **78-minute** `--server --stdio` run on 2026-09-13, graceful shutdown, `Destroying 0 active sessions` |

So: tried in August, the SDK/server control plane was exercised in September, no local sessions
persisted, binary since removed or never placed on PATH. **It is an install away, and the hard part
has already been run once.**

### Known unattended-run failure modes

Ranked by how likely they are to ruin an overnight run:

1. **Fail-closed policy strips `--allow-all`** (VERIFIED on this machine, §H). A startup-time network
   or auth hiccup silently disables permission escalation; autopilot then auto-denies everything it
   cannot do and the job burns credits producing nothing.
2. **Auto-update mid-flight.** Auto-update is **on by default** and *"a downloaded version applies at
   your next launch"* — so a long queue can silently change CLI versions between jobs. **Pin it:**
   `COPILOT_AUTO_UPDATE=false` or `--no-auto-update` (also `--prefer-version`). It is off by default
   in CI, detected via `CI`, `BUILD_NUMBER`, `RUN_ID`, `SYSTEM_COLLECTIONURI` — **an orchestrator can
   simply set `CI=1`.**
3. **No session locking** (VERIFIED, §B). Two workers on one `sessionId` is undefined behaviour and
   the platform will not stop them. The orchestrator must hold the lock.
4. **Bare `--resume` needs a TTY** and hard-errors under `-p`/non-TTY when multiple sessions exist
   (VERIFIED, §B). Always pass an explicit id.
5. **Sandbox-bypass cannot be auto-approved** (VERIFIED, §G). With the sandbox on, any command that
   must leave it stalls.
6. **Prompt hooks don't fire on resume or under `-p`** (VERIFIED, §H) — a seeding mechanism people
   will mistake for an injection mechanism.
7. **`COPILOT_ALLOW_ALL=true` vs `=1` differ in whether repo-controlled hooks execute** (VERIFIED,
   §H). Getting this wrong runs untrusted shell code from a repo.
8. **Soft credit cap overshoots.** *"A response can therefore exceed or exhaust the limit before the
   CLI can observe that it has done so"* (VERIFIED, §E).
9. **Ephemeral events are not replayed on resume** (VERIFIED, §C). A supervisor reconnecting must
   pull state by RPC.
10. **Background shells outlive turns.** `COPILOT_TASK_WAIT_TIMEOUT_SECONDS` (default **600**; `0`
    exits immediately) governs how long `-p` waits for pending background agents or shell commands
    before exiting. A dev server left running will hold a job for 10 minutes by default.
11. **OTLP export silently disabled over plaintext http://.** *"export is disabled rather than sent
    in cleartext; startup is not aborted... it surfaces only as a warning in the process log... and
    `--log-level error` or `none` suppress that warning, leaving no signal at all."* (VERIFIED.) If
    the orchestrator relies on OTel for progress, use the **file exporter**, not `http://localhost:4318`.
12. **macOS Keychain prompt on first use per account** — the token is stored in the system credential
    store. Not verified for Copilot specifically, but the same class of hazard the field scan flagged
    for Claude Code. **Sidestep it entirely by using `COPILOT_GITHUB_TOKEN` in the environment**, which
    never touches the Keychain.

### Is it plausible to run overnight unattended today?

**Yes — and it is the most plausible candidate this scan has produced.** The recommended posture:

```bash
CI=1 \
COPILOT_AUTO_UPDATE=false \
COPILOT_HOME=/path/to/account-profile \
COPILOT_GITHUB_TOKEN=<account token> \
COPILOT_ENABLE_INTERRUPTED_SESSION_RESTORE=1 \
COPILOT_OTEL_FILE_EXPORTER_PATH=/path/to/run.otel.jsonl \
COPILOT_TASK_WAIT_TIMEOUT_SECONDS=120 \
copilot -p "$PROMPT" \
  --session-id "$UUID" \
  --model gpt-5.4 \
  --output-format json \
  --usage-output-file "$RUNDIR/usage.json" \
  --share "$RUNDIR/transcript.md" \
  --allow-tool='write, shell(git:*), shell(npm:*)' \
  --deny-tool='shell(git push)' \
  --no-ask-user \
  --max-ai-credits 200 \
  --max-autopilot-continues 10 \
  --secret-env-vars='MY_SECRET,OTHER_KEY' \
  --no-auto-update
```

…with a `permissionRequest` HTTPS hook pointing at the supervisor, a `preCompact` hook for compaction
receipts, a `notification` hook matching `elicitation_dialog|permission_prompt`, and a periodic
`account.getQuota` poll from a long-lived `copilot --server --port N` (with `COPILOT_CONNECTION_TOKEN`
set) to decide when to pause the queue.

Every flag above is quoted verbatim from `--help` or the official reference. **None is guessed.**

---

## What this costs the orchestrator

### What comes free (no adapter work beyond wiring)

| Capability | Mechanism |
|---|---|
| Named sessions before they exist | `--session-id <uuid>` |
| Exact resume | `--resume=<uuid>` |
| Structured output | `--output-format json` |
| Remaining quota + reset date | `account.getQuota` |
| Per-account isolation | `COPILOT_HOME`, `COPILOT_GITHUB_TOKEN` |
| Live context fullness | `session.usage_info` |
| Compaction receipts | `session.compaction_complete`, `preCompact` hook |
| Programmatic permission answers | `permissionRequest` hook (HTTP) or `onPermissionRequest` |
| Programmatic answers to the agent's questions | `user_input.requested` / `.completed` |
| Mid-turn steering | `session.send({mode:"immediate"})` |
| In-band budget stop the orchestrator can resolve | `session_limits_exhausted.*` |
| Uniform telemetry | `COPILOT_OTEL_FILE_EXPORTER_PATH` |
| Machine stays awake | `keepAlive: "on"` |
| Cross-model reach | one adapter → Claude, GPT, Gemini, Grok, Kimi, MAI |

### What the orchestrator must build

| Cost | Why | Rough size |
|---|---|---|
| **A second protocol adapter** | ACP and the SDK runtime server are **different protocols** on the same binary. ACP is an open standard reusable across agents; the SDK RPC surface (`account.getQuota`, `session.usage.getMetrics`, `session.metadata.contextInfo`) is Copilot-specific and **is where the quota answer lives**. Choosing only ACP forfeits axis E; choosing only the SDK forfeits protocol reuse. | Realistically **both** — ACP for launch/prompt/permission, SDK server for quota and context RPCs. Two clients, ~1 module each. |
| **Session locking** | *"No session locking — concurrent access to same session is undefined."* | Small, but non-negotiable. |
| **Permission-posture verification after launch** | The fail-closed policy path can strip `--allow-all` silently. | Small: assert once per job. |
| **State re-pull on reconnect** | Ephemeral events are not replayed. | Small: call `contextInfo` + `getMetrics` on attach. |
| **Account-switch context re-seed** | A running session's account cannot change; separate `COPILOT_HOME`s do not share `session-state/`. | One compaction-summary-sized re-prompt per switch, or an untested symlink hack. |
| **`--output-format json` schema discovery** | Undocumented. One authenticated run captures it. | 15 minutes, once. |
| **`--usage-output-file` and statusline JSON schemas** | Both undocumented. | 15 minutes, once. |
| **Cancel path verification** | `session/cancel` is not a request method; the notification form is untested. | 15 minutes, once. |
| **Version pinning discipline** | Near-daily releases against a *public-preview* protocol and *experimental* RPCs. The SDK docs say it outright: *"Pin both the SDK and the Copilot CLI runtime if your application depends on them."* | Ongoing. Pin with `--prefer-version` / `VERSION=` at install. |

### Where it is unsupported, and what the workaround costs

| Axis | Gap | Closest workaround | Cost |
|---|---|---|---|
| D | No RPC to command compaction | Send `/compact` as an ACP prompt | None — supported and documented. |
| D | No custom-summariser hook | `/compact <focus instructions>`, or a custom `isTerminal` tool wrapping `history.clearContext` | The `clearContext` route needs the **model** to call the tool; the orchestrator can only make it available and nudge. |
| F | Running session's account is fixed | Close + reopen on the other account | One context re-seed. |
| G | `session/cancel` not a request | Kill the process; resume by `--session-id` | Loses an in-flight turn's work. |
| E | No structured reset-time on a rate-limit error | `account.getQuota` → `resetDate`; or parse the message text | Poll instead of react. Cheap. |
| E | REST billing API gives consumed, not remaining | Don't use it | None — `getQuota` is strictly better. |
| B | Crash restore is an opt-in startup **dialog** | `COPILOT_ENABLE_INTERRUPTED_SESSION_RESTORE=1`, or relaunch with the recorded `--session-id` | The relaunch path is more predictable headless; prefer it. |

### The honest bottom line

Copilot CLI scores higher against this contract than anything else in the scan so far, and it does so
on the two axes the owner called non-negotiable and that nothing else answers cleanly: **reading
remaining quota with a reset date**, and **answering a session's own question programmatically**.
Per-session `gitHubToken` on a shared runtime is a better answer to axis F than the owner's existing
profile-switcher machinery, because it needs no process-per-account.

The three things that should temper enthusiasm: the whole control-plane story rests on a
**public-preview protocol** and **experimental RPCs** that ship **near-daily**; the binary is
**145 MB** and **not currently installed**; and there is a **fail-closed policy path, observed on this
machine, that can silently disable the permission posture an unattended run depends on**. The first
is managed by pinning, the second is a one-time cost, and the third must be actively asserted after
every launch rather than assumed.

---

## Open questions for a follow-up pass

| # | Question | Axis | How to answer |
|---|---|---|---|
| 1 | Exact JSONL event schema of `--output-format json` | A, C | One authenticated `-p` run, capture stdout |
| 2 | Exact JSON schema of `--usage-output-file` | E | Same run, read the file |
| 3 | Exact JSON the `statusLine` command receives on stdin — does it carry quota as well as context? | D, E | Install a `statusLine` script that `cat`s stdin to a file |
| 4 | Does `session/cancel` work as an ACP **notification** (no `id`)? | G | One ACP session, send it mid-turn |
| 5 | Does `session.send("/compact")` work over the SDK server, and does it emit `command.queued`? | D | One SDK session |
| 6 | Does the owner's `gho_` gh token carry Copilot entitlement, and which billing platform is he on? | E, F | `GH_TOKEN=$(gh auth token)` + one `account.getQuota` call |
| 7 | Can two `COPILOT_HOME`s share `session-state/` by symlink, giving cross-account resume? | B, F | Symlink + resume test |
| 8 | Do the owner's existing `.claude/skills` GSD skills actually **execute** under Copilot, not just get discovered? | I | `copilot skill list` in this repo, then invoke one |
| 9 | Does `COPILOT_ENABLE_INTERRUPTED_SESSION_RESTORE=1` degrade gracefully under `-p` (no TTY)? | B | Kill a `-p` run mid-turn, relaunch |
| 10 | Does `--remote` / `--connect` work on this account, and can a supervisor use it as an out-of-band channel? | G | `copilot --remote` once |

---

## Sources

All retrieved or run on **2026-09-19** unless otherwise dated.

### Run on this machine (primary, VERIFIED)

| Source | What it gave |
|---|---|
| `copilot --help` (v1.0.86, isolated sandbox) | the complete flag surface quoted throughout |
| `copilot help limits \| billing \| environment \| config \| permissions \| sandbox \| providers \| logging \| monitoring \| commands` | all verbatim help-topic text |
| `copilot sessions\|login\|memories\|plugin\|mcp\|skill\|instruction\|lsp --help` | subcommand surfaces |
| `copilot --acp --stdio` + live JSON-RPC `initialize` | real `agentCapabilities`, `agentInfo`, `authMethods` |
| ACP method probe by error code (`-32601` vs `-32602`) | which methods exist; Zod param schemas for `session/new`, `session/load`, `session/set_mode`, `session/set_model`, `session/prompt` |
| `copilot --server` / `--server --stdio` | the hidden server flags; `COPILOT_CONNECTION_TOKEN` warning; TCP port binding |
| `copilot --acp --stdio --port 3000` | mutual-exclusion error text |
| Unauthenticated `copilot -p` | exit code 1; the fail-closed managed-policy log lines |
| `~/.copilot/config.json`, `~/.copilot/logs/process-1789304552095-73204.log` | the owner's 2026-08-11 first launch and 2026-09-13 78-minute server-mode run |
| `npm view @github/copilot --json` | version, dates, `bin`, `optionalDependencies`, dist metadata |
| `gh api repos/github/copilot-cli` | stars, pushed_at, open issues, license |
| `gh api /users/{u}/settings/billing/usage` | 404 + `documentation_url` proving the endpoint and its required `user` scope |
| `gh auth status` | the owner's `gho_` GitHub CLI OAuth token |

### Official documentation source (primary, VERIFIED — read as raw Markdown from `github/docs`)

| Path in `github/docs` | Used for |
|---|---|
| `content/copilot/reference/copilot-cli-reference/cli-command-reference.md` | flags, slash commands, env vars, permission patterns, OTel, session restore |
| `content/copilot/reference/copilot-cli-reference/cli-config-dir-reference.md` | `~/.copilot` layout, `session-state/events.jsonl`, `permissions-config.json` schema, `COPILOT_HOME` precedence, settings keys |
| `content/copilot/reference/copilot-cli-reference/cli-programmatic-reference.md` | programmatic flags, tool kinds, model precedence |
| `content/copilot/reference/copilot-cli-reference/acp-server.md` | ACP transports, server-fixed options, slash commands over ACP, `available_commands_update` |
| `content/copilot/reference/hooks-reference.md` | all hook events, `permissionRequest` / `preToolUse` / `agentStop` decision control, `preCompact` payload, notification types, prompt-hook limits |
| `content/copilot/how-tos/copilot-cli/automate-copilot-cli/run-cli-programmatically.md` | `-p` patterns, CI example |
| `content/copilot/concepts/agents/copilot-cli/context-management.md` | 80%/95% thresholds, checkpoints, `/context` breakdown |
| `content/copilot/concepts/agents/copilot-cli/autopilot.md` | autopilot semantics, `--max-autopilot-continues`, permission trade-offs |
| `content/copilot/how-tos/copilot-sdk/features/usage-and-billing.md` | **`account.getQuota` field table**, `session.usage_info`, `session.metadata.contextInfo` |
| `content/copilot/how-tos/copilot-sdk/features/streaming-events.md` | the full session-event taxonomy incl. `user_input.*`, `session_limits_exhausted.*`, `session.compaction_complete` |
| `content/copilot/how-tos/copilot-sdk/features/steering-and-queueing.md` | `mode: "immediate"` / `"enqueue"`, `MessageOptions` |
| `content/copilot/how-tos/copilot-sdk/features/session-persistence.md` | `infiniteSessions`, no-session-locking, BYOK re-auth |
| `content/copilot/how-tos/copilot-sdk/features/context-management.md` | `history.clearContext` restrictions, `isTerminal` |
| `content/copilot/how-tos/copilot-sdk/features/agent-loop.md` | `session.idle` vs `session.task_complete`, the autopilot nudge |
| `content/copilot/how-tos/copilot-sdk/features/session-limits.md` | `session_limits_exhausted.*` payloads |
| `content/copilot/how-tos/copilot-sdk/setup/multi-tenancy.md` | **per-session `gitHubToken`**, `mode: "empty"`, `baseDirectory` |
| `content/copilot/how-tos/copilot-sdk/setup/local-cli.md`, `bundled-cli.md` | stdio transport, `COPILOT_CLI_PATH` |
| `content/rest/billing/usage.md` | user vs org vs enterprise billing scope |

### Repo and package sources

- `github/copilot-cli` — `changelog.md` (3,208 lines, 172 dated releases, read in full for the axes above) and `README.md`, retrieved 2026-09-19. Repo pushed 2026-09-18.
- npm `@github/copilot@1.0.86` (published 2026-09-17) and `@github/copilot-darwin-arm64@1.0.86`.

### Secondary (CLAIMED)

- `docs.github.com/en/copilot/concepts/agents/about-copilot-cli` (rendered) — billing framing, the "95% compression" line.
- `docs.github.com/en/rest/billing/usage` (rendered) — the four user-level billing endpoints and their response fields.
- Package README marketing claims (premium-request-per-prompt, "same agentic harness as Copilot coding agent").

### Not covered here

Orchestrators that *manage* agents — see `orchestrator-landscape.md`, referenced by the task. The
field scan at `00-field-scan.md` records that this file was absent at the stated path when that scan
ran; it was still absent today.
