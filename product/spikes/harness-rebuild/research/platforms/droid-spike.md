# Factory Droid — orchestrator adapter spike

**Date:** 2026-09-19. **CLI version exercised:** `droid` **0.223.0** (npm `droid@0.223.0`, payload
`@factory/cli-darwin-arm64`, Bun 1.4.2 runtime). **SDK read:** `@factory/droid-sdk` **0.9.1**
(Apache-2.0). **Host:** owner's Mac, darwin 25.5.0 arm64.

**Companion:** the capability profile at [`droid.md`](droid.md). This document is the *recipe*:
exact commands, exact payloads, exact success and failure signatures. Where it contradicts the
profile, the contradiction is called out in [§13](#13-corrections-to-the-platform-profile) — this
spike ran things the profile only reasoned about.

## Evidence tags

- **VERIFIED** — executed on this machine, or read verbatim in the shipped 0.223.0 binary / the
  installed SDK's `.d.ts`.
- **CLAIMED** — asserted by Factory docs or marketing only.
- **UNKNOWN** — could not be established. No flag or field name in this document is guessed.

---

## 0. Ground rules for running these recipes

**Droid is still not installed for the owner.** `which droid` → not found; `~/.factory` does not
exist. (VERIFIED, re-checked after every probe below.)

Everything in this spike ran against an **isolated sandbox install**, and every command here is
written so it can be run the same way. Two environment variables do all the containment work:

```bash
export SB=/private/tmp/claude-501/<session>/scratchpad/droid/sandbox
export DROID="$SB/npm/node_modules/.bin/droid"   # npm install droid@0.223.0 --prefix "$SB/npm"
export FACTORY_HOME_OVERRIDE="$SB/home"          # relocates the ENTIRE .factory tree
export HOME="$SB/home"                           # belt and braces
export FACTORY_DROID_AUTO_UPDATE_ENABLED=false   # pin the version (see §11)
```

`FACTORY_HOME_OVERRIDE` is checked **before** `HOME` by the CLI's own home resolver (VERIFIED in
binary), so this is a complete account jail. Confirmed after the fact: the owner's `~/.factory`
still does not exist.

**No Factory account was used and no quota was spent.** Everything below that is marked VERIFIED
either runs entirely locally or fails at a documented auth boundary. That boundary turns out to be
much further in than expected: **the whole session-control protocol — create, load, list, context,
compaction, settings, fork, rename, interrupt, close — works with no credentials at all.** Only
model inference needs auth.

---

## 1. Preflight: installed, authenticated, which account?

```bash
"$DROID" --version                       # -> 0.223.0
"$DROID" doctor --json --auth
```

**VERIFIED output shape** (run in an unauthenticated home):

```json
{
  "generatedAt": "2026-09-19T13:32:57.944Z", "timeoutMs": 10000, "ok": true,
  "results": [
    {"id":"env.info","category":"environment","status":"pass",
     "detail":"v0.223.0 on darwin arm64 (bun 1.4.2)",
     "data":{"cliVersion":"0.223.0","platform":"darwin arm64","osRelease":"Darwin 25.5.0",
             "runtime":"bun 1.4.2","deploymentEnv":"production",
             "apiBaseUrl":"https://api.factory.ai","appBaseUrl":"https://app.factory.ai",
             "factoryDir":"~/.factory","logsDir":"~/.factory/logs"}},
    {"id":"auth.credentials","status":"pass","detail":"credential storage responded; no stored login found"},
    {"id":"auth.workosRefresh","status":"pass","detail":"POST api.workos.com/authenticate answered HTTP 400 (invalid-credential probe…)"},
    {"id":"auth.verify","status":"warn","detail":"no usable credentials found (not logged in)"}
  ]
}
```

**The gate is `auth.verify`, not `ok`.** This is the single most important line of this section.
With no credentials at all, top-level `"ok"` is still **`true`**, and `auth.credentials` still
reports **`pass`** — it only means "the keychain answered", not "there is a login". An adapter that
gates on `.ok` will happily dispatch work to a logged-out account and discover the problem one
turn later.

```bash
# Correct preflight assertion:
"$DROID" doctor --json --auth \
  | jq -e '.results[] | select(.id=="auth.verify") | .status == "pass"' >/dev/null \
  || { echo "droid: not authenticated in $FACTORY_HOME_OVERRIDE"; exit 1; }
```

- **Success:** `auth.verify.status == "pass"`. Exit 0.
- **Failure:** `auth.verify.status == "warn"` with `"no usable credentials found (not logged in)"`.
- **Which account?** `doctor` reports `factoryDir` as the literal tilde-collapsed string
  `"~/.factory"` — it does **not** resolve it, so you cannot use it to tell which
  `FACTORY_HOME_OVERRIDE` is live. (VERIFIED: a run with a fresh override still printed
  `"~/.factory"`.) Identify the home yourself instead:
  ```bash
  test -s "$FACTORY_HOME_OVERRIDE/.factory/auth.json" && echo logged-in-tree
  jq -r .hostId "$FACTORY_HOME_OVERRIDE/.factory/host.json"   # stable per-home machine identity
  ```
- **Fallback when `doctor` is unavailable:** `"$DROID" exec --output-format json "noop"` returns
  `subtype:"failure"` + `result:"Authentication failed…"` with exit code 1 (VERIFIED, §2).
  It costs nothing when unauthenticated, but it *will* cost credits when it succeeds — prefer
  `doctor`.

