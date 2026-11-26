# GitHub Copilot CLI — orchestrator adapter SPIKE

**Date:** 2026-09-19. **Machine:** owner's Mac, darwin 25.5.0, arm64.
**Binary exercised:** `@github/copilot-darwin-arm64` **1.0.86** (`copilot --version` → `GitHub Copilot CLI 1.0.86.`).
**Companion:** read `copilot-cli.md` (the capability profile) first. This file is the implementer's recipe book and **corrects the profile in five places** (§0.2).

**Evidence tags.** **VERIFIED** = I ran it on this machine in this pass, or read the exact flag in the
installed binary's own `--help`. **CLAIMED** = official docs/changelog only, not run here.
**UNKNOWN** = could not establish.

**What I ran, and what it cost.** Everything below was executed against the 1.0.86 binary already
present at
`…/scratchpad/copilot-sandbox/node_modules/@github/copilot-darwin-arm64/copilot`,
with `COPILOT_HOME` and `HOME` redirected into
`…/scratchpad/cop-spike/`. **The owner's `~/.copilot` was not modified** (re-checked after the run:
still one log file and the Aug-11 `config.json`). **Zero AI credits were spent** — every model call
was refused by GitHub before billing (see §0.1). No long agent run was started.

---

## 0.1 STOP — read this before implementing anything

**The owner's GitHub account has no Copilot entitlement. Copilot CLI cannot execute a task on this
machine today.** VERIFIED, two independent ways:

The runtime pushes the full identity as a `host.event` notification at session creation, with no
authentication step and no model call:

```json
{"method":"host.event","params":{"scope":{"type":"session","sessionId":"…"},"kind":"auth_changed",
 "payload":{"data":{"authInfo":{
   "type":"gh-cli","host":"https://github.com","login":"SashaMarchuk",
   "copilotUser":{
     "login":"SashaMarchuk",
     "access_type_sku":"no_access",        ← no entitlement
     "chat_enabled":false,                 ← no chat
     "assigned_date":null,
     "copilot_plan":"individual",
     "can_signup_for_limited":true,        ← a free tier is available to him
     "is_mcp_enabled":false,
     "cli_remote_control_enabled":false,   ← --remote / --connect will not work
     "cloud_session_storage_enabled":false,
     "organization_list":[],"enterprise_list":[]
   }}},"credentialsChanged":true}}}
```

And every model-touching call is refused server-side:

```
models.list      → -32603  {"kind":"http","status":403,"body":"unauthorized: not authorized to use this Copilot feature"}
copilot -p "…"   → exit 1, stderr: "Error: Access denied by policy settings (Request ID: 08A1:1CB38D:…)"
account.getQuota → {"quotaSnapshots":{}}   ← empty map, NOT an error
```

**Consequences for the implementer:**

1. This profile's open question #6 ("does the owner's `gho_` token carry Copilot entitlement?") is
   now **answered: no.** The token *authenticates* fine — the runtime resolved `login: SashaMarchuk`
   from it — it simply carries no Copilot SKU.
2. **Everything in this spike that does not require a model call is fully verified and working.**
   Session creation, pinning, listing, context reads, quota reads, steering, abort, destroy, resume
   selection, transcript files — all exercised for real, unauthenticated, below.
3. The gate is commercial, not technical: `can_signup_for_limited: true` means Copilot Free is one
   click away at <https://github.com/settings/copilot>. **Until someone clicks it, Copilot CLI is a
   tier-1-capable platform with a tier-unusable account.** Treat that as a procurement decision, not
   an engineering one.
4. **The adapter must not read `{"quotaSnapshots":{}}` as "zero quota remaining".** An empty map
   means *unauthenticated or unentitled*. Conflating the two will make the orchestrator pause a
   healthy queue forever. Distinguish them by `access_type_sku` from `auth_changed`.

---

## 0.2 Corrections to the capability profile

| # | Profile said | Actually (VERIFIED here) |
|---|---|---|
| 1 | The SDK server protocol's framing is unstated; my probe of `--server --stdio` with newline-delimited JSON produced nothing. | It is **LSP-style `Content-Length:` framing**, not newline-delimited. With correct framing every documented RPC answers. This is why the earlier probe looked dead. |
| 2 | "`session/cancel` … whether it works as a notification is UNKNOWN. Do not guess the cancel path." | As a *request* it is `-32601`. As a *notification* it is indistinguishable from a no-op (a deliberately bogus notification behaves identically). **The real cancel is `session.abort` on the SDK plane** → `{"success":true}`. VERIFIED. |
| 3 | "No session locking — the orchestrator owns this." | Still true, **but the platform gives you the signal**: the `session.start` event carries **`alreadyInUse`** (observed `false`). Assert it. |
| 4 | "An orchestrator must verify its permission posture after launch … rather than assuming the flag took." | Correct, and there is a **first-class event** for it: `session.managed_settings_resolved` with `failClosed`, `bypassPermissionsDisabled`, `sandboxEnabledByUndeterminedPolicy`. VERIFIED, full schema in §9. |
| 5 | Lists `COPILOT_ENABLE_INTERRUPTED_SESSION_RESTORE`, `COPILOT_CONNECTION_TOKEN`, `COPILOT_TASK_WAIT_TIMEOUT_SECONDS`, `COPILOT_SUBAGENT_MAX_CONCURRENT`, `COPILOT_LARGE_OUTPUT_THRESHOLD_BYTES`, `COPILOT_SKILLS_DIRS` as VERIFIED from `copilot help environment`. | **None of those six appear in `copilot help environment` at 1.0.86** (grepped; 0 hits each). They are docs/changelog claims. `COPILOT_CONNECTION_TOKEN` is separately **VERIFIED by behaviour** (§7). The rest stay **CLAIMED** — set them, but do not assume they took. |

Also new, and not in the profile at all: **`session/list` and `session/close` over ACP**
(`agentCapabilities.sessionCapabilities: {"close":{},"list":{}}`), and **`session.list`** on the SDK
plane, which enumerates persisted sessions **across processes** — the fleet-enumeration primitive.

---

## 0.3 The two control planes, and which one to use

The same binary speaks **two different protocols on two different flags**, with **two different
framings**. This is the single most important structural fact for the adapter.

| | **ACP plane** | **SDK runtime plane** |
|---|---|---|
| Flag | `copilot --acp --stdio` (or `--acp --port N`) | `copilot --server --stdio` (or `--server --port N`) |
| Visible in `--help`? | yes (`--acp`) | **no — hidden but accepted** (VERIFIED: `--server`, `--stdio`, `--port`, `--worktree`, `--sandbox`, `--no-sandbox`, `--prefer-version` all accepted; `--bogus-flag-xyz` → `error: unexpected argument`) |
| Framing | **newline-delimited JSON** | **`Content-Length: N\r\n\r\n<json>`** |
| Method naming | `session/new`, slash-separated | `session.create`, dot-separated |
| Unknown method | `-32601 "Method not found": X` | `-32601 Unhandled method X` |
| Has quota | **no** (`account/getQuota` → `-32601`) | **yes** (`account.getQuota`) |
| Has context RPCs | no | **yes** (`session.metadata.contextInfo`, `.recomputeContextTokens`) |
| Has cancel | **no** | **yes** (`session.abort`) |
| Standards reuse | open standard, reusable across agents | Copilot-specific |

