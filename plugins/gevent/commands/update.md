---
argument-hint: "<event title or id> <what to change> (e.g., 'Weekly Sync to 3pm')"
description: "Update an existing Google Calendar event (time, attendees, title, etc.). Delegates to the gevent skill's update flow — intent is detected from verbs like 'move', 'reschedule', 'change', 'update', 'add attendee'."
---

Invoke the `gevent:gevent` skill via the Skill tool, passing `$ARGUMENTS` verbatim. The skill's own intent-detector routes update-intent keywords ("move", "reschedule", "change", "update", "add attendee") to the update flow in `references/modes.md#default` → Update flow (Step 6 in SKILL.md). This command is a thin autocomplete-friendly alias for the skill's update path.
