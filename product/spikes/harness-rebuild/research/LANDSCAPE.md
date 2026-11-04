# Orchestrator landscape — open-source tools that run fleets of coding agents

**Rebuild note.** This file replaces
`…/scratchpad/context/orchestrator-landscape.md`, which was produced on 2026-09-13, reaped by macOS
before any consumer could read it, and then cited by five consecutive research stages that all had to
proceed without it (`research/platforms/00-field-scan.md`, `research/platforms/kimi.md`,
`research/platforms/glm.md`, `research/clusters/C4-capacity-research.md`,
`research/clusters/C6-liveness-recovery-research.md`, and `research/adoption/ADOPTION-VERDICT.md`,
whose §5 closes by asking for exactly this). It is rebuilt from scratch, in the repo this time. All
repository metadata was re-read live with `gh api` on **2026-09-19**; nothing here is carried over
from the lost file except the tool shortlist itself.

**Evidence tags.** **VERIFIED** = read in source, in a shipped docs file, or in `gh` output on
2026-09-19. **CLAIMED** = the README or marketing page asserts it and nothing was read behind it.
**unknown** = searched and found nothing conclusive. A search that returns *zero* hits is recorded as
VERIFIED absence, and is worth more than a soft yes.

---

## 1. What this category is, and what the job actually needs

The category is **tools that keep a fleet of coding-agent sessions working against a queue, without a
human in the chair**: they take a unit of work, give it an isolated place to run, launch a harness
(Claude Code, Codex, Cursor, OpenCode, Aider) inside it, watch what comes back, and decide what
happens next. It is a young, crowded and *extremely* fast-moving field — of the seventeen live
projects below, sixteen were pushed within the last nine days and ten were pushed on the day this was
written (VERIFIED, `gh api`, 2026-09-19). It is also a field where the headline star counts are a poor guide to fit: the two projects
that match this job's requirements most closely have 187 and 473 stars, and the two largest projects
in the survey (81k and 72k) turn out to be adjacent rather than in-category.

What the owner's job needs is not "run agents in parallel" — nearly everything here does that. It is
the eleven requirements summarised in `research/adoption/ADOPTION-VERDICT.md` §2, reused verbatim here
so the two documents agree:

| # | Requirement |
|---|---|
| 1 | Unattended queue for hours; clean stop when empty; kills only what it started |
| 2 | Does not own the process; runs GSD / superpowers / custom; must not forbid in-session subagents |
| 3 | Local registry **or** connected board; sets statuses and comments; mid-run pickup; watches the description |
| 4 | Quota per provider; user thresholds; hard / soft / save-and-resume; wait for reset; no Claude-shaped assumption |
| 5 | Several platforms and accounts, per role, switchable mid-run through one watched file, verified before a run |
| 6 | Watch each session's context window; compact or hand off at a user-set threshold; **guaranteed** |
| 7 | Survives its own death: health check, provider fallback, launch journal, never two orchestrators |
| 8 | Interactive terminals **or** headless per platform; orchestrator answers a session's own question |
| 9 | Config at global / project / run scope, changeable **during** a run, next-tick pickup; stop-hard / stop-soft / stop-custom |
| 10 | Prints nothing unless asked; status from a separate command; notifications to a configured, verified channel |
| 11 | Never touches other projects **or your parallel work in the same folder**; one prohibitions file every agent reads |

The capability matrix in §3 is an expansion of those eleven into seventeen observable axes, chosen so
that each one can be answered by reading code rather than by reading a pitch.

---

## 2. Identity — who is actually alive

Every row below was re-read with `gh api repos/<owner>/<name>` and `gh api repos/<owner>/<name>/releases`
on **2026-09-19**. Stars, licence, last push and archived status are therefore VERIFIED for all rows.
Positioning lines are the repository's own one-line description unless marked otherwise.

| Tool | Repo | Licence | ★ | Last push | Release cadence | Positioning |
|---|---|---|---|---|---|---|
| Untrivial agent-orchestrator | `Untrivial-ai/agent-orchestrator` (Go) | Apache-2.0 | 12,179 | 2026-09-19 | nightly (`v0.13.1-nightly.202609190928`) | Run and supervise teams of coding agents from planning to merge; any harness, 25+ supported |
| Gas Town | `gastownhall/gastown` (Go) | MIT | 18,117 | 2026-09-18 | slow tags (`v1.2.1` 2026-06-06) on a fast trunk | Multi-agent workspace manager; a tmux "town" of long-lived agent roles driven by a daemon |
| Sortie | `sortie-ai/sortie` (Go) | Apache-2.0 | 187 | 2026-09-17 | `v1.24.1` 2026-09-17, ~weekly minors | Turn tracker tickets into autonomous agent sessions |
| Symphony | `openai/symphony` (Elixir) | Apache-2.0 | 27,285 | 2026-09-15 | `v0.0.3` 2026-09-15 — pre-1.0, spec far ahead of code | Turns project work into isolated, autonomous implementation runs |
| claudexor | `razzant/claudexor` (TypeScript) | MIT | 473 | 2026-09-19 | `v3.12.4` 2026-09-19, multiple releases per week | Multi-harness control plane with quota-aware rotation across several Claude/Codex subscriptions |
| ralphex | `umputun/ralphex` (Go) | MIT | 1,487 | 2026-09-14 | `v1.7.0` 2026-09-07, ~monthly minors | Extended Ralph loop for autonomous AI-driven plan execution |
| Ralph Orchestrator | `mikeyobrien/ralph-orchestrator` (Rust) | MIT | 3,148 | 2026-09-10 | `v2.10.1` 2026-06-23 — releases have gone quiet, trunk has not | An improved implementation of the Ralph Wiggum technique |
| ralph-claude-code | `frankbria/ralph-claude-code` (Shell) | MIT | 9,638 | 2026-09-19 | **no releases and no tags at all** (VERIFIED: both endpoints return 0) | Autonomous AI development loop for Claude Code with "intelligent exit detection" |
| Bernstein | `sipyourdrink-ltd/bernstein` (Python) | Apache-2.0 | 1,200 | 2026-09-19 | `v3.19.2` 2026-09-10, ~weekly | Declarative governance + orchestration for AI agents, producing a replayable record |
| agent-deck | `asheshgoplani/agent-deck` (Go) | MIT | 922 | 2026-09-19 | `v1.16.12` 2026-09-19, several per week | Terminal session manager (TUI) for AI coding agents |
| Claude Squad | `smtg-ai/claude-squad` (Go) | AGPL-3.0 | 8,498 | 2026-08-20 | `v1.0.20` 2026-08-20 — **the slowest-moving project here**, ~2-month gaps | Manage multiple AI terminal agents (tmux + git worktrees) |
| Cyrus | `cyrusagents/cyrus` (TypeScript) | Apache-2.0 | 812 | 2026-09-19 | `v0.2.72` 2026-09-15, ~weekly patches | Claude Code background agent for Linear / Slack / GitHub / GitLab, deployable anywhere |
| Paperclip | `paperclipai/paperclip` (TypeScript) | MIT | 81,043 | 2026-09-19 | `v2026.916.0` 2026-09-16, date-versioned | "The open-source app everyone uses to manage agents at work"; its External Task Protocol makes it a superset of Symphony — see §2.3 |
| Ruflo | `ruvnet/ruflo` (TypeScript) | MIT | 72,829 | 2026-09-19 | `v3.42.4` 2026-09-17, several per week | Swarm/agent-harness framework with memory, federation and RAG |
| Emdash | `generalaction/emdash` (TypeScript) | Apache-2.0 | 5,777 | 2026-09-18 | `v1.2.5` 2026-09-18 plus a canary channel | Open-source Agentic Development Environment; run multiple coding agents in parallel |
| Orca | `stablyai/orca` (TypeScript) | MIT | 72,325 | 2026-09-19 | `v1.4.205` 2026-09-17, near-daily | ADE for working with a fleet of parallel agents; desktop, mobile and remote runtime |
| Vibe Kanban *(added)* | `BloopAI/vibe-kanban` (Rust) | Apache-2.0 | 28,128 | 2026-09-19 | `v0.1.45-20260919085201` 2026-09-19 | Kanban board that dispatches coding agents into isolated attempts — **not on the original list; added, see §2.2** |
| Claude Code native | Anthropic, closed-source CLI | proprietary | n/a | n/a | continuous | Baseline: what you get before installing anything — see §3 row and §4 |

### 2.1 Name resolution, and what was misremembered

Nothing on the shortlist turned out to be dead, but four names did not resolve to what they looked like
and one was ambiguous enough to be worth recording (all VERIFIED via `gh api`, 2026-09-19):

