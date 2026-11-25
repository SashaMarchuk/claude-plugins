## ADDED Requirements

### Requirement: H-115 Gmail, Telegram and Slack as optional channels connected through a bot or connector
The harness SHALL support Gmail, Telegram and Slack as optional notification channels set up at the start; the user MAY enable none, one, several or all three. The configured tracker stays the source of truth. Each channel SHALL connect through a bot or a connection, such as an MCP connector or a dedicated Telegram bot. The owner fixed no mechanism; default: agent decision, design.md D36.

Source: interview 2026-11-24 R28.1, R28.2, R28.3; delegated decision D36

#### Scenario: User enables two channels at setup
- **WHEN** the user enables Telegram and Slack during setup and leaves Gmail off
- **THEN** the harness records Telegram and Slack as active channels, each with its bot or connection
- **AND** the harness does not try to use Gmail

#### Scenario: No channel is configured
- **WHEN** the user enables no channel
- **THEN** the harness works through the configured tracker only
- **AND** all questions and answers stay in the tracker

#### Scenario: The project config holds a channel command (design.md D37-FLOW-8)
- **WHEN** the selected project config wires a channel through a non-empty command
- **THEN** the harness refuses to start and runs no command from that config
- **AND** the message tells the person to move the command to the user config and to keep only the channel's label in the project config

### Requirement: H-116 Questions mirrored exactly to one, several or all channels
When the harness asks a question in the configured tracker, it SHALL send the exact same question to the channels the user selected. The user MAY select one channel, several channels or all channels. A channel MUST NOT carry a question that is not in the tracker, and MUST NOT reword it.

Source: interview 2026-11-24 R28.4, R29.3

#### Scenario: Question mirrored to all channels
- **WHEN** the harness posts three clarifying questions on a ticket and the user selected all channels for questions
- **THEN** each channel receives the same three questions with the same wording and order

#### Scenario: Question mirrored to one channel
- **WHEN** the user selected only Telegram for questions
- **THEN** the question goes to the tracker and to Telegram only

### Requirement: H-117 Replies are watched and validated for sufficiency
The harness SHALL watch every channel it sent a question to for a reply, and check whether a reply answers the question well enough. If it does, and the author passes the access rules (H-033, H-035), the ticket continues. If not, the harness SHALL ask again: in the tracker first, mirrored to the selected channels. A setting SHALL limit the follow-ups.

Source: interview 2026-11-24 R28.5, R29.1, R29.3; access rules R11.2, R11.3, R29.7
Decided: design.md D37-NOTIFICATIONS-4

#### Scenario: Sufficient reply from a writer
- **WHEN** a reply in Slack fully answers the question
- **AND** the author maps to a tracker account with write access or higher
- **THEN** the harness records the answer and the ticket continues

#### Scenario: Sufficient reply from an unmapped author
- **WHEN** a reply in Slack fully answers the question
- **AND** the author cannot be mapped to a tracker account
- **THEN** the harness records the answer
- **AND** the ticket does not continue until a person with write access revalidates the answer, as set in H-035

#### Scenario: Insufficient reply
- **WHEN** a reply in Telegram answers only part of the question
- **THEN** the harness posts a follow-up question to the tracker and mirrors it to the selected channels

#### Scenario: The follow-up rounds are used up
- **WHEN** the round limit is 3 and the reply to the third follow-up question is still not enough
- **THEN** the harness asks no further question and posts one tracker comment that lists what is still missing
- **AND** the ticket stays blocked until a writer returns it to work

### Requirement: H-118 Channel answers are written back to the tracker
The harness SHALL write every answer that it accepts from a channel into the configured tracker. The tracker stays the source of truth, and everything else reads the answer from there (H-027). The harness MUST act on the answer as it is recorded in the tracker, not only as it exists in the channel.

Source: interview 2026-11-24 R28.2, R29.2, R29.4

#### Scenario: Telegram answer recorded on the ticket
- **WHEN** a user answers a question in Telegram
- **THEN** the harness adds the answer as a comment on the ticket in the configured tracker
- **AND** the ticket history shows the answer

### Requirement: H-119 The first answer read wins; later senders get a link
If answers to the same question arrive through more than one channel, the harness SHALL record only the first answer it reads. The harness MUST NOT apply any later answer. The harness SHALL tell each later sender that the answers are already recorded, give a link to the recorded answers, and say that changes must be made directly in the tracker.

Source: interview 2026-11-24 R11.5, R29.5
Decided: design.md D37-NOTIFICATIONS-5

#### Scenario: Answers arrive in two channels
- **WHEN** the harness reads an answer in Slack and, a minute later, reads another answer to the same question in Telegram
- **THEN** the harness records the Slack answer in the tracker
- **AND** the harness does not apply the Telegram answer
- **AND** the Telegram sender gets a note that answers are already recorded, with a link to them, and is told to make changes in the tracker

