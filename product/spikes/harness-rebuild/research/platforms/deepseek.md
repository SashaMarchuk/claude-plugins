# DeepSeek — platform profile for a provider-agnostic orchestrator

**Date of pass:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0), Node v22.18.0.
**Scope:** DeepSeek as an *agent platform to be driven*, measured on the A–J orchestrator contract.
Companion to `00-field-scan.md` in this directory. Does not cover orchestrators.

**Evidence tags:** **VERIFIED** — read in shipped source, read in official docs, or run on this
machine. **CLAIMED** — asserted by a README or vendor page only. **UNKNOWN** — could not establish.

---

## 0. What "DeepSeek" actually is, for this purpose

DeepSeek is **three separable things**, and the orchestrator has to decide about each one
independently. Conflating them is the main failure mode in every secondary source on this platform.

| # | Thing | What it is | Orchestrator role |
|---|---|---|---|
| 1 | **The API** | `https://api.deepseek.com` (OpenAI format) and `https://api.deepseek.com/anthropic` (Anthropic format). Two models: `deepseek-flash`, `deepseek-v4-pro`. Prepaid balance, no subscription. | A **provider swap** — a base URL + API key + model triple, exactly like Xiaomi MiMo in §2 of the field scan. Needs no new adapter. |
| 2 | **DeepSeek Harness (`dsh`)** | DeepSeek's own open-source agent harness, `@deepseek-ai/dsh`, `github.com/deepseek-ai/deepseek-harness`, MIT. A real executor with a browser UI, a one-shot headless mode, **and two stdio JSON-RPC control protocols**. | A **genuine new executor**, and the most orchestrator-shaped one found so far in this field — see §A and §G. |
| 3 | **DeepSeek-behind-someone-else's-CLI** | Claude Code, Codex, OpenCode, Crush, Kilo Code, Copilot CLI, OpenClaw and others, each pointed at the DeepSeek API. | The **cheapest path to value today**: reuse the existing Claude Code adapter, change three env vars. |

**Nothing DeepSeek is installed or configured on this machine (VERIFIED).** No `deepseek`/`dsh`
binary on PATH, no `~/.dsh`, no `DEEPSEEK_*` in the environment, no mention in `~/.zshrc`,
`~/.zshenv`, `~/.zprofile`, `~/.bashrc`, `~/.codex/config.toml`, `~/.cursor/cli-config.json`,
`~/.cursor/mcp.json`, or `~/.config/opencode/opencode.json`. There is no DeepSeek account, API key
or balance here. Everything below about `dsh` was established by installing `@deepseek-ai/dsh@0.1.5-rc.2`
into an **isolated sandbox** at
`/private/tmp/claude-501/.../scratchpad/dshbox` with its own `DSH_HOME`, and running read-only
commands. No owner config was touched, no agent run was started, no quota was spent.

### The two versions you must not confuse

| Artifact | Version | Date | Tag |
|---|---|---|---|
| `@deepseek-ai/dsh` `latest` | **0.1.5-rc.2** | published 2026-09-10 | VERIFIED (npm) |
| `@deepseek-ai/dsh` `alpha` | **0.1.6-alpha.2** | published 2026-09-17 | VERIFIED (npm) |
| First ever publish | 0.0.1-rc.1 | 2026-08-10 | VERIFIED (npm `time`) |
| Repo `deepseek-ai/deepseek-harness` | MIT, **229,699 stars**, 27,488 forks, created **2026-08-13**, pushed 2026-09-17 | — | VERIFIED (GitHub API, today) |
| Installed and tested here | **0.1.5-rc.2** (`dsh --version`) | — | VERIFIED (run on this machine) |

The repo is **five weeks old** and already the largest-starred agent CLI in the field scan. Every
flag, path and protocol detail below is pinned to **0.1.5-rc.2**; treat it as a moving target.

---

## A. LAUNCH

### A.1 The API path (thing 1) — headless is whatever the driving CLI supports

Nothing to add: `deepseek-flash` / `deepseek-v4-pro` behind `ANTHROPIC_BASE_URL` or
`OPENAI_BASE_URL`. The launch story is the host CLI's, not DeepSeek's. §J.2 has the exact env block.

### A.2 `dsh` — four launch modes, all VERIFIED by running `--help` on this machine

The launcher itself (`dsh --help`, run here, 0.1.5-rc.2):

```
Usage: dsh [options] [command] [args...]

Options:
  -V, --version                  output the version number
  --profile <name>               the profile under $DSH_HOME/profiles to boot
  --from-default-profile <name>  initialize a new custom profile from a shipped profile template
  --patch <path>                 extra patch-list overlay applied after the profile layer (repeatable)
  --dump-config                  print the composed profile tree and exit
  --dump-default-config          print the profile tree without its user layer or --patch overlays and exit

Commands:
  web [options] [args...]        boot the web profile (alias of --profile web)
  plugin [options] [args...]     manage a profile's plugins by forwarding the remaining arguments to pnpm
```

Profiles that **actually ship** (VERIFIED — each `--help` ran here; `--profile tui` fails with
`dsh: profile "tui" does not exist`, so the `tui` in the launcher's own examples is illustrative,
not real):

| Profile | Command | What it is |
|---|---|---|
| **`headless`** | `dsh --profile headless "run the tests"` | One task, final answer to stdout, exit and done. |
| **`acp`** | `dsh --profile acp` | **Agent Client Protocol v1** server over stdio JSON-RPC. |
| **`sdk`** | `dsh --profile sdk` | DeepSeek's own stdio JSON-RPC runtime. |
| **`sdk-minimal`** | `dsh --profile sdk-minimal` | Same startup provider, smaller tool selection. |
| **`web`** | `dsh web` / `npx @deepseek-ai/dsh web` | Browser UI on `http://127.0.0.1:3080`. |

**`headless` — the one-shot mode** (its own `--help`, run here, quoted exactly):

```
Usage: dsh --profile headless [options] [task...]

Answer one task, stream reasoning to stderr, print the final assistant message, and exit.

Arguments:
  task        the task text; multiple words are joined by spaces
Options:
  -h, --help  show this help
```

Contract, from `@deepseek-ai/dsh-headless/README.md` (VERIFIED, shipped in the package):
final assistant text on **stdout**; provider reasoning deltas on **stderr** under a
`dsh: reasoning:` heading; **exit 0** on a completed `turn/end`, **exit 1** on abort, error, or no
turn, with `dsh: <code>: <message>` on stderr. It opens no port and leaves nothing running.

**What `headless` does not have, and this matters:** no `--session-id`, no `--resume`, no
`--model`, no `--output-format json`, no `--continue`. It is a pure fire-and-forget one-shot. The
only knob is the task string. If the orchestrator needs identity, resume, or structured output, it
must use `acp` or `sdk` instead — not headless.

**`web` — the visible-terminal question.** `dsh` has **no TUI**. The attachable surface is a
**browser**, not a terminal:

```
Usage: dsh --profile web [options]
Options:
  --host <host>                  bind host
  --no-open                      do not open the Web UI in the default browser
  --port <port>                  listen port; pass 0 to let the OS pick a free one
  --trusted-host <authority...>  extra authority the /api browser-trust fence accepts (repeatable)
```

For the owner's "a visible terminal I can attach to and type into" requirement, the `dsh` answer is
"a browser tab you can attach to and type into". That is arguably *better* for a human supervisor —
it survives terminal death, it is reachable over SSH port-forward, several sessions live in one
window — but it is **not** a terminal, and none of the existing iTerm2-osascript launcher machinery
transfers. Structured output for a supervisor comes from `acp`/`sdk` on stdio, not from the web UI.

### A.3 Structured output

| Mode | Structured? | Tag |
|---|---|---|
| `headless` | **No.** Plain final text on stdout, prose reasoning on stderr. | VERIFIED |
| `acp` | **Yes** — newline-delimited ACP JSON-RPC on stdout, stdout reserved for protocol frames. | VERIFIED |
| `sdk` | **Yes** — newline-delimited JSON-RPC, stdout reserved for protocol frames. | VERIFIED |
| `web` | HTTP `POST /api/<namespace>/<method>`, but behind a browser-trust fence; generated, undocumented as a public API. | VERIFIED (docs/api-gateway.md) |

Both stdio protocols warn explicitly that a composed stdout logger breaks the wire
(`"stdout is the protocol"`). An orchestrator must keep diagnostics on stderr.

---

## B. IDENTITY & RESUME

### B.1 The headline: over the SDK protocol the orchestrator **names the session itself**

Read in the shipped bundle `@deepseek-ai/dsh-sdk-jsonrpc-server/lib/index.js` (VERIFIED):

