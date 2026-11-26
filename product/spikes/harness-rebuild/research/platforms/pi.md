# Platform profile — **pi** (Pi coding agent)

**Date of this pass:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0).
**Version evaluated:** `@earendil-works/pi-coding-agent` **0.85.1** (published 2026-09-05).
**Evaluated by:** installing 0.85.1 into an isolated sandbox with a sandboxed `HOME`, running the
real binary, reading the package's own shipped docs, and reading the unminified JavaScript in
`dist/`. No owner config was modified, no owner quota was spent, and no LLM request was ever made.

**Evidence tags.** **VERIFIED** = read in the shipped source/docs or executed on this machine.
**CLAIMED** = asserted by a README or vendor page only. **UNKNOWN** = could not establish.

---

## 0. Which "pi" this is, and why

The owner's list ("Codex, ChatGPT, Kimi, GLM, Gemini, pi, something from Xiaomi, opencode") gives
no other disambiguator than company. Three referents were considered.

| Candidate | What it is | Verdict |
|---|---|---|
| **Pi coding agent** — npm `@earendil-works/pi-coding-agent`, binary `pi`, repo `github.com/earendil-works/pi` | Open-source terminal coding agent by Mario Zechner (`badlogic`) | **This is what I evaluated.** The only referent that is a coding executor at all. |
| **Inflection Pi** (`pi.ai`) | Consumer conversational assistant | Rejected — no CLI, no agent loop, no code execution. Not an orchestratable executor. |
| **Pi Labs / withpi.ai** | Scoring and reward-model tooling | Rejected — evaluation tooling, not an executor. |

**Confidence: high.** The Pi coding agent is the only "pi" that appears in agent-CLI directories
next to the other tools the owner named, and it is the only one a queue of coding tasks could run
on. Repo facts, queried today from the authenticated GitHub API (**VERIFIED**):
`earendil-works/pi`, MIT, **107,198 stars**, 13,532 forks, 222 open issues, created 2025-08-09,
last push 2026-09-18, not archived. Latest release `v0.85.1` (2026-09-05). Package publish history
is dense and current — 45 versions, 0.74.0 on 2026-05-07 through 0.85.1, roughly weekly.

**Not installed on this machine** (**VERIFIED**): `which pi` → not found; no `~/.pi` directory.
Everything below was established in a sandbox, not from an existing owner install.

> **One correction to the field scan.** `00-field-scan.md` §1 lists "MCP" under pi's extensibility.
> That is wrong and it matters. pi has **no MCP support at all** — it is an explicit non-feature.
> `docs/usage.md:309` (VERIFIED): *"It intentionally does not include built-in MCP, sub-agents,
> permission popups, plan mode, to-dos, or background bash."* `README.md:499` (VERIFIED):
> *"**No MCP.** Build CLI tools with READMEs, or build an extension that adds MCP support."*
> The README line the scan likely read is `README.md:395`, "MCP server integration", which sits in a
> list headed **"What's possible:"** — things you *can build as an extension*, not things pi ships.

---

## A. LAUNCH

**Headless: yes, two distinct modes. Visible-terminal: yes, but mutually exclusive with programmatic control.**

All flags below are **VERIFIED** — quoted from `pi --help` run on this machine at 0.85.1.

| Mode | Flag | Character |
|---|---|---|
| Interactive TUI | *(default)* | Full-screen terminal app the owner can attach to and type into |
| Print / one-shot | `--print`, `-p` | *"Non-interactive mode: process prompt and exit"* |
| JSON event stream | `--mode json` | Every session event as JSON Lines on stdout |
| **Bidirectional RPC** | `--mode rpc` | Line-delimited JSON **over stdin and stdout**, with request/response correlation |

`--mode <mode>` takes `text` (default), `json`, or `rpc`.

Structured output: **yes, and unusually good.** `--mode json` emits `JsonAgentSessionEvent` records
— session header first, then `agent_start`, `turn_start`, `message_start`, `message_update`
(delta-only), `message_end`, `turn_end`, `agent_end`, plus `tool_execution_start/update/end`. Every
`message_update` carries a cumulative `usage` object with `input`/`output`/`cacheRead`/`cacheWrite`
and a per-field `cost` breakdown.

Print mode merges piped stdin into the prompt (**VERIFIED**, `docs/usage.md`):
`cat README.md | pi -p "Summarize this text"`.

**Exit codes and stream hygiene are correct** — tested directly, without a pipe (**VERIFIED**):

| Situation | Exit | stdout | stderr |
|---|---|---|---|
| `-p` with no credentials | **1** | *(empty)* | `No API key found for the selected model.` |
| `--mode json` with no credentials | **1** | session header line only — still valid JSONL | same message |
| `--definitely-not-a-flag` | **1** | *(empty)* | `Error: Unknown option: --definitely-not-a-flag` |

This is better than it sounds and worth stating plainly: **pi fails loudly.** Errors go to stderr,
stdout stays parseable, and the exit code is non-zero. The harness field-notes failure class of
"reports success and does nothing" does not apply to pi's launch path.

**The central launch tradeoff for this orchestrator.** A `pi` process is *either* a TUI the owner
can type into *or* an RPC process the supervisor can drive — never both. `--mode rpc` owns stdin.
So the choice is:

- **RPC** — full programmatic control (axes D and G below), but the owner cannot attach and type.
  He can only watch the session JSONL, or a UI the orchestrator renders itself.
- **TUI in tmux/iTerm** — the owner can attach and type, but the supervisor's only input channel is
  terminal keystroke injection (`tmux send-keys`), which is exactly the blind, unconfirmable nudge
  the current harness already fails at.

pi's own docs push you toward tmux for anything TUI-shaped (`docs/tmux.md`, and "No background
bash. Use tmux. Full observability, direct interaction."). tmux needs `set -g extended-keys on` and
`set -g extended-keys-format csi-u` (tmux ≥ 3.5) or Shift+Enter and Ctrl+Enter collapse into plain
Enter (**VERIFIED**, `docs/tmux.md`).

---

## B. IDENTITY & RESUME — *owner non-negotiable*

**The strongest axis in this profile, with one real defect and two silent traps.**

### The orchestrator names the session before it exists

`--session-id <id>` — help text, verbatim: *"Use exact project session ID, creating it if missing"*.
**VERIFIED by execution.** Launching with `--session-id orch-test-001` and asking `get_state`
returned `"sessionId":"orch-test-001"`. The id is an **arbitrary string**, not a forced UUID. This
removes the whole class of "scrape the session id out of startup output" fragility.

The file is named deterministically (**VERIFIED** in `dist/core/session-manager.js:667`):

```js
this.sessionFile = join(this.getSessionDir(), `${fileTimestamp}_${this.sessionId}.jsonl`);
```

so a supervisor can find a session by glob: `*_<session-id>.jsonl`.

### Exact resume works

**VERIFIED end-to-end.** I hand-wrote a session JSONL containing a user message and an assistant
message, then launched `pi --mode rpc --session-id crash-resume-probe`. It reopened that exact file,
printed no warning, and `get_last_assistant_text` returned
`"I completed step 1. MARKER_SURVIVED_CRASH"`. The same works in print mode:
`pi -p --session-id crash-resume-probe "continue"` reopened the file and appended to it.

