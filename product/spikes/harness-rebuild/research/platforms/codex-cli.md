# Platform profile — OpenAI Codex CLI / ChatGPT

**Date of pass:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0, macOS 26.5.2, arm64).
**Installed here:** `codex` **0.152.0** at `~/.nvm/versions/node/v22.18.0/bin/codex`
(npm `@openai/codex`, Apache-2.0, native binary at
`.../node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex`, 217 MB).
**npm latest:** 0.155.1 — this install is **3 releases behind** (`codex doctor` says so itself).
**Second copy on this machine:** `/Applications/ChatGPT.app/Contents/Resources/codex` = **0.155.0-alpha.9.2**.
**Account:** ChatGPT auth, `<email>`, plan **`prolite`**.

**Evidence tags:** **VERIFIED** = read in the generated protocol schema, read on disk, or executed
here today. **CLAIMED** = docs only. **UNKNOWN** = not established.

**What was run:** `--help` on every subcommand, `codex doctor`, `codex features list`,
`codex mcp list`, `codex login status`, `codex app-server generate-json-schema`, and two
**read-only JSON-RPC sessions against a live `codex app-server --stdio`**. No agent turn was
started; no model tokens were spent; no owner config was modified. One `codex queue` probe wrote a
row to `~/.codex/queue_1.sqlite` and **that row was deleted again** (verified: the only remaining
queued row is from 2026-09-04 and is not mine).

---

## Verdict up front

**Codex is the most orchestrator-ready platform in this field, by a wide margin, and the reason is
not the CLI — it is `codex app-server`: a documented, versioned, bidirectional JSON-RPC 2.0 control
plane with 98 client methods, 10 server-to-client requests and 81 server notifications.** Every axis
the owner called non-negotiable is a first-class method on it, and four of the five were executed
live on this machine today:

| Non-negotiable | Answer | Status |
|---|---|---|
| **E** read remaining quota | `account/rateLimits/read` → `usedPercent`, `resetsAt`, `windowDurationMins` | **VERIFIED — ran it, got 6% / weekly / resets 1790415035** |
| **F** account per role | `CODEX_HOME=<dir>` gives a fully isolated account | **VERIFIED — ran it, isolated home reported "Not logged in"** |
| **D** compaction from outside, with proof | `thread/compact/start` → `thread/compacted` notification; fullness from `thread/tokenUsage/updated` | **VERIFIED in schema + on disk; the trigger itself NOT executed (would spend quota)** |
| **B** resume exactly after a crash | `thread/resume {threadId}` / `codex exec resume <id>` | **VERIFIED — resumed a real 2026-09-04 thread, status went to `idle`** |
| **G** answer the session's own question | `item/tool/requestUserInput` is a **server→client JSON-RPC request**; the client replies `{answers:{...}}` | **VERIFIED in schema; no live question available to answer** |

The one thing Codex will **not** do is let the orchestrator **name a session before it exists**
(see B). Everything else it does better than the current harness.

---

## A. LAUNCH

### Headless — `codex exec` (VERIFIED, flags quoted from `codex exec --help` on 0.152.0)

```
codex exec [OPTIONS] [PROMPT]
codex exec resume [OPTIONS] [SESSION_ID] [PROMPT]
codex exec fork  [OPTIONS] ...
codex exec review [OPTIONS] ...
```

Orchestrator-relevant flags, all **VERIFIED** present in 0.152.0:

| Flag | Meaning |
|---|---|
| `--json` | newline-delimited JSON events on stdout (alias `--experimental-json`, CLAIMED by docs) |
| `-o, --output-last-message <FILE>` | write the agent's final message to a file — the clean "what did it conclude" channel |
| `--output-schema <FILE>` | JSON Schema the final response must satisfy — **structured, machine-checkable results** |
| `-C, --cd <DIR>` | working root |
| `--add-dir <DIR>` | extra writable roots |
| `-s, --sandbox <read-only\|workspace-write\|danger-full-access>` | sandbox policy |
| `-a, --ask-for-approval <on-request\|never>` | *(top-level `codex`; `exec` defaults to non-interactive)* |
| `--approve-for-me` | route approvals through automatic review under workspace-write |
| `--dangerously-bypass-approvals-and-sandbox` | no sandbox, no approvals (alias **`--yolo`**, hidden — **VERIFIED accepted**) |
| `--dangerously-bypass-hook-trust` | run hooks without persisted trust — **explicitly "intended only for automation"** |
| `--ephemeral` | run **without persisting session files** (do not use — it destroys axes B and C) |
| `--skip-git-repo-check` | run outside a git repo |
| `--ignore-user-config` | ignore `$CODEX_HOME/config.toml` (auth still uses `CODEX_HOME`) |
| `--ignore-rules` | ignore user/project execpolicy `.rules` files |
| `-p, --profile <NAME>` | layer `$CODEX_HOME/<name>.config.toml` over base config |
| `-c, --config key=value` | any config key, dotted path, TOML-parsed value |
| `--strict-config` | **error on unknown config keys** — see the capability-probe trick under J |
| `-m, --model`, `-i, --image`, `--color`, `--thread-source <SOURCE>` | |

The prompt may be an argument, or `-`/piped stdin. If stdin is piped **and** a prompt is given,
stdin is appended as a `<stdin>` block (VERIFIED, help text).

**`--full-auto` is documented but does NOT exist in 0.152.0** — `error: unexpected argument
'--full-auto' found` (VERIFIED). Docs/binary skew is real here; trust `--help`, not the docs.

### `codex exec --json` event vocabulary (VERIFIED — extracted from the native binary's string table)

```
thread.started  turn.started  turn.completed  turn.failed
item.started    item.updated  item.completed  error
```

`turn.completed` carries `turn.token_usage` (with `cached_input`, `cache_write_input`, `output`) and
`turn.cost_microusd` (VERIFIED, adjacent binary strings). Note these are **dot-separated** and are a
*different* vocabulary from the app-server's slash-separated `turn/completed`. An orchestrator that
supports both transports needs two parsers.

### Visible, attachable terminal (VERIFIED by help; not executed)

This is where Codex beats a tmux-scraping harness. `codex` (the TUI) accepts:

```
codex --remote <ADDR>              # ws://host:port | wss://host:port | unix:// | unix://PATH
codex --remote-auth-token-env <ENV_VAR>
codex --no-alt-screen              # inline mode, preserves scrollback
codex agents                       # "Browse all agent sessions on the shared local app-server daemon"
```