**Verdict: build the adapter on the SDK runtime plane.** It is a superset for every axis the owner
cares about. The ACP plane is worth a second, thin adapter only if the orchestrator wants one client
shared with other ACP agents — and even then ACP alone forfeits axes D, E and the cancel path.

Everything from §1 onward uses the SDK plane unless stated.

**The 12-line client the rest of this file assumes.** Save as `rpc.mjs`:

```javascript
import { spawn } from 'node:child_process';
export function connect(argv = ['--server','--stdio'], env = process.env) {
  const p = spawn(process.env.COPILOT_BIN, argv, { env, stdio:['pipe','pipe','pipe'] });
  let buf=''; const pending=new Map(); const listeners=[];
  p.stdout.on('data', d => { buf += String(d);
    for(;;){ const h = buf.indexOf('\r\n\r\n'); if (h < 0) break;
      const m = /Content-Length: (\d+)/.exec(buf.slice(0,h)); if (!m) break;
      const start = h+4, len = +m[1]; if (buf.length < start+len) break;
      const o = JSON.parse(buf.slice(start, start+len)); buf = buf.slice(start+len);
      if (o.id !== undefined) pending.get(o.id)?.(o); else listeners.forEach(f => f(o));
    }});
  let id = 0;
  const call = (method, params={}) => new Promise(res => {
    const i = ++id; pending.set(i, res);
    const s = JSON.stringify({jsonrpc:'2.0', id:i, method, params});
    p.stdin.write(`Content-Length: ${Buffer.byteLength(s)}\r\n\r\n${s}`);
  });
  return { call, on: f => listeners.push(f), proc: p };
}
```

---

## 1. Preflight: installed, authenticated, which account?

**Copilot is NOT on this machine's PATH** (VERIFIED: `which copilot` → not found; not in
`npm ls -g`). `~/.copilot/` exists (first launch 2026-08-11) with one process log from a 78-minute
`--server --stdio` run on 2026-09-13, and **no `session-state/`** — no session has ever completed
under the owner's HOME.

### 1a. Install (pin the version — releases are near-daily)

```bash
npm install -g @github/copilot@1.0.86          # or: brew install copilot-cli
export COPILOT_BIN="$(command -v copilot)"
"$COPILOT_BIN" --version                        # → GitHub Copilot CLI 1.0.86.
```

**Success:** a version line. **Failure:** `command not found`. **Footprint:** a 12 KB npm loader plus
a **145 MB** platform binary (`@github/copilot-darwin-arm64`, 149,952,304 bytes).

### 1b. Identity — the real preflight, costs nothing

Do **not** shell out to `gh auth status`; that tells you the GitHub login but nothing about Copilot
entitlement. Create a throwaway session on the SDK plane and read the `auth_changed` push:

```javascript
const rt = connect();
const auth = new Promise(r => rt.on(n => { if (n.method==='host.event' && n.params?.kind==='auth_changed') r(n.params.payload.data.authInfo); }));
await rt.call('session.create', { sessionId: PREFLIGHT_UUID, workingDirectory: '/tmp' });
const a = await auth;
// a.login, a.type ("gh-cli"), a.copilotUser.access_type_sku, .chat_enabled, .copilot_plan
await rt.call('session.destroy', { sessionId: PREFLIGHT_UUID });
```

**Success:** `access_type_sku` is anything other than `"no_access"` **and** `chat_enabled: true`.
**Failure (observed here):** `access_type_sku: "no_access"`, `chat_enabled: false` → the account can
authenticate but cannot run. **Fail the job at preflight rather than at the first model call** — the
latter wastes a session directory and a process spawn per task.

Also gate on `cli_remote_control_enabled` before offering `--remote`, and `is_mcp_enabled` before
wiring third-party MCP: with it false the CLI emits, on every run,
`session.warning` / `warningType: "policy"` — *"Third-party MCP servers are disabled by your
organization's Copilot policy. Only built-in servers are available."* (VERIFIED.)

**Token precedence** (VERIFIED, `copilot login --help` and `copilot help environment`):
`COPILOT_GITHUB_TOKEN` → `GH_TOKEN` → `GITHUB_TOKEN`. Accepted: fine-grained v2 PATs with the
*Copilot Requests* permission, Copilot-CLI OAuth tokens, and **`gh` CLI OAuth tokens (`gho_`)**.
**Classic `ghp_` PATs are not supported.** Non-interactive login: `copilot login --with-token < f`
or `copilot login --device-code`. The env-var route never touches the macOS Keychain — prefer it.

---

## 2. Start a task headless, pinned id, structured output

```bash
SID=$(uuidgen | tr 'A-Z' 'a-z')      # MUST be a real UUID — see the trap below
CI=1 \
COPILOT_HOME="$FLEET/accounts/$ACCOUNT" \
COPILOT_GITHUB_TOKEN="$TOKEN" \
COPILOT_AUTO_UPDATE=false \
copilot -p "$PROMPT" \
  --session-id "$SID" \
  --output-format json \
  --usage-output-file "$RUNDIR/usage.json" \
  --share "$RUNDIR/transcript.md" \
  --allow-tool='shell(git:*)' --allow-tool='write' \
  --deny-tool='shell(git push)' \
  --no-ask-user \
  --max-ai-credits 200 \
  --max-autopilot-continues 10 \
  --no-auto-update \
  -C "$WORKDIR" \
  > "$RUNDIR/events.jsonl" 2> "$RUNDIR/stderr.txt"
echo "exit=$?"
```

Every flag above was read verbatim from the installed 1.0.86 `--help`. `--allow-all-tools` (or
`--allow-all` / `--yolo`) is **required for non-interactive mode** — the help says so verbatim — but
prefer explicit `--allow-tool` patterns; see §9 for why `--yolo` is the wrong unattended posture.

### THE UUID TRAP — VERIFIED, and it will bite

`--session-id` for a **new** session requires a strictly valid RFC 4122 UUID. The variant nibble is
checked:

```
99999999-8888-7777-6666-555555555555  → Error: … "The value is not a valid UUID, so a new session cannot be created."
aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee  → same error
00000000-0000-4000-8000-000000000000  → accepted (valid v4)
$(uuidgen)                            → accepted
```

**And the two planes disagree:** `session.create` over the SDK plane happily accepted
`11111111-2222-3333-4444-555555555555`, which the CLI flag rejects. **Always mint ids with a real
UUIDv4 generator**, never a hand-written hex pattern, or the same id will work through one plane and
fail through the other.

`--session-id` and `--resume` are **hard-rejected together** by the argument parser (VERIFIED):
`error: the argument '--session-id <id>' cannot be used with '--resume [<value>]'`. The docs only
"advise against" it; the binary refuses. Pick one selector.

### The `--output-format json` envelope — VERIFIED (profile open question #1, answered)

One JSON object per line, this shape:

```json
{"type":"session.mcp_server_status_changed",
 "data":{"serverName":"github-mcp-server","status":"connected"},
 "ephemeral":true,
 "id":"cd8940f8-addc-49ba-88f6-94d1b07bb306",
 "timestamp":"2026-09-19T13:33:06.907Z",
 "parentId":"b2836cda-2ea0-4942-9f3b-4ff63dc1390f"}
```

