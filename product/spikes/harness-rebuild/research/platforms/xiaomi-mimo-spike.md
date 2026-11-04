# SPIKE — Xiaomi MiMo (MiMoCode) as a first-class orchestrator citizen

**Date:** 2026-09-19. **Machine:** owner's Mac, darwin 25.5.0, arm64.
**Under test:** `@mimo-ai/cli@0.1.14` (npm, published 2026-09-02), binary `mimo`, repo
`github.com/XiaomiMiMo/MiMo-Code`, MIT. An OpenCode fork.
**Companion:** `xiaomi-mimo.md` (the capability profile). Read that first; this file is the
implementer's recipe book and does not repeat its reasoning. Where the two disagree, this file wins —
every disagreement is listed in §0 with the evidence that overturned it.

**Evidence tags.** **VERIFIED** = I ran it on this machine in this session, or read the exact string
in the installed 0.1.14 binary / its saved route source. **CLAIMED** = vendor text only.
**UNKNOWN** = could not establish.

**How this was verified, and what it cost.** `@mimo-ai/cli@0.1.14` was installed into
`…/scratchpad/mimo-probe` with `MIMOCODE_HOME` pointed at a scratch directory and
`MIMOCODE_DISABLE_CLAUDE_IMPORT=1`. A `mimo serve` was run on `127.0.0.1:47513` with a password and
driven with `curl`. Every HTTP shape below is a real response from that server. Model calls were made
only with a **deliberately invalid API key** (`sk-bogus-…`), which returns 401 before any inference —
**no quota was spent and the owner's own credential was never used.** Nothing in `~/.claude`,
`~/.config` or `~/.zshrc` was modified. Teardown is §11.

> **Prerequisite that blocks everything below.** The owner's stored MiMo credential
> (`~/.config/claude-mimo/env`, a `tp-…` Token Plan key) returned `401 invalid_key` in the profile's
> pass and the endpoint still answers 401 to an invalid key today. **Re-mint a key at
> `platform.xiaomimimo.com` before any of these recipes touch a real model.** Every recipe here was
> therefore verified on its control plane, not on its inference.

**Three things this spike found that no documentation states, and that an implementer will otherwise
lose a night to:**

1. **`mimo run` hangs forever unless you close its stdin** (`< /dev/null`). Deterministic. §11b.
2. **The `serve` Basic-auth username is `mimocode`**, not empty. Every other form 401s. §0.1.
3. **The `.mimocode` Bun child outlives its `node` wrapper.** An orphaned server from the previous
   research pass was still holding a port 16 minutes later. §11a.

---

## 0. Corrections to the profile, with evidence

| # | Profile said | Actually | Evidence |
|---|---|---|---|
| 0.1 | `mimo serve` auth is "Basic auth with `MIMOCODE_SERVER_PASSWORD`" — no username given | Username is **`MIMOCODE_SERVER_USERNAME ?? "mimocode"`**. `curl -u :PASS`, `-u mimo:PASS`, `-u user:PASS` and `Authorization: Bearer` **all 401**. `curl -u mimocode:PASS` → **200** | VERIFIED — live, and the exact expression `process.env.MIMOCODE_SERVER_USERNAME??"mimocode"` read in the 0.1.14 binary |
| 0.2 | Provider/model id is `mimo/mimo-v2.5-pro` | Provider id is **`xiaomi`**. `mimo models` prints `xiaomi/mimo-v2.5`, `xiaomi/mimo-v2.5-pro`, `xiaomi/mimo-v2.5-pro-ultraspeed`, plus a separate `mimo/mimo-auto` router | VERIFIED — `mimo models` on this machine |
| 0.3 | `POST /session/:id/turn/:msgID/resume` "takes optional `agentID`, `modelProviderID`…" (implying a body) | They are **query-string parameters**, not a JSON body. A body is ignored | VERIFIED — `validator("query", …)` in the route source |
| 0.4 | `grep` for `x-ratelimit` over the repo → 0 hits, so nothing reads rate-limit headers | The strings **are** in the shipped binary (`x-ratelimit-limit/-remaining/-reset/-reset-after`) — but they belong to **vendored HTTP-client throttling plugins** (GitHub/REST-style, with `routeInfo`/`redis` keys), not to the model path. MiMoCode's own `decide()` reads only `retry-after-ms`, then `retry-after`, then a regex over the error text. **The conclusion stands; the premise was wrong** | VERIFIED — strings + `retry.ts` lines 262–273 |
| 0.5 | Session ids "are server-minted" (inferred from the schema) | Confirmed by experiment: `POST /session {"id":"ses_orchestrator_pinned_001", …}` returns **200** with a *different*, server-minted id. The field is silently dropped — **it does not error**, so a naive adapter will think it worked | VERIFIED — live |
| 0.6 | Nothing about pinning a *message* id | `PromptInput` accepts an optional **`messageID`**. The orchestrator cannot name the session but **can name the message it injects** — a better correlation handle than the title | VERIFIED — `PromptInput` zod read in the binary |
| 0.7 | `/session/status` shape given loosely as `idle\|busy\|retry\|notice` | Exact union VERIFIED (§4), including `retry.next` as an **absolute ms timestamp** and `scope: "request"\|"live-step"\|"max-candidate"\|"max-judge"` | VERIFIED — schema read in the binary |
| 0.8 | Compaction proof = the `session.time_compacting` column | There is a **second, stronger** proof: `CompactionPart.trigger` is an enum `"manual" \| "automatic" \| "provider-overflow"`. `manual` is exactly "the supervisor did this", distinguishable from the agent compacting on its own | VERIFIED — `CompactionPart` zod read in the binary |
| 0.9 | Unattended risks listed, but not this one | **`mimo run` intermittently never exits** when a `mimo serve` holds the same `MIMOCODE_HOME`. 3 of 4 probes hung past 60–150 s with zero output after a fatal 401; 1 exited in 5 s. See §11 | VERIFIED — live, repeatedly |
| 0.10 | Nothing about process teardown | The `node` wrapper (`node_modules/.bin/mimo`) spawns a Bun child (`bin/.mimocode`). **The child outlives the wrapper.** An orphaned `.mimocode serve --port 47311` from the *previous research pass*, `ppid=1`, was still listening 16 minutes later. `SIGTERM` to the **child** stopped it in ~2 s | VERIFIED — `ps`, `lsof`, `kill -TERM`, port went from 200 to refused |
| 0.13 | Nothing about stdin | **`mimo run` blocks forever on `Bun.stdin.text()` whenever stdin is not a TTY.** Spawned with an inherited pipe it produced **zero output and had to be killed** in 6 of 7 probes; with `< /dev/null` it exited **0 in 5 s** every time. Root cause isolated in this session | VERIFIED — live, deterministic, §11b |
| 0.12 | Nothing about process-level identity | `MIMOCODE_RUN_ID` and `MIMOCODE_PROCESS_ROLE` are assigned with `??=`, so **an orchestrator-supplied value is honoured** and lands in the log filename and every log line. A real identity handle the profile misses entirely | VERIFIED — live, §2e |
| 0.11 | `MIMOCODE_MIMO_ONLY=true` = "master switch: no `.claude` inheritance" | It did **not** drop the owner's `.claude` MCP servers or `.claude/commands` in my A/B test. `mimo debug config` printed the identical 9 MCP servers and the same `command` key with and without the flag. Treat it as **unproven**, not as a boundary | VERIFIED (the negative) — A/B of `mimo debug config` in the owner's repo root |

---

## 1. Preflight — installed, authenticated, which account

### 1a. Is it installed at all — **verified: true**

```bash
command -v mimo || echo "absent"
mimo --version                       # → 0.1.14
```
On this machine, **`mimo` is not installed for the owner** (`which mimo` → not found; no
`~/Library/Application Support/mimocode`). It exists only inside the probe sandbox. An adapter must
treat "MiMo lane" as *opt-in and self-installing*:

```bash
npm i -g @mimo-ai/cli@0.1.14        # PIN the version — 0.1.x, ~weekly releases
```

**Success:** `mimo --version` prints `0.1.14`.
**Failure:** command not found, or a version drift — flags move on a 0.1.x line.
**Fallback:** none. Without the CLI there is no MiMoCode lane; see §K of the profile for the
"MiMo-as-a-model-behind-Claude-Code" route, which needs no install.

### 1b. The mandatory environment block — **verified: true**

Every recipe below assumes this block. It is not optional hardening; four of these prevent
documented data-loss or credential-leak behaviour.

