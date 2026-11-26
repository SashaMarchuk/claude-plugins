# C7 — Session runtime: interactive vs headless, and answering an agent's prompts

Cluster: **C7-session-runtime** · Item: **R1-11** · Written 2026-09-19
Evidence grades used throughout: **VERIFIED** (I read it in source/schema, or ran it on this machine
and pasted the result), **CLAIMED** (a vendor doc, README or third-party post says so, unchecked),
**INFERRED** (my reasoning from verified parts, marked as such).

Machine this was checked on: macOS 26.5.2 (Darwin 25.5.0), arm64.
Installed and used: `claude` **2.1.278**, `codex-cli` **0.152.0**, `tmux` **3.6a**, `expect` (BSD),
`cursor-agent`. **Not installed here:** `gemini`, `opencode` — those two are documented from primary
source (repo source / official docs), not run.

---

## 1. What the owner decided — verbatim

> "Наприклад, **тільки інтерактивні сесії, або тільки headless
> сесії, тощо, так далі, або гібрид, або переважно інтерактивні і тільки інколи headless**, тощо, так
> далі. … Друге, це те, що **оркестратор може робити інтерактивність зесіями, наприклад, з тим самим
> код-кодом, якщо він раптом використовує ask user question, то оркестратор може відповідати на ці
> питання, і це повністю і повністю окей**" — [324]

In English, the rest of the answer: it all depends on configuration, each platform gets its own setting, and running Claude Code invisibly in headless mode is possible **"але з цим треба бути дуже обережним"**.

Confirmed at [328]: "Так, підтверджую, переходимо до наступного питання", against the interviewer's
restatement at [325]/[327], which added the qualifier the owner himself did not say:

> "Користувач налаштовує окремо для кожної платформи режим сесій: лише інтерактивні, лише фонові,
> змішані або переважно інтерактивні з можливістю фонових. Оркестратор має вміти взаємодіяти із
> сесіями, зокрема **відповідати на їхні запитання до користувача в межах налаштованих повноважень**." — [325]

**What is his and what is the interviewer's.** Four session modes, per-platform configuration, "треба
бути дуже обережним" about headless, and the orchestrator answering AskUserQuestion — all his. The
phrase "в межах налаштованих повноважень" (within configured authority) is the interviewer's wording,
accepted by him at [328] but not originated by him; `research/extract/by-item.md` flags exactly this
("the analysis appends 'within configured authority [325]', which is the interviewer's wording, not
his"). He attached **no condition** to answering: "це повністю і повністю окей", said twice.
`research/extract/outside-list.md` reads the doubling as pre-empting an objection.

Two things follow that this research must respect and does:

- The **fourth mode is his own invention** — "переважно інтерактивні і тільки інколи headless". That
  is not a boolean flag, it is a *policy*: something has to decide, per session, which way it goes.
- **Headless is allowed, and he himself attached the warning.** Nothing below overrides that. What
  section 4 does is name the specific thing that is dangerous, which turns out to be narrower and
  sharper than "headless is risky in general".

---

## 2. How the world does it

There are exactly four ways anything drives a coding agent today. Everything else is a variant.

### 2.1 A JSON-RPC protocol over stdio or a socket

The agent runs as a server; the supervisor is the client and holds the event loop. Questions the
agent would ask a human arrive as **requests the client must answer**, correlated by id.

- **Codex app-server** — `codex app-server --listen stdio://|unix://|ws://IP:PORT`. **VERIFIED** on
  this machine: I generated the protocol's own JSON Schema with
  `codex app-server generate-json-schema --out <dir>` and read the method lists out of it, and I
  completed a real `initialize` handshake over stdio (section 3.2).
- **ACP (Agent Client Protocol)** — a vendor-neutral JSON-RPC 2.0 stdio protocol: `session/prompt`,
  `session/update` (notifications), `session/request_permission`, `session/cancel`. Gemini CLI speaks
  it natively (`--acp`); Codex speaks it through the `codex-acp` adapter, which "starts the Codex App
  Server, translates ACP requests into Codex operations" (**CLAIMED**, repo description;
  `@agentclientprotocol/codex-acp` on npm). A Claude Code ACP adapter exists in the same family
  (**CLAIMED**, not checked).
- **Claude Code's own control protocol**, carried inside `--input-format stream-json` /
  `--output-format stream-json`. **VERIFIED** from the typings shipped in
  `@anthropic-ai/claude-agent-sdk` 0.2.141 on this machine: `SDKControlRequest` /
  `SDKControlResponse` with ~45 subtypes including `can_use_tool`, `hook_callback`, `interrupt`,
  `get_context_usage`, `set_permission_mode`, `request_user_dialog`, `elicitation`, `remote_control`.

### 2.2 An HTTP server with an event stream