It is **the same envelope** as the `event` field of the SDK plane's `session.event` notification and
the same as each line of `events.jsonl` on disk. **One parser serves all three surfaces.** Note
`ephemeral: true` — those lines are live-only and are not replayed on resume.

**Failure mode to design for (VERIFIED):** a fatal error is **not** in the JSONL. The stream ends
cleanly, the process exits **1**, and the reason is on **stderr** in prose:

```
Error: Access denied by policy settings (Request ID: 08A1:1CB38D:7718D3:B2F481:6AAE8F13)
```

**The adapter must read exit code + stderr, not just the JSONL**, or a failed job looks like a short
successful one.

**`--usage-output-file` is written even on a failed run** (VERIFIED — 381 bytes after an exit-1 run).
Its schema, undocumented on the web (profile open question #2, answered):

```json
{"totalPremiumRequestCost":0,"totalUserRequests":0,"totalNanoAiu":0,"totalApiDurationMs":0,
 "sessionStartTime":"2026-09-19T13:33:04.233Z",
 "codeChanges":{"linesAdded":0,"linesRemoved":0,"filesModifiedCount":0,"filesModified":[]},
 "modelMetrics":{},"agentMetrics":{},"lastCallInputTokens":0,"lastCallOutputTokens":0}
```

`--share` is **not** written when the run fails (VERIFIED — file absent after exit 1). Do not treat
its presence as optional-but-likely; treat its absence as a failure signal.

---

## 3. Start the same task in a visible terminal the owner can type into

`-i, --interactive <prompt>` — *"Start interactive mode and automatically execute this prompt"*
(VERIFIED in the installed `--help`). This is exactly "launch it visible, seed it, let him take
over".

The owner's launcher is already config-resolved — `~/.claude/shared/tooling.json` sets
`terminal_launcher.default: "iterm2-osascript"`, semantics *"tab in the current window when one
exists, else ONE fresh window"*. iTerm2 is installed (`/Applications/iTerm.app`), and **tmux 3.6a**
is on PATH (both VERIFIED). Reuse that launcher; do not hardcode one.

```bash
# via the owner's default launcher (iTerm2), one tab:
osascript -e 'tell application "iTerm2" to tell current window to create tab with default profile' \
          -e "tell application \"iTerm2\" to tell current session of current window to write text \"cd $WORKDIR && COPILOT_HOME=$ACCT copilot -i '$PROMPT' --session-id $SID\""

# or, for a pane the supervisor can also read and write:
tmux new-session -d -s "job-$SID" -c "$WORKDIR" \
  "COPILOT_MULTIPLEXER=tmux COPILOT_HOME=$ACCT copilot -i '$PROMPT' --session-id $SID"
```

**Set `COPILOT_MULTIPLEXER=tmux` explicitly** when launching inside tmux. The CLI's own help warns
that herdr panes inherit the herdr server's `TMUX` and that autodetection guesses wrong there
(VERIFIED, `copilot help environment`).

**Do not use a tmux pane as the control channel.** It is the *human* attach point only. Machine
control goes through §8. The owner's field notes already record a harness nudge that could not submit
stranded text — typing into a screen is the failure mode this platform lets you avoid entirely.

**Overnight:** set `keepAlive` in `settings.json` to `"on"` (or `"busy"`) — *"prevents the system
from sleeping while the session is active"*, default `"off"` (VERIFIED, `copilot help config`). This
is the only platform in the scan that ships its own caffeinate.

**Caveat:** I could not render the TUI in this environment (`script: tcgetattr/ioctl: Operation not
supported on socket`), so the interactive path is verified by flag-read, not by execution.

---

## 4. Is the session alive, working, waiting, or finished — from outside?

**`copilot sessions` has only one subcommand: `import`.** There is **no `copilot sessions list`**
(VERIFIED). Anyone reaching for a CLI listing will not find one. Use these three instead.

### 4a. `session.list` — the fleet enumerator, cross-process, no auth needed

```javascript
await rt.call('session.list', {});
```

VERIFIED output, read by a *separate, later* process than the one that created the session:

```json
{"sessions":[{
  "sessionId":"11111111-2222-3333-4444-555555555555",
  "startTime":"2026-09-19T13:32:19.444Z",
  "modifiedTime":"2026-09-19T13:32:28.455Z",
  "isRemote":false,
  "isDetached":false,
  "summary":"/compact","name":"/compact",
  "clientName":"sdk",
  "context":{"cwd":"…/cop-spike/work"}}]}
```

**`isDetached` is the liveness bit. `modifiedTime` is the progress bit.** A supervisor polls this
every N seconds against `$COPILOT_HOME/session-state/` and needs no handle on the original process.

**Gotcha (VERIFIED):** a session appears in `session.list` only once it has been **persisted** — a
freshly `session.create`d session with no message yet returns an empty list. Do not treat "absent
from list" as "dead" within the first few seconds of launch; treat it as "not yet started".

### 4b. Live event stream — the authoritative state machine

Subscribe to `session.event` notifications (SDK plane) or tail the `--output-format json` stdout.
Observed live on this machine, in order: `session.managed_settings_resolved` → `session.start` →
`pending_messages.modified` → `session.title_changed` → `session.mcp_server_status_changed`
(`pending` → `connected`) → … → `session.shutdown`.

Map to orchestrator states:

| State | Signal |
|---|---|
| starting | `session.start` received, `alreadyInUse` present |
| working | `assistant.turn_start`, `tool.execution_start` (CLAIMED — needs a real turn) |
| **waiting on a human** | `permission.requested` / `user_input.requested` / `elicitation.requested` (CLAIMED) |
| **idle / done** | `session.idle` — the reliable one (CLAIMED); `session.task_complete` is semantic and best-effort |
| finished | `session.shutdown` with `shutdownType` |
| failed | `session.error`, or exit≠0 + stderr |

### 4c. On-disk, zero-RPC fallback

```
$COPILOT_HOME/session-state/<uuid>/
  workspace.yaml              # identity + heartbeat
  events.jsonl                # the transcript, appended per event
  checkpoints/                # one per compaction
  files/  research/  rewind-file-snapshots/
  .workspace-fork.lock
$COPILOT_HOME/session-store.db          # SQLite (+ -wal, -shm)
$COPILOT_HOME/logs/process-<epochms>-<pid>.log
```

VERIFIED `workspace.yaml`:

```yaml
id: 11111111-2222-3333-4444-555555555555
cwd: …/cop-spike/work
client_name: github/cli
name: /compact
user_named: false
summary_count: 0
fork_count: 0
created_at: 2026-09-19T13:32:19.444Z
updated_at: 2026-09-19T13:33:11.644Z
```

`updated_at` and the mtime of `events.jsonl` are a free liveness heartbeat — `stat` is cheaper than
an RPC and works for sessions the orchestrator did not spawn. **`client_name` distinguishes
`github/cli` (a `-p`/TUI run) from `sdk` (a runtime-plane session)** — useful when the fleet mixes
both.

**Failure:** `events.jsonl` absent means no turn ever completed (VERIFIED — the exit-1 run created the
directory and `checkpoints/` but no `events.jsonl`). Directory-exists ≠ work-happened.

---

## 5. Read context fullness, force compaction, prove it

### 5a. Read — three free reads, no model call

```javascript
await rt.call('session.metadata.contextInfo', { sessionId });
await rt.call('session.metadata.recomputeContextTokens', { sessionId });
```

VERIFIED on a fresh session:

```json
{"contextInfo": null}
{"totalTokens":0,"messagesTokenCount":0,"systemTokenCount":0}
```

**`contextInfo` returns `null` until the session has initialised** (system prompt and tool metadata
cached) — the docs warn about this and it reproduces exactly. **`recomputeContextTokens` does not
return null**; it answers immediately with a real object. **Use `recomputeContextTokens` as the
primary read and `contextInfo` as the enrichment**, which is the reverse of what the profile
implies.

Third read, free, and it lands in the transcript: the `session.shutdown` event carries the final
context accounting. VERIFIED from `events.jsonl`:

```json
{"type":"session.shutdown","data":{"shutdownType":"routine","totalPremiumRequests":0,
 "totalNanoAiu":0,"totalApiDurationMs":0,"sessionStartTime":1789824739444,
 "codeChanges":{"linesAdded":0,"linesRemoved":0,"filesModified":[]},"modelMetrics":{},
 "currentTokens":4,"systemTokens":0,"conversationTokens":0,"toolDefinitionsTokens":0}, …}
```

Fourth read, CLAIMED: a `statusLine` command in `settings.json` receives *"the current session status
as JSON on stdin"* every `refreshInterval` seconds (VERIFIED that the config key and contract exist,
`copilot help config` lines 204-210; the **exact stdin schema remains UNKNOWN** — my pty capture
failed in this environment). Its value is that it works for a session the orchestrator did **not**
spawn. Worth 15 minutes on an entitled account.