```bash
export MIMOCODE_HOME="$ORCH_STATE/mimo/$ACCOUNT"   # one dir per account; moves data+config+cache+state together
export MIMOCODE_DISABLE_CLAUDE_IMPORT=1            # else first run copies ~/.claude/projects into its own DB
export MIMOCODE_ENABLE_ANALYSIS=false              # telemetry is ON by default
export MIMOCODE_DISABLE_AUTOUPDATE=true            # pin the version you tested
export MIMOCODE_SERVER_PASSWORD="$(openssl rand -hex 24)"
export MIMOCODE_SERVER_USERNAME=mimocode           # explicit; this is the default and curl needs it
```

**Verified:** `mimo debug paths` with `MIMOCODE_HOME` set reported **every** path (data, bin, log,
cache, config, state) under the scratch directory — full isolation, one env var.

**First-run cost, measured:** the first invocation prints
`Performing one time database migration, may take a few minutes…` and then
`sqlite-migration:done`. Here it took seconds, but **a supervisor with a short startup timeout will
kill it mid-migration.** Budget 5 minutes for the first call into a fresh `MIMOCODE_HOME`, or warm it
once at install time with `mimo debug paths`.

### 1c. Which account is active — **verified: true**

```bash
mimo providers list          # prints the auth.json path and one line per credential
mimo providers whoami        # logged-in user info
mimo debug paths             # where that auth.json lives
```

Live output with a credential injected by environment:

```
┌  Credentials  <MIMOCODE_HOME>/data/auth.json
│
●  Xiaomi  api
│
└  1 credentials
```

and with none: `└  0 credentials`.

**Success:** the provider you intend to use is listed, with the credential type you intend
(`api` / `oauth` / `wellknown`).
**Failure:** `0 credentials`, or the wrong provider. Note `providers list` does **not** validate the
key — a dead `tp-…` key still lists as present. That is exactly how this machine's credential rotted
unnoticed.
**Fallback for "is the key actually alive":** the cheapest honest probe is one 401-or-not request.
Do not use `mimo run` for this (it costs a real turn). Use the endpoint directly:

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST https://api.xiaomimimo.com/anthropic/v1/messages \
  -H "x-api-key: $MIMO_KEY" -H 'content-type: application/json' -d '{}'
# 401 → dead key.  400 → key is live, body was deliberately empty.  Nothing is billed either way.
```

**Base URL is per-account/per-region, not a constant** — the owner's is `token-plan-sgp…`, the docs
name `token-plan-cn…`, and the CLI's own default is `https://api.xiaomimimo.com/v1` (VERIFIED: that
URL appeared in the `metadata.url` of a live error event). Make it a config field.

---

## 2. Start a task headless, with a pinned session id, capturing structured output

**verified: true** (id-pinning verified *impossible*; everything else verified working)

### 2a. The launch

```bash
TITLE="ORCH-$(date +%s)-$(openssl rand -hex 4)"     # your correlation handle; make it unique
mimo run \
  --format json \
  --title "$TITLE" \
  --model xiaomi/mimo-v2.5-pro \
  --variant high \
  --agent build \
  --dir "$WORKDIR" \
  "$TASK_TEXT"  > "$RUNDIR/events.jsonl" 2> "$RUNDIR/run.err" < /dev/null
#                                                             ^^^^^^^^^^^^
#   MANDATORY. Without it `mimo run` blocks on stdin to EOF and never emits a byte. See §11b.
```

Every flag above was read from `mimo run --help` on 0.1.14. Message can also arrive on **stdin**
(`if (!process.stdin.isTTY) message += "\n" + await Bun.stdin.text()`), which is how you pass a task
longer than an argv limit — **and is exactly why `< /dev/null` is mandatory when you do not.** That
read waits for EOF, so an inherited, never-closed stdin hangs the process before it does anything.
§11b has the measurements.

### 2b. There is no `--session-id`. Recover the id from the stream.

`POST /session` accepts no `id`, and passing one is **silently ignored** (§0.5). The first
`--format json` line carries it:

```jsonc
{"type":"error","timestamp":1789824546256,"sessionID":"ses_-ffe5f4624d73affeE3baR7YLT","error":{…}}
```

```bash
SID=$(head -n1 "$RUNDIR/events.jsonl" | jq -r .sessionID)
```

Event types emitted: `tool_use`, `step_start`, `step_finish`, `text`, `reasoning` (only with
`--thinking`), `error`. **There is no `result` envelope and no totals line** — completion is process
exit or `GET /session/status`, and cost comes from the DB.

### 2c. Title correlation, for sessions the CLI did not create — **verified: true**

```bash
curl -s -u "mimocode:$MIMOCODE_SERVER_PASSWORD" \
  "http://127.0.0.1:$PORT/session?search=$TITLE" | jq -r '.[0].id'
```
Live result: one exact row, `[{"id":"ses_-ffe5f46260a0cffeV17fSNcA2","slug":"shiny-moon","projectID":"…","directory":"…","title":"ORCH-01JSPIKE-probe","version":"0.1.14","time":{"created":…,"updated":…}}]`.
Or `mimo session list -n 20 --format json` and match on `title`.

**Success:** exactly one row.
**Failure:** zero rows (the run died before creating the session) or more than one (title collision —
two sessions created in the same second are indistinguishable).
**Fallback:** put a ULID in the title; it makes collision impossible. And prefer §2b when you control
the launch.

### 2d. The better handle nobody documents: pin the **message** id — **verified: true**

`PromptInput` accepts an optional `messageID`. Create the session yourself, then inject with an id
you chose:

```bash
SID=$(curl -s -u "mimocode:$PW" -X POST "http://127.0.0.1:$PORT/session" \
        -H 'content-type: application/json' -d "{\"title\":\"$TITLE\"}" | jq -r .id)

curl -s -u "mimocode:$PW" -X POST "http://127.0.0.1:$PORT/session/$SID/prompt_async" \
  -H 'content-type: application/json' \
  -d "{\"messageID\":\"$MY_MSG_ID\",\"parts\":[{\"type\":\"text\",\"text\":\"$TASK_TEXT\"}],
       \"model\":{\"providerID\":\"xiaomi\",\"modelID\":\"mimo-v2.5-pro\"}}"
```
Now every `message.updated` event and every DB row for that turn carries an id the orchestrator
minted. This is the closest thing MiMoCode has to `--session-id`.

**Failure shape, verified:** an empty body returns
`400 {"data":{},"error":[{"expected":"array","code":"invalid_type","path":["parts"],…}],"success":false}`
— so the required field is `parts`, an array with at least one element.

### 2e. A third handle nobody documents: name the **process run** — **verified: true**

Two environment variables use a `??=` assignment, so **whatever the orchestrator sets is kept**
(VERIFIED — `process.env.MIMOCODE_RUN_ID ??= crypto.randomUUID()` and
`process.env.MIMOCODE_PROCESS_ROLE ??= <default>` read in the 0.1.14 binary):

```bash
export MIMOCODE_RUN_ID="ORCH-RUN-01JSPIKE-abc123"
export MIMOCODE_PROCESS_ROLE="orch-ticket-4412"
mimo run --format json …
```

VERIFIED live, in a fresh `MIMOCODE_HOME`:

```
<MIMOCODE_HOME>/data/log/2026-09-19T133623639Z-orch-ticket-4412-53720-2a749772.log
                          └── ISO ─────────┘ └── your role ──┘ └pid┘ └uuid8┘

INFO 2026-09-19T13:36:23 service=server-proxy version=0.1.14 args=["debug","paths"] \
     process_role=orch-ticket-4412 run_id=ORCH-RUN-01JSPIKE-abc123 mimocode
```

So even though the *session* id cannot be pinned, **the log file name and every log line carry ids the
orchestrator chose**. Use `MIMOCODE_PROCESS_ROLE` as the ticket id: `ls <data>/log/*-$TICKET-*.log`
then finds every process that ever worked that ticket, across crashes and restarts, with no database
lookup.

Also set for free, by MiMoCode, in the environment of **every command the agent runs**: `AGENT=1`,
`MIMOCODE=1`, `MIMOCODE_PID=<pid>` (VERIFIED). A project's own scripts can detect they are being run
by an agent, and the orchestrator can find the engine pid from inside a tool call.

---

## 3. Start the same task in a visible terminal the owner can type into

**verified: partial** — flags and the server side verified; the window was **not** opened (opening
GUI windows while the owner is away is externally visible, so I stopped at the command).

The design that makes this axis cheap: **one server, two faces.** The supervisor drives it over HTTP;
the owner attaches a TUI to the same server and types into the same sessions.

