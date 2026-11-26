# opencode — implementation spike for the provider-agnostic orchestrator

**Date:** 2026-09-19. **Version under test:** `opencode-ai@1.18.31` (Bun-compiled single binary,
darwin arm64, 144,470,498 bytes).

**How this was produced.** The binary from the earlier profile run was re-used from the sandbox at
`…/scratchpad/oc-sandbox`, with `HOME`, `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, `XDG_CACHE_HOME` and
`XDG_STATE_HOME` redirected into it. Eight servers were started and stopped on ports 4321–4340, the
live OpenAPI document was re-pulled (478,968 bytes), sessions were created, renamed, prompted,
permission-scoped and deleted over HTTP, the SQLite store was read with `sqlite3`, and the skill
discovery routine was read out of the binary's own strings and then tested against five candidate
directories. **No provider was ever authenticated, so no model call was made and none of the owner's
quota was spent.** The owner's `~/.config/opencode/opencode.json` is unchanged (`{"mcp":{}}`,
mtime 2026-07-11); `~/.local/share/opencode/` still contains only the two empty directories the npm
postinstall created; `~/.claude/skills` still holds its 91 entries and was only ever read.

**Tags.** **VERIFIED** = executed on this machine today, or read in the OpenAPI document served by
the running binary / in the binary's own strings. **CLAIMED** = docs or README only.
**UNKNOWN** = could not establish.

---

## Read this before the recipes: seven corrections to the platform profile

The profile (`opencode.md`) was written from the served schema. Several things the schema promises
are **not implemented in the shipped 1.18.31 binary**, and two of them sit directly on the owner's
non-negotiable axes. Every item below was executed.

| # | Profile said | Actually observed on 1.18.31 | Impact |
|---|---|---|---|
| 1 | `POST /api/session/{id}/compact` is a bodyless trigger — "the cleanest answer to this axis in the whole field" | **HTTP 503** `{"_tag":"ServiceUnavailableError","message":"Session compact is not available yet","service":"session.compact"}` | Axis D. Use the **v1** `POST /session/{id}/summarize` instead |
| 2 | `POST /api/session/{id}/wait` blocks until idle, "so an orchestrator does not have to poll" | **HTTP 503** `"Session wait is not available yet"`, `service: session.wait` | Axis G. You must poll or hold SSE |
| 3 | "Pick v2 and never mix" | **`DELETE` and `PATCH` exist only on v1 `/session/{sessionID}`.** v2 `/api/session/{sessionID}` is `get` only | Mixing is mandatory, not optional |
| 4 | `/tui/append-prompt` + `/tui/submit-prompt` are "the exact pair the old harness lacked" | Both return **`true` with HTTP 200 when no TUI is attached at all**, and do nothing | This *is* the FIELD-NOTES defect ("a nudge that cannot submit stranded text"), reproduced on opencode. Never use `/tui/*` to deliver work |
| 5 | `GET /pty/{ptyID}` "reports the exit code once exited" | On exit the record is **deleted**: `{"_tag":"PtyNotFoundError"}`. `status:"exited"` and `exitCode` are in the schema but unreachable by polling | Hold the WebSocket, or watch the exposed `pid` |
| 6 | "The owner's GSD skill library in `~/.claude/skills` is visible to opencode today, without migration" | **False on 1.18.31.** Five layouts tested, four found nothing (see recipe 0.3) | GSD needs a symlink farm, one line per skill |
| 7 | Malformed `OPENCODE_PERMISSION` is "silently skipped with a log warning" | Silently skipped with **no warning at all** — not on stdout, not on stderr, not in `~/.local/share/opencode/log/opencode.log`. `config.permission` becomes `null` (= permissive defaults) and the server starts normally | Validate the JSON in the supervisor before launch |

Two further corrections of shape, both VERIFIED:

- `GET /provider` returns **`{all:[…222…], connected:[…], default:{…}}`**, not `{providers:[…]}`.
- `POST /api/session` declares `additionalProperties:false` but **silently drops unknown keys and
  returns 200** (a `title` in the body is discarded; the session gets `"New session - <ISO>"`).
  `PATCH /session/{id}` by contrast validates strictly and returns
  `{"name":"BadRequest","data":{"message":"Missing key\n  at [\"permission\"][0][\"permission\"]"}}`.
  Do not trust a 200 from the create endpoint to mean your body was understood.

---

## Recipe 0 — the launch preamble every recipe assumes

### 0.1 Environment (VERIFIED)

```bash
export OPENCODE_DB=/var/orch/opencode/<account>/opencode.db     # store isolation
export OPENCODE_CONFIG_DIR=/var/orch/opencode/<account>/config  # config isolation
export OPENCODE_SERVER_PASSWORD="$(openssl rand -hex 24)"       # REQUIRED, see 0.2
export OPENCODE_SERVER_USERNAME=opencode                        # default is already 'opencode'
export OPENCODE_DISABLE_AUTOUPDATE=1
export OPENCODE_DISABLE_AUTOCOMPACT=1        # only if the orchestrator owns compaction timing
export OPENCODE_DISABLE_SHARE=1
export OPENCODE_PERMISSION='{"bash":"ask","edit":"allow","external_directory":"deny","webfetch":"deny"}'
```

Confirmed effects, read back from `GET /config` on a live server:

| Variable | `GET /config` shows | Tag |
|---|---|---|
| `OPENCODE_PERMISSION` (valid JSON) | `"permission":{"edit":"allow","bash":"ask","external_directory":"deny","webfetch":"deny"}` | VERIFIED |
| `OPENCODE_PERMISSION` (malformed) | `"permission":null` — silent | VERIFIED |
| `OPENCODE_DISABLE_AUTOCOMPACT=1` | `"compaction":{"auto":false}` | VERIFIED |
| `OPENCODE_DISABLE_AUTOUPDATE=1` | `"autoupdate":null` — **does not appear as `false`** | VERIFIED |
| `OPENCODE_DISABLE_SHARE=1` | `"share":null` — **does not appear as `"disabled"`** | VERIFIED |

**Because the last two do not surface in `/config`, the supervisor cannot verify them by read-back.**
Set them in the config file as well, where they *are* readable:

```bash
cat > "$OPENCODE_CONFIG_DIR/opencode.json" <<'JSON'
{ "autoupdate": false, "share": "disabled", "compaction": { "auto": false, "reserved": 10000 } }
JSON
```

**Validate the permission JSON before exporting it** — this is the whole mitigation for correction 7:

```bash
printf '%s' "$OPENCODE_PERMISSION" | jq -e . >/dev/null \
  || { echo "FATAL: OPENCODE_PERMISSION is not valid JSON; refusing to launch"; exit 78; }
```

### 0.2 Start the server (VERIFIED)

```bash
opencode serve --port 4321 --hostname 127.0.0.1 >"$LOGDIR/serve-4321.log" 2>&1 &
```

Success, on stdout: `opencode server listening on http://127.0.0.1:4321`.
Failure to secure it, on stdout, **as a warning only, exit code still 0**:
`Warning: OPENCODE_SERVER_PASSWORD is not set; server is unsecured.`

With the password set, an unauthenticated `GET /config` returns **401** and
`curl -u opencode:$OPENCODE_SERVER_PASSWORD` returns the config (both VERIFIED). Every `curl` below
omits `-u` for readability; in production every call carries it.

Never pass `--mdns` (it defaults the hostname to `0.0.0.0`) and never bind anything but `127.0.0.1`.

### 0.3 Make the GSD skills visible — the only layout that works (VERIFIED)

The discovery routine, read verbatim out of the binary
(`var bA=".claude",xA=".agents",GA="skills/**/SKILL.md",SA="{skill,skills}/**/SKILL.md",KA="**/SKILL.md"`),
scans `$HOME/.claude`, `$HOME/.agents`, every `.claude`/`.agents` walking up from the working
directory to the worktree root, then the opencode config directories, then `config.skills.paths`.
**Four of those five produced nothing when tested.** Each row is one server restart with the file in
place:

