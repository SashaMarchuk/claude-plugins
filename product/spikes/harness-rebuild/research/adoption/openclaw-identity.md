# "openclaw" — identity resolution

**Stage:** identify-only (no deep evaluation)
**Date of research:** 2026-09-19
**Method:** GitHub REST API via `gh` (primary), raw source/docs files from `main` (primary), npm registry (primary), web search (secondary, used only to find primaries)

---

## 0. Blocker to record

The comparative context file the task names —
`/private/tmp/claude-501/-Users-sasha-marchuk-Work-claude-plugins/ac653a10-c035-4b73-acab-a57e21fbeaae/scratchpad/context/orchestrator-landscape.md`
— **does not exist**. The `context/` directory exists and is empty (`find` across the whole scratchpad returns nothing). Verdict below is therefore *not* comparative against Agent Orchestrator / Gas Town / Sortie / Symphony / Claudexor / ralphex / Bernstein. The next stage must either regenerate that survey or be told it is missing.

---

## 1. Answer in one line

**"openclaw" is `openclaw/openclaw`** — an open-source personal/team AI assistant with a local Gateway control plane, MIT-licensed, copyright "OpenClaw Foundation", originally by Peter Steinberger (`steipete`), formerly named **Warelay → Clawdbot → Moltbot → OpenClaw**. It is **not** primarily an engineering-work orchestrator, but it has independently grown almost every mechanism the JTBD list asks for. It is the candidate the next stage should evaluate.

---

## 2. Candidates found

### A. `openclaw/openclaw` — **THE MATCH** ✅

