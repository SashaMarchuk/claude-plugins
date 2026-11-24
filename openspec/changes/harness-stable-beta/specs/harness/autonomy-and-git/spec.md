## ADDED Requirements

### Requirement: H-036 Each project selects an autonomy profile during setup
Each project SHALL select its level of autonomy through a profile. During setup, the harness MUST ask the user what level of autonomy they want and store the answer as the project's profile.
Source: interview 2026-11-24 R1.1, R8.1, R8.3

#### Scenario: Setup asks for the autonomy level
- **WHEN** the user sets up the harness for a project
- **THEN** the harness asks what level of autonomy the user wants
- **AND** the answer is stored as the project's autonomy profile

#### Scenario: Two projects use different profiles
- **WHEN** two projects have different autonomy profiles
- **THEN** each project runs under its own profile

### Requirement: H-037 Every step can be autonomous or a human gate
Every step of the flow SHALL be configurable as autonomous or as a human gate. This includes whether a ticket may start without a human. The interview did not discuss whether the engine checks these settings. Per design.md S8-08a (agent decision on an unanswered point, under D37), the engine, not the prompt, MUST check the gate settings before it moves past a gated point.
Source: interview 2026-11-24 R8.2; agent decision S8-08a (unanswered point, under D37)

#### Scenario: A human takes over after execution
- **WHEN** the profile sets a human gate right after execution
- **THEN** the harness stops after execution
- **AND** a human can check the work by hand, with no code review or other steps in between

#### Scenario: A ticket may not start on its own
- **WHEN** the profile sets ticket start as a human gate
- **THEN** a labelled ticket does not start until a human approves it

#### Scenario: The engine blocks a gated action
- **WHEN** a session tries to pass a step that the profile marks as a human gate
- **THEN** the engine refuses to go on until a human approves

### Requirement: H-038 Ready-made profiles plus a custom profile
The harness SHALL ship several ready-made autonomy profiles, about four, ranging from a very safe mode to full autonomy. Users MUST be able to create their own custom profile. The set of ready-made profiles and their contents is set in design.md D12.
Source: interview 2026-11-24 R8.4, R8.5, R8.6; delegated decision D12

#### Scenario: The user picks a ready-made profile
- **WHEN** the user chooses a ready-made profile during setup
- **THEN** the project uses that profile's gates and permissions

#### Scenario: The user builds a custom profile
- **WHEN** no ready-made profile fits the user's needs
- **THEN** the user can define a custom profile with their own gates and permissions

#### Scenario: Full autonomy takes a ticket to a release
- **WHEN** the project uses the full-autonomy profile
- **AND** a correctly labelled ticket appears and is self-sufficient
- **THEN** the harness picks it up, implements it and carries it as far as a release to the project's pre-production target, if one is configured

#### Scenario: A profile that ends at a draft PR
- **WHEN** the project uses the profile that ends at a draft PR
- **THEN** the harness opens a draft PR and stops
- **AND** it does not merge and does not release

#### Scenario: A profile that stops after verification
- **WHEN** the project uses the profile that runs plan, execution, code review and verification on its own
- **THEN** the harness stops after verification so that a human does the rest

### Requirement: H-039 Profiles assume no stage environment
Autonomy profiles MUST NOT assume that a stage environment exists. Profile settings SHALL be abstract and not depend on a stage.
Source: interview 2026-11-24 R8.7

#### Scenario: A project without stage
- **WHEN** a project has no stage environment
- **THEN** every ready-made profile still works for that project

#### Scenario: Profile content is checked for stage
- **WHEN** a ready-made profile is read
- **THEN** none of its settings requires a stage environment to exist

