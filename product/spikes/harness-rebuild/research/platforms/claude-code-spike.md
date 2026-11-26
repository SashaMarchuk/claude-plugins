# Claude Code — orchestrator adapter spike

**Written:** 2026-09-19. **Machine:** owner's Mac, darwin 25.5.0, `claude 2.1.278` (build
`809c980662e3`, `BUILD_TIME 2026-09-19T01:12:36Z`). **Companion:** the capability profile at
`research/platforms/claude-code.md` — read that for *what the platform can do*; this file is *how to
drive it*.

**Evidence tags.** **VERIFIED** = a command run on this machine during this pass, or a string read
out of the installed binary / a file on disk. **CLAIMED** = docs or README only. **UNKNOWN** = could
not establish. Every flag quoted here came from `claude --help`, a subcommand's `--help`, the
binary's own commander definitions, or an error the CLI actually printed. Nothing is guessed.

**What this pass spent.** Two full stream-json control sessions and one background job, all at
`total_cost_usd: 0` and `num_turns: 0` — **no model turn was ever taken** (VERIFIED, `result` frame
below). One `GET` of the OAuth usage endpoint. No config was modified; the two probe sessions and the
probe job were removed.

---

## 0. Eleven corrections to the profile — read these before writing code

Each was found by running the thing, not by reading about it. Several invalidate a design the profile
proposes.

| # | The profile says | What actually happens | Evidence |
|---|---|---|---|
| 1 | `-p --output-format stream-json` is the control-protocol launch | It **refuses to start** without `--verbose`: `Error: When using --print, --output-format=stream-json requires --verbose` | VERIFIED — ran it |
| 2 | Open question: does `--bg` accept `--session-id`? | **No.** `warning: --bg manages the session id; ignoring --session-id (use --resume <id> to continue an existing session)` | VERIFIED — binary string, line 138015 |
| 3 | `--bg` and `-p` "can't be combined" (docs) | Confirmed, and the CLI explains why: *"--bg and --print conflict: --print never starts the interactive session that `claude agents` attaches to, so the job would be unattachable."* | VERIFIED — ran `claude -p --bg "x"` |
| 4 | `claude agents --json` is a free fleet roster | It is **account-scoped for interactive sessions** and **global for background ones**. Under `<profile-A>` it listed 3 interactive sessions; under `<profile-B>`, a completely different 4. The 2 background rows appeared under every profile | VERIFIED — ran it under three `CLAUDE_CONFIG_DIR` values |
| 5 | `defer` is "the right primitive for an unattended queue" | `defer` is **print-mode only**: *"returned permissionDecision=defer in interactive mode; ignoring (defer is print-mode only)"* and *"returned permissionDecision=defer for a served call; refusing (no resume machinery)"*. A `--bg` or terminal session cannot park a question | VERIFIED — binary strings 202249/202251 |
| 6 | A `statusLine` script **per config dir** | All of the profile switcher's profiles **symlink one `settings.json`** at `~/.claude/settings.json`, and the owner already has a statusLine (`bash ~/.claude/statusline-command.sh`). There is exactly one slot for the whole fleet, and it is occupied — the orchestrator must *wrap*, never replace | VERIFIED — `ls -la ~/.<switcher>/profiles/*/` |
| 7 | Proof of compaction is the `compact_boundary` record; absence is ambiguous | Absence is **not** ambiguous on the stream. A compaction emits `system/status status="compacting"` then `system/status compact_result="failed"\|…` with `compact_error`. Start and outcome are both on the wire | VERIFIED — drove `/compact` and captured both frames |
| 8 | `initialize` reports `pending_permission_requests` / `pending_user_dialogs` from v2.1.268 | **Neither key was present** in the `initialize` response on 2.1.278. What is present: `session_state`, `current_permission_mode`, `account`, `pid`, `models`, `agents`, `commands`, `remote_control_available` | VERIFIED — full key list captured |
| 9 | Quota needs the OAuth endpoint (which rate-limits you) | A piped session answers `get_usage` with **the entire endpoint payload, including `limits[]`**, from the CLI's own cache — no HTTP call of yours, no 429 risk | VERIFIED — `get_usage` response captured |
| 10 | Background sessions are durable state | The daemon is **not** installed as a service on this build: *"Service install is disabled in this version — the daemon runs on demand and exits when the last client disconnects."* Background sessions **do not survive a reboot** | VERIFIED — `claude daemon --help` |
| 11 | (not covered) | There is an undocumented `claude --bg --exec <command>` that runs a **plain shell command** as a background job under the same daemon, roster and log surface — zero model tokens. It is the right way to test the whole bg lifecycle, and a useful primitive in its own right | VERIFIED — launched, polled, stopped and removed one |

---

## The two launch shapes, decided once

`--bg` and `-p` are mutually exclusive, so every ticket is one of these before anything else is
decided:

| | **PIPED** (`-p` stream-json) | **ATTACHED** (`--bg`, or a real terminal) |
|---|---|---|
| Session id | **you assign it** (`--session-id`) | **it assigns one** (short 8-hex + a UUID) |
| Context read | `get_context_usage` (exact, live) | statusLine tee, or transcript arithmetic |
| Compaction trigger | `/compact` on the stdin lane | `--autocompact <tokens>` at launch only |
| Quota read | `get_usage` (free, full payload) | statusLine tee, or the OAuth endpoint |
| Instruction in | `user` frame on stdin, acknowledged | only while **stopped**, or cross-session message |
| Permission prompts | `can_use_tool`, answered programmatically | pre-decided by mode + allow/deny lists |
| Question parking | `defer` works | `defer` is ignored |
| Owner can take over | no | yes (`claude attach <id>`) |
| Survives a reboot | no (your process died) | no (daemon is on-demand on this build) |

**Recommendation:** run every ticket **PIPED** and treat "the owner wants to take over" as a
*handoff* — stop the piped session, relaunch the same `--session-id` with `--resume` in a terminal.
The profile's framing (pick a shape per role) trades away the four non-negotiables for a convenience
that a handoff buys back in one command.

---

## 1. Preflight — installed, authenticated, which account

```bash
# binary + build
claude --version                      # -> "2.1.278 (Claude Code)"
claude doctor                         # -> "No installation issues found." + platform/commit/channel

# which account THIS shell would use  (JSON is the default; --text for humans)
claude auth status
```

Real output, VERIFIED:

```json
{ "loggedIn": true, "authMethod": "claude.ai", "apiProvider": "firstParty",
  "projectsDirectory": "<profile-dir>/projects",
  "configDirectory":  "<profile-dir>",
  "email": "<email>",
  "orgId": "<org-id>", "orgName": "…", "subscriptionType": "<plan>" }
```

Enumerate every account and probe each one — VERIFIED, it ran for every profile:

```bash
for d in ~/.<switcher>/profiles/*/; do
  [ -f "$d/.claude.json" ] || continue                 # a dir without one carries no identity
  n=$(basename "$d")
  printf '%-16s ' "$n"
  CLAUDE_CONFIG_DIR="$d" claude auth status \
    | jq -c '{loggedIn, email, subscriptionType, configDirectory}'
done
```

```
<one JSON line per profile — real account data omitted>
```

Two config dirs can resolve to the same underlying account, so anything keyed per dir (quota reads
included) can double-count; a dir can also exist and report `loggedIn: false`.

The Keychain row exists for **every profile**, including one that reports `loggedIn: false` — VERIFIED:

```bash
svc() { [ "$1" = "$HOME/.claude" ] && printf 'Claude Code-credentials' \
        || printf 'Claude Code-credentials-%s' "$(printf '%s' "$1" | shasum -a 256 | cut -c1-8)"; }
# each profile dir → its own Claude Code-credentials-<hash8> service name
```

- **Success:** `loggedIn: true` **and** `configDirectory` equals the dir you set.
- **Failure:** `loggedIn: false` (never signed in), or a present Keychain row with a token the API
  rejects (`OAuth access token has expired`) — an **auth** failure, never a quota failure.
- **Fallback:** none needed. **Do not** gate on the Keychain row; gate on `claude auth status`.
- **Before the first unattended run**, open each account once by hand so macOS records "Always
  Allow" for its Keychain item. An ungranted account blocks on a GUI dialog forever.

`verified: true`

---

## 2. Start a task headless, with a pinned session id, structured output

