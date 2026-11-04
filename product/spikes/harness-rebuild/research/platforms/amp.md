# Amp (Sourcegraph) — platform profile for a provider-agnostic orchestrator

**Profiled:** 2026-09-19. **Machine:** owner's Mac (darwin 25.5.0, arm64).
**Version under test:** `@ampcode/cli` **`0.0.1789819237-ge34793`**, which the binary itself reports as
*"released 2026-09-19T12:00:37.000Z"* — i.e. roughly one hour old at the time of profiling.

**Evidence tags** (same scheme as `00-field-scan.md`):
- **VERIFIED** — read in official docs, read in package/registry metadata, or run on this machine.
- **CLAIMED** — asserted by a README, vendor page or blog post, not independently confirmed.
- **UNKNOWN** — could not be established in this pass.

---

## 0. Method, and what "run on this machine" means here

**Amp is not installed on the owner's machine.** VERIFIED: `which amp` → not found; there is no
`~/.amp`, no `~/.config/amp`, no `~/Library/Application Support/amp`, no `~/.cache/amp`; nothing
matching `amp` in the npm global list, in `/opt/homebrew/bin` (only `myisampack`, unrelated), in
`~/.local/bin`, in `~/.bun/bin`, or in `~/.vscode/extensions`. This matches the field scan's
"not installed" row.

To get flag names from the binary rather than from prose, I unpacked the published tarballs into the
session scratchpad and ran the executable with a **redirected HOME**:

```
$SCRATCH/amp-sandbox/pkg/ampcode-cli-darwin-arm64-0.0.1789819237-ge34793/package/amp
HOME=$SCRATCH/amp-sandbox/home  XDG_CONFIG_HOME=$SCRATCH/amp-sandbox/home/.config  AMP_SKIP_UPDATE_CHECK=1
```

Nothing under the owner's `$HOME` was created, read or modified. No login was performed. No thread
was started, so **no owner credits were spent**. The only files the sandbox run produced were
`<sandbox>/.config/amp/`, `<sandbox>/.cache/amp/logs/cli.log` and
`<sandbox>/.local/share/amp/device-id.json` — which is itself a useful finding (§C).

**The single most productive probe** was not `--help`. It was:

```
amp completions zsh
```

Amp's zsh completion script embeds its **entire command/option tree as one JSON blob**, including
options marked `"hidden": true` that `--help` never prints. Parsing that blob yielded 361 command
paths and the complete flag surface. Everything in this document tagged VERIFIED-from-binary comes
from that tree, from `-h` output, or from `amp permissions list --builtin --json` /
`amp config keymap` / `amp plugins show-docs`, all of which run without authentication.

**A trap worth recording before anything else:** `amp <subcommand> --help` **silently prints the
root help** instead of the subcommand's. `amp <subcommand> -h` prints the right thing. VERIFIED —
`amp threads new --help`, `amp permissions --help`, `amp usage --help` and `amp threads context -h`
all dumped the top-level command list, while `amp usage -h` and `amp permissions add -h` printed
correct per-command usage. Anyone probing this CLI from a script will silently get the wrong page.

### Packaging

| Fact | Value | Tag |
|---|---|---|
| Current package | **`@ampcode/cli`** | VERIFIED (npm) |
| Old package | `@sourcegraph/amp` — now a 3-file shim whose description reads *"Renamed to @ampcode/cli - see https://ampcode.com/news/npm-package-changes"* | VERIFIED (npm) |
| Version | `0.0.1789819237-ge34793`, published **2026-09-19T12:12:52Z** | VERIFIED (npm `time`) |
| Total published versions | **4,266** | VERIFIED (npm `time`) |
| Release cadence | 5 releases between 2026-09-18T21:04Z and 2026-09-19T12:12Z — **one roughly every 3 hours** | VERIFIED (npm `time`) |
| Shape | `bin: {"amp": "bin/amp.exe"}` + optional platform packages `@ampcode/cli-{darwin,linux,win32}-{x64,arm64}` | VERIFIED |
| Real binary | a single native executable named `amp`, **~73 MB unpacked** for darwin-arm64. No Node runtime needed. | VERIFIED (unpacked and executed) |
| Licence | `SEE LICENSE IN LICENSE.md` — proprietary. SDK is "Amp Commercial License". | VERIFIED (npm) |
| Install (documented) | `curl -fsSL https://ampcode.com/install.sh \| bash` | VERIFIED (docs/cli) |
| Platform support | *"The CLI supports macOS, Linux, and Windows through WSL."* | VERIFIED (docs/cli) |

**Consequence for this research:** Amp is closed source. The binary is compiled and yields no
readable internal strings for its own logic (I extracted 102,132 strings; the CLI's own help text
and hidden-flag descriptions are not among them — only JSC/Bun runtime strings and vendored Rust
paths are). So anything not visible in `--help`, in the completion tree, in `show-docs`, or in the
public docs is genuinely unknowable without an authenticated run. Where that is the case below, the
tag is UNKNOWN rather than a guess.

---

## A. LAUNCH

### Headless — yes, and it is the primary documented path

