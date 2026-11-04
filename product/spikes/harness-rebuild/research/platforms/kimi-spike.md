# Kimi Code — orchestrator adapter spike

**Date:** 2026-09-19. **Target:** `@moonshot-ai/kimi-code@2.0.2` (binary `kimi`), published
2026-09-19T12:16Z. **Companion:** `kimi.md` (capability profile) — read that first for *why*; this
document is *how*.

**Evidence tags.** **VERIFIED** — I ran it on this machine, or read the exact flag/field in the
installed binary's `--help`, its source, or the live `/openapi.json` this binary served.
**CLAIMED** — official docs only. **UNKNOWN** — could not establish.

**How this was verified.** Kimi is **not installed on the owner's machine** (`which kimi` → not
found; no `~/.kimi-code`; VERIFIED). Everything below was exercised against an **isolated sandbox**:
`@moonshot-ai/kimi-code@2.0.2` in its own `node_modules` under
`<scratchpad>/kimi/sandbox`, `KIMI_CODE_HOME` pointed at a scratch directory, Node v24.18.0 (this
machine's default 22.18.0 is **below** kimi-code's `engines.node >= 22.19.0`). No login was
performed, **no model call ever succeeded, so no quota was spent**, and nothing of the owner's was
read or modified. Consequence: every recipe's *transport* is verified, and every recipe that needs a
model to actually answer is verified up to the point where the model would reply. Each recipe says
which.

---

## 0. Three corrections to the capability profile — verified by execution

These reverse or sharpen claims in `kimi.md`. An adapter built on the profile alone would be wrong
in two places and would lose its event stream every 20 seconds.

**0.1 — The WebSocket *does* heartbeat, and *does* disconnect you.** The profile says *"The server
never sends heartbeats and never disconnects an idle connection — keepalive and reconnection are the
client's job."* The live 2.0.2 server says otherwise. `server_hello` advertises
`heartbeat_ms: 10000`; the server then sends `{"type":"ping","payload":{"nonce":"…"}}` every 10s, and
a client that does not answer is closed:

```
OPEN
+10s ping (ignored)
CLOSE after 20s code=1001 reason=heartbeat timeout
```

(VERIFIED by execution.) The AsyncAPI agrees: `ping` is *"Heartbeat ping sent by the server; clients
must answer with pong."* **The adapter must echo the nonce back within ~20s or lose the stream.**
The upside: a dead supervisor is detected by the *server* in 20s, and `pong` doubles as the
supervisor's own liveness proof.

**0.2 — The `subscribe` frame is nested.** Not `{type:"subscribe", session_id}` (that is accepted
with `accepted: []` — a silent no-op). The real shape, from the live `/asyncapi.json` and confirmed
on the wire:

```json
{"type":"subscribe","id":"sub-1",
 "payload":{"session_ids":["session_…"],
            "cursors":{"session_…":{"seq":15,"epoch":"ep_…"}},
            "agent_filter":{"session_…":["main"]}}}
```

Ack: `{"type":"ack","id":"sub-1","code":0,"payload":{"accepted":[…],"not_found":[],
"resync_required":[],"cursors":{"session_…":{"seq":15,"epoch":"ep_…"}}}}` (VERIFIED live).
**An empty `accepted` array with `code:0` is the failure signature — assert on it.**

**0.3 — Events arrive typed at the top level, not wrapped.** The AsyncAPI declares a `session_event`
message, but on the wire each event is its own frame:

```json
{"type":"prompt.completed","seq":15,"session_id":"session_…","timestamp":"2026-09-19T13:28:04.867Z",
 "payload":{"type":"prompt.completed","agentId":"main","promptId":"orch-T77-a1","reason":"failed",…}}
```

(VERIFIED live.) Dispatch on the **top-level `type`**, take ordering from the top-level `seq`.
A supervisor that waits for `type === "session_event"` receives nothing and reports a healthy,
silent session forever.

**Also found, not in the profile:** `event.session.work_changed` — a single event carrying
`{busy, main_turn_active, pending_interaction, last_turn_reason, agentId}`. This is the liveness
event; §4 builds on it.

---

## 1. Standing setup — the launcher environment contract

Every `kimi` process the orchestrator spawns gets exactly this environment. Nine of these exist to
disarm a default that is wrong for unattended work.

```sh
# --- identity / isolation -------------------------------------------------
export KIMI_CODE_HOME="$HOME/.kimi-accounts/<account>"   # the ONLY account boundary
export KIMI_CODE_OAUTH_HOST="https://auth.kimi.ai"       # global; default is mainland-cn
export KIMI_CODE_BASE_URL="https://api.kimi.ai/coding/v1"

# --- stop the binary changing under the run -------------------------------
export KIMI_CODE_NO_AUTO_UPDATE=1

# --- stop the unbounded print-mode defaults -------------------------------
export KIMI_CODE_BACKGROUND_PRINT_BACKGROUND_MODE=drain  # default "steer" re-steers forever
export KIMI_CODE_BACKGROUND_BASH_TASK_TIMEOUT_S=900      # default 0 (NO timeout) in print mode
export KIMI_CODE_BACKGROUND_PRINT_MAX_TURNS=40           # default ~unbounded
export KIMI_CODE_BACKGROUND_PRINT_WAIT_CEILING_S=3600    # default 2147483

# --- optional ------------------------------------------------------------
export KIMI_DISABLE_CRON=1            # cron re-injection surprises a supervised queue
export KIMI_DISABLE_TELEMETRY=1
export KIMI_CODE_IDENTITY_SLUG="orch-<account>"   # tags User-Agent + MCP client name
export PATH="$HOME/.nvm/versions/node/v24.18.0/bin:$PATH"   # >= 22.19.0 required
```

Env-var names VERIFIED in `docs/en/configuration/env-vars.md` and
`docs/en/configuration/config-files.md` §`background`, §`loop_control`. `engines.node` VERIFIED in
`apps/kimi-code/package.json`.

**Do not** export `KIMI_API_KEY` / `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` and expect them to work —
Kimi does not read credential variables from the shell. Only `api_key_env` in `config.toml` and the
`KIMI_MODEL_*` family do (VERIFIED, `env-vars.md` + `overrides.md`).

Per-account `config.toml` (`$KIMI_CODE_HOME/config.toml`), the parts that matter unattended:

```toml
default_permission_mode = "yolo"        # "auto" = never-ask AND the dangerous-command guard is OFF

[loop_control]
max_steps_per_turn    = 120
max_attempts_per_step = 10              # default; retries 429/5xx/timeouts
reserved_context_size = 50000           # auto-compaction fires below this remaining

[background]
bash_task_timeout_s   = 900
print_background_mode = "drain"

[subagent]
timeout_ms = 1800000
[swarm]
timeout_ms = 1800000

# the ONLY guardrail that survives --auto and -p mode:
[[permission.rules]]
decision = "deny"
pattern  = "Bash(rm -rf*)"
scope    = "user"
reason   = "orchestrator: never"

[[hooks]]
event   = "SessionHeartbeat"            # 60s pulse; the timer only runs if configured
command = "/usr/local/bin/orch-heartbeat"
timeout = 10

[[hooks]]
event   = "PostCompact"                 # matcher: "manual" | "auto"
command = "/usr/local/bin/orch-compact-receipt"
timeout = 10
```

Table names, defaults and the four-field `[[hooks]]` schema VERIFIED in `config-files.md` and
`customization/hooks.md`. `SessionHeartbeat` VERIFIED in `hooks.md` line 121 and in
`packages/agent-core-v2/test/features/externalHooks/integration.test.ts`.

**Everything below assumes one `kimi web` per `KIMI_CODE_HOME`, on its own port.** Two shell
variables recur:

```sh
B="http://127.0.0.1:58700"
H="Authorization: Bearer $(cat "$KIMI_CODE_HOME/server.token")"
```

> **Shell trap, hit during this spike's predecessor.** In zsh, `"$B/api/v1/sessions/$SID:compact"`
> loses `:c` to parameter-modifier expansion and yields a bogus path plus a misleading
> `40001 unsupported action`. **Always brace: `"${SID}"`.** Every `:verb` URL below is braced.

---

## 2. Recipe 1 — Preflight: installed, authenticated, which account