```js
async prompt(params) {
  if (!this.initialized) throw new Error("SDK server is not initialized");
  const rec = await this.getOrCreateSession(params.sessionId);
  ...
  rec.handle.agent.followup(message);
  return { messageId: message.id };
}
```

`getOrCreateSession(params.sessionId)` — **the client supplies the id and the server creates the
session under it if it does not exist.** This is the same property that made `pi --session-id` the
standout in the field scan, and the same property Claude Code lacks. The orchestrator can allocate
`ticket-417-executor` up front, write it to its own state, and never have to scrape an id out of
output afterwards.

Over **ACP** it is the other way round. From the same kind of read of
`@deepseek-ai/dsh-acp/lib/index.js` (VERIFIED):

```js
async newSession(params, signal) {
  assertOpen();
  validateWorkspaceParams(params);
  const sessionId = brandString(randomUUID());
  ...
}
```

The **server** mints a `randomUUID()` and returns it in the `session/new` result. The orchestrator
records it; it cannot choose it.

### B.2 Resume

| Surface | Resume | Tag |
|---|---|---|
| **ACP** | `session/resume { sessionId, cwd, mcpServers? }`. Advertised in `initialize` as `sessionCapabilities: { close: {}, list: {}, resume: {} }`. | VERIFIED (source) |
| **ACP** | `session/list` → newest-first pages of `{ sessionId, cwd, createdAt }`, optional absolute `cwd` filter, cursor-paged (`sessionListPageSize`, default `100`). | VERIFIED (source) |
| **SDK** | No explicit resume method. Reusing the same `sessionId` on `session/prompt` reattaches through `getOrCreateSession`, and the profile mounts persistence. | VERIFIED (source) |
| **headless** | None. Every invocation is a fresh persisted session. | VERIFIED |

**The four ways ACP resume refuses** (all read in source, all things an orchestrator will hit):

```js
if (sessions.has(sessionId) || activating.has(sessionId) || ctx.sessions.get(sessionId) !== void 0)
  throw invalidParams(`session is already active: ${sessionId}`);
if (persisted === void 0 || persisted.origin === "subagent" || persisted.parentSession !== void 0)
  throw invalidParams(`session is not resumable: ${sessionId}`);
if (!await sameDirectory(persisted.cwd, params.cwd))
  throw invalidParams(`session cwd does not match: ${params.cwd}`);
```

So: **already-live sessions cannot be resumed** (single-owner fence — good for a supervisor, it
means two orchestrator processes cannot both drive one session); **subagent and child sessions are
never resumable** (only roots); and **the cwd must match by physical-directory identity**. A
supervisor that resumes from a different working directory, or across a symlinked checkout, gets
`session cwd does not match`. This must be stored alongside the id.

### B.3 What survives a crash — this is the strongest part of the platform

From `@deepseek-ai/dsh-session-persistence-jsonl/README.md` (VERIFIED, shipped):

> "Each subsequent batch appends lines or one compressed frame and `fsync`s before the append
> resolves; a caught write or sync failure rolls the file back to its prior length. Committed events
> are never rewritten. After a crash, the stored log keeps its interrupted final turn — every record
> in the committed prefix survives, and the resuming reader appends synthetic closers through its
> write handle. An incomplete final raw line is discarded. A torn final Zstandard frame contributes
> only its complete decoded JSONL records; a write handle truncates the torn bytes and durably
> rewrites those recovered records before its first new batch."

That is an explicit, engineered crash contract — `fsync` before each append resolves, append-only,
never rewritten, torn-tail recovery with synthetic closers. It is a materially stronger durability
story than "there is a JSONL file somewhere".

**Reboot:** persistence is file-backed under a configured `root`, so it survives reboot. But nothing
in `dsh` restarts a session after a reboot — the supervisor owns that, using `session/list` +
`session/resume`.

**Provider outage:** `@deepseek-ai/dsh-llm-retry` retries failed model requests at **durable agent-step
boundaries**, with `retryPolicy` offering bounded *normal* retries or unlimited *always* retries.
"Scheduled attempts reach the session log before backoff" — i.e. the retry is itself durable
evidence a supervisor can read. Caveat stated in the same README: **each retry is another billed
provider request**, and always-mode "continues until success, cancellation, or disposal" — an
unattended always-mode retry against a dead provider will quietly burn balance. Bound it.

### B.4 Verdict on the owner's non-negotiable "resume exactly after a crash"

