---
argument-hint: "[<task id / URL, or blank to pick from your in-progress list>]"
description: "Open ONE fresh seeded coding session for ONE in-progress task (default: a new iTerm2 tab running Claude Code — launcher and tool configurable), with its context + related calls + a report-back rule."
---

Invoke the `task-launch:task-launch` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. The skill picks one in-progress task (or the id/URL you passed), resolves and verifies its folder, confirms which calls to load, gathers any pass-through context, writes a starter prompt, then opens ONE fresh session per your configured launcher (default: a new iTerm2 tab — reusing the current window when one exists — running Claude Code) seeded with that prompt — per its SKILL.md. One task = one session; it always starts fresh and never resumes.