- **opencode** — `opencode serve` exposes an OpenAPI REST surface plus SSE. Relevant paths
  (**CLAIMED**, official docs at opencode.ai/docs/server): `POST /session`, `POST /session/:id/message`
  (send and wait), `POST /session/:id/prompt_async` (send and don't wait), `POST /session/:id/abort`,
  `GET /event` (SSE, first event `server.connected`), `GET /session/status`, and — the one that
  matters here — **`POST /session/:id/permissions/:permissionID`**, "Respond to a permission request".
  A typed client exists as `@opencode-ai/sdk`.

### 2.3 One-shot headless invocation

Run the agent to completion, read stdout. No dialogue: anything that would prompt is pre-decided by
flags, or the run dies.

- `claude -p` with `--output-format text|json|stream-json`, `--permission-mode`,
  `--permission-prompts host|none`. **VERIFIED** from `claude --help`.
- `codex exec [--json] [-s read-only|workspace-write|danger-full-access]
  [--approve-for-me|--dangerously-bypass-approvals-and-sandbox] [-o FILE] [--output-schema FILE]`.
  **VERIFIED** from `codex exec --help` and one real run.
- `gemini -p <prompt> -o text|json|stream-json --approval-mode default|auto_edit|yolo|plan`.
  **VERIFIED** from gemini-cli source, `packages/cli/src/config/config.ts` on `main`:
  `.option('approval-mode', { choices: ['default','auto_edit','yolo','plan'] })`,
  `.option('output-format', { alias:'o', choices: ['text','json','stream-json'] })`,
  `.option('resume', { alias:'r' })`, `.option('acp')` with `experimental-acp` deprecated in its
  favour. There is **no `--input-format`** — Gemini headless is one prompt per process. Latest release
  v0.60.0, 2026-09-15 (**VERIFIED**, `gh api`).
  Caveat worth carrying: `--output-format json` was documented before it existed (google-gemini/gemini-cli#9009,
  "Unknown arguments: output-format"); that issue is **closed as completed** (**VERIFIED**, `gh api`,
  closed 2025-09-26). Treat Gemini docs as ahead of Gemini binaries by default.
- `cursor-agent -p --output-format text|json|stream-json --resume [chatId] -f`. **VERIFIED** from
  `cursor-agent --help` on this machine. `-f` = "Force allow commands unless explicitly denied" —
  a blunt switch, no per-request channel.

### 2.4 A PTY someone types into

A terminal multiplexer or an AppleScript-driven terminal holds a real TTY; the supervisor sends
keystrokes and reads the screen.

**tmux** is the only one of these with a real machine interface (**VERIFIED**, `man tmux` on 3.6a):

- `send-keys [-l] [-H] [-t pane] key...` — "if the string is not recognised as a key, it is sent as a
  series of characters. **The -l flag disables key name lookup** and processes the keys as literal
  UTF-8 characters."
- **control mode** (`tmux -C` / `-CC`): "a textual interface … allows applications to communicate with
  tmux using a simple text-only protocol", with notifications including `%output pane-id value`,
  `%extended-output`, `%pause`, `%continue`, `%exit`, `%window-close`, `%layout-change`. This is a
  push stream of pane output — strictly better than polling `capture-pane`, and nothing in the old
  harness used it.
- `capture-pane -p [-J] [-S -N] [-e]` — the polling route.

**iTerm2 via AppleScript** and **Terminal.app** have no such interface: you get "write text" and
"get contents". This distinction is the whole of section 4.5.

---

## 3. What is feasible, per platform

### 3.1 Claude Code 2.1.278 — VERIFIED on this machine

**Runtimes available.** Four, not two:

1. **Headless one-shot** — `claude -p`.
2. **Headless conversational** — one long-lived `claude -p --input-format stream-json
   --output-format stream-json` process fed successive user messages on stdin.
   **VERIFIED by running it**: I sent "Remember the number 47. Reply OK." then, twelve seconds later,
   "What number did I ask you to remember?" into the same process. Output:
   `TEXT>> I'll save that for you.` … `TEXT>> 47` … `RESULT>> success 47`.
   This is the runtime the owner is reaching for when he says headless — a session with no terminal
   that the orchestrator can still talk to.
3. **Background session** — `claude --bg`, then `claude agents`, `attach`, `logs`, `stop`, `rm`,
   `respawn`. **VERIFIED**: `claude agents --json` on this machine returned a real registry with no
   TTY required —
   `{"id":"8402872a","cwd":"…","kind":"background","sessionId":"…","name":"…","state":"blocked"}`
   alongside `{"pid":35475,"kind":"interactive","sessionId":"…","status":"busy"}`.
   It lists **interactive sessions too**. That is a supervisor-grade session inventory the previous
   harness built by hand out of a registry directory and screen scrapes.
4. **Interactive TUI in a PTY** — the classic route, plus `--remote-control` (see 3.1.4).

**Resume.** `--resume <session-id>`, `--continue`, `--fork-session`, `--session-id <uuid>`
(pre-assign the id before launch), `--from-pr`. `--bg --resume <id>` "continues that session in the
background under the same ID". **VERIFIED** from `--help`.

**Permission prompts — a real protocol event.** `can_use_tool` arrives as a `control_request`
carrying `tool_name`, `input`, `tool_use_id`, `agent_id`, `permission_suggestions`,
`decision_reason_type` (`'rule' | 'mode' | 'subcommandResults' | 'permissionPromptTool' | 'hook' |
'asyncAgent' | 'sandboxOverride' | 'workingDir' | 'safetyCheck' | 'classifier' | 'other'`) and
`classifier_approvable`. The answer is a `PermissionResult`:
`{behavior:'allow', updatedInput?, updatedPermissions?}` or `{behavior:'deny', message, interrupt?}`.
**VERIFIED** in `sdk.d.ts` and exercised live. `--permission-prompt-tool <mcp tool>` still works on
2.1.278 — it is absent from the `--help` option list but **VERIFIED accepted** (the run succeeded).
`--permission-prompts host|none` selects whether the host or nobody answers.

**Hooks.** 29 events (**VERIFIED**, `HookEvent` in `sdk.d.ts`): `PreToolUse`, `PostToolUse`,
`PermissionRequest`, `PermissionDenied`, `Notification`, `Stop`, `SubagentStart`, `SubagentStop`,
`PreCompact`, `PostCompact`, `Elicitation`, `ElicitationResult`, `TeammateIdle`, `SessionStart`,
`SessionEnd`, `CwdChanged`, `FileChanged`, and more. Hooks are a second, out-of-band way for a
supervisor to observe and veto — they work in headless and interactive alike.

**Context window is measurable, two ways.** `get_context_usage` control request returns
`{categories: [{name, tokens}, …]}` (**VERIFIED**, `SDKControlGetContextUsageResponse`), and every
`result` message carries full `usage` plus `modelUsage[model].contextWindow` (**VERIFIED** in my runs:
`"contextWindow":200000`). In the TUI it is also on screen: I watched the status bar read
`Haiku 4.5 [████░░░░░░░░░░░░░░░░] 22% 44.4k master tmuxwork`. This closes the gap FIELD-NOTES names —
"nothing in the plugin measures a session's context window" — without scraping, for every runtime
except a pure PTY.

#### 3.1.4 Remote Control

`claude --remote-control [name]`, `--remote-control-session-name-prefix <prefix>` (**VERIFIED**,
`--help`), and a `remote_control` control-request subtype in the SDK protocol (**VERIFIED**,
`SDKControlRemoteControlRequest` in the union). Shipped 2026-02-24 as a research preview; it bridges a
local interactive session to the Claude mobile app / claude.ai so a human can "monitor, approve, and
direct" it from elsewhere, with execution staying local (**CLAIMED**, third-party write-ups; I did not
pair a device). Its relevance to C7 is narrow but real: it is Anthropic's own answer to "drive an
**interactive** session from outside the terminal", and it proves the TUI has an out-of-band control
channel that is not keystrokes. Whether a third-party orchestrator may speak it is **not established**
— treat as an open question, not a plan.

