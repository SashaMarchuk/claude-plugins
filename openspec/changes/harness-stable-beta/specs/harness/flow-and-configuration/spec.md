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
The harness SHALL have a flow configuration that describes, step by step from start to end, what happens when a ticket enters work, including how it is tested. The orchestrator MUST follow it. It SHALL be a setting of its own, separate from the profile, possibly per person (design.md S8-16b). Where the step list lives: design.md S8-15.

Source: interview 2026-11-24 R15.2, R15.15; S8-15
OPEN: see design.md OPEN-18

#### Scenario: The orchestrator follows the configured steps
- **WHEN** a ticket enters work
- **THEN** the orchestrator moves it through the steps that the flow configuration describes, in their configured order

#### Scenario: The flow is changed without changing the profile
- **WHEN** the user changes the flow configuration
- **THEN** the profile stays unchanged

### Requirement: H-066 Steps can be reordered, added, switched off and given a runner
For each project, the flow configuration SHALL let the user reorder, add and switch off steps, and name each step's runner. A step MAY be switched off when something else does it, for example code review on GitHub or by a review bot. Custom steps MAY be added anywhere in the flow; the scenarios give examples. Code review before the PR is opened SHALL be an allowed order.

Source: interview 2026-11-24 R15.3, R15.4, R15.5, R15.9

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
OPEN: see design.md OPEN-16

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

### Requirement: H-068 Any flow system is supported; a ready-made or own flow is chosen explicitly
The harness MUST support any flow system; named ones (GSD, superpowers) are examples only. Nothing SHALL restrict the choice, and no flow system's name SHALL be hard-coded in the plugin. The user SHALL explicitly pick a ready-made flow or set up their own. Generic ready-made flow and its name: design.md S8-16a.

Source: interview 2026-11-24 R16.1, R16.2; S8-16a; context (rejected: binding to one flow or hard-coding a vendor name)
OPEN: see design.md OPEN-16

#### Scenario: The user picks a ready-made flow
- **WHEN** the user picks a ready-made flow during setup
- **THEN** the harness runs tickets by that flow

#### Scenario: The user sets up an own flow
- **WHEN** the user chooses to set up an own flow
- **THEN** the harness lets the user define the steps of that flow
- **AND** runs tickets by it

#### Scenario: A system the harness has not seen before
- **WHEN** the user points the flow configuration to a flow system that is not among the named examples
- **THEN** the harness does not refuse it because of its name

### Requirement: H-069 Setup recommends the flow the person already uses
At setup, the configuration flow SHALL check the person's memory and existing setup. If it finds an existing flow (the owner's words allow two readings: any flow the person already uses, or only one that is also tested), it SHALL recommend that flow. If it finds none, it SHALL propose that the person creates their own flow. The recommendation MUST NOT replace the person's explicit choice.

Source: interview 2026-11-24 R16.6
OPEN: see design.md OPEN-17

#### Scenario: An existing flow is found
- **WHEN** setup finds that the person already uses GSD
- **THEN** setup recommends GSD
- **AND** the person still confirms or changes the choice

#### Scenario: No existing flow is found
- **WHEN** setup finds no flow in the person's memory or setup
- **THEN** setup proposes creating the person's own flow

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
A local file on each machine SHALL select which committed config the harness uses. Two machines that clone the same repo MUST be able to do a short harness setup and then reuse the same committed workflow. Whether the flow is chosen per project or per person is set in design.md S8-16b.

Source: interview 2026-11-24 R17.4; S8-16b
OPEN: see design.md OPEN-7 (where the local file lives, whether it is git-ignored, and what remote config means)

#### Scenario: A second machine reuses the committed workflow
- **WHEN** a second machine clones a repo with a committed workflow and runs the short harness setup
- **THEN** a local file on that machine selects the committed workflow
- **AND** the harness on that machine runs by it

#### Scenario: Two people select different configs
- **WHEN** two people select different committed configs in their local files
- **THEN** each person's harness runs by the config that person selected

