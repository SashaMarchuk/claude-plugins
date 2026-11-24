## ADDED Requirements

### Requirement: H-002 Label-only pickup trigger
On a tracker with labels, only a label on the ticket SHALL put the ticket into work. The harness MUST NOT offer a comment command that triggers pickup. The label names are chosen by the agent.

Source: interview 2026-11-24 R1.2; context: label names chosen by the agent

#### Scenario: A person sets the ready label
- **WHEN** a person with write access sets the ready label on a GitHub issue
- **THEN** the issue becomes a candidate for pickup

#### Scenario: A person writes a command in a comment
- **WHEN** a person writes a comment that looks like a run command on an issue without the ready label
- **THEN** the harness does not pick up the issue

### Requirement: H-003 Pickup on the next poll during a live run
While a run is live, the orchestrator SHALL watch the configured tracker and SHALL take tickets into work according to the project settings. A ticket that gets the ready trigger during a live run SHALL be noticed on the next poll.

Source: interview 2026-11-24 R1.3, R1.4

#### Scenario: A ticket is labelled during a live run
- **WHEN** a run is live and a person sets the ready label on a new ticket
- **THEN** the harness notices the ticket on its next poll
- **AND** the orchestrator takes it into work when the settings and the worker cap allow

### Requirement: H-004 Configurable polling interval
The polling interval SHALL be configurable, and it MUST be easy to change in the settings. The default value is an agent decision on the owner's delegation; see design.md D4.

Source: interview 2026-11-24 R3.7; D4

#### Scenario: The user changes the interval
- **WHEN** the user sets a new polling interval in the settings
- **THEN** the next run polls the tracker at the new interval

#### Scenario: No interval is set
- **WHEN** the user sets no polling interval
- **THEN** the harness uses the default from design.md D4

### Requirement: H-005 One intake flow for the terminal and the tracker
Adding a ticket from the terminal (`/harness:add`) and adding it in the project's configured tracker (for example GitHub Issues, ClickUp or Jira) SHALL be one single flow for the project. A ticket added from the terminal MUST land in the configured tracker and follow the same pickup path as a ticket added there by hand.

Source: interview 2026-11-24 R1.5

#### Scenario: A ticket is added from the terminal
- **WHEN** a person adds a ticket with `/harness:add` in a project that uses ClickUp
- **THEN** the ticket is created in ClickUp
- **AND** it is picked up by the same path as a ticket created in ClickUp directly

### Requirement: H-006 Grilling and tracker status when a ticket is added from the terminal
When a ticket is added from the terminal, the harness SHALL keep the existing grilling gate in `/harness:add`, so the person can be asked clarifying questions at once. After the ticket is added, the harness SHALL set the matching status in the tracker.

Source: interview 2026-11-24 R1.6; decided context CTX-grilling-gate

#### Scenario: A vague ticket is added from the terminal
- **WHEN** a person runs `/harness:add` with a short, unclear request
- **THEN** the harness asks clarifying questions before it creates the ticket

#### Scenario: A ticket is created from the terminal
- **WHEN** `/harness:add` creates a ticket
- **THEN** the ticket carries the matching status in the configured tracker

### Requirement: H-007 Fallback trigger for trackers without labels
Labels SHALL be the base trigger. A tracker without labels SHALL get a fallback trigger: a reserved word with a specific instruction in the ticket text, or a better one found by research, instead of it or alongside it. Fallback order: delegated agent decision, design.md D1 (a reserved line stays the last resort). The harness MUST find out who set any trigger.

