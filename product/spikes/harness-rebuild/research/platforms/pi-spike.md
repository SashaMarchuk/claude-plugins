# SPIKE — making **pi** a first-class citizen of the orchestrator

**Platform:** Pi coding agent — npm `@earendil-works/pi-coding-agent`, binary `pi`, repo `earendil-works/pi`, MIT.
**Version exercised:** **0.85.1** (published 2026-09-05). **Date:** 2026-09-19. **Machine:** owner's Mac, darwin 25.5.0.
**Companion:** read `research/platforms/pi.md` first — this file does not repeat its capability survey, it supersedes four of its conclusions (marked ⚠ **CORRECTION** below) and turns the rest into runnable recipes.

**Evidence tags.** **VERIFIED** = executed on this machine at 0.85.1, or read in the shipped TypeScript source / shipped docs. **CLAIMED** = vendor doc only. **UNKNOWN** = could not establish without spending the owner's quota.

**What was run to produce this file.** pi 0.85.1 installed in a sandbox (`$SBX` below), every run with `PI_CODING_AGENT_DIR` and `PI_CODING_AGENT_SESSION_DIR` pointed at scratch dirs, a protocol-compliant RPC client driving it over held-open stdin, and a tmux server on a private socket (`-L orchspike`) that was killed afterwards. The owner's `~/.pi`, `~/.claude`, `~/.config` and default tmux server were never written to. No LLM token was ever billed: every recipe below runs either with no credential at all, or with a deliberately invalid one.

> **Housekeeping finding (VERIFIED).** `~/.pi/agent/auth.json` and `~/.pi/agent/models-store.json` exist in the owner's real home, both `{}`, both created **2026-09-19 20:12:10** by the earlier profiling pass — i.e. **pi writes its config directory into `$HOME` on first run even when it does nothing else**. They are empty and harmless; they are also proof that *any* pi invocation without `PI_CODING_AGENT_DIR` set will mint an account store in `$HOME`. The orchestrator must set that variable on **every** invocation, including `pi auth check` and `pi --list-models`. Delete the two files if you want the home tree clean; nothing here depends on them.

---

## 0. Conventions used by every recipe

```bash
# --- pinned, absolute, PATH-independent (VERIFIED: /usr/local/bin/node is v18.17.1 and CANNOT run pi) ---
PI_NODE=/Users/sasha-marchuk/.nvm/versions/node/v24.18.0/bin/node
PI_CLI=$SBX/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js   # the `pi` bin target
pi() { "$PI_NODE" "$PI_CLI" "$@"; }

# --- per-task identity ---
TASK=task-1042                 # orchestrator's own id; becomes the pi session id AND the tmux pane title
ACCOUNT=acct-mimo-sgp          # orchestrator's account name
ORCH_ROOT=/Users/sasha-marchuk/.orch/pi

export PI_CODING_AGENT_DIR="$ORCH_ROOT/accounts/$ACCOUNT"      # credentials + model store, per account
export PI_CODING_AGENT_SESSION_DIR="$ORCH_ROOT/sessions"       # ONE flat dir for all tasks
export ORCH_DIR="$ORCH_ROOT/runs/$TASK"                        # sidecar files this spike's extension writes
mkdir -p "$PI_CODING_AGENT_DIR" "$PI_CODING_AGENT_SESSION_DIR" "$ORCH_DIR"

# --- cwd must be byte-identical across every launch of a task (see §10) ---
CWD=$(cd /Users/sasha-marchuk/Work/<work-project> && pwd -P)
```

**Two rules that everything else depends on, both VERIFIED by execution and confirmed in source:**

1. **Resolve the cwd once, with `pwd -P`, and store it with the task.** pi compares session cwd with `path.resolve()` and **no `realpath`** (`src/utils/paths.ts:82`, `resolvePath` = tilde-expand + `nodeResolvePath`; `src/core/session-manager.ts:631`, `sessionCwdMatches` = `resolvePath(a) === resolvedCwd`). `/tmp/x` ≠ `/private/tmp/x`, and a symlinked worktree ≠ its target. A one-character difference silently loses the whole transcript (§10, trap 2).
2. **Launch pi with an absolute Node path.** VERIFIED: `/usr/local/bin/node` (v18.17.1) → `ERR_MODULE_NOT_FOUND`, exit 1. `~/.nvm/.../v22.18.0` works despite being one patch below the declared `engines: node >=22.19.0` (npm `engines` is advisory). A daemon-spawned session inheriting a minimal `PATH` will pick the wrong one.

**Session dir layout (VERIFIED by execution).** With `PI_CODING_AGENT_SESSION_DIR` set, sessions land **flat** in that directory:
`$PI_CODING_AGENT_SESSION_DIR/<ISO-timestamp-with-:-and-.-as->_<session-id>.jsonl`.
Without it, pi uses `~/.pi/agent/sessions/--<cwd>--/…` where the directory name is, verbatim from `src/core/session-manager.ts:479`:

```js
const safePath = `--${resolvedCwd.replace(/^[/\\]/, "").replace(/[/\\:]/g, "-")}--`;
```

Use the flat layout. It makes `ls` a session list and removes the path-mangling from the orchestrator's code. It does **not** remove the cwd check — `SessionManager.list()` still filters by the header's `cwd` when an explicit dir is given (`session-manager.ts:1669-1677`).

---

## 1. Preflight — installed, authenticated, which account is active

```bash
# a) installed & version — VERIFIED
pi --version                       # -> 0.85.1 ; exit 0
                                   # FAIL: ERR_MODULE_NOT_FOUND (wrong node) or 127 (no cli.js)

# b) is this account's credential configured?  — VERIFIED
pi auth check --provider xiaomi-token-plan-sgp --json
# OK      -> {"status":"ready","provider":"xiaomi-token-plan-sgp","authType":"api_key"}   exit 0
# FAIL    -> {"status":"not_ready","provider":"…","reason":"credentials_not_configured"}  exit 1
#         -> {"status":"not_ready","provider":"…","reason":"provider_not_found"}          exit 1
#         -> {"status":"invalid",  "provider":"…","reason":"invalid_state"}               exit 1

# c) WHICH account — fingerprint, never log the secret — VERIFIED
FP=$(pi auth print-api-key --provider xiaomi-token-plan-sgp | shasum -a 256 | cut -c1-16)
[ "$FP" = "$EXPECTED_FP" ] || { echo "WRONG ACCOUNT: $FP"; exit 1; }

# d) does the model actually exist for this credential? — VERIFIED
pi --list-models xiaomi-token-plan-sgp
# provider               model          context  max-out  thinking  images
# xiaomi-token-plan-sgp  mimo-v2.5      1.0M     131.1K   yes       yes
# xiaomi-token-plan-sgp  mimo-v2.5-pro  1.0M     131.1K   yes       no
```

**Status/reason enum is exhaustive and source-verified** — `src/cli/auth-check.ts` (recovered from the shipped `.js.map` `sourcesContent`):
`AuthCheckStatus = "ready" | "not_ready" | "invalid"`;
`AuthCheckReason = "provider_not_found" | "credentials_not_configured" | "credential_not_available" | "invalid_state"`;
`authType = "api_key" | "oauth"`.

**Four preflight traps, all VERIFIED by execution:**

| Trap | Observed | Orchestrator rule |
|---|---|---|
| `pi auth check` with no `--provider`/`--model` | prints `Error: Auth checks require --provider…` and **exits 0** | never branch on exit code alone; require the JSON to parse and carry `status` |
| `auth check` is **offline** — `ModelRuntime.create({allowModelNetwork:false, refreshOnCreate:false})`, source-verified | `"ready"` means *a credential is present*, **not** that it works | a 401 is still possible; §6 is the only real proof |
| `pi --list-models <provider>` returns *nothing, exit 0* when that provider has no credential | looks identical to "provider doesn't exist" | pair (b) and (d); (d) alone is ambiguous |
| `auth check` rejects `--api-key` | `Error: Auth commands only accept --provider and --model`, **exit 2** | an `--api-key`-launched session cannot be preflighted; use `auth.json` or env instead |

**Install, once, pinned (CLAIMED — not executed; the sandbox here was built by the earlier pass):**
`npm install -g @earendil-works/pi-coding-agent@0.85.1` — 21.9 MB unpacked, 1056 files, 15 runtime deps, npm attestation + SLSA v1 present.
**Do not run pi from an unpacked `npm pack` tarball** — VERIFIED: it dies with `Cannot find package '@earendil-works/chord'`. pi must be *installed*.
Disable self-update in an unattended context: `pi update --self` exists; `PI_OFFLINE=1` (or `--offline`) *"disables startup network operations, including update checks, package updates, and install/update telemetry"* (`docs/environment-variables.md:84`, VERIFIED).

---

## 2. Start a task headless, with a pinned session id, capturing structured output

### 2a. The pre-seed — do this before every first launch of a task

⚠ **CORRECTION to `pi.md` §B.** The profile reports the "nothing on disk until the first assistant message" defect as unavoidable and calls the startup window "completely unrecoverable". **It is avoidable, in one line.** `src/core/session-manager.ts:898-923` (`_setSessionFile`) sets `this.flushed = true` whenever the target file **exists and parses** — including a file containing only a header, and including a zero-byte file. From then on `_persist()` takes the `appendFileSync` branch for *every* entry.

