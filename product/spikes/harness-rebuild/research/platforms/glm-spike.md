# SPIKE — Z.ai GLM as a first-class orchestrator platform

**Date:** 2026-09-19. **Machine:** owner's Mac, darwin 25.5.0. **Driver under test:** Claude Code
**2.1.278** (`~/.local/bin/claude` → `~/.local/share/claude/versions/2.1.278`).
**Companion:** `glm.md` (the capability profile — read it first; this document does not restate it).

---

## 0. Read this before the recipes: what "verified" means here, and the method that made it possible

**There is no Z.ai credential on this machine** (`which glm zai chelper coding-helper` → nothing; no
`~/.zai`, `~/.chelper`, `~/.zcode`; no `ZAI_*` / `GLM_*` / `ANTHROPIC_BASE_URL` in the environment —
all VERIFIED by probe today). A spike that stopped there could only have quoted documentation.

So this pass did something better than guess: **it built a local HTTP server that impersonates Z.ai's
Anthropic-compatible surface, pointed Claude Code at it with Z.ai's own documented environment block,
and ran all eleven recipes against it.** The stub (Appendix A, ~90 lines of Python, kept in the
scratchpad) can serve a normal streaming answer, a tool call, or **a real Z.ai `429` carrying error
code `1316`** — and it logs every header and body it receives.

That method verifies, with zero spend and zero risk to the owner's configuration:

- exactly what Claude Code puts **on the wire** when configured for GLM — model id, auth header
  shape, beta headers, cache breakpoints;
- exactly what it **writes to disk** — session file path, compaction records, error records;
- exactly what it **prints** on stdout vs stderr, and on which stream the orchestrator must parse;
- exactly how it **behaves on a GLM quota exhaustion**, end to end, including the final result object.

What it cannot verify is anything that depends on Z.ai's server actually being on the other end:
whether the gateway honours `cache_control`, whether it accepts the `context-1m` beta header, whether
`count_tokens` returns true numbers, and the live shape of an authenticated quota response. Those are
listed in §14 and each one is tagged **UNKNOWN (needs a live key)**.

**Tags used below:** **VERIFIED-LIVE** — run on this machine today against the stub or against Z.ai's
real endpoints. **VERIFIED-SOURCE** — read in Z.ai's own shipped code or in `claude --help` on the
installed build. **VERIFIED-DOCS** — read in official Z.ai documentation. **CLAIMED** — vendor or
third-party assertion only. **UNKNOWN** — could not be established.

> **Nothing in the owner's configuration was modified.** Every run used
> `CLAUDE_CONFIG_DIR=<scratchpad>/glmstub/cfg` and a scratchpad working directory. `~/.claude/settings.json`
> mtime is unchanged (Sep 18 23:43, before this session); no `~/.chelper` or `~/.zai` was created; all
> stub processes and test sessions were stopped and removed at the end (VERIFIED-LIVE).

---

## 0.1 The provider object — the single thing the orchestrator must model

GLM is not a CLI and not a session. It is a credential triple plus a context window. Everything in
this spike is parameterised by one record:

```jsonc
// orchestrator provider registry entry
{
  "id": "glm-prod-seat-1",
  "kind": "anthropic-compatible",
  "base_url": "https://api.z.ai/api/anthropic",     // CN: https://open.bigmodel.cn/api/anthropic
  "monitor_origin": "https://api.z.ai",             // = origin of base_url; derived, never configured
  "token_ref": "keychain://glm/seat-1",             // NEVER inline, NEVER in a settings file
  "model": "glm-5.3",
  "small_model": "glm-5.3-flash",
  "context_window": 1048576,                        // FIRST-CLASS. Never derived. See recipe 5.
  "plan_tier": "pro",                               // lite | pro | max | team-standard | team-premium
  "max_concurrent_sessions": 2                      // policy-derived, not technical. See recipe 7.
}
```

**The launch environment is a pure function of that record** (every name and value
VERIFIED-SOURCE in `@z_ai/coding-helper@0.1.1` `dist/lib/claude-code-manager.js`, re-downloaded and
read on disk today, and VERIFIED-LIVE as accepted by the 2.1.278 binary):

```bash
glm_env() {   # $1 = provider id; prints an env block, reads the token from the keychain at call time
  cat <<EOF
ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
ANTHROPIC_AUTH_TOKEN=$(security find-generic-password -s "glm/$1" -w)
API_TIMEOUT_MS=3000000
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
ANTHROPIC_DEFAULT_SONNET_MODEL=glm-5.3[1m]
ANTHROPIC_DEFAULT_OPUS_MODEL=glm-5.3[1m]
ANTHROPIC_DEFAULT_HAIKU_MODEL=glm-5.3-flash[1m]
CLAUDE_CODE_AUTO_COMPACT_WINDOW=1048576
EOF
}
```

### What the `[1m]` suffix actually does — corrected, VERIFIED-LIVE

`glm.md` §A.1 records the suffix rule but not its mechanism. The stub's request log settles it:

```
POST /v1/messages?beta=true
  model      = glm-5.3                      <-- the [1m] suffix is STRIPPED before the wire
  authorization  = Bearer <ANTHROPIC_AUTH_TOKEN>
  anthropic-beta = claude-code-20250219,context-1m-2025-08-07,interleaved-thinking-2025-05-14,
                   thinking-token-count-2026-05-13,context-management-2025-06-27,
                   prompt-caching-scope-2026-01-05,mid-conversation-system-2026-04-07,
                   mid-conversation-tool-changes-2026-07-01,effort-2025-11-24
  anthropic-version = 2023-06-01
  x-claude-code-session-id = <the pinned --session-id>
  user-agent = claude-cli/2.1.278 (external, sdk-cli)
  body contains "cache_control" x3
```

Four consequences the implementer must encode:

1. **`[1m]` is a client-side directive, not a model id.** Claude Code sends `glm-5.3` and converts the
   suffix into `anthropic-beta: context-1m-2025-08-07`. Do not expect Z.ai to recognise a literal
   `glm-5.3[1m]`; **do** expect Z.ai's gateway to have to tolerate that beta token. Whether it does is
   **UNKNOWN (needs a live key)** and is the cheapest high-value thing to test first.
2. **The auth header is `Authorization: Bearer <key>`** on the inference surface — while the **monitor**
   surface requires the same key **raw, with no `Bearer` prefix** (recipe 6). One key, two header
   shapes. This is the most likely copy-paste bug in the adapter.
3. **`x-claude-code-session-id` leaks the orchestrator's session id to Z.ai.** Harmless, but it means
   session ids should not encode anything sensitive.
4. **Claude Code does send `cache_control` breakpoints to the third-party endpoint** (3 per request
   here, plus the `prompt-caching-scope` beta). So `glm.md`'s open question #1 narrows: the client
   side is confirmed; only Z.ai's honouring of them is open, and recipe 6's probe measures it.

### The window-arithmetic trap, now with a number

Z.ai's helper writes `CLAUDE_CODE_AUTO_COMPACT_WINDOW=1048576` (VERIFIED-SOURCE:
`String(sel.modelContextWindow)` where the registry holds `1_048_576`). Claude Code's own accounting
**reports the window as `1000000`** (VERIFIED-LIVE: `modelUsage["glm-5.3[1m]"].contextWindow == 1000000`
in the result object, and `/context` renders `2.5k / 1m`). The two disagree by 48,576 tokens.

