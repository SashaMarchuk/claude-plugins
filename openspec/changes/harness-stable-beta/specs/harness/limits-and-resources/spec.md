## ADDED Requirements

### Requirement: H-104 Worker cap set before launch, per user or per project, default 1
The owner SHALL set the number of tickets that run in parallel: before a run starts, in the user configuration, or in the project configuration. The default, and the value the plugin recommends to a new user, SHALL be 1. The minimum SHALL be 1. The harness SHALL ship no maximum, because every machine differs; an owner with a stronger machine raises the cap in their own configuration.
Source: interview 2026-11-24 R21.1; owner decision 2026-11-26 (task 0.6)

#### Scenario: No cap is configured
- **WHEN** a run starts and none of the launch options, the project configuration or the user configuration sets a worker cap
- **THEN** the harness runs at most one ticket at a time

#### Scenario: The owner sets the cap before launch
- **WHEN** the owner sets a worker cap of 3 before the run starts
- **THEN** the harness uses 3 as the cap for that run

#### Scenario: The owner sets the cap for a project
- **WHEN** the project configuration sets a worker cap of 2 and nothing is set at launch
- **THEN** the harness uses 2 as the cap for runs in that project

#### Scenario: The owner raises the cap for all his projects
- **WHEN** the user configuration sets a worker cap of 5 and neither the launch options nor the project configuration set one
- **THEN** the harness uses 5 as the cap for that owner's runs

### Requirement: H-105 The worker cap is never exceeded
The harness MUST NOT run more worker sessions at once than the worker cap. A detailed check SHALL run before every worker start to prevent it. The way the check is enforced, including two starts at the same moment, is an agent decision (see design.md D26a).
Source: interview 2026-11-24 R21.2; D26a. S8-21 only rules out a free-memory check before a start.

#### Scenario: The cap is already reached
- **WHEN** the worker cap is 3, three worker sessions are running, and a fourth ticket is ready
- **THEN** the harness does not start a fourth worker, and the ticket waits until a worker slot is free

#### Scenario: Two starts race for the last slot (agent decision D26a)
- **WHEN** one slot is free and two start attempts happen at the same moment
- **THEN** only one worker starts, and the other attempt waits

### Requirement: H-106 A confirmed out-of-memory stop lowers the cap by one
When a container stops because the machine ran out of memory, and that cause is confirmed, the harness SHALL lower the worker cap by one automatically. When the cap is already 1, the harness SHALL keep the cap at 1 and restart the task. The harness MUST NOT lower the cap for a stop whose cause is not confirmed as lack of memory.
Decided: design.md D37-LIMITS-1, D37-LIMITS-2, D37-LIMITS-4, D37-LIMITS-6, D37-FLOW-8
Source: interview 2026-11-24 R21.3

#### Scenario: Confirmed out-of-memory stop with a cap above one
- **WHEN** the worker cap is 3 and a container stops, and the cause is confirmed as lack of memory
- **THEN** the cap becomes 2

#### Scenario: Confirmed out-of-memory stop at a cap of one
- **WHEN** the worker cap is 1 and a container stops, and the cause is confirmed as lack of memory
- **THEN** the cap stays at 1 and the task restarts

#### Scenario: Stop with an unconfirmed cause
- **WHEN** a container stops and the engine's check of the container runtime's own record does not say out of memory, or the record cannot be read
- **THEN** the worker cap does not change

#### Scenario: The same stop is reported twice (design.md D37-LIMITS-1)
- **WHEN** the worker cap is 3 and one confirmed out-of-memory stop is reported two times
- **THEN** the cap becomes 2, not 1

#### Scenario: The lowered cap lasts for the run only (design.md D37-LIMITS-2)
- **WHEN** a run lowered the cap from 3 to 2, the run is resumed, and later a new run starts
- **THEN** the resumed run keeps a cap of 2, the configured value is still 3, and the new run starts with a cap of 3

#### Scenario: The stopped task after the cap is lowered (design.md D37-LIMITS-4)
- **WHEN** the worker cap is 3, three workers run, and one ticket's container stops with a confirmed lack of memory
- **THEN** the cap becomes 2, the other two workers continue, and the stopped task restarts when a slot is free under the cap of 2

#### Scenario: The project config holds a check command (design.md D37-FLOW-8)
- **WHEN** the selected project config holds a non-empty command for the out-of-memory check
- **THEN** the harness refuses to start and runs no command from that config
- **AND** the message tells the person to move the command to the user config and to keep only its label in the project config

### Requirement: H-107 Per-stage and heavy-operation limits
The harness SHALL support limits per stage, such as a browser or UI check, next to the overall worker cap, and one shared limit for heavy operations. The owner left the choice of heavy operations to the orchestrator or a recommended list; as an agent decision, a default list is fixed and stage and heavy limits default to 1 (design.md D26). The orchestrator MAY extend the list but MUST NOT raise a limit.
Source: interview 2026-11-24 R21.4, R21.5; D26

