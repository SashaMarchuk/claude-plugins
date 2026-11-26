## MODIFIED Requirements

### Requirement: H-075 Per-step runtime, including Codex for steps with the same result
Each flow step SHALL be able to name its agent runtime, and any step SHALL be able to run on Codex, configurable with profiles. No runtime name SHALL be hard-coded in engine code; such names live in data files. Execution on Codex SHALL be marked experimental only until the Codex success path of H-157 passes.

Source: interview 2026-11-24 R24.5, R24.6; owner decision 2026-11-26 (review page, item 3): RP3.4
Decided: design.md D37-RUNTIME-1, D53

#### Scenario: UI review runs on Codex
- **WHEN** the flow configuration sets the UI review step to run on Codex
- **THEN** UI review runs on Codex, so the Codex subscription is also used for development

#### Scenario: Code review runs on Codex
- **WHEN** the flow configuration sets the code review step to run on Codex and the other steps on Claude Code
- **THEN** code review runs on Codex
- **AND** every other step runs on Claude Code

#### Scenario: Execution runs on Codex
- **WHEN** the flow configuration sets the execution step to run on Codex and the Codex success path of H-157 has passed
- **THEN** execution runs on Codex in an interactive session, and the harness does not mark it experimental

#### Scenario: Execution on Codex before the success path passed
- **WHEN** the flow configuration sets the execution step to run on Codex and the Codex success path of H-157 has not passed yet for this release
- **THEN** the start output marks the step as experimental

### Requirement: H-078 The same workflow runs on Codex and Claude Code where local setup allows
The same workflow, for example GSD, SHOULD run on both Codex and Claude Code. If that needs harness changes, the harness SHALL include them. A workflow set up for one runtime only SHALL be offered for setup on the other one, or its steps SHALL go to the runtime that has it (H-159).

Source: interview 2026-11-24 R24.5, R24.6; owner decision 2026-11-26 (review page, item 3): RP3.13
Decided: design.md D55

#### Scenario: One workflow on both runtimes
- **WHEN** a flow based on GSD runs some steps on Codex and some on Claude Code, and GSD is set up locally for both
- **THEN** both runtimes can follow the same GSD workflow

#### Scenario: Workflow not set up for Codex
- **WHEN** a step runs on Codex and the workflow is not installed for Codex on this machine
- **THEN** H-159 applies

#### Scenario: A harness change is needed
- **WHEN** running the same workflow on both runtimes needs a change in the harness
- **THEN** that change is made in the harness

## ADDED Requirements

### Requirement: H-159 A step whose skill is missing on one runtime is set up there or moved to a runtime that has it
When a skill, plugin or flow system that a step needs is missing on the step's runtime but present on another runtime, the harness SHALL offer two choices before the run: set it up after a yes (H-073), or run those steps on the runtime that has it. This SHALL hold in both directions. A step fixed to one runtime SHALL never move.

Source: owner decision 2026-11-26 (review page, item 3): RP3.13, RP3.14, RP3.15
Decided: design.md D55

#### Scenario: The person moves the steps
- **WHEN** a review skill is installed for Claude Code only, the flow names Codex for review, and the person chooses to move the steps
- **THEN** the review steps run on Claude Code for this run, and the change is recorded

#### Scenario: A fixed step
- **WHEN** the flow fixes code review to Codex and the review skill is missing for Codex
- **THEN** the harness offers only the setup for Codex, and without it the run does not start

#### Scenario: Codex has a skill that Claude Code lacks
- **WHEN** a skill a step needs is installed for Codex only and the step names Claude Code
- **THEN** the harness offers to set it up for Claude Code or to run the step on Codex

### Requirement: H-160 The orchestrator may shift load between runtimes inside limits the person set
At setup, the person SHALL be able to set a preferred split of steps between runtimes, steps fixed to one runtime, and whether the orchestrator may change the split during a run. With that permission, it MAY move movable steps by skill availability and by limits left, and SHALL record and report each move. Without it, an attended run SHALL ask, and an unattended run SHALL keep the split.

Source: owner decision 2026-11-26 (review page, item 3): RP3.15, RP3.16
Decided: design.md D56

#### Scenario: Limits run low on one runtime
- **WHEN** the person allowed changes to the split and the Claude Code account reaches its threshold while Codex has limits left
- **THEN** the orchestrator moves the next movable steps to Codex, records the change and tells the person

#### Scenario: A fixed step stays
- **WHEN** execution is fixed to Claude Code and the Claude Code account reaches its threshold
- **THEN** execution waits for the reset (H-114) and does not move to Codex

#### Scenario: No permission to change the split
- **WHEN** the person did not allow changes to the split and the orchestrator sees a reason to move work
- **THEN** an attended run asks the person, and an unattended run keeps the split and records the reason

#### Scenario: Steps fixed for a flow system
- **WHEN** the person fixes the GSD planning step to Claude Code and the superpowers review step to Codex
- **THEN** those steps never move, and other steps may move within the permission

### Requirement: H-161 The model role mapping stays current from a maintained public source
The harness SHALL keep the role mapping of H-150 current. It SHALL check the mapping against a maintained public model list and against the runtimes' own model lists, at setup and at most once a day. A gone or deprecated model, or a newer model of the same family, SHALL be shown as a proposed change, applied only after a yes. An unreadable list SHALL NOT fail a run.

Source: owner decision 2026-11-26 (review page, item 3): RP3.17
Decided: design.md D57

#### Scenario: A mapped model is deprecated
- **WHEN** the check finds that the model mapped to the strong role on Codex is marked deprecated
- **THEN** the harness proposes a replacement and keeps the old mapping until the person says yes

#### Scenario: The public list is unreachable
- **WHEN** the public model list cannot be read at run start
- **THEN** the run uses the current mapping and writes one log line

### Requirement: H-163 A non-default model inside a runtime is a routing target
A runtime MAY run a model that is not its vendor's default, for example Claude Code with another vendor's model. The person SHALL be able to make such a model a target of a role (H-150) and of load routing (H-160). Each session record SHALL name the runtime, the provider, the model requested and the model that ran.

Source: owner decision 2026-11-26 (review page, item 3): RP3.21
Decided: design.md D58

#### Scenario: A cheap checker on another vendor's model
- **WHEN** the person maps the cheap checker role on Claude Code to another vendor's model through a compatible endpoint
- **THEN** the checks of H-148 run on that model, and each session record names the provider and the model

#### Scenario: Known gaps are shown
- **WHEN** the person adds such a model at setup
- **THEN** the setup shows that the runtime vendor does not support this setup, and the known feature gaps