```bash
# supervisor side, once per account — long-lived
mimo serve --port "$PORT" --hostname 127.0.0.1    # VERIFIED: prints "mimocode server listening on http://127.0.0.1:47513"

# owner side, on demand
mimo attach "http://127.0.0.1:$PORT" -p "$MIMOCODE_SERVER_PASSWORD" -s "$SID"
```
`mimo attach --help` (VERIFIED on 0.1.14) takes `--dir`, `-c/--continue`, `-s/--session`, `--fork`,
`-p/--password`. So the owner can be dropped straight into the session the orchestrator is running.

On this machine, with the owner's configured launcher
(`~/.claude/shared/tooling.json` → `terminal_launcher.default = "iterm2-osascript"`, semantics
*"tab in the current window when one exists, else ONE fresh window"*):

```bash
osascript -e 'tell application "iTerm2"
  if (count of windows) = 0 then
    create window with default profile
  else
    tell current window to create tab with default profile
  end if
  tell current session of current window to write text "'"$ENVLINE mimo attach http://127.0.0.1:$PORT -p $PW -s $SID"'"
end tell'
```

**Hard constraint, and it happens to be satisfied here:** MiMoCode's README states it **does not
support macOS Terminal.app** and directs users to iTerm2 or the VS Code terminal (VERIFIED — the text
is embedded in the 0.1.14 binary: *"MiMoCode does not support the built-in Terminal.app"*).
`/Applications/iTerm.app` is present on this machine (VERIFIED). An orchestrator that defaults to
Terminal.app on some other machine will produce a garbled TUI and no error.

**Success:** the TUI paints, the footer shows the context meter, `/status` works.
**Failure:** garbled output (wrong terminal), or `401` (wrong username — see §0.1; `attach` builds
the header itself from `-p`, so the username only bites you in `curl`).
**Fallback if the owner must type but no TUI is available:** §8 — `prompt_async` is a complete
substitute for typing, and unlike the current harness's nudge it returns a receipt.

---

## 4. Tell whether the session is alive, working, waiting, or finished — from outside

**verified: true**

Four signals, in the order a supervisor should consult them.

### 4a. `GET /session/status` — the authoritative one

```bash
curl -s -u "mimocode:$PW" "http://127.0.0.1:$PORT/session/status" | jq
```
Live: `{}` when nothing is running (VERIFIED). The value type per session id, VERIFIED from the zod
union in the binary:

```ts
{ type: "idle" }
{ type: "busy",   message?: string }
{ type: "notice", message: string }
{ type: "retry",  attempt: number, phaseAttempt?: number, message: string,
                  next: number,                     // ABSOLUTE ms timestamp of the next attempt
                  phase?: "request" | "stream",
                  scope?: "request" | "live-step" | "max-candidate" | "max-judge" }
```

Map it straight onto the orchestrator's vocabulary:

| Signal | Orchestrator state |
|---|---|
| id absent from the map, or `{type:"idle"}` | **finished / not working** |
| `{type:"busy"}` | **working** |
| `{type:"retry"}` | **throttled** — and `next` tells you exactly when to look again |
| `{type:"notice"}` | working, with something to surface |
| `/permission` or `/question` non-empty for this id | **waiting on a human** — see §9 |

MiMoCode's own completion waiter does exactly this: it subscribes to `session.status`, treats
`status.type === "idle"` as done, and polls the same endpoint every **750 ms** as a belt-and-braces
(`intervalMs ?? 750`, VERIFIED in the binary). Copy that interval; do not invent one.

### 4b. `GET /event` — the live bus, no polling

```bash
curl -s -N -u "mimocode:$PW" "http://127.0.0.1:$PORT/event"
```
VERIFIED live: the first frame is `data: {"type":"server.connected","properties":{}}`, then
`message.updated`, `message.part.updated`, `session.status`, `session.idle`, `session.error`,
`permission.asked`, `question.asked`, `question.replied`, `question.rejected`, `session.goal`, …

### 4c. `GET /session/:id/actors` — per-actor detail, including subagents

VERIFIED live on a freshly created session:

```json
[{"sessionID":"ses_…","actorID":"main","mode":"main","status":"pending","lifecycle":"persistent",
  "agent":"main","description":"main agent","contextMode":"full","background":false,
  "tools":"INHERIT","lastTurnTime":1789824464374,"turnCount":0,
  "time":{"created":…,"updated":…}}]
```
`turnCount` and `lastTurnTime` are the cheapest "is it actually progressing, or just alive" check —
a `busy` session whose `lastTurnTime` has not moved in N minutes is stuck, and that is a different
condition from idle.

### 4d. Is the **process** alive — and beware the wrapper

```bash
lsof -nP -iTCP:"$PORT" -sTCP:LISTEN     # the child `.mimocode` is what listens, not the `node` wrapper
curl -s -o /dev/null -w '%{http_code}' -u "mimocode:$PW" "http://127.0.0.1:$PORT/path"   # 200 = up
```
**Never** infer liveness from the `node` pid. §0.10: the Bun child outlives it, and a dead wrapper
with a live child is precisely the state that leaves an orphan holding a port and the SQLite DB.

**Failure:** `/session/status` returning `{}` is ambiguous between "finished" and "never started".
Disambiguate with `GET /session/:id` (404 = never existed) and `GET /session/:id/message` (empty =
started nothing).
**Fallback if the HTTP plane is gone:** the DB is still truth —
`mimo db "SELECT id,title,time_updated FROM session ORDER BY time_updated DESC LIMIT 5" --format json`.

---

## 5. Read how full the context is, force a compaction or handoff, prove it happened

**verified: true** for reading, for the trigger's contract, and for the proof columns. The
compaction itself was not executed (it is a real model call and the credential is dead).

### 5a. The denominator — zero model calls

```bash
mimo models xiaomi
```
VERIFIED live output:

```
mimo/mimo-auto — window 1M, compacts at 900K
xiaomi/mimo-v2.5 — window 1.05M, compacts at 944K
xiaomi/mimo-v2.5-pro — window 1.05M, compacts at 944K
xiaomi/mimo-v2.5-pro-ultraspeed — window 1.05M, compacts at 944K
```
"compacts at" **is** the number to divide by. The exact arithmetic, VERIFIED by reading the compiled
functions:

```
hard      = model.limit.input || model.limit.context          // 0 ⇒ overflow handling OFF
effective = config compaction.max_context ?? hard             // can only LOWER the window
usable    = floor(effective * MIMOCODE_COMPACTION_TRIGGER_RATIO)      // ratio default 0.9
fill      = tokens.total || (tokens.input + tokens.output + tokens.cache.read + tokens.cache.write)
autocompact fires when  fill >= usable   (unless compaction.auto === false)
```

### 5b. The numerator — the newest assistant message

`AssistantMessage` schema, VERIFIED from the binary:

```ts
{ …, providerID, mode, agent, path:{cwd,root}, summary?: boolean, cost: number,
  tokens: { total?: number, input: number, output: number, reasoning: number,
            cache: { read: number, write: number } },
  structured?, variant?, finish?: string }
```

Read it live, either way:

```bash
# SQL — VERIFIED to parse and execute on the live DB
mimo db "SELECT id,
                json_extract(data,'\$.tokens.total')      AS total,
                json_extract(data,'\$.tokens.input')      AS input,
                json_extract(data,'\$.tokens.cache.read') AS cache_read,
                json_extract(data,'\$.summary')           AS is_summary
         FROM message
         WHERE session_id='$SID' AND json_extract(data,'\$.role')='assistant'
         ORDER BY time_created DESC LIMIT 1" --format json

# or HTTP
curl -s -u "mimocode:$PW" "http://127.0.0.1:$PORT/session/$SID/message" | jq '.[-1].info.tokens'
```

`percent = fill / usable`. No estimation, no tokenizer, no model call. MiMoCode's own pressure ladder
is 0/1/2/3 at `<0.50 / <0.70 / <0.85 / ≥0.85` — reuse those bands so the orchestrator and the agent
agree on what "nearly full" means.

### 5c. Force a compaction from outside

```bash
curl -s -u "mimocode:$PW" -X POST "http://127.0.0.1:$PORT/session/$SID/summarize" \
  -H 'content-type: application/json' \
  -d '{"providerID":"xiaomi","modelID":"mimo-v2.5","auto":false}'
```
**`providerID` and `modelID` are required — there is no "use the session's model" default.**
VERIFIED: omitting them returns
`400 … [{"path":["providerID"],…},{"path":["modelID"],…}]`.
Useful side effect: compact on the **cheap** model (`mimo-v2.5`, 1× credit burn) while the session
works on `-pro` (2×).

**Success:** `200 true`.
**Failure:** `400` (missing model), or the turn is busy.

### 5d. Prove it happened — three independent, durable signals

