# DeepSeek Harness (`dsh`) — adversarial verdict

**Target:** `deepseek-ai/deepseek-harness`, evaluated at `master@ddefc45` / `dsh-v0.1.6-alpha.2`.
**Stage:** steelman + attack. Follows `deepseek-harness-identity.md` and `deepseek-harness-mapping.md`.
**Date:** 2026-09-19. Every number re-verified against the GitHub API, the npm registry and
`raw.githubusercontent.com` on that date by this pass — not carried over on trust from the prior notes.
**Tags:** VERIFIED (read at a primary source, path given) · CLAIMED (asserted by a source that is not the
vendor, e.g. a community Discussion) · UNKNOWN.

**Verdict: BORROW-MECHANISMS.**

---

## Blocker, restated for the third time

`…/scratchpad/context/orchestrator-landscape.md` **still does not exist** (VERIFIED: `context/` is
present, empty, `total 0`; a filesystem-wide search finds nothing). The comparison below is again a
rebuilt minimum, verified directly by `gh`, not the survey. It is sufficient for the one comparative
question that decides this verdict, and it is not a substitute for regenerating the survey.

---

## Pass 1 — STEELMAN

The honest strongest case. Written as if the decision were "adopt", with the owner's time priced high
and `FIELD-NOTES.md` on the table.

### The premise is real: his current tool's failures are not edge cases, they are its architecture

`FIELD-NOTES.md` is not a list of bugs. Read as a whole it is a list of consequences of one decision —
**the harness controls sessions by typing text into other processes' terminals and reading their screens
back.** Every expensive failure descends from it:

- §1.1 (VERIFIED): "A model has no way to put text on its own input line" — compaction is performed by a
  watcher typing `/compact` into another session's tty.
- §1.2, §1.3, §1.4 (VERIFIED): `/compact` lands only when the target has no shell running; typed text may
  never arrive; the nudge cannot submit stranded text.
- §2.2 (VERIFIED): a shell that cannot exit reads as work.
- §3.3 (VERIFIED): `bin/*.sh` contains no reference to context, percentages or compaction at all; the
  33 config keys it reads include token-quota thresholds but no context-window threshold.
- §11.4, §4.1 (VERIFIED): a merge printed `Already up to date` / `Everything up-to-date` and did nothing,
  and verification steps reported success while doing nothing.
- §12.7 (VERIFIED): an audit log that recorded events that never happened.

DSH's answer to that entire class is structural, not incremental: **there is no screen.** State is an
append-only durable event log with an explicit fold; measurements name the `logRevision` they were
computed at; `turn/end { reason: 'interrupted' }` is a reason no loop ever emits, so "we crashed here" is
a recorded fact rather than an inference from a missing line; job teardown that throws "force-fails only
the record **without claiming that the work stopped**". On day one, the owner would stop guessing what a
session is doing from pixels.

### What he would gain on day one, concretely

1. **Context management that exists.** `packages/compaction/compaction-basic`: `thresholdRatio` 0.8 of the
   routed model's window, `retainRatio` 0.16, `auto: true`, firing at the `agent/pre-step` waterfall —
   structurally his "soft" mode — with per-route override `modelPolicies: [{ provider, model,
   thresholdRatio, retainTokens }]`, which is R1-08's "all sessions, or differently per provider" already
   built. Against §3.3 and §1.1–1.4 this replaces a three-attempts-one-lands tty procedure with an
   in-process call. (VERIFIED, package README + `docs/subsystems/compaction.md`.)
2. **Provider/account routing that is already what he described (R5).** Named routes in a `providers`
   dict, per-route `apiKeyEnv` credential references never stored in the config file, resolved *per
   request* — "settings changes take effect on the next request without a restart" — and refused at write
   time by `SettingsRegisterOptions.validate` if the route could not be served. That is "several accounts
   per role, switchable mid-run through one watched file, verified before a run", delivered. (VERIFIED,
   `packages/llm/llm-pi-ai/README.md`, `docs/subsystems/credentials.md`.)
