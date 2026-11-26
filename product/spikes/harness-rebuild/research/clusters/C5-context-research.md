# C5 — Context-window management and compaction

**Cluster:** C5-context · **Item:** R1-08 · **Written:** 2026-09-19
**Machine checked:** darwin 25.5.0 · Claude Code `2.1.278` · Codex CLI `0.152.0` (rollouts from `0.154.0-alpha.6.2`) · Gemini CLI **not installed** · opencode **not installed**

Evidence labels used throughout: **VERIFIED** = I read it in source, a binary's own strings, a schema the tool generated, or a file on this machine. **CLAIMED** = a vendor doc, README, blog or third-party write-up says so and I did not execute it. **INFERRED** = my reasoning from two or more of the above.

---

## 1. What the owner decided, quoted

The whole of R1-08 rests on one long answer at `[204]`, which the meta-reader records as the single richest answer in the transcript (he opened it with «Це дуже хороше питання»).

> «Людина може налаштувати, при скількох відсотках відбувається компакт, який буде робити оркестратор. …
> І якщо, наприклад, оркестратор наблизився до того числа, ну або, чи перейшов це число, то **повинен бути
> механізм, який гарантовано робить цю дію**, і відпрацьовує так, що сесія компактиться» — `[204]`

In English, the rest of the answer: the threshold, soft (compact once the current step ends) vs hard (stop, compact, continue), compact vs a fresh orchestrator, the compact command (official or a custom skill) and an optional post-compact prompt are all user-configured, per session role and per provider.

Soft mode, clarified:

> «Лише поточного кроку, але це можна налаштовувати, людина може сама налаштувати, що це означає» — `[209]`, ratified by «Так, правильно» `[212]`

**The nine requirements, as he stated them**

| # | Requirement | Source | Ratified? |
|---|---|---|---|
| R1-08.1 | The user sets the **percentage** at which a compact happens | `[204]` | via `[212]` for the soft-mode part only |
| R1-08.2 | **The orchestrator performs it** («компакт, який буде робити оркестратор») | `[204]` | — |
| R1-08.3 | **Soft** = compact when the current step finishes; **hard** = stop now, compact, continue | `[204]`, `[209]` | `[212]` for soft |
| R1-08.4 | Works **for all sessions**, and may be configured **per provider** or per session | `[204]` | restatement `[213]` **never ratified** |
| R1-08.5 | **Per-window thresholds** — his example is three Claude Code windows: context watcher, orchestrator, executor, each with its own threshold and its own method | `[204]` | — |
| R1-08.6 | The compact **method** is configurable: the platform's own command, or a custom skill | `[204]` | — |
| R1-08.7 | Optionally **a prompt is sent right after** the compact | `[204]` | restatement `[220]` **never ratified** |
| R1-08.8 | For the orchestrator: **compact OR start a wholly new orchestrator**, user's choice | `[204]` | restatement `[220]` **never ratified** |
| R1-08.9 | **«повинен бути механізм, який гарантовано робить цю дію»** — the configured action must be guaranteed to execute when the threshold trips | `[204]` | restatement `[220]` **never ratified** |

**Fidelity caveat, from `research/extract/corrections.md` lines 89–90 — raise this with him before building.**
Two of the four R1-08 restatements were never confirmed. At `[213]`/`[214]` (thresholds, scope, hard mode) he said «Повтори ще раз»; the interviewer repeated at `[217]` and then at `[218]` declared *«Підтвердив, зафіксував. Що далі?»* — **he said nothing in between**. At `[220]`/`[221]` (compact-or-new-session, command choice, guaranteed mechanism) he said «Яке наступне питання? Чи повтори будь ласка», it repeated at `[224]` and moved on to R1-09. The *words* at `[204]` are his and are safe to quote; the *formulations* in rows 213/220 — including the exact phrasing of the guaranteed-execution requirement — are the interviewer's and are unratified. Everything below is built on `[204]` and `[209]`/`[212]`.

**The role taxonomy he keeps restating and the analysis never records.** «контекст вочер / оркестратор / екзек'ютор» appears at `[036]`, `[195]` and again at `[204]`, the last time as three concrete terminal windows. C5 is the cluster where it becomes load-bearing: thresholds, methods and soft/hard attach *per window*, and `[195]` leaves open whether the orchestrator or the context watcher owns the polling. **That ownership question is open and it collides with the single-orchestrator invariant at `[300]`** — see §6.

---

## 2. How the world does it

### 2.1 Claude Code 2.1.278 — read path

**VERIFIED.** The `statusLine` command is a shell command the session runs itself, and it is handed the live context window on stdin. Extracted from the binary's own status-line payload builder (`function b0r({session,...})` in `~/.local/share/claude/versions/2.1.278`):

```
context_window: XUe(He, We),          // the object below
exceeds_200k_tokens: r,
rate_limits: { five_hour: {used_percentage, resets_at}, seven_day: {...}, spend_limit: {...} },
cost: { total_cost_usd, total_duration_ms, total_api_duration_ms, total_lines_added, total_lines_removed },
model: {id, display_name}, workspace: {...}, session_id, transcript_path, cwd, version, ...
```

and `XUe`:

```js
function XUe(e, n) {
  return {
    total_input_tokens:  e ? e.input_tokens + e.cache_creation_input_tokens + e.cache_read_input_tokens : 0,
    total_output_tokens: e?.output_tokens ?? 0,
    context_window_size: n,
    current_usage:       e,
    used_percentage:     r.used,
    remaining_percentage:r.remaining
  }
}
```

Confirmed against the published docs (`code.claude.com/docs/en/statusline`), which additionally state (**CLAIMED**, doc text): `context_window_size` is "200000 by default, or 1000000 for models with extended context"; `current_usage` is **`null` before the first API call and again after `/compact` until the next API call repopulates it**; `used_percentage` / `remaining_percentage` "may be `null` early in the session".

**When it runs** (**CLAIMED**, doc): once at session start including on resume, then on every new assistant message, when `/compact` **finishes**, on permission-mode change, on vim toggle, when the `command` setting changes, on a `refreshInterval` timer, and when a rate-limit window or a warm prompt-cache reaches its reset/expiry. Updates are debounced 300 ms; a new trigger **cancels an in-flight script**. `statusLine.refreshInterval` is a settings key (minimum 1 second) — **VERIFIED** in the binary's settings schema: `refreshInterval: A().min(1).optional()...describe("Re-run the status line command every N seconds in addition to event-driven updates")`.

**This is already running in production on this machine.** `~/.claude/settings.json` sets `statusLine.command = bash ~/.claude/statusline-command.sh`, and that script reads `.context_window.used_percentage`, `.context_window.total_input_tokens` and `.context_window.total_output_tokens`. A second, richer implementation ships with GSD at `~/.claude/hooks/gsd-statusline.js` — see §2.3.

**Second read path, needing no configuration at all: the transcript.** **VERIFIED** on this session's own jsonl (`~/.claude/projects/<slug>/<session-id>.jsonl`): every `type:"assistant"` row carries `message.usage` with `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`. Summing the first three of the **last** assistant row and dividing by the model's window reproduces `used_percentage` exactly — the binary computes it the same way (`IKt`: `e.input_tokens + e.cache_creation_input_tokens + e.cache_read_input_tokens`). Measured on this session: 397 577 + 3 681 + 2 = 401 260 of 1 000 000 → 40 %. The transcript also carries `type:"cost-state"` rows with cumulative per-model token and dollar totals.

