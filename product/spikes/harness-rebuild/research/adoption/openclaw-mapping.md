# OpenClaw — evaluated against the eleven jobs

**Target:** `openclaw/openclaw` (plus `openclaw/acpx`), identified in `openclaw-identity.md`
**Stage:** full evaluation
**Date:** 2026-09-19
**Method:** shallow clone + raw source reads from `main`, GitHub REST (repo, search/code, search/issues, stats), `gh` issue reads, the project's own docs. Every claim below is tagged VERIFIED (I read the file or the API returned it), CLAIMED (the project asserts it and I did not independently reproduce it), or UNKNOWN.

**Verdict in one line:** **Borrow, do not adopt.** OpenClaw has independently built world-class versions of three things the owner needs — a context-window subsystem, a single-instance guarantee, and a multi-vendor quota reader — and it cannot do the one thing the whole job is named after: drain a queue and stop. The component worth taking is not OpenClaw but its sibling `acpx`.

---

## 0. Blocker carried forward

The comparative context file the task names —
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/context/orchestrator-landscape.md`
— **still does not exist.** The `context/` directory exists and is empty; a `find` across the whole scratchpad returns nothing matching `*landscape*`. VERIFIED, twice.

Question 3 ("what does it do better than anything in the landscape survey") therefore cannot be answered comparatively against Agent Orchestrator, Gas Town, Sortie, Symphony, Claudexor, ralphex or Bernstein. It is answered against the field as the task describes it, and the limit is stated in place.

---

## 1. Scorecard

| # | Requirement | Verdict |
|---|---|---|
| 1 | Unattended queue for hours; clean stop when empty; kills only what it started | **Partial** — real queue, real cleanup, **no terminal condition** |
| 2 | Does not own the process; runs the user's engine; does not forbid in-session subagents | **Covered** — the candidate's strongest structural fit |
| 3 | Local registry **or** connected board; sets statuses and comments; picks up mid-run work; watches the task description | **Partial** — local yes, board **read-only**, description-watch absent |
| 4 | Quota per provider, user thresholds, hard/soft/save-resume, wait for reset, no Claude-shaped assumption | **Partial** — best-in-class sensing, **reactive-only** acting, **no thresholds** |
| 5 | Several platforms and accounts, per role, switchable mid-run through one watched file, verified before a run | **Covered** — better than the owner described, except the pre-run gate |
| 6 | Watch each session's context window; compact or hand off at a user-set threshold; action guaranteed | **Covered-partial** — measures and acts; threshold is engine-computed, not user-set |
| 7 | Survives its own death: health check, provider fallback, launch journal, never two orchestrators | **Covered** — except a watchdog on a *different* subscription |
| 8 | Interactive terminals or headless per platform; orchestrator answers a session's question | **Partial** — headless excellent, **no interactive terminals**, can approve tools but not answer questions |
| 9 | Config at global / project / run scope, changeable during a run; stop-hard / stop-soft / stop-custom | **Partial** — live change is excellent, **scopes and stop verbs absent** |
| 10 | Prints nothing unless asked; status from a separate command; notifications to a configured, verified channel | **Covered** |
| 11 | Never touches other projects or the owner's parallel work in the same folder; one prohibitions file every agent reads | **Partial** — prohibitions file solved *better than asked*, parallel-work boundary not solved |

Nothing is **actively prevented**. That is worth stating: the candidate never forbids a thing the owner needs. It simply has not built four of them.

---

## 2. Requirement by requirement

### R1 — Unattended queue, clean stop when empty, kills only what it started — **Partial**

**The queue exists, and it is serious.** The bundled **Workboard** plugin (disabled by default) is a real work registry, not a toy:

- Statuses `triage → backlog → todo → scheduled → ready → running → review → blocked → done`, agent-assignable, priority + labels. VERIFIED, `docs/plugins/workboard.md` (Card fields).
- Dependency graph: `workboard_link` — *"Children stay `todo` until every parent reaches `done`, then dispatch promotion moves them to `ready`."* VERIFIED. This is exactly R1-05's "dependency-blocked tasks do not start."
- Claim / heartbeat / release with a claim token; other agents' mutations are rejected without it; the token is redacted to `[redacted]` on every read surface and returned exactly once from `workboard_claim`. VERIFIED.
- Per-card `runtime limit`, `retry budget`, rolling failure count, and per-attempt history. VERIFIED. This is R1-Д5's "three identical failures."
- `workboard_protocol_violation` blocks a card when an automated worker stops without calling `workboard_complete` / `workboard_block`. VERIFIED — the candidate's answer to "a finished session is closed by nobody" (FIELD-NOTES 1.6).
- Concurrency: *"Each pass starts **at most 3 workers by default**… A pass starts only one card per owner/agent and skips owners that already have running or review work."* Plus global `agents.defaults.maxConcurrent` and per-lane caps (`main` = `max(8, cpus*4)`, `subagent` = 8). VERIFIED, `docs/concepts/queue.md:19-22`.
- Deterministic session keys per board/card (`agent:<agentId>:subagent:workboard-<boardId>-<cardId>`), so a redispatch returns to the same lane. VERIFIED.

**Unattended for hours: yes, but as a daemon.** `workboard dispatch` is a *pass*, not a loop. Its three entry points are a Control UI action, `openclaw workboard dispatch`, and `/workboard dispatch`. A board may hold an `automationJobId` whose cron schedule is, verbatim, *"the backstop"*, with session events nudging it to run immediately (coalesced 60 s). So "runs for hours" = a cron-driven dispatch pass against a resident Gateway. VERIFIED.

**Kills only what it started: covered, and better than the owner's current plugin.**

- Drain: the Gateway stops accepting new work, then waits for active agent turns and background tasks, default budget 5 minutes, capped at 315 s with 10 s reserved for final chat writes. VERIFIED, `docs/gateway/restart-recovery.md` §"Graceful restarts drain first".
- On Linux the unit *"must use `KillMode=mixed` so the initial stop signal reaches only the Gateway"*; the spawn broker deliberately stays alive while its Gateway connection is alive *"so cleanup can still launch commands and observe child exits."* VERIFIED.
- ACP: *"The acpx plugin cleans up OpenClaw-owned wrapper and adapter process trees after `close`, and reaps stale OpenClaw-owned ACPX orphans during Gateway startup."* VERIFIED, `docs/tools/acp-agents/runbook.md`. Note the qualifier — **OpenClaw-owned**. That is precisely Д3.
- Shutdown tracing: `OPENCLAW_GATEWAY_RESTART_TRACE=1` emits `.begin` per phase and a duration when it settles, so *"an unmatched begin identifies an entered phase that has not settled."* VERIFIED. This is the direct answer to FIELD-NOTES 2.2, "a shell that cannot exit reads as work."

**The gap: nothing terminates.** No primitive, CLI verb, config key or doc sentence describes draining a queue to empty and exiting. The design centre is a resident always-on Gateway that meets you in your chat channels. Д3 — *"No ready work left → finish"* — has no mechanism here. **Not covered.**

---

### R2 — Does not own the process; runs the user's engine; must not forbid in-session subagents — **Covered**

This is where the candidate fits the owner's stated architecture almost exactly.

**It runs other people's harnesses as themselves.** Verbatim, `docs/tools/acp-agents.md`: *"Agent Client Protocol (ACP) sessions let OpenClaw run external coding harnesses (Claude Code, Cursor, Copilot, Droid, OpenClaw ACP, OpenCode, Gemini CLI, and other supported acpx harnesses) through an ACP backend plugin."* VERIFIED. Spawn via `/acp spawn claude` or `sessions_spawn({ runtime: "acp" })`.

`acpx` standalone covers the same ground with `acpx pi|openclaw|codex|claude …` and `acpx --agent '<command>'` for any ACP server. VERIFIED, acpx README.

**In-session subagents are a feature, not a prohibition.** `docs/tools/subagents.md`, `docs/tools/swarm.md` (`maxConcurrent` 8, up to 1000), `docs/concepts/delegate-architecture.md`, `docs/concepts/subagent-yield-handoff.md`. An ACP harness session *is* Claude Code, so Claude Code's own Task tool works inside it. VERIFIED for OpenClaw-native subagents; CLAIMED (by construction) for subagents inside an ACP harness session.

**A fully custom step list exists, twice.**

- **acpx flows** — `defineFlow` from `acpx/flows`, node types `acp` / `action` / `compute` / `decision` / `checkpoint`, topological execution, run state persisted to `~/.acpx/flows/runs/<runId>/` with `0700`/`0600` permissions and atomic snapshot publication, replayable. Explicitly *"experimental, opt-in."* VERIFIED, acpx `docs/flows.md`.
- **Lobster** — separately installed `@openclaw/lobster`, a constrained typed DSL where *"approve/resume is a durable, built-in primitive"* and *"timeouts, output caps, sandbox checks, and allowlists are enforced by the runtime, not by each script."* VERIFIED, `docs/tools/lobster.md`.

**Caveat, honestly stated.** OpenClaw has strong opinions about *its own* process — bootstrap-file injection, memory flush, compaction policy, heartbeat turns. Those bind OpenClaw-native sessions. They do not bind an ACP harness session, which OpenClaw treats as a black box it steers and observes. R1-03's "either an existing process or a fully custom one, no mixing" survives intact on the ACP path.

---

### R3 — Local registry or connected board; statuses and comments; mid-run pickup; description-watching — **Partial**

**Local registry: covered.** Workboard, above. Cards carry notes, comments, links, proof, artifacts, attachments, worker logs, diagnostics, and a 22-value event history (`created`, `moved`, `claimed`, `heartbeat`, `attempt_started`, `proof_added`, `protocol_violation`, `stale`, …). Stored in the Gateway's own SQLite. VERIFIED.

**Connected board: not covered.** The bundled GitHub plugin is verbatim *"public-repository link previews and a **read-only** reader"*, and under Limits: *"The reader is public-only and read-only. Use **Open on GitHub** for private repositories, posting comments, or merging pull requests."* VERIFIED, `docs/plugins/github.md`. Workboard says of itself: *"It is **not** a replacement for GitHub Issues, Linear, Jira, or other team project management systems."* VERIFIED. No ClickUp plugin exists.

**The workaround is real but is a workaround.** `tools.github` gives agents a **managed `gh` identity**: a private `GH_CONFIG_DIR` profile per system or per agent, OAuth device flow or PAT, refreshed before its ~8-hour expiry, with the access token placed in `GH_TOKEN` *"only in the private child environment"* while `GITHUB_TOKEN` is cleared, and *"A missing, tokenless, or insecure profile refuses the local execution before the command starts instead of permitting native-keyring fallback."* VERIFIED, `docs/gateway/config-tools/github-identity.md`. So an agent shelling `gh issue comment` writes to a board under a per-role identity. That satisfies the *outcome* of R1-04 while leaving the *integration* unbuilt — no status-set primitive, no minimum-status readiness check on connect (R1-04 [153]), no tag-based readiness contract.

*(Note for the owner: this is the principled version of the `GH_CONFIG_DIR`-by-cwd routing in his own CLAUDE.md — identity bound at process launch rather than inferred from the working directory.)*

**Mid-run pickup: covered** for the local board. Each dispatch pass re-reads `ready` cards; cards created mid-run are picked up on the next pass. VERIFIED. Д2 satisfied.

**Watching the active task's description for changes: not covered.** Nothing polls a ticket body and reports a diff. The nearest things are `plugin.workboard.changed` invalidations carrying only a store epoch and revision, which the UI uses to re-read; and `/acp steer` for injecting new instructions into a live run. Д8 — *"a cheaper subagent watches the ticket, silent when nothing changed"* — has no mechanism here.

---

### R4 — Quota per provider, thresholds, hard/soft/save-resume, wait for reset — **Partial**

**Sensing is the best I have seen anywhere, and it is not Claude-shaped.**

`docs/concepts/usage-tracking.md`, VERIFIED: it *"Pulls provider usage/quota directly from each provider's usage endpoint. No estimated provider billing"*, normalizes everything to `X% left` *"even when a provider reports consumed quota, remaining quota, or only raw counts"*, and — the line that matters for R1-06's "no binding to Claude's windows" — *"Providers without resettable quota windows show provider summary text instead (for example a balance)."*

Ten provider usage surfaces are implemented with per-provider quirks handled: Anthropic (OAuth, `claude.ai` session-key fallback when the token lacks `user:profile`, model-scoped limits, extra-usage budgets, admin-key org history), OpenAI/Codex, GitHub Copilot, MiniMax (three host aliases; *"MiniMax's raw `usage_percent` fields mean **remaining** quota, so OpenClaw inverts them"*), OpenRouter, DeepSeek, Venice, Xiaomi MiMo, z.ai, ClawRouter. Surfaces: `openclaw status --usage`, `openclaw models status`, Control UI per-window bars *"(5-hour, weekly, model-scoped) with reset times, the provider plan when known (for example `Max (20x)`)"*, and — relevant — *"Claude Code CLI (`claude-cli`) setups reuse the same Anthropic subscription usage."* VERIFIED.

**Acting exists, but it is reactive and per-credential, not threshold-driven and per-run.**

Read the source, not the README:

- `src/agents/auth-profiles/usage.ts` — `isWhamWindowExhausted` fires on `used_percent >= 100`. On exhaustion, `applyWhamCooldownResult` writes `blockedUntil` (the provider's own reset, from `reset_after_seconds` or `reset_at`) and `blockedReason: "subscription_limit"`. VERIFIED, lines ~237-263.
- `src/agents/auth-profiles/usage-state.ts` — scope discipline: *"block only the failing model so fallback models on the same auth profile can still try"* for `rate_limit` / `timeout` / `model_not_found`; `auth` / `billing` / `format` / `server_error` stay profile-wide. VERIFIED.
- `src/agents/model-fallback-cooldown.ts` — `resolveCooldownDecision` returns `skip` (persistent auth issue), `attempt`, or `suspend_session`. A cooled-down primary is probed near its reset: `PROBE_MARGIN_MS = 2 min`, `MIN_PROBE_INTERVAL_MS = 30 s`, and — good engineering — *"Without fallbacks, probe on every open throttle slot: rolling caps can recover before the provider's reported reset, which may be days away (#90702)."* VERIFIED.

So "wait for the reset, then continue" **is** implemented — at the credential layer. R1-06 part 1 is satisfied in substance.

**User-set thresholds: not covered, and the project says so.** Code search for `quotaThreshold`, `usageThreshold`, `stopOnQuota` across the repo returns **0** results each. VERIFIED. And issue **#129327**, *"[Feature]: Proactive quota/usage threshold alerts at 80/85/90/95% before exhaustion"*, is **open** since 2026-08-25, labelled `stale`, `P3`, `clawsweeper:needs-product-decision`. Its problem statement is the owner's exact scenario: *"Weekly usage window ran low overnight (03:05–03:17), producing repeated generic 'Something went wrong' replies with zero diagnostic signal… `/status`-style usage data (`5h X% left`, `Week X% left`) was available internally the whole time but never pushed proactively."* VERIFIED via `gh issue view`.

Note what that issue asks for: **alerts**. Not a stop. The owner needs hard-stop-now / soft-stop-at-boundary / save-and-resume. Neither exists, and neither is proposed.

**R1-06 part 2 (state recorded so a run can be resumed, even by hand): covered by a different subsystem.** TaskFlow persists `flow_runs` in `~/.openclaw/state/openclaw.sqlite` with a revision counter and JSON state that survives gateway restarts; the task ledger records every detached run's lifecycle. VERIFIED, `docs/automation/taskflow.md`.

---

### R5 — Platforms, accounts, per role, switchable mid-run, verified before a run — **Covered**

**Per-role isolation is first-class.** `docs/concepts/multi-agent.md`, VERIFIED: *"Run multiple isolated agents in one Gateway process, each with its own workspace, state directory (`agentDir`), and SQLite-backed session history"* and *"An **agent** is the full per-persona scope: workspace files, auth profiles, model registry, and session store."*

So "orchestrator / watcher / executor" become three agent entries, each with its own:

| Surface | Key |
|---|---|
| Workspace + `AGENTS.md` / `SOUL.md` | `agents.entries.*.workspace` |
| Auth profiles (per-agent, in `<agentDir>/openclaw-agent.sqlite`) | `agents.entries.*.agentDir` |
| Model registry and fallback chain | `agents.entries.*.models` |
| GitHub identity | `agents.entries.*.tools.github.profileId` |
| Skills allowlist (*"explicit entries replace the default, they do not merge"*) | `agents.entries.*.skills` |
| Sandbox and tool policy | `agents.entries.*.sandbox` / `.tools` |

VERIFIED. ~70 provider docs exist; multiple accounts per provider via auth profiles; `auth.order` governs rotation; `docs/concepts/model-failover.md` covers auth-profile rotation then model fallback.

**Switchable mid-run through one watched file: covered, and the implementation is better than mtime.** The Gateway watches `~/.openclaw/openclaw.json`, and `agents`, `models`, `auth.order`, `auth.profiles` are all classified **hot** — the reload table's "Gateway restart needed?" column reads **No**. VERIFIED, `docs/gateway/configuration/hot-reload.md`. Crucially: *"Direct file edits are treated as untrusted until they validate. The watcher waits for editor temp-write/rename churn to settle, reads the final file, and rejects invalid external edits without rewriting `openclaw.json`."* That is the failure mode an mtime watcher walks into.

R1-07's soft/hard change semantics are **not** covered — a hot reload applies to subsequent operations; there is no "apply now, stop current work" variant.

**Verified to work before a run: partial.** `openclaw doctor`, `openclaw doctor --fix`, `openclaw status --deep` (live probe incl. per-account channel probes), `openclaw models status`, `/acp doctor` (backend health, capabilities, actionable fixes), `openclaw config validate`. All exist. None is an enforced pre-run gate, because there is no run to gate.

---

### R6 — Context window watched; compact or hand off at a threshold; guaranteed — **Covered-partial**

**This closes FIELD-NOTES 3.3 outright.** The owner's own plugin has nothing that measures a session's context window. OpenClaw has a live per-turn contract exposing `context.max_tokens`, `context.used_tokens`, `context.pct_used` and `state.compactions`, rendered as a context ring in the composer and a meter in the usage footer. VERIFIED, `docs/concepts/usage-tracking.md` (Contract Paths).

**Acting is thorough.** VERIFIED from `docs/concepts/compaction.md` + `docs/gateway/config-agents/heartbeat-compaction-and-streaming.md` + source:

- Auto-compaction runs before inference when the session nears the limit, and on a provider context-overflow error compacts and retries *"from their recorded results. It keeps the current model and account, preserves the original request, and does not replay completed actions."*
- Tool-call/`toolResult` pairs are kept together across the split point.
- Default `mode: "safeguard"` with a quality guard: *"If no finalized summary passes, compaction stops before writing a transcript entry, keeps the original history, and surfaces the existing recovery outcome."*
- `midTurnPrecheck` checks pressure after tool results, before the next model call.
- `maxActiveTranscriptBytes` byte guard (e.g. `"20mb"`) for sessions where provider-side context looks healthy while persisted history grows.
- Compaction can run on a different, cheaper model (`agents.defaults.compaction.model`, e.g. `ollama/llama3.1:8b`) — Д8's cost principle, applied to compaction.
- A silent memory-flush turn before compacting, optionally on a local model.
- `MAX_OVERFLOW_COMPACTION_ATTEMPTS = 3`, and the reserve is capped: `MAX_COMPACTION_RESERVE_RATIO = 0.25` — *"Caps compaction headroom so prompts retain at least three quarters of the model window."* VERIFIED, `src/agents/agent-compaction-constants.ts`.

**The guarantee R1-08 demands is honest rather than absolute.** *"If required compaction fails, OpenClaw reports that failure and keeps the conversation intact instead of starting over automatically."* It refuses to store known-bad context. That is a better contract than "guaranteed to happen," but it is not the same contract.

**What is missing:**
- **No user-set percentage.** The knobs are `keepRecentTokens` (20 000), `recentTurnsPreserve` (3), `maxActiveTranscriptBytes`, and an engine-computed reserve. "Compact at 80%" is not expressible.
- **No soft/hard modes.** Compaction happens before inference — i.e. always at a turn boundary, always "soft" in R1-08's vocabulary. There is no "stop now, compact, continue."
- **No threshold-driven handoff to a fresh orchestrator.** A context engine *may* return a compacted successor session identity, and `subagent-yield-handoff` transfers completion ownership to a successor turn — but neither is triggered by a context threshold.

---

### R7 — Survives its own death; never two orchestrators — **Covered**

**"Two orchestrators never run at once" is the best-engineered thing in the candidate.** `src/infra/gateway-lock.ts`, VERIFIED by reading it:

`acquireGatewayLock` layers four independent guards:
1. A SQLite `gateway-lifecycle` coordinator, acquired through `acquireWithWait` with `GATEWAY_LIFECYCLE_LOCK_TIMEOUT_MS = 5 * 60_000`, polling 250 ms → 2 s, logging `waiting for gateway-lifecycle ownership held by another OpenClaw process, up to N s`.
2. A gateway owner lease.
3. `tryAcquireExclusiveSqliteCoordinator` on `${lockPath}.sqlite`.
4. The JSON lock file itself, with `staleRecovery: "remove-if-unchanged"` and a payload carrying `pid`, `ownerId` (a fresh `randomUUID()` per acquisition), `createdAt`, `configPath`, `stateDir`, `port`, `role`, and `startTime`.

The stale-owner decision, `resolveGatewayOwnerStatus`, is a **triple identity check**, and its comment names the trap directly:

```
// Process start identity catches PID recycling even when the replacement
// process has the same argv shape.
```

PID alive → process **start time** compared against the payload → argv shape (`isGatewayArgv`, `isOpenClawArgv`, or per-role command match for `agent-embedded` / `sqlite-maintenance` / `skill-workshop-apply`). And when the cmdline reader is unavailable it **fails closed**: *"On win32/darwin/other, conservatively assume 'alive' to preserve single-instance guarantees when wmic/ps is unavailable."* An unreadable lock file is likewise treated as held. VERIFIED.

Roles are distinguished in the error text, so the operator learns *what* holds the lock: `another embedded OpenClaw state writer is active (pid N)` vs `gateway already running (pid N)`.

**Launch journal: covered.** A bounded stability recorder persists fatal exits, shutdown timeouts and restart startup failures under `~/.openclaw/logs/stability/`; `openclaw gateway stability --bundle latest`. Plus the durable task ledger and the `flow_runs` revision counter. VERIFIED.

**Health check: covered in-process.** Three unauthenticated probe pairs (`/health`, `/healthz`, `/readyz`); `openclaw health --verbose`; `openclaw status --deep`; a health monitor that stays out of a channel's own auto-restart backoff ladder until it *"gives up after 10 restart attempts"*, then takes over as last restart owner; liveness diagnostics recording event-loop delay/utilization, CPU-core ratio, and active/waiting/queued session counts. VERIFIED.

**Not covered:** R1-10's *"запускати якогось агента раз в N годин на якійсь іншій підписці"* — an external watchdog on a **different** subscription. Everything here is inside the Gateway process it is watching.

**Recovery of interrupted work is excellent and worth reading in full.** Three complementary detectors, VERIFIED from `docs/gateway/restart-recovery.md`:
- *At turn admission* — the user message, the running mark, and the recovery delivery claim are written **in one SQLite transaction** before any model or hook execution.
- *At shutdown* — every session with an active run is stamped before the run is aborted.
- *At startup* — a scan for sessions *"that still claim to be running but have no live owner in the new process. This catches hard crashes and kills where no shutdown code ran."*

Then: a few seconds after startup each marked session is re-dispatched with a synthetic system message, and *"If a final reply had already been produced but not delivered, its text is included so the agent can deliver it instead of redoing the work."* The loop guard is the part to steal thinking from: **a durable budget of three charged automatic dispatch attempts, retained across gateway restarts**, charged before dispatch, refunded only on explicit pre-acceptance rejection, retained when a post-dispatch result is uncertain — *"After the durable budget is exhausted, the session is tombstoned instead of looping forever."*

---

### R8 — Interactive or headless per platform; orchestrator answers a session's question — **Partial**

**Headless: covered, twice.**
- `acpx` is headless by construction. `--format json` emits NDJSON of raw ACP JSON-RPC, with hard rules: *"No acpx-specific event envelope wrapping ACP messages. No synthetic `type`/`stream`/`eventVersion` keys… What you read on stdout is the same wire-level JSON that would have crossed the ACP transport, in submission order."* `--json-strict` guarantees one message per line on stdout and silences informational stderr. VERIFIED.
- `openclaw agent exec` is *"the recommended headless entry point for CI and coding automation because it owns setup, cleanup, output projection, and process status"*, with a stable JSON envelope and exit codes `0` success / `1` model-or-result error / `2` timeout, default 600 s. VERIFIED, `docs/cli/agent.md`.

**Interactive terminals: not covered** in the sense R1-11 means. OpenClaw has a TUI and a Control UI, but nothing spawns a visible terminal (iTerm, tmux pane) that a human can take over mid-run, and there is no per-platform interactive/headless/hybrid switch. Everything a spawned worker does is observed through the Gateway's own surfaces.

**Orchestrator answering a session's question: partial, and the boundary is drawn precisely.**

What *is* possible, from acpx `docs/permissions.md` (VERIFIED):

```
--permission-policy '{"autoApprove":["read","search"],"escalate":["execute"],"defaultAction":"deny"}'
```
with precedence `autoDeny → autoApprove → escalate → defaultAction → mode`, and:

> *"JSON mode keeps the raw ACP stream and includes structured escalation details, including tool input when supplied by the agent, in the `session/request_permission` response `_meta.acpx.permissionEscalation` object **so an orchestrator can resume with a broader policy**."*

Embedding hosts get `onPermissionRequest` on `startTurn()` / `runTurn()`, per-turn, with an abort signal that fires when the turn finishes, times out, is cancelled, or the connection closes — and *"a late host response cannot approve the action."*

What is **explicitly refused**:

> *"Some agents also encode fixed-choice user questions as permission requests. When acpx recognizes such a question and cannot select an answer explicitly, it cancels the request and fails the prompt with `PERMISSION_PROMPT_UNAVAILABLE` (exit code `5`). **This takes precedence over permission modes, per-tool policies, and host permission callbacks**, including for existing custom launchers."*

So: an orchestrator can approve or deny a *tool*. It cannot answer an `AskUserQuestion`. On the OpenClaw side the same line holds — `ask_user` is *"available only in the main session. Subagents and other non-primary runs do not receive it"*, and answers come from a human on a chat surface.

**Steering a live session is covered, and it beats the owner's current nudge.** `/steer` (alias `/tell`) injects guidance *"at the next supported runtime boundary"*, falls back to sending the message as a normal prompt when the runtime cannot accept steering — *it never drops the text*. `/acp steer --session <key> <text>` targets a specific harness session. `/queue steer|collect|followup|interrupt` sets the default behaviour for inbound messages during an active run. VERIFIED, `docs/tools/steer.md`. Compare FIELD-NOTES 1.3 ("text typed at a session may never arrive") and 1.4 ("the engine's nudge does not submit stranded text").

---

### R9 — Config scope, live change, manual stops — **Partial**

**Live change: covered, and the mechanism is worth studying.** `docs/gateway/configuration/hot-reload.md`, VERIFIED. Reload planning classifies each changed path as `restart` / `hot` / `none`; *"The longest matching config prefix determines the outcome"*; *"a path that matches no rule defaults to a Gateway restart"* (fail-safe); plugin-supplied rules apply only while that plugin is loaded. Mode `hybrid` (default) hot-applies what it can and restarts automatically when it must. `config.set` RPC and `config.schema.lookup` for path-scoped schema reads. `$include` splits config across files.

That is strictly stronger than "re-read a file on each tick": it is schema-gated, per-path, rejects invalid edits without clobbering, and distinguishes "restart the owning subsystem" from "restart the process."

**Scopes: not covered.** One config file at `~/.openclaw/openclaw.json` (or `OPENCLAW_CONFIG_PATH`), with per-agent `agents.entries.*` and per-plugin `plugins.entries.*` as the only layering. There is **no project scope and no run scope**. Д1's model — the six config slots and three levels of `<baseline-marketplace>`, personal beating committed — has no equivalent. (`acpx` alone is closer: global + project JSON with CLI flags taking precedence. VERIFIED, acpx `docs/config.md`.)

**Manual stops: partial.** What exists:

| Intent | Nearest command |
|---|---|
| soft stop | `openclaw gateway restart --safe` — *"preflight active work and schedule one coalesced restart after that work drains… bounded to 5 minutes; when the budget expires the restart is forced"* |
| hard stop | `openclaw gateway restart --force` — skips the drain |
| cancel one unit | `openclaw tasks cancel <lookup>`, `/acp cancel`, Workboard **Stop** |
| cancel a pipeline | `openclaw tasks flow cancel` — sticky intent, persisted across restarts, refuses new children, finalizes once children settle |

There is no `stop-custom`, no single run-level stop verb, and no "the command writes into the file the orchestrator reads every tick" pattern (Д12). But `--safe`/`--force` *is* the soft/hard vocabulary, implemented with a real drain budget.

---

### R10 — Quiet by default; separate status command; configured, verified channel — **Covered**

- **Silence is a first-class value.** Automation delivery, verbatim: *"can deliver output to a chat channel, a webhook, or **nowhere**."* Task notify policies are `silent` / `done_only` / `state_changes`, per task, changeable with `openclaw tasks notify <lookup> <policy>`; **all** automation runs and CLI operations default to `silent`. Compaction notices default off (`notifyUser: false`). The usage footer defaults off. VERIFIED.
- **Status is a separate command.** `openclaw status` / `--all` / `--deep` / `--usage` / `--json`; `openclaw tasks list [--status …]`, `openclaw tasks flow list`, `openclaw tasks audit`; `openclaw workboard list`. Plain `openclaw status` *"stays on the fast read-only path"* — Д11's minimal-token principle, already implemented. VERIFIED.
- **Channels:** WhatsApp, Telegram, Slack, Discord, Google Chat, Signal, iMessage, Matrix, MS Teams, Feishu, Mattermost, plus webhook output. VERIFIED from the docs tree.
- **Verified to work:** `openclaw status --deep` runs per-account channel probes; readiness reports a failing account as unhealthy; automations take a configurable **failure destination** so preflight failures are visible. VERIFIED. Operator-invoked, not an enforced gate — same caveat as R5.
- **Caveat:** the Gateway is a logging daemon. "Prints nothing" is true of its notification surfaces, not of its process output.

---

### R11 — Boundaries; one prohibitions file every agent reads — **Partial**

**The prohibitions file is solved better than the owner asked for.**

`AGENTS.md` (plus `SOUL.md`, `USER.md`, `IDENTITY.md`, `BOOTSTRAP.md`) are auto-created per workspace and injected into the system prompt every turn — `agents.defaults.contextInjection: "always"` (default), `bootstrapMaxChars: 20000`. VERIFIED, `docs/gateway/config-agents/workspace-and-bootstrap.md`.

And then the part that matters: `agents.defaults.compaction.postCompactionSections`, defaulting to **`["Session Startup", "Red Lines"]`**. See §5 below — this is the mechanism to steal.

**Filesystem boundary: covered for what it isolates.**
- `agents.defaults.sandbox.workspaceAccess`: `none` (default — an isolated sandbox workspace under `~/.openclaw/sandboxes`, *"the agent workspace is not exposed"*), `ro` (mounted at `/agent`, write/edit/apply_patch disabled), `rw` (at `/workspace`). Sandbox backends: docker, podman, crabbox, openshell, ssh. VERIFIED.
- acpx: `--cwd` sets *"the session scope and filesystem boundary."* VERIFIED.
- Workboard dispatch: *"Workspace-bound dispatch accepts a directory or Git checkout only when its repository root **exactly matches** the target agent workspace"*, and Workboard *"records that authority when a workspace is assigned and intersects it with the current caller's authority again at dispatch, **so a persisted card cannot widen a later caller's access**."* VERIFIED. That is a genuinely good confused-deputy defence.
- Worktrees exist: `worktreeRoot` config, `src/agents/worktrees/git-lock.ts`. Д4 is expressible.

**The owner's parallel work in the same folder: not covered, and the project concedes it.** Verbatim from `docs/automation/taskflow.md`: *"Optional Workboard claims coordinate cooperating writers through its existing claim/heartbeat/release lifecycle. **Claims apply to cards, not paths or shell processes**; overlapping writers must agree on the same card or use isolated worktrees."*

Nothing here distinguishes a process the run started from a process the owner started in the same checkout. R1-16 — *"він би не мав зупиняти якісь там тести, які не він запускав"* — has no mechanism. Nor is there any resource budget, so FIELD-NOTES 5.1 (the owner's own container killed for memory by the run) would reproduce.

**One more sentence worth the owner's attention**, because it is the candidate warning about his own FIELD-NOTES 4.1 ("a merge reported success and did nothing"):

> *"Proof statuses are worker-reported outcomes, not independent verification. A `passed` entry means the worker **reports** that its command or check succeeded. Consumers that need an independent quality gate should inspect the attached command, URL, or artifact and run their own verifier."*

VERIFIED, `docs/plugins/workboard.md`. The candidate has the same hole and labels it.

---

## 3. The four questions

### Could this run the owner's overnight queue TODAY, unmodified?

**No.** Three hard blockers, in order of severity:

1. **No terminal condition.** The Gateway is a resident daemon. Nothing drains a queue to empty and exits. Д3 has no mechanism, and building one means fighting the architecture's centre of gravity, not filling a gap in it.
2. **No threshold-driven quota stop.** It reacts at 100% exhaustion, per auth profile, by cooling down and failing over. "At 90% of the weekly window, finish this task and start nothing new" is not expressible. Issue **#129327** is the project's own record that even the *alerting* form is unbuilt and undecided.
3. **No board write-back.** The one board it reads is public GitHub, read-only by design. Statuses and comments would be an agent shelling `gh`.

Secondary blockers: no interactive terminals (R8); no project or run config scope (R9); no description-watcher (R3/Д8); no parallel-work boundary (R11).

And the component shaped most like his queue — Workboard — is **disabled by default** and carries open defects on exactly the paths an overnight run would depend on. VERIFIED via `gh`:

| Issue | State | What it breaks |
|---|---|---|
| #122911 | open | *"dead worker run's execution record permanently starves its agent's dispatch lane"* |
| #114724 | open | *"Legacy workboard claims without ownerId permanently lock cards — no release/reclaim/dispatch path"* |
| #141156 | open | *"expired claims still block all non-owner mutations (verified on main); expired-claim sweep in dispatch not in stable release"* |
| #144872 | open | *"cards run as view-only subagents and cannot be continued when dispatched from automation/heartbeat"* |
| #116358 | open | *"dispatch overwrites card agentId with 'workboard-dispatcher'; board orchestration.defaultAssignee is never applied"* |

A permanently-starved dispatch lane and permanently-locked cards are, specifically, run-ending failures for an unattended overnight queue.

---

### Could it do so as a component, with the owner's plugin wrapping it — what is the seam?

**Yes — and the component is `acpx`, not OpenClaw.** This is the finding that justifies the whole evaluation.

**Seam A (recommended): `acpx` as the session layer, orchestrator unchanged.**

`openclaw/acpx` — MIT, 3 263 ★, pushed today, `npm i -g acpx`, Node ≥ 22.13. No Gateway, no daemon, no config takeover, no opinion about process. VERIFIED.

The call shape, from its docs:

```bash
acpx claude sessions ensure --name <ticket-id>            # idempotent for scripts
acpx --format json --json-strict --timeout 1800 \
     claude -s <ticket-id> --cwd <worktree> \
     --permission-policy '{"autoApprove":["read","search"],"escalate":["execute"],"defaultAction":"deny"}' \
     "<the ticket prompt>"