| Field | Value | Tag |
|---|---|---|
| Description | "The AI that really does things. Any OS. Any Platform. The lobster way. 🦞" | VERIFIED (GitHub API) |
| Homepage | https://openclaw.ai · docs at https://docs.openclaw.ai | VERIFIED |
| Stars / forks | **390,076** / 82,021 | VERIFIED (API, 2026-09-19) |
| Open issues | **8,025** | VERIFIED |
| Created | 2025-11-24 | VERIFIED |
| Last push | 2026-09-19 (today) | VERIFIED |
| Language | TypeScript (plus Swift, C#, Rust crates) | VERIFIED |
| License | **MIT** — `LICENSE` reads "MIT License / Copyright (c) 2026 OpenClaw Foundation". GitHub API reports `NOASSERTION` only because the file appends a line pointing at `THIRD_PARTY_NOTICES.md` | VERIFIED (read the file) |
| npm | `openclaw`, latest `2026.9.5`, license MIT, first published 2026-01-29, maintainers `steipete`, `vincentkoc` | VERIFIED (registry.npmjs.org) |
| Org | `openclaw`, created 2026-01-04, 92 public repos, **not** GitHub-verified | VERIFIED |
| Topics | ai, assistant, own-your-data, personal, crustacean, molty, openclaw | VERIFIED |

**Naming history (resolves the owner's word):** `VISION.md` states verbatim — *"It evolved through several names and shells: Warelay -> Clawdbot -> Moltbot -> OpenClaw."* Press coverage (CNBC, Forbes, Wikipedia) corroborates: renamed Clawdbot→Moltbot on 2026-01-27 after an Anthropic trademark request, then Moltbot→OpenClaw on 2026-01-30. VERIFIED (primary `VISION.md` + secondary press).

**Activity — extreme:**
- Commits per week, last 8 weeks: `2835, 2427, 2283, 2059, 2802, 3750, 4336, 4146` (VERIFIED, `stats/participation`)
- Last 7 days: **1,757 issues opened**, 1,017 issues closed, **4,501 PRs merged** (VERIFIED, search API)
- Releases: calendar-versioned, ~weekly. `v2026.9.5` (2026-09-19), `v2026.9.4` (09-11), `v2026.9.3` (09-08), `v2026.9.2` (09-05), `v2026.9.1` (09-03), plus a rolling `linux-stable` channel. (VERIFIED)

**What it claims to be** (README, VERIFIED verbatim): *"OpenClaw is an open-source AI assistant that runs on your own computer and meets you in the channels you already use."* *"The Gateway is the local control plane for sessions, tools, events, and channel connections."*

---

### B. `pjasicek/OpenClaw` — **UNRELATED, and confirmed as the decoy the task warned about** ❌
Reimplementation of the Captain Claw (1997) platformer. C++/SDL2, GPL-3.0, 507 stars, **last push 2022-10-24** — dormant for ~4 years. Predates the AI project by 8 years (created 2017-03-08). Multiple forks exist (`gmh5225/Game-OpenClaw`, `mialy/OpenClaw`, `arthurboss/WASM-OpenClaw`). Not a candidate. (VERIFIED)

---

### C. `gluk-w/claworc` — third-party fleet orchestrator *built on* OpenClaw 🟡
Go, 242 stars, 36 forks, created 2026-02-06, last push 2026-09-18 (active), license NOASSERTION. Site claworc.com claims: *"the open-source orchestrator for OpenClaw"*, *"Run multiple OpenClaw agents from one self-hosted dashboard"*, each agent gets *"its own isolated workspace — with chat, a live browser, terminal, file manager, and persistent storage"*, and positions itself as *"OpenClaw runs agents. Claworc helps you operate them."* (site claims CLAIMED; repo metadata VERIFIED).
**Not the thing the owner named**, but a legitimate secondary lead if the next stage finds OpenClaw's own fleet operation thin.

---

### D. `abhi1693/openclaw-mission-control` — **ARCHIVED** ❌
"AI Agent Orchestration Dashboard — Manage AI agents, assign tasks, and coordinate multi-agent collaboration via OpenClaw Gateway." 4,107 stars, 818 forks, MIT, **`archived: true`**, last push 2026-08-06. Dead. A same-named, lower-star variant exists (`manish-raana/openclaw-mission-control`, 274 stars, stale since 2026-02-09). (VERIFIED)

---

### E. `zeynepyorulmaz/openclaw-orchestrator` — abandoned hobby project ❌
34 stars, 4 forks, 1 open issue, TypeScript/SQLite, created 2026-02-23, **last push 2026-03-18** — six months stale. (VERIFIED)

---

### F. `Rolex8637/openclaw-orchestrator` — noise, and possibly repo-squatting ❌
**3 stars**, 1 fork. Its description is near-identical to E's. Note the anomaly: **created 2025-02-06, which is 9½ months before `openclaw/openclaw` itself existed** (2025-11-24) — so it is a renamed/repurposed repo riding the name. Ignore. (VERIFIED)

---

### G. `openclaw/acpx` — official sibling, mechanically the most interesting ⭐
"Headless CLI client for stateful Agent Client Protocol (ACP) sessions." 3,263 stars, 335 forks, MIT, created 2026-02-17, last push 2026-09-19, homepage acpx.sh. This is the component that lets OpenClaw drive **external coding harnesses**. Evaluate as part of A, not separately. (VERIFIED)

---

### H. Long tail — all noise (≤5 stars, or stale)
`openclaw-coder-bridge` (4★, "Bridge OpenClaw agents to any AI coding tool via file queue"), `thisisi3846/openclaw-worker` (3★), `yukiharukonishi/openclaw-cc` (5★, "OpenClaw reproduced with Claude Code"), `mmTheBest/long-running-tasks` (2★, "orchestrating multi-phase coding agent workflows"), `smaan712gb/Keel` (1★), `RichardSun700/task-resume-skill` (1★), plus the ecosystem's awesome-lists (`VoltAgent/awesome-openclaw-skills` 52k★, `hesamsheikh/awesome-openclaw-usecases` 31k★). None is a harness candidate.

**Scale note for the record:** GitHub reports **44,287 repositories** with "openclaw" in the name. The name is now an ecosystem, not a project.

---

## 3. Ranking

1. **`openclaw/openclaw`** — the only plausible referent. Everything else either derives from it or is the game.
2. `gluk-w/claworc` — active, but a thin operational layer over #1; only relevant if #1's multi-instance story fails.
3. `openclaw/acpx` — evaluate inside #1; it is the external-harness bridge, not a standalone answer.
4. Everything else — archived, stale, or noise.

---

## 4. Why this is worth a real evaluation (preliminary JTBD mapping)

I did not evaluate. But identification turned up doc-level evidence that this project has first-class primitives for most of the eleven jobs — which is unusual and is the reason to promote it rather than reject it. All paths below are files in `openclaw/openclaw@main/docs` (VERIFIED they exist; contents quoted where read).

| JTBD | Evidence | Read |
|---|---|---|
| **1. Unattended queue, clean stop** | `concepts/queue.md` — lane-aware FIFO, per-lane concurrency caps (`main` = `max(8, cpus*4)`, `subagent` = 8), global `agents.defaults.maxConcurrent`. `automation/tasks.md` — durable task ledger, `queued → running → terminal (succeeded/failed/timed_out/cancelled/lost)`. `automation/taskflow.md` — *"durable record of multi-step work… Flows survive gateway restarts."* `automation/standing-orders.md` — *"permanent operating authority… the agent executes autonomously within defined boundaries."* | **Partial.** The queue is an *inbound auto-reply* queue, not a work backlog. No primitive found for "drain a ticket queue, then stop." |
| **2. Does not own the process** | `tools/acp-agents.md` verbatim: *"ACP sessions let OpenClaw run external coding harnesses (Claude Code, Cursor, Copilot, Droid, OpenClaw ACP, OpenCode, Gemini CLI…)."* `gateway/cli-backends.md`: bundled `claude-cli` backend. `tools/subagents.md`, `tools/swarm.md`, `concepts/delegate-architecture.md`, `concepts/parallel-specialist-lanes.md` all exist — **in-session subagents are not forbidden, they are a feature.** | **Strong.** |
| **3. Board-driven work** | `plugins/github.md` — bundled GitHub plugin is *"public-repository link previews and a **read-only** reader"*. `plugins/workboard.md` — local Kanban, and says of itself verbatim: *"It is **not** a replacement for GitHub Issues, Linear, Jira, or other team project management systems."* | **Gap.** No write-back to a board. Biggest identified weakness. |
| **4. Quota watching** | `concepts/usage-tracking.md` — *"Pulls provider usage/quota directly from each provider's usage endpoint."* Normalized to `X% left`. Verbatim: *"per-window bars (5-hour, weekly, model-scoped) with reset times, the provider plan when known (for example `Max (20x)`)"*, and *"Claude Code CLI (`claude-cli`) setups reuse the same Anthropic subscription usage."* `openclaw status --usage`. | **Strong on *sensing*.** Whether it *reacts* (hard/soft stop, wait-for-reset) is UNKNOWN. |
| **5. Multi-platform, multi-account, per role** | `concepts/multi-agent.md` — *"Run multiple isolated agents in one Gateway process, each with its own workspace, state directory (`agentDir`)… auth profiles, model registry, and session store."* `docs/providers/` lists **~70 providers**. `concepts/model-failover.md` — auth-profile rotation within a provider, then model fallback. | **Strong.** |
| **6. Context window + guaranteed compaction** | `concepts/compaction.md` — auto-compaction on approaching the limit or on a context-overflow error; tool-call/result pairs kept intact across the split; `mode: "safeguard"` default with *"stricter guardrails, summary quality audits."* Also `concepts/context-engine.md`, `session-pruning.md`. Known open issues #53531 and #141666 concern compaction vs. auth-profile rotation. | **Strong** — and note the harness's own FIELD-NOTES gap ("nothing measures a session's context window") is *exactly* what this covers. |
| **7. Survives its own death; never two orchestrators** | `gateway/gateway-lock.md` — three-layer singleton: state-directory ownership lock → config lock → exclusive socket bind, each raising its own `GatewayLockError`; waits up to 5 min for the previous owner to release lifecycle ownership; *"Survive crashes/SIGKILL without leaving stale lock files behind."* Plus `gateway/health.md`, `heartbeat.md`, `restart-recovery.md`. | **Strong. This is the mechanism most worth borrowing even on a "reject".** |
| **8. Interactive or headless; orchestrator answers a session** | `acpx` (headless ACP), `gateway/background-process.md`, `gateway/cloud-workers.md`, `gateway/cloud-sessions.md`, `tools/ask-user.md`, `concepts/subagent-yield-handoff.md`, `concepts/queue-steering.md`, `tools/steer.md`. | Promising, unread. |
| **9. Config scope, live change, manual stops** | `gateway/configuration.md` + ~25 `config-*.md`. `VISION.md` config policy: *"OpenClaw runtime code reads the current configuration schema only. We do not keep long-lived aliases or compatibility branches"* + a mandatory `openclaw doctor --fix` migration per breaking change. | Global/agent scope VERIFIED to exist; **run-scope and stop-hard/soft UNKNOWN.** |
| **10. Quiet by default; configured notification channel** | Channels: WhatsApp, Telegram, Slack, Discord, Google Chat, Signal, iMessage. Automation delivery, verbatim: *"can deliver output to a chat channel, a webhook, or nowhere."* | **Strong** — "or nowhere" is literally requirement 10. |
| **11. Boundaries / prohibitions file** | `gateway/sandboxing.md`, `permission-modes.md`, `operator-scopes.md`, `sandbox-vs-tool-policy-vs-elevated.md`, `tools/exec-approvals.md`. Workspace files `AGENTS.md` / `SOUL.md` / `USER.md` are auto-injected every session — the natural home for a prohibitions file. | Promising, unread. |

---

## 5. Risks the next stage must weigh (found during identification)

1. **The maintainers themselves call the harness role unfinished.** `VISION.md` lists under *Next* priorities — not current — verbatim: *"Better computer-use and agent harness capabilities."* Current priorities are *"Security and safe defaults / Bug fixes and stability / Setup reliability and first-run UX."* **VERIFIED.** This is a personal assistant that grew harness features, not a work-queue runner that grew chat.

2. **Churn is violent.** ~4,000 commits and ~4,500 merged PRs *per week*, weekly releases, and an explicit no-backward-compatibility config policy. Building on it means tracking a fast-moving target; pinning means falling behind on security fixes in a project that is itself a known scam/security-attention magnet (Forbes, Jan 2026).

3. **8,025 open issues** against 1,017 closed in the last week — the backlog is growing, not shrinking.

4. **The board gap (JTBD 3) is real and stated by the project itself**, not inferred.

5. **Governance changed hands.** Copyright is now "OpenClaw Foundation", not Steinberger personally. Foundation structure, trademark posture, and funding are UNKNOWN and worth 10 minutes before any adoption call.

6. **The "adopt in every aspect" bar.** Even if every mechanism above checks out, OpenClaw's centre of gravity is *a chat-resident assistant with a gateway*. The owner's JTBD is *a ticket-queue runner that dies cleanly*. Most likely honest outcome is **borrow, not adopt** — specifically the three-layer gateway lock (7), the provider usage/quota surface (4), and the ACP external-harness bridge (2).

---

## 6. Verdict for the next stage

**Evaluate `openclaw/openclaw` (including `openclaw/acpx`).** Read, in this order:
`concepts/queue.md` · `automation/tasks.md` · `automation/taskflow.md` · `automation/standing-orders.md` · `automation/cron-jobs.md` · `concepts/usage-tracking.md` · `concepts/model-failover.md` · `gateway/gateway-lock.md` · `gateway/restart-recovery.md` · `tools/acp-agents.md` · `gateway/cli-backends.md` · `concepts/compaction.md` · `concepts/multi-agent.md` · `gateway/sandboxing.md` · `plugins/workboard.md` · `specs/codex-supervision.md`.

The two questions that decide adopt-vs-borrow:
- **Does quota sensing drive an action?** (`usage-tracking.md` proves it *reads* Anthropic's 5-hour and weekly windows; nothing yet proves it *stops* on them.)
- **Can a queue of tickets be drained to empty and the fleet then shut itself down?** (Nothing found suggests a terminal condition; the whole design is a resident, always-on gateway.)

Everything else on the list already has a named mechanism.
