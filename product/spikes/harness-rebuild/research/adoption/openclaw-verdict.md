# OpenClaw — adversarial verdict

**Target:** `openclaw/openclaw` + `openclaw/acpx` (scope set by `openclaw-identity.md`)
**Stage:** steelman + attack, after `openclaw-identity.md` and `openclaw-mapping.md`
**Date:** 2026-09-19
**Method:** GitHub REST (`gh`) for repo metadata, issues, contributors, security advisories, code search;
sparse clone of `openclaw/openclaw@main` docs and `openclaw/acpx@main`; npm registry; **and a first-hand
install and CLI probe of `acpx@0.17.0` on this machine.** Claims tagged VERIFIED / CLAIMED / UNKNOWN.

**Verdict: ADOPT-AS-COMPONENT** — adopt `acpx` (pinned) as the session layer; **reject** the OpenClaw
Gateway; take two openclaw-core mechanisms as *designs to reimplement*, not as code or dependency.

---

## 0. Blocker, carried forward for the third time

`…/scratchpad/context/orchestrator-landscape.md` **does not exist.** VERIFIED again today: the
`context/` directory exists and is empty; `find` over the whole scratchpad returns nothing matching
`*landscape*`.

This time I did not stop there. The scratchpad *does* hold raw primaries from that survey — 
`gastown-daemon.go` (115 KB), `gastown-estop.go`, `gastown-cmd-estop.go`, `symphony-SPEC.md` (92 KB),
`ralphex-llms.txt`. I read enough of them to make the comparative call the task demands, and §3 states
the limit in place.

---

## PASS 1 — STEELMAN

*The strongest honest case for adopting instead of building. The owner's time is expensive; his current
tool has a documented 34-hour failure record. What does he get on day one, and what does he stop
maintaining?*

### 1.1 Day one, the terminal-séance failure class disappears entirely

This is the real case, and it is strong. FIELD-NOTES §1 is not a list of bugs — it is a list of
consequences of one architectural choice: **the harness drives sessions by typing into a TTY.**

| FIELD-NOTES record | What it cost in the 34-hour run |
|---|---|
| 1.2 `/compact` lands only when no shell is running | 3 attempts, 1 worked; session drifted 91%→95% and auto-compacted anyway |
| 1.3 Text typed at a session may never arrive | **five instructions never delivered**; `send` destroys pending text; a re-invoked session discards the input line |
| 1.4 The nudge does not submit stranded text | measured twice, both times the text was still sitting there |
| 1.5 Heartbeat staleness is not a stall | **six nudges to six healthy sessions** |
| 1.6 A finished session is closed by nobody | one session idle and registered for **1 day 4 hours**, closed by hand |
| 2.2 A shell that cannot exit reads as work | a lane held an `until grep … sleep 5` that could never match; another accumulated **58 concurrent child shells** |

Every row is gone the moment the session is a process with arguments and an exit code instead of a
terminal with a cursor. `acpx` makes it exactly that, and I verified the surface first-hand.

**VERIFIED by running it here** (`acpx@0.17.0`, Node 22.18.0, macOS, 41 packages, 6 seconds):

```
prompt                         Prompt text
--timeout <seconds>            Maximum time to wait for agent response
--max-turns <count>            Maximum turns for the session
--prompt-retries <count>       Retry failed prompt turns on transient errors
--permission-policy <json>     autoApprove, autoDeny, escalate, defaultAction
--format json / --json-strict
--ttl <seconds>                Queue owner idle TTL before shutdown (0 = keep alive forever) (default: 300)
--append-system-prompt <text>  Append text to the agent system prompt
--allowed-tools <list>         Allowed tool names (use "" for no tools)
--cwd <dir>                    Working directory
Commands: prompt | exec | cancel | set-mode | set | status | sessions
Agents:   pi openclaw codex claude gemini cursor copilot devin droid …
```

A malformed invocation exited `2`, matching the published contract. `exec` is a one-shot prompt with no
saved session — a queue runner's primitive. `sessions ensure` is documented as the idempotent form for
scripts. `--ttl` is a genuine idle-shutdown: the session layer *does* stop by itself when no work
arrives, which is more than the Gateway ever does.