```bash
SID=$(uuidgen | tr 'A-Z' 'a-z')
export CLAUDE_CONFIG_DIR=~/.<switcher>/profiles/<profile>

claude -p --verbose \
  --input-format  stream-json \
  --output-format stream-json \
  --session-id "$SID" \
  --name "ticket-$TICKET" \
  --permission-mode dontAsk \
  --allowedTools "Read,Grep,Glob,Edit,Write,Bash(git *),Bash(npm test*)" \
  --disallowedTools "Bash(rm *),Bash(sudo *),WebFetch" \
  --autocompact 700k \
  --max-budget-usd 8 \
  --include-hook-events \
  --replay-user-messages \
  --model opus \
  < "$FIFO_IN" > "$LOG_OUT" 2>"$LOG_ERR"
```

**`--verbose` is mandatory.** Without it the process exits before reading a byte:

```
Error: When using --print, --output-format=stream-json requires --verbose
```

(VERIFIED — the omission killed the first probe run with a `BrokenPipeError` on the driver side.)

**Session-id validation is real and fires before any network call** — VERIFIED:

```
$ claude -p --session-id NOT-A-UUID "x"
Error: Invalid session ID. Must be a valid UUID.
```

**Wire contract** (VERIFIED from the binary's own protocol docs): one JSON object per line, both
directions. `initialize` is optional and normally the first line. **Closing stdin tells the CLI to
finish the current turn and exit** — that is the clean-stop primitive in §11.

Hold stdin open (a FIFO or a pipe from a long-lived driver), then write:

```json
{"type":"control_request","request_id":"i1","request":{"subtype":"initialize"}}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<the ticket>"}]},"parent_tool_use_id":null,"session_id":"<SID>"}
```

The `initialize` response, keys VERIFIED verbatim from a live run:

```
account, agents, analytics_disabled, available_output_styles, commands,
current_permission_mode, fast_mode_disabled_reason, fast_mode_state,
ide_rc_auto_enable_gate, models, output_style, pid,
remote_control_auto_connect_default, remote_control_auto_enable,
remote_control_auto_on_by_default, remote_control_available,
session_state, user_output_styles_dir
```

with, on this machine:

```json
{ "account": { "email": "<email>", "subscriptionType": "<plan>",
               "apiProvider": "firstParty" },
  "pid": 96891, "current_permission_mode": "dontAsk", "session_state": "idle",
  "remote_control_available": true }
```

**Record `pid` and `account.email` at this point.** They are the two facts that let you prove, later
and from outside, that the right process is running under the right account (§7).

- **Success:** a `system/init` frame carrying `session_id`, `tools[]`, `slash_commands`, then
  `assistant` frames, then one `result` frame. The `result` frame carries `is_error`,
  `total_cost_usd`, `usage`, `permission_denials[]`, `subagent_stats`, `num_turns`, `stop_reason`.
- **Failure:** the `result` frame's subtype. VERIFIED strings in the binary:
  `error_max_turns`, `error_max_budget_usd`, `error_during_execution`. The last is also
  *"the zeroed `error_during_execution` result a stream-json run writes before exiting on a known
  startup failure; `errors` carries the same text as stderr"*.
- **Fallback:** none — this is the platform's strongest path.
- **Trap:** `-p` **silently ignores settings files that fail validation** and skips the workspace
  trust dialog (VERIFIED, quoted from `--help`). Validate your settings JSON yourself before launch.

`verified: true` — the exact invocation above (minus the ticket prompt) ran here; the responses
quoted are from that run.

---

## 3. Start the same task in a terminal the owner can type into

Three options, in order of preference.

**(a) `--bg` + `claude attach`** — a real session the owner can join from any terminal:

```bash
claude --bg --name "ticket-$TICKET" \
  --permission-mode dontAsk \
  --allowedTools "…" --disallowedTools "…" \
  --autocompact 700k \
  "<the ticket>"
```

Real output, VERIFIED:

```
Starting background service…
backgrounded · 2f22c35b · spike-exec-probe
  claude agents             list sessions
  claude attach 2f22c35b    open in this terminal
  claude logs 2f22c35b      show recent output
  claude stop 2f22c35b      stop this session
```

**You cannot pin the id here.** `--session-id` is accepted and discarded with
`warning: --bg manages the session id; ignoring --session-id (use --resume <id> to continue an
existing session)` (VERIFIED). Capture the short id from stdout (`^[0-9a-f]{8}$`), or read it back
from `claude agents --json`; the full UUID is in the same row as `sessionId`.

Two guardrail gates that will stop an unattended launch dead (VERIFIED, binary strings):

```
--bg with bypassPermissions requires accepting the disclaimer first. Run `claude --dangerously-skip-permissions` once interactively.
--bg with auto mode requires opting in first. Run `claude --permission-mode auto` once interactively.
Background sessions are unavailable with --project-config-root.
```

**(b) A worktree + its own tmux/iTerm pane** — when the ticket should not touch the owner's checkout:

```bash
claude --bg -w "ticket-$TICKET" --tmux "<the ticket>"     # iTerm2 native panes when available
claude --bg -w "ticket-$TICKET" --tmux=classic "<task>"   # traditional tmux
```

**(c) The owner's existing launchers** (`task-launch`, `harness`) that open a real iTerm2 window.
Contract-identical to (a) minus the daemon roster; keep them for anything the owner will watch.

**(d) Zero-token lifecycle rehearsal** — `--exec` runs a shell command as a background job under the
same daemon, roster, `logs` and `stop`:

```bash
claude --bg --name probe --exec 'bash -lc "for i in 1 2 3; do echo tick-$i; sleep 2; done"'
```

Use it in the orchestrator's own smoke test: it exercises spawn → poll → logs → stop → rm without
spending a token. (VERIFIED end to end here.)

- **Success:** the `backgrounded · <id> · <name>` line, and the id appears in `claude agents --json`
  within a second or two.
- **Failure:** `Couldn't start a background session (…)`, or `No background daemon is running.`
- **Fallback:** if `--bg` refuses (bypass disclaimer, auto-mode opt-in, `--project-config-root`),
  fall back to the owner's terminal launcher, which has none of those gates.

`verified: true`

---

## 4. Alive, working, waiting, or finished — from outside

**Four independent surfaces. Use at least two; they disagree.**

### 4a. `claude agents --json` — the roster

```bash
claude agents --json          # active only
claude agents --json --all    # + completed background sessions (13 rows here vs 5)
claude agents --json --cwd /path/to/repo
```

Two row shapes, VERIFIED:

```json
{ "id":"2f22c35b", "kind":"background",  "state":"working",
  "sessionId":"2f22c35b-dfdc-497b-b424-2900161748fb", "name":"spike-exec-probe",
  "cwd":"…", "startedAt":1789824306800 }

{ "pid":21558,     "kind":"interactive", "status":"busy",
  "sessionId":"fe04c8bc-46ed-411c-af57-ba2a861cee56", "name":"ground-up-review-9c", "cwd":"…" }
```

Background rows carry `id` + **`state`**; interactive rows carry `pid` + **`status`**. Observed
values: `state ∈ {working, blocked, stopped, done}`, `status ∈ {busy, idle, waiting}`.

**The account-scoping trap — this is the one that will silently halve your fleet.** The same command,
same machine, same second, under three config dirs (VERIFIED):

```
CLAUDE_CONFIG_DIR=<profile-A> -> 5 rows: 2 background + project-a-60, project-c-3d, ground-up-review-9c
CLAUDE_CONFIG_DIR=<profile-B> -> 6 rows: the SAME 2 background + project-b-58, acceptance-walk,
                                          claude-plugins-d5, design-analysis
CLAUDE_CONFIG_DIR=<profile-C> -> 2 rows: the same 2 background, and nothing else
```

Background jobs are global (because `~/.<switcher>/profiles/*/jobs` all symlink `~/.claude/jobs`);
**interactive sessions are visible only under their own account.** The roster probe must therefore be:

```bash
roster() {
  for d in ~/.<switcher>/profiles/*/; do
    [ -f "$d/.claude.json" ] || continue
    CLAUDE_CONFIG_DIR="$d" claude agents --json 2>/dev/null \
      | jq --arg acc "$(basename "$d")" '.[] | . + {account:$acc}'
  done | jq -s 'unique_by(.sessionId)'      # background rows appear once per account
}
```

VERIFIED — run here, it returned the **whole 9-session fleet** where any single-account read saw 5 or
6, and it correctly labelled which account owns each row:

```json
[ {"account":"<profile-A>","kind":"interactive","name":"project-a-60",              "state":"busy"},
  {"account":"<profile-A>","kind":"interactive","name":"ground-up-review-9c", "state":"busy"},
  {"account":"<profile-A>","kind":"interactive","name":"project-c-3d","state":"busy"},
  {"account":"<profile-B>","kind":"interactive","name":"project-b-58",       "state":"busy"},
  {"account":"<profile-B>","kind":"interactive","name":"design-analysis",     "state":"waiting"},
  {"account":"<profile-B>","kind":"interactive","name":"acceptance-walk",     "state":"idle"},
  {"account":"<profile-B>","kind":"interactive","name":"claude-plugins-d5",   "state":"waiting"},
  {"account":"<profile-B>","kind":"background", "name":"task-review","state":"blocked"},
  {"account":"<profile-B>","kind":"background", "name":"bg-task …", "state":"blocked"} ]
```

### 4b. `~/.claude/jobs/<short-id>/state.json` — the background job's own record

VERIFIED, captured live while the probe job was running and again after stopping it:

```json
{ "state":"working", "detail":"tick-2", "tempo":"active",
  "template":"exec", "respawnFlags":[],
  "providerEnv": { "CLAUDE_CONFIG_DIR": "<profile-dir>" },
  "intent":"bash -lc \"for i in …\"", "name":"spike-exec-probe", "nameSource":"user",
  "sessionId":"2f22c35b-dfdc-497b-b424-2900161748fb",
  "resumeSessionId":"2f22c35b-dfdc-497b-b424-2900161748fb",
  "daemonShort":"2f22c35b", "cwd":"…", "backend":"daemon",
  "createdAt":"2026-09-19T13:25:06.800Z", "updatedAt":"2026-09-19T13:25:09.427Z",
  "firstTerminalAt":null }
```

`detail` is **the last line the job printed** and `tempo` flips `idle` → `active` as it works. A
Claude-backed job additionally carries `cliVersion`, `tokens`, `linkScanPath` (its transcript),
`worktreePath`/`worktreeBranch`, `needs` (the question it is blocked on) and a
`timeline.jsonl` of every state transition. A real blocked one, read here:

```json
{"at":"2026-05-18T10:25:42.191Z","state":"blocked","detail":"Want me to restart it?",
 "text":"Heads up: the `pnpm dev` background process exited …. Want me to restart it?"}
```

`state: "blocked"` + a `needs` string **is the platform telling you a human is required.** Route it.

### 4c. `ListAgents` / `SendMessage` — peers, if the supervisor is itself a Claude Code session

VERIFIED by running `ListAgents` from inside this session:

```
This process's main session is claude-plugins-d5 [ff22dc]
Peer sessions (3):
  design-analysis [5998b9]  ·  interactive  ·  waiting  ·  started 13m ago
  project-b-58   [b3f58b]  ·  interactive  ·  busy     ·  started 5d ago
  acceptance-walk [701f5a]  ·  interactive  ·  idle     ·  started 3h ago
```

Same account scoping as 4a, and the same three names appear in `agents --json` under `<profile-B>` —
the two surfaces agree once the account is right.

### 4d. Transcript liveness — works for **any** session, including ones nobody is piping

`$CLAUDE_CONFIG_DIR/projects/<encoded-cwd>/<session-uuid>.jsonl`. The encoder, VERIFIED against a
session I created: every non-alphanumeric character of the absolute cwd becomes `-`; over 200
characters it is truncated and hashed.

```
cwd  /private/tmp/claude-501/-Users-…-claude-plugins/ac653a10-…/scratchpad/spike/probe
dir  -private-tmp-claude-501--Users-…-claude-plugins-ac653a10-…-scratchpad-spike-probe
```

(Note the doubled `-` where the path contained `/-`.) A working reader is in
`tele/cc-probe.py` below; `mtime` alone is a good cheap heartbeat.

- **Success:** `state`/`status` is one of the live values *and* the transcript's mtime is recent.
- **Failure:** row gone from `agents --json` but present under `--all` → it exited. Row present but
  transcript mtime is minutes stale → hung, not working. `state: "blocked"` → needs a human.
- **Fallback:** `kill -0 <pid>` on an interactive row; `claude logs <id>` on a background one.

`verified: true`

---

## 5. Read context fullness, force a compaction, prove it happened

### 5a. Read it — exact, live, free

On a piped session, send:

```json
{"type":"control_request","request_id":"c1","request":{"subtype":"get_context_usage","detail":"summary"}}
```

`detail` must be `"summary"` or `"full"` (the CLI rejects anything else). `"summary"` answers from
the last response's usage and local estimates; `"full"` counts each category with the token-count
API. **Use `"summary"` for polling.**

Response, VERIFIED verbatim from a live session:

```json
{ "categories": [
    {"name":"System prompt",           "tokens":  3340, "kind":"used"},
    {"name":"System tools",            "tokens":  3822, "kind":"used"},
    {"name":"MCP tools (deferred)",    "tokens": 93802, "kind":"deferred", "isDeferred":true},
    {"name":"System tools (deferred)", "tokens": 24544, "kind":"deferred", "isDeferred":true},
    {"name":"Custom agents",           "tokens":  4821, "kind":"used"},
    {"name":"Memory files",            "tokens":  2622, "kind":"used"},
    {"name":"Skills",                  "tokens":  9933, "kind":"used"},
    {"name":"Messages",                "tokens":   152, "kind":"used"},
    {"name":"Autocompact buffer",      "tokens": 33000, "kind":"buffer"},
    {"name":"Free space",              "tokens":942465, "kind":"free"} ],
  "totalTokens": 24538, "maxTokens": 1000000, "rawMaxTokens": 1000000,
  "percentage": 2, "autocompactSource": "model-default",
  "autoCompactThreshold": 967000, "isAutoCompactEnabled": true,
  "model": "claude-opus-5[1m]", "apiUsage": null,
  "messageBreakdown": { "toolCallTokens":0, "toolResultTokens":0, "attachmentTokens":555,
                        "assistantMessageTokens":0, "userMessageTokens":0,
                        "redirectedContextTokens":0, "unattributedTokens":0,
                        "toolCallsByType":[], "attachmentsByType":[{"name":"hook_success","tokens":555}] },
  "gridRows": [ … ], "agents": …, "mcpTools": …, "memoryFiles": …, "skills": …, "slashCommands": … }
```

Read `percentage` and `totalTokens / maxTokens`. **Classify on `kind`, never on the English name** —
the binary says so explicitly. `autoCompactThreshold` (967000 here) is the level at which the CLI
will compact by itself, so the orchestrator's own threshold must sit *below* it to be the one in
control.

**Note the MCP cost.** 93,802 tokens of MCP tool schemas are *deferred* — they are not in context
until a tool is used, but they will be. Budget for them.

For **attached** sessions, two routes:

**(i) The statusLine tee — the highest-leverage thing in this whole document.** The stdin contract,
quoted verbatim from the binary's bundled schema (VERIFIED):

```
"session_id","session_name","prompt_id","transcript_path","cwd","version",
"model":{"id","display_name"},
"workspace":{"current_dir","project_dir","added_dirs","git_worktree","repo":{host,owner,name}},
"output_style":{"name"},
"context_window":{ "total_input_tokens",      // incl. cache reads/writes
                   "total_output_tokens",
                   "context_window_size",
                   "current_usage": {input_tokens, output_tokens,
                                     cache_creation_input_tokens, cache_read_input_tokens} | null,
                   "used_percentage": number|null, "remaining_percentage": number|null },
"effort":{"level"}, "thinking":{"enabled"}, "cost":{"total_cost_usd", …},
"exceeds_200k_tokens", "agent":{"name","type"}, "worktree":{"name","path","branch"},
"pr":{"number","url","review_state"}, "vim":{"mode"},
"rate_limits":{ "five_hour":{used_percentage,resets_at}, "seven_day":{…}, "spend_limit":{…} },
"prompt_cache":{ "warm","caching_observed","ttl","expires_at","requests","misses",
                 "expected_rebuilds","hit_ratio","cache_write_tokens","miss_recache_tokens",
                 "last_miss_at","last_miss_cause":{causes[],tools_added,tools_removed,
                 system_char_delta},"miss_causes","recache_tokens_if_cold" }
```

The construction is in the binary and settles the arithmetic (VERIFIED, read from source):

```js
total_input_tokens = input_tokens + cache_creation_input_tokens + cache_read_input_tokens
// spend_limit is emitted ONLY when the auth provider is "gateway":
...Oe()==="gateway" && je.overage && { spend_limit: { … } }
```

So on a subscription, `rate_limits.spend_limit` will **never** appear. Do not wait for it.

**There is exactly one statusLine slot on this machine and the owner is using it.** All of the switcher's
profiles symlink `~/.claude/settings.json`, whose `statusLine` is
`{"type":"command","command":"bash ~/.claude/statusline-command.sh"}`. Wrap it:

```bash
# ~/.claude/orchestrator/statusline-tee.sh   — VERIFIED: ran it, owner's bar rendered unchanged
#!/bin/bash
set -u
DIR="${CC_TELEMETRY_DIR:-$HOME/.claude/orchestrator/telemetry}"
REAL="${CC_STATUSLINE_DELEGATE:-$HOME/.claude/statusline-command.sh}"
payload="$(cat)"
mkdir -p "$DIR" 2>/dev/null
sid="$(printf '%s' "$payload" | jq -r '.session_id // "unknown"' 2>/dev/null)"
if [ -n "$sid" ] && [ "$sid" != "unknown" ]; then
  printf '%s' "$payload" | jq -c --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
      at:$at, session_id, session_name, transcript_path, cwd, version,
      model: .model.id,
      ctx_used_pct: .context_window.used_percentage,
      ctx_in:       .context_window.total_input_tokens,
      ctx_size:     .context_window.context_window_size,
      cost_usd:     .cost.total_cost_usd,
      five_hour:    .rate_limits.five_hour,
      seven_day:    .rate_limits.seven_day,
      cache_warm:   .prompt_cache.warm,
      cache_hit:    .prompt_cache.hit_ratio }' > "$DIR/$sid.json.tmp" 2>/dev/null \
    && mv -f "$DIR/$sid.json.tmp" "$DIR/$sid.json" 2>/dev/null
  cat "$DIR/$sid.json" >> "$DIR/$sid.jsonl" 2>/dev/null   # slope, not just level
fi
[ -x "$REAL" ] && printf '%s' "$payload" | "$REAL" && exit 0
[ -f "$REAL" ] && printf '%s' "$payload" | bash "$REAL" && exit 0
exit 0
```

Installed as:

```json
{ "statusLine": { "type": "command",
                  "command": "bash ~/.claude/orchestrator/statusline-tee.sh",
                  "refreshInterval": 5 } }
```

`refreshInterval` (minimum 1 s) re-runs it on a timer *in addition to* event-driven renders, which
otherwise go quiet while a coordinator waits on subagents. Renders are debounced at 300 ms.

Tested here against a synthetic payload matching the verified schema: the telemetry file was written
and the owner's bar came out byte-identical (`Opus [████████████████░░░░] 81% 816.5k tmp`).
**This edits the owner's `settings.json` and therefore needs his explicit consent.**

**(ii) Transcript arithmetic** — last resort, and it has a real flaw. A reader that sums
`message.usage` on the final `assistant` line works, but **the transcript does not record the context
window size**: running it against a 1 M-window session with a 200 k assumption returned
`ctx_used_pct: 126.7`. Get `maxTokens` from `get_context_usage` or `context_window_size` from the
statusLine; never hard-code it.

### 5b. Trigger it

```json
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"/compact"}]},
 "parent_tool_use_id":null,"session_id":"<SID>"}
```

VERIFIED end to end on this machine. For attached sessions the only outside control is
`--autocompact <auto|tokens>` at launch (`auto`, or 100k–1M; `500k`, `200000` and `200` are all
accepted) — it **cannot be changed later**, so pick the threshold when you spawn.

### 5c. Prove it

**On the stream** — the frames, VERIFIED verbatim from a live `/compact`:

```json
{"type":"system","subtype":"status","status":"compacting","session_id":"…","uuid":"…"}
{"type":"system","subtype":"status","status":null,"compact_result":"failed",
 "compact_error":"Not enough messages to compact.","session_id":"…","uuid":"…"}
```

then a **fresh `system/init`** as the context is rebuilt, then a `result` with
`total_cost_usd: 0, num_turns: 0`. The start frame and the outcome frame are both on the wire, so the
supervisor never has to infer from silence — this is better than the docs describe.

**On disk** — the durable record, read out of a real transcript here
(`~/.claude/projects/-<project-dir>/5804e6d0-….jsonl`):

```json
{ "type":"system", "subtype":"compact_boundary", "content":"Conversation compacted", "level":"info",
  "timestamp":"2026-06-15T08:21:12.792Z", "version":"2.1.169", "sessionId":"5804e6d0-…",
  "compactMetadata": { "trigger":"manual", "preTokens":508074, "postTokens":15836,
                       "durationMs":120686,
                       "preCompactDiscoveredTools":["mcp__clickup__clickup_get_task", …],
                       "preservedSegment":{"headUuid","anchorUuid","tailUuid"},
                       "preservedMessages":{"anchorUuid","uuids","allUuids"} } }
```

Timestamped, attributable, with before/after token counts. Also watch for `microcompact_boundary`
(VERIFIED subtype in the binary, alongside `tengu_time_based_microcompact`) — a lighter, time-based
compaction the orchestrator did not ask for; count it separately or your "did my compaction land?"
check will get a false positive.

- **Success:** `compact_result` is not `"failed"`, **or** a new `compact_boundary` line appears with
  `postTokens` well below `preTokens`.
- **Failure:** `compact_result:"failed"` with `compact_error` — `"Not enough messages to compact."`
  is a no-op, not an error. Treat it as "nothing to do".
- **Circuit breaker:** the binary carries *"Autocompact is thrashing: the context refilled to the
  limit within 3 turns of the previous compact, 3 times in a row. A file being read or a tool output
  is likely too large for the context window."* Three `compact_boundary` records in quick succession
  means **stop the ticket**, not "compact harder".
- **Hooks:** `PreCompact` / `PostCompact` both fire with
  `{session_id, hook_event_name, trigger:"manual"|"auto", custom_instructions, cwd, permission_mode}`.
  Docs say neither can block; the binary carries *"Compaction blocked by PreCompact hook"*. **UNKNOWN
  — do not design on blocking.** Use them as a free "it happened" notification for attached sessions.
- **Fallback for an attached session that must be compacted now:** stop it and relaunch
  `--resume <uuid>` piped, then `/compact` on the lane. Since `projects/` is shared, nothing is lost.

`verified: true` for the read, the trigger and both proofs (the failure-path proof was produced
live; the success-path record was read from a real transcript on this machine).

---

## 6. Read remaining quota and the reset time; detect a limit hit in-band

**Three routes, in the order the orchestrator should try them.**

### 6a. `get_usage` on a piped session — free, cached, no HTTP of your own

```json
{"type":"control_request","request_id":"u1","request":{"subtype":"get_usage","skip_behaviors":true}}
```

`skip_behaviors` must be a boolean. **Always pass `true`** — without it the CLI scans every transcript
touched in the last seven days.

Response, VERIFIED from a live run:

```json
{ "session": { "total_cost_usd":0, "total_api_duration_ms":0, "total_duration_ms":12654,
               "total_lines_added":0, "total_lines_removed":0, "model_usage":{} },
  "subscription_type": "max",
  "rate_limits_available": true,
  "rate_limits": {
    "five_hour": {"utilization":47,"resets_at":"2026-09-19T13:50:00.273508+00:00",
                  "limit_dollars":null,"used_dollars":null,"remaining_dollars":null,
                  "locked_reason":null},
    "seven_day": {"utilization":22,"resets_at":"2026-09-26T00:00:00.273529+00:00", …},
    "limits": [ … ], "model_scoped": …, "spend": …, "extra_usage": …,
    "seven_day_breakdown": …, "member_dashboard_available": …,
    "seven_day_opus":null, "seven_day_sonnet":null, "seven_day_cowork":null,
    "seven_day_oauth_apps":null, "seven_day_omelette":null,
    "tangelo":null, "iguana_necktie":null, "nimbus_quill":{"utilization":0,…},
    "cinder_cove":null, "copper_kite":null, "harbor_lantern":null, "wattle_ember":null,
    "amber_ladder":null, "amber_gauge":null, "juniper_tide":null, "cedar_ember":null,
    "omelette_promotional":null },
  "behaviors": null }
```

**`rate_limits` is the entire OAuth-endpoint payload, `limits[]` included** — the CLI already fetched
and cached it. This is the read to prefer: it cannot rate-limit you, and it is per-session so it is
automatically the right account.

### 6b. The statusLine tee — free, push-based, covers attached sessions

`rate_limits.five_hour` / `.seven_day`, each `{used_percentage, resets_at}` with **`resets_at` in
Unix epoch seconds** (the endpoint uses ISO-8601 — convert). Each window *"may be independently
absent, and Claude Code drops a window once its `resets_at` time passes"*. `spend_limit` appears only
behind a gateway (see §5a).

### 6c. The OAuth endpoint — for accounts with no live session

```bash
acct_usage() {           # $1 = CLAUDE_CONFIG_DIR
  local svc tok
  svc=$([ "$1" = "$HOME/.claude" ] && printf 'Claude Code-credentials' \
        || printf 'Claude Code-credentials-%s' "$(printf '%s' "$1" | shasum -a 256 | cut -c1-8)")
  tok=$(security find-generic-password -s "$svc" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty')
  [ -z "$tok" ] && { echo '{"error":"no-token"}'; return 1; }
  curl -s --max-time 20 https://api.anthropic.com/api/oauth/usage \
    -H "Authorization: Bearer $tok" -H "anthropic-beta: oauth-2025-04-20"
}
```

Live response for one profile today, VERIFIED:

```json
{ "five_hour": {"utilization":46.0,"resets_at":"2026-09-19T13:50:00.272071+00:00",
                "limit_dollars":null,"used_dollars":null,"remaining_dollars":null,"locked_reason":null},
  "seven_day": {"utilization":21.0,"resets_at":"2026-09-26T00:00:00.272093+00:00", …},
  "limits": [
    {"kind":"session","group":"session","percent":46,"severity":"normal",
     "resets_at":"2026-09-19T13:50:00.272071+00:00","scope":null,"is_active":true},
    {"kind":"weekly_all","group":"weekly","percent":21,"severity":"normal",
     "resets_at":"2026-09-26T00:00:00.272093+00:00","scope":null,"is_active":false},
    {"kind":"weekly_scoped","group":"weekly","percent":0,"severity":"normal",
     "resets_at":"2026-09-26T00:00:00+00:00",
     "scope":{"model":{"id":null,"display_name":"Fable"},"surface":null},"is_active":false} ],
  "extra_usage": {"is_enabled":false,"monthly_limit":null,"used_credits":null,
                  "spend_limit_reached":false,"credits_ever_enabled":true,"user_disabled":true, …} }
```

**Parse `limits[]`, not the top-level names.** It is self-describing (`kind`, `group`, `percent`,
`severity`, `resets_at`, `scope.model.display_name`, `scope.surface`, `is_active`) and it carries the
per-model weekly window the flat keys do not. The other top-level keys include codenames
(`nimbus_quill`, `cedar_ember`, `iguana_necktie`, `tangelo`, `harbor_lantern`, `amber_gauge`,
`wattle_ember`, `juniper_tide`, `copper_kite`, `cinder_cove`, `amber_ladder`, `omelette_promotional`)
whose meaning is **UNKNOWN**. Never parse by name.

**Windows that exist:** rolling **5-hour** (`kind:"session"`), **7-day** (`weekly_all`), **per-model
7-day** (`weekly_scoped`), plus `extra_usage` credits and, behind a gateway, a spend limit.

**Cache for ≥60 minutes and back off on 429.** The endpoint rate-limits its own callers; Claude
Code's `/usage` handles this by showing *"the last usage bars it loaded on this machine within the
past 60 minutes"*. A supervisor that polls every session every minute will lock itself out of exactly
the number it needs. **Treat 401 as a cold account, not an over-limit account** — the Keychain token
expires and only Claude Code refreshes it.

### In-band detection

- `rate_limit_event` — a `system` subtype on the output stream (VERIFIED, alongside
  `compact_boundary`, `api_retry`, `turn_preempted`, `model_fallback`). The retry frame carries
  `rate_limit_type` and `retry_in_ms`.
- `--max-budget-usd <amount>` is a hard per-ticket circuit breaker in `-p` mode; it ends the run with
  result subtype `error_max_budget_usd` (VERIFIED string).
- The CLI's **own** wait-and-resume is real but conditional (VERIFIED strings):
  `hasArmedQuotaAutoResume`, `quota-auto-resume`, `quota-auto-resume-cap`,
  `quota-auto-resume-cancelled`, and
  - *"the usage limit now resets more than 24 hours out, so this task will not resume on its own"*
  - *"Claude Code exited during the wait, so the task will not resume on its own"*
  - *"this session moved to the background, so the task will not resume on its own"*

  **Read the last one carefully: backgrounding cancels the auto-resume.** The orchestrator owns the
  re-drive for every `--bg` session. Fleet-wide, `autoContinueAtUsageLimit` in managed settings
  controls whether the CLI starts the wait at all (v2.1.234+).

- **Policy this pass recommends:** weekly ≥ 90 % → stop and schedule a wake after
  `limits[].resets_at` for `weekly_all`; 5-hour near exhaustion → pause until its `resets_at` (it is
  soon); 80–90 % → stop dispatching new tickets, let running ones finish.

`verified: true` for 6a and 6c (both run here); 6b's schema is verified from the binary, its live
payload was not captured because statusLine does not render in `-p` mode.

---

## 7. Switch a new session to a different account, and verify before work starts

**One environment variable. Nothing else.**

```bash
eval "$(<switcher> switch --print-env <profile>)"   # -> export CLAUDE_CONFIG_DIR="/Users/…/<profile>"
# or, without the switcher:
export CLAUDE_CONFIG_DIR="$HOME/.<switcher>/profiles/<profile>"
```

`<switcher> switch --print-env` prints exactly one line and mutates nothing (VERIFIED). Accounts are
**discovered, not enumerated**: any directory under `~/.<switcher>/profiles/` holding a `.claude.json`.

**Verify three times — before, at, and after launch:**

```bash
# 1. before: is this account usable at all?
CLAUDE_CONFIG_DIR="$D" claude auth status | jq -e '.loggedIn and (.configDirectory == $ENV.D)'

# 2. at launch (piped): the initialize response carries it
#    -> response.account.email, response.account.subscriptionType, response.pid

# 3. after launch (background): the job recorded it
jq -r '.providerEnv.CLAUDE_CONFIG_DIR' ~/.claude/jobs/<short-id>/state.json
```

Step 3 is VERIFIED — the probe job's `state.json` contained
`"providerEnv": {"CLAUDE_CONFIG_DIR": "<profile-dir>"}`, captured by
the daemon at spawn. That is a durable, external, after-the-fact proof of which account a running job
belongs to.

**Two traps:**

1. `~/.claude.json` and `~/.claude/.claude.json` are **different files**. The former is what Claude
   Code reads when `CLAUDE_CONFIG_DIR` is unset — i.e. from a daemon, a cron job, or a GUI-launched
   shell. A supervisor that forgets the variable silently runs on the wrong account, with the wrong
   quota, and the roster probe in §4 will not even show it.
2. macOS prompts once per account for Keychain access. Grant "Always Allow" by hand before the first
   unattended run.

**Changing a running session's account: not supported.** Nothing in the control-request list, the CLI
or the docs does it, and the binary warns when the variable moves under a live process:
*"where your own settings are found (CLAUDE_CONFIG_DIR, the HOME it defaults from, …) changed after
Claude Code started: set it in the shell, not a settings file."*

**Fallback (and it is cheap):** stop the session, relaunch `--resume <uuid>` under the new
`CLAUDE_CONFIG_DIR`. Every profile symlinks `projects`, `jobs`, `history.jsonl`, `file-history` and
`shell-snapshots` at `~/.claude`, so **the transcript is already visible to the new account** and
nothing is lost. That shared store is what makes cross-account resume work at all.

`verified: true`

---

## 8. Deliver an instruction into a running session and confirm it arrived

### 8a. Piped session — the strong path

Write a `user` StdinMessage on the lane:

```json
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Stop after the current file and summarise."}],"role":"user"},
 "parent_tool_use_id":null,"session_id":"<SID>"}
```

VERIFIED: a `user` frame written mid-session was accepted and acted on (the `/compact` probe in §5
used exactly this shape and produced `status:"compacting"` two seconds later).

**Confirmation, three ways:**

1. `--replay-user-messages` — *"re-emit user messages from stdin back on stdout for
   acknowledgment."* **Caveat found here: it did not echo a slash command.** A `/compact` sent on the
   lane produced no replayed `user` frame. Verify the echo for ordinary text before you rely on it,
   and never treat "no echo" as "not delivered" for a `/`-prefixed message. (VERIFIED negative.)
2. Any control request you send is answered with a `control_response` carrying **the same
   `request_id`** — id-correlated in both directions. *"A requester ignores responses for
   `request_id`s it is not waiting on."* `control_cancel_request` withdraws one in flight; the CLI
   emits a `keep-alive` frame *"periodically, for example while a long-running control request is in
   progress."*
3. The observable effect on the stream (a `status` frame, a new `assistant` turn).

Re-steering without stopping, all acknowledged, two VERIFIED live here:

```json
{"type":"control_request","request_id":"p1","request":{"subtype":"set_permission_mode","mode":"plan"}}
-> {"type":"control_response","response":{"subtype":"success","request_id":"p1","response":{"mode":"plan"}}}
-> {"type":"system","subtype":"status","status":null,"permissionMode":"plan","session_id":"…"}

{"type":"control_request","request_id":"x1","request":{"subtype":"interrupt"}}
-> {"type":"control_response","response":{"subtype":"success","request_id":"x1","response":{"still_queued":[]}}}
```

`still_queued` is the `interrupt_receipt_v1` capability (advertised on `system/init`; older CLIs send
an empty success with no such field). Others available: `set_model`, `set_max_thinking_tokens`,
`update_settings`, `rename_session`, `fork_conversation`, `rewind_conversation`, `rewind_files`,
`end_session`, `mcp_call`, `list_models`, `get_settings`, `mcp_status`, `mcp_reconnect`,
`reload_skills`, `reload_output_styles`, `list_permission_rules`, `stage_file`, `add_directory`,
`background_tasks`, `poll_event`, `remote_control`, `request_user_dialog`.

`mcp_call` is underrated: it *"invokes an MCP tool without a model turn. No permission check (control
channel is trusted)"* — the supervisor can drive a worker's MCP servers for free.

