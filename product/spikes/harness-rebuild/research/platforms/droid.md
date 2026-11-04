# Factory Droid — platform profile

**Date of research:** 2026-09-19. **Researcher context:** owner's Mac (darwin 25.5.0, arm64).
**Version examined:** `droid` **0.223.0**, published **2026-09-19** (the same day — this is the current release).
**Scope:** Factory Droid as an *agent platform to be driven*, measured against the orchestrator
contract axes A–J. Orchestrators themselves are out of scope.

**Evidence tags:**
- **VERIFIED** — read in the shipped binary, run on this machine, or read in official Factory docs / the official OpenAPI spec.
- **CLAIMED** — asserted by Factory marketing or a README only.
- **UNKNOWN** — could not be established in this pass.

---

## 0. Method, and what was and was not done on this machine

**Droid is NOT installed on the owner's machine.** (VERIFIED)
`which droid factory` → not found. There is no `~/.factory` and no `~/.droid`. The
[field scan](00-field-scan.md) already recorded `droid` as absent, and that still holds.

To avoid reasoning about flags from prose, I installed **0.223.0 into an isolated sandbox** at
`/private/tmp/claude-501/.../scratchpad/droid/sandbox/npm` and ran it with `HOME` and
`XDG_CONFIG_HOME` redirected into that sandbox. Every flag, enum, path and JSON shape tagged
VERIFIED below was read from that binary or from its own output.

**Nothing of the owner's was modified and no quota was spent.** Confirmed after the fact:
`~/.factory` still does not exist. No login was performed; the one `droid exec` invocation that
reached the agent loop failed with
`Authentication failed. Please log in using /login or set a valid FACTORY_API_KEY environment variable.`
— which is itself a useful VERIFIED datapoint, and it cost nothing.

Two primary sources were unusually productive and are worth naming for the next pass:

1. **`https://docs.factory.ai/llms.txt`** — a complete documentation index where every page is
   available as raw Markdown at `<page>.md`. This is the fastest way to read Factory docs
   accurately; the HTML renders badly.
2. **`https://docs.factory.ai/openapi.json`** — the machine-readable Factory Public API spec
   (OpenAPI 3.0.1, `info.version` 0.1.0, server `https://api.factory.ai/`). Enumerating all of its
   operations is what makes the **negative** finding on axis E trustworthy rather than a guess.

Where the shipped binary and the published docs disagree, **the binary wins** and the drift is
flagged. There are two such drifts, both recorded below (tool-control flag names in §H, transcript
path in §C).

### Install and distribution (VERIFIED)

| Fact | Value |
| --- | --- |
| npm package | `droid` — 213 versions, `latest` = 0.223.0 (2026-09-19); `@factory/cli` is the same version |
| npm license field | **`UNLICENSED`** — the CLI is closed source |
| Node requirement | `>=20.0.0`; the shipped binary embeds **Bun 1.4.2** as its runtime |
| Binary | `bin/droid`; real payload arrives via `optionalDependencies` `@factory/cli-{darwin,linux,win32}-{arm64,x64,x64-baseline}` |
| Install footprint | **227 MB** for `@factory/cli-darwin-arm64` |
| Installers | `curl -fsSL https://app.factory.ai/cli \| sh`; `brew install --cask droid`; `npm install -g droid`; Windows `irm https://app.factory.ai/cli/windows \| iex` |
| Pinned binaries | `https://downloads.factory.ai/factory-cli/releases/<version>/<platform>/<arch>/droid` plus `.sha256`; `<platform>` ∈ linux/darwin/windows, `<arch>` ∈ x64/arm64/x64-baseline |
| Public repo | `github.com/Factory-AI/factory` — 24 stars, 26 open issues, no license, last push 2026-09-17. A distribution/issue repo, **not** the source |
| SDKs | `@factory/droid-sdk` **0.9.1** (npm, 2026-09-04, **Apache-2.0**); `droid-sdk` **0.4.0** (PyPI, 2026-08-28, Apache-2.0, Python >=3.10) |

Note the licensing split: the CLI is proprietary, the SDKs that drive it are Apache-2.0.

---

## A. LAUNCH

**Verdict: excellent. Both modes are first class, and the structured-output surface is the richest in the field so far.**

### Non-interactive (headless)

`droid exec [prompt]` — VERIFIED from `droid exec --help` on 0.223.0:

```
droid exec "analyze this file"
droid exec -f prompt.txt            # -f, --file <path>
echo "summarize repo" | droid exec  # stdin
```

**Output formats.** `-o, --output-format <format>`, default `text`. The complete accepted set,
VERIFIED by extracting the validation array from the binary (the CLI's own error message,
`Invalid --output-format value`, does not list them):

```
["text","json","stream-json","stream-jsonrpc","acp","acp-daemon","debug"]
```

`--output-format json` returns a documented terminal object:

```json
{"type":"result","subtype":"success","is_error":false,"duration_ms":5657,
 "num_turns":1,"result":"…","session_id":"8af22e0a-d222-42c6-8c7e-7a059e391b0b"}
```

`session_id` in that payload is **the orchestrator's only documented way to learn a session's id**
— see axis B.

**Input formats.** `--input-format <format>`: `stream-jsonrpc` (the real control protocol, axis G)
and `stream-json` (**deprecated — still parses but prints a warning**, per the exec docs).

`acp` / `acp-daemon` are Agent Client Protocol modes. The binary carries `acp/ACPAdapter`,
`acp/ACPDaemonAdapter`, `acp/protocol`, `acp/session`, `acp/tools`, and the Python SDK lists `ACP`
as a `SessionPlatform`. ACP is a cross-vendor protocol, so for a *provider-agnostic* orchestrator
this is strategically interesting: it is the one launch surface that might be shared with other
platforms rather than written per-platform. Its exact method set was not examined (UNKNOWN).

**Other launch flags** (VERIFIED, 0.223.0): `--cwd <path>`, `-w/--worktree [name]`,
`--tag <spec>` (repeatable; plain name or JSON object), `--log-group-id <id>`,
`-m/--model <id>` (default shown as `gpt-5.6-sol`), `-r/--reasoning-effort <level>`,
`--spec-model`, `--spec-reasoning-effort`, `--use-spec`, `--append-system-prompt <text>`,
`--append-system-prompt-file <path>`, `--settings <path>`, `--list-tools`,
`--mission` with `--worker-model` / `--worker-reasoning-effort` / `--validator-model` /
`--validator-reasoning-effort`.

**Exit codes** (VERIFIED, docs): `0` success, `1` general runtime error, `2` invalid CLI arguments.
Fail-fast on permission violation with non-zero exit and no partial changes.

### Visible terminal

`droid` launches a full TUI the owner can attach to and type into; `droid "prompt"` seeds it.
`!` toggles bash mode, `Esc` returns.

**The gap that matters:** there is **no documented way for a supervisor to inject text into a TUI
session the owner started by hand.** The orchestrator must own the process (as an RPC child) to
talk to it. This is the same structural limitation the current harness's "nudge" suffers from, and
Droid does not solve it for foreign processes — it solves it for processes you spawn. See axis G.

### The daemon

`droid daemon` is a real, undocumented-in-prose control plane (VERIFIED from `--help`):

```
-p, --port <number>                 TCP port to listen on
--host <address>                    (default: 127.0.0.1)
--unix <path>                       Unix socket path (alternative to TCP)
--listen <transport>                "websocket" | "ipc"  (default: websocket)
--droid-path <path>                 Path to droid executable for spawning sessions
--liveness-fd <fd>                  Monitor parent process liveness via inherited pipe
--parent-pid <pid>                  Monitor parent process
--remote-access                     Allow remote access (default: false)
--software-factory-workstream <id>  Restrict the SF worker pool to one owned workstream UUID
```

`--droid-path` ("for spawning sessions"), `--liveness-fd` and `--parent-pid` are precisely
orchestrator-shaped: a supervisor can run the daemon as a child, have it die when the supervisor
dies, and have it spawn sessions. The binary contains a `daemon-core` package with
`capabilities/{droid,management,settings,software-factory,relay,terminal}` — including a
**`terminal` capability** — plus `daemon-connection-handler`, `pending-daemon-request-store`,
`request-dispatcher`, `authed-*` / `unauthed-*` connections for both websocket and IPC.
**The daemon's wire protocol is not publicly documented (UNKNOWN)**, and the TypeScript SDK refers
to "daemon clients" using `droid.sessions.*` and `droid.models.*` namespaces without specifying the
transport. **This is the single highest-value unknown about Droid** and deserves its own spike.

