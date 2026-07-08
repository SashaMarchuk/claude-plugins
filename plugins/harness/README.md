# harness (beta)

Runs Claude Code sessions in real terminals to execute your ticket queue autonomously —
overnight or any time you're away — with deterministic pausing on rate limits and a safe
terminal lifecycle. GSD-flavored by default, generic otherwise.

```
/harness:onboard      # once per machine: terminal, accounts (optional), limit policy
/harness:init         # once per project: repos, ticket source, workflow, guardrails
/harness:add implement CSV export for reports     # grills you, then queues a ticket
/harness:run          # spawns the fleet; go to sleep
/harness:status       # sessions, heartbeats, limits, attention items
/harness:stop         # graceful wind-down (STOP file + /exit per session)
/harness:resume       # after a crash/reboot: respawn dead sessions, exact continuation
```

## What a run looks like

One **orchestrator** session (window 1, next to the deterministic **watch** loop) claims
`harness:ready` tickets FIFO, splits them into independent lanes, and spawns **workers** into
git worktrees (window 2, one tab each). Each finished lane is re-verified by an independent
**validator** session against actual code before its tickets close. Everything lands locally:
PR-ready branches, `RUN-REPORT.md`, `OWNER-ACTIONS.md` (the "needs your hands" list), and a
decision log. Nothing is pushed unless you flip `guardrails.never_push`.

## Config: user + project

Per-key resolution: **project `.harness/config.json` → user `~/.claude/harness/config.json` →
defaults**. Annotated examples: [`templates/user-config.example.json`](templates/user-config.example.json),
[`templates/project-config.example.json`](templates/project-config.example.json).

The parts people ask about:

- **Accounts — optional by design.** Default = your normal `claude` login, one account, zero
  setup. If you keep separate accounts (e.g. work vs personal through a switcher like
  [cloak](https://github.com/synth1s/cloak)), set one key:
  `"accounts": { "env_command": "cloak switch --print-env work" }` — any command that prints
  export-style env vars works. Launchers eval it and fail loudly if it breaks. There is
  deliberately no account rotation.
- **Models — `|` means OR.** `"validator": "fable|mythos|opus"` tries `fable` first and falls
  through automatically when a model is unavailable or restricted (boot-failure fallback at
  spawn; native `--fallback-model` in print mode). `haiku` is rejected by policy; sonnet is
  reserved for spawn validation and big-context summarization.
- **Limits — pause, never stop.** At `pause_next_spawn_at` (default 90% of the 5-hour window)
  NEW spawns wait for the reset (timed from the usage API's `resets_at`, not from parsing
  terminal text); running sessions are never touched; `stop_at: null` means the harness never
  voluntarily stops. The watch loop also clears the interactive limit banner after reset —
  only when the session is idle.
- **Terminal.** `auto` detects iTerm2 → Terminal.app → tmux; two-window layout by default
  (control: orchestrator + watch · work: everything else); sessions are tracked by tty and
  closed one at a time via `/exit`-then-close — the harness never closes a window and never
  touches sessions it didn't start.

## Tickets

GitHub issues by default (`harness:ready → in-progress → done | blocked | needs-review`,
FIFO by issue number), or `.harness/tickets/*.md` for projects without a queue repo. ClickUp
(or any other tracker) stays human-mediated on purpose: paste the ticket into `/harness:add`.

**The grill gate is the first thing that happens, twice**: `/harness:add` interviews you until
outcome/scope/acceptance-criteria are real (or creates the ticket `blocked` with open
questions), and the orchestrator re-checks the same checklist before executing any ticket —
insufficient tickets get blocked with questions, never guessed at.

## Safety model

Deterministic guards first (absolute paths only; cwd must exist inside the project; `cd || exit`
inside every generated launcher — a session can never start in `$HOME` or `/`), then a **sonnet
spawn-validator** reviews every generated launcher before a terminal opens. Sessions get
pre-generated `--session-id` UUIDs (exact `--resume` later). `.harness/STOP` is checked before
every spawn and watch tick. Owner-gated actions (prod deploys, irreversible writes, secrets)
are never executed — they land in `OWNER-ACTIONS.md` regardless of any other setting.

The full rationale, including the ledger of 24 real incidents from three prior harness
generations that these rules encode, is in [`docs/DESIGN.md`](docs/DESIGN.md).

## Requirements

macOS (iTerm2/Terminal.app backends; tmux backend is OS-agnostic), `jq`, `gh` (only for the
GitHub ticket source), Claude Code ≥ 2.1. First iTerm2 spawn triggers a one-time macOS
Automation permission prompt.
