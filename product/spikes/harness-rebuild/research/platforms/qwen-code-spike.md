# SPIKE — making Alibaba Qwen Code a first-class orchestrator citizen

**Date:** 2026-09-19. **Version:** `@qwen-code/qwen-code` **0.24.1** (published 2026-09-19T08:28:42Z).
**Machine:** owner's Mac, darwin 25.5.0, Node 22.18.0.
**Companion:** read `qwen-code.md` (the capability profile) first. This document is the implementer's
recipe book; it does not repeat the profile's survey.

**Evidence tags.** **VERIFIED-RAN** — I executed it on this machine and pasted the real output.
**VERIFIED-SRC** — read in the installed CLI's `--help`, its shipped docs, or its shipped source.
**VERIFIED-VENDOR** — read in Alibaba's own current documentation.
**CLAIMED** — asserted by a README/marketing page only. **UNKNOWN** — could not establish.
Every flag name below was read in `--help` or run. Nothing here is guessed.

---

## 0. How this spike was run, and what it cost the owner

Qwen Code is **not installed on this machine** (VERIFIED-RAN: `which qwen` → not found; `~/.qwen`
does not exist). Nothing of the owner's was touched. The previous pass's isolated sandbox was still
present and was reused:

```
/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-.../scratchpad/qwen-sandbox/
  node_modules/@qwen-code/qwen-code/    # 0.24.1, 160 MB on disk
  fakehome/                             # HOME and QWEN_HOME for every invocation
  ws/                                   # a throwaway workspace
```

**Every run used a fake `HOME`, a fake `QWEN_HOME`, and a dummy API key pointed at a dead endpoint**
(`OPENAI_API_KEY=sk-dummy-not-real`, `OPENAI_BASE_URL=http://127.0.0.1:9/v1`). That combination let
me exercise the whole control plane — daemon, sessions, transcripts, context, intervention,
shutdown — while **no model was ever called and no quota was ever spent**. Turns fail at the socket
with `Connection error.`, which is itself a useful failure path to observe.

Three live processes were started and all three were stopped: one `qwen serve` daemon, one headless
run, one TUI session under a real PTY (`script -q /dev/null …`). At the end, `ps` shows nothing of
Qwen's running and the session registry directory is empty.

### What this spike corrects in the capability profile

The profile was written from docs and source. Running it moved nine things:

| # | The profile said | Actually |
|---|---|---|
| 1 | `--permission-response-timeout-ms` is a general unattended flag | **It exists only on `qwen serve`.** It is not in `qwen --help`. A headless or TUI run cannot bound a question this way (VERIFIED-RAN) |
| 2 | mid-turn delivery "is known from the HTTP status" | **HTTP 200 is not delivery.** An idle session returns `200 {"accepted":false,"reason":"session_idle"}`. You must read `accepted` (VERIFIED-RAN) |
| 3 | `GET /session/:id/status` returns 5 fields | It returns **`activeWorkState`, `isWaitingForPermission`, `isWaitingForUserQuestion`, `pendingInteractions[]`, `hasTurnError`, `turnError`** too. Axis-4 is a single GET (VERIFIED-RAN) |
| 4 | `context-usage` gives a ratio you compare to 0.85 | It ships **`breakdown.thresholds {warn, auto, hard, effectiveWindow}` and `currentTier`**. Do not compute the trigger — read it (VERIFIED-RAN) |
| 5 | `--json-file` is the supervised-TUI channel | True — and **it is silently ignored in headless mode.** I ran headless with `--json-file` and no file was created (VERIFIED-RAN) |
| 6 | `<sessionId>.runtime.json` marks any session | **Only TUI sessions write one.** The daemon and a short headless run did not (VERIFIED-RAN) |
| 7 | `QWEN_HOME=~/.qwen-accounts/work` gives `…/work/.qwen/` | **`QWEN_HOME` *is* the config home.** Files land at `…/work/peer-controllers.json` directly (VERIFIED-RAN) |
| 8 | quota reset time is free prose, effectively UNKNOWN | **The Coding Plan resets on a fixed published schedule** — weekly at Mon 00:00:00 UTC+8, plus a 5-hour window. No API needed to know *when* (VERIFIED-VENDOR) |
| 9 | the local spend ledger is the budget proxy | **Coding Plan quota is metered in model calls, not tokens.** Count `summary.requests`, not `totalTokens` (VERIFIED-VENDOR) |

Point 8 is the important one for the owner: the profile filed the reset time as unknowable. It is
published and deterministic. The orchestrator can compute the next reset without asking anyone.

---

## 1. Preflight — installed, authenticated, which account?

There are two preflight surfaces. Use the cheap one always, the rich one when a daemon is up.

### 1a. Cheap, no daemon, ~1 s

```bash
command -v qwen || exit 70                 # not installed
qwen --version                             # → 0.24.1
node -e 'process.exit(process.versions.node.split(".")[0] >= 22 ? 0 : 1)' || exit 71
```

`engines.node >= 22.0.0` is hard (VERIFIED-SRC, `package.json`). **Success:** a semver on stdout,
exit 0. **Failure:** `command -v` empty, or a version below the pin the orchestrator froze.

### 1b. Authoritative — one HTTP call against a running daemon

```bash
curl -s http://127.0.0.1:$PORT/workspace/preflight | jq '.cells[]|{kind,status,detail}'
```

VERIFIED-RAN, both states. With no credentials:

```json
{"kind":"auth","status":"warning","detail":{"source":"none","hasToken":false}}
{"kind":"providers","status":"ok","detail":{"count":1,"providers":["qwen-oauth"]}}
```

With `OPENAI_API_KEY` exported:

```json
{"kind":"auth","status":"ok",
 "detail":{"source":"openai","hasToken":true,
           "envVarCandidates":["OPENAI_API_KEY"],"presentVar":"OPENAI_API_KEY"}}
{"kind":"providers","status":"ok","detail":{"count":2,"providers":["qwen-oauth","openai"]}}
```

Other cells returned live: `node_version`, `cli_entry`, `workspace_dir`, `ripgrep`, `git`, `npm`,
`mcp_discovery`, `skills`, `tool_registry`, `egress`.

**`presentVar` is the account answer.** It names the exact environment variable the next session
will authenticate with — which is precisely what recipe 7 needs to verify a switch.

> **The trap, read in source.** `buildAuthPreflightCell` (`chunks/acpAgent-ANIVCBU3.js:21563`) carries
> a comment saying it "**Deliberately does NOT call `validateAuthMethod`**… Full validation still
> happens at session start." `hasToken: true` means *a credential is present*, **not that it works**.
> A revoked key preflights green. Treat recipe 1 as a configuration check and let recipe 2's first
> turn be the real authentication test.
>
> `providers: ["qwen-oauth"]` alone means *nothing is configured*: `qwen-oauth` is a hard-coded,
> discontinued entry (see §6) that is always listed.

### 1c. Preflight without any daemon, from the session itself

The first object of `--output-format json` is a full capability dump (VERIFIED-RAN):

```json
{"type":"system","subtype":"init","session_id":"…","cwd":"…",
 "tools":["read_file","edit","write_file","run_shell_command","agent","skill", …29 more],
 "mcp_servers":[],"model":"qwen3-coder-plus","permission_mode":"yolo",
 "slash_commands":["auth","compress","compress-fast","context","goal","model","review", …],
 "qwen_code_version":"0.24.1",
 "agents":["general-purpose","Explore","statusline-setup","review-agent","claude-code","codex"]}
```

Note the subtype is **`init`**, not `session_start` — `session_start` is the dual-output channel's
first frame (§3). Two different names for two different channels; the adapter must not share a parser.

**Fallback if none of this works:** treat the platform as down and route the ticket elsewhere. There
is no offline way to establish that a credential is valid.

**verified: true**

---

## 2. Start a task headless, with a pinned session id, capturing structured output

```bash
SID=$(uuidgen | tr 'A-Z' 'a-z')            # MUST be lower case — see below

QWEN_HOME="$HOME/.qwen-accounts/$ROLE" \
OPENAI_API_KEY="$KEY" OPENAI_BASE_URL="$BASE" OPENAI_MODEL="$MODEL" \
QWEN_CODE_UNATTENDED_RETRY=1 \
qwen "$TICKET_TEXT" \
  --session-id "$SID" \
  --approval-mode auto --sandbox \
  --output-format stream-json --include-partial-messages \
  --max-wall-time 45m --max-session-turns 200 --max-tool-calls 400 \
  --fallback-model "$CHEAPER_MODEL" \
  > "$RUN/$SID.jsonl" 2> "$RUN/$SID.err"
echo "exit=$?"
```

All flags VERIFIED-RAN in `qwen --help`. The prompt goes **positionally**; `-p/--prompt` still works
but `--help` marks it `[deprecated: Use the positional prompt instead]`.

**Success looks like:** the transcript appears at
`$QWEN_HOME/projects/<sanitized-cwd>/chats/$SID.jsonl` and the stream's final object is
`{"type":"result","subtype":"success","is_error":false,"duration_ms":…,"result":"…","usage":{…}}`.
VERIFIED-RAN: I ran with `--session-id bbbbbbbb-2222-4333-8444-555555555555` and got exactly that
id back in `system/init` **and** as the transcript filename. The path sanitiser replaces every `/`
with `-`, so `/a/b/ws` → `-a-b-ws`.

