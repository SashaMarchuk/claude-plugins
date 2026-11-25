# Changelog — harness

## Unreleased — rebuild on harness/next

- The 0.6.0 engine (scripts, commands, agents, skills, templates, design doc and static tests) is removed on this branch. Parts return only from the reuse list in the stable-beta design, each with a behaviour test shown failing first. The 0.6.0 code stays readable on `main`.
- New empty skeleton: manifest with display name "Harness Orchestrator" and pre-release version `1.0.0-next.0`, one entry script `bin/harness`, an isolation self-test, and a test runner that uses a scrubbed environment and a fake `claude`.
- Ticket queue (`harness tickets <verb>`, `lib/tickets.sh`): GitHub-label and local-file backends with the verbs bootstrap, ids, list, show/render, fence, add, claim, comment, block, review, release and done. Ticket text, titles and comment text reach a session only inside the untrusted fence (H-018). Every report is a new comment (H-024). Local ids are allocated under a lock (H-017). Every state change leaves one state label (H-030). Settings use `HO_TICKETS_*`, `HO_STATE_PREFIX` and `HO_TICKET_LOCK_*`. Tests use a stateful fake `gh`.
- Config and run state (T4): config lookup (project, then user, then default) with `schemaVersion: 2` required, safe-file and path helpers, schema 2 templates, stamped runs, an append-only run ledger, and markers that carry the run ID. A run folder without a stamp, such as a 0.6.0 run, is refused and left byte-identical.
- Flow profiles (T8, H-064): `flows/gsd` and `flows/basic`, each with the full ordered cycle; thin `worker` and `validator` role prompts in `prompts/`; `harness flow list | check | steps | render`. Placeholders are `@NAME@`; rendering is one literal pass, and a placeholder with no value fails the render. No flow-system name in engine code (D37-FLOW-1).
- Wave-1 review fixes: a failed `gh` or file step makes every ticket verb exit non-zero with no `OK` line (GitHub `block` no longer reports a lost reason comment as done). An unreadable ticket or input file is refused (exit 74) and never rewritten; local writes go to a temp file first. Local ids are read in base 10 with at most 9 digits, so `08-x.md` is ticket 8. The run folder is resolved physically, so a symlinked path still finds STOP. A signal during a ledger append frees the lock and exits (130, 143 or 129). `config get` with no key exits 64 with usage.
- Sessions (T7, `harness session <run-dir> launch|close|list`, `lib/sessions.sh`): launcher generation with a clean PATH (absolute entries only, no folder that holds a 0.6.0 script), a guarded `cd`, a per-role account and a fixed session ID. Each launch writes one registry record with the run ID, process ID and session ID; the terminal handle is kept for addressing only (S8-27). Sessions start interactively in a terminal (H-100). A wrong role, account or folder fails before anything is written. Graceful close types the runtime's exit command into that session's own terminal and waits for its exact process to end; a busy session is left open, never forced. Close refuses a session recorded under another run, and a session whose process is gone is only marked closed (H-103, PR-3). The launch command comes from `runtimes/claude-code.json`, selected by `runtime.main` (D37-RUNTIME-1). Accounts come from the user config only.
- Terminal adapter (`lib/term.sh`): one interface with two backends, iTerm2 and tmux, tested against fakes. The Terminal.app backend is dropped. The tmux backend uses its own server (`tmux -L ho-harness`) and checks that a pane belongs to this run before it types into or closes it. A close reaches a session through the backend recorded at launch, and the launcher starts no new model attempt once a close is under way.
- Wave-2 review fixes: close and send check that the tmux pane or iTerm2 tab still carries the session's tag, in the same terminal call that acts, so a pane ID reused after a tmux server restart never reaches another session (H-103, S8-27); a skipped pane close is recorded with its reason. The iTerm2 backend tags its sessions and reuses a stored window only while it holds a session of this run. A role must equal one role of the list (`worker validator` is refused before anything is written). `session list` shows the running process after a model fallback. `flow render` accepts only a numeric `TICKET_ID` and refuses DEL, U+0085, U+2028, U+2029 and bidi controls in one-line values.
- Wave-2 review round 3: the pane or tab tag is new for each launch (record field `term_tag`), so a resumed launch of the same session ID is never reached by a close of the earlier launch; `launch --resume` is refused while a record of the run with that session ID is not closed. Every iTerm2 call addresses its session by unique ID (`whose unique ID is`) and its window by `whose id is`, and re-checks the tag inside the same `tell` before it types, reads or closes. The test fake of the runtime leaves only on a whole `/exit` line.
- Wave-2 review round 4: each pane or tab also carries the session ID (tmux pane options `@ho_tag` and `@ho_session_id`, which replace `@ho_session`; iTerm2 variable `user.ho_session_id` beside `user.ho_run` and `user.ho_session`), and every send, key, capture and close checks the run, the tag and the session ID in the same call that acts. So a record that names another session's handle and tag does not reach that session. Close also checks, before it types, that the PID file names the record's session ID and process ID. tmux capture now checks and reads in one call. iTerm2 open takes the new session from a before/after list of IDs instead of the created tab, which is a position; with not exactly one new ID it tags and closes nothing and fails (exit 70). A pane or tab opened by the round 3 code has no session ID tag, so it cannot be closed by this code.
- Liveness (T12, H-090, H-099, `lib/liveness.sh`): `session <run-dir> status [name]` prints one JSON line of facts per session: `working`, `starting`, `dead`, `closed` or `unknown`, the process, and the transcript path, age and size. The verdict comes from the exact process and its session ID only. A session that has been silent for hours with a live process reads as `working`; the engine judges no quiet session (D20). A dead process turns the record `dead` once, with one ledger line. The gap between two model attempts reads as `starting`, and a process table or record that cannot be read gives `unknown`, never `dead`. `session <run-dir> read <name> transcript|screen [--lines N]` prints the tail of the session's transcript (found by its session ID under the root the runtime file names) or its screen, inside an untrusted fence; a line the session wrote that names the fence gets a `[session-text]` prefix, so it cannot close the fence. Nothing is typed. A record left `launching` by a killed launch command reads from its process first, so a live session never reads `dead`. A test scans the engine, the terminal adapter included, and finds no code path that types a key to wake a session; the stall rule, typed wake-ups and heartbeat files stay dropped.
- Slots (T16, H-104, H-105, H-107, D26, D26a, `lib/slots.sh`): `run new --workers N` sets the worker cap for the run, beating `limits.workers` in the config; the default and minimum are 1. Limits are fixed in `<run>/limits.json` at run start. A worker launch takes a worker slot under one lock and counts again after its write, so two starts racing for the last slot give it to one; the other gets exit 73 and nothing is opened, or waits with `--slot-wait SECONDS`. Close or a dead session gives the slot back. A session reads `dead` only when every process recorded for it is gone (the launch command, the launcher and the session process, each by PID and start time); the age of a record never frees a slot, so a launch may wait with `--slot-wait` or for its account command for as long as it needs. Before a dead holder's slot is freed its close flag is written, so a launcher that had not started yet starts nothing. A process counts as gone only on proof: `ps` shows its PID with another start time, or the kernel answers "No such process" to `kill -0`, or the launcher recorded its end (`.ended`, `.failed`); anything else reads `unknown` and keeps the slot, so a narrower process view never frees a live worker's slot. `session close` follows the same rule: with no readable process table, or a session process it can neither see nor prove gone, it changes nothing and exits 71. A stop recorded during `--slot-wait` ends the wait (exit 75). The owner can free the worker slot of a holder that reads `unknown` with `slot release worker --holder NAME --force`, at a terminal only, with a ledger line. The recorded transcript folder follows the account's `HOME` when its command sets one. A failed launch gives it back only when its session reads `dead`: a session that came up at the boot timeout, or after a late failed open, holds the slot while its process runs. `harness slot <run-dir> acquire|release heavy --op TYPE` holds the one heavy slot for the six shipped heavy types (`limits/heavy-ops.json`), and `acquire|release stage:<id>` holds a stage slot (`browser` and every other stage default to 1). `heavy-add TYPE REASON` adds a heavy type for the run; limits are never read from that list. No free-memory check (S8-21).

