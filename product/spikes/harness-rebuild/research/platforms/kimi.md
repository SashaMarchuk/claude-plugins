# Moonshot Kimi — platform profile for a provider-agnostic orchestrator

**Date of research:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0).
**Scope:** Kimi as an *agent platform to be driven*, measured against contract axes A–J.
Orchestrator tooling itself is out of scope (see `../../context/orchestrator-landscape.md`).

**Evidence tags**
- **VERIFIED** — read in the project's own source, read in official docs, or run on this machine.
- **CLAIMED** — asserted by marketing, a README, or a secondary source; not independently confirmed.
- **UNKNOWN** — could not be established in this pass.

---

## 0. Name resolution — "Kimi" is three different things, and two of them are CLIs

This is the first finding, and it changes the shape of every other answer. The open question the
field scan left (`00-field-scan.md` §6, question 6) resolves as follows:

| Thing | What it is | State on 2026-09-19 | Tag |
|---|---|---|---|
| **Kimi Code CLI (`kimi-code`)** | Node/TypeScript agent CLI, binary `kimi`, npm `@moonshot-ai/kimi-code`, repo `MoonshotAI/kimi-code`, MIT | **`2.0.2`, published 2026-09-19T12:16:26Z** (today). 7,499 stars, repo pushed today. **This is the live product.** | VERIFIED (npm registry + GitHub API + run locally) |
| **Kimi CLI (`kimi-cli`)** | *Legacy* Python agent CLI, also binary `kimi`, PyPI `kimi-cli`, repo `MoonshotAI/kimi-cli`, Apache-2.0 | `1.50.0`, last published **2026-09-01**; repo last pushed 2026-09-01; 11,404 stars. Its own README says: *"Kimi CLI is evolving into Kimi Code CLI … This project will be gradually wound down."* | VERIFIED (PyPI JSON + wheel METADATA + GitHub API) |
| **Kimi the model / API** | `kimi-k3`, `kimi-k2.7-code`, … served from `api.moonshot.ai` (OpenAI + Anthropic protocols) and, for plan holders, `api.kimi.com` / `api.kimi.ai` `/coding/v1` | current | VERIFIED (platform docs + models.dev) |

**Two data roots, two CLIs, one binary name.** Legacy Python data lives in `~/.kimi/`; Kimi Code
lives in `~/.kimi-code/`. `kimi migrate` copies config, MCP config, input history and chosen
sessions across, **never** OAuth credentials or MCP authorizations, and never deletes the old data
(VERIFIED, `docs/en/guides/migration.md`).

**A trap for any orchestrator that scripts "kimi":** the two CLIs disagree on `-c`.
In legacy Python `kimi-cli`, `-c` is an alias for `--command` / `--prompt`. In `kimi-code`, `-c` is
`--continue`. A script written against one silently does the wrong thing against the other.
(VERIFIED — read in `kimi_cli/cli/__init__.py` and `apps/kimi-code/src/cli/commands.ts`.)

**Everything below describes `kimi-code` 2.0.2 unless a row says "legacy".**

### Installed here?

**No.** `which kimi`, `which kimi-cli` → not found. No `~/.kimi`, no `~/.kimi-code`, no
`~/.config/kimi*`. No `KIMI_*` / `MOONSHOT_*` environment variables. No Kimi alias in `~/.zshrc`
(contrast `claude-mimo`, which is wired up). (VERIFIED, read-only probe 2026-09-19.)

For this research I installed `@moonshot-ai/kimi-code@2.0.2` into an **isolated sandbox**
(`<scratchpad>/kimi/sandbox`, its own `node_modules`, `KIMI_CODE_HOME` pointed at a scratch
directory, `KIMI_DISABLE_TELEMETRY=1`, `KIMI_CODE_NO_AUTO_UPDATE=1`), ran it, exercised its local
server API, then shut it down. **Nothing of the owner's was read or modified, no login was
performed, and no model call ever succeeded — so no quota was spent.** Node 22.18.0 on this machine
is *below* kimi-code's `engines.node >= 22.19.0`; I used the nvm-installed `v24.18.0`.

### The headline

Kimi Code 2.0 ships a **documented, authenticated, machine-readable local control plane** —
`kimi web` exposes **105 REST paths / 126 operations** under `/api/v1` and `/api/v2`, an OpenAPI
3.0.3 document at `/openapi.json`, a WebSocket event stream at `/api/v1/ws` with an AsyncAPI 3.1.0
document at `/asyncapi.json` (VERIFIED — counted from the live spec served by the sandbox instance).
That control plane answers, as first-class endpoints, four of the five axes the owner called
non-negotiable: read remaining quota, read context fullness, trigger compaction from outside, and
answer a session's own question programmatically.

**On the orchestrator contract, Kimi Code is the strongest platform surfaced so far — stronger
than pi's `--mode rpc`, because it is an addressable, stateful, multi-session HTTP/WS control plane
rather than one pipe per process.** Its weaknesses are narrow and specific: it will not let the
orchestrator *name* a session before it exists, and the whole thing is two days old.

---

## A. LAUNCH

### Headless / non-interactive

`kimi -p <prompt>` (long form `--prompt`). Output format is `--output-format text|stream-json`
(VERIFIED by `kimi --help` run on this machine, and in `apps/kimi-code/src/cli/commands.ts`).

```sh
kimi -p "Summarize the current repository status"
kimi -p "List changed files" --output-format stream-json
kimi -m kimi-code/kimi-for-coding -p "Explain the latest diff"
```

In `stream-json` mode **each line on stdout is a JSON object**. Assistant text goes to stdout;
thinking content, tool progress and "resuming session" notices go to **stderr**. Thinking content is
never written to the JSONL. (VERIFIED, `docs/en/reference/kimi-command.md`.)

Undocumented but real: **`KIMI_MODEL_OUTPUT_FORMAT`** sets the default `-p` output format when the
flag is absent; an invalid value fails fast. It is ignored outside prompt mode. (VERIFIED —
`apps/kimi-code/src/cli/options.ts`, constant `OUTPUT_FORMAT_ENV`. It is **not** in
`docs/en/configuration/env-vars.md`.)

### Flag conflicts — verified by running them

These are validated *before* anything else happens, in `validateOptions()`:

```
$ kimi -p "hello" --auto     → error: Cannot combine --prompt with --auto.
$ kimi -p "hello" --yolo     → error: Cannot combine --prompt with --yolo.
```

(VERIFIED by execution on this machine, and in
`apps/kimi-code/src/cli/options.ts`.)

> **Documentation bug worth knowing.** `docs/en/configuration/overrides.md` advertises
> `kimi --yolo -p "Batch rename the following files..."` under "Skip approval for batch tasks".
> That command **cannot run** — it is rejected at startup. `kimi-command.md` states the rule
> correctly. Do not build a launcher from the `overrides.md` example.

`-p` **is** combinable with `--continue` and with `--session <id>`; only a bare `--session` with no
id is rejected in prompt mode (`'Cannot use --session without an id in prompt mode.'`).
(VERIFIED in source and by running `kimi -p "hello" -c`, which proceeded past validation to
`error: failed to run prompt: No model configured.`)

**In `-p` mode no human approval is ever requested — regular tool calls run under the `auto`
permission policy, while static deny rules remain in effect.** (VERIFIED, `kimi-command.md`.)

### Visible terminal the owner can attach to and type into

Yes — plain `kimi` is a full TUI. While it streams, the input box stays live: **`Ctrl-S` injects the
text in the input box into the *running* turn** without waiting for it to finish; `Esc`/`Ctrl-C`
interrupts the turn (VERIFIED, `docs/en/guides/interaction.md`). There is also `!` shell mode, whose
output is written into the conversation context.

The orchestrator does not have to choose between "headless" and "attachable", which is the usual
trade: `kimi web` (below) serves a browser UI over the *same* sessions and the *same* data, so a
session driven by the API can be opened and typed into by a human at any time, and vice versa.

### The third launch mode — the local server

```sh
kimi web                 # foreground, REST + WebSocket + web UI on one origin
kimi web --no-open --port 58628 --log-level info
```

Verified options (from `kimi web --help`, run here): `--port <port>` (default `58627`, `+1` on a busy
port, up to 100 retries), `--host [host]` (omit → `127.0.0.1`; bare `--host` → `0.0.0.0`),
`--allowed-host <host...>`, `--insecure-no-tls`, `--allow-remote-shutdown`,
`--dangerous-bypass-auth`, `--log-level <level>`, `--debug-endpoints`, `--web-title <title>`,
`--rc, --remote-control`, `--no-open`. Sub-command `kimi web rotate-token`.

**Multiple instances share one home directory**, each registering itself under
`$KIMI_CODE_HOME/server/instances/<server_id>.json`. I read a live one:

```json
{"server_id":"01M2WX8VRD6H7Y81JDBKXSK8TY","pid":85118,"host":"127.0.0.1","port":58700,
 "started_at":1789824102157,"heartbeat_at":1789824102408,"host_version":"2.0.2"}
```

That file is a supervisor's discovery primitive: pid, port, host, version, and a **heartbeat
timestamp** it can watch for liveness. Stale entries are swept on next start. (VERIFIED — file read
from the sandbox; `packages/kap-server/src/instanceRegistry.ts`.)

> **Caveat, observed.** The `server_id` in the registry file (`01M2WX8VRD…`) is **not** the
> `server_id` returned by `GET /api/v1/meta` (`01M2WX8VXS…`) for the same process. Do not join those
> two by id — join by `pid` or by `port`. (VERIFIED by observation; cause UNKNOWN.)

### Remote control

