## ADDED Requirements

### Requirement: IH-073 Confirmed decisions carried into a requirements format
When `requirements.format` is set to a format, collect SHALL, after the analysis is written, carry into that format only items that are settled, confirmed, from a source-of-truth resource and free of unresolved contradictions, previewing every write and making it only on the person's yes, never replacing the analysis and never editing the project's main specs.

#### Scenario: Confirmed decision written after a yes
- **WHEN** an item is settled and confirmed from a source-of-truth resource and the person says yes to its previewed block
- **THEN** the block is written into the change linked to the topic, and the analysis is left as written

#### Scenario: Unconfirmed item stays open
- **WHEN** an item is partial, not ratified, contradicted or from a resource that needs confirmation
- **THEN** nothing is written for it and it stays open for the next round

#### Scenario: Autopilot still previews
- **WHEN** the person is on autopilot
- **THEN** every requirements-format write is still previewed and waits for their yes

#### Scenario: Nothing to carry
- **WHEN** a round produced no confirmed item that the format accepts
- **THEN** nothing is written and formats are not mentioned

### Requirement: IH-074 Requirements formats are off unless chosen
`requirements.format` SHALL default to `none`, under which the plugin neither detects, asks about nor mentions any format. It SHALL otherwise name a template under `references/formats/` or be `custom`, where `requirements.custom` holds the person's own instruction. When the chosen template is absent from the project, the plugin SHALL ask explicitly before using it there, and autopilot SHALL NOT answer that question.

#### Scenario: Default
- **WHEN** `requirements.format` is unset or `none`
- **THEN** run and collect behave as if no requirements format existed, with no detection and no question

#### Scenario: Template missing from the project
- **WHEN** `requirements.format` is `openspec` and the project has no OpenSpec root
- **THEN** the plugin asks whether to use OpenSpec in this project, writes nothing on a no, and records the answer for the project

#### Scenario: Custom instruction
- **WHEN** `requirements.format` is `custom`
- **THEN** collect follows `requirements.custom` with the same guards as a template: confirmed items only, each write previewed and made on a yes
