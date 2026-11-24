## ADDED Requirements

### Requirement: H-089 Liveness from simple, low-cost hooks
The harness SHALL use simple Claude Code hooks that record what each session does, so the harness can check that the session works. The hooks SHALL stay simple, SHALL spend few credits, and SHALL keep clutter low. The concrete cost rule is an agent decision; see design.md S8-SESSIONS.
OPEN: see design.md OPEN-SESSIONS-1

Source: interview 2026-11-24 R19.1; S8-SESSIONS

#### Scenario: A working session leaves a trace
- **WHEN** a session runs tools during its work
- **THEN** the hooks append short records of that activity to a log the harness reads
- **AND** the harness can tell from the log that the session works

#### Scenario: Hooks stay cheap
- **WHEN** the hooks run during a long session
- **THEN** they spend few credits and add little clutter, made concrete by design.md S8-SESSIONS (no model calls of their own, no text added to the session's conversation)

### Requirement: H-090 The orchestrator inspects a session's transcript or terminal by its recorded identifier
The orchestrator SHALL record the identifier of each terminal it launches. Besides the hook log, the orchestrator SHALL be able to read a specific session's terminal or transcript with a low-cost model to judge its status, including whether that session started other sessions. The orchestrator SHALL act on what it finds. Recording the session ID as well is an agent decision; see design.md S8-SESSIONS.

Source: interview 2026-11-24 R19.2; S8-SESSIONS

#### Scenario: Orchestrator checks one session
- **WHEN** the orchestrator needs to know the status of one worker session
- **THEN** it uses the recorded identifier to find that session's terminal or transcript
- **AND** a low-cost model reads it and reports the session's status

#### Scenario: A session started other sessions
- **WHEN** the transcript shows that the session started further sessions
- **THEN** the status report says that further sessions were started

### Requirement: H-091 The orchestrator decides how to handle a hung or stopped session
When a session stops or hangs, the orchestrator SHALL decide at run time what to do with its ticket, including whether to escalate to a human or to solve the problem itself. The harness gives the orchestrator a default order of options and a list of causes that escalate at once; this guard is an agent decision, see design.md D20.

Source: interview 2026-11-24 R18.1; D20

#### Scenario: A session stopped and the cause needs no human
- **WHEN** a worker session stops and the orchestrator finds no cause that needs a human
- **THEN** the orchestrator chooses a recovery step for the ticket itself

#### Scenario: A session hangs on something only a human can solve (design default D20)
- **WHEN** a worker session waits on something only a human can provide
- **THEN** following the design.md D20 default, the orchestrator escalates the ticket to a human instead of retrying it

### Requirement: H-092 Resume the same session by ID first, then a new session with full context
To recover or resume a ticket's work, the orchestrator SHALL first try to reopen the same session by ID in the existing terminal, keeping the cache. If that fails, it SHALL start a new session; a fresh terminal is last (the owner's order, R18.2). A new session MUST get all the context it needs to continue the ticket. The orchestrator picks the step at run time (conditions, context pack: design.md D14).

Source: interview 2026-11-24 R18.2, R18.3, R11.4; D14

#### Scenario: Same session can be reopened
- **WHEN** a session stopped abruptly and its session ID and transcript are available on this machine
- **THEN** the orchestrator reopens that session by ID in its existing terminal and continues

#### Scenario: Same session cannot be reopened
- **WHEN** the old session is on another computer, holds no usable information, or the resume fails
- **THEN** the orchestrator starts a new session and gives it all the context the ticket needs

#### Scenario: The existing terminal is gone
- **WHEN** neither the same session nor a new session can run in the existing terminal
- **THEN** the orchestrator starts the session in a fresh terminal

### Requirement: H-093 A stopped ticket restarts unless a human stopped it
When a ticket's session has stopped, the harness SHALL restart the ticket unless there is information that a human stopped it. When such information exists, the harness MUST NOT restart the ticket. The owner doubted that a human stop can always be detected, so restart is the default. The signals that count as a human stop are an agent decision; see design.md D20.

Source: interview 2026-11-24 R18.4; D20

#### Scenario: No sign of a human stop
- **WHEN** a ticket's session stopped and nothing shows that a human stopped it
- **THEN** the harness restarts the ticket so it gets done