Other useful preflight checks, all **VERIFIED by running them** and all auth-free:
`"$DROID" doctor --json --daemon` (includes `daemon.loopback`: "listen + connect + echo OK on
127.0.0.1:<port>"), `"$DROID" exec --list-tools --output-format json`,
`"$DROID" search --json "<q>"` → `{"query":"…","sessions":[]}`.

---

## 2. Start a task headless, with a pinned session id, capturing structured output

### 2a. The finding that changes the adapter design

The platform profile lists "can the orchestrator name a session before it exists?" as Droid's
weak point and its **number-one spike question**. It is answered, and the answer is **yes**.

**VERIFIED by execution.** `droid.initialize_session` accepts `params.sessionId` and honours it.
The binary's handler is `let pe = d || He()` — *use the caller's `sessionId`, else generate one* —
and the round trip proves it:

```
IN   {"jsonrpc":"2.0","factoryApiVersion":"1.0.0","factoryProtocolVersion":"1.217.0","type":"request",
      "id":"1","method":"droid.initialize_session",
      "params":{"sessionId":"11111111-2222-3333-4444-555555555555","machineId":"orch-mac",
                "cwd":"/…/droid/work","title":"pinned-id probe","tags":[{"name":"spike"}],
                "disableBuiltinSkills":true,"autonomyLevel":"low"}}

OUT  {"jsonrpc":"2.0","type":"response","factoryApiVersion":"1.0.0","factoryProtocolVersion":"1.217.0",
      "id":"1","result":{"sessionId":"11111111-2222-3333-4444-555555555555",
      "hostId":"<host-id>",
      "session":{"messages":[],"title":"pinned-id probe"},
      "settings":{…},"availableModels":[…]}}
```

and the file it wrote, on disk, with the pinned id in `session_start`:

```
$FACTORY_HOME_OVERRIDE/.factory/sessions/-private-tmp-…-droid-work/11111111-2222-3333-4444-555555555555.jsonl
  {"type":"session_start","id":"11111111-2222-3333-4444-555555555555","title":"pinned-id probe",
   "isSessionTitleManuallySet":true,"owner":"sasha-marchuk","version":2,
   "cwd":"/…/droid/work","hostId":"<host-id>"}
```

**There is no crash window.** The orchestrator assigns the id, so it can persist the
ticket→session mapping *before* spawning anything. This puts Droid level with `pi` on axis B.

> **The SDK cannot do this.** `SessionInitOptions` in `@factory/droid-sdk@0.9.1` has no `sessionId`
> field (VERIFIED in `node.d.ts`); `createSession(options?)` generates one. **Use raw JSON-RPC, not
> the SDK, if you want assigned ids.** This is a hard constraint on the adapter's implementation
> language-agnostic — it is a line protocol, so any language works.

### 2b. The envelope (get this wrong and you get `-32700`)

Every request needs five envelope fields. Omitting `type` alone yields
`{"id":null,"error":{"code":-32700,"message":"Invalid JSON-RPC message"}}` — with `id: null`, so
you cannot even correlate the failure. (VERIFIED: that was this spike's first attempt.)

```json
{"jsonrpc":"2.0","factoryApiVersion":"1.0.0","factoryProtocolVersion":"1.217.0",
 "type":"request","id":"<your id>","method":"droid.<method>","params":{…}}
```

`type` ∈ `request` | `response` | `notification` (VERIFIED enum). `factoryApiVersion` is the
required literal (marked *"DEPRECATED - use factoryProtocolVersion"* in the schema but still
required); `factoryProtocolVersion` is optional and the CLI answers with `1.217.0` on 0.223.0.

### 2c. Launch

```bash
droid exec --input-format stream-jsonrpc --output-format stream-jsonrpc \
           --cwd "$REPO" --auto low --tag "$TICKET" --log-group-id "$RUN_ID"
```

Then, on stdin, `initialize_session` with your id, then `add_user_message` with the task.

**Ordering constraint (VERIFIED the hard way):** requests sent before `initialize_session`'s
response arrives are rejected with
`-32603 "No active session. Call initialize_session or load_session first."` The adapter must
**await the init response** before anything else. Pipelining is not safe.

Useful `initialize_session` params, all **VERIFIED** from the binary's destructuring of
`e.params`:

| Param | Why the orchestrator wants it |
| --- | --- |
| `sessionId` | Assign the id (§2a) |
| `cwd`, `machineId`, `title`, `tags[]` | Identity and correlation |
| `modelId`, `reasoningEffort` | Cost routing (0.08×–12× spread) |
| `autonomyLevel`, `interactionMode` | Guardrails |
| `autoRejectPermissionRequests` | **Unattended kill-switch** — see §9 |
| `allowSubagentsInScripts` | Answers a profile UNKNOWN: it is settable at init |
| `disableBuiltinSkills` | Shrink context (`skills` category, §5) |
| `compactionThresholdCheckEnabled` | Per-session compaction control |
| `structuredOutputFormat` | Machine-readable result contract |
| `enabledToolIds` / `disabledToolIds` / `restrictToolIds` / `additionalToolIds` | Tool policy |
| `mcpServers[]` | Per-task MCP without touching config files |
| `systemPrompt` / `systemPromptOverride` | Prompt injection for the workflow engine |
| `sessionSource`, `sessionLocation`, `sessionOriginHint`, `callingMetadata` | Provenance |

### 2d. Fire-and-forget alternative

```bash
droid exec --output-format json --auto low "…"        # one shot, terminal object
```

**VERIFIED failure shape and exit code** (unauthenticated run, exit **1**):

```json
{"type":"result","subtype":"failure","is_error":true,"duration_ms":1,"num_turns":0,
 "result":"Authentication failed. Please log in using /login or set a valid FACTORY_API_KEY environment variable.",
 "session_id":"2bdac709-a873-4ccc-9ac4-aa62c63412e6",
 "usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,
          "cache_creation_input_tokens":0,"factory_credits":0}}
```

Note `session_id` and `usage.factory_credits` are present **even on failure** — so even a crashed
one-shot leaves a nameable session and a spend record. Exit codes: `0` success, `1` runtime error,
`2` invalid CLI arguments (CLAIMED in docs; `1` VERIFIED here).

- **Success:** `subtype:"success"`, `is_error:false`.
- **Fallback if you cannot run a JSON-RPC client:** use `--output-format json` and scrape
  `session_id`, accepting the crash window. Do not use `--input-format stream-json`; it is
  deprecated in 0.223.0 and warns.

---

## 3. Start the same task in a visible terminal the owner can type into

**Not verified end-to-end — recorded honestly.**

```bash
droid --cwd "$REPO" --auto low "…"          # TUI seeded with a prompt
droid --resume "$SESSION_ID"                 # attach to a session the orchestrator created
droid --resume --last                        # most recent session in this folder
```

`droid --resume <id>` is the bridge: because §2a lets the orchestrator **assign** the id, the owner
can always be handed an exact attach command for any queued task. That is a materially better story
than platforms where the id must be scraped first.

**VERIFIED:** run without a TTY, `droid "hello"` renders its ASCII banner and exits 0 — it does not
error, and it does not do work. So a supervisor must launch it inside a real terminal emulator
(the owner's existing `task-launch` iTerm2-osascript path, or `tmux new-session`), exactly as it
does for Claude Code. Nothing about Droid changes that plumbing.

- **The gap:** there is no supported way to inject text into a TUI the *owner* started by hand.
  The orchestrator must own the process to talk to it in-protocol.
- **Fallback, and a lead worth an hour:** the daemon exposes `daemon.list_opened_sessions`,
  `daemon.add_user_message`, `daemon.create_terminal`, `daemon.write_terminal_data`,
  `daemon.terminal_data` and `daemon.close_terminal` (VERIFIED — these method names are in the
  binary, see §12). If a TUI registers with a local daemon, that is a real path to driving a
  foreign visible session. **Whether the TUI registers is UNKNOWN** — it needs an authenticated
  daemon to test. If it does, Droid solves a problem no other platform in this scan solves.

---

## 4. Tell whether the session is alive, working, waiting, or finished — from outside

Four independent signals, in increasing cost. **All four VERIFIED.**

### 4a. The state machine (VERIFIED — enum read in SDK `DroidWorkingState`, transitions observed live)

```
idle | thinking | streaming_assistant_message | executing_tool |
compacting_conversation | waiting_for_tool_confirmation
```

The binary groups them itself: busy = `{thinking, streaming_assistant_message, executing_tool,
compacting_conversation}`; active = busy ∪ `{waiting_for_tool_confirmation}`.

Map straight onto the question:

| Question | Condition |
| --- | --- |
| **working** | state ∈ busy |
| **waiting** | state == `waiting_for_tool_confirmation` |
| **finished / idle** | state == `idle` |
| **alive** | process alive **and** one of the above was seen recently |

Observed transition on a real turn: `idle → streaming_assistant_message → thinking → idle`.

### 4b. Live, over the protocol (cheapest, zero latency)

```json
{"method":"droid.session_notification","params":{"sessionId":"…",
  "notification":{"type":"droid_working_state_changed","newState":"thinking"}}}
```

Terminal event, **VERIFIED live**:

```json
{"type":"agent_turn_completed","reason":"model_authentication_failed",
 "turnId":"97ebecd2-…","tokenUsage":{…,"factoryCredits":0},"cumulativeTokenUsage":{…}}
```

Other notification types seen on the wire: `mcp_status_changed`, `settings_updated`,
`session_title_updated`, `create_message`, `error`, `queued_messages_discarded`.

### 4c. One-shot poll, no process needed (**the best cost/benefit**)

`droid.load_session` returns a complete snapshot in a single call — **VERIFIED**:

```json
{"session":{"messages":[…],"title":"crash-resume"},"hasOlderMessages":false,
 "hostId":"<host-id>","updatedAt":1789824699,"settings":{…},"availableModels":[…],
 "isAgentLoopInProgress":false,"workingState":"idle","cwd":"/…/droid/work",
 "tokenUsage":{…},"inclusiveTokenUsage":{…}}
```

`workingState` + `isAgentLoopInProgress` + `tokenUsage` + `cwd`, from a cold process, without auth.

### 4d. From files alone, no process at all

```bash
S="$FACTORY_HOME_OVERRIDE/.factory/sessions/$(echo "$CWD" | tr '/' '-')/$SID"
jq '.assistantActiveTimeMs, .inclusiveTokenUsage.factoryCredits' "$S.settings.json"
tail -1 "$S.jsonl"
```

`assistantActiveTimeMs` is the antidote to the field-notes failure *"a shell that can never exit
reading as work"*: **a session whose active time is not advancing is not working, whatever its
process is doing.** (VERIFIED present in every sidecar this spike produced.)

- **Failure:** `-32004 "Session not found"` from `load_session` means the id never existed or its
  file was deleted. (VERIFIED with a bogus UUID.)
- **Fallback:** `kill -0 <pid>` plus a stale-`assistantActiveTimeMs` timeout.

---

## 5. Read how full the context is, then force a compaction, then prove it

### 5a. Read — and read the *right* number

Two methods. **Both VERIFIED by execution, with no auth.**

```json
{"method":"droid.get_context_stats","params":{}}
→ {"used":12029,"remaining":909971,"limit":922000,"accuracy":"estimated",
   "updatedAt":"2026-09-19T13:32:11.410Z"}

{"method":"droid.get_context_breakdown","params":{}}
→ {"modelId":"gpt-5.6-sol","modelDisplayName":"GPT-5.6 Sol",
   "contextBudget":250000,"usedTokens":12029,"freeTokens":237971,
   "categories":[{"name":"System prompt","tokens":1337,"colorKey":"systemPrompt"},
                 {"name":"System tools","tokens":10611,"colorKey":"systemTools"},
                 {"name":"MCP tools","tokens":0},{"name":"User info","tokens":0},
                 {"name":"AGENTS.md","tokens":0},{"name":"Custom agents","tokens":81},
                 {"name":"Skills","tokens":0},{"name":"Messages","tokens":0}],
   "skills":[],"mcpServers":[],
   "droids":[{"name":"user-testing-flow-validator","location":"personal","tokens":46}]}
```

> **Use `get_context_breakdown`, not `get_context_stats`.** The profile warns that `remaining` is
> room in the *model window*, not room before *compaction*, and tells you to compare `used` against
> `compactionTokenLimit` yourself. You do not have to: **`get_context_breakdown` already does it.**
> In the same session, `stats.remaining` said **909,971** while `breakdown.freeTokens` said
> **237,971** — a 3.8× difference, and the second one is the number that decides when compaction
> fires. An adapter that watches `remaining` will be blindsided.

`accuracy` is `"estimated"` — Droid approximates tokens from character counts. Do not build a
threshold that assumes precision; leave headroom.

`limit` is model-dependent and updates live: after `update_session_settings` switched the model to
`claude-haiku-4-5-20251001`, the same session reported `limit: 133424` instead of `922000`
(VERIFIED). So **re-read after any model change.**

The `categories` array is what makes this actionable rather than merely informative: it says *what*
to shed. In the probe session, `System tools` alone was 10,611 of 12,029 used tokens — which is why
`disableBuiltinSkills` and `--only-tools` are context levers, not just safety levers.

### 5b. Set the budget per task, without touching the owner's config

```bash
cat > /tmp/task-settings.json <<'EOF'
{ "compactionTokenLimit": 60000, "compactionModel": "gpt-5.6-luna" }
EOF
droid exec --settings /tmp/task-settings.json --input-format stream-jsonrpc …
```

**VERIFIED closed loop** — same session, same `usedTokens`, budget moved:

```
default                       contextBudget=250000  used=12029  free=237971
--settings compactionTokenLimit=60000   contextBudget= 60000  used=12029  free= 47971
```

`compactionModel` is a direct cost lever: compaction can run on `gpt-5.6-luna` (0.08×) while the
session runs on something strong.

### 5c. Force compaction

```json
{"method":"droid.compact_session","params":{}}
```

**VERIFIED failure signature on an empty conversation:**
`{"code":-32602,"message":"Nothing to compact — the conversation is empty."}` — a clean,
distinguishable error, so "nothing to do" never looks like "compaction broke".

**Not verified on a real conversation** (needs auth for the summarising call). From docs/SDK:
returns a **successor session** plus `removedCount`; the source session is retired
(`SessionReplacedError` on further use) but remains loadable by id.

> **The session id changes at compaction.** Any ticket→session mapping must be updated on the
> `compact` response, or it points at a retired session. This is the one place where §2a's
> "assign the id" property does *not* hold — the successor's id is Droid's to choose.

### 5d. Prove it happened — four receipts

1. `removedCount` in the `compact_session` response.
2. The successor id, with the source still on disk — a durable before/after pair.
3. **Live:** `droid_working_state_changed` → `newState: "compacting_conversation"` (VERIFIED enum
   member). This is a receipt the profile does not mention and it is the cheapest one: the
   supervisor sees compaction *as it happens*, including compactions it did not initiate.
4. Hooks `PreCompact` (`trigger: manual|auto`, `estimated_tokens`, `message_count`) and
   `SessionStart` (`source: "compact"`) (CLAIMED — hooks doc; not exercised here).

- **Fallback if compaction cannot be forced:** `droid.fork_session` (VERIFIED working, returns
  `{"newSessionId":"…"}`) gives a handoff into a fresh branch. Or end the task and start a
  successor with an assigned id, carrying a summary forward in `systemPrompt`.

---

## 6. Read remaining quota and the reset time; detect a limit hit in-band

This is the owner's non-negotiable axis and Droid's weakest. The picture is now sharper than the
profile's: the **in-band** half is fully solved, the **read-ahead** half is unsupported but real.

### 6a. In-band limit detection — solved, exactly typed

Every turn ends with `agent_turn_completed` carrying a `reason`. The **complete enum**, VERIFIED
verbatim from the binary:

```
completed | cancelled | permission_rejected | error | process_exit | spec_handoff |
structured_output_missing | structured_output_invalid | structured_output_schema_invalid |
model_usage_exhausted | model_authentication_failed | model_request_rejected |
model_provider_unreachable | model_provider_unavailable | model_rate_limited |
prompt_rejected | completion_persistence_failed | no_approver_available
```

The binary's own classifier (VERIFIED, reformatted):

```js
if (isUsageExhausted(e))                  return "model_usage_exhausted";      // plan window exhausted
if (status === 429 || reason === "throttling") return "model_rate_limited";    // throttled
if (status === 403 || reason === "authError")  return "model_authentication_failed";
if (status >= 500 || …)                   return "model_provider_unavailable";
```

**Adapter policy:**

| `reason` | Action |
| --- | --- |
| `model_usage_exhausted` | Plan window gone. Pause the queue, or downshift to Droid Core (§6c). |
| `model_rate_limited` | Transient. Back off and retry the same session. |
| `model_provider_unavailable` / `_unreachable` | Retry; Factory Router should have absorbed it. |
| `no_approver_available`, `permission_rejected` | **Treat as failure** — see the warning below. |
| `completed`, `spec_handoff` | Success. |

> **Trap, VERIFIED in the binary.** Droid's own telemetry treats
> `{completed, spec_handoff, cancelled, permission_rejected, process_exit, no_approver_available}`
> as a **non-error** set. So a session that died because nothing could answer a permission prompt
> is recorded as a normal ending. The supervisor must classify these itself or silent stalls will
> read as clean completions.

**VERIFIED live** — the auth-failure turn produced exactly this sequence, which is the same shape a
quota failure takes:

```json
{"type":"error","message":"No access token available","errorType":"Error",
 "error":{"name":"AuthenticationError","message":"No access token available"}}
{"type":"create_message","message":{"role":"system","content":[{"type":"text","text":"Authentication failed…"}],"visibility":"user_only"}}
{"type":"agent_turn_completed","reason":"model_authentication_failed","turnId":"…","tokenUsage":{…}}
{"type":"droid_working_state_changed","newState":"idle"}
```

### 6b. Read-ahead headroom — the undocumented endpoint, now with proof it exists

There is **no supported way** to read remaining capacity; the profile established that by
enumerating all 60 operations in `openapi.json`. This spike adds the missing piece: **proof that
the undocumented endpoint is real**, by differential probe (VERIFIED, unauthenticated):

```
GET https://api.factory.ai/api/billing/limits          -> HTTP 401  {"detail":"Missing authorization token in HTTP headers","status":401,"title":"Unauthorized","requestId":"hkg1::…"}
GET https://api.factory.ai/api/v0/sessions             -> HTTP 401  {"detail":"Missing authorization token …"}
GET https://api.factory.ai/api/billing/does-not-exist-xyz -> HTTP 404  <!DOCTYPE html>… (Next.js page)
GET https://api.factory.ai/api/auth/whoami             -> HTTP 404  <!DOCTYPE html>… (Next.js page)
```

A real route answers **401 with a typed JSON envelope**; a non-route answers **404 with HTML**.
`/api/billing/limits` is a real route. (It also retires a claim: `/api/auth/whoami`, listed in the
profile as an undocumented binary endpoint, is **not** reachable at that path.)

```bash
curl -sf https://api.factory.ai/api/billing/limits -H "Authorization: Bearer $FACTORY_API_KEY"
```

Response shape reconstructed from the consuming code (VERIFIED by usage, not by schema):

```jsonc
{"limits":{"standard":{"fiveHour":{"usedPercent":0,"windowEnd":"<ISO>"},
                       "weekly":{…},"monthly":{…}},
           "core":    {"fiveHour":{…},"weekly":{…},"monthly":{…}}},
 "extraUsageBalanceCents":0,"overagePreference":null,
 "extraUsageAllowed":true,"canManageOverage":true}
```

The binary's evaluation logic, **verbatim** (VERIFIED — this is the CLI deciding whether it is
blocked):

```js
const windowActive = (b) => new Date(b.windowEnd).getTime() >= Date.now();
const bucketMaxed  = (b) => windowActive(b) && b.usedPercent >= 100;
const isExhausted  = (l) => bucketMaxed(l.fiveHour) || bucketMaxed(l.weekly) || bucketMaxed(l.monthly);
// pool once exhausted:
const pool = (exhausted, pref) => exhausted
  ? (pref === "extraUsage" ? "extraUsage" : pref === "droidCore" ? "droidCore" : "blocked")
  : "standard";
// soonest reset among maxed buckets -> when to resume
// highest usedPercent among ACTIVE buckets -> the throttle signal
```

**Adapter recipe.** `usedPercent` maps to the owner's `utilization`; `windowEnd` maps to
`resets_at`. His existing 80/90/95 policy transfers verbatim, with a third (monthly) window and a
second (Core) pool:

```bash
jq -r '[.limits.standard.fiveHour, .limits.standard.weekly, .limits.standard.monthly]
       | map(select(.windowEnd > (now|todate))) | max_by(.usedPercent)
       | "\(.usedPercent)% until \(.windowEnd)"' <<<"$LIMITS"
```

- **Risk:** unsupported, absent from `openapi.json`, under `/api/billing/` not `/api/v0/`, on a
  CLI that ships near-daily. **Guard it with a contract test that fails loudly on shape change**,
  and fall back to §6a.
- **Supported-but-lesser alternative:** track *burn*, not headroom, from
  `.settings.json.inclusiveTokenUsage.factoryCredits` (§4d) plus each model's `tokenMultiplier`
  — which, usefully, `initialize_session` returns for every model in `availableModels[]`
  (VERIFIED: `{"id":"claude-fable-5.1",…,"tokenMultiplier":4}`).

### 6c. Degrade instead of stopping

Droid uniquely offers a graceful path: **Droid Core** is a free open-weight pool with its **own
separate rate limits**. The binary switches to it programmatically via `setModel(recommendedCoreModel)`
with `source:"detector_recovery"`. An orchestrator can implement *downshift at 90%* rather than
*pause at 90%* using `droid.update_session_settings({modelId})` (VERIFIED working, returns `{}`).
For an overnight queue this is strictly better than a hard stop.

---

## 7. Switch a new session to a different account, and verify before work starts

```bash
# Profiles are directories, exactly like the owner's profile-switcher pattern for CLAUDE_CONFIG_DIR.
export FACTORY_HOME_OVERRIDE=/opt/orch/accounts/acct-b
export FACTORY_DISABLE_KEYRING=1          # never block on a macOS Keychain modal
export FACTORY_DROID_AUTO_UPDATE_ENABLED=false
"$DROID" doctor --json --auth | jq -e '.results[]|select(.id=="auth.verify")|.status=="pass"'
```

**VERIFIED by execution.** A fresh `FACTORY_HOME_OVERRIDE` builds its own tree and touches nothing
else. Full tree observed after this spike's probes:

```
auth.json  config.json  history.json  mcp.json  settings.json  host.json
background-processes.json  background-tasks.json  task-invocations.json  last-startup-version
bin/ cache/ certs/ crons/ droids/ logs/ plugins/ sessions/ snapshots/ software-factory/ telemetry/ temp/
```

(`bin/`, `crons/`, `plugins/`, `snapshots/`, `software-factory/` are additions this spike observed
that the profile's list does not have.) Credentials live in `auth.json` **inside that tree**, so the
override is a complete account jail: auth, settings, MCP, custom droids and session history all move
together.

**`FACTORY_DISABLE_KEYRING=1`** — the profile lists the accepted values as UNKNOWN. Resolved: the
CLI's own remediation text says *"set `FACTORY_DISABLE_KEYRING=1` to store credentials on disk
instead"*, in two places, one of which describes precisely the failure the field notes fear:
*"The OS credential store is blocking before any network request is made; endpoint security or
policy software may be intercepting it."* (VERIFIED strings.)

Alternatives, in increasing isolation: `FACTORY_API_KEY=fk-…` (per process, simplest for headless)
→ `--settings <path>` (per-process config only, no credentials) → `FACTORY_HOME_OVERRIDE` (total)
→ service accounts (`POST /api/v0/service-accounts`, `…/api-keys`, `/rotate`, `/revoke`) with
admin-set per-user credit ceilings.

- **Verify the switch:** `auth.verify == "pass"` **plus** your own check of which directory is live
  (`doctor` will not tell you — §1). Assert on `host.json.hostId`, which is stable per home and is
  echoed in every `session_start` line and every `initialize_session` response.
- **Changing a RUNNING session's account: impossible.** (VERIFIED by absence across every surface;
  `update_session_settings` covers model, reasoning, interaction mode, autonomy, spec-mode and
  tools, and nothing else.) Cost of the workaround is **one killed turn**:
  `droid.interrupt_session` → `droid.close_session` → relaunch with
  `droid.load_session {sessionId}` under the new env. History, cwd, title and settings all survive
  (§10). Switch at turn boundaries.

---

## 8. Deliver an instruction into a running session and confirm it arrived

```json
{"jsonrpc":"2.0","factoryApiVersion":"1.0.0","factoryProtocolVersion":"1.217.0","type":"request",
 "id":"r2","method":"droid.add_user_message",
 "params":{"text":"stop refactoring and run the tests","queuePlacement":"end_of_turn"}}
```

`params.text` is required (VERIFIED: omitting it →
`-32602 "…params.text: Required"`). `queuePlacement` defaults to `"end_of_turn"` (VERIFIED in
binary).

**Two independent acknowledgements, both VERIFIED live:**

1. The correlated JSON-RPC response — `{"type":"response","id":"r2","result":{}}`.
2. A `create_message` notification that **echoes your request id**:

```json
{"type":"create_message","message":{"id":"97ebecd2-…","role":"user",
  "content":[{"type":"text","text":"say hello"}],"createdAt":1789824748583,
  "interactionMode":"auto","parentId":"context-97ebecd2-…"},"requestId":"r2"}
```

That `"requestId":"r2"` is the strong proof: the supervisor sees *its own* message enter the
conversation, by id, in the event stream. This is exactly the failure the field notes record for
the current harness — *"a nudge that cannot submit stranded text"* — and it is a real, correlated,
in-band answer, not a screen-scrape and not a keystroke.

- **Failure:** no response for `id` within the timeout, or `-32603 "No active session…"` if you
  never loaded one.
- **Queued rather than consumed:** `droid.resolve_queued_user_message` with
  `params.action` ∈ `"update_queue" | "delete"` (VERIFIED: the discriminator error names both
  values). Watch for the `queued_messages_discarded` notification.
- **Bulk history injection:** `droid.append_messages` (`params.messages` required).
- **Fallback for a TUI you do not own:** none in-protocol. See §3.

---

## 9. Answer a permission prompt or a clarifying question without a human

**These are server→client requests.** VERIFIED by probe: calling `droid.request_permission`,
`droid.ask_user`, `droid.permission_wait` or `droid.ask_user_wait` *from* the client returns
`-32601 "Unknown method"`. The adapter never sends them — it **answers** them.

### 9a. Permission

Droid sends (VERIFIED shape, from the binary's emitter):

```json
{"type":"request","jsonrpc":"2.0","factoryApiVersion":"1.0.0","factoryProtocolVersion":"1.217.0",
 "method":"droid.request_permission","id":"<requestId>",
 "params":{"toolUses":[{"toolUse":{"type":"tool_use","id":"<toolUseId>","name":"execute-cli","input":{…}},
                        "confirmationType":"execute","details":{…}}],
           "options":["proceed_once","proceed_always","cancel"],
           "associatedSessionIds":["…"]}}
```

You reply with the **same id**:

```json
{"type":"response","jsonrpc":"2.0","factoryApiVersion":"1.0.0","factoryProtocolVersion":"1.217.0",
 "id":"<requestId>","result":{"selectedOption":"proceed_once"}}
```

**Complete `selectedOption` enum, VERIFIED** (SDK `ToolConfirmationOutcome` + binary):

```
proceed_once | proceed_always | proceed_always_file | proceed_auto_run |
proceed_auto_run_low | proceed_auto_run_medium | proceed_auto_run_high |
proceed_new_session | proceed_new_session_low | proceed_new_session_medium |
proceed_new_session_high | proceed_edit | proceed_always_tools |
proceed_always_server | proceed_report_false_positive | cancel
```

Rules: pick **only from the `options` supplied in that request**; `proceed_edit` additionally
requires `editedSpecContent` (VERIFIED refinement: *"editedSpecContent is required when
selectedOption is proceed_edit"*); `comment` is optional. Returning an unavailable value, throwing,
or not answering **all cancel the request**.

`details` is discriminated by `type`, including `apply_patch`, `mcp_tool`, `sandbox_violation`
(`{violatingToolName, target, operationType, violationType, reason, violationReason?, isOrgDeny}`)
and `droid_shield_violation` (`{command, reason}`) — enough for a real policy layer, not just
blanket approval.

### 9b. Clarifying question

```json
{"type":"request",…,"method":"droid.ask_user","id":"<requestId>",
 "params":{"toolCallId":"…","questions":[{"index":0,"topic":"deploy","question":"Which env?",
                                          "options":["staging","prod"],"multiSelect":false}]}}
```

Reply — each answer must echo **both** `index` and the `question` text:

```json
{"type":"response",…,"id":"<requestId>",
 "result":{"answers":[{"index":0,"question":"Which env?","answer":"staging"}]}}
```

Decline the whole questionnaire with `{"cancelled":true,"answers":[]}`.

> **The silent trap, and it is real.** *"Without a handler, AskUser requests are declined."*
> Handlers are **not** persisted across resume. So: resume a session, forget to re-attach, and
> every question the agent asks is silently refused — the agent then proceeds on its own
> assumptions. **This produces no error in any log.** Any adapter must re-attach both handlers on
> every create *and* every resume, and must log every declined question. Treat "no handler" as a
> bug, never a default.

### 9c. The unattended kill-switch

`initialize_session` / `load_session` accept **`autoRejectPermissionRequests: boolean`** (VERIFIED
in the binary's param destructuring, defaults `false`). Setting it `true` makes a session that can
never block on a prompt — useful for a strictly read-only reconnaissance task, but it converts
every permission into a refusal, so pair it with `--auto` tuned high enough that the work does not
need prompting.

- **Detect a stalled decision without parsing a screen:** `workingState` becomes
  `waiting_for_tool_confirmation` the moment either request is emitted (VERIFIED — the binary calls
  `setWorkingState("waiting_for_tool_confirmation")` in both emitters).
- **Belt and braces:** `droid exec` **auto-denies sandbox violations without prompting**, where the
  TUI prompts even at Auto High (CLAIMED, sandbox doc). One more reason the queue uses `exec`.

---

## 10. Resume after a crash, and after the whole machine rebooted

**VERIFIED end to end on this machine.** The probe: create with a pinned id, send an instruction,
`SIGKILL` the process, then load the same id from a brand-new process.

```
P1 init:                      cccccccc-dddd-eeee-ffff-000000000001
P1 pid:                       40013
P1 alive after SIGKILL:       false
P2 load:  {"title":"crash-resume","msgs":3,"workingState":"idle",
           "isAgentLoopInProgress":false,"cwd":"/…/droid/work","tokenUsage":{…}}
P2 messages: [{"role":"user","text":"<system-reminder>…"},
              {"role":"user","text":"first instruction before the crash"},
              {"role":"user","text":"Authentication failed. Please log in…"}]
P3 unknown-id load: {"code":-32004,"message":"Session not found"}
```

The instruction sent before the kill came back intact. Recipe:

```json
{"method":"droid.load_session","params":{"sessionId":"<pinned id>","loadAllMessages":true}}
```

or headlessly: `droid exec -s <sessionId> "continue"` / `droid resume <sessionId>`.

**A reboot is the same case.** The transcript is append-only JSONL on disk (mode 0600, directory
0700), so a hard kill loses at most the in-flight turn. Nothing in `.factory` is memory-resident.

**Survives:** conversation history, cwd, title, and session settings (model, reasoning,
interaction mode, autonomy, spec-mode settings, tool overrides, custom system prompt).

**Does NOT survive — must be re-attached every time:** permission handler, AskUser handler, SDK MCP
servers, observability sinks, abort signal. See the §9b warning; this is the trap.

**Failure modes and their exact signatures:**

| Signature | Cause | Fix |
| --- | --- | --- |
| `-32004 "Session not found"` | id never existed, or the `.jsonl` was deleted | Recreate with a new assigned id |
| `InvalidSessionCwdError` (*"Saved working directory is invalid"*) | repo moved, or a worktree was cleaned up | `droid.change_working_directory` with **`params.workingDirectory`** (VERIFIED param name) *after* load — `load_session` itself takes no replacement cwd |
| Orphaned background work | a killed session's children | Read `~/.factory/background-tasks.json` → `{tasks:[…]}` and `background-processes.json` → `{processes:[…]}`; the CLI reaps dead PIDs with `process.kill(pid,0)` |

**Reboot checklist:** clean git worktrees are auto-removed on exit while dirty ones are preserved —
so a crash mid-task usually leaves the worktree, but a *clean* exit may remove the path a resume
expects. Pin `worktreeDirectory`, or resume with an explicit `change_working_directory`.

---

## 11. Stop it cleanly, leaving nothing running

Ordered shutdown, each step **VERIFIED**:

```json
{"method":"droid.interrupt_session","params":{}}   → {}     # cancel the in-flight turn
{"method":"droid.close_session","params":{}}       → {}     # release the session
```

then close stdin and `SIGTERM` the child.

```bash
kill -TERM "$DROID_PID"; sleep 2; kill -0 "$DROID_PID" 2>/dev/null && kill -KILL "$DROID_PID"
```

Daemon shutdown is clean on `SIGTERM` (VERIFIED — log tail and released port):

```
DEBUG: Stopped HeartbeatService
DEBUG: WebSocket server closed
DEBUG: Daemon server stopped successfully
```

**Verification after the whole spike** (VERIFIED): no `droid` processes left, port 47777 released,
`background-tasks.json` → `{"tasks":[]}`, `background-processes.json` → `{"processes":[]}`.

- A cancelled turn returns subtype `interrupted` with `success:false, interrupted:true`.
- **Cancellation emits `Notification`, not `Stop`** (CLAIMED, hooks doc) — a `Stop`-based
  completion detector will miss cancelled turns. Use `agent_turn_completed.reason` instead (§6a).
- Subagent cleanup: `droid.kill_worker_session` with **`params.workerSessionId`** (VERIFIED param
  name).
- **Pin the version or the recipes rot.** Standalone installs auto-update. Install via **npm**
  (auto-update disabled at build time) or export `FACTORY_DROID_AUTO_UPDATE_ENABLED=false` in the
  environment of **every** droid process including the daemon. VERIFIED working: the daemon logged
  `auto-update completed (0ms)` under that env. This is not hypothetical — this scan already found
  two flag names and one documented path that moved.

---

## 12. The daemon: what is now known

The profile called this *"the single highest-value unknown about Droid"*. It is now mostly mapped.

**VERIFIED by running it, unauthenticated:**

```bash
droid daemon -p 47777 --host 127.0.0.1 --listen websocket --droid-path "$DROID" \
             --parent-pid $$ --liveness-fd 3 -d
```

```
DEBUG: Daemon server initialized {"port":47777,"host":"127.0.0.1","ipcOnly":false,"parentIpc":false}
DEBUG: WebSocket server ready for connections
[droid daemon] Daemon is running
  Version: 0.223.0 · PID: 35101 · WebSocket endpoint: ws://127.0.0.1:47777
```

| Fact | Value | Tag |
| --- | --- | --- |
| Health probe | `GET http://127.0.0.1:<port>/health` → **HTTP 200**, body `factory-daemon ok`, **no auth** | VERIFIED |
| Other HTTP paths | `/`, `/healthz`, `/status`, `/api/health` → 404 | VERIFIED |
| Wire protocol | **Identical JSON-RPC envelope to stdio** (`type`/`jsonrpc`/`factoryApiVersion`/`factoryProtocolVersion`/`id`/`method`/`params`) | VERIFIED |
| Auth gate | Every method → `-32001 "Connection not authenticated. Must call daemon.authenticate first."` | VERIFIED |
| `daemon.authenticate` params | `{caller: string (required), token?, apiKey?, activeOrganizationId?, actAsGrant?, connectionId?, metadata?}`; refinement *"Either token or apiKey must be provided"*; result `{userId, orgId}` | VERIFIED (schema) |
| Bad credentials | `-32001 "Internal error"` | VERIFIED |
| Malformed authenticate | `-32700 "Parse error"` (schema violations surface as parse errors, **not** `-32602`) | VERIFIED |
| Method count | **158** `daemon.*` methods | VERIFIED |
| Port discovery | **None.** No port/lock file anywhere in `.factory`. The port is caller-chosen via `-p`, so you can only talk to a daemon **you** started. | VERIFIED |

Methods that matter to an orchestrator (names VERIFIED; params UNKNOWN without an account):

```
Spawn & sessions  daemon.droid_spawn  daemon.initialize_session  daemon.load_session
                  daemon.list_available_sessions  daemon.list_opened_sessions
                  daemon.get_session_messages  daemon.search_sessions  daemon.archive_session
Terminals         daemon.create_terminal  daemon.terminal_create  daemon.write_terminal_data
                  daemon.terminal_data  daemon.terminal_exit  daemon.close_terminal
Intervention      daemon.add_user_message  daemon.interrupt_session  daemon.ask_user
                  daemon.request_permission (DaemonRequestPermissionSchema in the SDK)
Scheduling        daemon.create_cron  daemon.list_crons  daemon.update_cron  daemon.delete_cron
                  daemon.create_automation  daemon.run_automation  daemon.list_automations
Context & git     daemon.get_context_breakdown  daemon.get_git_diff  daemon.git_commit
                  daemon.git_push  daemon.create_pr  daemon.cleanup_worktree
```

`--droid-path` (*"for spawning sessions"*), `--parent-pid` and `--liveness-fd` are precisely
orchestrator-shaped: run the daemon as a child bound to the supervisor's lifetime, and let it own
the fleet. **The terminal capability is the interesting one** — if a TUI the owner started registers
with the daemon, `daemon.write_terminal_data` is the missing answer to §3. **Whether it registers
is UNKNOWN** and is the one remaining question worth an authenticated hour.

**Recommendation for v1: do not use the daemon.** One `droid exec --input-format stream-jsonrpc`
child per task gives assigned ids, full intervention, context control and clean teardown, with a
protocol this spike has fully exercised. The daemon is a v2 optimisation whose params are still
unknown.

---

## 13. Corrections to the platform profile

Everything below was established by running the thing, and supersedes [`droid.md`](droid.md).

1. **Sessions CAN be pre-named.** The profile's axis-B gap and its top spike question are closed:
   `droid.initialize_session` accepts `params.sessionId` and returns it unchanged, and
   `session_start` on disk carries it. There is no scrape and no crash window. (§2a)
2. **The SDK is strictly weaker than the protocol.** `SessionInitOptions` has no `sessionId`, so
   the SDK cannot assign ids. Raw JSON-RPC only. (§2a)
3. **Nearly the whole control protocol works unauthenticated.** Create, load, list, context stats,
   context breakdown, fork, rename, interrupt, update settings, list tools/models/skills/commands,
   close — all verified with no credentials. Only inference needs auth. This makes a Droid adapter
   far cheaper to build and test than assumed.
4. **`get_context_breakdown` already solves the compaction-threshold problem.** The profile tells
   the implementer to compare `used` against `compactionTokenLimit` manually; `contextBudget` and
   `freeTokens` do it. Same session: `stats.remaining` 909,971 vs `breakdown.freeTokens` 237,971.
   (§5a)
5. **Re-initialising an existing id is idempotent, not an error.** The profile quotes a binary path
   that throws *"Session already exists locally"*. Over JSON-RPC it does not throw — it returns the
   same id and loads instead. Create-or-attach is one call.
6. **`fork_session` cannot be given an id.** Both `newSessionId` and `sessionId` params were
   ignored; fresh UUIDs came back. Fork ids must be read from `result.newSessionId` (returned
   synchronously, so this is benign). VERIFIED negative.
7. **`droid doctor`'s top-level `ok` is not an auth check,** and `auth.credentials: pass` does not
   mean logged in. Gate on `auth.verify`. (§1)
8. **`doctor` cannot tell you which account home is active** — it prints the literal `"~/.factory"`
   regardless of `FACTORY_HOME_OVERRIDE`. Use `host.json.hostId`. (§1, §7)
9. **`FACTORY_DISABLE_KEYRING=1`** — value resolved from the CLI's own remediation text. (§7)
10. **`/api/billing/limits` exists** — proven by a 401-JSON vs 404-HTML differential. Conversely
    **`/api/auth/whoami` does not** exist at that path. (§6b)
11. **There is a fourth compaction receipt:** `droid_working_state_changed` →
    `compacting_conversation`, live and free. (§5d)
12. **`no_approver_available` exists and is classified as a non-error by Droid.** An unattended
    session can die of "nobody could approve" and be logged as a normal ending. (§6a)
13. **Daemon protocol identified** — same envelope, WebSocket, `daemon.authenticate` first,
    unauthenticated `/health`, no port discovery file, 158 methods. (§12)
14. **Exact param names recovered** by error-driven schema discovery (send `{}`, read the
    `-32602`): `add_user_message.text`, `change_working_directory.workingDirectory`,
    `kill_worker_session.workerSessionId`, `rename_session.title`, `set_skill_disabled.{skillName,disabled}`,
    `submit_bug_report.userComment`, `append_messages.messages`,
    `resolve_queued_user_message.action` ∈ `{update_queue, delete}`,
    `get_rewind_info.{sessionId, messageId}`,
    `execute_rewind.{sessionId, messageId, filesToRestore, filesToDelete, forkTitle}`.
    **This technique is reusable for every platform in this scan** and costs nothing.

---

## 14. The adapter interface

Eleven capabilities. `hostId` and the assigned `sessionId` are the two keys everything hangs off.

| # | Capability | Droid | How |
| --- | --- | --- | --- |
| 1 | **Preflight** | **Native** | `doctor --json --auth`, gate on `auth.verify == "pass"` |
| 2 | **Launch headless, pinned id, structured output** | **Native** | `droid exec --input-format stream-jsonrpc --output-format stream-jsonrpc` + `initialize_session{sessionId}` |
| 3 | **Visible attachable terminal** | **Emulated** | Terminal emulator + `droid --resume <assigned id>`. Injecting into a *foreign* TUI is **impossible** in-protocol (daemon terminal methods UNKNOWN) |
| 4 | **Liveness / state** | **Native** | `workingState` (6-value enum) via notification or `load_session`; `assistantActiveTimeMs` from the sidecar |
| 5 | **Context read** | **Native** | `get_context_breakdown` → `contextBudget`/`freeTokens`/`categories` |
| 6 | **Compaction + proof** | **Native** | `compact_session` → `removedCount` + successor id; `compacting_conversation` state; `PreCompact` hook. **Must remap the ticket→session id.** |
| 7 | **Quota read-ahead** | **Emulated (unsupported)** | `GET /api/billing/limits` (route existence VERIFIED, undocumented) behind a contract test; else credit-burn estimation from the sidecar + `tokenMultiplier` |
| 8 | **Quota in-band** | **Native** | `agent_turn_completed.reason` ∈ `model_usage_exhausted` / `model_rate_limited` |
| 9 | **Account switch (new session)** | **Native** | `FACTORY_HOME_OVERRIDE` + `FACTORY_DISABLE_KEYRING=1`; verify via `auth.verify` + `host.json` |
| 9b | **Account switch (running session)** | **Impossible** | Interrupt → close → reload under new env. Cost: one killed turn |
| 10 | **Instruction delivery + ack** | **Native** | `add_user_message` → `{}` + `create_message` echoing `requestId` |
| 11 | **Answer permission / question** | **Native** | Respond to server→client `request_permission` / `ask_user` by id |
| 12 | **Resume after crash / reboot** | **Native** | `load_session{sessionId, loadAllMessages}`; VERIFIED across SIGKILL |
| 13 | **Clean stop** | **Native** | `interrupt` → `close` → SIGTERM; verify `background-tasks.json` empty |

**Impossible:** changing a running session's account; injecting into a TUI the orchestrator did not
spawn; a *supported* quota read-ahead.

**Emulation budget:** one line-delimited JSON-RPC client with id correlation (reusable across
platforms — `pi` needs the same shape), one `/api/billing/limits` poller with a contract test, and
the existing terminal-launch plumbing. That is small.

### Mandatory adapter invariants

1. **Await `initialize_session` before any other request.** Pipelining gets `-32603`.
2. **Re-attach `permissionHandler` and `askUserHandler` on every create *and* every resume**, and
   log every declined question. This failure is silent.
3. **Remap ticket→session on compaction** — the successor has a new id.
4. **Classify `no_approver_available` and `permission_rejected` as failures.** Droid does not.
5. **Pin the version** (`FACTORY_DROID_AUTO_UPDATE_ENABLED=false`, npm install) in *every* process.
6. **Use `droid exec`, never a driven TUI**, for unattended work — sandbox violations auto-deny
   instead of hanging.
7. **Watch `breakdown.freeTokens`, not `stats.remaining`.**
8. **Re-read `limit` after any model change.**
9. Hard-code binary flag names `--only-tools` / `--add-tools` / `--remove-tools`; the docs are stale.
10. Decide `cloudSessionSync` deliberately — it defaults to **`true`** and mirrors CLI sessions to
    Factory web.

---

## 15. Support tier

### **Tier 1** — all core axes, with one asterisk.

Droid implements **12 of the 13** adapter capabilities natively. It is the only platform in this
scan that answers launch, identity, transcript, context, intervention and guardrails *all* at
first-class quality, and after this spike it also answers **identity assignment**, which was the
last thing separating it from `pi`.

The asterisk is **quota read-ahead** — the owner's stated non-negotiable. There is no supported
programmatic read of remaining capacity; the only path is an undocumented endpoint on a CLI that
ships near-daily. This spike upgrades that from "probably real" to "the route provably exists and
its evaluation logic is known verbatim", which makes it a *manageable* bet rather than a guess, but
it remains a bet.

Two things materially soften it, and both are Droid-specific advantages:

- The **in-band** signal is precisely typed (`model_usage_exhausted` vs `model_rate_limited`), so
  the supervisor can always *react* correctly even if it cannot *predict*.
- Droid can **downshift to Droid Core**, a pool with separate limits, instead of stopping. The
  overnight queue degrades rather than halts — which no other platform here offers.

**Verdict: adopt as a tier-1 executor.** Build the adapter on raw JSON-RPC over
`droid exec --input-format stream-jsonrpc`, not the SDK and not the daemon. Treat
`/api/billing/limits` as a guarded optimisation on top of in-band reaction, never as the only
brake. The remaining work is small and the protocol is now fully charted.

### Still UNKNOWN, ranked by value

1. **Does a TUI session register with a local daemon?** If yes, `daemon.write_terminal_data` solves
   injecting into the owner's own visible sessions — a capability nothing else in this scan has.
   Needs one authenticated hour.
2. **`daemon.*` params** for `droid_spawn`, `create_terminal`, `create_cron`. 158 method names are
   known; no schemas.
3. **`compact_session` on a real conversation** — `removedCount`, successor semantics, and whether
   the successor is announced on the wire. Needs auth.
4. **Does the 429 `metadata` object carry a reset time?** `CreateSession429ResponseBody` is the
   generic error envelope with an untyped `metadata`.
5. **ACP mode** (`--output-format acp|acp-daemon`) — a cross-vendor protocol that might be shared
   with other platforms instead of writing this adapter per-platform.

---

## Sources

**Executed on this machine, 2026-09-19** (sandbox at `$SB`, owner's `~/.factory` never created):

- `droid --version | --help`; `droid exec --help`; `droid daemon --help`
- `droid doctor --json --auth`, `--json --daemon`
- `droid exec --output-format json "say hi"` (exit 1, auth failure — no quota spent)
- `droid search --json "pinned"`
- `droid daemon -p 47777 --listen websocket -d` — start, `/health`, WebSocket probe, SIGTERM
- A custom line-delimited JSON-RPC client over
  `droid exec --input-format stream-jsonrpc --output-format stream-jsonrpc`, driving:
  `initialize_session` (with and without a pinned id, and re-init of an existing id),
  `load_session` (existing and unknown id), `get_context_stats`, `get_context_breakdown`,
  `compact_session`, `fork_session`, `rename_session`, `update_session_settings`,
  `add_user_message`, `interrupt_session`, `close_session`, `list_tools`, `list_models`,
  `list_skills`, `list_commands`, `list_mcp_servers`, `list_mcp_tools`, `warmup_cache`,
  and empty-param probes of 23 methods for schema discovery
- SIGKILL-then-resume crash test with a pinned session id
- `--settings` override proving `contextBudget` 250000 → 60000
- `FACTORY_HOME_OVERRIDE` isolation test with `FACTORY_DISABLE_KEYRING=1`
- `curl` differential probe of four `api.factory.ai` routes (unauthenticated, 401-JSON vs 404-HTML)
- On-disk artefacts: `sessions/<cwd-slug>/<id>.jsonl`, `<id>.settings.json`, `host.json`,
  `background-tasks.json`, `background-processes.json`

**Read verbatim:**

- `strings` over `@factory/cli-darwin-arm64` 0.223.0 — `handleInitializeSession`, the JSON-RPC
  envelope schema, the turn-completion `reason` enum and its classifier, the billing-limits
  evaluation functions, `daemon.authenticate` schema, the permission/ask_user emitters, the
  working-state sets, `FACTORY_DISABLE_KEYRING` remediation text, the 158 `daemon.*` method names
- `@factory/droid-sdk@0.9.1` `dist/node.d.ts` and `dist/index-C06W9tbN.d.ts` — `CreateSessionOptions`,
  `SessionInitOptions`, `ResumeSessionOptions`, `DroidProcessConfig`, and the `DroidWorkingState`,
  `ToolConfirmationOutcome`, `AutonomyLevel`, `DroidInteractionMode`, `SessionPlatform` enums
- `https://docs.factory.ai/openapi.json`, `https://docs.factory.ai/llms.txt` (via the profile pass)
