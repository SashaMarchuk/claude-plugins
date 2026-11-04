# Cursor CLI (`cursor-agent`) — orchestrator adapter SPIKE

**Date:** 2026-09-19. **Machine:** owner's Mac, darwin 25.5.0, zsh.
**Companion to:** `cursor-cli.md` (the capability profile — read that first; this file does not repeat it).
**Scope:** the concrete recipe an implementer follows to make Cursor CLI a citizen of the
provider-agnostic orchestrator. Commands, paths, payloads, exit codes.

**Evidence tags:** **VERIFIED** — run on this machine, or read as an exact flag/string in the
installed binary's own source. **CLAIMED** — docs/changelog only. **UNKNOWN** — not established.

---

## 0. The gate that decides everything

```
installed here : 2025.09.12-4852336   (~/.local/share/cursor-agent/versions/…)   VERIFIED
current release: 2026.09.18-9a7762b   (fetched from https://cursor.com/install)  VERIFIED
gap            : 372 days
auth           : Not logged in, no keychain entry                                 VERIFIED
```

I grepped **every** `.js` in the installed bundle for the surfaces the profile's recipes depend on:

| Surface | Present in installed 2025.09.12 build? |
|---|---|
| `statusLine` (context-window feed) | **ABSENT** — VERIFIED, zero hits in any bundle file |
| `hooks.json`, `preCompact`, `beforeShellExecution` | **ABSENT** — VERIFIED, zero hits |
| `approvalMode` | **ABSENT** — VERIFIED, zero hits |
| `used_percentage` | **ABSENT** — VERIFIED, zero hits |
| `acp`, `persist`, `plugin`, `sandbox` subcommands | **ABSENT** — VERIFIED, `help <cmd>` falls through to root help |
| `worker` subcommand (hidden) | **PRESENT** — VERIFIED, `worker ping` → `pong` |

So: **axes D, G-via-hooks, and H are not merely unverified here — they do not exist in this build.**
Everything below is split into *works on the installed build* (fully verified) and *requires the
upgrade* (flag surface from docs, must be re-verified after install).

**Do the upgrade first, pinned:**

```bash
# VERIFIED: read out of the live installer script, not executed
VER=2026.09.18-9a7762b
OS=darwin ARCH=arm64   # or x64
curl -fSL "https://downloads.cursor.com/lab/${VER}/${OS}/${ARCH}/agent-cli-package.tar.gz" \
  -o /tmp/agent.tgz
mkdir -p "$HOME/.local/share/cursor-agent/versions/${VER}"
tar -xzf /tmp/agent.tgz -C "$HOME/.local/share/cursor-agent/versions/${VER}" --strip-components=1
# the official installer does `rm -f` then symlinks BOTH names:
ln -sfn "$HOME/.local/share/cursor-agent/versions/${VER}/cursor-agent" "$HOME/.local/bin/agent"
ln -sfn "$HOME/.local/share/cursor-agent/versions/${VER}/cursor-agent" "$HOME/.local/bin/cursor-agent"
```

> The fleet must **not** resolve through `~/.local/bin`. The installer replaces those symlinks in
> place (VERIFIED, lines 128–131 of the installer), so an auto-update or a manual reinstall
> re-points every running session's launcher mid-flight. Pin the absolute versioned path:
> `CURSOR_BIN="$HOME/.local/share/cursor-agent/versions/${VER}/cursor-agent"`.
> On this machine only `cursor-agent` exists — `~/.local/bin/agent` is **absent** (VERIFIED),
> because the install predates the rename. Call `cursor-agent`, never `agent`.

### Filesystem map (VERIFIED — read in `index-wgf8x11r.js` + `index-cryznx0t.js`, confirmed on disk)

```js
configDir() { CURSOR_CONFIG_DIR || ($XDG_CONFIG_HOME && join($XDG_CONFIG_HOME,"cursor")) || ~/.cursor }
dataDir()   { CURSOR_DATA_DIR   || ~/.cursor }          // NOTE: XDG is NOT honoured for data
projects()  = join(dataDir(), "projects")
slug(p)     = p.replace(/[^a-zA-Z0-9]/g,"-").replace(/-+/g,"-").replace(/^-+|-+$/g,"")
projectDir(p)= join(projects(), slug(p))                 // worker.sock, worker.log live here
cliConfig() = join(configDir(), "cli-config.json")
chatsDir()  = join(configDir(), "chats", md5(process.cwd()))   // <- chats are LOCAL, cwd-scoped
```

**This corrects the profile.** The profile looked in `projects/`, found no chats, and concluded
conversation state is server-side. It is not: `create-chat`'s own source builds
`join(chatsDir(), randomUUID(), "store.db")` — a local SQLite file, keyed by the **md5 of the
working directory**. Consequence for the orchestrator: **a ticket's session is only resumable from
the same `cwd`**, unless the current build's cross-workspace resume changes that.

---

## Recipe 1 — Preflight: installed, authenticated, which account? · **verified: true**

Three independent checks. Run them in this order; each one's failure is distinguishable.

```bash
CURSOR_BIN="$HOME/.local/share/cursor-agent/versions/2026.09.18-9a7762b/cursor-agent"

# 1a. binary exists + version gate (offline, unauthenticated, cheap)   VERIFIED HERE
"$CURSOR_BIN" --min-version 2026.09.18 create-chat >/dev/null 2>"$ERR"; rc=$?
```

`--min-version` is a **hidden global option**, registered in the installed binary as
*"Minimum version requirement for CLI compatibility, specified as a SemVer string. CLI will exit if
the current version is less than the minimum version."* (VERIFIED, read in `index.js`). Measured
here against the stale build:

