# SPIKE — making OpenAI Codex CLI a first-class orchestrator citizen

**Date:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0, macOS 26.5.2, arm64).
**Binary under test:** `/Users/sasha-marchuk/.nvm/versions/node/v22.18.0/bin/codex` → `codex-cli 0.152.0`.
**Companion profile:** `codex-cli.md` in this directory. Read it first; this file is the recipe book and
it **corrects the profile in six places** (see *Corrections*).

**Evidence tags:** **VERIFIED** = executed here today, or the exact flag read in the installed binary's
`--help` / generated schema. **CLAIMED** = docs or marketing only. **UNKNOWN** = not established.

**What this pass actually did.** Ran `--help` on every relevant subcommand; generated and parsed the
app-server JSON-RPC schema (98 client methods, 10 server→client requests, 81 notifications); opened
seven live `codex app-server --stdio` sessions; ran **nine real `codex exec` turns** on the cheapest
model (`gpt-5.6-luna`); forced and proved a real compaction; forced and answered a real permission
prompt; crashed a session with `kill -9` and resumed it; started and stopped a self-managed
app-server listener. Weekly quota moved **6% → 6%** (unchanged at this resolution). Nothing in
`~/.codex/config.toml` was modified. Artefacts created are listed in the appendix.

---

## Verdict up front

Codex remains the most orchestrator-ready platform in the field — the app-server gives real answers on
every axis the owner called non-negotiable — but **three blockers found today mean it cannot be run
unattended tonight without adapter work**, and none of the three are in the profile.

| # | Blocker | Status |
|---|---|---|
| **1** | **The owner's default model does not work in the installed CLI.** `~/.codex/config.toml` pins `model = "gpt-6-astra"`; CLI 0.152.0 gets `HTTP 400 — "The 'gpt-6-astra' model requires a newer version of Codex."` `model/list` on this build returns only `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna`, `gpt-5.5`. **Every unmodified `codex exec` on this machine fails on its first turn, exit 1.** | **VERIFIED** twice (a 20:21 exec run and my 20:28 app-server thread) |
| **2** | **`codex app-server daemon start` does not work with the npm install.** It demands `~/.codex/packages/standalone/current/codex`, installed only by `curl -fsSL https://chatgpt.com/codex/install.sh \| sh`. Consequence: **the app-server is not a daemon — it is a child of the orchestrator, and killing that connection aborts in-flight turns** (`turn_aborted` observed on disk). | **VERIFIED** |
| **3** | **`codex exec` blocks forever on an un-closed stdin**, even when a PROMPT argument is given: `Reading additional input from stdin...` and it never returns. An orchestrator that spawns it with a pipe and does not close it hangs the task for the whole night. `< /dev/null` is mandatory. | **VERIFIED** (first launch hung past 120 s; identical launch with `</dev/null` exited 0 in 6.15 s) |

With those three handled — pin a model, close stdin, accept that the orchestrator process owns its
sessions — every one of the eleven recipes below works, and **ten of eleven were executed here today**.

**Tier: tier-1**, conditional on blocker 1 being fixed at launch time (one flag) and blocker 3 being
fixed in the spawn call (one redirect).

---

## The two transports, and when to use each

| | `codex exec` (one OS process per task) | `codex app-server --stdio` (one long-lived child) |
|---|---|---|
| Survives orchestrator death | **Yes** — independent process | **No** — in-flight turn is aborted (VERIFIED) |
| Read context fullness live | via rollout file only | `thread/tokenUsage/updated` (VERIFIED) |
| Force compaction | no | `thread/compact/start` (VERIFIED) |
| Answer a permission prompt | no — `approval_policy` must be `never` | server→client request (VERIFIED) |
| Steer a running turn | no | `turn/steer` (VERIFIED error path) |
| Read quota without a turn | no | `account/rateLimits/read` (VERIFIED) |
| Event names | `thread.started`, `turn.started`, `item.completed`, `turn.completed`, `turn.failed`, `error` (dot) | `thread/started`, `turn/completed`, … (slash) |

**Recommended adapter shape: run the executors as `codex exec` processes, and run *one* short-lived
`app-server --stdio` alongside for the supervisory calls that `exec` cannot do** (quota read,
compaction, steering, approvals). A crashed supervisor then loses supervision, not work. If the
standalone install is added later, switch to the daemon and collapse the two.

---

## 1. Preflight — installed, authenticated, which account

```bash
CODEX=/Users/sasha-marchuk/.nvm/versions/node/v22.18.0/bin/codex   # pin an absolute path, never `codex`

"$CODEX" --version                       # codex-cli 0.152.0
"$CODEX" login status; echo $?           # "Logged in using ChatGPT" / 0
```

**VERIFIED.** Failure looks like `Not logged in`, **exit 1** (reproduced with an isolated
`CODEX_HOME`). Note: an unauthenticated run does *not* hang — it retries the websocket 5 times
(`ERROR: Reconnecting... 5/5`) and exits **1** with `401 Unauthorized`. Still, gate on
`login status` so a night's queue does not burn 5 retries per task.

Identity, plan and the effective config, in one app-server session (no tokens spent, **VERIFIED live**):

```json
→ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"orchestrator","title":"orchestrator","version":"1.0.0"}}}
← {"id":1,"result":{"userAgent":"orchestrator/0.152.0 (Mac OS 26.5.2; arm64) …","codexHome":"/Users/sasha-marchuk/.codex","platformFamily":"unix","platformOs":"macos"}}
→ {"jsonrpc":"2.0","method":"initialized"}
→ {"jsonrpc":"2.0","id":2,"method":"account/read","params":{"refreshToken":false}}
← {"id":2,"result":{"account":{"type":"chatgpt","email":"<email>","planType":"prolite"},"requiresOpenaiAuth":true}}
→ {"jsonrpc":"2.0","id":3,"method":"config/read","params":{}}
← {"id":3,"result":{"config":{"model":"gpt-6-astra","sandbox_mode":"danger-full-access","approval_policy":null,
                              "model_auto_compact_token_limit":null,"compact_prompt":null, …}}}
```

**`config/read` is the blocker-1 and blocker-3 gate.** The adapter must assert, before dispatching:

```
assert config.model ∈ (model/list).data[].id     # else pin -m explicitly
assert launch passes -s explicitly               # never inherit danger-full-access
```

**Model availability gate (VERIFIED):**

```json
→ {"jsonrpc":"2.0","id":4,"method":"model/list","params":{}}
← data[].id = ["gpt-5.6-sol"(isDefault), "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"]
```

**Capability probe for the installed build (VERIFIED, `--strict-config` rejects unknown keys):**

```bash
probe() { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"p","title":"p","version":"0"}}}' \
  | timeout 20 "$CODEX" app-server --stdio --strict-config -c "$1" >/dev/null 2>/tmp/sc.err
  [ -s /tmp/sc.err ] && echo "REJECTED $1" || echo "OK $1"; }
```

