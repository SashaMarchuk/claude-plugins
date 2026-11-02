# plugin-shape Specification

## Purpose
What interview-handoff is and where its boundaries lie: it prepares an interview that someone else runs and analyses the result, and it is never the interviewer.

## Requirements

### Requirement: IH-003 S&F marketplace architecture
The plugin SHALL follow the S&F marketplace architecture (in the snf-automation-workspace checkout: `requirements/OWNER-DECISIONS.md`, `plugin-anatomy.feature`, `plugin-commands.feature`, `plugin-agnosticism.feature`, `config-read.feature`, `.arch-work/drafts/config-levels-DRAFT.md`): a thin command plus a hidden skill, config read on every run, `config/recommended.json` for outside tools, and no connector named in shipped code.

#### Scenario: Architecture followed
- **WHEN** the plugin's source is checked against the S&F marketplace architecture
- **THEN** it has a thin command plus a hidden skill, reads config on every run, keeps outside tools in `config/recommended.json` and names no connector in shipped code

### Requirement: IH-006 Plugin name
The plugin SHALL be named `interview-handoff`, in kebab case, with no `snf-` or `claude-` prefix.

#### Scenario: Name checked
- **WHEN** the plugin is listed in the marketplace
- **THEN** its name is `interview-handoff`, with no `snf-` or `claude-` prefix

### Requirement: IH-007 Three commands
The plugin SHALL provide three commands: `run`, `collect` and `config`.

#### Scenario: Commands listed
- **WHEN** the plugin's commands are listed
- **THEN** they are `run`, `collect` and `config`

### Requirement: IH-008 Home repository
The plugin SHALL live in the `SashaMarchuk/claude-plugins` marketplace and SHALL follow the S&F architecture inside it.

#### Scenario: Home checked
- **WHEN** the plugin's home is checked
- **THEN** it is the `SashaMarchuk/claude-plugins` marketplace

### Requirement: IH-058 No connector or method named in code
No file under `commands/`, `skills/` or `scripts/` SHALL name a connector or a method; the skill SHALL name the sources it needs and read what answers them from the resolved config, and concrete tool and method names SHALL appear only in `config/recommended.json`.

#### Scenario: Source searched for names
- **WHEN** the files under `commands/`, `skills/` and `scripts/` are searched for a connector or method name
- **THEN** none is found, and concrete names appear only in `config/recommended.json`

### Requirement: IH-059 Recommended sources are advisory
`config/recommended.json` SHALL declare two sources, `session-logs` and `interview-method`, both with strength `weak`, and SHALL be advisory: read only while a source is being chosen, never a config layer, and never contributing to a resolved value.

#### Scenario: Recommendations read
- **WHEN** a source is resolved for a run
- **THEN** `config/recommended.json` contributes nothing to the resolved value, and is read only while a source is being chosen

### Requirement: IH-068 Never the interviewer
The plugin SHALL NOT run the interview itself.

#### Scenario: Interview needed
- **WHEN** a package is ready
- **THEN** the interview is run by a separate interviewer, not by the plugin

### Requirement: IH-069 Edits only its own output
The plugin SHALL NOT edit anything except its own package files and the analysis output.

#### Scenario: Files written
- **WHEN** the plugin runs
- **THEN** the only files it changes are its package files and the analysis output

### Requirement: IH-070 Never answers for the user
The plugin SHALL NOT invent an answer and SHALL NOT close a question on the user's behalf.

#### Scenario: Unanswered question
- **WHEN** a question has no answer from the user
- **THEN** it stays open

### Requirement: IH-071 No tracker, git workflow or CI
The plugin SHALL NOT pull in a task tracker, a git workflow or CI.

#### Scenario: Dependencies checked
- **WHEN** the plugin's behaviour is checked
- **THEN** it uses no task tracker, git workflow or CI

### Requirement: IH-072 No fixed connector
The plugin SHALL declare no fixed connector, so the hardcoding exception of the S&F architecture does not apply to it.

#### Scenario: Manifest checked
- **WHEN** the plugin's declared connectors are checked
- **THEN** none is fixed