**Third read path: OpenTelemetry.** **VERIFIED** — the binary emits metric/span names including `claude_code.token.usage`, `claude_code.compaction`, `claude_code.session.count`, `claude_code.llm_request`, gated by `CLAUDE_CODE_ENABLE_TELEMETRY`.

**What is *not* a read path: the screen.** The previous generation scraped `ctx=NN%` off the status line (`FIELD-NOTES.md` §3.3: "The context percentage is nevertheless available with no new machinery: it is printed on every session's own status line, and the watch loop already captures every screen each cycle"). Two problems, both **VERIFIED**:

1. **The screen number is not the same number.** `gsd-statusline.js:788-802` normalises against the auto-compact reserve before drawing the bar — `usableRemaining = ((remaining - AUTO_COMPACT_BUFFER_PCT) / (100 - AUTO_COMPACT_BUFFER_PCT)) * 100`, with `AUTO_COMPACT_BUFFER_PCT` defaulting to **16.5** and recomputed from `CLAUDE_CODE_AUTO_COMPACT_WINDOW` when set. Its own comment on the bridge file it writes (line 812) says the raw value "must match CC's native `/context` reporting: raw used = 100 - remaining_percentage (no buffer normalization applied). The normalized `used` value is correct for the statusline progress bar but **inflates the context monitor warning messages by ~13 points**". **A threshold tuned against a screen-scraped percentage is roughly 13 points tighter than the same number applied to the raw reading.** Whatever this rebuild does, `percent` must be defined once, in writing, as raw or normalised.
2. **Configuring a status line removes the busy signal the old watcher depended on.** The doc states (**CLAIMED**): "With a custom status line configured, Claude Code stops showing most of the footer's keyboard hints, **including `esc to interrupt`**". `WATCHER-PROMPT.md` line 126 gates the whole compaction procedure on exactly that string: "Only when the capture shows the orchestrator idle — no `esc to interrupt` on screen." Adopting the status-line read path **breaks** the screen-based idle check unless the busy signal moves to `claude agents --json` (§2.2).

### 2.2 Claude Code 2.1.278 — session registry and busy/idle, without a TTY

**VERIFIED by execution on this machine.** `claude agents --json` "Print active sessions (interactive and background) as a JSON array and exit (for scripting; **does not require a TTY**)". Real output:

```json
{"pid":35475,"cwd":"/Users/.../MNB","kind":"interactive","startedAt":1789743993512,
 "sessionId":"e4ea9e27-...","name":"mnb-60","status":"busy"}
{"pid":64503,"id":"a3ab5301","kind":"background","sessionId":"a3ab5301-...",
 "name":"ctxprobe","status":"idle","state":"done"}
```

`sessionId` is the key that joins to the transcript path and to the status-line payload. `status` is `busy`/`idle` and `state` on background sessions adds `blocked`/`done`. This replaces three of the previous generation's forgeable heuristics at once — the `esc to interrupt` string, the shell count (`FIELD-NOTES.md` §2.2: "A shell that cannot exit reads as work"), and heartbeat staleness (§1.5: "Heartbeat staleness is not a stall").

**Also VERIFIED by execution:** an in-process `ListAgents` lists *interactive* peer sessions with live `busy`/`idle`/`waiting`, and `SendMessage({to, message})` delivers text to a peer session with no tty typing at all — "messages enqueue and drain at the receiver's next tool round". `SendMessage` also offers `notify_when_idle: true`, a **one-shot subscription that fires exactly one notice when that session next goes idle or exits**. That is precisely the "wait for a safe boundary" primitive soft mode needs, and it is push, not poll.

**Two hard limits I measured rather than assumed:**
- I started a background session (`claude --bg -n ctxprobe`), confirmed it ran and answered, then tried `SendMessage({to:"ctxprobe"})` → `{"success":false,"message":"No agent named 'ctxprobe' is reachable."}`, and it did not appear in `ListAgents`. **Background sessions are not reachable over the peer-message channel; only interactive ones are.**
- `SendMessage` delivers *text to the model*. **A model cannot type a slash command onto its own input line.** `FIELD-NOTES.md` §1.1 states this as the governing constraint — "A model has no way to put text on its own input line" — and nothing in 2.1.278 changes it. So `SendMessage` is a first-class channel for *instructions* (including "write your handoff now"), and **not** a channel for `/compact`.

### 2.3 Claude Code — the write/trigger path, and its four hooks

**VERIFIED** from the binary's own hook table and Zod schemas:

```
| PreCompact  | "manual"/"auto" | Before compaction |
| PostCompact | "manual"/"auto" | After compaction (receives summary) |
| SessionStart| -               | When session starts |
```
```js
{hook_event_name:"PreCompact",  trigger: "manual"|"auto", custom_instructions: string|null}
{hook_event_name:"PostCompact", trigger: "manual"|"auto",
 compact_summary: "The conversation summary produced by compaction"}
{hook_event_name:"SessionStart", source: "startup"|"resume"|"clear"|"compact"|"fork",
 seconds_since_last_response: number?}
```

Plus, **VERIFIED** in the binary: `Compaction blocked by PreCompact hook` / `compaction blocked by PreCompact hook; continuing uncompacted` — **PreCompact can veto a compaction** (exit 2, per the published hooks doc — **CLAIMED**). And hooks may return `additionalContext` — "Text injected into model context" / "Context injected back to model".

Put together, these four facts give a **deterministic, keystroke-free spine** for everything except the trigger itself:

- **PreCompact** = the guaranteed place to refresh the handoff file, for *both* manual and automatic compactions. This replaces `WATCHER-PROMPT.md` steps 1–2 ("send 'update ORCH-HANDOFF.md'" then "wait for the mtime to move"), which the field notes show can silently never submit.
- **PostCompact** = proof the compaction *completed*, with the summary in hand to write to disk.
- **SessionStart, `source == "compact"`** = the guaranteed place to re-inject the handoff after a compact. This replaces `WATCHER-PROMPT.md` step 5 ("send 'read ORCH-HANDOFF.md and continue'"), the second keystroke that can be stranded.
- **PreCompact veto** = hard mode's interlock: a PreCompact hook can refuse a compaction while the session is in a state where compacting would destroy something (see the mutation case in §5.4).

**Prior art already on this machine, and it is good.** GSD ships exactly this shape. `gsd-statusline.js:804-827` writes a **bridge file** `$TMPDIR/claude-ctx-{session_id}.json` on every render: `{session_id, remaining_percentage, used_pct, timestamp}`. `gsd-context-monitor.js` is a PostToolUse hook that reads it and injects a warning as `additionalContext` at 35 % remaining (warning) and 25 % (critical), thresholds overridable per project via `.planning/config.json` → `hooks.context_warning_threshold` / `hooks.context_critical_threshold`, with a 5-tool-use debounce and severity escalation bypassing it. Its file header states the reason plainly: *"the statusline only shows the user"* — the agent is otherwise blind to its own context.

