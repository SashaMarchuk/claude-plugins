## ADDED Requirements

### Requirement: H-064 The full cycle of stages runs by default; every ticket goes through every step in order
By default, the harness SHALL run the whole cycle for every ticket, and each ticket MUST go through every step in order: classification (described well enough, or needs clarifying questions), a discussion (grilling) step if there are questions, planning, execution, code review, verification and a UI check. The ticket SHALL move to shipping only when all these steps pass. In shipping, a PR is created and reviewed.

Source: interview 2026-11-24 R15.1, R15.13

#### Scenario: A well-described ticket runs the default cycle
- **WHEN** a ticket is described well enough and the flow configuration changes nothing
- **THEN** the ticket goes through classification, planning, execution, code review, verification and the UI check, in that order
- **AND** only then does it move to shipping, where a PR is created and reviewed

#### Scenario: A ticket with open questions is grilled first
- **WHEN** the classification step finds that the ticket needs clarifying questions
- **THEN** the discussion (grilling) step runs before planning

#### Scenario: A failed step blocks shipping
- **WHEN** any step before shipping does not pass
- **THEN** the ticket does not move to shipping

### Requirement: H-065 A flow configuration, separate from the profile, that the orchestrator follows
The harness SHALL have a flow configuration that describes, step by step from start to end, what happens when a ticket enters work, including how it is tested. The orchestrator MUST follow it. It SHALL be a setting of its own, separate from the autonomy profile (design.md D12), possibly per person (design.md S8-16b). Where the step list lives: design.md S8-15.

Source: interview 2026-11-24 R15.2, R15.15; S8-15
Decided: design.md D37-FLOW-3

#### Scenario: The orchestrator follows the configured steps
- **WHEN** a ticket enters work
- **THEN** the orchestrator moves it through the steps that the flow configuration describes, in their configured order

#### Scenario: The flow is changed without changing the profile
- **WHEN** the user changes the flow configuration
- **THEN** the autonomy profile file stays unchanged

### Requirement: H-066 Steps can be reordered, added, switched off and given a runner
Per project, the flow configuration SHALL let the user reorder, add and switch off steps, and name each step's runner. A step MAY be switched off when something else does it. Custom steps MAY be added between steps, for example before or after code review. Code review before the PR is opened SHALL be an allowed order.

Source: interview 2026-11-24 R15.3, R15.4, R15.5, R15.9
Decided: design.md D37-FLOW-2 (steps between steps need an own step list)

#### Scenario: A version bump step
- **WHEN** the flow configuration adds a version-bump step
- **THEN** that step runs where the configuration places it

#### Scenario: A connection check step
- **WHEN** the flow configuration adds a check of an MCP or tracker connection
- **THEN** that check runs where the configuration places it

#### Scenario: A test audit before code review
- **WHEN** the flow configuration adds a test-audit step right before code review
- **THEN** every ticket runs the test audit before code review

#### Scenario: Code review is left to an external reviewer
- **WHEN** the flow configuration switches off the harness code review step because a review bot reviews every PR
- **THEN** the harness does not run its own code review step

#### Scenario: A test audit is added after code review
- **WHEN** the flow configuration adds a test-audit step right after code review
- **THEN** every ticket runs the test audit after code review and before the next step

#### Scenario: A project-specific test step
- **WHEN** a project adds a testing step that first starts a client connection the app needs, for example a connection to a chat service
- **THEN** that step runs as part of the project's flow

#### Scenario: Code review before the PR
- **WHEN** the flow configuration places code review before PR creation
- **THEN** the harness runs the review first and opens the PR afterwards

#### Scenario: A step is given a runner
- **WHEN** the flow configuration names the runner of a step
- **THEN** that runner performs the step

