# DeepSeek Harness (`dsh`) — mapped against the eleven requirements

**Stage:** adoption verdict. Follows `deepseek-harness-identity.md` in this directory.
**Candidate:** `deepseek-ai/deepseek-harness`, evaluated at `master` = `ddefc45fbc7f8e46dd73185e68295696d1297887`
(2026-09-17, release `0.1.6-alpha.2`). npm `@deepseek-ai/dsh` `latest` = `0.1.5-rc.2` (2026-09-10), 22 versions,
all pre-1.0. **Date of research:** 2026-09-19.
**Method:** repository source and package documentation read directly over `raw.githubusercontent.com`, the full
`master` tree via the GitHub trees API, repository metadata and the registry via `gh`/npm. Every claim below
carries a path into the repository. No claim rests on the top-level README alone.

---

## Blocker carried forward, and what was done about it

The brief again points at
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/context/orchestrator-landscape.md`.
**It still does not exist.** The `context/` directory exists and is empty; a filesystem search finds no file of
that name. The identity note flagged the same gap.

Rather than return a second absolute verdict, I rebuilt the minimum comparison the question needs by probing the
named tools directly (`gh search repos`, `gh api`, their READMEs). That is enough to answer "better than the best
of those *for this job*", and the relevant finding is in [Comparative verdict](#comparative-verdict). It is not a
substitute for the survey; the survey should still be regenerated.

---

## Bottom line

**DSH is not an orchestrator and cannot become one by configuration.** Its queue, its schedule, its goals, its
teams and its jobs are all scoped to one live Session in one live process, by their own documentation. There is no
cross-session work queue, no board integration that writes back, and — the decisive one — **nothing anywhere in
DSH reads a subscription quota.** The exhaustive generated config surface (`docs/config-catalog.md`, 128 packages)
contains no quota, spend, or wall-clock budget field at all.

What DSH is, is the best-documented collection of *durable agent primitives* in the field, and three of them solve
problems the owner's current harness measurably does not solve. The honest outcome is **borrow, do not adopt**, and
the borrowing is unusually cheap because DSH's primitives are separately published npm packages and one of them is
a C file.

One finding changes the picture from the identity note: **DSH ships first-party providers that drive a real
Claude Code session and a real Codex session as delegated children** (`packages/subagent/subagent-claude-code`,
`packages/subagent/subagent-codex`). The identity note listed this as an open question for stage two. It is real,
it is first-party, and it is one-shot only.

---

## The eleven requirements

Legend: **Covered** · **Partial** · **Absent** · **Prevented** (the design actively rules it out).

| # | Requirement | Verdict | One-line reason |
|---|---|---|---|
| 1 | Unattended queue for hours, clean stop, kills only its own | **Partial** | Loops and process-tree teardown are excellent; the queue is session-local and dies with the process |
| 2 | Does not own the process; runs GSD/superpowers/custom; must not forbid subagents | **Partial** | Subagents first-class and nestable; but DSH brings its own agent loop, and the only way to run GSD is one-shot Claude Code delegation |
| 3 | Work from local registry or GitHub Issues/ClickUp; statuses, comments, mid-run pickup | **Absent** | One inbound GitHub webhook that creates sessions; no read of a board, no write-back, no queue |
| 4 | Per-provider subscription quota, thresholds, hard/soft/save-resume, wait for reset | **Absent** | Zero quota awareness anywhere; `QUOTA` is only a terminal error code |
| 5 | Several platforms and accounts per role, switchable mid-run, verified before a run | **Covered** | Named provider routes, per-route credentials, live re-resolution per request, write-time validation |
| 6 | Watch context window, compact or hand off at a threshold, guaranteed to happen | **Covered** (except "guaranteed") | Replayable measurement + configurable threshold + automatic compaction; failure explicitly proceeds unchanged |
| 7 | Survives its own death: health check, provider fallback, launch journal, never two orchestrators | **Partial** | The single-owner lock and the event-sourced log are exemplary; no health check, no provider fallback |
| 8 | Interactive terminals or headless per platform; orchestrator answers a session's question | **Partial / Prevented** | Headless is excellent; there is no interactive terminal at all, and a delegated child is forbidden to ask |
| 9 | Config at global/project/run scope, changed DURING a run, next-tick pickup; manual stops | **Partial** | The watched settings document is exactly right; the scopes are wrong and there are no stop commands |
| 10 | Prints nothing unless asked; status from a separate command; verified notification channel | **Partial** | Headless is genuinely quiet; no status command, no notification channel of any kind |
| 11 | Never touches other projects or parallel work; one text file of prohibitions | **Covered**, differently than asked | OS-level sandbox confinement plus a loaded global `AGENTS.md`; stronger than requested, and the opposite of the owner's stated preference |

---

### R1 — Unattended queue for hours, clean stop, kills only what it started

**Verdict: Partial.** Three separate loop mechanisms exist, all session-local.

**What is there (VERIFIED):**

- `packages/goal/goal-round-driver` — continues an active goal round after round while the agent is idle,
  unattended, until the objective completes, the model blocks, or `maxGoalRounds` is exhausted (at which point it
  records a blocker with the stable code `round-limit`). It is **enabled in the shipped base composition**
  (`packages/bundle/base/cordis.patch.yml`, row `goal-round-driver`). Reservation-then-admission with a revision
  fence at `agent/pre-step`, a durability checkpoint (`ctx.sessions.flush()`) before queuing, fail-closed teardown.
- `packages/workflow/tool-ralph` — a fixed fresh-agent loop, `maxRounds` default 256, ceiling 64 in the base
  composition. **Disabled by default** in `packages/bundle/base/cordis.patch.yml` with an inline comment
  explaining why: "completion is a worker self-report, not an independent evaluation."
- `packages/jobs/jobs-local` — background job registry. `JobStatus: running | stopping | completed | killed | failed`,
  `maxConcurrentJobsPerOwner` default 10, owner-fenced by session id, first-wins settlement.
- **Kills only what it started — this part is genuinely solved.** The subprocess seam owns a
  *provider-managed range*, not a pid: `terminate()` runs the provider's documented procedure on that range, and
  `waitForExit()` "waits until the same managed range is empty — not just until the spawned command reports its
  outcome, so surviving work remains observable" (`docs/subsystems/subprocess.md`). Job registry teardown cancels
  live work and *awaits* compliant producers; a throwing teardown cancel force-fails only the record and never
  claims the work stopped (`docs/subsystems/jobs.md`).

**Why it is not the requirement (VERIFIED):**

- `docs/subsystems/schedule.md` is titled **"Session-local Schedule"** and states it in the type system:
  `type ScheduleDeliveryMode = 'session-local'`, with the prose "the original Session must be live: **no external
  notification channel or cold-session scheduler exists**". Minimum recurrence interval is five minutes; there is
  no cron expression.
- `packages/goal/goal-round-driver/README.md`, limitations: "**Same-session execution only** — this package
  deliberately does not spawn a fresh agent, fork a session prefix, or implement Ralph-style independent attempts."
  And: "**Round cap, not resource budget** — token, currency, time, and provider quota policies remain independent."
- Jobs are owned by a live `Agent`; "agent disposal cancels and awaits the job." Nothing outlives the process.

**Gap to the requirement:** a queue of tickets that survives a host restart, that the orchestrator draws from, and
that empties. DSH has no such object. The nearest is `packages/experimental/agent-team`'s task DAG — see R3.

---

### R2 — Does not own the engineering process; must not forbid subagents

**Verdict: Partial, and this is the central architectural tension.**

**The anti-requirement is satisfied (VERIFIED).** Subagents are a first-class seam
(`docs/subsystems/subagent.md`), nesting is allowed, and `maxDepth` is an *optional* per-start cap requiring a
provider capability flag — absent by default, not enforced. `toolFilter`, `persona` and `agentOptions` are
likewise opt-in. Nothing in DSH forbids the in-session delegation GSD and superpowers depend on.

**The positive requirement is not satisfied.** DSH is a peer of Claude Code, not a driver of it. Its own process
is the agent loop (`packages/core/agent-loop`), its own prompt sections, its own tools. Running GSD "inside" DSH
means one of two things:

1. **Re-express GSD as DSH plugins.** `packages/skill` reads skills, `packages/preset/agent-presets` composes
   agents, `packages/interaction/commands` registers `/commands`. A port is possible and large. It also violates
   R1-03 as stated: the orchestrator would then own the process.
2. **Delegate to a real Claude Code session** — and this exists, first-party (VERIFIED):
   `packages/subagent/subagent-claude-code`. Its README is explicit and favourable on the point that matters:
   > "The provider deliberately omits the SDK `settingSources` option, so Claude Code reads the host's normal
   > user, project, and local settings relative to the parent Session cwd."

   So a delegated Claude Code child **does** see the installed GSD plugin, its skills, and the project's
   `CLAUDE.md`. `permissionMode` defaults to `dontAsk`; `bypassPermissions` is available. A sibling
   `packages/subagent/subagent-codex` does the same over Codex's app-server protocol, and
   `packages/subagent/subagent-acp` covers any ACP agent.

**What makes option 2 fall short (VERIFIED, from the provider's own limitations section):**

- "**One fresh query and process per run** — there is no continuation, resume, pooling, progress stream, or
  product-session persistence." A GSD phase that needs three turns cannot have them.
- "**No human interaction path** — `AskUserQuestion` is disabled, permission prompts are denied, MCP elicitation
  is declined, and blocking dialogs fail closed instead of suspending." GSD's discussion and UAT steps die here.
- "**Assistant payload is final text only** — reasoning, intermediate messages, tool traffic, usage, stderr, and
  workspace diffs remain product-local." The orchestrator cannot watch the child work.
- "**Static instance selection** — Profile rows fix provider names, optional models, and tool bindings; calls
  cannot choose or change either a provider or model dynamically."
- "**No wall-clock timeout**."
- Disclosure from the Dev Note: the darwin-arm64 Claude Code payload "packs to about 92 MB and unpacks to about
  325 MB", pinned to Agent SDK 0.3.263.

Also relevant and easy to miss: `packages/hooks/hooks-claude-code` and `packages/hooks/hooks-codex` — DSH
implements *their* hook protocols, so hooks written for Claude Code run against DSH's own loop.

---

### R3 — Work from a local registry or a connected board; statuses, comments, mid-run pickup, watched description

**Verdict: Absent.** This is the largest gap, and it is not close.

**What exists (VERIFIED):**

- `packages/webhook/webhook-github` + `packages/webhook/webhook` — a signed GitHub webhook endpoint that turns a
  delivery into a new root Session. The worked example is real and shipped:
  `apps/cli/config/examples/github-review/github-ready-review-rule.mjs` matches
  `pull_request` / `ready_for_review` and returns a `WorkflowSessionRequest` with a workspace path, agent preset,
  permission preset and prompt. Guide: `docs/user/guide/github-review.md`.
- `packages/todo/tool-todo` — `TodoItem { content, status }`, three states, **no id**: "the list is replaced
  wholesale on every write (last-write-wins), so entries need no stable identity" (`docs/subsystems/todo.md`).
  Session-local.
- `packages/experimental/agent-team` — the one real queue object in the tree. `TeamTaskSnapshot` with `revision`
  (compare-and-set), `blockedBy` edges validated acyclic, `writeScopes` as advisory path prefixes, statuses
  `pending | in_progress | completed | deleted`, a durable mailbox where "an inactive teammate cold-resumes", and
  `waitForChange(caller, timeoutMs, signal)`. It is in `packages/experimental/` and its whole state is folded out
  of **one Lead Session's event log**.

**What is missing, and why the gap is structural (VERIFIED):**

- Nothing reads a board. The webhook is *ingress only*, and the guide says so: "The webhook secret authenticates
  inbound GitHub data only. It grants neither rule code nor the created Agent outbound GitHub access."
- Nothing writes a status or a comment back.
- The runtime is explicitly stateless about deliveries: "The runtime has no queue, retry, deduplication, execution
  status, crash replay, Agent-status listener, or completion result. Repeated delivery may create repeated
  Sessions" (`docs/subsystems/webhook.md`). The response contract is honest to a fault: "`202` means the signature
  and JSON were accepted and rule calls were scheduled in memory. It does not mean this rule matched or that a
  Session was created."
- Nothing watches an active ticket's description for changes (Д8).
- A GitHub or ClickUp MCP server through `packages/mcp/mcp-client` would give the *model* board tools. It gives the
  *orchestrator* nothing, because there is no orchestrator.

---

### R4 — Subscription quota per provider, user thresholds, hard/soft/save-resume, wait for reset

**Verdict: Absent. Verified exhaustively, not by absence of search results.**

`docs/config-catalog.md` is generated from source and is the complete accepted-configuration surface of all 128
configurable packages. Grepping it for `quota|subscription|budget|rate.limit` returns: image pixel budgets,
character budgets for tool-result pruning, thinking-token budgets, a 5000 ms graceful-shutdown budget, tool-call
timeout budgets, and `fileQuotaCleanupBatch` (deleting old harness-owned uploads before one Files-API retry).
**There is no subscription quota, no spend budget, no wall-clock run budget, and no reset-time concept.**

Three corroborating primary statements:

- `packages/llm/llm-pi-ai/README.md`: "terminal provider failures distinguish `QUOTA` from transient
  `RATE_LIMIT`." `QUOTA` is a failure classification, not a meter.
- `packages/llm/llm-retry/README.md`: normal mode retries only `EMPTY_RESPONSE`, `RATE_LIMIT`, `SERVER`,
  `TIMEOUT`, `TRANSPORT` — **`QUOTA` is deliberately not eligible.** Always mode "retries permanent failures —
  authentication, quota, invalid-request, protocol, and unrecoverable context errors continue until success,
  cancellation, or disposal". That is the opposite of waiting for a reset.
- `packages/goal/goal-round-driver/README.md`: "token, currency, time, and provider quota policies remain
  independent."

**The identity note's caution was right, and the conflation it warned about is real:** `token-meter` measures
*context pressure*, not entitlement. They are different problems and DSH solves only the first.

Nothing here reads `/api/oauth/usage` or any equivalent, and there is no hard/soft/save-and-resume vocabulary
anywhere in the tree. This requirement would be built from scratch on top of DSH exactly as it would be built from
scratch on top of nothing.

---

### R5 — Several platforms and accounts, per role, switchable mid-run, verified before a run

**Verdict: Covered.** The strongest native fit, and it is more complete than the identity note's surface read
suggested.

**VERIFIED, from `packages/llm/llm-pi-ai/README.md` and `docs/subsystems/credentials.md`:**

- The whole configuration surface is a `providers` dictionary; each key is a route name a request selects with
  `GenerateOptions.provider`. A route carries its own `apiKeyEnv` credential reference, `baseURL`, `api` wire
  protocol, model catalog, `reasoning` level, image budgets and `retryPolicy`.
- **Switchable mid-run without a restart, verbatim:** "Profiles and credentials are resolved for each request, so
  settings changes take effect on the next request without a restart." And: "a user can add a route, override one
  field of a composition route, or point a route at another proxy, all effective on the next request with no
  restart."
- **Verified before it is used, verbatim:** `SettingsRegisterOptions.validate` exists precisely for this —
  "Throwing here refuses the *write* that produced the value, so a caller learns at `update`/`replace`/`mutate`
  instead of storing something that would silently disable the owner." `dsh-llm-pi-ai` "uses it to refuse a
  provider profile it could not serve at the write that produced it". A section that later fails keeps the
  namespace's last good value and warns rather than stranding a running owner.
- **Credentials are never in the config file:** `apiKeyEnv` is a reference resolved per request through the
  credential seam; `docs/subsystems/credentials.md` states the rule — "consumers re-resolve at each operation and
  must not cache across operations — that per-operation read is what makes a changed credential reach the next
  operation without a restart". OAuth sign-in stores at `llm-pi-ai/<provider id>` and refreshes under a
  cross-process lock ("a token refresh is read-decide-replace under one lock").
- **Per-role assignment exists in two places:** `TeamMemberSnapshot.provider` is a durable per-teammate field
  (`docs/subsystems/agent-team.md`), and each `dsh-tool-subagent` row pins one provider and one `toolName`.
- **One watched file drives it:** see R9 — `settings.yaml` is watched and hot-published.

**Honest limits (VERIFIED):** the user layer can add or override routes but cannot *remove* a composition route;
dict keys cannot be deleted by the user layer; a sign-in flow lives only in the process that started it; a route's
model catalog never refreshes itself.

---

### R6 — Watch the context window, compact or hand off at a threshold, guaranteed to happen

**Verdict: Covered on measurement and threshold. The word "guaranteed" is where it fails, and DSH says so itself.**

**VERIFIED:**

- `packages/llm/token-meter` returns a `TokenMeasurement` carrying `logRevision` — "the number of durable events
  consumed for every field in the measurement" — plus `totalTokens`, `surfaceTokens`, signed `surfaceDeltaTokens`,
  and every priced node in positional order. `baseline.kind === 'usage'` when the last successful provider call
  had the same canonical request envelope; `estimated` otherwise. **The measurement is replayable and attributable
  to an exact log offset**, not scraped from a screen.
- `packages/compaction/compaction-basic` owns policy. Defaults: `thresholdRatio` **0.8** of the routed model's
  context window, `retainRatio` **0.16** kept verbatim, `maxTokens` 8192 for the summary, `compactionRetries` 1,
  `maxOverflowRetries` 1, `auto` true. **Per-route override is a first-class field** — `modelPolicies: [{ provider,
  model, thresholdRatio, retainTokens }]` — which is exactly R1-08's "для всіх сесій, або для окремого провайдера
  по-іншому".
- It fires at the `agent/pre-step` waterfall, i.e. **at a step boundary — structurally the owner's "soft" mode.**
  Manual `/compact` exists via `packages/compaction/command-compact`. Overflow recovery re-runs the failed request.
- The lock design is worth naming: `compaction/start` is appended *first* and `compaction/end` *last*, so
  "releasing the lock last turns a crash mid-operation into a detectable orphaned lock … rather than a
  `compaction/end` that falsely claims compaction finished" (`docs/subsystems/compaction.md`).

**Where it fails the requirement (VERIFIED, `packages/compaction/compaction-basic/README.md`):**

> "**Summarization failure preserves the latest durable surface** — before any replacement, the auto path logs a
> warning and **proceeds with full over-budget history**."

That is the direct negation of R1-08's "повинен бути механізм, який гарантовано робить цю дію". DSH chooses
detectability over guarantee. Also absent: the owner's **hard** mode (stop mid-step, compact, continue) and the
handoff alternative (start a fresh orchestrator instead of compacting). `compactRegion` additionally "requires an
open turn" and throws on a closed session.

**Contrast that makes this matter.** `FIELD-NOTES.md` §3.3 records that the current harness contains no reference
to context, percentages or compaction anywhere in `bin/*.sh`; §1.1–1.4 record that compaction is performed by
typing `/compact` into another session's tty, that it landed in 1 of 3 attempts, and that five instructions typed
into sessions were never delivered at all. DSH replaces that entire class of failure with an in-process call.

---

### R7 — Survives its own death: health check, provider fallback, launch journal, never two orchestrators

**Verdict: Partial — but the one part it covers, it covers better than anything else found.**

**Covered — the single-owner invariant (VERIFIED).** This is the strongest single artifact in the repository.

- `native/system/packages/entry/src/flock.c` + `flock.ts` expose `tryLockExclusive(fd)`: one non-blocking
  `flock(fd, LOCK_EX | LOCK_NB)` off the JS thread. `native/system/docs/flock-contract.md` is a behavior table
  tested against a C oracle that calls the OS directly. The row that matters: **"Holder process exits or is killed
  → Acquisition succeeds after process exit, without a stale-lock timeout."** No heartbeat, no TTL, no guessing.
- `packages/session/session-persistence-jsonl/README.md` states the consumer contract precisely: "**One live
  writer per session** — the write-handle claim excludes a second writer inside the owning backend instance, and a
  kernel lock (non-blocking `flock(2)` on `session.lock`; on Windows a named kernel semaphore derived from that
  path) **excludes every other instance and process**… A crashed holder's lock dies with its process, so its
  session is writable again immediately, while a live-but-wedged holder blocks writers until its process exits."
  It then discloses its own failure modes: advisory flock is unreliable on NFSv3, the Windows semaphore name is
  per login session, and removing the lock file on POSIX forfeits the exclusion.
- Supporting: POSIX materialization uses `link()` "so same-id races fail instead of overwriting a committed log";
  the change token is device + inode + size + nanosecond timestamps, so a rename-swap cannot be mistaken for the
  same log. A second writer gets `SessionAlreadyOwnedError` (`docs/subsystems/persistence.md`).
- **Journal and recovery (VERIFIED).** Everything is event-sourced. A log that crashed mid-turn ends with an open
  `turn/start`; persistence deliberately does **not** repair it, and resume computes `interruptedTurnClosers` —
  missing tool errors, any open `step/end`, and a synthetic `turn/end { reason: { kind: 'interrupted' } }` —
  appending them as an ordinary batch before publishing the Session. `interrupted` is the one `TurnEndReason` no
  loop ever emits, so an interruption is never confusable with a normal end.

**Absent (VERIFIED by exhaustion of the config catalog and package list):**

- **No health check.** Nothing supervises a DSH process from outside it. The only restart policy in the whole
  config surface is `ReconnectConfig` for one MCP server connection.
- **No provider fallback.** `llm-retry` retries the *same* route; there is no next-provider-on-failure. Its own
  limitation note says an always-mode policy "also prevents fallback" without naming any fallback that exists.
  `docs/subsystems/compaction.md` has a `compaction/summary-error` recovery waterfall, which is the closest thing
  to a fallback seam in the tree — and it is for summarization only.
- **No launch journal** in the owner's sense (which run started what, when). Session logs are per-session.

**Contrast:** `FIELD-NOTES.md` §11.6 records an 85-minute self-sustaining loop that "nothing internal detected",
a dead run flagging the same line 1085 times over five days, and a log line reading `NO ONE IS BEING TOLD`. A
kernel lock that dies with its holder is the correct primitive for the first half of that class of failure.

---

### R8 — Interactive terminals or headless per platform; the orchestrator answers a session's question

**Verdict: Partial on headless (excellent), Absent on interactive, Prevented on answering a child's question.**

**Headless — Covered, and it is the best executor seam found anywhere (VERIFIED,
`packages/bundle/headless/README.md`):**

```
dsh --profile headless --json --session-id <id> "task"
```

- One task, final answer on stdout, exit 0 on a completed `turn/end` and 1 on anything else. "It opens no ports
  and leaves nothing running behind."
- `--json` gives newline-delimited events: opens with `session`, closes with `final`, carries `status`, `text`,
  `thinking`, `tool_call`, `tool_result`. Bounding is specified to the byte: 8 KiB per string except the terminal
  `final` which is uncapped, 32 KiB per event line, depth cut at 64.
- `--session-id` **resumes a persisted conversation across invocations**, and the adoption checks are strict:
  it refuses a session recorded in another cwd, one that is a subagent or fork, one under an agent preset this
  profile does not compose, and one already live in this process — "A supervisor therefore cannot silently drive
  someone else's conversation under a different composition; any mismatch fails before the task runs."
- `dsh --profile acp` serves ACP over stdio; `dsh --profile sdk` serves JSON-RPC over stdio.

**Interactive terminal — Absent (VERIFIED).** DSH ships `web`, `headless`, `sdk`, `sdk-minimal`, `acp` and the
Electron `desktop` (`apps/cli/README.md`, `packages/bundle/`). **There is no TUI.** Every `tui` document in the
tree sits under `.agents/notes/archived/` (`2026-07-22-tui-interactive-extension-service`,
`2026-07-27-tui-chat-channel-module-split`, `2026-07-28-consolidated-tui-presentation`). The `dsh tui --resume`
line in the CLI help is explicitly labelled "example, assuming the tui profile is installed". The advertised front
door is a browser at `127.0.0.1:3080`.

There is a PTY subsystem (`docs/subsystems/terminal.md`, `packages/terminal`), but it is a **tool** — persistent
PTY sessions the *model* drives, with `TerminalWaitReason = 'stdin_read' | 'inferred_idle' | 'timeout' |
'session_exit'`. It is not a UI for a human or an orchestrator to attach to.

**Answering a session's question — Prevented for delegated children (VERIFIED,
`docs/subsystems/user-questions.md`):**

> "Runtime ownership, not durable session lineage, decides this boundary: **an owned child has no human answerer
> and would block forever**, while a lineage-bearing session resumed as a new runtime root may ask normally."

`ctx.userQuestions.ask()` throws `DELEGATED_CALLER` when the live agent is owned by another agent, and
`CALLER_NOT_LIVE` when it is not the registry's exact live instance. The Claude Code and Codex providers go
further and disable `AskUserQuestion` outright.

**But the seam to answer it programmatically is there, and it is clean:** `user-questions/request` is an
agent-scoped *waterfall* — "Return an answer to claim the request or call `next()` to delegate." A plugin can
register an answerer for a root agent and reply with structured `AskUserQuestionAnswerItem { id, selected,
custom }` without a human. That is precisely R1-11's "оркестратор може відповідати на ці питання", available for
root sessions and unavailable for owned children.

---

### R9 — Config at global / project / run scope, changed DURING a run, picked up on the next tick; manual stops

**Verdict: Partial. The live-change mechanism is exactly right; the scopes are wrong and the stop commands do
not exist.**

**Covered — the watched control file (VERIFIED, `packages/settings/settings-file/README.md`):**

One YAML document, `$DSH_HOME/settings.yaml`, `watch: true` by default with a 100 ms settle window. The property
list reads like the owner's own R1-07 / Д12 description:

- "users can edit the document directly — changes take effect live"
- writes are read-modify-write under a **cross-process** `<file>.lock` (`wx`-created, exponential backoff, 2 s
  acquisition deadline), committed by atomic rename through a random-suffix temp sibling that never follows a
  planted symlink; file `0600` under a `0700` directory
- **"Boot fails loud, reload keeps last good"** — an invalid document at boot fails plugin load; an invalid
  hand-edit later warns and keeps the last good sections, "so a hand-edit mistake cannot take the process down"
- YAML edits are leaf-level diffs: comments, anchors and formatting survive on untouched nodes
- self-write suppression by content, so the watcher does not react to the provider's own write
- a section owned by a plugin that is not loaded is never dropped
- consumers observe with `SettingsScope.watch(cb)`; invocations run one at a time in commit order; `applies:
  'live' | 'restart'` is a declared UI hint per namespace

Its own honest limit: "**A missed watcher event stays unseen until the next signal** — reads never re-stat the
file." A tick-based orchestrator would re-read rather than rely on the watcher.

**Partial — scopes (VERIFIED).** DSH has two distinct layering systems and neither is global/project/run:

1. *Settings* resolve as schema defaults → composition `base` → the single user section. One document, one
   machine-global home. **No project scope, no run scope.**
2. *Composition* layers as bundle patches in `dsh.profile.bundles` order → the profile's `cordis.patch.yml` →
   `$DSH_HOME/cordis.patch.yml` → `--patch` overlays in argv order (`apps/cli/README.md`). `--patch` is the only
   thing resembling per-run scope, and it is fixed at launch.

**Partial — live pickup (VERIFIED, `packages/boot/hmr/README.md`).** Profile and home patch changes trigger
recomposition through one serialized queue with `awaitWriteFinish: true`. But: "**Headless, SDK and ACP bundles
disable that entry in YAML**". The surface an automation would use is exactly the one without config HMR.

**Absent — manual stop commands.** No `stop-hard`, no `stop-soft`, no `stop-custom`, and nothing in
`docs/subsystems/commands.md` or the config catalog corresponds. The soft/hard vocabulary does not exist in DSH at
all; every boundary it has is structurally soft (`agent/pre-step`, whole-agent idle, step boundaries).

---

### R10 — Prints nothing unless asked; status from a separate command; a verified notification channel

**Verdict: Partial on silence, Absent on both status and notification.**

**Silence (VERIFIED, mixed).** The identity note's "the default front door opens a browser UI" is right for
`dsh web` but wrong for the surface automation would use. `headless` "opens no ports and leaves nothing running
behind"; default-mode stdout carries only the final answer. Two caveats from its own limitations: reasoning deltas
go to stderr by default ("redirection and supervisors may retain substantially more and potentially sensitive
model output"), and there is no pre-token heartbeat.

**Status command — Absent.** There is no `dsh status`. `packages/session-query` + `session-query-sqlite` +
`packages/session/session-stats` would let someone *build* one against the durable logs, and
`packages/experimental/inspector` exists, but nothing ships that answers "what is the run doing right now" from a
second terminal.

**Notification channel — Absent (VERIFIED by exhaustion).** Searching the whole `master` tree for
`notif|telegram|slack|email` returns only an internal session-controller `notifier.ts` and SDK test snapshots.
There is no Telegram, Slack, email, desktop-notification or webhook-**egress** package. The webhook subsystem is
ingress only.

The nearest thing, and it is a genuine near-miss: `packages/session/session-telemetry` +
`session-telemetry-otel` export session events over OpenTelemetry with severity **pre-mapped at capture** "so a
receiver can alert with zero configuration" — `error` for `turn/end` error reasons and tool results whose
`isError` is set, plus operational `agent-error` and `shutdown` records on a separate `ops` channel. That is an
alerting *source*, not a channel to a human, and nothing verifies it works before a run.

---

### R11 — Never touches other projects or parallel work; one text file of prohibitions

**Verdict: Covered — by a mechanism the owner explicitly said he did not want, plus one he did.**

**The prohibitions file — Covered almost literally (VERIFIED,
`packages/context/agent-instructions/src/config.ts`, via `docs/config-catalog.md`):**

```ts
/** Harness home containing the fixed user-global `AGENTS.md`; defaults to `$DSH_HOME` or `~/.dsh`. */
dshHome?: string
/** Directory entries that identify the project root while walking upward from the session cwd. */
projectRootMarkers?: string[]
maxBytes: number                        // UTF-8 cap per rendered batch
maxSourceBytes?: number                 // larger files are ignored
instructionFileCandidates?: string[]    // ordered same-directory project candidates
localInstructionFileCandidates?: string[] // ordered local overlay, loaded after the base files
```

One fixed user-global `AGENTS.md` under the harness home, loaded into every agent's context by the loader rather
than by the model's goodwill, plus project files discovered by walking up from the session cwd, with
per-directory trimmed-content dedup and byte caps. That is R1-15 as specified. (DSH's own repository root carries
`CLAUDE.md -> AGENTS.md` as a symlink.)

**The boundary — Covered, deterministically, against the owner's stated preference (VERIFIED,
`docs/subsystems/sandbox.md`):**

`SandboxMode = 'read-only' | 'workspace-write' | 'danger-full-access'`, enforced by real OS mechanisms —
Linux bwrap/Landlock, macOS Seatbelt, a Windows ACL restricted-token backend (`packages/sandbox/sandbox-local`),
and the same policy over SSH (`packages/ssh/sandbox-ssh`). Policy is resolved **per call**, and
`workspaceRoot` "derives from the calling session's immutable cwd", canonicalized where the files actually exist
so `symlink/..` cannot escape. Two concurrent sessions can run under different boundaries at the same instant.
Enforcement completeness is a *reported fact*: `SandboxEnforcement = 'full' | 'partial'`, with older Landlock ABIs
and the Windows Everyone/hard-link boundaries documented as current partial cases, and "consumers requiring an
absolute boundary must not treat `partial` as `full`."

`packages/interaction/permission-presets` bundles sandbox mode and approval policy into named presets; the
shipped table is `workspace-write` (workspace-write + ask) and `danger-full-access` (danger-full-access + never),
and the reserved names `custom` and `auto` fail at load if configured.

**The tension to record, because it is a decision and not a finding.** R1-16 says: "я не хочу якихось
детерміністського варіанту для цього, тому що він буде дуже складний оверінжиринг, але дуже якісь простий та
надійний варіант". DSH ships the deterministic variant, and the complexity is already paid for and hidden behind
one config word. Whether that counts as the over-engineering he rejected, or as the simple reliable thing he
wanted delivered by someone else, is the owner's call, not mine.

**Two things it still does not do:** it has no concept of the owner's *own parallel work in the same folder*
(`workspace-write` confines to the workspace root — which is exactly where that parallel work lives), and
`packages/workspace` is **not** an isolation mechanism despite its name. Read its README: it is a sidebar project
list — "keep an ordered, persistent list of project directories and the sessions run in each … it is invisible to
models and adds no prompt or request-context cost." The identity note scored it as partial coverage of R11; it
covers none of it.

Also worth correcting from the identity note: `packages/guard` is confirmed a red herring. It holds exactly
`repeat-tool-reminder` and `timeout-policy`.

---

## The four questions

### Could this run the owner's overnight queue TODAY, unmodified?

**No.** Four independent blockers, any one of which is fatal:

1. **There is no queue that outlives a session.** Everything queue-shaped is folded out of one live Session's
   event log, and `schedule` names its own boundary in its type system.
2. **There is no board.** Ingress-only webhooks, no read, no status write, no comment, no mid-run pickup, no
   description watch.
3. **There is no quota awareness at all.** The run would hit the wall and stop, or — in `always` retry mode —
   burn requests against an exhausted subscription indefinitely.
4. **There is no process that supervises anything.** No health check, no fallback, no restart policy, no notion of
   a "run".

Add: no notification channel, no status command, no stop commands, no interactive terminal.

### Could it do so as a component, with the owner's plugin wrapping it?

**Yes, and this is the realistic shape.** There are two clean seams, and they are seams DSH designed on purpose.

**Seam A — DSH as an executor process, driven by the owner's orchestrator (recommended).**

```
orchestrator (owner's plugin)  →  dsh --profile headless --json --session-id <id> "<step>"
```

The contract is unusually good for this: NDJSON events with specified byte bounds, exit 0 iff the turn completed,
no ports, exits on its own, and `--session-id` carries a conversation across invocations. The adoption guard
(same cwd, same preset, not a fork, not already live) means the orchestrator cannot accidentally drive the wrong
session. The owner's plugin keeps the queue, the board, the quota, the notifications and the run identity — all
the things DSH does not have. DSH replaces one tmux pane and gives back a machine-readable stream in exchange.

What the owner gives up at this seam: no interactive terminal to watch or type into (which FIELD-NOTES §1.3
suggests is a feature, not a loss), and per-invocation process startup cost.

**Seam B — DSH as a plugin host, with the orchestrator inside it as a Cordis plugin.** Everything needed is a
registration point: `ctx.settings.register(ns, schema)` for config, `user-questions/request` as a waterfall to
answer sessions programmatically, `ctx.webhookRuntime.register(rule)` for GitHub ingress, `ctx.jobs` for
concurrency, `onJobDone`/`onJobsChanged` for progress, `ctx.subagents` to drive Claude Code and Codex. This buys
more and costs more: it makes the orchestrator's life cycle DSH's life cycle, on an alpha with breaking changes
promised in its own README and no way to file an issue.

**Seam C — DSH's Claude Code provider as a GSD executor.** Technically works; the one-shot, no-resume,
no-question, final-text-only contract makes it unsuitable for a GSD phase as GSD is actually shaped.
`dsh --profile headless` on DSH's own loop is the better executor; a plain `claude` process is the better GSD
executor.

### What does it do better than anything in the landscape survey?

**Durable-state discipline, and it is not close.** Every stateful subsystem in DSH is event-sourced into an
append-only log with an explicit fold, a strict decoder that rejects unknown versions and reused ids, a published
persistence catalog (`docs/persistence-catalog.md`) and dated schema-change records
(`docs/persistence-changes/*.schema.json`). Three specific consequences no scripted orchestrator in the landscape
reproduces:

- **Measurement carries its own provenance.** A `TokenMeasurement` names the `logRevision` it was computed at, so
  the number is replayable rather than sampled off a screen.
- **Crash is a first-class state, not a gap.** `turn/end { reason: 'interrupted' }` is a reason no loop emits, so
  "we crashed here" is a fact in the log rather than an inference from a missing line. An orphaned
  `compaction/start` is a detectable half-finished operation by construction.
- **"Did nothing" cannot read as success.** Job teardown that throws "force-fails only the record **without
  claiming that the work stopped**". Compare `FIELD-NOTES.md` §4.1 — a merge that printed `Already up to date` and
  `Everything up-to-date` while doing nothing — and §11.4 generally.

Secondary, and also genuinely ahead of the field: package documentation that states its own limits as a required
section, and a `packages/runtime-diagnostics/invariants` registry where every workspace package must publish a
`./invariant` companion — and `pnpm run verify-package-invariants` mechanically rejects an empty one that does not
explain, package-specifically, why nothing is checkable.

### What single mechanism is worth stealing, and where does it live?

**The session write lock.** One primitive, ~200 lines plus a C file, that solves R7's hardest clause outright.

- **Primitive:** `native/system/packages/entry/src/flock.c` and `flock.ts` — `tryLockExclusive(fd)`, one
  `flock(fd, LOCK_EX | LOCK_NB)` off the JS thread. Contract and behavior table:
  `native/system/docs/flock-contract.md`, tested against `native/system/test/fixtures/flock-oracle.c`.
- **Consumer:** `packages/session/session-persistence-jsonl/README.md` §"One live writer per session" —
  `session.lock` beside the log, taken at write-open and, for a created session, only immediately before its first
  materializing write; POSIX `link()` materialization so same-id races fail instead of overwriting; device+inode+
  size+ns-timestamp change token so a rename-swap is not mistaken for the same log.

**Why this one and not `token-meter`.** `token-meter` is the more impressive engineering and the identity note was
right to flag it, but it is ~1,200 lines of positional surface pricing wired into DSH's own session model — it
does not port, it would have to be rebuilt. The lock ports as-is: a lock file per run, `flock(LOCK_EX|LOCK_NB)`,
and the rule that the lock dies with its holder and needs no TTL. Against `FIELD-NOTES.md` §11.6 — an 85-minute
loop nothing internal detected, a dead run flagging itself 1085 times over five days — it is the missing piece,
and `flock` is available from `bash` via `flock(1)` on Linux and from Node/Python everywhere, so no native addon
is needed to copy the idea.

**Runners-up, in order:**

1. **The compaction lock ordering** (`docs/subsystems/compaction.md`): append `start` first, `end` last, so a
   crash leaves a detectable orphaned lock instead of a false claim of completion. One line of discipline, and it
   is the general answer to the whole "reported success and did nothing" class in FIELD-NOTES §11.4.
2. **The watched settings document** (`packages/settings/settings-file`): one YAML file, cross-process writer
   lock, atomic rename, leaf-level diffs that preserve comments, self-write suppression by content, boot-fails-loud
   / reload-keeps-last-good. That is Д12's control file and R1-07's account file, already built and already tested.
3. **The headless `--json` contract** (`packages/bundle/headless`): specified byte bounds per string and per line,
   depth cut, `final` uncapped, exit code by turn-end reason. A good template for what the owner's executor should
   emit even when the executor is `claude`.

---

## Comparative verdict

The survey file is missing, so this is a rebuilt minimum, verified directly on 2026-09-19 via `gh`:

| Tool | Stars | What it is | Hits the owner's job where DSH does not |
|---|---:|---|---|
| `razzant/claudexor` | 473 | MIT, TypeScript, v3.12.4, pushed 2026-09-19, **issues open**. "Multi-harness control plane for Claude Code, Codex, Cursor, and OpenCode: quota-aware rotation across multiple Claude/Codex subscriptions" | **R4 and R5 together.** Its own README: "Live subscription-quota tracking — and the opt-in policy that rotates a spent account out of the way on typed vendor limits", plus named **credential profiles** per subscription |
| `gastownhall/gastown` | 18,116 | Multi-agent workspace manager | Cross-session workspace management (R1) |
| `umputun/ralphex` | 1,487 | Extended Ralph loop for autonomous plan execution | An unattended loop as the product, not a tool |
| `Yeachan-Heo/oh-my-claudecode` | 39,251 | Teams-first multi-agent orchestration **for Claude Code** | Runs the owner's engine natively (R2) |

**Answer to "is DSH better than the best of those for this job": no, and not on a close call.** For the two
requirements the owner ranked as make-or-break wiring (R4 quota, R5 accounts per role), a 473-star project already
ships what 229,699-star DSH explicitly defers. DSH wins decisively on the layer *below* the job — durable state,
crash semantics, process containment, measurement provenance — which is why "borrow" is the right verdict and
"adopt" is not.

The owner's stated bar is R1-18: he switches only when something is better **in every aspect**. DSH is not better
in every aspect; it is not even in the same category. Nothing here should move him off building his own.

---

## Governance risk, restated because it survives contact with the source

Confirmed at the API on 2026-09-19: `has_issues: false`, `has_pull_requests: false`, `open_issues_count: 0`.
`CONTRIBUTING.md`, verbatim: "We are sorry that we cannot accept external pull requests at the moment," and "You
may consider this repository an idea, an official showcase, and a source of inspiration, **but not a mandate from
us**." The tree carries a `.gitlab-ci.yml` and merge commits reference head branches in a separate
`deepseek-harness` org; git history begins on the public launch date. `README.md`: "**THERE WILL BE
COMPATIBILITY-BREAKING CHANGES.**" `SAFETY.md`: "experimental developer-preview software … has not undergone a
security audit and must not be treated as secure or production-ready," recommending a disposable VM or container,
and stating plainly that "Sandboxing, approval prompts, and permission controls can reduce risk, but they do not
guarantee isolation."

For software meant to run unattended overnight against the owner's real repositories, on a machine where he also
does his own parallel work: you cannot file a bug, you cannot upstream a fix, you cannot read the PR that broke
you, and the vendor tells you in writing not to treat this as a commitment. **Borrowing a mechanism carries none
of that risk. Depending on the runtime carries all of it.** That asymmetry, more than any capability score above,
is what decides this.

---

## Sources

All read directly on 2026-09-19 at `master@ddefc45`, over `raw.githubusercontent.com` and the GitHub API.

**Repository documentation:** `README.md`, `CONTRIBUTING.md`, `SAFETY.md`, `docs/config-catalog.md` (3,945 lines,
128 packages), `docs/persistence-catalog.md`, full `master` tree listing (13,854 paths).

**Subsystem docs read in full:** `docs/subsystems/{jobs, schedule, goal, workflow, subagent, token-meter,
compaction, settings, scope, user-questions, terminal, shell, webhook, feedback, session-telemetry, workspace,
approval, permission-presets, sandbox, session, persistence, storage, spill, agent-team, credentials, todo,
invariants, boot, core, skills, commands, tools, plan, deliverables, session-query, subprocess}.md`.

**Package sources and contracts:** `packages/subagent/{subagent, subagent-claude-code, subagent-codex,
subagent-acp}/README.md`, `packages/hooks/{hook-protocol, hooks-claude-code}/README.md`,
`packages/workflow/tool-ralph/README.md`, `packages/goal/goal-round-driver/README.md`,
`packages/llm/{llm-pi-ai, llm-retry}/README.md`, `packages/compaction/compaction-basic/README.md`,
`packages/workspace/workspace/README.md`, `packages/settings/settings-file/README.md`,
`packages/jobs/jobs-local/README.md`, `packages/session/session-persistence-jsonl/README.md`,
`packages/bundle/headless/README.md`, `packages/bundle/base/cordis.patch.yml`, `packages/boot/hmr/README.md`,
`packages/guard/timeout-policy/README.md`.

**Native:** `native/system/docs/flock-contract.md`.

**CLI and examples:** `apps/cli/README.md`, `apps/cli/src/args.ts`,
`apps/cli/config/examples/github-review/{cordis.yml, github-ready-review-rule.mjs}`,
`docs/user/guide/github-review.md`.

**Project side:** `plugins/harness/docs/FIELD-NOTES.md` (§1.1–1.4, §3.2–3.3, §4.1–4.4, §11.6, §11.7),
`product/spikes/harness-rebuild/round-1/ANALYSIS-01.md`,
`product/spikes/harness-rebuild/research/adoption/deepseek-harness-identity.md`.

**Landscape (rebuilt, primary):** `gh search repos` and `gh api repos/razzant/claudexor` plus its README,
2026-09-19.