| Case | stderr | exit |
|---|---|---|
| too old | `Error: Current CLI version (2025.09.12-4852336) is less than required minimum version (2026.09.18)` | **2** |
| ok | *(none)* — command proceeds | **0** |

**VERIFIED by running both cases.** This is the platform's preflight primitive: offline, free,
unambiguous, and it pins the whole adapter to a flag surface it has been tested against.

```bash
# 1b. authentication — do NOT use `status`                              VERIFIED HERE
```

> **`cursor-agent status` is unusable as a preflight.** On this machine it prints
> `Starting login process…`, then `Not logged in`, **and exits 0** (VERIFIED). On the installed
> build `status --format json` does not exist at all — `error: unknown option '--format'`,
> exit 1 (VERIFIED). `--format text|json` is CLAIMED for the current build only.

Use the credential itself as the check, and prefer an API key because **its failure signature is
clean and the browser-login-missing signature is not**:

```bash
# VERIFIED HERE — bad key: stdout EMPTY, clean stderr, exit 1
CURSOR_API_KEY=crsr_invalid "$CURSOR_BIN" -p --output-format json "hi" 2>err.txt
#   stderr: "⚠ Warning: The provided API key is invalid.
#            The API key was loaded from the CURSOR_API_KEY environment variable.
#            Please check you have the right key, create a new one, or authenticate without it."
#   exit 1
```

versus

```bash
# VERIFIED HERE — NO credential at all: 502 bytes of ANSI login art on STDOUT,
#                 stderr EMPTY, exit 1
"$CURSOR_BIN" -p --output-format json "hi"
#   stdout: "⬢ … Cursor Agent …  Press any key to sign in..."  (box-drawing splash)
```

**This is the single nastiest trap on the platform.** An unauthenticated headless run writes a TUI
splash screen into the *structured output channel* and says nothing on stderr. A supervisor that
pipes stdout to `jq` gets a parse error with no diagnosis. `AGENT_CLI_HIDE_BANNER=true` does **not**
suppress it (VERIFIED — that var only hides the "Welcome to Cursor Agent Beta" box, confirmed at
its call site in `chat-f4pxghr6.js`).

Adapter rule: **if the first byte of stdout is not `{`, treat the run as an auth failure**, regardless
of stderr.

```bash
# 1c. which account?  (network; NOT run here — no key on this machine)   CLAIMED (docs)
curl -fsS https://api.cursor.com/v1/me -H "Authorization: Bearer $CURSOR_API_KEY" | jq .
# -> { "apiKeyName": "...", "userId": "...", "userEmail": "...", "createdAt": "..." }
```

- **Success:** `userEmail` equals the role the orchestrator intended.
- **Failure:** non-2xx, or an email that is not the expected role → refuse to start the ticket.
- **Fallback if `/v1/me` is unavailable:** read `apiKeySource` out of the first `stream-json`
  event once work starts (§2) and abort the run if it is not `"env"`.

---

## Recipe 2 — Headless, pinned session id, structured output · **verified: true**

### Pin the id

```bash
# VERIFIED HERE — ran twice, returned two distinct UUIDv4s, exit 0, OFFLINE, UNAUTHENTICATED
SID="$("$CURSOR_BIN" create-chat | tail -1)"
# e.g. 2589d09c-1309-400a-b8c0-347f88efa44a
```

Its whole implementation (VERIFIED, `create-chat-7vht3w4a.js`, 732 bytes, read in full):

```js
let z = crypto.randomUUID();
let Y = join(chatsDir(), z);
let Z = join(Y, "store.db");
let E = new Database(Z); let F = new Store(E,E);
E.set("agentId", z); print(F.getId()); await F.dispose();
```

> **Measured surprise:** after two `create-chat` runs against an isolated
> `CURSOR_CONFIG_DIR`, **no `chats/` directory and no `store.db` were created** — only
> `cli-config.json` (VERIFIED, `find` over the whole scratch config dir). The id is real; its
> backing store is lazy. So the orchestrator **cannot confirm a pinned id by looking at disk**, and
> `--resume <never-used-id>` behaviour is **UNKNOWN**.
>
> Corollary worth testing on the current build: since the id is just `crypto.randomUUID()`, the
> orchestrator can likely skip the 132 MB process start and generate its own —
> `SID=$(uuidgen | tr 'A-Z' 'a-z')` — then pass it to `--resume`. **Test before relying on it.**

### Run

```bash
cd "$TICKET_WORKTREE"            # MUST match for later resume: chatsDir = md5(cwd)
CURSOR_API_KEY="$ROLE_KEY" \
"$CURSOR_BIN" \
  --min-version 2026.09.18 \
  -p --output-format stream-json \
  --resume "$SID" \
  --force \
  --model "$MODEL" \
  "$(cat "$TICKET_PROMPT")" \
  1> "$RUN/out.ndjson" \
  2> "$RUN/err.txt"
echo $? > "$RUN/exit"
```

- `-p`, `--output-format text|json|stream-json`, `--resume [chatId]`, `-f/--force`, `--model`
  are all **VERIFIED in the installed binary's own `--help`**.
- **`--output-format` defaults to `stream-json` on the installed build** (VERIFIED, help text) while
  the docs say `text`. Always pass it explicitly.
- `--force` is mandatory: without it headless runs *propose* edits and never apply them, which
  looks exactly like success. Same silent-no-op shape the field notes record for the harness merge.

### Event shapes — VERIFIED by reading the emitter in `chat-f4pxghr6.js`, not from docs