**VERIFIED** — all five commands run on this machine.

```sh
# a. installed, and the RIGHT kimi (legacy kimi-cli shares the binary name and flips -c)
kimi --version                       # → 2.0.2 ; assert major >= 2
# b. config files parse
kimi doctor; echo $?                 # → "All checked config files are valid." exit 0
# c. is this home authenticated at all
kimi provider list --json            # → {"providers":{},"models":{}} when NOT authenticated
# d. which region this home will talk to
curl -s -H "$H" "$B/api/v1/oauth/region"
# → {"code":0,"data":{"region":"mainland-cn"}}
# e. which account, and is the model layer ready
curl -s -H "$H" "$B/api/v1/auth"
# → {"code":0,"data":{"models_ready":false,"providers_count":0,"managed_provider":null}}
curl -s -H "$H" "$B/api/v1/oauth/userinfo"     # identity of the logged-in account
```

**Success:** `--version` ≥ 2; `doctor` exits 0; `auth.models_ready === true` **and**
`auth.managed_provider` names the expected plan; `oauth/region` matches the intended region.

**Failure, and what each means:**
- `kimi: command not found` → not installed.
- `--version` `1.x` → this is the **legacy Python `kimi-cli`**, where `-c` means `--command`, not
  `--continue`. A launcher written for 2.x silently does the wrong thing. **Assert the major
  version; do not assert on the binary's name.** (VERIFIED — read in `kimi_cli/cli/__init__.py`
  vs `apps/kimi-code/src/cli/commands.ts`.)
- `models_ready:false` / `providers_count:0` → not logged in. `kimi login --region global`
  (device-code flow, VERIFIED `kimi login --help`) — **interactive, cannot be automated.**
- `region: "mainland-cn"` on a fresh home is the **default** (VERIFIED live). For a European owner
  this is the wrong endpoint set. Pin `KIMI_CODE_OAUTH_HOST` / `KIMI_CODE_BASE_URL`.

**Preflight without a server running** (cheaper, and works before `kimi web` starts):

```sh
test -s "$KIMI_CODE_HOME/credentials/kimi-code.json" || echo "NOT AUTHENTICATED"
```

Credential path, `0700` dir / `0600` files, atomic tmp→fsync→rename: VERIFIED in
`packages/oauth/src/storage.ts`. **On disk, not in the macOS Keychain** — so an unattended run
cannot be blocked by a Keychain prompt.

**Fallback if none of this is available:** there is none that is safe. A `kimi` that fails preflight
must not be given a task; mark the account `unavailable` and route the ticket elsewhere.

---

## 3. Recipe 2 — Start a task headless with a pinned session id, structured output

**PARTIAL** — the id-pinning round trip, the flag surface, the exit codes and the first stream-json
line are VERIFIED live; the model never answered (no auth), so the body of the stream is
schema-verified, not observed.

**The constraint that shapes everything:** there is **no `--session-id <id>` that creates**.
`-S/--session [id]` only resumes; an unknown id is rejected:

```sh
kimi -p "x" -S "session_deadbeef-0000-0000-0000-000000000000"
# → error: failed to run prompt: Session "…" not found.   exit 1
```

(VERIFIED live.) And `POST /api/v1/sessions` **silently drops every metadata key except `cwd`** —
I sent `{"metadata":{"cwd":"…","orch_task":"T-77"}}` and got back only `cwd` (VERIFIED live).

**So the id contract is a two-step, and the second step is not optional:**

```sh
# 1. create — server mints the id; title is the only correlation channel that survives creation
SID=$(curl -s -X POST -H "$H" -H 'Content-Type: application/json' \
  -d "{\"metadata\":{\"cwd\":\"$WORKDIR\"},\"title\":\"T-77\"}" \
  "$B/api/v1/sessions" | jq -r .data.id)
# → session_375435cb-437b-4e11-880a-9225ab1e0216

# 2. stamp — /profile DOES persist arbitrary metadata, to disk and back out of every list
curl -s -X POST -H "$H" -H 'Content-Type: application/json' \
  -d '{"metadata":{"orch_task":"T-77","orch_attempt":"1"}}' \
  "$B/api/v1/sessions/${SID}/profile"

# 3. verify the stamp before any work is submitted
curl -s -H "$H" "$B/api/v1/sessions/${SID}" | jq '.data.metadata'
# → {"orch_task":"T-77","orch_attempt":"1","cwd":"…"}
```

(All three VERIFIED live.) The stamp reaches disk at
`$KIMI_CODE_HOME/sessions/<wd_slug_hash>/<sid>/state.json` under `"custom"`, and comes back out of
`kimi session list --json` as `metadata` — **with no server running** (VERIFIED, §11).

> **Crash window.** Between step 1 and step 2 a crash leaves an untagged session. Mitigate by
> setting `title` to the task id at creation (it *is* accepted at creation, VERIFIED) and treating
> `title` as the fallback index. There is no server-side metadata filter, so recovery is
> list-and-scan either way.

**Then run the work.** Two shapes, and they are not interchangeable:

```sh
# A. one-shot, own process, structured stdout
kimi -p "$TASK" --session "$SID" --output-format stream-json
# B. submit into the supervised session over HTTP (preferred — see §9)
```

Verified `-p` facts:
- `--output-format text|stream-json` (VERIFIED `kimi --help`). First stdout line in stream-json is
  `{"role":"meta","type":"system.version","version":"2.0.2"}` (VERIFIED live).
- **Assistant text on stdout; thinking, tool progress and "resuming session" notices on stderr**
  (CLAIMED, `kimi-command.md`). In text mode the `kimi version 2.0.2` banner is also on stderr
  (VERIFIED live) — do not parse stderr as content.
- Failure exits **1** with the reason on stderr (VERIFIED live: `exit=1`,
  `error: failed to run prompt: No model configured.`).
- `KIMI_MODEL_OUTPUT_FORMAT` sets the default when the flag is absent; invalid values fail fast
  (VERIFIED in `apps/kimi-code/src/cli/options.ts`, constant `OUTPUT_FORMAT_ENV` — **not** in the
  env-vars doc).
- **`-p` cannot be combined with `--auto` or `--yolo`** — rejected before anything runs:
  ```
  $ kimi -p "hello" --auto   → error: Cannot combine --prompt with --auto.     exit 1
  $ kimi -p "hello" --yolo   → error: Cannot combine --prompt with --yolo.     exit 1
  $ kimi -p "hello" -S       → error: Cannot use --session without an id in prompt mode.
  ```
  (All three VERIFIED live.) `docs/en/configuration/overrides.md` advertises
  `kimi --yolo -p "…"` — **that documented command cannot run.** Do not build a launcher from it.
- `-p` is combinable with `--session <id>` and `-c/--continue` (VERIFIED live).
- **In `-p` mode every tool call runs under the `auto` policy with no approval prompt ever**, while
  static `[[permission.rules]] decision="deny"` stay in force (CLAIMED, `kimi-command.md`; the
  deny-survives-everything half is stated in both `kimi-command.md` and `overrides.md`).

**Success:** exit 0, and a terminal `prompt.completed`/`turn.ended` with `reason:"completed"`.
**Failure:** non-zero exit, or exit 0 with `last_turn_reason:"failed"` — check both.
**Fallback if stream-json is unusable:** tail `wire.jsonl` (§5); it is strictly richer than stdout
and survives the process.

---

## 4. Recipe 3 — The same task in a visible terminal the owner can type into

**PARTIAL** — the session bridge is VERIFIED (an API-created session resumes from the CLI); the TUI
itself was not driven interactively (no TTY in this harness).

**The key property, and it is unusual:** `kimi web` and the TUI serve *the same sessions from the
same data root*. A session the orchestrator created over HTTP can be opened in a terminal, typed
into by the owner, and handed back — no export, no replay. Verified by resuming an API-created
session from the CLI:

```sh
kimi -p "x" -S "$SID"
# → error: failed to run prompt: no provider configured …    ← got PAST session resolution
```

(VERIFIED live; contrast the bogus-id case above, which fails at resolution with
`Session "…" not found.`)

**Three attach surfaces, in the order an orchestrator should prefer them:**

