# Adoption verdict — DeepSeek Harness and OpenClaw

**To:** the owner
**Date:** 2026-09-19
**Inputs:** `deepseek-harness-{identity,mapping,verdict}.md`, `openclaw-{identity,mapping,verdict}.md` (this
directory); `plugins/harness/docs/FIELD-NOTES.md`; `round-1/TRANSCRIPT-01.md` + `ANALYSIS-01.md`.
**Tags:** VERIFIED (read at a primary source) · CLAIMED (asserted by a non-vendor source) · UNKNOWN.

**Headline: neither replaces your build. One of them gives you a component worth taking today.**

---

## 0. One blocker you should know about before you read the table

The comparative context file the brief points at —
`…/scratchpad/context/orchestrator-landscape.md` — **does not exist**, and did not exist at any of the
five research stages that were told to use it. VERIFIED again while writing this: the `context/`
directory is present and empty; a filesystem-wide search for `*landscape*` returns nothing.

What survived are the survey's **raw primaries**, still sitting in the same scratchpad:
`gastown-daemon.go` (115 KB), `gastown-estop.go`, `gastown-cmd-estop.go`, `symphony-SPEC.md` (92 KB),
`ralphex-llms.txt`. Those were read, and the comparative column below is built from them plus fresh `gh`
verification — not from the survey. **Two consequences you should price in:** the third column is a
rebuilt minimum rather than the full field, and anything in `/private/tmp/claude-501/**` is one reboot
from gone. If the survey mattered, it needs regenerating into the repo, not the scratchpad.

---

## 1. What these two names turned out to be

### "deepseek harness" → `deepseek-ai/deepseek-harness` (`dsh`)

One name, one artifact, no collision — unusual in this space and worth saying, because it means your
note carried no hidden ambiguity. It is **first-party DeepSeek AI**, MIT, TypeScript, public since
2026-08-13, **229,704 stars** five weeks later, built on the Cordis micro-kernel under an
"everything-is-a-plugin" architecture. And it is **not an orchestrator**. It sits at the *same layer as
Claude Code* — one agent runtime driving one session's model calls, tools, sandbox and UI. Its
orchestration-shaped packages (`jobs`, `schedule`, `goal`, `workflow`, `agent-team`) are documented as
**session-local in their own type system**: `ScheduleDeliveryMode = 'session-local'`, `goal-round-driver`
says "Same-session execution only", and `agent-team` lives in `packages/experimental/`. The
cross-session, queue-of-work, runs-for-hours layer exists only in community plugins in the 2–96 star
range, days old. So the comparison that matters is not "DSH vs. my orchestrator" — they are not the
same product — but "is DSH a substrate or a donor". It is a donor. (VERIFIED throughout.)

### "openclaw" → `openclaw/openclaw`, and the useful part is its sibling `openclaw/acpx`

`openclaw/openclaw` is an open-source personal/team AI assistant with a local Gateway control plane,
MIT ("OpenClaw Foundation"), originally Peter Steinberger's, renamed three times under legal pressure
(**Warelay → Clawdbot → Moltbot → OpenClaw**, the last two in January 2026 after an Anthropic trademark
request). 390,076 stars, ~4,100 commits and ~4,500 merged PRs *per week*, weekly calendar releases. Its
centre of gravity is **a resident daemon that lives in your chat channels** — WhatsApp, Telegram,
Slack, Discord, Signal, iMessage — that grew harness features. Its own `VISION.md` files *"Better
computer-use and agent harness capabilities"* under **Next** priorities, not current. (VERIFIED.)

**And there is a decoy, exactly as suspected: `pjasicek/OpenClaw` is a C++/SDL2 reimplementation of the
1997 Captain Claw platformer, GPL-3.0, last pushed 2022-10-24.** It has nothing to do with agents, it
predates the AI project by eight years, and it is dormant. If you ever half-remember "openclaw" from a
gamedev context, that is why. Say it plainly: that repo is not a candidate and never was.

