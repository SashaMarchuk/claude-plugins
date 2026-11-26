# DeepSeek — the implementer's spike

**Date:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0, arm64), Node v22.18.0, zsh.
**Pinned artifact:** `@deepseek-ai/dsh@0.1.5-rc.2` (`latest` on npm; `alpha` is 0.1.6-alpha.2).
**Companion:** `deepseek.md` in this directory is the capability profile — read it for *why*. This
document is *how*: the commands, paths and payloads an implementer runs.

**Evidence tags.** **[V]** — run on this machine today, or read in the installed source at the
pinned version. **[C]** — vendor docs or README only. **[U]** — could not establish.

**What was actually exercised here.** The sandbox from the profile pass survives at
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/dshbox`
with `DSH_HOME=<that>/dshhome`. Every `[V]`-tagged command below was run against it: the ACP server
and the SDK server were booted, sessions were created under both, a session was killed with
`SIGKILL` and resumed from a fresh process, a custom profile was composed and patched, and the
durable log was read off disk in both encodings. **No API key exists on this machine, so no model
call ever succeeded and no money was spent** — every recipe that needs a live provider is marked
as such and says exactly what it would return. Nothing under `~/.dsh`, `~/.claude`, `~/.codex` was
created or modified; `~/.dsh` still does not exist.

---

## 0. Decide the lane before writing any code

DeepSeek is three things and the adapter is different for each. Pick per role, not per project.

| Lane | What it is | Adapter cost | Use it for |
|---|---|---|---|
| **A — API behind Claude Code** | `ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic` + the existing Claude Code adapter | **Zero.** Three env vars. | Today. The overflow lane when the Claude window is blocked. |
| **B — `dsh --profile sdk`** | DeepSeek's own stdio JSON-RPC runtime | Medium. ~200 lines of JSON-RPC client. | **Client-named session ids** and **queued follow-ups into a running session**. |
| **C — `dsh --profile acp`** | Agent Client Protocol v1 over stdio | Medium, and **reusable** — ACP is a standard. | **Answering permission prompts in-protocol**, **`usage_update`**, **`session/list` + `session/resume`**. |

**The finding that shapes the whole adapter: B and C are complementary and mutually exclusive.**
One `dsh` process serves one protocol — both own stdout exclusively. Neither protocol is a superset
of the other:

| Capability | B (`sdk`) | C (`acp`) |
|---|---|---|
| Client chooses the session id | **yes** [V] | no — server mints `randomUUID()` [V] |
| List sessions | no method [V] | `session/list` [V] |
| Resume a session | implicit, by reusing the id in the same process [V] | `session/resume`, across processes, after a crash [V] |
| Queue a message into a **running** session | **yes** — inbox accepts it, returns `{messageId}` [V] | **no** — `-32602 "a prompt is already in flight for this session"` [V] |
| Answer a permission prompt | **no answerer is mounted at all** [V] | **yes** — server calls `session/request_permission` on the client [V] |
| Pushed context occupancy | raw facts only: `request/context.contextWindow` + per-event usage [V] | cooked: `usage_update { used, size }` [V] |
| Cancel | no method [V] | `session/cancel` **notification** [V] |
| Answer a clarifying question | no channel [V] | `elicitation` is on the unsupported list [C] |

**Recommended composition:** run role sessions on **C (ACP)** and accept that steering means
"cancel, then prompt again". Use **B (SDK)** only where a client-chosen id is worth losing the
permission channel — and then you *must* run `DSH_PERMISSION_MODE=danger-full-access`, because the
`sdk` profile mounts no approval answerer and `ask` fails **closed** (see §9).

---

## 1. Preflight — installed, authenticated, which account

### 1.1 Is anything there at all

```sh
command -v dsh || echo absent          # [V] → absent on this machine
ls -d ~/.dsh 2>/dev/null || echo "no harness home"   # [V] → no harness home
env | grep -E '^DEEPSEEK_|^DSH_' || echo "no deepseek env"   # [V] → none
```

### 1.2 Install, pinned, into a role-owned prefix — never `latest`

```sh
ROLE=executor
export DSH_HOME="$HOME/.dsh-accounts/$ROLE"
mkdir -p "$HOME/.dsh-accounts/$ROLE" "$HOME/opt/dsh-0.1.5-rc.2"
cd "$HOME/opt/dsh-0.1.5-rc.2" && npm init -y >/dev/null
npm i @deepseek-ai/dsh@0.1.5-rc.2          # 522 packages, ~59 s in a clean sandbox [V, prior pass]
DSH="$HOME/opt/dsh-0.1.5-rc.2/node_modules/.bin/dsh"
```

* **Success:** `"$DSH" --version` prints `0.1.5-rc.2`. [V]
* **Failure:** `EBADENGINE` warnings from `@earendil-works/pi-ai@0.85.1` wanting Node `>=22.19.0`
  are **non-fatal** — it installed and ran on v22.18.0 here. [V]
* **Never** `npm i @deepseek-ai/dsh` unpinned: 22 published versions in 38 days, every one an
  `-rc`/`-alpha`, README promises compatibility-breaking changes. [V, npm]

### 1.3 Assert the composed configuration before you ever launch a task

This is the single best preflight primitive on this platform and most CLIs have no equivalent.

```sh
DSH_HOME="$HOME/.dsh-accounts/$ROLE" "$DSH" --profile acp --dump-config
```

* **Success:** 348 lines of composed plugin tree on stdout, exit 0, **in 0.07 s from a completely
  cold `DSH_HOME`** (it materialises `$DSH_HOME/profiles/acp` as a side effect and runs nothing).
  [V — timed here, `rc=0 lines=348 elapsed 0.07s`]
* Assert on it. The rows that matter, verbatim from the dump here [V]:

```yaml
- id: agent-default-model
  config: {provider: deepseek-official, model: deepseek-flash}
- id: session-persistence-jsonl
  config: {root: !!js dshHomePath('sessions')}          # → $DSH_HOME/sessions
- id: sandbox-policy
  config: {mode: !!js process.env.DSH_PERMISSION_MODE ?? 'workspace-write'}
- id: approval
  config: {policy: !!js "(process.env.DSH_PERMISSION_MODE ?? 'workspace-write') === 'danger-full-access' ? 'never' : 'ask'"}
- id: token-meter        # REQUIRED for usage_update; assert it is present
- id: compaction-basic   # no config → thresholdRatio 0.8, retainRatio 0.16
- id: acp
  config: {provider: deepseek-official, model: deepseek-v4-flash}
```

* **`--dump-default-config`** prints the same tree **without** the user layer or `--patch` overlays
  — diff the two to prove your overlay is the only difference. [V, `--help`]
* **Trap [V]:** `agent-default-model` says `deepseek-flash` but the `acp` plugin says
  `deepseek-v4-flash`. **These are different models.** The ACP session's effective default is
  `deepseek-v4-flash`.
* **Trap [V]:** `dsh-skill-filesystem` is mounted and its default roots include
  `$DSH_AGENTS_HOME` or **`~/.agents/skills`**. On this machine that directory exists and a booted
  SDK session's own `system-reminder` listed the owner's real skills (`find-skills`, …) — an
  unattended `dsh` role **silently inherits the owner's cross-agent skill catalog and pays its
  prompt-token cost**. Set `includeDefaultRoots: false` (or an explicit `customSkillDirs`) in the
  role patch unless you want that.

### 1.4 Which account is active

There is **no `whoami`**. An account is an API key, and the key is resolved per request. Three
resolution layers, launch environment highest [C, `dsh-credentials-local`]:

```
launch environment  >  $DSH_HOME/.credentials.yaml  >  project .env  >  harness-home .env
```

The env var name is **`DEEPSEEK_API_KEY`** (default of `apiKeyEnv`, overridable per profile),
and `DEEPSEEK_BASE_URL` overrides the endpoint. [V — read in `dsh-llm-deepseek` config schema; and
the exact string appears in the live error in §1.5]

```sh
# Which key would THIS launch use, without launching anything:
printf 'env=%s  file=%s\n' \
  "${DEEPSEEK_API_KEY:+set(${#DEEPSEEK_API_KEY} chars, ...${DEEPSEEK_API_KEY: -4})}" \
  "$( [ -f "$DSH_HOME/.credentials.yaml" ] && echo present || echo absent )"
```

### 1.5 Is that key actually good, and whose is it

```sh
curl -sS --max-time 20 -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
     https://api.deepseek.com/user/balance
