# Proposal

## Why

The `harness` plugin (display name "Harness Orchestrator") is at 0.6.0 "(beta)". It finished long unattended runs, but its record shows repeated failures. A working session was read as stalled, and a dead orchestrator went unnoticed for hours. Typed text never arrived. A merge reported success and did nothing. The limit meter read the wrong account or nothing at all. Mandatory steps lived only in prompt text and were skipped.

The owner's interview of 2026-11-24 fixed the features of a stable beta. The goal is a reliable beta that anyone can install and run on any project (interview 2026-11-24: R27.13). The plugin is rebuilt with deliberate reuse of the parts that proved themselves, not patched in place (delegated decisions D38, D40). This change holds the requirements for that beta.

## What Changes

- **Intake and tickets:** a label on a tracker ticket starts work, picked up on the next poll by a script. Only people with write access may queue work. Unknown access counts as read-only. A readiness check on meaning runs at every pickup. One ticket can run out of turn. A writer's comment can change a ticket in progress.
- **Tracker comments:** every role adds new comments and never edits old ones. Exactly one state label per ticket. Questions to humans go to the ticket, and only a writer's reply resumes it. A writer can unblock a ticket. The harness records who answered.
- **Autonomy and git:** every step can be autonomous or a human gate. Ready-made autonomy profiles plus a custom one. The default is safe: nothing leaves the machine. Push, draft PR, merge, merge confirmation by git and production deploy are each gated by the profile. Release to stage is a per-project setting for projects that have a stage. No ready-made profile deploys to production.
- **Verification:** an independent verdict is required before any merge. At least one test must exist and all must pass, unless a profile allows zero tests. Every PR carries a Verification block with the checks actually done. External review bots are handled. An optional verify-and-prove skill is installed separately.
- **Flow and configuration:** any flow system is supported, with one owner per step. A flow config is separate from the autonomy profile. Configs may live in the repo, and a local file selects one. Codex can run steps through a runtime profile. With nothing configured, the default is the GSD flow with OpenSpec, and the person confirms it once, in the configuration skill or at the first start. The confirmation can be saved in the user settings, and a project setting beats a user setting. An unattended run with no confirmation stops and raises an attention notice. OpenSpec stays optional.
- **Run lifecycle:** a run ends when all tickets are done. Standby is a setting. Soft, hard and custom stops exist; the default is a soft stop after the current step. Recovery after sleep or a crash is automatic by default.
- **Sessions and liveness:** interactive terminal sessions are preferred. Instructions go as messages between sessions, with osascript as the fallback, and nothing is ever typed to wake a session. Liveness comes from hooks, transcripts and process IDs. A hung session is resumed by ID first. A small script watches for service outages and restarts a dead orchestrator.
- **Limits and resources:** the user sets the worker cap (default 1), and the engine enforces it. A confirmed out-of-memory stop lowers it by one. Heavy work has its own limit. Subscription limits are read for every added account, in every window it has. Thresholds are optional and set by the user, one per window, and a project may set its own. Setup offers 90% for every window. The action at each threshold is configurable. An unreadable limit does not stop work.
- **Notifications:** Gmail, Telegram and Slack are optional channels that mirror the tracker. They have a user-set priority and fall back in that order. Answers are written back to the tracker with their author. The tracker stays the source of truth.
- **Distribution and setup:** the plugin id stays `harness` and the display name is "Harness Orchestrator". It ships a short install guide and two setup skills: one configures the harness, one prepares a project for AI development. It also has a "tested with" list and a note for newcomers who join a project that uses it. `/harness:feedback` files a problem report as an issue in the plugin's own repository, with technical context and no private data, after the person reads the text and says yes. A release checklist is run before every release: the real terminals (tmux and iTerm2) with the real runtime, plus the main success flow.
- **Owner review-page answers (2026-11-26):** the harness checks whether a repository has an automatic PR reviewer and waits for it, or waits a short fixed time when there is none (H-145 to H-147). Every terminal action is checked after it is done, with a cheap model role where no exact proof exists (H-148). A confidence log by terminal and runtime version sets how deep the checks go (H-149). Steps and checks name a model role, not a model (H-150). Every start checks that the settings profile still matches the machine (H-151). The first setup studies the machine and asks at most five questions (H-152), and a separate evaluation proves it (H-153). A readiness check skill tells whether the settings can work on every runtime (H-154). A missing skill can be set up after a yes (H-073). The Codex parity and routing answers are in the change `harness-codex-parity`, planned for the next release.
- New requirement IDs run from H-002 to H-154 and continue after H-001. They are never reused.

## Capabilities