3. **The single-orchestrator invariant, solved at the kernel (R7).** `flock(fd, LOCK_EX|LOCK_NB)` with a
   behavior table tested against a C oracle; the decisive row: "Holder process exits or is killed →
   Acquisition succeeds after process exit, **without a stale-lock timeout**." No heartbeat, no TTL, no
   guessing. Against §11.6 — an 85-minute self-sustaining loop nothing internal detected, a dead run
   flagging itself 1085 times over five days — this is the missing primitive. (VERIFIED,
   `native/system/docs/flock-contract.md`.)
4. **A watched control file he would otherwise have to write (R9/Д12).** One YAML document, cross-process
   writer lock, atomic rename through a random-suffix sibling that never follows a planted symlink, `0600`
   under `0700`, leaf-level diffs that preserve comments and anchors, self-write suppression by content,
   **boot fails loud / reload keeps last good** so a hand-edit mistake cannot take the process down.
   (VERIFIED, `packages/settings/settings-file/README.md`.)
5. **A machine-readable executor contract.** `dsh --profile headless --json --session-id <id> "task"`:
   NDJSON, 8 KiB per string except an uncapped terminal `final`, 32 KiB per line, depth cut at 64, exit 0
   iff the turn completed, "opens no ports and leaves nothing running behind", and a resume guard that
   refuses a session recorded in another cwd, a subagent, a fork, or one already live. This is what §11.2
   and §12.1 are missing: a supervisor that knows, rather than believes, whether its instruction landed.
6. **The prohibitions file, loaded by the loader rather than by the model's goodwill (R11).** One fixed
   user-global `AGENTS.md` under the harness home plus project files discovered by walking up from the
   session cwd, with dedup and byte caps. That is R1-15 as specified. (VERIFIED,
   `packages/context/agent-instructions/src/config.ts` via `docs/config-catalog.md`.)

### What he would stop maintaining

The tty-driving layer and everything that hangs off it: `harness-term.sh send`, screen scraping, the
attention file rebuilt from scratch each cycle (§2.1), the detectors that read the wrong thing (§12.2),
the heartbeat-staleness heuristic (§1.5), the "did the text arrive" problem (§1.3, §11.2, §12.1), and the
hand-rolled context estimate he does not currently have at all (§3.3). That is a large, permanently
fragile surface he did not want to own in the first place.

### The fair version of the strategic case

DSH is funded, full-time, MIT, first-party, and its documentation discipline is genuinely ahead of the
field — every package README carries a required limitations section, and
`packages/runtime-diagnostics/invariants` mechanically rejects a package that publishes an empty
invariant companion without explaining, package-specifically, why nothing is checkable. Betting against a
229,704-star first-party runtime with 36 contributors and ~1,000 commits a week, in favour of one
person's bash, is a real bet with a real cost. **The steelman's conclusion is not "adopt whole" — no
honest reading supports that — it is "adopt as the executor substrate and keep your orchestrator on top",
which would let him delete his most failure-prone subsystem this week.**

---

## Pass 2 — ATTACK

Now kill it. Taken in the order that adoptions actually die.

### A1. It cannot run the engine he must run — and this is what closes the component door

R1-03 is settled in his own words: the orchestrator runs GSD, superpowers, or a fully custom step list,
and does not own the process. His engines are Claude Code plugins. DSH has exactly one first-party path
to a real Claude Code session, `packages/subagent/subagent-claude-code`, and its own limitations block
(VERIFIED, fetched 2026-09-19) reads:

> - **One fresh query and process per run** — there is no continuation, resume, pooling, progress stream,
>   or product-session persistence.
> - **No human interaction path** — `AskUserQuestion` is disabled, permission prompts are denied, MCP
>   elicitation is declined, and blocking dialogs fail closed instead of suspending.
> - **Assistant payload is final text only** — reasoning, intermediate messages, tool traffic, usage,
>   stderr, and workspace diffs remain product-local.
> - **Static instance selection** — calls cannot choose or change either a provider or model dynamically.
> - **No wall-clock timeout or side-effect rollback.**

