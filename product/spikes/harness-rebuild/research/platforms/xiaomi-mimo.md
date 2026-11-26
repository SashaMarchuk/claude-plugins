# Platform profile — Xiaomi MiMo

**Date of research:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0, arm64).
**Scope:** Xiaomi MiMo as an *agent platform an orchestrator would drive* — measured against axes
A–J of the orchestrator contract. Orchestrator tooling itself is out of scope.

**Evidence tags:** **VERIFIED** = read in source, read in official docs, or run on this machine.
**CLAIMED** = vendor/README assertion only. **UNKNOWN** = could not establish.

---

## 0. Verdict up front, and a correction to the field scan

The field scan (`00-field-scan.md` §2) concluded: *"'Xiaomi' is not a separate CLI to adapt. It is
Claude Code pointed somewhere else via two environment variables."*

**That is wrong, and the error matters.** Xiaomi ships **MiMoCode**, a full terminal coding agent —
npm `@mimo-ai/cli`, binary `mimo`, repo `github.com/XiaomiMiMo/MiMo-Code`, MIT, 13,195 stars,
pushed today (VERIFIED). It is a **fork of OpenCode** (stated in its own README) and it inherits
OpenCode's headless HTTP control plane, then adds a persistent-memory layer, an externally
triggerable compaction path, a `session` orchestration tool, and an ACP server.

Measured against this contract, **MiMoCode is the most orchestrator-ready executor examined so
far** — ahead of Claude Code on axes C, D and G. It answers, over plain HTTP on localhost:

- **G (answer a session's own question programmatically)** — `POST /question/:requestID/reply`.
  No other platform in this scan has a *question* channel distinct from a *permission* channel.
- **D (compaction from outside, with proof)** — `POST /session/:id/summarize`, and the proof is a
  SQL column: `session.time_compacting`.
- **C (live transcript)** — a SQLite database with a documented CLI query surface
  (`mimo db "<SQL>" --format json`).

It fails hard on exactly one axis, and it is one the owner called non-negotiable:

- **E (read remaining quota)** — **not possible.** No endpoint, no header, no CLI. See §E.

And there is a live operational problem on this machine: **the owner's stored MiMo credential is
dead.** `~/.config/claude-mimo/env` holds a `tp-…` Token Plan key created 2026-05-09; as of today it
returns `401 {"code":"401","type":"invalid_key"}` on both `token-plan-sgp.xiaomimimo.com` and
`api.xiaomimimo.com` (VERIFIED, §F). Any unattended run that assumed this path works would fail at
the first model call.

### What exists, in coding-agent terms

| Thing | What it is | Tag |
|---|---|---|
| **MiMoCode** (`mimo`) | Terminal coding agent, OpenCode fork, TypeScript/Bun, MIT | VERIFIED |
| **MiMo models** | `mimo-v2.5-pro` (~1T MoE), `mimo-v2.5` (311B), `mimo-v2-flash` (310B) | VERIFIED |
| **Open weights** | HuggingFace org `XiaomiMiMo`, **license `mit`** on Pro / V2.5 / V2-Flash | VERIFIED (HF API) |
| **API** | OpenAI-compatible **and** Anthropic-compatible endpoints | VERIFIED |
| **MiMo Desktop** | Beta GUI app, "powered by MiMo Code as its core engine" | CLAIMED (README) |

So there are **two distinct integration routes**, and they measure very differently:

1. **MiMoCode as executor** — `mimo` drives the work. Rich control plane. This profile's main body.
2. **MiMo as a model behind another executor** — Claude Code (or anything) pointed at
   `…/anthropic`. The executor's own axis answers apply; only E and F change. See §K.

---

## Install state on this machine

Not installed for the owner (VERIFIED): `which mimo` → not found; no `~/.config/mimocode`, no
`~/Library/Application Support/mimocode`.

For this research I installed `@mimo-ai/cli@0.1.14` into an isolated sandbox
(`…/scratchpad/mimo-probe`) with `MIMOCODE_HOME` pointed at a scratch directory and
`MIMOCODE_DISABLE_CLAUDE_IMPORT=1`. **Nothing in the owner's home was created or modified**
(re-verified after the run). No model call was made; no quota was spent. Every flag, route, path and
SQL column quoted below was read from that copy or from the repo source at the same version.

| Fact | Value | Tag |
|---|---|---|
| Version tested | `0.1.14`, published **2026-09-02** | VERIFIED (`mimo --version`) |
| Release cadence | 14 GitHub releases since 2026-06-24; ~weekly | VERIFIED (GitHub API) |
| Disk footprint | `node_modules` **97 MB**; `MIMOCODE_HOME` after first run **62 MB** | VERIFIED (`du -sh`) |
| Platform binaries | `darwin-arm64`, `darwin-x64`(+baseline), `linux-x64/arm64`(+musl/baseline), `windows-x64/arm64` | VERIFIED (npm `optionalDependencies`) |

**First-run cost, and a footgun.** The first `mimo` invocation performs a one-time SQLite migration
("Performing one time database migration, may take a few minutes…") and then, unless
`MIMOCODE_DISABLE_CLAUDE_IMPORT` is set, **silently imports the owner's Claude Code sessions** from
`~/.claude/projects` into its own database (VERIFIED in `src/index.ts`; also exposed as
`mimo session import-claude`). A supervisor that launches `mimo` for the first time unattended, in a
normal home, will copy the owner's entire Claude Code history into a second store without asking.

---

## A. LAUNCH

**Both headless and attachable. VERIFIED by running `--help` on 0.1.14.**

### Headless one-shot

```
mimo run [message..]
```

Flags (exact, from the binary's own help):

| Flag | Meaning |
|---|---|
| `--format <default\|json>` | `json` emits **raw JSON events**, one per line |
| `-m, --model <provider/model>` | model, in `provider/model` form |
| `--agent <name>` | primary agent: `build` / `plan` / `compose` |
| `--variant <string>` | provider-specific reasoning effort, e.g. `high`, `max`, `minimal` |
| `--command <name>` | run a slash command; `message` becomes its args |
| `-f, --file <paths…>` | attach file(s) |
| `--title <string>` | session title (see §B — this is the correlation handle) |
| `--dir <path>` | directory to run in |
| `--port <n>` | port for the local server (default: random) |
| `--attach <url>` | run against an already-running `mimo serve` |
| `-p, --password` | basic-auth password (default `MIMOCODE_SERVER_PASSWORD`) |
| `--role <user\|assistant>` | role for the injected message — see §G |
| `--thinking` | show reasoning blocks |
| `--dangerously-skip-permissions`, `--yolo` | auto-approve anything not explicitly denied |

Message can come from argv **or stdin**: `if (!process.stdin.isTTY) message += "\n" + await Bun.stdin.text()`
(VERIFIED, `src/cli/cmd/run.ts`).

### Structured output — exact shape

With `--format json`, every line is `{"type": …, "timestamp": <ms>, "sessionID": <id>, …}`
(VERIFIED in `run.ts`, function `emit`). Emitted types:

`tool_use` · `step_start` · `step_finish` · `text` · `reasoning` (only with `--thinking`) · `error`

Note what is **absent**: there is no `session_start` / `result` envelope carrying totals. The
orchestrator learns the session id from the `sessionID` field of the first event, and must derive
completion from process exit or from `GET /session/status`.

### Headless server — the important one

```
mimo serve --port <n> --hostname <h> [--no-auth] [--cors …] [--mdns]
```

Starts a long-lived HTTP + SSE control plane. VERIFIED on this machine: bound 127.0.0.1:47311, and
`GET /path`, `/session`, `/session/status`, `/config`, `/permission`, `/question`, `/event` all
answered 200.

`mimo attach <url>` opens the TUI against a running server — so **one server can be driven headless
by the supervisor and attached to by the owner at the same time**, which is exactly the
"visible terminal the owner can type into" half of this axis. The README documents this for SSH:
`mimo serve --port 4096` remote, `ssh -N -L 4096:127.0.0.1:4096`, `mimo attach http://127.0.0.1:4096`.

### ACP

```
mimo acp --cwd <dir>
```
Starts an **Agent Client Protocol** server: newline-delimited JSON-RPC over stdin/stdout, via
`@agentclientprotocol/sdk` (`AgentSideConnection`, `ndJsonStream`) (VERIFIED, `src/cli/cmd/acp.ts`).
This is the standardised bidirectional protocol; the HTTP surface is richer, but ACP is the
portable one.

**Security note on `serve`:** binding a non-loopback address without `MIMOCODE_SERVER_PASSWORD`
is refused unless `--no-auth` is passed. On loopback with no password it prints
`Warning: MIMOCODE_SERVER_PASSWORD is not set; server is unsecured.` and serves anyway — and the
comment in `src/flag/flag.ts` is blunt about what that means: *"`/file` reads and writes the
project, `/pty` and `/bash-interactive` run commands"* for **any process running as this user**.
A supervisor should always set `MIMOCODE_SERVER_PASSWORD`.

---

## B. IDENTITY & RESUME

**Resume: excellent. Naming a session up front: not supported.**

### The orchestrator cannot assign an id

`Session.CreateInput` (VERIFIED, `src/session/session.ts:212`) is:

```ts
{ parentID?, contextFrom?, contextWatermark?, title?, permission?, workspaceID? }
```

There is **no `id` field**, and the HTTP `POST /session` validates against exactly this schema. Ids
are server-minted (`Identifier.descending("session")`). This is the one place pi beats MiMoCode
outright — pi's `--session-id <id>` creates-if-missing.

**Workaround, and its cost.** Pass a unique `--title` the supervisor generates, then resolve it:

```
mimo session list --format json      # → [{id,title,updated,created,projectId,directory}, …]
```
or `GET /session?search=<title>`. Cost: one extra round-trip, and a **race** — two sessions created
in the same second with colliding titles cannot be told apart. Use a ULID-ish title prefix.

The alternative — parse `sessionID` out of the first `--format json` event on stdout — is exact but
only works for `mimo run`, not for sessions created through the API.

### Listing and resuming

| Operation | Surface | Tag |
|---|---|---|
| List | `mimo session list [-n N] --format json` · `GET /session?roots&search&limit&start` | VERIFIED |
| Get one | `GET /session/:sessionID` | VERIFIED |
| Children | `GET /session/:sessionID/children` | VERIFIED |
| Status of all | `GET /session/status` → `{sessionID: {type:"idle"\|"busy"\|"retry"\|"notice", …}}` | VERIFIED (returned `{}` live) |
| Continue last | `mimo run -c` / `mimo -c` | VERIFIED |
| Continue by id | `mimo run -s <id>` / `mimo -s <id>` | VERIFIED |
| Fork | `mimo run --fork` (needs `-c`/`-s`) · `POST /session/:id/fork` | VERIFIED |
| Delete | `mimo session delete <id>` · `DELETE /session/:id` | VERIFIED |

### Crash recovery — the strong part

Two routes exist specifically for "the turn died mid-flight":

```
GET  /session/:sessionID/recovery                                  # session.recovery
POST /session/:sessionID/turn/:assistantMessageID/resume           # session.resume  → 202
```

`session.resume` is documented as *"Resume an incomplete assistant turn **without creating another
user message**"* (VERIFIED, `src/server/routes/instance/session.ts:1036`). It takes optional
`agentID`, `modelProviderID` + `modelID` (both or neither — a 400 otherwise), `directory`,
`workspace`, `task_id`. It calls `assertNotBusy` first, so a double-resume 409s rather than
double-runs.

**What survives what:**

| Failure | Survives? | Why |
|---|---|---|
| Process kill / Ctrl-C | **Yes** | State is in SQLite (`<data>/mimocode.db`), not process memory |
| Reboot | **Yes** | Same — plus `session.time_updated`, `last_checkpoint_message_id` on the row |
| Provider outage / 429 | **Yes, and it retries itself** | `src/session/retry.ts`: kinds `network`/`rate_limit`/`server` are retryable, `RATE_LIMIT_MAX_RETRIES = 5`, honours `retry-after` and `retry-after-ms` headers, and publishes `{type:"retry", attempt, next, message}` on `/session/status` so the supervisor sees the backoff |
| Context overflow | Terminal, not retried | `ContextOverflowError` → `kind:"terminal"` — prevent it via §D, don't rely on recovery |

Persistent memory is reloaded on resume: `MEMORY.md`, `checkpoint.md`, `notes.md`,
`tasks/<id>/progress.md` are injected automatically (CLAIMED, README — the checkpoint machinery is
real in source: `src/session/checkpoint.ts`, 85 KB).

---

## C. TRANSCRIPT

**Best-in-scan. A queryable database, not a log file to tail.**

| Fact | Value | Tag |
|---|---|---|
| Store | `<data>/mimocode.db` — SQLite, WAL mode | VERIFIED (`mimo db path`) |
| Default `<data>` (macOS) | `~/Library/Application Support/mimocode/` | VERIFIED (README; overridden by `MIMOCODE_HOME` in my probe) |
| Override | `MIMOCODE_HOME` relocates data/config/cache/state together | VERIFIED — `mimo debug paths` |
| Logs | `<data>/log/<ISO>-main-<pid>-<hash>.log`, rotating | VERIFIED (files on disk) |

### Tables (VERIFIED — `SELECT name FROM sqlite_master`)

```
account            account_state      actor_registry     claude_import
control_account    event              event_sequence     external_import
history_fts (+idx) inbox              memory_fts (+idx)  message
part               permission         permission_grant   project
session            session_prefix_snapshot               session_share
task               task_event         todo               workflow_run
workspace
```

### Exact columns a supervisor needs (VERIFIED — `PRAGMA table_info`)

```
session: id, project_id, parent_id, slug, directory, title, version, share_url,
         summary_additions, summary_deletions, summary_files, summary_diffs,
         revert, permission, time_created, time_updated,
         time_compacting,            -- ← compaction proof, see §D
         time_archived, workspace_id, context_from, context_watermark,
         last_checkpoint_message_id, prompt, auto_worktree_hint_sent

message: id, session_id, agent_id, time_created, time_updated, data   -- data = JSON
part:    id, message_id, session_id, time_created, time_updated, data -- data = JSON
```

### Reading it live

Three ways, all VERIFIED:

1. **SQL, from the CLI.** `mimo db "<query>" --format json|tsv`, plus `mimo db path`. This is a
   supported, documented command, not a hack.
2. **HTTP.** `GET /session/:id/message`, `GET /session/:id/message/:messageID`,
   `GET /session/:id/todo`, `GET /session/:id/task`, `GET /session/:id/diff`,
   `GET /session/:id/actors`.
3. **SSE.** `GET /event` — live bus. VERIFIED: opening it immediately yields
   `data: {"type":"server.connected","properties":{}}`, then `message.updated`,
   `message.part.updated`, `session.status`, `session.error`, `permission.asked`,
   `question.asked`, `question.replied`, `question.rejected`, …

**Caveat for concurrent readers:** SQLite in WAL mode with a live writer. Read-only connections are
fine, but a supervisor must open read-only and must not hold long transactions. Prefer `/event` +
HTTP for hot-path progress and SQL for periodic audit.

Offline: `mimo export [sessionID] [--sanitize]` → JSON, and `mimo import <file|url>`. `--sanitize`
redacts sensitive transcript and file data (VERIFIED, help text).

---

## D. CONTEXT

**Fully answered, in both directions, with durable proof. This is the standout axis.**

### Reading fullness from outside

Context accounting is per assistant message, in `message.data`:

```
tokens: { input, output, reasoning, cache: { read, write }, total }
```

The denominator comes from `contextWindow()` (VERIFIED, `src/session/overflow.ts`):

```ts
type Window = {
  hard:      number  // provider cap; 0 = unknown, overflow handling off
  effective: number  // after the user's compaction.max_context budget
  usable:    number  // the token count at which compaction fires
  source:    "model" | "config"
}
```

- `usable = floor(effective * MIMOCODE_COMPACTION_TRIGGER_RATIO)`, ratio **default 0.9**.
- Reserve: `compaction.reserved` ?? `min(33_000, maxOutputTokens(model))`, plus an output
  reservation capped at `OUTPUT_CAP = 20_000` when the provider publishes no separate input cap.
- `contextPressureLevel()` returns **0/1/2/3** at ratios **<0.50 / <0.70 / <0.85 / ≥0.85**.

The window is printable without any model call:

```
mimo models <provider>
# → provider/model — window 1.0M, budget 300K, compacts at 270K
```
(VERIFIED, `src/cli/cmd/models.ts` — it prints `window`, `budget` when `source === "config"`, and
`compacts at`.) The TUI footer uses the same number (`33.0K/260K↓ (13%)`; `↓` = a budget is in
force), and `/status` breaks it down.

**Supervisor recipe:** `usable` from `mimo models`, current `tokens.total` from the newest assistant
message (SQL or `message.updated` on `/event`) → exact percentage, no estimation.

### Triggering compaction from outside

```
POST /session/:sessionID/summarize
     { "providerID": "<p>", "modelID": "<m>", "auto": false }
  → 200 true
```
(VERIFIED, `session.ts:635`.) It runs `revert.cleanup` → `compact.create({sessionID, agent, model,
auto, agentID:"main"})` → `prompt.loop`. Note the body **requires** `providerID` and `modelID` — the
supervisor must decide which model pays for the summary, which is useful (compact on a cheap model)
and a gotcha (there is no "use the session's model" default).

### Proof it happened

Three independent, durable signals:

1. **`session.time_compacting`** — a column on the session row. A SQL read before/after is proof.
2. **`session.last_checkpoint_message_id`** — moves when a checkpoint is written.
3. **The compaction message itself** lands in `message`/`part` and streams over `/event`.

No other platform in this scan offers a *column* as compaction proof.

### Tuning

| Knob | Where | Effect |
|---|---|---|
| `compaction.max_context` | config, per-model, wildcards allowed (longest pattern wins) | Lower the working window. `"272K"`, `"1M"`, `"50%"`. Clamped to the provider cap — can only lower. `0` restores the model's own window |
| `compaction.reserved` | config | Headroom reserved for the summary |
| `compaction.auto: false` | config | Disable automatic compaction entirely |
| `MIMOCODE_COMPACTION_MAX_CONTEXT` | env | Same grammar, env-only path |
| `MIMOCODE_COMPACTION_TRIGGER_RATIO` | env | `"0.85"` or `"85%"`; out-of-range ignored |
| `MIMOCODE_DISABLE_AUTOCOMPACT` | env | Off switch |
| `MIMOCODE_DISABLE_CHECKPOINT` | env | Disables checkpoint writers and checkpoint-based rebuilds; overflow falls back to plain compaction |
| `/context-limit` | TUI | Interactive picker for `compaction.max_context` |

**Handoff primitive.** `POST /session` accepts `contextFrom: <sessionID>` and
`contextWatermark: <messageID>`, persisted as `session.context_from` / `session.context_watermark`.
A supervisor can create a **fresh** session seeded from a specific point in an old one — a true
handoff, not a compaction. (VERIFIED in schema; the exact semantics of the watermark are
**UNKNOWN** — not exercised.)

---

## E. QUOTA — the failing axis

**Remaining capacity cannot be read. Not by endpoint, not by header, not by CLI.** This is the
owner's non-negotiable, and MiMo does not meet it.

### What was checked, and found absent

| Candidate | Result | Tag |
|---|---|---|
| A usage/balance API on the MiMo platform | None documented. The official rate-limit page names only the web console `platform.xiaomimimo.com/console/balance` and a usage page `#/console/usage` with CSV export | VERIFIED (docs read today) |
| Rate-limit response headers | Not documented. Live probes returned no `x-ratelimit-*` of any kind — only `server: MiFE/3.4.29`, `x-mife-upstream-status` | VERIFIED (curl, today) |
| Anything in MiMoCode | `grep` over the repo for `x-ratelimit` → **0 hits**. `quota`/`credits` hits are all in `packages/console` (Xiaomi's own Stripe-billed SaaS console) and i18n strings, never in the agent runtime | VERIFIED (GitHub code search) |
| `mimo stats` | **Historical spend only.** Aggregates `message.data.tokens` and `message.data.cost` out of the local SQLite — tokens, cost, cost/day, tools, per-model breakdown. It never contacts the provider, so it can tell you what you *spent*, never what is *left* | VERIFIED (`src/cli/cmd/stats.ts`) |

### What the windows actually are

| Window | Value | Tag |
|---|---|---|
| RPM, `mimo-v2.5-pro` and `mimo-v2.5` | **100 requests/min** | VERIFIED (official rate-limit doc) |
| TPM, same models | **10M tokens/min** | VERIFIED (same) |
| Scope | Per **account**, summed across all API keys, per model | VERIFIED (same) |
| Pay-as-you-go | Pure per-token billing — no window at all | VERIFIED |
| Token Plan | Monthly **Credits**: Lite ¥39/60M, Standard ¥99/200M, Pro ¥329/700M, Max ¥659/1600M. Burn rate **2× tokens** for `-pro`, **1×** for `mimo-v2.5`. **No 5-hour window** | CLAIMED (plan-comparison sites; not found on a Xiaomi page in this pass) |

So the model is *credits/month + per-minute rate limits* — **no rolling-hours or weekly window** of
the Claude-subscription kind. That is genuinely good news for an overnight queue: there is no
"weekly limit hit at 02:00" failure. The bad news is that monthly credit burn is invisible until it
runs out.

### In-band limit signalling — partial credit

A limit-hit **is** signalled in-band and is machine-readable, even though remaining capacity is not:

- HTTP **429** (and 408, 425) classify as retryable; `decide()` also pattern-matches
  `rate_limit` / `rate limited` / code `"429"` in the body (`src/session/retry.ts`).
- Reset time is honoured when the provider sends it: `retry-after-ms` (ms), then `retry-after`
  (seconds or HTTP-date), then a regex over the error text
  (`/(?:try again|retry(?:ing)?)(?: in| after)\s+(\d+…)\s*(ms|s|m|h)/i`).
- The supervisor sees it live: `session.status` publishes
  `{type:"retry", attempt, phaseAttempt, message, next, phase:"request"|"stream", scope}` where
  `next` is the absolute ms timestamp of the next attempt.
- After `RATE_LIMIT_MAX_RETRIES = 5` it gives up and the turn errors.

**Whether the MiMo endpoint actually sends `retry-after` on 429 is UNKNOWN** — not observed,
because no 429 was provoked.

### Closest workaround, and its cost

1. **Budget locally from `mimo stats`.** Record cumulative cost at the start of each billing period
   and subtract. Cost: you are trusting a client-side ledger; it drifts if any usage happens
   outside this machine (the web console, the Desktop app, another host), and it silently misses
   anything the local DB never saw.
2. **Scrape the console.** `platform.xiaomimimo.com/#/console/usage` exports usage by date.
   Cost: browser automation against an authenticated SPA — fragile, and per-day granularity is far
   too coarse to pause a run.
3. **Treat 429 + `session.status.retry` as the only real signal.** Cost: reactive, not predictive.
   The orchestrator finds out it is out of capacity by hitting the wall, and `next` tells it when to
   come back only if the endpoint sends a header.

**Recommendation:** an orchestrator that must *predict* exhaustion cannot use MiMo as the account
whose quota it watches. Use MiMo for work where running out is survivable, keep the quota-critical
role on a platform that exposes a usage endpoint (Claude Code's
`GET https://api.anthropic.com/api/oauth/usage` remains the reference), and treat the MiMo lane as
best-effort with a 429-backoff policy.

---

## F. ACCOUNTS

**Per-session account selection is clean and env-only. Changing a *running* session's account is
partly possible. And the owner's current credential is dead.**

### The dead credential — fix this first

`~/.config/claude-mimo/env` (created 2026-05-09, mode 0600) contains:

```
export ANTHROPIC_BASE_URL=https://token-plan-sgp.xiaomimimo.com/anthropic
export ANTHROPIC_AUTH_TOKEN=tp-…          (51 chars, Token Plan key)
export ANTHROPIC_CUSTOM_MODEL_OPTION=mimo-v2.5-pro
export ANTHROPIC_CUSTOM_MODEL_OPTION_NAME='Xiaomi MiMo'
```
wired by `~/.zshrc:48`:
```
alias claude-mimo="source ~/.config/claude-mimo/env && claude --model 'mimo-v2.5-pro[1m]'"
```

Probed today (VERIFIED, no inference performed — the POST used a deliberately empty body so auth is
checked before any billing):

| Request | Result |
|---|---|
| `GET https://token-plan-sgp.xiaomimimo.com/v1/models` with `api-key:` / `Authorization: Bearer` / `x-api-key:` | **401** `{"message":"Invalid API Key","code":"401","type":"invalid_key"}` (all three) |
| `POST https://token-plan-sgp.xiaomimimo.com/anthropic/v1/messages` body `{}` | **401**, same body |
| `POST https://api.xiaomimimo.com/anthropic/v1/messages` body `{}` | **401**, same body |

The key is expired, revoked, or the subscription lapsed. **The field scan's "this is not
hypothetical — it already works" is no longer true.** A new key must be minted at
`platform.xiaomimimo.com/#/console/plan-manage` (`tp-…`) or `#/console/api-keys` (`sk-…`).

Also note the base URLs: the docs list `token-plan-**cn**` and the owner is on `token-plan-**sgp**`.
**Base URL is per-account/per-region, not a constant** — it must be a config field.

### Several accounts on one machine

Three independent mechanisms, all VERIFIED in source:

| Mechanism | How | Scope |
|---|---|---|
| **`MIMOCODE_HOME`** | Relocates `data`+`config`+`cache`+`state` as a set, so `auth.json` and `mimocode.db` move with it | **Full isolation.** Verified working on this machine — `mimo debug paths` reported every path under my scratch dir. This is the cleanest per-account switch: one env var, one directory per account |
| **`MIMOCODE_AUTH_CONTENT`** | Credentials JSON passed by environment; read on **every** `Auth.all()` | Per-process, no files touched |
| **`PUT /auth/{providerID}` / `DELETE /auth/{providerID}`** | Live HTTP routes on a running server (VERIFIED — they are the only two instance routes in `/doc`) | Per-server, at runtime |

Credential file: **`<data>/auth.json`**, written mode **`0o600`**, keyed by provider id
(VERIFIED, `src/auth/index.ts`). Three credential shapes:

```ts
{ type:"oauth", refresh, access, expires, accountId?, enterpriseUrl? }
{ type:"api",   key, metadata? }
{ type:"wellknown", key, token }
```

CLI: `mimo providers list|login [url]|logout|whoami` (alias `mimo auth`).
Separately, `mimo console login|logout|switch|orgs|open` manages **Xiaomi console accounts and
orgs** — a different thing: enterprise/billing identity, with `experimental.console.*` HTTP routes
behind it.

**Security note the source makes itself** (`src/auth/index.ts`): `MIMOCODE_AUTH_CONTENT` is honoured
but deprecated in favour of in-process `inject()`, because *"anything in the environment is readable
by every child the engine spawns — the bash tool alone turns `echo $MIMOCODE_AUTH_CONTENT` into a
credential dump, and a sibling can still read `/proc/<pid>/environ`"*. For an unattended orchestrator
running arbitrary tasks, **prefer `MIMOCODE_HOME` per account over `MIMOCODE_AUTH_CONTENT`.**

### Changing a running session's account

Partly. Three degrees:

1. **Model/provider per turn — yes.** `session.prompt`, `session.prompt_async`, `session.command`,
   `session.resume` and `session.summarize` all take `providerID` + `modelID`. The supervisor can
   switch a live session from `mimo/mimo-v2.5-pro` to another provider mid-conversation.
2. **Credential for a provider — yes, instance-wide.** `PUT /auth/{providerID}` rewrites
   `auth.json`, and `Auth.all()` re-reads on every call, so the next request uses the new key. This
   affects **every session on that server**, not one.
3. **One session on a different account than its siblings — no.** Accounts are an instance
   property. Run one `mimo serve` per account (each with its own `MIMOCODE_HOME`) and route sessions
   to servers. Cost: ~97 MB of node_modules once, plus one process and ~62 MB of state per account.

**No Keychain involvement**, which removes the "macOS blocks on a GUI dialog for an account never
granted Always Allow" failure mode that Claude Code has here.

---

## G. INTERVENTION

**The strongest axis. A question channel *and* a permission channel, both answerable over HTTP, both
with delivery confirmation.** This is the axis the current harness fails at ("a nudge that cannot
submit stranded text"), and MiMoCode answers it three different ways.

### 1. Inject an instruction into a running session

| Route | Semantics |
|---|---|
| `POST /session/:id/prompt_async` → **204** | Fire-and-forget. Starts the session if idle. Rate-limited server-side: `windowMs: 60_000, max: 20` per `prompt_async` (VERIFIED, `RateLimitMiddleware`) |
| `POST /session/:id/message` → message | Blocking; returns the created message |
| `POST /session/:id/command` | Invoke a slash command with arguments |
| `POST /session/:id/abort` | Stop the current turn |
| `POST /session/:id/shell` | Run a shell command inside the session's context |
| `POST /session/:id/revert` / `unrevert` | Roll the session back to a message/part |

**Did it arrive?** Yes, provably: `prompt_async` returns 204 only after validation, and the injected
message appears on `/event` as `message.updated` with its own `MessageID`, and in the `message`
table. That is a durable receipt, not a hope.

**`--role assistant`** deserves its own line. `mimo run --role assistant "<text>"` *"injects text as
model output then triggers continuation"* (VERIFIED, help text + `run.ts`). The supervisor can put
words in the agent's own mouth and let it continue from there — a steering primitive no other
platform in this scan exposes.

### 2. Answer the session's own question — programmatically

MiMoCode has a **dedicated question subsystem** (`src/question/index.ts`), separate from
permissions:

```
GET  /question                       → [{id, sessionID, questions:[{question, header,
                                          options:[{label,description}], multiple?, custom?,
                                          key?, params?}], tool?}]
POST /question/:requestID/reply      { answers: [["<label>"], …] }   # one array per question
POST /question/:requestID/reject
GET  /question/never-ask             → false
POST /question/never-ask             { enabled: true }
```

VERIFIED live on this machine: `GET /question` → `[]`, `GET /question/never-ask` → `false`.

Mechanics (VERIFIED in source): `ask()` creates a `Deferred`, publishes `question.asked` on the bus,
and blocks the turn until `reply()` or `reject()` resolves it. `reply()` publishes
`question.replied` with the answers; `reject()` publishes `question.rejected` and fails the turn's
await with `"The user dismissed this question"`. **The orchestrator is a first-class answerer** —
it subscribes to `/event`, sees `question.asked` with the full option list, and POSTs a reply.

`setNeverAsk(true)` is the unattended fallback: the question tool stays visible but `ask()` is never
reached — the tool returns a `[Never-Ask]` directive so *the model re-picks the best option itself*.
Toggleable at runtime (`--never-ask` at launch, `/never-ask` in the TUI, `POST /question/never-ask`
from outside).

### 3. Answer a permission prompt — programmatically

```
GET  /permission                              → pending requests
POST /permission/:requestID/reply             { reply: "once" | "always" | "reject" }
POST /session/:id/permissions/:permissionID   # permission.respond, session-scoped
GET/POST /permission/skip-all                 # instance-wide auto-allow toggle
GET/POST /permission/auto-approve-delete
GET/POST /permission/ask-timeout              # ms, or null = wait forever
```

VERIFIED live: `GET /permission` → `[]`, `/permission/skip-all` → `false`,
`/permission/ask-timeout` → `null`.

The event is `permission.asked` carrying `{id, sessionID, permission, patterns[]}` — the CLI's own
`run` loop consumes exactly this and calls `sdk.permission.reply({requestID, reply:"once"})`
(VERIFIED, `run.ts`). A supervisor does the same over HTTP.

### 4. Ask a session a side question without disturbing it

```
POST /session/:id/ask  { question, providerID?, modelID? }  → { answer }
```
*"one-shot, read-only side question over a frozen snapshot of its history … Does NOT inject a
message into the conversation or disturb the session's turn"* (VERIFIED, `session.ts:694`).

This is a supervision primitive purpose-built for a watcher: **"are you stuck?" without touching the
run.** Cost: it is a real model call on the snapshot, so it bills.

### 5. ACP

`mimo acp` exposes the same capabilities over standard Agent Client Protocol JSON-RPC — portable,
id-correlated, and the right shape if the orchestrator wants one protocol across platforms.

---

## H. GUARDRAILS

**Rich, layered, and — critically — the *defaults differ between surfaces*.**

### What it does unattended without asking

This is the part to get right, and it is not uniform:

| Surface | Default on a permission `ask` | Tag |
|---|---|---|
| `mimo run` (headless), no flags | **Auto-rejects**, printing `permission requested: …; auto-rejecting` | VERIFIED, `run.ts` |
| `mimo run --dangerously-skip-permissions` | Auto-replies `"once"` to everything not explicitly denied | VERIFIED |
| `mimo run` — the `question` tool | **Denied outright.** `run.ts` hard-codes `[{permission:"question", action:"deny", pattern:"*"}, {permission:"plan_exit", action:"deny", pattern:"*"}]` into the session it creates | VERIFIED |
| Background/subagent session | Auto-denied (`interactive:false` → `DeniedError`) | CLAIMED (orchestrator design doc) |
| Orchestrator peer child | **Forwarded** for approval; auto-denied after `FORWARD_DENY_TIMEOUT_MS` = **5 minutes** | CLAIMED (design doc; names `src/permission/index.ts`) |
| `mimo serve` instance default | `ask-timeout` = `null` — **waits indefinitely** | VERIFIED live |

**The trap:** a supervisor that drives `mimo serve` over HTTP inherits `ask-timeout: null`, so an
unanswered permission blocks the turn **forever**. A supervisor that shells out to `mimo run`
inherits auto-reject, so the turn fails fast instead. Neither default is right for unattended work.
Set `POST /permission/ask-timeout {ms}` explicitly, and decide deliberately.

### The ruleset

`Permission.Ruleset` is an ordered list of `{permission, action: "allow"|"deny"|"ask", pattern}`,
**last matching rule wins**. Settable per session at creation (`POST /session {permission: […]}`) or
in config:

```jsonc
{ "permission": { "external_directory": { "/tmp/**": "allow" } } }
```

Anything outside the project working directory triggers an `external_directory` ask by default —
including the system temp directory. The README documents allowing `/tmp/**` and is explicit about
the risk (world-writable, symlink races).

`--dangerously-skip-permissions` / `MIMOCODE_DANGEROUSLY_SKIP_PERMISSIONS=1` injects an allow-all
base **underneath** your config, so explicit rules still win. Three caveats from the README, all
load-bearing for unattended use:
- a leftover `"ask"` rule **still prompts** — the flag does not override it;
- a top-level `"*": "ask"` makes the flag a **no-op**;
- the interactive confirmation is **skipped when there is no TTY**, so in CI/unattended it activates
  silently.

### Delete protection

Separate permission `bash_delete`, so a broad `bash: allow` cannot silently pre-approve
destruction. It intercepts `rm`, `rmdir`, `unlink`, `shred`, `del`, `erase`, `rd`, `remove-item`
and destructive git (`reset --hard`, `clean -f`, `branch -D`, `worktree remove`, `push --force`,
`stash drop|clear`, `tag -d`). Override: `MIMOCODE_AUTO_APPROVE_DELETE=true`, or
`POST /permission/auto-approve-delete {enabled:true}` (which `mimo run --yolo` sets and restores).

`/skip-permissions` in the TUI is the lighter runtime toggle: `deny` still blocks, and forced-ask
operations **auto-reject after 60 s** with feedback the model can act on rather than hanging.

### Sandboxing

No process/OS sandbox of its own. `docs/` has a containerization story via
`flake.nix` + `packages/containers` (CLAIMED — not exercised). For an unattended run, the container
is the real boundary; the permission system is a policy layer inside it.

### Telemetry — on by default

`MIMOCODE_ENABLE_ANALYSIS` defaults to **true**: *"POSTing `model_call`/`tool_call`/`agent_request`
metrics"* (VERIFIED, `flag.ts`). Set `MIMOCODE_ENABLE_ANALYSIS=false` to opt out. For a repo the
owner cares about, this should be an explicit decision, not a default.

---

## I. EXTENSIBILITY

**Very high, and it will read your Claude Code setup unless you stop it.**

| Capability | Detail | Tag |
|---|---|---|
| **MCP** | `mimo mcp add\|list\|auth\|logout\|debug`; HTTP routes under `/mcp`; OAuth-enabled servers supported | VERIFIED |
| **Skills** | Bundled set (≈22: `deep-research`, `super-research`, `compose-next`, `skill-creator`, `evolve`, `claude-code`, `codex`, office/PDF/PPTX/XLSX, …). User skills at `.mimocode/skills/<name>/SKILL.md`; later scan order overrides builtins. BM25 + exact-name search with auto-load at score ≥0.85 | VERIFIED (flags), CLAIMED (skill list) |
| **Agents** | `build` / `plan` / `compose` primaries, plus `orchestrator` behind a flag; `mimo agent create\|list`, `mimo debug agent <name>` | VERIFIED |
| **Subagents** | Created on demand, share session context, run in parallel, with lifecycle tracking, cancellation and background execution; `GET /session/:id/actors` | CLAIMED (README) + route VERIFIED |
| **Workflows** | **Deterministic JavaScript** orchestration scripts in a sandboxed runtime — fixed phases, bounded retries, auto-parallelization, *"fire-and-forget execution with no user interaction required"*. Built-ins: `compose`, `deep-research`, `fact-check`, `research-experiment`. Custom: a `.js` in `.mimocode/workflows/` **or `.claude/workflows/`**; HTTP routes under `/workflows`; `workflow_run` table | CLAIMED (README) + routes/table VERIFIED |
| **Plugins** | `mimo plugin <npm-module> [-g] [--force]`; `--pure` runs without external plugins | VERIFIED |
| **Goal / stop condition** | `/goal` sets a stopping condition; an **independent judge model** evaluates whether it is truly met when the agent tries to stop — *"preventing premature optimistic stops during autonomous work"* (`src/session/goal.ts`, 11 KB) | CLAIMED (README) + source VERIFIED |
| **Worktrees** | `worktree.create/list/remove/reset` HTTP routes; children isolate onto `mimocode/<task-slug>` branches | VERIFIED |
| **LSP** | Built-in, with `mimo debug lsp` | VERIFIED |
| **Config precedence** | Project `.mimocode/mimocode.jsonc\|.json` over global `~/.config/mimocode/…`; `MIMOCODE_CONFIG` (path) and `MIMOCODE_CONFIG_CONTENT` (inline) override; published JSON Schemas at `https://mimo.xiaomi.com/mimocode/config.json` | VERIFIED |

### Can a GSD-style, subagent-heavy workflow engine run inside it?

**Yes — and this is the most consequential finding for the rebuild.** By default MiMoCode
*inherits Claude Code's setup*: `CLAUDE.md`, `~/.claude/skills`, `~/.claude/commands`,
`.claude/commands`, `.claude/workflows`, Claude Code MCP servers, and provider API keys from the
environment. All of it is individually switchable:

```
MIMOCODE_MIMO_ONLY                     # master switch: no .claude inheritance, no env provider keys
MIMOCODE_DISABLE_CLAUDE_CODE           # same, without forcing the mimo-auto default model
MIMOCODE_DISABLE_CLAUDE_CODE_PROMPT    # ignore CLAUDE.md
MIMOCODE_DISABLE_CLAUDE_CODE_SKILLS
MIMOCODE_DISABLE_CLAUDE_CODE_COMMANDS
MIMOCODE_DISABLE_CLAUDE_CODE_MCP       # stays ON even in mimo-only mode, deliberately
MIMOCODE_DISABLE_EXTERNAL_SKILLS       # umbrella: also AGENTS/codex/opencode skill sources
MIMOCODE_DISABLE_AGENTS_SKILLS / _CODEX_SKILLS / _OPENCODE_SKILLS
MIMOCODE_DISABLE_BUILTIN_SKILLS / _OFFICIAL_SKILLS / _SLASH_SKILLS
```

Cuts both ways. A GSD workflow could plausibly run under `mimo` with little porting. Equally, an
unattended `mimo` in the owner's home will pick up his entire Claude Code skill and command surface
unless told not to — including skills that spend money or touch external systems.

### Xiaomi's own orchestrator mode — read this before designing ours

`docs/harness/MiMo Orchestrator Mode.en.md` describes a shipped (flag-gated) design that solves the
same problem this rebuild is chartered for. Gate: `MIMOCODE_EXPERIMENTAL_ORCHESTRATOR=true`
(or `MIMOCODE_EXPERIMENTAL=1`), **off by default**.

A `session` tool with eight verbs, visible only to the orchestrator agent:

| verb | what it does |
|---|---|
| `create` | dispatch a background child — `task`, `mode` (build/plan/compose), `model`, `title`, `dir`, `isolate` |
| `switch` | move the frontend panel to a session |
| `list` | list children (id / title / mode / status) |
| `cancel` | stop a child; **deletes its worktree and branch** |
| `ask` | read-only one-shot side question against a frozen snapshot |
| `setmode` | change a child's mode for subsequent turns (plan → build in the *same* session) |
| `approve` | approve a child's currently pending permission request |
| `grant-approval` | pre-authorize a child, or `all` children |

Design decisions worth stealing, all stated in that doc:

- **No polling.** `create` returns immediately; the child wakes the parent through an **inbox**
  notification on completion. The doc explicitly tells the orchestrator not to loop on `list`.
- **Interrupting the parent does not stop the children.** They keep running and notify.
- **Isolation by git worktree.** `<data>/worktree/<projID>/<task-slug>` on branch
  `mimocode/<task-slug>`; the parent integrates with ordinary git (`git merge-tree` to preview,
  then `merge`).
- **A data-loss rule stated as a rule:** only `cancel` an isolated child *after its work is merged*
  — cancel deletes the branch. "Finished" ≠ "merged".
- **Approval routing with a dedup guarantee:** the direct-user path (`Permission.reply`) and the
  orchestrator path (`session approve`) converge on the same `Deferred`; the second is an idempotent
  no-op.
- **Never hangs:** an unanswered forwarded ask auto-denies after 5 minutes.
- **A globally-unique orchestrator workspace** at `<data>/orchestrator`, so switching into
  orchestrator mode from any directory lands on the same session and the same children.

Also in `docs/harness/`: *Mix of Harness and Hand-off*, *MiMo Token Efficient Mode*, *Agent
Multi-Skill Workflow Orchestration Design*; and `docs/architecture/codex-microkernel-runtime.md`
and `retry-coordinator.md`. **These are prior art for this rebuild and should be read in full.**

---

## J. OPERATIONAL REALITY

### Cost

| Item | Figure | Tag |
|---|---|---|
| `mimo-v2.5-pro` input, cache **hit** | **$0.0036** / Mtok | VERIFIED (vendor model page) |
| `mimo-v2.5-pro` input, cache **miss** | **$0.435** / Mtok | VERIFIED |
| `mimo-v2.5-pro` output | **$0.87** / Mtok | VERIFIED |
| Context / max output | **1M** / **128K** | VERIFIED |
| Long-horizon claim | *"Sustains coherent execution across nearly 1,000 tool calls"*; cited runs of 672 tool calls and 8,192 lines generated | CLAIMED (vendor) |
| Token Plan | Credits/month, 2× burn for `-pro`, 1× for `mimo-v2.5`, **no 5-hour window** | CLAIMED |

The ~120:1 cache-hit/cache-miss ratio is unusually aggressive. For an overnight queue that re-reads
the same repository context on every task, prompt-cache discipline is worth more here than
model choice.

### Maturity

Honest reading: **the model is mature, the CLI is young.**

- `@mimo-ai/cli` is **0.1.14** — a 0.1.x line, first published 2026-06-10, i.e. **~3 months old**.
- But it is an **OpenCode fork**, so the HTTP control plane, session store, LSP, MCP and permission
  system are inherited from a mature codebase, not written last quarter. The version number
  understates it.
- 13,195 stars, 1,364 forks, **1,018 open issues**, pushed today. High activity; high open-issue
  count for the age.
- MIT licence on both the CLI and the open weights, plus a separate `USE_RESTRICTIONS.md`.

### Platform support (macOS)

- `darwin-arm64` binary ships and runs here (VERIFIED).
- **The README states MiMoCode does not support Terminal.app** and recommends iTerm2 or the VS Code
  terminal. For an orchestrator that spawns visible terminals, this is a hard constraint —
  and the owner's shared tooling config already defaults to an iTerm2-osascript launcher, so it
  happens to be compatible.
- Voice input needs `sox`; irrelevant unattended.

### Known unattended-run failure modes

1. **Dead credential** (this machine, today) — 401 at the first model call. §F.
2. **No quota prediction** — the run discovers exhaustion by failing. §E.
3. **`ask-timeout: null` on `serve`** — an unanswered permission blocks a turn forever. §H.
4. **`run` auto-rejects permissions and denies the `question` tool** — the opposite failure: turns
   fail fast and the agent cannot ask for help. §H.
5. **First run imports `~/.claude/projects`** into a second store, unasked. Set
   `MIMOCODE_DISABLE_CLAUDE_IMPORT=1`.
6. **First run performs a SQLite migration** that can take minutes — a supervisor with a startup
   timeout will kill it mid-migration.
7. **Claude Code inheritance** — an unattended `mimo` picks up the owner's CLAUDE.md, skills,
   commands and env provider keys unless disabled. §I.
8. **Telemetry on by default.** §H.
9. **Unsecured loopback server** — `serve` without `MIMOCODE_SERVER_PASSWORD` exposes `/file`,
   `/pty` and `/bash-interactive` to any process running as the user. §A.
10. **`--dangerously-skip-permissions` silently activates with no TTY** and is a no-op against a
    `"*": "ask"` rule. §H.
11. **Orchestrator `cancel` destroys an unmerged worktree branch.** §I.
12. **Context overflow is terminal, not retried** — prevention via §D is mandatory, not optional.

### Is it plausible to run unattended overnight today?

**Yes, with one caveat and one blocker.**

- **Technically:** yes, and better than most. `mimo serve` + HTTP + SSE gives a supervisor
  everything it needs to watch, steer, answer, compact and resume. Self-retry with `retry-after`
  honouring, a goal-judge that resists premature stops, and git-worktree isolation are all built in.
- **Caveat:** 0.1.x on a 3-month-old CLI with 1,018 open issues. Pin the version, and expect flag
  surfaces to move between releases.
- **Blocker for *this* owner:** the credential is dead, and quota is unreadable. The first is a
  ten-minute fix; the second is structural.

---

## K. The other route — MiMo as a model behind another executor

If the executor stays Claude Code and only the *model* changes, the axis answers are Claude Code's,
with two changes:

- **E collapses further.** `GET https://api.anthropic.com/api/oauth/usage` measures the **Anthropic
  subscription**, not MiMo. Pointed at `ANTHROPIC_BASE_URL=…xiaomimimo.com/anthropic`, that endpoint
  is meaningless for the running session — it reports a window that is not the one being spent.
  This is a silent, dangerous failure: the supervisor reads a number that looks fine.
- **F becomes "two env vars".** `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`, plus
  `ANTHROPIC_CUSTOM_MODEL_OPTION`. Per-session, per-launch, trivially scriptable. This is the
  field scan's original observation and it is correct *for this route*.

The same trick generalises to Kimi, GLM/Z.ai, MiniMax and iFlow, which all publish
Anthropic-protocol endpoints. A **`{base_url, token, model_id}` triple** is the right config object.

**Which route to pick.** Use route 2 (MiMo behind Claude Code) when you want cheap tokens under
tooling you already trust, and accept that quota is unobservable either way. Use route 1 (MiMoCode
as executor) when you want the control plane — the question channel, external compaction with
proof, and SQL over the transcript are things Claude Code does not offer at any price.

---

## What this costs the orchestrator

### Free — already built, just call it

| Need | Cost |
|---|---|
| Headless launch with structured output | `mimo run --format json`. One process. |
| Long-lived controllable session | `mimo serve --port N` + `MIMOCODE_SERVER_PASSWORD`. One process per account. |
| Live progress | One SSE connection to `/event`. |
| Transcript audit | `mimo db "<SQL>" --format json`, or read-only SQLite. |
| Context percentage | `usable` from `mimo models <p>` ÷ `tokens.total` from the newest assistant message. Zero model calls. |
| Compaction from outside, with proof | `POST /session/:id/summarize`, then check `session.time_compacting`. |
| Answer a permission | subscribe `permission.asked` → `POST /permission/:id/reply {reply:"once"}`. |
| Answer a question | subscribe `question.asked` → `POST /question/:id/reply {answers:[["<label>"]]}`. |
| Inject a nudge, with a receipt | `POST /session/:id/prompt_async` → 204, then the message id on `/event`. |
| Steer as the agent | `mimo run --role assistant "<text>"`. |
| Probe without disturbing | `POST /session/:id/ask {question}` → `{answer}`. Costs one model call. |
| Resume after a crash | `GET /session/:id/recovery` → `POST /session/:id/turn/:msgID/resume`. |
| Per-account isolation | one `MIMOCODE_HOME` per account. ~62 MB state each. |

### Cheap — a few lines of glue

| Need | Cost |
|---|---|
| Know a session's id | Generate a unique `--title`, then `mimo session list --format json` and match. One round-trip; racy on title collision. Or parse `sessionID` from the first `--format json` line. |
| Sane unattended permission policy | Explicitly `POST /permission/ask-timeout {ms}` at startup — neither default (`null` on serve, auto-reject on run) is right. |
| Stop it eating the owner's setup | Set `MIMOCODE_DISABLE_CLAUDE_IMPORT=1`, `MIMOCODE_MIMO_ONLY=true` (or the finer-grained flags), `MIMOCODE_ENABLE_ANALYSIS=false`, `MIMOCODE_DISABLE_AUTOUPDATE=true`. |
| Pin compaction behaviour | `compaction.max_context` per model + `MIMOCODE_COMPACTION_TRIGGER_RATIO`. |

### Expensive — no good answer

| Need | Cost |
|---|---|
| **Read remaining quota (E)** | **Impossible today.** Best available: a local ledger from `mimo stats` (drifts, misses off-machine usage), or scraping the authenticated web console (fragile, per-day granularity). Practical stance: keep MiMo off the quota-critical role; treat 429 + `session.status.retry.next` as the only real signal and back off. |
| **Name a session before it exists (B)** | Not supported. Title-correlation costs a round-trip and a race window. |
| **Per-session account within one instance (F)** | Not supported. One `mimo serve` per account, ~97 MB + ~62 MB each. |
| **A supported sandbox** | None built in. Containerize, or accept the permission layer as the only boundary. |

### One-line recommendation

**Adopt MiMoCode as a driven executor on the strength of D, C and G — its control plane is the best
in this scan — but never give it the role whose quota the orchestrator must predict, and re-mint the
owner's API key before any run.**

---

## Sources

All retrieved or executed **2026-09-19** unless noted.

### Run on this machine (VERIFIED)
- `@mimo-ai/cli@0.1.14` installed to an isolated sandbox; `mimo --version`, `mimo --help`, and
  `--help` for `run`, `serve`, `providers`, `stats`, `export`, `session`, `acp`, `debug`,
  `llm-server`, `agent`, `db`, `mcp`, `plugin`.
- `mimo debug paths`, `mimo db path`, `mimo db "SELECT name FROM sqlite_master…"`,
  `mimo db "PRAGMA table_info(session|message|part)" --format json`.
- `mimo serve --port 47311 --hostname 127.0.0.1`; live GETs to `/doc`, `/path`, `/session`,
  `/session/status`, `/config`, `/permission`, `/permission/skip-all`, `/permission/ask-timeout`,
  `/question`, `/question/never-ask`, `/event`.
- `~/.config/claude-mimo/env`, `~/.zshrc:48`.
- Auth probes: `GET {token-plan-sgp,api}.xiaomimimo.com/v1/models` and
  `POST …/anthropic/v1/messages` with an empty body (auth-only, no inference) → 401 `invalid_key`.

### Repository source, `XiaomiMiMo/MiMo-Code` @ v0.1.14 (VERIFIED)
`README.md` · `packages/opencode/src/index.ts` · `src/cli/cmd/{run,serve,session,acp,account,models,stats}.ts` ·
`src/server/server.ts` · `src/server/routes/instance/{index,session,permission,question,event,config,provider,experimental,capability}.ts` ·
`src/session/{overflow,status,retry,schema,session}.ts` · `src/question/index.ts` ·
`src/auth/index.ts` · `src/global/index.ts` · `src/flag/flag.ts` ·
`docs/harness/MiMo Orchestrator Mode.en.md`.

### Registry / API metadata (VERIFIED)
- npm: `npm view @mimo-ai/cli` — 0.1.14, published 2026-09-02; 17 versions since 2026-06-10;
  `bin: {"mimo": "bin/mimo"}`; MIT.
- GitHub API: `repos/XiaomiMiMo/MiMo-Code` — 13,195 stars, 1,364 forks, 1,018 open issues,
  created 2026-06-10, pushed 2026-09-19, MIT, TypeScript; 14 releases.
- HuggingFace API: `XiaomiMiMo/MiMo-V2.5-Pro`, `MiMo-V2.5`, `MiMo-V2-Flash` — **`license: mit`**,
  lastModified 2026-07-09.

### Official documentation (VERIFIED as read; vendor claims tagged CLAIMED in-line)
- https://mimo.mi.com/models/en-US/mimo-v2.5-pro — pricing, 1M/128K, tool-call claim.
- https://mimo.mi.com/docs/en-US/quick-start/summary/first-api-call — base URLs (`api.xiaomimimo.com/v1`,
  `/anthropic`; `token-plan-cn.…`), key formats `sk-`/`tp-`, console usage page.
- https://mimo.mi.com/docs/en-US/api/guidance/rate-limit — 100 RPM / 10M TPM per model, per-account
  scope, 429, **no headers and no quota endpoint documented**.
- https://github.com/XiaomiMiMo/MiMo-Code — README, docs tree.

### Secondary, tagged CLAIMED
- Token Plan tier pricing (Lite/Standard/Pro/Max, credit burn multipliers, "no 5-hour limit") —
  plan-comparison sites; **not confirmed on a Xiaomi page in this pass**. Treat the numbers as
  indicative and re-verify in the console before budgeting against them.

### Open questions for a later pass
1. Does the MiMo endpoint actually emit `retry-after` / `retry-after-ms` on a real 429? (Requires
   provoking one.)
2. Exact semantics of `contextFrom` + `contextWatermark` on `POST /session` — how much history does
   a seeded session inherit?
3. Is Token Plan credit balance reachable through any authenticated JSON endpoint behind the console
   SPA?
4. Does `MIMOCODE_EXPERIMENTAL_ORCHESTRATOR` expose the `session` tool's eight verbs over HTTP, or
   only to the in-session orchestrator agent?
5. `packages/containers` / `flake.nix` — is there a supported container image for unattended runs?