### Requirement: H-072 A missing local selection stops the harness and offers setup
When no local file selects a config, the harness SHALL NOT continue with development (hard stop; the owner's likely, not firm, answer). If the repo holds a config, the harness SHALL ask whether to use it and, on yes, create a local file that points to it; otherwise a new workflow SHALL be created.

Source: interview 2026-11-24 R17.9
OPEN: see design.md OPEN-3 (the whole of R17.9 still needs the owner's ratification)

#### Scenario: A committed config is found and accepted
- **WHEN** the harness starts with no local selection and the repo holds a config
- **THEN** the harness stops and asks whether to use that config
- **AND** on yes, it creates a local file that points to the config

#### Scenario: The committed config is declined
- **WHEN** the person declines the committed config
- **THEN** the harness guides the person through creating a new workflow

#### Scenario: No config exists anywhere
- **WHEN** the harness starts with no local selection and the repo holds no config
- **THEN** harness setup may block harness work until the first config files exist, if the hard stop in design.md OPEN-3 is ratified

#### Scenario: A developer without the harness is not blocked
- **WHEN** a developer who does not use the harness works in the same repo
- **THEN** nothing in the harness blocks that developer's work

### Requirement: H-073 Flow systems are linked, never vendored, and checked present at start
Flow systems themselves, such as GSD or superpowers, SHALL NOT be stored in the project repo. Configs SHALL only link to them. When the harness starts development, it MUST check that every technology and skill the flow names is present, because a linked system may be absent from a given machine. What happens when one is missing is not decided yet.

Source: interview 2026-11-24 R17.5, R17.6
OPEN: see design.md OPEN-20

#### Scenario: All named tools are present
- **WHEN** the harness starts development and every technology and skill the flow names is installed
- **THEN** development starts

#### Scenario: A named skill is missing
- **WHEN** the harness starts development and a skill the flow names is not installed
- **THEN** the harness detects that the named skill is absent

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
Each flow step SHALL be able to name its agent runtime. Steps with the same result SHALL be able to run on Codex, configurable with profiles (part of the beta). No runtime name SHALL be hard-coded in the plugin. Details: design.md D30, D31.

Source: interview 2026-11-24 R24.5, R24.6; D30, D31; context (rejected: hard-coding a vendor name)
OPEN: see design.md OPEN-19 (Codex execution depth and Codex profile details) and OPEN-16 (hard-coded names)

#### Scenario: UI review runs on Codex
- **WHEN** the flow configuration sets the UI review step to run on Codex
- **THEN** UI review runs on Codex, so the Codex subscription is also used for development

#### Scenario: Execution on Codex needs careful checking
- **WHEN** the user wants the execution step to run on Codex
- **THEN** it runs there only after careful checking

#### Scenario: Code review runs on Codex
- **WHEN** the flow configuration sets the code review step to run on Codex and the other steps on Claude Code
- **THEN** code review runs on Codex
- **AND** every other step runs on Claude Code

#### Scenario: Execution on Codex is experimental
- **WHEN** the user looks at running the execution step on Codex
- **THEN** the harness offers it as experimental (design.md D30)

### Requirement: H-076 Optional requirements format, with an offer to set up OpenSpec
The harness SHALL be able to offer OpenSpec setup as a project's requirements format; for now it SHALL be the only such format, and others may come later. Using one MUST be optional and configurable, including whether grilling uses the requirements. A project without OpenSpec SHALL be a valid, normal case. Defaults: design.md D41 (agent decision under D37, not yet ratified).

Source: interview 2026-11-24 R30.2, R30.3; D41
OPEN: see design.md OPEN-1

#### Scenario: OpenSpec is offered and accepted
- **WHEN** the user picks OpenSpec as the requirements format and the project has none
- **THEN** the harness offers to set up OpenSpec
- **AND** sets it up only after the user says yes

#### Scenario: A project without OpenSpec
- **WHEN** a project uses GSD and has no OpenSpec
- **THEN** the harness runs tickets normally, with nothing about OpenSpec added

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
The same workflow, for example GSD, SHOULD run on both Codex and Claude Code (the owner called this the ideal). The harness SHALL support it where local setup allows. Installing a workflow for Codex is local setup, not a harness change (design.md D31).

Source: interview 2026-11-24 R24.5, R24.6; D31 (split from H-075)

#### Scenario: One workflow on both runtimes
- **WHEN** a flow based on GSD runs some steps on Codex and some on Claude Code, and GSD is set up locally for both
- **THEN** both runtimes can follow the same GSD workflow

#### Scenario: Workflow not set up for Codex
- **WHEN** a step runs on Codex and the workflow is not installed for Codex on this machine
- **THEN** installing it is a local setup task, and the harness itself does not change
