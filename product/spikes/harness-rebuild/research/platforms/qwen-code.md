# Platform profile — Alibaba Qwen Code (`@qwen-code/qwen-code`)

**Date of pass:** 2026-09-19. **Version examined:** **0.24.1**, published 2026-09-19T08:28:42Z — the
same day as this pass. **Machine:** owner's Mac (darwin 25.5.0).

**Evidence tags:** **VERIFIED** — read in shipped source, read in docs shipped inside the package, or
run on this machine. **CLAIMED** — asserted by a README/vendor page only. **UNKNOWN** — could not be
established.

---

## 0. Method, and why this pass has unusually good evidence

Qwen Code is **not installed on this machine** (VERIFIED: no `qwen` on PATH; `~/.qwen` does not
exist; `ls ~/.claude ~/.codex ~/.gemini ~/.config` shows no Qwen config anywhere). Nothing of the
owner's was modified and no agent run was started.

So I installed 0.24.1 into an isolated sandbox and ran it with a **fake `HOME`** so that even
`--help` could not create `~/.qwen`:

```
/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/qwen-sandbox
  node_modules/@qwen-code/qwen-code/     ← 124 MB unpacked
  fakehome/                              ← HOME for every invocation
```

Two things make this profile much better evidenced than a docs-only pass:

1. **The package ships its own full documentation** — 111 Markdown files under
   `node_modules/@qwen-code/qwen-code/bundled/qc-helper/docs/`, including `qwen-serve.md` (1247
   lines), `features/hooks.md` (1750), `configuration/settings.md` (1019),
   `features/cross-session-protocol.md`, `features/dual-output.md`, `features/headless.md`. These
   are vendor docs versioned *with the binary*, not a website that may have drifted.
2. **The bundle is not minified.** `chunks/server-PN5WV25I.js` and friends retain original source
   paths (`// packages/cli/src/serve/acp-http/json-rpc.ts`) and readable identifiers. Every route
   and shape below was read from the code that actually ships, not inferred.

Where the shipped docs and the shipped code disagree, I say so and **trust the code** (see §G).

### Two corrections to this workflow's starting assumptions

- **"Free-tier quotas" is out of date.** The Qwen OAuth free tier was **discontinued on
  2026-04-15** (VERIFIED, `docs/configuration/auth.md`): *"Qwen OAuth is no longer a selectable
  dialog entry — its free tier was discontinued on 2026-04-15."* There is no free path today. Qwen
  Code is a paid-API or subscription tool.
- **"Fork lineage from Gemini CLI" badly understates what this is now.** The Gemini-CLI bones are
  still visible (yargs layout, `settings.json` shape, `--sandbox` seatbelt profiles). But 0.24.1
  ships an HTTP control-plane daemon, a documented cross-process messaging protocol with minted
  controller tokens, a dual-output injection channel, subagents, skills, workflows, hooks with 20
  events, an agent board, and chat-platform channels. **On the orchestrator contract it is the
  strongest platform surveyed in this spike so far** — stronger than pi, and it is the only one that
  answers axis D completely.

---

## A. LAUNCH

**Both modes, well separated. Structured output in three shapes. VERIFIED (ran `--help`).**

### Headless

```
qwen [query..]                      # positional prompt, defaults to one-shot
-p, --prompt <text>                 # DEPRECATED in 0.24.1 — "Use the positional prompt instead"
-i, --prompt-interactive <text>     # run the prompt, then stay interactive
-o, --output-format text|json|stream-json
    --input-format  text|stream-json
    --include-partial-messages
    --json-schema <json|@path.json>
```

`--prompt` still works but the help text marks it deprecated. An orchestrator writing new code
should pass the prompt positionally.

`--output-format json` buffers and emits **one JSON array** of `system` / `assistant` / `result`
objects; `stream-json` emits the same objects as JSONL as they happen. The terminal `result` object
carries `is_error`, `duration_ms`, `result`, `usage` and a `stats` block with
`stats.models[].tokens.total`, `stats.tools.totalCalls` and `stats.tools.byName` (VERIFIED, docs +
`buildSessionStatsStatus` in `chunks/acpAgent-ANIVCBU3.js`).

`--json-schema` *"Registers a synthetic `structured_output` tool; the session ends on the first valid
call"* — a real machine-readable completion contract, not prompt-begging (VERIFIED, `--help`).

### Visible terminal the owner can attach to and type into

The TUI is the default (`qwen` with no `-p`). Critically, a TUI session is **not** opaque to a
supervisor — see axis C (`--json-file`) and axis G (`--input-file`). This is the combination the
owner wants: a window he can take over, that a supervisor can still read and drive.

### Daemon

```
qwen serve [--port 4170] [--hostname 127.0.0.1] [--token …] [--workspace <abs path>]
           [--no-web] [--require-auth] [--max-sessions 32]
```

One HTTP + SSE daemon hosting many sessions, plus a browser Web Shell at `/`. See axes B, C, D, G.

### Run-level budgets (unique, and directly useful)

```
--max-wall-time 90|30s|5m|1h|1.5h   # exit 55
--max-tool-calls <n>                # exit 55
--max-session-turns <n>             # exit 53
```

Exit codes are deliberately distinct — **53** turn cap, **55** budget exceeded
(`FatalBudgetExceededError`), **130** SIGINT — *"so CI scripts can branch on the reason"* (VERIFIED,
`docs/features/headless.md`). No other platform in this spike offers a wall-clock kill switch as a
first-class flag.

**Two documented traps.** `--max-tool-calls` counts **top-level** dispatches only: an `agent`
(subagent) call counts as 1 and its inner tool calls are uncounted, so *"a model that funnels work
through subagents can do unbounded inner work under a small top-level budget"*. And
`structured_output` is exempt from `--max-tool-calls` unconditionally, so a malformed-output retry
loop is **not** bounded by it. Pair with `--max-session-turns` / `--max-wall-time` (VERIFIED, same
doc).

---

## B. IDENTITY & RESUME

**The orchestrator can name a session before it exists, on both the CLI and the daemon, and the
daemon protocol verifies the id it got back. This is the strong half of the field.**

### Assigning an id

- CLI: `--session-id <id>` — *"Specify a session ID for this run."* (VERIFIED, `--help`)
- Daemon: `POST /session` accepts a `sessionId` in the body. The official SDK then **checks the echo
  and throws on mismatch** (VERIFIED, `chunks/chunk-JDS6RRHY.js`):

```js
if (typeof req.sessionId === "string" && session.sessionId !== req.sessionId.toLowerCase()) {
  throw new DaemonSessionIdProtocolError(req.sessionId.toLowerCase(), session.sessionId);
}
```

Note the **`.toLowerCase()`** — ids are canonicalised to lower case. An orchestrator that mints
mixed-case ids and then indexes on its own spelling will mis-key. Mint lower-case.

### Resuming

```
-c, --continue                # most recent session for this project
-r, --resume [sessionId]      # exact session; bare -r opens a picker (interactive only)
    --fork-session            # resume into a NEW session instead of appending
    --chat-recording          # if false, --continue/--resume DO NOT WORK
```

Headless resume is explicitly supported: `qwen --resume <uuid> -p "Apply the follow-up refactor"`
(VERIFIED, `docs/features/headless.md`). Restores *"conversation history, tool outputs, and
chat-compression checkpoints before sending the new prompt."*

