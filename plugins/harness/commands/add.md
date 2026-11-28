---
argument-hint: "<what to implement>"
description: "Create a harness ticket from a plain description. Grills you first (interactive) until outcome, scope, and acceptance criteria are clear — insufficient answers create a blocked ticket instead of a guessable one."
---

Create one harness ticket from this request: $ARGUMENTS

The ticket goes into the project's configured tracker (GitHub issues by default, or the local ticket folder). It then follows the same pickup path as a ticket labelled there by hand: the next poll checks who set the ready label and the ticket's readiness.

1. Draft the ticket silently first. Get the structure the plugin writes:
   `"${CLAUDE_PLUGIN_ROOT}/bin/harness" tickets template`
   Fill each heading from the request and a quick look at the repository: Outcome, Scope (repository, folders, what stays out), Acceptance criteria (each one checkable), Checks (the commands or tests that prove them).

2. Grill before you create anything. For every heading you could not fill with confidence, ask the person with AskUserQuestion: at most 4 questions per round, with concrete options where you can. Go on until every heading is filled, or until the person picks "use your best judgment". In that case, write their words under a `## Defaults accepted` heading.

3. Write the body to a temporary file and create the ticket with its tracker status:
   - all headings filled: `"${CLAUDE_PLUGIN_ROOT}/bin/harness" tickets add "<title>" <body-file> ready`
   - the person stopped with blockers still open: add an `## Open questions` heading with numbered questions, and create it as `blocked` instead of `ready`. Tell them: "Created as blocked. The harness will not take it until a person with write access answers and sets the ready label."

4. Print the ticket number and say that the next harness poll picks it up.