```bash
# Create the session file yourself. Cost: one line of JSON. Benefit: the defect disappears.
SID="$TASK"
TS=$(date -u +%Y-%m-%dT%H:%M:%S.000Z); FTS=${TS//:/-}; FTS=${FTS//./-}
SFILE="$PI_CODING_AGENT_SESSION_DIR/${FTS}_${SID}.jsonl"
printf '{"type":"session","version":3,"id":"%s","timestamp":"%s","cwd":"%s"}\n' "$SID" "$TS" "$CWD" > "$SFILE"
```

**VERIFIED end-to-end.** Launched against that header-only file, `get_state` returned `"sessionId":"orch-seed-002"` (our id, adopted from the header — not a random UUID) and a `thinking_level_change` entry was on disk **244 ms after start**, with no assistant message and no LLM call. A later `bash` entry appended immediately too (file grew 1 → 2 → 4 lines across runs).

**Why this matters more than it sounds.** Without the pre-seed I reproduced the defect exactly: a full RPC session that set a name, emitted `session_info`, and executed a real `bash` command left **no file and not even the project directory** on disk, while `get_state` cheerfully reported a `sessionFile` path that did not exist. With the pre-seed, "the process died before it wrote anything" stops being a state the orchestrator has to model.

> Caveat (source-verified, `session-manager.ts:1043-1052`): the first flush after a *new* (unseeded) session uses `openSync(file, "wx")` — exclusive create. Two unseeded sessions minted in the same millisecond with the same id would throw. Pre-seeding avoids that path entirely.

### 2b. Launch

```bash
pi --mode rpc \
   --session "$SID" \
   --provider xiaomi-token-plan-sgp --model mimo-v2.5-pro \
   --name "$TASK" \
   -ne -e "$ORCH_ROOT/ext/orch.ts" \
   --tools read,grep,find,ls,edit,write,bash \
   < "$FIFO_IN" > "$LOG_OUT" 2> "$LOG_ERR" &
```

**Flag notes, all VERIFIED from `pi --help` at 0.85.1:**
`--session <path|id>` (resume, loud on miss) vs `--session-id <id>` (create, **silent** on miss) — see §10.
`--mode <text|json|rpc>`; `--print|-p`; `--name|-n`; `--extension|-e` (repeatable); `--no-extensions|-ne` *(discovery off, explicit `-e` still loads)*; `--no-skills|-ns`; `--tools|-t` (strict allowlist); `--exclude-tools|-xt`; `--no-builtin-tools|-nbt`; `--no-tools|-nt`; `--approve|-a` / `--no-approve|-na`; `--offline`; `--session-dir`; `--fork <path|id>`; `--export <file>`; `--list-models [search]`; `--append-system-prompt`; `--thinking <off|minimal|low|medium|high|xhigh|max>`.
Built-in tools: `read bash powershell edit write grep find ls` — **`grep`, `find`, `ls` are OFF by default** (help text: *"read-only, off by default"*).

### 2c. Choosing a mode — and the one that will bite you

| mode | supervisor can send input | structured out | provider-error exit code |
|---|---|---|---|
| `--mode rpc` | **yes, two-way, id-correlated** | JSONL events | n/a — errors arrive as events + `response.success:false` |
| `--mode json -p` | no | JSONL events | ⚠ **always 0** |
| `-p` (text) | no | plain text | **1** |
| TUI (default) | keystrokes only | none | n/a |

⚠ **CORRECTION to `pi.md` §A — the most important new finding in this spike.** The profile states *"pi fails loudly … the harness field-notes failure class of 'reports success and does nothing' does not apply to pi's launch path."* **It applies, and precisely in the mode an orchestrator would choose.**

VERIFIED by execution with a deliberately invalid Anthropic key:

```
$ pi -p           "say hi" --provider anthropic --model claude-sonnet-4-5 ;  echo $?
  stderr: 401 {"type":"error","error":{"type":"authentication_error",…}}      -> 1

$ pi --mode json -p "say hi" --provider anthropic --model claude-sonnet-4-5 ;  echo $?
  stderr: (empty)                                                             -> 0
  stdout: …{"stopReason":"error","errorMessage":"401 …"}… {"type":"agent_settled"}
```

Source-confirmed, `src/modes/print-mode.ts:138-155` — the `stopReason === "error" || "aborted"` → `exitCode = 1` branch sits **inside `if (mode === "text")`** and is unreachable under `--mode json`. Deterministic, not a race.

**Rule: in `--mode json`, the exit code carries no information about whether the work happened.** Success is:

```bash
python3 - "$LOG_OUT" <<'EOF'
import json,sys
ok=False
for line in open(sys.argv[1]):
    line=line.strip()
    if not line: continue
    e=json.loads(line)
    if e.get("type") in ("message_end","agent_end"):
        msgs=e.get("messages") or [e.get("message")]
        for m in msgs:
            if m and m.get("role")=="assistant":
                if m.get("stopReason")=="error": sys.exit(f"FAIL {m.get('errorMessage')}")
                if m.get("stopReason") in ("stop","toolUse"): ok=True
print("OK" if ok else "NO ASSISTANT TURN")
EOF
```

**Event vocabulary (VERIFIED, `docs/rpc.md:858-882`):** `agent_start`, `agent_end` (`willRetry`), **`agent_settled`** (*"no automatic retry, compaction retry, or queued continuation remains"* — this is the real "done"), `turn_start/turn_end`, `message_start/message_update/message_end`, `bash_execution_update`, `tool_execution_start/update/end`, `queue_update`, `compaction_start/compaction_end`, `auto_retry_start/auto_retry_end`, `summarization_retry_*`, `extension_error`. First stdout line in `--mode json` is the session header (VERIFIED: emitted even when the run then fails for lack of a key).

**RPC client framing (VERIFIED in doc `rpc.md:28-38`, and by building one):** split on `\n` **only**, strip a trailing `\r`. **Node's `readline` is not protocol-compliant** — it also splits on U+2028/U+2029, which are legal inside JSON strings. And **hold stdin open**: `src/modes/rpc/rpc-mode.ts:806` is `process.stdin.on("end", onInputEnd)` → immediate `shutdown()`, with no drain of in-flight async commands. VERIFIED: a `bash` command issued just before EOF produced no response and no session entry.

---

## 3. Start the same task in a visible terminal the owner can type into

```bash
tmux new-session -d -s "pi-$TASK" -x 220 -y 60 -c "$CWD" \
  "PI_CODING_AGENT_DIR=$PI_CODING_AGENT_DIR PI_CODING_AGENT_SESSION_DIR=$PI_CODING_AGENT_SESSION_DIR ORCH_DIR=$ORCH_DIR \
   '$PI_NODE' '$PI_CLI' --session $SID --name $TASK -ne -e '$ORCH_ROOT/ext/orch.ts' \
   --provider xiaomi-token-plan-sgp --model mimo-v2.5-pro"
tmux set -g extended-keys on          # tmux >= 3.5, else Shift+Enter / Ctrl+Enter collapse to Enter
tmux set -g extended-keys-format csi-u
```

**VERIFIED on this machine (tmux 3.6a, private socket, cleaned up):**

* `tmux list-panes -a -F '#{pane_title}'` → **`π - task-1042 - work`**. pi sets the terminal title to `π - <--name> - <cwd basename>`. **This is the pane→task map** — pass the orchestrator's task id as `--name` and the mapping is free.
* The footer renders context as `0.0%/0` on the bottom-left and the model on the bottom-right — so `capture-pane` is a context read of last resort (§5 fallback).
* `capture-pane -p -t <pane>` renders the full resumed history, the loaded extension list (`[Extensions] orch.ts`), and any open dialog.
* ⚠ **`ps` is useless here.** VERIFIED: `ps -o args= -p <pane_pid>` prints **`pi`** — pi rewrites `process.title`, so the session id, provider and model are *not* recoverable from the process table. Pane title or the orchestrator's own bookkeeping are the only identity sources in TUI mode.

**The tradeoff, restated because the recipes below fork on it.** A pi process is **either** a TUI the owner types into **or** an RPC process the supervisor drives. `--mode rpc` owns stdin. Everything in §5, §8 and §9 that is "native" is native *in RPC mode only*.

**The honest middle path this spike recommends:** run every task in `--mode rpc` inside a tmux pane, pipe the JSONL through a renderer of the orchestrator's own (even `jq -r 'select(.type=="message_update")…'` is enough to start), and give the owner a `tmux send-keys`-free "take over" path that posts a `steer` through the orchestrator. The owner loses raw typing; he gains an intervention channel that is *acknowledged*, which the TUI never gives him.

---

## 4. Tell whether the session is alive, working, waiting, or finished — from outside

Four independent signals. Use all four; each covers a hole in the others.

