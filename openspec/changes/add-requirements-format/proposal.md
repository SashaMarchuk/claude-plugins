# Proposal

## Why

When a project keeps its requirements in a structured format such as OpenSpec, the decisions confirmed in an interview are re-typed by hand into that format, which loses the link to the person's words and invites the plugin's own restatement to be taken as a decision.

## What Changes

- `collect` gains a last step: carry confirmed decisions into the project's requirements format, alongside the analysis file, never instead of it. Only items that are settled, confirmed, from a source-of-truth resource and free of unresolved contradictions are eligible, and every write is previewed and made only on the person's yes.
- `run` may take a requirements-format change as the starting material for the context document; what it brings is current behaviour or a draft to ratify, never the person's decision.
- New plugin setting `requirements.format`: `none` by default (no detection, no question, no mention of any format), a template name from `references/formats/`, or `custom` with the person's own instruction in `requirements.custom`. When the chosen template is not in the project, the plugin asks explicitly before using it there.
- OpenSpec is the first format, described in `plugins/interview-handoff/references/formats/openspec.md`; the skill stays format-agnostic.
- Plugin version 0.5.0.

## Capabilities

### New Capabilities

### Modified Capabilities
- `interview-handoff/collect-analysis`: adds the requirements-format step (IH-073) and makes formats opt-in (IH-074).
- `interview-handoff/plugin-shape`: the agnosticism rule allows a format to be named in its own reference (IH-058); the edit limit lists exactly what the plugin may write (IH-069).
- `interview-handoff/configuration`: `requirements.format` is a plugin-only setting (IH-023).

## Non-goals

- Editing the project's main specs, archiving, syncing, or touching `tasks.md`.
- Replacing the analysis file with format output.
- An OpenSpec-aware interviewer prompt.

## Impact

`plugins/interview-handoff/`: `skills/interview-handoff/SKILL.md`, `references/config.md`, `references/formats/openspec.md` (new), `README.md`, `tests/run.sh`, `.claude-plugin/plugin.json`.
