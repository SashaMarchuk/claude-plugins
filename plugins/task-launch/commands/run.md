---
argument-hint: "[--all | --one | <task id / URL>]"
description: "Open fresh seeded coding sessions for your in-progress tasks — one task at a time (--one) or all of them at once (--all, one terminal each; default configurable), each with its context + related calls + a report-back rule."
---

Invoke the `task-launch:task-launch` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. Two launch modes: `--one` (or a task id/URL) opens ONE task; `--all` opens EVERY in-progress task, each in its own terminal. With neither flag the skill uses your configured `defaults.launch_mode`, or asks once and offers to save your answer.

For one task it resolves and verifies the folder, confirms which calls (and any Slack context) to load, gathers pass-through material, writes a starter prompt, and opens ONE fresh session per your configured launcher (default: a new iTerm2 tab — reusing the current window when one exists — running Claude Code). For `--all` it confirms the task set, analyzes every task **in parallel** (folder, calls, Slack context, follow-up questions), asks for ONE consolidated confirmation, then launches the terminals **sequentially** — one per task. One task = one session; sessions always start fresh and never resume.