### DEFECT — nothing is written to disk until the first assistant message

This is the single most important finding on this axis, and it is invisible from the docs.
`dist/core/session-manager.js:739`, verbatim:

```js
_persist(entry) {
    if (!this.persist || !this.sessionFile) return;
    const hasAssistant = this.fileEntries.some((e) => e.type === "message" && e.message.role === "assistant");
    if (!hasAssistant) {
        if (this.flushed) { appendFileSync(this.sessionFile, `${JSON.stringify(entry)}\n`); }
        else { this.flushed = false; }   // <- nothing reaches disk
        return;
    }
    ...
}
```

**VERIFIED by execution:** I ran a session that assigned an id, set a name, and executed a real
`bash` command through RPC. `get_entries` showed all of it in memory. `find … -name '*.jsonl'`
found **no file at all**. The session directory is created; the file is not.

Consequence for an unattended queue: the window between "process launched" and "first assistant
token returned" is **completely unrecoverable**. If the provider is down, the key is wrong, the
model is unavailable, or the machine reboots in that window, the session leaves no trace — not even
an empty file the supervisor could detect. And that is precisely the window in which startup
failures happen.

After the first assistant message, durability is excellent: `flushed` flips true and every
subsequent entry is `appendFileSync`'d synchronously, one line at a time. A crash then costs at most
the entry in flight.

### TRAP 1 — `--session-id` is cwd-scoped and fails *silently*

`dist/main.js:186` (**VERIFIED**):

```js
async function findLocalSessionByExactId(sessionId, cwd, sessionDir) {
    const localSessions = await SessionManager.list(cwd, sessionDir);
    const localMatch = localSessions.find((s) => s.id === sessionId);
    return localMatch ? { type: "local", path: localMatch.path } : undefined;
}
```

Only the current directory is searched. No global fallback. On a miss, `dist/main.js:343` prints a
yellow warning **to stderr** and then creates a brand-new session carrying the same id:

```
Warning: No project session found with id 'X'; creating a new session with that id.
```

**VERIFIED by execution:** same `--session-id crash-resume-probe`, run from a sibling directory →
new empty session, `messageCount: 0`, all prior context gone. If the supervisor discards stderr — and
harnesses usually do — this is a silent context amputation that looks like a successful resume. A
worktree path, a symlinked path, or a `/private/tmp` vs `/tmp` difference is enough to trigger it.

### TRAP 2 — `--session` resumes better but blocks on a prompt

`--session <path|id>` uses a different resolver (`resolveSessionPath`, `dist/main.js`): cwd-local
exact, then cwd-local **prefix**, then **global across all projects** (`SessionManager.listAll`),
exact then prefix. Two behaviours follow, both **VERIFIED by execution**:

- **Miss → loud failure.** `--session no-such-session-xyz` → stderr `No session found matching
  'no-such-session-xyz'`, **exit 1**. This is what an orchestrator wants.
- **Found in another directory → interactive prompt, then abort.** From a different cwd:
  `Session found in different project: …/piwork` / `Fork this session into current directory?
  [y/N] Aborted.` With no TTY it aborts. Cross-directory resume is **not available unattended**.

**The resulting rule for the orchestrator, which is not obvious and not documented:**
use **`--session-id` to create** a session, **`--session` to resume** it, and always relaunch from a
**byte-identical cwd**. `--session-id` fails silently; `--session` fails loudly. Loud is what you
want on a resume.

### Listing sessions

There is **no CLI subcommand to list sessions** (**VERIFIED** — `pi --help` commands are only
`install`, `remove`, `uninstall`, `update`, `list` *(packages, not sessions)*, `config`, `auth`).
`-r`/`--resume` opens an interactive picker, useless unattended. Programmatic listing exists only in
the SDK: `SessionManager.list(cwd, sessionDir?)` and `SessionManager.listAll(sessionDir?)`.
**Workaround:** read the filesystem directly — sessions live at
`~/.pi/agent/sessions/--<cwd with / replaced by ->--/<timestamp>_<id>.jsonl`. Cost: the orchestrator
reimplements listing and owns the path-mangling convention.

### What survives what

| Event | Survives? |
|---|---|
| Process kill after first assistant message | **Yes** — JSONL is synchronously appended per entry |
| Process kill before first assistant message | **No** — no file was ever created |
| Reboot | Same as above; nothing is held in a daemon |
| Provider outage mid-run | Session file intact; `auto_retry_*` then a `stopReason:"error"` assistant message |
| Concurrent second process on the same session | **Unprotected** — see below |

**Session files are not lock-protected.** `proper-lockfile` is a dependency and is used for
`auth.json` (`dist/core/auth-storage.js:39,85`), `settings.json` (`dist/core/settings-manager.js:63`)
and `trust.json` (`dist/core/trust-manager.js:113`) — but `grep lockfile dist/core/session-manager.js`
returns **nothing** (**VERIFIED**). Two pi processes pointed at one session file will interleave
appends with no arbitration. I ran two concurrently against the same id; both started, both exited 0,
neither complained. The orchestrator must enforce one-writer-per-session itself.

---

## C. TRANSCRIPT

**Excellent. The best-specified transcript format in this field scan so far.**

- **Location** (**VERIFIED**): `~/.pi/agent/sessions/--<path-with-slashes-as-dashes>--/<timestamp>_<uuid-or-assigned-id>.jsonl`
- **Override precedence** (**VERIFIED**, `docs/settings.md`): `--session-dir` → `PI_CODING_AGENT_SESSION_DIR` → `sessionDir` in settings.json.
- **Format:** JSONL, one JSON object per line, first line a `session` header
  (`{"type":"session","version":3,"id":…,"timestamp":…,"cwd":…}`).
- **Live-readable:** yes. Entries are appended synchronously with `appendFileSync` as they occur, so
  `tail -f` gives a supervisor real-time progress — *after* the first assistant message (see the
  defect in B).

**It is a tree, not a log.** Every entry has `id` (8-char hex) and `parentId`; the current position
is the active leaf. Version 3 is current; v1 and v2 auto-migrate on load. Entry types
(**VERIFIED**, `docs/session-format.md`): `message`, `model_change`, `thinking_level_change`,
`compaction`, `branch_summary`, `custom`, `custom_message`, `label`, `session_info`.

This means a supervisor reading the file must walk `parentId` from the leaf, not read top to bottom —
abandoned branches are physically present in the same file. `docs/session-format.md` specifies
`buildContextEntries()` / `buildSessionContext()` precisely enough to reimplement.

**Live reading over RPC, with a durable cursor.** `get_entries` accepts `since: "<entryId>"` and
returns only entries strictly after it, plus `leafId`. The doc states the intent directly: *"an entry
id works as a durable cursor … even across client restarts."* `get_tree` returns the whole tree.
This is a genuinely well-designed supervision surface — the orchestrator polls with its last-seen id
and gets an exact delta plus a one-field check ("did the active branch move?").