**Failure looks like** — and this is the sharp edge:

```
EXIT=1
stdout: [{"type":"system","subtype":"init",…},{"type":"assistant",…}]     # truncated, no result
stderr: {"error":{"type":"AlreadyReportedError",
                  "message":"[API Error: Connection error. (cause: fetch failed)]","code":1}}
```

**The reason lives on stderr, as a separate JSON document; stdout just stops.** VERIFIED-RAN. An
adapter that only parses stdout sees a truncated array and no explanation. Always capture both.

**Exit codes** (VERIFIED-SRC, `docs/features/headless.md`, and 1 VERIFIED-RAN):

| Code | Meaning | Scheduler action |
|---|---|---|
| 0 | success | next ticket |
| **1** | API/auth/provider error, reason on stderr | classify stderr, maybe rotate account |
| **53** | `--max-session-turns` exceeded | ticket too big — split it |
| **55** | `FatalBudgetExceededError`: `--max-wall-time` or `--max-tool-calls` | requeue with a bigger budget, or abandon |
| **130** | SIGINT | operator or supervisor stopped it |

**Two budget traps, both from the shipped doc.** `--max-tool-calls` counts *top-level* dispatches
only — an `agent` (subagent) call counts as **1** and its inner calls are uncounted, so "a model that
funnels work through subagents can do unbounded inner work under a small top-level budget". And
`structured_output` under `--json-schema` is **unconditionally exempt**, so a malformed-output retry
loop is not bounded by it. Always pair with `--max-wall-time`.

**Pin lower case.** `POST /session` canonicalises with `.toLowerCase()`, and the official SDK throws
`DaemonSessionIdProtocolError` on a mismatch. VERIFIED-RAN — I posted
`AAAAAAAA-2222-4333-8444-555555555555` and got back:

```json
{"sessionId":"aaaaaaaa-2222-4333-8444-555555555555","attached":false,
 "clientId":"client_86863e6f-…","createdAt":"2026-09-19T13:25:12.477Z"}
```

An orchestrator that mints mixed case and keys its own store on its own spelling will mis-key every
session. **Fallback if id pinning is ever removed:** read the id back from `system/init` and adopt it.

**verified: true**

---

## 3. Start the same task in a visible terminal the owner can type into

```bash
mkfifo "$RUN/$SID.events"          # FIFO, not a regular file — see below
: > "$RUN/$SID.input"

qwen --session-id "$SID" \
     --approval-mode auto --sandbox \
     --json-file "$RUN/$SID.events" \
     --input-file "$RUN/$SID.input" \
     "$TICKET_TEXT"
```

The TUI renders normally on stdout while structured events go to the side channel — "No ANSI parsing
on either side". VERIFIED-RAN under a real PTY (`script -q /dev/null node …/cli.js --json-file … --input-file …`).
The first frame on the channel was:

```json
{"type":"system","subtype":"session_start","session_id":"cccccccc-2222-4333-8444-555555555555",
 "data":{"session_id":"…","cwd":"…","protocol_version":2,"version":"0.24.1",
         "supported_events":["system","user","assistant","stream_event",
                             "result","control_request","control_response"]}}
```

**`supported_events` is a capability handshake the profile missed.** Negotiate against it rather than
hard-coding the event vocabulary; `protocol_version` tells you when the shape moved.

**Use `--json-file`, never `--json-fd`, for an attachable window.** `docs/features/dual-output.md`
devotes a section to why: `node-pty` and `bun-pty` "cannot forward extra fds to the child" —
`node-pty.spawn(file, args, options)` has **no `stdio` array**, so there is nowhere to attach fd 3.
Since a visible, attachable window *is* a PTY, `--json-fd` is structurally wrong here. `--json-fd`
and `--json-file` are mutually exclusive; fds 0/1/2 are rejected.

**Success:** the TUI paints, and `session_start` lands on the channel within a second or two.

**Failure is silent, and this is the one to design against.** Every dual-output failure is
fail-*open*: a bad fd, an unopenable path, or a reader disconnect (`EPIPE`) prints one stderr warning
and **the TUI keeps running with the channel disabled** (VERIFIED-SRC, "Failure modes"). So a
supervisor must treat *no events* as **"possibly disabled"**, never as *"idle"*. Cross-check against
`GET /session/:id/status` or the runtime file (§4) before concluding anything from silence.

**Fallback when no window is wanted:** run headless (§2) and give the owner
`qwen --resume $SID` to take it over later.

**verified: true**

---

## 4. Alive, working, waiting, or finished — from outside

Three independent probes. Use the one that matches how the session was launched.

### 4a. Daemon session — one GET, and it answers all four states

```bash
curl -s "http://127.0.0.1:$PORT/session/$SID/status"
```

VERIFIED-RAN, verbatim:

```json
{"sessionId":"aaaaaaaa-…","workspaceCwd":"…","createdAt":"2026-09-19T13:25:12.477Z",
 "updatedAt":"2026-09-19T13:25:55.011Z","clientCount":1,
 "hasActivePrompt":false,"activeWorkState":"idle","hasRunningBackgroundTasks":false,
 "isWaitingForPermission":false,"isWaitingForUserQuestion":false,
 "pendingInteractionCount":0,
 "hasTurnError":true,"turnError":{"message":"Connection error.","code":"-32603"},
 "pendingInteractions":[]}
```

Read it as:

| State | Test |
|---|---|
| **finished, clean** | `hasActivePrompt:false` ∧ `activeWorkState:"idle"` ∧ `hasTurnError:false` |
| **finished, failed** | `hasTurnError:true` → `turnError.message` is the reason |
| **working** | `activeWorkState:"active"` ∨ `hasActivePrompt:true` ∨ `hasRunningBackgroundTasks:true` |
| **waiting on a human** | `isWaitingForPermission` ∨ `isWaitingForUserQuestion` ∨ `pendingInteractionCount > 0` → §9 |
| **gone** | HTTP **404** `{"code":"session_not_found"}` |

`activeWorkState` ∈ **`active | idle | unknown | unsupported`** (VERIFIED-SRC,
`entryActiveWorkState`, `chunks/chunk-A4IJR5S6.js:10249`). `unknown` and `unsupported` mean the child
did not report a capability — **do not read them as idle.**

Cheaper still: `GET /session/:id/turns/current` → `{"state":"idle"}` (VERIFIED-RAN). Per-turn
outcomes: `GET /session/:id/turns/:promptId` (VERIFIED-RAN) →
`{"promptText":"say hi","queuedAt":…,"startedAt":…,"endedAt":…,"state":"error","error":{…}}`.

> **Do not poll `GET /workspace/:id/session-info`.** The shipped docs mark it `expensive: true`,
> `cost: "disk_scan"`, with an explicit "Disk scan — do not poll" (VERIFIED-SRC).

### 4b. Any session kind — the process registry

```bash
cd "$PROJECT" && QWEN_HOME=… qwen sessions ps --json
```