```jsonc
{"type":"system","subtype":"init","apiKeySource":"login","cwd":"…","session_id":"…","model":"…","permissionMode":"default"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"…"}]},"session_id":"…"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"…"}]},"session_id":"…"}   // one per text-delta
{"type":"tool_call","subtype":"started","call_id":"…","tool_call":{…},"session_id":"…"}
{"type":"tool_call","subtype":"completed","call_id":"…","tool_call":{…},"session_id":"…"}
{"type":"result","subtype":"success","is_error":false,"duration_ms":N,"duration_api_ms":N,"result":"…","session_id":"…","request_id":"…"}
```

Three things the docs do not tell you, all read in the emitter:

1. **`permissionMode` is the hard-coded string `"default"`.** It does not reflect the real mode.
   Never trust it.
2. `thinking-delta` / `thinking-completed` hit `break` with no write — reasoning is **dropped**, not
   merely hidden.
3. **No token counts anywhere in this build's events.** The changelog's per-turn
   input/output/cache totals are a 2026-02 addition — re-verify after upgrade, because §5 and §6
   both depend on them.

### Failure — VERIFIED, read in the `catch` block of the same emitter

```js
catch (D) { if (D.name === "AbortError") exit(130, "Operation cancelled"); else exit(1, String(D)); }
```

| Exit | Meaning | stdout |
|---|---|---|
| 0 | terminal `result` object emitted | valid NDJSON |
| 1 | any error, message = `String(err)` on **stderr** | **no JSON object at all** |
| 2 | `--min-version` gate | none |
| 130 | aborted / SIGINT — `"Operation cancelled"` | truncated NDJSON |

**Success:** exit 0 **and** a final line with `"type":"result"` and `"is_error":false`.
**Failure:** anything else — and on exit 1 the reason exists **only** in the stderr file, so
capturing stderr is not optional.
**Fallback for a stdout that never produced a `result`:** treat the run as failed and re-dispatch
from the last `tool_call.subtype=="completed"` recorded in `out.ndjson`.

---

## Recipe 3 — Same task in a visible terminal the owner can type into · **verified: true**

Cursor has no `persist`/`attach` on the installed build (VERIFIED absent). Use the owner's existing
launcher pattern (iTerm2-osascript per `~/.claude/shared/tooling.json`) or tmux, and shape the TUI
with env vars **read at their call sites in `chat-f4pxghr6.js`** (all VERIFIED):

| Env var | Exact semantics as implemented |
|---|---|
| `AGENT_CLI_EXIT_ON_COMPLETION=true` | on turn completion: `setTimeout(() => process.exit(0), 10)` |
| `AGENT_CLI_HIDE_BANNER=true` | suppresses the "Welcome to Cursor Agent Beta" box only |
| `AGENT_CLI_HIDE_HEADER=true` | suppresses the header block |
| `AGENT_CLI_HIDE_PROMPT_BAR=true` | hides the prompt bar — **but only while `decisions.length === 0`** |
| `AGENT_CLI_HIDE_USER_MESSAGES=true` | user-message cells render `null` |
| `AGENT_CLI_LOAD_HISTORY=false` | skips `getFullConversation()` on resume — start clean on a known id |

`AGENT_CLI_EXIT_ON_COMPLETION` is the important one: it converts an attachable TUI session into a
process whose **exit is the completion signal**, which is what §4 needs. And the prompt-bar rule is
a free intervention signal — the bar reappears exactly when a decision is pending.

```bash
tmux new-session -d -s "cursor-$TICKET" -c "$TICKET_WORKTREE" \
  "CURSOR_API_KEY='$ROLE_KEY' \
   AGENT_CLI_EXIT_ON_COMPLETION=true AGENT_CLI_HIDE_BANNER=true \
   '$CURSOR_BIN' --debug --resume '$SID' --model '$MODEL' \
   2>&1 | tee '$RUN/tui.log'"

tmux list-panes -t "cursor-$TICKET" -F '#{pane_pid} #{pane_dead}'   # liveness
tmux send-keys  -t "cursor-$TICKET" 'stop and summarise' Enter      # the owner, or §8
```

- **Success:** `tmux has-session -t cursor-$TICKET` is 0 and the owner can `tmux attach`.
- **Failure:** session dies immediately → the ANSI login splash in `tui.log` means auth (§1b).
- **Fallback:** `script -q "$RUN/tui.log" "$CURSOR_BIN" …` gives a pty without tmux, at the cost of
  losing `send-keys`.

Add `--debug` — recipe 4 depends on it.

---

## Recipe 4 — Alive / working / waiting / finished, from outside · **verified: true**

Four independent signals. The adapter should require **two** to agree before declaring a state.

### 4a. The debug log server — the strongest signal on a build with no hooks

`--debug` is a hidden global option: *"Enable debug mode with local log server"* (VERIFIED, read in
`index.js`). Its implementation (VERIFIED, read in full in `debug-vzzrycxy.js`):

- creates `mkdtemp(os.tmpdir() + "/cursor-agent-debug-")`, writes `session.log` inside it;
- binds an HTTP server on **127.0.0.1**, port `CURSOR_AGENT_DEBUG_PORT` or **43111**, incrementing
  on `EADDRINUSE` up to **50** times, then falling back to an ephemeral port;
- **first line of `session.log` is JSON**:
  `{"event":"debug-session-start","port":N,"basePort":43111,"attempts":N,"ephemeralFallback":false,"directory":"…","logFile":"…","pid":N,"startTime":"…"}`
- routes: `GET /` → HTML viewer · `GET /log` → `text/plain` whole log ·
  **`GET /events` → `text/event-stream`, one `data: <json>` frame per appended line.**