#### 3.1.5 tmux/PTY — what actually happens on 2.1.278

I ran a real TUI (`claude --model haiku --permission-mode bypassPermissions`) inside
`tmux new-session -d -s c7test -x 200 -y 50` and drove it. All **VERIFIED**, all pasted from the runs:

| Step | What I did | What happened |
|---|---|---|
| Launch | `send-keys -l 'claude …'` + `send-keys Enter` | A **trust dialog**: "Quick safety check: Is this a project you created or one you trust?" with `❯ No, exit` / `Yes, I trust this folder`. Screen only. |
| Answer it | `send-keys Down`, then `send-keys Enter` | Accepted; TUI came up at the prompt. |
| Type, don't submit | `send-keys -l 'reply with the single word PING'` | Text sat on the input line: `❯ reply with the single word PING`. |
| **Bare Enter** | `send-keys Enter` | **It submitted.** Within 3s: `❯ reply with the single word PING` / `⏺ PING` / `✻ Baked for 2s · done`. |
| Type into a **busy** session | mid-`sleep 20`, `send-keys -l 'SECONDMSG: say the word BANANA'` + `Enter` | **Queued**, visibly: `❯ SECONDMSG: say the word BANANA` / `ctrl+x ctrl+s to send now`, and the footer changed to `❯ Press up to edit queued messages`. |
| Wait it out | — | Both ran, in order: `⏺ FIRSTDONE` then `BANANA`. Nothing was lost. |

**This contradicts FIELD-NOTES §1.3/§1.4 on tmux + 2.1.278.** Those notes record that "a bare Enter
(`harness-term.sh key <tty> enter`) does **not** submit text already sitting on the line", that
`send` "**destroys** whatever was pending", and that five instructions were never delivered. I could
not reproduce any of that here. The reason is legible in the old code: `harness-term.sh` prefers
**iTerm2 via AppleScript** under `auto` (`harness-term.sh:16-17`), where `send` is
`write text "<text>" newline NO` followed by `write text "" newline YES`
(`harness-term.sh:127-145`). Those failures are recorded against the **AppleScript path**, not the
tmux path. I did not re-run the AppleScript path, so FIELD-NOTES stands unchallenged for iTerm2 —
what changes is that its conclusion must not be generalised to "a PTY cannot be driven."

**A live bug in the old tmux path, found while reading it.** `tmux_send` is
`tmux send-keys -t "$p" "$2"; sleep 2; tmux send-keys -t "$p" Enter` (`harness-term.sh:197-198`) —
**no `-l`**. Per `man tmux`, without `-l` each argument goes through key-name lookup first. A
one-word instruction that collides with a tmux key name (`Up`, `Enter`, `Space`, `Escape`, `Tab`,
`BSpace`) is sent as that **key**, not as text. `continue` is safe; `Up` silently is not.

#### 3.1.6 AskUserQuestion — the one that matters

This is the owner's own example, so I tested it three ways.

**(a) In the interactive TUI, via tmux — it works completely.** **VERIFIED.** I told the session to
call the tool. The dialog rendered:

```
 ☐ Deploy Target
Which environment should we deploy to?
❯ 1. Staging
     Deploy to staging environment for testing before production
  2. Production
     Deploy directly to production environment
  3. Type something.
  4. Chat about this
Enter to select · ↑/↓ to navigate · Esc to cancel
```

I sent one keystroke, `tmux send-keys -t c7test -l '2'`. The session recorded:

```
⏺ User answered Claude's questions:
  ⎿  · Which environment should we deploy to? → Production
⏺ You chose to deploy to Production.
```

A real answer, indistinguishable from the human's. Note option **3, "Type something"** — free-form
answers are reachable too, and option 4 "Chat about this" opens a discussion instead of choosing.

**(b) In headless/SDK mode, the question is fully visible.** **VERIFIED.** With a `canUseTool` host,
the tool call surfaces with its entire payload before it runs:

```
CAN_USE_TOOL>> {"toolName":"AskUserQuestion","input":{"questions":[{"question":"Do you prefer tabs or
spaces for indentation?","header":"Indentation","options":[{"label":"Tabs","description":"Use tab
characters for indentation"},{"label":"Spaces","description":"Use space characters for
indentation"}],"multiSelect":false}]},"opts":["signal","suggestions","blockedPath","decisionReason",
"title","displayName","description","toolUseID","agentID"]}
```

**(c) In headless mode, allowing it does not answer it — it fabricates an empty answer.** See 4.1.
This is the single most consequential finding in this cluster.

### 3.2 Codex CLI 0.152.0 — VERIFIED on this machine

**The app-server is the real interface, and it is not experimental in substance.** I ran a handshake:

```
$ printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{…}}}' … \
  | codex app-server --stdio
{"id":1,"result":{"userAgent":"c7-probe/0.152.0 (Mac OS 26.5.2; arm64) …","codexHome":"/Users/…/.codex",
 "platformFamily":"unix","platformOs":"macos"}}
{"method":"remoteControl/status/changed","params":{"status":"disabled","serverName":"<host>",…}}
```

**Every question Codex would ask a human is a `ServerRequest`** — a JSON-RPC request the client must
answer. The complete list, **VERIFIED** from the schema the binary itself generates:

| ServerRequest method | What it is |
|---|---|
| `item/commandExecution/requestApproval` | run this command? |
| `item/fileChange/requestApproval` | apply this patch? |
| **`item/tool/requestUserInput`** | **the Codex AskUserQuestion** |
| `item/permissions/requestApproval` | widen sandbox / network? |
| `mcpServer/elicitation/request` | an MCP server is asking |
| `item/tool/call` | client-side tool dispatch |
| `applyPatchApproval`, `execCommandApproval` | legacy forms |

`ToolRequestUserInputParams` is structurally the same object as Claude's AskUserQuestion:
`{threadId, turnId, itemId, isBlocking, questions: [{id, header, question, options: [{label,
description}]?, isOther, isSecret}]}`, answered with
`{answers: {<questionId>: {answers: [string, …]}}}`. Approvals answer with a `decision` —
`accept | acceptForSession | acceptWithExecpolicyAmendment | decline | cancel` for commands and file
changes; `PermissionsRequestApprovalResponse` carries a `GrantedPermissionProfile`, a
`scope` (default `"turn"`) and `strictAutoReview`.

**The orchestrator can drive a session it did not start.** `thread/resume`: "If thread_id identifies a
running thread, **app-server rejoins that thread**". **VERIFIED** from the schema's own prose.

**The orchestrator can interrupt, steer and inject.** `turn/steer` takes
`{threadId, expectedTurnId, input: UserInput[]}` — `expectedTurnId` is "Required active turn id
precondition. The request fails when it does not match the currently active turn", i.e. an optimistic
lock that makes mid-turn injection safe rather than racy. Also `turn/interrupt`,
`thread/inject_items` (append raw items to model-visible history), `thread/compact/start`,
`thread/shellCommand`, `thread/rollback`, `thread/revert`.

**Approvals can be routed to a machine by configuration.** `TurnStartParams.approvalsReviewer`:
`user | auto_review | guardian_subagent`, where `auto_review` "uses a carefully prompted subagent to
gather relevant context and apply a risk-based decision framework before approving or denying".
Codex ships the owner's idea — an agent answering on the human's behalf — as a first-class setting.
`approvalPolicy` is `untrusted | on-request | never`, or a `granular` object with
`{mcp_elicitations, rules, sandbox_approval, request_permissions, skill_approval}`.