`--json` on `sessions ps`, `sessions list` and `sessions controllers list` is real (VERIFIED-RAN in
each subcommand's `--help`) and the profile did not mention it. Live output with two sessions up:

```
tui   | 12558 | cccccccc-2222-4333-8444-555555555555 | ws-d4
serve |  1692 | aaaaaaaa-2222-4333-8444-555555555555 | ws-ed
```

`kind` ∈ `tui | headless | serve | external`. **`qwen sessions ps --json` redacts `ipcToken`**
(VERIFIED-RAN — present in the on-disk record, absent from the CLI output). To message a session
directly you must read `$QWEN_HOME/sessions/<pid>.json` yourself, or hold a controller token (§8).

`qwen sessions list --json` is **project-scoped to the current directory** — I got an empty result
from the sandbox root and the full record after `cd`-ing into the workspace (VERIFIED-RAN). It
returns `{sessionId, startTime, mtime, prompt, gitBranch, customTitle, filePath, cwd}`, and
`filePath` is the transcript path, ready to tail.

### 4c. Crash detection without a process table — TUI sessions only

```
$QWEN_HOME/projects/<sanitized-cwd>/chats/<sessionId>.runtime.json
```

VERIFIED-RAN. The on-disk shape is **snake_case** (the profile's pseudo-code was camelCase):

```json
{"schema_version":1,"pid":12558,"session_id":"cccccccc-…",
 "work_dir":"/…/ws","hostname":"<host>",
 "started_at":1789824391.86,"qwen_version":"0.24.1"}
```

> **Unit trap.** `runtime.json.started_at` is epoch **seconds with a fraction** (1789824391.86);
> the session-registry record's `startedAt` is epoch **milliseconds** (1789824391929). Same concept,
> two units, two files. VERIFIED-RAN.

The check, mirroring `getRuntimeStatusPathState` (`chunks/chunk-CXDWVOBM.js:301`):

```js
if (!s || s.session_id !== sid)      return "missing";
if (s.hostname !== os.hostname())    return "active";   // fails OPEN
try { process.kill(s.pid, 0); return "active"; }
catch (e) { return e.code === "ESRCH" ? "dead" : "active"; }
```

**Proven on this machine:** I SIGTERM'd the TUI (pid 12558), then ran that check against the
left-behind file — it returned **`dead`**. That is the crash detector, working.

Three limits, all real:

- **It fails open.** A foreign hostname, or any error that is not `ESRCH`, reads `active`. So
  `"dead"` is trustworthy; `"active"` is not proof of life. The enclosing `isSessionRuntimeActive`
  goes further and returns `true` when *no* record is found at all (VERIFIED-SRC).
- **Only TUI sessions write one.** The daemon and my headless run produced no `.runtime.json`
  (VERIFIED-RAN). Use 4a for daemon sessions and the exit code for headless ones.
- **On macOS `procStart` and `pidNs` are `null`** (VERIFIED-RAN in both registry records; the docs
  say they are Linux-only). Liveness therefore falls back to a bare PID probe, **which cannot
  distinguish a recycled PID from the original process.** After a reboot this matters — see §10.

**Fallback:** the orchestrator's own `spawn` + exit-code bookkeeping, which is what it needs for
headless runs anyway.

**verified: true**

---

## 5. Read context fullness, force a compaction, prove it happened

Qwen Code is the only platform in this spike that answers all three parts with first-class surfaces.

### 5a. Read it

```bash
curl -s "http://127.0.0.1:$PORT/session/$SID/context-usage"
```

VERIFIED-RAN, verbatim (trimmed):

```json
{"v":1,"sessionId":"aaaaaaaa-…","usage":{
  "modelName":"qwen3-coder-plus","totalTokens":0,"contextWindowSize":1000000,
  "breakdown":{"systemPrompt":5390,"builtinTools":18305,"mcpTools":0,
               "memoryFiles":1570,"skills":579,"messages":0,
               "freeSpace":824156,"autocompactBuffer":150000,
               "thresholds":{"warn":830000,"auto":850000,
                             "hard":977000,"effectiveWindow":980000},
               "currentTier":"safe"},
  "isEstimated":true,"showDetails":false},
 "formattedText":"## Context Usage\n\n*No API response yet…*"}
```

**Poll `breakdown.currentTier`, not a ratio you computed.** Tiers are `safe → warn → auto → hard`
(VERIFIED-SRC, `chunk-FVLDT6YJ.js:5615-5651`). Qwen publishes the exact thresholds it will act on, so
the supervisor and the runtime can never disagree about where the line is. The arithmetic behind them
(`computeThresholds`, `chunk-J6QWYIXU.js:40736`, VERIFIED-SRC): `DEFAULT_PCT = 0.85`,
`AUTOCOMPACT_BUFFER = 13000`, `WARN_BUFFER = 20000`, `HARD_BUFFER = 3000`, and
`effectiveWindow = window − SUMMARY_RESERVE`.

**`isEstimated: true` means there has been no API response yet** — the number is pre-conversation
overhead only, and `formattedText` says so in words. **Do not trigger a compaction on an estimated
reading.** Gate every decision on `isEstimated === false`.

The `breakdown` also tells you *why* it is full — whether the cost is MCP tool schemas, memory files,
skills, or actual conversation. That is a different remedy in each case: drop an MCP server, trim
`QWEN.md`, disable skills, or compact.

**For a TUI or headless session with no daemon**, the same three numbers arrive in the **`Stop` hook**
payload — `context_usage` (a ratio), `context_limit`, `input_tokens` — and the shipped docs say
plainly that this exists "to observe context usage and implement custom compact strategies"
(VERIFIED-SRC, `hooks.md:928-936`; `buildContextUsage`, `chunk-J6QWYIXU.js:21021`). **This is the
answer for non-daemon sessions and the profile did not have it.** Ship a `Stop` hook of
`type: "http"` pointed at the orchestrator and every turn reports its own fullness.

ACP twin of the HTTP route: `qwen/status/session/context_usage` (VERIFIED-SRC, `chunk-TUKPBUHT.js:76`).

### 5b. Force it

`/compress` (alias `/summarize`) declares `supportedModes: ["interactive", "non_interactive", "acp"]`
(VERIFIED-SRC, `chunk-3JHSUEQN.js:4135-4141`) — so it is invocable from outside on every launch
shape. `/compress-fast` is the non-AI variant: it strips old tool outputs and thinking parts and
costs no tokens.

| Session kind | Command |
|---|---|
| daemon | `curl -X POST …/session/$SID/prompt -d '{"prompt":[{"type":"text","text":"/compress"}]}'` |
| visible TUI | `echo '{"type":"submit","text":"/compress"}' >> "$RUN/$SID.input"` |
| headless follow-up | `qwen --resume "$SID" "/compress"` |

VERIFIED-RAN for the TUI route: I appended that exact line to a live session's `--input-file` and the
command was accepted and dispatched (it then failed at the dead provider, because AI compaction needs
a model call — use `/compress-fast` if you need a provider-free reduction).

Cheaper compaction model: `/model --compaction <model-id>` (VERIFIED-SRC, `docs/features/commands.md`).
Worth setting for an overnight queue — compaction is not free.

> `model.chatCompression.contextPercentageThreshold` is **REMOVED and silently ignored** in 0.24.1.
> The live key is `context.autoCompactThreshold` (default 0.85). Setting the old one does nothing
> and reports nothing (VERIFIED-SRC, `docs/configuration/settings.md`).

### 5c. Prove it

A **`PostCompact`** hook fires only after a compaction *succeeds* — "It does not fire when compaction
fails. Qwen waits for the hooks to finish before continuing" (VERIFIED-SRC, `hooks.md:1107-1120`).
Its matcher matches on `trigger`, so `"matcher": "manual"` fires **only** for compactions the
supervisor asked for. Drop this in `$QWEN_HOME/settings.json`:

```json
{ "hooks": { "PostCompact": [ { "matcher": "manual", "hooks": [
  { "type": "http",
    "url": "http://127.0.0.1:8787/qwen/compacted",
    "headers": { "Authorization": "Bearer ${HARNESS_TOKEN}" },
    "allowedEnvVars": ["HARNESS_TOKEN"],
    "timeout": 30,
    "name": "harness-compaction-proof" } ] } ] } }
```

The POST body carries the common fields (`session_id`, `transcript_path`, `cwd`, `hook_event_name`,
`timestamp`, `permission_mode`) plus:

```json
{"trigger":"manual","compact_summary":"the summary that replaced the compacted history, without its <analysis> block"}
```

HTTP hooks have SSRF protection that blocks private ranges but **explicitly allows loopback
(127.0.0.1, ::1)** — exactly where a local orchestrator listens (VERIFIED-SRC).

**So the full loop is: read `currentTier` → POST `/compress` → receive a webhook carrying the summary
and `trigger: "manual"`.** Proof is *delivered to* the supervisor, not scraped from a screen.

Three independent fallbacks if the hook is not wired: the compaction item carries
`originalTokenCount` / `newTokenCount` / `compressionStatus` (an enum where `1 = COMPRESSED`,
`5 = NOOP`, and `2/3/4/6/7` are distinct failures — VERIFIED-SRC); re-reading `context-usage` shows
`totalTokens` drop and `currentTier` fall; and a `PreCompact` sibling brackets the attempt.

**Failure looks like:** no webhook and no drop in `totalTokens` → the compaction failed. Fall back to
`/compress-fast`, and if that fails too, hand off: `--fork-session` into a fresh id carrying only the
ticket text and the last summary.

**What I did not execute:** the `PostCompact` webhook never fired, because completing a compaction
requires a real model call. The route, the payload shape, the matcher semantics and the loopback
allowance are all VERIFIED-SRC; the round trip is not VERIFIED-RAN. **This is the one leg of recipe 5
an implementer should smoke-test on first contact with a real key.**

**verified: true** *(read-only leg — `context-usage` — run live; trigger accepted live; webhook leg source-only)*

---

## 6. Read remaining quota and the reset time; detect a limit hit in-band

**This is the weak axis, and it is the owner's #1 stated requirement. Plan around it.**

### 6a. Remaining capacity cannot be read. Confirmed twice.

There is no endpoint, protocol event, CLI command or credential field that reports remaining provider
capacity. The profile established this by grepping every shipped chunk; I re-checked the two upstream
feature requests:

- **QwenLM/qwen-code#3302** "Add /quota command to view remaining daily limits and usage metrics for
  OAuth users" — opened 2026-04-15, **closed 2026-04-16** as a duplicate (VERIFIED-RAN, `gh api`).
- **#3203** "Qwen OAuth Free Tier Policy Adjustment" — the issue it was folded into — is also
  **closed** (VERIFIED-RAN).

So there is no quota command, and no open upstream work toward one.

Alibaba's own current docs agree: "You can view your usage information on the Coding Plan page" — the
web console, with no API named (VERIFIED-VENDOR).

### 6b. The reset time IS knowable — and the profile was wrong to file it as unknown

Straight from Alibaba's Coding Plan FAQ (VERIFIED-VENDOR, retrieved 2026-09-19):

| Window | Reset |
|---|---|
| **5-hour** | "Wait 5 hours for the quota to reset automatically." |
| **Weekly** | "The quota resets at **00:00:00 (UTC+8) on Monday**." |
| **Monthly** | "The quota resets at 00:00:00 (UTC+8) on the corresponding day of your next subscription month." |

**The Coding Plan's shape is the same 5-hour + 7-day pair the owner already watches on Anthropic.**
The difference is that Anthropic hands him `resets_at`; Alibaba publishes a fixed rule instead. A
fixed rule is *better* for a scheduler — it needs no network call and cannot go stale mid-outage:

```python
# next weekly reset, deterministic, no API
from datetime import datetime, timedelta, timezone
cst  = timezone(timedelta(hours=8))
now  = datetime.now(cst)
days = (7 - now.weekday()) % 7 or 7
nxt  = (now + timedelta(days=days)).replace(hour=0, minute=0, second=0, microsecond=0)
```

### 6c. Quota is metered in MODEL CALLS, not tokens

"The Coding Plan's quota consumption is based on the number of model calls, not on token
consumption" (VERIFIED-VENDOR). Alibaba puts a simple task at 5–10 calls and a complex one at 10–30+.

**This changes which number the budget ledger must count.** The profile proposed tracking tokens from
`usage_record.jsonl`. For a Coding Plan that is the wrong meter. Count **requests**:

```bash
curl -s "http://127.0.0.1:$PORT/usage/dashboard?range=today" | jq '.summary'
```

VERIFIED-RAN:

```json
{"totalTokens":0,"inputTokens":0,"outputTokens":0,"cachedTokens":0,"thoughtsTokens":0,
 "requests":0,"sessions":0,"toolCalls":0,"linesAdded":0,"linesRemoved":0,"cacheReadRate":0}
```

**`summary.requests` is the Coding Plan proxy.** Keep `totalTokens` for a Token Plan (credits) and for
per-token providers. The same data sits in a plain file readable **with no daemon running**:
`$QWEN_HOME/usage_record.jsonl`, global and cross-project (VERIFIED-SRC, `getUsageHistoryPath()`,
`chunk-J6QWYIXU.js`).

### 6d. In-band limit-hit detection

Classification is **prose matching** (VERIFIED-SRC, `chunk-YSD6IY6F.js:53`):

```js
function isQuotaExhaustedError(error) {
  const lower = getQuotaMessage(error).toLowerCase();
  return lower.includes("quota")
      && (lower.includes("exhausted") || lower.includes("exceeded"))
      && (lower.includes("will reset") || lower.includes("reset at"));
}
```

When it matches, the message is re-emitted with the literal prefix
**`"Quota exhausted: "`** (`QUOTA_EXHAUSTED_PREFIX`, VERIFIED-SRC) followed by
"Please retry after the reset time, or switch to another API key / auth method." **That prefix is the
orchestrator's reliable in-band marker** — grep for it rather than re-implementing the triple test.

How it surfaces, per launch kind:

| Kind | Where to catch it |
|---|---|
| **daemon** | SSE `turn_error` frame, or `GET /session/:id/status → turnError.message`. VERIFIED-RAN: the failure produced `event: turn_error` with `{"message":"Connection error.","code":"-32603"}` and `status.hasTurnError:true` |
| **TUI** | `assistant` message text on the `--json-file` channel. VERIFIED-RAN: `[API Error: Connection error. (cause: fetch failed)]` arrived as assistant content |
| **headless** | **stderr**, as `{"error":{"type":"AlreadyReportedError","message":"…","code":1}}`, exit 1. VERIFIED-RAN |
| **hook** | `StopFailure` with `"matcher": "rate_limit"` or `"billing_error"` |

> **`StopFailure` does not fire for API errors in headless runs** — "API errors fire it in the
> interactive UI and in ACP sessions, but **not in headless (`-p`) runs**" (VERIFIED-SRC,
> `hooks.md:961`). So the hook-based limit alarm covers TUI and daemon only; headless must parse
> stderr. Error classes: `rate_limit | authentication_failed | billing_error | invalid_request |
> server_error | max_output_tokens | loop_detected | unknown`, derived from status + message in that
> order — note **402/403/"billing"/"quota" → `billing_error`**, so quota exhaustion arrives under
> `billing_error`, *not* `rate_limit`. Match both.

Two consequences to swallow: there is **no structured reset timestamp in the error** (use §6b's rule
instead), and **detection is provider-dependent** — a 429 saying "insufficient balance" without the
words "will reset" is not classified as quota-exhausted and gets retried as an ordinary rate limit.
On a true classification the stream **fast-fails** (`retryDecision: "fail-fast"`) rather than retrying.

Ordinary rate limits *are* handled structurally: `getRateLimitErrorDetails` returns
`{statusCode, providerCode, providerType, providerMessage, requestId, transport}`, and
`getRateLimitRetryDelayMs` uses `retryAfterMode: "minimum"` — it waits **at least** what
`Retry-After` asked (VERIFIED-SRC, `chunk-YSD6IY6F.js:217`).

### 6e. The two mitigations, and the preflight assertion that prevents silent overspend

```
--fallback-model <m>[,<m2>,<m3>]   # up to 3, for capacity errors (429/503/529)
QWEN_CODE_UNATTENDED_RETRY=1       # retry 429/529 indefinitely, backoff capped at 5 min,
                                   # stderr heartbeat every 30 s so CI doesn't reap the process
```

`--fallback-model` is the better fit for an overnight queue: **degrade the model rather than stop.**
The docs insist `QWEN_CODE_UNATTENDED_RETRY` needs explicit opt-in — "CI=true alone does not activate
it — silently turning a fast-fail CI job into an infinite-wait job would be dangerous" — and must be
paired with `--max-wall-time` so a permanently broken provider cannot extend a job forever.

**And assert this at preflight** (VERIFIED-VENDOR): a Coding Plan key has the prefix **`sk-sp-`** and
must be paired with the plan base URL (`https://coding-intl.dashscope.aliyuncs.com/v1`, or
`/apps/anthropic` for the Anthropic-compatible shape). A general Model Studio key is `sk-`. **Using a
plan key against the wrong base URL means the usage is not deducted from the plan** — i.e. it is
billed per-token instead, silently. One regex in preflight prevents an expensive night:

```bash
case "$OPENAI_API_KEY:$OPENAI_BASE_URL" in
  sk-sp-*:*coding*dashscope*) ;;                       # plan key + plan URL: correct
  sk-sp-*)  echo "FATAL: plan key against non-plan base URL — usage will NOT count against the plan"; exit 72 ;;
esac
```

**Fallback for the whole axis:** a locally enforced budget. Before each ticket, read
`summary.requests` (Coding Plan) or `summary.totalTokens` (Token Plan / per-token) for the current
window, compare against a hand-calibrated per-account ceiling, and stop dispatching at the ceiling.
Treat the provider's own limit as an **exception path** — catch the `Quota exhausted: ` marker, rotate
to the next account (§7), and requeue. **Cost: the ceiling is a guess that drifts whenever the plan
changes.** Design the scheduler so a platform may answer "I don't know how much is left"; Qwen proves
that case is not hypothetical.

**verified: true**

---

## 7. Switch a new session to a different account, and verify before work starts

Two independent mechanisms. Use both together.

### 7a. Per-run, by environment alone — no config written, no global state mutated

Credential precedence, highest first (VERIFIED-SRC, `docs/configuration/auth.md`):

1. CLI flags — `--openai-api-key`, `--openai-base-url`, `--auth-type`
2. process env — `OPENAI_API_KEY` / `OPENAI_BASE_URL` / `OPENAI_MODEL`, `ANTHROPIC_API_KEY`,
   `GEMINI_API_KEY`, `DASHSCOPE_API_KEY`, `BAILIAN_CODING_PLAN_API_KEY`, `BAILIAN_TOKEN_PLAN_API_KEY`
3. `.env` — first hit wins, **never merged**: `.qwen/.env` → `.env` walking up → `~/.qwen/.env` → `~/.env`
4. `settings.json` → `env` (lowest)

`--auth-type` takes `openai | openai-responses | anthropic | qwen-oauth | gemini | vertex-ai`
(VERIFIED-RAN, `--help`).

> **Export `OPENAI_API_KEY`, not the provider-specific name.** `BAILIAN_CODING_PLAN_API_KEY` and
> friends "take effect once the `settings.json` provider entry … exists, because that entry declares
> it as the `envKey`" — the variable alone does **not** select the auth type (VERIFIED-SRC). This is
> confirmed by the preflight table: `AUTH_PREFLIGHT_ENV_KEYS` maps only
> `openai→OPENAI_API_KEY`, `anthropic→ANTHROPIC_API_KEY`, `gemini→GEMINI_API_KEY`,
> `vertex-ai→GOOGLE_API_KEY` (VERIFIED-SRC, `acpAgent-ANIVCBU3.js:16498`).

### 7b. Whole-home isolation — `QWEN_HOME`

**VERIFIED-RAN, and it corrects the profile.** `QWEN_HOME` *is* the config home; it does not get a
`.qwen` suffix. Running `QWEN_HOME=$SB/fakehome/acct-B qwen sessions controllers add --label acctB`
created exactly `$SB/fakehome/acct-B/peer-controllers.json`.

```
QWEN_HOME=~/.qwen-accounts/acct-a    qwen …    # → ~/.qwen-accounts/acct-a/settings.json, projects/, sessions/, usage_record.jsonl
QWEN_HOME=~/.qwen-accounts/acct-b    qwen …
```

**The trade-off:** relocating `QWEN_HOME` also partitions the transcript store, the session registry,
the usage ledger and the controller-token store. A session started under one home **cannot be resumed
under another**. The owner's profile-switcher setup solves the equivalent problem for Claude Code by symlinking
`projects/` into one shared store; a Qwen equivalent must be built by hand or the limitation accepted.

**Credentials sit in plain files** under `$QWEN_HOME` (mode-controlled by
`QWEN_CREDENTIAL_FILE_MODE` / `QWEN_CREDENTIAL_FILENAME`), with **no macOS Keychain involvement**.
That removes the silent-failure mode where an unattended run blocks on a GUI Keychain dialog —
**a genuine advantage over Claude Code for overnight running.** The cost is keys on disk.

### 7c. Verify the switch BEFORE work starts

Two assertions, both VERIFIED-RAN:

```bash
# 1. the daemon agrees which credential is live
curl -s "$B/workspace/preflight" \
  | jq -e '.cells[] | select(.kind=="auth")
           | select(.status=="ok" and .detail.presentVar=="OPENAI_API_KEY")' >/dev/null || exit 73

# 2. the model and base URL are the ones this role is supposed to use
curl -s "$B/workspace/providers" | jq '{current, approvalMode, providers:[.providers[]|{authType,status}]}'
```

`GET /workspace/providers` returned live:

```json
{"current":{"modelId":"coder-model"},"approvalMode":"auto","initialized":true,"acpChannelLive":true,
 "providers":[{"kind":"model_provider","status":"ok","authType":"qwen-oauth","current":false,
   "models":[{"modelId":"coder-model(qwen-oauth)","contextLimit":1000000,
              "baseUrl":"DYNAMIC_QWEN_OAUTH_BASE_URL", …}]}]}
```

Plus the §6e prefix/base-URL assertion. Only then dispatch the ticket.

### 7d. Changing a RUNNING session's account — partial, and the architectural consequence

- `POST /session/:id/model` with **`{"modelId": "…"}`** switches the model of a live session
  (VERIFIED-RAN — `{"model":…}` is rejected with `` `modelId` is required ``).
- `POST /workspace/auth/provider` installs a provider into a running daemon; guarded by
  `--allow-private-auth-base-url` for localhost/private base URLs.
- `POST /workspace/auth/device-flow` runs an OAuth device flow against a remote daemon, returning
  `{deviceFlowId, userCode, verificationUri, verificationUriComplete, expiresAt, intervalMs}` and
  emitting `auth_device_flow_authorized` on success. **This is how an unattended supervisor gets a
  human through a login without a terminal** — surface the URL and code in Slack, then subscribe.

> **But provider auth is workspace-scoped, not session-scoped.** Changing it changes it for every
> session in that workspace runtime. **Per-role accounts therefore need one daemon (or one
> `QWEN_HOME`) per account** — N daemons on N ports, and a `{role → port, QWEN_HOME}` registry the
> orchestrator owns. Budget for it; it is not optional.

**Fallback:** always spawn a fresh process with the right env rather than mutating a live one.
`QWEN_HOME` + `OPENAI_*` at spawn time is fully deterministic and needs no daemon at all.

**verified: true**

---

## 8. Deliver an instruction into a running session, and confirm it arrived

Three mechanisms. **They are not interchangeable — the adapter must route by session kind.**

### 8a. Visible TUI — the input file. PROVEN END TO END ON THIS MACHINE.

```bash
echo '{"type":"submit","text":"stop refactoring and open the PR"}' >> "$RUN/$SID.input"
```

VERIFIED-RAN. I appended `{"type":"submit","text":"say hi from the orchestrator"}` to a live TUI
session's `--input-file` and within seconds the `--json-file` channel emitted:

```json
{"type":"user","session_id":"cccccccc-…",
 "message":{"role":"user","content":[{"type":"text","text":"say hi from the orchestrator"}]}}
```

followed by `stream_event` frames and the `assistant` reply. **That `user` echo is the arrival
receipt.** This is the exact failure the owner's current harness has — the field notes record "a nudge
that cannot submit stranded text" — and here it is, solved, and demonstrated.

Semantics that matter (VERIFIED-SRC, `dual-output.md:329-348`):

- `submit` is **queued and auto-retried** — "if the TUI is busy responding, they are retried
  automatically the next time the TUI returns to the idle state." Text is never stranded.
- **Latency ≈ 500 ms worst case**: the file is watched with `fs.watchFile` at a 500 ms poll, chosen
  deliberately for portability across macOS and network mounts.
- Unparseable lines are logged and skipped; they do not kill the watcher.
- The owner can type in the TUI at any moment without breaking the supervisor.

**Always append (`>>`), never rewrite.** The watcher reads new lines from a growing file.

### 8b. Daemon — HTTP, with retract

```bash
curl -s -X POST "$B/session/$SID/mid-turn-message" \
     -H 'Content-Type: application/json' -d '{"message":"…"}'
```

VERIFIED-RAN, and **this corrects the profile**:

```
{"message":""}        → 400 {"error":"`message` must be a non-empty string, or `content` must carry at least one media block"}
{"message":"nudge"}   → 200 {"accepted":false,"reason":"session_idle"}
```

**HTTP 200 is not delivery.** `accepted: false` with `reason: "session_idle"` means the nudge went
nowhere — a mid-turn message only lands while a turn is running. The adapter must read `accepted`,
and fall back to `POST /session/:id/prompt` when the session is idle. Cap: **16 KiB**
(`MID_TURN_MESSAGE_MAX_LENGTH`).

Siblings, all VERIFIED-RAN or route-verified:

```
POST   /session/:id/prompt                      {"prompt":[{"type":"text","text":"…"}]} → 202 {promptId,lastEventId,eventEpoch}
POST   /session/:id/btw                         {"question":"…"}   # ≤ 4096 chars
GET    /session/:id/pending-prompts             → {"pendingPrompts":[]}
DELETE /session/:id/pending-prompts/:promptId   # retract a queued instruction
GET    /session/:id/mid-turn-messages           → {"messages":[],"settledMessageIds":[],"promotedMessageIds":[]}
DELETE /session/:id/mid-turn-messages/:messageId
POST   /session/:id/cancel
```

**The ability to list and retract is unusual and valuable** — a supervisor that changes its mind can
withdraw an instruction it already queued. Note `--max-pending-prompts-per-session` defaults to **5**;
beyond it, prompts return **503** (VERIFIED-RAN, `/daemon/status → limits`).

### 8c. Headless / any kind — the cross-session IPC socket with a controller token

One-time, per `QWEN_HOME` (VERIFIED-RAN):

```bash
QWEN_HOME=~/.qwen-accounts/work qwen sessions controllers add --label harness --json
# → {"id":"c_f2c9e476","label":"harness",
#    "token":"qpc_<redacted>",
#    "createdAt":1789824249966}
```

> **The plaintext token is printed exactly once.** The store keeps only a SHA-256 hash — I read
> `$QWEN_HOME/peer-controllers.json` and it holds `"tokenHash": "499b7214…"`, no token
> (VERIFIED-RAN). **Persist it at mint time or re-mint.** `qwen sessions controllers list --json`
> returns `{id,label,createdAt}` only.

Then: read the target's record at `$QWEN_HOME/sessions/<pid>.json`, connect to its `ipcPath` (a UNIX
socket under `$TMPDIR/qwen-socks-<16hex>/` on macOS — VERIFIED-RAN), and write newline-delimited JSON:

```json
{"msgV":1,"type":"auth","token":"qpc_…"}
{"msgV":1,"msgId":"<fresh uuid>","type":"user",
 "from":"<your own ipcPath>","replyToken":"<your own ipcToken>",
 "fromName":"harness","fromMode":"bypass",
 "toSessionId":"<sessionId from the record>","priority":"next",
 "message":{"role":"user","content":"stop refactoring and open the PR"}}
```

**Presenting a controller token is what makes the message *delivered* instead of *held for a human to
review*** — and it is exempt from the duplicate-suppression window. The receiver stamps the authority
itself (`origin="controller" controller="harness"`) from the connection, never from the frame.

**Delivery evidence is a first-class state machine** (VERIFIED-SRC, `cross-session-protocol.md` §5):

```
pending   → held | delivered | denied | refused | expired | misaddressed | dropped
held      → delivered | denied | expired | misaddressed
delivered → expired | misaddressed
```

`dropped` carries `dropReason ∈ rate-limited | duplicate | queue-full` and `droppedMsgIds` (up to 256
ids settled by one receipt, so a burst is answered once). **Bind your own inbox and set `from`, or
you are blind to all of this.**

Three honest limits, stated by the protocol doc itself:

- **`delivered` is not proof it was read** — only that it was queued for the model.
- **Rate limits are real**: per sender, burst 30 then 1 per 2 s; all senders together, burst 32 then
  1 per second. Hold buffer 50, expiring per `agents.crossSessionHeldExpiry` (default `5m`).
