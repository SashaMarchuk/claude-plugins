# Claude Code (Anthropic) — platform profile

**Scanned:** 2026-09-19. **Machine:** owner's Mac, darwin 25.5.0.
**Version under test:** `2.1.278 (Claude Code)` — VERIFIED by running `claude --version`.
**Binary:** `~/.local/bin/claude` → symlink to `~/.local/share/claude/versions/2.1.278`, a
**Mach-O 64-bit arm64 native executable, 208 MB** (VERIFIED: `ls -la`, `file`, `du -sh`). Not a
Node script — `claude gateway` refuses to run under npm with *"claude gateway requires the native
binary. Install via https://claude.ai/install.sh instead of npm."* (VERIFIED, string in binary).

**Evidence tags.** **VERIFIED** = read in the binary's own strings, read in official docs today, or
run read-only on this machine. **CLAIMED** = asserted by a README/marketing page only. **UNKNOWN** =
could not establish.

**Method note.** Flags are quoted from `claude --help` and `claude <sub> --help` run on this
machine, never from prose. Protocol and schema details were read out of the binary with
`strings -n 10` and cross-checked against `code.claude.com/docs` fetched today. No agent run was
started, no prompt was sent to a model, no config was modified. Two probes did spend a few bytes of
network: `claude auth status` (read-only) and a `GET` of the OAuth usage endpoint.

**The short version.** Claude Code is not merely "the reference platform" for this contract — it is
the only platform in the scan that answers **every** axis, including the four the owner called
non-negotiable, with a documented surface rather than a workaround. The two real gaps are (1) there
is **no way to force compaction on a session that is not listening on a pipe**, and (2)
`--bg` and `-p` are **mutually exclusive**, which forces a choice between a visible attachable
session and a structured stream.

---

## A. LAUNCH

### Headless (`-p`)

VERIFIED from `claude --help` on 2.1.278:

```
-p, --print                  Print response and exit (useful for pipes).
--output-format <format>     "text" (default), "json" (single result), or "stream-json"
--input-format <format>      "text" (default), or "stream-json" (realtime streaming input)
--include-partial-messages   partial message chunks (needs --print and stream-json)
--include-hook-events        all hook lifecycle events in the output stream (stream-json only)
--replay-user-messages       re-emit user messages from stdin back on stdout for acknowledgment
--forward-subagent-text      forward subagent text/thinking with parent_tool_use_id set
--max-budget-usd <amount>    Maximum dollar amount to spend on API calls (only works with --print)
--json-schema <schema>       JSON Schema for structured output validation
```

`--print` also **skips the workspace trust dialog** and **silently ignores settings files that fail
validation** (VERIFIED, quoted from the help text). Both matter unattended: a broken settings file
produces no error, just different behaviour.

The binary's own protocol documentation (VERIFIED, read from strings) states the wire contract
exactly:

> *"Everything the CLI writes to its output stream (stdout in stream-json mode): exactly one
> StdoutMessage per line, as a single JSON object. Besides the SDKMessage members this includes the
> control protocol — control requests the CLI originates, control responses to the client's
> requests, cancellations and keep-alives."*

> *"Everything a client may write to the CLI's input stream (stdin in stream-json input mode):
> exactly one StdinMessage per line … `initialize` is optional and normally the first line; the
> first user message initializes with defaults. … Closing the stream tells the CLI to finish the
> current turn and exit."*

### Visible / attachable

VERIFIED from `--help`:

```
--bg, --background       Start the session in the background and return immediately. Prints the id
                         that `claude attach`, `logs`, `stop` and `rm` take; `claude agents` lists
                         them. With --resume <session-id>, continues that session in the background
                         under the same ID, or starts a copy and says so when the session is
                         already running
-n, --name <name>        Set a display name for this session (shown in the prompt box, /resume
                         picker, and terminal title)
-w, --worktree [name]    Create a new git worktree for this session
--tmux                   Create a tmux session for the worktree (requires --worktree). Uses iTerm2
                         native panes when available; use --tmux=classic for traditional tmux.
```

**Constraint, and it is a real one:** the docs state `--bg` *"Can't be combined with `-p`/`--print`"*
(VERIFIED, code.claude.com/docs/en/cli-reference, fetched 2026-09-19). So the orchestrator picks one
of two launch shapes per session:

| Shape | Gets | Loses |
|---|---|---|
| `claude -p --output-format stream-json --input-format stream-json` | the full control protocol, structured events, `can_use_tool`, `get_context_usage`, `get_usage` | a terminal the owner can attach to and type in |
| `claude --bg "<task>"` (or a real terminal) | `claude attach/logs/stop/rm/respawn`, a JSON roster, owner can take over | the control protocol; intervention degrades to cross-session messaging (see G) |

There is a third shape the owner already uses: a **real terminal window** driven by the
`task-launch` / `harness` launchers. That is the same as `--bg` for contract purposes, minus the
daemon roster.

**Verdict A: fully supported, both modes, but not simultaneously.**

---

## B. IDENTITY & RESUME

### Naming a session before it exists

```
--session-id <uuid>    Use a specific session ID for the conversation (must be a valid UUID)
```

VERIFIED from `--help`. This is the strong form the owner wants: the orchestrator **assigns** the id
up front rather than scraping it out of output. (pi's `--session-id` is the only other platform in
the scan with this.)

```
-r, --resume [value]   Resume a conversation by session ID, or open interactive picker
-c, --continue         Continue the most recent conversation in the current directory
--fork-session         When resuming, create a new session ID instead of reusing the original
--from-pr [value]      Resume a session linked to a PR by PR number/URL
```

Docs add (VERIFIED, code.claude.com/docs/en/cli-reference, 2026-09-19): `--resume` accepts a session
ID, **a name**, or **the absolute path to the `.jsonl` transcript**. Lookup searches the current
project directory and its git worktrees first, then *"every other project on this machine"* —
cross-directory lookup since **v2.1.223**; older builds were scoped to the project dir.

### Listing live sessions

`claude agents --json` — VERIFIED by running it here (read-only, no TTY needed). Real output:

```json
[
  { "id": "8402872a", "cwd": "/Users/…/My Project site", "kind": "background",
    "startedAt": 1778851002499, "sessionId": "8402872a-1699-490a-b3f5-cfccbd5aa9f6",
    "name": "task-review", "state": "blocked" },
  { "pid": 35475, "cwd": "/Users/…/MNB", "kind": "interactive",
    "startedAt": 1789743993512, "sessionId": "e4ea9e27-…", "name": "project-a-60", "status": "busy" }
]
```

Note the shape difference: **background** rows carry `id` + `state`; **interactive** rows carry
`pid` + `status`. `--all` adds completed background sessions (12 rows here vs 5 active). This is a
liveness surface the orchestrator gets for free — no polling of `ps`.

### What survives a crash

VERIFIED on disk. Background sessions have durable state at
`~/.claude/jobs/<short-id>/state.json` + `timeline.jsonl`. A real `state.json` read here:

```json
{
  "state": "done", "detail": "summarized remaining work: …", "tempo": "idle",
  "inFlight": { "tasks": 0, "queued": 0, "kinds": [], "drainableMonitors": 0 },
  "tokens": 1032959,
  "linkScanPath": "/Users/…/.<switcher>/profiles/<profile>/projects/-Users-…-<work-project>/052c2fe5-….jsonl",
  "template": "bg",
  "respawnFlags": ["--allowed-tools","mcp__computer-use__request_access", …],
  "sessionId": "052c2fe5-1387-4c93-a16d-6458bd89f473",
  "resumeSessionId": "052c2fe5-1387-4c93-a16d-6458bd89f473",
  "daemonShort": "052c2fe5", "cliVersion": "2.1.258",
  "cwd": "/Users/…/<work-project>", "bgIsolation": "none",
  "providerEnv": { "CLAUDE_CONFIG_DIR": "/Users/…/.<switcher>/profiles/<profile>" },
  "backend": "daemon", "createdAt": "2026-09-02T19:03:34.405Z", …
}
```

That single file carries **the session id, the resume id, the exact relaunch flags, the account it
ran under, and a token count**. `claude respawn <id>|--all` restarts a background session *"with its
conversation intact"* to pick up a new binary (VERIFIED, `claude respawn --help` + docs).

The transcript itself is the durable record (see C). A crash loses only the in-flight turn: the
`.jsonl` is append-only and every completed message is already on disk.

**Verdict B: the strongest resume story in the scan.** Assign the id, list it later, resume exactly,
fork when you want a branch. Caveat: a session file is **machine-local** — cross-host resume needs
either a `sessionStore` adapter (SDK only) or physically moving the `.jsonl`.

---

## C. TRANSCRIPT

**Location (VERIFIED on disk, and in docs):**
`$CLAUDE_CONFIG_DIR/projects/<encoded-cwd>/<session-uuid>.jsonl`, defaulting to `~/.claude/projects/`.
The encoding replaces every non-alphanumeric character in the absolute cwd with `-`, so
`/Users/me/proj` → `-Users-me-proj`. Names over 200 characters are truncated and hashed, so a
reader must match the first 200 characters (VERIFIED, docs 2026-09-19). 394 project directories
exist here.

**Format:** one JSON object per line, append-only, readable live. Types observed in a single real
session file (VERIFIED, counted here):

```
assistant 132 · attachment 99 · user 85 · last-prompt 46 · mode 45 · permission-mode 45
atis-latch 45 · ai-title 44 · queue-operation 30 · system 23 · frame-link 16
file-history-snapshot 7 · artifact-autoreact-ledger 6 · file-history-delta 5
artifact-comment-monitor 4 · cost-state 3
```

Every envelope carries `uuid`, `parentUuid`, `sessionId`, `timestamp`, `cwd`, `gitBranch`,
`version`, `isSidechain`, `userType`. `isSidechain: true` marks subagent traffic, so a supervisor
can separate the main thread from a fan-out.

**Two records a supervisor should read directly:**

`type: "cost-state"` — a running ledger, VERIFIED here:

```json
{ "type":"cost-state", "sessionId":"ac653a10-…", "totalCostUSD": 79.906,
  "totalAPIDuration": 7509476, "totalToolDuration": 1123844,
  "totalLinesAdded": 1562, "totalLinesRemoved": 162, "startTime": 1789282808408,
  "modelUsage": { "claude-opus-5[1m]": { "inputTokens":452445, "outputTokens":498674,
    "thinkingTokens":198247, "cacheReadInputTokens":100418465, "costUSD":79.205 }, … } }
```

`message.usage` on each `assistant` line — the raw window arithmetic:
`input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`,
`output_tokens_details.thinking_tokens`, `service_tier`, plus a per-`iterations` breakdown.

**Verdict C: fully supported, live-readable, and richer than the docs advertise.**

---

## D. CONTEXT — read fullness, trigger compaction, prove it happened

This is one of the four non-negotiables. Claude Code answers all three parts, but the *trigger* part
has a condition.

### Reading how full the window is — three ways, all VERIFIED

**1. The statusLine stdin contract (the best one, and the one nothing in the current harness uses).**
A `statusLine` command configured in `settings.json` receives a JSON document on stdin on every
render. Quoted verbatim from the binary's bundled schema and confirmed against
`code.claude.com/docs/en/statusline` (2026-09-19):

```
"context_window": {
  "total_input_tokens": number,       // Input tokens currently in the context window
  "context_window_size": number,      // Context window size for current model (e.g., 200000)
  "current_usage": { … } | null,
  "used_percentage": number | null,      // Pre-calculated: % of context used (0-100)
  "remaining_percentage": number | null  // Pre-calculated: % of context remaining (0-100)
}
```

The same payload carries `session_id`, `session_name`, `transcript_path`, `cwd`, `model.id`,
`effort.level`, `agent.name`, `worktree`, and a whole `prompt_cache` block (`warm`, `hit_ratio`,
`last_miss_cause.causes`, `expected_rebuilds`). Config:

```json
{ "statusLine": { "type": "command", "command": "…", "refreshInterval": 5 } }
```

`refreshInterval` (minimum `1` second) re-runs the command on a timer **in addition to** the
event-driven updates, which the docs note *"can go quiet when the main session is idle, for example
while a coordinator waits on background subagents"*. Updates are debounced at 300 ms.

**This is the mechanism the rebuild should use.** It turns every session into a push-based telemetry
source, for context *and* quota, with no polling and no API call — a two-line shell script that
writes JSON into a per-session file the supervisor tails. `used_percentage` is computed from input
tokens only (`input + cache_creation + cache_read`), excluding output tokens; match that formula if
you compute it yourself.

**2. The `get_context_usage` control request** (stream-json sessions only). VERIFIED: the subtype
string, its validation error (`get_context_usage: detail must be 'summary' or 'full'`), and its
documented semantics:

> *"'full' counts each category with the token-count API; 'summary' answers from the last response's
> usage and local estimates without the per-category token-count calls. Defaults to 'full'."*
> *"Breakdown of current context window usage by category (system prompt, tools, messages, etc.)."*

Rows are classified `'used' | 'free' | 'buffer' | 'deferred'` — and the binary explicitly warns
*"Classify on this, never on the English name."* `'buffer'` is the compaction reserve.

**3. Transcript arithmetic.** Sum `message.usage` on the last assistant line against the model's
window. Works for any session, including one nobody is piping. Least precise; ignores the deferred
tool-schema rows.

### Triggering compaction from outside

**There is no control_request subtype that compacts.** VERIFIED by enumerating the subtype list in
the binary (`add_directory, background_tasks, cancel_async_message, channel_enable,
claude_authenticate, claude_oauth_callback, claude_oauth_wait_for_completion, end_session,
fork_conversation, get_binary_version, get_hooks_listing, get_memory_dialog, get_settings,
list_models, list_permission_rules, mcp_authenticate, mcp_clear_auth, mcp_oauth_callback_url,
mcp_reconnect, mcp_set_servers, mcp_status, poll_event, reload_output_styles, reload_skills,
remote_control, rename_session, rewind_conversation, rewind_files,
set_mcp_permission_mode_override, stage_file, submit_feedback, update_settings`, plus
`initialize, interrupt, can_use_tool, set_permission_mode, set_model, set_max_thinking_tokens,
get_context_usage, get_usage, mcp_call, request_user_dialog, keep-alive`). No `compact`.

What exists instead, in descending order of directness:

| Way in | Reaches | Cost |
|---|---|---|
| Send `/compact` as an ordinary user message on the stdin lane | stream-json sessions | free; one turn; needs the pipe |
| Type `/compact` into the TUI | any visible session | needs a robot typing on a screen — the failure mode the field notes already record |
| `--autocompact <auto\|tokens>` at launch (`auto`, or `100k–1M tokens`) | any session | pre-commits a threshold; cannot be changed later |
| `PreCompact` hook | any session | **can only veto, never trigger** |

The `/compact` route is VERIFIED end-to-end by the SDK docs (2026-09-19), which show exactly this
pattern and read the proof back:

```js
for await (const message of query({ prompt: "/compact",
                                    options: { continue: true, maxTurns: 1 } })) {
  if (message.type === "system" && message.subtype === "compact_boundary") {
    console.log("Pre-compaction tokens:", message.compact_metadata.pre_tokens);
    console.log("Trigger:", message.compact_metadata.trigger);
  }
}
```

Caveat the docs state plainly: with nothing to summarize, `/compact` returns a `success` result
**with no `compact_boundary` message** and the text `Not enough messages to compact.` — so absence
of the record is not the same as failure, and the supervisor must distinguish the two.

### Proof it happened — VERIFIED, on disk, in a real transcript

Read out of `~/.claude/projects/-<work>-<work-project>/ad544616-….jsonl`:

```json
{ "type": "system", "subtype": "compact_boundary",
  "content": "Conversation compacted", "level": "info",
  "logicalParentUuid": "54999e16-…",
  "compactMetadata": {
    "trigger": "manual",
    "preTokens": 330908, "postTokens": 10491,
    "cumulativeDroppedTokens": 320417, "durationMs": 125318,
    "preCompactDiscoveredTools": ["Monitor"],
    "preservedSegment": { "headUuid": "…", "anchorUuid": "…", "tailUuid": "…" },
    "preservedMessages": { "anchorUuid": "…", "uuids": [ … ], "allUuids": [ … ] } },
  "timestamp": "2026-09-04T15:33:02.903Z", "version": "2.1.260" }
```

That is unambiguous, timestamped, attributable proof with before/after token counts — better than
"the context looks smaller now". The orchestrator reads it from the transcript tail; it needs no
pipe and no cooperation from the session.

**Hooks around compaction (VERIFIED, docs 2026-09-19):** `PreCompact` and `PostCompact` both fire,
both receive `{session_id, hook_event_name, trigger: "manual"|"auto", custom_instructions, cwd,
permission_mode}`, neither takes a matcher, and **neither can block** — *"No blocking capability —
exit code 2 doesn't block compaction."* The binary nonetheless carries the strings
`"Compaction blocked by PreCompact hook"` and `"compaction blocked by PreCompact hook; continuing
uncompacted"`, so the block path exists in code even where the docs say it does not. Treat blocking
as **UNKNOWN** and do not design on it.

**One failure mode worth naming.** The binary carries an autocompact circuit breaker:

> *"Autocompact is thrashing: the context refilled to the limit within 3 turns of the previous
> compact, 3 times in a row. A file being read or a tool output is likely too large for the context
> window."*

An unattended run that reads a huge file in a loop will trip this and stop compacting. The
supervisor should watch for three `compact_boundary` records in quick succession and intervene.

**Verdict D: read — excellent, three independent ways. Trigger — works, but only on a session the
orchestrator holds a pipe to, or by pre-committing a threshold at launch. Proof — best in the scan.**

---

## E. QUOTA

The second non-negotiable. Three independent reads, all VERIFIED today.

