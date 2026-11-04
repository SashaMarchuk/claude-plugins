# Amp (Sourcegraph) — orchestrator adapter spike

**Written:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0, arm64).
**Binary under test:** `@ampcode/cli` **`0.0.1789819237-ge34793`**, self-reported as
*"released 2026-09-19T12:00:37.000Z"*, `buildTimestamp` `2026-09-19T12:03:41.556Z`.
**Companion:** read `amp.md` (the capability profile) first. This document does not repeat it; it
corrects it in §0 and then gives the eleven recipes.

**Amp is not installed on this machine.** VERIFIED today, again:

```
$ which amp                                          -> not found
$ for p in ~/.amp ~/.config/amp ~/.cache/amp ~/.local/share/amp \
           ~/Library/Application\ Support/amp /Library/Application\ Support/ampcode; do ...
  /Users/sasha-marchuk/.amp                            absent
  /Users/sasha-marchuk/.config/amp                     absent
  /Users/sasha-marchuk/.cache/amp                      absent
  /Users/sasha-marchuk/.local/share/amp                absent
  /Users/sasha-marchuk/Library/Application Support/amp absent
  /Library/Application Support/ampcode                 absent
$ ls /Users/sasha-marchuk/Work/claude-plugins/.amp     -> No such file or directory
$ ls /Users/sasha-marchuk/Work/claude-plugins/AGENTS.md -> No such file or directory
$ node --version -> v22.18.0        $ which bun -> ~/.nvm/versions/node/v22.18.0/bin/bun
```

So everything below marked **VERIFIED-ran** was run against the published binary unpacked into the
session scratchpad, executed with a redirected `HOME`, with either **no** API key (offline paths) or
a **deliberately invalid** key (`sgamp_fake_000`) so that the run dies at the server's 401 instead of
spending the owner's credits. No login was performed, no thread was created, no credit was spent, and
nothing under the owner's `$HOME` was written. Read access is a different matter — see correction 9.

```bash
# the harness every command below was run through
SB=/private/tmp/.../scratchpad/amp-sandbox
AMP=$SB/pkg/ampcode-cli-darwin-arm64-0.0.1789819237-ge34793/package/amp
HOME=$SB/home XDG_CONFIG_HOME=$SB/home/.config AMP_SKIP_UPDATE_CHECK=1 "$AMP" "$@"
```

**Tags.** VERIFIED-ran = executed here. VERIFIED-doc = read verbatim in official docs or in the
binary's own help/completion data. CLAIMED = vendor prose only. UNKNOWN = needs one authenticated
session and could not be established.

---

## 0. Twenty corrections to the profile — read these before writing code

The profile (`amp.md`) was written from the same binary. Running it harder changed twenty things.
Several of them will silently break an adapter written from the profile alone.

**1. `-h` on a third-level command prints the ROOT help. Every time. Including
`amp permissions add -h`.** The profile says `amp usage -h` and `amp permissions add -h` "printed
correct per-command usage". `amp usage -h` does. `amp permissions add -h` does not. VERIFIED-ran on
eight third-level commands — `permissions add`, `permissions test`, `plugins exec`, `mcp add`,
`orb service start`, `runner list`, `oauth-clients create`, `skill list` — **all eight dumped the
top-level command list**, as did `threads context`, `threads list`, `threads search`,
`threads markdown`, `threads raw`, `threads export`, `threads usage`. The single observed exception is
`amp threads continue -h`, which prints correctly. Two-level commands (`amp usage -h`, `amp top -h`,
`amp update -h`, `amp threads -h`) are reliable.
**Consequence:** the only authoritative flag surface is `amp completions zsh`. Parse it (§1).

**2. `amp permissions test` ignores every argument after the tool name.** VERIFIED-ran:

```
$ amp --settings-file S permissions test Bash 'rm -rf /' --json
{ "tool": "Bash", "arguments": {}, "action": "allow",
  "matchedEntry": { "tool": "Bash", "action": "allow" }, "matchIndex": 7, "source": "user" }
```

— with `{"tool":"Bash","matches":{"cmd":"*rm -rf*"},"action":"reject"}` sitting first in that same
settings file. `arguments` is **always `{}`**. So `matches.cmd` / `matches.*` rules are *never*
exercised by `permissions test`. You can preflight a **tool name**, not a command line. The profile
called this "a genuinely good orchestrator affordance"; it is good, but it is blunt, and an adapter
that preflights `git push` against a `*git*push*` rule will get a false "allow".

**3. `amp permissions add delegate '<tool>' --to <prog>` fails. Flag order is load-bearing.**
VERIFIED-ran, all four forms:

```
$ amp permissions add delegate '*' --to orch-perm-helper
Error: Invalid permission format: Delegate action requires --to argument at line 1, column 1
$ amp permissions add --to orch-perm-helper delegate '*'
Error: Invalid permission format: Expected action (allow, reject, ask, delegate) at line 1, column 1
$ amp permissions add delegate '*' --to=orch-perm-helper
Error: Invalid permission format: Unexpected character '=' at line 1, column 18
$ amp permissions add delegate --to orch-perm-helper '*'          # <- the only form that works
```

The "line 1, column N" wording shows the CLI re-serialises argv into a small DSL and parses that.
`--to` must sit **between the action and the tool pattern**, and `--to=value` is rejected.

**4. There IS a local log, it IS structured JSONL, and it IS supervisable — but only if you ask
for it.** The profile calls `~/.cache/amp/logs/cli.log` "a CLI diagnostic log, not a transcript" and
concludes "there is nothing to tail". Both undersell it. With `--log-level info|debug|trace` (or
`AMP_LOG_LEVEL`) the file carries, per run: `Starting Amp CLI.` → `{version, buildTimestamp}`;
`Initializing CLI context` → `{argv, hasAmpAPIKey, hasAmpURL, hasSettingsFile, nodeEnv}`;
`Execution mode resolved` → `{executeMode, executeFlag, noTUI, streamJson, stdoutTTY, stderrTTY}`;
`Using settings file` → `{settingsPath, workspaceSettingsPath}`; `Global configuration initialized`
→ `{settingsKeys}`; `using file-based secrets storage` → `{dataDir}`; `API key lookup before login`
→ `{found, deferAuth, ampURL}`; `Server status resolved` →
`{status, isAuthenticated, isError, errorMessage}`; `Finished loading skills` →
`{totalSkills, skillNames, skillBaseDirs, errorCount}`. Every line carries `pid`.
**Without `--log-level` the file is byte-for-byte empty.** VERIFIED-ran both ways.

**5. …but the log sink is asynchronous and is routinely lost.** VERIFIED-ran: the *identical*
command (`--log-level info --log-file X threads list --json`, invalid key) produced 15,598 bytes
once and 0 bytes on the next two attempts from a different cwd. Treat the log as a *best-effort*
forensic channel, never as a control channel. `stderr` + exit code are the reliable pair.

**6. There are three log files, not one.** `~/.cache/amp/logs/cli.log`,
`~/.cache/amp/logs/headless.log`, `~/.cache/amp/logs/plugin-runtime.log`. VERIFIED-ran (all three
appeared in the sandbox HOME). `plugin-runtime.log` is the most interesting: it shows that plugins
run in a **separate process** driven over a **stdio JSON-RPC**, with observed methods
`event`, `dispose`, `events.list`, `agent-mode.list`, `comm…`:

```
[…] Plugin runtime starting {"pluginPath":"…/orch-probe.ts","argv":["…/amp","/…/amp-plugin-runtime-NYQnGY/plugin-runtime.ts","…/orch-probe.ts"]}
[…] Setting up stdio RPC
[…] Handling request {"method":"event","id":"1"}
[…] Handling request {"method":"dispose","id":"2"}
[…] Received SIGINT, exiting
```

**7. `--daemon` is dead.** VERIFIED-ran: `amp --daemon` → `Error: amp --daemon has been replaced.
Use amp --no-tui instead.` One of the profile's three "tantalising" hidden flags is a tombstone.

**8. `--observe` and `--headless` both take a thread URL or ID.** VERIFIED-ran, from the binary's own
validation message:

```
$ amp --observe=zzz -x hi
Error: Invalid thread URL or ID: zzz
Provide a valid thread URL (e.g., https://ampcode.com/threads/T-12345678-…) or ID (e.g., T-12345678-…)
$ amp --headless=zzz -x hi        # identical error
```

With a well-formed id both proceed to the auth check, so they are real code paths, not stubs. Their
*semantics* remain UNKNOWN, but they are now narrowed from "no idea" to "attach to an existing
thread" — which makes `--observe` the single most valuable thing left to test on the first
authenticated session (see §12).

**9. Amp reads the owner's entire Claude Code skill library, and `HOME` redirection does not stop
it.** This is the correction with the largest blast radius. VERIFIED-ran with `HOME` pointed at the
sandbox and cwd inside the owner's repo:

```json
{"message":"Finished loading skills","totalSkills":107,"errorCount":2,
 "skillBaseDirs":["file:///Users/sasha-marchuk/.agents/skills/nomad-devops", …,
                  "file:///Users/sasha-marchuk/.claude/skills/gsd-manager", …]}
```

The mechanism is **ancestor-directory walking from cwd**, not `$HOME` resolution. Proof: running the
same command from `/private/tmp/.../amp-sandbox/outside` gives

```json
{"searchRoots":["…/outside","…/amp-sandbox","…/scratchpad","…/<session>",
                "file:///private/tmp/claude-501","file:///private/tmp","file:///private"],
 "totalSkills":12,"errorCount":0}
```

— it walks to the filesystem root either way. So an orchestrator that runs Amp anywhere under
`/Users/sasha-marchuk` gets 107 skills injected, and `HOME=/tmp/whatever` changes nothing.
The off switch works: with `"amp.skills.disableClaudeCodeSkills": true` and
`"amp.skills.disableGlobalAgentsSkills": true`, the same cwd yields **`"totalSkills":18`**.
VERIFIED-ran (107 → 18).

**Two of the owner's skills do not parse in Amp.** VERIFIED-ran, `errorCount: 2`:

| Path | Error |
|---|---|
| `~/.claude/skills/log-time/SKILL.md` | `YAMLParseError: Nested mappings are not allowed in compact mappings at line 2, column 14` |
| `~/.claude/skills/tde-prestep-validate/SKILL.md` | same |

Cause in both: an unquoted `description:` whose value contains `": "`. Two more warn:
`~/.claude/skills/handoff/SKILL.md` and `~/.claude/skills/grill-me/SKILL.md` →
`Unknown frontmatter field "disable-model-invocation"`.

**10. `--settings-file` does not suppress the workspace settings file.** VERIFIED-ran — the log names
both, every run:

```json
{"message":"Using settings file",
 "settingsPath":"…/orch-settings.json",
 "workspaceSettingsPath":"/Users/sasha-marchuk/Work/claude-plugins/.amp/settings.json"}
```

and `workspaceRoot` is resolved to the **git root**, not cwd (from `…/round-1`, workspaceRoot was
`/Users/sasha-marchuk/Work/claude-plugins`; from a non-git dir it was cwd itself). Since workspace
settings **override** user settings, a repo can still redefine the agent's permissions out from under
the orchestrator's `--settings-file`. The profile flagged the precedence; this pins the exact path
the adapter must check before every run.

**11. `amp usage` has an undocumented structured backdoor.** The profile calls §E structurally
unreadable because `amp usage` has no `--json`. It has no `--json`, but the CLI itself fetches the
balance as JSON. VERIFIED-ran by pointing `AMP_URL` at a local server and recording the request:

```
POST  {AMP_URL}api/internal?userDisplayBalanceInfo
Authorization: Bearer sgamp_SECRETVALUE_123
Content-Type: application/json
X-Amp-Client-Application: CLI
X-Amp-Client-Type: cli
X-Amp-Device-Fingerprint: v1:fp_<redacted>
X-Amp-Installation-ID: <installation-id>

{"method":"userDisplayBalanceInfo","params":{"markdown":true,"details":false}}
```

The `details` parameter is presumably what `--details` flips, but that is **inferred, not observed**:
against a local listener `amp usage --details` never reached this method (it aborts earlier, in
`getUserInfo` validation), so only the bare-`usage` body above is VERIFIED-ran.
**`markdown:false` is the lever** —
the parameter exists precisely because a non-markdown rendering exists. Other observed methods on the
same endpoint: `getUserInfo` (`params:{}`) and `loadPlugins`
(`params:{supportedPluginFormats:["directory-v1","directory-v2"],knownVersions:{}}`). This is an
internal, undocumented, unversioned RPC — but it is the CLI's own wire, and it turns §E from
"impossible" into "unsupported but available". Response shape UNKNOWN (needs a real token).