# branch on $?
acpx claude cancel -s <ticket-id>
acpx claude status  -s <ticket-id>
```

What the owner's orchestrator gets, that it does not have today:

| FIELD-NOTES failure | What acpx replaces it with |
|---|---|
| 1.3 "Text typed at a session may never arrive" | A prompt is an argument, not keystrokes; queued when a turn is running |
| 1.4 "The engine's nudge does not submit stranded text" | No nudge exists; `cancel` / `set-mode` / `set` are protocol calls |
| 1.6 "A finished session is closed by nobody" | The process exits, with a code |
| 2.2 "A shell that cannot exit reads as work" | `--timeout` → exit `3`; SIGINT/SIGTERM → exit `130`, cancelled cooperatively first |
| 4.1 "A merge reported success and did nothing" | `action` nodes in a flow, or the caller's own verification — the turn boundary is machine-readable |

The exit-code contract is stable and published: `0` success, `1` agent/protocol/runtime error, `2` CLI usage error, `3` timeout, `4` no session found, `5` permission denied (every request denied, none approved), `130` interrupted. VERIFIED, acpx `docs/exit-codes.md`.

Engine-agnostic by construction: `acpx claude`, `acpx codex`, `acpx pi`, `acpx openclaw`, `acpx --agent '<command>'`. Which is exactly R1-03's "the user configures which engine."

**The honest costs.** acpx is pre-1.0 and says so — *"Treat its CLI and runtime interfaces as evolving."* `--format json` is raw ACP wire traffic, so the orchestrator owns event interpretation (that is a deliberate design rule, not an oversight). Fixed-choice user questions abort the turn with exit `5` (R8). And it is headless only, so R1-11's "interactive sessions, or hybrid" would still be the owner's own layer.

**Seam B (deeper, only if the owner wants the resident model): TaskFlow controller + Workboard.**

The owner's plugin registers as a **managed flow controller**: `createManaged` with a goal and controller id, then drives `setWaiting` / `resume` / `finish` / `fail` / `requestCancel`, each requiring the latest expected revision or getting a conflict. Workboard owns claims, dependency promotion and the dispatch pass; TaskFlow owns durable multi-step state in `flow_runs` across gateway restarts.

The contract's own warning is the reason to be careful: *"Durability covers records, not a JavaScript call stack or automatic scheduling. After restart, the owning controller reloads the flow, checks cancellation and terminal state, reconciles any child outcome, and explicitly resumes from the latest revision. Waiting metadata alone does not register a timer or event listener."* VERIFIED. The owner would still write the resumption logic; he would gain a revision-checked durable store for it.

Price: the Gateway, the single global config file, the daemon lifecycle, the weekly release cadence, and a no-backward-compatibility config policy. That inverts R1-18.

**Seam C (narrowest, zero commitment): `openclaw agent exec`** as one more configurable executor alongside `claude`/`codex` — headless, no Gateway, stable JSON envelope, exit `0`/`1`/`2`. Useful as a fallback provider for R1-10's "fallbacks to other providers must exist," nothing more.

---

### What does it do better than anything in the landscape survey?

**Stated limit first:** the survey file does not exist, so this is not the comparative answer the task asked for. It is what is defensible from primary sources about this candidate.

1. **It measures and manages the context window as a first-class subsystem.** Live `context.pct_used` per turn, compaction that keeps tool-call/result pairs intact, a quality guard that refuses to store a bad summary, a separate cheap compaction model, a byte guard for growing transcripts, and a mid-turn pressure precheck. This is the exact gap FIELD-NOTES 3.3 records in the owner's own plugin — *"nothing in the plugin measures context"* — and the candidate has an answer with config surface, failure semantics and a retry cap.
2. **Its single-instance guarantee is engineered, not asserted.** PID + process start time + argv shape, four independent lock layers, failing closed when process inspection is unavailable. The common pattern in this class of tool is a PID file.
3. **Its quota reader is genuinely multi-vendor and window-shape-agnostic** — ten providers with per-provider quirks handled (MiniMax's inverted `usage_percent`, Anthropic's `user:profile` scope fallback, OpenAI credits that are *"provider credits; OpenClaw does not label them as dollars"*). Most tools in this space read Anthropic's windows and call it quota tracking.
4. **`acpx` is the only agent-agnostic harness driver found in this research with a published exit-code contract and a no-envelope raw-protocol output rule.** Both matter more for an unattended run than any feature.
5. **Interrupted-work recovery with a durable, restart-surviving attempt budget and a tombstone** instead of an unbounded retry loop.
6. **Maintenance velocity**: 4 146 commits in the last week (weekly series `2835, 2427, 2283, 2059, 2802, 3750, 4336, 4146`), 4 501 PRs merged in the last 7 days, weekly calendar releases — `v2026.9.5` published today, `v2026.9.4` on 09-11, plus a rolling `linux-stable` channel. VERIFIED via `stats/participation`, `search/issues`, `releases`.

---

### What single mechanism is worth stealing, and where does it live?

**`src/auto-reply/reply/post-compaction-context.ts` — post-compaction section re-injection.**

After every compaction, OpenClaw re-reads `AGENTS.md` from the workspace, extracts the H2/H3 sections named in `agents.defaults.compaction.postCompactionSections` — **default `["Session Startup", "Red Lines"]`** — and prepends them to the next turn with this prose:

> *"Session was just compacted. The conversation summary above is a hint, NOT a substitute for your startup sequence. Run your Session Startup sequence — read the required files before responding to the user."*

The details are what make it worth copying rather than reinventing:

- Heading extraction is **fenced-code-block aware**, so a `##` inside a code sample never opens a section; it captures until the next heading of the same or higher level.
- It substitutes `YYYY-MM-DD` with the real date — the source comment says why: *"so agents read the correct daily memory files instead of guessing based on training cutoff."*
- The result is bounded (`MAX_CONTEXT_CHARS = 1800`, overridable per agent) with UTF-16-safe truncation.
- Matching is a case-insensitive **multiset** comparison, so the documented default pair can be pinned in any order.
- The prose changes when the sections are custom: it then names the injected sections instead of asserting a "Session Startup" sequence that may not exist.
- Every failure path returns `null` — a missing, oversized or unreadable `AGENTS.md` degrades to no injection, never to an error.

