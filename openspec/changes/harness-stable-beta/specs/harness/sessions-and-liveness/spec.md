## ADDED Requirements

### Requirement: H-089 Liveness from simple, low-cost hooks
The harness SHALL use simple Claude Code hooks that record what each session does, so the harness can check that the session works. The hooks SHALL stay simple, SHALL spend few credits, and SHALL keep clutter low. The concrete cost rule is an agent decision; see design.md S8-SESSIONS.
Decided: design.md D37-SESSIONS-2 (hook events), D42l (time bounds)

Source: interview 2026-11-24 R19.1; S8-SESSIONS; owner message 2026-11-25 (iTerm2 incident)

#### Scenario: A working session leaves a trace
- **WHEN** a session runs tools during its work
- **THEN** the hooks append short records of that activity to a log the harness reads
- **AND** the harness can tell from the log that the session works

#### Scenario: Hooks stay cheap
- **WHEN** the hooks run during a long session
- **THEN** they spend few credits and add little clutter, made concrete by design.md S8-SESSIONS (no model calls of their own, no text added to the session's conversation)

#### Scenario: The harness's hook is bounded in time (design.md D42l)
- **WHEN** the harness's hook script runs for an event
- **THEN** it makes no call to the terminal app and finishes within 1 second
- **AND** it is declared with a time limit of 2 seconds, so a slow run is cut off and never holds the session

#### Scenario: Another hook in the user's settings has no time limit (design.md D42l)
- **WHEN** the start check finds a hook, in the settings that the sessions will load, with no time limit or with one above the configured maximum
- **THEN** the harness names each such hook in an attention notice and records one owner action
- **AND** it does not edit the settings, and by default the run still starts

### Requirement: H-090 The orchestrator inspects a session's transcript or terminal by its recorded identifier
The orchestrator SHALL record the identifier of each terminal it launches. Besides the hook log, the orchestrator SHALL be able to read a specific session's terminal or transcript with a low-cost model to judge its status, including whether that session started other sessions. The orchestrator SHALL act on what it finds. Recording the session ID as well is an agent decision; see design.md S8-SESSIONS.

Source: interview 2026-11-24 R19.2; S8-SESSIONS; owner message 2026-11-25 (iTerm2 incident)

#### Scenario: Orchestrator checks one session
- **WHEN** the orchestrator needs to know the status of one worker session
- **THEN** it uses the recorded identifier to find that session's terminal or transcript
- **AND** a low-cost model reads it and reports the session's status

#### Scenario: A session started other sessions
- **WHEN** the transcript shows that the session started further sessions
- **THEN** the status report says that further sessions were started

#### Scenario: The registry record is kept current (design.md D42h)
- **WHEN** a session starts or its status changes
- **THEN** its registry record holds the session ID, the process ID, the terminal identifier, the account label, the folder and the status

### Requirement: H-091 The orchestrator decides how to handle a hung or stopped session
When a session stops or hangs, the orchestrator SHALL decide at run time what to do with its ticket, including whether to escalate to a human or to solve the problem itself. The harness gives the orchestrator a default order of options and a list of causes that escalate at once; this guard is an agent decision, see design.md D20.

Decided: design.md D37-SESSIONS-8 (proof that a session ended)

Source: interview 2026-11-24 R18.1; D20

#### Scenario: A session counts as ended only with proof (design.md D37-SESSIONS-8)
- **WHEN** every recorded process of a session is proven gone
- **THEN** the session reads as ended, and the run ledger records it once

#### Scenario: The end cannot be proven (design.md D37-SESSIONS-8)
- **WHEN** the record or the process table cannot be read, or a process can neither be seen nor proven gone
- **THEN** the session reads as unknown, never as ended, and a close changes nothing

#### Scenario: A quiet session is not ended (design.md D37-SESSIONS-8)
- **WHEN** a session's transcript has not changed for hours and its process is alive
- **THEN** the session reads as working, and the age of the transcript or the record is not proof of an end

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
Decided: design.md D37-SESSIONS-1

Source: interview 2026-11-24 R18.5; D21

#### Scenario: Default attempts
- **WHEN** a worker session needs recovery and the configuration sets no values
- **THEN** the harness makes up to three recovery attempts with the default waits from design.md D21

#### Scenario: Owner changes the values
- **WHEN** the owner sets a different number of attempts or different waits in the configuration
- **THEN** the harness uses the configured values

#### Scenario: Attempts run out (design default D21)
- **WHEN** all configured recovery attempts for a ticket have failed
- **THEN** following the design.md D21 default, the ticket goes to `blocked` with a reason and one comment, and the queue continues

#### Scenario: Late attempt (design.md D37-SESSIONS-1)
- **WHEN** a ticket has been blocked for 12 hours because its recovery attempts ran out, the run is still alive, and no human-stop signal exists
- **THEN** the harness makes one more attempt with a new session and the context pack, and if it fails the ticket stays blocked and nothing more is tried

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
Decided: design.md D37-SESSIONS-3

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
- **THEN** it tells the orchestrator to continue, unless the orchestrator already continued by itself (design.md D37-SESSIONS-3)

#### Scenario: The context watcher is not the monitor
- **WHEN** the outage monitor runs
- **THEN** it runs separately from the context watcher, which MUST NOT take its role

#### Scenario: No model is involved
- **WHEN** the monitor checks the service
- **THEN** it uses no model session and spends no credits

### Requirement: H-097 The orchestrator marks that it is back after recovery
When the orchestrator works again after an outage, it SHALL mark an "I am back" status, so that the outage monitor stops asking it to start. Where a deterministic check that work has resumed is possible, the harness SHALL use it. The default "back" marker is an agent decision; see design.md D22.

Source: interview 2026-11-24 R18.9; D22
Decided: design.md D37-SESSIONS-3

#### Scenario: Orchestrator resumes
- **WHEN** the orchestrator resumes work after the monitor told it to continue
- **THEN** a "back" status is recorded and the monitor stops asking it to start

#### Scenario: Orchestrator does not resume
- **WHEN** the monitor told the orchestrator to continue and no "back" status appears
- **THEN** the monitor keeps treating the orchestrator as not resumed

#### Scenario: Orchestrator continued by itself
- **WHEN** the service is back, the orchestrator's last turn did not end with an API error, and a hook event from the orchestrator arrives within the wait
- **THEN** that event is the "back" status and the monitor sends no message (design.md D37-SESSIONS-3)

### Requirement: H-098 The orchestrator and the context watcher supervise each other, and the orchestrator starts the context watcher
The orchestrator SHALL start the context watcher and SHALL restart it if it stopped. The context watcher SHALL watch the orchestrator, also in standby, and SHALL be able to trigger an orchestrator restart if something goes wrong with it. Default restart path and deterministic backstop: design.md D23. Who plays the context watcher, and both sessions down: design.md D32.
Decided: design.md D37-SESSIONS-4

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

Decided: design.md D42g (when the typed fallback may run)

Source: interview 2026-11-24 R18.10, R24.7; S8-24; owner message 2026-11-25 (iTerm2 incident)

#### Scenario: A quiet session
- **WHEN** a session is quiet and the harness wants it to act
- **THEN** the harness does not type anything into the session to wake it

#### Scenario: Suggested text in the input line
- **WHEN** an interactive session shows suggested text in its input line
- **THEN** the harness does not treat that text as text typed by the user

#### Scenario: Typing an instruction as the fallback (design S8-24)
- **WHEN** the harness delivers a real instruction through the fallback in H-101
- **THEN** the harness types the instruction onto an empty input line and confirms delivery only by a transcript entry carrying that instruction or its id, as design.md S8-24 describes

#### Scenario: The input line holds a draft (design.md D42g)
- **WHEN** the typed fallback targets a session whose input line holds text typed by the user
- **THEN** the harness types nothing, so the session receives 0 bytes, and it reports that the instruction was not delivered

#### Scenario: The session is busy (design.md D42g)
- **WHEN** the typed fallback targets a session that is in the middle of a turn
- **THEN** the harness types nothing and sends no Enter key, and the instruction waits until the session is idle
- **AND** the only exception is the stop message of a hard stop, which design.md D37-LIFECYCLE-4 sends to a busy session on purpose

#### Scenario: A dialog or a notice is open (design.md D42g)
- **WHEN** the typed fallback targets a session that shows a dialog or a notice that would take the next key
- **THEN** the harness types nothing and sends no Enter key, and it reports what it saw

#### Scenario: A trust dialog shows on the screen (design.md D37-SESSIONS-7)
- **WHEN** a session's screen shows the folder trust dialog
- **THEN** the harness does not answer it, types nothing and records one owner action

#### Scenario: The input line is checked by reading (design.md D42g)
- **WHEN** the harness checks whether a session's input line is empty
- **THEN** it reads the screen and types no test character

### Requirement: H-100 Interactive terminal sessions are the preferred mode
The harness SHALL prefer interactive terminal sessions to run workers. Other modes MAY be used only as H-102 allows.

Source: interview 2026-11-24 R24.1; D30

#### Scenario: Default worker launch
- **WHEN** the harness launches a worker and no rule selects another mode
- **THEN** the worker runs as an interactive session in a terminal

### Requirement: H-101 Instructions go as messages first, with terminal typing as the fallback
In terminal mode, the harness SHALL send instructions to a session as a message between sessions first. Only a proven failure of the message SHALL fall back to typing the instruction into the session. A message whose outcome is unknown MUST NOT be typed. iTerm2 SHALL never get typed delivery. The message mechanism, the delivery proof and the action when both fail are an agent decision; see design.md S8-24.

Decided: design.md D42b, D42g, D37-SESSIONS-6

Source: interview 2026-11-24 R24.2; S8-24

#### Scenario: Message delivered
- **WHEN** the orchestrator sends an instruction to a worker and the message is delivered
- **THEN** the harness does not type into the terminal

#### Scenario: Message fails with proof (design.md D37-SESSIONS-6)
- **WHEN** the message command could not start at all, or it exited non-zero, its process group is gone and the readable transcript has no record of the instruction ID
- **THEN** the harness types the instruction into that session, under the conditions of H-099

#### Scenario: The message outcome is unknown (design.md D37-SESSIONS-6)
- **WHEN** the message command reaches its time limit, exits by a signal, or exits 0 with no proof, or the transcript cannot be read
- **THEN** the harness types nothing and does not retry
- **AND** it records one owner action that the instruction may not have arrived

#### Scenario: The session runs in iTerm2 (design.md D37-SESSIONS-6)
- **WHEN** an instruction goes to a session whose screen is in iTerm2 and not in the session host
- **THEN** the message route is the only route, and nothing is typed, because an idle screen cannot be proven there

#### Scenario: The session runs in the session host (design.md D42b, D42g)
- **WHEN** the message between sessions fails and the session runs in the session host
- **THEN** the harness types the instruction through the session host, not through the terminal app, and only under the conditions of H-099

#### Scenario: Busy worker, unrelated output
- **WHEN** an instruction is sent to a worker that keeps producing output, but no transcript entry carries that instruction or its id
- **THEN** the harness does not count the instruction as delivered
- **AND** it types nothing unless the message failed with proof, and otherwise records one owner action (design.md D37-SESSIONS-6)

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
The harness MUST stop a process only by its exact process ID. It MUST NEVER stop processes by matching a name or a pattern. After a stop it SHALL check that the process is really gone, and SHALL report a process that is still there.
Decided: design.md D42d (the check after a stop)

Source: decided context CTX-exact-pid (the owner's standing rule; defined in design.md Context); design.md D20 hard rules; owner message 2026-11-25 (iTerm2 incident)

#### Scenario: Closing a session's process
- **WHEN** the harness stops a session's process
- **THEN** it stops only the process with the recorded exact process ID

#### Scenario: Several similar processes run
- **WHEN** other processes with a similar name or command line are running
- **THEN** the harness leaves them untouched

#### Scenario: The stop command reports success but the process lives (design.md D42d)
- **WHEN** the stop command returns success and the process with that exact process ID still exists
- **THEN** the harness does not count the session as closed
- **AND** it checks that process ID again for up to 10 seconds, and then reports the session as not closed

#### Scenario: A process does not close outside a hard stop (design.md D42d)
- **WHEN** a process is still there after the check and no hard stop is in force
- **THEN** the harness does not force-close it, because a force-close belongs to a hard stop only (H-087)

### Requirement: H-132 Every call to the terminal app has a time limit, and an app that does not answer is recorded
The harness SHALL put a hard time limit on every call it makes to the terminal app. Before a terminal action it SHALL check that the app answers. An app that does not answer in time SHALL be recorded as not answering, and the harness MUST NOT wait for it without end. The limits are an agent decision; see design.md D42a.

Source: owner message 2026-11-25 (iTerm2 incident); D42a

#### Scenario: The terminal app does not answer
- **WHEN** the terminal app takes 60 seconds to answer the check
- **THEN** the harness records "terminal app not answering" within 6 seconds
- **AND** no harness call to the app waits more than 10 seconds

#### Scenario: The terminal app answers
- **WHEN** the terminal app answers the check in time
- **THEN** the terminal action runs

#### Scenario: The machine has no ready-made timeout command
- **WHEN** the operating system ships no timeout command
- **THEN** the time limit still holds, because the harness brings its own timer (design.md D42a)

### Requirement: H-133 A session survives a terminal app that hangs, quits or restarts
On a machine that has a session host, a session that the harness starts SHALL keep running when the terminal app hangs, quits or restarts. The terminal app SHALL only show the session, so the owner keeps an interactive view (H-100). With no session host, the harness SHALL say so at start. How sessions are hosted is an agent decision; see design.md D42b.

Source: owner message 2026-11-25 (iTerm2 incident); D42b

#### Scenario: The terminal app is force-quit while a worker is busy
- **WHEN** the terminal app is force-quit while a worker session is in the middle of a turn
- **THEN** the worker keeps the same process ID and its work continues
- **AND** when the app runs again, the harness can show that session in it again

#### Scenario: The terminal app quits the normal way
- **WHEN** the terminal app quits the normal way during a run
- **THEN** the run's sessions keep running, as in the force-quit case

#### Scenario: The machine has no session host (design.md D42b)
- **WHEN** the start check finds no session host on the machine
- **THEN** the harness says once that sessions will not survive a restart of the terminal app, and the run starts with sessions directly in the terminal app
- **AND** recovery from the registry (H-088) is the only cover for those sessions

### Requirement: H-134 A run starts and continues without the terminal app
When repeated checks of H-132 fail, the terminal app counts as hung. The harness SHALL then start or continue the run in the session host with no view. It SHALL record the switch in the run ledger and SHALL raise an attention notice. It SHALL open the view only after the app answers again. The count of failed checks is an agent decision; see design.md D42c.

Source: owner message 2026-11-25 (iTerm2 incident); D42c

#### Scenario: The app is hung at run start
- **WHEN** two checks of the terminal app fail within 60 seconds at run start
- **THEN** the run starts in the session host within 15 seconds of the second failure
- **AND** the run ledger records the switch, and the attention notice names the command that shows the sessions

#### Scenario: The app hangs during a run
- **WHEN** the terminal app stops answering during a run
- **THEN** the sessions continue, and the harness reaches them through the session host

#### Scenario: The app answers again
- **WHEN** the terminal app answers again after it was hung
- **THEN** the harness may open the view, and it restarts no session to do so

#### Scenario: The app is hung and there is no session host
- **WHEN** the terminal app is hung at run start and the machine has no session host
- **THEN** the run does not start, and the message names the hung app and the missing session host

### Requirement: H-135 The terminal app is never quit or restarted, and nothing is closed under a busy session
The harness MUST NOT quit or restart the terminal app. It MUST NOT close a window or a tab when that would end a busy session. It SHALL read the status of every affected session first, refuse, and list the busy sessions. A hard stop (H-087) is the only exception, and it closes only the run's own sessions. See design.md D42d.

Source: owner message 2026-11-25 (iTerm2 incident); D42d

#### Scenario: A close would end a busy session
- **WHEN** a harness command would close a window or a tab, and a session that would end with it is busy, which means its turn is running or one of its tool calls is open
- **THEN** the command exits with a non-zero code, lists the busy sessions and closes nothing

#### Scenario: Only the view closes
- **WHEN** a harness command closes a view of a session that runs in the session host
- **THEN** the session keeps running, so the close is allowed

#### Scenario: The terminal app is hung
- **WHEN** the terminal app is hung during a run
- **THEN** the harness does not quit or restart it, and it leaves that choice to the owner

### Requirement: H-136 A session starts with a clean environment
The harness SHALL start every session with an environment built from a short allow-list plus the variables the harness sets on purpose. Nothing else SHALL pass from the launching process. The same SHALL hold for a terminal app that the harness starts. The harness SHALL check this after launch and SHALL abort a launch that fails. See design.md D42e.

Decided: design.md D37-SESSIONS-7, D61

Source: owner message 2026-11-25 (iTerm2 incident); D42e

#### Scenario: The runtime binary comes from the repository (design.md D61)
- **WHEN** the person's PATH and shell variables are their own, but the runtime binary on that PATH resolves inside the project or one of its worktrees
- **THEN** the harness uses the person's environment as given, refuses the launch and names the path of the runtime binary

#### Scenario: The person has trusted the project folder (design.md D37-SESSIONS-7)
- **WHEN** a session is launched in a worktree of the project, and the person has already trusted the project folder in the runtime
- **THEN** the harness writes the same trust for that worktree before the session starts

#### Scenario: The person has not trusted the project folder (design.md D37-SESSIONS-7)
- **WHEN** a session is launched and the project folder is not trusted in the runtime
- **THEN** the harness writes no trust, stops the launch and records one owner action

#### Scenario: The launcher runs inside another session
- **WHEN** the launcher runs from a shell inside another Claude Code session
- **THEN** the new session's process holds no variable that identifies the parent session
- **AND** the new session records its own transcript, as a session started by hand does

#### Scenario: What the environment holds
- **WHEN** a session is launched
- **THEN** its environment holds only the allow-list, the harness's session mark, the runtime profile's variables and the values of the account command (design.md D37-SESSIONS-2, D37-SESSIONS-3, D37-SESSIONS-5)

#### Scenario: The check after launch fails
- **WHEN** the new process holds a variable with the runtime's prefix that the harness did not set
- **THEN** the harness closes that new session by its exact process ID and reports the launch as failed
- **AND** the run ledger records the name of the variable and never its value

### Requirement: H-137 Typed text has a size limit, and longer text goes through a file
The harness MUST NOT type more than a set number of bytes into a terminal in one piece. It SHALL count bytes, not characters. Longer text SHALL go into a file, and the harness SHALL type a short line that tells the session to read that file. After a typed launch line it SHALL check that the session started. The limit is an agent decision; see design.md D42f.

Source: owner message 2026-11-25 (iTerm2 incident); D42f

#### Scenario: A long prompt in multi-byte text
- **WHEN** a prompt of 3,000 bytes, written in a script that needs two bytes per letter, must reach a new session
- **THEN** the harness writes the prompt to a file in the run's state folder and types one line under the limit that names the file
- **AND** the session starts and reads the whole prompt

#### Scenario: A short prompt
- **WHEN** the text is at or under the limit, counted in bytes
- **THEN** the harness may type it directly

#### Scenario: The launch line is not accepted
- **WHEN** 10 seconds after a typed launch line the runtime's process does not run on that terminal
- **THEN** the harness records "launch line not accepted", types nothing more into that terminal and treats the launch as failed

### Requirement: H-139 A session keeps the account it was first launched with
The harness SHALL record a session's account label once, at first launch, in the session registry. Every resume or reopen SHALL use that record. A resume under another account MUST be refused. A session with no record SHALL be shown as "unknown", and the harness MUST NOT guess its account. See design.md D37-SESSIONS-5 and D42k.

Source: owner message 2026-11-25 (iTerm2 incident); D37-SESSIONS-5; D42k

#### Scenario: A resume uses the record
- **WHEN** the harness resumes or reopens a session
- **THEN** it launches the session under the account label in the registry record

#### Scenario: The caller names another account
- **WHEN** the registry record holds one account label and the caller passes a different one
- **THEN** the command exits with a non-zero code, names both labels and does not resume the session

#### Scenario: A session has no record
- **WHEN** a session has no account in the registry
- **THEN** the harness lists its account as "unknown" and does not resume it by itself

#### Scenario: The configuration changes during a run
- **WHEN** the account label of a role changes in the configuration while a run is active
- **THEN** sessions that already exist keep their recorded label, and only new sessions use the new one