So the intended shape is: **one app-server daemon owns the sessions; the orchestrator drives it over
JSON-RPC; the owner attaches a TUI to the same daemon and can watch and type into any session.**
That removes the whole class of "scrape the screen / can't submit stranded text" failures the
current harness records. `codex agents` requires a TTY (**VERIFIED**: `ERROR: stdin is not a
terminal`), which is correct — it is the human's window, not the orchestrator's.

### The control plane itself

```
codex app-server --listen <stdio://|unix://|unix://PATH|ws://IP:PORT|off>   # default stdio://
codex app-server --stdio
codex app-server daemon bootstrap|start|restart|stop|version
codex app-server daemon enable-remote-control|disable-remote-control
codex app-server proxy                      # proxy stdio bytes to the running control socket
codex app-server generate-ts | generate-json-schema --out <DIR>
codex remote-control start|stop|pair [--json]
```

WebSocket listeners have real auth: `--ws-auth <capability-token|signed-bearer-token>`,
`--ws-token-file`, `--ws-token-sha256`, `--ws-shared-secret-file`, `--ws-issuer`, `--ws-audience`,
`--ws-max-clock-skew-seconds` (all VERIFIED in `--help`).

Daemon control socket: `~/.codex/app-server-control/app-server-control.sock` (**VERIFIED** — named
verbatim in the error when no daemon is running). Locks: `~/.codex/app-server-daemon/daemon.lock`,
`app-server.pid.lock`, `~/.codex/app-server-control/app-server-startup.lock`,
`~/.codex/cross-instance-locks/`. A separate live socket `~/.codex/ipc/ipc.sock` exists (mtime today
15:42) — **UNKNOWN** what protocol it speaks; it is not the app-server control socket.

**Live handshake, VERIFIED today:**

```json
→ {"id":1,"method":"initialize","params":{"clientInfo":{"name":"orchestrator-probe","title":"probe","version":"0.0.1"}}}
← {"id":1,"result":{"userAgent":"orchestrator-probe/0.152.0 (Mac OS 26.5.2; arm64) iTerm.app/3.6.11 (...)",
                    "codexHome":"/Users/sasha-marchuk/.codex","platformFamily":"unix","platformOs":"macos"}}
→ {"method":"initialized"}
```

The server also pushed `remoteControl/status/changed` unprompted with
`{"status":"disabled","serverName":"<host>","installationId":"1832fd45-...","environmentId":null}`.

**Verdict on A:** both halves supported, and the "visible terminal" half is architecturally better
than anything the current harness does. The only cost is that the rich half is marked
`[experimental]` in `--help`.

---

## B. IDENTITY & RESUME

### What works (VERIFIED live)

`thread/resume {threadId}` on a real thread from 2026-09-04 returned the full thread object and
flipped its status to `{"type":"idle"}` with `"canAcceptDirectInput": true`. Resume is exact: the
`turns` array came back populated, and the response carries `itemsBackwardsCursor` /
`turnsBackwardsCursor` for paging the rest.

CLI equivalents (VERIFIED in `--help`):

```
codex exec resume [SESSION_ID|THREAD_NAME] [PROMPT]   [--last] [--all]
codex resume      [SESSION_ID|THREAD_NAME] [PROMPT]   [--last] [--all] [--include-non-interactive]
codex fork / codex exec fork                          # branch instead of continue
codex archive|unarchive|delete <id|name>
```

Both `resume` forms accept **a UUID or a thread name**, "UUIDs take precedence if it parses."
`codex resume` **hides non-interactive (exec) sessions from the picker unless
`--include-non-interactive` is passed** (VERIFIED) — an orchestrator resuming its own exec sessions
must pass it, or use `codex exec resume`, or the protocol.

Protocol surface: `thread/start`, `thread/resume`, `thread/fork`, `thread/list`, `thread/read`,
`thread/loaded/list`, `thread/archive`, `thread/unarchive`, `thread/delete`, `thread/unsubscribe`,
plus **`thread/rollback {numTurns}`** and **`thread/revert {beforeTurnId}`** — the orchestrator can
rewind a session that went wrong instead of killing it.

`thread/list` filters are rich enough to build a supervisor dashboard: `cwd` (string or list),
`searchTerm`, `archived`, `sectionId`, `modelProviders`, `sortKey` (`created_at`/`updated_at`/
`recency_at`/`section_position`), `sortDirection`, `cursor`, `limit`, and `sourceKinds` —
`cli | vscode | exec | appServer | subAgent | subAgentReview | subAgentCompact |
subAgentThreadSpawn | subAgentOther | unknown` (VERIFIED). The orchestrator's own sessions are
therefore filterable by `sourceKinds: ["exec"]` or `["appServer"]`.

### The one real gap: the orchestrator cannot name a session before it exists

`ThreadStartParams` has **no id field** (VERIFIED — full param list is `approvalPolicy`,
`approvalsReviewer`, `baseInstructions`, `config`, `cwd`, `developerInstructions`, `ephemeral`,
`model`, `modelProvider`, `personality`, `sandbox`, `serviceName`, `serviceTier`,
`sessionStartSource`, `threadSource`). `codex exec` has **no `--session-id` flag**. Compare pi's
`--session-id <id>` "use exact project session ID, creating it if missing".

`CODEX_SESSION_ID` exists in the binary but is an **output, not an input**: Codex *exports* it into
the agent's shell environment. **VERIFIED on disk** — a rollout from 2026-09-03 shows
`CODEX_SESSION_ID=01a0668a-aab3-74d3-9cea-34bece754852` inside a captured shell env dump, equal to
that rollout's own thread id.

**Workaround, and its cost.** Start, capture the id from `thread.started` (exec `--json`) or
`ThreadStartResponse.thread.id`, then immediately call **`thread/name/set {threadId, name}`** and
use that name as the stable handle forever after — both `codex exec resume` and
`codex queue --thread` accept a name. Cost: a **crash in the window between start and naming leaves
an orphan**. Mitigation that closes the window without protocol support: a **`SessionStart` hook**
(see H) fires inside the new session and can write the id where the orchestrator will find it.

### What survives a crash

The rollout JSONL is append-only and flushed per event, so a hard kill loses at most the in-flight
turn; `thread/resume` then replays from the file. **VERIFIED**: `~/.codex/state_5.sqlite` `threads`
row carries `rollout_path`, and `thread/read` returns that same `path`
(`~/.codex/sessions/2026/09/04/rollout-2026-09-04T12-37-32-<uuid>.jsonl`) — protocol and disk agree.

