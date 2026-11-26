# Cursor CLI (`cursor-agent` / `agent`) — orchestrator platform profile

**Date of research:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0).
**Scope:** Cursor CLI as an *agent platform a provider-agnostic orchestrator must drive*, measured
against axes A–J from `round-1/ANALYSIS-01.md`. Companion to `00-field-scan.md`.

**Evidence tags:** **VERIFIED** — read in official docs, read in the installed binary's own source,
or run on this machine. **CLAIMED** — asserted by a changelog, marketing page or third party,
not independently confirmed. **UNKNOWN** — could not be established in this pass.

---

## 0. Bottom line

Cursor CLI is, on paper, the **second-most orchestrable platform in this scan after Claude Code**,
and on two axes it is the *best* in the field:

- **Axis G (intervention)** is fully solved, twice over. `agent acp` is a JSON-RPC 2.0 server over
  stdio where the agent's own questions arrive as **blocking requests the supervisor answers
  programmatically** (`cursor/ask_question`, `cursor/create_plan`, `session/request_permission`).
  The TypeScript/Python SDK adds `run.steer(text)`, which injects a message into a turn already in
  flight and **returns whether it landed** (`complete_delivered` vs `revert_to_followup`). No other
  platform in this scan reports delivery.
- **Axis H (guardrails)** is the most granular surface seen: typed permission tokens
  (`Shell(...)`, `Read(...)`, `Write(...)`, `WebFetch(...)`, `Mcp(server:tool)`), three run modes,
  an OS-level sandbox (seatbelt on macOS) with a network allowlist, and 18 hook events.

Two axes are hard failures:

- **Axis E (quota)** — there is **no programmatic read of remaining capacity for an individual
  plan.** Usage is a monthly billing-cycle pool, readable in the web Spending dashboard or the
  interactive `/usage` slash command. The Admin API's `/teams/spend` is **Enterprise-teams only**.
  This is the owner's first non-negotiable, and Cursor does not meet it.
- **Axis D (compaction from outside)** — a supervisor can *read* context fullness and *observe*
  compaction with proof, but **cannot trigger it**. `/summarize` is an interactive slash command
  only; `preCompact` is explicitly observational and "cannot block or modify the compaction
  behavior".

And one fact dominates everything below: **the copy installed on this machine is a year old and
not logged in.** Nothing in this profile can be exercised here without the owner installing a
current build and authenticating.

---

## 0.1 What is actually installed here (VERIFIED, 2026-09-19)

| Fact | Value |
|---|---|
| Binary | `/Users/sasha-marchuk/.local/bin/cursor-agent` → `/Users/sasha-marchuk/.local/share/cursor-agent/versions/2025.09.12-4852336/cursor-agent` |
| `cursor-agent --version` | `2025.09.12-4852336` |
| Current build served by the installer | `2026.09.18-9a7762b` (read from `https://cursor.com/install`, the literal `DOWNLOAD_URL` is `https://downloads.cursor.com/lab/2026.09.18-9a7762b/${OS}/${ARCH}/agent-cli-package.tar.gz`) |
| Age of local install | **372 days** |
| `cursor-agent status` | `Not logged in` — **and it exits 0 anyway** |
| Keychain | no `cursor-*-access-token` entry exists; only the IDE's `Cursor Safe Storage` |
| Config present | `~/.cursor/cli-config.json` = `{"version":1,"editor":{"vimMode":false},"hasChangedDefaultModel":false,"permissions":{"allow":["Shell(ls)"],"deny":[]}}` |
| Cursor IDE state present | `~/.cursor/{extensions,plugins,projects,skills-cursor,snapshots,mcp.json,ai-tracking}` — the desktop app is in active use (`skills-cursor/` and `projects/` last written 2026-09-01) |

**The stale binary's help output is not the current flag surface.** `cursor-agent --help` on this
build lists only `--api-key --print --output-format --background --fullscreen --resume --model
--force`, and the commands `install-shell-integration login logout mcp status update create-chat
agent ls resume`. Everything in this profile marked *current* comes from the live docs, not from
that binary. **Any capability test must re-record the version first.**

> **First gotcha for a supervisor:** `cursor-agent status` prints `Not logged in` and **returns
> exit code 0** (VERIFIED, run here). A preflight that checks `$?` will conclude the platform is
> healthy when it has no credentials at all. Parse `agent status --format json` instead
> (VERIFIED in docs: `status`/`whoami` and `about` take `--format text|json`).

**Naming.** The installer creates **both** symlinks and the docs have switched to the short one
(VERIFIED, read from the install script):

```bash
command rm -f ~/.local/bin/agent ~/.local/bin/cursor-agent
# Create symlinks to the Cursor Agent executable (primary: agent, legacy: cursor-agent)
ln -s ~/.local/share/cursor-agent/versions/2026.09.18-9a7762b/cursor-agent ~/.local/bin/agent
ln -s ~/.local/share/cursor-agent/versions/2026.09.18-9a7762b/cursor-agent ~/.local/bin/cursor-agent
```

An orchestrator should invoke **`cursor-agent`**: it is the legacy name, still created, and it does
not collide with anything. All official docs say `agent`; both resolve to the same executable.

**One inconsistency to not trip on:** `cli/installation.md` tells you to add `~/.local/bin` to
`PATH`; `cli/github-actions.md` tells CI to add `$HOME/.cursor/bin`. The install script only ever
writes to `~/.local/bin` (VERIFIED). The GitHub Actions snippet appears to be **wrong or stale**.

---

## A. LAUNCH

### Headless (VERIFIED — `cursor-agent --help` on the stale build, plus `cli/reference/parameters.md`)

```bash
agent -p "prompt"                                   # print mode
agent -p --output-format text|json|stream-json "…"  # default: text
agent -p --output-format stream-json --stream-partial-output "…"
agent -p --force "…"          # or --yolo; without it, "changes are only proposed, not applied"
agent -p --trust "…"          # trust the workspace without prompting
agent --mode plan|ask "…"     # --plan is shorthand for --mode=plan
agent --model <id>            # --list-models to enumerate
agent --workspace <path>      # explicit repository root
agent -w|--worktree [name]    # run in a fresh worktree under ~/.cursor/worktrees/<repo>/<name>
```