The same file solves the single nastiest verification bug in this whole area, and it is worth copying verbatim rather than rediscovering. It also registers on **PreCompact**, where it writes a **watermark** `claude-ctx-{id}-compacted.json` holding the compaction's start time, and the reader then **drops any reading not strictly newer than the watermark plus a 60-second grace window**. Its comment says why:

> "the statusline re-writes the bridge on every render, and **a render during the compaction stamps the OLD `remaining_percentage` with a current time**. The watermark records the compaction's START, so 'newer than the watermark' alone still admits a mid-compaction render: the grace window covers the compaction's own duration."

**That is the general failure mode of every "wait for the percentage to drop" verification**, including `WATCHER-PROMPT.md` step 4 and `J-WATCH-01`. A reading taken during a compaction is the pre-compaction number wearing a fresh timestamp.

### 2.4 Claude Code — auto-compaction, and the two ways it dead-ends

**VERIFIED** from the binary. Controls: the `autoCompactEnabled` setting; the `--autocompact <auto|tokens>` CLI flag ("Auto-compact window size (auto, or 100k–1M tokens)"), which is the `autoCompactWindow` setting; the env vars `DISABLE_AUTO_COMPACT` and `DISABLE_COMPACT`, the latter documented in the binary as *"DISABLE_COMPACT also disables manual `/compact`"*; and `CLAUDE_CODE_MAX_CONTEXT_TOKENS`. There is also a `microcompact_boundary` transcript record and a `tengu_time_based_microcompact` event, i.e. a second, lighter compaction path distinct from the full one — **INFERRED** that it trims tool results rather than summarising the conversation; I did not confirm its scope.

The auto-compact entry point (`C9n`) returns, in order: `not_needed` if `DISABLE_COMPACT` is set; **`failure_breaker_open` if `consecutiveFailures >= N`**; `not_needed` if under threshold; then it checks the **prefix-overflow** case and the **thrash** case. Both are terminal for an unattended session:

1. **Prefix overflow.** `autocompact: fixed prefix ~${prefixTokens} > threshold ${thresholdTokens} — compaction cannot help`. When the un-summarisable prefix (system prompt, tool definitions, CLAUDE.md, skills) already exceeds the compaction threshold, **compacting cannot free anything**. This is the "late auto-compaction dead-end" named in the task, and it is a *configuration* failure as much as a runtime one: a session loaded with many MCP servers, plugins and memory files can be born past the point where compaction rescues it.
2. **Thrash breaker.** Verbatim: *"Autocompact is thrashing: the context refilled to the limit within 3 turns of the previous compact, 3 times in a row. A file being read or a tool output is likely too large for the context window. Try reading in smaller chunks, or use `/clear` to start fresh."* Three consecutive rapid refills → trip.
3. **Failure breaker.** N consecutive compaction failures → `failure_breaker_open`, i.e. auto-compact stops trying.

**All three are states in which "compact in place" is no longer a recovery, and only a fresh session is.** Nothing in the previous generation detects any of them. An unattended orchestrator that hits case 1 will sit at 95 %+ producing nothing, and the watcher's `/compact` will also do nothing, for as long as the run lasts.

### 2.5 Codex CLI — the best-instrumented platform of the four

**VERIFIED** from a real rollout on this machine (`~/.codex/sessions/2026/09/13/rollout-*.jsonl`). Every turn appends a `token_count` event and a `token_usage_record`:

```json
{"type":"token_count","info":{
  "total_token_usage":{"input_tokens":11262616,...,"total_tokens":11276984},
  "last_token_usage":{"input_tokens":123167,"cached_input_tokens":121984,
                      "output_tokens":87,"reasoning_output_tokens":0,"total_tokens":123254},
  "model_context_window":258400},
 "rate_limits":{"primary":{"used_percent":6.0,"window_minutes":10080,"resets_at":1790415035},...}}
```

`model_context_window` is **in the file**. Live occupancy is `last_token_usage.total_tokens / model_context_window` (here 123 254 / 258 400 ≈ 48 %); `total_token_usage` is cumulative across the thread and must **not** be used as occupancy — it reads 11.2 M against a 258 k window. Rate-limit position rides along in the same record, which is a bonus for the C4 limits cluster.

**Codex is the only platform of the four with a documented RPC to compact a running session.** `codex app-server generate-json-schema --out DIR` (I ran it) emits the protocol; it contains:

| Method / notification | Shape | Meaning |
|---|---|---|
| `thread/compact/start` | `ThreadCompactStartParams {threadId}` → `{}` | **trigger a compaction on a named thread** |
| `thread/compacted` | `{threadId, turnId}` | it happened (marked "Deprecated: use `ContextCompaction` item type") |
| `thread/tokenUsageUpdated` | `{threadId, turnId, tokenUsage:{last, total, modelContextWindow}}` | **push** of live occupancy |
| `turn/steer` | `TurnSteerParams` (text + `AdditionalContextEntry{kind:"untrusted"\|"application"}`) | inject into a **running** turn |
| `turn/interrupt` | `TurnInterruptParams` | stop the current turn — hard mode's "stop now" |

plus `ContextCompactionThreadItem` / `CompactionTriggerResponseItem` item types, and hook names `preCompact` / `postCompact` / `subAgentCompact` in the same schema.

Config keys, **VERIFIED** in the generated schema and the native binary's strings: `model_auto_compact_token_limit`, and `model_auto_compact_token_limit_scope` with the documented enum *"Selects which part of the active context is charged against `model_auto_compact_token_limit`"* — `total` ("Count the full active context against the limit") or `body_after_prefix` ("Count sampled output and later growth after the carried window prefix"). **That second scope is Codex's built-in answer to the prefix-overflow problem in §2.4.** Also `auto_compact_fallback_buffer_tokens` (default `16384`) and `auto_compact_fallback_prompt`.

**The socket.** `~/.codex/app-server-control/app-server-control.sock`, managed by `codex app-server daemon {start,restart,stop,version,enable-remote-control}`; `codex app-server proxy [--sock PATH]` "Proxy stdio bytes to the running app-server control socket". On this machine the daemon is not running (`codex app-server daemon version` → `failed to connect to …/app-server-control.sock`), so the RPC path is **VERIFIED as specified, not as executed**. Test it before designing on it.

**And a keystroke-free message channel that Claude Code lacks:** `codex queue --thread <UUID|name> --message <TEXT>` — "Queue a message for an existing session". **VERIFIED** from `--help`.

### 2.6 Gemini CLI — read from the source, not installed here

**VERIFIED** from `google-gemini/gemini-cli` `main` (repo pushed `2026-09-19T01:25:15Z`, 107 k stars):

