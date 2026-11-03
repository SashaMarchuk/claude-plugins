# Design

## Context

See proposal.md, Why. The analysis file is the plugin's evidence and is never rewritten; requirements-format files are living documents anyone edits.

## Goals / Non-Goals

**Goals:** confirmed decisions reach the project's requirements without re-typing, with the person approving every write.

**Non-Goals:** see proposal.md.

## Decisions

- **Alongside, never instead.** The analysis is written first every round and stays the evidence; format files are derived from it, because they cannot carry the never-rewritten guarantee.
- **Preview and yes on every write, autopilot included.** A requirement's SHALL sentence and scenario are the plugin's formulation of the person's words; a write is a decision about the subject, not a setting.
- **Off unless chosen.** The owner's rule: collect stays format-agnostic, and many interviews produce no requirements at all, so `requirements.format` defaults to `none`, with no detection and no question. OpenSpec is one template among possible others, and `custom` lets the person say in their own words what collect should do. A chosen template that the project does not have is asked about explicitly, never assumed and never answered by autopilot.
- **The topic-to-change link, the ledger of what was written where, and words changed in a preview live in the context document**, which is already the plugin's memory between rounds. No per-topic config.
- **One reference file per format under `references/formats/`.** No adapter framework: the skill reads the file the key names.
- **Requirement IDs follow the project.** Where headers carry IDs, a new requirement takes the next unused number with the same prefix; no ID is ever reused.

## Risks / Trade-offs

- [The plugin's wording is mistaken for the person's decision] → preview per block; detail the person did not say needs its own yes.
- [Round 2 changes a block written in round 1] → edit that ADDED block in place with a yes; never ADDED and MODIFIED for the same name.
- [The change is archived between rounds] → never write into `archive/`; offer a new change.