### 1. The OAuth usage endpoint — the authoritative source

```
GET https://api.anthropic.com/api/oauth/usage
  Authorization: Bearer <accessToken from the account's Keychain entry>
  anthropic-beta: oauth-2025-04-20
```

VERIFIED by running it here against one configured account. Real response (trimmed):

```json
{ "five_hour": { "utilization": 9.0,  "resets_at": "2026-09-19T17:50:00.147460+00:00",
                 "limit_dollars": null, "used_dollars": null, "locked_reason": null },
  "seven_day": { "utilization": 32.0, "resets_at": "2026-09-20T11:59:59.147485+00:00", … },
  "seven_day_opus": null, "seven_day_sonnet": null, "seven_day_cowork": null,
  "extra_usage": { "is_enabled": false, "spend_limit_reached": false, … },
  "limits": [
    { "kind":"session",       "group":"session", "percent":9,  "severity":"normal",
      "resets_at":"2026-09-19T17:50:00+00:00", "scope":null, "is_active":false },
    { "kind":"weekly_all",    "group":"weekly",  "percent":32, "severity":"normal",
      "resets_at":"2026-09-20T11:59:59+00:00", "scope":null, "is_active":true },
    { "kind":"weekly_scoped", "group":"weekly",  "percent":10, "severity":"normal",
      "resets_at":"2026-09-20T12:00:00+00:00",
      "scope": { "model": { "id": null, "display_name": "Fable" } }, "is_active":false } ],
  "spend": …, "seven_day_breakdown": …, "member_dashboard_available": … }
```

**Prefer `limits[]` over the named top-level keys.** It is self-describing (`kind`, `group`,
`percent`, `severity`, `resets_at`, `scope.model.display_name`, `is_active`) and it carries
per-model weekly windows that the flat keys do not. Several top-level keys are codenames
(`nimbus_quill`, `cedar_ember`, `iguana_necktie`, `tangelo`, `harbor_lantern`, …) whose meaning is
**UNKNOWN** and which should not be parsed by name.

**Windows that exist:** a rolling **5-hour session** window, a **7-day weekly** window (`weekly_all`),
and **per-model weekly** windows (`weekly_scoped`, e.g. scoped to Fable). Plus `extra_usage` (usage
credits, monthly) and, behind a gateway, a spend limit.

**Three operational traps, all hit during this scan:**

1. **The endpoint is itself rate limited.** Two calls returned
   `{"error":{"type":"rate_limit_error","message":"Rate limited. Please try again later."}}`.
   Claude Code's own `/usage` handles this by caching: *"shows the last usage bars it loaded on this
   machine within the past 60 minutes, along with a `Showing last-known usage` note"* (VERIFIED,
   docs). **The orchestrator must cache and back off the same way** — a supervisor that polls every
   session every minute will lock itself out of the number it needs most.
2. **The access token expires.** The Keychain blob is
   `{claudeAiOauth:{accessToken, refreshToken, expiresAt, refreshTokenExpiresAt, scopes[],
   subscriptionType, rateLimitTier}}` (VERIFIED, keys only — values not printed). One
   account returned `"OAuth access token has expired. Re-authenticate to continue."` A supervisor
   reading the Keychain directly does **not** refresh; only Claude Code does. Treat a 401 as "this
   account is cold", not "this account is over limit".
3. **The numbers are per account**, so the supervisor must read one per account it might route to.

### 2. The statusLine payload — free, push-based, no endpoint call

The same stdin document described in D also carries (VERIFIED, binary + docs):

```
"rate_limits": {           // Only for subscribers, or behind a gateway, after first API response
  "five_hour":   { "used_percentage": number, "resets_at": number },   // Unix epoch seconds
  "seven_day":   { "used_percentage": number, "resets_at": number },
  "spend_limit": { "used_percentage": number, "resets_at": number } }  // v2.1.251+
}
```

Each window *"may be independently absent, and Claude Code drops a window once its `resets_at` time
passes"*. This is the cheapest correct read: the CLI already fetched it, the orchestrator just
collects it. **Recommended primary source; use the endpoint as the fallback and for accounts with no
live session.**

### 3. The `get_usage` control request (stream-json sessions)

VERIFIED subtype, with `skip_behaviors: boolean` (validation error quoted:
`get_usage: skip_behaviors must be a boolean`). Documented as returning
*"Plan rate-limit utilization windows from the claude.ai usage endpoint, or null when unavailable"*
plus a 24h/7d local-transcript behaviour scan. Set `skip_behaviors: true` — the scan
*"reads every transcript touched in the last seven days"* and the orchestrator does not need it.

### In-band limit signalling

VERIFIED: `rate_limit_event` is a system-message subtype on the output stream, alongside
`compact_boundary`, `api_retry`, `turn_preempted`, `model_fallback`. The retry frame carries
`rate_limit_type` and `retry_in_ms`.

**And Claude Code will wait and resume on its own.** Strings in the binary (VERIFIED):

- `hasArmedQuotaAutoResume`, `preserveQuotaAutoResume`, `/rate-limit-options`
- *"the usage limit now resets more than 24 hours out, so this task will not resume on its own
  (/rate-limit-options to wait anyway)"*
- *"Claude Code exited during the wait, so the task will not resume on its own when the usage limit
  resets (send a prompt after the reset to continue)"*
- *"this session moved to the background, so the task will not resume on its own when the usage
  limit resets"*
- An injected checkpoint prompt: `[Usage limit approaching. Checkpoint now: finish the current step,
  then list up to 3 short bullets of the most impactful remaining work. Don't start subagents or
  long-running work.]`