- `packages/core/src/context/chatCompressionService.ts`: `const DEFAULT_COMPRESSION_TOKEN_THRESHOLD = 0.5;` — "Default threshold for compression token count as a fraction of the model's token limit". `COMPRESSION_PRESERVE_THRESHOLD = 0.3` — the last 30 % of history survives. `COMPRESSION_FUNCTION_RESPONSE_TOKEN_BUDGET = 50_000`.
- `ChatCompressionService.compress(chat, promptId, force, ...)` — a `force` flag distinguishes manual from automatic, and `const trigger = force ? PreCompressTrigger.Manual : PreCompressTrigger.Auto;` then `await config.getHookSystem()?.firePreCompressEvent(trigger)`. **The hook fires for both.**
- `packages/cli/src/config/settingsSchema.ts`: `model.compressionThreshold` — `type: 'number'`, `default: 0.5`, `requiresRestart: **true**`, *"The fraction of context usage at which to trigger context compression (e.g. 0.2, 0.3)"*. Separately `contextManagement.maxTokens` default `150_000` ("The number of tokens to allow before triggering compression") and `retainedTokens` default `40_000`.
- `packages/core/src/hooks/types.ts`: `HookEventName` = `BeforeTool, AfterTool, BeforeAgent, Notification, AfterAgent, SessionStart, SessionEnd, **PreCompress**, BeforeModel, AfterModel, BeforeToolSelection`. `PreCompressInput {trigger: "manual"|"auto"}`; **`PreCompressOutput {suppressOutput?, systemMessage?}` — no veto and no `additionalContext`.**
- Telemetry settings exist with `outfile` ("File path for writing telemetry output") and `useCollector`, and `logChatCompression` / `makeChatCompressionEvent` are in the telemetry path.

So Gemini CLI has: a configurable threshold (restart-only), a PreCompress hook that cannot block, an OTLP-to-file read path, `/compress` and `/stats` as interactive commands (**CLAIMED**, third-party write-ups) — and **no documented external trigger**.

### 2.7 opencode — the cleanest external API of the four

**CLAIMED** (fetched `opencode.ai/v2/docs/compaction`; not installed here, nothing executed):

- Config: `compaction.auto` (bool, default true), `compaction.keep.tokens` (default 15 000), `compaction.buffer` (default 20 000). V1 used `auto`/`prune`/`reserved`; V2 uses `auto`/`keep.tokens`/`buffer`.
- Trigger rule, quoted: `estimated tokens >= min(input limit - buffer, context limit - max(output reserve, buffer))`.
- **External trigger:** `POST http://localhost:4096/api/session/{id}/compact` with an optional `id` for idempotency.
- **And the caveat that matters most:** *"The response confirms admission; it does not wait for the summary."* Completion is observed via `session.compaction.*` events. It also warns that after native checkpoints, "automatic checks wait for fresh model usage because encrypted checkpoint bytes cannot provide a meaningful token count."

That last sentence is the whole design problem in one line: **admission is not execution, and execution is not a freed window.**

### 2.8 The generic case — a platform with none of the above

Three tiers, in descending order of trustworthiness:

1. **Parse the transcript** for whatever the provider recorded per response. Both Claude Code and Codex record exact server-reported usage, so this is exact where it exists.
2. **Ask the provider to count.** For Anthropic, `POST /v1/messages/count_tokens` is the supported endpoint, and `GET /v1/models/{id}` returns `max_input_tokens` (the window; there is no `context_window` field). Current first-party windows: Opus 5 / Sonnet 5 / Fable 5 / Opus 4.6–4.8 = **1M**; Haiku 4.5 = 200K. Anthropic also ships server-side **Compaction** as a beta (`compact-2026-01-12`, default trigger 150 K tokens) for SDK-hosted loops — the relevant lesson for us is that it too requires the caller to append the compaction blocks back, or the state is silently lost.
3. **Count locally with a tokenizer** — a last resort. Vendor guidance is explicit that `tiktoken` is the wrong tool for Claude. A local count is an estimate, it drifts with tokenizer changes, and it cannot see the system prompt, tool schemas or server-side injections. **Use it to rank sessions, never to trip a threshold.**

**Transcript file size is not a proxy for context.** It is monotonically increasing and survives compaction; a compacted session's file keeps growing while its window empties. It is a useful *liveness* signal (mtime) and a useless *occupancy* signal.

### 2.9 Capability matrix

| | Read % without being the session | Trigger compaction externally | Confirm it happened | Inject a prompt after |
|---|---|---|---|---|
| **Claude Code 2.1.278** | **Yes, 3 ways** — statusLine→file bridge (exact, event-driven), transcript `message.usage` (exact, no config), OTEL `claude_code.token.usage` | **No RPC.** Only: type `/compact` into a tty, or let auto-compact fire | **Yes** — PostCompact hook (+ `compact_summary`); `compact_boundary` in transcript; `current_usage` is `null` right after | **Yes, two ways** — SessionStart `source:"compact"` hook returning `additionalContext` (deterministic), or `SendMessage` to an interactive peer |
| **Codex CLI 0.152** | **Yes** — rollout `token_count` incl. `model_context_window`; `thread/tokenUsageUpdated` push | **Yes** — `thread/compact/start` over the app-server socket | **Yes** — `thread/compacted` / `ContextCompaction` item; next `token_count` | **Yes** — `codex queue --thread … --message …`, or `turn/steer` |
| **Gemini CLI** | **Partly** — OTLP telemetry to `outfile`; `/stats` is interactive only | **No documented external trigger** | PreCompress hook fires (manual+auto) but **cannot block**; no post-hook found | Hook output is `systemMessage` only — **no context injection** |
| **opencode** | **Partly** (CLAIMED) — server API + `session.compaction.*` events; no direct token endpoint documented | **Yes** — `POST /api/session/{id}/compact` | **Events only** — the POST confirms admission, not completion | Ordinary session message via the same server |

---

## 3. What is feasible, per platform

**Everything the owner asked for is feasible on Claude Code and Codex.** The gaps are Gemini CLI and opencode, and one specific verb on Claude Code.

| R1-08 requirement | Claude Code | Codex | Gemini CLI | opencode |
|---|---|---|---|---|
| .1 user-set percentage | **Yes** — our own threshold over an exact reading | **Yes** — ours, or `model_auto_compact_token_limit` | **Yes** for its own auto-compress (`model.compressionThreshold`); ours needs telemetry | **Yes** (`compaction.buffer`, indirectly) |
| .2 orchestrator performs it | **Yes** — on someone else's session, only by typing into its tty | **Yes** — RPC, no tty | **No** — no external trigger | **Yes** — HTTP |
| .3 soft (next step) / hard (now) | **Soft: yes**, via `notify_when_idle` or `agents --json status` transition. **Hard: partial** — no external interrupt; Escape into the tty is the only stop | **Both yes** — `turn/interrupt` then `thread/compact/start` | **No** | **Soft yes; hard** depends on an interrupt I did not verify |
| .4 all / per-provider / per-session | **Yes** — config is ours | **Yes** | **Yes** for its own knob | **Yes** |
| .5 per-window (watcher/orchestrator/executor) | **Yes** — `sessionId` from `agents --json` is the key | **Yes** — `threadId` | partial | **Yes** — session id |
| .6 configurable method (native cmd or custom skill) | **Yes** — native `/compact`, or any custom skill typed the same way; **`DISABLE_COMPACT` disables both** | **Yes** — RPC, `/compact`, or a skill | native `/compress` only | HTTP or native |
| .7 prompt right after | **Yes** — SessionStart(`compact`) hook, deterministic | **Yes** — `codex queue` | **No** | **Yes** |
| .8 compact **or** fresh orchestrator | **Yes**, and the fresh path is materially easier than in 2026-09: `claude --bg` / `attach` / `logs` / `stop` / `respawn` / `agents --json` are first-class | **Yes** — `codex resume`, `codex fork` | **Yes** (process restart) | **Yes** |
| .9 guaranteed execution | **Achievable, not free** — see §5 | **Achievable** — closest to free | **Not achievable externally** | **Achievable** |