The exit-code table (`0` ok, `1` agent/runtime, `2` usage, `3` timeout, `4` no session, `5` all denied,
`130` interrupted) is published as stable, and I checked the claim rather than repeating it: **across
44 published versions the CHANGELOG contains no entry that changes an exit code.** VERIFIED.

### 1.2 Day one, the plugin's three unbuilt subsystems have working reference designs

FIELD-NOTES 3.3, verbatim: *"`bin/*.sh` contains no reference to context, percentages, or compaction; a
grep for `compact|ctx=|auto-compact` returns nothing."* Meanwhile 3.1 records a lane spending **445k
tokens — 77% of all context growth in that window — on `echo idle`**, reaching 91%.

OpenClaw has, as shipped and documented subsystems:

- **A per-turn context contract** — `context.max_tokens`, `context.used_tokens`, `context.pct_used`,
  `state.compactions` — plus compaction that keeps tool-call/result pairs intact across the split, a
  quality guard that refuses to write a bad summary, a cheaper compaction model, a `midTurnPrecheck`,
  a byte guard, `MAX_OVERFLOW_COMPACTION_ATTEMPTS = 3` and `MAX_COMPACTION_RESERVE_RATIO = 0.25`.
- **A four-layer single-instance lock** whose stale-owner check is PID + **process start time** + argv
  shape, failing *closed* when process inspection is unavailable. The owner's requirement 7 ("two
  orchestrators of one run never run at once") is one PID reuse away from silently breaking under a
  naive lock file; this is the cheap correct version, and it is ~200 lines of idea.
- **`post-compaction-context.ts`** — re-reads `AGENTS.md` after every compaction and re-injects the
  named sections, default `["Session Startup", "Red Lines"]`, fenced-code-aware, date-substituted,
  bounded, degrading to `null` on every failure path. This is the only place where requirement 6
  (context) and requirement 11 (one prohibitions file) meet, and it answers a failure the owner's own
  design does not anticipate: **compaction deletes the red lines mid-run**, in a run long enough for
  that to happen repeatedly.

### 1.3 Day one, requirement 2 is satisfied structurally rather than by promise

The owner's hardest constraint is that the tool must *not own the engineering process* and must not
forbid in-session subagents. OpenClaw's answer is not a policy statement, it is an architecture:
`docs/tools/acp-agents.md`, verbatim — *"ACP sessions let OpenClaw run external coding harnesses
(Claude Code, Cursor, Copilot, Droid, OpenClaw ACP, OpenCode, Gemini CLI …)."* The harness session **is**
Claude Code, so GSD and superpowers and the Task tool work inside it untouched. `acpx claude`,
`acpx codex`, `acpx --agent '<cmd>'` deliver the same property with no gateway at all.

### 1.4 What he would stop maintaining

His harness is **2,261 lines of shell across 13 scripts** (VERIFIED, `wc -l plugins/harness/bin/*.sh`
plus tests). Adopting `acpx` retires the parts that have actually failed: `harness-term.sh` (235 lines,
and Terminal.app is already *"explicitly refused as undrivable"* for `send`/`key`), the typing and
nudging half of `harness-run.sh` watch, the boot-verify and trust-dialog dance in `harness-spawn.sh` and
`harness-trust.sh`, and the heartbeat-staleness heuristic that produced six false stalls. That is
plausibly 400–600 lines of the most defect-dense code in the plugin, replaced by one dependency and a
`case $?`.

### 1.5 And the honest version of the maximal case

If the owner wanted to stop building a harness altogether, OpenClaw is the only candidate in this
research that arrives with all of: multi-agent isolation per role with its own auth profiles and model
registry; a hot-reload config watcher that *"waits for editor temp-write/rename churn to settle … and
rejects invalid external edits without rewriting `openclaw.json`"* (strictly better than the mtime
watcher requirement 5 describes); a ten-provider quota reader that normalizes to `X% left` and does not
assume Claude's window shape; automation delivery that can go *"to a chat channel, a webhook, or
**nowhere**"* (requirement 10, literally); `AGENTS.md` auto-injected every turn (requirement 11); and a
release every week. On paper that is nine of eleven requirements with named mechanisms. **That is the
case to beat, and Pass 2 beats it.**