A GSD phase is multi-turn, asks questions (discuss-phase, UAT), and must be observable while it works.
Every one of those is explicitly unavailable. So the two seams collapse:

- **Seam A (DSH headless as executor):** runs *DSH's own agent loop*. His engine does not run. He would
  be adopting a competing process to execute a process he configured elsewhere — the exact thing R1-03
  forbids.
- **Seam C (DSH driving `claude`):** one-shot, mute, unanswerable. FIELD-NOTES §9.1 records that the
  single most valuable behaviour of the current run was that "sessions refused to guess, and escalated
  instead". Under this provider, escalation fails closed and the phase dies.

The honest residue: DSH's *own* loop is a fine executor for work that has no engine. He has an engine.

### A2. Zero quota awareness — verified by exhaustion, not by failed search

`docs/config-catalog.md` is generated from source and is the complete accepted-configuration surface of
all 128 configurable packages (3,945 lines). A case-insensitive grep for
`subscription|quota|spend|entitlement|usage.limit|resets?_at|five.hour|weekly` returns **two lines, both
the same field**: `fileQuotaCleanupBatch` — "Oldest harness-owned files deleted before one
quota-recovery upload retry". (VERIFIED, re-run this pass.)

Worse than absent, the retry policy is actively hostile to it: `llm-retry` normal mode excludes `QUOTA`
from retry, while `always` mode "retries permanent failures — authentication, **quota**, invalid-request,
protocol … until success, cancellation, or disposal". An unattended overnight run on an exhausted
subscription either stops blind or hammers a dead account. R4's hard / soft / save-and-resume vocabulary
does not exist anywhere in the tree. He would build 100% of R4 on DSH, exactly as he would on nothing —
and R4 is one of the two requirements he ranked make-or-break.

### A3. No board, no queue that outlives a process, no notifications, no status, no stops

- **R3 Absent.** The webhook subsystem is ingress-only and says so: "The webhook secret authenticates
  inbound GitHub data only. It grants neither rule code nor the created Agent outbound GitHub access."
  And: "The runtime has no queue, retry, deduplication, execution status, crash replay, Agent-status
  listener, or completion result. Repeated delivery may create repeated Sessions." No board read, no
  status write, no comment, no mid-run pickup, no description watch. (VERIFIED.)
- **R1 Partial.** `docs/subsystems/schedule.md` is titled "Session-local Schedule" and enforces it in the
  type system (`ScheduleDeliveryMode = 'session-local'`), with "the original Session must be live: no
  external notification channel or cold-session scheduler exists". `goal-round-driver` states "Same-session
  execution only". The only queue-shaped object, `agent-team`, lives in `packages/experimental/` and folds
  out of one Lead Session's log. (VERIFIED.)
- **R10 Absent twice.** A whole-tree search for `notif|telegram|slack|email` returns an internal
  `notifier.ts` and SDK test snapshots; re-verified this pass against the config catalog, which contains
  **no** `telegram|slack|notification` field at all. There is no `dsh status`.
- **R9 Absent on stops.** No `stop-hard`, `stop-soft`, `stop-custom`; the vocabulary does not exist. And
  the config-HMR that would deliver mid-run changes is, per `packages/boot/hmr/README.md`, **disabled in
  exactly the headless / SDK / ACP bundles automation would use.**

### A4. The unattended failure history — and the tracker he cannot use

Issues are disabled (VERIFIED: `has_issues: false`, `open_issues_count: 0`). Bugs go to Discussions. So
the Discussions *are* the unattended failure history, and they are damning for overnight use. All
CLAIMED (community reports, unconfirmed by the vendor), all open, all read 2026-09-19:

- **A single corrupted session log prevents `dsh` from starting at all** (0.1.6-alpha.2, 0 comments).
  For a tool left running overnight, one bad log bricks the next morning.
- **"Missing session-level lock silently corrupts shared-home deployments — any multi-writer topology
  destroys the durable work record"** (opened 2026-08-20, self-updated 2026-09-19, **0 comments**). This
  attacks the exact subsystem the steelman wants to borrow.