```bash
# assign the port per session so discovery is deterministic
CURSOR_AGENT_DEBUG_PORT=$((43200 + SLOT)) "$CURSOR_BIN" --debug … &

P=$((43200 + SLOT))
curl -s --max-time 2 "http://127.0.0.1:$P/log" | tail -5          # poll
curl -sN --max-time 0 "http://127.0.0.1:$P/events"                # live SSE feed
```

- **Alive:** `/log` answers 200.
- **Finished:** with `AGENT_CLI_EXIT_ON_COMPLETION=true`, the process exits and the port closes.
- **Dead:** connection refused while the PID from line 1 is gone.
- **Fallback:** the `logFile` path in that first line is a plain file — `tail -F` it.

### 4b. The local worker socket — VERIFIED by curl on this machine

The hidden `worker` subcommand (`ping | kill | sleep`) fronts an HTTP server on a **UNIX domain
socket**. Path and routes read in `index-20sqary7.js`, then exercised:

```bash
SOCK="$HOME/.cursor/projects/$(slug "$PWD")/worker.sock"
curl -s --max-time 5 --unix-socket "$SOCK" http://localhost/ping
# -> {"pong":"pong"}                                   VERIFIED HERE
curl -s --max-time 5 --unix-socket "$SOCK" http://localhost/nope
# -> {"error":"Cannot GET /nope"}  HTTP 404            VERIFIED HERE
```

Full route table (VERIFIED, read in source): `GET /ping`, `GET /getIndexingStatus`,
`GET /getRepositoryInfo`, `POST /openFile`, `POST /sleep`, `POST /getDiagnostics`,
`POST /decryptPath`, `POST /kill`. Server constant `INACTIVITY_TIMEOUT = 1_800_000` — **the worker
self-exits after 30 idle minutes**, resetting on every request.

Three traps, all measured here:

1. **`cursor-agent worker ping` is not read-only.** It *spawns* the worker if absent, and the worker
   immediately starts indexing the workspace. `worker.log` in the same directory recorded
   `[info] runServer` / `[info] Indexing now` / `[error] Indexing failed … No access token found`
   (VERIFIED — read the file). Prefer `curl --unix-socket` so a health check never starts anything.
2. **`GET /getIndexingStatus` hangs forever when unauthenticated** (VERIFIED — a curl with no
   timeout had to be killed). Always pass `--max-time`.
3. The spawned worker sat at **100 % CPU for its whole life** (VERIFIED, `ps`). Budget for it.

### 4c. Process + exit file

```bash
kill -0 "$PID" 2>/dev/null        # alive
[ -f "$RUN/exit" ]                # finished; content is the code from §2's table
```

### 4d. NDJSON staleness → "working" vs "waiting"

```bash
now=$(date +%s); mt=$(stat -f %m "$RUN/out.ndjson")
(( now - mt > 600 )) && echo STALLED
tail -1 "$RUN/out.ndjson" | jq -r '.type + "/" + (.subtype // "-")'
```

`tool_call/started` with no matching `completed` for the same `call_id` = **working or blocked on a
tool**. `result` = finished. Nothing at all for minutes with the process alive = **stalled** —
Cursor has no in-band "waiting for you" event outside ACP, so this heuristic *is* the answer, and it
is why an external liveness timeout is mandatory.

---

## Recipe 5 — Read context fullness, force compaction, prove it · **verified: false**

**Not possible on the installed build at all** — `statusLine`, `used_percentage`, `context_window`
and `preCompact` return zero hits across the entire bundle (VERIFIED by grep).

After the upgrade, the read half works and the trigger half does not.

### 5a. Read (CLAIMED — schema read on disk in `~/.cursor/skills-cursor/statusline/SKILL.md`)

```bash
cat > ~/.cursor/statusline-probe.sh <<'SH'
#!/bin/sh
payload=$(cat)
sid=$(printf '%s' "$payload" | jq -r '.session_id // "unknown"')
printf '%s' "$payload" > "/tmp/cursor-ctx-$sid.json"
printf '%s' "$payload" | jq -r '"ctx " + ((.context_window.used_percentage // 0)|tostring) + "%"'
SH
chmod +x ~/.cursor/statusline-probe.sh
```

```jsonc
// add to cli-config.json — NEVER hand-edit the owner's file; write a role copy (§7)
{ "statusLine": { "type":"command", "command":"~/.cursor/statusline-probe.sh",
                  "updateIntervalMs": 1000, "timeoutMs": 2000 } }
```

Supervisor read: `jq -r '.context_window.used_percentage' /tmp/cursor-ctx-$SID.json`.
The payload also carries `session_id`, `session_name`, **`transcript_path`**, `model.display_name`
and `worktree` — so this is *also* how the adapter discovers the transcript path instead of guessing
it. `used_percentage` is **null early in the session** — treat null as 0, never as 100.

### 5b. Trigger — **impossible**

`/summarize` (aliases `/compress`, `/compact`) is an interactive slash command only. There is no
`--summarize`, no `agent compact`, no SDK method. `preCompact` is documented as observational and
cannot modify behaviour. **I will not invent a flag.**

### 5c. The design that actually works: threshold → handoff

```bash
PCT=$(jq -r '.context_window.used_percentage // 0' "/tmp/cursor-ctx-$SID.json")
if awk "BEGIN{exit !($PCT > 75)}"; then
  # 1. ask the dying session to write its own handoff
  #    (delivered by whichever channel §8 chose)
  # 2. NEW=$("$CURSOR_BIN" create-chat | tail -1)
  # 3. relaunch §2 with --resume "$NEW" and the handoff file as the prompt
  # 4. record ticket -> [SID, NEW, …]   (one-to-many is mandatory)
fi
```

**Proof it happened** — three artefacts, all checkable: the handoff file exists and is non-empty;
`create-chat` returned a new id; the new session's `init` event carries the new `session_id`. That
is stronger proof than a compaction the supervisor merely observed.