### Requirement: H-040 The safe profile is the default and sends nothing to the remote
A new project SHALL start with the safe profile as its default. The safe profile MUST check that the ticket is self-sufficient and MUST send nothing to the remote: no push and no PR. It merges into no branch, not even locally; the interview left this open (agent decision on the owner's delegation). Full contents: design.md D12. Reaction to a ticket that is not self-sufficient: design.md D7.
Source: interview 2026-11-24 R8.8, R26.1; delegated decisions D12, D7

#### Scenario: New project with no choice made
- **WHEN** a new project is set up and the user does not choose a profile
- **THEN** the project uses the safe profile

#### Scenario: Safe profile finishes a ticket
- **WHEN** a ticket finishes under the safe profile
- **THEN** no branch is pushed and no PR is opened

#### Scenario: Safe profile makes no local merge
- **WHEN** a ticket finishes under the safe profile
- **THEN** the harness merges its work into no branch, not even a local one

#### Scenario: Safe profile checks self-sufficiency first
- **WHEN** a ticket starts under the safe profile
- **THEN** the harness checks that the ticket is self-sufficient before it starts implementation
- **AND** if the ticket is not self-sufficient, the harness handles it as set in design.md D7

### Requirement: H-041 Safe defaults can be overridden up to full autonomy, which must work
Safe defaults SHALL be defaults only, not locks. The user MUST be able to override them, including up to full autonomy. Nothing in the harness may block or disable that override, and full autonomy MUST work.
Source: interview 2026-11-24 R8.9, R26.2

#### Scenario: The user turns on full autonomy
- **WHEN** the user switches a project to full autonomy in the settings
- **THEN** the harness accepts the setting
- **AND** runs tickets with full autonomy

#### Scenario: No hidden lock
- **WHEN** a project runs under full autonomy
- **THEN** no built-in safe default stops a step that the profile allows

### Requirement: H-042 A ticket runs as far as the project's settings allow
The harness SHALL carry a ticket as far as the project's settings allow, up to a merged PR or a release. Each ticket, including one run on its own, MUST stop at the last step the settings allow. How a whole run ends is out of scope here. If the settings include a release and a smoke test, the ticket is complete only when the release is done and the smoke test passes.
Source: interview 2026-11-24 R1.1, R2.6

#### Scenario: Settings allow a merge
- **WHEN** a detailed ticket is added and the project's settings allow merging
- **THEN** the harness can take the ticket through development up to a merged PR

#### Scenario: Settings stop at an earlier step
- **WHEN** the project's settings stop before the merge
- **THEN** work on that ticket stops at that step

#### Scenario: Release and smoke test are allowed
- **WHEN** the settings allow a release and a smoke test
- **THEN** the ticket is complete only after the release is done and the smoke test passes

### Requirement: H-043 Push and draft PR only when settings allow, configured at first-run setup
The harness SHALL push the work branch and open a draft PR only when the settings allow it. First-run setup MUST configure this, as part of the autonomy profile or in addition to it. The settings MUST be able to allow or forbid everything, including keeping all changes local until a human pushes them. Branch names, the PR's Verification block and the PR-to-ticket link: design.md S8-07.
Source: interview 2026-11-24 R7.1, R7.2, R7.3; delegated decision S8-07

#### Scenario: First run with no configuration
- **WHEN** the harness runs for the first time in a project and finds no configuration file
- **THEN** first-run setup configures whether the harness may push and open PRs
- **AND** stores that setting

#### Scenario: Remote writes are forbidden
- **WHEN** the settings forbid remote writes
- **THEN** no change goes to the remote until a human pushes it

#### Scenario: Remote writes are allowed
- **WHEN** the settings allow push and PR
- **THEN** the harness pushes the work branch and opens a draft PR

### Requirement: H-044 The draft PR opening point is configurable
The point at which the harness opens the draft PR SHALL be configurable. The default is set in design.md D10; it starts from the owner's lean to open the PR after independent verification.
Source: interview 2026-11-24 R7.4; delegated decision D10

#### Scenario: Default opening point
- **WHEN** the settings allow a PR and no opening point is set
- **THEN** the harness opens the draft PR at the default point in design.md D10

#### Scenario: A custom opening point
- **WHEN** a profile sets another opening point
- **THEN** the harness opens the draft PR at that point

### Requirement: H-045 A confirmed merge closes the linked ticket after its post-merge steps
When git confirms a merge and every post-merge step the project configures (release, smoke test) has passed, the harness SHALL set the linked ticket to done and, by default, close it (agent decision on the owner's delegation, design.md D11, setting `close_on_merge`). A confirmed merge alone MUST NOT mark the ticket done while configured post-merge steps are pending or failed (H-042).
Source: interview 2026-11-24 R7.5, R1.1, R2.6; delegated decision D11

#### Scenario: Merge confirmed, no post-merge steps
- **WHEN** git confirms that the ticket's change is in the target branch and the project has no post-merge steps
- **THEN** the harness sets the linked ticket to done and closes it, as set in design.md D11

#### Scenario: Post-merge steps configured
- **WHEN** git confirms the merge and the project configures a release and a smoke test
- **THEN** the ticket stays in progress until the release is done and the smoke test passes, and only then is set to done

#### Scenario: Smoke test fails after merge
- **WHEN** the smoke test fails after a confirmed merge
- **THEN** the ticket is not set to done and is handled by the project's failure setting

#### Scenario: Closing is switched off
- **WHEN** the ticket would be set to done and `close_on_merge` is false
- **THEN** the harness sets the linked ticket to done and leaves it open

### Requirement: H-046 Every merge is confirmed through git
After each merge, the harness MUST confirm through git that the change really entered the target branch. A merge that git does not confirm MUST NOT count as done.
Source: interview 2026-11-24 R13.2

#### Scenario: Merge confirmed
- **WHEN** a merge finishes and git shows the change in the target branch
- **THEN** the harness records the merge as done

#### Scenario: Merge reports success but changed nothing
- **WHEN** a merge reports success but git does not show the change in the target branch
- **THEN** the harness does not mark the ticket done

### Requirement: H-047 Configurable merge gate: always, never, or a classifier that waits on any doubt
The merge gate SHALL be configurable per project: always merge, never merge, or an AI classifier step. After the shipping checks pass, the classifier MUST decide whether the PR may merge into the main branch without a human or must ask one; on any doubt it MUST wait for a human.
Source: interview 2026-11-24 R13.7, R13.8, R13.9; agent decision S8-08b (unanswered point, under D37); delegated decision D12

#### Scenario: Conditions are an agent proposal
- **WHEN** the classifier decides whether a PR may merge
- **THEN** it uses the conditions proposed in design.md S8-08b, because the owner did not yet know them

#### Scenario: Classifier only in a custom profile
- **WHEN** a project uses a ready-made profile
- **THEN** the merge gate is not the classifier; the classifier is available only in a custom profile (design.md D12)

#### Scenario: Gate set to never
- **WHEN** the merge gate is set to never merge
- **THEN** the harness does not merge the PR

#### Scenario: Gate set to always
- **WHEN** the merge gate is set to always merge and the shipping checks pass
- **THEN** the harness merges the PR

#### Scenario: Classifier is sure
- **WHEN** the merge gate is the classifier and the classifier finds the PR safe to merge without review
- **THEN** the harness merges the PR

#### Scenario: Classifier has doubt
- **WHEN** the merge gate is the classifier and the classifier has any doubt
- **THEN** the harness waits for a human before merging

### Requirement: H-048 No ready-made profile deploys to production
No ready-made profile SHALL allow the agent to deploy to production. The harness MUST NOT recommend self-deploy to production.
Source: interview 2026-11-24 R9.1, R9.2

#### Scenario: Ready-made profile reaches the end of its flow
- **WHEN** a ticket finishes under any ready-made profile, including full autonomy
- **THEN** the harness does not deploy to production

### Requirement: H-049 Production deploy only in a user's own profile, with optional custom post-deploy checks
A user SHALL be able to allow production deploy in their own profile or project workflow, at their own risk, when the project's deployment is configured. Such a workflow MAY add custom checks after the deploy, such as smoke tests and a service-up check.
Source: interview 2026-11-24 R9.2, R9.3

#### Scenario: The user allows production deploy
- **WHEN** a user's own profile allows production deploy and the project's deployment is configured
- **THEN** the agent may deploy to production

#### Scenario: Custom post-deploy checks
- **WHEN** a production-deploy workflow defines smoke tests or a service-up check
- **THEN** the harness runs those checks after the deploy

#### Scenario: Deployment is not configured
- **WHEN** a profile allows production deploy but the project has no deployment configured
- **THEN** the harness does not deploy to production

### Requirement: H-050 Release to stage is supported and configurable, with automatic smoke testing
Release to stage SHALL be supported and configurable per project, for projects that have a stage. Where the project's settings allow it, a PR MAY merge into the branch that deploys to stage, so the change can be checked at once. When a change reaches stage and the project defines smoke tests, the smoke tests MUST start automatically, with no human needed.
Source: interview 2026-11-24 R9.4, R9.7

#### Scenario: Settings allow a stage release
- **WHEN** the project's settings allow a release to stage and the merge gate passes
- **THEN** the harness merges into the branch that deploys to stage

#### Scenario: Change reaches stage
- **WHEN** a change reaches stage and the project defines smoke tests
- **THEN** the smoke tests start automatically without a human

#### Scenario: Stage release not allowed
- **WHEN** the project's settings do not allow a release to stage
- **THEN** the harness does not release to stage

### Requirement: H-051 Configurable reaction to a failed smoke test: revert or fix
The reaction to a failed smoke test after a release SHALL be a setting. The options MUST include reverting all changes and making a fix.
Source: interview 2026-11-24 R2.7, R9.5

#### Scenario: Reaction set to revert
- **WHEN** a smoke test fails after a release and the reaction is set to revert
- **THEN** the harness reverts all changes

#### Scenario: Reaction set to fix
- **WHEN** a smoke test fails after a release and the reaction is set to fix
- **THEN** the harness makes a fix for the failure

### Requirement: H-052 Permission prompts are not answered by default; answering is a setting
By default, the harness SHALL NOT answer permission prompts in its sessions. A setting MUST be able to allow answers. For example, a model MAY analyse the prompt, accept it if it judges it acceptable, and otherwise escalate it to a human.
Source: interview 2026-11-24 R26.3
OPEN: see design.md OPEN-8

#### Scenario: Default behaviour
- **WHEN** a session shows a permission prompt and the setting is off
- **THEN** the harness does not answer the prompt

#### Scenario: Example mode, the prompt is acceptable
- **WHEN** the setting is on in the analyse-or-escalate mode and the model judges the prompt acceptable
- **THEN** the harness accepts the prompt

#### Scenario: Example mode, the prompt is doubtful
- **WHEN** the setting is on in the analyse-or-escalate mode and the model does not judge the prompt acceptable
- **THEN** the harness escalates the prompt to a human