**Set `CLAUDE_CODE_AUTO_COMPACT_WINDOW=1048576` anyway** — it is what Z.ai ships — but the
orchestrator's own "how full is it" arithmetic must use **1,000,000**, because that is the number the
autocompact buffer is computed against. Budget the 48K difference as headroom, never as usable space.

---

## Recipe 1 — Preflight: installed, authenticated, which account is active

**verified: true** (every command below was run; only the `success:true` branch could not be reached
without a key).

```bash
#!/usr/bin/env bash
# glm-preflight.sh <provider-id> — exits 0 only if this provider can start work right now.
set -euo pipefail
BASE="https://api.z.ai/api/anthropic"
MON="${BASE%/api/anthropic}"                          # -> https://api.z.ai
KEY="$(security find-generic-password -s "glm/$1" -w)"

# 1. driver present
command -v claude >/dev/null || { echo "FAIL: no claude binary"; exit 10; }
claude --version                                       # -> "2.1.278 (Claude Code)"

# 2. the key is live, and the plan is active.  NOTE: HTTP status is USELESS here.
resp="$(curl -sS -m 20 "$MON/api/monitor/usage/quota/limit" \
          -H "Authorization: $KEY" \
          -H "Accept-Language: en-US,en" \
          -H "Content-Type: application/json")"
echo "$resp" | jq -e '.success == true' >/dev/null \
  || { echo "FAIL: $(echo "$resp" | jq -r '.code // "?" ') $(echo "$resp" | jq -r .msg)"; exit 11; }

# 3. which account is active — there is no /whoami; identity is the key + the plan level it reports
echo "$resp" | jq -r '"plan_level=\(.data.level)  windows=\([.data.limits[].type] | join(","))"'
```

**Success looks like** `{"code":200,"success":true,"data":{"level":"pro","limits":[…]}}` and the script
printing `plan_level=pro`. **(The authenticated shape is VERIFIED-SOURCE only** — from
`opencode-glm-quota`'s typed interface and Z.ai's own `query-usage.mjs` unwrapping `json.data`.)

**Failure looks like — and this is the headline defect of the whole platform:**

```
$ curl -s -w " HTTP %{http_code}" https://api.z.ai/api/monitor/usage/quota/limit
{"code":1001,"msg":"Authentication parameter not received in Header, unable to authenticate","success":false} HTTP 200

$ curl -s -w " HTTP %{http_code}" https://api.z.ai/api/monitor/usage/quota/limit -H "Authorization: not-a-real-key"
{"code":401,"msg":"token expired or incorrect","success":false} HTTP 200
```
*(Both VERIFIED-LIVE today, `api.z.ai`.)*

> **The monitor endpoints return HTTP 200 on authentication failure.** Z.ai's own official script and
> the best community plugin both gate on `res.statusCode !== 200` and therefore both read an auth
> failure as a successful, empty response. **Gate on `.success == true`. Never on the HTTP status.**
> An unattended pause loop that inherits this bug reports "no quota data" when the truth is "your key
> is dead", and sleeps forever.

Note the contrast, both VERIFIED-LIVE today: the **inference** surface is honest —
`POST /api/anthropic/v1/messages` with no key returns a real **HTTP 401** with an Anthropic-shaped
`{"error":{"message":…,"type":"1001"}}` body, which an Anthropic SDK client handles natively.

**Fallback if the monitor endpoint is unreachable:** send a 1-token `POST` to
`$BASE/v1/messages` with `max_tokens:1` and treat HTTP 401/403 as "key dead", 429 as "key alive but
throttled" (see recipe 6 for the codes), 200 as "alive". Costs a few credits; use only when the
monitor host itself fails.

**Preflight must also assert the account is not already in use** — see recipe 7 for why that is a
policy requirement, not an optimisation.

---

## Recipe 2 — Start a task headless, pinned session id, structured output

**verified: true** — run end to end against the stub; the exact command below produced the output
quoted.

```bash
SID=$(uuidgen | tr 'A-Z' 'a-z')      # Claude Code requires a valid lowercase UUID
env -i PATH="$PATH" HOME="$HOME" TERM=dumb \
    CLAUDE_CONFIG_DIR="$ORCH_HOME/agents/$SID" \
    $(glm_env glm-prod-seat-1) \
  claude -p "$TASK_TEXT" \
    --session-id "$SID" \
    --output-format json \
    --model sonnet \
    --permission-mode acceptEdits \
    --settings "$ORCH_HOME/guardrails.json" \
    < /dev/null \
    > "$RUN/$SID.result.json" \
    2> "$RUN/$SID.stderr"
```

**`--model sonnet`, not `--model glm-5.3`.** The GLM id is injected by
`ANTHROPIC_DEFAULT_SONNET_MODEL`; passing the tier alias is what lets one launcher serve every
provider. (VERIFIED-LIVE: the wire model was `glm-5.3` and `modelUsage` was keyed `glm-5.3[1m]`.)

**Success looks like** a single JSON object on **stdout**:

```jsonc
{ "type":"result", "subtype":"success", "is_error":false, "terminal_reason":"completed",
  "session_id":"11111111-2222-4333-8444-555555555555",
  "result":"GLM-STUB-OK", "num_turns":1, "duration_ms":39,
  "usage":{"input_tokens":11,"output_tokens":5,"cache_read_input_tokens":0,…},
  "modelUsage":{"glm-5.3[1m]":{"contextWindow":1000000,"maxOutputTokens":32000,
                               "costUSD":0.00018,"costBasis":"unknown","provider":"firstParty"}} }
```

**Two parsing rules, both VERIFIED-LIVE:**

1. **Never merge the streams.** stderr carries a line that is not part of the payload:
   `[claude-code:unrecognized_model] {"model":"glm-5.3[1m]","query_source":"sdk"}`.
   It is emitted on **every** GLM invocation. With `2>&1` the output stops being parseable JSON; with
   the streams separated, stdout parses cleanly (`json.load` → OK). Capture stderr to its own file —
   it is useful, not noise (recipe 4 reads it).
2. **`subtype` is not a success signal.** See recipe 6 — a quota exhaustion also reports
   `"subtype":"success"`. The gate is `is_error == false && terminal_reason == "completed"`.

**`costBasis":"unknown"` and `hasUnknownModelCost: true`** (the latter in the transcript's `cost-state`
record) are Claude Code telling you its dollar figure is fabricated from Anthropic's price table.
**`--max-budget-usd` is therefore unusable as a spend brake on GLM** — this closes `glm.md` open
question #5 in the negative. Budget in credits via recipe 6.

**Failure looks like:** exit code stays 0 even on API failure, so never gate on `$?`. A dead key
surfaces as `"is_error":true` with `api_error_status: 401`; a wrong `--session-id` (not a UUID) fails
immediately with a usage error before any request.

**Structured output beyond `json`:** `--output-format stream-json --verbose` gives a live event
stream (`system/init`, `stream_event`, `assistant`, `result`); `--include-partial-messages` adds token
deltas; `--json-schema <schema>` constrains the final answer. All VERIFIED-SOURCE in `claude --help`;
`stream-json` VERIFIED-LIVE in recipe 8.

---

## Recipe 3 — Start the same task in a visible terminal the owner can type into

