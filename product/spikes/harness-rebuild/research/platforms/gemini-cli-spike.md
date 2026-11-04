# Google Gemini CLI — orchestrator adapter spike

**Written:** 2026-09-19. **Version driven:** `@google/gemini-cli@0.60.0`. **Machine:** owner's Mac,
darwin 25.5.0. **Companion:** the capability profile at `research/platforms/gemini-cli.md` — read
that for *what the platform can do*; this file is *how to drive it*.

**Installed on the owner's machine?** **No.** `which gemini` → not found (VERIFIED). Everything below
was run against an isolated install at
`…/scratchpad/gemini-sandbox` with `GEMINI_CLI_HOME` and `HOME` pointed inside the sandbox.

**What this pass spent: nothing.** Every model-bound call was made with
`GEMINI_API_KEY=invalid-key-for-probe-only` and rejected at 400 `API_KEY_INVALID` with
`"total_tokens":0` (VERIFIED, captured below). The owner's `~/.gemini/` was read once and **not
modified** — its mtime is still `Jul 11 00:22` (VERIFIED after every probe).

**Evidence tags.** **VERIFIED** = run on this machine during this pass, or read verbatim out of the
installed bundle. **CLAIMED** = docs/README only. **UNKNOWN** = could not establish. No flag name
here is guessed; each came from `gemini --help`, a subcommand's `--help`, the shipped bundle source,
or an error the CLI actually printed.

---

## 0. Read this first — the account gate

The profile's §0 governs everything here: **Gemini CLI stopped serving Google AI Pro/Ultra and free
Code Assist on 2026-06-18.** A working session needs a paid Gemini API key, Vertex AI, a Code Assist
Standard/Enterprise seat, or a gateway endpoint. **Nothing in this spike changes that**, and two
recipes below (6, 7) have materially different answers depending on which of those the owner holds.

Because I had no valid credential, recipes are verified to the last point before the credential is
required, and that boundary is stated explicitly in each. **No recipe is marked `verified: true` on
the strength of reading source alone.**

---

## 1. Eleven corrections to the profile — each found by running the thing

Several of these invalidate a design the profile proposes. Read them before writing an adapter.

| # | The profile says | What actually happens | Evidence |
|---|---|---|---|
| 1 | A `SessionStart` hook is "the single cleanest wiring on this platform" — it hands the supervisor the session id and transcript path | **It does not fire in ACP mode at all.** Two full `--acp` runs with a user-level `SessionStart` hook installed produced **zero** new hook lines across `initialize` + `session/new`. It fires only for headless/TUI launches | VERIFIED — ran both, hook file line count unchanged |
| 2 | `session/cancel` → "✅ (`cancelPendingPrompt`)" | It is a **notification, not a request**. Sent with an `id` it returns `-32601 "Method not found": session/cancel`. Sent without an id it is accepted — and if no turn is in flight it throws internally (`Not currently generating`) and logs `Error handling notification … -32603` to stderr | VERIFIED — both forms run; `AGENT_METHODS.session_cancel` is handled only in `notificationHandler` |
| 3 | (not covered) | **`--acp` ignores SIGTERM, SIGINT and SIGHUP.** All three left the process alive past 3.5 s. The only clean stop is **closing stdin** → `exit code=0` in **23 ms**; otherwise SIGKILL | VERIFIED — all three signals tested in one run |
| 4 | Trust "gates project agents, project hooks and project skills" | It also gates **approval modes**, and it does so **silently in headless mode**: `--approval-mode yolo` in an untrusted folder prints `Approval mode overridden to "default" because the current folder is not trusted` to **stderr as a warning** and runs on. Over ACP the same thing is a hard error: `session/set_mode yolo` → `-32603 … "Cannot enable privileged approval modes in an untrusted folder."` | VERIFIED — both run; source is `Config.setApprovalMode` |
| 5 | Untrusted folders disable hooks | **User-level hooks fire regardless.** A hook in `$GEMINI_CLI_HOME/.gemini/settings.json` fired on a `--skip-trust` run in an untrusted folder. Only **project-level** hooks are suppressed. This is what makes hook-based supervision viable at all | VERIFIED — captured payload |
| 6 | `SessionEnd` is a first-class hook event | **It does not fire on the failure paths that matter.** No `SessionEnd` on the fatal exit-144 path, and none on SIGKILL. Do not use it as "the session finished" | VERIFIED — hook file never created across every probe |
| 7 | `session/load` is implemented (`loadSession: true`) | True, but it **requires a credential before it will do anything**: `-32000 "Authentication required"`. It is not usable as a cheap unauthenticated probe | VERIFIED — ran it |
| 8 | Trust is configured via `trustedFolders.json` or `GEMINI_CLI_TRUST_WORKSPACE=true` | Both work, but they are **not equivalent**. `checkPathTrust` reads the env var **first**, before `security.folderTrust.enabled` is even consulted, and returns `{isTrusted:true, source:"env"}`. The env var is the only lever that cannot be overridden by a settings file | VERIFIED — source read; empirically it is what made `set_mode yolo` succeed |
| 9 | Sessions that complete no model turn are deleted on exit | True **on a clean exit only**. A SIGKILLed process never runs `deleteCurrentSessionIfNotResumableAsync`, so **the transcript survives**. Killing hard preserves more than stopping politely | VERIFIED — transcripts from SIGKILLed ACP runs are still on disk; those from clean runs are gone |
| 10 | A 429 is mapped to `RequestError(429, …)` in ACP | Confirmed in shape: the JSON-RPC **`error.code` carries the upstream HTTP status verbatim**. I observed `{"code":400,"message":"…API_KEY_INVALID…"}` from `session/prompt`. So the in-band limit test is literally `error.code === 429` | VERIFIED for the mechanism (400 observed); 429 itself UNKNOWN by direct test |
| 11 | Permission outcomes include `proceed_always_and_save` | Only **`proceed_once` and `cancel` are always offered**. `proceed_always*` is suppressed entirely when `getDisableAlwaysAllow()` is set, and `proceed_always_and_save` is only added when `enablePermanentToolApproval` is true. **The supervisor must answer with an `optionId` the agent actually sent**, not one it hoped for | VERIFIED — `toPermissionOptions` read in full |