Daemon-side: `POST /session/:id/load` (cold reconnect, returns a bounded replay snapshot),
`POST /session/:id/resume` (*"Model context is restored on the agent side without UI replay"*),
`POST /session/:id/fork`, `POST /session/:id/branch`, `POST /session/:id/rewind` +
`GET /session/:id/rewind/snapshots` (VERIFIED, routes read from `chunks/server-PN5WV25I.js`).

### Listing

```
qwen sessions list          # persisted sessions      → ran it: "No sessions found."
qwen sessions ps            # sessions running NOW    → ran it: "No Qwen Code sessions are registered right now."
qwen sessions controllers   # see axis G
```

Both ran cleanly against the empty fake home (VERIFIED). `qwen sessions ps` is a real live-process
listing backed by the registry in §G, not a guess from the transcript directory.

### What survives a crash — and the liveness marker most tools don't have

Alongside each transcript, Qwen writes **`<sessionId>.runtime.json`** in the same `chats/` directory.
`getRuntimeStatusPathState` (VERIFIED, `chunks/chunk-CXDWVOBM.js`) reads it and returns
`active` / `dead` / `missing`:

```js
if (!status || status.sessionId !== sessionId) return "missing";
if (status.hostname !== os.hostname())        return "active";
try { process.kill(status.pid, 0); return "active"; }
catch (error) { if (error.code === "ESRCH") return "dead"; return "active"; }
```

**An orchestrator can therefore detect a crashed session by reading one small JSON file — no process
table scan, no PID bookkeeping of its own.** Note it fails *open*: a foreign hostname or any
non-`ESRCH` error reads as `"active"`, so `"dead"` is trustworthy but `"active"` is not proof of
life.

- Daemon child crash: publishes a `session_died` SSE event and drops the live session; the persisted
  session *can* be reloaded with `POST /session/:id/load` if a fresh child can be spawned (VERIFIED,
  `docs/qwen-serve.md`).
- **The real resume hazard is the writer lock, not the transcript.** `docs/conversations-recovery.md`
  is blunt: after an ungraceful shutdown a session can be fenced by a residual writer lock
  (`session_writer_conflict` / `session_writer_unavailable`), and *"There is no force-unlock API or
  automatic cross-boot/TTL takeover in this release."* Recovery is a five-step manual operator
  procedure. **For an unattended overnight queue this is the single most likely way a Qwen session
  becomes permanently unresumable without a human.** Budget for it: prefer `--fork-session` or a
  fresh id over fighting a fenced session.
- Provider outage: see axis E — `QWEN_CODE_UNATTENDED_RETRY=1` plus `--fallback-model`.

---

## C. TRANSCRIPT

**On disk as JSONL, in a documented location, plus a live event channel for TUI sessions and a paged
HTTP reader for daemon sessions. Fully answered.**

### On disk

```
$QWEN_HOME/projects/<sanitized-cwd>/chats/<sessionId>.jsonl          # the transcript
$QWEN_HOME/projects/<sanitized-cwd>/chats/<sessionId>.runtime.json   # liveness (see axis B)
$QWEN_HOME/projects/<sanitized-cwd>/chats/<sessionId>.ledger.jsonl   # sidecar, excluded from chat scans
```

`$QWEN_HOME` defaults to `~/.qwen`. VERIFIED two ways: `docs/features/headless.md` states
*"Session data is project-scoped JSONL under `~/.qwen/projects/<sanitized-cwd>/chats`"*, and the code
composes `path.join(new Storage(projectRoot).getProjectDir(), "chats")` and filters
`file.endsWith(".jsonl") && !file.endsWith(".ledger.jsonl")` (`chunks/chunk-3JHSUEQN.js`).

Requires `general.chatRecording` on (the default). `--chat-recording false` disables persistence
**and** breaks `--continue`/`--resume` (VERIFIED, `--help`).

### Live, for a TUI session the owner can watch — Dual Output

```
--json-file <path>   # JSONL events to a file, FIFO, or /dev/fd/N
--json-fd <n>        # same events to an inherited fd (n >= 3); mutually exclusive with --json-file
```

The TUI renders normally on stdout **while** structured events go to the side channel — *"No ANSI
parsing on either side."* The schema is the same as `--output-format stream-json` with
`includePartialMessages` always on. The first event is always `system` / `session_start`, *"emitted
when the bridge is constructed. Use it to correlate the channel with a session id before any other
event arrives"* (VERIFIED, `docs/features/dual-output.md`).

`--json-fd` is documented as **not working under a PTY** — which is exactly how an orchestrator that
wants a visible, attachable window will spawn it. **Use `--json-file` with a FIFO for supervised TUI
sessions.** The doc is explicit that the TUI starts immediately and a reader can connect later.

Failure modes are all fail-safe: a bad fd, an unopenable path, or a reader disconnect (`EPIPE`)
prints a stderr warning and **the TUI keeps running** with dual output silently disabled (VERIFIED).
A supervisor must therefore treat "no events" as "possibly disabled", not "possibly idle".

### Live, for a daemon session

- `GET /session/:id/events` — SSE, with `Last-Event-ID: N` replay against a ring of
  `--event-ring-size` (default **8000**) frames.
- `GET /session/:id/transcript` — *"returns the complete active on-disk transcript as replay pages
  without attaching a client or changing the live SSE replay window."* Cursor-paged. This is the
  read-only progress reader a supervisor wants.
- `GET /session/:id/status` → `{sessionId, workspaceCwd, createdAt, clientCount, hasActivePrompt}`,
  404 if not live. **This is the cheap liveness/busy poll.**
- `GET /session/:id/turns/current`, `GET /session/:id/turns/:promptId`, `GET /session/:id/agent-trace`.

**Do not poll `GET /workspace/:id/session-info`** — the docs mark it `expensive: true`,
`cost: "disk_scan"` with an explicit *"Disk scan — do not poll"* warning (VERIFIED).

**Replay is bounded twice** (SSE ring, and `--compacted-replay-max-bytes`, default 4 MiB). Long
disconnects (>5 min on a chatty turn) trigger `state_resync_required`. Use `/transcript` when
completeness matters; `/load` returns a *snapshot*, not the full history (VERIFIED,
`docs/qwen-serve.md` "Durability model").

---

## D. CONTEXT — **the owner's hardest axis, and Qwen Code answers all three parts**

Read fullness · trigger compaction from outside · prove it happened. Qwen Code is the only platform
in this spike so far that does all three with first-class surfaces.

### 1. Read how full the context window is — VERIFIED

```
GET /session/:id/context-usage[?detail=true]
```

ACP/JSON-RPC twin: `qwen/status/session/context_usage`. Response shape read directly from
`buildSessionContextUsageStatus` (VERIFIED, `chunks/acpAgent-ANIVCBU3.js`):

```js
{ type: "context_usage",
  modelName, totalTokens, contextWindowSize,
  breakdown: { systemPrompt, builtinTools, mcpTools, memoryFiles,
               skills, messages, freeSpace, autocompactBuffer },
  builtinTools: [], mcpTools: [], memoryFiles: [], skills: [],
  isEstimated, showDetails }
```

