# claude-plugins

This repository is in production — all four plugins (`clickup`, `g-event`, `ultra`, `ultra-analyzer`) are live for real users with a 170-test regression harness (`bash tests/run-all.sh`); every change must be made carefully, tested locally before commit, shipped via PR (no direct pushes to `main`), and accompanied by a migration note when registry-visible names or descriptions change so users can update via `/plugin update` rather than reinstall.

## Requirements (OpenSpec + GSD)
- Requirement text lives only in `openspec/`: `specs/` = current behaviour, `changes/<id>/` = intended change. Never restate, reword or invent requirements elsewhere. GSD never edits `openspec/`.
- `/gsd-new-milestone`: do not interview for requirements. Take every `### Requirement: ID Title` from the active change's delta specs (`openspec/changes/<id>/specs/`) and write `.planning/REQUIREMENTS.md` entries as `- [ ] **ID**: Title — openspec/changes/<id>/specs/<cap>/spec.md`. Keep OpenSpec IDs as they are; do not continue GSD numbering; add no "table stakes".
- Every GSD agent: the full requirement text is in the linked spec, not in REQUIREMENTS.md. Read it before planning, executing or verifying.
- `/gsd-discuss-phase` / `/gsd-plan-phase`: list `openspec/changes/<id>/proposal.md`, `design.md` and the delta specs in `<canonical_refs>`.
- Implement only through GSD; do not use OpenSpec `apply`. After the milestone's PR is merged: `openspec archive <id> --yes`.
