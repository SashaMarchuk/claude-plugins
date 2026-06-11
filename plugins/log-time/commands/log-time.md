---
argument-hint: "[<date range, e.g. 'this week' or 'jun 2-6'>]"
description: "Build a paste-ready time-log from your configured evidence sources (calendar, tracker, Claude Code sessions, transcripts, custom). Evidence-only; read-only against every source."
---

Invoke the `log-time:log-time` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. The skill loads the user's free-form config from `~/.claude/log-time/config.md`, preflights the configured sources, gathers evidence in parallel, synthesizes per-day, allocates per the user's own rules, and emits tracker-ready entries plus an audit file. If no config exists yet, the skill routes into the onboarding wizard first — it never builds a time-log unconfigured. Read-only against every source — it never writes to the calendar, tracker, transcripts, or any other source.