**12. No API key ⇒ the command BLOCKS on an interactive login. Invalid key ⇒ it fails fast.**
VERIFIED-ran, and this is the difference between an unattended preflight that reports and one that
hangs forever:

```
$ unset AMP_API_KEY; amp tools list --json
No API key found. Starting login flow...
To log in, visit:
https://auth.ampcode.com/device?user_code=ZBPK-CRCW
and confirm that the code shown matches: ZBPK-CRCW
Waiting for confirmation in the browser...         # ← blocks indefinitely

$ AMP_API_KEY=sgamp_fake_000 amp tools list --json
Error: Invalid or missing API key. Run 'amp login' to authenticate.     # stderr, exit 1
```

**13. `--stream-json` emits zero lines when auth fails.** VERIFIED-ran:
`amp -x "say hi" --stream-json` with a bad key → **stdout empty**, stderr one line, exit 1. No init
frame, no `result` frame. An adapter that waits for a `session_id` before writing its bookkeeping row
must therefore treat "child exited, zero stdout lines" as a first-class outcome.

**14. `amp update --target-version <v> --porcelain` exists.** VERIFIED-ran (`amp update -h`, which is
two-level and therefore honest):

```
--target-version <version>  Update to a specific version
--porcelain                 Print a machine-readable result to stdout:
                            "updated <version>" or "no update needed"
```

That is the version pin the profile asked for and could not name.

**15. `amp threads list --installation-id <v>` exists.** VERIFIED (completion tree). The installation
id lives at `<HOME>/.local/share/amp/device-id.json` (`{"installationID":"<installation-id>"}`) and is
**derived from HOME**, so it is per-profile — while `X-Amp-Device-Fingerprint` is per-machine and
shared across accounts. That pair is an adapter lever: separate HOMEs ⇒ separate installation ids ⇒
`threads list --installation-id` can scope a listing to one orchestrator role.

**16. `amp threads continue` takes MULTIPLE thread ids, and `--pick` is deprecated.** VERIFIED-ran
(`amp threads continue -h`): *"Each thread can be a thread URL or ID … When multiple threads are
given, all are resumed and the first is shown in the foreground."* and
*"--pick … (DEPRECATED: picker is now the default)"*. The profile lists `--pick` without the
deprecation, and misses the multi-resume.

**17. `amp threads archive --unarchive` exists.** VERIFIED (completion tree). The profile notes that
`-x` archives the thread and that `--include-archived` finds it; it does not mention that you can put
it back.

**18. The init frame has a field the profile omits: `agent_mode?: string`.** VERIFIED-doc
(docs/cli/streaming-json type block). Useful: it is the only place the effective mode is echoed.

**19. The command tree is 189 paths, not 361.** VERIFIED-ran (parsed from `amp completions zsh`
today). The full list is in §12's appendix note. Nothing was removed that the profile relied on; the
count was simply wrong.

**20. `amp plugins exec` takes a filesystem PATH, not a plugin name — and it runs offline, with no
auth, with no network.** VERIFIED-ran, which closes the profile's open question #6:

```
$ amp plugins exec orch-probe session.start
Error: plugin path not found: orch-probe

$ amp plugins exec ~/.config/amp/plugins/orch-probe.ts session.start \
      --data '{"thread":{"id":"T-12345678-0000-0000-0000-000000000000"}}'
[plugin] [orch-probe] ORCH_PROBE loaded
[plugin] [orch-probe] ORCH_PROBE session.start thread={"thread":{"id":"T-12345678-…"}}
```

`--data` must carry `thread.id` or dispatch fails with
`Error: Plugin event session.start is missing thread.id`. The plugin's top-level function runs, the
handler fires, and `amp.logger.log` output reaches stdout prefixed `[plugin] [<name>]`. What it does
**not** give you offline is the thread API — `amp.threads.get(id)` needs the server. So
`plugins exec` is a *unit-test harness for plugin code*, not a shell-side door into a live thread.

---

## The launch shape, decided once

Amp offers four executors. The adapter should not pretend they are interchangeable.

| Shape | Command | Who holds the agent | Survives laptop sleep | Can be steered mid-turn | Owner can type into it |
|---|---|---|---|---|---|
| **L — local piped** | `amp -x … --stream-json --stream-json-input` | the orchestrator's child process | **no** | **yes** (stdin) | no |
| **T — local TUI** | `amp` (no `-x`) | a terminal the owner owns | no | no (keystrokes only) | **yes** |
| **O — orb** | `amp -ox …` | Amp's servers | **yes** | via `threads continue -ox` | via ampcode.com |
| **R — runner** | `amp -x … --executor runner:<id>` | another machine you own | **yes** | via `threads continue -ox` | via ampcode.com |

**Recommendation for the orchestrator: shape L for everything it must supervise closely, shape R for
anything that must outlive the laptop.** L is the only shape where the supervisor owns the transcript
pipe and the steering channel in the same process. R is the only shape in this whole platform scan
where the queue keeps running when the orchestrator's Mac closes its lid, and it costs nothing extra
(runners are free; orbs are billed by the minute).

Everything below is written for shape L unless it says otherwise.

### The environment, fixed once, for every recipe

```bash
# ---- orchestrator/amp/env.sh  — source this before any amp invocation ----
export AMP_API_KEY="$(cat "$ROLE_DIR/token")"        # sgamp_… long-lived. NEVER from `amp login`.
export AMP_URL="https://ampcode.com/"                # explicit; per-process, honoured (VERIFIED-ran)
export AMP_SETTINGS_FILE="$ROLE_DIR/settings.json"   # per-role isolation
export AMP_LOG_FILE="$RUN_DIR/amp-cli.log"
export AMP_LOG_LEVEL=info                            # without this the log file stays EMPTY
export AMP_SKIP_UPDATE_CHECK=1
export HOME="$ROLE_DIR/home"                         # isolates settings/cache/installation-id ONLY
export NO_ANIMATION=1                                # documented equivalent of amp.terminal.animation:false
```

```jsonc
// $ROLE_DIR/settings.json — the unattended baseline
{
  "amp.updates.mode": "disabled",          // default is "auto"; a release ships every ~3h
  "amp.runner.autoUpdate.enabled": false,  // default is true; runners restart into new binaries
  "amp.notifications.enabled": false,
  "amp.notifications.system.enabled": false,
  "amp.thread.autoArchiveOnQuit": false,
  "amp.skills.disableClaudeCodeSkills": true,    // 107 -> 18 skills (VERIFIED-ran)
  "amp.skills.disableGlobalAgentsSkills": true,
  "amp.showCosts": true,
  "amp.network.timeout": 60,                     // default 30
  "amp.tools.enable": ["Bash","Read","create_file","edit_file","glob","Grep","oracle","Task",
                       "todo_read","todo_write","undo_edit","finder"],
  "amp.permissions": [
    { "tool": "*", "action": "delegate", "to": "orch-perm-helper" }
  ]
}
```

Every default in that block was read out of the binary's own settings reference and example
configuration (`amp --help`, VERIFIED-ran): `amp.updates.mode: "auto"`,
`amp.runner.autoUpdate.enabled: true`, `amp.network.timeout: 30`,
`amp.thread.autoArchiveOnQuit: false`, `amp.tools.disable: ["browser_navigate","builtin:edit_file"]`
as the shipped example.

---

## 1. Preflight — installed, authenticated, which account

```bash
#!/usr/bin/env bash
# orchestrator/amp/preflight.sh    exit 0 = ready, 10 = missing, 11 = unauthenticated,
#                                  12 = version drift, 13 = hostile workspace settings
set -uo pipefail

# --- 1a. installed, and at which exact build -------------------------------- VERIFIED-ran
command -v amp >/dev/null || exit 10
VER="$(amp --version)"                 # -> 0.0.1789819237-ge34793 (released 2026-09-19T12:00:37.000Z, 1h ago)
BUILD="${VER%% *}"
[ -n "${AMP_PIN:-}" ] && [ "$BUILD" != "$AMP_PIN" ] && {
  amp update --target-version "$AMP_PIN" --porcelain    # -> "updated <v>" | "no update needed"
  [ "$(amp --version | cut -d' ' -f1)" = "$AMP_PIN" ] || exit 12
}

# --- 1b. NEVER run an auth-needing command with an unset key ---------------- VERIFIED-ran
# unset AMP_API_KEY makes `amp tools list` print a device code and block forever.
[ -n "${AMP_API_KEY:-}" ] || exit 11
case "$AMP_API_KEY" in sgamp_*) ;; *) echo "not a long-lived access token" >&2; exit 11;; esac

# --- 1c. is the key good?  cheapest authenticated call ---------------------- VERIFIED-ran (failure path)
if ! OUT="$(amp threads list --json --limit 1 2>&1 >/dev/null)"; then
  case "$OUT" in
    *"Invalid or missing API key"*) exit 11 ;;      # exact string, on stderr, exit 1
    *"Cannot reach Amp servers"*)   exit 14 ;;      # network / AMP_URL wrong
    *) echo "$OUT" >&2; exit 15 ;;
  esac
fi

# --- 1d. which account?  ---------------------------------------------------- see caveat
amp usage                          # human text; the only personal-scope identity+balance surface
# structured, unsupported:
curl -sS -X POST "${AMP_URL}api/internal?getUserInfo" \
  -H "Authorization: Bearer $AMP_API_KEY" -H 'Content-Type: application/json' \
  -H 'X-Amp-Client-Application: CLI' -H 'X-Amp-Client-Type: cli' \
  -d '{"method":"getUserInfo","params":{}}'

# --- 1e. does the repo get to rewrite our permissions? --------------------- VERIFIED-ran
WS_ROOT="$(git -C "$TASK_CWD" rev-parse --show-toplevel 2>/dev/null || echo "$TASK_CWD")"
[ -f "$WS_ROOT/.amp/settings.json" ] && { echo "workspace settings present: $WS_ROOT/.amp/settings.json" >&2; exit 13; }

# --- 1f. prove our settings file is the one in force ----------------------- VERIFIED-ran
amp permissions test Bash --json | jq -e '.source == "user"' >/dev/null || exit 13

# --- 1g. record the flag surface for THIS build ---------------------------- VERIFIED-ran
amp completions zsh > "$RUN_DIR/amp-completions.zsh"     # the only honest flag reference (correction 1)
```

**The command-tree extractor**, because `-h` cannot be trusted (correction 1):

```python
# orchestrator/amp/flagsurface.py  — VERIFIED-ran; produced 189 command paths on this build
import re, json, sys
s = open(sys.argv[1]).read()                       # amp-completions.zsh
i = s.index("printf '%s' '") + len("printf '%s' '")
seg = s[i:s.index("\n", i)]
tree = json.loads(seg[:seg.rindex("}") + 1])
def walk(n, path=()):
    p = path + (n["names"][0],) if n.get("names") else path
    yield " ".join(p), n
    for c in n.get("commands") or []: yield from walk(c, p)
for path, node in walk(tree):
    opts = [(o.get("short") and o.get("long") and f'{o["short"]}, {o["long"]}') or o.get("long") or o.get("short")
            for o in node.get("options") or []]
    print(path, "|", ",".join(filter(None, opts)))
```

**Success looks like:** exit 0, `amp --version` matches the pin, `permissions test Bash --json`
reports `"source":"user"`, and no `.amp/settings.json` in the task's git root.

**Failure looks like:** exit 11 with `Invalid or missing API key. Run 'amp login' to authenticate.`
on stderr (VERIFIED-ran, exact string); or, if `AMP_API_KEY` is unset, **no failure at all** — a
device-code prompt and an indefinite block (correction 12). Guard 1b is not optional.

**Fallback when the platform cannot do it:** there is no `amp whoami` and no `amp doctor`
(VERIFIED — neither appears in the 189-path tree). If you will not call the internal endpoint,
identity is only obtainable by eye from `amp usage`, or by tagging every thread with a label that
encodes the role (§2) and reading it back with `amp threads list --json`.

---

## 2. Start a task headless, with a pinned session id, capturing structured output

### The blunt truth first