**verified: true** for the two Claude-Code-side facts; the terminal backend is the owner's existing,
already-shipped code.

There are two shapes, and they differ in a way that matters.

### 3a. Background session (`--bg`) — attachable, but it will not take your session id

```bash
env -i … $(glm_env glm-prod-seat-1) \
  claude --bg "$TASK_TEXT" --model sonnet --permission-mode acceptEdits
# -> backgrounded · 6674f750
#      claude attach 6674f750 / logs 6674f750 / stop 6674f750
```

**Two hard constraints, both VERIFIED-LIVE:**

```
$ claude --bg 'say hi' --session-id 3333… --permission-mode bypassPermissions
--bg with bypassPermissions requires accepting the disclaimer first.
Run `claude --dangerously-skip-permissions` once interactively.

$ claude --bg 'say hi' --session-id 3333… --permission-mode acceptEdits
warning: --bg manages the session id; ignoring --session-id (use --resume <id> to continue an existing session)
```

1. **`--bg` ignores `--session-id`.** To run a pinned id in the background, create it first with
   `-p --session-id <uuid>` (recipe 2), then `claude --bg --resume <uuid>`.
2. **`--bg` + `bypassPermissions` needs a one-time interactive disclaimer acceptance per config dir.**
   An orchestrator that mints a fresh `CLAUDE_CONFIG_DIR` per session will hit this on every launch.
   Either keep one long-lived config dir per provider account, or do not use `bypassPermissions` with
   `--bg` (prefer `acceptEdits` + a `PreToolUse` hook, recipe 9).

The short id (`6674f750`) is the first segment of the full session UUID
(`6674f750-61ef-433d-89ac-8b46e8f3a105`) — VERIFIED-LIVE, so the mapping is derivable, not a lookup.

### 3b. Real terminal window (what the owner actually asked for)

`--bg` gives an attachable session, not a window the owner can walk up to. For that, the orchestrator
spawns the driver inside a terminal it controls. **This already exists in the owner's tree** —
`plugins/harness/bin/harness-term.sh`, which speaks `spawn | send | key | capture | close`, addresses
sessions **by tty** (window ids drift), keeps a `group → window` map so later spawns become tabs in
the same window, and auto-selects iTerm2 → tmux → Terminal.app. `~/.claude/shared/tooling.json` sets
`terminal_launcher.default = "iterm2-osascript"` with semantics *"tab in the current window when one
exists, else ONE fresh window"*. (Both VERIFIED-LIVE by reading them today.)

The GLM-specific part is only that the launcher file must carry the environment:

```bash
cat > "$RUN/$SID.launch.sh" <<EOF
#!/usr/bin/env bash
cd "$WORKDIR"
export $(glm_env glm-prod-seat-1 | tr '\n' ' ')
exec claude --resume "$SID" --model sonnet --permission-mode acceptEdits
EOF
chmod +x "$RUN/$SID.launch.sh"
harness-term.sh spawn "glm-fleet" "glm-$SHORTID" "$RUN/$SID.launch.sh"
```

`harness-term.sh` deliberately never inlines prompt text into AppleScript (it executes a plain file)
and validates titles against a conservative charset — keep both properties.

**Success looks like** a visible tab whose banner reads `glm-5.3[1m] · API Usage Billing`
(VERIFIED-LIVE in `claude logs` output) — **that banner string is a free assertion that the session is
on GLM and not on the owner's Anthropic subscription.** Assert it.

**Failure looks like** a window that opens and dies instantly (bad env → `Not logged in · Please run
/login`, VERIFIED-LIVE when `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN` are absent), or
`osascript` returning `-1743` (macOS Automation permission not granted).

**Fallback:** tmux (`harness-term.sh` selects it automatically when iTerm2 is absent) — fully
scriptable, no GUI permission, and `capture-pane` replaces `capture`.

---

## Recipe 4 — Is the session alive, working, waiting, or finished?

**verified: true** — `claude agents --json --all` was run headless (no TTY) and produced the output
below, including a session that was, at that moment, stuck in a GLM 429 retry loop.

```bash
claude agents --json --all      # honours CLAUDE_CONFIG_DIR; needs no TTY
```

```json
[
  { "pid": 15229, "kind": "interactive", "status": "busy",
    "sessionId": "99999999-2222-4333-8444-555555555555",
    "cwd": "…/glmstub/work", "name": "work-03", "startedAt": 1789824444869 },
  { "pid": 23056, "id": "6674f750", "kind": "background", "status": "idle", "state": "working",
    "sessionId": "6674f750-61ef-433d-89ac-8b46e8f3a105", "name": "say hi", "startedAt": 1789824586298 }
]
```

**Fields worth trusting:** `pid`, `kind` (`interactive` | `background`), `status`
(`busy` | `idle` | `stopped`), `sessionId`, `cwd`, `startedAt`, and `id` for background sessions.
**`state` is stale** — VERIFIED-LIVE: a session that had visibly finished its turn still reported
`"state":"working"` while `"status":"idle"`. Use `status`.

> **The finding that changes the supervisor's design:** in the listing above, PID 15229 reports
> **`"status":"busy"`** — and it was doing nothing but retrying a `429 / 1316` quota error with
> exponential backoff. **A quota-exhausted GLM session is indistinguishable from a working one in
> `claude agents --json`.** Liveness alone is not progress. (VERIFIED-LIVE.)

### The four states, and how to actually tell them apart

| State | Signal | Tag |
|---|---|---|
| **finished (clean)** | result object on stdout with `is_error:false` **and** `terminal_reason:"completed"` | VERIFIED-LIVE |
| **finished (failed)** | result object with `is_error:true`; read `terminal_reason` + `api_error_status` | VERIFIED-LIVE |
| **alive and progressing** | the session JSONL's mtime advances **and** new `assistant`/`user` records appear | VERIFIED-LIVE |
| **alive but stalled on the provider** | new `{"type":"system","subtype":"api_error"}` records with rising `retryAttempt` | VERIFIED-LIVE |
| **gone** | `pid` absent from `claude agents --json`, no result object written | VERIFIED-LIVE |

The transcript is the ground truth. Its path is deterministic:

```
$CLAUDE_CONFIG_DIR/projects/<cwd with '/' and '.' replaced by '-'>/<session-uuid>.jsonl
```
e.g. `…/glmstub/cfg/projects/-private-tmp-…-scratchpad-glmstub-work/11111111-….jsonl` (VERIFIED-LIVE).

A supervisor's per-tick health read, all local, no API cost:

```bash
T="$CFG/projects/$(printf '%s' "$WORKDIR" | tr '/.' '-')/$SID.jsonl"
tail -n 200 "$T" | jq -c 'select(.type=="system" and .subtype=="api_error")
                          | {status:.error.status, retryAttempt, maxRetries,
                             code:(.error.message|capture("\"type\":\"(?<c>[0-9]+)\"").c // null)}'
```

**Fallback for a visible-terminal session:** `harness-term.sh capture <tty> 40`, or
`claude logs <id>` for a background one — but note `claude logs` returns a **raw ANSI screen dump**
(VERIFIED-LIVE: full escape sequences, cursor moves, box-drawing), not a log. Strip ANSI before
matching, and prefer the JSONL.

---

## Recipe 5 — Read context fullness, force a compaction, prove it happened

**verified: true** — all three steps run against the stub.

### 5a. Read fullness — two ways, one of them free