**The one verb Claude Code does not have is "compact this other session".** Everything else — read, wait for a boundary, refresh the handoff, confirm, re-brief, restart — is available without touching a keyboard. This is worth stating precisely because it is *narrower* than what the field notes imply: the field notes' three failed `/compact` attempts and five stranded instructions were all about typed text in general, and four of those five categories no longer need typed text at all.

---

## 4. What is NOT feasible, and why

1. **A model cannot compact itself.** Not on any of the four. `/compact` is an input-line command; a model has no way to put text on its own input line (`FIELD-NOTES.md` §1.1). Every "the session manages its own context" design reduces to either auto-compaction or the session *ending its turn* and something else acting.

2. **On Claude Code, a supervising process cannot trigger `/compact` without a tty.** There is no CLI subcommand, no RPC, no socket. `SendMessage` reaches an interactive peer but delivers text to the model, which cannot execute it. `claude --bg` sessions are not even reachable that way (measured). So the trigger keeps the tty dependency and its measured failure modes:
   - `/compact` **lands only when the target has no shell running** — three attempts on one session, one day: empty line + no shells → 73 % → 0 % in ~90 s; empty line + shells running → nothing, twice, and the second drifted 91 % → 95 % and auto-compacted (`FIELD-NOTES.md` §1.2).
   - A bare Enter does not submit stranded text; `send` types its own text **and destroys whatever was pending**; a background task re-invoking the session **discards** an idle input line (§1.3). Five instructions were never delivered in one run.
   - `Terminal.app` refuses `send` and `key` outright (`harness-term.sh:163-181`) — the trigger only exists on iTerm2/tmux.

3. **Gemini CLI cannot be compacted from outside at all.** No RPC, no server, no queue command. Its PreCompress hook fires but returns only `{suppressOutput?, systemMessage?}` — it cannot block and it cannot inject context. The only external levers are: set `model.compressionThreshold` before launch (**`requiresRestart: true`** — it cannot be re-tuned mid-run), read telemetry, and restart the process with a written position. **For Gemini CLI, R1-08's answer is forced to be (B) fresh session.** This is the divergence instruction **I1 `[182–184]`** asks to be raised as its own question.

4. **"Guaranteed" cannot mean "the keystroke always lands."** On every platform, the trigger can be admitted and still not execute: opencode says so outright ("the response confirms admission; it does not wait for the summary"); Claude Code's PreCompact hook can veto, and its auto-compact can return `failure_breaker_open` or `compaction cannot help`. The only honest reading of R1-08.9 is **guaranteed as a closed loop: detect → act → verify → escalate**, with a terminal fallback that does not depend on the same mechanism that just failed. §5 builds that.

5. **You cannot verify a compaction by watching the percentage alone.** A status-line render landing *during* a compaction republishes the pre-compaction number with a current timestamp — this is documented in `gsd-context-monitor.js` as the reason the watermark exists, and it is exactly what `WATCHER-PROMPT.md` step 4 and `J-WATCH-01` do.

6. **Nothing in the previous generation measures context at all.** `FIELD-NOTES.md` §3.3: `bin/*.sh` has no reference to context, percentages or compaction; a grep for `compact|ctx=|auto-compact` returns nothing, and the two limit keys (`limits.pause_next_spawn_at`, `limits.weekly_pause_at`) are **token-quota** thresholds, not context thresholds. C5 is being built from zero, not repaired.

---

## 5. Concrete proposals

### 5.1 Read: one adapter interface, four implementations, never the screen

```
context_probe(session) -> { percent_raw, tokens_used, window, at, source, stale }
```

- **Claude Code — primary:** our own `statusLine` command, which writes `{session_id, used_percentage, remaining_percentage, total_input_tokens, context_window_size, at}` to `$RUNDIR/state/ctx/<session-id>.json` and then `exec`s whatever status line the user already had. Event-driven, exact, and the payload already contains `rate_limits` for C4. Set `statusLine.refreshInterval: 30` so an idle coordinator still reports (the doc names this case explicitly). **Cost: it suppresses the footer hints including `esc to interrupt`** — accept it and take busy/idle from `claude agents --json` instead, which is better anyway.
- **Claude Code — fallback, zero configuration:** tail the transcript jsonl, take the last `type:"assistant"` row, sum `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`. Use this when the user declines to let us touch their status line, and as the cross-check that catches a stale bridge.
- **Codex:** tail the rollout jsonl for the last `token_count`; `last_token_usage.total_tokens / model_context_window`. If the daemon is running, subscribe to `thread/tokenUsageUpdated` instead and stop polling.
- **Gemini CLI:** `telemetry.target=file` + `telemetry.outfile`, parse token metrics.
- **Generic:** transcript parse → provider count endpoint → local tokenizer, in that order, and a session whose figure came from a local tokenizer is **flagged in the config output as approximate** so the owner knows which of his thresholds are soft.

**Two rules the adapter enforces for everyone.**
- **`percent` is raw.** Defined once: `percent_raw = 100 - remaining_percentage`, matching `/context`. If the UI wants the normalised bar it computes it separately. A migrated threshold from the old screen-scraped numbers must be **lowered by ~13 points** or restated.
- **Every reading carries `at`, and any reading inside `[compaction_started, compaction_started + grace]` is discarded, not queued.** Copy `gsd-context-monitor.js`'s watermark, including the "not strictly newer ⇒ drop" test and the sanity check on a future-dated watermark.

### 5.2 Trigger: a ladder, per platform, with the cheapest rung first

```
rung 0  make it unnecessary   auto-compact configured to fire just past our threshold
rung 1  native RPC            Codex thread/compact/start · opencode POST /compact
rung 2  peer message          Claude Code SendMessage → "wrap up and end your turn"  (soft boundary)
rung 3  tty keystroke         harness-term send <tty> "/compact"   (Claude Code only, preconditions below)
rung 4  fresh session         write position → start new session → point it at the position
```

Rung 3 fires **only** when all preconditions hold, each checked, never assumed: `agents --json` says `idle`; zero child shells (`ps -axo pid,ppid,command | awk '$2==<pid>'` — §1.2's discriminator, and §2.2's "shell that cannot exit" is why it is counted from `ps` and not read off the screen); the input line is empty (because `send` destroys pending text); and the handoff's mtime has moved since the last threshold trip.

**Rung 0 deserves more weight than the old design gave it.** Configuring `--autocompact <tokens>` so the platform compacts at *our* number turns a keystroke problem into a configuration problem, and it works while the session is mid-turn, which rung 3 does not. The cost is that we lose control of the moment — and §5.4 says when that cost is real.

### 5.3 Verify: four independent signals, ranked, and a definition of failure

A compaction is **confirmed** only by a signal the compaction itself produced, never by a number that merely looks lower.