---

## PASS 2 — ATTACK

### 2.1 The kill shot: the project's own scorecard grades the exact subsystems he needs at 0%

OpenClaw publishes a machine-generated maturity scorecard (`docs/maturity/scorecard.md`, rendered from
`taxonomy.yaml` + `qa/maturity-scores.yaml`). Its framing, verbatim: *"Coverage comes from deterministic
QA evidence"* and *"Coverage is deliberately evidence-led: an area does not become 'ready' just because
the implementation exists."* The project's stated aim is *"end-to-end coverage above 90% for mature
Stable-or-better features."*

**Overall self-grade: `68%` maturity, `Alpha`. Quality `Alpha — 65%`. Completeness `Beta — 71%`.
Coverage `Unscored`.** VERIFIED.

Now map his eleven jobs onto that table. Every row below is VERBATIM from the scorecard:

| His requirement | Subsystem the mapping praised | Project's own QA evidence |
|---|---|---|
| **6 — context window** | `session-memory.context-engine` | **missing — 0 of 9 (0%)** |
| 6 — compaction thresholds | `session-memory.token-management` | partial — 2 of 10 (20%) |
| 6 — session recovery | `session-memory.diagnostics-maintenance-and-recovery` | **missing — 0 of 10 (0%)** |
| **4 — quota per provider** | `agent-runtime.provider-auth` | **missing — 0 of 17 (0%)** |
| **4 — Anthropic quota + wait-for-reset** | `anthropic.provider-auth-and-recovery` | **missing — 0 of 9 (0%)** |
| 4 — model failover | `agent-runtime.model-and-runtime-selection` | partial — 1 of 11 (9.1%) |
| **7 — never two orchestrators, drain, restart** | `gateway.gateway-lifecycle` | partial — **2 of 12 (16.7%)** |
| **7 — health check** | `gateway.health-diagnostics-and-repair` | **missing — 0 of 7 (0%)** |
| 7 — heartbeat | `automation.heartbeat` | **missing — 0 of 4 (0%)** |
| 2 — runs his engine, allows subagents | `agent-runtime.external-runtimes-and-subagents` | partial — 3 of 10 (30%) |
| 11 — sandbox / boundaries | `security.approval-policy-and-tool-safeguards` | partial — 1 of 6 (16.7%) |
| — his actual OS | **every `macos-host.*` row**, incl. `gateway-service-lifecycle` | **missing — 0 of 10, 0 of 9, 0 of 5, 0 of 4 …** |

The mapping called the quota reader *"the best I have seen anywhere"* and the context subsystem a
closure of FIELD-NOTES 3.3. Both are true as descriptions of the **code**. By the project's own
deterministic QA evidence, both have **zero end-to-end proof**, and the Anthropic path — the one he
would hit at 03:00 on a weekly-window reset — is 0 of 9.

This does not make the designs wrong. It makes them **unproven implementations he would be trusting
unattended**, which is precisely the thing his own FIELD-NOTES exist to stop him doing again. It
converts "adopt these subsystems" into "read them, reimplement them small, and test them yourself."

### 2.2 It is actively moving *away* from requirement 8

acpx `CHANGELOG.md`, **Unreleased → Breaking**, VERBATIM:

> *"cancel fixed-choice interaction questions with a user-answer-required error instead of selecting an
> answer through tool approval. This also applies to existing custom launchers and **takes precedence
> over `--approve-all`, permission policies, and embedding host permission callbacks**."*

Requirement 8's second half is *"the orchestrator can answer a session's own question within its
authority."* An orchestrator can approve a **tool**; it cannot answer an `AskUserQuestion` — and the
project has just hardened that refusal so it overrides every escape hatch, retroactively, including for
custom launchers. On the OpenClaw side the same line holds: `ask_user` is *"available only in the main
session. Subagents and other non-primary runs do not receive it."*

For a run that is unattended for hours, a worker that asks a fixed-choice question does not wait — it
**fails the turn with exit `5`**. His orchestrator must handle that as a first-class outcome. This is a
requirement the candidate does not merely lack; it is deliberately closing the door.

