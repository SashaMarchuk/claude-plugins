# Tasks

## 1. Requirements format

- [x] 1.1 Write `references/formats/openspec.md` and verify its delta shapes with `openspec validate --strict` on a throwaway project
- [x] 1.2 Add collect step 5 and the run option to `SKILL.md`, format-agnostic, and verify `tests/run.sh` passes
- [x] 1.3 Add `requirements.format` to `references/config.md` (block, deferred table, wizard close) and verify the contract tests
- [x] 1.4 Mutation-check every new contract assert and verify each one fails when its rule is removed
- [x] 1.5 Make formats opt-in: default `none`, `custom` instruction, explicit ask when the template is absent (IH-074)

## Workflow follow-up

- Archive this change with `openspec archive add-requirements-format --yes` after the PR is merged.