---

## B. IDENTITY & RESUME

**Verdict: resume is strong; *pre-naming* a session is the weak point.**

### Can the orchestrator name a session before it exists?

**Not through any documented surface — this is a real gap.** (VERIFIED)

- CLI: `-s, --session-id <id>` is documented and help-texted as *"**Existing** session to continue
  (requires a prompt)"*. It continues; it does not create-with-id.
- SDK: `createSession(options?)` takes no session id. `resumeSession(sessionId, options?)` requires
  an existing one.
- REST: `POST /api/v0/sessions` — `CreateSessionRequestBody` has exactly three properties
  (`computerId`, `cwd`, `sessionSettings`) and **`required: ["computerId"]`**. No id field.

So the orchestrator's supported pattern is **launch → scrape `session_id` from
`--output-format json` (or the first `stream-jsonrpc` response) → record it**. That is strictly
worse than pi's `--session-id <id>` "create if missing", because there is a window between spawn
and id-capture in which a crash leaves an orphan the supervisor cannot name.

**However**, the binary contains a session-creation path that *accepts* an id and branches on
whether it already exists on disk — two distinct code sites, VERIFIED in the 0.223.0 strings:

```js
… getSessionMessagesPath(o, Dt); if (ye.existsSync(pt)) try {
      l("[Session] Session already exists locally, loading instead", {sessionId: o}),
      await this.loadSession(o, {…}) …

… getSessionMessagesPath(o, b);  if (ye.existsSync(T))
      throw new a("Session already exists locally", {sessionId: o}); …
      H = {type:"session_start", id:o, title:E, owner:…, organizationId:…}
```

That is create-with-caller-supplied-id, including writing `session_start` with `id: o`. It is
almost certainly reachable through `droid.initialize_session` over JSON-RPC or through the daemon.
**I could not confirm the parameter name, and I will not guess it** — the published
`droid.initialize_session` example shows only `machineId`, `cwd` and `disableBuiltinSkills`.
**UNKNOWN, and worth one hour of spike time**, because confirming it upgrades this axis from
"scrape the id" to "assign the id", which is what the owner asked for.

### Listing and resuming

- `droid --resume [sessionId]` / `-r`; `droid resume [sessionId]`; `--last` skips the picker and
  takes the most recent session **in the current folder**; `--fork <sessionId>` branches into a new
  id. (VERIFIED from `--help`.)
- `droid exec -s <id> "…"` continues headlessly; `droid exec --fork <id> "…"` branches.
- SDK `listSessions({limit, fetchOutsideCWD})` reads **local session storage without starting Droid
  or calling the API** — cheap, and safe to poll. Returns id, title, owner, message count, creation
  and modification time, cwd; sorted by `modifiedTime` descending.
- `droid search --json <query>` searches across local sessions (`--kind
  message_text|document|tool_use|tool_result|all`, `--reindex`).
- REST `GET /api/v0/sessions`, `GET /api/v0/sessions/{sessionId}` — but see the `computerId`
  caveat in axis G; these are the Droid Computers plane, not your local CLI.

### What survives a crash, a reboot, an outage

**Survives (VERIFIED, docs + on-disk evidence):** conversation history, working directory, title,
and session settings (model, reasoning, interaction mode, autonomy, spec-mode model settings, tool
overrides, custom system prompt). The transcript is append-only JSONL on disk (§C), so a hard kill
loses at most the in-flight turn.

**Does not survive — must be re-attached on every resume:** permission handler, AskUser handler,
SDK MCP servers, observability sinks, abort signal. These are runtime objects Droid cannot
serialize. **This is an operational trap**: a supervisor that resumes a session and forgets to
re-attach `askUserHandler` gets a session that silently declines every question it asks (see axis
G), which looks exactly like a hung agent.

**Failure modes to code against:** `SessionNotFoundError`, and `InvalidSessionCwdError` — *"Saved
working directory is invalid"*. The latter bites when a resumed session's repo was moved or a
worktree was cleaned up, and `resumeSession()` **does not accept a replacement `cwd`**. The RPC
surface has `droid.change_working_directory`, which is the escape hatch, but only after load.

**Provider outage:** Factory Router "routes across multiple models, providers, and capacity sources,
so sessions keep running when a provider degrades, hits rate limits, or constrains capacity", with
"request reliability at 99.9%+" (**CLAIMED**, vendor page, not independently verified). Also
`modelFallbacks` in settings: a `{ "<modelId>": "<fallbackModelId>" }` map (VERIFIED, settings doc).
Because inference is brokered by Factory rather than by your own provider key, a single upstream
provider outage is Factory's problem to route around — genuinely useful for overnight runs, and a
real architectural advantage over a direct-to-Anthropic setup.

---

## C. TRANSCRIPT

**Verdict: excellent — and it carries something no other platform in this scan has.**

### Location and format (VERIFIED empirically on this machine)

```
<factory-home>/.factory/sessions/<cwd-with-slashes-as-dashes>/<sessionId>.jsonl
<factory-home>/.factory/sessions/<cwd-with-slashes-as-dashes>/<sessionId>.settings.json
```

Observed directly in the sandbox after a single `droid exec` attempt:

```
~/.factory/sessions/-Users-sasha-marchuk-Work-claude-plugins-product-spikes-harness-rebuild-round-1/
    8564e028-5d4a-4644-a545-0c20e8ead1dc.jsonl
    8564e028-5d4a-4644-a545-0c20e8ead1dc.settings.json
```

The project directory encoding is the cwd with `/` replaced by `-`, identical in spirit to Claude
Code's `projects/` layout. Files are mode `0600`, the directory `0700`.

First line of the JSONL (VERIFIED, actual file content):

```json
{"type":"session_start","id":"8564e028-…","title":"x","owner":"sasha-marchuk",
 "version":2,"cwd":"/Users/…/round-1","hostId":"<host-id>"}
```

`version: 2` and a `hostId` that is persisted separately in `~/.factory/host.json`
(`{"schemaVersion":1,"hostId":"…","createdAt":…}`). A supervisor can therefore tell which machine
wrote a session — relevant once Droid Computers or BYOM are in play.

**Documentation drift, flagged:** the hooks doc shows `transcript_path` as
`/Users/.../.factory/**projects**/.../session.jsonl`. The real layout in 0.223.0 is
`.factory/**sessions**/<slug>/<sessionId>.jsonl`. The binary contains no `.factory/projects` string
at all; it does contain `.factory/sessions/`. **Trust the hook's runtime `transcript_path` value,
not the doc's example path.**

### The sidecar — the standout finding

`<sessionId>.settings.json` is written alongside the transcript and holds **live token and credit
accounting**. Actual content from the sandbox run (VERIFIED):

```json
{
  "assistantActiveTimeMs": 0,
  "model": "gpt-5.6-sol",
  "reasoningEffort": "high",
  "interactionMode": "auto",
  "autonomyLevel": "off",
  "autonomyMode": "normal",
  "compactionThresholdCheckEnabled": true,
  "toolExecutionMode": "direct_only",
  "allowSubagentsInScripts": false,
  "tags": [{"name": "exec"}],
  "tokenUsage": {"inputTokens":0,"outputTokens":0,"cacheCreationTokens":0,
                 "cacheReadTokens":0,"thinkingTokens":0,"factoryCredits":0},
  "childInclusiveTokenUsageBySessionId": {},
  "inclusiveTokenUsage": {"inputTokens":0,…,"factoryCredits":0}
}
```

Three things a supervisor gets **for free, by reading a file, with no API call and no auth**:

1. **`factoryCredits` actually spent by this session** — and `inclusiveTokenUsage` plus
   `childInclusiveTokenUsageBySessionId`, i.e. spend *including subagents and mission workers*,
   attributed per child session id. This is the cost-accounting primitive the owner's queue needs,
   and it is better than anything the API offers.
2. **`assistantActiveTimeMs`** — a direct liveness signal. A session whose active time is not
   advancing is not working, regardless of whether its process is alive. The field notes record
   "a shell that can never exit reading as work"; this field is the antidote.
3. The session's **effective** model, reasoning effort, autonomy level and tags, so the supervisor
   can verify a session actually launched with the settings it was told to use.

### Reading it live