The part of the OpenClaw org that is actually relevant to you is **`openclaw/acpx`** — a headless CLI
client for stateful Agent Client Protocol sessions. MIT, 3,263 stars, 3.41 MB, **4 open issues, zero
security advisories in its lifetime**. It drives Claude Code, Codex, Cursor, Copilot, Droid, Gemini CLI
and arbitrary `--agent '<cmd>'` behind one published exit-code contract. It was installed and run on
this machine during the evaluation (`acpx@0.17.0`, Node 22.18.0, 41 packages, 6 seconds) — the CLI
surface and the exit codes match the docs. (VERIFIED first-hand.)

---

## 2. Side by side against the eleven requirements

Legend: **Covered** · **Partial** · **Absent** · **Prevented** (the design actively rules it out) ·
**n/a** (out of that component's scope by construction).

Third-column note: the survey is missing, so the reference column is **`razzant/claudexor`** — the one
tool in the rebuilt field that ships both of your make-or-break items (R4 quota, R5 accounts per role).
473 stars, MIT, TypeScript, v3.12.4, pushed 2026-09-19, **issue tracker open with 75 issues**. Its rows
are from its README and repo metadata only; rows not evidenced there are marked UNKNOWN rather than
guessed. Two other field tools beat everything in this table on a single requirement each, and they are
footnoted under it.

| # | Requirement | `dsh` (DeepSeek) | `openclaw` Gateway | `acpx` (component) | claudexor (field ref.) |
|---|---|---|---|---|---|
| 1 | Unattended queue for hours; clean stop when empty; kills only what it started | **Partial** — process-tree teardown is excellent, queue is session-local and dies with the process | **Partial** — real lane-aware queue and durable task ledger, **no terminal condition at all** (`drainAndExit`, `exitWhenIdle`, `shutdownWhenEmpty`, `queueEmptyExit` → 0 hits each) | **Partial** — no queue, but `--ttl` is a genuine idle self-shutdown and the session is a process with an exit code | UNKNOWN |
| 2 | Does not own the process; runs GSD / superpowers / custom; must not forbid in-session subagents | **Partial → effectively Prevented** — subagents are first-class, but DSH brings *its own* loop; the only Claude Code path is one-shot | **Covered** — ACP runs external harnesses; the session *is* Claude Code, so GSD and the Task tool are untouched | **Covered** — `acpx claude`, `acpx codex`, `acpx --agent '<cmd>'` | **Covered** (multi-harness: `claude`, `codex`, `cursor`, `opencode`) |
| 3 | Local registry **or** connected board; sets statuses and comments; mid-run pickup; watches the description | **Absent** — one ingress-only GitHub webhook; its own doc: "no queue, retry, deduplication, execution status, crash replay… Repeated delivery may create repeated Sessions" | **Partial** — bundled GitHub plugin is verbatim *"a read-only reader"*; Workboard says of itself it is *"**not** a replacement for GitHub Issues, Linear, Jira"* | **n/a** | UNKNOWN |
| 4 | Quota per provider; user thresholds; hard / soft / save-and-resume; wait for reset; no Claude-shaped assumption | **Absent** — verified by exhaustion of the generated 3,945-line config catalog across all 128 configurable packages; the only quota word is `fileQuotaCleanupBatch` (disk). Worse: `llm-retry` `always` mode *retries on quota until success* | **Partial** — best-in-class **sensing** (10 providers, per-vendor quirks, 5-hour/weekly bars, plan label), **zero acting**: `quotaThreshold`, `usageThreshold`, `stopOnQuota`, `pauseOnQuota` → 0 hits each | **Absent** | **Covered** — "live subscription-quota tracking… rotates a spent account out of the way on typed vendor limits", per-window 5h/7d bars |
| 5 | Several platforms and accounts, per role, switchable mid-run through one watched file, verified before a run | **Covered** — named routes, `apiKeyEnv` refs never stored in config, resolved **per request** ("no restart"), refused at write time if unservable | **Covered** — isolated agents each with own workspace, `agentDir`, auth profiles, model registry; ~70 providers; hot-reload watcher that waits out editor temp-write churn | **Partial** — agent and `--cwd` per invocation; the account file is yours | **Covered** — named credential profiles per subscription |
| 6 | Watch each session's context window; compact or hand off at a user-set threshold; **guaranteed** | **Covered except "guaranteed"** — `thresholdRatio` 0.8, per-route overrides, fires at `agent/pre-step`; but its README: summarization failure *"proceeds with full over-budget history"* | **Covered-partial** — live `context.pct_used` per turn, pair-preserving split, quality guard, cheap compaction model, `midTurnPrecheck`; **no user-set percentage**, no soft/hard, no threshold handoff | **Absent** (the engine's job) | UNKNOWN |
| 7 | Survives its own death: health check, provider fallback, launch journal, never two orchestrators | **Partial** — the `flock` single-owner contract is the best artifact found anywhere; **no** health check, **no** provider fallback | **Covered** — four-layer lock with PID + **process start time** + argv identity, failing closed; stability journal; health probes; durable restart recovery. Missing only a watchdog on a *different* subscription | **n/a** | Partial (model/account fallback) |
| 8 | Interactive terminals **or** headless per platform; orchestrator answers a session's own question | **Partial / Prevented** — headless is the best executor seam found; **no interactive terminal at all**, and the delegated child is forbidden to ask | **Partial / hardening against you** — headless excellent, no interactive terminals, `ask_user` is main-session-only | **Prevented, deliberately** — Unreleased→Breaking: fixed-choice questions fail with `user-answer-required` and this *"takes precedence over `--approve-all`, permission policies, and embedding host permission callbacks"* → exit `5` | UNKNOWN |
| 9 | Config at global / project / run scope, changeable **during** a run, next-tick pickup; stop-hard / stop-soft / stop-custom | **Partial** — the watched settings-file protocol is exactly right; scopes are wrong; **no stop verbs**; and config-HMR is **disabled in precisely the headless/SDK/ACP bundles automation uses** | **Partial** — live change excellent; one global `~/.openclaw/openclaw.json`, **no project or run scope**; `gateway restart --safe\|--force` stops the *daemon*, not the *run* | **n/a** | UNKNOWN |
| 10 | Prints nothing unless asked; status from a separate command; notifications to a configured, verified channel | **Partial** — headless is genuinely quiet; **no `dsh status`**, and a whole-tree search for `notif\|telegram\|slack\|email` finds nothing user-facing. Default front door opens a **browser UI** | **Covered** — seven channels, and automation delivery goes *"to a chat channel, a webhook, or **nowhere**"*, which is requirement 10 word for word | **Covered** — silent, `--format json` on demand, `status` subcommand | UNKNOWN |
| 11 | Never touches other projects **or your parallel work in the same folder**; one prohibitions file every agent reads | **Covered differently** — OS-level sandbox (which you said you did not want) + a loaded global `AGENTS.md`. But `workspace-write` confines to the workspace root, **which is where your parallel work lives**, and there are two open, unanswered sandbox-escape reports | **Partial** — `AGENTS.md` / `SOUL.md` / `USER.md` auto-injected every session (solved *better* than you asked); the same-folder parallel-work boundary is **not** solved | **Partial** — `--cwd`, `--allowed-tools`, `--permission-policy` | UNKNOWN |

