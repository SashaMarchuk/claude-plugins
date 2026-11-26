## ADDED Requirements

### Requirement: H-155 Codex can be the orchestrator of interactive terminal sessions
In a flow with interactive terminal sessions, Codex SHALL be able to act as the orchestrator, at the same level as Claude Code: launch sessions, deliver instructions, read the screen and close sessions. Every rule that binds the Claude Code orchestrator SHALL bind the Codex orchestrator in the same way.

Source: owner decision 2026-11-26 (review page, item 3): RP3.4, RP3.6, RP3.7
Decided: design.md D53

#### Scenario: A Codex orchestrator runs a ticket
- **WHEN** the config names Codex as the orchestrator runtime and a ticket is ready
- **THEN** the Codex orchestrator launches the worker session in a terminal, delivers the instruction, follows the session and closes it when the task ends

#### Scenario: The same safety rules apply
- **WHEN** the Codex orchestrator wants to type into a session whose input line holds the user's draft
- **THEN** it types nothing, as H-099 requires

#### Scenario: A Codex orchestrator and a Claude Code worker
- **WHEN** the config names Codex as the orchestrator and a step names Claude Code
- **THEN** the Codex orchestrator launches the Claude Code session only when the person has turned on the opt-in of H-162
- **AND** without that opt-in, the run stops at start and names the opt-in and its API billing hint

#### Scenario: A headless flow is chosen
- **WHEN** the user chooses a flow without interactive terminals
- **THEN** this requirement does not apply

### Requirement: H-156 Codex can be a worker in an interactive session
Codex SHALL be able to run any flow step as a worker in an interactive terminal session, when the flow config names Codex for the step and the readiness check (H-154) passes for Codex. Its result SHALL count the same as a result from Claude Code.

Source: owner decision 2026-11-26 (review page, item 3): RP3.12
Decided: design.md D53

#### Scenario: Execution runs on Codex
- **WHEN** the flow config names Codex for the execution step and the readiness check passes for Codex
- **THEN** the execution step runs in an interactive Codex session, and its result counts the same as from Claude Code

#### Scenario: Codex is not ready for a step
- **WHEN** the flow config names Codex for a step and the readiness check fails for Codex
- **THEN** H-159 applies

#### Scenario: Execution is not marked experimental after the success path
- **WHEN** the Codex success path of H-157 has passed for this release
- **THEN** the start output does not mark Codex execution as experimental

### Requirement: H-158 Terminal control corrects itself and records what it learned
The orchestrator SHALL learn from failed terminal actions. It SHALL find out what went wrong, finish the task another way, and record the correction for its version combination (H-149). Learning SHALL be off, ask or automatic, and the person SHALL be able to start it by command. A correction SHALL never weaken a safety rule.

Source: owner decision 2026-11-26 (review page, item 3): RP3.5, RP3.8
Decided: design.md D54

#### Scenario: An update breaks delivery
- **WHEN** a runtime update changes the screen so that the usual delivery check fails, and learning is automatic
- **THEN** the orchestrator finds a way that works, finishes the delivery, and records the correction under the new version combination

#### Scenario: Learning asks first
- **WHEN** learning is set to ask and the orchestrator finds a correction
- **THEN** it keeps the correction only after the person's yes, and uses it for this run only until then

#### Scenario: A correction would weaken a safety rule
- **WHEN** a found correction would type into a busy session
- **THEN** the orchestrator does not keep it and records why

#### Scenario: The person starts a learning pass
- **WHEN** the person runs the learning command
- **THEN** the orchestrator reviews the recent failed actions and proposes corrections