```

* **Success [C, schema]:** `{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"}]}`
* **Failure, bogus key [V — run here]:** HTTP 401, JSON
  `{"error":{"message":"Authentication Fails, Your api key: ****0000 is invalid","type":"authentication_error","param":null,"code":"invalid_request_error"}}`
* **Failure, header omitted entirely [V — run here]:** HTTP 401 with a **plain-text** body
  `Authentication Fails (governor)`. **Your parser must survive a non-JSON 401.**
* **Response headers observed here [V]:** `x-ds-trace-id` (keep it for support), `server: elb`,
  CloudFront `via`. **No `x-ratelimit-*` and no `retry-after` on this response.**
* This endpoint tells you the *balance*, never *which account*. The orchestrator must carry the
  account identity itself, keyed by env-var name or `DSH_HOME` path — there is nothing to read back.

### 1.6 Lane A preflight (Claude Code pointed at DeepSeek)

```sh
export ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
export ANTHROPIC_AUTH_TOKEN="$DEEPSEEK_API_KEY"
export ANTHROPIC_MODEL=deepseek-flash[1m]
export ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-flash[1m]
export ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-flash[1m]
export ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-flash
export CLAUDE_CODE_SUBAGENT_MODEL=deepseek-flash
export CLAUDE_CODE_EFFORT_LEVEL=max
export CLAUDE_CODE_AUTO_COMPACT_WINDOW=786432
```
[C — DeepSeek's own `quick_start/agent_integrations/claude_code` page]

* **Trap [C]:** an unsupported model name **silently maps to `deepseek-flash`** on the Anthropic
  endpoint. A typo is a downgrade, not an error. Assert the model in the first response's `usage`,
  do not trust the request.

---

## 2. Start a task headless, with a pinned session id, capturing structured output

### 2.1 What `--profile headless` will and will not do

```sh
DSH_HOME="$HOME/.dsh-accounts/$ROLE" "$DSH" --profile headless "run the tests" \
  1>"$RUN/final.txt" 2>"$RUN/reasoning.log"
```

Its complete option surface, run here [V]:

```
Usage: dsh --profile headless [options] [task...]
Arguments:
  task        the task text; multiple words are joined by spaces
Options:
  -h, --help  show this help
```

* **Success:** exit 0, final assistant text on stdout, prose reasoning on stderr. [C, README]
* **Failure:** exit 1 with `dsh: <code>: <message>` on stderr. [C, README]
* **There is no `--session-id`, no `--resume`, no `--model`, no `--output-format json`.** The only
  knob is the task string. [V — that is the whole help output]
* **Verdict: unusable for a supervised queue.** Use it only for fire-and-forget shell steps.

### 2.2 The real recipe — SDK profile, client-chosen id, structured event stream [V — run here]

Launch:

```sh
DSH_HOME="$HOME/.dsh-accounts/$ROLE" DSH_PERMISSION_MODE=danger-full-access \
  "$DSH" --profile sdk       # stdio JSON-RPC; STDOUT IS THE PROTOCOL
```

Handshake, then prompt under **your** id — newline-delimited JSON on stdin:

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"cwd":"/abs/work/dir","provider":"deepseek-official","model":"deepseek-flash","reasoningEffort":"high"}}
{"jsonrpc":"2.0","id":2,"method":"session/prompt","params":{"sessionId":"ticket-417-executor","contentBlocks":[{"type":"text","text":"<the task>"}]}}
```

Exactly what came back here [V]:

```json
{"jsonrpc":"2.0","id":1,"result":{"serverInfo":{"name":"deepseek-harness-sdk-runtime","version":"0.0.1"}}}
{"jsonrpc":"2.0","id":2,"result":{"messageId":"b4d39c7a-1628-4a90-819b-b3fd763c585b"}}
```

`ticket-417-executor` is not a UUID — **any string works, the server creates the session under it**
(`getOrCreateSession(params.sessionId)`). [V — source, and run here]

The structured output is the notification stream, verbatim shapes captured here [V]:

```json
{"method":"session.status","params":{"sessionId":"ticket-417-executor","status":"running"}}
{"method":"session.event","params":{"sessionId":"…","event":{"type":"turn/start","seq":4,"time":…,"data":{"turn":1}}}}
{"method":"session.event","params":{"sessionId":"…","event":{"type":"request/context","seq":12,"data":{"provider":"deepseek-official","model":"deepseek-flash","contextWindow":1000000,"systemPromptUpdate":"in-history"}}}}
{"method":"session.event","params":{"sessionId":"…","event":{"type":"turn/end","seq":16,"data":{"turn":1,"reason":{"kind":"error","error":{"message":"llm-deepseek: no API key …"}}}}}}
{"method":"session.status","params":{"sessionId":"ticket-417-executor","status":"idle"}}
```

Event `type`s observed on the wire here, in order [V]: `permission/preset`, `sandbox/mode`,
`approval/policy`, `agent/inbox/spliced`, `turn/start`, `step/start`, `system/message`,
`user/message`, `request/header`, `request/context`, `session/title`, `assistant/attempt`,
`step/end`, `turn/end`. Plus `subagent.started {parentSessionId, childSessionId}` and
`subagent.finished {provider, agentId, parentSessionId, childSessionId, status, stopReason,
lastAssistantMessage?}` as their own notifications. [V — source]

* **`{messageId}` means "durably queued", not "answered."** The server states it does not assign an
  assistant message or `turn/end` to a prompt. Correlate by `messageId` against the event stream.
  [C, README + V, the response arrived here *after* `turn/start`]
* **Diagnostics must go to stderr.** Both protocols warn `"stdout is the protocol"`; a composed
  stdout logger breaks the wire. [C]
* **Env knobs the SDK profile reads [V, source]:** `DSH_MAX_TOKENS_AS_SUCCESS` (default `true` —
  a `max-tokens` stop is reported as `status: "ok"`; set `false` if you want it treated as failure).

### 2.3 The ACP variant, when you need list/resume/permissions instead of a chosen id

```json
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}
{"jsonrpc":"2.0","id":2,"method":"session/new","params":{"cwd":"/abs/work/dir","mcpServers":[]}}
{"jsonrpc":"2.0","id":3,"method":"session/prompt","params":{"sessionId":"<returned>","prompt":[{"type":"text","text":"<the task>"}]}}
```

`initialize` returned here, verbatim [V]:

```json
{"protocolVersion":1,"agentInfo":{"name":"deepseek-harness-acp","version":"0.0.1"},
 "agentCapabilities":{"mcpCapabilities":{"http":true},
 "promptCapabilities":{"image":false,"audio":false,"embeddedContext":false},
 "sessionCapabilities":{"close":{},"list":{},"resume":{}}},"authMethods":[]}
```

`session/new` returns `{sessionId, configOptions}` where `configOptions` is the live model and
effort selector [V — captured here]:

```json
{"id":"model","type":"select","currentValue":"[\"deepseek-official\",\"deepseek-v4-flash\"]",
 "options":[{"group":"deepseek-official","options":[
   {"value":"[\"deepseek-official\",\"deepseek-flash\"]","name":"DeepSeek-V41-Flash"},
   {"value":"[\"deepseek-official\",\"deepseek-v4-flash\"]","name":"DeepSeek-V4-Flash"},
   {"value":"[\"deepseek-official\",\"deepseek-v4-pro\"]","name":"DeepSeek-V4-Pro"},
   {"value":"[\"deepseek-official\",\"deepseek-v4-flash-vision-exp\"]","name":"DeepSeek-V4-Flash-Vision-Exp"}]}]}
{"id":"reasoning_effort","type":"select","currentValue":"high",
 "options":[{"value":"off"},{"value":"low"},{"value":"high"},{"value":"max"}]}
```

**Four models are advertised, not two** — `deepseek.md` §0 understates this. [V]
The `model` value is a **JSON-stringified `[provider, model]` pair**; pass it back byte-identical.

* **`session/prompt` settles with `{stopReason}`** after the agent goes idle *and* updates drain.
  Reasons: `end_turn`, `max_tokens`, `cancelled`. [V, source]
* **Sharp edge [V, source]:** the mapping is `completed→end_turn`, `max-tokens→max_tokens`,
  **`aborted→end_turn`**, **`blocked→end_turn`**, `interrupted→cancelled`. A *blocked* turn (hook
  or policy refusal) is indistinguishable from success by `stopReason` alone. A turn that **errors**
  is different — it rejects the JSON-RPC call with `-32603 "Internal error: turn failed: <msg>"`
  rather than resolving. Judge success from `tool_call_update.status` and the durable log, never
  from `end_turn`.

---

## 3. Start the same task in a visible surface the owner can type into

**There is no TUI.** `dsh --profile tui` does not exist — the launcher's own examples mention it but
the profile is absent (`dsh: profile "tui" does not exist`). [V, prior pass] The attachable surface
is a **browser**.

```sh
DSH_HOME="$HOME/.dsh-accounts/$ROLE" "$DSH" web --no-open --host 127.0.0.1 --port 3080
```

Complete flag set, run here [V]:

```
Usage: dsh --profile web [options]
  --host <host>                  bind host
  --no-open                      do not open the Web UI in the default browser
  --port <port>                  listen port; pass 0 to let the OS pick a free one
  --trusted-host <authority...>  extra authority the /api browser-trust fence accepts (repeatable)
