## ADDED Requirements

### Requirement: H-079 By default a run ends when all tickets are done
By default the harness SHALL finish the run when all of its tickets are done. Standby SHALL be off by default and SHALL be switched on by changing the configuration.
OPEN: see design.md OPEN-9
Source: interview 2026-11-24 R3.2, R20.1

#### Scenario: All tickets done, standby off
- **WHEN** standby is off and every ticket of the run is done
- **THEN** the harness ends the run and does not wait for new tickets

#### Scenario: Owner switches standby on
- **WHEN** the owner turns standby on in the configuration and every ticket of the run is done
- **THEN** the run does not end, and the harness enters standby instead

### Requirement: H-080 Opt-in standby mode: finished terminals close and only the orchestrator watches the tracker
The harness SHALL offer a standby mode. In standby, the harness SHALL close every finished terminal, and the orchestrator SHALL stay running as the only component that watches the tracker for new tickets. The context watcher SHALL keep running in standby and keep watching the orchestrator, as in H-098. The harness MUST NOT start a separate terminal or session to watch the tracker.
Source: interview 2026-11-24 R3.1, R3.3, R3.4

#### Scenario: Queue empties in standby
- **WHEN** standby is on and all tickets of the run are done
- **THEN** the finished worker terminals close, the orchestrator keeps running and checks the tracker for new tickets, and the context watcher keeps running and watches the orchestrator

#### Scenario: New ticket appears in standby
- **WHEN** the orchestrator is in standby and a new ready ticket appears in the tracker
- **THEN** the orchestrator picks it up and starts work on it

#### Scenario: No extra tracker watcher
- **WHEN** the harness enters standby
- **THEN** no third terminal or session is started to watch the tracker

### Requirement: H-081 Worker sessions close when their task ends, and only what this run started is closed
A worker session SHALL close automatically when its task ends; this is the default rule for all worker sessions, not a rule of standby only. The harness SHALL close only the sessions and processes that the current run started. It SHALL target each process by its exact process ID, as in H-103 (agent decision, design.md S8-27).
Decided: design.md D37-LIFECYCLE-3 (orchestrator and context watcher)
Source: interview 2026-11-24 R3.6, R20.2, R27.5; S8-27; CTX-exact-pid

#### Scenario: Worker finishes its task
- **WHEN** a worker session finishes the task it was given
- **THEN** the harness closes that session, with or without standby

#### Scenario: Session from another run or from the owner
- **WHEN** a terminal session is open that the current run did not start
- **THEN** the harness leaves it open

#### Scenario: Worker finishes while the run goes on
- **WHEN** a worker session closes because its task ended and the run is still active
- **THEN** the orchestrator and the context watcher stay open

### Requirement: H-082 Workers stop and the orchestrator waits when only tickets on review remain
When every remaining ticket waits on review, the harness SHALL stop the worker sessions; the orchestrator and the context watcher SHALL stay and wait for a ticket to change. When standby is off and only human-blocked tickets remain (unanswered by the owner), this SHALL be configurable through `on_only_human_blocked`, default `wait` (delegated agent decision, design.md S8-20a).
Source: interview 2026-11-24 R20.3; S8-20a

#### Scenario: Only review tickets remain
- **WHEN** every remaining ticket of the run is waiting on review and the default setting applies
- **THEN** the worker sessions stop, and the orchestrator and the context watcher keep running and wait

#### Scenario: A waiting ticket changes
- **WHEN** the orchestrator is waiting and a ticket on review changes so that work can continue
- **THEN** the orchestrator starts work on that ticket again

### Requirement: H-083 One ticket can start out of turn at top priority
The harness SHALL let the owner start development of one specific ticket. While other work is active, the owner SHALL be able to launch a ticket out of turn, and the harness SHALL carry it to the end at the highest priority. How a ticket is marked as urgent: see design.md D3.
Source: interview 2026-11-24 R2.1, R2.2; D3

#### Scenario: Single ticket, no run active
- **WHEN** no run is active and the owner starts development of one ticket
- **THEN** the harness runs that one ticket

#### Scenario: Urgent ticket during an active run with a free slot
- **WHEN** a run is active, the owner marks a ticket as urgent, and a worker slot is free
- **THEN** the urgent ticket starts before any other queued ticket and runs to the end

### Requirement: H-084 Other tickets pause when no slot is free, soft or hard by urgency
When an urgent ticket arrives and the concurrency limit leaves no free slot, the harness SHALL pause other tickets to make room, soft or hard by the incoming ticket's urgency. A soft pause SHALL finish only the current step or the whole ticket; a hard pause SHALL stop execution at once. Which ticket pauses, the default type and how it continues: design.md D3.
Source: interview 2026-11-24 R2.3, R2.4; D3

