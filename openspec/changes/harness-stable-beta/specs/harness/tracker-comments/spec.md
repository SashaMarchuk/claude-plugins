## ADDED Requirements

### Requirement: H-024 Every report is a new comment; no comment is edited or deleted
Every role SHALL report on a ticket by adding a new comment. The harness MUST NOT edit or overwrite an earlier comment, including its own. The harness MUST NOT delete an earlier comment either; this ban comes from design.md D13. The fix that replaced "edit the last comment" with "add a new comment" SHALL be part of the plugin source, not only of an installed copy.

Source: interview 2026-11-24 R10.1, R27.1; D13 (no deletion)

#### Scenario: Two roles report on the same ticket
- **WHEN** a worker posts its hand-off and a validator later posts its verdict on the same ticket
- **THEN** the ticket shows two separate comments
- **AND** the worker's hand-off is unchanged

#### Scenario: A role reports twice
- **WHEN** the same role reports twice on one ticket
- **THEN** the second report is a new comment and the first report stays as it was

### Requirement: H-025 One documented comment format
The harness SHALL write every comment in one documented format. The owner delegated the format to the agent. The format is set in design.md D13, which adopts the owner's stated lean (R10.5): new comments only, no rewritten history, no denormalised state that needs syncing, and a simpler but more reliable system over a richer one.

Source: interview 2026-11-24 R10.5; D13

#### Scenario: Current state is not kept in a comment
- **WHEN** a ticket's state changes
- **THEN** the harness records the change in the ticket's state
- **AND** it does not update a pinned or summary comment to match

#### Scenario: Harness tells its own comments from human replies
- **WHEN** the harness reads a ticket's comments after a restart
- **THEN** it tells which comments it wrote and which a human wrote, from the comment's account and the documented machine line, as set in design.md D13
- **AND** a comment with a machine line from any other account counts as a human comment

### Requirement: H-026 Status-change comments are optional and are always new comments
When the harness posts a status-change comment, it SHALL post it as a new comment. Such a comment is allowed and useful for audit, but not mandatory, because the tracker's own log already records the change. Whether to post it, and its content, are delegated to the agent; default: design.md D5 (change, reason, next action). The comment SHOULD name the role or system that set the status (the owner's nice-to-have).

Source: interview 2026-11-24 R4.7, R4.8; D5

#### Scenario: Ticket moved to needs-review
- **WHEN** the harness moves a ticket from ready to needs-review because the person who set ready has no confirmed write access
- **THEN** it adds a new comment
- **AND** per design.md D5, the comment names the change, gives that reason, and says what a person with write access must do next

#### Scenario: Change already clear from the tracker log
- **WHEN** a status change needs no reason or next action beyond what the tracker log shows
- **THEN** the harness MAY skip the status-change comment, as set in design.md D5

### Requirement: H-027 The configured tracker is the source of truth; nothing is duplicated into another tracker
The configured tracker SHALL record all statuses and history and SHALL be the source of truth. The tracker MUST be configurable; GitHub is the default. With another tracker, the harness MUST NOT duplicate tickets, statuses or comments into GitHub. Notification channels are optional additions that mirror tracker questions and events; for answers they carry back, the tracker stays the source of truth.

Source: interview 2026-11-24 R10.6, R28.2, R29.2, R29.3, R29.4

#### Scenario: Another tracker is configured
- **WHEN** a project uses ClickUp as its tracker
- **THEN** the harness writes statuses, questions and reports to ClickUp only
- **AND** nothing about the ticket appears in GitHub issues

#### Scenario: A channel and the tracker disagree
- **WHEN** a channel message and the tracker show different information about a ticket
- **THEN** the harness acts on what the tracker shows

### Requirement: H-028 Ticket states and step records let a run resume from real progress
Each ticket's state and its record of finished steps SHALL be kept in the tracker, so the harness can resume after a failure. On return, it SHALL read each ticket's state, see which steps are done, and move the ticket to the next step or status. The owner delegated the state set, step record and step-result check to best-practice research for software factories; the default is in design.md D2.

Source: interview 2026-11-24 R1.9, R20.12; D2

#### Scenario: Resume after a crash mid-ticket
- **WHEN** the harness restarts after a crash and a ticket's records show its execution step is done
- **THEN** the harness moves that ticket to the next step instead of repeating execution

#### Scenario: Recorded step has no real result
- **WHEN** the records name a step as done but its result does not exist
- **THEN** the harness repeats that step, as set in design.md D2

### Requirement: H-029 Statuses, comments and descriptions are standardised across flows
The harness SHALL use one standard set of ticket statuses and one standard form for the comments and descriptions it writes, whichever flow a project uses. Each flow SHALL describe what it writes to the ticket, within that standard.

Source: interview 2026-11-24 R16.3 (including the confirmed restatement of item 16); D2 (step names)

#### Scenario: Two projects with different flows
- **WHEN** one project uses a GSD flow and another uses a custom flow
- **THEN** both projects' tickets show the same status names and the same comment form

#### Scenario: A flow defines its own steps
- **WHEN** a flow names its own steps
- **THEN** the step names come from the flow, as set in design.md D2
- **AND** the statuses and comment form stay standard

### Requirement: H-030 Only the new state label remains after every state change
Every state change SHALL remove the old state labels, so only the new state label remains on the ticket (one at a time: design.md D2). In a tracker without labels, the same rule SHALL apply to the status the harness uses for state (design.md D1, D2). State names and their prefix are the agent's choice and stay configurable; default: design.md D2.