```

* **Success:** an HTTP server the owner opens at `http://127.0.0.1:3080`, survives terminal death,
  reachable over SSH port-forward, several sessions in one window.
* **Failure mode for an orchestrator:** `--no-open` is **mandatory** unattended, or every launch
  steals focus with a browser tab.
* **The orchestrator cannot drive it.** `POST /api/<namespace>/<method>` exists but sits behind the
  browser-trust fence and is generated, not a public API. [C, `docs/api-gateway.md`]
* **This breaks the existing iTerm2-osascript launcher entirely.** None of that machinery transfers.

**Fallback that preserves "a terminal I can type into":** run the ACP/SDK process inside a terminal
the owner already owns, and put a thin REPL between them — the orchestrator owns stdin/stdout of
`dsh`, and exposes a named pipe or a tiny TTY the owner types into, which the orchestrator forwards
as `session/prompt`. That is more work than `dsh web` but keeps one attach model across platforms.

**Sharpest caveat for a supervised run:** `dsh web` and `dsh --profile acp` **must not share a
session root**, because a live session's write lease is exclusive (§4.1) — if the owner opens the
web UI on the same `DSH_HOME` and clicks into a session the orchestrator owns, the web side
gets `SessionAlreadyOwnedError`. Give the human surface its own `DSH_HOME`, or accept read-only.

---

## 4. Tell whether the session is alive, working, waiting, or finished — from outside

### 4.1 The best primitive on this platform, and it needs no protocol connection: the write lease

Every live session holds a **non-blocking `flock(2)` on `<session-dir>/session.lock`**, released by
the kernel when the holding process dies — including `SIGKILL`. Readers never touch it. [V — source
`dsh-session-persistence-jsonl/lib/lease`, and proven live here]

```python
# liveness.py — exit 0 = a live writer holds it, exit 1 = nobody does
import fcntl, os, sys
fd = os.open(sys.argv[1], os.O_RDONLY)          # O_RDONLY: never truncate the lock file
try:
    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    fcntl.flock(fd, fcntl.LOCK_UN); print("FREE"); sys.exit(1)
except OSError as e:
    print(f"HELD errno={e.errno}"); sys.exit(0)   # EAGAIN/35 on macOS
finally:
    os.close(fd)
```

Proven here [V]: with one ACP process holding a session, the probe printed
`HELD errno=35 Resource temporarily unavailable`; the two sessions from an exited process printed
`FREE`; after the holder exited, that session flipped to `FREE` too.

* **NEVER delete `session.lock`.** A POSIX lock names an inode, and the harness verifies the locked
  inode is still the file at the path. Removing a live session's lock file **forfeits exclusion**.
  [V, source comment]
* **A wedged-but-alive process keeps the lock forever** — deliberately, there is no expiry. So
  `HELD` means "a process exists", not "work is progressing". Pair it with §4.3.

### 4.2 Find the session directory — glob it, never reconstruct the name

```sh
find "$DSH_HOME/sessions" -maxdepth 2 -type d -name "$SESSION_ID"
```

The layout, confirmed on disk here [V]:

```
$DSH_HOME/sessions/
  --private-tmp-claude-501--Users-sasha-marchuk-…-scratchpad-dswork--/   # slugged cwd
    01a080b1-0fdb-4875-9dee-0a52e06506cd/
      session.v3.jsonl.zstd      # 0.1.5-rc.2 writes v3
      session.lock               # 0 bytes, flock target
```

The slug is lossy (`/` → `-`, and an existing `-` collides). The session id is the directory
basename — glob for it.

### 4.3 Is it *working* — the three honest signals

| Question | Signal | Tag |
|---|---|---|
| Process alive? | `session.lock` flock probe (§4.1) | [V] |
| Agent busy? | SDK `session.status` / ACP internal `agent/status` | [V] |
| Progressing? | `seq` of the last durable record is advancing | [V] |

**`AgentStatus` has exactly two values: `"idle"` and `"running"`.** Read in source:
`get status() { return this.phase.kind === "idle" || this.phase.kind === "maintenance" ? "idle" : "running" }`.
**There is no `"waiting"`.** [V]

That is the axis's real gap: **a session blocked on a permission request reports `running`, and a
session that has finished reports `idle` exactly like one that never started.** The supervisor must
synthesise the four states:

```
alive    = flock(session.lock) == HELD
working  = alive AND last session.status == "running" AND max(seq) advanced in the last N seconds
waiting  = alive AND status == "running" AND seq stalled AND an unanswered session/request_permission
           is outstanding on your ACP connection   (you are the answerer — you know)
finished = last durable record is turn/end, AND status == "idle"
stalled  = alive AND status == "running" AND seq stalled AND no permission request outstanding
```

`seq` is monotonic per session and present on every record [V — `{"type":"turn/start","seq":4,…}`].

### 4.4 Read the durable log from outside — the `zstd` claim in `deepseek.md` is too strong

```sh
zstd -dc "$DIR/session.v3.jsonl.zstd" | tail -5
```

Run here, with the system `zstd` at `/usr/local/bin/zstd` [V]:

```json
{"type":"session","version":3,"id":"01a080b1-…","createdAt":1789824325757,"cwd":"/…/dswork","isSeeded":false,"delegationDepth":0}
{"type":"permission/preset","seq":0,"time":1789824325759,"data":{"preset":"workspace-write"}}
{"type":"sandbox/mode","seq":1,"time":1789824325760,"data":{"mode":"workspace-write"}}
{"type":"approval/policy","seq":2,"time":1789824325760,"data":{"policy":"ask"}}
```

**A plain `zstd -dc` reads the default compressed transcript perfectly, while the writer holds the
lock.** `deepseek.md` §C.2 says "the compressed default must be read through the backend"; that is
the README's wording, and for *polling* it is wrong. What is genuinely true: it is a **frame** stream,
so you cannot `tail -f | jq` it incrementally, and a torn final frame contributes only its complete
decoded records. Poll `zstd -dc | tail`, do not stream it.

* **Success:** JSONL on stdout, one object per durable fact, `seq` monotonic.
* **Failure:** `zstd` exits non-zero on a torn tail — **use the output anyway**, it is the committed
  prefix. Treat non-zero + non-empty output as success.
* **Fallback for true `tail -f`:** §5.3.

---

## 5. Read how full the context is, force a compaction, prove it happened

### 5.1 Read occupancy

**ACP — cooked, pushed, unprompted** [V, source `usageUpdate()`]:

```json
{"method":"session/update","params":{"sessionId":"…","update":{"sessionUpdate":"usage_update","used":412037,"size":1000000}}}
```

`occupancy = used / size`. Emitted alongside every committed assistant message, **but only when all
three hold**: the provider reported `usage`, `session.requestContext().contextWindow` is known, and
the `tokenMeter` service is mounted. A composition missing `dsh-token-meter` is **silently blind and
looks identical to an empty context.** Assert you have received at least one `usage_update` before
you trust "not full". [V, the guard is `if (size === void 0 || meter === void 0) return void 0`]

**SDK — raw facts, you do the division** [V — captured live here]:

```json
{"method":"session.event","params":{"event":{"type":"request/context","seq":12,
  "data":{"provider":"deepseek-official","model":"deepseek-flash","contextWindow":1000000,"systemPromptUpdate":"in-history"}}}}
```

`contextWindow` **is** on the SDK wire — `deepseek.md` implies only ACP exposes occupancy. Pair it
with the usage carried on assistant events. [V]

**Offline, from the log, no protocol connection:** the token meter replays the durable log, is
deterministic and **makes no model calls**; its projections are `tokenUsage`
(`uncachedInputTokens`, `outputTokens`, `cacheReadTokens`, `cacheWriteTokens`), `contextPressure`
(`pressureTokens`, `projectedTokens`, `contextWindow`) and `contextBreakdown`
(`systemTokens`, `toolsTokens`, `messageTokens`). **`projectedTokens` — "what the next request's
prompt would cost" — is the number to gate on for "will this session survive one more step".** [C,
`dsh-token-meter` README]

### 5.2 Trigger compaction from outside — you cannot, and here is the exact reason