#### Scenario: First answer from an unmapped author, later answer from a writer
- **WHEN** the first answer read comes from an author who cannot be mapped or has no write access, and a mapped writer later answers the same question in another channel
- **THEN** the first answer stays recorded, is not applied, and the ticket is in needs-review (H-035)
- **AND** the writer's channel answer is not applied, and the writer gets the link and is told to confirm or change the answer in the tracker (design.md D37-NOTIFICATIONS-5)

### Requirement: H-120 Channels announce run events and act as a fallback contact path
The harness SHALL announce run events, such as a ticket taken into work or done, in the active channels. The channels SHALL also be a fallback (plan B) contact path, polled on an interval for replies. Event set and per-event switches: agent decision, design.md S8-28a. Channels do not create tickets in this beta: D37-NOTIFICATIONS-2.

Source: interview 2026-11-24 R28.6, R28.8; delegated decisions S8-28a, S8-28b
Decided: design.md D37-NOTIFICATIONS-2, D37-NOTIFICATIONS-6

#### Scenario: Fallback contact returns with questions
- **WHEN** the session polls the channels and finds a reply
- **THEN** it returns to the run with the related questions

#### Scenario: A channel message asks for a new task
- **WHEN** a user sends a new task in a channel
- **THEN** no ticket is created and no work starts, because ticket intake through a channel is not in this beta (design.md D37-NOTIFICATIONS-2)

#### Scenario: Ticket done is announced
- **WHEN** a ticket reaches done and the "ticket done" event is switched on
- **THEN** the harness sends an event message to the active channels

#### Scenario: Event switched off
- **WHEN** the user switched off the "ticket taken into work" event
- **THEN** the harness does not announce that event in any channel

#### Scenario: Reply picked up by polling
- **WHEN** a user replies in a channel
- **THEN** the session finds the reply at its next interval poll and acts on it

### Requirement: H-121 User-set channel priority with fallback
When more than one channel is configured, the user SHALL be able to set the priority of the channels. If a send through one channel fails, the harness SHALL try the next channel by priority, and so on to the last one. The default order when the user sets none is an agent decision; see design.md S8-28a.

Source: interview 2026-11-24 R28.2, R28.7, R29.2; delegated decision S8-28a

#### Scenario: First channel fails
- **WHEN** the priority is Telegram, then Slack, then Gmail, and the send to Telegram fails
- **THEN** the harness sends the message through Slack

#### Scenario: All channels fail
- **WHEN** the sends through all configured channels fail
- **THEN** the message still exists in the tracker, which stays the source of truth

### Requirement: H-122 Channel identity data maps authors to tracker access
A channel bot SHALL be configured with identity data, such as an email address, where the channel needs it (the owner's example: a Telegram bot). The harness SHALL use it to map a channel author, by the sender ID the channel authenticates, to a tracker account and its access level (D37-NOTIFICATIONS-1). Slack and Gmail map the same way (D37-NOTIFICATIONS-3). Trust rules: H-033, H-035.
Decided: design.md D37-NOTIFICATIONS-3

Source: interview 2026-11-24 R29.9

#### Scenario: Author mapped through identity data
- **WHEN** a Telegram bot is configured with a user's email, and that email belongs to a tracker account with write access
- **THEN** an answer from that Telegram user is mapped to that tracker account and its write access

#### Scenario: Author cannot be mapped
- **WHEN** an answer arrives from a channel user with no configured identity data
- **THEN** the harness marks the author as unmapped for the access rules

#### Scenario: Shared or ambiguous identity counts as unmapped
- **WHEN** an answer arrives from a channel sender whose mapping entry is shared by more than one person, or whose sender ID matches no single entry
- **THEN** the harness marks the author as unmapped, and the answer waits for a writer to revalidate it (H-035)

### Requirement: H-123 Connections are checked before the build, and the owner is asked for what only he can do
Before the build starts, the session SHALL check that every connection the notification channels need exists. For anything that depends on the owner, the session SHALL ask the owner for it before the build. How the check works is an agent decision; see design.md D36. The owner's example of a session given computer use for Telegram was uncertain and is not a requirement.

Source: interview 2026-11-24 R28.11; delegated decision D36

#### Scenario: A channel connection is missing
- **WHEN** Telegram is a selected channel and its bot connection is not set up
- **THEN** the session reports the missing connection to the owner before the build starts
- **AND** asks the owner for the step that only the owner can do

### Requirement: H-124 Every notification flow is checked and confirmed to work
Every notification flow MUST be checked in detail and confirmed to work. This covers mirroring a question, reading a reply, writing the answer back to the tracker, announcing an event, and falling back to the next channel.

Source: interview 2026-11-24 R28.10

#### Scenario: Flow verified before release
- **WHEN** the notification channels are prepared for release
- **THEN** each notification flow has been run and its result confirmed
- **AND** a flow that was not confirmed is reported as not working