| Layout tested | Discovered? | Tag |
|---|---|---|
| `$HOME/.claude/skills/<name>/SKILL.md` (real `gsd-plan-phase`, `gsd-execute-phase`) | **no** | VERIFIED |
| `$HOME/.agents/skills/<name>/SKILL.md` | **no** | VERIFIED |
| `<project>/.claude/skills/<name>/SKILL.md` (plain dir **and** inside a git worktree) | **no** | VERIFIED |
| `config.skills.paths: ["<dir>"]` via `OPENCODE_CONFIG_CONTENT` — flat, nested under `skills/`, and pointed at the real `~/.claude/skills` | **no** (the path is echoed back by `GET /config`, and still nothing loads) | VERIFIED |
| **`$XDG_CONFIG_HOME/opencode/skills/<name>/SKILL.md`** | **yes** | VERIFIED |

Root cause UNKNOWN — the code path exists and the config is accepted; it simply does not yield
skills in 1.18.31. **Symlinks into the config directory do work**, which makes the fix one line per
skill and leaves `~/.claude/skills` untouched:

```bash
mkdir -p "$OPENCODE_CONFIG_DIR/skills"
for s in "$HOME/.claude/skills"/*/; do
  ln -sfn "${s%/}" "$OPENCODE_CONFIG_DIR/skills/$(basename "$s")"
done
```

Proof it worked, executed here with the owner's two real GSD skills:

```
GET /api/skill → ["customize-opencode","gsd-execute-phase","gsd-plan-phase","probe-cfg-skill"]
```

Whether a GSD skill *behaves* correctly once loaded — its `allowed-tools` frontmatter names Claude
Code tool names (`Read`, `Write`, `Bash`, `Task`) and opencode's registered tool ids are
`["invalid","question","bash","read","glob","grep","edit","write","task","webfetch","todowrite",
"websearch","skill","apply_patch"]` (VERIFIED) — is **UNKNOWN** and needs a paid trial run.

---

## Recipe 1 — Preflight: installed, authenticated, which account

**VERIFIED. Not installed on this machine** outside the sandbox: `which opencode` finds nothing.

```bash
# 1a. binary present and pinned
opencode --version                       # → 1.18.31   (exit 0)

# 1b. server reachable (start it first, recipe 0.2)
curl -fsS -u "$U:$P" http://127.0.0.1:4321/global/health
# → {"healthy":true,"version":"1.18.31"}

# 1c. credentials actually present
opencode providers list
# 0 credentials  → ┌  Credentials ~/.local/share/opencode/auth.json
#                  └  0 credentials

# 1d. which provider the orchestrator may use
curl -fsS -u "$U:$P" http://127.0.0.1:4321/provider | jq -c '.connected'

# 1e. which console account/org is active (opencode Console only)
curl -fsS -u "$U:$P" http://127.0.0.1:4321/experimental/console/orgs
# → {"orgs":[]}   when no console account is linked
curl -fsS -u "$U:$P" http://127.0.0.1:4321/experimental/console
# → {"consoleManagedProviders":[],"switchableOrgCount":0}
```

**Success:** `healthy:true`, and `.connected` contains the provider id this ticket is configured for.

**Failure, and two traps:**

- `opencode providers list` prints the path **`~/.local/share/opencode/auth.json`**, which **does not
  exist** — credentials live in the `credential` table of `opencode.db`. Do not health-check that
  file. (VERIFIED: the directory listing shows only `opencode.db`, `-wal`, `-shm`, `log/`, `repos/`.)
- **`.connected` returned `["opencode"]` on a server with zero credentials** (VERIFIED). OpenCode Zen
  is listed as connected whether or not you can pay for it. `.connected` alone is **not** an
  authentication check.

**The only preflight that actually proves auth** is a one-token call on the target model, which costs
money. Accept that, and make it the orchestrator's cheapest possible prompt, once per server boot —
not once per ticket.

**Fallback if `providers list` is ambiguous:** read the store directly.

```bash
sqlite3 "$OPENCODE_DB" \
  "select id, integration_id, label, connector_id, active from credential;"
```

---

## Recipe 2 — Start a task headless, with a pinned session id, structured output

**Do not use `opencode run` for this.** See the failure note at the end of this recipe. Use HTTP.

### 2a. Create the session under the orchestrator's own id (VERIFIED)

The id is the orchestrator's, constrained only by `pattern:"^ses"`. The ticket id *is* the session id.

```bash
curl -fsS -u "$U:$P" -X POST http://127.0.0.1:4321/api/session \
  -H 'content-type: application/json' \
  -d '{"id":"ses_TICKET1234",
       "agent":"build",
       "model":{"providerID":"anthropic","id":"claude-sonnet-4-6"},
       "location":{"directory":"/repo/path"}}'
```

Observed response (executed):

```json
{"data":{"id":"ses_spikerecipe000000000001","projectID":"global","cost":0,
 "tokens":{"input":0,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},
 "time":{"created":1789824630750,"updated":1789824630750},
 "title":"New session - 2026-09-19T13:30:30.750Z",
 "location":{"directory":"…/proj"}}}
```

Accepted body keys are exactly `id`, `agent`, `model` (`{providerID,id,variant}`), `location`
(`{directory,workspaceID}`). **`title` is not among them and is silently dropped** — set it
afterwards (recipe 2b).

**Success:** `data.id` equals the id you sent. **Failure:** anything else — and remember a 200 does
*not* prove the rest of your body was understood; verify the fields you care about in the response.

### 2b. Label it for the humans (VERIFIED — v1 only)

```bash
curl -fsS -u "$U:$P" -X PATCH http://127.0.0.1:4321/session/ses_TICKET1234 \
  -H 'content-type: application/json' -d '{"title":"TICKET-1234 add parquet connector"}'
# → {"id":"ses_TICKET1234","title":"TICKET-1234 add parquet connector", …}
```

### 2c. Pin per-session guardrails (VERIFIED — v1 only, and better than the env var)

`PATCH /session/{id}` accepts a `PermissionRuleset`: an array of
`{permission, pattern, action}` with `action ∈ {allow, deny, ask}`. This is **per session**, so two
tickets on one server can carry different policies — the env var cannot do that.

```bash
curl -fsS -u "$U:$P" -X PATCH http://127.0.0.1:4321/session/ses_TICKET1234 \
  -H 'content-type: application/json' -d '{"permission":[
       {"permission":"bash","pattern":"**","action":"ask"},
       {"permission":"edit","pattern":"**","action":"allow"},
       {"permission":"external_directory","pattern":"**","action":"deny"}]}'
```