**Amp cannot be given a session id.** VERIFIED by exhaustion over the 189-path tree including hidden
options: there is no `--thread-id`, `--session-id` or `--id` anywhere, and `amp threads new` takes
exactly one option (`--visibility`). The orchestrator must *read* the id, not *name* it — and
correction 13 says a failed launch gives it nothing to read.

**So the adapter's launch is a two-phase commit, and the first phase is a label, not an id.**

```bash
#!/usr/bin/env bash
# orchestrator/amp/launch.sh  <task-file> <run-id>
set -uo pipefail
RUN_ID="$2"; TASK="$(cat "$1")"
CORR="orch-$RUN_ID"                       # our own correlation id — the ONLY thing we control
OUT="$RUN_DIR/$RUN_ID.jsonl"; ERR="$RUN_DIR/$RUN_ID.err"
CTL="$RUN_DIR/$RUN_ID.ctl"                # the steering fifo (§8)
mkfifo "$CTL"

# phase 1: write the bookkeeping row BEFORE the process exists, keyed on CORR
jq -n --arg id "$RUN_ID" --arg corr "$CORR" --arg cwd "$TASK_CWD" \
  '{run:$id, corr:$corr, cwd:$cwd, thread:null, state:"launching", pid:null}' > "$RUN_DIR/$RUN_ID.json"

# phase 2: launch, holding both pipes
( exec 3<>"$CTL"
  amp --execute "$TASK" \
      --stream-json --stream-json-input --stream-json-thinking \
      --title "$RUN_ID" \
      --label "$CORR" --label "orchestrator" \
      --visibility unlisted \
      --mode high \
      --no-archive-after-execute \
      --plugin-ready-timeout 30 \
      --no-color --no-notifications --no-ide \
      <&3 >"$OUT" 2>"$ERR"
) & CHILD=$!
jq --arg p "$CHILD" '.pid = ($p|tonumber)' "$RUN_DIR/$RUN_ID.json" | sponge "$RUN_DIR/$RUN_ID.json"

# phase 3: harvest the id from the init frame — it is line 1, before any model work
for _ in $(seq 1 120); do
  TID="$(head -1 "$OUT" 2>/dev/null | jq -r 'select(.type=="system" and .subtype=="init") | .session_id' 2>/dev/null)"
  [ -n "${TID:-}" ] && [ "$TID" != "null" ] && break
  kill -0 "$CHILD" 2>/dev/null || break
  sleep 0.5
done

if [ -z "${TID:-}" ] || [ "$TID" = "null" ]; then
  # correction 13: an auth failure produces ZERO stdout lines. Reconcile by label.
  cat "$ERR" >&2
  amp threads list --json --include-archived --limit 50 \
    | jq -r --arg c "$CORR" '.[] | select((.labels // []) | index($c)) | .id'   # shape UNKNOWN
  exit 20
fi
jq --arg t "$TID" '.thread=$t | .state="running"' "$RUN_DIR/$RUN_ID.json" | sponge "$RUN_DIR/$RUN_ID.json"
echo "$TID"
```

### Every flag in that command, verified

| Flag | Verbatim from the binary | Tag |
|---|---|---|
| `-x, --execute [message]` | *"Use execute mode … By default, only the last assistant message is printed. Enabled automatically when redirecting stdout."* | VERIFIED-ran |
| `--stream-json` | *"When used with --execute, output in Claude Code-compatible stream JSON format instead of plain text."* | VERIFIED-ran |
| `--stream-json-thinking` | *"Include thinking blocks in stream JSON output (non-Claude Code extension). Implies --stream-json."* | VERIFIED-ran |
| `--stream-json-input` | *"Read JSON Lines user messages from stdin. Requires both --execute and --stream-json."* | VERIFIED-ran |
| `--title <title>` | *"With --execute, set the title of the new thread before starting the agent."* | VERIFIED-ran |
| `-l, --label <label>` | *"Add a label to the thread created or continued by this command. Repeat the flag for multiple labels."* | VERIFIED-ran |
| `--visibility` | `private, unlisted, workspace, group` | VERIFIED-ran |
| `-m, --mode <value>` | `low, medium, high, ultra, or a plugin mode by key or label` | VERIFIED-ran |
| `--no-archive-after-execute` | *"…leave the thread unarchived after the command finishes."* | VERIFIED-ran |
| `--plugin-ready-timeout [s]` | max **300**, enforced: `--plugin-ready-timeout 999` → `Error: … must be an integer <= 300` | VERIFIED-ran |

The flag-combination rules are enforced and their error text is stable enough to assert on
(all VERIFIED-ran):

```
amp -x hi --stream-json-input     -> Error: The --stream-json-input flag requires --stream-json
amp --stream-json                 -> Error: The --stream-json flag requires --execute mode
amp -ox                           -> Error: User message must be provided through stdin or as argument …
amp -x hi --runner-dir /tmp       -> Error: --runner-dir requires --execute and --executor runner:<id>.
amp --executor zzz -x hi          -> Error: executor must be "local", "orb", or "runner:<id>"
amp --orb-size zzz -x hi          -> …Allowed choices are a1.tiny, a1.small, a1.medium, a1.large, a1.xxlarge, a1.3xlarge.
```

### What comes back on stdout

One JSON object per line. Line 1 is always the init frame (VERIFIED-doc, verbatim from
docs/cli/streaming-json):

```json
{"type":"system","subtype":"init","cwd":"/Users/orb","session_id":"T-f9941a55-3765-421e-972f-05dc1138c3a3","tools":["Bash","finder","create_file","edit_file","glob","Grep","mcp__postgres__query","oracle","Read","read_mcp_resource","read_web_page","Task","todo_read","todo_write","undo_edit","web_search"],"mcp_servers":[{"name":"postgres","status":"connected"}]}
```

with an optional `agent_mode?: string` (correction 18) and `mcp_servers[].status` drawn from
`"awaiting-approval" | "authenticating" | "connecting" | "reconnecting" | "connected" | "denied" |
"failed" | "blocked-by-registry"`. **Assert on that status in the adapter** — a `denied` or
`blocked-by-registry` MCP server at launch is a silent capability loss for the whole run.

The terminal frame is one of exactly three shapes (VERIFIED-doc):

```ts
{ type:"result"; subtype:"success"; duration_ms; duration_api_ms?; is_error:false;
  num_turns; result:string; session_id; usage?; permission_denials?: string[] }
{ type:"result"; subtype:"error_during_execution"|"error_max_turns"; duration_ms; duration_api_ms?;
  is_error:true; num_turns; error:string; session_id; usage?; permission_denials?: string[] }
{ type:"system"; subtype:"error_max_turns"|"error_during_execution"; error:string; session_id }
```

**Success looks like:** a first line with `.type=="system" and .subtype=="init"` inside ~2s, then a
last line with `.type=="result" and .is_error==false`.

**Failure looks like:** the child exits with no stdout at all and one line on stderr (auth, network);
or a `result` frame with `is_error:true` and a free-text `error` (§6 explains why that is a problem).

**Fallback for the missing session id:** shapes O and R print the thread URL on stdout and exit —
`amp -ox "…"` → `https://ampcode.com/threads/T-…` (VERIFIED-doc). If you need an id *before* work
begins and cannot tolerate the parse, launch as an orb, capture the URL, then `amp threads continue
T-… -x "…"`. You pay one round trip and you get an id you can write down first.

---

## 3. Start the same task in a visible terminal the owner can type into

Amp's TUI is not scriptable and there is no `--attach`. There are exactly two honest options.

### 3a. tmux around the TUI — the orchestrator's option

```bash
SESS="amp-$RUN_ID"
tmux new-session -d -s "$SESS" -c "$TASK_CWD" \
  "env AMP_API_KEY=$AMP_API_KEY AMP_SETTINGS_FILE=$AMP_SETTINGS_FILE AMP_SKIP_UPDATE_CHECK=1 \
       amp threads continue $TID"
tmux send-keys -t "$SESS" "keep going, but run the tests first" Enter     # typing, not a protocol
tmux capture-pane -pt "$SESS" -S -2000 > "$RUN_DIR/$RUN_ID.pane"
open -a iTerm; tmux attach -t "$SESS"                                     # owner attaches
```

This is keystroke injection into a TUI. It is exactly the failure mode the owner's field notes
already record — *"a nudge that cannot submit stranded text"* — because whether `Enter` submits
depends on the TUI's current focus, and nothing acknowledges. **Do not use this as the intervention
channel.** Use it only so a human has a window. The real intervention channel is §8.

Relevant TUI bindings, VERIFIED-ran from `amp config keymap` (the authoritative list, 69 entries):

```
"thread.interrupt": "esc esc",              // Interrupt the active agent turn
"prompt.queue": null,                       // Queue the prompt to run after the current turn instead of steering
"prompt.dequeue": null,                     // Dequeue prompts
"prompt.steerQueuedMessage": null,          // Steer with the next queued prompt
"thread.analyzeContext": null,              // Open context usage for this thread on the web
"thread.showCost": null,                    // Show usage cost and entitlement for the active thread
"amp.relaunch": null,                       // Quit, reopen Amp, and resume active threads
"amp.disableRemoteThreadCreation": null,    // Stop accepting new threads from ampcode.com in this Amp
```

Everything useful is **unbound by default** (`null`). To drive them you must first write
`"amp.keymap": {"prompt.steerQueuedMessage":"ctrl+g", …}` into the settings file — which is a lot of
machinery to reinvent `--stream-json-input`.

### 3b. Amp's own answer — remote control, which the orchestrator cannot use

```bash
amp --remote-control-terminal              # expose this CLI's terminal to ampcode.com
amp --no-remote-control-terminal
AMP_REMOTE_CONTROL_TERMINAL=1|0            # env equivalent; an explicit CLI flag wins
amp --no-tui --runner-id mac-mini --remote-control-terminal     # a runner, reachable from a phone
```

(VERIFIED-ran for the flags and env var; VERIFIED-doc for the behaviour.) The owner then opens the
thread on ampcode.com from desktop or phone and types there. **This is the right answer for the
human and the wrong answer for the supervisor**: it can be gated behind workspace-wide *"Require
Passkey Authentication for Web & App Interaction"*, which an unattended process cannot satisfy.

**Recommendation:** run shape L (§2) for work, and give the owner a *view* rather than a terminal —
`https://ampcode.com/threads/<TID>`, which he can open on any device and type into, with
`--visibility unlisted` so the link works. That is strictly better than a tmux pane and costs
nothing.

**Fallback when even that is unavailable:** `tee` the child's stdout into a pretty-printer and put
*that* in a terminal. The owner reads a live view; steering still goes through §8.

---

## 4. Tell whether the session is alive, working, waiting, or finished — from outside

Amp gives four signals. None of them is a file you can tail (correction 4 softens this, but the log
is best-effort, not a state machine). Rank them in this order.

### 4a. The stdout pipe — authoritative, but only for a run you spawned

```bash
# orchestrator/amp/state.sh <run-id>  ->  launching|running|working|finished|failed|dead
S="$RUN_DIR/$1"; P="$(jq -r .pid "$S.json")"
LAST="$(tail -1 "$S.jsonl" 2>/dev/null)"
case "$(jq -r '.type + "/" + (.subtype // "-")' <<<"$LAST" 2>/dev/null)" in
  "result/success")                 echo finished ;;
  "result/error_during_execution"|"result/error_max_turns"|"system/error_"*) echo failed ;;
  "system/init")                    echo running ;;      # id known, no assistant turn yet
  "assistant/-"|"user/-")           echo working ;;
  *) kill -0 "$P" 2>/dev/null && echo launching || echo dead ;;
esac
# liveness of the last write, for a stall detector:
python3 -c "import os,time,sys;print(round(time.time()-os.path.getmtime(sys.argv[1]),1))" "$S.jsonl"
```

A `result` frame is definitive: it is the last line the process writes. `num_turns`, `duration_ms`
and `duration_api_ms` come with it, so the adapter gets its own telemetry for free.

**The gap this leaves:** there is **no `awaiting-approval` signal in the stream**. The complete set of
output types is `system/init`, `system/error_*`, `assistant`, `user`, `result` (VERIFIED-doc). A
session blocked on an `ask` permission looks, from the pipe, exactly like a session that is thinking.
Only the mtime of the JSONL distinguishes them, and only statistically. This is why §9's delegate
helper is not optional — it is the only way to guarantee the run never enters a state the pipe cannot
describe.