`--output-format` "is only valid when printing (`--print`) or when print mode is inferred
(non-TTY stdout or piped stdin)" (VERIFIED). **Print mode is inferred when stdout is not a TTY** —
which is exactly how a supervisor spawns it, so `-p` is effectively implicit but should be passed
anyway.

The three output modes (VERIFIED, `cli/reference/output-format.md`):

- **`text`** — final assistant message only.
- **`json`** — one object on success: `{type:"result", subtype:"success", is_error:false,
  duration_ms, duration_api_ms, result, session_id, request_id?}`. **On failure "the process exits
  with a non-zero code and writes an error message to stderr. No well-formed JSON object is
  emitted in failure cases."** A supervisor that only parses stdout learns nothing about why a run
  died.
- **`stream-json`** — NDJSON. Event types `system`(`subtype:"init"`, carrying `apiKeySource`,
  `cwd`, `session_id`, `model`, `permissionMode`), `user`, `assistant`, `tool_call`
  (`subtype:"started"|"completed"`, correlated by `call_id`), and a terminal `result`. **Every
  event carries `session_id`.** `thinking` events are suppressed in print mode.

Per the changelog (2026-02, CLAIMED — not in the reference page I read): stream-json also carries
"per-turn input/output/cache token totals and a `request_id`".

### Visible terminal the owner can attach to

`agent` with no flags is a full interactive TUI. Two features matter here:

- **`agent persist`** (CLAIMED, changelog 2026-08-26, **not in any reference doc**): "Start a
  persistent session with `agent persist`, detach with `/detach`, and reconnect later with
  `agent persist attach`. Use `agent persist list|stop` to manage sessions or
  `agent persist --resume` to continue an existing chat." If real, this is the single most useful
  launch primitive in the field for this orchestrator — a detachable, reattachable, listable
  session without tmux. **It is absent from `cli/reference/parameters.md`, so treat the exact
  subcommand names as unverified until run against a current build.**
- **`-b, --background`** exists on the stale build ("Start in background mode (open composer picker
  on launch)") and has been **dropped from the current parameter reference** (VERIFIED by absence).

### ACP (VERIFIED, `cli/acp.md`)

```bash
agent acp                              # JSON-RPC 2.0, newline-delimited, over stdio
agent --api-key "$CURSOR_API_KEY" acp
agent -e https://api2.cursor.sh acp    # endpoint override
agent -k acp                           # TLS option
```

`acp` is a **hidden command** ("hidden from default command help output" — VERIFIED). It is the
richest launch surface and is covered under G.

### Verdict

Headless: **yes, first-class.** Visible/attachable: **yes** (TUI; `persist` if it exists as
documented). Structured output: **yes, three formats, session-id on every event.**

---

## B. IDENTITY & RESUME

**The orchestrator can name a session before it exists — indirectly.** There is no `--session-id`
flag. Instead (VERIFIED, `cli/reference/parameters.md`):

```bash
agent create-chat        # "Create a new empty chat and return its ID"
agent --resume <chatId>  # resume that exact chat
agent --continue         # alias for --resume=-1 — the previous session
agent resume             # resume the latest chat
agent ls                 # browse/select previous chats
```

So the contract is: **`create-chat` → capture id → `-p --resume <id>` for every turn.** That gives
the orchestrator a stable, pre-allocated handle, the same guarantee pi gets from `--session-id`,
one extra process invocation.

Failing that, the id arrives in the first `system`/`init` event of `stream-json` and on every
subsequent event as `session_id` (VERIFIED). Interactively there is `/copy-conversation-id`.

