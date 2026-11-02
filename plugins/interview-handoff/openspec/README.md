# interview-handoff — requirements (OpenSpec)

What this plugin must do. Moved here losslessly on 2026-11-02 from `../REQUIREMENTS.md` (owner decision); how
the move was made is in `HISTORY.md`. This is the plugin's own OpenSpec root, isolated from every other plugin.

| Path | What it holds |
|---|---|
| `specs/interview-handoff/spec.md` | The requirements: decisions D1–D38 (numbers and wording kept), the sections RES-1, PKG-1, ANL-1, CFG-1, AGN-1, and the amendments AMD-1–AMD-10. One `#### Scenario: Acceptance` each |
| `reference/out-of-scope.md` | X-: never built |
| `reference/open-questions.md` | Q-: not decided. Never build against these; ask the owner |
| `changes/<change>/` | Decided but not yet on `main`: a proposal plus deltas (ADDED / MODIFIED / REMOVED by ID). `add-requirements-format` carries D39 |
| `changes/archive/` | Applied changes. Never edited |
| `HISTORY.md` | Origin of the requirements and of the move. Frozen |

A new decision gets the next free D-number and goes in through a change; IDs are never renumbered or reused.
Validate from this plugin's folder (the "SHALL or MUST" and "very long" warnings are expected, because the
decisions keep their original wording):

    OPENSPEC_TELEMETRY=0 npx -y @fission-ai/openspec@1.15.0 validate --all --no-interactive

This folder ships with the plugin when it is installed. It is documentation only; nothing reads it at run time.