| Rank | Signal | Platform | Why it is trustworthy |
|---|---|---|---|
| 1 | **PostCompact hook fired**, writing `{at, trigger, summary_len}` to `state/ctx/<id>-compacted.json` | Claude Code | the runtime emits it after completion, with `compact_summary` in hand |
| 1 | `thread/compacted` / `ContextCompaction` item | Codex | same |
| 1 | `session.compaction.*` event | opencode | same |
| 2 | `compact_boundary` record appended to the transcript | Claude Code | on disk, timestamped, survives everything |
| 3 | `context_window.current_usage == null` in the next status-line payload | Claude Code | documented as the post-`/compact` state until the next API call |
| 4 | percent dropped below `threshold - hysteresis` **on a reading strictly newer than the watermark + grace** | all | last resort; this is the one that lies |

**Failure is a timer, not a guess.** If no rank-1/2 signal arrives within `verify_timeout` (start at 10 minutes — `J-WATCH-01` measured 67 % → 0 % in about seven), the trigger **did not execute**. Escalate one rung and log both percentages, as `WATCHER-PROMPT.md` already requires.

**Three states that must abort the ladder and go straight to rung 4**, all of them invisible to the previous generation and all of them **VERIFIED** as real:
- `autocompact: fixed prefix … — compaction cannot help` in the session's debug output → compacting will never work in this session again.
- `Autocompact is thrashing: … 3 times in a row` → same.
- Auto-compact `failure_breaker_open` → same.
Detect these from the session's own log/debug stream, not the screen, and treat any of them as **"compaction is dead here"**: no further `/compact`, straight to a fresh session.

### 5.4 Compact in place vs. fresh session — what the evidence actually says

The owner already decided this is his choice to make (`[204]`: «оркестратор можна як компактити, так і запускати повністю новий оркестратор»). What research adds is *when each is right*, and the deciding variable is **where the position lives**.

**`ORCHESTRATION.md` states the rule better than anything I found published**, and it was written from this run:

> "A lane watches its own context window, because nothing else does. … **a lane's position already lives on disk**: its plans, its summaries, `NN-FOUND.md` and `.planning/STATE.md`. A compact costs a lane its working memory, not its place — which makes compacting cheap, and makes waiting until the window forces it the only expensive choice." (lines 150–153)
> "**Act at about eighty per cent, while the moment is still yours to pick.** Past that, the auto-compact chooses for you, and it chooses the middle of whatever you happen to be doing." (line 155)
> "**Never compact with a mutation applied** — restore it, confirm the tree is clean with `git status --porcelain`, and only then compact. A compact that lands mid-mutation can leave deliberately-broken code in the tree with nothing left that knows to undo it." (lines 161–164)

**Evidence for compact-in-place**
- It works and it is fast: 74 % → 7 % in about two minutes (2026-09-02), 67 % → 0 % in about seven minutes (`J-WATCH-01`), 73 % → 0 % in ~90 s (§1.2 attempt 2).
- **It needs no close, so running work survives** — the armed monitor, the lanes, the containers. This is the decisive practical point, and it was established by failure: the close-and-respawn procedure was tried twice on 2026-09-02 and **both times the handoff was written and the replacement failed**, because `harness-spawn.sh close` refuses a session with a running job, the following `spawn` fails with `session orchestrator already registered`, and each attempt's `/exit` raises the background-work dialog and **blocks the orchestrator at a prompt it did not choose to face**. `WATCHER-PROMPT.md` lines 113–124: "Attempting it manufactures the exact outage this watch exists to prevent."
- The cheap case is a session whose findings are already durable. `WATCHER-PROMPT.md` line 158: for the context watch itself, "A compact costs you working memory, not your findings — the opposite of the orchestrator's case, where the handoff must be written first."

**Evidence for a fresh session with a written position**
- **Compaction loses the plan, and the fix is always the same file.** Every one of the four prompts says so independently: "after a compact the session holds a summary, so point it at the file rather than assuming it remembers where it was" (`WATCHER-PROMPT.md` step 5); "**If you have just compacted:** the paragraphs above are who you are. Re-read the rest of this file before your next cycle rather than working from the summary — the checks are exact, and a paraphrase of them is not good enough" (line 29); "after a compact you hold a summary of your instructions, not the instructions, and the brief is where your finalize rules live" (`ORCHESTRATION.md` line 167). **The position file is load-bearing in the compact case too** — so the choice is not "handoff or no handoff", it is only "same process or new one".
- **Compaction has terminal failure states** (§2.4). Once tripped, a fresh session is the *only* recovery.
- **A wedged session cannot be compacted out of.** `ORCH-HANDOFF.md`, trap 3: a lane "finished its work and then spun at 67 % context waiting on notifications from 22 subagents, 20 of them killed"; `spawn.sh close` correctly refuses a running job; the recorded fix is kill the pid, close to clear the registry, "then **spawn under a new name** — re-running the old launcher resumes the wedged conversation, because the session id is baked into it."
- **Vendors now ship the fresh-session path as the default recovery.** Codex's own `auto_compact_fallback_prompt` is verbatim: *"Your current context window is nearly exhausted; only {n_remaining} tokens remain. **Before starting a new context window, save concise progress notes** with the `notes` tool with the goal, decisions, progress, learnings, next steps, and the window ID and item ID of every relevant user request still being solved, as well as important actions/tool calls for future reference. … You should write or append notes in a way to best help you recover in a new context window. It is also a good idea to clean up your old notes if they become obsolete."* Claude Code's own thrash message ends "or use `/clear` to start fresh."
- **Claude Code 2.1.278 makes the fresh path much cheaper than it was.** `claude --bg`, `attach`, `logs`, `stop`, `respawn`, `agents --json`, `--fork-session`, `--session-id <uuid>`, `-n <name>` — the registry, naming and lifecycle problems that made close-and-respawn fail in 2026-09 are now first-class CLI verbs rather than scripts. This is recent and worth re-testing rather than inheriting the old verdict.

**Proposed default, which he can override per role — this is a recommendation, not a decision**

| Role | Default | Why |
|---|---|---|
| **executor / lane** | **compact in place**, soft, at ~75 % raw | position already on disk; compacting is cheap; running work must survive |
| **context watcher** | **compact in place**, self-initiated, at ~85 % raw | its record is an append-only log; a compact costs it nothing but working memory (`WATCHER-PROMPT.md` line 162) |
| **orchestrator** | **compact in place** at ~66 % raw, *after* a verified handoff refresh; **fresh session** when the handoff refresh cannot be verified, or any terminal compaction state is seen, or it is wedged | its position is *not* implicitly on disk; the handoff is the only copy; and it holds monitors that a close would strand |

**Three rules that apply to both paths**
1. **Refresh the position before compacting, and prove the file moved.** Do not proceed on the instruction having been sent — `WATCHER-PROMPT.md` step 2 says why, and PreCompact makes it deterministic.
2. **Never compact while a deliberate mutation is applied.** Gate on `git status --porcelain` being clean, or on an explicit `state/unsafe-to-compact` marker the session writes. Rung 0 (auto-compact) cannot honour this, which is the one strong argument for keeping the threshold below the auto-compact point rather than letting the platform choose the moment.
3. **The soft boundary is the step, and the step is configurable** (`[209]`/`[212]`). Concretely: default `step = "the current plan/ticket is committed and its summary written"` — `ORCHESTRATION.md` line 165 already says "finish the plan you are on, commit it, write its summary, and compact between plans." Let the user redefine it; make the orchestrator *emit* a step-boundary marker so the watcher does not have to infer one.