Run here today: `definitely_not_a_real_key_xyz=1` → **REJECTED**
(`Error: unknown configuration field … in -c/--config override`); **accepted**:
`model_auto_compact_token_limit`, `model_auto_compact_token_limit_scope`, `compact_prompt`,
`model_context_window`, `approvals_reviewer`, `shell_environment_policy.inherit`,
`notify=["/bin/echo","turn-ended"]`, `suppress_unstable_features_warning`, `mcp_servers={}`,
`hooks={}`, `history.persistence`. **All VERIFIED.**

**Control-plane health probe (VERIFIED):**

```bash
"$CODEX" app-server daemon version
# running:  {"status":"running","managedCodexPath":"…","socketPath":"/Users/sasha-marchuk/.codex/app-server-control/app-server-control.sock","cliVersion":"0.152.0","appServerVersion":"0.152.0"}
# stopped:  Error: failed to connect to …/app-server-control.sock  (exit 1)
```

**Fallback if any preflight fails:** do not dispatch. `codex login status` is cheap, `config/read` is
free. There is no safe degraded mode for a wrong model — it burns a session slot and exits 1.

---

## 2. Start a task headless, with a pinned session id, capturing structured output

**Codex cannot be told a session id before the session exists.** `ThreadStartParams` has no id field
and `codex exec` has no `--session-id` (VERIFIED by absence and by `-a` probing). The orchestrator
therefore uses **start-then-name**.

```bash
cd "$WORKTREE"
printf '%s' '{"type":"object","additionalProperties":false,
  "properties":{"status":{"type":"string","enum":["done","blocked"]},"note":{"type":"string"}},
  "required":["status","note"]}' > "$RUN/schema.json"

"$CODEX" exec \
  --json \
  -m gpt-5.6-luna \                          # BLOCKER 1 — always pin, never inherit
  -s read-only \                             # or workspace-write; never inherit danger-full-access
  -c approval_policy='"never"' \             # NB: `codex exec` has NO -a/--ask-for-approval
  -c suppress_unstable_features_warning=true \
  -c model_auto_compact_token_limit=180000 \ # auto-compaction threshold, per launch
  -c compact_prompt="$(cat handoff-prompt.txt)" \
  -c shell_environment_policy.inherit='"core"' \   # keep secrets out of the rollout
  --ignore-user-config \                     # optional; see cost table below
  --skip-git-repo-check \
  -C "$WORKTREE" \
  --add-dir "$ARTEFACTS" \
  --output-schema "$RUN/schema.json" \
  -o "$RUN/last-message.txt" \
  "$TASK_PROMPT" \
  < /dev/null \                              # BLOCKER 3 — mandatory
  > "$RUN/events.jsonl" 2> "$RUN/stderr.log" &
echo $! > "$RUN/pid"
```

**Capture the id from the first event and name it immediately (VERIFIED):**

```bash
TID=$(timeout 30 sh -c 'while read -r l; do echo "$l" | grep -q thread.started && \
        echo "$l" | python3 -c "import sys,json;print(json.load(sys.stdin)[\"thread_id\"])" && break; done < "'$RUN'/events.jsonl"')
# then, over app-server:
→ {"jsonrpc":"2.0","id":9,"method":"thread/name/set","params":{"threadId":"<TID>","name":"orch-run-0001"}}
← {"id":9,"result":{}}                       # VERIFIED; notification thread/name/updated also fires
```

**What success looks like (VERIFIED, real output from this machine today):**

```json
{"type":"thread.started","thread_id":"01a0b9dd-5801-7cd1-bd22-52edba4ad341"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"{\"status\":\"done\",\"note\":\"ok\"}"}}
{"type":"turn.completed","usage":{"input_tokens":12512,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":19,"reasoning_output_tokens":0}}
```
exit **0**; `last-message.txt` contains exactly `{"status":"done","note":"ok"}` — `--output-schema` was
honoured.

**What failure looks like (VERIFIED):**

```json
{"type":"item.completed","item":{"id":"item_0","type":"error","message":"Model metadata for `gpt-6-astra` not found. …"}}
{"type":"error","message":"{\"type\":\"error\",\"status\":400,…\"The 'gpt-6-astra' model requires a newer version of Codex.\"}"}
{"type":"turn.failed","error":{…}}
```
exit **1**. Bad resume id: `Error: thread/resume: … no rollout found for thread id <x> (code -32600)`.

**Launch cost, measured here (VERIFIED, `/usr/bin/time -p`, trivial prompt):**

| launch | wall | input tokens |
|---|---|---|
| `--ignore-user-config` | **6.15 s** | **12,461** |
| inherited user config (7 MCP servers, skills, plugins) | **7.16 s** | **17,632** |
| inherited config + `-c mcp_servers={}` | 7.46 s | **17,632** — *no saving; the overhead is not MCP* |

So **the owner's global Codex surface costs ~5,200 extra input tokens on every task**, and
`mcp_servers={}` does **not** recover them — only `--ignore-user-config` does. There is a floor of
**~12.5 k input tokens per exec launch** regardless.

**Fallback:** if `--output-schema` is rejected by a future build, drop it and parse
`-o last-message.txt` yourself. If naming fails, the UUID from `thread.started` is already a valid
handle — the name is a convenience, not a requirement.

**Race the adapter must own:** a crash between `thread.started` and `thread/name/set` leaves an
unnamed orphan. `codex doctor` reports **1 duplicate rollout thread id and 1 missing active row**
out of 354 on this machine right now, plus two 2025-era rollouts with *no usable header record*
(the process died before writing `session_meta`). Budget for orphans; reconcile from
`state_5.sqlite` rather than assuming every launch is recoverable.

---

## 3. Start the same task in a visible terminal the owner can type into

**`codex agents` — the intended answer — does not work on this machine.** It browses sessions on
"the shared local app-server daemon", and that daemon requires the standalone install (blocker 2).
Both `codex agents` and `codex resume <id>` also **hard-require a TTY**:

```bash
"$CODEX" agents </dev/null                       # ERROR: stdin is not a terminal   (VERIFIED)
"$CODEX" resume <id> --include-non-interactive </dev/null   # Error: stdin is not a terminal (VERIFIED)
"$CODEX" 'hi' </dev/null                          # Error: stdin is not a terminal   (VERIFIED)
```

**So the visible half is an OS-level launcher, exactly as the current harness does it.** The reliable
recipe is: run the task as an ordinary `codex exec` (recipe 2), and when the owner wants to attach,
open a real terminal on the *same thread id*:

```bash
osascript -e 'tell application "iTerm2"
  tell current window to create tab with default profile
  tell current session of current window to write text "'"$CODEX"' resume '"$TID"' --include-non-interactive --no-alt-screen -m gpt-5.6-luna -s workspace-write"
end tell'
```