#### Scenario: A human stopped it
- **WHEN** a ticket's session stopped and one of the human-stop signals in design.md D20 is present
- **THEN** the harness leaves the ticket stopped

### Requirement: H-094 Configurable recovery attempts
The harness SHALL make three recovery attempts for a worker session by default. The number of attempts and the waits between them SHALL be configurable. The owner gave starting guesses for the waits; the defaults that replace them are an agent decision, see design.md D21.
OPEN: see design.md OPEN-SESSIONS-2

Source: interview 2026-11-24 R18.5; D21

#### Scenario: Default attempts
- **WHEN** a worker session needs recovery and the configuration sets no values
- **THEN** the harness makes up to three recovery attempts with the default waits from design.md D21

#### Scenario: Owner changes the values
- **WHEN** the owner sets a different number of attempts or different waits in the configuration
- **THEN** the harness uses the configured values

#### Scenario: Attempts run out (design default D21)
- **WHEN** all configured recovery attempts for a ticket have failed
- **THEN** following the design.md D21 default, the ticket goes to `blocked` with a reason

### Requirement: H-095 No prompts are sent while the service is down
When the Claude Code service is down, the harness MUST NOT keep sending prompts that will fail. It SHALL wait until the service is back and then continue.

Source: interview 2026-11-24 R18.6

#### Scenario: Service outage
- **WHEN** the harness knows that the Claude Code service is down
- **THEN** it sends no prompts and waits until the service is back

#### Scenario: Service returns
- **WHEN** the service is back after an outage
- **THEN** the harness continues the run

### Requirement: H-096 A deterministic outage monitor without a model session, separate from the context watcher
Unless Claude Code resumes by itself after an outage, the harness SHALL include a deterministic outage monitor with no model session, not the context watcher. It SHALL check the service status, and the internet only if an internet drop really stops the orchestrator. It SHALL log the last value, check more often while down, and tell the orchestrator when service returns.
OPEN: see design.md OPEN-SESSIONS-3

Source: interview 2026-11-24 R18.7, R18.8; D22 (build)

#### Scenario: Owner's sketch (design D22)
- **WHEN** the monitor is designed
- **THEN** the owner's sketch is a separate terminal, a check about once an hour and about every 30 minutes after a change; he called the numbers guesses, and design.md D22 records the agent decision that departs from it

#### Scenario: Claude Code resumes by itself
- **WHEN** Claude Code has a built-in way to resume when the service returns
- **THEN** the outage monitor is not needed

#### Scenario: Orchestrator survives an internet drop
- **WHEN** the orchestrator does not really stop when the internet drops
- **THEN** the monitor's internet check is not needed

#### Scenario: Connection drops
- **WHEN** the internet connection or the service goes down during a run
- **THEN** the monitor records the change in its log and starts checking more often

#### Scenario: Service comes back
- **WHEN** the monitor sees that the service and the connection are back
- **THEN** it tells the orchestrator to continue

#### Scenario: The context watcher is not the monitor
- **WHEN** the outage monitor runs
- **THEN** it runs separately from the context watcher, which MUST NOT take its role

#### Scenario: No model is involved
- **WHEN** the monitor checks the service
- **THEN** it uses no model session and spends no credits

### Requirement: H-097 The orchestrator marks that it is back after recovery
When the orchestrator works again after an outage, it SHALL mark an "I am back" status, so that the outage monitor stops asking it to start. Where a deterministic check that work has resumed is possible, the harness SHALL use it. The default "back" marker is an agent decision; see design.md D22.

Source: interview 2026-11-24 R18.9; D22

#### Scenario: Orchestrator resumes
- **WHEN** the orchestrator resumes work after the monitor told it to continue
- **THEN** a "back" status is recorded and the monitor stops asking it to start

#### Scenario: Orchestrator does not resume
- **WHEN** the monitor told the orchestrator to continue and no "back" status appears
- **THEN** the monitor keeps treating the orchestrator as not resumed

