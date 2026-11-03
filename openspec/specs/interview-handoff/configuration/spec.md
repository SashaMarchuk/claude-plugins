# configuration Specification

## Purpose
How interview-handoff stores, asks for and reuses its settings, including the config wizard, autopilot and language.

## Requirements

### Requirement: IH-012 Output location recommended, never forced
The plugin SHALL let the user set the output location at first run or through `config`, SHALL present `./docs/handoff/{topic}/` as the recommendation at the moment of asking, and SHALL NOT force it.

#### Scenario: Output location asked
- **WHEN** no output location is set and one is needed
- **THEN** the plugin asks, presents `./docs/handoff/{topic}/` as the recommendation, and uses the location the user sets

### Requirement: IH-015 Language detected by default
By default the plugin SHALL detect the language from the live conversation with the model at that moment, with no rule or recommendation in favour of English; configuration MAY set the language separately for the questions, the package documents and the analysis output.

#### Scenario: No language configured
- **WHEN** no language is configured and an artifact is written
- **THEN** its language is the one detected from the live conversation

### Requirement: IH-023 Shared and plugin-only settings
The language to speak to the person in and where session records live SHALL go to the general config (`shared/identity.json`); output location, package composition and the answers-file switch, per artifact language, labels, compression, context source and requirements format SHALL stay in the plugin's own file (`shared/plugins/interview-handoff.json`).

#### Scenario: Setting stored
- **WHEN** the plugin stores a setting
- **THEN** the speaking language and session-record location go to `shared/identity.json`, and output location, package composition, per artifact language, labels, compression, context source and requirements format go to `shared/plugins/interview-handoff.json`

### Requirement: IH-024 Config levels and placement
Configuration SHALL use the S&F levels, paths and precedence, and a value SHALL go to the general config when anything other than this plugin can use it, and to the plugin's own file only when nothing but this plugin can use it.

#### Scenario: Placement decided
- **WHEN** a value usable by more than this plugin is stored
- **THEN** it goes to the general config

### Requirement: IH-025 Source named session-logs
The source a session record is read from SHALL be named `session-logs`, never `transcripts`, because another plugin in this marketplace uses `transcripts` for a notetaker service.

#### Scenario: Source named
- **WHEN** the session-record source is named in config or source
- **THEN** it is `session-logs`

### Requirement: IH-029 Two-question first-run wizard
On a first run the config wizard SHALL ask only `output.path` and `language`; every other key SHALL keep a working default and be asked at its named in-context trigger, with the full sequence, wording and triggers written in `references/config.md`.

#### Scenario: First run
- **WHEN** the config wizard runs on a first run
- **THEN** it asks only `output.path` and `language`

### Requirement: IH-030 Config mode re-asks stored values
`config` mode SHALL start at the first question of the written sequence every time and SHALL ask whether a stored value is still current.

#### Scenario: Config re-run
- **WHEN** `config` runs with values already stored
- **THEN** it starts at the first question and asks whether each stored value is still current

### Requirement: IH-033 No setting is a precondition
No setting SHALL be a precondition for running: the plugin SHALL run with no configuration at any level, ask a missing value inline at the moment it is needed and write it down as configuration, and the wizard SHALL NOT gate the plugin.

#### Scenario: Setting missing
- **WHEN** a needed setting is missing
- **THEN** the plugin asks for it inline, writes it down, and continues

### Requirement: IH-034 Autopilot settles settings
Saying autopilot, or passing `--auto`, SHALL stop the questions about settings: values already on disk SHALL be reused, the written recommendation SHALL be taken for everything still unset, and the plugin SHALL then state what it chose and where it wrote it.

#### Scenario: Autopilot run
- **WHEN** the plugin runs under autopilot with settings unset
- **THEN** it reuses stored values, takes the written recommendation for the rest, and states what it chose and where it wrote it

### Requirement: IH-035 Autopilot covers settings only
Autopilot SHALL cover settings only and SHALL NOT answer a question about the subject being designed, pick a resource's trust level, or decide what the person meant.

#### Scenario: Subject question under autopilot
- **WHEN** a question about the subject comes up under autopilot
- **THEN** the plugin does not answer it on the person's behalf

### Requirement: IH-047 Every setting enumerable and re-askable
Every setting SHALL be enumerated in the wizard's closing line, and every deferred setting SHALL carry a trigger, so that it is shown back and can be asked again.

#### Scenario: Wizard closes
- **WHEN** the wizard closes
- **THEN** every setting is listed, and each deferred setting has a trigger at which it is asked again

### Requirement: IH-060 Config read first
The resolved config SHALL be read on every invocation, before any other work.

#### Scenario: Any invocation
- **WHEN** any command is invoked
- **THEN** the resolved config is read before any other work