`--include-non-interactive` is **required** to see exec-created sessions in the picker (VERIFIED in
`--help`); `--no-alt-screen` keeps scrollback so the owner can read what happened. `tmux` is present
at `/usr/local/bin/tmux` and `script` at `/usr/bin/script` if a headless-but-attachable PTY is
preferred.

**Success:** the TUI opens with the thread's history and `canAcceptDirectInput` is true.
**Failure:** `stdin is not a terminal` means the launcher did not give it a PTY.
**Fallback, and the better one for an unattended queue:** do not open a terminal at all — use
`codex queue` (recipe 8) to talk to the session, and read the transcript (recipe 4). The owner's
"visible terminal" requirement [R1-11] is satisfiable per-platform by config; for Codex the honest
setting is *headless executor + attach on demand*.

**If the standalone install is added** (`curl -fsSL https://chatgpt.com/codex/install.sh | sh`), this
recipe becomes `codex app-server daemon start` once, then `codex agents` in any terminal — one daemon
owning all sessions, orchestrator on JSON-RPC, owner attached to the same daemon. That is
architecturally better than everything the current harness does, and it is **one install away**.

---

## 4. Alive / working / waiting / finished — from outside

### 4a. Over the protocol — exact, four-valued (VERIFIED live)

`thread/status/changed` carries `ThreadStatus`, which is a closed set:

| `status.type` | meaning |
|---|---|
| `notLoaded` | on disk, not held by any app-server |
| `idle` | loaded, no turn running — **finished / ready for input** |
| `active`, `activeFlags: []` | **working** |
| `active`, `activeFlags: ["waitingOnApproval"]` | **blocked on a permission prompt** |
| `active`, `activeFlags: ["waitingOnUserInput"]` | **blocked on a clarifying question** |
| `systemError` | the turn failed hard |

All five transitions were observed live today on thread `01a0b9dd-…`, including
`{"type":"active","activeFlags":["waitingOnApproval"]}` while a real approval was pending. **This is
the single cleanest liveness signal in the whole field** — Codex tells you *why* a session is idle.

Polling equivalent: `thread/read {threadId, includeTurns:false}` returns the same `status`
(**VERIFIED** — note the param is `includeTurns` on `thread/read` and `excludeTurns` on
`thread/resume`; the profile conflated them).

### 4b. Without a daemon — from disk alone (VERIFIED)

```bash
# 1. process alive?
kill -0 "$(cat $RUN/pid)" 2>/dev/null

# 2. thread inventory
sqlite3 ~/.codex/state_5.sqlite \
  "select id,name,source,tokens_used,archived,datetime(updated_at,'unixepoch') from threads where name='orch-run-0001';"

# 3. terminal record in the rollout
F=$(sqlite3 ~/.codex/state_5.sqlite "select rollout_path from threads where name='orch-run-0001';")
tail -1 "$F" | python3 -c "import json,sys;print(json.load(sys.stdin)['payload'].get('type'))"
#   task_complete  → finished (check payload.error for failed-vs-ok)
#   turn_aborted   → interrupted
#   anything else + no live process → CRASHED
```

**Crash signature, VERIFIED by experiment:** I `kill -9`'d an exec run 6 s into its turn. The rollout
kept a valid `session_meta` header and 8 lines, ending at the `item_completed`/`UserMessage` record —
**no `task_complete`, no `token_count`**. That combination (`session_meta` present + no terminal
record + no live pid) is an exact crash detector.

**Note (VERIFIED): `SIGTERM` to `codex exec` leaves the identical signature** — the node shim kills its
native child, no orphans remain, and nothing terminal is written. On disk a clean stop and a crash are
indistinguishable; only the protocol can stop a turn *cleanly* (recipe 11).

**Thread name → id resolution: use SQL, not `searchTerm`.** `thread/list {"searchTerm":"orch-run-0001"}`
returned **0 rows** for a thread whose name is exactly that (VERIFIED); `searchTerm` matches
title/preview, not `name`. `select id from threads where name=? and archived=0` works, and so does
`codex queue --thread <name>`. `thread/list {"cwd":[…]}` also returned 0 rows here — the filter is
`string | string[]` (an object form errors: `data did not match any variant of untagged enum
ThreadListCwdFilter`) but it did not match paths that are present in the DB. **Treat `cwd` and
`searchTerm` filters as unreliable; filter in SQL.**

`thread/list {"sourceKinds":[…]}` **is** reliable, and its enum was extracted by deliberately sending a
bad value (VERIFIED): `cli, vscode, exec, appServer, subAgent, subAgentReview, subAgentCompact,
subAgentThreadSpawn, subAgentOther, unknown`. **Caveat: threads the orchestrator starts over the
app-server are recorded with `source = "vscode"`, not `appServer`** (VERIFIED — my thread/start with
`threadSource:"exec"` landed as `source:"vscode"`). Filter orchestrator sessions by `name` prefix, not
by source kind.

---

## 5. Read context fullness, force a compaction, prove it happened

### Read (VERIFIED, two independent channels)

**Protocol push** — `thread/tokenUsage/updated`:

```json
{"threadId":"01a0b9dd-…","turnId":"01a0b9de-8d09-…",
 "tokenUsage":{"total":{"totalTokens":0,…},"last":{"totalTokens":4862,…},"modelContextWindow":258400}}
```

**Disk** — one `event_msg`/`token_count` record per turn in the rollout JSONL, freshly produced here:

```json
{"type":"event_msg","payload":{"type":"token_count","info":{
  "total_token_usage":{"input_tokens":12512,"cached_input_tokens":0,"output_tokens":19,"total_tokens":12531},
  "last_token_usage":{…},"model_context_window":258400},
  "rate_limits":{"limit_id":"codex","primary":{"used_percent":6.0,"window_minutes":10080,"resets_at":1790415035},
                 "secondary":null,"plan_type":"prolite","rate_limit_reached_type":null}}}
```

```
fullness = info.total_token_usage.total_tokens / info.model_context_window
```

Cheap sweep across every session at once: `select id,name,tokens_used from threads` — `tokens_used`
tracked the live value exactly through this experiment (**VERIFIED**).

**`codex exec --json` carries NO context and NO quota data** — `turn.completed` has only `usage`
(input/cached/cache-write/output/reasoning), with no window size and no rate limits (VERIFIED against
five real runs). **The profile's claim of `turn.cost_microusd` was not observed in 0.152.0.** A
watcher that reads only the exec event stream is blind on axes D and E; it must tail the rollout.

### Force it, and prove it — EXECUTED END TO END TODAY

```json
→ {"jsonrpc":"2.0","id":2,"method":"thread/resume","params":{"threadId":"01a0b9dd-…","model":"gpt-5.6-luna","sandbox":"read-only","approvalPolicy":"never","excludeTurns":true}}
← status {"type":"idle"}
→ {"jsonrpc":"2.0","id":3,"method":"thread/compact/start","params":{"threadId":"01a0b9dd-…"}}
← {"id":3,"result":{}}                       ← an async ack, NOT proof
```