```bash
# 1. PROCESS — is anything there at all
kill -0 "$PID" 2>/dev/null                              # alive
tmux list-panes -a -F '#{pane_title} #{pane_dead} #{pane_pid}'   # TUI variant

# 2. RPC STATE — authoritative, RPC mode only (VERIFIED)
{"id":"live","type":"get_state"}
# -> {"success":true,"data":{
#      "isStreaming":false,"isCompacting":false,
#      "messageCount":1,"pendingMessageCount":2,
#      "sessionFile":"…/2026-09-19T13-25-45-000Z_task-1042.jsonl",
#      "sessionId":"task-1042","sessionName":"task-1042",
#      "steeringMode":"one-at-a-time","followUpMode":"one-at-a-time",
#      "autoCompactionEnabled":true,"model":{…}}}

# 3. TRANSCRIPT CURSOR — durable across supervisor restarts (VERIFIED)
{"id":"cur","type":"get_entries","since":"<last-seen-entry-id>"}
# -> {"data":{"entries":[…strictly after…],"leafId":"83888ab0"}}
#    leafId unchanged  => the active branch has not moved
#    success:false     => your cursor id is not in this session (you are on the wrong file)

# 4. FILE — works for TUI, works with no process, survives reboot
stat -f '%m %z' "$SFILE"      # mtime + size; both advance per entry (appendFileSync, one line each)
```

**State table:**

| Signal combination | Meaning |
|---|---|
| `kill -0` ok, `isStreaming:true` | **working** |
| `kill -0` ok, `isStreaming:false`, `pendingMessageCount:0`, `agent_settled` seen | **finished this turn, idle** |
| `kill -0` ok, idle, `pendingMessageCount>0` | **waiting to drain its queue** |
| `kill -0` ok, an unanswered `extension_ui_request` on stdout | **blocked on a question** → §9 |
| `kill -0` ok, `auto_retry_start` with no `auto_retry_end` | **retrying** — do not kill; `abort_retry` if you must |
| `kill -0` fails, file mtime recent | crashed mid-work → §10 resume |
| `kill -0` fails, **no file at all** | died before the first write — **impossible if you pre-seeded (§2a)**; if you see it, your pre-seed did not run |

**Why the file alone is not enough (VERIFIED):** `isStreaming` has no on-disk equivalent, and file mtime does not advance while a long LLM call is in flight — a thinking model looks identical to a wedged one from the filesystem. Conversely `get_state` needs RPC. Hence the sidecar in §5.

⚠ **Two "success" values that are not success, both VERIFIED:**
* `abort_bash` → `{"success":true}`, and the aborted command's own response is **`{"success":true,"data":{"output":"","cancelled":true}}`**. Branch on `data.cancelled` and `data.exitCode`, never on `success`.
* A `bash` whose command exits non-zero still returns `success:true` with the real `exitCode` in `data`.

---

## 5. Read how full the context is, then force compaction or a handoff, then PROVE it

### 5a. Read — native, RPC (VERIFIED for shape and for the absent case)

```json
{"id":"ctx","type":"get_session_stats"}
```
```json
{"success":true,"data":{
  "sessionFile":"…","sessionId":"task-1042",
  "userMessages":5,"assistantMessages":5,"toolCalls":12,"toolResults":12,"totalMessages":22,
  "tokens":{"input":50000,"output":10000,"cacheRead":40000,"cacheWrite":5000,"total":105000},
  "cost":0.45,
  "contextUsage":{"tokens":60000,"contextWindow":200000,"percent":30}}}
```

`docs/rpc.md:597` states the number is not decorative: *"`contextUsage` contains the actual current context-window estimate used for compaction and footer display."* The supervisor reads exactly what the compactor acts on.

**Three failure shapes the orchestrator must handle — first two VERIFIED by execution:**
1. **`contextUsage` absent entirely** when no model/context window is resolved. I reproduced this in every credential-free run: `get_session_stats` returned tokens and cost but **no `contextUsage` key**. Treat missing as **unknown**, never as 0.
2. **`ctx.getContextUsage()` returns `undefined`** in the same condition — my sidecar logged `contextTokens:null, contextWindow:null, contextPercent:null` every 5 s.
3. **`tokens` and `percent` are `null` immediately after a compaction** until a fresh post-compaction assistant response supplies usage (`rpc.md:598`, CLAIMED-from-doc). Polling right after a compact and reading "empty" would loop the orchestrator into compacting forever.

**Offline, no-RPC bonus (VERIFIED):** `cost` and `tokens` are reconstructed from the session file alone. My hand-written `usage.cost.total = 0.003` came back as `"cost":0.003` from a fresh process with no network. **Per-session spend is auditable from disk, hours later, with pi not running.** This is the only spend signal pi gives you (§6).

### 5b. Trigger — native, RPC (VERIFIED, including the failure shape)

```json
{"id":"cmp","type":"compact"}
{"id":"cmp","type":"compact","customInstructions":"Keep the file paths and the failing test names"}
{"type":"set_auto_compaction","enabled":false}
```

Observed on a too-small session:
```json
{"type":"compaction_start","reason":"manual"}
{"type":"compaction_end","reason":"manual","aborted":false,"willRetry":false,
 "errorMessage":"Compaction failed: Nothing to compact (session too small)"}
{"id":"cmp","type":"response","command":"compact","success":false,"error":"Nothing to compact (session too small)"}
```

### 5c. Prove — three receipts, one of them durable

1. **Command response** — `{"summary","firstKeptEntryId","tokensBefore","estimatedTokensAfter","usage","details"}`. `estimatedTokensAfter` is documented as a heuristic, good for "it happened", not for billing.
2. **Events** — `compaction_start{reason:"manual"|"threshold"|"overflow"}` then `compaction_end{result,aborted,willRetry,errorMessage?}`. `reason:"overflow"` + success ⇒ `willRetry:true` and pi re-runs the prompt itself.
3. **On disk, durable** — a typed entry lands in the JSONL. Shape **source-verified** in `src/core/session-manager.ts` (`CompactionEntry`), and it carries one field the docs omit:

```jsonc
{"type":"compaction","id":"…","parentId":"…","timestamp":"…",
 "summary":"…","firstKeptEntryId":"abc123","tokensBefore":150000,
 "usage":{…},"details":{"readFiles":[…],"modifiedFiles":[…]},
 "fromHook": true }        // true => an extension produced this summary, not pi
```

**Proof recipe:** `grep -c '"type":"compaction"' "$SFILE"` before and after. Survives a supervisor restart; re-readable hours later.

**Automatic threshold (VERIFIED, `docs/compaction.md` + `docs/settings.md:119-127`):** fires when `contextTokens > contextWindow - reserveTokens`; `compaction.reserveTokens` default **16384**, `compaction.keepRecentTokens` default **20000**, both settable in `$PI_CODING_AGENT_DIR/settings.json`.

**Custom compaction / handoff.** `session_before_compact` fires for **both** manual and automatic paths, receives `preparation{messagesToSummarize, turnPrefixMessages, previousSummary, fileOps, tokensBefore, firstKeptEntryId, settings}`, `reason`, `willRetry`, an `AbortSignal`, and may `return {cancel:true}` or supply its own summary — including one generated by a cheaper model. Shipped worked examples: `examples/extensions/custom-compaction.ts`, `trigger-compact.ts` (≈40 lines: compacts on crossing a threshold, registers `/trigger-compact`), and **`handoff.ts`** — *"Instead of compacting (which is lossy), handoff extracts what matters for your next task and creates a new session with a generated prompt."* All CLAIMED (read, not executed — no credential).

### 5d. Fallbacks when RPC is not available

| Situation | Fallback | Tag |
|---|---|---|
| TUI mode | `tmux capture-pane -p -t "pi-$TASK" \| tail -2` → footer `12.4%/248301` | VERIFIED (footer format observed as `0.0%/0`) |
| Any mode, no RPC | sidecar extension writes `contextPercent` to `$ORCH_DIR/heartbeat.jsonl` every 5 s | **VERIFIED** — see §12 |
| Force compaction without RPC | register a command in the sidecar and send `/orch-compact` via `tmux send-keys`, or call `ctx.compact()` from a timer inside the extension | CLAIMED (mechanism verified for `/orch-probe`, not for compact) |

---

## 6. Read remaining quota and the reset time; detect a limit hit in-band

**There is no first-party quota read, and there cannot be one.** pi is a BYO-credential client for ~35 providers; the quota lives at the provider, in the provider's shape.

**Exhaustive grep of `dist/` at 0.85.1 (VERIFIED):**

| pattern | hits |
|---|---|
| `oauth/usage` | **0** |
| `x-ratelimit` | **0** |
| `anthropic-ratelimit` | **0** |
| `five_hour` / `seven_day` | **0** / **0** |
| `usage_limit_reached` | 1 — only in `bundle/chunks/openai-codex-responses-*.js` |
| `resets_at` | 2 — same file |
| `retry-after` | 22 — all inside vendor SDK retry loops |

`pi --help` lists exactly these subcommands: `install remove uninstall update list config auth`. **No `usage`, no `limits`, no `quota`.** No window model of any kind.

### 6a. Detect a limit hit in-band — three places, in order of reliability