### 5b. Trigger compaction from outside

```javascript
const { messageId } = await rt.call('session.send', { sessionId, prompt: '/compact focus on the failing test' });
```

VERIFIED: `session.send` with `/compact` is **accepted and returns a `messageId`**
(`{"messageId":"51450a81-caee-4fc9-be68-412df84300df"}`), and the runtime acted on it — the session
title changed to `/compact` and the id was persisted into `workspace.yaml` as `name: /compact`. So
slash commands **do** dispatch over the SDK plane, which the profile could only infer. The compaction
itself could not run without entitlement.

**There is no compaction RPC on either plane.** VERIFIED: `session.compact` → `-32601 Unhandled
method`; ACP `session/compact` → `-32601 "Method not found"`. **Do not guess one.** Compaction is a
prompt-channel slash command, full stop.

### 5c. Prove it happened — four receipts (CLAIMED; needs one entitled run to confirm)

1. `session.compaction_complete` event with `preCompactionTokens` / `postCompactionTokens` /
   `summaryContent` / `compactionTokensUsed` / `requestId`. **A before/after token count is the
   proof.**
2. The `preCompact` hook, whose payload carries `trigger: "manual" | "auto"` — which is precisely
   *"proof it was **my** compaction and not the automatic one at 80%"* — plus `transcriptPath`.
3. **A checkpoint file appears under `$COPILOT_HOME/session-state/<uuid>/checkpoints/`** on every
   compaction, automatic or manual. The directory is real and is created at session start (VERIFIED
   — it exists in all four sessions I created). **This is the cheapest proof: `ls` before, `ls`
   after.** It needs no protocol client and works for sessions the orchestrator did not spawn.
4. OTel: chat spans carry `gen_ai.conversation.compacted=true`.

**Tuning rather than commanding:** `infiniteSessions: { enabled, backgroundCompactionThreshold: 0.80,
bufferExhaustionThreshold: 0.95 }` at session creation (ratios, not token counts). Default behaviour
is automatic compaction at ~80% and a hard pause at ~95%.

**Handoff, not compaction:** `history.clearContext` is **`-32601 Unhandled method` on the runtime
plane** (VERIFIED) — it is a *tool-handler primitive*, callable only from inside a tool call with a
non-empty seed prompt. **An external supervisor cannot invoke it.** To get a GSD-style hard handoff,
register a custom tool with `isTerminal: true` that wraps it and let the model pull the trigger. The
orchestrator can make it available and nudge; it cannot fire it.

---

## 6. Quota, reset time, and in-band limit detection

### 6a. Read remaining capacity — VERIFIED, and it is a server-scope call

```javascript
const { quotaSnapshots } = await rt.call('account.getQuota', {});
```

Ran here, unauthenticated, **with no session open**: `{"quotaSnapshots":{}}`. The method exists, is
server-scope, and costs nothing.

On an entitled account each snapshot carries (CLAIMED, official field table):
`entitlementRequests` (**`-1` = unlimited**), `usedRequests`, `remainingPercentage`, and
**`resetDate`** (ISO 8601). Keys are commonly `premium_interactions`, `chat`, `completions`.

```javascript
const snaps = quotaSnapshots ?? {};
if (Object.keys(snaps).length === 0) return { state: 'UNENTITLED' };   // ← NOT "zero quota"
const q = snaps.premium_interactions ?? snaps.chat ?? Object.values(snaps)[0];
if (!q) return { state: 'UNKNOWN_QUOTA_SHAPE' };
```

Two rules the adapter must encode: **(a)** the docs state plainly that *"the `quotaSnapshots` keys
are runtime strings that the SDK type system does not validate, so guard your lookups"* — never
hard-code `premium_interactions`; **(b)** empty map ≠ exhausted (§0.1).

**The axis-E/axis-F crossover (CLAIMED, and it is the best thing in this platform):** pass a specific
user's GitHub token to `getQuota` to read *that* account's quota. **One supervisor process can poll
every account the owner holds without spawning a session per account.** Nothing else in the field
scan does this.

### 6b. Windows

Monthly **AI credits** (current billing) or **premium requests** (legacy), with `resetDate` per
snapshot. A distinct **weekly** limit exists (`/usage` shows session and weekly bars). Per-model,
weekly and integration rate limits are classified separately from global 429s.

Opt-in per-session cap, VERIFIED verbatim from `copilot help limits`:

- `--max-ai-credits <credits>`, **minimum 30**.
- *"The AI credit limit is a soft cap: usage is known only after a model response returns. A response
  can therefore exceed or exhaust the limit before the CLI can observe that it has done so; the next
  model call is then blocked."*
- *"Hidden model work such as compaction counts toward `--max-ai-credits`."*
- *"Subagents share the same session limit as the parent session."* ← **matters for `--fleet`**: 32
  concurrent subagents draw on one budget.
- Timeline warnings at **50 / 75 / 90%**, and *"If this session continues, the next model call is
  final; tools will be disabled."*
- `--max-autopilot-continues <count>`, default **5** — a *turn* budget. Both caps are needed; they
  bound different things.

### 6c. Detect a limit hit in-band — VERIFIED shape

Any model-facing failure arrives as a `-32603` whose message embeds a **parseable HTTP envelope**:

```json
{"code":-32603,"message":"Request models.list failed with message: GenericFailure, {\"kind\":\"http\",
 \"status\":403,\"statusText\":\"Forbidden\",\"body\":\"unauthorized: not authorized to use this Copilot feature\\n\",
 \"hasRequestId\":true,\"headers\":[…,{\"name\":\"x-copilot-service-request-id\",\"value\":\"cff46b3a-…\"},…]}"}
```