Proof arrived 7 s later, on three independent channels:

```
[  0.9s] thread/status/changed  {"status":{"type":"active","activeFlags":[]}}
[  7.0s] item/completed         {"item":{"type":"contextCompaction","id":"01a0b9de-90c0-…"}}
[  7.0s] thread/tokenUsage/updated {"total":{"totalTokens":0},"last":{"totalTokens":4862},"modelContextWindow":258400}
[  7.0s] turn/completed         {"status":"completed","durationMs":7013}
```

and on disk, in the same rollout:

```json
{"ordinal":35,"type":"event_msg","payload":{"type":"item_completed","item":{"type":"ContextCompaction","id":"01a0b9de-90c0-…"},"started_at_ms":1789824766144,"completed_at_ms":1789824772206}}
```

with the `token_count` timeline moving **12531 → 12593 → 25204 → 0** and
`state_5.sqlite.threads.tokens_used` going to `0`.

**The three-line proof an adapter should assert:**
1. a `ContextCompaction` item completed for this thread (`item/completed` live, or `item.type ==
   "ContextCompaction"` in the rollout), **and**
2. `total_token_usage.total_tokens` strictly decreased, **and**
3. `turn/completed.status == "completed"` (not `interrupted`).

**Two profile claims are wrong and must not be used as proof.** (a) The
`thread/compacted` notification **did not fire** — the schema itself says *"Deprecated: Use
`ContextCompaction` item type instead."* (b) `thread/list {"sourceKinds":["subAgentCompact"]}` returned
**empty** immediately after a confirmed compaction — compaction did **not** spawn a child thread here.

**Failure mode discovered the hard way:** my first compaction attempt aborted because the script closed
the app-server's stdin while the turn ran. The rollout recorded `event_msg`/`turn_aborted` and
`tokens_used` went *up*, not down. **Hold the connection until `turn/completed`.**