```sh
# 1. browser — zero launcher code, works from any device on the machine
open "http://127.0.0.1:58700/#token=$(cat "$KIMI_CODE_HOME/server.token")"

# 2. a real terminal tab (owner's stated preference is iterm2-osascript —
#    ~/.claude/shared/tooling.json: "tab in the current window when one exists,
#    else ONE fresh window with one session")
osascript -e 'tell application "iTerm2" to tell current window to create tab with default profile' \
          -e "tell application \"iTerm2\" to tell current session of current window to write text \
              \"export KIMI_CODE_HOME=$KIMI_CODE_HOME; kimi --session $SID\""

# 3. remote, from the owner's phone — requires a paid membership, ~3 devices/account
kimi rc            # relays the same UI via https://code-rc.kimi.com/devices/<device-id>/
```

Inside the TUI the owner gets what the current harness cannot do: **`Ctrl-S` injects the text in the
input box into the *running* turn** without waiting for it to end; `Esc`/`Ctrl-C` interrupts; `!`
enters shell mode and its output joins the conversation context (CLAIMED,
`docs/en/guides/interaction.md`). The programmatic equivalent is `:steer` (§9).

**Success:** the terminal shows the same `title`/`metadata` the orchestrator stamped, and
`GET …/status` reports the session as `busy` while the owner's turn runs.
**Failure:** `Session "…" not found` → wrong `KIMI_CODE_HOME` in the tab's environment. This is the
single most likely launcher bug, because the home is the account boundary *and* the session store.
**Fallback:** the browser UI (surface 1) needs no launcher at all and is the honest default; a
terminal tab is a nicety, not a requirement.

---

## 5. Recipe 4 — Alive, working, waiting, or finished, from outside

**VERIFIED** — every field and both process-level checks were read live.

Four independent layers. Use all four; each catches a failure the others cannot see.

**Layer 1 — is the server process there?**

```sh
cat "$KIMI_CODE_HOME"/server/instances/*.json
# {"server_id":"01M2WXKNC2…","pid":15973,"host":"127.0.0.1","port":58700,
#  "started_at":1789824456066,"heartbeat_at":1789824606080,"host_version":"2.0.2"}
kill -0 "$PID" 2>/dev/null && echo alive || echo dead
curl -s -m3 "$B/api/v1/healthz"      # → {"code":0,"data":{"ok":true}} — the ONE auth-exempt route
```

Liveness in the registry is decided by **`process.kill(pid, 0)`**, not by heartbeat age; dead
entries are unlinked on the next sweep or list (VERIFIED — `packages/kap-server/src/
instanceRegistry.ts`, `pidAlive()` / `sweepStale()` / `listLiveInternal()`).
`HEARTBEAT_INTERVAL_MS = 15_000` (VERIFIED in source).

> **Reboot hazard, from reading that code.** After a reboot, PIDs are recycled: a stale registry file
> whose pid now belongs to an unrelated process reads as **alive**. `kill -0` alone is not enough
> across a boot. **Always confirm with `GET /api/v1/healthz` on the recorded port** and compare
> `server_id` against `GET /api/v1/meta`.
>
> **And do not join the registry to `/api/v1/meta` by `server_id`** — for one and the same process I
> read `01M2WXKNC2CJDPMCFC6ZC95YX6` in the file and `01M2WXKNETT5T9JNT9XERD4RPZ` from `/meta`
> (VERIFIED by observation; cause UNKNOWN). **Join by `pid` or by `port`.**

**Layer 2 — the session's own state, one GET:**

```sh
curl -s -H "$H" "$B/api/v1/sessions/${SID}" | jq '.data |
  {busy, main_turn_active, pending_interaction, last_turn_reason, current_prompt_id}'
# → {"busy":false,"main_turn_active":false,"pending_interaction":"none",
#    "last_turn_reason":"failed","current_prompt_id":null}
```

(VERIFIED live; `pending_interaction` ∈ `none|approval|question`, `last_turn_reason` ∈
`completed|cancelled|failed` — enums read from the live `/openapi.json`.) The state machine:

| Reading | Meaning |
|---|---|
| `busy:true`, `main_turn_active:true`, `pending_interaction:"none"` | **working** |
| `busy:true`, `pending_interaction:"approval"` \| `"question"` | **waiting on a human** → §10 |
| `busy:false`, `last_turn_reason:"completed"`, `current_prompt_id:null` | **finished** |
| `busy:false`, `last_turn_reason:"failed"` | **finished badly** — read the error from `wire.jsonl` |
| `busy:true` for longer than the task budget, no new `seq` | **stuck** — the hang mode of §1 |

Fleet sweep in one call: `GET /api/v1/sessions?busy=true` (VERIFIED live, returns
`{items:[],has_more:false}`).

**Layer 3 — push instead of poll.** Subscribe (§0.2) and watch for
`event.session.work_changed`, which carries exactly the layer-2 tuple:

```json
{"type":"event.session.work_changed","seq":14,"session_id":"session_…",
 "payload":{"busy":false,"main_turn_active":false,"pending_interaction":"none",
            "last_turn_reason":"failed","agentId":"main"}}
```

(VERIFIED live.) Remember §0.1: answer the 10s `ping` with the same nonce or you are cut at 20s.

**Layer 4 — the hang detector, which no single field gives you.** The field notes' failure mode —
*"a shell that can never exit reading as work"* — is `busy:true` with no progress. Kimi makes it
detectable because durable events carry a monotonic `seq`:

```
stuck := busy == true AND snapshot.as_of_seq unchanged for N minutes
```

Read `as_of_seq` from `GET …/snapshot` (VERIFIED live: `as_of_seq 15`). Pair it with the
`SessionHeartbeat` hook (60s pulse with `uptime_ms`) to distinguish *"the process is alive but the
turn is frozen"* from *"the process is gone"*. **This is the check the current harness lacks, and
Kimi is the first platform in this scan that makes it a one-integer comparison.**

**Fallback with no server:** `kimi session list --json --all` prints `lastTurnReason` and
`updatedAt` per session from disk (VERIFIED live). It cannot tell you `busy` — a session whose
server died mid-turn looks identical to one that finished. Cross-check `updatedAt` against the
`wire.jsonl` mtime.

---

## 6. Recipe 5 — Read context fullness, force compaction, prove it happened

**PARTIAL** — all three read paths and the compaction endpoint's refusal path are VERIFIED live; a
*successful* compaction could not be run (no model), so the proof channels are listed with the
evidence tag each actually carries.

**Read it — and know which surface lies.** Measured side by side on one session at one moment:

```
GET …/status              → context_tokens: 190          ← live, authoritative
GET …/sessions/{id}       → usage.context_tokens: 0      ← NOT live. do not use.
GET …/snapshot            → session.usage.context_tokens: 190
wire.jsonl                → {"type":"token_counting.turn_recorded","tokens":190,…}
```

(All four VERIFIED live, same session, same minute.) **`GET /api/v1/sessions/{id}` reports zero for
a session that holds 190 tokens.** An adapter that reads context from the session object will
believe every session is empty forever.

```sh
curl -s -H "$H" "$B/api/v1/sessions/${SID}/status"
# → {"busy":false,"thinking_level":"","permission":"manual","plan_mode":false,
#    "swarm_mode":false,"tower_mode":false,"context_tokens":190}
```

`context_usage` is a **0–1 float** and `max_context_tokens` an integer — both declared in the live
`/openapi.json` for this route, and **both absent from the response until a model resolves**
(VERIFIED live: the object above has neither). **Treat them as optional and fall back to
`context_tokens / max_context_tokens` from the model catalog, or to the ratio being unknown.**
Reading `/status` **resumes a cold session** (CLAIMED, `server-api.md`) — a supervisor polling it
keeps sessions warm, which costs memory, not quota.

`[token_counting] strategy` ∈ `measured+estimated` (default) / `measured` / `estimated`, overridable
by `KIMI_TOKEN_COUNTING_STRATEGY`, decides which number is *reported*; auto-compaction always uses
both regardless (VERIFIED, `config-files.md` §`token_counting`).

**Force it:**

```sh
curl -s -X POST -H "$H" -H 'Content-Type: application/json' \
  -d '{"instruction":"Preserve the task contract, the file paths already touched, and open TODOs."}' \
  "$B/api/v1/sessions/${SID}:compact"
```