### 2.3 The maintenance surface he would inherit is not comparable to what he would retire

| | His harness | `acpx` | `openclaw/openclaw` |
|---|---|---|---|
| Source size | ~80 KB shell (2,261 LOC) | **3.41 MB** | **442.0 MB** (91% TypeScript) |
| Open issues | — | **4** | **5,117** |
| Security advisories (lifetime) | — | **0** | **722** |
| Commits/week (last 8) | — | — | 2835, 2427, 2283, 2059, 2802, 3750, 4336, 4146 |
| Releases | — | 44 in 7 months | weekly, calendar-versioned |

All VERIFIED today via the GitHub API. The 722 advisories break down as **14 critical, 249 high, 390
medium, 69 low** — 263 high-or-worse in about ten months, batched in waves (75 published on 2026-09-11
alone; 67 on 05-28; 59 on 03-31). The *class* matters more than the count: reading the titles, they are
overwhelmingly authorization-bypass — *"Exec approvals could outlive their reviewed working
directory"* (high), *"Gateway upgrade-like requests could retain unauthenticated sockets"* (high),
*"Escaped newlines could confuse exec allowlist parsing"* (high), *"QQBot admin commands could skip
DM-only and allowFrom policy"* (**critical**), *"message.action forwarding could send Gateway
credentials to model-supplied loopback URLs"*.

Two things follow. First, **the advisory surface is concentrated in exactly the part he would not
adopt** — channels, pairing, chat-sourced authority, remote Gateway access — which is a point *for* the
acpx-only seam, not against it. Second, running a resident Gateway on his machine means a **mandatory
weekly upgrade treadmill** against a project whose `VISION.md` states, verbatim: *"OpenClaw runtime code
reads the current configuration schema only. We do not keep long-lived aliases or compatibility
branches."* Pinning to stay stable and patching to stay safe are mutually exclusive here. That is
disqualifying for an always-on daemon on a developer workstation, and it is the strongest reason the
Gateway is a reject rather than a maybe.

### 2.4 The recommended component is pre-1.0 in the way that actually hurts

`acpx@0.17.0`, 44 versions, first published 2026-02-17. Its own `docs/VISION.md`-adjacent framing calls
the interfaces evolving. I counted the receipts: **the CHANGELOG contains 40 `### Breaking` sections**
across those 44 releases. VERIFIED. Sampled, they are not cosmetic:

- *"Runtime API: require `AcpRuntimeTurn.promptStarted` …"*
- *"Session journals: `.stream.ndjson` now includes local lifecycle and segment records alongside ACP
  messages; direct consumers must distinguish entries with `jsonrpc: \"2.0\"`."*
- *"Windows agent launches now require structured `agents.<name>.argv` … **Existing custom-agent
  sessions without saved argv must be recreated.**"*

That last one is a data migration, not an API rename. An unpinned `acpx` in an overnight harness is a
run-ending risk. The mitigation is real but must be written down as a rule: **pin the exact version,
upgrade deliberately, and depend only on the subcommand names, the exit codes and `--format json`** —
the three surfaces that have provably not moved.

### 2.5 Bus factor, and what "Foundation" does and does not buy

`openclaw/openclaw` contributions: `steipete` **51,671**, `vincentkoc` 13,871, `shakkernerd` 4,344,
`obviyus` 2,390, then a long tail. One person is ~70% of the project by commit count. `acpx` is healthier
in relative terms — `steipete` 164, `dutifulbob` 107, `vincentkoc` 81, `dependabot` 68, `osolmaz` 67 —
but the npm maintainers are `steipete` and `osolmaz`, and the whole org's centre of gravity is one
person who has already renamed this project three times under legal pressure (Warelay → Clawdbot →
Moltbot → OpenClaw). `LICENSE` is clean MIT, copyright "OpenClaw Foundation"; the API reports
`NOASSERTION` only because the file appends a `THIRD_PARTY_NOTICES.md` pointer. Foundation structure,
funding and trademark posture remain **UNKNOWN**, and a foundation that appeared in January 2026 is not
yet evidence of institutional continuity.

### 2.6 Telemetry and data flow — small, real, and disableable

