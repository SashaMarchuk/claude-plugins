# Google Gemini CLI — orchestrator platform profile

**Date of research:** 2026-09-19. **Version examined:** `@google/gemini-cli@0.60.0` (npm `latest`,
published 2026-09-15T20:36:40Z). **Machine:** owner's Mac (darwin 25.5.0).

**Installed on this machine?** **No.** `which gemini` → not found (VERIFIED). A stale, empty config
directory exists — see §0.

**How the facts below were obtained.** I installed `@google/gemini-cli@0.60.0` into an isolated
sandbox at
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/gemini-sandbox`
with `HOME` and `GEMINI_CLI_HOME` pointed inside that sandbox, ran its `--help`, its read-only
subcommands, a real `--acp` JSON-RPC handshake, and several headless runs against a deliberately
invalid API key. **Nothing on the owner's machine was read for credentials, modified, or spent.** No
model tokens were consumed: every run that reached the API was rejected at 400 `API_KEY_INVALID`
with `total_tokens: 0`. Flag names and file paths below are quoted from the binary's own output or
from the shipped bundle source (`bundle/*.js`, which retains the original
`packages/core/src/...` / `packages/cli/src/...` module banners), never from prose.

**Evidence tags:** **VERIFIED** — read in shipped source, or run here. **CLAIMED** — asserted by
README/vendor/press only. **UNKNOWN** — could not establish.

---

## 0. The thing you must decide before reading anything else

**Gemini CLI no longer serves the account type the owner would most plausibly use.**

On **2026-05-19** Google announced that **on 2026-06-18** "Gemini CLI and Gemini Code Assist IDE
extensions will stop serving requests" for Google AI Pro subscribers, Google AI Ultra subscribers,
free-tier Gemini Code Assist for individuals, and Code Assist for GitHub. (VERIFIED — official
[Google Developers Blog post][src-blog].) The replacement Google names is **Antigravity CLI**,
distributed from `antigravity.google/download` (VERIFIED, blog). That cutoff was **three months
ago**.

Who still has a working Gemini CLI, quoted from the same post (VERIFIED):

> "If your organization uses Gemini CLI or our IDE extensions via a Gemini Code Assist Standard or
> Enterprise license... your access remains unchanged."

and

> "Gemini CLI will remain accessible via paid Gemini and Gemini Enterprise Agent Platform API keys."

So the platform is alive, actively developed (0.60.0 shipped four days ago; a nightly
`0.62.0-nightly.20260919` was published **today** — VERIFIED, npm `dist-tags`), and is **paid-only**:
a Gemini API key, a Vertex AI project, a Code Assist Standard/Enterprise seat, or a gateway.

**The repository README has not caught up.** Fetched today, it still advertises "60 requests/min and
1,000 requests/day with personal Google account" for OAuth login (VERIFIED — read today at
`raw.githubusercontent.com/google-gemini/gemini-cli/main/README.md`). That claim is stale.
**Do not price or plan this platform from its README.**

### The local footprint on this machine

| Path | Content | Reading |
|---|---|---|
| `~/.gemini/settings.json` | `{"mcpServers": {}}` (mtime 2026-07-11) | Configured once, emptied, never used |
| `~/.gemini/settings.json.bak-pre-pencil-removal-20260711-002233` | one `pencil` MCP server entry | The owner did wire an MCP server in, then removed it 2026-07-11 |
| `~/.gemini/antigravity/mcp_config.json` | `{"mcpServers": {}}` (dated Jan 2026) | An **Antigravity** directory, not Gemini CLI's — it predates the transition and is also empty |

No `oauth_creds.json`, no `google_accounts.json`, no `tmp/`, no `history/`, no binary. (VERIFIED)

---

## A. LAUNCH

### Headless

`-p, --prompt <text>` — help text, quoted exactly: *"Run in non-interactive (headless) mode with the
given prompt. Appended to input on stdin (if any)."* (VERIFIED, `--help`)

Stdin is concatenated ahead of `-p`, so `cat brief.md | gemini -p "now do it"` works.

`-i, --prompt-interactive <text>` — *"Execute the provided prompt and continue in interactive mode."*
This is the attach-a-human path. It **refuses** to run when stdin is a pipe (VERIFIED in source,
`packages/cli/src/gemini.tsx`):

```
Error: The --prompt-interactive flag cannot be used when input is piped from stdin.
```
exiting `42` (`FATAL_INPUT_ERROR`).

Bare `gemini [query..]` with no `-p` runs **interactive** — the positional is only a seed prompt.

### Structured output

`-o, --output-format` with `[choices: "text", "json", "stream-json"]` (VERIFIED, `--help`).

`json` envelope (VERIFIED, `packages/core/src/output/json-formatter.js`):

```json
{ "session_id": "...", "response": "...", "stats": {...}, "error": {...}, "warnings": [...] }
```

`stream-json` is JSONL. The complete emitted vocabulary, exhaustively enumerated from every
`streamFormatter.emitEvent({...})` call site (VERIFIED):

| `type` | Fields |
|---|---|
| `init` | `timestamp`, `session_id`, `model` |
| `message` | `timestamp`, `role` (`user` \| `assistant`), `content`, `delta` |
| `tool_use` | `timestamp`, `tool_name`, `tool_id`, `parameters` |
| `tool_result` | `timestamp`, `tool_id`, `status`, `output`, `error` |
| `error` | `timestamp`, `severity`, `message` |
| `result` | `timestamp`, `status` (`success`\|`error`), `stats`, `error?` |

Real captured output from this machine (VERIFIED):

```json
{"type":"init","timestamp":"2026-09-19T13:22:52.575Z","session_id":"eff575aa-096e-4eb4-bc53-6be291a27edf","model":"auto"}
{"type":"message","timestamp":"2026-09-19T13:22:52.576Z","role":"user","content":"hi"}
{"type":"result","timestamp":"2026-09-19T13:22:52.943Z","status":"error","error":{"type":"unknown","message":"[API Error: ...]"},"stats":{"total_tokens":0,...,"models":{"gemini-3.1-flash-lite":{...},"gemini-3.1-pro-preview":{...}}}}
```

### ⚠ `-o json` loses errors that `-o stream-json` reports

**Verified by running both against the same failing input.** With `-o json`, a mid-turn model-routing
failure produced **zero bytes on stdout** and a raw Node stack trace on stderr, exit **144**. With
`-o stream-json`, the identical failure produced a well-formed `{"type":"result","status":"error",...}`
line on stdout.

```
$ gemini --skip-trust -p "say hi" -o json > out.json 2> err.txt ; echo $?
144
$ wc -c < out.json
0
```

**An orchestrator must use `stream-json`, not `json`.** The `json` path has at least one fatal route
that bypasses its own formatter.

### Exit codes

From `packages/core/src/utils/exitCodes.ts` (VERIFIED):

```js
var ExitCodes2 = { SUCCESS: 0, FATAL_AUTHENTICATION_ERROR: 41, FATAL_INPUT_ERROR: 42,
                   FATAL_CONFIG_ERROR: 52, FATAL_CANCELLATION_ERROR: 130 };
```
plus `RELAUNCH_EXIT_CODE = 199` (VERIFIED). **41** observed here for missing auth. **144** observed
here for a generic fatal — **not in that table**; treat the table as incomplete and branch on
`result.status`, not on the exit code alone.

### ⚠ Trust gate blocks headless runs by default

First headless run in a fresh directory (VERIFIED, real output):

```
Gemini CLI is not running in a trusted directory. To proceed, either use `--skip-trust`,
set the `GEMINI_CLI_TRUST_WORKSPACE=true` environment variable, or trust this directory in
interactive mode.
```

`--skip-trust` is per-run; `GEMINI_CLI_TRUST_WORKSPACE=true` is per-environment; persistent trust
lives in `~/.gemini/trustedFolders.json`, relocatable with `GEMINI_CLI_TRUSTED_FOLDERS_PATH`
(VERIFIED, `Storage.getTrustedFoldersPath()`). **The consequence is larger than "it prompts" — see
§H.**

### Other launch-relevant flags (all VERIFIED from `--help`)

`-m, --model`, `--include-directories`, `-w, --worktree [name]` (*"Start Gemini in a new git
worktree"* — a genuinely useful primitive for parallel unattended lanes), `-s, --sandbox`,
`-e, --extensions <list>`, `--raw-output` / `--accept-raw-output-risk`, `--screen-reader`,
`-d, --debug`.

---

## B. IDENTITY & RESUME

### The orchestrator can name a session before it exists

`--session-id <uuid>` — *"Start a new session with a manually provided UUID."* (VERIFIED, `--help`)

Proven here (VERIFIED):

```
$ gemini --skip-trust --session-id 11111111-2222-3333-4444-555555555555 -p "hi" -o stream-json
{"type":"init",...,"session_id":"11111111-2222-3333-4444-555555555555","model":"auto"}
$ ls ~/.gemini/tmp/proj/chats/
session-2026-09-19T13-23-11111111.jsonl
```

**`--session-id` is create-only.** Reusing an id is refused (VERIFIED, real output):

```
Error starting session: Session ID "11111111-..." already exists. Use --resume to resume it, or provide a different ID.
```
→ exit 42. This is weaker than pi's `--session-id` ("use exact id, creating it if missing"): with
Gemini the orchestrator must remember whether it is creating or resuming and use a *different flag*.

### Resume

`-r, --resume <arg>` — help says *"Use 'latest' for most recent or index number (e.g. --resume 5)"*.
The help is **incomplete**: `SessionSelector.resolveSession` / `findSession` accept **`latest`, a
full UUID, or a 1-based index** (VERIFIED in source — the UUID branch is `sortedSessions.find(s =>
s.id === trimmedIdentifier)`, checked *before* the index parse). Resume by exact UUID works; it is
just undocumented in `--help`.

Companions: `--list-sessions`, `--delete-session <index>`, `--session-file <path>` (imports a session
JSON — note it **assigns a new UUID** and writes a new file, so it forks rather than resumes;
VERIFIED in `resolveSessionId`).

All of these are resolved in `main()` **before** the interactive/headless branch, so
`--session-id` / `--resume` / `--session-file` apply to headless `-p` runs too (VERIFIED).

### ⚠ What does *not* survive a crash — the sharpest finding on this axis

Sessions are scoped to the **project directory**, and a session is kept only if it is *resumable*.
`isResumableMessageRecord` (VERIFIED, `packages/core/.../chatRecordingService`):

- a `user` message counts only if its content is not "ignored user content" (the synthetic
  `<session_context>` preamble is ignored);
- a `gemini` message counts only if it has non-empty text, **or** ≥1 tool call, **or** ≥1 thought.

`deleteCurrentSessionIfNotResumableAsync()` runs in the exit cleanup path, and
`getSessionFiles` filters non-resumable sessions out of listings.

Proven here (VERIFIED): a session whose only turn failed existed on disk as
`session-2026-09-19T13-23-11111111.jsonl`, and yet:

```
$ gemini --skip-trust --resume 11111111-2222-3333-4444-555555555555 -p "hi"
Error resuming session: No previous sessions found for this project.
$ ls ~/.gemini/tmp/proj/chats/      # the file is now gone
```

**Read this carefully against the orchestrator's purpose.** A session that dies *before completing
one model turn* — first request hits the daily cap, network drops, the machine reboots during
startup — leaves **nothing to resume**, and the failed remnant is actively deleted. Resume protects
you against a crash in hour three; it does not protect you against a crash in minute one.

I could **not** test resume after a *successful* turn — that needs a valid paid key and would spend
the owner's money. The code path is unambiguous, but the end-to-end round trip is **UNKNOWN by
direct test**.

### Checkpointing is off by default

`general.checkpointing.enabled`, `default: false`, *"Enable session checkpointing for recovery"*,
`requiresRestart: true` (VERIFIED, settings schema). Checkpoints land in
`~/.gemini/tmp/<project>/checkpoints/` (VERIFIED, `Storage.getProjectTempCheckpointsDir()`) and are
restored with `/restore`. An orchestrator that wants file-level rollback must turn this on itself.

Note also `cleanupCheckpoints()` runs on every startup (VERIFIED) — checkpoints are garbage-collected
without being asked.

---

## C. TRANSCRIPT

### Where it lives

Project identity moved from a hash to a **human-readable slug** in this version. Layout, all VERIFIED
from `packages/core/src/config/storage.ts` and confirmed on disk:

```
~/.gemini/projects.json                          # { "projects": { "<abs path>": "<slug>" } }
~/.gemini/tmp/<slug>/.project_root               # marker file holding the absolute path back
~/.gemini/tmp/<slug>/chats/session-<ISO>-<id8>.jsonl     # the transcript
~/.gemini/tmp/<slug>/chats/<parentSessionId>/    # subagent transcripts
~/.gemini/tmp/<slug>/logs/session-<id>.jsonl
~/.gemini/tmp/<slug>/tool-outputs/session-<id>/
~/.gemini/tmp/<slug>/checkpoints/
~/.gemini/tmp/<slug>/<sessionId>/{plans,tracker,tasks}/
~/.gemini/history/<slug>/
```

Real `projects.json` written here (VERIFIED):

```json
{ "projects": { "/private/tmp/.../gemini-sandbox/proj": "proj" } }
```

**The filename is not the session id.** It is `session-` + an ISO-ish timestamp + the **first 8 hex
characters** of the UUID. To go from a known session id to its file, glob
`chats/session-*-${id.slice(0,8)}.jsonl` — that is exactly what `SessionSelector.sessionExists` does
(VERIFIED).

### The much easier route: hooks hand you the path

Every hook payload is built by `createBaseInput` (VERIFIED):

```js
{ session_id, transcript_path, cwd, hook_event_name, timestamp }
```

where `transcript_path` is
`geminiClient.getChatRecordingService().getConversationFilePath()`. **A `SessionStart` command hook
gives the supervisor the session id and the exact transcript path with no path arithmetic**, and
`SessionStartSource` tells it *why* the session started: `"startup" | "resume" | "clear"` (VERIFIED).
That is the single cleanest wiring on this platform.

### ⚠ The format is not an append-only event log

Captured verbatim from a real session file (VERIFIED):

```json
{"sessionId":"248aa3f6-...","projectHash":"80c6b997...","startTime":"2026-09-19T13:23:02.365Z","lastUpdated":"...","kind":"main"}
{"$set":{"messages":[{"id":"d049...","timestamp":"...","type":"user","content":[{"text":"<session_context>..."}]}]}}
{"sessionId":"248aa3f6-...", ... ,"lastUpdated":"2026-09-19T13:23:02.366Z","kind":"main"}
{"$set":{"messages":[ ...the whole array again... ]}}
```

It is a JSONL file of alternating **metadata headers** and **`$set` deltas that replace the entire
`messages` array**. A live reader must take the **last** `$set` and treat it as the whole
conversation — concatenating lines produces duplicates. `loadConversationRecord` also understands
rewind records (`isRewindRecord`) and per-message kinds, so hand-rolled parsing will drift from the
CLI's own semantics. Size grows superlinearly with turns, since every flush rewrites the history.

`kind: "main"` distinguishes the primary session from subagent records.

### Live reading over ACP

In `--acp` mode the agent streams `session/update` notifications to the client
(`CLIENT_METHODS.session_update`, VERIFIED), including `agent_message_chunk` content and tool-call
updates. That is a push feed, strictly better than tailing the JSONL, and it is available only in
ACP mode.

---

## D. CONTEXT — *(owner-critical)*

### Reading how full the window is: **yes, indirectly, and it is genuinely good**

The number the TUI itself uses is `chat.getLastPromptTokenCount()` against
`tokenLimit(model)` (VERIFIED). `tokenLimit` (VERIFIED):

```js
var DEFAULT_TOKEN_LIMIT = 1048576;     // 1,048,576 for the Gemini 2.5/3.x families
var GEMMA_4_TOKEN_LIMIT = 256e3;       // 256,000 for local Gemma-4 routing
```

Two supervisor-readable sources of that number:

1. **`AfterModel` hook.** Its payload carries `llm_response.usageMetadata` with
   `{ promptTokenCount, candidatesTokenCount, totalTokenCount }` (VERIFIED,
   `HookTranslatorGenAIv1.toHookLLMResponse`). `promptTokenCount / 1048576` **is** context fullness,
   computed from outside the process, per turn, with no polling.
2. **`stream-json` `result.stats`** (end of run only) and, over ACP, `session/prompt`'s
   `_meta.quota.token_count.{input_tokens,output_tokens}` plus `model_usage[]` per response
   (VERIFIED in `acpSession.ts`).

The TUI also exposes a `context-used` status item described as *"Percentage of context window
used"* (VERIFIED, footer schema) — confirming this is the vendor's own definition, not my
arithmetic.

**Verdict: axis D's read half is SOLVED on Gemini, better than on most of the field.**

### Triggering compaction from outside: **no**

- Auto-compaction exists: threshold `model.compressionThreshold`, `default: 0.5`, described as *"The
  fraction of context usage at which to trigger context compression"*, `requiresRestart: true`
  (VERIFIED, settings schema; the code constant is `DEFAULT_COMPRESSION_TOKEN_THRESHOLD = 0.5`).
  The supervisor can **tune** this by writing settings before launch — that is real control, just not
  imperative control.
- `/compress` (aliases `/summarize`, **`/compact`**) exists as a built-in slash command
  (VERIFIED, `compressCommand.ts`).

**But it cannot be driven headlessly.** Two independent reasons, both verified:

1. `compressCommand.action` writes into `context.ui` and **returns nothing**. The headless
   `handleSlashCommand` only forwards a result of type `submit_prompt`; anything else either throws
   `FatalInputError` ("Exiting due to command result that is not supported in non-interactive") or
   — as here — returns `undefined`, after which the raw text falls through and is sent to the model
   as a prompt. Worse, the action kicks off `void (async () => { ... tryCompressChat ... })()`, an
   **un-awaited** IIFE racing process exit.
2. Proven empirically (VERIFIED, real captured output):

```json
{"type":"init",...,"session_id":"78dff4a9-...","model":"auto"}
{"type":"message",...,"role":"user","content":"/compact"}     ← sent to the MODEL, verbatim
{"type":"result",...,"status":"error",...}
```

`gemini -p "/compact"` does **not** compact. It prompts the model with the four characters
`/compact`.

Over **ACP** it is worse: the ACP command registry contains only `memory`, `extensions`, `init`,
`restore`, `about`, `help` (VERIFIED, `acp/commands/commandRegistry.ts`). **There is no `compact`
over ACP at all.**

### Proof that compaction happened: **partial, and the obvious hook is a trap**

`PreCompress` is a first-class hook event, and its payload carries
`trigger: "manual" | "auto"` (VERIFIED, `PreCompressTrigger`). That looks like the proof mechanism.
It is not, quite — read the call order (VERIFIED, `chatCompressionService`):

```js
const trigger = force ? PreCompressTrigger.Manual : PreCompressTrigger.Auto;
await config2.getHookSystem()?.firePreCompressEvent(trigger);          // ← fires FIRST
const originalTokenCount = chat.getLastPromptTokenCount();
if (!force) {
  const threshold = await config2.getCompressionThreshold() ?? DEFAULT_COMPRESSION_TOKEN_THRESHOLD;
  if (originalTokenCount < threshold * tokenLimit(model)) {
    return { ..., compressionStatus: CompressionStatus.NOOP };        // ← nothing happened
  }
}
```

**`PreCompress` fires before the threshold check, so it also fires on every NOOP.** A hook that
merely counts `PreCompress` events will report compactions that never occurred. The honest proof is
the *token count dropping* across two consecutive `AfterModel` payloads — which the orchestrator can
see, and which is real evidence rather than an intention.

### Workaround and its cost

The realistic pattern on Gemini is **handoff, not compaction**: watch `promptTokenCount` from
`AfterModel`, and when it crosses your own line, stop the session and start a fresh one seeded with
a summary you generate yourself. Cost: you write and maintain the summarizer, you pay for the
summarization turn, and you lose the CLI's own compaction quality (`getCompressionPrompt`,
`COMPRESSION_PRESERVE_THRESHOLD = 0.3`, a 50k-token function-response budget) unless you replicate
it. In `--acp` mode the handoff is cheaper: `session/new` costs one round trip and you already hold
the transcript.

---

## E. QUOTA — *(owner-critical)*

### There is a real quota endpoint, and it is not on the CLI surface

`packages/core/src/code_assist/server.ts` (VERIFIED):

```js
var CODE_ASSIST_ENDPOINT   = "https://cloudcode-pa.googleapis.com";
var CODE_ASSIST_API_VERSION = "v1internal";
getBaseUrl()  { return `${process.env["CODE_ASSIST_ENDPOINT"] ?? CODE_ASSIST_ENDPOINT}/${process.env["CODE_ASSIST_API_VERSION"] || CODE_ASSIST_API_VERSION}`; }
getMethodUrl(method) { return `${this.getBaseUrl()}:${method}`; }
async retrieveUserQuota(req) { return this.requestPost("retrieveUserQuota", req); }
```

So the call is:

```
POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota
Authorization: Bearer <OAuth token from ~/.gemini/oauth_creds.json>
Content-Type: application/json

{"project": "<cloudaicompanionProject id>"}
```

Response shape, read off the parser in `Config.refreshUserQuota()` (VERIFIED):

```jsonc
{ "buckets": [ { "modelId": "gemini-3.1-pro-preview",
                 "remainingFraction": 0.42,      // always present when the bucket counts
                 "remainingAmount": "123",       // optional; when absent, limit is normalised to 100
                 "resetTime": "2026-09-20T00:00:00Z" } ] }
```

Per-model buckets, each with remaining, an implied limit (`remaining / remainingFraction`), and a
**reset time**. `Config.getQuotaRemaining() / getQuotaLimit() / getQuotaResetTime()` expose the
aggregate; `getRemainingQuotaForModel(modelId)` exposes one bucket; `refreshUserQuotaIfStale(30_000)`
is the cache policy (VERIFIED).

Two convenience facts: the TUI's `quota` status item is described as *"Percentage of daily limit
used (not shown when unavailable)"*, and its dialog text reads *"Usage limits span all sessions and
reset daily."* (VERIFIED). **The window is daily, pooled across sessions.** There is a companion
`loadCodeAssist` call with `mode: "HEALTH_CHECK"` that returns `paidTier.availableCredits` for the
G1 AI-credits balance, and a `billing.overageStrategy` setting (`ask` | `always` | `never`, default
`ask`) governing whether exhausted quota silently spills onto paid credits (VERIFIED). **For an
unattended run, `never` or `always` is a decision the owner must make deliberately — the default
`ask` will block.**

### ⚠ But none of it is reachable from the CLI

- **No flag** prints quota. `--help` has nothing.
- **`gemini -p "/stats"` does not work.** Verified empirically — captured output:

```json
{"type":"message",...,"role":"user","content":"/stats"}   ← "/stats" went to the MODEL
```
  `statsCommand.action` calls `context.ui.addItem({type:"stats", ...})`, and the headless
  `createNonInteractiveUI()` only prints items whose type is `error`, `warning` or `info` and which
  carry a `text` field. A `stats` item has neither. It prints **nothing** and then bills you for a
  model turn on the string `/stats`.
- **Not over ACP either** — `stats` is not in the ACP command registry (VERIFIED, §D).
- `coreEvents.emitQuotaChanged(remaining, limit, resetTime)` exists (VERIFIED) but is an in-process
  EventEmitter. No hook event surfaces it; the `HookEventName` enum has no quota member (VERIFIED,
  full enum in §G).

**The orchestrator must therefore call `cloudcode-pa.googleapis.com` itself**, and to do that it
needs two things the CLI keeps to itself: a live OAuth access token (refresh flow in
`~/.gemini/oauth_creds.json`) and the `cloudaicompanionProject` id (established by `loadCodeAssist` /
`onboardUser`, or supplied as `GOOGLE_CLOUD_PROJECT`). This is exactly the shape of the owner's
existing `claude-limits` helper — same pattern, different endpoint — so it is familiar work, but it
is **work**, on an **undocumented `v1internal` surface** that Google can change without notice.

**And it only exists for Code Assist / OAuth auth.** With a plain `GEMINI_API_KEY` against
`generativelanguage.googleapis.com`, `getCodeAssistServer(this)` returns nothing and
`refreshUserQuota()` returns `undefined` immediately (VERIFIED). **On the API-key path there is no
remaining-quota reading at all** — which, per §0, is the path most likely to be available to the
owner. That is the single worst interaction in this profile.

### Limit-hit signalling in band

A 429 is mapped to a JSON-RPC `RequestError(429, "Rate limit exceeded. Try again later.")` in ACP
mode (VERIFIED) and appears as `{"type":"result","status":"error",...}` in stream-json. **No reset
time accompanies it** — the reset time only comes from `retrieveUserQuota`. HTTP retry policy
retries `[429,429]`, `[499,499]`, `[500,599]` three times (VERIFIED), so a limit-hit costs several
seconds of silent retry before surfacing.

There is also a `ProQuotaDialog` and a model-fallback path in the TUI, and `overageMenuRequest` /
`emptyWalletRequest` dialogs for credits (VERIFIED) — all of which are **blocking UI** and therefore
unattended hazards if a session is ever run interactively.

---

## F. ACCOUNTS — *(owner-critical)*

### The lever exists and it is clean: `GEMINI_CLI_HOME`

`packages/core/src/utils/paths.ts` (VERIFIED):

```js
var GEMINI_DIR = ".gemini";
function homedir() {
  const envHome = process.env["GEMINI_CLI_HOME"];
  if (envHome) { return envHome; }
  return os.homedir();
}
```

Everything account-shaped hangs off `Storage.getGlobalGeminiDir()` = `homedir() + "/.gemini"`:
`oauth_creds.json`, `google_accounts.json`, `settings.json`, `installation_id`,
`mcp-oauth-tokens.json`, `a2a-oauth-tokens.json`, `trustedFolders.json`, `projects.json`, `tmp/`,
`history/`, `commands/`, `skills/`, `agents/`, `policies/` (VERIFIED, full `Storage` class).

Proven here (VERIFIED): with `GEMINI_CLI_HOME=$SB/home`, the CLI created
`$SB/home/.gemini/{projects.json,tmp,history}` and reported its settings path as
`$SB/home/.gemini/settings.json` — the real `~/.gemini` was untouched.

**So: one `GEMINI_CLI_HOME` per account, set at spawn time, and a new session is pinned to that
account purely by environment.** This is structurally identical to the `CLAUDE_CONFIG_DIR` mechanism
the owner already automates with a profile switcher, which means axis F is mostly a **configuration** problem
here, not an engineering one.

Why you need it: `google_accounts.json` is `{ active: string | null, old: string[] }` and
`oauth_creds.json` is a single file (VERIFIED). **One OAuth identity per config home, full stop.**
Concurrent accounts require concurrent homes.

### ⚠ One real inconsistency in `GEMINI_CLI_HOME`

`homedir()` treats it as **HOME** (so settings are at `$GEMINI_CLI_HOME/.gemini/settings.json`), but
the early memory-sizing bootstrap in `bundle/gemini.js` treats it as the **config dir**:

```js
const baseDir = process.env["GEMINI_CLI_HOME"] || join(os.homedir(), ".gemini");
const settingsPath = join(baseDir, "settings.json");   // $GEMINI_CLI_HOME/settings.json
```

(VERIFIED, both call sites read.) Harmless today — it only governs `advanced.autoConfigureMemory` —
but it means the variable's contract is not what one of its own readers believes. Do not build
anything on `$GEMINI_CLI_HOME/settings.json`.

### Other per-session switches (all VERIFIED, `getAuthTypeFromEnv`)

```js
GOOGLE_GENAI_USE_GCA=true      → oauth-personal (Code Assist)
GOOGLE_GENAI_USE_VERTEXAI=true → vertex-ai
GOOGLE_GEMINI_BASE_URL=<url>   → gateway
GEMINI_API_KEY=<key>           → gemini-api-key
CLOUD_SHELL / GEMINI_CLI_USE_COMPUTE_ADC=true → compute-adc
```

Plus `GOOGLE_API_KEY`, `GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`,
`GOOGLE_APPLICATION_CREDENTIALS`, `GOOGLE_CLOUD_QUOTA_PROJECT`, `GEMINI_DEFAULT_AUTH_TYPE`,
`GEMINI_CLI_CUSTOM_HEADERS`, `GOOGLE_VERTEX_BASE_URL`, `GOOGLE_GENAI_API_VERSION` (VERIFIED, env
scan of the bundle).

**`GOOGLE_GEMINI_BASE_URL` → `AuthType.GATEWAY` is worth flagging to the owner.** It is the same
trick as his working Xiaomi MiMo config: point the CLI at an arbitrary endpoint and hand it custom
headers. Gemini CLI has a *named, first-class* auth type for it, advertised in the ACP handshake as
`{"id":"gateway","name":"AI API Gateway","_meta":{"gateway":{"protocol":"google","restartRequired":"false"}}}`
(VERIFIED — captured from a real `initialize` response here). For a provider-agnostic orchestrator,
that makes Gemini CLI a *host* for Google-protocol endpoints, not only for Google.

### Changing a running session's account

**Only over ACP, and only partially.** `authenticate` is an ACP agent method and it calls
`config.refreshAuth(method, apiKey, baseUrl, headers)` on the live process, accepting
`_meta["api-key"]` and `_meta.gateway.{baseUrl,headers}` (VERIFIED) — and the gateway method
advertises `restartRequired: "false"`. But `authenticate` is scoped to the **agent**, not to an
existing session, and existing `Session` objects hold a `config` created at `session/new`. Whether
already-open sessions pick up the new credentials is **UNKNOWN** (untestable without two valid
accounts). In headless mode the account is fixed for the life of the process: **kill and relaunch.**

---

## G. INTERVENTION — *(owner-critical)*

### Headless: nothing

A `-p` run is one shot. There is no input channel: `--help` has **no `--input-format`**, and the
bundle contains no `input-format` string at all (VERIFIED — searched). `stream-json` is
**output-only**, unlike Claude Code's bidirectional variant. Stdin in headless mode is used for
exactly one thing: if it is a TTY, a keypress handler that treats Ctrl-C / ESC as *abort*
(VERIFIED, `setupStdinCancellation`). You can cancel a headless run. You cannot talk to it.

### ACP: this is the real answer, and it is strong

`--acp` — *"Starts the agent in ACP mode"* (VERIFIED, `--help`; `--experimental-acp` is the
deprecated alias). It speaks **Agent Client Protocol v1** over newline-delimited JSON-RPC on
stdin/stdout, via the bundled `@agentclientprotocol/sdk`.

**I ran the handshake on this machine. Verbatim captured response (VERIFIED):**

```json
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,
 "authMethods":[{"id":"oauth-personal",...},{"id":"gemini-api-key",...},
                {"id":"vertex-ai",...},{"id":"gateway",...}],
 "agentInfo":{"name":"gemini-cli","title":"Gemini CLI","version":"0.60.0"},
 "agentCapabilities":{"loadSession":true,
   "promptCapabilities":{"image":true,"audio":true,"embeddedContext":true},
   "mcpCapabilities":{"http":true,"sse":true}}}}
```

**And a real `session/new` (VERIFIED, captured):**

```json
{"jsonrpc":"2.0","id":2,"result":{"sessionId":"248aa3f6-a199-4e0c-af24-dc8025936d41",
 "modes":{"availableModes":[{"id":"default","name":"Default","description":"Prompts for approval"},
                            {"id":"autoEdit",...},{"id":"yolo",...},{"id":"plan","description":"Read-only mode"}],
          "currentModeId":"default"},
 "models":{"availableModels":[{"modelId":"auto","name":"Auto","description":"Let Gemini CLI decide the best model for the task: gemini-3.1-pro-preview, gemini-3.5-flash"},
                              {"modelId":"gemini-3.1-pro-preview"},{"modelId":"gemini-3-flash-preview"},
                              {"modelId":"gemini-2.5-pro"},{"modelId":"gemini-3.5-flash"},{"modelId":"gemini-3.1-flash-lite"}],
           "currentModelId":"auto"}}}
```

and the transcript file `chats/session-2026-09-19T13-23-248aa3f6.jsonl` appeared immediately.

#### What the agent implements

Read directly off the `GeminiAgent` class (VERIFIED, `acp/acpRpcDispatcher.ts`):

| ACP method | Implemented? |
|---|---|
| `initialize` | ✅ |
| `authenticate` | ✅ (api-key and gateway payloads) |
| `session/new` | ✅ (agent chooses the UUID) |
| `session/load` | ✅ (`loadSession: true`) |
| `session/prompt` | ✅ |
| `session/cancel` | ✅ (`cancelPendingPrompt`) |
| `session/set_mode` | ✅ (`default`/`autoEdit`/`yolo`/`plan`) |
| `session/set_model` | ✅ (`unstable_setSessionModel`) |
| `session/list` | ❌ → `methodNotFound` |
| `session/resume` | ❌ |
| `session/fork` | ❌ |
| `session/close` | ❌ |
| `session/set_config_option` | ❌ |

The SDK *defines* all of them; the agent implements the top eight.

#### Sending an instruction into a running session — and knowing it arrived

`session/prompt` is a JSON-RPC **request**: it carries an `id` and the orchestrator gets a correlated
result back. Arrival is not inferred, it is acknowledged. That is exactly what the owner asked for.

**⚠ One critical semantic.** From `acpSession.ts` (VERIFIED), the *first line* of `prompt` is:

```js
async prompt(params) {
  this.pendingPrompt?.abort();          // ← the in-flight turn is ABORTED, not queued
  ...
}
```

A mid-run `session/prompt` **interrupts** the current turn. There is no queue and no
"append to the current turn" mode. For a supervisor that wants to nudge ("you've been on this file
for 40 minutes"), the cost is the work in flight. The alternative — wait for the turn to end — means
your nudge lands late by definition. **Design around it: nudge between turns, or accept the abort.**

The prompt response carries usage back:

```jsonc
{ "stopReason": "end_turn" | "cancelled" | "max_turn_requests",
  "_meta": { "quota": { "token_count": { "input_tokens": N, "output_tokens": M },
                        "model_usage": [ { "model": "...", "token_count": {...} } ] } } }
```

#### Answering a permission prompt programmatically — **yes, cleanly**

This is the axis the owner's current harness fails, and ACP answers it properly. `session/request_permission`
is a **client** method: the agent sends it *to the orchestrator* and blocks on the reply
(VERIFIED, `acpSession.ts`):

```js
const params = { sessionId: this.id,
                 options: toPermissionOptions(confirmationDetails, config, enablePermanentToolApproval),
                 toolCall: { toolCallId, status: "pending", title, content, locations, kind } };
const output = RequestPermissionResponseSchema.parse(await this.connection.requestPermission(params));
const outcome = output.outcome.outcome === "cancelled" ? Cancel
              : z.nativeEnum(ToolConfirmationOutcome).parse(output.outcome.optionId);
await confirmationDetails.onConfirm(outcome);
await updatePolicy(tool, outcome, confirmationDetails, ...);   // ← the answer can be made durable
```

Outcomes the orchestrator may return: `proceed_once`, `proceed_always`, `proceed_always_and_save`,
`proceed_always_server`, `proceed_always_tool`, `cancel` (VERIFIED). `proceed_always_and_save`
**writes the decision into the policy file**, so the supervisor teaches the session once and is not
asked again.

The agent also asks permission for reads outside the workspace, with its own synthetic tool call
(*"Allow access to absolute path: …"*) — so a supervisor holding this channel controls file scope
too.

#### The trade-off

A session is **either** an attachable TUI **or** an ACP-driven agent. `--acp` replaces the
interactive UI. The owner's "a terminal I can attach to and type into" and "a protocol the
supervisor drives" are, on Gemini CLI, **mutually exclusive per process**. The compensation is that
ACP's `session/load` plus the on-disk transcript makes a handover possible: kill the ACP session,
relaunch `gemini --resume <uuid>` in a visible terminal, and a human takes over the same
conversation.

#### Clarifying questions

There is no distinct "the agent asked you a question" event. A question arrives as ordinary
`session/update` assistant text and the turn ends with `stopReason: "end_turn"`. Detecting it is
heuristic (the orchestrator must read the text); answering it is trivial (another `session/prompt`).
Permission requests are the only *structured* interrupt.

---

## H. GUARDRAILS

### Approval modes

`--approval-mode` with `[choices: "default", "auto_edit", "yolo", "plan"]` (VERIFIED, `--help`;
internally `ApprovalMode = default | autoEdit | yolo | plan`). Descriptions from the live ACP
`session/new` response (VERIFIED): default *"Prompts for approval"*, autoEdit *"Auto-approves edit
tools"*, yolo *"Auto-approves all tools"*, plan *"Read-only mode"*. `-y, --yolo` is the shorthand.
Settable mid-session over ACP via `session/set_mode`, and mode changes are echoed back to the client
as `[MODE_UPDATE] <mode>` (VERIFIED).

**`plan` deserves attention for an unattended queue**: a genuinely read-only mode, enabled by default
(`general.plan.enabled: true`), is the cheapest way to let a session reconnoitre a ticket overnight
without write risk.

### Policy Engine

`--allowed-tools` is **deprecated** and says so at runtime (VERIFIED, real warning):

> `Warning: --allowed-tools cli argument and tools.allowed in settings.json are deprecated and will
> be removed in 1.0: Migrate to Policy Engine: https://geminicli.com/docs/core/policy-engine/`

The replacement: `--policy <paths>` and `--admin-policy <paths>`, TOML files, loaded from
`~/.gemini/policies/`, `<project>/.gemini/policies/`, extension `policies/` directories, and the
system policy dir (`/Library/Application Support/GeminiCli/policies` on macOS) (VERIFIED).
`PolicyEngine.check(toolCall, serverName, annotations, subagent)` returns `allow` / `deny` /
`ask_user`, with decisions persisted to `policies/auto-saved.toml`, and integrity tracked in
`policy_integrity.json` (VERIFIED). The `--admin-policy` / system-settings split
(`GEMINI_CLI_SYSTEM_SETTINGS_PATH`) is a genuine two-tier model: an orchestrator can pin rules a
session cannot relax.

### Sandboxing

`-s, --sandbox`, `GEMINI_SANDBOX`, `GEMINI_SANDBOX_IMAGE`, `GEMINI_SANDBOX_PROXY_COMMAND`. Valid
commands (VERIFIED): `docker`, `podman`, `sandbox-exec`, `runsc`, `lxc`, `windows-native`.
**On macOS, `sandbox-exec` is auto-selected when present** (VERIFIED), with built-in seatbelt
profiles: `permissive-open`, `permissive-closed`, `permissive-proxied`, `restrictive-open`,
`restrictive-closed`, `restrictive-proxied`, `strict-open`, `strict-proxied`. Configurable
`allowedPaths`, `networkAccess`, `customImage`. This is the most complete sandboxing story in the
field so far and it costs nothing extra on this machine.

### ⚠ Trust gates far more than execution

Untrusted-folder behaviour, captured verbatim from `gemini skills list` here (VERIFIED):

```
Skipping project agents due to untrusted folder. To enable, ensure that the project root is trusted.
Project hooks disabled because the folder is not trusted.
No skills discovered.
```

**In an untrusted folder, project agents, project hooks and project skills are all silently
disabled** — and headless runs are refused outright. The failure is not loud: a session started with
`--skip-trust` still runs, but without the hooks the orchestrator was relying on for §C and §D. An
orchestrator must write `trustedFolders.json` (or set `GEMINI_CLI_TRUST_WORKSPACE=true`) **and**
verify its hooks actually fired, rather than assuming `--skip-trust` is equivalent.

There is also a credential-path guard: `SENSITIVE_SETTINGS_FILENAMES` blocks tool access to
`oauth_creds.json`, `google_accounts.json`, `gemini-credentials.json`, `mcp-oauth-tokens.json`,
`a2a-oauth-tokens.json`, and `AcpFileSystemService` refuses to proxy reads inside `~/.gemini`
(VERIFIED). The agent cannot read its own tokens. Good.

### What it will do unattended without asking

With `--yolo` / `--approval-mode yolo`, everything. With `default` in **headless** mode, an
`ask_user` decision resolves to `confirmed: false` — the tool is **denied**, not queued — because
nothing can answer (VERIFIED, message-bus handler). In **ACP** mode the same decision becomes a
`session/request_permission` to the orchestrator. That asymmetry is the strongest argument for
running ACP rather than `-p`.

---

## I. EXTENSIBILITY

Subcommand surface (VERIFIED, `--help` of each):

- **`gemini mcp`** — `add <name> <commandOrUrl> [args...]`, `remove`, `list`, `enable`, `disable`.
  HTTP and SSE transports advertised in the ACP handshake; MCP servers can also be injected
  **per-session** through `session/new`'s `mcpServers` parameter (VERIFIED) — the orchestrator can
  give each role a different toolset without touching config.
- **`gemini extensions`** — `install <git-url|path>`, `uninstall`, `list`, `update [--all]`,
  `disable/enable [--scope]`, `link <path>`, `new <path> [template]`, `validate <path>`,
  `config [name] [setting]`. Extensions may bundle `agents/`, `skills/`, `policies/`, `commands/`,
  and hook `env` settings.
- **`gemini skills`** — `list [--all]`, `enable`, `disable`, `install <git-url|path>`, `link`,
  `uninstall`. Skills resolve from `~/.gemini/skills`, `<project>/.gemini/skills`, and `.agents/skills`.
- **`gemini hooks migrate`** — *"Migrate hooks from Claude Code to Gemini CLI"*. The hook model is
  deliberately Claude-Code-shaped.
- **`gemini gemma`** — `setup`, `start`, `stop`, `status`, `logs` for a **local LiteRT-LM Gemma**
  server (binary under `~/.gemini/bin/litert/`). A local-model escape hatch inside a Google CLI is
  unusual and is worth knowing about for zero-quota work.

**Hooks** — the full `HookEventName` enum (VERIFIED):

```
BeforeTool, AfterTool, BeforeAgent, AfterAgent, Notification,
SessionStart, SessionEnd, PreCompress, BeforeModel, AfterModel, BeforeToolSelection
```

Configured as a top-level `hooks` object in settings, each event an array, `mergeStrategy: CONCAT`
across scopes, types `command` and `runtime`. Hook output supports
`{ continue, stopReason, suppressOutput, systemMessage, decision, reason, hookSpecificOutput }` —
with `BeforeTool` able to *rewrite* `tool_input` and `BeforeModel` able to return a **synthetic LLM
response**, short-circuiting the model entirely (VERIFIED). That last one is a powerful and
under-advertised capability: a supervisor can intercept a model call and answer it itself.

**Settings precedence** (VERIFIED): `SystemDefaults` → `System` → `User` → `Workspace` → `Session`,
with `system-defaults.json` and a system dir at `/Library/Application Support/GeminiCli` on macOS,
both relocatable via `GEMINI_CLI_SYSTEM_SETTINGS_PATH`.

**Subagents** exist (`~/.gemini/agents/`, `<project>/.gemini/agents/`,
`loadAgentsFromDirectory`, `renderSubAgents` in the system prompt, `acknowledgments/agents.json`,
subagent transcripts nested under `chats/<parentSessionId>/`) (VERIFIED). A GSD-style subagent-heavy
workflow has the primitives it needs — custom commands (TOML, via `FileCommandLoader`), skills,
subagents, MCP, hooks, and `GEMINI.md` context files. **Whether a GSD-shaped engine runs *well*
inside it is UNKNOWN** — untested.

**`-w, --worktree`** deserves a mention under extensibility too: the CLI will create and enter a git
worktree for you, which is the natural isolation unit for parallel unattended lanes.

---

## J. OPERATIONAL REALITY

| | |
|---|---|
| **License** | Apache-2.0 (VERIFIED, npm) |
| **Repo** | `github.com/google-gemini/gemini-cli` (VERIFIED) |
| **Version / cadence** | `0.60.0` 2026-09-15; `0.59.0` 2026-09-08; `0.58.0` 2026-09-01 — roughly weekly. `nightly` 0.62.0 published today, `preview` 0.61.0-preview.0. (VERIFIED, npm `time`) |
| **Runtime** | Node `>=20` (VERIFIED, `engines`). Bin `gemini` → `bundle/gemini.js` |
| **Install footprint** | 7 npm packages; `bundle/` is ~200 MB across 76 JS files, including a full DevTools frontend (`index.js` alone is large). **Not a small install.** (VERIFIED on disk) |
| **Install** | `npm i -g @google/gemini-cli`, `npx @google/gemini-cli`, `brew install gemini-cli`, `sudo port install gemini-cli` (VERIFIED, README — but see §0 before installing) |
| **macOS** | Fully supported; `sandbox-exec` auto-detected; darwin system config at `/Library/Application Support/GeminiCli` (VERIFIED) |
| **Cost model** | Paid only, post-2026-06-18 (§0). Gemini API key, Vertex AI, Code Assist Standard/Enterprise, or a gateway. Daily pooled quota on the Code Assist path; G1 credits as overage |
| **Models** | Live list from this machine: `auto` (router), `gemini-3.1-pro-preview`, `gemini-3-flash-preview`, `gemini-3.5-flash`, `gemini-3.1-flash-lite`, `gemini-2.5-pro`. Context limit **1,048,576** tokens (VERIFIED) |

### Known unattended-run failure modes (all observed or read here)

1. **Untrusted folder refuses headless runs** and silently disables project hooks/agents/skills
   (§H). The silent half is the dangerous half.
2. **`-o json` can emit nothing on fatal errors** while exiting non-zero with a raw stack trace on
   stderr (§A). Use `stream-json`.
3. **Sessions with no completed model turn are deleted and unresumable** (§B). Early failures leave
   no recovery point.
4. **`--list-sessions` reliably prints a stack trace** for the current session's not-yet-written
   file (VERIFIED, real output: `Error loading conversation record from JSONL: [Error: ENOENT ...
   session-2026-09-19T13-23-fa41225c.jsonl]`), and prints `No previous sessions found for this
   project.` **without a trailing newline**. Any parser must tolerate both.
5. **Interactive sessions exit 0 on TTY loss.** `setupTtyCheck` polls, and when neither stdin nor
   stdout is a TTY it calls `gracefulShutdown`, which exits `ExitCodes.SUCCESS` (VERIFIED). A
   terminal that closes overnight produces a **session that looks like it succeeded**. Supervise on
   the transcript and the `result` event, never on the exit code of an attached session.
6. **First run litters.** A single first invocation left **14** orphan `projects.json.<uuid>.tmp`
   files in `~/.gemini/` (VERIFIED, counted). Subsequent runs added none, so it is a one-time
   migration artefact — but it is 14 files from one `--list-sessions`.
7. **Blocking dialogs in interactive mode**: `ProQuotaDialog`, `overageMenuRequest`,
   `emptyWalletRequest`, auth-consent, extension-update confirmations. With
   `billing.overageStrategy` at its default `ask`, quota exhaustion **waits for a human**.
8. **`RELAUNCH_EXIT_CODE = 199`** — the CLI relaunches itself in some configurations
   (`relaunchOnExitCode`, `GEMINI_CLI_NO_RELAUNCH`). A supervisor tracking PIDs must expect the
   process to replace itself.

### Is it plausible to run overnight unattended today?

**Yes — over ACP, on a paid key, with the trust file written and hooks verified.** The ACP channel is
the best intervention surface found in this scan so far, permissions are answerable programmatically,
sandboxing is real, and context fullness is readable. That is a strong platform.

**But the answer is governed by §0 and §E, not by §G.** If the owner does not hold a Code Assist
Standard/Enterprise seat or a paid API key, the platform does not serve him at all. And if he holds
only an **API key**, `retrieveUserQuota` does not exist on that path — meaning the axis he called
non-negotiable is unavailable precisely in the configuration he is most likely to have. Gemini CLI
is a platform to orchestrate **if the account situation is right**; the account situation is the
gate, and it is the first thing to settle.

---

## What this costs the orchestrator

| Axis | Verdict | What it costs to support |
|---|---|---|
| **A. Launch** | Good | Must use `-o stream-json` (the `json` path drops fatal errors). Must set `--skip-trust`/`GEMINI_CLI_TRUST_WORKSPACE`/`trustedFolders.json`, and verify hooks fired rather than assume trust. Headless and attachable are separate processes. |
| **B. Resume** | Good with a hole | `--session-id` to name a new session, `--resume <uuid>` to reattach — **two different flags for one concept**, so the launcher must know which state it is in. Sessions are cwd-scoped. **Budget for the case where there is nothing to resume**: keep the ticket, not the session, as the unit of recovery. |
| **C. Transcript** | Good | Take `transcript_path` from a `SessionStart` hook rather than computing it. Write a reader that takes the **last `$set`**, not a line-concatenator. Over ACP, prefer `session/update` and skip the file. |
| **D. Context** | Read: solved. Trigger: no. | Read `promptTokenCount` from an `AfterModel` hook ÷ 1,048,576 — cheap and accurate. For compaction, set `model.compressionThreshold` before launch and otherwise **implement handoff yourself**: detect the line, summarise, `session/new`. Do **not** trust `PreCompress` as proof — it fires on NOOPs; prove it with the token count dropping. |
| **E. Quota** | Endpoint exists, CLI surface does not | Build an out-of-band client for `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` with the OAuth token and project id — undocumented `v1internal`, may break. **On the API-key path there is nothing to read; fall back to counting your own turns and treating a 429 as the signal.** Set `billing.overageStrategy` deliberately. |
| **F. Accounts** | Solved | One `GEMINI_CLI_HOME` per account, exported at spawn. Same shape as the owner's existing profile-switcher/`CLAUDE_CONFIG_DIR` machinery, so mostly configuration. Running sessions cannot switch: kill and relaunch. |
| **G. Intervention** | **Best in the scan so far — via ACP** | Implement an ACP client: `initialize`, `session/new`, `session/prompt`, `session/cancel`, and — the important one — **serve** `session/request_permission`, `session/update`, `fs/*`. Accept that a mid-run `session/prompt` **aborts** the turn in flight, and that ACP mode forfeits the attachable TUI. |
| **H. Guardrails** | Strong | Learn the Policy Engine TOML (`--allowed-tools` is deprecated). Use `sandbox-exec` on macOS — it is free here. Use `plan` mode for read-only reconnaissance. Remember trust gates hooks and agents, not just execution. |
| **I. Extensibility** | Strong | MCP, skills, extensions, subagents, custom commands, Claude-Code-shaped hooks with a migrator, per-session MCP injection, and `--worktree` isolation. Whether a GSD-shaped engine runs well inside it is untested. |
| **J. Operational** | Gated by account type | ~200 MB install, weekly releases against an unstable surface, and — decisively — **no consumer access since 2026-06-18**. |

### The three things to tell the owner

1. **Settle the account question first.** Gemini CLI stopped serving Pro/Ultra/free-Code-Assist on
   2026-06-18. Without a Code Assist Standard/Enterprise seat or a paid API key there is nothing to
   orchestrate, and its own README still says otherwise.
2. **Its ACP mode is the reference answer to axis G in this scan** — better than the current
   harness's stranded-text nudge, because `session/request_permission` lets the supervisor *answer*
   the session's own question over a correlated channel, and `proceed_always_and_save` makes the
   answer stick. Even if Gemini CLI is never adopted, **ACP itself is worth adopting as the
   orchestrator's protocol**: it is a published standard, several agents speak it, and it is exactly
   the shape the interview asked for.
3. **Quota is the mirror image of Claude Code.** On Claude the owner already reads
   `five_hour.utilization` / `seven_day.utilization` from a documented-enough OAuth endpoint. On
   Gemini the equivalent exists (`v1internal:retrieveUserQuota`, daily buckets, `resetTime`) but is
   unreachable from the CLI, requires reconstructing auth by hand, and **does not exist at all on
   the API-key path**. Plan for "count your own turns and treat 429 as the signal" as the realistic
   baseline.

---

## Sources

All retrieved or executed **2026-09-19**.

**Primary — run on this machine (VERIFIED):**
1. `@google/gemini-cli@0.60.0`, installed to an isolated sandbox: `gemini --help`;
   `gemini {mcp,extensions,skills,hooks,gemma} --help`; `gemini {mcp,extensions,skills} list`;
   `gemini --list-sessions`; `gemini -p … -o {json,stream-json}`; `gemini --session-id …`;
   `gemini --resume …`; `gemini --acp` with real `initialize` and `session/new` JSON-RPC requests.
2. Shipped bundle source, `node_modules/@google/gemini-cli/bundle/*.js`, which preserves its
   `packages/core/src/…` and `packages/cli/src/…` module banners. Files quoted above:
   `config/storage.ts`, `utils/paths.ts`, `utils/exitCodes.ts`, `code_assist/server.ts`,
   `services/chatRecordingService.ts`, `utils/sessionOperations.ts`, `context/chatCompressionService.ts`,
   `hooks/types.ts`, `output/json-formatter.js`, `output/stream-json-formatter.js`,
   `acp/acpRpcDispatcher.ts`, `acp/acpSession.ts`, `acp/acpSessionManager.ts`,
   `acp/acpFileSystemService.ts`, `acp/commands/commandRegistry.ts`, `nonInteractiveCliCommands.ts`,
   `validateNonInterActiveAuth.ts`, `ui/commands/compressCommand.ts`, `ui/commands/statsCommand`,
   `utils/sessions.ts`, the settings schema, and `@agentclientprotocol/sdk/dist/schema/index.js`.
3. Owner's machine, read-only: `~/.gemini/` contents; `which gemini` (absent).

**Primary — published by the vendor:**
4. [Google Developers Blog, "An important update: Transitioning Gemini CLI to Antigravity CLI"][src-blog]
   — announced 2026-05-19, cutoff 2026-06-18, tiers affected, API-key access retained.
5. npm registry metadata for `@google/gemini-cli` — version, `dist-tags`, `time`, `bin`, `engines`,
   `license`, `repository`.
6. `https://raw.githubusercontent.com/google-gemini/gemini-cli/main/README.md` — install commands and
   auth options; **its quota figures are stale and are not relied on here.**

**Secondary (CLAIMED, used only to corroborate the blog post, never as sole evidence):**
7. Press coverage of the transition (digitalapplied.com, aibuilderclub.com, thegputrade.com,
   aifreeapi.com) — consistent on the June 18 cutoff and on Antigravity CLI being a closed-source Go
   rewrite with the binary `agy` and a weekly compute cap. **Binary name, install command and
   license for Antigravity CLI remain UNKNOWN from primary sources.**

[src-blog]: https://developers.googleblog.com/an-important-update-transitioning-gemini-cli-to-antigravity-cli/

---

## Open questions this pass could not close

| # | Question | Why it matters | Axis |
|---|---|---|---|
| 1 | Does `--resume <uuid>` actually restore a session that completed a real model turn? | The whole crash-recovery story rests on it; only the failure case was testable without spending money | B |
| 2 | Does ACP `authenticate` re-credential **already-open** sessions, or only new ones? | Decides whether account switching ever avoids a relaunch | F |
| 3 | Is `--resume` honoured when combined with `--acp`, or does ACP ignore it in favour of `session/load`? | Decides the reattach recipe | B, G |
| 4 | Exact request/response schema and stability of `v1internal:retrieveUserQuota`; does an API-key-only account have *any* quota endpoint? | This is the owner's non-negotiable axis, and the answer looks like "no" on the likely path | E |
| 5 | What exit code 144 actually denotes (it is absent from `ExitCodes`) | Supervisors branch on exit codes | A, J |
| 6 | Does a GSD-style subagent-heavy workflow run acceptably inside Gemini's agents/skills/commands model? | Decides whether the owner's engine ports at all | I |
| 7 | Antigravity CLI: install command, binary, headless flags, session/resume, ACP support, quota reading | If Gemini CLI is account-gated out, `agy` is the actual Google target — and it remains the largest gap in the whole scan | all |