**Fallback if statusLine is unavailable (i.e. today):** estimate from `--debug`'s `/log` byte count
or from `wc -c out.ndjson` against a hand-calibrated ceiling. Crude, but it is the only number
available on this build.

---

## Recipe 6 — Quota and reset time · **verified: false**

**There is no way to do this on a personal plan.** Confirmed against the profile's survey; nothing
in the installed binary changes it (no usage/quota strings anywhere in the bundle).

```bash
# Enterprise teams ONLY — 20 req/min, admin key. NOT the owner's situation.
curl -fsS -X POST https://api.cursor.com/teams/spend \
  -H "Authorization: Bearer $CURSOR_ADMIN_KEY" -H 'Content-Type: application/json' -d '{}' \
| jq '.teamMemberSpend[] | {email, spendCents, hardLimitOverrideDollars}'
```

**In-band limit detection — the only thing that works:**

```bash
if [ "$(cat "$RUN/exit")" = "1" ] && \
   grep -qiE 'usage limit exceeded|rate limit exceeded' "$RUN/err.txt"; then
   STATE=quota_exhausted
fi
```

- **Success:** the string appears; the orchestrator now knows it is out.
- **Failure:** exit 1 with some other stderr — a normal error, retry per policy.
- **No reset time is exposed in-band anywhere.** The window is **monthly, tied to the billing
  cycle**, with no rollover — so unlike Claude Code's 5-hour/7-day rolling windows **there is
  nothing to wait out.**

**Fallback — self-metering, and be honest about what it misses:**

```bash
jq -s 'map(select(.type=="result")) | {turns: length, ms: (map(.duration_api_ms)|add)}' \
  "$RUN"/*/out.ndjson
```

Sum `duration_api_ms` (present in this build) or per-turn token totals (2026-02, CLAIMED — re-verify)
against a budget the owner declares by hand. It is blind to his IDE and Cloud Agent usage, which
draw from the same pool.

**Adapter contract:** Cursor is a **run-until-told-to-stop** executor. The pause/resume scheduler is
not applicable; on `quota_exhausted` the adapter stops the queue and notifies the owner.

---

## Recipe 7 — Switch a NEW session to a different account, verified before work · **verified: true**

### The mechanism

```bash
# VERIFIED HERE: config isolation is real — this created a fresh cli-config.json
#                in the scratch dir and left ~/.cursor untouched.
export CURSOR_CONFIG_DIR="$ORCH_HOME/roles/$ROLE/config"
export CURSOR_DATA_DIR="$ORCH_HOME/roles/$ROLE/data"
export CURSOR_API_KEY="$(security find-generic-password -s "orch-cursor-$ROLE" -w)"
```

Per-role `CURSOR_CONFIG_DIR` is worth setting even though credentials do not follow it: the
changelog records `cli-config.json` corruption under concurrent CLI processes, and a fleet is
exactly that shape. It also gives each role its own `chats/` tree.

### Why browser login cannot be used for multi-account — **open question #4 from the profile, now resolved**

The credential-store namespace is a **hard-coded literal**, not derived from `CURSOR_CONFIG_DIR`:

```js
// index.js                       (VERIFIED)
let Q = TK("cursor");
// index-20sqary7.js              (VERIFIED)
function zb(b){ let x=b.trim(); return { account:`${x}-user`,
  accessTokenService:`${x}-access-token`, refreshTokenService:`${x}-refresh-token`,
  apiKeyService:`${x}-api-key` }; }
function Jb(b){ if (platform()==="darwin") return new Keychain(b); return new FileStore(b); }
```

So on macOS the services are exactly `cursor-access-token`, `cursor-refresh-token`,
`cursor-api-key`, account `cursor-user` — confirmed absent here via
`security find-generic-password -s cursor-access-token` → *"The specified item could not be found"*
(VERIFIED). **Two `CURSOR_CONFIG_DIR`s share one keychain identity.** There is no env override.
A profile switcher solves this for Claude Code by hashing the config dir into the service name; Cursor does not.

**Therefore: API keys are the only multi-account mechanism. Mint one `crsr_…` key per role at
`cursor.com/dashboard/api`.** Note this changes the billing path — on individual plans BYOK requests
do not draw from the subscription pools. That is a decision for the owner, not a default.

### Verify the switch *before* work starts

```bash
# gate 1 — network identity (CLAIMED)
curl -fsS https://api.cursor.com/v1/me -H "Authorization: Bearer $CURSOR_API_KEY" \
  | jq -e --arg e "$EXPECTED_EMAIL" '.userEmail == $e' || exit 1

# gate 2 — what the session actually used (VERIFIED: apiKeySource is emitted in `init`)
head -1 "$RUN/out.ndjson" | jq -e '.apiKeySource == "env"' || abort_run
```

`apiKeySource` is `"env" | "flag" | "login"`. **Abort on `"login"`** — it means the env var was
ignored and the run is on the owner's own subscription. This is a real audit primitive and better
than Claude Code offers.

- **Failure to detect:** bad key → clean stderr, exit 1 (VERIFIED, §1b). Missing key → ANSI splash
  on stdout (VERIFIED). Both are caught before any work.
- **Changing a running session's account: impossible.** No flag, no method. Credentials bind at
  creation. Fallback is §5c's handoff under the other key.

---

## Recipe 8 — Deliver an instruction into a running session, confirm arrival · **verified: false**

Nothing here is runnable on the installed build (no `acp`, no hooks). Ranked by strength:

**8a. ACP — best, and it confirms nothing by itself.** `cursor-agent acp` is a hidden command
speaking newline-delimited JSON-RPC 2.0 over stdio. `session/prompt` injects a turn.
Confirmation is indirect: the following `session/update` notifications reference it.

**8b. SDK `run.steer()` — the only channel in the whole field that reports delivery.**

```typescript
const outcome = await run.steer("Skip the admin routes for now");
// "complete_delivered" -> the running turn took it; do not resend
// "revert_to_followup" -> it did not land; queue via agent.send() after the turn
```

Cloud runs and detached local handles **always** resolve `revert_to_followup`. This directly answers
the field-notes failure "a nudge that cannot submit stranded text".

**8c. `stop` hook + a mailbox file — cheapest, and arrival is observable.**

```json
{ "version": 1, "hooks": { "stop": [ { "type":"command",
  "command":"~/.orch/cursor-followup.sh", "loop_limit": 20 } ] } }
```

```sh
#!/bin/sh
# ~/.orch/cursor-followup.sh — stdin carries {status, loop_count, session_id, …}
sid=$(cat | jq -r .session_id)
box="$ORCH_HOME/mail/$sid.txt"
[ -s "$box" ] || { echo '{}'; exit 0; }
jq -Rs '{followup_message: .}' < "$box"
mv "$box" "$box.delivered.$(date +%s)"
```

**Proof of arrival:** the mailbox file is renamed to `.delivered.*` **and** `loop_count` increments
in the next invocation. Default cap is 5 auto follow-ups; raise with `loop_limit`, `null` removes it.

**8d. Fallback that works today:** `tmux send-keys -t "cursor-$TICKET" '…' Enter` into the §3
session. **Arrival is not confirmed** — this is precisely the stranded-text failure the field notes
already record. Treat as last resort; corroborate by watching `--debug`'s `/events`.

---

## Recipe 9 — Answer a permission prompt or a question without a human · **verified: false**

**9a. The real answer is ACP, and the adapter must answer *everything*.**

```jsonc
// inbound: the agent asks permission
{"jsonrpc":"2.0","id":7,"method":"session/request_permission","params":{…}}
// reply: "allow-once" | "allow-always" | "reject-once"
{"jsonrpc":"2.0","id":7,"result":{"outcome":{"outcome":"selected","optionId":"allow-once"}}}

// inbound: the agent asks a clarifying question — BLOCKING
{"jsonrpc":"2.0","id":8,"method":"cursor/ask_question",
 "params":{"toolCallId":"…","questions":[{"id":"q1","prompt":"…","options":[{"id":"a","label":"…"}]}]}}
{"jsonrpc":"2.0","id":8,"result":{"outcome":{"outcome":"answered",
 "answers":[{"questionId":"q1","selectedOptionIds":["a"]}]}}}

// inbound: plan approval — BLOCKING
{"jsonrpc":"2.0","id":9,"method":"cursor/create_plan","params":{…}}
{"jsonrpc":"2.0","id":9,"result":{"outcome":"accepted"}}
```

Cursor is the **only** platform in this scan that types the *question* as well as the answer.
The documented warning is load-bearing: *"If your client does not answer permission requests, tool
execution can block."* **A default-deny handler for unrecognised `cursor/*` methods is mandatory** —
an unanswered blocking method is an overnight hang.

**9b. Avoid the prompt instead — the posture that works headless.** Configure a role
`cli-config.json` rather than relying on `--force`:

```jsonc
{ "version": 1,
  "approvalMode": "auto-review",
  "sandbox": { "mode": "enabled", "networkAccess": "user_config_only",
               "networkAllowlist": ["api.cursor.com","github.com"] },
  "permissions": {
    "allow": ["Shell(git)","Shell(npm)","Shell(bash)","Read(**)","Write(src/**)"],
    "deny":  ["Read(.env*)","Write(**/*.key)","Shell(curl:*)","Shell(rm:*)","Mcp(*:*)"] } }
```

Deny beats allow. Under `auto-review` a blocked call is **denied, not escalated**, and the agent is
told why and can try another route — the correct unattended behaviour. `--force`/`--yolo` is Run
Everything with no sandbox and no classifier; it is the current default posture and it is wrong for
an overnight fleet.

**9c. Fallback today:** `--force` plus the sandbox, accepting that nothing can be asked. On the
installed build there is no `approvalMode` and no sandbox config, so the only options are `--force`
(everything) or non-`--force` (a run that proposes and applies nothing). **Neither is acceptable for
unattended work — this is the second reason the upgrade is a hard prerequisite.**

---

## Recipe 10 — Resume after a crash, and after a reboot · **verified: false**

```bash
cd "$TICKET_WORKTREE"          # MANDATORY — chatsDir = configDir/chats/md5(cwd)
CURSOR_API_KEY="$ROLE_KEY" "$CURSOR_BIN" \
  -p --output-format stream-json --resume "$SID" --force \
  "Continue. Re-read your last tool output first." \
  1>>"$RUN/out.ndjson" 2>>"$RUN/err.txt"
```