---

## 2. The three launch shapes, decided once

Every ticket is one of these before anything else is decided. They are **mutually exclusive per
process**.

| | **HEADLESS** (`-p … -o stream-json`) | **ACP** (`--acp`) | **TUI** (interactive) |
|---|---|---|---|
| Session id | **you assign** (`--session-id <uuid>`) | **agent assigns** (`session/new`) | you assign or resume |
| Instruction in-flight | **impossible** — no stdin protocol | `session/prompt` (**aborts** the in-flight turn) | human types |
| Permission prompts | **auto-denied** (`ask_user` → `confirmed:false`) | `session/request_permission` → you answer | human answers |
| SessionStart hook | **fires** | **does not fire** (correction 1) | fires |
| Live progress | tail the JSONL, or stream-json on stdout | `session/update` push | on screen |
| Owner can take over | no | no | yes |
| Clean stop | process ends by itself | **close stdin** (23 ms) | `/quit` |

**Recommendation — and it differs from the profile's.** The profile recommends ACP wholesale. Run
**ACP for the control lane**, but understand you are trading away the free session→transcript
mapping (correction 1) and gaining an unkillable process (correction 3). Concretely:

- **ACP** for any ticket that must be supervised, nudged, or asked a question. Compute the
  transcript path yourself (§4a).
- **HEADLESS** for fire-and-forget work that is fully pre-authorised by policy, where auto-deny is
  an acceptable failure mode and the exit code plus the final `result` frame is all you need.
- **TUI** only as a *handoff target* — kill the ACP process, relaunch `gemini --resume <uuid>` in a
  terminal, and the owner takes over the same conversation.

---

## 3. Preflight — installed, authenticated, which account

There is **no `gemini auth` subcommand** (VERIFIED — `gemini --help` lists only `mcp`, `extensions`,
`skills`, `hooks`, `gemma`). Preflight is therefore file inspection plus one cheap probe.

```bash
# a. present and what version
command -v gemini || { echo "NOT INSTALLED"; exit 1; }
gemini --version                      # -> "0.60.0"

# b. which config home this shell would use
echo "${GEMINI_CLI_HOME:-$HOME}/.gemini"

# c. what credential material exists in it  (presence only — never read the contents)
H="${GEMINI_CLI_HOME:-$HOME}/.gemini"
for f in oauth_creds.json google_accounts.json settings.json installation_id; do
  [ -f "$H/$f" ] && echo "present: $f" || echo "absent:  $f"
done

# d. which OAuth identity is active, if any
jq -r '.active // "none"' "$H/google_accounts.json" 2>/dev/null

# e. which auth type the ENVIRONMENT selects  (getAuthTypeFromEnv, VERIFIED)
#    precedence as implemented: GOOGLE_GENAI_USE_GCA -> oauth-personal
#                               GOOGLE_GENAI_USE_VERTEXAI -> vertex-ai
#                               GOOGLE_GEMINI_BASE_URL -> gateway
#                               GEMINI_API_KEY / GOOGLE_API_KEY -> gemini-api-key
```

**The authoritative probe** — it enumerates auth methods without spending a token, because
`initialize` is answered before any credential is used:

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"fs":{"readTextFile":true,"writeTextFile":true}}}}' \
  | gemini --acp 2>/dev/null | head -1 | jq '.result.agentInfo, [.result.authMethods[].id]'
```

Real output, VERIFIED on this machine:

```json
{ "name": "gemini-cli", "title": "Gemini CLI", "version": "0.60.0" }
[ "oauth-personal", "gemini-api-key", "vertex-ai", "gateway" ]
```

- **Success:** the binary answers, version parses, and the config home holds `oauth_creds.json`
  (OAuth path) **or** the environment carries `GEMINI_API_KEY` / Vertex vars.
- **Failure:** `gemini` not found; or a headless run exits **41** (`FATAL_AUTHENTICATION_ERROR`) —
  observed for missing auth.
- **Fallback:** there is none for "is this credential actually good". `initialize` succeeds with an
  invalid key (VERIFIED — my whole session ran on `invalid-key-for-probe-only`). **The only honest
  liveness test for a credential is one real turn**, which costs money. Budget one cheap
  `gemini -m gemini-3.1-flash-lite -p "ok"` per account per day as a canary and cache the verdict.

---

## 4. Start a task headless, pinned id, structured output

```bash
export GEMINI_CLI_HOME=/path/to/accounts/acctA     # §9 — pins the account
export GEMINI_CLI_TRUST_WORKSPACE=true             # §11 — or yolo is silently downgraded
SID=$(uuidgen | tr 'A-Z' 'a-z')

gemini \
  --session-id "$SID" \
  --approval-mode yolo \
  -o stream-json \
  -m gemini-3.1-flash-lite \
  -p "$(cat ticket.md)" \
  > "runs/$SID.jsonl" 2> "runs/$SID.err"