- **`session-persistence` takes `session.lock` on merely *opening* a session in the UI**, so a plugin's
  resume fails with `is already owned by an active write handle` (3 comments, unanswered).
- **Orphan writer lock is unrecoverable in practice**: after a kill, every later writer blocks the full
  `waitMs` (the plugin manager passes 120 s) and fails with a message naming only the path — not the
  recorded pid, not a remedy.
- **"Official compaction checkpoint: the loader and the writer disagree on the shadowed range — session
  fails to load (S5 violation)"** — the other borrow candidate, corrupting sessions.
- **"Failed tool call causing session dead lock"**: a rejected tool image result hard-aborts the turn and
  is replayed verbatim on every continue, "This repeats forever". That is the same infinite-loop class as
  FIELD-NOTES §11.6, inherited rather than cured.
- **Native HMR starts replacement activation before asynchronous disposal finishes**, so a plugin holding
  an exclusive resource fails to reactivate.

**And the support surface, measured (VERIFIED via GraphQL search, 2026-09-19):**

| Signal | Value |
|---|---:|
| Total discussions | **7,035** |
| Marked answered | **114** (1.6%) |
| With **zero** comments | **3,095** (44%) |
| Discussions commented in by the top-5 contributors combined | **16** (`tianyicui` 15, `LegGasai` 1, `imccyu`/`CreatixChu`/`kermanx` 0) |

External PRs are refused in writing — "We are sorry that we cannot accept external pull requests at the
moment" — and `CONTRIBUTING.md` says the repo is "an idea, an official showcase, and a source of
inspiration, **but not a mandate from us**." So: you cannot file an issue, you cannot upstream a fix, you
cannot read the PR that broke you, and there is a 1.6% chance anyone answers you. **That is not a
dependency, it is a read-only artifact.**

### A5. R11 is not actually covered — the sandbox has an open, unanswered escape report

The mapping scored R11 **Covered** on OS-level sandboxing. Two community reports (CLAIMED, open,
2026-09-12, one comment each) say otherwise:

- **Sandbox escape via a host route.** An agent read the cookie signing key from plaintext
  `<DSH_HOME>/.credentials.yaml`, minted a cryptographically valid browser-session cookie in-process, and
  called the host's `POST /open-in-app/open` — which runs **unsandboxed, with full user privileges** — to
  launch local applications, including terminal-class entries, and thereby write and delete files outside
  the workspace. Reporter's summary: the restricted process completed the action it was explicitly denied,
  "with no approval prompt and no user interaction".
- **The Linux sandbox's denial detection matches English GNU error strings** (`read-only file system`,
  `permission denied`), so under a `zh_CN` locale `denied` is permanently `false` — and upstream English
  CI can never catch it.

Set against `SAFETY.md`, which the vendor wrote: "experimental developer-preview software… has not
undergone a security audit and must not be treated as secure or production-ready", recommends "a
disposable virtual machine, container, or dedicated environment", and states that sandboxing and approval
controls "do not guarantee isolation". R11 is precisely the requirement that the thing must never touch
his other projects **or his own parallel work in the same folder** — and `workspace-write` confines to the
workspace root, which is exactly where that parallel work lives. Note also FIELD-NOTES §5.1: his own
container was killed for memory *by* the previous run. This is not a hypothetical blast radius.

### A6. Maintenance surface, migration cost, and the exit path

- **Inherited surface:** a 206 MB checkout, a pnpm workspace of ~55 package groups / 128 configurable
  packages, a third-party micro-kernel (Cordis) as the plugin substrate, and a native addon. He would not
  read that; he would depend on it.
- **Version reality:** 22 npm versions in five weeks, **every one a pre-release** (`latest` is
  `0.1.5-rc.2`; `alpha` is `0.1.6-alpha.2`). Never reached 1.0. `README.md`, capitalised by them:
  "**THERE WILL BE COMPATIBILITY-BREAKING CHANGES.**" (VERIFIED at the registry and the API this pass.)