### New Capabilities
- `harness/intake-and-tickets`
- `harness/tracker-comments`
- `harness/autonomy-and-git`
- `harness/verification`
- `harness/flow-and-configuration`
- `harness/run-lifecycle`
- `harness/sessions-and-liveness`
- `harness/limits-and-resources`
- `harness/notifications`
- `harness/distribution-and-setup`

### Modified Capabilities
- `harness/orchestrator-workflow`: H-001 states the default when nothing is configured (the GSD flow with OpenSpec), its single confirmation in the configuration skill or at the first start, the user and project levels, and the stop of an unattended run with no confirmation (owner decision 2026-11-26; design.md D37-FLOW-4, D37-FLOW-7).

## Non-goals

Not in this beta. These come from items the owner answered "no" or "later", from entries he rejected earlier, and from agent decisions that keep something out.

- Per-lane Docker isolation: later. The agent raises it again only after a recorded collision between lanes (interview 2026-11-24: R22.1, R22.2; delegated decision D27).
- Measuring the context window, setting compaction at start, or re-injecting ticket state after compaction: no. Claude Code handles compaction (R19.3; D24, S8-19).
- The harness compacting the orchestrator or the context watcher: the owner leaned no, and agent decision D24 keeps it out (R19.4; D24).
- Plugin-level deny lists or guards for secrets, force-push or destructive Docker commands: no. These are the project's own configuration (R26.4, R22.3).
- Plugin limits on who pushes or where: no. Such limits live at project level (R26.5).
- Managing which MCP tools a session gets: no (R26.6).
- Scrubbing secrets from transcripts: no. It is each project's or person's own setting (R26.8).
- Helping people tune their own setup for the harness: later, as a to-do (R26.7).
- Support for other agent harnesses beyond Claude Code and Codex: later (R24.8).
- Interactive Codex sessions: not in this beta, by agent decision D30. Codex execution is experimental until a comparison run passes (D30, D31). The owner's answers of 2026-11-26 ask for Codex at the same level as Claude Code; they are in the change `harness-codex-parity`, planned for the next release.
- Production deploy in any ready-made profile: no. A user's own profile may allow it at their own risk (R9.1, R9.2).
- A built-in production read step: not in the plugin, by agent decision S8-09. Reading production is a project setting.
- An absolute "never deploy to production" rule in the plugin: no (item 9).
- Client- or project-specific rules in the harness requirements: no (R9.6).
- The space-nudge patch, and any typed keystroke that wakes a session: no (R27.3, R18.10).
- A free-memory admission check before starting a worker: not in this beta, by agent decision S8-21.
- The harness choosing the number of workers by itself: no (rejected entry 4).
- A fixed timeout ladder for silent sessions: no (rejected entry 5).
- A watcher installed as a macOS launchd service: not in this beta, by agent decision D32.
- A third terminal or session that watches the tracker: no (R3.3).
- A comment command as a trigger: no. Only a label (or its fallback) triggers pickup (R1.2).
- A separate intake command besides `/harness:add`, and a Slack intake agent: no (rejected entry 8).
- Generic SMTP e-mail: not in this beta, by agent decision S8-28a. Gmail is the only e-mail channel.
- Comparison runs across flows as a user-facing feature: no. They are an evaluation test only (R29.8; owner decision 2026-11-26).
- Adopting an existing open-source orchestrator instead of this plugin (rejected entry 1).
- Binding the harness to one flow, or hard-coding a vendor or model name in plugin code (rejected entry 2).
- Mixing a ready-made and a custom process in one flow config (rejected entry 3).
- Container isolation as a security boundary (rejected entry 6).
- Universal checks for all work, such as "everything must have tests" (rejected entry 7). Zero tests stay possible by profile.
- Harness requirements inside product repositories (rejected entry 9). Configuration files are allowed.
- Anything about a separate work-ticket orchestrator outside this plugin (rejected entry 10).
- Renaming the plugin id. It stays `harness`.

## Impact

- `plugins/harness/` is rebuilt on the long-lived branch `harness/next`, cut from `main` after this change merges. Code returns only from a closed reuse list (design.md, Decisions, rebuild).
- `main` keeps `plugins/harness` at 0.6.0, unchanged, until one release PR from `harness/next`. The owner merges that PR.
- The release version is `1.0.0-beta.1`. A rollback tag, `harness--v0.6.0`, is pushed on the 0.6.0 commit before the release PR. There is no 0.6.1. The release PR carries the display name, an "Upgrading from 0.6.0" section and the migration note this repository requires, so users update with `/plugin update`.
- Kept for users at release: plugin id `harness`, the `/harness:*` command prefix, the `harness:*` label prefix, user and project config, and the STOP file. Old run data is never deleted or rewritten.
- `openspec/specs/harness/orchestrator-workflow` takes the H-001 delta at archive. The new capabilities join it under `openspec/specs/harness/` at the same time.