**Cost accounting is in the transcript.** Every `assistantMessage` carries `usage` with
`input`/`output`/`cacheRead`/`cacheWrite` and a `cost` sub-object. So per-session spend is
reconstructable from the file alone, offline, without asking any provider.

Also available: `--export <file>` renders a session to HTML and exits; RPC `export_html` does the
same in-process.

---

## D. CONTEXT — *owner non-negotiable*

**Fully answered. This is pi's best axis, and the only platform in this scan so far that answers all three parts — read, trigger, and proof.**

### Read context fullness from outside — YES

RPC `get_session_stats` returns, among token and cost totals:

```json
"contextUsage": { "tokens": 60000, "contextWindow": 200000, "percent": 30 }
```

The doc is explicit that this is not a decorative number: *"`contextUsage` contains the actual
current context-window estimate used for compaction and footer display."* The supervisor reads the
same value the compactor acts on.

Two documented caveats, both **VERIFIED** in docs and consistent with what I observed:
- `contextUsage` is **omitted entirely** when no model or context window is resolved. My probe
  sessions ran without credentials and the field was absent — the orchestrator must treat "missing"
  as "unknown", not "zero".
- `contextUsage.tokens` and `.percent` are **`null` immediately after compaction** until a fresh
  post-compaction assistant response supplies real usage. A supervisor polling right after a compact
  will see nulls and must not read that as "context is empty".

Inside an extension the same value is `ctx.getContextUsage()`.

### Trigger compaction from outside — YES

RPC command:

```json
{"type": "compact"}
{"type": "compact", "customInstructions": "Focus on code changes"}
```

`set_auto_compaction` toggles the automatic path: `{"type":"set_auto_compaction","enabled":false}`.

### Proof it happened — YES, three independent ways

1. **The command response returns the receipt**:
   `{"summary": "...", "firstKeptEntryId": "abc123", "tokensBefore": 150000, "estimatedTokensAfter": 32000, "usage": {...}, "details": {}}`.
   Note `estimatedTokensAfter` is documented as *"a heuristic estimate … not a provider-exact token
   count"* — good enough to confirm the compaction happened, not a billing figure.
2. **Events fire**: `compaction_start` with `reason` ∈ `"manual"` | `"threshold"` | `"overflow"`, then
   `compaction_end` with the full result, `aborted`, and `willRetry`. On failure, `result: null`,
   `aborted: false`, and an `errorMessage`. Abort gives `result: null`, `aborted: true`.
3. **A typed entry lands in the session file**: `{"type":"compaction", "id":…, "parentId":…,
   "summary":…, "tokensBefore":…, "firstKeptEntryId":…}`, optionally with `usage`, `details`
   (`{readFiles, modifiedFiles}`), and `retainedTail`. So proof is durable and survives a supervisor
   restart — it can be re-read from disk hours later.

### Auto-compaction and custom compaction

Threshold (**VERIFIED**, `docs/compaction.md`): `contextTokens > contextWindow - reserveTokens`, with
`reserveTokens` default 16384 and `keepRecentTokens` default 20000, both configurable in
`~/.pi/agent/settings.json` or `<project>/.pi/settings.json`. Checked after tool batches complete,
before a new user prompt, and after a low-level agent run ends.

**A custom-compaction hook exists and is first-class.** `session_before_compact` fires before both
manual and automatic compaction, receives `preparation` (`messagesToSummarize`, `turnPrefixMessages`,
`previousSummary`, `fileOps`, `tokensBefore`, `firstKeptEntryId`, `settings`), `reason`, `willRetry`
and an `AbortSignal`, and can either `return { cancel: true }` or supply its own summary — including
one generated by a **different, cheaper model**. `examples/extensions/custom-compaction.ts` is a
complete worked example. `session_compact_failed` pairs attempts with terminal outcomes for
telemetry. `serializeConversation(convertToLlm(...))` is exported for turning messages into text.

`examples/extensions/trigger-compact.ts` is a 40-line extension that compacts on crossing a token
threshold and registers a `/trigger-compact` command — effectively a ready-made template for
supervisor-driven context management.

**Handoff as an alternative to compaction.** `examples/extensions/handoff.ts` implements the
"transfer to a fresh session" pattern the owner has described wanting, with the rationale stated in
its header: *"Instead of compacting (which is lossy), handoff extracts what matters for your next
task and creates a new session with a generated prompt."*

---

## E. QUOTA — *owner non-negotiable*

**The weakest axis. pi never reads remaining capacity, and it cannot, because it has no account of its own.**

### There is no programmatic quota read — first-party

**VERIFIED by exhaustive grep of `dist/`:** zero occurrences of `oauth/usage`, zero of
`x-ratelimit`, zero of any usage-endpoint call. pi has **no** `pi usage`, `pi limits` or equivalent
subcommand (`pi --help` lists only `install`/`remove`/`uninstall`/`update`/`list`/`config`/`auth`).
There is no window model at all — no rolling-hours concept, no weekly concept, no credit balance.

This is architectural, not an oversight. pi is a **BYO-credential client** for ~35 providers. The
quota lives at whichever provider the credential belongs to, in that provider's own shape. pi never
claims to model it.

### What pi *does* give you — and it is more than nothing

**1. A limit-hit signal, in band, with a reset time — but only as prose.**
`dist/bundle/chunks/openai-codex-responses-*.js` (**VERIFIED**, verbatim):

```js
if (/usage_limit_reached|usage_not_included|rate_limit_exceeded/i.test(code) || response.status === 429) {
    let plan = err.plan_type ? ` (${err.plan_type.toLowerCase()} plan)` : "",
        mins = err.resets_at ? Math.max(0, Math.round((err.resets_at*1e3 - Date.now())/6e4)) : void 0,
        when = mins !== void 0 ? ` Try again in ~${mins} min.` : "";
    friendlyMessage = `You have hit your ChatGPT usage limit${plan}.${when}`.trim()
}
```

and then, in the same file: `throw new Error(info.friendlyMessage || info.message)`.

So the provider's structured `resets_at` **is parsed and then thrown away** — flattened into an
English sentence. The orchestrator's only access is a regex over
`"You have hit your ChatGPT usage limit (pro plan). Try again in ~47 min."` That string reaches the
supervisor reliably enough — as `auto_retry_start.errorMessage`, as `auto_retry_end.finalError`, and
as `errorMessage` on a `stopReason: "error"` assistant message persisted in the session file — but
it is prose, it is provider-specific, and it is one upstream wording change away from breaking.

**2. The real lever: `after_provider_response` exposes raw HTTP headers.**
This is the axis-E answer, and it is a good one. `docs/extensions.md:722` (**VERIFIED**):

> Fired after an HTTP response is received and **before its stream body is consumed**.
> `event.status` — HTTP status code. `event.headers` — normalized response headers.

```typescript
pi.on("after_provider_response", (event, ctx) => {
  if (event.status === 429) { console.log("rate limited", event.headers["retry-after"]); }
});
```