### 8b. Background session — **only while it is stopped**

```bash
claude --bg --resume <short-id> "the new instruction"
```

This wakes the job **with its saved `respawnFlags`** and delivers the text as the initial prompt
(`note: woke session <id> with its saved options (…)`). Three outcomes, all VERIFIED as strings in the
binary:

- delivered → the job restarts and runs it;
- **already running** → `Session <id> is already running — \`claude attach <id>\` to join it`, exit 1,
  **nothing delivered**;
- daemon unreachable → `Your message is saved and will be delivered when session <id> next starts.`

**So the CLI cannot push a message into a *running* background session.** That is the single hardest
constraint on this axis and it is why §"the two launch shapes" recommends piped for everything the
orchestrator must steer.

### 8c. Cross-session messaging — for terminals you cannot pipe

`ListAgents` + `SendMessage`, available inside any Claude Code session (VERIFIED: `ListAgents` ran
here and returned three addressable peers with `busy`/`idle`/`waiting`). Delivery is gated by
`crossSessionInbound` — `accept` | `hold` | `refuse` — with permission-mode attestation between
sender and receiver (VERIFIED strings):

```
The sending session's permission mode class doesn't match this session's. Review it below, or set "crossSessionInbound" to "accept".
The sender did not attest its permission mode and this session bypasses prompts.
This repository's settings set "crossSessionInbound" to "hold" (a repo may only tighten, so your own "accept" cannot override it).
```