Source: interview 2026-11-24 R1.7, R1.8 (fallback); R4.3, R4.4 and D1 (the trigger's author must be known)

#### Scenario: A tracker has no labels
- **WHEN** the configured tracker has no labels and a ticket carries the reserved word
- **AND** the person who set it has write access or higher
- **THEN** the harness treats the ticket as marked ready

#### Scenario: The author of the trigger is unknown
- **WHEN** the tracker cannot say who set the fallback trigger
- **THEN** the person counts as read-only
- **AND** the ticket is not taken into work
- **AND** the harness moves the ticket to the needs-review state

### Requirement: H-008 Write access or higher required for the ready trigger
Before taking a ticket, the harness SHALL check the access level of whoever set the ready label or status, and take it only if that person has write access or higher to the repository and the ticket is ready. A bot or automation SHALL be able to queue a ticket only through write access: its own, or that of the person it acts for.

Source: interview 2026-11-24 R4.1, R4.2, R4.6 (confirmed restatement covers both cases)
OPEN: see design.md OPEN-INTAKE-1

#### Scenario: A writer sets the label
- **WHEN** a person with write access sets the ready label
- **THEN** the harness may take the ticket into work

#### Scenario: A person with triage access sets the label
- **WHEN** a person with only triage or read access sets the ready label
- **THEN** the harness does not take the ticket into work

#### Scenario: A bot sets the label for a writer
- **WHEN** an automation sets the ready label on behalf of a person with write access
- **THEN** the harness judges the trigger by that person's access
- **AND** it may take the ticket into work

#### Scenario: A bot account with its own write access sets the label
- **WHEN** a bot account that itself has write access to the repository sets the ready label
- **THEN** the harness judges the trigger by the bot account's own access
- **AND** it may take the ticket into work

### Requirement: H-009 Unknown or unmatchable access counts as read-only
If the harness cannot determine the access level of the person who set the trigger, it SHALL treat that person as read-only. This MUST also apply when a person from an external tracker cannot be matched to a code host account.

Source: interview 2026-11-24 R4.3, R4.5

#### Scenario: The access check fails
- **WHEN** the code host does not answer the access query for the person who set the label
- **THEN** the harness treats the person as read-only

#### Scenario: No match is found
- **WHEN** a ClickUp user sets the ready status and no code host account matches that user
- **THEN** the harness treats the person as read-only

### Requirement: H-010 External tracker people matched to the code host by email
For an external tracker such as ClickUp, the harness SHALL match the person who set the trigger to a code host account by email, and SHALL use that account's access level.

Source: interview 2026-11-24 R4.5
OPEN: see design.md OPEN-11

#### Scenario: A ClickUp user with a matching email
- **WHEN** a ClickUp user sets the ready status and the user's email matches a code host account with write access
- **THEN** the harness treats the trigger as set by a writer

### Requirement: H-011 Tickets without confirmed write access move to needs-review
When the person who set the trigger has no write access, or the access cannot be verified, the harness itself SHALL move the ticket to a needs-review state. People with write access MUST be able to filter the tracker by that state to find the tickets that need their approval.

Source: interview 2026-11-24 R4.4

#### Scenario: A non-writer marks a ticket ready
- **WHEN** a person without write access sets the ready label
- **THEN** the harness moves the ticket to the needs-review state
- **AND** the ticket is not taken into work

#### Scenario: A writer approves the ticket
- **WHEN** a person with write access reviews a ticket in needs-review and sets the ready label
- **THEN** the harness may take the ticket into work

### Requirement: H-012 Readiness check at every pickup
At every pickup, also after a hand-set label, the harness SHALL first check whether the ticket is described well enough to start work. A detailed free-form ticket SHALL be able to go to work when the AI has no clarifying question for a human (the owner's suggestion, validated as design.md D8).

Source: interview 2026-11-24 R5.1 (readiness check); R5.3, R5.4 (owner's suggestion, validated as agent decision D8); D6 (what makes a ticket ready)

#### Scenario: No fixed structure required
- **WHEN** a detailed ticket does not follow a fixed structure
- **THEN** the missing structure does not block pickup (agent decision on the owner's delegation, design.md D8)

#### Scenario: A clear free-form ticket
- **WHEN** a ready ticket has no headings but its text says clearly what to change and how to tell it is done (the default criteria of design.md D6)
- **THEN** the readiness check passes
- **AND** the ticket goes to work

#### Scenario: A hand-set label on a thin ticket
- **WHEN** a writer sets the ready label by hand on a ticket with only a vague title
- **THEN** the readiness check runs at pickup
- **AND** the ticket does not go to work until the open questions are answered

### Requirement: H-013 Configurable required ticket content
What a ticket must contain to count as ready SHALL be configurable. The default content is an agent decision on the owner's delegation; see design.md D6.

Source: interview 2026-11-24 R5.2; D6

#### Scenario: A project sets its own required content
- **WHEN** a project config lists its own required ticket content
- **THEN** the readiness check uses that list

#### Scenario: No required content is set
- **WHEN** no required content is set
- **THEN** the readiness check uses the default from design.md D6

### Requirement: H-014 Working brief written by the AI at pickup
At pickup, the AI SHALL add the structure to the ticket itself: it SHALL write a corrected, structured version of the ticket and infer missing points from the text where it can, for example which checks to run. This is the owner's suggestion, adopted after validation (design.md D8); where D8 departs from it, see the scenarios.

Source: interview 2026-11-24 R5.3, R5.5 (owner's suggestion, validated as agent decision D8)
OPEN: see design.md OPEN-INTAKE-4

#### Scenario: Structured version posted as a comment
- **WHEN** the AI writes the structured version
- **THEN** per design.md D8 it keeps the description and posts the structured version as a comment; the owner suggested correcting the description itself, so this needs his ratification

#### Scenario: A ticket names no checks
- **WHEN** a ready ticket describes the change but names no checks
- **THEN** the AI writes a structured version with the checks it infers from the text

### Requirement: H-015 Tickets created through the plugin carry the structure at once
A ticket created through the plugin SHALL get the right description and structure when it is created.

Source: interview 2026-11-24 R5.6

#### Scenario: A ticket is added with /harness:add
- **WHEN** `/harness:add` creates a ticket
- **THEN** the ticket body already has the structure the plugin writes

### Requirement: H-016 Configurable reaction to a ticket marked ready but not ready
If a ticket is marked ready but is not ready, the harness SHALL NOT start work on it, and SHALL change its status so that it no longer counts as ready. The reaction SHALL be configurable and MAY depend on the autonomy level. The handling MUST stay simple. The default reaction is an agent decision on the owner's delegation; see design.md D7, which also posts a comment with numbered questions.

Source: interview 2026-11-24 R5.7; D7
OPEN: see design.md OPEN-INTAKE-5

#### Scenario: A ready ticket fails the readiness check
- **WHEN** a ticket with the ready label fails the readiness check
- **THEN** the harness does not start work on it
- **AND** the ticket leaves the ready state with the default reaction from design.md D7

#### Scenario: A project chooses another reaction
- **WHEN** the project config sets a different reaction for tickets that are not ready
- **THEN** the harness uses that reaction

### Requirement: H-017 Unique local ticket numbers under concurrent adds
The local ticket backend SHALL give every new ticket a number that no other ticket has. This MUST hold when two or more tickets are added at the same time. The fix that already exists as a hand patch SHALL move into the plugin code.

Source: interview 2026-11-24 R27.2

#### Scenario: Two tickets are added at once
- **WHEN** two sessions add a local ticket at the same moment
- **THEN** the two tickets get different numbers
- **AND** neither ticket file overwrites the other

### Requirement: H-018 Ticket text is treated as untrusted data
Ticket text from the tracker SHALL reach a session only inside a fence that marks it as untrusted data: requirements to satisfy, not instructions to the session. This covers the description and comment text. Text inside the fence MUST NOT change the session's rules.

Source: decided context CTX-untrusted-fence (already in the harness and staying; covers ticket bodies); the extension to comment text is an agent decision, design.md D37-INTAKE-1

#### Scenario: Comment text is fenced too
- **WHEN** ticket comment text is passed on to a session
- **THEN** it arrives inside the same untrusted fence as the description

#### Scenario: A ticket contains instructions aimed at the agent
- **WHEN** a ticket body says to ignore the harness rules and push to main
- **THEN** the session receives that text inside the untrusted fence
- **AND** the session's rules stay unchanged

### Requirement: H-019 Ticket changes accepted only through comments and watched while work runs
While work on a ticket is in progress, the harness SHALL watch the ticket for changes. Changes SHALL be accepted only through comments, so the harness always knows who added what. The watch mechanism is an agent decision on the owner's delegation; see design.md D9.

Source: interview 2026-11-24 R6.1, R6.2; D9
OPEN: see design.md OPEN-INTAKE-3

#### Scenario: A change arrives as a comment
- **WHEN** a person adds a comment with a change to a ticket that is in progress
- **THEN** the harness detects the comment while the work runs
- **AND** it knows who wrote it

### Requirement: H-020 The change author's write access decides the path
The harness SHALL check the write access of the person who added a change. A change from a person with write access or higher SHALL be able to go into the current work at once, if the current harness settings allow it.

Source: interview 2026-11-24 R6.3, R6.4

#### Scenario: A writer adds a change
- **WHEN** a person with write access comments a change on a ticket in progress and the settings allow changes into running work
- **THEN** the change goes into the current work

#### Scenario: Settings do not allow changes into running work
- **WHEN** a writer comments a change and the settings do not allow changes into running work
- **THEN** the change does not enter the current work
- **AND** the harness follows the configured reaction

### Requirement: H-021 A non-writer's change becomes a linked new ticket
A change from a person without write access SHALL become a new ticket that links to the source comment on the earlier ticket. The new ticket SHALL go through normal intake: a writer validates it, and at pickup it passes the readiness check. If its description is sufficient, it MAY start at once; if not, clarifying questions are asked. Its starting state is an agent decision; see design.md D37-INTAKE-2.

Source: interview 2026-11-24 R6.5, R6.6; D9; D37-INTAKE-2

#### Scenario: A non-writer comments a change
- **WHEN** a person without write access comments a change on a ticket in progress
- **THEN** the harness creates a new ticket that links to that comment
- **AND** the running work does not change

#### Scenario: The new ticket is unclear
- **WHEN** a writer has validated the new ticket and it fails the readiness check
- **THEN** the harness asks clarifying questions before work starts

### Requirement: H-022 Configurable reaction to changes, set at launch or per comment
The reaction to ticket changes SHALL be configurable at launch, so people get the result they expect. The author of a change SHALL also be able to choose its reaction. Supported reactions SHALL include a new ticket once work is finished or past a set stage, and a return to execution from any status, including the last. Default: agent decision on the owner's delegation, design.md D9.

Source: interview 2026-11-24 R6.7, R6.8; D9
OPEN: see design.md OPEN-INTAKE-2

#### Scenario: A change arrives in a late step
- **WHEN** a writer comments a change while the ticket is in its last execution step and the configured reaction allows it
- **THEN** the ticket returns to execution

#### Scenario: The author chooses the reaction
- **WHEN** a writer comments a change and chooses that it becomes a new ticket
- **THEN** the harness creates a new linked ticket instead of changing the running work

### Requirement: H-023 An accepted change is delivered to the worker as a note
A change that goes into the current work SHALL be passed to the active worker session as a note. When the note is delivered is an agent decision; see design.md D37-INTAKE-3.

Source: interview 2026-11-24 R6.9; D37-INTAKE-3

#### Scenario: A writer's change is accepted
- **WHEN** a writer's change is accepted into the current work
- **THEN** the active worker session receives the change as a note