The fleet-level switch is the **`autoContinueAtUsageLimit`** setting (VERIFIED in the binary and in
the costs doc: *"To control for your fleet whether Claude Code starts that wait on its own, set
`autoContinueAtUsageLimit` in managed settings"*). Auto-continue requires **v2.1.234 or later**.

Read the last two bullets together and a design decision falls out: **backgrounding a session
cancels its own quota auto-resume**, so the orchestrator owns the resume for `--bg` sessions and
should not assume the CLI will do it.

**Verdict E: fully supported, three ways, with reset times — the best quota story in the scan.**
Route 1 works per config dir: read that dir's Keychain token (see §F) and call the endpoint.

---

## F. ACCOUNTS

The third non-negotiable, and the mechanism already exists — the rebuild should adopt it rather than
design it.

### The mechanism

`CLAUDE_CONFIG_DIR`. One environment variable selects the account for a **new** process. VERIFIED by
running `claude auth status` under different values:

```
<profile> → { loggedIn, authMethod, email, subscriptionType, configDirectory }   (real values omitted)
```

`claude auth status` emits **JSON** with no TTY. That is the orchestrator's account-verification
probe: cheap, read-only, and it answers "is this account usable right now" in one call.

### Where the accounts live

If the user runs a profile switcher, each profile is its own config dir. The orchestrator takes the
account's config dir from configuration; it does not discover accounts.

`<switcher> switch --print-env <name>` prints exactly one line and mutates nothing (VERIFIED by running
it):

```
export CLAUDE_CONFIG_DIR="<profile-dir>"
```

That is the whole handoff. A supervisor spawning a session sets that variable and nothing else.
Per-folder binding is a per-folder marker file read by the shell function; a one-off is `claude -a <acc>`.

### Credentials

Per config dir, in the macOS Keychain, under a derived service name (VERIFIED):

```
~/.claude              → "Claude Code-credentials"
any other config dir   → "Claude Code-credentials-" + first 8 hex of sha256(config dir path)
```

**Presence is not the same as usable.** An entry can exist while `claude auth status` reports
`loggedIn: false`, or hold a token the API rejects as expired. The orchestrator must verify with
`claude auth status`, never by checking that a Keychain row exists.

### Where sessions live

Sessions are stored per config dir, under its `projects/`. A transcript watcher and `--resume` see only
the sessions of the config dir they point at, so the orchestrator records which config dir each session
ran under.

### Changing a running session's account

**Not supported.** UNKNOWN whether any path exists; nothing in the control-request list, the CLI, or
the docs does it. The binary warns when the variable moves under a live process:
*"where your own settings are found (CLAUDE_CONFIG_DIR, the HOME it defaults from, …) changed after
Claude Code started: set it in the shell, not a settings file"*. The workaround is the ordinary one:
stop the session, relaunch with `--resume <id>` under the new `CLAUDE_CONFIG_DIR`. The new config dir
must be able to see the transcript (see "Where sessions live").

### Two traps

1. `~/.claude.json` and `~/.claude/.claude.json` are **different files**. The former is what Claude
   Code reads when `CLAUDE_CONFIG_DIR` is unset — i.e. from a daemon, cron, or a GUI-launched shell.
   A supervisor that forgets the variable silently runs on the wrong account.
2. macOS may prompt once per account for Keychain access. An unattended run against an account that
   has never been granted "Always Allow" **blocks on a GUI dialog**. Grant it once per account, by
   hand, before the first unattended run.

**Verdict F: fully supported for new sessions, per-account, already built here. Not supported for a
running session.**

---

## G. INTERVENTION

The fourth non-negotiable — and the axis the current harness fails at (the field notes record a
nudge that cannot submit stranded text). Claude Code answers it **twice**, by two different
mechanisms that apply to the two launch shapes from A.

### G1. For a piped session: the control protocol

VERIFIED from the binary's own protocol documentation:

> *"Envelope for a control-protocol request, sent by either side on the same stream as the messages.
> The receiver normally answers with exactly one `control_response` carrying the same `request_id`
> … a requester ignores responses for `request_id`s it is not waiting on."*

So: **request/response correlation by id, in both directions.** `control_cancel_request` withdraws an
in-flight request; a keep-alive frame is *"Liveness heartbeat with no payload … the CLI emits it
periodically, for example while a long-running control request is in progress."*

- **Send an instruction:** write a `user` StdinMessage on the pipe. With `--replay-user-messages` the
  CLI *"re-emits user messages from stdin back on stdout for acknowledgment"* — that is the literal
  "know it arrived" the contract asks for.
- **Stop what it is doing:** the `interrupt` request. Its response is documented as *"Result of an
  interrupt operation. Advertised by the `interrupt_receipt_v1` capability on `system/init`; older
  CLIs send an empty success response with no `still_queued` field."*
- **Re-steer without stopping:** `set_permission_mode`, `set_model`, `set_max_thinking_tokens`,
  `update_settings`, `rename_session` — each acknowledged.

### G2. Answering the session's own question programmatically

Both a permission prompt and a clarifying question arrive on the **same** channel: the
`can_use_tool` control request (the SDK's `canUseTool` callback). VERIFIED, docs 2026-09-19:

> *"Claude requests user input in two situations: when it needs permission to use a tool … and when
> it has clarifying questions (via the `AskUserQuestion` tool). Both trigger your `canUseTool`
> callback, which pauses execution until you return a response."*

A permission answer:

```json
{ "behavior": "allow", "updatedInput": { … }, "updatedPermissions": [ … ] }
{ "behavior": "deny",  "message": "User denied this action" }
```

`updatedInput` was **required** for an allow before **v2.1.207**. `updatedPermissions` echoes back a
`PermissionUpdate` suggestion from `context.suggestions` — the "approve and remember" path that
writes a rule to `.claude/settings.local.json` so the same prompt never recurs.

An `AskUserQuestion` answer — the orchestrator returns an allow whose `updatedInput` carries the
answers keyed by question text:

```json
{ "behavior": "allow",
  "updatedInput": {
    "questions": [ /* pass the original array through — required */ ],
    "answers": { "How should I format the output?": "Summary",
                 "Which sections should I include?": ["Introduction", "Conclusion"] },
    "response": "optional freeform reply instead of answering" } }
```

Limits (VERIFIED): 1–4 questions, 2–4 options each; **`AskUserQuestion` is not available in
subagents** spawned via the Agent tool.

**The callback may block indefinitely** — *"Execution remains paused until your callback returns."*
For an overnight queue that is a hang. The documented escape is important enough to quote:

> *"If a user might take longer to respond than your process can reasonably stay running, register a
> `PreToolUse` hook that returns the `defer` decision instead of waiting in the callback, so the
> process can exit and resume later from the persisted session."*

`"allow" | "deny" | "ask" | "defer"` is VERIFIED in the binary's hook-decision enum. **`defer` is the
right primitive for an unattended queue**: a question parks the session cleanly instead of pinning a
process all night.

The `initialize` response also reports `pending_permission_requests` and `pending_user_dialogs` —
*"so a client joining an already-initialized session learns about in-flight prompts"* — always
present (possibly empty) from **v2.1.268**. A supervisor reattaching after its own crash can re-arm
every stranded prompt. One caveat is documented: *"A prompt inherited from a previous worker of the
same session can remain answerable without appearing here."*

### G3. For a visible session: cross-session messaging

This is the path for terminals the orchestrator cannot pipe, and it **works right now** — VERIFIED by
running `ListAgents` from inside this session:

```
This process's main session is claude-plugins-d5 [ff22dc] — the name OTHER sessions use to message it.
Peer sessions (3):
  design-analysis [5998b9]  ·  interactive  ·  busy  ·  started 7m ago
  project-b-58   [b3f58b]  ·  interactive  ·  busy  ·  started 5d ago
  acceptance-walk [701f5a]  ·  interactive  ·  idle  ·  started 3h ago
```

Discovery, addressing, and **liveness (`busy`/`idle`)** across independent local Claude Code
sessions. The paired `SendMessage` tool delivers into a named session. Delivery is gated by the
`crossSessionInbound` setting — `accept` | `hold` | `refuse` — with permission-mode attestation
between sender and receiver (VERIFIED, binary strings):

- *"The sending session's permission mode class doesn't match this session's. Review it below, or set
  `crossSessionInbound` to `accept`."*
- *"The sender did not attest its permission mode and this session bypasses prompts."*
- A repo may only **tighten**: *"a repo may only tighten, so your own 'accept' cannot override it"*.

There is also `cross_session_notify_idle` in the binary — an idle notification path between
sessions. The cost is real and documented: an inbound message *"is delivered as a new turn when this
session sits idle, sending your full context each time" —* i.e. a nudge is not free, it re-sends the
window.

**Verdict G: fully supported, and better than the field notes assume.** A supervisor that is itself a
Claude Code session can address peers today with no pipe at all; a supervisor holding a pipe gets
acknowledged, id-correlated delivery and can answer the session's own questions.

---

## H. GUARDRAILS

**Permission modes** (VERIFIED, `--help`): `--permission-mode <acceptEdits|auto|bypassPermissions|manual|dontAsk|plan>`.
`default` is also accepted; `manual` is its alias and needs **v2.1.200+**.

**Evaluation order** is documented and fixed (VERIFIED, docs 2026-09-19):
**hooks → deny rules → ask rules → permission mode → allow rules → `canUseTool`.**

Three consequences that matter unattended:

- A **deny rule beats `bypassPermissions`**. `disallowedTools: ["Bash(rm *)"]` holds even in bypass
  mode. A bare name (`"Bash"`, `"*"`, `"mcp__*"`) removes the tool from the model's context entirely.
- **`allowedTools` does not constrain `bypassPermissions`.** Listing `["Read"]` alongside bypass
  still approves `Bash`, `Write`, `Edit`. To narrow a bypass session, use `disallowedTools`.
- Even bypass mode does not auto-approve `rm`/`rmdir` against a **critical path**, connector tools an
  org set to `ask`, or tools marked `_meta["anthropic/requiresUserInteraction"]` — these still reach
  `canUseTool`.

**`dontAsk` is the mode an overnight queue actually wants**, and the docs say so: *"you want a fixed,
explicit tool surface for a headless agent and prefer a hard deny over silent reliance on
`canUseTool` being absent."* Pair it with `allowedTools`. `--permission-prompts none` is the CLI
equivalent — *"nobody: anything that would prompt is denied automatically"*.

**Subagent inheritance:** a subagent runs in the parent's mode; Claude Code never *applies* a
`bypassPermissions` value from an `AgentDefinition` — a subagent is in bypass only when the parent
is (**v2.1.267+**).

**Hooks.** 32 events documented today (VERIFIED, code.claude.com/docs/en/hooks). The bundled
reference inside the binary lists a smaller set (`PermissionRequest, PreToolUse, PostToolUse,
PostToolUseFailure, Notification, Stop, PreCompact, PostCompact, UserPromptSubmit, SessionStart`) —
**the binary's own table is stale relative to the docs**; trust the docs and verify per event.
Ones this orchestrator will use: `SessionStart` (matchers `startup|resume|clear|compact|fork`),
`SessionEnd` (`clear|resume|logout|prompt_input_exit|other`), `Stop`, `StopFailure`, `SubagentStart`,
`SubagentStop`, `TeammateIdle`, `PreCompact`, `PostCompact`, `PermissionRequest`, `Notification`.
Three hook types exist: `command`, `prompt` (LLM-evaluated), `agent` — the latter two only on tool
events.

Hook JSON output: `{systemMessage, continue, stopReason, suppressOutput, decision, reason,
hookSpecificOutput:{hookEventName, additionalContext}}`. `SessionEnd` hooks share a **1.5-second**
budget across all of them.

**Restriction and sandboxing.** `--restricted` removes command-running tools and WebFetch unless
`--tools` names them, ignores user/project/local settings, confines file tools to the working
directories, and **refuses `bypassPermissions`**. `--safe-mode` disables all customizations.
`--bare` skips hooks, LSP, plugin sync, auto-memory, keychain reads and CLAUDE.md discovery, and
forces `ANTHROPIC_API_KEY`/`apiKeyHelper` auth. Sandbox primitives (`sandbox-exec`, `seatbelt`,
`bubblewrap`) are present in the binary; their exact exposure is **UNKNOWN** in this pass.

**Verdict H: richest guardrail surface in the scan.** The orchestrator's default should be
`--permission-mode dontAsk` + explicit `--allowedTools` + a `disallowedTools` floor, **not**
`--dangerously-skip-permissions`.

---

## I. EXTENSIBILITY

**MCP:** full. `claude mcp add|add-json|get|list|login|logout|remove|serve|add-from-claude-desktop|reset-project-choices`,
plus `--mcp-config <configs...>` and `--strict-mcp-config`. With `-p`, `--mcp-config` waits for
pending servers up to `MCP_TIMEOUT` (30 s default) before the first turn (**v2.1.221+**). Tool
definitions are **deferred by default** — only names and server instructions enter context until a
tool is used. The `mcp_call` control request invokes an MCP tool *"without a model turn. No
permission check (control channel is trusted)"* — a supervisor can drive a session's MCP servers
directly, for free, without spending a turn. That is an underrated capability.

**Skills / commands / subagents:** `--agents <json>` defines subagents inline (validated at startup,
**v2.1.242+**); `--agent <name>` selects one; `--plugin-dir`, `--plugin-url` load plugins for one
session; `--disable-slash-commands` kills the lot. A session's available commands arrive in
`system/init.slash_commands`, and its loaded skills in `system/init.skills`. Sending `/<name>`
dispatches a skill **even when the `skills` allowlist omits it**. Since **v2.1.274**, an unknown
`/<name>` costs a model turn instead of returning `Unknown command`.

**Config precedence** (VERIFIED, docs 2026-09-19), highest first:
`--settings` → `.claude/settings.local.json` → `.claude/settings.json` → managed policy →
`~/.claude/settings.json`. Hooks **merge** across levels rather than replacing; `disableAllHooks`
cannot disable managed hooks from outside managed settings. `--setting-sources user,project,local`
selects which layers load at all.

**Can a GSD-style, subagent-heavy engine run inside it?** Yes — it already does here.
`~/.claude/settings.json` shows 20 enabled plugins, `~/.claude/gsd-core`, 66 agents and 33 hooks on
disk, and `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `env`. Agent teams are off by default and need
that variable. The cost is documented and steep: *"Agent teams use approximately 7x more tokens than
standard sessions when teammates run in plan mode."*

**Verdict I: fully supported, and the owner's engine is already resident.**

---

## J. OPERATIONAL REALITY

| | |
|---|---|
| **Version here** | 2.1.278, matching npm `latest` published 2026-09-19 — fully current (VERIFIED) |
| **Install footprint** | 208 MB single native arm64 binary + `~/.claude` content store |
| **macOS** | first-class; this is the reference platform on darwin |
| **Cost model** | subscription (this machine: two `max` accounts, one expired, one absent) or API/Bedrock/Vertex/Foundry per token |
| **Observed session cost** | `totalCostUSD: 79.91` for one long Opus session with 100 M cache-read tokens (VERIFIED, `cost-state`) |
| **Enterprise average** | ~$13/developer/active day, $150–250/month; <$30/active day for 90% of users (CLAIMED, docs) |
| **Maturity** | highest in the scan — versioned capability gates, a documented control protocol, per-field version requirements in the docs |

### Known unattended-run failure modes

1. **Keychain GUI prompt on first use of an account** — blocks silently, forever. Grant "Always
   Allow" once per account by hand.
2. **`CLAUDE_CONFIG_DIR` unset from a daemon** → wrong account, wrong quota, wrong everything.
3. **Usage endpoint rate-limits the poller.** Cache for 60 minutes and back off, as `/usage` does.
4. **Expired OAuth token** reads as an auth error, not a quota error. Probe with `claude auth status`.
5. **Autocompact thrashing** trips a circuit breaker after 3 refills in 3 turns, 3 times running.
6. **Backgrounding cancels quota auto-resume** — *"this session moved to the background, so the task
   will not resume on its own when the usage limit resets."*
7. **`-p` silently ignores invalid settings files** and skips the trust dialog.
8. **A `canUseTool` callback blocks forever** unless a `PreToolUse` hook returns `defer`.
9. **Cross-session messages and scheduled tasks re-send the full window on an idle session**, so a
   chatty supervisor burns the very quota it is protecting.
10. **`--bg` and `-p` cannot be combined**, so one session cannot be both attachable and streamed.

### Is it plausible to run unattended overnight today?

**Yes, and it is the only platform in the scan where that is not a qualified answer.** Every
ingredient exists and is documented: assign the id, launch headless or background, read context and
quota by push, answer permission prompts and clarifying questions over a correlated protocol, park
long questions with `defer`, resume exactly after a crash, and route each role to its own account by
one environment variable. The design work left is in the supervisor, not the platform.

---

## What this costs the orchestrator

| Axis | What it must build | Real cost |
|---|---|---|
| **A** | Two launch adapters, because `--bg` and `-p` are exclusive | Moderate. Decide per role: watchers and graders go headless; anything the owner may take over goes `--bg`/terminal |
| **B** | Generate a UUID per ticket; pass `--session-id`; persist it beside the ticket | Near zero. Do **not** parse ids out of output |
| **C** | A tail-reader for `$CLAUDE_CONFIG_DIR/projects/<encoded-cwd>/<uuid>.jsonl` and the cwd encoder (non-alphanumeric → `-`, truncate at 200 + hash) | Low, one-time. Worth writing once and reusing for every axis that reads proof |
| **D** | A `statusLine` script per config dir that writes `{session_id, context_window, rate_limits, prompt_cache}` to a file the supervisor tails; `refreshInterval: 5` | **Low — and it is the single highest-leverage thing in this profile.** It closes the field notes' "nothing measures the context window" gap for both D and E at once. Caveat: it writes into the owner's `settings.json`, so it needs his explicit consent |
| **D** | Compaction trigger: `/compact` on the stdin lane for piped sessions; `--autocompact <tokens>` at launch for the rest | Moderate. Accept that a terminal session cannot be compacted from outside without typing, and design the threshold instead |
| **D** | Proof: match a `compact_boundary` record with a rising `preTokens`/`postTokens` pair. Distinguish "compacted" from "`Not enough messages to compact.`" | Low |
| **E** | Cache the usage endpoint ≥60 min, back off on 429, treat 401 as cold-account, prefer `limits[]` over named keys, never parse the codename keys | Low, but **get the caching right or it fails exactly when it matters** |
| **E** | Decide who owns the limit wait. `--bg` cancels the CLI's own auto-resume, so the supervisor must re-drive after `resets_at` | Moderate |
| **F** | Read the account's config dir from configuration, probe it with `claude auth status`, set `CLAUDE_CONFIG_DIR` at spawn | **Near zero.** The account is config; do not discover or enumerate profiles |
| **F** | Accept that a running session's account cannot change: stop → relaunch `--resume <id>` under the new dir. Sessions are stored per config dir, so the new dir must be able to see the old transcript | Low |
| **G** | Piped path: an id-correlated control client (send `user`, read `control_request`, answer `can_use_tool`, honour `keep-alive`, handle `control_cancel_request`) | **The largest single build.** It is also the thing the current harness lacks. Read `pending_permission_requests` on reconnect |
| **G** | A `PreToolUse` hook returning `defer` so a question parks a session instead of pinning a process | Low, high value |
| **G** | Unpiped path: `ListAgents` + `SendMessage`, with `crossSessionInbound: accept` on the workers | Low. Budget for the turn cost — every nudge re-sends the window |
| **H** | A default profile: `--permission-mode dontAsk` + explicit `--allowedTools` + a `disallowedTools` floor. Not `--dangerously-skip-permissions` | Low. Mostly a decision |
| **I** | Nothing. GSD, plugins, agents and MCP already run inside it | Zero |
| **J** | Grant Keychain access per account once; pin `CLAUDE_CONFIG_DIR` in every spawn; watch for the autocompact circuit breaker | Low, but each is a silent overnight killer if skipped |

**If only three things get built, build these:** the per-account `statusLine` telemetry writer (D+E
in one stroke), the `defer` hook (stops a question from hanging the night), and the stdin control
client (G, and the only genuinely hard one).

---

## Open questions for a later pass

| # | Question | Axis |
|---|---|---|
| 1 | Does `PreCompact` actually block? Docs say no; the binary carries *"Compaction blocked by PreCompact hook"*. Test it | D, H |
| 2 | Exact `get_context_usage` / `get_usage` response schemas — read from a live stream-json session, not from strings | D, E |
| 3 | What the codename quota keys (`nimbus_quill`, `cedar_ember`, `tangelo`, `iguana_necktie`, …) mean, and whether any is load-bearing | E |
| 4 | Sandboxing: is `sandbox-exec`/`seatbelt` reachable from settings, and what does it confine? | H |
| 5 | Does `claude --bg` accept `--session-id`, so a background session can also be pre-named? | A, B |
| 6 | `~/.claude/daemon/{control.key, dispatch/, attach-journal/, roster.json}` — is there a supported external control path into a background session, short of `attach`? | B, G |
| 7 | Whether `--remote-control` gives a cleaner intervention channel into a visible session than cross-session messaging | G |
| 8 | Behaviour of `--max-budget-usd` as a per-ticket circuit breaker in a `-p` fleet | E, J |

---

## Sources

All read or run on **2026-09-19**.

**Run on this machine (read-only)**
- `claude --version` → `2.1.278 (Claude Code)`
- `claude --help`; `claude agents|auth|project|mcp|plugin|doctor|respawn --help`
- `claude agents --json`, `claude agents --json --all`
- `claude auth status` under several `CLAUDE_CONFIG_DIR` values
- `<switcher> --help`, `<switcher> whoami`, `<switcher> switch --print-env <profile>`
- `security find-generic-password -s "Claude Code-credentials-<hash>"` (key names only)
- `GET https://api.anthropic.com/api/oauth/usage` with `anthropic-beta: oauth-2025-04-20`
- `strings -n 10 ~/.local/share/claude/versions/2.1.278` (323,227 lines) — protocol schemas, hook
  tables, statusLine contract, control-request subtype list, quota-wait strings
- `ListAgents` from inside this session

**Read on disk**
- `~/.claude/projects/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-….jsonl` — message types, `usage`, `cost-state`
- `~/.claude/projects/-<work>-<work-project>/ad544616-….jsonl` — the real `compact_boundary` record
- `~/.claude/jobs/052c2fe5/state.json` and `timeline.jsonl`
- `~/.claude/settings.json`; `~/.claude/daemon/roster.json`; `~/.claude/daemon.log`
- the profile switcher's shell script — Keychain service-name derivation
- `~/.<switcher>/profiles/*/` — symlink layout

**Official documentation (fetched 2026-09-19)**
- `https://code.claude.com/docs/en/hooks` — 32 hook events, PreCompact/PostCompact stdin fields, settings precedence
- `https://code.claude.com/docs/en/cli-reference` — flags, subcommands, per-flag version requirements
- `https://code.claude.com/docs/en/statusline` — stdin JSON contract, `refreshInterval`, `rate_limits`
- `https://code.claude.com/docs/en/agent-sdk/permissions` — six-step evaluation order, modes
- `https://code.claude.com/docs/en/agent-sdk/user-input` — `canUseTool`, `AskUserQuestion`, the `defer` escape
- `https://code.claude.com/docs/en/agent-sdk/sessions` — resume, fork, transcript paths, cross-host
- `https://code.claude.com/docs/en/agent-sdk/slash-commands` — `/compact` over the SDK, `compact_boundary`
- `https://code.claude.com/docs/en/agent-sdk/streaming-vs-single-mode` — the two input modes
- `https://code.claude.com/docs/en/costs` — `/usage`, rate-limit windows, `autoContinueAtUsageLimit`, agent-team costs

**Companion documents**
- `product/spikes/harness-rebuild/research/platforms/00-field-scan.md` — local inventory, profile switcher, `pi`, MiMo
- `plugins/harness/docs/FIELD-NOTES.md` — the 34-hour unattended run this profile is meant to fix