Hooks receive `transcript_path` directly in their JSON payload (VERIFIED, hooks doc):

```json
{"session_id":"abc123","transcript_path":"…/session.jsonl","cwd":"/Users/me/project",
 "permission_mode":"off","hook_event_name":"PreToolUse","tool_name":"Create","tool_input":{…}}
```

Also available: `droid search --json` across all local sessions, and — for a session the
orchestrator owns — the `stream-jsonrpc` event feed (`droid.session_notification`), which is the
lowest-latency option and does not require tailing a file at all.

**Cloud mirror:** `cloudSessionSync` defaults to **`true`** — CLI sessions are mirrored to Factory
web. `sessionRetentionDays` (14–365) is org-managed. For a privacy-sensitive overnight queue this
is an opt-out the owner should make deliberately.

---

## D. CONTEXT

**Verdict: the best answer to this axis found anywhere in the scan so far. Read, trigger and proof are all first class.**

The field notes record that *nothing in the current plugin measures a session's context window*.
Droid measures it, exposes it, lets you act on it from outside, and leaves three independent
receipts.

### Reading context fullness — supported

RPC methods present in the 0.223.0 binary (VERIFIED):

```
droid.get_context_stats
droid.get_context_breakdown
```

SDK equivalent `session.getContextStats()` (VERIFIED, docs):

```typescript
const stats = await session.getContextStats();
console.log(stats.used, stats.remaining, stats.limit, stats.accuracy);
```

| Field | Meaning |
| --- | --- |
| `used` | Estimated tokens occupied by prompts, tools, instructions, conversation history |
| `limit` | Active model's maximum input window; unresolved model IDs fall back to the effective compaction limit |
| `remaining` | `Math.max(0, limit - used)` |
| `accuracy` | Currently `estimated` — **Droid approximates tokens from character counts** |

**Two caveats the orchestrator must encode, both stated in the docs:**

- `accuracy` is `estimated`, not measured. Do not build a threshold that assumes precision.
- **`remaining` is room in the model window, not room before compaction.** Droid compacts at a
  configured threshold that is *commonly 250,000 tokens*, which can be far below the model's actual
  window. A supervisor that watches `remaining` against `limit` will be surprised by a compaction
  that fires "early". Watch `used` against `compactionTokenLimit` instead.

`droid.get_context_breakdown` presumably itemises the occupancy (which tools, which history, which
instructions). Its response shape is **UNKNOWN** and is worth capturing in a spike, since it is what
would let a supervisor decide *what* to shed rather than just *that* it must shed.

### Triggering compaction from outside — supported

```
droid.compact_session          # JSON-RPC
```

SDK (VERIFIED, docs):

```typescript
const { session: compacted, removedCount } = await session.compact();
```

The exec docs confirm the raw protocol reaches this: *"Further session methods interrupt work,
update settings, manage MCP servers/tools, inspect context, fork sessions, or compact history."*

**Semantics an orchestrator must handle:** `compact()` is a *replacement*, not a mutation. It
returns a **successor session** and retires the source wrapper. After replacement, operations on the
source throw `SessionReplacedError`; its `id`, `settings` and `cwd` stay readable and `close()`
becomes a no-op; the persisted source session remains loadable later via `resumeSession(sourceId)`.
**So the session id the supervisor is tracking changes at compaction.** Any ticket→session mapping
must be updated on compaction or it will point at a retired session. Also: *do not replace a session
while it has an active stream*, and one handle may have only one active stream
(`ConcurrentStreamError`). `fork()` and `rewind()` share these successor semantics.

### Proof that compaction happened — three independent receipts

1. **`removedCount`** returned by `compact()` — how many messages were summarised away.
2. **A new successor session id**, with the source still on disk and loadable. The before/after pair
   is durable evidence.
3. **Hooks** (VERIFIED, hooks doc):
   - `PreCompact` — fires *before manual or automatic* compaction, with
     `trigger` (`manual` | `auto`), `custom_instructions`, `message_count`, `estimated_tokens`.
   - `SessionStart` — fires with `source: "compact"` *"plus optional prior session IDs"*, i.e. the
     successor announces its parent.

That third receipt is the important one: it fires for **automatic** compaction too, so a supervisor
learns about compactions it did not initiate. And because `PreCompact` carries `estimated_tokens`
and `message_count`, a hook can log the exact pressure at which each compaction fired.

### Custom compaction

Yes, on both sides (VERIFIED, settings doc):

| Setting | Meaning |
| --- | --- |
| `compactionTokenLimit` | Token threshold that triggers automatic compaction (model-dependent default) |
| `compactionTokenLimitPerModel` | `{ "<modelId>": number }` per-model overrides |
| `compactionModel` | Which model performs compaction: `same`, or a specific model ID |

`compactionModel` is a direct cost lever — compaction can be pushed onto a cheap model
(`gemini-3.8-flash` at 0.3×, `gpt-5.6-luna` at 0.08×) while the session itself runs on a strong one.
`PreCompact`'s `custom_instructions` field plus a hook is the "custom compaction" story.
The per-session sidecar exposes `compactionThresholdCheckEnabled`, so the supervisor can verify the
check is live for a given session.

---

## E. QUOTA

**Verdict: the owner's hardest requirement, and the answer is split. The data exists and has exactly the right shape — but only behind an undocumented endpoint. There is no supported way to read remaining capacity.**

### The windows (VERIFIED, pricing doc)

Individual plans are governed by **three independent rolling windows: 5-hour, 7-day, and 30-day.**
Each starts ticking on first use and resets after the window elapses. *"You need headroom in all
three to send a request."* Hitting the 5-hour cap does not consume the weekly or monthly faster.

On top of the windows there are three distinct pools:

| Pool | Behaviour |
| --- | --- |
| **Standard Usage** | Consumed first on Individual plans. Does **not** roll over month to month. |
| **Droid Core** | Free open-weight model pool with **its own separate Rate Limits**, usable after Standard runs out. Same billing, restricted to Core models. |
| **Extra Usage** | Prepaid USD credits, $10 minimum, no expiration, **does** roll over. A toggle that stays on until turned off or exhausted. |

Consumption is credit-based with **per-model multipliers** (see §J), not raw tokens.

Teams seats get Pro rate limits each; Business/Enterprise use contract terms rather than the rolling
model (VERIFIED, org pricing doc).

### Can remaining capacity be read programmatically?

**Not through any supported interface. This is a firm negative, established by enumeration rather
than by failing to find something.**

I enumerated **every operation** in the official OpenAPI spec (60 operations across
`automations/ci`, `computers`, `organization`, `service-accounts`, `sessions`, `wiki`). Then I
counted these substrings across the entire 266 KB spec:

```
'rate_limit': 0   'rateLimit': 0   'remaining': 0   'resets': 0
'resetAt':    0   'quota':     0   'five_hour': 0   'utilization': 0
```

The only usage-shaped endpoints are **org-admin write-side caps**, not personal headroom:

```
GET/PUT /api/v0/organization/usage/limits/global   # per-user credits CEILING
GET/PUT /api/v0/organization/usage/limits/users    # per-user overrides, bulk by email
```