**Footnotes to the third column — two field tools that beat every column above on one row each:**

- **R9, stop verbs.** Gas Town already has them. `gastown-estop.go`, verbatim: *"The E-stop is a
  town-wide mechanism to pause all agent work. It uses a sentinel file (ESTOP) at the town root. When
  present, all agents should be frozen (SIGTSTP) and the daemon should not restart them. **The Mayor is
  exempt from E-stop so it can coordinate recovery.**"* That is stop-hard plus the orchestrator-exempt
  carve-out you would need, already built.
- **R3, board integration.** Symphony already specs it. `symphony-SPEC.md` carries **§11 "Issue Tracker
  Integration Contract"**, next to §7 "Orchestration State Machine", §9 "Workspace Management and
  Safety" and §14 "Failure Model and Recovery Strategy".

---

## 3. The verdict on each

### `deepseek-ai/deepseek-harness` — **BORROW MECHANISMS. Do not adopt, not even as a component.**

**Deciding evidence:** the Known Limitations block of
`packages/subagent/subagent-claude-code/README.md`, fetched 2026-09-19 —

> **One fresh query and process per run** — there is no continuation, resume, pooling, progress stream,
> or product-session persistence. · **No human interaction path** — `AskUserQuestion` is disabled,
> permission prompts are denied, MCP elicitation is declined, and blocking dialogs fail closed instead
> of suspending. · **Static instance selection** — calls cannot choose or change either a provider or
> model dynamically. · **No wall-clock timeout or side-effect rollback.**