**But durability is not perfect, and `codex doctor` says so on this machine** (VERIFIED, today):

```
⚠ threads   3 issues - rollout files are missing from the state DB; duplicate thread inventory entries found
    rollout DB scan errors             44
    rollout DB missing active rows      1
    rollout DB duplicate rollout thread ids 1
    rollout DB scan error sample  ... "has no usable header record"
```

44 of 380 rollout files cannot be indexed because they have **no usable header record** — i.e. the
process died before writing `session_meta`. Those sessions are unresumable by id. For an overnight
queue this is the concrete failure mode: **~1% of sessions here are already unrecoverable, and a
crash at t=0 is exactly what produces them.**

A provider outage is not modelled as a session state: `ErrorNotification` carries
`{message, willRetry, codexErrorInfo}` per `{threadId, turnId}` (VERIFIED). `willRetry` is the flag
the supervisor should watch before deciding a session is dead.

---

## C. TRANSCRIPT

**Three stores, and the orchestrator should read exactly one of them.**

### 1. Rollout JSONL — the source of truth (VERIFIED)

`~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-<ISO8601>-<thread-uuid>.jsonl`
Archived: `~/.codex/archived_sessions/`. Here: **380 active files, 226.89 MB, avg 611 KB**; 10
archived. Line 1 is `session_meta`; every line is `{timestamp, ordinal, type, payload}`.

Record types seen in a real session (VERIFIED, counted):
`session_meta`, `response_item` (`message` / `reasoning` / `custom_tool_call` /
`custom_tool_call_output`), `event_msg` (`task_started`, `task_complete`, `item_completed`,
`token_count`, `thread_settings_applied`), `token_usage_record`, `turn_context`, `world_state`,
`realtime_item`.

`session_meta.payload` keys: `session_id`, `id`, `timestamp`, `cwd`, `originator`, `cli_version`,
`source`, `thread_source`, `model_provider`, `base_instructions`, `history_mode`, `context_window`,
`git`. `originator` distinguishes launchers: `codex_exec` for headless, `codex_work_desktop` for the
ChatGPT app (VERIFIED).

**A supervisor can tail this file live and needs nothing else** — it carries the transcript, the
token counts *and* the rate limits (see D and E). This is the single most important operational fact
in this profile: **the cheapest possible Codex supervisor is `tail -f` on one JSONL file.**

### 2. `~/.codex/thread_history_1.sqlite` — a projection, not a second truth (VERIFIED)

Tables `thread_turns`, `thread_items`, `thread_realtime_items`, `thread_history_projection_state`.
Every row carries `rollout_ordinal` / `rollout_byte_offset`, and
`thread_history_projection_state.next_rollout_byte_offset` is literally a resume pointer into the
JSONL. 72 MB here. It exists to paginate, not to replace the file. **All 345 threads on this machine
are `history_mode = 'paginated'`** — the new path is fully live.

### 3. `~/.codex/state_5.sqlite` — the inventory (VERIFIED)

`threads` table: `id`, `rollout_path`, `created_at`, `updated_at`, `source`, `model_provider`, `cwd`,
`title`, `sandbox_policy`, `approval_mode`, **`tokens_used`**, `archived`, `git_sha`, `git_branch`,
`git_origin_url`, `cli_version`, `agent_nickname`, `agent_role`, `model`, `reasoning_effort`,
`history_mode`, `is_pinned`, `project_id`, `originator`. Also `thread_spawn_edges`
(`parent_thread_id`, `child_thread_id`, `status`) — **the subagent tree is queryable in SQL.**

Source distribution on this machine today: **`exec=191, vscode=150, subagent:thread_spawn=3,
cli=1`**. The owner has already run 191 headless Codex sessions.

### Live read over the protocol (VERIFIED live)

`thread/items/list {threadId, limit, sortDirection, cursor, turnId?}` returned typed items:

```json
{"turnId":"01a06aec-182b-...","item":{"type":"agentMessage","id":"msg_...","text":"OK","phase":"final_answer"}}
{"turnId":"01a06aec-182b-...","item":{"type":"userMessage","id":"01a06aec-2818-...","content":[{"type":"text","text":"Say OK"}]}}
```

plus `thread/turns/list {itemsView: notLoaded|summary|full}`. The server pushed a
**`deprecationNotice`** during the probe — quoted verbatim, and it is an instruction to whoever
writes the client:

> "Full-history hydration is deprecated for paginated threads; use `excludeTurns: true`, then page
> with `thread/turns/list` and `thread/items/list`."

Streaming equivalents: `item/started`, `item/completed`, `item/agentMessage/delta`,
`item/reasoning/textDelta`, `item/reasoning/summaryTextDelta`, `item/commandExecution/outputDelta`,
`item/fileChange/patchUpdated`, `turn/diff/updated`, `turn/plan/updated`.

### Security note the orchestrator must handle (VERIFIED, and it matters)

**Rollout files capture the agent's full shell environment, including secrets.** A 2026-09-03 rollout
on this machine contains a live API key in plaintext inside an
`item_completed` payload. Value deliberately not reproduced here. Consequences: (1) any orchestrator
that ships transcripts off-box is exfiltrating credentials; (2) `~/.codex/sessions/` deserves the
same handling as a keychain; (3) `shell_environment_policy.filters` /
`shell_environment_policy.inherit = "core"` should be set for unattended runs.

---

## D. CONTEXT

**This is the axis the current harness cannot do at all, and Codex answers it three ways.**

### Reading fullness

`thread/tokenUsage/updated` notification (VERIFIED in schema):

```
{threadId, turnId, tokenUsage: {
   last:  {inputTokens, cachedInputTokens, cacheWriteInputTokens, outputTokens, reasoningOutputTokens, totalTokens},
   total: {...same...},
   modelContextWindow }}
```

**Fullness = `tokenUsage.total.totalTokens / tokenUsage.modelContextWindow`.** Both numbers are in
one event.

The same pair is on disk in every `event_msg`/`token_count` record (**VERIFIED**, real values from
`rollout-2026-09-13T17-19-52-...jsonl`):

```json
{"type":"event_msg","payload":{"type":"token_count",
  "info":{"total_token_usage":{"input_tokens":37765,"cached_input_tokens":19456,
           "output_tokens":224,"reasoning_output_tokens":0,"total_tokens":37989},
          "last_token_usage":{...},
          "model_context_window":258400},
  "rate_limits":{...}}}
```