Read back with `GET /session/ses_TICKET1234 | jq .permission` — observed identical to what was sent.
A wrong shape is **rejected loudly** with a JSON pointer to the offending key, unlike the env var.

### 2d. Start the work and stream it (VERIFIED)

```bash
# subscribe first, so nothing is missed
curl -N -u "$U:$P" "http://127.0.0.1:4321/api/session/ses_TICKET1234/event?after=0" \
  > "$LOGDIR/ses_TICKET1234.ndjson" &

curl -fsS -u "$U:$P" -X POST http://127.0.0.1:4321/api/session/ses_TICKET1234/prompt \
  -H 'content-type: application/json' \
  -d '{"id":"msg_TICKET1234_0001",
       "prompt":{"text":"<the ticket body>"},
       "delivery":"queue","resume":true}'
```

`resume:true` starts the agent loop. `resume:false` admits the input **without** running it — use it
to pre-load a queue of steps and release them later.

**Structured output:** the SSE stream is newline-delimited JSON, one `data: {…}` per event, with
`: heartbeat` comments so a dead stream is distinguishable from a quiet one (VERIFIED, observed).

### 2f. The `opencode run` fallback, and why it is a fallback

`opencode run [message..]` does support `--session`, `--format json`, `--agent`, `-m`, `--title`,
`--attach`, `--dir`, `--auto` (VERIFIED, `--help`). Its JSON is NDJSON on stdout carrying `sessionID`
on every line:

```json
{"type":"error","timestamp":1789824976823,"sessionID":"ses_runprobe00000000000001","error":{"name":"UnknownError","data":{"message":"Unexpected server error. Check server logs for details.","ref":"err_fa7cbb69"}}}
```

Three verified reasons not to build on it:

1. **`--session` with an unknown id fails on stderr, not as a JSON event**: empty stdout,
   `Error: Session not found`, exit 1. A JSON-only consumer sees nothing at all.
2. **Errors are opaque**: the event carries `ref: err_fa7cbb69` and the real cause is only in
   `~/.local/share/opencode/log/opencode.log`. The supervisor must join on that ref.
3. **It hung, repeatedly and finally always.** Early in this session `run --session … --format json
   -m anthropic/claude-sonnet-4-6` returned an error event in seconds. By the end of the session the
   same command hung with **zero bytes on stdout and stderr, exit 124 under an external timeout, in
   6 of 6 attempts** — with `--attach` and without it, with `--dir` and without it, with `--session`
   and without it, and from a **completely pristine state directory**. Throughout, the HTTP server
   answered `/global/health`, accepted prompts and returned `admittedSeq`, and `opencode --version`
   and `opencode session list` both exited 0. Root cause **UNKNOWN**.

**Therefore: every `opencode run` invocation gets a hard wall-clock timeout, and the adapter treats
`run` as a convenience for humans, never as the execution path.**

---

## Recipe 3 — The same task in a terminal the owner can type into

**The supported shape: one server, many attached TUIs.** (VERIFIED, `opencode attach --help`.)

```bash
opencode attach http://127.0.0.1:4321 \
  --session ses_TICKET1234 \
  --password "$OPENCODE_SERVER_PASSWORD" \
  --username opencode
```

Relevant flags, quoted from the installed binary:

```
  -c, --continue      continue the last session
  -s, --session       session id to continue
      --fork          fork the session when continuing (use with --continue or --session)
      --dir           directory to run in
  -p, --password      basic auth password (defaults to OPENCODE_SERVER_PASSWORD)
  -u, --username      basic auth username (defaults to OPENCODE_SERVER_USERNAME or 'opencode')
      --mini          start the minimal interactive interface
      --no-replay     disable mini session history replay on resume and after resize
      --replay-limit  cap visible mini replay to the newest N messages
```

Wrapped for iTerm2, matching the owner's existing launcher convention:

```bash
osascript -e 'tell application "iTerm2" to tell current window to create tab with default profile' \
          -e 'tell application "iTerm2" to tell current session of current tab of current window to write text "opencode attach http://127.0.0.1:4321 --session ses_TICKET1234"'
```

**Success:** the TUI renders and the session's history replays into it. The owner types; the
supervisor keeps streaming the same events over SSE — both are clients of one server, so neither
steals the session from the other.

**Failure:** `attach` exits immediately on a bad URL or wrong password.

**The trap (VERIFIED, and it is the important part of this recipe):**

```bash
curl -X POST http://127.0.0.1:4321/tui/append-prompt -d '{"text":"nudge"}'   # → true  [200]
curl -X POST http://127.0.0.1:4321/tui/submit-prompt -d '{}'                 # → true  [200]
```

**Both returned `true` and HTTP 200 with no TUI attached to that server at all.** This is precisely
the defect `plugins/harness/docs/FIELD-NOTES.md` records against the current harness — a nudge that
reports success and strands the text. It is present here too, and it is worse, because the `true`
looks like an acknowledgement. **`/tui/*` is a courtesy for a human who is already watching. It is
never a delivery mechanism.** Delivery is recipe 8.

**Fallback when no terminal emulator is available — own a PTY (VERIFIED):**

```bash
curl -fsS -u "$U:$P" -X POST http://127.0.0.1:4321/pty -H 'content-type: application/json' \
  -d '{"command":"/bin/sh","args":["-c","…"],"cwd":"/repo/path","title":"ticket-1234"}'
# → {"id":"pty_0b9e21319001ziGOUDmTiRn6d2","title":"long","command":"/bin/sh",
#    "args":["-c","sleep 25","-l"],"cwd":"…","status":"running","pid":54854}
```

`GET /pty` lists them, `PUT /pty/{id}` resizes (`{"cols":120,"rows":40}`), `DELETE /pty/{id}` → `true`,
`GET /pty/{id}/connect` upgrades to a WebSocket carrying output and accepting input, and
`POST /pty/{id}/connect-token` mints a single-use ticket. `GET /pty/shells` enumerates acceptable
shells. All VERIFIED.

Two observed gotchas: **opencode appends `-l` to your `args`** (the request above came back as
`["-c","sleep 25","-l"]`), and **the record is destroyed the moment the process exits** — a later
`GET /pty/{id}` returns `{"_tag":"PtyNotFoundError"}`, so the `exitCode` field in the `Pty` schema is
unreachable by polling. Keep the WebSocket open, or poll the exposed `pid` with `kill -0`.

---

## Recipe 4 — Alive, working, waiting, or finished — from outside

Four independent signals; use them together, because no single one is complete.

```bash
# 1. per-session status map — busy / idle / retry
curl -fsS -u "$U:$P" http://127.0.0.1:4321/session/status
# observed on an idle server: {}

# 2. what this process is actively running
curl -fsS -u "$U:$P" http://127.0.0.1:4321/api/session/active
# observed: {"data":{}}   ;  running: {"data":{"ses_…":{"type":"running"}}}

# 3. is anyone waiting on a human?
curl -fsS -u "$U:$P" http://127.0.0.1:4321/api/session/ses_TICKET1234/permission  # → {"data":[]}
curl -fsS -u "$U:$P" http://127.0.0.1:4321/api/session/ses_TICKET1234/question    # → {"data":[]}

# 4. is the server itself alive?
curl -fsS -u "$U:$P" -N http://127.0.0.1:4321/api/event   # server.connected, then ": heartbeat"
```