**Extract `status` and branch on it:** `403` = unentitled/policy (permanent — fail the job, do not
retry), `429` = rate limited (transient — pause the queue; `headers` is a full array, so
`retry-after` / `x-ratelimit-reset` land here if GitHub sends them). Keep
`x-copilot-service-request-id` in the job record; it is what a support ticket needs.

Under `-p` the same condition is exit **1** plus prose on stderr (§2).

Richer, CLAIMED signals on an entitled account: `session_limits_exhausted.requested` →
`.completed` is a **request/response pair**, not a notification — the supervisor can top the budget
up (`response.additionalAiCredits`) and continue **without a human**. That is genuinely unusual.
`continueOnAutoMode: true` auto-downgrades to a cheaper model on eligible rate-limit errors, but
*"does not apply to global rate limits, generic 429s, or BYOK providers."*

**Fallback when quota cannot be read:** poll `account.getQuota` on a timer and treat the last good
snapshot as authoritative; never infer remaining quota from `usage.json`, which reports **consumed**,
not remaining. Do **not** use the REST billing endpoints — they need the `user` scope (the owner's
`gh` token lacks it) and report consumption with no remaining-entitlement field.

---

## 7. Switch a new session to a different account, and verify before work starts

Three mechanisms, increasing quality. **Mechanism 2 is what I exercised** — every command in this
spike ran under a redirected `COPILOT_HOME`, which is the proof that isolation works.

**1 — env token (simplest).** `COPILOT_GITHUB_TOKEN=… copilot -p …`. Precedence and accepted token
types in §1b. Never touches the Keychain.

**2 — `COPILOT_HOME` per account (full isolation, VERIFIED).**

```bash
export COPILOT_HOME="$FLEET/accounts/$ACCOUNT"     # defaults to $HOME/.copilot
```

Everything moves with it: `config.json` (which holds **`loggedInUsers`**, plural), `settings.json`,
`session-state/`, `session-store.db`, `permissions-config.json`, `mcp-config.json`, `skills/`,
`agents/`, `hooks/`, `logs/`. Confirmed by the `workspacePath` the runtime returned from
`session.create`: `…/cop-spike/home/session-state/<uuid>`. `COPILOT_CACHE_HOME` relocates the cache
separately. The legacy `--config-dir` flag still exists; the docs say prefer `COPILOT_HOME`.

**This is directly analogous to the owner's existing `CLAUDE_CONFIG_DIR`/profile-switcher machinery — the same
orchestrator concept transfers with no new design.**

**3 — per-session `gitHubToken` on one shared runtime (CLAIMED, and the best answer in the field).**
`client.createSession({ sessionId, gitHubToken, mode: "empty" })`. The multi-tenancy guide says
*"Prefer this over a single shared user token"* and *"Do not use the default `mode: "copilot-cli"`
for shared servers."* One supervisor, one runtime, N sessions, N accounts, each with its own quota
readable via `getQuota(userToken)`.

### Verify the switch BEFORE work starts — VERIFIED, and this is the whole point

Reuse §1b: create the session, wait for `host.event`/`auth_changed`, assert
`payload.data.authInfo.login === expectedAccount`, **then** send the first prompt. The event fires at
session creation, before any model call, so a mis-routed job costs nothing.

```javascript
const auth = await waitForAuthChanged(rt, sessionId);
if (auth.login !== expectedAccount) { await rt.call('session.destroy', { sessionId }); throw new Error(`wrong account: ${auth.login}`); }
if (auth.copilotUser.access_type_sku === 'no_access') throw new Error('account has no Copilot entitlement');
```

**Failure:** `login` is the previous account → the token did not take; check precedence
(`COPILOT_GITHUB_TOKEN` beats `GH_TOKEN` beats `GITHUB_TOKEN`) and that no stored credential in that
`COPILOT_HOME` is winning.

### A running session's account CANNOT be changed

`/user switch` is interactive-only; there is no `copilot user` subcommand (VERIFIED — the full
subcommand list is `app, login, help, init, update, version, sessions, memories, plugin, mcp, skill,
instruction, lsp, completion`); the SDK's `gitHubToken` is fixed at `createSession`.

**Workaround and its exact cost:** destroy the session, create a new one on the other account. If the
two accounts share a `COPILOT_HOME` the transcript survives; **if they have separate `COPILOT_HOME`s
— the safer posture — `session-state/` does not follow and the orchestrator must re-seed context.**
Cost: one compaction-summary-sized re-prompt per switch. Symlinking `session-state/` between homes is
**untested and UNKNOWN**; `session-store.db` is SQLite with a live `-wal`, so sharing it across
concurrent homes is likely to corrupt. **Pick isolation or cross-account resume; do not assume both.**

**Also cleared on account switch (CLAIMED):** server-fetched managed settings. MDM device policy is
never cleared.

---

## 8. Deliver an instruction into a running session, and confirm it arrived

```javascript
const { messageId } = await rt.call('session.send', { sessionId, prompt: 'Use JWT instead', mode: 'immediate' });
```

**VERIFIED on this machine:** `session.send` returns `{"messageId":"469b84b5-1141-4fd1-a3ce-0948dc70128a"}`
and accepts `mode: "immediate"`. Missing `sessionId` fails loudly: `-32603 … "Missing sessionId in
session.send request"` — no silent drop.

Two delivery modes (CLAIMED, official table):

| Mode | During an active turn | While idle |
|---|---|---|
| `"immediate"` (steering) | injected **before the next LLM call** | starts a new turn immediately |
| `"enqueue"` (default) | waits in a **FIFO queue** | starts a new turn immediately |

**Three-stage confirmation — do not conflate them:**

1. **Accepted** — `messageId` returned. VERIFIED.
2. **Queued** — a `pending_messages.modified` event fires. **VERIFIED live** (observed twice within
   3s of each `session.send`). This is the proof the runtime took custody of the text — exactly the
   receipt the owner's current harness lacks.
3. **Observed** — `assistant.turn_start` / the message appearing in `events.jsonl`. CLAIMED.

The docs are honest about the one race: *"If a steering message arrives after the turn completes,
it's automatically moved to the queue."* **A steer is never lost; it may land a turn later.** And
*"Don't over-steer — multiple rapid steering messages can degrade turn quality"* — the adapter should
rate-limit itself.

**ACP equivalent:** `session/prompt` (VERIFIED it exists — empty params returned `-32602` naming
`sessionId` and `prompt` as required, not `-32601`). `prompt` is an **array** of content blocks.

**Fallback if the runtime plane is unavailable:** the `notification` hook with
`matcher: "elicitation_dialog"` or `"permission_prompt"` returns `{ additionalContext?: string }`,
and *"the text is injected into the session as a prepended user message. This can trigger further
agent processing if the session is idle."* (CLAIMED.) That is an out-of-band injection channel for a
session the orchestrator did not spawn. **Do not use a prompt hook for this** — prompt hooks are
`sessionStart`-only and *"do not fire on resume, and do not fire in non-interactive prompt mode
(`-p`)"*. They seed; they do not inject.

---

## 9. Answer a permission prompt or a clarifying question without a human

**Could not be executed here** (every path needs a real turn). Shapes below are CLAIMED from official
docs; the *posture assertion* in 9c is VERIFIED.

### 9a. Permission — two routes

**Route A, protocol:** `onPermissionRequest` on `createSession`; observable as
`permission.requested` (`requestId`, `permissionRequest`) → `permission.completed`
(`requestId`, `result.kind`), correlated by `requestId`.

