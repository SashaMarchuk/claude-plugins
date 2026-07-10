# Changelog — harness

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
