# Changelog — harness

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