#### Scenario: No free slot, soft pause
- **WHEN** an urgent ticket arrives, no slot is free, and a soft pause applies
- **THEN** a running ticket finishes its current step (or the whole ticket, by the chosen variant) and pauses, and the urgent ticket takes its slot

#### Scenario: No free slot, hard pause
- **WHEN** an urgent ticket arrives, no slot is free, and a hard pause applies
- **THEN** a running ticket stops at once and the urgent ticket takes its slot

### Requirement: H-085 Soft, hard and custom stop categories reused across the harness
The harness SHALL define two general stop categories, soft and hard, which may have sub-variants, plus a custom stop that passes the owner's own message (from his agreement to a restatement). Every part of the harness that stops or pauses work SHALL reuse these categories. The owner's variants are recommendations; final set: design.md D25.
Decided: design.md D37-LIFECYCLE-5
Source: interview 2026-11-24 R2.5, R20.4 (confirmed restatement), R20.9; D25

#### Scenario: Same categories in different places
- **WHEN** the harness pauses a ticket for an urgent one, or the owner stops a run
- **THEN** both use the same soft and hard stop categories

#### Scenario: Custom stop
- **WHEN** the owner stops the run with their own message
- **THEN** the harness adds that message, word for word, to the stop message of the chosen variant and sends it to every session the stop covers by the same route (design.md D37-LIFECYCLE-5)

#### Scenario: Own message with the immediate hard stop
- **WHEN** the owner chooses the immediate hard stop and gives an own message
- **THEN** the harness sends no message, writes the own message to the run ledger, says that it was not sent, and closes the sessions without delay

### Requirement: H-086 Soft stop variants, with the current step as the default
A soft stop SHALL support the variants: finish only the current step; in execution, stop once the current task's last step is done; finish the ticket fully, per ticket or for all. The default stop SHALL finish only the current step. A soft stop takes nothing new; the existing STOP file SHALL stay and trigger the default stop (agent decisions, design.md D25a, D25b).
Source: interview 2026-11-24 R20.5, R20.6; D25, D25a, D25b; proposal.md (STOP file kept for users)

#### Scenario: Default stop during execution
- **WHEN** the owner stops the run without choosing a variant and a session is in execution, with code review next
- **THEN** the session finishes execution and does not move to code review

#### Scenario: Default stop during planning or review
- **WHEN** the default stop arrives during planning or during a code review
- **THEN** planning ends at planning, and a code review finishes the review, writes its summary and ends

#### Scenario: Finish the ticket, per ticket or for all
- **WHEN** the owner chooses the "finish the ticket" soft stop for one ticket or for all tickets
- **THEN** each ticket it is set for runs to its end

#### Scenario: STOP file
- **WHEN** the STOP file is created for an active run
- **THEN** the harness applies the default soft stop, which finishes only the current step

### Requirement: H-087 Hard stop variants that may force-close sessions
A hard stop SHALL stop work at once. It MAY force-close sessions; the rule "never force-close a session" SHALL NOT apply to a hard stop. A force-close MUST target each process as in H-103 (agent decision, design.md S8-27). Final variants and forced send: design.md D25. Run state kept for recovery at an immediate hard stop: design.md S8-20b.
Decided: design.md D37-LIFECYCLE-4, D37-LIFECYCLE-6
Source: interview 2026-11-24 R20.7, R20.8; D25; S8-20b; S8-27; CTX-exact-pid

#### Scenario: Owner's recommended hard-stop variants
- **WHEN** the owner chooses a hard stop
- **THEN** the recommended variants are: an immediate total shutdown with no message; a stop message force-sent ahead of the session's queue, (feasible, see design.md D37-LIFECYCLE-4); and a stop or park prompt put in the session's queue

#### Scenario: Immediate total shutdown
- **WHEN** the owner chooses the immediate hard stop
- **THEN** the harness closes the run's sessions at once without sending them a message

#### Scenario: Hard stop by message
- **WHEN** the owner chooses a hard stop by message
- **THEN** the harness sends the stop message and, when the session has queued it, force-sends it ahead of the session's queue with the send-now key chord (design.md D37-LIFECYCLE-4); with the forced send switched off or not possible, the message waits in the queue; a session that does not park within the configured wait is handled as design.md D37-LIFECYCLE-6 states

