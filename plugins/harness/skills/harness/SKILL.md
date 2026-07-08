---
name: harness
description: Universal autonomous orchestration harness — runs Claude Code sessions in real terminals to execute tickets end-to-end (GSD-flavored by default), unattended, with deterministic rate-limit pausing and safe terminal lifecycle. Flag-routed backing skill for /harness:onboard, /harness:init, /harness:add, /harness:run, /harness:status, /harness:stop, /harness:resume. Use when the user says "run the harness", "implement <X> autonomously", "queue this for the harness", or invokes any /harness command.
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, AskUserQuestion, Agent
---

# harness — flag-routed skill

The first token of `$ARGUMENTS` selects the mode: `--onboard | --init | --add | --run |
--status | --stop | --resume`. Everything after it is the mode's input.

Engine scripts live at `${CLAUDE_PLUGIN_ROOT}/bin/` (also on PATH as `harness-*.sh`). Always
call them with absolute paths: `bash "${CLAUDE_PLUGIN_ROOT}/bin/harness-run.sh" status`.
**Every side effect goes through an engine verb.** You never run osascript/tmux yourself, never
write registry/state files by hand, never label GitHub issues except via `harness-tickets.sh`.

Config resolution (engine-enforced, know it to explain it): **project `.harness/config.json` >
user `~/.claude/harness/config.json` > built-in defaults**, per key.

---

## --onboard  (user-level setup; safe to re-run, preserves unknown keys)

Goal: write `~/.claude/harness/config.json`. Use AskUserQuestion for each decision — never
assume. Steps:

1. **Terminal**: detect the default deterministically — run `echo "$TERM_PROGRAM"`
   (`iTerm.app` → iterm2, `Apple_Terminal` → terminal; empty → check `ls /Applications/iTerm.app`).
   Present the detection: "You're running in iTerm2 — use it for harness sessions?" Options:
   detected app (recommended) / other installed terminal / tmux. Then ask fullscreen yes/no and
   explain the two-window layout (control window: orchestrator + watch; work window: workers) —
   it's the default; power users can edit `terminal.windows` later.
2. **Accounts**: explain plainly: "By default the harness uses your normal `claude` login —
   one account, nothing to set up. If you keep separate Claude accounts (say work vs personal,
   via a switcher like cloak), the harness can run its sessions under a specific one." Options:
   "Single account (default, recommended)" / "Use an account switcher". If switcher: ask for the
   env command (example to show: `cloak switch --print-env work`) and VERIFY it: run it, check
   it prints `export` lines, refuse to save a failing command.
3. **Limits**: explain the philosophy in one line — "the harness pauses NEW work at a threshold
   and auto-resumes at reset; it never kills running sessions and never stops unless you tell
   it to." Ask: pause threshold (default 90% of the 5h window) and whether to also pause on the
   weekly cap (default: no).
4. **Models**: show defaults (orchestrator/worker `opus`, validator `fable|mythos|opus`,
   summarizer sonnet) and explain `|` = fallback OR. Ask only "keep defaults?" — detailed chains
   are a config edit, not an interview.