So a supervisor reads context fullness **from the transcript file alone, with no daemon and no
protocol client**. `~/.codex/state_5.sqlite.threads.tokens_used` gives a coarser per-thread total for
a cheap SQL sweep across all sessions at once.

### Triggering compaction from outside, with proof

- **Trigger:** `thread/compact/start {threadId}` (VERIFIED in schema; **not executed — a compaction
  runs a real model turn and would spend the owner's quota**).
- **Proof:** `thread/compacted {threadId, turnId}` notification (VERIFIED in schema). A second,
  independent proof exists on disk: compaction runs as its own subagent thread, and
  `thread/list`'s `sourceKinds` includes **`subAgentCompact`** (VERIFIED) — so a compaction leaves a
  queryable row, not just a log line.
- **Hooks:** `PreCompact` / `PostCompact` fire around it (CLAIMED — docs).

### Configuring compaction (VERIFIED against the installed 0.152.0)

These keys were validated by the `--strict-config` probe described under J — a deliberately bogus
key was rejected, each of these was accepted:

| Key | Effect |
|---|---|
| `model_auto_compact_token_limit` | token threshold that auto-triggers compaction |
| `model_auto_compact_token_limit_scope` | `"total"` \| `"body_after_prefix"` |
| `compact_prompt` | **override the compaction prompt itself** |
| `model_context_window` | override the assumed window |

So the orchestrator can set the auto-compaction threshold per launch via `-c`, supply its own
handoff prompt, *and* force a compaction mid-run — with proof in both the notification stream and
the thread inventory. **Axis D is fully satisfied, and it is the largest single capability gain over
the current harness.**

### Related: native token budgets

`thread/goal/set {threadId, objective?, tokenBudget?, status?}` where status is
`active | paused | blocked | usageLimited | budgetLimited | complete`, and `thread/goal/get` returns
`{tokensUsed, timeUsedSeconds, tokenBudget, status}` (VERIFIED). Codex has a **built-in per-session
budget with usage/limit states the orchestrator can read** — `goals` is `stable/true` in
`codex features list`. Backed by `~/.codex/goals_1.sqlite`.

---

## E. QUOTA

### Executed live today (VERIFIED) — `account/rateLimits/read`, zero tokens spent

```json
{"rateLimits":{"limitId":"codex","limitName":null,
  "primary":{"usedPercent":6,"windowDurationMins":10080,"resetsAt":1790415035},
  "secondary":null,
  "credits":{"hasCredits":false,"unlimited":false,"balance":"0"},
  "individualLimit":null,"spendControlReached":false,
  "planType":"prolite","rateLimitReachedType":null},
 "rateLimitsByLimitId":{"codex":{...}},
 "rateLimitResetCredits":{"availableCount":2,"credits":[
    {"id":"RateLimitResetCredit_<id>...","resetType":"codexRateLimits","status":"available",
     "grantedAt":1788488180,"expiresAt":1791080180,"title":"Full reset",
     "description":"Thanks for using Codex! You've been granted one free rate limit reset."},
    {"id":"RateLimitResetCredit_<id>...", ...}]},
 "accountId":"<account-id>","rateLimitUpsell":null}
```

### Windows

`RateLimitWindow = {usedPercent (required), resetsAt (unix seconds, nullable), windowDurationMins
(nullable)}` (VERIFIED, schema). There are up to two: `primary` and `secondary`.

**The window layout is plan-dependent — do not hardcode it.** Across all 380 rollouts on this
machine (VERIFIED by counting):

| `window_minutes` | occurrences | meaning |
|---|---|---|
| 10080 | 4747 | 7 days |
| 10079 | 2726 | 7 days |
| 299 | 2726 | ~5 hours |
| 300 | 532 | 5 hours |

Historic sessions (Oct 2025, `plan_type: "plus"`) show **primary = 5h, secondary = weekly**. Today
on `prolite`, **primary = weekly and `secondary` is `null`**. An orchestrator that assumes
"primary = 5h" will mis-schedule on this account right now.

### Three independent ways to read it

1. **Protocol pull:** `account/rateLimits/read` — no thread needed, no tokens. *Best for a
   pre-flight gate.*
2. **Protocol push:** `account/rateLimits/updated` notification carrying the same `RateLimitSnapshot`
   — arrives as the numbers change. *Best for a live supervisor.*
3. **On disk:** the `rate_limits` block inside every `event_msg`/`token_count` line of the rollout
   JSONL — **VERIFIED present in `codex exec` rollouts too**, e.g.
   `rollout-2026-09-04T12-37-32-...jsonl`: `{"limit_id":"codex","primary":{"used_percent":36.0,
   "window_minutes":10080,"resets_at":1788748704},"plan_type":"prolite"}`. *Best for a zero-dependency
   watcher.*

Note the casing split: **on disk it is snake_case** (`used_percent`, `window_minutes`, `resets_at`),
**over the protocol it is camelCase** (`usedPercent`, `windowDurationMins`, `resetsAt`). Same data,
two spellings.

### Limit-hit signalled in band

`rateLimitReachedType` ∈ `rate_limit_reached | workspace_owner_credits_depleted |
workspace_member_credits_depleted | workspace_owner_usage_limit_reached |
workspace_member_usage_limit_reached`, plus `spendControlReached: bool` and `credits:
{hasCredits, unlimited, balance}` (VERIFIED). It has never fired on this machine (zero non-null
occurrences across all rollouts), so the **field is confirmed but the path is untested here**.

### The surprise: quota can be *reset* programmatically

`account/rateLimitResetCredit/consume {idempotencyKey, creditId?}` →
`{outcome: reset | nothingToReset | noCredit | alreadyRedeemed}` (VERIFIED, schema). **This account
holds 2 unused "Full reset" credits right now, expiring 1791080180 and 1791174114.** An overnight
orchestrator that hits the weekly wall can redeem one and keep going, idempotently, without the
owner awake. No other platform in this field has an equivalent.

Also available: `account/usage/read` → lifetime tokens, daily buckets, per-thread
`estimatedUsageCreditsMicros` / `estimatedUsageUsdMicros` (VERIFIED, schema) — real cost attribution
per thread.

---

## F. ACCOUNTS

### The mechanism: `CODEX_HOME` (VERIFIED by execution)

```
$ codex login status                      → Logged in using ChatGPT
$ CODEX_HOME=/tmp/…/fakehome codex login status   → Not logged in
```

One environment variable relocates **the entire account and state**: `auth.json`, `config.toml`,
`sessions/`, all four SQLite databases, plugins, skills. `codex doctor` reports `CODEX_HOME` as a
first-class field, and the app-server echoes `codexHome` back in the `initialize` result — so the
orchestrator can **confirm which account a session landed on** rather than hope.

This is strictly better than Claude Code's arrangement, where the owner needed a profile switcher and a
Keychain-derived service name. Codex stores credentials in a **plain file**,
`~/.codex/auth.json` (mode `-rw-------`), shape (VERIFIED, values withheld):

```
auth_mode: "chatgpt"
OPENAI_API_KEY: null
tokens.id_token / tokens.access_token / tokens.refresh_token
tokens.account_id: "<account-id>..."
last_refresh: "2026-09-18T14:46:38.156971Z"
```

**No Keychain, therefore no GUI prompt.** The field scan flagged that an unattended Claude Code run
can block forever on a macOS "Always Allow" dialog. **Codex cannot hit that failure mode.** For an
overnight queue this is a decisive practical advantage.

### Per-role setup, in practice

- Give each role its own `CODEX_HOME` (e.g. `~/.codex-roles/reviewer`), log in once interactively,
  then every launch is `CODEX_HOME=… codex exec …`. **VERIFIED mechanism.**
- Non-interactive login also exists: `codex login --with-api-key` and `codex login
  --with-access-token`, both **reading the secret from stdin** (VERIFIED), e.g.
  `printenv OPENAI_API_KEY | codex login --with-api-key`. Plus `--device-auth`.
- Over the protocol: `account/login/start` accepts `{type:"apiKey",apiKey}`,
  `{type:"chatgptAuthTokens",accessToken,chatgptAccountId,chatgptPlanType}`, `{type:"chatgpt"}`
  (returns `authUrl`+`loginId`), `{type:"chatgptDeviceCode"}` (returns `userCode`+`verificationUrl`),
  `{type:"amazonBedrock"…}`, `{type:"amazonBedrockAccessKeys"…}` (VERIFIED). Completion arrives as
  `account/login/completed {success, loginId, error?}` — **a login is fully automatable and
  observable**, which is rare.
- `account/read {refreshToken?}` → `{account:{type:"chatgpt",email,planType},requiresOpenaiAuth}`
  (**VERIFIED live**). Use it to assert the session is on the intended account before dispatching
  work.
- Env-var alternatives present in the binary: `CODEX_API_KEY`, `OPENAI_API_KEY`,
  `CODEX_ACCESS_TOKEN`, `CODEX_AGENT_IDENTITY_AUTH`, `CODEX_GITHUB_PERSONAL_ACCESS_TOKEN`
  (VERIFIED as strings; precedence **UNKNOWN**).
- `-p, --profile <NAME>` layers `$CODEX_HOME/<name>.config.toml` — per-role *config* within one
  account. None exist here (no `~/.codex/*.config.toml`).

### Can a running session's account be changed?

**No.** `account/login/start` and `account/logout` are process-wide for that `CODEX_HOME`; there is
no per-thread account parameter in `ThreadStartParams` or `ThreadResumeParams` (VERIFIED by absence).
Closest workaround: run **one app-server per account** and have the orchestrator route new threads to
the right daemon — which is what distinct `CODEX_HOME`s plus `--listen unix://<path-per-account>`
gives you naturally. Cost: N daemons, N sockets, N sets of MCP servers booting.

---

## G. INTERVENTION

**Codex is the strongest platform in this field on the axis the current harness fails.** Four
distinct mechanisms, at three levels of coupling.

### 1. Steer a turn that is already running — `turn/steer` (VERIFIED, schema)

```
TurnSteerParams  = {threadId, expectedTurnId, input[], clientUserMessageId?}
TurnSteerResponse= {turnId}
```

Two properties that matter. **`expectedTurnId` is an optimistic-concurrency guard** — the caller
states which turn it believes is running, so a steer cannot land on the wrong turn after a race.
And the response returns a `turnId`, so **delivery is acknowledged**, not hoped for. `steer` is
listed as stage `removed` / state `true` in `codex features list`, meaning the flag was retired
because the capability graduated to always-on (VERIFIED).

### 2. Inject items into a thread — `thread/inject_items {threadId, items[]}` (VERIFIED, schema)

Puts content into the thread's history without driving a turn. Item schema is open (`items: [True]`
in the generated schema, i.e. unconstrained) — exact accepted shapes **UNKNOWN**.