### 4b. `amp top --stream-jsonl` — the fleet view, on an unstable schema

```
$ amp top -h
Usage: amp top [options]
Show a live list of active threads across all repositories.
Options:
  --stream-jsonl   Stream a JSON line whenever the thread list changes (output schema is EXPERIMENTAL)
```

VERIFIED-ran, including the word EXPERIMENTAL, which is the binary's own. One long-lived process that
emits a line whenever any thread anywhere changes state — the right shape for a multi-session
supervisor, on a schema the vendor has pre-announced will break. Output shape **UNKNOWN** (requires
auth).

```bash
amp top --stream-jsonl | while IFS= read -r line; do
  printf '%s\n' "$line" >> "$RUN_DIR/top.jsonl"       # record first, parse defensively
done &
```

Wrap every field access in a default. Pin the binary (§1) so the schema at least does not change
mid-run.

### 4c. Polling the server — the durable read, for threads you did not spawn

```bash
amp threads list --json --include-archived --limit 50 [--offset N] [--installation-id <id>]
amp threads search "<query>" --json -n 50 [--offset N]
amp threads export  T-…      # Export a thread as JSON        (creator only — CLAIMED)
amp threads raw     T-…      # Export raw actor thread data as JSON
amp threads markdown T-…     # Render thread as markdown
```

All VERIFIED (completion tree + `amp threads -h`). **None takes a `since` cursor**, so live
monitoring means re-fetching the whole thread and diffing. Output shapes **UNKNOWN**.
`--installation-id` (correction 15) is the one scoping lever: give each orchestrator role its own
`HOME`, and each gets its own `installationID` in `<HOME>/.local/share/amp/device-id.json`, which
makes "list only *my* role's threads" expressible.

### 4d. The External API — for a supervisor that is not this machine

`GET https://ampcode.com/api/v2/threads/{threadID}/messages`, paginated (`limit` default 50,
`cursor`), returning `{nextCursor, messages[]}` where each message has `messageID`, `messageVersion`,
`createdAt` and, per the spec's own note, **unstable everything else**. Scope
`amp.api:workspace.threads.contents:view`, auth `v2.OAuth2AppAuth` client-credentials M2M against
`https://auth.ampcode.com/oauth2/token`, clients created with `amp oauth-clients create`.
VERIFIED-doc from `/api/v2/openapi.json`. This is a **workspace** API — for a single owner on an
Individual plan it is the wrong tool.

### 4e. In-process, from a plugin — the only place a real state enum exists

```ts
amp.threads.get(threadID).state   // Observable<ThreadState> & { get(): Promise<ThreadState> }
```

```ts
/**
 * - `idle`: the agent is not working; the last turn (if any) has finished.
 * - `running`: the agent is working (inference or tool execution in progress).
 * - `awaiting-approval`: the agent is blocked waiting for a tool approval.
 * - `error`: the turn stopped with an error that Amp will not retry on its own. A failed
 *   inference turn with an automatic retry pending is reported as `running`.
 */
export type ThreadState = 'idle' | 'running' | 'awaiting-approval' | 'error'
```

VERIFIED-ran (`amp plugins show-docs`, verbatim). Note the last sentence: **`running` silently
covers a failed turn that Amp is retrying.** A stall detector built on `state` will not see a
provider outage; it will see a thread that is "working" for a long time. Combine with mtime.

`waitForResponse({ timeoutMs })` *"Waits until the thread has been `running` (or
`awaiting-approval`) and returns to `idle`, then resolves with the last assistant message. Rejects if
the thread enters the `error` state or the timeout elapses (default 10 minutes)."* — a ready-made
per-turn watchdog, if you are willing to run a resident plugin.

**Success looks like:** `finished` derived from a `result/success` line, cross-checked against
`ThreadState === 'idle'`.
**Failure looks like:** the pipe goes quiet with no `result` frame — which means the process died
(check `kill -0 $PID`) or the turn is blocked on an approval the pipe cannot show you.
**Fallback:** mtime-based stall detection on the JSONL, plus a hard per-task deadline. With shape L
there is nothing better.

---

## 5. Read how full its context is, then force a compaction or a handoff, then PROVE it happened

### 5a. Read it — from the stream you already own, free

Every `assistant` frame may carry `usage` (VERIFIED-doc schema, verbatim):

```ts
usage?: {
  input_tokens: number;
  cache_creation_input_tokens?: number;
  cache_read_input_tokens?: number;
  cache_creation?: { ephemeral_5m_input_tokens: number; ephemeral_1h_input_tokens: number };
  output_tokens: number;
  max_tokens?: number;
  service_tier?: "standard" | "enterprise";
}
```

```bash
# orchestrator/amp/fullness.sh <run-id>  -> 0.0 .. 1.0, or "" if no usage frame yet
jq -r 'select(.type=="assistant") | .message.usage
       | select(. != null) | select(.max_tokens != null)
       | (((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))
          / .max_tokens)' "$RUN_DIR/$1.jsonl" | tail -1
```

The docs' own worked examples make this concrete (VERIFIED-doc): a three-message steered
conversation shows `cache_read_input_tokens` climbing `0 → 13993 → 14029` against a constant
`"max_tokens":968000`. Summing the three input counters against `max_tokens` is the honest estimate.

**Two caveats the adapter must encode.** `usage` is optional (`usage?:`) — tolerate frames without
it. And `max_tokens` is **not labelled** as the context ceiling anywhere; `968000` is consistent with
a ~1M window but the schema does not say so. Treat the ratio as a *trend*, set your threshold
conservatively (0.70, not 0.90), and never let a decision hinge on the absolute number.

The two other candidate readers are both worse:

- `amp threads context T-…` (alias `analyze-context`) — *"Analyze the current context for a thread"*.
  Takes one argument, **no `--json`** (VERIFIED, completion tree). Its TUI twin is
  `"thread.analyzeContext": null, // Open context usage for this thread on the web` — which strongly
  suggests it prints or opens a URL. Output **UNKNOWN**. Do not build on it untested.
- `GET /api/v2/threads/{id}/usage` returns `inputTokens`/`outputTokens`/`cacheReadInputTokens`/
  `cacheCreationInputTokens` — but these are **cumulative across the thread's life**, so they
  overstate occupancy after any compaction. Unusable for this axis.

### 5b. Trigger it — you cannot

VERIFIED by exhaustion, twice:

- the 189-path command tree, hidden options included, contains **zero** occurrences of `compact`,
  `handoff` or `fork`;
- the 69-entry `amp config keymap` list contains **zero** occurrences of `compact`, `handoff` or
  `fork` (`restore` appears once, as `prompt.history` — "Restore a previous prompt", an input-history
  feature).

There is no `/compact`. There is no external trigger. The archived
`ampcode.com/guides/context-management` describes a **Handoff** feature, under its own banner
*"Archived — This guide was written in November 2025 for an earlier model and context-management
era."*, and even as described it drafted into a prompt editor — interactive only.

The one lever that exists is a **pre-run** dial, settable only from inside a plugin
(VERIFIED-ran, `amp plugins show-docs`, verbatim):

```ts
/**
 * Estimated input-token count at which Amp automatically compacts the thread.
 * Must be a positive safe integer. When omitted, Amp uses the configured
 * percentage threshold, which defaults to 90%.
 */
compactionThresholdTokens?: number      // on CreateAgentConfig
```

There is no settings-file key for it: the complete `amp.*` settings list (28 keys, VERIFIED-ran from
`amp --help`) has no compaction entry.

### 5c. So the adapter owns the handoff. Here is the whole of it

```bash
#!/usr/bin/env bash
# orchestrator/amp/handoff.sh <run-id>   — rolls a thread over when fullness crosses the threshold
set -euo pipefail
RUN="$1"; OLD="$(jq -r .thread "$RUN_DIR/$RUN.json")"; CORR="$(jq -r .corr "$RUN_DIR/$RUN.json")"

# 1. stop the current turn cleanly, then let the process finish
printf '%s\n' '{"type":"user","steer":true,"message":{"role":"user","content":[{"type":"text","text":"Stop after the current tool call. Do not start new work."}]}}' > "$RUN_DIR/$RUN.ctl"
wait_for_result "$RUN"                                        # §4a

# 2. take the transcript off the server (the machine may not have it — §C of the profile)
amp threads markdown "$OLD" > "$RUN_DIR/$RUN.old.md"          # alias: amp threads md
amp threads export   "$OLD" > "$RUN_DIR/$RUN.old.json"        # creator-only (CLAIMED)

# 3. summarise it cheaply, in Amp itself, in a throwaway thread
SUMMARY="$(amp -x "Summarise the attached engineering session for a successor agent: the goal, what
is done, what is in flight, every file touched, every decision and its reason, and the exact next
step. Be specific; no pleasantries." \
  --mode low --label "$CORR" --label handoff-summary \
  --attach "$RUN_DIR/$RUN.old.md")"

# 4. open the successor and record the mapping BEFORE any work starts
NEW="$(printf '%s\n\n---\nCONTINUE FROM HERE:\n%s\n' "$SUMMARY" "$(cat "$RUN_DIR/$RUN.next")" \
       | amp -x --stream-json --title "$RUN (cont)" --label "$CORR" --label "succeeds:$OLD" \
              --no-archive-after-execute \
       | tee "$RUN_DIR/$RUN.b.jsonl" | head -1 | jq -r .session_id)"

jq --arg o "$OLD" --arg n "$NEW" '.thread=$n | .lineage += [$o]' "$RUN_DIR/$RUN.json" | sponge "$RUN_DIR/$RUN.json"
```

Cost, stated plainly: one extra model call per rollover, the loss of Amp's own (model-assisted, and
probably better) compaction summary, the loss of thread continuity in the ampcode.com UI, and a piece
of lineage state the orchestrator now owns forever. There is no cheaper option.

### 5d. Prove a compaction happened

**From the CLI: you cannot.** There is no compaction event in `PluginEventMap` — the complete list is
`session.start`, `agent.start`, `tool.call`, `tool.result`, `agent.end` (VERIFIED-ran) — and no CLI
flag exposes the compacted transcript.

**From a plugin: by diffing two reads.** VERIFIED-ran, verbatim from `amp plugins show-docs`:

> Read messages from the thread in a stable plugin-facing schema. By default this reads the messages
> a new inference turn would see: after a compaction, the latest compaction summary and the messages
> from the compaction cut point onward. Pass `full: true` to read the entire transcript, including
> compacted-away messages. Defaults to `{ from: 'end', limit: 10 }`. The maximum `limit` is 20.
> Combine with `offset` to fetch more messages.

```ts
// .amp/plugins/orch-compaction-witness.ts
export default function (amp: PluginAPI) {
  amp.on('agent.end', async (event) => {
    const t = amp.threads.get(event.thread.id)
    const live = await t.messages({ from: 'start', limit: 20, full: false })
    const all  = await t.messages({ from: 'start', limit: 20, full: true })
    if (live.length && all.length && JSON.stringify(live[0]) !== JSON.stringify(all[0])) {
      amp.logger.log(`COMPACTED thread=${event.thread.id} summary=${JSON.stringify(live[0]).slice(0,4000)}`)
    }
    return undefined
  })
}
```

The compaction summary itself is materialised as a **user message**, so it is readable — but there is
no marker, no timestamp and no event. Compare pi, which writes a typed `CompactionEntry` into its
session file. The `limit` cap of **20** is the binding constraint: witnessing a long thread means
paging.

**For the adapter's own handoff (5c), proof is trivial and local**: the lineage array in
`$RUN.json`, plus two files on disk, plus a new `T-…` that did not exist before. Prefer proving your
own rollover to detecting Amp's.

**Verdict on axis D: fails the owner's non-negotiable.** Reading fullness is clean. Triggering is
impossible. Proof is available only to resident plugin code, only by diffing, and only 20 messages at
a time.

---

## 6. Read remaining quota and the reset time; detect a limit hit in-band

### The shape is wrong, not just the API

Amp does not meter time windows. It meters **money**. There is no `five_hour.utilization`, no
`seven_day.utilization` and **no `resets_at`, because there is no window**. The failure mode is not
"wait four hours"; it is "the balance hit zero and stays zero until someone pays". The owner's
pause-until-reset-then-auto-resume loop has nothing to attach to.