`docs/gateway/telemetry.md`, VERBATIM: *"Automatic update checks send a daily request by default. It
asks whether a newer version exists and includes the OpenClaw version, operating system, Node.js
version, CPU architecture, and request surface."* The receiver also derives approximate location
server-side. Anonymous feature statistics (configured channels and providers, plugin inventory,
retained session-creation count) are **off by default and opt-in**, and `openclaw telemetry show` prints
exactly what would be sent. This is an honest, inspectable, switchable-off posture. It is a fact to
record, not a reason to reject — **and it does not apply to the acpx-only seam at all**, which makes no
such call.

### 2.7 The three hard blockers survive re-verification

I re-ran the mapping's decisive greps rather than trusting them.

1. **No terminal condition.** `drainAndExit`, `exitWhenIdle`, `shutdownWhenEmpty`, `queueEmptyExit` →
   **0 results each** in code search; no docs sentence matching *"exits when the queue is empty"* /
   *"shuts down when the queue"* / *"drain to empty"*. The Gateway is a resident daemon by design.
   Requirement 1 is the job's *name*, and it is architecturally absent.
2. **No quota thresholds.** `quotaThreshold`, `usageThreshold`, `stopOnQuota`, `pauseOnQuota` →
   **0 results each.** VERIFIED. Issue **#129327** — *"Proactive quota/usage threshold alerts at
   80/85/90/95% before exhaustion"* — is **OPEN** since 2026-08-25 and carries the labels `stale`, `P3`,
   `clawsweeper:needs-product-decision`, and **`issue-rating: 🌊 off-meta tidepool`**. The project has
   not merely failed to build requirement 4; it has triaged the *weakest possible form of it* — an
   alert, not a stop — as off-meta and awaiting a product decision, 25 days later.
3. **Workboard, the only component shaped like his queue, is disabled by default and broken in the
   places an overnight run lives.** All five issues re-verified **OPEN** today:

| Issue | Priority | Opened | Still open after | What it breaks |
|---|---|---|---|---|
| #122911 | **P1** | 2026-08-13 | 37 days | *"dead worker run's execution record permanently starves its agent's dispatch lane"* |
| #114724 | **P1** | 2026-07-27 | 54 days | *"Legacy workboard claims without ownerId permanently lock cards — no release/reclaim/dispatch path"* |
| #116358 | P2 | 2026-07-30 | 51 days | *"dispatch overwrites card agentId … defaultAssignee is never applied"* |
| #141156 | P2 | 2026-09-07 | 12 days | *"expired claims still block all non-owner mutations (verified on main)"* |
| #144872 | P2 | 2026-09-11 | 8 days | *"cards run as view-only subagents and cannot be continued when dispatched from automation/heartbeat"* |

Both P1s carry `clawsweeper:linked-pr-open`. **A fix has been open for 37 and 54 days on a project
merging ~4,500 PRs a week.** That is the most informative number in this whole evaluation: velocity is
not reaching this surface. Backlog arithmetic agrees — **6,921 issues opened vs 5,320 closed in the last
30 days**, net **+1,601/month**.

### 2.8 Migration cost and exit path

- **Gateway adoption:** install a daemon, move config into one global `~/.openclaw/openclaw.json` (no
  project scope, no run scope — requirement 9 unmet), rewrite his queue onto a beta Workboard with two
  open P1s, accept weekly breaking config migrations, and inherit 442 MB of source and a ~72
  advisories/month patch cadence — to replace 2,261 lines of shell he wrote and understands. **Exit
  path: expensive.** His queue semantics would live in someone else's SQLite.
- **acpx adoption:** `npm i acpx@0.17.0`, replace one spawn function, branch on `$?`. **Exit path:
  delete the dependency and go back to driving terminals.** He loses a capability, not a run. The
  reversal is an afternoon.

The asymmetry between those two lines is the entire verdict.

---

## 3. Is it better than the best of the field, for this job?

**Stated limit:** the landscape survey file does not exist, so this is not the full comparative answer.
It is what the surviving raw primaries in the scratchpad support.

