# History

Frozen. How these requirements came to be; nothing here is a requirement.

## Origin (`REQUIREMENTS.md`, header)

Status: agreed in a grilling session on 2026-08-21, five rounds, frontier empty. Built on 2026-08-22.
Nothing here was decided by the author. Every line traces to an answer given in those rounds.
Amendments after an independent validation are at the end of this file.

Each decision carries the round it was settled in.

## Amendments after independent validation, 2026-08-21

An independent review checked this spec against the two real sessions it generalises. Its verdict was that
the core is sound and the spec had dropped the two most valuable products of the manual process: the rules
governing interviewer behaviour, and the discipline of the analysis. The amendments below close that, plus
four owner decisions taken in a fifth round.

(The four owner decisions are D19 to D22; the amendments carried without a new decision are AMD-1 to AMD-10.)

## Moved into OpenSpec, 2026-11-02

Owner decision 2026-11-02 closed this open question, which the later lists shortened to "Whether
`REQUIREMENTS.md` stays in the plugin folder.":

> Whether `REQUIREMENTS.md` stays in the plugin folder or moves once the plugin is built.

It moved into this tree, losslessly, from `REQUIREMENTS.md` at `fd6125e`.

- Decisions D1 to D38 keep their numbers and wording; the bold title became the requirement name.
- Each untitled section (The resource, The package, The analysis, Configuration, Agnosticism) became one
  requirement (RES-1, PKG-1, ANL-1, CFG-1, AGN-1) with its text unchanged; the ten amendments carried without a
  new decision became AMD-1 to AMD-10.
- Added during the move, and nothing else: one `#### Scenario: Acceptance` per requirement, which restates the
  requirement and adds nothing to it; one `*Trace:*` line per requirement; an `*Amended by*` or `*Refined by*`
  line where a later decision changes an earlier one.
- "Not in scope" became `reference/out-of-scope.md` (X-1 to X-4). The source repeated its "not decided" list
  three times as amendments landed; the union is `reference/open-questions.md` (Q-1, Q-2).
- The full original stays in git history: `git show fd6125e:plugins/interview-handoff/REQUIREMENTS.md`.
