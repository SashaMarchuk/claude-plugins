> **This is a shipped template.** **Copy it to your run directory before editing.** Direct edits to this file will be wiped on `/plugin update`. `synthesize-project` fills the `{{...}}` placeholders and writes the result to `.planning/claude-migrate/<run>/project/<PNN__slug>/instructions-migration.md`.

<!--
PROJECT CUSTOM INSTRUCTIONS: MIGRATION VARIANT (with the OK protocol).

Purpose: this is the text you paste into the NEW account's project Custom Instructions
field BEFORE seeding any chats. It keeps the OK protocol active so each seeded chat's
first message (a migration brief) is acknowledged with a bare `OK` and does not trigger
real work until you continue. After every chat is seeded and renamed, swap this for
instructions-steady.md (the same text with the OK-protocol section removed).

Fill rules for synthesize-project:
  {{PROJECT_NAME}}        -> the destination project's name.
  {{WORKING_INSTRUCTIONS}} -> the project's working rules, carried over verbatim from the
                             source project's prompt_template (the source's own Custom
                             Instructions). Do NOT invent rules; copy what the export carried.
                             If the source had none, write: "No carried-over project rules."
This file is 100% domain-neutral: no domain, persona, or sample content is baked in.
-->

# {{PROJECT_NAME}}: Project Custom Instructions

## Migration onboarding protocol (temporary)

This project is being seeded from a previous Claude account. For the seeding phase only:

- The **first message** in any new chat is a **migration brief**: context carried over from the old account so this chat can resume where the old one left off.
- When the first message of a chat is a migration brief, reply with **exactly** `OK` and nothing else. Do not summarize it, act on it, or ask questions yet. The brief is context to absorb, not a task.
- Every message **after** the first one is a normal request: respond fully and normally, using the brief as background.

This onboarding section will be removed once seeding is complete; from then on, treat the first message of every chat as a normal request like any other.

## Working instructions

{{WORKING_INSTRUCTIONS}}