- **Gas Town already has the manual-stop verb OpenClaw lacks.** `gastown-estop.go`, VERBATIM header:
  *"The E-stop is a town-wide mechanism to pause all agent work. It uses a sentinel file (ESTOP) at the
  town root. When present, all agents should be frozen (SIGTSTP) and the daemon should not restart
  them. The Mayor is exempt from E-stop so it can coordinate recovery."* That is requirement 9's
  stop-hard/stop-soft — *"the command writes into the file the orchestrator reads every tick"* — already
  built, with the orchestrator-exempt carve-out the owner would need. OpenClaw's nearest equivalent is
  `gateway restart --safe|--force`, which stops the **daemon**, not the **run**.
- **Symphony already specs the board integration OpenClaw refuses.** `symphony-SPEC.md` carries
  **§11 "Issue Tracker Integration Contract"**, alongside §7 "Orchestration State Machine", §9
  "Workspace Management and Safety" and §14 "Failure Model and Recovery Strategy". OpenClaw's bundled
  GitHub plugin is verbatim *"public-repository link previews and a **read-only** reader"*, and
  Workboard says of itself *"It is **not** a replacement for GitHub Issues, Linear, Jira …"*.

So on requirements 1, 3 and 9 — stop cleanly, connected board, manual stop verbs — OpenClaw is **not**
better than the field; it is behind at least two tools the owner has already surveyed.

Where it is genuinely ahead of everything found in this research: **context-window management as a
first-class measured subsystem** (§1.2), **a single-instance guarantee that survives PID reuse**, a
**vendor-agnostic quota reader** that does not assume Claude's window shape, and — the one that matters
most in practice — **`acpx` as the only agent-agnostic harness driver with a published exit-code
contract and a no-envelope raw-protocol output rule.**

---

## 4. Verdict

**ADOPT-AS-COMPONENT.**

Adopt `openclaw/acpx`, pinned at an exact version, as the session layer beneath the owner's own
orchestrator — it is 3.41 MB with zero security advisories and four open issues, it installs and runs
correctly on this machine today, and it retires the entire terminal-typing failure class that produced
six of the FIELD-NOTES records including five undelivered instructions and a session left running for a
day and four hours. Reject `openclaw/openclaw` itself: the Gateway has no terminal condition at all
(four code searches, zero hits), no quota threshold of any kind (four more, zero hits, with the project's
own issue #129327 sitting `stale` / `off-meta tidepool` / `needs-product-decision` after 25 days), a
read-only board, and a weekly-breaking-config release cadence that cannot be reconciled with its
~72-security-advisories-per-month patch treadmill. Take `post-compaction-context.ts` and the
`gateway-lock.ts` PID+start-time+argv identity check as **designs to reimplement small and test
himself**, not as code to trust.

**The single piece of evidence that decided it:** OpenClaw's own machine-generated maturity scorecard,
which grades the whole project **68% / "Alpha"** and assigns **zero deterministic QA coverage** to
precisely the subsystems the adoption case rests on — `session-memory.context-engine` **0 of 9**,
`agent-runtime.provider-auth` **0 of 17**, `anthropic.provider-auth-and-recovery` **0 of 9**,
`gateway.health-diagnostics-and-repair` **0 of 7**, `gateway.gateway-lifecycle` **2 of 12**, and every
`macos-host.*` row at **0%** on the owner's own operating system — under the project's own rule that
*"an area does not become 'ready' just because the implementation exists."* Impressive unproven code is
the thing the 34-hour run already taught him not to run unattended.

---

## 5. If he adopts the component — the four rules

1. **Pin it.** `acpx@0.17.0` exactly. 40 `### Breaking` sections in 44 releases; one of them required
   recreating existing sessions. Upgrade deliberately, read the CHANGELOG's Breaking section first.
2. **Depend only on the stable triple**: subcommand names, exit codes, `--format json --json-strict`.
   Not the runtime API, not the session-journal schema — both have already broken.
3. **Treat exit `5` as a first-class outcome.** A worker asking a fixed-choice question does not block;
   it fails the turn. The project is hardening that refusal so it overrides every escape hatch.
4. **Keep the queue, the stop verbs, the board write-back and the quota policy in his own code.** Those
   are the four requirements OpenClaw does not have, two of which the field already solves better
   (Gas Town's ESTOP sentinel; Symphony's §11 tracker contract).
