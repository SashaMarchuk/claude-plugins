## ADDED Requirements

### Requirement: H-157 Test depth for each runtime and role
Before a release, Claude Code as the orchestrator SHALL be tested fully on the real terminals (H-142). Codex SHALL be tested on its main success path for terminal control, as orchestrator and as worker. A comparison run SHALL show that both runtimes give the same result. A Codex orchestrator launching Claude Code SHALL NOT be required in the tests.

Source: owner decision 2026-11-26 (review page, item 3): RP3.7, RP3.11, RP3.22
Decided: design.md D53

#### Scenario: The release checks for Codex
- **WHEN** the release checklist runs
- **THEN** it runs the Codex success path on tmux and on iTerm2, with Codex as orchestrator and as worker, and records the result

#### Scenario: The comparison run
- **WHEN** the release checklist runs
- **THEN** one ticket flow runs once with Codex and once with Claude Code in the same roles, and the release records whether both give the same result
- **AND** if they differ, Codex execution stays experimental in that release

#### Scenario: Codex launching Claude Code
- **WHEN** the release checklist runs
- **THEN** a Codex orchestrator launching Claude Code sessions is not required in it, and the "tested with" list says whether it was tested

### Requirement: H-164 The plugin and the marketplace also install in Codex
The harness plugin SHALL install and work in Codex too, and every plugin in the marketplace SHOULD. The marketplace layout MAY change for this. A current Claude Code user SHALL keep getting updates without a reinstall. A test SHALL prove that a skill of the plugin runs in both tools.

Source: owner decision 2026-11-26 (review page, item 4): RP4.5
Decided: design.md D60

#### Scenario: Install in Codex
- **WHEN** a Codex user adds the marketplace with the Codex plugin command and installs the harness
- **THEN** the harness skills are available in Codex

#### Scenario: A Claude Code user updates
- **WHEN** a Claude Code user who installed a plugin before the layout change runs the plugin update command
- **THEN** the plugin updates without a reinstall

#### Scenario: A part works in one tool only
- **WHEN** a plugin has a part that works only in Claude Code, such as a hook or a slash command
- **THEN** its README says so and names the Codex equivalent, or says there is none

#### Scenario: The cross-tool test
- **WHEN** the test suite runs with both tools logged in
- **THEN** a probe skill of the plugin runs in Claude Code and in Codex and each run leaves its proof file