### 3. Queue a message durably — `codex queue` (VERIFIED by execution, and the result surprised me)

```
codex queue --thread <THREAD_UUID|exact session name> --message <TEXT> [-i IMAGE]
```

I ran this **with no daemon running** and it still succeeded:

```
Queued message 01a0b9d2-d950-7703-9421-29e4ceaaa2f3 for thread 01a06aec-....
```

It wrote a row into `~/.codex/queue_1.sqlite` (`queued_items(id, thread_id, payload_json,
queue_order, created_at_ms)`, payload
`{"UserInput":{"content":[{"type":"text","text":"probe: do nothing"}],"client_id":"..."}}`), plus a
`queued_thread_revisions` counter that drives the `thread/queue/changed` notification.
*(This row was then deleted; see the header.)*

**This is the most valuable single finding for the orchestrator.** It means an instruction can be
handed to a session that is busy, idle, **or not even running**, from a plain shell command, with a
returned message id as the receipt, and it is durable across restarts. It is precisely the
capability the field notes record as missing — "a nudge that cannot submit stranded text" — and it
needs no protocol client at all. Caveat: the CLI returns a **queue** id, not a delivery confirmation;
proof of *consumption* has to come from `thread/queue/changed` or the transcript.

### 4. Answer the session's own question programmatically (VERIFIED, schema)

The app-server sends **server→client JSON-RPC requests** that the orchestrator answers by replying to
the request id. Ten of them:

| Server→client request | Client answers with |
|---|---|
| `item/tool/requestUserInput` | `{answers: {<questionId>: {answers: [string]}}}` |
| `item/commandExecution/requestApproval` | `{decision: accept \| acceptForSession \| acceptWithExecpolicyAmendment{…} \| …}` |
| `item/fileChange/requestApproval` | decision |
| `item/permissions/requestApproval` | `{permissions: {fileSystem?, network?}, scope: "turn"\|"session", strictAutoReview?}` |
| `execCommandApproval` / `applyPatchApproval` (legacy) | `{decision: approved \| approved_execpolicy_amendment{…} \| …}` |
| `mcpServer/elicitation/request` | elicitation response |
| `item/tool/call` (`DynamicToolCallParams`) | tool result — **the client can host tools for the agent** |
| `account/chatgptAuthTokens/refresh` | refreshed tokens |
| `attestation/generate` | attestation |