| Path | Reachable from a supervisor? |
|---|---|
| Automatic pressure at `thresholdRatio` × window (`agent/pre-step`) | No, but automatic [C] |
| Context-overflow recovery (`agent/request-error`) | No, but automatic [C] |
| `/compact` command | **No — `commands` is on ACP's unsupported list; the SDK surface is only `initialize`/`session/prompt`/`shutdown`** [V] |
| `ctx.compaction.compactNow(agent, signal, commandId)` | No wire method reaches it [V, source] |

Sending `/compact` as prompt text does **not** work — commands are a UI surface; the model sees the
literal string. Do not ship it.

**Four workarounds, in the order I would build them:**

1. **Tune the threshold at composition time** (cheapest, do this now). A `--patch` overlay:

```yaml
- id: compaction-basic
  config:
    thresholdRatio: 0.6        # default 0.8
    retainRatio: 0.16          # default 0.16; mutually exclusive with retainTokens
    summarizationProvider: deepseek-official
    summarizationModel: deepseek-flash      # summarise on the cheap model
    maxTokens: 8192            # default 8192
    compactionRetries: 1
    maxOverflowRetries: 1      # 0 disables overflow recovery
```
[V — field names and defaults read in the generated config catalog; overlay verified to land, §5.4]
**Cost:** the shipped profiles use `patchReload: startup`, so you cannot retune a live session. [V]

2. **Close-and-reseed** (the one I would actually build). Watch `usage_update`; when occupancy
crosses the line, `session/close`, open a fresh session, and seed it with a summary the supervisor
wrote. **Engine-agnostic — works identically on every platform in this scan.**

3. **A custom plugin** exposing `ctx.compaction.compactNow()` as a Remote method. Now you maintain a
plugin against a 0.1.x RC that promises breaking changes. The exact call site is verified
(`dsh-command-compact` does `await ctx.compaction.compactNow(invocation.agent, invocation.signal, invocation.commandId)`) [V], so it is small — but it is a fork of the platform's surface.

4. Nothing else.

### 5.3 Prove compaction happened — three independent channels

The durable bracket is `compaction/start` → `compaction/summary` → `compaction/end`, and even a
**failed** attempt is recorded. [V — event-type strings read in `dsh-compaction-basic/lib/index.js`]

```sh
# A. from the log
zstd -dc "$DIR/session.v3.jsonl.zstd" | grep -c '"type":"compaction/'
# B. from the live stream (SDK): session.event with event.type starting "compaction/"
# C. from stderr: ctx.logger.info emits, verbatim format from source:
#    compaction (pressure): shadowed 42 surface nodes (seqs 118-160, ~91234 tokens)
```
[V — the log line format is read in source; A and B are the event names read in source]

* **Success:** `compaction/summary` present, and the next `usage_update.used` is materially lower.
* **Failure:** `compaction/start` with no `compaction/summary` → the selected history changed, or no
  summarisation model was routable. The command's own failure text: *"Compaction is unavailable
  because this process has an active compaction, or the agent is not idle."* [V, source]
* **Silent no-op:** if nothing can be condensed safely, **nothing is written to the log at all**.
  Absence of `compaction/*` does not distinguish "not needed" from "not possible". [C, README]

### 5.4 The patch mechanics, verified end to end here

```sh
# 1. create a role profile from a shipped template (once)
"$DSH" --profile supervised --from-default-profile acp --dump-config >/dev/null   # exit 0 [V]
# 2. boot with an overlay (repeatable flag)
"$DSH" --profile supervised --patch ~/.dsh-accounts/executor/supervisor.patch.yml
# 3. assert the overlay landed, without running anything
"$DSH" --profile supervised --patch ~/…/supervisor.patch.yml --dump-config | grep -A4 compaction-basic
```

Confirmed on this machine: the overlay is a top-level YAML array of `{id, config}` entries, `!!js`
expressions allowed, and `--dump-config` showed `thresholdRatio: 0.6` / `retainRatio: 0.16` in place.
[V]

---

## 6. Read remaining quota and the reset time; detect a limit hit in band

### 6.1 There is no window. There is money.

```sh
curl -sS --max-time 20 -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
     https://api.deepseek.com/user/balance \
| python3 -c 'import sys,json; d=json.load(sys.stdin); b=d["balance_infos"][0]; \
print(d["is_available"], b["currency"], b["total_balance"], b["granted_balance"], b["topped_up_balance"])'
```

* **`is_available`** — one boolean: *"whether the user's balance is sufficient for API calls."* Gate
  on it. [C, official API reference]
* **`total_balance` = `granted_balance` + `topped_up_balance`**; granted (promotional) balance is
  spent first. [C, pricing page]
* **There is no `resets_at`, because nothing resets.** No rolling five-hour window, no weekly
  window, no token allowance, no plan tier. [C — `get-user-balance` is the *only* usage endpoint in
  the whole API reference]
* **No `x-ratelimit-*` headers were present** on the `/user/balance` response observed here. [V for
  the 401 path; **[U]** for a 200 and for `/chat/completions`]

The only other capacity axis is **concurrency: 2500 in-flight for `deepseek-flash`, 500 for
`deepseek-v4-pro`, per *account* (not per key)**. Multiple keys under one account give you no extra
capacity. Count your own in-flight requests. [C, `quick_start/rate_limit`]

**This forces a design change in the orchestrator, not a DeepSeek-specific hack.** `{utilization,
resets_at}` cannot express `{is_available, total_balance}`. You need a `Capacity` sum type:

```
Capacity = Window { utilization: f64, resets_at: Instant }      # Anthropic-style
         | Credit { available: bool, remaining: Decimal, currency: String }   # DeepSeek, Kimi, GLM, MiniMax, Xiaomi
```
with a policy per variant: **Window → pause until `resets_at`. Credit → top up or switch account, and
never wait, because waiting fixes nothing.** Build it once, now, before the next credit-style
platform lands.

### 6.2 Detect a limit hit in band

Provider HTTP status is normalised to a stable code before it reaches any supervisor. Read in
`dsh-llm-deepseek/lib/index.js` `httpErrorCode()` [V]:

| HTTP | Normalised code | Supervisor action |
|---|---|---|
| 401 / 403 | `AUTH` | Bad key. Stop; do not retry. |
| **402 (matched on the error body)** | **`QUOTA`** | **Hard stop for this account. Switch account or top up. There is no reset.** |
| 429 | `RATE_LIMIT` | Back off; reduce concurrency. `providerRetryAfterMs` is attached when the response carried `retry-after`. |
| 400 + context-overflow text | `CONTEXT_WINDOW_EXCEEDED` | Compaction recovery handles it. |
| 400 / 413 otherwise | `INVALID_REQUEST` | Your bug. |
| ≥ 500 | `SERVER` | Retry. |
| other | `HTTP_<status>` | — |

Also normalised: `EMPTY_RESPONSE` (a terminal stop with zero content blocks — safe to repeat) and
`MISSING_CREDENTIAL`. [V]

The error reaches the supervisor **in band**, with the message intact. Exact live capture of the
no-key case, which travels the identical path a 402 would [V]:

```json
{"type":"turn/end","seq":16,"data":{"turn":1,"reason":{"kind":"error","error":{
  "message":"llm-deepseek: no API key for provider route \"deepseek-official\"; store DEEPSEEK_API_KEY through the credentials service …"}}}}
```
and on ACP the same failure rejects the prompt call:
```json
{"error":{"code":-32603,"message":"Internal error: turn failed: llm-deepseek: no API key for provider route \"deepseek-official\"; …"}}
```

So: **watch `turn/end` with `reason.kind === "error"` (SDK), or a `-32603 turn failed:` rejection
(ACP).** The `LlmError` also carries `status`, `providerRetryAfterMs` and `requestId`. [V, source]

### 6.3 The retry policy — correct a worry in `deepseek.md`

Defaults read in `dsh-llm/lib/index.js` [V]:

```
mode: "normal", maxRetries: 5,
retryableCodes: ["EMPTY_RESPONSE","RATE_LIMIT","SERVER","TIMEOUT","TRANSPORT"],
backoff: { initialDelayMs: 500, maxDelayMs: 10000, jitterRatio: 0.1 }
```

**`QUOTA` and `AUTH` are not in the retryable set.** A 402 is *not* retried by default.
`deepseek.md` §J.4 item 5 warns that retries "quietly drain balance overnight against a 402" — that
is only true if you explicitly set `mode: "always"`, which retries **everything** with no cap.
**Never set `mode: "always"` on an unattended role.** The safe explicit form:

```yaml
- id: llm-deepseek
  config:
    retryPolicy:
      mode: normal
      maxRetries: 3
      retryableCodes: [RATE_LIMIT, SERVER, TIMEOUT, TRANSPORT, EMPTY_RESPONSE]
      backoff: {initialDelayMs: 500, maxDelayMs: 10000, jitterRatio: 0.1}
```
[V — schema keys validated; unknown keys throw `<path>: unknown key "<k>"`; overlay verified to land]

### 6.4 Two capacity-shaped things that are not quota

* **Keep-alive is health, not a stall.** Non-streaming requests return continuous empty lines;
  streaming returns `: keep-alive` SSE comments. **A request that has not started inference after
  10 minutes is closed by the server.** Do not treat keep-alive as a hang; do treat a 10-minute
  silent close as *dropped by the server*, not *hung client*. [C] The adapter's own
  `streamIdleTimeoutMs` defaults to five minutes, so it will usually give up first. [V, schema]
* **Peak/off-peak is a scheduling lever worth real money.** Peak = 01:00–04:00 and 06:00–10:00 UTC
  Mon–Fri; everything else, including all weekend, is half price. A Ukraine overnight run
  (22:00–06:00 local = 19:00–03:00 UTC) overlaps the first peak block by two hours. Front-load
  DeepSeek work before 01:00 UTC. [C, pricing page]
* **Cache discipline is the real cost control.** Cache-hit input is **$0.003/Mtok vs $0.15 cache
  miss — 50:1**, on by default, and `usage` reports `prompt_cache_hit_tokens` /
  `prompt_cache_miss_tokens` per request. **Anything the supervisor injects at the *front* of a
  prompt — a timestamp, a run id, a rotating instruction — destroys the prefix and re-pays 50× for
  the whole transcript. Put supervisor-injected volatile text at the end.** A collapsing hit rate is
  a defect signal you can measure. [C, pricing + `guides/kv_cache`]
* **`deepseek-v4-pro` currently routes to V4.1-Flash at Flash prices** (since 04:00 UTC 2026-09-14,
  until V4.1-Pro ships). **Read price from `usage`, never from the model name.** [C, `news/news260910`]

---

## 7. Switch a new session to a different account, and verify before work starts

### 7.1 Three independent switches, all environment-only — the cleanest axis-F story in the scan

```sh
# (a) whole harness home: profiles + plugins + credentials + session root
DSH_HOME="$HOME/.dsh-accounts/executor-b" "$DSH" --profile acp

# (b) just the key, launch environment has highest precedence
DEEPSEEK_API_KEY="$(pass deepseek/executor-b)" "$DSH" --profile acp

# (c) a per-profile env-var NAME, so one launch environment can hold several accounts
#     --patch: - id: llm-deepseek
#                config: {apiKeyEnv: DEEPSEEK_API_KEY_EXECUTOR_B}
```

* (a) [V — `DSH_HOME` materialises `profiles/`, `.anonymous-user-id`, `sessions/` in the named
  directory, and nothing is written to `~/.dsh`, which still does not exist on this machine]