**Met, better than Claude Code, on the ACP/SDK surfaces.** Durable append-only log with fsync and
torn-tail recovery, a list/resume pair, and on the SDK side a client-chosen id. Two real caveats:
resume **does not replay history to the client** (`session/resume` "restores the log without
replaying old updates"), so a supervisor that wants to *see* what happened before the crash must
read the transcript on disk itself (§C); and a session that was mid-turn comes back with synthetic
closers, not with the interrupted turn completed.

---

## C. TRANSCRIPT

### C.1 Where it lives

From `@deepseek-ai/dsh-session-persistence-jsonl/README.md` (VERIFIED):

```text
<root>/
  --<normalized-cwd>--/          # readable project directory (or _no-cwd/)
    <encoded-id>/                # session-owned directory
      session.jsonl.zstd         # released v0, compressed root
      session.v1.jsonl.zstd      # released v1, compressed root
      session.v2.jsonl.zstd      # released v2, compressed root
      session.jsonl              # released v0, raw root
      session.v1.jsonl           # released v1, raw root
      session.v2.jsonl           # released v2, raw root; later versions use vN
```

`root` is **required and has no default** — "a `process.cwd()` default would scatter session files
as the process's cwd changes". The shipped profiles set it; a supervisor composing its own profile
must set it and therefore **knows the path by construction**, which is better than discovering it.
The `--<normalized-cwd>--` convention is the same shape as pi's session directory naming.

### C.2 The compression trap — the single most important operational detail on this axis

| Field | Default | Meaning |
|---|---|---|
| `root` | required | Root directory for all session files |
| `compression` | **`'zstd'`** | `'zstd'` checksummed frames, or `'none'` newline-delimited UTF-8 text |

> "With `compression: 'none'`, the log is newline-delimited text an external reader can consume
> directly; **the compressed default must be read through the backend.**" (VERIFIED)

**By default a supervisor cannot `tail -f` a `dsh` transcript.** It is checksummed Zstandard frames.
A supervisor that wants to watch progress by reading the file must compose the persistence row with
`compression: 'none'` at profile-creation time, accepting larger logs. This is a one-line patch, but
it has to be made *before* the run, and it is invisible unless you read this README.

### C.3 The live path, which is better than reading the file

Reading the file is the fallback. The real answer is the protocol.

- **SDK**: `session.event` notification carries `{ sessionId, event }` for **every durable fact**,
  plus `session.status` `{ sessionId, status }` for agent lifecycle, plus `subagent.started`
  `{ parentSessionId, childSessionId }` (VERIFIED, read in `dsh-sdk-jsonrpc-server/lib/index.js`).
- **ACP**: `session/update` carries "committed assistant messages and thoughts, generic tool
  lifecycle, configuration changes, and context usage, serialized per session" — deliberately
  *semantic*, not raw. "Raw provider deltas, retry attempts, DSH presentation data, and unsupported
  content stay off the wire." (VERIFIED, `dsh-acp/README.md`)

The architectural rule stated in `docs/agent-lifecycle.md` (VERIFIED):

> "SDK users that need replayable transcript data should consume `session/event`; `agent/*` is the
> live coordination API for queue/status, prompt interception, request construction, steering,
> continuation, and errors."

So a supervisor gets **push, not poll** — the exact opposite of the current harness's file-tailing
model. The event stream is the transcript, live, structured, with the same durable facts that land
in the log.

### C.4 Also on this axis

- `@deepseek-ai/dsh-session-query` / `-sqlite` — "session reads, traces, filters, and search",
  SQLite-backed (VERIFIED, package exists).
- `@deepseek-ai/dsh-session-stats` — "whole-session turn and step counts plus LLM, tool, first-token
  and decode wall times ... from the complete durable log, so paging and compaction do not change
  them" (VERIFIED). A supervisor judging "is this session making progress or spinning" has real
  numbers, not a heuristic.
- `@deepseek-ai/dsh-session-telemetry-otel` — OpenTelemetry export (VERIFIED, package exists).
- Session format is **v3** as of `dsh-v0.1.5-alpha.1`, with a formal migration chain
  (`dsh-session-format-v0-to-v1`, `-v1-to-v2`, `-v2-to-v3`) and an explicit policy that
  "an alpha, beta, or release-candidate product publication establishes released Session-format
  obligations" (VERIFIED, `docs/session-format-status.md`). They take log compatibility seriously
  even in a 0.1.x. A parser the orchestrator writes will not be invalidated casually — but it **will**
  need to key on the `vN` filename.

---

## D. CONTEXT — read, and (partly) trigger

### D.1 Reading context fullness: **yes, and it is a first-class wire field**

This is the strongest finding on this axis in the whole field so far. Read in the shipped
`@deepseek-ai/dsh-acp/lib/index.js` (VERIFIED, exact source):

```js
/** Report current context occupancy only when DSH has both usage and capacity facts. */
function usageUpdate(ctx, session, event) {
	if (event.data.usage === void 0) return void 0;
	const size = session.requestContext()?.contextWindow;
	const meter = ctx.get("tokenMeter");
	if (size === void 0 || meter === void 0) return void 0;
	return {
		sessionUpdate: "usage_update",
		used: meter.measure(session).totalTokens,
		size
	};
}
```

An ACP client receives `{ sessionUpdate: "usage_update", used, size }` — **tokens used and context
window size, pushed, per session, unprompted.** No scraping a status line, no estimating from the
transcript, no `/context` command. The supervisor divides and gets occupancy.

Note the guard: the update is emitted **only** when the provider reported usage *and* a
`contextWindow` is known *and* `tokenMeter` is mounted. A composition without `dsh-token-meter` is
silently blind. A supervisor must verify it is receiving `usage_update` at all and not assume
absence means "not full".

The underlying service, `ctx.tokenMeter` (`@deepseek-ai/dsh-token-meter`, VERIFIED):
`measure(session, requestHeader?)` returns `totalTokens` (request-and-response pressure) and
`surfaceTokens`; it replays the durable log, is deterministic, and **makes no model calls**. It also
registers three projections: `tokenUsage` (`uncachedInputTokens`, `outputTokens`, `cacheReadTokens`,
`cacheWriteTokens` — i.e. **cost telemetry**), `contextPressure` (`pressureTokens`,
`projectedTokens`, `contextWindow`), and `contextBreakdown` (`systemTokens`, `toolsTokens`,
`messageTokens`). `projectedTokens` — "what the next request's prompt would cost" — is precisely
the number a supervisor wants for "will this session survive one more step".

### D.2 Triggering compaction from outside: **no, and this is the real gap**

`@deepseek-ai/dsh-compaction-basic` gives four behaviors (VERIFIED):

| Trigger | Mechanism | Externally invokable? |
|---|---|---|
| Automatic pressure | `agent/pre-step` hook, at `thresholdRatio` × routed context window | No — internal, but automatic |
| Context-overflow recovery | `agent/request-error`, condense + retry in the open step | No — internal, but automatic |
| `/compact` command | `@deepseek-ai/dsh-command-compact`, via `ctx.commands` | **Only in a chat UI** |
| Tool-result pruning | `dsh-compaction-tool-result-pruner`, before summary selection | No — internal |

Defaults (VERIFIED, complete policy surface): `thresholdRatio: 0.8`, `retainRatio: 0.16`,
optional `retainTokens`, optional `summarizationProvider`/`summarizationModel` (so summarization can
be routed to a **cheaper model than the main run** — a real cost lever), and per-route
`modelPolicies` overrides.

**Why `/compact` is not reachable from a supervisor.** ACP's own contract says, verbatim:

> "Unsupported surfaces are omitted or reject: `session/load`, deletion, fork, additional
> directories, SSE or ACP-transport MCP, **modes, commands, plans, terminals**, client filesystem
> operations, and elicitation."

`commands` is on the unsupported list. The SDK protocol's entire method surface is `initialize`,
`session/prompt`, `shutdown` (VERIFIED — read from the dispatch `case` labels in the bundle), so it
has no command channel either. **`/compact` exists, and neither control protocol can reach it.**

### D.3 Proof that compaction happened

Good, on both paths. `docs/agent-lifecycle.md` (VERIFIED):

> "`dsh-compaction-basic` uses `agent/pre-step` for pressure before request derivation and
> `agent/request-error` only for canonical context overflow. Once either trigger qualifies, optional
> tool-result pruning runs before summary selection."

and `dsh-command-compact` states that even *failed* attempts are "recorded in the session log". So
compaction leaves durable evidence in the transcript, and the `usage_update` occupancy figure drops
observably on the next turn. A supervisor can prove compaction occurred **after the fact**; it just
cannot **cause** it.

### D.4 Verdict on the owner's non-negotiable "compaction triggered from outside with proof"

**Half met, and the better half.** Reading occupancy from outside is fully solved and is the best
answer in the field. Proof-after-the-fact is solved. **Triggering from outside is not solved.**

**Closest workarounds, with their costs:**

1. **Tune the threshold instead of triggering.** Compose the profile with a `thresholdRatio` the
   supervisor chooses per role (e.g. 0.6 for a long unattended executor), so auto-compaction fires
   where the supervisor wants it. *Cost:* set at profile-composition time, not per-session, and the
   shipped profiles use `patchReload: startup` so **configuration changes require a restart** — you
   cannot retune a live session.
2. **Compose a custom profile that exposes compaction over the wire.** Everything is a plugin; a
   ~small plugin could mount a Remote method calling the compaction service. *Cost:* the orchestrator
   now maintains a `dsh` plugin against a 0.1.x RC with declared breaking changes.
3. **Hand off instead of compacting.** Watch `usage_update`, and when occupancy crosses the line,
   `session/close` and open a fresh session seeded with a summary the supervisor wrote. *Cost:* the
   supervisor owns summarization; but this is engine-agnostic, works identically on every platform,
   and is probably the right design for a provider-agnostic orchestrator anyway.
4. **Send `/compact` as a prompt.** Will not work — commands are a UI surface, not model input; the
   model would just see the literal text. Do not ship this.

---

## E. QUOTA

### E.1 There is a real endpoint, and it is dead simple

`GET https://api.deepseek.com/user/balance` (VERIFIED, `api-docs.deepseek.com/api/get-user-balance`,
read 2026-09-19). Response schema, quoted from the docs:

```json
{
  "is_available": true,
  "balance_infos": [
    { "currency": "CNY", "total_balance": "110.00",
      "granted_balance": "10.00", "topped_up_balance": "100.00" }
  ]
}
```

- `is_available` — *"Whether the user's balance is sufficient for API calls."* A single boolean the
  supervisor can gate on.
- `currency` — `CNY` or `USD`.
- `total_balance` = `granted_balance` + `topped_up_balance`; granted (promotional) balance is spent
  **first** when both exist (VERIFIED, pricing page "Deduction Rules").

It is the **only** usage/limits endpoint in the docs — the full API reference is
`create-chat-completion`, `create-completion`, `create-response`, `create-file`, `delete-file`,
`list-files`, `retrieve-file`, `list-models`, `get-user-balance` (VERIFIED, from the sitemap).

### E.2 What windows exist — and the answer is the interesting part

**There are none.** No rolling five-hour window, no weekly window, no token allowance, no monthly
cap, no plan tier. DeepSeek is **prepaid credit**. The only capacity axes are:

| Axis | Value | Tag |
|---|---|---|
| Balance | prepaid, no reset — it only goes down until you top up | VERIFIED |
| **Concurrency** | `deepseek-flash` **2500**, `deepseek-v4-pro` **500**, **per account, not per API key** | VERIFIED |
| Capacity expansion | "submit a capacity expansion request ... **no additional cost**" | CLAIMED (vendor) |
| Per-`user_id` concurrency | For expanded accounts only, each `user_id` gets its own 2500/500 ceiling; an empty id is a distinct special `user_id` | VERIFIED |

**This is the single most consequential fact in this document for an overnight queue.** The owner's
whole rate-limit design — read `five_hour.utilization`, read `seven_day.utilization`, pause until
`resets_at`, resume — has **no counterpart here and no need for one**. There is no window to wait
for. A DeepSeek executor never says "come back in four hours". It says "top up" or "slow down", and
both are immediate. The supervisor's quota logic for DeepSeek is:

```
balance check     → GET /user/balance, gate on is_available, alert on a low total_balance
concurrency check → count your own in-flight requests against 2500 / 500
```

That is a much simpler contract than Anthropic's, and it means a DeepSeek-backed role is the natural
**overflow lane** for a queue whose Claude lane is window-blocked.

### E.3 Limit-hit signalling, in band

From `quick_start/error_codes` (VERIFIED):

| Code | Meaning | What a supervisor does |
|---|---|---|
| **402 — Insufficient Balance** | *"You have run out of balance."* | **Hard stop for that account.** Switch account or top up. No reset time exists. |
| **429 — Rate Limit Reached** | *"You are sending requests too quickly."* The docs' own advice: *"We also advise users to temporarily switch to the APIs of alternative LLM service providers, like OpenAI."* | Back off, reduce concurrency. |
| 503 — Server Overloaded | high traffic | retry after a brief wait |
| 500 — Server Error | server issue | retry |

`@deepseek-ai/dsh-llm-deepseek/lib/index.js` handles `429` and reads a `retry-after` header
(VERIFIED — both strings present in the shipped bundle, alongside a `RATE_LIMIT` classification).
So a `retry-after` **is** honoured by DeepSeek's own adapter, which is strong evidence the API emits
one on 429; I could not confirm the header's presence or format against a live response because
there is no API key on this machine (**UNKNOWN**).

**No reset time is exposed** on 402, because there is nothing to reset. **UNKNOWN:** whether
`x-ratelimit-*` style headers exist on normal responses — not documented, not testable here.

### E.4 Two more capacity-shaped things a supervisor must know

**Keep-alive, and the 10-minute cliff.** From `quick_start/rate_limit` (VERIFIED):

> "Non-streaming requests: Continuously return empty lines. Streaming requests: Continuously return
> SSE keep-alive comments (`: keep-alive`). ... **If the request has not started inference after 10
> minutes, the server will close the connection.**"

A supervisor's liveness heuristic must not treat empty lines or `: keep-alive` comments as a stalled
session — they are the healthy signal. And a request queued behind capacity for ten minutes is
dropped by the server, not by the client.

**Peak / off-peak, which is a *scheduling* axis, not a quota axis** (VERIFIED, pricing page):

> "Off-peak rates are half of the peak rates. Peak hours are **01:00 - 04:00 and 06:00 - 10:00 UTC,
> Monday through Friday**, excluding Chinese public holidays. All other hours are off-peak, including
> weekends and Chinese public holidays in full."

For an overnight run from Ukraine (UTC+3 — local 22:00–06:00 is **19:00–03:00 UTC**), roughly the
last two hours of an overnight queue fall inside peak and cost **double**. The rest is half price.
Weekends are entirely off-peak. A cost-aware scheduler that front-loads DeepSeek work before 01:00
UTC and holds back after it is worth real money — see §J.1 for the arithmetic.

### E.5 Verdict on the owner's non-negotiable "read remaining quota programmatically"

**Met, and trivially — but it is a different quantity than he is used to.** One unauthenticated-shape
GET returns a boolean and a number. There is no utilization percentage because there is no window;
"remaining capacity" is money. The supervisor needs a **second kind of quota model**: percent-of-window
for Anthropic-style accounts, currency-remaining for credit-style accounts. That distinction is a
design requirement for the orchestrator, not a DeepSeek quirk — Kimi, GLM, MiniMax and Xiaomi will
all be credit-style too.

---

## F. ACCOUNTS

### F.1 What an "account" is here

A **DeepSeek API key** (`sk-…`), issued from the DeepSeek Platform, tied to a balance. Several keys
can belong to one account; **the concurrency limit is computed per account, not per key**
(VERIFIED). So multiple keys under one account give you *no* extra capacity and *no* separate
balance — only separate revocation. Real account separation means **separate DeepSeek accounts with
separate balances**.

`user_id` (VERIFIED, `quick_start/rate_limit`) is a *sub-account* mechanism, not an account
mechanism. It must match `[a-zA-Z0-9\-_]+`, max 512 chars, and gives content-safety isolation,
**KVCache isolation**, and scheduling isolation. For an orchestrator the KVCache angle is the
interesting one: passing a per-role `user_id` keeps roles' caches from colliding — but it also keeps
them from **sharing** cache, which with DeepSeek's cache-hit pricing (§J.1) is usually the wrong
trade. Set it only when isolation is actually wanted. Wire placement:

- OpenAI format: top-level `"user_id"` in the body (OpenAI SDK: under `extra_body`).
- Anthropic format: `"metadata": {"user_id": "…"}`.

### F.2 Switching a new session to a chosen account

**Path 1 — a CLI pointed at DeepSeek (the practical path today).** Pure environment. Nothing is
stored, nothing is switched, no keychain, no GUI prompt:

```sh
export ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
export ANTHROPIC_AUTH_TOKEN=<that role's DeepSeek API key>
```

This is the **cleanest axis-F story of any platform in the scan**. Compare Claude Code's own
accounts: `CLAUDE_CONFIG_DIR` plus a derived macOS Keychain service name plus a possible one-time
GUI "Always Allow" dialog that will block an unattended run (field scan §4). A DeepSeek key is one
environment variable with no ambient state at all. Per-role accounts are `env -i`-clean.

**Path 2 — `dsh` itself.** Credential resolution has a fixed precedence
(`@deepseek-ai/dsh-credentials-local`, VERIFIED):

> "the **launch environment wins**, followed by the stored file, the project's `.env`, and the
> harness-home `.env`; a newly saved value immediately overrides older `.env` values."

| Field | Default |
|---|---|
| `path` | `<harness home>/.credentials.yaml` |
| `dshHome` | `$DSH_HOME` or `~/.dsh` |
| `watch` | `true` (reloads on change) |
| `debounceMs` | `100` |

And the home itself (`@deepseek-ai/dsh-home-paths`, VERIFIED): *"An explicit configured path wins
over `$DSH_HOME`, which wins over `~/.dsh`; blank environment values are ignored."*

So there are **two independent per-role switches**, both environment-only:

```sh
DSH_HOME=~/.dsh-accounts/executor-a  dsh --profile acp   # whole harness home: profiles + credentials
# or, keeping one home, just override the key in the launch environment (highest precedence)
```

`DSH_HOME` is the stronger one — it isolates profiles, plugins, credentials and (if the profile
points there) session roots in one variable, exactly the way `CLAUDE_CONFIG_DIR` does for Claude
Code and a profile switcher. A supervisor can build `~/.dsh-accounts/<role>/` per account and never think about
it again.

**Verified on this machine:** setting `DSH_HOME` to a scratch directory caused `dsh` to materialize
`$DSH_HOME/profiles/{acp,headless,node_modules}` and `$DSH_HOME/.anonymous-user-id` there, with
nothing written to `~/.dsh` (which does not exist here). The isolation works as documented.

### F.3 Changing a **running** session's account

**No, on every surface** (VERIFIED). ACP's `session/set_config_option` can change `model` and
`reasoning_effort` at runtime — *"a prompt snapshots that selection ... and pins it across every
model step in that turn; a concurrent option change applies to the next turn"* — but the
**credential is not a session config option**. The SDK protocol binds provider/model at
`initialize`, once per process. And `dsh-sdk-app` states plainly: *"Configuration changes require
restart — the shipped `sdk` profile uses `patchReload: startup` so one stdio connection never
observes a replacement server or Agent dependency."*

**Closest workaround:** `session/close`, then relaunch the process with a different `DSH_HOME` or
`ANTHROPIC_AUTH_TOKEN`, then `session/resume` the same `sessionId` from the new process. The log is
durable and the cwd fence is satisfied, so this genuinely works. **Cost:** one process restart, a
cold KV cache on the new account (every subsequent request re-pays cache-*miss* input pricing until
prefixes re-persist — see §J.1, this is a real cost, not a rounding error), and a window where the
session is neither live nor resumable.

An honest note: on the Claude-Code-pointed-at-DeepSeek path (thing 3), "changing the running
session's account" is exactly as impossible as it is for Claude Code today, for the same reason —
the env was read at process start.

### F.4 Verdict on the owner's non-negotiable "switch accounts per role"

**Met cleanly for new sessions, unmet for running ones.** For new sessions this is the *easiest*
platform in the scan — one env var, no keychain, no GUI dialog, no ambient config file that a
daemon-spawned process might read instead (the `~/.claude.json` vs `~/.claude/.claude.json` trap
from the field scan has no analogue here).

---

## G. INTERVENTION

### G.1 Sending an instruction into a running session, and knowing it arrived

**Yes, on both protocols, with a durable receipt — this is a best-in-field answer.**

**SDK** (VERIFIED, source): `session/prompt { sessionId, contentBlocks }` →
`{ messageId }`. The README is explicit about what that receipt means and does not mean:

> "An accepted prompt queues one identified user message and immediately returns `{ messageId }`;
> the server then streams every durable fact as `session.event` and every whole-agent lifecycle
> transition as `session.status`. **It does not assign an assistant message or `turn/end` to a
> prompt**, and independent requests may enqueue more work on the same session."

So the receipt is *"your message is durably queued under this id"*, not *"the model answered it"*.
That is the honest and correct semantics for a supervisor: correlate by `messageId` against the
`session.event` stream, and don't expect a request/response turn.

**ACP** (VERIFIED): `session/prompt`, one prompt in flight per session, settling with a `stopReason`
after Agent idle **and** ordered update delivery. Stronger settlement, less concurrency.

The mechanism underneath both, from `docs/agent-lifecycle.md` (VERIFIED):

```
User->>Agent: followup(content)
Agent-->>SDK: agent/inbox/spliced
Agent-->>SDK: agent/inbox/inserted { message }
Agent->>Driver: queued work wakes driver
Driver-->>SDK: agent/status running
Driver-->>SDK: agent/inbox/claimed { message, turn } per message
```

A message goes into a real **inbox** with observable splice/insert/claim events. A supervisor sees
the instruction inserted, then sees it *claimed into a specific turn*. Contrast the field-notes
record of the current harness — "a nudge that cannot submit stranded text" — this is the structural
fix: there is no screen, no keystroke, no submit; text cannot be stranded because it was never typed.

Steering while mid-turn is explicitly supported: *"Steering and injected context pass through the
same waterfall after a later claim operation takes their next-step batch."*

**Cancellation:** ACP `session/cancel` / `$/cancel_request`, and, read in source, *"Cancel the active
prompt, or autonomous work when no ACP prompt exists"* — so a supervisor can stop a session that is
grinding on its own, not only one it prompted. Unknown session ids are no-ops (safe to fire blind).

### G.2 Answering a permission prompt programmatically

**Yes, over ACP.** Read in `dsh-acp/lib/index.js` (VERIFIED, exact source):

```js
options: [{
  optionId: "allow-once", name: "Allow once", kind: "allow_once"
}, {
  optionId: "reject-once", name: "Reject",     kind: "reject_once"
}]
...
return conn.request(methods.client.session.requestPermission, params);
}).then(({ outcome }) => {
  if (outcome.outcome === "cancelled") return "cancelled";
  return outcome.optionId === "allow-once" ? "allowed-once" : "rejected";
});
```

The server *calls the client*. The supervisor is the answerer, in-protocol, with a JSON-RPC
response. No screen, no expect script, no keystroke injection. The README says it plainly:
*"A permission prompt with one-shot allow/reject choices; **your client can answer automatically**."*

**The sharp edge:** the only options are `allow-once` and `reject-once`. **There is no "allow always"
over ACP.** Every single gated action pings the supervisor. For an overnight unattended run that is
either (a) fine, because the supervisor is a program and answering is free, or (b) a firehose,
depending on the permission preset. The right configuration is to set a permissive preset at the
profile level (§H) so few prompts are raised, and use the ACP answerer as the **exception handler**,
not the main path.

### G.3 Answering the session's own *question* (not a permission prompt)

**This is the one real hole, and it is worth being precise about.**

`@deepseek-ai/dsh-tool-ask-user` gives the model an `ask_user_question` tool: *"accepts one or more
questions and returns their answers as compact JSON. The call waits until an answer is accepted or
the turn is cancelled; **if no answer handler accepts it, the model receives an error.**"* The seam
is `ctx.userQuestions` (*"the service a model-facing tool or permission plugin uses when it needs to
pause work and ask the human"*). Both VERIFIED.

But ACP's unsupported list includes **`elicitation`** (VERIFIED, quoted in §D.2), which is ACP's
name for exactly this. And the SDK protocol has no question channel — its whole surface is
`initialize` / `session/prompt` / `shutdown`.

**So:** over ACP the supervisor can answer *permission* prompts but not *clarifying questions*; a
session that calls `ask_user_question` with no mounted answerer gets a **tool error**, and — per
`dsh-user-approval` — the fail-closed philosophy is consistent: *"Missing or failed answerers return
`unavailable`, so the action fails closed."*

**Closest workarounds:**
1. **Don't mount `dsh-tool-ask-user`** in unattended profiles. The model then has no way to ask, and
   must decide. Clean, and the tool's own docs note runtime-owned child agents already work this
   way: *"Runtime-owned child agents cannot call this tool and must report unresolved questions in
   their final result."* That is the right pattern to copy for unattended roles. *Cost:* the model
   guesses instead of asking.
2. **Mount a custom `ctx.userQuestions` answerer plugin** that forwards to the supervisor over a
   side channel. *Cost:* a bespoke plugin against a 0.1.x RC.
3. **Watch the event stream for the question and steer.** The `ask_user_question` call appears as a
   `tool/call` in `session.event`; the supervisor can see it and inject a follow-up. *Cost:* the
   tool call itself still errors; you are answering the *next* turn, not the blocked one.

### G.4 Verdict on the owner's non-negotiable "answer a session's own question programmatically"

**Met for permission prompts (in-protocol, one JSON-RPC response). Not met for clarifying
questions** — the seam exists in the harness but is not exposed on either wire protocol. The honest
recommendation for unattended roles is workaround 1: remove the ability to ask, and require the
model to report unresolved questions in its final result, which is what DeepSeek's own subagent
runtime already does.

---

## H. GUARDRAILS

All VERIFIED from shipped package READMEs unless marked.

| Mechanism | Package | What it gives |
|---|---|---|
| **Permission presets** | `dsh-permission-presets` | One selector combining sandbox mode + approval policy. Shipped table includes **`workspace-write`** and **`danger-full-access`**. A deployment sets a default for new sessions; changing the default does not alter existing sessions. `/permission` reports or changes it. A non-matching combination shows as `custom`, which users can see but not select or persist. |
| **Approval policy** | `dsh-user-approval` | `ask` → each request goes to *"the deployment's human **or machine** answerers"*; `never` → rejects without prompting. **Missing or failed answerers return `unavailable`, so the action fails closed.** An approval applies only to that request. Every request and outcome lands in the session's audit log. |
| **Sandbox policy** | `dsh-sandbox-policy` | One file-effect policy across every confined bash, filesystem and terminal call. Deployment sets default mode + fallback workspace root; each session can switch modes independently and **session choices survive restart**. The model is told the effective policy and workspace before each request. |
| **Sandbox runtime** | `dsh-sandbox-local` | Confines commands *and their descendants* on Linux, **macOS** and Windows. Picks a platform runner automatically, and **fails with `SANDBOX_UNAVAILABLE` when none is usable, so commands never silently run without confinement**. Reports `full` or `partial` enforcement plus denial and runner-failure signatures. (`node-addon-system-darwin-arm64` ships in the install here, so the macOS runner is a real native component — VERIFIED by presence.) |
| **Claude Code hooks** | `dsh-hooks-claude-code` | **Runs the owner's existing Claude Code `hooks.json`/settings hooks unmodified.** Session, prompt, tool, stop and subagent moments. Hooks can block prompts or tool calls with model-visible reasons, add conversation context, or force another model turn. |
| **Codex hooks** | `dsh-hooks-codex` | Same for an existing Codex `hooks.json`: five points — session start, prompt submission, before/after tool execution, stop. |
| **Tool timeouts** | `dsh-tool-call-timeout-policy`, `dsh-timeout` | Per-call timeout policy (package present). |
| **Output retention / spill** | `dsh-output-retention`, `dsh-spill`, `dsh-spill-policy` | Bounding oversized tool output (packages present). |

The `dsh-hooks-claude-code` row deserves emphasis: **the owner's existing guardrail investment is
portable.** The hooks in `~/.claude/hooks` and `settings.json` are not thrown away by moving a role
to `dsh`; there is a first-party adapter that runs them. That is unusual and materially lowers the
cost of adding `dsh` as a second executor.

### What it will do unattended without asking

Governed entirely by the preset. With `danger-full-access` + `never`, it will run anything the model
emits without a prompt. With `workspace-write` + `ask` and a supervisor answering ACP permission
requests, every gated action is a round trip. There is no middle "allow-always for this tool" over
ACP (§G.2) — the middle ground has to be expressed as a **preset**, not as accumulated approvals.

### The safety notice, which should be read as written

`SAFETY.md` in the repo (VERIFIED, quoted):

> "DeepSeek Harness is experimental developer-preview software. **It has not undergone a security
> audit and must not be treated as secure or production-ready.** ... Sandboxing, approval prompts,
> and permission controls can reduce risk, but **they do not guarantee isolation or prevent damage**.
> ... Do not rely on DeepSeek Harness as the sole security control for untrusted workloads."

And `dsh-credentials-local`: *"Only your OS user can read the file, but **agent tool processes run as
that same user**, so this store cannot isolate secrets from the agent."* An unattended `dsh` session
with shell access can read the credential file of every account configured in that `DSH_HOME`. That
is an argument for per-role `DSH_HOME` isolation on top of per-role keys.

---

## I. EXTENSIBILITY

**MCP** (`dsh-mcp-client`, VERIFIED): external MCP servers' tools appear as native harness tools
under stable names like `mcp__github__create_issue` — the same naming convention as Claude Code, so
prompt text and allowlists referencing tool names transfer. **stdio and Streamable HTTP** are
supported (ACP `initialize` advertises `mcpCapabilities: { http: true }`, VERIFIED in source); **SSE
and ACP-transport MCP are not**. No server is enabled by default. **MCP resources and prompts are
unsupported — tools only.** Caveat from the README: *"Tool definitions add tokens to every model
request, while a slow or crashed server can delay startup or make its tools fail until recovery."*
For ACP, MCP servers are declared per `session/new` and re-declared on `session/resume`; the ACP
client is a **trusted controller** — *"stdio MCP entries authorize their absolute commands and
environment, HTTP entries authorize their absolute HTTP(S) URLs and headers"*.

**Skills** (`dsh-skill` + `dsh-skill-filesystem` + `dsh-tool-skill`, VERIFIED): a catalog of reusable
task-specific instructions from local directories, embedded plugin data, or remote services, with
predictable duplicate-name resolution and on-demand loading of full instructions. Structurally the
same idea as Claude Code skills. **UNKNOWN:** whether the on-disk format is compatible with
`~/.claude/skills` — the README describes the seam, not the file format.

**Subagents** (`dsh-tool-subagent`, `dsh-subagent-spawn-in-process`, `dsh-subagent-fork-in-process`,
`dsh-subagent-acp`, VERIFIED): a named delegation tool with **`one-shot`** mode (waits for the child)
and **`continuable`** mode (starts a persistent background child, returns an id for later messages).
Per-instance child persona, tool access, and **depth limits**. Backends can expose approved child
LLM providers/models/effort — so a subagent can run on a *different, cheaper* model than its parent.
`subagent.started { parentSessionId, childSessionId }` is pushed to SDK clients, so a supervisor can
see the tree form in real time. `dsh-subagent-acp` spawns `dsh --profile acp` out-of-process — i.e.
**`dsh` orchestrates `dsh` over the same protocol an external orchestrator would use.** That is a
strong signal the protocol is real and exercised.

**Workflow engine — the GSD question.** `dsh-workflow` (VERIFIED): *"Run a plain-JavaScript
orchestration script that fans work out to subagents and returns the script's final JSON value.
Scripts can use `agent()`, `parallel()`, `pipeline()`, `phase()`, and `log()`; models normally access
them through the `workflow` tool."* There is a first-class, subagent-heavy, phase-shaped workflow
primitive **already inside the harness**. A GSD-style engine could plausibly run here — but it would
be a **port**, not a lift-and-shift: GSD is markdown skills + slash commands + `.planning/` state;
`dsh-workflow` is JavaScript. The commands surface exists (`dsh-commands`, `dsh-command-goal`,
`dsh-command-compact`, `dsh-command-feedback`) but, as established in §D.2, **commands are not
reachable over either control protocol**, so a supervisor cannot invoke a GSD-style slash command
remotely. That is the blocking issue for running GSD inside `dsh` under an orchestrator.

**Other relevant primitives** (all VERIFIED as shipped packages): `dsh-jobs` (background jobs with
stable `<kind>-N` ids, agent-scoped ownership, completion as an in-session notice without polling);
`dsh-schedule` (durable reminders returning as ordinary follow-up messages — *"delivery requires a
live root agent: closed sessions keep reminders overdue until resumed"*); `dsh-webhook` /
`dsh-webhook-github` (`ctx.webhookRuntime`, turning an external event into a new root Session —
a supervisor could enqueue work by webhook); `dsh-tool-ralph` (Ralph-style fresh-agent iteration
against an immutable objective, with the notable warning *"those reports are not independently
verified"* and *"Use it only when the direct human explicitly requests Ralph-style fresh-agent
iteration"*); `dsh-plan-mode`; `dsh-tool-todo`; `dsh-terminal` / `dsh-tool-bash-persistent`;
`dsh-browser-use` and `dsh-computer-use` provider seams (Playwright MCP, Chrome DevTools MCP,
Stagehand, CUA driver).

**Config precedence** (VERIFIED): profile layer → `--patch` overlays (repeatable) → user layer.
`dsh --dump-config` prints the composed tree; `dsh --dump-default-config` prints it without the user
layer or patches. Both exit without running anything — a supervisor can **assert on the composed
configuration before launch**, which is a genuinely useful preflight primitive that most CLIs lack.
Plugins are installed per profile via `dsh plugin --profile <name> add <package>` (forwards to pnpm).

**Architecture, for context:** everything is a Cordis plugin, including the agent loop
(`dsh-agent-loop`) and the LLM adapter registry (`ctx.llm`). 241 `@deepseek-ai/*` packages installed
in the sandbox for the base install. The LLM seam is genuinely open — `dsh-llm-pi-ai` ships
alongside `dsh-llm-deepseek`, so **`dsh` can drive non-DeepSeek models**, and a separate npm package
`@deepseek-ai/dsh-llm-deepseek` exists as *"DeepSeek chat-completions adapter for the DeepSeek
Harness LLM seam"*. `dsh` is not locked to DeepSeek models.

---

## J. OPERATIONAL REALITY

### J.1 Cost model — the real reason to care about this platform

Pricing, **USD per 1M tokens**, from `api-docs.deepseek.com/quick_start/pricing` (VERIFIED,
read 2026-09-19):

| | `deepseek-flash` off-peak | `deepseek-flash` peak | `deepseek-v4-pro` off-peak | `deepseek-v4-pro` peak |
|---|---|---|---|---|
| Input, **cache hit** | **$0.003** | $0.006 | $0.022 | $0.044 |
| Input, **cache miss** | **$0.15** | $0.30 | $0.66 | $1.32 |
| Output | **$0.60** | $1.20 | $1.98 | $3.96 |

Both models: **1M context, 384K max output** (VERIFIED). `deepseek-flash` = DeepSeek-V4.1-Flash;
`deepseek-v4-pro` = DeepSeek-V4-Pro-0813.

**The cache-hit ratio is 50:1.** $0.003 vs $0.15 per Mtok. An agent loop is the ideal shape for this:
the same system prompt, tool schemas and growing transcript prefix on every step. Context caching is
**on by default, no code change** (VERIFIED), and every response reports `prompt_cache_hit_tokens`
and `prompt_cache_miss_tokens` in `usage` — so a supervisor can **measure its own cache efficiency
per session** and treat a collapsing hit rate as a defect signal. That is a genuinely novel telemetry
axis the current harness has no equivalent of.

Three cache rules that an orchestrator's prompt construction must respect (VERIFIED,
`guides/kv_cache`): cache units are persisted at **request boundaries** (end of user input and end of
model output), on **detected common prefixes across requests**, and at **fixed token intervals** for
long inputs/outputs. A subsequent request hits only if it **fully matches** a persisted unit. Cache
construction *"takes seconds"*, entries clear *"usually within a few hours to a few days"*, and the
system is **best-effort with no guaranteed hit rate**. Practical consequence: anything the supervisor
injects at the *front* of a prompt (a timestamp, a rotating instruction, a per-run id) destroys the
prefix and re-pays the 50× miss rate for the whole transcript. **Put supervisor-injected volatile
text at the end, never the beginning.**

**A live pricing caveat that invalidates the v4-pro column.** From `news/news260910` (VERIFIED,
dated 2026-09-10):

> "Tests by multiple parties put V4.1-Flash ahead of V4-Pro on performance, cost, speed & total
> runtime. **We're phasing out V4-Pro.** Starting at **04:00 UTC on Sept 14, 2026**, all
> `deepseek-v4-pro` requests will route to V4.1-Flash **at V4.1-Flash rates**. This will continue
> until V4.1-Pro launches."

That date is **five days ago**. So today, asking for `deepseek-v4-pro` gets you Flash at Flash
prices, and the model-mapping trick below (`claude-opus` → `deepseek-v4-pro`) currently lands on
Flash too. The v4-pro column is a **future** price that will return when V4.1-Pro ships. An
orchestrator that hard-codes a cost model per model name will be wrong in both directions across
that transition. Price should be **read from `usage`**, not assumed.

**Scale, for the overnight-queue decision.** At off-peak Flash rates, a transcript that is 90%
cache-hit costs on the order of **$0.018 per Mtok of input**. Against frontier subscription-window
economics this is not "cheaper", it is a different category — the constraint stops being *time until
the window resets* and becomes *dollars spent*, which is continuous, predictable, and does not make
a queue sit idle for four hours.

### J.2 Install footprint and platform support

| Path | Footprint | Tag |
|---|---|---|
| **API only** | Zero. Three environment variables. | VERIFIED |
| **`dsh` via npx** | `npx @deepseek-ai/dsh web` — nothing installed permanently | VERIFIED (README) |
| **`dsh` installed** | **522 packages, ~59 s** in a clean sandbox here; 241 of them `@deepseek-ai/*`. Includes a native addon (`node-addon-system-darwin-arm64`) and `node-pty`. | VERIFIED (run here) |
| **From source** | `pnpm install && pnpm run build && pnpm dsh web` | CLAIMED (README) |
| **Node requirement** | Runs on **v22.18.0** here. Some transitive deps (`@earendil-works/pi-ai@0.85.1`) want `>=22.19.0` and emit `EBADENGINE` warnings; it worked anyway. | VERIFIED |
| **macOS** | Fully supported; native sandbox runner ships for darwin-arm64. | VERIFIED |

`DSH_HOME` defaults to `~/.dsh`. Also read by the launcher: `DSH_TELEMETRY_DISABLED`,
`DSH_LAUNCH_ENVIRONMENT_KEY` (VERIFIED, grepped from `dsh/lib/`), plus `DSH_TOOLS_MODE` and
`DSH_MAX_TOKENS_AS_SUCCESS` documented in the headless and SDK READMEs.

**The env block for the practical path today** (VERIFIED, from `quick_start/agent_integrations/claude_code`,
which is DeepSeek's own official Claude Code page):

```sh
export ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
export ANTHROPIC_AUTH_TOKEN=<your DeepSeek API Key>
export ANTHROPIC_MODEL=deepseek-flash[1m]
export ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-flash[1m]
export ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-flash[1m]
export ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-flash
export CLAUDE_CODE_SUBAGENT_MODEL=deepseek-flash
export CLAUDE_CODE_EFFORT_LEVEL=max
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=786432
```

Three things worth pulling out of that block. **`[1m]`** — the same 1M-context suffix the owner
already uses for `mimo-v2.5-pro[1m]`, so the pattern is familiar. **`CLAUDE_CODE_AUTO_COMPACT_WINDOW=786432`**
— 768K, i.e. 75% of 1M: a vendor-recommended compaction trigger, set by environment, which is a
partial answer to axis D **on the Claude Code path** that the `dsh` path cannot offer. And
**`CLAUDE_CODE_SUBAGENT_MODEL`** — a per-role model split that maps directly onto the orchestrator's
executor/reviewer roles.

Model mapping on the Anthropic endpoint (VERIFIED): `claude-opus*` → `deepseek-v4-pro`;
`claude-haiku*` / `claude-sonnet*` → `deepseek-flash`; **any unsupported model name silently maps to
`deepseek-flash`**. That last one is a trap — a typo'd model id does not error, it downgrades.
Anthropic-format compatibility is otherwise good but lossy: `anthropic-version` **ignored**,
`anthropic-beta` ignored for `/messages`, `mcp_servers` **ignored**, `container` ignored,
`service_tier` ignored, `top_k` ignored, `thinking.budget_tokens` ignored, `top_p` only applies in
thinking mode and is pinned to 1.0 otherwise.

**A Codex path also exists** (`quick_start/agent_integrations/codex`, VERIFIED): DeepSeek natively
supports the **Responses API**, and ships a one-click setup script
(`bash <(curl -fsSL https://cdn.deepseek.com/api-docs/codex-deepseek-setup-en.sh)`) that writes
`~/.codex/models.json` and edits `~/.codex/config.toml`, backing up to `~/.codex/backup-deepseek/`;
menu option 9 restores. **I did not run it** — it modifies the owner's `~/.codex`. Its declared
`models.json` entry for `deepseek-flash` sets `"context_window": 1048576`,
`"effective_context_window_percent": 95`, `"auto_compact_token_limit": null`, and
`"supported_reasoning_levels"` of `low` / `high` / `max`, with `"minimal_client_version": "0.144.0"`
— the local `codex` is 0.152.0, so it qualifies.

### J.3 Maturity — the honest assessment

**The API is mature. The harness is five weeks old.**

- `@deepseek-ai/dsh` has **never had a stable release**. Every one of its 22 published versions is
  `-rc.N` or `-alpha.N` (VERIFIED, npm). `latest` points at a **release candidate**.
- The README says, in bold: *"DeepSeek Harness is in developer preview and iterating rapidly.
  **THERE WILL BE COMPATIBILITY-BREAKING CHANGES.**"* (VERIFIED)
- `SAFETY.md`: not security-audited, not production-ready (§H).
- Release cadence is roughly **every 2–3 days** (22 versions in 38 days, VERIFIED from npm `time`).
- Counter-evidence for the maturity worry: the engineering *discipline* on display is high — a
  formal session-format version policy with migration packages and an explicit rule that prereleases
  create compatibility obligations; an fsync'd crash-recovery contract; documented invariant
  ownership per package; bilingual docs checked by a doc-standard test; a "keyless control-surface
  conformance test [that] drives the real profile through the public ACP SDK". This does not read
  like a rushed 0.1.x. It reads like a carefully built system that has not finished moving.

### J.4 Known unattended-run failure modes

Collected from the docs and source read during this pass:

1. **Zstd transcripts are unreadable to a file-tailing supervisor** unless `compression: 'none'` was
   set before the run (§C.2). Silent — you just see binary.
2. **`usage_update` is emitted only if `tokenMeter` is mounted and the provider reported usage and a
   `contextWindow` is known** (§D.1). A blind supervisor looks identical to a session with plenty of
   room. Assert you are receiving them.
3. **`ask_user_question` with no mounted answerer returns a tool error** and may derail a turn
   (§G.3). Don't mount the tool unattended.
4. **Permission prompts over ACP are one-shot only** — a restrictive preset plus an inattentive
   answerer stalls forever, and there is no way to say "always" (§G.2).
5. **`retryPolicy: always` retries indefinitely and bills every attempt** (§B.3). Against a 402 or a
   sustained outage this quietly drains balance overnight.
6. **402 Insufficient Balance is a hard stop with no reset** (§E.3). Unlike a window exhaustion, no
   amount of waiting fixes it. A supervisor that treats every limit error as "pause and retry later"
   will loop until morning.
7. **10-minute pre-inference connection close** (§E.4): a request that never gets scheduled is
   dropped by the server. Distinguish this from a hung session.
8. **Configuration changes require a process restart** — `patchReload: startup` (§F.3). No live
   retune of thresholds, models by profile, or credentials.
9. **`session/resume` fails if the cwd does not match by physical-directory identity** (§B.2). A
   worktree, a symlink, or a moved checkout breaks resume.
10. **Unsupported model names silently map to `deepseek-flash`** on the Anthropic endpoint (§J.2).
    A typo becomes a silent downgrade, not an error.
11. **`dsh` credentials are readable by the agent's own tool processes** (§H). Per-role `DSH_HOME`
    is the mitigation.
12. **`dsh` breaking changes land every 2–3 days** (§J.3). Pin the version; do not track `latest`.

### J.5 Can it run overnight unattended today?

**As a provider behind Claude Code (thing 3): yes, today, with no new engineering.** The owner's
existing harness, launcher, transcript reader and permission handling all keep working; only three
environment variables change. The quota model gets *simpler* (balance instead of windows).
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` gives an external compaction lever Claude-on-Anthropic does not
advertise. This is the highest value-per-hour move on the whole DeepSeek surface, and it is a
configuration change, not a feature.

**As `dsh` (thing 2): technically yes, prudently not yet.** The mechanism is there and is in places
better than anything else in the field — client-named sessions, pushed `usage_update`,
in-protocol permission answering, an fsync'd crash contract, an ACP surface that DeepSeek's own
subagent runtime uses. But `latest` is a release candidate from a five-week-old repo that promises
breaking changes and has not been security-audited, and the two gaps that remain (no external
compaction trigger, no clarifying-question channel) are exactly two of the owner's non-negotiables.

The defensible position: **adopt the API now as a cost lane; adopt the ACP protocol shape now as a
design target; adopt `dsh` itself as an executor when it reaches a stable minor.**

---

## What this costs the orchestrator

### What DeepSeek gives for free

- **A second, simpler quota model.** No windows to wait on. `GET /user/balance` → `is_available` +
  a number. A DeepSeek lane never sits idle waiting for a reset, which makes it the natural overflow
  target when the Claude lane is window-blocked.
- **The cleanest account switching in the scan.** One environment variable per role
  (`ANTHROPIC_AUTH_TOKEN`, or `DSH_HOME` for the whole harness). No keychain, no derived service
  names, no GUI dialog that can block an unattended run.
- **Order-of-magnitude cheaper tokens**, with a 50:1 cache-hit ratio that agent loops are shaped to
  exploit, and per-request `prompt_cache_hit_tokens` telemetry to verify it.
- **Zero-cost adoption of the API path** — the existing Claude Code adapter, three env vars.
- **A reference design for axes B, D and G**, whether or not `dsh` is ever used: client-named session
  ids, a pushed `usage_update { used, size }`, and `session/request_permission` answered in-protocol.

### What it costs to add

| Work | Why | Size |
|---|---|---|
| **A second quota abstraction** | `{utilization, resets_at}` cannot express `{is_available, total_balance}`. The supervisor needs a `Capacity` type with a window variant and a credit variant, and a policy per variant (pause-and-wait vs top-up-or-switch-account). | Small, but it touches the core loop and every provider added after this one — Kimi, GLM, MiniMax, Xiaomi will all be credit-style. Do it once, now. |
| **402 ≠ 429 handling** | Treating "out of money" as "rate limited" loops until morning. 402 must escalate to account switch or stop; 429 must reduce concurrency. | Small, high value. |
| **Concurrency accounting** | The only rate limit is 2500/500 in-flight **per account**, not per key. A supervisor running several sessions on one key must count its own. | Small. |
| **Prompt-prefix stability discipline** | Volatile supervisor-injected text at the front of a prompt destroys the KV cache and re-pays 50× on every subsequent step. | Small change, large money. |
| **Peak/off-peak scheduling** | 01:00–04:00 and 06:00–10:00 UTC Mon–Fri cost double. Ukraine overnight runs overlap the first peak block. | Optional; pure savings. |
| **An ACP client** (if adopting `dsh`) | `initialize`, `session/new`, `session/list`, `session/resume`, `session/prompt`, `session/cancel`, `session/close`, `session/set_config_option`, plus handling `session/update` and answering `session/request_permission`. Standard protocol with existing SDKs. | Medium. Reusable: ACP is a **standard**, so the same client may drive other agents later — this is the least platform-specific work on the list. |
| **A `dsh` profile composition** (if adopting `dsh`) | Setting `compression: 'none'`, a `thresholdRatio`, a permission preset, a session root, and *not* mounting `dsh-tool-ask-user`. Verifiable before launch with `--dump-config`. | Small, but must be got right **before** the first unattended run — several defaults are wrong for supervision. |
| **A compaction workaround** (if adopting `dsh`) | Neither protocol can trigger `/compact`. Either tune the threshold at composition time, or close-and-reseed on occupancy. | Medium. The close-and-reseed design is engine-agnostic and worth building regardless of platform. |
| **A clarifying-question policy** (if adopting `dsh`) | No elicitation channel. Unattended roles must not be able to ask. | Small — it is a decision, not code. |
| **Version pinning and a re-verification cadence** | `latest` is an RC, breaking changes are promised, releases land every 2–3 days. | Ongoing. Pin an exact version; re-read this profile before every upgrade. |

### The one-line recommendation

Take the **API** today as a cheap, window-free executor lane behind the existing Claude Code adapter.
Take the **ACP protocol shape** as the design target for the orchestrator's session interface —
it already answers three of the five non-negotiables and it is a standard, not a vendor API. Leave
**`dsh` itself** on the watchlist until it ships a stable minor, then re-run this pass.

---

## Sources

All read or run on **2026-09-19**.

**Official documentation (`api-docs.deepseek.com`), fetched today:**
- `/quick_start/pricing` — models, context, max output, peak/off-peak pricing, concurrency, deduction rules
- `/quick_start/rate_limit` — concurrency limits, `user_id` isolation, keep-alive, 10-minute close
- `/quick_start/error_codes` — 400/401/402/422/429/500/503
- `/quick_start/token_usage` — tokenization ratios, offline tokenizer
- `/api/get-user-balance` — `GET /user/balance` response schema
- `/api/deepseek-api` (first API call) — base URLs, model names, agent-tool pointer
- `/guides/kv_cache` — context caching, persistence rules, `prompt_cache_hit_tokens`
- `/guides/anthropic_api` — Anthropic-format compatibility matrix, model mapping
- `/guides/coding_agents` — Claude Code / OpenCode / OpenClaw integration
- `/quick_start/agent_integrations/claude_code` — the env block, `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, web search, model mapping
- `/quick_start/agent_integrations/codex` — Responses API, setup script, `models.json` contents
- `/quick_start/agent_integrations/opencode` — `/connect` flow, version floor
- `/news/news260910` (2026-09-10) — V4.1-Flash release; **V4-Pro phase-out and 2026-09-14 rerouting**
- `/news/news260813` (2026-08-13) — V4-Pro GA; peak/off-peak pricing introduced 2026-08-16 16:00 UTC
- `/news/news260821` (2026-08-21) — V4-Flash-Vision-Exp; Files API; "DeepSeek Harness 0.1.1"
- `/sitemap.xml` — used to establish that `get-user-balance` is the **only** usage endpoint

**Package registry and repository, queried today:**
- npm `@deepseek-ai/dsh` — dist-tags, all 22 versions with publish timestamps, `bin`, license, maintainers
- npm search `deepseek` — the `@deepseek-ai/dsh-*` package family
- GitHub API `repos/deepseek-ai/deepseek-harness` — stars, forks, license, created/pushed dates, releases
- GitHub API repo contents — `README.md`, `SAFETY.md`, `docs/api-gateway.md`, `docs/agent-lifecycle.md`, `docs/session-format-status.md`, `docs/capability-seams.md`, `docs/` listing

**Shipped source and docs, installed to an isolated sandbox and read here** (`@deepseek-ai/dsh@0.1.5-rc.2`):
- `@deepseek-ai/dsh-acp/lib/index.js` — `newSession` `randomUUID()`, `resumeSession` fences, `listSessions`, `requestPermission` options, `usageUpdate`, `cancel`, `initialize` capabilities
- `@deepseek-ai/dsh-acp/README.md` — full ACP method matrix, unsupported-surface list, limitations
- `@deepseek-ai/dsh-acp-app/README.md` — profile composition, stdio ownership, shutdown
- `@deepseek-ai/dsh-sdk-jsonrpc-server/lib/index.js` — dispatch `case` labels, `prompt()`, notification wiring, `initialize()`
- `@deepseek-ai/dsh-sdk-jsonrpc-server/README.md`, `@deepseek-ai/dsh-sdk-app/README.md`
- `@deepseek-ai/dsh-headless/README.md` — output contract, exit mapping
- `@deepseek-ai/dsh-session-persistence-jsonl/README.md` — on-disk layout, compression, crash semantics
- `@deepseek-ai/dsh-token-meter/README.md` — `measure()`, projections, `contextPressure`
- `@deepseek-ai/dsh-compaction-basic/README.md` — triggers, `thresholdRatio`/`retainRatio`, model policies
- `@deepseek-ai/dsh-command-compact/README.md` — `/compact` behavior and failure messages
- `@deepseek-ai/dsh-credentials-local/README.md`, `@deepseek-ai/dsh-home-paths/README.md` — `$DSH_HOME`, precedence
- `@deepseek-ai/dsh-llm-deepseek/lib/index.js` — `429` / `RATE_LIMIT` / `retry-after` handling
- READMEs of `dsh-permission-presets`, `dsh-user-approval`, `dsh-sandbox-policy`, `dsh-sandbox-local`, `dsh-hooks-claude-code`, `dsh-hooks-codex`, `dsh-mcp-client`, `dsh-skill`, `dsh-tool-subagent`, `dsh-workflow`, `dsh-jobs`, `dsh-schedule`, `dsh-webhook`, `dsh-user-questions`, `dsh-tool-ask-user`, `dsh-session-stats`, `dsh-tool-ralph`, `dsh-llm-retry`

**Run on this machine (read-only, no quota spent, no owner config touched):**
- `dsh --version` → `0.1.5-rc.2`; `dsh --help`
- `dsh --profile headless --help`, `--profile acp --help`, `--profile sdk --help`, `dsh web --help`
- `dsh --profile tui --help` → confirmed `tui` does not exist
- `$DSH_HOME` materialization check
- PATH / config / environment sweep confirming **no DeepSeek install or credential exists here**

**Not run, deliberately:** the Codex setup script (modifies `~/.codex`), any agent task, any billed
API request.