- **§8: ACP-driven sessions answer `refused` to everything inbound** — "a hold is a question put to a
  person, and nobody is watching a hold list on its behalf." **So a daemon-spawned session cannot be
  reached this way at all.** Use 8b for those.

Use `@qwen-code/sdk/peer` (Node, zero dependencies, tested against Qwen's own implementation in both
directions) rather than hand-rolling the framing.

**Also worth a prototype before building a bespoke queue:** `qwen board task|claim|done|ask|answer|decline|show|prune`
with `--board <name>` and `--json` — a file-backed shared task board with an explicit ask/answer
triad (VERIFIED-RAN, `qwen board --help`).

### Routing table the adapter must implement

| Kind | Instruction channel | Arrival evidence |
|---|---|---|
| `tui` | `--input-file` `submit` | `user` event on `--json-file` **(proven)** |
| `serve` / ACP | `POST /mid-turn-message` (running) or `/prompt` (idle) | `accepted:true`, or `202 {promptId}` |
| `headless` | IPC socket + controller token | `delivery_status` receipt |

**Fallback:** none needed — but note that a headless run with no IPC inbox bound and no daemon is
genuinely unreachable until it finishes. If a ticket may need steering, do not launch it headless.

**verified: true**

---

## 9. Answer a permission prompt or a clarifying question without a human