echo "exit=$?"
```

**Use `-o stream-json`, never `-o json`.** Reproduced independently this pass on the same failing
input (VERIFIED):

```
-o json         -> exit 144, stdout 0 bytes,    stderr = raw Node stack trace
-o stream-json  -> exit 144, stdout 1491 bytes, last line {"type":"result","status":"error",…}
```

`-o json` has at least one fatal route that bypasses its own formatter. An orchestrator that parses
it will see a silent empty success.

**Stdin is concatenated *ahead of* `-p`** (VERIFIED, help text), so `cat brief.md | gemini -p "now
do it"` works — but **not** with `-i/--prompt-interactive`, which refuses piped stdin and exits 42.

**`--session-id` is create-only.** Reusing one is refused with
`Session ID "…" already exists. Use --resume to resume it, or provide a different ID.` → exit 42
(VERIFIED, profile). The launcher must know whether it is creating or resuming and switch flags.

**The `init` frame echoes your id back** — always assert it before trusting the run:

```json
{"type":"init","timestamp":"2026-09-19T13:30:22.610Z","session_id":"11111111-2222-3333-4444-555555555501","model":"auto"}
```

- **Success:** `init.session_id` equals `$SID`, and the final line is
  `{"type":"result","status":"success",…}`.
- **Failure:** exit 42 (bad input / duplicate id), 41 (auth), 52 (config), **144** (generic fatal —
  *absent from the `ExitCodes` table*, so never branch on the code alone).
- **Fallback:** branch on `result.status`, not on the exit code. Treat "no `result` line at all" as
  a crash and go to §12.

### 4a. Map a session id to its transcript — the ACP case

In headless/TUI the `SessionStart` hook hands it over (§5). **In ACP it does not fire (correction 1),
so compute it.** The rule, VERIFIED on disk and in `SessionSelector.sessionExists`:

```bash
# slug: $GEMINI_CLI_HOME/.gemini/projects.json maps abs cwd -> slug
SLUG=$(jq -r --arg p "$PWD" '.projects[$p]' "$GEMINI_CLI_HOME/.gemini/projects.json")
# filename suffix is the FIRST 8 CHARACTERS of the session id, not the id
ls "$GEMINI_CLI_HOME/.gemini/tmp/$SLUG/chats/session-"*"-${SID:0:8}.jsonl"
```

Real path produced this pass (VERIFIED):

```
$GEMINI_CLI_HOME/.gemini/tmp/work/chats/session-2026-09-19T13-30-11111111.jsonl
```

The suffix is a plain 8-character prefix of whatever the id string is — a sibling file from earlier
research is `session-2026-09-19T13-23-skills-l.jsonl` for `"sessionId":"skills-list-session"`
(VERIFIED). **Do not assume the id is a UUID when slicing.**

---

## 5. Start the same task in a visible terminal

```bash
osascript -e 'tell application "iTerm2"
  tell current window to create tab with default profile
  tell current session of current window to write text "cd '"$PWD"' && \
    GEMINI_CLI_HOME='"$GEMINI_CLI_HOME"' GEMINI_CLI_TRUST_WORKSPACE=true \
    gemini --session-id '"$SID"' -i \"$(cat ticket.md)\""
end tell'
```

`-i, --prompt-interactive` *"Execute the provided prompt and continue in interactive mode"*
(VERIFIED, `--help`) — this is the attach-and-type shape. It **refuses piped stdin**
(`Error: The --prompt-interactive flag cannot be used when input is piped from stdin.`, exit 42), so
the prompt must be an argument, not a pipe.