**Handoff instead of compaction** (the owner's "launch a completely new orchestrator" option [R1-08]):
`codex exec` the same task in a fresh thread with `--output-schema`, seeded from the previous thread's
`-o last-message.txt`; or `thread/fork` / `codex fork` to branch. Configure the compaction prompt
itself with `-c compact_prompt="…"` (**VERIFIED accepted**) so the handoff text is the owner's, not
OpenAI's — this is the direct answer to *"чи відправляється якийсь промпт одразу після компакту"*.

**Soft vs hard (R1-08) maps cleanly:** *soft* = set `-c model_auto_compact_token_limit=<N>` at launch
and let Codex compact at a step boundary; *hard* = watch `thread/tokenUsage/updated`, call
`turn/interrupt`, then `thread/compact/start`, then re-issue the work with `turn/start`. Both
mechanisms are native. The owner's *"повинен бути механізм, який гарантовано робить цю дію"* is
satisfiable here, and on no other platform in this field is it this clean.

---

## 6. Read remaining quota and the reset time; detect a limit hit in band

**Pull, before every dispatch — no thread, no tokens (VERIFIED live, twice today):**

```json
→ {"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read"}
← {"rateLimits":{"limitId":"codex","limitName":null,
     "primary":{"usedPercent":6,"windowDurationMins":10080,"resetsAt":1790415035},
     "secondary":null,
     "credits":{"hasCredits":false,"unlimited":false,"balance":"0"},
     "individualLimit":null,"spendControlReached":false,
     "planType":"prolite","rateLimitReachedType":null},
   "rateLimitResetCredits":{"availableCount":2,"credits":[
     {"id":"RateLimitResetCredit_<id>…","resetType":"codexRateLimits","status":"available",
      "grantedAt":1788488180,"expiresAt":1791080180,"title":"Full reset"},
     {"id":"RateLimitResetCredit_<id>…","status":"available","expiresAt":1791174114}]},
   "accountId":"<account-id>"}
```

**Push, while running:** `account/rateLimits/updated` carries the same `RateLimitSnapshot`.
**On disk, zero dependencies:** the `rate_limits` block inside every `token_count` line of the rollout.

**Do not hardcode the window layout.** `RateLimitWindow = {usedPercent (required), resetsAt (int64,
nullable), windowDurationMins (int64, nullable)}` and there are at most two. On `prolite` **today,
`primary` is the 7-day window (10080 min) and `secondary` is `null`** — an orchestrator that assumes
"primary = 5 h" will mis-schedule this account. Across the 380 historic rollouts here both layouts
appear (10080/10079 weekly, 299/300 five-hourly), because the plan changed.

**Casing differs by channel:** `usedPercent` / `windowDurationMins` / `resetsAt` on the wire;
`used_percent` / `window_minutes` / `resets_at` on disk. Two parsers, one model.

**Limit-hit in band:** `rateLimitReachedType ∈ {rate_limit_reached,
workspace_owner_credits_depleted, workspace_member_credits_depleted,
workspace_owner_usage_limit_reached, workspace_member_usage_limit_reached}`, plus
`spendControlReached: bool` and `credits.hasCredits` (**VERIFIED in schema; never non-null on this
account, so the code path is UNTESTED here — UNKNOWN whether `codex exec` exits non-zero on it**).
What *is* verified is that a turn-level failure surfaces as `{"type":"error"}` +
`{"type":"turn.failed"}` on the exec stream with **exit 1**, and as `ErrorNotification
{error,threadId,turnId,willRetry}` on the protocol. **`willRetry` is the flag that distinguishes a
transient provider outage from a dead session** — watch it before declaring a session lost.

**The escape hatch nothing else in this field has:**

```json
→ {"jsonrpc":"2.0","id":7,"method":"account/rateLimitResetCredit/consume",
   "params":{"idempotencyKey":"orch-<runid>-<n>","creditId":"RateLimitResetCredit_<id>…"}}
← {"outcome":"reset" | "nothingToReset" | "noCredit" | "alreadyRedeemed"}
```

**This account holds 2 unused "Full reset" credits right now**, expiring 1791080180 and 1791174114.
An overnight run that hits the weekly wall can redeem one and continue, idempotently.
**Not executed** — it would consume a real credit. **UNKNOWN** whether it works headlessly without the
ChatGPT app.

**Owner's ladder [R1-06] in Codex terms:** hard stop = `turn/interrupt` + park the ticket;
soft stop = stop dispatching, let running turns finish; intermediate = `thread/compact/start`, record
state, resume after `resetsAt`. `thread/goal/set {tokenBudget}` gives a *per-session* budget whose
status auto-flips to `usageLimited` / `budgetLimited` — I watched it flip to `blocked` by itself when
a turn failed (VERIFIED), so it is a real supervisory signal, not decoration.

---

## 7. Switch a new session to a different account, and verify before work starts

**Mechanism: `CODEX_HOME`. One env var relocates the entire account and state** — `auth.json`,
`config.toml`, `sessions/`, all four SQLite DBs, skills, plugins.

```bash
export CODEX_HOME=~/.codex-roles/reviewer      # per role, per account
"$CODEX" login status                          # one-time interactive login
# non-interactive alternatives (VERIFIED in `codex login --help`, secret read from stdin):
printenv OPENAI_API_KEY    | "$CODEX" login --with-api-key
printenv CODEX_ACCESS_TOKEN| "$CODEX" login --with-access-token
"$CODEX" login --device-auth
```

**Isolation VERIFIED by execution today:**

```
$ codex login status                                   → Logged in using ChatGPT     (exit 0)
$ CODEX_HOME=$(mktemp -d) codex login status           → Not logged in               (exit 1)
$ CODEX_HOME=$(mktemp -d) codex exec … 'hi'            → 401 Unauthorized ×5, exit 1
```

The fresh `CODEX_HOME` was populated from scratch (`goals_1.sqlite`, `logs_2.sqlite`,
`installation_id`, …) — genuinely separate state, not a view.

**Verify the switch before dispatching (VERIFIED live):**

```json
→ {"jsonrpc":"2.0","id":1,"method":"initialize",…}
← result.codexHome == "/Users/sasha-marchuk/.codex-roles/reviewer"    ← assert this
→ {"jsonrpc":"2.0","id":2,"method":"account/read","params":{"refreshToken":false}}
← {"account":{"type":"chatgpt","email":"<expected>","planType":"<expected>"}}   ← and this
```

Two independent assertions, both free. This is exactly the owner's *"verified to work before a run
starts"* [R1-07].

**No macOS Keychain is involved** — credentials live in `~/.codex/auth.json` (mode `-rw-------`,
`auth_mode`/`tokens.{id,access,refresh}_token`/`tokens.account_id`/`last_refresh`). **Codex cannot hit
the "Always Allow" GUI-dialog hang that the field scan records against Claude Code.** For an unattended
queue this is a decisive practical advantage.

**Can a running session's account change? No.** There is no per-thread account parameter in
`ThreadStartParams` or `ThreadResumeParams` (VERIFIED by absence); `account/login/start` and
`account/logout` are process-wide per `CODEX_HOME`. **Fallback:** one app-server (or one exec
environment) per account, and route new threads to the right one. Cost: N processes, N MCP boots.
For `codex exec` this costs nothing extra — the env var is per-spawn.

**Soft/hard role reassignment [R1-07]:** soft = next `exec` spawn gets the new `CODEX_HOME`;
hard = `turn/interrupt` the running turn, then respawn under the new home with `codex exec resume`
(the thread lives in the *old* home's `sessions/`, so a hard switch across accounts means a **new
thread seeded from the old one's `-o last-message.txt`**, not a resume). That asymmetry is the real
cost of per-account isolation and the adapter must state it out loud.

---

## 8. Deliver an instruction into a running session and confirm it arrived

**`codex queue` — VERIFIED end to end today, including consumption.** This is the strongest single
result of the spike.

```bash
"$CODEX" queue --thread orch-run-0001 \
  --message "ORCHESTRATOR NUDGE: append the word NUDGED to your reply."
# → Queued message 01a0b9dd-9e3c-77a1-93f5-2787f7f1a05a for thread 01a0b9dd-5801-7cd1-bd22-52edba4ad341.
```

* accepts **a UUID or an exact thread name** (name resolution VERIFIED);
* works with **no app-server running and no client** — it writes straight to
  `~/.codex/queue_1.sqlite` `queued_items(id, thread_id, payload_json, queue_order, created_at_ms)`;
* returns a **message id as the receipt**;
* failure is explicit: `Error: No active session found matching 'does-not-exist-zzz'.`, **exit 1**.

**Proof of *delivery*, not just queuing (VERIFIED):** on the next `codex exec resume`, the agent
produced **two** messages —

```json
{"type":"item.completed","item":{"type":"agent_message","text":"{\"status\":\"done\",\"note\":\"ok\"} NUDGED"}}
{"type":"item.completed","item":{"type":"agent_message","text":"READY"}}
```

— the first answering the queued nudge, the second the resume prompt, **and the queue row was gone**:

```sql
select count(*) from queued_items where id='01a0b9dd-9e3c-77a1-93f5-2787f7f1a05a';  -- 0
```

**That row disappearing is the delivery receipt.** Poll it; it is a file on disk, it costs nothing,
and it works across process restarts. The `thread/queue/changed` notification is the live equivalent.

**This is precisely the capability the harness field notes record as missing — "a nudge that cannot
submit stranded text" — and it needs no protocol client at all.**

**Steer a turn already in flight (protocol):**

```json
→ {"jsonrpc":"2.0","id":5,"method":"turn/steer",
   "params":{"threadId":"<tid>","expectedTurnId":"<current turn id>","input":[{"type":"text","text":"…"}]}}
← {"turnId":"<turn id>"}                     ← acknowledgement
```

`expectedTurnId` is an **optimistic-concurrency guard**, and the profile's open question about its
error behaviour is now answered (VERIFIED):

```json
← {"code":-32600,"message":"expected active turn id `00000000-…` but found `01a0b9dd-6fc9-7540-82c8-2a0fe4f99d24`"}
```

Clean JSON-RPC error, **and the message leaks the real active turn id** — usable as a last-resort way
to discover it. `turn/interrupt` errors identically.

**`thread/inject_items` is not a safe nudge channel.** It returned `{}` on a live thread here and the
injected item **never appeared** in `thread/items/list`; the schema leaves `items` unconstrained
(`[True]`). **UNKNOWN shape, do not use.** Use `codex queue` or `turn/steer`.

**Also verified, and worth a warning: `thread/goal/set` with an `objective` starts a turn.** Setting
`{objective:"probe",tokenBudget:1000}` on an idle thread immediately drove a model turn (and made
`"probe"` the thread's preview). Use `thread/goal/set` for budgets, not for notes.

---

## 9. Answer a permission prompt or a clarifying question without a human

**EXECUTED END TO END TODAY.** The single most valuable verification in this spike, because it is the
axis where screen-scraping harnesses fail.

Setup: `thread/resume` with `approvalPolicy:"on-request"`, `sandbox:"read-only"`, then a turn that
requires a write. The server sent a **JSON-RPC request** (id-bearing, not a notification), the
orchestrator answered it by id, and the agent carried on:

```
[ 8.4s] thread/status/changed  {"status":{"type":"active","activeFlags":["waitingOnApproval"]}}
[ 8.4s] item/started           {"item":{"type":"commandExecution","command":"/bin/zsh -lc \"printf 'HELLO\\n' > PROOF.txt\"","status":"inProgress"}}
```
```json
← SERVER REQUEST  item/commandExecution/requestApproval
  {"kind":"command","threadId":"01a0b9dd-…","turnId":"01a0b9de-ea72-…","itemId":"exec-8bf0191b-…",
   "startedAtMs":1789824797418,"environmentId":"local",
   "reason":"May I create PROOF.txt in the current working directory as requested?",
   "command":"/bin/zsh -lc \"printf 'HELLO\\n' > PROOF.txt\"","cwd":"…/run1",
   "commandActions":[{"type":"unknown","command":"printf 'HELLO\\n' > PROOF.txt"}],
   "proposedExecpolicyAmendment":["/bin/zsh","-lc","printf 'HELLO\\n' > PROOF.txt"], …}

→ {"jsonrpc":"2.0","id":0,"result":{"decision":"decline"}}
```
```
[ 8.7s] serverRequest/resolved {"threadId":"01a0b9dd-…","requestId":0}
[ 8.7s] item/completed         {"item":{"type":"commandExecution","status":"declined", …}}
[11.5s] item/completed         {"item":{"type":"agentMessage","phase":"final_answer",
                                        "text":"Unable to create `PROOF.txt` because shell write permission was rejected."}}
[11.5s] turn/completed         {"status":"completed"}
```

`PROOF.txt` was **not** created (checked). Decision honoured, turn completed normally, no hang.

**The ten server→client requests and their answers (VERIFIED in schema):**

| request | client replies |
|---|---|
| `item/commandExecution/requestApproval` | `{"decision": "accept"｜"acceptForSession"｜{"acceptWithExecpolicyAmendment":{"execpolicy_amendment":[…]}}｜{"applyNetworkPolicyAmendment":{"network_policy_amendment":{"host","action":"allow"｜"deny"}}}｜"decline"｜…}` |
| `item/fileChange/requestApproval` | same decision family |
| `item/permissions/requestApproval` | `{"permissions":{…},"scope":"turn"｜"session","strictAutoReview":bool?}` |
| `item/tool/requestUserInput` | `{"answers":{"<questionId>":{"answers":["…"]}}}` |
| `execCommandApproval` / `applyPatchApproval` (legacy) | `{"decision":"approved"｜"approved_for_session"｜{"approved_execpolicy_amendment":{…}}｜"denied"｜…}` |
| `mcpServer/elicitation/request` | elicitation response |
| `item/tool/call` (`DynamicToolCallParams`) | a tool result — **the orchestrator can host tools for the agent** |
| `account/chatgptAuthTokens/refresh` | refreshed tokens |
| `attestation/generate` | attestation |

**The clarifying-question path is structured, not prose.**
`ToolRequestUserInputParams = {threadId, turnId, itemId, isBlocking, questions[]}` where each question
is `{id, header, question, options?[], isOther, isSecret}` — a stable id and an option list, so the
orchestrator answers by id and never pattern-matches a screen. Reply
`{"answers":{"<id>":{"answers":["<chosen option>"]}}}`. **This is the exact mechanism the owner
described** — *"якщо він раптом використовує ask user question, то оркестратор може відповідати на ці
питання"* [R1-11] — and it is a designed feature, not a workaround. (Schema **VERIFIED**; no live
question was available to answer today — **the live path for `item/tool/requestUserInput` remains
UNTESTED here**.)

**Skew note:** the live `item/commandExecution/requestApproval` payload contained a field beginning
`availableDe…` (almost certainly `availableDecisions`) that is **absent from the generated schema**
(`approvalId, command, commandActions, cwd, environmentId, itemId, kind, networkApprovalContext,
proposedExecpolicyAmendment, proposedNetworkPolicyAmendments, reason, startedAtMs, threadId, turnId`).
Parse the wire defensively.

**Fallback when running as plain `codex exec` (no protocol):** there is no approval channel, so set
`-c approval_policy='"never"'` and a real sandbox. Execution failures are then *returned to the model*
rather than blocking ("Execution failures are immediately returned to the model", VERIFIED help text).
**Do not use `--dangerously-bypass-approvals-and-sandbox` (`--yolo`) for this** — it removes the
sandbox too. A third option is `--approve-for-me` / `-c approvals_reviewer='"auto_review"'`
(**VERIFIED accepted**), which routes approvals to a prompted subagent that applies a risk framework;
the schema also exposes the legacy `guardian_subagent`, and `guardian_approval` is `stable/true` in
`codex features list`. That is the closest thing to the owner's *"tone of voice своїх рішень"* [R1-14]
that ships in the box.

---

## 10. Resume after a crash, and after a reboot

**After a crash — VERIFIED by experiment.** I launched an exec run, let it get 6 s into a turn, and
`kill -9`'d the process tree.

```bash
"$CODEX" exec resume 01a0b9e1-615f-7593-bc06-829a0ba98e6a --json \
  -m gpt-5.6-luna \
  -c approval_policy='"never"' -c sandbox_mode='"read-only"' \
  --ignore-user-config --skip-git-repo-check \
  -o "$RUN/last.txt" "Continue exactly where you left off." < /dev/null
```

```json
{"type":"thread.started","thread_id":"01a0b9e1-615f-7593-bc06-829a0ba98e6a"}   ← same id
{"type":"turn.completed","usage":{"input_tokens":12499,"cached_input_tokens":12032,…}}
```
exit **0**. Same thread id, context intact (12,032 cached input tokens = the prior prefix replayed).
**What was lost is exactly the in-flight turn's output** — the agent reported having written 0 words.
The user message survived; the assistant's partial work did not.

**⚠ `codex exec resume` is a much thinner flag surface than `codex exec` (VERIFIED):** it has **no
`-s/--sandbox`, no `-C/--cd`, no `--add-dir`, no `-p/--profile`, no `--approve-for-me`.** Sandbox and
approvals must be re-supplied as `-c sandbox_mode='"read-only"'` / `-c approval_policy='"never"'`, and
the working directory comes from the thread. An adapter that passes `-s` on resume gets
`error: unexpected argument`.

**Protocol equivalent (VERIFIED live):** `thread/resume {threadId, model?, sandbox?, approvalPolicy?,
cwd?, excludeTurns:true}` returns the thread with `status:{"type":"idle"}` and
`canAcceptDirectInput:true`. Pass `excludeTurns:true` — the server pushes a `deprecationNotice`
otherwise: *"Full-history hydration is deprecated for paginated threads; use `excludeTurns: true`,
then page with `thread/turns/list` and `thread/items/list`."*

**After a reboot.** Nothing about resume depends on a running process: the rollout JSONL is
append-only and flushed per event, `state_5.sqlite` holds `rollout_path`, and thread **names** persist
in `threads.name`. Recovery is:

```sql
select id, name, rollout_path, tokens_used
from threads
where name like 'orch-run-%' and archived = 0
order by updated_at desc;
```

then, per row, apply the 4b liveness test and `codex exec resume <id>` anything that has no terminal
record. **VERIFIED**: a thread from 2026-09-04 resumed cleanly today.

**Orphans are real and must be budgeted for.** `codex doctor` on this machine right now reports
**354 rollout DB rows, 1 missing active row, 1 duplicate rollout thread id**, and sample scan errors
of the form *"rollout at …jsonl has no usable header record"* — sessions whose process died before
`session_meta` was written. Those are **unresumable by id**; the adapter must mark them lost and
re-queue the ticket rather than retry forever.

**Reboot resilience of the *supervisor* is the weak point, not the sessions.** With no daemon
available (blocker 2), the app-server dies with the orchestrator and takes its in-flight turns with
it. `codex exec` children do not — they are independent processes. A `launchd` LaunchAgent around the
orchestrator (or `codex app-server daemon bootstrap`, once the standalone install exists) closes this;
`bootstrap` was **not exercised** — it installs persistent machine state and was out of scope.

---

## 11. Stop cleanly, leaving nothing running

**Clean, per session (VERIFIED live):**

```json
→ {"jsonrpc":"2.0","id":4,"method":"turn/interrupt","params":{"threadId":"<tid>","turnId":"<turn id>"}}
← {"id":4,"result":{}}
← turn/completed {"turn":{"id":"01a0b9e1-ccfd-…","status":"interrupted","durationMs":5070}}
← thread/status/changed {"status":{"type":"idle"}}
```

`status:"interrupted"` is the receipt, and the thread returns to `idle` — resumable, not broken.
Stale `turnId` errors cleanly with `-32600` (recipe 8), so a stop cannot land on the wrong turn.

**Blunt, per process (VERIFIED):**

```bash
kill -TERM "$(cat $RUN/pid)"     # the node shim; its native child dies with it, no orphans remain
```
Confirmed: `pgrep -fl "codex exec"` empty afterwards. **But it writes no terminal record** — on disk
it is indistinguishable from a crash. Prefer `turn/interrupt`, then let the process exit.

**Whole-fleet teardown, and the owner's "не залишати хвостів" [Д3]:**

```bash
# 1. interrupt every active turn (protocol), per thread
# 2. stop the control plane
pkill -f "app-server --listen"      # or: "$CODEX" app-server daemon stop
"$CODEX" app-server daemon version  # expect: Error: failed to connect to …app-server-control.sock  (exit 1)
# 3. stop executors
kill -TERM $(cat $RUN/*/pid)
pgrep -fl codex                     # expect: empty
# 4. tidy the inventory
"$CODEX" archive <id|name>          # reversible:  Archived session <id>.   (VERIFIED, exit 0)
"$CODEX" delete  <id|name>          # permanent — do not use unattended
```

**VERIFIED:** killing the listener removed `~/.codex/app-server-control/app-server-control.sock`
cleanly, and `daemon version` then failed with exit 1 — a reliable "nothing running" assertion.
`codex archive` was executed on the probe thread and returned `Archived session 01a0b9da-….`

**The self-managed listener trick, which is the workaround for blocker 2 (VERIFIED):**

```bash
nohup "$CODEX" app-server --listen "unix://" -c suppress_unstable_features_warning=true \
  > "$RUN/app-server.log" 2>&1 &
# creates ~/.codex/app-server-control/app-server-control.sock without the standalone install
"$CODEX" app-server daemon version    # {"status":"running","cliVersion":"0.152.0","appServerVersion":"0.152.0"}
```

Caveats, both **VERIFIED**: `unix://<path>` forms fail here (`socket directory path exists and is not
a directory: /tmp`, and `path must be shorter than SUN_LEN`) — only bare `unix://` worked; and
**`codex app-server proxy` did not bridge JSON-RPC to it** (exit 0, no output, then broken pipe), nor
did a raw unix-socket client (`BrokenPipeError`). So the listener is reachable for *health checks*
but **not, on 0.152.0, as a JSON-RPC transport for a second client** — which means it does **not**
rescue in-flight turns from an orchestrator restart. `--stdio` remains the only working control
transport here. **UNKNOWN** whether `--ws-*` listeners fare better; not exercised.

---

## The adapter interface this platform needs

| # | Capability | Codex | Mechanism |
|---|---|---|---|
| 1 | preflight / auth / account | **native** | `codex login status` (exit code) · `initialize.codexHome` · `account/read` · `config/read` · `model/list` |
| 2 | headless launch, structured output | **native** | `codex exec --json --output-schema -o` — **plus mandatory `-m`, `-s`, `-c approval_policy`, `< /dev/null`** |
| 2b | **pin a session id before launch** | **impossible** | no `--session-id`, no id in `ThreadStartParams`. **Emulate:** capture `thread.started.thread_id`, then `thread/name/set`; close the crash window with a `SessionStart` hook |
| 3 | visible attachable terminal | **emulated** | `codex resume <id> --include-non-interactive --no-alt-screen` in an iTerm2/tmux window. Native (`codex agents` + daemon) blocked by the missing standalone install |
| 4 | liveness: alive/working/waiting/finished | **native** | `ThreadStatus` = `notLoaded｜idle｜active[waitingOnApproval｜waitingOnUserInput]｜systemError`. Disk fallback: pid + `state_5.sqlite` + terminal rollout record |
| 5 | read context fullness | **native** | `thread/tokenUsage/updated`, or `token_count.info.{total_token_usage.total_tokens, model_context_window}` in the rollout, or `threads.tokens_used` |
| 5b | force compaction with proof | **native** | `thread/compact/start` → `ContextCompaction` item + total-tokens decrease. Configure with `model_auto_compact_token_limit` / `compact_prompt` |
| 6 | read quota + reset time | **native** | `account/rateLimits/read` (pull), `account/rateLimits/updated` (push), `rate_limits` on disk. Plus `account/rateLimitResetCredit/consume` |
| 6b | limit-hit in band | **native (untested)** | `rateLimitReachedType`, `spendControlReached`, `ErrorNotification.willRetry`, exec exit 1 |
| 7 | multi-account, verified switch | **native** | `CODEX_HOME` per role; assert `initialize.codexHome` + `account/read.email`. **No Keychain, no GUI dialog** |
| 7b | switch a *running* session's account | **impossible** | process-wide per `CODEX_HOME`. **Emulate:** interrupt, new thread in the other home seeded from `-o last-message.txt` |
| 8 | deliver an instruction, confirm arrival | **native** | `codex queue --thread <id｜name>` (durable, daemonless, receipt = message id, **delivery proof = row deleted**) · `turn/steer` with `expectedTurnId` |
| 9 | answer approvals & questions programmatically | **native** | ten server→client JSON-RPC requests; `serverRequest/resolved` confirms. Fallback for exec: `approval_policy=never` + sandbox, or `approvals_reviewer=auto_review` |
| 10 | resume after crash / reboot | **native** | `codex exec resume <id｜name>` / `thread/resume`. **Caveat:** thin flag surface on resume; ~1% of historic sessions are unresumable |
| 11 | clean stop | **native** | `turn/interrupt` → `status:"interrupted"`; `codex archive`; SIGTERM leaves no orphans but no terminal record |
| — | **supervisor survives its own death** | **impossible today** | `--stdio` turns abort with the connection; `daemon start` needs the standalone install. **Emulate:** run executors as independent `codex exec` processes |
| — | extensibility (MCP, skills, hooks, subagents) | **native** | `codex mcp`, `~/.codex/skills/`, `hooks/list` (hooks are `stable/true`), `thread_spawn_edges` — a GSD-style subagent engine maps on directly |

### Support tier: **TIER-1**, with two mandatory launch fixes and one structural caveat

Every core axis — launch, identity, transcript, context, quota, accounts, intervention, guardrails,
resume, stop — is answered natively, and **ten of the eleven recipes above were executed on this
machine today**. Nothing else in this field comes close on axes D (context), E (quota) and G
(intervention).

It is **not** tier-1 out of the box on this machine, for reasons that are all fixable in the adapter:

1. **Pin `-m` on every launch** (and `-s`, and `-c approval_policy`). Inheriting the owner's config
   produces a 100%-failing run.
2. **Redirect stdin from `/dev/null` on every spawn.** Otherwise the task hangs all night.
3. **Accept that the supervisor is not durable** until the standalone install is added. Run executors
   as `codex exec` processes so the work outlives the supervisor; use a short-lived
   `app-server --stdio` only for supervisory calls.

With those three, running the owner's queue on Codex overnight is plausible **today**, and more
plausible than on Claude Code — no Keychain dialog can block it, quota is readable before every
dispatch, compaction is forceable with proof, and a hit limit can be reset from two banked credits.

---

## Corrections to `codex-cli.md`

1. **`codex exec` has no `-a/--ask-for-approval`.** `codex exec -a never` →
   `error: unexpected argument '-a' found`. It exists on `codex`, `codex resume`, `codex review` — not
   on `exec`. Use `-c approval_policy='"never"'`. **VERIFIED.**
2. **`thread/compacted` does not fire.** The schema marks it *"Deprecated: Use `ContextCompaction`
   item type instead"*, and a confirmed compaction today produced no such notification. Watch
   `item/completed` with `item.type == "contextCompaction"`. **VERIFIED.**
3. **Compaction does not spawn a `subAgentCompact` thread.** `thread/list {"sourceKinds":
   ["subAgentCompact"]}` was empty immediately after a confirmed compaction. **VERIFIED.**
4. **`turn.cost_microusd` was not observed.** `turn.completed` in 0.152.0 carries only `usage`
   (`input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`,
   `reasoning_output_tokens`) — no cost, no context window, no rate limits. The event vocabulary also
   includes **`turn.failed`** and `item.completed` with `item.type == "error"`. **VERIFIED over five
   real runs.**
5. **Orchestrator threads are not filterable by `sourceKinds:["appServer"]`.** A `thread/start` from a
   custom client with `threadSource:"exec"` was recorded as `source:"vscode"`. Filter by name prefix.
   **VERIFIED.**
6. **`codex app-server daemon start` does not work with the npm install** — it requires
   `~/.codex/packages/standalone/current/codex`. The profile treats the daemon as available; it is
   not, here. **VERIFIED.**

Minor: `thread/read` takes `includeTurns`, `thread/resume` takes `excludeTurns` (opposite polarity);
`thread/list`'s `searchTerm` and `cwd` filters did not match rows that exist; `thread/inject_items`
accepted a call and produced nothing observable.

---

## Open questions after this pass

1. Does `account/rateLimitResetCredit/consume` work headlessly, without a ChatGPT-app confirmation?
   (2 credits banked, not redeemed — **UNKNOWN**)
2. What does `codex exec` do when `rateLimitReachedType` actually fires — exit code, retry, stall?
   (never observed on this account — **UNKNOWN**)
3. Does `codex app-server --listen ws://…` support a second client where `unix://` + `proxy` did not?
   That is the difference between a durable supervisor and a fragile one. (**UNKNOWN**)
4. Live `item/tool/requestUserInput`: schema verified, never triggered. Which agent behaviours raise
   it? (**UNKNOWN**)
5. Exact accepted item shapes for `thread/inject_items`. (**UNKNOWN**)
6. Does the standalone install (`chatgpt.com/codex/install.sh`) coexist with the npm install, and does
   it bring `gpt-6-astra` support plus a working daemon? If yes, blockers 1 and 2 both vanish and this
   becomes an unqualified tier-1. (**UNKNOWN — the highest-value next experiment**)
7. What protocol does `~/.codex/ipc/ipc.sock` speak? Still live, still not the control socket.
   (**UNKNOWN**)

---

## Appendix — what this spike created on the owner's machine

Threads (all in scratchpad working directories, all on `gpt-5.6-luna`):

| thread id | name | what it was |
|---|---|---|
| `01a0b9da-6c5d-71f2-90ea-08f1b43efce6` | `orch-spike-probe-001` | empty probe thread; failed on `gpt-6-astra`; **archived** |
| `01a0b9dd-5801-7cd1-bd22-52edba4ad341` | `orch-run-0001` | the main workhorse: structured output, queue delivery, compaction, approval, interrupt |
| `01a0b9e1-615f-7593-bc06-829a0ba98e6a` | — | `kill -9` crash test, then resumed |
| `01a0b9e1-fb4a-7333-8560-89d5601f3773` | — | SIGTERM test |
| `01a0b9e2-d814-7bf3-8987-d4ed8e4a4f43` | — | deliberate `gpt-6-astra` failure, exit 1 |
| plus 3 trivial timing runs | — | launch-overhead measurements |

Cleanup performed: the one `queue_1.sqlite` row this spike added was deleted (the only remaining row is
the owner's from 2026-09-04); the self-managed app-server listener was stopped and its socket removed;
the temporary `CODEX_HOME` directories were removed. **`~/.codex/config.toml` was not modified.**
Rollouts for the threads above remain under `~/.codex/sessions/2026/09/19/` as evidence.

Probe scripts and raw captures:
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/codexspike/`
(`rpc.py` — a ~50-line JSON-RPC client that is a working first draft of the adapter's transport;
`compact.py`, `approve.py`, `interrupt.py`, `exec1.jsonl`, `resume.jsonl`, `crash.jsonl`, `bad.jsonl`).
Generated protocol schema: `…/scratchpad/codex-schema/` (`ClientRequest.json` — 98 methods,
`ServerRequest.json` — 10, `ServerNotification.json` — 81).