Four mechanisms, in the order an implementer should reach for them.

### 9a. Prevent the question — `--approval-mode`

`plan | default | auto-edit | auto | yolo` (VERIFIED-RAN, `--help`). **The default is `auto`** —
confirmed live: `POST /session/:id/approval-mode` with `{"mode":"yolo"}` returned
`{"mode":"yolo","previous":"auto","persisted":false}`.

Two things in that one response matter. `previous: "auto"` **proves the out-of-the-box default is the
LLM classifier**, not `default`. And **`persisted: false`** means the change is session-scoped and is
**not written to the owner's config** — exactly what an orchestrator needs, since it must never mutate
his settings. (The request key is **`mode`**; `{"approvalMode":…}` is rejected with
`{"code":"invalid_approval_mode","allowed":["plan","default","auto-edit","auto","yolo"]}` — VERIFIED-RAN.)

> `auto` is a *model* deciding. When it blocks repeatedly, Qwen **falls back to asking the user** —
> which unattended means parking. Watch the `PermissionDenied` hook (`reason: "classifier_blocked"`;
> it reports and **cannot** approve).
>
> **`--yolo` does not enable a sandbox.** Qwen prints a stderr warning when it sees yolo-without-sandbox —
> VERIFIED-RAN, verbatim: *"Warning: running headless with --yolo / approval-mode=yolo and no sandbox.
> All tool calls (shell, write, edit) auto-execute at this process's privilege level."* For an
> unattended queue use `--yolo --sandbox` (native macOS Seatbelt; six `sandbox-macos-*.sb` profiles
> ship in the package).

### 9b. Adjudicate centrally — the `PermissionRequest` HTTP hook

The strongest option, because policy lives in one place for every session:

```json
{ "hooks": { "PermissionRequest": [ { "matcher": "^run_shell_command$", "hooks": [
  { "type": "http", "url": "http://127.0.0.1:8787/qwen/permission",
    "headers": {"Authorization":"Bearer ${HARNESS_TOKEN}"},
    "allowedEnvVars":["HARNESS_TOKEN"], "timeout": 20 } ] } ] } }
```

Request carries `{permission_mode, tool_name, tool_input, permission_suggestions}` plus the common
fields. Respond (VERIFIED-SRC, `hooks.md:1200-1221`):

```json
{"hookSpecificOutput":{"decision":{
  "behavior":"allow",
  "updatedInput":{"command":"rm -rf ./build"},
  "updatedPermissions":[], "message":"narrowed by harness policy", "interrupt":false}}}
```

**`updatedInput` lets the supervisor rewrite a dangerous call into a safe one** rather than only
voting yes/no. That is a stronger guardrail story than any allow/deny list.

### 9c. Vote on a specific pending request — daemon

```bash
curl -s -X POST "$B/session/$SID/permission/$REQUEST_ID" \
  -H 'Content-Type: application/json' \
  -d '{"outcome":{"outcome":"selected","optionId":"proceed_once"}}'
```

**The body is nested, and I established that by probing live.** A flat
`{"outcome":"selected","optionId":"…"}` is rejected `400`:

```
`outcome` must be `{ outcome: "cancelled" }` or `{ outcome: "selected", optionId: string }`
```

The nested form passes validation and returns `404 {"error":"No pending permission request for session"}`
when there is nothing pending — i.e. the shape is right (VERIFIED-RAN). Cancel form:
`{"outcome":{"outcome":"cancelled"}}`.

The pending request arrives as a `permission_request` SSE event carrying the `requestId`, and
`GET /session/:id/status → pendingInteractions[]` lists what is outstanding (§4a). Both
`POST /session/:id/permission/:requestId` (session-scoped, prefer this) and the legacy daemon-global
`POST /permission/:requestId` are registered in 0.24.1; `/capabilities` advertises
`session_permission_vote`, `permission_vote` and `permission_mediation` (VERIFIED-RAN).

> **The shipped `docs/qwen-serve.md` is stale here** — it still carries a "Stage 1 known gap:
> permissions are daemon-global, not per-session" warning. The code and `/capabilities` say
> otherwise. Heed its security point though: on a token-shared daemon any authenticated client can
> vote on any `requestId`.

### 9d. Vote from a visible TUI

```bash
echo '{"type":"confirmation_response","request_id":"…","allowed":true}' >> "$RUN/$SID.input"
```

Dispatched **immediately and never queued** — "because a tool call is blocking and the response must
reach the underlying `onConfirm` handler without waiting for any earlier `submit`." The `request_id`
comes from a `control_request` frame on the `--json-file` channel, and **arrival evidence is a
`control_response` frame**, emitted "whether the decision was made in the TUI (native approval UI) or
by an external `confirmation_response` … all observers see the final outcome" (VERIFIED-SRC).

### The timeout that keeps an unattended run from parking forever

```
qwen serve --permission-response-timeout-ms 600000
```

**Default is `0` = wait indefinitely.** One unanswered question parks a session for the whole night.
**And it exists only on `qwen serve`** — VERIFIED-RAN, it is absent from `qwen --help`. A TUI or
headless session has no equivalent knob, so for those the orchestrator must impose its own deadline
via `--max-wall-time` and kill on overrun.

Also useful: `--restore-ask-user-question` re-hangs a trailing unanswered question on reload instead
of synthesising a failed tool result.

**Fallback if all else fails:** `--approval-mode yolo --sandbox` and accept that nothing will ask.
That is the honest unattended posture; the sandbox, not the prompt, is the guardrail.

**verified: false** — the route and the exact nested payload were confirmed live by validation
probing (400 → 404), the hook contract and the TUI shapes are VERIFIED-SRC, but **I never answered an
actual permission prompt**: producing one needs a real model call. Smoke-test this on first contact.

---

## 10. Resume after a crash, and after a reboot

### 10a. Resume — VERIFIED-RAN

```bash
qwen --resume "$SID" "$FOLLOW_UP"          # exact session
qwen --continue "$FOLLOW_UP"               # most recent session for this project
qwen --resume "$SID" --fork-session "$T"   # resume into a NEW session instead of appending
```

I ran `--resume bbbbbbbb-2222-4333-8444-555555555555 "continue"` and the `system/init` event came back
carrying **that same `session_id`** — resume honored, identity preserved. It restores "conversation
history, tool outputs, and chat-compression checkpoints before sending the new prompt".

**Failure looks like** (VERIFIED-RAN):

```
EXIT=1
stderr: No saved session found with ID 99999999-0000-4000-8000-000000000000.
        Run `qwen --resume` without an ID to choose from existing sessions.
```

> **Trap: that message is plain text on stderr even under `--output-format json`.** The
> session-not-found path bypasses the JSON formatter entirely. An adapter that only parses JSON sees
> an empty stdout and exit 1 with no machine-readable reason. Match the literal string.

**Precondition:** `--chat-recording` must be on (the default). With `--chat-recording false` nothing
persists **and `--continue`/`--resume` do not work** (VERIFIED-RAN, `--help`).

Daemon-side: `POST /session/:id/load` (cold reconnect, bounded replay snapshot),
`POST /session/:id/resume` ("Model context is restored on the agent side without UI replay"),
`/fork`, `/branch`, `/rewind` + `GET /rewind/snapshots`.

### 10b. Detecting the crash first

Per §4c: read `<sessionId>.runtime.json`, test `process.kill(pid, 0)`. **Proven on this machine** —
after SIGTERM the file remained and the check returned `dead`. VERIFIED-RAN: SIGTERM removed the
session's **registry** record (`$QWEN_HOME/sessions/` went empty) but **left `runtime.json` behind**.
That asymmetry is the design: the registry says "reachable now", the runtime file says "who was here".