Returns immediately. Against an empty session I got the documented refusal verbatim:

```json
{"code":40910,"msg":"No messages to compact in current history.","data":null,
 "request_id":"01M2WXMCDCV082Q24VWK7PV8JD","stack":"Error2: … /private/tmp/claude-501/…"}
```

(VERIFIED live.) `40910` also means *a turn or another context change is already running* — so
**`40910` is ambiguous: "nothing to do" and "busy, try later" share a code.** Disambiguate with
`GET …/status.busy` before deciding whether to retry.

> **Log hygiene.** That error body carries a full Node `stack` with **absolute filesystem paths**
> (visible above). Scrub `stack` before logging or forwarding an envelope anywhere.

**Prove it — four channels, and their real evidence weight:**

| # | Proof | Tag |
|---|---|---|
| 1 | `compaction.*` frames on the WebSocket | CLAIMED (`server-api.md`); the frame family is real, the successful shape was not observed here |
| 2 | **`PostCompact` hook**, matcher literally `manual`\|`auto` — fires with the trigger reason, writes a receipt anywhere | VERIFIED in `customization/hooks.md`. **This is the strongest channel: it is an out-of-band file the supervisor owns.** |
| 3 | `context_tokens` drops on the next `GET …/status` | VERIFIED as a readable number; the drop itself not observed |
| 4 | `POST …:undo` returns `40911` with `{reason, requestedCount, undoableCount}` once a compaction boundary is in the way | CLAIMED (`server-api.md`) — i.e. compaction leaves a structural mark |

**The recommended proof is #2 + #3:** arm `PostCompact` to `echo "$(date -u +%FT%TZ) $session_id" >> "$RECEIPTS"`, then assert the receipt appeared **and** `context_tokens` fell. Two independent
sources, neither of which is the API call you just made.

**What you cannot do:** replace the compaction algorithm. `PreCompact`'s return value is
*"completely ignored"* (VERIFIED, `hooks.md`) — there is no custom-compaction hook in the Claude Code
sense. You may *steer the summary* with `instruction`, and that is all.

**Handoff instead of compaction** — often the better move for a supervisor:

```sh
curl -s -X POST -H "$H" -d '{}' "$B/api/v1/sessions/${SID}:fork"
# → {"code":0,"data":{"id":"session_4419d8eb-…","title":"Fork: spike-probe",
#      "metadata":{"orch_task":"T-77",…}}}
```

(VERIFIED live.) **Trap, found here: the fork inherits the parent's `metadata` verbatim, including
`orch_task`.** Two sessions now claim task T-77 and a list-and-scan recovery will find both.
**Re-stamp every fork immediately** (`POST …/profile` with a fresh `orch_attempt`, or clear it on the
parent). Auto-compaction tuning: `[loop_control] reserved_context_size` (example config ships
`50000`), `compaction_max_attempts = 5`, `[experimental] micro_compaction = false` (VERIFIED,
`config-files.md`).

---

## 7. Recipe 6 — Remaining quota, reset time, and an in-band limit hit

**PARTIAL** — the endpoint, its envelope and the error path are VERIFIED live; the success payload
is VERIFIED against the live `/openapi.json` schema and the Zod schemas in source, but no real
subscription was queried.

**Path A — with the local server:**

```sh
curl -s -H "$H" "$B/api/v1/oauth/usage?provider=managed:kimi-code"
```

Logged out, live, this returns — note `code:0`, **an upstream failure does not fail the envelope**:

```json
{"code":0,"msg":"success",
 "data":{"kind":"error","message":"No token for \"kimi-code\". Run /login to authenticate."}}
```

(VERIFIED live.) **So the adapter must branch on `data.kind`, never on `code`.** On success
`data` is `{kind:"ok", quota:{usages, extraUsage}}` with (schema read from the live spec served by
this binary, VERIFIED):

```
usages: { limit5h?:    {usedRatio: number, resetAt?: string},
          limit7d?:    {usedRatio, resetAt?},
          monthTotal?: {usedRatio, resetAt?},
          monthCode?:  {usedRatio, resetAt?} }
extraUsage: null | {balanceCents, totalCents, monthlyChargeLimitEnabled,
                    monthlyChargeLimitCents, monthlyUsedCents, currency}
```

`usedRatio` is 0–1; `resetAt` is RFC3339. **Every window is optional** — the weekly window was
*removed* for the new subscription tiers and retained only for legacy members, so `limit7d` will
simply be absent on a new plan. Render what is present; never assume a key.

**Path B — no server needed, which is what a watcher should actually use:**

```sh
ACCESS=$(jq -r .access_token "$KIMI_CODE_HOME/credentials/kimi-code.json")
curl -s -H "Authorization: Bearer $ACCESS" -H 'Accept: application/json' \
     "https://api.kimi.ai/coding/v1/usages"        # global; .com for mainland-cn
```

URL construction VERIFIED in `packages/oauth/src/managed-usage.ts`:
`kimiCodeUsageUrl() = kimiCodeBaseUrl() + "/usages"`, base
`https://api.kimi.com/coding/v1` (default) or `https://api.kimi.ai/coding/v1` (global), overridable
by `KIMI_CODE_BASE_URL`; 8-second client timeout. **Wire keys are snake_case and are remapped** —
the adapter reading the raw endpoint sees the *wire* names, not the domain names above (VERIFIED in
`parseQuotaUsages()`):

| Wire | Domain |
|---|---|
| `usages.limit_5h` | `limit5h` |
| `usages.limit_7d` | `limit7d` |
| `usages.limit_month_total` | `monthTotal` |
| `usages.limit_month_code` | `monthCode` |
| `used_ratio` | `usedRatio` |
| **`reset_time`** | **`resetAt`** |
| `boosterWallet` | `extraUsage` |

`401` ⇒ *"Authorization failed"*; **`404` ⇒ *"Usage endpoint not available. Try Kimi For Coding."*** —
the endpoint is scoped to the coding plan, not to every Kimi account (VERIFIED in source). **A 404
is not an outage; it is the wrong plan.** Treat it as a permanent capability signal, not a retry.

This is a near-exact structural match for the `five_hour.utilization` / `seven_day.utilization` /
`resets_at` triple the owner's existing `claude-limits` helper parses — **the same watcher logic
ports with a field rename**, plus a `limit7d`-may-be-absent branch.

**Path C — pay-as-you-go API key instead of a plan:** `GET https://api.moonshot.ai/v1/users/me/balance`
→ `{"code":0,"data":{"available_balance":…,"voucher_balance":…,"cash_balance":…}}` (USD), and each
429 carries `X-RateLimit-Limit` / `-Remaining` / `-Reset` headers, so remaining capacity is readable
**per response** rather than by polling (CLAIMED — official platform docs, not exercised here).

**Detect a limit hit in-band.** This is clean, and it is the reason Kimi is pleasant to supervise:
`[loop_control] max_attempts_per_step` (default 10) retries connection errors, timeouts, generic 429s
and 5xx — but **a 429 caused by exhausted quota or insufficient balance is not retried and fails
immediately** (CLAIMED, `config-files.md` §`loop_control`). It then surfaces as a `turn.ended` record
carrying a structured error. I verified that exact shape on a different error class:

```json
{"type":"turn.ended","agentId":"main","turnId":0,"reason":"failed",
 "error":{"code":"model.not_configured","message":"Model not set","retryable":false},
 "durationMs":13}
```

(VERIFIED live, from `wire.jsonl`.) **`error.retryable` is the field to branch on**, and the same
record arrives on the WebSocket as a top-level `turn.ended` frame and as a separate `error` frame
(VERIFIED live, `seq` 12 and 13).

**The structural fact that constrains the whole fleet:** *"all devices and API keys share one quota
pool"* (CLAIMED, official membership doc). **Four Kimi sessions on one account get no more throughput
than one.** Parallelism must come from §8, never from opening more terminals.

**Fallback when quota cannot be read at all** (404 plan, or a bare API key): run a token-budget
ledger from `token_counting.turn_recorded` in `wire.jsonl` (VERIFIED as present per turn) and stop at
a self-imposed ceiling. Strictly worse — it cannot see usage from the owner's phone against the same
pool — but it degrades safely.

---

## 8. Recipe 7 — Switch a new session to a different account, verified before work starts