`kimi rc` (alias `kimi remote`, or `kimi web --remote-control`, or `/rc` inside a session) exposes
the same web UI through a Moonshot relay at `https://code-rc.kimi.com/devices/<device-id>/`,
authenticated by logging into the same Kimi account. **Requires a paid membership.** One instance
per machine; single-instance lock at `~/.kimi-code/server/rc.json` recording pid and URL. Device
limit ≈ **3 devices per account**. Cannot be combined with `--dangerous-bypass-auth`; binds loopback
only and relays out. (VERIFIED, `docs/en/guides/remote-control.md`.) The device id derives from the
data directory, so the URL is stable across restarts.

### ACP

`kimi acp` speaks the **Agent Client Protocol** as JSON-RPC over stdin/stdout. Options:
`--login`, `--region <mainland-cn|global>` (VERIFIED by `kimi acp --help` run here).
Capability matrix and per-method coverage in §G.

---

## B. IDENTITY & RESUME

### What works

| Capability | How | Tag |
|---|---|---|
| Resume a specific session | `kimi --session <id>` / `-S <id>`; hidden alias `-r`/`--resume [id]` | VERIFIED (source + `--help`) |
| Resume the latest session for this cwd | `kimi --continue` / `-c` (hidden `-C`) | VERIFIED |
| Resume **inside** `-p` | `kimi -p "…" --session <id>` and `kimi -p "…" -c` both legal | VERIFIED (source + run) |
| Enumerate sessions from the shell, as JSON | `kimi session list --json [--all] [--archived] [--limit n] [--cwd path]` | VERIFIED (`kimi session list --help` run here; returns `[]` in a clean home) |
| Enumerate over the API | `GET /api/v1/sessions` (cursor paging, `busy` / `archived_only` / `exclude_empty` / `workspace_id` filters), plus `GET /api/v2/sessions` with `page_token` or stateless `page` | VERIFIED (live) |
| Fork a session | `kimi fork [sessionId] [-y]`, `POST /api/v1/sessions/{id}:fork`, ACP `session/fork`, `/fork` in the TUI | VERIFIED (ran `:fork` live; got a new session id) |
| Override the resumed session's mode | `kimi --continue --auto` etc. | VERIFIED (docs) |

Neither `kimi session list` nor `kimi fork` appear in `docs/en/reference/kimi-command.md` —
they are real, and verified by running `--help` on the binary.

### The gap: the orchestrator cannot name a session before it exists