### 5.5 The handoff document — what a fresh session actually needs

Three independent sources agree on the same field list, so this is a converged pattern rather than one project's habit.

| Source | Fields it names |
|---|---|
| Codex `auto_compact_fallback_prompt` (**VERIFIED**, vendor-shipped) | goal · decisions · progress · learnings · next steps · **window ID + item ID of every user request still being solved** · important actions/tool calls for future reference · *clean up obsolete notes* |
| `ORCHESTRATION.md` line 113 (**VERIFIED**) | "It holds **the position, never the narrative**: what is running, what is blocked, what a fresh orchestrator does next." Rewritten after every spawn, close, block, answer and approval, and at every heartbeat |
| `ORCH-HANDOFF.md` as actually written (**VERIFIED**) | supersession notice · where the file now lives · read-these-first list · position (what is running: nothing) · exact commit sha and its relation to origin · ticket states by id · what the next run does · what the owner is owed · **traps this run paid for** · machine state (containers, ports, accounts, limit readings) |

**Design points worth taking, each traceable to a specific failure:**
- **A supersession line at the top.** `ORCH-HANDOFF.md` opens "this copy supersedes the one describing run `20260918-161219`" and states "There is exactly one `ORCH-HANDOFF.md` in the repository; the duplicate is gone deliberately." `FIELD-NOTES.md` §11.4 records "A records-drift check across seven handoff files exists only as prose — nothing runs it", and that it reports a false clean (`OK, 0 files compared`) when run from a subdirectory. **One file, one writer, and a drift check that actually executes.**
- **Position, not narrative.** The narrative belongs in the run report; mixing them is what makes the handoff too expensive to rewrite at every heartbeat.
- **Write it where a compaction cannot reach it,** and never to a channel the engine rebuilds. `FIELD-NOTES.md` §2.1: `state/attention` is truncated and re-`mv`-ed every watch cycle, so a night of corrections was destroyed, including a measured rebuttal written while the orchestrator was weighing killing a 378-test suite at test 240. `WATCHER-PROMPT.md` line 170: "Never use `state/attention` as your channel."
- **Refresh it on a cadence, not only at the threshold,** so the fresh-session path is available at any moment and not only after a successful pre-compact handshake. `ORCHESTRATION.md` line 115: rewritten "after every spawn, close, block, answer and approval, and at every heartbeat."
- **Say what the file is *for* at the top of it** — `ORCHESTRATION.md` line 117: "It exists because the watcher restarts the orchestrator when its context fills. The real state is on disk anyway … so a stale position file costs restart speed, not correctness." That sentence is what makes it safe to restart.
- **Carry the traps.** The most valuable third of the real `ORCH-HANDOFF.md` is "Three traps this run paid for". A summary will not reconstruct those; a file will.

### 5.6 The guaranteed-execution design, end to end

One state machine per supervised session, owned by one process, persisted on disk so a watcher restart resumes it rather than re-trips it.

```
OK ──percent ≥ threshold (two consecutive fresh readings)──► ARMED
ARMED ──mode=soft: wait for step boundary (notify_when_idle / status idle / step marker)
      ──mode=hard: interrupt now (Codex turn/interrupt; Claude Code: Escape into the tty)
      ──► PREPARING
PREPARING ── refresh handoff; require proof (PreCompact hook fired, or mtime moved) ──► TRIGGERING
TRIGGERING ── run the ladder rung for this platform; stamp the watermark ──► VERIFYING
VERIFYING ── rank-1/2 signal within verify_timeout ──► RECOVERING ──► OK
          ── timeout, or terminal-compaction-state seen ──► ESCALATING
ESCALATING ── next rung; after the last rung ──► FRESH SESSION ── still failing ──► NOTIFY HUMAN + HOLD
```

**Non-negotiables, each earned from a recorded failure:**

1. **Two consecutive fresh readings** before arming. A single reading may be a mid-compaction render (§5.1) or a stale bridge. Hysteresis on the way back down too, or the loop re-arms forever.
2. **Idempotency by watermark.** A trip is identified by `(session_id, threshold, armed_at)` and written to disk before acting. `FIELD-NOTES.md` §11.6 records an 85-minute loop that nothing internal could break: the watch matched a banner inside the orchestrator's *own wrapped prose*, pressed Escape and sent `continue` every ~60 s; each zero-second turn left the screen unchanged so the same text matched again, for ever. It ended only when an external `SIGTERM` arrived, and line 5620 of that log reads `NO ONE IS BEING TOLD`. **Any detector that re-reads its own effect must be idempotent per trip.**
3. **A bounded escalation with a human at the end.** The same §11.6 record and §11.1 ("The stale-heartbeat nudge is the only escalation the engine has", observed peaks of 47 minutes and ~12.4 hours before it fired) say the failure mode is not acting wrongly — it is acting the same way for ever. Cap the rungs; the last rung is a notification, and the run holds rather than spins.
4. **Never log the trigger phrases.** `WATCHER-PROMPT.md` lines 106–109: a watcher that prints `/compact`, or `rate-limit`, on its own screen gets matched by the deterministic watch and interrupted every cycle. Write `context action` and `none|present`. This is not cosmetic — it is the same class of bug as §11.6.
5. **Guard every probe against silent-empty.** `FIELD-NOTES.md` §11.3: BSD `find -newermt "-10 minutes"` errors out, and with stderr to `/dev/null` it returns empty every time — which would have declared every healthy session idle for ever. **A probe that can return empty on error must distinguish empty from failed**, and a probe that has never once returned a positive must be reported as unproven, not as clean.
6. **Watch the watcher's own window.** `WATCHER-PROMPT.md` line 152: "You watch the orchestrator's context. **Nothing watches yours.**" The context watch refilled 9 % → 91 % in about ten hours of ordinary cycling, ~8 % an hour at a 120-second cadence, and run `20260911-212252` reached 89 % at cycle 286 "with no provision for this anywhere". Whatever polls must have a threshold and an action of its own, and its cadence is itself a context cost — the same prompt slows to ~10 minutes when fewer than two lanes are alive.
7. **Budget for the pathological consumer.** `FIELD-NOTES.md` §3.1: one lane spent **3 466 of 3 626 Bash calls** on the literal command `echo idle`, ~1 400/hour for three hours, adding **445 k tokens of context — 77 % of all context growth in that window** — against 135 k from real work, and reaching 91 %. Every other lane in the run had zero. It stopped within one minute of being told to end its turn. **A context watcher that only compacts is treating the symptom**; the cheap win is detecting a polling loop and telling the session to end its turn. Refill rate, not just level, is the signal — `Δpercent/hour` above a bound is a defect, not a threshold.

**Configuration shape this implies** (his `[204]` mapped onto the mechanisms above; keys illustrative):

