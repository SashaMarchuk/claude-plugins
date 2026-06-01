> **This is a shipped template.** **Copy it to your run directory before editing.** Direct edits to this file will be wiped on `/plugin update`. `synthesize-project` fills the `{{...}}` placeholders and writes the result to `.planning/claude-migrate/<run>/project/<PNN__slug>/instructions-steady.md`.

<!--
PROJECT CUSTOM INSTRUCTIONS: STEADY VARIANT (without the OK protocol).

Purpose: this is instructions-migration.md with the migration-onboarding section removed.
It is the post-seed, post-rename text the project should run on for normal use. finalize_run
swaps the project's Custom Instructions from the migration variant to THIS variant once every
chat has been seeded and renamed (copy-page mode shows a trailing "swap to steady" card per
project instead). Never leave a project in the migration variant after migration finishes.

Fill rules for synthesize-project:
  {{PROJECT_NAME}}        -> the destination project's name (same value as the migration variant).
  {{WORKING_INSTRUCTIONS}} -> the project's working rules, carried over verbatim from the source
                             project's prompt_template (identical to the migration variant). If
                             the source had none, write: "No carried-over project rules."
This file is 100% domain-neutral: no domain, persona, or sample content is baked in.
-->

# {{PROJECT_NAME}}: Project Custom Instructions

## Working instructions

{{WORKING_INSTRUCTIONS}}