Those configure what a user is *allowed* to spend. They do not report what is *left* in a rolling
window. `/limits` in the CLI is an **interactive TUI slash command** ("Manage token usage limits and
overage preferences"), and the documented monitoring path is **Settings → Usage** in the web app.
Neither is scriptable.

### The undocumented endpoint that does have the right shape

Extracted from the 0.223.0 binary (VERIFIED — this is the CLI's own code, reformatted):

```js
async function fetchBillingLimits() {
  if (config().airgapEnabled) return {type:"skipped", reason:"airgap"};
  const r = await authedFetch("/api/billing/limits", {method:"GET"}, auth);
  if (!r.ok) return {type:"http-error", status: r.status};
  return {type:"ok", data: await r.json()};
}

// exhaustion test, verbatim logic:
const windowActive  = (b) => new Date(b.windowEnd).getTime() >= Date.now();
const bucketMaxed   = (b) => windowActive(b) && b.usedPercent >= 100;
const isExhausted   = (l) => bucketMaxed(l.fiveHour) || bucketMaxed(l.weekly) || bucketMaxed(l.monthly);
```

The response shape, reconstructed from the consuming code (VERIFIED by usage, not by schema):

```jsonc
{
  "limits": {
    "standard": { "fiveHour": {"usedPercent": 0, "windowEnd": "<ISO>"},
                  "weekly":   {"usedPercent": 0, "windowEnd": "<ISO>"},
                  "monthly":  {"usedPercent": 0, "windowEnd": "<ISO>"} },
    "core":     { "fiveHour": {…}, "weekly": {…}, "monthly": {…} }
  },
  "extraUsageBalanceCents": 0,
  "overagePreference": null,          // "extraUsage" | "droidCore" | …
  "extraUsageAllowed": true,
  "canManageOverage": true
}
```

Authenticated with the same bearer the CLI uses (`FACTORY_API_KEY` works for the public API).
The companion write endpoint is `POST /api/organization/subscription/set-overage-preference` with
`{"overagePreference": …}`.

**This is exactly the shape of the owner's existing Claude Code quota check** — `usedPercent` maps
to `utilization`, `windowEnd` maps to `resets_at` — with a third (monthly) window and a separate
Core pool. A supervisor could implement the owner's 80/90/95% throttle policy against it verbatim.

**But it is unsupported.** It is absent from `openapi.json`, absent from the docs, and lives under
`/api/billing/` rather than `/api/v0/`. It has no version guarantee and can change in any of the
near-daily releases. Using it is a deliberate bet; the mitigation is a contract test that fails
loudly when the shape changes, plus a fallback to the in-band signal below.

### What *is* supported: spend, not headroom

Per-turn **spend** is well exposed, which is a different and lesser thing:

- SDK `DroidResult.tokenUsage` → `inputTokens`, `outputTokens`, `cacheReadTokens`,
  `cacheCreationTokens`, `thinkingTokens`, and **`factoryCredits`** (credits charged for that turn,
  when available). `tokenUsage` is `null` when usage is unavailable.
- `DroidMessageType.TokenUsageUpdate` partial events carry **cumulative committed usage for the
  session**.
- The on-disk `.settings.json` sidecar (§C) carries the same fields, including subagent-inclusive
  totals per child session id — readable with no API call.

A supervisor can therefore track *burn rate* precisely and *headroom* only by inference (or via the
undocumented endpoint).

### Is a limit-hit signalled in-band, and is a reset time exposed?

**In-band: yes.** *"The current request finishes, then subsequent requests receive a Rate Limit
error in the CLI or Factory App."* Missions specifically **pause** when they hit a rate limit
(VERIFIED, pricing doc). For the REST plane, `CreateSession429ResponseBody` exists — but its schema
is the generic error envelope (`detail`, `status`, `title`, plus an untyped `metadata` object), so
**there is no typed reset field on the 429** (VERIFIED from the spec). Whether `metadata` carries a
reset in practice is **UNKNOWN**.

**Reset time: only via the undocumented endpoint** (`windowEnd` per bucket). The binary formats it
for humans as `in 3h 20m` / `Nov 22`, which confirms it is a real timestamp.

**Notably absent: telemetry does not help.** I checked the full OTel data reference. The `droid.*`
metric catalog has counters for files, lines, commits, PRs, tool invocations, MCP calls, skills,
hooks, slash commands, logins and sessions — **but no token or credit metric at all**. The `genai`
format exports durations and call counts, again no tokens. So an org's own collector cannot be used
as a quota oracle either.

### Degradation instead of stopping

Worth noting for an overnight queue: Droid offers a graceful path the owner's current setup lacks.
When Standard is exhausted the CLI can switch the session to a **Droid Core** model and keep going
on a separate limit pool, or draw down **Extra Usage**. The binary does this programmatically —
`setModel(recommendedCoreModel)` with a `source: "detector_recovery"` event. An orchestrator could
implement "downshift to Core at 90% rather than pause" as a policy. That is a materially better
overnight story than a hard stop.

---

## F. ACCOUNTS

**Verdict: strong for new sessions — the mechanism is clean and matches what the owner already built for Claude Code. Changing a running session's account is impossible.**

### Several accounts on one machine — yes, cleanly

The decisive mechanism, VERIFIED from the binary (this is the CLI's actual home-directory resolver):

```js
function factoryHome() {
  return process.env.FACTORY_HOME_OVERRIDE
      ?? process.env.HOME
      ?? process.env.USERPROFILE
      ?? process.cwd();
}
```

**`FACTORY_HOME_OVERRIDE` is checked before `HOME`.** Setting it relocates the entire `.factory/`
tree. That tree contains everything that constitutes an account — confirmed from the binary's own
logout/cleanup routine, which walks exactly these entries:

```
directories: sessions, updates, logs, droids
files:       auth.json, config.json, history.json, mcp.json, settings.json
```

plus, observed empirically in the sandbox: `host.json`, `cache/`, `certs/`, `telemetry/`, `temp/`,
`background-tasks.json`, `background-processes.json`, `task-invocations.json`,
`last-startup-version`.

**Credentials live in `auth.json` inside that tree.** So `FACTORY_HOME_OVERRIDE=/path/to/acct-a` is
a complete per-account jail — auth, settings, MCP config, custom droids and session history all move
together. This is directly analogous to the `CLAUDE_CONFIG_DIR` mechanism the owner's profile switcher
already exploits, and the same "profiles are discovered directories" pattern would work unchanged.

### Switching a NEW session to a chosen account

Four mechanisms, in increasing order of isolation (all VERIFIED):

| Mechanism | Scope | Notes |
| --- | --- | --- |
| `FACTORY_API_KEY=fk-…` | Per process | Simplest for headless. Keys from app.factory.ai/settings/api-keys, or minted per role via the Service Accounts API |
| `FACTORY_HOME_OVERRIDE=<dir>` | Per process, total | Full account jail: auth + settings + sessions + droids + MCP |
| `--settings <path>` | Per process | *"Path to runtime settings file merged for this process only"* — change model/autonomy/policy without touching the owner's files. Available on `droid`, `droid exec`, `droid resume` and `droid daemon` |
| Service accounts | Per role, server-side | `POST /api/v0/service-accounts`, `…/api-keys`, plus `/rotate` and `/revoke` |

The service-account path deserves emphasis for an unattended queue: **roles can have their own
non-human identities with independently rotatable and revocable keys**, and org admins can set
per-user credit ceilings on them (`PUT /api/v0/organization/usage/limits/users`, bulk, by email).
That is a cleaner per-role story than sharing one human's subscription.

### The macOS Keychain trap — and Droid's escape hatch

The field scan flagged that an unattended Claude Code run can **block on a GUI Keychain dialog** for
an account that has never been granted "Always Allow". Droid has the same exposure — and a
documented-by-existence way out:

```
FACTORY_DISABLE_KEYRING     # VERIFIED env var; parsed as a lowercased boolean into `disableKeyring`
FACTORY_KEYTAR_PATH         # VERIFIED env var
```

Setting `FACTORY_DISABLE_KEYRING` forces credential storage off the system keyring. Combined with
`FACTORY_HOME_OVERRIDE`, an unattended supervisor can run entirely on file-based credentials and
never risk a modal dialog. **The exact accepted values are UNKNOWN** (the binary lowercases the
string and passes it to a boolean coercion), so a spike should confirm `1` / `true` empirically
rather than guessing.

### Verifying which account a home holds — scriptable

`droid doctor --json --auth` works **without being logged in** and reports credential state.
VERIFIED by running it in the sandbox:

```json
{"id":"auth.credentials","category":"auth","label":"Credential storage read",
 "status":"pass","detail":"credential storage responded; no stored login found","durationMs":0}
```

It also emits `env.info` with `factoryDir`, `apiBaseUrl`, `appBaseUrl`, `cliVersion`, `runtime`.
So a supervisor can cheaply assert "this `FACTORY_HOME_OVERRIDE` is logged in as the expected
account" before dispatching work to it. There is also `GET /api/auth/whoami` and
`/api/app/auth/me` in the binary (undocumented).

### Changing a RUNNING session's account

**Not possible.** (VERIFIED by absence across every surface.) `updateSettings()` covers model,
reasoning effort, interaction mode, autonomy level, spec-mode model settings and tool availability —
and nothing else. There is no `droid.*` RPC method for credentials (the full method list is in §G;
the only auth-adjacent methods are MCP-server auth). Identity is fixed at process start by the
environment.

**Workaround and its cost:** interrupt (`droid.interrupt_session`), close, then re-launch with
`droid exec -s <sessionId>` or `resumeSession()` under the new `FACTORY_HOME_OVERRIDE` /
`FACTORY_API_KEY`. Because history, cwd, title and settings all persist (§B), the conversation
survives intact. **The cost is one killed turn plus re-attaching handlers** — and the in-flight
turn's work is lost, so the supervisor should prefer switching at turn boundaries. In practice this
is acceptable: it is the same "pause, swap, resume" the owner already does per rate-limit window.

### Cross-provider identity (BYOK)

Custom models carry their own credentials in `customModels[]` in `~/.factory/settings.json`, with
`${ENV_VAR}` interpolation for `apiKey`, plus **`apiKeyHelper`** for minting short-lived tokens at
request time and `extraHeaders` for gateway auth. Keys stay local and are not uploaded to Factory.
Referenced as `--model "custom:<Display-Name>-<index>"`. Org admins can restrict this with
`modelPolicy.allowCustomModels` and `modelPolicy.allowedBaseUrls`.

This matters for the owner's wider plan: Droid is one of the platforms where the "same adapter,
different base URL + token" trick from the field scan works, via `provider:
"generic-chat-completion-api"` — the BYOK docs even use a Kimi-on-Groq example.

---

## G. INTERVENTION

**Verdict: best in class. This is the axis where the current harness fails, and Droid answers every part of it — with one important default that will bite an unattended run.**

### The control protocol

```bash
droid exec --input-format stream-jsonrpc --output-format stream-jsonrpc --auto low
```

Line-delimited JSON-RPC over stdin/stdout. Each stdin line is one request; each stdout line is a
response, a server→client request, or a notification. The client matches responses by `id` and owns
timeouts, process cleanup and session persistence. CLI flags do **not** configure an RPC session
(`-m`, `--auto`, `-r`, `--disable-builtin-skills` are validated but session settings come from the
RPC requests themselves) — a genuine gotcha, VERIFIED from the binary's own help text.

**The complete `droid.*` method inventory**, extracted from the 0.223.0 binary (VERIFIED — the docs
name only five of these):

```
Session lifecycle
  droid.initialize_session      droid.load_session          droid.close_session
  droid.fork_session            droid.compact_session       droid.execute_rewind
  droid.get_rewind_info         droid.rename_session        droid.update_session_settings
  droid.change_working_directory

Turns and intervention
  droid.add_user_message        droid.append_messages       droid.resolve_queued_user_message
  droid.interrupt_session       droid.kill_worker_session

Questions and permissions (server → client)
  droid.request_permission      droid.permission_wait
  droid.ask_user                droid.ask_user_wait

Context
  droid.get_context_stats       droid.get_context_breakdown

Discovery
  droid.list_tools              droid.list_models           droid.list_skills
  droid.list_commands           droid.set_skill_disabled

MCP
  droid.add_mcp_server          droid.remove_mcp_server     droid.toggle_mcp_server
  droid.toggle_mcp_tool         droid.list_mcp_servers      droid.list_mcp_tools
  droid.list_mcp_registry       droid.authenticate_mcp_server
  droid.submit_mcp_auth_code    droid.submit_mcp_auth_error
  droid.cancel_mcp_auth         droid.clear_mcp_auth
  droid.refresh_connector_tool_catalog

Events / misc
  droid.session_notification    droid.submit_bug_report
```

Example initialization (VERIFIED, from the exec docs):

```json
{"jsonrpc":"2.0","id":"1","method":"droid.initialize_session","params":{"machineId":"my-machine","cwd":"/workspace","disableBuiltinSkills":true}}
{"jsonrpc":"2.0","id":"2","method":"droid.load_session","params":{"sessionId":"session-123","disableBuiltinSkills":true}}
```

### Send an instruction into a running session, and know it arrived

**Yes.** `droid.add_user_message` sends a turn; the JSON-RPC response correlated by `id` is the
acknowledgement. `droid.resolve_queued_user_message` handles the case where a message was queued
rather than consumed immediately — which is precisely the "stranded text that cannot be submitted"
failure the field notes record for the current harness. `droid.append_messages` exists for bulk
history injection.

This is a real, correlated, in-band acknowledgement — not a screen-scrape and not a keystroke.

### Answer a permission prompt programmatically

**Yes.** `droid.request_permission` is a **server→client** request the client must answer
(`droid.permission_wait` is the paired wait state, useful for detecting a stalled decision).

SDK form (VERIFIED, docs):

```typescript
const session = await createSession({
  autonomyLevel: AutonomyLevel.Off,
  permissionHandler({ toolUses, options }) {
    // toolUses = pending actions; options = outcomes offered for THIS request
    return ToolConfirmationOutcome.ProceedOnce;   // or ProceedAlways | Cancel
  },
});
```

Outcomes: `ProceedOnce` (approve this request), `ProceedAlways` (approve **and persist the rule**),
`Cancel`. Available outcomes vary per request, so the handler must pick from the supplied `options`.
**Returning an unavailable value, throwing from the handler, or omitting the handler all cancel the
request.** A supervisor policy layer can approve, deny, transform or audit every tool call.

`ToolConfirmationType.ExitSpecMode` is a special case: approving it with `ProceedOnce` accepts a
completed plan, returns the session to Auto mode and continues implementation *in the same session*
— whereas `updateSettings({interactionMode: Auto})` leaves spec mode **without** approving the plan.
An orchestrator running plan-then-execute must not confuse the two.

### Answer the session's own clarifying question

**Yes** — `droid.ask_user` / `droid.ask_user_wait`, SDK `askUserHandler`:

```typescript
askUserHandler({ questions }) {
  return { answers: questions.map(q => ({ index: q.index, question: q.question,
                                          answer: q.options[0] ?? 'none' })) };
}
// decline the whole questionnaire:
// return { cancelled: true, answers: [] };
```

Each answer must echo the question's `index` and `question` text.

> **The one default that will bite an unattended run:**
> **"Without a handler, AskUser requests are declined."**
> Combined with the §B finding that handlers are **not** persisted across `resumeSession()`, this
> is a live trap: resume a session, forget to re-attach `askUserHandler`, and every question the
> agent asks is silently refused. The agent then proceeds on its own assumptions. **This will not
> look like an error in any log** — it looks like a session that made bad decisions. Any adapter
> must re-attach both handlers on every resume, and should log every declined question.

### Detecting a session that is stuck waiting

The `Notification` hook fires with `notification_type` ∈ `permission_prompt`, `idle_prompt`,
`auth_success`, `elicitation_dialog` (VERIFIED, hooks doc). `permission_prompt` means "waiting for
permission"; `idle_prompt` means "waiting for user input, including immediately after the user
cancels a turn". A supervisor watching hooks can distinguish *working* from *blocked* without
parsing a TUI. Note that **cancellation emits `Notification`, not `Stop`** — a `Stop`-based
completion detector will miss cancelled turns.

### Interrupting

`droid.interrupt_session` (RPC), `session.interrupt()` + `AbortSignal` (SDK),
`POST /api/v0/sessions/{sessionId}/interrupt` (REST). A cancelled turn returns result subtype
`interrupted` with `success:false, interrupted:true`.

### The REST Sessions API — read the fine print

`POST /api/v0/sessions` **requires `computerId`** and `PostMessageRequestBody` routes by
`computerId` too. This plane drives **Droid Computers** — Factory-managed remote environments or
your own machine registered via `droid computer register` (BYOM) — *not* an arbitrary local `droid`
process. `GET /api/v0/sessions/{id}` returns `status` ∈ `idle` | `pending` | `running`,
`messageCount`, `createdAt`/`updatedAt`/`completedAt`, and `parent_session_id` for Task subagents.

So there are **two** remote-control stories: JSON-RPC over stdio for sessions you spawn, and REST
for sessions on a registered computer. For the owner's local overnight queue, JSON-RPC is the one
that matters; BYOM is the path if he ever wants to drive the Mac from elsewhere.

---

## H. GUARDRAILS

**Verdict: the most thorough guardrail surface in the scan, and the unattended defaults are sane.**

### Autonomy tiers (VERIFIED from `droid exec --help`, quoted)

| Level | Allows | Blocks |
| --- | --- | --- |
| *default, no flag* | Read-only: `cat`, `head`, `ls`, `find` (without `-delete`/`-exec`), `git status\|log\|diff`, `ps`, `whoami` | Any modification |
| `--auto low` | File creation/modification in non-system dirs: `touch`, `mkdir`, `mv`, `cp` | System changes, package installs |
| `--auto medium` | Trusted package installs, `curl`/`wget` to known APIs, local git (`commit`, `checkout`, `pull`), builds | **`git push`**, sudo, production changes |
| `--auto high` | `curl \| bash`, port/firewall changes, **`git push`**, deployments, DB migrations, credential-touching commands | `sudo rm -rf /`, system-wide changes |
| `--skip-permissions-unsafe` | Everything, no confirmation | **Cannot be combined with `--auto`** |

`AutonomyLevel.Off` (SDK) asks before every action. `subagentAutonomyLevel` (`inherit` by default)
governs Task-spawned subagents and is **clamped to the org-managed `maxAutonomyLevel`**; mission
workers do not use it.

**Fail-fast is the documented default:** an action exceeding the current autonomy level stops
immediately with a clear error, non-zero exit, and **no partial changes**.

### Sandboxing (VERIFIED, sandbox doc)

Kernel-enforced, not self-policed: **Seatbelt on macOS**, **bubblewrap + seccomp** on Linux/WSL2,
and an HTTP/SOCKS filtering proxy for network on all platforms. If the primitives are unavailable it
**blocks rather than running unisolated**.

| Resource | Default |
| --- | --- |
| File reads | Allow all except explicit `denyRead` |
| File writes | **Deny all except CWD**; `denyWrite` overrides `allowWrite` |
| Network | **Deny all** except Factory's own and WorkOS auth domains |

Modes: `per-command` (default — each shell command and its children isolated; main process is not)
and `whole-process` (the entire Droid process, including MCP transports and subagents; **refuses to
start** if isolation cannot be established). Hooks are wrapped by the sandbox and **blocked** if it
cannot be established. Subagents inherit the parent policy. Sandboxed tool processes **cannot write
to Droid's own config files**, so policy cannot be silently self-modified.

> **The single most important unattended property found on this axis:**
> *"Non-interactive mode (`droid exec`): sandbox violations are **auto-denied without prompting**:
> no hang, no user interaction required. The agent receives a denial message and reports it in the
> output."*
> In the TUI the same violation **interrupts the agent loop with a prompt even at Auto (High)**.
> An overnight queue must therefore use `droid exec`, not a driven TUI, or a sandbox violation at
> 03:00 becomes a hang.

Network violations in TUI show a domain prompt with a **60s auto-deny timeout**.

### Command lists

`commandAllowlist` (run without extra confirmation), `commandDenylist` (always require
confirmation; can still be approved), and a **blocklist** that always wins. Commands in both allow
and deny default to deny. Anything in no list falls back to the session's autonomy level.

### Hooks as policy

Events: `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Notification`, `Stop`, `SubagentStop`,
`PreCompact`, `SessionStart`, `SessionEnd`. Control semantics:

| Event | Control |
| --- | --- |
| `PreToolUse` | Block risky operations, approve safe tools, **rewrite tool input** |
| `PostToolUse` | `decision:"block"` sends `reason` back after the tool ran; `additionalContext` |
| `UserPromptSubmit` | `decision:"block"` prevents processing; `additionalContext` appended otherwise |
| `Stop` / `SubagentStop` | `decision:"block"` **prevents stopping** — include `reason` so Droid knows what to do next |
| `SessionEnd` | **Cannot block** termination; cleanup/logging only |

`Stop` carries `stop_hook_active`, `tool_execution_count`, `elapsed_time` — enough to implement
"don't stop until tests pass" deterministically. Configured in `~/.factory/hooks.json`,
`<project>/.factory/hooks.json`, or inline in settings. Org admins can force
`allowManagedHooksOnly: true`.

### Org-level hard controls

`maxAutonomyLevel` (clamps everyone), `modelPolicy` (`allowedModelIds`, `blockedModelIds`,
`allowCustomModels`, `allowedBaseUrls`), `mcpPolicy` (`enabled`, `allowlist`),
`mcpAutonomyOverrides`, `mcpAutonomyUrlOverrides`, `networkPolicy.allowedIps`, `missionPolicy`,
`webSearchDisabled`, `sessionRetentionDays`, `disableAutoUpdate`. Plus **Droid Shield**, automatic
secret detection on commits and pushes.

### Tool controls — **documentation drift, trust the binary**

| Source | Flags |
| --- | --- |
| **Binary 0.223.0 (VERIFIED)** | `--only-tools <ids>`, `--add-tools <ids>`, `--remove-tools <ids>` |
| Docs (`/droid-exec/overview`) | `--restrict-tools`, `--additional-tools`, `--disabled-tools` |

The docs are stale. Selectors accept tool IDs or `MCP:<server>[/<tool>]`. `--list-tools` enumerates
what the selected model can use (combine with `--output-format json`). Note the SDK is weaker than
the CLI here: it exposes only subtractive `disabledToolIds` and **"does not expose a restrictive
allowlist"**.

---

## I. EXTENSIBILITY

**Verdict: strong, and structurally very close to Claude Code — a GSD-style workflow would port with modest effort.**

| Capability | Surface |
| --- | --- |
| **MCP** | `droid mcp add\|remove\|list\|permissions`; `~/.factory/mcp.json` and `<project>/.factory/mcp.json`; RPC methods for add/remove/toggle/auth; SDK in-process MCP servers (`createSdkMcpServer`, `tool()`); org `mcpPolicy` allowlist |
| **Skills** | `SKILL.md` files in `~/.factory/skills/` and `<project>/.factory/skills/`; `/skills`, `/create-skill`; `--disable-builtin-skills` (also `disableBuiltinSkills` on `initialize_session`/`load_session`); **inherited by child sessions, subagents and mission workers** |
| **Subagents ("custom droids")** | `<project>/.factory/droids/*.md` and `~/.factory/droids/`; own system prompt, model and tool policy, fresh context window; complexity tiers `light`/`medium`/`heavy` each pinnable via `subagentModelSettings.{light,medium,heavy}Model` + reasoning effort; built-ins `explorer` (light) and `worker` (medium) |
| **Slash commands** | `<project>/.factory/commands/` — reusable Markdown prompts **or executable scripts** |
| **Plugins** | `droid plugin install\|uninstall\|update\|list`, `droid plugin marketplace`; bundles of commands, droids, skills, output styles, hooks and MCP servers; enterprise **internal marketplaces** |
| **Project instructions** | `AGENTS.md` (and `.factory/system.md`) |
| **Output styles** | `default`, `concise`, or custom in `.factory/output-styles/` |

**Settings precedence.** Files: `~/.factory/settings.json`, `~/.factory/settings.local.json`,
`<project>/.factory/settings.json`, `<project>/.factory/settings.local.json`; local overrides merge
on top at the same level. Documented resolution order is **org > project > user**, with
`denyWrite`/`denyRead` using **union merge so org denies cannot be removed downstream**. The binary
carries a richer origin set than the docs describe (VERIFIED): `org-remote`, `org-plugin`,
`runtime`, `runtime-generated`, `automation`, `folder`, `project-settings`, `project-agent-dir`,
`project-plugin`, `user-settings`, `user-agent-dir`, `user-plugin`, `dynamic`, `builtin`. The exact
total ordering across all fourteen is **UNKNOWN**.

**`--settings <path>` is the orchestrator's friend**: *"Path to runtime settings file merged for
this process only"*, available on `droid`, `droid exec`, `droid resume` and `droid daemon`. A
supervisor can give each task its own model, autonomy, compaction threshold and tool policy without
ever writing to the owner's `~/.factory/settings.json`. Related: `FACTORY_RUNTIME_SETTINGS_PATH`,
`FACTORY_RUNTIME_SETTINGS_SHA256` and `FACTORY_RUNTIME_SETTINGS_SOURCE` exist as env vars, with the
binary validating the settings file against a SHA-256 — i.e. runtime settings are integrity-checked.

### Can a GSD-style, subagent-heavy engine run inside it?

**Yes.** Skills + custom droids + hooks + slash commands + MCP is close to a one-to-one mapping of
the Claude Code concepts GSD is built on, down to `AGENTS.md` ≈ `CLAUDE.md` and
`.factory/` ≈ `.claude/`. Three caveats:

1. `allowSubagentsInScripts` appears in the session sidecar and defaulted to **`false`** in the
   observed `droid exec` run. A subagent-heavy workflow launched headlessly may need this enabled;
   its configuration surface is **UNKNOWN**.
2. `subagentInactivityTimeout` (ms) governs when Droid treats a worker as stalled — a real knob for
   long-running GSD phases that would otherwise be declared dead.
3. Droid ships its **own** orchestrator (Missions, §J), so a GSD-style engine would be duplicating a
   native capability. Missions provide orchestrator/worker/validator roles with independent model
   selection (`missionOrchestratorModel`, `missionModelSettings.workerModel`,
   `missionModelSettings.validationWorkerModel`), run headlessly via `droid exec --mission`, and
   inherit MCP, skills, hooks, custom droids and `AGENTS.md`. **But Missions require `--auto high`
   or `--skip-permissions-unsafe`, require Extra Usage to be enabled, and pause on rate limits.**

---

## J. OPERATIONAL REALITY

### Cost model

Subscription + credit multipliers, not raw token billing (VERIFIED, pricing and models docs).

| Plan | Price | Usage |
| --- | --- | --- |
| Pro | $20/mo | Baseline |
| Plus | $100/mo | ~5× Pro, adds managed Droid Computers |
| Max | $200/mo | ~10× Pro, early feature access |

Credit **multipliers** are the real cost lever, and the spread is enormous (VERIFIED):

| Cheap | × | Expensive | × |
| --- | --- | --- | --- |
| `gpt-5.6-luna` | 0.08× | `gpt-5.5-pro` | 12× |
| `gemini-3.8-flash` | 0.3× | `gpt-6-astra` | 4× |
| `claude-haiku-4-5-20251001` | 0.4× | `claude-fable-5.1` | 4× |
| `claude-sonnet-5` | 0.8× | `claude-opus-5-fast` | 4× |
| `gpt-5.6-terra` | 0.8× | `claude-opus-5` | 2× |

A 150× spread between the cheapest and dearest model means **model routing, not run scheduling, is
the dominant cost control**. Combined with `compactionModel` (§D), `--worker-model` /
`--validator-model` (§I) and per-tier `subagentModelSettings` (§I), an orchestrator can put strong
models only where they matter. `gpt-5.6-sol` is promotionally 1.6× **through 2026-11-22**, then
returns to 2× — a dated fact that will silently change the economics of any queue pinned to it.

BYOK is free up to an allowance on all Individual plans, then charged per plan.

### Maturity

Very actively developed, commercially serious, but **closed and fast-moving**: 213 npm versions, the
last 15 spanning 0.212.0 → 0.223.0, with releases landing near-daily (0.223.0 published the morning
of this research). The CLI is `UNLICENSED`; the public GitHub repo is a 24-star distribution and
issue tracker with no source. The SDKs are Apache-2.0 but at **0.9.1 (TS)** and **0.4.0 (Python)** —
pre-1.0, so their APIs can still move. Enterprise posture is mature (SOC-2 claimed, airgapped
deployment, SSO/SCIM, OTel export, audit log).

### Platform support

macOS is first class: Homebrew cask, native Seatbelt sandboxing, signed platform binaries for
darwin-arm64. Verified running on darwin 25.5.0 arm64 at 0.223.0 with Bun 1.4.2.

### Known unattended-run failure modes

Ranked by how likely they are to ruin an overnight queue:

1. **Silent AskUser declines** (§G). No handler → every clarifying question refused, and handlers do
   **not** survive resume. Fails quietly and looks like bad judgement, not an error.
2. **Auto-update version drift.** Standalone installs *"check for and install CLI updates
   automatically"*. A queue can start on 0.223.0 and finish on 0.224.0 with different flags — and
   this scan already found two flag names that moved. Mitigations: install via **npm** (auto-update
   disabled at build time) or set `FACTORY_DROID_AUTO_UPDATE_ENABLED=false`, which the docs
   explicitly say must be set *"in the environment that launches every Droid process, including
   `droid daemon`"*.
3. **Rate-limit pause with no readable headroom** (§E). Missions pause; ordinary sessions error.
   Without `/api/billing/limits` the supervisor cannot pre-empt this, only react.
4. **Session-id churn at compaction** (§D). The tracked id becomes a retired id.
5. **TUI blocks where exec does not** (§H). Sandbox violations prompt in the TUI even at Auto High.
6. **`InvalidSessionCwdError`** on resume after a worktree is cleaned up (§B) — and clean worktrees
   are auto-removed on exit, while dirty ones are preserved.
7. **Keychain modal** for a never-granted account (§F), mitigated by `FACTORY_DISABLE_KEYRING`.
8. **`--skip-permissions-unsafe` cannot be combined with `--auto`** — a config generator that emits
   both produces an invalid command.

### Useful operational primitives

- **`droid doctor --json`** — scriptable preflight covering configuration, connectivity,
  certificates, proxy, auth and daemon transport, with `--verbose`, `--timeout <ms>` and
  category filters. **Runs without authentication** (VERIFIED by running it), so it is safe as a
  pre-dispatch health gate. Observed checks include `configuration.valid`, `env.info`,
  `proxy.env`, `proxy.system`, `certs.loaded`, `auth.credentials`, `auth.workosRefresh`,
  `daemon.loopback`.
- **Git worktrees** (`-w/--worktree [name]`, `worktreeDirectory` default `~/.factory/worktrees`) —
  parallel tasks on one repo without file conflicts. Clean worktrees auto-removed on exit, dirty
  ones preserved for review.
- **`--tag` and `--log-group-id`** — first-class run labelling for correlating a queue's runs.
- **`keepSystemAwakeDuringMissions`** defaults to **`true`** — the OS will not sleep mid-mission.
  Directly relevant to an overnight run on a laptop.
- **`llmRequestTimeout`** and **`subagentInactivityTimeout`** — configurable stall detection.
- **Background task tracking** — `~/.factory/background-tasks.json` records `{taskId, pid, status,
  parentSessionId, parentPid}`, and the CLI reaps dead PIDs (`process.kill(pid, 0)`) and kills
  children on shutdown. A supervisor can read this file to find orphans.
- **`DROID_PARENT_SESSION_ID`** — sets session lineage for telemetry; the docs specifically
  recommend it *"to attribute headless or CI runs"*.
- **`FACTORY_AIRGAP_ENABLED`** — disables outbound calls including the billing-limits probe.

### Is it plausible to run unattended overnight today?

**Yes — with more confidence than most of the field.** `droid exec` is purpose-built for it,
autonomy tiers are explicit and fail fast, sandbox violations auto-deny rather than hang, the
control protocol answers questions and permissions programmatically, and Missions provide native
multi-agent orchestration. The two things that require deliberate engineering are **pinning the
version** (or accepting drift) and **quota headroom**, which has no supported read.

---

## What this costs the orchestrator

A per-axis accounting of what a Droid adapter must build, and what it cannot have.

| Axis | Cost |
| --- | --- |
| **A. Launch** | **Near zero.** `droid exec --output-format json` for fire-and-forget; `stream-jsonrpc` for controlled runs. The only real work is a line-delimited JSON-RPC client with id correlation — which is reusable across platforms, and the same shape pi needs. Budget: one transport, shared. |
| **B. Identity & resume** | **Moderate, with one sharp edge.** Sessions cannot be pre-named through any documented surface, so the adapter must capture `session_id` from the first JSON response and persist it **before** doing anything else — there is a crash window in between. Add re-attachment of `permissionHandler` and `askUserHandler` on **every** resume (forgetting is silent). Handle `InvalidSessionCwdError` by calling `droid.change_working_directory` after load. **Spike first:** whether `droid.initialize_session` accepts a caller-supplied session id — the binary's create path clearly does, and confirming it removes the sharp edge entirely. |
| **C. Transcript** | **Negative cost — Droid gives more than asked.** JSONL at a derivable path, a `transcript_path` handed to every hook, `droid search --json`, and a live event stream. The `.settings.json` sidecar supplies per-session credit spend (including subagents, attributed by child session id) and `assistantActiveTimeMs` for liveness, with no API call and no auth. Budget: a file reader. Decide deliberately whether to leave `cloudSessionSync` on. |
| **D. Context** | **Low cost, high value.** `getContextStats()` / `droid.compact_session` are one call each, and proof arrives three ways (`removedCount`, successor id, `PreCompact` + `SessionStart{source:"compact"}` hooks). Two behaviours must be encoded: compare `used` against `compactionTokenLimit` rather than `remaining` against `limit`; and **update the ticket→session mapping when compaction returns a successor id**. Set `compactionModel` to something cheap. |
| **E. Quota** | **The expensive one — and the owner's non-negotiable.** No supported read exists; I proved this by enumerating all 60 public API operations. The adapter's realistic options: (a) depend on the undocumented `GET /api/billing/limits`, which returns exactly the right `usedPercent` + `windowEnd` shape across 5h/weekly/monthly and standard/core pools, guarded by a contract test that fails loudly on shape change; (b) estimate headroom from `factoryCredits` burn read off the sidecar, plus model multipliers, and treat it as an approximation; (c) react only to in-band rate-limit errors. **Recommendation: (a) guarded by (c) as fallback.** Also implement the graceful path Droid uniquely offers — downshift to **Droid Core** at ~90% rather than pausing, since Core has its own separate limit pool. |
| **F. Accounts** | **Low for new sessions, impossible for running ones.** `FACTORY_HOME_OVERRIDE` is a complete per-account jail — auth, settings, MCP, droids, sessions — and the owner's existing profile-switcher pattern (profiles as discovered directories, selected by env var) transfers with essentially no redesign. Add `FACTORY_DISABLE_KEYRING` to dodge the Keychain modal, and use `droid doctor --json --auth` as a pre-dispatch identity assertion. **Changing a running session's account costs one killed turn**: interrupt → close → resume under new env. Prefer switching at turn boundaries. Consider service accounts with per-role keys and admin-set credit ceilings rather than sharing one subscription. |
| **G. Intervention** | **Near zero — this axis is solved.** `droid.add_user_message` with id-correlated acknowledgement fixes the "nudge that cannot submit stranded text" failure the field notes record. `permissionHandler` and `askUserHandler` answer permissions and questions in-protocol. **The mandatory cost is discipline, not code:** an `askUserHandler` must be attached on every create *and* every resume, and every declined question must be logged, because the failure is silent. Treat "no handler" as a bug, never a default. |
| **H. Guardrails** | **Near zero, and it removes work elsewhere.** `--auto <level>` plus sandbox plus command lists plus `PreToolUse` hooks is more control than the orchestrator needs to impose itself. **Use `droid exec`, not a driven TUI** — that one decision converts sandbox violations from hangs into auto-denials. Hard-code the binary's flag names (`--only-tools` / `--add-tools` / `--remove-tools`); the docs are stale. |
| **I. Extensibility** | **Low.** `.factory/` maps almost one-to-one onto `.claude/`, so a GSD-style engine ports rather than being rewritten. Use `--settings <path>` for per-task config so the owner's files are never touched. Verify `allowSubagentsInScripts` before relying on subagents in headless runs. Consider whether native **Missions** should replace a hand-rolled orchestrator for some work — noting Missions demand `--auto high` and pause on rate limits. |
| **J. Operational** | **One mandatory task: pin the version.** Install via npm (auto-update disabled at build time) or export `FACTORY_DROID_AUTO_UPDATE_ENABLED=false` in the environment of **every** Droid process including the daemon. Beyond that: `droid doctor --json` as a health gate, `--worktree` for parallel isolation, `--tag`/`--log-group-id` for run correlation, and aggressive model-multiplier routing, where a 0.08×-to-12× spread makes model choice matter far more than scheduling. |

### The two things worth a spike before committing

1. **Does `droid.initialize_session` accept a caller-supplied session id?** The binary contains a
   create-with-id path that writes `session_start` with that id and branches on prior existence. If
   it is reachable, axis B goes from "scrape the id and hope" to "assign the id" — the same
   property that makes pi attractive. One hour of work with a `stream-jsonrpc` client.
2. **What is the `droid daemon` wire protocol?** `--listen websocket|ipc`, `--droid-path` for
   spawning sessions, `--liveness-fd` and `--parent-pid` for supervisor-bound lifetime, and a
   `daemon-core` package with a `terminal` capability. Nothing public documents it. If it is a
   usable multi-session control plane, it is a better foundation than spawning one `droid exec` per
   task — and it may also be where session-id assignment lives.

### Honest comparison to the alternatives

Droid is, on this evidence, **the strongest all-round platform examined so far** — it is the only
one that answers axes C, D, G and H well *simultaneously*, and its transcript sidecar answers a
cost-accounting question nothing else does. pi still wins axis B outright (`--session-id` creates if
missing) and is open source; Droid's equivalent is unconfirmed and its CLI is proprietary. The
decisive weakness is **axis E**: the owner made readable quota non-negotiable, and Droid's only path
to it is an endpoint Factory does not document and could change tomorrow. That is a real risk to
weigh, softened — but not removed — by the fact that Droid can downshift to a free model pool
instead of stopping.

---

## Sources

All retrieved or executed **2026-09-19**.

### Run on this machine (VERIFIED by execution)

- `droid --version` → `0.223.0`; `droid --help`; `droid exec --help`; `droid resume --help`;
  `droid daemon --help`; `droid search --help`; `droid update --help`; `droid mcp --help`;
  `droid plugin --help`; `droid computer --help`; `droid doctor --help`
- `droid doctor --json`, `droid doctor --json --auth`, `droid doctor --json --daemon`
- `droid exec --auto bogus` → `Invalid --auto value. Allowed values: low, medium, high.`
- `droid exec --input-format bogus` → `Authentication failed. Please log in using /login or set a valid FACTORY_API_KEY environment variable.`
- `strings` over the 227 MB `@factory/cli-darwin-arm64` binary (496,835 lines) — source of the
  `droid.*` method inventory, the `FACTORY_HOME_OVERRIDE` resolver, the `/api/billing/limits`
  logic and response shape, the `--output-format` enum, the session create-with-id paths, the
  `.factory/` tree inventory, and the settings-origin list
- On-disk artefacts produced in the sandbox: `~/.factory/sessions/<cwd-slug>/<uuid>.jsonl`,
  `<uuid>.settings.json`, `host.json`

### Registries and repositories (VERIFIED)

- npm `droid` — 0.223.0, published 2026-09-19, 213 versions, `UNLICENSED`, `engines.node >=20.0.0`
- npm `@factory/cli` 0.223.0; npm `@factory/droid-sdk` 0.9.1 (2026-09-04, Apache-2.0)
- PyPI `droid-sdk` 0.4.0 (2026-08-28, Apache-2.0, Python >=3.10)
- GitHub API `Factory-AI/factory` — 24 stars, 26 open issues, no license, pushed 2026-09-17

### Official Factory documentation (VERIFIED; raw Markdown via `<page>.md`)

- `https://docs.factory.ai/llms.txt` — documentation index
- `https://docs.factory.ai/openapi.json` — Factory Public API, OpenAPI 3.0.1, `info.version` 0.1.0
- `/droid-cli/overview`, `/droid-cli/quickstart`, `/droid-cli/cli-reference`, `/droid-cli/settings`
- `/droid-exec/overview` — headless mode, JSON-RPC, autonomy, missions, batch patterns
- `/sdk/typescript`, `/sdk/python`
- `/api-reference/sessions`, `/api-reference/organization`
- `/autonomy-and-safety/auto-run`, `/autonomy-and-safety/sandbox`
- `/harness/hooks`, `/harness/mcp`, `/harness/subagents`, `/harness/skills`, `/harness/plugins`
- `/model-independence/byok`, `/model-independence/factory-router`
- `/pricing/individuals`, `/pricing/organizations`, `/models`
- `/missions/reference`
- `/enterprise/identity-and-access`, `/enterprise/hierarchical-settings-and-org-control`,
  `/enterprise/llm-safety-and-agent-controls`, `/enterprise/telemetry/data-reference`

### Notes on source quality

- `https://docs.factory.ai/cli/user-guides/headless-mode` returns **HTTP 404 served as a Vercel
  login page** — a 404 that looks like a 200 to a naive fetcher. Any doc scraper in this project
  must check status codes, not just body content.
- The docs' own `droid exec --help` excerpt is **stale** relative to 0.223.0 in two places
  (tool-control flag names, and it omits `--tag`/`--log-group-id`/`--list-tools` ordering).
  The hooks doc's `transcript_path` example path is also wrong. Prefer the binary.
- CLAIMED-only items in this profile: Factory Router's "99.9%+ request reliability", SOC-2
  compliance, and the "~5x / ~10x Pro usage" plan multipliers. None were independently verified.