There is **no `--session-id <id>` that creates**. `--session [id]` only *resumes*; an unknown id is
not created. `POST /api/v1/sessions` does not accept a client-chosen id — it returns a server-minted
`session_<uuid4>`. This is the one place pi is cleaner (`--session-id <id>` — "use exact project
session ID, creating it if missing").

**The workaround, and its exact cost — tested, and it has a trap.**

`POST /api/v1/sessions` accepts a `metadata` object. **It silently drops every key except `cwd`.**
I created a session with `{"metadata":{"cwd":"…","orchestrator_task":"T-42"}}` and the response
carried only `cwd`. (VERIFIED by observation.)

But `POST /api/v1/sessions/{id}/profile` **does** persist arbitrary metadata, and it survives to
disk and back out through the list endpoint:

```sh
curl -X POST .../api/v1/sessions/$SID/profile -d '{"metadata":{"orchestrator_task":"T-42"},"title":"probe2"}'
# → metadata {'orchestrator_task': 'T-42', 'cwd': '…'}
```

and in `state.json` on disk:

```json
{"id":"session_00062ebf-…","version":2,"cwd":"…","createdAt":1789824123455,"updatedAt":1789824132792,
 "archived":false,"agents":{"main":{"homedir":"…/agents/main","type":"main"}},
 "custom":{"orchestrator_task":"T-42"},"title":"probe2","titleKind":"custom","isCustomTitle":true}
```

(VERIFIED — both the API round-trip and the on-disk file, read from the sandbox.)

**So the correlation pattern is: create → immediately `POST /profile` with your own id → thereafter
address the session by the server's id, and recover your id from `metadata.orchestrator_task` after
a crash.** The cost is one extra round trip and a window (between create and profile) in which a
crash leaves an untagged session. There is no server-side metadata *filter* on the list endpoints
(UNKNOWN whether `/api/v1/search` can reach `custom` metadata), so recovery means listing and
scanning client-side.

`title` **is** settable at creation and is a second, weaker correlation channel.

### What survives a crash, a reboot, a provider outage

**Everything that matters is on disk, continuously.** Layout (VERIFIED — read from the sandbox and
`docs/en/configuration/data-locations.md`):

```
$KIMI_CODE_HOME (default ~/.kimi-code)
├── session_index.jsonl        # one line per session: {"sessionId","sessionDir","workDir"}
├── sessions/<workDirKey>/<sessionId>/
│   ├── state.json             # id, cwd, createdAt/updatedAt, archived, title, custom{…}, forkedFrom
│   ├── agents/main/wire.jsonl # the event stream — see §C
│   ├── agents/<subagentId>/wire.jsonl
│   ├── agents/main/plans/<id>.md
│   ├── tasks/<task_id>.json + tasks/<task_id>/output.log
│   ├── cron/                  # reloaded into the scheduler on `kimi --session`
│   ├── upcoming-goals.json
│   └── notify/state.json      # (present on disk; undocumented)
├── credentials/<name>.json    # dir 0700, files 0600, atomic tmp→fsync→rename
├── server.token               # 0600, the bearer token for the local API
└── server/instances/<id>.json # live server registry (see §A)
```

`workDirKey` is `wd_<slug>_<first-12-hex-of-sha256(workDir)>` — I observed `wd_sandbox_587409df3f3d`
(VERIFIED). `session_index.jsonl` is exactly the three fields shown.

**Provider outage:** `[loop_control] max_attempts_per_step` (default **10**) retries transient
failures — connection errors, timeouts, HTTP 429 rate limits, 5xx. `KIMI_CODE_INFINITE_RETRY`
retries indefinitely with exponential backoff capped at 32 s, honoring `Retry-After`; an abort still
cancels immediately. **A 429 caused by exhausted quota or insufficient balance is not retried and
fails immediately** (VERIFIED, `config-files.md` §`loop_control`) — which is exactly the signal an
orchestrator wants, rather than a silent stall.

**Reboot:** the docs explicitly warn *"Do not manually edit files inside the `sessions/` directory —
doing so may prevent sessions from being restored correctly."* Reading is fine; writing is not.

---

## C. TRANSCRIPT

**Three surfaces, all usable live. This is the best-answered axis on the platform.**

### 1. On disk — `agents/<agentId>/wire.jsonl`

JSONL, one typed record per line, appended as the session runs. I read a real one, produced by an
actual (failing) turn in the sandbox:

```
metadata                  {"protocol_version":"1.5","created_at":1789824123548}
runtime.set_binding       {"workspaceId":"wd_sandbox_587409df3f3d","runtimeId":"local","agentId":"main",…}
turn.prompt               {"agentId":"main","input":[{"type":"text","text":"hi"}],"origin":{"kind":"user"},
                           "promptId":"orch-0001","turnId":0,…}
context.append_message    {"agentId":"main","message":{"role":"user","content":[…],"id":"orch-0001",…}}
agent.message.appended    {…"meta":{"source":"input","promptId":"orch-0001","tracked":true,…}}
agent.turn.started        {"turnId":0,"queueItemId":"orch-0001",…}
plugin.session_start      {"agentId":"main",…}
context.append_loop_event {"event":{"type":"step.end","turnId":"0","step":1,"finishReason":"error"},…}
turn.step.interrupted     {"agentId":"main","turnId":0,"step":1,"reason":"error",
                           "message":"[model.not_configured] Model not set",…}
agent.turn.ended          {"turnId":0,"outcome":"failed",…}
turn.ended                {"agentId":"main","turnId":0,"reason":"failed",
                           "error":{"code":"model.not_configured","message":"Model not set",
                                    "name":"Error2","retryable":false},"durationMs":41,…}
token_counting.turn_recorded {"agentId":"main","turnId":0,"length":2,"tokens":60,…}
prompt.completed          {"agentId":"main","promptId":"orch-0001",
                           "finishedAt":"2026-09-19T13:22:19.220Z","reason":"failed",…}
```

(VERIFIED — this is the literal file, reformatted for width.)

Three things a supervisor gets for free from a `tail -f` on this file and nothing else:
**structured error codes with a `retryable` boolean**; **per-turn token counts**
(`token_counting.turn_recorded`); and **terminal prompt outcomes keyed by the orchestrator's own
`promptId`**. The file "also carries a request trace — the tool schemas, request parameters, and MCP
tool listings sent to the model" (docs). Each subagent gets its own file.

### 2. Over REST

| Endpoint | What it gives |
|---|---|
| `GET /api/v1/sessions/{id}/messages` | flattened history, cursor-paged, `role` filter. Reading it **resumes a cold session** |
| `GET /api/v1/sessions/{id}/transcript?agent_id=main` | structured per-agent transcript: turns + steps + frames, plus `tasks`/`interactions`/`attachments`/`todos`/`prompts`/`meta`/`agents`/`pending_interactions` unpaginated on every response, plus `seq` |
| `GET /api/v1/sessions/{id}/transcript/ops?since_seq=N` | op-batch catch-up from a bounded journal; `complete:false` ⇒ do a full refresh |
| `GET /api/v1/sessions/{id}/transcript/user-messages` | every turn-opening input, with `origin` distinguishing real user text from slash commands and **cron** fires |
| `GET /api/v1/sessions/{id}/transcript/plan` | plan content, path, offered options, and review outcome for each `ExitPlanMode` call |
| `GET /api/v1/sessions/{id}/snapshot` | atomic rebuild: session + newest 100 messages + in-flight turn + live subagents + **pending approvals and questions**, stamped `as_of_seq` and `epoch` |

(VERIFIED live — I called `/transcript?agent_id=main` and `/snapshot` against the sandbox; the
live `/transcript` response carries a `prompts` key the docs' field list omits.)

### 3. Over WebSocket — live tail

`ws://<host>:<port>/api/v1/ws`. On connect the server sends `server_hello`
(`{ws_connection_id, protocol_version: 2, max_event_buffer_size: 1000, capabilities}`). Control
frames documented in prose: `subscribe`, `unsubscribe`, `subscribe_v2`, `unsubscribe_v2`,
`client_hello`. **The live AsyncAPI document lists 28 message types** including `ping`/`pong`,
`abort`, `resync_required`, and a whole `terminal_*` family (`terminal_attach`, `terminal_input`,
`terminal_resize`, `terminal_close`, `terminal_detach` and their acks) that the prose control-frame
table does not mention (VERIFIED — read from the live `/asyncapi.json`; single channel
`kimiCodeWebSocket`).

Event families: turns (`turn.started`/`ended`/`step.*`), streaming (`assistant.delta`,
`thinking.delta` with an `offset`), tools (`tool.call.started`/`delta`, `tool.progress`,
`tool.result`), interactions (`event.approval.requested`/`resolved`,
`event.question.requested`/`answered`/`dismissed`), subagents, background tasks, and
`compaction.*`, `skill.activated`, `goal.updated`, `prompt.*`, `error`, `warning`.

**Durable vs volatile:** durable events carry a strictly increasing `seq`, are journaled, and can be
replayed via `cursors: {seq, epoch}` on resubscribe. Volatile events (`*.delta`, `tool.progress`,
`shell.*`) are marked `volatile: true` and are **never** replayed. Fall more than the 1000-event
buffer behind and you get `resync_required` → fetch `/snapshot`, resubscribe with the fresh cursor.
**The server never sends heartbeats and never disconnects an idle connection — keepalive and
reconnection are the client's job.** (VERIFIED, `server-api.md` §WebSocket.)

### 4. Human-facing

`kimi vis [sessionId] [--port N] [--host H] [--no-open]` starts a local visualizer that inspects a
session "as it unfolds". `kimi export [sessionId] -o out.zip [-y] [--no-include-global-log]` packages
a session directory. `/export-md` writes readable Markdown. (VERIFIED, `--help` + docs.)

---

## D. CONTEXT — **non-negotiable axis: supported, with proof**

### Read how full the window is

```
GET /api/v1/sessions/{session_id}/status
→ { busy, model?, thinking_level, permission, plan_mode, swarm_mode,
    context_tokens, max_context_tokens?, context_usage? }
```

`context_usage` is a **0–1 float**. Reading this endpoint **resumes the session if it is cold**.
(VERIFIED live; against a session with no model configured the response was
`{"busy":false,"thinking_level":"","permission":"manual","plan_mode":false,"swarm_mode":false,
"tower_mode":false,"context_tokens":0}` — note `max_context_tokens` and `context_usage` are **absent
until a model resolves**, and note the **undocumented `tower_mode` field**.)

`GET /api/v1/sessions/{id}/snapshot` additionally returns real `usage` totals
(`input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`, `context_tokens`),
where the plain session endpoints return zeros. Off-API, `token_counting.turn_recorded` in
`wire.jsonl` gives per-turn token counts, so **context fill is derivable from the transcript alone**
with no server running.

Which number is reported is configurable: `[token_counting] strategy` ∈
`measured+estimated` (default) / `measured` / `estimated`, overridable by
`KIMI_TOKEN_COUNTING_STRATEGY`. Internal logic — auto-compaction triggers, budgets, overflow backoff
— always uses both, regardless of this setting. (VERIFIED, `config-files.md`.)

> This is the axis the field notes record as unmeasurable in the current harness: *"nothing in the
> plugin measures a session's context window."* Kimi Code measures it and hands it over as a float.

### Trigger compaction from outside

```
POST /api/v1/sessions/{session_id}:compact     body: { "instruction": "<optional guidance>" }
```

Returns immediately; progress and completion arrive as `compaction.*` WebSocket events.
`40910` when a turn or another context change is active, or when there is nothing to compact.

I called it against an empty session and got exactly the documented refusal:

```json
{"code":40910,"msg":"No messages to compact in current history.", …}
```

(VERIFIED live — the endpoint is reachable and the error path is real.)

> **Shell trap, and I hit it.** In zsh, `"$B/api/v1/sessions/$SID:compact"` has `:c` eaten as a
> parameter modifier, producing a bogus path and a misleading `40001 unsupported action` from the
> server. Use `"${SID}"` with braces, or percent-encode the colon (`%3A`). A supervisor that builds
> these URLs in a shell **must** brace the variable.

### Proof that it happened — four independent channels

1. `compaction.*` WebSocket events.
2. Hooks **`PreCompact`** and **`PostCompact`**, whose matcher is literally `manual` or `auto` — so
   a hook script fires with the trigger reason and can write a receipt anywhere the orchestrator
   wants. (VERIFIED, `docs/en/customization/hooks.md`.)
3. `context_tokens` / `context_usage` dropping on the next `GET …/status`.
4. `POST …:undo` reporting `40911` with `{reason, requestedCount, undoableCount}` once a
   **compaction boundary** is in the way — i.e. compaction leaves a structural mark in the history.

That is a stronger proof surface than pi's single `CompactionEntry`.

### Automatic compaction, and tuning it

`[loop_control] reserved_context_size` — *"Number of tokens reserved for model output; automatic
compaction is triggered when the remaining context window falls below this value."*
`[loop_control] compaction_max_attempts` (default `5`) bounds a failing compaction request.
`[experimental] micro_compaction` (default `false`) trims older large tool results while preserving
recent conversation. (VERIFIED, `config-files.md`.)

**A custom-compaction hook in the Claude Code sense does not exist** — `PreCompact`'s return value
is *"completely ignored"* (VERIFIED, hooks doc). The orchestrator can *observe* and *trigger*
compaction, and can *steer its summary* with the `instruction` body field, but cannot replace the
compaction algorithm. The closest substitute for a real handoff is `POST …:fork` (branch and let the
parent go cold) or `:btw` (a read-only child agent for side questions that never touches the working
context).

Also relevant: **subagents have fully independent context windows**; only the final result enters the
main agent's context. `KIMI_CODE_SUBAGENT_SCOPE_CACHE_SIZE` (default 32) controls how many completed
subagent scopes stay resident.

---

## E. QUOTA — **non-negotiable axis: supported, two separate paths**

### Path 1 — the Kimi Code plan (OAuth / subscription), which is what the owner would use

```
GET /api/v1/oauth/usage?provider=managed:kimi-code
```

`data` is `{ kind: "ok", quota }` or `{ kind: "error", message, status? }`. **An upstream failure
does not fail the envelope — it comes back in-band.** I confirmed the error shape live on a
logged-out sandbox:

```json
{"code":0,"msg":"success",
 "data":{"kind":"error","message":"No token for \"kimi-code\". Run /login to authenticate."}, …}
```

On success, `quota` is:

```
{ usages: { limit5h?: {usedRatio, resetAt?},
            limit7d?: {usedRatio, resetAt?},
            monthTotal?: {usedRatio, resetAt?},
            monthCode?: {usedRatio, resetAt?} },
  extraUsage: null | { balanceCents, totalCents, monthlyChargeLimitEnabled,
                       monthlyChargeLimitCents, monthlyUsedCents, currency } }
```

`usedRatio` is a **0–1 float**; `resetAt` is an RFC3339 timestamp. Entries are optional — *clients
render whichever entries are present*. (VERIFIED — `server-api.md` **and** the Zod schemas in
`packages/oauth/src/managed-usage.ts`.)

**The orchestrator does not need `kimi web` running to read this.** The CLI fetches it directly:

```
GET  https://api.kimi.com/coding/v1/usages      (mainland-cn, default)
GET  https://api.kimi.ai/coding/v1/usages       (global)
Header: Authorization: Bearer <access token>, Accept: application/json
```

overridable with `KIMI_CODE_BASE_URL`; 8-second client timeout. Wire keys are snake_case and are
remapped: `usages.limit_5h` → `limit5h`, `limit_7d` → `limit7d`, `limit_month_total` → `monthTotal`,
`limit_month_code` → `monthCode`; each entry's `used_ratio` → `usedRatio` and **`reset_time` →
`resetAt`**; `boosterWallet` → `extraUsage`. HTTP 401 ⇒ *"Authorization failed"*; **HTTP 404 ⇒
*"Usage endpoint not available. Try Kimi For Coding."*** — i.e. the endpoint is scoped to the coding
plan, not to every account. (VERIFIED — `packages/oauth/src/managed-usage.ts`, functions
`kimiCodeUsageUrl()` / `fetchManagedUsage()` / `parseQuotaUsages()`.)

The access token lives in `$KIMI_CODE_HOME/credentials/<name>.json`, dir `0700`, files `0600`,
written atomically (tmp → fsync → rename). **On disk, not in the macOS Keychain** — which means an
unattended run will *not* hit the Keychain-prompt failure mode that the field scan flags for Claude
Code profiles. (VERIFIED, `packages/oauth/src/storage.ts`.)

This is a near-exact structural match for the `five_hour.utilization` / `seven_day.utilization` /
`resets_at` triple the owner's existing `claude-limits` helper already parses — the same watcher
logic ports over with a field rename.

### Path 2 — a Moonshot Open Platform API key (pay-as-you-go)

```
GET https://api.moonshot.ai/v1/users/me/balance
Header: Authorization: Bearer {api_key}
→ {"code":0,"data":{"available_balance":49.58894,"voucher_balance":46.58893,
                    "cash_balance":3.00001},"scode":"0x0","status":true}
```

(VERIFIED — official platform docs, `platform.kimi.ai/docs/api/balance.md`.) Balances are USD;
`cash_balance` can be negative, `voucher_balance` cannot.

Rate limits on this path are tiered by cumulative recharge (VERIFIED, `docs/pricing/limits.md`):

| Tier | Threshold | Concurrency | RPM | TPM | TPD |
|---|---|---|---|---|---|
| Tier0 | $1 | 1 | 3 | 500K | 1.5M |
| Tier1 | $10 | 15 | 100 | 2M | Unlimited |
| Tier2 | $20 | 40 | 100 | 3M | Unlimited |
| Tier3 | $100 | 50 | 200 | 3M | Unlimited |
| Tier4 | $1,000 | 60 | 200 | 4M | Unlimited |
| Tier5 | $3,000 | 100 | 300 | 5M | Unlimited |

On exceed: **HTTP 429 with `X-RateLimit-Limit` / `X-RateLimit-Remaining` / `X-RateLimit-Reset`
headers** — remaining capacity is therefore readable *per response*, not only by polling.

### Windows, and a live change to them

- **5-hour rolling frequency window** — retained for every tier (VERIFIED, official membership doc).
- **Weekly (7-day) window** — *removed* for the new subscription tiers ("取消每周额度限制,不再每 7 天
  刷新"); **retained** for legacy members, refreshing every 7 days from the subscription date.
  An orchestrator must therefore treat `limit7d` as **optional**, exactly as the schema does — an
  account on a new tier simply will not have it.
- **Monthly total** — shared with the general Kimi membership; `monthCode` is the coding slice.
- **Booster / "Extra Usage" wallet** — lets requests continue past a window without waiting for a
  refresh; shared between kimi.com chat and Kimi Code. Minimum single top-up **25 RMB**, max 10
  top-ups/day, cumulative cap **3,000 RMB**, balance cap **10,000 RMB**. (VERIFIED, official doc.)

**Quota is pooled, not per-session and not per-device:** *"all devices and API keys share one quota
pool"*, and devices idle more than 30 days auto-unbind. **An orchestrator running four Kimi sessions
on one account gets no more throughput than one** — opening more terminals does not add capacity;
every session draws on the same budget.

### Limit-hit in band

Yes, and cleanly. A 429 from exhausted quota or insufficient balance **is not retried** and fails
immediately (`config-files.md` §`loop_control`), surfacing as a `turn.ended` record in `wire.jsonl`
carrying `error.code`, `error.message` and `error.retryable: false` — I verified that shape on a
different error (`model.not_configured`, `retryable:false`). The envelope error bands reserve
`7xxxx` for "LLM provider" errors with `msg` carrying the upstream text.

---

## F. ACCOUNTS

### Several accounts on one machine

**Yes, and the mechanism is a single environment variable — structurally identical to the
`CLAUDE_CONFIG_DIR` trick the owner already automates with a profile switcher.**

```sh
export KIMI_CODE_HOME="$HOME/.kimi-accounts/work"
```

*"Once set, **all** Kimi Code data lands under the new path: config, sessions, logs, OAuth
credentials, Kimi-specific user Skills, global AGENTS.md, and more."* And, stated as the warning
that makes it an account boundary: *"Multiple `kimi` instances sharing the same `KIMI_CODE_HOME`
will share config and credential files."* (VERIFIED, `env-vars.md`, and confirmed by running the
sandbox entirely inside a scratch `KIMI_CODE_HOME`.)

That one variable partitions: `credentials/` (the OAuth token), `config.toml` (every provider API
key), `sessions/` + `session_index.jsonl`, `server.token`, `server/instances/`, `logs/`, `skills/`,
`agents/`, `plugins/`, `mcp.json`, and the derived **Remote Control device id**.

Two knock-on effects a supervisor must plan for:

- **Session history does not span accounts.** Unlike the owner's Claude Code setup — where every
  switcher profile symlinks `projects/` into one shared store, which is what makes cross-account resume
  work — a second `KIMI_CODE_HOME` is a second, empty session store. Moving a task between accounts
  means starting a new session, not resuming the old one. **This is the single biggest behavioural
  difference from the Claude Code account model the owner already has.**
- **One local server port per home is the clean pattern.** Instances under the same home share
  `server.token` and one `server/instances/` registry; instances under different homes are fully
  independent. Give each account its own `--port`.

Generic cross-tool resources deliberately stay in the real OS home and are therefore **shared
across accounts**: `~/.agents/skills/`, `~/.agents/agents/`, `~/.agents/AGENTS.md` (VERIFIED,
`data-locations.md`). A team skill set installed once is visible to every account — useful, and a
leak vector to be aware of.

### Switching a NEW session to a chosen account

Four routes, in decreasing order of cleanliness:

1. **`KIMI_CODE_HOME=<dir>`** in the child process's environment. Whole-identity switch. The right
   default.
2. **`api_key_env`** on a provider in `config.toml` — the value is *re-read from the process's own
   environment on every request*, so no secret lands in `config.toml`. Mutually exclusive with
   `api_key` and with `oauth`; setting both is rejected. **Caveat, stated explicitly in the docs:**
   *"a running process only sees the environment it started with — rotating the variable takes a
   restart"*. Declaring `api_key_env` while the variable is unset fails fast, naming the provider and
   the variable, with no silent fallback. (VERIFIED, `overrides.md`; shipped in **2.0.1**, so it is
   three days old.)
3. **`KIMI_MODEL_*` family** — when `KIMI_MODEL_NAME` is set, the CLI synthesizes a provider and
   model alias **in memory**, writing nothing back. `KIMI_MODEL_NAME` (required, and the enable
   switch), `KIMI_MODEL_API_KEY` (required), `KIMI_MODEL_PROVIDER_TYPE` (`kimi`|`anthropic`|`openai`,
   default `kimi`), `KIMI_MODEL_BASE_URL`, `KIMI_MODEL_MAX_CONTEXT_SIZE` (default `262144`),
   `KIMI_MODEL_CAPABILITIES`, `KIMI_MODEL_DISPLAY_NAME`, `KIMI_MODEL_MAX_OUTPUT_SIZE`,
   `KIMI_MODEL_REASONING_KEY`, `KIMI_MODEL_THINKING_EFFORT`, `KIMI_MODEL_ADAPTIVE_THINKING`.
   Missing a required one fails at startup with a clear error. Priority: `-m <alias>` > `KIMI_MODEL_*`
   > `default_model`. **This is the per-role, per-launch credential channel that needs no files at
   all.** (VERIFIED, `env-vars.md`.)
4. **`kimi provider add <url> --api-key`** / `kimi provider catalog add <id> --api-key ...
   --default-model ...` / `kimi provider remove <id>` / `kimi provider list --json` — scriptable,
   non-interactive provider management, writing `config.toml`. (VERIFIED, `kimi provider --help`.)

> **The trap that the rest of the ecosystem gets wrong.** *"Credential variables such as
> `KIMI_API_KEY`, `ANTHROPIC_API_KEY`, and `OPENAI_API_KEY` are **not** read automatically from shell
> environment variables. Running `export KIMI_API_KEY=xxx` in the terminal does not give any provider
> its key."* They are **key names inside the `[providers.<name>.env]` sub-table of `config.toml`**.
> The only two channels that genuinely read the shell are `api_key_env` and `KIMI_MODEL_*`.
> (The single exception is `GOOGLE_APPLICATION_CREDENTIALS`, read by the Google SDK's own ADC flow.)
> A launcher that exports `KIMI_API_KEY` and expects it to work will fail, silently at config-load
> and loudly at first request. (VERIFIED, `env-vars.md` + `overrides.md`.)

**There is no project-level config file.** *"The CLI currently reads a single user-level config file
and has no project-level config file mechanism. To isolate config between different projects, point
`KIMI_CODE_HOME` at different data directories."* So per-project *and* per-account isolation are the
same lever and can collide — one home per (account × isolation domain).

Region is a further axis: `mainland-cn` (`auth.kimi.com` / `api.kimi.com/coding/v1` /
`code.kimi.com` / `www.kimi.com`) vs `global` (`auth.kimi.ai` / `api.kimi.ai/coding/v1` /
`code.kimi.ai` / `www.kimi.ai`). Resolution order: `KIMI_CODE_OAUTH_HOST` / `KIMI_OAUTH_HOST` env →
persisted login → default-slot login → a `<home>/region` marker file written by the installer →
default `mainland-cn`. `kimi login --region <mainland-cn|global>` picks it explicitly. My clean
sandbox resolved to `mainland-cn` — **the default is the mainland endpoint, which is probably not
what a European owner wants; the region must be set deliberately.** (VERIFIED — live
`GET /api/v1/oauth/region` returned `{"region":"mainland-cn"}`; `packages/oauth/src/region.ts`.)

### Changing a RUNNING session's account

**No.** Nothing switches the identity of a live session. The available runtime switches are model
and provider-shaped, not account-shaped:

- `POST /api/v1/sessions/{id}/profile` with `agent_config.model` — applied immediately to the main
  agent, but only picks a *different alias*, which resolves through the same credential store.
- `POST /api/v1/providers/{id}` / `PUT` / `:refresh` / `:refresh_oauth` — mutate config, but an
  `api_key_env` rotation explicitly needs a process restart.
- `POST /api/v1/sessions/{id}/runtime` with `runtime_id` — switches *where the agent loop runs*
  (`40420` unknown runtime, `40926` unavailable). I saw `runtimeId: "local"` in a real
  `runtime.set_binding` wire record. What non-`local` runtimes exist is **UNKNOWN** and is the most
  interesting undocumented lead on this platform.

**Cost of an account switch mid-task:** abort the turn (`POST …:abort`, verified: returns
`{"aborted":true}`), let the session go cold, start a fresh session under the other
`KIMI_CODE_HOME`, and re-seed it — the new home cannot see the old session's history. Budget one
full context re-establishment per switch. **Because quota is pooled per account, extra sessions on one
account add no capacity** — so any move to a separate account (if the user configures one) pays this cost in full.

---

## G. INTERVENTION — **non-negotiable axis: fully supported, and the best in the field**

### Send an instruction into a running session and know it arrived

```
POST /api/v1/sessions/{session_id}/prompts
body: { content: [{type:"text", text:"…"}], agent_id?, prompt_id?, skills?,
        profile?, model?, thinking?, permission_mode?, disabled_tools? }
→ { prompt_id, user_message_id, status: "running"|"queued"|"blocked", content, created_at }
```

**`prompt_id` is client-chosen and gives idempotent submission.** Verified live, with both outcomes:

```
POST … {"content":[…],"prompt_id":"orch-0001"}  → code 0, {"prompt_id":"orch-0001",
                                                   "user_message_id":"orch-0001","status":"running"}
POST … same prompt_id again                     → code 40927, "prompt_id 'orch-0001' is already in use"
```

The orchestrator names the unit of work before it exists — the thing §B does not let it do for
sessions, it *does* let it do for prompts, which is arguably the more useful half.

Queue control on top of that:

| Endpoint | Effect |
|---|---|
| `GET …/prompts` | `{active, queued}` snapshot; status `running`/`queued`/`blocked` |
| `POST …/prompts:steer` `{prompt_ids:[…]}` | force queued prompts into the **running** turn instead of waiting for it to end |
| `POST …/prompts/{prompt_id}:steer` | single-prompt form |
| `POST …/prompts/{prompt_id}:abort` | abort one running prompt (`40903` if already complete, `data.aborted:false`) |
| `POST …/sessions/{id}:abort` | abort the main agent's turn (verified: `{"aborted":true}`) |
| `POST …/sessions/{id}:btw` | fork a read-only child agent (`Read`/`Grep`/`Glob` only) for a side question that never pollutes the working context; returns `{agent_id}` |

`:steer` is the direct analogue of the TUI's `Ctrl-S`, and it is precisely what the field notes
record the current harness as unable to do: *"a nudge that cannot submit stranded text."*
Here the nudge is an HTTP POST with a correlation id and a typed response.

> **Acknowledgement is weaker than it looks, and this is the one real sharp edge.** The POST returns
> `status:"running"` **before the model is resolved**. I submitted a prompt to a session with *no
> provider configured at all* and got `code 0, status:"running"`. The turn then failed
> asynchronously, visible only in the event stream and on disk:
> `turn.ended … error {code:"model.not_configured", retryable:false}`, then
> `prompt.completed … reason:"failed"`, and the session's `last_turn_reason` flipped to `"failed"`.
> **A 200 on `/prompts` means "accepted", never "ran".** The orchestrator must confirm through
> `prompt.completed` / `turn.ended` (WebSocket or `wire.jsonl`), or by polling
> `GET /api/v1/sessions/{id}` for `last_turn_reason`. All four of those observations are VERIFIED live.
>
> Second observation, a divergence from the docs: the docs say a `prompt_id` belonging to an
> *already-completed* prompt fails `40903`. After my prompt completed (as `failed`), reuse returned
> **`40927` "already in use"**, not `40903` — the reservation was not released. Treat a `prompt_id`
> as burned for the lifetime of the process.

### Answer a permission prompt programmatically

```
GET  /api/v1/sessions/{id}/approvals?status=pending
  → items: { approval_id, session_id, agent_id, turn_id?, tool_call_id, tool_name,
             action, tool_input_display, created_at, expires_at }     # expires_at = created_at + 24h
POST /api/v1/sessions/{id}/approvals/{approval_id}
     { decision: "approved"|"rejected"|"cancelled", scope?: "session",
       feedback?: "…", selected_label?: "…" }
  → { resolved: true, resolved_at }      # 40902 if already resolved (data.resolved:false)
                                         # 41001 if it timed out
```

`scope:"session"` **remembers the rule for the rest of the session** — the programmatic equivalent of
"approve for this session". `selected_label` answers labelled choices such as a plan review.
(VERIFIED live: the list endpoint returns `{"items":[]}` and requires `status=pending`.)

### Answer the session's own question programmatically

```
GET  /api/v1/sessions/{id}/questions?status=pending
  → items: { question_id, agent_id?, turn_id?, tool_call_id?, questions[1..4], created_at }
    each question: { id, question, header?, body?, options[2..4], multi_select?, allow_other?, … }
POST /api/v1/sessions/{id}/questions/{question_id}
     { answers: { "q_0": {kind:"single", option_id:"…"}, … },
       method?: "enter"|"space"|"number_key"|"click", note?: "…" }
  → { resolved: true, resolved_at }
POST /api/v1/sessions/{id}/questions/{question_id}:dismiss
```

Answer kinds: `single` (`option_id`), `multi` (`option_ids`), `other` (`text`),
`multi_with_other` (`option_ids` + `other_text`), `skipped`. Errors: `40405` no such pending
question, `40902` already resolved, `41002` timed out.

**This is a direct, exact answer to the owner's hardest requirement.** The agent's question is a
structured object with stable ids and typed options, sitting in a queryable list with a timeout —
not text on a screen that has to be OCR'd or typed at. The orchestrator can even record *how* it
answered via `method`, and attach a free-form `note`.

> One wart for a client library: `:dismiss` **succeeds with envelope `code` `40909`**, not `0`.
> *"clients must special-case this endpoint's success code."* (VERIFIED, docs.)

New requests arrive as `event.approval.requested` / `event.question.requested` on the WebSocket, and
`GET …/snapshot` carries `pending_approvals` / `pending_questions` so a supervisor that reconnects
never misses one. The session object's `pending_interaction` field (`none` / `approval` / `question`)
is a one-field poll for "is anything blocked" (VERIFIED live — read `"pending_interaction":"none"`).

### Via ACP instead

`kimi acp` implements **core 3/3**, **session agent-side 11/11**, **client reverse-RPC 10/11**, plus
the `session/set_model` extension. `session/request_permission` is the shared channel for tool
approval and questions; `elicitation/create` is used when the client advertises `elicitation.form`,
falling back to `session/request_permission` on RPC failure. Declared capabilities include
`loadSession:true`, `sessionCapabilities.{list,resume,close,delete,fork,additionalDirectories}`,
`promptCapabilities.{image:true, audio:false, embeddedContext:true}`, `mcpCapabilities.{http,sse}`.
Not implemented: `providers/*`, `nes/*`, `document/*`, `elicitation/complete` → `methodNotFound`.
(VERIFIED, `docs/en/reference/kimi-acp.md`.)

ACP is the right surface for an orchestrator that already speaks ACP to several agents; the HTTP/WS
server is the right one for an orchestrator supervising many sessions at once, because it addresses
**sessions**, not processes.

---

## H. GUARDRAILS

### Three permission modes

| Mode | Flag / config | Behaviour |
|---|---|---|
| **Always Ask** (`manual`) | default | read-only runs automatically; everything else asks, one by one |
| **Ask When Needed** (`yolo`) | `-y`, `--yolo`, `/yolo`; hidden aliases `--yes`, `--auto-approve` | auto-approves regular tool calls; **still asks** before sensitive files (`.env`, SSH keys), dangerous commands (`shutdown`, `rm -rf`), and exiting Plan mode; the agent can still ask questions |
| **Never Ask** (`auto`) | `--auto`, `/auto` | fully unattended: every approval handled automatically **including sensitive files and plan exits**, and **the agent never asks questions**; the dangerous-command guard is **never active** in this mode |

Set persistently with `default_permission_mode = "manual"|"yolo"|"auto"`. Changeable at runtime via
`POST /api/v1/sessions/{id}/profile` `{agent_config:{permission_mode:"…"}}` or per-prompt via
`POST …/prompts` `{permission_mode:"…"}`. **`kimi -p` runs under `auto` regardless** (VERIFIED,
`kimi-command.md`). My live session reported `"permission":"manual"` by default (VERIFIED).

### Static rules

```toml
[[permission.rules]]
decision = "deny"                 # allow | deny | ask
pattern  = "Bash(rm -rf*)"        # ToolName or ToolName(arg-pattern)
scope    = "user"                 # turn-override | session-runtime | project | user
reason   = "never"
```

Matched **in order; first match wins**. `AgentSwarm`, MCP tools and custom tools match by **tool name
only** — argument patterns are not supported for them, which is a real blind spot when the dangerous
capability is behind an MCP server. **Static deny rules stay in effect even in `-p` mode and even in
Never Ask mode** — they are the only guardrail that is not mode-dependent, and therefore the one an
orchestrator should actually rely on.

`[permission] dangerous_command_guard = false` (or `KIMI_CODE_DANGEROUS_COMMAND_GUARD=false`, which
overrides the file) disables the built-in dangerous-command policy entirely.

**Sub-agents inherit the main agent's permission rules**, including "always allow" decisions accepted
interactively — so one careless approval propagates to every subagent that agent dispatches.
The `Agent` tool itself is allowed by default.

### Hooks

`[[hooks]]` in `config.toml`, fields `event` (required), `matcher` (regex, optional), `command`
(required), `timeout` (1–600 s, default 30). Only those four fields; extras fail config load. Event
JSON arrives on **stdin** (`hook_event_name`, `session_id`, `session_title`, `client_type`, `cwd`,
plus per-event fields, all snake_case). Exit `0` = allow, **exit `2` = block** (stderr becomes the
reason), any other non-zero = allow. Or return
`{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"…"}}` on stdout.

**Blockable events: `PreToolUse`, `Stop`, `UserPromptSubmit`. Everything else is observation-only.**

Events relevant to a supervisor: `SessionStart` (`startup`|`resume`), `SessionEnd` (`exit`|`archive`),
**`SessionHeartbeat` (every 60 s while alive, payload includes `uptime_ms`, and the timer only runs
when the event is configured)**, `TurnStarted`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`,
`PermissionRequest`, `PermissionResult`, `SubagentStart`/`Stop`, `TaskStarted`, `Stop`,
`StopFailure`, `Interrupt`, **`PreCompact`/`PostCompact` (`manual`|`auto`)**, `Notification`,
`UserPromptQueued`.

`SessionHeartbeat` is the cheapest possible liveness signal — a 60-second pulse per live session with
no polling, and the field notes' "a shell that can never exit reading as work" failure mode becomes
detectable by pairing heartbeats against `turn.*` records.

> **Hooks are explicitly fail-open.** *"Even if the script errors or times out, the CLI will not
> interrupt your work… Precisely because of fail-open, Hooks are suitable for alerts and lightweight
> interception, but should not be used as the sole security barrier."* A crashing guard hook silently
> permits. Use `[[permission.rules]] decision = "deny"` for anything that must actually be stopped.

### Sandboxing

**There is none.** No container, no seccomp, no filesystem jail. The blast radius is the workspace
plus whatever `--add-dir` adds, and 2.0.1 explicitly *"Remove[d] the system-prompt rule that forbade
all file access outside the working directory"* — so even the prompt-level fence is gone. Untrusted
project folders get a **workspace trust prompt** that lists each project-level MCP server's transport
and launch target before enabling it, and the prompt defaults to `Trust this folder`. Workspace trust
is programmable: `GET/POST /api/v1/workspaces/{id}/trust`, `…:untrust`.

Bounding levers that do exist: `[loop_control] max_steps_per_turn` (`KIMI_LOOP_MAX_STEPS_PER_TURN`),
`max_attempts_per_step` (default 10), `[background] max_running_tasks`, `bash_task_timeout_s`
(default 600 s; **`0` in print mode**), `kill_grace_period_ms` (5000), `[subagent] timeout_ms` and
`[swarm] timeout_ms` (both default 7,200,000 ms = 2 h), `KIMI_CODE_AGENT_SWARM_MAX_CONCURRENCY`,
`KIMI_DISABLE_CRON=1`, `[tools]` global tool switches, `disabled_tools` per prompt.

### The local server is a remote-code-execution surface

`GET /api/v1/fs:content` returns *"raw bytes of any host file (gated only by the token)"*, and
`/api/v1/sessions/{id}/terminals` creates terminals. The bearer token in
`$KIMI_CODE_HOME/server.token` (0600) is therefore root-equivalent for that user. Bind loopback only;
set `KIMI_CODE_PASSWORD` as a parallel credential for any non-loopback bind; never
`--dangerous-bypass-auth`. Non-loopback binds ban a source for 60 s after 10 auth failures in 60 s
(HTTP 429, code `42901`). `POST /api/v1/shutdown` is mounted **only on loopback** unless
`--allow-remote-shutdown`. `kimi web rotate-token` invalidates the old token immediately and every
running instance under that home picks the new one up without restart. (VERIFIED — I confirmed a
tokenless `GET /api/v1/meta` returns **401**, and `/api/v1/healthz` is the one auth-exempt route,
returning `{"ok":true}`.)

> **One more thing to know before piping responses into a log.** Error envelopes carry a full
> `stack` field with absolute filesystem paths. I got a complete Node stack trace with the sandbox's
> absolute path inside a `40910` response body. Scrub before logging or forwarding.

---

## I. EXTENSIBILITY

| Surface | Detail | Tag |
|---|---|---|
| **MCP** | Client for `stdio`, `http`, `sse`. Declared in `$KIMI_CODE_HOME/mcp.json` (user) and `.kimi-code/mcp.json` (project, wins on name collision). Per-server `startupTimeoutMs`/`toolTimeoutMs` beat the global `[mcp]` table, which `KIMI_MCP_STARTUP_TIMEOUT_MS`/`KIMI_MCP_TOOL_TIMEOUT_MS` beat in turn. Servers added mid-session join only *later* sessions; removed servers stay visible as `removed` in open ones. API: `GET /api/v1/mcp/servers`, `…:restart`, and a full `/api/v2/mcp` tree with `:test`, `:inspect`, `auth:begin/:complete/:cancel/:reset`. | VERIFIED |
| **Skills** | `SKILL.md` + YAML frontmatter (`name`, `description`, `type`, `whenToUse`, `disableModelInvocation`), directory or flat form, `${KIMI_SKILL_DIR}` for supporting files. Locations: `$KIMI_CODE_HOME/skills/` (moves with the home) and **`~/.agents/skills/`** (stays in the real OS home, cross-tool). `--skills-dir` **replaces** discovery for one launch and repeats; `extra_skill_dirs` **adds** permanently. Activation over the API: `POST …/skills/{name}:activate`, or `POST …/prompts` with a `skills: [{name, args?}]` array. | VERIFIED |
| **Sub-agents** | Built-ins `coder`, `explore` (read-only), `plan` (no shell). Independent context windows. The built-ins **cannot dispatch further sub-agents**, and a custom agent inherits that allowlist, *"so delegation chains always terminate and unbounded recursive spawning is impossible without an explicit opt-in"* — opt in with an explicit `subagents` allowlist. `--agent <name>` / `--agent-file <path>` bind the **main** agent at session creation and cannot be combined with `--session`/`--continue`. Discovery precedence: Explicit > Project > Extra > User > Plugin > Built-in. | VERIFIED |
| **Swarm** | An `AgentSwarm` tool distinct from `Agent`, with its own `[swarm] timeout_ms` and `KIMI_CODE_AGENT_SWARM_MAX_CONCURRENCY`; `swarm_mode` is a session flag settable through `/profile`. An experimental `tower` multi-agent mode exists (`/tower <base-branch>`, `tower_mode` in the live status payload, `tower:false` in `experimental_flags`). | VERIFIED |
| **Plugins** | `/plugins` manager + `/plugins install|list|enable|disable|remove|reload|info|marketplace`. A plugin can bundle skills, agents, a session-start skill, system-prompt instructions and MCP servers. Marketplace URL overridable with `KIMI_CODE_PLUGIN_MARKETPLACE_URL` (accepts `file://` and local paths — so a **private, offline marketplace is one env var**). Records in `plugins/installed.json`. | VERIFIED |
| **Hooks** | See §H. | VERIFIED |
| **Scheduled tasks** | `CronCreate` / `CronList` / `CronDelete` tools re-inject a prompt into the session. 5-field cron in local time, ≤50 per session, prompt ≤8 KB UTF-8. Persisted in `<sessionDir>/cron/` and **reloaded on `kimi --session`**. Deterministic jitter (`min(10% of period, 15 min)`); missed fires coalesce into one with a `coalescedCount` inside a `<cron-fire>` envelope; **recurring tasks older than 7 days fire once with `stale="true"` and self-delete**. `KIMI_DISABLE_CRON=1` kills it. | VERIFIED |
| **Goal mode** | `/goal <objective>` (≤4000 chars) keeps the agent working toward an outcome across turns, with **token, turn and wall-clock budgets** readable at `GET …/goal` → `{goalId, objective, completionCriterion?, status, turnsUsed, tokensUsed, wallClockMs, budget, terminalReason?}`, `status` ∈ `active`/`paused`/`blocked`/`complete`. Controllable via `/profile` `{agent_config:{goal_objective, goal_control:"pause"|"resume"|"cancel"}}`. `/goal next` queues follow-ups (`upcoming-goals.json`). **Non-interactive mode supports only *creating* goals — `kimi -p "/goal …"` exits `0` on complete, `3` on blocked, `6` on paused.** | VERIFIED |
| **Config precedence** | For ordinary runtime parameters: **CLI flags > `config.toml`**. Environment variables are *not* a general fallback — they do three specific jobs (locate the data root, flip runtime switches, redirect endpoints), and a named subset explicitly overrides specific config fields. Credentials resolve separately: `api_key` **or** `api_key_env` (exactly one) > `[providers.<n>.env]` key > hard failure. | VERIFIED |
| **Identity** | `[identity] name` / `slug` (or `KIMI_CODE_IDENTITY_NAME`/`_SLUG`) rename the agent in the system prompt, the `User-Agent` product token and the MCP client name. Useful for telling four concurrent Kimi sessions apart in server logs. | VERIFIED |

**Can a GSD-style, subagent-heavy workflow engine run inside it?** Yes, structurally: skills as
commands, custom agents as roles, hooks as gates, MCP for tools, per-session cron, and goal budgets.
Two caveats. (1) **Delegation depth is capped by default** — the built-in `coder`/`explore`/`plan`
cannot dispatch further, so a three-level GSD hierarchy needs custom agents with explicit
`subagents` allowlists. (2) **Skill/agent discovery is home-scoped**, so a per-account
`KIMI_CODE_HOME` means installing the engine once per account, or relying on the shared
`~/.agents/` tree.

**SDK note:** `packages/node-sdk` (`@moonshot-ai/kimi-code-sdk`, exporting `createKimiHarness`,
`listSessions`, `forkSession`) is marked **`"private": true`** and is not published to npm
(VERIFIED). `MoonshotAI/kimi-agent-sdk` (Apache-2.0, 575 stars, last pushed 2026-05-29) targets the
*legacy* Python CLI. **An orchestrator should integrate over HTTP/WS or ACP, not against an SDK.**

---

## J. OPERATIONAL REALITY

### Install footprint and platform support

macOS/Linux: `curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash` (single binary, checksum
verified, no Node required). Windows: `irm https://code.kimi.com/kimi-code/install.ps1 | iex` plus
Git for Windows (`KIMI_SHELL_PATH` if Git Bash is elsewhere). Or `npm install -g
@moonshot-ai/kimi-code` — **Node ≥ 22.19.0**, which this machine's default 22.18.0 does not meet.
Runtime deps are tiny (`ws`, `qrcode`; optional `node-pty`, `@mariozechner/clipboard`); `node-pty`
has a native build step, and npm flagged two install scripts (`@moonshot-ai/kimi-code` postinstall
and `node-pty`) as needing approval under this machine's npm policy. macOS is fully supported.
The CLI self-downloads `rg` and `fd` into `$KIMI_CODE_HOME/bin/` on first need. (VERIFIED.)

**Auto-update is on by default** (`[upgrade].auto_install` in `tui.toml`) and stages new binaries in
the background, recording staged-rollout decisions in `updates/rollout.log`. **For an unattended
fleet, set `KIMI_CODE_NO_AUTO_UPDATE=1`** (legacy alias `KIMI_CLI_NO_AUTO_UPDATE`) so a mid-run
version swap cannot change the flag surface underneath the orchestrator. (VERIFIED.)

### Cost model

Two, and they behave completely differently under an overnight queue.

**Subscription (Kimi Code plan) — the one that matters here.** Rolling 5-hour window on every tier;
weekly window *removed* for the new tiers and retained for legacy members; monthly totals shared with
the general Kimi membership; a booster wallet for overflow. **All devices and API keys share one
pool.** Tier names were renamed from Andante / Moderato / Allegretto to Plus / Pro (+ higher tiers)
with prices *"unchanged"* (VERIFIED — official membership doc). Secondary sources put the older
ladder at **$19 / $39 / $99 / $199 per month** (CLAIMED — geotoolbox, omidsaffari and similar; the
official pricing page is JS-rendered and did not yield figures to a fetch). **Treat the exact numbers
as unverified; treat the window *structure* as verified.**

**Pay-as-you-go API key** (VERIFIED, models.dev + platform docs, USD per Mtok):

| Model | Context | Max output | Input | Output | Cache read |
|---|---|---|---|---|---|
| `kimi-k3` | 1,048,576 | 131,072 | $3.00 | $15.00 | $0.30 |
| `kimi-k2.7-code` | 262,144 | 262,144 | $0.95 | $4.00 | $0.19 |
| `kimi-k2.7-code-highspeed` | 262,144 | 262,144 | $1.90 | $8.00 | $0.38 |
| `kimi-k2.6` | 262,144 | 262,144 | $0.95 | $4.00 | $0.16 |

Plan-side model aliases (`kimi-code-plan-global` / `-cn` in models.dev, cost `0` because the plan
covers them): `kimi-for-coding` (1M ctx, 32K out, released 2026-09-11), `k3` (1M / 131K),
`k3-256k` (256K / 131K), `kimi-for-coding-highspeed` (256K / 32K).

`kimi-k2.7-code` at **$0.95 / $4.00** with a 256K window is roughly a quarter of `kimi-k3`'s price and
well under frontier Anthropic pricing — the same economic argument the field scan makes for MiMo
applies here, with the added advantage that the *agent harness* is Kimi's own rather than Claude Code
pointed elsewhere. Discontinued and to be avoided: `kimi-k2.5` and the `moonshot-v1` family
(2026-08-31), `kimi-k2` series (2026-05-25), `kimi-latest` (2026-01-28).

### Maturity — the honest read

| Signal | Value |
|---|---|
| Version | `2.0.2`, published **2026-09-19T12:16Z** — *today* |
| `2.0.0` | **2026-09-17** — two days ago |
| Previous line | `0.43.1` on 2026-09-15; 80 npm versions since 2026-05-22 |
| Repo | MIT, 7,499 stars, pushed today, many distinct contributors in the changeset log |
| The API's own words | *"The REST and WebSocket APIs described on this page are **experimental**: interface stability is not guaranteed, and endpoints, fields, and event types may change in any release."* |
| Predecessor | Python `kimi-cli` 1.50.0, being wound down |

**This is a two-day-old major version of a four-month-old product whose control plane is explicitly
labelled experimental, replacing a CLI that is itself being retired.** Against that: the 2.0.1
changeset is full of exactly the bugs an unattended orchestrator would hit — *"Fix `kimi -p` exiting
early and cancelling the active turn when a cron task fires"*, *"Fix new messages occasionally
landing at an old position in the conversation after resuming a session"*, *"Keep follow-up messages
sent during a turn from appearing twice after a session reload"*, *"Fix deleting or archiving a
session sometimes never finishing"*, *"Fix compaction failing after switching to a model with a
smaller context window"*, *"Stop workspace file watchers from scanning an unbounded project root"*.
Those are real fixes to real long-run failure modes — and they are also proof that those failure
modes existed in shipped versions **within the last 72 hours**.

**Mitigation that makes it tractable:** the server publishes `/openapi.json` and `/asyncapi.json`
generated from the same validation schemas it enforces at runtime, and the docs state that *"when
this page and the live spec ever disagree, the live spec wins."* An orchestrator should **pin the
version, disable auto-update, and diff `/openapi.json` on every upgrade** rather than trusting the
prose. That converts "experimental API" from an unbounded risk into a mechanical regression check.

### Known / probable unattended failure modes

1. **Pooled quota means no free parallelism.** Four sessions on one account share one 5-hour window.
2. **A `200` on `/prompts` does not mean the prompt ran** (§G) — the single most likely way to build
   an orchestrator that silently does nothing.
3. **Auto-update swapping the binary mid-run.** Disable it.
4. **`bash_task_timeout_s` defaults to `0` (no timeout) in print mode**, and subagents default to no
   timeout there either — *"only the model itself stops a task."* A hung command in `-p` mode hangs
   forever unless `KIMI_CODE_BACKGROUND_BASH_TASK_TIMEOUT_S` is set. This is the field notes'
   "shell that can never exit reading as work" with the safety rail *off by default*.
5. **`print_background_mode` defaults to `"steer"`**, bounded by `print_max_turns = 100000` and
   `print_wait_ceiling_s = 2147483` — *"both effectively unbounded by default."* A `-p` run can keep
   spawning turns from background completions long after the main answer. Set `"exit"` or `"drain"`.
6. **Region defaults to `mainland-cn`** on a fresh home (VERIFIED live). Wrong endpoints, wrong
   latency, possibly wrong account.
7. **Cron re-injection only revives with `kimi --session`**, not in a new session — and a recurring
   task older than 7 days self-deletes after one final `stale="true"` fire.
8. **Remote Control dies with its terminal and with sleep/network loss**; *"Set the computer to never
   sleep."* Device limit ≈3 per account.
9. **The WebSocket has no server heartbeat and no idle disconnect** — keepalive is the client's job,
   and a silently dead socket looks identical to a quiet session.
10. **Events older than 1000 in the buffer are unreplayable** → `resync_required` → full snapshot.
11. **Hooks fail open.** A crashed guard permits.
12. **Error envelopes leak absolute filesystem paths in `stack`.**
13. **Node 22.18.0 on this machine is below the required 22.19.0** — a naive `npm i -g` under the
    default node will install and then fail at runtime.

### Is it plausible to run overnight unattended today?

**Yes, mechanically — and it is the most *supervisable* platform in this scan.** `--auto` is a real
never-ask mode, static deny rules survive it, quota/context/compaction/questions are all
programmatically reachable, and every session's history is durable JSONL on disk.

**But not yet as the primary executor for the owner's queue**, for two reasons that have nothing to
do with capability: the control plane is two days old and self-labelled experimental, and there is no
sandbox, so `--auto` plus no container plus a removed workspace fence is a wide blast radius for an
unattended overnight run.

The defensible position today is **Kimi Code as a second-class executor behind Claude Code**: run it
for a bounded queue, pinned to `2.0.2`, auto-update off, `KIMI_CODE_HOME` per account, region set
explicitly, deny rules for anything destructive, `KIMI_CODE_BACKGROUND_BASH_TASK_TIMEOUT_S` and
`print_background_mode` set, and the supervisor confirming every prompt through `prompt.completed`
rather than through the POST. Its *protocol* deserves to be copied regardless of whether its
*runtime* is adopted.

---

## What this costs the orchestrator

### What it gets for free (no adapter work beyond HTTP)

- **Quota** — one GET, four named windows, floats and reset timestamps, plus a booster balance in
  cents. Readable **without** the local server, straight against `…/coding/v1/usages` with the
  on-disk OAuth token. The owner's existing `claude-limits` logic ports over with a field rename.
- **Context fullness** — `context_usage` as a 0–1 float, per session, on demand.
- **Compaction from outside, with four proof channels** — endpoint, WS events, `PreCompact`/
  `PostCompact` hooks, and the `40911` compaction boundary.
- **Answering questions and approvals** — typed objects with stable ids, options, timeouts, and a
  `scope:"session"` that installs a standing rule.
- **Steering a running turn** — `:steer`, the thing the current harness cannot do.
- **Liveness** — `SessionHeartbeat` every 60 s, `server/instances/*.json` with a `heartbeat_at`,
  `GET /healthz` unauthenticated, `busy` / `main_turn_active` / `pending_interaction` /
  `last_turn_reason` on every session object.
- **A transcript that is both a live stream and a durable file**, with structured error codes,
  `retryable` flags and per-turn token counts.
- **Multi-account** — one environment variable.
- **A machine-readable contract** — `/openapi.json` (105 paths / 126 operations) and
  `/asyncapi.json`, generated from the runtime's own validation schemas, so the adapter can be
  regression-tested against the binary rather than against prose.

### What it must build, and the price

| Gap | Workaround | Cost |
|---|---|---|
| **Cannot name a session before it exists** (§B) | `POST /sessions` → immediately `POST /sessions/{id}/profile` with `{metadata:{<your id>}}`, then index client-side | one extra round trip; a crash window between the two calls leaves an untagged session; no server-side metadata filter, so recovery is list-and-scan |
| **`POST /sessions` silently drops non-`cwd` metadata** | as above — never trust creation-time metadata | a silent-wrong-answer bug if you don't know; verified here so you do |
| **A `200` on `/prompts` means accepted, not ran** | confirm via `prompt.completed` / `turn.ended` on WS or in `wire.jsonl`, or poll `last_turn_reason` | every submission needs a paired confirmation; this is the single most important adapter invariant |
| **`prompt_id` is burned after a failed prompt** (`40927`, not the documented `40903`) | mint a fresh id per attempt (e.g. `<task>-<attempt>`) | never retry with the same id |
| **No account switch for a running session** | abort → new session under the other `KIMI_CODE_HOME` → re-seed | one full context re-establishment per switch; sessions do not span homes |
| **Quota is pooled per account** | parallelism must come from more accounts, not more sessions | N accounts for N-way concurrency; N OAuth logins to maintain |
| **No sandbox** | `[[permission.rules]] decision="deny"` (the only mode-independent guardrail) + run in a disposable worktree/VM | denies cannot match MCP tool *arguments*, only tool names |
| **No custom-compaction hook** | steer the summary with `:compact` `{instruction}`; or `:fork` for a handoff; or `:btw` for read-only side work | you observe and trigger, you do not replace the algorithm |
| **Experimental API, two days old** | pin the version, `KIMI_CODE_NO_AUTO_UPDATE=1`, diff `/openapi.json` per upgrade | one CI check per version bump — cheap, and it converts the risk into a signal |
| **Unbounded defaults in `-p` mode** | set `KIMI_CODE_BACKGROUND_BASH_TASK_TIMEOUT_S`, `print_background_mode=exit\|drain`, `[subagent]/[swarm] timeout_ms`, `max_steps_per_turn` | four env vars in the launcher; without them an overnight run can hang forever |
| **No WS heartbeat** | client-side ping/pong (the frames exist in the AsyncAPI) + reconnect with `cursors:{seq,epoch}` + `/snapshot` on `resync_required` | standard reconnect logic, but it must be written |
| **Region defaults to `mainland-cn`** | `kimi login --region global`, or pin `KIMI_CODE_OAUTH_HOST` / `KIMI_CODE_BASE_URL` | one flag, easy to forget, expensive to debug |
| **Node ≥ 22.19.0** | ship the native installer or pin an nvm version in the launcher | this machine's default Node is 22.18.0 and will not run it |
| **Two CLIs, one binary name, colliding `-c`** | assert `kimi --version` ≥ 2 at preflight | one check; without it, legacy `-c "prompt"` becomes `--continue` |

### Where Kimi sits relative to the rest of the field

| Axis | Kimi Code 2.0.2 | For contrast |
|---|---|---|
| A Launch | headless + TUI + local HTTP/WS server + ACP + relay | pi: headless + `--mode rpc` |
| B Identity | resume/fork/list excellent; **cannot pre-name a session** | pi's `--session-id` wins here |
| C Transcript | JSONL on disk + REST paging + live WS + op-journal catch-up | pi: JSONL tree in one file |
| D Context | **read `context_usage` + trigger compaction + 4 proofs** | the current harness: nothing |
| E Quota | **4 windows, floats, reset times, booster balance, no server needed** | Claude Code: `oauth/usage`, same shape |
| F Accounts | one env var; **no cross-home session store** | Claude Code + profile switcher: shared `projects/` store |
| G Intervention | **prompts with client ids, `:steer`, typed approvals + questions** | the current harness: a nudge that strands text |
| H Guardrails | 3 modes, ordered rules, 20 hook events; **no sandbox, hooks fail open** | Cursor: allow/deny list |
| I Extensibility | MCP + skills + agents + swarm + plugins + cron + goal budgets | — |
| J Reality | **2 days old, API self-labelled experimental** | Goose v1.51.0, Codex 0.155.1 |

**One sentence:** on the five axes the owner called non-negotiable, Kimi Code answers four of them
outright and the fifth (resume-exactly) with a documented, tested, one-round-trip workaround — and
the only serious reason not to build on it today is its age.

---

## Sources

All accessed **2026-09-19** unless noted. Primary sources first.

### Run on this machine (strongest evidence)
- `@moonshot-ai/kimi-code@2.0.2` installed into an isolated sandbox and executed: `kimi --version`
  (`2.0.2`), `kimi --help`, `kimi web --help`, `kimi rc --help`, `kimi acp --help`,
  `kimi login --help`, `kimi provider --help`, `kimi session list --help`, `kimi doctor`,
  `kimi session list --json`, and the flag-conflict cases `kimi -p … --auto` / `--yolo` / `-c`.
- Live `kimi web --no-open --port 58700` against a scratch `KIMI_CODE_HOME`:
  `GET /api/v1/healthz`, `/api/v1/meta`, `/api/v1/auth`, `/api/v1/oauth/usage`, `/api/v1/oauth/region`,
  `POST /api/v1/sessions`, `GET …/status`, `…/approvals`, `…/questions`, `…/prompts`, `…/snapshot`,
  `…/transcript?agent_id=main`, `…/goal`, `POST …:compact`, `…:abort`, `…:fork`, `…/profile`,
  `POST …/prompts` (twice, same `prompt_id`), `POST /api/v1/shutdown`, plus `/openapi.json`
  (OpenAPI 3.0.3, "Kimi Code Server API" 2.0.2, 105 paths / 126 operations) and `/asyncapi.json`
  (AsyncAPI 3.1.0, channel `kimiCodeWebSocket`, 28 message types).
- Files read from the sandbox home: `server.token`, `server/instances/<id>.json`,
  `session_index.jsonl`, `sessions/<wd>/<sid>/state.json`, `sessions/<wd>/<sid>/agents/main/wire.jsonl`.
- Read-only probe of the owner's machine confirming Kimi is **not** installed: `which kimi kimi-cli`,
  `ls ~/.kimi ~/.kimi-code ~/.config/kimi*`, `env | grep -iE 'moonshot|kimi'`, `grep` over `~/.zshrc`.

### Source code (`MoonshotAI/kimi-code`, `main` @ 2026-09-19T12:56:18Z, MIT)
- `apps/kimi-code/src/cli/commands.ts` — every flag and subcommand registration
- `apps/kimi-code/src/cli/options.ts` — `validateOptions()`, `resolveOutputFormat()`, `OUTPUT_FORMAT_ENV`
- `apps/kimi-code/src/cli/sub/session.ts`, `sub/fork.ts`, `sub/web/*`
- `packages/oauth/src/managed-usage.ts` — usage URL, wire→domain field mapping, `fetchManagedUsage()`
- `packages/oauth/src/region.ts` — region profiles and resolution order
- `packages/oauth/src/storage.ts` — credential file layout and permissions
- `packages/kap-server/src/instanceRegistry.ts`, `services/auth/persistentToken.ts`
- `apps/kimi-code/CHANGELOG.md` — 2.0.0 / 2.0.1 / 2.0.2 entries
- `apps/kimi-code/package.json` — `2.0.2`, `bin.kimi`, `engines.node >= 22.19.0`

### Official documentation (in-repo `docs/en/`, and https://moonshotai.github.io/kimi-code/en/)
`reference/kimi-command.md`, `reference/server-api.md` (2,415 lines), `reference/kimi-acp.md`,
`reference/tools.md`, `reference/slash-commands.md`, `guides/sessions.md`, `guides/interaction.md`,
`guides/remote-control.md`, `guides/web.md`, `guides/getting-started.md`, `guides/migration.md`,
`configuration/data-locations.md`, `configuration/env-vars.md`, `configuration/config-files.md`,
`configuration/overrides.md`, `configuration/providers.md`, `customization/hooks.md`,
`customization/agents.md`, `customization/skills.md`, `customization/mcp.md`,
`customization/plugins.md`.

### Official platform documentation
- https://platform.kimi.ai/docs/api/overview — base URLs `https://api.moonshot.ai/v1` (OpenAI) and
  `https://api.moonshot.ai/anthropic` (Anthropic Messages); `Authorization: Bearer $MOONSHOT_API_KEY`
- https://platform.kimi.ai/docs/api/balance.md — `GET /v1/users/me/balance` and its response shape
- https://platform.kimi.ai/docs/pricing/limits.md — RPM/TPM/TPD/concurrency tiers; 429 +
  `X-RateLimit-Limit` / `-Remaining` / `-Reset`
- https://platform.kimi.ai/docs/models.md — current and discontinued model ids
- https://www.kimi.com/code/docs/kimi-code/membership.html — 5-hour rolling window retained, weekly
  window removed for new tiers, shared quota pool, 30-day device unbind, booster-pack limits
- https://www.kimi.com/code/docs/ — Kimi Code documentation index

### Registries and catalogs
- npm registry `@moonshot-ai/kimi-code` — dist-tags, publish times, `bin`, `engines`, dependency list
- PyPI `kimi-cli` JSON + the 1.50.0 wheel's `METADATA`, `entry_points.txt`, and
  `kimi_cli/cli/__init__.py` (legacy `--wire` / `--acp` / `--afk` / `--print` surface)
- GitHub API — `MoonshotAI/kimi-code`, `MoonshotAI/kimi-cli`, and the `MoonshotAI` org repo listing
  (`kimi-agent-sdk`, `kimi-agent-rs`, `kosong`, `pykaos`, `Kimi-K3`)
- https://models.dev/api.json — providers `moonshotai`, `moonshotai-cn`, `kimi-code-plan-global`,
  `kimi-code-plan-cn`; per-model context, output and USD pricing

### Secondary (CLAIMED — not independently confirmed)
- Subscription price points $19 / $39 / $99 / $199 per month for the pre-rename tiers
  (geotoolbox.ai, omidsaffari.com, felloai.com and similar, September 2026). The official pricing
  page is JS-rendered and did not yield figures to a fetch. **Do not quote these as verified.**

### Deliberately not relied upon
Comparison listicles and "best AI CLI 2026" roundups. The field scan's warning holds: one widely
linked article was wrong about star counts by tens of thousands. Every version, date and flag in this
document comes from a registry API, the project's own source, its own `--help`, or a live response
from the binary.