**What survives a crash.** Conversation state lives **server-side** — `agent ls` and `--resume`
work "across workspaces" and "resuming one loads the full conversation" (CLAIMED, changelog
2026-07-06: "Resume chats from any directory… `agent ls`, `agent --resume`, and `/resume` open All
chats across workspaces by default"). This is the opposite trade to Claude Code: a local disk wipe
does not lose the chat, but a **Cursor outage means no resume at all** — the ids are not
self-sufficient local files.

For SDK-driven runs the story is stronger and local (VERIFIED, `sdk/typescript.md`):
`Agent.resume(agentId)` "from a brand-new process picks up where the previous one left off";
runtime is auto-detected from the id prefix (`bc-` = cloud, anything else = local); local state is
a checkpoint store, **on-disk SQLite by default**, swappable for `JsonlLocalAgentStore` which
writes `agents.ndjson`, `runs.ndjson`, `run_events.ndjson`, `checkpoints.ndjson` into a directory
you choose.

**Caveat on resume (VERIFIED):** "Inline `mcpServers` are not persisted across resume — they often
carry secrets and live in memory only. Pass them again on resume." And `agent.model` is `undefined`
on resume unless re-passed.

### Verdict

**Exact resume: yes**, by pre-allocated id. **Crash-survivable: yes for the transcript, no if the
provider is down.** Reboot-survivable: yes (ids are server-side). Best in class for an
orchestrator that restarts its own process.

---

## C. TRANSCRIPT

There are **three** transcript surfaces and they are not the same thing.

**1. The live NDJSON stream (VERIFIED).** `-p --output-format stream-json` is the supervisor's
primary read. It is complete enough to judge progress: tool calls with args and results, assistant
messages, a terminal `result` with `duration_ms`.

**2. An on-disk transcript file (partially VERIFIED, path UNKNOWN).** Both the hooks payload and
the statusline payload hand the supervisor a path rather than documenting one:

- hooks common schema: `"transcript_path": "string | null"` — *"Path to the main conversation
  transcript file (null if transcripts disabled)"* (VERIFIED, `hooks.md`)
- hook environment: `CURSOR_TRANSCRIPT_PATH`, present "If transcripts enabled" (VERIFIED)
- statusline payload: `transcript_path`, plus `workspace.project_dir` described as *"Directory
  where transcripts are stored"*, whose example value is `/Users/me/project/.cursor/transcripts`
  (VERIFIED as text, read from `~/.cursor/skills-cursor/statusline/SKILL.md` shipped by Cursor on
  this machine — but it is an *example*, not a stated default)
- changelog 2026-02: *"headless transcripts write Claude Code-compatible JSONL"* and
  *"transcripts persist to disk for tooling and hooks"* (CLAIMED)

**The exact default path is UNKNOWN** and there is a documented switch ("transcripts disabled")
whose name and location I could not find. **The correct orchestrator design is therefore to not
guess it:** install a `sessionStart` hook or a `statusLine` command, read `transcript_path` out of
the payload it is handed, and record it against the session id. That is a documented field, not a
guessed path.

**What is *not* there.** On this machine `~/.cursor/projects/<slug>/` contains only `mcps/`,
`canvases/`, `terminals/`, `rules/` — **no chat or transcript files at all** (VERIFIED,
`find`). The slug rule is confirmed in the installed binary's own source:

```js
function H(){let q=process.env.CURSOR_CONFIG_DIR;if(q&&q.trim())return q;let B=process.env.XDG_CONFIG_HOME;if(B&&B.trim())return z(B,"cursor");return z(E(),".cursor")}
function I(){let q=process.env.CURSOR_DATA_DIR;if(q&&q.trim())return q;return z(E(),".cursor")}
function J(){return z(I(),"projects")}
function K(q){return q.replace(/[^a-zA-Z0-9]/g,"-").replace(/-+/g,"-").replace(/^-+|-+$/g,"")}
function Q(){return z(H(),"cli-config.json")}
```

(VERIFIED — `index-wgf8x11r.js` in the 2025.09.12 install. Data dir → `projects/` → per-workspace
slug with every non-alphanumeric turned into `-`; config dir → `cli-config.json`.)

**3. SDK stores (VERIFIED).** `JsonlLocalAgentStore` writing four NDJSON files to a directory the
orchestrator picks is the cleanest live-readable transcript in this whole scan — the supervisor
chooses the path instead of discovering it.

### Verdict

**Live read: excellent** (NDJSON on stdout, or SDK NDJSON files at a path you choose).
**On-disk CLI transcript: exists, path must be discovered at runtime, not assumed.**

---

## D. CONTEXT — read yes, trigger no

### Reading context fullness from outside: **two documented ways, both good.**

**1. The statusline command.** Add to `~/.cursor/cli-config.json` (VERIFIED, from the
Cursor-shipped `~/.cursor/skills-cursor/statusline/SKILL.md`):

```json
{ "statusLine": { "type": "command", "command": "~/.cursor/statusline.sh", "padding": 2 } }
```

The command is spawned on each conversation update with a JSON payload on **stdin** containing:

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/Users/me/project",
  "autorun": false,
  "model": { "id": "…", "display_name": "…", "max_mode": true },
  "workspace": { "current_dir": "…", "project_dir": "…/.cursor/transcripts", "added_dirs": [] },
  "version": "1.2.3",
  "context_window": {
    "total_input_tokens": 15234,
    "total_output_tokens": null,
    "context_window_size": 200000,
    "used_percentage": 34.5,
    "remaining_percentage": 65.5,
    "current_usage": null
  },
  "worktree": { "name": "…", "path": "…" }
}
```

`updateIntervalMs` defaults to 300 and is clamped to ≥300ms; `timeoutMs` defaults to 2000; "the
status line runs locally and does not consume API tokens". **A three-line shell script that dumps
this payload to `/tmp/cursor-ctx-$session_id.json` gives the supervisor a live, sub-second
context-fullness feed plus the session id plus the transcript path.** This is the single most
useful integration point on the whole platform, and it is the same contract as Claude Code's
status line (the skill says so explicitly).

Caveats (VERIFIED): `used_percentage` / `remaining_percentage` "may be null early in the session";
`current_usage` is null before the first API call; if the command exits non-zero with empty stdout
the previous text is kept; in-flight processes are killed on the next update.

**2. The `preCompact` hook** (VERIFIED, `hooks.md`) — input:

```json
{ "trigger": "auto" | "manual", "context_usage_percent": 85, "context_tokens": 120000,
  "context_window_size": 128000, "message_count": 45, "messages_to_compact": 30,
  "is_first_compaction": true }
```

That is **proof that compaction happened**, with the numbers, timestamped by the hook firing, and
it tells you whether it was `auto` or `manual`. Better proof than anything in the current harness.

Interactively there is also `/context` — "Visualize what's consuming the context window, broken
down by category" (CLAIMED, changelog 2026-06-09).

### Triggering compaction from outside: **not supported.**

- `/summarize` (aliases `/compress`, `/compact`) is an **interactive slash command** (VERIFIED,
  `cli/reference/slash-commands.md`). There is no `--summarize` flag, no `agent compact`
  subcommand, and no ACP or SDK method for it. I could not find one and **will not guess a flag
  name.**
- `preCompact` is explicitly *"an observational hook that cannot block or modify the compaction
  behavior"* (VERIFIED).
- The SDK exposes compaction only as *output*: `SummaryStartedUpdate` / `SummaryUpdate` /
  `SummaryCompletedUpdate` in the `InteractionUpdate` stream (VERIFIED). You can watch it; you
  cannot call it.

**Closest workaround, and what it costs.** Three options, in order of cleanliness:

1. **Send `/summarize` as a prompt.** Over ACP `session/prompt`, or as a `stop`-hook
   `followup_message`, submit the literal text `/summarize`. **Whether the CLI resolves slash
   commands arriving as programmatic prompt text is UNKNOWN** — the slash palette is a TUI
   affordance and there is no statement either way. If it works, this is a one-line answer; it must
   be tested against a live build before being relied on. Cost if it fails: silent — the agent
   receives "/summarize" as a literal user message and answers it in prose.
2. **Let auto-compaction do it and just detect it.** Watch `preCompact`. Cost: the orchestrator
   loses the ability to compact *before* a risky long step; it only learns afterwards.
3. **Hand off instead of compacting.** Watch `context_window.used_percentage` from the statusline;
   at a threshold, stop the session, `create-chat` a fresh one, and seed it with a written handoff.
   Cost: one extra full-context read to write the handoff, and the new chat has a different id — so
   the orchestrator's ticket→session mapping must be one-to-many.

Option 3 is the honest design. **This axis is a stated non-negotiable and Cursor half-fails it:
perfect observation, zero external control.**

---

## E. QUOTA — the hard failure

### What exists

| Surface | What it gives | Who can use it |
|---|---|---|
| `/usage` slash command | "your account's included-usage meters with Auto and API breakdowns, on-demand spend against your limit, plan name, and **billing-cycle reset date**" (CLAIMED, changelog 2026-07-13) | interactive TUI only |
| `cursor.com/dashboard/spending` | "real-time usage for both pools, remaining allowance, and any on-demand charges" (VERIFIED, `help/models-and-usage/usage-limits.md`) | browser |
| `POST https://api.cursor.com/teams/spend` | per-member `spendCents`, `overallSpendCents`, `monthlyLimitDollars`, `effectivePerUserLimitDollars`, `hardLimitOverrideDollars` (VERIFIED, `account/teams/admin-api.md`) | **Enterprise teams only**, admin API key, 20 req/min |
| `POST https://api.cursor.com/teams/daily-usage-data` | daily aggregates; "aggregated at the hourly level — we recommend polling this endpoint at most once per hour" (VERIFIED) | **Enterprise teams only** |
| `GET https://api.cursor.com/v1/agents/{id}/usage` | `inputTokens`/`outputTokens`/`cacheRead`/`cacheWrite`/`totalTokens`, per run (VERIFIED) | any plan — but this is **consumption of one cloud agent, not remaining capacity** |
| `GET https://api.cursor.com/v1/me` | `apiKeyName`, `userId`, `userEmail`, `createdAt` (VERIFIED) | **no quota fields at all** |
| SDK `agent.getUsage()` | `TokenUsage` + `UsageCost { rawCostCents, chargedCents }` per run (VERIFIED) | consumption, not remaining |

