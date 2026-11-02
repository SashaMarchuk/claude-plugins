# Carry confirmed decisions into a requirements format (D39)

Owner decision: round nine, plan reviewed independently and approved by the owner
In force: when interview-handoff 0.5.0 ships (built on branch `feat/interview-handoff-openspec`, commit `74adee6`)
Status: approved, not yet applied

## Why

D39 was decided and built on `feat/interview-handoff-openspec` while this tree was being created on `main`'s
base (`fd6125e`). Its text is carried here unchanged so that nothing is lost, and so the requirement does not
enter `specs/` before the behaviour it describes is on `main`.

## What Changes

- ADDED D39, word for word from `REQUIREMENTS.md@74adee6`, with one acceptance scenario added during the move.
- MODIFIED AGN-1: the Agnosticism section gains the D39 exception for `references/formats/`.
- MODIFIED CFG-1: the plugin config gains the requirements-format key.
- Not a spec, so not a delta: on apply, `reference/out-of-scope.md` X-2 becomes "It edits nothing except its own
  package files and the analysis output, and, since D39, with the person's yes on each write, the files of the
  one requirements-format change they linked to the topic."

## Apply

The branch that ships 0.5.0, in the same PR:

1. Applies the deltas to `specs/interview-handoff/spec.md` (`openspec archive add-requirements-format` does this
   and moves this folder to `changes/archive/`).
2. Edits X-2 in `reference/out-of-scope.md` by hand to the line above; archiving does not touch `reference/`.
3. Repoints its D39 tests: `REQS` now names the spec, so `^\*\*D39\.` becomes `^### Requirement: D39 · `, the
   `exception added by D39` check reads the spec (AGN-1), and the `since D39` check reads
   `reference/out-of-scope.md`. The existing D39 check accepts either location, so it needs no change.

D39 was smoke-validated against OpenSpec 1.16.0; this tree is validated with 1.15.0 (the version MNB pins). Both
accept these files.