**Why a reboot survives:** state is a local SQLite file at
`$(configDir)/chats/$(md5 of cwd)/$SID/store.db` (VERIFIED in source) — no server round-trip is
needed to find it, contrary to the profile's server-side reading. Persist `{ticket, SID, cwd,
CURSOR_CONFIG_DIR, role, $CURSOR_BIN}` in the orchestrator's own store; those five values are
everything needed to reconstruct the command.

**What does not survive / is unverified:**

- The store is created **lazily** — a crash before the first turn leaves no file (VERIFIED: two
  `create-chat` runs produced no `store.db`). `--resume` on such an id is **UNKNOWN**.
- Resume from a **different cwd** points at a different `md5` bucket. Cross-workspace resume is a
  2026-07 change (CLAIMED) and must be re-verified.
- Inline `mcpServers` are not persisted across resume — pass them again (CLAIMED).
- `agent.model` is `undefined` on resume unless re-passed (CLAIMED) — always re-pass `--model`.
- **There is no machine-readable session list.** `ls` and `resume` are interactive TUI pickers:
  `ls` → `runChat({resume:true})`, `resume` → `runChat({resume:"-1"})` (VERIFIED, read in
  `index.js`). The orchestrator **must** keep its own ticket→session index; it cannot enumerate.
  Cheapest enumeration fallback: `ls -1t "$(configDir)/chats/$(md5 cwd)/"`.

**Verify the resume landed:** the new `init` event's `session_id` equals `$SID`, and
`AGENT_CLI_LOAD_HISTORY` is left unset so prior history is loaded.
**Failure:** a *different* `session_id` in `init` means a fresh chat was silently started — abort
and reconcile, do not let two sessions work the same ticket.

---

## Recipe 11 — Stop cleanly, leave nothing running · **verified: true**

```bash
kill -INT  "$PID"                       # -> exit 130, "Operation cancelled"  (VERIFIED in source)
sleep 5; kill -0 "$PID" 2>/dev/null && kill -TERM "$PID"
sleep 5; kill -0 "$PID" 2>/dev/null && kill -KILL "$PID"
tmux kill-session -t "cursor-$TICKET" 2>/dev/null
```

Then the worker — **and do not believe what it tells you**:

> **VERIFIED, measured here.** `cursor-agent worker kill` printed `Worker server killed`, **exited
> 0**, and **removed `worker.sock`** — while the `worker-server` process kept running at 100 % CPU.
> `ps` showed it alive 15 seconds later, state `Rs`. It took an explicit `SIGTERM` to die.
> The source explains it: `POST /kill` replies 200 first, then `setTimeout(… process.exit(0), 0)` —
> a callback that never runs if the event loop is saturated, which it was. **This is the same
> "reports success and does nothing" shape the field notes record for the harness merge step, and
> it leaves an orphan burning a core all night.**

```bash
"$CURSOR_BIN" worker kill 2>/dev/null || true           # best-effort; DO NOT TRUST exit 0
sleep 2
pgrep -f 'index\.js worker-server' | while read -r wp; do
  kill -TERM "$wp" 2>/dev/null; sleep 2
  kill -0 "$wp" 2>/dev/null && kill -KILL "$wp"