**Route B, the `permissionRequest` hook — no protocol client needed, and this is the sleeper.** It
fires *before* rule checks, session approvals, auto-allow/deny and user prompting; returning
`behavior: "allow" | "deny"` short-circuits the whole flow. The docs call it *"especially useful in
CLI pipe mode (`-p`) … where no interactive prompt is available."* Output contract: `behavior`,
`message` (reason fed back to the LLM on deny), `interrupt` (with deny, **stops the agent**). Return
`{}` to fall through. For command hooks, **exit code 2 = deny**. Hook types are `command`, `exec` and
**`http`** — so point every session's `permissionRequest` hook at the supervisor's local endpoint and
you have a supervisor-decides permission loop with zero protocol code.

**Two hard constraints:** for `preToolUse` and `permissionRequest` the hook URL **must be `https://`**
(the docs are explicit — *"because the response can grant tool permissions"*), so the supervisor needs
a local TLS endpoint, not plain HTTP. And **sandbox-bypass requests cannot be auto-approved**: for any
request with `requestSandboxBypass: true`, a hook `allow` does not pre-approve — *"only `deny` still
propagates."* **With the sandbox on, an unattended run will stall on anything needing to leave it.**

### 9b. The agent's own question

Copilot models `ask_user` as a tool and surfaces it as a correlated request:

```
user_input.requested   → { requestId, question, choices? }
user_input.completed   → { requestId }
elicitation.requested  → { requestId, message, requestedSchema }
```

**`choices` means the supervisor answers multiple-choice without inventing free text** — the cleanest
answer to this axis in the whole field scan.

Fallbacks, descending: the `notification` hook (§8); a `preToolUse` hook matching `ask_user` that
denies with the answer in `permissionDecisionReason` (crude — the model reads it as a refusal); or
`--no-ask-user`, which refuses the category outright and forces the agent to decide alone.

### 9c. Assert the permission posture after launch — VERIFIED, do not skip this

The profile flags a fail-closed enterprise-policy path that can **silently strip `--allow-all`** when
policy cannot be determined. There is a first-class event for it. VERIFIED payload from this machine:

```json
{"type":"session.managed_settings_resolved","data":{
  "source":"none","serverManaged":false,"deviceManaged":false,"clientManaged":false,
  "policyHelperManaged":false,
  "failClosed":false,
  "sandboxEnabledByUndeterminedPolicy":false,
  "bypassPermissionsDisabled":false,
  "managedKeys":[]}}
```

It is the **first** session event, ahead of `session.start`. Gate every job on it:

```javascript
if (d.bypassPermissionsDisabled || d.failClosed) abortJob('permission posture degraded');
if (d.sandboxEnabledByUndeterminedPolicy)        abortJob('sandbox forced on by undetermined policy');
```

**Why this matters more than it looks:** without full permissions, autopilot *"will automatically
deny any tool requests that require approval"* — it degrades to **silent failure**, burning credits
and producing nothing. That is worse than blocking. Assert, don't assume.

**Preferred unattended posture — not `--yolo`.** Pre-seed
`$COPILOT_HOME/permissions-config.json`, keyed by **absolute path** (git root for a repo; linked
worktrees resolve to the main repo root and therefore **share** permissions with it), with
`locations.<key>.tool_approvals[].kind` ∈ `commands, read, write, mcp, mcp-sampling, memory,
custom-tool, extension-management, extension-permission-access`. It grants exactly what the job needs
with no prompt. It does **not** support deny rules, ask rules, default modes, URL rules or tool
filtering — those stay on the command line. Pattern syntax, with the traps:

| Pattern | Trap |
|---|---|
| `shell(git:*)` | matches the **stem** — `git push` yes, `gitea` no. Approval for `git`/`gh` is **per first-level subcommand**. |
| `write(.env)` | a **relative** path matches trailing components — `.env` in *any* directory. Use an absolute path to scope. |
| `url(https://*.github.com)` | **protocol-aware**: approving `https://` does not allow `http://`. |

**Denial always wins, even over `--allow-all-tools`.** And tool *visibility*
(`--available-tools` / `--excluded-tools`) is a separate layer from tool *approval*
(`--allow-tool` / `--deny-tool`): approving a tool you filtered out does not bring it back.

**The `COPILOT_ALLOW_ALL` cliff — VERIFIED verbatim from `copilot help environment`:** setting it to
**exactly `"true"`** *"additionally trusts the working directory without prompting, which loads that
directory's skills, plugins, MCP servers, and hooks, **including hooks that run shell commands**; the
other truthy spellings (`1`, `yes`, `on`, `y`) only auto-approve tools."* **`=true` executes
repo-controlled shell code; `=1` does not.** Choose the spelling deliberately and write down why.

---

## 10. Resume after a crash, and after a reboot

Session state is on disk under `$COPILOT_HOME/session-state/<uuid>/`, so the conversation survives a
kill or a reboot. VERIFIED: sessions created by one process were resumed and listed by later,
unrelated processes.

```bash
copilot -p "continue where you left off" --resume="$SID" --allow-all-tools --output-format json
```

**VERIFIED:** `--resume=<exact uuid>` resolved the on-disk session and proceeded all the way to the
model call (which failed only on entitlement). Same for `--continue`.

| Selector | Behaviour (VERIFIED in installed `--help`) |
|---|---|
| `-r, --resume[=VALUE]` | by session ID, **ID prefix (7+ hex chars)**, or session name (exact, case-insensitive) |
| `--continue` | most recent session in the cwd, falling back to the globally most recent |
| `-n, --name <name>` | name a new session so `--resume` can find it by name |
| `--session-id <id>` | resume by exact id, **or create a new session when the value is a valid UUID** |
| `--connect[=SESSION-ID]` | remote session — **unavailable on this account** (`cli_remote_control_enabled: false`) |
| `-w, --worktree[=NAME]` | hidden but accepted; isolated git worktree under `<repo>.worktrees/` |

**Two traps, both VERIFIED:**

- `--session-id` and `--resume` are **rejected by the argument parser** when combined (§2). Pick one.
- **A documented behaviour did not reproduce.** The docs say a bare `--resume` under `-p` with
  multiple sessions *"exits with an error instead of silently starting a new session."* With **five**
  sessions on disk at 1.0.86, bare `--resume` under `-p` **did not error** — it selected a session and
  proceeded to the model call. **Treat the documented guard as absent: always pass an explicit
  `--resume=<uuid>`.** Relying on it to fail loudly is relying on behaviour this build does not have.

**Crash mid-turn.** `COPILOT_ENABLE_INTERRUPTED_SESSION_RESTORE=1` is CLAIMED to make the next
startup offer to restore an interrupted session and *"automatically resume that work once restored"*.
**It does not appear in `copilot help environment` at 1.0.86** (0 hits — see §0.2), and it is
delivered as a **startup dialog**, i.e. it wants a TTY. **For a headless supervisor, do not depend on
it.** The predictable pattern:

```bash
# 1. detect death: no process, and events.jsonl mtime older than the liveness threshold
# 2. relaunch with the recorded id and an explicit continue prompt
copilot -p "Resume the task. Re-read your plan and continue from the last completed step." \
        --resume="$SID" --allow-all-tools --output-format json
```