**Wire the supervisor in through a user-level hook** — this is the only place a TUI session tells an
outside process anything. Written to `$GEMINI_CLI_HOME/.gemini/settings.json`, and **verified to
fire even in an untrusted folder** (correction 5):

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "/opt/orch/hook-session-start.sh" }] }],
    "AfterModel":   [{ "hooks": [{ "type": "command", "command": "/opt/orch/hook-after-model.sh" }] }]
  }
}
```

Real `SessionStart` payload captured this pass, **with zero model tokens spent** (VERIFIED):

```json
{
  "session_id": "11111111-2222-3333-4444-555555555501",
  "transcript_path": "…/.gemini/tmp/work/chats/session-2026-09-19T13-30-11111111.jsonl",
  "cwd": "…/gspike/work",
  "hook_event_name": "SessionStart",
  "timestamp": "2026-09-19T13:30:22.601Z",
  "source": "startup"
}
```

`source` is `"startup" | "resume" | "clear"` (VERIFIED) — which is how the supervisor distinguishes
a fresh launch from a reattach.

- **Success:** the hook file gains a line whose `session_id` is the one you pinned.
- **Failure:** nothing is written → the folder is untrusted **and** you put the hook at project
  level; move it to the user-level settings file.
- **Fallback:** poll `projects.json` + the `chats/` glob from §4a.

> ⚠ **`--yolo` in a visible terminal is still gated by trust**, and the downgrade is a stderr warning
> the owner will not see scroll past. Always set `GEMINI_CLI_TRUST_WORKSPACE=true` in the spawn.

---

## 6. Is it alive, working, waiting, or finished?

There is **no status command**. The answer differs per launch shape.

### ACP — the only shape with a real answer

Maintain a small state machine from the traffic you already receive:

| Observation | State |
|---|---|
| process alive, no `session/prompt` outstanding | **idle** |
| `session/prompt` request outstanding | **working** |
| `session/update` with `sessionUpdate: "agent_message_chunk"` / `"agent_thought_chunk"` / `"tool_call"` / `"tool_call_update"` arriving | **working, making progress** |
| a `session/request_permission` **request from the agent** is outstanding | **waiting on you** |
| `session/prompt` resolved with `stopReason` | **finished this turn** |
| stdout closed / `exit` event | **dead** |

`sessionUpdate` vocabulary, VERIFIED from the bundled SDK schema: `agent_message_chunk`,
`agent_thought_chunk`, `tool_call`, `tool_call_update`, `plan`, `user_message_chunk`,
`available_commands_update`, `current_mode_update`.

`stopReason` values, VERIFIED (`zStopReason`): `end_turn`, `max_tokens`, `max_turn_requests`,
`refusal`, `cancelled`.

**"Working" needs a timeout, not just a flag.** A `session/prompt` that never resolves and emits no
updates is indistinguishable from a wedged process. Use last-`session/update` age.

### Headless / TUI — liveness only

```bash
kill -0 "$PID" 2>/dev/null && echo alive || echo dead
# progress = transcript mtime, which advances on every flush
stat -f %m "$TRANSCRIPT"
```

- **Success:** mtime advancing ⇒ working. Final `{"type":"result"}` on stdout ⇒ finished.
- **Failure mode to expect:** **an interactive session that loses its TTY exits 0.**
  `setupTtyCheck` calls `gracefulShutdown` with `ExitCodes.SUCCESS` (VERIFIED, profile). A terminal
  closed overnight looks exactly like a clean success. **Never judge an attached session by its exit
  code** — require the `result` frame or a transcript whose last `$set` shows the work done.
- **`SessionEnd` is not a finish signal** (correction 6): it did not fire on the fatal path or on
  SIGKILL.

---

## 7. Read context fullness, force compaction, prove it

### Read — this works, and it is cheap

Context fullness is `promptTokenCount ÷ tokenLimit(model)`. `DEFAULT_TOKEN_LIMIT = 1048576`;
`GEMMA_4_TOKEN_LIMIT = 256000` (VERIFIED, `tokenLimit()` read this pass).

**The `AfterModel` hook is the supervisor's meter.** Its payload carries
`llm_response.usageMetadata.{promptTokenCount, candidatesTokenCount, totalTokenCount}` (VERIFIED —
`toHookLLMResponse` builds it from `response.usageMetadata`). Hook script:

```bash
#!/usr/bin/env bash
# /opt/orch/hook-after-model.sh  — stdin is the hook payload
IN=$(cat)
SID=$(jq -r .session_id <<<"$IN")
PT=$(jq -r '.llm_response.usageMetadata.promptTokenCount // empty' <<<"$IN")
[ -n "$PT" ] && printf '%s %s %s\n' "$(date -u +%FT%TZ)" "$SID" "$PT" >> /opt/orch/ctx.log
```

I **verified the hook fires and the envelope is correct** by capturing a real `BeforeModel` payload
this pass (VERIFIED — keys `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `timestamp`,
`llm_request{model,messages,config}`). The `AfterModel` twin could not be captured because the
invalid key never produced a model *response* — **`usageMetadata` is read-in-source, not observed.**

Over ACP there is a second source that needs no hook: `session/prompt`'s response carries
`_meta.quota.token_count.{input_tokens,output_tokens}` and `model_usage[]` (VERIFIED, profile).

### Trigger — you cannot, from outside

Both routes are closed, and the profile's empirical result reproduces:

- `gemini -p "/compact"` **sends the literal string `/compact` to the model** and bills you for it.
  `compressCommand.action` returns nothing, and the headless dispatcher only forwards
  `submit_prompt` results.
- **There is no `compact` command over ACP.** The ACP registry holds only `memory`, `extensions`,
  `init`, `restore`, `about`, `help` (VERIFIED, profile).

**What you *can* do is tune the automatic one, before launch:**

```json
{ "model": { "compressionThreshold": 0.5 } }
```

Exact key path `model.compressionThreshold`, VERIFIED this pass (`settings.model?.compressionThreshold`
in the config builder). `requiresRestart: true`.

### Prove it — and do not use the obvious hook

**`PreCompress` fires *before* the threshold check, so it also fires on every NOOP** (VERIFIED,
profile, `chatCompressionService` call order). A supervisor counting `PreCompress` events will report
compactions that never happened.

**The honest proof is the token count falling** across two consecutive `AfterModel` payloads for the
same `session_id`:

```bash
awk '$2==SID {if (prev && $3 < prev*0.7) print "COMPACTED", prev, "->", $3; prev=$3}' \
    SID="$SID" /opt/orch/ctx.log
```

- **Success:** a same-session `promptTokenCount` that drops sharply between turns.
- **Failure:** the count keeps climbing past your line ⇒ auto-compaction did not engage.
- **Fallback — and this is the realistic plan: handoff, not compaction.** Watch
  `promptTokenCount`; when it crosses your line, end the session, summarise the transcript yourself,
  and open a new one seeded with the summary. Over ACP that is one `session/new`. You pay for the
  summarisation turn and you lose the CLI's own compaction quality.

---

## 8. Read remaining quota and the reset time

### The endpoint is real and reachable — and it is not on the CLI surface

**No flag prints quota**, `gemini -p "/stats"` sends the literal string `/stats` to the model, and
`stats` is absent from the ACP command registry (all VERIFIED, profile). The orchestrator must call
the endpoint itself.

I confirmed the endpoint is **live** this pass (VERIFIED):

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota \
  -H 'Content-Type: application/json' -d '{}'