Set `crossSessionInbound: "accept"` on workers the orchestrator will nudge. **Budget for the cost:**
an inbound message *"is delivered as a new turn when this session sits idle, sending your full context
each time"* — a chatty supervisor burns the quota it is protecting. There is also a hidden
`--messaging-socket-path <path>` flag (*"Cross-session messaging server path: a Unix domain socket on
Mac/Linux … defaults to an auto-generated path"*, VERIFIED in the binary's commander setup) which
would let the orchestrator put a whole fleet on one known socket. Its behaviour is **UNKNOWN** —
worth a follow-up spike.

- **Success:** an echoed `user` frame, a matching `control_response`, or a `status` frame changing.
- **Failure:** `Session <id> is already running`; a held cross-session message; silence on the lane.
- **Fallback:** the last resort the field notes already condemn — typing into a TUI. Do not build it.

`verified: true` for 8a (delivery, `set_permission_mode`, `interrupt`, the replay caveat) and for the
`ListAgents` half of 8c; 8b's outcomes are verified as binary strings, not run.

---

## 9. Answer a permission prompt or a clarifying question without a human

**Both arrive on the same channel: the `can_use_tool` control request.** Claude Code requests user
input in two situations — a tool needs permission, or it has clarifying questions via
`AskUserQuestion` — and both trigger the same callback.

**Permission answer** (payload validated by the CLI; the error it prints when you get it wrong is
`Expected {behavior: 'allow', updatedInput?: object} or {behavior: 'deny', message: string}` —
VERIFIED string):

```json
{"behavior":"allow","updatedInput":{ …the original tool input… },"updatedPermissions":[ … ]}
{"behavior":"deny","message":"denied by orchestrator policy: writes outside the ticket worktree"}
```

`updatedInput` was **required** for an allow before v2.1.207; pass it through anyway. If it is
missing the CLI logs *"updatedInput is missing or empty, falling back to original tool input"* and
carries on. `updatedPermissions` echoes a `PermissionUpdate` from `context.suggestions` — the
"approve and remember" path that writes a rule into `.claude/settings.local.json` so the same prompt
never recurs. Malformed values are dropped with
*"Malformed updatedPermissions from SDK host ignored"*.

**Clarifying-question answer** — an allow whose `updatedInput` carries the answers keyed by question
text; the original `questions` array is **required**:

```json
{"behavior":"allow",
 "updatedInput":{"questions":[ /* the original array, unchanged */ ],
                 "answers":{"Which branch should I target?":"main",
                            "Include migrations?":["schema","seed"]},
                 "response":"optional freeform reply instead of answering"}}
```

Limits: 1–4 questions, 2–4 options each. **`AskUserQuestion` is not available in subagents** spawned
via the Agent tool, so a fan-out cannot ask.

**The hang, and the escape.** *"Execution remains paused until your callback returns."* For an
overnight queue that is a stall. The documented escape is a `PreToolUse` hook returning the `defer`
decision, so the process can exit and resume later from the persisted session:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer",
                       "permissionDecisionReason":"parked for the operator"}}