Terms, VERIFIED-doc from docs/pricing: Hobby free (pay-as-you-go orbs, own runners free,
*"No Amp token fees/limits"*); Individual **$20/mo** including *"45,000 minutes of orbin' time"*,
*"No Amp token fees or limits."*; Teams at no extra charge with *"Shared billing and pooled
credits"*; Enterprise custom with *"Pooled credits only"* and *"Spend limits and reporting"*.
*"Purchased credits expire twelve months after purchase."* Orbs are billed by the minute and Amp
*"pauses an orb 5 minutes after the agent stops working or 20 minutes after you last interacted with
it, whichever comes later. A paused orb costs nothing."* BYOK on every tier.

### 6a. The supported reader — text only

```
$ amp usage -h
Usage: amp usage [options]
Show your current Amp usage and credit balance
Options:
  --details            Show detailed credit, token, and thread usage
  --start <timestamp>  Start of the usage range as an ISO 8601 timestamp
  --end <timestamp>    End of the usage range as an ISO 8601 timestamp
```

That is the complete option list (VERIFIED-ran, and confirmed against the completion tree: `usage`
has exactly `--details`, `--start`, `--end`). **There is no `--json`**, while siblings like
`threads list` and `permissions list` have one. The omission is specific.
`amp threads usage T-…` has the same three options for one thread.

### 6b. The unsupported reader — structured, and the CLI's own (correction 11)

```bash
# orchestrator/amp/balance.sh  — UNSUPPORTED, UNVERSIONED. Wrap in try/except. Have a fallback.
curl -sS -X POST "${AMP_URL}api/internal?userDisplayBalanceInfo" \
  -H "Authorization: Bearer $AMP_API_KEY" \
  -H 'Content-Type: application/json' \
  -H 'X-Amp-Client-Application: CLI' -H 'X-Amp-Client-Type: cli' \
  -H "X-Amp-Installation-ID: $(jq -r .installationID "$HOME/.local/share/amp/device-id.json")" \
  -d '{"method":"userDisplayBalanceInfo","params":{"markdown":false,"details":true}}'
```

The endpoint, the method name, the header set and the `params` shape are all **VERIFIED-ran** — they
were captured off the wire from the real binary by pointing `AMP_URL` at a local listener. The
`markdown:false` variant is inferred from the parameter's existence (`amp usage` sends `true`,
the `details` flag is presumed to flip `params.details`, though that body could **not** be captured —
`amp usage --details` aborts before this call against a fake server); the **response body is UNKNOWN**
because it needs a real token. This is the single highest-value thing to check on the first
authenticated session: if `markdown:false` returns numbers, axis E goes from "scrape and pray" to
"poll a number", and the whole quota story changes.

**Adapter policy regardless:** call `amp usage --details` as the supported path, cache the raw text,
and treat the internal endpoint as an optimisation that may vanish at any release (and this binary
releases roughly every three hours).

### 6c. The External API — spend, not remaining, and workspace-scoped

| Endpoint | Returns | Scope |
|---|---|---|
| `GET /workspace/analytics/daily-usage` | `metadata{startDate,endDate,activeUsers,totalUsers,totalUsage}` (USD) + per-day per-user rows; params `endDate`, `lookbackDays` (1–365, default 1), `userID` | `amp.api:workspace.analytics:view` |
| `GET /threads/{threadID}/usage` | `usage` (USD), `estimatedProviderCostAtListPriceUSD`, per-model `requests`/`inputTokens`/`outputTokens`/`cacheReadInputTokens`/`cacheCreationInputTokens`; *"Data only available for threads less than 90 days old"* | `amp.api:workspace.threads.meta:view` |
| `GET /workspace/entitlements` | `[{id,name,type:"paid_credits",usageLimitUSD,windowDays,assignment}]` | `amp.api:workspace.entitlements:view` |

All VERIFIED-doc from `/api/v2/openapi.json`. **Every one reports spend so far; none reports
remaining.** `entitlements.windowDays ∈ {1,7,30}` paired with `usageLimitUSD` is the only rolling
window in the platform — and it is a workspace-admin object needing M2M OAuth, irrelevant to a single
owner on Individual.

### 6d. Detecting a limit hit in band

There is **no quota-specific signal**. The stream has exactly two error subtypes,
`error_during_execution` and `error_max_turns`, and the only structured failure list anywhere in the
schema is `permission_denials?: string[]`, which is about permissions, not money. So:

```bash
# the honest version: a fragile string match, declared as fragile
classify_failure() {                       # stdin = the result frame
  local err; err="$(jq -r '.error // empty')"
  case "$err" in
    *credit*|*balance*|*quota*|*insufficient*|*payment*|*billing*) echo quota ;;
    *rate*limit*|*429*)                                            echo ratelimit ;;
    '')                                                            echo unknown ;;
    *)                                                             echo error ;;
  esac
}
```

**And then do not retry.** A quota classification on Amp means **escalate to a human and stop the
queue** — there is no reset time to sleep until. The adapter's Amp branch must expose a
`quota_exhausted` terminal state that the Claude Code branch does not have.

**Success looks like:** `amp usage` exits 0 and its text contains a balance the operator recognises.
**Failure looks like:** a `result` frame with `is_error:true` and a free-text `error` that your
regex may or may not classify correctly.
**Fallback:** a hard spend ceiling the orchestrator enforces itself — sum
`usage.output_tokens`/`input_tokens` across every `result` frame in the run, convert at a rate you
configure, and stop the queue at your own number rather than the vendor's. It is the only ceiling you
can actually observe in real time.

**Verdict on axis E: fails the owner's non-negotiable, structurally.** Best achievable today:
scrape text before each task, try the internal endpoint, string-match on failure, escalate, never
auto-resume.

---

## 7. Switch a new session to a different account, and verify the switch before work starts

**This is Amp's best axis, and it is one environment variable.**

```
AMP_API_KEY   Access token for Amp (see https://ampcode.com/settings/security#access-token)
AMP_URL       URL for the Amp service (default is https://ampcode.com/)
AMP_SETTINGS_FILE / --settings-file <path>
AMP_LOG_FILE  / --log-file <path>
AMP_LOG_LEVEL / --log-level <value>
AMP_REMOTE_CONTROL_TERMINAL   Enable (1) or disable (0) terminal access from ampcode.com …
```

(The complete environment-variable section of `amp --help`, VERIFIED-ran.) No profile directories, no
`CLAUDE_CONFIG_DIR`-style indirection, no keychain derivation, no per-folder binding file.

```bash
# orchestrator/amp/account.sh <role>   — everything a role needs, in one env block
ROLE_DIR="$ORCH_HOME/accounts/$1"
export AMP_API_KEY="$(cat "$ROLE_DIR/token")"      # sgamp_…
export AMP_URL="$(cat "$ROLE_DIR/url" 2>/dev/null || echo https://ampcode.com/)"
export AMP_SETTINGS_FILE="$ROLE_DIR/settings.json"
export AMP_LOG_FILE="$RUN_DIR/$1.log"; export AMP_LOG_LEVEL=info
export HOME="$ROLE_DIR/home"                       # separate device-id.json / installationID
```

### Verify the switch before work starts — three independent proofs

```bash
# 1. the key is accepted at all (exit 0 = yes)                       VERIFIED-ran (failure path)
amp threads list --json --limit 1 >/dev/null

# 2. our settings file, not the built-ins, is in force                VERIFIED-ran
amp permissions test Bash --json | jq -e '.source=="user"'

# 3. the installation identity is this role's, not another's          VERIFIED-ran
jq -r .installationID "$HOME/.local/share/amp/device-id.json"          # e.g. <installation-id>

# 4. (best-effort) the log says what the process actually saw          VERIFIED-ran
jq -c 'select(.message=="Initializing CLI context")
       | {hasAmpAPIKey, hasAmpURL, hasSettingsFile}' "$AMP_LOG_FILE"
jq -c 'select(.message=="Server status resolved")
       | {status, isAuthenticated, errorMessage}'     "$AMP_LOG_FILE"
jq -c 'select(.message=="Using settings file")
       | {settingsPath, workspaceSettingsPath}'       "$AMP_LOG_FILE"
```

Proof 4 is the strongest and the least reliable — correction 5: the log sink is asynchronous and
frequently loses everything on a fast-exiting command. Use proofs 1–3 as the gate and 4 as forensics.

### The trap that will kill an overnight queue

Verbatim from docs/cli/execute-mode, *"Non-Interactive Environments"* (VERIFIED-doc):

> Use an access token from Settings, which starts with `sgamp_`. **The CLI rejects the short-lived
> session token that `amp login` stores, because it expires within an hour and cannot be refreshed
> from an environment variable.**

A queue started from an interactively logged-in shell has **under an hour** before its credential is
worthless. `AMP_API_KEY` with an `sgamp_` token is the only supported unattended path — and it is
also the only path that avoids the macOS keychain. The binary links Security.framework
(`_SecKeychainFindGenericPassword`, `_SecKeychainAddGenericPassword`, `_SecKeychainItemDelete`,
`_SecKeychainItemModifyAttributesAndData` all present) and carries the string *"Keychain access
denied. In CI environments, use {allowUnrestrictedAccess: true} option."* With a redirected `HOME`
the CLI announces its choice in the log (VERIFIED-ran):

```json
{"message":"using file-based secrets storage","dataDir":"…/home/.local/share/amp"}
```

— so a per-role `HOME` sidesteps the keychain entirely, which is a second independent reason to set
it.

### Can a running session's account be changed?

**No.** Nothing in the 189-path tree does this and nothing in the plugin API does either. The
workaround is to end the turn, then continue the thread from a new process under a different key:

```bash
env AMP_API_KEY="$OTHER" amp threads continue T-… -x "carry on"
```

**This works only if the other account can see that thread** — it owns it, or the thread's visibility
is `workspace` (both accounts in that workspace) or `unlisted`. Visibility is settable at launch
(`--visibility private|unlisted|workspace|group`), per repository origin
(`"amp.defaultVisibility": {"github.com/org/repo": "workspace"}`), after the fact
(`amp threads share T-… --visibility unlisted`), and from a plugin
(`thread.setVisibility('private'|'workspace')`, *"The authenticated user must own the thread."*).

**Decide the visibility policy at launch, before you need it.** A `private` thread is a dead end for
every other account, permanently. The adapter should default to `unlisted` for anything it might hand
off, and `private` only for work that must never be handed off.

### One orthogonal trap: BYOK keys are global, not per-session

`amp config model-providers activate` *"deactivates any other active key of the same provider"*. It
is a **machine-global** switch, so two concurrent sessions cannot use two different keys for the same
provider through it. Relevant because `amp config model-providers add-chatgpt-subscription` exists —
*"Link your ChatGPT subscription to Amp as a model provider by signing in to OpenAI in your
browser"* — which is the owner's stated interest in ChatGPT reachable through Amp, but only one
ChatGPT subscription at a time, machine-wide.

**Success looks like:** proofs 1–3 all pass before the task prompt is sent.
**Failure looks like:** exit 1 with `Invalid or missing API key…`; or, far worse, an **unset**
`AMP_API_KEY` and a device-code prompt that blocks forever (correction 12).
**Fallback:** none needed — this axis passes cleanly. It is the least work of any platform in the
scan.

---

## 8. Deliver an instruction into a running session and confirm it arrived

This is the axis the owner's field notes complain about most — *"a nudge that cannot submit stranded
text"*. Amp answers it with a documented flag and a worked example.

### The channel

`--stream-json-input` requires `--execute` **and** `--stream-json` (VERIFIED-ran, the CLI enforces
both). Amp then reads JSON Lines from stdin and, verbatim from docs/cli/streaming-json,
*"exits only after the assistant is done and stdin has closed. This allows a program to send several
user messages during one conversation."*

Input schema, verbatim (VERIFIED-doc):

```ts
type StreamJSONInputMessage = {
  type: "user";
  steer?: boolean;
  message: {
    role: "user";
    content: Array<
      | { type: "text"; text: string }
      | { type: "image"; source_path?: string;
          source: { type: "base64";
                    media_type: "image/jpeg"|"image/png"|"image/gif"|"image/webp";
                    data: string } }
    >;
  };
};
```

And the decisive sentence, verbatim:

> Set the top-level `steer` field to `true` if Amp should handle a queued message at the next
> interruption point while the agent is busy.

**That is the missing primitive**: inject an instruction into a session that is mid-turn, taken at
the next safe point. No TTY, no screen scraping, no keystroke simulation.

### The implementation

