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
The plugin SHALL provide `/harness:feedback`. The person describes a problem with the harness, and the command SHALL file it as an issue without labels in the plugin's own repository. It SHALL add technical context: plugin version, runtime version, operating system and a state summary of the last run. It MUST NOT add private data: paths outside the plugin, tokens, ticket text or account names. It SHALL show the full text first and send only after a yes.

Source: owner decision 2026-11-26

#### Scenario: A report is filed
- **WHEN** the person runs `/harness:feedback`, describes a problem and says yes to the shown text
- **THEN** one issue without labels is created in the plugin's own repository
- **AND** it holds the description, the plugin version, the runtime version, the operating system and the state summary of the last run

#### Scenario: The person says no
- **WHEN** the person reads the shown text and does not say yes
- **THEN** nothing is sent

#### Scenario: Private data stays out
- **WHEN** the last run worked on tickets of a private project
- **THEN** the shown text holds no ticket text, no path outside the plugin, no token and no account name

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
- **THEN** a session of the real runtime is launched in the real iTerm2 app, receives an instruction, reads as alive and is closed gracefully

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

### Requirement: H-151 Every start checks that the selected settings are current for this machine
Before a run, the harness SHALL find the selected config. With no confirmation, H-072 applies, and the configuration skill it names runs the first setup. Otherwise the harness SHALL check that the settings still match this machine. A change that breaks them SHALL stop the start. A change in behaviour SHALL be asked about when attended and SHALL stop an unattended start. A change with no effect SHALL be logged.

Source: owner decision 2026-11-26 (review page, item 4): RP4.1
Decided: design.md D50

#### Scenario: Nothing is configured
- **WHEN** an attended run starts and no config applies at the project level or the user level
- **THEN** it stops as H-072 says, offers the default and names the configuration skill
- **AND** the configuration skill runs the first setup (H-152), whose flow question is that one confirmation

#### Scenario: Nothing is configured, unattended
- **WHEN** an unattended run starts and no config applies at the project level or the user level
- **THEN** it stops and raises an attention notice, as H-072 says

#### Scenario: A saved user default
- **WHEN** a run starts in a project with no project config and the person saved a confirmed default in the user settings
- **THEN** the run uses that default with no setup, as H-072 says
- **AND** the first such start records the machine state with the local selection, and later starts compare against it

#### Scenario: Nothing changed
- **WHEN** a run starts and the machine still matches the approved settings
- **THEN** the run starts and asks nothing

#### Scenario: A runtime the plan uses is logged out
- **WHEN** a run starts and a runtime that a step uses is no longer logged in
- **THEN** the run stops before any worker starts and names the runtime with its login step

#### Scenario: A flow system version changed
- **WHEN** an attended run starts and the flow system's minor version changed for one runtime since the approval
- **THEN** the harness shows the change, runs the readiness check (H-154) and asks one yes before it records the new state

#### Scenario: An unattended start finds a change that needs a yes
- **WHEN** a restart after a crash finds a change that needs the person's yes
- **THEN** it stops with an attention notice that names the change, and it asks nothing

#### Scenario: A patch update only
- **WHEN** a run starts and only a patch version of a runtime changed
- **THEN** the harness writes one log line and the run starts

#### Scenario: What the start compares
- **WHEN** a run starts with approved settings
- **THEN** it compares the runtimes and their logins, the accounts that roles use, the flow system for each runtime, the terminal backends and the repository access with the approved state

#### Scenario: The approved state changes only after a yes
- **WHEN** the start finds a change and nobody says yes to it
- **THEN** the record of the approved state stays as it was

### Requirement: H-152 The first setup is short: the harness studies the machine and recommends
The first setup SHALL study the machine before it asks. It SHALL ask only what it cannot find out and what the person must choose, each with a recommended answer and its reason. It SHALL ask at most five questions; every prompt that waits for an answer counts. Other settings keep their defaults. It SHALL write nothing before the last yes, and SHALL never pick a flow for the person.

Source: owner decision 2026-11-26 (review page, item 4): RP4.2, RP4.3
Decided: design.md D51

#### Scenario: The configuration skill runs the first setup
- **WHEN** a person starts the first setup
- **THEN** it runs in the configuration skill (H-127, H-128)

#### Scenario: The most questions
- **WHEN** both runtimes are ready, the repository holds a committed config and the person declines it
- **THEN** the setup still asks at most five questions: runtimes, flow and requirements format, autonomy level, limit thresholds, and the final save