**PARTIAL** — home isolation is VERIFIED (this entire spike ran inside a non-default
`KIMI_CODE_HOME`); the verification commands are VERIFIED live; a genuine second logged-in account
was not created.

**One environment variable is the whole mechanism** — structurally identical to the
`CLAUDE_CONFIG_DIR` trick the owner already automates with a profile switcher:

```sh
export KIMI_CODE_HOME="$HOME/.kimi-accounts/work"
```

*"Once set, **all** Kimi Code data lands under the new path: config, sessions, logs, OAuth
credentials, Kimi-specific user Skills, global AGENTS.md, and more"*, and *"Multiple `kimi` instances
sharing the same `KIMI_CODE_HOME` will share config and credential files"* (VERIFIED,
`env-vars.md`). It partitions `credentials/`, `config.toml`, `sessions/`, `session_index.jsonl`,
`server.token`, `server/instances/`, `logs/`, `skills/`, `agents/`, `plugins/`, `mcp.json`, and the
Remote Control device id.

**The full switch, with the verification gate that makes it safe:**

```sh
set -e
export KIMI_CODE_HOME="$HOME/.kimi-accounts/$ACCOUNT"
PORT=$((58700 + ACCOUNT_INDEX))          # one port per home; homes are independent
kimi web --no-open --port "$PORT" --log-level info &

B="http://127.0.0.1:$PORT"
H="Authorization: Bearer $(cat "$KIMI_CODE_HOME/server.token")"

# --- GATE: refuse to dispatch until all three agree -----------------------
curl -s -H "$H" "$B/api/v1/auth"          | jq -e '.data.models_ready == true'
curl -s -H "$H" "$B/api/v1/oauth/userinfo"| jq -e --arg a "$EXPECTED_EMAIL" '.data.email == $a'
curl -s -H "$H" "$B/api/v1/oauth/region"  | jq -e '.data.region == "global"'
# only now: create the session and submit work
```

`/auth`, `/oauth/region` and the port-per-home pattern VERIFIED live; `/oauth/userinfo` exists in the
live `/openapi.json` (VERIFIED) and its field names are UNKNOWN — **read one real response before
asserting on `.data.email`.**

Three other credential channels exist, in decreasing cleanliness (all VERIFIED in `overrides.md` /
`env-vars.md`): `api_key_env` on a provider in `config.toml` (re-read from the process environment
every request, so no secret in the file — but *"a running process only sees the environment it
started with"*); the `KIMI_MODEL_*` family (`KIMI_MODEL_NAME` + `KIMI_MODEL_API_KEY` required,
synthesizes a provider **in memory**, writes nothing — the per-launch channel that needs no files);
and `kimi provider add/catalog add/remove/list --json` for scripted config writes (VERIFIED,
`kimi provider --help`).

**Two consequences to design around, and the first one is expensive:**

1. **Session history does not span accounts.** A second `KIMI_CODE_HOME` is a second, *empty*
   session store. Unlike the owner's Claude Code setup — where switcher profiles symlink `projects/`
   into one shared store, which is exactly what makes cross-account resume work — **moving a task
   between Kimi accounts means starting a new session and re-establishing context.** Budget one full
   re-seed per switch.
2. **There is no project-level config file.** *"To isolate config between different projects, point
   `KIMI_CODE_HOME` at different data directories"* (VERIFIED, `config-files.md`). Per-project and
   per-account isolation are the same lever, so the unit is one home per (account × project).

Generic cross-tool resources deliberately stay in the real OS home and are therefore **shared across
every account**: `~/.agents/skills/`, `~/.agents/agents/`, `~/.agents/AGENTS.md` (VERIFIED,
`data-locations.md`). Install the workflow engine once there; know it is also a leak path.

**Changing a RUNNING session's account: impossible.** Nothing switches a live session's identity.
`POST …/profile {agent_config:{model}}` only picks a different alias through the same credential
store; an `api_key_env` rotation explicitly needs a restart; `POST …/runtime {runtime_id}` switches
*where the loop runs* (`40420` unknown, `40926` unavailable — I observed `runtimeId:"local"` in a
real `runtime.set_binding` wire record; what non-`local` runtimes exist is **UNKNOWN** and is the
most interesting undocumented lead on this platform).

**Fallback:** abort (`POST …:abort`, VERIFIED → `{"aborted":true}`), let the session go cold, create
a fresh one under the other home, re-seed from the previous session's `/transcript` or its
`/export` ZIP. **Because quota is pooled per account (§7), this switch is the only way to raise
throughput — so its cost is structural, not incidental.**

---

## 9. Recipe 8 — Deliver an instruction into a running session and confirm it arrived

**VERIFIED** — submission, client-chosen id, idempotency rejection, the async failure path and the
`:steer` error path were all exercised live.

```sh
curl -s -X POST -H "$H" -H 'Content-Type: application/json' -d '{
  "content":[{"type":"text","text":"Stop after the current file and summarise."}],
  "prompt_id":"orch-T77-a1",
  "permission_mode":"auto"
}' "$B/api/v1/sessions/${SID}/prompts"
```

```json
{"code":0,"msg":"success","data":{"prompt_id":"orch-T77-a1","user_message_id":"orch-T77-a1",
 "status":"running","content":[…],"created_at":"2026-09-19T13:28:04.845Z"}}
```

(VERIFIED live.) **`prompt_id` is client-chosen** — the orchestrator names the unit of work before it
exists, which is the thing §3 does not let it do for sessions. Replay is rejected:

```json
{"code":40927,"msg":"prompt_id 'orch-T77-a1' is already in use"}
```

(VERIFIED live.)

> ### The single most important invariant in this adapter
>
> **A `200` with `status:"running"` means *accepted*, never *ran*.** I submitted this prompt to a
> session with **no provider configured at all** and still got `code:0, status:"running"`. The turn
> then failed asynchronously, visible only downstream:
>
> ```
> turn.ended        error {code:"model.not_configured", retryable:false}
> prompt.completed  reason:"failed"
> GET /sessions/{id} → last_turn_reason:"failed", current_prompt_id:null
> ```
>
> (All VERIFIED live.) **Every submission must be paired with a confirmation**, one of:
> `prompt.completed` with a matching `promptId` on the WebSocket; the same record in `wire.jsonl`;
> or polling `last_turn_reason` + `current_prompt_id`. An orchestrator that trusts the POST builds a
> queue that silently does nothing — which is precisely the field-notes failure *"a merge that
> reports success and does nothing"*, one layer up.
>
> **Second divergence from the docs.** The docs say reusing a *completed* prompt's id fails `40903`.
> After mine completed (as `failed`), reuse returned **`40927` "already in use"** — the reservation
> was never released. **Treat a `prompt_id` as burned for the lifetime of the process; mint
> `<task>-<attempt>` per try.**

**Queue control on top of submission** (paths VERIFIED present in the live `/openapi.json`):

| Call | Effect |
|---|---|
| `GET …/prompts` | `{active, queued}`; VERIFIED live → `{"active":null,"queued":[]}` |
| `POST …/prompts:steer {"prompt_ids":[…]}` | force queued prompts **into the running turn** — the HTTP `Ctrl-S` |
| `POST …/prompts/{id}:steer` | single-prompt form |
| `POST …/prompts/{id}:abort` | abort one running prompt |
| `POST …/sessions/{id}:abort` | abort the main agent's turn; VERIFIED live → `{"aborted":true}` |
| `POST …/sessions/{id}:btw` | read-only child agent (`Read`/`Grep`/`Glob`) for a side question that never touches the working context |

`:steer` against an idle session returns a clean, distinguishable error:

```json
{"code":40402,"msg":"no active prompt to steer into"}
```

(VERIFIED live — this code is **not** in the profile.) So the adapter's "nudge" is:
`POST /prompts` → if the session is already busy and the nudge must land *now*,
`POST /prompts:steer` with that id → on `40402`, the turn ended in between, so the plain prompt
already queued correctly. Either way the text is never stranded — the exact defect the field notes
record as *"a nudge that cannot submit stranded text."*

`:btw` on an unconfigured session returns `50001 "no provider configured; complete onboarding via
/login or the providers endpoint"` (VERIFIED live) — not the `{agent_id}` the profile lists, which is
the authenticated-path response.