```

**`defer` is print-mode only.** VERIFIED strings:

```
returned permissionDecision=defer in interactive mode; ignoring (defer is print-mode only)
returned permissionDecision=defer for a served call; refusing (no resume machinery)
Deferred tool resume: permissionMode mismatch (deferred under '<mode>')
```

So an attached (`--bg` or terminal) session **cannot park a question**. For those, the answer is
prevention, not handling:

```
--permission-mode dontAsk  +  --allowedTools "<explicit list>"  +  --disallowedTools "<floor>"
--permission-prompts none      # "nobody: anything that would prompt is denied automatically"
```

The evaluation order is fixed and documented:
**hooks → deny rules → ask rules → permission mode → allow rules → `canUseTool`.** Three consequences
that matter unattended:

- a **deny rule beats `bypassPermissions`** — `disallowedTools: ["Bash(rm *)"]` holds in bypass mode;
- **`allowedTools` does not constrain `bypassPermissions`** — to narrow a bypass session use
  `disallowedTools`;
- even bypass does not auto-approve `rm`/`rmdir` against a critical path, connector tools an org set
  to `ask`, or tools marked `_meta["anthropic/requiresUserInteraction"]`.

The owner's `~/.claude/settings.json` currently sets `permissions.defaultMode: "bypassPermissions"`
(VERIFIED). **The orchestrator must override this per launch** with `--permission-mode dontAsk` plus
an explicit `--allowedTools`, and must not inherit it.

- **Success:** a `control_response` to the `can_use_tool` request; the session proceeds.
- **Failure:** the callback never returns → the session hangs forever. Give the driver a deadline and
  deny on timeout with an explanatory `message`; the denial is recorded in the `result` frame's
  `permission_denials[]`.
- **Fallback for attached sessions:** none. Pre-decide with modes and lists, and route
  `state: "blocked"` jobs to the operator.

`verified: partial` — the channel, the payload validator's own error text, the `defer` restriction and
every permission flag were read in the installed binary or its help; **the `can_use_tool` round trip
itself was not exercised**, because it needs a real tool call and therefore a real model turn. Treat
the answer payloads above as CLAIMED-from-source until someone runs one.

---

## 10. Resume after a crash, and after a reboot

### After a crash (the process died, the machine did not)

```bash
CLAUDE_CONFIG_DIR="$ACCT" claude -p --verbose \
  --input-format stream-json --output-format stream-json \
  --resume "$SID" --permission-mode dontAsk --allowedTools "…"