5. Write the config: start from `${CLAUDE_PLUGIN_ROOT}/templates/user-config.example.json`,
   strip `_`-prefixed comment keys, fill answers, write to `~/.claude/harness/config.json`
   (create dir; if a config exists, merge — preserve keys you didn't ask about). Show the final
   JSON and where it lives.

## --init  (project-level setup; run inside the project)

1. Identify the project root (where `.harness/` will live — the current directory unless the
   user says otherwise). Detect repos: `find . -maxdepth 2 -name .git` → for each, get
   `git remote get-url origin` and default branch. Present the detected list for confirmation.
2. **Tickets**: if a detected repo has a GitHub remote, recommend `source: github` on that repo
   (ask which repo if several); otherwise recommend `source: local`. Explain the queue in one
   line: "you add tickets with /harness:add; the harness executes `harness:ready` ones in
   order." ClickUp note if the user mentions it: ClickUp stays manual by design — paste the
   ticket into /harness:add.
3. **Workflow**: `gsd` if `.planning/` exists in any repo (say why), else ask gsd/generic.
4. **Guardrails**: confirm `never_push` (default true — integration stays local, run ends at
   PR-ready branches + report) and read the default `owner_gated` list aloud; let them add items.
5. Write `<project>/.harness/config.json` from the project template (strip `_` keys), then:
   `bash "${CLAUDE_PLUGIN_ROOT}/bin/harness-tickets.sh" bootstrap` and add `.harness/runs/` to
   the project's `.gitignore` if the root is a repo. Show the config and a 3-line "what's next"
   (add a ticket → run → status).

## --add  (create a ticket — THE GRILL GATE LIVES HERE, and it runs FIRST)

Input: free text after `--add` (e.g. "implement CSV export for reports").

1. Draft the ticket silently first: outcome, scope (which repo/paths), acceptance criteria
   (testable), out-of-scope, references. Fill what the input + a quick look at the repo give you.
2. **Grill**: for every section you could NOT fill confidently, ask via AskUserQuestion —
   batched, max 4 per round, concrete options where possible ("Which repo does this belong to?"
   with the repos from config). Continue until the checklist is complete OR the user picks
   "use your best judgment" — record that verbatim in the ticket body under `## Defaults accepted`.
3. Compose the body (markdown: `## Outcome / ## Scope / ## Acceptance criteria /
   ## Out of scope / ## References`), write it to a temp file, then:
   `harness-tickets.sh add "<title>" <body-file> ready`.
   If the user cut the interview short with unanswered blockers: create with state `blocked`
   and an `## Open questions` section instead. Say clearly: "created as blocked — the harness
   will not touch it until the questions are answered and it's relabeled ready."
4. Echo the ticket id/url and: "run it with /harness:run (or it'll be picked up by the next run)."

## --run

1. Preflight is the engine's job: `bash "${CLAUDE_PLUGIN_ROOT}/bin/harness-run.sh" start` runs
   config/auth/terminal/env-command checks and refuses with specific messages — relay failures
   verbatim and help fix them (missing user config → offer --onboard; missing project → --init).
2. Before starting, show the operator a 5-line brief: tickets that will run (from
   `harness-tickets.sh list ready`), limits right now (`harness-limits.sh verdict`), terminal
   layout, and whether the queue is empty (empty → suggest /harness:add first; starting an
   empty run is allowed but pointless).
3. Start it. Report the run id and how to watch: `/harness:status`, STOP semantics
   (`/harness:stop`), and where artifacts land (`.harness/runs/<id>/RUN-REPORT.md`).

## --status

Run `bash "${CLAUDE_PLUGIN_ROOT}/bin/harness-run.sh" status` and present it readably. If
ATTENTION lines exist, lead with them and the fix (`resume` for DEAD, answer-and-relabel for
blocked tickets). Do not editorialize a healthy run.

## --stop

Confirm once ("stop run <id>? running sessions get a graceful /exit"), then
`bash "${CLAUDE_PLUGIN_ROOT}/bin/harness-run.sh" stop`. Report which sessions closed and
whether any refused (busy ones are left open by design — say where they are).

## --resume

`bash "${CLAUDE_PLUGIN_ROOT}/bin/harness-run.sh" resume` — relay what was respawned (exact
session continuation via recorded `--session-id`s) and current status.

---

## Failure vocabulary (engine exit codes you must handle, not hide)

- **75** from spawn = rate-paused: the engine says when it resets; `harness-limits.sh wait`
  blocks until then. Never present this as an error — it's the designed pause.
- **65** = a guard rejected (unsafe cwd, validator rejection, STOP present) — show the reason
  verbatim; these are protecting the machine.
- **69** = boot failed — show the launcher log tail the engine printed; commonest causes:
  model chain fully unavailable, account env_command broken.
- **70** = terminal automation failed — almost always the one-time macOS Automation permission
  (System Settings → Privacy & Security → Automation → allow your terminal to control iTerm2).