```yaml
context:
  defaults: { percent: 75, mode: soft, step: "plan-committed",
              action: compact, verify_timeout: 10m, on_fail: escalate }
  platforms:
    claude-code:
      read: statusline-bridge        # fallback: transcript
      trigger: [auto-compact, peer-message, tty-compact, fresh-session]
      command: "/compact"            # or a custom skill
      after: "read {{handoff}} and continue"   # delivered by SessionStart(compact) hook
    codex:
      read: rollout-token-count      # or app-server tokenUsageUpdated
      trigger: [rpc, queue-message, fresh-session]
    gemini-cli:
      read: otel-file
      trigger: [fresh-session]       # forced — see §4.3, raise as its own question
  roles:
    context-watcher: { percent: 85, action: compact }
    orchestrator:    { percent: 66, action: compact, on_fail: fresh-session,
                       handoff: .harness/supervisor/ORCH-HANDOFF.md }
    executor:        { percent: 75, action: compact }
```

Note this satisfies R1-08.5 exactly — per-window thresholds and per-window methods — and it is the same three names he used at `[036]`, `[195]` and `[204]`.

---

## 6. Open questions for the owner

Ordered by how much they block design.

1. **Raw or normalised percent?** They differ by ~13 points on Claude Code, and the old run's screen numbers were the normalised kind. My proposal is raw (matching `/context`), but 66 % raw ≈ 79 % on the bar he has been reading. **Which number is the 66 he has in mind?**

2. **Who owns the polling — the orchestrator or the context watcher?** At `[195]` he said «оркестратор чи контекст вочер», leaving it open, and at `[204]` he said the compact is «який буде робити оркестратор». But at `[300–302]` he set the single-orchestrator invariant and said two simultaneous orchestrators are «не окей». If the orchestrator is what acts on context, then restarting a full orchestrator to fix a context problem has to go through the same invariant. **The previous generation resolved this by making the watcher the actor and the orchestrator the subject — is that the split he wants, and does the watcher's authority to restart an orchestrator count against the invariant?**

3. **Gemini CLI cannot be compacted from outside, and its threshold needs a restart to change.** Per instruction **I1 `[182–184]`**, this is a per-platform divergence and gets its own question: **accept (B) fresh-session-only for that platform, drop it from the supported list, or require the user to write a custom skill for it?** The same question, in weaker form, applies to any platform we have not measured.

4. **Does "guaranteed" mean the action, or the outcome?** My reading is the outcome — a closed loop ending in a fresh session and then a human. That reading implies the orchestrator can be replaced without his say-so when compaction dead-ends. **Is a fresh-session fallback something the orchestrator may do on its own, or is it an escalation to him?** This is the same axis as the controlled/autonomous split at `[062]`/`[075]`, and it probably inherits that setting rather than getting its own.

5. **What exactly is a "step" by default?** `[209]` says the step, `[212]` ratifies, and «людина може сама налаштувати, що це означає». `ORCHESTRATION.md` already proposes "between plans, after the commit and the summary". **Is that the default, and should the orchestrator emit an explicit step-boundary marker so the watcher never has to guess?**

6. **Configuring a status line costs the `esc to interrupt` footer hint.** The replacement (`claude agents --json`) is better, but it is a behaviour change on his own terminal. **Is a status line the orchestrator is allowed to install acceptable, or must the read path stay purely passive (transcript only)?**

7. **The mutation rule vs. auto-compaction.** «Never compact with a mutation applied» cannot be honoured by the platform's own auto-compact, which fires whenever it likes. That argues for keeping our threshold safely below the auto-compact point and treating auto-compaction as a failure, not a fallback. **Does he want auto-compaction disabled (`DISABLE_AUTO_COMPACT`) on supervised sessions so that ours is the only compaction that ever happens — accepting that a missed trigger then means a hard wall instead of a clumsy rescue?**

8. **Three Claude Code compaction dead-ends exist that nothing currently detects** (prefix-overflow, thrash breaker, failure breaker). **Should hitting one be a notification-worthy event at night** (R1-17's question), or is silently starting a fresh session enough?

9. **Refill rate as a first-class signal.** The 445 k-token polling lane is the largest single context finding in the field notes and compaction would only have papered over it. **Should the context watcher be allowed to intervene on *how* a session spends its window — "end your turn instead of polling" — or is that the orchestrator's business under R1-09?**

---

## Sources

**Read on this machine (VERIFIED):** `~/.local/share/claude/versions/2.1.278` (binary strings: statusline payload builder, hook schemas, auto-compact path, settings schema) · `claude --help`, `claude agents --help`, `claude agents --json` (executed) · `~/.claude/settings.json`, `~/.claude/statusline-command.sh`, `~/.claude/hooks/gsd-statusline.js`, `~/.claude/hooks/gsd-context-monitor.js` · `~/.claude/projects/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-….jsonl` · `~/.codex/sessions/2026/09/13/rollout-2026-09-13T17-19-52-….jsonl` · `codex app-server generate-json-schema --out` output (executed) · `codex --help`, `codex queue --help`, `codex app-server {proxy,daemon} --help`, `codex app-server daemon version` (executed) · `@openai/codex-darwin-arm64` native binary strings · live `SendMessage`/`ListAgents` probe against a `claude --bg` session (executed) · `plugins/harness/docs/FIELD-NOTES.md` · `<work>/<work-project>/.harness/supervisor/{WATCHER-PROMPT.md,ORCHESTRATION.md,ORCH-HANDOFF.md}` · `product/spikes/harness-rebuild/round-1/{TRANSCRIPT-01.md,ANALYSIS-01.md}` · `product/spikes/harness-rebuild/research/extract/{by-item,outside-list,corrections,meta}.md` · `google-gemini/gemini-cli@main` `packages/core/src/context/chatCompressionService.ts`, `packages/core/src/hooks/types.ts`, `packages/cli/src/config/settingsSchema.ts` (fetched raw).

**Documentation (CLAIMED):** [Claude Code — status line](https://code.claude.com/docs/en/statusline) · [Claude Code — hooks](https://code.claude.com/docs/en/hooks) · [opencode — Compaction](https://opencode.ai/v2/docs/compaction) · [Context Compaction Deep Dive: Codex CLI, Claude Code, OpenCode](https://codex.danielvaughan.com/2026/04/14/context-compaction-deep-dive-codex-cli-claude-code-opencode/) · [Chat Compression and Context Management — google-gemini/gemini-cli (DeepWiki)](https://deepwiki.com/google-gemini/gemini-cli/4.12-chat-compression-and-context-management) · [Context Management and Compaction — sst/opencode (DeepWiki)](https://deepwiki.com/sst/opencode/2.4-context-management-and-compaction) · [How AI Coding Agents Handle a Full Context Window](https://wasnotwas.com/writing/context-compaction/) · Anthropic token counting (`POST /v1/messages/count_tokens`) and Models API `max_input_tokens`, per the bundled `claude-api` skill.

**May have changed since:** Claude Code ships several builds a week (four versions on this machine inside four days), so the absence of a compaction RPC is a fact about `2.1.278` on 2026-09-19, not a permanent one — **re-check `claude --help` and `claude agents --help` before committing to the tty path.** The Codex app-server protocol is marked `[experimental]` throughout and its v1/v2 schemas differ. opencode's V1→V2 compaction config renamed keys, and nothing about it was executed here.