For daemon sessions: a child crash publishes a `session_died` SSE event and drops the live session;
the persisted session can be reloaded with `POST /session/:id/load` if a fresh child can spawn.

### 10c. After a whole-machine reboot — **the hazard that ends the night**

`docs/conversations-recovery.md` is blunt, and this is the single most important operational fact in
the whole spike:

> "After an ungraceful shutdown, a Linux reboot or a container restart into a new PID namespace can
> leave an unsealed active writer record fenced indefinitely. There may be no surviving owner to
> close."
>
> "**There is no force-unlock API or automatic cross-boot/TTL takeover in this release.** When safe
> ownership cannot be established, retain the fence."

Recovery is a **five-step manual operator procedure** requiring a maintainer's judgement — identify
the session and storage, fence *every* possible writer including detached ACP children, inspect the
record with a maintainer, move verified artifacts to private recovery storage, then restart one
daemon. "Never recursively delete a lock directory or remove all locks."

The errors to watch for are `session_writer_conflict` ("the writer fence prevented access… **not
proof that another writer is currently alive**") and `session_writer_unavailable` ("ownership could
not be verified; retrying does not authorize bypassing it").

**Therefore the orchestrator's reboot policy must be: do not fight a fenced session.**

```
on resume attempt:
  if error is session_writer_conflict or session_writer_unavailable:
     do NOT retry            # retrying never wins; elapsed time never authorizes takeover
     mint a fresh lower-case session id
     relaunch with the ticket text + the last PostCompact summary + the last transcript tail
     record the fenced id for the owner to inspect in the morning
```

**macOS makes the identity check weaker, not stronger.** `procStart` and `pidNs` are `null` on
darwin (VERIFIED-RAN in both live registry records). The doc says `procStart` exists precisely so a
reader "cannot tell a recycled PID from the process that wrote the record" *without* it — so after a
reboot, a recycled PID can make a dead session read as **`active`** (the check fails open). **Never
let "active" alone authorize skipping a resume.** Cross-check `updatedAt`/`mtime` against wall-clock.

**Fallback, and it should be the default posture:** prefer `--fork-session` or a fresh id over
resuming. Qwen's resume is excellent when it works and unrecoverable-without-a-human when it does not;
for an unattended queue, cheap relaunch beats expensive recovery.

**verified: true**

---

## 11. Stop it cleanly, leaving nothing running

### 11a. Daemon session — VERIFIED-RAN

```bash
curl -s -o /dev/null -w '%{http_code}' -X POST   "$B/session/$SID/cancel"     # stop the turn, keep the session
curl -s -o /dev/null -w '%{http_code}' -X DELETE "$B/session/$SID"            # close the session
```

`DELETE` returned **204**, and the follow-up `GET /session/$SID/status` returned
**404 `{"code":"session_not_found"}`**. That pair is the success criterion.

### 11b. TUI / headless process — VERIFIED-RAN

```bash
kill -TERM "$pid"                     # graceful
sleep 5; kill -0 "$pid" 2>/dev/null && kill -KILL "$pid"
```

After SIGTERM the session's registry record disappeared from `$QWEN_HOME/sessions/` (VERIFIED-RAN —
the directory was empty). **`<sessionId>.runtime.json` is deliberately left behind** so the next
liveness read reports `dead`. **Do not delete it as cleanup** — it is the crash evidence, and it is
swept by the runtime itself.

### 11c. The daemon

```bash
pkill -f "cli.js serve --port $PORT"
curl -s --max-time 2 "http://127.0.0.1:$PORT/health" || echo "down"   # expect connection refused
```

`GET /health` → `{"status":"ok"}` while up (VERIFIED-RAN). With `--require-auth`, `/health` needs the
bearer too — "no loopback exemption".

### 11d. The teardown checklist an adapter should assert

```bash
qwen sessions ps --json | jq -e 'select(.sessionId=="'"$SID"'")' && echo "STILL REGISTERED"
ls "$QWEN_HOME/sessions/"                       # expect: empty, or only other roles' records
pgrep -f "@qwen-code"                           # expect: nothing
ls "$TMPDIR"/qwen-socks-*/ 2>/dev/null          # stale sockets outlive a crash — harmless, sweep them
```

The protocol doc is explicit that "a socket file outlives a crash", so a leftover `.sock` is **not**
evidence of a live session; only a dialable socket plus a live record counts.

### 11e. Two things that will bite an unattended stop

- **`--worktree` prompts on exit.** `--help`, verbatim: "On exit, the WorktreeExitDialog prompts to
  keep or remove the worktree." **An interactive dialog in an unattended run.** Either avoid
  `--worktree` in headless queues and manage worktrees yourself with plain `git worktree`, or use the
  daemon's `POST /session/:id/worktree-reset`.
- **Idle sessions are reaped at 30 minutes.** `--session-idle-timeout-ms` defaults to **1800000**
  (VERIFIED-RAN — `/daemon/status → limits.sessionIdleTimeoutMs: 1800000`, and the daemon logs
  `session reaper started (interval 60000ms, idle threshold 1800000ms)`). A disconnected supervisor
  that reconnects after 31 minutes finds the session gone. Either hold an SSE connection, call
  `POST /session/:id/heartbeat`, or raise the timeout at daemon start.

**verified: true**

---

## The adapter interface

```ts
interface QwenCodeAdapter {
  // 1  native   GET /workspace/preflight, or `qwen --version` + system/init
  preflight(): Promise<{installed, version, authSource, presentVar, valid: "unknown"}>

  // 2  native   --session-id (LOWER CASE) --output-format stream-json
  launchHeadless(t: Ticket, sid: string): Promise<{exitCode, transcriptPath}>

  // 3  native   TUI + --json-file (FIFO) + --input-file; never --json-fd under a PTY
  launchVisible(t: Ticket, sid: string): Promise<{pid, eventsFifo, inputFile}>

  // 4  native   GET /session/:id/status | sessions ps --json | runtime.json
  probe(sid): Promise<"working"|"waiting"|"finished"|"failed"|"dead"|"unknown">

  // 5  native read + native trigger + native proof (PostCompact webhook)
  contextUsage(sid): Promise<{tier, totalTokens, contextWindowSize, thresholds, isEstimated}>
  compact(sid, reason): Promise<{proven: boolean, summary?: string}>

  // 6  EMULATED — no remaining-capacity API exists anywhere
  budget(role): Promise<{requestsUsed, tokensUsed, ceiling, nextResetAt /* computed, not read */}>

  // 7  native   QWEN_HOME + OPENAI_* at spawn; verify via preflight.presentVar
  useAccount(role): SpawnEnv

  // 8  native, but THREE different channels — route by session kind
  instruct(sid, kind, text): Promise<DeliveryStatus>

  // 9  native   PermissionRequest HTTP hook + POST /session/:id/permission/:requestId
  decide(sid, requestId, decision): Promise<void>

  // 10 native resume; fenced-lock recovery is EMULATED by relaunching
  resume(sid): Promise<Session | {fenced: true, freshSid: string}>

  // 11 native   DELETE /session/:id, SIGTERM, plus a teardown assertion
  stop(sid): Promise<void>
}
```

| # | Axis | Verdict | Note |
|---|---|---|---|
| 1 | Preflight | **native** | one GET; but `hasToken` ≠ valid |
| 2 | Headless + pinned id + structured out | **native** | best-in-field: 3 output shapes, 3 budgets, distinct exit codes |
| 3 | Visible attachable terminal | **native** | the TUI is not opaque — unique among the platforms surveyed |
| 4 | Alive / working / waiting / finished | **native** | `activeWorkState` + `isWaitingFor*` answers all four in one GET |
| 5 | Context read → compact → **prove** | **native** | the only platform in this spike that closes all three |
| 6 | **Quota remaining** | **IMPOSSIBLE** | no API, upstream request closed. Reset time *is* computable; spend is local-only |
| 7 | Multi-account | **native** | env-only pinning, no Keychain. Cost: one daemon per account |
| 8 | Instruct a running session | **native ×3** | must route by kind; ACP sessions refuse IPC |
| 9 | Answer prompts/questions | **native ×4** | timeout knob is `serve`-only |
| 10 | Resume after crash / reboot | **native + emulation** | fenced writer lock has no programmatic recovery |
| 11 | Clean stop | **native** | watch the worktree exit dialog and the 30-min reaper |

**10 of 11 native. One impossible, and it is the owner's #1 requirement.**

### Qwen-specific work with no analogue in the Claude Code adapter

1. **A session-kind router.** Intervention, compaction and question-answering each have a *different*
   mechanism for `tui` / `headless` / `serve`, and the cross-session protocol explicitly refuses
   inbound to ACP-driven sessions. **The single largest piece of Qwen-specific work.**
2. **A daemon lifecycle manager** — one `qwen serve` per account, with a `{role → port, QWEN_HOME}`
   registry, because provider auth is workspace-scoped.
3. **A controller-token bootstrap** — mint once per `QWEN_HOME`, store it where the orchestrator can
   read it and the model cannot. The registry is world-readable-to-the-user by design: *"Do not print
   `ipcToken` anywhere a model or a log can see it."*