`totalTokens / contextWindowSize` is the fullness ratio, and the `breakdown` tells the supervisor
*why* it is full — whether it is MCP tool schemas, memory files, skills, or actual conversation. It
degrades gracefully: on an internal failure it returns zeros with `isEstimated: true` rather than
erroring, so **check `isEstimated` before acting on the number.**

Also available: `GET /session/:id/context`, `GET /session/:id/stats`. Interactively the same data is
`/context` and `/context detail`.

> Contrast with the owner's field notes: *"nothing in the plugin measures a session's context
> window."* Here it is one authenticated GET.

### 2. Trigger compaction from outside — VERIFIED

`/compress` (alias `/summarize`) and `/compress-fast` (non-AI: strips old tool outputs and thinking
parts). The command definition is decisive (VERIFIED, `chunks/chunk-3JHSUEQN.js`):

```js
var compressCommand = {
  name: "compress",
  altNames: ["summarize"],
  kind: "built-in",
  supportedModes: ["interactive", "non_interactive", "acp"],
  ...
```

**`supportedModes` includes `non_interactive` and `acp`** — so compaction is invocable from outside
by three routes:

| Session kind | How the supervisor fires it |
|---|---|
| Daemon session | `POST /session/:id/prompt` with `/compress` |
| Visible TUI session | write `{"type":"submit","text":"/compress"}` to the `--input-file` |
| Headless follow-up | `qwen --resume <id> -p "/compress"` |

Auto-compaction also exists, at `context.autoCompactThreshold` (default **0.85**), described as a
ceiling: *"on large windows it is the effective trigger (~85%), while on smaller windows compaction
may fire earlier to leave room to summarize."* The older
`model.chatCompression.contextPercentageThreshold` is **REMOVED and silently ignored** — do not set
it (VERIFIED, `docs/configuration/settings.md`).

### 3. Proof it happened — VERIFIED, and this is the part nothing else offers

A **`PostCompact` hook** fires after a successful compaction (VERIFIED, `docs/features/hooks.md`):

```json
{ "trigger": "manual | auto",
  "compact_summary": "the summary that replaced the compacted history, without its <analysis> block" }
```

*"Runs after a conversation compaction succeeds, to archive the summary or track usage. It does not
fire when compaction fails. Qwen waits for the hooks to finish before continuing."* The `matcher`
matches on `trigger`, so `"matcher": "manual"` fires **only** for compactions the supervisor asked
for. There is a `PreCompact` sibling too.

And hooks can be **`type: "http"`** — a POST to a URL the supervisor owns, with `headers`,
`allowedEnvVars` for `${VAR}` interpolation, `timeout` (default 600 s) and `once`. SSRF protection
blocks private IP ranges **but explicitly allows loopback (127.0.0.1, ::1)** — which is exactly where
a local orchestrator listens (VERIFIED).

**So the full loop is: read `context-usage` → POST `/compress` → receive a `PostCompact` webhook
carrying the summary and `trigger: "manual"`.** Trigger from outside, proof delivered to the
supervisor, not scraped. Three independent signals also exist as a fallback: the compaction item
carries `originalTokenCount` / `newTokenCount` / `compressionStatus` (an enum where `1 = COMPRESSED`,
`5 = NOOP`, and `2/3/4/6/7` are distinct failure reasons — VERIFIED), and re-reading
`context-usage` shows the drop.

Secondary knob: `/model --compaction <model-id>` sets a cheaper model for compression (VERIFIED,
`docs/features/commands.md`). Worth using — compaction on a long overnight queue is not free.

---

## E. QUOTA — **the weakest axis, and the one to plan around**

### Remaining capacity cannot be read. VERIFIED by exhaustive search.

There is **no** endpoint, protocol event, CLI command or credential-file field that reports
remaining provider capacity. I grepped every shipped chunk for `quota|usage|billing|balance|limit|credit`
route literals. The only three hits that looked promising were false leads, and I checked each:

| Literal | What it actually is |
|---|---|
| `GET /rate_limit` | **Octokit's GitHub REST route map** (`chunks/dist-DBBOFWSC.js`, next to `rateLimit: { get: [...] }`). Nothing to do with Qwen. |
| `GET /user/interaction-limits` | Same Octokit map. |
| `QWEN_REALTIME_LIMITS` | Audio frame-size caps for the voice/realtime session (`maxInputAudioFrameBytes`, `maxTranscriptChars`, …). Nothing to do with quota. |

This matters because a naive pass would have reported two "quota endpoints" that do not exist.

### What *can* be read: local spend, not remaining allowance

```
GET /usage/dashboard[?range=today&heatmapDays=N]
```

VERIFIED server-side in `chunks/server-PN5WV25I.js` (`registerUsageStatsRoutes`), and the SDK
documents it as *"the selected range's flattened totals plus a trailing per-day heatmap, read from
the durable local usage history (global, cross-project)."* `heatmapDays` defaults to ~6 months,
server-clamped to 1..366.

It is backed by a plain file the orchestrator can read **without the daemon running at all**
(VERIFIED, `usageHistoryService.ts` in `chunks/chunk-J6QWYIXU.js`):

```js
function getUsageHistoryPath() {
  return path4.join(Storage.getGlobalQwenDir(), "usage_record.jsonl");
}
```

→ **`$QWEN_HOME/usage_record.jsonl`** (i.e. `~/.qwen/usage_record.jsonl`), global and cross-project.

**This is a spend ledger, not a quota gauge.** It answers "how many tokens have I burned today across
every project", which is enough to enforce the orchestrator's *own* budget. It cannot answer "how
much does Alibaba still owe me".

### Windows that exist

Set by the **plan**, not by the CLI, and none of them is exposed locally:

| Plan | Billing shape | Endpoint |
|---|---|---|
| Coding Plan | fixed monthly fee, *"weekly quota included"* | `https://coding.dashscope.aliyuncs.com/v1` (CN) · `https://coding-intl.dashscope.aliyuncs.com/v1` (intl) |
| Token Plan | usage-based | `https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1` · `https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1` |
| Standard API key / third party | per-token | DashScope, OpenRouter, Requesty, ModelScope, … |
| Qwen OAuth free tier | **discontinued 2026-04-15** | — |

The Coding Plan's *weekly* quota is the closest analogue to the Anthropic seven-day window the owner
already watches — and unlike Anthropic's `/api/oauth/usage`, **it has no local readout**. Exact
figures: **UNKNOWN** (they live behind the ModelStudio console, which needs an account).

### In-band limit-hit signalling — present, but only as prose. VERIFIED, and this is the sharp edge.

Quota exhaustion is detected by **string-matching the provider's error message**
(`chunks/chunk-YSD6IY6F.js`):

```js
function isQuotaExhaustedError(error) {
  const message = getQuotaMessage(error);
  if (!message) return false;
  const lower = message.toLowerCase();
  return lower.includes("quota")
      && (lower.includes("exhausted") || lower.includes("exceeded"))
      && (lower.includes("will reset") || lower.includes("reset at"));
}
```

Consequences an orchestrator must swallow:

- **There is no structured reset timestamp.** The reset time, when it exists, is free text inside the
  provider's prose. `formatQuotaExhaustedMessage` can only say *"Please retry after the reset time,
  or switch to another API key / auth method."* — it does not know when that is.
- **Detection is provider-dependent.** A provider whose 429 body says "insufficient balance" without
  the words "will reset" is **not** classified as quota-exhausted and will be treated as an ordinary
  rate limit and retried.