**Fallback when the server is not running:** none over HTTP. The CLI fallback is
`kimi -p "<instruction>" --session "$SID"`, which appends a turn to the same session (VERIFIED that
session resolution works this way) — but it starts a second process against the same store, so do it
only when no server owns that home.

---

## 10. Recipe 9 — Answer a permission prompt or a clarifying question without a human

**PARTIAL** — both list endpoints were called live and the parameter/body schemas were read from the
live `/openapi.json` and `server-api.md`; **no real pending interaction could be produced** without a
model, so the resolve calls themselves are schema-verified, not observed.

**This is the axis the owner called hardest, and Kimi answers it with typed objects rather than
pixels.**

**Approvals — tool-permission prompts:**

```sh
curl -s -H "$H" "$B/api/v1/sessions/${SID}/approvals?status=pending"
# → {"code":0,"data":{"items":[]}}      (VERIFIED live)
```

`status` is **required and must be `pending`** — the only allowed enum value, read from the live
spec (VERIFIED). Omit it and you get `40001`. Each item is
`{approval_id, session_id, agent_id, turn_id?, tool_call_id, tool_name, action,
tool_input_display, created_at, expires_at}`, where **`expires_at` is `created_at` + 24h**
(VERIFIED, `server-api.md`).

```sh
curl -s -X POST -H "$H" -H 'Content-Type: application/json' -d '{
  "decision":"approved",          # approved | rejected | cancelled   (enum VERIFIED in live spec)
  "scope":"session",              # only value; installs the rule for the rest of the session
  "feedback":"orchestrator: matches the ticket allowlist",
  "selected_label":"Proceed"      # for labelled choices, e.g. a plan review
}' "$B/api/v1/sessions/${SID}/approvals/${APPROVAL_ID}"
# → {"resolved":true,"resolved_at":…} | 40404 no pending approval | 40902 already resolved
```

`scope:"session"` is the programmatic *"approve for this session"* — **one call installs a standing
rule**, so a well-chosen approval converts a recurring interruption into a one-time decision.

**Questions — the agent asking the human something:**

```sh
curl -s -H "$H" "$B/api/v1/sessions/${SID}/questions?status=pending"
# → {"code":0,"data":{"items":[]}}      (VERIFIED live)
```

Each item holds 1–4 `questions`, each `{id, question, header?, body?, options, multi_select?,
allow_other?, other_label?, other_description?}` with 2–4 `options` of `{id, label, description?}`
(VERIFIED, `server-api.md` lines 1150-1200).

```sh
curl -s -X POST -H "$H" -H 'Content-Type: application/json' -d '{
  "answers":{"q_0":{"kind":"single","option_id":"opt_2"},
             "q_1":{"kind":"other","text":"use the staging bucket"}},
  "method":"click",
  "note":"answered by orchestrator policy rule R-12"
}' "$B/api/v1/sessions/${SID}/questions/${QUESTION_ID}"
```

Answer kinds, VERIFIED in `server-api.md`: `single` (`option_id`), `multi` (`option_ids`), `other`
(`text`), `multi_with_other` (`option_ids` + `other_text`), `skipped`.
Errors: `40405` no such pending question, `40902` already resolved, `41002` timed out.

> **Client-library wart, VERIFIED in the docs and worth a unit test:** `:dismiss` **succeeds with
> envelope `code` `40909`**, not `0` — *"clients must special-case this endpoint's success code."*
> A generic `if (code !== 0) throw` wrapper turns every successful dismissal into an error.

**Never miss one.** Three arrival channels: `event.approval.requested` / `event.question.requested`
on the WebSocket; `GET …/snapshot` carries `pending_approvals` and `pending_questions` so a
reconnecting supervisor catches up (VERIFIED live — both keys present, both `[]`); and
`GET /sessions/{id}.pending_interaction` ∈ `none|approval|question` is a one-field poll (VERIFIED
live → `"none"`).

**The policy layer the orchestrator must own.** Answering is mechanical; *deciding* is not. The
recommended shape:

1. **Prevent** what should never be asked: `[[permission.rules]] decision="deny"` — the only
   guardrail that survives `--auto` and `-p` mode.
2. **Auto-approve** an explicit allowlist keyed on `tool_name` + a pattern over `tool_input_display`.
3. **Escalate** anything else to the owner, and **let it expire** — a 24h `expires_at` is a safe
   default failure mode.
4. For questions with no policy match, prefer `:dismiss` (remembering `40909`) or answer
   `{"kind":"skipped"}` rather than guessing; a wrong `single` answer is an instruction the agent
   will act on.

**Fallback — avoid the question entirely.** `--auto` (Never Ask mode) is documented as *"the agent
never asks questions"* and auto-approves everything **including sensitive files and plan exits, with
the dangerous-command guard never active** (VERIFIED, `overrides.md` table). `kimi -p` runs under
`auto` regardless of flags. That removes the interaction surface and removes the safety rails with
it. **Prefer `yolo` + programmatic answering; reserve `auto` for a disposable worktree.**

---

## 11. Recipe 10 — Resume after a crash, and after the machine rebooted

**VERIFIED** — I SIGKILLed the live server, inspected the wreckage, restarted, and recovered the
session *and* the event cursor.

### 11a. Server crash (SIGKILL), the honest simulation

```sh
kill -9 "$PID"
```

**What I observed, in order (all VERIFIED live):**

```
instance file:  SURVIVES, stale — {"pid":15973,"heartbeat_at":1789824606080,…}
pid:            DEAD (kill -0 → ESRCH)
port 58700:     no response (curl → 000)
sessions:       INTACT on disk
```

```sh
kimi session list --json --all       # works with NO server running
# [{"id":"session_375435cb-…","title":"spike-probe","lastPrompt":"say ok",
#   "workDir":"…","sessionDir":"…","createdAt":…,"updatedAt":…,"archived":false,
#   "metadata":{"orch_task":"T-77","orch_attempt":"1"},"lastTurnReason":"failed"}, …]
```

**`metadata` — the orchestrator's own task id — comes back out of a plain CLI call with no server,
no token and no HTTP.** That is the recovery index. (VERIFIED live.)

**Restart, and everything reconnects:**

```sh
kimi web --no-open --port 58700 --log-level info &
```

```
instances/:  stale file SWEPT, one fresh entry           (VERIFIED)
session:     metadata + last_turn_reason + messages intact (VERIFIED)
snapshot:    as_of_seq 15, epoch ep_01M2WXM8MVRF64MJFD70J3E8YR  ← SAME epoch as before the crash
```

### 11b. The finding that makes this platform genuinely resumable

**The event cursor survives a server crash.** Resubscribing after the restart with the cursor saved
*before* it replayed exactly the events lost during the outage:

```sh
{"type":"subscribe","id":"cur-1","payload":{"session_ids":["session_…"],
 "cursors":{"session_…":{"seq":10,"epoch":"ep_01M2WXM8MVRF64MJFD70J3E8YR"}}}}
```

```
REPLAY seq 11  turn.step.interrupted
REPLAY seq 12  turn.ended
REPLAY seq 13  error
REPLAY seq 14  event.session.work_changed
REPLAY seq 15  prompt.completed
ack … cursors:{"session_…":{"seq":15,"epoch":"ep_01M2WXM8MVRF64MJFD70J3E8YR"}}
```

(VERIFIED live, across a SIGKILL + restart.) **A supervisor that persists `{seq, epoch}` per session
loses nothing to a server crash.** And a stale epoch is handled in one round trip — the server hands
back the right one:

```json
{"type":"resync_required","payload":{"session_id":"session_…","reason":"epoch_changed",
 "current_seq":15,"epoch":"ep_01M2WXM8MVRF64MJFD70J3E8YR"}}
```

(VERIFIED live, by subscribing with a bogus epoch.) The other resync trigger is falling more than
`max_event_buffer_size: 1000` events behind (CLAIMED). **Handler for both: `GET …/snapshot`,
resubscribe with the returned `{as_of_seq, epoch}`.**

### 11c. Full machine reboot