`examples/extensions/provider-payload.ts` is a working 19-line implementation that appends
`[${event.status}] ${JSON.stringify(event.headers)}` to a log file on every response. A supervisor
can drop in an extension that parses `anthropic-ratelimit-unified-*`, `x-ratelimit-*` or
`retry-after` on **every single request** and writes them to a file or a socket — which is richer
and more current than polling a usage endpoint on a timer.

Documented caveat, quoted: *"Header availability depends on provider and transport. Providers that
abstract HTTP responses may not expose headers."* So this works for HTTP-streaming providers and is
**UNKNOWN** per-provider until tested. Bedrock and any WebSocket transport are the obvious doubts.

**3. Retry behaviour is configurable and has a quota-relevant trap.**
`auto_retry_start` / `auto_retry_end` events carry `attempt`, `maxAttempts`, `delayMs`,
`errorMessage`, `finalError`. Defaults: `retry.enabled: true`, `retry.maxRetries: 3`,
`retry.baseDelayMs: 2000` (2s/4s/8s). `abort_retry` cancels an in-flight retry from RPC.

`docs/settings.md` carries an explicit warning that the orchestrator must respect (**VERIFIED**,
verbatim):

> Keep `retry.provider.maxRetries` at `0` unless provider-level retries are explicitly needed.
> Setting it above `0` can make SDK/provider retries handle out-of-usage-limit errors before Pi sees
> them, **which may block the agent until the provider quota resets in some circumstances.**

That is an overnight-run killer: a silently wedged process that looks alive. Default is `0`; leave it.
Also relevant: `retry.provider.maxRetryDelayMs` (default 60000) fails fast instead of "waiting
silently" when a provider asks for a longer delay — set to `0` to disable the cap.

### Cost model — and a trap specific to this owner

`docs/providers.md` (**VERIFIED**, verbatim):

> **Claude Pro/Max** — Anthropic subscription auth is active for Claude Pro/Max accounts.
> **Third-party harness usage draws from extra usage and is billed per token, not against Claude
> plan limits.**

There is even a setting for the warning: `warnings.anthropicExtraUsage`, default `true`.

For this owner this is the headline economic fact of the whole profile. His entire existing
rate-limit discipline — `five_hour.utilization`, `seven_day.utilization`, `resets_at` from
`api.anthropic.com/api/oauth/usage`, wired into `claude-limits` in
`~/.config/claude-profiles/profiles.sh` — measures a budget that **pi does not consume**. Running pi
on his Claude subscription spends *money per token* rather than *plan quota*, and the number he
currently watches will not move. An orchestrator that treats pi-on-Anthropic as "free until the
weekly limit" would be wrong in the most expensive possible direction.

### Summary

| Question | Answer |
|---|---|
| Read remaining capacity programmatically? | **No.** Nothing first-party. |
| What windows exist? | **None modelled.** pi has no concept of a quota window. |
| Limit-hit signalled in band? | **Yes**, but as an English error string, not a field. |
| Reset time exposed? | **Parsed then discarded** — survives only inside that sentence. |
| Closest workaround | An `after_provider_response` extension logging real rate-limit headers per request, plus a regex on the limit-hit prose. |
| Cost of the workaround | Writing and maintaining a TypeScript extension per provider family, plus a brittle regex, plus per-provider verification that headers are exposed at all. |

---

## F. ACCOUNTS — *owner non-negotiable*

**Strong for new sessions, impossible for running ones.**

### Several accounts on one machine — YES, three independent mechanisms

**1. Whole-config isolation by environment variable — the cleanest.**
`PI_CODING_AGENT_DIR` overrides the config directory (default `~/.pi/agent`).
**VERIFIED by execution:** running with `PI_CODING_AGENT_DIR=<sandbox>/pi-acctB` produced a fully
separate tree — its own `auth.json`, its own `models-store.json`, its own `sessions/`. This is
exactly the `CLAUDE_CONFIG_DIR` pattern the owner's profile switcher already uses for Claude Code, so
**the existing multi-account machinery generalises to pi with no new concepts** — one env var per
account, set at spawn.

Note the deliberate split: `PI_CODING_AGENT_SESSION_DIR` (and `--session-dir`) move *sessions*
independently of *credentials*. An orchestrator can therefore give three accounts three credential
stores while pointing all of them at one shared session directory — or the reverse.

**2. Per-invocation credential override.** `--api-key <key>` is resolved first, ahead of everything
else. Resolution order (**VERIFIED**, `docs/providers.md`): `--api-key` → `auth.json` →
environment variable → custom provider keys in `models.json`.

**3. Per-provider environment variables.** ~35 of them, listed in `pi --help`. Relevant to the
owner's stated platform list: `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` / `ANTHROPIC_OAUTH_TOKEN`,
`MOONSHOT_API_KEY` and `KIMI_API_KEY` (Kimi For Coding), `ZAI_API_KEY` / `ZAI_CODING_CN_API_KEY`
(GLM), `GEMINI_API_KEY`, `OPENCODE_API_KEY`, and — directly matching the owner's existing MiMo
config — `XIAOMI_API_KEY`, `XIAOMI_TOKEN_PLAN_CN_API_KEY`, `XIAOMI_TOKEN_PLAN_AMS_API_KEY`,
**`XIAOMI_TOKEN_PLAN_SGP_API_KEY`**. That last one is the Singapore token-plan endpoint the field
scan found already configured in `~/.config/claude-mimo/env`. pi supports it as a **named
first-class provider** (`auth.json` key `xiaomi-token-plan-sgp`), not as a base-URL hack.

### `auth.json` can shell out for credentials — the best account-switching primitive here

`~/.pi/agent/auth.json`, created `0600`, takes precedence over environment variables. Its `key` field
supports command execution and env interpolation (**VERIFIED**, `docs/providers.md`):

```json
{ "type": "api_key", "key": "!security find-generic-password -ws 'anthropic'" }
{ "type": "api_key", "key": "!op read 'op://vault/item/credential'" }
{ "type": "api_key", "key": "$MY_ANTHROPIC_KEY" }
```

A leading `!` executes the whole value and uses stdout, **cached for the process lifetime**. `$$`
and `$!` escape a literal `$` / `!`. Credentials can also carry a provider-scoped `env` object used
ahead of the process environment.

This matters concretely: the owner's Claude credentials already live in the macOS Keychain under
derived service names (`Claude Code-credentials-<8 hex>`). A pi `auth.json` can read them directly
with a `!security find-generic-password` line — no copying of secrets into config files. The
"cached for process lifetime" note also means a long-running session will not re-prompt Keychain
mid-run, which sidesteps the GUI-dialog hang the field scan flagged as an unattended-run risk.

### Switching a NEW session to a chosen account — YES

Set `PI_CODING_AGENT_DIR` (whole account), or `--provider` + `--api-key`, or a provider env var, at
spawn. All are launch-time, all are scriptable, none require a TTY.

### Changing a RUNNING session's account — NO

**VERIFIED by exhaustive review of the RPC command list.** RPC exposes `set_model`, `cycle_model`,
`get_available_models` — model switching, yes. There is **no** `set_provider_credential`,
`set_api_key`, `reload_auth` or equivalent. `auth.json` shell-command keys are explicitly *"cached
for process lifetime"*, so even rewriting the file under a live process changes nothing.

