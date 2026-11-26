# opencode — platform profile for a provider-agnostic orchestrator

**Date of investigation:** 2026-09-19.
**Version examined:** `opencode-ai@1.18.31` (npm `latest`; GitHub tag `v1.18.31`, published 2026-09-14).
**How it was examined:** installed into an isolated sandbox at
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/oc-sandbox`
with `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME` and `XDG_CACHE_HOME` redirected into that sandbox.
A headless server was run on `127.0.0.1:4199`, its live OpenAPI document was pulled from `/doc`
(478,968 bytes), sessions were created and driven over HTTP, and the resulting SQLite database was
read back. **No provider was ever authenticated, so no model call was made and none of the owner's
quota was spent.** The owner's `~/.config/opencode/opencode.json` was not modified (still
`{"mcp":{}}`, mtime 2026-07-11).

**Evidence tags:** **VERIFIED** = read in the OpenAPI document served by the running binary, read in
the binary's own strings/typings, or executed on this machine today. **CLAIMED** = stated by
opencode.ai docs or a README only. **UNKNOWN** = could not establish.

---

## Identity correction

The field scan calls this "opencode (SST)". The canonical repository today is
**`anomalyco/opencode`** — `github.com/sst/opencode` now redirects to it (VERIFIED, GitHub API,
2026-09-19). Install channels have moved with it: `brew install anomalyco/tap/opencode`,
`ghcr.io/anomalyco/opencode`, `mise use -g github:anomalyco/opencode` (CLAIMED, docs). The npm
package name is unchanged: `opencode-ai`.

| Fact | Value | Tag |
|---|---|---|
| Repo | `anomalyco/opencode`, MIT | VERIFIED (GitHub API) |
| Stars / forks | 208,547 / 27,440 | VERIFIED |
| Open issues | 5,939 | VERIFIED |
| Created / last push | 2025-04-30 / 2026-09-19 (today) | VERIFIED |
| Language | TypeScript, shipped as a single Bun-compiled binary | VERIFIED |
| npm latest | `opencode-ai@1.18.31` | VERIFIED |
| SDK | `@opencode-ai/sdk@1.18.31`, exports `.`, `./v2`, `./client`, `./server`, `./v2/client`, `./v2/server`, `./v2/types`, `./v2/gen/client` | VERIFIED (npm) |
| Plugin types | `@opencode-ai/plugin@1.18.31` | VERIFIED (npm) |

**Not installed on this machine.** `which opencode` finds nothing; `~/.config/opencode/opencode.json`
exists (`{"mcp":{}}`, 2026-07-11) but no binary and no data directory. (VERIFIED)

**The headline.** opencode is the only platform in this scan whose entire feature surface is a
documented, versioned HTTP API with an OpenAPI 3.1 schema, an SSE event stream, an event-sourced
SQLite store, and a first-party SDK — because **the TUI is itself just a client of that server**
("When you run `opencode` it starts a TUI and a server. Where the TUI is the client that talks to the
server", docs/server). An orchestrator is not bolted on the side; it is the same kind of client the
product already ships.

---

## A. LAUNCH

**Both modes, and a third that matters more than either.**

*Headless one-shot.* `opencode run [message..]` (VERIFIED, `--help` on 1.18.31). Relevant flags,
quoted exactly:

```
      --command      the command to run, use message for args
  -c, --continue     continue the last session
  -s, --session      session id to continue
      --fork         fork the session before continuing (requires --continue or --session)
      --share        share the session
  -m, --model        model to use in the format of provider/model
      --agent        agent to use
      --format       format: default (formatted) or json (raw JSON events)
  -f, --file         file(s) to attach to message
      --title        title for the session
      --attach       attach to a running opencode server (e.g., http://localhost:4096)
  -p, --password     basic auth password (defaults to OPENCODE_SERVER_PASSWORD)
  -u, --username     basic auth username (defaults to OPENCODE_SERVER_USERNAME or 'opencode')
      --dir          directory to run in, path on remote server if attaching
      --port         port for the local server
      --variant      model variant (provider-specific reasoning effort, e.g., high, max, minimal)
      --thinking     show thinking blocks
  -i, --interactive  run in direct interactive split-footer mode
      --auto         auto-approve permissions that are not explicitly denied (dangerous!)
```

`--format json` emits **newline-delimited JSON events on stdout**, each carrying `sessionID`.
Observed here verbatim (VERIFIED, executed):

```json
{"type":"error","timestamp":1789824090549,"sessionID":"ses_f462bbf1effelkiJ5TLlj09bRC","error":{"name":"UnknownError","data":{"message":"Unexpected server error. Check server logs for details.","ref":"err_33881f5c"}}}
```

Exit code on that failure was **1** (VERIFIED). The session id appears on the first event, so an
orchestrator that does not pre-name sessions can still scrape one from line 1 of stdout.

*Visible terminal.* `opencode [project]` starts the TUI (default subcommand). `opencode attach <url>`
attaches a TUI to an already-running server, and `--mini` starts a minimal interactive interface.
The `-i, --interactive` flag on `run` gives a "direct interactive split-footer mode". So the owner
can walk up to a running unattended session and type into it — see §G, where the TUI is itself
remote-controllable.

*Server.* `opencode serve --port <n> --hostname <h>` — "starts a headless opencode server" (VERIFIED).
Defaults: `--port 0` (random) and `--hostname 127.0.0.1`. `opencode web` is the same plus a browser
UI. `opencode acp` speaks the Agent Client Protocol over JSON-RPC on stdio, for editors (CLAIMED,
docs/acp; exact JSON-RPC method names are UNKNOWN — the doc does not list them).

**The launch shape an orchestrator should use:** one long-lived `opencode serve`, and all task
launches as HTTP calls against it. `run` is then only needed when the owner wants a terminal he can
watch.

---

## B. IDENTITY & RESUME

**This is opencode's strongest axis, and it was proved on this machine rather than read.**

**The orchestrator names the session before it exists.** `POST /api/session` accepts an `id` in the
request body, constrained to `pattern: "^ses"` (VERIFIED, OpenAPI). Executed here:

```
POST /api/session  {"id":"ses_orchestratortest0001","location":{"directory":"…/proj"}}
→ {"data":{"id":"ses_orchestratortest0001","projectID":"global","cost":0,
   "tokens":{"input":0,"output":0,"reasoning":0,"cache":{"read":0,"write":0}}, …}}
```

and `GET /api/session/ses_orchestratortest0001` returned it unchanged. The body also accepts `agent`,
`model` (`{providerID, id, variant}`) and `location` (`{directory, workspaceID}`) — so role, model and
working directory are all bound at creation.

**`run --session` requires the session to already exist.** `opencode run --session ses_orchestratorprenamed99`
against an unknown id failed with `Error: Session not found`, exit 1 (VERIFIED). But after creating
`ses_orchpre000000000002` over HTTP, `opencode run --session ses_orchpre000000000002 …` picked it up
**without `--attach`** (VERIFIED) — because the CLI and the server open the same SQLite file. The
correct orchestrator recipe is therefore: *create over HTTP with a chosen id, then either drive it
over HTTP or hand the id to a terminal `run`.*

**Listing.** `GET /api/session` (ordered, cursor-paged), `GET /experimental/session` (all sessions
across projects), `opencode session list --format json` (VERIFIED; fields `id, title, updated,
created, projectId, directory`).

**Resume after a crash is event-sourced, not best-effort.** Everything is a durable event with a
monotonic per-session sequence. `GET /api/session/{sessionID}/history?after=<seq>&limit=<n>` returns
one finite page; `GET /api/session/{sessionID}/event?after=<seq>` **replays durable events after that
sequence and then continues with new ones** (VERIFIED, both executed). Observed:

```
GET /api/session/ses_orchestratortest0001/history         → seq 1, 2, 3   "hasMore":false
GET /api/session/ses_orchestratortest0001/history?after=2 → seq 3 only
GET /api/session/ses_orchestratortest0001/event?after=0   → SSE replay of 1,2,3 then live
```

A supervisor only has to persist the last `durable.seq` it processed. After its own crash, after a
reboot, after the opencode process dies, it resumes from that number with **no gap and no
duplicate**. No other platform in this scan offers exactly-once supervisor resume as a protocol
guarantee.

**What survives.** The store is SQLite at `~/.local/share/opencode/opencode.db` (VERIFIED,
`opencode db path`), with WAL. Tables (VERIFIED, `sqlite_master`): `account`, `account_state`,
`control_account`, `credential`, `data_migration`, `event`, `event_sequence`, `message`, `migration`,
`part`, `permission`, `project`, `project_directory`, `session`, `session_context_epoch`,
`session_input`, `session_message`, `session_share`, `todo`, `workspace`. A session row carries
`cost`, `tokens_input`, `tokens_output`, `tokens_reasoning`, `tokens_cache_read`,
`tokens_cache_write`, `agent`, `model`, `revert`, `permission`, `time_compacting`, `time_archived`.

**A provider outage** surfaces as `session.status` = `retry` and `session.next.retried` events rather
than a lost session — see §E.

---

## C. TRANSCRIPT

**On disk:** a single SQLite database, not JSONL files.

| Path | What | Tag |
|---|---|---|
| `~/.local/share/opencode/opencode.db` (+ `-wal`, `-shm`) | everything | VERIFIED (`opencode db path`) |
| `~/.local/share/opencode/log/` | rotated logs, `2026-…T….log`, newest 10 kept | CLAIMED (docs) / dir VERIFIED |
| `~/.local/state/opencode/locks/` | cross-instance locks | VERIFIED (created on this machine) |
| `~/.local/share/opencode/repos/` | cloned repos | VERIFIED |

Override the database path with **`OPENCODE_DB`** (VERIFIED, read in the binary's `RuntimeFlags`).

**Reading it live, three ways — all VERIFIED:**

1. **SSE, live.** `GET /api/event` (v2) or `GET /event` (v1). Captured here while a prompt was
   admitted:
   ```
   data: {"id":"evt_…","type":"session.next.prompt.admitted","durable":{"aggregateID":"ses_orchestratortest0001","seq":3,"version":1},"location":{"directory":"…/proj"},"data":{"timestamp":1789824049496,"sessionID":"ses_orchestratortest0001","messageID":"msg_…","prompt":{"text":"third nudge"},"delivery":"steer"}}
   data: {"id":"evt_…","type":"session.updated","durable":{…,"seq":4,…},"data":{"sessionID":"…","info":{…,"cost":0,"tokens":{…},"title":"orchestrator smoke test",…}}}
   ```
   The stream sends `: heartbeat` comments, so a dead stream is distinguishable from a quiet one.
   Note the envelope differs between versions: v1 `/event` uses `properties`, v2 `/api/event` uses
   `data` + `durable`. Pick v2; only v2 carries the sequence number you need for §B.
2. **Paged pull.** `GET /api/session/{id}/history?after=&limit=`, `GET /api/session/{id}/message`,
   `GET /api/session/{id}/message/{messageID}`.
3. **Direct SQL.** `opencode db "<SQL>" --format json|tsv` (VERIFIED). Useful for a supervisor that
   wants to read a session it is not attached to, or after the server has exited.

**Export.** `opencode export [sessionID] [--sanitize]` writes the session as JSON; `opencode import
<file|url>` reads it back. `--sanitize` "redact[s] sensitive transcript and file data" (VERIFIED,
`--help`) — relevant if transcripts leave the machine.

**Event vocabulary.** 180+ typed event names in the schema. The ones an orchestrator watches:
`session.created`, `session.updated`, `session.idle`, `session.error`, `session.status`,
`session.compacted`, `session.next.prompt.admitted`, `session.next.prompted`,
`session.next.step.started/.ended/.failed`, `session.next.tool.called/.success/.failed/.progress`,
`session.next.text.started/.delta/.ended`, `session.next.reasoning.*`, `session.next.retried`,
`session.next.compaction.started/.delta/.ended`, `session.next.context.updated`,
`permission.v2.asked/.replied`, `question.v2.asked/.replied/.rejected`, `todo.updated`,
`file.edited`, `server.connected`. (VERIFIED, enumerated from the served schema.)

---

## D. CONTEXT — *non-negotiable axis*

**Compaction can be triggered from outside with a one-line call, and it leaves three independent
proofs.** This is the cleanest answer to this axis in the whole field.

**Trigger.** `POST /api/session/{sessionID}/compact` — **no request body at all** (VERIFIED, OpenAPI:
the operation declares only the `sessionID` path parameter). The v1 equivalent
`POST /session/{sessionID}/summarize` does take a body: `{providerID, modelID, auto?}`.

**Proof, three ways:**

1. **Events.** `session.next.compaction.started` carries `{timestamp, sessionID, messageID, reason}`
   where **`reason` is the enum `"auto" | "manual"`** — so the orchestrator can prove its *own*
   compaction ran, distinguished from one opencode started by itself.
   `session.next.compaction.ended` carries the same plus **`text`** (the summary that was written)
   and **`recent`**. There is also a streaming `session.next.compaction.delta`, and a coarse
   `session.compacted`. (VERIFIED, schemas.)
2. **Database.** `session_context_epoch(session_id PRIMARY KEY, baseline, snapshot, baseline_seq)` —
   one row per session recording the sequence number the context was cut at. Plus
   `session.time_compacting` on the session row. (VERIFIED, DDL.)
3. **Read-back.** `GET /api/session/{sessionID}/context` — *"Retrieve the active context messages for
   a session (all messages after the last compaction)"* (VERIFIED, and it returned `{"data":[]}` for
   a fresh session here). Compare the array before and after.

**Reading how full the window is.** There is **no single "context is 74% full" field** — that is the
one real gap on this axis. But everything needed to compute opencode's own answer is exposed:

- `Model.limit` = `{context: number, input?: number, output: number}` per model, served at
  `GET /provider`. Observed live: `claude-sonnet-4-6` → `{"context":1000000,"output":128000}`;
  `mimo-v2.5-pro` (provider `xiaomi-token-plan-sgp`) → `{"context":1048576,"output":131072}`.
  (VERIFIED.)
- `session.next.step.ended.data.tokens` = `{input, output, reasoning, cache:{read, write}}` per step
  — the last step's `input + cache.read` is the live context occupancy.
- `config.compaction.reserved` is the headroom opencode itself subtracts.
- The binary's own decision function is `SessionCompaction.isOverflow({cfg, tokens, model,
  outputTokenMax})` (VERIFIED, read in the bundle) — i.e. exactly those three inputs. An orchestrator
  replicating it will agree with opencode.

**Configuring compaction** (VERIFIED, `Config.compaction` schema):

```json
"compaction": { "auto": true, "prune": false, "tail_turns": 4,
                "preserve_recent_tokens": 20000, "reserved": 10000 }
```

`OPENCODE_DISABLE_AUTOCOMPACT=1` sets `compaction.auto=false` and `OPENCODE_DISABLE_PRUNE=1` sets
`compaction.prune=false` — both VERIFIED by reading the config loader in the bundle. An orchestrator
that wants to own compaction timing turns auto off by environment variable alone, no config edit.

**Custom compaction is a first-class hook.** From `@opencode-ai/plugin@1.18.31` typings (VERIFIED):

```ts
"experimental.session.compacting"?: (input: { sessionID: string },
  output: { context: string[]; prompt?: string }) => Promise<void>
```
*"Called before session compaction starts. Allows plugins to customize the compaction prompt.
`context`: Additional context strings appended to the default prompt. `prompt`: If set, replaces the
default compaction prompt entirely."*

```ts
"experimental.compaction.autocontinue"?: (input: { sessionID, agent, model, provider, message,
  overflow: boolean }, output: { enabled: boolean }) => Promise<void>
```
*"Called after compaction succeeds and before a synthetic user auto-continue message is added.
`enabled`: Defaults to true. Set to false to skip the synthetic user 'continue' turn."*

The compaction agent itself is configurable: `config.agent.compaction` is a full `AgentConfig`
(`model`, `variant`, `prompt`, `tools`, `temperature`, …) — so compaction can be run on a cheap model
while the main loop runs on an expensive one. There is also a `ContextOverflowError` type for the
case where compaction could not save it.

---

## E. QUOTA — *non-negotiable axis, and the one opencode fails*

**There is no way to read remaining capacity programmatically. This is a VERIFIED negative, not an
unknown.** The words `quota`, `ratelimit`, `rate_limit`, `remaining`, `reset` and `balance` do not
appear as any field name anywhere in the 478,968-byte OpenAPI document served by the running binary.
No endpoint reports a limit, a window or a reset time.

**What exists instead is spend accounting, after the fact:**

- `opencode stats [--days N] [--models] [--tools] [--project P]` — sessions, messages, total cost,
  avg cost/day, input/output/cache tokens. Executed here; it is purely local arithmetic over the
  SQLite rows. (VERIFIED.)
- `session.cost` and `session.tokens` on every session object and in every `session.updated` event.
- `session.next.step.ended.data.cost` per step.
- `Model.cost` = `{input, output, cache:{read,write}, tiers[]}` and `ModelCost.tier` =
  `{type:"context", size}` for long-context pricing tiers.

So an orchestrator can know **exactly what it has spent** and never what it has left.

**The limit-hit signal IS in-band, and it is unusually rich.** This is the mitigation, and it is a
good one:

- `GET /session/status` returns a map `sessionID → status`, where status is one of
  `{"type":"idle"}`, `{"type":"busy"}`, or
  ```
  {"type":"retry","attempt":<int>,"message":<string>,"next":<int>,
   "action":{"reason":<string>,"provider":<string>,"title":<string>,
             "message":<string>,"label":<string>,"link":<string>}}
  ```
  (VERIFIED, `SessionStatus` schema). `next` is an integer — semantics **UNKNOWN**; it is either a
  delay or an absolute time and I could not establish which without provoking a real 429.
- The `session.next.retried` event carries `{timestamp, sessionID, attempt, error}` where `error` is
  `{message, statusCode?, isRetryable, responseHeaders?: Record<string,string>, responseBody?,
  metadata?}` (VERIFIED). **`responseHeaders` is the critical field:** a 429 from Anthropic arrives
  with `anthropic-ratelimit-*` and `retry-after` headers, and opencode hands the whole header map to
  the supervisor. That is a reset time — reactively, at the moment of the hit, rather than
  predictively before it.
- The TUI has a dedicated usage-exceeded dialog with keys
  `dialog.usageExceeded.accountRateLimit.{title,description,actionLabel}` and
  `dialog.usageExceeded.freeTier.*`. English strings: *"Go limit reached"*, *"Usage limit reached. To
  continue using this model now…"*, *"Subscribe to OpenCode Go for reliable access to the best
  open-source models for $10/month."* (VERIFIED, binary strings.) So opencode **knows** when a limit
  is hit; it renders it to a human and does not expose it as a number.

**Windows.** They belong to whichever provider is behind the session, not to opencode:
- **opencode Zen** (`provider: opencode`, env `OPENCODE_API_KEY`) — pay-as-you-go credit balance,
  auto-reload +$20 when below $5, optional workspace/per-member monthly caps (CLAIMED, docs/zen). No
  documented balance endpoint.
- **opencode Go** (`provider: opencode-go`, env `OPENCODE_API_KEY`) — $10/month subscription with an
  account rate limit (VERIFIED from binary strings; window length UNKNOWN).
- **Anthropic / OpenAI / Xiaomi / Kimi / Z.AI subscriptions** — their own windows, read from their
  own endpoints. The owner's existing `claude-limits` helper against
  `https://api.anthropic.com/api/oauth/usage` keeps working and is **outside** opencode.

**Cost to the orchestrator:** the pre-flight "are we under 80%?" check the owner insists on cannot be
answered by opencode. It must be answered by querying each provider directly, keyed on which provider
that session is configured to use — and opencode does tell you that (`session.model.providerID`).

---

## F. ACCOUNTS — *non-negotiable axis*

Three mechanisms, at different scopes. Getting this right matters because the obvious one is the
wrong one for an orchestrator.

**1. Per-provider credentials — the right lever, and it is per-session-capable.**
Every provider declares its own env var, and providers are independent, so "switching accounts per
role" is really "point role A at provider X's key and role B at provider Y's key". Observed live at
`GET /provider` (VERIFIED): **222 providers**, including

| Provider id | Name | Env var |
|---|---|---|
| `anthropic` | Anthropic | `ANTHROPIC_API_KEY` |
| `openai` | OpenAI | `OPENAI_API_KEY` |
| `opencode` | OpenCode Zen | `OPENCODE_API_KEY` |
| `opencode-go` | OpenCode Go | `OPENCODE_API_KEY` |
| `xiaomi-token-plan-sgp` | Xiaomi Token Plan (Singapore) | `XIAOMI_API_KEY` |
| `kimi-code-plan-global` | Kimi For Coding (kimi.ai) | `KIMI_API_KEY` |
| `zai-coding-plan` | Z.AI Coding Plan | `ZHIPU_API_KEY` |
| `minimax-coding-plan` | MiniMax coding plan | (present; var UNKNOWN) |

**Directly relevant to this owner:** `xiaomi-token-plan-sgp` is exactly the Singapore token-plan
endpoint already configured on his machine in `~/.config/claude-mimo/env`. In opencode it is a
built-in provider with a model catalogue — `mimo-v2.5-pro`, context `1048576`, output `131072` — not
an `ANTHROPIC_BASE_URL` override. The same is true of Kimi, GLM/Z.AI and MiniMax. **The "several
platforms are one adapter with different env vars" observation from the field scan collapses
entirely inside opencode: they are all just provider ids.**

Two ways to bind a key to a session without touching the owner's files:
- Environment on the server process, per provider.
- `config.provider.<id>.options.apiKey` with substitution — `{env:VAR}` or `{file:path}` (CLAIMED,
  docs/config) — delivered through **`OPENCODE_CONFIG_CONTENT`** (inline JSON) or **`OPENCODE_CONFIG`**
  (a file path), both read by the config loader (VERIFIED in the bundle). Also
  `config.provider.<id>.options.baseURL` for a regional or proxy endpoint.

Per-session model/provider selection: `POST /api/session` with `model:{providerID,id,variant}`, or
switch mid-flight with `POST /api/session/{sessionID}/model` (body `{model:{providerID,id,variant?}}`)
and `POST /api/session/{sessionID}/agent`. (VERIFIED.) **So a running session's provider CAN be
changed — this is one of the very few platforms where that is true.**

Credentials otherwise live in the `credential` table (`id, integration_id, label, value,
connector_id, method_id, active, …`) and are managed by `opencode providers` (alias `auth`),
`PUT /auth/{providerID}`, `DELETE /auth/{providerID}`, and
`POST /api/integration/{integrationID}/connect/key|oauth`. `OPENCODE_AUTH_CONTENT` also exists
(VERIFIED as a name; exact format UNKNOWN). Interactive OAuth is available for `openai` (ChatGPT
Pro/Plus, browser **and headless**), `github-copilot`, `gitlab`, `poe`, `digitalocean`,
`snowflake-cortex`, `xai` (SuperGrok) — VERIFIED from `GET /provider/auth`. Anthropic appears there
with an API-key path only; "Claude Pro/Max" login strings exist in the binary, so a subscription
login very likely exists too, but I could not confirm it from the auth-methods endpoint — **UNKNOWN**.

**2. opencode Console accounts — global, one at a time. Do not build on this.**
The database has `account(id, email, url, access_token, refresh_token, token_expiry, …)` — several
accounts — but `account_state(id INTEGER PRIMARY KEY, active_account_id, active_org_id)` holds
**exactly one active pair** (VERIFIED, DDL; the repo code selects `WHERE id = 1`). The API is
`GET /experimental/console/orgs` → `{orgs:[{accountID, accountEmail, accountUrl, orgID, orgName,
active}]}` and `POST /experimental/console/switch` with `{accountID, orgID}` → boolean (VERIFIED).
The config loader then fetches `${url}/api/config` for the active org and sets
`OPENCODE_CONSOLE_TOKEN` (VERIFIED in the bundle).

**The constraint an orchestrator must respect: this switch is global to the opencode state
directory, not per session. Two sessions under two different Console accounts cannot run
concurrently in one opencode instance.**

**3. The workaround for full isolation — one state directory per account.**
Run one `opencode serve` per account, each with its own `HOME`/`XDG_DATA_HOME` (or just
**`OPENCODE_DB`** + **`OPENCODE_CONFIG_DIR`**), on its own port. Cost: one ~145 MB binary is shared,
but each server is a separate process; sessions are no longer visible to each other; and the
orchestrator must keep a port↔account map. This is the same shape as the owner's existing profile-switcher
`CLAUDE_CONFIG_DIR` trick, and it is cheap. **Unlike Claude Code, no macOS Keychain is involved, so
there is no "blocks on a GUI dialog at 03:00" failure mode here** — credentials are rows in SQLite.

---

## G. INTERVENTION — *non-negotiable axis, and opencode's best result*

**Every part of this axis is answered, and the hardest part was proved empirically on this machine.**

**Sending an instruction into a running session, and knowing it arrived.**
`POST /api/session/{sessionID}/prompt` — *"Durably admit one session input and schedule agent-loop
execution unless resume is false."* Body:

```json
{ "id": "msg_…",                       // optional; the caller may name the message too
  "prompt": { "text": "…", "files": [...], "agents": [...] },
  "delivery": "steer" | "queue",
  "resume": true | false }
```

Response: `{"data":{"admittedSeq":<int>, "id":"msg_…", "sessionID":"ses_…", "prompt":{…},
"delivery":"…", "timeCreated":…, "promotedSeq"?:…}}`. (VERIFIED, OpenAPI.)

Executed here against a live server (VERIFIED):

```
POST /api/session/ses_orchestratortest0001/prompt
  {"id":"msg_orchtest00000000001","prompt":{"text":"hello"},"delivery":"queue","resume":false}
→ {"data":{"admittedSeq":1,"id":"msg_orchtest00000000001","sessionID":"ses_orchestratortest0001",
           "prompt":{"text":"hello"},"delivery":"queue","timeCreated":1789823981951}}
```

and the same instant, in SQLite:

```
session_input:  delivery=queue  admitted_seq=1  promoted_seq=null
event:          aggregate_id=ses_orchestratortest0001  seq=1  type=session.next.prompt.admitted.1
```

**Read that against the harness field notes.** The recorded defect there is *"a nudge that cannot
submit stranded text"* — the orchestrator types into a session and cannot tell whether it landed.
Here, arrival is (a) acknowledged synchronously with a monotonic `admittedSeq`, (b) persisted as a
row, (c) re-emitted on the event stream as `session.next.prompt.admitted` with `durable.seq`, and
(d) replayable afterwards from `history?after=`. **Text cannot be stranded, by construction.**

`delivery` is the distinction the harness never had: **`"steer"`** interrupts and redirects the
running turn; **`"queue"`** waits for the current turn to finish. `resume: false` admits the input
*without* starting the agent loop — an orchestrator can pre-load a work queue into a session and
release it later.

**Answering the session's own question programmatically.** `question` is a registered tool
(`GET /experimental/tool/ids` returned `["invalid","question","bash","read","glob","grep","edit",
"write","task","webfetch","todowrite","websearch","skill","apply_patch"]`, VERIFIED). When it fires:

- `GET /api/session/{sessionID}/question` or `GET /api/question/request?location[directory]=…` lists
  pending requests: `{id:"que…", sessionID, questions:[{question, header, options:[{label,
  description}], multiple, custom}]}`.
- `POST /api/session/{sessionID}/question/{requestID}/reply` with
  `{"answers": [["label1"], ["label2","label3"]]}` — *"User answers in order of questions (each
  answer is an array of selected labels)"*.