```sh
# 1. discover homes
for HOME_DIR in "$HOME"/.kimi-accounts/*; do
  # 2. registry after a reboot is untrustworthy — PIDs are recycled
  for f in "$HOME_DIR"/server/instances/*.json; do
    PORT=$(jq -r .port "$f")
    curl -s -m2 "http://127.0.0.1:$PORT/api/v1/healthz" || rm -f "$f"   # probe, don't trust kill -0
  done
  # 3. restart one server per home, then rebuild the task index from disk
  KIMI_CODE_HOME="$HOME_DIR" kimi web --no-open --port "$PORT" &
  KIMI_CODE_HOME="$HOME_DIR" kimi session list --json --all \
    | jq -r '.[] | select(.metadata.orch_task) | [.metadata.orch_task, .id, .lastTurnReason] | @tsv'
done
```

**Reboot-specific hazards, both established here:**
- **PID recycling** makes `kill -0` unsafe across a boot (§5). Probe `healthz`; `rm` the file if dead.
- **`kimi web` picks the next free port on a busy one, up to 100 retries** (CLAIMED,
  `kimi web --help` documents `--port` default 58627). **Never assume the port you asked for —
  re-read `server/instances/*.json` after every start.**
- **Cron re-injection only revives under `kimi --session`**, not a fresh session, and a recurring task
  older than 7 days fires once with `stale="true"` and deletes itself (CLAIMED, `config-files.md`).
  `KIMI_DISABLE_CRON=1` (§1) makes this a non-issue.
- The docs warn: *"Do not manually edit files inside the `sessions/` directory."* Reading is fine.

**Resuming the work itself**, once the session is found:

```sh
curl -s -X POST -H "$H" -d '{"content":[{"type":"text","text":"Resume. State what you had done."}],
  "prompt_id":"orch-T77-a2"}' "$B/api/v1/sessions/${SID}/prompts"      # NEW attempt id — §9
# or, without a server:
kimi -p "Resume…" --session "$SID"
```

**Fallback when the session is unrecoverable:** `kimi export "$SID" -o out.zip` packages the session
directory (VERIFIED `kimi export --help`; `-y` skips the previous-session confirmation,
`--no-include-global-log` omits the diagnostic log) — re-seed a fresh session from it.

---

## 12. Recipe 11 — Stop cleanly, leaving nothing running

**VERIFIED** — every call here was executed against the live sandbox, in this order.

```sh
# 1. stop the turn, if any
curl -s -X POST -H "$H" -d '{}' "$B/api/v1/sessions/${SID}:abort"
# → {"code":0,"data":{"aborted":true}}                                   (VERIFIED)

# 2. archive, then delete — or archive only, to keep the transcript
curl -s -X POST -H "$H" -d '{}' "$B/api/v1/sessions/${SID}:archive"
# → {"code":0,"data":{"archived":true}}                                  (VERIFIED)
curl -s -X POST -H "$H" -d '{}' "$B/api/v1/sessions/${SID}:delete"
# → {"code":0,"data":{"deleted":true}}                                   (VERIFIED)
curl -s -H "$H" "$B/api/v1/sessions/${SID}"
# → {"code":40401,"msg":"session … does not exist"}                      (VERIFIED)

# 3. stop the server gracefully — replies 200 FIRST, then exits
curl -s -X POST -H "$H" -d '{}' "$B/api/v1/shutdown"
# → {"code":0,"data":{"ok":true}}                                        (VERIFIED)
```

**Post-conditions I confirmed after the shutdown (VERIFIED live):**

```
pid:                         DEAD
server/instances/:           EMPTY   ← cleaned, not stale
port:                        no response
kimi session list --json:    3 sessions, intact
```

**This gives a free, reliable clean-stop test.** After a graceful shutdown the instances directory is
**empty**; after a SIGKILL a **stale file with a dead pid** is left behind (§11a). One `ls` tells the
next run which kind of ending the last one had:

```sh
ls "$KIMI_CODE_HOME"/server/instances/ | grep -q . && echo "UNCLEAN: crashed or still running" \
                                                   || echo "clean"
```

**Shutdown route caveats:** `POST /api/v1/shutdown` is *"mounted only on loopback binds"* — on a
non-loopback bind the route is **404 unless `--allow-remote-shutdown`** (VERIFIED, `kimi web --help`).
Escalation if it is unreachable: `SIGTERM` the registry pid, wait, then `SIGKILL`, then `rm` the
stale instance file yourself.

**What may still be running after all of the above** — check before declaring the machine clean:
- **Background `Bash` tasks.** With `print_background_mode` unset (default `"steer"`) and
  `bash_task_timeout_s` defaulting to **`0` in print mode**, *"only the model itself stops a task."*
  §1 sets both. Enumerate with `GET …/tasks` before shutdown; task output lives at
  `<sessionDir>/tasks/<task_id>/output.log`.
- **Subagents and swarm members** — `[subagent] timeout_ms` / `[swarm] timeout_ms` default to
  7,200,000 ms (2 h) interactively and to **no timeout** in print mode (CLAIMED, `config-files.md`).
- **A `kimi rc` relay**, which holds a single-instance lock at `$KIMI_CODE_HOME/server/rc.json`.
- **A staged auto-update** — disarmed by `KIMI_CODE_NO_AUTO_UPDATE=1` (§1).

**Token hygiene on teardown:** `kimi web rotate-token` invalidates the old bearer token immediately
and every running instance under that home picks the new one up without a restart (VERIFIED,
`kimi web --help`). Worth doing whenever the token may have reached a log — and note that
`$KIMI_CODE_HOME/server.token` is effectively **root-equivalent for that user**, because
`GET /api/v1/fs:content` returns raw bytes of any host file and `POST …/terminals` creates terminals.
**Bind loopback only. Never `--dangerous-bypass-auth`.**

---

## 13. The adapter interface

Eleven operations. **Seven are native single calls, three need emulation, one is impossible.**

| # | Operation | Native? | How, and what it costs |
|---|---|---|---|
| 1 | `preflight()` | **Native** | `kimi --version` + `kimi doctor` + `GET /api/v1/auth` + `/oauth/region`. Must assert **major ≥ 2** — the legacy Python CLI shares the binary name and flips `-c`. |
| 2 | `start(taskId, prompt) → sessionId` | **Emulated** | No `--session-id` that creates. `POST /sessions` (server mints the id) → **immediately** `POST /sessions/{id}/profile` with `{metadata:{orch_task}}`. Cost: one extra round trip; a crash between them leaves an untagged session (mitigate with `title` at creation). |
| 3 | `attach(sessionId)` | **Native** | Browser (`/#token=…`) or `kimi --session <id>` in a terminal — the *same* session, no export. Only real risk is the launcher's `KIMI_CODE_HOME`. |
| 4 | `state(sessionId)` | **Native** | `GET /sessions/{id}` → `{busy, main_turn_active, pending_interaction, last_turn_reason}`, or push via `event.session.work_changed`. Hang detection is `busy && as_of_seq` unchanged. |
| 5a | `readContext(sessionId)` | **Native** | `GET …/status` → `context_tokens`, and `context_usage` as a 0–1 float **once a model resolves**. **Never** read it from `GET /sessions/{id}` — that field reports 0 for a live session. |
| 5b | `compact(sessionId, instruction)` | **Native** | `POST …:compact`. Proof: `PostCompact` hook receipt + `context_tokens` falling. `40910` is ambiguous (nothing to compact **or** busy). |
| 6 | `quota(account)` | **Native** | `GET /oauth/usage?provider=managed:kimi-code`, **or** the raw `…/coding/v1/usages` with the on-disk token and **no server at all**. Branch on `data.kind`, not `code`. `limit7d` is optional by design. |
| 7 | `useAccount(account)` | **Native (new sessions only)** | `KIMI_CODE_HOME` + one port per home, gated on `/auth` + `/oauth/userinfo` + `/oauth/region`. **Sessions do not span homes** — a switch costs a full context re-seed. |
| 8 | `send(sessionId, text) → ack` | **Native, with a mandatory second step** | `POST …/prompts` with a client `prompt_id`; then **confirm** via `prompt.completed`. A 200 means *accepted*, never *ran*. Ids are burned after use (`40927`). |
| 9 | `answer(approval\|question)` | **Native** | `GET …/approvals?status=pending` / `…/questions?status=pending`, then POST a typed decision. `scope:"session"` installs a standing rule. `:dismiss` succeeds with `40909`. |
| 10 | `resume(taskId)` | **Native** | `kimi session list --json --all` recovers `metadata.orch_task` with no server running; `{seq, epoch}` cursors replay across a server crash. |
| 11 | `stop(sessionId)` | **Native** | `:abort` → `:archive` → `:delete` → `POST /api/v1/shutdown`. Empty `instances/` proves a clean stop. |
| — | `switchAccountOfRunningSession()` | **Impossible** | Nothing switches a live session's identity. Abort, create under the other home, re-seed. |