#### Scenario: A running session needs a heavy or stage slot under a soft stop (design.md D37-LIFECYCLE-7)
- **WHEN** a soft stop is in force and a session that already runs asks for a heavy or stage slot to finish its step
- **THEN** the harness grants the slot under the normal limits, so the step can finish

#### Scenario: The stop state cannot be read (design.md D37-LIFECYCLE-7)
- **WHEN** a session asks for a slot of any kind and the run's stop state cannot be read
- **THEN** the harness refuses the slot

#### Scenario: A stage limit holds while tickets run in parallel
- **WHEN** the worker cap is 3, the browser stage limit is 1, and one ticket is already in a browser check
- **THEN** a second ticket that reaches the browser check waits, while other tickets continue in other stages

#### Scenario: The shared heavy-operation limit holds
- **WHEN** the heavy-operation limit is 1 and one worker is running an operation that counts as heavy
- **THEN** another worker that starts a heavy operation waits until the first one ends

#### Scenario: No stage or heavy limit is configured
- **WHEN** a project sets only the worker cap
- **THEN** the harness applies the default limits of design.md D26 (agent decision)

#### Scenario: The orchestrator extends the heavy list
- **WHEN** the orchestrator finds an operation that is not on the default list and judges it heavy
- **THEN** that operation counts as heavy, and no limit is raised

### Requirement: H-108 Resource usage is logged as history to recommend concurrency
The harness SHALL log CPU, memory and process usage during runs, and keep these records as history. From that history the harness MAY recommend values during configuration: the total number of parallel tickets and the number per stage. How a recommendation is shown is an agent decision (design.md D26b).
Source: interview 2026-11-24 R21.6; D26b; context rejected entry 4; owner message 2026-11-25 (iTerm2 incident)

#### Scenario: Usage is recorded during a run
- **WHEN** a run is in progress
- **THEN** the harness writes CPU, memory and process usage readings to its history

#### Scenario: The terminal app's load is recorded (design.md D42m)
- **WHEN** a run is active
- **THEN** every 5 minutes the harness records the terminal app's CPU use and the count of listing lines for the app's own API socket in the usage history
- **AND** when that count reaches 1,000, the harness raises one attention notice and does not quit or restart the app (H-135)

#### Scenario: Configuration with history available (agent decision D26b)
- **WHEN** the owner configures concurrency for a project that has usage history
- **THEN** the harness may show recommended values for the total and per-stage counts, and the configured values stay as the owner sets them

#### Scenario: Configuration without history (agent decision D26b)
- **WHEN** the owner configures concurrency and no usage history exists
- **THEN** the harness shows no recommended value, and the defaults apply: a total of 1, and per-stage values per design.md D26

### Requirement: H-109 Limits are read for every added account, in every window it has
The harness SHALL read the subscription limits of every account added to it, in every window the account reports: a 5-hour window, which only some subscriptions have, a weekly window and any other window present. The owner accepted the current reading method and welcomed a better or more efficient one. The reading source is an agent decision (design.md D28, S8-23).
Decided: design.md D37-LIMITS-5
Source: interview 2026-11-24 R23.1, R23.2, R23.4; D28, S8-23; owner decision 2026-11-26

#### Scenario: Direct endpoint read is opt-in
- **WHEN** the harness reads limits and the user has not opted in to the direct endpoint read
- **THEN** it uses the default source, not the current direct endpoint read, which is an opt-in fallback that is off by default (design.md D28, S8-23); the owner did not address that endpoint's policy risk

#### Scenario: Two accounts are added
- **WHEN** the harness configuration names two accounts
- **THEN** the harness reads the limits of each account

#### Scenario: An account has a 5-hour window
- **WHEN** an account reports a 5-hour window next to its weekly window
- **THEN** the harness reads and checks both windows

#### Scenario: An account has no 5-hour window
- **WHEN** an account reports a weekly window but no 5-hour window
- **THEN** the harness checks the weekly window and does not treat the missing 5-hour window as an error

#### Scenario: An account has another window
- **WHEN** an account reports a window that is neither the 5-hour nor the weekly one
- **THEN** the harness reads that window too, under the name the account reports

### Requirement: H-110 Optional per-window thresholds, set by the user, and the stop action at each
Thresholds on limit usage SHALL be optional and set by the user, one per window: 5-hour, weekly and any other window present. When switched on, the harness SHALL read them and apply the user's values. A project MAY set its own, and the project setting SHALL beat the user setting. Setup SHALL offer 90% for every window. The action at each threshold SHALL be configurable: a soft or a hard stop, and which kind.
Source: interview 2026-11-24 R23.3, R20.13; D28, D28a; owner decision 2026-11-26