```

`--resume` accepts a **session ID**, a **name**, or the **absolute path to the `.jsonl` transcript**.
Lookup searches the current project directory and its git worktrees first, then every other project
on this machine (cross-directory lookup since v2.1.223). `--fork-session` branches instead of
continuing. `--continue` takes the most recent conversation in the cwd. One validation rule to know:

```
Error: --session-id can only be used with --continue or --resume if --fork-session is also specified.
```

Nothing is lost but the in-flight turn: the `.jsonl` is append-only and every completed message is
already on disk.

**Resuming a *background* session:**

```bash
claude --bg --resume <short-id>          # continues under the same id
claude respawn <id> | claude respawn --all   # restart so it picks up the current binary
```

`~/.claude/jobs/<id>/state.json` holds everything needed: `sessionId`, `resumeSessionId`,
`respawnFlags[]`, `providerEnv.CLAUDE_CONFIG_DIR`, `cwd`, `worktreePath`, `cliVersion`, `template`,
and for Claude-backed jobs `linkScanPath` (the transcript) and `tokens`. VERIFIED on disk for both a
real long-lived job and the probe job I created.

One documented cost to surface to the owner:
*"Resuming the full session will consume a substantial portion of your usage limits. We recommend
resuming from a summary."*

### After a reboot

**The daemon does not come back.** VERIFIED from `claude daemon --help` on 2.1.278:

> *"Service install is disabled in this version — the daemon runs on demand and exits when the last
> client disconnects."*

(The binary still carries the older string *"Installing it as a service keeps the background daemon
running across reboot so 'claude agents' stays available"* — that path is disabled on this build.)

So after a reboot:

- every background session is gone from `claude agents --json` (it will appear under `--all` if its
  job dir survives);
- `~/.claude/jobs/<id>/state.json` **survives**, and it contains the relaunch recipe;
- the transcript survives.

**The orchestrator owns reboot recovery.** Its own restart procedure:

```bash
for j in ~/.claude/jobs/*/; do
  s="$j/state.json"; [ -f "$s" ] || continue
  jq -r 'select(.state == "working" or .state == "blocked")
         | [.daemonShort, .resumeSessionId, .cwd, .providerEnv.CLAUDE_CONFIG_DIR,
            (.respawnFlags | join(" "))] | @tsv' "$s"
done
# then, per row:  cd "$cwd" && CLAUDE_CONFIG_DIR="$acct" claude --bg --resume "$short" $flags
```

VERIFIED — this loop runs and returns real relaunch recipes here, including one job whose
`respawnFlags` is 24 `--allowed-tools` entries plus `--permission-mode bypassPermissions`. Two
caveats the real output exposed:

- **`providerEnv` is not on older job records.** Both pre-existing jobs on this machine returned an
  empty account column; only the job I created today carried
  `providerEnv.CLAUDE_CONFIG_DIR`. When it is missing, fall back to the canonical store
  (`~/.claude`) and say so in the log rather than guessing an account.
- **`cwd` is hostile to a naive shell.** One real job's cwd is
  `/Users/…/Work/Some&Co/My Project site` — a space *and* an `&`. Quote
  every field, and prefer `@tsv` + `IFS=$'\t' read -r` over word-splitting.

- **Success:** the resumed session's first `system/init` reports the same `session_id`, and the
  transcript gains new lines after the crash timestamp.
- **Failure:** `--resume` cannot find the id (wrong `CLAUDE_CONFIG_DIR`, or the transcript was
  purged); a bg resume prints `Session <id> is already running` because a zombie holds it.
- **Fallback:** resume by **absolute transcript path** — it bypasses the whole lookup. Since
  `projects/` is shared across profiles, this works from any account.
- **Cross-host resume is not supported**: a session file is machine-local. Moving the `.jsonl` is the
  only route, and the SDK's `sessionStore` adapter the only sanctioned one.

`verified: partial` — the flags, the `--session-id`/`--fork-session` validation rule, the job-state
contents and the daemon's no-service statement were all read or run here, and the reboot-recovery loop
runs against real jobs; **an actual crash-resume round trip was not performed**, because resuming a
conversation costs a model turn.

---

## 11. Stop it cleanly, leaving nothing running

**Piped session** — in order of politeness:

```json
{"type":"control_request","request_id":"s1","request":{"subtype":"interrupt"}}
{"type":"control_request","request_id":"s2","request":{"subtype":"end_session"}}
```

then **close stdin**: *"Closing the stream tells the CLI to finish the current turn and exit."*
VERIFIED — both probe sessions exited `0` on stdin close, and the final `result` frame carried
`total_cost_usd: 0`. `SIGTERM` the pid from `initialize.pid` only if it is still alive after a
deadline.

**Background session** — VERIFIED end to end here:

```bash
claude stop 2f22c35b     # -> "stopped 2f22c35b"   (conversation kept; resumable)
claude rm   2f22c35b     # -> "removed 2f22c35b"   (job dir gone; works on exited sessions too)
```

Observed transitions, each read from `~/.claude/jobs/2f22c35b/state.json`:

```
launch  -> state=working  tempo=idle   detail=""
running -> state=working  tempo=active detail="tick-2"
stop    -> state=stopped  tempo=idle   + lastTerminalAt
           (disappears from `agents --json`, still present under `--all` as state=stopped)
rm      -> job directory gone
```

`claude rm` also reports what it could not clean, and takes the value back:

```
--discard-unpushed <commit>@<worktree-id>   discard the worktree's unpushed commits
--force-remove-worktree <worktree-id>       delete a worktree git/hooks refused to remove
```

**The whole fleet:**

```bash
claude daemon status                    # pid, version, uptime
claude daemon stop --any                # also stops a transient (non-service) daemon
claude daemon stop --keep-workers       # shut the supervisor, leave detached sessions running
```

**Leave-nothing-running checklist:**

1. `claude agents --json` **under every account dir** returns no rows you own (§4a);
2. no orphan pid from any `initialize.pid` you recorded;
3. `~/.claude/jobs/` holds no job dir for a ticket you retired;
4. worktrees created with `-w` are removed (`claude rm` does it, and tells you when it could not);
5. `claude daemon status` reports no daemon, or one you did not start.

Deep cleanup of a scratch project, if a ticket's directory is disposable —
`claude project purge [--dry-run|-y|-i|--all] <path>`, VERIFIED here on the probe directory:

```
$ claude project purge --dry-run /…/scratchpad/spike/probe
Purge plan for /…/scratchpad/spike/probe:
  dir:    /Users/…/.<switcher>/profiles/<profile>/projects/-private-tmp-…-scratchpad-spike-probe
           project transcripts (.jsonl) and memory/
shell-snapshots/ are not project-scoped and will not be touched
backups/ may still contain this project entry in old .claude.json snapshots …
Dry run: 1 item(s) would be deleted.

$ claude project purge -y /…/scratchpad/spike/probe
Purged 1 item(s) for /…/scratchpad/spike/probe.
```

**Always `--dry-run` first in an automated path.** Note what it does *not* clean:
`shell-snapshots/` is not project-scoped, and up to five `.claude.json` backups may still name the
project until they rotate out.

`verified: true`

---

## The adapter interface this platform needs

```
ClaudeCodeAdapter implements PlatformAdapter {

  preflight()            -> claude --version; claude doctor;
                            for each ~/.<switcher>/profiles/*/ with .claude.json:
                              CLAUDE_CONFIG_DIR=$d claude auth status   (JSON)
  launchHeadless(t)      -> claude -p --verbose --input-format stream-json
                              --output-format stream-json --session-id <uuid> …
                            (driver holds stdin open; NEVER omit --verbose)
  launchAttached(t)      -> claude --bg [-w <name>] [--tmux] "<task>"   (id is assigned, not pinned)
  list()                 -> union over accounts of `claude agents --json`, unique_by(.sessionId)
  status(s)              -> roster row + jobs/<id>/state.json + transcript mtime
  readContext(s)         -> get_context_usage{detail:"summary"}  |  telemetry/<sid>.json
  compact(s)             -> "/compact" as a user frame            |  --autocompact at launch
  proveCompaction(s)     -> system/status{compact_result} on the wire
                            + compact_boundary in the .jsonl (ignore microcompact_boundary)
  readQuota(acct|s)      -> get_usage{skip_behaviors:true}  |  telemetry  |  OAuth endpoint (cached 60m)
  selectAccount(acct)    -> CLAUDE_CONFIG_DIR=<dir> at spawn; verify auth status, then
                            initialize.account.email, then jobs/<id>/state.json.providerEnv
  send(s, text)          -> user frame on stdin (piped)
                            | claude --bg --resume <id> "<text>"  (STOPPED bg only)
                            | SendMessage (cross-session, costs a full-window turn)
  answerPrompt(s, a)     -> control_response to can_use_tool
  resume(s)              -> claude [-p …] --resume <uuid|name|transcript-path>
  stop(s)                -> interrupt -> end_session -> close stdin  |  claude stop/rm <id>
}
```

### Which of the eleven are native, emulated, or impossible

| # | Recipe | Piped (`-p`) | Attached (`--bg`) | Notes |
|---|---|---|---|---|
| 1 | Preflight | **native** | **native** | `claude auth status` is JSON with no TTY |
| 2 | Headless + pinned id + structured output | **native** | n/a | `--verbose` mandatory |
| 3 | Visible, attachable terminal | n/a | **native** | id cannot be pinned |
| 4 | Liveness from outside | **native** | **native** | must union across accounts |
| 5a | Read context | **native** | **emulated** (statusLine tee, or transcript arithmetic) | tee needs the owner's consent |
| 5b | Trigger compaction | **native** | **impossible from outside** — pre-commit `--autocompact` at launch | |
| 5c | Prove compaction | **native** (wire) | **native** (transcript) | better than documented |
| 6 | Quota + reset + in-band hit | **native** (`get_usage`) | **emulated** (tee / endpoint) | never poll the endpoint per session |
| 7 | Account switch for a NEW session | **native** | **native** | running-session switch **impossible** |
| 8 | Deliver an instruction | **native**, acknowledged | **emulated, degraded** — CLI refuses a running bg job; cross-session costs a full-window turn | |
| 9 | Answer a prompt / question | **native** (`can_use_tool`, `defer`) | **impossible** — `defer` is print-mode only; prevent with modes + lists | |
| 10 | Resume after crash | **native** | **native** | after **reboot**: emulated — the orchestrator relaunches from `jobs/*/state.json`; the daemon does not restart itself on this build |
| 11 | Clean stop | **native** | **native** | verified end to end |

**Nothing here is impossible in the piped shape except changing a running session's account.** Every
"impossible" in the attached column has the same escape hatch — stop, relaunch `--resume <uuid>`
piped — which costs one restart and loses nothing, because `projects/` is shared across accounts.

### Support tier

**TIER 1.** The only platform in the scan that answers all four of the owner's non-negotiables
(context, quota, accounts, intervention) with a documented, id-correlated surface rather than a
workaround, and the only one where an unattended overnight run needs no qualifier. Both of the
profile's "real gaps" turn out to be design choices rather than blockers: the `--bg`/`-p` exclusivity
is settled by running everything piped and treating owner takeover as a handoff, and
"no way to force compaction on a session that is not listening on a pipe" is answered by *putting
every session on a pipe*.

**The three things to build first, unchanged from the profile's advice but now with exact recipes:**

1. **the stdin control client** (§2, §8, §9) — the largest build and the only genuinely hard one;
   everything else is a file read or a one-line command;
2. **the statusLine tee** (§5a) — closes context *and* quota for attached sessions in one script, but
   it edits the owner's `settings.json`, so it needs his explicit yes;
3. **the account-union roster** (§4a) — twenty lines, and without it the supervisor is blind to most
   of its own fleet.

**The five silent overnight killers, each with its counter:**

| Killer | Counter |
|---|---|
| `--verbose` omitted → the process never starts | assert it in the launcher, not in a comment |
| `CLAUDE_CONFIG_DIR` unset from a daemon/cron → wrong account, wrong quota, invisible to the roster | pin it in every spawn; verify three times (§7) |
| roster read under one account → half the fleet invisible | union over accounts, `unique_by(.sessionId)` |
| usage endpoint polled per session → 429, exactly when quota matters | prefer `get_usage`; cache the endpoint ≥60 min |
| reboot → every background session gone, daemon does not return | reconstruct from `~/.claude/jobs/*/state.json` on orchestrator start |

---

## Still open after this pass

| # | Question | Axis | Why it matters |
|---|---|---|---|
| 1 | What does `--messaging-socket-path <path>` actually do? A known socket per fleet would make cross-session delivery deterministic | G | could replace the degraded attached-session path |
| 2 | Does `PreCompact` really block? Docs say no; the binary carries *"Compaction blocked by PreCompact hook"* | D, H | a custom-compaction hook would be worth a lot |
| 3 | The `can_use_tool` request payload as it appears on the wire (shape of `context.suggestions`) — needs one real tool call | G | the answer format is verified; the *request* format is not |
| 4 | `--sdk-url <url>` (hidden): a remote WebSocket endpoint for SDK I/O, `-p` + stream-json only | A, G | would move the control lane off pipes entirely |
| 5 | What `--exec` jobs can and cannot do (restart policy, env, exit-code capture) | A, J | a free non-model primitive inside the same roster |
| 6 | Whether `--workload <tag>` (hidden, `-p` only, "billing-header attribution") lets the orchestrator attribute spend per ticket | E, J | per-ticket cost accounting without parsing transcripts |
| 7 | Do the codename quota keys ever become load-bearing? | E | today: never parse them by name |
| 8 | `~/.claude/daemon/{control.key, dispatch/, attach-journal/, roster.json}` — a supported external control path into a running bg session, short of `attach`? | B, G | would fix the one real intervention gap |

---

## Appendix — files this spike produced, and what they prove

All under `/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/spike/`:

| File | What it is |
|---|---|
| `ctl.py` / `ctl-out.jsonl` | the zero-token control-protocol driver and its captured stream: `initialize`, `get_context_usage`, `get_usage`, `list_models` |
| `ctl2.py` / `ctl2-out.jsonl` | the second driver: `/compact` on the stdin lane, `set_permission_mode`, `interrupt`, and the post-compaction `system/init` |
| `tele/statusline-tee.sh` | the statusLine wrapper, tested against a synthetic payload with the owner's real bar delegated to and rendered unchanged |
| `tele/cc-probe.py` | the on-disk session reader: cwd encoder, transcript locator, last-`usage` arithmetic, `compact_boundary` extractor |
| `usage.json` | the live OAuth usage response for one profile, 2026-09-19 |
| `strings.txt` | 347,678 lines of `strings -n 8` over the 2.1.278 binary — the source for every quoted internal string here |

**Commands run on this machine for this spike (all read-only or self-cleaning):**
`claude --version`; `claude --help`; `claude {agents,attach,logs,stop,rm,respawn,auth,auth status,daemon,project} --help`;
`claude doctor`; `claude auth status` under every config dir; `claude agents --json` / `--json --all`
under three config dirs; `claude -p --session-id NOT-A-UUID "x"`; `claude -p --bg "x"`;
`claude --bg --exec` (no command); `claude --bg --name spike-exec-probe --exec '…'`;
`claude logs 2f22c35b`; `claude stop 2f22c35b`; `claude rm 2f22c35b`;
`claude project purge --dry-run|-y <probe dir>`; two stream-json control sessions;
`<switcher> --help`; `security find-generic-password -s …` (presence only);
`GET https://api.anthropic.com/api/oauth/usage`.

**Both probe sessions and the probe job were stopped and removed. No configuration file was modified.**