# -> 401
```

and the 401 body names the backing gRPC method, which is the strongest evidence it exists as
documented (VERIFIED, verbatim):

```json
{"error":{"code":401,"status":"UNAUTHENTICATED","details":[{"reason":"CREDENTIALS_MISSING",
 "metadata":{"method":"google.internal.cloud.code.v1internal.PredictionService.RetrieveUserQuota"}}]}}
```

The real call:

```bash
curl -s -X POST \
  "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota" \
  -H "Authorization: Bearer $(jq -r .access_token "$GEMINI_CLI_HOME/.gemini/oauth_creds.json")" \
  -H "Content-Type: application/json" \
  -d "{\"project\":\"$CLOUDAICOMPANION_PROJECT\"}"
```

Response shape, read off `Config.refreshUserQuota()` (VERIFIED this pass):

```jsonc
{ "buckets": [ { "modelId": "gemini-3.1-pro-preview",
                 "remainingFraction": 0.42,
                 "remainingAmount": "123",          // optional
                 "resetTime": "2026-09-20T00:00:00Z" } ] }
```

The parser's arithmetic, verbatim from source — **replicate it exactly or your numbers will differ
from the CLI's**: when `remainingAmount` is present, `remaining = parseInt(remainingAmount)` and
`limit = round(remaining / remainingFraction)`; when it is absent, `limit = 100` and
`remaining = round(remainingFraction * 100)`.

**The window is daily and pooled across sessions** (VERIFIED, profile: *"Usage limits span all
sessions and reset daily."*).

- **Success:** `buckets[]` non-empty, each with a `resetTime`.
- **Failure:** 401 ⇒ the OAuth token needs refreshing; 404/400 on `v1internal` ⇒ Google moved an
  **undocumented** surface, which it may do without notice.
- **Fallback, and it is the likely path:** **on a plain `GEMINI_API_KEY` there is no quota endpoint
  at all** — `getCodeAssistServer()` returns nothing and `refreshUserQuota()` returns `undefined`
  immediately (VERIFIED, profile). Count your own turns and treat 429 as the only signal.

### Detecting a limit hit in band

```
ACP:        session/prompt rejects with  {"code":429,"message":"Rate limit exceeded. Try again later."}
stream-json: final frame  {"type":"result","status":"error", "error":{…}}
```

The JSON-RPC `error.code` carries the upstream HTTP status verbatim — I observed `code: 400` for an
invalid key this pass (VERIFIED), so `error.code === 429` is the test. **No reset time accompanies
it**; that only comes from `retrieveUserQuota`. The HTTP layer retries `429` three times first, so a
limit hit costs several seconds of silence before it surfaces.

**Set the overage policy deliberately before any unattended run.** Key path `billing.overageStrategy`,
enum `ask | always | never`, **default `ask`** (VERIFIED this pass in the settings schema). The
default **blocks on a dialog** when quota runs out.

```json
{ "billing": { "overageStrategy": "never" } }
```

---

## 9. Switch a new session to a different account

**One `GEMINI_CLI_HOME` per account, exported at spawn.** `homedir()` returns
`process.env["GEMINI_CLI_HOME"] ?? os.homedir()`, and every account-shaped file hangs off
`<that>/.gemini/` (VERIFIED, `utils/paths.ts`).

Verified on this machine — two homes, two identities, owner's real config untouched:

```bash
for A in acctA acctB; do
  GEMINI_CLI_HOME=/opt/orch/accounts/$A gemini --list-sessions >/dev/null 2>&1
  echo "$A $(cat /opt/orch/accounts/$A/.gemini/installation_id)"
done
```
```
acctA 5faba960-1e00-45f0-9162-e8fcd041ae96
acctB edf30748-2bfb-448a-987a-f9671197d58d
```

**Verify the switch before work starts** — the assertion is that the home you set is the home in use:

```bash
test -f "$GEMINI_CLI_HOME/.gemini/oauth_creds.json" || echo "WARN: no OAuth creds in this home"
jq -r '.active' "$GEMINI_CLI_HOME/.gemini/google_accounts.json"   # -> the expected email
```

`google_accounts.json` is `{active, old[]}` and `oauth_creds.json` is a single file — **one identity
per home, full stop** (VERIFIED, profile). Concurrency requires concurrent homes.

> ⚠ **Do not use `$GEMINI_CLI_HOME/settings.json`.** The variable is read as *HOME* by `homedir()`
> (settings at `$GEMINI_CLI_HOME/.gemini/settings.json`) but as the *config dir* by the memory
> bootstrap in `bundle/gemini.js` (VERIFIED, both call sites). Only the `.gemini/` form is
> load-bearing.

**Changing a running session's account: treat as impossible.** ACP `authenticate` exists and the
`gateway` method advertises `restartRequired:"false"`, but it is scoped to the *agent*, and whether
open sessions re-credential is **UNKNOWN**. In headless mode the account is fixed for the process
life. **Kill and relaunch.**

**Worth flagging:** `GOOGLE_GEMINI_BASE_URL` selects `AuthType.GATEWAY`, advertised in the handshake
as `{"id":"gateway","name":"AI API Gateway","_meta":{"gateway":{"protocol":"google"}}}` (VERIFIED —
captured here). Gemini CLI is a **host for any Google-protocol endpoint**, not only for Google.

---

## 10. Deliver an instruction into a running session

**Headless: impossible.** There is no `--input-format`; the string does not appear in the bundle at
all (VERIFIED, profile). `stream-json` is output-only. Stdin in headless mode carries exactly one
thing: a TTY keypress handler treating Ctrl-C/ESC as abort. **You can cancel a headless run; you
cannot talk to it.**

**ACP: native, and acknowledged.**

```json
{"jsonrpc":"2.0","id":7,"method":"session/prompt",
 "params":{"sessionId":"<sid>","prompt":[{"type":"text","text":"stop refactoring and run the tests"}]}}
