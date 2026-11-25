## MODIFIED Requirements

### Requirement: H-001 Agnostic workflow of replaceable elements
The orchestrator's workflow MUST be agnostic and built from replaceable elements. When nothing is configured, the default MUST be GSD for execution and OpenSpec for requirements, and the person MUST confirm it once, in the configuration skill or at the first start. The confirmation MAY be saved in the person's user settings. A project setting MUST beat a user setting. OpenSpec MUST be swappable for another requirements format, or for none.

Source: owner decision 2026-11-26

#### Scenario: Default workflow
- **WHEN** the configuration skill or a first start runs and nothing is configured
- **THEN** the harness offers GSD for execution and OpenSpec for requirements
- **AND** it uses them only after the person confirms

#### Scenario: The confirmation is saved in the user settings
- **WHEN** the person saved a confirmed default in the user settings and a project sets nothing
- **THEN** runs in that project use the saved default without a new question

#### Scenario: The project beats the user
- **WHEN** the selected project config and the user settings name different flows or requirements formats
- **THEN** the project's choice is used

#### Scenario: An unattended run with no confirmation
- **WHEN** an unattended run starts and no confirmation exists at the user level or the project level
- **THEN** it stops and raises an attention notice
- **AND** it never picks a flow or a requirements format silently

#### Scenario: Another requirements format
- **WHEN** a run starts and the user prefers another requirements format, or none
- **THEN** that choice is used in place of OpenSpec