#### Scenario: Thresholds are switched off
- **WHEN** neither the project settings nor the user settings switch a threshold on
- **THEN** no threshold action runs below a limit
- **AND** the wait at a limit that was hit still applies (H-114)

#### Scenario: Setup offers the default
- **WHEN** the person reaches the limits part of setup
- **THEN** setup offers a threshold of 90% for every window
- **AND** thresholds are switched on only after a yes

#### Scenario: Each window has its own threshold
- **WHEN** the user sets 80% for the 5-hour window and 90% for the weekly window, and an account reaches 80% of its 5-hour window and 85% of its weekly window
- **THEN** the action of the 5-hour threshold runs
- **AND** the weekly threshold triggers nothing

#### Scenario: A threshold triggers its configured action
- **WHEN** a project sets "weekly window at 90%, soft stop after the current step" and an account reaches 90% of its weekly window
- **THEN** the harness runs that soft stop

#### Scenario: A threshold set to a hard stop
- **WHEN** the owner's settings set "5-hour window at 95%, hard stop" and an account reaches 95% of its 5-hour window
- **THEN** the harness runs the configured hard stop variant

#### Scenario: Project and user settings both exist
- **WHEN** the user settings and the project settings both set a threshold for the same window
- **THEN** the project setting wins for runs in that project
- **AND** other projects keep the user setting

#### Scenario: A window has no threshold
- **WHEN** thresholds are set for the weekly window only and an account also reports a 5-hour window
- **THEN** no threshold action runs for the 5-hour window

### Requirement: H-111 An unreadable limit does not stop work
When a limit cannot be read, the harness SHALL continue the work. An unreadable limit MUST NOT block worker starts or ticket work. How the unreadable state is recorded and reported is an agent decision (design.md D28b).
Source: interview 2026-11-24 R23.6; D28b

#### Scenario: Limits are not yet available
- **WHEN** a session has started but no limit data exists yet for its account
- **THEN** work continues

#### Scenario: The limit source fails during a run
- **WHEN** the limit source returns an error for an account during a run
- **THEN** the harness keeps running tickets and starting workers

### Requirement: H-112 The reserve for the owner's own work is kept through the per-window thresholds
The harness SHALL let the owner keep a reserve of subscription capacity for the owner's own work, per project or per user, through the optional per-window thresholds of H-110. The reserve of a window SHALL be the part above its threshold. The harness SHALL ship no active reserve: with thresholds switched off, none is kept.
Source: interview 2026-11-24 R23.7; D29; owner decision 2026-11-26

#### Scenario: No threshold is switched on
- **WHEN** neither the project nor the user settings switch a threshold on
- **THEN** the harness keeps no reserve

#### Scenario: The offered default is accepted
- **WHEN** the person accepts 90% for every window at setup
- **THEN** the harness keeps 10% of every window as the reserve

#### Scenario: The owner sets a reserve for one project
- **WHEN** the owner sets a threshold in one project's settings
- **THEN** that project's runs keep the reserve, and other projects are not affected

### Requirement: H-113 The limit banner in the terminal is recognised
The harness MUST recognise the subscription-limit banner that the coding tool shows in a session's terminal, and this SHALL be validated in the final product check. If that is not possible before release, a prepared deferred test task is left in the build tasks (tasks.md), not the released plugin. The build session MAY start that test itself when the build account comes close to a real limit.
Source: interview 2026-11-24 R27.4; D35; owner decision 2026-11-26

#### Scenario: The builder plans around current limits
- **WHEN** the build is planned
- **THEN** the builder plans around the current limits so the banner test can happen

#### Scenario: An approaching limit starts the test
- **WHEN** the build account comes close to a real limit while the deferred test task is still open
- **THEN** the build session starts the banner test itself, and no owner start is needed

#### Scenario: A session shows the limit banner
- **WHEN** a session's terminal shows the subscription-limit banner
- **THEN** the harness recognises it as the limit banner, not as ordinary session output

#### Scenario: The banner cannot be validated before release
- **WHEN** no account reaches a limit during the final product check
- **THEN** banner recognition is recorded as not yet validated, and a prepared deferred test task is left in the build tasks

### Requirement: H-114 A hit limit waits for reset and the run continues
When a session stops because its account hit a subscription limit, the harness SHALL wait until that limit resets and then continue the work. This is existing behaviour that stays; it was decided before the interview and was not restated in it. The wait and resume mechanism is an agent decision (design.md D28c).
Source: decided context CTX-wait-for-reset; D28c

#### Scenario: A session hits the limit
- **WHEN** a session stops because its account reached a subscription limit
- **THEN** the harness waits until the reset time of that limit

#### Scenario: The limit resets (agent decision D28c)
- **WHEN** the account's limit window resets after a wait
- **THEN** the harness continues the run without the owner's action