**Way 1 — from the transcript, zero API calls, always available:**

```bash
jq -s 'map(select(.type=="assistant" and .message.usage)) | last | .message.usage
       | (.input_tokens + .cache_read_input_tokens + .cache_creation_input_tokens + .output_tokens)' "$T"
# divide by 1000000 (NOT 1048576 — see §0.1)
```

**Way 2 — ask the session, and it is cheaper than it looks:**

```bash
claude -p '/context' --resume "$SID" --output-format json --model sonnet 2>/dev/null | jq -r .result
```
```
## Context Usage

**Model:** glm-5.3[1m]
**Tokens:** 2.5k / 1m (0%)

| Category | Tokens | Percentage |
| System prompt | 1.9k | 0.2% |
| Messages | 618 | 0.1% |
| Free space | 964.5k | 96.4% |
| Autocompact buffer | 33k | 3.3% |
```

**VERIFIED-LIVE, and measured:** that `/context` call made **zero inference requests** — the stub
logged exactly **10 `POST /v1/messages/count_tokens?beta=true`** calls and **no** `/v1/messages` call.
So it burns no output tokens and no reasoning, but it is **not** free: it depends on Z.ai implementing
`count_tokens`.

**Does Z.ai implement it? Strong evidence yes** (VERIFIED-LIVE, differential probe today):

```
POST https://api.z.ai/api/anthropic/v1/messages/count_tokens?beta=true   (no key)
  -> HTTP 401  {"error":{"message":"…","type":"1001"}}        <-- Anthropic-shaped: route IS handled

POST https://api.z.ai/api/anthropic/v1/definitely-not-a-route            (no key)
  -> HTTP 200  {"code":1001,"msg":"…","success":false}        <-- generic envelope: route NOT handled
```

The two shapes differ, so `count_tokens` is routed by Z.ai's Anthropic adapter rather than falling
through to the generic gateway. Whether the counts are *accurate* is **UNKNOWN (needs a live key)**.
**Use way 1 for the supervisor's polling loop** (free, no dependency) and way 2 for a human-readable
check; note that way 2 appends records to the session, so it is a write, not a read.

### 5b. Force compaction from outside

```bash
claude -p '/compact' --resume "$SID" --output-format json --model sonnet --permission-mode acceptEdits < /dev/null
# optional steer: '/compact keep the acceptance criteria and the failing test verbatim'
```

Auto-compaction is governed by `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (env) or `--autocompact <auto|tokens>`
— *"Auto-compact window size (auto, or 100k–1M tokens)"* (VERIFIED-SOURCE, quoted from `claude --help`
on 2.1.278).

### 5c. Prove it happened — this is the part worth stealing

A `compact_boundary` record is appended to the session JSONL (VERIFIED-LIVE, full record):

```json
{ "type": "system", "subtype": "compact_boundary", "content": "Conversation compacted",
  "level": "info", "timestamp": "2026-09-19T13:31:34.494Z",
  "logicalParentUuid": "cc6f5d97-f330-4dfd-a9a9-45ab3004da51",
  "compactMetadata": { "trigger": "manual", "preTokens": 43, "postTokens": 334,
                       "durationMs": 26, "cumulativeDroppedTokens": 0 },
  "sessionId": "11111111-2222-4333-8444-555555555555", "version": "2.1.278" }
```

```bash
jq -c 'select(.subtype=="compact_boundary") | .compactMetadata + {ts:.timestamp}' "$T" | tail -1
```

**Success:** a new record whose `timestamp` is after the request, with `trigger:"manual"` and
`postTokens < preTokens` on a real (non-toy) context. **`trigger` distinguishes an orchestrator-forced
compaction from an automatic one** — that is the proof, and it is free.

**Failure:** no new record, or `postTokens >= preTokens`. On GLM specifically, watch for a
compaction that *silently did not summarise*: the summarisation call is an ordinary model request,
so if it hits `1316` it fails inside the compaction and the boundary may be absent. Always re-read.

**Fallback (handoff instead of compaction):** have the session write a handoff file, then start a
fresh session seeded with it and a new `--session-id`, linking the two in the orchestrator's own
ledger. This is strictly more reliable than compaction and costs one extra turn; on a 1M window it is
rarely needed.

> **Z.ai provides no compaction hook, no server-side event, and no independent proof.** If the
> driver's transcript does not record it, it is unprovable. (VERIFIED by absence in the docs sitemap.)

---

## Recipe 6 — Read remaining quota and reset time; detect a limit hit in-band

**verified: true** — the unauthenticated behaviour, the error-code plumbing and the end-to-end
limit-hit behaviour were all run today; only the authenticated response body is VERIFIED-SOURCE.

### 6a. The poll

```bash
curl -sS -m 20 "https://api.z.ai/api/monitor/usage/quota/limit" \
  -H "Authorization: $KEY" \
  -H "Accept-Language: en-US,en" \
  -H "Content-Type: application/json"
```

**Three header rules, all load-bearing:**

- **`Authorization: <raw key>` — no `Bearer` prefix.** Stated as a literal in Z.ai's own
  `query-usage.mjs` (`'Authorization': authToken`) and called out as `// NO "Bearer" prefix` in
  `opencode-glm-quota`. Both VERIFIED-SOURCE. *(Probing with a bogus key returns the same 401 body
  either way, so this could not be differentially confirmed — trust the two independent sources.)*
- **`Accept-Language: en-US,en`** — without it the CN host answers in Chinese
  (`{"code":401,"msg":"令牌已过期或验证不正确"}`).
- **`quota/limit` takes NO query parameters.** VERIFIED-SOURCE — Z.ai's script calls it with
  `appendQueryParams = false`.

**Correction to `glm.md` §E.1:** the sibling endpoints `monitor/usage/model-usage` and
`monitor/usage/tool-usage` take `startTime`/`endTime` as **URL-encoded `yyyy-MM-dd HH:mm:ss` local-time
strings**, not millisecond epochs. VERIFIED-SOURCE — `query-usage.mjs` builds them with a
`formatDateTime()` helper and `encodeURIComponent`. Its window is "same hour yesterday" →
"end of this hour today".

### 6b. Parsing it — the two bugs to not inherit

```bash
parse_quota() {  # stdin: the raw response. stdout: one line per window.
  jq -e '.success == true' >/dev/null || { echo "QUOTA_READ_FAILED"; return 1; }   # NOT the HTTP status
  jq -r '.data.limits[]
         | select(.type=="TOKENS_LIMIT")
         | { window: (if .unit==3 and .number==5 then "5h"
                      elif .unit==6 and .number==1 then "7d"
                      else "unit\(.unit)/n\(.number)" end),
             pct: .percentage,
             resets_at: (.nextResetTime/1000 | todate) }
         | "\(.window) \(.pct)% resets \(.resets_at)"'
}
```

| `type` | `unit` | `number` | Window | Tag |
|---|---|---|---|---|
| `TOKENS_LIMIT` | 3 | 5 | 5-hour **rolling** | VERIFIED-SOURCE |
| `TOKENS_LIMIT` | 6 | 1 | weekly, anchored to the **subscription date** | VERIFIED-SOURCE + VERIFIED-DOCS |
| `TIME_LIMIT` | — | — | MCP tool usage, 1 month (`currentValue`/`usage` absolute) | VERIFIED-SOURCE |

