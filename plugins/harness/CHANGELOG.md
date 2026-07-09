# Changelog — harness

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