`SessionStatus` is exactly three shapes (VERIFIED, schema):

```json
{"type":"idle"}
{"type":"busy"}
{"type":"retry","attempt":0,"message":"…","next":0,
 "action":{"reason":"…","provider":"…","title":"…","message":"…","label":"…","link":"…"}}
```

`next` is `integer, minimum 0`; whether it is a delay in ms or an absolute epoch is **UNKNOWN** — it
could not be established without provoking a real 429.

**The decision table the adapter should implement:**

| Observation | State |
|---|---|
| `/session/status[id] == {"type":"busy"}` | working |
| `{"type":"retry"}` | throttled — recipe 6 |
| `{"type":"idle"}` **and** `permission` or `question` non-empty | **waiting on a human** — recipes 9 |
| `{"type":"idle"}`, both empty, last event is `session.idle` | finished |
| id absent from the map entirely | never started, or owned by another process |
| SSE heartbeats stop | the server died, not the session |

**`POST /api/session/{id}/wait` cannot be used.** It is documented ("Wait for a session agent loop to
become idle", responses `204/400/401/404/503`) and returns **503
`"Session wait is not available yet"`** (VERIFIED, executed). Poll `/session/status` on an interval,
or hold the per-session SSE stream and act on `session.idle`.

**Note on the empty map.** `/session/status` returned `{}` for sessions that exist and have history.
It reports only sessions this process currently owns. Absence means "not running here", never
"finished" — always cross-check with the session's own history.

---

## Recipe 5 — Read context fullness, force a compaction, prove it happened

### 5a. Read how full the window is — computed, never reported (VERIFIED)

There is no "context is 74% full" field. All three inputs are exposed, and the binary's own decision
function is `SessionCompaction.isOverflow({cfg, tokens, model, outputTokenMax})`, so a supervisor
replicating this will agree with opencode:

```bash
# the ceiling
curl -fsS -u "$U:$P" http://127.0.0.1:4321/provider \
  | jq -r '.all[]|select(.id=="anthropic")|.models["claude-sonnet-4-6"].limit'
# observed: {"context":1000000,"output":128000}

# the headroom opencode itself subtracts
curl -fsS -u "$U:$P" http://127.0.0.1:4321/config | jq -c '.compaction'

# the occupancy: last session.next.step.ended on the stream
#   data.tokens = {input, output, reasoning, cache:{read, write}}
```

```
occupancy = tokens.input + tokens.cache.read
headroom  = limit.context - limit.output - (compaction.reserved // 10000)
fullness  = occupancy / headroom
```

Cheapest cross-check, no HTTP, works even with the server down:

```bash
sqlite3 -json "$OPENCODE_DB" \
  "select tokens_input, tokens_cache_read, tokens_output, cost, time_compacting
     from session where id='ses_TICKET1234';"
```

### 5b. Force it — **v1, because v2 is not implemented** (VERIFIED)

```bash
# ✗ DO NOT: returns 503 on 1.18.31
curl -X POST http://127.0.0.1:4321/api/session/ses_TICKET1234/compact
# → {"_tag":"ServiceUnavailableError","message":"Session compact is not available yet",
#    "service":"session.compact"}   [503]

# ✓ DO: v1, and the body is required
curl -fsS -u "$U:$P" -X POST http://127.0.0.1:4321/session/ses_TICKET1234/summarize \
  -H 'content-type: application/json' \
  -d '{"providerID":"anthropic","modelID":"claude-sonnet-4-6","auto":false}'
```

Schema: `{providerID, modelID, auto?}`, `providerID` and `modelID` both **required**
(`additionalProperties:false`). **`modelID` is the bare id, not `provider/model`** — this was learned
the expensive way. Passing `"modelID":"anthropic/claude-sonnet-4-6"` returns HTTP 500
`{"name":"UnknownError","data":{"ref":"err_04055fef"}}` on the wire, and only the server log says why:

```
level=ERROR ref=err_04055fef error="ProviderModelNotFoundError: Model not found:
anthropic/claude-sonnet-4-6. Did you mean: claude-sonnet-4-6?"  … at SessionHttpApi.summarize
```

**Every 500 from this API carries a `ref` and nothing else. The supervisor must tail
`$XDG_DATA_HOME/opencode/log/opencode.log` and join on `ref=` to get a real error message.** Treat
that log as part of the protocol.

### 5c. Prove it — three independent proofs (schemas VERIFIED)

1. **The event carries who asked.** `session.next.compaction.started.data` is
   `{timestamp, sessionID, messageID, reason}` with **`reason` an enum of exactly `"auto" | "manual"`**.
   The orchestrator's own compaction is distinguishable from one opencode started by itself.
   `session.next.compaction.ended` adds **`text`** (the summary written) and `recent`. There is also
   a streaming `.delta` and a coarse `session.compacted` carrying only `{sessionID}`.
2. **The database records the cut point.**
   ```bash
   sqlite3 -json "$OPENCODE_DB" \
     "select session_id, baseline_seq from session_context_epoch where session_id='ses_TICKET1234';"
   ```
   DDL, read from `sqlite_master`:
   `session_context_epoch(session_id text PRIMARY KEY, baseline text NOT NULL, snapshot text NOT NULL, baseline_seq integer NOT NULL)`.
   `baseline_seq` must be strictly greater after than before. `session.time_compacting` also moves.
3. **Read the live window back.** `GET /api/session/{id}/context` — "the active context messages for
   a session (all messages after the last compaction)". Returned `{"data":[]}` for a fresh session
   here (VERIFIED). Compare `length` before and after.

**Failure:** 503 (you used v2), or 500 with a `ref` (bad `modelID`, or no credentials), or
`baseline_seq` unchanged (nothing happened, whatever the HTTP status said).

**Fallback if compaction is unreachable:** own the boundary instead of the mechanism. Leave
`OPENCODE_DISABLE_AUTOCOMPACT=1`, watch `fullness` from 5a, and at the threshold **end the session
and open a successor** — `POST /api/session` with a new id, seeded with a handoff written by the
supervisor, `parent_id` recorded in the orchestrator's own ledger. The event-sourced history (recipe
10) makes this cheap, and unlike compaction it cannot half-fail.

**Custom compaction, if you own the plugin layer** (CLAIMED from `@opencode-ai/plugin@1.18.31`
typings, not exercised here):
`experimental.session.compacting(input:{sessionID}, output:{context:string[], prompt?:string})` to
replace the compaction prompt, and
`experimental.compaction.autocontinue(input:{…, overflow}, output:{enabled})` to suppress the
synthetic "continue" turn. `config.agent.compaction` is a full `AgentConfig`, so compaction can run
on a cheap model while the main loop runs on an expensive one.

---

## Recipe 6 — Quota and reset time

**opencode cannot answer this, and that is a VERIFIED negative rather than an unknown.** Every
distinct `"key"` string in the 478,968-byte served OpenAPI document was extracted (1,019 unique
names) and matched against `quota|ratelimit|rate_limit|remaining|reset|balance|credit|retry_after`.
The only hits are `WorktreeResetFailedError` and `WorktreeResetInput`. **No endpoint anywhere reports
a limit, a window, a balance, or a reset time.**