* (b) [C, `dsh-credentials-local`: *"the launch environment wins, followed by the stored file, the
  project's `.env`, and the harness-home `.env`"*]
* (c) [V — `apiKeyEnv` is a config field defaulting to `DEEPSEEK_API_KEY`; the overlay was verified
  to land in `--dump-config` here]

**No keychain. No derived service name. No GUI "Always Allow" dialog that blocks an unattended run.
No ambient config file a daemon-spawned process might read instead.** Roles are `env -i`-clean.

### 7.2 Verify the switch *before* the task runs

```sh
# 1. the key answers, and has money — costs nothing, spends nothing
DEEPSEEK_API_KEY=$KEY_B curl -sS -H "Authorization: Bearer $KEY_B" \
  https://api.deepseek.com/user/balance | grep -q '"is_available":true' || exit 1
# 2. the composed config points at the intended key name and root
DSH_HOME=$HOME/.dsh-accounts/executor-b "$DSH" --profile supervised --patch $P --dump-config \
  | grep -E 'apiKeyEnv|root:'
# 3. the session root is empty / belongs to this account only
ls "$HOME/.dsh-accounts/executor-b/sessions" 2>/dev/null
```

There is **no post-hoc "who am I"** — the balance call proves the key works and has funds, and the
dump proves which key name would be read. That pair is the whole verification. [V for 2 and 3]

### 7.3 Changing a **running** session's account

**Impossible on every surface.** [V] ACP's `session/set_config_option` changes `model` and
`reasoning_effort` at runtime (verified live, §8.3) — **the credential is not a session config
option**. The SDK binds provider and model at `initialize`, once per process. And `dsh-sdk-app`
states configuration changes require a restart (`patchReload: startup`).

**Workaround that actually works:** `session/close` → relaunch the process with a different
`DSH_HOME`/`DEEPSEEK_API_KEY` → `session/resume` the same `sessionId` from the new process. The log
is durable and the cwd fence is satisfied. **Costs:** one restart; a **cold KV cache on the new
account**, so every subsequent request re-pays cache-*miss* input pricing until prefixes re-persist
(a 50× penalty on input, not a rounding error); and a window in which the session is neither live
nor resumable. [V for the close/resume mechanics, §10; C for the cache cost]

### 7.4 Security note that changes how you lay out homes

`dsh-credentials-local`: *"Only your OS user can read the file, but **agent tool processes run as
that same user**, so this store cannot isolate secrets from the agent."* [C] An unattended session
with bash access can read **every account's key in its `DSH_HOME`**. Therefore: **one `DSH_HOME` per
account, one key per home**, and prefer passing the key in the launch environment of that one
process over storing several in a shared `.credentials.yaml`.

---

## 8. Deliver an instruction into a running session and confirm it arrived

### 8.1 SDK — yes, with a durable receipt [V, run here]

```json
{"jsonrpc":"2.0","id":9,"method":"session/prompt","params":{"sessionId":"ticket-417-executor","contentBlocks":[{"type":"text","text":"stop refactoring and just make the failing test pass"}]}}
```

Proven live: a second `session/prompt` sent to a session **whose first turn was still running** was
accepted, returned `{"messageId":"8291af75-…"}`, and the stream showed it inserted and then claimed
into turn 2 [V]:

```json
{"event":{"type":"agent/inbox/spliced","seq":17,"data":{"target":"next-turn","start":0,"inserted":[{"content":[{"type":"text","text":"second message"}],"source":{"kind":"user"},"role":"user","id":"8291af75-…"}]}}}
{"method":"session.status","params":{"status":"running"}}
{"event":{"type":"turn/start","seq":18,"data":{"turn":2}}}
{"event":{"type":"agent/inbox/spliced","seq":19,"data":{"target":"next-turn","start":0,"removedCount":1,"inserted":[]}}}
```

**This is the structural fix for the current harness's "a nudge that cannot submit stranded text".**
There is no screen, no keystroke, no submit button. Text cannot be stranded because it was never
typed — it goes into a durable inbox with observable splice and claim events.

* **Confirm arrival** in two escalating strengths:
  1. `{messageId}` in the response = durably queued. [V]
  2. `agent/inbox/spliced` with `removedCount: 1` for that message id, followed by `turn/start`
     = **claimed into a specific turn**. That is the strong receipt. [V]
* **Failure:** `session agent was disposed outside the server: <id>` — the session died underneath
  you. [V, source]
* **Precision correction to `deepseek.md` §G.1.** The SDK's `session/prompt` calls
  `agent.followup()`, which is `send(input, "next-turn")`. Mid-turn steering is
  `agent.steer()` → `send(input, "next-step")`, and **no wire method on either protocol reaches
  `steer`.** [V, source] Your instruction lands at the **next turn boundary**, not mid-turn. For an
  urgent stop you must cancel first (§11.1) and then prompt.

### 8.2 ACP — no. One prompt in flight per session.

```
{"error":{"code":-32602,"message":"Invalid params: a prompt is already in flight for this session"}}
```
[V, source `if (this.inflight !== void 0) throw invalidParams$1(...)`]

**Fallback on ACP:** `session/cancel` (notification, §11.1) → wait for the prompt to settle with
`stopReason: "cancelled"` → `session/prompt` with the new instruction. You lose the in-flight step;
the durable log keeps everything committed before the cancel.

### 8.3 What *can* be changed mid-session, on ACP [V — run here]

```json
{"jsonrpc":"2.0","id":3,"method":"session/set_config_option","params":{"sessionId":"…","configId":"model","value":"[\"deepseek-official\",\"deepseek-flash\"]"}}
{"jsonrpc":"2.0","id":4,"method":"session/set_config_option","params":{"sessionId":"…","configId":"reasoning_effort","value":"max"}}
```

Both returned the full `configOptions` with `currentValue` updated. An unknown id is rejected:
`-32602 "Invalid params: unknown session config option: temperature"`. [V]
A prompt snapshots the selection and pins it across every model step of that turn; a concurrent
change applies to the **next** turn. [C]

---

## 9. Answer a permission prompt or a clarifying question without a human

### 9.1 Permission prompts — yes, in protocol, over ACP only

The **server calls the client**. Your ACP client must implement `session/request_permission`:

```json
// agent → client
{"jsonrpc":"2.0","id":7,"method":"session/request_permission","params":{
  "sessionId":"…","toolCall":{"toolCallId":"call_abc"},
  "options":[{"optionId":"allow-once","name":"Allow once","kind":"allow_once"},
             {"optionId":"reject-once","name":"Reject","kind":"reject_once"}]}}
// client → agent
{"jsonrpc":"2.0","id":7,"result":{"outcome":{"outcome":"selected","optionId":"allow-once"}}}
```
[V, source: `conn.request(methods.client.session.requestPermission, params)` and the outcome
handling `outcome.optionId === "allow-once" ? "allowed-once" : "rejected"`]

* **Success:** the tool proceeds; the request and its outcome land in the session's audit log.
* **`{"outcome":{"outcome":"cancelled"}}`** is a third legal answer.
* **Sharp edge:** the only options are **allow-once and reject-once. There is no "allow always."**
  Every gated action pings you. That is fine for a program, but it means the middle ground has to be
  expressed as a **preset**, not as accumulated approvals.

### 9.2 The trap that will bite the first implementer: `never` means *reject*, not *allow*

`DSH_PERMISSION_MODE` (read by the shipped base composition [V, seen in `--dump-config`]) selects
one of three presets:

| `DSH_PERMISSION_MODE` | sandbox | approval policy | What happens unattended |
|---|---|---|---|
| `read-only` | read-only | `ask` | Every write needs an answerer |
| **`workspace-write` (default)** | workspace-write | `ask` | Gated actions need an answerer |
| `danger-full-access` | danger-full-access | **`never`** | Nothing is gated, so nothing asks |

`dsh-user-approval`, verbatim: *"`ask` (the default) delegates to the composed answerers; **`never`
rejects every request deterministically before interactive dispatch**"*, and *"Without a terminal
answerer, requests resolve `unavailable` and fail closed."* [V, README + source]

**Therefore:**
* `--profile sdk` + default `workspace-write` = **every gated action fails closed as `unavailable`**,
  because the SDK profile mounts **no answerer at all** (its patch inserts only `sdk-app-startup`
  and `sdk-jsonrpc-server`) [V]. This is the worst configuration and it is the *default* one.
* `--profile sdk` must run `DSH_PERMISSION_MODE=danger-full-access`. You are trading the permission
  channel for the client-chosen id. Be explicit about that in the role definition.
* `--profile acp` + `workspace-write` + your client as answerer is the only configuration that has
  both guardrails and unattended progress.

**Prove the preset before work starts** — it is the first three durable records of every session
[V, captured here with `DSH_PERMISSION_MODE=danger-full-access`]:

```json
{"type":"permission/preset","seq":0,"data":{"preset":"danger-full-access"}}
{"type":"sandbox/mode","seq":1,"data":{"mode":"danger-full-access"}}
{"type":"approval/policy","seq":2,"data":{"policy":"never"}}
```

### 9.3 Clarifying questions — the one real hole

`ask_user_question` (from `dsh-tool-ask-user`) waits until an answer is accepted, and **if no answer
handler accepts it, the model receives an error**. ACP's unsupported list includes `elicitation`;
the SDK has no question channel. [C + V]

**Good news the profile pass missed: `dsh-tool-ask-user` is not mounted in any shipped profile.**
The composed `acp` plugin list here has `user-questions` (the service) but no `tool-ask-user`, so
the model has no way to ask. [V — full 100-plugin `--dump-config` list inspected]

**Residual hazard [V]:** the shipped system prompt still *mentions* `ask_user_question`
("Resolve discoverable facts by inspection. Use `ask_user_question` only for …"). The model is told
about a tool it does not have. For an unattended role, patch the persona or accept the occasional
wasted step.

**The policy to adopt** is the one DeepSeek's own runtime already uses for child agents: *"Runtime-owned
child agents cannot call this tool and must report unresolved questions in their final result."*
Keep the tool unmounted; require unresolved questions in the final answer; parse them out and
escalate to the owner's queue. [C]

---

## 10. Resume after a crash, and after a reboot

### 10.1 After a crash — proven live, end to end, with `SIGKILL` [V]

Sequence actually executed here: process A created session `5b8c65a5-d8be-4b1f-b00b-166012b2dda1`,
was killed with `SIGKILL`, and a **fresh process B** resumed it.

```json
// B: list — the crashed session is there, newest first
{"jsonrpc":"2.0","id":2,"method":"session/list","params":{"cwd":"/abs/work/dir"}}
→ {"result":{"sessions":[{"sessionId":"5b8c65a5-…","cwd":"/abs/work/dir"}, …]}}

// B: resume
{"jsonrpc":"2.0","id":4,"method":"session/resume","params":{"sessionId":"5b8c65a5-…","cwd":"/abs/work/dir"}}
→ {"result":{"configOptions":[…]}}          // success
```

**The four ways `session/resume` refuses, three of them reproduced live:**

| Refusal | Message | Tag |
|---|---|---|
| Session is live | `-32602 Invalid params: session is already active: <id>` | [V — run here] |
| Unknown / not a root session / a subagent / has a parent | `-32602 Invalid params: session is not resumable: <id>` | [V — run here with a zero UUID] |
| cwd differs by physical-directory identity | `-32602 Invalid params: session cwd does not match: /tmp` | [V — run here] |
| Two orchestrators both driving one session | prevented by the same "already active" fence | [V, source] |

* **Store the `cwd` next to the session id.** A worktree, a symlink, or a moved checkout breaks
  resume. The check is `realpath`-based. [V]
* **`session/list` excludes live sessions** — verified: the session held open by the connection did
  not appear in its own `session/list` result. It is an inventory of **resumable** work, not of
  running work. Combine it with the flock probe (§4.1) for a full picture. [V]
* **Resume does not replay history to the client** — it restores the log without re-emitting old
  updates. To *see* what happened before the crash, read the transcript on disk (§4.4). [C]
* **A mid-turn crash comes back with synthetic closers**, not with the interrupted turn completed.
  The persistence contract: fsync before each append resolves, committed events never rewritten,
  an incomplete final raw line discarded, a torn Zstandard frame contributing only its complete
  decoded records. [C, README — a genuinely engineered crash contract, stronger than most]

### 10.2 After a reboot

Persistence is file-backed under `$DSH_HOME/sessions`, so it survives. **Nothing in `dsh` restarts
anything** — the supervisor owns restart. The boot sequence:

```sh
for ROLE_HOME in "$HOME"/.dsh-accounts/*; do
  # 1. no lock can still be held after a reboot — the kernel released every one
  # 2. relaunch the ACP process for that role
  # 3. session/list --cwd <the role's stored cwd>
  # 4. session/resume each id the orchestrator's own state says was unfinished
done
```

* **Success:** every unfinished session resumes; `session.lock` is `FREE` for all of them before you
  start (the kernel released them on process death) [V — the mechanism is verified; a literal reboot
  was not performed here].
* **Failure:** the stored `cwd` no longer resolves to the same physical directory → `session cwd
  does not match`. Store and re-verify `realpath(cwd)` in the orchestrator's own state.
* **Fallback:** if resume refuses, the transcript is still fully readable (§4.4) — open a fresh
  session and seed it with a summary, which is the same close-and-reseed machinery as §5.2.

### 10.3 SDK-lane resume

There is no `session/resume` method. Reusing the same `sessionId` on `session/prompt` reattaches
through `getOrCreateSession`, and the profile mounts persistence. [V, source] Practically: relaunch
`dsh --profile sdk`, `initialize`, then `session/prompt` with the same client-chosen id. Since **you
chose the id in the first place**, there is nothing to look up — which is precisely why the SDK lane
is attractive despite everything else it lacks.

---

## 11. Stop it cleanly, leaving nothing running

### 11.1 Cancel — and the exact trap [V, reproduced live]

**`session/cancel` is a NOTIFICATION, not a request.** Sent with an `id`, it returns:

```json
{"error":{"code":-32601,"message":"\"Method not found\": session/cancel","data":{"method":"session/cancel"}}}
```

Sent correctly, with **no `id`**, it is accepted silently:

```json
{"jsonrpc":"2.0","method":"session/cancel","params":{"sessionId":"…"}}
```
[V — both forms run here; the SDK registers it via `.onNotification(...)`]

* It cancels the active prompt, **or autonomous work when no ACP prompt exists** [V, source] — so
  you can stop a session grinding on its own, not only one you prompted.
* **Unknown session ids are no-ops** — safe to fire blind during teardown.
* The cancelled prompt settles with `{"stopReason":"cancelled"}`.
* The SDK protocol has **no cancel at all**: `{"error":{"code":-32603,"message":"unknown DeepSeek
  Harness SDK runtime method: session/cancel"}}` [V, run here]. On the SDK lane, stopping means
  `shutdown` or killing the process.

### 11.2 The clean three-step teardown

```
1. session/cancel        (notification, per live session)      → ACP only
2. session/close         (request, per session)                → {"result":{}}         [V]
3. shutdown / close stdin                                       → process exits
```

`session/close` returned `{"result":{}}` here [V]. What it does, from source [V]: cancel the prompt,
drain agent activity to idle, **drain continuable subagent descendants**, flush persistence, dispose
the agent. Failures aggregate into an `AggregateError` naming each stage, e.g.
`"ACP session persistence flush failed"`.

SDK: `{"jsonrpc":"2.0","id":N,"method":"shutdown","params":{}}` → `{"result":{}}` [V, run here].
It disposes server-owned agents, the adapter and every subscription; the surrounding context keeps
running until stdin closes.

### 11.3 Prove nothing is running

```sh
pgrep -fl 'dsh --profile' || echo clean                      # [V — used here]
python3 liveness.py "$DIR/session.lock"   # expect FREE       # [V]
```

* **Success:** no matching process, and every `session.lock` probes `FREE`.
* **Failure:** a `HELD` lock with no matching process is impossible — the kernel releases on process
  death. A `HELD` lock therefore always means a real live process; find it with `lsof "$DIR/session.lock"`.
* **`SIGKILL` is safe** and was exercised here (§10.1): the log keeps its committed prefix and the
  session resumes. Prefer the clean path, but do not fear the kill.
* **Do not delete `session.lock` as cleanup.** §4.1.

---

## 12. The adapter interface, and the tier

### 12.1 The eleven capabilities, per lane

| # | Capability | A — API + Claude Code | B — `dsh sdk` | C — `dsh acp` |
|---|---|---|---|---|
| 1 | Preflight / auth / account | native (existing adapter) | native — `--dump-config` + `/user/balance` | native |
| 2 | Headless + pinned id + structured out | native (`--session-id`, `stream-json`) | **native — client names the id** | emulate: server mints, you record |
| 3 | Visible attachable surface | native (terminal) | **impossible** (stdio is yours) | **impossible** (stdio is yours) — use `dsh web` in a *separate home* |
| 4 | Liveness / working / waiting / finished | native-ish | **emulate**: flock + `session.status` + `seq` | **emulate**: same, plus you know your own outstanding permission requests |
| 5a | Read context fullness | `CLAUDE_CODE_AUTO_COMPACT_WINDOW` only | emulate: `request/context.contextWindow` + usage | **native — `usage_update {used,size}`** |
| 5b | Trigger compaction from outside | partially native (env threshold) | **impossible** → close-and-reseed | **impossible** → close-and-reseed |
| 5c | Prove compaction | emulate | native — `compaction/{start,summary,end}` | native — same |
| 6 | Quota + reset + in-band limit hit | native (`/user/balance`; **no reset exists**) | native — normalised `QUOTA`/`RATE_LIMIT` on `turn/end` | native — same, as a `-32603 turn failed:` |
| 7 | Switch account for a NEW session | **native — one env var** | native — `DSH_HOME` / `DEEPSEEK_API_KEY` / `apiKeyEnv` | native — same |
| 7b | Switch a RUNNING session's account | impossible | impossible → close + relaunch + resume | impossible → close + relaunch + resume |
| 8 | Deliver an instruction mid-run | emulate (type into the TTY) | **native, with a durable claim receipt** | **impossible mid-prompt** → cancel, then prompt |
| 9a | Answer a permission prompt | emulate (`--permission-mode`) | **impossible — no answerer mounted; must run danger-full-access** | **native — `session/request_permission`** |
| 9b | Answer a clarifying question | emulate | impossible → don't mount the tool | impossible (`elicitation` unsupported) → don't mount the tool |
| 10 | Resume after crash / reboot | native | native — same client-chosen id | **native — `session/list` + `session/resume`, proven across `SIGKILL`** |
| 11 | Stop cleanly | native | `shutdown` | `session/cancel` (notification) + `session/close` |

### 12.2 The adapter the orchestrator has to write

```
DeepSeekAdapter (lane C, ACP) implements:
  native   : preflight, quota(Credit), account-switch(new), context-read,
             compaction-proof, resume, permission-answer, stop
  emulate  : session identity (record the minted UUID + realpath(cwd) in orchestrator state),
             liveness (flock + status + seq), instruction delivery (cancel→prompt),
             compaction trigger (close-and-reseed on usage_update)
  impossible: a visible attachable terminal; changing a running session's account;
             answering a clarifying question; triggering /compact
```

Plus two cross-cutting changes that are **not DeepSeek-specific and should be built once, now**:

1. **`Capacity = Window | Credit`** with a policy per variant (§6.1). Kimi, GLM, MiniMax and Xiaomi
   will all be `Credit`.
2. **Close-and-reseed as the platform-independent compaction strategy** (§5.2 workaround 2). It is
   the only one that works everywhere, and building it removes the "trigger compaction from outside"
   requirement from the adapter contract entirely.

### 12.3 Support tier

**Lane A (DeepSeek API behind Claude Code): tier-1, today, with zero engineering.** The existing
adapter, launcher, transcript reader and permission handling all keep working; three environment
variables change; the quota model gets *simpler*. This is the highest value-per-hour move on the
whole DeepSeek surface and it is a configuration change, not a feature.

**Lane C (`dsh --profile acp`): tier-2 — workable with emulation, and worth building the ACP client
for, but not for the owner's overnight queue yet.**
It clears eight of the eleven natively or near-natively, and two of the three gaps (no visible
terminal, no external compaction trigger) are answered by close-and-reseed plus `dsh web` in a
separate home. What holds it at tier-2 rather than tier-1:
* `latest` is a **release candidate** from a repo created five weeks ago, shipping every 2–3 days,
  with a README that says in bold **"THERE WILL BE COMPATIBILITY-BREAKING CHANGES"** and a
  `SAFETY.md` that says it **"has not undergone a security audit and must not be treated as secure
  or production-ready."** [C]
* Two of the owner's stated non-negotiables — trigger compaction from outside, answer the session's
  own question — are **not met**, only worked around.
* Several defaults are **actively wrong for supervision** and must be patched before the first
  unattended run (§13).

**Lane B (`dsh --profile sdk`): tier-3 as shipped — executor-only.** It has the best identity story
in the field and the only real mid-run instruction channel, but it mounts **no permission answerer**,
so it can only run `danger-full-access`, and it has no cancel and no list. Use it where the task is
trusted and the id matters more than the guardrails.

**The defensible position, unchanged from the profile pass and now better evidenced:** adopt the API
today as a cost lane; adopt the **ACP protocol shape** as the orchestrator's session interface
regardless of `dsh` (it is a standard, and it already answers three non-negotiables); leave `dsh`
itself on the watchlist until a stable minor, then re-run this pass.

---

## 13. Pre-launch checklist — the defaults that are wrong for a supervisor

Apply as one `--patch` overlay, assert with `--dump-config`, **before** the first unattended run.

```yaml
# ~/.dsh-accounts/<role>/supervisor.patch.yml   [V — this exact file was composed and dumped here]
- id: session-persistence-jsonl
  config:
    root: !!js dshHomePath('sessions-plain')   # MUST be a SEPARATE root — see below
    compression: none                          # plain JSONL, tail -f-able

- id: compaction-basic
  config:
    thresholdRatio: 0.6                        # default 0.8 — compact earlier for long roles
    retainRatio: 0.16
    summarizationModel: deepseek-flash
    summarizationProvider: deepseek-official

- id: llm-deepseek
  config:
    apiKeyEnv: DEEPSEEK_API_KEY_EXECUTOR
    retryPolicy: {mode: normal, maxRetries: 3,
                  retryableCodes: [RATE_LIMIT, SERVER, TIMEOUT, TRANSPORT, EMPTY_RESPONSE]}

- id: skill-filesystem
  config:
    includeDefaultRoots: false                 # stop inheriting ~/.agents/skills silently
```

| # | Default | Why it is wrong | Discovery cost if you miss it |
|---|---|---|---|
| 1 | `compression: zstd` | Frames, not a stream — no incremental `tail -f`. (It *is* readable with `zstd -dc`, contra `deepseek.md`.) | Low — you see binary |
| 2 | **`compression: none` on an existing root** | **`session/new` fails**: `-32603 … "session artifact \"…/session.v3.jsonl.zstd\" uses .jsonl.zstd, but this backend is configured for compression \"none\"; use a separate root or select the matching compression mode"` [V — reproduced here] | **High — it fails at the first task launch, not at startup or `--dump-config`** |
| 3 | `DSH_PERMISSION_MODE` unset → `workspace-write` + `ask` | On `--profile sdk` there is **no answerer**, so every gated action fails closed as `unavailable` | **High — the session limps, it does not error loudly** |
| 4 | `thresholdRatio: 0.8` | Too late for a long unattended executor, and `patchReload: startup` means you cannot retune live | Medium |
| 5 | `retryPolicy` omitted → normal/5 | Fine. **But never set `mode: always`** — it retries everything forever and bills each attempt | Catastrophic if set |
| 6 | `skill-filesystem` default roots | Silently loads `~/.agents/skills`; tokens on every request, and the owner's tools in an unattended role | Medium — invisible without reading `system/message` |
| 7 | `acp` plugin model `deepseek-v4-flash` ≠ `agent-default-model` `deepseek-flash` | Two different models; you may be paying for and reasoning with the one you did not choose | Medium |
| 8 | `session/cancel` sent as a request | `-32601 Method not found` — it is a **notification** | Low but certain |
| 9 | Trusting `stopReason: "end_turn"` | `blocked` and `aborted` both map to `end_turn` | **High — silent false success** |
| 10 | Using `session/list` as a running-work inventory | It **excludes live sessions** | Medium |
| 11 | Unsupported model name on the Anthropic endpoint (lane A) | Silently downgrades to `deepseek-flash` | Medium |
| 12 | Volatile text at the front of a prompt | Destroys the KV prefix; 50× input cost for the whole transcript | **Expensive and invisible** |

---

## 14. Corrections this pass makes to `deepseek.md`

1. **Four models, not two.** `session/new` advertises `deepseek-flash` (DeepSeek-V41-Flash),
   `deepseek-v4-flash` (DeepSeek-V4-Flash), `deepseek-v4-pro`, `deepseek-v4-flash-vision-exp`. The
   `acp` profile's default is **`deepseek-v4-flash`**, not `deepseek-flash`. [V]
2. **The zstd transcript is readable with plain `zstd -dc`** while a writer holds the lock. The
   real constraint is frames-not-stream, i.e. poll rather than `tail -f`. [V]
3. **`compression: 'none'` is not a one-line patch** — it requires a **separate `root`**, and the
   failure appears at `session/new`, not at boot. [V]
4. **`session.lock` exists and is a kernel-arbitrated liveness signal.** Not mentioned in the
   profile's on-disk layout; it is the single best liveness primitive on the platform. [V]
5. **`AgentStatus` is `idle | running` only. There is no `waiting`.** [V]
6. **Neither protocol can reach `steer` (mid-turn).** The SDK's `session/prompt` is `followup`
   (next **turn**). `deepseek.md` §G.1 reads as if mid-turn steering is exposed; it is not. [V]
7. **ACP allows only one prompt in flight per session** — so "deliver an instruction into a running
   session" is an **SDK-only** capability, not a property of `dsh`. [V]
8. **The `sdk` profile mounts no approval answerer**, and `approval: never` means *reject*, not
   *allow*. So the SDK lane is `danger-full-access`-or-broken. [V]
9. **`dsh-tool-ask-user` is not mounted in any shipped profile** — the clarifying-question hazard is
   already mitigated by default; the residual issue is that the persona still mentions the tool. [V]
10. **`QUOTA` and `AUTH` are not in the default retryable set** (`EMPTY_RESPONSE`, `RATE_LIMIT`,
    `SERVER`, `TIMEOUT`, `TRANSPORT`; `maxRetries: 5`). The 402-drains-balance worry applies only to
    an explicit `mode: always`. [V]
11. **`DSH_PERMISSION_MODE` is a real env knob** in the shipped base composition, with three values.
    Not listed among the `DSH_*` variables in §J.2. [V]
12. **The credential env var is `DEEPSEEK_API_KEY`**, configurable per profile via `apiKeyEnv`;
    `DEEPSEEK_BASE_URL` overrides the endpoint. [V]
13. **`session/list` excludes live sessions.** [V]
14. **`--dump-config` costs 0.07 s from a cold `DSH_HOME`** and materialises the profile as a side
    effect — cheap enough to run on every launch as an assertion. [V]
15. **No `x-ratelimit-*` or `retry-after` headers** were observed on `/user/balance`; an
    unauthenticated call returns a **plain-text** 401 body, not JSON. [V]
16. `subagent.finished` is a second subagent notification the profile does not list, carrying
    `status` (`ok`/`error`), `stopReason` and `lastAssistantMessage`. [V]

---

## 15. Evidence log — exactly what was run on this machine, 2026-09-19

All against `@deepseek-ai/dsh@0.1.5-rc.2` in the pre-existing scratchpad sandbox, with
`DSH_HOME` pointed inside it. No API key present; no model call succeeded; no money spent; no owner
configuration read for writing or modified.

* `dsh --version` → `0.1.5-rc.2`; `dsh --help`; `dsh --profile {headless,acp,sdk} --help`;
  `dsh web --help`; `dsh plugin --help`.
* `dsh --profile acp --dump-config` → 348 lines; full composed plugin list inspected
  (100 plugin ids); timed from a cold `DSH_HOME` at **0.07 s**.
* `dsh --profile supervised --from-default-profile acp` → profile created; then
  `--patch supervisor.patch.yml --dump-config` → overlay verified in place for
  `session-persistence-jsonl`, `compaction-basic`, `llm-deepseek`.
* **ACP driven live over stdio**: `initialize`, `session/new`, `session/list`, `session/resume`
  (live / missing / wrong-cwd / after-`SIGKILL`), `session/set_config_option` (model, effort, bogus),
  `session/prompt` (failed at the provider for want of a key), `session/cancel` as request
  (`-32601`) **and** as notification (accepted), `session/close`, plus `session/load`,
  `session/set_mode`, `session/fork`, `session/delete` (all `-32601`).
* **SDK driven live over stdio**: `initialize`, `session/prompt` under the client-chosen id
  `ticket-417-executor`, a **second prompt while the first turn was running** (accepted and claimed
  into turn 2), `shutdown`; the full `session.event` / `session.status` notification stream captured.
* **Crash/resume**: process `SIGKILL`ed mid-session; a fresh process listed and resumed the session.
* **Persistence on disk**: `session.v3.jsonl.zstd` decoded with `/usr/local/bin/zstd -dc`;
  `compression: none` on a separate root produced a plain `session.v3.jsonl` read with `head`.
* **Liveness**: `fcntl.flock(LOCK_EX|LOCK_NB)` on `session.lock` — `HELD errno=35` with a live
  writer, `FREE` without, flipping on process exit.
* **Network, read-only**: `GET https://api.deepseek.com/user/balance` with no key (401, plain text)
  and with a bogus key (401, JSON, no rate-limit headers, `x-ds-trace-id` present).
* **Source read at the pinned version**: `dsh-acp/lib/index.js`, `dsh-sdk-jsonrpc-server/lib/index.js`,
  `dsh-agent-loop/lib/index.js`, `dsh-llm/lib/index.js`, `dsh-llm-deepseek/lib/index.js`,
  `dsh-compaction-basic/lib/index.js`, `dsh-command-compact/lib/index.js`,
  `dsh-session-persistence-jsonl/lib/index.js`, `dsh-skill-filesystem/lib/index.js`,
  `@agentclientprotocol/sdk@1.4.0` `dist/acp.js` + `dist/schema/index.js`; the shipped
  `cordis.patch.yml` of `dsh-base`, `dsh-acp-app`, `dsh-sdk-app`, `dsh-headless`; the generated
  `docs/config-catalog.md`; and the READMEs of `dsh-user-approval`, `dsh-credentials-local`,
  `dsh-session-persistence-jsonl`, `dsh-compaction-basic`, `dsh-agent`.
* **Deliberately not run**: the Codex setup script (it edits `~/.codex`), `dsh web` (it opens a
  browser), any agent task, any billed API request.