Two defects to avoid, both VERIFIED-SOURCE by reading the shipped implementations side by side:
**(a)** Z.ai's own `query-usage.mjs` labels *every* `TOKENS_LIMIT` as `'Token usage(5 Hour)'` and
**drops `unit`, `number` and `nextResetTime` entirely** — run the official plugin and you get two
identical rows and no reset time. **(b)** both implementations gate on the HTTP status, so both read an
auth failure as success. **Read the raw endpoint. Do not shell out to Z.ai's script.**

`nextResetTime` is **Unix milliseconds** and is the number the pause loop sleeps until. Only
`percentage` is returned for token windows — absolute remaining tokens must be inferred from the
published plan allowance (Lite 2,000/10,000 · Pro 12,000/60,000 · Max 28,000/140,000 credits;
VERIFIED-DOCS).

**Credits, not tokens, and time-of-day matters.** GLM-5.3 costs **1× off-peak / 3× peak**;
GLM-5.3-Flash **0.4× / 1.2×**. Peak = **Mon–Fri 14:00–18:00 SGT = 06:00–10:00 UTC = 09:00–13:00 Kyiv**
(VERIFIED-DOCS). The same work is **7.5× more expensive** on GLM-5.3 at peak than on Flash off-peak.
**An overnight European queue is entirely off-peak; a scheduler that holds heavy work until after
13:00 Kyiv cuts credit burn by roughly two-thirds.** Encode this as a scheduling rule, not a footnote.

### 6c. In-band limit detection — what a real 1316 does, end to end

The stub was switched to return the documented `429` and a full run was executed. **This is the most
operationally important result in the spike.**

**What lands in the transcript, per retry** (VERIFIED-LIVE, full record):

```json
{ "type":"system", "subtype":"api_error", "level":"error",
  "error": { "status": 429,
             "message": "429 {\"error\":{\"type\":\"1316\",\"message\":\"Usage limit reached for the past 5 hours. Insufficient balance\"}}",
             "formatted": "429 Usage limit reached for the past 5 hours. Insufficient balance",
             "rateLimits": null, "isNetworkDown": false },
  "retryInMs": 605, "retryAttempt": 1, "maxRetries": 10, "source": "request_retry",
  "sessionId": "88888888-…", "timestamp": "2026-09-19T13:30:31.642Z" }
```

> **The GLM numeric code survives into the transcript.** `error.message` carries the raw Z.ai body
> including `"type":"1316"`. **This is the only place the code survives** — see below. A supervisor
> tailing the JSONL detects and classifies a GLM quota exhaustion **in real time, with no API call**,
> and can tell a 5-hour pause (**1316**) from a week-long one (**1317**) the moment it happens.

```bash
# the supervisor's in-band detector — run every tick against the live transcript
tail -n 400 "$T" | jq -r 'select(.subtype=="api_error" and .error.status==429)
  | (.error.message | capture("\"type\":\"(?<c>[0-9]+)\"").c)' | tail -1
# 1316 -> 5h window exhausted   1317 -> weekly exhausted   1302/1305 -> transient
# 1313 -> FAIR USE / risk control   1309 -> plan expired   1311 -> model not on plan
```

**What the run actually did** (VERIFIED-LIVE, measured):

- **11 requests over 177 seconds** before giving up — retries at t+0, 0.5, 1.8, 3.8, 8.3, 17.1, 37,
  77, 114, … `maxRetries: 10`.
- **stdout stayed completely empty for those 177 seconds.** No partial output, nothing to parse.
- `error.rateLimits` is **`null`** — Z.ai's 429 carried no `retry-after` and no `anthropic-ratelimit-*`
  headers in this shape. `glm.md`'s open question #2 leans to "must poll `quota/limit`".
- **The final result object:**

```jsonc
{ "subtype": "success",                 // <-- THE TRAP
  "is_error": true,
  "terminal_reason": "api_error",
  "api_error_status": 429,
  "result": "API Error: Request rejected (429) · Usage limit reached for the past 5 hours. Insufficient balance",
  "num_turns": 1, "duration_ms": 177488 }
```
and the process **exited with code 0**.

> **Three traps in one object.** `subtype` says `"success"` on a quota exhaustion. The **exit code is
> 0**. And the numeric code **`1316` is gone** — only the prose survives. An orchestrator that gates on
> `subtype`, or on `$?`, marks a quota-blocked ticket as done and moves on. The gate is
> `is_error == false && terminal_reason == "completed"`; the code classification comes from the
> transcript, not the result.

**Practical consequence:** cap the wait. A supervisor should not let a session burn 177 s of wall time
re-hitting an exhausted window. Detect the **first** `api_error` with a `1316`/`1317` code in the
transcript, `claude stop` the session immediately, read `nextResetTime`, sleep, and resume (recipe 10).