### What does not exist

**There is no documented endpoint, protocol event, or CLI command that returns remaining capacity
for an individual (non-Enterprise) account.** I looked in `api.md`, the Cloud Agents endpoint list,
the Admin/Analytics API pages, the CLI reference, the SDK reference, and the usage help page. The
Anthropic equivalent the owner already uses — `GET /api/oauth/usage` returning
`five_hour.utilization`, `seven_day.utilization`, `resets_at` — **has no Cursor counterpart.**

### Windows

**Monthly, tied to the billing cycle** (VERIFIED, `usage-limits.md`): two pools — *Cursor Models*
(Cursor Grok 4.6 / 4.5, Composer 2.5) and *Other Models* (third-party at provider prices). "Usage
resets monthly with your billing cycle. Unused usage does not roll over." No rolling-hours window,
no weekly window. This is a **fundamentally different shape** from Claude Code's 5-hour + 7-day
rolling windows, and a rate-limit-aware orchestrator's pause/resume logic does not port: there is
nothing to wait out except the next billing cycle.

### In-band limit signalling

- SDK: `RateLimitError` with message "Rate limit exceeded" **or "Usage limit exceeded"**, carrying
  `isRetryable`, `code`, `status`, `requestId` (VERIFIED). The doc distinguishes the two causes:
  "Burst limit or monthly usage cap", and for the cap the recommended fix is to raise the plan
  limit — i.e. **there is nothing to wait for.**
- CLI headless: on failure "the process exits with a non-zero code and writes an error message to
  stderr" with no JSON object (VERIFIED). A limit hit is therefore a **stderr string match**, not a
  typed event. Changelog 2026-03 says "classified server errors (like rate limits) render with
  their real message" (CLAIMED).
- **No reset time is exposed in-band anywhere.**

### Closest workaround, and what it costs

Three bad options:

1. **Scrape `/usage`.** Drive the TUI in a pty, type `/usage`, screen-scrape. Cost: fragile,
   layout-dependent, needs a live terminal, and breaks on any UI change. This is exactly the
   "typing on a screen" failure mode the field notes already record for the current harness.
2. **Track spend yourself.** Sum `agent.getUsage().cost.chargedCents` (SDK) or the per-turn token
   totals in `stream-json`, against a budget the owner declares by hand. Cost: the orchestrator
   never learns the *real* remaining allowance, only what it itself spent — it is blind to the
   owner's IDE and Cloud Agent usage on the same account, which draw from the same pool. Also
   `chargedCents` "can take a moment to settle after a run ends".
3. **Treat limit-hit as terminal, not pausable.** On "Usage limit exceeded", stop the queue, notify
   the owner, do not retry. Cost: the whole rate-limit-aware pause/resume design is unusable for
   this platform; Cursor sessions become "run until they die".

**Verdict: FAILS the owner's first non-negotiable.** Option 3 is the only honest design for a
personal plan.

---

## F. ACCOUNTS

### Several accounts on one machine

**Config is isolatable (VERIFIED — read in source *and* run here).** Resolution order, from the
installed binary (see the code block under C): `CURSOR_CONFIG_DIR` → `XDG_CONFIG_HOME/cursor` →
`~/.cursor`, with a separate `CURSOR_DATA_DIR` → `~/.cursor` for `projects/`. Confirmed
empirically:

```bash
CURSOR_CONFIG_DIR=/tmp/cfgtest CURSOR_DATA_DIR=/tmp/cfgtest cursor-agent status
# → created /tmp/cfgtest/cli-config.json, left ~/.cursor untouched
```

Documented too (VERIFIED, `cli/reference/configuration.md`): "Override with environment variables:
**`CURSOR_CONFIG_DIR`**: custom directory path".

**Credentials are NOT isolated by it on macOS.** From the installed binary (VERIFIED):

```js
function zb(b){let x=b.trim();return{account:`${x}-user`,accessTokenService:`${x}-access-token`,
  refreshTokenService:`${x}-refresh-token`,apiKeyService:`${x}-api-key`}}
function Jb(b){if($b()==="darwin")return new S(b);return new E(b)}   // S = keychain, E = file
```

On `darwin` the credential store is the **OS keychain**, keyed by a fixed namespace string plus
`-access-token` / `-refresh-token` / `-api-key`; on every other platform it is a file at
`~/.<name>/auth.json` (or `$XDG_CONFIG_HOME/...`). **The keychain service name is derived from a
constant, not from `CURSOR_CONFIG_DIR`** (the constant's literal value is UNKNOWN — I could not
resolve the call site, and no such keychain entry exists on this machine because the CLI has never
been logged in). Consequence: **two `CURSOR_CONFIG_DIR`s would share one browser-login identity.**
This is precisely the problem a profile switcher solves for Claude Code by hashing the config dir into the
keychain service name — Cursor does not do that.

