---
argument-hint: "[<call to investigate>]"
description: "Pull deep, cited context from a past Google Calendar meeting — find / summarize / recap a call, or extract decisions and action-items. Read-only."
---

Invoke the `find-call:find-call` skill via the Skill tool, passing `$ARGUMENTS` through verbatim. The skill parses the query (topic / person / time anchor / intent), searches Calendar + Sembly in parallel, disambiguates matches, and returns cited summaries per its SKILL.md. Read-only — it never modifies Calendar, Drive, or Sembly.