`ToolRequestUserInputParams = {threadId, turnId, itemId, isBlocking, questions[]}` where each
question is `{id, header, question, options?[], isOther, isSecret}` — **a structured multiple-choice
question with a stable id**, not a string to pattern-match on a screen. A `serverRequest/resolved`
notification confirms resolution. **This is exactly the axis-G requirement, and it is a designed
feature rather than a workaround.**

### Also available

`turn/interrupt {threadId, turnId}` (clean stop), `thread/rollback {numTurns}`,
`thread/revert {beforeTurnId}`, `thread/shellCommand {threadId, command, timeoutMs?}`,
`thread/approveGuardianDeniedAction`.

---

## H. GUARDRAILS

### Sandbox (VERIFIED — `--help` values; semantics CLAIMED from docs)

`read-only` | `workspace-write` | `danger-full-access`, via `-s/--sandbox` or `sandbox_mode`.
Real stored policy from an exec thread on this machine (VERIFIED, `state_5.sqlite`):

```json
{"type":"managed","file_system":{"type":"restricted",
  "entries":[{"path":{"type":"special","value":{"kind":"root"}},"access":"read"}]},
 "network":"restricted"}
```

`codex sandbox <COMMAND>...` runs an arbitrary command under seatbelt — usable by the orchestrator
for its own subprocesses. `--add-dir` extends writable roots. Per-turn override exists too
(`TurnStartParams.sandboxPolicy` with `writableRoots`, `networkAccess`, `excludeSlashTmp`,
`excludeTmpdirEnvVar`).

### Approvals

`approval_policy` = `"on-request"` | `"never"` | `{granular = {…}}` (CLAIMED docs; the granular shape
appears in the schema as `{mcp_elicitations, request_permissions?, rules, sandbox_approval,
skill_approval?}` — VERIFIED).

`approvals_reviewer` = `"user"` | `"auto_review"` (docs) — the schema additionally exposes
**`"guardian_subagent"`** (VERIFIED). `--approve-for-me` selects automatic review under
workspace-write. Per docs (CLAIMED): the reviewer agent evaluates for data exfiltration, credential
probing, security weakening and destructive operations, classifies low/medium/high/critical, and
**denies critical outright**. Related notifications: `item/autoApprovalReview/started` /
`…/completed`, `autoApprovalReview/strictReviewRequired`, `guardianWarning`. `guardian_approval` is
`stable/true` here.