- On a true quota-exhausted classification the stream **fast-fails** rather than retrying
  (`retryDecision: "fail-fast"` — VERIFIED).
- Ordinary rate limits *are* handled structurally: `getRateLimitErrorDetails` returns
  `{statusCode, providerCode, providerType, providerMessage, requestId, transport}`, and
  `getRateLimitRetryDelayMs` honours `Retry-After` in `retryAfterMode: "minimum"` — i.e. it waits
  **at least** what the server asked.

### The two real mitigations

```
--fallback-model <m>[,<m2>,<m3>]   # up to 3, for capacity errors (429/503/529)
QWEN_CODE_UNATTENDED_RETRY=1       # retry 429/529 indefinitely, backoff capped at 5 min,
                                   # stderr heartbeat every 30s so CI doesn't reap the process
```

`--fallback-model` is the closer fit for the owner's multi-account ambition: **degrade the model
instead of stopping the queue.** The docs are firm that `QWEN_CODE_UNATTENDED_RETRY` needs explicit
opt-in — *"CI=true alone does not activate it — silently turning a fast-fail CI job into an
infinite-wait job would be dangerous"* — and should be paired with `--max-wall-time` so a
permanently-broken provider cannot extend a job forever (VERIFIED).

### Closest workaround, and what it costs

**Turn quota into a locally-enforced budget.** Read `~/.qwen/usage_record.jsonl` (or
`GET /usage/dashboard`) before dispatching each ticket, compare against a ceiling the owner sets per
account per day, and stop dispatching at the ceiling. Treat the provider's own limit as an
*exception path*, not a gauge: catch the fast-fail, rotate to the next account (axis F), and retry.

Cost: the ceiling is a guess that must be calibrated by hand against the plan, and it drifts whenever
the plan changes. **Compared with Claude Code's `five_hour.utilization` / `seven_day.utilization` /
`resets_at`, this is a genuine regression, and it is the owner's #1 stated requirement.** Plan the
orchestrator so that *quota reading is a per-platform capability that may be absent*, with a
budget-ledger fallback — do not design the scheduler assuming every platform can be asked how much
is left.

---

## F. ACCOUNTS

**Per-account isolation is clean and env-var driven. Switching a *running* session's account is
partially possible — better than most, still not complete.**

### Several accounts on one machine — VERIFIED