**Why this one, for this owner.** R1-15 settled that the red lines live in **one text file every agent must read**, with *no enforcement machinery in the plugin*. The failure that answer does not anticipate is that **compaction deletes them mid-run**, and FIELD-NOTES §3 shows sessions running long enough for that to happen repeatedly across a 34-hour night. This mechanism is roughly 200 lines, depends on nothing in OpenClaw, and converts "every agent must read the prohibitions file" from a hope at session start into a guarantee renewed at every compaction. It is also the only place in the candidate where the prohibitions file and the context-window machinery meet — which is precisely where the owner's two requirements (6 and 11) meet.

**Runner-up, if a second is wanted:** `src/infra/gateway-lock.ts` — `resolveGatewayOwnerStatus` (≈ lines 213-265) and `shouldReclaimGatewayLock` (≈ 293-320). The PID + process-start-time + argv triple identity, and the deliberate fail-closed default when process inspection is unavailable. R1-10's *"якщо раптом одночасно два якісь оркестратори працюють, то це не окей"* is one PID-reuse away from silently breaking under a naive lock file; this is the cheap, correct version.

---

## 4. Risks, for the record

1. **The maintainers themselves rank this use case as future work.** `VISION.md`, VERIFIED: current priorities are *"Security and safe defaults / Bug fixes and stability / Setup reliability and first-run UX"*; *"Better computer-use and agent harness capabilities"* sits under **Next priorities**. This is a chat-resident personal assistant that grew harness features, not a work-queue runner.
2. **Churn is violent.** ~4 100 commits and ~4 500 merged PRs per week; weekly releases; and `VISION.md` states an explicit no-compatibility policy: *"OpenClaw runtime code reads the current configuration schema only. We do not keep long-lived aliases or compatibility branches."* Building against it means tracking a moving target; pinning means falling behind security fixes in a project that is a documented scam-and-security-attention magnet.
3. **5 115 open issues** (VERIFIED today), against ~1 000 closed per week. The backlog grows.
4. **Governance is opaque.** `LICENSE` reads MIT, copyright "OpenClaw Foundation"; the GitHub API reports `NOASSERTION` because the file appends a pointer to `THIRD_PARTY_NOTICES.md`. `acpx` reports a clean `MIT`. Foundation structure, trademark posture and funding remain UNKNOWN.
5. **Workboard is the load-bearing component for R1/R3 and it is beta-shaped** — disabled by default, with five open issues on dispatch, claims and lane starvation (listed above).
6. **The seam recommended above is pre-1.0 by its own statement.** acpx's interfaces will move. The mitigation is that the surface the owner would depend on — subcommands, exit codes, `--format json` — is small, documented, and explicitly designed for scripts.

---

## 5. Recommendation

**Keep building. Take three things.**

1. **Adopt `acpx` as the session layer** (Seam A). It removes the entire terminal-séance class of failure the 34-hour run documented, costs one npm dependency, and keeps the orchestrator's ownership intact. This is the highest-value, lowest-commitment move in the whole evaluation.
2. **Copy `post-compaction-context.ts`** into the orchestrator's own context handling. ~200 lines; makes the Red Lines file survive compaction.
3. **Copy the lock identity check** from `gateway-lock.ts` — PID + start time + argv, failing closed — before the single-orchestrator invariant is tested by a PID reuse at 04:00.

Do **not** adopt `openclaw/openclaw`. It fails R1-18's bar in four places (R1, R3, R4, R9), and its centre of gravity — a resident gateway that lives in your chat channels — is the opposite of a queue runner that dies cleanly when the work is done.