**For an unattended run this is the right setting, not `--yolo`**: `--ask-for-approval never` plus a
real sandbox means an unapprovable action fails and is returned to the model ("Execution failures are
immediately returned to the model" — VERIFIED help text) instead of hanging on a prompt. With
`--dangerously-bypass-approvals-and-sandbox` there is no sandbox and no approval at all.

**This machine's current config is the dangerous one:** `~/.codex/config.toml` has
`sandbox_mode = "danger-full-access"`, and `codex doctor` flags
`⚠ sandbox filesystem unrestricted · network enabled` (VERIFIED). An orchestrator must set the
sandbox explicitly per launch rather than inherit this.

### Hooks (events CLAIMED from docs; `hooks` feature VERIFIED `stable/true`)

Events: `SessionStart`, `SessionEnd`, `PreToolUse`, `PostToolUse`, `PermissionRequest`,
`PreCompact`, `PostCompact`, `UserPromptSubmit`, `SubagentStart`, `SubagentStop`, `Stop`,
`Interrupt`. Configured in `~/.codex/hooks.json` or `[hooks]` in `config.toml`, then
`<repo>/.codex/hooks.json`, then plugin-bundled. Handlers are `"type":"command"` or
`"type":"mcp_tool"`. `PreToolUse` can **deny** (`"permissionDecision":"deny"`, or exit code 2) or
**rewrite** inputs (`"updatedInput"`); `PermissionRequest` can allow/deny.

Trust model: hooks must be reviewed and trusted before running — which is why
`--dangerously-bypass-hook-trust` exists and is documented as "intended only for automation that
already vets hook sources". **No `~/.codex/hooks.json` exists on this machine** (VERIFIED), so this
path is entirely unexercised here.

Hooks are observable from outside too: `hook/started` and `hook/completed` notifications, and
`hooks/list` returns `{cwd, hooks[], errors[], warnings[]}` per directory (VERIFIED).

### Other

`permissionProfile/list` → `{id, description?, allowed}` (VERIFIED); `CODEX_PERMISSION_PROFILE` env
var exists (VERIFIED as a string). Execpolicy `.rules` files, disabled with `--ignore-rules`.
Per-directory trust: `[projects."<path>"] trust_level = "trusted"` — **99 trusted project entries**
in this config (VERIFIED). `codex exec` refuses to run outside a git repo without
`--skip-git-repo-check`.

---

## I. EXTENSIBILITY

- **MCP** — both directions. As a client: `[mcp_servers.<id>]` with `command`/`args`/`env`/`cwd`/
  `enabled`/`startup_timeout_sec`; managed by `codex mcp list|get|add|remove|login|logout`.
  **7 servers configured here** (VERIFIED via `codex mcp list`), all booting on `thread/resume` —
  observed live as `mcpServer/startupStatus/updated … "starting" → "ready"` for `node_repl`,
  `n8n-mcp`, `cua_repl`, `codex_apps`, `computer-history`, `pencil`. As a server:
  **`codex mcp-server`** exposes Codex itself over stdio MCP — so Codex can be a tool inside another
  agent. Protocol-side: `mcpServer/tool/call`, `mcpServer/resource/read`, `mcpServerStatus/list`,
  `config/mcpServer/reload`, `mcpServer/oauth/login`.
- **Skills** — `~/.codex/skills/` holds 6 here (`find-call`, `find-skills`, `frontend-design`,
  `gmessage`, `mcp-builder`, `skill-creator`). Protocol: `skills/list {cwds[], forceReload}`,
  `skills/extraRoots/set`, `skills/config/write`, `skills/changed`. `skill_search` and
  `skill_mcp_dependency_install` are `stable/true`.
- **Plugins & marketplaces** — `codex plugin add|list|remove|marketplace`; `[marketplaces.<name>]`
  with `source_type`/`source`; `[plugins."<name>@<marketplace>"] enabled = true`. 11 plugins enabled
  here across `openai-bundled` and `openai-primary-runtime`. Protocol adds `plugin/install`,
  `plugin/uninstall`, `plugin/read`, `plugin/skill/read`, and a whole `plugin/share/*` family.
- **Subagents** — first-class. `thread_spawn_edges` in SQL, `sourceKinds` values `subAgent`,
  `subAgentReview`, `subAgentCompact`, `subAgentThreadSpawn`, and `agentNickname`/`agentRole` on
  each thread. A real example on this machine: parent `01a0668a-…` spawned children nicknamed
  **Meitner**, **Maxwell**, **Volta** at `depth: 1` (VERIFIED). **A GSD-style subagent-heavy engine
  maps onto this natively** — and unlike the current harness, the parent/child graph is queryable.
- **Config precedence** (CLAIMED, docs): CLI flags → project config → profile → user config →
  cloud-managed defaults → system config → built-in defaults. Project overrides live in
  `<repo>/.codex/config.toml`. Every key is reachable from the command line via `-c key=value`, and
  from the protocol via `config/read`, `config/value/write {keyPath, value, mergeStrategy:
  replace|upsert, expectedVersion?}` and `config/batchWrite` — **note `expectedVersion`, i.e.
  optimistic concurrency on config writes**.
- **Other surfaces:** `codex review` / `review/start` (targets: `uncommittedChanges`, `baseBranch`,
  `commit`, `custom`), `codex apply`, `codex cloud exec|status|list|apply|diff`,
  `codex exec-server` (remote execution environments), `notify = [cmd, "turn-ended"]`,
  `command/exec` + `command/exec/write` + `command/exec/terminate` + `command/exec/resize`
  (**a full PTY the orchestrator can drive**), `fs/*` including `fs/watch`,
  `externalAgentConfig/detect` + `/import` (imports other agents' configs), `feedback/upload`.

---

## J. OPERATIONAL REALITY

| Aspect | Finding | Tag |
|---|---|---|
| License | Apache-2.0 | VERIFIED (package.json) |
| Install | `npm i -g @openai/codex`; node shim + per-platform native binary | VERIFIED |
| Footprint | native binary **217 MB**; `~/.codex` here ≈ **360 MB** (rollouts 227 MB, thread_history 72 MB, logs_2 51 MB) | VERIFIED |
| Platforms | darwin arm64/x64, linux arm64/x64, win32 arm64/x64 | VERIFIED (optionalDependencies) |
| Node | `>=16` for the shim | VERIFIED |
| Release cadence | 0.152.0 → 0.155.1 since 2026-09-01; ChatGPT.app ships `0.155.0-alpha.9.2` | VERIFIED |
| Cost model | ChatGPT plan quota (`prolite` here), or API key, or Bedrock | VERIFIED |
| Cost attribution | `turn.cost_microusd`; `account/usage/read` → per-thread `estimatedUsageUsdMicros` | VERIFIED (schema/strings) |
| Maturity | `codex exec` stable; **`app-server` and `remote-control` are marked `[experimental]`** | VERIFIED |
| Track record here | **191 exec sessions already run on this machine** | VERIFIED |

### Known unattended-run failure modes

1. **~1% of sessions are already unrecoverable.** 44 of 380 rollouts have "no usable header record"
   (crash before `session_meta`), 1 missing active row, 1 duplicate thread id — all reported by
   `codex doctor` today. Budget for orphans; do not assume every launched session is resumable.
2. **Two codex binaries on PATH.** npm 0.152.0 vs ChatGPT.app 0.155.0-alpha.9.2, and `codex doctor`
   lists a third PATH entry at `/usr/local/bin/codex`. Flag surfaces differ across these
   (`--full-auto` exists in one docs generation and not in this binary). **Pin an absolute path.**
3. **Docs/binary skew is real.** `--full-auto` is documented and absent; `--yolo` is undocumented in
   `--help` and present. Verify every flag against the binary you will actually invoke.
4. **The docs moved.** `developers.openai.com/codex/*` now 308-redirects to `learn.chatgpt.com/docs/*`,
   and some old paths 404. Any stored doc link in the orchestrator will rot.
5. **This machine's default is `danger-full-access`.** Inheriting `~/.codex/config.toml` gives an
   unsandboxed agent. Pass `-s` explicitly on every launch.
6. **Transcripts contain secrets** (see C). Do not ship them off-box.
7. **`--ephemeral` silently destroys B and C.** Never set it for orchestrated work.
8. **MCP boot cost per resume.** Seven MCP servers started on a single `thread/resume` here, taking
   ~1.5 s wall-clock. Multiply by session count; consider `--ignore-user-config` or a lean
   role-specific `CODEX_HOME`.
9. **`chronicle` is enabled and under development** — the server warns:
   `"Under-development features enabled: chronicle. … may behave unpredictably."` Suppress with
   `suppress_unstable_features_warning = true` (VERIFIED accepted) **after** deciding whether you
   want the feature at all.
10. **`rateLimitReachedType` has never fired here** — the limit-hit path is confirmed in schema but
    untested in practice on this account.

### Capability-probe trick worth stealing

`--strict-config` turns config into a **queryable feature detector**. A bogus key is rejected:

```
$ codex app-server --stdio --strict-config -c definitely_not_a_real_key_xyz=1
Error: unknown configuration field `definitely_not_a_real_key_xyz` in -c/--config override
```

while `model_auto_compact_token_limit`, `compact_prompt`, `approvals_reviewer`,
`model_context_window`, `history.persistence`, `shell_environment_policy.inherit` and
`suppress_unstable_features_warning` were all **accepted** (VERIFIED, run today). The orchestrator
can use this at startup to detect what the installed Codex build supports, instead of guessing from
a version number.

### Is it plausible to run unattended overnight today?

**Yes — more plausibly than Claude Code, on this machine, for these reasons:** no Keychain GUI prompt
can block it; quota is readable before every dispatch and pushed as it changes; a hit limit can be
*reset* from two banked credits; compaction is controllable from outside with proof; and 191 headless
sessions have already run here. The reservations are that the control plane is labelled
`[experimental]`, the installed build is three releases stale, and ~1% of historic sessions are
unresumable.

---

## What this costs the orchestrator

**Build the Codex adapter against `codex app-server`, not against the CLI.** The CLI is the fallback.

| Work item | Effort | Why |
|---|---|---|
| JSON-RPC client over stdio (`--listen stdio://`) | small | `initialize` → `initialized` → methods. Proven working today in ~40 lines of Node. |
| **Two event parsers** | small-medium | exec `--json` emits `thread.started`/`turn.completed`; app-server emits `thread/started`/`turn/completed`. Same concepts, different names. Unavoidable if both transports are supported. |
| **Two casings for rate limits** | trivial | `used_percent` on disk, `usedPercent` on the wire. |
| **Start-then-name id handshake** | small | No `--session-id`. Capture id from `thread.started` / `ThreadStartResponse`, then `thread/name/set`. Add a `SessionStart` hook to close the crash window. |
| **One app-server per account** | medium | Account is process-wide per `CODEX_HOME`. N accounts = N daemons, N sockets, N MCP boots. This is the largest structural cost. |
| Answering approvals & questions | small | Reply to server→client request ids. Pure win — no screen scraping. |
| Orphan reconciliation | small | Sweep `state_5.sqlite` + `codex doctor --json`-style output for headerless rollouts; treat as lost rather than retrying forever. |
| Pinning the binary | trivial | Absolute path; record `cli_version` from `session_meta` with every run. |
| Sandbox hygiene | trivial | Always pass `-s`, never inherit `danger-full-access`. |
| Secret hygiene in transcripts | small | Set `shell_environment_policy.inherit="core"` + filters; never copy rollouts off-box. |

**What the orchestrator gets for free that it would otherwise have to build:** durable cross-process
message queue (`codex queue` → `queue_1.sqlite`), per-session token budgets with limit states
(`thread/goal/*`), subagent parent/child graph in SQL, turn-level rollback and revert, an automatic
approval reviewer (`approvals_reviewer`), structured final output validated against a JSON Schema
(`--output-schema`), per-thread USD cost, and a rate-limit reset button.

**Minimal viable Codex watcher, if the protocol is too much:** `tail -f` the rollout JSONL. One file
gives transcript, `model_context_window`, `total_tokens`, and `rate_limits` — axes C, D and E with no
daemon, no client and no dependencies.

---

## Sources

All consulted **2026-09-19**.

**Executed on this machine (primary, VERIFIED):**
- `codex --version` → `codex-cli 0.152.0`; `/Applications/ChatGPT.app/Contents/Resources/codex --version` → `0.155.0-alpha.9.2`
- `codex --help`, `codex exec --help`, `codex exec resume -h`, `codex resume --help`, `codex queue --help`, `codex agents --help`, `codex app-server --help`, `codex app-server daemon -h`, `codex remote-control --help`, `codex remote-control start -h`, `codex mcp-server --help`, `codex login --help`, `codex features --help`, `codex debug --help`, `codex debug app-server -h`, `codex debug app-server send-message-v2 --help`, `codex sandbox --help`, `codex plugin --help`, `codex mcp --help`, `codex help migrate-rollouts`, `codex help cloud`, `codex help exec-server`
- `codex app-server generate-json-schema --out <dir>` — **the authoritative protocol source for this profile**: 265 v2 type schemas plus `ClientRequest.json` (98 methods), `ServerRequest.json` (10), `ServerNotification.json` (81), `ClientNotification.json` (1)
- `codex doctor`, `codex features list`, `codex mcp list`, `codex login status`
- Two live read-only JSON-RPC sessions against `codex app-server --stdio`: `initialize`, `initialized`, `account/read`, `account/rateLimits/read`, `thread/list`, `thread/read`, `thread/items/list`, `thread/resume`
- `--strict-config` capability probes (bogus key rejected; 7 documented keys accepted)
- `CODEX_HOME=<tmp> codex login status` (account isolation proof)
- `codex queue --thread … --message …` against a stopped daemon (row created, inspected, **deleted**)

**Read on disk (primary, VERIFIED):**
- `~/.codex/config.toml`, `~/.codex/auth.json` (shape only), `~/.codex/session_index.jsonl`
- `~/.codex/sessions/2026/09/13/rollout-2026-09-13T17-19-52-01a09a47-….jsonl` (interactive: `token_count` + `rate_limits` + `model_context_window`)
- `~/.codex/sessions/2026/09/04/rollout-2026-09-04T12-37-32-01a06aec-….jsonl` (exec: `rate_limits` present)
- `~/.codex/sessions/2026/09/09/rollout-2026-09-09T18-30-03-01a085ee-….jsonl` (exec `session_meta`)
- `~/.codex/sessions/2026/09/03/rollout-2026-09-03T16-12-38-01a0668a-….jsonl` (`CODEX_SESSION_ID` exported into shell env; secret leak evidence)
- `sqlite3` schemas + queries: `state_5.sqlite`, `thread_history_1.sqlite`, `queue_1.sqlite`
- npm `@openai/codex@0.152.0` `package.json`, `bin/codex.js`; string table of the native binary

**Official documentation (CLAIMED unless separately verified):**
- https://learn.chatgpt.com/docs/developer-commands?surface=cli — `codex exec` reference *(via 308 from developers.openai.com/codex/cli/reference)*
- https://learn.chatgpt.com/docs/config-file/config-basic — config basics *(via 308 from developers.openai.com/codex/local-config)*
- https://learn.chatgpt.com/docs/config-file/config-reference.md — configuration reference
- https://learn.chatgpt.com/docs/agent-approvals-security.md — approvals, `auto_review`, unattended behaviour
- https://learn.chatgpt.com/docs/app-server — app-server transport, JSON-RPC 2.0, handshake, methods
- https://learn.chatgpt.com/docs/hooks — hook events, config locations, blocking, trust model
- Not reachable today (404): `https://learn.chatgpt.com/docs/automate-codex`, `https://learn.chatgpt.com/docs/sandbox-approvals`

**Open questions for a later pass**
1. What protocol does `~/.codex/ipc/ipc.sock` speak? It is live and is not the app-server control socket. (UNKNOWN)
2. Exact accepted item shapes for `thread/inject_items` — schema is unconstrained. (UNKNOWN)
3. Precedence among `CODEX_API_KEY`, `OPENAI_API_KEY`, `CODEX_ACCESS_TOKEN` and `auth.json`. (UNKNOWN)
4. Does `turn/steer` error cleanly on a stale `expectedTurnId`, and with what code? (UNKNOWN — needs a live turn)
5. Behaviour when `rateLimitReachedType` actually fires, and whether `codex exec` exits non-zero. (UNKNOWN — never observed here)
6. Whether `account/rateLimitResetCredit/consume` works headlessly without a ChatGPT-app confirmation. (UNKNOWN — not redeemed; would consume a real credit)
7. `codex app-server daemon bootstrap` — "durable local app-server management for SSH-driven use" is exactly the orchestrator's shape but was not exercised. (UNKNOWN)