- Screen text (T14, `harness screen <run-dir> classify|watch|pretrust|wait`, `lib/screen.sh`): recognition only, against saved screen fixtures in `tests/fixtures/screen/`. The engine recognises the subscription-limit notice (H-113), the folder-trust dialog and a password or sudo prompt, and it types nothing and sends no key for any of them; the typed reaction of 0.6.0 is dropped. The patterns live in their own data file that the runtime profile names (`runtimes/claude-code.screen.json`), so engine code holds none of them (D37-RUNTIME-1) and nothing else needs to be opened to read the profile. A line matches only as a whole line of the tool's own block, and the line has to open that block, so a session's own prose that quotes, wraps or summarises a notice does not match (field notes F1 and I2). The limit notice is the strictest shape: a closed set of lead-in words, and its reset line in the same block. The trust dialog needs its option line; the dialog and the prompt still allow bounded free text around the phrase, so a false match there is possible and costs one owner-action line. A recognised notice is recorded once per screen and leads to the reused STOP-aware wait for the reset time the limits reader gives; the reset time never comes from the screen, an unknown reset keeps waiting instead of continuing, and a later look at the same screen waits again until that screen reached its reset (H-114, D28c, PR-5, PR-8). A trust dialog and a password prompt become one owner action in the run ledger and are never answered. Pre-trust needs the person's consent: the project folder must already be trusted in the runtime state file the session uses. Only then is a working folder inside the project, or in a genuine worktree of the project's own repository, trusted before launch; the project folder itself is never written. Without consent nothing is written, the launch stops (exit 77) and one owner action asks the person to open the project once in the runtime and accept its trust question (PR #97 review). Writes take one lock and skip a folder that is already trusted; the worktree check clears the git repository variables and needs the project's own common git folder. The trust record and its file come from the runtime profile, never from a project config (D37-FLOW-8). A session that runs on its own account is not pre-trusted, because its account command may move the runtime config folder; that is recorded and the runtime's own trust hold applies (D37-SESSIONS-5). A reset of 0, with a leading zero or beyond the 64-bit range is refused (exit 64), and the classifier self-tests awk before its first match (unknown, exit 70, never a silent none). An unreadable or empty capture, and missing pattern data, read as unknown, never as nothing found (field notes I1, I3). No screen text reaches the run ledger (field note I4).

## 0.6.0 — 2026-07-10

Deterministic-core hardening from a deeper multi-agent review (6 design streams + an /ultra --xl
adversarial gate). The review split its findings into this low-risk deterministic core and a
concurrency/liveness follow-up (hardened locks + `session_pid` liveness + the claim-time sonnet
screen), which ships separately with behavioral tests. Every item below is behaviorally tested; the
`.harness/` run state is forward/backward compatible (all new state is additive).

### Added
- **`cfg_int`** — every numeric config knob (`stall_minutes`, `watch_interval_seconds`,
  `boot_grace_seconds`, `close_timeout_seconds`, `resume_margin_seconds`) is now read through a
  validator that WARNs loudly and falls back to the default on a non-integer value, base-10 normalized
  so a leading zero can't trip a fatal octal error. A bad value can no longer abort a watch tick or
  busy-spin the loop; `watch_interval` is floored to ≥1.
- **`tickets.sh render`** — the only sanctioned way ticket text enters a session prompt: the body is
  wrapped in labeled UNTRUSTED-DATA markers (spoofed sentinels neutralized), and the worker/validator/
  orchestrator prompts frame it as data, never instructions (first, always-on layer of the ticket-body
  injection defense).
- **`tickets.sh release` / `stale`** — the only in-progress→ready path (floor-gated), plus a start-time
  sweep that reports every in-progress ticket and releases the ones idle > 7 days that still pass the
  ready floor. The orchestrator's exit condition now counts only lanes IT claimed this run, so a ticket
  stranded by a crashed run can't poison a future run's completion.
- **`state.sh marker clear`** — lets a worker→validator retry reset attempt-1 markers/fail-file so
  stale state can't satisfy the new round.
- **`status --json`** — machine-readable run health (exit 1 on attention items or a DEAD-RUN marker)
  for cron/notifier babysitting.
- **git ground-truth stall cross-check (L18)** — the watch nudge now skips when the session's tree
  shows recent git activity (head for a worker, any branch for the orchestrator) or is mid-turn
  (`esc to interrupt`), so a long build with a quiet heartbeat no longer gets a blind Enter.

### Fixed / hardened
- **Secrets:** the OAuth token is fed to `curl` via stdin (`-H @-`), never on argv (no longer visible
  in `ps`); preflight refuses a literal credential embedded in any `accounts*.env_command`.
- **Launcher PATH sanitized** — empty / `.` / relative components dropped before baking (each was a
  `.`-injection vector in a bypass-permissions session).
- **`never_push` origin-pushurl belt** — an in-session `git push` (origin) fails fast under the
  never-push guarantee; fetch/pull unaffected (best-effort: origin only, documented).
- **`hcurrent_run` self-heals** an empty/stale `.harness/CURRENT` to the single live run (so state
  verbs no longer crash in the torn-write window); the CURRENT write is atomic.
- **`.blocked`-lane consumer** — a self-blocked lane is closed and its marker cleared instead of being
  nudged hourly.

### Removed
- The proposed per-session PostToolUse auto-heartbeat hook was cut before shipping (it fired only after
  a tool returned — missing the long-single-call stall it targeted — and could mask a genuinely stuck
  tool-spinning session; the git cross-check + `esc to interrupt` skip cover the case instead).

## 0.5.0 — 2026-07-10

Adds tiered autonomous decisions; fixes 13 defects from an adversarial red-team (opus break-review
→ escalating medium→large validation: 0 false positives, all confirmed real, 8 outright + 5 real-but-
overstated). Notably the static suite passed 30/30 with every one of these present — they were
runtime/logic gaps only an adversarial pass reaches.

### Added
- **Tiered autonomous decisions** (never AskUserQuestion): small → decide+log; non-trivial →
  3-voice `harness:council-advisor`; hard / <70%-sure / would-need-the-owner → escalate to
  `/ultra:run --large` and adopt its recommendation. Only scope changes block; only irreversible/
  prod is owner-gated. Soft dependency on the `ultra` plugin (council is the top tier without it).

### Fixed (red-team, validated)
- **F1 (MEDIUM): watch-loop screen-scrape false positives** — `password:`/`rate limit`/`trust…` as
  substrings in normal build output no longer misfire; detection is bottom-anchored (last ~3 non-blank
  lines) with tighter patterns, killing the "arbitrary scrollback contains the phrase" class.
- **F2 (MEDIUM): local `status:ready` (no space)** no longer causes infinite re-claim — the setter now
  matches optional whitespace like the getter.
- **F4 (MEDIUM): corrupt project `config.json`** now fails preflight loudly instead of silently
  reverting every setting to defaults.
- **F3: empty `.harness/CURRENT`** (crash between truncate and write) self-heals instead of wedging
  start/resume/status.
- **F5: caffeinate is bound to the watch pid (`-w`)** — a dead watch can no longer leave the Mac awake.
- **F6: sonnet rejected ANYWHERE in a build-role chain** (not just the primary) — `opus|sonnet` fallback
  can't run build work.
- **F7: cwd guard narrowed** to genuinely dangerous chars (`` ` `` `$ \ "`) — legit paths like `my(app)`
  are no longer refused.
- **F8: worktree check hardened** against `--separate-git-dir` spoofing (requires a genuine linked
  worktree); factored into one shared helper used by both callers.
- **F9: pretrust writes to the active account's `.claude.json`** (config-dir-aware), not always `$HOME`.
- **F10: limits fail CLOSED** to UNKNOWN when `limits[]` percents are null/non-numeric.
- **F11: guidance globs are repo-contained** — a `../` glob is flagged, not surfaced as authoritative.
- **F12: run ids/tmux sessions/launcher dirs are project-scoped** (hash prefix) — two projects can't collide.
- **F13: grill floor accepts synonym headers** (Goal / In scope / Definition of Done).
- Tests 30 → 38 (H-30 decision layer, H-31..H-38 the fixes).

## 0.4.0 — 2026-07-09

Adds project-guidance discovery; resolves a third review (Fable revalidation SHIP-WITH-FIXES +
an independent 0-100 validation that scored 82 with one blocking bug).

### Added
- **Project-guidance discovery** (`harness-guide.sh discover`): before working, each session reads
  the repo's own rules — README/CONTRIBUTING/AGENTS.md, `.github/` workflows + PR template +
  CODEOWNERS, Makefile/Justfile, package.json scripts, linter/formatter configs, DEPLOY/RELEASE
  docs, env setup — and follows them (real gate commands, commit/PR conventions, do-not-touch
  boundaries), owner-gating anything it can't satisfy. Advisory (lists paths, never enforces);
  optional `guidance` config block for extra files + a free-text steer; CLAUDE.md flagged as
  already-loaded. Wired into worker + orchestrator prompts. Test H-29.

### Fixed
- **BLOCKING (0-100 validator): `harness-trust.sh` and `harness-gsd.sh` were committed
  non-executable** (mode 100644) but invoked via direct exec — both trust-dialog layers silently
  died (`Permission denied`). Now `100755`.
- `.harness-project` pointer is added to the worktree's git exclude so `git add -A` never ships it
  in a PR.
- The stall-nudge now skips any session at a password OR trust modal (a blind Enter would submit an
  empty credential / accept a trust the sonnet gate declined).
- Preflight warns about Terminal.app's missing send/key when it's the RESOLVED backend, not only the
  configured literal.
- Boot-verify `pgrep` anchors out the caller's own pid (Linux self-match; macOS was already safe).
- `iso_to_epoch` falls back to `date(1)` when `python3` is absent (no silent rate-wait degradation).
- Docs: auto-detect order, validator-FAIL handling in orchestrator, DESIGN window-id/tty wording.

## 0.3.1 — 2026-07-09

Resolves a second Opus+Fable review (of 0.3.0) — overnight-survival hardening.

### Fixed
- **HIGH: orchestrator GSD bootstrap pointed at a hang.** The prompt said to bootstrap a milestone
  via `--auto new-milestone/new-project`, but those have no unattended path (verified vs installed
  GSD) — it now hand-seeds `.planning/`, matching gsd-workflow.md.
- **HIGH: dead-run fallback.** If the orchestrator crashes before setting `run.complete`, the watch
  loop now tears the run down after 3 idle ticks (caffeinate stops, Mac can sleep, DEAD-RUN marker)
  and `resume` respawns a missing orchestrator — previously the Mac stayed awake and the next run
  was blocked.
- **HIGH: weekly-cap pausing.** `weekly_pause_at` now defaults to 99 (was null), so a weekly-capped
  run waits on the weekly reset instead of injecting `continue` into hard-limited sessions every tick.
- **MEDIUM: no keystrokes into a password prompt.** The watch computes the password-prompt state
  first and skips the stall-nudge/limit-resume for a session sitting at one (an Enter was an empty
  credential — it contradicted the "never enter a secret" promise).
- **MEDIUM: `--run` is background-only.** SKILL no longer suggests a foreground timeout (the Bash
  tool's 10-min cap could kill a legitimate hours-long rate-wait and zombie the run); `resume` is
  now crash-safe (spawns a fresh orchestrator if the registry lost it).
- **MEDIUM: per-role rate metering.** The rate gate meters the role's actual account
  (`HARNESS_ROLE`) so an override account (e.g. an independent validator identity) is measured
  correctly, not the shared one.

## 0.3.0 — 2026-07-09

Resolves an `/ultra:run --large` review (6 researchers → blind validators → devil's-advocate →
2v2 debate → anti-slop) that caught a ship-blocker introduced by the 0.1.0 review wave.

### Fixed
- **CRITICAL (C1): `/harness:run` aborted at orchestrator boot every time.** The `{{`-placeholder
  guard (added in 0.1.0 to catch unfilled worker prompts) rejected the orchestrator's own prompt,
  which legitimately contains `{{LANE}}` as fill-instructions. The guard now matches only the
  closed set of harness tokens and is role-gated to worker/validator.
- **M1 (same root cause): ticket bodies with `{{ }}`** (GitHub Actions `${{ secrets.X }}`,
  Vue/Jinja) no longer make a lane un-spawnable.
- **HIGH (H1): a completed run now tears itself down** — the orchestrator sets a `run.complete`
  marker; the watch loop closes sessions, stops caffeinate (Mac can sleep), and clears the run so
  the next `/harness:run` isn't blocked.
- **HIGH (H2): deterministic floor under the grill gate** — `tickets.sh` refuses to create a
  `ready` ticket whose body lacks the Outcome/Scope/Acceptance headers.
- **M3: per-role account override** — `accounts.<role>.env_command` (falls back to the shared
  one); scaffolded in the project template (independent validator identity).
- **M4: sonnet rejected for orchestrator/worker (build) roles** — policy is now engine-enforced,
  not just defaulted.

### Changed
- Docs reconciled (M2): the per-key merge claim now names the project-only keys the orchestrator
  reads directly; "mandatory grill gate" → "grill gate (LLM over a structural engine floor)".
- New tests H-24..H-28 including an **end-to-end orchestrator-render check** (the test class that
  was missing — the suite previously never exercised `start`).

## 0.2.0 — 2026-07-09

### Added
- **GSD driven by discovery, not hardcoded** (`harness-gsd.sh discover` + a
  `references/gsd-workflow.md` driving guide): sessions resolve the current `/gsd-*` surface at
  runtime, prefer the `mcp__gsd__*` tools and GSD's high-level unified drivers (progress /
  autonomous / workstreams), verify names via `/gsd-help`, and always use `--auto` variants.
  Harness lanes now map to GSD **workstreams**; the full research→plan→execute→verify→learn cycle
  runs per workstream, with context refresh (map-codebase / docs-update) up front and
  learnings capture (extract-learnings / mempalace) at the end.
- **Trust-dialog handling**: deterministic `pretrust` of each created worktree (scoped to
  in-project paths; merge preserves all `~/.claude.json` keys) + a Sonnet-gated watch backstop.
- **Password/sudo prompts are owner-gated** — detected and surfaced, never typed. New
  `guardrails.sonnet_trust_check` knob.
- Tests H-21/22/23 (GSD discovery-first, trust+password handling, pretrust scoping).

### Changed
- Worker/orchestrator prompts no longer name specific GSD phase commands.

## 0.1.0 — 2026-07-09

Initial beta.

### Added
- Deterministic bash engine (`bin/harness-*.sh`): config resolution (project > user > default),
  terminal backends (iTerm2 / Terminal.app / tmux) with tty-keyed session registry, spawn
  pipeline (guards → generated linted launcher → sonnet validation → boot verification),
  graceful `/exit`-then-close lifecycle, rate-limit verdict/wait off the OAuth usage API
  (Keychain-first token), GitHub-issues + local-file ticket queues, marker/heartbeat/decision
  state primitives, run lifecycle with deterministic watch loop and harness-managed caffeinate.
- Model OR-chains: `fable|mythos|opus` — spawn-time boot-failure fallback (interactive) and
  native `--fallback-model` (print mode). `haiku` rejected by policy.
- `/harness:onboard`, `/harness:init`, `/harness:add` (grill gate), `/harness:run`,
  `/harness:status`, `/harness:stop`, `/harness:resume`.
- Agents: `context-summarizer` (sonnet), `council-advisor` (opus).
- Prompt templates (orchestrator / worker / validator) with lane-based worktree parallelism,
  finalize-commit completion signal, independent validation, OWNER-ACTIONS/RUN-REPORT outputs.
- `docs/DESIGN.md` with the 24-incident lessons ledger this engine encodes.

### Notes
- Accounts are optional: single-login default; any switcher pluggable via
  `accounts.env_command` (e.g. `cloak switch --print-env work`). No rotation by design.
- Limits philosophy: pause new spawns at threshold, auto-resume at API reset, never stop
  voluntarily (`stop_at: null` default).