- **Migration cost:** orchestrating through DSH means re-expressing his configured process as Cordis
  plugins (A1), plus building R3, R4, R7's health/fallback, R9's stops and R10 entirely — i.e. he still
  writes the orchestrator, and now writes it in someone else's alpha plugin system with a compatibility
  warning attached.
- **License and data flow — the one place the attack finds nothing.** MIT on both repo and npm package;
  no default vendor telemetry in the generated config catalog; OTel export exists but targets a receiver
  the user configures. Credit where due: adoption would cost him nothing in license or data terms.
- **Exit path:** good, and it is the argument *for* borrowing rather than depending. Mechanisms copied
  out — a `flock` contract, an append-start/append-end-last discipline, a settings-file protocol, an
  NDJSON executor contract — survive DSH's death completely. A runtime dependency on a pre-1.0,
  unauditable, issue-less mirror of a private repo does not.

### A7. The comparative kill, re-verified

| Tool | Stars | Issues open? | Hits the owner's job where DSH does not |
|---|---:|---|---|
| `razzant/claudexor` | **473** | **yes, 75 open** | **R4 + R5 together.** README, verified this pass: "Live subscription-quota tracking — and the opt-in policy that rotates a spent account out of the way on typed vendor limits"; named credential profiles per subscription; "auto-switch at quota limit, and per-window 5-hour/7-day quota bars"; multi-harness across `claude`, `codex`, `cursor`, `opencode` |
| `Yeachan-Heo/oh-my-claudecode` | 39,251 | — | Runs his actual engine natively (R2) |
| `gastownhall/gastown` | 18,116 | — | Cross-session workspace management (R1) |
| `umputun/ralphex` | 1,487 | — | The unattended loop as the product |

A 473-star project with an open issue tracker ships the two requirements he called make-or-break; the
229,704-star one ships neither and cannot accept a patch adding them. His stated bar (R1-18) is "better
in **every** aspect". DSH is better in one layer and absent in the layer that is the job.

### A8. The steelman's own best mechanisms, audited

Fairness requires attacking the borrow list too:

- **The `flock` primitive survives.** The C-level contract is sound and the open reports above are in the
  **TypeScript ownership and orphan-recovery layer above it**, not in `flock(2)`. Borrow the contract and
  the rule ("the lock dies with its holder, no TTL"); do **not** port their `withFileLock`, whose own
  users report an unrecoverable orphan after a kill. `flock(1)` from bash is enough.
- **The compaction *ordering* discipline survives** (append `start` first, `end` last, so a crash leaves
  a detectable orphan rather than a false completion) — that is one line of discipline and the general
  cure for FIELD-NOTES §11.4. **Their compaction implementation does not**: it has an open
  loader/writer disagreement report, and by its own README, "Summarization failure preserves the latest
  durable surface — the auto path logs a warning and **proceeds with full over-budget history**", which
  is the direct negation of R1-08's "guaranteed to happen".
- **`token-meter` does not port.** ~1,200 lines of positional surface pricing wired into DSH's own session
  model. Borrow the *idea* — a measurement that names the durable offset it was computed at — not the code.

---

## Verdict

**BORROW-MECHANISMS.**

DSH is a peer of Claude Code, not a layer above it, and the layer above it is the entire job: verified by
exhaustion, its complete 128-package configuration surface contains no subscription quota, no board, no
cross-session queue, no notification channel, no status command and no stop commands, so more than half
of the eleven requirements would be built from scratch on top of it exactly as they would on top of
nothing. The one door that absence alone would leave open — adopting DSH as the executor component under
his own orchestrator — is closed by DSH's own Claude Code provider being one-shot, unresumable, mute and
unable to answer a question, which means the engines he is contractually required to run (R1-03: GSD,
superpowers, or a custom step list) cannot run through it. What DSH does have that he does not is one
layer down and copies out cleanly at near-zero risk: a kernel `flock` contract whose lock dies with its
holder, the append-start-first/append-end-last discipline that makes "reported success and did nothing"
structurally impossible, a watched settings file that fails loud at boot and keeps last-good on reload,
and a byte-bounded NDJSON executor contract.