### How a supervisor pins a NEW session to a chosen account

**Use API keys, not browser login.** This is the clean, documented, fully isolated path
(VERIFIED, `cli/reference/authentication.md`):

```bash
CURSOR_API_KEY=<key-for-role-A> agent -p "…"        # env var, recommended
agent --api-key <key-for-role-B> -p "…"             # flag
agent --auth-token <token> acp                      # or CURSOR_AUTH_TOKEN (ACP doc only)
```

Keys are minted per user at `cursor.com/dashboard/api`, format `crsr_…`. The `system`/`init` event
reports `apiKeySource: "env"|"flag"|"login"` (VERIFIED) — **so the orchestrator can verify, from
the transcript, which credential a session actually used.** That is a real audit primitive and
better than Claude Code offers.

In the SDK the resolution order is explicit (VERIFIED): "explicit `apiKey`, then `CURSOR_API_KEY`,
then the stored login", with the stored login at `~/.cursor/sdk/auth.json` and a `store` option to
relocate it. **Two accounts can therefore run concurrently inside one SDK process** by passing
different `apiKey` values per `Agent.create()` — no env juggling, no process isolation. Nothing
else in this scan can do that.

### Changing a running session's account

**No.** No flag, no ACP method, no SDK call. Credentials are bound at session creation
(`apiKeySource` is reported once, in `init`). The workaround is the same as everywhere: finish or
cancel the run, `create-chat` under the other credential, seed it with a handoff. Cost: a context
rebuild.

### Verdict

**Per-role accounts: yes, cleanly, via `CURSOR_API_KEY`.** Browser-login multi-account on macOS:
**no** (shared keychain namespace). Running-session switch: **no**. Note that API-key billing
differs from subscription billing — see J.

---

## G. INTERVENTION — the platform's strongest axis

### ACP: the agent's own questions become answerable RPC (VERIFIED, `cli/acp.md`)

`agent acp` speaks JSON-RPC 2.0, newline-delimited, over stdio. Flow:
`initialize` → `authenticate {methodId:"cursor_login"}` → `session/new` (or `session/load`) →
`session/prompt` → handle `session/update` notifications → handle `session/request_permission` →
optionally `session/cancel`.

- **Permission prompts are RPC.** `session/request_permission` — the client answers with
  `allow-once`, `allow-always`, or `reject-once`. Explicit warning in the doc: *"If your client
  does not answer permission requests, tool execution can block."*
- **Clarifying questions are RPC, and they block.** `cursor/ask_question` is a **blocking**
  extension method: `{toolCallId, title?, questions:[{id, prompt, options:[{id,label}],
  allowMultiple?}]}`, answered with
  `{outcome:{outcome:"answered", answers:[{questionId, selectedOptionIds}]}}` — or
  `{outcome:"skipped", reason?}` / `{outcome:"cancelled"}`. **This is the exact capability the
  owner asked for on axis G and the only platform in this scan that ships it as a first-class
  typed method.**
- **Plan approval is RPC.** `cursor/create_plan` — also blocking — hands the supervisor the full
  markdown plan and a typed todo list, and takes `accepted` / `rejected {reason}` / `cancelled`.
  A supervisor can gate plan-mode work programmatically.
- Notifications (no reply needed): `cursor/update_todos` (with a `merge` flag — live todo state
  the supervisor can mirror), `cursor/task` (subagent lifecycle, with `agentId` for resuming a
  subagent), `cursor/generate_image`.
- Modes carry over: `agent`, `plan`, `ask`.
- **Limitation (VERIFIED):** "Team-level MCP servers configured through the Cursor dashboard are
  not supported in ACP mode."

The docs ship a complete ~40-line Node client. An orchestrator adapter is a day's work, not a
research project.

### SDK: steering with delivery confirmation (VERIFIED, `sdk/typescript.md`)

```typescript
const outcome = await run.steer?.("Skip the admin routes for now");
// "complete_delivered"  → the turn has it; do not resend
// "revert_to_followup"  → it did not land; send with agent.send() after the run
```

*"`run.steer(text)` injects a message into the turn that is already running instead of waiting for
it to finish. The promise settles once the turn confirms whether it appended the text."*
Local runs only — "Cloud runs and detached local handles expose `steer` but always resolve
`revert_to_followup`". Also: "Steering works while a foreground subagent is running. The subagent
moves to the background and keeps running so the parent turn can take the message."

**This directly answers the failure the field notes record — "a nudge that cannot submit stranded
text". Here the nudge tells you whether it was submitted.** Plus `run.cancel()` (status →
`cancelled`, in-flight tool calls stop, partial output retained) and
`run.onDidChangeStatus(cb)`.

### Hooks: a file-mediated injection channel (VERIFIED, `hooks.md`)

The `stop` hook fires when the agent loop ends, receives `{status:"completed"|"aborted"|"error",
loop_count}`, and may return `{"followup_message": "…"}` — *"When provided and non-empty, Cursor
will automatically submit it as the next user message. This enables loop-style flows (e.g.,
iterate until a goal is met)."* Default cap **5 auto follow-ups per script**, configurable via
`loop_limit`, `null` removes the cap; same limit applies to `subagentStop`.

So even without ACP, a supervisor can drop instructions into a file and have a `stop` hook feed
them in — and it **knows they arrived**, because `loop_count` increments and the session continues.

Also: `sessionStart` can return `{"env": {...}, "additional_context": "…"}` — environment variables
"available to all subsequent hook executions" and context injected into the conversation's initial
system context.

### Interactive steering

"Pressing Enter while the agent works now sends your queued message into the active run at a safe
boundary to steer it, and only interrupts the turn if you press Enter again" (CLAIMED, changelog
2026-08-11). And shell-approval prompts now offer *"Skip & tell the agent what to do instead"*,
opening a composer whose message reaches the agent as the skip reason (CLAIMED, 2026-07-13).

### Verdict

**Best in the field.** Three independent mechanisms, two of them typed and correlated, one of them
(`run.steer`) reporting delivery explicitly. This axis is not a risk for Cursor.

---

## H. GUARDRAILS

### Permission tokens (VERIFIED, `cli/reference/permissions.md`)

