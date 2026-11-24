## ADDED Requirements

### Requirement: H-125 The plugin id stays harness; the display name is Harness Orchestrator (decided name)
The plugin id SHALL stay `harness`, and its display name SHALL be "Harness Orchestrator" in its manifest, marketplace entry and README title. The `/harness:*` prefix and other on-disk names SHALL stay unchanged. The release SHALL carry a migration note for this registry-visible change (repository rule, not the owner's words).

Source: owner decision 2026-11-22, recorded before the interview (NAME-DECISION); migration note from the repository rule

#### Scenario: Migration note
- **WHEN** the release with the new display name ships
- **THEN** its migration note says users get the change through `/plugin update` without a reinstall

#### Scenario: A user browses the marketplace
- **WHEN** a user lists the plugins in the marketplace
- **THEN** the harness plugin shows the display name "Harness Orchestrator"
- **AND** its id is still `harness`

#### Scenario: An existing user updates
- **WHEN** an existing user runs `/plugin update`
- **THEN** the new display name appears
- **AND** every `/harness:*` command keeps its name and works without a reinstall

### Requirement: H-126 Short installation guide
The plugin SHALL provide a short installation guide for other people.

Source: interview 2026-11-24 R27.6

#### Scenario: A new user installs the plugin
- **WHEN** a new user follows the installation guide from start to end
- **THEN** the plugin is installed
- **AND** the guide is short

### Requirement: H-127 Two separate setup skills: harness configuration and project setup
The plugin SHALL provide two separate skills with different names: harness configuration fits the harness to a project, and project setup sets the project up for AI development. Names: design.md D33a.

Source: interview 2026-11-24 R27.7, R27.8, R27.9; D33
Decided: design.md D33a

#### Scenario: Final skill names
- **WHEN** the builder names the two skills
- **THEN** the working names are "config" and "setup", and the builder chooses the final names by careful analysis and a reinforcement loop (delegated to the builder; chosen names in design.md D33a: `/harness:config` and `/harness:ai-ready`)

#### Scenario: Which name fits which job
- **WHEN** the two jobs are assigned to the working names
- **THEN** each skill's job is taken from the content of R27.8 and R27.9: `/harness:config` is the harness configuration skill, and `/harness:ai-ready` is the project setup skill (design.md D33a)

#### Scenario: A user wants to change harness settings
- **WHEN** a user wants to change how the harness behaves in a project, such as its autonomy level
- **THEN** the user finds and runs the harness configuration skill
- **AND** the project setup skill is not needed for this

#### Scenario: A user wants to prepare a repository for AI development
- **WHEN** a user wants to add AI-development practices to a repository
- **THEN** the user finds and runs the project setup skill
- **AND** the harness configuration skill is not needed for this

### Requirement: H-128 The harness configuration skill builds the config profile and offers existing configs
The harness configuration skill SHALL cover the autonomy settings and every other setting the plugin can configure, and SHALL build a config profile from the answers. It SHALL stay relatively short. It SHALL read what it can from the person's memory and from what is installed. If configs already exist in the repository, it SHALL offer to use them. If none exist, it SHALL interview the person from scratch.

Source: interview 2026-11-24 R27.8

#### Scenario: The repository already has configs
- **WHEN** a person runs the harness configuration skill in a repository that already holds harness configs
- **THEN** the skill offers to use an existing config

#### Scenario: The repository has no configs
- **WHEN** a person runs the harness configuration skill in a repository with no harness configs
- **THEN** the skill uses what it can read from memory and installed tools
- **AND** it interviews the person from scratch and writes a config profile

#### Scenario: The skill covers every plugin setting
- **WHEN** a person runs the harness configuration skill
- **THEN** every setting the plugin offers, including the autonomy settings, can be set through this skill

### Requirement: H-129 The project setup skill applies AI-development practices
The project setup skill SHALL apply AI-development best practices to the repository, so that AI development there is more reliable. The scenarios give examples; the list is open, not the full set. The skill MUST NOT set up a flow system such as GSD (design.md D37-DISTRIBUTION-1).

Source: interview 2026-11-24 R27.9
Decided: design.md D37-DISTRIBUTION-1

#### Scenario: Hooks are added
- **WHEN** a person runs the project setup skill and hooks fit the repository
- **THEN** the skill may add hooks as one of its AI-development practices

#### Scenario: No flow system is set up
- **WHEN** a person runs the project setup skill
- **THEN** the skill does not install or configure a flow system such as GSD

#### Scenario: SECURITY.md is missing
- **WHEN** a person runs the project setup skill in a repository without SECURITY.md
- **AND** adding it is best practice for that repository
- **THEN** the skill adds SECURITY.md

#### Scenario: CLAUDE.md exists
- **WHEN** a person runs the project setup skill in a repository with a CLAUDE.md
- **THEN** the skill reviews CLAUDE.md against AI-development best practices
- **AND** it adds an AGENTS.md symlink if one is missing

### Requirement: H-130 The README lists the tested flow systems
The plugin README SHALL state which flow systems the harness was tested with. It SHALL also state that other flow systems are possible but untested.

Source: interview 2026-11-24 R16.5

#### Scenario: A user checks flow support
- **WHEN** a user reads the plugin README to see which flow systems work
- **THEN** the README names the flow systems that were tested before release
- **AND** it says that other flow systems may work but were not tested

### Requirement: H-131 Documentation explains how to set up or bypass the harness
Documentation SHALL explain how to set up the harness in a project that already uses it, and how to bypass it. It MUST say that working without the harness is not blocked. Where this text lives and how it is worded is in design.md D19.

Source: interview 2026-11-24 R17.10; D19

#### Scenario: A newcomer does not want the harness
- **WHEN** a newcomer finds harness config files in a project and does not want to use the harness
- **THEN** the documentation explains how to work without the harness (bypass it)
- **AND** it says their work is not blocked without the harness

#### Scenario: A newcomer wants the harness
- **WHEN** a newcomer finds harness config files in a project and wants to use the harness
- **THEN** the documentation tells them how to set the harness up