```bash
# 1. a COLUMN. Snapshot before, compare after.
mimo db "SELECT id,time_compacting,last_checkpoint_message_id FROM session WHERE id='$SID'" --format json
```
VERIFIED live shape: `[{"id":"ses_…","title":"…","time_compacting":null,"last_checkpoint_message_id":null}]`
— `null` before any compaction, and the column exists on the `session` table (VERIFIED via
`pragma_table_info`).

```
2. CompactionPart lands in `part`, and it carries  trigger: "manual" | "automatic" | "provider-overflow"
   plus  tail_start_id, tail_end_id, manifest?, compacted_tool_calls[]{call_id,tokens}
   →  trigger == "manual"  is proof the SUPERVISOR did it, not the agent.   (VERIFIED — zod in binary)

3. The assistant message written by the compaction has  summary: true.   (VERIFIED — AssistantMessage schema)
```

That triple is stronger than anything else in this scan: a column, a typed cause, and a flagged
message.

### 5e. Handoff instead of compaction

```bash
curl -s -u "mimocode:$PW" -X POST "http://127.0.0.1:$PORT/session" \
  -H 'content-type: application/json' \
  -d "{\"title\":\"$NEW_TITLE\",\"contextFrom\":\"$OLD_SID\",\"contextWatermark\":\"$MSG_ID\"}"
```
Persisted as `session.context_from` / `session.context_watermark` (both columns VERIFIED present).
**The exact semantics of the watermark — how much history the new session inherits — remain
UNKNOWN; not exercised.** Do not ship a handoff on this until someone runs it with a live key.

### 5f. Prevention beats recovery

`ContextOverflowError` is classified **terminal**, not retryable (VERIFIED — `retry.ts` returns
`{retryable:false, kind:"terminal", message:"Context window exceeded"}`). There is no recovering a
turn that overflowed. Set the budget up front:

```bash
export MIMOCODE_COMPACTION_MAX_CONTEXT="600K"     # or "50%"; clamped to the provider cap, can only lower
export MIMOCODE_COMPACTION_TRIGGER_RATIO="0.75"   # default 0.9 — too late for a long unattended turn
```

---

## 6. Read remaining quota and the reset time; detect a limit hit in-band

**verified: true — and the verified answer is "you cannot read remaining quota."**

### 6a. What the endpoint actually returns

The strongest evidence available without a live key: a real 401 from `api.xiaomimimo.com` captured as
a `--format json` error event. Its **full** `responseHeaders`, VERIFIED verbatim:

```
cache-control, connection, content-length, content-type, date, expires, pragma,
server: MiFE/3.4.29, vary, x-mife-upstream-status
```

**No `x-ratelimit-*`. No `ratelimit-*`. No `retry-after`. Nothing about balance or credits.** The MiMo
edge (`MiFE/3.4.29`) does not publish capacity. There is no usage endpoint in the docs, none in the
CLI, and the only balance surface Xiaomi documents is the **web console**
(`platform.xiaomimimo.com/#/console/balance`, `#/console/usage` with CSV export).

**This is the one axis the owner called non-negotiable, and MiMo fails it. It is structural, not a
bug to work around.**

### 6b. What you *can* read — a local ledger

```bash
mimo stats --days 30 --models --project ""      # VERIFIED: --days, --tools, --models, --project exist
```
VERIFIED live output shape: OVERVIEW (Sessions / Messages / Days) and COST & TOKENS (Total Cost,
Avg Cost/Day, Avg & Median Tokens/Session, Input, Output, Cache Read, Cache Write). It aggregates
`message.data.tokens` and `message.data.cost` **out of the local SQLite** and never contacts the
provider. It tells you what you **spent on this machine**, never what is **left**.

Equivalent, if you want it in the orchestrator's own store:

```bash
mimo db "SELECT SUM(json_extract(data,'\$.cost')) AS cost,
                SUM(json_extract(data,'\$.tokens.total')) AS tokens
         FROM message WHERE time_created > $PERIOD_START_MS" --format json
```

**Cost of this fallback, stated plainly:** it drifts. Any usage from the web console, the Desktop app,
or a second machine is invisible to it, and so is anything the local DB never saw.

### 6c. In-band limit detection — this part works, and is machine-readable

`decide()` in `retry.ts` (VERIFIED):

- HTTP **429**, 408, 425 → `kind:"rate_limit"`, retryable; also pattern-matches `rate_limit` /
  `rate limited` / code `"429"` in the body.
- Reset time: `retry-after-ms` (ms) → `retry-after` (seconds or HTTP-date) → a regex over the message
  (`/(?:try again|retry(?:ing)?)(?: in| after)\s+(\d+…)\s*(ms|s|m|h)/i`).
- `RATE_LIMIT_MAX_RETRIES = 5`, then the turn errors. (Also: `REQUEST_MAX_RETRIES=4`,
  `STREAM_MAX_RETRIES=5`, `SERVER_MAX_RETRIES=8`.)
- The supervisor sees it as `{type:"retry", attempt, message, next, phase, scope}` on
  `/session/status` and on `/event`, where **`next` is an absolute ms timestamp**.

```bash
# the supervisor's actual quota policy for this lane
curl -s -N -u "mimocode:$PW" "http://127.0.0.1:$PORT/event" |
while read -r line; do
  case "$line" in *'"session.status"'*'"type":"retry"'*)
      NEXT=$(printf '%s' "${line#data: }" | jq -r '.properties.status.next')
      # park this lane until $NEXT; do NOT start new work on this account
  ;; esac
done
```

**Whether the MiMo endpoint emits `retry-after` on a real 429 is UNKNOWN** — a 429 was not provoked.
If it does not, `next` is MiMoCode's own exponential backoff, not the provider's truth.

### 6d. The windows that exist

| Window | Value | Tag |
|---|---|---|
| RPM (`-pro`, `v2.5`) | 100 requests/min, per **account**, summed over all keys, per model | VERIFIED (official rate-limit doc) |
| TPM | 10M tokens/min | VERIFIED (same) |
| Pay-as-you-go | pure per-token, **no window** | VERIFIED |
| Token Plan | monthly **credits**; 2× burn for `-pro`, 1× for `v2.5`; **no 5-hour window** | CLAIMED (plan-comparison sites; not found on a Xiaomi page) |

**The good news for an overnight queue:** there is no rolling-hours or weekly wall of the
Claude-subscription kind, so there is no "weekly limit hit at 02:00". **The bad news:** monthly credit
burn is invisible until it stops working.

**Verdict for the adapter:** MiMo may never hold the role whose quota the orchestrator predicts.
Give it best-effort work, a 429-backoff policy, and a local ledger with a conservative hard stop.

---

## 7. Switch a new session to a different account, and verify before work starts

**verified: true**

### 7a. The mechanism to use: one `MIMOCODE_HOME` per account

```bash
ACCOUNT=acct-b
export MIMOCODE_HOME="$ORCH_STATE/mimo/$ACCOUNT"
export MIMOCODE_SERVER_PASSWORD="$(cat "$ORCH_STATE/mimo/$ACCOUNT/.pw")"
mimo serve --port 47601 --hostname 127.0.0.1 &
```
VERIFIED: `mimo debug paths` under a scratch `MIMOCODE_HOME` reported data, bin, log, cache, config
and state all relocated. `auth.json` and `mimocode.db` move with it, so accounts cannot bleed.

**Cost, measured:** `node_modules` ~97 MB once (shared), plus one process and ~62 MB of state per
account.

### 7b. The mechanism NOT to use unattended: `MIMOCODE_AUTH_CONTENT`

```bash
export MIMOCODE_AUTH_CONTENT='{"xiaomi":{"type":"api","key":"sk-…"}}'
```
VERIFIED working — `mimo providers list` immediately showed `● Xiaomi api / 1 credentials` with no
file written. Also VERIFIED to actually reach the provider (the 401 probe used exactly this).

**But MiMoCode's own source argues against it**, and for an unattended agent the argument is
decisive: *"anything in the environment is readable by every child the engine spawns — the bash tool
alone turns `echo $MIMOCODE_AUTH_CONTENT` into a credential dump, and a sibling can still read
`/proc/<pid>/environ`."* Use it for a preflight probe; never for a run that executes model-chosen
shell.

### 7c. Changing a **running** instance's credential

```bash
curl -s -u "mimocode:$PW" -X PUT "http://127.0.0.1:$PORT/auth/xiaomi" \
  -H 'content-type: application/json' -d '{"type":"api","key":"sk-NEW"}'
curl -s -u "mimocode:$PW" -X DELETE "http://127.0.0.1:$PORT/auth/xiaomi"
```
These are the **only two instance-level routes MiMoCode publishes in its own OpenAPI document**
(VERIFIED: `GET /doc` returns exactly `PUT/DELETE /auth/{providerID}` and `POST /log`). Credential
shapes, VERIFIED from that schema:

```ts
{type:"oauth", refresh, access, expires, accountId?, enterpriseUrl?}
{type:"api",   key, metadata?}
{type:"wellknown", key, token}
```

**Scope limit that decides the architecture:** this rewrites `auth.json` for the **whole instance**.
`Auth.all()` re-reads on every call, so the next request uses the new key — for *every* session on
that server. **One session on a different account from its siblings is impossible.** Run one server
per account and route sessions to servers.

### 7d. Verify the switch *before* work starts

```bash
mimo providers list | grep -q 'credentials' || exit 1          # something is configured
curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/anthropic/v1/messages" \
     -H "x-api-key: $KEY" -H 'content-type: application/json' -d '{}'   # 400 = live, 401 = dead
```
**Success:** `400` (auth passed, body was deliberately empty — nothing billed).
**Failure:** `401 {"code":"401","type":"invalid_key"}` — stop before queuing work. This is the check
that would have caught the owner's rotted key.
**Fallback:** none needed; this probe is free and takes one round-trip.

**No Keychain is involved anywhere** (VERIFIED — credentials are a `0600` `auth.json`). That removes
the "macOS blocks on a GUI dialog for an account never granted Always Allow" failure mode Claude Code
has on this machine.

---

## 8. Deliver an instruction into a running session and confirm it arrived

**verified: true** (route contract and validation verified live; delivery into a *busy* session not
exercised for want of a key)

```bash
curl -s -u "mimocode:$PW" -X POST "http://127.0.0.1:$PORT/session/$SID/prompt_async" \
  -H 'content-type: application/json' \
  -d '{"messageID":"'"$MY_MSG_ID"'",
       "parts":[{"type":"text","text":"Stop refactoring and run the test suite now."}]}'
# → 204 No Content
```

`PromptInput`, VERIFIED in full from the binary:

```ts
{ sessionID, messageID?, model?:{providerID,modelID}, modelRef?, agent?, agentID?, task_id?,
  source?: "user"|"spawn"|"hook", provenance?, noReply?, format?, titleLocale?,
  system?, systemMode?: "append"|"replace-agent", harness?: "auto"|"codex"|"default", variant?,
  parts: (TextPartInput|FilePartInput|AgentPartInput|SubtaskPartInput)[]   // min 1
}
```

**Server-side rate limit, VERIFIED in the route:** `RateLimitMiddleware({windowMs: 60_000, max: 20,
keyPrefix: "prompt_async"})` — **20 injections per minute**. A watcher that nudges in a tight loop
will be throttled by the platform itself.

### Proof it arrived — three receipts, pick one

1. **`204`** is returned only after schema validation and session lookup (404 if the session does not
   exist).
2. **`message.updated` on `/event`** carries the message id — and if you passed `messageID`, it is
   *your* id.
3. **The DB row**: `mimo db "SELECT id,time_created FROM message WHERE id='$MY_MSG_ID'" --format json`.

That is a durable receipt, not a hope. This is exactly the axis the current harness fails
("a nudge that cannot submit stranded text").

### Variants worth knowing

| Need | Call |
|---|---|
| Blocking, returns the created message | `POST /session/:id/message` |
| Run a slash command with args | `POST /session/:id/command` |
| Run a shell command in the session's context | `POST /session/:id/shell` |
| Stop the current turn | `POST /session/:id/abort` → VERIFIED live, returns `true` |
| Roll back | `POST /session/:id/revert` / `/unrevert` |
| **Speak as the agent** | `mimo run --role assistant "<text>"` — *"injects text as model output then triggers continuation"* (VERIFIED, `run --help`). No other platform in this scan exposes this. |
| **Ask without disturbing** | `POST /session/:id/ask {question,providerID?,modelID?}` → `{answer}`; a one-shot read-only side question over a frozen snapshot. Costs one model call. |

**Failure:** `400` with a zod error naming the missing path; `404` for an unknown session; `429` past
20/min.
**Fallback if HTTP is unavailable:** `mimo run -s "$SID" "<text>"` reaches the same session, at the
cost of a second process and no receipt until the DB row appears.

---

## 9. Answer a permission prompt or a clarifying question without a human

**verified: true** — every GET verified live; every POST toggle verified live; the reply bodies
verified from the binary's zod.

MiMoCode is the only platform in this scan with a **question channel distinct from a permission
channel**. Both are answerable over HTTP.

### 9a. Permissions

```bash
curl -s -u "mimocode:$PW" "http://127.0.0.1:$PORT/permission"                     # → []   (VERIFIED live)
curl -s -u "mimocode:$PW" -X POST "http://127.0.0.1:$PORT/permission/$REQ/reply" \
  -H 'content-type: application/json' -d '{"reply":"once"}'
```
`PermissionReplyBody` = `{ reply: "once" | "always" | "reject", message?: string }` (VERIFIED —
the enum `["once","always","reject"]` read in the binary). Session-scoped variant:
`POST /session/:id/permissions/:permissionID`. The event is `permission.asked` with
`{id, sessionID, permission, patterns[]}`; MiMoCode's own `run` loop consumes exactly this and calls
`permission.reply({requestID, reply:"once"})`.

### 9b. Questions

```bash
curl -s -u "mimocode:$PW" "http://127.0.0.1:$PORT/question"                       # → []   (VERIFIED live)
curl -s -u "mimocode:$PW" -X POST "http://127.0.0.1:$PORT/question/$REQ/reply" \
  -H 'content-type: application/json' -d '{"answers":[["Use the existing migration"]]}'
curl -s -u "mimocode:$PW" -X POST "http://127.0.0.1:$PORT/question/$REQ/reject"
```
`answers` is **one array per question** — the TUI's own call is
`question.reply({requestID, answers:[[choice]]})` (VERIFIED in the binary). `GET /question` returns
`[{id, sessionID, questions:[{question, header, options:[{label,description}], multiple?, custom?}], tool?}]`,
so the orchestrator sees the full option list before choosing. `ask()` blocks the turn on a
`Deferred` until `reply()` or `reject()`; `reject()` fails the await with *"The user dismissed this
question"*.

### 9c. The unattended posture — set these explicitly at startup

**Neither default is right for unattended work.** VERIFIED live on a fresh `serve`:
`/permission/ask-timeout` → `null` (**waits forever**), `/permission/skip-all` → `false`,
`/permission/auto-approve-delete` → `false`, `/question/never-ask` → `false`.

```bash
# VERIFIED: all three POSTs accepted and the subsequent GET returned the new value
curl -s -u "mimocode:$PW" -X POST "http://127.0.0.1:$PORT/permission/ask-timeout" \
     -H 'content-type: application/json' -d '{"ms":120000}'      # → 120000
curl -s -u "mimocode:$PW" -X POST "http://127.0.0.1:$PORT/question/never-ask" \
     -H 'content-type: application/json' -d '{"enabled":true}'   # → true
curl -s -u "mimocode:$PW" -X POST "http://127.0.0.1:$PORT/permission/skip-all" \
     -H 'content-type: application/json' -d '{"enabled":true}'   # → true
```

- **`ask-timeout`** is the single most important unattended setting. Left at `null`, one unanswered
  permission blocks a turn until the heat death of the run.