```

`session/prompt` is a **request**, so arrival is acknowledged by a correlated response, not inferred.
Verified end to end this pass — the request was accepted, dispatched, and answered in **227 ms** with
a correlated error from the model layer (the credential being invalid); the *transport* round trip is
proven:

```json
{"code":400,"message":"…API key not valid…"}
```

- **Success:** a response arrives bearing your `id`. On a valid credential it carries
  `stopReason` and `_meta.quota.token_count`.
- **Failure:** `-32601` (wrong method name), `-32602` (bad params), or a timeout ⇒ the process is
  wedged; go to §13.
- **⚠ The semantic that shapes the design:** `prompt()`'s first statement is
  `this.pendingPrompt?.abort()` (VERIFIED, profile). **A mid-run `session/prompt` aborts the turn in
  flight.** There is no queue and no append. Nudge *between* turns, or accept the loss.

---

## 11. Answer a permission prompt without a human

**Headless: you cannot — and the default silently destroys work.** In headless mode an `ask_user`
decision resolves to `confirmed:false`: the tool is **denied, not queued** (VERIFIED, profile). A
long unattended `-p` run in `default` mode will grind through a ticket having every write refused.

**Prevent it, in this order:**

1. **Trust the folder** — otherwise your `--approval-mode yolo` is silently overridden to `default`
   (correction 4). Verified failure output:
   ```
   Approval mode overridden to "default" because the current folder is not trusted.
   ```
   Fix, either of:
   ```bash
   export GEMINI_CLI_TRUST_WORKSPACE=true          # wins over everything (correction 8)
   ```
   ```json
   // $GEMINI_CLI_HOME/.gemini/trustedFolders.json   — a FLAT map, VERIFIED (loadTrustedFolders)
   { "/abs/path/to/repo": "TRUST_FOLDER" }
   ```
   Levels: `TRUST_FOLDER | TRUST_PARENT | DO_NOT_TRUST` (VERIFIED, `TrustLevel` enum).
   `security.folderTrust.enabled` defaults to **true** (VERIFIED, schema).
2. **Pin an approval mode**: `--approval-mode yolo` for full autonomy, `plan` for read-only recon.
3. **Pin a Policy Engine file** — `--allowed-tools` is deprecated and says so at runtime. Use
   `--policy <paths>` / `--admin-policy <paths>` (TOML). `check()` returns `allow`/`deny`/`ask_user`.

**ACP: native, and this is the platform's best feature.** The agent sends
`session/request_permission` **to you** as a JSON-RPC *request* and blocks on the reply:

```json
{"jsonrpc":"2.0","id":9,"method":"session/request_permission",
 "params":{"sessionId":"…","options":[{"optionId":"proceed_once","name":"Allow","kind":"allow_once"},
                                      {"optionId":"cancel","name":"Reject","kind":"reject_once"}],
           "toolCall":{"toolCallId":"…","status":"pending","title":"…","kind":"edit"}}}
```

You answer:

```json
{"jsonrpc":"2.0","id":9,"result":{"outcome":{"outcome":"selected","optionId":"proceed_once"}}}
```

**Answer only with an `optionId` the agent actually offered** (correction 11). `proceed_once` and
`cancel` are the base pair and are always present; `proceed_always`, `proceed_always_server`,
`proceed_always_tool` depend on the tool type and are suppressed entirely by `getDisableAlwaysAllow()`;
`proceed_always_and_save` appears only when `enablePermanentToolApproval` is on — and it is the one
that **writes the decision into the policy file**, so the supervisor teaches once and is never asked
again (all VERIFIED, `toPermissionOptions` + `ToolConfirmationOutcome` read this pass).

My probe client answered these automatically; no permission request arrived because no tool call ever
ran on an invalid key. **The wiring is verified; a live permission round trip is UNKNOWN by direct
test.**

**Clarifying questions have no structured event.** A question arrives as ordinary
`agent_message_chunk` text and the turn ends `stopReason:"end_turn"`. Detection is heuristic; the
answer is just another `session/prompt`.

---

## 12. Resume after a crash, and after a reboot

```bash
gemini --resume "$SID" -o stream-json -p "continue where you left off"
```

`-r, --resume` accepts **`latest`, a full UUID, or a 1-based index** — the UUID branch is
`sortedSessions.find(s => s.id === trimmedIdentifier)`, checked *before* the index parse (VERIFIED,
profile). The `--help` text mentions only `latest` and an index; **resume by exact id works and is
undocumented.**

Sessions are **scoped to the project directory**, so the orchestrator must resume from the same cwd.

### The hole, and it is the important part

**A session that dies before completing one model turn leaves nothing to resume**, and the remnant is
actively deleted: `deleteCurrentSessionIfNotResumableAsync()` runs in the exit cleanup path, and
`getSessionFiles` filters non-resumable sessions out of listings. Reproduced this pass — after every
clean probe run, `chats/` was empty and:

```
$ gemini --resume <id> -p "hi"
Error resuming session: No previous sessions found for this project.
```

**But a hard kill preserves it** (correction 9): transcripts from SIGKILLed ACP runs are still on
disk, because cleanup never ran. If you must kill, **kill hard** — you keep more.

**`--list-sessions` is hostile to parsers** (VERIFIED, reproduced verbatim this pass): it prints
`No previous sessions found for this project.` **with no trailing newline**, and then a stack trace
for the current session's not-yet-written file:

```
No previous sessions found for this project.Error loading conversation record from JSONL: [Error: ENOENT: …]
```

- **Success:** the resumed run's `SessionStart` hook reports `"source":"resume"`.
- **Failure:** `Error resuming session: No previous sessions found for this project.` ⇒ there is
  nothing there; **relaunch from the ticket, not the session.**
- **After a reboot:** nothing of Gemini's survives — no daemon, no service. The orchestrator
  relaunches from its own ticket state. Sessions that had ≥1 completed turn are resumable by id;
  the rest are gone. **Keep the ticket, not the session, as the unit of recovery.**
- Turn on `general.checkpointing.enabled` (default **false**, `requiresRestart: true`, VERIFIED) if
  you want file-level rollback. It needs a working `git` (it builds a shadow repo) and
  `cleanupCheckpoints()` garbage-collects on every startup without being asked.

**Does `--resume <uuid>` actually restore a session that completed a real turn?** The code path is
unambiguous but **UNKNOWN by direct test** — it needs a paid credential. This is the single largest
untested assumption in the adapter.

---

## 13. Stop it cleanly, leaving nothing running

**Signals do not work.** Verified this pass, all three, on a live `--acp` process:

```
SIGTERM: IGNORED — still alive after 3500ms
SIGINT:  IGNORED — still alive after 3500ms
SIGHUP:  IGNORED — still alive after 3500ms
```

**Closing stdin is the clean stop.** Verified: `exited code=0 sig=null after 23ms`.

```python
proc.stdin.close()                       # ACP: exits 0 in ~23ms
proc.wait(timeout=10)
if proc.poll() is None:
    proc.kill()                          # SIGKILL — the only signal that lands