- **"Gas Town"** → `gastownhall/gastown`. `steveyegge/gastown` still works but **redirects**; the
  canonical owner is now the `gastownhall` org.
- **"Cyrus"** → `cyrusagents/cyrus`. `ceedaragents/cyrus` **redirects** here.
- **"Symphony"** → `openai/symphony`, not one of the dozen third-party "symphony" orchestrators that
  dominate a keyword search (`cskwork/oh-my-symphony`, `jvogan/symphony-linear-starter`,
  `anantjain-xyz/symphony-rust`, …). Resolved by code-searching the exact string
  `"Symphony Service Specification"` from the surviving local `symphony-SPEC.md`, which matched
  `openai/symphony → SPEC.md`.
- **"Orca"** → `stablyai/orca`. A keyword search finds only satellites (`lhjnano/orcatui`,
  `orca-cli/orca` at 3 stars, `jiwangyihao/orca-conductor`); the canonical repo was recovered from a
  satellite README's link. It is a 72k-star project that keyword search simply does not surface.
- **"Paperclip"** → `paperclipai/paperclip`. The coding-agent parts people mean when they say
  "Paperclip runs Claude Code" are mostly **third-party plugins** (`mvanhorn/paperclip-plugin-acp`,
  `lacymorrow/paperclip-plugin-agent-usage`), not core. §4 keeps that line sharp.

### 2.2 Added to the shortlist

**`BloopAI/vibe-kanban`** (28,128★, Apache-2.0, Rust, pushed 2026-09-19) was not on the list and
plainly belongs: it is a board-driven dispatcher that runs Claude Code / Codex / others as isolated
"attempts" and is one of the most-used tools in the category.

### 2.3 One structural finding: three of these share a specification

`openai/symphony`'s `SPEC.md` is not only a product — it is becoming the field's reference text, and
two other surveyed projects build on it directly (both VERIFIED by reading their own documents):

- **Sortie** says so in the first line of `docs/architecture.md`: *"This document is derived from the
  [Symphony Service Specification]… Sortie is a concrete Go implementation, not a language-agnostic
  specification."* It then goes further than the spec, adding CI feedback, PR and bot review-comment
  reactions, auto-merge, merge-conflict handling, PR label commands and merge completion — sixteen
  contract sections against Symphony's eighteen, plus 30+ ADRs.
- **Paperclip** dedicates `docs/specs/external-task-protocol.md` §3.3 to the relationship, with a
  concept-by-concept crosswalk (claim → issue checkout + execution lock; per-issue workspace →
  execution workspace/worktree; `WORKFLOW.md` → workflow policy document), a *"Symphony-profile
  conformance"* clause at §9.6 and a section-by-section appendix. It positions itself as the superset:
  *"Where Symphony is intentionally narrow — single repository, coding agents only, one tracker, no
  multi-tenant control plane — this protocol extends it with company scoping, multi-agent routing,
  governance gates, issue documents/work products, and two-way sync policy."*

This matters for the rebuild in two ways. It means Symphony's section numbering is the closest thing
the field has to a shared vocabulary, so writing the harness's own contracts against those section
names costs nothing and buys comparability. And it means Paperclip, which at 81k stars looks like a
chat product from the outside, is in this category by its own specification — the host owns issue
checkout, execution locks, heartbeats, workspace lifecycle and budget enforcement, while connectors
own the provider writes.

### 2.4 Checked and rejected

- **`devflowinc/uzi`** (583★, MIT) — "CLI for running large numbers of coding agents in parallel with
  git worktrees" is an exact category fit, but its last push is **2025-06-04**, over fifteen months
  stale. VERIFIED dead for practical purposes; not carried into the matrix.

---

## 3. Capability matrix

Seventeen axes, split into three tables so the cells stay readable. Cell format is
`value [V|C] (pointer)`. **[V]** = VERIFIED (read in source, in a shipped docs file, or in `gh` / CLI
output on 2026-09-19). **[C]** = CLAIMED (README or repo description only). `unknown` cells carry no
tag and mean *I searched and did not establish it* — they are not "no".

A pointer of the form `0 hits for X` is a real negative result: that pattern was searched across the
repository (or the named file) and returned nothing.

**One methodological warning, recorded because it nearly poisoned this document.** GitHub's code-search
API silently returns `0` for a query using `OR` between terms. An early sweep of
`contextWindow OR context_window OR compact_threshold` returned zero for eight repositories in a row;
re-run term by term, the same repositories returned 24, 51, 10 and 6 hits. Every zero in the tables
below comes from a single-term search or a local `grep`, never from an `OR` query.

### 3A — Running the work

