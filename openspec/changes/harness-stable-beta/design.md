# Design

## Context

See proposal.md, Why. The requirements come from the owner's interview of 2026-11-24. Each requirement traces to it by opaque IDs: `R<item>.<n>` for his answers, `D<n>` and `S8-<item>` for choices he delegated. Where he handed a choice to the agent, the spec states only his part. The chosen value and its reason are below, each marked "agent decision on the owner's delegation". He can overturn any of them in one line.

`CTX-<name>` marks an item already decided before the interview, listed in the interview context as "already in the harness and staying, not asked" or as decided (for example CTX-untrusted-fence, CTX-grilling-gate, CTX-exact-pid, CTX-wait-for-reset, CTX-label-names). These are not the owner's interview answers. CTX-label-names: the owner left the label names to the agent, provided they are defined and validated; the names used are in D2.

`NAME-DECISION` marks the owner's naming decision of 2026-11-22, made before the interview: keep the plugin id `harness` and show "Harness Orchestrator" as its display name.

The installed 0.6.0 builds the new version. So the build must never break it, its data or its run state.

## Goals / Non-Goals

**Goals:**
- A reliable beta that anyone can install and run on any project (interview 2026-11-24: R27.13).
- The main success flow works end to end after revalidation: pickup, worker, independent validator, engine-checked merge (R30.5).
- The harness does autonomous task execution (R27.17).
- No over-engineering and no perfection. The result is effective, reliable and working (R30.9).
- Agnostic choices: flow system, tracker, runtime and requirements format are configuration, not code.

**Non-Goals:** see proposal.md, Non-goals.

## Decisions

### Rebuild (D38, D40)

