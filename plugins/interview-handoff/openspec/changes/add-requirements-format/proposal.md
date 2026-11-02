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

The branch that ships 0.5.0 applies these deltas to `specs/interview-handoff/spec.md` and the X-2 line above in
the same PR, then moves this folder to `changes/archive/`.