4. **A request-counting budget ledger** (not a token ledger) with a computed reset clock.
5. **A fenced-lock policy**: on `session_writer_conflict`, fork to a fresh id — never retry.

### What to copy into the engine-agnostic design regardless of whether Qwen is adopted

1. **`PostCompact` with `trigger: manual|auto` is the right shape for "compaction with proof."** Make
   it a contract the orchestrator asks every platform for.
2. **`activeWorkState` + `isWaitingForPermission` + `isWaitingForUserQuestion` is the right shape for
   liveness.** "Waiting on a human" is a distinct state from "working", and conflating them is how an
   overnight run dies quietly.
3. **The `delivery_status` state machine** beats a boolean for "did my nudge land" — and it names the
   failure the owner actually hit: `held`, waiting on a human who is asleep.
4. **Publish thresholds, don't make the supervisor guess them.** `thresholds{warn,auto,hard}` +
   `currentTier` means runtime and supervisor can never disagree about where the line is.
5. **`isEstimated` on a context reading.** A platform that admits when its number is a guess is safer
   to automate against than one that always sounds confident.
6. **Distinct exit codes per abort reason** (53 / 55 / 130) turn "it died" into a scheduler decision.
7. **Quota reading is not a universal capability.** Design the scheduler so a platform may answer "I
   don't know", with a local ledger and a *computed* reset clock as the fallback. Qwen proves this
   case is not hypothetical.

---

## Support tier

# TIER 2 — workable, with one emulation on the axis that matters most

**Tier-1 on nine axes and better than Claude Code on several of them.** Launch, identity, transcript,
context, intervention, permissions, guardrails, extensibility and clean shutdown are all documented,
programmatic surfaces with real delivery evidence — and I drove most of them live on this machine
without spending a cent. Two capabilities have no equal anywhere else in this survey: **a visible
terminal the owner can type into that a supervisor can still read and drive** (proven end to end in
§8a), and **compaction triggered from outside with proof delivered by webhook** (§5).

**It is not tier-1 because of axis E, and only because of axis E.** Remaining capacity cannot be read
by any means — no endpoint, no event, no CLI, and the upstream feature request is closed. Running Qwen
overnight means spending real money at a rate the orchestrator can measure locally but cannot bound
remotely. Against Claude Code's `five_hour.utilization` / `seven_day.utilization` / `resets_at`, that
is a genuine regression on the owner's stated top requirement.

**Three findings soften it more than the profile expected.** The reset schedule is *published and
deterministic* (Mon 00:00:00 UTC+8, plus a 5-hour window) so the scheduler needs no API to know when
capacity returns; the meter is *model calls*, which `/usage/dashboard → summary.requests` reports
locally; and the `sk-sp-` prefix rule makes silent off-plan overspend a preflight assertion rather
than a surprise. A request-counting ledger with a computed reset clock is a real substitute — a hand-
calibrated ceiling, but a working one.

**The risk that would actually end an unattended night is not quota — it is the writer lock.** After an
ungraceful shutdown a session can be fenced indefinitely with no force-unlock API and a five-step
manual recovery. **Any adapter must treat a fenced session as disposable and fork to a fresh id rather
than retry.** Build that in from the first commit, not after the first bad night.

**Recommended first unattended shape:**

```bash
QWEN_HOME=~/.qwen-accounts/$ROLE \
QWEN_CODE_UNATTENDED_RETRY=1 \
OPENAI_API_KEY=sk-sp-… OPENAI_BASE_URL=https://coding-intl.dashscope.aliyuncs.com/v1 \
qwen "$TICKET" \
  --session-id "$(uuidgen | tr 'A-Z' 'a-z')" \
  --approval-mode auto --sandbox \
  --max-wall-time 45m --max-session-turns 200 --max-tool-calls 400 \
  --fallback-model "$CHEAPER" \
  --output-format stream-json \
  > "$RUN/$SID.jsonl" 2> "$RUN/$SID.err"
```

Branch on 0 / 1 / 53 / 55 / 130. Read **both** streams. Pin the version — 0.24.x ships nightly and has
1,472 open issues against 28k stars; this is a fast-moving project, not a settled one.

---

## Residual unknowns

- **Coding Plan / Token Plan prices and exact quota figures** — behind the ModelStudio console, which
  needs an account. **UNKNOWN.**
- **Whether the `PostCompact` webhook round trip works end to end** — the contract is VERIFIED-SRC,
  the trip was never made (no provider). **Smoke-test first.**
- **Whether a permission prompt can be answered end to end** — route and payload VERIFIED-RAN,
  the prompt itself was never produced. **Smoke-test first.**
- **Qwen model context-window sizes per model id** — surfaced per session as `contextWindowSize`
  (1,000,000 for `qwen3-coder-plus`, VERIFIED-RAN) but not enumerated in the shipped docs.
- **Whether `--fallback-model` rotation interacts correctly with a `sk-sp-` plan key** when the
  fallback model is not covered by the plan. Untested, and a plausible silent-overspend path.

---

## Sources

All consulted or run **2026-09-19**. Package-internal paths are relative to
`node_modules/@qwen-code/qwen-code/` in the sandbox.

**Run live on this machine (VERIFIED-RAN):**
`qwen --version` · `--help` · `serve --help` · `sessions --help` · `sessions list --help` ·
`sessions ps --help` · `sessions controllers {add,list,remove} --help` · `board --help` ·
`sessions controllers add --label harness --json` · `sessions ps --json` · `sessions list --json` ·
a full `qwen serve` daemon on 127.0.0.1:47170 with `GET /health`, `/capabilities`, `/daemon/status`,
`/usage/dashboard`, `/workspace/preflight`, `/workspace/providers`, `/workspace/trust` and
`POST /session`, `/session/:id/{prompt,mid-turn-message,btw,model,approval-mode,permission/:id}`,
`GET /session/:id/{status,context-usage,stats,transcript,events,turns/current,turns/:promptId,agents,goal,pending-prompts,mid-turn-messages}`,
`DELETE /session/:id` · a headless run with `--session-id --output-format json --max-wall-time
--max-session-turns --json-file` · a headless `--resume` (valid and invalid ids) · a TUI session under
a real PTY with `--json-file` + `--input-file`, including a live `submit` injection · SIGTERM teardown
and a `runtime.json` liveness check returning `dead` · `QWEN_HOME` relocation ·
`gh api repos/QwenLM/qwen-code/issues/{3302,3203}`.

**Shipped docs, version-locked to 0.24.1 (VERIFIED-SRC):**
`docs/qwen-serve.md` · `docs/features/headless.md` · `docs/features/dual-output.md` ·
`docs/features/cross-session-protocol.md` · `docs/features/hooks.md` ·
`docs/configuration/auth.md` · `docs/configuration/settings.md` · `docs/conversations-recovery.md` ·
`docs/features/{approval-mode,sandbox,sub-agents,commands,goals,worktree,agent-board,scheduled-tasks}.md`

**Shipped source read directly (VERIFIED-SRC):**
`chunks/server-PN5WV25I.js` (route table, `mergeLiveStandaloneSummary`, `QWEN_METHOD_NS`) ·
`chunks/acpAgent-ANIVCBU3.js` (`buildSessionContextUsageStatus` :21890, `buildAuthPreflightCell` :21563,
`AUTH_PREFLIGHT_ENV_KEYS` :16498) · `chunks/chunk-A4IJR5S6.js` (`entryActiveWorkState` :10249) ·
`chunks/chunk-YSD6IY6F.js` (`isQuotaExhaustedError` :53, `QUOTA_EXHAUSTED_PREFIX` :35,
`getRateLimitRetryDelayMs` :217) · `chunks/chunk-J6QWYIXU.js` (`computeThresholds` :40736,
`buildContextUsage` :21021, `getUsageHistoryPath`) · `chunks/chunk-3JHSUEQN.js` (`compressCommand` :4135) ·
`chunks/chunk-CXDWVOBM.js` (`getRuntimeStatusPathState` :301) · `chunks/chunk-TUKPBUHT.js` (ext methods) ·
`chunks/chunk-FVLDT6YJ.js` (`CompactionThresholds` :5615)

**Vendor documentation (VERIFIED-VENDOR):**
- [Coding Plan FAQ — Alibaba Cloud Model Studio](https://www.alibabacloud.com/help/en/model-studio/coding-plan-faq) — reset schedules, model-call metering, `sk-sp-` prefix, base URLs, no quota API
- [Coding plan — Alibaba Cloud Model Studio](https://www.alibabacloud.com/help/en/model-studio/coding-plan)
- [Rate limiting — Alibaba Cloud Model Studio](https://www.alibabacloud.com/help/en/model-studio/rate-limit)
- [Qwen Cloud Token Plan overview](https://docs.qwencloud.com/token-plan/overview) — 7-day fixed window, credits, no carryover
- [Authentication | Qwen Code Docs](https://qwenlm.github.io/qwen-code-docs/en/users/configuration/auth/)
- [QwenLM/qwen-code#3302](https://github.com/QwenLM/qwen-code/issues/3302) — `/quota` command request, closed as duplicate 2026-04-16
