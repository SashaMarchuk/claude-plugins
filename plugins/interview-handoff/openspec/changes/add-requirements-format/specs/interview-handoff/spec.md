## ADDED Requirements

### Requirement: D39 · Confirmed decisions may also be carried into the project's requirements format, alongside the analysis, never instead of it

(round nine, plan reviewed independently and approved by the owner) OpenSpec is the first
format; each format is one file under `references/formats/`, and the plugin-config key `requirements.format`
selects it (null detects and asks once, `none` never asks; chosen by the owner over pure detection). The rules:

- The analysis is still written first, every round, and never rewritten. It is the evidence; the format's files are
  living documents anyone edits, so they are derived from it and are never evidence of what the person said.
- Only an item that is settled, confirmed, from a source-of-truth resource and free of an unresolved contradiction
  is eligible. Everything else stays open in the next round. A rejected premise is never turned into a removal by
  inference.
- Every write is previewed with the item id it comes from and made only on the person's yes. A requirement's
  wording and scenario are the plugin's formulation, so detail the person did not say needs its own yes. Autopilot
  never skips the preview, because it is a decision about the subject (D28).
- The plugin writes only inside the one change the person linked to the topic. It never edits the project's main
  specs, never archives or syncs, never asserts on the person's behalf that no behaviour changes, and never invents
  a requirement to satisfy a validator.
- In run, material taken from the format is current documented behaviour or a draft to ratify, never the person's
  decision, and never fills the rejected list.
- The link between a topic and its change, the ledger of what was written where, and any words the person changed
  in a preview live in the context document, which is the plugin's memory between rounds (D9, D22).

This amends the edit limit under "Not in scope" and the Agnosticism section. Details in
`references/formats/openspec.md`.

#### Scenario: Acceptance

Given a settled, confirmed item from a source-of-truth resource with no unresolved contradiction, and a requirements format selected by `requirements.format`, When `collect` has written the analysis, Then the plugin previews the write with the item id and makes it only on the person's yes, only inside the one change linked to the topic, after the analysis and never instead of it.

*Trace: REQUIREMENTS.md@74adee6 · D39*

## MODIFIED Requirements

### Requirement: AGN-1 · Agnosticism

No file under `commands/`, `skills/` or `scripts/` names a connector, and none names a method. The skill
names the sources it needs and reads what answers them from the resolved config. Concrete tool and method
names appear only in `config/recommended.json`, with one exception added by D39: a requirements format is
named inside its own file under `references/formats/`, and nowhere under `commands/`, `skills/` or `scripts/`.
The plugin declares no fixed connector, so the hardcoding exception does not apply to it.

`config/recommended.json` declares two sources, both with strength `weak`:

- `session-logs`, because the tool that holds a session recording differs from person to person, and
  several are plausible.
- `interview-method`, because the method that suits a person is theirs to pick, and any method installed
  in their environment can answer it.

That file is advisory. It is read only while a source is being **chosen**; it is never a config layer and
never contributes to a resolved value. See `references/config.md`.

*Amended by D39.*

#### Scenario: Acceptance

Given the files under `commands/`, `skills/` and `scripts/`, When they are searched for a connector or method name, Then none is found; concrete tool and method names appear only in `config/recommended.json`, and a requirements format is named only in its own file under `references/formats/`; `config/recommended.json` declares `session-logs` and `interview-method`, both `weak`, and is never a config layer.

*Trace: REQUIREMENTS.md@74adee6 · § Agnosticism*

### Requirement: CFG-1 · Configuration

Levels, paths and precedence are the S&F ones (D3). Which file a value lands in follows the
reusability test: anything usable by more than this plugin goes to the general config, and only a
value nothing but this plugin can use goes into the plugin's own file.

General config, `shared/identity.json`:

- `connectors.transcripts`, the source the resource is read from. The name matches the source
  `find-call` already uses in this same marketplace.
- the working language, when the user pins one instead of leaving it auto detected (D14).

Plugin config, `shared/plugins/interview-handoff.json`:

- output location (D11)
- which files the package contains, and whether the answers file is on (D2, D13)
- per artifact language overrides (D14)
- classification labels, when overridden (D12)
- whether normalisation is offered (D18)
- where the short context is taken from (D10)
- which requirements format confirmed decisions are also carried into (D39)

Behaviour required by the architecture:

- The plugin runs with no configuration at any level. It asks what it needs and writes the answer down
  as configuration.
- The resolved config is read on every invocation, before any other work.
- `config` mode starts at the first question every time, and asks whether a stored value is still
  current.

*Amended by D19 and D21. Refined by D20, D24 and D27.*

*Amended by D39.*

#### Scenario: Acceptance

Given no configuration at any level, When the plugin runs, Then it asks what it needs and writes the answer down as configuration, and on every invocation it reads the resolved config before any other work.

*Trace: REQUIREMENTS.md@74adee6 · § Configuration*