Source: interview 2026-11-24 R10.2; D1, D2

#### Scenario: Done ticket keeps no old label
- **WHEN** a ticket that was blocked, then in progress, moves to done
- **THEN** the ticket carries only the done state label

#### Scenario: Ticket moves to needs-review
- **WHEN** the harness moves a ready ticket to needs-review
- **THEN** the ready label is removed
- **AND** the ticket carries only the needs-review state label

### Requirement: H-031 Unblock command, usable only by people with write access
The harness SHALL provide a command that returns a blocked ticket to ready, removing the blocked state as it does. Only a person with write access to the repository, or higher, MAY unblock a ticket; a request from anyone else, or with unconfirmed access, MUST NOT unblock it. Unblock and label-cleanup tests: build-time rule R10.3, design.md Build-time rules, tasks.md 13.2.

Source: interview 2026-11-24 R10.2, R10.4, R4.3
OPEN: see design.md OPEN-10

#### Scenario: A writer unblocks a ticket
- **WHEN** a person with write access uses the unblock command on a blocked ticket
- **THEN** the ticket moves to ready and carries no blocked label

#### Scenario: A person without write access tries to unblock
- **WHEN** a person without write access uses the unblock command
- **THEN** the ticket stays blocked

#### Scenario: Access cannot be confirmed
- **WHEN** a person whose access cannot be confirmed uses the unblock command
- **THEN** the ticket stays blocked

### Requirement: H-032 Questions to a human go to the ticket as numbered items, and the session closes
When a worker needs a human, or a ticket lacks detail, the harness SHALL ask in the configured tracker's comments (GitHub by default): numbered questions in one new comment, with the ticket marked as waiting for an answer. The worker's session SHALL then close while other tickets continue. Human-need pre-check: agent decision, design.md S8-11. The orchestrator decides how work resumes (R11.4, H-092).

Source: interview 2026-11-24 R11.1, R11.6, R29.1; S8-11

#### Scenario: Worker needs two answers
- **WHEN** a worker needs two answers from a human
- **THEN** the ticket gets one new comment with questions 1 and 2
- **AND** the ticket is marked as waiting for an answer
- **AND** the worker's session closes

#### Scenario: Other tickets continue
- **WHEN** one ticket is waiting for an answer and other tickets are ready
- **THEN** the harness keeps working on the other tickets

### Requirement: H-033 Only a confirmed writer's reply resumes the ticket; other replies move it to needs-review
Only a reply from a person with confirmed write access, or higher, SHALL return a waiting ticket to work. A reply from a person without write access, or whose access cannot be confirmed, SHALL change the ticket's status to needs-review and MUST NOT resume the ticket.

Source: interview 2026-11-24 R11.2, R11.3
OPEN: see design.md OPEN-11

#### Scenario: Writer answers
- **WHEN** a person with confirmed write access answers the numbered questions
- **THEN** the ticket returns to work

#### Scenario: Outside contributor answers
- **WHEN** a person without write access answers the questions
- **THEN** the ticket moves to needs-review
- **AND** no session resumes the ticket

### Requirement: H-034 Answer author identified and recorded; an explicit author field comes first
The harness SHALL identify who wrote each answer and SHALL record that author in the comment that records the answer. When a comment carries an explicit author field in its structure, that field SHALL take priority over the platform author of the comment. Only comments from the harness's own account may carry a trusted author field, as set in design.md D13.

Source: interview 2026-11-24 R29.6; D13

#### Scenario: Answer arrives through a channel
- **WHEN** a person answers in a notification channel and the harness writes the answer into the tracker
- **THEN** the recorded comment names that person as the author, not the harness account

#### Scenario: Author field in a harness comment and platform author differ
- **WHEN** a comment from the harness's own account carries an author field that names one person, and the platform shows the harness account
- **THEN** the harness treats the person in the author field as the author

#### Scenario: Author field in a human comment is ignored
- **WHEN** a comment from any other account carries an author field that names a different person
- **THEN** the harness ignores the field and treats the platform author as the author, as set in design.md D13

### Requirement: H-035 Answers from unmapped authors need revalidation by a writer
An answer whose author maps to a tracker account with write access or higher SHALL be trusted. An answer whose author cannot be mapped MUST NOT be applied until a person with write access revalidates it. Until then, the ticket SHALL move to needs-review, as in H-033 (agent decision under D37, design.md D37-COMMENTS-1).

Source: interview 2026-11-24 R29.7; agent decision D37-COMMENTS-1 (from R11.2, R11.3)
OPEN: see design.md OPEN-11, OPEN-21

#### Scenario: Mapped writer answers in a channel
- **WHEN** an answer arrives from a channel author whose identity maps to a tracker account with write access
- **THEN** the harness records the answer and the ticket continues

#### Scenario: Unmapped author answers
- **WHEN** an answer arrives from a channel author who cannot be mapped to a tracker account
- **THEN** the harness records the answer with its author but does not apply it
- **AND** the ticket moves to needs-review until a person with write access revalidates the answer

#### Scenario: Unmapped author who really has write access
- **WHEN** an answer arrives from an author who cannot be mapped to a tracker account but who really has write access
- **THEN** the harness still does not apply the answer until a person with write access revalidates it