Missing quota (R4) alone rules out adopting DSH whole. That block rules out adopting it **as a
component** too, and this is the part worth dwelling on: R1-03 is settled in your own words — the
orchestrator runs GSD, superpowers or a custom step list and does not own the process. A GSD phase is
multi-turn, asks questions in discuss-phase and UAT, and must be observable while it works. Every one of
those is explicitly unavailable here. So both seams collapse: DSH-headless-as-executor runs *DSH's own
loop*, which is the thing R1-03 forbids; DSH-driving-`claude` is one-shot, mute and unanswerable, and
FIELD-NOTES §9.1 records that the single most valuable behaviour of your 34-hour run was that *sessions
refused to guess and escalated instead*. Under that provider, escalation fails closed and the phase dies.

**Two aggravating facts.** First, governance: `has_issues: false`, external PRs refused in writing
(*"We are sorry that we cannot accept external pull requests at the moment"*), `CONTRIBUTING.md` calling
the repo *"an idea, an official showcase… **but not a mandate from us**"*, git history starting on launch
day, a `.gitlab-ci.yml` in the tree and merge commits pointing at a private org. Support measured: 7,035
discussions, **114 answered (1.6%)**, **3,095 with zero comments (44%)**, and the top five contributors
have commented in **16 discussions combined**. That is not a dependency, it is a read-only artifact.
Second, the failure reports that hit exactly the subsystems an adopter would lean on — a single corrupted
session log preventing `dsh` from starting at all; *"Missing session-level lock silently corrupts
shared-home deployments"*; an orphan writer lock that is unrecoverable in practice; a compaction
checkpoint where *"the loader and the writer disagree"*; and a failed tool call that hard-aborts a turn
and replays verbatim forever — the same infinite-loop class as FIELD-NOTES §11.6, inherited rather than
cured. (All CLAIMED, all open, all read 2026-09-19.)

**Against your own bar (R1-18, "better in every aspect"):** a 473-star project ships the two
requirements you called make-or-break; the 229,704-star one ships neither and cannot accept a patch that
adds them.

### `openclaw/openclaw` — **REJECT the Gateway. `openclaw/acpx` — ADOPT AS A COMPONENT, pinned.**

**Deciding evidence for rejecting the Gateway:** OpenClaw publishes a machine-generated maturity
scorecard (`docs/maturity/scorecard.md`) under its own stated rule that *"an area does not become 'ready'
just because the implementation exists."* Overall self-grade **68% / "Alpha"**. Now map your jobs onto
it, verbatim rows:

| Your requirement | Subsystem the adoption case rests on | Project's own QA evidence |
|---|---|---|
| 6 — context window | `session-memory.context-engine` | **0 of 9 (0%)** |
| 6 — session recovery | `session-memory.diagnostics-maintenance-and-recovery` | **0 of 10 (0%)** |
| 4 — quota per provider | `agent-runtime.provider-auth` | **0 of 17 (0%)** |
| 4 — Anthropic quota + reset | `anthropic.provider-auth-and-recovery` | **0 of 9 (0%)** |
| 7 — health check | `gateway.health-diagnostics-and-repair` | **0 of 7 (0%)** |
| 7 — single instance, drain, restart | `gateway.gateway-lifecycle` | **2 of 12 (16.7%)** |
| — your actual OS | every `macos-host.*` row | **0 of 10, 0 of 9, 0 of 5, 0 of 4…** |

The code behind those rows is genuinely the best-designed in this whole research. By the project's own
deterministic evidence it has **zero end-to-end proof**, and the Anthropic path — the one you hit at
03:00 on a weekly-window reset — is 0 of 9. Impressive unproven code running unattended is precisely
what the 34-hour run taught you not to do again. That converts "adopt these subsystems" into "read them,
reimplement them small, test them yourself."