**Context and rate limits are protocol events, not screen text.**
`thread/tokenUsage/updated` → `{last, total, modelContextWindow}`;
`account/rateLimits/updated` → `RateLimitSnapshot` with `primary`/`secondary` `RateLimitWindow`
`{usedPercent, resetsAt, windowDurationMins}`, `planType`, and a `rateLimitReachedType` enum.
There is a matching request, `account/rateLimits/read`. **VERIFIED** from schema.
(Side note for C6/rate-limits: the Claude-side OAuth usage endpoint this project relies on answered
`{"error":{"type":"rate_limit_error"}}` when I called it today — that probe is itself rate-limited.
Codex's equivalent is free and push-based.)

**Session inventory and lifecycle without a TTY.** `thread/list`, `thread/read`, `thread/turns/list`,
`thread/items/list`, `thread/loaded/list`, `thread/status/changed`
(`notLoaded | idle | active{activeFlags} | systemError`), `turn/started`, `turn/completed`,
`thread/compacted`, `thread/queue/changed`, `serverRequest/resolved`.

**CLI conveniences that need no protocol client at all.** **VERIFIED** from `--help`:
`codex queue --thread <uuid|name> --message <TEXT>` — queue a message into an existing session;
`codex agents` — "Browse all agent sessions on the shared local app-server daemon";
`codex exec resume [--last]`, `codex exec fork`, `codex app-server daemon`,
`codex app-server proxy` (proxy stdio to the running daemon's control socket),
`codex remote-control start|stop|pair`.

**Headless events.** `codex exec --json` emits JSONL. **VERIFIED** by running it:
`{"type":"thread.started","thread_id":"01a0b9d3-…"}`, `{"type":"turn.started"}`,
`{"type":"item.completed","item":{…}}`, `{"type":"error",…}`, `{"type":"turn.failed",…}`.
(That run failed for an unrelated, real reason worth recording: `~/.codex/config.toml` pins
`model = "gpt-6-astra"`, and the API replied *"The 'gpt-6-astra' model requires a newer version of
Codex."* Codex on this machine is currently mis-pinned.)

### 3.3 Gemini CLI — VERIFIED from source, not run here

- **ACP** is the supervisable runtime: `gemini --acp`, JSON-RPC 2.0 over stdio,
  `initialize` / `authenticate` / `newSession` / `loadSession` / `prompt` / `cancel`, plus
  `setSessionMode` and `unstable_setSessionModel` (**CLAIMED**, `docs/cli/acp-mode.md`). Permission
  requests ride the ACP standard `session/request_permission`: params `{sessionId, toolCall, options:
  PermissionOption[]}` where each option is `{optionId, name, kind}` and `kind` ∈
  `allow_once | allow_always | reject_once | reject_always`; the client replies
  `{outcome: {outcome:"selected", optionId}}` or `{outcome:{outcome:"cancelled"}}` (**CLAIMED**,
  agentclientprotocol.com).
- **Headless**: `-p/--prompt`, `-o/--output-format text|json|stream-json`,
  `--approval-mode default|auto_edit|yolo|plan`, `--yolo`, `-r/--resume latest|<index>`,
  `--session-id`, `--session-file` (mutually exclusive with `--resume`), `-i/--prompt-interactive`.
  **VERIFIED** from `packages/cli/src/config/config.ts` on `main`.
- **No `--input-format`** — one prompt per process; continuity only via `--resume`. **VERIFIED**
  (absent from the flag definitions).

### 3.4 opencode — CLAIMED from official docs, not run here

`opencode serve` → OpenAPI REST + SSE. Create with `POST /session`; talk with
`POST /session/:id/message` (blocking) or `POST /session/:id/prompt_async`; watch `GET /event`;
stop with `POST /session/:id/abort`; poll `GET /session/status`. **Answer a permission with
`POST /session/:id/permissions/:permissionID`**, and pending permissions are retrievable per session.
Permission values include `ask` (the default for `doom_loop` and `external_directory`) and `always`,
which "would approve future requests matching suggested patterns for the rest of the current
session". `@opencode-ai/sdk` gives `createOpencode()` (boot server + client) and
`createOpencodeClient()` (attach to a running one).

### 3.5 cursor-agent — VERIFIED from `--help`, bonus platform

`-p/--print`, `--output-format text|json|stream-json` (default `stream-json`), `--resume [chatId]`,
`create-chat` (returns an id), `-b/--background`, `-f/--force` ("Force allow commands unless
explicitly denied"). **No per-request permission channel** — only the blunt `-f`. Treat as
headless-only, policy-decided-in-advance.

### 3.6 The generic PTY route

`tmux` is the only PTY host with a machine interface worth building on (2.4). Control mode gives a
push stream (`%output`, `%pause`, `%exit`, `%window-close`) instead of polling. `expect` is present
here but is the wrong tool for a full-screen TUI: it matches a byte stream, and these TUIs repaint.
AppleScript-driven terminals are covered in 4.5.

---

## 4. What is NOT feasible, and why

### 4.1 Claude Code headless cannot answer AskUserQuestion. Allowing it fabricates an empty answer.

**VERIFIED by running it.** Host allows the tool call. The session receives:

```json
{"type":"user","message":{"role":"user","content":[{"type":"tool_result",
 "content":"User has answered your questions: . You can now continue with the user's answers in mind.",
 "tool_use_id":"toolu_01Eba…"}]},
 "tool_use_result":{"questions":[{"question":"Do you prefer tabs or spaces for indentation?",…}],
 "answers":{}}}
```

`answers: {}`. The sentence reads "User has answered your questions: **.**" — the answer list is
empty and the trailing period is all that is left of it. The child model noticed and carried on
anyway; its own reasoning in that run: *"the function result says 'User has answered your questions:
.' without showing what the answer was. This is unusual…"* — and it then reported the task complete.

**This is the exact failure shape FIELD-NOTES was written to warn about** — the merge that reports
success and does nothing, the truncated suite read as a pass. A headless session that asks a question
is told it was answered, is given nothing, and proceeds. Silently. Unattended, overnight.

**"Дуже обережним" is right, and this is the specific thing to be careful about.** Not headless in
general — *this*.

Two working answers exist. Both **VERIFIED by running them**:

- **Deny-with-message.** `{behavior:'deny', message:"SUPERVISOR ANSWER (acting for the user):
  Spaces. Treat this as the user's answer and continue."}`. The text reaches the model and it acts on
  it: `TEXT>> You prefer spaces for indentation.` **But** it arrives as
  `"is_error":true` with `tool_use_result:"Error: SUPERVISOR ANSWER …"`, and the run is recorded in
  `permission_denials`. It works by lying to the transcript. Do not build on it.
- **Replace the tool.** Disallow `AskUserQuestion`; inject an MCP tool the orchestrator owns. Full run:

  ```
  TOOLUSE>> mcp__orch__ask_supervisor {"question":"Which database should we use for this project?"}
  SUPERVISOR GOT>> {"question":"Which database should we use for this project?"}
  TEXT>>  The supervisor has decided that we should use Postgres for this project.
  RESULT>> success "The supervisor has decided that we should use Postgres for this project."
  ```

  A clean tool result. No `is_error`. No phantom answer. No `permission_denials` entry. This is
  proposal P2.

### 4.2 ACP has no "ask the user a question" primitive

ACP standardises **permission** (`session/request_permission`, four option kinds) and nothing else
interactive. There is no multiple-choice or free-form question method (**CLAIMED**, confirmed absent
across two ACP doc pages). So on **Gemini via ACP**, an agent's clarifying question is *ordinary
assistant text* in a `session/update` `agent_message_chunk` — the orchestrator must notice it is a
question by reading prose, and answer with a follow-up `session/prompt`. That is heuristic, not
protocol. Consequence: **Gemini cannot give the owner what Claude Code and Codex can.** Structured
questions are not portable.

### 4.3 A `claude --bg` background session cannot be answered without attaching

`claude agents --json` reports `"state":"blocked"` (**VERIFIED** — two of the user's real background
sessions were in that state while I looked). The command surface is `agents`, `attach`, `logs`,
`stop`, `rm`, `respawn`, `--resume` — **no "answer" or "send" verb** (**VERIFIED**, full `Commands:`
list from `--help`). A blocked background session is unblocked by `claude attach <id>`, i.e. by
becoming a PTY. Background mode therefore buys invisibility and a registry, but *forfeits the
answering channel* unless permissions were pre-decided at launch.

### 4.4 Screen scraping is fragile — and this run shows why, concretely

- **The spinner word is randomised.** In one short session I captured four different ones:
  `Pollinating…`, `Baked for 2s`, `Churned for 29s`, `Cooked for 3s`. Any detector keyed to a verb
  is a detector keyed to a dice roll.
- **State lives in the footer and changes shape.** Idle: `❯ ` · queued:
  `❯ Press up to edit queued messages` · busy: `esc to interrupt`. Three different strings for
  "is it working", none of them stable API.
- **Capture can return nothing while the process is perfectly alive.** For the first several seconds
  `tmux capture-pane -p` returned **empty** on a running pane; `alternate_on` was `0` and
  `capture-pane -a` said "no alternate screen". A poller that reads emptiness as death is wrong.
- **The process title is not the process.** `#{pane_current_command}` was `2.1.278` — Claude Code
  renames itself to its version. Backend code matching on `claude` will not find it.
- **Reflow.** Everything above was captured at a pinned `-x 200 -y 50`. At a human's window width the
  same dialog wraps differently, and column-sensitive parsing breaks.

FIELD-NOTES already counted the cost of this: "Four detector false positives fixed in one day: a
non-ASCII space misread as an unsent nudge…" and six false-STALLED nudges on healthy sessions.

### 4.5 Terminal.app cannot be driven at all; iTerm2/AppleScript is where the old failures live

`harness-term.sh:163-181` refuses `send` and `key` on Terminal.app outright — "not supported on
Terminal.app backend" (**VERIFIED** in source). And the AppleScript iTerm2 path is what
FIELD-NOTES §1.3, §1.4, §11.2 and §13 record against: five undelivered instructions, thirteen
consecutive stranded `continue`s, a 149-minute stall, and a recovery that destroyed the instruction
it was recovering (`key enter` did nothing, then `send " "` cleared the line). **Not reproduced by
me** — I did not re-run AppleScript — but nothing here rehabilitates it either, and 3.1.5 shows tmux
does not share the defect. The honest reading: *the old harness's terminal problems were an
AppleScript problem, not a PTY problem.*

### 4.6 The first-run trust dialog is screen-only

**VERIFIED**: a fresh interactive `claude` in a directory it has not seen blocks on
"Quick safety check: Is this a project you created or one you trust?" — no protocol event, no flag
observed that pre-answers it for the TUI. `-p` skips it ("The workspace trust dialog is skipped when
Claude is run in non-interactive mode", `--help`). Any PTY-based orchestrator must recognise and
answer this dialog before its session exists, or its worker never starts. FIELD-NOTES does not
mention it; it would strand a run in a new worktree.

### 4.7 Nothing here lets the orchestrator put text on *its own* input line

FIELD-NOTES §1.1: "A model has no way to put text on its own input line" — still true, and none of
the protocol routes change it. Self-compaction remains something a *second* process does to a
session. What changes: with Codex, `thread/compact/start` makes it a protocol call rather than typed
keystrokes; with Claude Code headless, `--autocompact <auto|tokens>` and `get_context_usage` make it
a policy rather than a screen-percentage race. FIELD-NOTES §1.2 (`/compact` lands only when no shell
is running) is a *TUI* constraint and evaporates outside the TUI.

---

## 5. Proposals

### P1 — Make the runtime a two-axis contract, not a boolean

The owner asked for four modes. They are two independent questions wearing one name:

- **drive** — `protocol` | `pty`: how the orchestrator talks to the session.
- **visibility** — `visible` | `hidden`: whether a human can walk up to it.

His four modes land on this cleanly, and the fourth stops being special:

| Owner's words | drive | visibility | Note |
|---|---|---|---|
| "тільки інтерактивні сесії" | pty | visible | |
| "тільки headless сесії" | protocol | hidden | |
| "гібрид" | per-role mix | per-role mix | |
| "переважно інтерактивні і тільки інколи headless" | default pty, protocol on a named condition | — | needs a *rule*, see P6 |

Why split them: `claude --bg` is **protocol-ish and hidden but not answerable** (4.3), and a tmux
session is **pty and hidden** (a detached session is invisible until someone attaches). One boolean
cannot say either of those. Config key shape, per the owner's "під кожну платформу своє налаштування":
`orchestrator.platforms.<platform>.runtime = {drive, visibility, answering}`.

### P2 — Make questions a protocol event on every platform: ban `AskUserQuestion`, inject `ask_supervisor`

**The strongest single recommendation in this cluster, and it is verified end to end.**

For any session the orchestrator runs headless: disallow the platform's native user-question tool and
inject an MCP tool the orchestrator answers — one `ask_supervisor(question, options[])`. MCP is
supported by Claude Code, Codex, Gemini CLI and opencode, so **one implementation covers every
platform**, including the two (Gemini, cursor-agent) that expose no question event at all.

What it buys, beyond working: every question and every answer passes through one function the
orchestrator owns. That is the natural place to apply R1-14's "tone of voice" authority basis, to
refuse and escalate when the question exceeds authority, and to write the provenance record in P5.

Trade-offs, stated plainly:
- The child model is steered toward a non-default tool; a session that ignores the instruction and
  finds no `AskUserQuestion` will improvise (usually by writing the question as text). The
  orchestrator must also watch for question-shaped assistant text as a fallback.
- Interactive PTY sessions should keep native `AskUserQuestion` — there it works, and a human may
  want to answer it (3.1.6a).
- Per-platform tool names differ; the disallow list is platform-specific even though the MCP tool is not.

### P3 — The decision table

| Platform | Recommended runtime | How the orchestrator answers a question | What is lost |
|---|---|---|---|
| **Claude Code** — hidden worker | `claude -p --input-format stream-json --output-format stream-json`, long-lived, host answers `can_use_tool`; `--session-id` pre-assigned; `AskUserQuestion` disallowed + `ask_supervisor` injected (**VERIFIED**) | Permissions: `PermissionResult` on the `can_use_tool` control request. Questions: the MCP tool call. | No human can walk up to it mid-run. Native `AskUserQuestion` must not be re-enabled (4.1). |
| **Claude Code** — visible worker | Interactive TUI in **tmux** (never AppleScript, never Terminal.app), control mode for output, `send-keys -l` + separate `Enter` (**VERIFIED**) | Read the dialog off the pane, send the option digit — e.g. `send-keys -l '2'` → `→ Production` (**VERIFIED**). Option "Type something" reaches free-form. | Everything in 4.4: scraping, reflow, randomised spinner words, the trust dialog (4.6). Context only as a status-bar percentage. |
| **Claude Code** — background | `claude --bg`, inventory via `claude agents --json` (**VERIFIED**) | **It cannot, while backgrounded.** Answer by `claude attach <id>` — i.e. convert to PTY (4.3). | The answering channel. Use only with permissions fully pre-decided. |
| **Codex CLI** | `codex app-server` (stdio, or `--listen unix://`), one client for all threads; `thread/resume` rejoins running threads (**VERIFIED**) | Reply to the `ServerRequest`: `item/tool/requestUserInput` → `{answers:{id:{answers:[…]}}}`; approvals → `decision`. Or set `approvalsReviewer:"auto_review"` and let Codex's own subagent decide. (**VERIFIED**, schema) | Experimental surface, may move between versions. Requires a real JSON-RPC client, not a shell script. |
| **Codex CLI** — cheap path | `codex exec --json` + `codex queue --thread … --message …` (**VERIFIED**, `--help`) | Queue a message; approvals only via `-s`/`--approve-for-me`/`--dangerously-bypass-…` set in advance. | Structured questions. `queue` posts a message, it does not answer a specific `requestUserInput`. |
| **Gemini CLI** | `gemini --acp` (**VERIFIED** flag exists in source) | Permissions: ACP `session/request_permission` → `{outcome:"selected", optionId}`. **Questions: no protocol event** — detect question-shaped text and reply with `session/prompt` (4.2). | Structured questions. Use P2's `ask_supervisor` to get them back. |
| **Gemini CLI** — one-shot | `gemini -p … -o stream-json --approval-mode …` (**VERIFIED**, source) | Nothing mid-run: `--approval-mode` decides in advance; continuity only via `-r/--resume`. | All interaction. No `--input-format` exists. |
| **opencode** | `opencode serve` + SSE `GET /event` (**CLAIMED**, docs) | `POST /session/:id/permissions/:permissionID`. Messages: `POST /session/:id/prompt_async`. | Unverified here — nothing was run. Verify before committing. |
| **cursor-agent** | `-p --output-format stream-json --resume <chatId>` (**VERIFIED**, `--help`) | Nothing. `-f` decides everything up front. | All interaction. Headless-only platform. |
| **Generic / unknown CLI** | tmux + control mode | Screen-read, `send-keys -l`. Last resort. | Everything in 4.4. |

### P4 — If a PTY is required, make tmux the only PTY backend

The owner wants visible terminals available and sometimes preferred; that is his call and it stands.
What this research adds is *which* PTY. Retire the AppleScript backends: Terminal.app is refused by
the old code's own hand (4.5), and iTerm2/AppleScript is where every recorded delivery failure lives.
tmux is scriptable, has a documented control-mode event stream, works headless and attached, is
OS-agnostic, and on 2.1.278 delivers text and queues messages correctly (3.1.5).

Concretely: always `send-keys -l` for text (the missing `-l` is a live bug, 3.1.5); send `Enter` as a
separate call; subscribe to control mode rather than polling `capture-pane`; pin pane geometry so
scraped layout is reproducible; and add a trust-dialog handler to session startup (4.6).

**Trade-off the owner should hear:** iTerm2 is what he actually looks at. Moving to tmux means either
running tmux *inside* an iTerm2 window (keeps the visible terminal, gains the control interface —
`claude --tmux` exists and "uses iTerm2 native panes when available", **VERIFIED** in `--help`), or
accepting that visible sessions look different. The first option costs nothing and is what I'd pick,
but it is his to pick.

### P5 — Record every answer the orchestrator gives, as evidence

Whatever channel answers a question, write one record: platform, session id, the question and its
options verbatim, the answer given, the authority basis it was given under, and the timestamp.

Rationale from his own words, not mine: R1-14 makes the *basis* for a decision configurable —
user-written rules, a "tone of voice" of past decisions, previous answers to similar questions, the
agent's project knowledge. None of that is learnable unless answers are recorded. And in
**controlled** mode the same record is what the human reviews before the hard stop releases.

This also gives the orchestrator the one thing headless mode otherwise destroys: a way to tell the
difference between "answered" and "was told it was answered" (4.1).

### P6 — Name the rule behind "переважно інтерактивні і тільки інколи headless"

His fourth mode needs a predicate, and a defensible default exists that is built only from verified
facts: **run PTY/interactive by default; go headless only when the work needs no question answered
that the orchestrator is not authorised to answer.** Since P2 routes every question through
`ask_supervisor`, the orchestrator knows its own authority before it launches — so the choice is
computable rather than guessed.

Sharper heuristics, all supported above: prefer headless for bounded, well-specified work with
pre-decided permissions (4.3's constraint is then harmless); prefer interactive when the ticket is
underspecified, when the run touches the trunk (R1-12), or when the human said the run is
**controlled** (R1-14) — in controlled mode, a stop must reach a human anyway, so a visible terminal
costs nothing and is where he can type.

I am proposing the predicate, not the answer. It is his to set.

---

## 6. Open questions for the owner

1. **Headless AskUserQuestion is a silent-corruption bug, not a risk.** (4.1: the tool reports
   "answered" with `answers:{}`.) Do you want the orchestrator to (a) forbid the native tool in
   headless and inject `ask_supervisor` (P2, verified working), (b) refuse to launch headless at all
   for roles that might ask, or (c) allow it and accept that a headless session can be told it was
   answered when it was not? I recommend (a), but you said "все можливо, варіант" and this is the
   variant that decides how much of your unattended run is trustworthy.

2. **"В межах налаштованих повноважень" was the interviewer's phrase, not yours** ([325] vs [324]).
   You said "повністю і повністю окей" with no condition. Does the orchestrator answer *anything* a
   session asks, or is there a class of question it must refuse and escalate even in an autonomous
   run? R1-14 already gives you the machinery ("Якщо агент вирішив, що це точно має бути хардстопом …
   відбувається хардстоп … навіть якщо це автономний ран" [082]) — the open part is whether a
   *question from a child session* can trigger it.

3. **The fourth mode needs a rule** (P6). "Переважно інтерактивні і тільки інколи headless" — what is
   "інколи"? A per-role setting, a per-ticket flag, a budget ("no more than N headless at once"), or
   a predicate the orchestrator computes?

4. **Gemini cannot do what Claude Code and Codex can** (4.2: ACP has permissions but no question
   event). Is Gemini a first-class platform that must support structured questions via P2's MCP tool,
   or a second-class one for work that never asks?

5. **tmux instead of iTerm2/AppleScript** (P4). This changes what your visible terminals look like
   unless tmux runs inside iTerm2. Which do you want: iTerm2 windows exactly as today (and keep the
   AppleScript failure modes), or tmux-in-iTerm2 (same look, scriptable, but a new layer)?

6. **Codex ships `approvalsReviewer: "auto_review"`** — its own subagent deciding approvals on the
   user's behalf, with a "risk-based decision framework" (3.2). That is your idea, already built, but
   it is *their* policy, not yours. Do you want the orchestrator to use it where available, or always
   answer with your own configured authority so the basis is uniform across platforms?

7. **`claude agents --json` already lists every session, interactive and background, with state**
   (3.1). It is a better registry than the one the old harness maintained by hand. Should the
   orchestrator adopt per-platform native inventories where they exist (`claude agents`,
   `codex agents` / `thread/list`, opencode `GET /session/status`), or keep one registry of its own
   for uniformity across platforms that have none?

8. **`claude --remote-control` exists** (3.1.4) and is Anthropic's own channel for directing an
   interactive session from outside the terminal. Worth a spike to see whether an orchestrator may
   speak it, or out of scope as a human-only feature?

---

## Appendix — commands run for this research

```
claude --version                                  # 2.1.278
claude --help                                     # flags + Commands list
claude agents --help ; claude agents --json       # live session inventory, no TTY
claude -p --permission-prompt-tool mcp__foo__bar --model haiku 'say hi'   # hidden flag accepted
node askq.mjs        # SDK host, canUseTool allow  -> answers:{} (4.1)
node askq-deny.mjs   # SDK host, deny w/ message   -> answer lands, is_error:true
node askq-mcp.mjs    # MCP ask_supervisor          -> clean answer (P2)
bash multiturn.sh    # -p stream-json in+out, two user messages, state kept
tmux new-session -d -s c7test -x 200 -y 50 ; send-keys -l / Enter / Down ; capture-pane -p
man tmux             # send-keys -l, CONTROL MODE notifications
codex --version                                   # codex-cli 0.152.0
codex --help ; codex exec --help ; codex queue --help ; codex agents --help
codex app-server --help ; codex remote-control --help
codex app-server generate-json-schema --out <dir>  # ServerRequest/ClientRequest/ServerNotification
printf '…initialize…' | codex app-server --stdio   # live handshake
codex exec --json --skip-git-repo-check -s read-only '…'   # JSONL event shapes
cursor-agent --help
gh api repos/google-gemini/gemini-cli/{issues/9009,releases/latest,contents/packages/cli/src/config/config.ts}
```

Artefacts left in the scratchpad:
`…/scratchpad/c7/{askq.mjs,askq-deny.mjs,askq-mcp.mjs,multiturn.sh}` and
`…/scratchpad/c7-schema/` (the generated Codex app-server protocol schemas).