In `~/.cursor/cli-config.json` (global) or `<project>/.cursor/cli.json` (project — **permissions
are the only thing configurable per project**):

| Token | Meaning |
|---|---|
| `Shell(commandBase)` | first token of the command line; globs; `Shell(curl:*)` matches command **and args** |
| `Read(pathOrGlob)` | e.g. `Read(.env*)` in `deny` |
| `Write(pathOrGlob)` | e.g. `Write(**/*.key)` in `deny` |
| `WebFetch(domainOrPattern)` | `*`, `*.example.com`, or an exact host |
| `Mcp(server:tool)` | `Mcp(datadog:*)`, `Mcp(*:search)`, `Mcp(*:*)` |

"Deny rules take precedence over allow rules." Project overrides merge from git root down to cwd,
deeper wins, and "project overrides only affect the current session; they are not written back to
the home config" (VERIFIED, from `~/.cursor/skills-cursor/update-cli-config/SKILL.md`).

### Run modes (VERIFIED, `agent/security/run-modes.md` + `cli-config.json` `approvalMode`)

`approvalMode` accepts **`allowlist`** (default), **`auto-review`**, **`unrestricted`**:

| Mode | Runs without asking | Sandbox | Classifier |
|---|---|---|---|
| Auto-review | allowlisted immediately; other shell in sandbox when possible; rest to a classifier | yes, shell | yes |
| Allowlist | only allowlisted | optional, shell | no |
| Run Everything | everything | no | no |

`-f/--force` (alias `--yolo`) = Run Everything for that invocation. The classifier runs on Claude
4.5 Haiku or GPT-5.4 Mini and is steered by plain-English `block_instructions` in
`~/.cursor/permissions.json` and/or `<project>/.cursor/permissions.json` (merged). Explicit
warning: *"Auto-review is not a security boundary."*

### Sandbox (VERIFIED)

`--sandbox enabled|disabled`, plus `agent sandbox enable|disable|reset|run`. `sandbox run` takes
`--allow-paths`, `--readonly-paths`, `--blocked-patterns`, `--sandbox`, `--network` (default
`false`), `--sb-debug`. Config: `sandbox.mode`, `sandbox.networkAccess`
(`user_config_only` | `user_config_with_defaults` | `allow_all`), `sandbox.networkAllowlist`.
macOS uses **seatbelt**; Linux uses bubblewrap. SDK sandboxing writes only to `local.cwd` + temp +
allowed paths, and **denies outbound network by default**, reading `.cursor/sandbox.json` or
`~/.cursor/sandbox.json`.

### Hooks (VERIFIED, `hooks.md`)

18 events: `sessionStart`, `sessionEnd`, `preToolUse`, `postToolUse`, `postToolUseFailure`,
`subagentStart`, `subagentStop`, `beforeShellExecution`, `afterShellExecution`,
`beforeMCPExecution`, `afterMCPExecution`, `beforeReadFile`, `afterFileEdit`, `beforeSubmitPrompt`,
`preCompact`, `stop`, `afterAgentResponse`, `afterAgentThought`, plus `workspaceOpen` and the Tab
events. Config in `~/.cursor/hooks.json` / `.cursor/hooks.json`, `{"version":1,"hooks":{…}}`, each
entry taking `command`, `type` (`command` | **`prompt`** — an LLM-evaluated policy), `timeout`,
`matcher` (**JavaScript regex, not POSIX**), `failClosed`, `loop_limit`. Exit code 2 blocks; other
non-zero fails **open** unless `failClosed: true`. Claude Code `settings.json` hooks "are read and
merged" (CLAIMED, changelog 2026-01) and `CLAUDE_PROJECT_DIR` is provided as an alias.

### What it does unattended without asking

With `-p --force` (or `approvalMode` non-allowlist): **everything.** The parameter doc is blunt —
`-p` "Has access to all tools, including write and shell", and `cli/using.md` says "Cursor has full
write access in non-interactive mode." The SDK is blunter: "By default a local agent runs every
tool call without restriction, since headless runs have no human to approve them", and sandbox is
`enabled: false` by default. **Without `--force`, headless changes are only proposed, not applied**
— so a supervisor that forgets the flag gets a run that looks successful and changes nothing. That
is the same silent-no-op shape the field notes record for the current harness's merge step.

Safer unattended posture: `local.autoReview: true` (SDK) or `approvalMode: "auto-review"` (CLI)
plus `sandboxOptions.enabled` plus an explicit deny list. Note the SDK caveat: "a call the
classifier blocks is denied rather than escalated, and the agent gets the block reason and can try
another approach" — which is the right behaviour for unattended work.

### Verdict

**Best-in-class granularity.** The risk is not capability, it is that the *defaults* for headless
are maximally permissive.

---

## I. EXTENSIBILITY

- **MCP** — `~/.cursor/mcp.json` and `<project>/.cursor/mcp.json`, shared with the IDE. Commands:
  `agent mcp login|list|list-tools|enable|disable <identifier>` (VERIFIED). Approval gate:
  `--approve-mcps` "Automatically approve all MCP servers". Not in ACP: dashboard-configured
  team servers.
- **Rules** — `.cursor/rules` (`.mdc`), **plus `AGENTS.md` and `CLAUDE.md` at the project root,
  "applied as rules alongside `.cursor/rules`"** (VERIFIED). A GSD-style repo needs no porting.
- **Skills** — the Agent Skills format, `SKILL.md` with frontmatter; `user-invocable: false` hides
  one from `/` autocomplete while keeping it model-callable (CLAIMED, changelog 2026-07-06).
  Managed skills sync into `~/.cursor/skills-cursor/` — **27 are present on this machine**
  (VERIFIED), including `create-hook`, `create-subagent`, `statusline`, `update-cli-config`, `sdk`,
  `loop`, `subscribe`, `autopilot`. These are Cursor's own documentation shipped to disk and are
  the best primary source for the surfaces the web docs skip.
- **Subagents** — `.cursor/agents/` (project) and `~/.cursor/agents/` (user), `.md` + YAML
  frontmatter (`name`, `description`), body = system prompt; project wins on name collision
  (VERIFIED). Per-subagent model routing via `subagentModels.explore` =
  `default|inherit|disabled|{modelId,parameters,maxMode}` (VERIFIED).