Rebuild with deliberate reuse; do not continue 0.6.0 (agent decision on the owner's delegation; interview 2026-11-24).
- **Why rebuild.** The failing parts sit at the centre of the engine: the stall rule, the typed wake-up, the typed reaction to the limit banner, and a state file rebuilt by truncation. The owner's answers replace those same parts. Mandatory steps live only in prompt text. The engine is about 1,900 lines of bash, and its 51 static grep tests give no safety net. Editing the live builder in place risks the tool that builds the new one.
- **Where.** Same repository, same folder `plugins/harness/`, one long-lived branch `harness/next`. It is cut from `origin/main` after this change merges. The engine stays bash with jq, git and gh.
- **Rules on the branch.** The first commit removes the 0.6.0 engine files and adds an empty skeleton. A file returns only if it is on the reuse list, with a behaviour test shown failing once. The branch does not edit shared files until the release PR: marketplace manifest, `tests/run-all.sh`, root README, root CLAUDE.md, `openspec/`. Plugin id stays `harness`. `displayName` becomes "Harness Orchestrator". The version is a pre-release string other than 0.6.0. Requirement text changes only through a PR to `main`, and `harness/next` takes it by merge. Code PRs never edit `openspec/`.
- **Reuse list (closed).** A file not on it needs a recorded decision.
  - Config lookup (project, then user, then default), and the safe-file and path helpers.
  - The ticket queue: GitHub-label and local-file backends, its verbs, and the untrusted fence around ticket text. Every state change removes all other state labels.
  - The two approved hand patches: a new comment per report, and local ticket IDs under a lock.
  - Launcher generation: clean PATH, guarded `cd`, per-role account, fixed session ID, one registry record per session.
  - The model-chain parser (`a|b|c`). Default chains move to config.
  - Graceful close. Force-close is used only as the explicit hard stop.
  - One terminal adapter (iTerm2, tmux). Typing is only a checked fallback.
  - From the limits code: wait for reset, the one-line verdict, "unreadable is unknown, never OK", and the STOP-aware wait. The reader sits behind an interface.
  - Recognition of the limit banner, rebuilt against saved screen fixtures.
  - Pre-trust inside the project only. A password or sudo prompt is never answered; it becomes an owner action.
  - The project-guidance finder, and the GSD helper behind the GSD flow profile.
  - The STOP file, decision log and owner-action log, merged into one append-only run ledger. Every marker carries the run ID.
  - `caffeinate` bound to the watch process, and clean teardown.
  - The never-push belt as one layer of the `safe` profile.
  - The independent validator role and its prompt as starting text.
  - The prompt rules that held: ticket text is data; the finalize commit is the only completion signal; blocked beats guessed; no interactive questions in unattended sessions.
  - The local integration branch per run, with the gate re-run on the merged tree.
  - The grilling gate in `/harness:add`, the readiness floor, the seven command names, and the context-summarizer agent.
  - Config templates with `schemaVersion` raised to 2.
  - Recorded lessons, review findings and field notes, turned into tests, not prose.
- **Drop list.**
  - The stall rule and every typed wake-up.
  - The typed reaction to a limit banner.
  - Agent-written heartbeat files as liveness.
  - The truncated attention file.
  - The terminal device as session identity.
  - The long orchestrator prompt as control flow.
  - Editing the last comment.
  - The model-based spawn check.
  - The three-advisor council.
  - Model and vendor names in engine code.
  - GSD steps in the core prompt and the `gsd | generic` switch.
  - A single-account token read as the only limits source.
  - "Tear everything down after three dead ticks" as the only recovery.
  - The Terminal.app backend.
  - The static grep tests.
  - `docs/DESIGN.md` as a living document.
  - Anything for self-compaction.
- **How the frozen 0.6.0 builds the new one.**
  - **Freeze.** Back up the one installed copy, with a diff against the repo. No plugin update, no reinstall, no version change on `main`, no 0.6.1. Never register the build folder as a local marketplace.
  - **Builder config.** Lanes are cut from `harness/next`. Workflow is GSD. Two workers. Never push. Work stays under `plugins/harness/` and its tests.
  - **Separate state.** The new engine uses its own variable names and one entry script. It never reads the old variables. Its tests run in temp folders against a fake `claude`. New config is schema 2. A run without a stamp is refused and left byte-identical.
  - **Attended tickets.** Tickets about the limit banner, trust dialogs and password prompts are built by the attended session, because the old watch loop reacts to that screen text.
- **Waves.** One run of the builder is one wave of independent tickets. 0.6.0 runs worker and validator, merges into its local integration branch and re-runs the gate. It pushes nothing. The attended build session checks the base, runs `bash tests/run-all.sh`, pushes, and opens one PR per wave into `harness/next`. `main` is merged into `harness/next` at the start of each wave, never rebased.
- **Release.** One PR `harness/next` → `main` carries the new code, the version bump, the display name, an "Upgrading from 0.6.0" section and the migration note. The owner merges it only when no 0.6.0 run is live and the backup is in place. A rollback tag on the 0.6.0 commit needs his yes (OPEN-13). After release, one small PR archives this change.
- **Requirements and GSD.** Implementation runs only through GSD, one milestone in the build clone. Every ticket cites its requirement IDs. Lane gate: `bash tests/run-all.sh` plus `openspec validate --all --strict`.

### Agent decisions on the owner's delegations

- D1 — Fallback trigger for trackers without labels: label first; else map the five states to the tracker's own status; last resort a line `harness:ready` in the text. The trigger's author must be known, or the ticket goes to needs-review (agent decision on the owner's delegation; interview 2026-11-24).
- D2 — Pickup acknowledgement and states: five states (`ready`, `in-progress`, `blocked`, `needs-review`, `done`) with exactly one label at a time. The order at pickup is the write-access check, then claim and comment, then the readiness check. Each finished step is a new comment with a machine line. Step labels are opt-in and off by default. Step names come from the chosen flow, never from the harness. The state label prefix is configurable. Resume checks that the step's real result exists before moving on. Tracker comments are the source of truth (agent decision on the owner's delegation; interview 2026-11-24).
- D3 — One ticket out of turn: label `harness:urgent`. With a free slot it starts at once. With no slot, the newest lane pauses, by default after its current step. One urgent ticket at a time, and the worker cap is never exceeded. It also passes the write-access check (agent decision on the owner's delegation; interview 2026-11-24).
- D4 — Polling interval: default 60 seconds, one key, minimum 30. Waits back off up to 15 minutes on tracker errors. A script polls, not a model (agent decision on the owner's delegation; interview 2026-11-24).
- D5 — Status-change comment: one new comment per state change that needs a reason or a next action. It holds the state change, the reason, the next action and a hidden machine line. Text is English (agent decision on the owner's delegation; interview 2026-11-24).
- D6 — Default ticket content: only the outcome must come from a human. A ticket is ready when the AI can state the outcome, the done-check and the scope, and has no human-only question. The plugin writes four headings: Outcome, Scope, Acceptance criteria, Checks (agent decision on the owner's delegation; interview 2026-11-24).
- D7 — Ticket marked ready but not ready: move it to `blocked`, post numbered questions, take the next ticket. Setting `ask` (default) or `assume` (agent decision on the owner's delegation; interview 2026-11-24).
  - With `assume`, the AI fills gaps itself, lists every assumption in the pickup comment, and blocks only on a question that truly needs a human. The full-autonomy profile may use `assume`; the safe profile uses `ask`.
- D8 — Ticket structure: not required. A readiness check on meaning gates pickup. The AI posts a "Working brief" comment and does not rewrite the description by default. The heading check stops blocking (agent decision on the owner's delegation; interview 2026-11-24).
  - Setting `tickets.normalize`: `comment` (default, the Working brief), `body` (the AI rewrites the description, as the owner suggested; OPEN-INTAKE-4) or `off` (no structured version is written). With `body`, the harness records its own edit so D9 does not read it as a change.
- D9 — Ticket changes during work: the poll script reads new comments. A writer's change enters the work at the next step boundary while the ticket is in progress, and becomes a new linked ticket after done. A non-writer's change becomes a new ticket in needs-review. The mode is configurable: `apply` (default), `new-ticket` or `ignore` (agent decision on the owner's delegation; interview 2026-11-24).
  - The author may choose the reaction for one change with a first comment line `harness:apply` or `harness:new-ticket`.
  - Edits to the ticket description are not a change channel. The harness works from the version it picked up, and one comment asks for the change as a comment.
  - If a person removes the in-progress label or closes the ticket, that lane gets a soft stop.
  - The owner's lean and these points are open for his confirmation (OPEN-INTAKE-2, OPEN-INTAKE-3).
- D10 — When the draft PR opens: after the validator passes, never at first push. Always a draft. Only a profile that may merge marks it ready (agent decision on the owner's delegation; interview 2026-11-24).
- D11 — Merge closes the ticket: yes. A merge confirmed by git sets the ticket to done, but only after every configured post-merge step (release, smoke test) has passed (H-042); until then the ticket stays in progress. A run does not end while a ticket's post-merge steps are pending. On GitHub, `Closes #N` is added too. Setting `close_on_merge`, default true; with false the ticket is set to done and stays open (agent decision on the owner's delegation; interview 2026-11-24).
- D12 — Autonomy profiles: `safe` (default; nothing leaves the machine), `gated`, `draft-pr`, `full`, plus `custom`. No ready-made profile deploys to production. The engine checks the profile before every push, PR and merge (agent decision on the owner's delegation; interview 2026-11-24).
  - A profile holds only gates and permissions. Steps live in the flow config. Fields: `gates` (each step `auto` or `human`), `push`, `pr` (`none`, `draft`, `ready`), `pr_open`, `merge` (`never`, `always`, `classifier`), `post_merge`, `deploy_production`, `remarks` (D15) and `allow_zero_tests`.
  - `safe`: plan, execution, review and verification run locally. No push, no PR and no merge, not even a local integration merge. The ticket ends in needs-review on its local branch. The Verification block goes to the ticket as a comment.
  - `gated`: a human approves the requirements after the readiness check, the plan and the PR. It pushes, opens a draft PR and stops. No merge.
  - `draft-pr`: no human gates until the end. It runs through verification, pushes, opens a draft PR and stops. A human marks it ready and merges.
  - `full`: no human gates. It pushes, opens the PR, marks it ready, handles external review comments if the flow has that step, and merges when all mechanical conditions hold. Then it runs the project's post-merge steps, if any. Any doubt waits for a human.
  - All four have `deploy_production: no`. No profile names "stage". In `custom` the user sets every field, at their own risk.
  - `full` uses `merge: always` with mechanical conditions. The AI classifier is available only in `custom`, because its criteria are not yet known.
  - Migration from 0.6.0: `never_push: true` becomes `safe`, and `never_push: false` becomes `draft-pr`.
- D13 — Comment format: new comments only, never edited or deleted. A visible first line names the role and event, then a short body. A hidden machine line is trusted only on comments from the harness's own account (agent decision on the owner's delegation; interview 2026-11-24).
- D14 — Resume or new session after an answer: the orchestrator decides. Default: resume by session ID once if possible, otherwise a new session with a context pack (agent decision on the owner's delegation; interview 2026-11-24).
  - The order itself is the owner's words: same session by ID in the existing terminal, then a new session, then a fresh terminal last (R18.2). Only the run-time choice and the details below are the agent's.
  - Resume by ID only when the ID is recorded, the transcript is on this machine, the branch and worktree still exist, and the tool supports resume by ID. Resume is tried once. On failure or refusal a new session starts at once, and this counts inside the D21 attempts. The orchestrator may skip the resume when the old session was near its context limit.
  - Context pack for a new session: the ticket text; the whole thread with questions and recorded answers; the branch and worktree path; the current step; the last step-done reports; the old session ID for reference (agent decision on the owner's delegation; interview 2026-11-24).
- D15 — "Passed with remarks": never merges by itself. `remarks: human` below `full`. `remarks: fix` in `full`, with a fresh validator each round and at most 3 rounds (agent decision on the owner's delegation; interview 2026-11-24).
- D16 — Visual reference for the verify-and-prove skill: `auto` uses the mockup if present, a base-branch before/after pair if present, both if both, none otherwise. The proof names the reference used (agent decision on the owner's delegation; interview 2026-11-24).
- D17 — Chosen workflow vs harness flow: one owner per step, and the chosen system wins. Harness extra steps go only before or after it. Other harness rules are hints. Lifecycle gates stay with the harness (agent decision on the owner's delegation; interview 2026-11-24).
- D18 — Custom flow for evaluation: one small flow `custom-eval` with plain prompts, `test-audit`, a low-effort code review and a version bump. `/ship` is tested as a separate case (agent decision on the owner's delegation; interview 2026-11-24).
- D19 — Newcomer explanation: a short README inside the committed harness config folder. The project README is untouched by default. The plugin README gets a "Joining a project that already uses the harness" section (agent decision on the owner's delegation; interview 2026-11-24).
- D20 — Hung ticket and escalation: the engine reports facts (a dead process ID). The orchestrator judges doubts (no hook event for 15 minutes). The options follow a fixed order. Escalate at once on causes only a human can fix (agent decision on the owner's delegation; interview 2026-11-24).
  - The owner delegated this choice to the orchestrator at run time, not to a fixed default. The fixed order is a guard the agent added. Order: leave it (working, waiting for a human, or held on purpose); resume the same session by ID; new session with full context; new session in a fresh terminal; escalate (ticket to `blocked` with a reason, one comment, lane freed, queue continues).
  - Escalate at once when the cause needs a human (a password or permission prompt, a missing secret, an open question), when the same error came twice in a row, or when the D21 attempts ran out.
  - Human-stop signals: a STOP file, a stop comment or label, a ticket label changed by hand, or `/exit` typed by a human in the transcript. The owner doubted that a human stop can always be detected. So the default is to restart unless one of these signals shows the opposite.
  - Hard rules: no wake keystrokes; processes are stopped by exact process ID only (the owner's standing rule in the decided context); one ledger line with the reason for every decision.
- D21 — Retry count and intervals: 3 attempts at 1, 5 and 15 minutes, then blocked. One late attempt after 12 hours. The clock stops during outages, limit waits and sleep. All configurable (agent decision on the owner's delegation; interview 2026-11-24).
  - Deviation from the owner's guess, for him to see: he gave 1, 5 and 50 minutes, asked for a recommendation and said he would accept it. The third wait is 15 minutes. The agent's reason: the three attempts then end in about 21 minutes, inside the one-hour cache window (the link between cache and retries is the agent's inference).
  - These are waits between recovery attempts after a session is confirmed dead or hung. They are not timeouts for a quiet session; a quiet session only makes the orchestrator look (D20).
  - The late 12-hour attempt is not one of the three, and runs only if the run is still alive. When the attempts run out, the ticket goes to `blocked` with a reason and one comment. Both points are the agent's, not the owner's words (OPEN-SESSIONS-2).
- D22 — Outage monitor: inside the watch script, no session. Two plain HTTP checks. Every 5 minutes when up, every 60 seconds when down. One "service is back" message (agent decision on the owner's delegation; interview 2026-11-24).
  - Deviation from the owner's sketch, for him to see: he described a separate terminal with no Claude Code session, a check about once an hour, and about every 30 minutes after a change (his numbers were guesses). The agent puts the check inside the watch script, so there is no third process, and its log can show in its own terminal tab. The faster intervals keep the wait inside the one-hour cache window.
  - During an outage the harness sends no prompts, starts no new sessions, and pauses the D21 counters.
  - "I am back" marker: the first hook event from the orchestrator after the "service is back" message. The message repeats at most 3 times, 2 minutes apart. After that the D23 restart path applies.
- D23 — Dead-orchestrator recovery: the watch script calls the existing resume command. It resumes by ID, else starts a fresh session with the handoff file. At most 3 restarts per hour (agent decision on the owner's delegation; interview 2026-11-24).
  - Two callers run the same restart command: the watch script by default, as the deterministic backstop, and the context watcher if it notices first. The owner's model, in which the context watcher restarts the orchestrator (R3.5), stays. The script is the default caller because a session can itself be dead (OPEN-SESSIONS-4).
- D24 — Compacting the orchestrator and context watcher: no. Claude Code's own auto-compaction handles them. Run state lives in a handoff file written by the engine (agent decision on the owner's delegation; interview 2026-11-24).
- D25 — Stop variants: three soft stops (`soft:step` default, `soft:task`, `soft:ticket`). Two hard stops (`hard:message` default, `hard:now`). An optional own message. Force-send of a queued message uses the "send now" key chord and must be tested locally (OPEN-12) (agent decision on the owner's delegation; interview 2026-11-24).
  - D25a — A soft stop takes no new ticket or step; the sessions only finish what the chosen variant allows (agent decision on the owner's delegation; interview 2026-11-24).
  - D25b — The STOP file applies the default stop, `soft:step` (agent decision on the owner's delegation; the STOP file is kept per proposal.md).
  - D25c — If a session has not parked within 120 seconds of a `hard:message` stop, the stop escalates to `hard:now`. The wait is configurable (agent decision on the owner's delegation; interview 2026-11-24). The owner did not speak about this case, so it needs his confirmation (OPEN-25).
- D26 — Heavy work: a default list of six operation types. One heavy job at a time, and one browser stage at a time. The slot is enforced by the engine. The orchestrator may extend the list but never raise a limit (agent decision on the owner's delegation; interview 2026-11-24).
  - D26a — Worker-cap admission: the same engine-enforced slot mechanism applies to the worker cap. A start takes a slot under one lock, and the slot count is checked inside that lock. When two starts race for the last slot, one gets it and the other waits. Free memory is not checked (S8-21) (agent decision under D37, applying the owner's call for a detailed check in R21.2; interview 2026-11-24).
  - D26b — Concurrency recommendation (R21.6): shown only during configuration and only when usage history exists. With no history, nothing is recommended, and the defaults apply (total 1; stage and heavy limits 1). The owner's value is never changed by a recommendation, because the system must not decide parallelism by itself (context rejected entry 4) (agent decision under D37; interview 2026-11-24).
- D27 — Docker isolation: not raised again now. The guide gets a short multi-worker recipe. The question returns to the owner only after a recorded collision between lanes (agent decision on the owner's delegation; interview 2026-11-24).
  - D27a — Field notes E1 to E3 are not a recorded collision between lanes. A collision needs two identified lanes, one of which damages or blocks the other's ports, containers, network, state or data, and a record that shows it. E1 is one lane's two image builds stopping the owner's own container; the heavy-work slot covers it (D26). E2 hit the owner's default compose project, and the actor is unknown. E3 records no port or state collision, and the source does not say what used up Docker's address pool. So the question does not go back to the owner now, and the trigger stays armed for later runs. A later subnet failure counts when another lane is shown to hold the pool (agent decision on the owner's delegation; field notes E1 to E3).
  - D27b — The multi-worker recipe in the install guide: each lane has its own worktree outside the repository folder, its own compose project name and its own port block. Every compose command names its project, because a command without one lands on the default project. If a stack cannot get a subnet, set a fixed subnet per lane or widen Docker's address pool. This is guide text only; the plugin adds no Docker guard (agent decision on the owner's delegation; field notes E2 and E3).
- D28 — Reading limits: status line data per session and per account. Every window present is read, and none is hard-coded. Default: 90% on any window pauses spawns. The direct endpoint read is an opt-in fallback, off by default (agent decision on the owner's delegation; interview 2026-11-24).
  - The threshold actions are `pause_spawns`, `soft_stop_step`, `soft_stop_ticket` and `hard_stop`. The owner named soft and hard stops (H-110). The agent adds `pause_spawns`, which starts no new sessions and stops nothing, and makes it the default.
  - D28a — Threshold settings merge order: project setting, then personal setting, then the shipped default. This reuses the existing config lookup order (Rebuild reuse list) (agent decision under D37; the owner gave no order in R23.3).
  - D28b — Unreadable limit (R23.6): the reading is recorded as "unknown" in the run ledger and shown as unknown in status, never as OK. "Unknown" never blocks worker starts or ticket work. The reused rule "unreadable is unknown, never OK" applies to reporting only, not to spawn decisions (agent decision under D37; interview 2026-11-24).
  - D28c — Wait for reset (decided context CTX-wait-for-reset, existing behaviour, not restated in the interview): the reused STOP-aware wait from the limits code. The harness waits until the reset time of the hit window, then continues the run with no owner action. A STOP during the wait ends it. Whether the same session is resumed by its ID is OPEN-23 (agent decision under D37).
- D29 — Limit reserve: not an agent decision. The owner sets it himself later (OPEN-15).
- D30 — `-p` vs interactive: interactive by default. `-p` only when five conditions hold: one input and one result; no possible human question; short; a checked file or JSON result; no need to watch. Codex is offered for review stages through `codex exec`. Codex execution is experimental (agent decision on the owner's delegation; interview 2026-11-24).
  - MCP in `-p` mode (answers the owner's MCP worry, R24.3): a normal `claude -p` loads MCP servers, hooks, skills and plugins like an interactive session. The harness never uses `--bare`, and checks at start that MCP servers and plugins loaded.
- D31 — One workflow on Codex and Claude Code: a runtime profile as a data file, and each flow step may name a runtime. Installing GSD for Codex is local setup, not a harness change (agent decision on the owner's delegation; interview 2026-11-24).
  - Start check: for every runtime a flow names, the tool must be logged in and the flow's skills installed for it. If not, the harness stops and prints the install step. It never installs anything itself.
- D32 — Watcher as a launchd service: no launchd in the beta. The orchestrator and the context watcher check the watch script's process ID and restart it (agent decision on the owner's delegation; interview 2026-11-24).
  - Roles: three parts, two of them sessions. The orchestrator is a Claude Code session; it runs tickets and watches workers. The context watcher is a Claude Code session; it and the orchestrator watch each other, and it plays the owner's "context watcher" role. The watch script is a deterministic script with no session; it checks that both sessions are alive, restarts a dead orchestrator (D23) and holds the outage check (D22).
  - When both sessions are down, the watch script runs the D23 restart for the orchestrator, and the orchestrator then restarts the context watcher. When everything is down, the next `/harness:run` or `/harness:resume` resumes the last run without asking. After a reboot or logout nothing starts by itself; recovery begins at the next harness start. This narrows the owner's reboot case (R20.10), so it needs his confirmation (OPEN-27).
- D33 — Skill names: `/harness:config` and `/harness:project-setup`. The old `onboard` and `init` stay one release as aliases. A blind naming test decides ties (agent decision on the owner's delegation; interview 2026-11-24).
- D34 — Isolated tests on the owner's laptop: a separate eval lane. It has its own Claude config folder, its own state root, the plugin loaded with `--plugin-dir`, a clean PATH and scratch targets only. An isolation self-test runs first. At most 2 workers while it runs (agent decision on the owner's delegation; interview 2026-11-24).
- D35 — Deferred limit-banner test: not an agent decision. The owner starts it himself (OPEN-15).
- D36 — Channel connection: one channel contract (`send`, `read_replies`, `check`), wired by `command` or `mcp`. Tokens stay in user-level config. A read-only connections check runs before the build, and owner actions are listed once (OPEN-14) (agent decision on the owner's delegation; interview 2026-11-24).
- D37 — Remaining open questions: decided in this order: the owner's words, then his decided and rejected lists, then the simplest configurable option. Each is recorded as an agent decision and traced by ID. A question goes back to him only if the choice contradicts his words, changes scope, or costs money or accounts (agent decision on the owner's delegation; interview 2026-11-24).
  - D37-INTAKE-1 — The untrusted fence, already in the harness for ticket bodies (CTX-untrusted-fence), also covers any ticket comment text passed on to a session. Comments carry changes and answers into running work (R6.2), so they need the same guard (agent decision taken under D37; see H-018).
  - D37-INTAKE-2 — A new ticket made from a non-writer's change starts in the needs-review state, as D9 states. A writer validates it before normal intake. The starting state was not covered by the D9 delegation, so it is decided under D37 from the owner's words R6.5 and R4.4 (agent decision taken under D37; see H-021).
  - D37-COMMENTS-1 — While an answer from an author who cannot be mapped waits for a writer to revalidate it, the ticket moves to needs-review. This applies the owner's rule for replies with unconfirmed access (R11.3, R4.5) to channel answers; R29.7 itself says only that the answer waits for revalidation (agent decision taken under D37; see H-035).
  - D37-NOTIFICATIONS-1 — Channel identity mapping keys on the sender ID that the channel itself authenticates (for example a Telegram or Slack user ID), set by the owner in user-level config. A sender with no entry, or an entry shared by more than one person, counts as unmapped, so the answer waits for a writer to revalidate it. This applies the owner's rule that an impossible match means review (R4.5) to channel answers; telling several people on one bot apart stays open (OPEN-NOTIFICATIONS-2) (agent decision taken under D37, from a code review finding; see H-122).
  - D37-INTAKE-3 — An accepted change reaches the active worker session as a note at the next step boundary, as D9 states, not at any moment. Delivery timing was an open point of item 6, not part of the D9 delegation (agent decision taken under D37; see H-023).
- D38 — What to reuse: see Rebuild above (agent decision on the owner's delegation; interview 2026-11-24).
- D39 — Past-run findings: Sonnet agents mine past runs once, narrowly. A finding enters only if all hold: it repeated or destroyed work, it fixes an existing step, and it fits the owner's words. It enters as a test scenario, not a feature (agent decision on the owner's delegation; interview 2026-11-24).
- D40 — Rebuild or continue: rebuild with deliberate reuse on `harness/next`. See Rebuild above (agent decision on the owner's delegation; interview 2026-11-24).
- D41 — Optional OpenSpec in grilling: `requirements.format: none | openspec`, default `none`. `requirements.use_in_grilling` defaults to true with OpenSpec. With OpenSpec on, one text block is added to the grilling step. It is read only and never adopted automatically (agent decision on the owner's delegation; he delegated this item without naming who decides, and said he did not know the right answer; interview 2026-11-24). Its default clashes with H-001, see OPEN-1.
- S8-07 — Branch prefix and PR link: branch `harness/<ticket-id>-<short-title>`, prefix configurable. The Verification block goes in the PR. The PR always links its ticket (agent decision on the owner's delegation; interview 2026-11-24).
- S8-08a — Autonomy checks: the engine checks the profile at every step boundary and before push, PR, merge and deploy. Not per tool call (agent decision under D37, unanswered point, item 8; interview 2026-11-24).
- S8-08b — When an AI merge classifier may merge: all must hold. A clean validator pass. More than zero tests, all green. CI green. No open question. No path on the project's "always a human" list. Any doubt waits for a human (agent decision under D37, unanswered point, item 8; interview 2026-11-24).
- S8-09 — Reading production: no plugin step and no plugin ban. It is a project setting (agent decision on the owner's delegation; interview 2026-11-24).
- S8-11 — Does a question really need a human: one cheap step first. The worker tries the ticket, the code and the requirements. A reversible, in-scope answer is decided and recorded (agent decision on the owner's delegation; interview 2026-11-24).
- S8-15 — Where the stage list lives: in the harness flow config only. Project CI and docs are not edited (agent decision on the owner's delegation; interview 2026-11-24).
- S8-16a — "Generic" flow: ships as `basic`, with every step written out (agent decision on the owner's delegation; interview 2026-11-24).
- S8-16b — Flow per project or per person: per person, through a local pointer file. The project may suggest a default (agent decision on the owner's delegation; interview 2026-11-24).
- S8-19 — Context measuring and state re-injection: not built (agent decision on the owner's delegation; interview 2026-11-24).
- S8-20a — Only human-blocked tickets left, standby off: wait without nudges. Setting `on_only_human_blocked`, default `wait` (agent decision on the owner's delegation; interview 2026-11-24).
- S8-20b — State at an immediate hard stop: the engine writes one record per session before closing. Sessions save nothing (agent decision on the owner's delegation; interview 2026-11-24).
- S8-21 — Free-memory check before spawn: no. A fixed worker count plus the out-of-memory rule (agent decision on the owner's delegation; interview 2026-11-24).
- S8-22-25-26 — Docker scope, launchd mode, deny-list format: nothing to decide. They are later, covered by D32, or moved to the project (agent decision on the owner's delegation; interview 2026-11-24).
- S8-23 — Policy risk of the limits endpoint: settled by D28. The endpoint read is off by default in the public build (agent decision on the owner's delegation; interview 2026-11-24).
- S8-24 — Messages between terminals: Claude Code cross-session messaging first. Every instruction carries a short unique id. A send counts as delivered only when the target's transcript records a user turn containing that instruction (or its id), or a reply acknowledging that id. Other transcript growth proves liveness, never delivery. osascript is the fallback. Never wake keystrokes (agent decision on the owner's delegation; interview 2026-11-24).
  - Typing a real instruction through the osascript fallback is delivery, not waking. It goes onto an empty input line, and it counts only under the same correlated proof (agent reading of R18.10 next to R24.2, under D37).
- S8-SESSIONS — Hooks and identifiers (agent decisions under D37, making R19.1 and R19.2 testable):
  - The liveness hooks make no model calls and add no text to the session's conversation. They append short records to a log file that the engine reads. The owner asked only for few credits and little clutter.
  - Besides the terminal identifier the owner named, the orchestrator also records each session's ID, because D14 and D23 resume by ID.
  - Which hook events are used is open (OPEN-SESSIONS-1).
- S8-27 — Four known engine bugs: all fixed, each with a test that fails first. They are the placeholder guard, run IDs in stale markers, closing by process plus session ID, and a single state label (agent decision on the owner's delegation; interview 2026-11-24).
  - Closing and force-closing always target the exact process ID recorded for the session, never a name pattern (agent decision, from S8-27, D20 hard rules and the owner's standing exact-PID rule in the decided context; see H-103).
- S8-28a — Channels: the user sets the priority. With no priority set, the order of setup applies. Gmail is the only e-mail. Seven default events, each switchable: a question for a human; a ticket blocked or sent to needs-review; a ticket taken into work; a ticket done; the run ended or stopped; a limit pause; the orchestrator is down (agent decision on the owner's delegation; interview 2026-11-24).
- S8-28b — Ticket intake through a channel: recommended not in this beta (agent recommendation on the owner's delegation, not a decision; it needs the owner, OPEN-2).
- S8-30 — Temporary vs permanent requirements: permanent = the specs in `openspec/specs`; temporary = changes in flight in `openspec/changes`, here this change's `design.md` and `tasks.md` (build-time rules and agent decisions), ending at archive (agent reading on the owner's delegation; it needs his confirmation, OPEN-5).

## Build-time rules

These are temporary requirements. They guide the build and the evaluation, and they end when this change is archived. Most are not specs. R10.3, R28.10 and R28.11 also appear in specs (H-031, H-124, H-123); here they only add the build-time part.

- R10.3 — Unblock command and label cleanup get careful dedicated tests; a tasks.md test item.
- R16.4 — Pre-release test matrix: GSD under several profiles, superpowers variants, one third-party skill collection the owner named, and one custom flow (design D18, custom-eval).
- R23.5 — Research the Claude Code CLI docs and reuse native features; input to design D28.
- R27.10 — Hands-on, real-user testing of every requirement after implementation; the evaluation programme in tasks.md.
- R27.11 — Failures found in evaluation are fixed at once without over-engineering; big changes are escalated to the owner.
- R27.12 — Evaluation scope: about 10 scenarios across flows, profiles and settings, repeated with shorter re-tests for up to 4 cycles (design D34).
- R27.13 — Release goal: a reliable beta anyone can install and run on any project; stated in proposal Why and design Goals.
- R27.14 — Pre-release installs and test runs happen on the owner's laptop, as isolated as possible (design D34 eval lane).
- R27.15 — Evaluation must not wipe or break the current harness or its data (design rebuild plan D38/D40).
- R27.16 — Evaluation imitates real use across trackers, with an observer terminal that analyses every step's logs.
- R27.17 — Evaluation success criterion: the harness does autonomous task execution.
- R28.10 — Every notification flow is checked in detail during evaluation.
- R28.11 — Before the build, a read-only connections check lists owner-only actions (design D36; owner actions in design Open Questions).
- R29.8 — Comparison runs across flows are evaluation tests, not a user feature.
- R30.1 — All harness requirements go into OpenSpec; this change is that step. The temporary-vs-permanent reading is OPEN (S8-30).
- R30.4 — Verify grilling with and without OpenSpec, with GSD grilling and with the grilling skill of that third-party collection (design D41 release test).
- R30.5 — Release success: the main success flow works end to end after revalidation.
- R30.6 — Sonnet agents mine past runs; the agent revalidates what is worth adding (design D39).
- R30.7 — The current harness builds the new one and must stay unbroken (design D38/D40 rebuild plan, builder freeze).
- R30.8 — The build project uses OpenSpec.
- R30.9 — Build principle: no over-engineering; effective, reliable and working. Goes into design Goals.
- R30.10 — The agent settles remaining open questions and records them as agent decisions (design D37).

## Risks / Trade-offs

- [The builder cannot be rebuilt from git: its hand patches exist only in the installed copy] → freeze it, back it up, no update and no 0.6.1.
- [The old watch loop reacts to screen text about limits, trust dialogs and passwords] → build those tickets attended, keep fixture text in files, and read the watch log after each wave.
- [Inherited environment from the builder (old variables, old scripts on PATH)] → new variable names, one entry script, and an isolation self-test before any work.
- [`main` is public and has no branch protection] → the builder never pushes; only the attended session pushes; branch protection is an owner question (OPEN-13).
- [Long-branch drift] → merge `main` at each wave start; no shared-file edits on the branch.
- [A rewrite loses knowledge] → recorded lessons and field notes become tests; past runs are mined (D39).
- [Reuse turns into patching] → the reuse list is closed.
- [Machine load and the shared subscription limit] → two builder workers; never run an evaluation during a wave; check usage before each evaluation cycle.
- [Cutover replaces the owner's 0.6.0 through auto-update] → release only when no 0.6.0 run is live; old run data is refused, never rewritten; a rollback tag (OPEN-13).
- [Agent decisions are mistaken for the owner's words] → each is labelled as an agent decision, and the spec states only his part.
- [Change watching on a public repository turns outsiders' comments into needs-review tickets] → that is the owner's rule; a later switch for non-writers may be wanted.

## Open Questions

- OPEN-1: H-001 (orchestrator-workflow) fixes the default as GSD plus OpenSpec, but R30.3 makes OpenSpec optional and agent decision D41 defaults the requirements format to none; R16.6 has setup recommend the flow already in use. H-001 is not rewritten here; new requirement text states no default, and the clash goes to the owner.
- OPEN-2: Ticket intake through a notification channel (R28.8, S8-28b) clashes with rejected entry 8. Recommended: not in this beta. Needs the owner.
- OPEN-3: R17.9 rests on hedged words: the owner said the harness most likely stops hard. The stop when no local config is selected must be ratified by the owner.
- OPEN-4: The verify-and-prove skill: opt-in or opt-out. R14.1 carries both readings: the skill runs only if the user wants it, and it is recommended by default and the user can refuse it.
- OPEN-5: The reading of temporary versus permanent requirements (S8-30): permanent = the specs in openspec/specs; temporary = changes in flight in openspec/changes, here this change's design.md and tasks.md. Needs confirmation.
- OPEN-6: A /harness:feedback command that files problems as untagged issues was mentioned (outside the numbered items), and the owner called it a separate matter. Beta scope is open; no requirement is written.
- OPEN-7: Where the local config selector file lives, whether it is git-ignored, and what the owner meant by configs that also live remotely (item 17 open point).
- OPEN-8: Permission prompts (R26.3): how an optional plugin answer to prompts fits with R26.4, under which the permission mode is the user's own matter, and whether the plugin keeps setting the bypass mode by default.
- OPEN-9: Whether standby is a start parameter or a config setting (R3.2). Proposed by D37 rule: a config setting with a run flag override.
- OPEN-10: Name and trigger form of the unblock command (R10.2, R10.4) are not chosen; to be set by the agent under D37.
- OPEN-11: Where the email-to-account identity data comes from for external trackers and for Slack, and how several people on one bot are told apart (R4.5, R29.9 open points).
- OPEN-12: Force-send of a queued stop message from scripts (D25, Ctrl+X Ctrl+S via osascript) is untested; hard:message depends on a local test before release.
- OPEN-13: Build-time owner questions (tasks.md, not specs). Recommendations are the agent's.
  1. Who merges wave PRs into `harness/next`? Recommended: the build session, after the validator passes, `bash tests/run-all.sh` is green and the external review is answered. Until the owner answers, he merges every wave PR. Wave 1 can start either way.
  2. May the redacted field notes, and the root CLAUDE.md section that points to them, go onto the build branch? Or should the open docs PR merge first? The repo is public.
  3. May branch protection be switched on for `main` (pull request required, no direct push, no force-push)? Recommended: yes, before the build starts.
  4. May one private throwaway repo be created for GitHub intake tests? Needed later, not for the first tickets.
  5. Release version string: `1.0.0-beta.1` (recommended) or `0.7.0`. Nothing is published without the owner's yes.
  6. May a rollback tag be pushed on the 0.6.0 commit before release? Recommended: yes.
  7. A 0.6.1 with the two hand patches for today's users? Recommended: no. It would replace the frozen builder.
  8. May an empty leftover branch with no commits beyond `main` be deleted?
- OPEN-14: Owner-only channel setup actions before the build (D36): create the Telegram bot, pick the Slack chat and route, confirm the Gmail address, put tokens in user-level config.
  - The Telegram bot needs the first message from the owner, because a bot cannot write first.
  - The Slack route is a bot token or an existing Slack MCP server.
  - The first real message per channel is sent only in the evaluation run.
- OPEN-15: Kept by the owner, not decided by the agent: the limit reserve value (D29) and starting the deferred limit-banner test (D35).
  - Also left to the owner or the project: the per-project worker count, and safety rules 3 to 6.
- OPEN-16: Unresolved tensions not voiced to the owner (interview 2026-11-24, conflicts list): retry intervals vs rejected entry 5 (fixed timeout ladder); automatic cap lowering vs rejected entry 4; Codex support vs rejected entry 2 (must stay a config profile, per D31). Also: no flow system or runtime name hard-coded in the plugin (rejected entry 2) vs H-001 fixing GSD as a default (OPEN-1) and D30 naming `codex exec`; and "one process per config, never mixed" (context.md) vs D17 (harness extra steps before or after the chosen system) and R15.5 (custom steps between steps).
- OPEN-17: Setup flow recommendation (R16.6): does setup recommend any flow the person already uses, or only an existing flow that is also tested? The owner's words carry both readings (interview 2026-11-24, item 16 open point).
- OPEN-18: What "profile" means next to the flow configuration (R15.15). The flow config is separate from the profile, but the meaning of "profile" in that answer is not defined (interview 2026-11-24, item 16 open point).
- OPEN-19: Codex depth (R24.5, R24.6): how far execution on Codex goes beyond "experimental" (D30), and what the Codex profiles contain (interview 2026-11-24, items 24 and 30 open points).
- OPEN-20: What the harness does when a technology or skill that the flow names is missing at start (R17.6). The owner said only that the harness checks the list. D31 gives the agent's answer for runtimes and their skills: stop at start and print the install step, never install. It needs the owner's confirmation, and other missing technologies are not covered.
- OPEN-21: A channel answer whose author maps to a known person who has no write access (interview 2026-11-24, item 29 open point). R11.3 moves a tracker reply from such a person to needs-review; the owner did not say whether the same holds for channel answers.
- OPEN-22: Whether the context watcher is exempt from the close-when-done rule (R27.5; item 27 open point).
- OPEN-23: Whether sessions resume by their own session IDs after sleep, a crash or a reboot (R20.10; item 20 open point).
- OPEN-24: How the custom stop message is delivered to the sessions (R20.4; item 20 open point). The agent's interim answer in D25: an own message on any stop replaces the standard stop text and travels the same way as that stop. The force-send part depends on OPEN-12. It needs the owner's confirmation.
- OPEN-25: What the harness does when a session ignores a hard stop message. The agent's interim answer is D25c: escalate to `hard:now` after 120 seconds. It needs the owner's confirmation.
- OPEN-LIMITS-1: How an out-of-memory container stop is confirmed before the worker cap is lowered (R21.3; item 21 open point).
- OPEN-LIMITS-2: Whether the lowered worker cap lasts only for the current run or persists into later runs or the project configuration (R21.3; item 21 open point).
- OPEN-LIMITS-3: The exact trigger for the deferred limit-banner test (R27.4; item 27 open point). The owner's intent is that an approaching limit prompts it, and he will tell the builder to plan around the current limits. Starting the test stays with the owner (OPEN-15).
- OPEN-LIMITS-4: What happens to the task whose container stopped for lack of memory when the cap was above 1: restart, requeue or block. The owner spoke only of the cap-1 case (R21.3).
- OPEN-LIMITS-5: How the usage history helps with the 5-hour limit (R23.4, R21.6; item 23 open point).
- OPEN-VERIFICATION-1: Whether the harness ever calls the verify-and-prove skill when no workflow names it (interview 2026-11-24, item 14 open point). Opt-in versus opt-out is OPEN-4.
- OPEN-VERIFICATION-2: Whether the sum check (passed + failed + skipped = total) switches off together with the test-count check when a profile allows zero tests. The owner accepted the sum check only through a yes to the feature as read (interview 2026-11-24, item 13 open point).
- OPEN-VERIFICATION-3: The Verification block parts other than the checks (ticket and session ID, verifier and verdict, proof and gaps) rest only on the owner's yes to the feature as read. Interviewer-invented questions X8 to X11 overlap these parts and create no requirement. How the block shows a listed check that was not done is not decided either (interview 2026-11-24, item 12 open point).
- OPEN-VERIFICATION-4: External-review configuration modes are not chosen beyond two: react by default, and off when a setting says so (interview 2026-11-24, item 15 open point).
- OPEN-VERIFICATION-5: "Passed with remarks" (R13.5). The maximum-autonomy behaviour (the agent fixes the remarks, then the change merges once everything is OK) was given as the likely behaviour, not a firm decision. The context recommendation that remarks never merge by themselves conflicts with it and is not decided. A line that hands the change to a human in the other case was added by the interviewer, and the owner confirmed it as a restatement (R13.6). The other case is ambiguous: below maximum autonomy, or when the agent cannot fix the remarks. Whether a change fixed after "passed with remarks" needs a new validator pass is open. D15 is the agent's interim answer to all of these and needs the owner's confirmation.
- OPEN-VERIFICATION-6: Whether a project flow configuration may switch off the browser check for UI changes (R15.14), given that steps can be switched off or skipped when something else does them (R15.3, R15.4).
- OPEN-INTAKE-1: Whether a bot account with its own write access needs an allow-list before it may queue tickets (interview 2026-11-24, item 4 open point; not discussed). The context recommendation "bots never unless allow-listed" is not a decided item. H-008 accepts such a bot through its write access until the owner answers.
- OPEN-INTAKE-2: The default reaction to a change that arrives late in the work (R6.7, R6.8; item 6 open point). The owner leaned towards allowing a return to execution at any stage, including after the last status, but said he may be wrong. D9 departs from that lean on purpose: after done, a writer's change becomes a new linked ticket by default. D9 also lets the author mark the reaction in a first comment line. Both are agent answers that need the owner's confirmation.
- OPEN-INTAKE-3: Whether edits to the ticket description during work count as changes (interview 2026-11-24, item 6 open point). The owner said changes come through comments so the author is known (R6.2), but he did not speak about description edits. D9 gives the agent's answer (description edits are not a change channel), which needs his confirmation.
- OPEN-INTAKE-4: Where the AI's structured version of a ticket goes (R5.5). The owner suggested that the AI corrects the description itself. D8 instead keeps the original description and posts a "Working brief" comment. This departs from his words, so under the D37 rule it needs his ratification.
- OPEN-INTAKE-5: How the reaction to a ticket marked ready but not ready varies by autonomy level (R5.7; item 5 open point). D7 gives one default (`blocked` with numbered questions) and an `ask` or `assume` setting. It ties them to autonomy only loosely: the full-autonomy profile may use `assume`, and the safe profile uses `ask`. This is the agent's answer and needs the owner's confirmation.
- OPEN-SESSIONS-1: Which Claude Code hook events the liveness hooks use (R19.1; item 19 open point). The owner asked only for simple, low-cost hooks with little clutter.
- OPEN-SESSIONS-2: Whether the late 12-hour attempt counts as one of the three recovery attempts, and what happens when the attempts run out (R18.5; item 18 open points). The owner said the 12-hour attempt applies only if the harness still runs. D21 keeps it outside the three and moves the ticket to `blocked`; neither point is his words.
- OPEN-SESSIONS-3: Whether Claude Code has a built-in way to resume when the service returns (the owner believes it has none), and whether the orchestrator really stops when the internet drops (R18.7 conditions). The outage monitor is needed only in the first case, and its internet check only in the second. D22 asks to test the retry watchdog setting before relying on it.
- OPEN-SESSIONS-4: Who restarts a stopped orchestrator, and which component is the "context watcher" (R3.5; item 3 and item 25 open points). The owner's model has the context watcher restart the orchestrator. He also raised the risk that nobody restarts a stopped orchestrator, and said he did not yet understand the split between the watcher and the orchestrator. D23 and D32 settle it as agent decisions (a deterministic watch script as backstop); this needs his confirmation.
- OPEN-26: Whether comparison runs across flows ever become a user-facing feature (R29.8; item 29 open point). In this beta they are evaluation tests only.
- OPEN-27: Recovery after a reboot (R20.10, R20.11). The owner agreed that the harness resumes the last run after a reboot without asking. D32 starts nothing by itself after a reboot or logout; recovery begins at the next `/harness:run` or `/harness:resume`. This narrows his point and needs his confirmation.
- OPEN-DISTRIBUTION-1: Which item the project setup skill must not set up (R27.9; item 27 open point). The owner excluded one item, and reading it as the flow system (GSD) is an interpretation.
- OPEN-DISTRIBUTION-2: Which working name, "config" or "setup", goes with which skill (R27.7; item 27 open point). The jobs come from R27.8 and R27.9. The final names are agent decision D33.
- OPEN-NOTIFICATIONS-1: When clarification ends (item 29 open point). The harness asks again after a reply that is not enough (R28.5), but no limit on the rounds is set.
- OPEN-NOTIFICATIONS-2: Identity mapping beyond the Telegram example (R29.9). Same question as OPEN-11: where identity data comes from for Slack and Gmail, and how several people on one bot are told apart.
- OPEN-NOTIFICATIONS-3: Ticket intake through a channel (R28.8). Same question as OPEN-2. Until the owner answers, channels do not create tickets.
- OPEN-NOTIFICATIONS-4: Whether the first answer still wins when its author cannot be mapped or has no write access, and whether a later answer from a writer may then replace it (R29.5 next to R29.7). Related to OPEN-21.
- OPEN-NOTIFICATIONS-5: The role of a remote session mode next to the channels as a fallback contact path (R28.6; item 28 open point). The owner did not say what it adds.