```

For headless runs, the process ends by itself; to abort early, SIGKILL.

**Then verify nothing is left:**

```bash
pgrep -f 'gemini-cli/bundle/gemini.js' || echo "clean"
# --worktree lanes leave a git worktree behind
git worktree list
```

- **Success:** exit 0 within a second of the stdin close, and no matching processes.
- **Failure:** still alive after your timeout ⇒ SIGKILL and accept that `SessionEnd` never fired
  (correction 6) and that the transcript is preserved (correction 9).
- **Watch for `RELAUNCH_EXIT_CODE = 199`** — the CLI relaunches itself in some configurations
  (`relaunchOnExitCode`, suppressed by `GEMINI_CLI_NO_RELAUNCH`). **A supervisor tracking PIDs must
  expect the process to replace itself.** Set `GEMINI_CLI_NO_RELAUNCH` for unattended lanes.

---

## 14. The adapter interface

| # | Capability | Headless (`-p`) | ACP (`--acp`) | Notes |
|---|---|---|---|---|
| 1 | Preflight | **native** (partial) | **native** (partial) | no `auth` subcommand; credential validity needs a paid canary turn |
| 2 | Headless + pinned id + structured output | **native** | n/a | `--session-id` + `-o stream-json`; never `-o json` |
| 3 | Visible terminal | **native** (`-i`) | **impossible** — ACP replaces the TUI | handoff via `--resume` |
| 4 | Liveness / working / waiting / finished | **emulated** — pid + transcript mtime only | **native** | headless cannot express "waiting" |
| 5 | Read context fullness | **native** (`AfterModel` hook) | **native** (`_meta.quota` on prompt) | ÷ 1,048,576 |
| 5b | Trigger compaction | **impossible** | **impossible** | tune `model.compressionThreshold`; otherwise **emulate handoff** |
| 5c | Prove compaction | **emulated** — token count falling | same | `PreCompress` fires on NOOPs — do not use |
| 6 | Read quota + reset | **emulated** — out-of-band `v1internal` call | same | **impossible on the API-key path** |
| 6b | Detect limit hit in band | **native** (`result.status:"error"`) | **native** (`error.code === 429`) | no reset time attached |
| 7 | Account switch for a NEW session | **native** (`GEMINI_CLI_HOME`) | **native** | running-session switch: **impossible** — relaunch |
| 8 | Deliver an instruction | **impossible** | **native**, acknowledged | mid-run prompt **aborts** the turn |
| 9 | Answer a permission prompt | **impossible** — auto-denied | **native** (`session/request_permission`) | must echo an offered `optionId` |
| 10 | Resume after crash / reboot | **native** (`--resume <uuid>`) | `session/load` (needs auth) | **nothing to resume if no turn completed** |
| 11 | Clean stop | **native** | **native** — *close stdin* | **all signals ignored**; SIGKILL is the only one |

**Impossible on both, no workaround:** triggering compaction from outside; changing a running
session's account; reading quota on an API-key-only account.

**The adapter is therefore two drivers, not one:**

1. **an ACP client** — `initialize`, `session/new`, `session/prompt`, the `session/cancel`
   *notification*, `session/set_mode`, `session/set_model`, and — the load-bearing part — **serving**
   `session/request_permission`, `session/update` and `fs/*`. This is the whole build.
2. **a hook sidecar** — two shell scripts writing to append-only logs, giving `SessionStart`
   (id → transcript, headless/TUI only) and `AfterModel` (context meter). Twenty lines each.

Plus a spawn wrapper that exports `GEMINI_CLI_HOME`, `GEMINI_CLI_TRUST_WORKSPACE=true` and
`GEMINI_CLI_NO_RELAUNCH`, and a quota poller that is **only built if the owner is on the OAuth/Code
Assist path**.

### Support tier

**TIER 2 — workable with emulation, and gated on the account question.**

Not tier 1, for three reasons that no amount of adapter code fixes:

- **Quota (axis E) is unreadable on the path the owner is most likely to hold.** With a plain
  `GEMINI_API_KEY` there is no endpoint at all. The owner called this axis non-negotiable, and it is
  absent precisely in the likely configuration.
- **Compaction cannot be triggered from outside** in any mode. Handoff must be built and paid for.
- **Supervision and human takeover are mutually exclusive per process.** ACP replaces the TUI, and
  ACP is also the only shape where permissions can be answered.

It is comfortably above tier 3, because over ACP the platform answers the two axes most CLIs fail:
**intervention is acknowledged over a correlated channel, and permission prompts are answerable
programmatically with a durable "always" option.** That is a better intervention surface than the
owner's current harness has today.

**Three things to tell the owner:**

1. **Settle the account question before any adapter work.** Without a Code Assist Standard/Enterprise
   seat or a paid key there is nothing to orchestrate, and on an API-key-only account the quota axis
   is simply unavailable.
2. **Adopt ACP as the orchestrator's protocol even if Gemini CLI is never adopted.** It is a
   published standard, several agents speak it, and `session/request_permission` is exactly the
   shape the interview asked for — the supervisor *answers the session's own question* over a
   correlated channel, and `proceed_always_and_save` makes the answer stick.
3. **Budget for the operational sharp edges**, none of which are in the docs: a process that ignores
   SIGTERM, a `SessionStart` hook that silently does not fire in ACP, an approval mode that silently
   downgrades in an untrusted folder, and a `-o json` that emits nothing when it fails.

### The five silent overnight killers, each with its counter

| Killer | Counter |
|---|---|
| untrusted folder ⇒ `yolo` silently becomes `default` ⇒ every tool denied | export `GEMINI_CLI_TRUST_WORKSPACE=true` in the spawn and assert the mode after `session/new` |
| `-o json` emits nothing on a fatal ⇒ looks like empty success | use `-o stream-json`; require a final `result` frame |
| session dies before turn 1 ⇒ nothing to resume, remnant deleted | recover from the **ticket**, never the session |
| `SIGTERM` ignored ⇒ "stopped" lanes still running and still spending | stop by closing stdin; escalate to SIGKILL; `pgrep` to confirm |
| `overageStrategy: "ask"` ⇒ quota exhaustion waits for a human | set it to `never` (or `always`) deliberately, before the run |

---

## 15. Still open after this pass

| # | Question | Axis | Why it matters |
|---|---|---|---|
| 1 | Does `--resume <uuid>` restore a session that completed a real model turn? | B | the entire crash-recovery story rests on it; only the failure case is testable without spending |
| 2 | Is `AfterModel`'s `llm_response.usageMetadata` populated as the source implies? | D | the context meter is built on it; I captured `BeforeModel` but never a response |
| 3 | Does `--resume` combined with `--acp` resume, or is it ignored in favour of `session/load`? | B, G | `--acp --resume latest` starts and answers `initialize` cleanly (VERIFIED), but with no prior session there was nothing to prove |
| 4 | A live `session/request_permission` round trip, with the real `options[]` array on the wire | G | the answer format is verified from source; the request was never triggered |
| 5 | What exit code **144** denotes — it is absent from `ExitCodes` and I reproduced it three times | A, J | supervisors branch on exit codes |
| 6 | Does ACP `authenticate` re-credential already-open sessions? | F | decides whether account switching ever avoids a relaunch |
| 7 | Stability of the undocumented `v1internal:retrieveUserQuota` surface | E | the owner's non-negotiable axis rests on an internal API |
| 8 | Antigravity CLI (`agy`) — the named successor | all | if Gemini CLI is account-gated out, this is the actual Google target, and it is still unexamined |

---

## Appendix — what was run, and what it proves

All probe artefacts under `…/scratchpad/gspike/`:

| File | What it proves |
|---|---|
| `acp.mjs` / `acp-log.json` | the ACP supervisor client: `initialize`, `session/new`, unimplemented-method census, `set_mode`/`set_model`, `session/prompt` round trip |
| `acp2.mjs` | the same under `GEMINI_CLI_TRUST_WORKSPACE=true` — proves trust is what unblocks `set_mode yolo` |
| `acp3.mjs` | `session/cancel` as a notification, `session/load` → `Authentication required`, stdin-close shutdown (exit 0 / 23 ms), `--acp --resume latest` |
| `sig.mjs` | SIGTERM / SIGINT / SIGHUP all ignored |
| `hook-sessionstart.jsonl`, `hook-beforemodel.jsonl` | real hook payloads, captured at zero token cost; and the absence of `hook-sessionend.jsonl` |
| `oj.out` / `os.out` | `-o json` 0 bytes vs `-o stream-json` 1491 bytes on the identical failing input |

**Commands run on this machine (all read-only, self-contained, or against an invalid key):**
`gemini --version`; `gemini --help`; `gemini {mcp,extensions,skills,hooks,gemma} --help`;
`gemini --list-sessions`; `gemini -p … -o {json,stream-json}`; `gemini --session-id … -p …`;
`gemini --skip-trust --approval-mode yolo -p …`; `gemini --approval-mode yolo -p …` (untrusted);
five `--acp` sessions driven over JSON-RPC; two unauthenticated `POST`s to
`cloudcode-pa.googleapis.com` (`retrieveUserQuota`, `loadCodeAssist`, both 401); and static reads of
`node_modules/@google/gemini-cli/bundle/*.js`.

**No model turn was ever completed — every API-bound call returned `"total_tokens":0`. The owner's
`~/.gemini/` was not modified.**
