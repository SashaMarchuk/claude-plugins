---
argument-hint: "<event title or id> (e.g., 'Weekly Sync tomorrow')"
description: "Cancel (delete) a Google Calendar event. Delegates to the gevent skill's cancel flow — intent is detected from verbs like 'cancel', 'delete', 'remove'."
---

Invoke the `gevent:gevent` skill via the Skill tool, passing `$ARGUMENTS` verbatim. The skill's own intent-detector routes cancel-intent keywords ("cancel", "delete", "remove") to the cancel flow in `references/modes.md#default` → Cancel flow (Step 7 in SKILL.md). This command is a thin autocomplete-friendly alias for the skill's cancel path.
