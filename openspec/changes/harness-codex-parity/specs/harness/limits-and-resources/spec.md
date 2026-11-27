## ADDED Requirements

### Requirement: H-162 Routing between subscriptions is offered only across providers
Load routing because of limits SHALL be offered by default only between subscriptions of different providers. Routing between subscriptions of one provider SHALL be off by default. A person with API billing MAY turn it on, and the setting SHALL show that it needs API credits. The same opt-in SHALL allow a Codex orchestrator to launch Claude Code sessions.

Source: owner decision 2026-11-26 (review page, item 3): RP3.19, RP3.20
Decided: design.md D59

#### Scenario: Two providers
- **WHEN** the person has a Claude subscription and a Codex subscription and allowed load routing
- **THEN** the orchestrator may move movable steps between them when one reaches its threshold

#### Scenario: Two subscriptions of one provider
- **WHEN** the person has two Claude subscriptions and no API billing opt-in
- **THEN** the harness does not move work from one to the other when one reaches its limit
- **AND** the run waits for the reset (H-114)

#### Scenario: The person turns on the opt-in
- **WHEN** the person turns on routing within one provider
- **THEN** the setup shows that this needs API billing with credits, and records the person's yes

#### Scenario: A fixed role account
- **WHEN** the person set the validator role to run on a second account
- **THEN** the validator runs on that account as set, and the harness never moves other work to it because of limits

#### Scenario: The billing path is recorded
- **WHEN** a session runs under the API billing opt-in
- **THEN** the session record names its billing path