**1. Raw provider headers, per request — the real lever.** `after_provider_response` fires *after the HTTP response and before its stream body is consumed*, with `event.status` and `event.headers` (normalized). `docs/extensions.md:735`: *"Runs once per provider request; retries reuse the same headers rather than re-firing the hook."* The sidecar in §12 writes every one to `$ORCH_DIR/ratelimit.jsonl`:

```jsonc
{"ts":"…","status":429,"headers":{"retry-after":"47","anthropic-ratelimit-unified-reset":"…"}}
```

Richer and more current than polling a usage endpoint on a timer. **Documented caveat, quoted:** *"Header availability depends on provider and transport. Providers that abstract HTTP responses may not expose headers."* Whether Anthropic, Xiaomi MiMo SGP, Kimi or GLM actually expose usable headers here is **UNKNOWN** — it needs one live request per provider, which this spike did not spend.

**2. `stopReason:"error"` + `errorMessage` on the assistant message** — in the event stream *and persisted in the session file*. VERIFIED: my invalid-key run produced `"stopReason":"error","errorMessage":"401 {…authentication_error…}"` both in `--mode json` stdout and in the on-disk JSONL. Match `/429|rate.?limit|usage limit|quota/i` against `errorMessage`.

**3. The prose sentence** — for ChatGPT/Codex OAuth only. Source, verbatim (`bundle/chunks/openai-codex-responses-*.js`):

```js
if (/usage_limit_reached|usage_not_included|rate_limit_exceeded/i.test(code) || response.status === 429) {
  let plan = err.plan_type ? ` (${err.plan_type.toLowerCase()} plan)` : "",
      mins = err.resets_at ? Math.max(0, Math.round((err.resets_at*1e3 - Date.now())/6e4)) : void 0,
      when = mins !== void 0 ? ` Try again in ~${mins} min.` : "";
  friendlyMessage = `You have hit your ChatGPT usage limit${plan}.${when}`.trim()
}
```
The provider's structured `resets_at` **is parsed and then thrown away**. The orchestrator's only access is a regex over `"You have hit your ChatGPT usage limit (pro plan). Try again in ~47 min."` — one upstream wording change from silent failure.

### 6b. Retry settings the orchestrator MUST pin

`$PI_CODING_AGENT_DIR/settings.json`:
```json
{ "retry": { "enabled": true, "maxRetries": 3, "baseDelayMs": 2000,
             "provider": { "maxRetries": 0, "maxRetryDelayMs": 60000 } } }
```
`docs/settings.md:152`, verbatim: *"Keep `retry.provider.maxRetries` at `0` … Setting it above `0` can make SDK/provider retries handle out-of-usage-limit errors before Pi sees them, **which may block the agent until the provider quota resets in some circumstances.**"* That is an overnight-run killer — a wedged process that reads as alive. Default is `0`; assert it, do not assume it.
`retry.provider.maxRetryDelayMs` (default 60000) makes pi fail fast rather than wait silently when a provider asks for a longer delay. Keep it non-zero.
In-band retry visibility: `auto_retry_start{attempt,maxAttempts,delayMs,errorMessage}` / `auto_retry_end{success,attempt,finalError?}`; `{"type":"abort_retry"}` cancels one.

### 6c. The economic trap specific to this owner

`docs/providers.md:35`, verbatim: *"Anthropic subscription auth is active for Claude Pro/Max accounts. **Third-party harness usage draws from extra usage and is billed per token, not against Claude plan limits.**"* (settings key `warnings.anthropicExtraUsage`, default `true`.)

The owner's existing discipline — `five_hour.utilization` / `seven_day.utilization` / `resets_at` from `api.anthropic.com/api/oauth/usage`, wired into `claude-limits` in `~/.config/claude-profiles/profiles.sh` — **measures a budget pi does not consume**. Running pi on his Claude subscription spends money per token while that number does not move. An orchestrator treating pi-on-Anthropic as "free until the weekly limit" is wrong in the most expensive possible direction.

**Policy this spike recommends: run pi only on per-token / token-plan providers.** The owner already holds exactly such a credential — VERIFIED, `~/.config/claude-mimo/env` sets `ANTHROPIC_BASE_URL=https://token-plan-sgp.xiaomimimo.com` with model `mimo-v2.5-pro`, which is **byte-for-byte pi's built-in `xiaomi-token-plan-sgp` provider** (`baseUrl: https://token-plan-sgp.xiaomimimo.com/v1`, models `mimo-v2.5`, `mimo-v2.5-pro`, 1.0M context). The same token should register directly as `auth.json` key `xiaomi-token-plan-sgp` — *should*, because Claude Code drives that host with the **Anthropic Messages** wire format while pi's built-in uses **`openai-completions`** at `/v1`. Whether the token authenticates both is **UNKNOWN**; it is one cheap live request to settle, and this spike deliberately did not spend it.

**Budget model the orchestrator must supply itself, since pi supplies none:**
```bash
# after every session, offline, from the file — VERIFIED working
pi --mode rpc --session "$SID" <<< '{"type":"get_session_stats"}' | jq '.data.cost, .data.tokens.total'
```
Accumulate per account per day; stop the queue on a spend ceiling. There is no window, no reset, and nothing to poll.

---

## 7. Switch a new session to a different account, and verify before work starts

**Account is a directory.** `PI_CODING_AGENT_DIR` overrides the config dir (default `~/.pi/agent`) — the same `CLAUDE_CONFIG_DIR` pattern the owner's profile switcher already uses, so no new concepts.

```bash
# one directory per account; credentials never leave it
ORCH_ROOT=/Users/sasha-marchuk/.orch/pi
install -d -m 700 "$ORCH_ROOT/accounts/acct-mimo-sgp"
cat > "$ORCH_ROOT/accounts/acct-mimo-sgp/auth.json" <<'JSON'
{ "xiaomi-token-plan-sgp": { "type": "api_key", "key": "!security find-generic-password -ws 'mimo-sgp'" } }
JSON
chmod 600 "$ORCH_ROOT/accounts/acct-mimo-sgp/auth.json"

# switch = set one variable at spawn
PI_CODING_AGENT_DIR="$ORCH_ROOT/accounts/acct-mimo-sgp" pi --mode rpc --session "$SID" …
```

**VERIFIED by execution — two isolated accounts, distinct fingerprints:**

```
acctA auth.json  {"anthropic":{"type":"api_key","key":"sk-ant-ACCOUNT-A-0000"}}
acctB auth.json  {"anthropic":{"type":"api_key","key":"!printf sk-ant-ACCOUNT-B-1111"}}

PI_CODING_AGENT_DIR=…/acctA  pi auth check … --json  -> {"status":"ready",…,"authType":"api_key"}   fp=16016070b5146006
PI_CODING_AGENT_DIR=…/acctB  pi auth check … --json  -> {"status":"ready",…,"authType":"api_key"}   fp=c207aa7039790d13
```
The differing fingerprint proves the `!command` form executed. `auth.json` is created `0600`; a leading `!` runs the whole value and uses stdout, **cached for the process lifetime** (so no mid-run Keychain dialog); `$VAR` interpolates; `$$` / `$!` escape.

This composes with what the owner already has: his Claude credentials sit in the macOS Keychain under `Claude Code-credentials-<8 hex>` (VERIFIED — the service name pattern is present in his keychain), reachable from pi with one `!security find-generic-password` line and **no secret copied into a config file**.

### Verify the switch BEFORE work starts

```bash
pi auth check --provider "$PROVIDER" --json | jq -e '.status=="ready"' >/dev/null || exit 1
FP=$(pi auth print-api-key --provider "$PROVIDER" | shasum -a 256 | cut -c1-16)
[ "$FP" = "$EXPECTED_FP" ] || { echo "account mismatch"; exit 1; }
```

⚠ **Precedence trap, VERIFIED and NOT in `pi.md`.** The documented order is `--api-key` → `auth.json` → environment variable → `models.json` keys. I confirmed the middle pair by execution:

```
ANTHROPIC_API_KEY=sk-ant-FROM-ENV  PI_CODING_AGENT_DIR=…/acctA  pi auth print-api-key --provider anthropic
-> sk-ant-ACCOUNT-A-0000        # the env var is SILENTLY IGNORED
```

**An orchestrator that switches accounts by exporting a provider env var will be silently overridden by any `auth.json` in that config dir.** Pick one mechanism per account directory and assert it with the fingerprint check above.

Broken-credential shapes (VERIFIED): a `!command` that exits non-zero → `auth check` reports `credentials_not_configured` (exit 1) and `print-api-key` prints `Error: No usable API key is configured` (exit 1). Both loud. Good.

### Changing a RUNNING session's account — **NO**

Source-verified across the complete RPC command list (`src/modes/rpc/rpc-mode.ts`, 33 `case` labels): `set_model`, `cycle_model`, `get_available_models` exist; there is **no** `set_api_key`, `set_provider_credential` or `reload_auth`. `auth.json` shell keys are cached for the process lifetime, so rewriting the file under a live process changes nothing. `set_model` to a different *provider* will use whatever credential that provider already resolves to — you can move a live session Anthropic→Xiaomi, never Anthropic-A→Anthropic-B.