```bash
# orchestrator/amp/nudge.sh <run-id> <text> [--steer]
set -euo pipefail
RUN="$1"; TEXT="$2"; STEER="${3:-}"
MARK="[nudge:$(uuidgen)]"                      # correlation id WE add, because the protocol has none
BEFORE="$(wc -l < "$RUN_DIR/$RUN.jsonl")"

jq -cn --arg t "$MARK $TEXT" --argjson s "$([ "$STEER" = "--steer" ] && echo true || echo false)" \
  '{type:"user", steer:$s, message:{role:"user", content:[{type:"text", text:$t}]}}' \
  > "$RUN_DIR/$RUN.ctl"                        # the fifo the launcher opened on fd 3

# confirm arrival: Amp ECHOES every accepted user message back on stdout
for _ in $(seq 1 60); do
  if tail -n "+$BEFORE" "$RUN_DIR/$RUN.jsonl" \
     | jq -e --arg m "$MARK" 'select(.type=="user")
         | .message.content[]? | select(.type=="text") | select(.text | contains($m))' >/dev/null 2>&1
  then echo delivered; exit 0; fi
  sleep 1
done
echo not-acknowledged >&2; exit 1
```

The echo is real and documented. The docs' own three-message example interleaves all three echoes
with the assistant replies (VERIFIED-doc):

```json
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"now add 8 to that"}]},"parent_tool_use_id":null,"session_id":"T-addfb7a4-61d9-41e1-890b-7330aa54087a"}
```

and the docs ship a supervisor sketch verbatim:

```bash
send_message() {
  local text="$1"
  echo '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"'$text'"}]}}'
}
{ send_message "what's 2+2?"; sleep 10
  send_message "now add 8 to that"; sleep 10
  send_message "now add 5 to that"; } | amp --execute --stream-json --stream-json-input
```

### What the receipt does and does not give you

**It is an echo, not an acknowledgement.** The input schema has no request-id field and the output
has no correlated response; matching is by content and ordering. That is weaker than pi's
`--mode rpc`, where a command carries an optional `id` and gets a correlated `{type:"response"}`.
**Mitigation: prefix every nudge with a UUID marker**, as above. Two identical nudges then stay
distinguishable, which the bare protocol cannot promise.

**Image nudges have no receipt at all.** Verbatim: *"User image blocks are accepted as input but
omitted from streamed user messages on stdout so the output remains compatible with Claude Code."*
(VERIFIED-doc.) If the orchestrator ever sends an image, it must confirm by some other means.

### From a plugin — reach a thread you did not spawn

```ts
amp.threads.get(threadID).appendUserMessage({ type:'user-message', content: text }, { steer: true })
amp.threads.get(threadID).append([ …UserMessage ])
amp.threads.get(threadID).cancel()        // "Stop the agent's current turn. During agent.start, prevents the turn from starting."
```

VERIFIED-ran, verbatim from `amp plugins show-docs`, including
*"When `steer` is true and the thread is busy, the message is queued as a steering message and is
preferred when the thread next dequeues work."* `amp.threads.get(threadID)` is **not limited to the
current thread** — one resident plugin can steer every sibling session, which makes an in-process
orchestrator possible. (`parentThreadID()` is the one method scoped to the current thread only.)

**Success looks like:** the marker text appears in a `{"type":"user",…}` echo line on stdout.
**Failure looks like:** 60 seconds with no echo. Causes: the child already wrote its `result` frame
and closed stdin; the fifo was never opened on fd 3; or `--stream-json-input` was omitted and the
launch silently ran as a single-shot.
**Fallback:** `amp threads continue T-… -x "<text>"` from a *new* process. This starts a new turn
rather than steering the current one, and requires the current turn to be finished — but it always
works, needs no held pipe, and survives the orchestrator restarting.

---

## 9. Answer a permission prompt or a clarifying question without a human

### There is no question event. There is something better.

The complete list of stream output types is `system/init`, `system/error_*`, `assistant`, `user`,
`result` (VERIFIED-doc). There is **no** `question` or `permission_request` event. What Amp offers
instead is an **external program that arbitrates every tool call, synchronously, out of process**.

The contract, verbatim from `ampcode.com/notes/permissions` (VERIFIED-doc):

> And then you'll write a tiny program called `amp-permissions-helper` and put it on your `$PATH`.
> The program receives the tool parameters on stdin as JSON, and makes a decision with its exit
> code: **0 allows the tool call, 1 makes Amp ask, and 2 rejects the tool call, forwarding stderr to
> the model.**

The tool name arrives in the environment as `AGENT_TOOL_NAME` (VERIFIED-doc — it is used in the
docs' own Open Policy Agent example, which builds `{input:{toolName,args}}` and maps
`allow/ask/reject` onto 0/1/2).

### Install it — with the flag order that actually works (correction 3)

```bash
amp permissions add delegate --to orch-perm-helper '*'
#              ^action  ^--to BEFORE the tool pattern   ^tool glob
```

VERIFIED-ran end to end: the rule is prepended to `amp.permissions` in the file named by
`--settings-file`, existing rules are preserved, the file is created at mode `0600` if absent, and
the result is re-serialised as 2-space JSON:

```json
{ "amp.updates.mode": "disabled",
  "amp.permissions": [
    { "tool": "*", "action": "delegate", "to": "orch-perm-helper" },
    { "tool": "Bash", "matches": { "cmd": "*rm -rf*" }, "action": "reject" },
    …
  ] }
```

*"Add a permission rule to the beginning of the list. Rules are evaluated in order, so newer rules
take precedence."* — `amp permissions add -h` … which prints the root help (correction 1); that text
came from the profile's earlier capture and from `/news/tool-level-permissions`.
`--context thread|subagent` is supported and lands as `"context": "subagent"` (VERIFIED-ran).

### The helper

```bash
#!/usr/bin/env bash
# orch-perm-helper  — on $PATH.  stdin = the tool's input object.  env AGENT_TOOL_NAME = the tool.
# exit 0 allow | 1 ask | 2 reject (stderr goes to the model)
set -uo pipefail
INPUT="$(cat)"
TOOL="${AGENT_TOOL_NAME:-unknown}"

# 1. record every decision point — this is the orchestrator's audit log AND its liveness signal
jq -cn --arg t "$TOOL" --arg r "${ORCH_RUN_ID:-?}" --argjson i "${INPUT:-null}" \
   --arg ts "$(date -u +%FT%TZ)" '{ts:$ts, run:$r, tool:$t, input:$i}' >> "$ORCH_DECISIONS"

# 2. ask the orchestrator, with a deadline — NEVER block forever unattended
DECISION="$(timeout 20 curl -sS --unix-socket "$ORCH_SOCK" \
             -H 'Content-Type: application/json' \
             --data-binary "$(jq -cn --arg t "$TOOL" --argjson i "$INPUT" '{tool:$t,input:$i}')" \
             http://orch/decide 2>/dev/null | jq -r '.action // empty')"

case "$DECISION" in
  allow)  exit 0 ;;
  reject) echo "orchestrator policy: ${TOOL} is not permitted for this task" >&2; exit 2 ;;
  ask)    echo "orchestrator requires human review of ${TOOL}" >&2; exit 2 ;;   # unattended: ask == reject
  *)      echo "orchestrator unreachable; denying ${TOOL} by default" >&2; exit 2 ;;
esac
```

**Never return 1 unattended.** `1` means "make Amp ask", and what an `ask` does in `-x` mode with no
TTY is **UNKNOWN** — the stream has no approval channel, `ThreadState` includes `awaiting-approval`
as a real state, and the built-in defaults `ask` on `git push`. It may auto-deny; it may hang. Until
one authenticated test settles it, the adapter must ensure `ask` is never reachable: delegate
everything, and let the helper choose only 0 or 2.

### Preflight the policy without running anything

```bash
$ amp --settings-file S permissions test mcp__x__y --json
{ "tool":"mcp__x__y", "arguments":{}, "action":"reject",
  "matchedEntry":{"tool":"mcp__*","action":"reject"}, "matchIndex":6, "source":"user" }
$ amp --settings-file S permissions test mcp__x__y -q ; echo $?     # 2
```

**Exit-code mapping, VERIFIED-ran by construction** (a settings file with one rule of each kind):

| `action` | `permissions test -q` exit |
|---|---|
| `allow` | **0** |
| `ask` | **1** |
| `reject` | **2** |
| unknown tool (`"action": null`) | **0** |

Three sharp edges, all VERIFIED-ran:
1. **An unknown tool name exits 0** with `"action": null` — indistinguishable from `allow` by exit
   code alone. Always parse `--json` and check `action != null`.
2. **`arguments` is always `{}`** (correction 2) — you cannot preflight a command string.
3. **`matchIndex` is not an index into `permissions list --json`.** With four user rules, the
   third matched at `matchIndex: 6` and the fourth at `7`. Use `matchedEntry` + `source`
   (`"user"` | `"built-in"`), never the index.

### What the defaults do if you skip all of this

`amp permissions list --builtin --json` runs offline with no auth and returns **187 rules**
(VERIFIED-ran). The dangerous ones, exact:

```json
{ "tool": "load_plugin",       "action": "ask" }
{ "tool": "reload_plugins",    "action": "ask" }
{ "tool": "Bash",              "action": "ask",   "matches": { "cmd": "*git*push*" } }
{ "tool": "mcp__*",            "action": "allow" }
{ "tool": "read_mcp_resource", "action": "allow" }
… 180 more, ending with a bare  { "tool": "Bash", "action": "ask" }
```

The tail is a long `allow` list of first-party integrations — `slack_write`, `slack_read`,
`gmail_read`, `gmail_write`, `google_drive_read`, `google_docs_write`, `google_sheets_write`,
`x_reply`, `create_github_subscription` and more — all **allowed by default** (VERIFIED-ran, read
from the dump). Combined with `{"tool":"mcp__*","action":"allow"}`, an out-of-the-box unattended Amp
will send Slack messages, write Google Docs and post to X without asking, plus every tool of every
connected MCP server. `amp permissions test Bash --json` on a default install returns
`{"action":"ask","source":"built-in","matchIndex":27}` — i.e. **bare `Bash` asks**, which in a
no-TTY run is the exact state whose behaviour is unknown.

Note also the docs/binary contradiction the profile records: `ampcode.com/docs/tools#permissions`
says, in full, *"Permissions — Amp does not ask for approval before running tools. Use a custom
plugin to control tool use."*, while the shipping binary carries a complete `permissions` subsystem
with `ask` rules in its defaults. **Test the real behaviour before trusting a run unattended.**

### The richer surface, from a plugin

```ts
amp.on('tool.call',  h)  // -> { action:'allow' } | { action:'reject-and-continue', message }
                         //    { action:'modify', input } | { action:'synthesize', result:{output, exitCode?} }
amp.on('tool.result',h)  // observe or replace the result
amp.on('agent.start',h)  // -> { message:{ content, display? } } — inject context, alter the system prompt
amp.on('agent.end',  h)  // -> { action:'continue', userMessage, maxContinuations? }
```

VERIFIED-ran. `agent.end → {action:'continue'}` is a sanctioned autonomous loop driver with a
built-in circuit breaker: *"How many plugin `continue` turns may run in a row after the last
user-sent message … Defaults to 5. Any message the user sends resets the count. Raise it
deliberately, for example in a plugin that drives long-running work toward a goal, and keep your own
stop condition."*

**Success looks like:** every tool call appears in `$ORCH_DECISIONS` with a decision, and
`result.permission_denials` at the end matches what the helper rejected.
**Failure looks like:** the helper is not on `$PATH` (behaviour when a delegate target is missing is
**UNKNOWN** — test it), or it returns 1 and the run blocks.
**Fallback:** `"amp.dangerouslyAllowAll": true` — *"Disable all command confirmation prompts (agent
will execute all commands without asking)"*. This removes the hang risk and removes the
orchestrator's veto with it. Prefer the helper. Use `amp.tools.enable` as the second line of defence
regardless, since it is a hard allow-list rather than a policy.

---

## 10. Resume the task after a crash, and after the whole machine rebooted

**Amp's state is not on your disk, so there is nothing to recover — only an id to remember.**

### After a crash (the process died, the machine did not)