**`QWEN_HOME` relocates the entire config home.** Everything keys off
`Storage.getGlobalQwenDir()`, which is `QWEN_HOME`-aware rather than always `~/.qwen`. Confirmed by
the shipped source comments (*"Pass the QWEN_HOME-aware global dir (`Storage.getGlobalQwenDir()`) so
a relocated config home is honored instead of always reading the real OS home"*) and by a guard
string in the bundle:

```
QWEN_HOME points to "${activeQwenDir}" but no settings.json was found there.
Existing config remains at "${legacyQwenDir}" …
```

So the pattern is exactly the one the owner already uses for Claude Code via `CLAUDE_CONFIG_DIR` and
a profile switcher:

```
QWEN_HOME=~/.qwen-accounts/acct-a   qwen ...
QWEN_HOME=~/.qwen-accounts/acct-b   qwen ...
```

and each account gets its own `settings.json`, `projects/`, `sessions/`, `usage_record.jsonl` and
controller-token store. **Note the trade-off: relocating `QWEN_HOME` also partitions the transcript
store and the usage ledger.** The owner's profile-switcher setup deliberately symlinks `projects/` into one
shared store so resume works across accounts; a Qwen equivalent would have to do the same by hand,
or accept that a session started under one account cannot be resumed under another.

### Per-session / per-run, without touching any config — VERIFIED

Credentials resolve in a documented precedence (highest first):

1. CLI flags — `--openai-api-key`, `--openai-base-url`, `--auth-type`
2. process env — `OPENAI_API_KEY` / `OPENAI_BASE_URL` / `OPENAI_MODEL`, `ANTHROPIC_API_KEY` /
   `ANTHROPIC_BASE_URL`, `GEMINI_API_KEY`, `DASHSCOPE_API_KEY`,
   `BAILIAN_CODING_PLAN_API_KEY`, `BAILIAN_TOKEN_PLAN_API_KEY`
3. `.env` — first hit wins, **never merged**: `.qwen/.env` → `.env` walking up from cwd, then
   `~/.qwen/.env` → `~/.env`
4. `settings.json` → `env` (lowest)

`--auth-type` takes `openai | openai-responses | anthropic | qwen-oauth | gemini | vertex-ai`
(VERIFIED, `--help`). **So a supervisor can pin a brand-new session to a chosen account purely by the
spawn environment — no config file written, no global state mutated.** That is the cleanest form of
axis F and it needs no profile-switcher equivalent at all for the per-run case.

One gotcha worth writing into the adapter (VERIFIED, `docs/configuration/auth.md`): a
provider-specific key like `BAILIAN_TOKEN_PLAN_API_KEY` *"takes effect once the `settings.json`
provider entry … exists, because that entry declares it as the `envKey`"* — it does **not** select
the auth type on its own. **To switch accounts with environment variables alone, export
`OPENAI_API_KEY` (+ `OPENAI_BASE_URL`), not the provider-specific name.**

### Credentials at rest

Plain files under `$QWEN_HOME`, mode-controlled by `QWEN_CREDENTIAL_FILE_MODE` /
`QWEN_CREDENTIAL_FILENAME` (VERIFIED, env-var names in the bundle). **No macOS Keychain** — which
removes the silent-failure mode the field scan flagged for Claude Code, where an unattended run can
block on a GUI Keychain dialog. **For overnight running this is a genuine advantage over Claude
Code.** The cost is that keys sit in files; `docs/configuration/auth.md` says as much and recommends
`.qwen/.env` over `settings.json`.

### Changing a RUNNING session's account — partially, VERIFIED

Better than most platforms, but read the caveats:

- `POST /session/:id/model` switches the model of a live session and publishes a `model_switched`
  event (VERIFIED).
- `POST /workspace/auth/provider` installs a provider (base URL + key) into a **running daemon**.
  It is guarded: `--allow-private-auth-base-url` is required before it will accept
  localhost/private-network base URLs, and the docs restrict that to *"local development with trusted
  clients"* (VERIFIED, `--help` + route in `server-PN5WV25I.js`).
- `POST /workspace/auth/device-flow` runs an OAuth device flow **against a remote daemon**, returning
  `{deviceFlowId, userCode, verificationUri, verificationUriComplete, expiresAt, intervalMs}` and
  emitting an `auth_device_flow_authorized` SSE event on success (VERIFIED, `docs/qwen-serve.md`).
  **This is how an unattended supervisor gets a human through a login without a terminal** — surface
  the URL and code in Slack, poll or subscribe for the event.

**But**: provider auth is **workspace-scoped, not session-scoped**. Changing it changes it for every
session in that workspace runtime. Per-role accounts therefore want **one daemon (or one `QWEN_HOME`)
per account**, not one daemon with per-session identities. Cost: N daemons on different ports, N
config homes, and a port/`QWEN_HOME` registry the orchestrator owns.

---

## G. INTERVENTION — **three independent mechanisms, all programmatic, all with delivery evidence**

This is the axis the owner's current harness fails at — the field notes record *"a nudge that cannot
submit stranded text"*. Qwen Code answers it three different ways depending on how the session was
launched.

### 1. Daemon session — HTTP

```
POST /session/:id/prompt                      # normal turn
POST /session/:id/mid-turn-message            # inject WHILE a turn is running  ← the nudge
GET  /session/:id/mid-turn-messages
DELETE /session/:id/mid-turn-messages/:messageId
POST /session/:id/btw                         # sibling out-of-band channel
GET  /session/:id/pending-prompts
DELETE /session/:id/pending-prompts/:promptId # retract a queued prompt
POST /session/:id/cancel
```

`mid-turn-message` is capped at **16 KiB** (`MID_TURN_MESSAGE_MAX_LENGTH = 16 * 1024`) and validates
strictly — empty message with no media → `400` (VERIFIED, `server-PN5WV25I.js`). Delivery is known
from the HTTP status, and the docs state *"A mid-turn user message runs first and starts a fresh
two-attempt stage"*. The ability to **list and retract** pending prompts is unusual and valuable: a
supervisor that changes its mind can withdraw an instruction it already queued.

**Answering the session's own question — the owner's non-negotiable:**

```
POST /session/:id/permission/:requestId       # session-scoped
POST /permission/:requestId                   # daemon-global (legacy)
```

Both are registered in 0.24.1 (VERIFIED by grepping the route table). **The shipped
`docs/qwen-serve.md` is stale here** — it still carries a *"Stage 1 known gap — permissions are
daemon-global, not per-session"* warning and describes the session-scoped route as future work. The
code says it shipped. Prefer the session-scoped route; treat the doc's warning as historical, but
still heed its security point: on a token-shared daemon, any authenticated client can vote on any
`requestId`.

The pending request arrives as a `permission_request` SSE event carrying the `requestId`.
`--permission-response-timeout-ms` (default **0** = wait forever) bounds both permission and
`ask_user_question` waits — **set it for unattended runs**, or a single unanswered question parks a
session indefinitely. And `--restore-ask-user-question` decides what happens on reload: *"re-hang a
trailing unanswered `ask_user_question` instead of synthesizing a failed tool result"* — i.e. the
question survives a restart instead of being silently failed.

### 2. Visible TUI session — Dual Output input file

```
qwen --json-file /tmp/qwen-events.jsonl --input-file /tmp/qwen-input.jsonl
```

Two command shapes, verbatim from `docs/features/dual-output.md` (VERIFIED):

```jsonc
{ "type": "submit", "text": "What does this function do?" }
{ "type": "confirmation_response", "request_id": "...", "allowed": true }
```

Semantics the owner should care about:

- `submit` is **queued and auto-retried** when the TUI is busy — *"they are retried automatically the
  next time the TUI returns to the idle state."* **This is precisely the "stranded text" failure the
  current harness has, solved.**
- `confirmation_response` is **dispatched immediately and never queued**, *"because a tool call is
  blocking and the response must reach the underlying `onConfirm` handler without waiting for any
  earlier `submit`."*
- Whichever side answers first wins; the loser's response is harmlessly dropped. So the owner can
  take over the keyboard at any moment without breaking the supervisor.
- **Evidence of arrival:** a `control_response` event is emitted on the output channel *"whether the
  decision was made in the TUI (native approval UI) or by an external `confirmation_response` … all
  observers see the final outcome."*
- **Latency:** the input file is watched with `fs.watchFile` at a **500 ms poll**, so worst-case
  round trip is about half a second. Deliberate, for portability across macOS and network mounts.
- Unparseable lines are logged and skipped; they do not kill the watcher.

The docs ship runnable proof-of-concepts for exactly this: *POC 2 — inject prompts from outside* and
*POC 3 — remote tool-permission bridge* (*"The TUI confirmation prompt dismisses and the tool
executes."*).

### 3. Any session — the cross-session protocol with **controller tokens**

`docs/features/cross-session-protocol.md` is a 338-line wire contract for *"a program that wants to
take part in cross-session messaging without being a Qwen Code session: a voice front-end, a relay
daemon, a script that watches a build."* That is the orchestrator, described by name.

Every running session publishes a registry record:

```
$QWEN_HOME/sessions/<pid>.json              (dir 0700, file 0600)
$QWEN_HOME/sessions/<pid>-<8 hex>.json      (a process hosting several sessions)
```

carrying `{schemaVersion, pid, procStart, pidNs, sessionId, cwd, name, startedAt, qwenVersion,
kind, ipcPath, ipcToken}`, where `kind` ∈ `tui | headless | serve | external`. Messages go over a
UNIX socket at `$XDG_RUNTIME_DIR/qwen-socks/<pid>.sock` (or a `$TMPDIR` / `/tmp` fallback),
newline-delimited JSON, 1 MiB line cap, 64 concurrent connections.

**The controller token is the orchestrator's credential**, and it is a real, minted grant:

```
qwen sessions controllers add --label <name>   # "Mint a controller token and print it once"
qwen sessions controllers list                 # "List the controllers this Qwen home trusts"
qwen sessions controllers remove <id>          # "Revoke a controller by id"
```

(VERIFIED — I ran `qwen sessions controllers` and read the subcommand table.) The token format is
`qpc_<64 hex>`. Presenting it on the auth line makes the inbox conclude *"a program the user
trusts"*, and the message is **delivered under the parity default** rather than held for human
review — and is exempt from the duplicate-suppression window. The receiving model sees the sender's
authority stamped by the *receiver* from what the connection presented, never from the frame:
`origin="controller" controller="<label>"`.

**Delivery evidence is a first-class part of the protocol** — a `delivery_status` control frame per
outcome, with a defined state machine:

```
pending   → held | delivered | denied | refused | expired | misaddressed | dropped
held      → delivered | denied | expired | misaddressed
delivered → expired | misaddressed
```

`dropped` additionally carries `dropReason` ∈ `rate-limited | duplicate | queue-full` and
`droppedMsgIds` (up to 256 ids settled by one receipt, so a burst is answered once).

Three honest limits, all stated by the doc itself:

- **`delivered` is not proof it was read** — only that it was queued for the model.
- Rate limits are real: per sender, burst 30 then one per 2 s; all senders together, burst 32 then
  one per second. Hold buffer 50, expiring per `agents.crossSessionHeldExpiry` (default `5m`).
- **§8: *"Inbound messages to ACP-driven sessions … answers `refused` to anything sent to it"*.** A
  daemon-spawned or editor-driven session can *send* but cannot *receive* over this channel, because
  *"a hold is a question put to a person, and nobody is watching a hold list on its behalf."*

**So the mechanisms are complementary, not redundant, and the adapter must pick by session kind:**
daemon sessions → HTTP (§1); TUI sessions → `--input-file` (§2) or the IPC socket (§3); headless
sessions → IPC socket (§3).

`@qwen-code/sdk/peer` implements the joining side in Node with no dependencies, *"and its tests run
it against Qwen Code's own implementation in both directions"* — worth using rather than
hand-rolling the framing.

### 4. Bonus — the agent board

```
qwen board task <subject> | claim <id> | done <id>
           ask <to> <question> | answer <id> <answer> | decline <id> <reason>
           show | prune        [--board <name>] [--as <actor>] [--json]
```

A file-backed shared task board with an explicit **ask/answer/decline** triad and `--json` output
(VERIFIED — ran `qwen board --help`; `qwen board show --json` correctly demanded `--board <name>`).
This is a ready-made queue + question channel between the orchestrator and its fleet, requiring no
protocol work at all. Worth a prototype before building a bespoke ticket store.

---

## H. GUARDRAILS

**Rich, and the defaults are safer than most. VERIFIED.**

### Approval modes

`--approval-mode plan | default | auto-edit | auto | yolo` (also `-y` / `--yolo`, and
`tools.approvalMode` in settings):

| Mode | File edits | Shell | Notes |
|---|---|---|---|
| `plan` | ❌ read-only | ❌ | analysis only |
| `default` ("Ask Permissions") | approval | approval | |
| `auto-edit` | auto | approval | |
| **`auto`** | classifier | classifier | **the documented out-of-the-box default** |
| `yolo` | auto | auto | |

**`auto` being the default is the most consequential unattended fact on this axis.** An LLM
classifier auto-approves safe actions and blocks risky ones. It is a safety net, but it is a *model*
making the call, and when it blocks repeatedly Qwen falls back to asking the user — which, unattended,
means parking. Pair `auto` with `--permission-response-timeout-ms` so a fallback-to-ask cannot hang
the run forever, and watch the `PermissionDenied` hook (fires on classifier blocks, `reason:
classifier_blocked`; it reports and **cannot** approve).

### Allow / deny

`--allowed-tools <array>` (bypass confirmation), `--exclude-tools <array>`, `--core-tools <array>`,
`--allowed-mcp-server-names <array>`, `--disabled-slash-commands`, plus `GET`/`POST
/workspace/permissions` and `POST /session/:id/approval-mode` to change mode on a **live** session.

### Sandboxing — and the warning that matters

```
-s, --sandbox            # or QWEN_SANDBOX=1
    --sandbox-image <uri>
qwen sandbox [cmd...]    # inspect the backend, or run a command inside it
```

On macOS this is **native Seatbelt** (`sandbox-exec`), and the package ships six profiles:
`sandbox-macos-{permissive,restrictive}-{closed,open,proxied}.sb` (VERIFIED — the files are in the
package root). Default `permissive-open`: *"restricts writes outside the project directory, but
allows most other operations and outbound network access."* Docker/Podman is the alternative; the
container *"mounts your workspace and your `~/.qwen` directory"* — relevant if `QWEN_HOME` was
relocated for account isolation.

> **`--yolo` does not enable a sandbox.** The docs say so explicitly, and Qwen prints a one-line
> stderr warning when it sees yolo-without-sandbox (suppress with `QWEN_CODE_SUPPRESS_YOLO_WARNING=1`).
> For an unattended queue on the owner's own machine, the recommended combination is
> `--yolo --sandbox --max-session-turns N --max-wall-time 10m --output-format json`.

### Hooks — 20 events

`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `UserPromptSubmit`,
`UserPromptExpansion`, `SessionStart`, `SessionEnd`, `SessionDelete`, `MessageDisplay`, `Stop`,
`StopFailure`, `SubagentStart`, `SubagentStop`, **`PreCompact`**, **`PostCompact`**, `Notification`,
**`PermissionRequest`**, `PermissionDenied`, `TodoCreated` (VERIFIED, `docs/features/hooks.md`).

Four hook types: `command`, **`http`**, `function`, `prompt`.

**`PermissionRequest` is a second, synchronous way to answer the session's own question** — the hook
returns a structured decision:

```json
{ "hookSpecificOutput": { "decision": {
    "behavior": "allow",           // or "deny"
    "updatedInput": { },           // optional: rewrite the tool call
    "updatedPermissions": [ ],     // optional
    "message": "…", "interrupt": false } } }
```

An HTTP `PermissionRequest` hook pointed at `http://127.0.0.1:<orchestrator>` lets the supervisor
**adjudicate every permission prompt centrally, for every session, with policy in one place** — and
`updatedInput` even lets it rewrite a dangerous call into a safe one. This is a stronger guardrail
story than allow/deny lists.

### Other

`--safe-mode` disables *all* customizations (context files, hooks, extensions, skills, MCP,
custom subagents, permission rules, settings-sourced approval overrides, memory, sandbox settings)
while leaving `--yolo`/`--approval-mode` in force — a clean bisect tool when an overnight run
misbehaves. `--bare` skips implicit startup auto-discovery. Folder trust is a real gate
(`GET /workspace/trust`, `POST /workspace/trust/request`): untrusted workspaces do not read
repo-controlled hooks or project `.qwen` files.

---

## I. EXTENSIBILITY

**The richest surface in the field. A GSD-style, subagent-heavy engine would run inside it. VERIFIED.**

- **MCP** — `qwen mcp`, `--mcp-config <json|path>`, `--allowed-mcp-server-names`, plus full runtime
  management on the daemon: `POST /workspace/mcp/servers`, `DELETE /workspace/mcp/servers/:name`,
  `POST /workspace/mcp/:server/restart`, `/reload`, `/initialize`, and `GET /workspace/mcp/:server/tools`.
  Servers can be added to a **running** daemon and publish `mcp_server_added` / `mcp_server_removed`
  events. Budgeting exists (`--mcp-client-budget`, `--mcp-budget-mode enforce|warn|off`).
- **Skills** — bundled ones ship in the package (`batch`, `browser-use`, `computer-use`, `coordinate`,
  `dataviz`, `loop`, `review`, `simplify`, `stuck`, `workflow-authoring`, `workflow-creator`,
  `new-app`, `goal-draft`, `extension-creator`, …). Runtime toggles:
  `POST /workspace/skills/:name/enable`, batch `POST /workspace/skills/enable`, install via
  `POST /workspace/skills/install`.
- **Subagents** — `--max-subagent-depth` (default **5**, cap 100), `GET /session/:id/agents`,
  `GET /session/:id/agent-trace`, `POST /session/:id/subagents/:subagentRef/cancel`,
  `SubagentStart` / `SubagentStop` hooks, `POST /session/:id/side-task`, `POST /session/:id/fork`
  (*"Spawn a background agent that inherits the full conversation"*).
  **The orchestrator can see and cancel individual subagents of a running session** — a level of
  granularity nothing else in this spike offers.
- **Workflows** — a real engine: `qwen/control/session/task/workflow-action`, saved workflow
  definitions, `QWEN_CODE_MAX_WORKFLOW_SECONDS`, `QWEN_CODE_MAX_TOKENS_PER_WORKFLOW`,
  `QWEN_CODE_ENABLE_WORKFLOWS` / `QWEN_CODE_DISABLE_WORKFLOWS`, and a `workflow-authoring` skill.
- **Goals** — a persistent objective with a verifier that keeps working until satisfied, drivable
  entirely headlessly: `qwen -p "/goal <objective>"`, then
  `qwen --continue -p "/goal pause|resume|clear"`. Under `--output-format stream-json` every status
  change emits a `goal_state` event. **This is a durable long-horizon primitive the orchestrator
  could delegate to instead of re-implementing.** Note *"Runtime-scheduled Goal continuation segments
  do not count against `--max-session-turns`"* — so a Goal can outlive a turn budget; bound it with
  `--max-wall-time`.
- **Extensions** — `qwen extensions`, `-e/--extensions`, `-l/--list-extensions`,
  `PUT /workspaces/:workspace/extensions/activation`.
- **Context files** — `QWEN.md` (the `CLAUDE.md` analogue), `--include-directories/--add-dir`,
  `context.importFormat`, auto-memory with `/remember`, `/forget`, `/dream`.
- **Config precedence** — system → user (`~/.qwen/settings.json`) → project (`.qwen/settings.json`)
  → env → CLI flags. Docs recommend putting `modelProviders` in **user** scope *"to avoid merge
  conflicts between project and user settings"*.
- **Scheduled tasks** — `docs/features/scheduled-tasks.md`, with daemon keepalive
  (`scheduled-task-keepalive.ts`). Cron-shaped work is native.
- **Worktrees** — `--worktree [slug|#123|PR-url]` starts the session inside
  `<repoRoot>/.qwen/worktrees/<slug>/`. **Parallel tickets on one repo without collisions, for free.**
  On exit a dialog asks whether to keep the worktree — an interactive prompt to be aware of in
  unattended runs; the daemon has `POST /session/:id/worktree-reset`.
- **SDK** — `@qwen-code/sdk` **0.1.13**, published 2026-09-19 (VERIFIED, npm), *"TypeScript SDK for
  programmatic access to qwen-code CLI"*, with the `@qwen-code/sdk/peer` submodule for the
  cross-session protocol.
- **ACP** — `--acp` speaks Agent Client Protocol on stdio, with a `_qwen/` JSON-RPC extension
  namespace (`QWEN_METHOD_NS = "_qwen/"`) and ~30 `qwen/status/*` and ~40 `qwen/control/*` ext
  methods mirroring the HTTP surface. An orchestrator can drive a session over stdio **without** the
  daemon.

---

## J. OPERATIONAL REALITY

| Fact | Value | Tag |
|---|---|---|
| Package | `@qwen-code/qwen-code`, binary `qwen` | VERIFIED (npm) |
| Version | **0.24.1**, published **2026-09-19T08:28:42Z** | VERIFIED (npm) |
| First published | 2025-07-22 | VERIFIED (npm `time.created`) |
| Repo | `QwenLM/qwen-code`, **Apache-2.0** | VERIFIED (GitHub API) |
| Stars / open issues | **27,986** / **1,472** | VERIFIED (GitHub API, today) |
| Last push | 2026-09-19T13:08:11Z (today) | VERIFIED |
| Release cadence | v0.24.1 today, `v0.24.1-preview.0` yesterday, nightlies daily | VERIFIED (GitHub releases) |
| Node | **>= 22.0.0** | VERIFIED (`engines`) |
| Install size | **124 MB** unpacked, 16 packages | VERIFIED (measured) |
| macOS | yes — native Seatbelt profiles ship in the package | VERIFIED |
| Install | `npm i -g @qwen-code/qwen-code@latest`, `brew install qwen-code`, or the standalone script at `qwen-code-assets.oss-cn-hangzhou.aliyuncs.com` | VERIFIED (README) |
| Also ships | Desktop app (`desktop-v0.24.1`), VS Code / JetBrains / Zed integrations, Web Shell, Telegram / DingTalk / WeChat / Feishu / QQ / GitHub / GitLab channels | VERIFIED |
| Installed on this machine | **No** | VERIFIED |
| Cost | No free tier since 2026-04-15. Coding Plan (fixed monthly, weekly quota) / Token Plan (usage-based) / any OpenAI-, Anthropic- or Gemini-compatible key | VERIFIED (auth.md) |
| Actual prices | **UNKNOWN** — behind the ModelStudio console | UNKNOWN |

**Maturity read.** The version number is modest (0.24.x) but the engineering is not: bounded
journals, adaptive memory growth, rate-limit tiers, SSRF protection on hooks, writer-lease fencing,
`errorKind` enums, capability negotiation. **1,472 open issues** against 28k stars is a lot of churn
— this is a fast-moving, heavily-used project, not a settled one. Pin an exact version in the
orchestrator and upgrade deliberately.

### Known unattended-run failure modes — the list to design against

1. **Fenced writer lock after an ungraceful shutdown.** No force-unlock API, no TTL takeover; manual
   operator procedure. **The most likely way a session becomes permanently unresumable.** (VERIFIED)
2. **Daemon ACP sessions ignore the run budgets.** *"the daemon ACP session path does NOT currently
   consult `--max-wall-time` / `--max-tool-calls` from settings.json. These budgets only apply to
   single-shot `qwen -p` runs and to `--input-format stream-json` sessions."* **So the daemon — the
   most controllable launch mode — is exactly the one where the wall-clock kill switch does not
   apply.** Enforce the timeout in the orchestrator, or use `--prompt-deadline-ms`. (VERIFIED)
3. **An unanswered question parks a session forever** unless `--permission-response-timeout-ms` is
   set (default `0` = wait indefinitely). (VERIFIED)
4. **Quota exhaustion fast-fails with no machine-readable reset time.** (VERIFIED — axis E)
5. **Replay-window overrun** on long disconnects → `state_resync_required`; `/load` returns a
   snapshot, not full history. Use `/transcript`. (VERIFIED)
6. **Dual output fails open** — a dead reader silently disables the channel and the TUI keeps
   running. Silence ≠ idle. (VERIFIED)
7. **`qwen serve` self-describes as Stage 1 experimental**, *"sized for developers prototyping
   clients against the protocol surface and for local single-user / small-team collaboration"*.
   Production multi-client guarantees are explicitly deferred. Single-user local overnight is exactly
   the supported case — but do not build on it as if it were stable. (VERIFIED)
8. **`--worktree` prompts on exit** (keep or remove) — an interactive dialog in an unattended run.
9. **Shipped docs lag shipped code** (the permissions example in §G). Verify against the bundle.

### Is it plausible to run overnight unattended today?

**Yes — on the control surface it is the most plausible platform in this spike, with one real hole.**

Everything the owner needs for launch, identity, transcript, context, intervention and guardrails is
a documented, programmatic surface with delivery evidence. The hole is **axis E**: he cannot ask how
much capacity is left, and the reset time is prose. Combined with the loss of the free tier, running
Qwen overnight means **spending real money at a rate the orchestrator can measure locally but cannot
bound remotely**.

Recommended shape for a first unattended run:

```bash
QWEN_HOME=~/.qwen-accounts/<role> \
QWEN_CODE_UNATTENDED_RETRY=1 \
OPENAI_API_KEY=… OPENAI_BASE_URL=… \
qwen "<ticket>" \
  --session-id "<lowercase-uuid-the-orchestrator-minted>" \
  --approval-mode auto --sandbox \
  --max-wall-time 45m --max-session-turns 200 --max-tool-calls 400 \
  --fallback-model <cheaper-model> \
  --output-format stream-json \
  --json-file /run/qwen/<id>.events.jsonl \
  --input-file /run/qwen/<id>.input.jsonl
```

Branch on exit code: **53** turn cap, **55** budget, **130** interrupt, 0 success.

---

## What this costs the orchestrator

**Build once, reuse everywhere:**

- A **session-kind router.** Intervention, compaction and question-answering each have a different
  mechanism for `tui` / `headless` / `serve` sessions, and the cross-session protocol explicitly
  refuses inbound to ACP-driven sessions (§8). The adapter must know how a session was launched and
  pick the channel. **This is the single largest piece of Qwen-specific work**, and it has no
  analogue in the Claude Code adapter.
- A **daemon lifecycle manager** — start/health-check/reap one `qwen serve` per account, with a
  `QWEN_HOME` + port registry, because provider auth is workspace-scoped, not session-scoped (axis F).
- A **controller-token bootstrap** — `qwen sessions controllers add --label harness` once per
  `QWEN_HOME`, stored where the orchestrator can read it and the model cannot. The docs warn the
  registry is world-readable-to-the-user by design: *"Do not print `ipcToken` anywhere a model or a
  log can see it."*
- A **budget ledger** replacing the quota gauge — read `~/.qwen/usage_record.jsonl` (or
  `GET /usage/dashboard`), enforce a hand-calibrated per-account ceiling, and treat provider
  exhaustion as an exception path with account rotation. **This is the expensive compromise, and it
  is on the owner's #1 axis.**
- A **fenced-lock recovery policy** — detect `session_writer_conflict` / `session_writer_unavailable`
  and fork to a fresh session id rather than retrying, because there is no force-unlock.

**Free, or nearly:**

- Assigning session ids up front, on both CLI and daemon, with protocol-level verification (B).
- Crash detection by reading one `<sessionId>.runtime.json` (B).
- Reading context fullness *and its breakdown* over HTTP (D).
- Triggering compaction from outside and getting a `PostCompact` webhook as proof (D).
- Answering permission prompts and `ask_user_question` programmatically — **three ways** (G).
- Injecting mid-turn instructions into a running session, with retract (G).
- Per-run account pinning by environment alone, no config mutation, **no Keychain dialog** (F).
- Wall-clock / tool-call / turn budgets with distinct exit codes (A) — for non-daemon launches.
- Per-ticket git worktrees (I).
- An agent board with ask/answer/decline and `--json` (G) — possibly replacing a bespoke queue.

**What to copy into the engine-agnostic design, regardless of whether Qwen is ever used:**

1. **`PostCompact` with `trigger: manual|auto` is the right shape for "compaction with proof".** Make
   it a contract the orchestrator asks every platform for, and record which platforms can honour it.
   Today: Qwen yes, pi partially (a `CompactionEntry` in the session file), Claude Code unknown.
2. **The `delivery_status` state machine** (`pending → held | delivered | denied | refused | expired |
   misaddressed | dropped`) is a better model for "did my nudge land" than a boolean, and it names
   the failure the owner actually hit — `held`, waiting on a human who is asleep.
3. **Distinct exit codes per abort reason** (53/55/130) — cheap, and it turns "the session died" into
   a decision the scheduler can make.
4. **`isEstimated` on the context reading** — a platform that admits when its number is a guess is
   safer to automate against than one that always returns a confident figure.
5. **Quota reading is not a universal capability.** Design the scheduler so a platform may answer
   "I don't know", with a local spend ledger as the fallback. Qwen proves this case is not
   hypothetical.

---

## Sources

All consulted **2026-09-19**. Package-internal paths are relative to
`node_modules/@qwen-code/qwen-code/` in the sandbox at
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/qwen-sandbox/`.

**Run on this machine (VERIFIED):**
- `qwen --version` → `0.24.1`; `qwen --help`; `qwen serve --help`; `qwen sessions --help`;
  `qwen sessions controllers`; `qwen sessions list`; `qwen sessions ps`; `qwen board --help`;
  `qwen board show --json`; `qwen channel --help` — all with `HOME` pointed at a sandbox.
- `npm view @qwen-code/qwen-code --json`, `npm view @qwen-code/sdk`
- `gh api repos/QwenLM/qwen-code`, `gh api repos/QwenLM/qwen-code/releases`
- `ls ~/.claude ~/.codex ~/.gemini ~/.config`; `which -a claude codex gemini opencode cursor-agent amp droid aider qwen kimi`

**Docs shipped inside the package, version-locked to 0.24.1 (VERIFIED):**
- `bundled/qc-helper/docs/qwen-serve.md` (1247 lines) — daemon routes, auth, durability, device flow
- `bundled/qc-helper/docs/features/headless.md` (468) — output formats, budgets, exit codes, retry
- `bundled/qc-helper/docs/features/dual-output.md` (632) — `--json-file` / `--json-fd` / `--input-file`
- `bundled/qc-helper/docs/features/cross-session-protocol.md` (338) — registry, inbox, controller tokens, receipts
- `bundled/qc-helper/docs/features/hooks.md` (1750) — 20 events, HTTP hooks, PreCompact/PostCompact, PermissionRequest
- `bundled/qc-helper/docs/configuration/auth.md` (407) — free-tier discontinuation, plans, endpoints, precedence
- `bundled/qc-helper/docs/configuration/settings.md` (1019) — `context.autoCompactThreshold`
- `bundled/qc-helper/docs/configuration/model-providers.md` (960)
- `bundled/qc-helper/docs/conversations-recovery.md` (102) — writer locks, no force-unlock
- `bundled/qc-helper/docs/features/approval-mode.md`, `sandbox.md`, `sub-agents.md`, `commands.md`,
  `structured-output.md`, `multi-agent-coordination.md`, `status-line.md`, `scheduled-tasks.md`
- `README.md`, `LICENSE`, `sandbox-macos-*.sb`

**Shipped source read directly (VERIFIED):**
- `chunks/server-PN5WV25I.js` — the full HTTP route table, `/session/:id/context-usage`,
  `/mid-turn-message` (16 KiB cap), both `/permission/:requestId` routes, `/usage/dashboard`,
  `QWEN_METHOD_NS = "_qwen/"`, `QWEN_REALTIME_LIMITS`
- `chunks/acpAgent-ANIVCBU3.js` — `buildSessionContextUsageStatus`, `buildSessionStatsStatus`
- `chunks/chunk-TUKPBUHT.js` — `SERVE_STATUS_EXT_METHODS`, `SERVE_CONTROL_EXT_METHODS`
- `chunks/chunk-JDS6RRHY.js` — SDK daemon client, `DaemonSessionIdProtocolError`, `usageDashboard()`
- `chunks/chunk-YSD6IY6F.js` — `isQuotaExhaustedError`, `formatQuotaExhaustedMessage`,
  `getRateLimitErrorDetails`, `getRateLimitRetryDelayMs`
- `chunks/chunk-J6QWYIXU.js` — `usageHistoryService` / `getUsageHistoryPath()`, quota fast-fail path
- `chunks/chunk-3JHSUEQN.js` — `compressCommand` (`supportedModes`), `chats/` dir construction
- `chunks/chunk-CXDWVOBM.js` — `getRuntimeStatusPathState` (`<sessionId>.runtime.json` liveness)
- `chunks/chunk-2UK4NN6N.js` — settings schema (`autoCompactThreshold`)
- `chunks/dist-DBBOFWSC.js` — Octokit route map (the `/rate_limit` false lead)

**Not established (UNKNOWN):**
- Coding Plan / Token Plan prices and exact weekly quota figures — behind the ModelStudio console.
- Whether any Alibaba ModelStudio *cloud* API exposes remaining quota that an orchestrator could poll
  out-of-band. Not reachable from the CLI or its docs; worth one targeted check if Qwen is adopted.
- Qwen model context-window sizes per model id — surfaced per session as `contextWindowSize`, but not
  enumerated in the shipped docs.