Reinforcing, and each independently sufficient: **no terminal condition** (four code searches, zero
hits — the Gateway is a resident daemon by design, and requirement 1 is the *name* of your job);
**no quota threshold of any kind**, with issue **#129327** asking only for *alerts* at 80/85/90/95% open
since 2026-08-25 and labelled `stale`, `P3`, `needs-product-decision`, **`issue-rating: 🌊 off-meta
tidepool`**; **Workboard**, the only component shaped like your queue, disabled by default with two P1s
open for **37 and 54 days** (*"dead worker run's execution record permanently starves its agent's
dispatch lane"*, *"Legacy workboard claims without ownerId permanently lock cards — no
release/reclaim/dispatch path"*) — **both with a linked PR open** on a project merging ~4,500 PRs a
week. Velocity is not reaching this surface. Backlog arithmetic agrees: 6,921 issues opened vs 5,320
closed in the last 30 days, net **+1,601/month**. And the operational disqualifier for an always-on
daemon on your workstation: **722 lifetime security advisories** (14 critical / 249 high / 390 medium /
69 low; 75 published on 2026-09-11 alone), overwhelmingly authorization-bypass in the channel, pairing
and remote-access surface, against a `VISION.md` that states *"We do not keep long-lived aliases or
compatibility branches."* Pinning to stay stable and patching to stay safe are mutually exclusive there.

**Deciding evidence for adopting `acpx`:** the asymmetry of the two migrations, and it is not close.
Gateway adoption = install a daemon, move config into one global file (losing project and run scope),
rewrite your queue onto a beta Workboard with two open P1s, accept weekly breaking config migrations,
inherit 442 MB of source and ~72 advisories/month — to replace 2,261 lines of shell you wrote and
understand. acpx adoption = `npm i acpx@0.17.0`, replace one spawn function, `case $?`. **Exit path:
delete the dependency and go back to driving terminals. You lose a capability, not a run. The reversal
is an afternoon.**

What it buys on day one is the retirement of an entire failure *class*, not a list of bugs. Every one of
these FIELD-NOTES records descends from one decision — that the harness controls sessions by typing into
a TTY and reading the screen back:

| FIELD-NOTES | What it cost in the 34-hour run | What acpx makes of it |
|---|---|---|
| §1.3 typed text may never arrive | **five instructions never delivered** | a prompt is an argument, queued if a turn is running |
| §1.4 the nudge cannot submit stranded text | measured twice, text still sitting there | no nudge exists; `cancel` / `set-mode` are protocol calls |
| §1.2 `/compact` lands only with no shell running | 3 attempts, 1 worked; drifted 91%→95% | n/a — the engine compacts itself |
| §1.5 heartbeat staleness ≠ a stall | **six nudges to six healthy sessions** | liveness is the process, not a screen |
| §1.6 a finished session is closed by nobody | one idle and registered **1 day 4 hours** | the process exits, with a code |
| §2.2 a shell that cannot exit reads as work | a lane held an `until grep… sleep 5` that could never match; another accumulated **58 concurrent child shells** | `--timeout` → exit `3`; SIGTERM → `130` |

The exit-code contract (`0` ok · `1` agent/runtime · `2` usage · `3` timeout · `4` no session · `5` all
denied · `130` interrupted) was not taken on trust: **across 44 published versions the CHANGELOG contains
no entry that changes an exit code.** VERIFIED.

**The four rules that come with it, non-negotiable:**

1. **Pin `acpx@0.17.0` exactly.** 40 `### Breaking` sections in 44 releases, one of which required
   recreating existing sessions (*"Existing custom-agent sessions without saved argv must be recreated"*).
   An unpinned acpx in an overnight run is a run-ending risk.
2. **Depend only on the stable triple:** subcommand names, exit codes, `--format json --json-strict`.
   Not the runtime API, not the session-journal schema — both have already broken.
3. **Treat exit `5` as a first-class outcome.** A worker that asks a fixed-choice question does not
   wait; it fails the turn. The project is *hardening* that refusal so it overrides every escape hatch.
4. **Keep the queue, the stop verbs, the board write-back and the quota policy in your own code.**

---

## 4. What to steal

Each item: what it is, where it lives, what it replaces in your design. Ordered by value per hour.

### From `acpx` — take the code (as a pinned dependency)

1. **The session layer itself.** `acpx claude sessions ensure --name <ticket-id>`, then
   `acpx --format json --json-strict --timeout 1800 claude -s <id> --cwd <worktree> --permission-policy
   '{"autoApprove":["read","search"],"escalate":["execute"],"defaultAction":"deny"}' "<prompt>"`, then
   branch on `$?`; `cancel` / `status` as protocol calls.
   **Replaces:** `harness-term.sh` (235 lines, and Terminal.app is already *"explicitly refused as
   undrivable"* for `send`/`key`), the typing-and-nudging half of `harness-run.sh watch`, the
   boot-verify and trust-dialog dance in `harness-spawn.sh` / `harness-trust.sh`, and the
   heartbeat-staleness heuristic that produced six false stalls. Plausibly **400–600 lines of your most
   defect-dense shell**, replaced by one dependency and a `case`.
   **Do not delete that code — demote it.** See §5 on why R8 forces a hybrid.
2. **The exit-code table as a contract.** `acpx docs/exit-codes.md`.
   **Replaces:** every place your orchestrator currently infers a session's outcome from screen text.

### From `openclaw/openclaw` — take the designs, reimplement small (the scorecard says do not trust the code)

3. **Post-compaction re-injection of the prohibitions file.**
   `src/auto-reply/reply/post-compaction-context.ts`. After every compaction it re-reads `AGENTS.md`,
   extracts the H2/H3 sections named in `compaction.postCompactionSections` — default
   `["Session Startup", "Red Lines"]` — and prepends them with: *"Session was just compacted. The
   conversation summary above is a hint, NOT a substitute for your startup sequence."* The details are
   why it is worth copying rather than reinventing: heading extraction is **fenced-code-block aware**;
   `YYYY-MM-DD` is substituted with the real date *"so agents read the correct daily memory files
   instead of guessing based on training cutoff"*; bounded at `MAX_CONTEXT_CHARS = 1800` with
   UTF-16-safe truncation; case-insensitive **multiset** section matching; the prose changes when the
   sections are custom; and **every failure path returns `null`** — a missing or oversized `AGENTS.md`
   degrades to no injection, never to an error. ~200 lines, depends on nothing in OpenClaw.
   **Replaces:** R1-15's "one text file every agent must read", which today is a hope at session start.
   It is the only place in either candidate where R6 (context) and R11 (prohibitions) meet, and it
   answers a failure your design does not anticipate: **compaction deletes the red lines mid-run**, in a
   run long enough for that to happen repeatedly.
4. **The lock identity check.** `src/infra/gateway-lock.ts` — `resolveGatewayOwnerStatus` (≈213–265) and
   `shouldReclaimGatewayLock` (≈293–320): PID → **process start time** → argv shape, with the comment
   naming the trap (*"Process start identity catches PID recycling even when the replacement process has
   the same argv shape"*), and **failing closed** when the cmdline reader is unavailable.
   **Replaces:** the naive PID-file version of R1-10's "two orchestrators must never run at once", which
   is one PID reuse at 04:00 from silently breaking. Use it where `flock` cannot reach.
5. **A durable, restart-surviving retry budget with a tombstone.** `docs/gateway/restart-recovery.md`:
   three charged automatic dispatch attempts, **retained across gateway restarts**, charged *before*
   dispatch, refunded only on explicit pre-acceptance rejection, retained when a post-dispatch result is
   uncertain — *"After the durable budget is exhausted, the session is tombstoned instead of looping
   forever."*
   **Replaces:** Д5's "three identical failures → act per configuration", which in your design counts
   in-run. This makes the count survive the orchestrator's own death, which is the case where looping
   forever actually happens.
6. **Turn admission as one transaction.** Same doc: the user message, the running mark and the recovery
   delivery claim are written **in a single SQLite transaction before any model or hook execution**; at
   shutdown every session with an active run is stamped; at startup a scan finds sessions *"that still
   claim to be running but have no live owner in the new process."*
   **Replaces:** FIELD-NOTES §2.1's attention file rebuilt from scratch each cycle.

### From `dsh` — take the contracts (never the runtime)

7. **The single-run lock contract.** `native/system/docs/flock-contract.md`, tested against
   `native/system/test/fixtures/flock-oracle.c`. The decisive row: *"Holder process exits or is killed →
   Acquisition succeeds after process exit, **without a stale-lock timeout**."* No heartbeat, no TTL, no
   guessing.
   **Replaces:** R7's hardest clause, and it is the missing primitive behind FIELD-NOTES §11.6 — an
   85-minute self-sustaining loop nothing internal detected, and a dead run flagging itself **1,085 times
   over five days**. Take the *contract and the rule* ("the lock dies with its holder, no TTL");
   `flock(1)` from bash is enough. **Do not port their `withFileLock`** — its own users report an
   unrecoverable orphan after a kill.
8. **Append `start` first, `end` last.** `docs/subsystems/compaction.md`. One line of discipline: a crash
   leaves a **detectable orphan** rather than a false claim of completion.
   **Replaces:** the whole "reported success and did nothing" class — FIELD-NOTES §11.4 (a merge printing
   `Already up to date` / `Everything up-to-date` and doing nothing), §4.1 (verification steps reporting
   success while doing nothing), §12.7 (an audit log recording events that never happened).
9. **The watched control-file protocol.** `packages/settings/settings-file/README.md`: one YAML document,
   cross-process writer lock, atomic rename through a random-suffix sibling that **never follows a planted
   symlink**, `0600` under `0700`, leaf-level diffs that preserve comments and anchors, self-write
   suppression by content, and **boot fails loud / reload keeps last good** so a hand-edit mistake cannot
   take the process down.
   **Replaces:** Д12's control file and R1-07's account file — already designed, including the failure
   mode you would otherwise discover by hand-editing at 02:00.
10. **The route model for accounts.** `packages/llm/llm-pi-ai/README.md` + `docs/subsystems/credentials.md`:
    named routes in a `providers` dict, per-route `apiKeyEnv` **references never stored in the config
    file**, resolved *per request* so a change lands with no restart, and **refused at write time** by
    `SettingsRegisterOptions.validate` if the route could not be served.
    **Replaces:** R5 end to end, including the "verified to work before a run" clause you would otherwise
    build as a separate preflight — here it is a write-time refusal, which is strictly better.
11. **The executor's output contract.** `packages/bundle/headless/README.md`: NDJSON, specified byte
    bounds per string and per line, depth cut at 64, an **uncapped terminal `final`**, exit 0 iff the turn
    completed, *"opens no ports and leaves nothing running behind"*, and a resume guard that refuses a
    session recorded in another cwd, a subagent, a fork, or one already live.
    **Replaces:** the gap behind FIELD-NOTES §11.2 and §12.1 — a supervisor that *knows* rather than
    *believes* that its instruction landed. Worth emitting even when the executor is plain `claude`.
12. **Idea only: a measurement that names the offset it was computed at.** `token-meter`'s `logRevision`.
    Do **not** port the code (~1,200 lines of positional surface pricing wired into DSH's session model).
    Port the property: a context reading is replayable, not sampled off a screen.

### From the field, restated because it bears directly on §5

13. **The ESTOP sentinel, with the orchestrator exempt.** `gastown-estop.go` / `gastown-cmd-estop.go`.
    **Replaces:** R9's stop-hard / stop-soft — "the command writes into the file the orchestrator reads
    every tick", already built, including the carve-out that lets the orchestrator coordinate recovery
    while everything else is frozen.
14. **§11 "Issue Tracker Integration Contract".** `symphony-SPEC.md`.
    **Replaces:** starting R3 from a blank page.
15. **Quota-aware account rotation.** `razzant/claudexor` — the only working implementation of R4+R5
    together found in this research, MIT, with an open issue tracker you can actually file against.

---

## 5. What this changes about the plan

**Neither candidate beats building. Keep building.** DSH is not in your category at all, and OpenClaw
fails your R1-18 bar in four places (R1, R3, R4, R9), two of which the field already solves better. The
plan does not change in direction. It changes in three specific ways.

**Change 1 — adopt `acpx` and retire the terminal séance.** This is the single highest-value, lowest-
commitment move in the entire research, and it is the only "adopt" recommendation on the table. It
converts the failure class that produced six FIELD-NOTES records into `case $?`, for one pinned npm
dependency with an afternoon-long exit path.

**Change 2 — R8 stops being a feature and becomes an architectural fork.** Both candidates are not
merely missing "the orchestrator answers a session's question" — **both are actively closing the door**.
DSH's Claude Code provider disables `AskUserQuestion` and fails blocking dialogs closed. acpx's
Unreleased→Breaking entry makes fixed-choice questions fail with `user-answer-required` and says it
*"takes precedence over `--approve-all`, permission policies, and embedding host permission callbacks"*
— retroactively, including custom launchers. OpenClaw's `ask_user` is main-session-only. Read together
that is the industry telling you: **in a headless session, a question is a terminal outcome, not
something to answer.** Three consequences: exit `5` becomes a first-class state in your state machine;
Д6's "one configured channel for questions, clarifications, confirmations and review" becomes
load-bearing rather than optional; and **R1-11's hybrid mode is no longer a nice-to-have** — headless
via acpx for work that can run to completion, your own interactive terminal path kept alive for work
that must be answerable. Do not delete `harness-term.sh`. Demote it to the interactive lane.

**Change 3 — close the two cheap gaps where you are simply behind the field.** R6: both candidates
measure the context window as a first-class subsystem; FIELD-NOTES §3.3 records that `bin/*.sh` contains
no reference to context, percentages or compaction at all, while §3.1 records a lane burning **445k
tokens — 77% of all context growth in that window — on `echo idle`**, reaching 91%. R7: both have a
better single-instance primitive than you do; `flock(1)` plus the PID+start-time+argv check is an
evening's work against a failure that cost you 85 minutes of undetected loop and 1,085 false flags.
These are not research problems. They are unstarted work.

### Where you are unusually exposed — the parts nobody solved

This is the part worth sitting with. Across DSH, OpenClaw, and the rebuilt field, **four of your eleven
requirements have no working implementation anywhere**, and three of them are the ones that make your
tool the thing it is:

- **R1 — the terminal condition.** "Drain the queue, stop cleanly, kill only what you started" is the
  *name* of your job, and nobody ships it. OpenClaw is architecturally a resident daemon (four searches,
  zero hits). DSH's queue is session-local by type. Ralph-loop-shaped tools never stop on purpose. If
  there is a moat in your build, it is here — and it is also completely unowned, so nobody will build it
  for you.
- **R4 — quota sensing driving an action.** DSH: absent, and its `always` retry mode will hammer a dead
  account. OpenClaw: the best sensing in the world attached to nothing, and the weakest possible form of
  the request — an *alert*, not a stop — triaged **off-meta, needs-product-decision, stale, 25 days
  old**. Only a 473-star project has the whole thing. You called this make-or-break; budget real time
  for it, and read claudexor's rotation policy before you write yours.
- **R3 — board write-back.** OpenClaw says in its own documentation that Workboard is *"not a
  replacement for GitHub Issues"* and its GitHub plugin is a *"read-only reader"*. DSH's webhook is
  ingress-only and admits it has no queue, retry, dedup or status. Only Symphony has even specified it.
- **R11's second half — your parallel work in the same folder.** Nobody solves it. DSH's
  `workspace-write` confines an agent to the workspace root, **which is exactly where your parallel work
  lives**; and this is not hypothetical — FIELD-NOTES §5.1 records your own container being killed for
  memory *by* the previous run. A sandbox is the wrong shape for this requirement; it needs a
  path-level, per-run ownership rule that you will have to invent.

Two more where you are merely *equally* exposed: **R9's global/project/run scopes** (both candidates
have exactly one global file) and **R7's external watchdog on a different subscription** (everything in
both candidates watches itself from inside the process it is watching).

### One housekeeping item

Regenerate the landscape survey **into the repo**, not the scratchpad. It was named by five consecutive
research stages and was missing for all five; its raw primaries are still sitting in `/private/tmp`, one
reboot from gone. Every comparative sentence in this document is weaker than it needed to be because of
that.

---

## In ten seconds

Neither name beats building: DeepSeek Harness is a peer of Claude Code with zero quota awareness, no
board, no cross-session queue and a Claude Code provider that is one-shot and cannot be asked a question,
and OpenClaw is a resident chat daemon whose own maturity scorecard gives 0% end-to-end coverage to every
subsystem the adoption case rested on. Adopt exactly one thing — `acpx@0.17.0`, pinned — as the session
layer, and delete the terminal-typing code that caused six of your documented failures. Then spend the
time you saved on the four requirements nobody in this field has solved: stopping when the queue is
empty, turning quota readings into a stop, writing back to a board, and staying out of your own parallel
work in the same folder.