done
rm -f "$HOME/.cursor/projects/$(slug "$PWD")/worker.sock"
```

**Success — assert all four (VERIFIED as the exact checks I used to confirm this machine is clean):**

```bash
pgrep -f 'index\.js worker-server' | wc -l          # -> 0
pgrep -f 'cursor-agent'            | wc -l          # -> 0
test ! -S "$HOME/.cursor/projects/$(slug "$PWD")/worker.sock"
tmux has-session -t "cursor-$TICKET" 2>/dev/null && echo LEAK
```

**Fallback:** the worker self-exits after `INACTIVITY_TIMEOUT = 1_800_000 ms` (30 min, VERIFIED in
source) — but a spinning one may not reach that timer either. Always assert on `pgrep`, never on an
exit code.

---

## The adapter interface

| # | Capability | Native? | Cost / emulation |
|---|---|---|---|
| 1 | Preflight | **native** | `--min-version` (exit 2) + `/v1/me`. **Never `status` — exits 0 unauthenticated.** |
| 2 | Headless + pinned id + structured | **native** | `create-chat` → `-p --output-format stream-json --resume --force`. Capture stderr separately. |
| 3 | Visible attachable terminal | **emulated** | tmux/iTerm2 + `AGENT_CLI_EXIT_ON_COMPLETION=true`. No `persist` on any build I could verify. |
| 4 | Liveness / state | **native** | `--debug` SSE at `/events` + `curl --unix-socket … /ping` + NDJSON staleness. Requires an external timeout. |
| 5 | Read context | **native after upgrade** | statusLine script → `context_window.used_percentage`. Absent on the installed build. |
| 5 | Trigger compaction | **IMPOSSIBLE** | No flag, no subcommand, no RPC. Emulate with threshold → `create-chat` → seeded handoff; ticket→session becomes one-to-many. |
| 6 | Read remaining quota | **IMPOSSIBLE** (personal plan) | Self-meter `duration_api_ms` against a declared budget. Blind to the owner's IDE usage. |
| 6 | Detect limit hit | **emulated** | exit 1 + stderr regex `usage limit exceeded`. **No reset time exists** — monthly billing cycle, nothing to wait out. |
| 7 | Account switch (new session) | **native** | `CURSOR_API_KEY` per role; audit via `apiKeySource=="env"` in `init`. |
| 7 | Multi browser-login on macOS | **IMPOSSIBLE** | Keychain namespace is the hard-coded literal `"cursor"`; `CURSOR_CONFIG_DIR` does not scope it. |
| 7 | Switch a running session | **IMPOSSIBLE** | Credentials bind at creation. Handoff only. |
| 8 | Deliver an instruction | **native** (SDK/ACP) | `run.steer()` is the only delivery-confirming channel in the field. `stop`-hook mailbox is the cheap version. |
| 9 | Answer prompts/questions | **native** (ACP) | `session/request_permission`, `cursor/ask_question`, `cursor/create_plan`. **Must default-deny unknown blocking methods or it hangs.** |
| 10 | Resume after crash/reboot | **native** | Local SQLite, but `cwd`-keyed by md5 and lazily created. **No machine-readable session list** — keep your own index. |
| 11 | Clean stop | **emulated** | `worker kill` lies. `pgrep`-assert every teardown. |

**Best-in-field on 9 (typed questions *and* typed answers) and 8 (delivery confirmation). Worst-in-field
on 6.**

---

## Support tier: **tier-2 — workable with emulation — but only after the upgrade, and never as a scheduler citizen**

- **Not tier-1**, because axis E is a stated non-negotiable and Cursor has no programmatic read of
  remaining capacity on a personal plan, and no reset time even when it fails. The
  read-quota/pause/resume scheduler the owner described cannot drive it.
- **Not tier-3**, because it is far more than an executor: live NDJSON, a debug SSE feed, a unix
  socket health endpoint, local resumable state, per-role API-key isolation with an audit field, and
  the cleanest programmatic answer-the-agent's-question surface that exists anywhere in this scan.
- **Today, on the installed 2025.09.12 build, it is closer to unusable than tier-2**: no statusline,
  no hooks, no `approvalMode`, no sandbox, no ACP — leaving only `--force` (unrestricted) or a run
  that applies nothing. Both are wrong for an overnight fleet.

**Shape the adapter as: a supervised worker with a hand-declared budget, not a scheduled one.**
Give it tickets whose failure mode is "stopped, needs the owner" rather than "paused, will resume".

---

## Residual unknowns (ranked by what they would change)

| # | Question | Blocks | How to settle it |
|---|---|---|---|
| 1 | Does `--resume <uuid>` accept an id `create-chat` never materialised on disk? If yes, drop the subprocess and use `uuidgen`. | 2, 10 | One authenticated run against a self-generated UUIDv4. |
| 2 | Does a slash command sent as programmatic prompt text (`/summarize` via `session/prompt` or a `stop` hook's `followup_message`) execute, or land as literal text? | 5 | One ACP prompt; check for a `SummaryStartedUpdate`. |
| 3 | Is `agent persist attach|list|stop` real? It appears only in the 2026-08-26 changelog, in no reference page. | 3 | `agent persist --help` on the current build. |
| 4 | Does the current build's `stream-json` carry per-turn token totals? §5 and §6 both degrade without them. | 5, 6 | One run; `jq 'keys'` on the `result` event. |
| 5 | Does `agent worker start` (the self-hosted cloud-agent runner with `/healthz`, `/readyz`, `/metrics`) exist, and is it an orchestration surface in its own right? The installed build already ships `worker ping|kill|sleep` over a unix socket. | 1, 4 | `agent worker --help` on the current build. |
| 6 | `mcp list` reported *"No MCP servers configured"* while `~/.cursor/mcp.json` holds six servers under `mcpServers` (VERIFIED here). Version skew, or an approval gate? | 9 | `agent mcp list` on the current build. |
| 7 | Does `--min-version` survive on the current build? The whole preflight rests on it. | 1 | `agent --min-version 9999.1.1 create-chat; echo $?` → expect 2. |

---

## Appendix — everything run on this machine, 2026-09-19

```
cursor-agent --version                          -> 2025.09.12-4852336
cursor-agent --help / help <cmd> x 13           -> flag + command surface
cursor-agent status                             -> "Not logged in", EXIT 0
cursor-agent status --format json               -> unknown option '--format', EXIT 1
cursor-agent --min-version 2026.09.18 create-chat -> EXIT 2 + stderr
cursor-agent --min-version 2025.01.01 create-chat -> EXIT 0 + UUIDv4
cursor-agent create-chat  (x3, isolated cfg)    -> 3 distinct UUIDv4, NO files created
cursor-agent -p --output-format json "hi"       -> 502 B ANSI splash on STDOUT, stderr empty, EXIT 1
CURSOR_API_KEY=crsr_invalid … -p                -> clean stderr, stdout empty, EXIT 1
AGENT_CLI_HIDE_BANNER=true … -p                 -> splash NOT suppressed
cursor-agent worker ping                        -> "pong"; SPAWNED worker-server @100% CPU
curl --unix-socket …/worker.sock /ping          -> {"pong":"pong"}
curl --unix-socket …/worker.sock /nope          -> {"error":"Cannot GET /nope"} 404
curl --unix-socket …/worker.sock /getIndexingStatus -> HUNG (killed at 120 s)
cursor-agent worker kill                        -> "Worker server killed", EXIT 0, socket gone,
                                                   PROCESS STILL ALIVE @100% CPU; SIGTERM required
cat …/projects/<slug>/worker.log                -> runServer / Indexing now / No access token found
cursor-agent mcp list                           -> "No MCP servers configured" (6 are configured)
security find-generic-password -s cursor-access-token -> not found (x3 namespace guesses)
curl https://cursor.com/install                 -> current release 2026.09.18-9a7762b
grep over every bundle .js                      -> statusLine/hooks/preCompact/approvalMode ABSENT
```

**Read in the installed binary** — `index.js` (command + hidden-option registration, `TK("cursor")`),
`index-wgf8x11r.js` (config/data dir, slug), `index-cryznx0t.js` (chats dir = `md5(cwd)`),
`create-chat-7vht3w4a.js` (full, 732 B), `chat-f4pxghr6.js` (stream-json emitter, exit codes,
`AGENT_CLI_*` call sites), `index-20sqary7.js` (worker routes, `INACTIVITY_TIMEOUT`, keychain
namespace derivation), `debug-vzzrycxy.js` (full, 9.8 KB — debug log server).

**State left on this machine:** none. All spawned processes terminated and asserted gone;
`~/.cursor/cli-config.json` unmodified; all probe writes confined to the session scratchpad.
One side effect remains by design: `~/.cursor/projects/Users-sasha-marchuk-Work-claude-plugins/worker.log`,
created by the worker this spike started.