- **Plugins** — `--plugin-dir <path>` (repeatable), `/plugin`, marketplaces
  (`agent plugin marketplace add|list|update|remove`, `--format json`). Cursor supports **both**
  its own `.cursor-plugin/plugin.json` format and the open **Agent Plugins** standard
  (`plugin.json` at the root). Plugins can carry hooks, and plugin hooks run including from
  `--plugin-dir` (CLAIMED, changelog 2026-08-11).
- **Config precedence** — permissions: enterprise > team > project > user (for hooks, CLAIMED
  2026-01); CLI config: project `.cursor/cli.json` merged git-root→cwd over
  `~/.cursor/cli-config.json`, permissions only.
- **Can a GSD-style, subagent-heavy engine run inside it?** Yes in principle — subagents, skills,
  slash-command-shaped skills, rules from `CLAUDE.md`, MCP, hooks, and a `stop`-hook loop are all
  present. The gaps are D (no external compaction) and E (no quota read), not extensibility.

### Verdict

**Strong, and unusually portable** — `CLAUDE.md` + Claude-Code-compatible hooks + Claude-Code-style
statusline mean much of the existing harness content transfers without a rewrite.

---

## J. OPERATIONAL REALITY

**Cost model.** Subscription with **monthly pools** (Cursor Models / Other Models), on-demand
overage optional, no rollover, reset on the billing cycle. Separately, **API keys bill differently**
— "On individual plans, [BYOK] requests don't draw from either pool"; on Teams/Enterprise a Cursor
Token Rate of $0.25/Mtok applies. SDK runs "follow the same pricing, request pools, and Privacy
Mode rules as the IDE and Cloud Agents" and show on the dashboard "under the SDK tag". **An
orchestrator driving Cursor with per-role API keys is therefore on a different billing path from
the owner's interactive use, and that needs a deliberate decision, not a default.**

**Maturity.** Very high velocity — roughly monthly releases with large surfaces
(2026-08-26, 08-11, 07-20, 07-13, 07-06, 06-29, 06-22, 06-09, 05-20, 05-14, 05-07, then monthly
back to 2026-01). High velocity cuts both ways: flags appear and disappear (`--background` is gone
from the current reference; `--mode`, `--sandbox`, `--trust`, `--plugin-dir`, `--worktree`,
`acp`, `worker`, `persist` all arrived after the build installed here).

**Install footprint.** `curl https://cursor.com/install -fsS | bash` → `~/.local/share/cursor-agent/versions/<version>/`
(~270 MB on this machine, bundled Node + rg + ~360 files) with symlinks in `~/.local/bin`. macOS,
Linux, WSL, native Windows. No package manager, no npm package.

**macOS support.** Full, including seatbelt sandboxing and keychain credentials.

### Known unattended-run failure modes (each VERIFIED or CLAIMED as marked)

1. **`status` exits 0 while unauthenticated** (VERIFIED here). Preflight must parse
   `--format json`, not `$?`.
2. **Auto-update mutates the running install.** Auto-update is on by default;
   `--disable-auto-update` turns it off (CLAIMED, changelog 2026-01). A 2026-07-13 entry records
   the real failure: "Auto-update cleanup could delete the installed version a long-running session
   was launched from, crashing it mid-turn." Fixed by marking in-use directories — but an overnight
   fleet should still pass `--disable-auto-update` and pin the version, because the install script
   **replaces the `~/.local/bin` symlinks in place** (VERIFIED) and every session in the fleet
   resolves through them.
3. **Failure emits no JSON.** `--output-format json` writes nothing parseable on failure; the
   supervisor must capture stderr separately or it will see an empty result and no reason.
4. **`-p` without `--force` silently proposes instead of applying** (VERIFIED). Looks like success.
5. **macOS keychain prompts.** Changelog 2026-07-20: "keychain failures at startup now explain the
   cause and the fix, like unlocking a locked keychain" — an unattended run on a locked keychain
   fails, and before that fix failed with a raw exit code.