| Flag | Exact meaning (quoted from the binary's own help unless noted) | Tag |
|---|---|---|
| `-x, --execute [message]` | *"Use execute mode, optionally with user message. In execute mode, agent will execute provided prompt (either as argument, or via stdin). By default, only the last assistant message is printed. Enabled automatically when redirecting stdout."* | VERIFIED |
| `--stream-json` | *"When used with --execute, output in Claude Code-compatible stream JSON format instead of plain text."* | VERIFIED |
| `--stream-json-thinking` | *"Include thinking blocks in stream JSON output (non-Claude Code extension). Implies --stream-json."* | VERIFIED |
| `--stream-json-input` | *"Read JSON Lines user messages from stdin. Requires both --execute and --stream-json."* | VERIFIED |
| `--title <title>` | *"With --execute, set the title of the new thread before starting the agent."* | VERIFIED |
| `-l, --label <label>` | repeatable; labels the thread created or continued | VERIFIED |
| `--visibility <visibility>` | `private, unlisted, workspace, group` | VERIFIED |
| `-m, --mode <value>` | *"(low, medium, high, ultra, or a plugin mode by key or label, case-insensitive) — controls the model, system prompt, and tool selection"* | VERIFIED |
| `--features <value>` / `--fast` | `fast` = "Faster serving for supported models, billed at a premium"; `pro` = "GPT-5.6 Pro mode (OpenAI API only, not supported by ChatGPT subscriptions)" | VERIFIED |
| `--mcp-config <value>` | *"JSON configuration or file path for MCP servers to merge with existing settings"* | VERIFIED |
| `--plugin-ready-timeout [seconds]` | waits for plugins so `agent.start`/`agent.end` hooks are not skipped. Bare flag = 10s, **max 300**, `0` disables. Off unless set. | VERIFIED |
| `--no-archive-after-execute` | leaves the thread unarchived after the command finishes | VERIFIED |
| `--settings-file <path>` | overrides `~/.config/amp/settings.json` for this process | VERIFIED |
| `--no-color`, `--no-notifications`, `--no-ide` | quiet a non-TTY run | VERIFIED |

Three input forms are documented and all work with `-x` (VERIFIED, docs/cli/execute-mode):

```
$ amp -x "what files in this folder are markdown files?"
$ echo "what package manager is used here?" | amp -x
$ cat ~/.vimrc | amp -x "which colorscheme is used?"
$ amp < prompt.txt > output.txt          # redirecting stdout implies -x
```

Note the behavioural default: *"Interactive CLI threads remember whether the last thread used Fast
mode. Execute mode and other noninteractive thread creation default to Standard mode each time."*
(VERIFIED). An orchestrator therefore gets a deterministic mode without pinning one — good.

### Remote launch — Amp's distinctive axis-A capability

Amp can start a thread somewhere that is **not the orchestrator's process**, and the launching
command exits immediately:

| Flag | Behaviour | Tag |
|---|---|---|
| `-ox, --orb-execute` | *"When used with -x/--execute, execute in an async orb on the Amp server. The -ox shorthand enables both options. With `threads continue`, sends the message to the existing thread so it runs on that thread's own remote executor."* Prints `https://ampcode.com/threads/T-…` and exits **while the agent keeps working**. | VERIFIED |
| `--executor <local\|orb\|runner:<id>>` | *"Run a new thread locally, in an orb, or on a runner"* | VERIFIED |
| `--runner-dir <abs path>` | with `--execute --executor runner:<id>`, picks one absolute directory the runner serves | VERIFIED |
| `--orb-size <size>` | `a1.tiny, a1.small, a1.medium, a1.large, a1.xxlarge, a1.3xlarge` | VERIFIED (completion tree enumerates the choices) |
| `--project [project]` | pins the orb thread to an Amp project instead of inferring from git remotes | VERIFIED |
| `--attach <path>` | repeatable; uploads a local file and adds its URL to the message | VERIFIED |

And the inverse — turning a machine into a thread server:

```
amp --no-tui                                          # serve remote thread creation for this dir
amp --no-tui --runner-id grandmas-garage-server       # stable, hostname-shaped, case-insensitive id
amp --no-tui --runner-id mac-mini --dir ~/code/amp --dir ~/code/sandcastle
amp --no-tui --runner-id x --discover-dirs            # git checkouts up to two levels deep
amp runner list | amp runner dirs add|remove|list [--runner-id <id>]
```

(VERIFIED — `--no-tui` and `amp runner …` from the binary; `--dir`, `--discover-dirs`,
`--discover-depth <1-10>`, `--discover-exclude <pattern>` are **hidden** in `--help` but present in
the completion tree and documented on docs/cli/runners.)

**This is the one thing Amp has that nothing else in the scan so far has:** a supported way for the
orchestrator to hand a task to *a different machine it owns*, addressed by a stable name, with the
launch command returning instantly. For a queue that must survive the orchestrator's own laptop
going to sleep, that is architecturally significant.

### Visible terminal the owner can attach to and type into

Only the TUI (`amp` with no `-x`), which is not scriptable. Amp's answer to "let the human reach
into a running session" is the opposite direction from a terminal multiplexer:

```
amp --remote-control-terminal        # expose this CLI's terminal to ampcode.com
amp --no-remote-control-terminal     # explicitly disable
AMP_REMOTE_CONTROL_TERMINAL=1|0      # env equivalent; an explicit CLI flag wins
```

(VERIFIED, docs/cli/remote-control.) The owner then opens the thread on ampcode.com from desktop or
phone and types there. This is a *human* attach path, not an orchestrator one — and it can be gated
behind "Require Passkey Authentication for Web & App Interaction", which an unattended supervisor
cannot satisfy.

### Structured output

Yes — `--stream-json`, and it is deliberately **Claude-Code-compatible**. Full schema in §C/§G.
Also `amp top --stream-jsonl` for a live fleet view (§C), and `--json` on a long list of read
commands: `threads list --json`, `threads search --json`, `tools list --json`, `tools show --json`,
`permissions list --json`, `permissions test --json`, `skill list --json`, `skill info --json`,
`plugins repositories --json`, `plugins show-agent-options --json`, `mcp list --json`,
`mcp remote list --json`, `net status --json`, `orb service ensure --json`,
`config model-providers list --json`. (All VERIFIED from the completion tree.)

### Hidden flags

Present in the completion tree with `"hidden": true`, absent from `--help`, **semantics UNKNOWN**
(no help text exists for them anywhere I could reach, and the completion engine suppresses their
values too):

`--headless[=v]`, `--daemon`, `--observe=<v>`, `--stats`, `--output-format=<v>`,
`--output-tool=<v>`, `--interactive` / `--no-interactive`, `--model=<v>`, `--share`,
`--dangerously-allow-all`, `--format=<v>`, `--jetbrains` / `--no-jetbrains`,
`--hide-welcome` / `--show-welcome`, `--runner-id=<v>`, `--orb-provider=<v>`,
`--dir=<v>`, `--discover-dirs[=v]`, `--discover-depth=<v>`, `--discover-exclude=<v>`.

Three of these are tantalising for an orchestrator — `--observe`, `--daemon`, `--headless` — and I
will not guess what they do. `--runner-id`, `--dir` and the `--discover-*` family are hidden but
**documented** on docs/cli/runners, so those are safe to use. The rest are not.

### SDK — a first-class programmatic entry point

| Fact | Value | Tag |
|---|---|---|
| TypeScript | npm **`@ampcode/sdk`** `0.1.0-20260918210405-g81edbf0`, published 2026-09-18T21:08Z, deps `zod` + `@ampcode/cli@latest`, `node >= 18` | VERIFIED (npm) |
| Python | PyPI **`amp-sdk`** `0.1.20260918210324`, uploaded 2026-09-18T21:04Z | VERIFIED (PyPI JSON) |
| Shape | `for await (const message of execute({ prompt, options, signal }))` — an async generator over the same stream-json message types | VERIFIED (docs/sdk) |
| Options seen in docs | `cwd`, `continue: true \| 'T-…'`, `mode`, `effort` (`none\|minimal\|low\|medium\|high\|xhigh\|max`), `labels`, `title`, `visibility`, `executor: 'orb'\|'runner'`, `runnerId`, `runnerDir`, `mcpConfig`, `settingsFile`, `skills`, `logLevel`, `logFile` | VERIFIED (docs/sdk) |
| Multi-turn | `execute({ prompt: asyncGenerator })` with `createUserMessage(...)` | VERIFIED |
| Cancellation | pass an `AbortSignal` | VERIFIED |
| Note | *"Remote executors need an `AMP_API_KEY`."* and the SDK drives the CLI as a subprocess ("Amp CLI must be at least the version pinned by the installed SDK release") | VERIFIED |

The SDK is a thin, honest wrapper over the CLI, not a separate protocol. An orchestrator written in
TypeScript or Python gets typed access to exactly what §G describes; one written in bash gets the
same thing over pipes. **Verdict on A: strong.** Headless is first-class, structured output is
first-class, and remote launch is a genuine differentiator.

---

## B. IDENTITY & RESUME

### The id

A session id in Amp is a **thread id**, shaped `T-<uuid>`. The plugin API types it exactly:
`export type ThreadID = \`T-${string}\`` (VERIFIED, `amp plugins show-docs`). Threads are addressed
identically across CLI, web (`https://ampcode.com/threads/T-…`), the macOS/iOS apps and Slack
(VERIFIED, docs/threads).

### Can the orchestrator *assign* the id before the session exists?

**No.** VERIFIED by exhaustion: there is no `--thread-id`, `--session-id`, `--id` or equivalent
anywhere in the 361-entry command tree, hidden options included. `amp threads new` takes exactly one
option, `--visibility`. This is the axis where pi (`--session-id <id>`, "creating it if missing")
beats Amp outright, and it matters: the orchestrator must *read* an id out of a launched process
rather than *name* it, which means the launch and the bookkeeping cannot be made atomic.

### Reading the id back — two clean paths, both VERIFIED

**1. `--stream-json`, first line.** Every message in the stream carries `session_id`, and the very
first is the init frame (quoted verbatim from docs/cli/streaming-json):

```json
{"type":"system","subtype":"init","cwd":"/Users/orb","session_id":"T-f9941a55-3765-421e-972f-05dc1138c3a3","tools":["Bash","finder","create_file","edit_file","glob","Grep","mcp__postgres__query","oracle","Read","read_mcp_resource","read_web_page","Task","todo_read","todo_write","undo_edit","web_search"],"mcp_servers":[{"name":"postgres","status":"connected"}]}
```

So the id is available after one line of output, before any model work — which is as close to
"assign it up front" as Amp gets. The init frame also hands the orchestrator the **effective tool
list** and **MCP server health** for free, which is a genuinely good preflight signal.

**2. Remote launch prints the URL.** `amp -ox "…"` and `amp -x "…" --executor runner:<id>` each
print `https://ampcode.com/threads/T-…` on stdout and exit (VERIFIED, docs/cli/execute-mode).

### Resume

```
amp threads continue T-…                        # attach the CLI to an existing thread
amp threads continue T-… -x "next instruction"  # headless resume
amp threads continue --execute "…" --stream-json
amp threads continue T-… -ox 'message'          # send without attaching; runs on the thread's own remote executor
amp threads continue --last                     # most recent
amp threads continue --pick                     # interactive picker
amp last            (alias: amp l)              # continue the last thread
```

(All VERIFIED — subcommand and flags from the binary's completion tree; the `-x` and `-ox` forms
quoted from docs/cli/streaming-json and docs/threads.)

### What survives a crash, a reboot, a provider outage

| Event | What survives | Tag |
|---|---|---|
| CLI process killed | **Everything in the thread.** Thread state is stored server-side on ampcode.com, not on disk. `amp threads continue T-…` from a fresh process picks it up. | VERIFIED (docs/threads: threads stored server-side; same thread opens on web, CLI, iOS/macOS, Slack) |
| Machine reboot | Same. Also `amp.relaunch` exists as a TUI command: *"Quit, reopen Amp, and resume active threads"*. | VERIFIED (`amp config keymap`) |
| Orchestrator laptop sleeps mid-run, `-ox` or `--executor runner:` used | The agent **keeps working** remotely; the local process was only streaming. | VERIFIED (docs/cli/execute-mode, docs/sdk) |
| Orchestrator laptop sleeps mid-run, local executor | The turn dies with the process. Whether the *partial* turn is recoverable — i.e. whether `threads continue` resumes mid-turn or starts a new turn — is **UNKNOWN**. | UNKNOWN |
| Provider outage | UNKNOWN. `amp.network.timeout` (seconds) is the only related setting. A failed inference turn *with an automatic retry pending* is reported as `running` by the plugin thread-state API, so Amp does retry internally — depth and policy UNKNOWN. | Partly VERIFIED (plugin API comment on `ThreadState`) |
| ampcode.com unreachable | Fatal for everything, including *reading your own transcript*. There is no offline mode. | VERIFIED by construction |

### Constraints the orchestrator must model

- **One thread = one working directory.** *"Each thread has one working directory, so use separate
  `execute()` calls for different directories. Continuing a thread keeps its existing directory.
  The `cwd` option only sets the local CLI subprocess directory."* (VERIFIED, docs/sdk.) A queue
  that moves between repos needs a thread per repo, not a thread per task.
- **Archiving is the default after execute.** `--no-archive-after-execute` exists precisely because
  `-x` archives the thread when it finishes (VERIFIED from the flag's own help). Archived threads
  stay readable and their URLs keep working (VERIFIED, docs/threads), and `threads list
  --include-archived` finds them, but a naive `amp threads list` will not show a finished run.

**Verdict on B: good, with one real gap.** Resume-by-id is exact, durable and survives everything
short of the vendor being down — because the state was never on your disk to begin with. The gap is
that the orchestrator cannot name the session in advance and must parse an id out of the first line
of output, so a launch that dies before emitting that line leaves an orphan thread the orchestrator
never learns the id of. Mitigation: `--title` and `-l/--label` are settable at launch, and
`amp threads list --json` / `amp threads search --json` can find the orphan afterwards by label.
That is a recovery path, not a guarantee.

---

## C. TRANSCRIPT

### There is no local transcript file. At all.

VERIFIED, two ways. First, the sandboxed run created exactly three things under the redirected HOME:

```
<HOME>/.config/amp/                      # settings dir (empty until first write)
<HOME>/.cache/amp/logs/cli.log           # CLI diagnostic log, not a transcript
<HOME>/.local/share/amp/device-id.json   # device identity
```

Second, the docs are explicit that threads live server-side and are reached by URL. The CLI's own
defaults confirm the paths (quoted from `amp --help`, with the sandbox HOME substituted back):

- settings: `~/.config/amp/settings.json` (or `.jsonc`), overridable with `--settings-file` / `AMP_SETTINGS_FILE`
- logs: `~/.cache/amp/logs/cli.log`, overridable with `--log-file` / `AMP_LOG_FILE`
- log verbosity: `--log-level` / `AMP_LOG_LEVEL`

**This inverts the supervisor design.** Every other platform in this scan writes JSONL to disk and a
watcher tails it. Amp gives a supervisor four different things instead, none of which is a file:

### 1. The live stream — only for a run you spawned

`--stream-json` emits one JSON object per line on the child's stdout. The orchestrator must hold the
pipe. If it loses the pipe, it loses the live view; it does not lose the data (see 3).

### 2. `amp top --stream-jsonl` — the fleet view

```
amp top                  # "Show a live list of active threads across all repositories."
amp top --stream-jsonl   # "Stream a JSON line whenever the thread list changes (output schema is EXPERIMENTAL)"
```

VERIFIED from `amp top -h`, including the word EXPERIMENTAL, which is the binary's own. This is the
closest thing Amp has to a liveness watchdog: one long-lived process that emits a line whenever any
thread anywhere changes state. For an orchestrator running several sessions this is exactly the
right shape — and the schema is explicitly unstable, so anything built on it will break. Output
shape **UNKNOWN** (requires authentication to observe).

### 3. Polling the server — the durable read

```
amp threads export T-…      # "Export a thread as JSON"  (creator only)
amp threads raw T-…         # "Export raw actor thread data as JSON"  (alias: raw-thread)
amp threads markdown T-…    # "Render thread as markdown"  (alias: md)
amp threads list --json [--include-archived] [--limit N] [--offset N]
amp threads search <q> --json [-n/--limit N] [--offset N]
```

(All VERIFIED from the binary. `export` being creator-only is CLAIMED from docs/threads.) None of
these takes a "since" cursor, so live monitoring means re-fetching the whole thread and diffing.
Output shapes **UNKNOWN** — all require authentication.

### 4. The External API

`GET https://ampcode.com/api/v2/threads/{threadID}/messages`, paginated (`limit` default 50,
`cursor`), returning `{nextCursor, messages[]}` where each message has `messageID`, `messageVersion`,
`createdAt` — and the spec itself says **the other fields are unstable**. Scope required:
`amp.api:workspace.threads.contents:view`. VERIFIED from `/api/v2/openapi.json` (fetched today,
187 KB, `info.title` = "Amp External API v2"). Note this is a *workspace* API on M2M OAuth — see §E
for why that is a heavier lift than it sounds.

### 5. In-process, from a plugin — the richest path

```ts
amp.threads.get(threadID)          // a handle for ANY thread by id, not just the current one
  .messages({ from: 'start'|'end', offset, limit /* clamped to 20 */, roles, full })
  .state                           // Observable<'idle' | 'running' | 'awaiting-approval' | 'error'>
  .title                           // Observable<string | null>
  .waitForResponse({ timeoutMs })  // resolves with the last assistant message; default 10 min
```

VERIFIED from `amp plugins show-docs`. The `limit` cap of 20 is the binding constraint — reading a
long thread means paging in 20-message chunks.

**Verdict on C: workable but inverted, and it costs you.** There is nothing to tail. A supervisor
built for "tail the JSONL" must be rewritten around (a) owning the child's stdout pipe,
(b) `amp top --stream-jsonl` for liveness, and (c) `amp threads export` polling for anything it
missed. The compensation is real: because the transcript is on the server, it is complete and
readable even when the machine that produced it is gone.

---

## D. CONTEXT — *(non-negotiable axis)*

### Can a supervisor TRIGGER compaction from outside? No.

This is the clearest negative finding in the profile, and it is VERIFIED by exhaustion rather than
by absence of documentation:

- The **complete CLI command tree** — 361 command paths extracted from the binary's own completion
  data, hidden entries included — contains **zero** occurrences of `compact`, `handoff` or `fork`.
- The **complete TUI command list** — all 69 entries from `amp config keymap`, which is the
  authoritative list of every bindable command in the client — contains **zero** occurrences of
  `compact`, `handoff` or `fork`. (`restore` appears once, as `prompt.history`, "Restore a previous
  prompt" — an input-history feature, not a context operation.)

There is no `/compact`. There is no external trigger. Compaction happens automatically or not at all.

The archived guide at `ampcode.com/guides/context-management` describes a **Handoff** feature —
"you first specify a goal for what you want to do next… a new message that contains the relevant
information and files is drafted and put in the prompt editor of a new thread". That page carries
its own banner: *"Archived — This guide was written in November 2025 for an earlier model and
context-management era."* Even as described, Handoff was interactive-only: it drafts into a prompt
editor. It has no command in the shipping client.

### Can a supervisor CONFIGURE the compaction point? Partly — from inside a plugin.

The one lever that exists, quoted verbatim from `amp plugins show-docs` (`CreateAgentConfig`):

```ts
/**
 * Estimated input-token count at which Amp automatically compacts the thread.
 * Must be a positive safe integer. When omitted, Amp uses the configured
 * percentage threshold, which defaults to 90%.
 */
compactionThresholdTokens?: number
```

So: default is **90% of the window**, and a *custom agent defined in a plugin* can set an absolute
token threshold instead. That is a knob on a dial the orchestrator can turn before the run, not a
button it can press during one. There is no settings-file key for it (`amp.*` settings list has no
compaction entry — VERIFIED from `amp --help`'s full settings reference).

### Can a supervisor READ how full the window is?

Three candidate paths, in descending order of how much I would trust them:

**1. `usage` on every assistant frame of `--stream-json` — the honest answer.** The documented
schema (VERIFIED, docs/cli/streaming-json):

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

and the docs' own worked examples show real values, e.g.
`"usage":{"input_tokens":10,"cache_creation_input_tokens":16256,"cache_read_input_tokens":0,"output_tokens":99,"max_tokens":968000,"service_tier":"standard"}`.

Summing `input_tokens + cache_creation_input_tokens + cache_read_input_tokens` against `max_tokens`
gives a per-turn fullness estimate that the orchestrator can compute from a stream it already reads.
Field **presence is VERIFIED**; the interpretation of `max_tokens` as the context ceiling is
**CLAIMED** — the schema does not label it, and `968000` is consistent with a ~1M window but is not
stated to be one. Note also that the whole `usage` object is optional (`usage?:`), so the
orchestrator must tolerate frames without it.

**2. `amp threads context T-…` — exists, output unverified.** The binary describes it as
*"Analyze the current context for a thread"* (alias `analyze-context`). It takes one argument and
**no `--json`**. The corresponding TUI command in `amp config keymap` is described as:

```
"thread.analyzeContext": null, // Open context usage for this thread on the web
```

— which strongly suggests the CLI form may print or open a URL rather than emit numbers. Output
format **UNKNOWN**; it needs authentication to observe. **Do not build on this without testing it.**

**3. The External API** exposes token counts per thread (`/threads/{id}/usage` returns per-model
`inputTokens`, `outputTokens`, `cacheReadInputTokens`, `cacheCreationInputTokens`) but these are
*cumulative spend counters across the thread's whole life*, not current-window occupancy. They will
overstate fullness after a compaction. Not usable for this axis.

### Is there proof a compaction happened?

Yes, but only from inside a plugin, and only by inference. From `ThreadMessagesOptions` (VERIFIED,
verbatim):

```
When true, read the full transcript, including messages that have been compacted away.

By default, messages are read as a new inference turn would see them:
when the thread has been compacted, the latest compaction summary
(as a user message) followed by the messages after the compaction cut
point; otherwise the full transcript.
```

So a plugin can read `messages({full: false})` and `messages({full: true})` and conclude a
compaction occurred when they diverge — and can read the compaction summary itself, because it is
materialised as a user message. There is **no compaction event** in `PluginEventMap` (the complete
list is `session.start`, `agent.start`, `tool.call`, `tool.result`, `agent.end` — VERIFIED), and no
CLI equivalent of the `full` flag. Compare pi, which writes a typed `CompactionEntry` into the
session file; Amp leaves a summary but no marker.

### Closest workaround, and what it costs

Re-implement handoff outside the tool:

1. watch `usage` in the stream; when input tokens cross your own threshold,
2. `amp threads markdown T-old` (or `threads export`) to get the transcript,
3. summarise it — either with your own model call or with `amp -x` in `low` mode, which is cheap,
4. `amp -x "<summary + next instruction>" --title … --label …` to open a fresh thread,
5. record the old→new id mapping yourself.

Cost: one extra model call per rollover, loss of Amp's own (better, model-assisted) compaction
summary, loss of thread continuity in the UI, and the orchestrator now owns a piece of state Amp
would otherwise have owned. There is no cheaper option; the trigger simply does not exist.

**Verdict on D: fails the owner's non-negotiable.** Reading fullness is possible and reasonably
clean via `--stream-json` `usage`. Triggering compaction from outside is impossible, and proof that
it happened is available only to in-process plugin code, by diffing two reads.

---

## E. QUOTA — *(non-negotiable axis)*

### The model is wrong-shaped for the owner's supervisor

The owner's existing quota logic is built around Anthropic's `five_hour.utilization` /
`seven_day.utilization` / `resets_at`. **Amp has no equivalent, because Amp does not meter time
windows — it meters money.** VERIFIED from docs/pricing:

| Tier | Terms | Tag |
|---|---|---|
| Hobby (free) | all product features; pay-as-you-go for orbs, or use your own runners free; *"No Amp token fees/limits"* | VERIFIED |
| Individual ($20/mo) | includes *"45,000 minutes of orbin' time"*; *"No Amp token fees or limits."* | VERIFIED |
| Teams (no extra charge) | members on mixed tiers; *"Shared billing and pooled credits"* | VERIFIED |
| Enterprise (custom) | *"Pooled credits only, no paid user seats"*, *"Spend limits and reporting"*, *"Higher resource quotas and rate limits"* | VERIFIED |

Other stated terms: pricing is *"actual model and tool usage in each thread"* with no Amp markup for
individuals and non-enterprise workspaces; *"Purchased credits expire twelve months after
purchase"*; when the included allowance runs out you *"can add paid credits and keep working"*; orbs
are *"billed by the minute"* and Amp *"pauses an orb 5 minutes after the agent stops working or 20
minutes after you last interacted with it, whichever comes later. A paused orb costs nothing."*
BYOK is available on every tier.

**There is no rolling window and therefore no `resets_at`.** The failure mode is not "wait four
hours"; it is "the balance hit zero, and it stays zero until someone pays". An orchestrator's
pause-and-resume-at-reset logic has nothing to hook onto. What it needs instead is a
*spend-remaining* threshold and a human escalation.

### What can actually be read programmatically

**`amp usage` — the only personal-scope reader.** Quoted verbatim from `amp usage -h`:

```
Usage: amp usage [options]

Show your current Amp usage and credit balance

Options:
  --details            Show detailed credit, token, and thread usage
  --start <timestamp>  Start of the usage range as an ISO 8601 timestamp
  --end <timestamp>    End of the usage range as an ISO 8601 timestamp
```

That is the complete option list. **There is no `--json`.** (VERIFIED — I checked both the `-h`
output and the completion tree; `amp usage` has exactly these three options plus globals, while
sibling commands like `threads list` and `permissions list` *do* have `--json`. The omission is
specific, not an oversight I can route around.) So reading the credit balance programmatically means
parsing human-formatted text whose layout is undocumented and unversioned. Output shape **UNKNOWN**
— it requires authentication.

`amp threads usage T-…` has the same three options and covers one thread.

The TUI also has `thread.showCost` — *"Show usage cost and entitlement for the active thread"* — so
entitlement state is surfaced per thread, but only interactively.

**The External API — workspace scope only, spend not remaining.** Base
`https://ampcode.com/api/v2`, spec at `/api/v2/openapi.json`. Auth is **`v2.OAuth2AppAuth`,
client-credentials M2M**, token endpoint `https://auth.ampcode.com/oauth2/token`; clients are created
with `amp oauth-clients create` / `list` / `edit`. Relevant endpoints (VERIFIED from the spec):

| Endpoint | Returns | Scope |
|---|---|---|
| `GET /workspace/analytics/daily-usage` | `metadata{startDate,endDate,activeUsers,totalUsers,totalUsage}` (USD) + per-day per-user rows. Params `endDate`, `lookbackDays` (1–365, default 1), `userID`. | `amp.api:workspace.analytics:view` |
| `GET /threads/{threadID}/usage` | `usage` (USD), `estimatedProviderCostAtListPriceUSD`, per-model `requests`/`inputTokens`/`outputTokens`/`cacheReadInputTokens`/`cacheCreationInputTokens`. *"Data only available for threads less than 90 days old"* | `amp.api:workspace.threads.meta:view` |
| `GET /workspace/entitlements` | `[{id, name, type:"paid_credits", usageLimitUSD, windowDays, assignment}]` | `amp.api:workspace.entitlements:view` |
| `GET /actor` | identity | `amp.api:actor:view` |

Every one of these reports **spend so far**. None reports **remaining**.

### The one rolling window that does exist

**Entitlements.** `windowDays` is constrained to `1 | 7 | 30`, paired with a `usageLimitUSD` and an
`assignment` of `default | users | workspace_groups | unmanaged`. They are creatable and updatable
over the API (`POST`/`PATCH /workspace/entitlements`, scope `…entitlements:manage`). VERIFIED from
the OpenAPI spec.

This is the closest structural analogue to a rate-limit window in the whole platform — a rolling
1/7/30-day dollar cap. It is also a **workspace-admin object**, not a personal quota, and requires
an Enterprise-shaped workspace and an M2M OAuth client to touch. For a single owner on an Individual
plan, it does not apply.

### Is a limit-hit signalled in band?

**Not specifically.** The stream's terminal frame is (VERIFIED, documented schema):

```ts
| { type: "result"; subtype: "error_during_execution" | "error_max_turns";
    duration_ms: number; is_error: true; num_turns: number;
    error: string; session_id: string; usage?: {...}; permission_denials?: string[] }
```

There are exactly two error subtypes, neither of them quota-specific. Distinguishing "out of
credits" from "the tool crashed" means **string-matching the free-text `error` field**, which is
exactly the fragile thing the owner's field notes already complain about elsewhere. The only
structured failure list in the whole schema is `permission_denials?: string[]`, and that is about
permissions, not money.

**Verdict on E: fails the owner's non-negotiable, and fails it structurally rather than
accidentally.** There is a command that prints the balance, but it emits text only. There is an API
that reports spend, but it reports the wrong side of the ledger and needs workspace-admin OAuth.
There is no reset time because there is no window. Best achievable: scrape `amp usage --details`
before each task, string-match the `error` field on failure, and escalate to a human on
depletion — with no automatic resume, ever.

---

## F. ACCOUNTS — *(non-negotiable axis)*

### This is Amp's best axis by a wide margin

Account selection for a **new** session is one environment variable:

```
AMP_API_KEY   "Access token for Amp (see https://ampcode.com/settings/security#access-token)"
```

quoted from `amp --help`'s environment-variable section (VERIFIED). Tokens start with `sgamp_`.
No profile directories, no `CLAUDE_CONFIG_DIR`-style indirection, no keychain derivation, no
per-folder binding file. `env AMP_API_KEY=$token_for_role amp -x …` and that process is that
account. Several accounts coexist on one machine trivially, because nothing is shared.

Three more per-process overrides make the isolation complete (all VERIFIED from `amp --help`):

| Variable / flag | Effect |
|---|---|
| `AMP_URL` | *"URL for the Amp service (default is https://ampcode.com/)"* — per-process endpoint, incl. custom domains / self-hosted |
| `AMP_SETTINGS_FILE` / `--settings-file <path>` | an entirely separate settings file per session — separate MCP servers, separate permission rules, separate tool allow-lists |
| `AMP_LOG_FILE` / `--log-file <path>` | per-session log |

So a supervisor can give each role its own **account + endpoint + settings + log** with four env
vars and no filesystem surgery. Compare Claude Code, where §4 of the field scan
documents per-profile `CLAUDE_CONFIG_DIR`, a derived keychain service name
(`Claude Code-credentials-<8 hex>`), and the `~/.claude.json` vs `~/.claude/.claude.json` trap. Amp
has none of that.

### The trap that will bite an unattended run — and it is documented

Quoted verbatim from docs/cli/execute-mode, "Non-Interactive Environments" (VERIFIED):

> Use an access token from Settings, which starts with `sgamp_`. **The CLI rejects the short-lived
> session token that `amp login` stores, because it expires within an hour and cannot be refreshed
> from an environment variable.**

Read that twice. A queue started from an interactively logged-in shell has **under an hour** before
its credential is worthless. The orchestrator must use long-lived access tokens from
`ampcode.com/settings/security`, never `amp login`.

### The login path, and its macOS hazard

`amp login` is an interactive **device-code** flow. Observed live in the sandbox (I killed it before
confirming, so no account was touched):

```
$ amp threads
No API key found. Starting login flow...
To log in, visit:

https://auth.ampcode.com/device?user_code=ZHHB-HXHL

and confirm that the code shown matches: ZHHB-HXHL

Waiting for confirmation in the browser...
```

`amp logout` is described as *"Log out by removing stored API key"*. The binary links macOS
Security.framework — `_SecKeychainFindGenericPassword`, `_SecKeychainAddGenericPassword`,
`_SecKeychainItemDelete`, `_SecKeychainItemModifyAttributesAndData` are all present in its symbol
table (VERIFIED) — and carries the string *"Keychain access denied. In CI environments, use
{allowUnrestrictedAccess: true} option."* So the interactive path has the same
"macOS blocks on a GUI keychain dialog" failure mode the field scan flags for Claude Code. **The
`AMP_API_KEY` path avoids the keychain entirely**, which is a second, independent reason to use it.

### Can a running session's account be changed?

**No.** Nothing in the command tree does this, and nothing in the plugin API does either. The
workaround is to let the turn finish (or `thread.cancel()` it from a plugin), then continue the
thread from a new process under a different key:

```
env AMP_API_KEY=$other amp threads continue T-… -x "carry on"
```

This works **only if the other account can see that thread** — i.e. it owns it, or the thread's
visibility is `workspace` (and both accounts are in that workspace) or `unlisted`. Visibility is
settable at launch (`--visibility private|unlisted|workspace|group`), per repository
(`amp.defaultVisibility`, e.g. `{"github.com/org/repo": "workspace"}`), after the fact
(`amp threads share T-… --visibility unlisted`), and from a plugin
(`thread.setVisibility('private'|'workspace')`). **An orchestrator that wants role handoff between
accounts must decide its visibility policy up front**, because a `private` thread is a dead end for
every other account.

### Orthogonal: model-provider credentials (BYOK)

Distinct from Amp accounts. `amp config model-providers` offers
`list / activate / deactivate / show --workspace / delete / test / check-access / add-router /
edit-router / setup-guide / edit-key / add-chatgpt-subscription`, with router options covering
`--base-url`, `--api-format`, `--headers`, `--query-params`, Cloudflare AI Gateway
(`--cloudflare-account-id`, `--cloudflare-gateway-id`), Google Cloud
(`--workload-identity-provider`, `--google-cloud-project`, `--google-cloud-location`) and AWS
(`--iam-role-arn`, `--aws-region`). All VERIFIED from the completion tree.

Two things matter for an orchestrator. First, `activate` *"deactivates any other active key of the
same provider"* — it is a **global** switch, not per-session, so two concurrent sessions cannot use
two different keys for the same provider through this mechanism. Second, `add-chatgpt-subscription`
*"Link your ChatGPT subscription to Amp as a model provider by signing in to OpenAI in your
browser"* — which is directly relevant to the owner's stated interest in ChatGPT as a platform: Amp
can consume a ChatGPT subscription as a backend. Workspace-level equivalents live at
`/api/v2/workspace/model-provider-keys` (*"Key secrets are never returned"*).

**Verdict on F: passes the owner's non-negotiable, and is the best implementation in the scan so
far.** One env var per process, no shared state, no keychain, no config-dir archaeology. The two
caveats — `amp login` tokens expire in under an hour, and a running session's account cannot be
changed — are both documented and both designable-around.

---

## G. INTERVENTION — *(non-negotiable axis)*

The owner's field notes record a nudge that cannot submit stranded text. Amp has **two** independent
answers to that, and one of them is better than anything else in this scan except pi's RPC.

### 1. Steering a running headless session, over stdin

`--stream-json-input` (requires `--execute` **and** `--stream-json`). Amp then reads JSON Lines from
stdin and — quoted verbatim from docs/cli/streaming-json — *"exits only after the assistant is done
and stdin has closed. This allows a program to send several user messages during one
conversation."* The input schema, verbatim:

```ts
type StreamJSONInputMessage = {
  type: "user";
  steer?: boolean;
  message: {
    role: "user";
    content: Array<
      | { type: "text"; text: string }
      | { type: "image"; source_path?: string;
          source: { type: "base64"; media_type: "image/jpeg"|"image/png"|"image/gif"|"image/webp"; data: string } }
    >;
  };
};
```

And the decisive line, verbatim:

> Set the top-level `steer` field to `true` if Amp should handle a queued message at the next
> interruption point while the agent is busy.

That is precisely the missing primitive: **inject an instruction into a session that is mid-turn,
and have it taken at the next safe point.** No TTY, no screen scraping, no keystroke simulation.

The docs even ship a working supervisor sketch (verbatim):

```bash
send_message() {
  local text="$1"
  echo '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"'$text'"}]}}'
}
{
  send_message "what's 2+2?"
  sleep 10
  send_message "now add 8 to that"
  sleep 10
  send_message "now add 5 to that"
} | amp --execute --stream-json --stream-json-input
```

### Does the orchestrator *know it arrived*?

**Yes, by echo — but not by acknowledgement.** Each accepted user message is re-emitted on stdout
before the next assistant turn:

```json
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"now add 8 to that"}]},"parent_tool_use_id":null,"session_id":"T-addfb7a4-61d9-41e1-890b-7330aa54087a"}
```

(VERIFIED — the docs' own three-message worked example shows all three echoes interleaved with the
assistant replies.) So there **is** a receipt. What there is not is an id: the input schema has no
request-id field and the output has no correlated response. Matching is by content and ordering.
That is weaker than pi's `--mode rpc`, where a command carries an optional `id` and gets a
correlated `{type:"response"}`. For an orchestrator sending distinguishable instructions it is
sufficient; for one sending two identical nudges it is ambiguous.

One caveat: image blocks sent as input are deliberately **not** echoed — *"User image blocks are
accepted as input but omitted from streamed user messages on stdout so the output remains compatible
with Claude Code."* (VERIFIED.) An image nudge therefore has no receipt at all.

### 2. Answering the session's own question — permission delegation

There is **no** `question` or `permission_request` event in the stream schema (the complete list of
output types is `assistant`, `user`, `result`, `system/init`, `system/error_*` — VERIFIED). What
Amp offers instead is stronger and more general: an **external program arbitrates every tool call,
synchronously, out of process.**

```
amp permissions add delegate --to amp-permissions-helper '*'
```

or, in `amp.permissions`:

```json
{ "tool": "*", "action": "delegate", "to": "my-permission-helper" }
```

The contract, quoted verbatim from `ampcode.com/notes/permissions`:

> And then you'll write a tiny program called `amp-permissions-helper` and put it on your `$PATH`.
> The program receives the tool parameters on stdin as JSON, and makes a decision with its exit
> code: **0 allows the tool call, 1 makes Amp ask, and 2 rejects the tool call, forwarding stderr to
> the model.**

The tool name arrives in the environment as `AGENT_TOOL_NAME` (VERIFIED — used in the docs' own Open
Policy Agent example, which forwards `{input:{toolName, args}}` to an OPA server and maps
`allow/ask/reject` onto exit codes 0/1/2).

**This is the axis-G answer the owner is actually looking for**, and it is better than a
question-answering channel: rather than waiting for the agent to ask, the supervisor gets a veto on
every action before it happens, with a channel (stderr → the model) for explaining *why*. A
supervisor can implement "phone home, wait for the orchestrator's policy, decide" in a 20-line shell
script.

### 3. From inside a plugin — the richest surface

From `amp plugins show-docs` (all VERIFIED):

```ts
amp.on('tool.call',  h)  // → { action: 'allow' }
                         //   { action: 'reject-and-continue'; message }
                         //   { action: 'modify'; input }
                         //   { action: 'synthesize'; result: { output, exitCode? } }
amp.on('tool.result',h)  // observe or replace the result
amp.on('agent.start',h)  // → { message: { content, display? } } — inject context, alter the system prompt
amp.on('agent.end',  h)  // → { action: 'continue'; userMessage; maxContinuations? }

amp.threads.get(id).appendUserMessage(msg, { steer })   // reach ANY thread by id
amp.threads.get(id).cancel()                            // stop the current turn
amp.threads.get(id).state                               // 'idle'|'running'|'awaiting-approval'|'error'
amp.activeThread                                        // which thread the user is looking at
amp.ai.ask(...)                                         // thread-scoped yes/no classification
ctx.ui.notify / confirm / input / select                // and helpers.isPluginUINotAvailableError
```

Three of these deserve emphasis:

- **`agent.end` → `{action:'continue'}`** is a sanctioned autonomous loop driver. Its own docs:
  *"How many plugin `continue` turns may run in a row after the last user-sent message. Amp ignores
  `continue` once this many consecutive plugin continuations have already happened. Defaults to 5.
  Any message the user sends resets the count. Raise it deliberately, for example in a plugin that
  drives long-running work toward a goal, and keep your own stop condition."* A ralph-style loop is
  a supported use case, with a built-in circuit breaker.
- **`amp.threads.get(threadID)`** is not limited to the current thread. One plugin can steer a
  sibling session. That makes an in-process orchestrator possible.
- **`state === 'awaiting-approval'`** means a blocked session is externally detectable — and its
  presence confirms that approval blocking is real, which matters for §H.

### 4. The TUI path, for completeness

`thread.interrupt` is bound to `esc esc`. `prompt.queue` ("Queue the prompt to run after the current
turn instead of steering"), `prompt.dequeue` and `prompt.steerQueuedMessage` all exist as commands
but have **no default binding** (`null` in `amp config keymap` — VERIFIED), so a supervisor driving a
TUI by keystroke would have to bind them first via the `amp.keymap` setting. Nobody should do this
when `--stream-json-input` exists.

**Verdict on G: passes the owner's non-negotiable, twice over.** Steering a busy session is a
documented flag with a worked example and an echo receipt. Answering the session's own decisions is
better than answering questions — it is a synchronous external veto on every tool call with a
documented exit-code contract. The only shortfall against pi is the absence of request-id
correlation on injected messages.

---

## H. GUARDRAILS

### Two current primary sources disagree, and both matter

`https://ampcode.com/docs/tools#permissions`, fetched 2026-09-19, says this **in full**:

> Permissions — Amp does not ask for approval before running tools. Use a custom plugin to control
> tool use. Workspace admins can distribute it as a global workspace plugin.

`https://ampcode.com/docs/sdk` repeats it verbatim under "Tool Permissions". Meanwhile the shipping
binary still carries a complete `amp permissions` subsystem *and* ships built-in rules with `ask`
actions in them, and the plugin API still has an `awaiting-approval` thread state.

The reconciliation I would offer, tagged **CLAIMED** because nothing states it: the docs describe
the post-"Amp Neo" *default posture* (Amp does not prompt you out of the box), while the rule engine
still exists for people who configure it. An orchestrator must not rely on either reading alone.
**Test the actual behaviour before trusting a run unattended.**

### The rule engine, as the binary describes it

```
amp permissions list [--json] [--builtin] [-w|--workspace]
amp permissions add <action> <tool> [--to <program>] [--context <thread|subagent>] [-w]
amp permissions test <tool-name> [-c <context>] [-t <thread>] [--json] [-q|--quiet] [-w]
amp permissions edit [-w]
```

Quoted from `amp permissions add -h` (VERIFIED):

> Add a permission rule to the beginning of the list. Rules are evaluated in order, so newer rules
> take precedence.
> `<action>` — Permission action: **allow, reject, ask, or delegate**
> `<tool>` — Tool name (supports globs like `"mcp__playwright__*"`)

and from `amp permissions test -h`:

> Test permissions against configured rules without running the tool.

Rule shape, from `/news/tool-level-permissions` (VERIFIED, verbatim):

```jsonc
"amp.permissions": [
  { "tool": "Bash", "matches": { "cmd": "*git commit*" }, "action": "ask"},
  { "tool": "Bash", "matches": { "cmd": ["*python *", "*python3 *"] }, "action": "reject"},
  { "tool": "mcp__*", "action": "ask"},
  { "tool": "*", "action": "delegate", "to": "my-permission-helper"}
]
```

`amp permissions test … -q` reduces the decision to an exit status. **That is a genuinely good
orchestrator affordance** — a preflight that answers "would this be allowed?" without running
anything, scriptably.

### The built-in defaults, dumped verbatim from the binary

`amp permissions list --builtin --json` (VERIFIED, run here, no auth needed). Abridged but exact:

```json
[
  { "tool": "load_plugin",        "action": "ask" },
  { "tool": "reload_plugins",     "action": "ask" },
  { "tool": "Bash", "action": "ask",   "matches": { "cmd": "*git*push*" } },
  { "tool": "Bash", "action": "allow", "matches": { "cmd": "/rg\\s+[-;(]+/" } },
  { "tool": "mcp__*",             "action": "allow" },
  { "tool": "read_mcp_resource",  "action": "allow" },
  { "tool": "Bash", "action": "allow",
    "matches": { "cmd": "/^(.*\\s+)?(bazel|ibazel)\\s+.*\\/\\/[^\\s]*.*$/" } },
  { "tool": "Bash", "action": "allow",
    "matches": { "cmd": ["ls","ls *","dir","dir *","cat *","head *","tail *","less *","more *",
                         "grep *","egrep *","fgrep *","tree","tree *","file *","wc *","pwd","stat *", …] } }
]
```

**Read the fifth line again: `{"tool": "mcp__*", "action": "allow"}`.** Every MCP tool from every
connected server is allowed by default. For an unattended run with, say, a Slack or a database MCP
server attached, that is the whole attack surface, wide open, before you have configured anything.

### What the platform will do unattended without asking

- Everything on the built-in allow-list, plus every MCP tool.
- `git push` is the one notable `ask` in the defaults — so a default-configured unattended run may
  **block on a push** (thread state `awaiting-approval`) unless overridden.
- **UNKNOWN and important:** what an `ask` does in `--execute` mode with no TTY. It may auto-deny,
  it may hang. `ThreadState` includes `awaiting-approval` as a real state, and there is no
  approval channel in the stream schema, so hanging is plausible. The `result` frame's
  `permission_denials?: string[]` field suggests denials at least get reported. **This is the single
  most important thing to test before any overnight run.**

### The off switches

| Control | Exact text | Tag |
|---|---|---|
| `amp.dangerouslyAllowAll` | *"Disable all command confirmation prompts (agent will execute all commands without asking)"* | VERIFIED (settings reference in `amp --help`) |
| `--dangerously-allow-all` | hidden flag; exists in the completion tree; no help text | VERIFIED (existence) / UNKNOWN (semantics) |
| `amp.guardedFiles.allowlist` | *"Array of file glob patterns that are allowed to be accessed without confirmation. Takes precedence over the built-in denylist."* The built-in denylist's contents are not printed anywhere I could reach. | VERIFIED (key) / UNKNOWN (denylist contents) |
| `amp.tools.disable` | *"Array of tool names to disable. Use 'builtin:toolname' to disable only the builtin tool with that name (allowing an MCP server to provide a tool by that name)."* | VERIFIED |
| `amp.tools.enable` | *"Array of tool name patterns to enable. Supports glob patterns (e.g., 'mcp__metabase__*'). If not set, all tools are enabled. If set, only matching tools are enabled."* | VERIFIED |
| `amp.mcpPermissions` | MCP server allow/denylist | VERIFIED (docs/cli/settings) |
| `amp mcp approve` | approve a workspace MCP server | VERIFIED |

MCP server health is visible in the init frame with a status enum that is itself a guardrail
signal: `"awaiting-approval" | "authenticating" | "connecting" | "reconnecting" | "connected" |
"denied" | "failed" | "blocked-by-registry"` (VERIFIED, documented schema). Enterprise workspaces
additionally have an MCP registry allow-list (`/docs/enterprise/mcp-registry-allowlist`).

### Settings precedence and enterprise control

- User: `~/.config/amp/settings.json` or `.jsonc` (macOS and Linux; `%USERPROFILE%\.config\amp\…` on Windows)
- Workspace: the nearest `.amp/settings.json` or `.jsonc`, searched upward from cwd
- Enterprise managed (macOS): `/Library/Application Support/ampcode/managed-settings.json`
  (Linux `/etc/ampcode/managed-settings.json`, Windows `%ProgramData%\ampcode\managed-settings.json`)
- Precedence: **workspace overrides user overrides enterprise managed**
- Per-process override: `--settings-file <path>` / `AMP_SETTINGS_FILE`
- `amp config edit [--global|--workspace]` opens the right one in `$EDITOR`

(All VERIFIED, docs/cli/settings plus the binary.)

**Note the precedence direction.** Workspace settings — a file inside the repository the agent is
working on — override the user's. An orchestrator checking out untrusted code is checking out its
own permission rules along with it. `--settings-file` does not close this; only not running in
hostile repos does.

### Sandboxing

There is **no local sandbox**. Amp's isolation story is remoting: **orbs**, Amp-hosted VMs reached
with `--executor orb` / `-ox` at sizes `a1.tiny` → `a1.3xlarge`, with their own secrets
(`amp secrets list/get/set/delete/history` — *"secret values are never returned"*), supervised
services (`amp orb service start|stop|restart|status|logs|list|ensure`, declared in
`.amp/services.yaml`), HTTP portals, an iOS simulator, OIDC token minting (`amp orb id-token
--audience --ttl-seconds --subject-scope`), and **Amp Net** — `amp net exit-node` / `route` /
`status` / `ping` / `run`, which sends an orb's outbound traffic through a machine you control.
(All VERIFIED from the command tree.) Isolation by billing-per-minute, in other words.

**Verdict on H: capable, but the defaults are not safe for an unattended queue, and the
documentation contradicts the binary.** Configure explicitly: set `amp.tools.enable` to a
glob allow-list, override the `mcp__*` allow, decide what `ask` should become, and prefer a
`delegate` helper over `dangerouslyAllowAll` so that the orchestrator keeps a decision point.

---

## I. EXTENSIBILITY

### MCP — comprehensive

```
amp mcp add <name> -- <command...>            [--env K=V] [--header H] [--workspace]
amp mcp add <name> <https-url>                # remote server
amp mcp list [--json] | amp mcp remove <name> | amp mcp doctor | amp mcp approve <name>
amp mcp remote add <name> <url> --auth <oauth|bearer|none>
        [--bearer-token-file F] [--oauth-client-id ID] [--oauth-client-secret-file F]
        [--personal | --workspace <w> | --project <p> | --current-project] [--json]
amp mcp remote list|update|remove|check|tools|login|logout
amp mcp oauth login|logout|status <server>
```

Per-run injection without touching settings: `--mcp-config '<json or path>'`, e.g. (verbatim from
the docs)

```
amp --mcp-config '{"everything": {"command": "npx", "args": ["-y", "@modelcontextprotocol/server-everything"]}}' -x "What tools are available to you?"
```

`${VAR}` placeholders in an MCP server's `env` are expanded from Amp's environment at server
startup (VERIFIED, docs/sdk). All VERIFIED.

### Skills — and a finding specific to this owner

```
amp skill add <source> [--target T] [--global] [--overwrite] [--name N]
amp skill list [--json] | remove | info [--json] | repositories [--json]
```

The settings keys tell you where skills are found, verbatim from `amp --help`:

- `amp.skills.disableClaudeCodeSkills` — *"Disable skills from `.claude/skills/`,
  `~/.claude/skills/`, and `~/.claude/plugins/cache/`."*
- `amp.skills.disableGlobalAgentsSkills` — *"Disable skills from `~/.config/agents/skills/` and
  `~/.agents/skills/`."*
- `amp.skills.path` — *"Path to additional directories containing skills. Supports colon-separated
  paths (semicolon on Windows)."*

**Amp reads Claude Code's skill directories by default.** For this owner specifically, whose
`~/.claude` is described in the field scan as "rich and active — `agents/`, `commands/`, `skills`,
`plugins`, `hooks`, `gsd-core`, `harness/`…", installing Amp means his entire Claude Code skill
library and plugin cache become visible to Amp on first run without any action. That is either a
large free head start or an unwanted surprise, depending on intent, and it is worth knowing before
install rather than after.

### Plugins — TypeScript, and the real extension point

Locations (VERIFIED, `amp plugins show-docs`): project `.amp/plugins/*.ts`; system
`~/.config/amp/plugins/*.ts`; global/workspace plugins in workspace settings (limited experimental
release). Directory plugins use `<name>/index.ts`.

```
amp plugins add <url> [--auto-update] [--target T] | remove | update [--force] | list
amp plugins import <ref> [--repository R] [--overwrite] | repositories [--json]
amp plugins show-agent-options [--json]     # legal models + builtin tool names for plugin agents
amp plugins exec <plugin> <event> [--data <json>]   # run a plugin against a synthetic event
amp plugins show-docs                        # the full 2,074-line API reference, offline
```

`amp plugins show-docs` printing the complete typed API offline, without authentication, is the
single most researchable thing about this platform. Every plugin quote in this document came from
it.

API highlights beyond §G's event handlers:

```ts
amp.registerTool(...)      amp.registerCommand(...)      await amp.registerSkill(...)
amp.ai.ask(...) / generateText / generateObject      amp.attachments.upload(...)
amp.$`shell command`       amp.logger      amp.configuration (Observable)
amp.system.{ workspaceRoot, ampURL, user, executor }
amp.system.executor.kind : 'local' | 'remote' | 'unknown'
amp.system.executor.keepAlive()   // orb only; renews automatically, consumes orb runtime credits
amp.experimental.createStatusItem(...)
```

`amp.system.executor.kind` lets a plugin know whether it is running locally or in an orb — useful
for an orchestrator that spreads work across both.

**`amp plugins exec <plugin> <event> --data <json>`** is the one shell-side door into plugin code.
Its semantics beyond that one-line description are **UNKNOWN**, but if it does what it says, it is
the bridge between a bash orchestrator and the plugin API's thread-steering surface.

### Agents and subagents

Built-in modes: `low`, `medium`, `high`, `ultra` (deprecated aliases `smart`, `deep`, `rush` still
accepted). Selected with `-m/--mode` or `mode.toggle` (`ctrl+s`). Built-in specialist subagents,
each with *"its own context window and access to tools like file editing and terminal commands"*:
**Search**, **Oracle** (reasoning and planning), **Librarian** (external codebases), **Read Thread**.
They *"work in isolation, so they can't communicate with each other"*. A `Task` tool appears in the
init frame's tool list. Supporting models handle *"analyzing images, PDFs, audio, and video;
generating or editing images; naming threads; and compacting the context."* (All VERIFIED,
docs/models-and-subagents.)

Custom agents, from the plugin API (VERIFIED):

```ts
amp.experimental.createAgent({
  name, model, instructions, tools /* AgentToolSelection, globs like 'mcp__*', 'plugin__*' */,
  reasoningEffort /* none|minimal|low|medium|high|xhigh|max */,
  oracle: { model, reasoningEffort },      // pin the Oracle for threads running this agent
  subagents: { model, reasoningEffort },   // pin Task workers, finder, thread reader, librarian
  compactionThresholdTokens,               // see §D
  features, display,
})
amp.getBuiltinAgent('low'|'medium'|'high'|'ultra')
amp.registerAgentMode({ ... })   // needs a matching `// @amp-agent-mode key label` comment
Agent.run(message, options?)     Agent.createThread(options?)
```

Being able to pin the model *and* the reasoning effort of the Oracle and of Task workers separately
from the main agent is unusually fine-grained, and directly relevant to a GSD-style workflow that
wants a cheap executor and an expensive reviewer.

### Context files

`AGENTS.md` is Amp's convention (`/docs/customize/agents-md`), and the context guide confirms
*"The AGENTS.md files you have in your codebase go into the context window too."* Whether Amp also
reads `CLAUDE.md` is **UNKNOWN** — it reads Claude Code's *skills* directories by name, but
`CLAUDE.md` is not named in any setting.

### Can a GSD-style, subagent-heavy engine run inside Amp?

Structurally, yes — and with less porting than expected. The pieces GSD needs all exist: skills
(already reading `~/.claude/skills`), subagents with independent context windows, custom agents with
per-role model pinning, MCP, project-scoped config, and a plugin event loop that can drive
continuation. The gaps are mechanical, not architectural:

1. GSD's entry points are Claude Code slash commands; Amp's equivalent is `amp.registerCommand` in a
   plugin, or a skill. Every command needs a shim.
2. GSD's hook model is Claude Code's `settings.json` hooks; Amp's is `amp.on(...)` in TypeScript.
   Five events versus Claude Code's larger set — `session.start`, `agent.start`, `tool.call`,
   `tool.result`, `agent.end`. There is **no** `SessionEnd`, no `PreCompact`, no notification hook.
3. Anything GSD does by writing state files under `.planning/` works unchanged, since the agent has
   a normal filesystem.

**Verdict on I: strong.** MCP, skills, plugins, custom agents and per-role model pinning are all
first-class, the API is fully documented offline, and the settings surface is well-factored.

---

## J. OPERATIONAL REALITY

### Cost model

Usage-based in USD with no Amp markup for individuals and non-enterprise workspaces. Hobby free /
Individual **$20/mo** including *"45,000 minutes of orbin' time"* / Teams pooled at no extra charge /
Enterprise pooled-credits with spend limits. Credits expire twelve months after purchase. Orbs are
billed by the minute and auto-pause (5 min after the agent stops, or 20 min after last interaction,
whichever is later); *"A paused orb costs nothing."* BYOK on every tier. (VERIFIED, docs/pricing.)

For an overnight queue, the relevant number is not the subscription — it is that **model spend is
uncapped by default** and there is no rolling window to hide behind (§E). Whatever the queue burns,
it burns.

### Maturity and velocity — the biggest unattended hazard

4,266 published versions. Five releases between 2026-09-18T21:04Z and 2026-09-19T12:12Z. The binary
I profiled announced itself as released **one hour** before I ran it. And the defaults are:

- `amp.updates.mode` — *"Control update checking behavior: `warn` shows update notifications,
  `disabled` turns off checking, `auto` automatically runs update."* Default: **`"auto"`**.
- `amp.runner.autoUpdate.enabled` — *"Let `amp --no-tui` runners install CLI updates and restart
  into them once no thread is running there (at most once every 12 hours). `amp.updates.mode:
  disabled` also turns this off."* Default: **`true`**.

(Both VERIFIED from the settings reference in `amp --help`.)

**An unattended overnight queue will, by default, update its own binary underneath itself and — on
a runner — restart into the new one.** With a release every few hours, that is not a theoretical
risk over an eight-hour run. Mitigation is one line of settings (`"amp.updates.mode": "disabled"`)
plus `AMP_SKIP_UPDATE_CHECK=1` in the environment. Nothing else in this scan has this property to
this degree, and it belongs in the orchestrator's preflight.

### Install footprint

One native executable, ~73 MB for darwin-arm64, no Node runtime required (the npm entry is a
platform-selecting wrapper; the documented install is a shell script). Runtime state on this
machine: `~/.config/amp/`, `~/.cache/amp/logs/cli.log`, `~/.local/share/amp/device-id.json`.
Shell completions for bash 4+, zsh, fish and PowerShell 7. (All VERIFIED.)

### Known and suspected unattended failure modes

| # | Failure mode | Tag |
|---|---|---|
| 1 | **Auto-update mid-queue.** Default `amp.updates.mode: "auto"`, plus runner self-restart. | VERIFIED (defaults) |
| 2 | **Credential expiry under an hour.** A queue started from an `amp login` session dies when the stored session token expires and cannot be refreshed. Must use `AMP_API_KEY` with an `sgamp_` access token. | VERIFIED (docs/cli/execute-mode) |
| 3 | **`ask` with no TTY.** `ThreadState` has `awaiting-approval`; the stream has no approval channel; built-in defaults `ask` on `git push`. Behaviour UNKNOWN — may hang indefinitely. | UNKNOWN — **test first** |
| 4 | **`mcp__*` allowed by default.** Every MCP tool runs unattended out of the box. | VERIFIED |
| 5 | **Workspace settings override user settings.** A repo can redefine the agent's permissions. | VERIFIED |
| 6 | **`amp top --stream-jsonl` is EXPERIMENTAL** by its own help text; the liveness watchdog is built on an unstable schema. | VERIFIED |
| 7 | **`--help` on a subcommand prints the root help.** Scripted capability probes silently read the wrong page. Use `-h`. | VERIFIED (observed) |
| 8 | **Hard dependency on ampcode.com** for launching, resuming and even reading your own transcript. No offline mode. | VERIFIED by construction |
| 9 | **macOS keychain prompt** on the interactive login path (Security.framework symbols + "Keychain access denied" string present). Avoidable via `AMP_API_KEY`. | VERIFIED (binary) |
| 10 | **Threads archive themselves after `-x`** unless `--no-archive-after-execute`; a plain `amp threads list` will not show completed runs. | VERIFIED |
| 11 | **Passkey re-auth** can be required for web/app interaction, workspace-wide by an admin — which an unattended supervisor cannot satisfy if it depends on the web path. | VERIFIED (docs/cli/remote-control) |

### Is it plausible to run Amp overnight unattended today?

**Yes — with a specific and non-obvious preflight.** The minimum viable configuration:

```bash
export AMP_API_KEY=sgamp_...          # long-lived access token from Settings → Security. Never amp login.
export AMP_SKIP_UPDATE_CHECK=1
export AMP_SETTINGS_FILE=/path/to/orchestrator-settings.json   # per-role, isolated
# in that settings file:
#   "amp.updates.mode": "disabled"
#   "amp.tools.enable":  [ ...explicit glob allow-list... ]
#   "amp.permissions":   [ { "tool": "*", "action": "delegate", "to": "orchestrator-permission-helper" } ]

amp -x "<task>" --stream-json --stream-json-input \
    --title "<queue item>" -l "<run-id>" --no-archive-after-execute \
    --plugin-ready-timeout 30
```

with the orchestrator holding stdin (for `steer` nudges), parsing stdout (for `session_id`, `usage`
and the terminal `result`), and a `delegate` helper adjudicating every tool call.

What it will do well: run, be steered mid-turn, survive its own crash, resume exactly, and let a
supervisor veto every action. What it will not do: tell you how much capacity is left in any form
you can parse, or let you compact from outside.

---

## What this costs the orchestrator

**Four things Amp gives you that reduce the adapter's work:**

1. **Account switching is free.** One env var per process. Delete the profile-directory, keychain
   and config-dir machinery the Claude Code adapter needs; there is no equivalent here.
2. **Resume is free and total.** State is server-side. Nothing to checkpoint, nothing to recover,
   no crash-consistency problem — the orchestrator only has to remember a `T-…` string.
3. **Steering is a flag, not a hack.** `--stream-json-input` with `steer: true` replaces the
   "nudge that cannot submit stranded text" the field notes record, and comes with an echo receipt.
4. **Permission arbitration is an out-of-process contract.** A `delegate` helper on `$PATH` gives
   the supervisor a synchronous veto over every tool call, with stdin JSON in and exit codes
   0/1/2 out, and stderr fed back to the model. This is a better primitive than answering questions.

**Five things Amp makes the orchestrator build, buy or abandon:**

1. **A quota story that is not a quota story.** There is no window, no utilisation percentage, no
   `resets_at`. The adapter must scrape `amp usage --details` text (no `--json` exists), treat
   depletion as terminal rather than as a pause, and escalate to a human. The owner's
   "pause until reset, then auto-resume" loop **cannot be implemented against Amp**. Budget: a text
   parser that will break, plus an escalation path the other adapters do not need.
2. **A compaction story the orchestrator owns entirely.** No external trigger exists. The adapter
   must watch `usage.input_tokens` against `usage.max_tokens` itself, decide the rollover point
   itself, summarise via `amp threads markdown` + a model call itself, open the successor thread
   itself, and maintain the old→new id mapping itself. Budget: a full handoff implementation,
   roughly what the plugin's existing context logic does, with none of it reusable from Amp.
3. **A transcript reader with no file to tail.** Three separate mechanisms replace one tail:
   own the child's stdout pipe, run `amp top --stream-jsonl` (EXPERIMENTAL schema) for liveness, and
   poll `amp threads export T-…` for anything missed. Budget: a poller with a diffing layer, plus
   acceptance that the liveness schema will change without notice.
4. **Id bookkeeping after the fact, not before.** No `--session-id`. The adapter must parse
   `session_id` from the first stream line, handle the window where a process died before emitting
   it, and reconcile orphans by `--label` through `amp threads search --json`. Budget: small, but
   it is a correctness problem, not a convenience one.
5. **A version pin and an update lock, as a first-class preflight step.** `amp.updates.mode` defaults
   to `"auto"` against a binary that ships roughly every three hours. The adapter must set
   `"amp.updates.mode": "disabled"` and `AMP_SKIP_UPDATE_CHECK=1`, and should record the exact
   version in the run manifest — because with this cadence, two runs a day apart are not running the
   same software.

**One strategic observation.** Amp is the only platform in this scan whose architecture assumes the
supervisor is *not* on the same machine as the agent. Orbs, runners (`--executor runner:<id>`),
cross-client access, thread ids as the only handle, server-side transcripts, per-thread entitlements
— all of it is built for "start work somewhere, watch it from anywhere". An orchestrator that
adopted Amp's shape rather than adapting Amp to a tail-a-file shape would get remote execution,
crash immunity and multi-machine fan-out for free. It would also permanently give up the two things
the owner called non-negotiable that Amp cannot do. That is the real trade, and it is not a small
one in either direction.

**Where Amp sits against the field so far.** Best-in-scan on accounts (F) and on unattended
guardrail arbitration (G/H's delegate contract); second only to pi on intervention (G), losing only
on request-id correlation; unique on remote execution (A); worst-in-scan on quota (E), where it is
not merely weaker but structurally different; and a clear fail on externally-triggered compaction
(D), where the capability simply does not exist in the shipping client.

---

## Open questions a later pass should close

| # | Question | Axis | Why it matters |
|---|---|---|---|
| 1 | What does `amp threads context T-…` actually print? Numbers, or a URL? | D | It is the only named context-reading command; if it prints numbers, §D's verdict softens. |
| 2 | What do the hidden `--observe`, `--daemon` and `--headless` flags do? | A, C, G | Three plausible orchestrator hooks, all undocumented. |
| 3 | What does an `ask` permission do in `-x` mode with no TTY — hang, or deny? | H, J | Decides whether an unattended run can survive the default `git push` rule. |
| 4 | What is `amp top --stream-jsonl`'s actual output schema? | C | It is the only fleet-wide liveness signal. |
| 5 | What exactly does `amp usage --details` print? | E | Determines whether a scraper is feasible at all. |
| 6 | Does `amp plugins exec <plugin> <event> --data <json>` let a shell script drive the plugin thread API? | G, I | If yes, a bash orchestrator gets `appendUserMessage`, `cancel` and `state` without writing a resident plugin. |
| 7 | Does a locally-executing turn resume mid-turn after the CLI is killed, or start a new turn? | B | The difference between "resume exactly" and "resume approximately". |
| 8 | Does Amp read `CLAUDE.md` as well as `AGENTS.md`? | I | Affects how much of the owner's existing context transfers. |
| 9 | What is in the built-in guarded-files denylist? | H | Unknown denylist means unknown blast radius. |

All nine need one authenticated session with a throwaway account. None of them can be answered from
documentation.

---

## Sources

All fetched or executed **2026-09-19**.

**Run on this machine (sandboxed HOME, no authentication, no credits spent):**
- `amp --version` → `0.0.1789819237-ge34793 (released 2026-09-19T12:00:37.000Z, 1h ago)`
- `amp --help` — 472 lines: commands, visible options, environment variables, examples, full settings reference
- `amp completions zsh` — 81 KB; embedded JSON command tree, 361 command paths, hidden options included
- `amp <cmd> -h` for `permissions`, `permissions add`, `permissions test`, `permissions list`, `permissions edit`, `usage`, `threads`, `top`
- `amp permissions list --builtin --json` — built-in permission rules
- `amp config keymap` — complete 69-entry TUI command list
- `amp plugins show-docs` — 2,074-line typed Plugin API reference
- `amp threads` with no key — observed the device-code login flow, then killed it
- Local install probe: `which amp`, `~/.amp`, `~/.config/amp`, `~/Library/Application Support/amp`, npm global, Homebrew, `~/.local/bin`, `~/.bun/bin`, `~/.vscode/extensions` — **all negative**
- `strings` over the 73 MB binary (102,132 lines) — Security.framework keychain symbols confirmed; CLI-internal strings not recoverable

**Registries:**
- npm `@ampcode/cli` — version, bin, optional platform packages, 4,266 versions, publish times
- npm `@sourcegraph/amp` — deprecation shim, description pointing at the rename
- npm `@ampcode/sdk` `0.1.0-20260918210405-g81edbf0` (2026-09-18T21:08Z)
- PyPI `amp-sdk` `0.1.20260918210324` (2026-09-18T21:04Z)

**Official documentation (ampcode.com):**
- `/manual` — navigation and section index
- `/docs/cli` — install, executors, completions, IDE connect, platform support
- `/docs/cli/execute-mode` — `-x`, `-ox`, piping, `--fast`, `--plugin-ready-timeout`, `--executor runner:`, `AMP_API_KEY` and the one-hour session-token warning
- `/docs/cli/streaming-json` — complete output and input schemas, `session_id`, `usage`, `steer`, worked multi-message example
- `/docs/cli/settings` — settings file locations, precedence, enterprise managed settings, env vars
- `/docs/cli/runners` — `--no-tui`, `--runner-id`, `--dir`, `--discover-dirs`, `amp runner dirs`
- `/docs/cli/remote-control` — cross-client access, `--remote-control-terminal`, passkey requirement
- `/docs/threads` — thread ids, server-side storage, `threads continue/share/markdown/export`, visibility levels
- `/docs/tools#permissions` — *"Amp does not ask for approval before running tools."*
- `/docs/models-and-subagents` — modes, Search/Oracle/Librarian/Read Thread, system models, BYOK
- `/docs/pricing` — tiers, credits, expiry, orb billing
- `/docs/customize/plugins` — plugin locations and lifecycle events
- `/docs/orbs/automations` — schedule-triggered thread continuation
- `/docs/sdk` — SDK options, executors, MCP config, settings file, skills
- `/api/external` and `/api/v2/openapi.json` — External API v2, 26 endpoints, OAuth scopes, entitlements, analytics
- `/news` — changelog; *"One Runner Is Now Enough"* (17 Sept 2026), *"Fable 5.1"* (1 Sept 2026), *"Global Plugins and Skills"* (11 Aug 2026)
- `/news/tool-level-permissions` — `amp.permissions` rule shape with `allow/reject/ask/delegate`
- `/notes/permissions` — the delegate helper contract: stdin JSON, exit codes 0/1/2, `AGENT_TOOL_NAME`, OPA example
- `/guides/context-management` — **archived**, banner dated November 2025; Handoff, thread referencing