**Four invariants the adapter must encode, or it will be quietly wrong:**

1. **Confirm every prompt downstream.** `status:"running"` is an acknowledgement of receipt, nothing
   more. (§9)
2. **Pong within 20 seconds.** The server heartbeats at 10s and closes at 20s with
   `1001 heartbeat timeout`. (§0.1)
3. **Dispatch on the top-level frame `type`**, not on a `session_event` envelope that never arrives.
   (§0.3)
4. **Re-stamp every fork.** `:fork` copies `metadata` verbatim, so two sessions will claim one task
   id. (§6)

**Six defaults to disarm at launch** (§1): auto-update, `print_background_mode="steer"`,
`bash_task_timeout_s=0` in print mode, unbounded `print_max_turns`, `region=mainland-cn`, and
Node < 22.19.0.

---

## 14. Verdict — **tier-1, with a maturity asterisk**

**On capability, Kimi Code is tier-1, and it is the strongest platform in this scan.** Ten of the
eleven operations are native or one round trip from native. Every axis the owner called
non-negotiable is answered by a documented endpoint that I called on this machine: quota as floats
with reset timestamps, context as an integer and a ratio, compaction triggerable from outside with a
hook receipt to prove it, a running turn steerable over HTTP, and the agent's own questions delivered
as typed objects with stable ids and enumerated options instead of text on a screen. Its transcript
is simultaneously a live WebSocket, a paged REST resource and a durable JSONL file with structured
error codes and per-turn token counts. Its event cursor survives a `kill -9`. Multi-account is one
environment variable, and its credentials sit in a `0600` file rather than the Keychain, so an
unattended run cannot be blocked by a prompt.

**Two capability gaps are real but priced.** It cannot name a session before it exists — a two-call
workaround with a narrow crash window. And sessions do not span accounts, so every account switch
costs one full context re-seed — which matters more than it sounds, because quota is pooled per
account, so extra sessions on one account add no throughput.

**The asterisk is maturity, and it is the whole argument against adopting it today.** Version 2.0.2
was published **the morning of this research**; 2.0.0 landed two days earlier; the control plane
labels itself *"experimental: interface stability is not guaranteed."* The 2.0.1 changelog is a list
of exactly the bugs an unattended orchestrator hits — `-p` exiting early when a cron task fires,
messages landing at the wrong position after a resume, archiving sometimes never finishing,
compaction failing after a model switch — which is reassuring about the maintainers and alarming
about the surface. Three of the profile's own claims proved wrong against the running binary
(§0), which is what a two-day-old API does. There is also **no sandbox**: no container, no seccomp,
no filesystem jail, and 2.0.1 explicitly removed the system-prompt rule that fenced file access to
the working directory. Hooks fail open, so a crashed guard permits.

**The mitigation is mechanical and cheap, which is why the verdict is still tier-1.** The server
publishes `/openapi.json` (105 paths / 126 operations) and `/asyncapi.json` (28 message types)
**generated from the validation schemas it enforces at runtime**, and the docs concede *"when this
page and the live spec ever disagree, the live spec wins."* So: **pin 2.0.2, set
`KIMI_CODE_NO_AUTO_UPDATE=1`, and diff `/openapi.json` + `/asyncapi.json` in CI on every version
bump.** That converts "experimental API" from unbounded risk into a failing test — and it is how I
found all three of §0's corrections in an afternoon.

**Recommended posture:** adopt Kimi Code as a **first-class supervised executor behind Claude Code**,
not as the primary one — pinned, auto-update off, one `KIMI_CODE_HOME` per account, region set
explicitly, `yolo` rather than `auto`, static deny rules for anything destructive, the four
print-mode timeouts set, work confined to a disposable git worktree, and every prompt confirmed
through `prompt.completed`. **Build the adapter against it regardless of whether its runtime is
adopted: its control plane is the shape every other platform in this scan should be measured
against, and writing the adapter is how the orchestrator's own interface gets designed honestly.**

---

## 15. What was run on this machine

`kimi --version` · `kimi --help` · `kimi web --help` · `kimi acp --help` · `kimi login --help` ·
`kimi provider --help` · `kimi provider list --json` · `kimi session --help` ·
`kimi session list --help` · `kimi session list --json --all` · `kimi export --help` ·
`kimi doctor` · `kimi -p … --auto` / `--yolo` / `-S` (conflict cases) · `kimi -p …` (exit 1) ·
`kimi -p … --output-format stream-json` · `kimi -p "x" -S <real id>` · `kimi -p "x" -S <bogus id>`

Live server (`kimi web --no-open --port 58700 --log-level info`, scratch `KIMI_CODE_HOME`):
`GET /api/v1/healthz` (authless, and 401 on `/meta` without a token) · `/api/v1/meta` · `/api/v1/auth` ·
`/api/v1/oauth/region` · `/api/v1/oauth/usage` · `POST /api/v1/sessions` (metadata-drop test) ·
`POST …/profile` (metadata-persist test) · `GET /api/v1/sessions/{id}` · `…/status` · `…/prompts` ·
`POST …/prompts` ×2 (idempotency) · `…/prompts:steer` · `…/approvals?status=pending` ·
`…/questions?status=pending` · `…/goal` · `…/snapshot` · `…/transcript/ops` · `GET /api/v1/sessions?busy=true` ·
`POST …:compact` · `…:abort` · `…:btw` · `…:fork` · `…:archive` · `…:delete` · `POST /api/v1/shutdown` ·
`/openapi.json` (3.0.3, 105 paths) · `/asyncapi.json` (3.1.0, 28 messages)

WebSocket `ws://127.0.0.1:58700/api/v1/ws`: handshake + `server_hello` · wrong-shape `subscribe`
(silent no-op) · correct `subscribe` + ack with cursors · server `ping` observed twice ·
**no-pong disconnect (`1001 heartbeat timeout` at 20s)** · **cursor replay of seq 11–15 across a
SIGKILL + restart** · `resync_required` with `reason:"epoch_changed"` on a bogus epoch

Lifecycle: **SIGKILL of the live server** → stale instance file, dead pid, dead port, sessions intact
on disk → restart → stale file swept, session + metadata + epoch recovered → graceful shutdown →
empty `instances/`, sessions intact.

Files read from the sandbox home: `server.token` · `server/instances/<id>.json` ·
`session_index.jsonl` · `workspaces.json` · `sessions/<wd>/<sid>/agents/main/wire.jsonl`

Source (`MoonshotAI/kimi-code` @ 2.0.2, MIT): `packages/kap-server/src/instanceRegistry.ts`
(`HEARTBEAT_INTERVAL_MS = 15_000`, `pidAlive`, `sweepStale`, `listLiveInternal`) ·
`packages/oauth/src/managed-usage.ts` (`kimiCodeUsageUrl`, `parseQuotaUsages`, wire→domain mapping) ·
`packages/oauth/src/region.ts` · `packages/oauth/src/storage.ts` (0700/0600, atomic write) ·
`apps/kimi-code/src/cli/goal-prompt.ts` (`GOAL_EXIT_CODES = {complete:0, blocked:3, paused:6}`) ·
`apps/kimi-code/src/cli/options.ts` · `apps/kimi-code/src/cli/headless-exit.ts` ·
`packages/agent-core-v2/test/features/externalHooks/integration.test.ts` (`SessionHeartbeat`)

Docs (in-repo `docs/en/`): `reference/server-api.md` · `reference/kimi-command.md` ·
`configuration/config-files.md` · `configuration/env-vars.md` · `configuration/overrides.md` ·
`customization/hooks.md`

**Not verified, and flagged as such above:** any call that needs an authenticated account — a
successful quota payload, a real compaction, a real pending approval or question, a second account's
`userinfo` shape, and the content of a model's stream-json reply.