6. **Team admins can disable headless mode org-wide** (CLAIMED, changelog 2026-05-14: "A team
   setting blocks non-interactive CLI usage org-wide"). If the owner's account is under a team,
   the whole integration can be switched off by someone else.
7. **Concurrent CLI processes once corrupted `cli-config.json`** (CLAIMED, fixed 2026-07-06 with
   atomic staged writes). A fleet of parallel sessions is exactly the shape that triggered it —
   worth pinning each role to its own `CURSOR_CONFIG_DIR` regardless of the credential caveat.
8. **A stalled headless upload used to hang forever** on HTTP/1.1 (CLAIMED, fixed 2026-08-11). The
   supervisor still needs its own liveness timeout.
9. **ACP blocks if you do not answer.** "If your client does not answer permission requests, tool
   execution can block" (VERIFIED). An ACP adapter must answer *every* `session/request_permission`
   and every blocking `cursor/*` method, including ones it does not understand.

### Plausible to run overnight unattended today?

**Yes for execution, no for governance.** A single Cursor session will happily run all night
headless with `--force`, and a supervisor can watch it, steer it, answer its questions and see its
context fill up. What it cannot do is the thing the owner's whole design is built around: **know
how much budget is left and pause before hitting the wall.** Cursor will simply fail with
"Usage limit exceeded" and there will be nothing to wait for until the billing cycle turns.

---

## What this costs the orchestrator

| Axis | Verdict | What the adapter must build, and what it costs |
|---|---|---|
| **A Launch** | ✅ | Thin. `cursor-agent -p --force --output-format stream-json --resume <id>`. Also pass `--disable-auto-update` and `--trust`. |
| **B Identity & resume** | ✅ | One extra `create-chat` call per ticket to pre-allocate the id. Accept that resume depends on Cursor being up. |
| **C Transcript** | ✅ | Read stdout NDJSON. Do **not** guess the on-disk path — install a statusline or `sessionStart` hook and record `transcript_path` from the payload. |
| **D Context** | ⚠️ half | Statusline script → `context_window.used_percentage` (sub-second, free). `preCompact` hook → proof, with numbers. **No external trigger**: design for threshold → stop → `create-chat` → seeded handoff, and accept a one-to-many ticket→session mapping. |
| **E Quota** | ❌ | **No solution on a personal plan.** Self-track spend from `stream-json` token totals against a hand-declared budget, treat "Usage limit exceeded" as terminal, and notify the owner. The pause/resume machinery does not apply. Revisit only if the owner moves to Enterprise (`/teams/spend`). |
| **F Accounts** | ✅ new / ❌ running | Mint one `crsr_…` key per role; launch with `CURSOR_API_KEY`. Verify with `apiKeySource` in the `init` event. Do **not** rely on `CURSOR_CONFIG_DIR` to separate browser logins on macOS — the keychain namespace is shared. No mid-session switch. |
| **G Intervention** | ✅✅ | Write an ACP client (~1 day; a working reference client is in the docs). It answers `session/request_permission`, `cursor/ask_question`, `cursor/create_plan` programmatically. If the SDK path is chosen instead, `run.steer()` gives delivery confirmation. Cheapest fallback: a `stop` hook reading a file and returning `followup_message`. |
| **H Guardrails** | ✅ | Ship a role-specific `cli-config.json` (`approvalMode: "auto-review"`, deny list) and a `hooks.json`. Cost is config, not code. Never rely on the defaults. |
| **I Extensibility** | ✅ | `CLAUDE.md` is read as a rule; hooks are Claude-Code-compatible and merged; the statusline contract is the same. Much of the existing harness content ports as-is. |
| **J Operational** | ⚠️ | Pin the version, disable auto-update, capture stderr, parse `status --format json`, add an external liveness timeout, and decide deliberately whether API-key billing is acceptable. |

**Summary for the rebuild.** Cursor is the platform to copy on axis G and the platform to avoid on
axis E. If the orchestrator's scheduler is built around "read remaining quota, pause, resume",
Cursor cannot be a first-class citizen of that scheduler on a personal plan — it can only be a
worker that runs until it is told it is out. Conversely, its ACP surface is the cleanest existing
implementation of "answer the session's own question programmatically", and it — not pi's `rpc`
mode alone — should shape the orchestrator's intervention protocol, because it types the *question*
as well as the answer.

---

## Open questions for a follow-up pass

| # | Question | Axis |
|---|---|---|
| 1 | Does a slash command submitted as programmatic prompt text (`session/prompt` with `/summarize`, or a `stop`-hook `followup_message`) actually execute, or land as literal text? This is the whole of D's workaround. | D |
| 2 | Is `agent persist` real, and are `attach|list|stop|--resume` the exact subcommands? It appears only in the 2026-08-26 changelog. | A, B |
| 3 | What is the default on-disk transcript directory, and what disables transcripts? | C |
| 4 | What is the literal keychain namespace string, and does any env var override it (which would make browser-login multi-account work on macOS)? | F |
| 5 | Does `/usage` have any non-interactive form, or an undocumented endpoint behind it? | E |
| 6 | Does `--resume <chatId>` combine with `-p` as the global-flag table implies? Never stated in prose. | A, B |
| 7 | What does `agent worker start` actually expose — it is a self-hosted cloud-agent runner with `/healthz`, `/readyz`, `/metrics` and a pool/claim protocol, which is an orchestration surface in its own right. | A, J |

---

## Sources (all retrieved 2026-09-19)

**Run on this machine**
- `cursor-agent --version` → `2025.09.12-4852336`; `cursor-agent --help`; `cursor-agent help <cmd>` for `agent`, `ls`, `resume`, `create-chat`, `mcp`, `status`, `login`, `logout`, `update`
- `cursor-agent status` → `Not logged in`, exit 0
- `CURSOR_CONFIG_DIR=… CURSOR_DATA_DIR=… cursor-agent status` → config isolation confirmed
- `security find-generic-password -s cursor-…` → no CLI keychain entry
- `find ~/.cursor` — no chat/transcript files under `projects/`

**Read in the installed binary (2025.09.12-4852336)**
- `index-wgf8x11r.js` — config/data dir resolution, project slug, `cli-config.json` path
- `index-20sqary7.js` — keychain vs file credential stores, service-name derivation
- grep for `CURSOR_*` env vars: `CURSOR_API_KEY`, `CURSOR_API_ENDPOINT`, `CURSOR_CONFIG_DIR`, `CURSOR_DATA_DIR`, `CURSOR_AGENT`, `CURSOR_CLI`, `CURSOR_CLI_MODE`, `CURSOR_RULES`, …

**Cursor-shipped skills on disk (`~/.cursor/skills-cursor/`, synced 2026-09-01)**
- `statusline/SKILL.md` — the full `StatusLinePayload` schema including `context_window`
- `create-hook/SKILL.md` — hook events, `hooks.json` format, matcher and exit-code semantics
- `update-cli-config/SKILL.md` — every `cli-config.json` field, including `subagentModels`, `approvalMode`, `sandbox`, `bedrock`, and the fields not to edit
- `create-subagent/SKILL.md`, `sdk/SKILL.md`, `loop/SKILL.md`, `subscribe/SKILL.md`, `autopilot/SKILL.md`, `shell/SKILL.md`, `automate/SKILL.md`, `rename-chat/SKILL.md`, `share/SKILL.md`, `origin/SKILL.md`

**Official docs (`cursor.com/docs/…​.md`, fetched as markdown)**
- `cli/overview`, `cli/installation`, `cli/using`, `cli/changelog`, `cli/headless`, `cli/acp`,
  `cli/shell-mode`, `cli/github-actions`
- `cli/reference/parameters`, `…/slash-commands`, `…/authentication`, `…/permissions`,
  `…/configuration`, `…/output-format`, `…/terminal-setup`
- `hooks`, `plugins`, `agent/security`, `agent/security/run-modes`, `configuration/worktrees`
- `sdk/typescript`, `sdk/bridge`, `sdk/changelog`
- `api`, `cloud-agent/api/endpoints`, `account/teams/admin-api`, `account/teams/analytics-api`
- `help/models-and-usage/usage-limits`
- `https://cursor.com/install` (the installer script itself, read not executed) — current build
  `2026.09.18-9a7762b`

**Not consulted / out of scope:** comparison listicles and third-party blogs. Per the field scan's
warning, nothing here is dated or sized from secondary sources.