```bash
# the id is already in our bookkeeping row from §2 phase 3
TID="$(jq -r .thread "$RUN_DIR/$RUN_ID.json")"

# re-attach and continue, headless, with the pipes rebuilt
amp threads continue "$TID" \
    --execute "Resume. Re-read your last few messages, state what you were doing, then continue." \
    --stream-json --stream-json-input \
    --label "$CORR" --no-archive-after-execute \
    < "$RUN_DIR/$RUN_ID.ctl" >> "$RUN_DIR/$RUN_ID.jsonl" 2>> "$RUN_DIR/$RUN_ID.err"
```

Forms, all VERIFIED (completion tree + `amp threads continue -h` + docs):

```
amp threads continue T-…                      # attach the CLI (interactive)
amp threads continue T-… -x "next instruction" # headless resume
amp threads continue T-… -ox 'message'         # send without attaching; runs on the thread's own remote executor
amp threads continue T-… T-… T-…               # multiple: all resumed, first shown in foreground (correction 16)
amp threads continue --last                    # last thread in this checkout for the current mode, preferring this terminal
amp last     (alias: amp l)                    # continue the last thread
```

**If the id was never captured** (correction 13: an auth failure emits zero stdout lines), reconcile
by the label you set at launch:

```bash
amp threads list --json --include-archived --limit 100 \
  | jq -r --arg c "$CORR" '.[] | select((.labels // []) | index($c)) | .id'
amp threads search "$RUN_ID" --json -n 50        # the --title also carries the run id
```

Both are VERIFIED to exist; their **output shapes are UNKNOWN** (auth required), so the adapter must
tolerate either an array or an object with an items key, and must not assume a `labels` field name.
**This is a recovery path, not a guarantee** — which is the price of not being able to name the
session in advance.

**Does a killed local turn resume mid-turn, or start a new one?** **UNKNOWN.** The profile flags it;
nothing in the docs or the binary answers it. Design for the pessimistic case: the resume prompt above
deliberately asks the agent to restate what it was doing, so that a fresh turn re-establishes context
instead of assuming it.

### After a reboot

```bash
#!/usr/bin/env bash
# orchestrator/amp/resume-all.sh   — run from a LaunchAgent at login
for f in "$RUN_DIR"/*.json; do
  state=$(jq -r .state "$f"); tid=$(jq -r .thread "$f"); cwd=$(jq -r .cwd "$f"); run=$(jq -r .run "$f")
  [ "$state" = "running" ] || continue
  [ "$tid" != "null" ] || { echo "orphan: $run" >&2; continue; }
  ( cd "$cwd" && source "$ORCH_HOME/amp/account.sh" "$(jq -r .role "$f")" \
    && exec "$ORCH_HOME/amp/launch-continue.sh" "$run" "$tid" ) &
done
```

Nothing else is needed. Thread state lives server-side; the same `T-…` opens identically from the
CLI, `https://ampcode.com/threads/T-…`, the macOS/iOS apps and Slack (VERIFIED-doc, docs/threads).
The TUI even has a command for it — `"amp.relaunch": null, // Quit, reopen Amp, and resume active
threads` (VERIFIED-ran, `amp config keymap`), unbound by default.

**Shapes O and R do not need this at all.** An orb or runner thread kept working through the reboot;
the local process was only streaming. That is the strongest argument for shape R as the default
executor for anything long.

### What actually breaks resume

| Event | Outcome | Tag |
|---|---|---|
| CLI killed | everything in the thread survives; `threads continue` picks it up | VERIFIED-doc |
| Machine reboot | same | VERIFIED-doc |
| Laptop sleeps, shape O/R | the agent **keeps working** remotely | VERIFIED-doc |
| Laptop sleeps, shape L | the turn dies with the process; mid-turn recoverability UNKNOWN | UNKNOWN |
| Provider outage | a failed inference turn with a retry pending reports as `running`; retry depth and policy UNKNOWN | partly VERIFIED-ran |
| **ampcode.com unreachable** | **fatal for everything, including reading your own transcript.** `Error: Cannot reach Amp servers. Are you offline?` | VERIFIED-ran |
| Thread archived by `-x` | still readable, URL still works, found by `--include-archived`; invisible to a bare `threads list` | VERIFIED-doc |
| Binary auto-updated mid-queue | `amp.updates.mode` defaults to `"auto"`; runners self-restart (`amp.runner.autoUpdate.enabled: true`) | VERIFIED-ran (defaults) |

**One thread = one working directory.** Verbatim from docs/sdk: *"Each thread has one working
directory, so use separate `execute()` calls for different directories. Continuing a thread keeps its
existing directory. The `cwd` option only sets the local CLI subprocess directory."* A queue that
moves between repos needs **a thread per repo**, not a thread per task. The adapter's bookkeeping row
must therefore key on `(cwd, thread)`, and a task that changes directory is a new thread, not a
continuation.

**Success looks like:** `threads continue` emits a fresh `system/init` line with the *same*
`session_id` and the run proceeds.
**Failure looks like:** `Cannot reach Amp servers. Are you offline?` — and with Amp there is no
offline degradation, so the correct response is to pause the whole queue, not to retry the task.
**Fallback:** none is needed for state. The fallback that *is* needed is for identity: always set
`--title "$RUN_ID"` and `--label "$CORR"`, so that a lost id is findable.

---

## 11. Stop it cleanly, leaving nothing running

```bash
#!/usr/bin/env bash
# orchestrator/amp/stop.sh <run-id> [--hard]
set -uo pipefail
RUN="$1"; S="$RUN_DIR/$RUN"; TID="$(jq -r .thread "$S.json")"; PID="$(jq -r .pid "$S.json")"

# 1. ask the agent to stop, at the next safe point            (VERIFIED-doc: steer)
printf '%s\n' '{"type":"user","steer":true,"message":{"role":"user","content":[{"type":"text","text":"Stop now. Do not start any new tool call. Summarise what you completed and what remains."}]}}' > "$S.ctl"

# 2. close stdin — this is what makes --stream-json-input exit
#    "exits only after the assistant is done and stdin has closed"   (VERIFIED-doc)
exec 3>&-   2>/dev/null || true
: > "$S.ctl.closed"

# 3. wait for the result frame, bounded
for _ in $(seq 1 180); do
  tail -1 "$S.jsonl" 2>/dev/null | jq -e '.type=="result"' >/dev/null 2>&1 && break
  sleep 1
done

# 4. escalate only if it did not land
if kill -0 "$PID" 2>/dev/null; then
  kill -TERM "$PID"; sleep 5
  kill -0 "$PID" 2>/dev/null && { [ "${2:-}" = "--hard" ] && kill -KILL "$PID"; }
fi

# 5. leave the server side tidy
amp threads archive "$TID"                      # reversible: amp threads archive "$TID" --unarchive
# amp threads delete "$TID"                     # irreversible — only on explicit operator request

# 6. local cleanup
rm -f "$S.ctl"
jq '.state="stopped"' "$S.json" | sponge "$S.json"
```

### What "nothing running" actually has to cover

| Thing | How to be sure | Tag |
|---|---|---|
| The CLI child | `kill -0 $PID`; then TERM, then KILL | standard |
| Its plugin runtime | a **separate process** driven over stdio RPC; it logs `Received SIGINT, exiting` — it dies with the parent, but check for strays named `plugin-runtime.ts` | VERIFIED-ran |
| The fifo | `rm -f "$S.ctl"` — a leaked fifo silently blocks the next launcher | — |
| A `--no-tui` runner | `amp runner list`, then stop the process you started; `amp runner dirs list` shows what it serves | VERIFIED (tree) |
| An orb | it is **not** stopped by killing your CLI. Amp *"pauses an orb 5 minutes after the agent stops working or 20 minutes after you last interacted with it, whichever comes later. A paused orb costs nothing."* | VERIFIED-doc |
| Orb services | `amp orb service stop <name>` / `status` / `list` — declared in `.amp/services.yaml`, *"supervised processes that survive Amp CLI updates and restart on failure"* | VERIFIED-ran |
| Remote-control exposure | `amp --no-remote-control-terminal`, or `AMP_REMOTE_CONTROL_TERMINAL=0` | VERIFIED-ran |
| Remote thread creation | `"amp.remoteThreadCreation.enabled": false` (the shipped default), or the TUI's `amp.disableRemoteThreadCreation` | VERIFIED-ran |
| The thread itself | `amp threads archive T-…` (reversible) or `amp threads delete T-…` (not) | VERIFIED (tree) |

**Read the orb row twice.** Killing the local process does **not** stop an orb; it only stops you
watching it. Billing continues until Amp's own pause timer fires. A stop routine that only kills
PIDs will leak money on shape O.

**Success looks like:** a `result` frame in the JSONL, no live PID, no fifo, and the thread archived.
**Failure looks like:** the process ignores TERM because it is mid-inference. `--hard` exists for
that; the thread survives regardless, so a KILL costs nothing but the current turn.
**Fallback for a thread you cannot reach from a pipe:** from a plugin, `amp.threads.get(id).cancel()`
— *"Stop the agent's current turn. During agent.start, prevents the turn from starting."* There is no
CLI equivalent, which means **a shell-only orchestrator cannot cancel a turn it does not have a pipe
to.** For shapes O and R, the only stop is a `-ox` message asking it to stop, or the web UI.

---

## The adapter interface this platform needs

```ts
// orchestrator/platforms/amp.ts   — the shape the eleven recipes actually require
export const amp: PlatformAdapter = {
  id: 'amp',
  binary: 'amp',

  // ---- native: one command or one env var, nothing invented ------------------
  preflight,            // amp --version | amp threads list --json --limit 1 | permissions test --json
  launchHeadless,       // amp -x … --stream-json --stream-json-input   (holds BOTH pipes)
  launchRemote,         // amp -ox … | amp -x … --executor runner:<id>  (prints a URL, exits)
  resume,               // amp threads continue T-… -x …
  stop,                 // steer -> close stdin -> TERM -> KILL -> threads archive
  readContextFullness,  // usage.* / usage.max_tokens off the assistant frames
  switchAccount,        // AMP_API_KEY + AMP_URL + AMP_SETTINGS_FILE + HOME, per process
  sendInstruction,      // one JSON line to stdin, steer:true, echo-confirmed
  arbitratePermission,  // permissions add delegate --to <helper> '*'; exit 0/1/2
  pinVersion,           // amp update --target-version <v> --porcelain

  // ---- emulated: the orchestrator owns state the platform does not keep ------
  sessionId,            // READ from stream line 1; reconcile orphans by --label
  liveness,             // stream frames + mtime + amp top --stream-jsonl (EXPERIMENTAL schema)
  transcript,           // own the pipe; poll `amp threads export|markdown` for gaps
  compact,              // NOT triggerable: markdown -> summarise -> new thread -> lineage map
  quota,                // scrape `amp usage --details`; optionally POST api/internal?userDisplayBalanceInfo
  detectLimitHit,       // regex over result.error — no structured signal exists

  // ---- impossible: do not build these, design around them --------------------
  assignSessionId:      null,   // no --session-id / --thread-id anywhere in 189 command paths
  triggerCompaction:    null,   // zero `compact|handoff|fork` in the command tree or the 69-entry keymap
  quotaResetTime:       null,   // no rolling window exists; the model is money, not time
  switchAccountInPlace: null,   // no CLI or plugin path changes a running session's account
  cancelTurnFromShell:  null,   // thread.cancel() is plugin-only; shell has only the pipe
  answerAskFromShell:   null,   // no approval channel in the stream; ask-with-no-TTY is UNKNOWN
}
```

### Which of the eleven are native, emulated, or impossible

| # | Recipe | Verdict | The one sentence that decides it |
|---|---|---|---|
| 1 | Preflight | **native** | `amp --version`, `threads list --json --limit 1`, `permissions test --json` (`source:"user"`) — but never with an unset key. |
| 2 | Headless + pinned id | **native launch, emulated id** | `-x --stream-json --stream-json-input` is first-class; the id can only be *read*, from line 1, and a failed launch emits nothing. |
| 3 | Visible terminal | **emulated, badly** | Only the TUI (unscriptable) or ampcode.com (passkey-gateable). Give the owner the thread URL, not a pane. |
| 4 | Liveness | **emulated** | Four partial signals; `awaiting-approval` exists in the plugin API but **not** in the stream. |
| 5 | Context read / compact / prove | **read native · trigger impossible · proof plugin-only** | `usage.max_tokens`; zero compaction commands; proof only by diffing `messages({full})` 20 at a time. |
| 6 | Quota + reset + in-band | **emulated · reset impossible** | `amp usage` has no `--json`; there is no window, so no reset; failures are free text. |
| 7 | Account switch + verify | **native — best in scan** | `AMP_API_KEY` per process, plus `AMP_URL`, `AMP_SETTINGS_FILE`, `HOME`. Three independent proofs. |
| 8 | Deliver an instruction | **native** | `--stream-json-input` with `steer:true`, echoed back on stdout. Add your own UUID marker. |
| 9 | Answer without a human | **native, and better than asked for** | `delegate --to <helper>` gives a synchronous veto on *every* tool call, exit 0/1/2, stderr to the model. |
| 10 | Resume after crash / reboot | **native** | State is server-side. `amp threads continue T-…`. Nothing to checkpoint. |
| 11 | Stop cleanly | **native locally · leaky remotely** | Close stdin, TERM, archive. An orb keeps billing until Amp's own pause timer. |

