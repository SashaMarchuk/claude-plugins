# interview-method Specification

## Purpose
How interview-handoff resolves the interview method it grills with and points the interviewer at, without ever copying it.

## Requirements

### Requirement: IH-026 Method resolved on every run
The skill SHALL name the source `interview-method` and resolve what answers it from the config on every run, so an updated or newly available method is used as it now is, with concrete candidates appearing only in `config/recommended.json`.

#### Scenario: Method needed
- **WHEN** a run needs the interview method
- **THEN** it is resolved from the config on that run

### Requirement: IH-027 Built-in method fallback
The plugin SHALL ship its own compact method in `references/interview-method.md` and fall back to it when nothing else is available, so it never depends on a method it did not ship.

#### Scenario: No method available
- **WHEN** no other method is available
- **THEN** the plugin uses `references/interview-method.md`

### Requirement: IH-028 Drivable method checked
Before recommending a resolved method, the plugin SHALL check whether the skill can drive it or it must be handed to the user.

#### Scenario: Method recommended
- **WHEN** the plugin is about to recommend a resolved method
- **THEN** it has checked whether the skill can drive it

### Requirement: IH-041 Method referenced, resolved by name first
A method SHALL be referenced, never stored as a frozen copy, and SHALL be resolved by exact name first, then the stored path, then the stored URL, then the built-in method.

#### Scenario: Stored path stops resolving
- **WHEN** the stored path does not resolve but a method with the exact name is installed
- **THEN** the installed method is used

### Requirement: IH-042 Remote method by URL
When the method is not installed locally, its URL SHALL be handed over, or fetched at that moment and passed inline.

#### Scenario: Method not installed
- **WHEN** the method is not installed locally
- **THEN** its URL is handed over, or its text is fetched and passed inline

### Requirement: IH-043 Stored value carries name, path and URL
The stored method value SHALL carry `name`, `path` and `url` together: the name resolves it, the path records which copy was actually read, and the URL is copied in at write time, so the run-time branch never reads `config/recommended.json` and an interviewer running elsewhere is never handed a path it cannot open.

#### Scenario: Method value stored
- **WHEN** a method choice is written to config
- **THEN** it carries `name`, `path` and `url`

### Requirement: IH-044 Exact name matching
Method names SHALL be matched exactly, never loosely; the plugin SHALL ask rather than silently choose between similar names.

#### Scenario: Similar names
- **WHEN** two installed methods have similar names
- **THEN** neither is chosen by a loose match

### Requirement: IH-046 Package points at the method
The generated prompt SHALL name the resolved method by path, and by URL where one exists, and SHALL inline the method's text only when neither can be reached.

#### Scenario: Prompt generated
- **WHEN** the prompt is generated with a resolved method
- **THEN** it names the method by path, and by URL where one exists

### Requirement: IH-048 Method source disclosed
The plugin SHALL tell the person which method it is using and where it actually read it from, even when that differs from the configured path.

#### Scenario: Method loaded from another copy
- **WHEN** the method is loaded from a copy other than the configured path
- **THEN** the person is told which copy is in play

### Requirement: IH-051 One obvious method taken
On a clean first run with exactly one method in exactly one copy, the plugin SHALL take it, name it out loud along with the copy that was read, and offer the person the chance to settle it, an offer that SHALL NOT block the first round.

#### Scenario: Single method installed
- **WHEN** a clean first run finds exactly one method in exactly one copy
- **THEN** the plugin takes it, names it and its copy, and starts the first round

### Requirement: IH-052 Several or no methods go to the person
With more than one method, the same method in more than one copy, or none at all, the plugin SHALL let the person pick, showing what is installed alongside the candidates; under autopilot it SHALL still write without asking.

#### Scenario: Two methods installed
- **WHEN** more than one method is installed and autopilot is off
- **THEN** the person picks, shown what is installed alongside the candidates

### Requirement: IH-053 No phantom contradiction
On a run where nothing was configured, the plugin SHALL NOT report a difference between `config/recommended.json` and what is installed as though the person's configuration had been contradicted.

#### Scenario: Nothing configured
- **WHEN** nothing is configured and the installed method differs from `config/recommended.json`
- **THEN** no contradiction of the person's configuration is reported