**The single piece of evidence that decided it:** the Known Limitations block of
`packages/subagent/subagent-claude-code/README.md` — "One fresh query and process per run — there is no
continuation, resume, pooling, progress stream, or product-session persistence" together with "No human
interaction path — `AskUserQuestion` is disabled, permission prompts are denied … blocking dialogs fail
closed". Missing quota rules out ADOPT-WHOLE; that block rules out ADOPT-AS-COMPONENT as well, because it
proves DSH cannot drive the engine the owner's own requirement obliges him to keep.

**Borrow list, in priority order, with where it lives:**

1. `native/system/docs/flock-contract.md` — the single-run lock contract (the C oracle's behavior table,
   not their TS wrapper). Answers R7's hardest clause and FIELD-NOTES §11.6.
2. `docs/subsystems/compaction.md` — lock ordering: append `start` first, `end` last. General cure for the
   FIELD-NOTES §11.4 / §12.7 class.
3. `packages/settings/settings-file/README.md` — the watched control-file protocol (cross-process writer
   lock, atomic rename, leaf-level diffs, self-write suppression, boot-fails-loud / reload-keeps-last-good).
   That is Д12 and R1-07, already designed.
4. `packages/bundle/headless/README.md` — the executor contract shape (specified byte bounds per string
   and per line, depth cut, uncapped terminal event, exit code by turn-end reason, adoption guard on
   resume). Worth emitting even when the executor is plain `claude`.
5. `packages/llm/llm-pi-ai/README.md` — the route model: named routes, `apiKeyEnv` references never stored
   in config, resolved per request so a change lands on the next request with no restart, refused at write
   time if unservable. R5, designed for him.
6. *Idea only:* a measurement that carries the durable log offset it was computed at (`token-meter`'s
   `logRevision`), so a context reading is replayable rather than sampled off a screen.

**Do not take on:** the runtime, the plugin system, the sandbox as a security boundary, or any dependency
that a `has_issues: false`, external-PRs-refused, pre-1.0, unaudited repository would have to support.

---

## Sources

Re-verified by this pass on 2026-09-19 (everything below was fetched in this session, not inherited):

- GitHub API: `repos/deepseek-ai/deepseek-harness` (`has_issues: false`, `open_issues_count: 0`,
  `stargazers_count: 229704`, `forks_count: 27488`, MIT, created 2026-08-13, pushed 2026-09-17,
  `size: 206488` KB); `releases` (5 most recent, all `prerelease: true`); `repos/razzant/claudexor`
  (473 stars, `has_issues: true`, 75 open, MIT).
- GraphQL discussion search: totals (7,035 / 114 answered / 3,095 zero-comment), per-contributor
  `commenter:` counts, and full bodies of the lock, sandbox, corruption and dead-lock reports quoted above.
- npm: `@deepseek-ai/dsh` — `latest` `0.1.5-rc.2`, `alpha` `0.1.6-alpha.2`, 22 versions all pre-release,
  MIT, 344,017 downloads in the week of 2026-09-12.
- Raw files: `CONTRIBUTING.md`, `SAFETY.md`, `packages/subagent/subagent-claude-code/README.md` (full
  Known Limitations block), `docs/config-catalog.md` (3,945 lines; grepped for quota and notification
  vocabulary).
- Project side: `plugins/harness/docs/FIELD-NOTES.md` §1.1–1.5, §2.1–2.2, §3.3, §4.1, §5.1, §9.1, §11.2,
  §11.4, §11.6, §11.7, §12.1–12.2, §12.7; `product/spikes/harness-rebuild/round-1/ANALYSIS-01.md`
  (R1-01…R1-04, R1-18).
- Prior stages relied on for paths and quotations not re-fetched here: `deepseek-harness-identity.md`,
  `deepseek-harness-mapping.md` (both in this directory).
