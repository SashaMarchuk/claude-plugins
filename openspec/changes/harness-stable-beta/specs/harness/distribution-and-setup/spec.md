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

#### Scenario: Nothing is configured yet
- **WHEN** a person runs the harness configuration skill and nothing is configured
- **THEN** the skill recommends a flow the person already uses, if it finds one (H-069)
- **AND** otherwise it offers the default of H-001 for one confirmation
- **AND** it asks whether to save the confirmation in the user settings

#### Scenario: Limit thresholds are offered
- **WHEN** the skill reaches the limits settings
- **THEN** it offers a threshold of 90% for every window
- **AND** it switches thresholds on only after a yes (H-110)

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

### Requirement: H-140 A feedback command files a problem report as an issue, after the person's yes
The plugin SHALL provide `/harness:feedback`. The person describes a problem with the harness, and the command SHALL file it as an issue without labels in the plugin's own repository. It SHALL add technical context from fixed fields only, with no private data: no path outside the plugin, token, ticket text or account name. The description SHALL be sent as written. It SHALL show the full text first and send only after a yes.

Source: owner decisions 2026-11-26, 2026-11-27; design.md D43, D60

#### Scenario: A report is filed
- **WHEN** the person runs `/harness:feedback`, describes a problem and says yes to the shown text
- **THEN** one issue without labels is created in the plugin's own repository
- **AND** it holds the description, the plugin version, the runtime version, the operating system and the state summary of the last run

#### Scenario: The person says no
- **WHEN** the person reads the shown text and does not say yes
- **THEN** nothing is sent

#### Scenario: Private data stays out of the added context
- **WHEN** the last run worked on tickets of a private project
- **THEN** the added context holds no ticket text, no path outside the plugin, no token and no account name

#### Scenario: The description is sent as written (design.md D60)
- **WHEN** the person's description holds a path, a token or another private value
- **THEN** the shown text and the issue hold the description exactly as the person wrote it, and the harness removes nothing from it

#### Scenario: No run exists yet
- **WHEN** the person runs `/harness:feedback` before any run
- **THEN** the shown text says that there is no last run, and the rest of the context is still added

### Requirement: H-141 A release checklist is run in full before every release
The plugin SHALL keep a release checklist in its repository. Before every release, the checklist MUST be run in full, and the release MUST NOT be published while an item fails or is skipped. The results SHALL be recorded with the release. The checklist SHALL cover the automated tests, the real terminals (H-142) and the main success flow (H-143).

Source: owner decision 2026-11-26

#### Scenario: Every item passes
- **WHEN** a release is prepared and every checklist item passes
- **THEN** the release may be published
- **AND** the results are recorded with the release

#### Scenario: An item fails
- **WHEN** a checklist item fails
- **THEN** the release is not published until the cause is fixed and that item passes again

#### Scenario: An item is skipped
- **WHEN** a checklist item was not run
- **THEN** it counts as not passed, and the release is not published

### Requirement: H-142 Every release is checked on the real terminals with the real runtime
Before every release, each supported terminal backend, tmux and iTerm2, MUST be checked on the real terminal app with the real agent runtime, not a fake. For each backend, the check SHALL launch a session, deliver an instruction to it, read that it is alive, and close it gracefully. A backend that ran only against fakes MUST NOT count as checked.

Source: owner decision 2026-11-26; owner message 2026-11-25 (iTerm2 incident)

#### Scenario: tmux is checked
- **WHEN** the release checklist reaches the terminal checks
- **THEN** a session of the real runtime is launched in real tmux, receives an instruction, reads as alive and is closed gracefully

#### Scenario: iTerm2 is checked
- **WHEN** the release checklist reaches the terminal checks
- **THEN** a session of the real runtime is launched in the real iTerm2 app, receives an instruction by the message route, reads as alive and is closed gracefully
- **AND** typed delivery is not part of the iTerm2 check: iTerm2 never gets typed delivery, because its screen capture keeps no colours and an idle screen cannot be proven there

#### Scenario: A backend ran only against fakes
- **WHEN** a backend passed its automated tests against a fake terminal and was not run on the real app
- **THEN** its checklist item is not passed

### Requirement: H-143 The main success flow is checked end to end before every release
Before every release, the main success flow MUST be run end to end with the real agent runtime in a throwaway repository: a ready ticket is picked up, a worker does the work, an independent validator gives the verdict, and the engine merges only after its own checks, with git confirming the merge. From pickup to merge, the run MUST need no human action, under a profile that allows the merge.

Source: owner decision 2026-11-26; interview 2026-11-24 R30.5, R27.17

#### Scenario: The flow passes
- **WHEN** the checklist runs one ready ticket in a throwaway repository under a profile that allows the merge
- **THEN** the ticket is picked up, worked, validated by an independent validator and merged
- **AND** git confirms that the change is in the target branch

#### Scenario: A human hand was needed
- **WHEN** the run reaches the merge only after a person typed into a session or fixed a step by hand
- **THEN** the checklist item is not passed

#### Scenario: The merge is not confirmed
- **WHEN** the run reports a merge and git does not show the change in the target branch
- **THEN** the checklist item is not passed