What exists is spend accounting, after the fact (VERIFIED, executed):

```bash
opencode stats --days 7 --models
# ┌ OVERVIEW ┐ Sessions 9 │ Messages 8 │ Days 1
# ┌ COST & TOKENS ┐ Total Cost $0.00 │ Avg Cost/Day $0.00 │ Input 0 │ Cache Read 0 …
```

It is local arithmetic over SQLite, so the supervisor can do it faster itself:

```bash
sqlite3 -json "$OPENCODE_DB" "select sum(cost) spent,
  sum(tokens_input) tin, sum(tokens_cache_read) tcr, count(*) n
  from session where time_updated > strftime('%s','now','-5 hours')*1000;"
```

### 6a. The pre-flight check must query the provider, not opencode

Key the check on `session.model.providerID`, which opencode *does* tell you. Provider → env var, read
live from `GET /provider` (VERIFIED, 222 providers):

| providerID | Name | env |
|---|---|---|
| `anthropic` | Anthropic | `ANTHROPIC_API_KEY` |
| `openai` | OpenAI | `OPENAI_API_KEY` |
| `opencode` | OpenCode Zen | `OPENCODE_API_KEY` |
| `opencode-go` | OpenCode Go | `OPENCODE_API_KEY` |
| `xiaomi-token-plan-sgp` / `-ams` / `-cn` | Xiaomi Token Plan | `XIAOMI_API_KEY` |
| `kimi-code-plan-global` / `-cn` | Kimi For Coding | `KIMI_API_KEY` |
| `zai-coding-plan`, `zai` | Z.AI Coding Plan | `ZHIPU_API_KEY` |
| `minimax-coding-plan`, `minimax` | MiniMax | `MINIMAX_API_KEY` |
| `google` | Google | `GOOGLE_API_KEY`, `GOOGLE_GENERATIVE_AI_API_KEY`, `GEMINI_API_KEY` |
| `github-copilot` | GitHub Copilot | `GITHUB_TOKEN` |

For `anthropic`, the owner's existing helper still works and is entirely outside opencode:

```bash
curl -s https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $(security find-generic-password -s 'Claude Code-credentials' -w | jq -r .claudeAiOauth.accessToken)" \
  -H 'anthropic-beta: oauth-2025-04-20' \
  | jq '{five:.five_hour.utilization, seven:.seven_day.utilization, reset:.five_hour.resets_at}'
```

**But see recipe 7: that OAuth token cannot drive an opencode session anyway.** For Zen, Go, Xiaomi,
Kimi, Z.AI and MiniMax, whether a balance endpoint exists at all is **UNKNOWN**.

### 6b. Detect the hit in-band — this part is genuinely good (schemas VERIFIED)

```bash
curl -N -u "$U:$P" http://127.0.0.1:4321/api/event \
 | jq -c 'select(.type=="session.next.retried") | .data'
```

`session.next.retried.data` is `{timestamp, sessionID, attempt, error}` and `error` is:

```json
{"message":"…","statusCode":429,"isRetryable":true,
 "responseHeaders":{"retry-after":"…","anthropic-ratelimit-requests-reset":"…"},
 "responseBody":"…","metadata":{}}
```

**`responseHeaders` is a full `Record<string,string>` of the provider's own 429 headers** — that *is*
the reset time, handed straight through. Reactively, at the moment of the hit, never before it.

