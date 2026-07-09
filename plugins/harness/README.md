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

Per-key resolution for engine-read keys (via `cfg()`): **project `.harness/config.json` →
user `~/.claude/harness/config.json` → defaults**. A handful of project-shape keys the orchestrator
reads directly (`repos`, `workflow`, `parallel`, `guardrails.owner_gated`/`never_push`,
`tickets`) live at project level only — they have no user-level fallback by design. Annotated examples: [`templates/user-config.example.json`](templates/user-config.example.json),
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
- **Terminal.** `auto` detects iTerm2 → tmux → Terminal.app (Terminal.app is never auto-picked
  when tmux exists, because it can't deliver `/exit`/nudges — so graceful stop and auto-resume
  need iTerm2 or tmux). Sessions are tracked by tty and by the claude pid, and closed one at a
  time via `/exit`-then-close — the harness never closes a window and never touches sessions it
  didn't start. The two-window control/work layout is delivered on **iTerm2** (tabs grouped into
  two windows); on tmux it's one session with a window per role; on Terminal.app, one window per
  session.

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

**Trust dialogs** ("Do you trust the files in this folder?") are handled two ways: the harness
**pre-trusts** each worktree it creates (writing `hasTrustDialogAccepted` for that path in
`~/.claude.json`, but only for paths inside your project), and the watch loop is a backstop — if
a dialog appears anyway, it answers yes **only after** a deterministic in-project check *and* a
Sonnet confirmation; a folder outside the project is left for you.

**Passwords and `sudo` are never typed by the harness.** A password/passphrase/`sudo` prompt is
detected and owner-gated (surfaced in `OWNER-ACTIONS.md` and the status ATTENTION list) — the
harness will not enter a secret on your behalf. For unattended Docker: on macOS, Docker Desktop's
`docker` CLI needs no `sudo`; on Linux, add your user to the `docker` group or use a scoped
`NOPASSWD` sudoers line so nothing ever prompts.

The full rationale, including the ledger of 24 real incidents from three prior harness
generations that these rules encode, is in [`docs/DESIGN.md`](docs/DESIGN.md).

## Project guidance

Before touching code, each session runs `harness-guide.sh discover` and reads the files it finds —
your project's own rules win over the harness's defaults. It surfaces what a repo actually has:
`README`, `CONTRIBUTING`, `AGENTS.md`, `.github/` workflows + PR template + `CODEOWNERS`,
`Makefile`/`Justfile`, `package.json` scripts, linter/formatter configs, `DEPLOY`/`RELEASE` docs,
env setup. Workers run the project's real lint/test/build gate (not a guessed `npm test`), match
its commit/PR conventions, respect its do-not-touch boundaries, and owner-gate anything a gate
needs that they can't do (a deploy secret, a prod cutover). It's advisory — the helper lists paths,
the session reads and follows them; nothing is hardcoded. Add project-specific files or a one-line
steer via the optional `guidance` block in project config; `CLAUDE.md` is already auto-loaded so
it's flagged, not re-read.

## Requirements

macOS (iTerm2/Terminal.app backends; tmux backend is OS-agnostic), `jq`, `gh` (only for the
GitHub ticket source), Claude Code ≥ 2.1. First iTerm2 spawn triggers a one-time macOS
Automation permission prompt (System Settings → Privacy & Security → Automation).

With the default `session.permissions: bypass`, **accept "Bypass Permissions" once per account**
before the first run — run `claude --dangerously-skip-permissions` interactively and accept, or
set `session.permissions` to `auto`/`acceptEdits`. Otherwise the first spawned session hangs on
the acceptance dialog (preflight warns when it can't confirm prior acceptance).