- **`never-ask: true`** does not silence the question tool; it makes `ask()` unreachable and returns a
  `[Never-Ask]` directive so *the model re-picks the best option itself* (VERIFIED — that exact
  wording is the route's own description). This is the right default for a lane with no supervisor
  attached; if the supervisor *is* attached and answering, leave it `false` and answer for real.
- **`skip-all: true`** is the blunt instrument. Prefer a per-session ruleset (§ below).

### 9d. Surface-dependent defaults — the trap

| Surface | Default on an `ask` | Tag |
|---|---|---|
| `mimo run` headless, no flags | **auto-rejects**, printing `permission requested: …; auto-rejecting` | VERIFIED (source) |
| `mimo run` — the `question` tool | **denied outright**; `run` hard-codes `{permission:"question",action:"deny",pattern:"*"}` and the same for `plan_exit` | VERIFIED (source) |
| `mimo serve` instance | `ask-timeout: null` — **blocks forever** | VERIFIED (live GET) |
| `--dangerously-skip-permissions` / `--yolo` | auto-`once` for anything not explicitly denied; **the interactive confirmation is skipped when there is no TTY**, so it activates silently in CI | VERIFIED (help + README) |

So: shelling out to `mimo run` gives you an agent that **fails fast and cannot ask for help**;
driving `mimo serve` gives you one that **waits forever**. Choose deliberately, then override.

### 9e. The ruleset, per session

```bash
curl -s -u "mimocode:$PW" -X POST "http://127.0.0.1:$PORT/session" \
  -H 'content-type: application/json' \
  -d '{"title":"'"$TITLE"'","permission":[
        {"permission":"bash","action":"allow","pattern":"*"},
        {"permission":"bash_delete","action":"ask","pattern":"*"},
        {"permission":"external_directory","action":"allow","pattern":"/tmp/**"},
        {"permission":"webfetch","action":"deny","pattern":"*"}]}'
```
Ordered list, **last matching rule wins**. Caveats that bite: a leftover `"ask"` rule still prompts
even under `--yolo`; a top-level `"*":"ask"` makes `--yolo` a no-op. `bash_delete` is a separate
permission covering `rm/rmdir/unlink/shred/del/erase/rd/remove-item` and destructive git
(`reset --hard`, `clean -f`, `branch -D`, `worktree remove`, `push --force`, `stash drop|clear`) —
so a broad `bash: allow` cannot silently pre-approve destruction. Override only via
`MIMOCODE_AUTO_APPROVE_DELETE=true` or `POST /permission/auto-approve-delete`.

`MIMOCODE_SKIP_ALL_FORCED_ASK_TIMEOUT_MS` (VERIFIED present in the binary's env table) tunes the
60 s auto-reject that `skip-all` applies to forced-ask operations.

---

## 10. Resume after a crash, and after the whole machine rebooted

**verified: true** for the read side and the route contract; a real interrupted turn was not produced
(no key).

### 10a. What survives

| Failure | Survives | Why |
|---|---|---|
| `SIGKILL` / Ctrl-C | **yes** | all state is in `<MIMOCODE_HOME>/data/mimocode.db` (SQLite, WAL), not process memory |
| Reboot | **yes** | same, plus `session.time_updated` and `session.last_checkpoint_message_id` on the row |
| Provider outage / 429 | **yes, self-healing** | `network`/`rate_limit`/`server` are retryable; honours `retry-after*`; publishes `{type:"retry",…,next}` |
| **Context overflow** | **no** | classified `terminal`. Prevent it (§5f) |

### 10b. The recipe

```bash
# 1. Is there an interrupted turn?   (VERIFIED live: returns [] when there is none)
curl -s -u "mimocode:$PW" "http://127.0.0.1:$PORT/session/$SID/recovery"
# → [{ "assistantMessageID": "msg_…", "parentMessageID": "msg_…", "created": 1789… }, …]

MID=$(curl -s -u "mimocode:$PW" "http://127.0.0.1:$PORT/session/$SID/recovery" | jq -r '.[0].assistantMessageID')

# 2. Resume it WITHOUT creating another user message.
#    NOTE: parameters go in the QUERY STRING, not a body.   (corrects the profile — §0.3)
curl -s -u "mimocode:$PW" -X POST \
  "http://127.0.0.1:$PORT/session/$SID/turn/$MID/resume?agentID=main&modelProviderID=xiaomi&modelID=mimo-v2.5-pro"
# → 202 Accepted
```

Guarantees read directly in the route source:

- **`assertNotBusy` runs first** → a double-resume returns **409**, it does not double-run.
- The candidate is **validated against `recovery()`** → resuming a message that is not resumable
  returns **404** with `"No resumable interrupted turn found for assistant message …"`.
- `modelProviderID` and `modelID` must be **both or neither** → **400**
  `"modelProviderID and modelID must be provided together"`.
- `agentID` absent or `"main"` routes to `resumeMainCascading`; anything else to `resumeBackground`.
- Failures after acceptance are published as a `session.error` event, not as an HTTP status — the
  202 means *accepted*, not *succeeded*. **Watch `/event`.**

### 10c. After a reboot

Nothing is registered with `launchd`. The orchestrator owns restart:

```bash
# 1. re-export the §1b env block for each account
# 2. relaunch one server per account
mimo serve --port "$PORT" --hostname 127.0.0.1 &
# 3. re-enumerate — the DB is intact
mimo session list -n 50 --format json          # → [{id,title,updated,created,projectId,directory}, …]
# 4. for every session the orchestrator still has queued:
curl -s -u "mimocode:$PW" "http://127.0.0.1:$PORT/session/$SID/recovery"    # then §10b
```
**Success:** `session list` shows the pre-reboot sessions with their titles; `recovery` returns a
candidate for anything that died mid-turn.
**Failure:** an empty `session list` means the wrong `MIMOCODE_HOME` — the state is per-home, and a
missing env var silently gives you a *different, empty* store rather than an error.
**Fallback when `recovery` is empty but work is unfinished:** `mimo run -s "$SID" "<continue>"`, or
`POST /session/:id/prompt_async` with a fresh instruction. That creates a new user message — less
clean, always available.

### 10d. Continue without HTTP

```bash
mimo run -c              # continue the last session
mimo run -s "$SID"       # continue a specific one
mimo run -s "$SID" --fork   # branch instead of continuing
```

---

## 11. Stop it cleanly, leaving nothing running

**verified: true — and this is where the platform surprised me twice.**

### 11a. Surprise one: the child outlives the wrapper

`node_modules/.bin/mimo` is a **Node shim** that spawns the real Bun binary
`@mimo-ai/cli/bin/.mimocode`. VERIFIED on this machine: an orphaned
`.mimocode serve --port 47311`, **`ppid=1`**, left over from the *previous research pass*, was still
listening 16 minutes after that pass ended — still holding its port and its SQLite database.

```
PID   PPID  ELAPSED  COMMAND
59048 1     16:15    …/@mimo-ai/cli/bin/.mimocode serve --port 47311 --hostname 127.0.0.1
```

**Kill the child, not the wrapper.** VERIFIED clean shutdown:

```bash
kill -TERM 59048        # → process gone in ~2 s
curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://127.0.0.1:47311/path   # 200 → 000 (refused)
```
`serve` registers `process.once("SIGINT", …)` and `process.once("SIGTERM", …)`, both calling
`server.stop(true)` then `process.exit(0)` (VERIFIED in the binary). SIGTERM is the right signal;
SIGKILL is never needed and would leave the WAL dirty.

### 11b. Surprise two: `mimo run` hangs forever unless you close its stdin

**This is the single most important operational fact in this document, it is deterministic, and it is
not in any documentation.**

`mimo run` implements "message from stdin" as
`if (!process.stdin.isTTY) message += "\n" + await Bun.stdin.text()`. `Bun.stdin.text()` **reads to
EOF**. A supervisor that spawns `mimo run` the ordinary way — stdin inherited from the parent, an open
pipe or socket that nobody ever closes — hangs **before the first event is emitted**, forever, with
zero output. It does not time out, it does not log, it does not fail. It waits.

Measured, same command, same bogus key, same machine, back to back:

| stdin | Result |
|---|---|
| `< /dev/null` | **exit 0 in 5 s**, 905 bytes, the error event on stdout — **twice, identically** |
| inherited (open) | **killed at 90 s** by `timeout`, **0 bytes** written |

And the same hang, before the cause was isolated, in five earlier probes: three on a shared
`MIMOCODE_HOME`, two on an isolated one, every one of them `rc=124` at 150 s with 0–117 bytes (the 117
was only the first-run migration banner on stderr). The `MIMOCODE_HOME` had nothing to do with it —
**it was stdin every time.**

**The rule:**

```bash
mimo run --format json … < /dev/null          # ALWAYS. Not optional.
```
…unless you are deliberately feeding the task text on stdin, in which case you must close the pipe:
```bash
printf '%s' "$TASK_TEXT" | mimo run --format json --title "$TITLE"   # writer exits ⇒ EOF ⇒ proceeds
```

Two further consequences, both VERIFIED:

1. **Always wrap it in an external timeout anyway.**
   ```bash
   timeout --signal=TERM --kill-after=30s 900 mimo run --format json … < /dev/null || RC=$?
   ```
   (`--signal`/`--kill-after` are GNU coreutils; this machine has
   `/usr/local/bin/timeout (GNU coreutils) 9.11` — VERIFIED. macOS ships no `timeout` at all, so an
   adapter must either depend on coreutils or implement the watchdog itself.)
2. **`mimo run` exits `0` even when the only event it emitted was a fatal `error`.** VERIFIED: a 401
   from the provider produced one `{"type":"error",…}` line and `EXIT_CODE=0`. **Exit code is not a
   success signal.** Parse the stream:
   ```bash
   jq -e 'select(.type=="error")' "$RUNDIR/events.jsonl" >/dev/null && echo FAILED
   ```

### 11c. The teardown sequence

```bash
# 1. stop the current turn (VERIFIED live → true, safe when nothing is running)
curl -s -u "mimocode:$PW" -X POST "http://127.0.0.1:$PORT/session/$SID/abort"

# 2. wait for idle rather than guessing
until [ "$(curl -s -u "mimocode:$PW" "http://127.0.0.1:$PORT/session/status" | jq -r --arg s "$SID" '.[$s].type // "idle"')" = idle ]; do sleep 1; done

# 3. archive before you destroy anything
mimo export "$SID" --sanitize > "$ARCHIVE/$SID.json"       # --sanitize redacts transcript + file data

# 4. stop the server — the CHILD pid
pkill -TERM -f "bin/\.mimocode serve --port $PORT"

# 5. confirm nothing is left
lsof -nP -iTCP:"$PORT" -sTCP:LISTEN || echo "port released"
pgrep -fl "\.mimocode" || echo "no mimocode processes"

# 6. optional: forget the session
curl -s -u "mimocode:$PW" -X DELETE "http://127.0.0.1:$PORT/session/$SID"
#    or:  mimo session delete "$SID"
```

**Success:** step 5 prints both "port released" and "no mimocode processes".
**Failure:** a surviving `.mimocode` with `ppid=1` — exactly the state found on this machine.
**Fallback:** `pkill -KILL -f "\.mimocode"` only after SIGTERM has had 10 s; expect a WAL recovery on
next start.

**Do not use `cancel` semantics carelessly.** In MiMoCode's orchestrator mode, cancelling an isolated
child **deletes its git worktree and branch**. Its own design doc states the rule: only cancel an
isolated child *after its work is merged*. "Finished" is not "merged".

---

## Cross-cutting: the five things that will bite an unattended run

0. **`mimo run` with an inherited stdin hangs forever, silently.** Deterministic, undocumented, and
   the first thing an adapter will hit. `< /dev/null`, always. §11b.
1. **Claude Code inheritance is real and I watched it happen.** With `MIMOCODE_HOME` pointed at a
   scratch directory, `GET /config` on the fresh server still returned the owner's **9 MCP servers**
   (`browsermcp, clickup, drawio, gsd, n8n-mcp, playwright-persistent, sentry,
   slack-user`) and his `.claude/commands/new-skill` template, verbatim. An unattended `mimo` in the
   owner's tree gets his entire command, skill and MCP surface — including anything that spends money
   or writes to external systems.
   **And `MIMOCODE_MIMO_ONLY=true` did not stop it** in an A/B of `mimo debug config`: identical MCP
   list, identical command. Until someone finds the flag that actually works, the only boundary I
   would trust is a **container or a copied working tree**. The finer-grained switches
   (`MIMOCODE_DISABLE_CLAUDE_CODE`, `_PROMPT`, `_SKILLS`, `_COMMANDS`, `_MCP`,
   `MIMOCODE_DISABLE_EXTERNAL_SKILLS`, `MIMOCODE_DISABLE_PROVIDER_ENV`) exist in the binary's env
   table but were **not** individually verified to work.
2. **The unsecured-server default.** Without `MIMOCODE_SERVER_PASSWORD` on loopback, `serve` prints
   `Warning: MIMOCODE_SERVER_PASSWORD is not set; server is unsecured.` and serves anyway (VERIFIED —
   that exact line is in the probe's `serve.log`). The source is blunt about the consequence:
   `/file` reads and writes the project, `/pty` and `/bash-interactive` run commands, for **any
   process running as this user**. Always set a password; remember the username is `mimocode`.
3. **First-run SQLite migration** can take minutes and a startup timeout will kill it mid-flight.
4. **Telemetry is on by default** (`MIMOCODE_ENABLE_ANALYSIS` defaults true, POSTing
   `model_call` / `tool_call` / `agent_request` metrics). For the owner's repos this should be an
   explicit decision.

---

## The adapter interface this platform needs

`MimoAdapter` against the orchestrator's eleven capabilities. **Native** = one documented call.
**Emulated** = the orchestrator must add glue. **Impossible** = no honest implementation exists.

| # | Capability | Verdict | Implementation |
|---|---|---|---|
| 1 | **Preflight** | **native** | `mimo --version`; `mimo providers list`; `mimo debug paths`; plus an empty-body 401/400 probe, because `providers list` never validates the key |
| 2 | **Launch headless, structured** | **native, with one mandatory guard** | `mimo run --format json --title … --dir … < /dev/null` (**stdin must be closed or it hangs forever** — §11b), or `POST /session` + `POST /session/:id/prompt_async`. Exit code is always 0; detect failure by grepping the event stream for `type:"error"` |
| 2b | **Pinned session id** | **impossible → emulated** | `POST /session` silently drops `id`. Emulate by parsing `sessionID` from the first JSON event, or `GET /session?search=<ULID title>`. **Better handles:** pin the *message* id via `PromptInput.messageID`, and pin the *process* via `MIMOCODE_RUN_ID` + `MIMOCODE_PROCESS_ROLE`, which land in the log filename and every log line |
| 3 | **Visible, attachable terminal** | **native** | `mimo serve` + `mimo attach <url> -p <pw> -s <id>`; one server serves both faces. iTerm2/VS Code only — **not Terminal.app** |
| 4 | **Liveness / progress** | **native** | `GET /session/status` (`idle`/`busy`/`retry`/`notice`), `GET /event` SSE, `GET /session/:id/actors` (`turnCount`, `lastTurnTime`). Poll at 750 ms, the interval MiMoCode itself uses |
| 5a | **Read context fullness** | **native** | `usable` from `mimo models <provider>`; `fill` from `tokens.total` on the newest assistant message. Exact formula in §5a. Zero model calls |
| 5b | **Force compaction, with proof** | **native, best in scan** | `POST /session/:id/summarize {providerID,modelID,auto:false}`; proof = `session.time_compacting` **and** `CompactionPart.trigger == "manual"` **and** `AssistantMessage.summary == true` |
| 5c | **Handoff to a fresh session** | **native, unproven** | `POST /session {contextFrom, contextWatermark}`. Columns exist; **semantics UNKNOWN** — validate before shipping |
| 6a | **Read remaining quota** | **impossible** | No endpoint, no header, no CLI. Verified absent from a real 401's full header set. Emulate with a local `mimo stats` ledger and accept the drift |
| 6b | **Detect a limit hit in-band** | **native** | 429 → `{type:"retry", next}` on `/session/status` and `/event`; `next` is an absolute ms timestamp. Whether the provider supplies `retry-after` is **UNKNOWN** |
| 7a | **Several accounts, one machine** | **native** | one `MIMOCODE_HOME` per account; ~62 MB state each, `node_modules` shared |
| 7b | **Per-session account** | **impossible** | credentials are an instance property. One `serve` per account; route sessions to servers |
| 8 | **Deliver an instruction, with a receipt** | **native, best in scan** | `POST /session/:id/prompt_async` → 204, plus `message.updated` carrying *your* `messageID`. 20/min server-side cap. Bonus: `--role assistant`, and `POST /session/:id/ask` to probe without disturbing |
| 9a | **Answer a permission** | **native** | `GET /permission` → `POST /permission/:id/reply {reply:"once"\|"always"\|"reject"}` |
| 9b | **Answer a clarifying question** | **native, unique** | `GET /question` → `POST /question/:id/reply {answers:[["label"]]}`; a channel no other platform in this scan has. Unattended fallback: `POST /question/never-ask {enabled:true}` |
| 9c | **Sane unattended posture** | **emulated** | must be set explicitly: `POST /permission/ask-timeout {ms}` (default `null` = forever), per-session `permission` ruleset at create time |
| 10 | **Resume after crash / reboot** | **native** | `GET /session/:id/recovery` → `POST /session/:id/turn/:msgID/resume?agentID=&modelProviderID=&modelID=` (**query string**), 202/400/404/409. Survives kill and reboot via SQLite |
| 11 | **Stop cleanly** | **emulated** | `abort` → wait idle → `export --sanitize` → **`SIGTERM` the `.mimocode` child, not the `node` wrapper** → verify with `lsof`/`pgrep`. The wrapper-orphan case is real and was found live |

### Scoreboard

- **Native: 13 of 18 rows** — including three (5b, 8, 9b) that are the **best implementations of
  those axes in the entire scan**. One of the thirteen (5c, handoff) is native-but-unproven.
- **Emulated: 3** — id pinning, unattended permission posture, teardown. All cheap glue.
- **Impossible: 2** — **reading remaining quota**, and **per-session accounts within one instance**.

---

## Support tier

**Tier 2 — workable with emulation.**

**Not tier 1, for exactly one reason:** axis E. The owner stated quota-awareness as non-negotiable,
and MiMo cannot report remaining capacity by any means — no endpoint, no header, no CLI, verified
against a real response's complete header set. Everything else about this platform is tier-1 or
better; this single gap caps it.

**Not tier 3 either, and the distinction matters.** Tier 3 is "can run a task but cannot be
supervised." MiMoCode is the *most supervisable* executor in this scan: it answers its own questions
over HTTP, compacts on command and proves it with a database column, takes an instruction with a
receipt, and resumes an interrupted turn without inventing a user message. On axes C, D and G it is
ahead of Claude Code.

**The tier-2 contract, concretely:**

- **Give it work where running out of credit is survivable.** Never the lane whose quota the
  orchestrator predicts. Keep that role on a platform with a usage endpoint (Claude Code's
  `GET https://api.anthropic.com/api/oauth/usage` remains the reference).
- **Budget it locally.** Record cumulative `mimo stats` cost at the start of each billing period, set
  a conservative hard stop, and accept that the ledger drifts against off-machine usage.
- **Back off reactively.** `{type:"retry", next}` is the only real capacity signal; park the lane
  until `next` and do not start new work on that account.
- **One `mimo serve` per account**, and **every `mimo run` gets `< /dev/null` and an external
  timeout** (§11b).
- **Pin `0.1.14`.** A 0.1.x line, ~weekly releases, 1,018 open issues. Flag surfaces will move.
- **Re-mint the owner's key before anything runs.** The stored `tp-…` credential is dead.
- **Treat Claude Code inheritance as unbounded until a container is in place** — `MIMOCODE_MIMO_ONLY`
  did not stop it here.

**Promotion to tier 1 requires exactly one thing:** a programmatic read of remaining Token Plan
credits. If Xiaomi ships a usage endpoint — or if an authenticated JSON endpoint behind the console
SPA turns out to expose balance (open question #3 in the profile) — MiMoCode becomes the strongest
executor in this scan, full stop.

---

## Appendix A — a paste-ready lane bootstrap

```bash
#!/usr/bin/env bash
set -euo pipefail
ACCOUNT="${1:?account name}"; PORT="${2:?port}"
ORCH_STATE="${ORCH_STATE:?}"; MIMO="$(command -v mimo)"

export MIMOCODE_HOME="$ORCH_STATE/mimo/$ACCOUNT"
export MIMOCODE_DISABLE_CLAUDE_IMPORT=1
export MIMOCODE_ENABLE_ANALYSIS=false
export MIMOCODE_DISABLE_AUTOUPDATE=true
export MIMOCODE_COMPACTION_TRIGGER_RATIO=0.75
export MIMOCODE_SERVER_USERNAME=mimocode
export MIMOCODE_SERVER_PASSWORD="$(cat "$MIMOCODE_HOME/.pw")"
AUTH=(-u "mimocode:$MIMOCODE_SERVER_PASSWORD"); B="http://127.0.0.1:$PORT"

mkdir -p "$MIMOCODE_HOME"
"$MIMO" debug paths >/dev/null            # warm the one-time SQLite migration BEFORE the timeout matters

"$MIMO" serve --port "$PORT" --hostname 127.0.0.1 >"$MIMOCODE_HOME/serve.log" 2>&1 &
until curl -sf "${AUTH[@]}" -o /dev/null "$B/path"; do sleep 0.5; done

# unattended posture — neither default is safe
curl -s "${AUTH[@]}" -X POST "$B/permission/ask-timeout" -H 'content-type: application/json' -d '{"ms":120000}' >/dev/null
# never-ask stays FALSE because this supervisor answers questions itself (§9b).
# Flip it to true only for a lane with nobody watching.
curl -s "${AUTH[@]}" -X POST "$B/question/never-ask"     -H 'content-type: application/json' -d '{"enabled":false}' >/dev/null

# prove the credential before queuing a single ticket
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$MIMO_BASE_URL/anthropic/v1/messages" \
        -H "x-api-key: $MIMO_KEY" -H 'content-type: application/json' -d '{}')
[ "$code" = 401 ] && { echo "FATAL: MiMo key is dead ($ACCOUNT)"; exit 1; }

echo "lane $ACCOUNT up on $B  (attach: mimo attach $B -p \$MIMOCODE_SERVER_PASSWORD)"
```

## Appendix B — every claim I could not settle

| # | Open question | Why it matters |
|---|---|---|
| 1 | Does the MiMo endpoint emit `retry-after` on a **real** 429? | If not, `retry.next` is MiMoCode's own backoff, not the provider's truth — the orchestrator's park-until time would be a guess |
| 2 | `contextFrom` + `contextWatermark` semantics on `POST /session` | Decides whether a true handoff (§5e) is usable or just a column |
| 3 | Is Token Plan **credit balance** reachable behind the console SPA? | The single thing standing between tier-2 and tier-1 |
| 4 | Which flag actually severs Claude Code inheritance? `MIMOCODE_MIMO_ONLY` did not | Determines whether an unattended lane needs a container |
| 5 | Does `mimo run` also block on stdin when it *succeeds*, or only before the first model call? | Only the failure path was timed. If the read happens once at startup (as the source implies), `< /dev/null` covers both — but that was not measured on a successful turn |
| 6 | Does `MIMOCODE_EXPERIMENTAL_ORCHESTRATOR` expose its eight `session` verbs over **HTTP**, or only to the in-session agent? | If HTTP, MiMoCode ships half this orchestrator already |
| 7 | `packages/containers` / `flake.nix` — is there a supported image? | The only boundary worth trusting for #4 |

## Appendix C — what was actually executed on this machine

**Ran (VERIFIED):** `npm i @mimo-ai/cli@0.1.14` into `…/scratchpad/mimo-probe`; `mimo --version`,
`--help`, and `--help` for `run`, `serve`, `attach`, `session`, `session list`, `db`, `export`, `acp`,
`llm-server`, `debug`, `agent`, `providers`, `stats`; `mimo debug paths`; `mimo debug config` (A/B
with and without `MIMOCODE_MIMO_ONLY`); `mimo models`; `mimo stats`; `mimo providers list` (with and
without an injected credential); `mimo db path`; `mimo db` for `sqlite_master`, `pragma_table_info`
on `session`/`message`/`inbox`/`permission`, and the context-fill and compaction-proof queries;
`mimo session list --format json`; `mimo run --format json` four times against a **bogus** key; a
fifth `mimo debug paths` with `MIMOCODE_RUN_ID` / `MIMOCODE_PROCESS_ROLE` set, and inspection of the
resulting log filename and first log line.

**HTTP against a live `mimo serve` on 127.0.0.1:47513 (VERIFIED):** `/path`, `/doc`, `/config`,
`/project`, `/pty`, `/experimental/console`, `/session` (GET, POST, POST-with-`id`, `?search=`),
`/session/:id`, `/session/:id/message`, `/recovery`, `/todo`, `/actors`, `/diff`, `/abort`,
`/summarize` (400 probe), `/prompt_async` (400 probe), `/session/status`, `/permission`,
`/permission/ask-timeout` (GET+POST), `/permission/skip-all` (GET+POST),
`/permission/auto-approve-delete`, `/question` (GET), `/question/never-ask` (GET+POST), `/event`
(SSE), `/workflows` (400 probe), and Basic-auth negative tests for five username forms and Bearer.

**Process-level (VERIFIED):** `ps`/`lsof` on the `node` wrapper vs the `.mimocode` child;
`kill -TERM` on an orphaned server and confirmation the port was released; **eight timed `mimo run`
probes** varying stdin (inherited vs `< /dev/null`), `MIMOCODE_HOME` (shared with a live `serve` vs
isolated) and stdout target, which isolated stdin as the sole cause of the hang.

**Read in the 0.1.14 binary or its saved route source (VERIFIED):** the Basic-auth username
expression; `SessionStatus` zod union; `AssistantMessage` zod; `CompactionPart` zod; `PromptInput`
zod; `PermissionReplyBody` enum; the question reply call shape; `contextWindow`/`usable`/autocompact
functions; `retry.ts` retry ceilings and `retry-after` precedence; the `serve` SIGINT/SIGTERM
handlers; the full `MIMOCODE_*` environment-variable table; the Terminal.app statement.

**Deliberately not done:** any real model call; any GUI window; any write to the owner's `~/.claude`,
`~/.config`, `~/.zshrc` or repository configuration.