#### Scenario: A session does not park after a hard stop message
- **WHEN** a session has not parked within the configured wait (default 120 seconds) after a hard stop by message was issued
- **THEN** the engine writes one record for that session and force-closes it by its exact process ID, and sessions that parked are closed the normal way (design.md D37-LIFECYCLE-6)

#### Scenario: Hard stop by message while the service is down
- **WHEN** the owner chooses a hard stop by message and the harness knows that the service is down
- **THEN** the harness sends no message and closes the run's sessions as in the immediate hard stop (design.md D37-LIFECYCLE-6)

### Requirement: H-088 Automatic recovery after sleep, failure or reboot; asking first is a setting
After the laptop sleeps, a failure occurs, or the machine reboots, the harness SHALL resume the last run's sessions and continue where it stopped. By default it SHALL do this without asking. A setting SHALL let the owner require permission first. After a reboot, recovery begins at the next harness start (agent decision, design.md D32).
Decided: design.md D37-LIFECYCLE-1, D37-LIFECYCLE-2, D42h, D42i
Source: interview 2026-11-24 R20.10 (confirmed restatement), R20.11; D32

#### Scenario: Wake after sleep, default setting
- **WHEN** the laptop wakes from sleep during a run and the default setting applies
- **THEN** the harness resumes the run's sessions and continues from where they stopped, without asking

#### Scenario: Recovery requires permission
- **WHEN** the setting to ask first is on and the harness restarts after a failure or a reboot
- **THEN** the harness asks the owner and resumes only after the owner allows it

#### Scenario: After a reboot (design.md D32)
- **WHEN** the machine reboots during a run and the default setting applies
- **THEN** nothing starts by itself, and the next `/harness:run` or `/harness:resume` resumes the last run without asking

#### Scenario: A session of the last run is dead (design.md D37-LIFECYCLE-1)
- **WHEN** recovery finds a session of the last run that is no longer alive
- **THEN** the harness resumes that session by its ID once if the design.md D14 conditions hold, and otherwise starts a new session with the context pack

#### Scenario: The terminal app was quit or restarted during a run (design.md D42h)
- **WHEN** the terminal app was quit or restarted during a run and some of the run's sessions are no longer alive
- **THEN** the harness reads the session registry, leaves every session whose process is alive, and resumes each other session by its recorded ID under its recorded account label (H-139)
- **AND** each resumed session has a live process within 60 seconds

#### Scenario: A live session stopped on an error after sleep (design.md D42i)
- **WHEN** the machine wakes, a session of the run is alive, and its last turn ended with an API error
- **THEN** that session gets a continue instruction with an id, through the delivery of H-101: the orchestrator sends it to a worker, and the watch script sends it to the orchestrator
- **AND** with the service reachable and the machine awake, the first goes out within 3 minutes of the wake, and it is sent at most 3 times, 2 minutes apart
- **AND** if no hook event follows, the session is handled as a hung session (H-091)

#### Scenario: The service is down or the machine sleeps again (design.md D42i)
- **WHEN** a continue instruction is due and the service is down, or the machine sleeps again before it is sent
- **THEN** nothing is sent (H-095), the count does not advance, and the instruction is due again after the next wake or when the service is back

### Requirement: H-138 The machine stays awake during a run and while an attended controlling session lives
While a run is active, the harness SHALL hold one wake assertion for the whole run, not a chain of short ones. It SHALL also hold one for an attended session that controls the harness, for as long as that session lives. Each assertion SHALL end with its process. A setting SHALL switch each one off. See design.md D42j.

Source: owner message 2026-11-25 (iTerm2 incident); D42j

#### Scenario: A long run with no input
- **WHEN** a run lasts 12 hours on mains power and nobody touches the machine
- **THEN** the machine does not go into idle sleep during the run
- **AND** one wake assertion, bound to the watch process, holds for the whole time

#### Scenario: The run ends
- **WHEN** the run ends or is stopped
- **THEN** the run's wake assertion ends with the watch process and nothing is left behind

#### Scenario: An attended controlling session between runs
- **WHEN** the owner controls the harness from an attended session, no run is active, and that session waits for a long reply
- **THEN** the machine does not go into idle sleep while that session's process lives

#### Scenario: The controlling session closes
- **WHEN** the attended controlling session ends
- **THEN** its wake assertion ends with it

#### Scenario: The machine sleeps anyway
- **WHEN** the machine sleeps for a reason a wake assertion cannot prevent, such as a closed lid
- **THEN** the recovery of H-088 applies after the wake