`set_model` with a different `provider` will use whatever credential that provider already resolves
to — so you can move a running session from Anthropic to Xiaomi if both are configured, but you
cannot move it from *Anthropic account A* to *Anthropic account B*.

**Workaround:** treat account as immutable per process. On exhaustion, abort, let the process exit,
relaunch with a different `PI_CODING_AGENT_DIR` and `--session <id>` from the identical cwd. Cost:
one process restart plus a context rebuild from the session file — and, because of the trap in axis
B, a hard requirement that the relaunch cwd matches byte-for-byte.

---

## G. INTERVENTION — *owner non-negotiable*

**The best answer in the field so far. This is the axis the current harness fails at, and pi solves it properly — in RPC mode only.**

### Send an instruction into a running session and know it arrived — YES

Three distinct delivery semantics, all **VERIFIED** in `docs/rpc.md`:

| Command | When it lands |
|---|---|
| `{"type":"prompt","message":…}` | Immediately, if idle. If streaming, **requires** `streamingBehavior` or it is **rejected with an error** |
| `{"type":"steer","message":…}` | After the current assistant turn finishes its tool calls, **before the next LLM call** |
| `{"type":"follow_up","message":…}` | Only once the agent has fully stopped |

Delivery pacing is itself controllable: `set_steering_mode` and `set_follow_up_mode` take `"all"` or
`"one-at-a-time"` (default `one-at-a-time`).

**Knowing it arrived is explicit**, and the semantics are stated with unusual care:

```json
{"id": "req-1", "type": "response", "command": "prompt", "success": true}
```

> `success: true` means the prompt was accepted, queued, or handled immediately. `success: false`
> means the prompt was rejected before acceptance. **Failures after acceptance are reported through
> the normal event and message stream, not as a second `response` for the same request id.**

Plus a `queue_update` event fires *whenever the pending queue changes*, echoing the full
`steering` and `followUp` arrays — so the supervisor gets unsolicited confirmation that its text is
queued, and can watch it drain. `clear_queue` returns the stranded text rather than discarding it:
`{"steering": ["Change direction"], "followUp": [...]}`.

**This is the direct answer to the harness field note about "a nudge that cannot submit stranded
text."** In pi, text is never stranded in an editor buffer: it is either accepted into a named queue
that the supervisor can read back, or explicitly rejected with `success: false`.