**Fallback (emulated rotation):**
```
abort  ->  /orch-stop (graceful, §11)  ->  process exits  ->  relaunch:
PI_CODING_AGENT_DIR=<new account> pi --mode rpc --session "$SID"   # SAME cwd, byte-identical
```
Cost: one restart plus a context rebuild from the session file. Cheap, but it makes "rotate on exhaustion" a restart operation, not a reconfiguration.

---

## 8. Deliver an instruction into a running session and confirm it arrived

**This is the axis the current harness fails at, and pi answers it properly — in RPC mode.**

| command | lands |
|---|---|
| `{"type":"prompt","message":…}` | immediately if idle; **rejected with an error** if streaming and no `streamingBehavior` given |
| `{"type":"prompt","message":…,"streamingBehavior":"steer"\|"followUp"}` | as steer / follow-up |
| `{"type":"steer","message":…}` | after the current turn's tool calls, **before the next LLM call** |
| `{"type":"follow_up","message":…}` | only once the agent has fully stopped |

Pacing: `{"type":"set_steering_mode","mode":"all"|"one-at-a-time"}` and `set_follow_up_mode` (both default `one-at-a-time`).

**VERIFIED transcript from this machine:**
```
>> {"id":"r7","type":"steer","message":"steer-probe-A"}
<< {"type":"queue_update","steering":["steer-probe-A"],"followUp":[]}
<< {"id":"r7","type":"response","command":"steer","success":true}
>> {"id":"r8","type":"follow_up","message":"followup-probe-B"}
<< {"type":"queue_update","steering":["steer-probe-A"],"followUp":["followup-probe-B"]}
<< {"id":"r8","type":"response","command":"follow_up","success":true}
>> {"id":"r9","type":"get_state"}
<< {"…"pendingMessageCount":2}
>> {"id":"r10","type":"clear_queue"}
<< {"type":"queue_update","steering":[],"followUp":[]}
<< {"id":"r10","type":"response","command":"clear_queue","success":true,
    "data":{"steering":["steer-probe-A"],"followUp":["followup-probe-B"]}}
```

**Four independent acknowledgements**, which is why this is a real answer and not a hopeful one:
1. the id-correlated `response`;
2. an unsolicited `queue_update` echoing the full queues;
3. `get_state.pendingMessageCount`;
4. **`clear_queue` hands the stranded text back** instead of discarding it.

`docs/rpc.md:78` is unusually careful about what the ack means: *"`success: true` means the prompt was accepted, queued, or handled immediately. `success: false` means the prompt was rejected before acceptance. Failures after acceptance are reported through the normal event and message stream, not as a second `response` for the same request id."* VERIFIED negatively too — a `prompt` with no model resolved returned `{"success":false,"error":"No API key found for the selected model…"}`.

**This is the direct answer to the harness field note about a nudge that cannot submit stranded text.** In pi, text is never marooned in an editor buffer: it is accepted into a *named, readable, drainable* queue, or explicitly rejected.

### TUI fallback — and it is better than blind

`tmux send-keys -t "pi-$TASK" "do X instead" Enter` — VERIFIED: the text lands in the editor and Enter submits it. On its own that is the old, unconfirmable nudge: I also VERIFIED that a submission which errors before the agent starts leaves the session file **unchanged** (7 lines → 7 lines), so the transcript is not an ack channel.

**Make it confirmable with the `input` hook.** `docs/extensions.md:909` — `input` fires on every user input with `event.source ∈ "interactive" | "rpc" | "extension"`, before skill/template expansion. The sidecar (§12) appends each one to `$ORCH_DIR/inbox.jsonl`. **VERIFIED both paths on this machine:**

```jsonc
{"ts":"2026-09-19T13:29:48.372Z","source":"rpc",        "streamingBehavior":null,"text":"instruction-from-supervisor"}
{"ts":"2026-09-19T13:30:00.769Z","source":"interactive","streamingBehavior":null,"text":"nudge-from-tmux"}
```

The second line is a `tmux send-keys` nudge, acknowledged, with its exact text, in a file the supervisor polls. **That closes the blind-nudge gap for the TUI path too** — at the cost of the sidecar extension.

Also available: `{"type":"abort"}` — *"abort the current operation and wait for the session to become idle before responding"*, so its response is a genuine quiescence signal (VERIFIED: `{"success":true}` returned).

---

## 9. Answer a permission prompt or a clarifying question without a human

pi ships **no permission prompts of its own** (§10 guardrails). Questions come from extensions — and in RPC mode they become an id-correlated request/response pair on the same stdio channel.

**VERIFIED end-to-end on this machine, with no credential and no LLM call:**

```
>> {"id":"c2","type":"prompt","message":"/orch-probe"}
<< {"type":"extension_ui_request","id":"2ea3096c-…","method":"select",
    "title":"orch-probe: pick one","options":["ping","pong"],"timeout":15000}
>> {"type":"extension_ui_response","id":"2ea3096c-…","value":"ping"}
<< {"type":"extension_ui_request","id":"63aa414b-…","method":"notify",
    "message":"orch-probe got: ping","notifyType":"info"}
<< {"id":"c2","type":"response","command":"prompt","success":true}
```
and the extension's own sidecar recorded `{"kind":"probe_answer","value":"ping"}`.

**Protocol (VERIFIED, `docs/rpc.md:1207-1375`):**
* **Dialog** methods — `select`, `confirm`, `input`, `editor` — emit `extension_ui_request` and **block** until a matching `extension_ui_response` arrives on stdin.
* **Fire-and-forget** — `notify`, `setStatus`, `setWidget`, `setTitle`, `set_editor_text` — emit, expect nothing.
* Responses: `{"type":"extension_ui_response","id":…,"value":"Allow"}` (select/input/editor) · `{"…","confirmed":true}` (confirm) · `{"…","cancelled":true}` (any).
* An optional `timeout` (ms) makes the **agent** auto-resolve; *"the client does not need to track timeouts."* For an unattended queue that is the right default — a supervisor crash degrades to a timeout, not a permanent hang.

**`ctx.hasUI` is `true` in RPC mode and `ctx.mode` is `"rpc"`** — so an extension written for the TUI generally works unchanged under supervisor control. Degraded in RPC: `custom()` → `undefined`, `getEditorText()` → `""`, `setWorkingMessage/setFooter/setHeader/setToolsExpanded` are no-ops, `setTheme()` fails. **Anything built on `ctx.ui.custom()` — including the shipped `examples/extensions/question.ts` — will not work under RPC** and must be rewritten to `ctx.ui.select()`.

**The policy pattern** (adapted from the shipped `permission-gate.ts`, with the non-interactive branch as the unattended default):

```ts
pi.on("tool_call", async (event, ctx) => {
  if (event.toolName !== "bash") return undefined;
  const command = String((event.input as any).command ?? "");
  if (!dangerous.some(p => p.test(command))) return undefined;
  if (!ctx.hasUI) return { block: true, reason: "orch: no UI to confirm" };   // deny by default
  const choice = await ctx.ui.select(`orch-gate: allow?\n\n${command}`, ["allow","deny"], { timeout: 30000 });
  return choice === "allow" ? undefined : { block: true, reason: "orch: denied" };
});
```
Under `--mode rpc` that `ctx.ui.select()` becomes an `extension_ui_request` **the supervisor answers** — a policy engine with a human escalation path, in ~30 lines.

**TUI fallback (VERIFIED).** The same dialog rendered in the pane as a list with a visible countdown:
```
 orch-probe: pick one (13s)
 → ping
   pong
 ↑↓ navigate  enter select  escape/ctrl+c cancel
```
Answerable only by `tmux send-keys -t <pane> Down` then `Enter` — which I did, and the extension received `"pong"`. Position-dependent, brittle, and the countdown means a slow supervisor loses the race. **Use RPC for anything that gates a dangerous action.**

---

## 10. Resume after a crash, and after the machine rebooted

**One rule: `--session-id` CREATES, `--session` RESUMES. Never resume with `--session-id`.**

| flag | resolution order | on miss |
|---|---|---|
| `--session-id <id>` | cwd-local exact only (`findLocalSessionByExactId`, `src/main.js:186`) | ⚠ **silent** — yellow warning on **stderr**, then a brand-new empty session with that id |
| `--session <path\|id>` | cwd-local exact → cwd-local prefix → global exact → global prefix (`resolveSessionPath`) | **loud** — `No session found matching 'X'`, **exit 1** |

**All three behaviours VERIFIED by execution today:**

```
# A) cross-directory --session, no TTY
$ cd $WRONG_CWD && echo '{"type":"get_state"}' | pi --mode rpc --session orch-resume-001
Session found in different project: …/spike/work
Fork this session into current directory? [y/N] Aborted.        # cross-dir resume is NOT available unattended

# B) unknown --session
$ pi --mode rpc --session no-such-session-xyz </dev/null
No session found matching 'no-such-session-xyz'                 # exit 1   <- what you want

# C) --session-id from the WRONG cwd  ← the amputation
$ cd $WRONG_CWD && echo '{"type":"get_state"}' | pi --mode rpc --session-id orch-resume-001
Warning: No project session found with id 'orch-resume-001'; creating a new session with that id.
{"…","sessionId":"orch-resume-001","messageCount":0,…}          # all prior context gone, exit 0
```