#### Scenario: Offers go into the final save
- **WHEN** the setup also offers the verify-and-prove skill, adding a detected review bot, the OpenSpec setup and saving the flow as the user default
- **THEN** these appear as choices in the final save question, each with its recommended value, and none of them writes or installs anything before that yes

#### Scenario: A committed config shows its autonomy values
- **WHEN** the flow question offers a committed config
- **THEN** it shows that config's autonomy level and its push, PR and merge values, and taking it selects that autonomy profile (H-036)

#### Scenario: Each question shows its recommendation
- **WHEN** the setup asks the autonomy question on a machine whose account cannot push to the repository
- **THEN** it marks the safe level as recommended, says why, and shows the levels that need a push as unavailable

#### Scenario: A machine with one runtime
- **WHEN** a person runs the first setup on a machine with only Claude Code logged in and no harness config in the repository
- **THEN** the setup asks at most four questions: the flow and requirements format, the autonomy level, the limit thresholds, and the final save

#### Scenario: The repository already has a config
- **WHEN** a person runs the first setup in a repository that holds a committed harness config
- **THEN** the flow question offers that config first, and if the person takes it, the setup does not ask a separate autonomy question

#### Scenario: Something the machine shows is not asked
- **WHEN** the machine has one account and one supported terminal app
- **THEN** the setup asks neither about the account nor about the terminal

#### Scenario: The default flow is not installed
- **WHEN** the shipped default flow system is not installed for the main runtime
- **THEN** the setup still offers it, marks it "not installed" with its install step, and names a flow that runs now

#### Scenario: The person stops halfway
- **WHEN** the person leaves the setup before the last yes
- **THEN** no file is written

### Requirement: H-153 A separate evaluation proves the setup flow before release
The plugin SHALL have an evaluation of the setup flow over a fixed set of machine states, run before every release. For each state it SHALL check the number of questions, that nothing the machine shows is asked, that no default is wrong, and that nothing is installed or written without a yes.

Source: owner decision 2026-11-26 (review page, item 4): RP4.3
Decided: design.md D51

#### Scenario: The evaluation runs before a release
- **WHEN** the release checklist (H-141) runs
- **THEN** the setup evaluation runs over every machine state, three times each, and its result goes into the release PR
- **AND** a machine state passes only when all three runs pass

#### Scenario: A setup asks what it could detect
- **WHEN** a change makes the setup ask which terminal app to use on a machine with one supported terminal app
- **THEN** the evaluation fails

#### Scenario: A setup installs without a yes
- **WHEN** a change makes the setup run an install command before the person's yes
- **THEN** the evaluation fails

#### Scenario: The machine states
- **WHEN** the setup evaluation is built
- **THEN** it covers at least a fresh machine, Claude Code only, Codex only, both runtimes, a flow system for one runtime only, a stale profile after an upgrade, several accounts and no tracker access

#### Scenario: An unattended start waits for an answer
- **WHEN** a change makes an unattended start wait for an answer
- **THEN** the evaluation fails

### Requirement: H-154 A readiness check skill tells whether the settings can work
The plugin SHALL provide a readiness check skill, separate from the configuration skill and the project setup skill. It SHALL check whether the chosen settings can work on this machine, for every runtime and account the plan uses. It SHALL show one verdict and every missing item with its install step. Its scripted part SHALL be a read-only engine command that the start check also runs.

Source: owner decision 2026-11-26 (review page, item 4): RP4.4
Decided: design.md D52

#### Scenario: GSD is set up for both runtimes
- **WHEN** the plan runs GSD steps on Claude Code and on Codex, and GSD is installed for both at the same version
- **THEN** the verdict is ready

#### Scenario: GSD versions differ
- **WHEN** GSD is installed for both runtimes at different versions
- **THEN** the verdict is ready with notes, and the note names the older runtime and its update step

#### Scenario: A step's command is unknown for a runtime
- **WHEN** the check cannot confirm the form in which Codex calls a step's command
- **THEN** it reports that item as unknown, not as ready

#### Scenario: The setup ends with the check
- **WHEN** the first setup reaches its last step
- **THEN** it runs the readiness check on the chosen plan before it asks the final save question

#### Scenario: The start check uses the same command
- **WHEN** a run starts
- **THEN** the start check runs the read-only part of the readiness check and stops on a missing item

#### Scenario: Limits cannot be read
- **WHEN** the readiness check cannot read an account's limits
- **THEN** it reports a note and does not stop the start (H-111)

#### Scenario: The readiness check changes nothing
- **WHEN** a person runs the readiness check skill
- **THEN** it changes no settings; changing settings stays with the configuration skill