Also watch `/session/status` for `{"type":"retry", …, "action":{reason, provider, title, message,
label, link}}` — `action.reason` and `action.provider` are the human-readable cause, and the TUI
renders them through locale keys `dialog.usageExceeded.accountRateLimit.*` and
`dialog.usageExceeded.freeTier.*` (VERIFIED, binary strings: *"Usage limit reached. To continue using
this model now…"*). **opencode knows a limit was hit; it renders it to a human and exposes it only as
an event.**

**The design consequence, and it is not a small one.** The owner's stated rule — check both windows
before and during a run, stop at 90% weekly — cannot be enforced through opencode for any provider
without its own usage endpoint. **Invert it: design the queue to survive the hit rather than avoid
it.** On `retry`, park the ticket, read `retry-after`, sleep, resume from `durable.seq` (recipe 10).
That is the honest architecture here, and it is more robust anyway.

---

## Recipe 7 — Switch a new session to a different account, verified before work starts

Three mechanisms at three scopes. **The obvious one is the wrong one.**

### 7a. Per-provider credentials — the right lever (VERIFIED)

Providers are independent, so "role A on account X, role B on account Y" is really "role A on
provider X's key, role B on provider Y's key", and it is already per-session:

```bash
# bind at creation
curl -fsS -u "$U:$P" -X POST http://127.0.0.1:4321/api/session -H 'content-type: application/json' \
  -d '{"id":"ses_TICKET1234","model":{"providerID":"xiaomi-token-plan-sgp","id":"mimo-v2.5-pro"},
       "location":{"directory":"/repo"}}'

# or switch mid-flight — one of very few platforms where this is possible
curl -fsS -u "$U:$P" -X POST http://127.0.0.1:4321/api/session/ses_TICKET1234/model \
  -H 'content-type: application/json' \
  -d '{"model":{"providerID":"anthropic","id":"claude-sonnet-4-6"}}'

# verify BEFORE any work is scheduled
curl -fsS -u "$U:$P" http://127.0.0.1:4321/api/session/ses_TICKET1234 | jq -c '.data.model'
```

Install a key without touching the owner's files:

```bash
curl -fsS -u "$U:$P" -X POST \
  http://127.0.0.1:4321/api/integration/anthropic/connect/key \
  -H 'content-type: application/json' -d '{"key":"sk-ant-…","label":"orch-account-B"}'
# schema: {key: string (required), label?: string}

# or the older per-provider route
curl -fsS -u "$U:$P" -X PUT http://127.0.0.1:4321/auth/anthropic \
  -H 'content-type: application/json' -d '{"type":"api","key":"sk-ant-…"}'
# Auth = OAuth | ApiAuth | WellKnownAuth
# ApiAuth = {type:"api", key: string, metadata?: Record<string,string>}
# OAuth   = {type:"oauth", refresh, access, expires, accountId?, enterpriseUrl?}
```

Config-file route, no writes to disk: `config.provider.<id>.options.apiKey` with `{env:VAR}` or
`{file:path}` substitution, delivered through `OPENCODE_CONFIG_CONTENT` (inline JSON) or
`OPENCODE_CONFIG` (a path). `options.baseURL` handles regional/proxy endpoints.

**The finding that costs this owner money (VERIFIED).** Interactive/OAuth login is available for
exactly ten providers — `GET /provider/auth` returns
`["azure","cloudflare-ai-gateway","cloudflare-workers-ai","digitalocean","github-copilot","gitlab","openai","poe","snowflake-cortex","xai"]`
— and **`anthropic` is not among them**. `GET /api/integration` confirms the methods per provider:

```
anthropic               methods: ["key","env"]
kimi-code-plan-global   methods: ["key","env"]
xiaomi-token-plan-sgp   methods: ["key","env"]
zai-coding-plan         methods: ["key","env"]
opencode                methods: ["key","env","oauth"]
```

**There is no Claude Pro/Max subscription login in opencode 1.18.31 — Anthropic is API-key only.**
The profile left this UNKNOWN; it is now a verified negative. Work the owner runs through opencode on
an Anthropic model is billed at API rates against a key, not drawn from the Max subscription he
already pays for. Note also that `openai` **does** have OAuth (ChatGPT Plus/Pro), so the asymmetry is
Anthropic-specific.

### 7b. opencode Console accounts — global, one at a time. Do not build on this. (VERIFIED)

```bash
curl -fsS -u "$U:$P" http://127.0.0.1:4321/experimental/console/orgs
# → {"orgs":[]}   ;  populated: [{accountID, accountEmail, accountUrl, orgID, orgName, active}]
curl -fsS -u "$U:$P" -X POST http://127.0.0.1:4321/experimental/console/switch \
  -H 'content-type: application/json' -d '{"accountID":"…","orgID":"…"}'   # → boolean
```

Schema requires both `accountID` and `orgID`. The store is
`account_state(id INTEGER PRIMARY KEY, active_account_id, active_org_id)` — **exactly one active
pair, selected `WHERE id = 1`** (VERIFIED, DDL). **Two sessions under two different Console accounts
cannot run concurrently in one opencode instance.**

### 7c. Full isolation — one server per account (VERIFIED, and cheap)

```bash
OPENCODE_DB=/var/orch/oc/acctA/opencode.db OPENCODE_CONFIG_DIR=/var/orch/oc/acctA/config \
  opencode serve --port 4321 --hostname 127.0.0.1 &
OPENCODE_DB=/var/orch/oc/acctB/opencode.db OPENCODE_CONFIG_DIR=/var/orch/oc/acctB/config \
  opencode serve --port 4322 --hostname 127.0.0.1 &
```

The orchestrator keeps a port↔account map; sessions are no longer visible across servers. The 145 MB
binary is shared. **No macOS Keychain is involved anywhere** — credentials are rows in
`credential` — so opencode has none of Claude Code's "blocks on a GUI dialog at 03:00" failure mode.
Verified by inspection: a fresh state directory needs no keychain access to start and serve.

**Success for the whole recipe:** `GET /api/session/{id} | jq .data.model` shows the intended
`providerID` *before* the first prompt is admitted. **Failure:** it shows a different provider, or
`null` — in which case opencode will fall back to `config.model` or the provider default and spend on
the wrong account. Check it; do not assume it.

---

## Recipe 8 — Deliver an instruction into a running session and confirm it arrived

**This is opencode's best axis and it was proved end to end on this machine.**

```bash
curl -fsS -u "$U:$P" -X POST http://127.0.0.1:4321/api/session/ses_TICKET1234/prompt \
  -H 'content-type: application/json' \
  -d '{"id":"msg_TICKET1234_0007",
       "prompt":{"text":"stop refactoring, run the test suite and report"},
       "delivery":"steer",
       "resume":true}'
```

Body schema (VERIFIED): `{id?: "^msg_", prompt: PromptInput (required), delivery: "steer"|"queue",
resume?: boolean}`. The description is *"Durably admit one session input and schedule agent-loop
execution unless resume is false."*

- **`delivery:"steer"`** interrupts and redirects the turn in flight.
- **`delivery:"queue"`** waits for the current turn to finish.
- **`resume:false`** admits without starting the loop.
- **`id`** is the caller's to choose — the orchestrator can name messages as well as sessions, which
  makes the delivery idempotent from its own ledger.

Executed here, verbatim:

```
POST /api/session/ses_spikerecipe000000000001/prompt
  {"id":"msg_spikerecipe0000000001","prompt":{"text":"recipe probe one"},
   "delivery":"queue","resume":false}
→ {"data":{"admittedSeq":1,"id":"msg_spikerecipe0000000001",
           "sessionID":"ses_spikerecipe000000000001","prompt":{"text":"recipe probe one"},
           "delivery":"queue","timeCreated":1789824639090,"promotedSeq":null}}
```

**Arrival is confirmed four independent ways, all observed:**

1. **Synchronously**, by a monotonic `admittedSeq` in the response.
2. **As a row**: `session_input(delivery='queue', admitted_seq=1, promoted_seq=NULL)`.
3. **On the stream**: `session.next.prompt.admitted` with `durable.seq` matching.
4. **Replayable afterwards**:
   ```
   GET /api/session/{id}/history          → {"data":[{…"durable":{"seq":1}…}],"hasMore":false}
   GET /api/session/{id}/history?after=1  → {"data":[{…"seq":2…}],"hasMore":false}
   ```

**Text cannot be stranded here, by construction.** Contrast recipe 3's `/tui/submit-prompt`, which
returns `true` into the void.

**One thing to know about `seq`.** It is a per-aggregate counter that also advances on operations
that are not history events. Observed on one session: history returned seqs **`[1, 2, 7]`** after two
prompts and several `PATCH` calls. **`after=<seq>` remains exactly correct; contiguity does not hold.
Never treat a gap as a lost event.**

**Failure:** non-2xx, or a response whose `admittedSeq` does not advance. **Fallback:** none needed —
but if the session is not owned by this process, `POST` still admits the input durably and the owning
process picks it up, because both read the same SQLite store (VERIFIED earlier: a session created
over HTTP was picked up by a CLI `run` with no `--attach`).

---

## Recipe 9 — Answer a permission prompt or a question without a human

### 9a. Permissions (endpoints and schemas VERIFIED; live firing needs credentials)

```bash
curl -fsS -u "$U:$P" http://127.0.0.1:4321/api/session/ses_TICKET1234/permission
# → {"data":[]}   when nothing is pending
```

`PermissionV2Request` = `{id:"^per", sessionID:"^ses", action, resources[], save[]?, metadata?,
source?}`; `action` and `resources` are required.

```bash
curl -fsS -u "$U:$P" -X POST \
  "http://127.0.0.1:4321/api/session/ses_TICKET1234/permission/$PER_ID/reply" \
  -H 'content-type: application/json' -d '{"reply":"once","message":"auto-approved by orchestrator"}'
```

`{reply: "once"|"always"|"reject", message?: string}` — `reply` required, `additionalProperties:false`.
Watch `permission.v2.asked` / `permission.v2.replied` on the stream. Audit the standing grants the
supervisor issued overnight:

```bash
curl -fsS -u "$U:$P" http://127.0.0.1:4321/api/permission/saved            # → {"data":[]}
curl -fsS -u "$U:$P" -X DELETE http://127.0.0.1:4321/api/permission/saved/$ID
```

### 9b. Clarifying questions (schemas VERIFIED)

`question` is a registered tool (`GET /experimental/tool/ids` →
`["invalid","question","bash","read","glob","grep","edit","write","task","webfetch","todowrite",
"websearch","skill","apply_patch"]`).

```bash
curl -fsS -u "$U:$P" http://127.0.0.1:4321/api/session/ses_TICKET1234/question
# → {"data":[]}
# populated: {id:"^que", sessionID, questions:[QuestionInfo], tool?:QuestionTool}
# QuestionInfo = {question, header (≤30 chars), options:[{label,description}], multiple?, custom?}

curl -fsS -u "$U:$P" -X POST \
  "http://127.0.0.1:4321/api/session/ses_TICKET1234/question/$QUE_ID/reply" \
  -H 'content-type: application/json' -d '{"answers":[["Use the existing schema"],["Yes"]]}'
# QuestionV2Reply = {answers: QuestionV2Answer[]}  — "User answers in order of questions
#                                                    (each answer is an array of selected labels)"

curl -fsS -u "$U:$P" -X POST \
  "http://127.0.0.1:4321/api/session/ses_TICKET1234/question/$QUE_ID/reject"
```

Events: `question.v2.asked` / `.replied` / `.rejected`.

**The answers are *labels*, not indices.** Copy them out of `options[].label` verbatim; an invented
label will not match.

### 9c. The right default for an unattended fleet

**Do not turn everything on.** `--auto` on `run` describes itself as *"auto-approve permissions that
are not explicitly denied (dangerous!)"* — its own help says so. Prefer the per-session ruleset from
recipe 2c, which is narrow, auditable and readable back.

Understand what you are overriding: **with no permission config, most permissions default to
`"allow"`; only `doom_loop` and `external_directory` default to `"ask"`; `read` allows everything
except `.env`** (CLAIMED, docs/permissions — consistent with `PermissionActionConfig` =
`"ask"|"allow"|"deny"`, VERIFIED). **`bash` and `edit` run unattended without asking, out of the
box.** Combined with correction 7 — a typo in `OPENCODE_PERMISSION` silently yields exactly this
default — the launch preamble's `jq -e` validation is not optional.

Permission keys (VERIFIED, `PermissionConfig`): `read`, `edit`, `glob`, `grep`, `list`, `bash`,
`task`, `external_directory`, `todowrite`, `question`, `webfetch`, `websearch`, `lsp`, plus `skill`
and `doom_loop` from the docs. Patterns support `*`/`?` and `~`/`$HOME`; **last matching rule wins**
(CLAIMED).

**Fallback, and the stronger option if you own the plugin layer:** the `permission.ask` hook
(`(input: Permission, output: {status:"ask"|"deny"|"allow"}) => Promise<void>`, CLAIMED from typings)
puts policy *inside* opencode, closing the poll-interval window in which a session sits blocked.

---

## Recipe 10 — Resume after a crash, and after a reboot

**This is the strongest axis on the platform, and it is a protocol guarantee rather than
best-effort.**

### 10a. The supervisor persists one integer per session

```
seq := max(durable.seq) seen for this session
```

### 10b. Resume, whatever died (VERIFIED, executed)

```bash
# finite catch-up page
curl -fsS -u "$U:$P" "http://127.0.0.1:4321/api/session/ses_TICKET1234/history?after=$seq&limit=500"
# → {"data":[…events…],"hasMore":false}

# replay-then-follow: durable events after $seq, then live, on one connection
curl -N   -u "$U:$P" "http://127.0.0.1:4321/api/session/ses_TICKET1234/event?after=$seq"
```

Observed on this machine:

```
GET …/history            → seqs [1,2]        "hasMore":false
GET …/history?after=1    → seqs [2]          "hasMore":false
GET …/event?after=0      → SSE replay of 1, then 2, then live
```

**No gap and no duplicate.** Persist one number; recover exactly.

### 10c. After a whole-machine reboot (VERIFIED)

The store is SQLite with WAL at `$XDG_DATA_HOME/opencode/opencode.db` (`opencode db path`), and
survives everything that is not a disk failure. Across **eight server starts and stops on eight
ports**, `ses_spikerecipe000000000001` kept its id, its title, its per-session permission ruleset and
its full history (`[1,2]`, later `[1,2,7]`). Nothing was lost and nothing was replayed twice.

Boot sequence for the orchestrator:

```bash
# 1. bring the server back (recipe 0.2) with the SAME OPENCODE_DB
# 2. reconcile: what does opencode think exists?
opencode session list --format json
# [{"id":"ses_spikerecipe000000000001","title":"orch-ticket-1234","updated":1789824630750,
#   "created":1789824630750,"projectId":"global","directory":"…/proj"}, …]
#   — VERIFIED, exact field names

# 3. cross-project view
curl -fsS -u "$U:$P" http://127.0.0.1:4321/experimental/session

# 4. per session, re-subscribe from the stored seq (10b)
# 5. re-arm any unfinished work with delivery:"queue" (recipe 8)
```

**Read the store with the server down** — useful when the server itself will not start:

```bash
opencode db "select id,title,time_updated,cost,agent,model from session order by time_updated desc limit 20" --format json
opencode export ses_TICKET1234 --sanitize > /var/orch/backup/ses_TICKET1234.json
opencode import /var/orch/backup/ses_TICKET1234.json
```

`--sanitize` "redact[s] sensitive transcript and file data" (VERIFIED, `--help`) — relevant if
transcripts ever leave the machine.

**Failure:** `GET /api/session/{id}` returns 404 — the session was deleted (`DELETE /session/{id}`
returns `true` and the id 404s immediately afterwards; VERIFIED). There is no undelete. Keep
`opencode export` snapshots at every phase boundary.

**A provider outage is not a crash.** It surfaces as `session.status.retry` and
`session.next.retried`, and the session is intact throughout — recipe 6.

**UNKNOWN:** long-run behaviour of this store — WAL growth and lock contention across many concurrent
sessions in `$XDG_STATE_HOME/opencode/locks/` — was not exercised. The locks directory stayed empty
for the single-server, low-concurrency shapes tested here.

---

## Recipe 11 — Stop cleanly, leaving nothing running

In order, each step VERIFIED unless noted:

```bash
# 1. stop the work in flight (idle interruption is a documented no-op)
curl -fsS -u "$U:$P" -X POST http://127.0.0.1:4321/api/session/ses_TICKET1234/interrupt
# → HTTP 204, empty body        (observed on an idle session)

# 1b. v1 hard abort, if interrupt is not enough
curl -fsS -u "$U:$P" -X POST http://127.0.0.1:4321/session/ses_TICKET1234/abort
# → true   [200]

# 2. confirm nothing is running
curl -fsS -u "$U:$P" http://127.0.0.1:4321/session/status        # → {}
curl -fsS -u "$U:$P" http://127.0.0.1:4321/api/session/active    # → {"data":{}}

# 3. archive rather than delete — keeps the transcript, hides it from the UI
curl -fsS -u "$U:$P" -X PATCH http://127.0.0.1:4321/session/ses_TICKET1234 \
  -H 'content-type: application/json' -d '{"time":{"archived":'"$(date +%s000)"'}}'
#    PATCH schema: {title?, metadata?, permission?, time?:{archived:number}}   — VERIFIED

# 4. reap PTYs (they are NOT closed by interrupting the session)
curl -fsS -u "$U:$P" http://127.0.0.1:4321/pty | jq -r '.[].id' \
  | xargs -I{} curl -fsS -u "$U:$P" -X DELETE http://127.0.0.1:4321/pty/{}   # each → true

# 5. stop the server
kill "$SERVER_PID"

# 6. verify the machine is clean
pgrep -fl 'opencode.exe' || echo "clean"
```

**Only if the ticket is to be destroyed** (there is no undo):

```bash
curl -fsS -u "$U:$P" -X DELETE http://127.0.0.1:4321/session/ses_TICKET1234   # → true  [200]
curl -s -o /dev/null -w '%{http_code}\n' -u "$U:$P" \
  http://127.0.0.1:4321/api/session/ses_TICKET1234                            # → 404
# CLI equivalent: opencode session delete <sessionID>
```

**The one that actually leaks: PTYs.** They are independent processes with their own `pid` and are
not owned by the session's lifecycle. Because the record disappears the instant the process exits
(correction 5), the reliable sequence is: record every `pid` at creation, `DELETE` at teardown, then
`kill -0 <pid>` to confirm, then `kill -TERM` any survivor.

**Fallback if the server is wedged:** `pkill -f 'opencode.exe serve'`, then let recipe 10 recover —
the SQLite store makes a hard kill safe. This was done eight times here with no data loss.

---

## The adapter interface

Eleven capabilities, mapped to what 1.18.31 actually does.

| # | Capability | Status | How |
|---|---|---|---|
| 1 | **Preflight** | **Partial — native, incomplete** | `/global/health` + `opencode providers list` + `/provider .connected`. **`.connected` lists `opencode` with zero credentials**, so proof of auth costs one real token |
| 2 | **Headless launch, pinned id, structured output** | **Native, best in class** | `POST /api/session {"id":"ses_<ticket>"}` — the orchestrator names the session. SSE is NDJSON. `opencode run` is not usable (hung 6/6) |
| 3 | **Visible terminal** | **Native** | `opencode attach <url> --session <id>`, many TUIs on one server. `/tui/*` is a **trap**, not a channel |
| 4 | **Liveness** | **Emulated** | `/session/status` + `/api/session/active` + pending `permission`/`question` + SSE heartbeat. **`POST …/wait` returns 503**, so the supervisor polls |
| 5a | **Read context fullness** | **Emulated (~30 lines)** | `step.ended.tokens.input + cache.read` ÷ (`Model.limit.context` − `output` − `compaction.reserved`); agrees with `SessionCompaction.isOverflow` |
| 5b | **Force compaction + prove it** | **Partial — v1 only** | v2 `/api/…/compact` is **503**. Use v1 `/session/{id}/summarize {providerID, modelID}` with a **bare** `modelID`. Proof: `reason:"manual"` on the event, `session_context_epoch.baseline_seq`, `GET …/context` |
| 6a | **Read remaining quota** | **Impossible** | Zero quota/limit/reset/balance fields in 1,019 OpenAPI key names. Must be answered per provider, out of band |
| 6b | **Detect a limit hit + reset time** | **Native, and unusually rich** | `session.next.retried.error.responseHeaders` hands through the provider's raw 429 headers; `/session/status → retry.action` |
| 7 | **Switch accounts** | **Native per provider; global for Console** | `model:{providerID,…}` at create and `POST …/model` mid-flight. Console switch is **one active account per state dir**. **No Anthropic OAuth — API key only** |
| 8 | **Deliver an instruction, confirm arrival** | **Native, best in class** | `POST …/prompt` → `admittedSeq`, + row, + event, + replay. `steer` vs `queue`. Stranding is structurally impossible |
| 9 | **Answer permission / question** | **Native** | `…/permission/{id}/reply {reply:"once"\|"always"\|"reject"}`; `…/question/{id}/reply {answers:[[label]]}` |
| 10 | **Resume after crash / reboot** | **Native, best in class** | Persist one `durable.seq`; `…/event?after=<seq>` replays then follows. Survived 8 restarts here. Seqs are **sparse** |
| 11 | **Stop cleanly** | **Native, with one leak** | `interrupt` (204) → `abort` (true) → archive → **reap PTYs by `pid`** → kill server |

**Native: 6. Emulated: 3 (liveness, context fullness, compaction-via-v1). Impossible: 1 (quota).
Plus one trap that must be actively designed around (`/tui/*`).**

### Non-obvious work the implementer must budget for

1. **A provider-quota module.** The largest genuinely new piece. Keyed on
   `session.model.providerID`; Anthropic via the owner's `oauth/usage` helper; Zen/Go/Xiaomi/Kimi/
   Z.AI/MiniMax **UNKNOWN**. Design the queue to survive the hit, not to avoid it.
2. **A `ref` → log joiner.** Every 500 returns only `{"name":"UnknownError","data":{"ref":"err_…"}}`.
   The real message is in `$XDG_DATA_HOME/opencode/log/opencode.log`. Tail it; treat it as protocol.
3. **A validated launch preamble.** `jq -e` the permission JSON; pin `autoupdate:false` and
   `share:"disabled"` in the config file, because the env vars do not read back through `/config`.
4. **A skill symlink farm** into `$OPENCODE_CONFIG_DIR/skills/` — the documented paths do not work.
5. **A v1/v2 routing table, not a v1/v2 rule.** `DELETE`, `PATCH`, `summarize` and `abort` are v1;
   everything else is v2. Pin the opencode version and re-test this table on every upgrade.
6. **A hard wall-clock timeout on every CLI invocation**, and no CLI on the execution path.
7. **A PTY reaper** keyed on `pid`, because the record vanishes on exit.

---

## Support tier

### **Tier 2 — workable with emulation. A strong tier 2, and the best executor in the scan.**

**Not tier 1**, for two independent reasons, either of which alone would be disqualifying against the
owner's stated non-negotiables:

- **Quota is unreadable.** VERIFIED negative across the entire served API. The owner's rule — read
  both windows, stop at 90% weekly — cannot be enforced from inside opencode for any provider.
- **Two shipped-schema endpoints on core axes return 503.** `compact` and `wait` are documented and
  unimplemented in the version on disk today. Both have workarounds (v1 `summarize`; polling), but a
  tier-1 platform does not require the orchestrator to discover this by running it.

**Comfortably not tier 3**, because everything supervision actually depends on is native and was
proved here: assigned session ids, exactly-once event replay from a single integer, acknowledged
intervention with a monotonic `admittedSeq`, programmatic permission and question answering,
per-session permission rulesets, mid-flight provider switching, and a store that survived eight
restarts intact.

**What it costs the owner specifically.** Against Claude Code, opencode trades **one** capability for
**five**: it loses readable quota, and it gains assigned ids, exactly-once replay, acknowledged
delivery, programmatic answering, and externally-triggered compaction with typed proof — **four of
which `plugins/harness/docs/FIELD-NOTES.md` names as things the current harness cannot do.** The
second cost is newer and sharper than the profile suggested: **no Anthropic OAuth means his Claude
Max subscription cannot drive an opencode session at all.** That is a real bill, not an inconvenience,
and it should be priced before opencode is adopted as anything more than a secondary executor.

**Is it plausible to run unattended overnight today?** **Yes, over HTTP, with the preamble from
recipe 0 and a wall-clock timeout on everything.** Not through `opencode run` — which hung, silently
and reproducibly, in the last six attempts of this session while the HTTP surface stayed perfectly
healthy throughout.

---

## Footprint left on this machine

Everything is under
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/oc-sandbox`
and can be deleted. All servers were stopped (`pgrep -fl opencode.exe` → nothing).

Unchanged and verified after the run: `~/.config/opencode/opencode.json` (`{"mcp":{}}`, mtime
2026-07-11), `~/.local/share/opencode/` (the two empty directories from the July npm postinstall),
`~/.local/state/opencode/` (empty), `~/.claude/skills` (91 entries, read only — two were copied
*from* and two symlinked *into* the sandbox).