⚠ **CORRECTION to `pi.md` §B, TRAP 1.** The profile treats that stderr warning as the signal of a silent fork. **It is not a usable signal**: I VERIFIED it fires identically on a *legitimate first creation* of a new session. Warning present ⇏ context lost. The orchestrator must decide from its own bookkeeping ("I expected this task to have a session") and then verify with `messageCount` / `get_entries`, not from stderr text.

⚠ Second-order risk: once a silently-forked session produces an assistant message, the flat session dir contains **two files with the same session id** and later `--session <id>` resolution is ambiguous. (In my run the fork wrote nothing, because it never got an assistant message — but unattended it would.)

### Resume recipe (VERIFIED end-to-end)

```bash
# 1. find the file — the orchestrator owns the list; there is no `pi sessions` subcommand
SFILE=$(ls -1 "$PI_CODING_AGENT_SESSION_DIR"/*_"$SID".jsonl 2>/dev/null | head -1)
[ -n "$SFILE" ] || { echo "no session for $SID — pre-seed did not run"; exit 1; }

# 2. assert cwd identity BEFORE launching
HDR_CWD=$(head -1 "$SFILE" | python3 -c 'import json,sys;print(json.load(sys.stdin)["cwd"])')
[ "$HDR_CWD" = "$CWD" ] || { echo "cwd drift: $HDR_CWD != $CWD"; exit 1; }

# 3. resume from that exact cwd, by PATH (skips id resolution entirely — no ambiguity possible)
cd "$CWD" && pi --mode rpc --session "$SFILE" --provider … --model …

# 4. prove the context came back
{"type":"get_state"}                  # messageCount > 0
{"type":"get_last_assistant_text"}    # -> "…MARKER_SURVIVED_CRASH"
{"type":"get_entries","since":"<last cursor>"}
```

**VERIFIED transcript** — I hand-wrote a three-line session file, launched `--session orch-resume-001`, and got:
```
{"command":"get_state","success":true,"data":{"sessionId":"orch-resume-001","messageCount":2,…}}
{"command":"get_last_assistant_text","success":true,"data":{"text":"Step 1 done. MARKER_SURVIVED_CRASH"}}
{"command":"get_session_stats","success":true,"data":{"tokens":{"total":120},"cost":0.003,…}}
```
No warning on stderr, entries preserved, and **every new entry appended to disk immediately** (file grew 3 → 5 lines) because an assistant message was already present.

**Crash vs reboot:** identical. Nothing is held in a daemon; there is no pi server to restart. `PI_CODING_AGENT_SESSION_DIR` must not be under `/tmp` if you want reboot survival on macOS — put it in `$HOME`.

**Durability, restated with the §2a fix applied:**

| event | survives? |
|---|---|
| kill after first entry, **with pre-seed** | **yes** — one `appendFileSync` per entry; at most the in-flight entry is lost |
| kill before first assistant message, **without pre-seed** | **no** — no file was ever created |
| reboot | same as above |
| provider outage mid-run | file intact; `auto_retry_*` then a `stopReason:"error"` assistant entry persisted |
| **two processes on one session file** | ⚠ **unarbitrated** |

**No lockfile on session files (source-verified).** `proper-lockfile` is used for `auth.json`, `settings.json` and `trust.json`, and **not** for session files. The orchestrator must enforce one writer per session itself:
```bash
exec 9>"$ORCH_DIR/$SID.lock"; flock -n 9 || { echo "already running"; exit 1; }
```

---

## 11. Stop it cleanly, leaving nothing running

**Three stops, in descending order of gentleness. All three source- or execution-verified.**

**1. Graceful, deferred to the next settle point — the one to use.** There is **no `shutdown` RPC command**; it goes through an extension. `src/modes/rpc/rpc-mode.ts:344` — `shutdownHandler: () => { shutdownRequested = true; }`, consumed after each command (`checkShutdownRequested`) and on the **`agent_settled`** event. So a stop requested mid-turn lands after the turn finishes, never truncating it.

```
>> {"type":"prompt","message":"/orch-stop"}       # extension command, calls ctx.shutdown()
<< {"type":"response","command":"prompt","success":true}
   $ORCH_DIR/lifecycle.jsonl:
   {"kind":"stop_requested",   "ts":"2026-09-19T13:27:41.367Z"}
   {"kind":"session_shutdown", "ts":"2026-09-19T13:27:41.367Z"}       # VERIFIED, process exited
```

**2. Close stdin.** VERIFIED: `process.stdin.on("end", …)` → immediate `shutdown()`, `session_shutdown` fires, exit 0. ⚠ It does **not** drain in-flight async commands — a `bash` issued just before EOF produced no response and no session entry. Use it only when you know the session is idle.

**3. `SIGTERM`.** Source-verified in both `print-mode.ts:50-65` and `rpc-mode.ts:365-378`: handlers registered for `SIGTERM` and (non-Windows) `SIGHUP`; each calls `killTrackedDetachedChildren()` then `shutdown(143)` / `shutdown(129)`. **`SIGINT` is not handled in print/json mode.** ⚠ And `shutdown()` **skips `flushRawStdout()` when the signal is SIGTERM** (`rpc-mode.ts:741`) — so a SIGTERM stop can truncate the tail of the event stream. The session file is unaffected (synchronous appends).

**Corollary: verify a stop from the file, not the stream.**

```bash
# clean stop sequence
send '{"type":"abort"}'              # blocks until idle — its response IS the quiescence proof
send '{"type":"prompt","message":"/orch-stop"}'
for i in $(seq 1 30); do kill -0 "$PID" 2>/dev/null || break; sleep 1; done
kill -TERM "$PID" 2>/dev/null        # escalate
sleep 3
kill -KILL "$PID" 2>/dev/null        # last resort — the session file is still valid JSONL
tmux kill-session -t "pi-$TASK" 2>/dev/null

# verify nothing is left
pgrep -fl "pi-coding-agent"; tmux ls 2>/dev/null | grep "^pi-$TASK"
tail -1 "$SFILE" | python3 -c 'import json,sys; json.loads(sys.stdin.read()); print("transcript intact")'
rm -f "$ORCH_DIR/$SID.lock"
```

`abort_bash` stops a running shell command without ending the session — VERIFIED: `{"success":true}`, and the bash command's own response came back `{"success":true,"data":{"output":"","cancelled":true}}`. Again: **branch on `cancelled`, not on `success`.**

---

## 12. The one artefact this all depends on — the sidecar extension

Every fallback above (context without RPC, quota headers, nudge acks, the policy gate, the graceful stop) is one ~90-line TypeScript file. **It was written and run on this machine**; the log excerpts in §5, §8, §9 and §11 are its real output.