### Requirement: H-098 The orchestrator and the context watcher supervise each other, and the orchestrator starts the context watcher
The orchestrator SHALL start the context watcher and SHALL restart it if it stopped. The context watcher SHALL watch the orchestrator, also in standby, and SHALL be able to trigger an orchestrator restart if something goes wrong with it. Default restart path and deterministic backstop: design.md D23. Who plays the context watcher, and both sessions down: design.md D32.
OPEN: see design.md OPEN-SESSIONS-4

Source: interview 2026-11-24 R3.4, R3.5, R3.8; D23, D32

#### Scenario: Run start
- **WHEN** a run starts the orchestrator
- **THEN** the orchestrator starts the context watcher

#### Scenario: Orchestrator fails
- **WHEN** the orchestrator stops or something goes wrong with it
- **THEN** the context watcher or the deterministic watch script runs the restart command from design.md D23, and the orchestrator is restarted

#### Scenario: Context watcher stops
- **WHEN** the context watcher stops
- **THEN** the orchestrator restarts it

#### Scenario: Standby
- **WHEN** the run is in standby
- **THEN** the context watcher keeps running and watching the orchestrator

### Requirement: H-099 Nothing is ever typed into a session to wake it, and text typed by the user is told apart from suggested text
The harness MUST NEVER write keystrokes, such as spaces, into a session to wake it. In interactive terminals, the harness SHALL tell text typed by the user into the input apart from text that the tool only suggests.

Source: interview 2026-11-24 R18.10, R24.7; S8-24

#### Scenario: A quiet session
- **WHEN** a session is quiet and the harness wants it to act
- **THEN** the harness does not type anything into the session to wake it

#### Scenario: Suggested text in the input line
- **WHEN** an interactive session shows suggested text in its input line
- **THEN** the harness does not treat that text as text typed by the user

#### Scenario: Typing an instruction as the fallback (design S8-24)
- **WHEN** the harness delivers a real instruction through the fallback in H-101
- **THEN** the harness types the instruction onto an empty input line and confirms delivery by the growth of the target's transcript, as design.md S8-24 describes

### Requirement: H-100 Interactive terminal sessions are the preferred mode
The harness SHALL prefer interactive terminal sessions to run workers. Other modes MAY be used only as H-102 allows.

Source: interview 2026-11-24 R24.1; D30

#### Scenario: Default worker launch
- **WHEN** the harness launches a worker and no rule selects another mode
- **THEN** the worker runs as an interactive session in a terminal

### Requirement: H-101 Instructions go as messages first, with terminal typing as the fallback
In terminal mode, the harness SHALL send instructions to a session as a message between sessions first. If that fails, it SHALL type the instruction directly into the terminal (on a Mac, through osascript). The message mechanism, the delivery proof and the action when both fail are an agent decision; see design.md S8-24.

Source: interview 2026-11-24 R24.2; S8-24

#### Scenario: Message delivered
- **WHEN** the orchestrator sends an instruction to a worker and the message is delivered
- **THEN** the harness does not type into the terminal

#### Scenario: Message fails
- **WHEN** the message between sessions fails
- **THEN** the harness types the instruction directly into that session's terminal

### Requirement: H-102 Non-interactive mode only where the rule allows; the result and the log suffice
The harness SHALL launch a session in non-interactive mode (`claude -p`) only where a documented rule allows it. The rule, including the check of whether MCP access works in that mode, is an agent decision; see design.md D30. For a session launched this way, the result and the log SHALL be enough; the owner does not need to watch it live.

Source: interview 2026-11-24 R24.3, R24.4; D30

#### Scenario: Step fits the rule
- **WHEN** a step meets the rule for non-interactive mode
- **THEN** the harness may launch it non-interactively and judges it by its result and log

#### Scenario: Step does not fit the rule
- **WHEN** a step does not meet the rule
- **THEN** the harness launches it as an interactive terminal session

### Requirement: H-103 Processes are stopped by exact PID only
The harness MUST stop a process only by its exact process ID. It MUST NEVER stop processes by matching a name or a pattern.

Source: decided context CTX-exact-pid (the owner's standing rule; defined in design.md Context); design.md D20 hard rules

#### Scenario: Closing a session's process
- **WHEN** the harness stops a session's process
- **THEN** it stops only the process with the recorded exact process ID

#### Scenario: Several similar processes run
- **WHEN** other processes with a similar name or command line are running
- **THEN** the harness leaves them untouched