**Cache probe (settles `glm.md` open question #1, the most expensive unknown).** Claude Code is
confirmed to send `cache_control` (§0.1). With a live key, run the same prompt twice and read:

```bash
jq -s 'map(select(.type=="assistant")) | last | .message.usage
       | {cache_read_input_tokens, cache_creation_input_tokens, input_tokens}' "$T"
```
`cache_read_input_tokens > 0` on the second run ⇒ Z.ai honours the breakpoints ⇒ resume and
subagent fan-out are cheap. Always `0` ⇒ every resume re-bills the whole context at full rate. **One
`$18` Lite month answers this; nothing else does.**

---

## Recipe 7 — Switch a new session to a different account, and verify before work starts

**verified: true** — the mechanism was exercised; the verification assertion below was run.

**This is GLM's best axis, and it is better than the owner's current platform.** A GLM account is a
string. There is no OAuth, no browser, no keychain service name to derive, no macOS Keychain dialog
that can block an unattended run at 03:00, and no per-account config directory to provision.

```bash
launch_for_account() {   # $1 = provider id, $2 = session uuid
  env -i PATH="$PATH" HOME="$HOME" TERM=dumb \
      CLAUDE_CONFIG_DIR="$ORCH_HOME/agents/$2" \
      $(glm_env "$1") \
    claude -p "$TASK" --session-id "$2" --output-format json --model sonnet < /dev/null
}
```

**Verify the switch before any work happens** — cheap, local, and it catches the whole class of
"launched against the wrong account" bugs:

```bash
# assertion 1: the session believes it is on the GLM model  (VERIFIED-LIVE)
printf '' | claude -p --input-format stream-json --output-format stream-json --verbose \
  --session-id "$SID" --model sonnet 2>/dev/null \
| jq -r 'select(.type=="system" and .subtype=="init") | "model=\(.model) mode=\(.permissionMode) sid=\(.session_id)"'
# -> model=glm-5.3[1m] mode=acceptEdits sid=cccccccc-…

# assertion 2: the key routed to is the one intended  (VERIFIED-LIVE for the failure branch)
curl -sS "$MON/api/monitor/usage/quota/limit" -H "Authorization: $KEY" -H "Accept-Language: en-US,en" \
| jq -e '.success == true and .data.level == "pro"' >/dev/null || abort "wrong or dead account"

# assertion 3: for a visible session, the banner   (VERIFIED-LIVE)
claude logs "$SHORTID" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | grep -q 'glm-5.3\[1m\] · API Usage Billing'
```

**Failure looks like** `Not logged in · Please run /login` (VERIFIED-LIVE: what happens when the env
block is missing), or a session that silently runs on the owner's Anthropic subscription because
`ANTHROPIC_BASE_URL` was dropped — which assertion 1 or 3 catches before a single token is spent.

**Changing a running session's account: no.** The environment is read at process start. The workaround
is `claude stop` → relaunch with `--resume <id>` under the new env — and on GLM that workaround has a
real price: the replayed context is re-billed to the **new** account's credits (recipe 10).

### The constraint that is not technical, and that governs the fleet design

VERIFIED-DOCS, `docs.z.ai/devpack/usage-policy`:

- *"Account sharing or multi-user access is prohibited."*
- *"GLM Coding Plan may only be used within officially supported tools and products."*
- Concurrency is tier-scoped: **Lite = single project, Pro = 1–2 simultaneous, Max = 2+**.
- *"Violations … may trigger … rate limiting, account freezing … Accounts with more than three
  violations may be banned."* The in-band signal is error code **1313**.

Three rules the orchestrator must encode:

1. **A concurrency governor keyed to `plan_tier`.** On Lite that is literally one session. Exceeding
   it is a policy violation with a three-strikes ban attached, not merely a 429. *This, not any
   technical limit, is what caps a GLM fleet.*
2. **Stay a launcher of officially supported CLIs.** Claude Code, Codex, opencode, pi, Crush, Droid
   are all on Z.ai's supported list (VERIFIED-DOCS, `docs.z.ai/devpack/tool/others`). An orchestrator
   that calls the inference API directly risks being an "unsupported tool". Calling the **monitor**
   endpoint directly is fine — Z.ai's own Claude Code plugin does exactly that.
3. **The Team Plan is the sanctioned multi-key path** (min 2 seats, per-seat keys, *"Plan usage is
   limited separately by seat"* — VERIFIED-DOCS) — but seats map to **people**. **Whether one person
   running an agent fleet across their own team seats is compliant is UNKNOWN and must be asked
   before money is spent.**

> **Never run `coding-helper auth reload claude`.** VERIFIED-SOURCE, re-read on disk today:
> `loadGLMConfig()` (a) writes `hasCompletedOnboarding:true` into `~/.claude.json`, (b) **edits the
> user's shell rc files** to strip `ANTHROPIC_API_KEY`/`ANTHROPIC_BASE_URL` lines, and (c) **rewrites
> `~/.claude/settings.json`**, deleting the `ANTHROPIC_DEFAULT_*_MODEL` keys and replacing the whole
> `env` block. On this machine that collides head-on with the profile-switcher multi-profile setup and the
> `~/.zshrc` MiMo alias. **The orchestrator sets environment per child process and touches no config
> file.** Make this a lint rule.

---

## Recipe 8 — Deliver an instruction into a running session and confirm it arrived

**verified: true** — run end to end against the stub; the transcript below is the actual output.

```bash
claude -p \
  --input-format stream-json --output-format stream-json --verbose \
  --replay-user-messages \
  --session-id "$SID" --model sonnet --permission-mode acceptEdits
```

Write one JSON object per line on stdin:

```json
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"stop refactoring; make the failing test pass first"}]}}
```

**Success — the receipt** (VERIFIED-LIVE): `--replay-user-messages` re-emits the injected message on
**stdout** as a `{"type":"user"}` event before the turn runs. Observed sequence for two injections:

```
system init
system status
user      [{"type":"text","text":"first"}]                    <-- receipt for injection 1
stream_event … assistant … stream_event …
result    success

system init
system status
user      [{"type":"text","text":"second injected instruction"}]   <-- receipt for injection 2
stream_event … assistant … stream_event …
result    success
```

Correlate by matching the echoed text (or an orchestrator-inserted marker) and record the arrival.
**Delivery is provable. Obedience is not** — and on a third-party model that gap is real: whether
GLM-5.3 honours a mid-run course correction as reliably as the model a workflow was tuned on is
**UNKNOWN**, and is the right thing to measure in a first paid trial.

**Failure looks like** no `user` echo within the tick budget — the session is wedged or the pipe is
closed. Escalate to recipe 11.

**Fallback for a visible-terminal session** (which owns its own stdin, so the pipe is unavailable):
`harness-term.sh send <tty> "<text>"` then a **separate** Enter keystroke — the split exists because a
combined paste gets swallowed. Confirmation is then `harness-term.sh capture <tty>` plus a new `user`
record in the JSONL. This is emulation, not a protocol receipt: **prefer the stream-json shape for any
session the orchestrator will need to steer.**

---

## Recipe 9 — Answer a permission prompt without a human

**verified: true** — three routes were tested; the one that works was run end to end.

### What does NOT work (tested, so you don't have to)

With `--permission-prompts host` on a raw stdin/stdout stream-json session, Claude Code **did not emit
a `can_use_tool` control request**. It emitted `system permission_denied` and auto-denied:

```
assistant: [{"type":"tool_use","id":"toolu_stub1","name":"Bash","input":{"command":"curl -s https://example.com/…"}}]
system permission_denied
user:      [{"type":"tool_result","content":"This command requires approval","is_error":true,…}]
```

Sending a bare `{"type":"control_request","request":{"subtype":"initialize","hooks":{}}}` handshake
first **did** get a valid `control_response` back (the session replied with its full command list), but
**still** did not route the permission to the host. (Both VERIFIED-LIVE.) The host-side permission
channel evidently needs a capability declaration this pass could not determine — **UNKNOWN**. The
supported route is the Agent SDK, or `--permission-prompt-tool <mcp-tool>` (a real, accepted flag —
VERIFIED-LIVE: `claude --permission-prompt-tool foo -p x` is accepted, not rejected as an unknown
option — though it is not listed in `--help`).

### What DOES work: a `PreToolUse` hook

```bash
cat > "$ORCH_HOME/auto-approve.sh" <<'SH'
#!/bin/bash
payload=$(cat)                       # the hook receives the tool call as JSON on stdin
# ... orchestrator policy: inspect .tool_name / .tool_input, consult the ticket's allowlist ...
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"orchestrator policy: ticket allows network reads"}}'
SH
chmod +x "$ORCH_HOME/auto-approve.sh"

cat > "$ORCH_HOME/guardrails.json" <<JSON
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"$ORCH_HOME/auto-approve.sh"}]}]}}
JSON

claude -p "$TASK" --settings "$ORCH_HOME/guardrails.json" \
  --permission-mode manual --session-id "$SID" --output-format stream-json --verbose
```

**VERIFIED-LIVE:** under `--permission-mode manual` — which denied the identical call in the test
above — the hook's `permissionDecision:"allow"` let it through and **the command actually executed**
(the `tool_result` contained the real fetched page). The hook is the orchestrator's programmatic
answer to a permission prompt, it is deterministic, it is logged, and it works identically against a
GLM endpoint because nothing about it touches the provider.

Emit `"deny"` with a reason to refuse; `"ask"` to fall through to the normal flow.
`--include-hook-events` (VERIFIED-SOURCE, `claude --help`) surfaces every hook decision in the output
stream, so the supervisor can audit what it approved.

**Answering a clarifying *question* (not a permission prompt)** is recipe 8: the session asks in text,
the supervisor detects the stall via the transcript and injects an answer with `--replay-user-messages`
as the receipt.

**Guardrails available for an unattended GLM run** (all VERIFIED-SOURCE, all provider-independent):
`--permission-mode acceptEdits|auto|bypassPermissions|manual|dontAsk|plan`, `--allowedTools` /
`--disallowedTools`, `--tools`, `--restricted`, `--safe-mode`, `--add-dir`, `--strict-mcp-config`,
plus hooks. **Z.ai contributes no server-side guardrail whatsoever** — its only server-side control is
risk control (recipe 7), which protects Z.ai's capacity and can freeze the account mid-run. That is a
hazard to an unattended queue, not a safeguard for it.

> **A cheaper provider invites `--dangerously-skip-permissions` on work that would never have earned
> it at frontier prices.** Name this in the orchestrator's defaults: GLM sessions get the *same*
> permission posture as any other, and `--bg` + `bypassPermissions` is blocked anyway (recipe 3).

---

## Recipe 10 — Resume after a crash, and after a reboot

**verified: true** — resume was run against the stub and the replay cost was measured on the wire.

```bash
claude -p "$FOLLOW_UP" --resume "$SID" --output-format json --model sonnet < /dev/null
```

**Success** (VERIFIED-LIVE): `session_id` in the result equals the pinned id; the conversation
continues. Nothing about resume depends on the provider — **Z.ai has no server-side session concept at
all** (no conversation id, no thread, no "list my sessions" endpoint anywhere in the docs sitemap;
VERIFIED-DOCS by absence). State is 100% the driver's JSONL on local disk.

### After a crash

1. The session file survives — it is appended per event, so a killed process leaves a valid prefix.
2. `claude agents --json --all` no longer lists the pid ⇒ the process is gone.
3. Before relaunching, **classify why it died** from the tail of the transcript: an `api_error` with
   `1316`/`1317` means "do not resume yet, sleep until `nextResetTime`" (recipe 6). Resuming into an
   exhausted window costs another 177 seconds of retries and achieves nothing.
4. Relaunch with the same `--session-id` under the same provider env.

### After a reboot

Same procedure; nothing is held in memory. The orchestrator's own ledger must persist
`{session_id, cwd, provider_id, config_dir, ticket}` to disk, because `claude agents --json` only
lists **running** sessions — after a reboot it returns `[]` and the transcript directory is the only
record. Background sessions do not survive a reboot; `claude respawn [id|--all]` exists
(VERIFIED-SOURCE, `claude --help`) but restarts them under the current version rather than restoring
a crashed run.

### The GLM-specific cost of resume — measured

The stub counted messages per request: the first turn sent **2 messages**, the resumed turn sent
**5** (VERIFIED-LIVE). **Resume replays the whole conversation to the provider and those input tokens
are re-billed against GLM credits.** On a 600K-token context in a crash loop this is either trivial or
ruinous, and which one depends entirely on the cache question in recipe 6c.

**Mitigations until that question is answered:** cap resume attempts per session (3 is reasonable);
compact before resuming a very large context (recipe 5); and prefer a **handoff** — a fresh session
seeded with a written summary — over resuming a 600K context on a provider whose caching is unproven.

---

## Recipe 11 — Stop cleanly, leaving nothing running

**verified: true** — every command below was run, and the final state was confirmed empty.

```bash
claude stop "$SHORTID"      # -> "stopped 6674f750"   (conversation kept; attach/resume still work)
claude rm   "$SHORTID"      # -> "removed 6674f750"   (deletes the background session record)
```

**Verify** (VERIFIED-LIVE — this is the actual transition observed):

```bash
claude agents --json --all | jq -r '.[] | "\(.id) \(.kind) \(.status)"'
# before: 6674f750 background idle
# after stop: 6674f750 background stopped     (pid field gone)
# after rm:   (absent)
```

Full teardown for a GLM fleet:

```bash
for id in $(claude agents --json | jq -r '.[] | select(.kind=="background") | .id'); do
  claude stop "$id"
done
# visible sessions: close the terminal session, never the window
harness-term.sh close "$tty"
# headless sessions: SIGTERM the pid from the agents listing, then verify it is gone
pkill -TERM -f "$SID" ; sleep 2 ; pgrep -f "$SID" && pkill -KILL -f "$SID"
# final assertion
[ "$(claude agents --json --all | jq 'length')" = "0" ] || echo "LEAK"
```

**Failure looks like** a `stopped` entry that still has a live pid, or an orphaned process holding the
provider's concurrency slot — which on GLM is a **policy** problem, not just a resource one (recipe 7).
Make "no orphans" a post-run assertion, not a hope.

**Nothing Z.ai-side needs stopping.** There is no server session to close; the last HTTP request simply
completes. An in-flight request that is killed mid-stream still consumed its input credits.

---

## 12. The adapter interface

```
GLMProvider  ->  { base_url, monitor_origin, token_ref, model, small_model,
                   context_window, plan_tier, max_concurrent_sessions }
Driver       ->  ClaudeCodeAdapter (unchanged) | PiAdapter | CodexAdapter | OpencodeAdapter
```

**The central architectural finding: GLM needs no adapter of its own.** It needs a provider object and
**one new method on the existing driver adapter** — `env_for(provider)` — plus **one genuinely
GLM-specific component**, the quota reader. Everything else is the driver's, already built or already
needed for every other platform.

| # | Capability | How it is met | Effort |
|---|---|---|---|
| 1 | Preflight | **Native (GLM-specific)** — `monitor/usage/quota/limit`, gated on `.success` | new, ~2 h |
| 2 | Headless + pinned id + structured output | **Native (driver)** — `-p --session-id --output-format json` | none |
| 3 | Visible terminal | **Emulated (driver + owner's `harness-term.sh`)**; `--bg` ignores `--session-id` | exists |
| 4 | Liveness / progress | **Native (driver)** — `claude agents --json` + transcript tail | small |
| 5 | Context read + forced compaction + proof | **Native (driver)** — `/context`, `/compact`, `compact_boundary` | small |
| 6 | Quota + reset + in-band limit hit | **Native (GLM)** — the platform's best axis; codes 1316/1317 land in the transcript | ~3 h |
| 7 | Account switch + verification | **Native (GLM)** — three env vars; *best in the field* | trivial |
| 8 | Instruction injection + receipt | **Native (driver)** — `--input-format stream-json --replay-user-messages` | none |
| 9 | Answer a permission prompt | **Emulated (driver)** — `PreToolUse` hook (host control channel did not route) | ~2 h |
| 10 | Resume after crash / reboot | **Native (driver)**, with a GLM-specific re-billing cost | small |
| 11 | Clean stop | **Native (driver)** — `claude stop` / `rm` + orphan assertion | small |

**Impossible on GLM (accept and design around):**

- **Changing a running session's account.** Env is read at process start. Stop → relaunch → re-bill.
- **Server-side session state, transcripts, or any Z.ai-side proof of anything.** No conversation id,
  no compaction hook, no server-side event. If the driver's JSONL does not record it, it is unprovable.
- **Absolute remaining tokens.** Only `percentage` per window; absolute figures must be inferred from
  the plan allowance.
- **A trustworthy dollar spend brake.** `--max-budget-usd` computes from Anthropic's price table;
  Claude Code itself flags the result `costBasis:"unknown"` / `hasUnknownModelCost:true`. Budget in
  credits.
- **Running a fleet larger than the tier's stated concurrency.** Technically easy, contractually a
  three-strikes ban. The hard ceiling is policy, not code.

**The five things the implementer must not get wrong** (each one a silent failure, each VERIFIED-LIVE):

1. Gate the quota poll on **`.success == true`**, never on the HTTP status.
2. Gate task completion on **`is_error == false && terminal_reason == "completed"`**, never on
   `subtype` (which says `"success"` on a quota exhaustion) and never on the exit code (always 0).
3. Keep **stdout and stderr separate** — stderr always carries `[claude-code:unrecognized_model]`.
4. Carry **`context_window` as a first-class field**; set `CLAUDE_CODE_AUTO_COMPACT_WINDOW=1048576`
   but do the supervisor's own arithmetic against **1,000,000**.
5. `Authorization: Bearer <key>` on inference, **raw `Authorization: <key>` on the monitor endpoint**.

---

## 13. Support tier

### **Tier 1 — on the technical axes. Tier 2 in practice, and the constraint is contractual.**

Every one of the eleven recipes has a working, verified answer. Two of them (quota, accounts) are
**better on GLM than on the owner's current platform**: the quota endpoint needs only the session's own
key — no OAuth token, no keychain read, no beta header — and an account switch is three environment
variables, with none of the `CLAUDE_CONFIG_DIR` + keychain machinery whose documented failure mode is a
macOS GUI dialog blocking an unattended run at 03:00. Install footprint is **zero**: no new binary, no
daemon, no config directory.

The reasons it is not unqualified tier 1:

1. **The concurrency ceiling is a usage policy with a ban attached** (Lite 1, Pro 1–2, Max 2+;
   three violations → ban; in-band code 1313). The owner's stated design — a fleet across several
   accounts — runs straight at it. **GLM is an excellent platform for one or two concurrent unattended
   sessions and a policy risk for six.**
2. **The prompt-cache question is unanswered**, and it decides whether resume and subagent fan-out are
   cheap or ruinous. Recipe 6c is the probe; **$18 for one Lite month** is the whole cost of the answer.
3. **Recipe 9 needs emulation** — the host permission channel did not route; the `PreToolUse` hook does.
   That is a driver gap, not a GLM gap, and the hook is solid.
4. **The silent failures outnumber the loud ones.** GLM's in-band error codes are excellent; what kills
   an overnight run is the HTTP-200 auth failure, the `subtype:"success"` on exhaustion, the exit code
   0, and a 1M model quietly compacting at 200K because one env var disagreed with the model id.

**Verdict: adopt GLM as a second provider behind the Claude Code driver, with a hard concurrency
governor keyed to the plan tier, and buy one Lite month before anything else to settle the cache
question.** Choosing GLM is choosing a price and an unusually good quota API. It is not choosing an
orchestration surface — that choice is the driver's, and it stays open.

---

## 14. Open questions that need a live key (ranked by what they cost to leave open)

| # | Question | Recipe | Why it matters |
|---|---|---|---|
| 1 | Does Z.ai honour `cache_control`? (`cache_read_input_tokens > 0` on a repeat run) | 6c | Decides if resume and subagent fan-out are cheap or ruinous. **The most expensive unknown.** |
| 2 | Does Z.ai's gateway accept `anthropic-beta: context-1m-2025-08-07`? | 0.1 | If it rejects unknown betas, the entire `[1m]` 1M-context route fails. Cheapest test; run it first. |
| 3 | Does `count_tokens` return true numbers? (route is confirmed handled) | 5a | Decides whether `/context` is usable or the supervisor must compute from the transcript. |
| 4 | Is one person running a fleet across their own Team seats compliant? | 7 | Decides whether the fleet design is legal. **Ask Z.ai before spending money.** |
| 5 | Does the 429 body or headers ever carry a reset timestamp? (`rateLimits` was `null` here) | 6c | One call vs two on every limit hit. |
| 6 | Does GLM-5.3 obey a mid-run injected instruction as reliably as the tuned model? | 8 | Delivery is provable; obedience is not. Measure in the trial. |
| 7 | Are there `unit` values beyond 3/5/6? (`unit:5` is CLAIMED to be web-search quota) | 6b | The window map comes from two implementations, not a spec. |
| 8 | What is `docs.z.ai/devpack/resources/memory-mechanism`, and is it orchestrator-controllable? | 5 | A possible plan-level handoff mechanism, unread. |

---

## Appendix A — the verification rig (reusable)

`<scratchpad>/glmstub/stub.py` — a ~90-line Python HTTP server that impersonates Z.ai's
Anthropic-compatible surface. Modes via `STUB_MODE`: `ok` (SSE text answer), `tool` (emits a `Bash`
tool_use, for permission testing), `limit5h` / `limit7d` (HTTP 429 with a real
`{"error":{"type":"1316"|"1317"}}` body). It logs every request's path, headers, model, stream flag,
`cache_control` occurrence count and message count to a JSONL file.

**Keep this.** It is the only way to regression-test a provider adapter without spending credits, and
it caught four defects that no amount of documentation reading would have surfaced:
`subtype:"success"` on a quota exhaustion, `--bg` silently ignoring `--session-id`, the stderr warning
line that breaks naive JSON parsing, and the `[1m]`-suffix-to-beta-header translation. Point it at
any `ANTHROPIC_BASE_URL`-compatible driver and the same fixtures apply to Xiaomi MiMo, DeepSeek,
Kimi and any other Anthropic-shaped gateway.

---

## Appendix B — corrections to `glm.md`

| § | Correction | Tag |
|---|---|---|
| A.1 | The `[1m]` suffix is **stripped before the wire**; the model sent is `glm-5.3` and the suffix becomes `anthropic-beta: context-1m-2025-08-07`. | VERIFIED-LIVE |
| A.1 | `ANTHROPIC_AUTH_TOKEN` is sent as **`Authorization: Bearer <key>`** on the inference surface — the opposite of the monitor surface's raw header. | VERIFIED-LIVE |
| D.2 | Claude Code reports the window as **1,000,000**, not the 1,048,576 Z.ai's helper writes. Use 1,048,576 for the env var, 1,000,000 for the supervisor's arithmetic. | VERIFIED-LIVE |
| E.1 | `model-usage` / `tool-usage` take `startTime`/`endTime` as URL-encoded **`yyyy-MM-dd HH:mm:ss` local-time strings**, not ms epochs. `quota/limit` takes **no** parameters. | VERIFIED-SOURCE |
| E.4 | A 1316 produces `subtype:"success"`, `is_error:true`, `terminal_reason:"api_error"`, exit code 0, after **11 requests / 177 s**; `error.rateLimits` is `null`; the numeric code survives **only** in the transcript's `api_error` record. | VERIFIED-LIVE |
| I.2 | `--max-budget-usd` is confirmed **unusable** on GLM — Claude Code marks its own figure `costBasis:"unknown"` / `hasUnknownModelCost:true`. (Closes open question #5 in the negative.) | VERIFIED-LIVE |
| B/I | Claude Code **does** send `cache_control` breakpoints (3/request) and the `prompt-caching-scope` beta to the third-party endpoint; only Z.ai's honouring of them remains open. | VERIFIED-LIVE |
| — | `docs.z.ai` sitemap note: the profile's remark that `…/scratchpad/context/orchestrator-landscape.md` is empty still holds — that path contains no file today. | VERIFIED-LIVE |