### Requirement: H-067 A chosen flow system owns its steps
A flow configuration MAY point to a chosen flow system with its own workflow, for example GSD. The harness SHALL check that workflow and apply it. The step mechanism MUST be simple and reliable. On conflict, the harness SHALL follow the rule in design.md D17 (delegated agent decision; the owner's lean in R15.7 matches): the chosen system owns its steps, as the scenarios detail.

Source: interview 2026-11-24 R15.6, R15.7, R15.8; D17
Decided: design.md D37-FLOW-2

#### Scenario: A chosen system's workflow is applied
- **WHEN** the flow configuration points to GSD
- **THEN** the harness checks the GSD workflow and runs the ticket through it

#### Scenario: A harness setting conflicts with the chosen system
- **WHEN** the harness flow says how to do a step and the chosen system does that step its own way
- **THEN** the chosen system's way wins
- **AND** the harness setting reaches the session only as a hint

#### Scenario: A harness extra step next to a chosen system
- **WHEN** the flow configuration adds a harness extra step to a flow that uses a chosen system
- **THEN** the extra step runs before or after the chosen system's steps

#### Scenario: Lifecycle gates stay with the harness
- **WHEN** a chosen system runs a ticket's steps
- **THEN** the harness still applies its own lifecycle gates to that ticket

#### Scenario: A flow config names both a system and its own step list
- **WHEN** a flow configuration points to a chosen system and also holds its own step list
- **THEN** the harness stops at start with a clear message
- **AND** it does not merge the two lists

#### Scenario: A step is placed inside a chosen system's steps
- **WHEN** a flow configuration that uses a chosen system places a step between that system's steps
- **THEN** the harness stops at start and names the step
- **AND** the message names the route: copy the system's step list into an own flow

### Requirement: H-068 Any flow system is supported; the flow is the person's confirmed choice
The harness MUST support any flow system; named ones (GSD, superpowers) are examples only. Nothing SHALL restrict the choice, and no flow system's name SHALL be hard-coded in engine code. The flow SHALL be the person's confirmed choice: a ready-made flow, an own flow, or the default of H-001. The harness MUST NOT use a flow that nobody confirmed.

Source: interview 2026-11-24 R16.1, R16.2; S8-16a; owner decision 2026-11-26
Decided: design.md D37-FLOW-1

#### Scenario: The user picks a ready-made flow
- **WHEN** the user picks a ready-made flow during setup
- **THEN** the harness runs tickets by that flow

#### Scenario: The user sets up an own flow
- **WHEN** the user chooses to set up an own flow
- **THEN** the harness lets the user define the steps of that flow
- **AND** runs tickets by it

#### Scenario: The default is confirmed
- **WHEN** nothing is configured and the person confirms the default at setup
- **THEN** the harness runs tickets by the GSD flow
- **AND** the flow's name comes from the shipped default config, not from engine code

#### Scenario: A system the harness has not seen before
- **WHEN** the user points the flow configuration to a flow system that is not among the named examples
- **THEN** the harness does not refuse it because of its name

#### Scenario: Nothing is configured and nothing is confirmed
- **WHEN** a run starts, no flow is configured at the project level or the user level, and no confirmation exists
- **THEN** the harness uses no flow silently
- **AND** it follows H-072

#### Scenario: The chosen flow cannot be loaded
- **WHEN** a run starts and the named flow file is missing or unreadable
- **THEN** the harness stops at start and names the flow
- **AND** it does not fall back to another flow or to the default

### Requirement: H-069 Setup recommends the flow the person already uses
At setup, the configuration flow SHALL check the person's memory and existing setup. If it finds an existing flow, it SHALL recommend that flow and say whether it is on the tested list (design.md D37-FLOW-6). If it finds none, it SHALL offer the default of H-001, and the person MAY create an own flow instead. The recommendation MUST NOT replace the person's explicit choice.

Source: interview 2026-11-24 R16.6; owner decision 2026-11-26
Decided: design.md D37-FLOW-6

#### Scenario: An existing flow is found
- **WHEN** setup finds that the person already uses GSD
- **THEN** setup recommends GSD
- **AND** the person still confirms or changes the choice

#### Scenario: No existing flow is found
- **WHEN** setup finds no flow in the person's memory or setup
- **THEN** setup offers the default: the GSD flow with OpenSpec
- **AND** the person confirms it, picks another flow, or creates an own flow

#### Scenario: The found flow is not on the tested list
- **WHEN** setup finds a flow system that the README does not list as tested
- **THEN** setup still recommends it and says that it is not tested with the harness
- **AND** the person still confirms or changes the choice

### Requirement: H-070 Configs, profiles and flows may live in the repo, named for their owner
Harness configuration files (settings, profiles and flows) MAY live in the project repo, and the harness SHALL be able to reuse them. These files SHALL be configuration only. A person without the harness MUST be able to work their own way, unaffected; nobody SHALL be forced to use the committed workflow. A config file MAY be named to show whose it is. The harness SHALL run by the config that is selected.

Source: interview 2026-11-24 R17.1, R17.2, R17.3

#### Scenario: Committed configs are reused
- **WHEN** the project repo holds harness settings, profiles and flows
- **THEN** the harness uses them

#### Scenario: A developer works without the harness
- **WHEN** a developer without the harness works in a repo that holds harness configs
- **THEN** the developer's own way of working is not affected

#### Scenario: Two named configs in one repo
- **WHEN** the repo holds two flow configs, each named for its owner
- **THEN** the harness runs by the one that is selected, and ignores the other

### Requirement: H-071 A local file selects the config to use
A local file on each machine SHALL select which committed config the harness uses, or record that the confirmed default is used. Two machines that clone the same repo MUST be able to do a short harness setup and then reuse the same committed workflow. Whether the flow is chosen per project or per person is set in design.md S8-16b.

Source: interview 2026-11-24 R17.4; S8-16b
Decided: design.md D37-FLOW-5 (where the local file lives, that it is not committed, and what remote config means)

#### Scenario: A second machine reuses the committed workflow
- **WHEN** a second machine clones a repo with a committed workflow and runs the short harness setup
- **THEN** a local file on that machine selects the committed workflow
- **AND** the harness on that machine runs by it

#### Scenario: Two people select different configs
- **WHEN** two people select different committed configs in their local files
- **THEN** each person's harness runs by the config that person selected

#### Scenario: The local file is not committed
- **WHEN** the configuration skill writes the local file
- **THEN** git does not track that file
- **AND** the repository's shared ignore file is unchanged

### Requirement: H-072 A missing confirmation stops the harness and asks once
With no confirmed config for the project on this machine, the harness SHALL stop development and ask once. A committed config SHALL need the person's yes on this machine. With no config anywhere, the harness SHALL offer the default of H-001. A saved user default SHALL count only when the repo holds no config. An unattended run SHALL stop and raise an attention notice, and MUST NOT pick silently.

Source: interview 2026-11-24 R17.9; owner decision 2026-11-26
Decided: design.md D37-FLOW-4

#### Scenario: A committed config is found and accepted
- **WHEN** the harness starts with no local selection and the repo holds a config
- **THEN** the harness stops and asks whether to use that config
- **AND** on yes, it creates a local file that points to the config
- **AND** the same yes writes the record of the approved profile, so the first start does not stop a second time (design.md D37-FLOW-8)

#### Scenario: The committed config is declined
- **WHEN** the person declines the committed config
- **THEN** the harness guides the person through creating a new workflow

#### Scenario: Nothing is configured anywhere
- **WHEN** the harness starts with no local selection, the repo holds no config, and the user settings hold no confirmed default
- **THEN** the harness stops, offers the default (the GSD flow with OpenSpec) and names the configuration skill, which recommends a flow the person already uses (H-069)
- **AND** on yes, it writes the local file that records the confirmation, and asks whether to save the confirmation in the user settings
- **AND** the person may pick another flow or requirements format through the configuration skill instead

#### Scenario: A confirmed default is saved in the user settings
- **WHEN** the harness starts with no local selection, the repo holds no config, and the user settings hold a confirmed default
- **THEN** the run starts without a question
- **AND** the local file records that the confirmation came from the user settings

#### Scenario: A committed config next to a saved user default
- **WHEN** the harness starts with no local selection, the repo holds a config, and the user settings hold a confirmed default
- **THEN** the harness still stops and asks whether to use the committed config
- **AND** the saved user default does not accept it

#### Scenario: A config is committed after a start on the default
- **WHEN** a project runs on the confirmed default and a config later appears in the repo
- **THEN** the harness keeps the confirmed selection and prints one notice that names the new config
- **AND** it uses that config only after the person selects it

#### Scenario: An unattended start with no confirmation
- **WHEN** an automatic restart, a resume or another unattended start finds no confirmation at the project level or the user level
- **THEN** it stops and raises an attention notice
- **AND** it picks no flow, no requirements format and no config

#### Scenario: A developer without the harness is not blocked
- **WHEN** a developer who does not use the harness works in the same repo
- **THEN** nothing in the harness blocks that developer's work

#### Scenario: The selection names a missing config
- **WHEN** the local file names a config that is missing or unreadable
- **THEN** the harness stops as with no confirmation
- **AND** it does not fall back to another config, to the saved user default or to the shipped default config

### Requirement: H-073 Flow systems are linked, never vendored, and checked present at start
Flow systems, such as GSD, SHALL NOT be stored in the project repo; configs SHALL only link to them. At start, the harness MUST check that every technology and skill the flow names is present for each runtime that uses it. If one is missing, it SHALL stop before work starts and name it with its install step, and SHALL install only after a person's yes.

Source: interview 2026-11-24 R17.5, R17.6; owner decision 2026-11-26 (review page, item 3): RP3.13
Decided: design.md D37-RUNTIME-3, D49

#### Scenario: All named tools are present
- **WHEN** the harness starts development and every technology and skill the flow names is installed
- **THEN** development starts

#### Scenario: A named skill is missing
- **WHEN** the harness starts development and a skill the flow names is not installed
- **THEN** the harness stops before any work starts and prints the missing skill with its install step

#### Scenario: The person agrees to set it up
- **WHEN** an attended start finds a missing skill and the person says yes to the offer to set it up
- **THEN** the harness runs the printed install step, checks again, and starts only when the check passes

#### Scenario: The person declines, or nobody answers
- **WHEN** an attended start finds a missing skill and the person says no, or an unattended start finds one
- **THEN** the harness installs nothing and does not start

#### Scenario: A flow system is set up for one runtime only
- **WHEN** the flow runs some steps on Claude Code and some on Codex, and its flow system is installed for Claude Code only
- **THEN** the check names the flow system as missing for Codex, with the install step for Codex

#### Scenario: The repo holds only links
- **WHEN** a flow config uses GSD
- **THEN** the repo holds a reference to GSD, not a copy of it

### Requirement: H-074 A project never depends on the harness
A project that uses the harness MUST NOT depend on it. A newcomer who does not use the harness SHALL NOT be hindered by it in any way. A newcomer who wants to use the harness SHALL be able to find out that it is used and install it.

Source: interview 2026-11-24 R17.8

#### Scenario: A newcomer works without the harness
- **WHEN** a newcomer clones the repo and works without the harness
- **THEN** the harness files do not stop or change that newcomer's work

#### Scenario: A newcomer wants the harness
- **WHEN** a newcomer wants to work with the harness
- **THEN** the newcomer can learn from the repo that the harness is used and how to install it

### Requirement: H-075 Per-step runtime, including Codex for steps with the same result
Each flow step SHALL be able to name its agent runtime, and any step SHALL be able to run on Codex, configurable with profiles. No runtime name SHALL be hard-coded in engine code; such names live in data files. Execution on Codex SHALL be marked experimental only until the Codex success path of H-157 passes.

Source: interview 2026-11-24 R24.5, R24.6; owner decision 2026-11-26 (review page, item 3): RP3.4
Decided: design.md D37-RUNTIME-1, D53

#### Scenario: UI review runs on Codex
- **WHEN** the flow configuration sets the UI review step to run on Codex
- **THEN** UI review runs on Codex, so the Codex subscription is also used for development

#### Scenario: Execution on Codex needs careful checking
- **WHEN** the user wants the execution step to run on Codex
- **THEN** it runs there only when the flow config names Codex for that step, and the harness marks it experimental until a comparison run gives the same result (design.md D37-RUNTIME-2)

#### Scenario: Code review runs on Codex
- **WHEN** the flow configuration sets the code review step to run on Codex and the other steps on Claude Code
- **THEN** code review runs on Codex
- **AND** every other step runs on Claude Code

#### Scenario: Execution on Codex is experimental
- **WHEN** the user looks at running the execution step on Codex
- **THEN** the harness offers it as experimental (design.md D30)

### Requirement: H-076 Optional requirements format; OpenSpec is the default after one confirmation
The requirements format SHALL be a setting: OpenSpec, for now the only format, or none. When nothing is configured, the default SHALL be OpenSpec, confirmed once together with the flow (H-001). The setting SHALL resolve project first, then user. Whether grilling uses the requirements SHALL be configurable. A project without OpenSpec SHALL be a valid, normal case.

Source: interview 2026-11-24 R30.2, R30.3; D41; owner decision 2026-11-26
Decided: design.md D37-FLOW-7

#### Scenario: The default is confirmed in a project without OpenSpec
- **WHEN** the person confirms OpenSpec as the requirements format and the project has none
- **THEN** the harness offers to set up OpenSpec
- **AND** sets it up only after the user says yes

#### Scenario: The OpenSpec setup is declined
- **WHEN** the person declines the OpenSpec setup, or answers none
- **THEN** the harness records none as the requirements format for this project on this machine
- **AND** tickets run normally, with nothing about OpenSpec added

#### Scenario: A project without OpenSpec
- **WHEN** a project uses GSD and its requirements format is none
- **THEN** the harness runs tickets normally, with nothing about OpenSpec added

#### Scenario: A folder alone decides nothing
- **WHEN** a project holds an `openspec/` folder and its requirements format is none
- **THEN** the harness does not read that folder as requirements

#### Scenario: The project beats the user
- **WHEN** the user's confirmed default is OpenSpec and the selected project config sets none
- **THEN** the requirements format for that project is none

#### Scenario: Grilling ignores the requirements
- **WHEN** the project uses OpenSpec and the user sets grilling not to take requirements into account
- **THEN** the grilling step runs without reading the OpenSpec requirements

### Requirement: H-077 Selectable agent language, English by default
The user SHALL be able to select the language in which the agent communicates. The default language MUST be English.

Source: interview 2026-11-24 R28.9

#### Scenario: Default language
- **WHEN** the user has not selected a language
- **THEN** the agent communicates in English

#### Scenario: Another language is selected
- **WHEN** the user selects another language
- **THEN** the agent communicates in that language

### Requirement: H-078 The same workflow runs on Codex and Claude Code where local setup allows
The same workflow, for example GSD, SHOULD run on both Codex and Claude Code. If that needs harness changes, the harness SHALL include them. A workflow set up for one runtime only SHALL be offered for setup on the other one, or its steps SHALL go to the runtime that has it (H-159).

Source: interview 2026-11-24 R24.5, R24.6; owner decision 2026-11-26 (review page, item 3): RP3.13
Decided: design.md D55

#### Scenario: One workflow on both runtimes
- **WHEN** a flow based on GSD runs some steps on Codex and some on Claude Code, and GSD is set up locally for both
- **THEN** both runtimes can follow the same GSD workflow

#### Scenario: Workflow not set up for Codex
- **WHEN** a step runs on Codex and the workflow is not installed for Codex on this machine
- **THEN** the harness stops and prints the install step (design.md D31); in the agent's current assessment this is local setup

#### Scenario: A harness change is needed
- **WHEN** running the same workflow on both runtimes needs a change in the harness
- **THEN** that change is made in the harness

### Requirement: H-150 Steps and checks name a model role, not a model
A flow step, a check or a helper call SHALL name a model role, not a model. The roles SHALL be at least: cheap checker, standard, strong and strongest. One data file SHALL map each role to a model for each runtime. The user MAY change the mapping.

Source: owner decision 2026-11-26 (review page, item 3): RP3.9, RP3.18
Decided: design.md D48

#### Scenario: A check asks for the cheap checker
- **WHEN** the check of H-148 runs on Claude Code
- **THEN** the harness takes the model for the cheap checker role on Claude Code from the mapping file

#### Scenario: The user changes a role
- **WHEN** the user maps the strong role on Codex to another model in the user config
- **THEN** every step that names the strong role and runs on Codex uses that model

#### Scenario: A role has no model for a runtime
- **WHEN** a step names a role that the mapping does not give for the step's runtime
- **THEN** the run stops at start and names the role and the runtime
- **AND** it never picks a model by itself

#### Scenario: A project selects a role for a step
- **WHEN** a project config sets the role of its code review step to strongest
- **THEN** code review uses the model mapped to the strongest role for its runtime