- `POST /api/session/{sessionID}/question/{requestID}/reject` to decline.
- Events `question.v2.asked` / `.replied` / `.rejected` announce it on the stream.

(All VERIFIED from the served schema.) The tool appears to be gated by
`OPENCODE_ENABLE_QUESTION_TOOL` and by the `question` permission key; the endpoints exist regardless.

**Answering a permission prompt programmatically.**
`GET /api/session/{sessionID}/permission` → `[{id:"per…", sessionID, action, resources[], save[],
metadata, source:{type:"tool", messageID, callID}}]`, then
`POST /api/session/{sessionID}/permission/{requestID}/reply` with
`{"reply": "once" | "always" | "reject", "message"?: "…"}`. Events `permission.v2.asked` /
`.replied`. (VERIFIED.) A second, in-process route exists: the plugin hook
`"permission.ask"?: (input: Permission, output: {status: "ask"|"deny"|"allow"}) => Promise<void>`
(VERIFIED, typings) lets policy live inside opencode rather than in the supervisor's poll loop.

**Stopping and waiting.** `POST /api/session/{sessionID}/interrupt` (*"Interrupt active execution
owned by this OpenCode process. Idle interruption is a no-op."*), `POST /session/{sessionID}/abort`,
and `POST /api/session/{sessionID}/wait` (*"Wait for a session agent loop to become idle"*) — a
blocking call, so an orchestrator does not have to poll. `GET /api/session/active` returns
`{data: {"ses_…": {"type":"running"}}}` for foreground work owned by this process. (VERIFIED.)

**Driving the owner's own terminal.** If the owner is watching a TUI, the supervisor can write into
it: `POST /tui/append-prompt`, `POST /tui/submit-prompt`, `POST /tui/clear-prompt`,
`POST /tui/execute-command`, `POST /tui/show-toast`, `POST /tui/select-session`,
`POST /tui/open-models|sessions|themes|help`, plus a request queue
(`GET /tui/control/next`, `POST /tui/control/response`). **Append *and* submit are separate
endpoints** — the exact pair the old harness lacked. (VERIFIED.)

**Owning a terminal outright.** `POST /pty` creates a pseudo-terminal, `GET /pty/{ptyID}/connect`
upgrades to a WebSocket streaming output and accepting input, `POST /pty/{ptyID}/connect-token` mints
a short-lived single-use ticket, `PUT /pty/{ptyID}` resizes, `DELETE /pty/{ptyID}` kills it, and
`GET /pty/{ptyID}` reports the exit code once exited. (VERIFIED.) This matters against another field
note: *"a shell that can never exit reading as work"* — here a PTY reports a real exit code.

---

## H. GUARDRAILS

**Unattended defaults are permissive. This is the single biggest operational risk on this
platform and the orchestrator must override it explicitly.**

Per docs/permissions (CLAIMED, but consistent with the `PermissionActionConfig` enum
`"ask" | "allow" | "deny"` which is VERIFIED): with no permission config, **most permissions default
to `"allow"`**; only `doom_loop` and `external_directory` default to `"ask"`; `read` allows
everything except `.env` files. So `bash` and `edit` run unattended without asking, out of the box.

**Permission keys** (VERIFIED from `PermissionConfig`): `read`, `edit`, `glob`, `grep`, `list`,
`bash`, `task`, `external_directory`, `todowrite`, `question`, `webfetch`, `websearch`, `lsp`, plus
`skill` and `doom_loop` from the docs. Each is `"ask"|"allow"|"deny"` or an object of pattern rules;
`*` and `?` wildcards, `~`/`$HOME` expansion, **last matching rule wins** (CLAIMED, docs).

**Setting policy without touching the owner's config** — this is the clean orchestrator lever, and it
is VERIFIED by reading the config loader in the bundle:

```
if(k.OPENCODE_PERMISSION) try { B.permission = merge(B.permission ?? {}, JSON.parse(k.OPENCODE_PERMISSION)) }
catch(G){ logWarning("OPENCODE_PERMISSION contains invalid JSON, skipping", {err:G}) }
```

So `OPENCODE_PERMISSION='{"bash":"ask","edit":"allow","external_directory":"deny"}'` on the server
process is enough. **Note the failure mode: invalid JSON is silently skipped with a log warning, not
an error** — a typo in the supervisor's policy string yields a wide-open session that still starts.
Validate the JSON before launch.

Other levers: per-agent overrides (`config.agent.<name>.permission`, and `AgentConfig` also has
`tools`, `disable`, `steps`, `maxSteps`), `config.tools` as a boolean map (VERIFIED: it is translated
into permissions, with `write`/`edit`/`patch` collapsing onto `edit`), `--auto` on `run` and `tui`
("auto-approve permissions that are not explicitly denied (dangerous!)" — its own help says so),
`experimental.continue_loop_on_deny`, and `experimental.policies` of shape
`{action:"provider.use", effect, resource}` — a provider allow/deny list.

**Saved decisions** persist in the `permission` table (`project_id, action, resource`) and are
readable/removable via `GET /api/permission/saved` and `DELETE /api/permission/saved/{id}` — so
"always allow" answers given at 02:00 are auditable in the morning.

**Sandboxing.** A Docker image exists (`ghcr.io/anomalyco/opencode`, CLAIMED). There is no
built-in OS-level sandbox equivalent to Claude Code's; isolation is the orchestrator's job.
**`config.server.hostname` defaults to `127.0.0.1`, and `serve` prints
`Warning: OPENCODE_SERVER_PASSWORD is not set; server is unsecured.`** (VERIFIED, observed).
Set `OPENCODE_SERVER_PASSWORD` (and optionally `OPENCODE_SERVER_USERNAME`, default `opencode`) for
HTTP basic auth, and never pass `--mdns` (which "defaults hostname to 0.0.0.0") on a shared network.

**Other safety-relevant config:** `snapshot` (boolean), `config.share` = `"manual"|"auto"|"disabled"`
and `OPENCODE_DISABLE_SHARE` (a transcript-exfiltration switch worth pinning to `disabled`),
`autoupdate` = `true|false|"notify"` and `OPENCODE_DISABLE_AUTOUPDATE` (**pin this off — an
unattended fleet must not upgrade itself mid-run**), `tool_output.{max_lines,max_bytes}`,
`watcher.ignore`, `OPENCODE_PURE` / `--pure` to run with no external plugins.

---

## I. EXTENSIBILITY

**Strong, and unusually well aligned with what this owner already has.**

**It reads Claude Code's content.** `OPENCODE_DISABLE_EXTERNAL_SKILLS=1` and
`OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` *"skip the external skill scans under `~/.claude/` and
`~/.agents/`"* — quoted verbatim from the binary (VERIFIED). `CLAUDE.md` and `AGENTS.md` are both
discovered as instruction files (VERIFIED, binary strings). `OPENCODE_DISABLE_CLAUDE_CODE` /
`_PROMPT` / `_SKILLS` are the three off-switches. **The owner's GSD skill library in `~/.claude/skills`
is visible to opencode today, without migration.** Whether every GSD skill *behaves* identically is
UNKNOWN and needs a real trial run.

**Agents and subagents.** `config.agent.<name>` with `AgentConfig` = `{model, variant, temperature,
top_p, prompt, tools, disable, description, mode, hidden, options, color, steps, maxSteps,
permission}` (VERIFIED). Built-in slots: `plan`, `build`, `general`, `explore`, `title`, `summary`,
`compaction`. `mode` is `"all"|"primary"|"subagent"`. `config.subagent_depth` caps nesting. The
`task` tool launches subagents; `opencode agent create --path --description --mode --permissions
--model` and `opencode agent list` manage them. `GET /api/agent`, `POST /api/session/{id}/agent` to
switch mid-session. `experimental.backgroundSubagents` exists as a capability flag (observed
`false` here) with `POST /experimental/session/{sessionID}/background` to *"detach any synchronous
subagents currently blocking the session and continue them in the background"*. **A GSD-style
subagent-heavy workflow engine has everything it needs.** (VERIFIED.)

**Commands and skills.** `GET /command`, `GET /api/command`, `POST /session/{id}/command`,
`GET /api/skill`, `GET /skill`; `config.skills = {paths[], urls[]}`; `.opencode/skills` and
`.opencode/bin` are scanned. Slash commands are callable over HTTP.

**MCP.** Full lifecycle over HTTP: `GET /mcp` (status), `POST /mcp` (add at runtime),
`POST /mcp/{name}/connect` / `/disconnect`, `POST /mcp/{name}/auth`, `/auth/authenticate`,
`/auth/callback`, `DELETE /mcp/{name}/auth`; CLI `opencode mcp add|list|auth|logout|debug`;
config `mcp` with `McpLocalConfig` / `McpRemoteConfig` / `McpOAuthConfig`. Status enum includes
`MCPStatusConnected|Disabled|Failed|NeedsAuth|NeedsClientRegistration` — **an orchestrator can detect
a dead MCP server and reconnect it without restarting the session.** `GET /experimental/resource`
lists MCP resources. (VERIFIED.)

**Plugins.** `.opencode/plugins/` and `~/.config/opencode/plugins/`; `opencode plugin <module> [-g]
[-f]`; `config.plugin: Array<string | [string, options]>`. Complete hook list, VERIFIED from
`@opencode-ai/plugin@1.18.31` typings: `dispose`, `event`, `config`, `tool`, `auth`, `provider`,
`chat.message`, `chat.params`, `chat.headers`, `permission.ask`, `command.execute.before`,
`tool.execute.before`, `tool.execute.after`, `shell.env`, `tool.definition`,
`experimental.chat.messages.transform`, `experimental.chat.system.transform`,
`experimental.provider.small_model`, `experimental.session.compacting`,
`experimental.compaction.autocontinue`, `experimental.text.complete`. Plugin input is
`{client, project, directory, worktree, serverUrl, $, experimental_workspace}` — note `client` is a
full SDK client, so **a plugin can call the orchestrator's own HTTP API from inside a session**.
Plugins can also register custom tools and whole providers and auth methods (`AuthHook` with `oauth`
and `api` methods, including headless flows).

**Config precedence** (CLAIMED, docs; the loader order was VERIFIED in the bundle): remote
`.well-known/opencode` → `~/.config/opencode/opencode.json` → `OPENCODE_CONFIG` → project
`opencode.json` → `.opencode/` directories → `OPENCODE_CONFIG_CONTENT` → managed config in
`/Library/Application Support/opencode/` → macOS managed preferences via MDM. Files **merge**, they
do not replace. `OPENCODE_DISABLE_PROJECT_CONFIG=1` ignores the project layer.

**Worktrees and workspaces.** `GET/POST/DELETE /experimental/worktree` and
`POST /experimental/worktree/reset` create and destroy git worktrees with startup scripts;
`/experimental/workspace*` and `/sync/*` move sessions between them;
`POST /experimental/control-plane/move-session` moves a session to another project directory. For a
queue running many tickets in parallel against one repo, this is native branch isolation.

---

## J. OPERATIONAL REALITY

**Install & footprint.** `curl -fsSL https://opencode.ai/install | bash`, `npm i -g opencode-ai`,
`brew install anomalyco/tap/opencode`, bun/pnpm/yarn, pacman/AUR, choco/scoop, Docker, or a GitHub
release binary (CLAIMED, docs). macOS/Linux/Windows; Windows via WSL recommended. The npm path
downloads a platform binary in `postinstall.mjs` — **~145 MB on macOS arm64** (VERIFIED, measured).
Install here took ~60 s. No Node runtime is needed at run time (it is a Bun-compiled single file);
the npm package needs Node only for the postinstall shim.

**Cost model.** MIT, free. You pay whichever provider you point it at; opencode's own products are
Zen (pay-as-you-go credits) and Go ($10/month). **`opencode stats` will tell you what you spent;
nothing will tell you what you have left** (§E).

**Maturity.** 208,547 stars, 16 months old, near-daily commits, v1.18.31 with a stable v1 API *and* a
newer `/api/v2` surface running alongside it. **5,939 open issues** is the number to hold next to the
star count — this ships fast and carries a large backlog. The v1/v2 split is itself a hazard: several
concepts exist twice with different envelopes (`/event` vs `/api/event`, `/session/{id}/summarize`
vs `/api/session/{id}/compact`, `permission.asked` vs `permission.v2.asked`). **Pick v2 and never mix.**

**Known unattended failure modes — one found by running it here, the rest read:**

1. **`run --attach <url> --session <id> --dir <dir>` hangs forever with zero output.** Reproduced
   twice on 1.18.31 / darwin 25.5.0: exit 124 after a 30 s external timeout, 0 bytes on stdout and
   stderr, nothing in the server log, no event emitted. Dropping `--dir` works; dropping `--session`
   works. All three together hang. (VERIFIED, reproduced.) **An orchestrator using `run --attach`
   must impose its own wall-clock timeout — the process will not tell you it is stuck.**
2. **`OPENCODE_PERMISSION` with malformed JSON is silently skipped** and the session starts with
   default (permissive) permissions (VERIFIED, read in the loader).
3. **`serve` starts unsecured by default** and says so on stderr only
   (`Warning: OPENCODE_SERVER_PASSWORD is not set; server is unsecured.`) (VERIFIED, observed).
4. **Autoupdate is on by default** — an overnight fleet can change version under itself unless
   `autoupdate: false` / `OPENCODE_DISABLE_AUTOUPDATE=1`.
5. `run --format json` returned **exit 0 in one invocation and exit 1 in another for the same class
   of error** (the first was through a pipe to `head`, so `$?` was the pipeline's). Read the exit
   code with no pipeline in between. (VERIFIED.)
6. Docs list plugin-related crashes/hangs, cache corruption and "Connection Failed"/splash-freeze as
   known issues (CLAIMED, docs/troubleshooting).
7. Whether `session.status.retry.next` is a delay or an absolute timestamp is **UNKNOWN**.
8. Long-run behaviour of the SQLite store — WAL growth, lock contention across many concurrent
   sessions in `~/.local/state/opencode/locks/` — is **UNKNOWN**; it was not exercised here.

**Is it plausible to run unattended overnight today?** **Yes — more plausible than anything else in
this scan, on every axis except quota.** It has a supervisable control plane, exactly-once resume,
in-band question and permission answering with acknowledgement, externally-triggered compaction with
proof, and a 222-provider catalogue that already contains this owner's Xiaomi, Kimi and Z.AI plans.
The one thing it cannot do is tell you how much capacity is left before you start.

---

## What this costs the orchestrator

**What you get nearly free.**

- **The adapter is an HTTP client, not a terminal scraper.** One `opencode serve` plus the generated
  SDK (`@opencode-ai/sdk`, `createOpencodeClient({baseUrl})`) or plain `curl`. No PTY parsing, no
  screen scraping, no "is that prompt waiting for me?" heuristics.
- **Session identity is yours to assign.** `POST /api/session {"id":"ses_<yourticketid>"}`. The
  orchestrator's ticket id *is* the session id. No id-scraping, no mapping table.
- **Crash recovery is a single integer.** Persist `durable.seq` per session; resume with
  `GET /api/session/{id}/event?after=<seq>`. No replay ambiguity.
- **Intervention is acknowledged.** `POST …/prompt` → `admittedSeq`. The class of bug the field
  notes record — a nudge that cannot submit stranded text — is structurally impossible here.
- **Compaction is a bodyless POST with `reason:"manual"` in the proof event.**
- **Provider fan-out is configuration, not code.** Xiaomi/Kimi/GLM/MiniMax are provider ids with
  their own env vars, not base-URL hacks.
- **The owner's `~/.claude/skills` are already on opencode's search path.**

**What you must build yourself.**

1. **Quota, entirely.** Per provider, out of band, keyed on `session.model.providerID`. For Anthropic
   that is the owner's existing `api.anthropic.com/api/oauth/usage` helper; for Zen/Go/Xiaomi/Kimi
   there may be no endpoint at all (UNKNOWN). Budget a provider-quota module; it is the largest piece
   of genuinely new work this platform implies.
2. **A reactive limit handler.** Subscribe to `session.status` and `session.next.retried`; on
   `type:"retry"`, parse `error.responseHeaders` for `retry-after` / `anthropic-ratelimit-*`, and
   treat `action.reason` as the human-readable cause. Design the queue to *survive* hitting a limit
   rather than to avoid it — that inversion is forced by §E and is arguably healthier anyway.
3. **A context-fullness estimator.** `last step.ended tokens.input + tokens.cache.read` vs
   `Model.limit.context` minus `compaction.reserved`. Roughly 30 lines, and it will agree with
   `SessionCompaction.isOverflow`.
4. **Account isolation, if roles need different Console accounts.** One `serve` per account with its
   own `OPENCODE_DB` + `OPENCODE_CONFIG_DIR` (or `HOME`) and port. If roles only need different
   *provider keys*, skip this entirely — that is per-session already.
5. **A hard wall-clock timeout on every `run --attach` invocation**, because of failure mode J-1.
6. **A launch preamble** that pins the unsafe defaults: `OPENCODE_PERMISSION` (validated as JSON
   first), `OPENCODE_DISABLE_AUTOUPDATE=1`, `OPENCODE_SERVER_PASSWORD`, `share:"disabled"`,
   and `OPENCODE_DISABLE_AUTOCOMPACT=1` if the orchestrator wants to own compaction timing.
7. **A v1/v2 discipline rule.** Two API generations run side by side with different envelopes. Write
   the adapter against `/api/*` only and pin the opencode version.

**The honest comparison.** Against the harness's current Claude Code target, opencode trades *one*
capability for *five*. It loses readable quota — which Claude Code gives the owner today via
`api.anthropic.com/api/oauth/usage`, already wired into `~/.config/claude-profiles/profiles.sh`.
It gains: assigned session ids, exactly-once event replay, acknowledged intervention, programmatic
question and permission answering, externally-triggered compaction with typed proof, mid-session
model and provider switching, and a PTY that reports real exit codes. Four of those five are named in
`plugins/harness/docs/FIELD-NOTES.md` as things the current harness cannot do.

---

## Sources

All consulted 2026-09-19.

**Run on this machine (VERIFIED):**
- `opencode-ai@1.18.31` installed to a sandbox; `opencode --version`, `--help`, and per-command
  `--help` for `run`, `serve`, `acp`, `session`, `stats`, `db`, `export`, `import`.
- Live OpenAPI 3.1 document from `GET http://127.0.0.1:4199/doc` (478,968 bytes; 472 component
  schemas; ~190 operations).
- Live endpoints: `/global/health`, `/config`, `/global/config`, `/experimental/capabilities`,
  `/experimental/console`, `/experimental/console/orgs`, `/provider`, `/provider/auth`,
  `/session/status`, `/experimental/tool/ids`, `/api/skill`, `/api/session` (POST with chosen id),
  `/api/session/{id}` , `/api/session/{id}/prompt` (POST ×3), `/api/session/{id}/context`,
  `/api/session/{id}/history[?after=]`, `/api/session/{id}/event?after=0`, `/api/event`, `/event`.
- SQLite: `opencode db path`, `sqlite_master` table list, DDL for `account`, `account_state`,
  `control_account`, `credential`, `event`, `event_sequence`, `session`, `session_context_epoch`,
  `session_input`, `permission`; row reads of `session_input` and `event`.
- `opencode stats --models`, `opencode session list --format json`.
- `strings` over `node_modules/opencode-ai/bin/opencode.exe` for the 79 `OPENCODE_*` variables, the
  config loader, `RuntimeFlags`, `SessionCompaction`, `AccountRepo`, and the `dialog.usageExceeded.*`
  locale keys.
- `@opencode-ai/plugin@1.18.31` `dist/index.d.ts` — the `Hooks` interface, verbatim.
- Reproduction of the `run --attach --session --dir` hang (2 attempts, 30 s each, exit 124).

**Registries and APIs (VERIFIED):** npm `opencode-ai`, `@opencode-ai/sdk`, `@opencode-ai/plugin`;
GitHub API `repos/sst/opencode` (redirects to) `repos/anomalyco/opencode` and its releases.

**Official documentation (CLAIMED unless confirmed above):** `https://opencode.ai/docs/`,
`/docs/cli/`, `/docs/server/`, `/docs/config/`, `/docs/permissions/`, `/docs/plugins/`, `/docs/sdk/`,
`/docs/acp/`, `/docs/zen/`, `/docs/troubleshooting/`.

**Not consulted:** no blog posts, comparison articles or listicles were used for any claim.

**Footprint left on this machine:** two empty directories,
`~/.local/share/opencode/log/` and `~/.local/share/opencode/repos/`, created by the npm postinstall
at 20:17. No files were written into them. `~/.config/opencode/opencode.json` is unchanged. All
sandbox state is under
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/oc-sandbox`
and can be deleted.