| Tool | Concurrency cap | Worktree isolation | Merge / integration | Terminal condition | Crash recovery | Single-instance safety |
|---|---|---|---|---|---|---|
| **Untrivial AO** | no [V] (only `semaphore := make(chan struct{}, c.workers)`, `backend/internal/service/agent/readiness_coordinator.go:272` — a readiness fan-out bound, not an operator session cap) | yes [V] (152 Go files match `worktree`; `internal/gitdefault`, `internal/workspacewatch`) | partial [C] ("from planning to merge", repo description; not read in source) | unknown | yes [V] (`internal/storage/sqlite` with 70+ migrations, `internal/daemon`, `internal/lifecycle`) | no [V] (`singleton` is a one-row DB key in `storage/sqlite/gen`, not a process lock; no `flock`) |
| **Gas Town** | partial [V] (`d.rigPool.runPerRig(...)` "with bounded concurrency", `internal/daemon/daemon.go:121` — per-rig, not an operator cap) | yes [V] (per-polecat worktrees; `listPolecatWorktrees`, and the daemon auto-commits WIP "in active polecat worktrees to prevent data loss") | unknown | **no** [V] (0 hits for `drainAndExit\|exitWhenIdle\|shutdownWhenEmpty\|queueEmptyExit` in `daemon.go`; resident daemon by construction) | yes [V] (`heartbeat`, `restartTracker` with crash-loop guard + backoff, `FindOrphanedDaemons`/`KillOrphanedDaemons`, `IsShutdownInProgress`) | **yes** [V] (`gofrs/flock` on `daemon/daemon.lock`, non-blocking `TryLock`, plus a PID file with an ownership nonce — `daemon.go:460-500`; the comment names the TOCTOU race it closes) |
| **Sortie** | **yes** [V] (`max_concurrent_agents`, `max_concurrent_agents_by_state[state]`, `worker.max_concurrent_agents_per_host` — `docs/architecture/08-…md` §8.3) | partial [V] (isolated per-issue *workspace directories*, `docs/architecture/09-workspace-management-and-safety.md`; only 5 files mention `worktree`) | **yes** [V] (ADR 0012 auto-merge reaction; architecture §11C `MergePR`/`DeleteBranch` + merge-precondition state machine + token-scope preflight; §11E merge-conflict reaction) | no [V] ("Sortie is a long-running automation service", `docs/architecture.md`; 0 hits for drain/exit-when-idle) | yes [V] (SQLite-backed retry queues and run history "so it survives process restarts"; §14 partial-state recovery on restart) | unknown |
| **Symphony** | yes [V] (SPEC §8 concurrency control; §11.1 "the orchestrator applies … claims, retries, and concurrency after normalization") | yes [V] (SPEC §9 "Workspace Management and Safety" — per-issue workspaces, agent commands run only inside them) | unknown | no [V] (SPEC §1 "long-running automation service that continuously reads work"; 0 hits for drain/exit-when-idle/terminal condition in SPEC.md) | yes [V] (SPEC §14 "Failure Model and Recovery Strategy"; §7 claim states `Unclaimed`/`Claimed`/`Running`/`RetryQueued`/`Released`) | unknown |
| **claudexor** | unknown | unknown | unknown | unknown (resident: `packages/daemon/src/daemon-listen.ts`, `daemon-shutdown-rpc.ts`) | yes [V] (`packages/journal` `DurableJournal` + `packages/event-log`; the interaction store is journal-backed and projects from it) | unknown |
| **ralphex** | no [V] (one plan, sequential; 0 parallel/concurrency in its shipped `llms.txt`) | **yes** [V] (`--worktree`, `--branch=<name>`; `llms.txt` §"run in isolated git worktree") | partial [V] (produces a feature branch; `move_plan_on_completion` commits the archive on it — merge itself is not automated) | **yes** [V] (finishes when the plan's tasks are done and moves it to `docs/plans/completed/`; `review_patience` terminates the review loop after N unchanged rounds) | unknown | unknown |
| **Ralph Orchestrator** | no [V] (waves dispatch one worker per payload, `crates/ralph-cli/src/wave.rs`; no operator cap found) | yes [V] (`crates/ralph-cli/src/presets.rs:52` — a preset that "merges completed parallel loop from worktree back to main branch") | yes [V] (same preset) | **yes** [V] (`ralph.yml` `event_loop.completion_promise: LOOP_COMPLETE`, `max_iterations: 150`, `max_runtime_seconds: 28800`; `default_completion_promise()` in `crates/ralph-core/src/config.rs`) | unknown | unknown |
| **ralph-claude-code** | no [V] (0 hits for parallel/concurrent in `ralph_loop.sh` and `lib/queue_manager.sh`) | **no** [V] (0 files match `worktree`) | partial [V] (`gh_create_pr`, `lib/github_lifecycle.sh:112`) | **yes** [V] (`should_exit_gracefully()` `ralph_loop.sh:906` over `.ralph/.exit_signals`; and `_count_blocking_unchecked` `:219` — unticked `- [ ]` outside `OPTIONAL_SECTIONS` block the plan-complete exit) | partial [V] (state in `.ralph/` files: `.call_count`, `.token_count`, `.last_reset`, `.exit_signals`) | unknown |
| **Bernstein** | unknown | unknown | unknown | unknown | unknown | unknown |
| **agent-deck** | unknown | yes [V] (312 files match `worktree`) | unknown | no [V] (0 hits for `drainAndExit\|exitWhenIdle\|shutdownWhenEmpty\|queueEmptyExit`) | partial [V] (`internal/statedb`, `internal/atomicfile`, `internal/selfheal` engine+policy) | partial [V] (`internal/procowner` — `kill(pid,0)` ownership check; `internal/procfd`; no cross-process orchestrator lock found) |
| **Claude Squad** | **no** [V] (0 hits for `max.?concurrent\|concurrency\|max.?parallel` in the whole repo) | yes [V] (19 files; a git worktree per instance under `session/`) | unknown | no [V] (0 hits for `drainAndExit\|exitWhenIdle\|shutdownWhenEmpty\|queueEmptyExit`; it is a TUI you sit in) | unknown | unknown |
| **Cyrus** | **yes** [V] (`maxConcurrentSessions`, `packages/core/src/config-schemas.ts:550`, enforced in `packages/edge-worker/src/RunnerConcurrency.ts:58`) | yes [V] (151 files match `worktree`; `EdgeWorker.parent-branch.test.ts`) | unknown | unknown (a deployed background worker driven by tracker webhooks) | unknown | unknown |
| **Paperclip** | partial [V] (the host owns "issue checkout, execution locks, heartbeat invocation, and execution workspace lifecycle" — `docs/specs/external-task-protocol.md` §3.4) | yes [V] ("Per-issue workspace → Execution workspace / worktree", §3.3 crosswalk, §9.4) | unknown | unknown | yes [V] ("Retry queued → Host retry/recovery + scheduled wakes", §9.3) | partial [V] (execution locks, §3.4 / §9.2) |
| **Ruflo** | unknown | unknown | unknown | unknown | unknown | unknown |
| **Emdash** | partial [V] (`maxConcurrentRuns` + `DEFAULT_MAX_CONCURRENT_RUNS` in `packages/core/src/runtimes/automations/node/scheduling/scheduler.ts:53,75` — governs the *automations* runtime) | yes [V] (369 files match `worktree`) | unknown | unknown | unknown | unknown |
| **Orca** | unknown | **yes** [V] (~60 dedicated `worktree-*` modules in `src/main/`, incl. `worktree-create-preparation-pool.ts`, `worktree-removal-safety.ts`, `worktree-removal-home-guard.ts`, `worktree-removal-session-partition-fencing.test.ts`, `worktree-retirement-*`, `worktree-lineage-pruning.ts` — the deepest in the field by a wide margin) | unknown | unknown | yes [V] (`src/main/crash-reporting`, `durable-file-write.ts`, and a large `persistence-*` recovery suite incl. `persistence-load-repair-durability.test.ts`) | partial [V] (`src/main/file-transaction-lock.ts`, `in-flight-run-dedupe.ts`) |
| **Vibe Kanban** | **no** [V] (0 hits for `max_concurrent\|semaphore\|concurrency` across `crates/**/*.rs`) | yes [V] (`crates/worktree-manager`, `crates/workspace-manager`) | yes [V] (`crates/git-host`, `crates/review/src/github.rs`) | no [V] (0 hits for `drain_and_exit\|exit_when_idle\|shutdown_when_empty\|queue_empty_exit`; `crates/server` is a resident HTTP server) | partial [V] (`crates/db` with dated SQLite migrations) | unknown |
| **Claude Code native** | **no** [V] (no concurrency flag in `claude --help` or `claude agents --help`, v2.1.278) | **yes** [V] (`-w, --worktree [name]`; `--tmux` "create a tmux session for the worktree"; `claude rm <id>` "delete a background session, and its worktree when that is safe") | no [V] (no merge or PR command in `claude --help`) | **yes** [V] (`-p, --print` "print response and exit"; the session is a process with an exit code) | yes [V] (`-r/--resume`, `-c/--continue`, `claude respawn [id]\|--all`, `claude stop <id>` — "its conversation is kept") | **no** [V] (nothing in `claude --help` or `claude agents --help` prevents two sessions colliding in one checkout) |

### 3B — Money and limits

| Tool | Quota sensing | Quota → action | Account switching | Context measurement / compaction |
|---|---|---|---|---|
| **Untrivial AO** | **yes** [V] (the `conversations` table persists `rate_limit_primary_percent`, `rate_limit_secondary_percent`, `rate_limit_primary_resets_in`, `rate_limit_secondary_resets_in`, `rate_limit_plan` — both windows; plus `internal/service/agent/codex_capacity.go` `codexCapacityCoordinator`) | **no** [V] (those columns are read only by `storage/sqlite/store/conversation_store.go`; `RecordModelReroute` *records the provider answering with a different model*, it does not initiate one; no pause/wait-for-reset path found) | yes [V] (`internal/service/agent/codex_accounts.go`, `codex_account_service.go` — operator-initiated: `CODEX_ACCOUNT_SWITCH_IN_PROGRESS`) | **yes** [V] (`context_used`, `context_window` and `compacted_at` persisted per conversation, `storage/sqlite/gen/conversations.sql.go`) |
| **Gas Town** | yes [V] (`internal/daemon/usage_limit.go` `IsClaudeUsageLimit(pane)` — matches the usage-limit signature in a captured tmux pane) | **yes** [V] (`internal/daemon/quota_dog.go`: a ticker, default 5 min, shelling to `gt quota rotate --json`, which per its own comment handles "scanning for rate-limited sessions, planning account assignments, and executing keychain swaps + session restarts") | **yes** [V] (same path — keychain swaps between accounts; rotation fails benignly on "<2 accounts") | unknown |
| **Sortie** | **no** [V] (all 86 quota/limit hits are *tracker* API limits — `internal/tracker/linear/client.go` `recordRateLimit`, `internal/notify/*/errors.go` HTTP 429; nothing reads a provider subscription window) | partial [V] (not quota, but spend: `agent.max_tokens` cumulative per-issue token ceiling stops a run already in flight, and `agent.max_sessions` blocks re-dispatch — ADR 0013) | unknown | unknown |
| **Symphony** | unknown | unknown | unknown | unknown |
| **claudexor** | **yes** [V] (`QuotaSnapshot` with per-constraint `used_ratio` and a `freshness` field; worst-window headroom across constraints — `packages/orchestrator/src/account-pool.ts`) | **yes** [V] — the most complete in the field. `packages/orchestrator/src/credential-profile-rotation.ts` declares `ProfilePolicy { limit_action: "auto" \| "fail" \| "ask" \| "rotate"; rotation_eligible: string[]; headroom_threshold: number }`, and `auto` resolves *by credential kind* — `rotate` for subscription routes, `fail` for metered API-key or unknown routes | **yes** [V] (named `CredentialProfile` rows ranked by fresh headroom descending, then unknown/stale, then exhausted; `credential_pool_exhausted` is a typed terminal; `credential-cooldown.ts`, `account-resolution.ts`) | yes [V] (`packages/context/*`; `context_window` appears in `packages/schema/src/harness-model.ts` and per-harness parsers) |
| **ralphex** | **yes** [V] (per-executor pattern sets `claude_limit_patterns` / `codex_limit_patterns`, matched against a bounded window of structured CLI diagnostics rather than ordinary assistant text, so a run that *quotes* a limit phrase is not a false positive) | **yes** [V] (`--wait` / `wait_on_limit`: on a limit match it waits the configured duration and retries; without it, limit matches fall through to error behaviour and the run exits) | unknown | unknown |
| **Ralph Orchestrator** | **no** [V] (the only rate-limit token is its *own* HTTP API's `RpcErrorCode::RateLimited` in `crates/ralph-api/src/errors.rs`) | no [V] (same) | unknown | partial [V] (`resolve_context_window_for_backend`, `crates/ralph-core/src/config.rs:1115` — returns a *configured size* (`context_window_tokens`, else 200,000 for claude/pi, else 0), not a measurement of what is used) |
| **ralph-claude-code** | **yes** [V] (`ralph_loop.sh:2412-2435` parses Claude's stream-json `rate_limit_event` for `status:"rejected"` and distinguishes the 5-hour plan limit from the Extra Usage quota, returning `2` for the latter) | **yes** [V] (`ralph_loop.sh:868-902` waits for the reset with a countdown and notifies; also self-imposed counters in `.ralph/.call_count`, `.token_count`, `.last_reset`) | unknown | unknown |
| **Bernstein** | unknown | unknown | unknown | unknown |
| **agent-deck** | **yes** [V] (`internal/quota` with per-provider fetchers `claude.go` and `zai.go`, a `quota.Store` cache, and `agent-deck usage` — "show how much of each provider's subscription quota is left") | **no** [V] (the only importers of `internal/quota` are `cmd/agent-deck/usage_cmd.go`, `hook_handler.go`, `internal/session/account_usage.go` and `claude_statusline.go` — display and hooks, never dispatch) | partial [V] (`internal/fleet/authgate.go`, `authcred.go`, `internal/credrefresh`; `system_cmd_accounts`) | **yes** [V] — the best measurement in the field. `internal/ctxinspect` reconstructs everything occupying the window with two-axis provenance (`TextProv` for the bytes, `TokenProv` for the number) under the stated rule *"a wrong token number is worse than no token number"*; and `internal/ui/clear_on_compact.go` acts on it at `clearOnCompactThreshold = 80.0` (`internal/ui/home.go:125-127`), sending `/clear` before Claude's own auto-compact at ~95-98%. The threshold is a Go constant, **not** user configuration |
| **Claude Squad** | **no** [V] (0 hits for `quota\|rate.?limit\|usage limit\|429` in the whole repo) | no [V] (same) | unknown | **no** [V] (0 hits for `context.?window\|compact`) |
| **Cyrus** | **yes** [V] (consumes Codex's `account/rateLimits/updated` — `primary` 300-minute and `secondary` 10,080-minute windows with `usedPercent` and `resetsAt` — and Claude's `SDKRateLimitEvent`) | **no** [V] (`handleRateLimitEvent`, `packages/edge-worker/src/AgentSessionManager.ts:651-671`, calls `log.warn` / `log.info` and nothing else; the trailing comment says `"allowed"` is a no-op "provides no actionable information") | unknown | unknown |
| **Paperclip** | unknown (a third-party plugin, `lacymorrow/paperclip-plugin-agent-usage`, advertises it — that is a plugin, not core) | partial [V] (the host owns "Budget, approval, blocker, and execution-policy enforcement", §3.4 — spend and policy, not a subscription window) | unknown | unknown |
| **Ruflo** | unknown | unknown | unknown | unknown |
| **Emdash** | **no** [V] (the only usage-limit token in `apps/` + `packages/` is Linear's `UsageLimitExceededLinearError`) | no [V] (same) | unknown | unknown |
| **Orca** | **yes** [V] — the widest sensing anywhere. `src/main/rate-limits/` carries per-vendor fetchers for Claude (OAuth + CLI + PTY-parser fallback chain: `claude-oauth-usage-request.ts`, `claude-cli-usage-fetch.ts`, `claude-pty-usage-parser.ts`, `claude-usage-window.ts`), Codex (`codex-pty-rate-limit-probe.ts`, `codex-rpc-rate-limit-probe.ts`, `codex-rate-limit-window-classification.ts`), plus Gemini, Grok, Kimi, MiniMax, OpenCode and Antigravity | **no** [V] (`account-runtime-target-sync.ts` decides *which runtime to read quota from*, not what to do when spent; `src/main/automations/` holds `run-usage-collection.ts` — collection — plus probe schedulers and a drift report, and no limit-gated scheduling) | **yes** [V] (`src/main/claude-accounts/` with `claude-account-selection.ts`, `keychain.ts`, `oauth-refresh.ts`, `runtime-auth-service.ts` and a dedicated `runtime-auth-service-account-switching.test.ts`; also `codex-accounts/`, `grok-accounts/`) | unknown |
| **Vibe Kanban** | **no** [V] (14 files match quota/limit; none reads a subscription window) | no [V] | unknown | partial [V] (`model_context_window: u32` in `crates/executors/src/logs/mod.rs:111`; `auto_compact: bool` + `setup_compaction_env()` in `crates/executors/src/executors/opencode.rs:60,798` — a pass-through toggle for one executor, no orchestrator-side threshold) |
| **Claude Code native** | **no** [V] (nothing in `claude --help` v2.1.278 exposes subscription quota; the only budget control is `--max-budget-usd`, and it is API-spend, `--print`-only) | no [V] (same) | partial [V] (`claude auth`, `claude setup-token`; no multi-account switch command in `--help`) | **yes** [V] (`--autocompact <auto\|tokens>` — "auto-compact window size (auto, or …)": a user-settable threshold, expressed in tokens rather than percent) |

### 3C — Work intake, verification and people

| Tool | Board ingest | Board write-back | Independent verification | Stall / no-progress | Human escalation | Config scopes | Notifications |
|---|---|---|---|---|---|---|---|
| **Untrivial AO** | unknown | unknown | **yes** [V] (`internal/autoreview/coordinator.go`, `internal/review`, `internal/reviewgateway`; ADR 0002 "secure interactive reviewer gateway") | partial [V] (`internal/processalive`, `internal/presence`, `internal/observe`) | **yes** [V] (`internal/sessionguard/guard.go` — see §4) | unknown | yes [V] (`internal/notify/hub.go`, `manager.go`, `enrich.go`, `internal/push`) |
| **Gas Town** | yes [V] (a "beads" issue store per rig; `d.beadsStores`, `SearchIssues`, `hasActiveWork()` queries `in_progress`) | partial [V] (`isBeadClosed`, `hasAssignedOpenWork` — reads; writes not confirmed) | partial [V] ("witness" and "refinery" patrol roles per rig, `ensureWitnessesRunning`, `ensureRefineriesRunning`) | **yes** [V] (`checkDeaconHeartbeat` + `restartStuckDeacon` with a crash-loop guard and backoff — see §4) | yes [V] (`notifySlack(channel, priority, message)` via `bin/gt-notify`, used for "crash loop detected — manual intervention required") | partial [V] (`daemon.json` patrol config + a loaded operational config; per-rig filters) | yes [V] (same `gt-notify`, with `--channel` and `--priority`) |
| **Sortie** | **yes** [V] (`fetch_issues_by_states` / `fetch_issues_by_ids`, Jira and Linear adapters under `internal/tracker/`) | **yes** [V] (`TrackerAdapter.TransitionIssue`; the orchestrator "writes tracker state at exactly three configured points, each one reporting an event it observed" — `docs/architecture.md`; ADR 0007, ADR 0017) | **yes** [V] (ADR 0021 "run self-review before ending on the completion signal"; §11A CI feedback contract; §11B/11D PR and bot review-comment feedback) | **yes** [V] — the sharpest treatment anywhere. ADR 0020 withholds the handoff transition when absence of work is *observed*, configured by `tracker.handoff_evidence: observed \| strict \| off`, with `agent.max_consecutive_absences` parking an issue after a ceiling (ADR 0027) | **yes** [V] (ADR 0014 `notify_operator` as an adapter *family*; ADR 0022 "release a parked issue on a human gesture"; ADR 0025 — see §4) | partial [V] (documented precedence: defaults → YAML → curated `SORTIE_*` env → `.env`; `WORKFLOW.md` is watched and reloaded live, with a documented list of keys that are *not* rebuilt on reload — §6.2) | **yes** [V] (adapter family; Slack and webhook implementations under `internal/notify/`) |
| **Symphony** | **yes** [V] (SPEC §11.1 required adapter operations; and §11.1 "the refresh operation returns full normalized snapshots, not only state strings, because label, assignment, routing … can change while a run is active") | **no, deliberately** [V] (SPEC §11: *"a portable read kernel for scheduling … Do not add generic comment/state/attachment CRUD merely to make providers look alike"*; §1: ticket writes "are typically performed by the coding agent through provider-native tools") | unknown | unknown | unknown | yes [V] (SPEC §6 Configuration Specification; policy lives in an in-repo `WORKFLOW.md`) | unknown |
| **claudexor** | unknown | unknown | yes [V] (`packages/review`, `packages/arbitration`, `packages/canary`; `candidateReview.ts`, `contract-gates.ts`, `council-input.ts` in the orchestrator) | unknown | **yes** [V] (`packages/daemon/src/interactions.ts` — see §4) | unknown | yes [V] (`packages/delivery`) |
| **ralphex** | no [V] (input is a Markdown plan file, not a tracker) | no [V] | **yes** [V] (an external-review loop: Codex reviews Claude's work, with `review_patience` stalemate detection after N unchanged rounds) | **yes** [V] (`--idle-timeout` / `idle_timeout` kills an executor session when no output arrives for a duration, resetting on each output line — explicitly "for detecting hung sessions that completed work but didn't exit") | partial [V] (Ctrl+\ / SIGQUIT pauses in the task phase and prompts, letting you edit the plan mid-run; not remote) | **yes** [V] (global `~/.config/ralphex`, overridable by `RALPHEX_CONFIG_DIR`, plus a per-project `.ralphex/` created by `ralphex --init`) | **yes** [V] (`notify_*` config fields: `telegram`, `email`, `slack`, `webhook` or `custom` script, **disabled by default**) |
| **Ralph Orchestrator** | unknown | unknown | **yes** [V] (`backpressure.gates` in `ralph.yml` — `cargo fmt --check`, `clippy -D warnings`, `cargo test --all`, each with an `on_fail` message fed back to the agent) | unknown | yes [V] (`crates/ralph-telegram` — "Telegram bot for human-in-the-loop") | partial [V] (per-backend preset files `ralph.yml`, `ralph.qa.yml`, `ralph.reviewer.yml`, …) | yes [V] (same Telegram crate) |
| **ralph-claude-code** | **yes** [V] (`lib/queue_manager.sh`: `add_to_queue`, `sort_queue_by_priority`, `parse_issue_dependencies`, `is_dependency_satisfied`, `validate_dependencies`, `get_next_issue` — a real dependency-aware priority queue) | **yes** [V] (`lib/github_lifecycle.sh`: `gh_issue_comment`, `gh_close_issue`, `gh_add_labels`, `gh_create_pr`, `lifecycle_post_progress`, `lifecycle_on_completion`) | partial [V] (`lib/response_analyzer.sh`, `lib/circuit_breaker.sh`; gates are heuristics over the agent's own output, not a second agent) | partial [V] (exit reason `test_saturation` after `MAX_CONSECUTIVE_TEST_LOOPS`; `lib/timeout_utils.sh`) | partial [V] (`send_notification`; exit reason `permission_denied` halts so the user can fix `ALLOWED_TOOLS` in `.ralphrc`) | partial [V] (`.ralphrc` per project) | yes [V] (`send_notification`, used on rate limit and on API limit) |
| **Bernstein** | unknown | unknown | unknown | unknown | unknown | unknown | unknown |
| **agent-deck** | partial [V] (`conductor/gh-watcher`) | unknown | unknown | partial [V] (`internal/sessionstatus`, `internal/health`, `internal/selfheal` with `policy.go`/`predicate.go`/`candidate.go`; `conductor/HEARTBEAT_RULES.md`) | yes [V] (`internal/desknotify`, `internal/feedback`) | partial [V] (`--profile`, `internal/profile`) | yes [V] (`internal/desknotify`) |
| **Claude Squad** | no [V] (0 hits for issue/tracker ingest) | no [V] | unknown | partial [V] (`HasUpdated()` in `session/tmux/tmux.go:246` — SHA-256 of the captured pane compared tick to tick; unchanged hash = no progress) | partial [V] (same function returns `hasPrompt` by matching per-program literals: `"No, and tell Claude what to do differently"` for Claude, `"(Y)es/(N)o/(D)on't ask again"` for Aider, `"Yes, allow once"` for Gemini — it detects the question but a human must answer it) | unknown | unknown |
| **Cyrus** | **yes** [V] (`packages/core/src/issue-tracker/IIssueTrackerService.ts` — `fetchIssue`, `fetchIssueChildren`, `fetchIssueAttachments`, `fetchComments`; Linear adapter plus a CLI adapter and an RPC server) | **yes** [V] (same interface: `updateIssue(issueId, updates)`, `createComment`; `packages/linear-event-transport/src/LinearIssueTrackerService.ts`) | unknown | unknown | partial [C] (Slack is in the repo description; not read) | partial [V] (`packages/edge-worker/src/ConfigManager.ts` with a named override list) | unknown |
| **Paperclip** | **yes** [V] (`docs/specs/external-task-protocol.md` §5.1 REQUIRED Task Source Adapter operations; Linear, Jira, Asana, Notion, Trello, GitHub Issues named) | **yes** [V] (§5.2 OPTIONAL write operations behind a capability declaration; §10.1 Outbound Write Engine; §3.4 "Connectors MUST own … all provider writes (comments, transitions, fields, links)") | unknown | partial [V] ("Running map / live session → Heartbeat runs + issue liveness state", §9.3) | unknown | yes [V] (§9.5 workflow policy document, Symphony's `WORKFLOW.md` mapped onto a host primitive) | unknown |
| **Ruflo** | unknown | unknown | unknown | unknown | unknown | unknown | unknown |
| **Emdash** | **yes** [V] — the widest ingest in the field: `packages/plugins/src/issues/impl/` ships **twelve** trackers (asana, featurebase, forgejo, github, gitlab, jira, linear, monday, notion, plain, plane, trello) | **no** [V] (the capability is read-only: the GitHub implementation exports exactly `listIssues` and `searchIssues`, `packages/plugins/src/issues/impl/github/index.ts:14,43`) | unknown | unknown | unknown | unknown | unknown |
| **Orca** | yes [V] (`src/main/` carries `github/`, `gitlab/`, `jira/`, `linear/`, `azure-devops/`, `bitbucket/`, `gitea/`, plus `issue-command-file.ts` and `hooks-issue-command.test.ts`) | unknown | unknown | partial [V] (`src/main/hang-watchdog/` — but this watches the Electron **main thread**, `main-thread-hang-watchdog.ts`, not an agent session's progress) | yes [V] (`src/main/notifications/`) | partial [V] (`src/main/orca-profiles/`, `effective-hook-config.ts`, `hooks-orca-yaml-parsing.test.ts`) | yes [V] (`src/main/notifications/`, `src/main/tray`) |
| **Vibe Kanban** | partial [V] (its board is its **own** SQLite DB plus a first-party remote service at `/api/remote/issues`, `crates/server/src/routes/remote/issues.rs`; no external-tracker adapter found) | no [V] (same — writes go to its own store; `crates/git-host` opens PRs) | yes [V] (`crates/review`, incl. `review/src/github.rs`) | unknown | unknown | unknown | unknown |
| **Claude Code native** | **no** [V] (no issue/tracker command in `claude --help`) | no [V] | partial [V] (`claude ultrareview [target]` — "run a cloud-hosted multi-agent code review of the current branch (or a PR number / base branch) and print the findings") | no [V] (nothing in `--help` watches a session for progress) | partial [V] (Notification hooks exist; but no command lets an outside process answer a headless session's question) | yes [V] (`--settings`, `--add-dir`, `--agents`, `--plugin-dir`; `claude doctor` "reads settings files in the current directory") | partial [V] (`claude agents --json` "print active sessions … as a JSON array and exit (for scripting; does not require a TTY)" is a real quiet status surface) |

---

## 4. Mechanisms worth copying

Only entries where something is implemented *well enough to steal*. Everything here is VERIFIED — read
in the file named.

### Gas Town — telling a quota pause apart from a crash

`gastownhall/gastown` → `internal/daemon/daemon.go`, `restartStuckDeacon()` (and
`internal/daemon/usage_limit.go`, `internal/daemon/quota_dog.go`)

The best single idea in the survey, and it is eleven lines. A session sitting at a usage-limit prompt
has a stale heartbeat, which from outside is *indistinguishable* from a crash — and the comment says
exactly that:

> *"Distinguish a usage-limit pause from a true crash. If Claude is sitting at a rate-limit prompt the
> heartbeat will go stale, looking identical to a crash — but killing and respawning won't help (the new
> session hits the same limit) and the repeated kills burn the crash-loop budget. Detect the rate-limit
> signature in the pane and let quota_dog handle account rotation instead."*

Three things to take: capturing the pane to disambiguate before acting; `restartTracker.RecordPause()`,
which records the event *without* spending the crash-loop budget; and the crash-loop guard that stops
restarting and escalates to Slack instead (`"Deacon crash loop detected — manual intervention
required"`). The rotation itself is a deliberately dumb ticker — `runQuotaDog()` shells out to
`gt quota rotate --json` and logs; the comment calls this the daemon's *"dumb scheduler" principle*:
the daemon schedules, existing commands do the work.

### Gas Town — the stop verbs, already built

`gastownhall/gastown` → `internal/estop/estop.go`, `cmd/.../estop.go`

A sentinel file `ESTOP` at the town root; `IsActive()` is an `os.Stat`; the file's first field is
`manual` or `auto` and it carries a timestamp and a reason. `gt estop` freezes every agent session with
`SIGTSTP` via process-group signalling and `gt thaw` sends `SIGCONT` and then *nudges* every thawed
session so it notices; both take an optional rig filter. The carve-out is the part to copy verbatim:
**the Mayor (the coordinator) is exempt, so it survives to coordinate recovery.** That is stop-hard plus
an orchestrator-exempt carve-out, in one sentinel file.

### claudexor — a quota policy with the right verbs

`razzant/claudexor` → `packages/orchestrator/src/credential-profile-rotation.ts`,
`packages/orchestrator/src/account-pool.ts`, `credential-cooldown.ts`

```ts
export interface ProfilePolicy {
  limit_action: "auto" | "fail" | "ask" | "rotate";
  rotation_eligible: string[];
  headroom_threshold: number;
}
```

`auto` resolves *by credential kind*: `rotate` for a subscription route, `fail` for a metered API key or
an unresolved route — so exhausting a subscription never silently starts spending money. The pool
ranking in `account-pool.ts` adds the rule everyone else gets wrong:

> *"Ranking (D3 freshness preserved — **stale quota never authorizes routing**): 1. rows with FRESH
> model-applicable quota evidence and headroom below the exhaustion bound, by known headroom DESCENDING;
> 2. rows with unknown/stale quota (eligible, but never ranked as known headroom); 3. exhausted rows —
> never selected; they only count toward 'the pool is exhausted'."*

Headroom is the **worst** window, not the average: `freshModelHeadroom()` walks every constraint on every
fresh snapshot and keeps the minimum of `1 - used_ratio`. And running out is a typed terminal,
`credential_pool_exhausted`, not an error.

### claudexor — a question as a durable pending state, not a terminal one

`razzant/claudexor` → `packages/daemon/src/interactions.ts`, `packages/cli/src/interaction-prompt.ts`

A journal-backed `InteractionStore` holding `ControlPendingInteraction` rows keyed by
`runId`/`taskId`/`attemptId`/`harnessId`, each with `requestedAt` and a nullable `timeoutAt`, resolved by
one of four terminals: `answered | timeout | run_terminal | interrupted`; answers arrive as an
`InteractionAnswerSet` whose delivery reports `delivered | not_found | already_resolved | rejected`.
This is the only implementation found of "the orchestrator answers a session's own question", and it is
worth reading before writing your own, because the four terminals and the four delivery statuses are
exactly the states that turn out to matter.

### Sortie — deciding a run produced nothing, and refusing to lie about it

`sortie-ai/sortie` → `docs/decisions/0020-withhold-handoff-on-observed-absence-of-work.md`,
config key `tracker.handoff_evidence: observed | strict | off`

The problem is stated better here than anywhere else: the handoff transition *"asserts something about a
run's output, and the test applied to it described only the run's exit."* A worker that exited cleanly
having produced nothing took the same path as one that did the work, and the failure was *"silent in
every channel an operator watches."* Two design rules to take:

- **The two errors are not symmetric.** Advancing an empty issue moves work in a system you do not own,
  removes it from the queue you do own, and puts it in front of a person. Withholding leaves it where it
  was, in a queue you keep watching, with the withholding recorded. *"The first error is silent and
  leaves the system; the second is visible and stays inside it."*
- **Absence of evidence is not evidence of absence** — hence three values, not a boolean: `observed`
  withholds only on positively observed emptiness, `strict` also withholds an undeterminable verdict,
  `off` restores the old behaviour. `agent.max_consecutive_absences` (ADR 0027) then parks the issue.

### Sortie — a question is a terminal outcome, centrally

`sortie-ai/sortie` → `docs/decisions/0025-refuse-agent-requests-only-a-human-could-answer.md`

The opposite posture to claudexor's, argued equally well: *"Consent on a person's behalf is outside the
orchestrator's authority. An unattended run contains no one who can grant permission."* A permission
request is refused in a form that lets the agent continue another way; a genuine request for human input
**ends the attempt immediately with a dedicated non-retryable outcome**. The driver worth copying is
about retry budgets: where all three of "needs a person", "failed" and "produced nothing" arrive as one
generic timeout, *"the retry classification that follows sends the attempt back into the wait it just
left"* — a bounded budget draining into a state no retry can change. And the rule that it lives in the
shared layer, not per adapter, because *"a rule replicated per adapter is a rule a new adapter can
omit, and omission here is silent."*

### Untrivial AO — never answer a dialog on the user's behalf

`Untrivial-ai/agent-orchestrator` → `backend/internal/sessionguard/guard.go`

Every path that writes bytes into a live agent pane funnels through one guard whose invariant is:
re-read the session immediately before writing, and refuse when the paste could land somewhere only the
user may act. The reasoning is specific: *"The runtime appends Enter after every paste, so a write into
a session paused on a permission/approval dialog would answer the decision on the user's behalf — an
unrecoverable action, unlike a skipped message which callers re-attempt or surface."* Two details:
`InputLease` is a late-bound admission authority held until the pane write returns, because *"session
mutations close admission first and then wait for already-issued leases to drain, eliminating the
check-then-write race that a boolean 'input allowed' query cannot avoid"*; and `SuppressedUnknown` — the
outcome when the pre-write read failed — is deliberately the **zero value**, so a forgotten assignment
can never read as a successful send.

### agent-deck — measuring a context window honestly, and acting before the harness does

`asheshgoplani/agent-deck` → `internal/ctxinspect/doc.go` and the package around it;
`internal/ui/clear_on_compact.go` with `clearOnCompactThreshold = 80.0` (`internal/ui/home.go:125`)

`ctxinspect` reconstructs everything occupying a session's context window *before the first user turn*
and records where every number came from. Its governing rule — *"A wrong token number is worse than no
token number"* — is enforced by two mechanisms worth copying outright: provenance is **two-axis**
(`TextProv` says how good the bytes are — verbatim from the harness, reconstructed, or absent;
`TokenProv` says how good the number is — provider-measured, real tokenizer, estimated, derived by
subtraction, or unknown), because collapsing them onto one axis forces a lie in one direction; and
*numbers cannot exist without provenance* (`TokenCount` has no bare exported constructor). The package
is also deliberately pure — no shelling out, no tmux, no network — so a report can be produced from
golden fixtures. Separately, `ActionableTotal()` counts only items the user has a *lever* on and returns
a `complete` flag so an unknown cost renders as a lower bound rather than being summed away.

The action half: at 80% occupancy agent-deck sends `/clear` to conductor sessions, deliberately ahead of
Claude's own auto-compact at ~95-98%, *"giving a clean slate via /clear"*. The threshold is a Go
constant, so copy the mechanism and make the number configuration.

### ralphex — limit patterns that do not fire on prose about limits

`umputun/ralphex` → `wait_on_limit` / `--wait`, `claude_limit_patterns`, `codex_limit_patterns`
(documented in its shipped `llms.txt`)

The naive version of quota detection greps the session output for "rate limit" and fires when a code
review *mentions* rate limiting. ralphex's fix is the one to copy: for Claude, patterns are matched **by
source** — a bounded window of structured CLI diagnostics (result/error records, assistant API-error
messages, relevant system events) plus non-JSON CLI lines is authority, while ordinary assistant text
and successful result summaries are excluded. And a `result` record counts as diagnostic only when it
authenticates itself (`is_error:true`, `terminal_reason:"api_error"`, or a non-zero `api_error_status`)
— `subtype` is explicitly not consulted, *"since a genuine rate-limit result has been observed carrying
`subtype:"success"`"*. Transient `529/502/503/504` were moved out of the limit set into
`claude_retry_patterns` so they auto-retry without `--wait`.

### ralph-claude-code — a terminal condition made of checkboxes

`frankbria/ralph-claude-code` → `ralph_loop.sh`, `_count_blocking_unchecked()` (`:219`) and
`should_exit_gracefully()` (`:906`)

Two independent stopping rules. The hard one is mechanical: count unticked `- [ ]` items in the plan
file, but items under sections listed in `OPTIONAL_SECTIONS` do **not** block the plan-complete exit —
so "truly optional/future work" can exist in a plan without preventing the loop from ever finishing. The
soft one is a JSON ledger at `.ralph/.exit_signals` holding `test_only_loops`, `done_signals` and
`completion_indicators`, with `MAX_CONSECUTIVE_DONE_SIGNALS=2` and a named reason on every exit
(`permission_denied`, `test_saturation`, …). Naming the exit reason, rather than just exiting, is the
part that pays.

### Ralph Orchestrator — gates that hand their failure back as a prompt

`mikeyobrien/ralph-orchestrator` → `ralph.yml`, `backpressure.gates`

```yaml
backpressure:
  gates:
    - name: clippy
      command: cargo clippy --all-targets --all-features -- -D warnings
      on_fail: "Clippy lint failures. Fix all warnings before proceeding."
```

A gate is a command plus the sentence the agent is told when it fails. Cheap, engine-agnostic, and it
makes "independent verification" a config file rather than a second agent. Paired with
`event_loop.completion_promise: LOOP_COMPLETE`, `max_iterations` and `max_runtime_seconds`, it is the
whole of a terminal condition in about fifteen lines of YAML.

### Orca — killing only what you started

`stablyai/orca` → `src/main/pty-descendant-termination.ts`, `pty-descendant-exit-verification.ts`,
`own-chromium-tree-kill-guard.ts`, `main-process-tree-kill-gate.test.ts`,
`refused-tree-kill-root-termination.test.ts`, `windows-descendant-exit-verification.ts`

R1's third clause ("kills only what it started") has more engineering behind it here than anywhere else:
descendant termination with *exit verification* rather than fire-and-forget, a guard that refuses to
tree-kill Orca's own Chromium processes, a gate on killing from the main process, and a test named for
the case where root termination is refused. Also worth reading beside it:
`worktree-removal-home-guard.ts` and `worktree-removal-safety.ts`.

### Claude Squad — the cheapest possible progress detector

`smtg-ai/claude-squad` → `session/tmux/tmux.go`, `statusMonitor` and `HasUpdated()` (`:246`)

SHA-256 the captured pane each tick and compare to the previous hash: unchanged means no progress. In
the same call it returns `hasPrompt` by matching one literal per program — `"No, and tell Claude what to
do differently"` (Claude), `"(Y)es/(N)o/(D)on't ask again"` (Aider), `"Yes, allow once"` (Gemini). It is
brittle by construction and it is thirty lines; useful as a floor, not a design.

### Symphony — refresh returns the whole issue, not the state string

`openai/symphony` → `SPEC.md` §11.1

> *"The refresh operation returns full normalized snapshots, not only state strings, because label,
> assignment, routing, and provider-specific dispatchability can change while a run is active."*

That single sentence is requirement 3's "mid-run pickup; watches the description", specified. Its
neighbours are worth the read too: an ID-refresh call **must fail** rather than silently omit a malformed
record, *"because omission is meaningful"*, while a state-list call **may** omit one, because such a
record was never safe to dispatch anyway.

---

## 5. Nobody solves these

`research/adoption/ADOPTION-VERDICT.md` §5 names four requirements with "no working implementation
anywhere": **R1** (terminal condition), **R4** (quota sensing driving an action), **R3** (board
write-back) and **R11's second half** (parallel work in the same folder). That list was written without
this survey, from two candidates plus a partial reconstruction of the field. Checked against the
evidence above, **two of the four are wrong, one needs sharpening, and one holds.** Two requirements the
verdict did not list belong on it.

### R4 — quota sensing driving an action: **CORRECTED. Solved, four times over.**

§5 says *"Only a 473-star project has the whole thing."* It is not only claudexor:

- **claudexor** — `limit_action: auto | fail | ask | rotate` with a `headroom_threshold` and a
  `rotation_eligible` list, and `auto` resolving by credential kind so a spent subscription never
  silently falls through to a metered key. VERIFIED in `credential-profile-rotation.ts`.
- **Gas Town** — a `quota_dog` patrol on a 5-minute ticker driving `gt quota rotate`, which "scans for
  rate-limited sessions, plans account assignments, and executes keychain swaps + session restarts".
  VERIFIED in `internal/daemon/quota_dog.go`.
- **ralphex** — `wait_on_limit` / `--wait`: detect the limit, wait the configured duration, retry. That
  is requirement 4's "wait for reset" verb, shipped. VERIFIED in its `llms.txt`.
- **ralph-claude-code** — parses Claude's `rate_limit_event` for `status:"rejected"`, distinguishes the
  5-hour plan limit from the Extra Usage quota, waits for reset with a countdown, notifies. VERIFIED in
  `ralph_loop.sh:2412-2435` and `:868-902`.

What is genuinely missing inside R4 is narrower and worth stating precisely: **nobody implements
save-and-resume.** Every tool here does one of *wait*, *rotate* or *fail*; none checkpoints the run's
state, releases the session, and resumes it after the window resets. And **the best sensing in the field
is attached to nothing** — Orca has per-vendor fetchers for eight providers, Untrivial AO persists both
window percentages and their reset times per conversation, Cyrus consumes Codex's 300-minute and
10,080-minute windows, and all three of those act on none of it (Cyrus's handler is two `log` calls with
a comment explaining that the third case "provides no actionable information").

### R3 — board write-back: **CORRECTED. Wrong, including about Symphony.**

§5 says *"Only Symphony has even specified it."* Symphony specified the **opposite**: SPEC §11 is
explicitly *"a portable read kernel for scheduling"* and instructs implementers *"do not add generic
comment/state/attachment CRUD merely to make providers look alike"*, pushing ticket writes onto the
agent's own provider-native tools. Meanwhile four projects implement or specify write-back:

- **Cyrus** — `IIssueTrackerService.updateIssue()` and `createComment()`, platform-agnostic with Linear,
  CLI and RPC adapters.
- **Sortie** — `TrackerAdapter.TransitionIssue`, writing tracker state "at exactly three configured
  points, each one reporting an event it observed", plus ADR 0017 closing the issue when the managed PR
  merges.
- **ralph-claude-code** — `gh_issue_comment`, `gh_close_issue`, `gh_add_labels`, `gh_create_pr`.
- **Paperclip** — an entire normative specification for it, `docs/specs/external-task-protocol.md`,
  covering six providers, an Outbound Write Engine (§10.1), capability-declared write operations (§5.2)
  and a link lifecycle with deduplication and unlink semantics (§6).

The **real** gap inside R3 is the clause after the semicolon: *"mid-run pickup; watches the
description."* Nothing found re-reads a ticket's **description** mid-run and changes what the agent is
doing. Symphony §11.1 specifies re-fetching full snapshots because label, assignment and routing can
change mid-run, and Sortie's ADR 0026 re-reads issue state before recording an absence failure — but
both are about *dispatchability*, not about the operator editing the brief while the agent works on it.

### R1 — the terminal condition: **HOLDS, sharpened.**

Four tools do stop on purpose: ralph-claude-code (`should_exit_gracefully()` plus the blocking-checkbox
count), Ralph Orchestrator (`completion_promise: LOOP_COMPLETE`, `max_iterations`,
`max_runtime_seconds`), ralphex (plan complete → archived to `docs/plans/completed/`, plus
`review_patience` stalemate exit), and Claude Code itself (`-p` prints and exits). So the claim that
"ralph-loop-shaped tools never stop on purpose" is too strong — the ralph family is the *only* part of
the field that stops on purpose.

But every one of those terminates **one plan or one loop**, not a drained queue. Every tool in the
survey that has a real multi-ticket queue is an explicitly resident daemon: Gas Town, Sortie, Symphony,
Cyrus, Vibe Kanban, agent-deck and Claude Squad all return **zero hits** for
`drainAndExit | exitWhenIdle | shutdownWhenEmpty | queueEmptyExit`. Requirement 1 as written — *run a
queue unattended for hours, stop cleanly when it empties, and kill only what you started* — is still
unowned. The nearest thing to the third clause is Orca's descendant-termination family (§4), which is
worth copying and is not a terminal condition.

### R11's second half — your parallel work in the same folder: **HOLDS, unanimously.**

Every tool solves isolation the same way: give the agent its own worktree, workspace directory, clone or
VM. Thirteen of the eighteen rows in §3A are `yes` or `partial` on worktree isolation (one, ralph-claude-code, is a verified `no`; four are unknown). Not one of them
protects the *human's* concurrent edits in the *same* checkout. Orca's `worktree-removal-home-guard.ts`,
`worktree-removal-safety.ts` and `worktree-removal-session-partition-fencing.test.ts` are the closest,
and they guard against the tool deleting the wrong tree — not against an agent and its owner writing the
same file at the same time. Confirmed unsolved, and confirmed as something that must be invented rather
than adopted.

### Two more that belong on the list

**R8's premise needs revising, not just its gap.** ADOPTION-VERDICT §5 "Change 2" reads the field as
unanimous — *"in a headless session, a question is a terminal outcome, not something to answer."* The
field is **split, and both sides argued it explicitly**. Sortie ADR 0025 makes a human-input request a
dedicated non-retryable terminal, on the ground that *"an unattended run contains no one who can grant
permission."* claudexor does the opposite: `packages/daemon/src/interactions.ts` parks the question as a
durable pending interaction with a timeout and four resolution terminals, answerable later from the CLI.
Claude Squad detects the prompt but cannot answer it; Untrivial AO's `sessionguard` exists precisely to
*refuse* to answer one by accident. So R8 is not unsolved — it is a live design fork with one
implementation on each side, and claudexor's is the one to read before choosing.

**R7's external watchdog on a different subscription: nobody, confirmed.** Every liveness mechanism
found watches from inside the process or the machine it is watching — Gas Town's daemon heartbeats its
own agents, Orca's hang-watchdog watches its own Electron main thread, agent-deck's `selfheal` engine
runs in the TUI it is healing. No tool runs its watchdog on a different account or a different provider
from the work.

**R9's three config scopes: nobody has three.** ralphex has two and they are the right two — a global
`~/.config/ralphex` (relocatable via `RALPHEX_CONFIG_DIR`) plus a per-project `.ralphex/` created by
`ralphex --init`. Sortie has one file with the best *reload* semantics in the field, including a
documented list of keys that deliberately do **not** rebuild on reload. Nobody has a run scope, and only
Gas Town has stop verbs.

---

## 6. Sources

All access dated **2026-09-19** unless noted. Method, in order of preference: `gh api repos/…` and
`gh api repos/…/releases` for identity; `gh api repos/…/contents/…` piped through `base64 -d` for
individual files; `git clone --depth 1` plus local `grep -rIn` for whole-repository sweeps (this is both
faster than and immune to the code-search rate limit, and it is how every `0 hits` result below was
obtained); and the locally installed `claude` CLI for the native row.

### Repositories read (2026-09-19)

| Source | What was read |
|---|---|
| `github.com/Untrivial-ai/agent-orchestrator` | shallow clone; `backend/internal/sessionguard/guard.go`, `service/agent/codex_capacity.go`, `storage/sqlite/gen/conversations.sql.go`, `storage/sqlite/store/conversation_store.go`, `service/agent/readiness_coordinator.go`, package listing of `backend/internal`, `docs/adr/` |
| `github.com/gastownhall/gastown` | `internal/daemon/quota_dog.go` (via contents API); plus the surviving local primaries `gastown-daemon.go`, `gastown-estop.go`, `gastown-cmd-estop.go` |
| `github.com/sortie-ai/sortie` | shallow clone; `docs/architecture.md`, `docs/architecture/06-configuration-specification.md`, `docs/architecture/08-polling-scheduling-and-reconciliation.md`, ADRs 0007, 0013, 0014, 0020, 0025; `internal/tracker/linear/*`, `internal/notify/*` |
| `github.com/openai/symphony` | the surviving local primary `symphony-SPEC.md` (§1, §7, §11); repo tree via contents API (`elixir/lib`, `docs/`) |
| `github.com/razzant/claudexor` | `packages/orchestrator/src/account-pool.ts`, `credential-profile-rotation.ts`; `packages/daemon/src/interactions.ts`; `packages/budget/src/usage-evidence.ts`; package and file listings for `orchestrator`, `daemon`, `context`, `secrets`, `policy`, `control-api`, `cli` |
| `github.com/umputun/ralphex` | the surviving local primary `ralphex-llms.txt` (the project's own condensed documentation bundle) |
| `github.com/mikeyobrien/ralph-orchestrator` | shallow clone; `ralph.yml`, `crates/ralph-core/src/config.rs`, `crates/ralph-cli/src/{wave,presets,loop_runner}.rs`, `crates/ralph-api/src/errors.rs` |
| `github.com/frankbria/ralph-claude-code` | shallow clone; `ralph_loop.sh`, `lib/queue_manager.sh`, `lib/github_lifecycle.sh` |
| `github.com/asheshgoplani/agent-deck` | shallow clone; `internal/ctxinspect/doc.go` + package listing, `internal/ui/clear_on_compact.go`, `internal/ui/home.go`, `cmd/agent-deck/usage_cmd.go`, `internal/quota/`, `internal/{fleet,selfheal,procowner}/`, `conductor/` |
| `github.com/smtg-ai/claude-squad` | shallow clone; `session/tmux/tmux.go`, `session/instance.go`, `app/app.go` |
| `github.com/cyrusagents/cyrus` | shallow clone; `packages/core/src/issue-tracker/IIssueTrackerService.ts`, `packages/edge-worker/src/AgentSessionManager.ts`, `RunnerConcurrency.ts`, `ConfigManager.ts`, `packages/core/src/config-schemas.ts`, `packages/codex-runner/` fixtures |
| `github.com/generalaction/emdash` | shallow clone; `packages/plugins/src/issues/` (plugin, capability, all twelve `impl/`), `packages/core/src/runtimes/automations/node/scheduling/scheduler.ts` |
| `github.com/stablyai/orca` | contents API listings of `src/`, `src/main/`, `src/main/rate-limits/`, `src/main/claude-accounts/`, `src/main/hang-watchdog/`; `src/main/rate-limits/account-runtime-target-sync.ts` |
| `github.com/BloopAI/vibe-kanban` | shallow clone; `crates/` listing, `crates/server/src/routes/remote/issues.rs`, `crates/executors/src/logs/mod.rs`, `crates/executors/src/executors/opencode.rs` |
| `github.com/paperclipai/paperclip` | `docs/specs/external-task-protocol.md` §§1-3 (problem statement, goals/non-goals, system overview, §3.3 Symphony relationship, §3.4 core-vs-connector boundary) and its section headings through §7; top-level tree. The rest of the 5,500-issue monorepo was not read |
| `github.com/sipyourdrink-ltd/bernstein` | **identity only**. Capability rows are `unknown`; whether it is a runner or a policy layer over someone else's runner was not established |
| `github.com/ruvnet/ruflo` | **identity only**. Capability rows are `unknown` |
| `github.com/devflowinc/uzi` | identity only, to confirm staleness (last push 2025-06-04) |
| Claude Code CLI | the locally installed binary, `claude --version` → **2.1.278**; `claude --help`, `claude agents --help`, `claude respawn --help` |

### Documents in this repository

- `research/adoption/ADOPTION-VERDICT.md` — §2 (the eleven requirements, reused verbatim in §1 above)
  and §5 (the four-item unsolved list, cross-checked in §5 above).
- `research/platforms/00-field-scan.md`, `research/platforms/kimi.md`, `research/platforms/glm.md`,
  `research/clusters/C4-capacity-research.md`, `research/clusters/C6-liveness-recovery-research.md` —
  the five stages that cited the lost survey and had to proceed without it.

### Surviving raw primaries from the 2026-09-13 run

Still present under
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/`
and read in full for this rebuild: `gastown-daemon.go` (115 KB), `gastown-estop.go`,
`gastown-cmd-estop.go`, `symphony-SPEC.md` (92 KB), `ralphex-llms.txt` (32 KB). The directory
`scratchpad/context/` — which held `orchestrator-landscape.md`, `harness-evidence.md` and
`snf-architecture.md` — **is empty**, as five earlier stages separately recorded. No `claudexor-*`
primary survived; claudexor was re-read live.

### Known gaps in this document

Stated plainly so the next reader does not mistake silence for a finding:

1. **Bernstein and Ruflo have identity rows only.** Whether Bernstein is a runner or a policy layer
   over someone else's runner was not established; Ruflo was not opened at all. Paperclip's category
   placement *was* resolved (§2.3), but only from its protocol specification — none of its
   implementation was read, so every Paperclip cell tagged [V] is verified against a normative spec the
   project wrote about itself, not against shipped code.
2. **Orca's merge, concurrency, board write-back and terminal-condition rows are unknown.** Its quota,
   account, worktree and process-teardown machinery were read; the rest of a 72k-star Electron app was
   not.
3. **claudexor's concurrency, worktree, board and single-instance rows are unknown.** Its quota, account
   and interaction machinery were read in depth; the rest of its 30-package monorepo was not.
4. Several `unknown` cells in §3 are unknown because the search budget went to the axes the job turns on
   (R1, R3, R4, R6, R8), not because the feature is absent.