**After a reboot** the procedure is identical — nothing in `session-state/` is process-bound. Two
things to clean first: stale `.workspace-fork.lock` files, and `session-store.db-wal` /
`-shm` sidecars (SQLite recovers these itself; do not delete the `.db`).

**Session locking is still yours to build** — *"concurrent access to same session is undefined"* — but
assert the platform's signal: `session.start` carries **`alreadyInUse`** (VERIFIED, observed `false`).
If it is ever `true`, another worker holds that id; back off rather than racing.

Resilience the platform gives free (CLAIMED, changelog 2026-09-17): sessions resume *"even when
transcript files contain recoverable corruption"*, and a benchmarked **230 MB / 74k-event** transcript
loads in **under a second**.

---

## 11. Stop it cleanly, leaving nothing running

**The clean two-step, both VERIFIED on this machine:**

```javascript
await rt.call('session.abort',   { sessionId });   // → {"success":true}   cancels the in-flight turn
await rt.call('session.destroy', { sessionId });   // → {"success":true}   tears the session down
```

**This is the cancel path the profile could not find.** `session.abort` exists and works;
`session.compact`, `session.close`, `session.interrupt` do **not** (`-32601 Unhandled method`). On the
ACP plane the equivalent is `session/close` (exists, requires `sessionId`); ACP `session/cancel` is
**absent as a request and indistinguishable from a no-op as a notification** — do not use it.

**Verify the teardown:**

```javascript
const { sessions } = await rt.call('session.list', {});
sessions.find(s => s.sessionId === sessionId);   // gone, or isDetached:true
```

Then close the runtime. **VERIFIED graceful-shutdown sequence** from the process log — EOF on stdin is
enough:

```
[INFO] Received EOF on stdin, shutting down ACP server
[INFO] Preparing runtime for graceful shutdown
[INFO] Destroying 0 active sessions
[INFO] CLI server prepared for shutdown; transport remains open for RPC response
```

**Two shutdown hazards, both VERIFIED:**

```
[WARNING] [telemetry-queue] in-flight flushes did not settle within 999ms; posting the final batch alongside them
[WARNING] [shutdown] Timed out dispose: telemetryDisposeProcess (2001ms)
```

Telemetry disposal takes **~2 s**. **Allow at least 3 s between SIGTERM and SIGKILL** or the harness
will leave half-flushed telemetry and, worse, look like it hung.

For a `-p` run: SIGTERM the process; the session survives on disk and is resumable by id.
`COPILOT_TASK_WAIT_TIMEOUT_SECONDS` (CLAIMED, default **600**, `0` = exit immediately) governs how
long `-p` waits for pending background agents or shell commands — **a dev server left running holds a
job for ten minutes by default.** Set it low.

For a TCP runtime, kill by port, not by name:

```bash
lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t | xargs -r kill    # then verify the port is free
```

**Leak audit after every job:** no `copilot` process; no listener on the allocated port; no stale
`.workspace-fork.lock`; `usage.json` and `transcript.md` present (their absence is itself a failure
signal, §2).

---

## 12. Runtime-plane RPC surface — the map, VERIFIED by probe

Exists = answered or complained about params. Absent = `-32601 Unhandled method`.

| Method | Status | Returns / requires |
|---|---|---|
| `account.getQuota` | **exists** | `{quotaSnapshots:{}}` — server-scope, no session needed |
| `session.create` | **exists** | `{sessionId, nativeSessionId, startTime, isRemote, mode:"interactive", workspacePath, capabilities:{ui:{elicitation,mcpApps,canvases},extensions}, modelState}`; accepts `sessionId`, `workingDirectory` |
| `session.list` | **exists** | `{sessions:[{sessionId,startTime,modifiedTime,isRemote,isDetached,summary,name,clientName,context:{cwd}}]}` — cross-process |
| `session.send` | **exists** | `{messageId}`; needs `sessionId`, `prompt`; accepts `mode` |
| `session.abort` | **exists** | `{success:true}` — **the cancel path** |
| `session.destroy` | **exists** | `{success:true}` |
| `session.usage.getMetrics` | **exists** | see below |
| `session.metadata.contextInfo` | **exists** | `{contextInfo:null}` until initialised |
| `session.metadata.recomputeContextTokens` | **exists** | `{totalTokens,messagesTokenCount,systemTokenCount}` |
| `models.list` | **exists** | 403 here (unentitled); carries per-model AI-credit pricing when entitled |
| `session.close` · `session.compact` · `session.interrupt` · `history.clearContext` · `history.get` · `account.getInfo` · `account.getUser` · `session.metadata.get` · `permission.respond` · `userInput.respond` · `server.info` · `runtime.info` · `session.state.get` | **absent** | `-32601 Unhandled method` |

`session.usage.getMetrics`, VERIFIED response (same schema as `--usage-output-file`):

```json
{"totalPremiumRequestCost":0,"totalUserRequests":0,"totalNanoAiu":0,"totalApiDurationMs":0,
 "sessionStartTime":"2026-09-19T13:31:57.033Z",
 "codeChanges":{"linesAdded":0,"linesRemoved":0,"filesModifiedCount":0,"filesModified":[]},
 "modelMetrics":{},"agentMetrics":{},"lastCallInputTokens":0,"lastCallOutputTokens":0}
```

**Notification channels (VERIFIED):** `session.lifecycle` (`type`: `session.created` /
`session.updated`, plus `metadata.startTime` / `modifiedTime`), `session.event` (`{sessionId, event}`
where `event` is the standard envelope), and `host.event` (`{scope, kind, payload}` — `kind:
"auth_changed"` is the identity push of §1b).

### TCP mode and its shared secret — VERIFIED

```bash
copilot --server --port 47999
# → CLI server listening on port 47999
# → Warning: No COPILOT_CONNECTION_TOKEN was set, so connections will be accepted from any client

COPILOT_CONNECTION_TOKEN=… copilot --server --port 48001
# → CLI server listening on port 48001        (warning gone — the variable is real and gates the port)
```

Binds **127.0.0.1** (confirmed via `lsof`). `--stdio` and `--port` are mutually exclusive.
**Any orchestrator running a TCP control plane must set `COPILOT_CONNECTION_TOKEN`**, or any local
process can drive the agent. It appears in **no documentation and no help topic**.

---

## 13. The adapter interface