Also available: `abort` (*"Abort the current operation and wait for the session to become idle
before responding"* — it blocks until idle, so the response is a real quiescence signal), and
`abort_bash`.

### Answer a permission prompt or clarifying question programmatically — YES, via a sub-protocol

pi ships **no permission prompts of its own** (see H). But when an extension asks a question,
RPC turns it into a request/response pair over the same stdio channel.

**Dialog methods** — `select`, `confirm`, `input`, `editor` — emit on stdout and **block** until the
client answers on stdin with a matching `id`:

```json
{"type":"extension_ui_request","id":"uuid-1","method":"select",
 "title":"Allow dangerous command?","options":["Allow","Block"],"timeout":10000}
```

```json
{"type":"extension_ui_response","id":"uuid-1","value":"Allow"}
{"type":"extension_ui_response","id":"uuid-2","confirmed":true}
{"type":"extension_ui_response","id":"uuid-3","cancelled":true}
```

**Fire-and-forget methods** — `notify`, `setStatus`, `setWidget`, `setTitle`, `set_editor_text` —
emit but expect no reply.

An optional `timeout` (ms) on a dialog auto-resolves with a default if the client stays silent, and
the doc is explicit: *"The client does not need to track timeouts."* For an unattended queue that is
the right default — a supervisor crash degrades to a timeout, not a permanent hang.
`examples/extensions/timed-confirm.ts` demonstrates the pattern.

Crucially, `ctx.hasUI` is **`true`** in RPC mode, and `ctx.mode` is `"rpc"` — so an extension written
for the TUI generally keeps working under supervisor control without modification. Degraded in RPC:
`custom()` returns `undefined`, `getEditorText()` returns `""`, `setTheme()` fails, and
`setWorkingMessage`/`setFooter`/`setHeader` are no-ops. Anything built on `ctx.ui.custom()` — such as
the shipped `examples/extensions/question.ts` — **will not work** under RPC; it must be rewritten to
use `ctx.ui.select()`.

### The catch, stated plainly

**All of the above requires `--mode rpc`.** In print mode (`-p`) the prompt is fixed at launch and
there is no input channel at all. In TUI mode the only channel is keystroke injection. So the
orchestrator gets rich, confirmable, two-way intervention **or** a terminal the owner can type into —
not both on one process.

---

## H. GUARDRAILS

**pi's stated position is that it has none, on purpose. For an unattended overnight queue this is the most dangerous axis.**

`docs/security.md` (**VERIFIED**, verbatim): *"**No Built-in Sandbox.** Pi does not include a
built-in sandbox. Built-in tools can read files, write files, edit files, and run shell commands with
the permissions of the pi process. Extensions are TypeScript modules that run with the same
permissions."*

And `README.md:503`: *"**No permission popups.** Run in a container, or build your own confirmation
flow with extensions."*

**What pi will do unattended without asking: anything the shell can do, as the owner's user.**
There is no allowlist, no denylist, no `--dangerously-skip-permissions` equivalent because there is
nothing to skip. This is a deliberate, argued position — the doc explains that *"A partial in-process
sandbox would be easy to misunderstand as a security boundary"* — but it is the opposite of what an
overnight unattended run wants by default.

### What does exist

**1. Tool allow/deny at launch** (**VERIFIED**, `pi --help`) — this is the real guardrail:

| Flag | Effect |
|---|---|
| `--tools`, `-t <list>` | Strict **allowlist** across built-in, extension and custom tools |
| `--exclude-tools`, `-xt <list>` | **Denylist** |
| `--no-builtin-tools`, `-nbt` | Drop built-ins, keep extension/custom tools |
| `--no-tools`, `-nt` | Disable everything |
| `defaultTools` (settings.json) | Built-ins enabled at startup; `[]` means none |

Built-in tools: `read`, `bash`, `powershell` (Windows), `edit`, `write`, `grep`, `find`, `ls`.
Note `grep`, `find` and `ls` are **off by default** per `pi --help` ("read-only, off by default").
A genuine read-only run is one flag: `pi --tools read,grep,find,ls -p "Review the code in src/"`.

**2. Project trust — an input-loading guard, not a sandbox.** Controls whether `.pi/settings.json`,
`.pi/extensions|skills|prompts|themes`, `.pi/SYSTEM.md` and project `.agents/skills` are loaded.
Decisions are saved by canonical directory in `~/.pi/agent/trust.json` (lock-protected). The global
fallback is `defaultProjectTrust` ∈ `"ask"` (default) | `"always"` | `"never"`.

**The unattended semantics are exactly right** (**VERIFIED**, `docs/security.md`): *"Non-interactive
modes (`-p`, `--mode json`, and `--mode rpc`) do not show a trust prompt."* Without a saved decision,
`ask` and `never` **ignore** project resources; `always` trusts them. `--approve`/`-a` and
`--no-approve`/`-na` override for a single run. So an unattended run can never hang on a trust
dialog — it silently under-loads instead, which the orchestrator should detect via
`ctx.isProjectTrusted()` or by diffing `get_commands` against what it expected.

The doc is careful to say what trust is *not*: *"It does not make untrusted code, untrusted prompts,
or untrusted model output safe. Prompt injection from repository files … is expected local-agent risk
and cannot be reliably prevented by pi."*

**3. Hooks that can block a tool call.** `pi.on("tool_call", …)` can return
`{ block: true, reason: "..." }`. The shipped `examples/extensions/permission-gate.ts` is the
canonical pattern, and its non-interactive branch is the right default for a queue:

```typescript
if (isDangerous) {
  if (!ctx.hasUI) { return { block: true, reason: "Dangerous command blocked (no UI for confirmation)" }; }
  const choice = await ctx.ui.select(`⚠️ Dangerous command:\n\n  ${command}\n\nAllow?`, ["Yes", "No"]);
  if (choice !== "Yes") return { block: true, reason: "Blocked by user" };
}
```

Under `--mode rpc`, `ctx.hasUI` is true, so that `ctx.ui.select()` becomes an `extension_ui_request`
the **supervisor** answers — a policy engine with a human escalation path, in ~30 lines.
Related shipped examples: `protected-paths.ts`, `confirm-destructive.ts`, `dirty-repo-guard.ts`,
`timed-confirm.ts`, `sandbox/`, `gondolin/`.

**4. Real isolation, if you want it** (`docs/containerization.md`): four documented patterns —
**Gondolin** (host pi, built-in tools routed into a local Linux micro-VM; needs Node ≥ 23.6 and
QEMU), **plain Docker** (whole process; API keys enter the container), **NVIDIA OpenShell**
(policy-controlled sandbox, can keep raw keys outside via an `https://inference.local` route), and
**Docker Sandboxes** (`sbx`, whole process, credential kept on the host and substituted by a proxy on
egress to `api.anthropic.com`). `sbx exec <name> -- pi -p "list the failing tests"` is a documented
scripted entry point. All are **CLAIMED** — documented but not tested here.

**Bottom line for the owner's use case:** pi unattended on a real source tree with no extension and no
container is a shell with a language model attached. The cost of using it safely is either a
container (operational weight, credential plumbing) or a hand-written permission-gate extension
(~30–100 lines, plus the supervisor logic to answer its dialogs).

---

## I. EXTENSIBILITY

**Exceptional — the deepest extension surface in this scan — with one hard exclusion.**

### MCP — NO

Already covered above; repeating because the field scan got it wrong. No MCP, by design, with a
linked rationale post. The workaround pi proposes is skills wrapping plain CLI tools. Cost for this
owner: **substantial.** His environment leans on MCP servers (`slack-user`, `n8n-mcp`, `sentry`,
`clickup`, `figma`, Playwright). None of them reach pi without either an MCP-bridge extension
someone has to write, or CLI equivalents.

### Skills — YES, and they are directly compatible with what the owner already has

pi implements the [Agent Skills standard](https://agentskills.io/specification) (**VERIFIED**,
`docs/skills.md`), loading from `~/.pi/agent/skills/`, `~/.agents/skills/`, project `.pi/skills/` and
`.agents/skills/` (walking up to the git root), packages, the `skills` settings array, and repeatable
`--skill <path>`. Skills register as `/skill:name`.

**The doc explicitly supports borrowing Claude Code's skills**, verbatim:

```json
{ "skills": ["~/.claude/skills", "~/.codex/skills"] }
```

under the heading *"Using Skills from Other Harnesses"*. pi even relaxes one spec rule for this
reason — it allows a skill name to differ from its directory because *"that rule is suboptimal for
shared skill directories used across multiple agent harnesses."* For a provider-agnostic
orchestrator, this is the single most portable asset the owner owns: his ~90 skills in
`~/.claude/skills` are loadable by pi with a one-line setting.

`CLAUDE.md` is also read directly as a context file, alongside `AGENTS.md`, with
`AGENTS.override.md` taking precedence in a directory and `--no-context-files`/`-nc` to disable.

### Sub-agents — not built in, but a complete worked example ships

`README.md:501`: *"**No sub-agents.** There's many ways to do this. Spawn pi instances via tmux, or
build your own with extensions."*

`examples/extensions/subagent/` is a full implementation (35 KB `index.ts` plus `agents.ts`, four
agent definitions — `scout`, `planner`, `reviewer`, `worker` — and three workflow presets:
`implement.md` = scout → planner → worker, `scout-and-plan.md`, `implement-and-review.md`). Its
README claims: *"Isolated context: each subagent runs in a separate `pi` process"*, streaming output,
parallel streaming, per-agent **usage tracking (turns, tokens, cost, and context usage)**, and
Ctrl+C abort propagation.

**So a GSD-style, subagent-heavy workflow engine can run inside pi**, but as *spawned sibling
processes*, not an in-process primitive. That is architecturally the same thing the orchestrator
already does with terminals — which makes it a natural fit rather than an impedance mismatch — but
it means every agent definition, dispatch rule and result-merge is the orchestrator's code to write
and own.

### Extension API surface

Events (from `docs/extensions.md` §Events): startup, resource, session
(`session_start`, `session_before_compact`, `session_compact_failed`, `session_before_tree`,
`session_before_switch`, `session_before_fork`, `session_shutdown`, `project_trust`), agent
(`before_agent_start`, `before_provider_headers`, `before_provider_request`,
`after_provider_response`, `turn_end`, …), model, tool (`tool_call`, `tool_result`), user-bash, and
input events.

`ExtensionContext`: `ui`, `mode`, `hasUI`, `cwd`, `isProjectTrusted()`, `sessionManager`,
`modelRegistry`/`model`/`thinkingLevel`/`scopedModels`, `signal`, `isIdle()`/`abort()`/
`hasPendingMessages()`, **`shutdown()`**, **`getContextUsage()`**, **`compact()`**,
`getSystemPrompt()`.

`ExtensionAPI`: `on`, `registerTool`, `sendMessage`, `sendUserMessage`, `appendEntry`,
`setSessionName`, `setLabel`, `registerCommand`, `getCommands`, renderers, `registerShortcut`,
**`registerFlag`** (extensions add their own CLI flags), `exec`, `getActiveTools`/`setActiveTools`,
`setModel`, `get`/`setThinkingLevel`, `events`, **`registerProvider`**/`unregisterProvider`.

`ctx.shutdown()` deserves a callout for unattended use: *"RPC mode: deferred until the next idle
state."* A graceful stop that does not truncate a turn — which is what a rate-limit pause or a STOP
signal needs.

Extensions are TypeScript, loaded via `jiti`, from `~/.pi/agent/extensions/`, `.pi/extensions/`,
`-e/--extension <path|npm|git>` (repeatable), or packages. `--no-extensions`/`-ne` disables
discovery while explicit `-e` still loads — a clean way for the orchestrator to pin exactly its own
extension set and ignore whatever the owner has installed.

### Packages, providers, config precedence

`pi install npm:@foo/bar | git:github.com/user/repo | https://… | ./local/path`, `-l` for
project-local; `pi list`, `pi config`, `pi update [--self|--extensions|--models|--all]`.

`pi.registerProvider(name, config)` plus `models.json` lets pi talk to Ollama, LM Studio, vLLM or
any endpoint speaking OpenAI Completions, OpenAI Responses, Anthropic Messages or Google Generative
AI — with `custom-provider.md` (777 lines) and two worked examples
(`custom-provider-anthropic`, `custom-provider-gitlab-duo`).

Config precedence (**VERIFIED**, `docs/settings.md`): project `.pi/settings.json` overrides
`~/.pi/agent/settings.json`, with nested objects **merged**. Resource paths resolve relative to the
settings file's own directory. Arrays support globs, `!pattern` exclusions, `+path` force-include,
`-path` force-exclude.

There is also an **SDK** (`docs/sdk.md`, 1224 lines) — `AgentSession` imported directly from
`@earendil-works/pi-coding-agent`. For a Node/TypeScript orchestrator this removes the subprocess
boundary entirely. The docs recommend it over spawning: *"If you're building a Node.js application,
consider using `AgentSession` directly … instead of spawning a subprocess."*

A source-only **experimental remote harness** exists (`PI_EXPERIMENTAL=1 ./pi-test.sh server|client`,
`PI_SERVER_DIR`, `PI_SERVER_ID`) but is **explicitly excluded from npm packages and standalone
binaries** (`docs/development.md`). Not available to this orchestrator today.

**Rebranding note:** `piConfig` in `package.json` lets a fork change `name`, `configDir` and `bin`,
which changes config paths and env-var names. Extensions should use the exported `CONFIG_DIR_NAME`
rather than hardcoding `.pi`. An orchestrator hardcoding `~/.pi/agent` is making an assumption that
pi itself treats as configurable.

---

## J. OPERATIONAL REALITY

### Install footprint

| Fact | Value | Tag |
|---|---|---|
| Install | `npm install -g @earendil-works/pi-coding-agent` | VERIFIED |
| Binary | `pi` → `dist/bundle/cli.js` | VERIFIED (npm `bin`) |
| Unpacked size | **21.9 MB**, 1056 files | VERIFIED (npm `dist`) |
| Declared engine | `node >=22.19.0` | VERIFIED (`engines`) |
| Runtime deps | 15, incl. `undici`, `typebox`, `jiti`, `proper-lockfile`, `@earendil-works/{chord,pi-ai,pi-tui,pi-agent-core}` | VERIFIED |
| Provenance | npm attestation present, SLSA v1 predicate | VERIFIED |
| Legacy tag | `legacy-node20` → `0.74.2` for Node 20 | VERIFIED |

**A local gotcha.** This machine's nvm default is **v22.18.0** — one patch *below* the declared
`>=22.19.0`. In practice it runs (`node v22.18.0 … --version` → `0.85.1`, **VERIFIED**), because npm
`engines` is advisory without `engine-strict`. But `/usr/local/bin/node` is **v18.17.1**, and that
one will not. A daemon-spawned session inheriting a minimal `PATH` can easily pick up the v18 binary.
**The orchestrator should launch pi with an absolute path to a known-good Node**, not rely on `PATH`.
I used `~/.nvm/versions/node/v24.18.0/bin/node` throughout this pass.

**Do not run pi from an unpacked tarball.** `npm pack` + extract fails at runtime because the bundle
imports `@earendil-works/chord`. pi must be *installed*, not unpacked.

### Platform support

macOS: yes, primary. Also documented: Windows (`docs/windows.md`, `powershell` tool, shell-path
settings), Termux (`docs/termux.md`), llama.cpp local models (`docs/llama-cpp.md`).
Terminal specifics in `docs/terminal-setup.md` — inline images work in Kitty/Ghostty via the Kitty
graphics protocol; in iTerm2 fullscreen mode they degrade to text placeholders.

### Maturity

Pre-1.0 (**0.85.1**) but with a strong maintenance signal: 45 releases since 2026-05-07, weekly
cadence, pushed yesterday, MIT, 107k stars, 222 open issues. Version-number risk is real — a `0.x`
project can break flags between minors, and this one ships often. **The orchestrator must pin the pi
version and re-verify its adapter on upgrade.** `pi update --self` exists and should be disabled or
gated in an unattended context.

### Known and suspected unattended-run failure modes

| # | Failure | Severity | Evidence |
|---|---|---|---|
| 1 | **Session never written to disk** before the first assistant message — startup-window crashes leave no trace | **High** | VERIFIED in source + execution (axis B) |
| 2 | **`--session-id` miss silently forks a new empty session**, warning only on stderr | **High** | VERIFIED by execution (axis B) |
| 3 | **No account switch on a live session** — exhaustion forces a process restart | **High** | VERIFIED (axis F) |
| 4 | **No quota read** — the orchestrator cannot pace itself, only react to a 429 | **High** | VERIFIED (axis E) |
| 5 | **`retry.provider.maxRetries > 0` can block until the provider quota resets** | **High** | VERIFIED — documented warning (axis E) |
| 6 | **No sandbox and no permission prompts** — full shell access unattended | **High** | VERIFIED (axis H) |
| 7 | **RPC exits on stdin EOF without draining in-flight async commands** — a `bash` command written just before EOF produced no response and no session entry | Medium | VERIFIED by execution; fixed by holding stdin open |
| 8 | **Concurrent processes on one session file are unarbitrated** (no lockfile on sessions) | Medium | VERIFIED in source (axis B) |
| 9 | **Cross-directory `--session` resume prompts and aborts** with no TTY | Medium | VERIFIED by execution (axis B) |
| 10 | **A failed run still appends to the session** — a no-credential `-p` run added a `thinking_level_change` entry | Low | VERIFIED by execution |
| 11 | **`contextUsage` is absent with no model and null right after compaction** — must not be read as zero | Low | VERIFIED in docs (axis D) |
| 12 | **Provider headers may be unavailable** on some providers/transports, breaking the axis-E workaround | UNKNOWN per provider | Documented caveat |

### Can it plausibly run overnight unattended today?

**Yes — with an adapter and two accepted risks.**

What makes it plausible, and better than most of this field: RPC gives real two-way control with
confirmed delivery; context is readable and compactable from outside with durable proof; the
transcript is a well-specified, cursor-addressable, append-synchronous JSONL; failures exit non-zero
with clean stdout; `ctx.shutdown()` is a graceful, idle-deferred stop; and `PI_CODING_AGENT_DIR`
makes per-account isolation a one-variable spawn concern.

The two risks that do not go away:
1. **Quota is unmanageable.** Without a capacity read, an overnight queue cannot pace itself. It can
   only run until a 429 and then parse an English sentence for a reset time. On a Claude
   subscription it additionally bills **per token as extra usage**, so "run until the limit" has no
   natural stopping point — it just costs money.
2. **No guardrails by default.** Unattended pi on a real repo has unrestricted shell access. This
   needs a container or a permission-gate extension before it runs against anything the owner cares
   about.

---

## What this costs the orchestrator

Ordered by cost, highest first.

**1. A quota strategy that pi cannot provide — the largest single cost.**
Write an `after_provider_response` extension per provider family to capture rate-limit headers, plus
a regex over the limit-hit prose, plus per-provider verification that headers are exposed at all.
None of it is portable across providers, and all of it is one upstream wording change from silent
failure. **Plus a budget model the owner does not currently have**: his `claude-limits` discipline
measures a plan quota that pi does not consume, so pi-on-Anthropic needs *spend* tracking rather than
*utilization* tracking. Realistically the safest short-term policy is to run pi only on
per-token/token-plan providers (Xiaomi MiMo SGP, Kimi, GLM, OpenRouter) where cost is explicit and
the subscription-quota question does not arise.

**2. Choosing between supervision and attachability — an architectural cost, not a code cost.**
RPC and TUI are mutually exclusive on one process. Every capability in axes D and G exists **only**
under `--mode rpc`, where the owner cannot attach and type. If attachability is non-negotiable, the
orchestrator must build its own viewer over the session JSONL and the event stream, and accept that
"the owner takes over this session by typing into it" becomes "the owner sends a steer through the
orchestrator." That is arguably better, but it is the orchestrator's UI to build.

**3. Guardrails, from zero.** Either a container (Gondolin/Docker/`sbx` — credential plumbing,
operational weight, four documented patterns none of which is tested here) or a permission-gate
extension plus the supervisor-side policy that answers its `extension_ui_request` dialogs. ~30–100
lines for the extension; more for the policy. Non-optional before pointing pi at a real repo
unattended.

**4. MCP loss.** Every MCP server the owner depends on is unreachable from pi. Either an MCP-bridge
extension (nobody has written one; `registerTool` makes it feasible) or CLI equivalents wrapped as
skills. Note the offset: his `~/.claude/skills` are loadable by pi with one settings line, so *skills*
port for free — it is only *MCP tools* that do not.

**5. Session-identity discipline.** Enforce one writer per session (no lockfile on session files);
relaunch from a byte-identical cwd; use `--session-id` to create and `--session` to resume; parse
stderr for the silent-fork warning; and treat "no session file exists" as a distinct, expected state
meaning "died before first assistant message" rather than an error.

**6. Per-account process lifecycle.** Account is immutable per process, so switching means abort →
exit → relaunch with a new `PI_CODING_AGENT_DIR` and `--session <id>`. Cheap to implement, but it
makes "rotate accounts when one is exhausted" a restart-and-rebuild operation rather than a
reconfiguration.

**7. RPC client correctness — small, but a real trap.** Strict LF-only JSONL framing. The docs warn
explicitly that **Node's `readline` is not protocol-compliant** because it also splits on `U+2028`
and `U+2029`, which are legal inside JSON strings. Hold stdin open (finding #7 above). Use the
documented manual buffer-splitting reader.

**8. Version pinning.** A `0.x` on a weekly cadence. Pin the version, disable `pi update --self` in
unattended contexts, re-verify the adapter on upgrade, and launch with an absolute path to a
known-good Node binary rather than trusting `PATH`.

### What pi gives back, and why it is worth reading even if it is never used

pi is the reference implementation for the two axes the current harness fails at. `--session-id`
names a session **before it exists**, which removes id-scraping entirely. RPC answers "send an
instruction and know it arrived" with id-correlated responses, named queues, `queue_update`
echoes, and a `clear_queue` that hands stranded text *back* instead of losing it. `get_session_stats`
answers "how full is the context" with the same number the compactor acts on, and `compact` leaves
proof in three places, one of them durable on disk. `get_entries { since }` is a durable cursor over
an append-only tree.

**Even if pi is never adopted as an executor, its protocol is the right shape to copy** — and it is
MIT-licensed, so it can be copied.

---

## Sources

All consulted **2026-09-19**. Primary sources only; no comparison blogs were used.

**Executed on this machine** (sandboxed `HOME`, `PI_CODING_AGENT_DIR`, and cwd; no owner config
touched; no LLM request made; no owner quota spent):
- `pi --version` → `0.85.1`; `pi --help`; `pi auth --help`; `pi update --help`; `pi install --help`; `pi list --help`
- `pi auth check --provider anthropic --json` → `{"status":"not_ready","provider":"anthropic","reason":"credentials_not_configured"}`
- `pi --mode rpc --session-id … --offline` driven over a held-open stdin pipe: `get_state`, `get_session_stats`, `get_entries`, `get_commands`, `bash`, `get_last_assistant_text`
- `pi -p` / `--mode json` with and without credentials; exit codes captured without a pipe
- `--session-id` vs `--session` resolution, same cwd and different cwd; synthetic session file resume; concurrent same-session launch
- `pi --list-models --offline`; pi under node v22.18.0 and v24.18.0

**Shipped docs read in full or in part** (in the published package under `docs/`, 12,580 lines total):
`rpc.md` (1618), `compaction.md` (418), `session-format.md` (438), `sessions.md` (145), `usage.md` (311),
`settings.md` (369), `providers.md` (317), `security.md` (59), `json.md` (98),
`environment-variables.md` (99), `containerization.md` (156), `tmux.md` (63), `skills.md` (232),
`development.md` (90), plus `extensions.md` (3023) §Events / §ExtensionContext / §ExtensionAPI.

**Shipped source read** (unminified, in `dist/`):
`core/session-manager.js` (`_persist`, `_appendEntry`, session file naming),
`main.js` (`findLocalSessionByExactId`, `resolveSessionPath`, session resolution),
`bundle/chunks/openai-codex-responses-*.js` (`parseErrorResponse`, `resets_at` handling),
`core/auth-storage.js`, `core/settings-manager.js`, `core/trust-manager.js` (lockfile usage).

**Shipped examples read:** `provider-payload.ts`, `permission-gate.ts`, `trigger-compact.ts`,
`question.ts`, `qna.ts`, `handoff.ts`, `subagent/README.md`.

**Registries and APIs, queried today:**
- npm registry — `npm view @earendil-works/pi-coding-agent --json` (versions, `time`, `bin`, `engines`, `dependencies`, `dist`, attestations)
- GitHub API — `gh api repos/earendil-works/pi` (stars, forks, license, dates, archived) and `/releases`

**Not verified / open questions:**
- Whether `after_provider_response` exposes usable rate-limit headers for Anthropic, Xiaomi MiMo, Kimi or GLM specifically (**UNKNOWN** — requires a live credential per provider)
- All four containerization patterns (**CLAIMED**, documented but untested here)
- Whether the `subagent` example scales to a GSD-shaped workflow (**UNKNOWN** — not executed)
- Behaviour of `--mode rpc` under a real provider outage mid-turn (**UNKNOWN** — no live run was made)
- Armin Ronacher as co-author: asserted by one blog post, **not** confirmed in repo metadata (**CLAIMED**)