### What Amp saves the adapter, and what it makes it build

**Saves four things outright.** Account switching is one env var — delete the profile-directory,
keychain and config-dir machinery the Claude Code adapter needs. Resume is free and total — remember
a `T-…` string and nothing else. Steering is a documented flag with an echo receipt, not a keystroke
hack. Permission arbitration is an out-of-process contract with a 20-line shell implementation.

**Makes it build five.** A quota story that is not a quota story, with no auto-resume and a human
escalation the other adapters do not need. A complete handoff implementation, because compaction
cannot be triggered from outside. A transcript reader with no file to tail — the pipe, plus an
EXPERIMENTAL fleet stream, plus a polling differ. Id bookkeeping *after* the fact, with an orphan
reconciliation path. And a version pin as a first-class preflight step, because the binary ships
roughly every three hours and updates itself by default.

---

## Support tier

### **Tier 2 — workable with emulation. It clears eight of eleven and fails two of the owner's four non-negotiables.**

Scored against the owner's own axes:

| Axis | Verdict |
|---|---|
| A · Launch | **strong** — headless first-class, structured output first-class, plus remote launch that nothing else in the scan has |
| B · Identity & resume | **good, one real gap** — exact and durable resume; cannot name the session in advance |
| C · Transcript | **workable but inverted** — nothing to tail; three mechanisms replace one file |
| D · Context *(non-negotiable)* | **FAIL** — reading is clean, triggering is impossible, proof is plugin-only |
| E · Quota *(non-negotiable)* | **FAIL, structurally** — no window, no reset, no `--json`, no in-band signal |
| F · Accounts *(non-negotiable)* | **PASS — best in scan** — one env var per process |
| G · Intervention *(non-negotiable)* | **PASS, twice** — `steer` with a receipt, and a synchronous veto on every tool call |
| H · Guardrails | **capable, defaults unsafe** — `mcp__*` allowed, Slack/Gmail/Drive/Docs/X allowed, `ask` behaviour with no TTY unknown |
| I · Extensibility | **strong** — MCP, skills, plugins, custom agents, per-role model *and* reasoning-effort pinning |
| J · Operational reality | **runnable overnight, with a specific preflight** — the auto-update default is the biggest hazard in the scan |

**Not tier 1** because axis D has no external trigger at all and axis E has no window to wait for.
Those are not gaps an adapter can paper over; they change what the orchestrator can promise. On Amp,
"pause until the quota resets, then auto-resume" is not implementable, and "compact before the
context fills" becomes "roll the thread over yourself and keep a lineage map".

**Not tier 3** because everything an executor-only platform lacks, Amp has and has well: a real
steering channel with a receipt, a synchronous permission veto, exact resume across reboots, and the
cleanest account isolation in the whole scan. A supervisor can genuinely supervise an Amp session —
it just cannot manage its context or its money.

**The strategic caveat, stated once.** Amp is the only platform in this scan whose architecture
assumes the supervisor is *not* on the same machine as the agent — orbs, runners addressed by stable
name, cross-client access, thread ids as the only handle, server-side transcripts. An orchestrator
that adopted Amp's shape rather than bending Amp into a tail-a-file shape would get remote execution,
crash immunity and multi-machine fan-out for free, and would permanently give up externally-triggered
compaction and any notion of a quota window. That is the trade, and it is not small in either
direction.

**Minimum viable overnight configuration** (every element VERIFIED-ran or VERIFIED-doc above):

```bash
export AMP_API_KEY=sgamp_...                       # long-lived. NEVER `amp login`.
export AMP_URL=https://ampcode.com/
export AMP_SETTINGS_FILE=/path/to/role/settings.json
export AMP_LOG_FILE=/path/to/run/amp-cli.log AMP_LOG_LEVEL=info
export AMP_SKIP_UPDATE_CHECK=1
export HOME=/path/to/role/home

# settings.json: updates disabled, runner auto-update off, Claude Code skills off,
#                tools.enable allow-list, permissions -> delegate to orch-perm-helper
amp permissions add delegate --to orch-perm-helper '*'      # note the flag order

amp -x "<task>" --stream-json --stream-json-input --stream-json-thinking \
    --title "<run-id>" -l "<corr-id>" -l orchestrator \
    --visibility unlisted --mode high \
    --no-archive-after-execute --plugin-ready-timeout 30 \
    --no-color --no-notifications --no-ide
```

with the orchestrator holding stdin (steering), parsing stdout (`session_id`, `usage`, the terminal
`result`), and `orch-perm-helper` adjudicating every tool call and never returning 1.

---

## Still open after this pass — and what each one is worth

Nine questions, all needing **one authenticated session on a throwaway account**. Ranked by what they
change.

| # | Question | Axis | If the answer is good |
|---|---|---|---|
| 1 | Does `POST api/internal?userDisplayBalanceInfo` with `markdown:false` return structured numbers? | E | Axis E goes from "scrape and pray" to "poll a number". The single highest-value test. |
| 2 | What does an `ask` permission do in `-x` mode with **no TTY** — auto-deny, or hang? | H, J | Decides whether an unattended run can survive any `ask` at all, and whether the helper may ever return 1. |
| 3 | What does `--observe <T-…>` do? | A, C, G | If it streams an existing thread, the adapter gets a transcript reader for sessions it did **not** spawn — the one hole in §4. |
| 4 | What does `--headless [T-…]` do? | A, C | Same family. `--daemon` is dead (correction 7); these two are what replaced it. |
| 5 | What does `amp threads context T-…` print — numbers or a URL? | D | If numbers, §5a gets a second, independent fullness reader that works for threads you do not pipe. |
| 6 | What is `amp top --stream-jsonl`'s actual output schema? | C | It is the only fleet-wide liveness signal, and it is pre-announced as unstable. |
| 7 | Does a locally-executing turn resume **mid-turn** after the CLI is killed, or start a new turn? | B | The difference between "resume exactly" and "resume approximately". |
| 8 | What happens when a `delegate` target is missing from `$PATH`? | H | Determines whether a mis-deployed helper fails open or fails closed. |
| 9 | What is in the built-in guarded-files denylist (`amp.guardedFiles.allowlist` "takes precedence over the built-in denylist")? | H | Unknown denylist means unknown blast radius. |

Three questions the profile listed are now **closed**: `--daemon` (dead, correction 7),
`amp plugins exec` semantics (path not name, runs offline, no thread API — correction 20), and
whether Amp reads Claude Code's context (it reads the **skills**, 107 of them, by ancestor-directory
walk, and `HOME` redirection does not stop it — correction 9; whether it reads `CLAUDE.md` itself
remains UNKNOWN, as `AGENTS.md` is the named convention).

---

## Appendix — what was run, and what it proves

All executed **2026-09-19** against `@ampcode/cli 0.0.1789819237-ge34793`, sandboxed `HOME`, no
login, no credits spent.

**Offline, no key at all — these are the commands an adapter can rely on without a network:**

| Command | Result | Proves |
|---|---|---|
| `amp --version` | `0.0.1789819237-ge34793 (released 2026-09-19T12:00:37.000Z, 1h ago)` | version pinning is observable |
| `amp --help` | 472 lines: commands, options, 6 env vars, examples, 28-key settings reference, example config | the defaults in §0 |
| `amp completions zsh` | 82,976 bytes; embedded JSON tree, **189 command paths**, hidden options included | the only honest flag surface (correction 1) |
| `amp config keymap` | 69 TUI commands; **zero** `compact`/`handoff`/`fork` | §5b's impossibility, by exhaustion |
| `amp permissions list --builtin --json` | **187 rules**, incl. `{"tool":"mcp__*","action":"allow"}` and a long first-party `allow` list | §9's "defaults are not safe" |
| `amp permissions test <tool> [--json] [-q] [-c ctx]` | `{tool,arguments,action,matchedEntry,matchIndex,source}`; exits 0/1/2 for allow/ask/reject | §9's preflight, and corrections 2 and 3 |
| `amp permissions add <action> [--to p] <tool>` | rewrites the settings file, prepends, preserves, creates at 0600 | §9's install step |
| `amp plugins show-docs` | 2,074-line typed Plugin API | every plugin quote in this document |
| `amp plugins exec <path> <event> --data <json>` | runs the plugin, fires the handler, `[plugin] [name] …` on stdout | correction 20 |
| `amp update -h` | `--target-version <version>`, `--porcelain` | correction 14 |
| `amp --daemon` | `Error: amp --daemon has been replaced. Use amp --no-tui instead.` | correction 7 |
| `amp --observe=zzz` / `--headless=zzz` | `Error: Invalid thread URL or ID: zzz` | correction 8 |
| `amp --output-format=zzz` / `--format=zzz` / `--orb-size=zzz` / `--executor=zzz` | choice enumerations in the error text | correction 8, §2 |
| `amp -x hi --stream-json-input` etc. | five distinct flag-combination errors | §2's validation table |

**With a deliberately invalid key (`sgamp_fake_000`) — the failure shapes:**

| Command | Result | Proves |
|---|---|---|
| `amp threads list --json` | `Error: Invalid or missing API key. Run 'amp login' to authenticate.` — **stderr**, stdout empty, **exit 1** | §1's classifier |
| `amp -x "say hi" --stream-json` | **zero stdout lines**, one stderr line, exit 1 | correction 13 |
| `amp --log-level debug --log-file X …` | 20,317 bytes of JSONL: version, argv, exec mode, settings paths, secrets dir, auth state, 107 skills | corrections 4 and 9 |
| same command, two later attempts | **0 bytes** | correction 5 (async sink) |
| `AMP_URL=http://127.0.0.1:59999/ amp threads list` | `Error: Cannot reach Amp servers. Are you offline?` | §7, §10 |

**With no key and no network (`AMP_API_KEY` unset):**

| Command | Result | Proves |
|---|---|---|
| `amp tools list --json` | device-code URL printed, then *"Waiting for confirmation in the browser..."* — **blocks** | correction 12, the single worst unattended trap |

**Against a local HTTP listener via `AMP_URL` — the wire, captured:**

```
POST /api/internal?getUserInfo                {"method":"getUserInfo","params":{}}
POST /api/internal?listThreads                (path only; the CLI aborts on the 401 before sending a body we captured)
POST /api/internal?loadPlugins                {"method":"loadPlugins","params":{"supportedPluginFormats":["directory-v1","directory-v2"],"knownVersions":{}}}
POST /api/internal?userDisplayBalanceInfo     {"method":"userDisplayBalanceInfo","params":{"markdown":true,"details":false}}

Authorization: Bearer sgamp_…
X-Amp-Client-Application: CLI      X-Amp-Client-Type: cli
X-Amp-Device-Fingerprint: v1:fp_<64 hex>       (per machine)
X-Amp-Installation-ID: <uuid>                  (per HOME, from .local/share/amp/device-id.json)
```

Proves correction 11 and §6b.

**Files the sandbox created, and only these:**

```
<HOME>/.config/amp/plugins/orch-probe.ts     # written by me, not by amp
<HOME>/.local/share/amp/device-id.json       # {"installationID":"<installation-id>"}
<HOME>/.cache/amp/logs/cli.log
<HOME>/.cache/amp/logs/headless.log
<HOME>/.cache/amp/logs/plugin-runtime.log
```

Nothing under the owner's `$HOME` was written. Amp did **read** 107 skill files from
`~/.claude/skills/`, `~/.claude/skills/synced/` and `~/.agents/skills/` on every run whose cwd was
inside the owner's home — see correction 9, and the two files that fail to parse.