| # | Capability | Native / Emulated / Impossible | Mechanism | Verified here |
|---|---|---|---|---|
| 1 | Preflight & identity | **Native** | `host.event`/`auth_changed` → `login`, `access_type_sku`, `chat_enabled` | **yes** |
| 2 | Headless + pinned id + structured output | **Native** | `-p --session-id <uuid> --output-format json` | **yes** |
| 3 | Visible attachable terminal | **Native** | `-i "<prompt>"` via iTerm2/tmux; `COPILOT_MULTIPLEXER=tmux` | flag-read only |
| 4 | Liveness / state | **Native** | `session.list` (`isDetached`, `modifiedTime`) + event stream + `workspace.yaml` | **yes** |
| 5a | Read context fullness | **Native** | `session.metadata.recomputeContextTokens` (primary), `contextInfo` (enrich) | **yes** |
| 5b | Force compaction | **Native, via prompt channel** | `session.send("/compact …")` — **no RPC exists** | send verified |
| 5c | Prove compaction | **Native** | `session.compaction_complete` + `preCompact` hook (`trigger`) + a new file in `checkpoints/` | dir verified |
| 6 | Quota + reset + limit-hit | **Native** | `account.getQuota` → `remainingPercentage`, `resetDate`; `-32603` envelope carries HTTP `status` + headers | call verified |
| 7 | Account switch (new session) | **Native** | `COPILOT_HOME` / `COPILOT_GITHUB_TOKEN` / per-session `gitHubToken`; verified via `auth_changed` | **yes** |
| 7b | Account switch (running session) | **Impossible** | destroy + recreate; costs one context re-seed across separate homes | n/a |
| 8 | Deliver an instruction + receipt | **Native** | `session.send` → `messageId`, then `pending_messages.modified` | **yes** |
| 9a | Answer a permission prompt | **Native** | `permissionRequest` **https** hook, or `onPermissionRequest` | no |
| 9b | Answer the agent's own question | **Native** | `user_input.requested` with **`choices`** | no |
| 9c | Assert permission posture | **Native** | `session.managed_settings_resolved` → `bypassPermissionsDisabled`, `failClosed` | **yes** |
| 10 | Resume after crash / reboot | **Native** | `--resume=<uuid>`; state in `session-state/<uuid>/` | **yes** |
| 10b | Auto-restore a mid-turn crash | **Emulated** | env var is CLAIMED, TTY-oriented, absent from 1.0.86 help — relaunch by id instead | no |
| 11 | Clean stop | **Native** | `session.abort` → `session.destroy` → stdin EOF; **allow 3 s** for telemetry | **yes** |
| — | Session locking | **Emulated (orchestrator owns it)** | platform gives only the `alreadyInUse` signal | signal verified |
| — | Custom compaction summariser | **Impossible from outside** | `history.clearContext` is a tool-handler primitive the **model** must invoke | absent verified |
| — | Remote/mobile supervision | **Impossible on this account** | `cli_remote_control_enabled: false` | **yes** |

**Emulation the orchestrator must write:** a session lock (file lock on
`session-state/<uuid>/`, cross-checked against `alreadyInUse`); a mid-turn crash detector
(process gone + `events.jsonl` mtime stale) with relaunch-by-id; a local **HTTPS** endpoint for the
permission hook; a context re-seeder for cross-account moves; and stderr+exit-code parsing, because
fatal errors never appear in the JSONL.

**Build order for an implementer:** ① the `Content-Length` RPC client (§0.3) — nothing works without
the right framing; ② preflight/identity (§1b) — it is also the account verifier and the entitlement
gate; ③ launch + pinned UUID + JSONL parsing (§2); ④ liveness via `session.list` (§4a); ⑤ abort/destroy
(§11); ⑥ quota polling (§6); ⑦ steering (§8); ⑧ the permission hook (§9), which is the only piece
needing TLS and the only one not verifiable without entitlement.

**Unattended launch posture:**

```bash
CI=1 \
COPILOT_AUTO_UPDATE=false \
COPILOT_HOME="$FLEET/accounts/$ACCOUNT" \
COPILOT_GITHUB_TOKEN="$TOKEN" \
COPILOT_OTEL_FILE_EXPORTER_PATH="$RUNDIR/otel.jsonl" \
COPILOT_TASK_WAIT_TIMEOUT_SECONDS=120 \
copilot -p "$PROMPT" --session-id "$(uuidgen | tr 'A-Z' 'a-z')" \
  --output-format json --usage-output-file "$RUNDIR/usage.json" --share "$RUNDIR/tx.md" \
  --allow-tool='shell(git:*)' --deny-tool='shell(git push)' --no-ask-user \
  --max-ai-credits 200 --max-autopilot-continues 10 --no-auto-update
```

`CI=1` alone disables auto-update (detected via `CI`, `BUILD_NUMBER`, `RUN_ID`,
`SYSTEM_COLLECTIONURI` — VERIFIED in help); the explicit flags are belt-and-braces against a
near-daily release cadence. Use the **OTel file exporter**, never `http://localhost:4318` — plaintext
OTLP export is **silently disabled** and the warning is suppressed by `--log-level error|none`,
leaving no signal at all.

---

## 14. Support tier

### **Tier 1 on capability. Currently unusable on this account.**

**Tier 1 on capability, and it is not close.** Copilot CLI is the only platform in this scan that
answers *all eleven* recipes with a documented mechanism, and I verified nine of them by running them
here — including the three the owner called non-negotiable and that the current harness fails:

- **Read remaining quota with a reset date** — `account.getQuota`, server-scope, free, and readable
  for *other* accounts by passing their token.
- **Answer the session's own question programmatically** — `user_input.requested` with a `choices`
  array, correlated by `requestId`.
- **Deliver an instruction and know it arrived** — `session.send` → `messageId` → the
  `pending_messages.modified` event I watched fire. No keyboard, no stranded text.

Three things it does *better* than the profile claimed, all newly verified here: **`session.abort`
is a real cancel path**; **`session.list` enumerates the fleet across processes**; and the
**permission-posture assertion is a first-class event**, not something the orchestrator must infer.

**But the account is `access_type_sku: "no_access"`, so today it scores unusable in practice.** The
gap is one checkout, not one engineering quarter — `can_signup_for_limited: true`.

**The three things that should temper enthusiasm** are unchanged and real: the control plane rests on
a **public-preview protocol** with **experimental RPCs** shipping **near-daily** (835 versions in
twelve months) — pin with `--prefer-version` and `@1.0.86`; the binary is **145 MB** and **not
currently installed**; and a **fail-closed policy path** can silently strip the permission posture an
unattended run depends on — which is why §9c is mandatory, not optional.

**Recommendation.** Treat Copilot CLI as the **reference implementation the adapter interface is
designed against**, because it exercises every axis and will expose gaps in the abstraction that
weaker platforms let you paper over. Build the adapter now against the unauthenticated surface — nine
of eleven recipes are verifiable without spending a credit, which is an unusually good position to be
in. Then make the entitlement decision as a separate, explicit call.

### Follow-ups, in value order — each needs one entitled run

| # | Question | Axis | Cost |
|---|---|---|---|
| 1 | Do the owner's `.claude/skills` GSD skills **execute** under Copilot, not merely get discovered? Copilot reads `.claude/skills/` **and `CLAUDE.md`** natively. | I | 1 run — **highest value in this file**; it decides whether the workflow engine ports for free |
| 2 | Exact stdin JSON the `statusLine` command receives — does it carry quota as well as context? It is the only context read that works for a session the orchestrator did not spawn. | D, E | 15 min |
| 3 | Confirm `session.compaction_complete` fires from an SDK-sent `/compact`, and that a `checkpoints/` file appears. | D | 1 run |
| 4 | Confirm `session_limits_exhausted.requested/.completed` really lets the supervisor top up a budget mid-run without a human. | E | 1 run with `--max-ai-credits 30` |
| 5 | Does `--fleet`'s 32-way subagent concurrency share one session budget in practice? (`copilot help limits` says subagents share the parent limit.) | E, I | 1 run |
| 6 | Can two `COPILOT_HOME`s share `session-state/` by symlink for cross-account resume — and does `session-store.db`'s WAL survive it? | B, F | 30 min, no entitlement needed |