`$ORCH_ROOT/ext/orch.ts`, loaded with `-ne -e "$ORCH_ROOT/ext/orch.ts"` (pins exactly the orchestrator's extension set and ignores whatever the owner has installed):

```ts
import { appendFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function orch(pi: ExtensionAPI) {
  const dir = process.env.ORCH_DIR; if (!dir) return;
  mkdirSync(dir, { recursive: true });
  const w = (f: string, o: unknown) => {
    try { appendFileSync(join(dir, f), JSON.stringify({ ts: new Date().toISOString(), ...(o as object) }) + "\n"); } catch {}
  };

  // E — raw rate-limit headers, every response, before the body is consumed
  pi.on("after_provider_response", e => w("ratelimit.jsonl", { status: e.status, headers: e.headers }));

  // D + liveness — context %, idle, sampled on a timer, readable from disk in ANY mode
  let timer: ReturnType<typeof setInterval> | undefined;
  pi.on("session_start", (_e, ctx) => {
    w("lifecycle.jsonl", { kind: "session_start", cwd: ctx.cwd, trusted: ctx.isProjectTrusted() });
    timer = setInterval(() => {
      const u = ctx.getContextUsage();
      w("heartbeat.jsonl", { idle: ctx.isIdle(), pending: ctx.hasPendingMessages(),
        contextTokens: u?.tokens ?? null, contextWindow: u?.contextWindow ?? null, contextPercent: u?.percent ?? null });
    }, 5000);
    (timer as any).unref?.();
  });
  pi.on("session_before_compact", e => { w("lifecycle.jsonl", { kind: "before_compact", reason: e.reason }); return undefined; });
  pi.on("session_shutdown", () => { if (timer) clearInterval(timer); w("lifecycle.jsonl", { kind: "session_shutdown" }); });

  // G — ack EVERY inbound instruction, including tmux keystrokes
  pi.on("input", async e => { w("inbox.jsonl", { source: e.source, streamingBehavior: e.streamingBehavior ?? null, text: e.text }); return { action: "continue" }; });

  // H — policy gate; supervisor answers via extension_ui_response, timeout denies
  const dangerous = [/\brm\s+(-rf?|--recursive)/i, /\bsudo\b/i, /\bgit\s+push\b/i, /\b(chmod|chown)\b.*777/i];
  pi.on("tool_call", async (e, ctx) => {
    if (e.toolName !== "bash") return undefined;
    const command = String((e.input as any).command ?? "");
    if (!dangerous.some(p => p.test(command))) return undefined;
    w("lifecycle.jsonl", { kind: "gate_ask", command });
    if (!ctx.hasUI) return { block: true, reason: "orch: no UI to confirm" };
    const choice = await ctx.ui.select(`orch-gate: allow?\n\n${command}`, ["allow", "deny"], { timeout: 30000 } as any);
    w("lifecycle.jsonl", { kind: "gate_answer", command, choice: choice ?? null });
    return choice === "allow" ? undefined : { block: true, reason: "orch: denied" };
  });

  pi.registerCommand("orch-probe", { description: "Supervisor round-trip probe",
    handler: async (_a, ctx) => { const v = await ctx.ui.select("orch-probe: pick one", ["ping","pong"], { timeout: 15000 } as any);
                                  w("lifecycle.jsonl", { kind: "probe_answer", value: v ?? null }); ctx.ui.notify(`orch-probe got: ${v}`, "info"); } });

  pi.registerCommand("orch-stop", { description: "Graceful shutdown at next settle",
    handler: async (_a, ctx) => { w("lifecycle.jsonl", { kind: "stop_requested" }); ctx.shutdown(); } });
}
```

Real output captured during this spike:
```jsonc
// lifecycle.jsonl
{"ts":"…T13:26:13.665Z","kind":"session_start","cwd":"…/spike/work","trusted":true}
{"ts":"…T13:26:17.113Z","kind":"probe_answer","value":"ping"}
{"ts":"…T13:27:41.367Z","kind":"stop_requested"}
{"ts":"…T13:27:41.367Z","kind":"session_shutdown"}
// heartbeat.jsonl  (no model configured -> nulls, NOT zeros)
{"ts":"…T13:26:18.668Z","idle":true,"pending":false,"contextTokens":null,"contextWindow":null,"contextPercent":null}
// inbox.jsonl
{"ts":"…T13:29:48.372Z","source":"rpc","streamingBehavior":null,"text":"instruction-from-supervisor"}
{"ts":"…T13:30:00.769Z","source":"interactive","streamingBehavior":null,"text":"nudge-from-tmux"}
```

**Not verified:** `after_provider_response` never fired here (no live request was made), so whether Anthropic / Xiaomi SGP / Kimi / GLM expose usable rate-limit headers through it is **UNKNOWN**. That is the single highest-value follow-up experiment: one cheap live request per provider.

---

## 13. Guardrails to set before this runs unattended on a real repo

`docs/security.md`, verbatim: *"**No Built-in Sandbox.** Pi does not include a built-in sandbox. Built-in tools can read files, write files, edit files, and run shell commands with the permissions of the pi process. Extensions are TypeScript modules that run with the same permissions."* `README.md:503`: *"**No permission popups.** Run in a container, or build your own confirmation flow with extensions."*

There is no `--dangerously-skip-permissions` because there is nothing to skip. **Unattended pi on a real source tree, with no extension and no container, is a shell with a language model attached.**

What actually exists, in the order the orchestrator should apply it:

```bash
# 1. strict allowlist — the real guardrail (VERIFIED in --help)
--tools read,grep,find,ls                       # genuinely read-only run
--tools read,grep,find,ls,edit,write,bash       # normal work
--exclude-tools bash                            # denylist form
--no-builtin-tools | --no-tools                 # drop built-ins / everything
# settings.json: { "defaultTools": ["read","edit","write","bash"] }   ([] = no built-ins)
```

```json
// 2. $PI_CODING_AGENT_DIR/settings.json — pin everything the orchestrator depends on
{
  "defaultProjectTrust": "never",
  "quietStartup": true,
  "defaultTools": ["read", "grep", "find", "ls", "edit", "write", "bash"],
  "compaction": { "enabled": true, "reserveTokens": 16384, "keepRecentTokens": 20000 },
  "retry": { "enabled": true, "maxRetries": 3, "baseDelayMs": 2000,
             "provider": { "maxRetries": 0, "maxRetryDelayMs": 60000 } },
  "warnings": { "anthropicExtraUsage": true }
}
```

3. **Project trust.** Governs whether `.pi/settings.json`, `.pi/extensions|skills|prompts|themes`, `.pi/SYSTEM.md` and project `.agents/skills` load. Decisions are saved by canonical directory in `$PI_CODING_AGENT_DIR/trust.json` (lock-protected). Global fallback `defaultProjectTrust ∈ "ask"(default)|"always"|"never"`. **The unattended semantics are exactly right** (`docs/security.md`, VERIFIED): *"Non-interactive modes (`-p`, `--mode json`, and `--mode rpc`) do not show a trust prompt."* With no saved decision, `ask` and `never` **ignore** project resources; `always` trusts them. So an unattended run can never hang on a trust dialog — it silently **under-loads** instead. Detect that: `ctx.isProjectTrusted()` (the sidecar logs it — VERIFIED `trusted: true` for a directory with no `.pi`), or diff `get_commands` against what you expected.
   The doc is careful about what trust is *not*: *"It does not make untrusted code, untrusted prompts, or untrusted model output safe. Prompt injection from repository files … is expected local-agent risk and cannot be reliably prevented by pi."*

4. **The `tool_call` gate** in §12 — deny-by-default when `!ctx.hasUI`, escalate to the supervisor when it can.

5. **Real isolation, if wanted (all CLAIMED, none tested here):** `docs/containerization.md` documents four patterns — **Gondolin** (host pi, built-in tools routed into a local Linux micro-VM; needs Node ≥ 23.6 + QEMU), plain **Docker** (keys enter the container), **NVIDIA OpenShell**, and **Docker Sandboxes** (`sbx exec <name> -- pi -p "list the failing tests"`, credential kept on the host and substituted by an egress proxy).

**Extensibility, briefly, because it changes what the orchestrator must port.** **No MCP, by design** (`docs/usage.md:309`, `README.md:499`) — every MCP server the owner leans on (`slack-user`, `n8n-mcp`, `sentry`, `clickup`, `figma`, Playwright) is unreachable without an MCP-bridge extension nobody has written, or CLI equivalents wrapped as skills. The offset is large: **skills port for free.** `docs/skills.md` has a section headed *"Using Skills from Other Harnesses"* whose example is literally `{"skills": ["~/.claude/skills", "~/.codex/skills"]}`, and pi relaxes the spec's name-must-match-directory rule *"for shared skill directories used across multiple agent harnesses."* `CLAUDE.md` is read as a context file alongside `AGENTS.md`. Sub-agents are not built in; `examples/extensions/subagent/` is a complete worked implementation that spawns sibling `pi` processes — architecturally the same thing the orchestrator already does with terminals, so a GSD-shaped workflow is a fit, but every agent definition, dispatch rule and result merge is the orchestrator's code to own (**UNKNOWN** whether it scales to GSD).

---

## 14. Adapter interface

```ts
interface PlatformAdapter {
  preflight(account): Promise<{ready: boolean, fingerprint: string, models: Model[]}>;
  launchHeadless(task, account): Promise<Handle>;
  launchVisible(task, account): Promise<Handle>;
  status(handle): Promise<"alive"|"working"|"waiting"|"blocked"|"finished"|"dead">;
  readContext(handle): Promise<{tokens, window, percent} | "unknown">;
  compact(handle, instructions?): Promise<CompactionProof>;
  readQuota(account): Promise<Quota | "unavailable">;
  switchAccount(task, account): Promise<void>;
  send(handle, text, mode): Promise<Ack>;
  answer(handle, requestId, value): Promise<void>;
  resume(task): Promise<Handle>;
  stop(handle): Promise<void>;
}
```

| # | Capability | pi | How |
|---|---|---|---|
| 1 | Preflight / identify account | **native** | `pi auth check --provider X --json` + `pi auth print-api-key \| shasum` fingerprint + `pi --list-models X`. Caveat: offline check — "ready" ≠ "works". |
| 2 | Headless + pinned id + structured out | **native + one emulation** | `--mode rpc` / `--mode json` with `--session <id>`. **Emulation required:** pre-seed the header line (§2a), or the startup window leaves no trace. **Adapter must ignore the exit code in `--mode json`.** |
| 3 | Visible terminal | **native** | TUI in tmux; `--name` → `#{pane_title}`. **Mutually exclusive with 5/8/9-native.** |
| 4 | Liveness from outside | **native (RPC) / emulated (TUI)** | `get_state` + `get_entries{since}` cursor; TUI needs process + file mtime + sidecar. |
| 5 | Read context | **native (RPC)** | `get_session_stats.contextUsage`; sidecar `ctx.getContextUsage()` elsewhere. Missing ≠ zero; null after compaction. |
| 5b | Force compaction + proof | **native** | `{"type":"compact"}` → response receipt + `compaction_start/end` + a durable `{"type":"compaction",…,"fromHook"}` entry in the JSONL. Best of any platform in this scan. |
| 6 | **Read remaining quota** | **IMPOSSIBLE** | No endpoint, no subcommand, no window model, no concept. Best available: `after_provider_response` header logging (per-provider, **UNKNOWN** availability) + a regex on English prose. |
| 6b | Detect a limit hit in-band | **emulated** | `stopReason:"error"` + `errorMessage` regex; `auto_retry_*` events; status 429 in the sidecar. |
| 6c | Reset time | **emulated, lossy** | Parsed from the provider then flattened to a sentence — recoverable only by regex, ChatGPT/Codex only. |
| 7 | Switch a NEW session's account | **native** | `PI_CODING_AGENT_DIR` per account; `auth.json` with `!command` keys reads the Keychain directly. ⚠ auth.json silently beats env vars. |
| 7b | Switch a RUNNING session's account | **IMPOSSIBLE** | No RPC command exists; shell keys cached for process lifetime. Emulate: abort → exit → relaunch, same cwd. |
| 8 | Deliver an instruction + confirm | **native (RPC), emulated (TUI)** | `prompt`/`steer`/`follow_up` + id-correlated response + `queue_update` + `clear_queue` returns stranded text. TUI: `send-keys` + `input`-hook ack file. **Reference implementation for this axis.** |
| 9 | Answer a question without a human | **native (RPC)** | `extension_ui_request` / `extension_ui_response`, with agent-side timeouts. TUI fallback is keystroke-position-dependent and racy. |
| 10 | Resume after crash / reboot | **native + discipline** | `--session <path>` from a byte-identical cwd. ⚠ `--session-id` silently forks; no lockfile on session files; **no `pi sessions` subcommand — the adapter owns listing.** |
| 11 | Stop cleanly | **native** | `abort` → `/orch-stop` (`ctx.shutdown()`, deferred to `agent_settled`) → SIGTERM(143) → SIGKILL. ⚠ SIGTERM skips the stdout flush; verify from the file. |

**Emulation cost, ordered:** the sidecar extension (~90 lines, written and proven here) unlocks 4-TUI, 5-nonRPC, 6b, 8-TUI, 9-policy and 11-graceful at once. The pre-seed is one line. Session listing is ~20 lines of `ls` + header parse. A per-provider quota strategy is unbounded and not portable.

---

## 15. Support tier

### **Tier 2 — workable with emulation. Executor-grade today; supervisable only because you write the sidecar.**

**Why not tier 1.** One core axis is architecturally impossible: **quota (E) cannot be read.** There is no endpoint, no subcommand, no window model — not a gap, a design position, because pi owns no account. An unattended queue on pi cannot pace itself; it can only run until a 429 and then parse an English sentence for a reset time. On a Claude subscription it additionally bills **per token as extra usage**, so "run until the limit" has no natural stopping point — it just costs money. Two further impossibilities: **no account switch on a live session**, and **no attach-and-type on a supervised session**.

**Why not tier 3.** Everything else is not merely present but *best in this field scan*. `--session-id` names a session **before it exists**, deleting the id-scraping problem. RPC answers "send an instruction and know it arrived" with id-correlated responses, named queues, unsolicited `queue_update` echoes, and a `clear_queue` that hands stranded text **back**. `get_session_stats` answers "how full is the context" with the exact number the compactor acts on, and `compact` leaves proof in three places, one durable on disk. `get_entries{since}` is a real durable cursor over an append-only tree. `extension_ui_request` makes questions programmatically answerable with agent-side timeouts. `ctx.shutdown()` is a graceful stop deferred to the next settle. And the whole transcript format is specified precisely enough to reimplement.

**Can it run overnight unattended today? Yes — with the sidecar, the pre-seed, a container or the tool allowlist, and a spend ceiling instead of a quota budget.**

**The three things that will actually break a run, ranked:**
1. ⚠ **`--mode json` exits 0 on provider failure** (source-verified). An adapter that trusts the exit code will mark failed tasks complete and move on. *This is the FIELD-NOTES "reports success and does nothing" class, alive in pi.* Parse `stopReason`.
2. ⚠ **No quota read + per-token billing on Anthropic.** Run pi on token-plan providers (the owner's Xiaomi MiMo SGP credential is a native pi provider) and cap by accumulated `get_session_stats.cost`.
3. ⚠ **`--session-id` from a drifted cwd silently amputates the transcript**, and the stderr warning does *not* distinguish that from a normal first create. Resume by **path**, assert the header `cwd`, hold a `flock`.

**Recommended posture.** Adopt pi as a **tier-2 executor on per-token providers**, behind the sidecar extension and the pre-seed. And read its RPC protocol regardless of that decision: it is the reference design for the two axes the current harness fails at — confirmed instruction delivery and provable context management — and it is MIT-licensed, so it can be copied.

---

## 16. Verification ledger

**Executed on this machine, 2026-09-19, pi 0.85.1, sandboxed config + session dirs, private tmux socket, no owner config written, no LLM token billed:**
`pi --version` · `pi --help` · `pi auth --help` · `pi auth check` (ready / not_ready / provider_not_found / broken-`!`command / no-provider-exit-0 / rejects-`--api-key`-exit-2) · `pi auth print-api-key` + shasum fingerprints across two isolated `PI_CODING_AGENT_DIR`s · `pi --list-models` (all / xiaomi / kimi / zai, with and without credentials, with and without `--offline`) · `pi -p` and `pi --mode json -p` with no key, with an invalid key, and with an unknown flag (exit codes captured without a pipe) · `--mode rpc` driven over a protocol-compliant held-open-stdin client: `get_state`, `get_session_stats`, `get_entries`, `get_tree`-shape, `get_commands`, `get_fork_messages`, `get_last_assistant_text`, `bash`, `abort_bash`, `abort`, `steer`, `follow_up`, `clear_queue`, `prompt` (accepted and rejected), `compact` (failure path), `set_auto_compaction`, `set_model` (failure path), `export_html` · a custom extension loaded with `-ne -e` exercising `after_provider_response`, `session_start`, `session_before_compact`, `session_shutdown`, `input`, `tool_call`, `registerCommand`, `ctx.getContextUsage`, `ctx.isIdle`, `ctx.isProjectTrusted`, `ctx.ui.select`, `ctx.ui.notify`, `ctx.shutdown` · full `extension_ui_request`/`extension_ui_response` round trip · pre-seeded-header durability proof (file grew before any assistant message) · `--session` vs `--session-id` resolution, same cwd and different cwd · hand-written session file resume with a survival marker · TUI in tmux: `capture-pane`, `list-panes -F '#{pane_title}'`, `send-keys` text/Enter/Down, dialog answered by keystrokes, `ps` title opacity · node v18.17.1 / v22.18.0 / v24.18.0 · unpacked-tarball failure.

**Shipped TypeScript source read** (recovered from `dist/**/*.js.map` `sourcesContent` — the published package ships full sources):
`src/core/session-manager.ts` (`_persist`, `_setSessionFile`, `newSession`, `getDefaultSessionDirPath`, `sessionCwdMatches`, `list`/`listAll`, `CompactionEntry`, `SessionHeader`) · `src/modes/print-mode.ts` (exit-code branch, signal handlers) · `src/modes/rpc/rpc-mode.ts` (33 command cases, `shutdown`, `shutdownHandler`, stdin-end, signal handlers) · `src/cli/auth-check.ts` (status/reason enums) · `src/utils/paths.ts` (`resolvePath`, `normalizePath`) · minified `dist/bundle/chunks/*` for provider base URLs, `usage_limit_reached`/`resets_at`, and exhaustive quota greps.

**Shipped docs read:** `rpc.md` (1618 lines, in full for commands/events/extension-UI) · `extensions.md` §Events §ExtensionContext §ExtensionAPI · `settings.md` · `providers.md` · `security.md` · `session-format.md` · `compaction.md` · `environment-variables.md` · `skills.md` · `containerization.md` · `tmux.md` · `usage.md`.

**Not verified / open, in priority order:**
1. Whether `after_provider_response` exposes usable rate-limit headers for **Anthropic / Xiaomi MiMo SGP / Kimi / GLM** — needs one live request per provider. This is the highest-value follow-up; it decides whether §6a is real or decorative.
2. Whether the owner's existing MiMo SGP token authenticates pi's built-in `xiaomi-token-plan-sgp` provider (`openai-completions` at `/v1`) as well as it does the Anthropic-Messages route Claude Code uses. One cheap request.
3. A real compaction end-to-end (needs a credential and a large context) — shapes are source- and doc-verified, the run is not.
4. All four containerization patterns — **CLAIMED**, documented, untested.
5. Whether `examples/extensions/subagent/` scales to a GSD-shaped workflow.
6. `--mode rpc` behaviour under a real provider outage mid-turn.
7. Version drift: 0.85.1 is a `0.x` on a roughly weekly cadence (45 releases since 2026-05-07). **Pin the version, disable `pi update --self`, and re-run this ledger on every upgrade.** `piConfig` in `package.json` even lets a fork change `name`/`configDir`/`bin`, so `~/.pi` itself is configurable — extensions should use the exported `CONFIG_DIR_NAME`.
