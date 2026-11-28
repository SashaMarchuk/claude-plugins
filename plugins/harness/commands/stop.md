---
description: "Stop the current harness run, soft (finish the current step, the task or the ticket) or hard (a stop message, or close everything now), with an optional own message."
argument-hint: "[soft:step|soft:task|soft:ticket|hard:message|hard:now] [--ticket ID]... [--message TEXT]"
---

Stop the current harness run: $ARGUMENTS

1. **Pick the stop.** If `$ARGUMENTS` names a type, use it. Otherwise ask the person once with AskUserQuestion, recommended first:
   - `soft:step` (the default): each session finishes only its current step; nothing new starts.
   - `soft:task`: in execution, stop once the current task's last step is done.
   - `soft:ticket`: the named tickets (or all) run to their end; nothing new starts.
   - `hard:message`: a stop message goes to every session at once; a session that does not park in time is closed by its exact process ID.
   - `hard:now`: every session of the run closes at once, with no message.
   Offer to add an own message; it is added word for word to the stop text. With `hard:now` an own message is not sent; it is only written to the run ledger.

2. **Stop.** Run `"${CLAUDE_PLUGIN_ROOT}/bin/harness" run stop --type <type> [--ticket ID]... [--message "<text>"] [reason]` from the project's main checkout. It records the stop, and for a soft stop it delivers the stop text to every session the stop covers; a hard stop acts at once.

3. **Report** what the engine printed: the stop id, the type, the sessions that got the text, and any session the text may not have reached (an owner action). Say that `/harness:resume` lifts the stop. A STOP file in the run folder also stops the run (the default soft stop) and must be removed before a resume.
